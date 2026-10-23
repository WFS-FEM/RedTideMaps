#' Canonical monthly red-tide map workflow.
#'
#' Pipeline:
#'   1. Ingest FWC HAB CSVs from cell_counts/ -> one merged Rdata.
#'   2. Spatially filter observations to the WFS Ecospace grid.
#'   3. Build per-month sdmTMB models (lognormal on positives + NB2).
#'   4. Predict to the depth-template grid -> monthly raster stack.
#'   5. Clip the stack to buffered concave hulls; optionally also to
#'      MODIS nFLH polygons and VIIRS probability rasters. With
#'      cfg$viirs_nearshore / cfg$modis_nearshore = "mask5adj" (or the
#'      smaller set "mask5") the hull footprint is added to the satellite
#'      layers inside the nearshore set (the hybrids, issues #11, #10, #18).
#'   6. Merge clipped stacks (hybrid > VIIRS > hybrid_modis > MODIS > hulls)
#'      -> combined stack.
#'   7. Write per-month ASCII for Ecospace under out/<res>min/ecospace_ascii/.
#'   8. Optionally export ASCII files to the external Ecospace ST drivers.
#'
#' How to run:
#'   - From the repo root: `Rscript run_redtide_maps.R`, or open
#'     RedTideMaps.Rproj and source this file. Rscript also works from any
#'     directory when given the full path to this file.
#'   - Machine-specific settings (e.g. the Ecospace export folder) go in a
#'     gitignored config.local.R; copy config.local.example.R to start one.

# Repo root --------------------------------------------------------------
# Everything is resolved from the repo root, so find it rather than assume
# the working directory: the working directory if it holds the .Rproj,
# otherwise the folder this script was launched from by Rscript.
.rt_repo_root <- function() {
  if (file.exists("RedTideMaps.Rproj"))
    return(normalizePath(getwd(), winslash = "/"))
  f <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE))
  if (length(f) == 1) {
    d <- dirname(normalizePath(f, winslash = "/", mustWork = FALSE))
    if (file.exists(file.path(d, "RedTideMaps.Rproj"))) return(d)
  }
  stop("Can't find the repo root. Open RedTideMaps.Rproj, or setwd() to ",
       "the repo folder. Currently: ", getwd(), call. = FALSE)
}

# Config -----------------------------------------------------------------
cfg <- list(
  # Resolution (integer minutes). Supported here: 5, 15.
  res = 5L,

  # Year range to model
  styr = 1985,
  enyr = as.integer(format(Sys.Date(), "%Y")),

  # Repo root, detected above. All other paths default to subfolders of
  # this one — the workflow is standalone within the repo.
  repo_dir = .rt_repo_root(),

  # Working dir for inputs (cell_counts/, VIIRS/, MODIS/) and outputs.
  # Defaults to repo_dir so a fresh clone runs end-to-end without any
  # external paths. Override only if you keep data outside the repo.
  proj_dir = NULL,

  # Depth + excl ASCII templates. Defaults to the repo's template rasters/.
  bathy_dir = NULL,

  # Optional: external Ecospace "ST drivers" root, used only when
  # export_ecospace is TRUE. Machine-specific, so set it in config.local.R.
  ecospace_root = NULL,

  # Buffered-hull fallback (fn.buffered_hulls; see README "Why the clipping cascade")
  hull_link_km      = 75,     # single-linkage cut (km): positives farther apart than this get separate footprints
  hull_buffer_km    = 10,     # buffer (km) around each footprint
  hull_min_pts      = 4L,     # distinct locations needed for a concave hull; smaller clusters get buffered points
  hull_concavity    = 2,      # concaveman concavity for every hull (lower = tighter)
  hull_warn_span_km = 300,    # flag months whose largest footprint spans more than this (km) in hull_diagnostics.csv

  # Nearshore hybrid for VIIRS months (fn.nearshore_mask, fn.clip_2_hybrid; issues #11,
  # #15, #18; see README "Why the clipping cascade"). "mask5adj" (default since #18):
  # inside the nearshore set (cells in the VIIRS no-data mask, or within 5 km of the
  # coast, or touching a land cell of the basemap) a cell takes max(VIIRS-clipped,
  # hull-clipped); outside it the VIIRS result stands, zeros included. "mask5": the
  # same without the touching-land criterion (issue #8). "none": the VIIRS-clipped
  # layer is used as it is (the maps delivered before #18).
  viirs_nearshore  = "mask5adj",
  # The same rule for the months served from MODIS nFLH polygons (issue #10): the
  # same set, max(MODIS-clipped, hull-clipped) inside it. Needs use_viirs (the set
  # is read from the VIIRS stack) and use_modis.
  modis_nearshore  = "mask5adj",

  # Toggles
  use_viirs        = TRUE,
  use_modis        = TRUE,    # requires existing FLH polygons
  update_modis     = FALSE,   # set TRUE to pull/refresh ERDDAP nFLH first
  rebuild_nflh     = FALSE,   # set TRUE to rebuild FLH polygons from stack
  fwc_refresh      = TRUE,    # set FALSE to reuse the local FWC CSV without querying FWC (reproducing a run)
  fwc_force_full   = FALSE,   # set TRUE to rebuild the FWC merged CSV from scratch
  incremental_fit  = TRUE,    # skip months already fit (delete OM_month/<yyyymm>/ to force refit)
  fit_nb           = FALSE,   # set TRUE to also fit the NB2 model (only the log model is used downstream)
  export_ecospace  = FALSE   # set TRUE (in config.local.R) to copy the ASCII drop to ecospace_root
)

