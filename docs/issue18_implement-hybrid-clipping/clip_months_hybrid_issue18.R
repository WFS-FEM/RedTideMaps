#' Issue #18, step 6: the monthly comparison PDF with the hybrid column.
#'
#' One row per month for all 504 months (1985-01 to 2026-12), twelve rows (one calendar
#' year) per page, in the layout of the #6 PDF (docs/issue6_VIIRS-zeros/clip_months_issue6.pdf),
#' with a sixth column for the delivered map:
#'   A  the FWC samples of the month, filled by abundance class, with the class counts
#'   B  the sdmTMB prediction, unclipped
#'   C  the prediction clipped to the positive VIIRS cells
#'   D  the prediction clipped to the MODIS nFLH polygons
#'   E  the prediction clipped to the buffered hulls
#'   F  the delivered map: the nearshore hybrid (rule mask5adj) of the framed panel and
#'      the hulls, i.e. the combined stack the ASCII files are written from
#' The red frame keeps the #6 meaning: the clip the final map is built on (C in VIIRS
#' months, D in MODIS months, E in hull months). F is always the delivered map, drawn with
#' the outline of the framed panel and the nearshore set outlined in black. Every map panel
#' (B to F) prints its total exposure, the sum of cells/L over the water cells of that map
#' (as Ecospace integrates it), then the positives and the five FWC classes (samples in A,
#' grid cells in B to F). Land is drawn as the land cells of the 5-arcmin template (NA in
#' the depth grid, NODATA in the ASCII files), what the maps carry and Ecospace sees, not
#' as a coastline polygon.
#'
#' Reads only what the last 5-arcmin pipeline run left on disk (out/5min/) and the tracked
#' tables, and asserts first that the run on disk is the delivered one (its ASCII files
#' equal tables/md5_refresh5_issue18.csv and the combined stack cell for cell). Nothing is
#' refit or re-clipped. No RNG; the CSV and the PNG are byte-identical from run to run (the
#' PDF carries the two date lines every R pdf() device writes).
#'
#' Run from the repo root:
#'   Rscript docs/issue18_implement-hybrid-clipping/clip_months_hybrid_issue18.R   (3 to 6 min)
#'   RT_QA_QUICK=1            draw only the pages holding the 16 headline months of #6
#'   RT_QA_PNG_DIR=<folder>   also render the pages of RT_QA_PNG_YEARS (default
#'                            1990,2012,2017,2018,2026) as PNG previews (PDFs cannot be read here)
#'
#' Output (docs/issue18_implement-hybrid-clipping/):
#'   clip_months_hybrid_issue18.pdf                 42 pages, 13.2 x 29.1 in
#'   tables/clip_class_counts_hybrid_issue18.csv    the count-box numbers and the exposures, one month per row
#'   figures/fig3_monthly_rows_example_issue18.png  four example rows, 2012-01 to 2012-04 (the #6 example months)
#'   console: the checks and the summary

# Repo root: the working directory if it holds the .Rproj, else two levels above this script.
.root <- local({
  if (file.exists("RedTideMaps.Rproj")) return(normalizePath(getwd(), winslash = "/"))
  f <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE))
  if (length(f) == 1) {
    d <- normalizePath(file.path(dirname(f), "..", ".."), winslash = "/", mustWork = FALSE)
    if (file.exists(file.path(d, "RedTideMaps.Rproj"))) return(d)
  }
  stop("Run from the repo root: Rscript docs/issue18_implement-hybrid-clipping/clip_months_hybrid_issue18.R", call. = FALSE)
})
source(file.path(.root, "scripts", "_setup.R"))   # sf, raster, viridis, ...

# Parameters ---------------------------------------------------------------------
thr_bloom     <- 1e4        # cells/L: the first coloured bin of the map PDFs
rule_name     <- "mask5adj"
rows_per_page <- 12L        # one calendar year per page
viirs_era     <- c("201201", "202412")
quick     <- nzchar(Sys.getenv("RT_QA_QUICK"))
png_dir   <- Sys.getenv("RT_QA_PNG_DIR", "")
png_years <- strsplit(Sys.getenv("RT_QA_PNG_YEARS", "1990,2012,2017,2018,2026"), ",")[[1]]
# Frozen numbers, asserted below (the #18 runs of 23 Oct 2026 and the #6 inputs).
expected <- list(n_months = 504L,
                 use = c(hybrid = 155L, hybrid_modis = 123L, pred = 226L),
                 n_changed = 210L, n_changed_viirs = 121L, n_changed_modis = 89L,
                 viirs_layers = 155L, viirs_zero = 89L, set_cells = 189L,
                 n_land = 1310L, n_water = 3838L,   # the 5-arcmin template: land = the NA cells of the depth grid (no zero depth), NODATA in every ASCII file
                 fit = c(fitted = 331L, failed = 5L, none = 168L),   # from the unclipped layers of the refresh run (23 Oct 2026; the #6 run of 6 Oct had 329 / 5 / 170)
                 n_headline = 16L,
                 refreshed = c("202609", "202610"),   # the hull months the refresh run changed against the frozen record table
                 samples_file = "FWC HAB data 19800102-20261021_filtered.Rdata")

