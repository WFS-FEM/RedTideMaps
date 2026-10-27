# Issue #18, stage record: the delivered maps against the 6 Oct 2026 maps (and the mask5 run of #10)

From the combined stacks of the final 5-arcmin run (hoard/final5, FWC samples frozen at the 20260922 pull) and the 6 Oct 2026 run; 504 months, 278 of them satellite months (155 VIIRS, 123 MODIS), 226 hull months byte-identical.

## By group (`tables/record_groups_issue18.csv`)

| group | months_changed | exposure_6oct | exposure_final | exposure_ratio | exposure_ratio_mask5 | cellmonths_ge10k_6oct | cellmonths_ge10k_final | cellmonths_ge100k_6oct | cellmonths_ge100k_final | cellmonths_ge1M_6oct | cellmonths_ge1M_final | samples_ge10k | share_ge10k_6oct | share_ge10k_final | samples_gt1M | share_gt1M_6oct | share_gt1M_final |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| all 504 months 1985-2026 | 210 | 8,874,996,166 | 9,421,841,896 | 1.062 | 1.053 | 35,606 | 38,110 | 13,290 | 14,183 | 1,716 | 1,809 | 17,760 | 0.724 | 0.956 | 2,195 | 0.785 | 0.983 |
| the 278 satellite months | 210 | 6,494,237,122 | 7,041,082,852 | 1.084 | 1.073 | 27,970 | 30,474 | 10,569 | 11,462 | 1,253 | 1,346 | 13,280 | 0.632 | 0.942 | 1,610 | 0.706 | 0.977 |
| the 155 VIIRS months | 121 | 4,119,726,916 | 4,583,313,352 | 1.113 | 1.102 | 10,204 | 12,133 | 5,633 | 6,367 | 901 | 978 | 8,745 | 0.532 | 0.966 | 1,168 | 0.637 | 0.992 |
| the 123 MODIS months | 89 | 2,374,510,206 | 2,457,769,500 | 1.035 | 1.023 | 17,766 | 18,341 | 4,936 | 5,095 | 352 | 368 | 4,535 | 0.824 | 0.896 | 442 | 0.889 | 0.937 |
| the 226 hull months | 0 | 2,380,759,044 | 2,380,759,044 | 1 | 1 | 7,636 | 7,636 | 2,721 | 2,721 | 463 | 463 | 4,480 | 0.998 | 0.998 | 585 | 1 | 1 |
| the 58 zeroed VIIRS months of #6 | 58 | 0 | 43,721,958 |  |  | 0 | 358 | 0 | 105 | 0 | 3 | 904 | 0 | 0.885 | 32 | 0 | 0.969 |
| the 16 headline months of #6 | 16 | 0 | 42,352,413 |  |  | 0 | 358 | 0 | 105 | 0 | 3 | 867 | 0 | 0.886 | 32 | 0 | 0.969 |

## The 16 headline months of #6 (`tables/record_months_issue18.csv`; figure 1)

| yrmo | samples_ge10k | in_ge10k_v6oct | in_ge10k_final | km2_ge10k_v6oct | km2_ge10k_final | exposure_v6oct | exposure_final | cells_changed_final |
|---|---|---|---|---|---|---|---|---|
| 201203 | 13 | 0 | 9 | 0 | 1,389 | 0 | 1,863,106 | 58 |
| 201303 | 49 | 0 | 44 | 0 | 1,603 | 0 | 991,425 | 34 |
| 201603 | 27 | 0 | 22 | 0 | 992 | 0 | 539,344 | 78 |
| 201604 | 41 | 0 | 36 | 0 | 606 | 0 | 373,342 | 40 |
| 201701 | 116 | 0 | 113 | 0 | 3,037 | 0 | 5,411,890 | 51 |
| 201702 | 129 | 0 | 113 | 0 | 2,974 | 0 | 3,618,177 | 56 |
| 201703 | 59 | 0 | 46 | 0 | 2,058 | 0 | 966,510 | 51 |
| 201704 | 21 | 0 | 19 | 0 | 304 | 0 | 267,158 | 53 |
| 201802 | 31 | 0 | 22 | 0 | 3,292 | 0 | 3,600,570 | 59 |
| 201803 | 96 | 0 | 81 | 0 | 2,985 | 0 | 9,261,667 | 63 |
| 201804 | 60 | 0 | 52 | 0 | 2,836 | 0 | 2,964,720 | 65 |
| 201805 | 23 | 0 | 21 | 0 | 536 | 0 | 346,771 | 70 |
| 201902 | 4 | 0 | 2 | 0 | 539 | 0 | 583,273 | 13 |
| 202001 | 5 | 0 | 1 | 0 | 148 | 0 | 65,907 | 38 |
| 202011 | 5 | 0 | 5 | 0 | 458 | 0 | 210,270 | 37 |
| 202106 | 188 | 0 | 182 | 0 | 3,568 | 0 | 11,288,283 | 63 |

