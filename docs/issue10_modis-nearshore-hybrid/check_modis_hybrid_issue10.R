#' QA for issue #10: the nearshore hybrid (mask5) for the MODIS months.
#'
#' Issue #11 put the mask5 nearshore rule into the pipeline for the VIIRS months.
#' This script asks the same question for the months the pipeline serves from
#' MODIS nFLH polygons and, once the rule is applied to them, checks the runs.
#' Stages, chosen with RT_QA_STAGE (default "examine"). Each reads only what the
#' last pipeline run left on disk and the tracked tables, refits nothing and uses
#' no RNG; CSVs and PNGs are byte-identical from run to run (the PDF carries the
#' two date lines every R pdf() device writes).
#'
#'   examine  no pipeline run: prototypes the rule on the MODIS-served months from
#'            the MODIS-clipped, hull-clipped and nearshore-set rasters of the last
#'            run (hybrid = max(MODIS-clipped, hull-clipped) inside the set, the
#'            MODIS-clipped layer outside it) and reports what it changes
#'            -> tables/examine_months_issue10.csv, tables/examine_annual_issue10.csv,
#'               tables/examine_groups_issue10.csv, tables/excluded_samples_issue10.csv,
#'               tables/excluded_bands_issue10.csv, tables/modis_coverage_issue10.csv,
#'               tables/modis_never_positive_bands_issue10.csv,
#'               figures/fig1_examine_months_issue10.pdf, figures/fig2_examine_series_issue10.png,
#'               figures/fig3_excluded_samples_issue10.png, comments/examine_summary.md
#'   regress  after run A (cfg$viirs_nearshore = "mask5", cfg$modis_nearshore = "none",
#'            fwc_refresh = FALSE): the 504 ASCII files must equal the issue #11 "mask5"
#'            run byte for byte (the refactor and the cascade change alter nothing)
#'            -> tables/md5_runA_issue10.csv
#'   mask5    after run B (both "mask5"): only the MODIS-served months with a nearshore
#'            hull change, the MODIS hybrid stack equals the examine prototype in every
#'            month, the VIIRS hybrid and hull months are untouched
#'            -> tables/md5_runB_issue10.csv, tables/hybrid_modis_vs_prototype_issue10.csv
#'   compare  the whole record as Ecospace reads it, three variants: the 6 October 2026
#'            maps (satellite only), the VIIRS hybrid (#11, run A) and both hybrids
#'            (#10, run B), read from docs/issue11_nearshore-hybrid-pipeline/hoard/before/,
#'            hoard/before/ and hoard/after/ (combined stacks and clipping_source.csv of
#'            the runs; hoard/ folders are gitignored)
#'            -> tables/record_months_issue10.csv, tables/record_annual_issue10.csv,
#'               tables/record_groups_issue10.csv, tables/cells_modis_issue10.csv,
#'               figures/fig4_record_2002-2026_issue10.png, figures/fig5_cells_modis_issue10.png,
#'               comments/compare_summary.md
#'   (run 0, both "none", is checked by the unchanged issue #11 stage `none`.)
#'
#' Run from the repo root:
#'   RT_QA_STAGE=examine Rscript docs/issue10_modis-nearshore-hybrid/check_modis_hybrid_issue10.R
#'   RT_QA_STAGE=regress ...   RT_QA_STAGE=mask5 ...   RT_QA_STAGE=compare ...
#'   RT_QA_PNG_DIR=<folder> adds PNG previews of the fig 1 pages (stage examine).
#' Needs out/5min/clipped/nearshore_mask_mask5.grd from a run with a nearshore rule on
#' and the 6 October 2026 combined stack in
#' docs/issue11_nearshore-hybrid-pipeline/hoard/before/combined/ (the delivered maps).

# Repo root: the working directory if it holds the .Rproj, else two levels above this script.
.root <- local({
  if (file.exists("RedTideMaps.Rproj")) return(normalizePath(getwd(), winslash = "/"))
  f <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE))
  if (length(f) == 1) {
    d <- normalizePath(file.path(dirname(f), "..", ".."), winslash = "/", mustWork = FALSE)
    if (file.exists(file.path(d, "RedTideMaps.Rproj"))) return(d)
  }
  stop("Run from the repo root: Rscript docs/issue10_modis-nearshore-hybrid/check_modis_hybrid_issue10.R", call. = FALSE)
})
source(file.path(.root, "scripts", "_setup.R"))   # sf, raster, viridis, ...
stage <- match.arg(Sys.getenv("RT_QA_STAGE", "examine"), c("examine", "regress", "mask5", "compare"))
message("Issue #10 check, stage: ", stage)

# Parameters ---------------------------------------------------------------------
thr_bloom  <- 1e4      # cells/L: FWC "low"; first coloured bin of the pipeline PDFs
thr_high   <- 1e5      # cells/L: FWC "medium"
class_brks <- c(-Inf, 0, 1e3, 1e4, 1e5, 1e6, Inf)   # FWC classes, right-closed (as #6, #8 and #11)
class_lv   <- c("negative", "background", "very_low", "low", "medium", "high")
coast_bands <- c(0, 2, 5, 10, Inf); band_lv <- c("0-2 km", "2-5 km", "5-10 km", "> 10 km")
min_samples_group <- 5L   # a month enters the sample-share groups with at least this many water samples >= 10,000 cells/L
fig1_top      <- 12L      # fig 1: the months with the largest gain in samples included ...
fig1_per_page <- 8L
coast_tol_m   <- 500      # coastline simplified for drawing
coast_step_m  <- 200      # coastline densified for distances (as fn.nearshore_mask())
# Numbers of the 22 Oct 2026 read-only prototype (plan, section 1), asserted below.
expected <- list(n_modis = 123L, n_set = 136L, km2_set = 10227, n_changed = 87L,
                 samples_ge1e4 = 4535L, in_before = 3736L, in_after = 4035L,
                 samples_high = 442L, high_in_before = 393L, high_in_after = 413L,
                 n_excluded = 799L, excluded_in_set = 301L, excluded_recovered = 299L,
                 set_cells_modis_pos = 132L, exposure_before = 2374510206,
                 n_ge5 = 60L, n_lowinc_before = 10L, n_lowinc_after = 2L,
                 n_nobloom_before = 8L, n_nobloom_after = 7L, n_allzero = 29L,
                 # the runs (issue #11 figures for the VIIRS side)
                 n_ascii = 504L, n_viirs = 155L, n_changed_viirs = 121L,
                 use_runA = c(hybrid = 155L, modis = 123L, pred = 226L),
                 use_runB = c(hybrid = 155L, hybrid_modis = 123L, pred = 226L))

# Paths --------------------------------------------------------------------------
dir_out      <- file.path(.root, "out", "5min")
dir_sdm      <- file.path(dir_out, "sdm")
dir_clipped  <- file.path(dir_out, "clipped")
dir_docs     <- file.path(.root, "docs", "issue10_modis-nearshore-hybrid")
dir_tab      <- file.path(dir_docs, "tables")
dir_fig      <- file.path(dir_docs, "figures")
dir_cmt      <- file.path(dir_docs, "comments")
dir_hoard11  <- file.path(.root, "docs", "issue11_nearshore-hybrid-pipeline", "hoard")
dir_tab11    <- file.path(.root, "docs", "issue11_nearshore-hybrid-pipeline", "tables")
dir_hoard    <- file.path(dir_docs, "hoard")
dir_ascii    <- file.path(dir_out, "ecospace_ascii")
dir_combined <- file.path(dir_out, "combined")
for (d in c(dir_tab, dir_fig, dir_cmt)) dir.create(d, recursive = TRUE, showWarnings = FALSE)
one_file <- function(dir, pattern, what) {
  f <- list.files(dir, pattern = pattern, full.names = TRUE)
  if (length(f) != 1) stop("Expected one ", what, " in ", dir, " (found ", length(f), ").", call. = FALSE)
  f
}
grd <- function(f) sub("[.]grd$", "", f)
file_depth <- one_file(file.path(.root, "template rasters"), "^depth 5min .*[.]asc$", "depth template")
file_tab6  <- file.path(.root, "docs", "issue6_VIIRS-zeros", "tables", "clip_comparison_issue6.csv")
file_coast <- file.path(.root, "data", "coastline", "ne_10m_coastline_wfs.gpkg")
file_mask  <- file.path(dir_clipped, "nearshore_mask_mask5.grd")
file_cs    <- file.path(dir_clipped, "clipping_source.csv")
for (f in c(file_tab6, file_coast, file_cs)) if (!file.exists(f)) stop("Missing ", f, call. = FALSE)
if (!file.exists(file_mask))
  stop("Missing ", file_mask, ": run the pipeline once with cfg$viirs_nearshore = \"mask5\" (issue #11) so the nearshore set is on disk.", call. = FALSE)

# Common objects -----------------------------------------------------------------
depth    <- raster::raster(file_depth)
dv       <- raster::values(depth)
land     <- is.na(dv)
water    <- !land
cell_km2 <- raster::values(raster::area(depth))
nr <- nrow(depth); nc <- ncol(depth); n5 <- raster::ncell(depth)
xy5 <- raster::xyFromCell(depth, seq_len(n5))
read_mat <- function(f) {
  b <- raster::brick(f)
  stopifnot(raster::compareRaster(depth, b))
  m <- raster::values(b); colnames(m) <- sub("^X", "", names(b)); m
}
norm_map <- function(M) { M[is.na(M)] <- 0; M[land, ] <- NA; M }   # as make_redtide_ascii() writes every layer
same <- function(a, b) all((a == b) | (is.na(a) & is.na(b)))
fmt_n <- function(x) format(x, big.mark = ",", trim = TRUE, scientific = FALSE)
tab6 <- read.csv(file_tab6, colClasses = c(yrmo = "character"), stringsAsFactors = FALSE)

# The MODIS-served months: in the MODIS-clipped stack and not in the VIIRS one, whatever
# the nearshore rule of the last run (the cascade serves them from MODIS, or from the
# MODIS hybrid once issue #10 is in).
cs <- read.csv(file_cs, stringsAsFactors = FALSE); cs$yrmo <- sub("^X", "", cs$yrmo)
months <- sort(cs$yrmo[cs$modis %in% TRUE & !(cs$viirs %in% TRUE)])
stopifnot(length(months) == expected$n_modis)

