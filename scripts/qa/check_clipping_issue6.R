#' QA for issue #6: non-clipped vs clipped monthly red tide maps.
#'
#' Compares, for every month of the last pipeline run, the unclipped sdmTMB
#' prediction with the final (clipped, combined) map and with each clipping
#' alternative (VIIRS, MODIS nFLH, buffered hulls), and relates each map to
#' the in-situ samples of that month. Built entirely from the stacks the
#' pipeline already writes; nothing is refit or re-clipped. Motivated by
#' issue #5 (VIIRS months with no positive cell are written as all-zero
#' maps, overriding fitted surfaces with hundreds of positive samples).
#'
#' Needs a previous pipeline run at 5-min resolution (out/5min/sdm,
#' out/5min/clipped, out/5min/combined, VIIRS/VIIRS_*.grd).
#'
#' Run from the repo root:  Rscript scripts/qa/check_clipping_issue6.R
#'   RT_QA_PDF=0    skip the per-month PDF (table, summary and figures only)
#'   RT_QA_QUICK=1  draw only the headline months in the PDF
#'
#' Output:
#'   docs/issue6/clip_comparison_issue6.csv     one row per month (504)
#'   docs/issue6/clip_comparison_summary.md     tables for the issues
#'   docs/issue6/fig1_viirs_calendar.png        VIIRS status by year x month
#'   docs/issue6/fig2_insitu_vs_viirs.png       in-situ positives vs VIIRS cells
#'   docs/issue6/fig3_bloom_area_unclipped_vs_final.png
#'   docs/issue6/fig4_headline_months.png       unclipped / final / hull / MODIS
#'   docs/issue6/clip_check_issue6.pdf          one page per fitted month (4 panels)
#'   docs/issue6/clip_months_issue6.pdf         one row per month, 12 rows (a year) per
#'       page: FWC counts | unclipped | VIIRS | MODIS | hulls, each with its legend
#'       and a count box; the panel the final map uses is framed in red
#'   docs/issue6/clip_class_counts_issue6.csv   the count-box numbers, one month per row
#'   console: the summary and the stopifnot() results
#'
#' Deterministic: no RNG, no timestamps in any output.

# Repo root: the working directory if it holds the .Rproj, else two levels
# above this script (scripts/qa/).
.root <- local({
  if (file.exists("RedTideMaps.Rproj")) return(normalizePath(getwd(), winslash = "/"))
  f <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE))
  if (length(f) == 1) {
    d <- normalizePath(file.path(dirname(f), "..", ".."), winslash = "/", mustWork = FALSE)
    if (file.exists(file.path(d, "RedTideMaps.Rproj"))) return(d)
  }
  stop("Run from the repo root: Rscript scripts/qa/check_clipping_issue6.R", call. = FALSE)
})
source(file.path(.root, "scripts", "_setup.R"))   # sf, raster, terra, ggplot2, viridis, maps, fields, ...

# Parameters ---------------------------------------------------------------
thr_bloom <- 1e4   # cells/L: first coloured bin in the map PDFs; FWC "low"
thr_high  <- 1e5   # cells/L: FWC "medium"; lower inflection of the Ecospace mortality response
min_samples_flag     <- 5L     # samples >= thr_bloom needed before the low_vs_hull / samples_outside flags can fire
hull_ratio_flag      <- 0.25   # flag when the final map keeps less than this share of the hull-clipped bloom area
samples_outside_frac <- 0.50   # flag when fewer than this share of samples >= thr_bloom sit in a non-zero final cell
headline <- c("201604", "201701", "201702", "201703", "201704",
              "201803", "201804", "201805", "202106", "202305")
expected <- list(n_months = 504L,
                 use = c(viirs = 155L, modis = 123L, pred = 226L),
                 viirs_layers = 155L, viirs_zero = 89L)
viirs_era  <- c("201201", "202412")   # months with a VIIRS tif expected
render_pdf  <- !identical(Sys.getenv("RT_QA_PDF"), "0")           # per-month PDF (clip_check_issue6.pdf)
monthly_pdf <- !identical(Sys.getenv("RT_QA_MONTHLY_PDF"), "0")   # one-row-per-month PDF (clip_months_issue6.pdf)
rows_per_page <- 12L   # rows (months) per page of the monthly PDF; 12 = one calendar year per page
quick      <- nzchar(Sys.getenv("RT_QA_QUICK"))

# Paths --------------------------------------------------------------------
dir_out      <- file.path(.root, "out", "5min")
dir_sdm      <- file.path(dir_out, "sdm")
dir_clipped  <- file.path(dir_out, "clipped")
dir_combined <- file.path(dir_out, "combined")
dir_plots    <- file.path(dir_out, "plots")
dir_docs     <- file.path(.root, "docs", "issue6")
dir.create(dir_docs, recursive = TRUE, showWarnings = FALSE)

one_file <- function(dir, pattern, what) {
  f <- list.files(dir, pattern = pattern, full.names = TRUE)
  if (length(f) != 1)
    stop("Expected one ", what, " in ", dir, " (found ", length(f), "); run the pipeline first.",
         call. = FALSE)
  f
}
grd <- function(f) sub("[.]grd$", "", f)
file_depth     <- one_file(file.path(.root, "template rasters"), "^depth 5min .*[.]asc$", "depth template")
file_unclip    <- grd(one_file(dir_sdm,      "^sdmTMB_log_stack_[0-9]{6}-[0-9]{6}[.]grd$", "unclipped stack"))
file_hull      <- grd(one_file(dir_clipped,  "_clipped_hull[.]grd$",  "hull-clipped stack"))
file_viirs     <- grd(one_file(dir_clipped,  "_clipped_viirs[.]grd$", "VIIRS-clipped stack"))
file_modis     <- grd(one_file(dir_clipped,  "_clipped_modis[.]grd$", "MODIS-clipped stack"))
file_final     <- grd(one_file(dir_combined, "_clipped_combined[.]grd$", "combined stack"))
file_viirs_raw <- grd(one_file(file.path(.root, "VIIRS"), "^VIIRS_[0-9]{6}-[0-9]{6}[.]grd$", "VIIRS stack"))
file_modis_pol <- one_file(file.path(.root, "MODIS"), "^FLH polys.*[.]Rdata$", "MODIS polygon file")
file_clipsrc   <- file.path(dir_clipped, "clipping_source.csv")
file_hulldiag  <- file.path(dir_sdm, "hull_diagnostics.csv")
file_fitmat    <- file.path(dir_sdm, "RT_fit_matrix.RData")
# Several *_filtered.Rdata can accumulate (one per FWC cache date); take the
# newest by the end date in its name, and its hull-polygon twin.
ff <- list.files(dir_sdm, pattern = "_filtered[.]Rdata$", full.names = TRUE)
if (length(ff) == 0) stop("No *_filtered.Rdata in ", dir_sdm, "; run the pipeline first.", call. = FALSE)
ff_end <- as.integer(substr(regmatches(basename(ff), regexpr("[0-9]{8}_filtered", basename(ff))), 1, 8))
file_filtered  <- ff[which.max(ff_end)]
file_hullpolys <- sub("_filtered[.]Rdata$", "_hullpolys.Rdata", file_filtered)
for (f in c(file_clipsrc, file_hulldiag, file_fitmat, file_hullpolys))
  if (!file.exists(f)) stop("Missing ", f, "; run the pipeline first.", call. = FALSE)
message("Samples: ", basename(file_filtered))

# Load ---------------------------------------------------------------------
depth    <- raster::raster(file_depth)
dv       <- raster::values(depth)
land     <- is.na(dv)
cell_km2 <- raster::values(raster::area(depth))
nr <- nrow(depth); nc <- ncol(depth)

