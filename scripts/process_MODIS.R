#' MODIS nFLH stack + red-tide polygon building + clipping.
#'
#' Four functions:
#'   - fn.pull_MODIS_flh_erddap(): pull/update monthly nFLH from ERDDAP.
#'   - fn.make_nflh_polys():       build red-tide polygons by thresholding
#'                                 monthly nFLH >= 0.02 mW cm-2 um-1 sr-1.
#'   - fn.clip_2_modis():          mask predicted stack with FLH polygons.
#'   - fn.plot_modis():            FLH maps with overlaid polygons.
#'
#' nFLH threshold rationale: Hu et al. 2005 suggested >= 0.012 for high
#' Chl-a. Calibration updates make 0.02 the current threshold to detect
#' HABs (personal communication, Chuanmin).

# Optional packages (only needed by ERDDAP pull / plotting helpers).
# Loaded here rather than in _setup.R to avoid forcing them on users
# who only run the main workflow.
.ensure_modis_pkgs <- function() {
  for (p in c("rerddap", "curl", "data.table", "rasterVis", "colorRamps")) {
    if (!requireNamespace(p, quietly = TRUE))
      stop("Package '", p, "' is required for MODIS helpers. ",
           "Install it or skip the MODIS update step.")
  }
  suppressPackageStartupMessages({
    library(rerddap); library(curl)
  })
}

# Pull MODIS FLH from ERDDAP ---------------------------------------------

