#' Nearshore set and the satellite + hull hybrid clip.
#'
#' Two functions used by the main workflow (issue #8 decision, #11 for the
#' VIIRS months, #10 for the MODIS months):
#'   - fn.nearshore_mask(): the static nearshore set (VIIRS no-data mask
#'                           or within 5 km of the coast) as a raster.
#'   - fn.clip_2_hybrid():  the satellite-clipped layer outside that set,
#'                           the cell-wise maximum of the satellite- and
#'                           hull-clipped layers inside it.
#' Both were in process_VIIRS.R until issue #10 applied the rule to the
#' MODIS months as well.

# Nearshore set for the satellite + hull hybrid -------------------------

#' Flag the nearshore water cells the hull footprint may serve in satellite months.
#'
#' The VIIRS product carries a static no-data band along the coast (the
#' first row of 0.1-degree cells plus the bays, 0 to about 5 km wide) that
#' holds about two thirds of the FWC samples in every abundance class
#' (issue #8). Rule `"mask5"` (issue #8, decision D1): a template water
#' cell of the Gulf domain is nearshore if its 0.1-degree VIIRS cell is in
#' that static mask (NA in at least `mask_share` of the VIIRS layers), or
#' if its centre lies within `coast_km` of the coastline. The Gulf domain
#' is every template water cell outside the Atlantic-side box that
#' fn.filter_hab_data() drops samples from (east of -82 E, north of
#' 28.5 N), which the VIIRS product does not cover. The set is static: one
#' raster for every month. On the 5-arcmin template it has 136 cells
#' (10,227 km2): 84 in the VIIRS mask, 132 within 5 km, 80 in both.
#'
#' @param file_viirs Path (without extension) to the VIIRS stack written
#'   by fn.viirs_tifs2stack().
#' @param file_depth Path to the depth ASCII template.
#' @param file_coast Path to the Natural Earth 1:10m coastline gpkg
#'   (`paths$file_coast`, tracked in data/coastline/; never downloaded here).
#' @param rule Nearshore rule. Only `"mask5"` is implemented.
#' @param coast_km Distance to the coastline (km, inclusive) for the coast
#'   part of the set.
#' @param mask_share Share of the VIIRS layers a 0.1-degree cell must be
#'   NA in to count as the static mask (0.9: a handful of cells have data
#'   in one or two months).
#' @param coast_step_m The coastline is densified to points this far apart
#'   (m, UTM 17N) before nearest-point distances are taken, as in the
#'   issue #8 diagnostic.
#' @param dir_out Directory to write `nearshore_mask_<rule>.grd` into.
#' @return List: `file` (path without extension), `raster` (1 = nearshore,
#'   0 = other water, NA = land), `n_cells`, `km2`, `n_mask_cells` (the
#'   VIIRS-mask part) and `n_coast_cells` (the within-`coast_km` part).
fn.nearshore_mask <- function(file_viirs, file_depth, file_coast, rule = "mask5",
                              coast_km = 5, mask_share = 0.9, coast_step_m = 200,
                              dir_out) {
  rule <- match.arg(rule, "mask5")
  if (!file.exists(file_coast))
    stop("Coastline not found: ", file_coast,
         "\nIt is tracked in data/coastline/ (see the README there); ",
         "the pipeline does not download it.", call. = FALSE)
  depth <- raster(file_depth)
  viirs <- brick(file_viirs)
  land  <- is.na(values(depth))
  n5    <- ncell(depth)
  xy5   <- xyFromCell(depth, seq_len(n5))
  atl   <- xy5[, 1] > -82 & xy5[, 2] > 28.5
  domain <- !land & !atl

  # Part 1: the static VIIRS no-data mask, read from the stack itself and
  # mapped to the template cells by their centres.
  na_per_cell <- rowSums(is.na(values(viirs)))
  mask01  <- na_per_cell >= mask_share * nlayers(viirs)
  cell01  <- cellFromXY(viirs, xy5)
  if (anyNA(cell01))
    stop("Some template cell centres fall outside the VIIRS extent.", call. = FALSE)
  in_mask <- mask01[cell01]

  # Part 2: cell centres within coast_km of the coastline (nearest point of
  # the coastline densified to coast_step_m, UTM 17N, as the hulls).
  coast     <- st_read(file_coast, quiet = TRUE)
  coast_utm <- st_transform(st_geometry(coast), 32617)
  seg       <- st_segmentize(coast_utm, coast_step_m)
  coast_pts <- st_cast(st_sfc(st_multipoint(st_coordinates(seg)[, 1:2]), crs = 32617), "POINT")
  p  <- st_as_sf(data.frame(lon = xy5[!land, 1], lat = xy5[!land, 2]),
                 coords = c("lon", "lat"), crs = 4326)
  p  <- st_transform(p, 32617)
  nn <- st_nearest_feature(p, coast_pts)
  dist_km <- rep(NA_real_, n5)
  dist_km[!land] <- as.numeric(st_distance(st_geometry(p), coast_pts[nn], by_element = TRUE)) / 1000
  near_coast <- !is.na(dist_km) & dist_km <= coast_km

  set <- domain & (in_mask | near_coast)
  m <- raster(depth)
  m[] <- ifelse(land, NA_real_, as.numeric(set))
  names(m) <- paste0("nearshore_", rule)
  km2 <- values(area(depth))
  file_mask <- file.path(dir_out, paste0("nearshore_mask_", rule))
  writeRaster(m, file_mask, overwrite = TRUE)
  message(sprintf("Nearshore set %s: %d cells, %s km2 (%d in the VIIRS mask, %d within %g km of the coast)",
                  rule, sum(set), format(round(sum(km2[set])), big.mark = ","),
                  sum(domain & in_mask), sum(domain & near_coast), coast_km))
  list(file = file_mask, raster = m, n_cells = sum(set), km2 = sum(km2[set]),
       n_mask_cells = sum(domain & in_mask), n_coast_cells = sum(domain & near_coast))
}

