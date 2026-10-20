# Issue #11: VIIRS-only vs nearshore-hybrid maps (from the two pipeline runs)

Produced by `docs/issue11_nearshore-hybrid-pipeline/check_hybrid_issue11.R` (stage `compare`) from the combined stacks of the `none` run (the 6 October 2026 maps) and the `mask5` run. Bloom area is km2 of water cells at or above 10,000 (`a1e4`) or 100,000 cells/L (`a1e5`); `mean_cells_water` is the mean of the map over every template water cell (what Ecospace reads); samples are FWC water-cell samples whose 5-arcmin cell is non-zero in the map. MODIS and hull months are identical in the two runs (checked); the 155 VIIRS months are compared.

## Totals by month group (`tables/groups_issue11.csv`)

| group | n_months | months_changed | a1e4_km2_before | a1e4_km2_after | a1e4_ratio | a1e5_km2_before | a1e5_km2_after | months_with_bloom_before | months_with_bloom_after | mean_cells_water_before | mean_cells_water_after | n_ge1e4 | share_ge1e4_before | share_ge1e4_after | n_high | share_high_before | share_high_after |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| all 155 VIIRS months | 155 | 121 | 776,173 | 898,477 | 1.16 | 427,929 | 475,626 | 58 | 75 | 6,925.2 | 7,628.8 | 8,745 | 0.532 | 0.951 | 1,168 | 0.637 | 0.985 |
| the 58 zeroed months | 58 | 58 | 0 | 21,750 |  | 0 | 5,805 | 0 | 16 | 0 | 137 | 904 | 0 | 0.855 | 32 | 0 | 0.875 |
| the 16 headline months | 16 | 16 | 0 | 21,750 |  | 0 | 5,805 | 0 | 16 | 0 | 479.5 | 867 | 0 | 0.859 | 32 | 0 | 0.875 |
| the 60 VIIRS-positive fitted months of #6 | 60 | 60 | 776,173 | 876,727 | 1.13 | 427,929 | 469,821 | 58 | 59 | 17,889.9 | 19,575 | 7,841 | 0.594 | 0.962 | 1,136 | 0.655 | 0.988 |
| the 66 VIIRS-positive months | 66 | 63 | 776,173 | 876,727 | 1.13 | 427,929 | 469,821 | 58 | 59 | 16,263.7 | 17,795.7 | 7,841 | 0.594 | 0.962 | 1,136 | 0.655 | 0.988 |
| the 89 VIIRS all-zero months | 89 | 58 | 0 | 21,750 |  | 0 | 5,805 | 0 | 16 | 0 | 89.3 | 904 | 0 | 0.855 | 32 | 0 | 0.875 |

## By year (`tables/annual_issue11.csv`; km2 summed over the months of the year)

| year | months_changed | viirs_zero_months | a1e4_km2_before | a1e4_km2_after | a1e4_ratio | months_with_bloom_before | months_with_bloom_after | mean_cells_water_before | mean_cells_water_after | n_ge1e4 | in_ge1e4_before | in_ge1e4_after | n_high | in_high_before | in_high_after |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 2012 | 11 | 7 | 27,493 | 37,244 | 1.35 | 5 | 6 | 1,410.9 | 1,790 | 665 | 292 | 624 | 37 | 19 | 36 |
| 2013 | 12 | 7 | 10,709 | 15,529 | 1.45 | 3 | 4 | 1,607.8 | 1,980.9 | 616 | 338 | 586 | 67 | 49 | 66 |
| 2014 | 11 | 7 | 37,282 | 39,402 | 1.06 | 5 | 5 | 2,461.7 | 2,503.3 | 282 | 199 | 217 | 17 | 9 | 11 |
| 2015 | 6 | 4 | 44,523 | 53,865 | 1.21 | 4 | 4 | 3,240.6 | 4,070.5 | 477 | 265 | 466 | 68 | 32 | 67 |
| 2016 | 10 | 6 | 58,985 | 74,629 | 1.27 | 6 | 8 | 3,881.9 | 4,755.5 | 1,088 | 421 | 1,035 | 103 | 49 | 103 |
| 2017 | 11 | 9 | 17,411 | 25,712 | 1.48 | 2 | 6 | 798.2 | 1,004.3 | 456 | 64 | 417 | 17 | 6 | 16 |
| 2018 | 12 | 4 | 209,203 | 231,682 | 1.11 | 8 | 12 | 39,404.5 | 42,253.8 | 1,724 | 1,049 | 1,667 | 401 | 269 | 400 |
| 2019 | 11 | 7 | 33,469 | 41,301 | 1.23 | 5 | 6 | 9,250.4 | 11,007.2 | 430 | 250 | 409 | 118 | 81 | 117 |
| 2020 | 9 | 11 | 10,856 | 11,992 | 1.1 | 1 | 3 | 2,908.6 | 2,943.5 | 91 | 60 | 87 | 18 | 15 | 18 |
| 2021 | 12 | 2 | 162,682 | 184,958 | 1.14 | 9 | 11 | 15,650.7 | 16,705.9 | 1,639 | 894 | 1,573 | 206 | 129 | 203 |
| 2022 | 5 | 9 | 31,197 | 34,358 | 1.1 | 2 | 2 | 2,758.7 | 2,941 | 236 | 160 | 236 | 40 | 29 | 40 |
| 2023 | 7 | 8 | 35,565 | 46,313 | 1.3 | 4 | 4 | 2,214.8 | 2,673.7 | 701 | 405 | 665 | 60 | 41 | 57 |
| 2024 | 4 | 8 | 96,796 | 101,492 | 1.05 | 4 | 4 | 4,091.4 | 4,153.6 | 340 | 258 | 334 | 16 | 16 | 16 |

