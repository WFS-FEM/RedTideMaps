# Issue #15: the land-adjacent nearshore rule on the Ecospace basemap

Examination for [WFS-FEM/RedTideMaps#15](https://github.com/WFS-FEM/RedTideMaps/issues/15), the test Holden asked for before the [#5](https://github.com/WFS-FEM/RedTideMaps/issues/5) call: an alternative to the `mask5` nearshore set of [#8](https://github.com/WFS-FEM/RedTideMaps/issues/8), [#11](https://github.com/WFS-FEM/RedTideMaps/issues/11) and [#10](https://github.com/WFS-FEM/RedTideMaps/issues/10). The rule: a water cell of the Ecospace basemap that shares an edge or a corner with a land cell is nearshore; in satellite months (VIIRS or MODIS) those cells take the sdmTMB projection unclipped; hull months are untouched. Two questions: does the set cover the cells the VIIRS no-data mask hides (if not, adapt the rule), and what the rule does to the metrics (in-situ samples included, total exposure, cells added at >=10k, >=100k and >1M cells/L). Branch `15-test-adjacent-land-cells-hybrid`, 22 October 2026. The plan, with the decisions it rests on, is `issue15-adjacent-land-plan.md`.

**Nothing in the pipeline changes here, and no pipeline run is needed.** The check script prototypes every variant from the stacks the last run left on disk and from the local copies of the #11 and #10 runs. The tracked deliverables (`out/5min/ecospace_ascii/`, `out/5min/plots/`) stay the 6 October 2026 maps; the #5 call then chooses between `mask5` and a rule from here, and only then does a rule go into the pipeline.

## What is compared

The land cells of the basemap are the NODATA cells of `template rasters/depth 5min 66x78.asc`, which is numerically the EcospaceBasemap grid `output/5min/depth/depth_5min.asc` (asserted cell for cell at run time). The Gulf domain is every water cell outside the Atlantic-side box east of -82 E and north of 28.5 N, which is always excluded (the pipeline drops its samples and VIIRS does not cover it).

| variant | nearshore set | fill inside the set, satellite months |
|---|---|---|
| `v6oct` | none | the satellite-clipped layer (the delivered maps) |
| `mask5` | `mask5` (VIIRS no-data mask or within 5 km of the coast; 136 cells) | max(satellite-clipped, hull-clipped), both sensors (#11 and #10) |
| `adj8_sdm` | land-adjacent (edge or corner), the issue's rule | the raw sdmTMB projection |
| `adj8m_sdm` | land-adjacent or in the VIIRS no-data mask | the raw sdmTMB projection |
| `adj8_hull` | land-adjacent | max(satellite-clipped, hull-clipped), the `mask5` fill |
| `union_hull` | the union of `mask5` and land-adjacent (189 cells) | max(satellite-clipped, hull-clipped), the `mask5` fill |

After checkpoint 1 Holden kept the hull fill and narrowed the question to the set: `mask5` against the union of `mask5` and the land-adjacent cells, which captures every VIIRS-masked cell and every cell near the shore by distance or by grid proximity (question 3 below). The first three variants stay as the record of the fill question.

## How to run

```
# no pipeline run; needs out/5min/sdm/, out/5min/clipped/ and VIIRS/ from the last run,
# the nearshore_mask_mask5.grd of a run with a nearshore rule on, the 6 Oct 2026 combined
# stack in docs/issue11_nearshore-hybrid-pipeline/hoard/before/combined/, the run-B
# combined stack in docs/issue10_modis-nearshore-hybrid/hoard/after/combined/, and the
# EcospaceBasemap checkout beside this repository (env RT_BASEMAP_DEPTH overrides the path)
RT_QA_STAGE=examine Rscript docs/issue15_adjacent-land-hybrid/check_adjacent_hybrid_issue15.R   # RT_QA_PNG_DIR=<dir> adds PNG previews of fig 3
```

## Files

| File | What |
|---|---|
| `issue15-adjacent-land-plan.md` | the plan: the review of where things stood, the facts established before the run, the three decisions, the GitHub workflow, the stage, the verification |
| `check_adjacent_hybrid_issue15.R` | the check script, stage `examine` |
| `tables/set_coverage_issue15.csv` | one row per candidate set (rook-adjacent, edge-or-corner-adjacent, within 2 cells, adjacent or VIIRS mask, mask5, the union): cells, km2, VIIRS-mask cells covered (of 84), within-5-km cells covered (of 132), land-adjacent cells covered (of 177), mask5 cells covered (of 136), cells not in mask5, Atlantic-box cells excluded |
| `tables/set_missed_mask_cells_issue15.csv` | the VIIRS-mask cells each candidate misses: cell, row, column, position, depth, distance to the coast, whether it is in the top grid row |
| `tables/set_cells_issue15.csv` | every cell in any candidate set or in mask5: position, depth, km2, distance to the coast, distance to the nearest basemap land cell (in cells), the set flags (adjacent, within 5 km, VIIRS mask, mask5, union), the Atlantic flag, months the satellite map / the hull map / the raw surface (>= 10k cells/L) is positive there |
| `tables/mask5_vs_union_issue15.csv` | mask5 against the union, both with the hull fill: cells, km2, coverage of the mask / 5 km / adjacent cells, exposure (all satellite months, VIIRS, MODIS) and its ratio to the delivered maps, cell-months at the three thresholds, months changed, samples included overall, > 1M cells/L, in the zeroed months and by era |
| `tables/exposure_by_era_issue15.csv` | total exposure by era (all 278 satellite months, the 155 VIIRS months, the 123 MODIS months): the delivered maps, mask5 and the union, the three ratios, cell-months >= 10k cells/L and the share of samples included |
| `tables/examine_months_issue15.csv` | the 278 satellite months, one row each: use, fit status, whether a surface exists, the #6 flags, samples >= 10k and > 1M cells/L, then per variant: exposure, cells and km2 at or above 10k, cells >= 100k and >= 1M, maximum, cells changed against the delivered map, samples included and their share |
| `tables/examine_groups_issue15.csv`, `tables/examine_annual_issue15.csv` | the same summed by month group (all 278; VIIRS; MODIS; the 58 zeroed, 16 headline and 60 VIIRS-positive fitted months of #6; months with at least 5 such samples; months with and without a surface) and by year; ratios to the delivered maps and to mask5 |
| `tables/record_months_issue15.csv`, `tables/record_groups_issue15.csv` | all 504 months 1985-2026, the five variants (the hull months identical by construction, asserted), for the #5 call |
| `tables/fill_values_issue15.csv` | what each fill writes into its set cells: the cell-months changed against the delivered map by class of the value written (<= 1k, 1k to 10k, 10k to 100k, 100k to 1M, > 1M cells/L), the share below 10k, the median, the exposure added; by variant and era |
| `tables/excluded_samples_issue15.csv`, `tables/excluded_bands_issue15.csv` | the water samples >= 10k cells/L outside the delivered footprint in satellite months (4,889): position, count, cell, set flags, distance to the coast, and which variant includes them; and the same by distance band (0-2, 2-5, 5-10, > 10 km) |
| `tables/cells_sat_issue15.csv` | per water cell over the 278 satellite months: cumulative exposure and cell-months >= 100k and >= 1M cells/L under the delivered maps, mask5 and the #15 rule, and the differences |
| `figures/fig1_sets_issue15.png` | left: the land-adjacent set against mask5 (in both, adjacent only, mask5 only; the VIIRS static mask outlined; the 6 mask cells the adjacent set misses marked); right: the union, mask5 in purple and the 53 adjacent-only cells in orange, the 12 mask5 cells that touch no land cell ringed and labelled |
| `figures/fig2_record_2002-2026_issue15.png` | the record from the first satellite month: total exposure, cells >= 10k / 100k / 1M cells/L, share of samples included; the delivered maps (black), mask5 (purple), the #15 rule (orange), the adjacent-or-mask variant (dashed); clip source shaded |
| `figures/fig3_months_issue15.pdf` | the 16 headline months of #6, then the 12 satellite months where the #15 rule and mask5 differ most in exposure, one row each: samples \| delivered map \| mask5 \| #15 rule \| raw sdmTMB with the adjacent set shaded; 4 pages (`RT_QA_PNG_DIR` writes PNG previews) |
| `figures/fig4_cells_issue15.png` | per cell over the satellite months: cumulative exposure under the delivered maps, mask5 and the #15 rule; where the #15 rule is above and below mask5; the difference in cell-months >= 100k cells/L |
| `comments/examine_summary.md` | the coverage, group, fill, distance-band, headline-month, annual and per-cell tables in markdown, as the script writes them |

## Results (22 October 2026, checkpoint 1)

Frozen FWC samples to 22 September 2026; the stacks of run 0 of #10 (both rules off); the mask5 maps of run B of #10. Two runs of the stage give byte-identical CSVs and PNGs; the recomputation of three months by hand (2017-01, 2003-02, 2018-10) equals the tables.

### Question 1: does the land-adjacent set cover the cells the VIIRS mask hides?

Mostly. The land-adjacent set (edge or corner with a NODATA cell of the basemap, Gulf domain) has 177 cells and 13,311 km2 (202 cells before excluding the 25 land-adjacent cells of the Atlantic-side box). It covers 78 of the 84 template cells in the static VIIRS no-data mask and 124 of the 136 mask5 cells (`fig1`). The 6 mask cells it misses are cells 13 and 14 in the top grid row (30.46 N, 86.4 to 86.5 W, near Destin: the land north of them is outside the grid, so on the grid they have no land neighbour) and four second-row cells (333 near Panama City, 736 off Apalachicola, 3573 and 3651 in Charlotte Harbor) whose 0.1-degree VIIRS cell is masked although the 5-arcmin cell does not touch land. The 53 adjacent cells that are not in mask5 (1.3 to 24.4 m deep) touch land but have their centre more than 5 km from the Natural Earth coastline and a VIIRS cell with data: along the Big Bend, in the Panhandle bays and down the south-west coast (`fig1`).

| set | cells | km2 | VIIRS-mask cells covered (of 84) | mask5 cells covered (of 136) | cells not in mask5 |
|---|---|---|---|---|---|
| rook-adjacent (edge only) | 128 | 9,627 | 66 | 105 | 23 |
| land-adjacent (edge or corner), the #15 rule | 177 | 13,311 | 78 | 124 | 53 |
| land-adjacent or VIIRS static mask, the adaptation (D2) | 183 | 13,759 | 84 | 130 | 53 |
| within 2 cells of land | 338 | 25,417 | 84 | 136 | 202 |
| mask5 (#8 decision D1) | 136 | 10,227 | 84 | 136 | 0 |

Adding the 6 mask cells is the smallest adaptation that covers the mask (183 cells); within 2 cells of land covers everything but is 2.5 times the mask5 area.

### Question 2: what the rule does to the metrics

Over the 278 satellite months (155 VIIRS, 123 MODIS); water samples are FWC samples whose 5-arcmin cell is water; "included" = the map is non-zero in the sample's cell:

| variant | total exposure (cells/L summed over the water cells) | cell-months >= 10k / >= 100k / >= 1M cells/L | samples >= 10k cells/L included (of 13,280) | samples > 1M cells/L included (of 1,610) | months changed |
|---|---|---|---|---|---|
| the delivered 6 Oct 2026 maps | 6.49e9 | 27,970 / 10,569 / 1,253 | 63.2% | 70.6% | 0 |
| mask5, both sensors | 6.97e9 (+7.3%) | 29,962 / 11,297 / 1,336 | 93.0% | 97.1% | 208 |
| land-adjacent set, raw sdmTMB fill (the #15 rule) | 7.65e9 (+17.9%) | 40,041 / 13,129 / 1,349 | 93.4% | 97.6% | 215 |
| land-adjacent or VIIRS mask, raw sdmTMB fill | 7.68e9 (+18.2%) | 40,370 / 13,192 / 1,349 | 93.8% | 97.6% | 215 |
| land-adjacent set, hull fill (the mask5 fill) | 7.03e9 (+8.2%) | 30,355 / 11,430 / 1,345 | 93.4% | 97.6% | 210 |

1. **The set hardly matters for the samples; the fill is what changes the maps.** The land-adjacent set with the mask5 fill includes 93.4% of the samples >= 10k cells/L against 93.0% for mask5 and adds 8.2% to the exposure against 7.3%: the two sets cover the same samples (within 2 km of the coast 99.3% vs 99.7% included, 2 to 5 km 98.3% vs 96.3%, `excluded_bands`). The raw sdmTMB fill on the same set includes exactly the same samples (12,408 of 13,280; a sample >= 10k cells/L inside the set sits in the hull footprint by construction, so either fill reaches it when the month has a surface) but adds 1.16e9 cells/L to the satellite months, 2.5 times the 4.7e8 of mask5 and 2.2 times the hull fill on the same set.
2. **The raw fill is the model surface, not the samples, so it fills the strip in every fitted month.** It changes 215 of the 217 satellite months that have a surface (mask5 changes 208, the months with a nearshore hull), and 57% of the 27,968 cell-months it changes are below 10k cells/L (8,546 at or below 1k, 7,351 between 1k and 10k; `fill_values`): a background-level strip wherever the fit says so (the hull fill of mask5 is also 53% below 10k cells/L, but over 4,260 changed cell-months, not 27,968). The other 43% are at bloom level: cell-months >= 10k cells/L rise from 29,962 (mask5) to 40,041 (+34%), >= 100k from 11,297 to 13,129 (+16%), >= 1M from 1,336 to 1,349. In the 16 headline months of #6 the raw fill gives 61.3 million cells/L summed and 984 cell-months >= 10k against 29.4 million and 285 for mask5; 2017-01 goes from 2,428 km2 (mask5) to 12,006 km2 at or above 10k cells/L because the raw surface of that month is above 10k over 289,289 km2 and the set takes its coastal strip (`fig3`, page 1).
3. **In the headline months mask5 includes more samples than the plain adjacent set, and the adaptation restores them.** Over the 58 zeroed months, 85.5% of the samples >= 10k cells/L are included under mask5, 81.9% under the land-adjacent set (either fill) and 85.4% with the VIIRS mask added: the 12 mask5-only cells (the 6 missed mask cells and 6 within-5-km cells) hold samples in those months (2017-01: 113 of 116 included under mask5, 101 under the adjacent set, 103 with the mask added). Over all satellite months the order reverses (93.0% / 93.4% / 93.8%) because the 53 adjacent-only cells hold samples in the VIIRS-positive months.
4. **The MODIS era is where the two fills differ most in relative terms.** mask5 adds 2.3% to the 123 MODIS months (MODIS looks at the coast, #10); the raw fill adds 14.6%, in 94 months, while the samples included go from 89.0% to 89.5%. By year the ratio of the #15 rule to the delivered maps runs from 1.05 (2020) to 1.92 (2012) in the VIIRS era and from 1.07 (2025) to 1.30 (2003) in the MODIS era, against 1.01 to 1.27 and 1.00 to 1.06 for mask5 (`examine_annual`).
5. **Per cell** (`fig4`), the #15 rule is above mask5 in all 177 of its cells over the satellite months (up to 9.8 million cells/L summed) and below it in the 12 mask5-only cells (up to 2.8 million); 174 cells gain 1 to 27 cell-months >= 100k cells/L against mask5 and 9 lose up to 8.

### Question 3: mask5 or the union, with the hull fill

Holden's reading of checkpoint 1 (22 October 2026): keep the hull fill; compare only `mask5` with the union of `mask5` and the land-adjacent cells. `mask5` is exactly "in the static VIIRS mask, or centre within 5 km of the Natural Earth coastline" (136 cells; recomposed from the set table and asserted equal to the pipeline raster). The union adds the 53 land-adjacent cells `mask5` lacks and so has 189 cells and 14,205 km2; it covers the 84 mask cells, the 132 within-5-km cells and the 177 adjacent cells by construction, and is `mask5` plus one `raster::adjacent()` call on the depth template (no new input).

**Why the two parts see different cells.** They see different land. Adjacency reaches further than 5 km on the open coast: the 53 adjacent-only cells touch a land cell but have their centre 5.0 to 12.1 km (median 6.6) from the coastline, because a 5-arcmin cell is 8 to 9 km wide and the centre of a corner-touching neighbour lies well away from the land cell and further still from the coastline inside it (Big Bend, the Panhandle bays, the south-west coast). Adjacency fails only where the basemap has no land cell: the 12 `mask5` cells that touch no land cell (median 3.6 km from the coastline) all sit two cells from the nearest basemap land cell. Two are Choctawhatchee Bay cells cut by the map edge (13, 14; treating the northern grid edge as land catches exactly these two and nothing else). Nine are Gulf-side cells against barrier islands or thin peninsulas that the 5-arcmin ETOPO grid draws as water while the coastline draws them as land: 91 and 92 against Okaloosa Island at Destin, 333 off Shell Island (Panama City), 413 off Crooked Island, 649 west of St Joseph Peninsula, 736 and 812 off St George Island (Apalachicola), 2710 off Anna Maria Island at the mouth of Tampa Bay, 3573 in Pine Island Sound behind Captiva; 3651 off Sanibel (5.3 km, in the mask) is the twelfth. All twelve are 4 to 18 m deep and hull-positive in 13 to 157 months (`fig1`, right; `set_cells`). Median distance from cell centre to the coastline: 3.1 km for the adjacent cells (max 12.1), 2.1 km for the `mask5` cells (max 6.3).

| set, hull fill, 278 satellite months | cells | km2 | total exposure vs 6 Oct | cell-months >= 10k / >= 100k / >= 1M cells/L | samples >= 10k cells/L included (of 13,280) | samples > 1M cells/L included (of 1,610) | in the 58 zeroed months | months changed |
|---|---|---|---|---|---|---|---|---|
| `mask5` | 136 | 10,227 | +7.3% | 29,962 / 11,297 / 1,336 | 93.0% (12,351) | 97.1% | 85.5% | 208 (121 VIIRS, 87 MODIS) |
| union of `mask5` and land-adjacent | 189 | 14,205 | +8.4% | 30,474 / 11,462 / 1,346 | 94.2% (12,515) | 97.7% | 88.5% | 210 (121 VIIRS, 89 MODIS) |

Total exposure by era (cells/L summed over the 3,838 water cells and the months of the era; `exposure_by_era`):

| era | months | 6 Oct 2026 maps | mask5 | union | mask5 vs 6 Oct | union vs 6 Oct | union vs mask5 | samples >= 10k cells/L included: 6 Oct / mask5 / union |
|---|---|---|---|---|---|---|---|---|
| all satellite months | 278 | 6,494,237,122 | 6,967,296,294 | 7,041,082,852 | +7.3% | +8.4% | +1.1% | 63.2% / 93.0% / 94.2% |
| VIIRS months | 155 | 4,119,726,916 | 4,538,271,356 | 4,583,313,352 | +10.2% | +11.3% | +1.0% | 53.2% / 95.1% / 96.6% |
| MODIS months | 123 | 2,374,510,206 | 2,429,024,938 | 2,457,769,500 | +2.3% | +3.5% | +1.2% | 82.4% / 89.0% / 89.6% |

The union includes 164 more samples >= 10k cells/L and adds 1.1 points of exposure (7.4e7 cells/L summed, 4.5e7 of it in the VIIRS months and 2.9e7 in the MODIS months), all from the 53 adjacent-only cells. By distance to the coast, the 2 to 5 km band goes from 96.3% to 99.2% included and the 5 to 10 km band from 88.7% to 92.8%; within 2 km both sets are at or above 99.7%. With the hull fill the set is a second-order choice: either way the maps gain only where positive samples sit, and the union simply extends that reach to the land-adjacent cells the 5 km rule does not see.

### Checks the stage enforces

The basemap grid equals the template cell for cell (1,310 NODATA cells, depths within 0.01 m); the adjacent set has 177 Gulf-domain cells and no Atlantic cell is ever filled; the VIIRS static mask has 84 template cells and the on-disk mask5 raster has the 136 cells of the #11 table and equals "mask or centre within 5 km" cell for cell; the union has 189 cells, 14,205 km2, covers the mask, the 5 km band and the adjacent cells, equals mask5 inside mask5 and the adjacent-set variant inside the adjacent set, and is never below either; the coverage counts of the plan; the satellite months are the 155 VIIRS and 123 MODIS months of `clipping_source.csv` and their delivered layers equal the 6 Oct 2026 combined stack; the raw layer is all NA on water or has no NA, is at or above the satellite-clipped layer on every water cell and equals it where the satellite is positive; mask5 recomputed equals the run-B combined stack and changes 121 VIIRS and 87 MODIS months; each variant equals the delivered map outside its set and is never below it; the raw fill changes no month without a surface; the per-month sample counts equal the #6 table; the 6 Oct 2026 and mask5 metrics equal `exposure_months_issue11.csv` and `record_months_issue10.csv` month by month; the hull months are identical in every variant; the headline totals of the first runs (exposure, samples included, months changed, cell-months >= 10k per variant, the union included; 4,889 excluded samples; 217 months with a surface) are frozen in `expected` and asserted.
