# Workflow Review: RedTideMaps

## 0. How to read this document

This document is for someone who has to run, trust or maintain RedTideMaps without having written it: a new analyst, the operator doing the monthly rerun, or the author a year from now. It defines every technical term where it first appears and collects them in §10.4. Numbers sit in tables with their source beside them; the prose says what they mean.

Three documents describe this repository:

- `science-review.md` (Doc A): what the pipeline estimates and why, in research-article form; read it first if you need to interpret or cite the maps.
- this document (Doc B): how to set it up, what goes in, what each stage does, what comes out, how long it takes, and what was verified; read §1-2 to run it, §3-7 to trust it, §8-9 to maintain it.
- `draft-repo-audit-log.md` (Doc C): the audit record: every finding with its file and line, the recommended fixes, the decisions and the questions for the author; read it before changing code.

Line numbers refer to `main` at commit `a875d64`. Written 6 Oct 2026 in a review-only audit (no code was changed); the findings it cites are open items, not fixed ones. Last updated 6 Oct 2026.

## 1. The pipeline in one page

One command, `Rscript run_redtide_maps.R`, does everything. It pulls the FWC red-tide sample records from the state's public web API (or only the new ones, if a local copy exists), keeps the samples that fall on the West Florida Shelf grid, fits one small spatial statistical model per calendar month to the positive samples, predicts a concentration at every grid cell, cuts each month's prediction down to that month's bloom footprint (satellite-derived where a satellite product exists, otherwise polygons drawn around the positive samples), and writes one ESRI ASCII grid per month into `out/5min/ecospace_ascii/`. A monthly operator rerun repeats all of that; the model fits are cached per month so only new months are fitted.

| Stage | What goes in | What comes out | How long (30 Sept 2026 log, warm cache) | Where in the code |
|---|---|---|---|---|
| 1 Ingest FWC samples | six ArcGIS REST endpoints (`data/FWC HAB API query urls.txt`); existing merged CSV in `cell_counts/` if any | `cell_counts/FWC HAB data <from>-<to>.csv` and `.Rdata` (about 216,000 records) | 10 s incremental; about 3 min for a full pull (README, not measured here) | `scripts/get_HAB_data.R`, `fn.get_fwc_data()` |
| 2 Spatial filter and sample plots | merged Rdata; depth template | `out/5min/sdm/*_filtered.Rdata` (183,133 samples, 1980-2026); two PNGs in `plots/` | 22 s | `fn.filter_hab_data()`, `fn.plot_hab_data()` |
| 3 Monthly sdmTMB fits | filtered samples; prediction grid from the depth template | `out/5min/sdm/OM_month/<yyyymm>/fit_sdmTMBlog.RData` (334 months); `pred_SDMs_RT.RData`, `RT_fit_matrix.RData`, `pred_obs_RT.RData`, `fit_warnings.csv`; five diagnostic PNGs in `sdm/plots/` | 1 min 22 s with 0 months to refit; about 7 min cold (README, not measured here) | `scripts/sdmTMB_HAB_data.R`, `fn.fit_monthly_sdmTMB()` |
| 4 Predict to grid | `pred_SDMs_RT.RData`; depth template | `sdm/sdmTMB_log_stack_198501-202612.grd` (504 monthly layers); `plots/sdmTMB log maps.pdf` | 1 min 31 s | `fn.predict_monthly_sdmTMB()`, `fn.plot_sdmTMB()` |
| 5 Footprints and clipping | filtered samples; prediction stack; `VIIRS/*.tif`; `MODIS/FLH polys *.Rdata` | `sdm/*_hullpolys.Rdata`, `sdm/hull_diagnostics.csv`; `VIIRS/VIIRS_201201-202412.grd`; three clipped stacks in `clipped/` | 3 min 6 s | `scripts/polygon_clipping_rt.R`, `process_VIIRS.R`, `process_MODIS.R` |
| 6-7 Combine and write ASCII | three clipped stacks; depth template | `clipped/clipping_source.csv`; `combined/*_clipped_combined.grd`; 504 files in `ecospace_ascii/`; `plots/*_clipped_combined.pdf`; `Hulls:` line in the run log | 1 min 41 s | `make_redtide_ascii()`, `fn.plot_redtide_stack()` |
| 8 Export (opt-in) | `ecospace_ascii/` | copies into `<ecospace_root>/5min/red tide/sdmTMB/` | seconds | `export_to_ecospace()` |

Times are read from `out/5min/run_20260930.log` on the reviewer's machine (Windows 11, R 4.5.1, fits cached). The 6 Oct baseline (§9.1) is the measured record.

```
FWC API ──► merged CSV ──► spatial filter ──► monthly sdmTMB fits ──► prediction stack
                                 │                                          │
                                 ▼                                          ▼
                          buffered hulls ──────────────┐           clip to hull  ─┐
                          VIIRS tifs ──► VIIRS stack ──┼──► clip to VIIRS ────────┼──► pick VIIRS > MODIS > hull ──► ASCII per month
                          MODIS polys ─────────────────┘           clip to MODIS ─┘
```

## 2. Setting up and running

### 2.1 Software

Tested with R 4.5.1 on Windows 11 [README "Reproducibility"]. The spatial packages need GDAL, GEOS and PROJ, which the CRAN Windows binaries of `sf` and `terra` bundle; on Linux or macOS they must be installed first. Package versions on the reviewer's machine on 6 Oct 2026 are in §10.3 (sdmTMB 1.1.0, TMB 1.9.25, sf 1.0.21, raster 3.6.32, terra 1.8.80, concaveman 1.2.0).

Required packages (19, checked in the first second of a run): `sf`, `raster`, `terra`, `rnaturalearth`, `rnaturalearthdata`, `sdmTMB`, `lubridate`, `concaveman`, `cluster`, `ggplot2`, `viridis`, `scales`, `cowplot`, `ggh4x`, `maps`, `fields`, `rvest`, `httr`, `jsonlite` [`scripts/_setup.R:28-31`]. If one is missing the run stops with a message that contains the exact `install.packages()` line. Seven of the 19 are not called by the live code (Doc C P2): `lubridate`, `cluster`, `viridis`, `scales`, `cowplot`, `ggh4x`, `rvest`. `sp` is used but not declared; it arrives with `raster` (Doc C P4). Optional, only for `update_modis = TRUE`: `rerddap`, `curl`, `data.table`, `rasterVis`, `colorRamps` [`scripts/process_MODIS.R:18-27`]; `rerddap` is not installed on the reviewer's machine.

### 2.2 Configuration

