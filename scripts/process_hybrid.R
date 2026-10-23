#' Nearshore set and the satellite + hull hybrid clip.
#'
#' Two functions used by the main workflow (issue #8 decision, #11 for the
#' VIIRS months, #10 for the MODIS months, #15 and #18 for the final set):
#'   - fn.nearshore_mask(): the static nearshore set (VIIRS no-data mask,
#'                           within 5 km of the coast, or touching a land
#'                           cell) as a raster.
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
#' if its centre lies within `coast_km` of the coastline. Rule `"mask5adj"`
#' (issue #15, decision D9; the default since issue #18) adds a third
#' criterion: the cell shares an edge or a corner with a land cell of the
#' template (a NODATA cell of the depth grid, the land of the Ecospace
#' basemap; the grid borders are not land). The Gulf domain is every
#' template water cell outside the Atlantic-side box that
#' fn.filter_hab_data() drops samples from (east of -82 E, north of
#' 28.5 N), which the VIIRS product does not cover. The set is static: one
#' raster for every month. On the 5-arcmin template `"mask5"` has 136 cells
#' (10,227 km2): 84 in the VIIRS mask, 132 within 5 km, 80 in both;
#' `"mask5adj"` has 189 cells (14,205 km2): 177 touch land, 53 of them by
#' that criterion only. The rule is written out in
#' docs/issue15_adjacent-land-hybrid/nearshore-set-method.md.
#'
#' @param file_viirs Path (without extension) to the VIIRS stack written
#'   by fn.viirs_tifs2stack().
#' @param file_depth Path to the depth ASCII template.
#' @param file_coast Path to the Natural Earth 1:10m coastline gpkg
#'   (`paths$file_coast`, tracked in data/coastline/; never downloaded here).
#' @param rule Nearshore rule: `"mask5"` (the VIIRS mask or within
#'   `coast_km` of the coast) or `"mask5adj"` (the same, or touching a land
#'   cell).
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
#'   VIIRS-mask part), `n_coast_cells` (the within-`coast_km` part) and
#'   `n_adjacent_cells` (the touching-land part; NA for `"mask5"`).
fn.nearshore_mask <- function(file_viirs, file_depth, file_coast, rule = "mask5adj",
                              coast_km = 5, mask_share = 0.9, coast_step_m = 200,
                              dir_out) {
  rule <- match.arg(rule, c("mask5", "mask5adj"))
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

  # Part 3 (rule "mask5adj", issue #15): water cells sharing an edge or a
  # corner with a land cell of the template. raster::adjacent() from the
  # water side, keeping the water cell of every pair whose neighbour is
  # land: the mirror of fn.build_coastal() in the EcospaceBasemap
  # repository, which runs the same adjacency from the land side. Cells on
  # the grid border get no neighbour beyond it, so the border is not land.
  adj <- rep(FALSE, n5)
  if (rule == "mask5adj") {
    pairs <- raster::adjacent(depth, cells = which(!land), directions = 8,
                              pairs = TRUE, include = FALSE)
    adj[unique(pairs[land[pairs[, 2]], 1])] <- TRUE
  }

  set <- domain & (in_mask | near_coast | adj)
  m <- raster(depth)
  m[] <- ifelse(land, NA_real_, as.numeric(set))
  names(m) <- paste0("nearshore_", rule)
  km2 <- values(area(depth))
  file_mask <- file.path(dir_out, paste0("nearshore_mask_", rule))
  writeRaster(m, file_mask, overwrite = TRUE)
  n_adj <- if (rule == "mask5adj") sum(domain & adj) else NA_integer_
  message(sprintf("Nearshore set %s: %d cells, %s km2 (%d in the VIIRS mask, %d within %g km of the coast%s)",
                  rule, sum(set), format(round(sum(km2[set])), big.mark = ","),
                  sum(domain & in_mask), sum(domain & near_coast), coast_km,
                  if (rule == "mask5adj") sprintf(", %d adjacent to land", n_adj) else ""))
  list(file = file_mask, raster = m, n_cells = sum(set), km2 = sum(km2[set]),
       n_mask_cells = sum(domain & in_mask), n_coast_cells = sum(domain & near_coast),
       n_adjacent_cells = n_adj)
}

# Hybrid clip: satellite outside the nearshore set, satellite or hull inside -----

