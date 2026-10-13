# Clipped vs unclipped comparison (issue #6)

Inputs: `sdmTMB_log_stack_198501-202612` (unclipped), the three clipped stacks, the combined stack, `clipping_source.csv`, `hull_diagnostics.csv`, `RT_fit_matrix.RData`, `FWC HAB data 19800102-20260922_filtered.Rdata`, `VIIRS_201201-202412`.
Bloom area = km2 of grid cells >= 10,000 cells/L (`area_1e4_*`) or >= 1e+05 cells/L (`area_1e5_*`), land masked. Flags: `zeroed_fit` (fitted surface, final map all zero); `low_vs_hull` (satellite-clipped final map keeps < 25% of the hull-clipped bloom area, >= 5 samples >= 1e4); `samples_outside` (< 50% of water-cell samples >= 1e4 sit in a non-zero final cell, >= 5 such samples).

The unclipped surface is not a usable map on its own: in 181 of 329 fitted months it exceeds 10,000 cells/L over more than 90% of the 291,361 km2 of water cells (median unclipped bloom area 281,089 km2), because the intercept-only lognormal is fit to positive samples only. The clip therefore does all the localisation, and `retained_1e4` (final / unclipped bloom area) is reported for completeness but not flagged; `hull_ratio_1e4` (final / hull-clipped bloom area) is the comparison between the satellite footprint and the sample-based footprint.

## Months by clip source and fit status

| use | failed | fitted | none | total |
|---|---|---|---|---|
| modis | 1 | 94 | 28 | 123 |
| pred | 3 | 114 | 109 | 226 |
| viirs | 1 | 121 | 33 | 155 |

## VIIRS era (201201-202412): VIIRS layer status by fit status

| viirs_status | failed | fitted | none | total |
|---|---|---|---|---|
| missing | 0 | 1 | 0 | 1 |
| positive | 0 | 63 | 3 | 66 |
| zero | 1 | 58 | 30 | 89 |

## VIIRS layer status by calendar month (VIIRS era)

| month | missing | positive | zero |
|---|---|---|---|
| Jan | 0 | 7 | 6 |
| Feb | 0 | 4 | 9 |
| Mar | 0 | 2 | 11 |
| Apr | 0 | 2 | 11 |
| May | 0 | 2 | 11 |
| Jun | 0 | 2 | 11 |
| Jul | 0 | 5 | 8 |
| Aug | 0 | 4 | 9 |
| Sep | 0 | 8 | 5 |
| Oct | 0 | 10 | 3 |
| Nov | 0 | 11 | 2 |
| Dec | 1 | 9 | 3 |

## Fitted months written as all-zero maps (58)

`area_1e4_hull_km2` and `area_1e4_modis_km2` are what the hull and MODIS clips of the same surface keep (the alternatives already on disk); `n_pos_1e4_water` counts samples >= 1e4 cells/L on water cells of the grid.