Every setting lives in one list, `cfg`, at the top of the driver [`run_redtide_maps.R:38-71`]. To change one on your machine, do not edit the driver: copy `config.local.example.R` to `config.local.R` in the repository root (that file is gitignored, so it never reaches GitHub) and uncomment the lines you need. The driver reads it after building the defaults and before touching any input [`run_redtide_maps.R:80-84`], and prints "Applied local overrides from config.local.R" so the run log records that an override was in play.

| Key | Default | Purpose | When to change it |
|---|---|---|---|
| `res` | `5L` | Grid resolution in arc-minutes; templates exist for 5 and 15 | Only for the 15-min Ecospace variant |
| `styr`, `enyr` | `1985`, current year | First and last year modelled; every month in the range gets an ASCII file | Never for the production driver; note that `enyr` moves every January (Doc C R8) |
| `repo_dir` | detected | Repository root (the folder holding `RedTideMaps.Rproj`) | Never |
| `proj_dir` | `repo_dir` | Where `cell_counts/`, `VIIRS/`, `MODIS/` and `out/` live | If you keep the data and outputs outside the clone; then copy `VIIRS/` and `MODIS/` there too, or the cascade silently loses them (Doc C P1) |
| `bathy_dir` | `<repo>/template rasters` | Folder with the depth and exclusion templates | Rarely |
| `ecospace_root` | `NULL` | Root of the Ecospace "ST drivers" tree (on OneDrive for the reviewer) | Set it together with `export_ecospace` |
| `use_viirs`, `use_modis` | `TRUE` | Include the two satellite footprints | Sensitivity runs only |
| `update_modis`, `rebuild_nflh` | `FALSE` | Download new MODIS nFLH months from ERDDAP, then rebuild the polygons | When a new satellite month must be added (needs network and the optional packages) |
| `fwc_force_full` | `FALSE` | Ignore the local FWC cache and pull all six layers again (about 3 min) | After FWC corrects old records |
| `incremental_fit` | `TRUE` | Reuse cached monthly fits; delete `OM_month/<yyyymm>/` to force a refit | Set `FALSE` after an sdmTMB upgrade |
| `fit_nb` | `FALSE` | Also fit the negative-binomial model (not used downstream) | Diagnostics only |
| `export_ecospace` | `FALSE` | Copy the ASCII drop to `<ecospace_root>/<res>min/red tide/sdmTMB/`, which must already exist | Production runs on the modeller's machine |
| `hull_link_km` | `75` | Single-linkage cut: positives further apart than this, with no chain of closer positives, get separate footprints | 50 km is the sensitivity case from issue #3 |
| `hull_buffer_km` | `10` | Buffer around each footprint | |
| `hull_min_pts` | `4L` | Distinct locations a cluster needs for a concave hull; fewer get buffered points | |
| `hull_concavity` | `2` | concaveman concavity (lower is tighter) | |
| `hull_warn_span_km` | `300` | Footprint span above which a month is flagged in the log and diagnostics | |

The reviewer's own override (the only machine-specific value in play) sets `ecospace_root` to the OneDrive "ST drivers" folder and leaves `export_ecospace` off.

### 2.3 Entry point and run modes

The one file to run is `run_redtide_maps.R`. From the command line: `Rscript run_redtide_maps.R` in the repository folder, or `Rscript <full path>/run_redtide_maps.R` from anywhere (the driver finds its own folder from the `--file=` argument) [`run_redtide_maps.R:25-35`]. Interactively: open `RedTideMaps.Rproj` in RStudio and source the file. The two modes differ only in where messages go; all figures are written to files, no plot window is opened, and nothing prompts the user. A run that starts in the wrong folder stops immediately with a message that prints the current directory and says to open the project file.

The run writes an append-only log, `out/<res>min/run_<yyyymmdd>.log`, with one timestamped line per stage; a successful run ends with `Run complete.` and, just before it, a `Hulls:` line listing any hull-served months whose footprint spans more than `hull_warn_span_km`. Two runs on the same day append to the same log (Doc C B11).

### 2.4 The three run targets

| Target | Machine and layout | What it needs | Verified in |
|---|---|---|---|
| 1 The reviewer | Windows 11, R 4.5.1, clone at `C:/Repos/WFS-FEM/RedTideMaps`, `config.local.R` with the OneDrive Ecospace root, export off, fits cached from 30 Sept 2026 | Network for the FWC pull | §9.1 (baseline) |
| 2 The original author | In this review-only audit the reviewer is also the author; the original authors' layouts (Vilas, Chagaris) are not available and their real paths do not appear in the tracked code | A `config.local.R` with their Ecospace root | §9.3 (pending; not run in review-only mode) |
| 3 A fresh clone | Any OS with R ≥ 4.5 and the 19 packages; no data to place because every input is tracked or pulled | Network for the first FWC pull (about 3 min) and about 20 min for the first fits (README figures, not measured) | §9.3 (pending) |

### 2.5 What a first run prints

There is no input manifest or input-check table in this pipeline (Doc C P1). A first run prints the package check result (silent on success), the repository root it found, "Applied local overrides" if a local config exists, then the stage lines. The first stage prints "Fetching: <layer>" and record counts for each of the six FWC layers; a later run prints "Loading existing merged file" and "Last SAMPLE_DATE in local data". The fitting stage prints one banner per (year, month) and, at the end, "Fit summary: n newly fit, m reused from cache" and the number of captured warnings. A missing package, a missing template, a missing Ecospace export folder (when export is on) or an unreachable FWC endpoint stop the run with a one-line reason before any slow work, except the endpoint, which is checked at stage 1. Missing VIIRS tifs stop the run inside stage 5, after the fits; missing MODIS polygons are skipped with one log line and the affected months fall to the hull path.

## 3. Data inputs

Every input the pipeline reads, in the order it reads them. "Vintage" is how to tell which version of an input you hold.

### 3.1 FWC HAB cell counts (pulled on every run)

**What it is.** The Florida Fish and Wildlife Conservation Commission's harmful-algal-bloom monitoring records: one row per water sample with date, position, depth and the *Karenia brevis* concentration in cells per litre (`COUNT_`). The state serves them as six ArcGIS REST map layers (1980-1989, 1990-1999, 2000-2006, 2007-2014, 2015-2023, 2024-present), listed one per line in `data/FWC HAB API query urls.txt`. Public.

