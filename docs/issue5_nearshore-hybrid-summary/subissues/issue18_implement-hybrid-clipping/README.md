# Issue #18: the hybrid clipping approach in the pipeline, the regenerated deliverables, the closure of #5

Implementation, verification and the regenerated deliverables for [WFS-FEM/RedTideMaps#18](https://github.com/WFS-FEM/RedTideMaps/issues/18), the issue that closes [#5](https://github.com/WFS-FEM/RedTideMaps/issues/5) after [#6](https://github.com/WFS-FEM/RedTideMaps/issues/6), [#8](https://github.com/WFS-FEM/RedTideMaps/issues/8), [#11](https://github.com/WFS-FEM/RedTideMaps/issues/11), [#10](https://github.com/WFS-FEM/RedTideMaps/issues/10) and [#15](https://github.com/WFS-FEM/RedTideMaps/issues/15). The nearshore set decided in #15 (the union of `mask5` and the land-adjacent cells, 189 cells at 5 arcmin; `docs/issue5_nearshore-hybrid-summary/subissues/issue15_adjacent-land-hybrid/nearshore-set-method.md`) goes into the pipeline as rule `"mask5adj"`, becomes the default for both sensors, and the Ecospace deliverables are regenerated at 5 and 15 arcmin. Branch `18-implement-hybrid-clipping`, PR #19, 23 October 2026. The plan, with the decisions it rests on (D10 to D13), is `issue18-implement-hybrid-plan.md`.

**The tracked deliverables (`out/5min/ecospace_ascii/`, `out/15min/ecospace_ascii/`, and the plots beside them) are the hybrid maps since this issue**, regenerated with the FWC samples frozen at the 22 September 2026 pull and then refreshed with the samples to 21 October 2026 (only the two latest hull-served months differ between the two), and copied to the Ecospace ST drivers folder. With both keys at `"none"` the pipeline still reproduces the 6 October 2026 maps byte for byte.

Step 6 (24 October 2026, branch `18-monthly-comparison-pdf`, PR #20) adds `clip_months_hybrid_issue18.pdf`: the monthly comparison PDF of #6 redrawn from the delivered run, with the delivered hybrid map as a sixth column and the total exposure printed in every map panel.

## What changed in the pipeline

- **`fn.nearshore_mask()`** (`scripts/process_hybrid.R`): rule `"mask5adj"`, the decided set of #15. A template water cell of the Gulf domain (the Atlantic-side box east of -82 E and north of 28.5 N is always excluded) is nearshore if its 0.1-degree VIIRS cell is in the static VIIRS no-data mask (NA in at least 90% of the VIIRS layers), or if its centre lies within 5 km of the Natural Earth 1:10m coastline, or if it shares an edge or a corner with a land cell of the template (a NODATA cell of the depth grid, the land of the Ecospace basemap; `raster::adjacent(directions = 8)` from the water side, the grid borders not treated as land). The first two criteria are the `"mask5"` rule of #8, #11 and #10, whose code path is untouched; the third is computed only for `"mask5adj"`. The function returns and reports `n_adjacent_cells`; the raster is `out/<res>min/clipped/nearshore_mask_mask5adj.grd`. At 5 arcmin: 189 cells, 14,205 km2 (84 in the VIIRS mask, 132 within 5 km, 177 touching land; `mask5` is 136 cells). The rule is written out in `docs/issue5_nearshore-hybrid-summary/subissues/issue15_adjacent-land-hybrid/nearshore-set-method.md`.
- **`fn.clip_2_hybrid()`**: unchanged. Inside the set a cell takes the cell-wise maximum of the satellite-clipped and hull-clipped layers; outside it the satellite result stands, zeros included (#11, #10).
- **Config** (`run_redtide_maps.R`, `config.local.example.R`, README): `cfg$viirs_nearshore` and `cfg$modis_nearshore` accept `"none"`, `"mask5"` and `"mask5adj"`; the run-log line names the rule, the set size and, for `"mask5adj"`, the count of cells touching land. (The defaults are flipped to `"mask5adj"` in step 3 below.)

## How to run

```
# config.local.R for the verification runs (step 2): cfg$fwc_refresh <- FALSE, the two keys as named
cfg$viirs_nearshore <- "mask5adj"; cfg$modis_nearshore <- "mask5adj"    # run A, then:
RT_QA_STAGE=rule Rscript docs/issue5_nearshore-hybrid-summary/subissues/issue18_implement-hybrid-clipping/check_final_hybrid_issue18.R   # 210 files change; = the #15 prototype month by month; copy the outputs to hoard/runA/
cfg$viirs_nearshore <- "none";     cfg$modis_nearshore <- "none"        # run 0, then:
RT_QA_STAGE=none Rscript docs/issue5_nearshore-hybrid-summary/subissues/issue11_nearshore-hybrid-pipeline/check_hybrid_issue11.R         # the unchanged #11 check: the 6 Oct 2026 maps byte for byte
```

Each pipeline run takes 7 to 8 minutes alone on the machine (the first run at 15 arcmin fits every month, about 20 minutes); after a verification run, `git checkout -- out/5min/ecospace_ascii out/5min/plots` restores the tracked deliverables.

```
# step 3, the defaults flipped; config.local.R: no nearshore key, cfg$fwc_refresh <- FALSE, cfg$export_ecospace <- TRUE
Rscript run_redtide_maps.R                                                                      # the final 5-arcmin run, then:
RT_QA_STAGE=final  RT_QA_RES=5  Rscript docs/issue5_nearshore-hybrid-summary/subissues/issue18_implement-hybrid-clipping/check_final_hybrid_issue18.R   # = run A byte for byte; the export equal; copy the outputs to hoard/final5/ (with sdm/*_filtered.Rdata)
RT_QA_STAGE=record RT_QA_RES=5  Rscript docs/issue5_nearshore-hybrid-summary/subissues/issue18_implement-hybrid-clipping/check_final_hybrid_issue18.R   # the record from hoard/final5/ (RT_QA_PNG_DIR=<dir> adds PNG previews of fig 1)
RT_QA_STAGE=baseline RT_QA_RES=15 Rscript docs/issue5_nearshore-hybrid-summary/subissues/issue18_implement-hybrid-clipping/check_final_hybrid_issue18.R # before the first 15-arcmin run: MD5 of the tracked files
cfg$res <- 15L; Rscript run_redtide_maps.R                                                      # the 15-arcmin run, then:
RT_QA_STAGE=final  RT_QA_RES=15 Rscript docs/issue5_nearshore-hybrid-summary/subissues/issue18_implement-hybrid-clipping/check_final_hybrid_issue18.R   # the set and the hybrid relations at 15 arcmin; copy the outputs to hoard/final15/
# step 4, the refresh: cfg$fwc_refresh line removed (TRUE), at each resolution:
Rscript run_redtide_maps.R
RT_QA_STAGE=refresh RT_QA_RES=<5|15> Rscript docs/issue5_nearshore-hybrid-summary/subissues/issue18_implement-hybrid-clipping/check_final_hybrid_issue18.R  # only hull-served months from the first new sample month differ from hoard/final<res>/
# step 6, the monthly comparison PDF: reads the 5-arcmin run on disk (no pipeline run), 3 to 6 min
Rscript docs/issue5_nearshore-hybrid-summary/subissues/issue18_implement-hybrid-clipping/clip_months_hybrid_issue18.R   # RT_QA_QUICK=1 draws only the 8 pages holding the #6 headline months, to hoard/; RT_QA_PNG_DIR=<dir> adds PNG previews of the pages of RT_QA_PNG_YEARS
```

## Files

| File | What |
|---|---|
| `issue18-implement-hybrid-plan.md` | the plan: context and state found, the decisions of 23 Oct 2026 (D10 to D13), the GitHub workflow, the five steps, verification |
| `check_final_hybrid_issue18.R` | the check script, stages `baseline`, `rule`, `final`, `record`, `refresh` (`RT_QA_STAGE`), resolution `RT_QA_RES` |
| `tables/md5_runA_issue18.csv` | run A against the 6 Oct 2026 baseline: `yrmo, file, use, hybrid, hybrid_modis, hybrid_changed, md5_now, md5_6oct, changed_vs_6oct` |
| `tables/nearshore_set5_issue18.csv` | the 189 cells of the set raster written by run A, with the three criteria flags joined from the #15 table |
| `tables/hybrid_vs_prototype_issue18.csv` | per satellite month (278), the hybrid stacks of run A against the `union_hull` prototype of #15 on 9 metrics (exposure, cells and km2 at or above 10k, cells at or above 100k and 1M cells/L, maximum, cells changed, samples >= 10k and > 1M cells/L included), and `equal` |
| `tables/md5_final5_issue18.csv`, `tables/md5_final15_issue18.csv` | the final runs with the defaults: at 5 arcmin against run A and the 6 October baseline, at 15 arcmin against the tracked files of 22 May 2026 (`md5_tracked15_issue18.csv`, taken before the run); with `exported_equal` (the Ecospace ST drivers copy) |
| `tables/nearshore_set15_issue18.csv` | the set raster written at 15 arcmin: cell, row, col, lon, lat, depth, km2 |
| `tables/record_months_issue18.csv` | all 504 months, three variants (`v6oct` the 6 October maps, `mask5` the #10 run B, `final` the delivered maps): total exposure, cells and km2 at the thresholds, maximum, cells changed, samples >= 10k and > 1M cells/L and how many the map includes; the #6 month flags |
| `tables/record_groups_issue18.csv`, `tables/record_annual_issue18.csv` | the same summed by month group (all 504; hull, satellite, VIIRS, MODIS; the zeroed, headline and VIIRS-positive fitted months of #6; months with at least 5 water samples >= 10k cells/L) and by year, with the exposure ratios |
| `figures/fig1_headline_months_issue18.pdf` | the 16 headline months of #6, one row each: samples (red border = >= 10k cells/L on water, outside the 6 October footprint) \| the 6 October map \| the delivered map (nearshore set shaded, changed cells in orange); 2 pages |
| `figures/fig2_record_2002-2026_issue18.png` | the record from the first satellite month (2002-07) to 2026: exposure, cells at or above 10k / 100k / 1M cells/L, share of samples included; the 6 October maps and the delivered maps, clip source shaded |
| `comments/record_summary.md` | the group and headline tables in markdown, as the script writes them |
| `tables/md5_refresh5_issue18.csv`, `tables/md5_refresh15_issue18.csv` | the refresh runs against the frozen runs, with `exported_equal` |
| `tables/refresh_months5_issue18.csv`, `tables/refresh_months15_issue18.csv` | the months whose water samples or ASCII file changed between the frozen and the refreshed run: samples and positives before and after |
| `clip_months_hybrid_issue18.R` | step 6: draws the monthly comparison PDF, its CSV and the example figure from the 5-arcmin run on disk, after asserting that the run is the delivered one |
| `clip_months_hybrid_issue18.pdf` | one row per month for all 504 months, twelve rows (one calendar year) per page, 42 pages (a month's page is its year minus 1984), 9.2 MB: A FWC counts \| B sdmTMB unclipped \| C VIIRS clipped \| D MODIS clipped \| E hulls \| F the delivered map (the hybrid nearshore map, rule `mask5adj`); every map panel with its total exposure and class counts; the red frame on the clip the final map is built on |
| `tables/clip_class_counts_hybrid_issue18.csv` | the count-box numbers of that PDF, one month per row: `use`, `sat_src` (the framed panel: viirs / modis / hull), `hybrid_changed`, `fit_status`, `viirs_status`; `<map>_<class>` for the maps `fwc` (samples), `unclip`, `viirs`, `modis`, `hull`, `final` and the classes `n_pos`, `n_le1e3`, `n_1e3_1e4`, `n_1e4_1e5`, `n_1e5_1e6`, `n_gt1e6`; `<map>_exposure` for the five maps (cells/L summed over the water cells, unrounded); `final_n_changed` (cells where the final map differs from the framed clip). NA where the month has no samples, no fit or no layer |
| `figures/fig3_monthly_rows_example_issue18.png` | four rows of that PDF, 2012-01 to 2012-04 (the months of the #6 example figure), for the issue |
| `hoard/` (gitignored) | local copies of the run outputs the later stages read: `runA/`, `final5/`, `final15/`, `refresh5/`, `refresh15/`; `preview/` (PNG pages of the monthly PDF) and the quick-mode PDF |

## Results

### Step 2: the rule verified at 5 arcmin (23 October 2026, FWC samples frozen at 22 September 2026)

| run | `viirs_nearshore` / `modis_nearshore` | minutes | result |
|---|---|---|---|
| A | `mask5adj` / `mask5adj` | 7.4 | **210 of 504 ASCII files differ from the 6 October 2026 maps, exactly the months the hybrid changed** (121 VIIRS, 89 MODIS); 155 hybrid / 123 hybrid_modis / 226 pred; the set raster has the 189 cells of the #15 table (14,205 km2; 84 / 132 / 177 by criterion; no Atlantic cell); both hybrid stacks equal the satellite clip outside the set and the cell-wise maximum inside it, never below, no detection removed; **all 278 satellite months equal the #15 `union_hull` prototype on the 9 metrics**; the 226 hull months equal the 6 October maps |
| 0 | `none` / `none` | 7.6 | **0 of 504 ASCII files differ from the 6 October 2026 maps** (the unchanged #11 stage `none`; the escape hatch still works after the code change); the log says `Nearshore rule: none` for both sensors |

Over the 278 satellite months run A gives what the prototype gave: exposure 7.04e9 (x 1.084 vs 6 Oct), 30,474 cell-months at or above 10k cells/L, 12,515 of 13,280 water samples >= 10k cells/L included (94.2%), 1,573 of 1,610 samples > 1M cells/L (97.7%).

### Step 3: the defaults flipped, the deliverables regenerated with the frozen samples (23 October 2026)

Both defaults are `"mask5adj"` (`run_redtide_maps.R`); `config.local.R` carries no nearshore key, `fwc_refresh = FALSE` and `export_ecospace = TRUE`.

| run | resolution | minutes | result |
|---|---|---|---|
| final 5 | 5 arcmin | 8.3 | **0 of 504 ASCII files differ from run A** (the flipped defaults do what the local override did); 210 differ from the 6 October maps; set 189 cells; the hybrid relations hold; **the 504 files in the Ecospace ST drivers folder (`<root>/5min/red tide/sdmTMB/`) equal `ecospace_ascii/` byte for byte** (stage `final`) |
| final 15 | 15 arcmin | 7.4 (after a cold run that fitted the 334 months and was stopped by the machine in the clipping step; the fits are cached) | **the set at 15 arcmin has 53 of the 428 water cells, 35,890 km2** (13 in the VIIRS mask, 20 within 5 km, 48 touching land; 5 Atlantic cells excluded; depth median 7.7 m); **205 months change (118 VIIRS, 87 MODIS)**; the hybrid relations hold; 323 of 504 files differ from the tracked files of 22 May 2026 (which predate the hull rule of #3, so that difference is not the hybrid alone); **the 504 files in `<root>/15min/red tide/sdmTMB/` equal `ecospace_ascii/` byte for byte** |

**The whole record as Ecospace reads it** (stage `record`, from the final 5-arcmin combined stack against the 6 October 2026 maps, with the `mask5` run of #10 beside them; `tables/record_months_issue18.csv`, `record_groups_issue18.csv`, `record_annual_issue18.csv`, `comments/record_summary.md`). The three variants equal the #15 record table month by month in all 504 months, so the delivered maps are the prototype that #15 and the #5 summary describe:

| months | months changed | total exposure, 6 Oct -> delivered (`mask5`) | cell-months >= 10k / >= 100k / >= 1M cells/L | samples >= 10k cells/L included | samples > 1M cells/L included |
|---|---|---|---|---|---|
| all 504, 1985-2026 | 210 | 8.87e9 -> 9.42e9, x 1.062 (x 1.053) | 35,606 -> 38,110 / 13,290 -> 14,183 / 1,716 -> 1,809 | 72.4% -> 95.6% (94.7%) | 78.5% -> 98.3% (97.9%) |
| the 278 satellite months | 210 | 6.49e9 -> 7.04e9, x 1.084 (x 1.073) | 27,970 -> 30,474 / 10,569 -> 11,462 / 1,253 -> 1,346 | 63.2% -> 94.2% (93.0%) | 70.6% -> 97.7% (97.1%) |
| the 155 VIIRS months | 121 | 4.12e9 -> 4.58e9, x 1.113 (x 1.102) | 10,204 -> 12,133 / 5,633 -> 6,367 / 901 -> 978 | 53.2% -> 96.6% (95.1%) | 63.7% -> 99.2% (98.5%) |
| the 123 MODIS months | 89 | 2.37e9 -> 2.46e9, x 1.035 (x 1.023) | 17,766 -> 18,341 / 4,936 -> 5,095 / 352 -> 368 | 82.4% -> 89.6% (89.0%) | 88.9% -> 93.7% (93.4%) |
| the 226 hull months | 0 | 2.38e9, unchanged | unchanged | 99.8% | 100% |
| the 58 zeroed VIIRS months of #6 | 58 | 0 -> 4.37e7 | 0 -> 358 / 0 -> 105 / 0 -> 3 | 0% -> 88.5% (85.5%) | 0% -> 96.9% (87.5%) |
| the 16 headline months of #6 | 16 | 0 -> 4.24e7 | 0 -> 358 / 0 -> 105 / 0 -> 3 | 0% -> 88.6% (85.9%) | 0% -> 96.9% (87.5%) |

Figures: `figures/fig1_headline_months_issue18.pdf` (the 16 headline months, one row each: samples | the 6 October map | the delivered map with the nearshore set shaded and the changed cells in orange; 2 pages) and `figures/fig2_record_2002-2026_issue18.png` (the record from the first satellite month: exposure, cells at the three thresholds, share of samples included; the 6 October maps in black, the delivered maps in purple).

### Step 4: the refresh rerun with the new FWC samples (23 October 2026)

After the frozen deliverables were committed, the pipeline ran again with `fwc_refresh = TRUE` (the default: the `Recent_` endpoint re-queried from the last local sample date), the same defaults and the export on; stage `refresh` compares each run with the frozen one (`hoard/final5/`, `hoard/final15/`).

| run | minutes | FWC samples | result |
|---|---|---|---|
| refresh 5 | 7.4 | `19800102-20260922` -> `19800102-20261021` | **2 of 504 ASCII files changed, 2026-09 and 2026-10, both hull-served**; 2026-09 gained 110 water samples (121 -> 231, positives 1 -> 13), 2026-10 is new (62 samples, 2 positives); the 278 satellite months and the other hull months byte-identical to the frozen run; the Ecospace copy equals `ecospace_ascii/` |
| refresh 15 | 6.7 | the same pull (no new records) | **2 of 504 ASCII files changed, 2026-09 and 2026-10, both hull-served**; on the 15-arcmin grid 2026-09 gained 119 water samples (138 -> 257, positives 1 -> 11) and 2026-10 is new (72 samples, 3 positives; the counts differ from 5 arcmin because the coarser grid marks different cells as land); the satellite months byte-identical to the frozen run; the Ecospace copy equals `ecospace_ascii/` |

The refreshed maps are the tracked deliverables; the only difference from the frozen, verified maps is the two latest months, which the hulls serve. (At the time of the check the Ecospace ST drivers folder at 5 arcmin also held `sdmTMB_log__202302-IF-NCBS-24GLV34.asc`, a OneDrive conflict copy made while the folder was being overwritten; the check reports and ignores files that are not monthly files. Holden deleted the copy on 26 October 2026.)

### Step 6: the monthly comparison PDF with the hybrid column (24 October 2026)

`clip_months_hybrid_issue18.pdf` is the #6 PDF (`docs/issue5_nearshore-hybrid-summary/subissues/issue6_VIIRS-zeros/clip_months_issue6.pdf`, the 6 October 2026 maps) redrawn by `clip_months_hybrid_issue18.R` from the delivered run on disk (the refresh run of 23 October 2026, FWC samples to 21 October 2026), with one more column. One row per month from 1985-01 to 2026-12, twelve rows per page so each page is one calendar year (42 pages; a month's page is its year minus 1984). The columns: **A** the FWC samples of the month, filled by abundance class; **B** the unclipped sdmTMB surface; **C** the prediction clipped to the positive VIIRS cells, outlined; **D** clipped to the MODIS nFLH polygons, outlined; **E** clipped to the buffered hulls, outlined; **F** the delivered map, the nearshore hybrid of the framed panel and the hulls (the combined stack the ASCII files are written from), with the outline of the framed panel in grey and the nearshore set (189 cells) in black. The red frame keeps the #6 meaning, the clip the final map is built on (C in the 155 VIIRS months, D in the 123 MODIS months, E in the 226 hull months), so the two PDFs read side by side: F shows what the hybrid makes of the framed panel, and in the hull months it equals E. Every map panel prints its **total exposure**, the sum of cells/L over the 3,838 water cells (the number Ecospace integrates; three significant figures), then the positive cells and the five FWC classes with FWC's bounds (at most 1,000; 1,000 to 10,000; 10,000 to 100,000; 100,000 to 1,000,000; above 1,000,000 cells/L); panel A counts the samples the same way; F adds the count of cells changed against the framed clip. A month with no samples, no fit, no VIIRS tif or no MODIS polygon keeps its row with a note in the empty panel. Land is drawn as the template's land cells (the 1,310 NODATA cells of the 5-arcmin depth grid, which every ASCII file carries and Ecospace sees), not as a coastline polygon, so bays and estuaries appear as the grid has them (Holden, 26 October 2026). The same numbers are in `tables/clip_class_counts_hybrid_issue18.csv`.

What the PDF shows in numbers (the script's summary, from the CSV):

| months | final map exposure, cells/L | the framed clips | ratio | cells changed |
|---|---|---|---|---|
| all 504 | 9.42e9 | 8.88e9 | 1.062 | 5,428 cell-months in the 210 `hybrid_changed` months |
| the 278 satellite months | 7.04e9 | 6.49e9 | 1.084 | the same 5,428 |
| the 226 hull months | 2.38e9 | the same | 1 | 0 |
| the 58 fitted VIIRS months whose layer is all zero (#6) | 4.37e7 | 0 | | 2,115 positive cells in the final maps |
| the 16 headline months of #6 | 4.24e7 | 0 | | 829 positive cells |

The satellite-month figures equal the record stage of step 3 (7,041,082,852 against 6,494,237,122 cells/L); the all-month figures differ from it only through 2026-09 and 2026-10, the months the refresh changed. Fit status from the unclipped layers: 331 fitted, 5 failed, 168 not attempted (the #6 run had 329 / 5 / 170; 2026-09 and 2026-10 are fitted since the refresh).

Reading the example (`figures/fig3_monthly_rows_example_issue18.png`, 2012-01 to 2012-04, the months of the #6 example figure): in 2012-01 the VIIRS layer has positive cells, the VIIRS clip keeps 85 cells (exposure 3.56 million cells/L) and the final map keeps 105 cells (3.98 million), the 20 added cells taken from the hull clip inside the nearshore set. In 2012-02 to 2012-04 the VIIRS layer is all zero, so the framed panel is empty (exposure 0; in the #6 PDF this was the final map) while the final map holds 33, 58 and 24 cells (exposure 24,600, 1.86 million and 27,400 cells/L), the nearshore part of the hull clips (83, 146 and 49 cells; 61,900, 4.47 million and 51,900 cells/L).

## Checks the script enforces

Stage `rule`: the 504 files exist and no others; use counts 155 / 123 / 226 with `hybrid` and `hybrid_modis` set exactly where `use` says; the changed files are exactly the `hybrid_changed` months and number 210 (121 + 89); the run log holds the `mask5adj` line with the three counts, the two `Hybrid:` lines with 121 and 89, `fwc_refresh = FALSE` and `Run complete.`; the set raster is NA exactly on land, 0 or 1 on water, has no Atlantic cell, 189 cells, 14,205 km2, the cell ids of the #15 table and its criterion counts; each hybrid stack equals its satellite-clipped stack outside the set and the cell-wise maximum with the hull-clipped stack inside it, never below it; the combined stack equals the hybrid stacks in the satellite months and the 6 Oct combined stack in the hull months; the satellite clips of the run equal the 6 Oct maps in the satellite months; every satellite month equals the prototype on the 9 metrics (exposure within 1 cells/L of the rounded table value), no cell is removed, the changed-file flag equals `cells_changed > 0`; the totals equal the frozen prototype numbers. Two runs of the stage give byte-identical CSVs.

Stage `final`: the run log holds the `mask5adj` line, the two `Hybrid:` lines, `fwc_refresh = FALSE`, `Step 8: export` and `Run complete.`; use counts 155 / 123 / 226; at 5 arcmin 0 files differ from run A and exactly the 210 `hybrid_changed` months differ from the 6 October baseline; at 15 arcmin the set has 53 cells and 35,890 km2, 428 water cells with 5 in the Atlantic box, 205 months change (118 VIIRS, 87 MODIS) and the log line carries 13 / 20 / 48; the set raster is NA exactly on land with no Atlantic cell; the hybrid relations and the combined-stack identity as in `rule`; every monthly file in the Ecospace ST drivers folder equals its `ecospace_ascii/` file by MD5. Stage `record`: the three combined stacks have NA exactly on land; the delivered maps are at or above the 6 October maps and the `mask5` maps on every water cell; the hull months are identical across the variants; the per-month sample counts equal the #6 table; the three variants equal the #15 record table month by month (exposure within 1 cells/L) in all 504 months; the satellite-month totals equal the frozen prototype numbers; no hull month changed. Stage `refresh`: use counts and `hybrid_changed` unchanged; the log says the samples were ingested from the ArcGIS REST endpoints, names the rule and the export; every changed file is a hull-served month on or after the first month with new or changed water samples; no month lost samples; the export folder equals `ecospace_ascii/`. Two runs of every stage give byte-identical CSVs and PNGs (the PDF carries the date lines every R pdf() device writes).

`clip_months_hybrid_issue18.R` (step 6), before drawing: the 504 ASCII files on disk equal `tables/md5_refresh5_issue18.csv` by MD5 and the combined stack cell for cell, and the samples file is the one of 21 October 2026 (the run on disk is the delivered one); `clipping_source.csv` matches the stacks, use counts 155 / 123 / 226, `hybrid_changed` in 210 months (121 VIIRS, 89 MODIS); the combined stack equals the hybrid stacks in the satellite months and the hull clip in the hull months, NA exactly on land; each hybrid stack equals its satellite clip outside the set and the cell-wise maximum with the hull clip inside it, never below, and the cells changed are positive exactly in the `hybrid_changed` months; the set raster has 189 cells, NA exactly on land, none in the Atlantic box; the VIIRS stack has 155 layers, 89 with no positive cell; 2022-12 is `missing` and MODIS-served; the fit status read from the unclipped layers equals `RT_fit_matrix.RData` in every month (331 / 5 / 168); every month with a positive sample has a hull footprint; the matrix-to-image orientation. On the count boxes: the sample classes sum to the positives and equal the sample table, the final classes sum to the final positives, the final map never has fewer positive cells or less exposure than the framed clip (equal in the 294 months the hybrid did not change), the hull months equal the hull clip, the final exposure equals `exposure_final` of `record_months_issue18.csv` within 1 cells/L except in 2026-09 and 2026-10 (the months the refresh changed), and the unclipped exposure is at or above every clip. Two runs give a byte-identical CSV and PNG.
