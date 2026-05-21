#' Canonical monthly red-tide map workflow.
#'
#' Pipeline:
#'   1. Ingest FWC HAB CSVs from cell_counts/ -> one merged Rdata.
#'   2. Spatially filter observations to the WFS Ecospace grid.
#'   3. Build per-month sdmTMB models (lognormal on positives + NB2).
#'   4. Predict to the depth-template grid -> monthly raster stack.
#'   5. Clip the stack to buffered concave hulls; optionally also to
#'      MODIS nFLH polygons and VIIRS probability rasters.
#'   6. Merge clipped stacks (VIIRS > MODIS > hulls) -> combined stack.
#'   7. Write per-month ASCII for Ecospace under out/<res>min/ecospace_ascii/.
#'   8. Optionally export ASCII files to the external Ecospace ST drivers.
#'
#' Monthly rerun checklist:
#'   - Download the latest "Recent HAB" CSV from
#'     https://geodata.myfwc.com/datasets/myfwc::recent-harmful-algal-bloom-hab-events/explore
#'     and place it next to the Historic CSV in `cfg$proj_dir/cell_counts/`.
#'   - Set `cfg$res` and `cfg$enyr` below.
#'   - Source this file.

# Config -----------------------------------------------------------------
cfg <- list(
  # Resolution (integer minutes). Supported here: 5, 15.
  res = 15L,

  # Year range to model
  styr = 1985,
  enyr = as.integer(format(Sys.Date(), "%Y")),

  # Repo root. Change if you cloned the repo to a different path.
  # All other paths default to subfolders of this one — the workflow is
  # standalone within the repo.
  repo_dir = "C:/Users/dchagaris/Github/WFS-FEM/RedTideMaps",

  # Working dir for inputs (cell_counts/, VIIRS/, MODIS/) and outputs.
  # Defaults to repo_dir so a fresh clone runs end-to-end without any
  # external paths. Override only if you keep data outside the repo.
  proj_dir = NULL,

  # Depth + excl ASCII templates. Defaults to the repo's template rasters/.
  bathy_dir = NULL,

  # Optional: external Ecospace ST drivers root (used only by export_to_ecospace).
  ecospace_root = "C:/Users/dchagaris/OneDrive - University of Florida/WFS Fisheries Ecosystem Modeling/WFS EwE/Ecospace/ST drivers",

  # Toggles
  use_viirs        = TRUE,
  use_modis        = TRUE,    # requires existing FLH polygons
  update_modis     = FALSE,   # set TRUE to pull/refresh ERDDAP nFLH first
  rebuild_nflh     = FALSE,   # set TRUE to rebuild FLH polygons from stack
  fwc_force_full   = FALSE,   # set TRUE to rebuild the FWC merged CSV from scratch
  export_ecospace  = FALSE    # set TRUE to copy ASCII drop to ecospace_root
)
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
rt_log(paths, "Step 1: ingest FWC HAB data from ArcGIS REST")
hab_files <- fn.get_fwc_data(dir_data   = paths$cellcnts,
                             urls_file  = cfg$fwc_urls,
                             force_full = cfg$fwc_force_full)

# 2) Spatial filter ------------------------------------------------------
rt_log(paths, "Step 2: spatial filter to WFS grid")
hab <- fn.filter_hab_data(file_hab   = hab_files$rdata,
                          file_depth = paths$file_depth,
                          file_excl  = paths$file_excl,
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
fit_files <- fn.fit_monthly_sdmTMB(habdata    = habdata,
                                   input_grid = input_grid,
                                   dir_sdmout = paths$sdm_out,
                                   dir_om     = file.path(paths$sdm_out, "OM_month"),
                                   styr       = cfg$styr,
                                   enyr       = cfg$enyr)

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
                                    enyr          = cfg$enyr)
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

# 5c) MODIS nFLH clipping (2003-2012)
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

# 6 + 7) Combine and write ASCII -----------------------------------------
rt_log(paths, "Step 6: combine clipped stacks + write ASCII for Ecospace")
combined_path <- make_redtide_ascii(file_hull    = clip_hull$file,
                                    file_viirs   = if (!is.null(clip_viirs)) clip_viirs$file else NULL,
                                    file_modis   = if (!is.null(clip_modis)) clip_modis$file else NULL,
                                    dir_ascii    = paths$ecospace,
                                    dir_combined = paths$combined,
                                    file_depth   = paths$file_depth,
                                    var          = "log")
fn.plot_redtide_stack(file_stack = combined_path, dir_plots = paths$plots_out)

# 8) Optional external export -------------------------------------------
if (isTRUE(cfg$export_ecospace)) {
  rt_log(paths, "Step 8: export ASCII drop to external Ecospace ST drivers")
  export_to_ecospace(dir_ascii     = paths$ecospace,
                     ecospace_root = cfg$ecospace_root,
                     res           = paths$res)
}

rt_log(paths, "Run complete.")