**How it is obtained.** Automatically. On a first run (or with `fwc_force_full = TRUE`) all six layers are paged through, 2,000 records per request, and merged [`scripts/get_HAB_data.R:30-80,133-141`]. On every later run the newest merged CSV in `cell_counts/` is read, its last `SAMPLE_DATE` taken, and only the layer whose URL contains `Recent_` is queried for records on or after that date; the new rows are appended, the table is de-duplicated on (HAB_ID, OBJECTID, SAMPLE_DATE, LATITUDE, LONGITUDE), keeping the first occurrence, and written back under a new name carrying the full date range. The previous CSV and Rdata are deleted [`:118-131,146-169`].

**Size and location.** `cell_counts/FWC HAB data <yyyymmdd>-<yyyymmdd>.csv` (33 MB) and `.Rdata` (4 MB), under `proj_dir`. Gitignored. The reviewer's copy on 6 Oct runs 1980-01-02 to 2026-09-22 (the baseline pull advanced it from 09-17).

**Which stages read it.** Stage 1 writes it; stage 2 reads the Rdata (object `hab.out`).

**Without it.** No cache: a full pull (network, about 3 min). No network: `httr::GET()` fails and the run stops at stage 1 with the HTTP status or a connection error. There is no offline mode (Doc C R2).

**Vintage and drift.** The file name is the only vintage record; the API serves the current compilation, so two full pulls on different days can differ for any year. Corrections to records already cached are not picked up by an incremental pull (README "Known limits"; Doc C R3). Reference counts: about 216,000 records after a full pull (README); 183,133 after the spatial filter on the 30 Sept data.

### 3.2 VIIRS monthly red-tide frequency rasters (tracked)

**What it is.** Monthly rasters at 0.1° (65 columns by 55 rows over the WFS box) giving the frequency of red-tide detection from the VIIRS satellite sensor, produced by the USF Optical Oceanography Laboratory with NOAA (README cites Hu et al. 2015 and Yao et al. 2023). Values 0 to 0.99; land is NA. The files carry no georeferencing of their own (extent 0-65 by 0-55, no coordinate system), so the code assigns the WFS box (87.5°W to 81°W, 25°N to 30.5°N) and flips them vertically [`scripts/process_VIIRS.R:36-38`]. A PNG preview accompanies each.

**How it is obtained.** Ships in the repository: `VIIRS/redtide_maps_0.1degree/<yyyy>_<mm>_month_frequency_noaa_resize.tif`, 155 files, 2.2 MB in all. No download code; the original URL is not recorded.

**Coverage.** 2012-01 to 2024-12 except 2022-12, whose TIF is missing although its PNG is present (Doc C R1). Months after 2024-12 have no VIIRS product and fall to MODIS or the hull.

**Which stages read it.** Stage 5b stacks all tifs into `VIIRS/VIIRS_<first>-<last>.grd` (rebuilt on every run, gitignored) and clips the prediction.

**Without it.** `use_viirs = FALSE` skips it cleanly. With the toggle on and the folder empty, the run stops inside stage 5 ("No VIIRS tifs found under ...") after the fits and predictions have already run.

**What a zero layer means.** 89 of the 155 months have no positive cell. For those months the final map is all zero whatever the samples show (Doc C M1).

### 3.3 MODIS nFLH bloom polygons (tracked)

**What it is.** Per-month polygons of where MODIS Aqua normalised fluorescence line height (nFLH) was at or above 0.02 mW cm⁻² µm⁻¹ sr⁻¹, the bloom threshold from Hu et al. 2005 as updated by personal communication [`scripts/process_MODIS.R:11-13`]. One R object, `flh.polys`, a named list of `SpatialPolygonsDataFrame` objects in WGS84.

**How it is obtained.** Ships as `MODIS/FLH polys 200207-20250926.Rdata` (3 MB). It can be rebuilt: `update_modis = TRUE` downloads the raw monthly nFLH stack from NOAA CoastWatch ERDDAP (needs network and the five optional packages; the raw stack is gitignored, so the first update pulls everything since 2002), and `rebuild_nflh = TRUE` thresholds it into polygons [`scripts/process_MODIS.R:37-168,222-270`]. Not exercised in this audit.

**Coverage.** 275 months from 2002-07 to 2025-09; 2006-04, 2016-06, 2024-11 and 2024-12 are absent (Doc C R1). 2006-04 is therefore a hull month; the other three are VIIRS months.

**Which stages read it.** Stage 5c clips the prediction for every month present in the list.

**Without it.** With `use_modis = TRUE` and no file matching `^FLH polys` under `proj_dir/MODIS/`, the run logs "No FLH polys found; skipping MODIS clipping." and continues; every month 2002-07 to 2011-12 and 2025-01 to 2025-09 then comes from the hull path. If several files match, the alphabetically first is used without comment (Doc C R5).

### 3.4 Grid templates (tracked)

**What it is.** ESRI ASCII rasters of depth and of an exclusion mask on the Ecospace grid, one pair per resolution (4, 5, 6, 10, 15 arc-minutes), in `template rasters/`. The 5-min depth template has 66 rows by 78 columns, lower-left corner at 87.5°W, 25°N, cell size exactly 1/12 degree, no-data -9999, and 1,310 land cells. Their origin (the Ecospace basemap repository, presumably) is not recorded.

**How it is obtained.** Ships in the repository (324 KB in all). `bathy_dir` points at the folder.

**Which stages read it.** Every stage: the depth template defines the sample filter box (stage 2), the prediction grid (stage 3), the raster template (stage 4), the land mask (stages 5-7) and the ASCII header. The exclusion template is located, logged and passed to `fn.make_input_grid()`, which ignores it (Doc C D6).

**Without it.** `rt_paths()` stops before any work: "No depth template found in ... matching 'depth 5min *.asc'".

### 3.5 FWC endpoint list (tracked)

`data/FWC HAB API query urls.txt`: six URLs, one per line; blank lines and `#` comments are ignored. The substring `Recent_` marks the layer used for incremental pulls. Missing: stage 1 stops with "URL file not found".

### 3.6 Coastline (package data)

`rnaturalearth::ne_countries(country = "united states of america", scale = "medium")` supplies the land polygons used only to draw the sample-location figure [`scripts/get_HAB_data.R:259-270`]. It needs `rnaturalearthdata` installed, which the package check enforces.

### 3.7 Tracked files that are not inputs

`data/habsos_20240430.csv` (29.9 MB), `data/habsos_20240430_example.csv` and `data/1985-2025.09.09 WFS Kb and environmental data.xlsx` (2.1 MB) are tracked but read by no live code; the HABSOS reader exists only in the never-called `fn.get_habsos_data()` and the HABSOS branch of the filter (Doc C E2, B1). The 4, 6 and 10-min templates and `WFS_4min_masked.asc`, `depth_masked.asc` are likewise unread.

### 3.8 Expected data tree