# Local overrides (gitignored); see config.local.example.R
if (file.exists(file.path(cfg$repo_dir, "config.local.R"))) {
  source(file.path(cfg$repo_dir, "config.local.R"))
  message("Applied local overrides from config.local.R")
}

# A mistyped nearshore rule must stop the run here, not in step 5.
for (.key in c("viirs_nearshore", "modis_nearshore")) {
  if (!is.character(cfg[[.key]]) || length(cfg[[.key]]) != 1 ||
      !cfg[[.key]] %in% c("none", "mask5", "mask5adj"))
    stop("cfg$", .key, " must be \"none\", \"mask5\" or \"mask5adj\" (got: ",
         paste(format(cfg[[.key]]), collapse = ", "), ").", call. = FALSE)
}
if (cfg$modis_nearshore != "none" && !(isTRUE(cfg$use_viirs) && isTRUE(cfg$use_modis)))
  stop("cfg$modis_nearshore = \"", cfg$modis_nearshore, "\" needs use_viirs = TRUE ",
       "(the nearshore set is read from the VIIRS stack) and use_modis = TRUE.", call. = FALSE)
if (cfg$viirs_nearshore != "none" && cfg$modis_nearshore != "none" &&
    cfg$viirs_nearshore != cfg$modis_nearshore)
  stop("cfg$viirs_nearshore and cfg$modis_nearshore must name the same set when both are on (got \"",
       cfg$viirs_nearshore, "\" and \"", cfg$modis_nearshore, "\").", call. = FALSE)

# Check the export destination now rather than after a 20-minute run. It
# must already exist: creating it would hide a mistyped root.
if (isTRUE(cfg$export_ecospace)) {
  if (!is.character(cfg$ecospace_root) || length(cfg$ecospace_root) != 1 ||
      !nzchar(cfg$ecospace_root))
    stop("export_ecospace is TRUE but ecospace_root is not set. ",
         "Set cfg$ecospace_root in config.local.R.", call. = FALSE)
  .dest <- file.path(cfg$ecospace_root, paste0(cfg$res, "min"), "red tide", "sdmTMB")
  if (!dir.exists(.dest))
    stop("Ecospace export folder not found: ", .dest,
         "\nCheck cfg$ecospace_root in config.local.R.", call. = FALSE)
}

# Resolve repo-relative defaults
if (is.null(cfg$proj_dir))  cfg$proj_dir  <- cfg$repo_dir
if (is.null(cfg$bathy_dir)) cfg$bathy_dir <- file.path(cfg$repo_dir, "template rasters")

# FWC URL list (one ArcGIS REST endpoint per line)
cfg$fwc_urls <- file.path(cfg$repo_dir, "data", "FWC HAB API query urls.txt")

