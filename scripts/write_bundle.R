# write_bundle.R: the data bundle for WFS-Portal (step 9 of run_redtide_maps.R; issue #23).
#
# fn.write_bundle() writes out/<res>min/bundle/, a tracked, data-only, text-only description of
# the delivered monthly maps: the values of every ASCII file reproduced text for text, a per-month
# summary, the FWC samples, the grid, the display facts of the product and the provenance of the
# run. The folder is specified by docs/issue23_portal-bundle/bundle-schema.md (schema 1.0), which
# the stage writes into the bundle as SCHEMA.md. Everything is written LF through binary
# connections; the stage reads every file back and asserts it is identical to what it computed,
# then swaps the folder into place, so a failure never leaves a half-written bundle.
#
# The stage needs the run on disk (clipping_source.csv, the filtered samples, the stacks, the fit
# record, the nearshore raster, the hull diagnostics are gitignored outputs); it reads the ASCII
# files, not the combined stack, because they are the deliverable and the bundle must reproduce
# their text. Every optional input that is missing leaves NA in the columns derived from it.

# Formatting and writing helpers ------------------------------------------------------------

#' Print doubles with 15 significant digits, or 17 where 15 do not round-trip (schema 3.2).
fn.fmt_num <- function(x) {
  s <- sprintf("%.15g", x)
  bad <- !is.na(x) & is.finite(x) & (suppressWarnings(as.numeric(s)) != x)
  s[bad] <- sprintf("%.17g", x[bad])
  s[is.na(x)] <- NA_character_
  s
}

#' Write a data frame as CSV with LF line ends; quote the character columns only (schema 3.3).
#' Doubles go through fn.fmt_num(); integers and logicals print as they are; NA is the bare token.
#' quote = "character" quotes exactly the columns that are character before formatting;
#' quote = FALSE quotes nothing (the values files).
fn.write_csv_lf <- function(df, file, quote = "character") {
  df <- as.data.frame(df, stringsAsFactors = FALSE)
  is_chr <- vapply(df, is.character, logical(1))
  for (j in seq_along(df)) if (is.double(df[[j]])) df[[j]] <- fn.fmt_num(df[[j]])
  q <- if (identical(quote, "character")) { if (any(is_chr)) which(is_chr) else FALSE } else FALSE
  con <- file(file, open = "wb")
  on.exit(close(con))
  utils::write.csv(df, con, row.names = FALSE, quote = q, na = "NA", eol = "\n")
  invisible(file)
}

#' Write a list as pretty JSON with LF line ends (schema 4.1, 4.2).
fn.write_json_lf <- function(x, file) {
  txt <- jsonlite::toJSON(x, auto_unbox = TRUE, pretty = TRUE, digits = NA, null = "null", na = "null")
  con <- file(file, open = "wb")
  on.exit(close(con))
  writeLines(as.character(txt), con, sep = "\n")
  invisible(file)
}

#' Re-write a text file LF (SCHEMA.md, .gitattributes): never file.copy(), the working tree may be CRLF.
fn.write_text_lf <- function(file_in, file_out, lines = NULL) {
  if (is.null(lines)) lines <- readLines(file_in, warn = FALSE)
  con <- file(file_out, open = "wb")
  on.exit(close(con))
  writeLines(lines, con, sep = "\n")
  invisible(file_out)
}

#' md5 and byte count of each file's content with every carriage return byte removed (schema 4.9).
fn.md5_lf <- function(files) {
  tmp <- tempfile("md5lf_")
  on.exit(unlink(tmp))
  out <- data.frame(bytes = integer(length(files)), md5 = character(length(files)), stringsAsFactors = FALSE)
  for (i in seq_along(files)) {
    raw <- readBin(files[i], what = "raw", n = file.info(files[i])$size)
    raw <- raw[raw != as.raw(13L)]
    writeBin(raw, tmp)
    out$bytes[i] <- length(raw)
    out$md5[i]   <- unname(tools::md5sum(tmp))
  }
  out
}

#' md5 of a character string's ASCII bytes (no separator, no trailing newline).
fn.md5_string <- function(s) {
  tmp <- tempfile("md5s_")
  on.exit(unlink(tmp))
  writeBin(charToRaw(s), tmp)
  unname(tools::md5sum(tmp))
}

#' Stop if any file under dir holds a carriage return (0x0D) or a non-ASCII byte (schema 3.1).
fn.assert_no_cr <- function(dir) {
  files <- list.files(dir, recursive = TRUE, all.files = TRUE, full.names = TRUE, no.. = TRUE)
  for (f in files) {
    raw <- readBin(f, what = "raw", n = file.info(f)$size)
    if (any(raw == as.raw(13L))) stop("Carriage return byte in ", f, call. = FALSE)
    if (any(raw > as.raw(0x7F))) stop("Non-ASCII byte in ", f, call. = FALSE)
  }
  invisible(length(files))
}

#' A path relative to the repository root with "/" separators, or NA when it lies outside it.
fn.rel_to_repo <- function(p, repo_dir) {
  rp <- normalizePath(repo_dir, winslash = "/", mustWork = FALSE)
  p  <- normalizePath(p, winslash = "/", mustWork = FALSE)
  if (startsWith(p, paste0(rp, "/"))) substring(p, nchar(rp) + 2) else NA_character_
}

#' file, bytes, md5 of every file under dir except manifest.csv, paths relative with "/",
#' in C-locale byte order (schema 4.10).
fn.bundle_manifest <- function(dir) {
  files <- list.files(dir, recursive = TRUE, all.files = TRUE, no.. = TRUE)
  files <- sort(setdiff(files, "manifest.csv"), method = "radix")
  m <- fn.md5_lf(file.path(dir, files))
  data.frame(file = files, bytes = m$bytes, md5 = m$md5, stringsAsFactors = FALSE)
}