# Hybrid clip: VIIRS outside the nearshore set, VIIRS or hull inside -----

#' Add the hull footprint to the VIIRS-clipped layers inside the nearshore set.
#'
#' For every layer of the VIIRS-clipped stack: outside the nearshore set the
#' VIIRS-clipped layer stands, zeros included (where VIIRS has valid
#' observations its result is kept, Yao Yao's condition); inside the set a
#' cell takes the maximum of the VIIRS-clipped and hull-clipped layers of
#' the month, so the sample-based footprint is added nearshore and never
#' removes a VIIRS detection. Months without a VIIRS layer are not in the
#' output; make_redtide_ascii() serves them from MODIS or the hulls as
#' before.
#'
#' @param file_viirs_clipped Path (without extension) to the VIIRS-clipped
#'   stack from fn.clip_2_viirs().
#' @param file_hull_clipped Path (without extension) to the hull-clipped
#'   stack from fn.clip_2_hulls().
#' @param file_mask Path (without extension) to the nearshore raster from
#'   fn.nearshore_mask().
#' @param file_depth Path to the depth ASCII (ocean/land mask).
#' @param dir_out Directory to write the *_clipped_hybrid.grd stack into.
#' @return List: `file` (path without extension), `stack`, and `months`, a
#'   data frame with one row per VIIRS month: `yrmo`, `cells_changed`
#'   (cells where the hybrid differs from the VIIRS-clipped layer) and
#'   `changed`.
fn.clip_2_hybrid <- function(file_viirs_clipped, file_hull_clipped, file_mask,
                             file_depth, dir_out) {
  depth     <- raster(file_depth)
  viirs     <- stack(file_viirs_clipped)
  hull      <- stack(file_hull_clipped)
  nearshore <- raster(file_mask)
  compareRaster(depth, viirs, hull, nearshore)
  land   <- is.na(values(depth))
  inside <- values(nearshore) %in% 1
  missing_hull <- setdiff(names(viirs), names(hull))
  if (length(missing_hull) > 0)
    stop("No hull-clipped layer for VIIRS month(s): ",
         paste(sub("^X", "", missing_hull), collapse = ", "), call. = FALSE)

  # The same normalisation make_redtide_ascii() applies: NA -> 0 on water
  # (an all-zero VIIRS month is written with zeros everywhere), land -> NA.
  norm <- function(v) { v[is.na(v)] <- 0; v[land] <- NA; v }
  hybrid <- stack()
  rows   <- vector("list", nlayers(viirs))
  for (i in seq_len(nlayers(viirs))) {
    nm  <- names(viirs)[i]
    v   <- norm(values(viirs[[i]]))
    h   <- norm(values(hull[[which(names(hull) == nm)]]))
    out <- v
    out[inside] <- pmax(v[inside], h[inside])
    n_changed <- sum(out != v, na.rm = TRUE)
    r <- raster(depth)
    r[] <- out
    names(r) <- nm
    hybrid <- addLayer(hybrid, r)
    rows[[i]] <- data.frame(yrmo = sub("^X", "", nm), cells_changed = n_changed,
                            changed = n_changed > 0, stringsAsFactors = FALSE)
    cat(sprintf("################## %s: %d nearshore cell(s) changed\n", sub("^X", "", nm), n_changed))
  }
  months <- do.call(rbind, rows)

  base <- basename(file_viirs_clipped)
  base <- if (grepl("_clipped_viirs$", base)) sub("_clipped_viirs$", "_clipped_hybrid", base) else
    paste0(base, "_clipped_hybrid")
  file_hybrid <- file.path(dir_out, base)
  writeRaster(hybrid, file_hybrid, overwrite = TRUE)
  message(sprintf("Hybrid: %d of %d VIIRS month(s) changed by the nearshore rule",
                  sum(months$changed), nrow(months)))
  list(file = file_hybrid, stack = hybrid, months = months)
}
