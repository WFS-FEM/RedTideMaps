#' QA for issue #8, step 1: where are the samples VIIRS does not see?
#'
#' Classifies every filtered FWC sample of the VIIRS era (2012-01 to 2024-12)
#' by FWC abundance class and by the VIIRS cell it falls in that month
#' (masked = no data in the tif, valid with no detection, valid with a
#' detection), adds its distance to the coastline and to the nearest
#' VIIRS-evaluated cell, and relates the result to the 58 zeroed months and
#' the VIIRS-positive months of issue #6. Built from the stacks of the last
#' pipeline run and the #6 tables; nothing is refit or re-clipped.
#'
#' Needs a 5-min pipeline run (out/5min/sdm, clipped, combined),
#' VIIRS/VIIRS_*.grd and the issue-6 tables (docs/issue6_VIIRS-zeros/tables/).
#' The Natural Earth 1:10m coastline is downloaded once into docs/issue8_nearshore-hybrid/coastline/
#' (internet on the first run only).
#'
#' Run from the repo root:  Rscript docs/issue8_nearshore-hybrid/check_nearshore_issue8.R
#'
#' Output (docs/issue8_nearshore-hybrid/):
#'   tables/samples_viirs_status_issue8.csv    one row per sample (gitignored: 98,123 rows)
#'   tables/mask_cells_issue8.csv              the masked 0.1-degree cells that hold template water
#'   tables/mask_band_issue8.csv               share of template water cells masked, by region x coast band
#'   tables/t1_class_by_viirs_cell_issue8.csv  class x VIIRS cell status x template
#'   tables/t2_zeroed_months_by_class_issue8.csv   the 58 zeroed months, per class
#'   tables/t3_outside_footprint_by_class_issue8.csv  VIIRS-positive months: samples outside the footprint
#'   tables/t4_dist_coast_by_class_issue8.csv  distance to coast by class and status
#'   tables/t5_months_issue8.csv               one row per VIIRS month (155)
#'   figures/fig1_viirs_mask.png               the mask over the template, with the coastline
#'   figures/fig2_dist_coast_ecdf.png          distance to coast by class and status
#'   figures/fig3_headline_months.png          the 16 headline months: samples by status, VIIRS layer, hulls
#'   figures/fig4_monthly_status.png           2012-2024: low/medium/high samples by month, masked vs valid
#'   comments/nearshore_summary.md             the tables in markdown, for #8
#'   console: the summary and the stopifnot() results
#'
#' Deterministic: no RNG, no timestamps in any output.

# Repo root: the working directory if it holds the .Rproj, else two levels
# above this script (docs/issue8_nearshore-hybrid/).
.root <- local({
  if (file.exists("RedTideMaps.Rproj")) return(normalizePath(getwd(), winslash = "/"))
  f <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE))
  if (length(f) == 1) {
    d <- normalizePath(file.path(dirname(f), "..", ".."), winslash = "/", mustWork = FALSE)
    if (file.exists(file.path(d, "RedTideMaps.Rproj"))) return(d)
  }
  stop("Run from the repo root: Rscript docs/issue8_nearshore-hybrid/check_nearshore_issue8.R", call. = FALSE)
})
source(file.path(.root, "scripts", "_setup.R"))   # sf, raster, terra, rnaturalearth, viridis, ...

# Parameters ---------------------------------------------------------------
thr_bloom <- 1e4      # cells/L: FWC "low"; first coloured bin of the pipeline PDFs
thr_high  <- 1e5      # cells/L: FWC "medium"
viirs_era <- c(2012L, 2024L)
coast_bands  <- c(0, 2, 5, 10, 20, Inf)   # km from the coastline (Yao: 2 to 5 km)
coast_step_m <- 200                        # coastline densified to points this far apart for distances
# FWC abundance classes of the in-situ maps (myfwc.com/research/redtide/statewide/),
# right-closed bounds as in check_clipping_issue6.R class_counts().
class_brks <- c(-Inf, 0, 1e3, 1e4, 1e5, 1e6, Inf)
class_lv   <- c("negative", "background", "very_low", "low", "medium", "high")
class_lab  <- c("negative (0)", "background (<= 1,000)", "very low (1,000 - 10,000)",
                "low (10,000 - 100,000)", "medium (100,000 - 1,000,000)", "high (> 1,000,000)")
pos_lv     <- class_lv[-1]
status_lv  <- c("masked", "valid_zero", "valid_pos")
status_lab <- c(masked = "masked (no data)", valid_zero = "valid, no detection", valid_pos = "valid, detection")
# Coarse coastal regions for the band-width table (lon/lat boxes).
region_lv <- c("Panhandle", "Big Bend", "Tampa Bay to Charlotte Harbor", "Lee County to the Keys")
region_of <- function(lon, lat) factor(ifelse(lon < -84, region_lv[1], ifelse(lat >= 28.6, region_lv[2],
                                       ifelse(lat >= 26.5, region_lv[3], region_lv[4]))), levels = region_lv)
# Numbers from the 19 Oct 2026 check in the plan (section 2), asserted below.
expected <- list(viirs_layers = 155L, na_range = c(1002L, 1012L),
                 y201701 = c(na = 1004L, zero = 2571L, pos = 0L),
                 y201809 = c(na = 1002L, zero = 2213L, pos = 360L),
                 n_samples = 98123L, n_no_layer = 610L, n_off_grid = 55L, n_masked = 62416L,
                 n_high = 1627L, n_high_masked = 1076L,
                 n_zeroed = 58L, n_headline = 16L,
                 t3 = c(months = 60L, samples = 7841L, outside = 3186L))

# Paths --------------------------------------------------------------------
dir_out      <- file.path(.root, "out", "5min")
dir_sdm      <- file.path(dir_out, "sdm")
dir_clipped  <- file.path(dir_out, "clipped")
dir_combined <- file.path(dir_out, "combined")
dir_docs  <- file.path(.root, "docs", "issue8_nearshore-hybrid")
dir_fig   <- file.path(dir_docs, "figures")
dir_tab   <- file.path(dir_docs, "tables")
dir_cmt   <- file.path(dir_docs, "comments")
dir_coast <- file.path(dir_docs, "coastline")
for (d in c(dir_fig, dir_tab, dir_cmt)) dir.create(d, recursive = TRUE, showWarnings = FALSE)