#' Update the local MODIS nFLH monthly stack from ERDDAP.
#'
#' Discovers available monthly + daily datasets, downloads only what is
#' missing from the existing local stack, and writes a single .grd stack.
#'
#' @param file_depth Path to depth ASCII (defines bbox).
#' @param dir_modis Directory holding the catalog CSV and FLH-poly Rdata.
#' @param dir_modis_raw Directory holding the FLH raster stacks.
#' @return Path to the written .grd stack (without extension).
fn.pull_MODIS_flh_erddap <- function(file_depth, dir_modis, dir_modis_raw) {
  .ensure_modis_pkgs()
  bbox <- extent(raster(file_depth))
  today_lab <- format(Sys.Date(), "%Y%m%d")
  varname <- "flh"

  url_erddap <- "https://coastwatch.pfeg.noaa.gov/erddap/"
  ed <- cbind(do.call(rbind.data.frame,
                      ed_search(query = paste0(varname, " global modis"),
                                url = url_erddap)$alldata),
              var = varname)
  ed <- ed[, c("dataset_id", "var", "institution", "title")]
  ed <- ed[substr(ed$dataset_id, 1, 4) == "erdM", ]
  drops <- c(grep("DEPRECATED|8 Day|5 Day|EXPERIMENTAL|Lon0360", ed$title),
             which(substr(ed$title, 1, 3) %in% c("Dif", "Pho")),
             grep("NotMasked", ed$dataset_id))
  ed <- ed[-drops, ]
  dup_ids <- ed$dataset_id[duplicated(ed$dataset_id)]
  rem_ids <- which(ed$dataset_id %in% dup_ids & ed$var == "chla")
  if (length(rem_ids) > 0) ed <- ed[-rem_ids, ]
  ed$res <- ifelse(grepl("1day", ed$dataset_id), "day",
                   ifelse(grepl("mday", ed$dataset_id), "month", "other"))
  ed$t_end <- ed$t_start <- as.Date(NA)

  for (i in seq_len(nrow(ed))) {
    tmp <- info(ed$dataset_id[i], url = url_erddap)$alldata$time
    t0 <- as.Date(substr(tmp$value[tmp$attribute_name == "time_origin"], 1, 11),
                  format = "%d-%b-%Y")
    t1 <- as.numeric(unlist(strsplit(
      tmp$value[tmp$attribute_name == "actual_range"], split = ",")))
    t2 <- as.Date(as.POSIXct(t1, origin = t0, tz = "GMT"))
    ed$t_start[i] <- t2[1]; ed$t_end[i] <- t2[2]
  }
  ed <- ed[order(ed$var, ed$res, ed$dataset_id),
           c(1, 2, 5:7, 3, 4)]
  write.csv(ed,
            file.path(dir_modis, paste0("erddap_modis_datasets_", today_lab, ".csv")),
            row.names = FALSE)

  message("Now processing ", varname)
  var_m <- ed[ed$var == varname & ed$res == "month", ]
  var_d <- ed[ed$var == varname & ed$res == "day", ]

  avail_months <- format(seq.Date(min(var_m$t_start), max(var_m$t_end), "month"),
                         "%Y%m")
  avail_months <- data.frame(yrmo = avail_months, datid = NA)
  for (m in seq_len(nrow(avail_months))) {
    mm <- as.numeric(avail_months$yrmo[m])
    t1 <- as.numeric(gsub("-", "", substr(var_m$t_start, 1, 7))) <= mm
    t2 <- as.numeric(gsub("-", "", substr(var_m$t_end,   1, 7))) >= mm
    avail_months$datid[m] <- var_m$dataset_id[max(which(t1 & t2))]
  }
  avail_days <- seq.Date(min(var_d$t_start), max(var_d$t_end), "day")

  files_flh <- list.files(dir_modis_raw, pattern = "\\.gri$", full.names = TRUE)
  if (length(files_flh) > 0) {
    stack_in <- stack(gsub("\\.gri$", "", files_flh[length(files_flh)]))
    stack_in <- stack_in[[sort(names(stack_in))]]
    have_months <- gsub("X", "", names(stack_in))
    do_months <- avail_months[!avail_months$yrmo %in% as.numeric(have_months), ]
    last_day <- as.Date(substr(basename(files_flh),
                               nchar(basename(files_flh)) - 11,
                               nchar(basename(files_flh)) - 4),
                        format = "%Y%m%d")
    do_days <- avail_days[!as.numeric(gsub("-", "", substr(avail_days, 1, 7)))
                          %in% avail_months$yrmo]
    update_days <- ifelse(max(do_days) > last_day, TRUE, FALSE)
  } else {
    stack_in <- stack()
    do_months <- avail_months
    do_days <- avail_days[!as.numeric(gsub("-", "", substr(avail_days, 1, 7)))
                          %in% avail_months$yrmo]
    update_days <- TRUE
  }

  s_m <- stack()
  for (d in unique(do_months$datid)) {
    do_months_d <- do_months$yrmo[do_months$datid == d]
    erd_info1 <- griddap(info(d, url = url_erddap),
                         latitude = c("last", "last"),
                         longitude = c("last", "last"))
    erd_time1 <- data.frame(time = erd_info1$data$time)
    erd_time1$yrmo <- gsub("-", "", substr(erd_time1$time, 1, 7))
    erd_time1 <- erd_time1[as.numeric(erd_time1$yrmo) >= do_months_d[1], ]
    erd1 <- griddap(info(d, url = url_erddap),
                    latitude = bbox[3:4], longitude = bbox[1:2],
                    time = erd_time1$time[c(1, nrow(erd_time1))])
    stack_d <- stack(erd1$summary$filename, quick = TRUE)
    names(stack_d) <- erd_time1$yrmo
    keepers <- which(gsub("X", "", names(stack_d)) %in% do_months_d)
    if (length(keepers) > 0) s_m <- addLayer(s_m, stack_d[[keepers]])
  }

  s_m2 <- stack()
  if (update_days) {
    do_datid_d <- var_d$dataset_id[which.max(var_d$t_end)]
    erd_info2 <- griddap(info(do_datid_d, url = url_erddap),
                         latitude = c("last", "last"),
                         longitude = c("last", "last"))
    erd_time2 <- data.frame(time = erd_info2$data$time)
    erd_time2$yrmo <- gsub("-", "", substr(erd_time2$time, 1, 7))
    erd_time2$date <- as.Date(erd_time2$time)
    erd_time2 <- erd_time2[erd_time2$date >= do_days[1], ]
    erd2 <- griddap(info(do_datid_d, url = url_erddap),
                    latitude = bbox[3:4], longitude = bbox[1:2],
                    time = erd_time2$time[c(1, nrow(erd_time2))])
    s_d <- stack(erd2$summary$filename, quick = TRUE)
    names(s_d) <- erd_time2$date
    s_m2 <- stackApply(s_d, indices = erd_time2$yrmo, fun = mean, na.rm = TRUE)
    names(s_m2) <- sort(unique(erd_time2$yrmo))
  }

  if (dim(stack_in)[3] == 0) {
    stack_out <- if (dim(s_m)[3] > 0 && dim(s_m2)[3] > 0) stack(s_m, s_m2)
                 else if (dim(s_m)[3] > 0) s_m
                 else s_m2
  } else {
    stack_out <- if (dim(s_m)[3] > 0 && dim(s_m2)[3] > 0) stack(stack_in, s_m, s_m2)
                 else if (dim(s_m)[3] > 0) stack(stack_in, s_m)
                 else if (dim(s_m2)[3] > 0) stack(stack_in, s_m2)
                 else stack_in
  }

  file_modis_raw <- file.path(
    dir_modis_raw,
    paste0(varname, "_", paste(round(as.matrix(bbox), 1), collapse = "_"),
           "_", gsub("X", "", names(stack_out)[1]),
           "-", gsub("-", "", tail(erd_time2$date, 1))))
  writeRaster(stack_out, filename = file_modis_raw, overwrite = TRUE)
  if (length(files_flh) > 0) {
    unlink(files_flh)
    unlink(gsub("\\.gri$", ".grd", files_flh))
  }
  file_modis_raw
}