# Each stack is read once as a cell x month matrix; every statistic is then
# a column operation (indexing a 504-band file layer by layer is slow).
read_mat <- function(f) {
  b <- raster::brick(f)
  m <- raster::values(b)
  colnames(m) <- sub("^X", "", names(b))
  m
}
bricks <- lapply(c(file_unclip, file_hull, file_viirs, file_modis, file_final), raster::brick)
stopifnot(raster::compareRaster(depth, bricks[[1]], bricks[[2]], bricks[[3]], bricks[[4]], bricks[[5]]))
U  <- read_mat(file_unclip)   # unclipped prediction, cells/L
H  <- read_mat(file_hull)     # hull-clipped
Vc <- read_mat(file_viirs)    # VIIRS-clipped
Mc <- read_mat(file_modis)    # MODIS-clipped
Fm <- read_mat(file_final)    # final (combined)
key <- colnames(U)
U[land, ] <- NA               # the prediction grid includes land cells; mask like the clipped stacks

Vraw <- raster::brick(file_viirs_raw)
stopifnot(isTRUE(all.equal(as.vector(raster::extent(Vraw)), as.vector(raster::extent(depth)))))
Vr <- raster::values(Vraw); colnames(Vr) <- sub("^X", "", names(Vraw))
viirs_n_pos <- colSums(Vr > 0, na.rm = TRUE)
viirs_max   <- apply(Vr, 2, max, na.rm = TRUE)

clipsrc <- read.csv(file_clipsrc, stringsAsFactors = FALSE)
clipsrc$yrmo <- sub("^X", "", clipsrc$yrmo)
hdiag <- read.csv(file_hulldiag, colClasses = c(yrmo = "character"))
load(file_fitmat)        # fit_matrix (character)
fm <- as.data.frame(fit_matrix, stringsAsFactors = FALSE)
fm <- fm[is.na(fm$model) | fm$model != "fit_sdmTMBnb", ]
fm$yrmo <- sprintf("%04d%02d", as.integer(fm$year), as.integer(fm$month))
load(file_filtered)      # filtered_points_df (sf)
load(file_hullpolys)     # pol_list (sf per month, names "198509")
load(file_modis_pol)     # flh.polys (sp per month, names "X200207")

# Samples: one grid lookup for all rows -------------------------------------
pts <- sf::st_drop_geometry(filtered_points_df)
pts$cells <- suppressWarnings(as.numeric(pts$cells))
n_cells_na <- sum(is.na(pts$cells))
pts <- pts[!is.na(pts$cells), ]
pts$yrmo <- sprintf("%d%02d", as.integer(pts$year), as.integer(pts$month))
pts$cell <- raster::cellFromXY(depth, cbind(pts$lon, pts$lat))
pts$water <- FALSE
ok <- !is.na(pts$cell)
pts$water[ok] <- !land[pts$cell[ok]]
by_m <- split(pts, pts$yrmo)

# Per-month table ----------------------------------------------------------
area_ge <- function(v, thr) sum(cell_km2[!is.na(v) & v >= thr])
lstats  <- function(M, ym) {
  if (!(ym %in% colnames(M))) return(c(max = NA_real_, a1e4 = NA_real_, a1e5 = NA_real_))
  v <- M[, ym]
  if (all(is.na(v))) return(c(max = NA_real_, a1e4 = NA_real_, a1e5 = NA_real_))
  c(max = max(v, na.rm = TRUE), a1e4 = area_ge(v, thr_bloom), a1e5 = area_ge(v, thr_high))
}
fit_status_of <- function(v) {
  if (all(is.na(v))) return("none")
  if (max(v, na.rm = TRUE) == 0) return("failed")
  "fitted"
}
viirs_status_of <- function(ym) {
  if (ym %in% names(viirs_n_pos)) return(if (viirs_n_pos[[ym]] > 0) "positive" else "zero")
  if (ym >= viirs_era[1] && ym <= viirs_era[2]) "missing" else "no_coverage"
}
hits <- function(p, ym, thr) {
  # samples >= thr on water cells, and how many of them sit in a non-zero final cell
  if (is.null(p)) return(c(n = 0L, hit = 0L))
  q <- p[p$water & p$cells >= thr, ]
  if (nrow(q) == 0) return(c(n = 0L, hit = 0L))
  c(n = nrow(q), hit = sum(Fm[q$cell, ym] > 0, na.rm = TRUE))
}

rows <- lapply(key, function(ym) {
  p  <- by_m[[ym]]
  u  <- lstats(U, ym); fnl <- lstats(Fm, ym)
  av <- lstats(Vc, ym); am <- lstats(Mc, ym); ah <- lstats(H, ym)
  h4 <- hits(p, ym, thr_bloom); h5 <- hits(p, ym, thr_high)
  hd <- hdiag[match(ym, hdiag$yrmo), ]
  fr <- fm[match(ym, fm$yrmo), ]
  mp <- flh.polys[[paste0("X", ym)]]
  data.frame(
    yrmo = ym, year = as.integer(substr(ym, 1, 4)), month = as.integer(substr(ym, 5, 6)),
    n_samples      = if (is.null(p)) 0L else nrow(p),
    n_samples_land = if (is.null(p)) 0L else sum(!p$water),
    n_pos     = if (is.null(p)) 0L else sum(p$cells > 0),
    n_pos_1e4 = if (is.null(p)) 0L else sum(p$cells >= thr_bloom),
    n_pos_1e5 = if (is.null(p)) 0L else sum(p$cells >= thr_high),
    max_cells = if (is.null(p)) 0 else max(p$cells),
    fit_status = fit_status_of(U[, ym]),
    converged  = if (is.na(fr$model)) NA_character_ else fr$convergence,   # NA: no fit attempted; "no model": both attempts failed
    use = clipsrc$use[match(ym, clipsrc$yrmo)],
    viirs_status = viirs_status_of(ym),
    viirs_n_pos_cells = if (ym %in% names(viirs_n_pos)) as.integer(viirs_n_pos[[ym]]) else NA_integer_,
    viirs_max_freq    = if (ym %in% names(viirs_max)) round(viirs_max[[ym]], 3) else NA_real_,
    modis_present = ym %in% colnames(Mc),
    modis_n_polys = if (is.null(mp)) NA_integer_ else length(mp),
    hull_n_pos        = hd$n_pos,
    hull_n_polys      = hd$n_polys,
    hull_footprint_km2 = hd$total_area_km2,
    unclip_max = u[["max"]], area_1e4_unclip_km2 = u[["a1e4"]], area_1e5_unclip_km2 = u[["a1e5"]],
    final_max  = fnl[["max"]], area_1e4_final_km2 = fnl[["a1e4"]], area_1e5_final_km2 = fnl[["a1e5"]],
    area_1e4_viirs_km2 = av[["a1e4"]], area_1e4_modis_km2 = am[["a1e4"]], area_1e4_hull_km2 = ah[["a1e4"]],
    n_pos_1e4_water = h4[["n"]], n_pos_1e4_in_fp = h4[["hit"]],
    n_pos_1e5_water = h5[["n"]], n_pos_1e5_in_fp = h5[["hit"]],
    stringsAsFactors = FALSE)
})
tab <- do.call(rbind, rows)
tab$retained_1e4 <- ifelse(tab$area_1e4_unclip_km2 > 0, tab$area_1e4_final_km2 / tab$area_1e4_unclip_km2, NA)
tab$retained_1e5 <- ifelse(tab$area_1e5_unclip_km2 > 0, tab$area_1e5_final_km2 / tab$area_1e5_unclip_km2, NA)
tab$frac_pos_1e4_in_fp <- ifelse(tab$n_pos_1e4_water > 0, tab$n_pos_1e4_in_fp / tab$n_pos_1e4_water, NA)
tab$frac_pos_1e5_in_fp <- ifelse(tab$n_pos_1e5_water > 0, tab$n_pos_1e5_in_fp / tab$n_pos_1e5_water, NA)
tab$flag_zeroed_fit    <- tab$fit_status == "fitted" & !is.na(tab$final_max) & tab$final_max == 0
# The unclipped surface exceeds thr_bloom over almost the whole shelf in most
# fitted months (intercept-only lognormal on positives), so "share of the
# unclipped area kept" is small everywhere and is reported, not flagged. The
# hull-clipped map is the sample-based footprint, so a satellite month that
# keeps much less than it is the "drastic difference" the issue asks about.
tab$hull_ratio_1e4 <- ifelse(!is.na(tab$area_1e4_hull_km2) & tab$area_1e4_hull_km2 > 0,
                             tab$area_1e4_final_km2 / tab$area_1e4_hull_km2, NA)