#' Git state of the maps the bundle encodes (schema 6): head_commit, branch, ascii_commit (the
#' last commit touching ascii_dir), ascii_dirty (that folder modified in the working tree).
#' "unknown" wherever git cannot answer.
fn.git_state <- function(repo_dir, ascii_dir) {
  out <- list(head_commit = "unknown", branch = "unknown", ascii_commit = "unknown", ascii_dirty = NA)
  git <- Sys.which("git")
  run <- function(...) {
    if (!nzchar(git)) return(NULL)
    r <- tryCatch(suppressWarnings(system2(git, c("-C", shQuote(repo_dir), ...), stdout = TRUE, stderr = FALSE)),
                  error = function(e) NULL)
    if (is.null(r) || !is.null(attr(r, "status")) && attr(r, "status") != 0) return(NULL)
    r
  }
  rel <- fn.rel_to_repo(ascii_dir, repo_dir)   # NA when the maps live outside the repository: the ASCII keys stay unknown
  h <- run("rev-parse", "HEAD");               if (length(h) == 1 && grepl("^[0-9a-f]{40}$", h)) out$head_commit <- h
  b <- run("rev-parse", "--abbrev-ref", "HEAD"); if (length(b) == 1 && nzchar(b)) out$branch <- b
  if (!is.na(rel)) {
    a <- run("log", "-1", "--format=%H", "--", shQuote(rel)); if (length(a) == 1 && grepl("^[0-9a-f]{40}$", a)) out$ascii_commit <- a
    d <- run("status", "--porcelain", "--", shQuote(rel)); if (!is.null(d)) out$ascii_dirty <- length(d) > 0
  }
  if (out$head_commit == "unknown") {   # base-R fallback: .git/HEAD and the refs (head_commit and branch only)
    head_file <- file.path(repo_dir, ".git", "HEAD")
    if (file.exists(head_file)) {
      ref <- readLines(head_file, warn = FALSE)[1]
      if (grepl("^ref: ", ref)) {
        out$branch <- sub("^ref: refs/heads/", "", ref)
        rf <- file.path(repo_dir, ".git", sub("^ref: ", "", ref))
        if (file.exists(rf)) out$head_commit <- readLines(rf, warn = FALSE)[1] else {
          pk <- file.path(repo_dir, ".git", "packed-refs")
          if (file.exists(pk)) { l <- grep(paste0(" ", sub("^ref: ", "", ref), "$"), readLines(pk, warn = FALSE), value = TRUE); if (length(l) == 1) out$head_commit <- substr(l, 1, 40) }
        }
      } else if (grepl("^[0-9a-f]{40}$", ref)) out$head_commit <- ref
    }
  }
  out
}

# Reading and computing ---------------------------------------------------------------------

#' Read every monthly ASCII file of a directory as a cell x month matrix (schema 3.5: the text,
#' parsed with scan(); values below -1e30 are the NODATA token). The six header lines are parsed
#' and compared with the template. Returns months, M (NA on land), header, md5 (yrmo, file, bytes, md5).
fn.read_ascii_dir <- function(dir_ascii, file_depth, pattern = "^sdmTMB_log__([0-9]{6})[.]asc$") {
  files <- sort(list.files(dir_ascii, pattern = pattern))
  if (length(files) == 0) stop("No monthly ASCII file in ", dir_ascii, call. = FALSE)
  extra <- setdiff(list.files(dir_ascii, pattern = "[.]asc$"), files)
  if (length(extra)) stop("Unexpected .asc file(s) in ", dir_ascii, ": ", paste(extra, collapse = ", "), call. = FALSE)
  months <- sub(pattern, "\\1", files)
  depth  <- raster::raster(file_depth)
  nc <- raster::ncol(depth); nr <- raster::nrow(depth); n <- raster::ncell(depth)
  land <- is.na(raster::values(depth))
  header <- NULL
  M <- matrix(NA_real_, n, length(months), dimnames = list(NULL, months))
  for (i in seq_along(files)) {
    f <- file.path(dir_ascii, files[i])
    h <- readLines(f, n = 6, warn = FALSE)
    kv <- strsplit(trimws(h), "[[:space:]]+")
    hd <- setNames(vapply(kv, `[`, "", 2), toupper(vapply(kv, `[`, "", 1)))
    if (is.null(header)) header <- hd
    else if (!identical(unname(hd[c("NCOLS", "NROWS", "XLLCORNER", "YLLCORNER", "CELLSIZE")]),
                        unname(header[c("NCOLS", "NROWS", "XLLCORNER", "YLLCORNER", "CELLSIZE")])))
      stop("ASCII header of ", files[i], " differs from ", files[1], call. = FALSE)
    v <- scan(f, what = double(), skip = 6, quiet = TRUE)
    if (length(v) != n) stop(files[i], ": ", length(v), " values, template has ", n, call. = FALSE)
    v[v < -1e30] <- NA
    M[, i] <- v
  }
  if (as.integer(header[["NCOLS"]]) != nc || as.integer(header[["NROWS"]]) != nr ||
      abs(as.numeric(header[["XLLCORNER"]]) - raster::xmin(depth)) > 1e-9 ||
      abs(as.numeric(header[["YLLCORNER"]]) - raster::ymin(depth)) > 1e-9 ||
      abs(as.numeric(header[["CELLSIZE"]]) - raster::xres(depth)) > 1e-12)
    stop("ASCII header does not match the template ", basename(file_depth), call. = FALSE)
  md5 <- fn.md5_lf(file.path(dir_ascii, files))
  list(months = months, M = M, header = header, land = land,
       md5 = data.frame(yrmo = months, file = files, bytes = md5$bytes, md5 = md5$md5, stringsAsFactors = FALSE))
}

