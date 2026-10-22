# RedTideMaps issue #15: the land-adjacent nearshore rule on the Ecospace basemap

Code plan for branch `15-test-adjacent-land-cells-hybrid` (WFS-FEM/RedTideMaps, created from main `0dd2b2b`), approved by Holden on 22 October 2026. Examine-only, like step 1 of #10: no pipeline change, no pipeline run, one check script run from the stacks on disk, a checkpoint comment on #15, then the #5 call chooses between `mask5` and this rule.

## 1. Context (the review)

**Where things stand (22 Oct 2026).** PRs #12 (#11, VIIRS mask5), #13 (#10, MODIS mask5) and #14 (#5 summary) are merged. The pipeline can apply `mask5` to both sensors behind `cfg$viirs_nearshore` / `cfg$modis_nearshore`, both default `"none"`; the tracked deliverables are still the 6 Oct 2026 maps. The last run on disk is run 0 (both `none`): `out/5min/clipped/clipping_source.csv` has 155 viirs / 123 modis / 226 pred. Holden's `config.local.R` has `fwc_refresh = FALSE` and both keys `"none"`. The #5 call (accept mask5 for both sensors, flip the defaults, regenerate, commit the 504 ASCII files) waits for this test.

**What #15 asks** (opened by Holden, 22 Oct 2026, no comments yet): define "nearshore" from the Ecospace basemap itself, not the Natural Earth coastline: a water cell that shares an edge or a corner with a land cell. In satellite months (VIIRS or MODIS) those cells take the sdmTMB projection unclipped; hull months are untouched. Two questions: (1) does the set cover the cells the VIIRS mask hides, and if not, adapt the rule; (2) what it does to the metrics: in-situ samples accounted for, total exposure, cells added at the thresholds (>=10k, >=100k, >1M cells/L).

**Facts established today (read-only):**

- The RedTideMaps template `template rasters/depth 5min 66x78.asc` is numerically the EcospaceBasemap grid `output/5min/depth/depth_5min.asc` (EcospaceBasemap commit `462de94`): same header, 1,310 NODATA cells in both, 0 NODATA mismatches, values within 0.01 (formatting and line endings differ, so MD5s differ). Land on the basemap is exactly NODATA of the depth grid (`make_WFS_basemaps.R` L68-80: ETOPO elevation > 0 is NA); the exclusion layer marks water deeper than 500 m and must not be used as land. EcospaceBasemap has `fn.build_coastal()` (`R/port_functions.R` L175-216), `terra::adjacent(directions = 8)` from the land side; the water side of the same pairs is the #15 set.
- Edge-or-corner adjacency on that grid: 202 water cells, 177 in the Gulf domain (outside the Atlantic-side box east of -82 E and north of 28.5 N), 13,311 km2. Rook adjacency: 128 in the domain; within 2 cells: 338 (25,417 km2).
- Coverage: the 177-cell set covers 78 of the 84 template cells in the static VIIRS mask and 124 of the 136 `mask5` cells; 53 of its cells are not in `mask5` (depth 1 to 24 m). The 6 mask cells missed: 13 and 14 (top grid row, 30.458 N, the land north of them is off-grid, Destin area), 333, 736, 3573, 3651 (second-row cells). Adjacent OR VIIRS static mask = 183 cells.
- The raw sdmTMB stack `out/5min/sdm/sdmTMB_log_stack_198501-202612.grd` is in cells/L (not log), 504 layers, NA on every water cell in the 170 months without a fit, positive on every water cell in fitted months (2018-10: 694 to 1.46e7). The satellite-clipped layer equals the raw layer where the satellite is positive and 0 elsewhere (checked for 2018-10), so raw >= satellite-clipped everywhere: the #15 fill never lowers a cell, and it gives the whole set a nonzero value in every fitted satellite month, samples or not. That is the main difference from `mask5`, whose hull fill is sample-supported.

**Decisions by Holden today (22 Oct 2026):**