tab$flag_low_vs_hull <- tab$fit_status == "fitted" & tab$use != "pred" & tab$n_pos_1e4 >= min_samples_flag &
                        !is.na(tab$hull_ratio_1e4) & tab$hull_ratio_1e4 < hull_ratio_flag
tab$flag_samples_outside <- tab$fit_status == "fitted" & tab$n_pos_1e4_water >= min_samples_flag &
                            !is.na(tab$frac_pos_1e4_in_fp) & tab$frac_pos_1e4_in_fp < samples_outside_frac
tab$any_flag <- tab$flag_zeroed_fit | tab$flag_low_vs_hull | tab$flag_samples_outside
# A zeroed month matters most when the lost surface held bloom-level values.
tab$zeroed_material <- tab$flag_zeroed_fit & !is.na(tab$area_1e4_unclip_km2) & tab$area_1e4_unclip_km2 > 0
for (v in grep("_km2$|retained|hull_ratio|frac_|_max$", names(tab), value = TRUE)) tab[[v]] <- round(tab[[v]], 3)

fitted_months <- tab$yrmo[tab$fit_status == "fitted"]
tab$pdf_page <- NA_integer_
tab$pdf_page[match(fitted_months, tab$yrmo)] <- seq_along(fitted_months)

file_csv <- file.path(dir_docs, "clip_comparison_issue6.csv")
write.csv(tab, file_csv, row.names = FALSE)
message("Table written: ", file_csv, " (", nrow(tab), " rows)")

# Checks (before any plotting) ------------------------------------------------
cat("\n=== stopifnot() checks ===\n")
# Matrix -> image() orientation: z[col, nr - row + 1] must equal the cell value.
to_z <- function(v) matrix(v, nrow = nc)[, nr:1]
z <- to_z(dv); cells <- seq_len(raster::ncell(depth))
stopifnot(identical(z[cbind(raster::colFromCell(depth, cells),
                            nr - raster::rowFromCell(depth, cells) + 1)], dv))
cat("image() orientation: OK\n")
stopifnot(length(key) == expected$n_months, identical(key, colnames(H)), identical(key, colnames(Fm)),
          all(colnames(Vc) %in% key), all(colnames(Mc) %in% key))
stopifnot(nrow(clipsrc) == expected$n_months, identical(sort(clipsrc$yrmo), sort(key)),
          all(clipsrc$viirs == (clipsrc$yrmo %in% colnames(Vc))),
          all(clipsrc$modis == (clipsrc$yrmo %in% colnames(Mc))),
          all(clipsrc$use == ifelse(clipsrc$viirs, "viirs", ifelse(clipsrc$modis, "modis", "pred"))))
use_counts <- table(factor(tab$use, levels = names(expected$use)))
stopifnot(all(as.integer(use_counts) == expected$use))
cat("clipping_source.csv: ", paste(names(use_counts), as.integer(use_counts), collapse = ", "), "  OK\n")
stopifnot(ncol(Vr) == expected$viirs_layers, sum(viirs_n_pos == 0) == expected$viirs_zero)
cat("VIIRS stack: ", ncol(Vr), " layers, ", sum(viirs_n_pos == 0), " with no positive cell  OK\n")
stopifnot(tab$viirs_status[tab$yrmo == "202212"] == "missing", tab$use[tab$yrmo == "202212"] == "modis")
# The final map must equal the chosen clipped layer on water (NA -> 0, land -> NA),
# which is exactly what make_redtide_ascii() does.
bad <- character(0)
for (ym in key) {
  src <- switch(tab$use[tab$yrmo == ym], viirs = Vc[, ym], modis = Mc[, ym], pred = H[, ym])
  src[is.na(src)] <- 0; src[land] <- NA
  if (!isTRUE(all.equal(Fm[, ym], src))) bad <- c(bad, ym)
}
if (length(bad)) message("final != chosen source for: ", paste(bad, collapse = " "))
stopifnot(length(bad) == 0, all(is.na(Fm) == land))
cat("final map equals its chosen source in all ", length(key), " months; land mask identical  OK\n")
fm_status <- ifelse(is.na(tab$converged), "none",
                    ifelse(tab$converged == "no model", "failed", "fitted"))
mism <- tab$yrmo[fm_status != tab$fit_status]
if (length(mism)) message("fit status mismatch (layer vs fit_matrix): ", paste(mism, collapse = " "))
stopifnot(length(mism) == 0)
cat("fit status from layers agrees with RT_fit_matrix: ",
    paste(names(table(tab$fit_status)), table(tab$fit_status), collapse = ", "), "  OK\n")
fitted_viirs_zero <- tab$yrmo[tab$fit_status == "fitted" & tab$use == "viirs" & tab$viirs_status == "zero"]
stopifnot(all(fitted_viirs_zero %in% tab$yrmo[tab$flag_zeroed_fit]))
extra_zero <- setdiff(tab$yrmo[tab$flag_zeroed_fit], fitted_viirs_zero)
cat("fitted months written as zero: ", sum(tab$flag_zeroed_fit), " (", length(fitted_viirs_zero),
    " by an all-zero VIIRS layer", if (length(extra_zero)) paste0("; other: ", paste(extra_zero, collapse = " ")) else "",
    ")\n", sep = "")
# Hull cross-checks: diagnostics are from the last run and undated, so warn only.
d_mis <- tab$yrmo[!is.na(tab$hull_n_pos) & tab$hull_n_pos != tab$n_pos]
if (length(d_mis)) warning("hull_diagnostics n_pos differs from recomputed positives for: ",
                           paste(d_mis, collapse = " "), call. = FALSE)
no_row <- tab$yrmo[is.na(tab$hull_n_pos)]
stopifnot(all(tab$n_samples[tab$yrmo %in% no_row] == 0))
stopifnot(all(tab$yrmo[tab$n_pos > 0] %in% names(pol_list)))
stopifnot(all(colSums(H[, setdiff(key, names(pol_list)), drop = FALSE], na.rm = TRUE) == 0))
cat("hull diagnostics: ", length(no_row), " months without a row (no samples); every month with positives has a footprint  OK\n")
stopifnot(all(cell_km2 > 70 & cell_km2 < 80))
cat("cells: ", sum(!land), " water, ", sum(land), " land; area ", round(min(cell_km2), 1), "-",
    round(max(cell_km2), 1), " km2\n", sep = "")
cat("samples: ", nrow(pts), " (", n_cells_na, " dropped for NA count); ", sum(!ok),
    " off-grid; ", sum(ok & !pts$water), " on land cells of the template\n", sep = "")
cat("All checks passed.\n")

