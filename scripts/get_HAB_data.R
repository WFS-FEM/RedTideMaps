#' Ingest, filter, and plot HAB cell-count data.
#'
#' This file provides three functions used at the front of the workflow:
#'   - fn.get_fwc_data()    : pull FWC HAB samples from the ArcGIS REST
#'                            endpoints, write merged CSV + Rdata.
#'   - fn.filter_hab_data() : spatially filter observations to the WFS grid
#'                            and build supporting land/excl polygons.
#'   - fn.plot_hab_data()   : QA plots of sampling effort.
#'
#' All functions take explicit args and return explicit objects. No <<-
#' superassignment and no setwd() side effects.

# Get HAB data from FWC --------------------------------------------------

# Canonical column order for the merged HAB CSV (matches the
# Historic_*.csv / Recent_*.csv schema).
.FWC_COLS <- c("X","Y","OBJECTID","SAMPLE_DATE","TIME","TIMEZONE","DEPTH",
               "LOCATION","LATITUDE","LONGITUDE","NAME","COUNT_","HAB_ID")

#' Internal: paginate an ArcGIS REST endpoint and return a data.frame
#' with the canonical FWC HAB schema. SAMPLE_DATE is returned as Date.
#'
#' @param url Base endpoint URL (existing query string is ignored).
#' @param since Optional Date. If supplied, only fetch records with
#'   SAMPLE_DATE >= since.
#' @param page_size ArcGIS REST page size (the server caps at 2000).
#' @return data.frame with columns `.FWC_COLS` (missing cols filled NA).
#' @keywords internal
.fwc_fetch_endpoint <- function(url, since = NULL, page_size = 2000) {
  base_url <- sub("\\?.*$", "", url)
  where <- if (is.null(since)) "1=1" else
    sprintf("SAMPLE_DATE >= timestamp '%s 00:00:00'", format(since, "%Y-%m-%d"))

  pages <- list()
  offset <- 0L
  repeat {
    resp <- httr::GET(base_url, query = list(
      where             = where,
      outFields         = "*",
      outSR             = "4326",
      resultOffset      = offset,
      resultRecordCount = page_size,
      f                 = "json"))
    if (httr::status_code(resp) != 200)
      stop("FWC API request failed (HTTP ", httr::status_code(resp), "): ", base_url)
    d <- jsonlite::fromJSON(httr::content(resp, "text", encoding = "UTF-8"),
                            simplifyVector = FALSE)
    if (!is.null(d$error))
      stop("FWC API error: ", d$error$message %||% "unknown")
    if (is.null(d$features) || length(d$features) == 0) break
    pages[[length(pages) + 1L]] <- d$features
    if (!isTRUE(d$exceededTransferLimit)) break
    offset <- offset + page_size
  }

  feats <- unlist(pages, recursive = FALSE)
  if (length(feats) == 0) {
    out <- as.data.frame(matrix(NA, nrow = 0, ncol = length(.FWC_COLS)))
    names(out) <- .FWC_COLS
    return(out)
  }

  attrs <- do.call(rbind, lapply(feats, function(f)
    as.data.frame(lapply(f$attributes, function(x) if (is.null(x)) NA else x),
                  stringsAsFactors = FALSE)))
  geoms <- do.call(rbind, lapply(feats, function(f) {
    g <- f$geometry
    data.frame(X = if (is.null(g$x)) NA_real_ else g$x,
               Y = if (is.null(g$y)) NA_real_ else g$y)
  }))
  df <- cbind(geoms, attrs)

  if ("SAMPLE_DATE" %in% names(df)) {
    df$SAMPLE_DATE <- as.Date(as.POSIXct(as.numeric(df$SAMPLE_DATE) / 1000,
                                         origin = "1970-01-01", tz = "UTC"))
  }

  for (col in setdiff(.FWC_COLS, names(df))) df[[col]] <- NA
  df[, .FWC_COLS, drop = FALSE]
}

# Small null-coalescing helper used above
`%||%` <- function(a, b) if (is.null(a)) b else a