# Paths --------------------------------------------------------------------------
dir_out      <- file.path(.root, "out", "5min")
dir_sdm      <- file.path(dir_out, "sdm")
dir_clipped  <- file.path(dir_out, "clipped")
dir_combined <- file.path(dir_out, "combined")
dir_ascii    <- file.path(dir_out, "ecospace_ascii")
dir_docs     <- file.path(.root, "docs", "issue18_implement-hybrid-clipping")
dir_tab      <- file.path(dir_docs, "tables")
dir_fig      <- file.path(dir_docs, "figures")
for (d in c(dir_tab, dir_fig)) dir.create(d, recursive = TRUE, showWarnings = FALSE)
one_file <- function(dir, pattern, what) {
  f <- list.files(dir, pattern = pattern, full.names = TRUE)
  if (length(f) != 1) stop("Expected one ", what, " in ", dir, " (found ", length(f), "); run the pipeline first.", call. = FALSE)
  f
}
grd  <- function(f) sub("[.]grd$", "", f)
need <- function(...) for (f in c(...)) if (!file.exists(f)) stop("Missing ", f, call. = FALSE)
file_depth     <- one_file(file.path(.root, "template rasters"), "^depth 5min .*[.]asc$", "depth template")
file_unclip    <- grd(one_file(dir_sdm,      "^sdmTMB_log_stack_[0-9]{6}-[0-9]{6}[.]grd$", "unclipped stack"))
file_hull      <- grd(one_file(dir_clipped,  "_clipped_hull[.]grd$",  "hull-clipped stack"))
file_viirs     <- grd(one_file(dir_clipped,  "_clipped_viirs[.]grd$", "VIIRS-clipped stack"))
file_modis     <- grd(one_file(dir_clipped,  "_clipped_modis[.]grd$", "MODIS-clipped stack"))
file_hyv       <- grd(one_file(dir_clipped,  "_clipped_hybrid[.]grd$", "VIIRS hybrid stack"))
file_hym       <- grd(one_file(dir_clipped,  "_clipped_hybrid_modis[.]grd$", "MODIS hybrid stack"))
file_final     <- grd(one_file(dir_combined, "_clipped_combined[.]grd$", "combined stack"))
file_mask      <- file.path(dir_clipped, paste0("nearshore_mask_", rule_name, ".grd"))
file_viirs_raw <- grd(one_file(file.path(.root, "VIIRS"), "^VIIRS_[0-9]{6}-[0-9]{6}[.]grd$", "VIIRS stack"))
file_modis_pol <- one_file(file.path(.root, "MODIS"), "^FLH polys.*[.]Rdata$", "MODIS polygon file")
file_clipsrc   <- file.path(dir_clipped, "clipping_source.csv")
file_fitmat    <- file.path(dir_sdm, "RT_fit_matrix.RData")
file_md5ref    <- file.path(dir_tab, "md5_refresh5_issue18.csv")
file_rec       <- file.path(dir_tab, "record_months_issue18.csv")
file_refm      <- file.path(dir_tab, "refresh_months5_issue18.csv")
file_tab6      <- file.path(.root, "docs", "issue6_VIIRS-zeros", "tables", "clip_comparison_issue6.csv")
# Several *_filtered.Rdata accumulate (one per FWC cache date); the newest by the end date in its name.
ff <- list.files(dir_sdm, pattern = "_filtered[.]Rdata$", full.names = TRUE)
if (length(ff) == 0) stop("No *_filtered.Rdata in ", dir_sdm, "; run the pipeline first.", call. = FALSE)
ff_end <- as.integer(substr(regmatches(basename(ff), regexpr("[0-9]{8}_filtered", basename(ff))), 1, 8))
file_filtered  <- ff[which.max(ff_end)]
file_hullpolys <- sub("_filtered[.]Rdata$", "_hullpolys.Rdata", file_filtered)
need(file_mask, file_clipsrc, file_fitmat, file_hullpolys, file_md5ref, file_rec, file_refm, file_tab6)
message("Samples: ", basename(file_filtered))

# Load ---------------------------------------------------------------------------
depth    <- raster::raster(file_depth)
dv       <- raster::values(depth)
land     <- is.na(dv); water <- !land
cell_km2 <- raster::values(raster::area(depth))
nr <- nrow(depth); nc <- ncol(depth); n5 <- raster::ncell(depth)
xy5 <- raster::xyFromCell(depth, seq_len(n5))
atl <- xy5[, 1] > -82 & xy5[, 2] > 28.5         # the Atlantic-side box: never in a nearshore set (Holden, 22 Oct 2026)
# Each stack is read once as a cell x month matrix (indexing a 504-band file layer by layer is slow).
read_mat <- function(f) {
  b <- raster::brick(f)
  stopifnot(raster::compareRaster(depth, b))
  m <- raster::values(b); colnames(m) <- sub("^X", "", names(b)); m
}
norm_map <- function(M) { M[is.na(M)] <- 0; M[land, ] <- NA; M }   # as make_redtide_ascii() writes every layer
same  <- function(a, b) all((a == b) | (is.na(a) & is.na(b)))
fmt_n <- function(x) format(x, big.mark = ",", trim = TRUE, scientific = FALSE)
U  <- read_mat(file_unclip); U[land, ] <- NA   # the prediction grid includes land cells; mask like the clipped stacks
H  <- read_mat(file_hull)      # hull-clipped
Vc <- read_mat(file_viirs)     # VIIRS-clipped (one layer per VIIRS month)
Mc <- read_mat(file_modis)     # MODIS-clipped (one layer per month with a MODIS polygon)
Hv <- read_mat(file_hyv)       # the VIIRS hybrid (the VIIRS months)
Hm <- read_mat(file_hym)       # the MODIS hybrid (the MODIS-served months)
Fm <- read_mat(file_final)     # the combined stack: the delivered map of every month
key <- colnames(U)
set_r <- raster::raster(file_mask); stopifnot(raster::compareRaster(depth, set_r))
set_v <- raster::values(set_r); set <- set_v %in% 1
Vraw <- raster::brick(file_viirs_raw)
stopifnot(isTRUE(all.equal(as.vector(raster::extent(Vraw)), as.vector(raster::extent(depth)))))
Vr <- raster::values(Vraw); colnames(Vr) <- sub("^X", "", names(Vraw))
viirs_n_pos <- colSums(Vr > 0, na.rm = TRUE)
clipsrc <- read.csv(file_clipsrc, stringsAsFactors = FALSE)
clipsrc$yrmo <- sub("^X", "", clipsrc$yrmo)
load(file_fitmat)        # fit_matrix (character)
fm <- as.data.frame(fit_matrix, stringsAsFactors = FALSE)
fm <- fm[is.na(fm$model) | fm$model != "fit_sdmTMBnb", ]
fm$yrmo <- sprintf("%04d%02d", as.integer(fm$year), as.integer(fm$month))
load(file_filtered)      # filtered_points_df (sf)
load(file_hullpolys)     # pol_list (sf per month, names "198509")
load(file_modis_pol)     # flh.polys (sp per month, names "X200207")
t6  <- read.csv(file_tab6, colClasses = c(yrmo = "character"), stringsAsFactors = FALSE)
hl  <- t6$yrmo[t6$zeroed_material]   # the 16 headline months of #6
rec <- read.csv(file_rec, colClasses = c(yrmo = "character"), stringsAsFactors = FALSE)
refm <- read.csv(file_refm, colClasses = c(yrmo = "character"), stringsAsFactors = FALSE)

