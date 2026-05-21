#' Polygon-based clipping of sdmTMB predictions.
#'
#' Three steps in the clipping cascade:
#'   - fn.buffered_hulls(): per-month buffered concave hulls around
#'     positive observations. Used for all months (fallback).
#'   - fn.clip_2_hulls(): mask the predicted stack with those hulls.
#'   - make_redtide_ascii(): merge hull/MODIS/VIIRS-clipped stacks into a
#'     single combined stack (VIIRS > MODIS > hulls by preference)
#'     and write monthly ASCII files for Ecospace.
#'
#' fn.plot_redtide_stack() renders the combined stack to a PDF.

# Per-month buffered concave hulls around positive HAB observations -----

#' Build per-month concave-hull polygons (with 10 km buffer) around
#' positive HAB observations. k-means splits multi-cluster months.
#'
#' @param file_filtered Path to filtered HAB Rdata (filtered_points_df).
#' @param file_depth Path to depth ASCII (only used to assert template loadable).
#' @param dir_out Directory to write the hull-polys Rdata into.
#' @return Path to the written Rdata file.
fn.buffered_hulls <- function(file_filtered, file_depth, dir_out) {
  load(file_filtered)  # provides filtered_points_df
  depth <- raster(file_depth)  # currently used only to validate the template
  invisible(depth)

  habyrs <- sort(unique(filtered_points_df$year))
  pts_utm <- st_transform(filtered_points_df, 32617)
  pol_list <- list()

  for (y in habyrs) {
    for (m in sort(unique(filtered_points_df$month[filtered_points_df$year == y]))) {
      cat(sprintf("####### %s %02d #######\n", y, m))
      pts_ym <- subset(pts_utm, year == y & month == m & cells != 0)
      coords <- st_coordinates(pts_ym)
      if (nrow(coords) < 4) next

      # Jitter duplicated coordinates so concave hull doesn't degenerate
      dups <- duplicated(coords) | duplicated(coords, fromLast = TRUE)
      if (sum(dups) > 1) {
        coords_jit <- coords
        coords_jit[dups, ] <- coords[dups, ] *
          matrix(1 + runif(sum(dups) * 2, -1, 1) / 1e6, ncol = 2)
        new_geom <- st_sfc(lapply(seq_len(nrow(coords_jit)),
                                  function(i) st_point(coords_jit[i, ])),
                           crs = 32617)
        pts_ym2 <- pts_ym
        st_geometry(pts_ym2) <- new_geom
      } else {
        pts_ym2 <- pts_ym
      }
      if (nrow(pts_ym2) < 4) next

      # Pick number of clusters from k-means within-SS elbow
      coords <- st_coordinates(pts_ym2)
      wss <- numeric()
      for (k in 1:min(10, nrow(coords) / 4)) {
        wss[k] <- kmeans(coords, centers = k)$tot.withinss
      }
      ncenters <- which.max(abs(diff(wss))) + 1

      if (length(ncenters) != 0) {
        km <- kmeans(coords, centers = ncenters)
        pts_ym2$group <- as.factor(km$cluster)
        if (min(table(pts_ym2$group)) >= 4) {
          polys <- lapply(split(pts_ym2, pts_ym2$group), function(gp) {
            hull <- concaveman(gp)
            st_transform(st_buffer(hull, 10000), 4326)
          })
          hab_pol <- do.call(rbind, polys)
        } else {
          hull <- concaveman(pts_ym2, concavity = 1)
          hab_pol <- st_transform(st_buffer(hull, 10000), 4326)
        }
      } else {
        hull <- concaveman(pts_ym2, concavity = 1)
        hab_pol <- st_transform(st_buffer(hull, 10000), 4326)
      }
      pol_list[[sprintf("%d%02d", y, m)]] <- hab_pol
    }
  }

  file_hullpolys <- file.path(
    dir_out, gsub("_filtered", "_hullpolys", basename(file_filtered)))
  save(pol_list, file = file_hullpolys)
  file_hullpolys
}

# Clip predicted stack to per-month hull polygons -----------------------