# Setup ------------------------------------------------------------------
source(file.path(cfg$repo_dir, "scripts", "_setup.R"))
source(file.path(cfg$repo_dir, "scripts", "get_HAB_data.R"))
source(file.path(cfg$repo_dir, "scripts", "sdmTMB_HAB_data.R"))
source(file.path(cfg$repo_dir, "scripts", "process_VIIRS.R"))
source(file.path(cfg$repo_dir, "scripts", "process_MODIS.R"))
source(file.path(cfg$repo_dir, "scripts", "process_hybrid.R"))
source(file.path(cfg$repo_dir, "scripts", "polygon_clipping_rt.R"))

paths <- rt_paths(res          = cfg$res,
                  proj_dir     = cfg$proj_dir,
                  repo_dir     = cfg$repo_dir,
                  bathy_dir    = cfg$bathy_dir,
                  ecospace_dir = cfg$ecospace_root)
rt_init_dirs(paths)
rt_log(paths, sprintf("Starting run. res=%dmin styr=%d enyr=%d",
                      paths$res, cfg$styr, cfg$enyr))
rt_log(paths, paste0("Depth template: ", paths$file_depth))
rt_log(paths, paste0("Excl  template: ", paths$file_excl))

# 1) HAB data ingest -----------------------------------------------------
rt_log(paths, if (isTRUE(cfg$fwc_refresh))
  "Step 1: ingest FWC HAB data from ArcGIS REST" else
  "Step 1: FWC HAB data from the local merged CSV (fwc_refresh = FALSE: no query to FWC)")
hab_files <- fn.get_fwc_data(dir_data   = paths$cellcnts,
                             urls_file  = cfg$fwc_urls,
                             force_full = cfg$fwc_force_full,
                             refresh    = cfg$fwc_refresh)

# 2) Spatial filter ------------------------------------------------------
rt_log(paths, "Step 2: spatial filter to WFS grid")
hab <- fn.filter_hab_data(file_hab   = hab_files$rdata,
                          file_depth = paths$file_depth,
                          dir_out    = paths$sdm_out)
fn.plot_hab_data(points        = hab$points,
                 land_polygons = hab$land_polygons,
                 dir_out       = paths$plots_out)

# 3) Fit monthly sdmTMB --------------------------------------------------
rt_log(paths, "Step 3: build input grid + fit monthly sdmTMB")
input_grid <- fn.make_input_grid(file_depth = paths$file_depth,
                                 file_excl  = paths$file_excl)

# Drop observations outside the prediction grid box (defensive).
habdata <- hab$points
fit_files <- fn.fit_monthly_sdmTMB(habdata     = habdata,
                                   input_grid  = input_grid,
                                   dir_sdmout  = paths$sdm_out,
                                   dir_om      = file.path(paths$sdm_out, "OM_month"),
                                   styr        = cfg$styr,
                                   enyr        = cfg$enyr,
                                   incremental = cfg$incremental_fit,
                                   fit_nb      = cfg$fit_nb)

# 4) Predict to grid -----------------------------------------------------
rt_log(paths, "Step 4: predict monthly sdmTMB to grid")
pred_paths <- fn.predict_monthly_sdmTMB(file_sdmpred = fit_files$pred_array,
                                        file_depth   = paths$file_depth,
                                        dir_sdmout   = paths$sdm_out)
fn.plot_sdmTMB(file_log  = pred_paths$file_log,
               file_nb   = pred_paths$file_nb,
               dir_plots = paths$plots_out)

# 5) Clipping ------------------------------------------------------------
rt_log(paths, "Step 5: clipping cascade (hulls / MODIS / VIIRS)")

# 5a) Buffered concave hulls (always, scoped to fit year range)
file_hullpolys <- fn.buffered_hulls(file_filtered = hab$file,
                                    file_depth    = paths$file_depth,
                                    dir_out       = paths$sdm_out,
                                    styr          = cfg$styr,
                                    enyr          = cfg$enyr,
                                    link_km       = cfg$hull_link_km,
                                    buffer_km     = cfg$hull_buffer_km,
                                    min_hull_pts  = cfg$hull_min_pts,
                                    concavity     = cfg$hull_concavity,
                                    warn_span_km  = cfg$hull_warn_span_km)