| yrmo | n_pos | n_pos_1e4 | n_pos_1e5 | max_cells | converged | area_1e4_unclip_km2 | area_1e4_hull_km2 | area_1e4_modis_km2 | n_pos_1e4_water | pdf_page |
|---|---|---|---|---|---|---|---|---|---|---|
| 201202 | 12 | 0 | 0 | 5,000 | TRUE | 0 | 0 | 0 | 0 | 196 |
| 201203 | 41 | 14 | 8 | 513,300 | TRUE | 8,657 | 5,098 | 2,318 | 13 | 197 |
| 201204 | 20 | 1 | 0 | 11,000 | TRUE | 0 | 0 | 0 | 1 | 198 |
| 201205 | 8 | 0 | 0 | 1,000 | TRUE | 0 | 0 | 0 | 0 | 199 |
| 201206 | 42 | 2 | 0 | 80,300 | TRUE | 0 | 0 | 0 | 1 | 200 |
| 201208 | 23 | 0 | 0 | 6,300 | TRUE | 0 | 0 | 0 | 0 | 201 |
| 201303 | 173 | 69 | 15 | 853,300 | TRUE | 10,402 | 2,292 | 763 | 49 | 208 |
| 201304 | 133 | 9 | 2 | 352,600 | TRUE | 0 | 0 | 0 | 9 | 209 |
| 201305 | 85 | 0 | 0 | 5,000 | TRUE | 0 | 0 | 0 | 0 | 210 |
| 201306 | 19 | 0 | 0 | 5,667 | TRUE | 0 | 0 | 0 | 0 | 211 |
| 201308 | 6 | 0 | 0 | 1,000 | FALSE | 0 | 0 | 0 | 0 | 213 |
| 201309 | 20 | 1 | 0 | 11,000 | TRUE | 0 | 0 | 0 | 1 | 214 |
| 201310 | 113 | 13 | 2 | 133,000 | TRUE | 0 | 0 | 0 | 9 | 215 |
| 201401 | 15 | 0 | 0 | 3,000 | TRUE | 0 | 0 | 0 | 0 | 218 |
| 201402 | 16 | 0 | 0 | 2,000 | TRUE | 0 | 0 | 0 | 0 | 219 |
| 201403 | 17 | 0 | 0 | 1,000 | TRUE | 0 | 0 | 0 | 0 | 220 |
| 201404 | 27 | 0 | 0 | 1,000 | TRUE | 0 | 0 | 0 | 0 | 221 |
| 201405 | 17 | 0 | 0 | 2,000 | TRUE | 0 | 0 | 0 | 0 | 222 |
| 201406 | 15 | 0 | 0 | 2,300 | TRUE | 0 | 0 | 0 | 0 | 223 |
| 201503 | 11 | 0 | 0 | 667 | TRUE | 0 | 0 | 0 | 0 | 229 |
| 201603 | 133 | 30 | 2 | 219,333 | TRUE | 2,208 | 1,601 | 1,144 | 27 | 237 |
| 201604 | 246 | 57 | 10 | 1,610,000 | TRUE | 1,211 | 985 | 227 | 41 | 238 |
| 201605 | 79 | 5 | 0 | 51,000 | TRUE | 0 | 0 | 0 | 3 | 239 |
| 201608 | 36 | 0 | 0 | 1,667 | TRUE | 0 | 0 | 0 | 0 | 240 |
| 201701 | 274 | 161 | 95 | 5,767,962 | TRUE | 289,289 | 4,181 | 21,891 | 116 | 245 |
| 201702 | 320 | 192 | 85 | 5,944,400 | TRUE | 260,962 | 7,244 | 10,044 | 129 | 246 |
| 201703 | 258 | 98 | 17 | 638,094 | TRUE | 281,758 | 6,417 | 8,376 | 59 | 247 |
| 201704 | 168 | 34 | 5 | 167,000 | TRUE | 457 | 457 | 0 | 21 | 248 |
| 201705 | 79 | 3 | 0 | 15,500 | TRUE | 0 | 0 | 0 | 0 | 249 |
| 201706 | 37 | 3 | 0 | 10,500 | TRUE | 0 | 0 | 0 | 2 | 250 |
| 201707 | 17 | 0 | 0 | 1,000 | TRUE | 0 | 0 | 0 | 0 | 251 |
| 201708 | 8 | 0 | 0 | 1,333 | TRUE | 0 | 0 | 0 | 0 | 252 |
| 201802 | 82 | 38 | 15 | 881,073 | TRUE | 249,480 | 7,808 | 8,992 | 31 | 257 |
| 201803 | 236 | 153 | 68 | 2,450,000 | TRUE | 55,038 | 7,061 | 5,322 | 96 | 258 |
| 201804 | 190 | 79 | 36 | 4,117,733 | TRUE | 272,276 | 4,982 | 6,373 | 60 | 259 |
| 201805 | 116 | 24 | 5 | 890,633 | TRUE | 1,150 | 766 | 536 | 23 | 260 |
| 201902 | 11 | 4 | 2 | 403,000 | TRUE | 9,578 | 1,233 | 3,242 | 4 | 269 |
| 201904 | 6 | 0 | 0 | 667 | TRUE | 0 | 0 | 0 | 0 | 270 |
| 201905 | 49 | 0 | 0 | 9,000 | TRUE | 0 | 0 | 0 | 0 | 271 |
| 201906 | 14 | 0 | 0 | 667 | TRUE | 0 | 0 | 0 | 0 | 272 |
| 201907 | 6 | 0 | 0 | 667 | TRUE | 0 | 0 | 0 | 0 | 273 |
| 201908 | 13 | 1 | 0 | 11,333 | TRUE | 0 | 0 | 0 | 1 | 274 |
| 202001 | 56 | 5 | 0 | 72,333 | TRUE | 3,397 | 1,694 | 3,397 | 5 | 279 |
| 202002 | 14 | 1 | 0 | 26,000 | TRUE | 0 | 0 | 0 | 0 | 280 |
| 202003 | 14 | 0 | 0 | 9,333 | TRUE | 0 | 0 | 0 | 0 | 281 |
| 202005 | 9 | 0 | 0 | 3,667 | TRUE | 0 | 0 | 0 | 0 | 282 |
| 202008 | 9 | 1 | 0 | 11,667 | TRUE | 0 | 0 | 0 | 0 | 283 |
| 202009 | 13 | 0 | 0 | 1,333 | TRUE | 0 | 0 | 0 | 0 | 284 |
| 202010 | 8 | 0 | 0 | 1,333 | TRUE | 0 | 0 | 0 | 0 | 285 |
| 202011 | 37 | 8 | 0 | 60,500 | TRUE | 687 | 458 | 534 | 5 | 286 |
| 202106 | 376 | 230 | 111 | 7,964,888 | TRUE | 285,799 | 7,361 | 9,106 | 188 | 293 |
| 202112 | 32 | 1 | 0 | 74,667 | TRUE | 0 | 0 | 0 | 1 | 299 |
| 202205 | 13 | 0 | 0 | 6,667 | TRUE | 0 | 0 | 0 | 0 | 300 |
| 202206 | 10 | 0 | 0 | 2,333 | TRUE | 0 | 0 | 0 | 0 | 301 |
| 202208 | 6 | 0 | 0 | 667 | FALSE | 0 | 0 | 0 | 0 | 302 |
| 202305 | 171 | 20 | 1 | 184,500 | TRUE | 0 | 0 | 0 | 9 | 310 |
| 202306 | 13 | 0 | 0 | 667 | TRUE | 0 | 0 | 0 | 0 | 311 |
| 202310 | 33 | 0 | 0 | 4,500 | TRUE | 0 | 0 | 0 | 0 | 312 |

