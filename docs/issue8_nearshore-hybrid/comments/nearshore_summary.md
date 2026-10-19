# Issue #8, step 1: where are the samples VIIRS does not see?

Produced by `docs/issue8_nearshore-hybrid/check_nearshore_issue8.R` from the 6 October 2026 run (samples `FWC HAB data 19800102-20260922_filtered.Rdata`). Every sample of 2012-2024 is classified by FWC abundance class and by the VIIRS cell it falls in that month: masked (no data in the tif), valid with no detection (0), or valid with a detection (> 0). The 609 samples of 2022-12 (no VIIRS tif) and 55 negative samples just outside the grid box (lat >= 30.5) are left out of the tables below.

## The mask

- 1002 to 1012 no-data cells per layer over 155 layers. The static mask (no data in at least 90% of the months) has 1004 cells: 1001 in every month and 3 in 145 to 152 months. 15 further cells are no-data in a few months only (15 of them in a single month, 14 of those over water deeper than 100 m in the south-west corner): a transient gap, not part of the mask.
- 66 static-mask cells hold Gulf-domain template water (84 5-arcmin water cells, 6,316 km2, 2% of the 287,210 km2 of Gulf-domain water); their mean template depth has a median of 2.2 m (90th percentile 5.8 m, max 15.0 m) and their centres a median distance to the coast of 1.0 km (90th percentile 4.5 km).
- The Atlantic-side corner of the template (east of -82 E, north of 28.5 N, where the pipeline drops samples) is no-data in every VIIRS month because the product covers the Gulf only; it is left out of every mask statistic.

### Share of template water cells masked, by region and distance to the coast (`tables/mask_band_issue8.csv`)

| region | band | n_cells | n_masked_always | share_masked_always | km2 | km2_masked_always |
| --- | --- | --- | --- | --- | --- | --- |
| Panhandle | 0-2 km | 28 | 19 | 0.68 | 2,072.56 | 1,407.40 |
| Panhandle | 2-5 km | 29 | 15 | 0.52 | 2,146.12 | 1,109.68 |
| Panhandle | 5-10 km | 27 | 0 | 0.00 | 2,000.98 | 0.00 |
| Panhandle | 10-20 km | 54 | 0 | 0.00 | 4,004.99 | 0.00 |
| Panhandle | > 20 km | 2,460 | 0 | 0.00 | 186,681.15 | 0.00 |
| Big Bend | 0-2 km | 6 | 3 | 0.50 | 447.10 | 222.85 |
| Big Bend | 2-5 km | 7 | 4 | 0.57 | 521.89 | 297.70 |
| Big Bend | 5-10 km | 18 | 0 | 0.00 | 1,342.10 | 0.00 |
| Big Bend | 10-20 km | 29 | 0 | 0.00 | 2,163.95 | 0.00 |
| Big Bend | > 20 km | 122 | 0 | 0.00 | 9,125.03 | 0.00 |
| Tampa Bay to Charlotte Harbor | 0-2 km | 16 | 13 | 0.81 | 1,214.36 | 985.97 |
| Tampa Bay to Charlotte Harbor | 2-5 km | 20 | 13 | 0.65 | 1,518.31 | 987.74 |
| Tampa Bay to Charlotte Harbor | 5-10 km | 19 | 3 | 0.16 | 1,441.36 | 227.58 |
| Tampa Bay to Charlotte Harbor | 10-20 km | 34 | 0 | 0.00 | 2,578.20 | 0.00 |
| Tampa Bay to Charlotte Harbor | > 20 km | 355 | 0 | 0.00 | 26,945.71 | 0.00 |
| Lee County to the Keys | 0-2 km | 14 | 9 | 0.64 | 1,077.88 | 692.44 |
| Lee County to the Keys | 2-5 km | 12 | 4 | 0.33 | 923.76 | 307.67 |
| Lee County to the Keys | 5-10 km | 17 | 1 | 0.06 | 1,308.97 | 77.17 |
| Lee County to the Keys | 10-20 km | 30 | 0 | 0.00 | 2,310.44 | 0.00 |
| Lee County to the Keys | > 20 km | 485 | 0 | 0.00 | 37,384.86 | 0.00 |
| all regions | 0-2 km | 64 | 44 | 0.69 | 4,811.90 | 3,308.67 |
| all regions | 2-5 km | 68 | 36 | 0.53 | 5,110.08 | 2,702.80 |
| all regions | 5-10 km | 81 | 4 | 0.05 | 6,093.41 | 304.76 |
| all regions | 10-20 km | 147 | 0 | 0.00 | 11,057.58 | 0.00 |
| all regions | > 20 km | 3,422 | 0 | 0.00 | 260,136.75 | 0.00 |