# Summary (console + markdown) ------------------------------------------------
md_table <- function(df, digits = 2) {
  df <- as.data.frame(df, stringsAsFactors = FALSE)
  fmt <- function(x) if (is.numeric(x)) ifelse(is.na(x), "", format(round(x, digits), big.mark = ",", trim = TRUE)) else ifelse(is.na(x), "", as.character(x))
  cells <- vapply(df, fmt, character(nrow(df)))
  if (nrow(df) == 1) cells <- matrix(cells, nrow = 1)
  c(paste0("| ", paste(names(df), collapse = " | "), " |"),
    paste0("|", paste(rep("---", ncol(df)), collapse = "|"), "|"),
    apply(cells, 1, function(r) paste0("| ", paste(r, collapse = " | "), " |")))
}
pct <- function(x) ifelse(is.na(x), NA, round(100 * x))
era <- tab[tab$yrmo >= viirs_era[1] & tab$yrmo <= viirs_era[2], ]
xt1 <- as.data.frame.matrix(table(tab$use, tab$fit_status))
xt1 <- cbind(use = rownames(xt1), xt1, total = rowSums(xt1))
xt2 <- as.data.frame.matrix(table(era$viirs_status, era$fit_status))
xt2 <- cbind(viirs_status = rownames(xt2), xt2, total = rowSums(xt2))
cal <- as.data.frame.matrix(table(era$month, era$viirs_status))
cal <- cbind(month = month.abb[as.integer(rownames(cal))], cal)
zeroed <- tab[tab$flag_zeroed_fit, c("yrmo", "n_pos", "n_pos_1e4", "n_pos_1e5", "max_cells", "converged",
                                     "area_1e4_unclip_km2", "area_1e4_hull_km2", "area_1e4_modis_km2",
                                     "n_pos_1e4_water", "pdf_page")]
flagged <- tab[tab$any_flag & !tab$flag_zeroed_fit,
               c("yrmo", "use", "viirs_status", "n_pos", "n_pos_1e4", "n_pos_1e5",
                 "area_1e4_final_km2", "area_1e4_hull_km2", "hull_ratio_1e4", "n_pos_1e4_water",
                 "frac_pos_1e4_in_fp", "flag_low_vs_hull", "flag_samples_outside", "pdf_page")]
water_km2 <- sum(cell_km2[!land])
fit_all <- tab[tab$fit_status == "fitted", ]
shelf_note <- sprintf(paste0(
  "The unclipped surface is not a usable map on its own: in %d of %d fitted months it exceeds %s cells/L over more than 90%% of the %s km2 of water cells ",
  "(median unclipped bloom area %s km2), because the intercept-only lognormal is fit to positive samples only. ",
  "The clip therefore does all the localisation, and `retained_1e4` (final / unclipped bloom area) is reported for completeness but not flagged; `hull_ratio_1e4` (final / hull-clipped bloom area) is the comparison between the satellite footprint and the sample-based footprint."),
  sum(fit_all$area_1e4_unclip_km2 > 0.9 * water_km2), nrow(fit_all), format(thr_bloom, big.mark = ","),
  format(round(water_km2), big.mark = ","), format(round(median(fit_all$area_1e4_unclip_km2)), big.mark = ","))
vpos_nofit <- tab[tab$viirs_status == "positive" & tab$fit_status != "fitted",
                  c("yrmo", "fit_status", "n_pos", "viirs_n_pos_cells", "area_1e4_final_km2")]
fit_tab <- tab[tab$fit_status == "fitted" & tab$n_pos_1e4_water >= min_samples_flag, ]
insitu <- do.call(rbind, lapply(split(fit_tab, fit_tab$use), function(d) data.frame(
  use = d$use[1], months = nrow(d),
  median_retained_1e4 = round(median(d$retained_1e4, na.rm = TRUE), 2),
  median_frac_pos_1e4_in_fp = round(median(d$frac_pos_1e4_in_fp, na.rm = TRUE), 2),
  months_lt_half_in_fp = sum(d$frac_pos_1e4_in_fp < 0.5, na.rm = TRUE))))
vpos_fit <- fit_tab[fit_tab$use == "viirs" & fit_tab$viirs_status == "positive", ]
sub_viirs <- data.frame(
  subset = c("VIIRS positive", "VIIRS all-zero"),
  months = c(nrow(vpos_fit), sum(fit_tab$use == "viirs" & fit_tab$viirs_status == "zero")),
  median_retained_1e4 = c(round(median(vpos_fit$retained_1e4, na.rm = TRUE), 2), 0),
  median_frac_pos_1e4_in_fp = c(round(median(vpos_fit$frac_pos_1e4_in_fp, na.rm = TRUE), 2), 0),
  months_lt_half_in_fp = c(sum(vpos_fit$frac_pos_1e4_in_fp < 0.5, na.rm = TRUE),
                           sum(fit_tab$use == "viirs" & fit_tab$viirs_status == "zero")))

md <- c(
  "# Clipped vs unclipped comparison (issue #6)",
  "",
  paste0("Inputs: `", basename(file_unclip), "` (unclipped), the three clipped stacks, the combined stack, `clipping_source.csv`, `hull_diagnostics.csv`, `RT_fit_matrix.RData`, `", basename(file_filtered), "`, `", basename(file_viirs_raw), "`."),
  paste0("Bloom area = km2 of grid cells >= ", format(thr_bloom, big.mark = ","), " cells/L (`area_1e4_*`) or >= ", format(thr_high, big.mark = ","), " cells/L (`area_1e5_*`), land masked. Flags: `zeroed_fit` (fitted surface, final map all zero); `low_vs_hull` (satellite-clipped final map keeps < ", pct(hull_ratio_flag), "% of the hull-clipped bloom area, >= ", min_samples_flag, " samples >= 1e4); `samples_outside` (< ", pct(samples_outside_frac), "% of water-cell samples >= 1e4 sit in a non-zero final cell, >= ", min_samples_flag, " such samples)."),
  "",
  shelf_note,
  "",
  "## Months by clip source and fit status",
  "", md_table(xt1), "",
  paste0("## VIIRS era (", viirs_era[1], "-", viirs_era[2], "): VIIRS layer status by fit status"),
  "", md_table(xt2), "",
  "## VIIRS layer status by calendar month (VIIRS era)",
  "", md_table(cal), "",
  paste0("## Fitted months written as all-zero maps (", nrow(zeroed), ")"),
  "",
  "`area_1e4_hull_km2` and `area_1e4_modis_km2` are what the hull and MODIS clips of the same surface keep (the alternatives already on disk); `n_pos_1e4_water` counts samples >= 1e4 cells/L on water cells of the grid.",
  "", md_table(zeroed, 0), "",
  sprintf(paste0("Of these %d months, %d have a fitted surface that reaches %s cells/L somewhere (`zeroed_material`): %s. ",
                 "For them the hull clip would keep %s km2 of bloom area in total and the MODIS clip %s km2 (%d months have a MODIS polygon). ",
                 "In the other %d months the fitted surface stays below %s cells/L everywhere (max %s cells/L), so the zero map differs from the alternatives only below the first colour bin of the map PDFs."),
          nrow(zeroed), sum(tab$zeroed_material), format(thr_bloom, big.mark = ","),
          paste(tab$yrmo[tab$zeroed_material], collapse = ", "),
          format(round(sum(tab$area_1e4_hull_km2[tab$zeroed_material], na.rm = TRUE)), big.mark = ","),
          format(round(sum(tab$area_1e4_modis_km2[tab$zeroed_material], na.rm = TRUE)), big.mark = ","),
          sum(tab$zeroed_material & tab$modis_present),
          sum(tab$flag_zeroed_fit & !tab$zeroed_material), format(thr_bloom, big.mark = ","),
          format(round(max(tab$unclip_max[tab$flag_zeroed_fit & !tab$zeroed_material], na.rm = TRUE)), big.mark = ",")),
  "",
  paste0("## Other flagged months (", nrow(flagged), ")"),
  "", md_table(flagged), "",
  "## Samples inside the final footprint, fitted months with >= 5 water samples >= 1e4 cells/L",
  "",
  "`median_frac_pos_1e4_in_fp`: median share of those samples whose grid cell is non-zero in the final map. For VIIRS-positive months this tests whether the satellite footprint covers the sampled bloom (the nearshore hypothesis in #5).",
  "", md_table(insitu), "", md_table(sub_viirs), "",
  paste0("## VIIRS-positive months without a fitted surface (", nrow(vpos_nofit), ")"),
  "",
  "The satellite saw a bloom but fewer than 6 positive samples exist, so the prediction is all NA and the clip writes zeros (issue M2 territory, not a clipping fault).",
  "", md_table(vpos_nofit, 0), "")
