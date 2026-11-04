#' Issue #23: checks of the data bundle for WFS-Portal (out/<res>min/bundle/, schema 1.0).
#'
#' Reads only what the last pipeline run left on disk (out/<res>min/), the tracked #18 tables
#' and the bundle; writes its tables and figures byte-identically on rerun (no RNG, no dates in
#' the CSVs). It never sources the driver: cfg comes from the bundle's own meta.json.
#'
#' Run from the repo root:
#'   RT_QA_STAGE=frozen Rscript docs/issue23_portal-bundle/check_bundle_issue23.R   (default stage)
#'   RT_QA_STAGE=rerun  Rscript docs/issue23_portal-bundle/check_bundle_issue23.R
#'   RT_QA_RES=15          check out/15min/ (the #18 class-count and record tables exist at 5 arcmin only)
#'   RT_QA_BUNDLE_DIR=dir  check a bundle other than out/<res>min/bundle (step 2: hoard/trial/bundle)
#'
#' Stage frozen: (1) the gate: the maps on disk are the delivered ones of the #18 refresh run (a
#' line-ending-independent digest of the ASCII files, frozen below; the raw md5s of the #18 refresh
#' table reported as a fact); (2) the files against the manifest, the git blobs where the bundle is
#' tracked and the working copy equals HEAD, no carriage return or non-ASCII byte, the ASCII md5
#' guard, the grid and the depths against the template, the nearshore cells against the #18 set
#' table, the layers, the months, the style; (3) the values rebuilt from the year files against the
#' ASCII text (identical), the GDAL float32 reading and the combined stack (per-cell relative
#' tolerance 1e-9), and the key metrics recomputed here without the writer's code; (4) at 5 arcmin
#' behind the gate, the summary against clip_class_counts_hybrid_issue18.csv in all months: the
#' bundle counts the Gulf domain only (D19) and the #18 table every water cell, so the bundle plus
#' the Atlantic-box contribution recomputed from the ASCII must equal the table; (5) the threshold
#' metrics against record_months_issue18.csv in the 502 months the October refresh did not change;
#' (6) the samples against the filtered file the bundle names; (7) the frozen counts of the run of
#' 23 October 2026 and the two figures, drawn from the bundle's own files.
#' Stage rerun: fn.write_bundle(mode = "standalone") into hoard/rerun/bundle with the cfg and the
#' inputs the bundle under check names; every file byte-identical except the volatile keys.
#'
#' Output (docs/issue23_portal-bundle/): tables/bundle_vs_issue18_issue23.csv and
#'   tables/bundle_vs_record_issue23.csv (5 arcmin, behind the gate), tables/bundle_files<res>_issue23.csv,
#'   tables/bundle_rerun<res>_issue23.csv (stage rerun); figures/fig1_bundle_quicklook<res>_issue23.png,
#'   figures/fig2_summary_record<res>_issue23.png; the console.

# Repo root: the working directory if it holds the .Rproj, else two levels above this script.
.root <- local({
  if (file.exists("RedTideMaps.Rproj")) return(normalizePath(getwd(), winslash = "/"))
  f <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE))
  if (length(f) == 1) {
    d <- normalizePath(file.path(dirname(f), "..", ".."), winslash = "/", mustWork = FALSE)
    if (file.exists(file.path(d, "RedTideMaps.Rproj"))) return(d)
  }
  stop("Run from the repo root: Rscript docs/issue23_portal-bundle/check_bundle_issue23.R", call. = FALSE)
})
source(file.path(.root, "scripts", "_setup.R"))        # raster, sf, jsonlite, ...
source(file.path(.root, "scripts", "write_bundle.R"))  # fn.read_ascii_dir, fn.md5_lf, fn.md5_string, fn.rel_to_repo, fn.write_bundle

stage <- Sys.getenv("RT_QA_STAGE", "frozen")
res   <- suppressWarnings(as.integer(Sys.getenv("RT_QA_RES", "5")))
if (!stage %in% c("frozen", "rerun")) stop("RT_QA_STAGE must be frozen or rerun", call. = FALSE)
if (!res %in% c(5L, 15L)) stop("RT_QA_RES must be 5 or 15.", call. = FALSE)

# Frozen facts of the delivered maps (the #18 refresh run of 23 October 2026): the LF digest of the
# ASCII files (meta.source.ascii_md5 of a bundle written from them), by resolution.
frozen_ascii_md5 <- c(`5` = "2a2d8e68d311fe3dc2a0a3f29b1c26d6", `15` = "45e1549f8bdfc5a0f5e2c00bb8cbb4dc")

# Paths ------------------------------------------------------------------------------------------
dir_docs <- file.path(.root, "docs", "issue23_portal-bundle")
dir_tab  <- file.path(dir_docs, "tables"); dir_fig <- file.path(dir_docs, "figures")
for (d in c(dir_tab, dir_fig)) dir.create(d, recursive = TRUE, showWarnings = FALSE)
dir_out     <- file.path(.root, "out", paste0(res, "min"))
dir_ascii   <- file.path(dir_out, "ecospace_ascii")
dir_sdm     <- file.path(dir_out, "sdm")
dir_clipped <- file.path(dir_out, "clipped")
dir_comb    <- file.path(dir_out, "combined")
dir_bundle_tracked <- file.path(dir_out, "bundle")
dir_bundle  <- Sys.getenv("RT_QA_BUNDLE_DIR", dir_bundle_tracked)
if (!dir.exists(dir_bundle)) stop("No bundle at ", dir_bundle, call. = FALSE)
for (d in c(paste0(dir_bundle_tracked, "_tmp"), paste0(dir_bundle_tracked, "_old")))
  if (dir.exists(d)) stop("A leftover ", d, " exists; the writer did not finish its swap. Delete it first.", call. = FALSE)
