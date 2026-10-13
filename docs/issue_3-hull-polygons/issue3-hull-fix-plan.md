# RedTideMaps issue #3: spurious hull polygons in fallback months

Diagnosis and fix plan. Prepared and finalized 29 September 2026 for the branch `3-polygon-clipping-issues` (WFS-FEM/RedTideMaps). Sections 1 to 5 are written so they can be pasted into the issue as a comment; sections 6 to 10 are the finalized work plan for Claude Code (design in 6, decisions in 6.5, steps in 7, acceptance criteria in 8, kickoff prompt in 10).

## 1. Summary

The long, thin, low-concentration polygons that run from the Panhandle to southwest Florida in the combined maps (1991-01, 1996-08, 1996-09, 1996-10, 1997-01, 1998-02, 1998-03, 1999-11, 2002-02, 2025-12) are produced by `fn.buffered_hulls()` in `scripts/polygon_clipping_rt.R`. Every flagged month is a **buffered-hull fallback month** (no VIIRS before 2012, no MODIS nFLH polygon before 2002-07 or after 2025-09), and in each one a few positive samples far from the main bloom get lumped into a single concave hull with the main cluster. The hull is a sliver connecting distant points; the 10 km buffer turns it into a band; the clip then lets the sdmTMB prediction through along that band.

The root cause is the clustering logic, not concaveman or the buffer: k-means with a within-SS "elbow" (a) almost always returns k = 2, (b) cannot run at all for 4 to 7 positives, and (c) when any cluster has fewer than 4 points the code falls back to **one hull around all points**, which is exactly the case where the outliers should have been separated. The fix replaces k-means with a distance-based rule (single-linkage clustering cut at a user-settable linkage distance, default 75 km, base R `hclust`/`cutree`), gives small clusters a buffered-point footprint instead of forcing them into the main hull, and writes a per-run diagnostics table so future slivers are flagged automatically.

This matters operationally: the hull path is also the **live path for every month after the last satellite product** (currently 2025-10 onward), so any monthly update runs through this code until VIIRS/MODIS are refreshed.

## 2. Where the affected months come from

`make_redtide_ascii()` chooses per month: VIIRS if available, else MODIS, else the hull-clipped prediction (README, "Why the clipping cascade"). Coverage in the repo:

| Source | Coverage in repo | Flagged months covered? |
|---|---|---|
| VIIRS tifs (`VIIRS/redtide_maps_0.1degree/`) | 2012-01 to 2024-12 | none |
| MODIS nFLH polys (`MODIS/FLH polys 200207-20250926.Rdata`) | 2002-07 to 2025-09 | none (2002-02 is before 2002-07) |
| Buffered hulls | all months with ≥ 4 positive samples | **all ten** |

So the bug is confined to `fn.buffered_hulls()` and `fn.clip_2_hulls()`; VIIRS and MODIS months are unaffected and their ASCII files should be byte-identical before and after the fix (a useful regression check, section 8).

## 3. Root cause in `fn.buffered_hulls()` (`scripts/polygon_clipping_rt.R`, lines 24 to 92)

Positives are `cells != 0` for the month (line 39). The clustering block (lines 59 to 83) then has three failure paths:

**A. Small-cluster fallback hulls everything together (lines 70, 77 to 78).**
`if (min(table(pts_ym2$group)) >= 4)` hull each cluster; **else** `concaveman(pts_ym2, concavity = 1)` on *all* points. When k-means isolates 1 to 3 far-away samples as their own cluster, this branch fires and draws one hull from the outliers to the main bloom. With `concavity = 1` the hull hugs the points, so the connection is a thin neck, and `st_buffer(hull, 10000)` makes it a ~20 km band.
Months: 1991-01 (clusters 2 + 35), 1996-08 (3 + 13), 1997-01 (3 + 26), 1998-02 (3 + 12), 1999-11 (1 + 44).

**B. The elbow is undefined for 4 ≤ n < 8 (lines 62 to 65).**
`for (k in 1:min(10, nrow(coords) / 4))` gives `1:1` when n < 8, so `wss` has length 1, `diff(wss)` is empty, `which.max(...)` is `integer(0)`, and `ncenters` is `integer(0)`; the `else` branch (line 81) hulls all points.
Month: 1998-03 (6 positives spanning 337 km).

