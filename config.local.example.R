#' Local overrides for run_redtide_maps.R.
#'
#' Copy this file to config.local.R in the repo root and edit it.
#' config.local.R is gitignored, so machine-specific paths never reach the
#' repository - this is the only file you should need to touch to run the
#' workflow somewhere else.
#'
#' The driver sources it AFTER building the `cfg` defaults and BEFORE using
#' any of them, so uncomment only the lines you actually want to change.


# Export the monthly ASCII files to the Ecospace "ST drivers" folder.
# The files land in <ecospace_root>/<res>min/red tide/sdmTMB/, which must
# already exist - the run stops up front if it does not.
# cfg$ecospace_root   <- "C:/Users/<you>/University of Florida/WFS Fisheries Ecosystem Model - WFS EwE/Ecospace/ST drivers"
# cfg$export_ecospace <- TRUE


# Output resolution in minutes (5 or 15; templates ship in template rasters/).
# cfg$res <- 15L


# Keep inputs (cell_counts/, VIIRS/, MODIS/) and outputs (out/) outside the
# repo. Default: the repo root.
# cfg$proj_dir <- "D:/RedTideMaps-data"