one_file <- function(dir, pattern, what) {
  f <- list.files(dir, pattern = pattern, full.names = TRUE)
  if (length(f) != 1)
    stop("Expected one ", what, " in ", dir, " (found ", length(f), "); run the pipeline first.", call. = FALSE)
  f
}
grd <- function(f) sub("[.]grd$", "", f)
file_depth     <- one_file(file.path(.root, "template rasters"), "^depth 5min .*[.]asc$", "depth template")
file_hull      <- grd(one_file(dir_clipped,  "_clipped_hull[.]grd$",  "hull-clipped stack"))
file_viirs     <- grd(one_file(dir_clipped,  "_clipped_viirs[.]grd$", "VIIRS-clipped stack"))
file_modis     <- grd(one_file(dir_clipped,  "_clipped_modis[.]grd$", "MODIS-clipped stack"))
file_final     <- grd(one_file(dir_combined, "_clipped_combined[.]grd$", "combined stack"))
file_viirs_raw <- grd(one_file(file.path(.root, "VIIRS"), "^VIIRS_[0-9]{6}-[0-9]{6}[.]grd$", "VIIRS stack"))
file_tab6      <- file.path(.root, "docs", "issue6_VIIRS-zeros", "tables", "clip_comparison_issue6.csv")
file_cls6      <- file.path(.root, "docs", "issue6_VIIRS-zeros", "tables", "clip_class_counts_issue6.csv")
file_coast     <- file.path(dir_coast, "ne_10m_coastline_wfs.gpkg")
ff <- list.files(dir_sdm, pattern = "_filtered[.]Rdata$", full.names = TRUE)
if (length(ff) == 0) stop("No *_filtered.Rdata in ", dir_sdm, "; run the pipeline first.", call. = FALSE)
ff_end <- as.integer(substr(regmatches(basename(ff), regexpr("[0-9]{8}_filtered", basename(ff))), 1, 8))
file_filtered  <- ff[which.max(ff_end)]
file_hullpolys <- sub("_filtered[.]Rdata$", "_hullpolys.Rdata", file_filtered)
for (f in c(file_tab6, file_cls6, file_hullpolys))
  if (!file.exists(f)) stop("Missing ", f, "; run the pipeline and scripts/qa/check_clipping_issue6.R first.", call. = FALSE)
message("Samples: ", basename(file_filtered))

# Coastline (Natural Earth 1:10m, cropped to the grid box, cached in docs/issue8_nearshore-hybrid/coastline/) ------
if (!file.exists(file_coast)) {
  dir.create(dir_coast, recursive = TRUE, showWarnings = FALSE)
  message("Downloading the Natural Earth 1:10m coastline (first run only) ...")
  cl <- rnaturalearth::ne_download(scale = 10, type = "coastline", category = "physical",
                                   returnclass = "sf", destdir = tempdir(), load = TRUE)
  s2_was <- sf::sf_use_s2(); suppressMessages(sf::sf_use_s2(FALSE))
  bb <- sf::st_as_sfc(sf::st_bbox(c(xmin = -87.5, xmax = -81, ymin = 25, ymax = 30.5), crs = sf::st_crs(4326)))
  cr <- suppressWarnings(sf::st_intersection(sf::st_geometry(cl), bb))
  suppressMessages(sf::sf_use_s2(s2_was))
  cr <- cr[sf::st_geometry_type(cr) %in% c("LINESTRING", "MULTILINESTRING")]
  cr <- sf::st_sf(geometry = sf::st_cast(cr, "MULTILINESTRING"))
  sf::st_write(cr, file_coast, delete_dsn = TRUE, quiet = TRUE)
  writeLines(c("# Coastline for the issue-8 distance-to-coast diagnostic",
               "",
               paste0("`ne_10m_coastline_wfs.gpkg`: Natural Earth 1:10m physical coastline (public domain, ",
                      "https://www.naturalearthdata.com/downloads/10m-physical-vectors/), downloaded with ",
                      "`rnaturalearth::ne_download(scale = 10, type = \"coastline\", category = \"physical\")` on ",
                      format(Sys.Date(), "%d %B %Y"), " and cropped to the WFS grid box (-87.5 to -81 E, 25 to 30.5 N) by ",
                      "`docs/issue8_nearshore-hybrid/check_nearshore_issue8.R`, which recreates it when it is missing."),
               "",
               "At 1:10m the coastline resolves the large bays (Tampa Bay, Charlotte Harbor, Apalachicola Bay) ",
               "but not every small inlet, so a distance to coast from it is good to about 1 to 2 km."),
             file.path(dir_coast, "README.md"))
  message("Coastline written: ", file_coast)
}
coast     <- sf::st_read(file_coast, quiet = TRUE)
coast_utm <- sf::st_transform(sf::st_geometry(coast), 32617)   # UTM 17N, metres (as the hulls)
seg       <- sf::st_segmentize(coast_utm, coast_step_m)
coast_pts <- sf::st_cast(sf::st_sfc(sf::st_multipoint(sf::st_coordinates(seg)[, 1:2]), crs = 32617), "POINT")
message("Coastline: ", round(sum(as.numeric(sf::st_length(coast_utm))) / 1000), " km in the grid box, ",
        length(coast_pts), " points at ", coast_step_m, " m")
# Nearest-point distance (km) from lon/lat coordinates to a set of UTM points.
dist_to_km <- function(lon, lat, target) {
  p  <- sf::st_transform(sf::st_as_sf(data.frame(lon = lon, lat = lat), coords = c("lon", "lat"), crs = 4326), 32617)
  nn <- sf::st_nearest_feature(p, target)
  as.numeric(sf::st_distance(sf::st_geometry(p), target[nn], by_element = TRUE)) / 1000
}

# Load rasters -------------------------------------------------------------
depth    <- raster::raster(file_depth)
dv       <- raster::values(depth)
land     <- is.na(dv)
cell_km2 <- raster::values(raster::area(depth))
nr <- nrow(depth); nc <- ncol(depth); n5 <- raster::ncell(depth)
read_mat <- function(f) {
  b <- raster::brick(f)
  stopifnot(raster::compareRaster(depth, b))
  m <- raster::values(b); colnames(m) <- sub("^X", "", names(b)); m
}
H  <- read_mat(file_hull)     # hull-clipped, cells/L
Vc <- read_mat(file_viirs)    # VIIRS-clipped
Mc <- read_mat(file_modis)    # MODIS-clipped
Fm <- read_mat(file_final)    # final (combined)
Vraw <- raster::brick(file_viirs_raw)
stopifnot(isTRUE(all.equal(as.vector(raster::extent(Vraw)), as.vector(raster::extent(depth)))))
Vr <- raster::values(Vraw); colnames(Vr) <- sub("^X", "", names(Vraw))
nr1 <- nrow(Vraw); nc1 <- ncol(Vraw); n1 <- raster::ncell(Vraw)
tab6 <- read.csv(file_tab6, colClasses = c(yrmo = "character"), stringsAsFactors = FALSE)
cls6 <- read.csv(file_cls6, colClasses = c(yrmo = "character"), stringsAsFactors = FALSE)
load(file_hullpolys)     # pol_list

