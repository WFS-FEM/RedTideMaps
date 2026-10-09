## Results: non-clipped vs clipped comparison (PR #7)

Task 1 of this issue is done. Everything is in [`docs/issue6/`](https://github.com/WFS-FEM/RedTideMaps/tree/5649829/docs/issue6) on branch `6-nonclipped-comparison-maps` (#7), produced by one tracked script, [`scripts/qa/check_clipping_issue6.R`](https://github.com/WFS-FEM/RedTideMaps/blob/5649829/scripts/qa/check_clipping_issue6.R), from the stacks the 6 Oct 2026 run left on disk. No pipeline code or deliverable changed. The script runs in about 30 s (`Rscript scripts/qa/check_clipping_issue6.R`), checks its inputs with a `stopifnot()` block before plotting, and writes byte-identical tables and figures on every run.

| File | What it is |
|---|---|
| [`README.md`](https://github.com/WFS-FEM/RedTideMaps/blob/5649829/docs/issue6/README.md) | the findings note: what was compared, results, evidence for #5, candidate rules |
| [`clip_comparison_issue6.csv`](https://github.com/WFS-FEM/RedTideMaps/blob/5649829/docs/issue6/clip_comparison_issue6.csv) | one row per month, 1985-01 to 2026-12 (504 rows, 44 columns) |
| [`clip_comparison_summary.md`](https://github.com/WFS-FEM/RedTideMaps/blob/5649829/docs/issue6/clip_comparison_summary.md) | all the tables: counts by source, the 58 zeroed months, the 33 other flagged months |
| [`fig1_viirs_calendar.png`](https://github.com/WFS-FEM/RedTideMaps/blob/5649829/docs/issue6/fig1_viirs_calendar.png) | VIIRS layer status by year and month with the in-situ positives |
| [`fig2_insitu_vs_viirs.png`](https://github.com/WFS-FEM/RedTideMaps/blob/5649829/docs/issue6/fig2_insitu_vs_viirs.png) | monthly in-situ positives vs VIIRS positive cells, 2012-2024 |
| [`fig3_bloom_area_unclipped_vs_final.png`](https://github.com/WFS-FEM/RedTideMaps/blob/5649829/docs/issue6/fig3_bloom_area_unclipped_vs_final.png) | bloom area before and after clipping, by clip source |
| [`fig4_headline_months.png`](https://github.com/WFS-FEM/RedTideMaps/blob/5649829/docs/issue6/fig4_headline_months.png) | ten headline months: unclipped, final, hull alternative, MODIS alternative |
| [`out/5min/plots/clip_check_issue6.pdf`](https://github.com/WFS-FEM/RedTideMaps/blob/5649829/out/5min/plots/clip_check_issue6.pdf) | one page per fitted month (329 pages, 7.7 MB): unclipped + samples + footprint, VIIRS-clipped, MODIS-clipped, hull-clipped; the panel used in the final map has a red frame; page numbers are in the CSV (`pdf_page`) |

### What the comparison shows

**1. The unclipped map is not a usable map on its own.** The intercept-only lognormal is fit to positive samples only, so the fitted surface exceeds 10,000 cells/L over more than 90% of the shelf in 181 of the 329 fitted months (median unclipped bloom area 281,089 of 291,361 km2 of water). The clip does all the localisation and removes 90% or more of the unclipped bloom area in 178 of the 235 fitted months that have any. "Drastic difference between clipped and unclipped" is therefore the normal case, and a retention flag fired on almost every month; it was replaced by two comparisons that do discriminate: the final map against the **hull-clipped alternative** (the sample-based footprint) and against the **samples themselves**.

**2. 58 fitted months are written as all-zero maps, all by an all-zero VIIRS layer.** No MODIS or hull month is zeroed. Only 16 of the 58 have a surface that reaches 10,000 cells/L anywhere (`zeroed_material` in the CSV); in the other 42 the surface stays below 10,000 cells/L everywhere (max 6,915), so for those the zero map differs from the alternatives only below the first colour bin. The 16 hold 474 samples at or above 100,000 cells/L. The hull clip of the same surface, already on disk, would keep 59,637 km2 of bloom area for them and the MODIS clip 82,266 km2:

| yrmo | n_pos | n >= 1e5 | max cells/L | unclipped bloom km2 | hull-clipped km2 | MODIS-clipped km2 | PDF page |
|---|---|---|---|---|---|---|---|
| 201203 | 41 | 8 | 513,300 | 8,657 | 5,098 | 2,318 | 197 |
| 201303 | 173 | 15 | 853,300 | 10,402 | 2,292 | 763 | 208 |
| 201603 | 133 | 2 | 219,333 | 2,208 | 1,601 | 1,144 | 237 |
| 201604 | 246 | 10 | 1,610,000 | 1,211 | 985 | 227 | 238 |
| 201701 | 274 | 95 | 5,767,962 | 289,289 | 4,181 | 21,891 | 245 |
| 201702 | 320 | 85 | 5,944,400 | 260,962 | 7,244 | 10,044 | 246 |
| 201703 | 258 | 17 | 638,094 | 281,758 | 6,417 | 8,376 | 247 |
| 201704 | 168 | 5 | 167,000 | 457 | 457 | 0 | 248 |
| 201802 | 82 | 15 | 881,073 | 249,480 | 7,808 | 8,992 | 257 |
| 201803 | 236 | 68 | 2,450,000 | 55,038 | 7,061 | 5,322 | 258 |
| 201804 | 190 | 36 | 4,117,733 | 272,276 | 4,982 | 6,373 | 259 |
| 201805 | 116 | 5 | 890,633 | 1,150 | 766 | 536 | 260 |
| 201902 | 11 | 2 | 403,000 | 9,578 | 1,233 | 3,242 | 269 |
| 202001 | 56 | 0 | 72,333 | 3,397 | 1,694 | 3,397 | 279 |
| 202011 | 37 | 0 | 60,500 | 687 | 458 | 534 | 286 |
| 202106 | 376 | 111 | 7,964,888 | 285,799 | 7,361 | 9,106 | 293 |

**3. Even where VIIRS sees the bloom, its footprint misses much of the sampled bloom.** Water-cell samples at or above 10,000 cells/L in fitted months with at least five such samples, and how many fall outside the final footprint:

| clip source | months | samples >= 1e4 | outside the final footprint |
|---|---|---|---|
| hull | 87 | 4,434 | 0% (by construction) |
| MODIS | 60 | 4,515 | 17% |
| VIIRS, layer positive | 60 | 7,841 | 41% |
| VIIRS, layer all zero | 18 | 890 | 100% |

In the 60 VIIRS-positive fitted months the hull-clipped map has more bloom area than the VIIRS-clipped one in 32. A further 24% of all FWC samples (44,351 of 183,151) sit in bays and estuaries that the 5-arcmin template marks as land, which no map represents.

**4. Flags** (thresholds are parameters at the top of the script): `zeroed_fit` 58 months; `low_vs_hull` (satellite-clipped map keeps < 25% of the hull-clipped bloom area) 2 more months, 2018-01 and 2021-04; `samples_outside` (< 50% of the samples >= 10,000 cells/L inside the footprint) 33 months, 23 of them VIIRS-positive and 10 MODIS. Three VIIRS-positive months (2015-05, 2015-07, 2015-08) have no fit because fewer than six positive samples exist, which is the M2 question, not a clipping one.

![VIIRS calendar](https://raw.githubusercontent.com/WFS-FEM/RedTideMaps/5649829/docs/issue6/fig1_viirs_calendar.png)

![Headline months](https://raw.githubusercontent.com/WFS-FEM/RedTideMaps/5649829/docs/issue6/fig4_headline_months.png)

### Reading the PDF

Each page is one fitted month, in the palette of the pipeline PDFs (white below 10,000 cells/L). Panel 1 is the unclipped surface with every sample of the month (viridis-filled circles for positives, binned at 1,000 / 10,000 / 100,000 / 1,000,000 cells/L) and the outline of the footprint the final map used; panels 2 to 4 are the VIIRS-, MODIS- and hull-clipped maps with their own footprint outlines. The used panel has a red frame; the page title gives the source, the sample counts, the final bloom area as a share of the hull-clipped one, how many samples >= 10,000 cells/L sit inside the footprint, and the flags.

### Task 2 of this issue

Updating the decision logic is tracked in #5. The candidate rules and what each would do, read straight from the table, are in [`README.md` section 5](https://github.com/WFS-FEM/RedTideMaps/blob/5649829/docs/issue6/README.md#5-candidate-rules-and-what-each-would-do): keep as is; fall back to the hull when the VIIRS layer is empty (restores 59,637 km2 over the 16 material months, changes nothing else); union of VIIRS and hull in every VIIRS month (also covers the 41% of samples the satellite footprint misses); or treat an empty layer as missing and fall through to MODIS (15 of the 16 have a MODIS polygon). Section 4 lists the evidence for #5 and the questions for the data provider.
