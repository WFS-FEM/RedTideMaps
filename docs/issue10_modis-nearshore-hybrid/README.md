# Issue #10: the nearshore hybrid for the MODIS months

Examination, implementation and checks for [WFS-FEM/RedTideMaps#10](https://github.com/WFS-FEM/RedTideMaps/issues/10), the follow-up of [#8](https://github.com/WFS-FEM/RedTideMaps/issues/8) and [#11](https://github.com/WFS-FEM/RedTideMaps/issues/11) under [#5](https://github.com/WFS-FEM/RedTideMaps/issues/5). Issue #11 put the `mask5` nearshore rule into the pipeline for the 155 VIIRS months; this issue asks whether the 123 months served from MODIS nFLH polygons (2002-07 to 2011-12, 2022-12, 2025-01 to 2025-09) need the same, examines it from the stacks on disk (step 1), and applies the same set and rule to them behind `cfg$modis_nearshore` (steps 2 and 3). Branch `10-modis-nearshore-hybrid`, PR #13, 22 October 2026. The plan, with the decisions it rests on, is `issue10-modis-hybrid-plan.md`.

**The tracked deliverables (`out/5min/ecospace_ascii/`, `out/5min/plots/`) are still the 6 October 2026 maps.** Both defaults stay `"none"`; the hybrid deliverables were produced locally, are described here and in the #10 thread, and will be committed when #5 accepts them (then both defaults flip and the maps are regenerated once).

## What changed in the pipeline

- **`scripts/process_hybrid.R`** (new): `fn.nearshore_mask()` and `fn.clip_2_hybrid()` moved here from `scripts/process_VIIRS.R`, unchanged in behaviour (run 0 below proves it), because they are no longer VIIRS-specific.
- **`fn.clip_2_hybrid(file_sat_clipped, file_hull_clipped, file_mask, file_depth, dir_out, source = "viirs" | "modis", months = NULL)`**: takes any satellite-clipped stack; `months` keeps only the layers named (the driver passes the MODIS months that have no VIIRS layer, i.e. the months the cascade serves from MODIS); writes `*_clipped_hybrid` for VIIRS (as in #11) and `*_clipped_hybrid_modis` for MODIS; the `months` table gains `source`.
- **`make_redtide_ascii(file_hybrid_modis = NULL)`** (`scripts/polygon_clipping_rt.R`): cascade `hybrid > VIIRS > hybrid_modis > MODIS > hull`; `clipping_source.csv` gains `hybrid_modis` and the `use` value `"hybrid_modis"`; `hybrid_changed` is computed for either hybrid against the satellite layer it was built from; a MODIS hybrid month that also has a VIIRS layer stops the run.
- **Config** (`run_redtide_maps.R`, `config.local.example.R`): `cfg$modis_nearshore = "none"` (default) or `"mask5"`, validated with `viirs_nearshore` right after `config.local.R` (needs `use_viirs` and `use_modis`; both rules name the same set when both are on). Step 5 now clips to VIIRS (5b) and MODIS (5c) first, then builds the nearshore set once and the hybrids (5d). The VIIRS log lines are unchanged, so the #11 checks still read them; new lines name the MODIS rule and the MODIS months changed.
- **README**: cascade diagram and bullet, pipeline table, config table, outputs tree.

## How to run

```
# step 1, no pipeline run (needs out/5min/clipped/ from the last run, the nearshore_mask_mask5.grd
# of a run with a nearshore rule on, and the 6 Oct 2026 combined stack in
# docs/issue11_nearshore-hybrid-pipeline/hoard/before/combined/)
RT_QA_STAGE=examine Rscript docs/issue10_modis-nearshore-hybrid/check_modis_hybrid_issue10.R   # ~1 min; RT_QA_PNG_DIR=<dir> adds PNG previews of fig 1

# steps 2 and 3: three pipeline runs (config.local.R: cfg$fwc_refresh <- FALSE), each followed by a stage
cfg$viirs_nearshore <- "mask5"; cfg$modis_nearshore <- "none"    # run A, then:
RT_QA_STAGE=regress Rscript docs/issue10_modis-nearshore-hybrid/check_modis_hybrid_issue10.R   # equals the #11 mask5 run byte for byte; copy the outputs to hoard/before/
cfg$viirs_nearshore <- "mask5"; cfg$modis_nearshore <- "mask5"   # run B, then:
RT_QA_STAGE=mask5   Rscript docs/issue10_modis-nearshore-hybrid/check_modis_hybrid_issue10.R   # only the MODIS months with a nearshore hull change; copy the outputs to hoard/after/
cfg$viirs_nearshore <- "none";  cfg$modis_nearshore <- "none"    # run 0, then:
RT_QA_STAGE=none    Rscript docs/issue11_nearshore-hybrid-pipeline/check_hybrid_issue11.R      # the unchanged #11 check: the 6 Oct 2026 deliverables byte for byte
RT_QA_STAGE=compare Rscript docs/issue10_modis-nearshore-hybrid/check_modis_hybrid_issue10.R   # the whole record, three variants, from the hoard copies
```

After each run, `git checkout -- out/5min/ecospace_ascii out/5min/plots` restores the tracked deliverables.

## Files

| File | What |
|---|---|
| `issue10-modis-hybrid-plan.md` | the plan: context and preview numbers, GitHub workflow, the four steps, verification |
| `check_modis_hybrid_issue10.R` | the check script, stages `examine`, `regress`, `mask5`, `compare` |
| `tables/examine_months_issue10.csv` | one row per MODIS-served month (123): fit status, nFLH polygons, cells changed, and before / after the rule: footprint and bloom area (km2 at or above 10,000 and 100,000 cells/L), maximum, mean over water, total exposure, cells at or above 10k / 100k / 1M cells/L, water samples >= 10,000 cells/L and > 1,000,000 cells/L with how many the map includes |
| `tables/examine_annual_issue10.csv`, `tables/examine_groups_issue10.csv` | the same summed by year and by month group (all 123; 2002-2011; 2022-12 and 2025; months with at least 5 such samples; of those, under half included before; months with such samples but no cell at 10,000 cells/L) |
| `tables/excluded_samples_issue10.csv` | one row per water sample >= 10,000 cells/L outside the MODIS footprint (799): month, position, count, class, template cell, in the set or not, distance to the coast, recovered by the rule or not |
| `tables/excluded_bands_issue10.csv` | all water samples >= 10,000 cells/L of the MODIS months by distance to the coast (0-2, 2-5, 5-10, > 10 km): in the set, excluded before, recovered, excluded after, share included before / after |
| `tables/modis_coverage_issue10.csv` | the 136 set cells: depth, distance to the coast, months MODIS-positive, months hull-positive, months the rule changes |
| `tables/modis_never_positive_bands_issue10.csv` | water cells MODIS never marks positive over the 123 months, by distance band |
| `tables/md5_runA_issue10.csv`, `tables/md5_runB_issue10.csv` | MD5 of the 504 ASCII files of run A and run B against the 6 October 2026 baseline and the #11 `mask5` run, with the `clipping_source.csv` columns of the run |
| `tables/hybrid_modis_vs_prototype_issue10.csv` | the MODIS hybrid stack of run B against the examine prototype, 11 metrics per month |
| `tables/record_months_issue10.csv` | all 504 months, three variants (the 6 October maps, the VIIRS hybrid, both hybrids): total exposure, cells at or above 10k / 100k / 1M cells/L, samples >= 10,000 and > 1,000,000 cells/L included |
| `tables/record_annual_issue10.csv`, `tables/record_groups_issue10.csv` | the same summed by year and by month group (all 504; hull, VIIRS, MODIS, satellite months) |
| `tables/cells_modis_issue10.csv` | per water cell over the 123 MODIS months: cumulative exposure and cell-months at or above 100,000 and 1,000,000 cells/L, run A vs run B |
| `figures/fig1_examine_months_issue10.pdf` | the 12 months with the largest gain in samples included, then the 8 months with such samples but no bloom cell: samples | MODIS-clipped (the delivered map) | hybrid | hull-clipped with the set shaded; count boxes |
| `figures/fig2_examine_series_issue10.png` | the 123 MODIS months as a series: total exposure, cells at or above 10k / 100k / 1M cells/L, share of samples included; before and after; all-zero MODIS maps shaded (run B reproduces the prototype, so this is also the run-B series) |
| `figures/fig3_excluded_samples_issue10.png` | the 799 excluded samples on the map (recovered or not) and their distance to the coast (ECDF) |
| `figures/fig4_record_2002-2026_issue10.png` | the record from the first satellite month (2002-07) to 2026, the three variants, with the clip source of each month shaded; the hull months before 2002-07 are identical in every variant and are left out |
| `figures/fig5_cells_modis_issue10.png` | per cell over the MODIS months: cumulative exposure (log colour) and cell-months at or above 100,000 cells/L; MODIS-only, MODIS hybrid, difference; the fig 1 map palette |
| `comments/examine_summary.md`, `comments/compare_summary.md` | the tables above in markdown, as the script writes them |
| `hoard/` (gitignored) | local copies of the run A (`before/`) and run B (`after/`) outputs the compare stage reads |

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
4. **Reading for the go / no-go:** the same rule applied to the MODIS months changes little in the aggregate (+2% exposure) and does exactly what it was meant to do nearshore (99% of the coastal samples included, as in the VIIRS era), so the record would carry one nearshore treatment across the satellite eras instead of a step at 2012 and 2025. A MODIS-specific set, for a product of different resolution, remains a possible follow-up. Holden gave the go on 22 October 2026.

### Steps 2 and 3: the rule in the pipeline and the three runs (22 October 2026, checkpoint 2)

| run | `viirs_nearshore` / `modis_nearshore` | minutes | result |
|---|---|---|---|
| A | `mask5` / `none` | 7.0 | **0 of 504 ASCII files differ from the #11 `mask5` run** (the refactor and the cascade change alter nothing); `clipping_source.csv` equals the #11 one apart from the new all-FALSE `hybrid_modis` column; 155 hybrid / 123 modis / 226 pred; the log says `Nearshore rule (MODIS): none` |
| B | `mask5` / `mask5` | 7.2 | **87 of 504 files differ from run A, exactly the MODIS months with `hybrid_modis` and `hybrid_changed`**; 155 hybrid / 123 hybrid_modis / 226 pred; the MODIS hybrid stack equals the MODIS-clipped stack outside the set and the cell-wise maximum inside it, never below it, and equals the examine prototype in all 123 months on 11 metrics; the VIIRS hybrid and hull months are byte-identical to run A; the log names the rule and the 87 months |
| 0 | `none` / `none` | 7.7 | **0 of 504 files differ from the 6 October 2026 baseline** (the unchanged #11 stage `none`); the log says `Nearshore rule: none` and `Nearshore rule (MODIS): none` |

**The whole record as Ecospace reads it** (stage `compare`; the 6 October maps -> the VIIRS hybrid of #11 -> both hybrids):

- Over all 504 months 1985-2026: total exposure 8.87e9 -> 9.29e9 (+4.7%) -> 9.35e9 (+5.3%); the share of the in-situ water samples >= 10,000 cells/L the projection includes 72.4% -> 93.0% -> 94.7% (12,861, 16,522 and 16,821 of 17,760); the high samples (> 1,000,000 cells/L) 78.5% -> 96.9% -> 97.9% (of 2,195).
- Over the 278 satellite months: total exposure +6.4% -> +7.3%; samples included 63.2% -> 90.8% -> 93.0%; high samples 70.6% -> 95.8% -> 97.1%. The 226 hull months are untouched (99.8% of their samples included in every variant).
- Cell-months at or above 10,000 / 100,000 / 1,000,000 cells/L over the record: 35,606 -> 37,220 -> 37,598; 13,290 -> 13,919 -> 14,018; 1,716 -> 1,788 -> 1,799.
- Per cell over the MODIS months, 105 water cells gain cumulative exposure (median 1.5e5 cells/L summed, max 8.9e6), all along the coast and in the bays; 45 cells gain 1 to 9 cell-months at or above 100,000 cells/L, 8 cells gain at 1,000,000.

Checks the stages enforce. Stage `regress`: the 504 files exist and no others; MD5s equal the #11 `mask5` run; use counts 155 / 123 / 226; `hybrid_modis` all FALSE; 121 `hybrid_changed`; the log holds the VIIRS `mask5` line, the MODIS `none` line and the `fwc_refresh = FALSE` line. Stage `mask5`: use counts 155 / 123 / 226 with `hybrid_modis`; the changed files are exactly the `hybrid_modis & hybrid_changed` months and number 87; the set raster has 136 cells and 10,227 km2; the MODIS hybrid stack equals the MODIS-clipped stack outside the set and the cell-wise maximum inside it, never below it; the 11 per-month metrics equal the examine prototype in every month; no cell is removed; the combined stack equals the #11 `mask5` combined stack outside the MODIS months and the MODIS hybrid inside them. Stage `compare`: the three stacks have NA exactly on the land cells and a value on every water cell; run B equals run A outside the 87 changed MODIS months and run A equals the 6 October maps outside the 121 changed VIIRS months; nothing falls between variants; the MODIS-month totals of run B equal the examine stage. Two runs of every stage give byte-identical CSVs and PNGs.