# The VIIRS mask ---------------------------------------------------------------
na_mat          <- is.na(Vr)
na_per_month    <- colSums(na_mat)
n_months_masked <- rowSums(na_mat)
# The static mask: no data in at least 90% of the months (every month for all but a
# few cells). Cells with no data in only a few months are a transient gap, not the mask.
mask_static    <- n_months_masked >= 0.9 * ncol(Vr)
mask_transient <- n_months_masked > 0 & !mask_static
mask_any       <- n_months_masked > 0
valid_always   <- !mask_any
# Each 5-min cell belongs to one 0.1-degree VIIRS cell (by its centre).
xy5       <- raster::xyFromCell(depth, seq_len(n5))
cell01_of5 <- raster::cellFromXY(Vraw, xy5)
stopifnot(!any(is.na(cell01_of5)))
# Gulf domain: template water outside the Atlantic-side box that fn.filter_hab_data()
# drops samples from (-82 to -80.5 E, 28.5 to 31 N). The VIIRS product does not cover
# that corner, so its water cells are no-data for a different reason than the coast.
atl5   <- xy5[, 1] > -82 & xy5[, 2] > 28.5
domain <- !land & !atl5
agg01 <- function(x, fun) { a <- tapply(x, cell01_of5, fun); out <- rep(NA_real_, n1); out[as.integer(names(a))] <- a; out }
water_frac01 <- agg01(domain, mean)
n_water5_01  <- agg01(domain, sum)
depth01      <- agg01(ifelse(domain, dv, NA), function(x) if (all(is.na(x))) NA_real_ else mean(x, na.rm = TRUE))
masked5_static <- mask_static[cell01_of5]
masked5_any    <- mask_any[cell01_of5]
xy1 <- raster::xyFromCell(Vraw, seq_len(n1))
# Distance to coast of every 5-min water cell centre and of every 0.1-degree cell centre.
dist5 <- rep(NA_real_, n5); dist5[!land] <- dist_to_km(xy5[!land, 1], xy5[!land, 2], coast_pts)
dist1 <- dist_to_km(xy1[, 1], xy1[, 2], coast_pts)
region5 <- region_of(xy5[, 1], xy5[, 2])
# Nearest always-valid VIIRS cell centre (for "how far is the sample from where VIIRS looks").
valid_pts <- sf::st_transform(sf::st_as_sf(data.frame(xy1[valid_always, , drop = FALSE]), coords = c("x", "y"), crs = 4326), 32617)
valid_pts <- sf::st_geometry(valid_pts)

mask_cells <- data.frame(cell01 = which(mask_any & n_water5_01 > 0))
mask_cells$lon <- round(xy1[mask_cells$cell01, 1], 3); mask_cells$lat <- round(xy1[mask_cells$cell01, 2], 3)
mask_cells$n_months_masked <- n_months_masked[mask_cells$cell01]
mask_cells$mask <- ifelse(mask_static[mask_cells$cell01], "static", "transient")
mask_cells$n_water_cells_5min <- n_water5_01[mask_cells$cell01]
mask_cells$water_frac <- round(water_frac01[mask_cells$cell01], 2)
mask_cells$mean_depth_m <- round(depth01[mask_cells$cell01], 1)
mask_cells$dist_coast_km <- round(dist1[mask_cells$cell01], 1)
mask_cells$region <- region_of(mask_cells$lon, mask_cells$lat)
write.csv(mask_cells, file.path(dir_tab, "mask_cells_issue8.csv"), row.names = FALSE)
mc_static <- mask_cells[mask_cells$mask == "static", ]
mc_trans  <- mask_cells[mask_cells$mask == "transient", ]

band_of <- function(d) cut(d, coast_bands, right = FALSE, include.lowest = TRUE,
                           labels = c("0-2 km", "2-5 km", "5-10 km", "10-20 km", "> 20 km"))
w <- domain
band_tab <- aggregate(cbind(n_cells = 1, n_masked_always = masked5_static[w], n_masked_any = masked5_any[w],
                            km2 = cell_km2[w], km2_masked_always = cell_km2[w] * masked5_static[w]),
                      by = list(region = region5[w], band = band_of(dist5[w])), FUN = sum)
band_tab$share_masked_always <- round(band_tab$n_masked_always / band_tab$n_cells, 2)
band_tab <- band_tab[order(band_tab$region, band_tab$band), ]
band_all <- aggregate(cbind(n_cells = 1, n_masked_always = masked5_static[w], n_masked_any = masked5_any[w],
                            km2 = cell_km2[w], km2_masked_always = cell_km2[w] * masked5_static[w]),
                      by = list(band = band_of(dist5[w])), FUN = sum)
band_all$region <- "all regions"; band_all$share_masked_always <- round(band_all$n_masked_always / band_all$n_cells, 2)
band_tab <- rbind(band_tab, band_all[names(band_tab)])
write.csv(band_tab, file.path(dir_tab, "mask_band_issue8.csv"), row.names = FALSE)

# Samples ------------------------------------------------------------------------
load(file_filtered)      # filtered_points_df (sf)
pts <- sf::st_drop_geometry(filtered_points_df)
pts$cells <- suppressWarnings(as.numeric(pts$cells))
n_cells_na <- sum(is.na(pts$cells)); pts <- pts[!is.na(pts$cells), ]
pts <- pts[pts$year >= viirs_era[1] & pts$year <= viirs_era[2], ]
pts$yrmo  <- sprintf("%d%02d", as.integer(pts$year), as.integer(pts$month))
pts$cell5 <- raster::cellFromXY(depth, cbind(pts$lon, pts$lat))
# A few samples sit just outside the grid box (on its northern edge, lat >= 30.5,
# kept by the spatial filter's crop): no template cell, no VIIRS cell. They stay
# in the per-sample table as "off_grid" and are left out of the class tables.
off <- is.na(pts$cell5)
pts$template <- ifelse(off, "off_grid", ifelse(land[ifelse(off, 1L, pts$cell5)], "land", "water"))
pts$depth_m  <- ifelse(off, NA_real_, round(dv[ifelse(off, 1L, pts$cell5)], 1))
pts$cell01   <- raster::cellFromXY(Vraw, cbind(pts$lon, pts$lat))
li <- match(pts$yrmo, colnames(Vr)); ok <- !is.na(li) & !off
pts$viirs_freq <- NA_real_; pts$viirs_freq[ok] <- Vr[cbind(pts$cell01[ok], li[ok])]
pts$viirs_cell <- ifelse(off, "off_grid", ifelse(is.na(li), "no_layer",
                  ifelse(is.na(pts$viirs_freq), "masked", ifelse(pts$viirs_freq > 0, "valid_pos", "valid_zero"))))
pts$class <- cut(pts$cells, class_brks, labels = class_lv, right = TRUE)
val_at <- function(M) { j <- match(pts$yrmo, colnames(M)); out <- rep(NA_real_, nrow(pts)); k <- !is.na(j)
                        out[k] <- M[cbind(pts$cell5[k], j[k])]; out }
pts$in_final_fp <- val_at(Fm) > 0     # NA on template land (the maps are NA there)
pts$in_viirs_fp <- val_at(Vc) > 0
pts$in_modis_fp <- val_at(Mc) > 0
pts$in_hull_fp  <- val_at(H)  > 0
# Distances on the distinct locations only.
uc <- unique(pts[, c("lon", "lat")])
uc$dist_coast_km <- round(dist_to_km(uc$lon, uc$lat, coast_pts), 2)
uc$dist_valid_km <- round(dist_to_km(uc$lon, uc$lat, valid_pts), 2)
m <- match(paste(pts$lon, pts$lat), paste(uc$lon, uc$lat))
pts$dist_coast_km <- uc$dist_coast_km[m]; pts$dist_valid_km <- uc$dist_valid_km[m]
pts$region <- region_of(pts$lon, pts$lat)
m6 <- match(pts$yrmo, tab6$yrmo)
pts$use <- tab6$use[m6]; pts$viirs_status <- tab6$viirs_status[m6]; pts$fit_status <- tab6$fit_status[m6]
pts$zeroed_fit <- tab6$flag_zeroed_fit[m6]; pts$zeroed_material <- tab6$zeroed_material[m6]
pts$masked5_static <- ifelse(off, NA, masked5_static[ifelse(off, 1L, pts$cell5)])
out_cols <- c("yrmo", "lon", "lat", "cells", "class", "template", "depth_m", "region", "viirs_cell", "viirs_freq",
              "in_final_fp", "in_viirs_fp", "in_modis_fp", "in_hull_fp", "dist_coast_km", "dist_valid_km",
              "use", "viirs_status", "fit_status", "zeroed_fit", "zeroed_material")
