# RedTideMaps issue #15: the land-adjacent nearshore rule on the Ecospace basemap

Code plan for branch `15-test-adjacent-land-cells-hybrid` (WFS-FEM/RedTideMaps, created from main `0dd2b2b`), approved by Holden on 22 October 2026. Examine-only, like step 1 of #10: no pipeline change, no pipeline run, one check script run from the stacks on disk, a checkpoint comment on #15, then the #5 call chooses between `mask5` and this rule.

## 1. Context (the review)

**Where things stand (22 Oct 2026).** PRs #12 (#11, VIIRS mask5), #13 (#10, MODIS mask5) and #14 (#5 summary) are merged. The pipeline can apply `mask5` to both sensors behind `cfg$viirs_nearshore` / `cfg$modis_nearshore`, both default `"none"`; the tracked deliverables are still the 6 Oct 2026 maps. The last run on disk is run 0 (both `none`): `out/5min/clipped/clipping_source.csv` has 155 viirs / 123 modis / 226 pred. Holden's `config.local.R` has `fwc_refresh = FALSE` and both keys `"none"`. The #5 call (accept mask5 for both sensors, flip the defaults, regenerate, commit the 504 ASCII files) waits for this test.

**What #15 asks** (opened by Holden, 22 Oct 2026, no comments yet): define "nearshore" from the Ecospace basemap itself, not the Natural Earth coastline: a water cell that shares an edge or a corner with a land cell. In satellite months (VIIRS or MODIS) those cells take the sdmTMB projection unclipped; hull months are untouched. Two questions: (1) does the set cover the cells the VIIRS mask hides, and if not, adapt the rule; (2) what it does to the metrics: in-situ samples accounted for, total exposure, cells added at the thresholds (>=10k, >=100k, >1M cells/L).

**Facts established today (read-only):**

- The RedTideMaps template `template rasters/depth 5min 66x78.asc` is numerically the EcospaceBasemap grid `output/5min/depth/depth_5min.asc` (EcospaceBasemap commit `462de94`): same header, 1,310 NODATA cells in both, 0 NODATA mismatches, values within 0.01 (formatting and line endings differ, so MD5s differ). Land on the basemap is exactly NODATA of the depth grid (`make_WFS_basemaps.R` L68-80: ETOPO elevation > 0 is NA); the exclusion layer marks water deeper than 500 m and must not be used as land. EcospaceBasemap has `fn.build_coastal()` (`R/port_functions.R` L175-216), `terra::adjacent(directions = 8)` from the land side; the water side of the same pairs is the #15 set.
- Edge-or-corner adjacency on that grid: 202 water cells, 177 in the Gulf domain (outside the Atlantic-side box east of -82 E and north of 28.5 N), 13,311 km2. Rook adjacency: 128 in the domain; within 2 cells: 338 (25,417 km2).
- Coverage: the 177-cell set covers 78 of the 84 template cells in the static VIIRS mask and 124 of the 136 `mask5` cells; 53 of its cells are not in `mask5` (depth 1 to 24 m). The 6 mask cells missed: 13 and 14 (top grid row, 30.458 N, the land north of them is off-grid, Destin area), 333, 736, 3573, 3651 (second-row cells). Adjacent OR VIIRS static mask = 183 cells.
- The raw sdmTMB stack `out/5min/sdm/sdmTMB_log_stack_198501-202612.grd` is in cells/L (not log), 504 layers, NA on every water cell in the 170 months without a fit, positive on every water cell in fitted months (2018-10: 694 to 1.46e7). The satellite-clipped layer equals the raw layer where the satellite is positive and 0 elsewhere (checked for 2018-10), so raw >= satellite-clipped everywhere: the #15 fill never lowers a cell, and it gives the whole set a nonzero value in every fitted satellite month, samples or not. That is the main difference from `mask5`, whose hull fill is sample-supported.

**Decisions by Holden today (22 Oct 2026):**

- D1 fill: the headline variant is the issue's rule (raw sdmTMB inside the set); the same set with the `mask5` fill (max of satellite-clipped and hull-clipped) is tabulated as a comparison so the tables separate the set from the fill.
- D2 adaptation candidate: adjacent OR VIIRS static mask (183 cells), carried through the full metrics beside the plain set.
- D3 domain: the Gulf domain of `mask5`; **always exclude the Atlantic Ocean cells** (standing rule, to be saved to memory as feedback once out of plan mode).

