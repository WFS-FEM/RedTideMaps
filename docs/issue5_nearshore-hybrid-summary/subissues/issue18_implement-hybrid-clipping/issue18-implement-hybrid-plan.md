# Issue #18: implement the hybrid clipping approach, regenerate the deliverables, close #5

Plan for [WFS-FEM/RedTideMaps#18](https://github.com/WFS-FEM/RedTideMaps/issues/18) (Holden, 23 Oct 2026): put the decided nearshore set into the pipeline as rule `"mask5adj"`, make it the default for both sensors, regenerate the Ecospace deliverables, document the method and the differences in the #5 summary, and close #5. Decisions taken by Holden today (23 Oct 2026) during planning are in section 1.

## 1. Context

**What #18 asks** (its body): run the hybrid pipeline (satellite clip offshore, buffered hulls in the nearshore set); write the final results for Ecospace in `./out`; document the methods and the differences from the non-hybrid approach by updating `docs/issue5_nearshore-hybrid-summary/`. It should close #5.

**What is already decided and built** (#8, #11, #10, #15; all merged):

- The rule: in every satellite month (VIIRS or MODIS), outside the nearshore set the satellite-clipped map stands, zeros included; inside it a cell takes `max(satellite-clipped, hull-clipped)`. Hull months untouched. Implemented as `fn.clip_2_hybrid()` in `scripts/process_hybrid.R`, unchanged here.
- The set (D9, 22 Oct): the union of `mask5` (VIIRS static no-data mask, or center within 5 km of the Natural Earth coastline) and the land-adjacent cells (edge or corner contact with a NODATA cell of the depth template), Gulf domain only, Atlantic box always excluded. 189 cells, 14,205 km2 at 5 arcmin. Written out in `docs/issue5_nearshore-hybrid-summary/subissues/issue15_adjacent-land-hybrid/nearshore-set-method.md`; the cells are `tables/nearshore_set_issue15.csv`; the per-month prototype is the `union_hull` columns of `tables/examine_months_issue15.csv` (210 of the 278 satellite months change: 121 VIIRS + 89 MODIS).
- The pipeline today: `fn.nearshore_mask(rule = "mask5")` only (`scripts/process_hybrid.R:48-99`); `cfg$viirs_nearshore` / `cfg$modis_nearshore` validated at `run_redtide_maps.R:103-115` against `"none" | "mask5"`, both default `"none"`; the tracked 5-min deliverables are still the 6 Oct 2026 maps. The specification for the new rule is section 3 of part 2 of `docs/issue5_nearshore-hybrid-summary/subissues/issue15_adjacent-land-hybrid/issue15-adjacent-land-plan.md`; the adjacency code to copy is the `adj_set()` helper of `docs/issue5_nearshore-hybrid-summary/subissues/issue15_adjacent-land-hybrid/check_adjacent_hybrid_issue15.R:293-296`.

**State found today (read-only):**

- Local repo is on the merged branch `5-summary-issue15-update`; local `main` (cb1250d) is behind `origin/main` (6e4b581, the PR #17 merge). Stale merged branches: local `5-summary-issue15-update`, `15-test-adjacent-land-cells-hybrid`; remote `5-nearshore-hybrid-summary`, `15-test-adjacent-land-cells-hybrid`, `5-summary-issue15-update`. Working tree clean, no stash.
- Issue #5 is closed (23 Oct 13:14:59, two seconds after PR #17 merged; the PR said it does not close #5, so the Development link did it).
- On disk: `out/5min/` holds run 0 of #10 (both `"none"`, 22 Oct, 7.7 min); `clipped/` still has the run-B hybrid stacks and `nearshore_mask_mask5.grd`; hoards intact (`docs/issue5_nearshore-hybrid-summary/subissues/issue11_.../hoard/{before,after}`, `docs/issue5_nearshore-hybrid-summary/subissues/issue10_.../hoard/{before,after}`). FWC cache `cell_counts/FWC HAB data 19800102-20260922.{csv,Rdata}`. `config.local.R`: `ecospace_root` set, `export_ecospace FALSE`, `fwc_refresh FALSE`, both nearshore keys `"none"`.
- `out/15min/` has only the tracked `ecospace_ascii/` (504 files, last committed 22 May 2026, before the #3 hull fix) and `plots/`; no fits cached, so a 15-min run is a cold run (about 20 min). Templates `depth 15min 22x26.asc` / `excl layer 15min 22x26.asc` exist.
- Ecospace ST drivers: `<root>/5min/red tide/sdmTMB/` (504 files dated 4 Jun 2026, older than the repo's 30 Sep deliverables) and `<root>/15min/red tide/sdmTMB/` both exist, so the export check at the top of the driver passes.
- A refresh run re-queries only the `Recent_` endpoint for `SAMPLE_DATE >= 22 Sep 2026` (`scripts/get_HAB_data.R:91-133`); months already fit are not refit (`incremental_fit`), so new samples change only the hulls (and a fit for a new month), i.e. the hull-served tail months 2026-09 onward.

**Decisions by Holden, 23 Oct 2026 (planning):**

- D10: reopen #5 now; #18's PR closes both, with the closing record posted on #5.
- D11: regenerate twice. First with the FWC samples frozen at 22 Sep 2026 (`fwc_refresh = FALSE`, fewer moving pieces; the committed maps equal the verification run byte for byte and the #15 prototype month by month). Then, after everything is done and checked, a rerun that pulls the new samples. Extra time for the refresh step: one more run per resolution (about 9 min at 5 min, about 10 min at 15 min with the fits cached by then), the pull itself under a minute, one second per new month fitted; about 20 min of runs plus two checks and one more deliverables commit.
- D12: export to the Ecospace ST drivers folder in the final runs (`export_ecospace = TRUE`).
- D13: regenerate the 15-min deliverables too (one cold run, then the refresh run).

## 2. Step 0: clean up before branching

1. `git checkout main && git fetch --prune && git merge --ff-only origin/main` (local main to 6e4b581).
2. Delete the local merged branches: `git branch -d 5-summary-issue15-update 15-test-adjacent-land-cells-hybrid`.
3. Remote merged branches `5-nearshore-hybrid-summary`, `15-test-adjacent-land-cells-hybrid`, `5-summary-issue15-update`: Holden deletes them on GitHub (their practice), or says the word and I run `git push origin --delete <branch>`; then `git fetch --prune`.
4. Reopen #5 (`gh issue reopen 5` with a one-line comment: closed by the PR #17 merge by mistake, #18 closes it). If the classifier denies it, hand Holden the command with `!`.
5. Nothing on disk needs removing; the hoards stay (the `record` stage reads the 6 Oct and run-B copies).

Why: a branch for #18 must start from the merged state; stale branches invite a wrong base; the issue list should show what is open.

## 3. GitHub workflow

- Branch `18-implement-hybrid-clipping` from `main`. Folder `docs/issue5_nearshore-hybrid-summary/subissues/issue18_implement-hybrid-clipping/` with this plan (`issue18-implement-hybrid-plan.md`), a README skeleton, `.gitignore` (`hoard/`, `issue18-*-comment.md`), as the other issue folders.
- Draft PR "Implement the hybrid clipping approach - closes #18" against `main` after the first commit, body with the step list and the checkpoints; `Closes #18` and `Closes #5` in the body (both close on merge). Holden merges with a merge commit, as before. Mark the PR ready only at the end (a draft hides the merge button).
- Commits by type, as the repo does: `docs:`, `feat:`, `config:`, `test:`, `qa:`, `data:` (the deliverables).
- Checkpoints, each a comment on #18 drafted in `comments/issue18-<n>-comment.md` (gitignored), `gh issue comment` tried once, the `!` command handed over on a denial:
  1. after the verification runs (the `rule` and `none` tables),
  2. after the frozen regeneration at 5 and 15 min, before the deliverables commit (the MD5 tables, the record numbers, the headline-months figure),
  3. after the refresh rerun (what the new samples changed), then the docs and the #5 closing record.
- Explain the why of each GitHub step briefly as it happens (Holden's request).

## 4. Step 1: the rule in the pipeline (`feat:`, `config:`), defaults unchanged

**`scripts/process_hybrid.R`, `fn.nearshore_mask()`:** `rule <- match.arg(rule, c("mask5", "mask5adj"))`. A third part, computed only for `"mask5adj"`, copied from the #15 `adj_set()` helper:

```r
a <- raster::adjacent(depth, cells = which(!land), directions = 8, pairs = TRUE, include = FALSE)
adjacent <- rep(FALSE, n5); adjacent[unique(a[land[a[, 2]], 1])] <- TRUE
```

(the water cell of every pair whose neighbor is land; grid borders are not land). `set <- domain & (in_mask | near_coast | adjacent)`; the message and the returned list gain `n_adjacent_cells` (0 or NA for `"mask5"`); the file stays `nearshore_mask_<rule>.grd`; roxygen: the three criteria, the counts at 5 arcmin (84 / 132 / 177, union 189, 14,205 km2), pointer to `nearshore-set-method.md`. The `"mask5"` path is untouched by construction. `fn.clip_2_hybrid()` unchanged.

**`run_redtide_maps.R`:** validation at L103-115 accepts `"mask5adj"` (`c("none", "mask5", "mask5adj")`, message updated); the step-5d log line (L266-269) adds `, %d adjacent to land` when the rule is `"mask5adj"` (the `"mask5"` line stays as it is, so the #11 and #10 checks still read it); header comment L8-12 and the cfg comments L73-82 name the three values. **`config.local.example.R`:** the new value with one sentence. **README:** the two cascade bullets, the pipeline-table row, the config-table rows, the outputs tree (`nearshore_mask_<rule>.grd`).

## 5. Step 2: verification at 5 min (`test:`), tracked deliverables untouched

Script `docs/issue5_nearshore-hybrid-summary/subissues/issue18_implement-hybrid-clipping/check_final_hybrid_issue18.R`, stages via `RT_QA_STAGE`, resolution via `RT_QA_RES` (default 5), helpers copied from `check_modis_hybrid_issue10.R` (the convention: the check scripts are not sourced). Deterministic, no RNG, byte-identical outputs on rerun; headline numbers frozen in an `expected` list after the first run.

**Run A** (`config.local.R`: both keys `"mask5adj"`, `fwc_refresh FALSE`, export FALSE; about 8 min, alone on the machine), then **stage `rule`**:

- MD5 of the 504 ASCII files against `docs/issue5_nearshore-hybrid-summary/subissues/issue11_nearshore-hybrid-pipeline/tables/md5_baseline_issue11.csv` (6 Oct): exactly 210 changed, all `hybrid_changed` months (121 `hybrid`, 89 `hybrid_modis`); use counts 155 / 123 / 226; run-log lines (`Nearshore rule mask5adj: 189 cells, 14,205 km2 (84 ..., 132 ..., 177 adjacent to land)`, `Hybrid: 121 of 155`, `Hybrid (MODIS): 89 of 123`, `fwc_refresh = FALSE`).
- The set raster `nearshore_mask_mask5adj.grd`: NA exactly on land, 189 cells, 14,205 km2, cell ids identical to `nearshore_set_issue15.csv`, no Atlantic cell.
- Both hybrid stacks equal the satellite-clipped stacks outside the set and the cell-wise maximum inside it, never below; no satellite detection removed.
- Per-month metrics equal the `union_hull` columns of `examine_months_issue15.csv` in all 278 satellite months on the 11 metrics of the #10 `mask5` stage (exposure, cells and km2 at the thresholds, maximum, cells changed, samples >= 10k and > 1M cells/L included).
- The combined stack equals the 6 Oct hoard stack in the 226 hull months.
- Writes `tables/md5_runA_issue18.csv`, `tables/hybrid_vs_prototype_issue18.csv`, `tables/nearshore_set_issue18.csv`. Copy `combined/`, `clipped/clipping_source.csv`, `clipped/nearshore_mask_mask5adj.*`, `ecospace_ascii/`, `plots/`, the run log to `hoard/runA/`.

**Run 0** (both `"none"`, same settings; about 8 min), then the unchanged #11 stage `none`: the 6 Oct maps byte for byte (the escape hatch still works after the code change). After each run: `git checkout -- out/5min/ecospace_ascii out/5min/plots`.

Pre-run test before run A (scratchpad, not committed): build the set with the new function on the on-disk VIIRS stack and compare with the #15 table; 1 min, catches a wrong adjacency before an 8-min run. Checkpoint 1.

## 6. Step 3: flip the defaults and regenerate, frozen samples (`config:`, `data:`)

1. `config:` defaults `"mask5adj"` for both keys in `run_redtide_maps.R`; `config.local.example.R` (the default, `"mask5"` and `"none"` as the alternatives); README config table and the cascade bullets (from "opt-in" to the default; `"none"` reproduces the satellite-only maps); `docs/issue5_nearshore-hybrid-summary/subissues/issue15_adjacent-land-hybrid/nearshore-set-method.md` "Implementation" paragraph (implemented in #18).
2. `config.local.R` for the final 5-min run: remove the two nearshore lines, keep `fwc_refresh FALSE`, set `export_ecospace TRUE`. Run (about 8 min). **Stage `final`** (`RT_QA_RES=5`): the 504 ASCII files equal run A byte for byte (`hoard/runA/`); the run log shows the rule without a local override; the files in `<ST drivers>/5min/red tide/sdmTMB/` equal `out/5min/ecospace_ascii/` by MD5; writes `tables/md5_final5_issue18.csv` (the new baseline for later checks).
3. **Stage `record`** (5 min): the whole record from the delivered combined stack against the 6 Oct hoard (and the run-B `mask5` hoard for the bracketed figures): per month, by era and by group, exposure, cell-months at >= 10k / >= 100k / > 1M cells/L, samples >= 10k and > 1M cells/L included; asserted equal to the #15 `union_hull` and `v6oct` totals. Writes `tables/record_months_issue18.csv`, `record_groups_issue18.csv`, `comments/record_summary.md`, `figures/fig1_headline_months_issue18.pdf` (the 16 headline months: samples | 6 Oct map | final map, vector PDF per Holden's rule), and `figures/fig2_record_2002-2026_issue18.png` (re-pointing `plot_summary_issue5.R` at the #18 table).
4. The 15-min run: `config.local.R` `cfg$res <- 15L`, same other settings. Cold run, about 20 min (every month fitted). **Stage `res15`**: set raster at 15 min (NA on land only, no Atlantic cell, counts reported and frozen; no 5-min numbers apply), hybrid relations as in `rule`, use counts, hull months equal between the hybrid and a satellite-only view only where asserted possible; MD5 of the 504 15-min files against the tracked May 2026 files recorded for the log (most will differ: the #3 hull rule and the hybrid both apply); export folder equals `out/15min/ecospace_ascii/`. Writes `tables/md5_final15_issue18.csv`, `tables/nearshore_set15_issue18.csv`. Copy both runs' outputs to `hoard/final5/` and `hoard/final15/`.
5. Checkpoint 2 on #18 (the MD5 tables, the record table, fig 1 and fig 2). Then commit the deliverables: `data:` 5 min (210 ASCII files + plots), `data:` 15 min (ASCII files + plots), `test:`/`qa:` the script and its outputs. The commit message names the rule, the frozen FWC date and the run log date.

## 7. Step 4: the refresh rerun (`data:`)

After checkpoint 2 and the deliverables commit: `config.local.R` with `fwc_refresh` removed (default TRUE), `res` 5, export on. Run (about 9 min: the `Recent_` query, a fit for 2026-10 if it has more than 5 positives, then the usual steps). **Stage `refresh`** (per resolution): the new FWC cache name and its end date; the ASCII files differ from the frozen run only in months from 2026-09 on, all hull-served (`use == "pred"`); the 278 satellite months are byte-identical to the frozen run; use counts unchanged; export folder equal. Then `res` 15 (about 10 min with the fits cached; the second pull returns no new records). Writes `tables/md5_refresh5_issue18.csv`, `md5_refresh15_issue18.csv`, `tables/refresh_months_issue18.csv` (what changed, with the sample counts). Commit `data:` (the tail months at both resolutions, the plots). Checkpoint 3 on #18. `config.local.R` left as the standing monthly-rerun config (defaults, export on; Holden decides whether export stays on).

## 8. Step 5: documentation and closure (`docs:`)

- `docs/issue5_nearshore-hybrid-summary/subissues/issue18_implement-hybrid-clipping/README.md`: what changed in the pipeline, how to run (the config of each run), files, results (the verification, the frozen regeneration at both resolutions, the refresh), the checks the script enforces.
- `docs/issue5_nearshore-hybrid-summary/README.md` (the #18 checkbox): "Where things stand" rewritten (done, the deliverables are the hybrid maps as of the run dates); section 2 gains the #18 step; section 4 numbers confirmed from the delivered maps (the `record` stage) with the source tables switched to #18; section 5 gains D10 to D13; section 6 becomes "Closed" with the follow-ups kept (MODIS-specific set, the positive-sample definition, the #3 clustering to-do, new VIIRS maps); appendix A2 (rule `"mask5adj"` implemented, the defaults, the 15-min set), A3 (the #18 runs added to the verification chain), A5 (the #18 row), A6 (the dates).
- `docs/README.md`: #18 row; the #5 row to "closed"; the #15 row's "follow in a new issue" sentence to "#18".
- One line each in the #11 and #10 READMEs (the deliverables are now the hybrid maps; the default is `"mask5adj"`; `"mask5"` and `"none"` remain for comparison runs).
- Root README: "Monthly rerun" step 3 unchanged; the ST-drivers paragraph unchanged; the config table done in step 3.
- Closing record on #5 (draft `comments/issue18-close5-comment.md`): the decision, the rule in one paragraph, the headline numbers from the `record` stage, the run dates and FWC dates, where the method and the evidence live. PR body updated, PR marked ready; Holden merges (closes #18 and #5).
- After the merge: local main fast-forwarded, the branch deleted, memory notes updated (new #18 memory; the #15 and #5 memories marked done).

## 9. Verification (end to end)

1. Stage `rule`: 210 of 504 files changed, all hybrid months; 278 of 278 months equal the prototype on 11 metrics; set 189 cells = the #15 table.
2. Stage `none` (#11): 0 of 504 files differ from 6 Oct.
3. Stage `final` (5 min): 0 of 504 differ from run A; export folder MD5-equal.
4. Stage `record`: totals equal the #15 `union_hull` and `v6oct` columns (e.g. satellite months: samples >= 10k included 63.2% -> 94.2%, exposure +8.4%; whole record exposure 8.87e9 -> 9.42e9, +6.2%).
5. Stage `res15`: set and hybrid relations hold at 15 min; export folder equal.
6. Stage `refresh` (both resolutions): only hull-served months from 2026-09 differ from the frozen run; satellite months byte-identical.
7. Every stage run twice gives identical CSVs and PNGs; `git status` clean apart from gitignored drafts; the hull months of the 5-min deliverables are byte-identical to 6 Oct in the frozen commit.
8. Hand spot checks: 2017-01 and 2003-02 in the final maps equal the prototype; one `mask5`-only cell (e.g. 2710, Anna Maria) and one adjacent-only cell are in the set raster; no cell east of -82 E and north of 28.5 N is in it.

## 10. Run notes

- `"C:/Program Files/R/R-4.5.1/bin/x64/Rscript.exe" run_redtide_maps.R` from the repo root, one run at a time, nothing else running (15 GB machine). Close any output PDF in Acrobat and any figure PNG in a viewer before a run or a check.
- Checks: `RT_QA_STAGE=<stage> RT_QA_RES=<5|15> Rscript docs/issue5_nearshore-hybrid-summary/subissues/issue18_implement-hybrid-clipping/check_final_hybrid_issue18.R`, 1 to 3 min each.
- Machine time: run A 8, run 0 8, final 5-min 8, 15-min cold 20, refresh 9 + 10 = about 63 min of runs plus checks, spread over the checkpoints.
- Wording: `>=10k`, `>=100k`, `>1M cells/L`; the Atlantic box is always excluded (asserted); every number in a README or a comment comes from a table the script writes.