# Samples: one grid lookup for all rows (#6) ---------------------------------------
pts <- sf::st_drop_geometry(filtered_points_df)
pts$cells <- suppressWarnings(as.numeric(pts$cells))
n_cells_na <- sum(is.na(pts$cells))
pts <- pts[!is.na(pts$cells), ]
pts$yrmo <- sprintf("%d%02d", as.integer(pts$year), as.integer(pts$month))
pts$cell <- raster::cellFromXY(depth, cbind(pts$lon, pts$lat))
pts$water <- FALSE
ok <- !is.na(pts$cell)
pts$water[ok] <- water[pts$cell[ok]]
by_m <- split(pts, pts$yrmo)

# Per-month status --------------------------------------------------------------
fit_status_of <- function(v) { if (all(is.na(v))) return("none"); if (max(v, na.rm = TRUE) == 0) return("failed"); "fitted" }
viirs_status_of <- function(ym) {
  if (ym %in% names(viirs_n_pos)) return(if (viirs_n_pos[[ym]] > 0) "positive" else "zero")
  if (ym >= viirs_era[1] && ym <= viirs_era[2]) "missing" else "no_coverage"
}
months_v <- colnames(Hv); months_m <- colnames(Hm); months_h <- setdiff(key, c(months_v, months_m))
S_sat <- cbind(norm_map(Vc), norm_map(Mc[, months_m]))          # the satellite clip the final map is built on, normalised
sat_months <- colnames(S_sat)
tab <- data.frame(yrmo = key, year = as.integer(substr(key, 1, 4)), month = as.integer(substr(key, 5, 6)), stringsAsFactors = FALSE)
tab$use <- clipsrc$use[match(key, clipsrc$yrmo)]
tab$hybrid_changed <- clipsrc$hybrid_changed[match(key, clipsrc$yrmo)]
tab$sat_src <- c(hybrid = "viirs", hybrid_modis = "modis", pred = "hull")[tab$use]
tab$fit_status <- vapply(key, function(ym) fit_status_of(U[, ym]), character(1))
j_fm <- match(key, fm$yrmo)
tab$converged  <- ifelse(is.na(j_fm) | is.na(fm$model[j_fm]), NA_character_, fm$convergence[j_fm])   # NA: no fit attempted; "no model": both attempts failed
tab$viirs_status <- vapply(key, viirs_status_of, character(1))
tab$viirs_n_pos_cells <- ifelse(key %in% names(viirs_n_pos), as.integer(viirs_n_pos[key]), NA_integer_)
tab$n_samples <- vapply(key, function(ym) if (is.null(by_m[[ym]])) 0L else nrow(by_m[[ym]]), integer(1))
tab$n_pos     <- vapply(key, function(ym) if (is.null(by_m[[ym]])) 0L else sum(by_m[[ym]]$cells > 0), integer(1))
tab$final_n_changed <- 0L
tab$final_n_changed[match(sat_months, key)] <- as.integer(colSums(Fm[, sat_months] != S_sat, na.rm = TRUE))

# Checks, before any drawing --------------------------------------------------------
cat("\n=== checks ===\n")
# 1. The run on disk is the delivered one: the ASCII files equal the refresh-run MD5 table, and
#    the combined stack equals the ASCII files cell for cell (the NODATA value read as NA).
asc <- sort(list.files(dir_ascii, pattern = "^sdmTMB_log__[0-9]{6}[.]asc$"))
stopifnot(length(asc) == expected$n_months, length(list.files(dir_ascii, pattern = "[.]asc$")) == expected$n_months)
asc_md5 <- data.frame(yrmo = substr(asc, 13, 18), md5 = unname(tools::md5sum(file.path(dir_ascii, asc))), stringsAsFactors = FALSE)
md5ref  <- read.csv(file_md5ref, colClasses = c(yrmo = "character"), stringsAsFactors = FALSE)
stopifnot(setequal(asc_md5$yrmo, md5ref$yrmo), setequal(asc_md5$yrmo, key),
          all(asc_md5$md5 == md5ref$md5_now[match(asc_md5$yrmo, md5ref$yrmo)]))