#' Read a raster stack as a cell x month matrix, layer names without the X prefix.
fn.read_stack_mat <- function(file, depth) {
  b <- raster::brick(file)
  stopifnot(raster::compareRaster(depth, b))
  m <- raster::values(b); colnames(m) <- sub("^X", "", names(b)); m
}

#' The five bands on the positive values (schema 5.1): c(n_pos, five bands).
fn.band_counts <- function(v, breaks = c(0, 1e3, 1e4, 1e5, 1e6, Inf)) {
  v <- v[!is.na(v) & v > 0]
  k <- cut(v, breaks, labels = FALSE, include.lowest = TRUE)
  c(length(v), tabulate(k, nbins = length(breaks) - 1))
}

#' The map metrics of a cell x month matrix over the data domain (schema 4.7): pure, reused by the
#' check script. `domain` is the logical vector of the cells that carry data (water outside the
#' Atlantic-side box for the red tide bundle).
fn.layer_summary <- function(M, domain, km2, breaks = c(0, 1e3, 1e4, 1e5, 1e6, Inf)) {
  Mw <- M[domain, , drop = FALSE]
  bands <- t(apply(Mw, 2, fn.band_counts, breaks = breaks))
  ge <- function(thr) !is.na(Mw) & Mw >= thr
  mx <- apply(Mw, 2, max, na.rm = TRUE)
  wmx <- apply(Mw, 2, which.max)
  max_cell <- ifelse(mx > 0, which(domain)[wmx], NA_integer_)
  data.frame(exposure  = colSums(Mw, na.rm = TRUE),
             n_pos     = as.integer(bands[, 1]),
             n_le1k    = as.integer(bands[, 2]), n_1k_10k   = as.integer(bands[, 3]),
             n_10k_100k = as.integer(bands[, 4]), n_100k_1M = as.integer(bands[, 5]),
             n_gt1M    = as.integer(bands[, 6]),
             n_ge10k   = as.integer(colSums(ge(1e4))), km2_ge10k = colSums(ge(1e4) * km2[domain]),
             n_ge100k  = as.integer(colSums(ge(1e5))), n_ge1M = as.integer(colSums(ge(1e6))),
             max_cells = as.numeric(mx), max_cell = as.integer(max_cell),
             row.names = NULL, stringsAsFactors = FALSE)
}

#' Cells changed between the delivered map M and the satellite clip S, with the relative
#' tolerance of schema 5.4 (the ASCII text against a float32 stack).
fn.n_changed <- function(M, S, tol = 1e-9) {
  as.integer(colSums(abs(M - S) > tol * pmax(abs(S), 1), na.rm = TRUE))
}

#' The filtered FWC samples of the product months with their template cell (schema 4.8).
fn.samples_table <- function(file_filtered, depth, water, styr, enyr) {
  e <- new.env(); load(file_filtered, envir = e)
  if (!inherits(e$filtered_points_df, "data.frame"))
    stop("fn.write_bundle: ", basename(file_filtered), " holds no filtered_points_df", call. = FALSE)
  pts <- sf::st_drop_geometry(e$filtered_points_df)
  pts <- data.frame(year = as.integer(pts$year), month = as.integer(pts$month),
                    cells = suppressWarnings(as.numeric(pts$cells)),
                    lon = as.numeric(pts$lon), lat = as.numeric(pts$lat), stringsAsFactors = FALSE)
  n_filtered <- nrow(pts)
  pts <- pts[!is.na(pts$cells) & pts$year >= styr & pts$year <= enyr, ]
  pts$cell  <- raster::cellFromXY(depth, cbind(pts$lon, pts$lat))
  pts$water <- ifelse(is.na(pts$cell), NA, water[ifelse(is.na(pts$cell), 1L, pts$cell)])
  pts <- pts[order(pts$year, pts$month, pts$lat, pts$lon, pts$cells), ]
  rownames(pts) <- NULL
  attr(pts, "n_filtered") <- n_filtered
  pts
}

#' The style.json content (schema 4.2): the product facts, with the palette expanded to hex.
fn.bundle_style <- function() {
  anchors <- c("white", "purple", "blue", "darkblue", "cyan", "green", "darkgreen", "yellow", "orange", "red", "darkred")
  cols <- c(grDevices::colorRampPalette(anchors, bias = 2)(401), "darkred")
  hex <- toupper(grDevices::rgb(t(grDevices::col2rgb(cols)), maxColorValue = 255))
  list(schema_version = "1.0", units = "cells/L",
       palette = list(type = "ramp", anchors = anchors, bias = 2,
                      breaks = list(zero = 0, first_colored = 10000, step = 10000, last = 4000000),
                      above = "darkred", colors_hex = hex),
       bands = list(breaks = list(0, 1000, 10000, 100000, 1000000, "Inf"), right_closed = TRUE,
                    columns = c("n_le1k", "n_1k_10k", "n_10k_100k", "n_100k_1M", "n_gt1M"),
                    sample_columns = c("s_le1k", "s_1k_10k", "s_10k_100k", "s_100k_1M", "s_gt1M"),
                    labels = c("<= 1k", "1k to 10k", "10k to 100k", "100k to 1M", "> 1M")),
       codes = list(use = list(hybrid = "VIIRS clip, hull footprint added inside the nearshore set",
                               viirs = "VIIRS clip",
                               hybrid_modis = "MODIS clip, hull footprint added inside the nearshore set",
                               modis = "MODIS clip",
                               pred = "hull-clipped prediction (no satellite coverage)"),
                    fit_status = list(fitted = "a model was fit", failed = "the fit failed (all-zero layer)",
                                      none = "no fit attempted"),
                    viirs_status = list(positive = "VIIRS layer with detections", zero = "VIIRS layer, no detection",
                                        missing = "inside the VIIRS era, tif missing",
                                        no_coverage = "outside the VIIRS era")))
}

# The stage ----------------------------------------------------------------------------------