```
RedTideMaps/                     (or proj_dir, for the four data folders)
  RedTideMaps.Rproj              root anchor
  run_redtide_maps.R             entry point
  config.local.R                 optional, gitignored
  data/FWC HAB API query urls.txt
  template rasters/depth 5min 66x78.asc, excl layer 5min 66x78.asc   (+ 15 min)
  VIIRS/redtide_maps_0.1degree/*.tif    155 files, 2012-01 .. 2024-12 (no 2022-12)
  MODIS/FLH polys 200207-20250926.Rdata
  cell_counts/FWC HAB data <from>-<to>.csv/.Rdata   written by stage 1, gitignored
  out/5min/                      written by the run; only ecospace_ascii/ and plots/ tracked
```

| Input | Size | Used by | Source | How a user gets it |
|---|---|---|---|---|
| FWC HAB records | 33 MB CSV + 4 MB Rdata | stages 1-5 | FWC ArcGIS REST, public | pulled automatically; `fwc_force_full` refreshes |
| VIIRS monthly frequency tifs | 155 files, 2.2 MB | stage 5b | USF/NOAA via the authors | ships in the repository |
| MODIS nFLH polygons | 3 MB Rdata | stage 5c | NOAA CoastWatch ERDDAP, thresholded by the authors | ships; rebuildable with `update_modis` + `rebuild_nflh` |
| Depth and exclusion templates | 324 KB | all stages | Ecospace basemap (provenance unexplained) | ships |
| Endpoint list | 1 KB | stage 1 | authors | ships |
| Coastline | package | plots | Natural Earth via `rnaturalearth` | `install.packages("rnaturalearthdata")` |

## 4. Pipeline and data transformations

### 4.1 Stage 1: ingest

Inputs: the endpoint list and any existing merged CSV. Steps: page each endpoint (full) or the Recent endpoint from the last cached date (incremental); convert the epoch-millisecond `SAMPLE_DATE` to a Date; fill missing columns with NA; append, de-duplicate, sort by date and OBJECTID; write CSV and Rdata named by the date range; delete the previous pair [`scripts/get_HAB_data.R:30-80,101-175`]. Units: cells per litre as served. Invariant: none checked; the only report is the record count and date range printed. Failure: HTTP status other than 200, or an `error` element in the JSON, stops the run; an endpoint returning zero records is accepted silently.

### 4.2 Stage 2: spatial filter

Inputs: the Rdata (`hab.out`) and the depth template. Steps: lower-case the names; derive year and month; keep latitude, longitude, year, month, cells; drop rows without coordinates; make an `sf` point layer in the template's coordinate system (WGS84); drop points inside the Atlantic box (82°W-80.5°W, 28.5°N-31°N); crop to the template's bounding box; append the coordinates as `lon`, `lat`; save as `filtered_points_df` [`:225-300`]. Land points are kept on purpose (`:259`). Output: `out/5min/sdm/<cache name>_filtered.Rdata`. Invariant: 0 NA counts, 0 negative counts on the 30 Sept data (Doc C §3). Failure: an unrecognised file-name prefix stops the run; nothing else is checked. Two QA figures are written to `plots/`.

### 4.3 Stage 3: monthly fits

Inputs: the filtered points and the prediction grid (cell centres of the depth template). Steps per (year, month): count positive samples (`cells > 0`); if six or more, and no cached fit exists for the month (incremental mode), fit the lognormal spatial model to the positive samples (`cells != 0`) and save it under `OM_month/<yyyymm>/`; otherwise skip. Then, for every month in the range, load the fit if any, predict to the grid, compute in-sample diagnostics, and fill a 4-D array (cell × {lon, lat, log model, NB model} × month × year) [`scripts/sdmTMB_HAB_data.R:61-290`]. Months without a model get zeros (by the route described in Doc C B3). Outputs: `pred_SDMs_RT.RData`, `RT_fit_matrix.RData`, `pred_obs_RT.RData`, `fit_warnings.csv` (only when warnings occurred; Doc C R4), five diagnostic PNGs. Invariant: none checked. Failure: a fit that errors twice is recorded as "no model" and becomes a zero map, with a console message only (Doc C B6); warnings are captured to the CSV and muffled.

### 4.4 Stage 4: predict to grid

Inputs: `pred_SDMs_RT.RData` and the depth template. Steps per month: take the month's slice, drop incomplete rows, make it a gridded `sp` object, rasterise each model column onto a raster built from the template's extent and resolution (so the grid is the template's), name the layer `X<yyyymm>`, stack [`:343-401`]. Output: `sdm/sdmTMB_log_stack_<first>-<last>.grd` (504 layers); the NB stack only if it holds any prediction. Invariant: the stack's extent and cell size equal the template's (verified: the ASCII headers match the template's `NCOLS`, `NROWS`, corners and `CELLSIZE`). Failure: a month with fewer than two distinct coordinates is written as all NA with a message.

### 4.5 Stage 5: footprints and clipping

**5a Hulls.** For each (year, month) with any sample: project the positives to UTM 17N (metres); single-linkage cluster them at `hull_link_km`; per cluster, a concave hull if at least `hull_min_pts` distinct locations, else the points; buffer by `hull_buffer_km`; record area, span and a flag; reproject to WGS84 as one MULTIPOLYGON layer per month [`scripts/polygon_clipping_rt.R:59-150`]. Outputs: `sdm/<cache name>_hullpolys.Rdata`, `sdm/hull_diagnostics.csv`. Then mask each month of the prediction stack with its polygons (cells whose centre falls inside keep their value, others become 0, land stays NA); months with no polygon become all zero [`:172-207`]. Output: `clipped/*_clipped_hull.grd`.

**5b VIIRS.** Stack the tifs with the forced extent; for each prediction month that has a VIIRS layer: if the layer has no positive cell, write an all-zero month; else polygonise the positive cells, mask the prediction with the polygon through `terra`, set outside to 0 and land to NA [`scripts/process_VIIRS.R:19-46,97-149`]. Output: `clipped/*_clipped_viirs.grd` (155 layers).

**5c MODIS.** For each prediction month in `flh.polys`: rasterise the polygons on the prediction raster, mask, outside 0, land NA [`scripts/process_MODIS.R:175-213`]. Output: `clipped/*_clipped_modis.grd` (275 layers).

Invariants: every clipped layer has the template's grid (same raster object); a footprint of one buffered point (314 km²) always covers at least one 5-min cell (about 76 km²), so no month with a positive sample is lost to the raster rule (Doc C §3). Failure: a missing VIIRS folder stops the run here; missing MODIS polygons are skipped with a log line.