#' Mask a predicted stack to the per-month hull polygons.
#'
#' Months with no hull polygon get a zero-filled raster (ocean cells = 0,
#' land cells = NA).
#'
#' @param file_pred Path (without extension) to predicted sdmTMB stack.
#' @param file_polys Path to hull-polys Rdata.
#' @param file_depth Path to depth ASCII (for ocean/land mask).
#' @param dir_out Directory to write the *_clipped_hull.grd into.
#' @return Raster stack of clipped predictions.
fn.clip_2_hulls <- function(file_pred, file_polys, file_depth, dir_out) {
  depth <- raster(file_depth)
  land_mask <- calc(depth, function(x) ifelse(is.na(x), NA, 1))
  load(file_polys)  # provides pol_list
  polys <- pol_list
  pred_stack <- stack(file_pred)

  pred_clipped <- stack()
  for (i in seq_len(nlayers(pred_stack))) {
    yrmo <- gsub("X", "", names(pred_stack)[i])
    message(yrmo)

    if (yrmo %in% names(polys)) {
      p <- polys[[which(names(polys) == yrmo)]]
      r <- pred_stack[[i]]
      p <- st_transform(p, crs = crs(r))
      mask_raster <- rasterize(p, r, field = 1, background = NA)
      hab_raster <- mask(r, mask_raster)
      hab_raster[is.na(hab_raster)] <- 0
      hab_raster <- mask(hab_raster, land_mask)
    } else {
      hab_raster <- depth
      hab_raster[!is.na(depth)] <- 0
    }
    names(hab_raster) <- names(pred_stack)[i]
    pred_clipped <- addLayer(pred_clipped, hab_raster)
  }

  out_file <- file.path(dir_out,
                        gsub("\\.grd$", "_clipped_hull",
                             paste0(basename(file_pred), ".grd")))
  out_file <- gsub("\\.grd$", "", out_file)
  writeRaster(pred_clipped, out_file, overwrite = TRUE)
  pred_clipped
}

# Combine hull/MODIS/VIIRS-clipped stacks into the final Ecospace ASCII -

#' Combine hull/MODIS/VIIRS-clipped stacks into one stack and write the
#' per-month ASCII files for Ecospace.
#'
#' Preference rule per month: VIIRS > MODIS > hull (i.e. observation-based
#' satellite clipping is preferred where available).
#'
#' @param dir_pred Directory holding the *_clipped_hull/_clipped_viirs/
#'   _clipped_modis.grd stacks.
#' @param dir_ascii Directory to write monthly ASCII files into.
#' @param dir_combined Directory to write the combined .grd stack into.
#' @param file_depth Path to depth ASCII (ocean/land mask).
#' @param var Variable prefix to combine (default "log").
#' @return Path to the combined .grd stack (without extension).
make_redtide_ascii <- function(dir_pred,
                               dir_ascii,
                               dir_combined,
                               file_depth,
                               var = "log") {
  depth <- raster(file_depth)

  r_hull  <- list.files(dir_pred, pattern = paste0("^sdmTMB_", var, ".*hull\\.gri$"),  full.names = TRUE)
  r_viirs <- list.files(dir_pred, pattern = paste0("^sdmTMB_", var, ".*viirs\\.gri$"), full.names = TRUE)
  r_modis <- list.files(dir_pred, pattern = paste0("^sdmTMB_", var, ".*modis\\.gri$"), full.names = TRUE)

  hull_stack  <- if (length(r_hull)  > 0) stack(gsub("\\.gri$", "", r_hull))  else stack()
  viirs_stack <- if (length(r_viirs) > 0) stack(gsub("\\.gri$", "", r_viirs)) else stack()
  modis_stack <- if (length(r_modis) > 0) stack(gsub("\\.gri$", "", r_modis)) else stack()

  clip_source <- data.frame(yrmo = sort(unique(c(names(hull_stack),
                                                 names(viirs_stack),
                                                 names(modis_stack)))))
  clip_source$pred  <- clip_source$yrmo %in% names(hull_stack)
  clip_source$viirs <- clip_source$yrmo %in% names(viirs_stack)
  clip_source$modis <- clip_source$yrmo %in% names(modis_stack)
  clip_source$use   <- ifelse(clip_source$viirs, "viirs",
                       ifelse(clip_source$modis, "modis", "pred"))
  write.csv(clip_source, file.path(dir_pred, "clipping_source.csv"), row.names = FALSE)

  full_stack <- stack()
  for (i in seq_len(nrow(clip_source))) {
    yrmo_i <- clip_source$yrmo[i]
    src_i  <- clip_source$use[i]
    message(yrmo_i, " -> ", src_i)

    raster_i <- switch(src_i,
                       pred  = hull_stack[[which(names(hull_stack) == yrmo_i)]],
                       modis = modis_stack[[which(names(modis_stack) == yrmo_i)]],
                       viirs = viirs_stack[[which(names(viirs_stack) == yrmo_i)]])
    raster_i[is.na(raster_i)] <- 0
    raster_i[is.na(depth)]    <- NA
    full_stack <- addLayer(full_stack, raster_i)
  }

  message("saving rasters and ASCII files")
  combined_path <- file.path(dir_combined,
                             gsub("hull", "combined", basename(gsub("\\.gri$", "", r_hull))))
  writeRaster(full_stack, filename = combined_path, overwrite = TRUE)
  writeRaster(full_stack,
              filename = file.path(dir_ascii, paste0("sdmTMB_", var, "_")),
              bylayer = TRUE,
              suffix  = gsub("X", "", names(full_stack)),
              format  = "ascii",
              overwrite = TRUE)
  combined_path
}