## T1: samples by FWC class and VIIRS cell status (`tables/t1_class_by_viirs_cell_issue8.csv`)

| class_label | masked | valid_zero | valid_pos | total | masked_share | detected_share_of_valid | masked_water | masked_land |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| negative (0) | 49,295 | 24,766 | 2,603 | 76,664 | 0.643 | 0.095 | 32,690 | 16,605 |
| background (<= 1,000) | 2,708 | 1,217 | 530 | 4,455 | 0.608 | 0.303 | 1,884 | 824 |
| very low (1,000 - 10,000) | 3,054 | 817 | 835 | 4,706 | 0.649 | 0.505 | 2,167 | 887 |
| low (10,000 - 100,000) | 3,288 | 728 | 1,247 | 5,263 | 0.625 | 0.631 | 2,284 | 1,004 |
| medium (100,000 - 1,000,000) | 2,995 | 415 | 1,334 | 4,744 | 0.631 | 0.763 | 2,034 | 961 |
| high (> 1,000,000) | 1,076 | 66 | 485 | 1,627 | 0.661 | 0.880 | 725 | 351 |
| all samples | 62,416 | 28,009 | 7,034 | 97,459 | 0.640 | 0.201 | 41,784 | 20,632 |

## T2: the 58 zeroed months, by class (`tables/t2_zeroed_months_by_class_issue8.csv`)

| months | class | n | masked | valid_zero | valid_pos | land | masked_water | masked_share | valid_zero_share | land_share |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| the 58 zeroed months | background | 1,624 | 1,029 | 595 | 0 | 417 | 702 | 0.63 | 0.37 | 0.26 |
| the 58 zeroed months | very_low | 1,145 | 833 | 312 | 0 | 296 | 594 | 0.73 | 0.27 | 0.26 |
| the 58 zeroed months | low | 761 | 535 | 226 | 0 | 192 | 376 | 0.70 | 0.30 | 0.25 |
| the 58 zeroed months | medium | 428 | 291 | 137 | 0 | 137 | 188 | 0.68 | 0.32 | 0.32 |
| the 58 zeroed months | high | 47 | 34 | 13 | 0 | 15 | 22 | 0.72 | 0.28 | 0.32 |
| the 16 headline months | background | 720 | 498 | 222 | 0 | 198 | 337 | 0.69 | 0.31 | 0.28 |
| the 16 headline months | very_low | 814 | 602 | 212 | 0 | 187 | 456 | 0.74 | 0.26 | 0.23 |
| the 16 headline months | low | 713 | 505 | 208 | 0 | 175 | 361 | 0.71 | 0.29 | 0.25 |
| the 16 headline months | medium | 423 | 288 | 135 | 0 | 134 | 187 | 0.68 | 0.32 | 0.32 |
| the 16 headline months | high | 47 | 34 | 13 | 0 | 15 | 22 | 0.72 | 0.28 | 0.32 |

Headline months (16), samples at or above 10,000 cells/L: `hull_km2_in_mask` is the bloom area (>= 10,000 cells/L) of the hull-clipped map that lies in the masked band, i.e. what a mask rule would restore in that month.

| yrmo | n_pos | n_ge_1e4 | masked | valid_zero | valid_pos | land | masked_share | median_dist_coast_km | hull_km2_in_mask |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 201203 | 41 | 14 | 2 | 12 | 0 | 1 | 0.14 | 5.5 | 463 |
| 201303 | 173 | 68 | 54 | 14 | 0 | 19 | 0.79 | 1.0 | 993 |
| 201603 | 133 | 29 | 18 | 11 | 0 | 3 | 0.62 | 2.0 | 687 |
| 201604 | 246 | 56 | 30 | 26 | 0 | 16 | 0.54 | 1.4 | 379 |
| 201701 | 274 | 160 | 127 | 33 | 0 | 45 | 0.79 | 1.2 | 1,821 |
| 201702 | 320 | 190 | 140 | 50 | 0 | 61 | 0.74 | 1.1 | 1,447 |
| 201703 | 258 | 94 | 67 | 27 | 0 | 38 | 0.71 | 0.9 | 1,067 |
| 201704 | 168 | 34 | 29 | 5 | 0 | 13 | 0.85 | 1.1 | 152 |
| 201802 | 82 | 38 | 22 | 16 | 0 | 7 | 0.58 | 1.5 | 1,607 |
| 201803 | 236 | 151 | 99 | 52 | 0 | 56 | 0.66 | 0.7 | 1,377 |
| 201804 | 190 | 79 | 46 | 33 | 0 | 19 | 0.58 | 0.9 | 1,456 |
| 201805 | 116 | 23 | 20 | 3 | 0 | 1 | 0.87 | 1.2 | 383 |
| 201902 | 11 | 4 | 0 | 4 | 0 | 0 | 0.00 | 7.8 | 154 |
| 202001 | 56 | 5 | 1 | 4 | 0 | 0 | 0.20 | 48.2 | 74 |
| 202011 | 37 | 8 | 2 | 6 | 0 | 3 | 0.25 | 0.1 | 76 |
| 202106 | 376 | 230 | 170 | 60 | 0 | 42 | 0.74 | 2.4 | 2,044 |

