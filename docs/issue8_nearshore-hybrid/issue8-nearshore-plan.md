# RedTideMaps issue #8: nearshore samples and a VIIRS + hull hybrid

Code plan for branch `8-explore-nearshore` (WFS-FEM/RedTideMaps, sub-issue of #5), drafted 19 October 2026. Sections 1 to 3 give the question, what the VIIRS files already show, and the hypotheses; sections 4 to 6 are the work plan in three steps (diagnosis, hybrid prototype, pipeline change), each ending at a checkpoint; section 7 lists the decisions that need Holden, Dave and Yao; section 8 is the GitHub workflow; section 9 the run notes. Nothing in the pipeline changes before checkpoint 2.

## 1. Question

Issue #5 found that 58 fitted months are written as all-zero maps because the VIIRS layer of the month has no positive cell, and that even in VIIRS-positive months 41% of the water-cell samples at or above 10,000 cells/L sit outside the satellite footprint (#6, PR #7). FWC bulletins document blooms, fish kills and respiratory irritation in many of the zeroed months (`docs/issue6_VIIRS-zeros/FWC-bulletins/`).

Yao Yao (USF Optical Oceanography Lab, replies of 14 and 16 October 2026 in #5):

- nearshore pixels are masked out of the VIIRS product because of atmospheric-correction uncertainty and land adjacency, so nearshore samples with high *K. brevis* counts can be too close to land to be detected;
- keep the hierarchy VIIRS > MODIS > hulls for continuity; where VIIRS has valid observations and no detection, keep the VIIRS result rather than replace it with MODIS or hulls; a plain union of VIIRS and hull footprints is not recommended, because the two estimate bloom extent differently;
- a split of in-situ data for the nearshore band (2 to 5 km from shore) and satellite data offshore is worth trying, and would need some change to the hull method.

Dave (#5, 9 October): use buffered hulls when a fitted surface exists and VIIRS is zero, while new VIIRS maps are awaited.

So two questions, in order:

1. **Diagnosis.** Are the high-count samples VIIRS does not see in the masked nearshore band, or in cells where VIIRS has valid observations and saw nothing?
2. **Hybrid rule.** If mostly the former: what does a rule that keeps VIIRS wherever VIIRS looks, and uses the sample-based hulls only where it cannot, do to the maps, and which parameters matter?

## 2. What the VIIRS files already show (check run 19 October 2026)

A read-only check of the VIIRS stack (`VIIRS/VIIRS_201201-202412.grd`, 155 layers, 0.1 degree, 55 x 65 cells) against the 5-arcmin depth template and the filtered samples of the 6 October run (`out/5min/sdm/FWC HAB data 19800102-20260922_filtered.Rdata`). The step-1 script reproduces these numbers and asserts them.

**The no-data region is a static land-plus-coast mask, not a monthly cloud mask.** Every layer has 1,002 to 1,012 NA cells (six distinct counts over 155 months); 2017-01 has 1,004 NA, 2,571 zero and 0 positive cells, 2018-09 has 1,002 NA, 2,213 zero and 360 positive cells. Of the 1,004 NA cells of 2017-01, 912 are land in the template by nearest neighbour and 92 are water; 175 NA cells contain some template water and 97 are at least half water. No VIIRS-valid cell is wholly template land. The template depth of the NA cells that hold water has a median of 4.8 m (quartiles 2.0 and 12.7 m, maximum 24 m); the VIIRS-valid cells have a median depth of 156 m (quartiles 35 and 2,933 m, minimum 1.1 m). So the mask is, in effect, the first row of 0.1-degree cells along the coast plus the bays and estuaries: the nearshore band Yao described, readable from the files themselves.

**The masked band holds most of the in-situ record, in every abundance class.** Filtered FWC samples 2012-01 to 2024-12 by FWC abundance class (section 4.0) and by the VIIRS cell they fall in that month: masked (NA), valid with no detection (0) or valid with a detection (> 0). The 610 samples of 2022-12, which has no VIIRS tif, and 55 negative samples that sit just outside the grid box on its northern edge are left out (numbers as reproduced by the step-1 script).

| FWC class | masked | valid, zero | valid, positive | total | masked share | detected share of the valid |
|---|---|---|---|---|---|---|
| negative (0) | 49,295 | 24,766 | 2,603 | 76,664 | 64% | 10% |
| background (<= 1,000) | 2,708 | 1,217 | 530 | 4,455 | 61% | 30% |
| very low (1,000 to 10,000) | 3,054 | 817 | 835 | 4,706 | 65% | 51% |
| low (10,000 to 100,000) | 3,288 | 728 | 1,247 | 5,263 | 62% | 63% |
| medium (100,000 to 1,000,000) | 2,995 | 415 | 1,334 | 4,744 | 63% | 76% |
| high (> 1,000,000) | 1,076 | 66 | 485 | 1,627 | 66% | 88% |
| all | 62,416 | 28,009 | 7,034 | 97,459 | 64% | 20% |

Two readings. First, the mask takes the same share of every class, 61 to 66%: it is a matter of where FWC samples, not of what the samples find, so two thirds of the medium and high samples are in cells VIIRS never evaluates. Second, among the samples VIIRS does evaluate, the share in a positive cell rises steeply with abundance, from 30% of the background samples to 88% of the high ones; only 66 of the 1,627 high samples and 415 of the 4,744 medium samples sit in a valid cell that saw nothing that month. That is a first, coarse reading of H1 against H2 (section 3): the satellite sees most of what it is allowed to look at, and the problem is mostly what it is not allowed to look at. Step 1 repeats this per month and per footprint.

Of the 62,416 masked samples, 41,784 are on template water cells and 20,632 on template land (bays and estuaries):

| FWC class | masked, template water | masked, template land |
|---|---|---|
| negative | 32,690 | 16,605 |
| background | 1,884 | 824 |
| very low | 2,167 | 887 |
| low | 2,284 | 1,004 |
| medium | 2,034 | 961 |
| high | 725 | 351 |

The 41,784 masked samples on template water, 5,043 of them low or above, are the ones a nearshore rule can serve: they lie on Ecospace water cells that the current cascade writes as zero in every VIIRS month, whatever the samples say. The 20,632 on template land cannot be represented by any map, but they can still anchor a hull whose 10 km buffer reaches the adjacent water cells, as the hull path already does.

Consequences for the plan:

- "Nearshore" can be defined from the VIIRS files themselves, as the masked water cells, with no coastline data and no distance parameter. That definition is exactly "where VIIRS cannot look", which is the distinction Yao draws between no observation and a valid zero.
- A distance-to-coast definition (2, 5, 10 km, Yao's range) is still needed, to describe the width of the mask and as the alternative rule. The 1:50m Natural Earth polygons the pipeline uses for basemaps are too coarse for a 2 km band; the proposed source is the Natural Earth 1:10m coastline, downloaded once with `rnaturalearth::ne_download(scale = 10, type = "coastline", category = "physical")`, cropped to the grid box and saved in this folder (`coastline/`; decision D6).
- The all-zero months are not the only case. In every one of the 155 VIIRS months the masked band is written as zero; the 58 zeroed months are where that is most visible because nothing else survives.

## 3. Hypotheses to test in step 1

- **H1, nearshore mask.** The high-count samples outside the VIIRS footprint lie in masked cells. If true: in the 58 zeroed months most of the low, medium and high samples are in masked cells, and in the 60 VIIRS-positive fitted months most of the 41% "outside" samples are too. A nearshore rule addresses these.
- **H2, valid but not detected.** A material share of the high-count samples sit in VIIRS-valid cells whose value is 0 that month (patchiness, detection threshold, timing, clouds within the month: Yao's first reply). A nearshore rule does not address these; they stay with the #5 options (b) and (e) and the provider.
- **H3, resolution.** Samples in a VIIRS-positive 0.1-degree cell whose 5-arcmin final cell is zero (polygon and raster edge effects in `fn.clip_2_viirs()`). Expected to be small; reported for completeness.

The split between H1 and H2 is the result of step 1 and decides whether step 2 is worth doing.

## 4. Step 1: diagnosis (`docs/issue8_nearshore-hybrid/check_nearshore_issue8.R`)

One deterministic script in the pattern of `check_clipping_issue6.R`: run from the repo root, reads only what the 6 October run left on disk (filtered samples, VIIRS raw stack, VIIRS-, MODIS- and hull-clipped stacks, final stack, depth template, hull polygons, `docs/issue6_VIIRS-zeros/tables/clip_comparison_issue6.csv`), no refits, no RNG, about a minute, CSVs and PNGs byte-identical from run to run. Outputs go to `docs/issue8_nearshore-hybrid/{tables,figures,comments}`.

### 4.0 Sample classes

Every table and figure counts samples by the FWC abundance classes of the in-situ maps, with FWC's right-closed bounds, exactly as the count boxes of the #6 monthly PDF do (`class_counts()` in `check_clipping_issue6.R`): negative (0 cells/L), background (above 0 to 1,000), very low (1,000 to 10,000), low (10,000 to 100,000), medium (100,000 to 1,000,000), high (above 1,000,000). The five positive classes partition the positives, and every count of "samples VIIRS does not see" is given per class, so the masked share of the background samples is never mixed with that of the medium and high ones. Where a single threshold is needed for a map comparison, 10,000 cells/L (the first coloured bin of the pipeline PDFs, FWC "low") and 100,000 cells/L (FWC "medium") are used, as in #6.

### 4.1 Per-sample table

`tables/samples_viirs_status_issue8.csv`, one row per filtered sample of 2012-01 to 2024-12 (98,123 rows, of which 610 in 2022-12 have no VIIRS layer and carry `viirs_cell = no_layer`): `yrmo`, `lon`, `lat`, `cells`, `class` (section 4.0), `template` (water / land), `depth_m` (template), `viirs_cell` (masked / valid_zero / valid_pos, from the 0.1-degree cell that month), `viirs_freq`, `in_final_fp` (final 5-arcmin cell > 0), `in_hull_fp`, `in_modis_fp`, `dist_coast_km` (Natural Earth 1:10m coastline), `dist_valid_km` (distance to the nearest VIIRS-valid cell centre), and the month's `use` and `viirs_status` from the #6 table.

### 4.2 Mask geometry

`figures/fig1_viirs_mask.png`: the VIIRS mask over the template water cells, with the coastline; `tables/mask_geometry_issue8.csv`: for each of the 92 to 175 masked water cells its depth, distance to coast and the month(s) in which it is masked; a summary of the band width by region (Panhandle, Big Bend, Tampa Bay to Charlotte Harbor, Ten Thousand Islands) as the distance from the coastline to the nearest valid cell centre. This tells us which of Yao's 2, 5 or 10 km the mask corresponds to, and whether the 1,002 to 1,012 variation matters (expected: a few edge cells).

### 4.3 Tables

- **T1** all VIIRS-era samples: class x `viirs_cell` x `template` (the two tables of section 2, reproduced).
- **T2** the 58 zeroed months, with the 16 headline months marked: samples by class, and for each class the share in masked cells, in valid-zero cells, and on template land. Expected under H1: masked dominates in the low, medium and high classes.
- **T3** the 60 VIIRS-positive fitted months: the 3,186 samples at or above 10,000 cells/L outside the final footprint (41% in #6), decomposed by class into masked, valid-zero and valid-positive-but-final-zero (H3).
- **T4** distance to coast: quantiles of `dist_coast_km` by class and `viirs_cell`; share of the samples of each class within 2, 5 and 10 km of the coast, and the share of those that are masked.
- **T5** one row per VIIRS month (155 rows), joined to the #6 month table: counts of samples by class and `viirs_cell` (18 columns), plus the hull footprint area that falls in the masked band (what a nearshore rule could restore before any prototype is built).

`comments/nearshore_summary.md` holds T1 to T4 and the headline rows of T5 in markdown, ready to paste into #8.

### 4.4 Figures

- `fig1_viirs_mask.png` (4.2).
- `fig2_dist_coast_ecdf.png`: empirical distribution of distance to coast, one panel per FWC class (background to high), lines by `viirs_cell` (masked / valid_zero / valid_pos); a second row of panels splits the same classes by inside vs outside the final footprint.
- `fig3_headline_months.png`: the 16 headline months in the row format of the #6 monthly PDF (samples | final map | VIIRS raw with the mask hatched | hull-clipped), samples drawn with the class symbols and legend of the FWC maps (as in the #6 sample panels) and outlined by `viirs_cell`.
- `fig4_monthly_status.png`: 2012 to 2024, one stacked bar per month of the low, medium and high samples by class, in two panels (masked cells; valid cells), with the VIIRS layer status (zero / positive) marked, so the zeroed months can be read against the rest.

### 4.5 Checks the script enforces

The mask counts of section 2 (1,002 to 1,012 NA cells per layer; 2017-01: 1,004 / 2,571 / 0; 2018-09: 1,002 / 2,213 / 360); the class x `viirs_cell` table of section 2 (97,459 samples, 62,416 masked, 1,627 high of which 1,076 masked); per-month `n_pos` and the five class counts equal to the #6 tables (`clip_class_counts_issue6.csv`, `fwc_*` columns); the five positive classes partition the positives; `viirs_cell` partitions every sample; samples with `in_final_fp` are only in valid-positive cells (H3 should show the reverse is not guaranteed).

**Checkpoint 1** (posted to #8): T1 to T5, the four figures, and a one-paragraph answer to H1 vs H2. Decision on whether to proceed to the prototype and with which nearshore definition (D1) and sample threshold (D2).

## 5. Step 2: hybrid prototype (second part of the same script, gated by `RT_QA_HYBRID=1`)

Built from on-disk layers, so no sdmTMB run: for each of the 155 VIIRS months and each nearshore definition N, the hybrid map is the VIIRS-clipped layer outside N and the hull-clipped layer inside N. In the VIIRS-valid area the VIIRS result stands, including zero, which is Yao's condition and separates this rule from the full hull fallback (#6 option b) and from the union (option c).

Nearshore definitions N (5-arcmin masks, template water only):

| N | Definition | Parameter |
|---|---|---|
| `mask` | cells whose 0.1-degree VIIRS cell is NA that month | none |
| `coast2`, `coast5`, `coast10` | cells whose centre is within 2, 5, 10 km of the coastline | km |
| `mask+coast5` | union of `mask` and `coast5` (if the mask has gaps along the coast) | km |

Step 2 as run (19 October 2026) used `mask`, `coast2`, `coast5` and `coast10`; `mask+coast5` was added as `mask5` on 20 October 2026 at Holden's request after checkpoint 2, once the sets table showed that `coast5` leaves out 4 masked bay cells whose centres sit 5 to 6.3 km from the coastline (see `README.md`, Step 2).

Hull source: (i) the pipeline's monthly hulls (all positives, 75 km linkage, 10 km buffer), already on disk; (ii) hulls built from the samples at or above 10,000 cells/L only, via `fn.buffered_hulls()` on a subset (the function takes `file_filtered`, so the prototype writes a filtered copy; the pipeline version gets a `min_cells` argument in step 3).

Outputs:

- `tables/hybrid_months_issue8.csv`: one row per VIIRS month: bloom area at or above 10,000 and 100,000 cells/L for the current final map, each variant, the hull-clipped map; share of the samples of each class (low, medium, high) inside each footprint; cells changed vs current.
- `figures/fig5_hybrid_headline.png`: the 16 headline months plus 2018-01 and 2021-04 (the two VIIRS-positive months that trip `low_vs_hull` in #6) and two VIIRS-positive control months with good agreement: samples | current final | `mask` | `coast5` | hull.
- `hybrid_months_issue8.pdf`: all 155 VIIRS months, one row per month, 12 rows per page (the #6 layout), columns samples | current | `mask` | `coast5` | hull, with count boxes.
- `comments/hybrid_summary.md`: totals over the 58 zeroed months and over the 60 positive months for each variant.

**Checkpoint 2** (posted to #8; discussed with Dave and Yao at the meeting being scheduled): the rule and its parameters (D1 to D4). The #5 decision (checkpoint B there) is taken at the same time.

## 6. Step 3: pipeline implementation (after checkpoint 2)

**Implemented in issue #11 (branch `11-nearshore-hybrid-pipeline`, PR #12, 20 October 2026)** with the decided rule, not the draft below: the set is `mask5` (so no `nearshore_km` / `nearshore_min_cells` keys), inside the set the rule is the cell-wise maximum, not a replacement, and the only key is `cfg$viirs_nearshore = "none" | "mask5"` (plus `cfg$fwc_refresh` for the byte-for-byte check). Signatures as built: `fn.nearshore_mask(file_viirs, file_depth, file_coast, rule, coast_km, mask_share, coast_step_m, dir_out)` and `fn.clip_2_hybrid(file_viirs_clipped, file_hull_clipped, file_mask, file_depth, dir_out)` in `scripts/process_VIIRS.R`; the coastline lives in `data/coastline/`. Results and checks: `docs/issue11_nearshore-hybrid-pipeline/README.md`.

Behind a config key, default = today's behaviour, so an unchanged config reproduces the 6 October deliverables byte for byte.

- **Config** (`run_redtide_maps.R`, documented in `config.local.example.R`): `cfg$viirs_nearshore` = `"none"` (default) | `"mask"` | `"coast"`; `cfg$nearshore_km` (used by `"coast"`, default 5); `cfg$nearshore_min_cells` (sample threshold for the nearshore hulls, default 0 = every positive, as the hull path does now).
- **Code** (`scripts/process_VIIRS.R`): `fn.nearshore_mask(file_viirs, file_depth, rule, km, coastline)` returns one 5-arcmin raster per month (or one static raster for `"coast"`) with 1 on nearshore template-water cells; `fn.clip_2_hybrid(file_viirs_clipped, file_hull_clipped, masks, file_depth, dir_out)` writes `*_clipped_hybrid.grd`, taking the VIIRS-clipped layer where the mask is 0 and the hull-clipped layer where it is 1. `fn.clip_2_viirs()` and `fn.clip_2_hulls()` are not touched, so their outputs stay identical. `make_redtide_ascii()` gains `file_hybrid = NULL`, preferred over `file_viirs` when given; `clipping_source.csv` records `use = "hybrid"`; the run log names the rule, the parameters and the number of months whose map changed. `fn.buffered_hulls()` gains `min_cells = 0` (D2).
- **Coastline** (only if `"coast"` is chosen): the step-1 file (`docs/issue8_nearshore-hybrid/coastline/ne_10m_coastline_wfs.gpkg`, with its source and download date in the README beside it) moves to `data/coastline/` if the pipeline uses it (D6).
- **Docs:** README cascade section and pipeline table; `config.local.example.R`; `docs/issue8_nearshore-hybrid/README.md` in the #6 style (what was compared, results, how to rerun).
- **Verification:** MD5 of all 504 ASCII files before (the 6 October run) and after, with the expectation that only VIIRS months with a nearshore hull differ (no MODIS or hull month changes; no change at all with `viirs_nearshore = "none"`); before/after panels for the headline months; run time in the log.
- **Out of scope, noted for follow-up:** the MODIS nFLH months (2002-07 to 2011-12, 2025-01 to 2025-09) presumably have the same nearshore gap; `fn.clip_2_hybrid()` is written so a MODIS-clipped stack can be passed in its place later. **Done in issue #10 (October 2026):** the same set and rule behind `cfg$modis_nearshore`; examination and checks in `docs/issue10_modis-nearshore-hybrid/`.

**Checkpoint 3:** regenerated 5-arcmin deliverables, the MD5 table and the panels; PR marked ready with `Closes #8`; the #5 decision recorded in #5.

## 7. Decisions needed

| ID | Decision | Options | Recommendation (to be confirmed at checkpoint 1 or 2) |
|---|---|---|---|
| D1 | nearshore definition | `mask` (VIIRS no-data water cells) / `coast` with W km / union | `mask`, with the coast distance reported: it is VIIRS's own blind zone, needs no parameter or external data, and matches Yao's valid vs no-observation distinction; `coast` as the sensitivity case |
| D2 | which samples build the nearshore hulls | all positives (as the hull path now) / >= 10,000 / >= 100,000 cells/L | prototype with the existing hulls (all positives); show >= 10,000 as sensitivity; FWC "background" (< 1,000) is the #5 item M3 and is not changed here |
| D3 | apply in all VIIRS months or only the 89 all-zero ones | all / all-zero only | all: the rule is about where VIIRS can look, not whether it saw something; the all-zero months are where it matters most |
| D4 | the VIIRS-valid area in all-zero months | VIIRS zero stands (Yao) / hull fallback (Dave's interim, #6 option b) | VIIRS zero stands, unless step 1 shows a material H2 share; the prototype reports both so the difference is visible |
| D5 | MODIS months | in scope / follow-up | follow-up issue (#10, done October 2026) |
| D6 | coastline source if `coast` is used anywhere | Natural Earth 1:10m / NOAA GSHHG / template land edge | Natural Earth 1:10m via `rnaturalearth::ne_download()`, cropped and committed; the template edge (5 arcmin, about 9 km) is too coarse |

**Decided on 20 October 2026** (Holden, after the step-2 and step-2b results and the meeting with Yao; recorded in the #8 decision comment): D1 = `mask5`, the VIIRS no-data mask or any cell within 5 km of the coastline (`mask` and `coast10` stay in the prototype as the lower and upper bounds); D2 = the hulls as the pipeline builds them (every positive sample, no count threshold); D3 = all VIIRS months; D4 = VIIRS valid zeros stand outside the nearshore set, the hull applies inside it whether the cell is masked or valid, and the full hull fallback for all-zero months (#6 option b) is dropped, since the nearshore hybrid covers what it was for; D5 = follow-up issue; D6 = Natural Earth 1:10m, since the 5 km band needs it.

## 8. GitHub workflow and checkpoints

- Branch `8-explore-nearshore`, draft PR against `main`, small commits split by type (`docs:` this plan and the issue README; `qa:` the script and its outputs; `feat:` the pipeline functions; `config:` the keys and example; `test:` the MD5 and acceptance checks). Each checkpoint is one comment on #8 with the tables and figures, and work pauses there for Holden's reply.
- Issue 8 keeps the sub-issue label and parent #5; the #5 rule decision (checkpoint B in the #5 plan) is taken at checkpoint 2 here.
- The PR is marked ready at checkpoint 3 and closes #8; #5 closes when the regenerated deliverables are accepted.

## 9. Run notes

- R 4.5.1: `"C:/Program Files/R/R-4.5.1/bin/x64/Rscript.exe" docs/issue8_nearshore-hybrid/check_nearshore_issue8.R` from the repo root; `RT_QA_HYBRID=1` adds step 2; `RT_QA_PDF=0` skips the PDF.
- Steps 1 and 2 need no pipeline run. Step 3 reruns `run_redtide_maps.R` (about 9 minutes warm, 5-arcmin) alone on the machine; close any output PDF in Acrobat first.
- The 6 October run is the baseline for every comparison; its MD5 table is written before step 3 starts.