# Samples of the given months on the template, as the #8 prototype and #11 counted them:
# water cells only, off-grid samples (northern edge) dropped, FWC classes right-closed.
load_samples <- function(months) {
  ff <- list.files(dir_sdm, pattern = "_filtered[.]Rdata$", full.names = TRUE)
  if (length(ff) == 0) stop("No *_filtered.Rdata in ", dir_sdm, call. = FALSE)
  ff_end <- as.integer(substr(regmatches(basename(ff), regexpr("[0-9]{8}_filtered", basename(ff))), 1, 8))
  file_filtered <- ff[which.max(ff_end)]
  message("Samples: ", basename(file_filtered))
  load(file_filtered)      # filtered_points_df (sf)
  pts <- sf::st_drop_geometry(filtered_points_df)
  pts$cells <- suppressWarnings(as.numeric(pts$cells)); pts <- pts[!is.na(pts$cells), ]
  pts$yrmo  <- sprintf("%d%02d", as.integer(pts$year), as.integer(pts$month))
  pts <- pts[pts$yrmo %in% months, ]
  pts$cell5 <- raster::cellFromXY(depth, cbind(pts$lon, pts$lat))
  pts <- pts[!is.na(pts$cell5), ]
  pts$water <- water[pts$cell5]
  pts$class <- as.character(cut(pts$cells, class_brks, labels = class_lv, right = TRUE))
  pts$ge1e4 <- pts$cells >= thr_bloom
  pts
}
# Per month: water samples by class, and how many sit in a non-zero cell of M.
samples_of <- function(M, pw, months) {
  j <- match(pw$yrmo, months); inside <- M[cbind(pw$cell5, j)] > 0
  stopifnot(!any(is.na(inside)))
  ymf <- factor(pw$yrmo, levels = months)
  cnt <- function(sel) as.vector(table(ymf[sel])); hit <- function(sel) as.vector(table(ymf[sel & inside]))
  out <- data.frame(yrmo = months, stringsAsFactors = FALSE)
  for (k in c("low", "medium", "high")) { s <- pw$class == k; out[[paste0("n_", k)]] <- cnt(s); out[[paste0("in_", k)]] <- hit(s) }
  out$n_ge1e4 <- cnt(pw$ge1e4); out$in_ge1e4 <- hit(pw$ge1e4)
  out$share_ge1e4 <- ifelse(out$n_ge1e4 > 0, round(out$in_ge1e4 / out$n_ge1e4, 3), NA)
  out
}
area_ge <- function(M, thr) colSums((!is.na(M) & M >= thr) * cell_km2)
metrics_of <- function(M) data.frame(
  fp_km2 = colSums((!is.na(M) & M > 0) * cell_km2), a1e4_km2 = area_ge(M, thr_bloom), a1e5_km2 = area_ge(M, thr_high),
  n_cells_fp = colSums(!is.na(M) & M > 0), max_cells = apply(M, 2, max, na.rm = TRUE),
  mean_cells_water = colMeans(M[water, , drop = FALSE]), stringsAsFactors = FALSE)
# Exposure per map as Ecospace reads it (#11 stage exposure): the sum of cells/L over the
# water cells and the cells at or above 10,000 / 100,000 / 1,000,000 cells/L.
thr <- c(ge1e4 = 1e4, ge1e5 = 1e5, ge1e6 = 1e6)
expo_of <- function(M) {
  out <- data.frame(exposure = colSums(M[water, , drop = FALSE]))
  for (k in names(thr)) {
    hit <- !is.na(M) & M >= thr[[k]]
    out[[paste0("n_", k)]] <- colSums(hit); out[[paste0("km2_", k)]] <- colSums(hit * cell_km2)
  }
  out
}
# Rounding for the written tables: km2 and exposure sums to whole numbers, means to
# one decimal, ratios to three.
round_cols <- function(df) {
  for (nm in grep("km2|mean_cells|exposure", names(df), value = TRUE))
    df[[nm]] <- round(df[[nm]], if (grepl("mean_cells", nm)) 1 else if (grepl("ratio", nm)) 3 else 0)
  df
}
md_table <- function(df, digits = 3) {
  cell <- function(x, nm) {
    if (!is.numeric(x) || nm %in% c("year", "month", "yrmo", "cell")) return(ifelse(is.na(x), "", as.character(x)))
    ifelse(is.na(x), "", format(round(x, digits), big.mark = ",", trim = TRUE, scientific = FALSE, drop0trailing = TRUE))
  }
  body <- do.call(cbind, Map(cell, df, names(df)))
  if (is.null(dim(body))) body <- matrix(body, nrow = 1)
  c(paste0("| ", paste(names(df), collapse = " | "), " |"), paste0("|", paste(rep("---", ncol(df)), collapse = "|"), "|"),
    apply(body, 1, function(r) paste0("| ", paste(r, collapse = " | "), " |")))
}
# Nearest-point distance (km) from lon/lat to the coastline densified to coast_step_m
# (UTM 17N), as fn.nearshore_mask() and the #8 diagnostic compute it.
coast_full <- sf::st_read(file_coast, quiet = TRUE)
coast_pts  <- local({
  seg <- sf::st_segmentize(sf::st_transform(sf::st_geometry(coast_full), 32617), coast_step_m)
  sf::st_cast(sf::st_sfc(sf::st_multipoint(sf::st_coordinates(seg)[, 1:2]), crs = 32617), "POINT")
})
dist_coast_km <- function(lon, lat) {
  if (length(lon) == 0) return(numeric(0))
  p  <- sf::st_transform(sf::st_as_sf(data.frame(lon = lon, lat = lat), coords = c("lon", "lat"), crs = 4326), 32617)
  nn <- sf::st_nearest_feature(p, coast_pts)
  as.numeric(sf::st_distance(sf::st_geometry(p), coast_pts[nn], by_element = TRUE)) / 1000
}
band_of <- function(d) factor(as.character(cut(d, coast_bands, labels = band_lv, right = FALSE, include.lowest = TRUE)), levels = band_lv)

# Drawing helpers (the #8 / #11 panel style) --------------------------------------
xs <- raster::xFromCol(depth, 1:nc); ys <- rev(raster::yFromRow(depth, 1:nr))
xlim <- c(-87.5, -81); ylim <- c(25, 30.5); asp <- 1 / cos(27.5 * pi / 180)
to_z   <- function(v) matrix(v, nrow = nc)[, nr:1]
colv   <- c("white", "purple", "blue", "darkblue", "cyan", "green", "darkgreen", "yellow", "orange", "red", "darkred")
funpal <- colorRampPalette(colv, bias = 2)
brks   <- c(0, 1e4 - 1, seq(1e4, 4e6, 10000), Inf); brks_img <- brks; brks_img[length(brks_img)] <- 1e12
color  <- c(funpal(length(brks) - 2), "darkred")
land_z <- to_z(ifelse(land, 1, NA))
spal   <- viridis::viridis(5, direction = -1)
coast  <- suppressWarnings(sf::st_simplify(coast_full, dTolerance = coast_tol_m))
base_panel <- function(main, xl = xlim, yl = ylim, cex_main = 0.85, axes = FALSE)
  plot(NA, xlim = xl, ylim = yl, xlab = "", ylab = "", asp = asp, main = main, cex.main = cex_main, xaxs = "i", yaxs = "i", axes = axes)
draw_land <- function() { image(xs, ys, land_z, col = "gray82", add = TRUE, useRaster = TRUE)
                          plot(sf::st_geometry(coast), add = TRUE, col = "gray30", lwd = 0.5) }
info_box <- function(lines, cex = 0.55) legend("left", legend = lines, bty = "o", bg = "white", box.col = "gray60",
                                              cex = cex, inset = 0.01, x.intersp = 0.3, y.intersp = 0.9)
class_counts_v <- function(v) { v <- v[!is.na(v) & v > 0]; k <- cut(v, class_brks[-1], labels = FALSE, include.lowest = TRUE); c(length(v), tabulate(k, nbins = 5)) }
class_lines <- function(cnt) paste(fmt_n(cnt), c("positives", "<= 1,000", "1,000 - 10,000", "10,000 - 100,000", "100,000 - 1,000,000", "> 1,000,000"))
draw_map_panel <- function(v, main, diff_from = NULL, shade = NULL, extra = NULL) {
  base_panel(main); rect(xlim[1], ylim[1], xlim[2], ylim[2], col = "white", border = NA)
  image(xs, ys, to_z(v), breaks = brks_img, col = color, add = TRUE, useRaster = TRUE)
  if (!is.null(shade)) image(xs, ys, to_z(ifelse(shade, 1, NA)), col = grDevices::adjustcolor("mediumpurple", 0.3), add = TRUE, useRaster = TRUE)
  if (!is.null(diff_from)) {
    d <- ifelse(!is.na(v) & !is.na(diff_from) & v != diff_from, 1, NA)
    if (any(!is.na(d))) image(xs, ys, to_z(d), col = grDevices::adjustcolor("orangered", 0.4), add = TRUE, useRaster = TRUE)
  }
  draw_land(); info_box(c(class_lines(class_counts_v(v)), extra)); box()
}
# Write a PDF to a temporary file and rename it into place (a copy open in a viewer
# does not kill the run); draw() draws every page.
write_pdf <- function(file_pdf, width, height, draw) {
  file_tmp <- sub("[.]pdf$", "_tmp.pdf", file_pdf)
  opened <- tryCatch({ pdf(file_tmp, width = width, height = height, onefile = TRUE); TRUE },
                     error = function(e) { warning("Cannot open ", file_tmp, ": ", conditionMessage(e), call. = FALSE); FALSE })
  if (!opened) return(invisible(FALSE))
  tryCatch(draw(), finally = invisible(dev.off()))
  if (file.exists(file_pdf) && !file.remove(file_pdf)) {
    warning("Could not replace ", file_pdf, " (open in a viewer?); the new file is ", file_tmp, call. = FALSE)
    return(invisible(FALSE))
  }
  file.rename(file_tmp, file_pdf); invisible(TRUE)
}

