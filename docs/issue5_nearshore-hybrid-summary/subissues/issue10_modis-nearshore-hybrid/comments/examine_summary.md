# Issue #10: the mask5 nearshore rule on the MODIS months (examine stage)

Produced by `docs/issue5_nearshore-hybrid-summary/subissues/issue10_modis-nearshore-hybrid/check_modis_hybrid_issue10.R` (stage `examine`) from the stacks of the last pipeline run: the MODIS-clipped layers of the 123 months the cascade serves from MODIS (equal to the delivered 6 October 2026 maps for those months, checked), the hull-clipped layers of the same months and the `mask5` set (136 cells, 10,227 km2). The hybrid is max(MODIS-clipped, hull-clipped) inside the set and the MODIS-clipped layer outside it. Bloom area = km2 of cells at or above 10,000 cells/L; exposure = the plain sum of cells/L over the 3,838 water cells; samples included = water-cell samples at or above 10,000 cells/L (and the high class, above 1,000,000) whose cell is non-zero in the map. Yearly and group totals are sums over the months.

## Overall

- Over the 123 MODIS months the rule changes 87 maps, raises the summed bloom area by 2.1% (1,343,000 to 1,371,529 km2) and total exposure by 2.3% (2,374,510,206 to 2,429,024,938 cells/L summed), and lifts the share of the in-situ water samples >= 10,000 cells/L that the projection includes from 82.4% to 89.0% (3,736 to 4,035 of 4,535; +6.6 percentage points); for the high samples (> 1,000,000 cells/L) from 88.9% to 93.4% (of 442).
- MODIS has no coastal no-data band: 132 of the 136 set cells are MODIS-positive in at least one of the 123 months; the 2,123 water cells MODIS never marks positive sit a median 230 km from the coast (4 of them within 5 km).
- Of the 799 excluded samples >= 10,000 cells/L, 301 lie in the set and 299 of those are recovered; the rest are offshore (median 11.9 km from the coast; 39% of the excluded within 5 km) where MODIS looked and saw nothing. Within 5 km of the coast the included share goes 87.8% -> 98.9%, beyond 5 km 75.4% -> 76.1%.
- Months with at least 5 such samples and under half of them included: 10 before, 2 after. Months with such samples but no cell >= 10,000 cells/L: 8 before, 7 after. All-zero MODIS maps: 29 before and after (no hull inside the set in those months).

## Totals by month group (`tables/examine_groups_issue10.csv`)

| group | n_months | months_changed | months_all_zero | a1e4_km2_before | a1e4_km2_after | exposure_before | exposure_after | exposure_ratio | cellmonths_ge1e4_before | cellmonths_ge1e4_after | cellmonths_ge1e5_before | cellmonths_ge1e5_after | cellmonths_ge1e6_before | cellmonths_ge1e6_after | samples_ge1e4 | samples_ge1e4_in_before | samples_ge1e4_in_after | share_samples_ge1e4_before | share_samples_ge1e4_after | samples_high | share_samples_high_before | share_samples_high_after |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| all 123 MODIS months | 123 | 87 | 29 | 1,343,000 | 1,371,529 | 2,374,510,206 | 2,429,024,938 | 1.023 | 17,766 | 18,144 | 4,936 | 5,035 | 352 | 363 | 4,535 | 3,736 | 4,035 | 0.824 | 0.89 | 442 | 0.889 | 0.934 |
| the 113 months of 2002-2011 | 113 | 81 | 25 | 1,289,950 | 1,315,838 | 2,235,637,076 | 2,287,822,891 | 1.023 | 17,069 | 17,412 | 4,692 | 4,785 | 320 | 331 | 4,244 | 3,481 | 3,760 | 0.82 | 0.886 | 404 | 0.889 | 0.931 |
| the 10 months of 2022-12 and 2025 | 10 | 6 | 4 | 53,050 | 55,691 | 138,873,130 | 141,202,047 | 1.017 | 697 | 732 | 244 | 250 | 32 | 32 | 291 | 255 | 275 | 0.876 | 0.945 | 38 | 0.895 | 0.974 |
| the 60 months with at least 5 water samples >= 10,000 cells/L | 60 | 54 | 0 | 1,330,332 | 1,358,172 | 2,361,926,263 | 2,415,952,429 | 1.023 | 17,601 | 17,970 | 4,936 | 5,035 | 352 | 363 | 4,515 | 3,726 | 4,021 | 0.825 | 0.891 | 442 | 0.889 | 0.934 |
| the 10 of those with under half of them included before | 10 | 10 | 0 | 153,291 | 160,039 | 86,507,171 | 91,048,799 | 1.053 | 2,031 | 2,120 | 17 | 27 | 4 | 4 | 342 | 122 | 230 | 0.357 | 0.673 | 18 | 0.056 | 0.333 |
| the 8 months with such samples but no cell >= 10,000 cells/L before | 8 | 6 | 2 | 0 | 153 | 7,538,832 | 7,694,934 | 1.021 | 0 | 2 | 0 | 0 | 0 | 0 | 28 | 19 | 22 | 0.679 | 0.786 | 0 |  |  |