stopifnot(basename(file_filtered) == expected$samples_file)
asc_bad <- character(0)
for (i in seq_along(asc)) {
  a <- raster::values(raster::raster(file.path(dir_ascii, asc[i]))); a[!is.na(a) & a < -1e30] <- NA
  if (!isTRUE(all.equal(a, unname(Fm[, asc_md5$yrmo[i]])))) asc_bad <- c(asc_bad, asc_md5$yrmo[i])
}
stopifnot(length(asc_bad) == 0)
cat("ASCII files: 504, MD5 equal to tables/md5_refresh5_issue18.csv (the delivered maps); the combined stack equals them cell for cell; samples ", basename(file_filtered), "  OK\n", sep = "")
# 2. clipping_source.csv against the stacks.
stopifnot(length(key) == expected$n_months, identical(key, colnames(H)), identical(key, colnames(Fm)),
          all(colnames(Vc) %in% key), all(colnames(Mc) %in% key), identical(colnames(Vc), months_v), all(months_m %in% colnames(Mc)),
          nrow(clipsrc) == expected$n_months, setequal(clipsrc$yrmo, key),
          all(clipsrc$viirs == (clipsrc$yrmo %in% colnames(Vc))), all(clipsrc$modis == (clipsrc$yrmo %in% colnames(Mc))),
          all(clipsrc$hybrid == (clipsrc$use == "hybrid")), all(clipsrc$hybrid_modis == (clipsrc$use == "hybrid_modis")),
          all(clipsrc$use == ifelse(clipsrc$viirs, "hybrid", ifelse(clipsrc$modis, "hybrid_modis", "pred"))),
          setequal(clipsrc$yrmo[clipsrc$use == "hybrid"], months_v), setequal(clipsrc$yrmo[clipsrc$use == "hybrid_modis"], months_m))
use_counts <- table(factor(tab$use, levels = names(expected$use)))
stopifnot(all(as.integer(use_counts) == expected$use), sum(tab$hybrid_changed) == expected$n_changed,
          sum(tab$hybrid_changed & tab$use == "hybrid") == expected$n_changed_viirs, sum(tab$hybrid_changed & tab$use == "hybrid_modis") == expected$n_changed_modis)
cat("clipping_source.csv: ", paste(names(use_counts), as.integer(use_counts), collapse = ", "), "; hybrid_changed in ", sum(tab$hybrid_changed), " months  OK\n", sep = "")
# 3. The combined stack: the hybrid stacks in the satellite months, the hull clip in the hull months, NA exactly on land.
stopifnot(all(is.na(Fm) == land), same(Fm[, months_v], Hv), same(Fm[, months_m], Hm), same(Fm[, months_h], norm_map(H)[, months_h]))
# 4. The hybrid relations: outside the set the satellite clip, inside it the cell-wise maximum with the hull clip, never below.
Hn <- norm_map(H)
stopifnot(all(is.na(Hv) == land), all(is.na(Hm) == land),
          same(Hv[!set, ], S_sat[!set, months_v]), same(Hv[set, ], pmax(S_sat[set, months_v], Hn[set, months_v])), all(Hv[water, ] >= S_sat[water, months_v]),
          same(Hm[!set, ], S_sat[!set, months_m]), same(Hm[set, ], pmax(S_sat[set, months_m], Hn[set, months_m])), all(Hm[water, ] >= S_sat[water, months_m]),
          all((tab$final_n_changed > 0) == tab$hybrid_changed))
cat("final map = the hybrid of the framed clip and the hulls (max inside the set, the clip outside) in the 278 satellite months, = the hull clip in the 226 hull months; cells changed > 0 exactly in the ", sum(tab$hybrid_changed), " hybrid_changed months  OK\n", sep = "")
# 5. The set raster.
stopifnot(all(is.na(set_v) == land), all(set_v[water] %in% c(0, 1)), sum(set) == expected$set_cells, !any(atl[set]),
          sum(land) == expected$n_land, sum(water) == expected$n_water, all(dv[water] > 0))
cat("template: ", sum(land), " land cells (NA), ", sum(water), " water cells; nearshore set ", rule_name, ": ", sum(set), " cells, ", fmt_n(round(sum(cell_km2[set]))), " km2, none in the Atlantic box  OK\n", sep = "")
# 6. The VIIRS stack, 2022-12, the fit status against RT_fit_matrix, the hull footprints, the image() orientation.
stopifnot(ncol(Vr) == expected$viirs_layers, sum(viirs_n_pos == 0) == expected$viirs_zero,
          tab$viirs_status[tab$yrmo == "202212"] == "missing", tab$use[tab$yrmo == "202212"] == "hybrid_modis")
