# The red tide data bundle: schema 1.0

Schema version 1.0, 4 November 2026. This document specifies the folder `out/<res>min/bundle/` that step 9 of `run_redtide_maps.R` writes (`fn.write_bundle()`, `scripts/write_bundle.R`) for the delivered red tide maps, and it is written into every bundle as `SCHEMA.md`, so the data travels with its description. The consumer it was designed for is the WFS-Portal application ([WFS-FEM/WFS-Portal](https://github.com/WFS-FEM/WFS-Portal)); any reader of CSV and JSON can use it. The plan and the decisions behind it are `issue23-portal-bundle-plan.md` in this folder ([#23](https://github.com/WFS-FEM/RedTideMaps/issues/23)).

## 1. What the bundle is

The bundle is a data-only, text-only description of one map product on one grid: the monthly maps the pipeline delivers to Ecospace (`out/<res>min/ecospace_ascii/`), with a per-month summary, the FWC samples the maps were built from, the grid they sit on, the display facts of the product (palette recipe, band definition, units) and the provenance of the run. It holds no image and no binary file. A bundle is one grid plus one or more layers; the red tide bundle has one layer, `redtide`. Its identity is `bundle_id = <product>_<res>min`, `redtide_5min` for the 5-arcmin product; the resolution is encoded by the parent folder (`out/5min/`) and repeated in `meta.json`, and no file name inside the bundle carries the identity, so the folder is copied as a unit.

The values the bundle carries are the cells/L of each monthly ASCII file, reproduced text for text (section 3.5). Everything else is derived from the run that wrote the maps.

## 2. Layout

```
out/5min/bundle/
  .gitattributes                 "* text eol=lf": LF in the index and in every checkout
  SCHEMA.md                      this document
  meta.json                      identity, grid header, month range, samples, nearshore set, clipping counts, provenance, build, cfg
  style.json                     display facts of the product: units, palette recipe, bands, code vocabularies
  grid.csv                       one row per template cell (5,148 at 5 arcmin)
  months.csv                     one row per month (504); the only place the placeholder flag lives
  layers.csv                     one row per layer (1); the only place the layer definitions live
  values/redtide/<yyyy>.csv      one file per year, long sparse: the positive water cells of each month
  summary/redtide.csv            one row per month: the monthly summary
  samples/fwc_<yyyy>.csv         one file per year: the filtered FWC samples of the product months
  ascii_md5.csv                  one row per ASCII file: the LF md5 of the map the bundle encodes
  manifest.csv                   file, bytes, md5 of every file above, .gitattributes included (written last)
```

Size at 5 arcmin: about 10 MB of text, comparable to the 10.6 MB of ASCII it describes; the values about 1.4 MB, the samples about 7 to 8 MB, `grid.csv` about 350 KB. A monthly pipeline run changes `values/redtide/<current year>.csv` (and the previous year's file when late samples change a hull-served month), `samples/fwc_<current year>.csv`, the changed rows of `summary/redtide.csv` and of `ascii_md5.csv`, `months.csv` only when the last data month moves, `meta.json` and `manifest.csv`.

## 3. Conventions

### 3.1 Text and line endings

Every file is text: CSV for tables, JSON for metadata, Markdown for this document. Every file is written through a binary connection with LF line endings, and the folder's `.gitattributes` pins LF at checkout, so a local copy, a fresh clone and a raw download from GitHub are byte-identical and the md5 values of `manifest.csv` hold everywhere. (R writes CRLF on Windows by default and git stores LF; without the pin the two would differ byte for byte.) A bundle never contains a carriage return byte (0x0D); the writer asserts it.

### 3.2 Numbers, logicals, missing values, the month key

- Every double is printed as the shortest decimal that survives a round trip through `as.numeric()`: `sprintf("%.15g", x)`, or `sprintf("%.17g", x)` for the values where 15 significant digits do not round-trip. Map values never need the fallback (the ASCII files carry at most 15 significant digits). Cell centers in `grid.csv` and about half of the sample coordinates do, and are printed with 17 digits; they are the exact doubles of the pipeline (the FWC coordinates are six-decimal values that the pipeline's parser stored one ulp off in about half the rows; rounding them would move 33 samples across cell edges, so they are kept exact).
- Integers print as integers, logicals as `TRUE` / `FALSE`, missing values as `NA`.
- `yrmo` is a six-character string, `"198501"`; read it as character (`colClasses = c(yrmo = "character")`), never as a number.
- `Inf` appears only in `style.json`, as the string `"Inf"` in the band breaks.

### 3.3 Quoting

CSV files quote exactly their character columns (so `layers.csv$name`, which contains a comma, is quoted) and never a number. The values files, whose three columns can hold no comma or quote, are written without quotes. `read.csv()` reads both forms.

### 3.4 Order

The order of every file is deterministic, so a rerun of the writer with the same inputs is byte-identical except the volatile keys of `meta.json` (section 6): months ascending; values by `yrmo` then `cell`; samples by `year, month, lat, lon, cells`; cells by `cell`; `ascii_md5.csv` by month; `manifest.csv` by path.

### 3.5 Which reading of the ASCII the bundle reproduces

The bundle values are identical to the text of the ASCII files, parsed as doubles (`scan()` in R; 15 significant digits). Readers that go through GDAL (the `raster` and `terra` packages, QGIS) see the same files as 32-bit floats and differ from the text at the 16th significant digit in some months, as the pipeline's own combined stack (a float32 raster) does. Comparisons against such readers use a tolerance (`isTRUE(all.equal())` in R), never exact equality. Two derived columns carry a tolerance rule for the same reason: `n_changed` counts a cell as changed when `abs(M - S) > 1e-9 * max(abs(S), 1)` (section 5.4), and an exposure recomputed from a float32 reading agrees with the bundle within 1e-3 cells/L (the measured maximum difference is about 1e-9).

### 3.6 The grid and the cell order

The grid is the depth template of the pipeline (`template rasters/depth 5min 66x78.asc` at 5 arcmin): 78 columns by 66 rows of 1/12 degree, extent -87.5 to -81 E and 25 to 30.5 N, WGS 84 longitude and latitude (EPSG:4326). Cells are numbered row-major from the northwest corner, `cell = (row - 1) * ncols + col`, the numbering of the `raster` package and the token order of the ASCII files. Land is the set of template cells with no depth (1,310 at 5 arcmin; NODATA in every ASCII file); water is the rest (3,838). The Atlantic-side box (longitude greater than -82 and latitude greater than 28.5) is excluded from every spatial set the pipeline builds (the nearshore set, the sample filter); the maps still carry those cells, as zeros, and `grid.csv` flags them.

The ASCII files write their NODATA value, -3.4e+38, and a reader that parses the text must treat any value below -1e30 as missing: the first token of every file is printed as a 39-digit decimal rather than in scientific notation.

## 4. The files

### 4.1 `meta.json`

One object, written by `jsonlite::toJSON(auto_unbox = TRUE, pretty = TRUE, digits = NA)`. The layer definitions live in `layers.csv` and the placeholder flag in `months.csv`, not here.

| key | content |
|---|---|
| `schema_version` | `"1.0"` |
| `bundle_id`, `product`, `product_name`, `res_arcmin` | `"redtide_5min"`, `"redtide"`, `"Red Tide Maps"`, `5` |
| `grid` | `ncols`, `nrows`, `xllcorner`, `yllcorner`, `cellsize` (as the ASCII header prints them), `nodata`, `crs` (`"EPSG:4326"`), `extent` (`[xmin, xmax, ymin, ymax]`), `n_cells`, `n_water`, `cell_order` (the sentence of section 3.6), `template` (the template file, repository-relative), `atlantic_box` (`{"lon_gt": -82, "lat_gt": 28.5}`) |
| `months` | `first`, `last`, `n`, `last_data` (the last month with an FWC sample), `n_placeholder` (the months after it) |
| `samples` | `file_pattern` (`"samples/fwc_<yyyy>.csv"`), `source` (`"FWC-FWRI HAB Monitoring Database (ArcGIS REST)"`), `file` (the filtered samples file the run used), `date_from`, `date_to` (the sample date range of that file), `n_rows_filtered`, `n_rows_bundle`, `last_month`, `coordinate_note`; `null` when a bundle carries no samples |
| `nearshore` | `rule` (`"mask5adj"`), `n_cells`, `km2`; `null` when both nearshore rules of the run are `"none"` |
| `clipping` | the count of months by `use` (`hybrid`, `viirs`, `hybrid_modis`, `modis`, `pred`), `hybrid_changed`, `hull_flagged` |
| `source` | `repo`, `branch`, `ascii_dir`, `ascii_commit`, `ascii_dirty`, `ascii_md5`, `head_commit`, `schema_url` (section 6) |
| `build` | `built_at` (UTC, ISO 8601), `r_version`, `raster_version`, `writer` (`"scripts/write_bundle.R"`), `run_log` (the pipeline log of the run, or `null` for a standalone call), `mode` (`"pipeline"` or `"standalone"`), `toggles` (the run toggles of the pipeline configuration: `update_modis`, `rebuild_nflh`, `fwc_refresh`, `fwc_force_full`, `incremental_fit`, `fit_nb`, `export_ecospace`, `write_bundle`) |
| `cfg` | the map-determining keys of the pipeline configuration: `res`, `styr`, `enyr`, `hull_link_km`, `hull_buffer_km`, `hull_min_pts`, `hull_concavity`, `hull_warn_span_km`, `viirs_nearshore`, `modis_nearshore`, `use_viirs`, `use_modis`. Path keys are never written. |

### 4.2 `style.json`

Facts about the product that a consumer needs to draw it as the pipeline does; nothing about layout, sizes, fonts or colors chosen for display, which belong to the consumer. This file changes only when the pipeline's own palette or the band convention changes, with a note in section 10.

| key | content |
|---|---|
| `schema_version` | `"1.0"` |
| `units` | `"cells/L"` |
| `palette` | `type` (`"ramp"`), `anchors` (the eleven color names of the pipeline PDFs: white, purple, blue, darkblue, cyan, green, darkgreen, yellow, orange, red, darkred), `bias` (2), `breaks` (`zero` 0, `first_colored` 10000, `step` 10000, `last` 4000000), `above` (`"darkred"`), `colors_hex` (the 402 colors the recipe expands to: white up to 9,999 cells/L, 400 ramp colors in steps of 10,000 up to 4,000,000, darkred above) |
| `bands` | `breaks` (`[0, 1000, 10000, 100000, 1000000, "Inf"]`), `right_closed` (`true`), `columns` (the five band columns of the summary), `sample_columns` (the five sample band columns), `labels` (`"<= 1k"`, `"1k to 10k"`, `"10k to 100k"`, `"100k to 1M"`, `"> 1M"`) |
| `codes` | the vocabularies of the summary's categorical columns with one-line meanings: `use`, `fit_status`, `viirs_status` |

### 4.3 `grid.csv`

One row per template cell, in cell order. Required columns (what every bundle on this schema carries): `cell, row, col, lon, lat, water, km2`. Optional columns, present in the red tide bundle: `depth_m, nearshore, atlantic`.

| column | type | definition |
|---|---|---|
| `cell` | integer | 1 to `n_cells`, row-major from the northwest corner |
| `row`, `col` | integer | 1-based; row 1 is the northernmost |
| `lon`, `lat` | double | the cell center, full precision, so a point-in-cell lookup round-trips |
| `water` | logical | `TRUE` where the template has a depth, `FALSE` on land |
| `km2` | double | the cell area (`raster::area()` of the template; 73.7 to 77.5 km2 at 5 arcmin) |
| `depth_m` | double | the template depth; `NA` on land |
| `nearshore` | logical | `TRUE` for the cells of the run's nearshore set, `FALSE` on other water, `NA` on land; absent when both nearshore rules are `"none"` |
| `atlantic` | logical | `TRUE` in the Atlantic-side box (section 3.6) |

### 4.4 `months.csv`

One row per month of the product, ascending: `yrmo` (character), `year`, `month` (integer), `index` (1 to `n`), `label` (`"1985-01"`), `placeholder` (logical: `TRUE` for the months after the last month with an FWC sample, whose maps are zero by construction because the pipeline writes the whole current year).

### 4.5 `layers.csv`

One row per layer: `id`, `name`, `units`, `encoding`, `file_pattern`, `summary_file`, `total_column`, `fill`, `precision`, `description`. The red tide row: `redtide`, `Karenia brevis cell concentration, delivered map`, `cells/L`, `long_sparse`, `values/redtide/<yyyy>.csv`, `summary/redtide.csv`, `exposure`, `0`, `shortest decimal that round-trips the double (15 or 17 significant digits)`, and the description of the clipping cascade and the nearshore rule of the run. `encoding` has one value in schema 1.0, `long_sparse` (section 4.6).

### 4.6 `values/<layer>/<yyyy>.csv`

Columns `yrmo, cell, value`, unquoted: one row per water cell with a value above zero in each month of that year, sorted by `yrmo` then `cell`. Cells not listed are 0 on water and missing on land, the normalization the pipeline applies to every map it writes. A year without a positive cell still has its file, with the header line only. To rebuild a month: a vector of `n_cells` zeros, `NA` where `grid.csv$water` is `FALSE`, then the listed values at their cells.

### 4.7 `summary/<layer>.csv`

One row per month, ascending. The map metrics are computed on the water cells of the delivered map; the bands are right-closed on the positive cells (section 5.1); the exposure is the sum of cells/L over the water cells (section 5.2). The sample-derived columns (`n_samples` through `in_ge10k`) are optional in the schema and `NA` in a bundle without samples.

| column | type | definition |
|---|---|---|
| `yrmo`, `year`, `month` | character, integer, integer | the month |
| `use` | character | the clip source the delivered map is built on: `hybrid` (the VIIRS clip with the hull footprint added inside the nearshore set), `viirs` (the VIIRS clip as it is), `hybrid_modis` (the MODIS clip with the hull footprint added inside the nearshore set), `modis` (the MODIS clip as it is), `pred` (the hull-clipped prediction, no satellite coverage); `viirs` and `modis` occur only when a nearshore rule of the run is `"none"` |
| `hybrid_changed` | logical | the nearshore rule changed at least one cell of the month |
| `n_changed` | integer | the water cells the nearshore rule changed (section 5.4); 0 for `viirs`, `modis` and `pred` months; `NA` when the clipped stacks were not available to the writer |
| `hull_span_km` | double | the largest span of the month's hull footprint (`max_span_km` of the pipeline's hull diagnostics); `NA` for a month without a footprint |
| `hull_flagged` | logical | the pipeline's hull flag: the footprint spans more than the configured limit and the month is hull-served (`use == "pred"`); `FALSE` for a satellite month whose footprint serves only inside the nearshore set; `NA` where there is no footprint |
| `fit_status` | character | `fitted` (a model was fit), `failed` (a layer exists but is all zero), `none` (no fit attempted: fewer than six positive samples) |
| `converged` | logical | the convergence flag of the lognormal fit; `NA` when no model was fit |
| `viirs_status` | character | `positive` (a VIIRS layer with detections), `zero` (a VIIRS layer with none), `missing` (inside the VIIRS era but the tif is missing), `no_coverage` (outside the VIIRS era); `NA` when the run did not use VIIRS |
| `n_samples` | integer | the filtered FWC samples of the month with a count |
| `n_samples_water` | integer | those on a water cell of the template |
| `n_samples_pos` | integer | those with a count above zero |
| `s_le1k`, `s_1k_10k`, `s_10k_100k`, `s_100k_1M`, `s_gt1M` | integer | the positive samples by band; they sum to `n_samples_pos` |
| `samples_ge10k` | integer | the water samples at or above 10k cells/L |
| `in_ge10k` | integer | how many of them sit in a cell where the map is above zero |
| `exposure` | double | the sum of cells/L over the water cells, unrounded |
| `n_pos` | integer | the water cells above zero |
| `n_le1k`, `n_1k_10k`, `n_10k_100k`, `n_100k_1M`, `n_gt1M` | integer | the positive cells by band; they sum to `n_pos` |
| `n_ge10k`, `km2_ge10k` | integer, double | the cells at or above 10k cells/L and their area |
| `n_ge100k`, `n_ge1M` | integer | the cells at or above 100k and at or above 1M cells/L |
| `max_cells`, `max_cell` | double, integer | the maximum value and its cell (the first on ties); `NA` when the month is all zero |

### 4.8 `samples/fwc_<yyyy>.csv`

Columns `year, month, cells, lon, lat, cell, water`: the rows of the pipeline's filtered FWC samples (the Atlantic box removed, the grid box applied) with a count, for the years of the product, plus `cell` (the template cell of the coordinates, `NA` off the grid) and `water` (the grid flag of that cell, `NA` off the grid). `cell` is the authoritative cell of a sample; recomputing it from the printed coordinates gives the same cell because the text round-trips the double. Duplicate rows (the same station, count and month on different days) are kept as delivered. Sorted by `year, month, lat, lon, cells`, so a monthly run appends at the end of the current year's file.

### 4.9 `ascii_md5.csv`

Columns `yrmo, file, bytes, md5`: for each monthly ASCII file, its name, its size on the writer's disk, and the md5 of its content with every carriage return byte removed, so the value is the same on a CRLF working tree, an LF checkout and a GitHub raw download, and equals the md5 of the git blob. This is the staleness guard: a consumer with the ASCII files beside the bundle can verify that the bundle describes them (the pipeline's check script and the WFS-Portal fetch script do). `meta.json$source$ascii_md5` is the md5 of the 504 md5 strings concatenated in month order, one value to compare.

### 4.10 `manifest.csv`

Columns `file, bytes, md5`: every file of the bundle except the manifest itself, `.gitattributes` included, paths relative to the bundle folder with `/` separators, md5 of the LF bytes. Written last.

### 4.11 `SCHEMA.md` and `.gitattributes`

This document and the one-line attributes file, both written LF by the writer (never copied byte for byte from a working tree, which may be CRLF).

## 5. Definitions

### 5.1 Bands

The five classes of the FWC monitoring reports, right-closed on the positive values: `cut(v[v > 0], c(0, 1e3, 1e4, 1e5, 1e6, Inf), include.lowest = TRUE)`. A value of exactly 1,000 falls in `<= 1k`, exactly 10,000 in `1k to 10k`, exactly 1,000,000 in `100k to 1M`. Zeros are not in any band. The same rule applies to map cells and to samples. Threshold columns (`n_ge10k`, `samples_ge10k`, and so on) are inclusive: at or above the threshold.

### 5.2 Exposure

The sum of cells/L over the water cells of a month, with no area weighting: what Ecospace integrates when it reads a map, and what every map panel of the pipeline's comparison figures prints first.

### 5.3 Placeholder months

The pipeline models and writes every month of the current year, so the months after the last month with an FWC sample carry zero maps that are not forecasts. `months.csv$placeholder` marks them; `meta.json$months$last_data` names the last data month. A viewer should not offer placeholder months; the bundle keeps them because the Ecospace deliverable carries them.

### 5.4 `n_changed`

For a `hybrid` month, the water cells where the delivered map differs from the VIIRS-clipped layer it was built on; for a `hybrid_modis` month, from the MODIS-clipped layer; both layers normalized as the pipeline writes them (missing to 0 on water). A cell counts as changed when `abs(M - S) > 1e-9 * max(abs(S), 1)`, a relative tolerance that ignores the float32 representation of the pipeline's stacks (section 3.5). `hybrid_changed` is `TRUE` exactly when `n_changed > 0`.

### 5.5 `hull_flagged`

The pipeline flags a month whose largest hull footprint spans more than `cfg$hull_warn_span_km` (300 km by default) and reports the flag only for the months the hull path serves (`use == "pred"`), because the satellite months use the footprint only inside the nearshore set. The column follows that rule; `hull_span_km` carries the span itself for any month with a footprint.

### 5.6 `fit_status`, `converged`, `viirs_status`

`fit_status` comes from the unclipped prediction layer of the month (`none` when the pipeline did not fit the month, `failed` when the layer is all zero, `fitted` otherwise); `converged` from the pipeline's fit record of the lognormal model; `viirs_status` from the VIIRS stack of the run (its first and last layer bound the VIIRS era). The code lists of `style.json` repeat the meanings.

## 6. Provenance

- `source.ascii_commit` is the last commit that changed the maps the bundle encodes (`git log -1 -- out/<res>min/ecospace_ascii/` at build time). `source.ascii_dirty` is `TRUE` when the ASCII files on the writer's disk differ from that commit (a monthly run, whose new maps are not yet committed) and `FALSE` on a verification run that reproduced the committed maps. `source.ascii_md5` ties the bundle to the exact ASCII bytes (section 4.9).
- `source.head_commit` is the repository HEAD at build time, informational: the parent of the commit that will carry the bundle. The bundle's own commit cannot be known when it is written; it is stated in the message of the `data:` commit that carries it, and a consumer records it beside its copy (WFS-Portal writes it to `FETCH.json`). A bundle and the ASCII files it describes are committed together.
- `source.schema_url` points at this document in the repository at `head_commit`.
- `build.mode` is `"pipeline"` when step 9 of a run wrote the bundle and `"standalone"` when the writer was called from the console against a run on disk (a schema change, a verification). Every git value reads `"unknown"` when git could not be called.
- Volatile keys, the only ones that differ between two writes of the same inputs: `build.built_at`, `build.run_log`, `build.mode`, and the `source` block.

## 7. Optional files and columns; other products on this schema

Optional in schema 1.0: `samples/` and `meta.samples` (absent or `null` in a bundle without point samples, with the sample-derived summary columns `NA`); `grid.csv$depth_m`, `nearshore`, `atlantic`; `meta.nearshore` (`null` when the run used no nearshore rule); `summary` columns beyond `yrmo, year, month, exposure, n_pos, max_cells, max_cell` for a layer that is not red tide.

A bundle for another product on the same grid (an Ecospace run, with one layer per species or fleet) uses the same files: the same `grid.csv`, its own `months.csv`, one `layers.csv` row per layer with its `units` and `total_column`, `values/<layer_id>/<yyyy>.csv`, `summary/<layer_id>.csv` with at least `yrmo, year, month, total, mean, n_pos, max_value, max_cell`, no `samples/`, and a `style.json` with its palette recipe and `"bands": null`.

Reserved, named here and specified by a later minor version when a product needs them: a dense encoding for layers positive almost everywhere; per-layer style overrides in `style.json`; a `viridis` palette type.

## 8. Reading the bundle in base R

```r
dir    <- "out/5min/bundle"
meta   <- jsonlite::fromJSON(file.path(dir, "meta.json"))
grid   <- read.csv(file.path(dir, "grid.csv"))
months <- read.csv(file.path(dir, "months.csv"), colClasses = c(yrmo = "character"))
summ   <- read.csv(file.path(dir, "summary", "redtide.csv"), colClasses = c(yrmo = "character"))
vals   <- do.call(rbind, lapply(list.files(file.path(dir, "values", "redtide"), full.names = TRUE),
                 read.csv, colClasses = c("character", "integer", "numeric")))
M <- matrix(0, nrow(grid), nrow(months), dimnames = list(NULL, months$yrmo))
M[!grid$water, ] <- NA
M[cbind(vals$cell, match(vals$yrmo, months$yrmo))] <- vals$value
# M[, "201809"] is the September 2018 map in cell order; matrix(M[, "201809"], nrow = meta$grid$ncols)[, meta$grid$nrows:1]
# is the image() orientation (columns west to east, rows south to north).
```

Verify a copy: recompute `tools::md5sum()` of every file and compare with `manifest.csv`.

## 9. Attribution

The maps are produced by the WFS-FEM/RedTideMaps pipeline (Chagaris, Vilas, Harris; MIT license) on the West Florida Shelf Ecospace grid (Vilas et al. 2023), as part of the project "Operationalizing the West Florida Shelf ecosystem model and application to red tides, stock assessment, and catch advice for Gulf of Mexico reef fish" (PI David Chagaris, University of Florida). In situ Karenia brevis cell counts: Florida Fish and Wildlife Conservation Commission, Fish and Wildlife Research Institute, HAB Monitoring Database (ArcGIS REST services). Satellite bloom detection: University of South Florida Optical Oceanography Laboratory (PI Chuanmin Hu), monthly VIIRS red tide probability maps from NOAA VIIRS and MODIS nFLH from NASA Aqua. Model: sdmTMB. The maps are model products, not observations, and not an FWC or USF product; the repository README describes the method and its limits.

## 10. Version history

| version | date | change | commit |
|---|---|---|---|
| 1.0 | 4 Nov 2026 | first version: the layout, conventions, files and definitions above (#23) | (the `docs:` commit of step 1) |

A minor version adds files, columns or keys (readers ignore unknown ones); a major version renames, removes or changes the meaning of anything (the band definition, the cell order, the layout, the meaning of a provenance key). A consumer accepts the major version it was written for and warns on a newer minor one.