file_md <- file.path(dir_docs, "clip_comparison_summary.md")
writeLines(md, file_md)
cat("\n", paste(md, collapse = "\n"), "\n", sep = "")
message("Summary written: ", file_md)

# Drawing helpers -----------------------------------------------------------
# Same palette and breaks as fn.plot_redtide_stack() / fn.plot_sdmTMB(), so
# panels match the pipeline PDFs.
colv   <- c("white","purple","blue","darkblue","cyan","green","darkgreen","yellow","orange","red","darkred")
funpal <- colorRampPalette(colv, bias = 2)
brks   <- c(0, 1e4 - 1, seq(1e4, 4e6, 10000), Inf)
color  <- c(funpal(length(brks) - 2), "darkred")
brks_img <- brks; brks_img[length(brks_img)] <- 1e12   # base image() needs finite breaks
xs <- raster::xFromCol(depth, 1:nc); ys <- rev(raster::yFromRow(depth, 1:nr))
xlim <- c(-87.5, -81); ylim <- c(25, 30.5)
# Coastline drawn four times per page: simplify it once (0.5 km tolerance,
# invisible at 5-min cells) so the PDF does not carry the full polygon 1,300 times.
fl_full <- sf::st_as_sf(maps::map("state", region = "Florida", plot = FALSE, fill = TRUE))
tol_m <- function(m) if (sf::sf_use_s2()) m else m / 1e5   # st_simplify tolerance: metres with s2, degrees without
fl <- suppressWarnings(sf::st_simplify(fl_full, dTolerance = tol_m(2000)))
message("Florida outline: ", nrow(sf::st_coordinates(fl_full)), " -> ", nrow(sf::st_coordinates(fl)), " vertices")
simplify_outline <- function(s) if (is.null(s)) NULL else suppressWarnings(sf::st_simplify(s, dTolerance = tol_m(1000)))
sbrks <- c(0, 1e3, 1e4, 1e5, 1e6, Inf)
slabs <- c("<= 1,000", "1,000-10,000", "10,000-100,000", "100,000-1,000,000", "> 1,000,000")
spal  <- viridis::viridis(5, direction = -1)

# Footprint outlines of each clip source, built lazily and cached.
.viirs_pol <- list()
viirs_outline <- function(ym) {
  if (!(ym %in% colnames(Vr)) || viirs_n_pos[[ym]] == 0) return(NULL)
  if (!is.null(.viirs_pol[[ym]])) return(.viirs_pol[[ym]])
  r2 <- Vraw[[which(names(Vraw) == paste0("X", ym))]]
  r2[r2 == 0] <- NA
  p <- raster::rasterToPolygons(r2, fun = function(x) !is.na(x) & x != 0, dissolve = TRUE)
  p <- sf::st_sf(geometry = sf::st_union(sf::st_as_sf(p)))
  sf::st_crs(p) <- 4326
  .viirs_pol[[ym]] <<- p
  p
}
modis_outline <- function(ym) {
  p <- flh.polys[[paste0("X", ym)]]
  if (is.null(p)) return(NULL)
  s <- suppressWarnings(sf::st_as_sf(p))
  if (is.na(sf::st_crs(s))) sf::st_crs(s) <- 4326 else s <- sf::st_transform(s, 4326)
  simplify_outline(s)   # 1-km pixel polygons carry ~4,000 vertices a month; outline only
}
hull_outline <- function(ym) simplify_outline(pol_list[[ym]])
outline_of <- function(ym, src) switch(src, viirs = viirs_outline(ym), modis = modis_outline(ym),
                                       pred = , hull = hull_outline(ym))
outline_col <- c(viirs = "deepskyblue4", modis = "darkorange3", hull = "black", pred = "black")

# A small cells/L colour bar in the right margin of the current panel, with
# the same bin-to-colour mapping as the map (one rect per ten of the 400 bins).
colorbar_legend <- function(cex = 0.5) {
  op <- par(xpd = NA); on.exit(par(op))
  n <- 40; x1 <- xlim[2] + 0.12; x2 <- xlim[2] + 0.42
  yy <- seq(ylim[1], ylim[2], length.out = n + 1)
  rect(x1, yy[-(n + 1)], x2, yy[-1], col = color[1 + 10 * seq_len(n) - 4], border = NA)
  rect(x1, ylim[1], x2, ylim[2], border = "gray30", lwd = 0.5)
  at <- c(1e4, 1e6, 2e6, 3e6, 4e6)
  ya <- ylim[1] + (at - 1e4) / (4e6 - 1e4) * diff(ylim)
  segments(x2, ya, x2 + 0.08, ya, lwd = 0.5)
  text(x2 + 0.12, ya, c("10k", "1M", "2M", "3M", "4M"), adj = 0, cex = cex)
  text((x1 + x2) / 2, ylim[2] + 0.12, "cells/L", adj = c(0.5, 0), cex = cex)
}
# Counts by FWC abundance class, for sample counts or map cells alike (NA
# ignored): positives (> 0) and the five classes of the sample legend, with
# FWC's right-closed bounds: <= 1,000 background, 1,000-10,000 very low,
# 10,000-100,000 low, 100,000-1,000,000 medium, > 1,000,000 high. The five
# classes partition the positives.
class_names  <- c("n_pos", "n_le1e3", "n_1e3_1e4", "n_1e4_1e5", "n_1e5_1e6", "n_gt1e6")
class_labels <- c("positives", "<= 1,000", "1,000 - 10,000", "10,000 - 100,000",
                  "100,000 - 1,000,000", "> 1,000,000")
class_counts <- function(v) {
  v <- v[!is.na(v) & v > 0]
  k <- cut(v, sbrks, labels = FALSE, include.lowest = TRUE)
  setNames(c(length(v), tabulate(k, nbins = 5)), class_names)
}
info_lines <- function(cnt) paste(fmt_n(cnt), class_labels)

draw_panel <- function(v, main, pts = NULL, all_pts = FALSE, zeros = TRUE, outline = NULL, ocol = "black",
                       used = FALSE, placeholder = NULL, axes = TRUE, cex_main = 0.85,
                       info = NULL, cex_info = 0.6, cbar = FALSE, cex_pts = 0.7, olwd = 1.4) {
  plot(NA, xlim = xlim, ylim = ylim, xlab = "", ylab = "", asp = 1 / cos(27.5 * pi / 180),
       main = main, cex.main = cex_main, xaxs = "i", yaxs = "i", axes = FALSE)
  rect(xlim[1], ylim[1], xlim[2], ylim[2], col = if (is.null(v) && is.null(placeholder)) "white" else "darkgray", border = NA)
  if (!is.null(v) && is.null(placeholder)) {
    # useRaster = TRUE embeds the 66 x 78 grid as a bitmap (no interpolation),
    # as raster::plot() does in the pipeline PDFs; vector rects made the
    # 329-page PDF 34 MB.
    image(xs, ys, to_z(v), breaks = brks_img, col = color, add = TRUE, useRaster = TRUE)
  } else if (!is.null(placeholder)) {
    text(mean(xlim), mean(ylim), placeholder, cex = 0.9 * cex_main / 0.85)
  }
  plot(sf::st_geometry(fl), add = TRUE, col = "wheat", border = "gray40")
  if (!is.null(outline)) plot(sf::st_geometry(outline), add = TRUE, border = ocol, col = NA, lwd = olwd)
  if (!is.null(pts) && nrow(pts) > 0) {
    if (all_pts) {
      z0 <- pts[pts$cells == 0, ]
      if (zeros) points(z0$lon, z0$lat, pch = ".", cex = 1.8, col = "gray45")
      pp <- pts[pts$cells > 0, ]
      bins <- cut(pp$cells, sbrks, labels = FALSE, include.lowest = TRUE)
      points(pp$lon, pp$lat, pch = 21, bg = spal[bins], col = "black", cex = cex_pts, lwd = 0.5)
    } else {
      pp <- pts[pts$cells >= thr_bloom, ]
      points(pp$lon, pp$lat, pch = 1, cex = 0.6, col = "black", lwd = 0.7)
    }
  }
  if (!is.null(info)) legend("left", legend = info, bty = "o", bg = "white", box.col = "gray60",
                             cex = cex_info, inset = 0.01, x.intersp = 0.3, y.intersp = 0.9)
  if (cbar) colorbar_legend()
  if (axes) { axis(1, cex.axis = 0.7, padj = -1); axis(2, cex.axis = 0.7, las = 1, hadj = 0.8) }
  box(col = if (used) "red" else "black", lwd = if (used) 3 else 1)
}
sample_legend <- function(cex = 0.6) legend("bottomleft", legend = slabs, pt.bg = spal, pch = 21, cex = cex,
                                            title = "samples, cells/L", bg = "white", box.col = "gray60")