write.csv(pts[order(pts$yrmo, pts$lat, pts$lon), out_cols],
          file.path(dir_tab, "samples_viirs_status_issue8.csv"), row.names = FALSE)
message("Samples ", viirs_era[1], "-", viirs_era[2], ": ", nrow(pts), " (", n_cells_na, " with no count dropped; ",
        sum(off), " off the grid box, all negative: ", all(pts$cells[off] == 0), "); distinct locations: ", nrow(uc))

# Checks (before any table or figure) -------------------------------------------------
stopifnot(ncol(Vr) == expected$viirs_layers,
          min(na_per_month) == expected$na_range[1], max(na_per_month) == expected$na_range[2])
chk_month <- function(ym) c(na = sum(is.na(Vr[, ym])), zero = sum(Vr[, ym] == 0, na.rm = TRUE), pos = sum(Vr[, ym] > 0, na.rm = TRUE))
stopifnot(identical(chk_month("201701"), expected$y201701), identical(chk_month("201809"), expected$y201809))
stopifnot(nrow(pts) == expected$n_samples,
          sum(pts$yrmo == "202212") == expected$n_no_layer,                 # the one month without a tif
          all(pts$viirs_cell[pts$yrmo == "202212"] %in% c("no_layer", "off_grid")),
          identical(sort(unique(pts$yrmo[pts$viirs_cell == "no_layer"])), "202212"),
          sum(pts$viirs_cell == "off_grid") == expected$n_off_grid,
          all(pts$cells[pts$viirs_cell == "off_grid"] == 0), all(pts$lat[pts$viirs_cell == "off_grid"] >= 30.5),
          sum(pts$viirs_cell == "masked") == expected$n_masked,
          sum(pts$class == "high" & pts$viirs_cell != "no_layer") == expected$n_high,
          sum(pts$class == "high" & pts$viirs_cell == "masked") == expected$n_high_masked)
stopifnot(!any(is.na(pts$class)), all(table(pts$class[pts$cells > 0])[pos_lv] >= 0),
          sum(pts$cells > 0) == sum(pts$class %in% pos_lv))               # the five classes partition the positives
stopifnot(all(pts$viirs_cell %in% c(status_lv, "no_layer", "off_grid")))  # the status partitions every sample
# Per-month positives and class counts agree with the #6 tables.
cc <- table(pts$yrmo, pts$class)[, pos_lv]
c6 <- cls6[match(rownames(cc), cls6$yrmo), c("fwc_n_le1e3", "fwc_n_1e3_1e4", "fwc_n_1e4_1e5", "fwc_n_1e5_1e6", "fwc_n_gt1e6")]
stopifnot(all(as.matrix(c6) == unclass(cc)))
stopifnot(all(tab6$n_pos[match(rownames(cc), tab6$yrmo)] == rowSums(cc)))
# Matrix -> image() orientation (as in #6): z[col, nr - row + 1] equals the cell value.
to_z  <- function(v) matrix(v, nrow = nc)[, nr:1]
to_z1 <- function(v) matrix(v, nrow = nc1)[, nr1:1]
stopifnot(to_z(dv)[3, nr - 5 + 1] == dv[raster::cellFromRowCol(depth, 5, 3)] || (is.na(to_z(dv)[3, nr - 5 + 1]) && is.na(dv[raster::cellFromRowCol(depth, 5, 3)])))
# Zeroed and headline months as in #6.
zeroed   <- tab6$yrmo[tab6$flag_zeroed_fit %in% TRUE]
headline <- tab6$yrmo[tab6$zeroed_material %in% TRUE]
stopifnot(length(zeroed) == expected$n_zeroed, length(headline) == expected$n_headline, all(headline %in% zeroed))
message("Checks passed.")

# T1: class x VIIRS cell status x template -----------------------------------------
pv <- pts[pts$viirs_cell %in% status_lv, ]     # drops 2022-12 (no layer) and the off-grid negatives
pv$viirs_cell <- factor(pv$viirs_cell, levels = status_lv)
t1_all   <- table(class = pv$class, status = pv$viirs_cell)
t1_water <- table(class = pv$class[pv$template == "water"], status = pv$viirs_cell[pv$template == "water"])
t1_land  <- table(class = pv$class[pv$template == "land"],  status = pv$viirs_cell[pv$template == "land"])
t1 <- data.frame(class = class_lv, class_label = class_lab,
                 masked = t1_all[, "masked"], valid_zero = t1_all[, "valid_zero"], valid_pos = t1_all[, "valid_pos"])
t1$total <- rowSums(t1[, status_lv])
t1$masked_share <- round(t1$masked / t1$total, 3)
t1$detected_share_of_valid <- round(t1$valid_pos / (t1$valid_pos + t1$valid_zero), 3)
t1$masked_water <- t1_water[, "masked"]; t1$masked_land <- t1_land[, "masked"]
t1$valid_zero_water <- t1_water[, "valid_zero"]; t1$valid_pos_water <- t1_water[, "valid_pos"]
tot <- data.frame(class = "all", class_label = "all samples", masked = sum(t1$masked), valid_zero = sum(t1$valid_zero),
                  valid_pos = sum(t1$valid_pos), total = sum(t1$total))
tot$masked_share <- round(tot$masked / tot$total, 3); tot$detected_share_of_valid <- round(tot$valid_pos / (tot$valid_pos + tot$valid_zero), 3)
tot$masked_water <- sum(t1$masked_water); tot$masked_land <- sum(t1$masked_land)
tot$valid_zero_water <- sum(t1$valid_zero_water); tot$valid_pos_water <- sum(t1$valid_pos_water)
t1 <- rbind(t1, tot); rownames(t1) <- NULL
write.csv(t1, file.path(dir_tab, "t1_class_by_viirs_cell_issue8.csv"), row.names = FALSE)

# T2: the 58 zeroed months, per class --------------------------------------------------
count_by <- function(p) {
  # one row per class: n, masked, valid_zero, valid_pos, land, masked_water
  do.call(rbind, lapply(pos_lv, function(k) {
    q <- p[p$class == k, ]
    data.frame(class = k, n = nrow(q), masked = sum(q$viirs_cell == "masked"), valid_zero = sum(q$viirs_cell == "valid_zero"),
               valid_pos = sum(q$viirs_cell == "valid_pos"), land = sum(q$template == "land"),
               masked_water = sum(q$viirs_cell == "masked" & q$template == "water"),
               in_hull_fp = sum(q$in_hull_fp %in% TRUE), stringsAsFactors = FALSE)
  }))
}
t2 <- do.call(rbind, lapply(zeroed, function(ym) {
  r <- count_by(pts[pts$yrmo == ym, ])
  cbind(yrmo = ym, headline = ym %in% headline, r, stringsAsFactors = FALSE)
}))
write.csv(t2, file.path(dir_tab, "t2_zeroed_months_by_class_issue8.csv"), row.names = FALSE)
t2_tot <- function(months, label) {
  r <- count_by(pts[pts$yrmo %in% months, ])
  r$masked_share <- round(r$masked / pmax(r$n, 1), 2); r$valid_zero_share <- round(r$valid_zero / pmax(r$n, 1), 2)
  r$land_share <- round(r$land / pmax(r$n, 1), 2); cbind(months = label, r, stringsAsFactors = FALSE)
}
t2_sum <- rbind(t2_tot(zeroed, sprintf("the %d zeroed months", length(zeroed))),
                t2_tot(headline, sprintf("the %d headline months", length(headline))))
