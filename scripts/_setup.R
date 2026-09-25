#' Setup: libraries and path helpers for the RedTideMaps workflow.
#'
#' Source this once at the top of run_redtide_maps.R, after defining
#' `proj_dir` and `repo_dir`. It loads required packages and exposes
#' rt_paths() which returns the canonical output tree for a given
#' resolution.

# Package check -----------------------------------------------------------

#' Stop early, with one install line, if any required package is missing.
#'
#' Runs before the library() calls below so a missing package fails in the
#' first second of a run rather than partway through it.
#'
#' @param pkgs Character vector of package names.
#' @return Invisibly TRUE if all are installed.
rt_check_packages <- function(pkgs) {
  missing <- pkgs[!vapply(pkgs, requireNamespace, logical(1), quietly = TRUE)]
  if (length(missing) > 0)
    stop("Missing R packages: ", paste(missing, collapse = ", "),
         "\nInstall with:\n  install.packages(c(",
         paste0('"', missing, '"', collapse = ", "), "))", call. = FALSE)
  invisible(TRUE)
}

# rnaturalearthdata is not attached, but rnaturalearth::ne_countries(scale =
# "medium") in fn.filter_hab_data() needs it installed.
rt_check_packages(c("sf", "raster", "terra", "rnaturalearth", "rnaturalearthdata",
                    "sdmTMB", "lubridate", "concaveman", "cluster",
                    "ggplot2", "viridis", "scales", "cowplot", "ggh4x",
                    "maps", "fields", "rvest", "httr", "jsonlite"))

# Library loading ---------------------------------------------------------
# Grouped by purpose. Kept in one place so individual function files
# don't load packages as a side effect of being sourced.

# Spatial
suppressPackageStartupMessages({
  library(sf)
  library(raster)
  library(terra)
  library(rnaturalearth)
})

# Modeling
suppressPackageStartupMessages({
  library(sdmTMB)
  library(lubridate)
})

# Polygon building
suppressPackageStartupMessages({
  library(concaveman)
  library(cluster)
})

# Plotting
suppressPackageStartupMessages({
  library(ggplot2)
  library(viridis)
  library(scales)
  library(cowplot)
  library(ggh4x)
  library(maps)
  library(fields)
})

# Web / API
suppressPackageStartupMessages({
  library(rvest)
  library(httr)
  library(jsonlite)
})

# Path helpers ------------------------------------------------------------

#' Build the canonical output tree for one resolution.
#'
#' @param res Integer resolution in minutes (e.g. 5, 15).
#' @param proj_dir Working dir where outputs and FWC cell counts live.
#' @param repo_dir Repo root (where scripts/ and template rasters/ live).
#' @param bathy_dir Directory holding the depth + excl ASCII templates.
#' @param ecospace_dir Optional target dir for the Ecospace ST-driver export.
#' @return A list of resolved paths. Directories are not created here;
#'   call rt_init_dirs() to create the output tree.
rt_paths <- function(res,
                     proj_dir,
                     repo_dir,
                     bathy_dir,
                     ecospace_dir = NULL) {
  stopifnot(is.numeric(res) || grepl("^[0-9]+$", res))
  res <- as.integer(res)
  out_root <- file.path(proj_dir, "out", paste0(res, "min"))

  # Depth + excl templates use a "depth <res>min <cols>x<rows>.asc" pattern.
  depth_glob <- list.files(bathy_dir,
                           pattern = paste0("^depth ", res, "min .*\\.asc$"),
                           full.names = TRUE)
  excl_glob  <- list.files(bathy_dir,
                           pattern = paste0("^excl layer ", res, "min .*\\.asc$"),
                           full.names = TRUE)
  if (length(depth_glob) == 0)
    stop("No depth template found in ", bathy_dir,
         " matching 'depth ", res, "min *.asc'")
  if (length(excl_glob) == 0)
    stop("No excl template found in ", bathy_dir,
         " matching 'excl layer ", res, "min *.asc'")

  list(
    res         = res,
    proj_dir    = proj_dir,
    repo_dir    = repo_dir,
    scripts_dir = file.path(repo_dir, "scripts"),

    # Inputs
    cellcnts    = file.path(proj_dir, "cell_counts"),
    viirs       = file.path(proj_dir, "VIIRS"),
    modis       = file.path(proj_dir, "MODIS"),
    file_depth  = depth_glob[1],
    file_excl   = excl_glob[1],

    # Outputs
    out_root    = out_root,
    sdm_out     = file.path(out_root, "sdm"),
    clipped_out = file.path(out_root, "clipped"),
    combined    = file.path(out_root, "combined"),
    ecospace    = file.path(out_root, "ecospace_ascii"),
    plots_out   = file.path(out_root, "plots"),
    log_file    = file.path(out_root,
                            paste0("run_", format(Sys.Date(), "%Y%m%d"), ".log")),

    # Optional external export target (None = repo-local only)
    ecospace_export = ecospace_dir
  )
}

#' Create the output tree if missing. Idempotent.
rt_init_dirs <- function(paths) {
  dirs <- c(paths$cellcnts,
            paths$out_root, paths$sdm_out,
            paths$clipped_out, paths$combined,
            paths$ecospace, paths$plots_out)
  for (d in dirs) {
    if (!dir.exists(d)) dir.create(d, recursive = TRUE)
  }
  invisible(paths)
}

#' Append a line to the run log. Quiet on failure.
rt_log <- function(paths, msg) {
  line <- paste0("[", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), "] ", msg)
  message(line)
  try(cat(line, "\n", file = paths$log_file, append = TRUE), silent = TRUE)
  invisible(NULL)
}
