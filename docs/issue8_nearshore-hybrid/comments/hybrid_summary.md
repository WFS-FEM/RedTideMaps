# Issue #8, step 2: hybrid footprints (VIIRS outside N, VIIRS or hull inside N)

Produced by `docs/issue8_nearshore-hybrid/hybrid_nearshore_issue8.R` from the clipped stacks of the 6 October 2026 run and the step-1 objects. For each of the 155 VIIRS months and each nearshore set N, `hybrid_N = max(viirs_clipped, hull_clipped * [cell in N])`: outside N the VIIRS result stands, zeros included; inside N the hull footprint (the pipeline's hull method: every positive sample, 75 km linkage, 10 km buffer) is added and never removes a VIIRS detection. Comparators: `current` (the final map) and `hull` (the hull-clipped map, a full hull fallback). Bloom area is km2 of water cells at or above 10,000 cells/L (`a1e4`) or 100,000 cells/L (`a1e5`); `added` is area the variant adds to the current map, split by whether the 0.1-degree VIIRS cell is masked or valid that month; samples are water-cell samples whose 5-arcmin cell is non-zero in the variant.

## The four nearshore sets (`tables/hybrid_sets_issue8.csv`)

| set | n_cells | km2 | share_in_mask | mask_cells_not_in_set | median_depth_m | max_depth_m | median_dist_km | max_dist_km | overlap_mask | overlap_coast2 | overlap_coast5 | overlap_coast10 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| mask | 84 | 6,316 | 1.00 | 0 | 2.3 | 18.1 | 1.8 | 6.3 | 84 | 44 | 80 | 84 |
| coast2 | 64 | 4,812 | 0.69 | 40 | 2.1 | 17.5 | 0.9 | 1.9 | 44 | 64 | 64 | 64 |
| coast5 | 132 | 9,922 | 0.61 | 4 | 2.9 | 18.1 | 2.1 | 5.0 | 80 | 64 | 132 | 132 |
| coast10 | 213 | 16,015 | 0.39 | 0 | 3.8 | 27.0 | 3.9 | 9.8 | 84 | 64 | 132 | 213 |

## Totals by month group (`tables/hybrid_groups_issue8.csv`)

### all 155 VIIRS months

| variant | months_changed | a1e4_km2 | a1e4_vs_hull | a1e5_km2 | added_1e4_km2 | added_1e4_km2_masked | added_1e4_km2_valid | removed_fp_km2 | n_ge1e4 | in_ge1e4 | share_ge1e4 | share_medium | share_high |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| current | 0 | 776,173 | 1.06 | 427,929 | 0 | 0 | 0 | 0 | 8,745 | 4,655 | 0.532 | 0.579 | 0.637 |
| mask | 121 | 866,561 | 1.18 | 465,246 | 90,389 | 90,162 | 227 | 0 | 8,745 | 7,651 | 0.875 | 0.899 | 0.959 |
| coast2 | 121 | 841,355 | 1.15 | 454,446 | 65,182 | 52,156 | 13,026 | 0 | 8,745 | 6,953 | 0.795 | 0.816 | 0.911 |
| coast5 | 121 | 894,379 | 1.22 | 474,032 | 118,206 | 86,063 | 32,143 | 0 | 8,745 | 7,982 | 0.913 | 0.930 | 0.973 |
| coast10 | 121 | 937,983 | 1.28 | 488,801 | 161,811 | 90,162 | 71,649 | 0 | 8,745 | 8,528 | 0.975 | 0.982 | 0.994 |
| hull | 121 | 734,401 | 1.00 | 348,560 | 358,244 | 90,162 | 268,083 | 438,288 | 8,745 | 8,745 | 1.000 | 1.000 | 1.000 |

### the 58 zeroed months

| variant | months_changed | a1e4_km2 | a1e4_vs_hull | a1e5_km2 | added_1e4_km2 | added_1e4_km2_masked | added_1e4_km2_valid | removed_fp_km2 | n_ge1e4 | in_ge1e4 | share_ge1e4 | share_medium | share_high |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| current | 0 | 0 | 0.00 | 0 | 0 | 0 | 0 | 0 | 904 | 0 | 0.000 | 0.000 | 0.000 |
| mask | 58 | 14,179 | 0.24 | 3,662 | 14,179 | 14,179 | 0 | 0 | 904 | 531 | 0.587 | 0.601 | 0.625 |
| coast2 | 58 | 9,847 | 0.17 | 2,902 | 9,847 | 7,317 | 2,530 | 0 | 904 | 390 | 0.431 | 0.426 | 0.344 |
| coast5 | 58 | 20,911 | 0.35 | 5,653 | 20,911 | 13,340 | 7,571 | 0 | 904 | 705 | 0.780 | 0.825 | 0.812 |
| coast10 | 58 | 32,304 | 0.54 | 9,474 | 32,304 | 14,179 | 18,124 | 0 | 904 | 840 | 0.929 | 0.935 | 0.969 |
| hull | 58 | 59,637 | 1.00 | 14,220 | 59,637 | 14,179 | 45,458 | 0 | 904 | 904 | 1.000 | 1.000 | 1.000 |

### the 16 headline months

| variant | months_changed | a1e4_km2 | a1e4_vs_hull | a1e5_km2 | added_1e4_km2 | added_1e4_km2_masked | added_1e4_km2_valid | removed_fp_km2 | n_ge1e4 | in_ge1e4 | share_ge1e4 | share_medium | share_high |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| current | 0 | 0 | 0.00 | 0 | 0 | 0 | 0 | 0 | 867 | 0 | 0.000 | 0.000 | 0.000 |
| mask | 16 | 14,179 | 0.24 | 3,662 | 14,179 | 14,179 | 0 | 0 | 867 | 513 | 0.592 | 0.602 | 0.625 |
| coast2 | 16 | 9,847 | 0.17 | 2,902 | 9,847 | 7,317 | 2,530 | 0 | 867 | 372 | 0.429 | 0.426 | 0.344 |
| coast5 | 16 | 20,911 | 0.35 | 5,653 | 20,911 | 13,340 | 7,571 | 0 | 867 | 677 | 0.781 | 0.827 | 0.812 |
| coast10 | 16 | 32,304 | 0.54 | 9,474 | 32,304 | 14,179 | 18,124 | 0 | 867 | 804 | 0.927 | 0.934 | 0.969 |
| hull | 16 | 59,637 | 1.00 | 14,220 | 59,637 | 14,179 | 45,458 | 0 | 867 | 867 | 1.000 | 1.000 | 1.000 |

### the 60 VIIRS-positive fitted months of #6

| variant | months_changed | a1e4_km2 | a1e4_vs_hull | a1e5_km2 | added_1e4_km2 | added_1e4_km2_masked | added_1e4_km2_valid | removed_fp_km2 | n_ge1e4 | in_ge1e4 | share_ge1e4 | share_medium | share_high |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| current | 0 | 776,173 | 1.15 | 427,929 | 0 | 0 | 0 | 0 | 7,841 | 4,655 | 0.594 | 0.631 | 0.655 |
| mask | 60 | 852,382 | 1.26 | 461,585 | 76,210 | 75,982 | 227 | 0 | 7,841 | 7,120 | 0.908 | 0.926 | 0.968 |
| coast2 | 60 | 831,508 | 1.23 | 451,543 | 55,336 | 44,839 | 10,497 | 0 | 7,841 | 6,563 | 0.837 | 0.851 | 0.927 |
| coast5 | 60 | 873,468 | 1.29 | 468,380 | 97,295 | 72,723 | 24,572 | 0 | 7,841 | 7,277 | 0.928 | 0.939 | 0.978 |
| coast10 | 60 | 905,680 | 1.34 | 479,327 | 129,507 | 75,982 | 53,525 | 0 | 7,841 | 7,688 | 0.980 | 0.986 | 0.995 |
| hull | 60 | 674,764 | 1.00 | 334,340 | 298,607 | 75,982 | 222,625 | 435,426 | 7,841 | 7,841 | 1.000 | 1.000 | 1.000 |

### the 66 VIIRS-positive months

| variant | months_changed | a1e4_km2 | a1e4_vs_hull | a1e5_km2 | added_1e4_km2 | added_1e4_km2_masked | added_1e4_km2_valid | removed_fp_km2 | n_ge1e4 | in_ge1e4 | share_ge1e4 | share_medium | share_high |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| current | 0 | 776,173 | 1.15 | 427,929 | 0 | 0 | 0 | 0 | 7,841 | 4,655 | 0.594 | 0.631 | 0.655 |
| mask | 63 | 852,382 | 1.26 | 461,585 | 76,210 | 75,982 | 227 | 0 | 7,841 | 7,120 | 0.908 | 0.926 | 0.968 |
| coast2 | 63 | 831,508 | 1.23 | 451,543 | 55,336 | 44,839 | 10,497 | 0 | 7,841 | 6,563 | 0.837 | 0.851 | 0.927 |
| coast5 | 63 | 873,468 | 1.29 | 468,380 | 97,295 | 72,723 | 24,572 | 0 | 7,841 | 7,277 | 0.928 | 0.939 | 0.978 |
| coast10 | 63 | 905,680 | 1.34 | 479,327 | 129,507 | 75,982 | 53,525 | 0 | 7,841 | 7,688 | 0.980 | 0.986 | 0.995 |
| hull | 63 | 674,764 | 1.00 | 334,340 | 298,607 | 75,982 | 222,625 | 438,288 | 7,841 | 7,841 | 1.000 | 1.000 | 1.000 |

### the 89 VIIRS all-zero months

| variant | months_changed | a1e4_km2 | a1e4_vs_hull | a1e5_km2 | added_1e4_km2 | added_1e4_km2_masked | added_1e4_km2_valid | removed_fp_km2 | n_ge1e4 | in_ge1e4 | share_ge1e4 | share_medium | share_high |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| current | 0 | 0 | 0.00 | 0 | 0 | 0 | 0 | 0 | 904 | 0 | 0.000 | 0.000 | 0.000 |
| mask | 58 | 14,179 | 0.24 | 3,662 | 14,179 | 14,179 | 0 | 0 | 904 | 531 | 0.587 | 0.601 | 0.625 |
| coast2 | 58 | 9,847 | 0.17 | 2,902 | 9,847 | 7,317 | 2,530 | 0 | 904 | 390 | 0.431 | 0.426 | 0.344 |
| coast5 | 58 | 20,911 | 0.35 | 5,653 | 20,911 | 13,340 | 7,571 | 0 | 904 | 705 | 0.780 | 0.825 | 0.812 |
| coast10 | 58 | 32,304 | 0.54 | 9,474 | 32,304 | 14,179 | 18,124 | 0 | 904 | 840 | 0.929 | 0.935 | 0.969 |
| hull | 58 | 59,637 | 1.00 | 14,220 | 59,637 | 14,179 | 45,458 | 0 | 904 | 904 | 1.000 | 1.000 | 1.000 |

Over all 155 VIIRS months the `mask` rule changes 121 months and adds 90,389 km2 of bloom area (>= 10,000 cells/L), all of it in masked cells; `coast5` changes 121 months and adds 118,206 km2, of which 32,143 km2 in VIIRS-valid cells; the share of water samples >= 10,000 cells/L inside the footprint goes from 53% (current) to 88% (mask), 80% (coast2), 91% (coast5), 98% (coast10) and 100% (hull). In the 58 zeroed months the hybrids restore 24% (mask), 17% (coast2), 35% (coast5) and 54% (coast10) of the hull-clipped bloom area; in the 60 VIIRS-positive fitted months of #6 they add 76,210 / 55,336 / 97,295 / 129,507 km2 against a current 776,173 km2.

## The 16 headline months, the two low_vs_hull months and the two control months (`tables/hybrid_months_issue8.csv`)

Bloom area >= 10,000 cells/L (km2) by variant:

| yrmo | tag | current | mask | coast2 | coast5 | coast10 | hull |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 201203 | headline | 0 | 463 | 540 | 1,080 | 1,698 | 5,098 |
| 201303 | headline | 0 | 993 | 535 | 1,222 | 1,910 | 2,292 |
| 201603 | headline | 0 | 687 | 459 | 916 | 1,221 | 1,601 |
| 201604 | headline | 0 | 379 | 152 | 606 | 682 | 985 |
| 201701 | headline | 0 | 1,821 | 911 | 2,276 | 3,341 | 4,181 |
| 201702 | headline | 0 | 1,447 | 1,144 | 2,134 | 3,661 | 7,244 |
| 201703 | headline | 0 | 1,067 | 610 | 1,448 | 2,517 | 6,417 |
| 201704 | headline | 0 | 152 | 152 | 228 | 304 | 457 |
| 201802 | headline | 0 | 1,607 | 1,225 | 2,451 | 3,906 | 7,808 |
| 201803 | headline | 0 | 1,377 | 1,072 | 2,221 | 3,676 | 7,061 |
| 201804 | headline | 0 | 1,456 | 997 | 2,223 | 3,374 | 4,982 |
| 201805 | headline | 0 | 383 | 306 | 536 | 766 | 766 |
| 201902 | headline | 0 | 154 | 231 | 462 | 693 | 1,233 |
| 202001 | headline | 0 | 74 | 74 | 148 | 148 | 1,694 |
| 202011 | headline | 0 | 76 | 76 | 229 | 381 | 458 |
| 202106 | headline | 0 | 2,044 | 1,362 | 2,731 | 4,027 | 7,361 |
| 201801 | low_vs_hull | 1,456 | 2,835 | 2,454 | 3,681 | 4,602 | 10,150 |
| 202104 | low_vs_hull | 0 | 841 | 688 | 1,683 | 2,831 | 4,132 |
| 201408 | control | 15,692 | 15,692 | 15,692 | 15,692 | 15,692 | 13,310 |
| 202109 | control | 33,308 | 34,957 | 34,652 | 35,402 | 36,372 | 37,724 |

Water samples >= 10,000 cells/L inside the footprint, by variant (the month's total is the `current` row's denominator, `n_ge1e4` in the tables):

| yrmo | tag | current | mask | coast2 | coast5 | coast10 | hull | n_ge1e4 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 201203 | headline | 0 | 3 | 1 | 6 | 9 | 13 | 13 |
| 201303 | headline | 0 | 34 | 19 | 41 | 46 | 49 | 49 |
| 201603 | headline | 0 | 13 | 15 | 22 | 22 | 27 | 27 |
| 201604 | headline | 0 | 26 | 16 | 34 | 38 | 41 | 41 |
| 201701 | headline | 0 | 74 | 60 | 100 | 113 | 116 | 116 |
| 201702 | headline | 0 | 75 | 62 | 103 | 117 | 129 | 129 |
| 201703 | headline | 0 | 30 | 21 | 41 | 52 | 59 | 59 |
| 201704 | headline | 0 | 12 | 14 | 18 | 20 | 21 | 21 |
| 201802 | headline | 0 | 14 | 11 | 21 | 24 | 31 | 31 |
| 201803 | headline | 0 | 41 | 47 | 79 | 90 | 96 | 96 |
| 201804 | headline | 0 | 29 | 29 | 51 | 59 | 60 | 60 |
| 201805 | headline | 0 | 18 | 14 | 21 | 23 | 23 | 23 |
| 201902 | headline | 0 | 0 | 1 | 2 | 2 | 4 | 4 |
| 202001 | headline | 0 | 0 | 0 | 1 | 1 | 5 | 5 |
| 202011 | headline | 0 | 0 | 0 | 5 | 5 | 5 | 5 |
| 202106 | headline | 0 | 144 | 62 | 132 | 183 | 188 | 188 |
| 201801 | low_vs_hull | 7 | 31 | 18 | 35 | 37 | 46 | 46 |
| 202104 | low_vs_hull | 2 | 57 | 34 | 74 | 75 | 75 | 75 |
| 201408 | control | 140 | 140 | 140 | 140 | 140 | 152 | 152 |
| 202109 | control | 152 | 166 | 159 | 161 | 168 | 171 | 171 |

## Checks

- Every hybrid equals the current map outside its set and the cell-wise maximum of the current and hull-clipped maps inside it; never below the current map, never above that maximum; an empty set reproduces the current map and the whole domain the full union.
- The sets are nested (coast2 in coast5 in coast10), so bloom areas are monotone; no hybrid removes a cell.
- Per-month water-sample counts by class equal the step-1 month table; the counts of samples >= 10,000 cells/L on water and inside the current footprint equal the #6 month table; the step-1 `in_final_fp` flag is reproduced.
- Control months by the rule (no #6 flag, >= 80% of the samples >= 10,000 cells/L inside, hull ratio 0.75 to 1.33, the two highest shares): 201408, 202109.

