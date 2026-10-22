# Issue #10: the nearshore hybrid for the MODIS months

Examination, implementation and checks for [WFS-FEM/RedTideMaps#10](https://github.com/WFS-FEM/RedTideMaps/issues/10), the follow-up of [#8](https://github.com/WFS-FEM/RedTideMaps/issues/8) and [#11](https://github.com/WFS-FEM/RedTideMaps/issues/11) under [#5](https://github.com/WFS-FEM/RedTideMaps/issues/5). Issue #11 put the `mask5` nearshore rule into the pipeline for the 155 VIIRS months; this issue asks whether the 123 months served from MODIS nFLH polygons (2002-07 to 2011-12, 2022-12, 2025-01 to 2025-09) need the same, examines it from the stacks on disk, and, on a go, applies the same set and rule to them behind `cfg$modis_nearshore`. Branch `10-modis-nearshore-hybrid`, PR #13, October 2026. The plan, with the decisions it rests on, is `issue10-modis-hybrid-plan.md`.

**Status (22 October 2026): step 1 (examine) done and posted to #10 as checkpoint 1; nothing in the pipeline has changed yet.** The tracked deliverables (`out/5min/ecospace_ascii/`, `out/5min/plots/`) are still the 6 October 2026 maps.

## How to run

```
# from the repo root; needs the stacks of the last pipeline run in out/5min/clipped/, the
# nearshore_mask_mask5.grd of a "mask5" run (issue #11) and the 6 Oct 2026 combined stack in
# docs/issue11_nearshore-hybrid-pipeline/hoard/before/combined/
RT_QA_STAGE=examine Rscript docs/issue10_modis-nearshore-hybrid/check_modis_hybrid_issue10.R   # ~1 min; RT_QA_PNG_DIR=<dir> adds PNG previews of fig 1
```

## Files

| File | What |
|---|---|
| `issue10-modis-hybrid-plan.md` | the plan: context and preview numbers, GitHub workflow, the four steps, verification |
| `check_modis_hybrid_issue10.R` | the check script; stage `examine` (the stages for the pipeline runs follow the pipeline change) |
| `tables/examine_months_issue10.csv` | one row per MODIS-served month (123): fit status, nFLH polygons, cells changed, and before / after the rule: footprint and bloom area (km2 at or above 10,000 and 100,000 cells/L), maximum, mean over water, total exposure, cells at or above 10k / 100k / 1M cells/L, water samples >= 10,000 cells/L and > 1,000,000 cells/L with how many the map includes |
| `tables/examine_annual_issue10.csv`, `tables/examine_groups_issue10.csv` | the same summed by year and by month group (all 123; 2002-2011; 2022-12 and 2025; months with at least 5 such samples; of those, under half included before; months with such samples but no cell at 10,000 cells/L) |
| `tables/excluded_samples_issue10.csv` | one row per water sample >= 10,000 cells/L outside the MODIS footprint (799): month, position, count, class, template cell, in the set or not, distance to the coast, recovered by the rule or not |
| `tables/excluded_bands_issue10.csv` | all water samples >= 10,000 cells/L of the MODIS months by distance to the coast (0-2, 2-5, 5-10, > 10 km): in the set, excluded before, recovered, excluded after, share included before / after |
| `tables/modis_coverage_issue10.csv` | the 136 set cells: depth, distance to the coast, months MODIS-positive, months hull-positive, months the rule changes |
| `tables/modis_never_positive_bands_issue10.csv` | water cells MODIS never marks positive over the 123 months, by distance band |
| `figures/fig1_examine_months_issue10.pdf` | the 12 months with the largest gain in samples included, then the 8 months with such samples but no bloom cell: samples | MODIS-clipped (the delivered map) | hybrid | hull-clipped with the set shaded; count boxes |
| `figures/fig2_examine_series_issue10.png` | the 123 months as a series: total exposure, cells at or above 10k / 100k / 1M cells/L, share of samples included; before and after; all-zero MODIS maps shaded |
| `figures/fig3_excluded_samples_issue10.png` | the 799 excluded samples on the map (recovered or not) and their distance to the coast (ECDF) |
| `comments/examine_summary.md` | the tables above in markdown, as the script writes them |

## Results

### Step 1: examine (22 October 2026, checkpoint 1)

Prototype from the stacks on disk: for the 123 MODIS-served months, hybrid = max(MODIS-clipped, hull-clipped) inside the 136-cell `mask5` set, the MODIS-clipped layer outside it (the same set and rule as #11; the MODIS-clipped layers equal the delivered 6 October 2026 maps for those months, checked). Frozen FWC samples to 22 September 2026.

| quantity (123 MODIS months) | VIIRS months (#11) | MODIS, before -> after |
|---|---|---|
| months changed by the rule | 121 of 155 | 87 of 123 |
| water samples >= 10,000 cells/L included | 53.2% -> 95.1% | 82.4% -> 89.0% (3,736 -> 4,035 of 4,535) |
| samples > 1,000,000 cells/L included | 63.7% -> 98.5% | 88.9% -> 93.4% (393 -> 413 of 442) |
| total exposure (cells/L summed over the 3,838 water cells, all months) | +10.2% | +2.3% (2.37e9 -> 2.43e9) |
| bloom area >= 10,000 cells/L, km2 summed over the months | +16% | +2.1% (1,343,000 -> 1,371,529) |
| cell-months >= 10k / 100k / 1M cells/L | 10,204 -> 11,818 / 5,633 -> 6,262 / 901 -> 973 | 17,766 -> 18,144 / 4,936 -> 5,035 / 352 -> 363 |

1. **The gap is real but smaller than in the VIIRS era, because MODIS looks at the coast.** 132 of the 136 set cells are MODIS-positive in at least one of the 123 months; the 2,123 water cells MODIS never marks positive sit a median 230 km offshore (4 within 5 km of the coast). There is no coastal no-data band to fill.
2. **What the rule recovers is the coastal strip; the rest of the misses are offshore.** Of the 799 excluded samples, 301 lie in the set and 299 are recovered (median 0.9 km from the coast); the 500 still excluded sit a median 24.7 km out, where MODIS looked and saw nothing (Yao Yao's condition keeps those). Within 5 km of the coast the included share goes 87.8% -> 98.9%, beyond 5 km 75.4% -> 76.1%; samples within 2 km: 87.1% -> 99.8%.
3. **Where it matters:** the 10 months with at least 5 such samples and under half of them included (2002-08, 2003-02, 2003-06, 2003-07, 2003-08, 2003-12, 2005-04, 2006-06, 2007-02, 2009-11) go from 35.7% to 67.3% included, 2 of them stay under half; 2003 as a year 59% -> 78%, 2007 81% -> 94%, 2006-07 67 -> 93 of 104 samples. The 29 all-zero MODIS maps stay all-zero (no hull inside the set in those months), and the 8 months with samples but no bloom cell have 1 to 10 samples each.
4. **Reading for the go / no-go:** the same rule applied to the MODIS months changes little in the aggregate (+2% exposure) and does exactly what it was meant to do nearshore (99% of the coastal samples included, as in the VIIRS era), so the record would carry one nearshore treatment across the satellite eras instead of a step at 2012 and 2025. A MODIS-specific set, for a product of different resolution, remains a possible follow-up.

Checks the stage enforces: 123 months; the MODIS-clipped layers equal the 6 October combined layers; the hybrid is never below the MODIS layer and equals it outside the set; the per-month sample counts equal `n_pos_1e4_water` of the #6 table; the numbers of the plan's preview (87 changed; 4,535 / 3,736 / 4,035 samples; 442 / 393 / 413 high; 799 / 301 / 299 excluded; 132 of 136 set cells; the exposure sum; the group sizes 60 / 10 / 2 / 8 / 7 / 29) are asserted. Two runs give byte-identical CSVs and PNGs.