clip_hull <- fn.clip_2_hulls(file_pred  = pred_paths$file_log,
                             file_polys = file_hullpolys,
                             file_depth = paths$file_depth,
                             dir_out    = paths$clipped_out)

# 5b) VIIRS clipping (2012-present)
clip_viirs <- NULL
if (cfg$use_viirs) {
  viirs <- fn.viirs_tifs2stack(dir_viirs = paths$viirs)
  clip_viirs <- fn.clip_2_viirs(file_pred  = pred_paths$file_log,
                                file_viirs = viirs$file,
                                file_depth = paths$file_depth,
                                dir_out    = paths$clipped_out)
}

# 5c) MODIS nFLH clipping (2002-07 to 2011-12, and later months without a VIIRS layer)
clip_modis <- NULL
if (cfg$use_modis) {
  if (cfg$update_modis) {
    fn.pull_MODIS_flh_erddap(file_depth     = paths$file_depth,
                             dir_modis      = paths$modis,
                             dir_modis_raw  = paths$modis)
  }
  if (cfg$rebuild_nflh) {
    fn.make_nflh_polys(dir_in     = paths$modis,
                       dir_out    = paths$modis,
                       file_depth = paths$file_depth)
  }
  file_flhpolys <- list.files(paths$modis, pattern = "^FLH polys",
                              full.names = TRUE)
  if (length(file_flhpolys) > 0) {
    clip_modis <- fn.clip_2_modis(file_pred     = pred_paths$file_log,
                                  file_flhpolys = file_flhpolys[1],
                                  file_depth    = paths$file_depth,
                                  dir_out       = paths$clipped_out)
  } else {
    rt_log(paths, "No FLH polys found; skipping MODIS clipping.")
  }
}

# 5d) Nearshore hybrids (issues #11 and #10): inside the nearshore set the
# hull footprint is added to the satellite-clipped layer (cell-wise
# maximum); outside it the satellite result stands, zeros included. Each
# rule is off by default. The set is built once, from the VIIRS stack.
clip_hybrid <- NULL; clip_hybrid_modis <- NULL
if (cfg$use_viirs && (cfg$viirs_nearshore != "none" || cfg$modis_nearshore != "none")) {
  rule <- if (cfg$viirs_nearshore != "none") cfg$viirs_nearshore else cfg$modis_nearshore
  nearshore <- fn.nearshore_mask(file_viirs = viirs$file,
                                 file_depth = paths$file_depth,
                                 file_coast = paths$file_coast,
                                 rule       = rule,
                                 dir_out    = paths$clipped_out)
  rt_log(paths, sprintf("Nearshore %s %s: %d cells, %s km2 (%d in the VIIRS no-data mask, %d within 5 km of the coast%s); inside the set max(satellite-clipped, hull-clipped), outside it the satellite result as is",
                        if (cfg$viirs_nearshore != "none") "rule" else "set", rule, nearshore$n_cells,
                        format(round(nearshore$km2), big.mark = ","),
                        nearshore$n_mask_cells, nearshore$n_coast_cells,
                        if (!is.na(nearshore$n_adjacent_cells))
                          sprintf(", %d adjacent to land", nearshore$n_adjacent_cells) else ""))
}
if (cfg$use_viirs && cfg$viirs_nearshore != "none") {
  clip_hybrid <- fn.clip_2_hybrid(file_sat_clipped  = clip_viirs$file,
                                  file_hull_clipped = clip_hull$file,
                                  file_mask         = nearshore$file,
                                  file_depth        = paths$file_depth,
                                  dir_out           = paths$clipped_out,
                                  source            = "viirs")
  rt_log(paths, sprintf("Hybrid: %d of %d VIIRS months changed by the nearshore rule: %s",
                        sum(clip_hybrid$months$changed), nrow(clip_hybrid$months),
                        paste(clip_hybrid$months$yrmo[clip_hybrid$months$changed], collapse = ", ")))
} else {
  rt_log(paths, "Nearshore rule: none (VIIRS-clipped layers used as they are)")
}
if (cfg$modis_nearshore != "none" && !is.null(clip_modis)) {
  # Only the months the cascade serves from MODIS: those without a VIIRS layer.
  modis_served <- setdiff(sub("^X", "", names(clip_modis$stack)),
                          sub("^X", "", names(clip_viirs$stack)))
  clip_hybrid_modis <- fn.clip_2_hybrid(file_sat_clipped  = clip_modis$file,
                                        file_hull_clipped = clip_hull$file,
                                        file_mask         = nearshore$file,
                                        file_depth        = paths$file_depth,
                                        dir_out           = paths$clipped_out,
                                        source            = "modis",
                                        months            = modis_served)
  rt_log(paths, sprintf("Hybrid (MODIS): %d of %d MODIS-served months changed by the nearshore rule: %s",
                        sum(clip_hybrid_modis$months$changed), nrow(clip_hybrid_modis$months),
                        paste(clip_hybrid_modis$months$yrmo[clip_hybrid_modis$months$changed], collapse = ", ")))
} else if (cfg$modis_nearshore != "none") {
  rt_log(paths, sprintf("Nearshore rule (MODIS) %s requested but there is no MODIS-clipped stack; skipped", cfg$modis_nearshore))
} else {
  rt_log(paths, "Nearshore rule (MODIS): none (MODIS-clipped layers used as they are)")
}