#' Pull FWC HAB cell-count data from the ArcGIS REST endpoints.
#'
#' First run (or `force_full = TRUE`): fetches every endpoint listed in
#' `urls_file` and assembles the full dataset.
#'
#' Subsequent runs: reads the existing `FWC HAB data *.csv` in `dir_data`,
#' takes the max(SAMPLE_DATE), and re-queries only the live endpoint
#' (the one whose URL contains "Recent_") for records on or after that
#' date. New records are appended and de-duplicated on
#' (HAB_ID, OBJECTID, SAMPLE_DATE, LATITUDE, LONGITUDE).
#'
#' Output: a merged CSV + Rdata named with the observed date range. The
#' Rdata holds a single object `hab.out` (matches what fn.filter_hab_data
#' expects). Older merged copies are deleted.
#'
#' @param dir_data Directory where the merged CSV/Rdata lives.
#' @param urls_file Path to the URL list (one endpoint per line, blanks
#'   and '#' comments ignored).
#' @param force_full If TRUE, ignore any local CSV and do a full pull.
#' @return list(csv, rdata) with the written file paths.
fn.get_fwc_data <- function(dir_data, urls_file, force_full = FALSE) {
  if (!file.exists(urls_file))
    stop("URL file not found: ", urls_file)
  urls <- trimws(readLines(urls_file, warn = FALSE))
  urls <- urls[nzchar(urls) & !startsWith(urls, "#")]
  if (length(urls) == 0)
    stop("No URLs in ", urls_file)

  file_curr <- list.files(dir_data, pattern = "^FWC HAB.*\\.csv$", full.names = TRUE)
  have_existing <- length(file_curr) > 0 && !force_full

  if (have_existing) {
    file_in <- file_curr[which.max(file.mtime(file_curr))]
    message("Loading existing merged file: ", basename(file_in))
    hab_existing <- read.csv(file_in)
    hab_existing$SAMPLE_DATE <- as.Date(hab_existing$SAMPLE_DATE)
    last_date <- max(hab_existing$SAMPLE_DATE, na.rm = TRUE)
    message("Last SAMPLE_DATE in local data: ", last_date)

    recent_urls <- urls[grepl("Recent_", urls)]
    if (length(recent_urls) == 0) {
      message("No Recent_ endpoint found in URLs; nothing to update.")
      hab_out <- hab_existing
    } else {
      new_chunks <- list()
      for (u in recent_urls) {
        label <- sub(".*/services/(.*?)/MapServer.*", "\\1", u)
        message("Fetching incremental from: ", label)
        df_new <- .fwc_fetch_endpoint(u, since = last_date)
        message("  + ", nrow(df_new), " records on/after ", last_date)
        new_chunks[[length(new_chunks) + 1L]] <- df_new
      }
      hab_new <- do.call(rbind, new_chunks)
      hab_out <- rbind(hab_existing[, .FWC_COLS, drop = FALSE],
                       hab_new[,      .FWC_COLS, drop = FALSE])
    }
  } else {
    chunks <- list()
    for (u in urls) {
      label <- sub(".*/services/(.*?)/MapServer.*", "\\1", u)
      message("Fetching: ", label)
      df_u <- .fwc_fetch_endpoint(u)
      message("  + ", nrow(df_u), " records")
      chunks[[length(chunks) + 1L]] <- df_u
    }
    hab_out <- do.call(rbind, chunks)
  }

  # De-dupe on the natural key.
  hab_out <- hab_out[!duplicated(hab_out[, c("HAB_ID","OBJECTID","SAMPLE_DATE",
                                             "LATITUDE","LONGITUDE")]), ]
  hab_out <- hab_out[order(hab_out$SAMPLE_DATE, hab_out$OBJECTID), ]

  suffx     <- paste(gsub("-", "", range(hab_out$SAMPLE_DATE, na.rm = TRUE)), collapse = "-")
  file_fwc  <- file.path(dir_data, paste0("FWC HAB data ", suffx, ".csv"))
  file_rdat <- gsub("\\.csv$", ".Rdata", file_fwc)

  write.csv(hab_out, file_fwc, row.names = FALSE)
  # Save under the legacy variable name `hab.out` for downstream load().
  hab.out <- hab_out
  save(hab.out, file = file_rdat)

  for (old in setdiff(file_curr, file_fwc)) {
    unlink(old)
    unlink(gsub("\\.csv$", ".Rdata", old))
  }

  message("Wrote ", basename(file_fwc), " (", nrow(hab_out), " records, ",
          format(min(hab_out$SAMPLE_DATE, na.rm = TRUE)), " to ",
          format(max(hab_out$SAMPLE_DATE, na.rm = TRUE)), ")")
  list(csv = file_fwc, rdata = file_rdat)
}

# Get HAB data from HABSOS ------------------------------------------------