Of these 58 months, 16 have a fitted surface that reaches 10,000 cells/L somewhere (`zeroed_material`): 201203, 201303, 201603, 201604, 201701, 201702, 201703, 201704, 201802, 201803, 201804, 201805, 201902, 202001, 202011, 202106. For them the hull clip would keep 59,637 km2 of bloom area in total and the MODIS clip 82,266 km2 (16 months have a MODIS polygon). In the other 42 months the fitted surface stays below 10,000 cells/L everywhere (max 6,915 cells/L), so the zero map differs from the alternatives only below the first colour bin of the map PDFs.

## Other flagged months (33)

| yrmo | use | viirs_status | n_pos | n_pos_1e4 | n_pos_1e5 | area_1e4_final_km2 | area_1e4_hull_km2 | hull_ratio_1e4 | n_pos_1e4_water | frac_pos_1e4_in_fp | flag_low_vs_hull | flag_samples_outside | pdf_page |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 200208 | modis | no_coverage | 111 | 55 | 17 | 11,509.18 | 6,839.71 | 1.68 | 47 | 0.15 | FALSE | TRUE | 108 |
| 200302 | modis | no_coverage | 105 | 52 | 14 | 11,741.08 | 3,768.61 | 3.12 | 41 | 0.02 | FALSE | TRUE | 114 |
| 200306 | modis | no_coverage | 92 | 44 | 9 | 11,631.26 | 8,378.99 | 1.39 | 35 | 0.49 | FALSE | TRUE | 118 |
| 200307 | modis | no_coverage | 165 | 87 | 27 | 14,306.00 | 14,048.03 | 1.02 | 70 | 0.47 | FALSE | TRUE | 119 |
| 200308 | modis | no_coverage | 157 | 91 | 36 | 18,709.28 | 10,798.15 | 1.73 | 79 | 0.48 | FALSE | TRUE | 120 |
| 200312 | modis | no_coverage | 45 | 20 | 3 | 20,914.57 | 3,647.28 | 5.73 | 19 | 0.47 | FALSE | TRUE | 124 |
| 200504 | modis | no_coverage | 56 | 14 | 4 | 13,439.33 | 3,727.10 | 3.61 | 5 | 0.20 | FALSE | TRUE | 135 |
| 200606 | modis | no_coverage | 33 | 10 | 4 | 9,714.83 | 1,455.63 | 6.67 | 9 | 0.33 | FALSE | TRUE | 147 |
| 200702 | modis | no_coverage | 30 | 10 | 3 | 12,319.39 | 12,741.99 | 0.97 | 9 | 0.33 | FALSE | TRUE | 155 |
| 200911 | modis | no_coverage | 65 | 28 | 21 | 29,005.74 | 2,833.59 | 10.24 | 28 | 0.36 | FALSE | TRUE | 175 |
| 201201 | viirs | positive | 91 | 34 | 17 | 6,482.49 | 4,353.61 | 1.49 | 29 | 0.45 | FALSE | TRUE | 195 |
| 201209 | viirs | positive | 163 | 20 | 0 | 76.30 | 152.49 | 0.50 | 13 | 0.38 | FALSE | TRUE | 202 |
| 201211 | viirs | positive | 499 | 359 | 147 | 2,912.88 | 9,554.40 | 0.30 | 290 | 0.23 | FALSE | TRUE | 204 |
| 201212 | viirs | positive | 247 | 102 | 40 | 2,527.42 | 7,697.00 | 0.33 | 75 | 0.32 | FALSE | TRUE | 205 |
| 201302 | viirs | positive | 403 | 297 | 174 | 3,217.37 | 6,433.97 | 0.50 | 201 | 0.46 | FALSE | TRUE | 207 |
| 201409 | viirs | positive | 122 | 60 | 30 | 3,809.02 | 7,013.83 | 0.54 | 60 | 0.23 | FALSE | TRUE | 226 |
| 201410 | viirs | positive | 59 | 18 | 10 | 1,051.47 | 2,738.74 | 0.38 | 18 | 0.00 | FALSE | TRUE | 227 |
| 201511 | viirs | positive | 312 | 231 | 162 | 11,669.62 | 11,944.97 | 0.98 | 158 | 0.49 | FALSE | TRUE | 233 |
| 201601 | viirs | positive | 349 | 270 | 158 | 3,976.50 | 7,391.24 | 0.54 | 206 | 0.18 | FALSE | TRUE | 235 |
| 201602 | viirs | positive | 324 | 209 | 95 | 3,910.06 | 9,911.00 | 0.40 | 136 | 0.18 | FALSE | TRUE | 236 |
| 201611 | viirs | positive | 391 | 308 | 195 | 18,235.31 | 16,473.50 | 1.11 | 218 | 0.46 | FALSE | TRUE | 243 |
| 201612 | viirs | positive | 299 | 203 | 111 | 6,052.98 | 9,059.93 | 0.67 | 136 | 0.39 | FALSE | TRUE | 244 |
| 201710 | viirs | positive | 70 | 9 | 0 | 0.00 | 0.00 |  | 9 | 0.00 | FALSE | TRUE | 253 |
| 201712 | viirs | positive | 224 | 109 | 54 | 10,051.38 | 6,349.47 | 1.58 | 80 | 0.46 | FALSE | TRUE | 255 |
| 201801 | viirs | positive | 116 | 67 | 24 | 1,456.01 | 10,150.27 | 0.14 | 46 | 0.15 | TRUE | TRUE | 256 |
| 201812 | viirs | positive | 145 | 74 | 21 | 8,451.43 | 2,970.28 | 2.85 | 38 | 0.32 | FALSE | TRUE | 267 |
| 201901 | viirs | positive | 165 | 75 | 38 | 3,761.53 | 14,312.43 | 0.26 | 57 | 0.19 | FALSE | TRUE | 268 |
| 201912 | viirs | positive | 108 | 39 | 16 | 7,006.10 | 6,129.57 | 1.14 | 29 | 0.34 | FALSE | TRUE | 278 |
| 202102 | viirs | positive | 147 | 72 | 24 | 3,852.46 | 5,808.55 | 0.66 | 59 | 0.41 | FALSE | TRUE | 289 |
| 202104 | viirs | positive | 273 | 124 | 38 | 0.00 | 4,131.97 | 0.00 | 75 | 0.03 | TRUE | TRUE | 291 |
| 202105 | viirs | positive | 298 | 135 | 41 | 2,979.08 | 7,785.67 | 0.38 | 103 | 0.39 | FALSE | TRUE | 292 |
| 202111 | viirs | positive | 226 | 91 | 28 | 20,425.26 | 18,257.29 | 1.12 | 75 | 0.39 | FALSE | TRUE | 298 |
| 202304 | viirs | positive | 270 | 93 | 19 | 3,512.49 | 9,448.28 | 0.37 | 65 | 0.40 | FALSE | TRUE | 309 |