#' Add the hull footprint to satellite-clipped layers inside the nearshore set.
#'
#' For every layer of a satellite-clipped stack (VIIRS, fn.clip_2_viirs(),
#' or MODIS, fn.clip_2_modis()): outside the nearshore set the
#' satellite-clipped layer stands, zeros included (where the satellite has
#' valid observations its result is kept, Yao Yao's condition); inside the
#' set a cell takes the maximum of the satellite-clipped and hull-clipped
#' layers of the month, so the sample-based footprint is added nearshore
#' and never removes a satellite detection. Months not in the output are
#' served by make_redtide_ascii() from the next source of the cascade as
#' before.
#'
#' @param file_sat_clipped Path (without extension) to the satellite-clipped
#'   stack (`*_clipped_viirs` or `*_clipped_modis`).
#' @param file_hull_clipped Path (without extension) to the hull-clipped
#'   stack from fn.clip_2_hulls().
#' @param file_mask Path (without extension) to the nearshore raster from
#'   fn.nearshore_mask().
#' @param file_depth Path to the depth ASCII (ocean/land mask).
#' @param dir_out Directory to write the hybrid stack into.
#' @param source `"viirs"` or `"modis"`: names the output
#'   (`*_clipped_hybrid` for VIIRS, as in issue #11; `*_clipped_hybrid_modis`
#'   for MODIS, issue #10) and the messages.
#' @param months Optional character vector of months (`"yyyymm"`) to keep;
#'   NULL (default) takes every layer of the satellite stack. The driver
#'   passes the MODIS months that have no VIIRS layer, i.e. the months the
#'   cascade serves from MODIS, so the hybrid stack holds only months it
#'   will write.
#' @return List: `file` (path without extension), `stack`, `source`, and
#'   `months`, a data frame with one row per layer: `yrmo`, `source`,
#'   `cells_changed` (cells where the hybrid differs from the
#'   satellite-clipped layer) and `changed`.
fn.clip_2_hybrid <- function(file_sat_clipped, file_hull_clipped, file_mask,
                             file_depth, dir_out, source = c("viirs", "modis"),
                             months = NULL) {
  source    <- match.arg(source)
  label     <- c(viirs = "VIIRS", modis = "MODIS")[[source]]
  depth     <- raster(file_depth)
  sat       <- stack(file_sat_clipped)
  hull      <- stack(file_hull_clipped)
  nearshore <- raster(file_mask)
  compareRaster(depth, sat, hull, nearshore)
  land   <- is.na(values(depth))
  inside <- values(nearshore) %in% 1
  if (!is.null(months)) {
    keep <- paste0("X", sub("^X", "", months))
    missing_sat <- setdiff(keep, names(sat))
    if (length(missing_sat) > 0)
      stop("No ", label, "-clipped layer for month(s): ",
           paste(sub("^X", "", missing_sat), collapse = ", "), call. = FALSE)
    sat <- sat[[keep]]
  }
  missing_hull <- setdiff(names(sat), names(hull))
  if (length(missing_hull) > 0)
    stop("No hull-clipped layer for ", label, " month(s): ",
         paste(sub("^X", "", missing_hull), collapse = ", "), call. = FALSE)

  # The same normalisation make_redtide_ascii() applies: NA -> 0 on water
  # (an all-zero satellite month is written with zeros everywhere), land -> NA.
  norm <- function(v) { v[is.na(v)] <- 0; v[land] <- NA; v }
  hybrid <- stack()
  rows   <- vector("list", nlayers(sat))
  for (i in seq_len(nlayers(sat))) {
    nm  <- names(sat)[i]
    v   <- norm(values(sat[[i]]))
    h   <- norm(values(hull[[which(names(hull) == nm)]]))
    out <- v
    out[inside] <- pmax(v[inside], h[inside])
    n_changed <- sum(out != v, na.rm = TRUE)
    r <- raster(depth)
    r[] <- out
    names(r) <- nm
    hybrid <- addLayer(hybrid, r)
    rows[[i]] <- data.frame(yrmo = sub("^X", "", nm), source = source, cells_changed = n_changed,
                            changed = n_changed > 0, stringsAsFactors = FALSE)
    cat(sprintf("################## %s (%s): %d nearshore cell(s) changed\n", sub("^X", "", nm), label, n_changed))
  }
  months_tab <- do.call(rbind, rows)

  suffix <- if (source == "viirs") "_clipped_hybrid" else "_clipped_hybrid_modis"
  base <- basename(file_sat_clipped)
  base <- if (grepl(paste0("_clipped_", source, "$"), base))
    sub(paste0("_clipped_", source, "$"), suffix, base) else paste0(base, suffix)
  file_hybrid <- file.path(dir_out, base)
  writeRaster(hybrid, file_hybrid, overwrite = TRUE)
  message(sprintf("Hybrid (%s): %d of %d month(s) changed by the nearshore rule",
                  label, sum(months_tab$changed), nrow(months_tab)))
  list(file = file_hybrid, stack = hybrid, source = source, months = months_tab)
}