## T3: the 60 VIIRS-positive fitted months of #6: water samples >= 10,000 cells/L outside the final footprint (`tables/t3_outside_footprint_by_class_issue8.csv`)

Selection as in #6 (use = viirs, layer positive, fitted, at least 5 such samples): 60 months, 7841 samples, 3186 outside the footprint (#6: 60 / 7841 / 3186).

| class | n_water_samples | outside_fp | outside_share | outside_masked | outside_valid_zero | outside_valid_pos | inside_masked | inside_valid_zero | inside_valid_pos |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| low | 3,403 | 1,559 | 0.46 | 1,158 | 401 | 0 | 750 | 41 | 1,053 |
| medium | 3,245 | 1,198 | 0.37 | 985 | 213 | 0 | 861 | 26 | 1,160 |
| high | 1,136 | 392 | 0.35 | 358 | 34 | 0 | 345 | 3 | 396 |
| all >= 10,000 | 7,841 | 3,186 | 0.41 | 2,532 | 654 | 0 | 1,961 | 71 | 2,623 |

## T4: distance to the coast (km) by class and status (`tables/t4_dist_coast_by_class_issue8.csv`)

| class | status | n | q10 | q25 | median | q75 | q90 | within_2km | within_5km | within_10km |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| background | masked | 2,708 | 0.1 | 0.5 | 0.9 | 1.5 | 3.1 | 0.8 | 1.0 | 1.0 |
| background | valid_zero | 1,217 | 0.3 | 1.2 | 6.2 | 24.2 | 48.3 | 0.3 | 0.4 | 0.6 |
| background | valid_pos | 530 | 0.3 | 0.6 | 4.5 | 14.0 | 28.3 | 0.4 | 0.5 | 0.7 |
| very_low | masked | 3,054 | 0.2 | 0.5 | 0.9 | 1.6 | 3.1 | 0.8 | 1.0 | 1.0 |
| very_low | valid_zero | 817 | 0.2 | 0.6 | 3.1 | 11.5 | 31.1 | 0.4 | 0.6 | 0.7 |
| very_low | valid_pos | 835 | 0.2 | 0.6 | 4.7 | 13.1 | 27.7 | 0.4 | 0.5 | 0.7 |
| low | masked | 3,288 | 0.2 | 0.5 | 1.0 | 1.9 | 3.6 | 0.8 | 1.0 | 1.0 |
| low | valid_zero | 728 | 0.1 | 0.3 | 3.0 | 8.2 | 22.8 | 0.4 | 0.6 | 0.8 |
| low | valid_pos | 1,247 | 0.2 | 0.6 | 4.7 | 11.2 | 26.5 | 0.4 | 0.5 | 0.7 |
| medium | masked | 2,995 | 0.2 | 0.5 | 1.0 | 1.7 | 3.2 | 0.8 | 1.0 | 1.0 |
| medium | valid_zero | 415 | 0.1 | 0.3 | 2.0 | 7.7 | 17.3 | 0.5 | 0.6 | 0.8 |
| medium | valid_pos | 1,334 | 0.2 | 0.8 | 4.7 | 10.6 | 24.6 | 0.4 | 0.5 | 0.7 |
| high | masked | 1,076 | 0.1 | 0.4 | 0.9 | 1.3 | 2.7 | 0.9 | 1.0 | 1.0 |
| high | valid_zero | 66 | 0.1 | 0.3 | 0.8 | 5.1 | 16.2 | 0.6 | 0.7 | 0.9 |
| high | valid_pos | 485 | 0.1 | 0.3 | 2.3 | 8.6 | 14.4 | 0.5 | 0.6 | 0.8 |