- D1 fill: the headline variant is the issue's rule (raw sdmTMB inside the set); the same set with the `mask5` fill (max of satellite-clipped and hull-clipped) is tabulated as a comparison so the tables separate the set from the fill.
- D2 adaptation candidate: adjacent OR VIIRS static mask (183 cells), carried through the full metrics beside the plain set.
- D3 domain: the Gulf domain of `mask5`; **always exclude the Atlantic Ocean cells** (standing rule, to be saved to memory as feedback once out of plan mode).

## 2. GitHub workflow

1. Work on the existing branch; draft PR "Test the land-adjacent nearshore rule on the Ecospace basemap (#15)" against `main` after the first commit; body with the checkpoint list; "Closes #15" only when Holden says the test closes the issue.
2. Commits by type: `docs:` (this plan as `issue15-adjacent-land-plan.md`, README skeleton, folder `.gitignore`), `qa:` (the script and its outputs), `docs:` (README results, a row in `docs/README.md`, one line in the #5 summary "pending" section).
3. **Checkpoint 1** after the examine stage: comment on #15 with the coverage table, the group table and the figures (draft `comments/issue15-examine-comment.md`, gitignored); try `gh issue comment` once, on a denial hand Holden the command with the `!` prefix. Work pauses for the #5 call (mask5, the #15 rule, or the adapted rule).
4. Explain the why of each GitHub step briefly as it happens (Holden's request, 22 Oct).

## 3. Step 1: the examine stage (no pipeline run)

Folder `docs/issue15_adjacent-land-hybrid/` with `check_adjacent_hybrid_issue15.R` (stage `examine`, env `RT_QA_STAGE`, default `examine`), `tables/`, `figures/`, `comments/`, `.gitignore` (`hoard/`, `issue15-*-comment.md`, as `docs/issue10_modis-nearshore-hybrid/.gitignore`). Deterministic, no RNG, byte-identical CSVs and PNGs on rerun, 1 to 2 min.

Built by copying the helpers of `docs/issue10_modis-nearshore-hybrid/check_modis_hybrid_issue10.R` (L48-262: `.root`, `one_file`, `grd`, `read_mat`, `norm_map`, `same`, `fmt_n`, `load_samples`, `samples_of`, `area_ge`, `metrics_of`, `expo_of`, `round_cols`, `md_table`, `dist_coast_km`, `band_of`, the drawing helpers, `write_pdf`) and its `draw_record` (L775) and `draw_series` (L466); the check scripts cannot be sourced, copying is the convention. Thresholds and wording: `>=10k`, `>=100k`, `>1M cells/L`; new columns named by threshold (`share_ge10k`), never low/medium/high.

**Inputs, all on disk:** the depth template; the EcospaceBasemap depth grid (`C:/Repos/WFS-FEM/EcospaceBasemap/output/5min/depth/depth_5min.asc`, path overridable with env `RT_BASEMAP_DEPTH`; the stage stops if it is missing: the set is the basemap's by proof, and the pipeline gains no cross-repo dependency); the VIIRS stack `VIIRS/VIIRS_201201-202412.grd` (for the static mask, NA in >= 90% of the layers, as `fn.nearshore_mask()` in `scripts/process_hybrid.R` L66-71); `out/5min/clipped/` VIIRS-clipped (155 layers), MODIS-clipped (275, keep the 123 with `use == "modis"`), hull-clipped (504) and `nearshore_mask_mask5.grd`; the raw stack `out/5min/sdm/sdmTMB_log_stack_198501-202612.grd`; `out/5min/clipped/clipping_source.csv` (155 / 123 / 226 asserted); the 6 Oct combined stack in `docs/issue11_nearshore-hybrid-pipeline/hoard/before/combined/` and the run-B (both mask5) combined stack in `docs/issue10_modis-nearshore-hybrid/hoard/after/combined/`; the latest `*_filtered.Rdata`; `docs/issue6_VIIRS-zeros/tables/clip_comparison_issue6.csv` (`fit_status`, `use`, `viirs_status`, `flag_zeroed_fit`, `zeroed_material`, `n_pos_1e4_water`); `data/coastline/ne_10m_coastline_wfs.gpkg` (distances only); `docs/issue11_nearshore-hybrid-pipeline/tables/nearshore_set_issue11.csv` and `docs/issue8_nearshore-hybrid/tables/mask_cells_issue8.csv` (cross-checks: 136 and 84).

**The sets** (Gulf-domain water cells; `raster::adjacent(depth, cells = water, directions = 8, pairs = TRUE)`, keep the water cell of every pair whose neighbour is land, the mirror of `fn.build_coastal()`): `adj8` (177, the issue's rule), `adj4` and `ring2` (coverage only), `adj8_mask` = adj8 OR VIIRS static mask (183, D2). The 25 land-adjacent cells of the Atlantic box are flagged in the set table and never filled (D3).

**The variants, satellite months only** (278 = 155 VIIRS + 123 MODIS; the 226 hull months are identical in every variant and enter the record tables as context), each a normalised matrix (NA -> 0 on water, land NA):

| key | set | fill inside the set | source |
|---|---|---|---|
| `v6oct` | none | satellite-clipped (the delivered maps) | #11 hoard/before combined stack, asserted equal to the on-disk VIIRS/MODIS-clipped layers |
| `mask5` | mask5 (136) | max(satellite, hull-clipped), both sensors | #10 hoard/after combined stack, asserted equal to the recomputation |
| `adj8_sdm` (headline) | adj8 (177) | raw sdmTMB | computed: `A <- S; A[set, ] <- pmax(S[set, ], R[set, ])` (equals `R[set, ]` by the clipping relation, asserted) |
| `adj8m_sdm` | adj8_mask (183) | raw sdmTMB | computed |
| `adj8_hull` | adj8 (177) | max(satellite, hull-clipped) | computed (D1 comparison) |

**Tables** (`tables/`, `_issue15.csv` suffix):

- `set_cells`: one row per Gulf-domain water cell in any candidate set or in mask5: `cell, lon, lat, depth_m, km2, adj8, adj4, ring2, viirs_mask, mask5, adj8_mask, dist_coast_km, atlantic, n_sat_pos_months, n_hull_pos_months`.
- `set_coverage`: one row per candidate (`adj4, adj8, ring2, adj8_mask, mask5`): cells, km2, VIIRS-mask cells covered (of 84), mask5 cells covered (of 136), cells not in mask5; plus `set_missed_mask_cells` listing the mask cells each candidate misses (the 6 of adj8 with lon, lat, depth, row position).
- `examine_months`: 278 rows: `yrmo, year, month, use, fit_status, viirs_status, zeroed, headline, viirs_pos_fitted, samples_ge10k, samples_gt1M`, then per variant `exposure, n_ge10k, n_ge100k, n_gt1M, km2_ge10k, max_cells, cells_changed_vs_v6oct, in_ge10k, in_gt1M, share_ge10k`.
- `examine_groups` and `examine_annual`: sums and shares by group (all 278 satellite months; 155 VIIRS; 123 MODIS; the 58 zeroed, 16 headline and 60 VIIRS-positive fitted months of #6; months with >= 5 samples >= 10k cells/L) and by year, every variant side by side; ratios to `v6oct` and to `mask5`.
- `record_months`: all 504 months, the five variants on the #10 `record_months` columns (hull months identical by construction, asserted), so the #5 call sees the full record.
- `fill_values`: what the fills write into the set cells, by class of value (0, <=1k, 1k-10k, 10k-100k, 100k-1M, >1M cells/L) and by group, `mask5` vs `adj8_sdm` vs `adj8_hull`: shows how much of the raw fill is background-level.
- `excluded_samples` and `excluded_bands`: water samples >= 10k cells/L outside the delivered footprint in satellite months, by distance band, recovered by each variant.
- `cells_sat`: per water cell over the 278 months, cumulative exposure and cell-months >= 100k cells/L under `v6oct`, `mask5`, `adj8_sdm`, and the differences.

**Figures** (`figures/`): `fig1_sets_issue15.png` (two map panels: adj8 vs mask5, cells in both / adj8 only / mask5 only, VIIRS static mask outlined, the 6 missed cells marked; adj8_mask vs mask5), `fig2_record_2002-2026_issue15.png` (the #10 fig 4 layout from the first satellite month: exposure, cells >=10k / >=100k / >1M, share of samples included; `v6oct` black, `mask5` purple, `adj8_sdm` orange, `adj8m_sdm` dashed, clip source shaded), `fig3_months_issue15.pdf` (vector PDF, Holden's rule for grids: the 16 headline months and the 12 months where `adj8_sdm` and `mask5` differ most in exposure, one row each: samples | delivered map | mask5 | adj8_sdm | raw sdmTMB with the set shaded, count boxes; `RT_QA_PNG_DIR` previews), `fig4_cells_issue15.png` (per cell over the satellite months: mask5, adj8_sdm, difference; the #10 fig 5 palette). `comments/examine_summary.md`: the group, coverage, fill and headline tables in markdown, as the script writes them.

**Checks the stage enforces:** basemap and template agree on NODATA cell for cell (1,310) and on values within 0.01; adj8 has 177 Gulf-domain cells and no Atlantic cell is filled; the static mask has 84 template cells in the domain and `mask5` on disk has 136 (= the #11 table); adj8 covers 78 of 84 and adj8_mask 84 of 84; every variant has NA exactly on land; raw >= satellite-clipped on every water cell of every satellite month, equal where the satellite is positive; each variant >= `v6oct` everywhere and equal outside its set; `adj8_sdm` changes no month without a fit; `v6oct` and `mask5` rebuilt from the on-disk stacks equal the hoard stacks; the per-month sample counts equal `n_pos_1e4_water` of the #6 table; the `mask5` group totals equal `record_groups_issue10.csv`; group sizes 278 / 155 / 123 / 58 / 16 / 60; headline numbers frozen in an `expected` list after the first run (as #10 did), so a rerun that differs fails loudly.

## 4. Checkpoint 1 and the #5 call

Comment on #15: the answer to question 1 (coverage, the 6 missed cells, the adapted rule), the answer to question 2 (the group table: samples included, exposure, cells added at each threshold, for `mask5`, `adj8_sdm`, `adj8m_sdm`, `adj8_hull` against the delivered maps), the fill-values table (how much of the raw fill is below 10k cells/L), fig 2 and fig 3, and a plain reading: what the two rules share, where they differ, and what each means for the maps Ecospace reads. No recommendation beyond the evidence unless Holden asks. Then the planning session for the #5 call.

## 5. Step 2, only if the call picks a #15 rule (not in this PR)

Sketch, to size the follow-up: `fn.nearshore_mask()` gains `rule = "adjacent"` (from the depth template alone, `raster::adjacent`, Gulf domain) and `"adjacent_mask"` (plus the VIIRS static mask); `fn.clip_2_hybrid()` gains `fill = c("hull", "sdm")` and a `file_pred` argument for the raw stack; `cfg$viirs_nearshore` / `cfg$modis_nearshore` accept the new values and a `cfg$nearshore_fill` key; `make_redtide_ascii()` unchanged; three verification runs as #10 (none = 6 Oct byte for byte; the new rule = the examine prototype on 11 metrics; mask5 unchanged); README and config example. Then the defaults flip and the deliverables are regenerated once.

## 6. Verification

1. Run the stage twice: identical MD5s of every CSV and PNG; all assertions pass.
2. Hand spot checks: cells 13 and 14 are in the mask but not in adj8 (top row); in 2017-01 (headline) the `adj8_sdm` values inside the set equal the raw layer and outside it the delivered map; one MODIS month (2003-02) likewise; one month without a fit is unchanged in every variant.
3. `v6oct` totals equal `tables/exposure_months_issue11.csv` (before) and `mask5` totals equal `record_months_issue10.csv` (`_v10` columns), asserted.
4. `git status` clean apart from the gitignored comment draft; the tracked deliverables untouched (no pipeline run).

## 7. Run notes

- `"C:/Program Files/R/R-4.5.1/bin/x64/Rscript.exe" docs/issue15_adjacent-land-hybrid/check_adjacent_hybrid_issue15.R` from the repo root; close any output PDF or PNG in a viewer before a rerun (an open file makes `pdf()` / `png()` fail).
- Memory: the 504-layer raw stack is 21 MB in memory; the stage reads three 504-layer stacks and two short ones, well under the machine's limits; nothing else running.
