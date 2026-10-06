# RedTideMaps review-only audit: Issues Flagged, Recommended Changes and Decisions

## 0. Status

```
Issue: none (review-only)        Branch: main        Pull request: none
Mode: review-only (full audit scope, with second-audit carry-overs from docs/issue3-hull-fix-plan.md)
Org profile: wfs-fem
Reviewer: Holden Harris, with Claude Code        Original author: Holden Harris (own past code; Vilas and Chagaris credited, not asked)
Line numbers refer to commit: a875d64
Last completed step: §5 step 8 (fix design, plan, decisions, needs-examination); statuses set at Pause 5
Next step: §5 step 5 (clean baseline rerun in progress, run2) then step 9 (static Phase 8 checks, Doc B §0, Doc A §6-7, §11)
Last updated: 2026-10-06
```

Documents live untracked in `docs/review/` on the reviewer's clone; no commit, issue, branch or pull request is made in this mode. If the audit is later promoted to `audit` mode, this file is renamed `issueN-<slug>-log.md` and §10 is filled.

## 1. Scope and targets

1. **The reviewer** (Holden Harris) runs it: Windows 11 Enterprise, R 4.5.1, clone at `C:/Repos/WFS-FEM/RedTideMaps`, `config.local.R` with the OneDrive Ecospace root and export off, FWC cache through 2026-09-17 at the start of the audit, 334 cached fits. Network available.
2. **The original author**: the reviewer (own past code for the operational layer). Daniel Vilas wrote the sdmTMB and clipping code and David Chagaris designed the workflow; their layouts are not available and nothing in the tracked code depends on them.
3. **A fresh clone**: any machine with R ≥ 4.5, the 19 packages and network; no data needs placing because every input is tracked or pulled. Not exercised in review-only mode; the static review says what would happen.

In scope: the driver and the six files in `scripts/` that it sources, `scripts/qa/check_hulls_issue3.R`, the configuration files, the README, the tracked inputs and the 5-min deliverables. The MODIS ERDDAP update path and the Ecospace export are reviewed statically (no network pull, export stays off).

Out of scope (decision 1): the methods in `scripts/old scripts/` and `scripts/experimental/` (inventoried under the E lens only); the 15-min outputs in `out/15min/` (noted when last built, not regenerated or drift-checked).

Documents produced: Doc A `science-review.md` and Doc B `workflow-review.md` written fresh (none existed); this Doc C.

## 2. Findings register

```
Carried over from docs/issue3-hull-fix-plan.md (merged in PR #4, 30 Sept 2026):
- Unticked acceptance criteria: none (all six in plan §8 were reported met in commit 23a5935).
- Needs-examination items still open: the positive-sample definition (plan §6.4 last bullet, decision 4):
  whether background-level detections (≤ 1,000 cells/L) should define a footprint and enter the fits.
  The follow-up issue the plan promised has not been opened (gh issue list shows only #1 and #3, both closed). Now M3.
- Open sub-issues: none.
- README "Known caveats" entries: the README has no such section; "Known limits of the incremental rerun"
  lists two (late corrections not picked up; months with a cached fit are not refit when new data arrive). Now R3.
- Ops decision log: plan §9 step 5 asked for a line in WFS-FEM/Ops docs/decisions.md for the 75 km default;
  not verifiable from this repository.
Closed findings from that fix were re-checked on 6 Oct 2026: single-linkage hull code present
(scripts/polygon_clipping_rt.R:59-150), five hull keys in cfg and the config example, hull_diagnostics.csv
written, .Rhistory untracked, kmeans and runif gone (static sweep: no rng_call hits outside scripts/experimental/).
First run step for this audit: drift check of a fresh run against the committed deliverables (§3, Doc B §9.1).
```

Smoke (6 Oct 2026): anchor OK (`RedTideMaps.Rproj` tracked, checked at `run_redtide_maps.R:25-35`); 16 files parsed with 0 errors (`static_sweep.R`); 19 required packages installed, optional `rerddap` missing; inputs OK (templates, MODIS polys, URL file, 155 VIIRS tifs, FWC cache); FWC endpoint HTTP 200. No smoke failure.

### 2.1 Portability (P)

| ID | Where (file:line) | Problem | Kind | Severity | Status |
|---|---|---|---|---|---|
| P1 | `run_redtide_maps.R:207-216`; `scripts/process_VIIRS.R:22-23`; `scripts/_setup.R:102-109` | No input manifest or up-front input check. Missing inputs fail at different depths: templates stop before any work (good), the URL file stops at step 1, VIIRS tifs stop inside step 5 after the fits and predictions have run, and missing MODIS polygons are silently skipped (`rt_log("No FLH polys found; skipping MODIS clipping.")`), so a `proj_dir` override pointing at a folder without `MODIS/` quietly turns 123 months into hull months | mechanical | medium | fix: step A3 |
| P2 | `scripts/_setup.R:28-31,48,54,60-63,70`; `README.md:213` | Seven of the 19 required packages are not called by any live code: `lubridate`, `cluster`, `viridis`, `scales`, `cowplot`, `ggh4x` (no call in the driver or the six stage files; checked by function-name grep) and `rvest` (only in the never-called `fn.get_habsos_data`, E1). A newcomer must install all seven or the run stops. Cross-ref E1 | mechanical | low | fix: step A3 |
| P3 | `RedTideMaps.Rproj:3-5` | `RestoreWorkspace: Default`, `SaveWorkspace: Default`, `AlwaysSaveHistory: Default`: RStudio saves and restores a workspace, which is how the 6.5 MB `.RData` (30 Sept) got into the repository root; gitignored, but every interactive session starts with stale objects loaded. Set all three to `No` | mechanical | low | fix: step A3 |
| P4 | `scripts/sdmTMB_HAB_data.R:371-372`; `scripts/process_MODIS.R:197` | `coordinates(ypred) <- ~ lon + lat`, `gridded(ypred) <- TRUE` and `spTransform()` are `sp` functions; `sp` is neither declared (`_setup.R:28-31`) nor attached; it works only because `raster` still has `Depends: sp` (raster 3.6.32). Namespace them (`sp::`) or declare `sp` | mechanical | low | fix: step A3 |

### 2.2 Reproducibility (R)