fm_status <- ifelse(is.na(tab$converged), "none", ifelse(tab$converged == "no model", "failed", "fitted"))
mism <- tab$yrmo[fm_status != tab$fit_status]
if (length(mism)) message("fit status mismatch (layer vs fit_matrix): ", paste(mism, collapse = " "))
fit_counts <- table(factor(tab$fit_status, levels = names(expected$fit)))
stopifnot(length(mism) == 0)
if (!all(as.integer(fit_counts) == expected$fit)) stop("Fit status counts ", paste(names(fit_counts), as.integer(fit_counts), collapse = ", "), " differ from the frozen ", paste(expected$fit, collapse = "/"), call. = FALSE)
stopifnot(all(tab$yrmo[tab$n_pos > 0] %in% names(pol_list)), all(colSums(H[, setdiff(key, names(pol_list)), drop = FALSE], na.rm = TRUE) == 0))
to_z <- function(v) matrix(v, nrow = nc)[, nr:1]
z <- to_z(dv); cells <- seq_len(n5)
stopifnot(identical(z[cbind(raster::colFromCell(depth, cells), nr - raster::rowFromCell(depth, cells) + 1)], dv))
stopifnot(length(hl) == expected$n_headline, all(hl %in% key))
cat("VIIRS stack: ", ncol(Vr), " layers, ", sum(viirs_n_pos == 0), " with no positive cell; fit status from the layers = RT_fit_matrix (",
    paste(names(fit_counts), as.integer(fit_counts), collapse = ", "), "); every month with positives has a footprint; image() orientation  OK\n", sep = "")
cat("samples: ", nrow(pts), " (", n_cells_na, " dropped for NA count); ", sum(!ok), " off-grid; ", sum(ok & !pts$water), " on land cells of the template\n", sep = "")

# Count boxes: positives and the five FWC classes (#6), and the exposure of a map ---------
sbrks <- c(0, 1e3, 1e4, 1e5, 1e6, Inf)
slabs <- c("<= 1,000", "1,000-10,000", "10,000-100,000", "100,000-1,000,000", "> 1,000,000")
spal  <- viridis::viridis(5, direction = -1)
class_names  <- c("n_pos", "n_le1e3", "n_1e3_1e4", "n_1e4_1e5", "n_1e5_1e6", "n_gt1e6")
class_labels <- c("positives", "<= 1,000", "1,000 - 10,000", "10,000 - 100,000", "100,000 - 1,000,000", "> 1,000,000")
class_counts <- function(v) {
  v <- v[!is.na(v) & v > 0]
  k <- cut(v, sbrks, labels = FALSE, include.lowest = TRUE)
  setNames(c(length(v), tabulate(k, nbins = 5)), class_names)
}
info_lines  <- function(cnt) paste(fmt_n(cnt), class_labels)
exposure_of <- function(v) sum(v[water], na.rm = TRUE)            # cells/L summed over the water cells, as Ecospace integrates a map
fmt_expo    <- function(x) fmt_n(signif(x, 3))
map_info    <- function(v) c(sprintf("exposure %s cells/L", fmt_expo(exposure_of(v))), info_lines(class_counts(v)))

# The CSV of the count boxes: <map>_<class> and <map>_exposure ---------------------------
maps <- c("fwc", "unclip", "viirs", "modis", "hull", "final")
cls <- do.call(rbind, lapply(key, function(ym) {
  r <- tab[tab$yrmo == ym, ]
  p <- by_m[[ym]]
  layer <- list(fwc = if (is.null(p)) NULL else p$cells,
                unclip = if (r$fit_status != "none") U[, ym] else NULL,
                viirs = if (ym %in% colnames(Vc)) Vc[, ym] else NULL,
                modis = if (ym %in% colnames(Mc)) Mc[, ym] else NULL,
                hull = H[, ym], final = Fm[, ym])
  one <- function(v) if (is.null(v)) setNames(rep(NA_integer_, 6), class_names) else class_counts(v)
  cnt <- unlist(lapply(maps, function(m) one(layer[[m]])))
  names(cnt) <- paste(rep(maps, each = 6), class_names, sep = "_")
  expo <- vapply(maps[-1], function(m) if (is.null(layer[[m]])) NA_real_ else exposure_of(layer[[m]]), numeric(1))
  names(expo) <- paste0(maps[-1], "_exposure")
  data.frame(yrmo = ym, use = r$use, sat_src = r$sat_src, hybrid_changed = r$hybrid_changed, fit_status = r$fit_status,
             viirs_status = r$viirs_status, as.list(cnt), as.list(expo), final_n_changed = r$final_n_changed, stringsAsFactors = FALSE)
}))
# 7. Class counts: the sample classes sum to the positives and equal n_pos; the final classes sum to the
#    final positives; the final map never has fewer positives than the framed clip; hull months equal the hull clip.
framed_pos  <- ifelse(cls$sat_src == "viirs", cls$viirs_n_pos, ifelse(cls$sat_src == "modis", cls$modis_n_pos, cls$hull_n_pos))
framed_expo <- ifelse(cls$sat_src == "viirs", cls$viirs_exposure, ifelse(cls$sat_src == "modis", cls$modis_exposure, cls$hull_exposure))
is_h <- cls$sat_src == "hull"
stopifnot(nrow(cls) == length(key),
          all(cls$fwc_n_pos[!is.na(cls$fwc_n_pos)] == tab$n_pos[!is.na(cls$fwc_n_pos)]), all(tab$n_samples[is.na(cls$fwc_n_pos)] == 0),
          all(rowSums(cls[, paste0("fwc_", class_names[-1])], na.rm = TRUE) == ifelse(is.na(cls$fwc_n_pos), 0, cls$fwc_n_pos)),
          all(rowSums(cls[, paste0("final_", class_names[-1])]) == cls$final_n_pos),
          !anyNA(framed_pos), all(cls$final_n_pos >= framed_pos),
          all(cls[is_h, paste0("final_", class_names)] == cls[is_h, paste0("hull_", class_names)]))
