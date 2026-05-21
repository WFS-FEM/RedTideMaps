#' VIIRS red-tide probability stack + clipping.
#'
#' Two functions used by the main workflow:
#'   - fn.viirs_tifs2stack(): stack monthly VIIRS GeoTIFFs, fix extent/CRS,
#'                             write one combined .grd stack.
#'   - fn.clip_2_viirs():     mask a predicted sdmTMB stack to non-zero
#'                             VIIRS cells for each matching year-month.
#'
#' A diagnostic helper fn.get_viirs_obs() is retained for ad-hoc analysis;
#' it extracts VIIRS values at HAB observation locations.

# Stack monthly VIIRS GeoTIFFs ------------------------------------------

#' Build one stacked .grd from monthly VIIRS GeoTIFFs.
#'
#' Each input tif is read, given the WFS extent (-87.5..-81, 25..30.5)
#' and WGS84 CRS, then flipped vertically. Layers are named X<YYYY><MM>.
#'
#' @param dir_viirs Directory holding monthly VIIRS .tif files.
#' @return List with `file` (stack basename without .gri) and `stack`.
fn.viirs_tifs2stack <- function(dir_viirs) {
  lf <- list.files(dir_viirs, pattern = "tif$", full.names = TRUE, recursive = TRUE)
  if (length(lf) == 0)
    stop("No VIIRS tifs found under ", dir_viirs)

  yrmos <- as.numeric(gsub("_", "", substr(basename(lf), 1, 7)))
  sfx <- paste0(min(yrmos), "-", max(yrmos))

  viirs_stack <- stack()
  for (f in lf) {
    cat("################ ", f, " ####\n", sep = "")
    r <- raster(f)
    y <- substr(names(r), 2, 5)
    m <- substr(names(r), 7, 8)

    extent(r) <- c(-87.5, -81, 25, 30.5)
    crs(r)    <- "+proj=longlat +datum=WGS84 +no_defs"
    r1 <- flip(r, direction = "y")
    names(r1) <- paste0("X", y, m)
    viirs_stack <- addLayer(viirs_stack, r1)
  }

  file_viirs <- file.path(dir_viirs, paste0("VIIRS_", sfx))
  writeRaster(viirs_stack, filename = file_viirs, overwrite = TRUE)
  list(file = file_viirs, stack = viirs_stack)
}

# Extract VIIRS values at HAB observation locations ---------------------

#' Diagnostic helper: pair VIIRS values with HAB observations.
#'
#' @param file_filtered Path to filtered HAB Rdata.
#' @param viirs_stack Raster stack from fn.viirs_tifs2stack()$stack.
#' @return Data frame: year, month, lon, lat, viirs, obs.
fn.get_viirs_obs <- function(file_filtered, viirs_stack) {
  load(file_filtered)  # provides filtered_points_df
  filtered_points_df$month <- sprintf("%02d", filtered_points_df$month)

  viirs_obs <- data.frame()
  for (i in seq_len(nlayers(viirs_stack))) {
    r1 <- viirs_stack[[i]]
    y <- as.numeric(substr(names(viirs_stack)[i], 2, 5))
    m <- substr(names(viirs_stack)[i], 6, 7)
    cat(sprintf("################## %s%s###\n", y, m))
    if (mean(values(r1), na.rm = TRUE) == 0) { cat("### JUMPING -------\n"); next }

    ydf <- subset(filtered_points_df, year == y & month == m)
    if (nrow(ydf) == 0) next

    icoords <- data.frame(lon = ydf$lon, lat = ydf$lat, cells = ydf$cells)
    icoords <- icoords[order(icoords$cells), ]
    coordinates(icoords) <- ~ lon + lat
    vals <- raster::extract(r1, icoords)

    viirs_obs <- rbind(
      viirs_obs,
      data.frame(year = y, month = m,
                 lon = coordinates(icoords)[, 1],
                 lat = coordinates(icoords)[, 2],
                 viirs = vals, obs = ydf$cells))
  }
  viirs_obs
}

# Clip predicted stack to VIIRS polygons --------------------------------

#' Mask a predicted raster stack by months where VIIRS shows red tide.
#'
#' For each layer in `file_pred` whose name matches a VIIRS layer, the
#' VIIRS positive cells are dissolved to a polygon and used to mask the
#' prediction. Cells outside the polygon are set to 0; ocean NA cells in
#' depth are preserved.
#'
#' @param file_pred  Path (without extension) to predicted sdmTMB stack.
#' @param file_viirs Path (without extension) to VIIRS stack.
#' @param file_depth Path to depth ASCII (for ocean mask).
#' @param dir_out    Directory to write the *_clipped_viirs.grd stack into.
#' @return Raster stack of clipped predictions.
fn.clip_2_viirs <- function(file_pred, file_viirs, file_depth, dir_out) {
  viirs <- stack(file_viirs)
  pred  <- stack(file_pred)
  depth <- raster(file_depth)

  pred_clipped <- stack()
  do_clip <- which(names(pred) %in% names(viirs))

  for (i in do_clip) {
    y <- substr(names(pred)[i], 2, 5)
    m <- substr(names(pred)[i], 6, 7)
    ipred <- pred[[i]]
    r1 <- viirs[[which(names(viirs) == paste0("X", y, m))]]
    cat(sprintf("################## %s%s###\n", y, m))

    if (mean(values(r1), na.rm = TRUE) == 0 || nlayers(ipred) == 0) {
      ipred[] <- 0
      pred_clipped <- addLayer(pred_clipped, ipred)
      cat("### JUMPING -------\n")
      next
    }

    r2 <- r1
    r2[r2 == 0] <- NA
    r2pol <- rasterToPolygons(r2, fun = function(x) !is.na(x) & x != 0, dissolve = TRUE)
    r2pol <- st_union(st_as_sf(r2pol))
    r2pol <- st_sf(geometry = r2pol)
    st_crs(r2pol) <- st_crs(r2)

    ipred_terra <- rast(as.matrix(ipred), crs = projection(ipred), extent = extent(ipred))
    r2pol <- st_transform(r2pol, crs(ipred_terra))
    clipped <- mask(ipred_terra, vect(r2pol))
    clipped[is.na(clipped)] <- 0
    names(clipped) <- paste0("X", y, m)

    clipped <- raster(clipped)
    clipped[is.na(clipped)] <- 0
    clipped[is.na(depth)]   <- NA
    pred_clipped <- addLayer(pred_clipped, clipped)
  }

  fname  <- basename(file_pred)
  prefix <- sub("(.*stack_).*", "\\1", fname)
  start_date <- gsub("X", "", names(pred_clipped)[1])
  end_date   <- gsub("X", "", names(pred_clipped)[nlayers(pred_clipped)])
  file_clipped <- file.path(dir_out,
                            paste0(prefix, start_date, "-", end_date,
                                   "_clipped_viirs"))
  writeRaster(pred_clipped, file_clipped, overwrite = TRUE)
  list(file = file_clipped, stack = pred_clipped)
}