cells_legend <- function() {
  op <- par(no.readonly = TRUE); on.exit(par(op))
  par(mfrow = c(1, 1), mar = c(0, 0, 0, 0), oma = c(0, 0, 0, 1), new = TRUE)
  fields::image.plot(legend.only = TRUE, zlim = range(brks[-length(brks)]),
                     breaks = brks[-length(brks)], col = color[-1],
                     legend.width = 0.8, legend.mar = 5, legend.line = 3.3, legend.lab = "cells/L",
                     axis.args = list(cex.axis = 0.7, at = c(1e4, 1e6, 2e6, 3e6, 4e6),
                                      labels = c("10,000", "1,000,000", "2,000,000", "3,000,000", "4,000,000")))
}
fmt_n <- function(x) format(x, big.mark = ",")
fit_label <- function(r) if (r$fit_status == "fitted") paste0("fitted, converged = ", r$converged) else r$fit_status
draw_page <- function(ym, layout = TRUE, zeros = TRUE) {
  r <- tab[tab$yrmo == ym, ]
  p <- by_m[[ym]]
  if (layout) par(mfrow = c(1, 4), mar = c(2.2, 2.8, 2.6, 0.6), oma = c(0, 0, 4.2, 6.5))
  draw_panel(U[, ym], sprintf("Unclipped sdmTMB (%s)\nbloom area %s km2, max %s cells/L", fit_label(r),
                              fmt_n(round(r$area_1e4_unclip_km2)), fmt_n(round(r$unclip_max))),
             pts = p, all_pts = TRUE, zeros = zeros, outline = outline_of(ym, r$use), ocol = outline_col[[r$use]])
  sample_legend()
  if (ym %in% colnames(Vc)) {
    draw_panel(Vc[, ym], sprintf("%sVIIRS-clipped (%d positive VIIRS cells)\nbloom area %s km2",
                                 if (r$use == "viirs") "USED: " else "", r$viirs_n_pos_cells,
                                 fmt_n(round(r$area_1e4_viirs_km2))),
               pts = if (r$use == "viirs") p else NULL, outline = viirs_outline(ym), ocol = outline_col[["viirs"]], used = r$use == "viirs")
  } else draw_panel(NULL, "VIIRS-clipped", placeholder = if (r$viirs_status == "missing") "VIIRS tif missing for this month" else "no VIIRS layer (outside 2012-2024)")
  if (ym %in% colnames(Mc)) {
    draw_panel(Mc[, ym], sprintf("%sMODIS nFLH-clipped (%d polygon(s))\nbloom area %s km2",
                                 if (r$use == "modis") "USED: " else "", r$modis_n_polys,
                                 fmt_n(round(r$area_1e4_modis_km2))),
               pts = if (r$use == "modis") p else NULL, outline = modis_outline(ym), ocol = outline_col[["modis"]], used = r$use == "modis")
  } else draw_panel(NULL, "MODIS nFLH-clipped", placeholder = "no MODIS polygon for this month")
  draw_panel(H[, ym], sprintf("%sHull-clipped (%s footprint(s), %s km2)\nbloom area %s km2",
                              if (r$use == "pred") "USED: " else "",
                              ifelse(is.na(r$hull_n_polys), 0, r$hull_n_polys),
                              fmt_n(round(ifelse(is.na(r$hull_footprint_km2), 0, r$hull_footprint_km2))),
                              fmt_n(round(r$area_1e4_hull_km2))),
             pts = if (r$use == "pred") p else NULL, outline = hull_outline(ym), ocol = outline_col[["hull"]], used = r$use == "pred")
  flags <- c("zeroed_fit", "low_vs_hull", "samples_outside")[unlist(r[c("flag_zeroed_fit", "flag_low_vs_hull", "flag_samples_outside")])]
  mtext(sprintf("%s-%s   |   source used: %s   |   VIIRS layer: %s%s",
                substr(ym, 1, 4), substr(ym, 5, 6), ifelse(r$use == "pred", "hull", r$use),
                sub("_", " ", r$viirs_status),
                if (length(flags)) paste0("   |   FLAGS: ", paste(flags, collapse = ", ")) else ""),
        outer = TRUE, cex = 1, font = 2, line = 2.3)
  mtext(sprintf("samples %s, positives %s, >= 10,000 cells/L: %s, >= 100,000: %s (max %s cells/L)   |   final bloom area = %s%% of the hull-clipped one   |   %s of %s water samples >= 10,000 cells/L inside the final footprint",
                fmt_n(r$n_samples), fmt_n(r$n_pos), fmt_n(r$n_pos_1e4), fmt_n(r$n_pos_1e5), fmt_n(round(r$max_cells)),
                ifelse(is.na(r$hull_ratio_1e4), "-", pct(r$hull_ratio_1e4)), r$n_pos_1e4_in_fp, r$n_pos_1e4_water),
        outer = TRUE, cex = 0.85, line = 0.8)
  cells_legend()
}

# Figures for the issue -------------------------------------------------------
# Fig 1: VIIRS status calendar.
era$status <- factor(era$viirs_status, levels = c("positive", "zero", "missing"),
                     labels = c("VIIRS positive cells", "VIIRS all zero", "VIIRS tif missing"))
era$bold <- ifelse(era$n_pos_1e5 > 0, "bold", "plain")
g1 <- ggplot(era, aes(x = month, y = year)) +
  geom_tile(aes(fill = status), colour = "white", linewidth = 0.6) +
  geom_tile(data = era[era$flag_zeroed_fit, ], fill = NA, colour = "red", linewidth = 1.1) +
  geom_text(aes(label = n_pos, fontface = bold), size = 2.8) +
  scale_fill_manual(values = c("VIIRS positive cells" = "#9ecae1", "VIIRS all zero" = "gray88",
                               "VIIRS tif missing" = "khaki"), name = NULL) +
  scale_x_continuous(breaks = 1:12, labels = month.abb, expand = c(0, 0)) +
  scale_y_reverse(breaks = unique(era$year), expand = c(0, 0)) +
  labs(x = NULL, y = NULL,
       title = "VIIRS monthly layers, 2012-2024: satellite status vs in-situ positives",
       subtitle = "Tile text = positive FWC samples that month (bold: at least one sample >= 100,000 cells/L). Red border = fitted sdmTMB surface written as an all-zero map.") +
  theme_minimal(base_size = 11) + theme(legend.position = "bottom", panel.grid = element_blank(),
                                        plot.subtitle = element_text(size = 8.5))
ggsave(file.path(dir_docs, "fig1_viirs_calendar.png"), g1, width = 9, height = 7.5, dpi = 300, bg = "white")

# Fig 2: in-situ positives vs VIIRS positive cells, monthly.
era$date <- as.Date(sprintf("%d-%02d-01", era$year, era$month))
era$date_end <- as.Date(sprintf("%d-%02d-01", ifelse(era$month == 12, era$year + 1, era$year),
                                ifelse(era$month == 12, 1, era$month + 1)))