#' Download the most recent HABSOS CSV archive from NOAA NCEI.
#'
#' @param url_habsos NCEI HABSOS archive URL.
#' @param dir_data Local directory to write the CSV into.
#' @return Path(s) to the downloaded CSV file(s).
fn.get_habsos_data <- function(url_habsos = "https://www.ncei.noaa.gov/data/oceans/archive/arc0069/0120767/",
                               dir_data) {
  web_page <- read_html(url_habsos)
  links <- web_page |> html_nodes("a") |> html_attr("href")
  xml_files <- links[grepl("\\.xml$", links)]
  cat("List of .xml files in the directory:\n"); print(xml_files)

  latest_xml <- tail(sort(xml_files), 1)
  data_version <- substr(gsub("\\.xml$", "", latest_xml),
                         nchar(gsub("\\.xml$", "", latest_xml)) - 2,
                         nchar(gsub("\\.xml$", "", latest_xml)))

  data_url <- paste0(url_habsos, data_version, "/data/0-data/")
  web_page <- read_html(data_url)
  links <- web_page |> html_nodes("a") |> html_attr("href")
  csv_files <- links[grepl("\\.csv$", links)]
  cat("List of .csv files in the directory:\n"); print(csv_files)

  if (all(csv_files %in% list.files(dir_data))) {
    message("File(s) already exist in ", dir_data, ". Download skipped.")
    return(file.path(dir_data, csv_files))
  }

  out <- character()
  for (csv in csv_files) {
    dest <- file.path(dir_data, csv)
    download.file(url = paste0(data_url, csv), destfile = dest, mode = "wb")
    cat("File downloaded successfully to\n", dest, "\n")
    out <- c(out, dest)
  }
  out
}

# Filter HAB data --------------------------------------------------------

#' Spatially filter HAB observations to the WFS Ecospace grid.
#'
#' Builds polygons for the U.S. landmass, an Atlantic exclusion box, and
#' the depth-excluded cells, then drops any observation falling inside
#' the union.
#'
#' @param file_hab   Path to merged FWC or HABSOS .Rdata.
#' @param file_depth Path to the depth template ASCII for the target res.
#' @param file_excl  Path to the exclusion template ASCII for the target res.
#' @param dir_out    Directory to write the *_filtered.Rdata into.
#' @return A list with:
#'   - file: path to the filtered .Rdata,
#'   - points: filtered_points_df (sf with lon/lat/year/month/cells),
#'   - inside_polygons: per-point logical matrix from st_within,
#'   - land_polygons: U.S. coastline polygons clipped to depth extent.
fn.filter_hab_data <- function(file_hab, file_depth, file_excl, dir_out) {
  file_out <- file.path(dir_out,
                        gsub("\\.Rdata$", "_filtered.Rdata", basename(file_hab)))

  depth <- raster(file_depth)
  load(file_hab)  # provides hab.out
  df <- hab.out
  names(df) <- tolower(names(df))

  if (startsWith(tolower(basename(file_hab)), "habsos")) {
    df$sample_date <- as.Date(df$sample_date)
    df$year  <- as.numeric(format(df$sample_date, "%Y"))
    df$month <- as.numeric(format(df$sample_date, "%m"))
    df <- df[, tolower(c("LATITUDE", "LONGITUDE", "year", "CELLCOUNT", "month"))]
    colnames(df) <- c("lat", "lon", "year", "cells", "month")
  } else if (startsWith(tolower(basename(file_hab)), "fwc")) {
    df$sample_date <- as.Date(df$sample_date)
    df$year  <- as.numeric(format(df$sample_date, "%Y"))
    df$month <- as.numeric(format(df$sample_date, "%m"))
    df <- df[, tolower(c("latitude", "longitude", "year", "month", "count_"))]
    colnames(df) <- c("lat", "lon", "year", "month", "cells")
  } else {
    stop("Unrecognized HAB source: ", basename(file_hab))
  }
  df <- df[complete.cases(df[, 1:2]), ]
  obs_sf <- st_as_sf(df, coords = c("lon", "lat"), crs = st_crs(depth))

  # Build polygons we want to exclude (land + Atlantic side + deep cells)
  excl_raster <- raster(file_excl)
  us <- ne_countries(country = "united states of america",
                     scale = "medium", returnclass = "sf")
  us <- us["geometry"]
  us_bbox <- st_as_sfc(st_bbox(depth))
  us_cropped <- st_cast(st_crop(us, us_bbox), "POLYGON")

  depth_extent <- st_as_sf(st_as_sfc(st_bbox(depth)))
  excl_sf <- st_as_sf(rasterToPolygons(excl_raster, dissolve = TRUE))

  us_clipped_sf <- st_intersection(us_cropped, depth_extent)

  # Atlantic-side exclusion box (NE of FL peninsula).
  atl_coords <- matrix(c(-82, 28.5,
                         -80.5, 28.5,
                         -80.5, 31,
                         -82, 31,
                         -82, 28.5),
                       ncol = 2, byrow = TRUE)
  atl_sf <- st_sf(geometry = st_sfc(st_polygon(list(atl_coords))),
                  crs = st_crs(depth))

  us_clipped_sf <- st_transform(us_clipped_sf, st_crs(depth))
  excl_sf       <- st_transform(excl_sf,       st_crs(depth))
  atl_sf        <- st_transform(atl_sf,        st_crs(depth))

  us_clipped_sf <- st_make_valid(us_clipped_sf)
  us_clipped_sf_polygons <- st_cast(us_clipped_sf, "POLYGON")

  all_polys <- st_union(us_clipped_sf, atl_sf)
  all_polys <- st_union(all_polys, excl_sf)
  all_polys <- st_cast(st_combine(all_polys), "POLYGON")

  # Drop observations falling inside any exclusion polygon
  inside_polygons <- st_within(obs_sf, all_polys, sparse = FALSE)
  filtered <- obs_sf[!apply(inside_polygons, 1, any), ]

  # Crop to depth raster bbox
  bbox_raster <- st_bbox(st_as_sfc(st_bbox(depth)))
  filtered <- st_crop(filtered, bbox_raster)

  filtered_points_df <- cbind(filtered, st_coordinates(filtered))
  names(filtered_points_df) <- c("year", "month", "cells", "lon", "lat", "geometry")

  save(filtered_points_df, file = file_out)
  message(basename(file_out), " saved to ", dir_out)

  list(
    file            = file_out,
    points          = filtered_points_df,
    inside_polygons = inside_polygons,
    land_polygons   = us_clipped_sf_polygons
  )
}