# Plot the combined red-tide stack as a PDF -----------------------------

#' One PDF of monthly maps for the combined stack.
#'
#' @param file_stack Path (without extension) to the combined .grd stack.
#' @param dir_plots Directory for the PDF.
#' @return Invisibly returns the PDF path.
fn.plot_redtide_stack <- function(file_stack, dir_plots) {
  if (!dir.exists(dir_plots)) dir.create(dir_plots, recursive = TRUE)
  habstack <- stack(file_stack)

  colv <- c("white","purple","blue","darkblue","cyan","green","darkgreen","yellow","orange","red","darkred")
  funpal <- colorRampPalette(colv, bias = 2)
  brks <- c(0, 1e4 - 1, seq(1e4, 4e6, 10000), 1e8)
  color <- funpal(length(brks) - 1)

  file_pdf <- file.path(dir_plots, paste0(basename(file_stack), ".pdf"))
  pdf(file_pdf, onefile = TRUE)
  par(mfrow = c(4, 3), mar = c(1, 1, 2, 0), oma = c(2, 2, 0, 6))
  for (i in seq_len(nlayers(habstack))) {
    hab_i <- habstack[[i]]
    name_i <- names(habstack)[i]
    plot(hab_i, main = "", breaks = brks, col = color,
         colNA = "darkgray", legend = FALSE)
    map(database = "state", region = "Florida", add = TRUE, fill = TRUE, col = "wheat")
    text(-86, 26, gsub("X", "", name_i), cex = 1.5)
    if (substr(name_i, 6, 7) == "12") {
      par(mfrow = c(1, 1), mar = c(0, 0, 0, 0), oma = c(0, 0, 0, 1))
      image.plot(hab_i, legend.only = TRUE,
                 breaks = brks[-length(brks)], col = color[-1],
                 add = TRUE, legend.width = 1, legend.mar = 4,
                 legend.line = 3, legend.lab = "cells/L")
      par(mfrow = c(4, 3), mar = c(1, 1, 2, 0), oma = c(2, 2, 0, 6))
    }
  }
  dev.off()
  message("pdf file saved at: ", file_pdf)
  invisible(file_pdf)
}

# Opt-in: copy the ASCII drop to the WFS EwE ST drivers location --------

#' Copy the per-month ASCII files into the Ecospace ST drivers tree.
#'
#' Default behavior of the workflow writes to out/<res>min/ecospace_ascii/
#' inside the repo (or proj_dir). This function copies that drop to the
#' configured external location when the user asks. The destination is
#' typically:
#'   <ecospace_root>/<res>min/red tide/sdmTMB/
#'
#' @param dir_ascii Source directory (produced by make_redtide_ascii).
#' @param ecospace_root Target Ecospace "ST drivers" root.
#' @param res Resolution in minutes.
#' @return Invisibly returns the destination directory.
export_to_ecospace <- function(dir_ascii, ecospace_root, res) {
  if (is.null(ecospace_root) || ecospace_root == "")
    stop("ecospace_root must be set to use export_to_ecospace().")
  dest <- file.path(ecospace_root, paste0(res, "min"), "red tide", "sdmTMB")
  if (!dir.exists(dest)) dir.create(dest, recursive = TRUE)
  files <- list.files(dir_ascii, full.names = TRUE)
  ok <- file.copy(files, dest, overwrite = TRUE)
  message("Copied ", sum(ok), "/", length(ok), " file(s) to ", dest)
  invisible(dest)
}