long2 <- rbind(
  data.frame(date = era$date, panel = "FWC samples: positive (light) and >= 100,000 cells/L (dark)",
             value = era$n_pos, part = "positive"),
  data.frame(date = era$date, panel = "FWC samples: positive (light) and >= 100,000 cells/L (dark)",
             value = era$n_pos_1e5, part = "high"),
  data.frame(date = era$date, panel = "VIIRS cells with detection frequency > 0",
             value = ifelse(is.na(era$viirs_n_pos_cells), 0, era$viirs_n_pos_cells), part = "viirs"))
shade <- era[era$viirs_status == "zero", c("date", "date_end")]
g2 <- ggplot() +
  geom_rect(data = shade, aes(xmin = date, xmax = date_end, ymin = -Inf, ymax = Inf), fill = "gray90") +
  geom_col(data = long2[long2$part == "positive", ], aes(date, value), fill = "#9ecae1", width = 28) +
  geom_col(data = long2[long2$part == "high", ], aes(date, value), fill = "#08519c", width = 28) +
  geom_col(data = long2[long2$part == "viirs", ], aes(date, value), fill = "#636363", width = 28) +
  geom_point(data = era[era$flag_zeroed_fit, ], aes(date, y = 0), shape = 17, colour = "red", size = 1.6) +
  facet_wrap(~ panel, ncol = 1, scales = "free_y") +
  scale_x_date(date_breaks = "1 year", date_labels = "%Y", expand = c(0.005, 0)) +
  labs(x = NULL, y = NULL,
       title = "In-situ positives vs VIIRS detections by month, 2012-2024",
       subtitle = "Grey bands: months whose VIIRS layer has no positive cell (written as all-zero maps). Red triangles: fitted months zeroed that way.") +
  theme_minimal(base_size = 11) + theme(panel.grid.minor = element_blank(), plot.subtitle = element_text(size = 8.5))
ggsave(file.path(dir_docs, "fig2_insitu_vs_viirs.png"), g2, width = 11, height = 6, dpi = 300, bg = "white")

# Fig 3: unclipped vs final bloom area, fitted months.
ft <- tab[tab$fit_status == "fitted", ]
ft$source <- factor(ifelse(ft$use == "pred", "hull", ft$use), levels = c("viirs", "modis", "hull"))
ft$zeroed <- ifelse(ft$flag_zeroed_fit, "final map all zero", "final map non-zero")
g3a <- ggplot(ft, aes(area_1e4_unclip_km2, area_1e4_final_km2, colour = source)) +
  geom_abline(slope = 1, intercept = 0, linetype = 2, colour = "gray60") +
  geom_point(aes(shape = zeroed), size = 1.9, alpha = 0.8) +
  scale_shape_manual(values = c("final map all zero" = 4, "final map non-zero" = 16), name = NULL) +
  scale_colour_manual(values = c(viirs = "deepskyblue4", modis = "darkorange3", hull = "gray20"), name = "clip source") +
  scale_x_continuous(trans = scales::pseudo_log_trans(sigma = 100), breaks = c(0, 1e2, 1e3, 1e4, 1e5), labels = scales::comma) +
  scale_y_continuous(trans = scales::pseudo_log_trans(sigma = 100), breaks = c(0, 1e2, 1e3, 1e4, 1e5), labels = scales::comma) +
  labs(x = "unclipped bloom area, km2 (cells >= 10,000 cells/L)", y = "final map bloom area, km2",
       title = "Bloom area before and after clipping, fitted months") +
  theme_minimal(base_size = 11)
g3b <- ggplot(ft[!is.na(ft$retained_1e4), ], aes(source, retained_1e4, colour = source)) +
  geom_boxplot(outlier.shape = NA, width = 0.5) +
  geom_point(position = position_jitter(width = 0.18, height = 0, seed = 1), size = 1.2, alpha = 0.5) +   # seeded: byte-identical across runs
  scale_colour_manual(values = c(viirs = "deepskyblue4", modis = "darkorange3", hull = "gray20"), guide = "none") +
  scale_y_continuous(labels = scales::percent) +
  labs(x = "clip source", y = "share of unclipped bloom area kept", title = "Retention by clip source") +
  theme_minimal(base_size = 11)
g3 <- cowplot::plot_grid(g3a, g3b, ncol = 2, rel_widths = c(1.6, 1))
ggsave(file.path(dir_docs, "fig3_bloom_area_unclipped_vs_final.png"), g3, width = 12, height = 5, dpi = 300, bg = "white")

# Fig 4: headline months, unclipped / final / hull alternative / MODIS alternative.
hl <- headline[headline %in% tab$yrmo]
png(file.path(dir_docs, "fig4_headline_months.png"), width = 11, height = 2.6 * length(hl), units = "in", res = 110)
par(mfrow = c(length(hl), 4), mar = c(1.2, 1.6, 2.4, 0.4), oma = c(0, 0, 2.5, 0))
for (ym in hl) {
  r <- tab[tab$yrmo == ym, ]; p <- by_m[[ym]]
  lab <- paste0(substr(ym, 1, 4), "-", substr(ym, 5, 6))
  draw_panel(U[, ym], sprintf("%s unclipped (%s positives, %s >= 1e5)", lab, fmt_n(r$n_pos), fmt_n(r$n_pos_1e5)),
             pts = p, all_pts = TRUE, axes = FALSE)
  draw_panel(Fm[, ym], sprintf("%s final map (%s): %s km2", lab, ifelse(r$use == "pred", "hull", r$use),
                               fmt_n(round(r$area_1e4_final_km2))), pts = p, axes = FALSE, used = TRUE)
  draw_panel(H[, ym], sprintf("%s hull-clipped alternative: %s km2", lab, fmt_n(round(r$area_1e4_hull_km2))),
             pts = p, outline = hull_outline(ym), axes = FALSE)
  if (ym %in% colnames(Mc))
    draw_panel(Mc[, ym], sprintf("%s MODIS-clipped alternative: %s km2", lab, fmt_n(round(r$area_1e4_modis_km2))),
               pts = p, outline = modis_outline(ym), ocol = outline_col[["modis"]], axes = FALSE)
  else draw_panel(NULL, sprintf("%s MODIS-clipped alternative", lab), placeholder = "no MODIS polygon", axes = FALSE)
}
mtext("Issue #5 headline months: fitted surface, the all-zero final map, and the two clipping alternatives already on disk (open circles: samples >= 10,000 cells/L)",
      outer = TRUE, cex = 0.95, font = 2)
dev.off()
message("Figures written to ", dir_docs)

# Per-month PDF -----------------------------------------------------------------
if (render_pdf) {
  pages <- if (quick) hl else fitted_months
  file_pdf <- file.path(dir_docs, "clip_check_issue6.pdf")
  file_tmp <- file.path(dir_docs, "clip_check_issue6_tmp.pdf")
  opened <- tryCatch({ pdf(file_tmp, width = 16, height = 5, onefile = TRUE); TRUE },
                     error = function(e) { warning("Cannot open ", file_tmp, ": ", conditionMessage(e), call. = FALSE); FALSE })
  if (opened) {
    # zero-count samples are left off the PDF pages (the title carries the counts) to keep the file small
    tryCatch(for (ym in pages) draw_page(ym, zeros = FALSE), finally = dev.off())
    if (file.exists(file_pdf) && !file.remove(file_pdf))
      warning("Could not replace ", file_pdf, " (open in a viewer?); the new file is ", file_tmp, call. = FALSE)
    else { file.rename(file_tmp, file_pdf); message("PDF written: ", file_pdf, " (", length(pages), " pages)") }
  }
}
# Two pages as PNG for a quick visual check without a PDF viewer (gitignored folder).
for (ym in c("201702", "201810")) {
  if (!(ym %in% tab$yrmo)) next
  png(file.path(dir_clipped, paste0("clip_page_", ym, ".png")), width = 16, height = 5, units = "in", res = 100)
  draw_page(ym); dev.off()
}
message("Sample pages in ", dir_clipped)