# Stage examine --------------------------------------------------------------------
if (stage == "examine") {
  # The set, the MODIS-clipped and hull-clipped layers of the MODIS-served months, and
  # the prototype: A = B outside the set, max(B, hull) inside it.
  mask_r <- raster::raster(file_mask)
  stopifnot(raster::compareRaster(depth, mask_r))
  mv <- raster::values(mask_r); set <- mv %in% 1
  stopifnot(all(is.na(mv) == land), sum(set) == expected$n_set, round(sum(cell_km2[set])) == expected$km2_set)
  Mc <- read_mat(grd(one_file(dir_clipped, "_clipped_modis[.]grd$", "MODIS-clipped stack")))
  H  <- read_mat(grd(one_file(dir_clipped, "_clipped_hull[.]grd$", "hull-clipped stack")))
  stopifnot(all(months %in% colnames(Mc)), all(months %in% colnames(H)))
  cat(sprintf("MODIS-clipped stack: %d layers (%s to %s); %d of them are MODIS-served months (%s to %s)\n",
              ncol(Mc), colnames(Mc)[1], colnames(Mc)[ncol(Mc)], length(months), months[1], months[length(months)]))
  B  <- norm_map(Mc[, months]); Hm <- norm_map(H[, months])
  A  <- B; A[set, ] <- pmax(B[set, ], Hm[set, ])
  # The delivered maps of these months (6 Oct 2026 combined stack) are the MODIS-clipped layers.
  f_before11 <- one_file(file.path(dir_hoard11, "before", "combined"), "_clipped_combined[.]grd$", "6 Oct 2026 combined stack")
  Cb <- read_mat(f_before11)
  stopifnot(all(months %in% colnames(Cb)), same(B, Cb[, months]))
  rm(Cb, Mc)
  stopifnot(all(is.na(B) == land), all(is.na(A) == land), all(A[water, ] >= B[water, ]), same(A[!set, ], B[!set, ]))

  # Per-month table.
  mB <- metrics_of(B); mA <- metrics_of(A); eB <- expo_of(B); eA <- expo_of(A)
  pts <- load_samples(months); pw <- pts[pts$water, ]
  sB <- samples_of(B, pw, months); sA <- samples_of(A, pw, months)
  m6 <- match(months, tab6$yrmo); stopifnot(!anyNA(m6), all(tab6$use[m6] == "modis"))
  em <- data.frame(yrmo = months, year = as.integer(substr(months, 1, 4)), month = as.integer(substr(months, 5, 6)),
                   fit_status = tab6$fit_status[m6], modis_n_polys = tab6$modis_n_polys[m6],
                   cells_changed = colSums(A != B, na.rm = TRUE), stringsAsFactors = FALSE)
  em$changed <- em$cells_changed > 0
  for (k in c("fp_km2", "a1e4_km2", "a1e5_km2", "max_cells", "mean_cells_water")) { em[[paste0(k, "_before")]] <- mB[[k]]; em[[paste0(k, "_after")]] <- mA[[k]] }
  for (k in names(eB)) { em[[paste0(k, "_before")]] <- eB[[k]]; em[[paste0(k, "_after")]] <- eA[[k]] }
  em$exposure_added <- eA$exposure - eB$exposure
  em$exposure_ratio <- ifelse(eB$exposure > 0, eA$exposure / eB$exposure, NA_real_)
  for (k in names(thr)) em[[paste0("n_", k, "_added")]] <- eA[[paste0("n_", k)]] - eB[[paste0("n_", k)]]
  em$samples_ge1e4 <- sB$n_ge1e4; em$samples_ge1e4_in_before <- sB$in_ge1e4; em$samples_ge1e4_in_after <- sA$in_ge1e4
  em$share_samples_ge1e4_before <- sB$share_ge1e4; em$share_samples_ge1e4_after <- sA$share_ge1e4
  em$samples_high <- sB$n_high; em$samples_high_in_before <- sB$in_high; em$samples_high_in_after <- sA$in_high
  em$all_zero_before <- mB$n_cells_fp == 0; em$all_zero_after <- mA$n_cells_fp == 0
  em$nobloom_before  <- em$samples_ge1e4 > 0 & em$n_ge1e4_before == 0
  em$nobloom_after   <- em$samples_ge1e4 > 0 & em$n_ge1e4_after == 0
  em$ge5 <- em$samples_ge1e4 >= min_samples_group
  em$lowinc_before <- em$ge5 & em$share_samples_ge1e4_before < 0.5
  em$lowinc_after  <- em$ge5 & em$share_samples_ge1e4_after < 0.5
  # Checks: a changed month has a raised cell, so its exposure rises and nothing falls; the
  # sample counts per month equal the #6 table; the headline numbers equal the prototype.
  stopifnot(all(em$exposure_added >= 0), identical(em$exposure_added > 0, em$changed),
            all(em$n_ge1e4_added >= 0), all(em$n_ge1e5_added >= 0), all(em$n_ge1e6_added >= 0),
            identical(sB$n_ge1e4, sA$n_ge1e4), all(sA$in_ge1e4 >= sB$in_ge1e4), all(sA$in_high >= sB$in_high),
            all(em$samples_ge1e4 == tab6$n_pos_1e4_water[m6]),
            sum(em$changed) == expected$n_changed,
            sum(em$samples_ge1e4) == expected$samples_ge1e4, sum(em$samples_ge1e4_in_before) == expected$in_before, sum(em$samples_ge1e4_in_after) == expected$in_after,
            sum(em$samples_high) == expected$samples_high, sum(em$samples_high_in_before) == expected$high_in_before, sum(em$samples_high_in_after) == expected$high_in_after,
            round(sum(em$exposure_before)) == expected$exposure_before,
            sum(em$ge5) == expected$n_ge5, sum(em$lowinc_before) == expected$n_lowinc_before, sum(em$lowinc_after) == expected$n_lowinc_after,
            sum(em$nobloom_before) == expected$n_nobloom_before, sum(em$nobloom_after) == expected$n_nobloom_after,
            sum(em$all_zero_before) == expected$n_allzero, sum(em$all_zero_after) == expected$n_allzero)
  write.csv(round_cols(em), file.path(dir_tab, "examine_months_issue10.csv"), row.names = FALSE)
  cat(sprintf("MODIS months: %d, changed by the rule: %d; samples >= 10,000 cells/L (water cells) %s, included %s -> %s (%.1f%% -> %.1f%%); exposure %s -> %s (x %.3f)\n",
              nrow(em), sum(em$changed), fmt_n(sum(em$samples_ge1e4)), fmt_n(sum(em$samples_ge1e4_in_before)), fmt_n(sum(em$samples_ge1e4_in_after)),
              100 * sum(em$samples_ge1e4_in_before) / sum(em$samples_ge1e4), 100 * sum(em$samples_ge1e4_in_after) / sum(em$samples_ge1e4),
              fmt_n(round(sum(em$exposure_before))), fmt_n(round(sum(em$exposure_after))), sum(em$exposure_after) / sum(em$exposure_before)))

  # Sums by year and by month group.
  sum_block <- function(d) {
    r <- data.frame(n_months = nrow(d), months_changed = sum(d$changed), months_all_zero = sum(d$all_zero_before),
                    a1e4_km2_before = sum(d$a1e4_km2_before), a1e4_km2_after = sum(d$a1e4_km2_after),
                    exposure_before = sum(d$exposure_before), exposure_after = sum(d$exposure_after),
                    exposure_ratio = if (sum(d$exposure_before) > 0) sum(d$exposure_after) / sum(d$exposure_before) else NA_real_,
                    months_ge1e4_before = sum(d$n_ge1e4_before > 0), months_ge1e4_after = sum(d$n_ge1e4_after > 0))
    for (k in names(thr)) { r[[paste0("cellmonths_", k, "_before")]] <- sum(d[[paste0("n_", k, "_before")]]); r[[paste0("cellmonths_", k, "_after")]] <- sum(d[[paste0("n_", k, "_after")]]) }
    share <- function(num, den) if (den > 0) round(num / den, 3) else NA_real_
    r$samples_ge1e4 <- sum(d$samples_ge1e4); r$samples_ge1e4_in_before <- sum(d$samples_ge1e4_in_before); r$samples_ge1e4_in_after <- sum(d$samples_ge1e4_in_after)
    r$share_samples_ge1e4_before <- share(r$samples_ge1e4_in_before, r$samples_ge1e4); r$share_samples_ge1e4_after <- share(r$samples_ge1e4_in_after, r$samples_ge1e4)
    r$samples_high <- sum(d$samples_high); r$samples_high_in_before <- sum(d$samples_high_in_before); r$samples_high_in_after <- sum(d$samples_high_in_after)
    r$share_samples_high_before <- share(r$samples_high_in_before, r$samples_high); r$share_samples_high_after <- share(r$samples_high_in_after, r$samples_high)
    r
  }
  ann <- do.call(rbind, lapply(split(em, em$year), function(d) cbind(year = d$year[1], sum_block(d))))
  rownames(ann) <- NULL
  write.csv(round_cols(ann), file.path(dir_tab, "examine_annual_issue10.csv"), row.names = FALSE)
  groups <- list(months, months[em$year <= 2011], months[em$year >= 2022], months[em$ge5], months[em$lowinc_before], months[em$nobloom_before])
  names(groups) <- c(sprintf("all %d MODIS months", length(months)),
                     sprintf("the %d months of 2002-2011", sum(em$year <= 2011)),
                     sprintf("the %d months of 2022-12 and 2025", sum(em$year >= 2022)),
                     sprintf("the %d months with at least %d water samples >= 10,000 cells/L", sum(em$ge5), min_samples_group),
                     sprintf("the %d of those with under half of them included before", sum(em$lowinc_before)),
                     sprintf("the %d months with such samples but no cell >= 10,000 cells/L before", sum(em$nobloom_before)))
  grp <- do.call(rbind, lapply(names(groups), function(lab) cbind(group = lab, sum_block(em[em$yrmo %in% groups[[lab]], ]), stringsAsFactors = FALSE)))
  rownames(grp) <- NULL
  write.csv(round_cols(grp), file.path(dir_tab, "examine_groups_issue10.csv"), row.names = FALSE)

  # The samples >= 10,000 cells/L the MODIS footprint excludes: where they are, and which
  # ones the rule recovers.
  j <- match(pw$yrmo, months); inB <- B[cbind(pw$cell5, j)] > 0; inA <- A[cbind(pw$cell5, j)] > 0
  g <- pw$ge1e4
  dist_g <- dist_coast_km(pw$lon[g], pw$lat[g])
  ex_rows <- which(g & !inB)
  excl <- data.frame(yrmo = pw$yrmo[ex_rows], lon = round(pw$lon[ex_rows], 5), lat = round(pw$lat[ex_rows], 5), cells = pw$cells[ex_rows],
                     class = pw$class[ex_rows], cell5 = pw$cell5[ex_rows], in_set = set[pw$cell5[ex_rows]],
                     dist_coast_km = round(dist_coast_km(pw$lon[ex_rows], pw$lat[ex_rows]), 2), included_after = inA[ex_rows], stringsAsFactors = FALSE)
  stopifnot(nrow(excl) == expected$n_excluded, sum(excl$in_set) == expected$excluded_in_set, sum(excl$included_after) == expected$excluded_recovered,
            all(excl$in_set[excl$included_after]))
  write.csv(excl, file.path(dir_tab, "excluded_samples_issue10.csv"), row.names = FALSE)
  cat(sprintf("Excluded samples >= 10,000 cells/L: %d; %d in the set, %d recovered by the rule; distance to the coast median %.1f km, %d%% within 2 km, %d%% within 5 km, %d%% within 10 km; still excluded after: %d (median %.1f km)\n",
              nrow(excl), sum(excl$in_set), sum(excl$included_after), median(excl$dist_coast_km),
              round(100 * mean(excl$dist_coast_km <= 2)), round(100 * mean(excl$dist_coast_km <= 5)), round(100 * mean(excl$dist_coast_km <= 10)),
              sum(!excl$included_after), median(excl$dist_coast_km[!excl$included_after])))
  # By distance band: all water samples >= 10,000 cells/L of the MODIS months.
  bg <- band_of(dist_g); inBg <- inB[g]; inAg <- inA[g]; setg <- set[pw$cell5[g]]
  bands <- data.frame(band = band_lv, stringsAsFactors = FALSE)
  bands$n_samples_ge1e4   <- as.vector(table(bg))
  bands$n_in_set          <- as.vector(table(bg[setg]))
  bands$excluded_before   <- as.vector(table(bg[!inBg]))
  bands$excluded_in_set   <- as.vector(table(bg[!inBg & setg]))
  bands$recovered         <- as.vector(table(bg[!inBg & inAg]))
  bands$excluded_after    <- as.vector(table(bg[!inAg]))
  bands$share_included_before <- round(1 - bands$excluded_before / bands$n_samples_ge1e4, 3)
  bands$share_included_after  <- round(1 - bands$excluded_after / bands$n_samples_ge1e4, 3)
  bands <- rbind(bands, data.frame(band = "all", n_samples_ge1e4 = sum(bands$n_samples_ge1e4), n_in_set = sum(bands$n_in_set),
                                   excluded_before = sum(bands$excluded_before), excluded_in_set = sum(bands$excluded_in_set), recovered = sum(bands$recovered),
                                   excluded_after = sum(bands$excluded_after),
                                   share_included_before = round(1 - sum(bands$excluded_before) / sum(bands$n_samples_ge1e4), 3),
                                   share_included_after = round(1 - sum(bands$excluded_after) / sum(bands$n_samples_ge1e4), 3), stringsAsFactors = FALSE))
  stopifnot(bands$excluded_before[nrow(bands)] == nrow(excl), bands$recovered[nrow(bands)] == sum(excl$included_after))
  write.csv(bands, file.path(dir_tab, "excluded_bands_issue10.csv"), row.names = FALSE)

  # Does MODIS look at the coast? Months in which each set cell is MODIS-positive, and the
  # water cells MODIS never marks positive, by distance to the coast.
  pos_months  <- rowSums(B > 0, na.rm = TRUE)
  hull_months <- rowSums(Hm > 0, na.rm = TRUE)
  dist_w <- rep(NA_real_, n5); dist_w[water] <- dist_coast_km(xy5[water, 1], xy5[water, 2])
  cov <- data.frame(cell = which(set), lon = round(xy5[set, 1], 4), lat = round(xy5[set, 2], 4), depth_m = round(dv[set], 1),
                    dist_coast_km = round(dist_w[set], 2), months_modis_positive = pos_months[set], months_hull_positive = hull_months[set],
                    months_changed = rowSums(A[set, ] != B[set, ], na.rm = TRUE))
  stopifnot(sum(cov$months_modis_positive > 0) == expected$set_cells_modis_pos)
  write.csv(cov, file.path(dir_tab, "modis_coverage_issue10.csv"), row.names = FALSE)
  bw <- band_of(dist_w[water]); never <- pos_months[water] == 0
  never_tab <- data.frame(band = band_lv, water_cells = as.vector(table(bw)), never_modis_positive = as.vector(table(bw[never])), stringsAsFactors = FALSE)
  never_tab$share_never <- round(never_tab$never_modis_positive / never_tab$water_cells, 3)
  never_tab$set_cells <- as.vector(table(bw[set[water]]))
  never_tab$set_cells_never <- as.vector(table(bw[set[water] & never]))
  write.csv(never_tab, file.path(dir_tab, "modis_never_positive_bands_issue10.csv"), row.names = FALSE)
  cat(sprintf("Set cells MODIS-positive in at least one of the %d months: %d of %d; water cells never MODIS-positive: %d (median %.0f km from the coast, %d within 5 km)\n",
              length(months), sum(cov$months_modis_positive > 0), nrow(cov), sum(never), median(dist_w[water][never]), sum(never & dist_w[water] <= 5)))

  # Fig 1: the months with the largest gain in samples included, then the months with
  # samples >= 10,000 cells/L but no such cell: samples | MODIS-clipped | hybrid | hull-clipped.
  gain <- em$samples_ge1e4_in_after - em$samples_ge1e4_in_before
  top  <- em$yrmo[order(-gain, em$yrmo)][seq_len(fig1_top)]
  fig1_months <- c(top, setdiff(em$yrmo[em$nobloom_before], top))
  pts$in_before <- FALSE; pts$in_before[pts$water] <- inB   # pw is pts[pts$water, ] in the same order
  draw_samples_panel <- function(ym, main) {
    q <- pts[pts$yrmo == ym, ]
    base_panel(main); rect(xlim[1], ylim[1], xlim[2], ylim[2], col = "white", border = NA); draw_land()
    z0 <- q[q$cells == 0, ]; points(z0$lon, z0$lat, pch = ".", cex = 1.6, col = "gray45")
    pp <- q[q$cells > 0, ]; pp <- pp[order(pp$cells), ]
    bins <- cut(pp$cells, class_brks[-1], labels = FALSE, include.lowest = TRUE)
    bord <- ifelse(pp$ge1e4 & pp$water & !pp$in_before, "red", "black")
    points(pp$lon, pp$lat, pch = 21, bg = spal[bins], col = bord, cex = 0.75, lwd = 0.9)
    hi <- q[q$cells >= thr_bloom & q$water, ]
    info_box(c(class_lines(class_counts_v(q$cells)),
               sprintf(">= 10,000 on water: %d, %d outside the MODIS footprint", nrow(hi), sum(!hi$in_before)),
               sprintf("%d on template land", sum(!q$water))))
    box()
  }
  draw_row <- function(ym) {
    lab <- paste0(substr(ym, 1, 4), "-", substr(ym, 5, 6)); k <- match(ym, months); r <- em[k, ]
    draw_samples_panel(ym, sprintf("%s: FWC samples (fit %s, %s nFLH polygons)", lab, r$fit_status, ifelse(is.na(r$modis_n_polys), "no", r$modis_n_polys)))
    draw_map_panel(B[, k], sprintf("before (MODIS-clipped): %s km2", fmt_n(round(r$a1e4_km2_before))),
                   extra = sprintf(">= 10k samples inside: %d / %d", r$samples_ge1e4_in_before, r$samples_ge1e4))
    draw_map_panel(A[, k], sprintf("after (hybrid mask5): %s km2 (+%s)", fmt_n(round(r$a1e4_km2_after)), fmt_n(round(r$a1e4_km2_after) - round(r$a1e4_km2_before))),
                   diff_from = B[, k], extra = sprintf("inside: %d / %d; %d cells changed", r$samples_ge1e4_in_after, r$samples_ge1e4, r$cells_changed))
    draw_map_panel(Hm[, k], sprintf("hull-clipped: %s km2 (set shaded)", fmt_n(round(area_ge(Hm[, k, drop = FALSE], thr_bloom)))), shade = set,
                   extra = sprintf("inside: %d / %d", samples_of(Hm[, k, drop = FALSE], pw[pw$yrmo == ym, ], ym)$in_ge1e4, r$samples_ge1e4))
  }
  pages <- split(fig1_months, ceiling(seq_along(fig1_months) / fig1_per_page))
  draw_fig1_page <- function(i) {
    par(mfrow = c(fig1_per_page, 4), mar = c(0.4, 0.5, 1.5, 0.5), oma = c(0.3, 0, 4.4, 0))
    for (ym in pages[[i]]) draw_row(ym)
    mtext(sprintf("Issue #10: the %d MODIS months with the largest gain in samples included, then the %d with samples >= 10,000 cells/L but no such cell (page %d of %d): samples | MODIS-clipped (the 6 Oct 2026 map) | hybrid mask5 | hull-clipped",
                  fig1_top, length(fig1_months) - fig1_top, i, length(pages)), outer = TRUE, cex = 0.85, font = 2, line = 2.9)
    mtext("km2 in the titles = bloom area >= 10,000 cells/L (+ = added by the hybrid). Orange = cells the hybrid changed. Purple shading in the hull column = the mask5 set (VIIRS no-data mask or within 5 km of the coast).",
          outer = TRUE, cex = 0.7, line = 1.6)
    mtext("Samples: fill = FWC class (viridis, light = background to dark = > 1,000,000 cells/L); red border = a water sample >= 10,000 cells/L outside the MODIS footprint. Maps: pipeline palette, white below 10,000 cells/L.",
          outer = TRUE, cex = 0.7, line = 0.5)
  }
  fig1_w <- 10; fig1_h <- 2.4 * fig1_per_page + 1.3
  file_fig1 <- file.path(dir_fig, "fig1_examine_months_issue10.pdf")
  ok_pdf <- write_pdf(file_fig1, width = fig1_w, height = fig1_h, function() for (i in seq_along(pages)) draw_fig1_page(i))
  if (ok_pdf) message("Fig 1 written: ", file_fig1)
  png_dir <- Sys.getenv("RT_QA_PNG_DIR", "")
  if (nzchar(png_dir)) for (i in seq_along(pages)) {
    png(file.path(png_dir, sprintf("fig1_examine_p%d.png", i)), width = fig1_w, height = fig1_h, units = "in", res = 70)
    draw_fig1_page(i); invisible(dev.off())
  }

  # Fig 2: the series over the MODIS months (2002-2011, then 2022-12 and 2025 after a gap
  # mark), the #11 five-panel layout: exposure (linear), three cell counts, share of
  # samples included; before black, after purple; all-zero MODIS months shaded.
  zero_col <- grDevices::adjustcolor("gray40", 0.3)
  draw_series <- function(d, title) {
    n <- nrow(d); x <- seq_len(n); few <- d$samples_ge1e4 < min_samples_group
    gap <- which(diff(d$year) > 1)
    panels <- list(list(b = d$exposure_before / 1e6, a = d$exposure_after / 1e6, lab = "million cells/L (sum over water cells)", main = sprintf("Total exposure: cells/L summed over the %s water cells", fmt_n(sum(water)))),
                   list(b = d$n_ge1e4_before, a = d$n_ge1e4_after, lab = "cells", main = "Grid cells at or above 10,000 cells/L"),
                   list(b = d$n_ge1e5_before, a = d$n_ge1e5_after, lab = "cells", main = "Grid cells at or above 100,000 cells/L"),
                   list(b = d$n_ge1e6_before, a = d$n_ge1e6_after, lab = "cells", main = "Grid cells at or above 1,000,000 cells/L"),
                   list(b = replace(d$share_samples_ge1e4_before, few, NA), a = replace(d$share_samples_ge1e4_after, few, NA), lab = "share of samples",
                        main = sprintf("Share of the in-situ samples >= 10,000 cells/L (water cells) that the projection includes, months with at least %d such samples", min_samples_group), pts = TRUE))
    par(mfrow = c(length(panels), 1), mar = c(2.8, 4.6, 2.2, 0.6), oma = c(0, 0, 1.8, 0), mgp = c(3, 0.6, 0))
    for (i in seq_along(panels)) {
      p <- panels[[i]]; yb <- p$b; ya <- p$a
      yl <- if (isTRUE(p$pts)) c(0, 1.04) else c(0, max(c(yb, ya), 1) * 1.08)
      plot(NA, xlim = c(0.5, n + 0.5), ylim = yl, xlab = "", ylab = p$lab, main = p$main, cex.main = 0.95, axes = FALSE, xaxs = "i", yaxs = "i")
      zm <- which(d$all_zero_before); rect(zm - 0.5, yl[1], zm + 0.5, yl[2], col = zero_col, border = NA)
      abline(v = gap + 0.5, lty = 2, col = "gray40")
      if (isTRUE(p$pts)) { points(x, ya, col = "purple3", pch = 1, cex = 0.8, lwd = 1.2); points(x, yb, col = "black", pch = 16, cex = 0.7) } else {
        lines(x, ya, col = "purple3", lwd = 1.8); lines(x, yb, col = "black", lwd = 1.6) }
      at <- which(d$month == 1 | c(TRUE, diff(d$year) > 1)); at <- sort(unique(at))
      labs <- ifelse(d$month[at] == 1, as.character(d$year[at]), sprintf("%d-%02d", d$year[at], d$month[at]))
      axis(1, at = at, labels = labs, cex.axis = 0.8)
      axis(2, las = 1, cex.axis = 0.85)
      box()
      if (i == 1) legend("topleft", legend = c("before: MODIS only (6 Oct 2026 maps)", "after: nearshore hybrid mask5", "MODIS map all zero", "gap in the MODIS-served months"),
                         col = c("black", "purple3", NA, "gray40"), lwd = c(1.6, 1.8, NA, 1), lty = c(1, 1, NA, 2),
                         fill = c(NA, NA, zero_col, NA), border = NA, cex = 0.78, bg = "white", box.col = "gray60", ncol = 2)
      if (isTRUE(p$pts)) legend("bottomleft", legend = c("before: MODIS only", "after: hybrid"), col = c("black", "purple3"), pch = c(16, 1), pt.cex = c(0.7, 0.8), cex = 0.78, bg = "white", box.col = "gray60", ncol = 2)
    }
    mtext(title, outer = TRUE, cex = 0.9, font = 2, line = 0.4)
  }
  png(file.path(dir_fig, "fig2_examine_series_issue10.png"), width = 13, height = 13.5, units = "in", res = 150)
  draw_series(em, sprintf("Exposure per monthly map, the %d MODIS-served months (2002-07 to 2011-12, 2022-12, 2025-01 to 2025-09): MODIS-only vs nearshore hybrid mask5", nrow(em)))
  invisible(dev.off())

  # Fig 3: the excluded samples on the map (recovered or not) and their distance to the coast.
  png(file.path(dir_fig, "fig3_excluded_samples_issue10.png"), width = 13, height = 6.6, units = "in", res = 150)
  layout(matrix(1:2, 1), widths = c(1.15, 1))
  par(mar = c(3.2, 3.2, 2.6, 0.6), oma = c(0, 0, 1.6, 0))
  base_panel(sprintf("The %d water samples >= 10,000 cells/L outside the MODIS footprint (set shaded)", nrow(excl)), axes = TRUE, cex_main = 0.9)
  rect(xlim[1], ylim[1], xlim[2], ylim[2], col = "white", border = NA)
  image(xs, ys, to_z(ifelse(set, 1, NA)), col = grDevices::adjustcolor("mediumpurple", 0.35), add = TRUE, useRaster = TRUE); draw_land()
  o <- order(excl$included_after)   # recovered drawn last
  points(excl$lon[o], excl$lat[o], pch = 21, cex = 0.7, lwd = 0.6, col = "gray20",
         bg = ifelse(excl$included_after[o], grDevices::adjustcolor("purple3", 0.8), grDevices::adjustcolor("red", 0.6)))
  legend("bottomleft", legend = c(sprintf("recovered by the rule (%d; in the set)", sum(excl$included_after)), sprintf("still excluded (%d; MODIS looked and saw nothing)", sum(!excl$included_after)), "the mask5 set"),
         pch = c(21, 21, 22), pt.bg = c(grDevices::adjustcolor("purple3", 0.8), grDevices::adjustcolor("red", 0.6), grDevices::adjustcolor("mediumpurple", 0.35)), pt.cex = c(1, 1, 1.6),
         col = c("gray20", "gray20", NA), cex = 0.8, bg = "white", box.col = "gray60")
  box()
  par(mar = c(4.2, 4.4, 2.6, 1))
  dd <- excl$dist_coast_km
  plot(NA, xlim = c(0, 60), ylim = c(0, 1), xlab = "distance to the coast, km (Natural Earth 1:10m; x axis cut at 60 km)", ylab = "share of samples within that distance",
       main = "Distance to the coast of the excluded samples (ECDF)", cex.main = 0.9, las = 1)
  abline(v = c(2, 5, 10), col = "gray75", lty = 3)
  lines(ecdf(dd), col = "black", lwd = 1.8, do.points = FALSE, verticals = TRUE)
  lines(ecdf(dd[excl$included_after]), col = "purple3", lwd = 1.8, do.points = FALSE, verticals = TRUE)
  lines(ecdf(dd[!excl$included_after]), col = "red", lwd = 1.8, do.points = FALSE, verticals = TRUE)
  dist_all <- dist_g
  lines(ecdf(dist_all), col = "gray50", lwd = 1.4, lty = 2, do.points = FALSE, verticals = TRUE)
  legend("bottomright", legend = c(sprintf("excluded before (%d; median %.1f km)", length(dd), median(dd)),
                                   sprintf("of which recovered (%d; median %.1f km)", sum(excl$included_after), median(dd[excl$included_after])),
                                   sprintf("of which still excluded (%d; median %.1f km)", sum(!excl$included_after), median(dd[!excl$included_after])),
                                   sprintf("all %s water samples >= 10,000 cells/L (median %.1f km)", fmt_n(length(dist_all)), median(dist_all))),
         col = c("black", "purple3", "red", "gray50"), lwd = c(1.8, 1.8, 1.8, 1.4), lty = c(1, 1, 1, 2), cex = 0.8, bg = "white", box.col = "gray60")
  mtext(sprintf("Issue #10: where the samples the MODIS footprint cuts are, and what the mask5 rule recovers (%d MODIS-served months)", length(months)), outer = TRUE, cex = 0.95, font = 2, line = 0.3)
  invisible(dev.off())

  # Markdown summary for #10.
  g_cols <- c("group", "n_months", "months_changed", "months_all_zero", "a1e4_km2_before", "a1e4_km2_after", "exposure_before", "exposure_after", "exposure_ratio",
              "cellmonths_ge1e4_before", "cellmonths_ge1e4_after", "cellmonths_ge1e5_before", "cellmonths_ge1e5_after", "cellmonths_ge1e6_before", "cellmonths_ge1e6_after",
              "samples_ge1e4", "samples_ge1e4_in_before", "samples_ge1e4_in_after", "share_samples_ge1e4_before", "share_samples_ge1e4_after",
              "samples_high", "share_samples_high_before", "share_samples_high_after")
  gall <- grp[1, ]
  top_tab <- em[match(fig1_months, em$yrmo), c("yrmo", "fit_status", "modis_n_polys", "cells_changed", "a1e4_km2_before", "a1e4_km2_after", "exposure_before", "exposure_after",
                                                "n_ge1e4_before", "n_ge1e4_after", "samples_ge1e4", "samples_ge1e4_in_before", "samples_ge1e4_in_after")]
  md <- c("# Issue #10: the mask5 nearshore rule on the MODIS months (examine stage)", "",
          sprintf("Produced by `docs/issue10_modis-nearshore-hybrid/check_modis_hybrid_issue10.R` (stage `examine`) from the stacks of the last pipeline run: the MODIS-clipped layers of the %d months the cascade serves from MODIS (equal to the delivered 6 October 2026 maps for those months, checked), the hull-clipped layers of the same months and the `mask5` set (%d cells, %s km2). The hybrid is max(MODIS-clipped, hull-clipped) inside the set and the MODIS-clipped layer outside it. Bloom area = km2 of cells at or above 10,000 cells/L; exposure = the plain sum of cells/L over the %s water cells; samples included = water-cell samples at or above 10,000 cells/L (and the high class, above 1,000,000) whose cell is non-zero in the map. Yearly and group totals are sums over the months.",
                  length(months), sum(set), fmt_n(round(sum(cell_km2[set]))), fmt_n(sum(water))),
          "", "## Overall", "",
          sprintf("- Over the %d MODIS months the rule changes %d maps, raises the summed bloom area by %.1f%% (%s to %s km2) and total exposure by %.1f%% (%s to %s cells/L summed), and lifts the share of the in-situ water samples >= 10,000 cells/L that the projection includes from %.1f%% to %.1f%% (%s to %s of %s; +%.1f percentage points); for the high samples (> 1,000,000 cells/L) from %.1f%% to %.1f%% (of %s).",
                  gall$n_months, gall$months_changed, 100 * (gall$a1e4_km2_after / gall$a1e4_km2_before - 1), fmt_n(round(gall$a1e4_km2_before)), fmt_n(round(gall$a1e4_km2_after)),
                  100 * (gall$exposure_ratio - 1), fmt_n(round(gall$exposure_before)), fmt_n(round(gall$exposure_after)),
                  100 * gall$share_samples_ge1e4_before, 100 * gall$share_samples_ge1e4_after, fmt_n(gall$samples_ge1e4_in_before), fmt_n(gall$samples_ge1e4_in_after), fmt_n(gall$samples_ge1e4),
                  100 * (gall$share_samples_ge1e4_after - gall$share_samples_ge1e4_before), 100 * gall$share_samples_high_before, 100 * gall$share_samples_high_after, fmt_n(gall$samples_high)),
          sprintf("- MODIS has no coastal no-data band: %d of the %d set cells are MODIS-positive in at least one of the %d months; the %s water cells MODIS never marks positive sit a median %.0f km from the coast (%d of them within 5 km).",
                  sum(cov$months_modis_positive > 0), nrow(cov), length(months), fmt_n(sum(never)), median(dist_w[water][never]), sum(never & dist_w[water] <= 5)),
          sprintf("- Of the %d excluded samples >= 10,000 cells/L, %d lie in the set and %d of those are recovered; the rest are offshore (median %.1f km from the coast; %d%% of the excluded within 5 km) where MODIS looked and saw nothing. Within 5 km of the coast the included share goes %.1f%% -> %.1f%%, beyond 5 km %.1f%% -> %.1f%%.",
                  nrow(excl), sum(excl$in_set), sum(excl$included_after), median(excl$dist_coast_km), round(100 * mean(excl$dist_coast_km <= 5)),
                  100 * mean(inBg[dist_g <= 5]), 100 * mean(inAg[dist_g <= 5]), 100 * mean(inBg[dist_g > 5]), 100 * mean(inAg[dist_g > 5])),
          sprintf("- Months with at least %d such samples and under half of them included: %d before, %d after. Months with such samples but no cell >= 10,000 cells/L: %d before, %d after. All-zero MODIS maps: %d before and after (no hull inside the set in those months).",
                  min_samples_group, sum(em$lowinc_before), sum(em$lowinc_after), sum(em$nobloom_before), sum(em$nobloom_after), sum(em$all_zero_before)),
          "", "## Totals by month group (`tables/examine_groups_issue10.csv`)", "",
          md_table(round_cols(grp[, g_cols]), 3),
          "", "## By year (`tables/examine_annual_issue10.csv`; sums over the months of the year)", "",
          md_table(round_cols(ann[, c("year", g_cols[-1])]), 3),
          "", "## Samples >= 10,000 cells/L by distance to the coast (`tables/excluded_bands_issue10.csv`)", "",
          md_table(bands, 3),
          "", sprintf("## The %d months of fig 1 (`tables/examine_months_issue10.csv`): the %d largest gains in samples included, then the %d with samples but no bloom cell", length(fig1_months), fig1_top, length(fig1_months) - fig1_top), "",
          md_table(round_cols(top_tab), 0),
          "", "## Water cells MODIS never marks positive, by distance to the coast (`tables/modis_never_positive_bands_issue10.csv`)", "",
          md_table(never_tab, 3),
          "")
  writeLines(md, file.path(dir_cmt, "examine_summary.md"))
  cat(md, sep = "\n")
  message("Stage examine OK: ", sum(em$changed), " of ", nrow(em), " MODIS months change; samples included ",
          round(100 * gall$share_samples_ge1e4_before, 1), "% -> ", round(100 * gall$share_samples_ge1e4_after, 1), "%.")
}
# Shared by the stages after a pipeline run ----------------------------------------
if (stage %in% c("regress", "mask5")) {
  # The run log: the block of the latest run in the newest run_<date>.log.
  run_block <- local({
    lf <- list.files(dir_out, pattern = "^run_[0-9]{8}[.]log$", full.names = TRUE)
    if (length(lf) == 0) return(character(0))
    x <- readLines(lf[which.max(file.mtime(lf))], warn = FALSE)
    s <- grep("Starting run", x); if (length(s) == 0) return(x)
    x[s[length(s)]:length(x)]
  })
  run_minutes <- local({
    ts <- as.POSIXct(sub("^\\[([^]]+)\\].*", "\\1", run_block[grepl("^\\[", run_block)]), format = "%Y-%m-%d %H:%M:%S")
    if (length(ts) < 2) NA_real_ else round(as.numeric(difftime(max(ts), min(ts), units = "mins")), 1)
  })
  # MD5 of the 504 ASCII files against the 6 Oct 2026 baseline and the issue #11 "mask5"
  # run (VIIRS hybrid on, no MODIS rule), joined to clipping_source.csv of the run.
  md5_table <- function() {
    base <- read.csv(file.path(dir_tab11, "md5_baseline_issue11.csv"), colClasses = "character")
    m11  <- read.csv(file.path(dir_tab11, "md5_mask5_issue11.csv"), colClasses = "character")
    stopifnot(nrow(base) == expected$n_ascii, identical(sort(base$yrmo), sort(m11$yrmo)))
    f <- file.path(dir_ascii, base$file); stopifnot(all(file.exists(f)))
    extra <- setdiff(list.files(dir_ascii, pattern = "[.]asc$"), base$file)
    if (length(extra) > 0) stop("Unexpected ASCII files: ", paste(extra, collapse = ", "), call. = FALSE)
    stopifnot(identical(sort(cs$yrmo), sort(base$yrmo)), all(c("hybrid", "hybrid_modis", "hybrid_changed", "use") %in% names(cs)))
    m <- match(base$yrmo, cs$yrmo); j <- match(base$yrmo, m11$yrmo)
    d <- data.frame(yrmo = base$yrmo, file = base$file, use = cs$use[m], hybrid = cs$hybrid[m], hybrid_modis = cs$hybrid_modis[m],
                    hybrid_changed = cs$hybrid_changed[m], md5_6oct = base$md5, md5_runA_ref = m11$md5_after[j],
                    md5_now = unname(tools::md5sum(f)), stringsAsFactors = FALSE)
    d$changed_vs_runA <- d$md5_now != d$md5_runA_ref
    d$changed_vs_6oct <- d$md5_now != d$md5_6oct
    d
  }
  report_run <- function(d) {
    use_counts <- table(d$use)
    cat("clipping_source.csv use:", paste(names(use_counts), as.integer(use_counts), collapse = ", "), "\n")
    cat("ASCII files changed vs the #11 mask5 run (= run A):", sum(d$changed_vs_runA), "of", nrow(d),
        "; vs the 6 Oct 2026 baseline:", sum(d$changed_vs_6oct), "\n")
    cat("Run log:", if (length(run_block)) paste0(length(run_block), " lines, ", run_minutes, " min") else "not found", "\n")
    cat(grep("Nearshore|Hybrid|Step 1|Hulls:|Run complete", run_block, value = TRUE), sep = "\n")
  }
}