## By calendar month (`tables/climatology_issue11.csv`; means over 2012-2024)

| month | n_years | viirs_zero_years | years_changed | a1e4_km2_before | a1e4_km2_after | a1e5_km2_before | a1e5_km2_after | mean_cells_water_before | mean_cells_water_after | share_ge1e4_before | share_ge1e4_after |
|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | 13 | 6 | 10 | 3,230 | 4,278 | 1,719 | 2,148 | 4,645.8 | 5,210.2 | 0.423 | 0.958 |
| 2 | 13 | 9 | 10 | 1,879 | 3,035 | 1,137 | 1,753 | 2,078.7 | 2,826.8 | 0.368 | 0.909 |
| 3 | 13 | 11 | 10 | 861 | 1,775 | 511 | 811 | 610.8 | 974.1 | 0.329 | 0.872 |
| 4 | 13 | 11 | 9 | 270 | 886 | 0 | 47 | 30.6 | 162.4 | 0.103 | 0.897 |
| 5 | 13 | 11 | 11 | 229 | 428 | 41 | 65 | 69.7 | 110.8 | 0.29 | 0.957 |
| 6 | 13 | 11 | 10 | 383 | 663 | 188 | 311 | 357.3 | 518.3 | 0.222 | 0.943 |
| 7 | 13 | 8 | 6 | 1,996 | 2,287 | 1,636 | 1,770 | 10,484.2 | 11,314.9 | 0.672 | 0.981 |
| 8 | 13 | 9 | 10 | 4,025 | 4,235 | 2,361 | 2,461 | 9,916.5 | 10,897.2 | 0.781 | 0.981 |
| 9 | 13 | 5 | 10 | 9,084 | 9,661 | 4,678 | 4,984 | 9,837.5 | 10,467.8 | 0.694 | 0.928 |
| 10 | 13 | 3 | 13 | 16,862 | 17,982 | 10,811 | 11,361 | 20,366.8 | 21,568 | 0.707 | 0.962 |
| 11 | 13 | 2 | 12 | 14,773 | 16,514 | 7,198 | 7,826 | 18,169.7 | 20,235.6 | 0.555 | 0.97 |
| 12 | 12 | 3 | 10 | 6,623 | 7,985 | 2,856 | 3,303 | 6,502.2 | 7,228.1 | 0.512 | 0.979 |

## The 16 headline months (`tables/months_issue11.csv`)

| yrmo | a1e4_km2_before | a1e4_km2_after | a1e5_km2_before | a1e5_km2_after | mean_cells_water_before | mean_cells_water_after | n_ge1e4 | in_ge1e4_before | in_ge1e4_after | n_high | in_high_before | in_high_after | cells_changed |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 201203 | 0 | 1,080 | 0 | 464 | 0 | 374.5 | 13 | 0 | 6 | 0 | 0 | 0 | 47 |
| 201303 | 0 | 1,298 | 0 | 77 | 0 | 217.6 | 49 | 0 | 41 | 0 | 0 | 0 | 26 |
| 201603 | 0 | 992 | 0 | 0 | 0 | 125.3 | 27 | 0 | 22 | 0 | 0 | 0 | 62 |
| 201604 | 0 | 606 | 0 | 0 | 0 | 84 | 41 | 0 | 36 | 2 | 0 | 2 | 32 |
| 201701 | 0 | 2,428 | 0 | 683 | 0 | 940.2 | 116 | 0 | 113 | 5 | 0 | 5 | 41 |
| 201702 | 0 | 2,287 | 0 | 381 | 0 | 515.8 | 129 | 0 | 113 | 1 | 0 | 0 | 47 |
| 201703 | 0 | 1,524 | 0 | 76 | 0 | 176.1 | 59 | 0 | 43 | 0 | 0 | 0 | 42 |
| 201704 | 0 | 228 | 0 | 0 | 0 | 56 | 21 | 0 | 18 | 0 | 0 | 0 | 45 |
| 201802 | 0 | 2,527 | 0 | 918 | 0 | 784.7 | 31 | 0 | 22 | 0 | 0 | 0 | 47 |
| 201803 | 0 | 2,297 | 0 | 1,457 | 0 | 1,784.9 | 96 | 0 | 80 | 6 | 0 | 6 | 49 |
| 201804 | 0 | 2,300 | 0 | 460 | 0 | 641.5 | 60 | 0 | 51 | 6 | 0 | 6 | 52 |
| 201805 | 0 | 536 | 0 | 0 | 0 | 81.9 | 23 | 0 | 21 | 0 | 0 | 0 | 57 |
| 201902 | 0 | 462 | 0 | 154 | 0 | 134.4 | 4 | 0 | 2 | 0 | 0 | 0 | 12 |
| 202001 | 0 | 148 | 0 | 0 | 0 | 15.5 | 5 | 0 | 1 | 0 | 0 | 0 | 31 |
| 202011 | 0 | 229 | 0 | 0 | 0 | 38.1 | 5 | 0 | 5 | 0 | 0 | 0 | 30 |
| 202106 | 0 | 2,807 | 0 | 1,135 | 0 | 1,701.5 | 188 | 0 | 171 | 12 | 0 | 9 | 50 |

## Bloom months per cell (`tables/bloom_months_per_cell_issue11.csv`)

- 1247 water cells reach 10,000 cells/L in at least one VIIRS month before, 1295 after; 130 cells gain months (1 to 57; median 8), none lose any.
- Cells with the most bloom months: before max 48, after max 58 (of 155).