dir_sub18 <- file.path(.root, "docs", "issue5_nearshore-hybrid-summary", "subissues", "issue18_implement-hybrid-clipping", "tables")
opt_file <- function(dir, pattern, what) {   # NULL when absent (the writer treats it as optional), stop on more than one
  f <- list.files(dir, pattern = pattern, full.names = TRUE)
  if (length(f) > 1) stop("More than one ", what, " in ", dir, ": ", paste(basename(f), collapse = ", "), call. = FALSE)
  if (length(f) == 1) f else NULL
}
one_file <- function(dir, pattern, what) { f <- opt_file(dir, pattern, what); if (is.null(f)) stop("No ", what, " in ", dir, "; run the pipeline first.", call. = FALSE); f }
grd  <- function(f) if (is.null(f)) NULL else sub("[.]grd$", "", f)
file_depth   <- one_file(file.path(.root, "template rasters"), paste0("^depth ", res, "min .*[.]asc$"), "depth template")
file_clipsrc <- file.path(dir_clipped, "clipping_source.csv")
file_comb    <- grd(one_file(dir_comb, "_clipped_combined[.]grd$", "combined stack"))
file_unclip  <- grd(opt_file(dir_sdm, "^sdmTMB_log_stack_[0-9]{6}-[0-9]{6}[.]grd$", "unclipped stack"))
file_viirs   <- grd(opt_file(dir_clipped, "_clipped_viirs[.]grd$", "VIIRS-clipped stack"))
file_modis   <- grd(opt_file(dir_clipped, "_clipped_modis[.]grd$", "MODIS-clipped stack"))
file_fitmat  <- file.path(dir_sdm, "RT_fit_matrix.RData");   if (!file.exists(file_fitmat)) file_fitmat <- NULL
file_hulldiag <- file.path(dir_sdm, "hull_diagnostics.csv"); if (!file.exists(file_hulldiag)) file_hulldiag <- NULL
if (!file.exists(file_clipsrc)) stop("Missing ", file_clipsrc, "; run the pipeline first.", call. = FALSE)

# The bundle ------------------------------------------------------------------------------------
rd <- function(f, classes = NA) utils::read.csv(file.path(dir_bundle, f), colClasses = classes, stringsAsFactors = FALSE)
meta   <- jsonlite::fromJSON(file.path(dir_bundle, "meta.json"), simplifyVector = TRUE)
style  <- jsonlite::fromJSON(file.path(dir_bundle, "style.json"), simplifyVector = TRUE)
grid   <- rd("grid.csv")
months <- rd("months.csv", c(yrmo = "character"))
layers <- rd("layers.csv")
summ   <- rd(file.path("summary", "redtide.csv"), c(yrmo = "character"))
amd5   <- rd("ascii_md5.csv", c(yrmo = "character"))
manif  <- rd("manifest.csv")
key    <- months$yrmo
stopifnot(identical(summ$yrmo, key), identical(amd5$yrmo, key))
cfg <- c(meta$cfg, meta$build$toggles)
years <- as.integer(cfg$styr):as.integer(cfg$enyr)
file_mask <- if (is.null(meta$nearshore)) NULL else file.path(dir_clipped, paste0("nearshore_mask_", meta$nearshore$rule))
file_viirs_raw <- if (isTRUE(cfg$use_viirs)) grd(one_file(file.path(.root, "VIIRS"), "^VIIRS_[0-9]{6}-[0-9]{6}[.]grd$", "VIIRS stack")) else NULL
# The samples file the bundle names (meta.samples.file); the newest *_filtered.Rdata when it is gone.
file_filtered <- file.path(dir_sdm, meta$samples$file)
if (!file.exists(file_filtered)) {
  ff <- list.files(dir_sdm, pattern = "_filtered[.]Rdata$", full.names = TRUE)
  if (length(ff) == 0) stop("No *_filtered.Rdata in ", dir_sdm, call. = FALSE)
  ff_end <- as.integer(substr(regmatches(basename(ff), regexpr("[0-9]{8}_filtered", basename(ff))), 1, 8))
  file_filtered <- ff[which.max(ff_end)]
  message("The bundle's samples file ", meta$samples$file, " is not on disk; using the newest, ", basename(file_filtered))
}
message("Bundle: ", dir_bundle, "\nSamples: ", basename(file_filtered))
cat("\n=== stage ", stage, ", ", res, " arcmin, schema ", meta$schema_version, ", ", meta$bundle_id, ", built ", meta$build$built_at,
    " (", meta$build$mode, "), ASCII commit ", substr(meta$source$ascii_commit, 1, 7), " ===\n", sep = "")

# The template, the ASCII text --------------------------------------------------------------------
depth <- raster::raster(file_depth)
dv <- raster::values(depth); land <- is.na(dv); water <- !land
xy  <- raster::xyFromCell(depth, seq_len(raster::ncell(depth)))
atl <- xy[, 1] > -82 & xy[, 2] > 28.5
domain <- water & !atl; box <- water & atl
km2 <- raster::values(raster::area(depth))
nc <- raster::ncol(depth); nr <- raster::nrow(depth); n5 <- raster::ncell(depth)
A <- fn.read_ascii_dir(dir_ascii, file_depth)         # the text, NA on land
stopifnot(identical(A$months, key))
Mt <- A$M; Mt[!domain, ] <- NA                          # the text on the domain: what the bundle must reproduce
pass <- function(ok, msg) { if (!isTRUE(ok)) stop("FAIL: ", msg, call. = FALSE); cat("  ok  ", msg, "\n") }
rel_tol <- function(a, b, tol = 1e-9) identical(is.na(a), is.na(b)) && (all(is.na(a)) || max(abs(a - b) / pmax(abs(b), 1), na.rm = TRUE) <= tol)
git <- Sys.which("git")
git_run <- function(...) { if (!nzchar(git)) return(NULL); r <- suppressWarnings(system2(git, c("-C", shQuote(.root), ...), stdout = TRUE, stderr = FALSE)); if (!is.null(attr(r, "status")) && attr(r, "status") != 0) NULL else r }
bands_of <- function(v) { v <- v[!is.na(v) & v > 0]; c(length(v), tabulate(cut(v, c(0, 1e3, 1e4, 1e5, 1e6, Inf), labels = FALSE, include.lowest = TRUE), 5)) }
file_files <- file.path(dir_tab, sprintf("bundle_files%d_issue23.csv", res))
file_rerun <- file.path(dir_tab, sprintf("bundle_rerun%d_issue23.csv", res))
file_fig1  <- file.path(dir_fig, sprintf("fig1_bundle_quicklook%d_issue23.png", res))
file_fig2  <- file.path(dir_fig, sprintf("fig2_summary_record%d_issue23.png", res))