## By year (`tables/examine_annual_issue10.csv`; sums over the months of the year)

| year | n_months | months_changed | months_all_zero | a1e4_km2_before | a1e4_km2_after | exposure_before | exposure_after | exposure_ratio | cellmonths_ge1e4_before | cellmonths_ge1e4_after | cellmonths_ge1e5_before | cellmonths_ge1e5_after | cellmonths_ge1e6_before | cellmonths_ge1e6_after | samples_ge1e4 | samples_ge1e4_in_before | samples_ge1e4_in_after | share_samples_ge1e4_before | share_samples_ge1e4_after | samples_high | share_samples_high_before | share_samples_high_after |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 2002 | 6 | 4 | 0 | 113,696 | 115,658 | 41,617,080 | 42,554,241 | 1.023 | 1,506 | 1,532 | 10 | 11 | 0 | 0 | 152 | 96 | 118 | 0.632 | 0.776 | 4 | 0.75 | 1 |
| 2003 | 12 | 12 | 0 | 224,295 | 233,155 | 159,774,672 | 169,299,558 | 1.06 | 2,974 | 3,091 | 166 | 198 | 6 | 6 | 707 | 419 | 548 | 0.593 | 0.775 | 29 | 0.621 | 0.724 |
| 2004 | 12 | 5 | 5 | 115,099 | 116,462 | 72,888,362 | 74,079,355 | 1.016 | 1,527 | 1,545 | 84 | 87 | 7 | 7 | 181 | 145 | 151 | 0.801 | 0.834 | 5 | 1 | 1 |
| 2005 | 12 | 12 | 0 | 390,189 | 396,631 | 1,185,422,329 | 1,205,416,611 | 1.017 | 5,162 | 5,248 | 2,777 | 2,811 | 193 | 199 | 1,323 | 1,176 | 1,218 | 0.889 | 0.921 | 139 | 0.95 | 0.964 |
| 2006 | 11 | 10 | 1 | 144,593 | 147,186 | 303,432,823 | 317,525,687 | 1.046 | 1,909 | 1,943 | 491 | 502 | 59 | 64 | 1,143 | 998 | 1,039 | 0.873 | 0.909 | 137 | 0.949 | 0.993 |
| 2007 | 12 | 9 | 3 | 108,021 | 111,162 | 111,483,912 | 116,868,164 | 1.048 | 1,430 | 1,472 | 227 | 238 | 1 | 1 | 274 | 223 | 258 | 0.814 | 0.942 | 18 | 0.667 | 0.944 |
| 2008 | 12 | 4 | 7 | 7,863 | 8,325 | 5,012,017 | 5,184,749 | 1.034 | 102 | 108 | 0 | 0 | 0 | 0 | 61 | 54 | 55 | 0.885 | 0.902 | 0 |  |  |
| 2009 | 12 | 8 | 3 | 95,665 | 96,199 | 50,773,952 | 50,989,476 | 1.004 | 1,265 | 1,272 | 39 | 39 | 4 | 4 | 112 | 82 | 83 | 0.732 | 0.741 | 17 | 0.235 | 0.235 |
| 2010 | 12 | 7 | 5 | 0 | 0 | 5,635,532 | 5,679,426 | 1.008 | 0 | 0 | 0 | 0 | 0 | 0 | 12 | 12 | 12 | 1 | 1 | 0 |  |  |
| 2011 | 12 | 10 | 1 | 90,529 | 91,061 | 299,596,397 | 300,225,624 | 1.002 | 1,194 | 1,201 | 898 | 899 | 50 | 50 | 279 | 276 | 278 | 0.989 | 0.996 | 55 | 1 | 1 |
| 2022 | 1 | 1 | 0 | 22,861 | 23,830 | 36,343,880 | 36,862,374 | 1.014 | 301 | 314 | 33 | 34 | 7 | 7 | 122 | 118 | 120 | 0.967 | 0.984 | 23 | 0.957 | 0.957 |
| 2025 | 9 | 5 | 4 | 30,189 | 31,861 | 102,529,250 | 104,339,673 | 1.018 | 396 | 418 | 211 | 216 | 25 | 25 | 169 | 137 | 155 | 0.811 | 0.917 | 15 | 0.8 | 1 |

## Samples >= 10,000 cells/L by distance to the coast (`tables/excluded_bands_issue10.csv`)