# Stage regress ----------------------------------------------------------------------
if (stage == "regress") {
  d <- md5_table()
  write.csv(d, file.path(dir_tab, "md5_runA_issue10.csv"), row.names = FALSE)
  report_run(d)
  use_counts <- table(factor(d$use, levels = names(expected$use_runA)))
  # clipping_source.csv equals the #11 mask5 run's apart from the new all-FALSE column.
  cs11 <- read.csv(file.path(dir_hoard11, "after", "clipping_source.csv"), stringsAsFactors = FALSE)
  cs11$yrmo <- sub("^X", "", cs11$yrmo)
  cols <- c("yrmo", "pred", "viirs", "modis", "hybrid", "hybrid_changed", "use")
  norm_df <- function(x) { x <- x[order(x$yrmo), cols]; rownames(x) <- NULL; x }
  stopifnot(sum(d$changed_vs_runA) == 0, all(as.integer(use_counts) == expected$use_runA),
            !any(d$hybrid_modis %in% TRUE), sum(d$hybrid_changed %in% TRUE) == expected$n_changed_viirs,
            identical(norm_df(cs), norm_df(cs11)),
            any(grepl("Nearshore rule mask5", run_block)), any(grepl("Nearshore rule \\(MODIS\\): none", run_block)),
            any(grepl("fwc_refresh = FALSE", run_block)))
  message("Stage regress OK: 0 of ", nrow(d), " ASCII files differ from the #11 mask5 run; use counts ",
          paste(names(use_counts), as.integer(use_counts), collapse = ", "), ".")
}