# Stage frozen ------------------------------------------------------------------------------------
if (stage == "frozen") {

  # 1. The gate: the maps on disk are the delivered ones of the #18 refresh run.
  cat("1. gate\n")
  ascii_md5_lf <- fn.md5_string(paste0(A$md5$md5, collapse = ""))
  frozen <- identical(ascii_md5_lf, unname(frozen_ascii_md5[as.character(res)]))
  f18 <- file.path(dir_sub18, sprintf("md5_refresh%d_issue18.csv", res))
  if (file.exists(f18)) {
    md5ref <- utils::read.csv(f18, colClasses = c(yrmo = "character"), stringsAsFactors = FALSE)
    raw <- unname(tools::md5sum(file.path(dir_ascii, A$md5$file)))
    raw_eq <- setequal(md5ref$yrmo, key) && all(raw == md5ref$md5_now[match(key, md5ref$yrmo)])
    cat(sprintf("  --   raw md5 of the working-tree ASCII files %s tables/%s (a CRLF checkout differs from an LF one here)\n", if (raw_eq) "equals" else "differs from", basename(f18)))
  }
  cat(if (frozen) "  --   the LF digest of the ASCII files equals the frozen digest of the #18 refresh run: the delivered maps; the #18 comparisons run\n"
      else "  --   the LF digest of the ASCII files differs from the frozen digest: a later run; the #18 comparisons (4, 5, 7) do not run\n")
  if (!frozen) for (f in c("bundle_vs_issue18_issue23.csv", "bundle_vs_record_issue23.csv")) if (file.exists(file.path(dir_tab, f))) { unlink(file.path(dir_tab, f)); cat("  --   removed the stale ", f, "\n", sep = "") }

  # 2. Files, md5s, bytes, the grid, the layers, the months, the style.
  cat("2. files\n")
  files_disk <- sort(setdiff(list.files(dir_bundle, recursive = TRUE, all.files = TRUE, no.. = TRUE), "manifest.csv"), method = "radix")
  pass(identical(files_disk, manif$file), paste0("the file set equals manifest.csv (", nrow(manif), " files listed plus the manifest; .gitattributes included; C-locale order)"))
  md5_disk <- fn.md5_lf(file.path(dir_bundle, manif$file))
  raw_md5  <- unname(tools::md5sum(file.path(dir_bundle, manif$file)))
  pass(all(raw_md5 == manif$md5) && all(md5_disk$md5 == manif$md5) && all(md5_disk$bytes == manif$bytes), "every md5 and byte count equals the manifest (the files are LF on disk)")
  fn.assert_no_cr(dir_bundle); cat("  ok   no carriage return or non-ASCII byte in any file\n")
  rel_bundle <- fn.rel_to_repo(dir_bundle, .root)
  at_head <- if (is.na(rel_bundle)) NULL else git_run("ls-tree", "-r", "--name-only", "HEAD", "--", shQuote(rel_bundle))
  if (length(at_head)) {
    dirty <- git_run("status", "--porcelain", "--", shQuote(rel_bundle))
    if (length(dirty)) cat("  --   the bundle differs from HEAD (a later run not yet committed); the git blob comparison is skipped\n") else {
      blob_md5 <- vapply(manif$file, function(f) {
        tmp <- tempfile(); on.exit(unlink(tmp))
        st <- suppressWarnings(system2(git, c("-C", shQuote(.root), "show", shQuote(paste0("HEAD:", rel_bundle, "/", f))), stdout = tmp, stderr = FALSE))
        if (st != 0) stop("git show failed for ", f, call. = FALSE)
        unname(tools::md5sum(tmp)) }, character(1))
      pass(all(blob_md5 == manif$md5), "every md5 equals the git blob at HEAD (the tracked copy)")
    }
  } else cat("  --   the bundle is not tracked at HEAD (no git blob comparison)\n")
  amd5_now <- fn.md5_lf(file.path(dir_ascii, A$md5$file))
  pass(identical(amd5$file, A$md5$file) && all(amd5$md5 == amd5_now$md5) && all(amd5$bytes == amd5_now$bytes),
       "ascii_md5.csv equals the LF md5 and byte count of the ASCII files on disk (the staleness guard)")
  pass(meta$source$ascii_md5 == ascii_md5_lf, "meta.source.ascii_md5 is the md5 of the concatenated month md5s")
  hd <- A$header
  pass(meta$grid$ncols == nc && meta$grid$nrows == nr && meta$grid$n_cells == n5 && meta$grid$n_water == sum(water) && meta$grid$n_domain == sum(domain) &&
       meta$grid$xllcorner == as.numeric(hd[["XLLCORNER"]]) && meta$grid$cellsize == as.numeric(hd[["CELLSIZE"]]) &&
       isTRUE(all.equal(meta$grid$extent, as.vector(raster::extent(depth)))),
       sprintf("meta.grid equals the template header: %d x %d, %d cells, %d water, %d domain", nc, nr, n5, sum(water), sum(domain)))
  pass(nrow(grid) == n5 && identical(grid$cell, seq_len(n5)) && identical(grid$water, water) && identical(grid$domain, domain) &&
       identical(grid$atlantic, atl) && isTRUE(all.equal(grid$km2, km2)) && identical(grid$lon, xy[, 1]) && identical(grid$lat, xy[, 2]) &&
       identical(grid$depth_m, ifelse(land, NA_real_, dv)) &&
       identical(grid$row, as.integer(raster::rowFromCell(depth, seq_len(n5)))) && identical(grid$col, as.integer(raster::colFromCell(depth, seq_len(n5)))),
       sprintf("grid.csv: cells, rows, columns, centers, depths, water, domain (%d), atlantic (%d water cells in the box), km2 equal the template", sum(domain), sum(box)))
  if (!is.null(file_mask)) {
    mr <- raster::raster(file_mask); mv <- raster::values(mr)
    pass(identical(grid$nearshore, ifelse(land, NA, mv == 1)) && !any(grid$nearshore %in% TRUE & atl), sprintf("grid.csv nearshore equals the run's %s raster (%d cells, none in the box)", meta$nearshore$rule, sum(mv %in% 1)))
    fset <- file.path(dir_sub18, sprintf("nearshore_set%d_issue18.csv", res))
    if (file.exists(fset)) { set18 <- utils::read.csv(fset); pass(setequal(which(grid$nearshore %in% TRUE), set18$cell), sprintf("the nearshore cells equal tables/%s", basename(fset))) }
  }
  pass(nrow(layers) == 1 && layers$id == "redtide" && layers$encoding == "long_sparse" && layers$total_column == "exposure" && layers$fill == 0 &&
       layers$summary_file == "summary/redtide.csv" && layers$file_pattern == "values/redtide/<yyyy>.csv" && file.exists(file.path(dir_bundle, layers$summary_file)) &&
       all(file.exists(file.path(dir_bundle, "values", "redtide", paste0(years, ".csv")))) && all(file.exists(file.path(dir_bundle, "samples", paste0("fwc_", years, ".csv")))),
       "layers.csv: one layer, redtide, long_sparse, total column exposure; the values and samples files of every year exist")
  exp_months <- sprintf("%04d%02d", rep(years, each = 12), 1:12)
  pass(identical(key, exp_months) && identical(months$index, seq_along(key)) && identical(months$label, paste0(substr(key, 1, 4), "-", substr(key, 5, 6))) &&
       identical(months$year, as.integer(substr(key, 1, 4))) && identical(months$month, as.integer(substr(key, 5, 6))),
       sprintf("months.csv: %d contiguous months %s to %s, year and month as the key", length(key), key[1], key[length(key)]))
  pass(all(style$bands$columns %in% names(summ)) && all(style$bands$sample_columns %in% names(summ)) && identical(style$bands$labels, c("<= 1k", "1k to 10k", "10k to 100k", "100k to 1M", "> 1M")) &&
       length(style$palette$colors_hex) == 402 && identical(as.numeric(style$bands$breaks), c(0, 1e3, 1e4, 1e5, 1e6, Inf)) && style$units == "cells/L",
       "style.json: the band columns exist in the summary, the labels in k and M, 402 palette colors, the band breaks")

  # 3. The values and the summary against the ASCII text, the float32 readings, the combined stack, and this script's own arithmetic.
  cat("3. values\n")
  vals <- do.call(rbind, lapply(years, function(y) rd(file.path("values", "redtide", paste0(y, ".csv")), c(yrmo = "character", cell = "integer", value = "numeric"))))
  Mb <- matrix(0, n5, length(key), dimnames = list(NULL, key)); Mb[!domain, ] <- NA
  Mb[cbind(vals$cell, match(vals$yrmo, key))] <- vals$value
  pass(identical(Mb, Mt), sprintf("the values rebuilt from the %d year files are identical to the ASCII text on the domain (%d rows)", length(years), nrow(vals)))
  pass(all(domain[vals$cell]) && !anyDuplicated(paste(vals$yrmo, vals$cell)) && all(vals$value > 0) && !is.unsorted(order(vals$yrmo, vals$cell)),
       "every row is a domain cell, unique within its month, strictly positive, sorted by month then cell")
  rb_ok <- TRUE; cm_ok <- TRUE
  Cm <- fn.read_stack_mat(file_comb, depth); Cm[is.na(Cm)] <- 0; Cm[!domain, ] <- NA
  for (m in key) {
    a <- raster::values(raster::raster(file.path(dir_ascii, paste0("sdmTMB_log__", m, ".asc")))); a[!is.na(a) & a < -1e30] <- NA; a[!domain] <- NA
    if (!rel_tol(unname(Mb[, m]), unname(a))) rb_ok <- FALSE
    if (!rel_tol(unname(Mb[, m]), unname(Cm[, m]))) cm_ok <- FALSE
  }
  rm(Cm)
  pass(rb_ok && cm_ok, "within a relative 1e-9 of every cell of the GDAL float32 reading of the ASCII files and of the combined stack")
  Md <- A$M[domain, , drop = FALSE]
  bd <- t(apply(Md, 2, bands_of))
  own <- data.frame(exposure = colSums(Md), n_pos = bd[, 1], n_le1k = bd[, 2], n_1k_10k = bd[, 3], n_10k_100k = bd[, 4], n_100k_1M = bd[, 5], n_gt1M = bd[, 6],
                    n_ge10k = colSums(Md >= 1e4), km2_ge10k = colSums((Md >= 1e4) * km2[domain]), n_ge100k = colSums(Md >= 1e5), n_ge1M = colSums(Md >= 1e6),
                    max_cells = apply(Md, 2, max))
  own$max_cell <- ifelse(own$max_cells > 0, which(domain)[apply(Md, 2, which.max)], NA_integer_)
  cnt_cols <- c("n_pos", "n_le1k", "n_1k_10k", "n_10k_100k", "n_100k_1M", "n_gt1M", "n_ge10k", "n_ge100k", "n_ge1M", "max_cell")
  pass(all(sapply(cnt_cols, function(k) identical(as.integer(own[[k]]), as.integer(summ[[k]])))) && rel_tol(summ$exposure, own$exposure) &&
       rel_tol(summ$km2_ge10k, own$km2_ge10k) && rel_tol(summ$max_cells, own$max_cells),
       "the key metrics recomputed here from the ASCII text (colSums, cut, the thresholds, the maximum) equal the summary in every month")
  pass(all(rowSums(summ[, c("n_le1k", "n_1k_10k", "n_10k_100k", "n_100k_1M", "n_gt1M")]) == summ$n_pos) && sum(summ$n_pos) == nrow(vals),
       "the bands sum to n_pos and n_pos sums to the value rows")

  # The Atlantic-box contribution the delivered maps carry (D19: not in the bundle; added back for the #18 tables).
  Bx <- A$M[box, , drop = FALSE]
  bb <- t(apply(Bx, 2, bands_of))
  boxc <- data.frame(yrmo = key, box_exposure = colSums(Bx, na.rm = TRUE), box_n_pos = bb[, 1], box_n_le1k = bb[, 2], box_n_1k_10k = bb[, 3],
                     box_n_10k_100k = bb[, 4], box_n_100k_1M = bb[, 5], box_n_gt1M = bb[, 6],
                     box_n_ge10k = colSums(!is.na(Bx) & Bx >= 1e4), box_km2_ge10k = colSums((!is.na(Bx) & Bx >= 1e4) * km2[box]),
                     box_n_ge100k = colSums(!is.na(Bx) & Bx >= 1e5), box_n_ge1M = colSums(!is.na(Bx) & Bx >= 1e6),
                     box_max_cells = apply(Bx, 2, max, na.rm = TRUE), stringsAsFactors = FALSE)
  cat(sprintf("  --   the delivered maps carry positive cells in the Atlantic-side box in %d months (%d positive cell-months, %.2f%% of the record's exposure); the bundle leaves them out (D19)\n",
              sum(boxc$box_n_pos > 0), sum(boxc$box_n_pos), 100 * sum(boxc$box_exposure) / (sum(summ$exposure) + sum(boxc$box_exposure))))

  # 4. The summary against the #18 class-count table (every water cell): bundle + box.
  if (frozen && res == 5L) {
    cat("4. summary vs clip_class_counts_hybrid_issue18.csv\n")
    t18 <- utils::read.csv(file.path(dir_sub18, "clip_class_counts_hybrid_issue18.csv"), colClasses = c(yrmo = "character"), stringsAsFactors = FALSE)
    j <- match(key, t18$yrmo); stopifnot(!anyNA(j)); t18 <- t18[j, ]
    sat_src <- c(hybrid = "viirs", hybrid_modis = "modis", pred = "hull", viirs = "viirs", modis = "modis")[summ$use]
    cmp <- data.frame(yrmo = key, use = summ$use, use_18 = t18$use, sat_src = unname(sat_src), sat_src_18 = t18$sat_src,
                      hybrid_changed = summ$hybrid_changed, hybrid_changed_18 = t18$hybrid_changed,
                      fit_status = summ$fit_status, fit_status_18 = t18$fit_status, viirs_status = summ$viirs_status, viirs_status_18 = t18$viirs_status,
                      exposure = summ$exposure, box_exposure = boxc$box_exposure, exposure_18 = t18$final_exposure,
                      d_exposure = summ$exposure + boxc$box_exposure - t18$final_exposure,
                      n_pos = summ$n_pos, box_n_pos = boxc$box_n_pos, n_pos_18 = t18$final_n_pos,
                      n_le1k = summ$n_le1k, box_n_le1k = boxc$box_n_le1k, n_le1k_18 = t18$final_n_le1e3,
                      n_1k_10k = summ$n_1k_10k, box_n_1k_10k = boxc$box_n_1k_10k, n_1k_10k_18 = t18$final_n_1e3_1e4,
                      n_10k_100k = summ$n_10k_100k, box_n_10k_100k = boxc$box_n_10k_100k, n_10k_100k_18 = t18$final_n_1e4_1e5,
                      n_100k_1M = summ$n_100k_1M, box_n_100k_1M = boxc$box_n_100k_1M, n_100k_1M_18 = t18$final_n_1e5_1e6,
                      n_gt1M = summ$n_gt1M, box_n_gt1M = boxc$box_n_gt1M, n_gt1M_18 = t18$final_n_gt1e6,
                      n_changed = summ$n_changed, n_changed_18 = t18$final_n_changed,
                      n_samples_pos = summ$n_samples_pos, fwc_n_pos_18 = t18$fwc_n_pos,
                      s_le1k = summ$s_le1k, s_le1k_18 = t18$fwc_n_le1e3, s_1k_10k = summ$s_1k_10k, s_1k_10k_18 = t18$fwc_n_1e3_1e4,
                      s_10k_100k = summ$s_10k_100k, s_10k_100k_18 = t18$fwc_n_1e4_1e5, s_100k_1M = summ$s_100k_1M, s_100k_1M_18 = t18$fwc_n_1e5_1e6,
                      s_gt1M = summ$s_gt1M, s_gt1M_18 = t18$fwc_n_gt1e6, stringsAsFactors = FALSE)
    fwc_na <- is.na(cmp$fwc_n_pos_18)
    cmp$equal <- cmp$use == cmp$use_18 & cmp$sat_src == cmp$sat_src_18 & cmp$hybrid_changed == cmp$hybrid_changed_18 &
      cmp$fit_status == cmp$fit_status_18 & cmp$viirs_status == cmp$viirs_status_18 & abs(cmp$d_exposure) <= 1e-3 &
      cmp$n_pos + cmp$box_n_pos == cmp$n_pos_18 & cmp$n_le1k + cmp$box_n_le1k == cmp$n_le1k_18 & cmp$n_1k_10k + cmp$box_n_1k_10k == cmp$n_1k_10k_18 &
      cmp$n_10k_100k + cmp$box_n_10k_100k == cmp$n_10k_100k_18 & cmp$n_100k_1M + cmp$box_n_100k_1M == cmp$n_100k_1M_18 & cmp$n_gt1M + cmp$box_n_gt1M == cmp$n_gt1M_18 &
      cmp$n_changed == cmp$n_changed_18 &
      ifelse(fwc_na, summ$n_samples == 0, cmp$n_samples_pos == cmp$fwc_n_pos_18 & cmp$s_le1k == cmp$s_le1k_18 & cmp$s_1k_10k == cmp$s_1k_10k_18 &
               cmp$s_10k_100k == cmp$s_10k_100k_18 & cmp$s_100k_1M == cmp$s_100k_1M_18 & cmp$s_gt1M == cmp$s_gt1M_18)
    utils::write.csv(cmp, file.path(dir_tab, "bundle_vs_issue18_issue23.csv"), row.names = FALSE)
    pass(all(cmp$equal), sprintf("all %d months equal the #18 class-count table once the box is added back (max exposure difference %.2g cells/L); the clip source, the fit and VIIRS status, the cells changed and the sample bands equal", nrow(cmp), max(abs(cmp$d_exposure))))

    # 5. The threshold metrics against the #18 record table (the frozen run; the October refresh changed 202609 and 202610).
    cat("5. summary vs record_months_issue18.csv\n")
    rec <- utils::read.csv(file.path(dir_sub18, "record_months_issue18.csv"), colClasses = c(yrmo = "character"), stringsAsFactors = FALSE)
    j <- match(key, rec$yrmo); stopifnot(!anyNA(j)); rec <- rec[j, ]
    refreshed <- c("202609", "202610")
    cr <- data.frame(yrmo = key, refreshed = key %in% refreshed,
                     n_ge10k = summ$n_ge10k + boxc$box_n_ge10k, n_ge10k_18 = rec$n_ge10k_final,
                     km2_ge10k = summ$km2_ge10k + boxc$box_km2_ge10k, km2_ge10k_18 = rec$km2_ge10k_final,
                     n_ge100k = summ$n_ge100k + boxc$box_n_ge100k, n_ge100k_18 = rec$n_ge100k_final,
                     n_ge1M = summ$n_ge1M + boxc$box_n_ge1M, n_ge1M_18 = rec$n_ge1M_final,
                     max_cells = pmax(summ$max_cells, boxc$box_max_cells), max_cells_18 = rec$max_cells_final,
                     samples_ge10k = summ$samples_ge10k, samples_ge10k_18 = rec$samples_ge10k,
                     in_ge10k = summ$in_ge10k, in_ge10k_18 = rec$in_ge10k_final, stringsAsFactors = FALSE)
    cr$equal <- cr$n_ge10k == cr$n_ge10k_18 & abs(cr$km2_ge10k - cr$km2_ge10k_18) <= 0.5 & cr$n_ge100k == cr$n_ge100k_18 & cr$n_ge1M == cr$n_ge1M_18 &
      abs(cr$max_cells - cr$max_cells_18) <= 0.5 & cr$samples_ge10k == cr$samples_ge10k_18 & cr$in_ge10k == cr$in_ge10k_18
    utils::write.csv(cr, file.path(dir_tab, "bundle_vs_record_issue23.csv"), row.names = FALSE)
    pass(all(cr$equal[!cr$refreshed]), sprintf("%d of %d months equal the #18 record table on the threshold metrics, the maximum and the samples at or above 10k; the refreshed months (%s) %s",
                                               sum(cr$equal[!cr$refreshed]), nrow(cr), paste(refreshed, collapse = ", "), if (all(cr$equal[cr$refreshed])) "also equal" else "differ as expected"))
  }

  # 6. The samples against the filtered file the bundle names.
  cat("6. samples\n")
  pass(basename(file_filtered) == meta$samples$file, sprintf("the samples file on disk is the bundle's (%s)", meta$samples$file))
  e <- new.env(); load(file_filtered, envir = e)
  p <- sf::st_drop_geometry(e$filtered_points_df)
  p <- data.frame(year = as.integer(p$year), month = as.integer(p$month), cells = suppressWarnings(as.numeric(p$cells)), lon = as.numeric(p$lon), lat = as.numeric(p$lat))
  p <- p[!is.na(p$cells) & p$year >= cfg$styr & p$year <= cfg$enyr, ]
  p$cell <- raster::cellFromXY(depth, cbind(p$lon, p$lat)); p$water <- ifelse(is.na(p$cell), NA, water[ifelse(is.na(p$cell), 1L, p$cell)])
  p <- p[order(p$year, p$month, p$lat, p$lon, p$cells), ]; rownames(p) <- NULL
  sb <- do.call(rbind, lapply(years, function(y) rd(file.path("samples", paste0("fwc_", y, ".csv")), c(year = "integer", month = "integer", cells = "numeric", lon = "numeric", lat = "numeric", cell = "integer", water = "logical"))))
  rownames(sb) <- NULL; p$cell <- as.integer(p$cell)
  pass(identical(sb, p), sprintf("the %d sample rows equal the filtered file's rows with a count in %d-%d (%d off the grid), with the cell of raster::cellFromXY()", nrow(sb), cfg$styr, cfg$enyr, sum(is.na(sb$cell))))
  cnt <- as.integer(table(factor(sprintf("%04d%02d", sb$year, sb$month), levels = key)))
  pass(identical(cnt, summ$n_samples) && !any(atl[sb$cell[!is.na(sb$cell)]]), "the per-month counts equal n_samples; no sample lies in the Atlantic-side box")
  last_data <- max(sprintf("%04d%02d", sb$year, sb$month))
  pass(identical(months$placeholder, key > last_data) && meta$months$last_data == last_data && meta$months$n_placeholder == sum(key > last_data),
       sprintf("the placeholder months are the %d months after %s", sum(key > last_data), last_data))

  # The files table (every file, the manifest included).
  files_tab <- data.frame(file = c(manif$file, "manifest.csv"), bytes = c(manif$bytes, as.integer(file.info(file.path(dir_bundle, "manifest.csv"))$size)), stringsAsFactors = FALSE)
  files_tab$rows <- vapply(files_tab$file, function(f) if (grepl("[.]csv$", f)) length(readLines(file.path(dir_bundle, f))) - 1L else NA_integer_, integer(1))
  utils::write.csv(files_tab, file_files, row.names = FALSE)

  # 7. The frozen counts of the run of 23 October 2026 (5 arcmin).
  if (frozen && res == 5L) {
    cat("7. frozen counts\n")
    expected <- list(n_months = 504L, all_zero = 173L, value_rows = 51872L, box_pos = 2503L, box_months = 94L, n_domain = 3782L,
                     use = c(hybrid = 155L, viirs = 0L, hybrid_modis = 123L, modis = 0L, pred = 226L), hybrid_changed = 210L,
                     fit = c(failed = 5L, fitted = 331L, none = 168L), converged = c(`FALSE` = 3L, `TRUE` = 328L, `NA` = 173L),
                     hull_flagged = c("199009", "199604", "199606", "199711", "199909", "200009", "200010", "200110", "200112", "200201"), hull_na = 19L,
                     placeholder = c("202611", "202612"), n_samples = 181411L, off_grid = 93L, n_files = 94L,
                     m201809 = list(exposure = 310492554.245117, bands = c(0L, 0L, 127L, 450L, 71L), n_ge10k = 648L, km2_ge10k = 49160L, max_cells = 7746619, max_cell = 2864L,
                                    n_changed = 32L, n_samples = 1026L, n_samples_pos = 525L, s = c(54L, 105L, 132L, 158L, 76L), samples_ge10k = 290L, in_ge10k = 289L))
    s9 <- summ[summ$yrmo == "201809", ]
    pass(nrow(summ) == expected$n_months && sum(summ$n_pos == 0) == expected$all_zero && nrow(vals) == expected$value_rows &&
         sum(boxc$box_n_pos) == expected$box_pos && sum(boxc$box_n_pos > 0) == expected$box_months && sum(domain) == expected$n_domain && nrow(files_tab) == expected$n_files,
         "504 months, 173 all zero, 51,872 value rows on the domain, 2,503 positive cell-months in the box over 94 months, 3,782 domain cells, 94 files")
    pass(identical(as.integer(table(factor(summ$use, levels = names(expected$use)))), unname(expected$use)) && sum(summ$hybrid_changed) == expected$hybrid_changed && sum(summ$n_changed > 0) == expected$hybrid_changed,
         "use 155 / 0 / 123 / 0 / 226, hybrid_changed and n_changed > 0 in 210 months")
    pass(identical(as.integer(table(factor(summ$fit_status, levels = names(expected$fit)))), unname(expected$fit)) &&
         identical(c(sum(summ$converged %in% FALSE), sum(summ$converged %in% TRUE), sum(is.na(summ$converged))), unname(expected$converged)),
         "fit_status 5 failed / 331 fitted / 168 none; converged 3 FALSE / 328 TRUE / 173 NA")
    pass(identical(summ$yrmo[summ$hull_flagged %in% TRUE], expected$hull_flagged) && sum(is.na(summ$hull_flagged)) == expected$hull_na && identical(key[months$placeholder], expected$placeholder),
         "hull_flagged exactly the ten months of the run log, NA in 19; placeholders 202611 and 202612")
    pass(nrow(sb) == expected$n_samples && sum(is.na(sb$cell)) == expected$off_grid, "181,411 samples, 93 off the grid")
    x <- expected$m201809
    pass(abs(s9$exposure - x$exposure) < 1e-6 && identical(as.integer(s9[, c("n_le1k", "n_1k_10k", "n_10k_100k", "n_100k_1M", "n_gt1M")]), x$bands) &&
         s9$n_ge10k == x$n_ge10k && round(s9$km2_ge10k) == x$km2_ge10k && round(s9$max_cells) == x$max_cells && s9$max_cell == x$max_cell &&
         s9$n_changed == x$n_changed && s9$n_samples == x$n_samples && s9$n_samples_pos == x$n_samples_pos &&
         identical(as.integer(s9[, c("s_le1k", "s_1k_10k", "s_10k_100k", "s_100k_1M", "s_gt1M")]), x$s) && s9$samples_ge10k == x$samples_ge10k && s9$in_ge10k == x$in_ge10k,
         "2018-09: exposure 310,492,554 cells/L, 648 positives (0 / 0 / 127 / 450 / 71), 648 cells >= 10k over 49,160 km2, max 7,746,619 at cell 2864, 32 cells changed, 1,026 samples (525 positive: 54 / 105 / 132 / 158 / 76), 290 >= 10k with 289 inside the map")
  }

  # Figures, drawn from the bundle's own files only (meta.json, grid.csv, months.csv, values/, summary/, samples/, style.json).
  cat("figures\n")
  g_nc <- meta$grid$ncols; g_nr <- meta$grid$nrows
  to_z <- function(v) matrix(v, nrow = g_nc)[, g_nr:1]
  xs <- sort(unique(grid$lon)); ys <- sort(unique(grid$lat)); h <- meta$grid$cellsize / 2
  pb <- style$palette$breaks
  cols <- style$palette$colors_hex; brks <- c(pb$zero, pb$first_colored - 1, seq(pb$first_colored, pb$last, pb$step), 1e12)
  land_z <- to_z(ifelse(!grid$water, 1, NA)); box_z <- to_z(ifelse(grid$water & grid$atlantic, 1, NA))
  draw_month <- function(m) {
    r <- summ[summ$yrmo == m, ]
    plot(NA, xlim = range(xs) + c(-h, h), ylim = range(ys) + c(-h, h), xlab = "", ylab = "", asp = 1 / cos(27.5 * pi / 180), xaxs = "i", yaxs = "i", axes = FALSE,
         main = sprintf("%s-%s: %s", substr(m, 1, 4), substr(m, 5, 6), r$use), cex.main = 0.9)
    image(xs, ys, land_z, col = "wheat", add = TRUE, useRaster = TRUE)
    image(xs, ys, box_z, col = "gray88", add = TRUE, useRaster = TRUE)
    v <- Mb[, m]; v[!grid$domain] <- NA
    image(xs, ys, to_z(v), breaks = brks, col = cols, add = TRUE, useRaster = TRUE)
    sm <- sb[sb$year == as.integer(substr(m, 1, 4)) & sb$month == as.integer(substr(m, 5, 6)), ]
    if (nrow(sm)) points(sm$lon, sm$lat, pch = 16, cex = 0.25, col = ifelse(sm$cells > 0, "black", "gray45"))
    legend("left", bty = "o", bg = "white", box.col = "gray60", cex = 0.6, x.intersp = 0.3, y.intersp = 0.9,
           legend = c(sprintf("exposure %s cells/L", format(signif(r$exposure, 3), big.mark = ",", scientific = FALSE)),
                      sprintf("%d positives", r$n_pos), sprintf("%d %s", c(r$n_le1k, r$n_1k_10k, r$n_10k_100k, r$n_100k_1M, r$n_gt1M), style$bands$labels),
                      sprintf("%d samples (%d positive)", r$n_samples, r$n_samples_pos)))
    box()
  }
  fig_months <- c("201809", "201202", "200510", meta$months$last_data)
  fig_months <- fig_months[fig_months %in% key]
  png(file_fig1, width = 1600, height = 1300, res = 150)
  par(mfrow = c(2, 2), mar = c(0.5, 0.5, 2, 0.5), oma = c(0, 0, 2.5, 0))
  for (m in fig_months) draw_month(m)
  mtext(sprintf("The data bundle %s drawn from its own files: land (wheat) and the Atlantic-side box (gray, water without data) from grid.csv, the maps from values/, the samples from samples/, the counts from summary/", meta$bundle_id), outer = TRUE, cex = 0.65, line = 1)
  mtext(sprintf("Palette: style.json (white below %sk cells/L, %s above %sM). Exposure and counts over the Gulf domain. Samples: black positive, gray zero.", pb$first_colored / 1e3, style$palette$above, pb$last / 1e6), outer = TRUE, cex = 0.6, line = 0)
  invisible(dev.off())
  png(file_fig2, width = 1800, height = 900, res = 150)
  par(mfrow = c(2, 1), mar = c(2.2, 4.2, 2, 1), oma = c(1.5, 0, 1.5, 0))
  idx <- seq_along(key); jan <- which(months$month == 1)
  era_col <- c(hybrid = adjustcolor("gold", 0.22), viirs = adjustcolor("gold", 0.22), hybrid_modis = adjustcolor("steelblue", 0.18), modis = adjustcolor("steelblue", 0.18), pred = adjustcolor("gray40", 0.12))
  draw_series <- function(y, lab) {
    plot(idx, y, type = "n", xlab = "", ylab = lab, xaxt = "n", las = 1)
    rect(idx - 0.5, par("usr")[3], idx + 0.5, par("usr")[4], col = era_col[summ$use], border = NA)
    if (any(months$placeholder)) rect(min(idx[months$placeholder]) - 0.5, par("usr")[3], max(idx) + 0.5, par("usr")[4], col = adjustcolor("red", 0.15), border = NA)
    lines(idx, y, col = "purple3", lwd = 1); axis(1, at = jan, labels = FALSE, tck = -0.02); axis(1, at = jan[seq(1, length(jan), 5)], labels = months$year[jan[seq(1, length(jan), 5)]], tick = FALSE, cex.axis = 0.8)
    box()
  }
  draw_series(summ$exposure / 1e6, "exposure, million cells/L")
  draw_series(summ$n_ge10k, "cells >= 10k cells/L")
  mtext(sprintf("summary/redtide.csv of %s, %s to %s: hull-served months gray, MODIS-served blue, VIIRS-served gold, placeholders red", meta$bundle_id, key[1], key[length(key)]), outer = TRUE, cex = 0.75, line = 0.2)
  invisible(dev.off())
  cat("  --   ", basename(file_fig1), " (", paste(fig_months, collapse = ", "), "), ", basename(file_fig2), ", ", basename(file_files), "\n", sep = "")
  cat("\nAll checks passed (stage frozen).\n")
}

