# The red tide data bundle: schema 1.0

Schema version 1.0, 4 November 2026. This document specifies the folder `out/<res>min/bundle/` that step 9 of `run_redtide_maps.R` writes (`fn.write_bundle()`, `scripts/write_bundle.R`) for the delivered red tide maps, and it is written into every bundle as `SCHEMA.md`, so the data travels with its description. The consumer it was designed for is the WFS-Portal application ([WFS-FEM/WFS-Portal](https://github.com/WFS-FEM/WFS-Portal), planned); any reader of CSV and JSON can use it. The plan and the decisions behind it are `docs/issue23_portal-bundle/issue23-portal-bundle-plan.md` in the RedTideMaps repository ([#23](https://github.com/WFS-FEM/RedTideMaps/issues/23)).

## 1. What the bundle is

The bundle is a data-only, text-only description of one map product on one grid: the monthly maps the pipeline delivers to Ecospace (`out/<res>min/ecospace_ascii/`), with a per-month summary, the FWC samples the maps were built from, the grid they sit on, the display facts of the product (palette recipe, band definition, units) and the provenance of the run. It holds no image and no binary file. A bundle is one grid plus one or more layers; the red tide bundle has one layer, `redtide`. Its identity is `bundle_id = <product>_<res>min`, `redtide_5min` for the 5-arcmin product; the resolution is encoded by the parent folder (`out/5min/`) and repeated in `meta.json`, and no file name inside the bundle carries the identity, so the folder is copied as a unit.

The values the bundle carries are the cells/L of each monthly ASCII file on the cells of the data domain, reproduced text for text (section 3.5); the Atlantic-side box carries no data (section 3.6). Everything else is derived from the run that wrote the maps.

## 2. Layout

```
out/5min/bundle/
  .gitattributes                 "* text eol=lf": LF in the index and in every checkout
  SCHEMA.md                      this document
  meta.json                      identity, grid header, month range, samples, nearshore set, clipping counts, provenance, build, cfg
  style.json                     display facts of the product: units, palette recipe, bands, code vocabularies
  grid.csv                       one row per template cell (5,148 at 5 arcmin)
  months.csv                     one row per month (504 today); the only place the placeholder flag lives
  layers.csv                     one row per layer (1); the only place the layer definitions live
  values/redtide/<yyyy>.csv      one file per calendar year, long sparse: the positive water cells of each month
  summary/redtide.csv            one row per month: the monthly summary
  samples/fwc_<yyyy>.csv         one file per calendar year: the filtered FWC samples of the product months
  ascii_md5.csv                  one row per ASCII file: the LF md5 of the map the bundle encodes
  manifest.csv                   file, bytes, md5 of every file above, .gitattributes included (written last)
```

Size at 5 arcmin: about 10 MB of text, comparable to the 10.6 MB of ASCII it describes; the values about 1.4 MB, the samples about 7 to 8 MB, `grid.csv` about 470 KB. A monthly pipeline run changes `values/redtide/<current year>.csv` (and the previous year's file when late samples change a hull-served month), `samples/fwc_<current year>.csv`, the changed rows of `summary/redtide.csv` and of `ascii_md5.csv`, `months.csv` only when the last data month moves, `meta.json` and `manifest.csv`.

## 3. Conventions

### 3.1 Text and line endings

Every file is text: CSV for tables, JSON for metadata, Markdown for this document. Every file is written through a binary connection with LF line endings, and the folder's `.gitattributes` pins LF at checkout, so a local copy, a fresh clone and a raw download from GitHub are byte-identical and the md5 values of `manifest.csv` hold everywhere. (R writes CRLF on Windows by default and git stores LF; without the pin the two would differ byte for byte.) A bundle never contains a carriage return byte (0x0D); the writer asserts it. Files are ASCII (valid UTF-8, no byte-order mark).

### 3.2 Numbers, logicals, missing values, the month key

- Every double is printed with 15 significant digits (`sprintf("%.15g", x)`, trailing zeros dropped) or, where that text does not parse back to the same double, with 17 (`sprintf("%.17g", x)`). This is not always the shortest text that round-trips the double, so a port of the writer must use the same rule to be byte-identical. Map values never need the 17-digit form (the ASCII files carry at most 15 significant digits). Two thirds of the longitudes and two thirds of the latitudes in `grid.csv` need it (3,432 of 5,148 each at 5 arcmin; 4,576 rows have at least one 17-digit coordinate), and so do about half of the sample coordinates: the FWC coordinates are six-decimal values that the pipeline's parser stored one ulp off in about half the rows, and they are kept as those exact doubles (rounding them to six decimals would move 33 samples across cell edges).
- A double prints in exponent form (`1e-05`, `1e+15`) when its magnitude is below 1e-4 or at or above 1e15 (1e17 for the 17-digit form); no value of the red tide bundle does (the smallest positive map value is above 100 cells/L, the largest below 1e9).
- Integers print as integers, logicals as `TRUE` / `FALSE`, missing values as the bare token `NA` in every column, quoted character columns included.
- `yrmo` is a six-character string, `"198501"`; read it as character (`colClasses = c(yrmo = "character")` in R), never as a number.
- `Inf` appears only in `style.json`, as the string `"Inf"` in the band breaks.

### 3.3 CSV dialect and quoting

Every CSV file has one header row, comma-separated fields, a period as the decimal mark, no row-name column and LF line ends. Files quote exactly their character columns (so `layers.csv$name`, which contains a comma, is quoted), never a number, a logical or `NA`; the header fields are quoted in a file that quotes a column. The values files, whose three columns can hold no comma or quote, are written without any quotes, header included. A double quote inside a field would be doubled; no field holds one in schema 1.0. `read.csv()` reads every form.

### 3.4 Order

The order of every file is deterministic: months ascending; values by `yrmo` then `cell`; samples by `year, month, lat, lon, cells`, all ascending; cells by `cell`; `ascii_md5.csv` by month; `manifest.csv` by path in C-locale byte order (`sort(method = "radix")` in R), the same on every machine. A reader matches manifest rows by `file`, never by position. A rerun of the writer with the same inputs is therefore byte-identical except the volatile keys of `meta.json` (section 6) and, through them, the `meta.json` row of `manifest.csv`.

### 3.5 Which reading of the ASCII the bundle reproduces

The bundle values are identical to the text of the ASCII files, parsed as doubles (`scan()` in R; 15 significant digits). Readers that go through GDAL (the `raster` and `terra` packages, QGIS) see the same files as 32-bit floats and differ from the text at the 16th significant digit in some months, as the pipeline's own combined stack (a float32 raster) does. Comparisons against such readers use a tolerance (`isTRUE(all.equal())` in R), never exact equality. Two derived columns carry a tolerance rule for the same reason: `n_changed` counts a cell as changed when `abs(M - S) > 1e-9 * max(abs(S), 1)` (section 5.4), and an exposure recomputed from a float32 reading agrees with the bundle within 1e-3 cells/L (the measured maximum difference is about 1e-9).

### 3.6 The grid, the cell order and the Atlantic-side box

The grid is the depth template of the pipeline (`template rasters/depth 5min 66x78.asc` at 5 arcmin): 78 columns by 66 rows of 1/12 degree, extent -87.5 to -81 E and 25 to 30.5 N, WGS 84 longitude and latitude (EPSG:4326). Cells are numbered row-major from the northwest corner, `cell = (row - 1) * ncols + col`, the numbering of the `raster` package and the token order of the ASCII files. The cell size is exactly 1/12 degree: `dx = (xmax - xmin) / ncols` and `dy = (ymax - ymin) / nrows` from `meta.grid.extent` in double arithmetic. The `cellsize` string of the ASCII header, repeated in `meta.grid.cellsize`, is a 15-digit rounding of that value and must not be used for cell arithmetic. Cell centers are `xmin + (col - 0.5) * dx` and `ymax - (row - 0.5) * dy`. Land is the set of template cells with no depth (1,310 at 5 arcmin; NODATA in every ASCII file); water is the rest (3,838).

The Atlantic-side box (cell center longitude greater than -82 and latitude greater than 28.5; 56 water cells at 5 arcmin) is excluded from everything the project computes: the pipeline keeps it out of the nearshore set and the sample filter, and the bundle treats it as land for every value and metric. The data domain is the water outside the box (`grid.csv$domain`; 3,782 cells at 5 arcmin): the values files list domain cells only, a reader rebuilds the box as missing, and exposure, the bands, the thresholds, the maximum and the cells changed run over the domain. The box cells keep `water = TRUE` and `atlantic = TRUE`, so a viewer can draw them as water without values. The delivered maps themselves still carry values there today (the MODIS nFLH polygons are not confined to the Gulf, so 94 of the 504 months hold positive cells on the Atlantic coast, about 1% of the record's exposure), which is why the bundle's metrics are smaller than a count over all water cells in those months; the pipeline's own tables counted all water cells until this schema, and zeroing the box in the delivered maps is a planned pipeline change.

The ASCII files write their NODATA value, -3.4e+38, and a reader that parses the text must treat any value below -1e30 as missing: the first token of every file is printed in full, a 39-digit integer part followed by a decimal point and 15 zeros (56 characters with the sign), rather than in scientific notation.

## 4. The files

### 4.1 `meta.json`

One object, written by `jsonlite::toJSON(auto_unbox = TRUE, pretty = TRUE, digits = NA)`. The layer definitions live in `layers.csv` and the placeholder flag in `months.csv`, not here. Shapes: `clipping` is a flat object of seven integers; `samples` and `nearshore` are an object or `null`; `extent` is a four-element array `[xmin, xmax, ymin, ymax]`; `months.first`, `months.last`, `months.last_data` and `samples.last_month` are `yrmo` strings; `samples.date_from` and `samples.date_to` are `YYYY-MM-DD`; `build.built_at` is UTC in ISO 8601; `build.toggles` and `cfg` are flat objects.

| key | content |
|---|---|
| `schema_version` | `"1.0"` |
| `bundle_id`, `product`, `product_name`, `res_arcmin` | `"redtide_5min"`, `"redtide"`, `"Red Tide Maps"`, `5` |
| `grid` | `ncols`, `nrows`, `xllcorner`, `yllcorner`, `cellsize` (as the ASCII header prints them), `nodata`, `crs` (`"EPSG:4326"`), `extent`, `n_cells`, `n_water`, `n_domain` (the cells that carry data), `domain_rule` (one sentence), `cell_order` (the sentence of section 3.6), `template` (the template file, repository-relative; its base name when the template lives outside the repository), `atlantic_box` (`{"lon_gt": -82, "lat_gt": 28.5}`) |
| `months` | `first`, `last`, `n`, `last_data` (the last month with an FWC sample), `n_placeholder` (the months after it) |
| `samples` | `file_pattern`, `source`, `file` (the filtered samples file the run used), `date_from`, `date_to` (the sample date range parsed from that file's name; `null` when the name carries no `yyyymmdd-yyyymmdd` range), `n_rows_filtered` (the rows of the filtered file, all years and missing counts included), `n_rows_bundle` (the rows written to `samples/`), `last_month` (equals `months.last_data`), `coordinate_note`; `null` when a bundle carries no samples |
| `nearshore` | `rule`, `n_cells`, `km2` (rounded to a whole km2); `null` when both nearshore rules of the run are `"none"` |
| `clipping` | the count of months by `use` (`hybrid`, `viirs`, `hybrid_modis`, `modis`, `pred`), `hybrid_changed`, `hull_flagged` |
| `source` | `repo`, `branch`, `ascii_dir`, `ascii_commit`, `ascii_dirty` (`true`, `false`, or `null` when git could not answer), `ascii_md5`, `head_commit`, `schema_url` (section 6) |
| `build` | `built_at`, `r_version`, `raster_version` (the package's own version string, as its DESCRIPTION prints it), `writer`, `run_log` (the pipeline log of the run, `null` for a standalone call), `mode` (`"pipeline"` or `"standalone"`), `toggles` (the run toggles of the pipeline configuration; a key absent from the configuration is `null`) |
| `cfg` | the map-determining keys of the pipeline configuration (a key absent from the configuration is `null`). Path keys are never written. |

Example (the 5-arcmin bundle; `<...>` marks values that change with the run):

```json
{
  "schema_version": "1.0",
  "bundle_id": "redtide_5min", "product": "redtide", "product_name": "Red Tide Maps", "res_arcmin": 5,
  "grid": {"ncols": 78, "nrows": 66, "xllcorner": -87.5, "yllcorner": 25, "cellsize": 0.0833333333333333,
           "nodata": -3.4e+38, "crs": "EPSG:4326", "extent": [-87.5, -81, 25, 30.5],
           "n_cells": 5148, "n_water": 3838, "n_domain": 3782,
           "domain_rule": "the cells that carry data: water cells outside the Atlantic-side box, which is treated as land",
           "cell_order": "row-major from the northwest corner: cell = (row - 1) * ncols + col, the raster package numbering and the ASCII token order",
           "template": "template rasters/depth 5min 66x78.asc",
           "atlantic_box": {"lon_gt": -82, "lat_gt": 28.5}},
  "months": {"first": "198501", "last": "202612", "n": 504, "last_data": "202610", "n_placeholder": 2},
  "samples": {"file_pattern": "samples/fwc_<yyyy>.csv",
              "source": "FWC GIS Open Data, Harmful Algal Bloom (HAB) Events layers (ArcGIS REST services)",
              "file": "FWC HAB data 19800102-20261021_filtered.Rdata", "date_from": "1980-01-02", "date_to": "2026-10-21",
              "n_rows_filtered": 183402, "n_rows_bundle": 181411, "last_month": "202610",
              "coordinate_note": "exact doubles of the pipeline (6-decimal source values, about half stored one ulp off, printed with 17 digits where needed); cell is computed from them"},
  "nearshore": {"rule": "mask5adj", "n_cells": 189, "km2": 14205},
  "clipping": {"hybrid": 155, "viirs": 0, "hybrid_modis": 123, "modis": 0, "pred": 226, "hybrid_changed": 210, "hull_flagged": 10},
  "source": {"repo": "https://github.com/WFS-FEM/RedTideMaps", "branch": "main",
             "ascii_dir": "out/5min/ecospace_ascii",
             "ascii_commit": "<40-hex sha of the last commit touching out/5min/ecospace_ascii>",
             "ascii_dirty": false,
             "ascii_md5": "<32-hex md5 of the concatenated month md5s>",
             "head_commit": "<40-hex sha of HEAD at build time>",
             "schema_url": "https://github.com/WFS-FEM/RedTideMaps/blob/<head_commit>/docs/issue23_portal-bundle/bundle-schema.md"},
  "build": {"built_at": "<2026-11-10T15:04:11Z>", "r_version": "4.5.1", "raster_version": "3.6-32", "writer": "scripts/write_bundle.R",
            "run_log": "<run_20261110.log>", "mode": "pipeline",
            "toggles": {"update_modis": false, "rebuild_nflh": false, "fwc_refresh": false, "fwc_force_full": false,
                        "incremental_fit": true, "fit_nb": false, "export_ecospace": false, "write_bundle": true}},
  "cfg": {"res": 5, "styr": 1985, "enyr": 2026, "hull_link_km": 75, "hull_buffer_km": 10, "hull_min_pts": 4, "hull_concavity": 2,
          "hull_warn_span_km": 300, "viirs_nearshore": "mask5adj", "modis_nearshore": "mask5adj", "use_viirs": true, "use_modis": true}
}
```

### 4.2 `style.json`

Facts about the product that a consumer needs to draw it as the pipeline does; nothing about layout, sizes, fonts or colors chosen for display, which belong to the consumer. This file changes only when the pipeline's own palette or the band convention changes, with a note in section 10.

| key | content |
|---|---|
| `schema_version` | `"1.0"` |
| `units` | `"cells/L"` |
| `palette` | `type` (`"ramp"`), `anchors` (the eleven color names of the pipeline PDFs), `bias` (2), `breaks` (`zero`, `first_colored`, `step`, `last`), `above` (the color above `last`), `colors_hex` (the 402 colors the recipe expands to). The recipe: `colors = c(colorRampPalette(anchors, bias = bias)(401), above)` and `brks = c(zero, first_colored - 1, seq(first_colored, last, step), Inf)`; color `k` applies to the values `brks[k] < v <= brks[k + 1]`, with `v = 0` in color 1. So color 1 (white) covers 0 and the values up to and including `first_colored - 1` (9,999 cells/L), color 2 the values above that up to 10k, colors 3 to 401 the 399 steps of 10k from 10k to 4M, and color 402 (darkred) everything above 4M. |
| `bands` | `breaks` (`[0, 1000, 10000, 100000, 1000000, "Inf"]`), `right_closed` (`true`), `columns` (the five band columns of the summary), `sample_columns` (the five sample band columns), `labels` (`"<= 1k"`, `"1k to 10k"`, `"10k to 100k"`, `"100k to 1M"`, `"> 1M"`) |
| `codes` | the vocabularies of the summary's categorical columns with one-line meanings: `use`, `fit_status`, `viirs_status` |

Example:

```json
{"schema_version": "1.0", "units": "cells/L",
 "palette": {"type": "ramp",
             "anchors": ["white", "purple", "blue", "darkblue", "cyan", "green", "darkgreen", "yellow", "orange", "red", "darkred"],
             "bias": 2, "breaks": {"zero": 0, "first_colored": 10000, "step": 10000, "last": 4000000}, "above": "darkred",
             "colors_hex": ["#FFFFFF", "<400 more>", "#8B0000"]},
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

### 4.3 `grid.csv`

One row per template cell, in cell order. Required columns (what every bundle on this schema carries): `cell, row, col, lon, lat, water, domain, km2`. Optional columns, present in the red tide bundle: `depth_m, nearshore, atlantic`.

| column | type | definition |
|---|---|---|
| `cell` | integer | 1 to `n_cells`, row-major from the northwest corner |
| `row`, `col` | integer | 1-based; row 1 is the northernmost |
| `lon`, `lat` | double | the cell center, `xmin + (col - 0.5) * dx` and `ymax - (row - 0.5) * dy` (section 3.6), full precision, so a point-in-cell lookup round-trips |
| `water` | logical | `TRUE` where the template has a depth, `FALSE` on land |
| `domain` | logical | `TRUE` for the cells that carry data: water outside the Atlantic-side box (3,782 at 5 arcmin); `FALSE` on land and in the box |
| `km2` | double | the cell area (`raster::area()` of the template; 73.7 to 77.5 km2 at 5 arcmin) |
| `depth_m` | double | the template depth; `NA` on land |
| `nearshore` | logical | `TRUE` for the cells of the run's nearshore set, `FALSE` on other water, `NA` on land; absent when both nearshore rules are `"none"` |
| `atlantic` | logical | `TRUE` where the cell center lies in the Atlantic-side box (section 3.6): water drawn without data |

### 4.4 `months.csv`

One row per month of the product, ascending: `yrmo` (character), `year`, `month` (integer), `index` (1 to `n`), `label` (`"1985-01"`), `placeholder` (logical). The months are contiguous calendar months from `meta.months.first` (a January) to `meta.months.last` (a December), `n = 12 * number of years`, with no gap; `index` is the position in that sequence. `placeholder` is `TRUE` for the months after the last month with an FWC sample, whose maps are zero by construction because the pipeline writes the whole current year (section 5.3); in a bundle without samples it is `FALSE` throughout, `last_data` equals `last` and `n_placeholder` is 0.

### 4.5 `layers.csv`

One row per layer: `id`, `name`, `units`, `encoding`, `file_pattern`, `summary_file`, `total_column`, `fill`, `precision`, `description`; every column character except `fill` (double). The red tide row: `redtide`, `Karenia brevis cell concentration, delivered map`, `cells/L`, `long_sparse`, `values/redtide/<yyyy>.csv`, `summary/redtide.csv`, `exposure`, `0`, `15 significant digits, 17 where 15 do not round-trip`, `sdmTMB prediction clipped by the VIIRS / MODIS / hull cascade with the nearshore hybrid, rule mask5adj` (the rule name is the run's nearshore rule). `encoding` has one value in schema 1.0, `long_sparse` (section 4.6).

### 4.6 `values/<layer>/<yyyy>.csv`

Columns `yrmo, cell, value`, unquoted: `yrmo` character (section 3.2); `cell` integer, a domain cell of `grid.csv` (`domain` is `TRUE`), unique within a month; `value` double, finite and strictly positive, usually fractional, printed per section 3.2. One row per domain cell with a value above zero in each month of that year, sorted by `yrmo` then `cell`. Cells not listed are 0 on the domain and missing elsewhere (land and the Atlantic-side box). There is one file per calendar year of the month range, from the year of `first` to the year of `last`; a year without a positive cell still has its file, with the header line only. To rebuild a month: a vector of `n_cells` zeros, `NA` where `grid.csv$domain` is `FALSE`, then the listed values at their cells.

### 4.7 `summary/<layer>.csv`

One row per month, ascending. The map metrics are computed on the domain cells of the delivered map (section 3.6); the bands are right-closed on the positive cells (section 5.1); the exposure is the sum of cells/L over the domain cells (section 5.2). The sample-derived columns (`n_samples` through `in_ge10k`) are optional in the schema: a bundle without samples omits them, and a reader treats an absent optional column as all `NA`. Every column derived from an optional input of the writer (`n_changed`, `hull_span_km`, `hull_flagged`, `fit_status`, `converged`, `viirs_status`) is `NA` throughout when that input was not supplied.

| column | type | definition |
|---|---|---|
| `yrmo`, `year`, `month` | character, integer, integer | the month |
| `use` | character | the clip source the delivered map is built on: `hybrid` (the VIIRS clip with the hull footprint added inside the nearshore set), `viirs` (the VIIRS clip as it is), `hybrid_modis` (the MODIS clip with the hull footprint added inside the nearshore set), `modis` (the MODIS clip as it is), `pred` (the hull-clipped prediction, no satellite coverage); `viirs` and `modis` occur only when a nearshore rule of the run is `"none"` |
| `hybrid_changed` | logical | the pipeline's own flag: the nearshore rule changed at least one cell of the month (section 5.4) |
| `n_changed` | integer | the water cells the nearshore rule changed (section 5.4); 0 for `viirs`, `modis` and `pred` months; `NA` for a `hybrid` (`hybrid_modis`) month when the VIIRS-clipped (MODIS-clipped) stack was not available to the writer |
| `hull_span_km` | double | the largest span of the month's hull footprint (`max_span_km` of the pipeline's hull diagnostics); 0 for a month with samples but no positive sample, which has no footprint; `NA` for a month without a diagnostics row (no samples that month; 19 months today) |
| `hull_flagged` | logical | the pipeline's hull flag: the footprint spans more than the configured limit and the month is hull-served (`use == "pred"`); `FALSE` for a satellite month whose footprint serves only inside the nearshore set and for a month without a footprint; `NA` for a month without a diagnostics row |
| `fit_status` | character | `fitted` (a model was fit), `failed` (a layer exists but is all zero), `none` (no fit attempted: fewer than six positive samples) |
| `converged` | logical | the convergence flag of the lognormal fit; `NA` when no model was fit |
| `viirs_status` | character | `positive` (a VIIRS layer with detections), `zero` (a VIIRS layer with none), `missing` (inside the VIIRS era but the tif is missing), `no_coverage` (outside the VIIRS era) |
| `n_samples` | integer | the filtered FWC samples of the month with a non-missing count, zero counts included |
| `n_samples_water` | integer | those on a domain cell (water outside the Atlantic-side box; the pipeline keeps no sample in the box, so this is every sample on a water cell) |
| `n_samples_pos` | integer | those with a count above zero |
| `s_le1k`, `s_1k_10k`, `s_10k_100k`, `s_100k_1M`, `s_gt1M` | integer | the positive samples by band; they sum to `n_samples_pos` |
| `samples_ge10k` | integer | the water samples at or above 10k cells/L |
| `in_ge10k` | integer | how many of them sit in a cell where the map is above zero |
| `exposure` | double | the sum of cells/L over the domain cells, unrounded |
| `n_pos` | integer | the domain cells above zero |
| `n_le1k`, `n_1k_10k`, `n_10k_100k`, `n_100k_1M`, `n_gt1M` | integer | the positive cells by band; they sum to `n_pos` |
| `n_ge10k`, `km2_ge10k` | integer, double | the cells at or above 10k cells/L and their area |
| `n_ge100k`, `n_ge1M` | integer | the cells at or above 100k and at or above 1M cells/L |
| `max_cells`, `max_cell` | double, integer | the maximum value over the domain cells and its cell (the first on ties); `max_cells` is 0 and `max_cell` is `NA` when the month is all zero |

### 4.8 `samples/fwc_<yyyy>.csv`

Columns `year, month, cells, lon, lat, cell, water`: `year`, `month` integer; `cells` double, the count in cells/L (integer-valued in the FWC data); `lon`, `lat` double (section 3.2); `cell` integer; `water` logical. The rows are the pipeline's filtered FWC samples (the Atlantic box removed, the grid box applied) with a count, for the years of the product, one file per calendar year of the month range (header-only when the year has no row), plus `cell`, the template cell of the coordinates, and `water`, the `grid.csv$water` flag of that cell. `cell` is computed as `raster::cellFromXY()` does: `col = floor((lon - xmin) * ncols / (xmax - xmin)) + 1` (`col = ncols` when `lon == xmax`), `row = floor((ymax - lat) * nrows / (ymax - ymin)) + 1` (`row = nrows` when `lat == ymin`), `cell = (row - 1) * ncols + col`, in double arithmetic (the multiplier is exactly 12 at this grid; dividing by `dx` instead gives the same cell for every in-range sample today), and `cell` is `NA` when `col` is outside 1 to `ncols` or `row` outside 1 to `nrows`. A point on a cell edge resolves by that arithmetic; a reader should use the printed `cell`, which the writer computed this way, rather than recompute it. `cell` and `water` are `NA` for the few rows that lie just outside the template (today 93 rows up to two hundredths of a degree north of 30.5 N: the sample filter crops to the template's bounding box in spherical geometry, whose northern edge bows a few hundredths of a degree north of 30.5 N between the corners, so a few Panhandle stations just north of the grid pass the filter). Duplicate rows (the same station, count and month on different days) are kept as delivered. Sorted by `year, month, lat, lon, cells`, so a monthly run appends at the end of the current year's file.

### 4.9 `ascii_md5.csv`

Columns `yrmo, file, bytes, md5`: for each monthly ASCII file, its base name (`sdmTMB_log__<yyyymm>.asc`, inside `meta.source.ascii_dir`), the byte count of its content with every carriage return byte removed, and the md5 (32 lowercase hexadecimal characters) of those same bytes, so that `bytes` and `md5` describe the same byte string on a CRLF working tree, an LF checkout and a GitHub raw download, and `md5` equals the md5 of the file's content as git stores it (what `git show <commit>:<path>` prints). This is the staleness guard: a consumer with the ASCII files beside the bundle can verify that the bundle describes them (the pipeline's check script and the WFS-Portal fetch script do). `meta.json$source$ascii_md5` is the md5 of the ASCII bytes of the `md5` strings of every row, joined with no separator and no trailing newline, in the row order of the file (`paste0(md5, collapse = "")` in R; 504 strings today): one value to compare.

### 4.10 `manifest.csv`

Columns `file, bytes, md5`: every file of the bundle except the manifest itself, `.gitattributes` included, paths relative to the bundle folder with `/` separators, `bytes` integer and `md5` as in section 4.9 (the files are LF already). Written last.

### 4.11 `SCHEMA.md` and `.gitattributes`

This document and the one-line attributes file, both written LF by the writer (never copied byte for byte from a working tree, which may be CRLF).

## 5. Definitions

### 5.1 Bands

The five classes of the FWC monitoring reports, right-closed on the positive values: `cut(v[v > 0], c(0, 1e3, 1e4, 1e5, 1e6, Inf), include.lowest = TRUE)`. A value of exactly 1k falls in `<= 1k`, exactly 10k in `1k to 10k`, exactly 1M in `100k to 1M`. Zeros are not in any band. The same rule applies to map cells and to samples. Threshold columns (`n_ge10k`, `samples_ge10k`, and so on) are inclusive: at or above the threshold. So `n_ge10k` equals the sum of the three upper bands unless a cell is exactly 10k cells/L, which is counted in `n_ge10k` but banded `1k to 10k` (no such cell today; the writer reports one when it occurs).

### 5.2 Exposure

The sum of cells/L over the domain cells of a month, with no area weighting: the exposure of a map as Ecospace reads it over the Gulf, and what every map panel of the pipeline's comparison figures prints first (those figures counted all water cells, the Atlantic-side box included; the bundle leaves the box out, section 3.6).

### 5.3 Placeholder months

The pipeline models and writes every month of the current year, so the months after the last month with an FWC sample carry zero maps that are not forecasts. `months.csv$placeholder` marks them; `meta.json$months$last_data` names the last data month. A placeholder month has its row in `months.csv` and in `summary/<layer>.csv` (every map metric zero, `max_cell` `NA`, `n_samples` 0, `use` as the pipeline recorded it) and no row in the values files. A viewer should not offer placeholder months; the bundle keeps them because the Ecospace deliverable carries them.

### 5.4 `hybrid_changed` and `n_changed`

`hybrid_changed` is the pipeline's own flag, written when the maps are combined: an exact comparison, in memory, of the delivered layer with the satellite-clipped layer it was built on. `n_changed` is the writer's count of the same difference from the bundle's own values: for a `hybrid` month, the domain cells where the delivered map differs from the VIIRS-clipped layer; for a `hybrid_modis` month, from the MODIS-clipped layer; both layers normalized as the pipeline writes them (missing to 0 on the domain). The nearshore set lies inside the domain, so leaving the box out changes no count. A cell counts as changed when `abs(M - S) > 1e-9 * max(abs(S), 1)`, a relative tolerance that ignores the float32 representation of the pipeline's stacks (section 3.5). The two agree in every month of the current bundle (`hybrid_changed` is `TRUE` exactly where `n_changed > 0`, 210 months), and the pipeline's check script asserts the agreement.

### 5.5 `hull_span_km` and `hull_flagged`

The pipeline flags a month whose largest hull footprint spans more than `cfg$hull_warn_span_km` (300 km by default) and reports the flag only for the months the hull path serves (`use == "pred"`), because the satellite months use the footprint only inside the nearshore set. `hull_flagged` follows that rule. `hull_span_km` carries the span itself for every month with a diagnostics row (every month with samples; 0 where the samples are all zero and there is no footprint); both columns are `NA` for a month without samples.

### 5.6 `fit_status`, `converged`, `viirs_status`

`fit_status` comes from the unclipped prediction layer of the month (`none` when the pipeline did not fit the month, `failed` when the layer is all zero, `fitted` otherwise); `converged` from the pipeline's fit record of the lognormal model; `viirs_status` from the VIIRS stack of the run (its first and last layer bound the VIIRS era). The code lists of `style.json` repeat the meanings.

## 6. Provenance

- `source.ascii_commit` is the last commit that changed the maps the bundle encodes (`git log -1 -- out/<res>min/ecospace_ascii/` at build time). `source.ascii_dirty` is `TRUE` when the ASCII files on the writer's disk differ from that commit (a monthly run, whose new maps are not yet committed) and `FALSE` on a verification run that reproduced the committed maps. `source.ascii_md5` ties the bundle to the exact ASCII bytes (section 4.9).
- `source.head_commit` is the repository HEAD at build time, informational: the parent of the commit that will carry the bundle. The bundle's own commit cannot be known when it is written; it is stated in the message of the `data:` commit that carries it, and a consumer records it beside its copy (WFS-Portal writes it to `FETCH.json`). On a monthly run the bundle and the new ASCII files go into the same `data:` commit; otherwise `source.ascii_commit` names the earlier commit that holds the maps.
- `source.schema_url` is `https://github.com/WFS-FEM/RedTideMaps/blob/<head_commit>/docs/issue23_portal-bundle/bundle-schema.md`, the document this file copies, at the build commit; it is `null` when `head_commit` is `"unknown"`.
- `build.mode` is `"pipeline"` when step 9 of a run wrote the bundle and `"standalone"` when the writer was called from the console against a run on disk (a schema change, a verification). When git cannot be called, the string keys of `source` read `"unknown"` and `ascii_dirty` is `null`; a base-R fallback that reads the repository's own files fills `head_commit` and `branch` only.
- Volatile keys, the only ones that differ between two writes of the same inputs: `build.built_at`, `build.run_log`, `build.mode`, and the `source` block.

## 7. Optional files and columns; other products on this schema

Optional in schema 1.0: `samples/` (absent, with `meta.samples` `null` and the sample-derived summary columns omitted, in a bundle without point samples); `grid.csv$depth_m`, `nearshore`, `atlantic`; `meta.nearshore` (`null` when the run used no nearshore rule); and, for a layer that is not red tide, every `summary` column beyond the generic set of the next paragraph. A reader treats an absent optional column as all `NA`; a present optional column may hold `NA` where its definition says so.

A bundle for another product on the same grid (an Ecospace run, with one layer per species or fleet) uses the same files: the same `grid.csv` (the same domain: the box carries no data in any product), its own `months.csv`, one `layers.csv` row per layer with its `units` and `total_column`, `values/<layer_id>/<yyyy>.csv`, `summary/<layer_id>.csv` with at least `yrmo, year, month, total, mean, n_pos, max_value, max_cell` (the generic set; `total_column` names the total, `total`), no `samples/`, and a `style.json` with its palette recipe and `"bands": null`. The red tide summary names its total `exposure` and its maximum `max_cells`, as the pipeline's own tables do.

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
M[!grid$domain, ] <- NA   # land and the Atlantic-side box carry no data
M[cbind(vals$cell, match(vals$yrmo, months$yrmo))] <- vals$value
# M[, "201809"] is the September 2018 map in cell order.
z <- matrix(M[, "201809"], nrow = meta$grid$ncols)[, meta$grid$nrows:1]
# z has its first index west to east and its second index south to north, as image() expects:
image(sort(unique(grid$lon)), sort(unique(grid$lat)), z)
```

Verify a copy: recompute `tools::md5sum()` of every file and compare with `manifest.csv`.

## 9. Attribution

The maps are produced by the WFS-FEM/RedTideMaps pipeline (Chagaris, Vilas, Harris; MIT license) on the West Florida Shelf Ecospace grid (Vilas et al. 2023), as part of the project "Operationalizing the West Florida Shelf ecosystem model and application to red tides, stock assessment, and catch advice for Gulf of Mexico reef fish" (PI David Chagaris, University of Florida). In situ Karenia brevis cell counts: Florida Fish and Wildlife Conservation Commission, Fish and Wildlife Research Institute, Harmful Algal Bloom (HAB) Events layers of the FWC GIS Open Data (ArcGIS REST services). Satellite bloom detection: University of South Florida Optical Oceanography Laboratory (PI Chuanmin Hu), monthly VIIRS red tide probability maps (Hu et al. 2015; Yao et al. 2023) and MODIS nFLH served by NOAA CoastWatch ERDDAP (Hu et al. 2005). Model: sdmTMB. The maps are model products, not observations, and not an FWC or USF product; the repository README describes the method and its limits.

## 10. Version history

| version | date | change | commit |
|---|---|---|---|
| 1.0 | 4 Nov 2026 | first version: the layout, conventions, files and definitions above (#23) | the first commit of this file in WFS-FEM/RedTideMaps |

A minor version adds files, columns or keys (readers ignore unknown ones); a major version renames, removes or changes the meaning of anything (the band definition, the cell order, the layout, the meaning of a provenance key). A consumer accepts the major version it was written for and warns on a newer minor one.