# Clip predicted stack to MODIS FLH polygons -----------------------------

#' Mask a predicted raster stack to MODIS nFLH-derived red-tide polygons.
#'
#' @param file_pred  Path (without extension) to predicted sdmTMB stack.
#' @param file_flhpolys Path to FLH-polys Rdata file.
#' @param file_depth Path to depth ASCII (for ocean mask).
#' @param dir_out    Directory to write the *_clipped_modis.grd into.
#' @return Raster stack of clipped predictions.
fn.clip_2_modis <- function(file_pred, file_flhpolys, file_depth, dir_out) {
  load(file_flhpolys)  # provides flh.polys
  pred <- stack(file_pred)
  depth <- raster(file_depth)

  pred_clipped <- stack()
  do_clip <- which(names(pred) %in% names(flh.polys))

  for (i in do_clip) {
    y <- substr(names(pred)[i], 2, 5); m <- substr(names(pred)[i], 6, 7)
    message(paste(y, m))
    p <- flh.polys[[which(names(flh.polys) == names(pred)[i])]]
    ri <- pred[[i]]
    pi <- spTransform(p, crs(ri))
    pri <- rasterize(pi, ri)
    lri <- mask(x = ri, mask = pri)
    names(lri) <- paste0("X", y, m)
    lri[is.na(lri)] <- 0
    lri[is.na(depth)] <- NA
    pred_clipped <- addLayer(pred_clipped, lri)
  }

  file_clipped <- gsub("X", "",
    paste0(gsub("\\.grd$", "", gsub("[0-9-]", "", basename(file_pred))),
           names(pred_clipped)[1], "-",
           names(pred_clipped)[nlayers(pred_clipped)], "_clipped_modis"))
  out_path <- file.path(dir_out, file_clipped)
  writeRaster(pred_clipped, out_path, overwrite = TRUE)
  list(file = out_path, stack = pred_clipped)
}

# Build red-tide polygons from MODIS nFLH --------------------------------