# Headline months, low + medium + high together.
t2_hl <- do.call(rbind, lapply(headline, function(ym) {
  q <- pts[pts$yrmo == ym & pts$class %in% c("low", "medium", "high"), ]
  data.frame(yrmo = ym, n_pos = sum(pts$yrmo == ym & pts$cells > 0), n_ge_1e4 = nrow(q),
             masked = sum(q$viirs_cell == "masked"), valid_zero = sum(q$viirs_cell == "valid_zero"),
             valid_pos = sum(q$viirs_cell == "valid_pos"), land = sum(q$template == "land"),
             masked_share = round(mean(q$viirs_cell == "masked"), 2),
             median_dist_coast_km = round(median(q$dist_coast_km), 1),
             hull_km2_in_mask = NA_real_, stringsAsFactors = FALSE)
}))

# T3: VIIRS-positive fitted months, samples >= thr_bloom on water outside the final footprint ------
sel3 <- tab6$yrmo[tab6$use == "viirs" & tab6$viirs_status == "positive" & tab6$fit_status == "fitted" & tab6$n_pos_1e4_water >= 5]
p3 <- pts[pts$yrmo %in% sel3 & pts$template == "water" & pts$cells >= thr_bloom, ]
p3$outside <- !(p3$in_final_fp %in% TRUE)
t3_n <- c(months = length(sel3), samples = nrow(p3), outside = sum(p3$outside))
if (!identical(unname(t3_n), unname(expected$t3)))
  warning("T3 selection differs from #6 (months/samples/outside): ", paste(t3_n, collapse = "/"),
          " vs ", paste(expected$t3, collapse = "/"), call. = FALSE)
t3 <- do.call(rbind, lapply(c("low", "medium", "high"), function(k) {
  q <- p3[p3$class == k, ]; o <- q[q$outside, ]
  data.frame(class = k, n_water_samples = nrow(q), outside_fp = nrow(o), outside_share = round(nrow(o) / max(nrow(q), 1), 2),
             outside_masked = sum(o$viirs_cell == "masked"), outside_valid_zero = sum(o$viirs_cell == "valid_zero"),
             outside_valid_pos = sum(o$viirs_cell == "valid_pos"),
             inside_masked = sum(!q$outside & q$viirs_cell == "masked"), inside_valid_zero = sum(!q$outside & q$viirs_cell == "valid_zero"),
             inside_valid_pos = sum(!q$outside & q$viirs_cell == "valid_pos"), stringsAsFactors = FALSE)
}))
t3_all <- data.frame(class = "all >= 10,000", n_water_samples = nrow(p3), outside_fp = sum(p3$outside),
                     outside_share = round(mean(p3$outside), 2),
                     outside_masked = sum(p3$outside & p3$viirs_cell == "masked"), outside_valid_zero = sum(p3$outside & p3$viirs_cell == "valid_zero"),
                     outside_valid_pos = sum(p3$outside & p3$viirs_cell == "valid_pos"),
                     inside_masked = sum(!p3$outside & p3$viirs_cell == "masked"), inside_valid_zero = sum(!p3$outside & p3$viirs_cell == "valid_zero"),
                     inside_valid_pos = sum(!p3$outside & p3$viirs_cell == "valid_pos"), stringsAsFactors = FALSE)
t3 <- rbind(t3, t3_all)
write.csv(t3, file.path(dir_tab, "t3_outside_footprint_by_class_issue8.csv"), row.names = FALSE)

# T4: distance to coast by class and status ---------------------------------------------
qs <- c(0.1, 0.25, 0.5, 0.75, 0.9)
t4 <- do.call(rbind, lapply(class_lv, function(k) do.call(rbind, lapply(status_lv, function(s) {
  d <- pv$dist_coast_km[pv$class == k & pv$viirs_cell == s]
  if (length(d) == 0) return(NULL)
  q <- quantile(d, qs)
  data.frame(class = k, status = s, n = length(d), q10 = q[1], q25 = q[2], median = q[3], q75 = q[4], q90 = q[5],
             within_2km = round(mean(d <= 2), 2), within_5km = round(mean(d <= 5), 2), within_10km = round(mean(d <= 10), 2),
             stringsAsFactors = FALSE)
}))))
rownames(t4) <- NULL
# Share of each class within each band, and the masked share within the band.
t4b <- do.call(rbind, lapply(pos_lv, function(k) {
  q <- pv[pv$class == k, ]
  do.call(rbind, lapply(c(2, 5, 10), function(km) {
    inb <- q$dist_coast_km <= km
    data.frame(class = k, band_km = km, n = nrow(q), n_within = sum(inb), share_within = round(mean(inb), 2),
               masked_share_within = round(mean(q$viirs_cell[inb] == "masked"), 2),
               masked_share_beyond = round(mean(q$viirs_cell[!inb] == "masked"), 2), stringsAsFactors = FALSE)
  }))
}))
write.csv(t4, file.path(dir_tab, "t4_dist_coast_by_class_issue8.csv"), row.names = FALSE)
write.csv(t4b, file.path(dir_tab, "t4b_coast_bands_by_class_issue8.csv"), row.names = FALSE)

# T5: one row per VIIRS month ---------------------------------------------------------
months <- colnames(Vr)
t5 <- do.call(rbind, lapply(months, function(ym) {
  q <- pts[pts$yrmo == ym, ]
  r <- tab6[tab6$yrmo == ym, ]
  cnt <- as.vector(t(table(factor(q$class, levels = pos_lv), factor(q$viirs_cell, levels = status_lv))))
  names(cnt) <- paste0("n_", rep(pos_lv, each = 3), "_", rep(status_lv, times = 3))
  lnd <- as.vector(table(factor(q$class[q$template == "land"], levels = pos_lv))); names(lnd) <- paste0("n_", pos_lv, "_land")
  h <- H[, ym]; wm <- domain & masked5_static
  data.frame(yrmo = ym, use = r$use, viirs_status = r$viirs_status, fit_status = r$fit_status,
             zeroed_fit = r$flag_zeroed_fit %in% TRUE, headline = r$zeroed_material %in% TRUE,
             n_samples = nrow(q), n_pos = sum(q$cells > 0), n_ge_1e4 = sum(q$cells >= thr_bloom), n_ge_1e5 = sum(q$cells >= thr_high),
             n_ge_1e4_masked = sum(q$cells >= thr_bloom & q$viirs_cell == "masked"),
             n_ge_1e4_valid_zero = sum(q$cells >= thr_bloom & q$viirs_cell == "valid_zero"),
             n_ge_1e4_valid_pos = sum(q$cells >= thr_bloom & q$viirs_cell == "valid_pos"),
             as.list(cnt), as.list(lnd),
             viirs_n_pos_cells = r$viirs_n_pos_cells, area_1e4_final_km2 = r$area_1e4_final_km2, area_1e4_hull_km2 = r$area_1e4_hull_km2,
             hull_footprint_km2 = r$hull_footprint_km2,
             hull_fp_km2_in_mask = round(sum(cell_km2[wm & !is.na(h) & h > 0])),
             hull_1e4_km2_in_mask = round(sum(cell_km2[wm & !is.na(h) & h >= thr_bloom])),
             hull_1e5_km2_in_mask = round(sum(cell_km2[wm & !is.na(h) & h >= thr_high])),
             stringsAsFactors = FALSE)
}))
write.csv(t5, file.path(dir_tab, "t5_months_issue8.csv"), row.names = FALSE)
t2_hl$hull_km2_in_mask <- t5$hull_1e4_km2_in_mask[match(t2_hl$yrmo, t5$yrmo)]

