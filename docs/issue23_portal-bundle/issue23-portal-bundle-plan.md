# Issue #23: the data bundle for WFS-Portal (the producer side of the Red Tide Maps portal)

Plan for [WFS-FEM/RedTideMaps#23](https://github.com/WFS-FEM/RedTideMaps/issues/23) (Holden, 3 Nov 2026), approved 4 Nov 2026. The issue asks for an R Shiny visualization tool and data portal for the monthly red tide maps. The decisions taken during planning split the work in two: this repository gains a final pipeline step that writes a tracked, data-only bundle of the delivered maps (the schema is `bundle-schema.md` in this folder), and the application itself is built in a new repository, [WFS-FEM/WFS-Portal](https://github.com/WFS-FEM/WFS-Portal), designed as the future integrated portal for the Ecospace outputs with the red tide maps as its first product. #23 closes when the bundle ships; the portal has its own issues there.

This document is the plan file of the planning session as approved: first the executable summary (the findings, the decisions D1 to D18, the design summary, the step list with checkpoints, the verification), then, as an appendix, the full revised design document (the bundle schema, the producer stage, the WFS-Portal layout, the product contract, the Shiny modules, the pre-render step, the fetch flow, the tests, the issue drafts). The sections that concern the portal are copied into the WFS-Portal docs folder at its step P1. Paths in the appendix are absolute to the planning machine; the repository paths are the ones that matter.

---

# Issue #23: Red Tide Maps portal (R Shiny) — plan

Status: approved 4 Nov 2026 (the planning session's final draft). Decisions D1-D4 fixed with Holden (3 Nov); design
decisions D5-D14 from the design workflow (three independent designs, three judges, a synthesis,
three critics, a revision; every repo claim verified) and my review; Holden's answers D15-D18
(3 Nov). This plan is the executable summary. The full revised design document (schema, stage,
portal, modules, tests, issue drafts; about 117 KB) is the appendix at the end, for reference
during implementation; step 1 copies it into docs/issue23_portal-bundle/ as the issue plan
(house convention), and step P1 copies the portal sections into the WFS-Portal issue folder.

## Context

The RedTideMaps pipeline (run_redtide_maps.R) turns FWC cell counts and USF satellite imagery
into monthly red tide maps on the 5-arcmin WFS Ecospace grid. Issue #23 asks for an R Shiny
application that (Part 1) visualizes those maps month by month with summary metrics (panels
A-F: map, exposure time series, band histogram, FWC samples, previous and next thumbnails, a
key-information box; month slider with auto-play), (Part 2) exports figures (PNG/TIFF/JPG,
12-months-per-page PDF, GIF), and (Part 3) serves as a data portal (time and bounding-box
subsets of maps and tables). Holden also plans a larger integrated portal for Ecospace outputs
(species and fleet distributions beside the red tide maps, per-species downloads), which fixed
the repository decision. Issue #22 is an earlier truncated draft of #23: close as a duplicate.

## What the surveys found (3 Nov 2026)

Data products
- Final maps: out/5min/ecospace_ascii/sdmTMB_log__YYYYMM.asc, 504 months 1985-01 to 2026-12,
  tracked, 10.6 MB. Linear cells/L, land = NODATA (-3.4e+38; the first token is printed as a
  39-digit decimal: treat values < -1e30 as NA). Grid 78 x 66 = 5,148 cells, 3,838 water,
  extent -87.5..-81 E, 25..30.5 N. 2026-11 and 2026-12 are zero placeholders (the run covers
  the whole current year). 173 months all zero; 54,375 positive cell-months; no cell is exactly
  10,000. scan() reads all 504 files in 0.35 s. The combined .grd stack is FLT4S and differs
  from the ASCII at the 16th digit in 162 months (compare with all.equal, as #18 does).
- Per-month clipping method: out/5min/clipped/clipping_source.csv (yrmo with X prefix; use in
  hybrid / viirs / hybrid_modis / modis / pred; hybrid_changed). NOT tracked.
- FWC samples: cell_counts/ (gitignored) -> out/5min/sdm/FWC HAB data 19800102-20261021_filtered.Rdata
  (filtered_points_df sf: year, month, cells, lon, lat; 183,402 rows, 181,411 from 1985 on,
  39,928 positives, 93 off-grid, 44,430 on land cells of the template = bay stations). NOT tracked.
- No per-month summary table is written by the pipeline. The #18 tables under
  docs/issue5_nearshore-hybrid-summary/subissues/issue18_implement-hybrid-clipping/tables/
  (clip_class_counts_hybrid_issue18.csv final_* and fwc_* columns; record_months_issue18.csv;
  nearshore_set5_issue18.csv; md5_refresh5_issue18.csv) are a verified 504-month snapshot of the
  run on disk and serve as the regression target. record_months predates the refresh: 202609
  and 202610 are exempt from that comparison (clip_months_hybrid_issue18.R:68, 306-309).
- 2018-09 recomputed from the ASCII: exposure 310,492,554.245117; 648 positives; bands
  0 / 0 / 127 / 450 / 71; 648 cells >= 10k over 49,160 km2; max 7,746,619 at cell 2864.
- hull_diagnostics.csv flags 71 months, but the pipeline rule counts only hull-served months
  (use == "pred"): 10 today (run_redtide_maps.R:321-338).
- RT_fit_matrix: fit_sdmTMBlog in 336 rows; convergence TRUE 328, FALSE 3, "no model" 173.

Plotting code
- No shared plotting module and no R/ folder. The panels in the issue images come from
  clip_months_hybrid_issue18.R: draw_panel() (base image(), wheat land from the template NA
  cells), colorbar_legend(), sample_legend(), class_counts(), exposure_of(), map_info()
  (exposure first, then positives and five bands), to_z(), read_mat(), norm_map(). They depend
  on script globals (xs, ys, xlim, ylim, land_z, color, brks_img, nc, nr, sbrks, spal, water, fmt_n).
- Pipeline palette (polygon_clipping_rt.R:339-343): colv = white, purple, blue, darkblue, cyan,
  green, darkgreen, yellow, orange, red, darkred; colorRampPalette(bias = 2);
  brks = c(0, 1e4 - 1, seq(1e4, 4e6, 1e4), Inf); linear, white below 10k.
- Bands in every check script: cut(v[v > 0], c(0,1e3,1e4,1e5,1e6,Inf), include.lowest = TRUE),
  right-closed, zeros excluded (this is FWC's own class convention). Samples colored
  viridis(5, direction = -1). The older fn.plot_hab_data uses left-closed bands (outlier).
- Exposure series: base lines() in plot_summary_issue5.R (million cells/L, era shading).
- 12-months-per-page PDF layout exists in fn.plot_redtide_stack (pipeline) and the #18 script.

Automation and repo
- No scheduler, workflow, or deploy script anywhere as of now, but planned for the future. Runs are manual; VIIRS tifs are added by
  hand (stack ends 2024-12); MODIS polygons end 2025-09; deliverables committed by hand. A
  monthly rerun takes about 9 min. fn.plot_sdmTMB and fn.plot_redtide_stack rewrite the tracked
  plots PDFs (date lines) on every run, so the tree is never clean at the end of a run.
- Repo public (WFS-FEM/RedTideMaps), MIT (David Chagaris); authors Chagaris, Vilas, Harris.
  core.autocrlf = true; no .gitattributes; R writes CRLF here, git stores LF.
- Local refs stale: remote main is 4fee1c9 and already contains branch 5-subissue-folders
  (PR #21 merged 28 Oct) plus three README edits. #23 starts from git fetch --prune + ff main.

Conventions: 
- one docs folder per issue (docs/issueNN_slug/ with README, plan, check script,
  tables/, figures/, comments/, per-folder .gitignore for hoard/ and comment drafts) branch
  NN-slug; 
- draft PR; small commits split by type (docs:, feat:, config:, test:, qa:, data:);
- Holden merges with a merge commit; pauses with evidence before commits. 
- American English; metric units
- k/M wording for cell counts, i.e, 'k' = 1,000 and 'M' = 1,000,000
- This project focuses on the West Florida Shelf in the Gulf of Mexico; 
  water cells in the the Atlantic box (lon > -82, lat > 28.5) should always excluded from every spatial set; 
- explain Git, data science, and coding processes with minimal jargon
- Fully and carefully document code, workflow, and decisions
- Inherited code tested for '3-way reproducibility': (1) runs here (Holden's machine), (2) should run on an external user, (3) changes made so that the code would run on the orignal author's machine

Environment (R 4.5.1 ucrt; Rscript at C:/Program Files/R/R-4.5.1/bin/x64/Rscript.exe, not on PATH)
- Installed: shiny 1.12.0, bslib 0.9.0, htmltools, jsonlite, testthat 3.3.1, rsconnect, httpuv,
  leaflet, magick, gifski, ragg, png, terra 1.8.80, raster 3.6.32, sf, data.table, dplyr,
  ggplot2, viridis, fields, maps, memoise, digest, renv, pak, arrow, fst, gh.
  capabilities("cairo") and capabilities("tiff") TRUE. Sys.which("git") resolves.
- Not installed: shinytest2, shinylive, plotly, qs.
- run_redtide_maps.R: cfg list 42-96; validation 104-130; source list 140-146; hab (170),
  fit_files (184), pred_paths (195), clip_viirs (222/225), clip_modis (232/247),
  nearshore only inside the if at 261-274, clip_hybrid 260, combined_path 310, step 8 export
  340-346, "Run complete." 347. make_redtide_ascii (polygon_clipping_rt.R:241-326) writes
  clipping_source.csv and the combined stack; norm_v (NA -> 0 on water, land -> NA) is the
  normalization the bundle must match. rt_paths() _setup.R:86-139, rt_init_dirs() 142-151.

## Decisions

Fixed with Holden (3 Nov 2026)
- D1 Hosting: undecided until a constraint forces it. Build portable: light dependencies, no
  host-specific code, deployable from the app folder. An institutional server may exist later.
- D2 Repository: a NEW repo WFS-FEM/WFS-Portal (D2a) that is the future integrated portal;
  red tide is product one. RedTideMaps gains a final pipeline stage that writes a tracked,
  data-only bundle and documents its schema; WFS-Portal holds the app, product-agnostic modules,
  the plotting code (the #18 panel style is presentation), the pre-render cache, and a fetch
  script. Monthly update: pipeline run + commit in RedTideMaps, then fetch + commit + redeploy.
- D2b The red tide product is also deployable standalone under the name "Red Tide Maps" (same
  code, one product enabled).
- D3 Part 1 maps: static base-graphics panels in the #18 style, pre-rendered to PNG by a build
  step and cached; aesthetics adjustable; fast scroll and play. Interactive maps revisited later
  only if fast enough.
- D4 Issue #23 covers the producer side in RedTideMaps and closes when the bundle ships;
  WFS-Portal gets its own issues for Parts 1-3, linked from #23; #22 closed as a duplicate.
- Note: WFS-Portal is cloned at C:/Repos/WFS-FEM/WFS-Portal; Claude Code needs that folder
  added as a working directory (/add-dir) or a session started there.

Design decisions (from the design workflow, 3 Nov 2026, and my review)
- D5 Bundle = text: CSV tables + JSON metadata, LF line endings pinned by a .gitattributes in
  the bundle folder, deterministic sort, shortest round-trip decimals (%.15g, %.17g fallback),
  an md5 manifest written last. No RDS, no binary. Values long-sparse per year (yrmo, cell,
  value; positive water cells only; 1.43 MB total). Samples per year. Small monthly diffs.
- D6 The bundle carries product data only: grid, months, layers, values, summary, samples,
  meta, and a style.json limited to facts about the product (palette recipe + expanded hex,
  band breaks/columns/labels, units, the use-code list). All presentation (sizes, cex, pch,
  line colors, era shading, series labels, panel text) lives in WFS-Portal's one style file.
- D7 The stage reads the tracked ASCII (the deliverable; 0.35 s) plus the run's gitignored
  outputs (clipping_source.csv, filtered samples, stacks, fit matrix, mask, hull diagnostics)
  and needs the run on disk, like every check script. No "rebuild from a fresh clone" claim.
- D8 Provenance: meta.source.ascii_commit = last commit touching out/<res>min/ecospace_ascii
  and ascii_dirty = porcelain scoped to that folder (TRUE on a monthly update, FALSE on a
  verification run); no unscoped dirty flag. The bundle's own commit is known only after the
  data: commit and lives in WFS-Portal's FETCH.json; the footer shows that commit.
- D9 hull_flagged = hull_diagnostics flagged AND use == "pred" (the pipeline rule); the span
  itself travels as hull_span_km. Bands right-closed on positive cells, labeled "<= 1k",
  "1k to 10k", "10k to 100k", "100k to 1M", "> 1M" (FWC's convention; matches #18 tables).
- D10 Every per-month panel is pre-rendered (main map, thumbnail, band histogram, samples);
  the series is rendered once per metric with a CSS month line positioned by renderUI; no
  renderPlot per month, so a frame is one round trip (about 30-60 ms locally). Play uses
  Shiny's slider animate plus a small keyboard handler and a speed select. Preload is windowed
  (next 24, previous 6 months); a full walk is a site option, off by default.
- D11 Modules take (product, month) and key on yrmo, never the slider index; one shared month
  control over the union of months drives N products side by side later. Product =
  (bundle_id, layer_id); the registry can later generate one product per layer of a bundle.
- D12 Cache key = hash of (PLOT_VERSION, style, sizes); per-year invalidation by content md5 of
  the year's values, summary rows and samples; the key sits in the URL path (immutable URLs).
  The cache is gitignored by default (revisit with D1).
- D13 Dependencies of the app: shiny (brings bslib, htmltools, jsonlite); ragg optional (cairo
  fallback); testthat and png for tests; rsconnect only if a host needs it. No raster, terra,
  sf, viridis, ggplot2, leaflet in the app. DESCRIPTION yes (ten lines); renv deferred.
- D14 Schema versioning major.minor; Part 1 ships 1.0; reserved (not specified) in 1.0:
  dense encodings, per-layer style overrides, the viridis palette type. Samples optional in
  the schema (sample-derived columns NA when absent).

Answered by Holden (3 Nov 2026)
- D15 (Q1) The filtered FWC samples (181,411 rows, locations and counts since 1985) are
  redistributed in the public bundle, with attribution to FWC-FWRI. Panel D stays.
- D16 (Q2) Placeholder months (months after the last month with FWC samples; 2026-11 and
  2026-12 today) are HIDDEN in the viewer: the month control and the series end at last_data.
  The bundle still carries all 504 months (months.csv placeholder = TRUE marks them).
  PARKED NOTE (Holden): the Ecospace deliverables (out/<res>min/ecospace_ascii/ and the ST
  drivers export) should in future also stop carrying these future placeholder months; that is
  a pipeline change (the month axis written in make_redtide_ascii / the enyr handling), not
  part of #23. Open it as its own issue after Part 1.
- D17 (Q3) 5 arcmin only in #23. The stage writes out/<res>min/bundle/ for whatever cfg$res
  runs; a 15-arcmin bundle is one later run (the check script skips the #18 comparisons at 15).
- D18 (Q4) No deploy trial in Part 1: the app runs locally; step P7 does an rsconnect
  manifest dry run (rsconnect::writeManifest()) so the folder is known to be deployable.
  Return to D1 when a host is chosen.

Still open, none blocking Part 1
- Track the PNG cache in WFS-Portal or keep it gitignored: decided with the host (D1). An
  upload-style deploy carries the gitignored cache; a git-backed deploy needs a prerender on the
  host or a tracked cache (about 30 MB of binaries rewritten on every restyle).
- Attribution wording (section D) and the funding acknowledgment line: Holden confirms with
  FWC-FWRI and the USF Optical Oceanography Laboratory before any public deploy.
- Ecospace bundle volume and transport (plain git, Git LFS, or release assets), month range,
  units, precision and layer count: decided when the first Ecospace bundle is planned.
- Band label note: the issue text writes "<1k"; the check scripts and FWC's own classes are
  right-closed (1,000 falls in the first band), so the app labels it "<= 1k". Say so if you
  want left-closed bands instead (it changes counts only at exact band edges).

## Design summary

### A. The red tide bundle (schema 1.0), tracked at out/5min/bundle/ in RedTideMaps

```
out/5min/bundle/
  .gitattributes            "* text eol=lf"
  SCHEMA.md                 copy of docs/issue23_portal-bundle/bundle-schema.md (written LF)
  meta.json                 identity (bundle_id redtide_5min, product, product_name, res_arcmin),
                            grid header (ncols, nrows, xllcorner, yllcorner, cellsize, nodata, crs,
                            extent, n_cells, n_water, cell_order, template, atlantic_box),
                            months range (first, last, n, last_data), samples block (source, file,
                            date_from, date_to, n_rows), nearshore (rule, n_cells, km2), clipping
                            counts (incl. hull_flagged), source (repo, branch, ascii_dir,
                            ascii_commit = last commit touching ecospace_ascii, ascii_dirty =
                            porcelain scoped to it, ascii_md5 = md5 of the 504 ASCII md5 strings,
                            head_commit informational, schema_url), build (built_at, r_version,
                            raster_version, writer, run_log, mode pipeline | standalone, toggles:
                            update_modis, rebuild_nflh, fwc_refresh, fwc_force_full,
                            incremental_fit, fit_nb, export_ecospace, write_bundle), cfg
                            (map-determining keys only: res, styr, enyr, hull_*, viirs_nearshore,
                            modis_nearshore, use_viirs, use_modis), schema_version. No layers
                            array and no placeholder list here (layers.csv and months.csv own them)
  style.json                product facts only: units; palette recipe (anchors, bias, breaks,
                            above) + colors_hex[402]; bands (breaks, right_closed, columns,
                            sample_columns, labels); code vocabularies of use, fit_status,
                            viirs_status. No colors, sizes or labels for display: presentation is
                            the portal's (D6); this file changes only with a schema note
  grid.csv                  cell, row, col, lon, lat, water, km2 (required); depth_m, nearshore,
                            atlantic (optional); 5,148 rows in raster cell order
  months.csv                yrmo, year, month, index, label, placeholder (504 rows)
  layers.csv                id, name, units, encoding (long_sparse), file_pattern, summary_file,
                            total_column, fill, precision, description (1 row: redtide)
  values/redtide/<yyyy>.csv yrmo, cell, value: positive water cells per month (unquoted)
  summary/redtide.csv       one row per month (columns below)
  samples/fwc_<yyyy>.csv    year, month, cells, lon, lat, cell, water (rows of filtered_points_df
                            with a count, styr..enyr; sorted year, month, lat, lon, cells)
  ascii_md5.csv             yrmo, file, bytes, md5 (LF-normalized, fn.md5_lf) of each ASCII file:
                            the staleness guard tying the bundle to the maps beside it
  manifest.csv              file, bytes, md5 of every file above, .gitattributes included
                            (written last)
```

summary/redtide.csv columns: yrmo, year, month, use, hybrid_changed, n_changed (water cells
where the delivered map differs from the satellite clip it was built on, counted with the
relative tolerance abs(M - S) > 1e-9 * pmax(abs(S), 1): the ASCII text and the FLT4S stacks
differ by up to 5e-15 relative and exact inequality would count that noise in 15 of the 155
VIIRS months; 0 for viirs/modis/pred months; NA when the clipped stacks are not supplied),
hull_span_km (max_span_km of hull_diagnostics.csv), hull_flagged (flagged AND use == "pred", the
pipeline rule: 10 months today, not the 71 raw flags), fit_status
(fitted / failed / none), converged, viirs_status (positive / zero / missing / no_coverage),
n_samples, n_samples_water, n_samples_pos, s_le1k, s_1k_10k, s_10k_100k, s_100k_1M, s_gt1M,
samples_ge10k, in_ge10k, exposure (unrounded sum over water cells), n_pos, n_le1k, n_1k_10k,
n_10k_100k, n_100k_1M, n_gt1M, n_ge10k, km2_ge10k, n_ge100k, n_ge1M, max_cells, max_cell.
Definitions as clip_months_hybrid_issue18.R:257-270 and check_final_hybrid_issue18.R:204-242.

Size about 10 MB. A monthly update touches values/<current year>.csv (and the previous year
when late samples change a hull month), samples/fwc_<current year>.csv, the changed rows of
summary/redtide.csv and of ascii_md5.csv, months.csv only when last_data moves, meta.json,
manifest.csv. Numbers print as the shortest round-trip decimal (%.15g; %.17g where needed:
never for map values, in 3,432 grid centers and about half the sample coordinates, which keep
the pipeline's exact doubles because rounding to 6 decimals moves 33 samples across cell edges).

Future Ecospace products: one bundle per run (ecospace_<run>_5min) with the same grid.csv, its
own months.csv, one layers.csv row per species or fleet, values/<layer>/<yyyy>.csv, a generic
summary (yrmo, total, mean, n_pos, max_value, max_cell), no samples. Volume (dense layers) and
LFS/release assets are decided when the first Ecospace bundle is planned.

### B. Producer stage in RedTideMaps (new file scripts/write_bundle.R)

- fn.write_bundle(dir_ascii, file_depth, file_clipsrc, file_filtered, dir_out, cfg, res,
  repo_dir, file_schema, file_mask = NULL, file_unclip = NULL, file_fitmat = NULL,
  file_viirs_raw = NULL, file_viirs_clip = NULL, file_modis_clip = NULL, file_hulldiag = NULL,
  file_combined = NULL, mode = c("pipeline", "standalone"), product = "redtide",
  product_name = "Red Tide Maps", layer = "redtide", schema_version = "1.0")
  -> invisible(list(bundle_id, dir, n_months, n_placeholder, n_months_pos, n_samples,
  samples_to, n_files, bytes, ascii_commit, ascii_dirty, seconds, summary, manifest)).
- Helpers in the same file: fn.read_ascii_dir (scan skip = 6; v < -1e30 -> NA; header parsed
  and compared to the template; LF md5 per file), fn.band_counts, fn.layer_summary (pure,
  matrix in -> summary columns out; reused by the check script), fn.n_changed(M, S, tol = 1e-9),
  fn.samples_table (exact doubles), fn.fmt_num, fn.write_csv_lf (binary connection, eol "\n",
  quotes exactly the character columns; values files quote = FALSE), fn.write_json_lf,
  fn.write_text_lf (readLines + writeLines(sep = "\n") on a "wb" connection, for SCHEMA.md and
  .gitattributes; never file.copy, which would carry CRLF into the bundle), fn.md5_lf,
  fn.git_state (head_commit, branch, ascii_commit via git log -1 -- <dir>, ascii_dirty via git
  status --porcelain -- <dir>, through system2(Sys.which("git")); base-R fallback reading .git
  for head and branch; "unknown" on failure), fn.bundle_style, fn.bundle_manifest
  (list.files(all.files = TRUE)), fn.assert_no_cr.
- Writes to out/<res>min/bundle_tmp/ (stops if it exists and cannot be removed: unlink()
  returns 1 silently when a file is held open), runs the assertions and the read-back there,
  then swaps (bundle -> bundle_old, bundle_tmp -> bundle, bundle_old unlinked with its return
  value checked; a leftover bundle_old is reported and deleted by hand). A failure before the
  swap leaves the tracked folder untouched. Assertions: 12 * (enyr - styr + 1) ASCII
  files, contiguous, equal to clipping_source rows; NA set == template land; water values finite
  and >= 0; use in the five values; bands sum to n_pos; sample bands sum to n_samples_pos;
  all.equal to the combined stack when given; mask NA on land, 0/1 on water, none in the
  Atlantic box; after writing, every file read back and identical() to what was computed; no
  0x0D byte in any bundle file. Regression against the #18 tables is the check script's job.
- Hook in run_redtide_maps.R (edited on the branch, never during a run): header line 9;
  cfg$write_bundle = TRUE (after line 95); source line after 146; line 260 gains
  `nearshore <- NULL`; step 9 block between lines 346 and 347 (calls fn.write_bundle with
  paths$ecospace, paths$file_depth, clipping_source.csv, hab$file, paths$bundle, cfg, paths$res,
  cfg$repo_dir, the schema file, nearshore$file if non-NULL, pred_paths$file_log,
  fit_files$fit_matrix, viirs$file if use_viirs, clip_viirs$file / clip_modis$file if non-NULL,
  hull_diagnostics.csv, combined_path, mode = "pipeline") and rt_log's one summary line
  (months, placeholders, months with positives, samples and their end date, files, MB, the
  ASCII commit with a "modified, not yet committed" suffix when ascii_dirty, seconds).
- _setup.R: rt_paths() gains bundle = file.path(out_root, "bundle"); rt_init_dirs unchanged
  (the stage creates its own folder). config.local.example.R: `# cfg$write_bundle <- FALSE`
  block. .gitignore: `!out/*/bundle/` and `!out/*/bundle/**` after line 21.
- README: pipeline table row, first-run list item, monthly rerun step 3 (commit bundle/ too),
  configuration table row, outputs tree, a "Data bundle for WFS-Portal" section. docs/README.md
  row for issue23_portal-bundle/.
- Cost about 10 s on a 9-minute run (measured at step 2 and recorded in the #23 README).

### C. The #23 docs folder: docs/issue23_portal-bundle/

README.md (what changed, how to run, files, results, checks), issue23-portal-bundle-plan.md
(this plan's producer side), bundle-schema.md (schema 1.0 tables + changelog; source of
SCHEMA.md), check_bundle_issue23.R (stages frozen | rerun via RT_QA_STAGE; RT_QA_RES, default
5; at 15 the #18 comparisons are skipped with a message; RT_QA_BUNDLE_DIR), tables/
(bundle_vs_issue18_issue23.csv, bundle_vs_record_issue23.csv, bundle_rerun_issue23.csv,
bundle_files_issue23.csv), figures/ (fig1_bundle_quicklook_issue23.png: four months drawn from
the bundle with base image() only; fig2_summary_record_issue23.png: exposure and n_ge10k
1985-2026 from summary/redtide.csv), .gitignore (hoard/, issue23-*-comment.md), comments/.

check_bundle_issue23.R never sources the driver: it sources _setup.R and write_bundle.R, takes
cfg and res from the tracked meta.json (c(meta$cfg, meta$build$toggles)), builds its file list
from rt_paths() plus the newest *_filtered.Rdata (as clip_months_hybrid_issue18.R:89-112), and
refuses to run while out/<res>min/bundle_tmp/ or bundle_old/ exists.
Stage frozen: (1) gate on the 504 ASCII md5s == md5_refresh5_issue18.csv (else skip steps 4-5
with a message, run the rest, so the script survives the first monthly refresh); (2) file set ==
manifest (.gitattributes included), every md5 on disk and, for the tracked bundle, equal to
git show HEAD:<file> (the LF blob); no 0x0D byte in any file; ascii_md5.csv == fn.md5_lf() of
the ASCII on disk and meta$source$ascii_md5 == md5 of its strings (the staleness guard);
meta$grid == the template header; grid.csv (5,148 rows, water == template, km2 == area(),
centers == xyFromCell(), nearshore == the 189 cells of nearshore_set5_issue18.csv, none in the
Atlantic box); months.csv 504 contiguous, placeholders 202611 and 202612; (3) values rebuilt from
the year files identical() to scan()'s text of each ASCII (with the < -1e30 guard), and
isTRUE(all.equal()) to raster's GDAL float32 reading and to the normalized combined stack (the
#18 criterion; identical() is wrong there by construction: 162 months differ at the 16th
digit); row count == sum(n_pos); fn.layer_summary() from the ASCII == summary; (4) all 504
months vs clip_class_counts_hybrid_issue18.csv: n_pos and the five bands == final_* exactly,
|exposure - final_exposure| <= 1e-3 (measured max 1.2e-9), use, hybrid_changed, fit_status,
viirs_status equal, sat_src derived from use equal, n_changed == final_n_changed in every
month, sample bands == fwc_*; (5) vs record_months_issue18.csv in 502 months (202609, 202610
reported, not asserted); (6) sample rows identical() to the filtered rows with a count in
styr..enyr (181,411), per-month counts == n_samples; (7) frozen counts from an expected list,
quoted in the #23 README: 504 months, 173 all zero, 54,375 positive cell-months, use
155 / 0 / 123 / 0 / 226, hybrid_changed 210, converged TRUE 328 / FALSE 3 / NA 173,
hull_flagged TRUE exactly in 199009, 199604, 199606, 199711, 199909, 200009, 200010, 200110,
200112, 200201 (the log's Hulls list) and NA in 19 months, placeholder 2, the 2018-09 row;
figures (fig1: 2018-09, 2012-02, 2005-10, 2026-10 by base image() only; fig2: exposure and
n_ge10k 1985-2026) written byte-identically.
Stage rerun: fn.write_bundle(mode = "standalone") into hoard/rerun/ from the disk outputs with
the cfg of the tracked meta.json (or RT_QA_BUNDLE_DIR); every file byte-identical to the tracked
bundle except meta.json (build.built_at, build.run_log, build.mode, source.*) and manifest's
meta.json row; no 0x0D byte in either copy. A cfg change between production runs is a
legitimate meta.json difference, not what this stage tests.

### D. WFS-Portal repository (new, public, MIT, C:/Repos/WFS-FEM/WFS-Portal)

```
app.R                         shinyApp(app_ui(site, products), app_server(site, products))
DESCRIPTION                   Package: WFSPortal; Imports: shiny (>= 1.8); Suggests: ragg, testthat, png, rsconnect
README.md LICENSE ATTRIBUTION.md .gitignore .gitattributes WFS-Portal.Rproj
config/products.R             the registry: product_def(id, name, short, bundle, layer, source, panels, style_file, info)
config/redtide.R              preset: site <- list(title = "Red Tide Maps", products = "redtide", play_interval_ms = 200, speeds_ms = c(500, 200, 100), preload_all = FALSE)  (default)
config/portal.R               preset: site <- list(title = "WFS Portal", products = c("redtide"), ...)
config/active.example.R       copy to config/active.R (gitignored) to pick a preset locally
config/local.example.R        copy to config/local.R (gitignored): redtidemaps_dir <- "C:/Repos/WFS-FEM/RedTideMaps"
config/style/redtide.json     THE one style file: overrides merged over the bundle's style.json + all presentation keys
R/packages.R bundle_read.R (read_bundle, read_layer, expand_to_grid, verify_bundle)
R/product.R (product_def, products_from_bundle, make_product, validate_product, viewer_months, union_months)
R/style.R (style_from_bundle, merge_style, palette_of, style_hash, fmt_n, fmt_big) geometry.R summary.R
R/plot_map.R plot_series.R plot_bands.R plot_samples.R plot_dashboard.R cache.R
R/mod_month.R mod_map.R mod_thumbs.R mod_series.R mod_bands.R mod_samples.R mod_info.R mod_product.R
R/app_ui.R app_server.R about.R
data/redtide_5min/            the fetched bundle (tracked) + FETCH.json
cache/                        gitignored: cache/<bundle_id>/<key8>/{main,thumb,hist,samples}/<yrmo>.png, series_<metric>.png, series_geometry.json, manifest.csv, cache_info.json
www/keys.js preload.js portal.css
scripts/fetch_bundle.R prerender.R render_dashboard.R check_packages.R  (later: update.R)
tests/testthat/ helper-source.R test-*.R fixtures/mini_bundle/ (generated by fixtures/make_mini_bundle.R)
docs/issue1_part1-visualization/  README.md, issue1-part1-visualization-plan.md, figures/ (the static dashboard PNGs), checklist.md
                              (the manual checklist with results), comments/, .gitignore (hoard/, issue1-*-comment.md): the
                              RedTideMaps docs convention mirrored, minus a check script (the tests live in tests/testthat)
```

Preset order in app.R: env var WFS_PORTAL_CONFIG, else config/active.R, else config/redtide.R.
A plain clone runs as the standalone "Red Tide Maps"; the portal is one line. One UI builder:
bslib::page_navbar(title = site$title) with one nav_panel per enabled product plus About; one
product -> no product tabs. Attribution (About panel + footer): RedTideMaps pipeline (Chagaris,
Vilas, Harris; MIT) on the WFS Ecospace grid (Vilas et al. 2023), project PI David Chagaris
(UF); FWC-FWRI HAB Monitoring Database; USF Optical Oceanography Lab (PI Chuanmin Hu), NOAA
VIIRS and NASA MODIS; sdmTMB; model products, not observations. Holden confirms wording.

### E. Product contract and modules

read_bundle(dir) -> list(id, dir, meta, grid, cells, months, layers, samples | NULL, style,
fetched). read_layer(bundle, layer_id) -> list(values = n_cells x n_months matrix (NA on land,
0 fill, colnames yrmo), summary); dispatches on encoding (long_sparse only in Part 1), asserts
every cell is water and no (yrmo, cell) repeats. make_product(def, bundle) -> the object every
module consumes: id, name, short, bundle_id, layer, grid, cells, months, values, summary,
samples, viewer_months (months$yrmo[!placeholder], D16; the one function to change if
placeholders are ever shown), style (style_from_bundle for the bundle facts + merge_style with
the product's style file, which holds every presentation key and may override a fact for
display), panels, units,
total_column, info (function(row, product) -> character), geometry (map_geometry: xs, ys, xlim,
ylim, asp, land_z, ncols, nrows), palette (palette_of: colors[402], breaks_img[403] with Inf ->
1e12), cache dir, source (for the footer). validate_product(): schema major 1; dims; months
contiguous; referenced style columns exist; rowSums(bands) == n_pos; manifest md5s on disk.

Modules (mod_<x>_ui / mod_<x>_server(id, product, month); month = list(yrmo, index) reactives):
- mod_month(id, months, site): sliderInput over the viewer months with animate(interval =
  input$speed, loop = TRUE), rebuilt by renderUI at the current index when the speed select
  changes (site$speeds_ms 500 / 200 / 100 ms, labels slow / normal / fast, default
  site$play_interval_ms), first/prev/next/last buttons, keyboard (ArrowLeft/Right, Home, End,
  Space via www/keys.js), the month label. Returns list(yrmo, index).
- mod_map: renderUI(tags$img(src = cache_url(product, "main", yrmo))). mod_thumbs: prev and
  next thumb PNGs, placeholder at the ends. mod_bands: hist/<yrmo>.png (y axis fixed record-wide
  by default; decided at the P3 aesthetics checkpoint). mod_samples: samples/<yrmo>.png (zero
  dots, class points, count box, class legend); hidden when samples is NULL. mod_series: the
  once-rendered series_<metric>.png in a position: relative div with a .month-line div whose
  left % comes from series_geometry.json; metric select. mod_info: definition list from
  product$info(row): month; method (labels$use[use], "+ N cells changed by the nearshore hull
  fill" when hybrid_changed, "hull footprint spans N km (flagged)" only when hull_flagged); fit
  status / convergence; samples (n, positives, >= 10k and how many the map includes); exposure
  first (fmt_big + full number in a title attribute); positives; five bands; cells >= 10k and
  km2; maximum and its cell lon/lat (no placeholder notice: those months are not offered, D16;
  the footer's "FWC samples through <date>" says where the data ends). mod_product composes the
  panels of product$panels and sends the windowed preload message (next 24, previous 6; the
  full walk only when site$preload_all, FALSE in both tracked presets).
- app_server: one mod_month over union_months(products), then mod_product per product in
  layout_columns; Part 1 has one product.

Layout (bslib): navbar; month control row; layout_columns(col_widths = c(8, 4), card(A map),
column(card(C bands), card(D samples), layout_columns(c(6,6), card(E prev), card(F next)),
card(key information))); card(B series) full width below; footer with data provenance.

### F. Pre-render and cache

scripts/prerender.R <product_id> [--force] [--prune]: key8 = style_hash(PLOT_VERSION, style,
sizes); renders placeholders once, series_<metric>.png + geometry once per metric (x axis over
the viewer months), then the viewer months of every year whose content md5 changed (placeholder
months skipped): main (1200 x 1000 @150, ~29 KB), thumb (320 x 270 @96), hist (600 x 400 @120),
samples (800 x 670 @120); ragg::agg_png if installed else png(type = "cairo"); temp file then
rename. About 150 ms per month: 502 viewer months in 1.5-3 min; a monthly update 2-5 s.
ensure_cache() at app start; a missing month renders lazily on first use (never breaks a deploy).
Plot functions lifted from clip_months_hybrid_issue18.R with globals turned into arguments:
to_z(v, ncols, nrows); map_geometry(grid, cells); band_counts(v, breaks); exposure_of(v, water);
map_info_lines(row, style); draw_colorbar(palette, cb, xlim, ylim, cex); draw_map(v, geometry,
palette, style, main, info, pts, cbar, placeholder, ...) (outline/used arguments dropped);
draw_sample_points, draw_sample_legend; draw_samples(pts, geometry, style, main); draw_bands(row,
style, ymax, main); draw_series(summary, style, metric, months) -> series_geometry (era shading
by use, placeholder shading, January ticks by year, minor month ticks); draw_dashboard(product,
yrmo) (layout() of A-F + info on one device: the static test product and the Part 2 export);
render_png(file, w, h, res, expr). PLOT_VERSION bumped on any visual change.

### G. Fetch and monthly update

scripts/fetch_bundle.R <bundle_id> [--commit <sha>] [--github] [--allow-dirty]: local mode
copies from redtidemaps_dir (refuses a dirty out/<res>min/bundle unless --allow-dirty, which
records <sha>-dirty; asserts meta.source.ascii_commit is an ancestor of the clone's HEAD via
git merge-base --is-ancestor; recomputes the LF md5s of the clone's ecospace_ascii and refuses
when they differ from ascii_md5.csv); GitHub mode takes --commit <sha> (the documented
reproducible path) or resolves the branch head with one API call and prints it, then downloads
manifest-first from raw URLs (about 96 files; the ASCII md5 check is skipped there, the pinned
commit stands for it); verifies md5s (CRLF-normalization fallback with a warning), checks schema
major 1, replaces data/<bundle_id>/ by a rename-aside (Windows cannot rename onto an existing
directory), writes FETCH.json (bundle_id, source_repo, source_path, commit, mode, fetched_at,
n_files, bytes, md5_ok, ascii_commit, ascii_md5_checked, previous_commit), prints what changed. Commit message: `data: redtide_5min from RedTideMaps@<sha7> (FWC samples through <date>)`.
Monthly update: (1) RedTideMaps run, read the log's Hulls and Bundle lines, commit data:
(ecospace_ascii, plots, bundle), push; (2) WFS-Portal fetch, prerender, test_dir, commit data:,
push; (3) deploy (host-specific, the only such step). scripts/update.R wraps 2 (+3) later.
Footer: `Data: RedTideMaps @ <FETCH commit 7> (fetched <date>) . maps built <date> . FWC samples
through <date> . schema 1.0 . render <key8>`, linked to the bundle tree at that commit.

### H. Tests

RedTideMaps: check_bundle_issue23.R (section C). WFS-Portal tests/testthat (Rscript -e
'testthat::test_dir("tests/testthat")'); the fixture mini_bundle/ (6 x 5 grid, 3 months: one
all zero, one placeholder, one with samples) is generated by fixtures/make_mini_bundle.R and
tracked; test-bundle_read asserts its manifest matches its files, so a hand edit without
regeneration fails. Files: test-bundle_read (fixture + the real bundle when present: 5,148 x
504, NA exactly on 1,310 land cells, 2018-09 exposure within 1e-6, bands recomputed ==
summary), test-product (viewer_months drops the placeholder month; products_from_bundle on a
two-layer toy bundle gives two products; validate_product requires only the required grid
columns), test-summary (band_counts on c(NA,0,500,1e3,1e4,10001,1e5,1e6,2e6) -> n_pos 7, bands
2,1,2,1,1; exposure ignores land; map_info_lines exposure first; fmt_n; fmt_big),
test-geometry, test-plot (draw_* into render_png for a normal, an all-zero and a placeholder
month: file size and pixel size; draw_samples with and without samples), test-style (merge,
facts from the bundle and presentation from the portal file, hash stability), test-cache
(prerender on the fixture writes the four panels per viewer month and none for the
placeholder; second run renders nothing; one changed row re-renders that year; lazy render),
test-mod_month and test-mod_product (shiny::testServer; a speed change keeps the index; no
hull line for a satellite month), test-fetch (verify passes, fails on a tampered file, passes
after CRLF normalization with a warning). No screenshot tests.
Manual checklist (docs/issue1_part1-visualization/checklist.md): start < 3 s warm; slider end
to end; a year of play at 200 ms with no dropped frame and no XHR per frame, and the speed
select changes the interval; keys; thumbnails show the placeholder at 1985-01 and at the last
data month; the control and the series end at 2026-10 (2026-11 and 2026-12 not offered); the
2018-09 box == the #18 row (310.5M cells/L = 310,492,554, 648 positives, 0/0/127/450/71, 648
cells >= 10k over 49,160 km2, max 7,746,619, VIIRS + hulls nearshore, 32 cells changed, no
hull-flag line, 525 positive of 1,026 samples, 290 >= 10k with 289 inside the map); the 2018-11
box (exposure 514,537,038; 867 positives: 0 / 5 / 221 / 543 / 98; 862 cells >= 10k over 65,075
km2; max 10,097,242; 45 changed; 782 samples, 500 positive; 294 >= 10k, all inside the map);
2022-12 shows MODIS + hulls nearshore and VIIRS tif missing; 1985-01 shows no samples and an
empty map; 1990-09 (hull-served, flagged) shows hulls (no satellite coverage) and the hull-flag
line; metric select keeps the line at the month; resize; footer; the portal preset changes the
title to WFS Portal, the default shows Red Tide Maps with no product tabs.

## Step list with checkpoints

Holden works piecemeal: each checkpoint shows the evidence and the full diff of every commit
it names before any of them is made, and each commit is approved separately (labels E1/E2,
G1-G3, H1/H2, J1/J2, M1/M2 below). Local commands use
"C:/Program Files/R/R-4.5.1/bin/x64/Rscript.exe" (READMEs keep the generic `Rscript`).
Never edit run_redtide_maps.R or a sourced script while a run is in progress.

RedTideMaps, issue #23, branch 23-portal-bundle from the fresh main (4fee1c9), draft PR
"Data bundle for WFS-Portal (closes #23)":
0. git fetch --prune; checkout main; merge --ff-only origin/main; branch; draft PR after the
   first commit; gh issue close 22 as a duplicate (Holden's go-ahead; command handed over if
   the classifier denies).
1. docs: the folder skeleton (plan, README skeleton, .gitignore, bundle-schema.md v1.0,
   docs/README.md row). Checkpoint A: Holden approves column names, k/M labels, the layout.
2. feat: scripts/write_bundle.R + paths$bundle in _setup.R; the stage run standalone from the
   R console against the run on disk into docs/issue23_portal-bundle/hoard/trial/ (no pipeline
   run). Checkpoint B: file list with sizes, head() of each table, the 2018-09 row beside the
   #18 row, the assertion log, the timing.
3. config: the hook (header, cfg, source line, nearshore <- NULL, step 9), config.local.example.R,
   .gitignore exceptions. Checkpoint C: parse() passes; the diff.
4. test: check_bundle_issue23.R stage frozen against hoard/trial/, its tables and figures.
   Checkpoint D: bundle_vs_issue18 all 504 equal; the record table with 202609/202610 reported;
   fig1 and fig2 previewed.
5. Verification run with cfg$fwc_refresh <- FALSE in config.local.R (about 9 min, nothing
   edited meanwhile); stage rerun with RT_QA_BUNDLE_DIR=out/5min/bundle against hoard/trial/.
   Checkpoint E: the log's Step 9 and Bundle lines with seconds and "ASCII commit 543bc8e"
   without the modified suffix; git status shows ecospace_ascii unchanged, out/5min/bundle new,
   the plots PDFs changed by date lines only (restored before the commit); rerun table all equal
   except the volatile keys. Commit data: (E1; message `data: bundle redtide_5min schema 1.0
   (ASCII at 543bc8e, FWC samples through 2026-10-21)`), then qa: (E2; tables, figures).
6. docs: README sections, docs/README.md, the #23 README results; PR ready; Holden merges;
   the three WFS-Portal issues opened and linked from #23; memory updated.

WFS-Portal, issue #1 "Part 1: visualization tool" (issues #2 "Part 2: exports" and #3
"Part 3: data portal" opened and parked with the issue text's wording), branch 1-part1-viz:
P0. Holden creates WFS-FEM/WFS-Portal (public, MIT, empty README), clones to
    C:/Repos/WFS-FEM/WFS-Portal, adds it as a working directory for Claude Code.
P1. skeleton (README, LICENSE, ATTRIBUTION.md, DESCRIPTION, .gitignore, .gitattributes,
    config/*, R/packages.R, scripts/check_packages.R, scripts/fetch_bundle.R local mode, the
    docs/issue1_part1-visualization/ folder with README, plan and .gitignore) and the fetched
    bundle. Checkpoint G: FETCH.json, git status of data/, the md5 and ASCII-md5 verification
    lines. Commits docs: (G1), feat: (G2), data: (G3).
P2. the contract (bundle_read, product, style, geometry, summary), the registry, the style
    file, fixtures/make_mini_bundle.R and its output, test-bundle_read, test-product,
    test-summary, test-geometry, test-style. Checkpoint H: test_dir output; the printed product
    (dims, viewer months, memory, load time); the 2018-09 summary row. Commits feat: (H1),
    test: (H2).
P3. feat: the plot functions and scripts/render_dashboard.R; static dashboard PNGs (A to F plus
    the info box on one page) for 2018-09, 2018-11, 2012-02, 2005-10, 2022-12, 1990-09
    (hull-served, flagged), 1985-01 (empty) and 2026-10 (the last data month), tracked in
    docs/issue1_part1-visualization/figures/. Checkpoint I: Holden judges the palette, the wheat
    land, the count box order, the k/M labels, the series ticks and shading, the histogram axis
    (fixed record-wide or per month), panel D (zero dots, class points, count box, class legend
    position and size); iterate the style file until approved. No Shiny code before this is
    approved.
P4. cache.R, scripts/prerender.R, test-cache, test-plot. Checkpoint J: the timing and size
    report (cache_info.json), three sampled PNGs per panel type, a second run rendering
    nothing. Commits feat: (J1), test: (J2).
P5. feat: app.R, app_ui, app_server, mod_month, mod_map, mod_thumbs, keys.js, preload.js,
    portal.css (map and month control only). Checkpoint K: Holden scrolls and plays locally;
    flush time printed.
P6. feat:/test: mod_bands, mod_samples, mod_series, mod_info, mod_product, about.R, the module
    tests; one commit per panel. Checkpoint L: the full layout; the manual checklist ticked in
    checklist.md with the 2018-09, 2018-11 and 1990-09 numbers.
P7. docs:/config: both presets exercised, README, scripts/update.R skeleton; rsconnect
    manifest dry run (no deploy, D18). Checkpoint M: both titles; the manifest resolves; the
    footer shows the fetched commit, build date and FWC date.

## Automation and parked issues

The pipeline is not unattended today: VIIRS tifs arrive by hand (stack ends 2024-12), MODIS
polygons refresh only with update_modis = TRUE, the two data: commits and the deploy are manual.
Part 1 changes none of that; the bundle stage and scripts/update.R make the chain scriptable.
Parked (opened after Part 1, not in #23): "Schedule the monthly run" (Task Scheduler on
Holden's machine vs a GitHub Action running the cold pipeline, about 20 min; which steps stay
manual), "Stop writing future placeholder months to the Ecospace deliverables" (D16: the ASCII
drop and the ST drivers export end at the last month with samples; a make_redtide_ascii /
enyr change with its own check), "Part 2 exports" (PNG/JPG/TIFF single month or range via draw_dashboard/draw_map at
export size; 12-months-per-page PDF with par(mfrow = c(4, 3)); GIF from the cached main PNGs
via gifski or magick; the zip package for ranges), "Part 3 data portal" (time range and
bounding box inputs; CSV long export, ESRI ASCII export in base R, GeoTIFF via terra inside a
download handler only; always exclude the Atlantic box), "15-arcmin product"
(one cfg$res <- 15L run), "Ecospace bundles" (volume: plain git vs LFS vs release assets; month
range, units, precision, layer count). Not built in Part 1: download handlers, map clicks,
dense encodings, a layer selector, leaflet, a client-side month controller, auth, renv.

## Verification (end to end)

1. RedTideMaps: stage frozen of check_bundle_issue23.R passes against hoard/trial/ and again
   against out/5min/bundle/ after the verification run; stage rerun byte-identical; the
   deliverables (ecospace_ascii) unchanged by the run; parse() of the driver; a second
   verification run reproduces the bundle.
2. WFS-Portal: test_dir green; prerender timing recorded; the app runs locally under both
   presets; the manual checklist ticked; the 2018-09 and 2018-11 boxes equal the #18 rows.
3. Round trip: fetch_bundle.R in GitHub mode against the merged main reproduces the local copy
   byte for byte (md5_ok TRUE).

## Critical files

- C:\Repos\WFS-FEM\RedTideMaps\run_redtide_maps.R (cfg 42-96, sources 140-146, line 260, the
  step-9 slot between 346 and 347)
- C:\Repos\WFS-FEM\RedTideMaps\scripts\_setup.R (rt_paths 86-139, rt_init_dirs 142-151,
  rt_check_packages 17-24)
- C:\Repos\WFS-FEM\RedTideMaps\scripts\polygon_clipping_rt.R (make_redtide_ascii 241-326; the
  palette 339-343; the 4 x 3 PDF layout 347-362)
- C:\Repos\WFS-FEM\RedTideMaps\docs\issue5_nearshore-hybrid-summary\subissues\issue18_implement-hybrid-clipping\clip_months_hybrid_issue18.R
  (readers and status rules 124-193; ASCII guard 208; md5 gate 199-204; counts and exposure
  257-270; panel functions 248, 323-332, 365-405; refreshed-month exemption 68, 306-309)
- ...\issue18_implement-hybrid-clipping\check_final_hybrid_issue18.R (load_samples, samples_of,
  expo_of 204-242) and tables/ (clip_class_counts_hybrid_issue18.csv, record_months_issue18.csv,
  nearshore_set5_issue18.csv, md5_refresh5_issue18.csv)
- docs/issue5_nearshore-hybrid-summary/plot_summary_issue5.R (series axes and era shading)
- New: scripts/write_bundle.R; docs/issue23_portal-bundle/{README.md, issue23-portal-bundle-plan.md,
  bundle-schema.md, check_bundle_issue23.R}; the WFS-Portal tree of section D.

## Appendix: full design document (reference)

What follows is the revised design document produced by the design workflow on 3-4 Nov 2026
(three independent designs, three judges, synthesis, three critics, revision; repo claims
verified by read-only R and git checks). The plan above is the executable summary and wins
where the two differ. Step 1 copies this document into docs/issue23_portal-bundle/ as the
issue plan; step P1 copies its portal sections into docs/issue1_part1-visualization/.

---

# Issue #23 design (revised synthesis): the red tide bundle, the producer stage in RedTideMaps, and WFS-Portal Part 1

Status: revision of the 3 Nov 2026 synthesis after the critique, 4 Nov 2026. Decisions D1 to D4 of `C:\Users\User\.claude\plans\cozy-conjuring-raven.md` are fixed; the plan's design decisions D5 to D14 and Holden's answers D15 to D18 (samples redistributed; placeholder months hidden in the viewer; 5 arcmin only; no deploy trial in Part 1) are applied here. Paths are absolute to `C:\Repos\WFS-FEM\RedTideMaps` (RedTideMaps); WFS-Portal will be cloned at `C:\Repos\WFS-FEM\WFS-Portal` and does not exist yet. Local commands use `"C:/Program Files/R/R-4.5.1/bin/x64/Rscript.exe"` (Rscript is not on PATH on this machine; the READMEs keep the generic `Rscript`).

Answer to the request: a new repository (WFS-Portal) does make the later integrated Shiny application easier, but what does the work is the contract, not the split. RedTideMaps writes a tracked, data-only, layer-based bundle; the portal loads it through one product contract, and every module takes (product, month) and nothing else. An Ecospace run then becomes one bundle with one layer per species or fleet on the same grid, and side-by-side maps are the same modules under one shared month control.

Facts verified in this session (3 and 4 Nov 2026), which the design rests on:

- Repo: local checkout on `5-subissue-folders` at `2311468`; remote `main` is `4fee1c9` (the local `origin/main` ref `6a734ea` is stale, so #23 starts with `git fetch --prune` and a fast-forward of `main`). `core.autocrlf = true` in the system gitconfig, no `.gitattributes`. R writes CRLF here: `out/5min/clipped/clipping_source.csv`, which git never touched, holds 505 CR bytes (one per line); the tracked tables and ASCII files are `i/lf w/crlf`. `Sys.which("git")` resolves (`C:\PROGRA~1\Git\ucrt64\bin\git.exe`); `capabilities("cairo")` is TRUE. Installed: shiny 1.12.0, bslib 0.9.0, htmltools 0.5.8.1, jsonlite 2.0.0, ragg 1.5.0, testthat 3.3.1, png 0.1-8, magick 2.9.1, gifski, rsconnect 1.8.0, viridisLite, digest.
- Data: `scan()` reads the 504 ASCII files in 0.35 s; every file's NA set equals the 1,310 land cells of the template; the ASCII text carries at most 15 significant digits and `sprintf("%.15g")` round-trips all 54,375 positive values parsed from it. `raster::raster(<asc>)` reads the file through GDAL (`r@file@driver == "gdal"`, `dataType FLT4S`), so `raster::values()` returns float32-rounded numbers that differ from the parsed text in 162 of 504 months (1985-09: 6 cells, e.g. cell 2157 text `3585.32055664062`, raster `3585.320556640625`; `all.equal()` TRUE in every month). The combined `.grd` stack is FLT4S too: `identical()` to the text in 342 months, `all.equal()` in all 504 (maximum relative difference 5.0e-15; 8,000 cells differ in those 162 months). 173 months are all zero; the largest years by positive cell-months are 2005 (5,362), 2003 (3,997) and 2018 (3,502); the sparse long text of every positive cell-month at `%.15g` is 1,431,062 bytes. No cell is exactly 10,000. ASCII header keys `NCOLS, NROWS, XLLCORNER, YLLCORNER, CELLSIZE, NODATA_value` with `CELLSIZE 0.0833333333333333` and `NODATA_value -3.4e+38` at both resolutions (the 15-arcmin product is 26 x 22; `-9999` is the NODATA of the depth templates only); the first NODATA token of every file is printed as a 39-digit decimal.
- Samples: the filtered file (`FWC HAB data 19800102-20261021_filtered.Rdata`) holds 183,402 rows (`year, month, cells, lon, lat`), 181,411 from 1985 on with a count, no NA counts, 39,928 positives, none in the Atlantic box, 93 off-grid, 44,430 on land cells of the template (bay and estuary stations), 485 months with samples since 1985; 1,026 samples in 2018-09 and 782 in 2018-11. The source coordinates are 6-decimal values, but the pipeline's parser stored about half of them one ulp away from the nearest double (`-82.280500000000004`, `26.816166999999997`): `%.15g` fails to round-trip 15,962 lon and 75,731 lat values, `%.17g` round-trips all. Rounding to 6 decimals would restore short text but moves 33 samples that sit exactly on quarter-degree cell edges into the neighboring cell (measured with `cellFromXY`), which would break the equality of `samples_ge10k` and `in_ge10k` with the #18 tables; the bundle therefore keeps the exact doubles.
- Hull flags: `out/5min/sdm/hull_diagnostics.csv` (columns `yrmo, n_pos, n_locations, n_clusters, cluster_sizes, n_polys, total_area_km2, max_area_km2, max_span_km, flagged`, 485 rows) has `flagged` TRUE in 71 months: 43 `hybrid`, 18 `hybrid_modis`, 10 `pred`. The pipeline reports only the hull-served ones (`run_redtide_maps.R:321-338`, README line 65): 199009, 199604, 199606, 199711, 199909, 200009, 200010, 200110, 200112, 200201.
- 2018-09 recomputed from the ASCII: exposure 310,492,554.245117, 648 positives, bands 0 / 0 / 127 / 450 / 71, 648 cells >= 10k over 49,160 km2, maximum 7,746,619 cells/L at cell 2864, 32 cells changed, 525 positive samples of 1,026 (54 / 105 / 132 / 158 / 76), 290 samples >= 10k with 289 inside the map: equal to the #18 rows. 2018-11 (#18 rows): exposure 514,537,037.834229, 867 positives, bands 0 / 5 / 221 / 543 / 98, 862 cells >= 10k over 65,075 km2, maximum 10,097,242, 45 cells changed, 782 samples with 500 positive (52 / 61 / 100 / 170 / 117), 294 samples >= 10k, all 294 inside the map. `record_months_issue18.csv` carries zeros for 202609 and 202610 (it predates the refresh) while `clip_class_counts_hybrid_issue18.csv` has 21 and 23 positives there: those two months are exempt from the record comparison, as `clip_months_hybrid_issue18.R:68, 306-309` does.
- The refresh commit `543bc8e` changed 12 files: four ASCII files (two per resolution) and the tracked plots (the PDFs by their date lines); `fn.plot_sdmTMB()` (`run_redtide_maps.R:198-200`) and `fn.plot_redtide_stack()` (line 319) run before the step-9 slot (line 346), so the working tree is never clean when the bundle is written.
- `RT_fit_matrix.RData`: columns `year, month, model, RRMSE, MAE, aic, aicc, nll, convergence`; model `fit_sdmTMBlog` in 336 rows, NA in 168; convergence TRUE 328, FALSE 3, "no model" 173.

---

## 1. Red tide bundle schema (schema 1.0)

### 1.1 Location, identity, tracking

- Folder: `out/<res>min/bundle/` in RedTideMaps, `out/5min/bundle/` for the 5-arcmin product, beside `ecospace_ascii/` in the `out/<res>min` tree of `rt_paths()` (`scripts/_setup.R:93-138`). Tracked through two new `.gitignore` exceptions after line 21 (`!out/*/plots/**`), the pattern used for `ecospace_ascii/` and `plots/` (lines 16-21): `!out/*/bundle/` and `!out/*/bundle/**`. The bundle holds no PNG or PDF.
- Identity: `bundle_id = <product>_<res>min` (`redtide_5min`; a 15-arcmin run would write `redtide_15min` to `out/15min/bundle/`, D17: not in #23). The resolution is encoded by the parent folder and repeated in `meta.json` (`res_arcmin`, `bundle_id`, `product`); no file name inside the bundle carries the id, so the folder is copied as a unit. WFS-Portal keeps the fetched copy under `data/<bundle_id>/`.
- A portal product is a `(bundle_id, layer_id)` pair, always (D11). The red tide bundle has one layer, `redtide`. The registry can later generate one product per layer of a bundle (`products_from_bundle()`, section 3.1), so the product chooser is the layer selector and a side-by-side view is N products under one month control; there is no separate layer `selectInput` design.
- Layer-based from day one: a bundle is one grid plus N layers. The one extra folder level costs nothing in Part 1 and is what lets an Ecospace run with 50 species be one bundle (1.5).

### 1.2 Layout

```
out/5min/bundle/
  .gitattributes                 one line: "* text eol=lf" (LF in the index and in every checkout, including WFS-Portal's copy); written by fn.write_text_lf()
  SCHEMA.md                      docs/issue23_portal-bundle/bundle-schema.md re-written LF by fn.write_text_lf() (the data travels with its description)
  meta.json                      identity, grid header, month range, samples, nearshore, clipping, source (ASCII provenance), build, cfg
  style.json                     product facts only: units, the pipeline palette recipe + hex colors, band breaks/columns/labels, the use codes
  grid.csv                       one row per template cell (5,148)
  months.csv                     one row per month (504); the only place the placeholder flag lives
  layers.csv                     one row per layer (1); the only place the layer definitions live
  values/redtide/1985.csv ...    one file per year, long sparse: the positive water cells of each month
  summary/redtide.csv            one row per month: the monthly summary (1.4)
  samples/fwc_1985.csv ...       one file per year: the filtered FWC samples of the product months (D15: redistributed)
  ascii_md5.csv                  one row per ASCII file: the LF md5 of the map the bundle encodes (staleness guard)
  manifest.csv                   file, bytes, md5 of every file above, .gitattributes included (written last)
```

Size at 5 arcmin: values 1.43 MB in total (54,375 rows; 2005 is the largest year at about 140 KB; a year with no positive cell gets a header-only file); samples about 7 to 8 MB in total (measured 6.9 MB at 15 digits, the largest year 2021 at about 405 KB; the 17-digit coordinates of about half the rows add about 10 percent; every per-year file stays under 500 KB, so GitHub renders its diff); `grid.csv` about 350 KB; `ascii_md5.csv` about 35 KB; everything else under 200 KB. About 10 MB, comparable to the 10.6 MB of ASCII it describes. A monthly update changes `values/redtide/<current year>.csv` (and the previous year's when late samples change a hull month), `samples/fwc_<current year>.csv`, the changed rows of `summary/redtide.csv`, the changed rows of `ascii_md5.csv`, `months.csv` only when `last_data` moves, `meta.json` and `manifest.csv`: about seven files and a few hundred diff lines.

### 1.3 File formats and why

- CSV for tables, JSON for metadata. `read.csv()` is base R; `jsonlite` is already loaded by the pipeline (`scripts/_setup.R:31, 72`) and is an import of `shiny`, so neither side gains a package. Text is what git delta-compresses and what a PR shows. Rejected: RDS (binary, R-only, opaque PR diffs, a full new blob per change; the right format only for the portal's own cache); the ASCII files alone (10.6 MB, land as NODATA strings, the first-token quirk, no summary, no schema); wide per-year rows of 3,838 columns (one changed month is one unreadable 3,838-value line); feather, parquet, fst, qs (a package on both sides; `arrow` is absent from webR).
- Values are long sparse, three columns `yrmo, cell, value`, positive water cells only: 1.43 MB against 3 to 4 MB wide, and a changed month is a few changed rows.
- Which reading of the ASCII the bundle reproduces: the text. The bundle values are `identical()` to `scan()`'s parse of the ASCII (15 significant digits). GDAL-based readers (raster, terra, QGIS) and Ecospace see the same files as float32 and differ from the text at the 16th significant digit in 162 months, as the FLT4S combined stack does; comparisons against those readers use `isTRUE(all.equal())` (the #18 criterion, `clip_months_hybrid_issue18.R:209`), never `identical()`. `SCHEMA.md` states this, with the tolerance rules of the derived columns (`n_changed`: relative 1e-9; exposure: absolute 1e-3, the measured maximum text-versus-stack difference being 1.2e-9 cells/L).
- Line endings are LF everywhere: every file is written through a binary (`"wb"`) connection with `eol = "\n"`: tables by `fn.write_csv_lf()`, JSON by `fn.write_json_lf()`, `SCHEMA.md` and `.gitattributes` by `fn.write_text_lf()` (`readLines()` then `writeLines(sep = "\n")`; never `file.copy()`, which would carry the CRLF of a re-checked-out working tree into the bundle and its md5 into the manifest). After writing, the stage asserts that no bundle file contains a 0x0D byte. The folder's `.gitattributes` pins LF at checkout, so a local copy, a fresh clone and a GitHub raw download are byte-identical and the md5 manifest holds everywhere.
- Number formatting, one rule for every double column: `fn.fmt_num(x)` prints `sprintf("%.15g", x)` and, for any value that does not survive `as.numeric()` of that text, falls back to `sprintf("%.17g", x)` (17 digits round-trip every double). Map values never need the fallback (verified: all 54,375), so the bundle text equals the ASCII digits. Cell centers in `grid.csv` (`xllcorner + (col - 0.5) / 12`) need 17 digits in 3,432 of 5,148 cells, and the sample coordinates need them in about half the rows (the ulp noise described in the facts): correct, slightly noisy, and stated in `SCHEMA.md`; rounding was rejected because it moves 33 samples across quarter-degree cell edges. Integers print as integers, logicals as `TRUE`/`FALSE`, `NA` for missing; `yrmo` is a six-character string read back with `colClasses = c(yrmo = "character")` as every repo script does (`plot_summary_issue5.R:29`).
- Quoting: `fn.write_csv_lf()` quotes exactly the genuine character columns (`quote = which(vapply(df, is.character, TRUE))`, computed before the doubles are turned into formatted strings), so numbers are never quoted and `layers.csv$name`, which contains a comma, is. The values files are written with `quote = FALSE` (no field can contain a comma or a quote). The read-back assertion (2.4) checks both.
- JSON via `jsonlite::toJSON(x, auto_unbox = TRUE, pretty = TRUE, digits = NA)` (verified: `digits = NA` prints `0.0833333333333333` for 1/12, the ASCII header text) written by `fn.write_json_lf()`.
- Sorting is deterministic (months ascending; values by `yrmo, cell`; samples by `year, month, lat, lon, cells`; cells by id; `ascii_md5.csv` by month), so a rerun with the same inputs is byte-identical except the volatile keys of `meta.json` (`build.built_at`, `build.run_log`, `source.*`) and the `meta.json` row of `manifest.csv`.

### 1.4 Exact contents and column names

**meta.json** (keys and values for the 5-arcmin bundle; written before `manifest.csv`; the layer definitions live in `layers.csv` and the placeholder flag in `months.csv`, not here):

```json
{
  "schema_version": "1.0",
  "bundle_id": "redtide_5min", "product": "redtide", "product_name": "Red Tide Maps", "res_arcmin": 5,
  "grid": {"ncols": 78, "nrows": 66, "xllcorner": -87.5, "yllcorner": 25, "cellsize": 0.0833333333333333,
           "nodata": -3.4e+38, "crs": "EPSG:4326", "extent": [-87.5, -81, 25, 30.5],
           "n_cells": 5148, "n_water": 3838,
           "cell_order": "row-major from the northwest corner: cell = (row - 1) * ncols + col, the raster package numbering and the ASCII token order",
           "template": "template rasters/depth 5min 66x78.asc",
           "atlantic_box": {"lon_gt": -82, "lat_gt": 28.5}},
  "months": {"first": "198501", "last": "202612", "n": 504, "last_data": "202610", "n_placeholder": 2},
  "samples": {"file_pattern": "samples/fwc_<yyyy>.csv", "source": "FWC-FWRI HAB Monitoring Database (ArcGIS REST)",
              "file": "FWC HAB data 19800102-20261021_filtered.Rdata", "date_from": "1980-01-02", "date_to": "2026-10-21",
              "n_rows_filtered": 183402, "n_rows_bundle": 181411, "last_month": "202610",
              "coordinate_note": "exact doubles of the pipeline (6-decimal source values, about half stored one ulp off, printed with 17 digits where needed); cell is computed from them"},
  "nearshore": {"rule": "mask5adj", "n_cells": 189, "km2": 14205},
  "clipping": {"hybrid": 155, "viirs": 0, "hybrid_modis": 123, "modis": 0, "pred": 226, "hybrid_changed": 210, "hull_flagged": 10},
  "source": {"repo": "https://github.com/WFS-FEM/RedTideMaps", "branch": "main",
             "ascii_dir": "out/5min/ecospace_ascii",
             "ascii_commit": "<40-hex: last commit touching out/5min/ecospace_ascii, 543bc8e... today>",
             "ascii_dirty": false,
             "ascii_md5": "<md5 of the 504 md5 strings of ascii_md5.csv concatenated in month order>",
             "head_commit": "<40-hex HEAD at build time; informational, the parent of the data: commit that carries this bundle>",
             "schema_url": "https://github.com/WFS-FEM/RedTideMaps/blob/<head_commit>/docs/issue23_portal-bundle/bundle-schema.md"},
  "build": {"built_at": "2026-11-10T15:04:11Z", "r_version": "4.5.1", "raster_version": "3.6-32", "writer": "scripts/write_bundle.R",
            "run_log": "run_20261110.log", "mode": "pipeline",
            "toggles": {"update_modis": false, "rebuild_nflh": false, "fwc_refresh": false, "fwc_force_full": false,
                        "incremental_fit": true, "fit_nb": false, "export_ecospace": false, "write_bundle": true}},
  "cfg": {"res": 5, "styr": 1985, "enyr": 2026, "hull_link_km": 75, "hull_buffer_km": 10, "hull_min_pts": 4, "hull_concavity": 2,
          "hull_warn_span_km": 300, "viirs_nearshore": "mask5adj", "modis_nearshore": "mask5adj", "use_viirs": true, "use_modis": true}
}
```

Rules. `cfg` carries only the map-determining keys of the `cfg` list of `run_redtide_maps.R:42-96` (res, styr, enyr, the five `hull_*`, the two nearshore rules, `use_viirs`, `use_modis`); the run toggles sit under `build.toggles`, and the path keys (`repo_dir, proj_dir, bathy_dir, ecospace_root`) are never written (public repo, machine-specific). `samples.date_from/date_to` are parsed from the filtered file name (`fn.filter_hab_data()` builds it from the merged file name, `get_HAB_data.R:240-241`). `months.last_data` is the last month with a sample; the placeholder months are the months after it (their maps are zero by construction, the run covers the whole current year, `run_redtide_maps.R:48`). Provenance (D8): `source.ascii_commit` is `git log -1 --format=%H -- out/<res>min/ecospace_ascii` (the last commit that changed the maps the bundle encodes), `source.ascii_dirty` is TRUE when `git status --porcelain -- out/<res>min/ecospace_ascii` is non-empty (TRUE on a monthly update, whose new ASCII are not yet committed; FALSE on a verification run: informative, unlike an unscoped flag, which the tracked PDFs make TRUE on every run), `source.ascii_md5` ties the bundle to the exact ASCII bytes (1.4, `ascii_md5.csv`), and `head_commit` is informational. The bundle's own commit is known only after the `data:` commit; it lives in that commit's message and in WFS-Portal's `FETCH.json` (section 7), and `SCHEMA.md` says so. `"unknown"` for any git value when git is not callable. `build.mode` is `"pipeline"` (step 9 of a run) or `"standalone"` (the stage called from the console against the run on disk, as in steps 2 and 4 of section 9 and the check script's rerun stage). Volatile keys: `build.built_at`, `build.run_log`, `source.*`.

**grid.csv** (5,148 rows in cell order). Required columns (what `validate_product()` demands of any bundle): `cell, row, col, lon, lat, water, km2`; optional, present in the red tide bundle: `depth_m, nearshore, atlantic`.

| column | type | definition |
|---|---|---|
| `cell` | int | 1 to 5,148, raster cell number (row-major from the northwest corner) |
| `row`, `col` | int | `raster::rowFromCell`, `colFromCell`; row 1 is the northernmost |
| `lon`, `lat` | dbl | cell center, `raster::xyFromCell`, full precision (17 digits where needed) so `cellFromXY` round-trips |
| `water` | lgl | TRUE where the depth template is not NA (3,838), FALSE on land (1,310; NODATA in every ASCII) |
| `km2` | dbl | `raster::values(raster::area(depth))` (73.7 to 77.5 at 5 arcmin), what `check_final_hybrid_issue18.R:238` uses for `km2_ge10k` |
| `depth_m` | dbl, optional | the template value; NA on land |
| `nearshore` | lgl, optional | TRUE for the cells of the run's nearshore set (`nearshore_mask_<rule>.grd`; 189 for `mask5adj`), FALSE on other water, NA on land; absent when both rules are `"none"` |
| `atlantic` | lgl, optional | `lon > -82 & lat > 28.5`, the box excluded from every spatial set (`process_hybrid.R:72`, `get_HAB_data.R:279-292`); for Part 3 subsets |

**months.csv** (504 rows): `yrmo` (chr, "198501"), `year`, `month`, `index` (1 to 504), `label` ("1985-01"), `placeholder` (lgl, TRUE after `samples.last_month`: 202611 and 202612 today). The viewer hides placeholder months (D16); the bundle keeps them because the Ecospace deliverable carries them.

**layers.csv** (one row per layer): `id, name, units, encoding, file_pattern, summary_file, total_column, fill, precision, description`. The red tide row: `redtide, "Karenia brevis cell concentration, delivered map", cells/L, long_sparse, values/redtide/<yyyy>.csv, summary/redtide.csv, exposure, 0, "shortest decimal that round-trips the double (15 or 17 significant digits)", "sdmTMB prediction clipped by the VIIRS / MODIS / hull cascade with the nearshore hybrid, rule mask5adj"`. `encoding` has one value in schema 1.0, `long_sparse`; a dense encoding is reserved, not specified (1.5). There is no `kind` column.

**values/redtide/<yyyy>.csv** (unquoted; columns `yrmo, cell, value`): one row per water cell with value > 0 in each month of that year, sorted by `yrmo` then `cell`, `value` through `fn.fmt_num()`. Cells not listed are 0 on water and NA on land (the normalization `make_redtide_ascii()` applies to every written layer, `polygon_clipping_rt.R:287, 307-308`). A year without positives still gets its file with the header only.

**summary/redtide.csv** (504 rows, one per month, ascending). Map metrics are on the delivered map's water cells; bands are right-closed on positive cells: `cut(v[v > 0], c(0, 1e3, 1e4, 1e5, 1e6, Inf), include.lowest = TRUE)` (`clip_months_hybrid_issue18.R:257-266`); exposure is the sum of cells/L over the water cells (line 268; `check_final_hybrid_issue18.R:235`). The sample-derived columns (`n_samples` through `in_ge10k`) are optional in the schema: NA when a bundle carries no `samples/` (`meta.samples = null`); the red tide bundle carries them (D15). There is no `method` column: the portal labels `use` itself.

| column | type | definition and source |
|---|---|---|
| `yrmo, year, month` | chr, int, int | |
| `use` | chr | `clipping_source.csv` `use` (the `X` prefix of that file is on `yrmo`, stripped when joining): one of `hybrid, viirs, hybrid_modis, modis, pred` (`polygon_clipping_rt.R:275-278`; README line 67); `viirs` and `modis` occur when a nearshore key is `"none"` |
| `hybrid_changed` | lgl | `clipping_source.csv` |
| `n_changed` | int | water cells where the delivered map differs from the satellite clip it was built on (the VIIRS-clipped stack for `hybrid`, the MODIS-clipped stack for `hybrid_modis`, normalized as `norm_map`, lines 129, 179, 192-193), counted with a relative tolerance: `sum(abs(M - S) > 1e-9 * pmax(abs(S), 1), na.rm = TRUE)`. The tolerance is the rule, because the ASCII text and the FLT4S stacks differ by up to 5e-15 relative, and exact inequality would count representation noise (15 of the 155 VIIRS months differ from `final_n_changed` without it; with it all 155 agree). 0 for `viirs`, `modis` and `pred` months; NA when the clipped stacks are not supplied |
| `hull_span_km` | dbl | `hull_diagnostics.csv$max_span_km` for any month with a row; NA where the month has no row (today the 19 months without samples) or the file is not supplied |
| `hull_flagged` | lgl | the pipeline rule (`run_redtide_maps.R:331-332`, README line 65): `hull_diagnostics.csv$flagged & use == "pred"`, FALSE for satellite months whose footprint serves only inside the nearshore set, NA where no row or file not supplied. 10 months today (the log's `Hulls:` list), not the 71 raw flags |
| `fit_status` | chr | `fitted` / `failed` (a layer exists but is all zero) / `none` (no fit attempted), from the unclipped stack as line 173; NA when not supplied |
| `converged` | lgl | `RT_fit_matrix` `convergence` of `fit_sdmTMBlog`: TRUE or FALSE when a log model was fit, NA otherwise (`"no model"` or no attempt; 328 / 3 / 173 today); NA when the file is not supplied |
| `viirs_status` | chr | `positive` / `zero` / `missing` (inside the VIIRS stack's first-to-last month but no layer) / `no_coverage`, as lines 174-177 with the range read from the stack's layer names (`VIIRS_201201-202412.grd`); NA when `use_viirs` is FALSE |
| `n_samples` | int, optional | filtered FWC samples of the month with a non-NA count (all rows of the month, as `tab$n_samples`, line 190) |
| `n_samples_water` | int, optional | those on a water cell of the template (`cellFromXY` not NA and `water`) |
| `n_samples_pos` | int, optional | rows with `cells > 0` (equals `fwc_n_pos` of the #18 table) |
| `s_le1k, s_1k_10k, s_10k_100k, s_100k_1M, s_gt1M` | int, optional | the positive samples by band (the `fwc_n_*` columns, panel A of #18, line 417) |
| `samples_ge10k`, `in_ge10k` | int, optional | water samples with `cells >= 10000`, and how many of them sit in a cell where the map is > 0 (`check_final_hybrid_issue18.R:204-230`; the `record_months` columns) |
| `exposure` | dbl | unrounded sum over the water cells |
| `n_pos` | int | water cells with value > 0 |
| `n_le1k, n_1k_10k, n_10k_100k, n_100k_1M, n_gt1M` | int | the five bands; they sum to `n_pos` |
| `n_ge10k, km2_ge10k, n_ge100k, n_ge1M` | int, dbl, int, int | cells at or above each threshold and the km2 of the first (`expo_of`, `check_final_hybrid_issue18.R:234-242`; the #5 figure metrics, `plot_summary_issue5.R:46-49`) |
| `max_cells, max_cell` | dbl, int | maximum and its `cell` (first on ties; NA when the maximum is 0) |

**samples/fwc_<yyyy>.csv** (columns `year, month, cells, lon, lat, cell, water`): the rows of `filtered_points_df` (`get_HAB_data.R:298-299`) with a non-NA count and `year` in `styr..enyr` (181,411 rows today; the 1,991 rows before 1985 are outside the product months), plus `cell` (`raster::cellFromXY(depth, cbind(lon, lat))` on the exact doubles, NA for the 93 off-grid rows) and `water` (the grid flag of that cell; NA off-grid). `cell` is the authoritative cell of a sample; a consumer recomputing it from the printed `lon, lat` gets the same cell because the text round-trips the double. Duplicate rows (same station, count and month on different days) are kept as delivered. Sorted by `year, month, lat, lon, cells` so a monthly run appends at the end of the current year's file.

**ascii_md5.csv** (504 rows; columns `yrmo, file, bytes, md5`): per ASCII file, the md5 of its content with every 0x0D byte removed (`fn.md5_lf()`: `readBin` the file, drop CR, `tools::md5sum` of a temp copy), so the value is the same on a CRLF working tree, an LF checkout and a GitHub raw download, and equals the md5 of the git blob's content. This is the staleness guard: the check script and the fetch script (local mode) recompute it from the ASCII on disk and refuse a bundle that does not match the maps beside it (a bundle from an older run, or a run with `cfg$write_bundle = FALSE` after the maps changed). `meta.source.ascii_md5` is the md5 of the 504 strings concatenated in month order, one value to compare.

**style.json** (product facts only, D6; all presentation lives in WFS-Portal's one style file, section 4.3):

```json
{"schema_version": "1.0", "units": "cells/L",
 "palette": {"type": "ramp",
             "anchors": ["white","purple","blue","darkblue","cyan","green","darkgreen","yellow","orange","red","darkred"],
             "bias": 2, "breaks": {"zero": 0, "first_colored": 10000, "step": 10000, "last": 4000000}, "above": "darkred",
             "colors_hex": ["#FFFFFF", "...400 more...", "#8B0000"]},
 "bands": {"breaks": [0, 1000, 10000, 100000, 1000000, "Inf"], "right_closed": true,
           "columns": ["n_le1k", "n_1k_10k", "n_10k_100k", "n_100k_1M", "n_gt1M"],
           "sample_columns": ["s_le1k", "s_1k_10k", "s_10k_100k", "s_100k_1M", "s_gt1M"],
           "labels": ["<= 1k", "1k to 10k", "10k to 100k", "100k to 1M", "> 1M"]},
 "codes": {"use": {"hybrid": "VIIRS clip, hull footprint added inside the nearshore set",
                   "viirs": "VIIRS clip", "hybrid_modis": "MODIS clip, hull footprint added inside the nearshore set",
                   "modis": "MODIS clip", "pred": "hull-clipped prediction (no satellite coverage)"},
           "fit_status": {"fitted": "a model was fit", "failed": "the fit failed (all-zero layer)", "none": "no fit attempted"},
           "viirs_status": {"positive": "VIIRS layer with detections", "zero": "VIIRS layer, no detection",
                            "missing": "inside the VIIRS era, tif missing", "no_coverage": "outside the VIIRS era"}}}
```

The palette recipe is the pipeline's (`polygon_clipping_rt.R:339-343`: `colv`, `colorRampPalette(colv, bias = 2)`, `brks <- c(0, 1e4 - 1, seq(1e4, 4e6, 10000), Inf)`, `color <- c(funpal(length(brks) - 2), "darkred")`), with `colors_hex` the expanded 402-color vector so a non-R reader gets the same colors; it is a fact about the delivered product (the pipeline PDFs use it). The band definition is the house convention (right-closed, positive cells, k and M labels). The code lists document the vocabularies of the summary columns; display labels, band colors, point symbols, line colors, era shading, series labels, sizes and text are the portal's (4.3). Nothing here changes without a schema version note.

**manifest.csv** (columns `file, bytes, md5`): every file of the bundle except itself, listed with `list.files(dir, all.files = TRUE, recursive = TRUE, no.. = TRUE)` so `.gitattributes` is included, paths relative to the bundle folder with `/` separators, `tools::md5sum` on the LF files. The fetch script verifies against it; the check script uses it for the byte-identical rerun.

**SCHEMA.md**: `docs/issue23_portal-bundle/bundle-schema.md` re-written LF into the bundle, so the data describes itself. The document holds the tables above; the ASCII quirk (treat values below -1e30 as NODATA, `clip_months_hybrid_issue18.R:208`); the statement that the bundle reproduces the text of the ASCII while GDAL readers see float32, with the tolerance rules (`all.equal()` against float32 readers; `n_changed` relative 1e-9; exposure absolute 1e-3); the coordinate note; the provenance rules (`ascii_commit`, `ascii_dirty`, `ascii_md5`; the bundle's own commit lives in the `data:` commit and `FETCH.json`); the optional columns and files (`depth_m, nearshore, atlantic`; `samples/` and the sample-derived summary columns); the attribution text (3.5); a "reserved for the first Ecospace bundle" paragraph (1.5); and the version history.

### 1.5 Future Ecospace products on the same schema

An Ecospace run is one bundle (`ecospace_<run>_5min`) with the same `grid.csv` (same template; the optional columns may be absent), its own `months.csv` (may start or end elsewhere), `layers.csv` with one row per species or fleet (`id gag_grouper, name "Gag grouper biomass", units "t/km2", encoding long_sparse, total_column total, fill 0, precision "6 significant digits"`), `values/<layer_id>/<yyyy>.csv`, `summary/<layer_id>.csv` with the generic columns `yrmo, year, month, total, mean, n_pos, max_value, max_cell` (anything else optional), no `samples/` (`meta.samples = null`, the sample-derived columns absent), and a `style.json` with the bundle's palette recipe and `"bands": null`. The writer is a small script in the Ecospace outputs repository (or `scripts/write_bundle.R` reused with `product = "ecospace"` and a layer loop), reading Ecospace's per-species ASCII with the same `fn.read_ascii_dir()` because Ecospace writes the same grid. Nothing in the portal is red-tide-specific except the `redtide` product definition and its style file: the series module reads the portal style's `series` block, the bands module hides when `style$bands` is null, the samples module when `samples` is null.

Reserved for the first Ecospace bundle, named but not specified in 1.0 (D14; a minor bump adds them): a dense `encoding` for layers positive almost everywhere (20 dense layers x 3,838 cells x 504 months is about 300 MB of text, which also raises plain git versus Git LFS versus GitHub release assets, fetched by the same script); per-layer style overrides (a species and a fleet need their own scales and units); a `viridis` palette type. Specifying them now, with nothing exercising them, would only get them wrong.

### 1.6 Versioning

`schema_version` is `"major.minor"`: a minor bump adds files, columns or keys (readers ignore unknown ones); a major bump renames, removes or changes the meaning of anything (band definition, cell order, layout, the meaning of a provenance key). The portal loader accepts major 1 and stops with a clear message otherwise, warning on a newer minor. The specification is `docs/issue23_portal-bundle/bundle-schema.md` (house convention: one folder per issue; a later issue that bumps the schema holds the next version and its changelog row), written into every bundle as `SCHEMA.md`; `meta.json$source$schema_url` points at it at the build commit. Part 1 ships 1.0. A schema change is applied by calling the stage standalone on a machine that has the run on disk (about 10 s, `build.mode = "standalone"`, no 9-minute run): the stage needs the gitignored run outputs (`clipping_source.csv`, the filtered samples, the stacks, the fit matrix, the mask, `hull_diagnostics.csv`), like every check script, so there is no "rebuild from a fresh clone" (D7). A bundle-to-bundle re-encode mode (the previous bundle supplying the non-ASCII columns) is not built.

---

## 2. Producer stage in RedTideMaps

### 2.1 Function and file

New file `scripts/write_bundle.R`, sourced by the driver after `polygon_clipping_rt.R` (`run_redtide_maps.R:146`). The `fn.` prefix follows the pipeline's own functions.

```r
fn.write_bundle <- function(dir_ascii,              # paths$ecospace: the 504 tracked ASCII files, the source of the values
                            file_depth,             # paths$file_depth: land, cell centers, km2, the grid header
                            file_clipsrc,           # file.path(paths$clipped_out, "clipping_source.csv"): use, hybrid_changed (gitignored: the run must be on disk)
                            file_filtered,          # hab$file: filtered_points_df (the samples; gitignored)
                            dir_out,                # paths$bundle (the stage writes to <dir_out>_tmp and swaps)
                            cfg, res, repo_dir,     # meta.json cfg/build blocks, res_arcmin, git state
                            file_schema,            # docs/issue23_portal-bundle/bundle-schema.md, re-written LF as SCHEMA.md
                            file_mask       = NULL, # nearshore$file (grid$nearshore); NULL when both rules are "none"
                            file_unclip     = NULL, # pred_paths$file_log (fit_status)
                            file_fitmat     = NULL, # fit_files$fit_matrix (converged)
                            file_viirs_raw  = NULL, # viirs$file (viirs_status); NULL when use_viirs is FALSE
                            file_viirs_clip = NULL, # clip_viirs$file (n_changed of the hybrid months)
                            file_modis_clip = NULL, # clip_modis$file (n_changed of the hybrid_modis months)
                            file_hulldiag   = NULL, # out/<res>min/sdm/hull_diagnostics.csv (hull_span_km, hull_flagged)
                            file_combined   = NULL, # combined_path: all.equal() check against the stack the ASCII was written from
                            mode = c("pipeline", "standalone"),
                            product = "redtide", product_name = "Red Tide Maps", layer = "redtide",
                            schema_version = "1.0")
# returns invisible(list(bundle_id, dir, n_months, n_placeholder, n_months_pos, n_samples, samples_to,
#                        n_files, bytes, ascii_commit, ascii_dirty, seconds, summary = <data.frame>, manifest = <data.frame>))

fn.read_ascii_dir <- function(dir_ascii, file_depth, pattern = "^sdmTMB_log__([0-9]{6})[.]asc$")
#   list(months = <chr>, M = <n_cells x n_months double matrix, NA on land>, header = <list>, md5 = <data.frame yrmo, file, bytes, md5>):
#   scan(f, skip = 6, quiet = TRUE); v[v < -1e30] <- NA (the first-token quirk, clip_months_hybrid_issue18.R:208);
#   the six header lines parsed and compared to the template (ncols, nrows, xllcorner, yllcorner, cellsize); md5 via fn.md5_lf()
fn.band_counts   <- function(v, breaks = c(0, 1e3, 1e4, 1e5, 1e6, Inf))   # class_counts(), lines 262-266: c(n_pos, five bands)
fn.layer_summary <- function(M, water, km2, breaks)        # pure: the map-metric columns from a cell x month matrix (colSums, as expo_of); reused by the check script
fn.n_changed     <- function(M, S, tol = 1e-9)             # colSums(abs(M - S) > tol * pmax(abs(S), 1), na.rm = TRUE): the n_changed rule
fn.samples_table <- function(file_filtered, depth, styr, enyr)   # lines 161-169 of the #18 script plus the year filter; exact doubles
fn.fmt_num       <- function(x)                            # %.15g, %.17g where that does not round-trip (1.3)
fn.write_csv_lf  <- function(df, file, quote = "character")  # "wb" connection, write.csv(eol = "\n"); quotes the character columns only; FALSE for values files
fn.write_json_lf <- function(x, file)                      # toJSON(auto_unbox, pretty, digits = NA) + writeLines to a "wb" connection
fn.write_text_lf <- function(file_in, file_out)            # readLines + writeLines(sep = "\n") on a "wb" connection (SCHEMA.md, .gitattributes)
fn.md5_lf        <- function(files)                        # md5 of each file's bytes with 0x0D removed (temp copy + tools::md5sum)
fn.git_state     <- function(repo_dir, ascii_dir)          # head_commit, branch, ascii_commit (git log -1 --format=%H -- <dir>), ascii_dirty (git status --porcelain -- <dir>)
                                                           # via system2(Sys.which("git"), c("-C", shQuote(repo_dir), ...)); base-R fallback reads .git/HEAD and packed-refs for
                                                           # head_commit and branch only, the ascii keys "unknown"; every key "unknown" when nothing works
fn.bundle_style  <- function()                             # the style.json content of 1.4 (facts only), colors_hex expanded from the recipe
fn.bundle_manifest <- function(dir)                        # file, bytes, md5 of every file except manifest.csv (all.files = TRUE)
fn.assert_no_cr  <- function(dir)                          # stops if any file under dir contains a 0x0D byte
```

### 2.2 Hook in `run_redtide_maps.R` (edited once, on the branch, never during a run)

- Header comment (lines 3-16): add `9. Write the data-only bundle for WFS-Portal under out/<res>min/bundle/ (tracked).`
- `cfg` (line 95 gets a trailing comma; new line after it): `write_bundle = TRUE,   # step 9: the data-only bundle for WFS-Portal, out/<res>min/bundle/ (tracked; docs/issue23_portal-bundle/bundle-schema.md)`.
- Source list (after line 146): `source(file.path(cfg$repo_dir, "scripts", "write_bundle.R"))`.
- Line 260 (`clip_hybrid <- NULL; clip_hybrid_modis <- NULL`) becomes `clip_hybrid <- NULL; clip_hybrid_modis <- NULL; nearshore <- NULL`: today `nearshore` is assigned only inside the `if` at lines 261-274, so a run with both nearshore keys `"none"` (documented in `config.local.example.R:52, 60`) has no such object and `nearshore$file` would stop step 9.
- New block after step 8 (line 346), before `rt_log(paths, "Run complete.")` (line 347):

```r
# 9) Data bundle for WFS-Portal (tracked, data only; docs/issue23_portal-bundle/bundle-schema.md)
if (isTRUE(cfg$write_bundle)) {
  rt_log(paths, "Step 9: write the data bundle for WFS-Portal (out/<res>min/bundle/)")
  bundle <- fn.write_bundle(
    dir_ascii       = paths$ecospace,
    file_depth      = paths$file_depth,
    file_clipsrc    = file.path(paths$clipped_out, "clipping_source.csv"),
    file_filtered   = hab$file,
    dir_out         = paths$bundle,
    cfg = cfg, res = paths$res, repo_dir = cfg$repo_dir,
    file_schema     = file.path(cfg$repo_dir, "docs", "issue23_portal-bundle", "bundle-schema.md"),
    file_mask       = if (!is.null(nearshore)) nearshore$file else NULL,
    file_unclip     = pred_paths$file_log,
    file_fitmat     = fit_files$fit_matrix,
    file_viirs_raw  = if (isTRUE(cfg$use_viirs)) viirs$file else NULL,
    file_viirs_clip = if (!is.null(clip_viirs)) clip_viirs$file else NULL,
    file_modis_clip = if (!is.null(clip_modis)) clip_modis$file else NULL,
    file_hulldiag   = file.path(paths$sdm_out, "hull_diagnostics.csv"),
    file_combined   = combined_path,
    mode            = "pipeline")
  rt_log(paths, sprintf("Bundle %s: %d months (%d placeholders, %d with positives), %d samples to %s, %d files, %.1f MB, ASCII commit %s%s, %.0f s",
                        bundle$bundle_id, bundle$n_months, bundle$n_placeholder, bundle$n_months_pos,
                        bundle$n_samples, bundle$samples_to, bundle$n_files, bundle$bytes / 1e6,
                        substr(bundle$ascii_commit, 1, 7), if (isTRUE(bundle$ascii_dirty)) " (ASCII modified, not yet committed)" else "",
                        bundle$seconds))
}
```

- `scripts/_setup.R`: `rt_paths()` gains `bundle = file.path(out_root, "bundle"),` after `plots_out` (line 132). `rt_init_dirs()` (lines 142-151) is unchanged: the stage creates its own folder by the swap of 2.3.
- `config.local.example.R`: a block ending `# cfg$write_bundle <- FALSE` with two comment lines (skip step 9 on an experimental run whose maps will not be committed).
- `.gitignore`: the two exceptions of 1.1.

### 2.3 What it reads and how it computes

1. The template: `depth <- raster(file_depth)`; `land`, `water`, `km2 <- values(area(depth))`, `xy <- xyFromCell()`, `atlantic`, as `process_hybrid.R:67-73`; the header for `meta$grid`.
2. The ASCII directory, not the combined stack: it is the deliverable Ecospace reads, it is tracked, and it is what the bundle must reproduce text for text (0.35 s to read). The other inputs (`clipping_source.csv`, the samples, the stacks, the fit matrix, the mask, `hull_diagnostics.csv`) are gitignored run outputs, so the stage needs the run on disk, like every check script. `file_combined`, when given, is only compared to (2.4).
3. `clipping_source.csv` (`use`, `hybrid_changed`; `yrmo` with its `X` stripped); the unclipped stack (`fit_status`); `RT_fit_matrix.RData` (`converged`, as `clip_months_hybrid_issue18.R:148-151, 186-187`); the raw VIIRS stack (`viirs_status`); the VIIRS- and MODIS-clipped stacks normalized as `norm_map`, `n_changed <- fn.n_changed(M[, m], S[, m])` for the hybrid months with the relative tolerance of 1.4 (lines 179, 192-193 use exact inequality between two FLT4S stacks; the tolerance reproduces their counts from the ASCII text); `hull_diagnostics.csv` (`hull_span_km = max_span_km`; `hull_flagged = flagged & use == "pred"`); the nearshore raster (`grid$nearshore`). Each optional input missing yields NA in its column.
4. The samples: `load(file_filtered)`, `sf::st_drop_geometry`, `as.numeric(cells)`, drop NA counts, `cell <- cellFromXY()` on the exact doubles, `water`, keep `year` in `styr..enyr`; per-month counts as lines 161-170, 190-191 and `check_final_hybrid_issue18.R:204-230`.
5. Metrics, vectorized over the matrix (`fn.layer_summary()`): `exposure = colSums(M[water, ])`; `n_pos = colSums(M > 0, na.rm = TRUE)`; the bands by `tabulate(cut(v[v > 0], breaks, labels = FALSE, include.lowest = TRUE), 5)` per column; `n_ge10k`, `km2_ge10k`, `n_ge100k`, `n_ge1M` as `expo_of` (`check_final_hybrid_issue18.R:234-242`); `max_cells = apply(M, 2, max, na.rm = TRUE)`; `max_cell = which.max` (NA when the maximum is 0).
6. `placeholder`: months after the last sample month (`months.csv`); `last_data` and `n_placeholder` in `meta.months`.
7. Writing, atomically: everything goes to `<dir_out>_tmp/` (`out/<res>min/bundle_tmp/`, created fresh; the stage stops if it exists and cannot be removed, since `unlink()` returns 1 without an error when Explorer or an editor holds a file): `.gitattributes`, `SCHEMA.md`, `grid.csv`, `months.csv`, `layers.csv`, `values/`, `summary/`, `samples/`, `ascii_md5.csv`, `style.json`, `meta.json`, then `manifest.csv`. The read-back and the CR assertion (2.4) run on the temp folder. Then the swap: `file.rename(dir_out, "<dir_out>_old")` if `dir_out` exists (Windows cannot rename a directory onto an existing one), `file.rename("<dir_out>_tmp", dir_out)`, `unlink("<dir_out>_old", recursive = TRUE)` with its return value checked (a leftover `bundle_old/` is reported, never tracked: it is matched by no `.gitignore` exception... it would be, under `!out/*/`, so the stage adds nothing and the README tells the operator to delete it; the check script refuses to run while it exists). A failure before the swap leaves the tracked folder untouched, so `git status` after a failed 9-minute run shows the old bundle, not a half-written one.

### 2.4 Assertions inside the stage (stop the run on failure; under two seconds)

- Exactly `12 * (enyr - styr + 1)` monthly ASCII files and no other `.asc`; the months contiguous and equal to the rows of `clipping_source.csv`; every header equal to the template's first five lines.
- In every month the NA set equals the template land; all water values finite and >= 0.
- `use` in the five documented values; bands sum to `n_pos`; sample bands sum to `n_samples_pos`; `n_ge10k` equals the sum of the three upper bands unless a cell is exactly 10,000 (reported, not fatal: the right-closed band wins, none exist today); `hull_flagged` TRUE only where `use == "pred"`.
- When `file_combined` is given: for every month `isTRUE(all.equal(M[, m], norm(stack[, m])))`, the #18 criterion (line 209), because the FLT4S stack and the 15-digit text differ at the 16th digit in 162 months; `identical()` is wrong here by construction.
- When `file_mask` is given: the raster is NA exactly on land, 0 or 1 on water, none of its cells in the Atlantic box.
- After writing, on the temp folder: every table is read back with the documented `colClasses` and is `identical()` to the data frame that was written (this verifies the number formatting and the quoting on every run); the values matrix rebuilt from the year files (0 fill, NA on land) is `identical()` to `M`; `meta.json` and `style.json` parse; `fn.assert_no_cr()` finds no 0x0D byte in any file; the manifest lists every file including `.gitattributes`.
- Regression against the #18 tables is not asserted in the pipeline: those tables are a frozen snapshot of one run, and a later run legitimately differs. That is the check script's job (section 8).

### 2.5 Config, README and docs updates

- `README.md`: the pipeline table (lines 40-55) gains `| Write the data bundle for WFS-Portal | fn.write_bundle | write_bundle.R |`; the first-run list (87-93) gains `7. Write the data bundle to out/<res>min/bundle/`; "Monthly rerun" step 3 (line 106) becomes "Commit the updated deliverables, `out/<res>min/ecospace_ascii/`, `out/<res>min/plots/` and `out/<res>min/bundle/`" with the note that the bundle's `ascii_md5.csv` must match the ASCII in the same commit (the check script verifies it); the configuration table (146-169) gains `write_bundle`; the outputs tree (187-219) gains `bundle/` with one line per file and the note at 221 names it as tracked; a new section "Data bundle for WFS-Portal" (what it is, who reads it, the schema link, the WFS-Portal link, the provenance keys).
- `docs/README.md`: a row for `issue23_portal-bundle/`.
- The #23 README states the local Rscript path once (`"C:/Program Files/R/R-4.5.1/bin/x64/Rscript.exe" run_redtide_maps.R`), the generic README keeps `Rscript`.
- `scripts/README.md` is a one-line stub ("Create a folder"); out of scope, mentioned to Holden.

### 2.6 The #23 docs folder: `docs/issue23_portal-bundle/`

| file | what |
|---|---|
| `README.md` | what changed, how to run (local Rscript path), files, results (the frozen counts of 8.1 quoted), checks the script enforces (the #18 README's headings) |
| `issue23-portal-bundle-plan.md` | this design's sections 1, 2, 8 and 9 (producer side) with decisions D1 to D18 quoted |
| `bundle-schema.md` | the schema of section 1 with a changelog table (version, date, change, commit); the source of `SCHEMA.md` |
| `check_bundle_issue23.R` | stages `frozen` and `rerun` (`RT_QA_STAGE`), resolution `RT_QA_RES` (default 5; at 15 the #18 comparisons are skipped with a message, D17), `RT_QA_BUNDLE_DIR` |
| `tables/bundle_vs_issue18_issue23.csv` | per month: the bundle metrics beside the `final_*` and `fwc_*` columns of `clip_class_counts_hybrid_issue18.csv`, their differences, `equal` |
| `tables/bundle_vs_record_issue23.csv` | per month: `n_ge10k, km2_ge10k, n_ge100k, n_ge1M, max_cells, samples_ge10k, in_ge10k` beside `record_months_issue18.csv`, `equal`, `refreshed` |
| `tables/bundle_rerun_issue23.csv` | per file: bytes, md5 tracked (`git show HEAD:<file>`), md5 on disk, md5 rerun, `equal` |
| `tables/bundle_files_issue23.csv` | file, bytes, rows |
| `figures/fig1_bundle_quicklook_issue23.png` | 2018-09, 2012-02, 2005-10 and 2026-10 (the last data month) drawn from the bundle with base `image()` only (no raster package): orientation and self-sufficiency |
| `figures/fig2_summary_record_issue23.png` | exposure (million cells/L) and `n_ge10k` 1985-2026 from `summary/redtide.csv`, placeholders shaded |
| `.gitignore` | `hoard/`, `issue23-*-comment.md` (as the #18 folder); `comments/` for the drafts |

### 2.7 Commit plan (branch `23-portal-bundle` from the fresh `main` at `4fee1c9`; draft PR "Data bundle for WFS-Portal (closes #23)")

Each checkpoint of section 9 shows the evidence and the full diff of every commit it names before any of them is made; Holden approves each commit separately.

1. `docs:` the issue folder skeleton (plan, README skeleton, `.gitignore`, `bundle-schema.md` v1.0, the `docs/README.md` row).
2. `feat:` `scripts/write_bundle.R`; `paths$bundle` in `_setup.R`.
3. `config:` step 9, `cfg$write_bundle` and `nearshore <- NULL` in `run_redtide_maps.R`; `config.local.example.R`; the `.gitignore` exceptions.
4. `test:` `check_bundle_issue23.R`.
5. `data:` `out/5min/bundle/` from the verification run with `cfg$fwc_refresh <- FALSE` (the ASCII byte-identical, so `ascii_dirty` is FALSE; the plots PDFs, changed only by their date lines, are restored before the commit, as the #18 convention restores tracked files after a verification run). Message: `data: bundle redtide_5min schema 1.0 (ASCII at 543bc8e, FWC samples through 2026-10-21)`.
6. `qa:` the tables and figures of the check run.
7. `docs:` README, `docs/README.md`, the #23 README results; `gh issue close 22` as a duplicate; the WFS-Portal issues (9.1) opened and linked from #23.

### 2.8 Run-time cost

Reading the 504 ASCII files 0.35 s and their LF md5s about 1.5 s; the template and the optional stacks (unclipped, two clipped, raw VIIRS, mask) about 2 s; samples load and `cellFromXY` about 2 s; `all.equal` against the combined stack about 1 s; writing 42 + 42 + 7 text files about 3 s; md5, read-back and the CR scan about 2 s. About 12 s on a 7.4 to 9 minute run (ASSUMPTION; measured and recorded in the #23 README at step 2 of section 9).

---

## 3. WFS-Portal repository layout

```
WFS-Portal/
  app.R                       shinyApp(app_ui(site, products), app_server(site, products)); reads the preset, loads the enabled products
  DESCRIPTION                 Package: WFSPortal; Imports: shiny (>= 1.8); Suggests: ragg, testthat, png, rsconnect; no package structure
  README.md  LICENSE  ATTRIBUTION.md  .gitignore  .gitattributes  WFS-Portal.Rproj
  config/
    products.R                the product registry (tracked): one product_def() per product; products_from_bundle() for later multi-layer bundles
    redtide.R                 preset: site <- list(title = "Red Tide Maps", products = "redtide", play_interval_ms = 200, speeds_ms = c(500, 200, 100), preload_all = FALSE)   (the default)
    portal.R                  preset: site <- list(title = "WFS Portal", products = c("redtide"), ...)
    active.example.R          copy to config/active.R (gitignored): source("config/portal.R"); site$preload_all <- TRUE for local use
    local.example.R           copy to config/local.R (gitignored): redtidemaps_dir <- "C:/Repos/WFS-FEM/RedTideMaps"
    style/redtide.json        THE one style file: every presentation key (4.3) plus overrides of the bundle's facts
  R/                          auto-sourced by shiny; scripts and tests source it explicitly
    packages.R                check_packages(): the rt_check_packages() pattern (_setup.R:17-24)
    bundle_read.R             read_bundle(), read_layer(), expand_to_grid(), verify_bundle()
    product.R                 product_def(), products_from_bundle(), make_product(), validate_product(), viewer_months(), union_months()
    style.R                   style_from_bundle(), merge_style(), palette_of(), style_hash(), fmt_n(), fmt_big()
    geometry.R                map_geometry(), to_z()
    summary.R                 band_counts(), exposure_of(), map_info_lines(), info_lines_redtide()
    plot_map.R                draw_map(), draw_colorbar(), draw_sample_points(), draw_sample_legend()
    plot_series.R             draw_series(), series_geometry()
    plot_bands.R              draw_bands()
    plot_samples.R            draw_samples()
    plot_dashboard.R          draw_dashboard()
    cache.R                   cache_dir(), cache_key(), cache_url(), ensure_cache(), render_month(), render_png(), prerender_product()
    mod_month.R  mod_map.R  mod_thumbs.R  mod_series.R  mod_bands.R  mod_samples.R  mod_info.R  mod_product.R
    app_ui.R  app_server.R  about.R
  data/redtide_5min/          the fetched bundle (tracked) + FETCH.json
  cache/                      gitignored: cache/<bundle_id>/<key8>/...
  www/keys.js  preload.js  portal.css
  scripts/fetch_bundle.R  prerender.R  render_dashboard.R  check_packages.R   (later: update.R)
  tests/testthat/             helper-source.R, test-*.R, fixtures/make_mini_bundle.R, fixtures/mini_bundle/ (generated, tracked)
  docs/issue1_part1-visualization/   README.md, issue1-part1-visualization-plan.md, figures/ (the static dashboard PNGs), checklist.md
                                     (the manual checklist with results), comments/, .gitignore (hoard/, issue1-*-comment.md):
                                     the RedTideMaps docs convention mirrored, minus a check script (the tests live in tests/testthat)
```

### 3.1 Product configuration (standalone vs integrated)

`config/products.R`:

```r
products <- list(
  redtide = product_def(id = "redtide", name = "Red Tide Maps", short = "Red tide",
                        bundle = "redtide_5min", layer = "redtide",
                        source = list(repo = "WFS-FEM/RedTideMaps", path = "out/5min/bundle", branch = "main"),
                        panels = c("map", "series", "bands", "samples", "thumbs", "info"),
                        style_file = "config/style/redtide.json",
                        info = info_lines_redtide))      # function(row, product) -> character
# later: products <- c(products, products_from_bundle("ecospace_run12_5min", layers = NULL, panels = c("map", "series", "thumbs", "info"),
#                      style_file = "config/style/ecospace.json"))   # one product per layer; the product chooser is the layer selector
```

`app.R` picks the preset in this order: the environment variable `WFS_PORTAL_CONFIG` if set (a standard setting on every candidate host, not host-specific code), else `config/active.R` if present (gitignored, local development), else `config/redtide.R`. So a plain clone runs as the standalone "Red Tide Maps" (D2b, one code path) and the integrated portal is one line or one variable. The UI builder is the same in both cases: `bslib::page_navbar(title = site$title, ...)` with one `nav_panel` per enabled product plus an About panel; with one product the navbar carries the product's name and no product tabs. Site options: `play_interval_ms` (the default speed), `speeds_ms` (the choices of the speed select, 5.1), `preload_all` (5.4).

### 3.2 Dependencies and R version

| package | role | why |
|---|---|---|
| `shiny` (>= 1.8; 1.12.0 installed) | runtime | the app; brings `bslib` (0.9.0; `page_navbar`, `layout_columns`, `card`), `htmltools`, `jsonlite` (meta, style, config) as its own imports, so no extra install |
| `grDevices`, `graphics`, `utils`, `tools` | runtime and build | base: `png(type = "cairo")`, `read.csv`, `md5sum`, `download.file` |
| `ragg` | build, optional (Suggests) | faster, font-stable PNG rendering for the cache (`agg_png`); falls back to `grDevices::png(type = "cairo")` |
| `testthat` (3.3.1), `png` | tests only | `testthat::test_dir()`; `png::readPNG` for image dimensions (skipped if absent) |
| `rsconnect` | deploy only, optional | the `writeManifest()` dry run of step P7 and, later, a shinyapps.io or Connect deploy (D1); never referenced by the app |

Not used: `raster`, `terra`, `sf` (the bundle carries the grid, centers and km2; the loader is base R, which keeps shinylive possible), `viridis`/`viridisLite` (the band colors are hex in the style file), `digest` (`tools::md5sum`), `magick`/`gifski`/`zip` (Part 2; `utils::zip()` needs an external binary on Windows, so the `zip` package is the portable choice when ranges are exported), `leaflet` (interactive maps, later if ever). All runtime packages exist in the webR R 4.5 index (shiny, bslib, htmltools, jsonlite, png, ragg present; gifski and arrow absent).

R: `Depends: R (>= 4.2)`; developed and tested with 4.5.1. DESCRIPTION yes (ten lines: it documents the set and `rsconnect`, Connect and `pak::local_install_deps()` read it); renv no (D1: added only when a host demands pinned versions). `scripts/check_packages.R` mirrors `rt_check_packages()` with one install line.

### 3.3 `.gitignore` and `.gitattributes`

```
.Rproj.user/  .Rhistory  .RData  *.log  hoard/
config/active.R  config/local.R
cache/            # pre-rendered PNGs; drop this line if the host deploys from git (see 11)
rsconnect/
```

`.gitattributes`: `data/** text eol=lf` (belt and suspenders: the bundle's own `.gitattributes` is copied in by the fetch and applies too). Tracked: all code, `config/products.R`, the presets, the style file, `data/<bundle_id>/` (about 10 MB of text plus `FETCH.json`), the fixture generator and its output, the issue folder. Not tracked: the PNG cache (rebuilt by `scripts/prerender.R`; rsconnect uploads the folder including gitignored files, so upload-style deploys carry it), the local clone path, the active preset, deploy records.

### 3.4 README outline

1. What this is (the WFS portal; products; red tide first; the RedTideMaps link). 2. Quick start (`git clone`, `Rscript scripts/check_packages.R`, `Rscript scripts/fetch_bundle.R redtide_5min`, `Rscript scripts/prerender.R redtide`, `shiny::runApp()`; a note that Windows users without Rscript on PATH use the full path). 3. Products and configuration (presets, standalone vs portal, the style file, the site options). 4. Data flow (RedTideMaps -> bundle -> fetch -> cache -> app; the schema link). 5. Monthly update (section 7, including which steps stay manual). 6. Deployment (generic: the folder is the app; notes per candidate host, none required; shinylive needs the cache on a static URL). 7. Repository layout. 8. Adding a product (the bundle schema, `product_def()`, `products_from_bundle()`). 9. Tests and the manual checklist. 10. Data sources and attribution. 11. License and authors.

### 3.5 License and attribution

`LICENSE`: MIT, `Copyright (c) 2026 David Chagaris`, as RedTideMaps. `ATTRIBUTION.md`, also shown in the About panel and condensed in the footer:

> Red tide maps are produced by the WFS-FEM/RedTideMaps pipeline (Chagaris, Vilas, Harris; MIT license) on the West Florida Shelf Ecospace grid (Vilas et al. 2023), as part of the project "Operationalizing the West Florida Shelf ecosystem model and application to red tides, stock assessment, and catch advice for Gulf of Mexico reef fish" (PI David Chagaris, University of Florida). In situ Karenia brevis cell counts: Florida Fish and Wildlife Conservation Commission, Fish and Wildlife Research Institute, HAB Monitoring Database (ArcGIS REST services). Satellite bloom detection: University of South Florida Optical Oceanography Laboratory (PI Chuanmin Hu), monthly VIIRS red tide probability maps from NOAA VIIRS (Hu et al. 2015; Yao et al. 2023) and MODIS nFLH from NASA Aqua (Hu et al. 2005). Model: sdmTMB (Anderson et al.). Coastline: Natural Earth 1:10m. The maps are model products, not observations, and not an FWC or USF product; see the RedTideMaps README for the method and its limits.

ASSUMPTION: FWC and USF products may be redistributed with attribution (D15 settles the samples); Holden confirms the wording with the providers before the first public deploy. The funding acknowledgment line is supplied by Holden.

---

## 4. Product contract in R

### 4.1 The bundle object (`read_bundle(dir)`, `R/bundle_read.R`)

```r
list(id = "redtide_5min", dir = "data/redtide_5min",
     meta    = <list, meta.json>,
     grid    = <list meta$grid>,
     cells   = data.frame(cell, row, col, lon, lat, water, km2, ...optional depth_m, nearshore, atlantic),
     months  = data.frame(yrmo, year, month, index, label, placeholder),
     layers  = data.frame(id, name, units, encoding, file_pattern, summary_file, total_column, fill, precision, description),
     samples = data.frame(yrmo, year, month, cells, lon, lat, cell, water) | NULL,   # yrmo added by the loader; NULL when meta$samples is null
     style   = <list, style.json: units, palette, bands, codes>,
     fetched = <list, FETCH.json> | NULL)
```

`read_layer(bundle, layer_id)` returns `list(values = <n_cells x n_months double matrix, NA on land, 0 fill, colnames yrmo>, summary = <data.frame>)`: it dispatches on `encoding` (`long_sparse` in Part 1; any other value stops with "encoding not supported by this loader"), reads the year files with `read.csv(colClasses = c("character", "integer", "numeric"))`, and fills `M <- matrix(0, n_cells, n_months); M[!water, ] <- NA; M[cbind(cell, match(yrmo, months))] <- value`, asserting every `cell` is a water cell and no `(yrmo, cell)` repeats. `verify_bundle(dir)` checks the manifest md5s (shared with the fetch script). Load time about 1 to 2 s (42 + 42 small reads, one 181,411-row rbind, one matrix fill; ASSUMPTION, measured at step P2); memory about 35 MB per product (the matrix 20.8 MB, the samples about 10 MB).

### 4.2 The product object (`make_product(def, bundle)`), what every module consumes

| field | type | meaning |
|---|---|---|
| `id, name, short` | chr | from `product_def()` |
| `bundle_id, layer` | chr | the pair |
| `grid, cells, months` | as the bundle | all 504 months |
| `viewer_months` | chr | `viewer_months(product)`: `months$yrmo[!months$placeholder]` (D16; the one function to change if placeholders are ever shown) |
| `values` | matrix n_cells x n_months | from `read_layer()` |
| `summary` | data.frame | must hold `yrmo` and every column named in `style$series$metrics` and `style$bands$columns` |
| `samples` | data.frame or NULL | NULL hides the samples panel |
| `style` | list | `style_from_bundle(style.json)` (facts) then `merge_style()` with the product's style file (recursive `modifyList`; presentation keys live only there) |
| `panels` | chr | enabled panels |
| `units, total_column` | chr | from `layers.csv` |
| `info` | function(row, product) | lines of the key-information box |
| `geometry` | list | `map_geometry(grid, cells)`: `xs, ys, xlim, ylim, asp, land_z, ncols, nrows` |
| `palette` | list | `palette_of(style$palette)`: `colors` (402), `breaks_img` (403, `Inf` replaced by 1e12 for `image()`, line 327) |
| `cache` | chr | `cache/<bundle_id>/<key8>/` for this product's style hash |
| `source` | list | `meta$source`, `meta$build`, `meta$samples$date_to`, `fetched$commit`, `fetched$fetched_at`, `schema_version` for the footer |

`validate_product()` checks: schema major 1; the required grid columns present; `nrow(cells) == nrow(values)`; `nrow(months) == ncol(values)`; months contiguous and unique; the referenced style columns exist in `summary`; `rowSums(summary[bands]) == summary$n_pos`; the manifest md5s equal the files on disk (so a damaged copy is caught at startup; CRLF normalization as a fallback with a warning).

### 4.3 The style object (`R/style.R`); `config/style/redtide.json` is the one adjustable file

```r
style <- list(
  units = "cells/L",                                              # bundle fact
  palette = list(colors = <chr[402]>, breaks_img = <dbl[403]>),   # from the bundle recipe (overridable)
  bands = list(breaks = c(0, 1e3, 1e4, 1e5, 1e6, Inf), columns = c("n_le1k", ...), sample_columns = c("s_le1k", ...),
               labels = c("<= 1k", "1k to 10k", "10k to 100k", "100k to 1M", "> 1M"),       # bundle facts
               colors = c("#FDE725", "#5DC863", "#21908C", "#3B528B", "#440154")),           # portal: viridis(5, direction = -1) as hex, line 259
  map = list(land = "wheat", sea = "white", placeholder = "darkgray", asp_lat = 27.5,       # portal; asp_lat is the #18 aspect, line 380
             colorbar = list(at = c(1e4, 1e6, 2e6, 3e6, 4e6), labels = c("10k", "1M", "2M", "3M", "4M"), title = "cells/L")),
  samples = list(zero_color = "gray45", zero_pch = ".", zero_cex = 1.8, pch = 21, cex = 0.6,  # portal; lines 392-397
                 legend = list(position = "bottomleft", cex = 0.48, title = "samples, cells/L")),   # line 404
  series = list(default = "exposure",                                                         # portal
                metrics = list(exposure = list(label = "Total exposure (million cells/L, summed over the 3,838 water cells)", divisor = 1e6),
                               n_ge10k = list(label = "Cells at or above 10k cells/L", divisor = 1),
                               km2_ge10k = list(label = "km2 at or above 10k cells/L", divisor = 1),
                               n_gt1M = list(label = "Cells above 1M cells/L", divisor = 1)),
                era = list(hull = c("gray40", 0.12), MODIS = c("steelblue", 0.18), VIIRS = c("gold", 0.22)),   # adjustcolor() recipes, plot_summary_issue5.R:37
                line = "purple3", month_line = "red"),
  labels = list(use = c(hybrid = "VIIRS + hulls nearshore", viirs = "VIIRS", hybrid_modis = "MODIS + hulls nearshore",
                        modis = "MODIS", pred = "hulls (no satellite coverage)"),             # portal display labels of the bundle's use codes
                fit_status = c(fitted = "fitted", failed = "fit failed", none = "no fit")),
  sizes = list(main = c(w = 1200, h = 1000, res = 150), thumb = c(w = 320, h = 270, res = 96),
               hist = c(w = 600, h = 400, res = 120), samples = c(w = 800, h = 670, res = 120),
               series = c(w = 1800, h = 420, res = 120), dashboard = c(w = 16, h = 10, res = 150), export = c(w = 2400, h = 2000, res = 300)),
  text = list(cex_main = 1.1, cex_info = 0.8, cex_pts = 0.6, font_family = ""),
  fmt_n = function(x) format(x, big.mark = ",", trim = TRUE, scientific = FALSE),   # clip_months_hybrid_issue18.R:131
  fmt_big = function(x) ...)   # 950 -> "950", 12,345 -> "12.3k", 310,492,554 -> "310.5M"
```

`style_from_bundle()` turns `style.json` into the `units`, `palette`, `bands` (without colors) and `codes` entries; `merge_style()` lays the product's JSON file over it, so the portal file both supplies every presentation key and may override a fact for display (a different colorbar range, for instance) without touching the bundle. `palette_of()` builds `colorRampPalette(anchors, bias)(401)` plus `above` from the recipe, or takes `colors_hex` as given (the `ramp` type is the only one in 1.0). `style_hash(style, sizes)` is the first 8 hex characters of the md5 of the canonical JSON of `list(plot_version = PLOT_VERSION, style, sizes)` via `tools::md5sum` on a temp file; the bundle commit is not part of it (section 6).

---

## 5. Shiny architecture for Part 1

### 5.1 Modules (`mod_<x>_ui(id, ...)` / `mod_<x>_server(id, product, month, ...)`; `month` is `list(yrmo = reactive, index = reactive)`)

| module | server | what it does |
|---|---|---|
| `mod_month` | `mod_month_server(id, months, site)` returns `list(yrmo, index)` | the slider is built by `renderUI` so the play speed is a user control: `sliderInput(idx, 1..n, step = 1, ticks = FALSE, animate = animationOptions(interval = input$speed, loop = TRUE))` rebuilt (at the current index) when the `selectInput("speed")` changes between `site$speeds_ms` (labels "slow / normal / fast", default `site$play_interval_ms`); buttons first / prev / next / last; the month label ("September 2018") as large text; `input$key` from `www/keys.js` (ArrowLeft, ArrowRight, Home, End step or jump through `updateSliderInput`; Space clicks the slider's own play button). `months` is the product's `viewer_months` (placeholders excluded, D16); any character vector of `yrmo` works, so a shared control later takes a union. Shiny's built-in animate gives play, pause and the interval; no server play loop |
| `mod_map` | `mod_map_server(id, product, month)` | `renderUI(tags$img(src = cache_url(product, "main", yrmo), class = "map-img"))`; no R graphics |
| `mod_thumbs` | `mod_thumbs_server(id, product, month)` | two images, `thumb/<prev>.png` and `thumb/<next>.png`, `placeholder_thumb.png` at the ends of the viewer months (1985-01 has no previous; the last data month has no next) |
| `mod_bands` | `mod_bands_server(id, product, month)` | `hist/<yrmo>.png` (pre-rendered, fixed record-wide y axis so bars are comparable during play; confirmed or changed at checkpoint I); hidden when `style$bands` is NULL |
| `mod_samples` | `mod_samples_server(id, product, month)` | `samples/<yrmo>.png` (panel D: zero-count samples as gray dots, positive samples as class points, the count box, the class legend); hidden when `product$samples` is NULL |
| `mod_series` | `mod_series_server(id, product, month)` | the once-rendered `series_<metric>.png` inside a `div.series-wrap` (position: relative) with a `div.month-line` whose `left` percentage is computed by `renderUI` from `series_geometry.json` (`x0 + (index - 0.5) / n * (x1 - x0)`, `n` the viewer months); a `selectInput` for the metric swaps the image |
| `mod_info` | `mod_info_server(id, product, month)` | `renderUI` definition list from `product$info(row, product)` (5.5) |
| `mod_product` | `mod_product_server(id, product, month, site)` | composes the panels named in `product$panels`; sends the `preload` message with the next 24 and previous 6 months' URLs after every change |

### 5.2 UI layout (bslib `page_navbar`, one `nav_panel` per product, `layout_columns`)

```
+---------------------------------------------------------------------------------------------+
| Red Tide Maps                                                        [Maps]  [About]        |
+---------------------------------------------------------------------------------------------+
| [|<] [<]  1985-01 |============================o==========================| 2026-10 [>] [>|] |
| [play]  speed [normal v]                   September 2018                                    |
+----------------------------------------------------------------+----------------------------+
|                                                                | C  cells by band (PNG)     |
|   A  red tide map 2018-09 (PNG from the cache)                 |    five bars, k/M labels   |
|      pipeline palette, wheat land, count box with exposure     +----------------------------+
|      first, color bar 10k to 4M                                | D  FWC samples 2018-09     |
|                                                                |    (PNG) zero dots, points |
|                                                                |    by band, count box,     |
|                                                                |    class legend            |
|                                                                +-------------+--------------+
|                                                                | E  2018-08  | F  2018-10   |
|                                                                |    (thumb)  |    (thumb)   |
|                                                                +-------------+--------------+
|                                                                | Key information            |
|                                                                | method: VIIRS + hulls      |
|                                                                |   nearshore (32 cells      |
|                                                                |   changed)                 |
|                                                                | exposure: 310.5M cells/L   |
|                                                                | positives: 648 ...         |
+----------------------------------------------------------------+----------------------------+
| B  total exposure 1985-01 to 2026-10 (PNG once per metric), red month line   metric [exposure v]
|    year ticks major, month ticks minor; era shading hull / MODIS / VIIRS                     |
+---------------------------------------------------------------------------------------------+
| Data: RedTideMaps @ 4fee1c9 (fetched 2026-11-10) . maps built 2026-11-05 . FWC samples       |
| through 2026-10-21 . schema 1.0 . render a1b2c3d4 . attribution                              |
+---------------------------------------------------------------------------------------------+
```

`layout_columns(col_widths = c(8, 4), card(A), layout_columns(col_widths = 12, card(C), card(D), layout_columns(c(6, 6), card(E), card(F)), card(info)))` above `card(B)`; C and D have fixed heights so the map keeps its size.

### 5.3 Reactive flow

`month <- mod_month_server("month", months = product$viewer_months, site)`; every other module observes `month$yrmo()` (never the slider index), which is what lets a shared control later drive products with different month lists. The product object is built once at startup outside `server` (shared across sessions). Per month change, one Shiny flush: four `renderUI` image tags, one `renderUI` line position, one `renderUI` info box. No `renderPlot` runs per month in Part 1.

### 5.4 Serving the pre-rendered PNGs and preloading

`shiny::addResourcePath("cache", "cache")` at startup; URLs are `cache/redtide_5min/<key8>/main/201809.png`. The style key in the path makes every URL immutable, so browser caching is safe and a restyle is a new URL set (no query-string cache busting needed). Static paths, not `renderImage` (whose one-off URLs defeat caching). `www/preload.js` (about 20 lines) keeps a `Set` of preloaded URLs and creates `new Image()` objects on the `preload` message (the next 24 and previous 6 months, about 1.7 MB, which covers play and stepping). The full walk of the record (502 viewer months x about 57 KB for the four panels, about 29 MB per session) runs only when `site$preload_all` is TRUE: FALSE in both tracked presets (a public host would pay it per visitor), TRUE in `config/active.R` for local use; it walks in `requestIdleCallback` chunks after 3 s idle and stops on a `pause` message. `ensure_cache(product)` at startup returns the key directory if its `cache_info.json` matches the current hash; otherwise it warns and `cache_url()` renders a requested month on first use (`render_month()`, about 150 ms), so a missing cache slows the first view but never breaks a deploy. For a shinylive host, `site$img_base_url` replaces `cache/` by a static URL (a shinylive export bundles the app folder into the browser, so 29 MB of PNGs must live on a static host).

### 5.5 What renders live, the key-information box, and expected frame time

Live in R: nothing per month during play. The info box is text: month; method (`style$labels$use[use]`, plus "N cells changed by the nearshore hull fill" when `hybrid_changed`, and "hull footprint spans N km (flagged)" only when `hull_flagged` is TRUE, the pipeline rule, so a satellite month such as 2018-09 never shows it); fit status and convergence; FWC samples (n, positives, samples >= 10k and how many the map includes); total exposure first (`fmt_big` with the full number in a `title` attribute); positive cells; the five bands; cells >= 10k and their km2; maximum and its cell's lon/lat. Placeholder months are not offered by the viewer (D16), so there is no placeholder notice; the footer's "FWC samples through <date>" says where the data ends.

Per frame: one WebSocket round trip (5 to 20 ms locally), the six `renderUI` outputs (10 to 20 ms), DOM update and decode of preloaded images (5 to 10 ms): about 30 to 60 ms on Holden's machine, so the default 200 ms interval (5 frames per second) has margin and the 100 ms "fast" setting is possible locally; on a remote host add its latency (ASSUMPTION; measured at step P5 with a `--profile` print of the flush time). If a host's latency makes play stutter, the escalation is a client-side controller (image `src` swaps, the CSS line and the info box driven from an embedded summary JSON by `www/month-control.js`, with the server receiving the index throttled): zero round trips per frame, same cache, same modules; not built in Part 1.

### 5.6 Composition for side-by-side products later

`app_server` builds one `mod_month_server` over `union_months(products)` (ascending union of the products' viewer months), then `mod_product_server(p$id, p, month, site)` for each product inside `layout_columns(col_widths = rep(12 / n, n))`; a product lacking the selected month shows its placeholder images; each info box follows its own product. Nothing in the Part 1 modules refers to red tide or to the slider index, so this is a layout change, not a module change.

---

## 6. Pre-render build step

### 6.1 Script

`Rscript scripts/prerender.R <product_id> [--force] [--prune]`: sources `R/`, loads the product, computes `key8 = style_hash()`, creates `cache/<bundle_id>/<key8>/{main,thumb,hist,samples}/`, renders `placeholder_main.png` and `placeholder_thumb.png` once, `series_<metric>.png` and `series_geometry.json` once per metric (the x axis spans the viewer months), and then, per year, compares the year's content md5 (`tools::md5sum` of `values/<layer>/<yyyy>.csv`, of the year's rows of `summary/<layer>.csv` and of `samples/fwc_<yyyy>.csv`, written to a temp file) with `manifest.csv` (`year, content_md5, rendered_at, n_png`); it renders the viewer months of every year whose md5 changed or whose files are missing (placeholder months are skipped), rewrites the manifest and `cache_info.json` (key, style md5, PLOT_VERSION, sizes, bundle commit, rendered_at), and prints the timing. `--force` re-renders everything; `--prune` deletes key directories other than the current one.

### 6.2 Functions lifted from `clip_months_hybrid_issue18.R` into `R/plot_*.R` (no globals: every former global becomes an argument or a field of `geometry`, `palette`, `style`)

| new signature | lifted from | change |
|---|---|---|
| `to_z(v, ncols, nrows)` | line 248 | `nc`, `nr` become arguments |
| `map_geometry(grid, cells, style)` | lines 248, 328-332 | `xs <- xllcorner + (seq_len(ncols) - 0.5) * cellsize`, `ys` likewise, `land_z <- to_z(ifelse(!cells$water, 1, NA))`, `xlim`, `ylim` from `meta$grid$extent`, `asp` from `style$map$asp_lat` |
| `band_counts(v, breaks)` | `class_counts`, 262-266 | returns `c(n_pos, five bands)` named by `style$bands$columns` |
| `exposure_of(v, water)` | 268 | `water` argument |
| `map_info_lines(row, style)` | `map_info`, 267-270 | from the summary row: exposure first, then positives and the five bands with k/M labels |
| `draw_colorbar(palette, cb, xlim, ylim, cex)` | `colorbar_legend`, 365-376 | palette, ticks and labels from arguments |
| `draw_map(v, geometry, palette, style, main = "", info = NULL, pts = NULL, cbar = TRUE, placeholder = NULL, cex_main, cex_info, cex_pts)` | `draw_panel`, 377-403 | the `outline`, `outline2` and `used` arguments dropped (section 10 keeps them out until a product needs them) |
| `draw_sample_points(pts, style, cex_pts)` | 392-398 | zero-count samples as `style$samples$zero_*` dots, positives as `pch 21` points filled by band (`cut(cells, breaks, include.lowest = TRUE)`, the right-closed bands) |
| `draw_sample_legend(style, cex)` | `sample_legend`, 404-405 | position, `cex` and title from `style$samples$legend`; labels `style$bands$labels`, fills `style$bands$colors` |
| `draw_samples(pts, geometry, style, main)` | panel A of `draw_row`, 414-419 | panel D: the land bitmap, the zero dots, the class points, the count box (`info_lines(class_counts(p$cells))`: samples, positives, five bands) and the class legend; "no samples" placeholder when the month has none |
| `draw_bands(row, style, ymax, main)` | new | `barplot` of the five counts in `style$bands$colors`, counts printed above the bars |
| `draw_series(summary, style, metric, months)` | new; axes and shading as `plot_summary_issue5.R:53-66` | over the viewer months: era rectangles by `use`, VIIRS zero/missing marks, January ticks labeled by year (every year; every fifth label when the panel is narrow), minor month ticks (`axis(1, tck = -0.01, labels = FALSE)`); returns `series_geometry()` = `list(x0, x1, y0, y1)` from `grconvertX(c(0.5, n + 0.5), "user", "ndc")` |
| `draw_dashboard(product, yrmo)` | new | `layout()` of A to F plus the info text on one device: the static test product (step P3) and the Part 2 export |
| `render_png(file, w, h, res, expr)` | `png_open`/`png_done`, 473-476 | writes `<file>_tmp.png` then renames; `ragg::agg_png` if installed else `png(type = "cairo")` |

Every function draws on the current device and reads nothing from disk; `PLOT_VERSION <- "1"` in `R/plot_map.R` is bumped on any visual change and is part of the hash.

### 6.3 Sizes and run time

| image | pixels | res | note |
|---|---|---|---|
| main | 1200 x 1000 | 150 | measured: 54 ms draw + 24 ms encode, 29 KB with ragg |
| thumb | 320 x 270 | 96 | map only, month as title; about 4 KB, 16 ms |
| hist | 600 x 400 | 120 | about 6 KB, 20 ms |
| samples | 800 x 670 | 120 | about 18 KB, 30 ms |
| series | 1800 x 420 | 120 | once per metric |
| dashboard (step P3) | 16 x 10 in | 150 | about 150 KB |
| export (Part 2) | 2400 x 2000 | 300 | the same functions, other arguments |

About 150 ms per month for the four panels: 502 viewer months in 75 to 90 s with ragg (ASSUMPTION: up to twice that on the cairo device), 29 MB per product. A monthly update re-renders one or two years: 2 to 5 s. A restyle re-renders everything into a new key directory.

### 6.4 Adjusting aesthetics

One file: `config/style/redtide.json` (every presentation key of 4.3, including sizes and text, plus any override of a bundle fact for display). Look at one month with `Rscript scripts/render_dashboard.R redtide 201809 hoard/`, then `Rscript scripts/prerender.R redtide`; the new key means a new URL set, so no browser shows a stale image. The bundle's `style.json` is not an aesthetics file: it changes only when the pipeline's own palette or the band convention changes, with a schema version note.

---

## 7. Fetch and update flow

### 7.1 `scripts/fetch_bundle.R <bundle_id> [--commit <sha>] [--github] [--allow-dirty]`

1. Reads `config/products.R` for `source$repo`, `source$path`, `source$branch`, and `config/local.R` for `redtidemaps_dir` if present.
2. Local mode (default when `redtidemaps_dir` exists and `--github` is not given): `git -C <dir> rev-parse HEAD`; refuses when `git -C <dir> status --porcelain -- <path>` is not empty unless `--allow-dirty`, which records `commit = "<sha>-dirty"`; asserts `meta.source.ascii_commit` is an ancestor of that HEAD (`git merge-base --is-ancestor <ascii_commit> HEAD`; a bundle older than the maps or from another branch is refused); recomputes the LF md5s of the clone's `out/<res>min/ecospace_ascii/` and refuses when they differ from `ascii_md5.csv` (the bundle does not describe the maps beside it: rerun the stage); copies the bundle folder to a temp folder.
3. GitHub mode (`--github`, or no local clone): `--commit <sha>` is the documented reproducible path (the sha of a RedTideMaps `data:` commit, printed by step 1 of 7.3); without it the script resolves the branch head from `https://api.github.com/repos/<repo>/commits/<branch>` (one API call, far below the unauthenticated limit) and prints the resolved sha; downloads `manifest.csv` from `https://raw.githubusercontent.com/<repo>/<sha>/<path>/manifest.csv`, then every listed file (about 96 files, `utils::download.file(method = "libcurl")`, 20 to 60 s) into a temp folder. Manifest-first, so no tree or contents API call is needed; the ASCII md5 check is skipped (it would mean downloading 10.6 MB), the pinned commit stands for it.
4. Verifies every md5 against `manifest.csv` (LF-pinned, so the md5s hold for a local copy, a fresh clone and a raw download alike; as a fallback it normalizes CRLF to LF before hashing and prints that it had to); checks `schema_version` major 1; replaces `data/<bundle_id>/` with a rename-aside (`data/<bundle_id>` to `data/<bundle_id>.old`, the temp folder in, the old one unlinked with its return value checked), so files not in the manifest disappear.
5. Writes `data/<bundle_id>/FETCH.json`: `{bundle_id, source_repo, source_path, commit, mode, fetched_at, n_files, bytes, md5_ok, ascii_commit, ascii_md5_checked, previous_commit}`.
6. Prints what changed against the previous copy: files added, removed, modified; the months whose `summary` rows changed; the new `last_data` month and FWC sample end date.

### 7.2 What gets committed in WFS-Portal

`data/<bundle_id>/` including `FETCH.json`, message `data: redtide_5min from RedTideMaps@<sha7> (FWC samples through <date>)`. Never the cache (3.3, section 11).

### 7.3 The monthly update, three steps, what stays manual, and the later wrapper

1. RedTideMaps: `Rscript run_redtide_maps.R` (about 9 min, step 9 included); read the log's `Hulls:` and `Bundle` lines; restore the plots PDFs if only their date lines changed, or commit them; commit `data:` with `out/5min/ecospace_ascii/`, `out/5min/plots/`, `out/5min/bundle/` in one commit (so the bundle's `ascii_md5.csv` and the ASCII it describes share a sha); push; note the sha.
2. WFS-Portal: `Rscript scripts/fetch_bundle.R redtide_5min` (local mode, or `--github --commit <sha>`); `Rscript scripts/prerender.R redtide` (seconds); `Rscript -e 'testthat::test_dir("tests/testthat")'`; commit `data:`; push.
3. Deploy: `rsconnect::deployApp()`, or copy the folder to the server, or the host's git hook (the only host-specific step; none chosen in Part 1, D18).

What stays manual today, against the issue's automation aim: the pipeline is not unattended. VIIRS tifs are added by hand (the tracked stack ends 2024-12, README line 61); MODIS polygons refresh only with `update_modis = TRUE` (they end 2025-09); the FWC pull (`fwc_refresh`) and the incremental sdmTMB fits are automatic; the `Hulls:` line wants a human look when a month is flagged; both `data:` commits and the deploy are by hand. Part 1 changes none of that; it makes the chain scriptable. `scripts/update.R` (later) would run step 2 end to end and, given `deploy_cmd` in `config/local.R`, step 3; it would not run the RedTideMaps pipeline or its commit (those stay in RedTideMaps), add VIIRS tifs, decide a MODIS refresh or review the hull flags. A scheduler (Task Scheduler on Holden's machine, or a GitHub Action running the cold pipeline, about 20 min) running the RedTideMaps driver followed by `update.R` is the parked issue "Schedule the monthly run" (section 10).

### 7.4 Showing the bundle commit in the app

Footer and About: `Data: RedTideMaps @ <FETCH commit, 7 hex>[ (uncommitted changes)] (fetched <date>) . maps built <meta build.built_at date> . FWC samples through <meta samples.date_to> . schema <version> . render <key8>`, the commit linked to `https://github.com/WFS-FEM/RedTideMaps/tree/<sha>/out/5min/bundle`. The FETCH commit is the one to reproduce from (`fetch_bundle.R --github --commit <sha>`); `meta$source$ascii_commit` (the About panel shows it too) is the last commit that changed the maps.

---

## 8. Tests and checks

### 8.1 RedTideMaps: `docs/issue23_portal-bundle/check_bundle_issue23.R`

Run from the repo root (`.root` detection as `plot_summary_issue5.R:15-23`, two levels up); reads only the run on disk, the tracked tables and the bundle; writes its tables and figures byte-identically on rerun (no RNG). It never sources the driver: it sources `scripts/_setup.R` and `scripts/write_bundle.R`, takes `cfg` and `res` from the tracked bundle's `meta.json` (`cfg <- c(meta$cfg, meta$build$toggles)`), and builds its file list from `rt_paths()` plus the newest `*_filtered.Rdata` as `clip_months_hybrid_issue18.R:89-112` does. `RT_QA_STAGE` = `frozen` (default) or `rerun`; `RT_QA_RES` = 5 (at 15 the #18 comparisons, steps 1, 4 and 5, are skipped with a message because those tables exist at 5 arcmin only, and the rest runs against `out/15min/`, D17); `RT_QA_BUNDLE_DIR` names a bundle to check instead of the tracked one. It refuses to run while `out/<res>min/bundle_tmp/` or `bundle_old/` exists.

Stage `frozen`, in order:

1. Gate: the 504 working-tree ASCII md5s equal `tables/md5_refresh5_issue18.csv` (`clip_months_hybrid_issue18.R:199-204`, raw bytes as #18 computed them) sets `frozen = TRUE`; otherwise steps 4 and 5 are skipped with a message and the rest runs, so the script survives the first monthly refresh.
2. Files: the file set equals `manifest.csv` (`.gitattributes` included) and every md5 matches on disk; for the tracked bundle every md5 also equals `git show HEAD:<file>` piped to a temp file (the LF blob, independent of the working tree's line endings); no file contains a 0x0D byte; `ascii_md5.csv` equals `fn.md5_lf()` of the ASCII on disk and `meta$source$ascii_md5` equals the md5 of its strings (the staleness guard); `meta.json$grid` equals the template header; `grid.csv`: 5,148 rows, `water` equals the template, `km2` equals `raster::area()`, centers equal `xyFromCell()`, `nearshore` equals the 189 cells of `nearshore_set5_issue18.csv`, none in the Atlantic box; `months.csv` 504 contiguous months, placeholders 202611 and 202612.
3. Values: for every month the vector rebuilt from the year files is `identical()` to `scan()`'s parse of the ASCII with the `< -1e30` guard (text to text), `isTRUE(all.equal())` to `raster::values(raster::raster(<asc>))` with the same guard (the GDAL float32 reading, line 208) and to the normalized combined stack column (the #18 criterion, line 209); the row count equals `sum(n_pos)`; `fn.layer_summary()` recomputed from the ASCII equals `summary/redtide.csv` (consistency).
4. Summary vs `clip_class_counts_hybrid_issue18.csv`, all 504 months: `n_pos` and the five bands equal `final_n_pos, final_n_le1e3, final_n_1e3_1e4, final_n_1e4_1e5, final_n_1e5_1e6, final_n_gt1e6` exactly; `abs(exposure - final_exposure) <= 1e-3` (the tolerance rule; measured maximum 1.2e-9); `use, hybrid_changed, fit_status, viirs_status` equal and `sat_src` derived as `c(hybrid = "viirs", hybrid_modis = "modis", pred = "hull", viirs = "viirs", modis = "modis")[use]` (line 184) equal; `n_changed == final_n_changed` in every month (the relative-tolerance rule reproduces the FLT4S count); `n_samples_pos == fwc_n_pos` where not NA and `n_samples == 0` where NA; the sample bands equal `fwc_n_*`. Table `bundle_vs_issue18_issue23.csv`; assert all 504 rows equal.
5. Summary vs `record_months_issue18.csv`: `n_ge10k == n_ge10k_final`, `round(km2_ge10k) == km2_ge10k_final`, `n_ge100k`, `n_ge1M`, `round(max_cells) == max_cells_final`, `samples_ge10k`, `in_ge10k == in_ge10k_final` in 502 months; the two refreshed months 202609 and 202610 (`expected$refreshed`) are reported, not asserted. Table `bundle_vs_record_issue23.csv`.
6. Samples: the bundle rows equal the filtered rows with a non-NA count in `styr..enyr` (181,411; `identical()` on the exact doubles after sorting); per-month counts equal `summary$n_samples`.
7. Frozen counts asserted from an `expected` list and quoted in the #23 README: 504 months, 173 all zero, 54,375 positive cell-months, `use` 155 / 0 / 123 / 0 / 226, `hybrid_changed` 210, `converged` TRUE 328 / FALSE 3 / NA 173, `hull_flagged` TRUE exactly the ten months 199009, 199604, 199606, 199711, 199909, 200009, 200010, 200110, 200112, 200201 (the log's `Hulls:` list; the pipeline rule, not the 71 raw flags) and NA in 19 months, `placeholder` 2, the 2018-09 row of the facts. Figures `fig1_bundle_quicklook_issue23.png` (base `image()` on `to_z()` of the expanded vector, land from `cells$water`, points from the samples; the orientation test of lines 248-250) and `fig2_summary_record_issue23.png`.

Stage `rerun`: `fn.write_bundle(mode = "standalone")` called again into `hoard/rerun/` from the disk outputs with the cfg of the tracked `meta.json` (or `RT_QA_BUNDLE_DIR` pointing at the run's bundle); every file byte-identical to the tracked bundle except `meta.json`, whose difference is confined to `build.built_at`, `build.run_log`, `build.mode` and `source.*`, and `manifest.csv`'s `meta.json` row; no 0x0D byte in either copy. A `cfg` change between production runs is a legitimate `meta.json` difference and is not what this stage tests. Table `bundle_rerun_issue23.csv`.

### 8.2 WFS-Portal: `tests/testthat/` (`helper-source.R` sources `R/`; `Rscript -e 'testthat::test_dir("tests/testthat")'`)

The fixture `fixtures/mini_bundle/` (6 x 5 grid, 3 months: one all zero, one placeholder, one with samples; schema 1.0) is generated by `fixtures/make_mini_bundle.R`, a base-R script of about 60 lines that writes the files of 1.2 following `bundle-schema.md` (same names, columns, LF, manifest); its output is tracked and `test-bundle_read.R` asserts the fixture's manifest matches its files, so a hand edit without regeneration fails; a schema bump regenerates it.

| file | what |
|---|---|
| `test-bundle_read.R` | the fixture: dims, NA on land, zero fill, summary order, placeholder kept by the loader, schema major 2 refused, manifest consistent; with `data/redtide_5min` present (`skip_if_not`): 5,148 x 504, NA exactly on the 1,310 land cells, `summary$exposure["201809"]` equals 310492554.245117 within 1e-6, bands recomputed from `values` equal the summary in all months |
| `test-product.R` | `viewer_months()` drops the placeholder month of the fixture; `products_from_bundle()` on a two-layer toy bundle yields two products; `validate_product()` accepts a grid without the optional columns and refuses a missing required one |
| `test-summary.R` | `band_counts(c(NA, 0, 500, 1e3, 1e4, 10001, 1e5, 1e6, 2e6))` gives `n_pos 7` and bands `2, 1, 2, 1, 1` (right-closed: 1,000 in `<= 1k`, 10,000 in `1k to 10k`); `exposure_of()` ignores land; `map_info_lines()` puts exposure first with k/M labels; `fmt_n(1234567)` is "1,234,567"; `fmt_big(310492554)` is "310.5M" |
| `test-geometry.R` | `to_z()` on a 3 x 2 toy grid; `map_geometry()` centers equal `cells$lon/lat` |
| `test-plot.R` | `draw_map()`, `draw_bands()`, `draw_samples()` (with and without samples), `draw_series()` into `render_png(tempfile())` for a normal, an all-zero and a placeholder month: the file exists, is over 1 KB and has the requested pixel size (`png::readPNG` when installed); `draw_dashboard()` runs for the fixture; `series_geometry()` returns `0 < x0 < x1 < 1` |
| `test-style.R` | `merge_style()` overrides one key and keeps the rest; the presentation keys come from the portal file, the facts from the bundle; `style_hash()` is stable and changes with any key or with `PLOT_VERSION`; `palette_of()` yields 402 colors and 403 finite breaks |
| `test-cache.R` | `prerender_product()` on the fixture writes the four panels per viewer month (none for the placeholder) and the manifest; a second call renders nothing; changing one summary row re-renders that year; `ensure_cache()` renders a missing month lazily |
| `test-mod_month.R` | `shiny::testServer(mod_month_server, args = list(months = m, site = site), { session$setInputs(idx = 1); expect_equal(yrmo(), m[1]); session$setInputs(`next` = 1); expect_equal(yrmo(), m[2]); ... })`: prev/next clamp at 1 and n, Home/End keys, a speed change keeps the index |
| `test-mod_product.R` | `testServer` with the fixture product: the four image URLs contain the key and the month, the line percentage moves, the info output contains the method label and no hull line for a satellite month; a product without samples composes without the samples panel; a product with `bands = NULL` without the histogram |
| `test-fetch.R` | `verify_bundle()` on a temp copy: passes, fails when one file is altered, passes after CRLF normalization with a warning |

No screenshot tests.

### 8.3 Manual checklist for the app (recorded in `docs/issue1_part1-visualization/checklist.md`)

1. Start under 3 s with a warm cache. 2. Slider end to end without an R console error. 3. Play a full year at 200 ms without a dropped frame; DevTools shows images from cache and no XHR per frame; the speed select changes the interval. 4. Arrow keys, Home, End and Space work after a click anywhere in the page. 5. Thumbnails show the placeholder at 1985-01 (no previous) and at the last data month, 2026-10 (no next). 6. The month control and the series end at 2026-10; 2026-11 and 2026-12 are not offered (D16). 7. The 2018-09 box equals the #18 row: 310.5M cells/L (310,492,554), 648 positives, bands 0 / 0 / 127 / 450 / 71, 648 cells >= 10k over 49,160 km2, maximum 7,746,619 cells/L, "VIIRS + hulls nearshore", 32 cells changed, no hull-flag line, 525 positive samples of 1,026, 290 samples >= 10k with 289 inside the map. 8. The 2018-11 box: exposure 514.5M (514,537,038), 867 positives (0 <= 1k, 5 in 1k to 10k, 221 in 10k to 100k, 543 in 100k to 1M, 98 above 1M), 862 cells at or above 10k over 65,075 km2, maximum 10,097,242, 45 cells changed, 782 samples (500 positive), 294 samples >= 10k, all 294 inside the map. 9. 2022-12 shows "MODIS + hulls nearshore" and VIIRS tif missing. 10. 1985-01 shows "no samples" in D and an empty map. 11. 1990-09 (a hull-served, flagged month) shows "hulls (no satellite coverage)" and the "hull footprint spans N km (flagged)" line. 12. The metric select redraws the series and the line stays at the month. 13. Window resize keeps the layout. 14. The footer shows the fetched commit, build date and FWC date. 15. `config/active.R` sourcing `config/portal.R` changes the title to "WFS Portal"; without it the title is "Red Tide Maps" with no product tabs.

---

## 9. Part 1 step list with checkpoints

Holden works piecemeal: each checkpoint shows the evidence and the full diff of every commit it names before any of them is made, and each commit is approved separately. Local commands use `"C:/Program Files/R/R-4.5.1/bin/x64/Rscript.exe"` (Rscript is not on PATH; the READMEs keep the generic `Rscript`). Static test products come before any Shiny code. Never edit `run_redtide_maps.R` or a sourced script while a run is in progress.

**RedTideMaps, issue #23, branch `23-portal-bundle`**

| step | files | evidence at the checkpoint |
|---|---|---|
| 0. Fresh base: `git fetch --prune`, `git checkout main`, `git merge --ff-only origin/main` (to `4fee1c9`), branch `23-portal-bundle`; draft PR after the first commit | | the branch list; `gh issue close 22` as a duplicate (Holden's go-ahead; the command handed over if the classifier denies) |
| 1. Folder skeleton and schema | `docs/issue23_portal-bundle/{README.md, issue23-portal-bundle-plan.md, bundle-schema.md, .gitignore}`; `docs/README.md` row | A: the plan and the schema tables; Holden approves column names, the k/M labels, the layer layout, the provenance keys; commit `docs:` |
| 2. The stage, run standalone from the R console against the run on disk into `docs/issue23_portal-bundle/hoard/trial/` (no pipeline run) | `scripts/write_bundle.R`, `scripts/_setup.R` | B: the file list with sizes, `head()` of each table, the 2018-09 row beside the #18 row, the assertion log (including the CR scan and the read-back) and the timing; commit `feat:` |
| 3. Hook and config | `run_redtide_maps.R` (header, cfg, source line, `nearshore <- NULL`, step 9), `config.local.example.R`, `.gitignore` | C: `"C:/Program Files/R/R-4.5.1/bin/x64/Rscript.exe" -e 'invisible(parse("run_redtide_maps.R"))'` and the diff; commit `config:` |
| 4. The check, stage `frozen`, against `hoard/trial/` | `check_bundle_issue23.R`, its tables and figures | D: `bundle_vs_issue18_issue23.csv` all 504 equal, the record table with the two refreshed months flagged, the frozen counts printed, fig1 and fig2 PNGs previewed; commit `test:` |
| 5. Verification run with `cfg$fwc_refresh <- FALSE` in `config.local.R` (about 9 min; nothing edited meanwhile); then stage `rerun` with `RT_QA_BUNDLE_DIR=out/5min/bundle` against `hoard/trial/` | `config.local.R` (gitignored) | E: the log's `Step 9` and `Bundle` lines with the seconds and `ASCII commit 543bc8e` without the "modified" suffix; `git status` showing `ecospace_ascii/` unchanged, `out/5min/bundle/` new and the plots PDFs modified by their date lines only (restored); the rerun table all equal except the volatile keys; commit `data:` (E1), then `qa:` (E2) |
| 6. Docs and closure | `README.md`, `docs/README.md`, the #23 README results | F: the rendered README sections; commit `docs:`; PR marked ready; Holden merges; the three WFS-Portal issues (9.1) opened and linked from #23 |

**WFS-Portal, issue #1 "Part 1: visualization tool", branch `1-part1-viz` (issues #2 and #3 opened and parked)**

| step | files | evidence |
|---|---|---|
| P0. Holden creates `WFS-FEM/WFS-Portal` (public, MIT, empty README), clones to `C:/Repos/WFS-FEM/WFS-Portal`, adds it as a working directory for Claude Code | | |
| P1. Skeleton and fetch | `README.md`, `LICENSE`, `ATTRIBUTION.md`, `DESCRIPTION`, `.gitignore`, `.gitattributes`, `config/*`, `R/packages.R`, `scripts/check_packages.R`, `scripts/fetch_bundle.R` (local mode first), `docs/issue1_part1-visualization/{README.md, issue1-part1-visualization-plan.md, .gitignore}`; the fetched bundle | G: `FETCH.json`, `git status` of `data/`, the md5 and ASCII-md5 verification lines; commits `docs:` (G1), `feat:` (G2), `data:` (G3) |
| P2. Contract and tests | `R/bundle_read.R`, `R/product.R`, `R/style.R`, `R/geometry.R`, `R/summary.R`, `config/products.R`, `config/style/redtide.json`, `tests/testthat/{fixtures/make_mini_bundle.R, fixtures/mini_bundle/, test-bundle_read.R, test-product.R, test-summary.R, test-geometry.R, test-style.R}` | H: `test_dir` output; the printed product (dims, viewer months, memory, load time); the 2018-09 summary row; commits `feat:` (H1), `test:` (H2) |
| P3. Static test products, before any Shiny code | `R/plot_*.R`, `scripts/render_dashboard.R` | I: dashboard PNGs (A to F plus the info box on one page) for 2018-09, 2018-11, 2012-02, 2005-10, 2022-12, 1990-09 (hull-served, flagged), 1985-01 (empty) and 2026-10 (the last data month) in `docs/issue1_part1-visualization/figures/`; Holden judges the palette, the wheat land, the count box order, the k/M labels, the series ticks and shading, the histogram axis (fixed or per month), panel D (zero dots, class points, count box, class legend position and size); iterate the style file until approved; commit `feat:` |
| P4. Pre-render | `R/cache.R`, `scripts/prerender.R`, `test-cache.R`, `test-plot.R` | J: the timing and size report (`cache_info.json`), three sampled PNGs per panel type, a second run rendering nothing; commits `feat:` (J1), `test:` (J2) |
| P5. Shiny, map and month control only | `app.R`, `R/app_ui.R`, `R/app_server.R`, `R/mod_month.R`, `R/mod_map.R`, `R/mod_thumbs.R`, `www/keys.js`, `www/preload.js`, `www/portal.css` | K: Holden runs it locally, scrolls, plays at each speed; the flush time printed by `--profile`; commit `feat:` |
| P6. The remaining panels, one commit per panel | `R/mod_bands.R`, `mod_samples.R`, `mod_series.R`, `mod_info.R`, `mod_product.R`, `R/about.R`, `test-mod_month.R`, `test-mod_product.R` | L: the full layout; the manual checklist ticked in `checklist.md` with the 2018-09, 2018-11 and 1990-09 numbers; commits `feat:` (one per panel), `test:` |
| P7. Standalone, README, manifest dry run | `config/redtide.R` and `portal.R` exercised, `README.md`, `scripts/update.R` skeleton; `rsconnect::writeManifest()` dry run (no deploy, D18) | M: both titles; the manifest resolves; the footer shows the fetched commit, build date and FWC date; commits `docs:` (M1), `config:` (M2) |

### 9.1 Draft bodies for the WFS-Portal issues (opened at step 6, linked from #23; wording carried over from #23)

**#1 Part 1: visualization tool (Red Tide Maps)**

> Parent: WFS-FEM/RedTideMaps#23 (the producer side: the data bundle `out/5min/bundle/`, schema `docs/issue23_portal-bundle/bundle-schema.md`). This issue builds the interactive visualization tool for the 5-arcmin map products, as the first product of the portal and as the standalone "Red Tide Maps" app (same code, one product enabled).
>
> Panels (the layout sketched in the design, section 5.2): A, the main panel, the red tide map of the month (pipeline palette, wheat land, count box with the total exposure first, color bar 10k to 4M cells/L). B, underneath, the time series of total red tide exposure (y: map-summed cells/L; x: year-months with minor ticks at months and major ticks at years; a vertical line at the month shown; a metric select for cells >= 10k, km2 >= 10k, cells > 1M). C, a histogram of grid cells by band (<= 1k, 1k to 10k, 10k to 100k, 100k to 1M, > 1M cells/L; right-closed bands on positive cells, the convention of the RedTideMaps check scripts). D, the FWC cell counts of the month (zero-count samples as dots, positives colored by band, a count box, a class legend). E and F, thumbnails of the previous and next month. Key information for the month: the footprint clipping method (VIIRS + hulls nearshore, MODIS + hulls nearshore, hulls; cells changed by the nearshore fill; the hull-flag line for hull-served months), total exposure, positive cells and the counts behind the histogram, cells >= 10k and their km2, the maximum and its cell, fit status and convergence, FWC samples (n, positives, >= 10k, included by the map).
>
> Toggles: the month is controlled by a slider with first / previous / next / last buttons, keyboard arrows, auto-play with a speed select; panels are pre-rendered PNGs so scrolling and play are fast. Months after the last month with FWC samples are not offered (the bundle carries them as placeholders).
>
> Data: fetched from RedTideMaps at a pinned commit by `scripts/fetch_bundle.R`; the footer shows that commit, the build date and the FWC sample end date. Tasks: P1 to P7 of the design's section 9; definition of done: the manual checklist of section 8.3 ticked, `testthat::test_dir()` green, the 2018-09 and 2018-11 boxes equal to the #18 regression rows, `rsconnect::writeManifest()` resolving. No deploy in this issue (hosting undecided).

**#2 Part 2: export visualizations**

> Parent: WFS-FEM/RedTideMaps#23; follows #1. After the visualization tool, add user exports: (a) a single month or a range of months as PNG, TIFF or JPG (the dashboard or the map alone, at export size); (b) PDF printing of maps over a range of time, 12 months per page for user-defined years (the layout of `fn.plot_redtide_stack()`); (c) later, after (a) and (b) work, GIF animations over a user-defined range built from the cached map frames. Hooks already in place from #1: every drawing is a pure function of (data, geometry, palette, style) on the current device; `draw_dashboard(product, yrmo)` and `style$sizes$export` exist. Decisions for this issue: the `zip` package for ranges (`utils::zip()` needs an external binary on Windows), `gifski` or `magick` for the GIF. Every export prints a provenance line (bundle commit, build date, FWC date, schema).

**#3 Part 3: data portal**

> Parent: WFS-FEM/RedTideMaps#23; follows #1 and #2. The portal lets the user export maps and spreadsheets for a time domain (months of interest) and a spatial domain (the entire grid or a user-defined bounding box; the Atlantic box can be excluded on request). Downloads: the monthly summary table and the sample table as CSV; the map values as long CSV (yrmo, cell, value); ESRI ASCII per month (the pipeline's header and NODATA, in base R); GeoTIFF (via `terra` inside a download handler only, a dependency decision for this issue). Hooks already in place from #1: `meta.json$grid` carries the full ASCII header, `grid.csv` carries `lon, lat, km2, atlantic`, so a subset is a row filter and a column slice of the product's values matrix; `summary/redtide.csv` is already the downloadable table; `product$source` carries the provenance. Per-species downloads for the Ecospace products follow the same handlers once those bundles exist.

---

## 10. Hooks for Part 2, Part 3 and the Ecospace products

**What Part 1 does now so these are cheap later**

- Every drawing is a pure function of (data, geometry, palette, style) on the current device, and `draw_dashboard(product, yrmo)` exists from step P3: Part 2's PNG/JPG/TIFF export of a month is `render_png()` / `jpeg()` / `tiff()` (all in `grDevices`; `capabilities("tiff")` is TRUE here) around `draw_dashboard()` or `draw_map()` at `style$sizes$export`; a range is a loop and an archive built with the `zip` package (a Part 2 dependency decision; `utils::zip()` depends on an external binary that Windows R does not ship); the 12-months-per-page PDF is `pdf()` with `par(mfrow = c(4, 3))` around `draw_map()`, the layout of `fn.plot_redtide_stack()` (`polygon_clipping_rt.R:347-362`); the GIF takes the cached main PNGs as frames (`gifski::gifski()` or `magick::image_animate()`, chosen then) with no re-render.
- `meta.json$grid` carries the full ASCII header and `grid.csv` carries `lon, lat, km2, atlantic`, so a Part 3 subset is a row filter (centers inside the bounding box) and a column slice (`months$index` in range) of `product$values`; CSV long export is that slice; ESRI ASCII export is six header lines plus `cat()` of the row-major vector with the pipeline's NODATA, in base R; GeoTIFF needs `terra` only inside a download handler (a dependency decision for then). The `atlantic` flag lets Part 3 exclude the box on request.
- `summary/redtide.csv` is already the downloadable table; `product$source` carries the commits, FWC date and schema so every export can print a provenance line.
- Modules take (product, month) and key on `yrmo`; the product list and `mod_product` already handle N products under one control; product = (bundle, layer) and `products_from_bundle()` turn a 50-species bundle into 50 products without a new UI concept; the loader dispatches on `encoding`; the schema reserves the dense encoding and per-layer styles for the first Ecospace bundle.
- Parked issues, opened after Part 1 (not in #23): "Schedule the monthly run" (7.3); "Stop writing future placeholder months to the Ecospace deliverables" (D16's note: the ASCII drop and the ST drivers export should end at the last month with samples, a `make_redtide_ascii` / `enyr` change with its own check); "15-arcmin product" (one `cfg$res <- 15L` run; the check script already skips the #18 comparisons at 15); "Ecospace bundles" (volume: plain git vs LFS vs release assets; month range, units, precision, layer count).

**Not built yet**: download handlers and their UI, range and bounding-box inputs, map clicks, PDF, zip and GIF code, GeoTIFF and `terra`, a dense-encoding reader, per-layer style overrides, interactive (leaflet) maps, the client-side month controller, a bundle-to-bundle re-encode mode, per-user state, authentication or usage logging, host-specific code, renv.

---

## 11. Risks and open questions for Holden

Answered since the first synthesis (now fixed, from the plan file): the FWC samples are redistributed in the public bundle with attribution (D15); placeholder months are hidden in the viewer and kept in the bundle (D16); 5 arcmin only in #23 (D17); no deploy trial in Part 1, an rsconnect manifest dry run instead (D18).

Questions that still change the work:

1. **Track the PNG cache in WFS-Portal?** Gitignored (default): an upload-style deploy carries it, a git-backed deploy needs a prerender on the host or a tracked cache (about 30 MB of binaries rewritten on every restyle). Decided with the host (D1); nothing in Part 1 depends on it, so it can wait until a host is chosen.
2. **Attribution wording.** The text of 3.5 is shown in the app and in every export; Holden confirms it with FWC-FWRI and the USF Optical Oceanography Laboratory, and supplies the funding acknowledgment line, before the first public deploy.
3. **Ecospace bundle volume.** Dense species layers reach hundreds of MB as text; before the first Ecospace bundle: plain git, Git LFS, or GitHub release assets fetched by the same script, and the month range, units, precision and layer count of the runs. Changes nothing in Part 1.

Notes and risks (defaults chosen here): the issue text writes the first band as "<1k" while every check script uses right-closed bands (1,000 falls in the first band); the design keeps the right-closed definition and labels it "<= 1k". The standing regression check after the first real monthly rerun compares to the #18 tables only while the ASCII md5s match the frozen set and otherwise checks the bundle against the ASCII on disk (the gate of 8.1); restricting the #18 comparison to months before 2026-09 permanently is the alternative. Fonts differ between ragg (local), cairo (servers) and Noto (webR), so the info text in the count boxes stays short and sized by `cex`. The ASCII first-token quirk and the float32 reading of GDAL-based readers are documented in `SCHEMA.md` for third-party readers. The git calls in the stage fall back to reading `.git/HEAD` and `packed-refs` when git is not on the Rscript PATH (the ASCII keys then read `"unknown"` and the check script reports it). A leftover `out/5min/bundle_old/` after a failed swap must be deleted by hand; the check script refuses to run while it exists. `raster` stays the pipeline's package; the portal never loads it.

---

### Critical Files for Implementation

- `C:\Repos\WFS-FEM\RedTideMaps\run_redtide_maps.R` (cfg at lines 42-96, the source list at 140-146, `nearshore <- NULL` at line 260, the hull rule at 321-338, the step-9 block between lines 346 and 347)
- `C:\Repos\WFS-FEM\RedTideMaps\scripts\_setup.R` (`rt_paths()` lines 86-139, `rt_init_dirs()` 142-151, `rt_check_packages()` 17-24)
- `C:\Repos\WFS-FEM\RedTideMaps\scripts\polygon_clipping_rt.R` (`make_redtide_ascii()` 241-326: `use` values 275-278, normalization 287 and 307-308; the palette 339-343; the 4 x 3 PDF layout 347-362)
- `C:\Repos\WFS-FEM\RedTideMaps\docs\issue5_nearshore-hybrid-summary\subissues\issue18_implement-hybrid-clipping\clip_months_hybrid_issue18.R` (file list 89-112; readers and status rules 124-131, 161-193; the ASCII guard 208 and the md5 gate 199-204; counts and exposure 257-270; the panel functions 248, 323-332, 365-405; the refreshed-month exemption 68, 306-309; temp-then-rename 461-476)
- `C:\Repos\WFS-FEM\RedTideMaps\docs\issue5_nearshore-hybrid-summary\subissues\issue18_implement-hybrid-clipping\check_final_hybrid_issue18.R` (`load_samples`, `samples_of`, `expo_of` 204-242) with the regression targets `tables/clip_class_counts_hybrid_issue18.csv`, `tables/record_months_issue18.csv`, `tables/nearshore_set5_issue18.csv`, `tables/md5_refresh5_issue18.csv`
- New: `C:\Repos\WFS-FEM\RedTideMaps\scripts\write_bundle.R` and `C:\Repos\WFS-FEM\RedTideMaps\docs\issue23_portal-bundle\{bundle-schema.md, check_bundle_issue23.R}`