# 8. Exposures: the final map at or above the framed clip, equal where the hybrid changed nothing; equal to the
#    record table (the frozen run) except in the months the refresh changed; a clip only removes.
d_expo <- cls$final_exposure - framed_expo
stopifnot(!anyNA(framed_expo), all(d_expo >= -1e-6), all(abs(d_expo[!cls$hybrid_changed]) <= 1e-6), all(d_expo[cls$hybrid_changed] > 0),
          all(cls[is_h, "final_exposure"] == cls[is_h, "hull_exposure"]))
j <- match(cls$yrmo, rec$yrmo)
stopifnot(!anyNA(j), setequal(refm$yrmo[refm$ascii_changed], expected$refreshed))
off <- cls$yrmo[abs(cls$final_exposure - rec$exposure_final[j]) > 1]
stopifnot(setequal(off, expected$refreshed) || length(off) == 0, all(off %in% expected$refreshed))
fitted <- cls$fit_status == "fitted"
stopifnot(all(cls$unclip_exposure[fitted] >= cls$hull_exposure[fitted]),
          all(cls$unclip_exposure[fitted & !is.na(cls$viirs_exposure)] >= cls$viirs_exposure[fitted & !is.na(cls$viirs_exposure)]),
          all(cls$unclip_exposure[fitted & !is.na(cls$modis_exposure)] >= cls$modis_exposure[fitted & !is.na(cls$modis_exposure)]))
cat("count boxes: sample classes sum to the positives; final classes sum to the final positives; final positives >= the framed clip in every month; final exposure >= the framed clip (equal in the ",
    sum(!cls$hybrid_changed), " months the hybrid did not change), = the record table within 1 cells/L except ", paste(off, collapse = ", "),
    " (the months the refresh changed); unclipped exposure >= every clip  OK\n", sep = "")
file_cls <- file.path(dir_tab, "clip_class_counts_hybrid_issue18.csv")
write.csv(cls, file_cls, row.names = FALSE)
message("Class counts written: ", file_cls, " (", nrow(cls), " rows)")
cat("All checks passed.\n\n")