| band | n_samples_ge1e4 | n_in_set | excluded_before | excluded_in_set | recovered | excluded_after | share_included_before | share_included_after |
|---|---|---|---|---|---|---|---|---|
| 0-2 km | 1,939 | 1,924 | 250 | 247 | 247 | 3 | 0.871 | 0.998 |
| 2-5 km | 617 | 487 | 63 | 41 | 39 | 24 | 0.898 | 0.961 |
| 5-10 km | 661 | 304 | 67 | 13 | 13 | 54 | 0.899 | 0.918 |
| > 10 km | 1,318 | 0 | 419 | 0 | 0 | 419 | 0.682 | 0.682 |
| all | 4,535 | 2,715 | 799 | 301 | 299 | 500 | 0.824 | 0.89 |

## The 20 months of fig 1 (`tables/examine_months_issue10.csv`): the 12 largest gains in samples included, then the 8 with samples but no bloom cell

| yrmo | fit_status | modis_n_polys | cells_changed | a1e4_km2_before | a1e4_km2_after | exposure_before | exposure_after | n_ge1e4_before | n_ge1e4_after | samples_ge1e4 | samples_ge1e4_in_before | samples_ge1e4_in_after |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 200607 | fitted | 19 | 12 | 9,702 | 10,615 | 34,442,333 | 44,421,452 | 128 | 140 | 104 | 67 | 93 |
| 200302 | fitted | 51 | 14 | 11,741 | 12,278 | 2,217,751 | 2,503,381 | 156 | 163 | 41 | 1 | 24 |
| 200308 | fitted | 41 | 15 | 18,709 | 19,854 | 18,918,104 | 20,571,483 | 248 | 263 | 79 | 38 | 60 |
| 200208 | fitted | 49 | 12 | 11,509 | 12,422 | 3,106,966 | 3,556,405 | 152 | 164 | 47 | 7 | 27 |
| 200307 | fitted | 45 | 14 | 14,306 | 15,366 | 6,231,307 | 7,109,764 | 189 | 203 | 70 | 33 | 53 |
| 200701 | fitted | 27 | 6 | 17,902 | 18,360 | 13,388,939 | 13,810,031 | 236 | 242 | 65 | 35 | 55 |
| 200305 | fitted | 31 | 21 | 11,896 | 12,888 | 3,303,395 | 4,324,065 | 157 | 170 | 80 | 46 | 62 |
| 200509 | fitted | 32 | 13 | 79,367 | 80,330 | 468,307,846 | 469,313,771 | 1,053 | 1,066 | 337 | 321 | 335 |
| 200306 | fitted | 59 | 12 | 11,631 | 12,545 | 4,287,650 | 4,719,595 | 153 | 165 | 35 | 17 | 29 |
| 200608 | fitted | 37 | 11 | 14,754 | 15,593 | 22,245,893 | 25,516,583 | 195 | 206 | 210 | 166 | 178 |
| 200304 | fitted | 30 | 15 | 13,049 | 14,191 | 17,860,376 | 19,621,327 | 172 | 187 | 126 | 96 | 107 |
| 202501 | fitted | 38 | 12 | 23,519 | 24,427 | 94,466,033 | 95,498,505 | 308 | 320 | 112 | 97 | 108 |
| 200601 | fitted | 28 | 1 | 0 | 0 | 1,682,709 | 1,686,085 | 0 | 0 | 8 | 7 | 7 |
| 200802 | none | 32 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 3 | 0 | 0 |
| 200803 | none | 35 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 2 | 0 | 0 |
| 200804 | fitted | 27 | 20 | 0 | 0 | 211,225 | 276,181 | 0 | 0 | 1 | 0 | 1 |
| 200904 | fitted | 27 | 4 | 0 | 153 | 151,446 | 190,517 | 0 | 2 | 1 | 0 | 1 |
| 201001 | fitted | 71 | 1 | 0 | 0 | 2,269,656 | 2,276,289 | 0 | 0 | 10 | 10 | 10 |
| 201002 | fitted | 80 | 2 | 0 | 0 | 2,790,714 | 2,803,908 | 0 | 0 | 2 | 2 | 2 |
| 201108 | fitted | 27 | 11 | 0 | 0 | 433,082 | 461,954 | 0 | 0 | 1 | 0 | 1 |

## Water cells MODIS never marks positive, by distance to the coast (`tables/modis_never_positive_bands_issue10.csv`)

| band | water_cells | never_modis_positive | share_never | set_cells | set_cells_never |
|---|---|---|---|---|---|
| 0-2 km | 72 | 2 | 0.028 | 64 | 2 |
| 2-5 km | 75 | 2 | 0.027 | 68 | 1 |
| 5-10 km | 89 | 1 | 0.011 | 4 | 1 |
| > 10 km | 3,602 | 2,118 | 0.588 | 0 | 0 |