# Class counts per month and map (the numbers in the count boxes), as a CSV ------
# Columns <map>_<class>: map = fwc (samples), unclip, viirs, modis, hull, final;
# class = n_pos (> 0), n_le1e3, n_1e3_1e4, n_1e4_1e5, n_1e5_1e6, n_gt1e6. NA when
# the month has no samples / no fit / no VIIRS layer / no MODIS polygon.
cls <- do.call(rbind, lapply(key, function(ym) {
  r <- tab[tab$yrmo == ym, ]
  p <- by_m[[ym]]
  one <- function(v, has) if (has) class_counts(v) else setNames(rep(NA_integer_, 6), class_names)
  out <- c(one(if (is.null(p)) NULL else p$cells, !is.null(p)),
           one(U[, ym], r$fit_status != "none"),
           one(if (ym %in% colnames(Vc)) Vc[, ym] else NULL, ym %in% colnames(Vc)),
           one(if (ym %in% colnames(Mc)) Mc[, ym] else NULL, ym %in% colnames(Mc)),
           one(H[, ym], TRUE),
           one(Fm[, ym], TRUE))
  names(out) <- paste(rep(c("fwc", "unclip", "viirs", "modis", "hull", "final"), each = 6), class_names, sep = "_")
  data.frame(yrmo = ym, use = r$use, as.list(out), stringsAsFactors = FALSE)
}))
stopifnot(nrow(cls) == length(key),
          all(cls$fwc_n_pos[!is.na(cls$fwc_n_pos)] == tab$n_pos[!is.na(cls$fwc_n_pos)]),
          all(tab$n_samples[is.na(cls$fwc_n_pos)] == 0),
          all(rowSums(cls[, paste0("fwc_", class_names[-1])], na.rm = TRUE) == ifelse(is.na(cls$fwc_n_pos), 0, cls$fwc_n_pos)),
          all(rowSums(cls[, paste0("final_", class_names[-1])]) == cls$final_n_pos))
file_cls <- file.path(dir_docs, "clip_class_counts_issue6.csv")
write.csv(cls, file_cls, row.names = FALSE)
message("Class counts written: ", file_cls, " (", nrow(cls), " rows)")

# One-row-per-month PDF ----------------------------------------------------------
# Columns: FWC samples | unclipped | VIIRS-clipped | MODIS-clipped | hull-clipped.
# Every panel carries a count box (positives and the five FWC classes: samples in
# column A, grid cells elsewhere) and a legend; the clipped panel the final map
# uses is framed in red. Months without samples or without a fit keep their row.
draw_row <- function(ym) {
  r <- tab[tab$yrmo == ym, ]
  p <- by_m[[ym]]
  lab <- paste0(substr(ym, 1, 4), "-", substr(ym, 5, 6))
  cm <- 0.75
  # A: raw FWC counts
  if (is.null(p)) {
    draw_panel(NULL, paste("FWC counts", lab), placeholder = "no samples", axes = FALSE, cex_main = cm)
  } else {
    draw_panel(NULL, paste("FWC counts", lab), pts = p, all_pts = TRUE, axes = FALSE, cex_main = cm,
               cex_pts = 0.5, info = info_lines(class_counts(p$cells)))
    sample_legend(cex = 0.48)
  }
  # B: unclipped
  if (r$fit_status == "fitted") {
    draw_panel(U[, ym], "sdmTMB unclipped", axes = FALSE, cex_main = cm, cbar = TRUE,
               info = info_lines(class_counts(U[, ym])))
  } else {
    draw_panel(NULL, "sdmTMB unclipped", axes = FALSE, cex_main = cm,
               placeholder = if (r$fit_status == "failed") "fit failed" else sprintf("no fit (%d positives)", r$n_pos))
  }
  # C: VIIRS
  if (ym %in% colnames(Vc)) {
    draw_panel(Vc[, ym], "VIIRS clipped", axes = FALSE, cex_main = cm, cbar = TRUE, used = r$use == "viirs",
               outline = viirs_outline(ym), ocol = "gray50", olwd = 0.5, info = info_lines(class_counts(Vc[, ym])))
  } else {
    draw_panel(NULL, "VIIRS clipped", axes = FALSE, cex_main = cm,
               placeholder = if (r$viirs_status == "missing") "VIIRS tif missing" else "no VIIRS layer")
  }
  # D: MODIS
  if (ym %in% colnames(Mc)) {
    draw_panel(Mc[, ym], "MODIS clipped", axes = FALSE, cex_main = cm, cbar = TRUE, used = r$use == "modis",
               outline = modis_outline(ym), ocol = "gray50", olwd = 0.5, info = info_lines(class_counts(Mc[, ym])))
  } else {
    draw_panel(NULL, "MODIS clipped", axes = FALSE, cex_main = cm, placeholder = "no MODIS polygon")
  }
  # E: hulls (a layer exists for every month; all zero when there is no footprint or no fit)
  draw_panel(H[, ym], "Hulls", axes = FALSE, cex_main = cm, cbar = TRUE, used = r$use == "pred",
             outline = hull_outline(ym), ocol = "gray50", olwd = 0.5, info = info_lines(class_counts(H[, ym])))
}
page_chunks <- split(key, ceiling(seq_along(key) / rows_per_page))
page_title <- function(ch) if (length(ch) == 12 && substr(ch[1], 5, 6) == "01") substr(ch[1], 1, 4) else
  paste(paste0(substr(ch[1], 1, 4), "-", substr(ch[1], 5, 6)), "to", paste0(substr(ch[length(ch)], 1, 4), "-", substr(ch[length(ch)], 5, 6)))
draw_month_page <- function(ch) {
  par(mfrow = c(rows_per_page, 5), mar = c(0.4, 0.5, 1.5, 2.1), oma = c(0.3, 0, 2.0, 0))
  for (ym in ch) draw_row(ym)
  mtext(sprintf("%s   |   FWC counts  |  sdmTMB unclipped  |  VIIRS clipped  |  MODIS clipped  |  hulls   (red frame = used in the final map)", page_title(ch)),
        outer = TRUE, cex = 1, font = 2, line = 0.5)
}
page_w <- 11; page_h <- 2.35 * rows_per_page + 0.9
if (monthly_pdf) {
  chunks <- if (quick) page_chunks[vapply(page_chunks, function(ch) any(ch %in% hl), logical(1))] else page_chunks
  file_mpdf <- file.path(dir_docs, "clip_months_issue6.pdf")
  file_mtmp <- file.path(dir_docs, "clip_months_issue6_tmp.pdf")
  opened <- tryCatch({ pdf(file_mtmp, width = page_w, height = page_h, onefile = TRUE); TRUE },
                     error = function(e) { warning("Cannot open ", file_mtmp, ": ", conditionMessage(e), call. = FALSE); FALSE })
  if (opened) {
    tryCatch(for (ch in chunks) draw_month_page(ch), finally = dev.off())
    if (file.exists(file_mpdf) && !file.remove(file_mpdf))
      warning("Could not replace ", file_mpdf, " (open in a viewer?); the new file is ", file_mtmp, call. = FALSE)
    else { file.rename(file_mtmp, file_mpdf)
           message("Monthly PDF written: ", file_mpdf, " (", length(chunks), " pages, ",
                   round(file.size(file_mpdf) / 1e6, 1), " MB)") }
  }
}
# Two year-pages as PNG for a visual check (gitignored folder).
for (y in c("2017", "2018")) {
  ch <- key[substr(key, 1, 4) == y]
  if (length(ch) == 0) next
  png(file.path(dir_clipped, paste0("clip_months_", y, ".png")), width = page_w, height = page_h, units = "in", res = 90)
  draw_month_page(ch); dev.off()
}
cat("\nDone.\n")