### 4.6 Stages 6-7: combine and write

Inputs: the three clipped stacks and the depth template. Steps: list every month in any stack; choose `viirs` if VIIRS has the month, else `modis`, else `pred` (hull); write the decision table; for each month take the chosen layer, set NA to 0 and land to NA; write the combined stack and one ASCII per month [`scripts/polygon_clipping_rt.R:226-284`]. Outputs: `clipped/clipping_source.csv`, `combined/*_clipped_combined.grd`, `ecospace_ascii/sdmTMB_log__<yyyymm>.asc` (504 files), `plots/*_clipped_combined.pdf`, and the `Hulls:` log line for flagged hull-served months. No-data is written as -3.4e+38 (Doc C R6). Invariant: the number of ASCII files equals 12 × (enyr − styr + 1). Failure: `pdf()` fails if the previous PDF is open (Doc C B10).

### 4.7 Stage 8: export (opt-in)

Copies every `.asc` from `ecospace_ascii/` into `<ecospace_root>/<res>min/red tide/sdmTMB/`, which must exist (checked at the start of the run and again here); any failed copy stops the run [`:339-354`].

## 5. Statistical models and estimators

### 5.1 The monthly concentration model (sdmTMB, lognormal on positives)

**Question it answers.** Given the positive samples of one calendar month, what concentration (cells/L) would a sample taken at each grid cell show?

**Inputs.** The month's positive samples (`cells != 0`), their longitude and latitude in degrees; the cell centres of the template as prediction points. Nothing else: no depth, no covariates, no other months.

**Specification.** `sdmTMB(cells ~ 1, family = lognormal(), spatial = "on", spatiotemporal = "off", mesh = make_mesh(..., cutoff = 0.1))` [`scripts/sdmTMB_HAB_data.R:154-159`]. In words: log concentration = a month-wide mean + a smooth spatial surface (a Gaussian Markov random field on a triangular mesh whose vertices are at least 0.1° apart, Matérn covariance) + lognormal noise. The spatial range (distance at which cells are effectively independent) and the field and noise standard deviations are estimated per month. sdmTMB's lognormal family uses the Prentice (1974) mean parameterisation, so the response-scale prediction is the mean concentration, not the median.

**Assumptions (not stated in the code).** Concentration given presence is lognormal around a stationary, isotropic spatial surface; samples are independent given the surface; where samples were taken carries no information beyond their values (FWC sampling is event-driven, so during blooms this is doubtful); nothing is shared across months or years; six positives are enough to estimate three variance parameters and a field.

**How it is fit.** Maximum marginal likelihood by nlminb through TMB; two attempts on error (identical inputs, so the retry cannot change the outcome; Doc C B5). Deterministic: no random draws anywhere (§6).

**Diagnostics saved.** Per fit: in-sample RRMSE (RMSE divided by the mean observation), MAE, AIC, a mis-specified AICc (Doc C B7), the negative log-likelihood, and "convergence" = nlminb return code 0 [`:243-262`]; all fit warnings to `fit_warnings.csv`. What the code does not run is sdmTMB's `sanity()`. Run on the 334 cached fits on 6 Oct: 326 have return code 0, 229 pass `sanity()`; the pass rate is 33% for months with ten or fewer positives and 97% above 100 (Doc C M4). In-sample RRMSE median 2.29.

**Failure and fallback.** A fit that errors twice yields no model and a zero map for the month; nothing summarises this in the run log (Doc C B6). A fit that converges by the code's criterion but fails `sanity()` is used as if sound.

**Where the parameters live.** The positive threshold (> 5), the mesh cutoff (0.1) and the family are literals in the function, not in `cfg`.

**How the result feeds the next stage.** Predictions at cell centres become the monthly layer of the prediction stack (§4.4); the clipping cascade then decides which cells keep them.

### 5.2 The footprint estimators

Three estimators of "where the bloom was this month", each a 0/1 mask:

- **Buffered hulls** (every month with a positive): single-linkage clustering at 75 km, concave hull per cluster with at least four distinct locations, 10 km buffer; parameters in `cfg`, chosen in issue #3 with a sensitivity case at 50 km. Deterministic; a diagnostics table and a span flag are written. A month with one positive gets one 10 km disc.
- **VIIRS**: any cell with frequency > 0; threshold chosen by the code, not documented (Doc C M1 for the consequence).
- **MODIS**: nFLH ≥ 0.02 after a division by 10 whose units are unexplained (Doc C M7); polygons pre-built.

The preference VIIRS > MODIS > hull is a fixed rule, not an estimate. The final map is E[concentration | model] × mask.

## 6. Randomness and reproducibility

**Random draws in the live code: none.** The static sweep finds no sampling, jitter, bootstrap or random-start call in the driver or the six stage files; the k-means and jitter that made hull months irreproducible were removed in PR #4. The only `set.seed()` is `set.seed(6)` at the top of `scripts/sdmTMB_HAB_data.R` (line 14), which runs once when the file is sourced and resets the session's random state as a side effect; it protects nothing (Doc C S1).

**Same-seed and cross-seed evidence (6 Oct 2026, Doc C §3):**

| Test | Result |
|---|---|
| Fit 1996-08 (16 positives) four times: seed 6, seed 6, no seed, seed 123 | all four parameter vectors `identical()` |
| Fit 2018-09 (525 positives) the same four ways | all four `identical()` |
| Refit vs the fit cached on 30 Sept (same machine, same packages) | `identical()`; max abs difference 0 |
| Two full runs on the same cached fits (30 Sept and run2 on 6 Oct, 14 duplicate records added) | all 504 ASCII files byte-identical (§9.1) |

**What does vary between runs.** The FWC pull: an incremental run appends whatever the state has added since the last sample date, so the filtered data, the months with six or more positives, the fits for those months (new months only, under incremental mode) and every downstream output for the affected months can change. The baseline on 6 Oct advanced the cache from 2026-09-17 to 2026-09-22. Package versions also matter: the README warns that sdmTMB fits are TMB-version sensitive; the run log records no versions (Doc C R9).

**What a fixed seed would not fix.** Nothing here, since nothing is drawn; the sensitivities that matter are the methods choices in Doc C M1 to M5.

## 7. Outputs

**The deliverable.** `out/<res>min/ecospace_ascii/sdmTMB_log__<yyyymm>.asc`, one ESRI ASCII grid per month from January of `styr` to December of `enyr` (504 files for 1985-2026). Grid: the template's (5 min: 66 × 78, corner 87.5°W 25°N, cell 1/12°). Units: cells per litre, as float32 values (e.g. `96024.078125`). Zero means "no bloom here this month" (outside the footprint, or no model). No-data (land) is written as `-3.4e+38`, not the template's `-9999` (Doc C R6); the no-data cells are exactly the template's 1,310 land cells. Consumer: the WFS Ecospace model, as the red-tide spatial-temporal driver, copied there by stage 8 or by hand.