# Stage mask5 ------------------------------------------------------------------------
if (stage == "mask5") {
  d <- md5_table()
  write.csv(d, file.path(dir_tab, "md5_runB_issue10.csv"), row.names = FALSE)
  report_run(d)
  use_counts <- table(factor(d$use, levels = names(expected$use_runB)))
  chg <- d$changed_vs_runA
  stopifnot(all(as.integer(use_counts) == expected$use_runB),
            all(d$hybrid == (d$use == "hybrid")), all(d$hybrid_modis == (d$use == "hybrid_modis")),
            all(d$use[chg] == "hybrid_modis"), identical(chg, d$use == "hybrid_modis" & d$hybrid_changed %in% TRUE),
            sum(chg) == expected$n_changed, sum(d$hybrid_changed[d$use == "hybrid"] %in% TRUE) == expected$n_changed_viirs,
            any(grepl("Nearshore rule mask5", run_block)),
            any(grepl(sprintf("Hybrid \\(MODIS\\): %d of %d MODIS-served months changed", expected$n_changed, expected$n_modis), run_block)),
            any(grepl(sprintf("Hybrid: %d of %d VIIRS months changed", expected$n_changed_viirs, expected$n_viirs), run_block)),
            any(grepl("fwc_refresh = FALSE", run_block)))

  # The set, as in #11.
  mask_r <- raster::raster(file_mask)
  stopifnot(raster::compareRaster(depth, mask_r))
  mv <- raster::values(mask_r); set <- mv %in% 1
  stopifnot(all(is.na(mv) == land), sum(set) == expected$n_set, round(sum(cell_km2[set])) == expected$km2_set)

  # The MODIS hybrid stack against the MODIS- and hull-clipped stacks and the examine prototype.
  Mc <- read_mat(grd(one_file(dir_clipped, "_clipped_modis[.]grd$", "MODIS-clipped stack")))
  H  <- read_mat(grd(one_file(dir_clipped, "_clipped_hull[.]grd$", "hull-clipped stack")))
  Hy <- read_mat(grd(one_file(dir_clipped, "_clipped_hybrid_modis[.]grd$", "MODIS hybrid stack")))
  stopifnot(identical(colnames(Hy), months), all(months %in% colnames(Mc)), all(months %in% colnames(H)))
  B <- norm_map(Mc[, months]); Hm <- norm_map(H[, months])
  stopifnot(all(is.na(Hy) == land), same(Hy[!set, ], B[!set, ]), same(Hy[set, ], pmax(B[set, ], Hm[set, ])), all(Hy[water, ] >= B[water, ]))
  em <- read.csv(file.path(dir_tab, "examine_months_issue10.csv"), colClasses = c(yrmo = "character"), stringsAsFactors = FALSE)
  stopifnot(identical(em$yrmo, months))
  mH <- metrics_of(Hy); eH <- expo_of(Hy)
  pts <- load_samples(months); pw <- pts[pts$water, ]; sH <- samples_of(Hy, pw, months)
  cmp <- data.frame(yrmo = months,
                    fp_km2 = round(mH$fp_km2), fp_km2_proto = em$fp_km2_after,
                    a1e4_km2 = round(mH$a1e4_km2), a1e4_km2_proto = em$a1e4_km2_after,
                    a1e5_km2 = round(mH$a1e5_km2), a1e5_km2_proto = em$a1e5_km2_after,
                    max_cells = signif(mH$max_cells, 10), max_cells_proto = signif(em$max_cells_after, 10),
                    exposure = round(eH$exposure), exposure_proto = em$exposure_after,
                    n_ge1e4 = eH$n_ge1e4, n_ge1e4_proto = em$n_ge1e4_after,
                    n_ge1e5 = eH$n_ge1e5, n_ge1e5_proto = em$n_ge1e5_after,
                    n_ge1e6 = eH$n_ge1e6, n_ge1e6_proto = em$n_ge1e6_after,
                    cells_changed = colSums(Hy != B, na.rm = TRUE), cells_changed_proto = em$cells_changed,
                    in_ge1e4 = sH$in_ge1e4, in_ge1e4_proto = em$samples_ge1e4_in_after,
                    in_high = sH$in_high, in_high_proto = em$samples_high_in_after,
                    removed_cells = colSums(Hy == 0 & B > 0, na.rm = TRUE),
                    ascii_changed = chg[match(months, d$yrmo)], stringsAsFactors = FALSE)
  pairs <- c("fp_km2", "a1e4_km2", "a1e5_km2", "max_cells", "exposure", "n_ge1e4", "n_ge1e5", "n_ge1e6", "cells_changed", "in_ge1e4", "in_high")
  cmp$equal <- Reduce(`&`, lapply(pairs, function(k) cmp[[k]] == cmp[[paste0(k, "_proto")]]))
  write.csv(cmp, file.path(dir_tab, "hybrid_modis_vs_prototype_issue10.csv"), row.names = FALSE)
  cat("Months equal to the examine prototype on all", length(pairs), "metrics:", sum(cmp$equal), "of", nrow(cmp), "\n")
  if (any(!cmp$equal)) print(cmp[!cmp$equal, ])
  stopifnot(all(cmp$equal), all(cmp$removed_cells == 0), identical(cmp$ascii_changed, cmp$cells_changed > 0),
            sum(cmp$cells_changed > 0) == expected$n_changed)

  # The combined stack of the run: the MODIS-served months are the MODIS hybrid, every
  # other month equals the #11 mask5 run (VIIRS hybrid and hull months untouched).
  Cb   <- read_mat(grd(one_file(dir_combined, "_clipped_combined[.]grd$", "combined stack")))
  Ca11 <- read_mat(grd(one_file(file.path(dir_hoard11, "after", "combined"), "_clipped_combined[.]grd$", "#11 mask5 combined stack")))
  other <- setdiff(colnames(Cb), months)
  stopifnot(ncol(Cb) == expected$n_ascii, identical(colnames(Cb), colnames(Ca11)), same(Cb[, other], Ca11[, other]), same(Cb[, months], Hy))
  message("Stage mask5 OK: ", sum(chg), " ASCII files changed, all MODIS-served months with a nearshore hull; set ", sum(set),
          " cells; the MODIS hybrid equals the prototype in every month; VIIRS hybrid and hull months untouched.")
}