# Summary (console + markdown) --------------------------------------------------------
md_table <- function(df, digits = 2) {
  fmt <- function(x) if (is.numeric(x)) ifelse(is.na(x), "", format(round(x, digits), big.mark = ",", trim = TRUE, scientific = FALSE)) else ifelse(is.na(x), "", as.character(x))
  body <- apply(as.data.frame(lapply(df, fmt), stringsAsFactors = FALSE), 1, paste, collapse = " | ")
  c(paste("|", paste(names(df), collapse = " | "), "|"), paste("|", paste(rep("---", ncol(df)), collapse = " | "), "|"), paste("|", body, "|"))
}
pct <- function(x) ifelse(is.na(x), NA, round(100 * x))
hdr <- c(
  "# Issue #8, step 1: where are the samples VIIRS does not see?",
  "",
  sprintf("Produced by `docs/issue8_nearshore-hybrid/check_nearshore_issue8.R` from the 6 October 2026 run (samples `%s`). Every sample of %d-%d is classified by FWC abundance class and by the VIIRS cell it falls in that month: masked (no data in the tif), valid with no detection (0), or valid with a detection (> 0). The %d samples of 2022-12 (no VIIRS tif) and %d negative samples just outside the grid box (lat >= 30.5) are left out of the tables below.",
          basename(file_filtered), viirs_era[1], viirs_era[2], sum(pts$viirs_cell == "no_layer"), sum(pts$viirs_cell == "off_grid")),
  "",
  "## The mask",
  "",
  sprintf("- %d to %d no-data cells per layer over %d layers. The static mask (no data in at least 90%% of the months) has %d cells: %d in every month and %d in %s months. %d further cells are no-data in a few months only (%s): a transient gap, not part of the mask.",
          min(na_per_month), max(na_per_month), ncol(Vr), sum(mask_static), sum(n_months_masked == ncol(Vr)),
          sum(mask_static & n_months_masked < ncol(Vr)), paste(range(n_months_masked[mask_static & n_months_masked < ncol(Vr)]), collapse = " to "),
          sum(mask_transient), paste0(sum(mask_transient & n_months_masked == 1), " of them in a single month, ",
                                      sum(n_water5_01[mask_transient] > 0 & depth01[mask_transient] > 100, na.rm = TRUE), " of those over water deeper than 100 m in the south-west corner")),
  sprintf("- %d static-mask cells hold Gulf-domain template water (%d 5-arcmin water cells, %s km2, %d%% of the %s km2 of Gulf-domain water); their mean template depth has a median of %.1f m (90th percentile %.1f m, max %.1f m) and their centres a median distance to the coast of %.1f km (90th percentile %.1f km).",
          nrow(mc_static), sum(masked5_static & domain), format(round(sum(cell_km2[masked5_static & domain])), big.mark = ","),
          round(100 * sum(cell_km2[masked5_static & domain]) / sum(cell_km2[domain])), format(round(sum(cell_km2[domain])), big.mark = ","),
          median(mc_static$mean_depth_m, na.rm = TRUE), quantile(mc_static$mean_depth_m, 0.9, na.rm = TRUE), max(mc_static$mean_depth_m, na.rm = TRUE),
          median(mc_static$dist_coast_km), quantile(mc_static$dist_coast_km, 0.9)),
  "- The Atlantic-side corner of the template (east of -82 E, north of 28.5 N, where the pipeline drops samples) is no-data in every VIIRS month because the product covers the Gulf only; it is left out of every mask statistic.",
  "",
  "### Share of template water cells masked, by region and distance to the coast (`tables/mask_band_issue8.csv`)",
  "",
  md_table(band_tab[, c("region", "band", "n_cells", "n_masked_always", "share_masked_always", "km2", "km2_masked_always")]),
  "",
  "## T1: samples by FWC class and VIIRS cell status (`tables/t1_class_by_viirs_cell_issue8.csv`)",
  "",
  md_table(t1[, c("class_label", "masked", "valid_zero", "valid_pos", "total", "masked_share", "detected_share_of_valid", "masked_water", "masked_land")], 3),
  "",
  sprintf("## T2: the %d zeroed months, by class (`tables/t2_zeroed_months_by_class_issue8.csv`)", length(zeroed)),
  "",
  md_table(t2_sum[, c("months", "class", "n", "masked", "valid_zero", "valid_pos", "land", "masked_water", "masked_share", "valid_zero_share", "land_share")]),
  "",
  sprintf("Headline months (%d), samples at or above %s cells/L: `hull_km2_in_mask` is the bloom area (>= %s cells/L) of the hull-clipped map that lies in the masked band, i.e. what a mask rule would restore in that month.",
          length(headline), format(thr_bloom, big.mark = ","), format(thr_bloom, big.mark = ",")),
  "",
  md_table(t2_hl),
  "",
  sprintf("## T3: the %d VIIRS-positive fitted months of #6: water samples >= %s cells/L outside the final footprint (`tables/t3_outside_footprint_by_class_issue8.csv`)",
          length(sel3), format(thr_bloom, big.mark = ",")),
  "",
  sprintf("Selection as in #6 (use = viirs, layer positive, fitted, at least 5 such samples): %d months, %d samples, %d outside the footprint (#6: %d / %d / %d).",
          t3_n[1], t3_n[2], t3_n[3], expected$t3[1], expected$t3[2], expected$t3[3]),
  "",
  md_table(t3),
  "",
  "## T4: distance to the coast (km) by class and status (`tables/t4_dist_coast_by_class_issue8.csv`)",
  "",
  md_table(t4[t4$class != "negative", ], 1),
  "",
  "Share of each class within 2, 5 and 10 km of the coast, and the masked share inside and beyond that band (`tables/t4b_coast_bands_by_class_issue8.csv`):",
  "",
  md_table(t4b),
  "",
  "## T5: per month (`tables/t5_months_issue8.csv`), headline rows",
  "",
  md_table(t5[t5$headline, c("yrmo", "n_pos", "n_ge_1e4", "n_ge_1e4_masked", "n_ge_1e4_valid_zero", "n_ge_1e4_valid_pos",
                             "hull_footprint_km2", "hull_fp_km2_in_mask", "area_1e4_hull_km2", "hull_1e4_km2_in_mask")]),
  ""
)
writeLines(hdr, file.path(dir_cmt, "nearshore_summary.md"))
cat(hdr, sep = "\n")

