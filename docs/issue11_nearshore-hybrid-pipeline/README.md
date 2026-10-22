# Issue #11: the nearshore hybrid (`mask5`) in the pipeline

Implementation and checks for [WFS-FEM/RedTideMaps#11](https://github.com/WFS-FEM/RedTideMaps/issues/11), the sub-issue of [#5](https://github.com/WFS-FEM/RedTideMaps/issues/5) that follows [#8](https://github.com/WFS-FEM/RedTideMaps/issues/8). Issue #8 showed that the high-count FWC samples VIIRS misses sit in the static VIIRS no-data band along the coast, prototyped a hybrid from the on-disk clipped stacks, and settled on the `mask5` set with the cell-wise maximum rule (decision of 20 October 2026). This issue puts that rule into the pipeline behind a config key, checks that the default reproduces the 6 October 2026 deliverables byte for byte and that the new rule reproduces the prototype, and compares the VIIRS-only and hybrid maps. Branch `11-nearshore-hybrid-pipeline`, PR #12, 20 October 2026.

**The tracked deliverables (`out/5min/ecospace_ascii/`, `out/5min/plots/`) are still the 6 October 2026 maps.** The default stays `viirs_nearshore = "none"`; the `mask5` deliverables were produced locally, are described here and in the #11 thread, and will be committed when #5 accepts them (then the default flips). The same rule for the MODIS-served months is issue #10 (`docs/issue10_modis-nearshore-hybrid/`), which also moved the two hybrid functions from `scripts/process_VIIRS.R` to `scripts/process_hybrid.R`.

## What changed in the pipeline

- **`fn.nearshore_mask()`** (`scripts/process_VIIRS.R` then; `scripts/process_hybrid.R` since #10): the static nearshore set as a 5-arcmin raster (1 nearshore, 0 other water, NA land), written to `out/<res>min/clipped/nearshore_mask_mask5.grd`. Rule `mask5`: a template water cell of the Gulf domain (outside the Atlantic-side box east of -82 E and north of 28.5 N, which VIIRS does not cover) is nearshore if its 0.1-degree VIIRS cell is NA in at least 90% of the VIIRS layers (the static no-data mask, read from the stack itself), or if its centre lies within 5 km of the Natural Earth 1:10m coastline (nearest point of the coastline densified to 200 m, UTM 17N, as in the #8 diagnostic). 136 cells, 10,227 km2: 84 in the VIIRS mask, 132 within 5 km, 80 in both.
- **`fn.clip_2_hybrid()`** (`scripts/process_VIIRS.R` then; `scripts/process_hybrid.R` since #10, where it takes any satellite stack): for every layer of the VIIRS-clipped stack, outside the set the VIIRS-clipped layer stands, zeros included; inside it the cell takes `max(viirs_clipped, hull_clipped)`, the hull-clipped layer being the pipeline's own (every positive sample, 75 km linkage, 10 km buffer). Written to `*_clipped_hybrid.grd`; returns the months changed. `fn.clip_2_viirs()` and `fn.clip_2_hulls()` are untouched.
- **`make_redtide_ascii()`** (`scripts/polygon_clipping_rt.R`): new `file_hybrid`, preferred over the VIIRS stack when given (hybrid > VIIRS > MODIS > hull). `clipping_source.csv` gains `hybrid` (the month is served by the hybrid stack) and `hybrid_changed` (the hybrid layer differs from the VIIRS-clipped one); both all FALSE without the hybrid, and `use` unchanged then. A latent bug surfaced here: `names()` of an empty raster stack is the string `"NULL."`, so an absent stack entered the month list as a phantom month; absent stacks now stay NULL (any run without VIIRS or MODIS would have hit it).
- **Config** (`run_redtide_maps.R`, `config.local.example.R`): `cfg$viirs_nearshore = "none"` (default) or `"mask5"`, validated right after `config.local.R`; the run log names the rule, the set size and the months the hybrid changed. `cfg$fwc_refresh = TRUE`; `FALSE` reuses the local merged FWC CSV without querying FWC (the file is rewritten byte-identical), so a rerun sees exactly the samples of the run it reproduces. The ingest step otherwise pulls new samples on every run, which would change 2026 months for a reason unrelated to the rule.
- **Coastline**: `docs/issue8_nearshore-hybrid/coastline/` moved to `data/coastline/` (a pipeline input now, exposed as `paths$file_coast`); the #8 script and README point there.
- **README**: cascade section, pipeline table, config table, inputs and outputs.

## How to run

```
# config.local.R
cfg$fwc_refresh     <- FALSE     # reproduce the samples of the previous run
cfg$viirs_nearshore <- "mask5"   # or leave the default "none"
Rscript run_redtide_maps.R       # 7 to 15 min warm, alone on the machine

# checks, from the repo root (each stage reads what the last run left on disk)
RT_QA_STAGE=none    Rscript docs/issue11_nearshore-hybrid-pipeline/check_hybrid_issue11.R   # after a "none" run
RT_QA_STAGE=mask5   Rscript docs/issue11_nearshore-hybrid-pipeline/check_hybrid_issue11.R   # after a "mask5" run (RT_QA_PNG_DIR=<dir> adds PNG previews of fig 1)
RT_QA_STAGE=compare Rscript docs/issue11_nearshore-hybrid-pipeline/check_hybrid_issue11.R   # from hoard/before and hoard/after
RT_QA_STAGE=exposure Rscript docs/issue11_nearshore-hybrid-pipeline/check_hybrid_issue11.R  # exposure per map, all 504 months, from the same copies
```

The `compare` stage reads the combined stacks and `clipping_source.csv` of the two runs from `hoard/before/` and `hoard/after/` (local copies of the two runs' `out/5min/` deliverables; `hoard/` is gitignored), so it does not depend on which run is on disk. The #6 and #8 QA scripts (`scripts/qa/check_clipping_issue6.R`, `docs/issue8_nearshore-hybrid/*.R`) assert that the final map equals the VIIRS-clipped layer in every VIIRS month, so they need a `"none"` run on disk.

| File | What |
|---|---|
| `check_hybrid_issue11.R` | the three-stage check script |
| `tables/md5_baseline_issue11.csv` | MD5 of the 504 tracked ASCII files at main 7f08076 (the 6 October 2026 run), taken before any run here |
| `tables/md5_none_issue11.csv` | the `"none"` run against the baseline: `yrmo, use, md5_before, md5_after, changed` |
| `tables/md5_mask5_issue11.csv` | the `"mask5"` run against the baseline, with `hybrid` and `hybrid_changed` from `clipping_source.csv` |
| `tables/nearshore_set_issue11.csv` | the 136 cells of the set: cell, lon, lat, depth, km2 |
| `tables/hybrid_vs_prototype_issue11.csv` | per VIIRS month, the hybrid stack of the run against the #8 prototype (`mask5` rows of `hybrid_months_long_issue8.csv`): footprint, bloom areas, cells changed and added, water samples by class inside, and `equal` |
| `tables/months_issue11.csv` | per VIIRS month, before (VIIRS only) and after (hybrid): footprint and bloom areas, cells in the footprint, max, mean over all water cells, cells changed, water samples by class and how many are inside |
| `tables/annual_issue11.csv`, `tables/climatology_issue11.csv`, `tables/groups_issue11.csv` | the same by year (km2 summed over the months), by calendar month (means over 2012-2024), and by month group |
| `tables/bloom_months_per_cell_issue11.csv` | per water cell, months at or above 10,000 cells/L before and after |
| `tables/exposure_months_issue11.csv` | all 504 months 1985-2026, before and after: total exposure (cells/L summed over the 3,838 water cells), cells and km2 at or above 10,000 / 100,000 / 1,000,000 cells/L, max, clip source, whether the hybrid changed the month |
| `tables/exposure_annual_issue11.csv`, `tables/exposure_climatology_issue11.csv`, `tables/exposure_groups_issue11.csv` | the same summed by year (cell-months), averaged by calendar month over 2012-2024, and summed by month group (all 504; hull, MODIS, VIIRS; zeroed, headline, VIIRS-positive fitted) |
| `tables/exposure_cells_issue11.csv` | per water cell over the 155 VIIRS months: cumulative exposure and cell-months at or above 100,000 and 1,000,000 cells/L, before and after |
| `figures/fig4_exposure_1985-2026_issue11.png`, `figures/fig5_exposure_2012-2024_issue11.png` | per month, before vs after: total exposure (millions of cells/L, linear axis), the three cell counts, and the share of in-situ samples >= 10,000 cells/L the projection includes (months with at least 5 such samples); over the full record (clip source shaded) and over the VIIRS era (all-zero VIIRS months shaded) |
| `figures/fig6_exposure_cells_issue11.png` | per cell over the VIIRS months: cumulative exposure and cell-months at or above 100,000 cells/L, before, after and the difference |
| `comments/exposure_summary.md` | the exposure tables in markdown, as written by the script |
| `figures/fig1_headline_before_after_issue11.pdf` | the 16 headline months of #6, one row each: samples (border = VIIRS cell status) \| before (VIIRS-clipped) \| after (hybrid, changed cells in orange) \| hull-clipped with the set shaded; 2 pages |
| `figures/fig2_area_2012-2024_issue11.png` | per month 2012-2024: bloom area at >= 10,000 and >= 100,000 cells/L, mean over all water cells, share of samples >= 10,000 cells/L inside; before vs after |
| `figures/fig3_bloom_months_per_cell_issue11.png` | bloom months per cell before, after, and the months the hybrid adds |
| `comments/compare_summary.md` | the group, annual, climatology, headline and per-cell tables in markdown, as written by the script |

## Results

### Acceptance (20 October 2026, both runs with `fwc_refresh = FALSE`, FWC data to 22 September 2026)

1. **`"none"` reproduces the 6 October 2026 deliverables byte for byte**: 0 of the 504 ASCII files differ; `clipping_source.csv` has 155 viirs / 123 modis / 226 pred and all-FALSE hybrid columns; the run log says `Nearshore rule: none`; same 10 flagged hull months as on 6 October; 6.6 min. The tracked PNG plots are byte-identical; the two tracked PDFs differ only in their date lines (10 and 12 bytes).
2. **`"mask5"` changes exactly the 121 VIIRS months with a nearshore hull**: 121 of 504 ASCII files differ, all of them `use = hybrid` with `hybrid_changed = TRUE`; the other 34 VIIRS months, the 123 MODIS months and the 226 hull months are unchanged. The set has 136 cells and 10,227 km2 (84 in the VIIRS mask, 132 within 5 km). The log names the rule, the set and the 121 months. 15.1 min (the machine was busier; the "none" run took 6.6).
3. **The run equals the #8 prototype in every month**: footprint, bloom area at >= 10,000 and >= 100,000 cells/L, cells changed, cells added, and the water samples >= 10,000 cells/L and by class inside the footprint equal the prototype's `mask5` rows in all 155 months (11 metrics). No cell is ever lowered (the hybrid is never below the VIIRS-clipped map). The check script's tables and PNGs are byte-identical across reruns.

### The VIIRS-only and hybrid maps compared

Totals over the 155 VIIRS months (bloom area in km2 of water cells; samples are FWC water-cell samples whose 5-arcmin cell is non-zero):

| group | months changed | area >= 10,000 cells/L, before -> after | area >= 100,000, before -> after | months with bloom area, before -> after | mean over all water cells (cells/L), before -> after | samples >= 10,000 inside, before -> after | high samples (> 1,000,000) inside |
|---|---|---|---|---|---|---|---|
| all 155 VIIRS months | 121 | 776,173 -> 898,477 (x 1.16) | 427,929 -> 475,626 (x 1.11) | 58 -> 75 | 6,925 -> 7,629 | 53% -> 95% (of 8,745) | 64% -> 98% (of 1,168) |
| the 58 zeroed months of #6 | 58 | 0 -> 21,750 | 0 -> 5,805 | 0 -> 16 | 0 -> 137 | 0% -> 86% (of 904) | 0% -> 88% (of 32) |
| the 16 headline months | 16 | 0 -> 21,750 | 0 -> 5,805 | 0 -> 16 | 0 -> 480 | 0% -> 86% (of 867) | 0% -> 88% (of 32) |
| the 60 VIIRS-positive fitted months of #6 | 60 | 776,173 -> 876,727 (x 1.13) | 427,929 -> 469,821 | 58 -> 59 | 17,890 -> 19,575 | 59% -> 96% (of 7,841) | 66% -> 99% (of 1,136) |

1. **The change is confined to the coast and adds 16% to the bloom area over the VIIRS era.** 121 of the 155 months change, by 12 to 62 cells each; the added area is 122,304 km2 over 155 months against a VIIRS footprint of 776,173 km2, and the mean concentration Ecospace reads over the whole template rises by 10% (6,925 to 7,629 cells/L). Every added cell is in the 136-cell nearshore set; nothing is removed anywhere (`fig3`: 130 water cells gain bloom months, 1 to 57 each, median 8; none lose any; the cells with the most bloom months go from 48 to 58 of 155).
2. **The 58 zeroed months get their nearshore footprint back; the 16 headline months are the ones that matter.** The hybrid gives the 16 headline months 21,750 km2 of bloom area (147 to 2,807 km2 each; 2017-01 to 2017-03: 2,428 / 2,287 / 1,524 km2; 2021-06: 2,807 km2) and 5,805 km2 at or above 100,000 cells/L; the other 42 zeroed months get hull values below 10,000 cells/L (the fitted surface stays below that everywhere in them, as #6 found). Of the water samples >= 10,000 cells/L in the zeroed months 86% now sit inside the footprint (773 of 904) and 88% of the high samples (28 of 32), against none before. The four headline months whose high counts sit offshore in valid VIIRS cells (2012-03, 2019-02, 2020-01, 2020-11) stay small (148 to 1,080 km2), as decided (D4: a valid VIIRS zero stands).
3. **In the VIIRS-positive months the hybrid adds a nearshore strip and little else.** The 60 fitted VIIRS-positive months of #6 gain 13% of bloom area (776,173 to 876,727 km2) and the share of their samples >= 10,000 cells/L inside the footprint goes from 59% to 96%; the two big blooms (2018, 2021) change by 11 to 14% a year (`fig2`). The 6 VIIRS-positive months without a fit or with fewer than 5 such samples add nothing at or above 10,000 cells/L.
4. **Seasonally the hybrid matters most in spring.** By calendar month (means over 2012-2024), March to June bloom area doubles or triples (March 861 to 1,775 km2, April 270 to 886, May 229 to 428, June 383 to 663) because those are the months the VIIRS layer is most often all zero (11 of 13 years), while the autumn peak changes by 4 to 12% (October 16,862 to 17,982 km2). The share of samples >= 10,000 cells/L inside the footprint is at least 0.9 in every calendar month after, against 0.1 to 0.8 before.
5. **By year** the ratio of hybrid to VIIRS-only bloom area runs from 1.05 (2024) to 1.48 (2017); 2017 goes from 2 to 6 months with bloom area, 2018 from 8 to 12.

### Red tide exposure per monthly map (what Ecospace reads)

Ecospace reads each monthly map cell by cell, so the comparison was repeated on quantities that follow the driver directly (stage `exposure`, 21 October 2026): **total exposure**, the plain sum of cells/L over the 3,838 water cells of a map (no area weighting; the water-cell count is the same in every map); the **number of grid cells at or above 10,000, 100,000 and 1,000,000 cells/L**; and the **share of the in-situ samples at or above 10,000 cells/L that the projection includes** (water-cell samples whose 5-arcmin cell is non-zero in the map, the converse of the samples the footprint cuts). Both methods, all 504 months 1985-2026; the methods are identical outside the 155 VIIRS months (checked), so the hull and MODIS eras are context. Yearly and group totals are sums over the months (cell-months).

**Overall: over the 155 VIIRS months the hybrid raises total exposure by 10.2% and the share of in-situ samples >= 10,000 cells/L that the projection includes from 53.2% to 95.1% (4,655 to 8,316 of 8,745), and for the high samples from 63.7% to 98.5%. Over all 504 months 1985-2026: exposure +4.7%, samples included 72.4% to 93.0% (12,861 to 16,522 of 17,760), high samples 78.5% to 96.9%.** The hull and MODIS months are unchanged, which is why the record-wide shares move less: the hull months already include 99.8% of their samples (4,470 of 4,480; the rest fall in months with no fitted surface) and the MODIS months 82.4% (3,736 of 4,535).

| group | months changed | total exposure, before -> after (cells/L summed) | cell-months >= 10,000 cells/L | cell-months >= 100,000 | cell-months >= 1,000,000 |
|---|---|---|---|---|---|
| all 504 months 1985-2026 | 121 | 8.87e9 -> 9.29e9 (x 1.047) | 35,606 -> 37,220 | 13,290 -> 13,919 | 1,716 -> 1,788 |
| the 155 VIIRS months | 121 | 4.12e9 -> 4.54e9 (x 1.102) | 10,204 -> 11,818 | 5,633 -> 6,262 | 901 -> 973 |
| the 60 VIIRS-positive fitted months of #6 | 60 | 4.12e9 -> 4.51e9 (x 1.094) | 10,204 -> 11,533 | 5,633 -> 6,186 | 901 -> 972 |
| the 58 zeroed months | 58 | 0 -> 3.05e7 | 0 -> 285 | 0 -> 76 | 0 -> 1 |
| the 16 headline months | 16 | 0 -> 2.94e7 | 0 -> 285 | 0 -> 76 | 0 -> 1 |

1. **In exposure terms the hybrid is a 10% addition to the VIIRS era and 5% to the whole record.** The 155 VIIRS months hold 46% of the record's summed exposure (4.12e9 of 8.87e9; the 226 hull months 2.38e9, the 123 MODIS months 2.37e9); the hybrid adds 4.19e8 to them. Cell-months at or above 10,000 cells/L rise 16% in the VIIRS months, at or above 100,000 by 11%, at or above 1,000,000 by 8% (72 cell-months, 23 cells).
2. **Most of the added exposure is the nearshore strip of VIIRS-positive months, not the zeroed months.** Of the 4.19e8 added, 3.88e8 (93%) falls in the 60 VIIRS-positive fitted months and 3.05e7 (7%) in the 58 zeroed months. The zeroed months go from nothing to something, but that something is modest: the 16 headline months sum to 2.94e7 (0.06 to 6.9 million each; 2018-03 6.9e6, 2021-06 6.5e6, 2017-01 3.6e6), with 285 cell-months at or above 10,000 cells/L, 76 at or above 100,000 and one at or above 1,000,000 (2021-06, max 1.3e6 cells/L), because the fitted surfaces of those months are moderate and the hull keeps them to the sampled coast. In the maps Ecospace reads, the big-bloom years still dominate: 2018 alone carries 1.81e9 before and 1.95e9 after, more than the whole hull era.
3. **By year** the ratio in the VIIRS era runs from 1.01 (2020) to 1.27 (2012); the largest additions are 2018 (+1.3e8) and 2019 (+8.1e7). **By calendar month** the hybrid multiplies April exposure by 5.3 (from a very low base, 1.2e5 to 6.2e5 on average), March by 1.6 and February by 1.4, against 1.06 to 1.11 for September to January: the VIIRS layer is all zero in 11 of 13 springs.
4. **Per cell** (`fig6`), 131 of the 3,838 water cells gain cumulative exposure over the VIIRS months (median 1e6 cells/L summed, max 4.7e7, all along the coast from the Panhandle to the Keys and in Tampa Bay and Charlotte Harbor); 106 cells gain 1 to 29 cell-months at or above 100,000 cells/L. The cell with the most exposure before (5.85e7, off Lee County) stays the maximum after (5.95e7).

### Checks the script enforces

Stage `none`: the 504 files exist and no others; MD5s equal the baseline; use counts 155 / 123 / 226; hybrid columns all FALSE; the log holds the `none` line and the `fwc_refresh = FALSE` line. Stage `mask5`: use counts 155 hybrid / 123 / 226; the changed files are exactly the `hybrid_changed` months and number 121; the set raster matches the template, has 136 cells and 10,227 km2; the hybrid stack equals the VIIRS-clipped stack outside the set and the cell-wise maximum inside it, never below the VIIRS-clipped map; the 11 per-month metrics equal the prototype in every month; no cell is removed; the changed ASCII files are exactly the months with a changed cell. Stage `compare`: the MODIS and hull months are identical in the two runs; the hybrid is never below the VIIRS-only map; 121 months changed. Stage `exposure`: both stacks have NA exactly on the 1,310 land cells and a value on every water cell in all 504 months; before equals after outside the 121 changed months; exposure and every count rise or stay in every month, and exposure rises in exactly the changed months; for the VIIRS months the km2 at the two lower thresholds equal the compare-stage bloom areas, the exposure equals the compare-stage mean times 3,838 within rounding, and the samples included equal the compare-stage counts; the sample count per month is the same for both methods and the included count never falls. The #6 month table supplies the 58 zeroed, 16 headline and 60 VIIRS-positive fitted months, asserted by count.
