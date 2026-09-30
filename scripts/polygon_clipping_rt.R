#' Polygon-based clipping of sdmTMB predictions.
#'
#' Three steps in the clipping cascade:
#'   - fn.buffered_hulls(): per-month buffered footprints (concave hull or
#'     buffered points per single-linkage cluster) around positive
#'     observations. Used for all months (fallback). Also writes
#'     hull_diagnostics.csv.
#'   - fn.clip_2_hulls(): mask the predicted stack with those hulls.
#'   - make_redtide_ascii(): merge hull/MODIS/VIIRS-clipped stacks into a
#'     single combined stack (VIIRS > MODIS > hulls by preference)
#'     and write monthly ASCII files for Ecospace.
#'
#' fn.plot_redtide_stack() renders the combined stack to a PDF.

# Per-month buffered footprints around positive HAB observations ---------

#' Build per-month bloom-footprint polygons around positive HAB observations.
#'
#' For each (year, month) with at least one positive sample (`cells != 0`),
#' positives are grouped by single-linkage hierarchical clustering
#' (`stats::hclust` / `stats::cutree`) cut at `link_km`: two samples share
#' a footprint when a chain of positive samples connects them with every
#' link shorter than `link_km`. Each cluster then gets one footprint:
#'   - clusters with at least `min_hull_pts` distinct locations get a
#'     concave hull (`concaveman`, concavity `concavity`);
#'   - smaller clusters, and clusters whose hull is degenerate (collinear
#'     points), get the points themselves;
#' and every footprint is buffered by `buffer_km`. The rule is deterministic,
#' so the same input always gives the same polygons. This replaced a k-means
#' split that lumped distant outliers into one long hull (issue #3).
#'
#' As a side effect the function writes `hull_diagnostics.csv` into
#' `dir_out`, one row per (year, month) with samples: `yrmo, n_pos,
#' n_locations, n_clusters, cluster_sizes, n_polys, total_area_km2,
#' max_area_km2, max_span_km, flagged`. `max_span_km` is the largest
#' bounding-box diagonal of any footprint (UTM zone 17N, before
#' reprojection) and `flagged = max_span_km > warn_span_km`. A flag is a
#' prompt for a human look, not a failure: a real coast-wide bloom can
#' legitimately exceed the threshold.
#'
#' @param file_filtered Path to filtered HAB Rdata (filtered_points_df).
#' @param file_depth Path to depth ASCII (only used to assert template loadable).
#' @param dir_out Directory to write the hull-polys Rdata and the
#'   diagnostics CSV into.
#' @param styr,enyr Optional year range. If NULL, all years in the
#'   filtered data are processed.
#' @param link_km Single-linkage cut distance in km (default 75). Positive
#'   samples farther apart than this, with no chain of closer positives
#'   between them, get separate footprints.
#' @param buffer_km Buffer around each footprint in km (default 10).
#' @param min_hull_pts Distinct locations needed for a concave hull
#'   (default 4); smaller clusters get buffered points.
#' @param concavity concaveman concavity for every hull (default 2).
#' @param warn_span_km Footprint span (km) above which a month is flagged
#'   in the diagnostics (default 300).
#' @return Path to the written hull-polys Rdata file. The file holds
#'   `pol_list`: one sf (EPSG:4326, MULTIPOLYGON) per month, named
#'   `"%d%02d"`, as consumed by fn.clip_2_hulls().
fn.buffered_hulls <- function(file_filtered, file_depth, dir_out,
                              styr = NULL, enyr = NULL,
                              link_km = 75, buffer_km = 10,
                              min_hull_pts = 4, concavity = 2,
                              warn_span_km = 300) {
  load(file_filtered)  # provides filtered_points_df
  depth <- raster(file_depth)  # currently used only to validate the template
  invisible(depth)

  habyrs <- sort(unique(filtered_points_df$year))
  if (!is.null(styr)) habyrs <- habyrs[habyrs >= styr]
  if (!is.null(enyr)) habyrs <- habyrs[habyrs <= enyr]
  pts_utm <- st_transform(filtered_points_df, 32617)
  pol_list <- list()
  diag_rows <- list()

  for (y in habyrs) {
    for (m in sort(unique(filtered_points_df$month[filtered_points_df$year == y]))) {
      yrmo <- sprintf("%d%02d", y, m)
      cat(sprintf("####### %s %02d #######\n", y, m))
      pts_ym <- subset(pts_utm, year == y & month == m & cells != 0)
      n_pos  <- nrow(pts_ym)

      if (n_pos == 0) {
        diag_rows[[yrmo]] <- data.frame(
          yrmo = yrmo, n_pos = 0L, n_locations = 0L, n_clusters = 0L,
          cluster_sizes = "", n_polys = 0L, total_area_km2 = 0,
          max_area_km2 = 0, max_span_km = 0, flagged = FALSE,
          stringsAsFactors = FALSE)
        next
      }

      # Single-linkage clusters cut at link_km. hclust() needs >= 2 points.
      # Exact duplicate coordinates are fine (distance 0), so no jitter.
      coords <- st_coordinates(pts_ym)
      grp <- if (n_pos == 1) 1L else
        cutree(hclust(dist(coords), method = "single"), h = link_km * 1000)
      pts_ym$group <- factor(grp)

      # Work in sfc throughout: concaveman() on an sf object returns a
      # geometry column named "polygons", which would not bind with
      # st_sf(geometry = ...).
      footprints <- lapply(split(pts_ym, pts_ym$group), function(gp) {
        g   <- st_geometry(gp)
        g_u <- st_cast(st_union(g), "POINT")           # distinct locations only
        core <- NULL
        if (length(g_u) >= min_hull_pts)
          core <- tryCatch(concaveman(g_u, concavity = concavity),
                           error = function(e) NULL)
        # Too few distinct locations, or a degenerate (collinear) hull:
        # buffer the points themselves.
        if (is.null(core) || !all(st_is_valid(core)) ||
            sum(as.numeric(st_area(core))) == 0)
          core <- st_union(g_u)
        st_buffer(core, buffer_km * 1000)
      })

      # Diagnostics in UTM (metres) before reprojection.
      areas_km2 <- vapply(footprints,
                          function(f) sum(as.numeric(st_area(f))) / 1e6, numeric(1))
      spans_km  <- vapply(footprints, function(f) {
        b <- st_bbox(f)
        as.numeric(sqrt((b["xmax"] - b["xmin"])^2 + (b["ymax"] - b["ymin"])^2)) / 1000
      }, numeric(1))
      n_polys <- sum(vapply(footprints,
                            function(f) length(st_cast(f, "POLYGON")), integer(1)))
      sizes   <- sort(as.integer(table(pts_ym$group)), decreasing = TRUE)
      n_loc   <- length(st_cast(st_union(st_geometry(pts_ym)), "POINT"))

      diag_rows[[yrmo]] <- data.frame(
        yrmo           = yrmo,
        n_pos          = n_pos,
        n_locations    = n_loc,
        n_clusters     = length(footprints),
        cluster_sizes  = paste(sizes, collapse = ";"),
        n_polys        = n_polys,
        total_area_km2 = round(sum(areas_km2), 1),
        max_area_km2   = round(max(areas_km2), 1),
        max_span_km    = round(max(spans_km), 1),
        flagged        = max(spans_km) > warn_span_km,
        stringsAsFactors = FALSE)

      # One sf per month; the sfc objects already carry EPSG:32617. One
      # geometry type for the whole column so raster::rasterize() (via
      # sf::as_Spatial) never sees a mixed POLYGON/MULTIPOLYGON column.
      hab_pol <- st_sf(group    = names(footprints),
                       geometry = do.call(c, unname(footprints)))
      hab_pol <- st_cast(st_transform(hab_pol, 4326), "MULTIPOLYGON")
      pol_list[[yrmo]] <- hab_pol
    }
  }

  diag <- do.call(rbind, unname(diag_rows))
  write.csv(diag, file.path(dir_out, "hull_diagnostics.csv"), row.names = FALSE)

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
  list(file = out_file, stack = pred_clipped)
}