#' Write the data bundle of the delivered maps (schema 1.0).
#'
#' @param dir_ascii       paths$ecospace: the monthly ASCII files, the source of the values.
#' @param file_depth      paths$file_depth: the template (land, centers, km2, the grid header).
#' @param file_clipsrc    out/<res>min/clipped/clipping_source.csv (use, hybrid_changed).
#' @param file_filtered   the filtered FWC samples (*_filtered.Rdata).
#' @param dir_out         paths$bundle. The stage writes <dir_out>_tmp and swaps it into place.
#' @param cfg, res, repo_dir  the pipeline configuration (meta$cfg, meta$build$toggles), the
#'   resolution in arcmin, the repository root (git state).
#' @param file_schema     docs/issue23_portal-bundle/bundle-schema.md, re-written LF as SCHEMA.md.
#' @param file_mask       the nearshore raster (grid$nearshore); NULL when both rules are "none".
#' @param file_unclip     the unclipped prediction stack (fit_status).
#' @param file_fitmat     RT_fit_matrix.RData (converged).
#' @param file_viirs_raw  the raw VIIRS stack (viirs_status); NULL when use_viirs is FALSE.
#' @param file_viirs_clip, file_modis_clip  the VIIRS- and MODIS-clipped stacks (n_changed).
#' @param file_hulldiag   sdm/hull_diagnostics.csv (hull_span_km, hull_flagged).
#' @param file_combined   the combined stack: compared with the ASCII (all.equal), never read from.
#' @param file_log        the run log (meta$build$run_log); NULL for a standalone call.
#' @param mode            "pipeline" (step 9 of a run) or "standalone" (called from the console).
#' @return invisible list: bundle_id, dir, n_months, n_placeholder, n_months_pos, n_samples,
#'   samples_to, n_files, bytes, ascii_commit, ascii_dirty, seconds, summary, manifest.
fn.write_bundle <- function(dir_ascii, file_depth, file_clipsrc, file_filtered, dir_out,
                            cfg, res, repo_dir, file_schema,
                            file_mask = NULL, file_unclip = NULL, file_fitmat = NULL,
                            file_viirs_raw = NULL, file_viirs_clip = NULL, file_modis_clip = NULL,
                            file_hulldiag = NULL, file_combined = NULL, file_log = NULL,
                            mode = c("pipeline", "standalone"),
                            product = "redtide", product_name = "Red Tide Maps", layer = "redtide",
                            schema_version = "1.0") {
  t0 <- Sys.time()
  mode <- match.arg(mode)
  res  <- as.integer(res)
  bundle_id <- paste0(product, "_", res, "min")
  opt <- function(f) !is.null(f) && file.exists(f) || (!is.null(f) && file.exists(paste0(f, ".grd")))
  for (f in c(dir_ascii, file_depth, file_clipsrc, file_filtered, file_schema))
    if (!file.exists(f)) stop("fn.write_bundle: missing ", f, call. = FALSE)

  # The template and the grid ---------------------------------------------------------------
  depth <- raster::raster(file_depth)
  nc <- raster::ncol(depth); nr <- raster::nrow(depth); n <- raster::ncell(depth)
  dv <- raster::values(depth); land <- is.na(dv); water <- !land
  km2 <- raster::values(raster::area(depth))
  xy  <- raster::xyFromCell(depth, seq_len(n))
  atl <- xy[, 1] > -82 & xy[, 2] > 28.5
  domain <- water & !atl   # the cells that carry data: the Atlantic-side box is treated as land for every value and metric (D19)
  ext <- as.vector(raster::extent(depth))   # xmin, xmax, ymin, ymax
  grid <- data.frame(cell = seq_len(n),
                     row = as.integer(raster::rowFromCell(depth, seq_len(n))), col = as.integer(raster::colFromCell(depth, seq_len(n))),
                     lon = xy[, 1], lat = xy[, 2], water = water, domain = domain, km2 = km2,
                     depth_m = ifelse(land, NA_real_, dv), stringsAsFactors = FALSE)
  nearshore <- NULL
  if (!is.null(file_mask) && opt(file_mask)) {
    mr <- raster::raster(if (file.exists(file_mask)) file_mask else paste0(file_mask, ".grd"))
    stopifnot(raster::compareRaster(depth, mr))
    mv <- raster::values(mr)
    if (!all(is.na(mv) == land) || !all(mv[water] %in% c(0, 1)) || any(atl & mv %in% 1))
      stop("The nearshore raster is not NA exactly on land, 0 or 1 on water, outside the Atlantic box.", call. = FALSE)
    grid$nearshore <- ifelse(land, NA, mv == 1)
    nearshore <- list(rule = sub("^nearshore_mask_", "", sub("[.]grd$", "", basename(file_mask))),
                      n_cells = sum(mv %in% 1), km2 = round(sum(km2[mv %in% 1])))
  }
  grid$atlantic <- atl

  # The maps: the ASCII text ------------------------------------------------------------------
  A <- fn.read_ascii_dir(dir_ascii, file_depth)
  months <- A$months; M <- A$M
  n_years <- as.integer(cfg$enyr) - as.integer(cfg$styr) + 1L
  if (length(months) != 12L * n_years) stop(length(months), " ASCII files; the configuration asks for ", 12L * n_years, call. = FALSE)
  exp_months <- sprintf("%04d%02d", rep(as.integer(cfg$styr):as.integer(cfg$enyr), each = 12), 1:12)
  if (!identical(months, exp_months)) stop("The ASCII months are not the contiguous months ", exp_months[1], " to ", exp_months[length(exp_months)], call. = FALSE)
  if (!all(is.na(M) == land)) stop("An ASCII file is NA somewhere other than the template land.", call. = FALSE)
  if (!all(is.finite(M[water, ])) || any(M[water, ] < 0)) stop("A water cell is not finite and >= 0.", call. = FALSE)
  n_box_pos <- sum(M[water & atl, ] > 0, na.rm = TRUE)   # what the delivered maps carry in the box (reported, then dropped)
  M[!domain, ] <- NA   # the box carries no data in the bundle (D19)
  if (!is.null(file_combined) && opt(file_combined)) {
    Cm <- fn.read_stack_mat(file_combined, depth)
    if (!identical(colnames(Cm), months)) stop("The combined stack has other months than the ASCII files.", call. = FALSE)
    Cm[is.na(Cm)] <- 0; Cm[!domain, ] <- NA
    for (m in months) if (!isTRUE(all.equal(unname(M[, m]), unname(Cm[, m]))))
      stop("ASCII and combined stack differ beyond tolerance in ", m, call. = FALSE)
    rm(Cm)
  }

  # The clip source and the optional run outputs ---------------------------------------------
  clipsrc <- utils::read.csv(file_clipsrc, stringsAsFactors = FALSE)
  clipsrc$yrmo <- sub("^X", "", clipsrc$yrmo)
  if (!setequal(clipsrc$yrmo, months)) stop("clipping_source.csv does not hold the ASCII months.", call. = FALSE)
  j <- match(months, clipsrc$yrmo)
  use <- clipsrc$use[j]; hybrid_changed <- as.logical(clipsrc$hybrid_changed[j])
  if (!all(use %in% c("hybrid", "viirs", "hybrid_modis", "modis", "pred"))) stop("Unknown use value in clipping_source.csv", call. = FALSE)
  # The nearshore facts must be the run's: hybrid months need the set, and the set's rule must be a configured one.
  rules <- c(cfg$viirs_nearshore, cfg$modis_nearshore)
  if (is.null(nearshore) && any(use %in% c("hybrid", "hybrid_modis")))
    stop("clipping_source.csv has hybrid months but no nearshore raster was supplied (file_mask).", call. = FALSE)
  if (!is.null(nearshore) && !(nearshore$rule %in% setdiff(rules, "none")))
    stop("The nearshore raster is rule \"", nearshore$rule, "\" but the configuration names ", paste(rules, collapse = " / "), ".", call. = FALSE)

  # Cells the nearshore rule changed, per sensor: a hybrid month without its clipped stack stays NA;
  # the viirs / modis / pred months are 0 by definition once any clipped stack is at hand.
  n_changed <- rep(NA_integer_, length(months))
  norm <- function(X) { X[is.na(X)] <- 0; X[!domain, ] <- NA; X }
  has_v <- !is.null(file_viirs_clip) && opt(file_viirs_clip); has_m <- !is.null(file_modis_clip) && opt(file_modis_clip)
  if (has_v || has_m) n_changed[use %in% c("viirs", "modis", "pred")] <- 0L
  if (has_v) { Vc <- norm(fn.read_stack_mat(file_viirs_clip, depth)); mv <- months[use == "hybrid"]
    if (length(mv)) n_changed[use == "hybrid"] <- fn.n_changed(M[, mv, drop = FALSE], Vc[, mv, drop = FALSE]); rm(Vc) }
  if (has_m) { Mc <- norm(fn.read_stack_mat(file_modis_clip, depth)); mm <- months[use == "hybrid_modis"]
    if (length(mm)) n_changed[use == "hybrid_modis"] <- fn.n_changed(M[, mm, drop = FALSE], Mc[, mm, drop = FALSE]); rm(Mc) }
  hull_span_km <- rep(NA_real_, length(months)); hull_flagged <- rep(NA, length(months))
  if (!is.null(file_hulldiag) && file.exists(file_hulldiag)) {
    hd <- utils::read.csv(file_hulldiag, colClasses = c(yrmo = "character"), stringsAsFactors = FALSE)
    k <- match(months, hd$yrmo)
    hull_span_km <- as.numeric(hd$max_span_km[k])
    hull_flagged <- ifelse(is.na(k), NA, as.logical(hd$flagged[k]) & use == "pred")
  }
  fit_status <- rep(NA_character_, length(months))
  if (!is.null(file_unclip) && opt(file_unclip)) {
    U <- fn.read_stack_mat(file_unclip, depth); U[land, ] <- NA   # the prediction grid carries land values; the status is read on water, as #18 does
    fit_status <- vapply(months, function(m) {
      if (!(m %in% colnames(U))) return("none")
      v <- U[, m]; if (all(is.na(v))) "none" else if (max(v, na.rm = TRUE) == 0) "failed" else "fitted" }, character(1))
    rm(U)
  }
  converged <- rep(NA, length(months))
  if (!is.null(file_fitmat) && file.exists(file_fitmat)) {
    e <- new.env(); load(file_fitmat, envir = e)
    if (is.null(e$fit_matrix)) stop("fn.write_bundle: ", basename(file_fitmat), " holds no fit_matrix", call. = FALSE)
    fm <- as.data.frame(e$fit_matrix, stringsAsFactors = FALSE)
    fm <- fm[!is.na(fm$model) & fm$model == "fit_sdmTMBlog", ]
    fm$yrmo <- sprintf("%04d%02d", as.integer(fm$year), as.integer(fm$month))
    k <- match(months, fm$yrmo)
    cv <- fm$convergence[k]
    converged <- ifelse(is.na(cv) | !(cv %in% c("TRUE", "FALSE")), NA, cv == "TRUE")
  }
  viirs_status <- rep(NA_character_, length(months))
  if (!is.null(file_viirs_raw) && opt(file_viirs_raw)) {
    Vr <- raster::brick(if (file.exists(file_viirs_raw)) file_viirs_raw else paste0(file_viirs_raw, ".grd"))
    vm <- sub("^X", "", names(Vr))
    npos <- colSums(raster::values(Vr) > 0, na.rm = TRUE)
    era <- range(vm)
    viirs_status <- vapply(months, function(m) {
      if (m %in% vm) { if (npos[[match(m, vm)]] > 0) "positive" else "zero" }
      else if (m >= era[1] && m <= era[2]) "missing" else "no_coverage" }, character(1))
    rm(Vr)
  }

  # The samples -----------------------------------------------------------------------------
  pts <- fn.samples_table(file_filtered, depth, water, as.integer(cfg$styr), as.integer(cfg$enyr))
  if (nrow(pts) == 0) stop("fn.write_bundle: no FWC sample with a count in ", cfg$styr, "-", cfg$enyr,
                           " (the red tide bundle carries samples; schema 4.1).", call. = FALSE)
  pts$yrmo <- sprintf("%04d%02d", pts$year, pts$month)
  ymf <- factor(pts$yrmo, levels = months)
  cnt <- function(sel) as.integer(table(ymf[sel]))
  on_water <- !is.na(pts$cell) & domain[ifelse(is.na(pts$cell), 1L, pts$cell)]   # a domain cell; the pipeline keeps no sample in the box
  pos <- pts$cells > 0
  sb <- cut(pts$cells[pos], c(0, 1e3, 1e4, 1e5, 1e6, Inf), labels = FALSE, include.lowest = TRUE)
  s_band <- t(sapply(1:5, function(b) { sel <- rep(FALSE, nrow(pts)); sel[which(pos)[sb == b]] <- TRUE; cnt(sel) }))
  ge10k <- on_water & pts$cells >= 1e4
  inside <- rep(FALSE, nrow(pts)); inside[ge10k] <- M[cbind(pts$cell[ge10k], match(pts$yrmo[ge10k], months))] > 0
  last_data <- if (nrow(pts)) max(pts$yrmo) else months[length(months)]
  placeholder <- months > last_data
  rng <- regmatches(basename(file_filtered), regexpr("[0-9]{8}-[0-9]{8}", basename(file_filtered)))
  as_date <- function(s) paste0(substr(s, 1, 4), "-", substr(s, 5, 6), "-", substr(s, 7, 8))

  # The summary ------------------------------------------------------------------------------
  ls <- fn.layer_summary(M, domain, km2)
  summ <- data.frame(yrmo = months, year = as.integer(substr(months, 1, 4)), month = as.integer(substr(months, 5, 6)),
                     use = use, hybrid_changed = hybrid_changed, n_changed = n_changed,
                     hull_span_km = hull_span_km, hull_flagged = hull_flagged,
                     fit_status = fit_status, converged = converged, viirs_status = viirs_status,
                     n_samples = cnt(rep(TRUE, nrow(pts))), n_samples_water = cnt(on_water), n_samples_pos = cnt(pos),
                     s_le1k = s_band[1, ], s_1k_10k = s_band[2, ], s_10k_100k = s_band[3, ], s_100k_1M = s_band[4, ], s_gt1M = s_band[5, ],
                     samples_ge10k = cnt(ge10k), in_ge10k = cnt(inside),
                     stringsAsFactors = FALSE)
  summ <- cbind(summ, ls)
  rownames(summ) <- NULL
  if (!all(rowSums(summ[, c("n_le1k", "n_1k_10k", "n_10k_100k", "n_100k_1M", "n_gt1M")]) == summ$n_pos)) stop("Bands do not sum to n_pos.", call. = FALSE)
  if (!all(rowSums(summ[, c("s_le1k", "s_1k_10k", "s_10k_100k", "s_100k_1M", "s_gt1M")]) == summ$n_samples_pos)) stop("Sample bands do not sum to n_samples_pos.", call. = FALSE)
  if (any(summ$hull_flagged %in% TRUE & summ$use != "pred")) stop("hull_flagged TRUE in a satellite month.", call. = FALSE)
  exact10k <- sum(M[domain, ] == 1e4, na.rm = TRUE)
  if (exact10k > 0) message("Note: ", exact10k, " cell-month(s) are exactly 10,000 cells/L (band 1k to 10k, counted in n_ge10k).")
  if (n_box_pos > 0) message("Note: the delivered maps carry ", n_box_pos, " positive cell-month(s) in the Atlantic-side box; the bundle carries no data there (D19).")

  # The tables -------------------------------------------------------------------------------
  months_df <- data.frame(yrmo = months, year = summ$year, month = summ$month, index = seq_along(months),
                          label = paste0(substr(months, 1, 4), "-", substr(months, 5, 6)), placeholder = placeholder,
                          stringsAsFactors = FALSE)
  layers_df <- data.frame(id = layer, name = "Karenia brevis cell concentration, delivered map", units = "cells/L",
                          encoding = "long_sparse", file_pattern = paste0("values/", layer, "/<yyyy>.csv"),
                          summary_file = paste0("summary/", layer, ".csv"), total_column = "exposure", fill = 0,
                          precision = "15 significant digits, 17 where 15 do not round-trip",
                          description = paste0("sdmTMB prediction clipped by the VIIRS / MODIS / hull cascade with the nearshore hybrid, rule ",
                                               if (is.null(nearshore)) "none" else nearshore$rule),
                          stringsAsFactors = FALSE)
  pos_idx <- which(!is.na(M) & M > 0, arr.ind = TRUE)
  values_df <- data.frame(yrmo = months[pos_idx[, 2]], cell = as.integer(pos_idx[, 1]), value = M[pos_idx], stringsAsFactors = FALSE)
  values_df <- values_df[order(values_df$yrmo, values_df$cell), ]; rownames(values_df) <- NULL
  samples_df <- pts[, c("year", "month", "cells", "lon", "lat", "cell", "water")]
  samples_df$cell <- as.integer(samples_df$cell); rownames(samples_df) <- NULL
  years <- as.integer(cfg$styr):as.integer(cfg$enyr)

  # The metadata -----------------------------------------------------------------------------
  gs <- fn.git_state(repo_dir, dir_ascii)
  ascii_md5_all <- fn.md5_string(paste0(A$md5$md5, collapse = ""))
  rel_ascii <- fn.rel_to_repo(dir_ascii, repo_dir); if (is.na(rel_ascii)) rel_ascii <- paste0("out/", res, "min/ecospace_ascii")   # never a machine path
  rel_template <- fn.rel_to_repo(file_depth, repo_dir); if (is.na(rel_template)) rel_template <- basename(file_depth)
  cfg_keys <- c("res", "styr", "enyr", "hull_link_km", "hull_buffer_km", "hull_min_pts", "hull_concavity",
                "hull_warn_span_km", "viirs_nearshore", "modis_nearshore", "use_viirs", "use_modis")
  tog_keys <- c("update_modis", "rebuild_nflh", "fwc_refresh", "fwc_force_full", "incremental_fit", "fit_nb", "export_ecospace", "write_bundle")
  pick <- function(keys) { out <- list(); for (k in keys) out[[k]] <- if (is.null(cfg[[k]])) NA else cfg[[k]]; out }
  use_counts <- as.list(table(factor(use, levels = c("hybrid", "viirs", "hybrid_modis", "modis", "pred"))))
  use_counts <- lapply(use_counts, as.integer)
  meta <- list(
    schema_version = schema_version,
    bundle_id = bundle_id, product = product, product_name = product_name, res_arcmin = res,
    grid = list(ncols = nc, nrows = nr,
                xllcorner = as.numeric(A$header[["XLLCORNER"]]), yllcorner = as.numeric(A$header[["YLLCORNER"]]),
                cellsize = as.numeric(A$header[["CELLSIZE"]]), nodata = as.numeric(A$header[["NODATA_VALUE"]]),
                crs = "EPSG:4326", extent = ext, n_cells = n, n_water = sum(water), n_domain = sum(domain),
                domain_rule = "the cells that carry data: water cells outside the Atlantic-side box, which is treated as land",
                cell_order = "row-major from the northwest corner: cell = (row - 1) * ncols + col, the raster package numbering and the ASCII token order",
                template = rel_template,
                atlantic_box = list(lon_gt = -82, lat_gt = 28.5)),
    months = list(first = months[1], last = months[length(months)], n = length(months),
                  last_data = last_data, n_placeholder = sum(placeholder)),
    samples = list(file_pattern = "samples/fwc_<yyyy>.csv",
                   source = "FWC GIS Open Data, Harmful Algal Bloom (HAB) Events layers (ArcGIS REST services)",
                   file = basename(file_filtered),
                   date_from = if (length(rng)) as_date(substr(rng, 1, 8)) else NA, date_to = if (length(rng)) as_date(substr(rng, 10, 17)) else NA,
                   n_rows_filtered = attr(pts, "n_filtered"), n_rows_bundle = nrow(pts), last_month = last_data,
                   coordinate_note = "exact doubles of the pipeline (6-decimal source values, about half stored one ulp off, printed with 17 digits where needed); cell is computed from them"),
    nearshore = nearshore,
    clipping = c(use_counts, list(hybrid_changed = sum(hybrid_changed), hull_flagged = sum(hull_flagged %in% TRUE))),
    source = list(repo = "https://github.com/WFS-FEM/RedTideMaps", branch = gs$branch,
                  ascii_dir = rel_ascii,
                  ascii_commit = gs$ascii_commit, ascii_dirty = gs$ascii_dirty, ascii_md5 = ascii_md5_all,
                  head_commit = gs$head_commit,
                  schema_url = if (gs$head_commit == "unknown") NULL else
                    paste0("https://github.com/WFS-FEM/RedTideMaps/blob/", gs$head_commit, "/docs/issue23_portal-bundle/bundle-schema.md")),
    build = list(built_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
                 r_version = paste(R.version$major, R.version$minor, sep = "."),
                 raster_version = utils::packageDescription("raster")$Version,
                 writer = "scripts/write_bundle.R",
                 run_log = if (is.null(file_log)) NULL else basename(file_log), mode = mode,
                 toggles = pick(tog_keys)),
    cfg = pick(cfg_keys))

  # Writing, into a temporary folder ----------------------------------------------------------
  dir_tmp <- paste0(dir_out, "_tmp"); dir_old <- paste0(dir_out, "_old")
  if (dir.exists(dir_old)) stop("A leftover ", dir_old, " exists; delete it before writing the bundle.", call. = FALSE)
  if (dir.exists(dir_tmp) && unlink(dir_tmp, recursive = TRUE) != 0 || dir.exists(dir_tmp))
    stop("Cannot remove ", dir_tmp, " (a file in it may be open).", call. = FALSE)
  for (d in c(dir_tmp, file.path(dir_tmp, "values", layer), file.path(dir_tmp, "summary"), file.path(dir_tmp, "samples")))
    dir.create(d, recursive = TRUE, showWarnings = FALSE)
  fn.write_text_lf(NULL, file.path(dir_tmp, ".gitattributes"), lines = "* text eol=lf")
  fn.write_text_lf(file_schema, file.path(dir_tmp, "SCHEMA.md"))
  fn.write_csv_lf(grid,      file.path(dir_tmp, "grid.csv"))
  fn.write_csv_lf(months_df, file.path(dir_tmp, "months.csv"))
  fn.write_csv_lf(layers_df, file.path(dir_tmp, "layers.csv"))
  for (y in years) {
    fn.write_csv_lf(values_df[values_df$yrmo >= sprintf("%04d01", y) & values_df$yrmo <= sprintf("%04d12", y), ],
                    file.path(dir_tmp, "values", layer, paste0(y, ".csv")), quote = FALSE)
    fn.write_csv_lf(samples_df[samples_df$year == y, ], file.path(dir_tmp, "samples", paste0("fwc_", y, ".csv")))
  }
  fn.write_csv_lf(summ,   file.path(dir_tmp, "summary", paste0(layer, ".csv")))
  fn.write_csv_lf(A$md5,  file.path(dir_tmp, "ascii_md5.csv"))
  fn.write_json_lf(fn.bundle_style(), file.path(dir_tmp, "style.json"))
  fn.write_json_lf(meta, file.path(dir_tmp, "meta.json"))
  manifest <- fn.bundle_manifest(dir_tmp)
  fn.write_csv_lf(manifest, file.path(dir_tmp, "manifest.csv"))

  # Read-back: every table identical to what was computed, no CR byte ---------------------------
  rb <- function(file, classes) { d <- utils::read.csv(file, colClasses = classes, stringsAsFactors = FALSE); rownames(d) <- NULL; d }
  same <- function(a, b, what) if (!identical(a, b)) stop("Read-back differs: ", what, call. = FALSE)
  cls_grid <- c(cell = "integer", row = "integer", col = "integer", lon = "numeric", lat = "numeric", water = "logical", domain = "logical", km2 = "numeric", depth_m = "numeric", nearshore = "logical", atlantic = "logical")
  same(rb(file.path(dir_tmp, "grid.csv"), cls_grid[names(grid)]), grid, "grid.csv")
  same(rb(file.path(dir_tmp, "months.csv"), c(yrmo = "character", year = "integer", month = "integer", index = "integer", label = "character", placeholder = "logical")), months_df, "months.csv")
  same(rb(file.path(dir_tmp, "layers.csv"), c(rep("character", 7), "numeric", "character", "character")), layers_df, "layers.csv")
  cls_summ <- c(yrmo = "character", year = "integer", month = "integer", use = "character", hybrid_changed = "logical", n_changed = "integer",
                hull_span_km = "numeric", hull_flagged = "logical", fit_status = "character", converged = "logical", viirs_status = "character",
                n_samples = "integer", n_samples_water = "integer", n_samples_pos = "integer",
                s_le1k = "integer", s_1k_10k = "integer", s_10k_100k = "integer", s_100k_1M = "integer", s_gt1M = "integer",
                samples_ge10k = "integer", in_ge10k = "integer", exposure = "numeric", n_pos = "integer",
                n_le1k = "integer", n_1k_10k = "integer", n_10k_100k = "integer", n_100k_1M = "integer", n_gt1M = "integer",
                n_ge10k = "integer", km2_ge10k = "numeric", n_ge100k = "integer", n_ge1M = "integer", max_cells = "numeric", max_cell = "integer")
  same(rb(file.path(dir_tmp, "summary", paste0(layer, ".csv")), cls_summ), summ, paste0("summary/", layer, ".csv"))
  same(rb(file.path(dir_tmp, "ascii_md5.csv"), c(yrmo = "character", file = "character", bytes = "integer", md5 = "character")), A$md5, "ascii_md5.csv")
  vb <- do.call(rbind, lapply(years, function(y) rb(file.path(dir_tmp, "values", layer, paste0(y, ".csv")), c(yrmo = "character", cell = "integer", value = "numeric"))))
  rownames(vb) <- NULL
  same(vb, values_df, "values/")
  Mb <- matrix(0, n, length(months), dimnames = list(NULL, months)); Mb[!domain, ] <- NA
  Mb[cbind(vb$cell, match(vb$yrmo, months))] <- vb$value
  same(Mb, M, "the values matrix rebuilt from the year files")
  sbk <- do.call(rbind, lapply(years, function(y) rb(file.path(dir_tmp, "samples", paste0("fwc_", y, ".csv")), c(year = "integer", month = "integer", cells = "numeric", lon = "numeric", lat = "numeric", cell = "integer", water = "logical"))))
  rownames(sbk) <- NULL
  same(sbk, samples_df, "samples/")
  invisible(jsonlite::fromJSON(file.path(dir_tmp, "meta.json"))); invisible(jsonlite::fromJSON(file.path(dir_tmp, "style.json")))
  mf <- rb(file.path(dir_tmp, "manifest.csv"), c(file = "character", bytes = "integer", md5 = "character"))
  same(mf, manifest, "manifest.csv")
  if (!(".gitattributes" %in% mf$file)) stop("manifest.csv does not list .gitattributes", call. = FALSE)
  fn.assert_no_cr(dir_tmp)

  # The swap ---------------------------------------------------------------------------------
  if (dir.exists(dir_out)) {
    if (!file.rename(dir_out, dir_old)) stop("Cannot move ", dir_out, " aside (a file in it may be open).", call. = FALSE)
  }
  if (!file.rename(dir_tmp, dir_out)) {
    if (dir.exists(dir_old) && !dir.exists(dir_out)) file.rename(dir_old, dir_out)   # put the previous bundle back
    stop("Cannot rename ", dir_tmp, " to ", dir_out, " (a file may be open); the previous bundle was restored.", call. = FALSE)
  }
  if (dir.exists(dir_old) && (unlink(dir_old, recursive = TRUE) != 0 || dir.exists(dir_old)))
    warning("The previous bundle could not be deleted; remove ", dir_old, " by hand (it is never tracked).", call. = FALSE)

  secs <- as.numeric(difftime(Sys.time(), t0, units = "secs"))
  invisible(list(bundle_id = bundle_id, dir = dir_out, n_months = length(months), n_placeholder = sum(placeholder),
                 n_months_pos = sum(summ$n_pos > 0), n_domain = sum(domain), n_box_pos = n_box_pos,
                 n_samples = nrow(pts), samples_to = meta$samples$date_to,
                 n_files = nrow(manifest) + 1L, bytes = sum(manifest$bytes) + file.info(file.path(dir_out, "manifest.csv"))$size,
                 ascii_commit = gs$ascii_commit, ascii_dirty = gs$ascii_dirty, seconds = secs,
                 summary = summ, manifest = manifest))
}