# Figures ---------------------------------------------------------------------------
xs <- raster::xFromCol(depth, 1:nc); ys <- rev(raster::yFromRow(depth, 1:nr))
xs1 <- raster::xFromCol(Vraw, 1:nc1); ys1 <- rev(raster::yFromRow(Vraw, 1:nr1))
xlim <- c(-87.5, -81); ylim <- c(25, 30.5)
asp <- 1 / cos(27.5 * pi / 180)
spal <- viridis::viridis(5, direction = -1)                      # class fill, as the #6 sample panels
scol <- c(masked = "red", valid_zero = "black", valid_pos = "deepskyblue3")   # point border by status
colv   <- c("white","purple","blue","darkblue","cyan","green","darkgreen","yellow","orange","red","darkred")
funpal <- colorRampPalette(colv, bias = 2)
brks   <- c(0, 1e4 - 1, seq(1e4, 4e6, 10000), Inf); brks_img <- brks; brks_img[length(brks_img)] <- 1e12
color  <- c(funpal(length(brks) - 2), "darkred")
land_z <- to_z(ifelse(land, 1, NA))
mask_cat <- ifelse(land, NA, ifelse(atl5, 3, ifelse(masked5_static, 2, ifelse(masked5_any, 1, 0))))
mask_col <- c("white", "gold", "orangered", "gray55")

base_panel <- function(main, xl = xlim, yl = ylim, cex_main = 0.85, axes = FALSE) {
  plot(NA, xlim = xl, ylim = yl, xlab = "", ylab = "", asp = asp, main = main, cex.main = cex_main,
       xaxs = "i", yaxs = "i", axes = axes)
}
draw_land <- function() { image(xs, ys, land_z, col = "gray82", add = TRUE, useRaster = TRUE)
                          plot(sf::st_geometry(coast), add = TRUE, col = "gray30", lwd = 0.5) }
info_box <- function(lines, cex = 0.55) legend("left", legend = lines, bty = "o", bg = "white", box.col = "gray60",
                                              cex = cex, inset = 0.01, x.intersp = 0.3, y.intersp = 0.9)
fmt_n <- function(x) format(x, big.mark = ",")

# Fig 1: the mask over the template water cells, full shelf and a zoom.
png(file.path(dir_fig, "fig1_viirs_mask.png"), width = 12, height = 6.2, units = "in", res = 150)
par(mfrow = c(1, 2), mar = c(2.5, 2.8, 2.6, 0.6), oma = c(0, 0, 0, 0))
for (zoom in c(FALSE, TRUE)) {
  xl <- if (zoom) c(-83.6, -81.4) else xlim; yl <- if (zoom) c(26.0, 28.6) else ylim
  base_panel(if (zoom) "Zoom: Tampa Bay to Lee County, with the 0.1-degree VIIRS grid" else
             sprintf("VIIRS no-data mask: %d of %d Gulf water cells (5 arcmin) masked", sum(masked5_static & domain), sum(domain)),
             xl, yl, axes = TRUE)
  image(xs, ys, to_z(mask_cat), breaks = c(-0.5, 0.5, 1.5, 2.5, 3.5), col = mask_col, add = TRUE, useRaster = TRUE)
  draw_land()
  if (zoom) { abline(v = seq(-87.5, -81, 0.1), h = seq(25, 30.5, 0.1), col = "gray70", lwd = 0.3)
              pc <- xy1[valid_always, ]; points(pc[, 1], pc[, 2], pch = 3, cex = 0.4, col = "gray40") }
  legend("bottomleft", legend = c("template water, VIIRS valid every month", "no data in a few months (transient gap)", "static mask (no data in >= 90% of months)",
                                  "outside the Gulf domain (Atlantic box)", "template land", "Natural Earth 1:10m coastline", if (zoom) "valid VIIRS cell centre"),
         fill = c(mask_col, "gray82", NA, if (zoom) NA), border = c(rep("gray40", 5), NA, if (zoom) NA),
         lty = c(NA, NA, NA, NA, NA, 1, if (zoom) NA), pch = c(NA, NA, NA, NA, NA, NA, if (zoom) 3), col = c(rep(NA, 5), "gray30", if (zoom) "gray40"),
         cex = 0.7, bg = "white", box.col = "gray60")
  box()
}
invisible(dev.off())

# Fig 2: distance to the coast, ECDF by class: status (top) and inside/outside the final footprint (bottom).
png(file.path(dir_fig, "fig2_dist_coast_ecdf.png"), width = 13, height = 6, units = "in", res = 150)
par(mfrow = c(2, 5), mar = c(3.2, 3.2, 2.4, 0.6), oma = c(0, 0, 1.8, 0), mgp = c(2, 0.6, 0))
for (k in pos_lv) {
  q <- pv[pv$class == k, ]
  plot(NA, xlim = c(0, 40), ylim = c(0, 1), xlab = "distance to coast (km)", ylab = "share of samples",
       main = sprintf("%s (n = %s)", class_lab[match(k, class_lv)], fmt_n(nrow(q))), cex.main = 0.85, cex.axis = 0.8, cex.lab = 0.8)
  abline(v = c(2, 5, 10), col = "gray75", lty = 3)
  for (s in status_lv) { d <- q$dist_coast_km[q$viirs_cell == s]; if (length(d)) lines(ecdf(d), col = scol[[s]], lwd = 1.6, do.points = FALSE, verticals = TRUE) }
  if (k == "background") legend("bottomright", legend = sprintf("%s", status_lab[status_lv]), col = scol[status_lv], lwd = 1.6, cex = 0.7, bg = "white", box.col = "gray60")
}
for (k in pos_lv) {
  q <- pv[pv$class == k & pv$template == "water" & pv$use == "viirs", ]
  q$inside <- q$in_final_fp %in% TRUE
  plot(NA, xlim = c(0, 40), ylim = c(0, 1), xlab = "distance to coast (km)", ylab = "share of samples",
       main = sprintf("%s, water cells (n = %s)", k, fmt_n(nrow(q))), cex.main = 0.85, cex.axis = 0.8, cex.lab = 0.8)
  abline(v = c(2, 5, 10), col = "gray75", lty = 3)
  for (ins in c(TRUE, FALSE)) { d <- q$dist_coast_km[q$inside == ins]; if (length(d)) lines(ecdf(d), col = if (ins) "darkgreen" else "darkorange3", lwd = 1.6, do.points = FALSE, verticals = TRUE) }
  if (k == "background") legend("bottomright", legend = c("inside the final footprint", "outside (final cell = 0)"), col = c("darkgreen", "darkorange3"), lwd = 1.6, cex = 0.7, bg = "white", box.col = "gray60")
}
mtext(sprintf("Distance to the coast of the %d-%d samples, by FWC class. Top: by VIIRS cell status. Bottom: VIIRS months, water cells, inside vs outside the final footprint. Dotted: 2, 5, 10 km.", viirs_era[1], viirs_era[2]),
      outer = TRUE, cex = 0.8, font = 2, line = 0.4)
invisible(dev.off())

