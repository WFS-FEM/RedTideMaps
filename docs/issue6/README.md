# Issue #6: non-clipped vs clipped monthly red tide maps

Diagnostic comparison prepared 8 October 2026 on branch `6-nonclipped-comparison-maps` for [WFS-FEM/RedTideMaps#6](https://github.com/WFS-FEM/RedTideMaps/issues/6), the sub-issue of [#5](https://github.com/WFS-FEM/RedTideMaps/issues/5) (VIIRS months with no positive cell are written as all-zero maps). Nothing in the pipeline or the deliverables was changed; every number here is read from the stacks the 6 October 2026 run left on disk. Sections 1 to 3 are written to be pasted into #6, sections 4 and 5 into #5.

Everything is produced by one tracked script:

```
Rscript scripts/qa/check_clipping_issue6.R        # ~30 s; RT_QA_PDF=0 skips the PDF
```

| File | What |
|---|---|
| `docs/issue6/clip_comparison_issue6.csv` | one row per month, 1985-01 to 2026-12 (504 rows); columns in §1.2 |
| `docs/issue6/clip_comparison_summary.md` | the tables below in full (all 58 zeroed months, all 33 other flagged months) |
| `docs/issue6/fig1_viirs_calendar.png` | VIIRS layer status by year and month, with in-situ positives |
| `docs/issue6/fig2_insitu_vs_viirs.png` | monthly in-situ positives vs VIIRS positive cells, 2012-2024 |
| `docs/issue6/fig3_bloom_area_unclipped_vs_final.png` | bloom area before and after clipping, by clip source |
| `docs/issue6/fig4_headline_months.png` | the ten headline months: unclipped, final, hull alternative, MODIS alternative |
| `docs/issue6/clip_check_issue6.pdf` | one page per fitted month (329 pages, 7.7 MB): unclipped + samples + footprint, VIIRS-clipped, MODIS-clipped, hull-clipped |
| `docs/issue6/clip_months_issue6.pdf` | one row per month for all 504 months, 12 rows (one calendar year) per page: FWC counts, unclipped, VIIRS-clipped, MODIS-clipped, hull-clipped, each panel with its legend and a count box; the clipped panel the final map uses is framed in red (§1.3) |

## 1. What was compared

### 1.1 The four maps of a month

The pipeline predicts one sdmTMB surface per month (the **unclipped** map, `out/5min/sdm/sdmTMB_log_stack_*.grd`) and masks it three ways: to the VIIRS positive cells, to the MODIS nFLH polygons, and to the buffered hulls around the positive samples (`out/5min/clipped/*_clipped_{viirs,modis,hull}.grd`). The **final** map (`out/5min/combined/`) is the VIIRS-clipped one if a VIIRS tif exists for the month, else the MODIS-clipped one, else the hull-clipped one. All three alternatives are on disk for every month that has that source, so "what would the other rule have produced" needs no rerun.

Each PDF page shows the four maps side by side in the palette of the pipeline PDFs (white below 10,000 cells/L). The panel the final map actually uses has a red frame and the title prefix "USED". The unclipped panel carries every sample of the month (small dots for zero counts, viridis-filled circles for positives binned at 1,000 / 10,000 / 100,000 / 1,000,000 cells/L) and the outline of the footprint used; the used panel repeats the samples at or above 10,000 cells/L as open circles so samples outside the footprint are visible.

### 1.2 The per-month table

Bloom area is the km2 of water cells at or above 10,000 cells/L (`area_1e4_*`, the first coloured bin of the PDFs and FWC "low") or 100,000 cells/L (`area_1e5_*`, FWC "medium" and the lower inflection of the Ecospace mortality response), land masked. Column groups:

- in situ: `n_samples`, `n_samples_land` (samples that fall on cells the 5-arcmin template marks as land: 44,351 of 183,151 samples, 24%, mostly bays and estuaries, which no map can represent), `n_pos`, `n_pos_1e4`, `n_pos_1e5`, `max_cells`;
- fit: `fit_status` (none / failed / fitted, from the unclipped layer and cross-checked against `RT_fit_matrix.RData`), `converged`;
- cascade: `use` (viirs / modis / pred = hull), `viirs_status` (positive / zero / missing / no_coverage), `viirs_n_pos_cells`, `viirs_max_freq`, `modis_present`, `modis_n_polys`, `hull_n_polys`, `hull_footprint_km2`;
- bloom area of the unclipped, final, VIIRS-, MODIS- and hull-clipped maps, `retained_1e4` (final / unclipped), `hull_ratio_1e4` (final / hull-clipped);
- samples vs map: how many water-cell samples at or above 10,000 (and 100,000) cells/L sit in a non-zero cell of the final map (`n_pos_1e4_in_fp`, `frac_pos_1e4_in_fp`, ...);
- flags and `pdf_page`.

Flags (thresholds are parameters at the top of the script):

| Flag | Rule | Months |
|---|---|---|
| `zeroed_fit` | a fitted surface exists and the final map is all zero | 58 |
| `zeroed_material` | `zeroed_fit` and the surface reaches 10,000 cells/L somewhere | 16 |
| `low_vs_hull` | satellite-clipped final map keeps < 25% of the hull-clipped bloom area, with at least 5 samples >= 10,000 cells/L | 2 (plus the zeroed months) |
| `samples_outside` | fewer than 50% of the water-cell samples >= 10,000 cells/L sit in a non-zero cell of the final map, with at least 5 such samples | 33 (plus the zeroed months) |

A retention flag (final / unclipped bloom area) was tried first and dropped: the unclipped surface exceeds 10,000 cells/L over more than 90% of the 291,361 km2 of water cells in 181 of the 329 fitted months (median unclipped bloom area 281,089 km2), because the intercept-only lognormal is fit to positive samples only. The unclipped map is therefore not a usable fallback on its own; the clip does all the localisation, and the sample-based hull footprint is the natural reference for "how much did the satellite footprint cut away".

### 1.3 The monthly PDF (`clip_months_issue6.pdf`)

One row per month from 1985-01 to 2026-12, twelve rows per page so each page is one calendar year (42 pages). Columns: **A** the raw FWC samples of the month (viridis-filled circles binned at 1,000 / 10,000 / 100,000 / 1,000,000 cells/L, with the class legend); **B** the unclipped sdmTMB surface; **C** the VIIRS-clipped map with the positive VIIRS cells outlined; **D** the MODIS-clipped map with the nFLH polygons outlined; **E** the hull-clipped map with the footprints outlined. The clipped panel the final map uses (VIIRS if a tif exists, else MODIS, else hulls) has a red frame. Every panel carries a box with three counts: in column A the samples that are positive, at or above 10,000 and at or above 100,000 cells/L; in columns B to E the grid cells of that map above 0, at or above 10,000 and at or above 100,000 cells/L. Raster panels have their own cells/L colour bar. Months with no samples, no fit, no VIIRS tif or no MODIS polygon keep their row with a note in the empty panel, so the sequence is unbroken; the page number of a month is its year minus 1984.

### 1.4 Checks the script enforces

Before anything is plotted the script asserts that the final map equals the chosen clipped layer cell for cell in all 504 months (NA to 0, land to NA, exactly as `make_redtide_ascii()` does), that `clipping_source.csv` matches the stacks (155 VIIRS, 123 MODIS, 226 hull), that 89 of the 155 VIIRS layers have no positive cell, that the fit status read from the layers agrees with `RT_fit_matrix.RData` for every month (329 fitted, 5 failed, 170 not attempted), that every month with a positive sample has a hull footprint, and that the matrix-to-image orientation is right. All pass on the 6 October run.

## 2. Results

### 2.1 Where the months come from

| use | failed | fitted | none | total |
|---|---|---|---|---|
| modis | 1 | 94 | 28 | 123 |
| pred (hull) | 3 | 114 | 109 | 226 |
| viirs | 1 | 121 | 33 | 155 |

VIIRS era (2012-01 to 2024-12), VIIRS layer status by fit status:

| viirs_status | failed | fitted | none | total |
|---|---|---|---|---|
| missing (2022-12, served by MODIS) | 0 | 1 | 0 | 1 |
| positive | 0 | 63 | 3 | 66 |
| zero | 1 | 58 | 30 | 89 |

### 2.2 The 58 fitted months written as all-zero maps

All 58 are VIIRS months whose layer has no positive cell; no MODIS or hull month is zeroed. Of the 58, 17 have at least one sample at or above 100,000 cells/L, 14 have 100 or more positive samples, and **16 have a fitted surface that reaches 10,000 cells/L somewhere** (`zeroed_material`). In the other 42 the fitted surface stays below 10,000 cells/L everywhere (maximum 6,915 cells/L), so for them the zero map differs from the alternatives only below the first colour bin of the PDFs (not nothing for Ecospace, whose foraging response starts at 12,500 cells/L, but small).

The 16 material months, with what the two alternatives already on disk would keep:

| yrmo | n_pos | n >= 1e4 | n >= 1e5 | max cells/L | unclipped bloom km2 | hull-clipped km2 | MODIS-clipped km2 | PDF page |
|---|---|---|---|---|---|---|---|---|
| 201203 | 41 | 14 | 8 | 513,300 | 8,657 | 5,098 | 2,318 | 197 |
| 201303 | 173 | 69 | 15 | 853,300 | 10,402 | 2,292 | 763 | 208 |
| 201603 | 133 | 30 | 2 | 219,333 | 2,208 | 1,601 | 1,144 | 237 |
| 201604 | 246 | 57 | 10 | 1,610,000 | 1,211 | 985 | 227 | 238 |
| 201701 | 274 | 161 | 95 | 5,767,962 | 289,289 | 4,181 | 21,891 | 245 |
| 201702 | 320 | 192 | 85 | 5,944,400 | 260,962 | 7,244 | 10,044 | 246 |
| 201703 | 258 | 98 | 17 | 638,094 | 281,758 | 6,417 | 8,376 | 247 |
| 201704 | 168 | 34 | 5 | 167,000 | 457 | 457 | 0 | 248 |
| 201802 | 82 | 38 | 15 | 881,073 | 249,480 | 7,808 | 8,992 | 257 |
| 201803 | 236 | 153 | 68 | 2,450,000 | 55,038 | 7,061 | 5,322 | 258 |
| 201804 | 190 | 79 | 36 | 4,117,733 | 272,276 | 4,982 | 6,373 | 259 |
| 201805 | 116 | 24 | 5 | 890,633 | 1,150 | 766 | 536 | 260 |
| 201902 | 11 | 4 | 2 | 403,000 | 9,578 | 1,233 | 3,242 | 269 |
| 202001 | 56 | 5 | 0 | 72,333 | 3,397 | 1,694 | 3,397 | 279 |
| 202011 | 37 | 8 | 0 | 60,500 | 687 | 458 | 534 | 286 |
| 202106 | 376 | 230 | 111 | 7,964,888 | 285,799 | 7,361 | 9,106 | 293 |

Totals over the 16: 474 samples at or above 100,000 cells/L; the hull clip would keep 59,637 km2 of bloom area, the MODIS clip 82,266 km2 (15 of the 16 have a MODIS polygon; 2017-04 does not). `fig4_headline_months.png` shows ten of them.

### 2.3 Months the satellite footprint cuts into

Samples at or above 10,000 cells/L on water cells, and how many of them lie outside the final footprint (fitted months with at least 5 such samples):

| clip source | months | samples >= 1e4 | outside the final footprint | share |
|---|---|---|---|---|
| hull | 87 | 4,434 | 0 | 0% (by construction) |
| MODIS | 60 | 4,515 | 789 | 17% |
| VIIRS, layer positive | 60 | 7,841 | 3,186 | 41% |
| VIIRS, layer all zero | 18 | 890 | 890 | 100% |

In the 60 VIIRS-positive fitted months the hull-clipped map has more bloom area than the VIIRS-clipped one in 32; the median share of samples inside the VIIRS footprint is 61%, against 87% for MODIS and 100% for the hull. 23 VIIRS-positive months and 10 MODIS months trip `samples_outside`; two VIIRS-positive months (2018-01 and 2021-04) also trip `low_vs_hull` (2021-04: 7 positive VIIRS cells, 273 positive samples, final bloom area 0 km2, 3% of the samples >= 10,000 cells/L inside the footprint). The full list is in `clip_comparison_summary.md`.

Three VIIRS-positive months (2015-05, 2015-07, 2015-08: 3 positive cells each) have no fitted surface because fewer than six positive samples exist, so they are zero maps for the issue-M2 reason, not a clipping one.

## 3. What the comparison says for #6

- The unclipped maps are already in the repository (`out/5min/plots/sdmTMB log maps.pdf`); what was missing was the side-by-side with samples and alternatives, now in `clip_check_issue6.pdf`, and the per-month numbers, now in the CSV.
- "Drastic difference between clipped and unclipped" is the normal case, not the exception: the fitted surface covers the shelf in most months and the clip removes 90% or more of its bloom area in 178 of the 235 fitted months whose unclipped surface has any bloom area at all (the other 94 fitted surfaces stay below 10,000 cells/L everywhere). The informative comparisons are between the clip sources (satellite vs hull) and between the final map and the samples.
- Two kinds of month stand out: the 58 (16 material) VIIRS-zero months, which is #5; and the VIIRS-positive months where the satellite footprint misses 40% of the sampled bloom on average, which bears on how any VIIRS rule should treat the hull footprint.

## 4. Evidence for #5

1. **The zeros are in the source files.** Every one of the 89 all-zero months is all zero in its tif under `VIIRS/redtide_maps_0.1degree/` (2017_01: 2,571 water cells = 0, 1,004 NA; the same land mask as 2018_09, which has 360 positive cells). Not a stacking, flip or extent artefact; `fn.viirs_tifs2stack()` reproduces the files faithfully.
2. **The mechanism.** `fn.clip_2_viirs()` (`scripts/process_VIIRS.R:114-119`) writes an all-zero layer when `mean(values(r1)) == 0`, and `make_redtide_ascii()` (`scripts/polygon_clipping_rt.R:241-250`) treats a month as VIIRS-served whenever a tif exists, so the zero layer wins over the hull and MODIS alternatives that exist for the same month.
3. **The pattern is seasonal with gaps inside blooms.** By calendar month, the VIIRS layer is all zero in 11 of 13 years in March, April, May and June and in 2 or 3 of 13 years in October, November and December (`fig1_viirs_calendar.png`). That matches the bloom season, but the zero months include 2017-01 to 2017-04 immediately after four positive months (2016-09 to 2016-12) while FWC counted 274, 320, 258 and 168 positives, and 2021-06 (376 positives, 111 at or above 100,000 cells/L) between a positive May and a positive July (`fig2_insitu_vs_viirs.png`). The 89 zero months hold 4,091 in-situ positives and 479 samples at or above 100,000 cells/L; the 66 positive months hold 16,704 and 5,905.
4. **Zero vs no-data.** The published USF dataset of these maps (digitalcommonsdata.usf.edu/datasets/b3ny46b2w2) defines 0 as "no bloom detected during valid observations" and NaN as "no valid observations". Our `_noaa_resize` files carry NaN only on land, never on water, so the files cannot separate "looked and saw nothing" from "no usable retrievals" (cloud, sun glint, CDOM-rich winter water). Whether the all-zero months are the former or the latter is the question for the provider.
5. **The nearshore hypothesis is supported even where the satellite sees the bloom.** In VIIRS-positive months 41% of the water-cell samples at or above 10,000 cells/L fall outside the VIIRS footprint (17% for MODIS). A further 24% of all FWC samples sit in bays and estuaries that the 5-arcmin template marks as land and that no map represents.

## 5. Candidate rules and what each would do

The options from the audit (Doc C §8, M1), with their effect read from the table. Options (c) and (d) are the same rule (the union of the VIIRS and hull footprints) phrased from either side.

| Rule | Effect on the 58 zeroed months | Effect on the 60 VIIRS-positive fitted months | Notes |
|---|---|---|---|
| (a) keep: the satellite is the arbiter in 2012-2024 | the 16 material months stay zero; 474 samples >= 100,000 cells/L are not represented | none | needs the provider to confirm that zero means no bloom |
| (b) fall back to the hull footprint when the VIIRS layer is empty and the month has a fit (`viirs_empty_rule = "hull"`) | restores 59,637 km2 of bloom area over the 16 material months (2017-01..03: 4,181 / 7,244 / 6,417 km2; 2021-06: 7,361 km2); the other 42 get hull maps with values below 10,000 cells/L | none | smallest change; the hull is a conservative, sample-based footprint (10 km buffer) |
| (c)/(d) union of the VIIRS and hull footprints in every VIIRS month | as (b) | adds hull area in the 32 months where the hull footprint exceeds the VIIRS one; covers the 3,186 samples >= 10,000 cells/L (41%) now outside the footprint | changes every VIIRS month with positives, not only the empty ones |
| (e) treat an empty VIIRS layer as missing: fall through to MODIS, then hull | 15 of the 16 material months have a MODIS polygon (82,266 km2 kept); 2017-04 falls to the hull | none | MODIS footprints miss 17% of the sampled bloom and end in 2025-09; the cascade already does this for 2022-12 |

Whichever rule is chosen, the implementation is the config key the audit proposed (`viirs_empty_rule`, default = today's behaviour until decided), a run-log line naming the months affected, and an MD5 before/after table showing that only the intended months changed; the 16 material months (and the 42 others for a value check) are the acceptance panels.

Questions for the data provider (USF Optical Oceanography Lab / NOAA): does an all-zero `*_month_frequency_noaa_resize.tif` mean no detection with valid observations, or no valid observations; is a no-data mask available for 2012-2024; what is the `_noaa` product's relation to the published 2012-2014 VIIRS SNPP maps; are nearshore pixels masked.