**C. The elbow heuristic always picks k = 2 (line 65).**
`which.max(abs(diff(wss))) + 1` selects the largest successive drop in within-SS, which for k-means is essentially always the drop from k = 1 to k = 2. In the emulation below it returned k = 2 in 15 of 15 months. With three real groups (Panhandle, Big Bend, southwest Florida), two get merged into one elongated hull.
Months: 1996-09 (4 + 4 split; one hull spans 358 km), 1996-10 (20 + 20; 556 km), 2002-02 (75 + 132; 641 km).

Contributing factors, not bugs on their own:

- "Positive" includes background-level detections. Several of the outliers are exactly 1,000 cells/L (1996-08 Apalachicola, 1991-01 offshore), which FWC reports as "not present/background" (0 to 1,000 cells/L; "very low" is >1,000 to 10,000; see https://myfwc.com/research/redtide/statewide/). Whether background detections should define a bloom footprint is a science decision for a separate issue (section 6.4); it also affects the sdmTMB fits, which use the same `cells != 0` rule.
- `kmeans()` is unseeded, so hull polygons (and therefore ASCII deliverables for fallback months) are not reproducible run to run. The jitter on line 48 (`runif`) is unseeded too.
- The concavity differs by branch (`concaveman(gp)` default 2 for clusters; `concavity = 1` for the fallback). concaveman implements Park and Oh (2012); lower concavity means a tighter, more concave hull.

## 4. Evidence

Emulated `fn.buffered_hulls()` in Python on `data/habsos_20240430.csv` (FWC samples via HABSOS, through April 2024), with the same spatial filter as `fn.filter_hab_data()` (depth-template box −87.5 to −81.0 °E, 25 to 30.5 °N, minus the Atlantic box). Concave hulls emulated with shapely rather than concaveman; for the small point sets involved both reduce to nearly the convex hull. Diagonal = bounding-box diagonal of the buffered hull; "band ratio" = hull area ÷ (diagonal × 20 km), where ≈ 1 means the polygon is essentially a 20 km wide band.

| Month | n positive | Branch taken | Largest hull diagonal (km) | Band ratio | Flagged? |
|---|---|---|---|---|---|
| 1991-01 | 37 | A: k=2 gave sizes 2, 35 → single hull | 543 | 3.3 | yes |
| 1996-08 | 16 | A: sizes 13, 3 → single hull | 484 | 1.7 | yes |
| 1996-09 | 8 | C: split 4, 4 | 358 | 1.1 | yes |
| 1996-10 | 40 | C: split 20, 20 | 556 | 2.2 | yes |
| 1997-01 | 29 | A: sizes 3, 26 → single hull | 242 | 1.7 | yes (the "maybe") |
| 1998-02 | 15 | A: sizes 12, 3 → single hull | 523 | 2.6 | yes |
| 1998-03 | 6 | B: elbow undefined → single hull | 373 | 1.5 | yes |
| 1999-11 | 45 | A: sizes 1, 44 → single hull | 562 | 1.2 | yes |
| 2002-02 | 207 | C: split 75, 132 | 641 | 1.5 | yes |
| 1996-07 | 14 | split 9, 5 | 140 | 1.5 | no |
| 1996-11 | 82 | split 17, 65 | 274 | 1.9 | no |
| 1996-12 | 25 | split 11, 14 | 99 | 1.7 | no |
| 2002-01 | 154 | split 105, 49 | 227 | 1.9 | no |
| 2002-03 | 66 | split 52, 14 | 240 | 1.4 | no |

Every flagged month reproduces; none of the five control months does. 2025-12 is after the HABSOS file and was not emulated, but it is a hull month with the same code path. The figure `issue3_hull_before_after.png` shows 1991-01, 1996-08, 1998-02 and 1999-11 under the current logic and under the proposed rule.

Example, 1996-08: three samples of 1,000 to 1,330 cells/L near Apalachicola on 1 August, and 13 samples of 333 to 333,000 cells/L between Sarasota and Sanibel. k-means splits them 3 + 13, the 3-point cluster trips the `< 4` check, and one hull is drawn from Apalachicola to Sanibel (484 km, ~15,900 km² after buffering).

## 5. Downstream impact

The band carries the sdmTMB prediction for that month, mostly 10⁴ to 10⁵ cells/L (purple to blue in the PDF palette, whose first non-white break is 10,000). In the WFS-FEM the direct mortality response is a logistic in cells/L with inflection points of 50,000 to 400,000 cells/L, and the foraging (avoidance) response has inflection points of 12,500 to 300,000 cells/L (Chagaris et al. 2025, SEDAR88-WP; Vilas et al. 2023). So the artifact adds small direct mortality and a spurious foraging response over open-shelf cells that had no positive sample within 100 to 500 km, in the affected months. The 1990s months precede the 2002 to 2022 mortality series used for SEDAR 88, but the model runs from 1985, and 2025-12 and every later month until the satellite products are refreshed are also hull months. The effect on annual mortality is probably small; the point is that the operational pipeline must not produce it unattended.

## 6. Fix design

### 6.1 Recommended: distance-based clustering, footprint per cluster

Replace the k-means block with single-linkage hierarchical clustering cut at a linkage distance (base R, no new dependency, deterministic):

```r
# Two positive samples belong to the same footprint if a chain of positive
# samples connects them with every link shorter than link_km.
# pts_ym: sf POINT in EPSG:32617 (metres), positives for one (year, month).
coords <- st_coordinates(pts_ym)
grp <- if (nrow(coords) == 1) 1L else
  cutree(hclust(dist(coords), method = "single"), h = link_km * 1000)
pts_ym$group <- factor(grp)

# Work in sfc throughout: concaveman() on an sf object returns a geometry
# column named "polygons", which would not rbind with st_sf(geometry = ...).
footprints <- lapply(split(pts_ym, pts_ym$group), function(gp) {
  g   <- st_geometry(gp)
  g_u <- st_cast(st_union(g), "POINT")           # distinct locations only
  core <- NULL
  if (length(g_u) >= min_hull_pts)
    core <- tryCatch(concaveman(g_u, concavity = concavity),
                     error = function(e) NULL)
  # Too few distinct locations, or a degenerate (collinear) hull: buffer the
  # points themselves, which is what hull + buffer tends to anyway.
  if (is.null(core) || !all(st_is_valid(core)) || as.numeric(st_area(core)) == 0)
    core <- st_union(g_u)
  st_buffer(core, buffer_km * 1000)
})
hab_pol <- st_sf(group = names(footprints), geometry = do.call(c, footprints))
# (the sfc objects already carry EPSG:32617, so no crs argument is needed)
# One geometry type for the whole column, so raster::rasterize() (which goes
# through sf::as_Spatial) never sees a mixed POLYGON/MULTIPOLYGON column.
hab_pol <- st_cast(st_transform(hab_pol, 4326), "MULTIPOLYGON")
```

Notes on the sketch: `hclust()` needs at least two points, hence the `nrow == 1` guard; exact duplicate coordinates are fine for single linkage (distance 0), so the `runif` jitter on line 48 is no longer needed for clustering, and `st_union(g)` removes duplicates before `concaveman()`. `concaveman.sfc` uses `st_coordinates()`, so pass POINT geometries (not a MULTIPOINT, whose coordinates carry an extra `L1` column). Compute the diagnostics (area, bounding-box diagonal) on `footprints` in UTM before the transform to 4326.

Parameters (new `cfg` keys in `run_redtide_maps.R`, passed through to `fn.buffered_hulls()`):

| Key | Default | Meaning |
|---|---|---|
| `hull_link_km` | 75 | single-linkage cut distance (decided 29 Sept 2026; see 6.2). Override per machine in `config.local.R`, e.g. `cfg$hull_link_km <- 50` |
| `hull_buffer_km` | 10 | buffer around each footprint (unchanged from today) |
| `hull_min_pts` | 4 | distinct locations needed for a concave hull; smaller clusters get buffered points |
| `hull_concavity` | 2 | concaveman concavity, one value for all clusters (today: 2 for clusters, 1 for the fallback) |
| `hull_warn_span_km` | 300 | diagnostics flag threshold (section 6.3) |

Single linkage at distance h is the same thing as connected components of the "within h km" graph, which is the rule the hull is meant to express. It is deterministic, so the ASCII deliverables for fallback months become reproducible.

### 6.2 Choice of linkage distance (sensitivity, from the same emulation)

Decision (Holden, 29 Sept 2026): default `hull_link_km = 75`, user-settable. The evidence behind it follows.

Minimum linkage distance at which all positives in a month collapse to one cluster, i.e. the gap the outliers would have to bridge:

| Flagged months | km | Real blooms (control) | km |
|---|---|---|---|
| 1991-01 | 301 | 1996-12 | 47 |
| 1996-08 | 324 | 2002-01 | 50 |
| 1996-09 | 327 | 2005-09 | 49 |
| 1996-10 | 321 | 2021-07 | 45 |
| 1997-01 | 121 | 2018-09 | 253 (Panhandle + SW Florida) |
| 1998-02 | 210 | 2018-10 | 172 |
| 1998-03 | 213 | | |
| 1999-11 | 484 | | |
| 2002-02 | 495 | | |

Any cut of 100 km or less separates the flagged outliers (they need 121 to 495 km). The large coast-wide blooms of 2005-09, 2002-01, 2021-07 and 1996-12 stay in one cluster at 50 km and above (their largest link is 45 to 50 km); at 25 km they fragment into 3 to 13 clusters. Fragmentation is not harmful under the new rule, since every cluster still gets a footprint, but it is unnecessary.

Three-way comparison at 50, 75 and 100 km (figure `issue3_hull_50_75_100km.png`; four flagged months and three real blooms):

| Month | 50 km | 75 km | 100 km |
|---|---|---|---|
| 1991-01 (flagged) | 3 footprints, 3,252 km², span 131 km | same | same |
| 1996-08 (flagged) | 3, 2,731 km², span 65 km | 2, 3,670 km², span 139 km | same as 75 |
| 1998-02 (flagged) | 5, 5,062 km², span 96 km | 3, 7,971 km², span 194 km | same as 75 |
| 1999-11 (flagged) | 2, 2,307 km², span 93 km | same | same |
| 1996-11 (bloom) | 4, 11,789 km² | 3, 13,528 km² | same as 75 |
| 2002-03 (bloom) | 3, 7,067 km² | 2, 8,756 km² | same as 75 |
| 2018-10 (bloom) | 6, 36,232 km² | 4, 40,922 km² | same as 75 |

Across the 349 hull-fallback months with ≥ 4 positives (pre-2012 or after 2025-09): clustering is identical at 50 and 75 km in 246 months, at 75 and 100 km in 292, at 50 and 100 km in 212; median total footprint per month is 4,198 km² at 50 km, 4,735 at 75 and 5,128 at 100. Across all 475 months, the largest cluster spans > 350 km in 8 months at 50 km, 15 at 75 and 25 at 100 (the current code exceeds 480 km in six of the ten flagged months).

Reading: 50 km is the smallest cut that keeps the observed coast-wide blooms intact, so it is the "only where sampled" end of the range; 75 km additionally joins sampled patches separated by 50 to 75 km of unsampled coast (Sarasota to Sanibel in 1996-08, Charlotte Harbor to Naples in 1998-02, the along-coast gaps in 1996-11 and 2002-03), and going to 100 km adds almost nothing beyond that. The cost of 75 km is that a single sample at the margin can become a hull vertex rather than an isolated disc (2018-10: one offshore sample at about −84, 28.5 pulls the main hull ~100 km offshore). 75 km was chosen as the default to favour along-coast continuity of the footprint; 50 km is the sensitivity case to report (and to prefer if the marginal-vertex behaviour turns out to matter in the diagnostics). There is no literature value for this distance; it encodes the sampling spacing of the FWC coastal monitoring more than bloom biology.

### 6.3 Diagnostics and QA

`fn.buffered_hulls()` writes `out/<res>min/sdm/hull_diagnostics.csv` on every run as a side effect (its return value stays the hull-polys path, so the call site and the archive scripts are unaffected): one row per (year, month) with `yrmo, n_pos, n_locations, n_clusters, cluster_sizes` (sizes pasted with `;`), `n_polys, total_area_km2, max_area_km2, max_span_km, flagged`, where `max_span_km` is the largest bounding-box diagonal of any footprint (UTM, before reprojection) and `flagged = max_span_km > warn_span_km`. The driver then reads the CSV and writes the count and list of flagged months to the run log with `rt_log(paths, ...)` (`rt_log` takes `paths` and a message, so it is called from `run_redtide_maps.R`, not from inside the function). A flag is a prompt for a human look, not a failure (a real coast-wide bloom can legitimately exceed 300 km).

### 6.4 Alternatives considered

- Keep k-means and simply drop clusters with fewer than 4 points. Fixes A but not B or C, keeps the unseeded RNG, and drops real detections silently. Not recommended.
- DBSCAN (`dbscan::dbscan`, eps = the same linkage distance, minPts = 1 to 4). Equivalent behaviour to single linkage for this purpose but adds a dependency; single linkage in base R is enough.
- A sliver post-filter alone (reject polygons by area/perimeter ratio). Treats the symptom; keep it only as the diagnostics flag.
- Raising the positive threshold (e.g., > 1,000 cells/L, FWC "very low" and above) for hull membership. This would remove several of the outliers on its own but changes what a footprint means and interacts with the sdmTMB positive-only fits, so it belongs in a separate issue with Dave's input, not in this PR.

### 6.5 Decisions (finalized 29 Sept 2026)

1. `hull_link_km = 75` as the default, overridable in `config.local.R` (section 6.2). Report 50 km as the sensitivity case in the PR. Decided by Holden.
2. Small clusters (fewer than `hull_min_pts` distinct locations) get a buffered-point footprint rather than being dropped, so every positive sample stays inside a footprint and the rule is uniform. Finalized as the default; change `hull_min_pts` or the branch in 6.1 if Dave prefers otherwise.
3. Months with 1 to 3 positives currently get no hull at all (`if (nrow(coords) < 4) next`, lines 41 and 57). The new rule processes every month with at least one positive and gives them small buffered discs. This changes nothing in the output where there is no sdmTMB fit (fits need > 5 positives, so the prediction is NA and the clip gives 0); the arbitrary threshold goes. Finalized.
4. A follow-up issue on the positive-sample definition (6.4, last bullet: whether background-level detections of ≤ 1,000 cells/L should define a footprint) will be opened in RedTideMaps after this PR, for discussion with Dave. It is out of scope here.

Nothing in this list needs to stop the implementation; Claude Code should proceed through section 7 and raise a question only if the code contradicts the plan.

## 7. Implementation steps (for Claude Code, on branch `3-polygon-clipping-issues`)

Reviewed and finalized 29 Sept 2026. Constraints that apply to every step: base R only for clustering (`stats::hclust`, `stats::cutree`), no new package dependencies; do not touch `fn.clip_2_viirs()`, `fn.clip_2_modis()`, `make_redtide_ascii()` or the sdmTMB code; keep every existing function signature valid for old callers (new arguments get defaults); the machine is Windows 11 with R 4.5.1, so avoid shell pipes inside R and prefer R functions (`tools::md5sum()`, `file.copy()`) over PowerShell.

1. **Confirm the branch.** `git branch --show-current` prints `3-polygon-clipping-issues`; `git status` is clean; `git log -1` is at or after `1641e3e`.
2. **Read** `scripts/polygon_clipping_rt.R`, the `cfg` block of `run_redtide_maps.R` (lines 38 to 71) and the step 5a call (lines 161 to 166), `scripts/_setup.R` (`rt_paths`, `rt_log`), `config.local.example.R`, and README sections "Why the clipping cascade", "Configuration" and "Outputs". Confirm that `out/5min/sdm/*_filtered.Rdata` and the cached fits exist from a previous run; if not, run the pipeline once first so step 7 has inputs and step 8 has a baseline.
3. **Rewrite `fn.buffered_hulls()`** per section 6.1. New signature: `fn.buffered_hulls(file_filtered, file_depth, dir_out, styr = NULL, enyr = NULL, link_km = 75, buffer_km = 10, min_hull_pts = 4, concavity = 2, warn_span_km = 300)`. Remove the k-means block (lines 59 to 83), the `runif` jitter (lines 43 to 57) and both `< 4` skips (lines 41 and 57); process every (year, month) with at least one positive. Keep the `cells != 0` definition of positive (section 6.4). Save `pol_list` exactly as before (names `"%d%02d"`, one sf per month, EPSG:4326, MULTIPOLYGON) so `fn.clip_2_hulls()` needs no change. Roxygen: update the description and document the new arguments and the diagnostics file.
4. **Diagnostics** (section 6.3): build the rows inside the month loop, write `file.path(dir_out, "hull_diagnostics.csv")` before returning, keep the return value as the hull-polys path. In `run_redtide_maps.R`, after the step 5a call, read the CSV and `rt_log()` the number of flagged months and their `yrmo` values (or "no flagged hulls").
5. **Config.** Add `hull_link_km = 75, hull_buffer_km = 10, hull_min_pts = 4L, hull_concavity = 2, hull_warn_span_km = 300` to `cfg` with one-line comments, pass them into the step 5a call, and add a commented block to `config.local.example.R` (`# cfg$hull_link_km <- 50` with a sentence on what it does).
6. **README.** "Why the clipping cascade": replace the k-means sentence with the single-linkage rule and the buffered-points behaviour for small clusters, and state the default of 75 km. Configuration table: the five new keys. Outputs tree: `hull_diagnostics.csv` under `sdm/`. Add one sentence under "Monthly rerun" step 2 telling the operator to check the flagged-hull line in the run log.
7. **QA script** `scripts/qa/check_hulls_issue3.R` (tracked). Once, from the shell: `git show main:scripts/polygon_clipping_rt.R > scripts/qa/_polygon_clipping_rt_main.R` (add `scripts/qa/_*` to `.gitignore`; this is the pre-fix code for comparison). The script: sources `_setup.R` for the libraries, `sys.source()`s the old file into `env_old <- new.env()` and the working-tree file into `env_new`, loads `out/5min/sdm/*_filtered.Rdata`, and for the ten flagged months plus the controls (1996-07, 1996-11, 1996-12, 2002-01, 2002-03, 2005-09, 2018-09, 2018-10, 2021-07) builds the old hulls (with `set.seed(1)` so k-means is repeatable) and the new footprints at `link_km` 50 and 75. Output: `out/5min/plots/hull_check_issue3.pdf` (one page per month: samples coloured by log10 cells/L, old hull, new footprints at both distances, with n, area and max span in the panel) and the diagnostics rows for both distances printed to the console. Also a synthetic `stopifnot()` block: 3 points near (−85, 29.7) and 12 points near (−82.4, 27.0), projected to 32617, must give two footprints at 75 km, neither spanning more than 100 km; and two consecutive calls on the same input must return `identical()` polygon lists (determinism, which the old k-means code fails).
8. **Baseline before the full run.** With R: `tools::md5sum(list.files("out/5min/ecospace_ascii", full.names = TRUE))` saved to `out/5min/md5_before.csv`, and copy `out/5min/clipped/clipping_source.csv` to `out/5min/clipping_source_before.csv` (both under the gitignored `out/**`).
9. **Full run.** `Rscript run_redtide_maps.R` (about 9 min on a warm cache; the sdmTMB fits are cached and are not refit). Then work through section 8 and record the evidence.
10. **Housekeeping (optional, separate commit).** `.Rhistory` and `scripts/.Rhistory` are in `.gitignore` but still tracked, so every R session dirties the tree: `git rm --cached .Rhistory scripts/.Rhistory`.
11. **Commit and PR.** Commit (a) code + README + config example + QA script; (b) regenerated deliverables (`out/5min/ecospace_ascii/`, `out/5min/plots/`); (c) the `.Rhistory` untracking if done. `git push` (the upstream branch exists). Open the PR against `main` with `Fixes #3`, a short summary of sections 3 and 6, the section 8 checklist with evidence, `hull_check_issue3.pdf` attached, and a note for Dave on the 75 km default and the `config.local.R` override.

## 8. Acceptance criteria

- The ten flagged panels in `out/5min/plots/*_clipped_combined.pdf` no longer show a polygon spanning the Big Bend; footprints sit on the sampled clusters only. (Evidence: the panels, plus `hull_check_issue3.pdf`.)
- `hull_diagnostics.csv`: none of the ten months is flagged at 75 km, and any other flagged month is a real coast-wide bloom on inspection (list them in the PR).
- `clipping_source.csv` is identical to `clipping_source_before.csv` (the cascade decision is untouched).
- Every ASCII for a VIIRS or MODIS month (`use != "pred"` in `clipping_source.csv`) has the same MD5 as in `md5_before.csv`; only `use == "pred"` months change. Report how many changed.
- Determinism: the `stopifnot()` block in the QA script passes (two calls on the same input give identical polygon lists).
- Run log ends with `Run complete.` and contains the flagged-hull line; no new package dependency (`rt_check_packages()` list unchanged); `Rscript run_redtide_maps.R` still works from a fresh clone.

## 9. GitHub workflow for this fix

Already done: issue #3 created; branch `3-polygon-clipping-issues` created from the issue's Development sidebar; `git fetch origin` and `git checkout 3-polygon-clipping-issues` run locally ("Checkout locally" is the right choice: it gives the two commands to run in your existing clone, as opposed to opening GitHub Desktop).

Remaining:

1. Work on the branch in Claude Code (section 7). Commit as you go; the branch is already tracking `origin/3-polygon-clipping-issues`, so `git push` is enough after the first commit.
2. Open the pull request after the first push. GitHub shows a "Compare & pull request" banner on the repo page, or use `gh pr create --base main --fill` from the terminal. Put `Fixes #3` in the description so merging closes the issue automatically. A draft PR opened early is a good place to attach the before/after PDF and the diagnostics table while the work is in progress; mark "Ready for review" when done.
3. Review and merge with "Squash and merge" (one clean commit on `main`) or a merge commit, whichever the repo has used so far (PR #2 used a merge commit). Delete the branch on merge.
4. Project tracking: the organization project's auto-add workflow only watches WFS-FEM/Ops, so add issue #3 to project #4 by hand from the issue sidebar ("Projects") if it should appear on the board; closing it will then move it to Done. Label it `bug` in RedTideMaps.
5. Log the linkage-distance decision (75 km default, user-settable; 50 km sensitivity) in `docs/decisions.md` in WFS-FEM/Ops, and note it for Dave in the PR description.

## 10. Claude Code kickoff prompt

Copy the plan into the repo first (`docs/issue-3-hull-fix-plan.md`; commit it with the code so the PR carries its own rationale), then start Claude Code in the repo root on the branch and paste:

```
We are fixing WFS-FEM/RedTideMaps issue #3 (spurious hull polygons in
fallback months) on branch 3-polygon-clipping-issues. The diagnosis and the
finalized plan are in docs/issue-3-hull-fix-plan.md. Read it fully first.
Sections 6.1 to 6.3 are the design, 6.5 lists the decisions already made
(default hull_link_km = 75, overridable in config.local.R; buffered points
for small clusters; every month with >= 1 positive gets a footprint), and
section 7 is the step list: work through it in order, pausing after step 7
(QA script results) and after step 9 (full run) to show me the evidence
before committing. Constraints: base R hclust/cutree for clustering, no new
package dependencies, do not modify the VIIRS, MODIS, combine or sdmTMB
functions, keep fn.buffered_hulls() returning the hull-polys path, and keep
pol_list in the same format so fn.clip_2_hulls() is unchanged. Windows 11,
R 4.5.1: use R functions (tools::md5sum) rather than shell pipes for the
baseline. Finish by reporting the section 8 acceptance criteria as a
checklist with evidence (MD5 comparison for VIIRS/MODIS months, the
hull_diagnostics.csv rows for the ten flagged months at 75 km and 50 km,
the stopifnot results, and the path to hull_check_issue3.pdf), then draft
the PR description with "Fixes #3".
```

## References

- Chagaris, D., et al. 2025. Estimates of red tide mortality on red grouper 2002 to 2022 from the West Florida Shelf Fisheries Ecosystem Model. SEDAR88-WP (project file). Mortality response `P = 1 / (1 + (x/c)^-b)` with c = 50,000 to 400,000 cells/L; foraging response inflection 12,500 to 300,000 cells/L.
- Vilas, D., et al. 2023. Evaluating red tide effects on the West Florida Shelf using a spatiotemporal ecosystem modeling framework. Scientific Reports 13:2541. https://doi.org/10.1038/s41598-023-29327-z
- Park, J.-S., and S.-J. Oh. 2012. A new concave hull algorithm and concaveness measure for n-dimensional datasets. Journal of Information Science and Engineering 28:587–600. (Algorithm implemented by the `concaveman` R package.)
- Florida Fish and Wildlife Conservation Commission, statewide red tide status and K. brevis abundance categories: https://myfwc.com/research/redtide/statewide/
- WFS-FEM/RedTideMaps README, "Why the clipping cascade" and "Outputs": https://github.com/WFS-FEM/RedTideMaps
- Figures: `issue3_hull_before_after.png` (current logic vs 50 km), `issue3_hull_50km_vs_100km.png`, `issue3_hull_50_75_100km.png` (in `operationalizing/Claude outputs/`).
- Emulation scripts (Python, shapely + scipy) used for sections 4 and 6.2: `hull_check.py`, `link_sensitivity.py`, `hull_figure*.py` (Claude session scratch; the R QA script in step 7 supersedes them).