**Also tracked.** `out/<res>min/plots/`: two sample-coverage PNGs, the unclipped monthly map PDF, the combined monthly map PDF, and (5 min only) `hull_check_issue3.pdf` from the issue #3 QA script.

**Intermediates (gitignored).** `sdm/` (filtered samples, per-month fits, prediction array and stack, fit diagnostics, hull polygons and diagnostics), `clipped/` (three clipped stacks and `clipping_source.csv`), `combined/`, `VIIRS/VIIRS_*.grd`, `cell_counts/`, run logs.

**How to sanity-check a run.** (1) The log ends with `Run complete.` and the `Hulls:` line names only months you can justify as coast-wide blooms. (2) `clipped/clipping_source.csv` has 155 `viirs`, 123 `modis` and the rest `pred` for 1985-2026 with the current inputs. (3) `sdm/RT_fit_matrix.RData` has no new "no model" rows beyond the five known ones. (4) Open `plots/*_clipped_combined.pdf` at a known bloom (September 2018, October 2021) and a known quiet month. (5) `git diff --stat out/5min/ecospace_ascii` after a rerun changes only the months you expect (new data months; every month if a fit or rule changed).

```
out/5min/
  ecospace_ascii/sdmTMB_log__198501.asc .. 202612.asc   deliverable (tracked)
  plots/                                                 tracked
  sdm/                                                   gitignored
    FWC HAB data <range>_filtered.Rdata, _hullpolys.Rdata
    OM_month/<yyyymm>/fit_sdmTMBlog.RData [fit_sdmTMBnb.RData]
    pred_SDMs_RT.RData, RT_fit_matrix.RData, pred_obs_RT.RData, fit_warnings.csv
    sdmTMB_log_stack_<range>.grd/.gri, hull_diagnostics.csv, plots/*.png
  clipped/  *_clipped_hull, *_clipped_viirs, *_clipped_modis (.grd/.gri), clipping_source.csv
  combined/ *_clipped_combined.grd/.gri
  run_<yyyymmdd>.log
```

## 8. Run times and efficiency

### 8.1 Timing table

Measured on 6 Oct 2026 (run2, §9.1): reviewer's machine (20 logical processors, 15 GB RAM), `Rscript` from the command line, nothing else running, warm cache (0 of 334 months refit), incremental FWC pull of 14 records. Times are differences between consecutive stage lines in the run log; the 30 Sept log gave 8 min 12 s for the same stages.

| Stage | Wall time | What dominates | Cache or skip candidate |
|---|---|---|---|
| 1 ingest (incremental) | 8 s | one API page | no |
| 2 filter + plots | 23 s | `sf` operations, two PNGs | no |
| 3 fits (0 refit) | 1 min 17 s | loading 334 fits and predicting in-sample | prediction array cache keyed on fit folders |
| 4 predict + PDF | 1 min 14 s | 504 `rasterize()` calls and a 504-page PDF | same cache; skip the PDF when nothing changed |
| 5 footprints + clipping | 2 min 42 s | VIIRS stack rebuild, three 504-layer masks | VIIRS stack cache keyed on the tif list |
| 6-7 combine + ASCII + PDF | 1 min 31 s | 504 ASCII writes and a 504-page PDF | no |
| Total (first to last stage line) | 7 min 15 s | wall time including R start-up: 7.3 min | |

The same stages took about 35 minutes earlier the same day when an sdmTMB sweep and a runaway process shared the machine and memory ran out (§9.1, first run); a monthly operator run should have the machine to itself. Cold-run figures (first FWC pull, 334 fits) remain the README's unmeasured "about 20 minutes" (Doc C D2).

### 8.2 Existing caches and toggles

| Toggle | Effect on a rerun |
|---|---|
| `incremental_fit = TRUE` | refits only months with no fit on disk; the README measured 8 min 50 s against about 19 min cold |
| `fwc_force_full = TRUE` | full pull, about 3 min (README) |
| `fit_nb = TRUE` | roughly doubles fit time for refit months (README) |
| `update_modis = TRUE` | ERDDAP download; first time pulls everything since 2002 |
| `use_viirs`, `use_modis = FALSE` | skips the stack build and the clip |

A second run in the same tree works: every `writeRaster()` has `overwrite = TRUE`, directories are created recursively, and the log is appended. Invalidation: delete `OM_month/<yyyymm>/` to refit a month; delete the cache CSV or set `fwc_force_full` to re-pull.

### 8.3 Proposed caches (Doc C T2, T3)

A prediction-stack cache (skip stages 3b-4 when no `OM_month/` folder is newer than `pred_SDMs_RT.RData`) would save about 3 min of a 9-min rerun; a VIIRS stack cache (skip when `VIIRS_*.grd` is newer than every tif) about a minute; a column-wise build of the FWC table would cut the full pull. Each is mechanical only if the outputs stay byte-identical.

### 8.4 Code inventory

From the static sweep (`RedTideMaps-audit/sweep/`): 16 `.R` files parsed, 0 failures; functions defined in live files: 4 in `_setup.R`, 6 in `get_HAB_data.R`, 8 in `sdmTMB_HAB_data.R`, 5 in `polygon_clipping_rt.R`, 3 in `process_VIIRS.R`, 5 in `process_MODIS.R`. Never called: `fn.get_habsos_data`, `fn.get_viirs_obs`, `fn.plot_modis`; called but unused product: `compute_area_km2` (Doc C E1). Superseded code: `archive/` (4 files, README), `scripts/old scripts/` (10, no README), `scripts/experimental/` (6, README) (Doc C E3). Tracked data no code reads: 32 MB under `data/` and `template rasters/` (Doc C E2).

## 9. Verification record

### 9.1 As-found baseline

Run on 6 Oct 2026 on the reviewer's machine (Windows 11, R 4.5.1, sdmTMB 1.1.0, TMB 1.9.25, sf 1.0.21, raster 3.6.32, terra 1.8.80) with `Rscript` through `run_logged.R`, on the unmodified code at `a875d64` with the reviewer's `config.local.R` (export off; no other edit). Fingerprints of `out/5min`, `out/15min` and `cell_counts` were taken before the run (`RedTideMaps-audit/20261006/md5_*_before.csv`) and a copy of the committed deliverables and key intermediates sits in `RedTideMaps-audit/20261006/committed/`.