# Stage compare ----------------------------------------------------------------------
if (stage == "compare") {
  f0 <- one_file(file.path(dir_hoard11, "before", "combined"), "_clipped_combined[.]grd$", "6 Oct 2026 combined stack")
  fA <- one_file(file.path(dir_hoard, "before", "combined"),   "_clipped_combined[.]grd$", "run A combined stack")
  fB <- one_file(file.path(dir_hoard, "after", "combined"),    "_clipped_combined[.]grd$", "run B combined stack")
  M0 <- read_mat(grd(f0)); MA <- read_mat(grd(fA)); MB <- read_mat(grd(fB)); all_yrmo <- colnames(M0)
  stopifnot(identical(all_yrmo, colnames(MA)), identical(all_yrmo, colnames(MB)), ncol(M0) == expected$n_ascii,
            all(is.na(M0) == land), all(is.na(MA) == land), all(is.na(MB) == land))
  csB <- read.csv(file.path(dir_hoard, "after", "clipping_source.csv"), stringsAsFactors = FALSE); csB$yrmo <- sub("^X", "", csB$yrmo)
  mcs <- match(all_yrmo, csB$yrmo); stopifnot(!anyNA(mcs))
  use <- csB$use[mcs]; hyb_chg <- csB$hybrid_changed[mcs] %in% TRUE
  use_counts <- table(factor(use, levels = names(expected$use_runB)))
  is_modis <- use == "hybrid_modis"; is_viirs <- use == "hybrid"; is_hull <- use == "pred"
  stopifnot(all(as.integer(use_counts) == expected$use_runB), identical(sort(all_yrmo[is_modis]), months),
            same(MA[, !is_modis], MB[, !is_modis]), all(MB[water, ] >= MA[water, ]),
            same(M0[, !is_viirs], MA[, !is_viirs]), all(MA[water, ] >= M0[water, ]),
            sum(hyb_chg[is_modis]) == expected$n_changed, sum(hyb_chg[is_viirs]) == expected$n_changed_viirs)
  n_water <- sum(water)
  variants <- c(v6oct = "6 Oct 2026 (satellite only)", v11 = "VIIRS hybrid (#11)", v10 = "VIIRS + MODIS hybrids (#10)")
  Ms <- list(v6oct = M0, v11 = MA, v10 = MB)
  pts <- load_samples(all_yrmo); pw <- pts[pts$water, ]
  # expo_of() has its own n_ge1e4 (cells), so the sample counts get their own names.
  per <- lapply(Ms, function(M) { s <- samples_of(M, pw, all_yrmo)
    cbind(expo_of(M), samples_ge1e4 = s$n_ge1e4, in_ge1e4 = s$in_ge1e4, samples_high = s$n_high, in_high = s$in_high) })
  stopifnot(identical(per$v6oct$samples_ge1e4, per$v10$samples_ge1e4), all(per$v11$in_ge1e4 >= per$v6oct$in_ge1e4), all(per$v10$in_ge1e4 >= per$v11$in_ge1e4))
  m6 <- match(all_yrmo, tab6$yrmo); stopifnot(!anyNA(m6))
  rec <- data.frame(yrmo = all_yrmo, year = as.integer(substr(all_yrmo, 1, 4)), month = as.integer(substr(all_yrmo, 5, 6)),
                    use = use, hybrid_changed = hyb_chg, fit_status = tab6$fit_status[m6], viirs_status = tab6$viirs_status[m6], stringsAsFactors = FALSE)
  metrics <- c("exposure", "n_ge1e4", "n_ge1e5", "n_ge1e6", "in_ge1e4", "in_high")
  rec$samples_ge1e4 <- per$v6oct$samples_ge1e4; rec$samples_high <- per$v6oct$samples_high
  for (k in names(Ms)) for (mt in metrics) rec[[paste0(mt, "_", k)]] <- per[[k]][[mt]]
  write.csv(round_cols(rec), file.path(dir_tab, "record_months_issue10.csv"), row.names = FALSE)
  # The MODIS months of run B equal the examine stage.
  eg <- read.csv(file.path(dir_tab, "examine_groups_issue10.csv"), stringsAsFactors = FALSE)
  stopifnot(round(sum(rec$exposure_v10[is_modis])) == eg$exposure_after[1], sum(rec$in_ge1e4_v10[is_modis]) == eg$samples_ge1e4_in_after[1],
            round(sum(rec$exposure_v11[is_modis])) == eg$exposure_before[1], sum(rec$in_ge1e4_v11[is_modis]) == eg$samples_ge1e4_in_before[1])

  sum_block <- function(d) {
    r <- data.frame(n_months = nrow(d), months_changed_11 = sum(d$hybrid_changed & d$use == "hybrid"), months_changed_10 = sum(d$hybrid_changed & d$use == "hybrid_modis"))
    share <- function(num, den) if (den > 0) round(num / den, 3) else NA_real_
    for (k in names(Ms)) {
      r[[paste0("exposure_", k)]] <- sum(d[[paste0("exposure_", k)]])
      for (mt in c("n_ge1e4", "n_ge1e5", "n_ge1e6")) r[[paste0("cellmonths_", sub("^n_", "", mt), "_", k)]] <- sum(d[[paste0(mt, "_", k)]])
    }
    r$samples_ge1e4 <- sum(d$samples_ge1e4); r$samples_high <- sum(d$samples_high)
    for (k in names(Ms)) { r[[paste0("in_ge1e4_", k)]] <- sum(d[[paste0("in_ge1e4_", k)]]); r[[paste0("share_ge1e4_", k)]] <- share(r[[paste0("in_ge1e4_", k)]], r$samples_ge1e4) }
    for (k in names(Ms)) { r[[paste0("in_high_", k)]] <- sum(d[[paste0("in_high_", k)]]); r[[paste0("share_high_", k)]] <- share(r[[paste0("in_high_", k)]], r$samples_high) }
    r$exposure_ratio_11 <- if (r$exposure_v6oct > 0) round(r$exposure_v11 / r$exposure_v6oct, 3) else NA_real_
    r$exposure_ratio_10 <- if (r$exposure_v6oct > 0) round(r$exposure_v10 / r$exposure_v6oct, 3) else NA_real_
    r
  }
  ann <- do.call(rbind, lapply(split(rec, rec$year), function(d) cbind(year = d$year[1], clip_sources = paste(sort(unique(d$use)), collapse = "/"), sum_block(d))))
  rownames(ann) <- NULL
  write.csv(round_cols(ann), file.path(dir_tab, "record_annual_issue10.csv"), row.names = FALSE)
  groups <- list(all_yrmo, all_yrmo[is_hull], all_yrmo[is_viirs], all_yrmo[is_modis], all_yrmo[is_viirs | is_modis])
  names(groups) <- c(sprintf("all %d months 1985-2026", length(all_yrmo)), sprintf("the %d hull months", sum(is_hull)),
                     sprintf("the %d VIIRS months", sum(is_viirs)), sprintf("the %d MODIS months", sum(is_modis)),
                     sprintf("the %d satellite months", sum(is_viirs | is_modis)))
  grp <- do.call(rbind, lapply(names(groups), function(lab) cbind(group = lab, sum_block(rec[rec$yrmo %in% groups[[lab]], ]), stringsAsFactors = FALSE)))
  rownames(grp) <- NULL
  write.csv(round_cols(grp), file.path(dir_tab, "record_groups_issue10.csv"), row.names = FALSE)

  # Per cell over the MODIS months: cumulative exposure and cell-months >= 100,000 and 1,000,000 cells/L, run A vs run B.
  cum_b <- rowSums(MA[, is_modis]); cum_a <- rowSums(MB[, is_modis])
  n5_b <- rowSums(MA[, is_modis] >= 1e5); n5_a <- rowSums(MB[, is_modis] >= 1e5); n6_b <- rowSums(MA[, is_modis] >= 1e6); n6_a <- rowSums(MB[, is_modis] >= 1e6)
  cells <- data.frame(cell = which(water), lon = round(xy5[water, 1], 4), lat = round(xy5[water, 2], 4), depth_m = round(dv[water], 1),
                      exposure_before = cum_b[water], exposure_after = cum_a[water], exposure_added = (cum_a - cum_b)[water],
                      cellmonths_ge1e5_before = n5_b[water], cellmonths_ge1e5_after = n5_a[water],
                      cellmonths_ge1e6_before = n6_b[water], cellmonths_ge1e6_after = n6_a[water])
  write.csv(round_cols(cells), file.path(dir_tab, "cells_modis_issue10.csv"), row.names = FALSE)

  # Fig 4: the whole record, three variants, the #11 five-panel layout.
  use_col <- c(pred = grDevices::adjustcolor("gray40", 0.12), hybrid_modis = grDevices::adjustcolor("steelblue", 0.18), hybrid = grDevices::adjustcolor("gold", 0.22))
  zero_col <- grDevices::adjustcolor("gray40", 0.3); miss_col <- grDevices::adjustcolor("red", 0.25)
  vcol <- c(v6oct = "black", v11 = "dodgerblue3", v10 = "purple3"); vpch <- c(v6oct = 16, v11 = 2, v10 = 1)
  min_samples_share <- 5L
  draw_record <- function(d, title) {
    n <- nrow(d); x <- seq_len(n); few <- d$samples_ge1e4 < min_samples_share
    panel_of <- function(mt, lab, main, pts = FALSE, div = 1) list(y = lapply(names(Ms), function(k) { y <- d[[paste0(mt, "_", k)]] / div; if (pts) { y <- y / d$samples_ge1e4; y[few] <- NA }; y }), lab = lab, main = main, pts = pts)
    panels <- list(panel_of("exposure", "million cells/L (sum over water cells)", sprintf("Total exposure: cells/L summed over the %s water cells", fmt_n(n_water)), div = 1e6),
                   panel_of("n_ge1e4", "cells", "Grid cells at or above 10,000 cells/L"),
                   panel_of("n_ge1e5", "cells", "Grid cells at or above 100,000 cells/L"),
                   panel_of("n_ge1e6", "cells", "Grid cells at or above 1,000,000 cells/L"),
                   panel_of("in_ge1e4", "share of samples", sprintf("Share of the in-situ samples >= 10,000 cells/L (water cells) that the projection includes, months with at least %d such samples", min_samples_share), pts = TRUE))
    par(mfrow = c(length(panels), 1), mar = c(2.8, 4.6, 2.2, 0.6), oma = c(0, 0, 1.8, 0), mgp = c(3, 0.6, 0))
    for (i in seq_along(panels)) {
      p <- panels[[i]]
      yl <- if (p$pts) c(0, 1.04) else c(0, max(c(unlist(p$y), 1), na.rm = TRUE) * 1.08)
      plot(NA, xlim = c(0.5, n + 0.5), ylim = yl, xlab = "", ylab = p$lab, main = p$main, cex.main = 0.95, axes = FALSE, xaxs = "i", yaxs = "i")
      for (u in names(use_col)) { w <- which(d$use == u); if (length(w)) rect(w - 0.5, yl[1], w + 0.5, yl[2], col = use_col[[u]], border = NA) }
      zm <- which(d$viirs_status == "zero"); mm2 <- which(d$viirs_status == "missing")
      rect(zm - 0.5, yl[1], zm + 0.5, yl[2], col = zero_col, border = NA); rect(mm2 - 0.5, yl[1], mm2 + 0.5, yl[2], col = miss_col, border = NA)
      for (k in rev(seq_along(Ms))) {
        if (p$pts) points(x, p$y[[k]], col = vcol[[k]], pch = vpch[[k]], cex = if (k == 1) 0.6 else 0.8, lwd = 1.1) else
          lines(x, p$y[[k]], col = vcol[[k]], lwd = if (k == 1) 1.4 else 1.7)
      }
      jan <- which(d$month == 1); axis(1, at = jan, labels = d$year[jan], cex.axis = 0.85)
      axis(2, las = 1, cex.axis = 0.85); box()
      if (i == 1) legend("topleft", legend = c(unname(variants), "hull months", "MODIS months", "VIIRS months", "VIIRS layer all zero", "VIIRS tif missing (2022-12)"),
                         col = c(unname(vcol), rep(NA, 5)), lwd = c(1.4, 1.7, 1.7, rep(NA, 5)),
                         fill = c(NA, NA, NA, use_col[["pred"]], use_col[["hybrid_modis"]], use_col[["hybrid"]], zero_col, miss_col), border = NA, cex = 0.78, bg = "white", box.col = "gray60", ncol = 2)
      if (p$pts) legend("bottomleft", legend = unname(variants), col = unname(vcol), pch = unname(vpch), pt.cex = c(0.6, 0.8, 0.8), cex = 0.78, bg = "white", box.col = "gray60", ncol = 3)
    }
    mtext(title, outer = TRUE, cex = 0.95, font = 2, line = 0.4)
  }
  # From the first satellite month: the hybrids add the nearshore hull to satellite months
  # only, so the hull months before 2002-07 are identical in every variant.
  png(file.path(dir_fig, "fig4_record_2002-2026_issue10.png"), width = 15, height = 13.5, units = "in", res = 150)
  draw_record(rec[rec$yrmo >= months[1], ], sprintf("Red tide exposure per monthly map from the first satellite month (%s-%s) to %s: the 6 Oct 2026 maps, the VIIRS hybrid (#11) and both hybrids (#10)",
                                                     substr(months[1], 1, 4), substr(months[1], 5, 6), max(rec$year)))
  invisible(dev.off())

  # Fig 5: per cell over the MODIS months, run A vs run B (the #11 fig 6 layout), in the
  # map palette of fig 1 (the pipeline's, purple to dark red; white = nothing).
  pal_fig1 <- colorRampPalette(colv[-1], bias = 2)
  png(file.path(dir_fig, "fig5_cells_modis_issue10.png"), width = 15, height = 11.5, units = "in", res = 150)
  par(mfrow = c(2, 3), mar = c(2.5, 2.8, 2.6, 0.6), oma = c(0, 0, 2.0, 0))
  lmax <- ceiling(max(log10(c(cum_a[which(cum_a > 0)], cum_b[which(cum_b > 0)]))))
  lbrk <- seq(3, lmax, 0.5); lcol <- pal_fig1(length(lbrk) - 1)
  draw_log_map <- function(v, main) {
    lv <- ifelse(!is.na(v) & v > 0, pmax(log10(v), 3), NA)
    base_panel(main, axes = TRUE); rect(xlim[1], ylim[1], xlim[2], ylim[2], col = "white", border = NA)
    image(xs, ys, to_z(lv), breaks = lbrk, col = lcol, add = TRUE, useRaster = TRUE); draw_land(); box()
    at <- seq(3, lmax, 1); legend("bottomleft", legend = sprintf("1e%d", at), fill = lcol[pmin(match(at, lbrk), length(lcol))], border = "gray40", cex = 0.75, bg = "white", box.col = "gray60", title = "cells/L, summed")
  }
  draw_log_map(cum_b, sprintf("before: cumulative exposure per cell over the %d MODIS months (max %s)", sum(is_modis), fmt_n(signif(max(cum_b, na.rm = TRUE), 3))))
  draw_log_map(cum_a, sprintf("after (MODIS hybrid): max %s", fmt_n(signif(max(cum_a, na.rm = TRUE), 3))))
  draw_log_map(cum_a - cum_b, sprintf("added by the hybrid: %d cells, max %s", sum(cum_a > cum_b, na.rm = TRUE), fmt_n(signif(max(cum_a - cum_b, na.rm = TRUE), 3))))
  nmax5 <- max(c(n5_a, n5_b), na.rm = TRUE); cnt_col5 <- c("white", pal_fig1(nmax5))
  draw_cnt_map <- function(v, main, vmax, cols) {
    base_panel(main, axes = TRUE); rect(xlim[1], ylim[1], xlim[2], ylim[2], col = "white", border = NA)
    image(xs, ys, to_z(v), breaks = seq(-0.5, vmax + 0.5, 1), col = cols, add = TRUE, useRaster = TRUE); draw_land(); box()
  }
  draw_cnt_map(n5_b, sprintf("before: cell-months at or above 100,000 cells/L (max %d of %d)", max(n5_b, na.rm = TRUE), sum(is_modis)), nmax5, cnt_col5)
  draw_cnt_map(n5_a, sprintf("after (MODIS hybrid): max %d", max(n5_a, na.rm = TRUE)), nmax5, cnt_col5)
  d5 <- n5_a - n5_b; dmax5 <- max(d5, na.rm = TRUE)
  draw_cnt_map(d5, sprintf("added by the hybrid: %d cells gain 1 to %d months", sum(d5 > 0, na.rm = TRUE), dmax5), dmax5, c("white", pal_fig1(max(dmax5, 1))))
  mtext(sprintf("Per-cell exposure over the %d MODIS months: cumulative cells/L (top) and months at or above 100,000 cells/L (bottom); MODIS-only, MODIS hybrid, and the difference (the fig 1 map palette)", sum(is_modis)), outer = TRUE, cex = 0.95, font = 2, line = 0.5)
  invisible(dev.off())

  # Markdown summary.
  gain <- cells$exposure_added > 0
  g <- grp[1, ]; gs <- grp[grp$group == names(groups)[5], ]
  line_of <- function(g, lab) sprintf("Over %s: total exposure %s (6 Oct 2026) -> %s (VIIRS hybrid, %+.1f%%) -> %s (both hybrids, %+.1f%%); the share of the in-situ water samples >= 10,000 cells/L the projection includes %.1f%% -> %.1f%% -> %.1f%% (%s, %s and %s of %s); the high samples (> 1,000,000 cells/L) %.1f%% -> %.1f%% -> %.1f%% (of %s).",
                                      lab, fmt_n(round(g$exposure_v6oct)), fmt_n(round(g$exposure_v11)), 100 * (g$exposure_ratio_11 - 1), fmt_n(round(g$exposure_v10)), 100 * (g$exposure_ratio_10 - 1),
                                      100 * g$share_ge1e4_v6oct, 100 * g$share_ge1e4_v11, 100 * g$share_ge1e4_v10, fmt_n(g$in_ge1e4_v6oct), fmt_n(g$in_ge1e4_v11), fmt_n(g$in_ge1e4_v10), fmt_n(g$samples_ge1e4),
                                      100 * g$share_high_v6oct, 100 * g$share_high_v11, 100 * g$share_high_v10, fmt_n(g$samples_high))
  g_cols <- c("group", "n_months", "months_changed_11", "months_changed_10", "exposure_v6oct", "exposure_v11", "exposure_v10", "exposure_ratio_11", "exposure_ratio_10",
              "cellmonths_ge1e4_v6oct", "cellmonths_ge1e4_v11", "cellmonths_ge1e4_v10", "cellmonths_ge1e5_v6oct", "cellmonths_ge1e5_v11", "cellmonths_ge1e5_v10",
              "cellmonths_ge1e6_v6oct", "cellmonths_ge1e6_v11", "cellmonths_ge1e6_v10",
              "samples_ge1e4", "share_ge1e4_v6oct", "share_ge1e4_v11", "share_ge1e4_v10", "samples_high", "share_high_v6oct", "share_high_v11", "share_high_v10")
  md <- c("# Issue #10: the whole record with both nearshore hybrids (compare stage)", "",
          sprintf("Produced by `docs/issue10_modis-nearshore-hybrid/check_modis_hybrid_issue10.R` (stage `compare`) from three combined stacks of %d months: the 6 October 2026 maps (satellite clips only), run A (the VIIRS hybrid of #11, `viirs_nearshore = \"mask5\"`) and run B (both hybrids, `modis_nearshore = \"mask5\"` as well). Total exposure = the plain sum of cells/L over the %s water cells; cell counts at or above 10,000 / 100,000 / 1,000,000 cells/L; samples included = water-cell samples at or above 10,000 cells/L (and the high class) whose cell is non-zero in the map. Yearly and group totals are sums over the months. Run B differs from run A in exactly the %d MODIS months with a nearshore hull, run A from the 6 October maps in exactly the %d VIIRS months with one (checked).",
                  length(all_yrmo), fmt_n(n_water), expected$n_changed, expected$n_changed_viirs),
          "", "## Overall", "",
          paste0("- ", line_of(g, names(groups)[1])),
          paste0("- ", line_of(gs, names(groups)[5])),
          "", "## Totals by month group (`tables/record_groups_issue10.csv`)", "",
          md_table(round_cols(grp[, g_cols]), 3),
          "", "## By year (`tables/record_annual_issue10.csv`; sums over the months of the year)", "",
          md_table(round_cols(ann[, c("year", "clip_sources", g_cols[-1])]), 3),
          "", "## Per cell over the MODIS months (`tables/cells_modis_issue10.csv`)", "",
          sprintf("- Cumulative exposure: %d of the %d water cells gain (1 to %s cells/L summed over the months, median %s); the cell maximum goes from %s to %s.",
                  sum(gain), n_water, fmt_n(signif(max(cells$exposure_added), 3)), fmt_n(signif(median(cells$exposure_added[gain]), 3)), fmt_n(signif(max(cum_b, na.rm = TRUE), 3)), fmt_n(signif(max(cum_a, na.rm = TRUE), 3))),
          sprintf("- Cell-months at or above 100,000 cells/L: %s before, %s after; %d cells gain 1 to %d months. At or above 1,000,000 cells/L: %s before, %s after; %d cells gain.",
                  fmt_n(sum(n5_b, na.rm = TRUE)), fmt_n(sum(n5_a, na.rm = TRUE)), sum(d5 > 0, na.rm = TRUE), dmax5,
                  fmt_n(sum(n6_b, na.rm = TRUE)), fmt_n(sum(n6_a, na.rm = TRUE)), sum(n6_a > n6_b, na.rm = TRUE)),
          "")
  writeLines(md, file.path(dir_cmt, "compare_summary.md"))
  cat(md, sep = "\n")
  message("Stage compare done.")
}
cat("\nDone:", stage, "\n")