# Fig 3: the headline months: samples by status | VIIRS layer | hull-clipped | hull-clipped inside the mask.
class_counts_v <- function(v) { v <- v[!is.na(v) & v > 0]; k <- cut(v, class_brks[-1], labels = FALSE, include.lowest = TRUE); c(length(v), tabulate(k, nbins = 5)) }
class_lines <- function(cnt) paste(fmt_n(cnt), c("positives", "<= 1,000", "1,000 - 10,000", "10,000 - 100,000", "100,000 - 1,000,000", "> 1,000,000"))
draw_samples_panel <- function(ym, main) {
  q <- pts[pts$yrmo == ym, ]
  base_panel(main); rect(xlim[1], ylim[1], xlim[2], ylim[2], col = "white", border = NA); draw_land()
  z0 <- q[q$cells == 0, ]; points(z0$lon, z0$lat, pch = ".", cex = 1.6, col = "gray45")
  pp <- q[q$cells > 0, ]; pp <- pp[order(pp$cells), ]
  bins <- cut(pp$cells, class_brks[-1], labels = FALSE, include.lowest = TRUE)
  points(pp$lon, pp$lat, pch = 21, bg = spal[bins], col = scol[pp$viirs_cell], cex = 0.75, lwd = 0.9)
  hi <- q[q$cells >= thr_bloom, ]
  info_box(c(class_lines(class_counts_v(q$cells)), sprintf(">= 10,000: %d masked, %d valid-0, %d valid+", sum(hi$viirs_cell == "masked"), sum(hi$viirs_cell == "valid_zero"), sum(hi$viirs_cell == "valid_pos"))))
  box()
}
draw_viirs_panel <- function(ym, main) {
  v <- Vr[, ym]; z <- ifelse(is.na(v), 0, ifelse(v > 0, 2, 1))
  base_panel(main)
  image(xs1, ys1, to_z1(z), breaks = c(-0.5, 0.5, 1.5, 2.5), col = c("gray82", "white", "deepskyblue3"), add = TRUE, useRaster = TRUE)
  plot(sf::st_geometry(coast), add = TRUE, col = "gray30", lwd = 0.5)
  info_box(c(sprintf("%d no-data cells", sum(is.na(v))), sprintf("%d valid, no detection", sum(v == 0, na.rm = TRUE)), sprintf("%d valid, detection", sum(v > 0, na.rm = TRUE))))
  box()
}
draw_map_panel <- function(v, main, outline = NULL, mask_overlay = FALSE) {
  base_panel(main); rect(xlim[1], ylim[1], xlim[2], ylim[2], col = "white", border = NA)
  image(xs, ys, to_z(v), breaks = brks_img, col = color, add = TRUE, useRaster = TRUE)
  if (mask_overlay) image(xs, ys, to_z(ifelse(masked5_static & domain, 1, NA)), col = grDevices::adjustcolor("orangered", 0.25), add = TRUE, useRaster = TRUE)
  draw_land()
  if (!is.null(outline)) plot(sf::st_geometry(outline), add = TRUE, border = "gray40", col = NA, lwd = 0.6)
  info_box(class_lines(class_counts_v(v)))
  box()
}
png(file.path(dir_fig, "fig3_headline_months.png"), width = 12, height = 2.5 * length(headline) + 0.9, units = "in", res = 120)
par(mfrow = c(length(headline), 4), mar = c(0.4, 0.5, 1.5, 0.5), oma = c(0.3, 0, 3.0, 0))
for (ym in headline) {
  lab <- paste0(substr(ym, 1, 4), "-", substr(ym, 5, 6)); r <- t5[t5$yrmo == ym, ]
  draw_samples_panel(ym, sprintf("%s: FWC samples by VIIRS cell status", lab))
  draw_viirs_panel(ym, "VIIRS layer (0.1 degree)")
  h <- H[, ym]
  draw_map_panel(h, sprintf("Hull-clipped, mask shaded (%s km2 >= 10k)", fmt_n(round(r$area_1e4_hull_km2))),
                 outline = pol_list[[ym]], mask_overlay = TRUE)
  draw_map_panel(ifelse(masked5_static & domain, h, 0), sprintf("Hull-clipped inside the mask (%s km2 >= 10k)", fmt_n(r$hull_1e4_km2_in_mask)))
}
mtext(sprintf("The %d headline months of #6 (fitted surface written as zero by an all-zero VIIRS layer): samples | VIIRS layer | hull-clipped map with the mask | what a mask rule would restore",
              length(headline)), outer = TRUE, cex = 0.85, font = 2, line = 1.6)
mtext("Samples: fill = FWC class (viridis, light = background to dark = > 1,000,000 cells/L), border = VIIRS cell (red masked, black valid with no detection, blue valid with detection). Maps: pipeline palette, white below 10,000 cells/L.",
      outer = TRUE, cex = 0.72, line = 0.3)
invisible(dev.off())

# Fig 4: 2012-2024, low / medium / high samples per month, masked vs valid cells.
all_months <- sprintf("%d%02d", rep(viirs_era[1]:viirs_era[2], each = 12), 1:12)
vz <- tab6$viirs_status[match(all_months, tab6$yrmo)]
cnt_panel <- function(statuses) sapply(all_months, function(ym) {
  q <- pts[pts$yrmo == ym & pts$viirs_cell %in% statuses, ]
  sapply(c("low", "medium", "high"), function(k) sum(q$class == k))
})
png(file.path(dir_fig, "fig4_monthly_status.png"), width = 13, height = 6.5, units = "in", res = 150)
par(mfrow = c(2, 1), mar = c(2.8, 3.6, 2.2, 0.6), oma = c(0, 0, 1.6, 0), mgp = c(2.2, 0.6, 0))
for (pnl in 1:2) {
  M <- if (pnl == 1) cnt_panel("masked") else cnt_panel(c("valid_zero", "valid_pos"))
  ymax <- max(colSums(cnt_panel("masked")), colSums(cnt_panel(c("valid_zero", "valid_pos")))) * 1.05
  bp <- barplot(M, col = spal[3:5], border = NA, names.arg = rep("", length(all_months)), ylim = c(0, ymax), ylab = "samples", space = 0,
                main = if (pnl == 1) "Samples in masked VIIRS cells (no data)" else "Samples in valid VIIRS cells (detection or not)", cex.main = 0.9, cex.axis = 0.8)
  zero_m <- which(vz == "zero"); miss_m <- which(vz == "missing")
  rect(bp[zero_m] - 0.5, 0, bp[zero_m] + 0.5, ymax, col = grDevices::adjustcolor("gray40", 0.18), border = NA)
  rect(bp[miss_m] - 0.5, 0, bp[miss_m] + 0.5, ymax, col = grDevices::adjustcolor("red", 0.25), border = NA)
  barplot(M, col = spal[3:5], border = NA, names.arg = rep("", length(all_months)), add = TRUE, space = 0, axes = FALSE)
  jan <- which(substr(all_months, 5, 6) == "01"); axis(1, at = bp[jan], labels = substr(all_months[jan], 1, 4), cex.axis = 0.8)
  if (pnl == 1) legend("topleft", legend = c("low (10,000 - 100,000)", "medium (100,000 - 1,000,000)", "high (> 1,000,000)", "VIIRS layer all zero", "VIIRS tif missing"),
                       fill = c(spal[3:5], grDevices::adjustcolor("gray40", 0.18), grDevices::adjustcolor("red", 0.25)), border = NA, cex = 0.75, bg = "white", box.col = "gray60")
}
mtext(sprintf("FWC samples at or above %s cells/L per month, %d-%d, by FWC class: in masked VIIRS cells (top) and in valid cells (bottom); shaded months have an all-zero VIIRS layer",
              format(thr_bloom, big.mark = ","), viirs_era[1], viirs_era[2]), outer = TRUE, cex = 0.85, font = 2, line = 0.3)
invisible(dev.off())
cat("\nDone.\n")
