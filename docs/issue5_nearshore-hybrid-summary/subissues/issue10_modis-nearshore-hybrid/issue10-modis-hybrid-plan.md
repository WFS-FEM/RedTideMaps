# RedTideMaps issue #10: the nearshore hybrid for the MODIS months

Code plan for branch `10-modis-nearshore-hybrid` (WFS-FEM/RedTideMaps, follow-up of #8 and #11 under #5), approved and posted to #10 on 22 October 2026. Section 1 gives the question and a preview from a read-only prototype; section 2 the GitHub workflow; sections 3 to 6 the work in four steps (examine, pipeline, runs and checks, docs), with a checkpoint after the first and after the third; section 7 the verification; section 8 the run notes. Nothing in the pipeline changes before checkpoint 1.

## 1. Context

Issue #8 decided the nearshore rule `mask5` (a 5-arcmin Gulf water cell in the static VIIRS no-data mask, or within 5 km of the coastline; 136 cells, 10,227 km2; inside the set a cell takes max(satellite-clipped, hull-clipped), outside it the satellite result stands, zeros included). Issue #11 (PR #12, merged 22 October 2026) put it in the pipeline for the 155 VIIRS months behind `cfg$viirs_nearshore`. Issue #10 asks whether the months the pipeline serves from MODIS nFLH polygons need the same treatment: 123 months, 2002-07 to 2011-12 (113, 2006 has 11), 2022-12 (no VIIRS tif) and 2025-01 to 2025-09.

A read-only prototype run on 22 October 2026 from the stacks on disk (MODIS-clipped stack restricted to the 123 served months, the hull-clipped stack, the `mask5` raster of the #11 run, frozen FWC samples to 22 September 2026) says the gap exists but is smaller than in the VIIRS era:

| quantity (123 MODIS months) | VIIRS-era figure for comparison (#11) | MODIS, before -> after |
|---|---|---|
| months changed by the rule | 121 of 155 | 87 of 123 |
| water samples >= 10,000 cells/L included | 53.2% -> 95.1% | 82.4% -> 89.0% (3,736 -> 4,035 of 4,535) |
| samples > 1,000,000 cells/L included | 63.7% -> 98.5% | 88.9% -> 93.4% (393 -> 413 of 442) |
| total exposure (sum of cells/L over water cells) | 4.12e9 -> 4.54e9 (+10.2%) | 2.375e9 -> 2.429e9 (+2.3%) |
| bloom area >= 10,000 cells/L, km2 summed | +16% | 1,343,000 -> 1,371,529 (+2.1%) |
| cell-months >= 10k / 100k / 1M cells/L | 10,204 -> 11,818 / 5,633 -> 6,262 / 901 -> 973 | 17,766 -> 18,144 / 4,936 -> 5,035 / 352 -> 363 |

Why smaller: MODIS has no coastal no-data band. 132 of the 136 set cells are MODIS-positive in at least one of the 123 months, and the 2,123 water cells MODIS never marks positive in those months sit a median 230 km offshore. The 799 excluded samples >= 10,000 cells/L are mostly offshore (median 11.9 km from the coast, 39% within 5 km); 301 of them lie in the set and 299 of those are recovered. Within 5 km of the coast the included share goes 87.8% -> 98.9%, beyond 5 km 75.4% -> 76.1% (MODIS looked and saw nothing: Yao Yao's condition keeps those as they are). Months with at least 5 such samples and under half included fall from 10 to 2; the biggest gains are 2006-07 (67 -> 93 of 104 samples), 2003-02 (1 -> 24 of 41), 2003-08 (38 -> 60 of 79), 2002-08 (7 -> 27 of 47), 2003-07 (33 -> 53 of 70). The 29 all-zero MODIS months stay all-zero (no hull inside the set).

**Decisions taken 21 and 22 October 2026 (Holden):** merge PR #12 first and branch from `main`; examine first with a checkpoint on #10, then implement; use the same `mask5` set for MODIS for now (a MODIS-specific rule, given the product's different resolution, is a possible later follow-up); document the plan in #10 once settled. Standing choices carried over from #11: the PR carries code, checks and docs only (the tracked deliverables stay at the 6 October 2026 state until the #5 call, which will then cover both sensors); `cfg$fwc_refresh = FALSE` for every verification run; checkpoints with evidence; small commits split by type.

## 2. GitHub workflow

0. PR #12 merged on GitHub with a merge commit (as #4, #7 and #9); branch `10-modis-nearshore-hybrid` created from `main` (done 22 October 2026).
1. Draft PR "Nearshore hybrid for the MODIS months - closes #10" against `main`, body with the checkpoint list, opened after the first commit (GitHub needs the branch to differ from `main`).
2. Commits by type, in this order: `docs:` (this plan, the folder README skeleton and `.gitignore`), `qa:` (examine stage and outputs), `refactor:`, `feat:`, `config:`, `test:` (regress / mask5 / none stages and MD5 tables), `qa:` (compare and exposure), `docs:`.
3. **Checkpoint 1** after the examine stage: comment on #10 with the tables and figures (draft kept in `comments/issue10-examine-comment.md`, gitignored); work pauses for the go/no-go. **Checkpoint 2** after the runs: results comment on #10, PR marked ready, summary on #5 (the deliverables call then covers VIIRS and MODIS at once).

## 3. Step 1: examine (no pipeline run; checkpoint 1)

`docs/issue5_nearshore-hybrid-summary/subissues/issue10_modis-nearshore-hybrid/check_modis_hybrid_issue10.R`, stage `examine` (env `RT_QA_STAGE`, default `examine`), with `tables/`, `figures/`, `comments/`. Deterministic, about a minute, byte-identical outputs on rerun.

Built in the pattern of `docs/issue5_nearshore-hybrid-summary/subissues/issue11_nearshore-hybrid-pipeline/check_hybrid_issue11.R`, copying its helpers (`one_file`, `grd`, `read_mat`, `norm_map`, `same`, `fmt_n`, `load_samples`, `samples_of`, `area_ge`, `metrics_of`, the exposure helper, `round_cols`, `md_table`, `to_z`, `base_panel`, `draw_land`, `info_box`, `draw_map_panel`, `draw_series`, `write_pdf`). The #11 script runs its own checks at load and cannot be sourced; copying is what #11 did with #8.

Inputs (all on disk, nothing refit): the depth template; `out/5min/clipped/sdmTMB_log_stack_200207-202509_clipped_modis.grd` (275 layers; keep the 123 with `use == "modis"` in `out/5min/clipped/clipping_source.csv`, asserted 123); the hull-clipped stack; `out/5min/clipped/nearshore_mask_mask5.grd` (from the #11 `mask5` run; the stage stops with a message if it is missing); the 6 October combined stack in `docs/issue5_nearshore-hybrid-summary/subissues/issue11_nearshore-hybrid-pipeline/hoard/before/combined/` (to check that the MODIS layers equal the delivered maps); the latest `*_filtered.Rdata`; `docs/issue5_nearshore-hybrid-summary/subissues/issue6_VIIRS-zeros/tables/clip_comparison_issue6.csv` (`fit_status`, `modis_n_polys`, `n_pos_1e4_water`); `data/coastline/ne_10m_coastline_wfs.gpkg` (distances, UTM 17N, 200 m densified, as in `fn.nearshore_mask()`).

Prototype: `B` = normalised MODIS-clipped layers (NA -> 0 on water, land NA), `Hm` = normalised hull layers of the same months, `A = B; A[set, ] <- pmax(B[set, ], Hm[set, ])`.

Tables (`tables/`):

- `examine_months_issue10.csv`: 123 rows: `yrmo, year, month, fit_status, modis_n_polys, cells_changed, changed`, then before/after pairs of `fp_km2, a1e4_km2, a1e5_km2, max_cells, exposure, n_ge1e4, n_ge1e5, n_ge1e6`, and `samples_ge1e4, samples_ge1e4_in_before/after, share_before/after, samples_high, samples_high_in_before/after`.
- `examine_groups_issue10.csv`: sums and shares for all 123; the 113 months of 2002-2011; the 10 of 2022-12 and 2025; the 60 months with at least 5 water samples >= 10,000 cells/L; the 10 low-inclusion months (>= 5 samples, under half included); the 8 months with samples >= 10,000 cells/L but no cell at that level.
- `examine_annual_issue10.csv`: by year.
- `excluded_samples_issue10.csv`: one row per water sample >= 10,000 cells/L outside the MODIS footprint (799): `yrmo, lon, lat, cells, class, cell5, in_set, dist_coast_km, included_after`; plus `excluded_bands_issue10.csv` (counts within 2 / 5 / 10 km and beyond, in and out of the set, before and after).
- `modis_coverage_issue10.csv`: per set cell, the number of the 123 months in which the MODIS-clipped map is positive (the "MODIS has no coastal mask" evidence), with lon, lat, depth; and a table of never-positive water cells by distance band.

Figures (`figures/`):

- `fig1_examine_months_issue10.pdf` (PNG previews with `RT_QA_PNG_DIR`): the 12 months with the largest sample gain and the 8 no-bloom-cell months, one row each: samples | MODIS-clipped | hybrid | hull-clipped, the set outlined, count boxes (the #11 fig 1 layout).
- `fig2_examine_series_issue10.png`: 2002-2011 and a short 2022/2025 strip: bloom area >= 10,000 cells/L, exposure (linear, millions), cells >= 10k / 100k / 1M, share of samples included; before black, after purple (the #11 five-panel layout).
- `fig3_excluded_samples_issue10.png`: map of the 799 excluded samples (recovered vs not) over the set, and the distance-to-coast ECDF before/after.

`comments/examine_summary.md` (the tables in markdown, as the script writes them) and the gitignored comment draft. Checks the stage enforces: 123 months; `B` equals the 6 October combined layers of those months; `A >= B` everywhere, `A == B` outside the set; the per-month sample counts equal `n_pos_1e4_water` of the #6 table; the headline numbers of the context table (87 changed; 4,535 / 3,736 / 4,035; 2.375e9 / 2.429e9; 132 of 136 set cells positive) frozen in an `expected` list.

## 4. Step 2: pipeline (after checkpoint 1)

- **`refactor:`** move `fn.nearshore_mask()` and `fn.clip_2_hybrid()` from `scripts/process_VIIRS.R` into a new `scripts/process_hybrid.R` (sourced in `run_redtide_maps.R` after `process_MODIS.R`); README pipeline rows and the `process_VIIRS.R` header follow. No behaviour change (run 0 below proves it).
- **`feat:`** `fn.clip_2_hybrid(file_sat_clipped, file_hull_clipped, file_mask, file_depth, dir_out, source = c("viirs", "modis"), months = NULL)`: `file_viirs_clipped` becomes `file_sat_clipped`; `months` keeps only those layers (the runner passes the MODIS months not in the VIIRS stack, i.e. the months the cascade serves from MODIS); output `<prefix>_clipped_hybrid` for `viirs` (unchanged) and `<prefix>_clipped_hybrid_modis` for `modis`; the returned `months` table gains `source`; messages name the source. `make_redtide_ascii()` gains `file_hybrid_modis = NULL`: cascade `hybrid > viirs > hybrid_modis > modis > pred`; `clipping_source.csv` gains `hybrid_modis` (after `hybrid`), `hybrid_changed` is computed for both (against the VIIRS layer for `hybrid`, the MODIS layer for `hybrid_modis`), `use` gains the value `"hybrid_modis"`; a `hybrid_modis` month that is also in the VIIRS stack stops the run.
- **`config:`** `cfg$modis_nearshore = "none"` (| `"mask5"`), validated with `viirs_nearshore` after `config.local.R`; step 5 reordered to 5b VIIRS clip, 5c MODIS clip, 5d nearshore set and hybrids: the set is built once when either rule is on (`fn.nearshore_mask()` reads the VIIRS stack for the mask part, so `modis_nearshore != "none"` with `use_viirs = FALSE` stops with a message); log lines `Nearshore rule (MODIS) mask5: ...` and `Hybrid (MODIS): N of 123 MODIS-served months changed: <list>`, or `Nearshore rule (MODIS): none`; `config.local.example.R` block; the hull-flag comment covers `hybrid_modis`.
- Root `README.md`: diagram and cascade bullet (`hybrid > VIIRS > hybrid_modis > MODIS > hulls`), pipeline rows (`process_hybrid.R`), config row `modis_nearshore`, outputs tree (`*_clipped_hybrid_modis.grd`), the `clipping_source.csv` paragraph.

## 5. Step 3: runs and checks (alone on the machine; `config.local.R` keeps `cfg$fwc_refresh <- FALSE`)

Three pipeline runs of 7 to 15 min each; after each, `git checkout -- out/5min/ecospace_ascii out/5min/plots` so the tracked deliverables stay at the 6 October state.

- **Run A** (`viirs_nearshore = "mask5"`, `modis_nearshore = "none"`), stage `regress`: the 504 ASCII MD5s equal `md5_after` of `docs/issue5_nearshore-hybrid-summary/subissues/issue11_nearshore-hybrid-pipeline/tables/md5_mask5_issue11.csv` (0 differ), so the refactor and the `make_redtide_ascii()` change alter nothing; `clipping_source.csv` equals the #11 one apart from the all-FALSE `hybrid_modis` column; the log has the MODIS `none` line. Outputs copied to `hoard/before/` (combined, ascii, plots, clipping_source.csv, log).
- **Run B** (both `"mask5"`), stage `mask5`: use counts hybrid 155 / hybrid_modis 123 / pred 226; exactly the months with `hybrid_modis & hybrid_changed` differ from run A and number 87; VIIRS-hybrid and hull months byte-identical; the `_clipped_hybrid_modis` stack equals the MODIS-clipped stack outside the set and the cell-wise maximum inside it, never below it, and equals the examine prototype in every month on the 11 metrics of the #11 check; the log names the rule and the 87 months. Outputs to `hoard/after/`.
- **Run 0** (both `"none"`), the existing #11 `none` stage (`RT_QA_STAGE=none Rscript docs/issue5_nearshore-hybrid-summary/subissues/issue11_nearshore-hybrid-pipeline/check_hybrid_issue11.R`): 0 of 504 differ from the 6 October baseline. Run last so the machine ends in the baseline state.
- Stage `compare` (from the 6 October combined stack in the #11 hoard, `hoard/before` = run A and `hoard/after` = run B): the whole record as Ecospace reads it in three variants (the 6 October maps, the VIIRS hybrid, both hybrids): exposure, cell counts and the share of samples included per month, by year and by group, so the #5 call sees the full 504-month picture; per cell over the MODIS months. Figures: `fig4_record_2002-2026_issue10.png` (from the first satellite month, both sensors' eras shaded) and `fig5_cells_modis_issue10.png` (the fig 1 map palette); the MODIS-era series is fig 2 of the examine stage, which run B reproduces. `comments/compare_summary.md`. (As built on 22 October 2026; the draft plan had the exposure metrics as a separate stage and a separate MODIS-era series figure.)

## 6. Step 4: docs and closure

- Issue folder README (what changed, how to run every stage, file table, results, checks); root README (step 2); `docs/issue5_nearshore-hybrid-summary/subissues/issue8_nearshore-hybrid/issue8-nearshore-plan.md` D5 row and its "out of scope" line point to #10; one line in the #11 README.
- Checkpoint 2: results comment on #10 (draft `comments/issue10-results-comment.md`), PR ready with `Closes #10`, summary on #5: accept `mask5` for both sensors, then both defaults flip, the deliverables are regenerated once (one run with both rules on) and committed. Follow-up noted in #10: a MODIS-specific set, since the two products differ in resolution.

## 7. Verification

1. Examine stage twice: identical MD5s of the CSVs and PNGs; the `expected` assertions pass; spot-check 2003-02 by hand (1 -> 24 of 41 samples included) and one month with no hull in the set (unchanged).
2. Run A: `regress` reports 0 of 504 changed against the #11 `mask5` MD5 table. Run B: 87 changed, all `hybrid_modis`, prototype matched 123 of 123. Run 0: the #11 `none` stage passes unchanged.
3. The compare stage reruns byte-identical; the MODIS-month totals of run B in `record_groups` equal the examine stage (asserted); `git status` clean apart from the gitignored hoard.

## 8. Run notes

- R 4.5.1: `"C:/Program Files/R/R-4.5.1/bin/x64/Rscript.exe"` from the repo root; `RT_QA_STAGE=examine` needs no pipeline run; the three runs of step 3 take 7 to 15 min each, alone on the machine, with any output PDF or PNG closed in its viewer first (an open file makes `pdf()` / `png()` fail; the fix is to close it and rerun the stage).