## 2. GitHub workflow

1. Work on the existing branch; draft PR "Test the land-adjacent nearshore rule on the Ecospace basemap (#15)" against `main` after the first commit; body with the checkpoint list; "Closes #15" only when Holden says the test closes the issue.
2. Commits by type: `docs:` (this plan as `issue15-adjacent-land-plan.md`, README skeleton, folder `.gitignore`), `qa:` (the script and its outputs), `docs:` (README results, a row in `docs/README.md`, one line in the #5 summary "pending" section).
3. **Checkpoint 1** after the examine stage: comment on #15 with the coverage table, the group table and the figures (draft `comments/issue15-examine-comment.md`, gitignored); try `gh issue comment` once, on a denial hand Holden the command with the `!` prefix. Work pauses for the #5 call (mask5, the #15 rule, or the adapted rule).
4. Explain the why of each GitHub step briefly as it happens (Holden's request, 22 Oct).

## 3. Step 1: the examine stage (no pipeline run)

Folder `docs/issue15_adjacent-land-hybrid/` with `check_adjacent_hybrid_issue15.R` (stage `examine`, env `RT_QA_STAGE`, default `examine`), `tables/`, `figures/`, `comments/`, `.gitignore` (`hoard/`, `issue15-*-comment.md`, as `docs/issue10_modis-nearshore-hybrid/.gitignore`). Deterministic, no RNG, byte-identical CSVs and PNGs on rerun, 1 to 2 min.

Built by copying the helpers of `docs/issue10_modis-nearshore-hybrid/check_modis_hybrid_issue10.R` (L48-262: `.root`, `one_file`, `grd`, `read_mat`, `norm_map`, `same`, `fmt_n`, `load_samples`, `samples_of`, `area_ge`, `metrics_of`, `expo_of`, `round_cols`, `md_table`, `dist_coast_km`, `band_of`, the drawing helpers, `write_pdf`) and its `draw_record` (L775) and `draw_series` (L466); the check scripts cannot be sourced, copying is the convention. Thresholds and wording: `>=10k`, `>=100k`, `>1M cells/L`; new columns named by threshold (`share_ge10k`), never low/medium/high.

**Inputs, all on disk:** the depth template; the EcospaceBasemap depth grid (`C:/Repos/WFS-FEM/EcospaceBasemap/output/5min/depth/depth_5min.asc`, path overridable with env `RT_BASEMAP_DEPTH`; the stage stops if it is missing: the set is the basemap's by proof, and the pipeline gains no cross-repo dependency); the VIIRS stack `VIIRS/VIIRS_201201-202412.grd` (for the static mask, NA in >= 90% of the layers, as `fn.nearshore_mask()` in `scripts/process_hybrid.R` L66-71); `out/5min/clipped/` VIIRS-clipped (155 layers), MODIS-clipped (275, keep the 123 with `use == "modis"`), hull-clipped (504) and `nearshore_mask_mask5.grd`; the raw stack `out/5min/sdm/sdmTMB_log_stack_198501-202612.grd`; `out/5min/clipped/clipping_source.csv` (155 / 123 / 226 asserted); the 6 Oct combined stack in `docs/issue11_nearshore-hybrid-pipeline/hoard/before/combined/` and the run-B (both mask5) combined stack in `docs/issue10_modis-nearshore-hybrid/hoard/after/combined/`; the latest `*_filtered.Rdata`; `docs/issue6_VIIRS-zeros/tables/clip_comparison_issue6.csv` (`fit_status`, `use`, `viirs_status`, `flag_zeroed_fit`, `zeroed_material`, `n_pos_1e4_water`); `data/coastline/ne_10m_coastline_wfs.gpkg` (distances only); `docs/issue11_nearshore-hybrid-pipeline/tables/nearshore_set_issue11.csv` and `docs/issue8_nearshore-hybrid/tables/mask_cells_issue8.csv` (cross-checks: 136 and 84).

**The sets** (Gulf-domain water cells; `raster::adjacent(depth, cells = water, directions = 8, pairs = TRUE)`, keep the water cell of every pair whose neighbour is land, the mirror of `fn.build_coastal()`): `adj8` (177, the issue's rule), `adj4` and `ring2` (coverage only), `adj8_mask` = adj8 OR VIIRS static mask (183, D2). The 25 land-adjacent cells of the Atlantic box are flagged in the set table and never filled (D3).

**The variants, satellite months only** (278 = 155 VIIRS + 123 MODIS; the 226 hull months are identical in every variant and enter the record tables as context), each a normalised matrix (NA -> 0 on water, land NA):

| key | set | fill inside the set | source |
|---|---|---|---|
| `v6oct` | none | satellite-clipped (the delivered maps) | #11 hoard/before combined stack, asserted equal to the on-disk VIIRS/MODIS-clipped layers |
| `mask5` | mask5 (136) | max(satellite, hull-clipped), both sensors | #10 hoard/after combined stack, asserted equal to the recomputation |
| `adj8_sdm` (headline) | adj8 (177) | raw sdmTMB | computed: `A <- S; A[set, ] <- pmax(S[set, ], R[set, ])` (equals `R[set, ]` by the clipping relation, asserted) |
| `adj8m_sdm` | adj8_mask (183) | raw sdmTMB | computed |
| `adj8_hull` | adj8 (177) | max(satellite, hull-clipped) | computed (D1 comparison) |

**Tables** (`tables/`, `_issue15.csv` suffix):

- `set_cells`: one row per Gulf-domain water cell in any candidate set or in mask5: `cell, lon, lat, depth_m, km2, adj8, adj4, ring2, viirs_mask, mask5, adj8_mask, dist_coast_km, atlantic, n_sat_pos_months, n_hull_pos_months`.
- `set_coverage`: one row per candidate (`adj4, adj8, ring2, adj8_mask, mask5`): cells, km2, VIIRS-mask cells covered (of 84), mask5 cells covered (of 136), cells not in mask5; plus `set_missed_mask_cells` listing the mask cells each candidate misses (the 6 of adj8 with lon, lat, depth, row position).
- `examine_months`: 278 rows: `yrmo, year, month, use, fit_status, viirs_status, zeroed, headline, viirs_pos_fitted, samples_ge10k, samples_gt1M`, then per variant `exposure, n_ge10k, n_ge100k, n_gt1M, km2_ge10k, max_cells, cells_changed_vs_v6oct, in_ge10k, in_gt1M, share_ge10k`.
- `examine_groups` and `examine_annual`: sums and shares by group (all 278 satellite months; 155 VIIRS; 123 MODIS; the 58 zeroed, 16 headline and 60 VIIRS-positive fitted months of #6; months with >= 5 samples >= 10k cells/L) and by year, every variant side by side; ratios to `v6oct` and to `mask5`.
- `record_months`: all 504 months, the five variants on the #10 `record_months` columns (hull months identical by construction, asserted), so the #5 call sees the full record.
- `fill_values`: what the fills write into the set cells, by class of value (0, <=1k, 1k-10k, 10k-100k, 100k-1M, >1M cells/L) and by group, `mask5` vs `adj8_sdm` vs `adj8_hull`: shows how much of the raw fill is background-level.
- `excluded_samples` and `excluded_bands`: water samples >= 10k cells/L outside the delivered footprint in satellite months, by distance band, recovered by each variant.
- `cells_sat`: per water cell over the 278 months, cumulative exposure and cell-months >= 100k cells/L under `v6oct`, `mask5`, `adj8_sdm`, and the differences.

**Figures** (`figures/`): `fig1_sets_issue15.png` (two map panels: adj8 vs mask5, cells in both / adj8 only / mask5 only, VIIRS static mask outlined, the 6 missed cells marked; adj8_mask vs mask5), `fig2_record_2002-2026_issue15.png` (the #10 fig 4 layout from the first satellite month: exposure, cells >=10k / >=100k / >1M, share of samples included; `v6oct` black, `mask5` purple, `adj8_sdm` orange, `adj8m_sdm` dashed, clip source shaded), `fig3_months_issue15.pdf` (vector PDF, Holden's rule for grids: the 16 headline months and the 12 months where `adj8_sdm` and `mask5` differ most in exposure, one row each: samples | delivered map | mask5 | adj8_sdm | raw sdmTMB with the set shaded, count boxes; `RT_QA_PNG_DIR` previews), `fig4_cells_issue15.png` (per cell over the satellite months: mask5, adj8_sdm, difference; the #10 fig 5 palette). `comments/examine_summary.md`: the group, coverage, fill and headline tables in markdown, as the script writes them.

**Checks the stage enforces:** basemap and template agree on NODATA cell for cell (1,310) and on values within 0.01; adj8 has 177 Gulf-domain cells and no Atlantic cell is filled; the static mask has 84 template cells in the domain and `mask5` on disk has 136 (= the #11 table); adj8 covers 78 of 84 and adj8_mask 84 of 84; every variant has NA exactly on land; raw >= satellite-clipped on every water cell of every satellite month, equal where the satellite is positive; each variant >= `v6oct` everywhere and equal outside its set; `adj8_sdm` changes no month without a fit; `v6oct` and `mask5` rebuilt from the on-disk stacks equal the hoard stacks; the per-month sample counts equal `n_pos_1e4_water` of the #6 table; the `mask5` group totals equal `record_groups_issue10.csv`; group sizes 278 / 155 / 123 / 58 / 16 / 60; headline numbers frozen in an `expected` list after the first run (as #10 did), so a rerun that differs fails loudly.

## 4. Checkpoint 1 and the #5 call

Comment on #15: the answer to question 1 (coverage, the 6 missed cells, the adapted rule), the answer to question 2 (the group table: samples included, exposure, cells added at each threshold, for `mask5`, `adj8_sdm`, `adj8m_sdm`, `adj8_hull` against the delivered maps), the fill-values table (how much of the raw fill is below 10k cells/L), fig 2 and fig 3, and a plain reading: what the two rules share, where they differ, and what each means for the maps Ecospace reads. No recommendation beyond the evidence unless Holden asks. Then the planning session for the #5 call.

## 5. Step 2, only if the call picks a #15 rule (not in this PR)

Sketch, to size the follow-up: `fn.nearshore_mask()` gains `rule = "adjacent"` (from the depth template alone, `raster::adjacent`, Gulf domain) and `"adjacent_mask"` (plus the VIIRS static mask); `fn.clip_2_hybrid()` gains `fill = c("hull", "sdm")` and a `file_pred` argument for the raw stack; `cfg$viirs_nearshore` / `cfg$modis_nearshore` accept the new values and a `cfg$nearshore_fill` key; `make_redtide_ascii()` unchanged; three verification runs as #10 (none = 6 Oct byte for byte; the new rule = the examine prototype on 11 metrics; mask5 unchanged); README and config example. Then the defaults flip and the deliverables are regenerated once.

## 6. Verification

1. Run the stage twice: identical MD5s of every CSV and PNG; all assertions pass.
2. Hand spot checks: cells 13 and 14 are in the mask but not in adj8 (top row); in 2017-01 (headline) the `adj8_sdm` values inside the set equal the raw layer and outside it the delivered map; one MODIS month (2003-02) likewise; one month without a fit is unchanged in every variant.
3. `v6oct` totals equal `tables/exposure_months_issue11.csv` (before) and `mask5` totals equal `record_months_issue10.csv` (`_v10` columns), asserted.
4. `git status` clean apart from the gitignored comment draft; the tracked deliverables untouched (no pipeline run).

## 7. Run notes

- `"C:/Program Files/R/R-4.5.1/bin/x64/Rscript.exe" docs/issue15_adjacent-land-hybrid/check_adjacent_hybrid_issue15.R` from the repo root; close any output PDF or PNG in a viewer before a rerun (an open file makes `pdf()` / `png()` fail).
- Memory: the 504-layer raw stack is 21 MB in memory; the stage reads three 504-layer stacks and two short ones, well under the machine's limits; nothing else running.

## Part 2 (22 October 2026): the union set against mask5, hull fill

After checkpoint 1 Holden kept the hull fill and narrowed the question to the set. The sections below are the approved follow-up plan; section numbers restart.

Follow-up on branch `15-test-adjacent-land-cells-hybrid` (draft PR #16, checkpoint 1 posted 22 Oct 2026). Holden's reading of the checkpoint: keep the hull fill (the sample-supported footprint of #8 / #11 / #10), not the raw sdmTMB fill. The only comparison of interest now is the set: `mask5` (VIIRS mask or centre within 5 km of the coastline) against the union of `mask5` and the land-adjacent cells, which captures every VIIRS-masked cell and every cell near the shore by distance or by grid proximity.

### 1. Context: what the data say (read-only checks, 22 Oct 2026)

- `mask5` is exactly "in the static VIIRS mask OR centre within 5 km of the Natural Earth coastline", 136 cells, 10,227 km2 (recomposed from the #15 set table, equal to the pipeline raster). The land-adjacent set (edge or corner with a NODATA cell of the basemap, Gulf domain) is 177 cells. Their **union is 189 cells, 14,205 km2** = `mask5` + 53 adjacent-only cells; it covers the 84 mask cells, the 132 within-5-km cells and the 177 adjacent cells by construction, and is `mask5` plus one `raster::adjacent()` call on the depth template (no new input).
- **Why the two parts differ (Holden's questions).** They see different land. Adjacency reaches further than 5 km on the open coast: the 53 adjacent-only cells have centres 5.0 to 12.1 km (median 6.6) from the coastline, because a cell is 8 to 9 km wide and a corner-touching neighbour's centre lies well away from the land cell and further from the coastline inside it (Big Bend, Panhandle bays, south-west coast). Adjacency fails only where the basemap has no land cell: the 12 `mask5`-only cells (median 3.6 km from the coastline) all sit two cells from the nearest basemap land cell, with the coastline within 5 km of their centre. Two are Choctawhatchee Bay cells cut by the map edge (13, 14; treating the northern grid edge as land catches exactly these two and nothing else). Nine are Gulf-side cells against barrier islands or thin peninsulas that the 5-arcmin ETOPO grid draws as water while the Natural Earth coastline draws them as land: 91 and 92 against Okaloosa Island at Destin, 333 off Shell Island (Panama City), 413 off Crooked Island, 649 west of St Joseph Peninsula, 736 and 812 off St George Island (Apalachicola), 2710 off Anna Maria Island at the Tampa Bay mouth, 3573 in Pine Island Sound behind Captiva; 3651 (Sanibel, 5.3 km, in the mask) is the twelfth. All are 4 to 18 m deep and hull-positive in 13 to 157 months. Median distance to the coastline: adjacent cells 3.1 km (max 12.1), `mask5` cells 2.1 km (max 6.3).
- **With the hull fill, over the 278 satellite months:** `mask5` includes 93.0% of the water samples >= 10k cells/L (12,351 of 13,280), 97.1% of those > 1M, 85.5% in the 58 zeroed months, adds 7.3% exposure, 29,962 cell-months >= 10k, changes 208 months (121 VIIRS + 87 MODIS). The **union: 94.2% (12,515), 97.7%, 88.5%, +8.4%, 30,474 cell-months, 210 months (121 + 89)**. The gain is 164 samples and 1.1 points of exposure, all from the 53 adjacent-only cells. The set is a second-order choice once the fill is the hull.

### 2. Step 1: add the union with the hull fill to the examine stage (in PR #16)

`docs/issue15_adjacent-land-hybrid/check_adjacent_hybrid_issue15.R`, stage `examine`, same inputs. The three committed variants of the fill question (`adj8_sdm`, `adj8m_sdm`, `adj8_hull`) stay as the record; nothing else is added.

- Sets: `near5 <- dist_w <= 5 & domain` (the distances are already computed); assert `set5 == domain & (in_mask | near5)` (the recomposition); `union <- set5 | adj8`, asserted 189 cells, 14,205 km2, covering 84 / 132 / 177; `set_coverage` gains the row `union` and the columns `within5km_cells_covered` (of 132) and `adjacent_cells_covered` (of 177); `set_cells` gains the `within5km` and `union` flags and `nearest_land_cells` (Chebyshev distance to the nearest NODATA cell, 1 or 2 in every set cell).
- Variant: `union_hull` (189, hull fill) added to `Ms` / `set_of` / `variants`; every table takes it through the existing loops over `keys`. Freeze its headline numbers in `expected` after the first run (12,515 samples included; exposure 7,041,xxx,xxx; 210 months changed).
- Fig 1 panel 2 becomes the union: `mask5` cells in one colour, the 53 adjacent-only cells in another, the 12 `mask5`-only cells marked, the coastline drawn, the barrier-island cells readable. Fig 2 to 4 unchanged.
- `comments/examine_summary.md`: a "mask5 vs union, hull fill" table (cells, km2, coverage, exposure ratio, cell-months >= 10k / 100k / 1M, samples included overall, > 1M and in the zeroed months).
- README results: subsection "Question 3: mask5 or the union, with the hull fill" with that table, the explanation of why the two parts differ (barrier islands, the map edge, the reach of adjacency on the open coast), and the per-era numbers; the docs index row and the #5 summary line updated to say the fill question is settled (hull) and the set is the open choice. The repo copy of the plan gains this part as a section.
- Rerun twice (byte-identical); spot-check the union in 2017-01 by hand (samples included >= the 113 of `mask5`).
- Commits: `qa:` (script and outputs), `docs:` (README, index, summary, plan). Follow-up comment on #15 (draft `comments/issue15-union-comment.md`, gitignored): the answer to the set question and the table; PR #16 body updated. Then Holden picks `mask5` or the union.

### 3. Step 2, if the pick is the union: the rule in the pipeline

Superseded on 22 October 2026: Holden chose the union and moved the implementation and the final projections to a new issue, so PR #16 carries the examination only. The sketch below stands as the specification for that issue.

Rule name `"mask5adj"` (mask5 plus adjacency; the name carries the lineage).

- **`feat:`** `fn.nearshore_mask()` in `scripts/process_hybrid.R`: `rule <- match.arg(rule, c("mask5", "mask5adj"))`; a third part, `adjacent`, from the depth template with `raster::adjacent(depth, cells = which(!land), directions = 8, pairs = TRUE)` keeping the water cell of each pair whose neighbour is land, computed only for `"mask5adj"`; `set <- domain & (in_mask | near_coast | adjacent)`; the message and the returned list gain `n_adjacent_cells`; the file is `nearshore_mask_<rule>.grd` as now. `fn.clip_2_hybrid()` unchanged (the fill stays the hull). The `"mask5"` path is untouched by construction.
- **`config:`** `run_redtide_maps.R` validation (L103-115) accepts `"mask5adj"` for both keys (same-set check unchanged); the log line already names the rule and the set size; `config.local.example.R` lists the value; root README config table and cascade bullet mention it.
- **`test:`** stage `rule` in the #15 script, after a run with both keys `"mask5adj"` and `fwc_refresh = FALSE`: use counts 155 hybrid / 123 hybrid_modis / 226 pred; the set raster has 189 cells and 14,205 km2; the two hybrid stacks equal the satellite-clipped stacks outside the set and the cell-wise maximum inside it, never below; the per-month metrics equal the `union_hull` prototype in all 278 months (the 11 metrics of the #11 check); the changed ASCII files are exactly the `hybrid_changed` months (210 = 121 VIIRS + 89 MODIS); MD5 table against the 6 Oct baseline. Then run 0 (both `"none"`): the unchanged #11 stage `none` (6 Oct byte for byte). Two runs of about 8 min each, alone on the machine, `git checkout -- out/5min/ecospace_ascii out/5min/plots` after each.
- **`docs:`** README results for the runs; one line each in the #11 and #10 READMEs (a third rule value exists); the #5 summary section 6 names the chosen rule.

### 4. Then the #5 closure (the existing implementation plan, rule name substituted)

Flip both defaults to the chosen rule in `run_redtide_maps.R`, `config.local.example.R` and the README; regenerate once (decide `fwc_refresh`); commit the 504 ASCII files and the plots; export to Ecospace; closing comment on #5; PR #16 marked ready and merged with a merge commit. Holden's `config.local.R` still has both keys `"none"` and `fwc_refresh = FALSE`.

### 5. Verification

1. Step 1: the stage runs twice with identical MD5s; the recomposition and coverage assertions pass; the union numbers of section 1 (189 cells, 12,515 samples included, +8.4%, 210 months) reappear in the tables; fig 1 panel 2 shows the 53 adjacent-only and 12 `mask5`-only cells.
2. Step 2: the `rule` stage reports 278 of 278 months equal to the prototype and 210 changed files; the `none` stage passes; `git status` clean apart from the gitignored comment drafts.

### 6. Run notes

- `"C:/Program Files/R/R-4.5.1/bin/x64/Rscript.exe" docs/issue15_adjacent-land-hybrid/check_adjacent_hybrid_issue15.R` from the repo root, about two minutes; close any output PDF or PNG in a viewer first.
- Wording: `>=10k`, `>=100k`, `>1M cells/L`; the Atlantic-side box is always excluded (asserted).