# 6 + 7) Combine and write ASCII -----------------------------------------
rt_log(paths, "Step 6: combine clipped stacks + write ASCII for Ecospace")
combined_path <- make_redtide_ascii(file_hull    = clip_hull$file,
                                    file_viirs   = if (!is.null(clip_viirs)) clip_viirs$file else NULL,
                                    file_modis   = if (!is.null(clip_modis)) clip_modis$file else NULL,
                                    file_hybrid  = if (!is.null(clip_hybrid)) clip_hybrid$file else NULL,
                                    file_hybrid_modis = if (!is.null(clip_hybrid_modis)) clip_hybrid_modis$file else NULL,
                                    dir_ascii    = paths$ecospace,
                                    dir_combined = paths$combined,
                                    file_depth   = paths$file_depth,
                                    var          = "log")
fn.plot_redtide_stack(file_stack = combined_path, dir_plots = paths$plots_out)

# Flagged hulls (largest footprint > hull_warn_span_km), reported only for
# the months the hull path actually serves (use == "pred" in
# clipping_source.csv; VIIRS and MODIS months never use the hull, and the
# hybrid months, VIIRS or MODIS, use it only inside the nearshore set). A flag is a prompt
# for a human look at the panel, not a failure: a real coast-wide bloom can
# exceed the threshold.
hull_diag <- read.csv(file.path(paths$sdm_out, "hull_diagnostics.csv"),
                      colClasses = c(yrmo = "character"))
clip_src  <- read.csv(file.path(paths$clipped_out, "clipping_source.csv"),
                      stringsAsFactors = FALSE)
hull_months  <- gsub("^X", "", clip_src$yrmo[clip_src$use == "pred"])
hull_flagged <- hull_diag$yrmo[hull_diag$flagged & hull_diag$yrmo %in% hull_months]
rt_log(paths, if (length(hull_flagged) == 0)
  sprintf("Hulls: no flagged hulls (max footprint span <= %g km) in the %d months served by the hull path.",
          cfg$hull_warn_span_km, length(hull_months)) else
  sprintf("Hulls: %d of %d hull-served month(s) have a footprint spanning > %g km: %s (inspect in plots/*_clipped_combined.pdf; details in sdm/hull_diagnostics.csv)",
          length(hull_flagged), length(hull_months), cfg$hull_warn_span_km,
          paste(hull_flagged, collapse = ", ")))

# 8) Optional external export -------------------------------------------
if (isTRUE(cfg$export_ecospace)) {
  rt_log(paths, "Step 8: export ASCII drop to external Ecospace ST drivers")
  export_to_ecospace(dir_ascii     = paths$ecospace,
                     ecospace_root = cfg$ecospace_root,
                     res           = paths$res)
}
rt_log(paths, "Run complete.")
