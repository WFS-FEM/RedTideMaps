# Issue #18: the hybrid clipping approach in the pipeline, the regenerated deliverables, the closure of #5

Implementation, verification and the regenerated deliverables for [WFS-FEM/RedTideMaps#18](https://github.com/WFS-FEM/RedTideMaps/issues/18), the issue that closes [#5](https://github.com/WFS-FEM/RedTideMaps/issues/5) after [#6](https://github.com/WFS-FEM/RedTideMaps/issues/6), [#8](https://github.com/WFS-FEM/RedTideMaps/issues/8), [#11](https://github.com/WFS-FEM/RedTideMaps/issues/11), [#10](https://github.com/WFS-FEM/RedTideMaps/issues/10) and [#15](https://github.com/WFS-FEM/RedTideMaps/issues/15). The nearshore set decided in #15 (the union of `mask5` and the land-adjacent cells, 189 cells at 5 arcmin; `docs/issue15_adjacent-land-hybrid/nearshore-set-method.md`) goes into the pipeline as rule `"mask5adj"`, becomes the default for both sensors, and the Ecospace deliverables are regenerated at 5 and 15 arcmin. Branch `18-implement-hybrid-clipping`, October 2026. The plan, with the decisions it rests on, is `issue18-implement-hybrid-plan.md`.

(Work in progress: the sections below are filled in as the steps complete.)

## What changed in the pipeline

- **`fn.nearshore_mask()`** (`scripts/process_hybrid.R`): rule `"mask5adj"`, the decided set of #15. A template water cell of the Gulf domain (the Atlantic-side box east of -82 E and north of 28.5 N is always excluded) is nearshore if its 0.1-degree VIIRS cell is in the static VIIRS no-data mask (NA in at least 90% of the VIIRS layers), or if its centre lies within 5 km of the Natural Earth 1:10m coastline, or if it shares an edge or a corner with a land cell of the template (a NODATA cell of the depth grid, the land of the Ecospace basemap; `raster::adjacent(directions = 8)` from the water side, the grid borders not treated as land). The first two criteria are the `"mask5"` rule of #8, #11 and #10, whose code path is untouched; the third is computed only for `"mask5adj"`. The function returns and reports `n_adjacent_cells`; the raster is `out/<res>min/clipped/nearshore_mask_mask5adj.grd`. At 5 arcmin: 189 cells, 14,205 km2 (84 in the VIIRS mask, 132 within 5 km, 177 touching land; `mask5` is 136 cells). The rule is written out in `docs/issue15_adjacent-land-hybrid/nearshore-set-method.md`.
- **`fn.clip_2_hybrid()`**: unchanged. Inside the set a cell takes the cell-wise maximum of the satellite-clipped and hull-clipped layers; outside it the satellite result stands, zeros included (#11, #10).
- **Config** (`run_redtide_maps.R`, `config.local.example.R`, README): `cfg$viirs_nearshore` and `cfg$modis_nearshore` accept `"none"`, `"mask5"` and `"mask5adj"`; the run-log line names the rule, the set size and, for `"mask5adj"`, the count of cells touching land. (The defaults are flipped to `"mask5adj"` in step 3 below.)

## How to run

```
# config.local.R for the verification runs (step 2): cfg$fwc_refresh <- FALSE, the two keys as named
cfg$viirs_nearshore <- "mask5adj"; cfg$modis_nearshore <- "mask5adj"    # run A, then:
RT_QA_STAGE=rule Rscript docs/issue18_implement-hybrid-clipping/check_final_hybrid_issue18.R   # 210 files change; = the #15 prototype month by month; copy the outputs to hoard/runA/
cfg$viirs_nearshore <- "none";     cfg$modis_nearshore <- "none"        # run 0, then:
RT_QA_STAGE=none Rscript docs/issue11_nearshore-hybrid-pipeline/check_hybrid_issue11.R         # the unchanged #11 check: the 6 Oct 2026 maps byte for byte
```

Each pipeline run takes 7 to 8 minutes alone on the machine; after a verification run, `git checkout -- out/5min/ecospace_ascii out/5min/plots` restores the tracked deliverables. The stages after the flip (`final`, `record`, `refresh`, with `RT_QA_RES=5` or `15`) are listed in the script header and below once run.

## Files

| File | What |
|---|---|
| `issue18-implement-hybrid-plan.md` | the plan: context and state found, the decisions of 23 Oct 2026 (D10 to D13), the GitHub workflow, the five steps, verification |
| `check_final_hybrid_issue18.R` | the check script, stages `baseline`, `rule`, `final`, `record`, `refresh` (`RT_QA_STAGE`), resolution `RT_QA_RES` |
| `tables/md5_runA_issue18.csv` | run A against the 6 Oct 2026 baseline: `yrmo, file, use, hybrid, hybrid_modis, hybrid_changed, md5_now, md5_6oct, changed_vs_6oct` |
| `tables/nearshore_set5_issue18.csv` | the 189 cells of the set raster written by run A, with the three criteria flags joined from the #15 table |
| `tables/hybrid_vs_prototype_issue18.csv` | per satellite month (278), the hybrid stacks of run A against the `union_hull` prototype of #15 on 9 metrics (exposure, cells and km2 at or above 10k, cells at or above 100k and 1M cells/L, maximum, cells changed, samples >= 10k and > 1M cells/L included), and `equal` |
| `hoard/` (gitignored) | local copies of the run outputs the later stages read: `runA/`, `final5/`, `final15/` |

## Results

### Step 2: the rule verified at 5 arcmin (23 October 2026, FWC samples frozen at 22 September 2026)

| run | `viirs_nearshore` / `modis_nearshore` | minutes | result |
|---|---|---|---|
| A | `mask5adj` / `mask5adj` | 7.4 | **210 of 504 ASCII files differ from the 6 October 2026 maps, exactly the months the hybrid changed** (121 VIIRS, 89 MODIS); 155 hybrid / 123 hybrid_modis / 226 pred; the set raster has the 189 cells of the #15 table (14,205 km2; 84 / 132 / 177 by criterion; no Atlantic cell); both hybrid stacks equal the satellite clip outside the set and the cell-wise maximum inside it, never below, no detection removed; **all 278 satellite months equal the #15 `union_hull` prototype on the 9 metrics**; the 226 hull months equal the 6 October maps |
| 0 | `none` / `none` | 7.6 | **0 of 504 ASCII files differ from the 6 October 2026 maps** (the unchanged #11 stage `none`; the escape hatch still works after the code change); the log says `Nearshore rule: none` for both sensors |

Over the 278 satellite months run A gives what the prototype gave: exposure 7.04e9 (x 1.084 vs 6 Oct), 30,474 cell-months at or above 10k cells/L, 12,515 of 13,280 water samples >= 10k cells/L included (94.2%), 1,573 of 1,610 samples > 1M cells/L (97.7%).

## Checks the script enforces

Stage `rule`: the 504 files exist and no others; use counts 155 / 123 / 226 with `hybrid` and `hybrid_modis` set exactly where `use` says; the changed files are exactly the `hybrid_changed` months and number 210 (121 + 89); the run log holds the `mask5adj` line with the three counts, the two `Hybrid:` lines with 121 and 89, `fwc_refresh = FALSE` and `Run complete.`; the set raster is NA exactly on land, 0 or 1 on water, has no Atlantic cell, 189 cells, 14,205 km2, the cell ids of the #15 table and its criterion counts; each hybrid stack equals its satellite-clipped stack outside the set and the cell-wise maximum with the hull-clipped stack inside it, never below it; the combined stack equals the hybrid stacks in the satellite months and the 6 Oct combined stack in the hull months; the satellite clips of the run equal the 6 Oct maps in the satellite months; every satellite month equals the prototype on the 9 metrics (exposure within 1 cells/L of the rounded table value), no cell is removed, the changed-file flag equals `cells_changed > 0`; the totals equal the frozen prototype numbers. Two runs of the stage give byte-identical CSVs.