| ID | Where (file:line) | Problem | Kind | Severity | Status |
|---|---|---|---|---|---|
| R1 | `VIIRS/redtide_maps_0.1degree/` (155 tif, 156 png); `MODIS/FLH polys 200207-20250926.Rdata` (275 of 279 months); `scripts/polygon_clipping_rt.R:245-250` | Silent coverage gaps in the satellite inputs: the December 2022 VIIRS tif is absent (its PNG is present) and the MODIS polygon list lacks 2006-04, 2016-06, 2024-11 and 2024-12. The cascade handles them without a word: 2022-12 is served by MODIS and 2006-04 by the hull (verified in the 30 Sept `clipping_source.csv`). The per-month decision table is written to the gitignored `clipped/`, and neither README nor run log names the exceptions. Ask of the data provider: the one missing tif; fix: a cascade summary line in the run log and the exceptions in the README | mechanical (log, README); behavioural if the tif is obtained | medium | fix: step A3 |
| R2 | `scripts/get_HAB_data.R:118-131,166-169` | Every run, including an incremental one with nothing new, queries the FWC "Recent" endpoint; there is no use-cache-only toggle, so an outage blocks a rerun of unchanged data at step 1. The merged cache is renamed by its date range and the previous copy deleted (`unlink(old)`), so the exact inputs of an earlier run cannot be recovered. The baseline run on 6 Oct replaced `...-20260917.csv` with `...-20260922.csv` | mechanical | medium | fix: step A5 |
| R3 | `scripts/get_HAB_data.R:146-155` | `rbind(hab_existing, hab_new)` then `!duplicated()` on (HAB_ID, OBJECTID, SAMPLE_DATE, LATITUDE, LONGITUDE) keeps the cached row whenever FWC re-serves a record with the same key but a corrected count, and treats a record whose OBJECTID was renumbered as new. README "Known limits" documents the first half (`:126`) and points at `fwc_force_full`. Carry-over from the README | behavioural (if the rule changes) | low | author (§8; sub-issue at A9) |
| R4 | `scripts/sdmTMB_HAB_data.R:82-83,181-189` | `fit_warnings.csv` is written only when a run captures warnings and is not in the stale-file cleanup list, so a rerun with no refits (the normal monthly case) leaves the previous run's file in place. Evidence: `out/5min/sdm/fit_warnings.csv` dated 25 Sept beside siblings dated 30 Sept | mechanical | low | fix: step A4 |
| R5 | `out/5min/sdm/` (both `FWC HAB data 19800102-20260909_*` and `...-20260917_*` present); `run_redtide_maps.R:207-211` | Intermediates named by the cache date range (`*_filtered.Rdata`, `*_hullpolys.Rdata`) accumulate across runs and are never cleaned; `list.files(pattern = "^FLH polys")[1]` picks the alphabetically first polygon file if several exist, with no check for more than one | mechanical | low | fix: step A4 |
| R6 | `scripts/polygon_clipping_rt.R:272-277`; all 504 files in `out/5min/ecospace_ascii/` and `out/15min/ecospace_ascii/` | Deliverables carry `NODATA_value -3.4e+38` (raster's default for a float layer; no `NAflag` is passed) while the templates in `template rasters/` use `-9999`, and the first data token of every file is written as `-339999999999999996128486808808066248288.000000000000000`. Present since the May 2026 commit `6cfdf00`. Values are float32 (e.g. `96024.078125`); the no-data pattern equals the depth template's 1,310 land cells. Writing `NAflag = -9999` changes every file's bytes but no value | behavioural (bytes) | low | fix: step A8 (decision 2) |
| R7 | `out/15min/` (504 ASCII + 4 plots); `git log -1 -- out/15min` = `6cfdf00`, 22 May 2026 | The 15-min deliverables are tracked but were last regenerated before the hull fix (PR #4) and before the FWC data through September 2026; nothing in the README says which resolution is current. Out of scope for regeneration (decision 1); recorded so the staleness is known | mechanical (document) | medium | wontfix (decision 5) |
| R8 | `run_redtide_maps.R:44` (`enyr = as.integer(format(Sys.Date(), "%Y"))`) | The deliverable set depends on the run date: every month of the current year is written, so a run in January 2027 adds 12 files and the months after the last sample are zero maps (2026-10 to 2026-12 on the 30 Sept run). Mechanical here (document; pin `enyr` in the README); what a zero future month means is M6 | mechanical | low | fix: step A6 |
| R9 | `scripts/_setup.R:150-155`; `README.md:211` | No environment record travels with a run: the log has no R or package versions, there is no lock file, and the README's "Tested with R 4.5.1" is the only statement. sdmTMB fits are TMB-version sensitive (README `:224`). One `sessionInfo()` summary line per run log fixes it | mechanical | low | fix: step A3 |
| R10 | Baseline run, 6 Oct 2026 (Doc B §9.1) | The run was stopped by the session harness in stage 6 (machine out of memory) before the ASCII write. What it did produce is byte-identical to the 30 Sept intermediates (`RT_fit_matrix.RData`, `hull_diagnostics.csv`, `clipping_source.csv`) although the FWC pull added records for 17-22 Sept 2026, so the committed deliverables would have been reproduced; the only tracked changes are the two sample plots (new samples drawn) and a PDF timestamp. Found by the baseline: `sdmTMB log maps.pdf` and the combined PDF change bytes on every run through their embedded creation date, so they can never be byte-stable deliverables | mechanical (plots) | low | fix: step A6 |

### 2.3 Bugs and fragility (B)

| ID | Where (file:line) | Problem | Kind | Severity | Status |
|---|---|---|---|---|---|
| B1 | `scripts/get_HAB_data.R:241-245,292` | HABSOS branch of `fn.filter_hab_data()` mislabels two columns: the branch orders the frame `lat, lon, year, cells, month` (`:244-245`), `st_as_sf()` consumes `lon`/`lat`, `cbind(st_coordinates())` appends `X`, `Y`, and the positional rename at `:292` (`c("year","month","cells","lon","lat","geometry")`) then calls the cell-count column `month` and the month column `cells`. The FWC branch (`:246-250`) orders `year, month, cells` and is correct. Dormant: the driver only ever passes the FWC file | mechanical (fix); behavioural for HABSOS input | medium | fix: step A4 |
| B2 | `scripts/process_VIIRS.R:114` (and `:65`) | `if (mean(values(r1), na.rm = TRUE) == 0 \|\| ...)`: for a layer that is entirely NA the mean is NaN, the comparison is NA and `if` stops with "missing value where TRUE/FALSE needed". Latent: none of the 155 tifs is all-NA (checked 6 Oct; NA counts 1,002-1,012 per layer, the land cells) | mechanical | low | fix: step A4 |
| B3 | `scripts/sdmTMB_HAB_data.R:275-277,362-369`; `scripts/polygon_clipping_rt.R:190` | Months without a model become zero maps by accident: the loop writes zeros to `pred_array[, j, ...]` for `j in seq_along(mods)`, which are columns 1 and 2 (`lon`, `lat`), not the model columns; `fn.predict_monthly_sdmTMB()` then finds one unique coordinate, writes an all-NA layer ("Insufficient spatial data"), and `fn.clip_2_hulls()` turns NA into 0. Verified: `pred_array[, , "Jan", "1985"]` is 0 in all four columns. Same final map as the intended zeros | mechanical | low | fix: step A4 |
| B4 | `scripts/sdmTMB_HAB_data.R:239-240` | `predict(fit, newdata = ..., type = "response", t_i = prediction_data$month, se_fit = FALSE)`: `t_i` is not an argument of `predict.sdmTMB` (its formals are `object, newdata, type, se_fit, re_form, re_form_iid, allow_new_levels, nsim, sims_var, model, offset, mcmc_samples, nonlocal_newdata, return_tmb_object, return_tmb_report, return_tmb_data, ...`), so it is swallowed by `...`. Harmless for a spatial-only model | mechanical | low | fix: step A4 |
| B5 | `scripts/sdmTMB_HAB_data.R:141-169` | `max_attempts <- 2`: a failed `sdmTMB()` call is repeated on identical inputs. The fit is deterministic (S1: identical parameters across four fits of two months), so the second attempt can never succeed where the first failed; it only doubles the time of the 5 failing months | mechanical | low | fix: step A4 |
| B6 | `scripts/sdmTMB_HAB_data.R:118,302-306`; `run_redtide_maps.R:229-247` | Zero maps have no cause in the run log. A month is a zero map when it has 0-5 positives (`:116-118`), when both fit attempts fail (`:302-306`, "no model"), or when VIIRS shows nothing (M1); the only record is `RT_fit_matrix.RData` (gitignored) and `clipping_source.csv` (gitignored). The `Hulls:` line is the only operator-facing summary. On the 30 Sept run: 170 months with no fit attempted, 5 failed, 89 VIIRS-zero | mechanical (a summary line) | medium | fix: step A5 |
| B7 | `scripts/sdmTMB_HAB_data.R:255-258` | AICc uses `k_value <- length(fit$tmb_obj$par) + length(fit$tmb_obj$env$random)`, counting every spatial random-effect node as a parameter, so `n - k_value - 1` is negative for most months and `aicc` is meaningless. Unused downstream | mechanical | low | fix: step A4 |
| B8 | `scripts/sdmTMB_HAB_data.R:300-305,311-314,325-335` | `.plot_fit_diagnostics()` remaps convergence strings from the VAST-era workflow that the current code never produces, labels an "approach" by `grepl("VAST", ...)`, and clips four metrics with hard-coded `scale_y_continuous(limits = ...)` that drop out-of-range months with a warning. Diagnostic PNGs only (`sdm/plots/`, gitignored) | mechanical | low | fix: step A4 |
| B9 | `scripts/get_HAB_data.R:211` | `download.file(url = ..., destfile = dest, mode = "wb")` with R's 60 s default timeout, no `options(timeout)` and no `try()`; inside the never-called `fn.get_habsos_data()` (E1), so dormant | mechanical | low | fix: step A7 |
| B10 | `run_redtide_maps.R:227`; `scripts/polygon_clipping_rt.R:299` | The combined-stack PDF is rendered after the ASCII files are written, and `pdf()` fails if the previous PDF is open in a viewer (it happened during the issue #3 work). The run then dies with the deliverables already on disk but before the `Hulls:` line and `Run complete.`, so the README's operator check (`:106-107`) reports a failed run. Wrap the plot in `try()` with a logged warning, or render it last and say so | mechanical | low | fix: step A5 |
| B11 | `scripts/_setup.R:129-130,153` | The log name is `run_<date>.log`, so two runs on one day append to one file (today's log holds the baseline under the 30 Sept-style stage lines); `rt_log()` swallows write failures silently (`try(..., silent = TRUE)`) | mechanical | low | fix: step A3 |
| B12 | `scripts/sdmTMB_HAB_data.R:135-136` | `names(mdf_df)[which(names(mdf_df) %in% c("X","Y"))] <- c("lon","lat")`: the columns `X`, `Y` never exist (the filtered frame already has `lon`, `lat` from `:292`), so both lines are no-ops left from the HABSOS-era schema | mechanical | low | fix: step A4 |

### 2.4 Documentation (D)

| ID | Where (file:line) | Problem | Kind | Severity | Status |
|---|---|---|---|---|---|
| D1 | `README.md:59,60,168`; `run_redtide_maps.R:194` | "VIIRS (2012–present)" and "(2012-present)" against tracked tifs for 2012-01 to 2024-12 minus 2022-12; "MODIS nFLH (2003–2025)" against polygons for 2002-07 to 2025-09 minus four months; driver comment "5c) MODIS nFLH clipping (2003-2012)". README `:59` calls the VIIRS product "probability rasters" while the files are `*_month_frequency_*` | mechanical | low | fix: step A6 |
| D2 | `README.md:83,84,86,112` | First run "about 20 minutes" at `:83` and "about 19 minutes" at `:112`; stage times "(~3 min, ~216k records)" and "(~7 min)" with no log in the repository behind them (run logs are gitignored). Doc B §8 takes the measured values from the 6 Oct baseline | mechanical | low | fix: step A6 |
| D3 | `scripts/sdmTMB_HAB_data.R:3,51-52,63-64` | File header says "Three functions" and lists four; roxygen for `fn.fit_monthly_sdmTMB()` describes a "confirmation prompt" that does not exist in the body; `fit_nb` is documented as "If TRUE (default)" while the driver passes `FALSE` (`run_redtide_maps.R:70`) | mechanical | low | fix: step A6 |
| D4 | `scripts/README.md:1` | The whole file is "Create a folder"; nothing says what `scripts/`, `scripts/qa/`, `scripts/old scripts/` and `scripts/experimental/` hold (the last has its own README) | mechanical | low | fix: step A6 |
| D5 | `README.md:160-170,213` | "Inputs" lists only the URL file under `data/`, not the tracked `habsos_20240430.csv` (29.9 MB), its example, or the 2.1 MB xlsx (E2); "Required packages" lists seven packages the live code does not call (P2) | mechanical | low | fix: step A6 |
| D6 | `run_redtide_maps.R:145`; `scripts/sdmTMB_HAB_data.R:21-22`; `README.md:148` | Comment "Drop observations outside the prediction grid box (defensive)" sits above a plain assignment with no filter; `file_excl` is documented as "unused here but kept in signature"; README "Configuration" says `bathy_dir` holds the "depth + excl ASCII templates", implying the exclusion layer is used. It is read, logged and never used | mechanical | low | fix: step A6 |
| D7 | `README.md:59,62-63,104-107` | The cascade text says a VIIRS month is "masked to those cells" where any cell is > 0, but not that a VIIRS month with no positive cell is written as an all-zero map whatever the in-situ samples show (89 of 155 months, M1), nor that months with 0-5 positives are zero maps (M2); the operator check in "Monthly rerun" step 2 covers only the hull flag | mechanical | medium | fix: step A6 |
| D8 | repository root; `README.md` section list | No `CLAUDE.md`, no "For collaborators" or "Known caveats" README section, and `docs/issue3-hull-fix-plan.md` (the only review record) is not linked from the README; the `docs/review/` documents from this audit are not yet linked either | mechanical | low | fix: step A6 |

### 2.5 Methods and statistics (M)

| ID | Where (file:line) | Problem | Kind | Severity | Status |
|---|---|---|---|---|---|
| M1 | `scripts/process_VIIRS.R:114-119`; `scripts/polygon_clipping_rt.R:215-218` | A VIIRS month with no positive cell is written as an all-zero map and takes precedence over the in-situ evidence. Measured on the 30 Sept run (§3): 89 of 155 VIIRS months have zero positive cells; 58 of them had a fitted model (≥ 6 positives); 14 had 100 or more positive samples (2017-01 to 2017-04: 274, 320, 258, 168; 2021-06: 376; 2016-04: 246); 17 had a maximum in-situ count of 100,000 cells/L or more. Whether a satellite "no detection" should override sampled blooms (nearshore and estuarine samples the 0.1° product may not resolve) is the author's call; arithmetic unchanged | scientific | high | author (§8; sub-issue at A9) |
| M2 | `scripts/sdmTMB_HAB_data.R:116-118`; `scripts/polygon_clipping_rt.R:79` | Months with 1 to 5 positive samples (87 of 421 months with any positive since 1985) get a footprint but no model, so their map is all zero; months with ≥ 6 positives are modelled. The threshold "> 5" has no recorded justification and is not in `cfg`. Options: a minimum-positives key with the current default; a fallback (e.g. the footprint filled with the month's mean positive count) for 1-5 positives; or document the zero as intended | scientific | medium | author (§8; sub-issue at A9) |
| M3 | `scripts/polygon_clipping_rt.R:79`; `scripts/sdmTMB_HAB_data.R:115,133` (`cells != 0`, `cells > 0`) | Carry-over from issue #3 (plan §6.4, decision 4): a positive sample is any non-zero count, including FWC's "background" class (up to 1,000 cells/L; 10% of positives are ≤ 667 cells/L). The promised follow-up issue was not opened. Affects which months are modelled (M2), the footprints, and the lognormal fits | scientific | medium | author (§8; sub-issue at A9) |
| M4 | `scripts/sdmTMB_HAB_data.R:260` (`conv <- fit$model$convergence == 0`) | Convergence is the optimiser's return code only. sdmTMB's own `sanity()` rejects fits this accepts: 1996-08 (16 positives) has nlminb code 0 but fails the Hessian, standard-error and sigma checks; 2018-09 (525 positives) passes all. The 30 Sept run captured 2,011 fit warnings (1,852 "NA/NaN function evaluation", 80 non-positive-definite Hessian). Sanity sweep over the 334 cached fits (§3): 326 have nlminb code 0 and are counted as converged, but only 229 pass `sanity()` (80 fail the Hessian check, 79 have NA standard errors, 92 fail the sigma check); the pass rate is 33% for months with ≤ 10 positives, 43% for 11-30, 69% for 31-100 and 97% above 100. A fit that fails `sanity()` still predicts a map | scientific | medium | author (§8; sub-issue at A9) |
| M5 | `scripts/sdmTMB_HAB_data.R:154-159` | Model specification is undocumented and its assumptions unstated: intercept-only lognormal on positives, spatial field on an SPDE mesh with `cutoff = 0.1` (degrees, about 11 km), no covariates (depth is on the grid), no sharing across months or years, no treatment of event-driven sampling. In-sample RRMSE median 2.29 (§3). Doc A §5.3 now states the assumptions; whether they are acceptable is the author's | scientific | medium | author (§8; sub-issue at A9) |
| M6 | `run_redtide_maps.R:44`; `scripts/polygon_clipping_rt.R:195-200` | Months of the current year after the last sample are written as zero maps (2026-10 to 2026-12 on the 30 Sept run), and every month after the last satellite product (2025-10 onward) is a hull month. Ecospace reads a zero as "no red tide" for months that have not happened. Cross-ref R8 | scientific | low | author (§8; sub-issue at A9) |
| M7 | `scripts/process_MODIS.R:243` (`flh <- flh / 10`), `:248` (`threshold <- 0.02`) | The raw ERDDAP nFLH stack is divided by 10 before the 0.02 threshold with no comment on the units or the scale factor; the README quotes the threshold in physical units. Static only (rebuild path not run); unexplained | scientific | low | author (§8; sub-issue at A9) |

### 2.6 Stochasticity (S)

| ID | Where (file:line) | Problem | Kind | Severity | Status |
|---|---|---|---|---|---|
| S1 | `scripts/sdmTMB_HAB_data.R:14` (`set.seed(6)`) | The only seed in the live code, at file scope, so it runs at `source()` time and resets the session's random state for anything the user does afterwards. No random draw remains in the live pipeline (static sweep: no `rng_call` hit outside `scripts/experimental/`; the k-means and jitter went in PR #4). Measured 6 Oct (§3): fits of 1996-08 and 2018-09 are identical with seed 6 twice, with no seed and with seed 123, and identical to the fits cached on 30 Sept (max abs parameter difference 0). The seed is vestigial; removing it changes nothing. Run-to-run variation comes only from the live FWC pull (R2) | mechanical | low | fix: step A4 (decision 3) |

### 2.7 Run time (T)

| ID | Where (file:line) | Problem | Kind | Severity | Status |
|---|---|---|---|---|---|
| T1 | `out/5min/run_20260930.log`; baseline 6 Oct (Doc B §8, §9.1) | Measured warm-cache timings: 30 Sept run 8 min 12 s (steps: 10 s, 22 s, 1 min 22 s, 1 min 31 s, 3 min 6 s, 1 min 41 s). 6 Oct baseline: about 35 min to the point it was stopped in stage 6, on a machine that was out of memory with a sanity sweep and a stray process beside it; not evidence (Doc B §9.1). README "about 9 minutes" is consistent; "about 20 minutes" cold is claimed, not measured (D2) | mechanical | low | fix: step A6 |
| T2 | `scripts/process_VIIRS.R:22-46`; `scripts/sdmTMB_HAB_data.R:343-401`; `scripts/polygon_clipping_rt.R:172-207` | Every run rebuilds the VIIRS stack from 155 tifs, re-predicts all 504 months and re-clips three ways even when no fit changed; stages 4 to 6 are about 6 of the 8 minutes on a warm cache. A prediction cache keyed on the fit folders' modification times and a VIIRS stack cache keyed on the tif list would skip most of it. Only if byte-identical (prove with `snapshot_md5.R`) | mechanical | low | wontfix (decision 6) |
| T3 | `scripts/get_HAB_data.R:63-69` | The full pull builds the record table with `do.call(rbind, lapply(feats, function(f) as.data.frame(...)))`, one data frame per record for about 216,000 records (quadratic in the worst case); the README's "~3 min" for the pull is mostly this, not the network. `data.table::rbindlist()` or a column-wise build would cut it; only matters with `fwc_force_full` | mechanical | low | wontfix (decision 6) |

### 2.8 Efficiency and artifacts (E)

| ID | Where (file:line) | Problem | Kind | Severity | Status |
|---|---|---|---|---|---|
| E1 | `scripts/get_HAB_data.R:185`; `scripts/process_VIIRS.R:55`; `scripts/process_MODIS.R:279`; `scripts/sdmTMB_HAB_data.R:30-39` | Never called from the driver or any sourced file: `fn.get_habsos_data()`, `fn.get_viirs_obs()`, `fn.plot_modis()` (static sweep, confirmed by grep). `compute_area_km2()` is called but its product `input_grid$Area_km2` is read nowhere. (`%||%` is used at `:48`; the sweep misses infix calls.) `fn.pull_MODIS_flh_erddap()` and `fn.make_nflh_polys()` run only under `update_modis`/`rebuild_nflh` | mechanical | low | fix: step A7 |
| E2 | `data/habsos_20240430.csv` (29.9 MB), `data/habsos_20240430_example.csv` (148 KB), `data/1985-2025.09.09 WFS Kb and environmental data.xlsx` (2.1 MB); `template rasters/` (4, 6, 10 min variants, `WFS_4min_masked.asc`, `depth_masked.asc`); `RT.jpg`; `VIIRS/*.png` (156) | Tracked files no live code reads (grep over the driver, `scripts/*.R`, the QA script and the README finds no reader; the HABSOS path exists only in dead code). `data/` is 30.7 MB of the 60 MB tracked. Candidates for `archive/` with a README row, or `hoard/` | mechanical | low | fix: step A7 |
| E3 | `scripts/old scripts/` (10 files, no README; `polygon_clipping_rt.R:15-31` branches paths on the login name and falls back to `choose.dir()`); `scripts/experimental/` (6 files, README present; `accuracy_evaluation.R:14-20` machine paths); `archive/` (4 files, README table) | Three generations of superseded code in two places. Inventory only (decision 1); the move of `old scripts/` under `archive/` with a README row each is the obvious housekeeping step, and `scripts/README.md` (D4) should point at all three | mechanical | low | fix: step A7 |
| E4 | repository root `.RData` (6.5 MB, 30 Sept); `out/5min/clipping_source_before.csv`, `md5_before.csv`, `md5_compare.csv`, `run_20260924.log`, `run_20260929.log`; `out/5min/sdm/*20260909*` | Local, gitignored leftovers from the issue #3 work and from RStudio (P3). Nothing reads them. `hoard/` with a README is where the conventions put them | mechanical | low | fix: step A7 |

## 3. Evidence notes

Facts established on 6 Oct 2026 on the reviewer's machine (R 4.5.1; package table in Doc B §10.3). Each line names the register row it supports.

- **R1**: `ls VIIRS/redtide_maps_0.1degree` gives 156 PNG and 155 TIF; `comm` on the stems names `2022_12_month_frequency_noaa_resize` as the one without a TIF. `names(flh.polys)` has 275 entries, 200207 to 202509; `setdiff()` against the monthly sequence gives 200604, 201606, 202411, 202412. The 30 Sept `clipping_source.csv` has `X200604 = pred`, `X202212 = modis`; totals 155 viirs, 123 modis, 226 pred.
- **R1, M1 (VIIRS georeferencing)**: every tif has extent 0-65, 0-55, resolution 1 and no CRS (`raster()` reports `unknown extent`); the forced extent at `process_VIIRS.R:36` is therefore required, not an override. Layers have 1,002-1,012 NA cells (land) and values 0 to 0.99.
- **M1**: per-layer `sum(values > 0)` is 0 for 89 of 155 tifs. Joining with `RT_fit_matrix.RData`: 58 of those months have a fit (`convergence` TRUE or FALSE). Positives per month from the filtered data: median 13, 90th percentile 169, max 376 (2021-06). Months with ≥ 100 positives: 201303 (173), 201304 (133), 201310 (113), 201603 (133), 201604 (246), 201701 (274), 201702 (320), 201703 (258), 201704 (168), 201803 (236), 201804 (190), 201805 (116), 202106 (376), 202305 (171). Months whose maximum in-situ count is ≥ 1e5 cells/L: 17.
- **M2, M3**: filtered data 183,133 rows (1980-2026), 0 NA counts, 0 negative, 143,225 zeros, 39,908 positives; positive-count quantiles 1 / 667 (10%) / 20,000 (50%) / 685,810 (90%) / 8.6e6 (99%) / 3.88e8 (max). Months since 1985 with ≥ 1 positive: 421; with > 5: 334; with 1-5: 87.
- **M4**: `RT_fit_matrix.RData` (30 Sept): 334 months attempted, 326 `TRUE`, 3 `FALSE`, 5 "no model"; RRMSE quantiles 0 / 1.31 / 2.29 / 3.50 / 4.89 (90%) / 10.08. `sanity()` on a refit of 1996-08: `hessian_ok`, `se_magnitude_ok`, `se_na_ok`, `sigmas_ok`, `all_ok` FALSE with nlminb code 0; 2018-09: all TRUE. `fit_warnings.csv` (25 Sept): 2,011 rows, all `log`; 1,852 "NA/NaN function evaluation", 80 "non-positive-definite Hessian", 79 "NaNs produced". Sanity sweep over the 334 cached fits (`RedTideMaps-audit/20261006/fit_sanity.csv`, 6 Oct): 5 no model; 326 nlminb code 0; 229 `all_ok`; failures: `hessian_ok` 80, `se_na_ok` 79, `sigmas_ok` 92, `range_ok` 0. Positives per fitted month: 6 (min), 9 (10%), 16 (25%), 65 (median), 165 (75%), 614 (max). `all_ok` rate by positives: ≤ 10: 0.33; 11-30: 0.43; 31-100: 0.69; > 100: 0.97. Estimated spatial range among `all_ok` fits: 0.01 / 0.33 / 0.50 / 0.70 / 4.28 degrees (min / quartiles / max). The five "no model" months: 1990-03, 1999-07, 2001-02, 2008-05, 2012-07.
- **S1, B5**: `sdmTMB()` on the month's positives with `make_mesh(cutoff = 0.1)`, `lognormal()`, `spatial = "on"`: 1996-08 (n = 16) and 2018-09 (n = 525), four fits each (seed 6, seed 6, none, seed 123), `identical(fa$model$par, ...)` TRUE for all; `identical()` with the cached `fit_sdmTMBlog$model$par` TRUE, max abs diff 0. About 0.1-0.2 s per fit.
- **B3**: `pred_array` dims 5148 × 4 × 12 × 42; `apply(pred_array[, , "Jan", "1985"], 2, range)` is 0 for `lon`, `lat`, `fit_sdmTMBlog`, `fit_sdmTMBnb`; for 2018-09 `lon` spans -87.46 to -81.04 and `fit_sdmTMBlog` 16,228 to 7,746,619.
- **B4**: `names(formals(sdmTMB:::predict.sdmTMB))` listed in the row; no `t_i`.
- **R6**: `sed -n 6p` over all 504 files in each resolution: `NODATA_value -3.4e+38` in every file; first token identical in every file; `git show 6cfdf00:out/5min/ecospace_ascii/sdmTMB_log__201809.asc` has the same header and token. Reading 2018-09 back with `raster()` gives 1,310 NA cells, the same cells as the depth template. Writing the template-derived raster with `format = "ascii"` and `NAflag = -9999` produces `NODATA_value -9999` and `-9999.000000000000000` as the first token (so the expanded first token is raster's writer, not the no-data choice). Values are float32 (`96024.078125`, `106015.0546875`); 592 of the 2018-09 tokens carry decimals.
- **P2**: grep over the driver and six stage files for `ymd(|month(|year(|as_date(|floor_date(`, `pam(|agnes(|daisy(|clara(|diana(|silhouette(`, `viridis(|scale_fill_viridis|magma(`, `percent(|comma(|rescale(|alpha(|hue_pal|label_`, `plot_grid(|theme_cowplot|ggdraw(`, `facet_nested|force_panelsizes|facet_wrap2`: no call (the only `month(` hits are inside `sprintf()` strings). `read_html|html_nodes|html_attr` only at `get_HAB_data.R:187-199` inside `fn.get_habsos_data()`.
- **Hull footprints (no finding)**: `hull_diagnostics.csv` (30 Sept): 421 months with positives, smallest `max_area_km2` 314 (one 10 km disc) against a 5-min cell of about 76 km² at 27.75°N, so a footprint always covers at least one cell centre; 71 months flagged overall, 10 among the 226 hull-served months (run log).
- **Static sweep** (`RedTideMaps-audit/sweep/`): 16 files, 0 parse failures; pattern hits in live files: 1 `download` (B9), 1 `set_seed` (S1), 1 `<<-` (`sdmTMB_HAB_data.R:104`, inside a warning handler, fine), all `writeRaster()` calls carry `overwrite = TRUE`, no `setwd()`, no `windows()`, no machine path (the only hit is the gitignored `config.local.R:5`).
- **Tracked size**: `git ls-files | du -b`: data 30.7 MB, out 23.7 MB, MODIS 2.9 MB, VIIRS 2.2 MB, everything else under 1 MB; pack 23.9 MB.
- **Baseline run** (6 Oct, `RedTideMaps-audit/20261006/run/`): stopped in stage 6 by the harness (low memory); `cmp` of `clipping_source.csv`, `hull_diagnostics.csv` and `RT_fit_matrix.RData` against the 30 Sept copies: identical; `git status`: three plot files modified, no ASCII file touched; `OM_month/` still 334 folders; cache now `19800102-20260922`. Doc B §9.1 holds the table.

## 4. Recommended changes (fix design)

Written for a later `audit` or `fix` session; nothing here was applied in review-only mode. Statuses in §2 decide which parts are used.

### 4.1 Configuration

New keys in `cfg`, each with a default that reproduces today's outputs, each overridable in `config.local.R` and documented in `config.local.example.R`:

| Key | Default | Purpose | Closes |
|---|---|---|---|
| `fwc_offline` | `FALSE` | `TRUE` skips the API and runs from the newest cached CSV; the log says so | R2 |
| `min_positives` | `6L` | Positives a month needs before it is modelled (today's literal `> 5`) | M2 (exposes the choice; the default keeps it) |
| `mesh_cutoff` | `0.1` | sdmTMB mesh cutoff in degrees (today's literal) | M5 (exposes the choice) |
| `viirs_empty_rule` | `"zero"` | What a VIIRS month with no positive cell gets: `"zero"` (today) or `"hull"` (fall back to the hull footprint) | M1 (only after the author decides; default keeps today's behaviour) |
| `ascii_nodata` | `-3.4e+38` | `NAflag` passed to the ASCII writer; `-9999` matches the templates | R6 (decision needed before changing the default) |

No author-layout mapping is needed: the tracked code holds no machine path.

### 4.2 Setup checks

- `rt_input_manifest()` and `rt_check_inputs()` in `scripts/_setup.R` (base R): one row per input (depth template, exclusion template, URL file, VIIRS folder with a count of tifs and the missing months in the 2012-2024 sequence, MODIS polygon file with a check that exactly one matches, FWC cache or "network required"); printed as an OK/MISSING table after the package check and before stage 1; stop on a missing required input; the MODIS row turns the silent skip into a visible decision (P1, R1, R5).
- One line in the run log with `R.version.string` and the versions of `sdmTMB`, `TMB`, `sf`, `raster`, `terra` (R9).
- Declare `sp` or namespace its three calls; drop the six unused packages from the check and the README once E1 settles `rvest` (P2, P4).
- `RedTideMaps.Rproj`: `RestoreWorkspace: No`, `SaveWorkspace: No`, `AlwaysSaveHistory: No` (P3).

### 4.3 Code changes, one line per finding (all keep existing signatures; new arguments get defaults)

- **R1**: after stage 6, log one cascade summary: counts by source and the months whose source differs from what their date implies (`202212 -> modis (no VIIRS tif)`, `200604 -> hull (no MODIS polygon)`); README states the two gaps.
- **R2**: `fwc_offline`; keep the previous merged CSV under `cell_counts/previous/` instead of `unlink()`.
- **R4**: add `fit_warnings.csv` to the stale-file list at `sdmTMB_HAB_data.R:82`, or write an empty file when there are no warnings.
- **R5**: delete `*_filtered.Rdata` and `*_hullpolys.Rdata` whose cache stem is not the current one; stop if more than one `FLH polys` file matches.
- **R6**: `NAflag = cfg$ascii_nodata` in `make_redtide_ascii()`; the default keeps the bytes; changing it is an `outputs` commit under a decision.
- **R8**: README: state that `enyr` follows the calendar and what the trailing zero months mean.
- **B1**: in `fn.filter_hab_data()`, rename columns by name (`names(df)[names(df) == "count_"] <- "cells"`) instead of by position at `:292`; a `stopifnot(all(c("year","month","cells","lon","lat") %in% names(filtered_points_df)))` guard.
- **B2**: `if (isTRUE(mean(values(r1), na.rm = TRUE) == 0) || ...)` at `process_VIIRS.R:114` and `:65`, so an all-NA layer counts as empty.
- **B3**: write zeros to the model columns and the grid coordinates to `lon`, `lat` for no-model months (`:275-277`); outputs identical (both routes give a zero map; prove with `snapshot_md5.R`).
- **B4**: drop `t_i =` from the `predict()` call.
- **B5**: drop the retry loop; one attempt, same result.
- **B6**: write `sdm/month_status.csv` (yrmo, n_pos, fit status, sanity result, footprint source, map is zero and why) and log "Months: n modelled, n failed, n below `min_positives`, n VIIRS-empty, n no samples".
- **B7**: compute k from `length(fit$model$par)` (fixed effects plus variance parameters) or drop AICc.
- **B8**: remove the VAST remapping and the hard-coded `limits`, or move `.plot_fit_diagnostics()` to `scripts/experimental/`.
- **B9**: if `fn.get_habsos_data()` stays, wrap `download.file()` in `try()` with `options(timeout = 600)` restored on exit; otherwise it moves with E1.
- **B10**: wrap `fn.plot_redtide_stack()` and `fn.plot_sdmTMB()` in `try()` with `rt_log()` of the failure; the `Hulls:` line and `Run complete.` then always follow the ASCII write.
- **B11**: log file name with a time stamp (`run_<yyyymmdd-HHMMSS>.log`) or a `==== new run ====` separator; log a warning when `rt_log()` cannot write.
- **B12**: delete lines `135-136`.
- **D1-D8**: README edits listed in §4.3 of Doc B's "sync" offer (Phase 9): coverage dates and gaps, one measured run time, inputs list, package list, the zero-map rules, "For collaborators" and "Known caveats" sections linking `docs/review/`; `scripts/README.md` describing the four folders; roxygen fixes at `sdmTMB_HAB_data.R:3,51-52,63-64`; delete the dead comment at `run_redtide_maps.R:145`; a `CLAUDE.md` from the skill's template.
- **S1**: delete `set.seed(6)`; evidence: identical fits with and without it (§3).
- **T2, T3**: optional, separate commits, each proved byte-identical with `snapshot_md5.R compare`.
- **M1-M7**: no code change; §8 and sub-issues.

### 4.4 Housekeeping (nothing deleted)

- `git mv "scripts/old scripts" archive/old-scripts` with a README row per file (E3); `scripts/README.md` points at `qa/`, `experimental/` and `../archive/`.
- `git mv` the HABSOS CSVs, the xlsx, the 4/6/10-min templates and the two masked templates to `archive/data/` with a README table (E2); or `hoard/` if nobody will cite them.
- `fn.get_habsos_data()`, `fn.get_viirs_obs()`, `fn.plot_modis()` to `scripts/experimental/` (E1), unless the author wants them kept as documented helpers.
- `hoard/` (gitignored, README) for `.RData`, the issue #3 scratch CSVs and old logs (E4); add `hoard/` to `.gitignore`.
- `git ls-files -ci --exclude-standard` is already empty; no `git rm --cached` needed.

### 4.5 Alternatives considered

- Regenerating `out/15min/` now: out of scope (decision 1); it needs its own decision because the 15-min maps would change for every hull month.
- Replacing `raster`/`sp` with `terra`/`sf` throughout: large behavioural risk (rasterisation rules differ at cell edges), no user benefit now; not recommended.
- A delta (hurdle) model in sdmTMB that estimates presence instead of masking with a footprint: a methods change for the author (M5), not a fix.
- Pinning package versions with `renv`: more than this repository needs; a version line in the log (R9) is enough for now.

### 4.6 Constraints

No new package dependency. Every function keeps its current signature; new arguments default to current behaviour. The sdmTMB arithmetic, the cascade preference and the hull rule are not touched except through new `cfg` keys at their current defaults. Windows 11, R 4.5.1; base R over shell pipes; forward slashes. Evidence for every mechanical step: `snapshot_md5.R compare` against the baseline copy in `RedTideMaps-audit/20261006/committed/` shows every ASCII file identical (or, for a run with new FWC data, identical for every month before the new records' month).

## 5. Implementation plan

Review-only mode: no code changes are made. The plan written in Phase 6 is the plan a later `audit` or `fix` session would execute.

- [x] 1. Phase 1 interview; mode, reviewer and scope recorded (§0-1).
- [x] 2. Phase 2 orientation drafts: Doc A §1-5, Doc B §1-2, this document.
- [x] 3. Pause 2 confirmed by the reviewer (6 Oct 2026).
- [x] 4. Phase 4 smoke checks (anchor, parse, packages, inputs); baseline run launched with logging and fingerprints.
- [ ] 5. Baseline results into Doc B §8-9.1; R10 and T1 filled; sanity counts into M4.
- [x] 6. Phase 5 registers reviewed; Doc A §5-7 and Doc B §3-7 completed.
- [x] 7. Pause 5: one status per finding row (6 Oct 2026; batch accepted).
- [x] 8. Phase 6 fix design (§4), plan for a later session (§5 continued), decisions (§7), needs-examination (§8).
- [ ] 9. Phase 8 (static part): convention checks recorded in Doc B §9.3; Doc B §0 and Doc A §6-7 finalised.

Plan for a later session in `audit` mode (one issue, one branch `N-review-fixes`, one draft PR; commit types in brackets; pause before each `outputs` commit):

- [ ] A1. Open the issue from this log; branch; move `docs/review/draft-repo-audit-log.md` to `issueN-review-fixes-log.md`; commit the three documents. (docs)
- [ ] A2. Fresh baseline on that day's data with `run_logged.R` and `snapshot_md5.R`; record in Doc B §9.1. (record)
- [ ] A3. Setup and portability: input manifest and check, version line in the log, `sp` declared, package list trimmed, `.Rproj` settings, cascade summary line. Outputs byte-identical. (code; P1, P2, P3, P4, R1, R9, B11)
- [ ] A4. Fragility, identical outputs: B1, B2, B3, B4, B5, B7, B8, B12, R4, R5, S1. Prove with `snapshot_md5.R compare`. (code)
- [ ] A5. Operator visibility: `month_status.csv` and the "Months:" log line; `fwc_offline` and the cache history folder; plots in `try()`. (code; B6, B10, R2)
- [ ] A6. README, `scripts/README.md`, roxygen, `CLAUDE.md`, config example. (docs; D1-D8, R8)
- [ ] A7. Housekeeping moves to `archive/` and `hoard/`, every file listed in the commit. (housekeeping; E1-E4)
- [ ] A8. Decision-gated: `ascii_nodata = -9999` and regenerate the 5-min deliverables with the before/after table (pause 8). (outputs; R6, decision 2)
- [ ] A9. Sub-issues for M1-M7 and R3 from §8; `[Decision]` issues in Ops for M1 and M3 (wfs-fem profile). (record)
- [ ] A10. Phase 8 verification: fresh clone without network fails at the manifest; fresh clone with network completes; interactive run identical; convention checks; tick §9. (record)

## 6. Change log

No commits in review-only mode.

## 7. Decisions log

1. **6 Oct 2026 (Holden Harris):** Review-only mode; no GitHub writes, no commits; reviewer is author and reviewer; `old scripts/`, `experimental/` and the 15-min outputs are out of scope beyond inventory. (scope)

Accepted at Pause 5 (6 Oct 2026, Holden Harris; the reviewer answered "please continue" to the proposed batch):

2. **6 Oct 2026 (Holden Harris):** Write the ASCII no-data value as `-9999` to match the templates, regenerating the 5-min deliverables once with a before/after table showing no value changed. (R6; behavioural in bytes only)
3. **6 Oct 2026 (Holden Harris):** Remove `set.seed(6)`; the same-seed and no-seed fits are identical, so this is mechanical. (S1)
4. **6 Oct 2026 (Holden Harris):** Keep today's VIIRS, positive-threshold and convergence rules unchanged in any fix session until the author answers M1-M4; expose `min_positives`, `mesh_cutoff` and `viirs_empty_rule` as keys at their current defaults so the sensitivity runs need no code edit. (M1, M2, M4, M5)
5. **6 Oct 2026 (Holden Harris):** Leave `out/15min/` as committed and say in the README that it predates the hull fix, until a decision to regenerate it. (R7)

## 8. Needs examination (for the original author)

Scientific items left unchanged. In review-only mode no sub-issue is opened; each entry is written so it can be pasted into one.

- **M1 VIIRS non-detection overrides sampled blooms.** `scripts/process_VIIRS.R:114-119` writes an all-zero map for any VIIRS month with no positive cell, and the cascade prefers VIIRS. Evidence: 89 of 155 VIIRS months are empty; 58 of them had a fitted model; 14 had ≥ 100 positive samples; 17 had a sample ≥ 100,000 cells/L (§3). Options: (a) keep, and document that the satellite is the arbiter in 2012-2024; (b) fall back to the hull footprint when the VIIRS layer is empty and the month has at least `min_positives` positives (`viirs_empty_rule = "hull"`); (c) union the VIIRS and hull footprints in every VIIRS month; (d) use VIIRS only to extend, never to shrink, a hull footprint. Not changed because every 2012-2024 map in the committed deliverables depends on it.
- **M2 Months with 1-5 positives are zero maps.** `sdmTMB_HAB_data.R:116-118`. 87 months since 1985 (33 of them hull-served). Options: keep and document; lower the threshold and accept worse fits (M4 shows fits with ≤ 10 positives pass `sanity()` a third of the time); or fill the footprint of a sub-threshold month with a constant (the month's mean positive count, or the previous month's surface). Not changed: the threshold decides which months exist in the deliverable.
- **M3 What counts as a positive sample.** Carried over from issue #3 (plan §6.4): `cells != 0` includes FWC's background class (≤ 1,000 cells/L; 10% of positives are ≤ 667). Options: keep; raise the hull-membership threshold only; raise it for the fits too. Affects M2 counts, every hull footprint and the lognormal means. The follow-up issue promised in the plan has not been opened.
- **M4 Convergence criterion.** `sdmTMB_HAB_data.R:260` accepts nlminb code 0; `sanity()` rejects 100 of the 329 fits (§3), mostly small months. Options: keep; record `sanity()` in `RT_fit_matrix` and the new `month_status.csv` without acting on it; treat a failing month like a failed fit (zero map, 100 more zero months); or refit failing months with a fixed or penalised range (`sdmTMBcontrol`/priors). Not changed: 100 maps would change.
- **M5 Model specification.** Intercept-only lognormal on positives, `cutoff = 0.1`, no covariates, no sharing between months (Doc A §5.3 states the implied assumptions). Options for a sensitivity study, not for this pipeline: depth as a covariate; a shared spatial field with monthly deviations (`spatiotemporal = "iid"` over months within a year); a delta-lognormal model on all samples so presence is estimated rather than masked. Not changed.
- **M6 Zero maps for months not yet observed.** `run_redtide_maps.R:44`. Options: keep (Ecospace needs complete years); write the trailing months as NA or omit them and let Ecospace repeat the last month; document. Not changed.
- **M7 nFLH scaling.** `process_MODIS.R:243` divides the ERDDAP stack by 10 before the 0.02 threshold with no note of the units. Question for whoever built `FLH polys 200207-20250926.Rdata`: is the ERDDAP variable scaled by 10 (then the comment should say so), or is the threshold effectively 0.2 in the served units? Static only; the rebuild path was not run.
- **R3 Record corrections are never applied by an incremental pull.** `get_HAB_data.R:146-155` keeps the cached row on a duplicate key. Options: prefer the newer row (`fromLast = TRUE`), which changes any month FWC has corrected; or keep, with `fwc_force_full` as the documented remedy and a periodic full pull in the operator's checklist.

## 9. Acceptance criteria

For a later audit session that implements the Phase 6 plan:

- [ ] A fresh clone with network completes `Rscript run_redtide_maps.R` from the command line (Doc B §9.3).
- [ ] A run from the wrong folder stops with the anchor message; a missing required input stops before any slow work with a table naming the file and how to get it (Doc B §9.3).
- [ ] `git grep -nE "\b[A-Za-z]:/|/Users/|/home/|OneDrive|AppData" -- '*.R'` matches only commented examples; `git grep -n "windows(" -- '*.R'` matches nothing.
- [ ] A fresh run regenerates the committed 5-min deliverables identically, or every difference has a cause (Doc B §9.1 table).
- [ ] Two runs on the same inputs give identical outputs (Doc B §6).
- [ ] `git ls-files -ci --exclude-standard` is empty.
- [ ] Doc A, Doc B and the README describe the stages, inputs, outputs and tested environment.
- [ ] The reviewer signs off.

## 10. GitHub record

None in review-only mode.

## 11. Closing summary

Review-only audit closed on 6 Oct 2026. No code, output or GitHub state was changed; the three documents in `docs/review/` are untracked on the reviewer's clone. Pre-ready check: no row `open`; every row has a status; the placeholders that remain are the pending run-matrix cells in Doc B §9.3 that only an `audit` session can fill.

| ID | Outcome |
|---|---|
| P1, P2, P3, P4, R1, R9, B11 | fix at step A3 (setup and portability) |
| R4, R5, B1, B2, B3, B4, B5, B7, B8, B12 | fix at step A4 (identical outputs) |
| S1 | fix at step A4 under decision 3 |
| R2, B6, B10 | fix at step A5 (operator visibility) |
| R8, R10, D1-D8, T1 | fix at step A6 (documentation) |
| B9, E1, E2, E3, E4 | fix at step A7 (housekeeping moves; nothing deleted) |
| R6 | fix at step A8 under decision 2 (`-9999` no-data; outputs commit with before/after table) |
| R7 | wontfix (decision 5): 15-min outputs stay as committed, README to say they predate the hull fix |
| T2, T3 | wontfix (decision 6): caches deferred |
| M1, M2, M3, M4, M5, M6, M7, R3 | author; §8 entries ready to paste into sub-issues at step A9 |

Carried to the next audit: steps A1-A10; the pending run-matrix cells (author's interactive run, fresh clone with and without network); the Ops decision-log line for the 75 km hull default promised in issue #3; the follow-up issue on the positive-sample definition (M3). README and `CLAUDE.md` sync from Doc A and Doc B: not done in this mode (listed under D8 and step A6).

The one measured surprise of this audit, for the author's attention first: 58 modelled months in 2012-2024 are written as zero maps because the VIIRS layer shows no detection (M1), including documented blooms with hundreds of positive samples.