# Drawing helpers (#6, the palette and breaks of the pipeline PDFs) ------------------------
colv   <- c("white","purple","blue","darkblue","cyan","green","darkgreen","yellow","orange","red","darkred")
funpal <- colorRampPalette(colv, bias = 2)
brks   <- c(0, 1e4 - 1, seq(1e4, 4e6, 10000), Inf)
color  <- c(funpal(length(brks) - 2), "darkred")
brks_img <- brks; brks_img[length(brks_img)] <- 1e12   # base image() needs finite breaks
xs <- raster::xFromCol(depth, 1:nc); ys <- rev(raster::yFromRow(depth, 1:nr))
xlim <- c(-87.5, -81); ylim <- c(25, 30.5)
# Land is the template's land cells (NA in the depth grid, NODATA in every ASCII file), drawn
# as a bitmap in every panel: what the maps carry and Ecospace sees, not a coastline polygon.
land_z <- to_z(ifelse(land, 1, NA))
tol_m <- function(m) if (sf::sf_use_s2()) m else m / 1e5   # st_simplify tolerance: metres with s2, degrees without
simplify_outline <- function(s) if (is.null(s)) NULL else suppressWarnings(sf::st_simplify(s, dTolerance = tol_m(1000)))
cells_to_outline <- function(r2) {   # the dissolved outline of the non-NA cells of a raster
  p <- raster::rasterToPolygons(r2, dissolve = TRUE)
  p <- sf::st_sf(geometry = sf::st_union(sf::st_as_sf(p)))
  sf::st_crs(p) <- 4326
  p
}
# Footprint outlines of each clip source, built lazily and cached.
.viirs_pol <- list()
viirs_outline <- function(ym) {
  if (!(ym %in% colnames(Vr)) || viirs_n_pos[[ym]] == 0) return(NULL)
  if (!is.null(.viirs_pol[[ym]])) return(.viirs_pol[[ym]])
  r2 <- Vraw[[which(names(Vraw) == paste0("X", ym))]]
  r2[r2 == 0] <- NA
  p <- cells_to_outline(r2)
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
outline_of <- function(ym, src) switch(src, viirs = viirs_outline(ym), modis = modis_outline(ym), hull = hull_outline(ym))
set_r2 <- set_r; set_r2[set_r2 != 1] <- NA
set_outline <- cells_to_outline(set_r2)   # the nearshore set, once

# A small cells/L colour bar in the right margin of the current panel.
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
draw_panel <- function(v, main, pts = NULL, all_pts = FALSE, outline = NULL, ocol = "gray50", olwd = 0.5,
                       outline2 = NULL, ocol2 = "gray20", olwd2 = 0.3, used = FALSE, placeholder = NULL,
                       cex_main = 0.75, info = NULL, cex_info = 0.55, cbar = FALSE, cex_pts = 0.5) {
  plot(NA, xlim = xlim, ylim = ylim, xlab = "", ylab = "", asp = 1 / cos(27.5 * pi / 180),
       main = main, cex.main = cex_main, xaxs = "i", yaxs = "i", axes = FALSE)
  rect(xlim[1], ylim[1], xlim[2], ylim[2], col = if (is.null(placeholder)) "white" else "darkgray", border = NA)
  image(xs, ys, land_z, col = "wheat", add = TRUE, useRaster = TRUE)   # the land cells; the maps are NA there, so the order does not matter
  if (!is.null(v) && is.null(placeholder)) {
    # useRaster = TRUE embeds the 66 x 78 grid as a bitmap (no interpolation), as the pipeline PDFs do.
    image(xs, ys, to_z(v), breaks = brks_img, col = color, add = TRUE, useRaster = TRUE)
  } else if (!is.null(placeholder)) {
    text(mean(xlim), mean(ylim), placeholder, cex = 0.9 * cex_main / 0.85)
  }
  if (!is.null(outline))  plot(sf::st_geometry(outline),  add = TRUE, border = ocol,  col = NA, lwd = olwd)
  if (!is.null(outline2)) plot(sf::st_geometry(outline2), add = TRUE, border = ocol2, col = NA, lwd = olwd2)
  if (!is.null(pts) && nrow(pts) > 0 && all_pts) {
    z0 <- pts[pts$cells == 0, ]
    points(z0$lon, z0$lat, pch = ".", cex = 1.8, col = "gray45")
    pp <- pts[pts$cells > 0, ]
    bins <- cut(pp$cells, sbrks, labels = FALSE, include.lowest = TRUE)
    points(pp$lon, pp$lat, pch = 21, bg = spal[bins], col = "black", cex = cex_pts, lwd = 0.5)
  }
  if (!is.null(info)) legend("left", legend = info, bty = "o", bg = "white", box.col = "gray60",
                             cex = cex_info, inset = 0.01, x.intersp = 0.3, y.intersp = 0.9)
  if (cbar) colorbar_legend()
  box(col = if (used) "red" else "black", lwd = if (used) 3 else 1)
}
sample_legend <- function(cex = 0.48) legend("bottomleft", legend = slabs, pt.bg = spal, pch = 21, cex = cex,
                                             title = "samples, cells/L", bg = "white", box.col = "gray60")
final_title <- c(hybrid = "Final: VIIRS + hulls nearshore", hybrid_modis = "Final: MODIS + hulls nearshore", pred = "Final: hulls")

# One row: A FWC counts | B unclipped | C VIIRS | D MODIS | E hulls | F the delivered map ------
draw_row <- function(ym) {
  r <- tab[tab$yrmo == ym, ]
  p <- by_m[[ym]]
  lab <- paste0(substr(ym, 1, 4), "-", substr(ym, 5, 6))
  # A: raw FWC counts
  if (is.null(p)) {
    draw_panel(NULL, paste("FWC counts", lab), placeholder = "no samples")
  } else {
    draw_panel(NULL, paste("FWC counts", lab), pts = p, all_pts = TRUE, info = info_lines(class_counts(p$cells)))
    sample_legend()
  }
  # B: unclipped
  if (r$fit_status == "fitted") {
    draw_panel(U[, ym], "sdmTMB unclipped", cbar = TRUE, info = map_info(U[, ym]))
  } else {
    draw_panel(NULL, "sdmTMB unclipped", placeholder = if (r$fit_status == "failed") "fit failed" else sprintf("no fit (%d positives)", r$n_pos))
  }
  # C: VIIRS
  if (ym %in% colnames(Vc)) {
    draw_panel(Vc[, ym], "VIIRS clipped", cbar = TRUE, used = r$sat_src == "viirs", outline = viirs_outline(ym), info = map_info(Vc[, ym]))
  } else {
    draw_panel(NULL, "VIIRS clipped", placeholder = if (r$viirs_status == "missing") "VIIRS tif missing" else "no VIIRS layer")
  }
  # D: MODIS
  if (ym %in% colnames(Mc)) {
    draw_panel(Mc[, ym], "MODIS clipped", cbar = TRUE, used = r$sat_src == "modis", outline = modis_outline(ym), info = map_info(Mc[, ym]))
  } else {
    draw_panel(NULL, "MODIS clipped", placeholder = "no MODIS polygon")
  }
  # E: hulls (a layer exists for every month; all zero when there is no footprint or no fit)
  draw_panel(H[, ym], "Hulls", cbar = TRUE, used = r$sat_src == "hull", outline = hull_outline(ym), info = map_info(H[, ym]))
  # F: the delivered map, with the outline of the framed panel and the nearshore set
  extra <- if (r$sat_src == "hull") NULL else sprintf("%s cells changed vs %s clip", fmt_n(r$final_n_changed), toupper(r$sat_src))
  draw_panel(Fm[, ym], final_title[[r$use]], cbar = TRUE, outline = outline_of(ym, r$sat_src), outline2 = set_outline,
             info = c(map_info(Fm[, ym]), extra))
}
page_chunks <- split(key, ceiling(seq_along(key) / rows_per_page))
page_title <- function(ch) if (length(ch) == 12 && substr(ch[1], 5, 6) == "01") substr(ch[1], 1, 4) else
  paste(paste0(substr(ch[1], 1, 4), "-", substr(ch[1], 5, 6)), "to", paste0(substr(ch[length(ch)], 1, 4), "-", substr(ch[length(ch)], 5, 6)))
header1 <- "A FWC counts  |  B sdmTMB unclipped  |  C VIIRS clipped  |  D MODIS clipped  |  E hulls  |  F final: the hybrid nearshore map (rule mask5adj)"
header2 <- sprintf("Red frame: the clip the final map is built on. F carries the outline of the framed panel (grey) and of the nearshore set (black). Land (wheat) is the %s land cells of the 5-arcmin template, as the maps carry them.", fmt_n(sum(land)))
header3 <- "Each map panel prints its total exposure (cells/L summed over the water cells), the positive cells and the five FWC classes; panel A counts the samples."
draw_month_page <- function(ch) {
  par(mfrow = c(rows_per_page, 6), mar = c(0.4, 0.5, 1.5, 2.1), oma = c(0.3, 0, 3.4, 0))
  for (ym in ch) draw_row(ym)
  mtext(sprintf("%s   |   %s", page_title(ch), header1), outer = TRUE, cex = 0.95, font = 2, line = 2.0)
  mtext(header2, outer = TRUE, cex = 0.62, line = 0.95)
  mtext(header3, outer = TRUE, cex = 0.62, line = 0.15)
}
page_w <- 11 * 6 / 5; page_h <- 2.35 * rows_per_page + 1.3   # the #6 panel size, one more column, a three-line header

# Write a PDF to a temporary file and rename it into place (a copy open in a viewer does not kill the run).
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
png_open <- function(file_png, ...) { file_tmp <- sub("[.]png$", "_tmp.png", file_png); png(file_tmp, ...); file_tmp }
png_done <- function(file_png) { invisible(dev.off()); file_tmp <- sub("[.]png$", "_tmp.png", file_png)
  if (file.exists(file_png) && !file.remove(file_png)) { warning("Could not replace ", file_png, " (open in a viewer?); the new file is ", file_tmp, call. = FALSE); return(invisible(FALSE)) }
  file.rename(file_tmp, file_png); invisible(TRUE) }

# The monthly PDF -----------------------------------------------------------------------
chunks <- if (quick) page_chunks[vapply(page_chunks, function(ch) any(ch %in% hl), logical(1))] else page_chunks
file_pdf <- if (quick) file.path(dir_docs, "hoard", "clip_months_hybrid_issue18_quick.pdf") else file.path(dir_docs, "clip_months_hybrid_issue18.pdf")   # quick mode never replaces the tracked PDF
if (quick) dir.create(dirname(file_pdf), showWarnings = FALSE)
t0 <- Sys.time()
if (write_pdf(file_pdf, width = page_w, height = page_h, function() for (ch in chunks) draw_month_page(ch)))
  message("Monthly PDF written: ", file_pdf, " (", length(chunks), " pages, ", round(file.size(file_pdf) / 1e6, 1), " MB, ",
          round(as.numeric(difftime(Sys.time(), t0, units = "secs"))), " s)")

# Example rows for the issue (tracked figure): the four months of the #6 example.
example_rows <- c("201201", "201202", "201203", "201204")
file_png <- file.path(dir_fig, "fig3_monthly_rows_example_issue18.png")
invisible(png_open(file_png, width = page_w, height = 2.35 * length(example_rows) + 1.1, units = "in", res = 150))
par(mfrow = c(length(example_rows), 6), mar = c(0.4, 0.5, 1.5, 2.1), oma = c(0.3, 0, 3.0, 0))
for (ym in example_rows) draw_row(ym)
mtext(paste("Example rows, 2012-01 to 2012-04   |  ", header1), outer = TRUE, cex = 0.8, font = 2, line = 1.9)
mtext(header2, outer = TRUE, cex = 0.62, line = 0.95)
mtext(header3, outer = TRUE, cex = 0.62, line = 0.15)
png_done(file_png)
message("Example rows written: ", file_png)

# Page previews as PNG (for a look without a PDF viewer), when asked.
if (nzchar(png_dir)) {
  dir.create(png_dir, recursive = TRUE, showWarnings = FALSE)
  for (y in png_years) {
    ch <- key[substr(key, 1, 4) == y]
    if (length(ch) == 0) next
    png(file.path(png_dir, paste0("clip_months_hybrid_", y, ".png")), width = page_w, height = page_h, units = "in", res = 90)
    draw_month_page(ch); dev.off()
  }
  message("Page previews in ", png_dir, ": ", paste(png_years, collapse = ", "))
}

# Summary ---------------------------------------------------------------------------
cat("\n=== summary ===\n")
cat(sprintf("Months: %d; by final map: %d VIIRS hybrid, %d MODIS hybrid, %d hulls; the hybrid changed %d months (%d VIIRS, %d MODIS)\n",
            nrow(tab), use_counts[["hybrid"]], use_counts[["hybrid_modis"]], use_counts[["pred"]], sum(tab$hybrid_changed),
            sum(tab$hybrid_changed & tab$use == "hybrid"), sum(tab$hybrid_changed & tab$use == "hybrid_modis")))
cat(sprintf("Fit status: %s\n", paste(names(fit_counts), as.integer(fit_counts), collapse = ", ")))
tot <- function(m) sum(cls[[paste0(m, "_exposure")]], na.rm = TRUE)
cat(sprintf("Exposure summed over the 504 months (cells/L): unclipped %s (fitted months), VIIRS clip %s (%d months), MODIS clip %s (%d months), hulls %s, final %s; the framed clips %s\n",
            fmt_expo(tot("unclip")), fmt_expo(tot("viirs")), sum(!is.na(cls$viirs_exposure)), fmt_expo(tot("modis")), sum(!is.na(cls$modis_exposure)),
            fmt_expo(tot("hull")), fmt_expo(tot("final")), fmt_expo(sum(framed_expo))))
cat(sprintf("Final vs the framed clips: exposure x %.3f over all months, x %.3f over the 278 satellite months; cells changed in total %s\n",
            tot("final") / sum(framed_expo), sum(cls$final_exposure[!is_h]) / sum(framed_expo[!is_h]), fmt_n(sum(cls$final_n_changed))))
cat(sprintf("Headline months of #6 (%d): final positives %s (VIIRS clip 0 in all), final exposure %s\n", length(hl),
            fmt_n(sum(cls$final_n_pos[cls$yrmo %in% hl])), fmt_expo(sum(cls$final_exposure[cls$yrmo %in% hl]))))
cat("\nDone.\n")