# Combine hull/MODIS/VIIRS-clipped stacks into the final Ecospace ASCII -

#' Combine hull/MODIS/VIIRS-clipped stacks into one stack and write the
#' per-month ASCII files for Ecospace.
#'
#' Preference rule per month: VIIRS > MODIS > hull (i.e. observation-based
#' satellite clipping is preferred where available). Function takes the
#' clipped-stack paths explicitly so it can't pick up stale files from
#' prior runs.
#'
#' @param file_hull  Path (without ext) of the hull-clipped stack. Required.
#' @param file_viirs Path (without ext) of the VIIRS-clipped stack, or NULL.
#' @param file_modis Path (without ext) of the MODIS-clipped stack, or NULL.
#' @param dir_ascii  Directory to write monthly ASCII files into.
#' @param dir_combined Directory to write the combined .grd stack into.
#' @param file_depth Path to depth ASCII (ocean/land mask).
#' @param var Variable prefix used in the ASCII filenames (default "log").
#' @return Path (without ext) to the combined .grd stack.
make_redtide_ascii <- function(file_hull,
                               file_viirs   = NULL,
                               file_modis   = NULL,
                               dir_ascii,
                               dir_combined,
                               file_depth,
                               var = "log") {
  if (is.null(file_hull) || !any(file.exists(paste0(file_hull, c(".grd",".gri")))))
    stop("file_hull is required and must point to an existing .grd stack.")
  depth <- raster(file_depth)

  hull_stack  <- stack(file_hull)
  viirs_stack <- if (!is.null(file_viirs)) stack(file_viirs) else stack()
  modis_stack <- if (!is.null(file_modis)) stack(file_modis) else stack()

  clip_source <- data.frame(yrmo = sort(unique(c(names(hull_stack),
                                                 names(viirs_stack),
                                                 names(modis_stack)))))
  clip_source$pred  <- clip_source$yrmo %in% names(hull_stack)
  clip_source$viirs <- clip_source$yrmo %in% names(viirs_stack)
  clip_source$modis <- clip_source$yrmo %in% names(modis_stack)
  clip_source$use   <- ifelse(clip_source$viirs, "viirs",
                       ifelse(clip_source$modis, "modis", "pred"))
  write.csv(clip_source, file.path(dirname(file_hull), "clipping_source.csv"),
            row.names = FALSE)

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
                             gsub("_clipped_hull$", "_clipped_combined",
                                  basename(file_hull)))
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
  # Upper break Inf so any cell value above 4M still renders darkred.
  brks <- c(0, 1e4 - 1, seq(1e4, 4e6, 10000), Inf)
  color <- c(funpal(length(brks) - 2), "darkred")

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
#' configured external location when the user asks. The destination is:
#'   <ecospace_root>/<res>min/red tide/sdmTMB/
#'
#' The destination must already exist. It is never created here, so a
#' mistyped root fails instead of silently writing somewhere new. Any file
#' that fails to copy stops the run.
#'
#' @param dir_ascii Source directory (produced by make_redtide_ascii).
#' @param ecospace_root Target Ecospace "ST drivers" root.
#' @param res Resolution in minutes.
#' @return Invisibly returns the destination directory.
export_to_ecospace <- function(dir_ascii, ecospace_root, res) {
  if (!is.character(ecospace_root) || length(ecospace_root) != 1 ||
      !nzchar(ecospace_root))
    stop("ecospace_root must be set to use export_to_ecospace().")
  dest <- file.path(ecospace_root, paste0(res, "min"), "red tide", "sdmTMB")
  if (!dir.exists(dest))
    stop("Ecospace export folder not found: ", dest,
         "\nCheck ecospace_root; the folder is not created automatically.")
  files <- list.files(dir_ascii, pattern = "\\.asc$", full.names = TRUE)
  ok <- file.copy(files, dest, overwrite = TRUE)
  if (!all(ok))
    stop("Failed to copy ", sum(!ok), "/", length(ok), " file(s) to ", dest,
         ": ", paste(basename(files[!ok]), collapse = ", "))
  message("Copied ", sum(ok), "/", length(ok), " file(s) to ", dest)
  invisible(dest)
}