# Plot HAB data ----------------------------------------------------------

#' Plot annual sampling locations and the monthly sample count time series.
#'
#' @param points sf data frame of filtered observations (output of fn.filter_hab_data).
#' @param land_polygons sf POLYGONs of clipped U.S. coastline (same source).
#' @param dir_out Directory to write the two PNGs into.
#' @param min_year Earliest year to include in the per-year facets.
#' @return Invisibly returns the paths of the PNGs written.
fn.plot_hab_data <- function(points, land_polygons, dir_out, min_year = 1985) {
  habdata <- points

  p1 <- ggplot() +
    geom_sf(data = st_as_sf(land_polygons),
            fill = "lightgrey", color = "black", alpha = 0.5) +
    geom_sf(data = subset(habdata, year >= min_year),
            aes(geometry = geometry), color = "blue", size = 0.5, alpha = 0.5) +
    labs(x = "longitude", y = "latitude") +
    theme_minimal() +
    scale_y_continuous(breaks = c(30, 28, 26)) +
    scale_x_continuous(breaks = c(-86, -84, -82)) +
    facet_wrap(~year, ncol = 8)
  f1 <- file.path(dir_out, "sample locations by year.png")
  png(f1, width = 12, height = 10, units = "in", res = 300); print(p1); dev.off()

  sampling_effort <- as.data.frame(habdata)
  full_dates <- data.frame(
    date = seq(as.Date("1985-01-01"),
               as.Date(paste(max(sampling_effort$year), 12, "01", sep = "-")),
               by = "month")
  )
  sampling_effort$date <- as.Date(paste(sampling_effort$year,
                                        sampling_effort$month, "01", sep = "-"))
  monthly_counts <- as.data.frame(table(sampling_effort$date))
  colnames(monthly_counts) <- c("date", "n")
  monthly_counts$date <- as.Date(monthly_counts$date)
  plot_data <- merge(full_dates, monthly_counts, by = "date", all.x = TRUE)
  plot_data$n[is.na(plot_data$n)] <- 0

  p2 <- ggplot(plot_data, aes(x = date, y = n)) +
    geom_line() +
    labs(x = "time", y = "n samples") +
    theme_minimal()
  f2 <- file.path(dir_out, "N samples over time.png")
  png(f2, width = 7, height = 7, units = "in", res = 300); print(p2); dev.off()

  invisible(c(f1, f2))
}