#' Threshold monthly nFLH at 0.02 and dissolve to per-month polygons.
#'
#' @param dir_in  Directory holding the FLH .grd stack(s).
#' @param dir_out Directory to write the FLH-polys Rdata into.
#' @param file_depth Path to depth ASCII (for cropping).
#' @return List with `file` (Rdata path) and `numpolys` (per-month polygon
#'   count diagnostic).
fn.make_nflh_polys <- function(dir_in, dir_out, file_depth) {
  files_flhstack <- list.files(dir_in, pattern = "\\.grd$", full.names = TRUE)
  if (length(files_flhstack) == 0)
    stop("No FLH .grd stacks found in ", dir_in)
  flh <- stack(gsub("\\.grd$", "", files_flhstack))
  flh <- flh / 10
  depth <- raster(file_depth)
  flh <- crop(flh, depth)

  threshold <- 0.02
  flh_polys_out <- list()
  for (i in seq_len(nlayers(flh))) {
    message(names(flh)[i])
    flh_sub <- flh[[i]]
    flh_sub[flh_sub >= threshold] <- 10
    iflh_poly <- rasterToPolygons(flh_sub, n = 16,
                                  function(x) x == 10, dissolve = TRUE)
    flh_lines <- as(iflh_poly, "SpatialLinesDataFrame")
    flh_sflines <- st_as_sf(flh_lines)
    flh_sfunion <- st_union(flh_sflines)
    flh_poly <- st_sf(st_polygonize(flh_sfunion))
    flh_poly <- flh_poly[!st_is_empty(flh_poly), ]
    flh_poly <- st_collection_extract(flh_poly, "POLYGON")
    flh_poly <- st_cast(flh_poly, "POLYGON", group_or_split = TRUE)
    flh_poly$ID <- as.character(seq_len(nrow(flh_poly)))
    flh_polys_out[[i]] <- as(flh_poly, "Spatial")
    names(flh_polys_out)[i] <- names(flh)[i]
    rm(flh_sub, flh_poly, flh_lines); gc()
  }

  flh.polys <- flh_polys_out
  file_flhpolys <- file.path(
    dir_out,
    paste0("FLH polys ",
           substr(basename(files_flhstack),
                  nchar(basename(files_flhstack)) - 18,
                  nchar(basename(files_flhstack)) - 4),
           ".Rdata"))
  save(flh.polys, file = file_flhpolys)

  list(file = file_flhpolys,
       numpolys = data.frame(
         yrmo = names(flh),
         npolys = sapply(seq_along(flh.polys),
                         function(x) length(flh.polys[[x]][[1]]))))
}

# Plot FLH images with overlaid polygons --------------------------------

#' PDF of monthly FLH images with red-tide polygons overlaid.
#'
#' @param dir_in Directory holding the FLH .grd stack.
#' @param file_flhpolys Path to FLH-polys Rdata.
#' @param file_depth Path to depth ASCII.
#' @param dir_out Where to write the PDF.
fn.plot_modis <- function(dir_in, file_flhpolys, file_depth, dir_out = dir_in) {
  files_flhstack <- list.files(dir_in, pattern = "\\.grd$", full.names = TRUE)
  flh <- stack(files_flhstack) / 10
  depth <- raster(file_depth)
  flh <- crop(flh, depth)
  flh_yrs <- sort(unique(as.numeric(substr(names(flh), 2, 5))))

  load(file_flhpolys)

  colv <- c("purple","blue","darkblue","cyan","green","darkgreen","yellow","orange","red","darkred")
  funpal <- colorRampPalette(colv, bias = 2)
  brks <- seq(0, .1, .001)
  color <- funpal(length(brks) - 1)

  pdf_file <- file.path(dir_out,
                        paste0("FLH_", gsub("X", "", names(flh)[1]),
                               "_to_", gsub("X", "", names(flh)[dim(flh)[3]]),
                               "_monthly_with_polygons.pdf"))
  pdf(pdf_file, onefile = TRUE)
  for (y in flh_yrs) {
    yr_idx <- which(as.numeric(substr(names(flh), 2, 5)) == y)
    yr_idx_polys <- which(as.numeric(substr(names(flh.polys), 2, 5)) == y)
    flh_yr <- flh[[yr_idx]]
    poly_yr <- flh.polys[yr_idx_polys]
    par(mfrow = c(4, 3), mar = c(1, 1, 2, 0), oma = c(2, 2, 0, 6))
    for (i in seq_len(nlayers(flh_yr))) {
      plot(flh_yr[[i]], legend = FALSE, col = color, colNA = "black",
           zlim = c(0, .1), breaks = brks,
           main = gsub("X", "", names(flh_yr)[i]), axes = FALSE)
      if (i %in% c(1, 4, 7, 10)) axis(2, at = 24:30, labels = 24:30)
      else axis(2, at = 24:30, labels = NA)
      if (i %in% 10:12) axis(1, at = seq(-88, -81, 2), labels = seq(-88, -81, 2))
      else axis(1, at = seq(-88, -81, 2), labels = NA)
      plot(poly_yr[[i]], add = TRUE, border = "red")
    }
    par(mfrow = c(1, 1), mar = c(0, 0, 0, 0), oma = c(0, 0, 0, 1))
    image.plot(flh_yr, legend.only = TRUE, zlim = c(0, .1), col = color,
               add = TRUE, legend.width = 1, legend.mar = 4, legend.line = 3,
               legend.lab = expression("mW cm"^-2 * " um"^-1 * " sr"^-1))
  }
  dev.off()
  invisible(pdf_file)
}