Share of each class within 2, 5 and 10 km of the coast, and the masked share inside and beyond that band (`tables/t4b_coast_bands_by_class_issue8.csv`):

| class | band_km | n | n_within | share_within | masked_share_within | masked_share_beyond |
| --- | --- | --- | --- | --- | --- | --- |
| background | 2 | 4,455 | 2,773 | 0.62 | 0.78 | 0.32 |
| background | 5 | 4,455 | 3,454 | 0.78 | 0.76 | 0.08 |
| background | 10 | 4,455 | 3,771 | 0.85 | 0.72 | 0.00 |
| very_low | 2 | 4,706 | 3,129 | 0.66 | 0.78 | 0.38 |
| very_low | 5 | 4,706 | 3,910 | 0.83 | 0.77 | 0.07 |
| very_low | 10 | 4,706 | 4,220 | 0.90 | 0.72 | 0.00 |
| low | 2 | 5,263 | 3,350 | 0.64 | 0.76 | 0.39 |
| low | 5 | 5,263 | 4,270 | 0.81 | 0.74 | 0.11 |
| low | 10 | 5,263 | 4,767 | 0.91 | 0.69 | 0.00 |
| medium | 2 | 4,744 | 3,086 | 0.65 | 0.76 | 0.38 |
| medium | 5 | 4,744 | 3,844 | 0.81 | 0.75 | 0.11 |
| medium | 10 | 4,744 | 4,321 | 0.91 | 0.69 | 0.00 |
| high | 2 | 1,627 | 1,200 | 0.74 | 0.78 | 0.34 |
| high | 5 | 1,627 | 1,412 | 0.87 | 0.75 | 0.09 |
| high | 10 | 1,627 | 1,514 | 0.93 | 0.71 | 0.00 |

## T5: per month (`tables/t5_months_issue8.csv`), headline rows

| yrmo | n_pos | n_ge_1e4 | n_ge_1e4_masked | n_ge_1e4_valid_zero | n_ge_1e4_valid_pos | hull_footprint_km2 | hull_fp_km2_in_mask | area_1e4_hull_km2 | hull_1e4_km2_in_mask |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 201203 | 41 | 14 | 2 | 12 | 0 | 14,023.3 | 1,665 | 5,098.12 | 463 |
| 201303 | 173 | 69 | 55 | 14 | 0 | 6,437.0 | 1,448 | 2,292.04 | 993 |
| 201603 | 133 | 30 | 19 | 11 | 0 | 15,423.5 | 2,960 | 1,600.72 | 687 |
| 201604 | 246 | 57 | 31 | 26 | 0 | 13,393.8 | 1,522 | 984.68 | 379 |
| 201701 | 274 | 161 | 128 | 33 | 0 | 8,395.3 | 2,281 | 4,180.95 | 1,821 |
| 201702 | 320 | 192 | 142 | 50 | 0 | 12,955.0 | 2,276 | 7,243.98 | 1,447 |
| 201703 | 258 | 98 | 69 | 29 | 0 | 10,452.5 | 2,195 | 6,416.86 | 1,067 |
| 201704 | 168 | 34 | 29 | 5 | 0 | 10,057.6 | 2,270 | 457.23 | 152 |
| 201802 | 82 | 38 | 22 | 16 | 0 | 14,015.8 | 2,284 | 7,808.46 | 1,607 |
| 201803 | 236 | 153 | 100 | 53 | 0 | 12,712.8 | 2,203 | 7,060.88 | 1,377 |
| 201804 | 190 | 79 | 46 | 33 | 0 | 11,259.7 | 2,572 | 4,982.06 | 1,456 |
| 201805 | 116 | 24 | 21 | 3 | 0 | 12,466.7 | 2,567 | 766.10 | 383 |
| 201902 | 11 | 4 | 0 | 4 | 0 | 2,992.3 | 375 | 1,232.75 | 154 |
| 202001 | 56 | 5 | 1 | 4 | 0 | 18,086.4 | 1,057 | 1,693.80 | 74 |
| 202011 | 37 | 8 | 2 | 6 | 0 | 5,795.7 | 1,442 | 457.74 | 76 |
| 202106 | 376 | 230 | 170 | 60 | 0 | 15,115.6 | 2,655 | 7,360.98 | 2,044 |