## Samples inside the final footprint, fitted months with >= 5 water samples >= 1e4 cells/L

`median_frac_pos_1e4_in_fp`: median share of those samples whose grid cell is non-zero in the final map. For VIIRS-positive months this tests whether the satellite footprint covers the sampled bloom (the nearshore hypothesis in #5).

| use | months | median_retained_1e4 | median_frac_pos_1e4_in_fp | months_lt_half_in_fp |
|---|---|---|---|---|
| modis | 60 | 0.08 | 0.87 | 10 |
| pred | 87 | 0.02 | 1.00 | 0 |
| viirs | 78 | 0.03 | 0.46 | 41 |

| subset | months | median_retained_1e4 | median_frac_pos_1e4_in_fp | months_lt_half_in_fp |
|---|---|---|---|---|
| VIIRS positive | 60 | 0.05 | 0.61 | 23 |
| VIIRS all-zero | 18 | 0.00 | 0.00 | 18 |

## VIIRS-positive months without a fitted surface (3)

The satellite saw a bloom but fewer than 6 positive samples exist, so the prediction is all NA and the clip writes zeros (issue M2 territory, not a clipping fault).

| yrmo | fit_status | n_pos | viirs_n_pos_cells | area_1e4_final_km2 |
|---|---|---|---|---|
| 201505 | none | 3 | 3 | 0 |
| 201507 | none | 2 | 3 | 0 |
| 201508 | none | 2 | 3 | 0 |