**Result: stopped by the session harness during stage 6, before the ASCII write, because the machine ran critically low on memory (1.8 GB free of 15.4 GB at 15:10). Exit code: none recorded. Wall time to the stop: about 35 min (14:42:11 to about 15:17), against 8 min 12 s for the same stages on 30 Sept.** The slowdown is the machine, not the code: a sanity sweep over 334 fits ran beside it from about 14:49 to 15:04, a stray helper process spun on one core from 15:09, and memory was exhausted. The timing is therefore not evidence for Doc B §8; the 30 Sept log stands as the only clean measurement until the run is repeated.

| Stage | Ran | Log evidence |
|---|---|---|
| 1 ingest | yes | 14:42:15-14:42:25; cache advanced from `19800102-20260917` to `19800102-20260922` (incremental pull added records dated 17-22 Sept 2026) |
| 2 filter + plots | yes | 14:42:25-14:42:48; `*_20260922_filtered.Rdata` written; two PNGs rewritten |
| 3 fits | yes | 14:42:48-14:44:11; no new `OM_month/` folder (334 before and after); `RT_fit_matrix.RData` byte-identical to the 30 Sept copy |
| 4 predict | yes | 14:44:11-14:45:36; stack and PDF rewritten |
| 5 footprints + clipping | yes | 14:45:36-15:14:52 (29 min; 3 min on 30 Sept); `hull_diagnostics.csv` byte-identical to the 30 Sept copy; three clipped stacks written |
| 6-7 combine + ASCII | started | 15:14:52; `clipping_source.csv` written at 15:14:53 and byte-identical to the 30 Sept copy; stopped before the combined stack and the ASCII files |

**Comparison with the committed outputs** (`git status` after the stop):

| Output group | Identical | Changed | Cause |
|---|---|---|---|
| `out/5min/ecospace_ascii/` (504 files) | 504 | 0 | not reached; and nothing upstream that feeds them changed (fit matrix, hull diagnostics and cascade table identical despite the new records), so a completed run would have reproduced them |
| `out/5min/plots/` (5 files) | 2 | 3 | `N samples over time.png` and `sample locations by year.png`: the 17-22 Sept 2026 samples now appear (a few bytes larger); `sdmTMB log maps.pdf`: same size, embedded creation timestamp |
| `out/15min/` (508 files) | 508 | 0 | not regenerated at `res = 5` |
| `cell_counts/` | 0 | 2 | replaced by the `-20260922` pair (R2: the previous pair was deleted by the code; the audit copy holds it) |

The three changed plots were left in the working tree for the reviewer to discard or keep.

**Run2 (clean repeat, same day).** Started 16:50:59 with nothing else running, same code, same config, through `run_logged.R` (`RedTideMaps-audit/20261006/run2/run_20261006-165059.log`).

**Result: all stages ran to completion. Exit code 0. Wall time 439.7 s (7.3 min), of which 7 min 15 s between the first and last stage lines.**

| Stage | Ran | Log evidence |
|---|---|---|
| 1 ingest | yes | 16:51:04-16:51:12 (8 s); "Last SAMPLE_DATE in local data: 2026-09-22"; "+ 14 records on/after 2026-09-22"; "Wrote FWC HAB data 19800102-20260922.csv (216198 records, 1980-01-02 to 2026-09-22)" (the 14 were duplicates of cached rows: same count as before) |
| 2 filter + plots | yes | 16:51:12-16:51:35 (23 s) |
| 3 fits | yes | 16:51:35-16:52:52 (1 min 17 s); "Fit summary: 0 month(s) newly fit, 334 reused from cache."; "No fit warnings captured." (and `fit_warnings.csv` from 25 Sept still present: R4) |
| 4 predict | yes | 16:52:52-16:54:06 (1 min 14 s) |
| 5 footprints + clipping | yes | 16:54:06-16:56:48 (2 min 42 s) |
| 6-7 combine + ASCII | yes | 16:56:48-16:58:19 (1 min 31 s); "Hulls: 10 of 226 hull-served month(s) have a footprint spanning > 300 km: 199009, 199604, 199606, 199711, 199909, 200009, 200010, 200110, 200112, 200201"; "Run complete." |

**Comparison with the committed outputs** (`snapshot_md5.R compare` of `out/5min`, 863 fingerprinted files, before the first run against after run2; no line-ending-only differences):

| Output group | Identical | Changed | Cause |
|---|---|---|---|
| `ecospace_ascii/` (504 files) | 504 | 0 | deterministic pipeline, no new fit, no new positive-bearing month; the 14 new records were duplicates |
| `plots/` (5 files) | 1 (`hull_check_issue3.pdf`, not written by the pipeline) | 4 | two sample PNGs: the 17-22 Sept 2026 samples now drawn; two PDFs: embedded creation timestamp (same size) (R10) |
| `sdm/` (348 files) | 348 | 0, 2 added | the `-20260922` `_filtered` and `_hullpolys` Rdata beside the `-20260917` pair (R5) |
| `clipped/clipping_source.csv` | 1 | 0 | |

So the committed 5-min deliverables are reproduced exactly by a fresh run of the same commit on new FWC data that contained nothing new for any modelled month. The copy of run2's outputs is the working tree itself (unchanged except the plots); the fingerprints are `md5_5min_before.csv` and `md5_5min_after_run2.csv` in the audit folder.

### 9.2 Same-inputs repeat

The clean rerun of 6 Oct (run2, below) is compared with the committed deliverables; because the fit matrix, hull diagnostics and cascade table of the first run were already byte-identical to 30 Sept, a byte-identical ASCII set from run2 is the "two runs on the same inputs" evidence.

### 9.3 As-left verification

No code changed in review-only mode, so "as left" equals "as found". The convention checks were run on 6 Oct 2026 against the tracked tree at `a875d64`:

| Command | Result |
|---|---|
| `git grep -nE "\b[A-Za-z]:/\|/Users/\|/home/\|OneDrive\|AppData" -- '*.R'` (URLs dropped) | Live code: only the two commented examples in `config.local.example.R:15,25`. Superseded folders: `archive/` (22 hits in 4 files), `scripts/old scripts/` (12 in 3 files), `scripts/experimental/` (5 in 2 files), all covered by Doc C E3 |
| `git grep -n "windows(" -- '*.R'` | Empty |
| `git ls-files -ci --exclude-standard` | Empty |
| `git status` after the runs | Three plot files modified (sample PNGs with the new September samples; PDF timestamp), `docs/review/` untracked; no ASCII file modified |

Run matrix:

| Target | How run | Inputs | Result | Evidence |
|---|---|---|---|---|
| Reviewer, command line | `run_logged.R` on `a875d64`, reviewer's `config.local.R` | tracked inputs; FWC pulled live | first run stopped by the harness in stage 6 (memory); clean rerun: see §9.1 run2 | `RedTideMaps-audit/20261006/run/`, `run2/` |
| Author's layout (interactive) | not run (reviewer is the author; same machine) | | pending | |
| Fresh clone, no network | not run in review-only mode; static reading: stops at stage 1 with the HTTP error after the package check and template check pass | | pending | Doc C P1 |
| Fresh clone, with network | not run in review-only mode | | pending | |

## 10. Appendices

### 10.1 Configuration keys

See §2.2.

### 10.2 Function inventory (live files)

| File | Function | Purpose | Called by |
|---|---|---|---|
| `run_redtide_maps.R` | `.rt_repo_root` | find the repository root from the working directory or `--file=` | driver |
| `scripts/_setup.R` | `rt_check_packages`, `rt_paths`, `rt_init_dirs`, `rt_log` | package check; output tree; create folders; timestamped log | driver |
| `scripts/get_HAB_data.R` | `.fwc_fetch_endpoint`, `%\|\|%`, `fn.get_fwc_data`, `fn.filter_hab_data`, `fn.plot_hab_data` | page an endpoint; null-coalesce; pull and merge; spatial filter; QA plots | `fn.get_fwc_data`; `.fwc_fetch_endpoint`; driver; driver; driver |
| | `fn.get_habsos_data` | download the NCEI HABSOS archive | nobody |
| `scripts/sdmTMB_HAB_data.R` | `fn.make_input_grid`, `compute_area_km2`, `fn.fit_monthly_sdmTMB`, `.has_existing_fit`, `catch_warns`, `.plot_fit_diagnostics`, `fn.predict_monthly_sdmTMB`, `fn.plot_sdmTMB` | grid; cell area (unused product); fits; cache test; warning capture; diagnostic PNGs; rasterise; PDF | driver; `fn.make_input_grid`; driver; fit; fit; fit; driver; driver |
| `scripts/polygon_clipping_rt.R` | `fn.buffered_hulls`, `fn.clip_2_hulls`, `make_redtide_ascii`, `fn.plot_redtide_stack`, `export_to_ecospace` | footprints; hull mask; combine and write; PDF; copy out | driver |
| `scripts/process_VIIRS.R` | `fn.viirs_tifs2stack`, `fn.clip_2_viirs` | stack tifs; VIIRS mask | driver |
| | `fn.get_viirs_obs` | VIIRS value at each sample | nobody |
| `scripts/process_MODIS.R` | `.ensure_modis_pkgs`, `fn.pull_MODIS_flh_erddap`, `fn.make_nflh_polys`, `fn.clip_2_modis` | optional packages; ERDDAP pull; polygons; MODIS mask | pull/polys; driver (toggle); driver (toggle); driver |
| | `fn.plot_modis` | nFLH maps with polygons | nobody |

### 10.3 Packages (reviewer's machine, 6 Oct 2026)

R 4.5.1 (2025-06-13 ucrt), x86_64-w64-mingw32, Windows 10 x64 build (Windows 11 Enterprise), locale English_United States.utf8, no renv.

| Package | Version | | Package | Version |
|---|---|---|---|---|
| sf | 1.0.21 | | ggplot2 | 4.0.0 |
| raster | 3.6.32 | | viridis | 0.6.5 |
| terra | 1.8.80 | | scales | 1.4.0 |
| sp | 2.2.0 | | cowplot | 1.2.0 |
| rnaturalearth | 1.2.0 | | ggh4x | 0.3.1 |
| rnaturalearthdata | 1.0.0.9000 | | maps | 3.4.3 |
| sdmTMB | 1.1.0 | | fields | 17.1 |
| TMB | 1.9.25 | | rvest | 1.0.5 |
| fmesher | 0.8.0 | | httr | 1.4.7 |
| lubridate | 1.9.4 | | jsonlite | 2.0.0 |
| concaveman | 1.2.0 | | rerddap | not installed |
| cluster | 2.1.8.1 | | curl, data.table, rasterVis, colorRamps | 7.0.0, 1.17.8, 0.51.7, 2.3.4 |

### 10.4 Glossary

| Term | Meaning |
|---|---|
| ASCII grid (ESRI) | a text raster: six header lines (columns, rows, corner, cell size, no-data value) then one number per cell |
| cells/L | *Karenia brevis* cells per litre of seawater; FWC's scale: background ≤ 1,000; very low to 10,000; low to 100,000; medium to 1,000,000; high above |
| footprint | the set of cells treated as "bloom present" for a month; everything outside is set to zero |
| hull (concave) | a polygon hugging a set of points more tightly than the convex hull; `concaveman` concavity 2 |
| incremental pull | fetching only records dated on or after the last one already cached |
| lognormal | a distribution whose logarithm is normal; here the noise around the spatial surface |
| mesh, SPDE | the triangulation on which sdmTMB approximates the spatial random field; `cutoff` is the minimum vertex spacing |
| nFLH | normalised fluorescence line height, a MODIS chlorophyll-fluorescence index used to detect blooms |
| no-data | the value standing for "not a water cell" (land); -9999 in the templates, -3.4e+38 in the deliverables |
| sanity() | sdmTMB's set of post-fit checks (Hessian positive definite, finite standard errors, variance parameters not at bounds, range plausible) |
| single linkage | clustering in which two points join a cluster when any chain of points connects them with every step shorter than the cut distance |
| spatial range | the distance beyond which two cells' random effects are nearly uncorrelated (about 0.13 correlation) |
| UTM 17N (EPSG:32617) | the metric projection used for hull distances and buffers |

### 10.5 Command cheat-sheet

```
Rscript run_redtide_maps.R                                   # full run (incremental fits, incremental FWC pull)
rm -rf out/5min/sdm/OM_month/202503 && Rscript run_redtide_maps.R   # refit one month
# config.local.R:  cfg$fwc_force_full <- TRUE                # re-pull every FWC layer once
Rscript scripts/qa/check_hulls_issue3.R                      # hull QA (needs scripts/qa/_polygon_clipping_rt_main.R)
Rscript <skill>/scripts/snapshot_md5.R snapshot out/5min before.csv   # fingerprint outputs
Rscript <skill>/scripts/snapshot_md5.R compare before.csv after.csv --md
Rscript <skill>/scripts/run_logged.R run_redtide_maps.R --out ../RedTideMaps-audit/<stamp>/run
```