# Stage rerun --------------------------------------------------------------------------------------
if (stage == "rerun") {
  cat("rerun: fn.write_bundle(mode = \"standalone\") with the cfg and inputs the bundle under check names, into hoard/rerun/bundle\n")
  dir_rerun <- file.path(dir_docs, "hoard", "rerun"); dir.create(dir_rerun, recursive = TRUE, showWarnings = FALSE)
  out <- fn.write_bundle(dir_ascii = dir_ascii, file_depth = file_depth, file_clipsrc = file_clipsrc, file_filtered = file_filtered,
                         dir_out = file.path(dir_rerun, "bundle"), cfg = cfg, res = res, repo_dir = .root,
                         file_schema = file.path(dir_docs, "bundle-schema.md"), file_mask = file_mask, file_unclip = file_unclip,
                         file_fitmat = file_fitmat, file_viirs_raw = file_viirs_raw,
                         file_viirs_clip = file_viirs, file_modis_clip = file_modis, file_hulldiag = file_hulldiag, file_combined = file_comb,
                         mode = "standalone")
  cat(sprintf("  --   written in %.1f s: %d files, %.2f MB\n", out$seconds, out$n_files, out$bytes / 1e6))
  fa <- sort(list.files(dir_bundle, recursive = TRUE, all.files = TRUE, no.. = TRUE), method = "radix")
  fb <- sort(list.files(file.path(dir_rerun, "bundle"), recursive = TRUE, all.files = TRUE, no.. = TRUE), method = "radix")
  pass(identical(fa, fb), sprintf("the same %d files", length(fa)))
  ma <- fn.md5_lf(file.path(dir_bundle, fa)); mb <- fn.md5_lf(file.path(dir_rerun, "bundle", fb))
  tab <- data.frame(file = fa, bytes = ma$bytes, md5 = ma$md5, md5_rerun = mb$md5, equal = ma$md5 == mb$md5, stringsAsFactors = FALSE)
  utils::write.csv(tab, file_rerun, row.names = FALSE)
  volatile <- c("meta.json", "manifest.csv")
  pass(all(tab$equal[!tab$file %in% volatile]), sprintf("%d of %d files byte-identical (all but meta.json and the manifest row that hashes it)", sum(tab$equal), nrow(tab)))
  ja <- jsonlite::fromJSON(file.path(dir_bundle, "meta.json"), simplifyVector = FALSE); jb <- jsonlite::fromJSON(file.path(dir_rerun, "bundle", "meta.json"), simplifyVector = FALSE)
  for (k in c("built_at", "run_log", "mode")) ja$build[[k]] <- jb$build[[k]] <- NULL
  for (k in c("branch", "ascii_commit", "ascii_dirty", "head_commit", "schema_url")) ja$source[[k]] <- jb$source[[k]] <- NULL
  pass(identical(ja, jb), "meta.json differs only in build.built_at, build.run_log, build.mode and the volatile source keys (branch, ascii_commit, ascii_dirty, head_commit, schema_url)")
  mfa <- rd("manifest.csv"); mfb <- utils::read.csv(file.path(dir_rerun, "bundle", "manifest.csv"), stringsAsFactors = FALSE)
  pass(identical(mfa[mfa$file != "meta.json", ], mfb[mfb$file != "meta.json", ]), "manifest.csv differs only in its meta.json row")
  fn.assert_no_cr(file.path(dir_rerun, "bundle")); cat("  ok   no carriage return or non-ASCII byte in the rerun\n")
  cat("\nAll checks passed (stage rerun).\n")
}
