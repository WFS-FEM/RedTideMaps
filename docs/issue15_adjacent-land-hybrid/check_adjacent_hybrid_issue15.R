#' QA for issue #15: the land-adjacent nearshore rule on the Ecospace basemap.
#'
#' Issue #15 asks whether a nearshore set defined from the Ecospace basemap itself
#' (a water cell that shares an edge or a corner with a land cell), filled with
#' the unclipped sdmTMB projection in satellite months, could replace the mask5
#' rule of #8 / #11 / #10 (the VIIRS no-data mask or within 5 km of the
#' coastline, filled with the hull-clipped projection). Two questions: does the
#' set cover the cells the VIIRS mask hides, and what does the rule do to the
#' metrics (in-situ samples included, total exposure, cells added at or above
#' 10k / 100k / 1M cells/L).
#'
#' One stage, `examine` (env RT_QA_STAGE), no pipeline run: everything is
#' prototyped from the stacks the last run left on disk, the VIIRS stack, the
#' local copies of the #11 and #10 runs, and the tracked tables. Refits nothing,
#' uses no RNG; CSVs and PNGs are byte-identical from run to run (the PDF
#' carries the two date lines every R pdf() device writes).
#'
#' Five variants over the 278 satellite months (155 VIIRS, 123 MODIS); the 226
#' hull months are identical in every variant:
#'   v6oct      the delivered maps (satellite-clipped; the 6 Oct 2026 run)
#'   mask5      the mask5 set, max(satellite-clipped, hull-clipped) inside it, both
#'              sensors (run B of #10)
#'   adj8_sdm   the land-adjacent set (edge or corner, Gulf domain), the raw sdmTMB
#'              projection inside it: the issue's rule
#'   adj8m_sdm  the land-adjacent set or the static VIIRS no-data mask, raw sdmTMB
#'              inside it: the adaptation candidate (Holden, 22 Oct 2026)
#'   adj8_hull  the land-adjacent set with the mask5 fill: separates the set from
#'              the fill
#'
#' Outputs -> tables/*_issue15.csv, figures/fig1..fig4, comments/examine_summary.md.
#' Run from the repo root:
#'   RT_QA_STAGE=examine Rscript docs/issue15_adjacent-land-hybrid/check_adjacent_hybrid_issue15.R
#'   RT_QA_PNG_DIR=<folder> adds PNG previews of the fig 3 pages.
#'   RT_BASEMAP_DEPTH=<path> names the EcospaceBasemap 5-min depth grid (default:
#'   ../EcospaceBasemap/output/5min/depth/depth_5min.asc beside this repository).
#' Needs out/5min/sdm/, out/5min/clipped/ (with nearshore_mask_mask5.grd from a run
#' with a nearshore rule on) and VIIRS/ from the last run; the 6 Oct 2026 combined
#' stack in docs/issue11_nearshore-hybrid-pipeline/hoard/before/combined/ and the
#' run-B combined stack in docs/issue10_modis-nearshore-hybrid/hoard/after/combined/.

# Repo root: the working directory if it holds the .Rproj, else two levels above this script.
.root <- local({
  if (file.exists("RedTideMaps.Rproj")) return(normalizePath(getwd(), winslash = "/"))
  f <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE))
  if (length(f) == 1) {
    d <- normalizePath(file.path(dirname(f), "..", ".."), winslash = "/", mustWork = FALSE)
    if (file.exists(file.path(d, "RedTideMaps.Rproj"))) return(d)
  }
  stop("Run from the repo root: Rscript docs/issue15_adjacent-land-hybrid/check_adjacent_hybrid_issue15.R", call. = FALSE)
})
source(file.path(.root, "scripts", "_setup.R"))   # sf, raster, viridis, ...
stage <- match.arg(Sys.getenv("RT_QA_STAGE", "examine"), c("examine"))
message("Issue #15 check, stage: ", stage)

# Parameters ---------------------------------------------------------------------
thr <- c(ge10k = 1e4, ge100k = 1e5, ge1M = 1e6)   # cell thresholds (inclusive), as #11 and #10
thr_bloom  <- thr[["ge10k"]]
class_brks <- c(-Inf, 0, 1e3, 1e4, 1e5, 1e6, Inf)   # FWC classes, right-closed
class_lab  <- c("zero", "le1k", "1k_10k", "10k_100k", "100k_1M", "gt1M")
coast_bands <- c(0, 2, 5, 10, Inf); band_lv <- c("0-2 km", "2-5 km", "5-10 km", "> 10 km")
min_samples_group <- 5L   # a month enters the sample-share groups with at least this many water samples >= 10k cells/L
mask_share    <- 0.9      # fn.nearshore_mask(): a 0.1-degree VIIRS cell NA in this share of the layers is the static mask
fig3_top      <- 12L      # fig 3: the headline months, then the months where adj8_sdm and mask5 differ most in exposure
fig3_per_page <- 7L
coast_tol_m   <- 500      # coastline simplified for drawing
coast_step_m  <- 200      # coastline densified for distances (as fn.nearshore_mask())
# Frozen numbers, asserted below: the grid and the sets (read-only check of 22 Oct 2026,
# plan section 1), the #6 month groups, and the headline metrics of the first run.
expected <- list(n_cells = 5148L, n_land = 1310L, n_water = 3838L, n_atl_water = 56L,
                 n_adj8_all = 202L, n_adj8 = 177L, km2_adj8 = 13311, n_adj4 = 128L, n_ring2 = 338L,
                 n_mask = 84L, n_set5 = 136L, km2_set5 = 10227, n_adj8_mask = 183L, n_near5 = 132L, n_union = 189L, km2_union = 14205,
                 adj8_covers_mask = 78L, adj8_covers_set5 = 124L, adj8_not_in_set5 = 53L,
                 n_sat = 278L, n_viirs = 155L, n_modis = 123L, n_hull = 226L,
                 n_zeroed = 58L, n_headline = 16L, n_sel3 = 60L,
                 n_changed_mask5_viirs = 121L, n_changed_mask5_modis = 87L,
                 # the first run (22 Oct 2026), over the 278 satellite months, by variant
                 n_surface = 217L, samples_ge10k = 13280L, samples_gt1M = 1610L, n_excluded = 4889L,
                 exposure = c(v6oct = 6494237122, mask5 = 6967296294, adj8_sdm = 7654733791, adj8m_sdm = 7678186657, adj8_hull = 7027864825, union_hull = 7041082852),
                 in_ge10k = c(v6oct = 8391L, mask5 = 12351L, adj8_sdm = 12408L, adj8m_sdm = 12453L, adj8_hull = 12408L, union_hull = 12515L),
                 in_gt1M  = c(v6oct = 1137L, mask5 = 1563L, adj8_sdm = 1571L, adj8m_sdm = 1572L, adj8_hull = 1571L, union_hull = 1573L),
                 months_changed   = c(v6oct = 0L, mask5 = 208L, adj8_sdm = 215L, adj8m_sdm = 215L, adj8_hull = 210L, union_hull = 210L),
                 cellmonths_ge10k = c(v6oct = 27970L, mask5 = 29962L, adj8_sdm = 40041L, adj8m_sdm = 40370L, adj8_hull = 30355L, union_hull = 30474L))

# Paths --------------------------------------------------------------------------
dir_out      <- file.path(.root, "out", "5min")
dir_sdm      <- file.path(dir_out, "sdm")
dir_clipped  <- file.path(dir_out, "clipped")
dir_docs     <- file.path(.root, "docs", "issue15_adjacent-land-hybrid")
dir_tab      <- file.path(dir_docs, "tables")
dir_fig      <- file.path(dir_docs, "figures")
dir_cmt      <- file.path(dir_docs, "comments")
dir_hoard11  <- file.path(.root, "docs", "issue11_nearshore-hybrid-pipeline", "hoard")
dir_hoard10  <- file.path(.root, "docs", "issue10_modis-nearshore-hybrid", "hoard")
dir_tab11    <- file.path(.root, "docs", "issue11_nearshore-hybrid-pipeline", "tables")
dir_tab10    <- file.path(.root, "docs", "issue10_modis-nearshore-hybrid", "tables")
for (d in c(dir_tab, dir_fig, dir_cmt)) dir.create(d, recursive = TRUE, showWarnings = FALSE)
one_file <- function(dir, pattern, what) {
  f <- list.files(dir, pattern = pattern, full.names = TRUE)
  if (length(f) != 1) stop("Expected one ", what, " in ", dir, " (found ", length(f), ").", call. = FALSE)
  f
}
grd <- function(f) sub("[.]grd$", "", f)
file_depth   <- one_file(file.path(.root, "template rasters"), "^depth 5min .*[.]asc$", "depth template")
file_basemap <- Sys.getenv("RT_BASEMAP_DEPTH", file.path(dirname(.root), "EcospaceBasemap", "output", "5min", "depth", "depth_5min.asc"))
file_viirs   <- grd(one_file(file.path(.root, "VIIRS"), "^VIIRS_.*[.]grd$", "VIIRS stack"))
file_tab6    <- file.path(.root, "docs", "issue6_VIIRS-zeros", "tables", "clip_comparison_issue6.csv")
file_coast   <- file.path(.root, "data", "coastline", "ne_10m_coastline_wfs.gpkg")
file_mask5   <- file.path(dir_clipped, "nearshore_mask_mask5.grd")
file_cs      <- file.path(dir_clipped, "clipping_source.csv")
file_set11   <- file.path(dir_tab11, "nearshore_set_issue11.csv")
file_expo11  <- file.path(dir_tab11, "exposure_months_issue11.csv")
file_rec10   <- file.path(dir_tab10, "record_months_issue10.csv")
file_raw     <- grd(one_file(dir_sdm, "^sdmTMB_log_stack_[0-9]{6}-[0-9]{6}[.]grd$", "raw sdmTMB stack"))
for (f in c(file_tab6, file_coast, file_cs, file_set11, file_expo11, file_rec10)) if (!file.exists(f)) stop("Missing ", f, call. = FALSE)
if (!file.exists(file_basemap))
  stop("Missing the EcospaceBasemap depth grid: ", file_basemap,
       "\nClone https://github.com/WFS-FEM/EcospaceBasemap beside this repository or set RT_BASEMAP_DEPTH.", call. = FALSE)
if (!file.exists(file_mask5))
  stop("Missing ", file_mask5, ": run the pipeline once with cfg$viirs_nearshore = \"mask5\" so the mask5 set is on disk.", call. = FALSE)

# Common objects -----------------------------------------------------------------
depth    <- raster::raster(file_depth)
dv       <- raster::values(depth)
land     <- is.na(dv)
water    <- !land
cell_km2 <- raster::values(raster::area(depth))
nr <- nrow(depth); nc <- ncol(depth); n5 <- raster::ncell(depth)
xy5 <- raster::xyFromCell(depth, seq_len(n5))
atl    <- xy5[, 1] > -82 & xy5[, 2] > 28.5        # the Atlantic-side box: always excluded (Holden, 22 Oct 2026)
domain <- water & !atl
stopifnot(n5 == expected$n_cells, sum(land) == expected$n_land, sum(water) == expected$n_water, sum(water & atl) == expected$n_atl_water)
read_mat <- function(f) {
  b <- raster::brick(f)
  stopifnot(raster::compareRaster(depth, b))
  m <- raster::values(b); colnames(m) <- sub("^X", "", names(b)); m
}
norm_map <- function(M) { M[is.na(M)] <- 0; M[land, ] <- NA; M }   # as make_redtide_ascii() writes every layer
same <- function(a, b) all((a == b) | (is.na(a) & is.na(b)))
fmt_n <- function(x) format(x, big.mark = ",", trim = TRUE, scientific = FALSE)
tab6 <- read.csv(file_tab6, colClasses = c(yrmo = "character"), stringsAsFactors = FALSE)
zeroed   <- tab6$yrmo[tab6$flag_zeroed_fit %in% TRUE]
headline <- tab6$yrmo[tab6$zeroed_material %in% TRUE]
sel3     <- tab6$yrmo[tab6$use == "viirs" & tab6$viirs_status == "positive" & tab6$fit_status == "fitted" & tab6$n_pos_1e4_water >= 5]
stopifnot(length(zeroed) == expected$n_zeroed, length(headline) == expected$n_headline, length(sel3) == expected$n_sel3)

# Samples on the template, as #8, #11 and #10 counted them: water cells only, off-grid
# samples dropped, FWC classes right-closed; ge10k = at or above 10,000 cells/L, gt1M =
# above 1,000,000 cells/L (the FWC high class).
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
  pts$ge10k <- pts$cells >= thr_bloom
  pts$gt1M  <- pts$cells > 1e6
  pts
}
# Per month: water samples >= 10k and > 1M cells/L, and how many sit in a non-zero cell of M.
samples_of <- function(M, pw, months) {
  j <- match(pw$yrmo, months); inside <- M[cbind(pw$cell5, j)] > 0
  stopifnot(!any(is.na(inside)))
  ymf <- factor(pw$yrmo, levels = months)
  cnt <- function(sel) as.vector(table(ymf[sel])); hit <- function(sel) as.vector(table(ymf[sel & inside]))
  data.frame(yrmo = months, samples_ge10k = cnt(pw$ge10k), in_ge10k = hit(pw$ge10k),
             samples_gt1M = cnt(pw$gt1M), in_gt1M = hit(pw$gt1M), stringsAsFactors = FALSE)
}
# Exposure per map as Ecospace reads it (#11 stage exposure, #10 stage compare): the sum of
# cells/L over the water cells, the cells (and km2) at or above each threshold, the maximum.
expo_of <- function(M) {
  out <- data.frame(exposure = colSums(M[water, , drop = FALSE]))
  for (k in names(thr)) {
    hit <- !is.na(M) & M >= thr[[k]]
    out[[paste0("n_", k)]] <- colSums(hit); out[[paste0("km2_", k)]] <- colSums(hit * cell_km2)
  }
  out$max_cells <- apply(M, 2, max, na.rm = TRUE)
  out
}
round_cols <- function(df) {
  for (nm in grep("km2|exposure|median_value", names(df), value = TRUE))
    df[[nm]] <- round(df[[nm]], if (grepl("ratio", nm)) 3 else 0)
  df
}
share <- function(num, den) ifelse(den > 0, round(num / den, 3), NA_real_)
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
# (UTM 17N), as fn.nearshore_mask() and the #8 diagnostic compute it (distances only here).
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

# Drawing helpers (the #8 / #11 / #10 panel style) ----------------------------------
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
class_lines <- function(cnt) paste(fmt_n(cnt), c("positives", "<= 1k", "1k - 10k", "10k - 100k", "100k - 1M", "> 1M cells/L"))
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
# The same for a PNG: open the device on a temporary file; png_done() closes it and moves
# it into place, and only warns if the target is held open by a viewer (the run goes on).
png_open <- function(file_png, width, height, res = 150) {
  file_tmp <- sub("[.]png$", "_tmp.png", file_png)
  png(file_tmp, width = width, height = height, units = "in", res = res)
  file_png
}
png_done <- function(file_png) {
  invisible(dev.off())
  file_tmp <- sub("[.]png$", "_tmp.png", file_png)
  if (file.exists(file_png) && !file.remove(file_png)) {
    warning("Could not replace ", file_png, " (open in a viewer?); the new file is ", file_tmp, call. = FALSE)
    return(invisible(FALSE))
  }
  file.rename(file_tmp, file_png); invisible(TRUE)
}

# Stage examine --------------------------------------------------------------------
if (stage == "examine") {

  # 1. The basemap is the template: same grid, land = NODATA cell for cell, values agree.
  bm <- raster::raster(file_basemap)
  stopifnot(raster::compareRaster(depth, bm, crs = FALSE, values = FALSE))
  bv <- raster::values(bm)
  stopifnot(identical(is.na(bv), land), max(abs(bv[water] - dv[water])) < 0.01)
  cat(sprintf("Basemap %s: %d x %d, %d NODATA cells = the template land cells; depth values agree within %.4f m\n",
              file_basemap, nr, nc, sum(is.na(bv)), max(abs(bv[water] - dv[water]))))

  # 2. The sets. Adjacency on the template (raster::adjacent from the water side, keeping
  # the water cell of every pair whose neighbour is land: the mirror of fn.build_coastal()
  # in EcospaceBasemap/R/port_functions.R, which runs terra::adjacent from the land side).
  adj_set <- function(dirs) {
    a <- raster::adjacent(depth, cells = which(water), directions = dirs, pairs = TRUE, include = FALSE)
    s <- rep(FALSE, n5); s[unique(a[land[a[, 2]], 1])] <- TRUE; s
  }
  ring_dirs <- matrix(1, 5, 5); ring_dirs[3, 3] <- 0
  adj8_all <- adj_set(8); adj4_all <- adj_set(4); ring2_all <- adj_set(ring_dirs)
  stopifnot(all(water[adj8_all]), all(adj8_all[adj4_all]), all(ring2_all[adj8_all]))
  adj8 <- adj8_all & domain; adj4 <- adj4_all & domain; ring2 <- ring2_all & domain
  # The static VIIRS no-data mask on the template, as fn.nearshore_mask() reads it from
  # the VIIRS stack (a 0.1-degree cell NA in at least mask_share of the layers).
  viirs <- raster::brick(file_viirs)
  mask01 <- rowSums(is.na(raster::values(viirs))) >= mask_share * raster::nlayers(viirs)
  cell01 <- raster::cellFromXY(viirs, xy5); stopifnot(!anyNA(cell01))
  in_mask <- mask01[cell01] & domain
  rm(viirs)
  # The mask5 set of the pipeline (the raster of the last run with a nearshore rule on).
  mask5_r <- raster::raster(file_mask5); stopifnot(raster::compareRaster(depth, mask5_r))
  mv <- raster::values(mask5_r); set5 <- mv %in% 1
  set11 <- read.csv(file_set11, stringsAsFactors = FALSE)
  stopifnot(all(is.na(mv) == land), sum(set5) == expected$n_set5, setequal(which(set5), set11$cell), round(sum(cell_km2[set5])) == expected$km2_set5,
            all(domain[set5]), all(set5[in_mask]))
  adj8_mask <- adj8 | in_mask
  # The within-5-km part of mask5 (cell centres, the coastline densified to 200 m, as
  # fn.nearshore_mask()), and the recomposition mask5 = mask OR within 5 km. The union of
  # mask5 and the land-adjacent set (Holden, 22 Oct 2026) covers the mask, the 5 km band
  # and the adjacent cells by construction.
  row5 <- raster::rowFromCell(depth, seq_len(n5)); col5 <- raster::colFromCell(depth, seq_len(n5))
  dist_w <- rep(NA_real_, n5); dist_w[water] <- dist_coast_km(xy5[water, 1], xy5[water, 2])
  near5 <- !is.na(dist_w) & dist_w <= 5 & domain
  stopifnot(identical(set5, domain & (in_mask | near5)))
  union_set <- set5 | adj8
  sets     <- list(adj4 = adj4, adj8 = adj8, ring2 = ring2, adj8_mask = adj8_mask, mask5 = set5, union = union_set)
  sets_all <- list(adj4 = adj4_all, adj8 = adj8_all, ring2 = ring2_all, adj8_mask = adj8_all | in_mask, mask5 = set5, union = set5 | adj8_all)
  stopifnot(sum(adj8_all) == expected$n_adj8_all, sum(adj8) == expected$n_adj8, round(sum(cell_km2[adj8])) == expected$km2_adj8,
            sum(adj4) == expected$n_adj4, sum(ring2) == expected$n_ring2, sum(in_mask) == expected$n_mask, sum(near5) == expected$n_near5,
            sum(adj8_mask) == expected$n_adj8_mask, sum(adj8 & in_mask) == expected$adj8_covers_mask,
            sum(adj8 & set5) == expected$adj8_covers_set5, sum(adj8 & !set5) == expected$adj8_not_in_set5,
            sum(adj8_mask & in_mask) == expected$n_mask, !any(atl[adj8_mask]), !any(atl[set5]),
            sum(union_set) == expected$n_union, round(sum(cell_km2[union_set])) == expected$km2_union, !any(atl[union_set]),
            all(union_set[in_mask]), all(union_set[near5]), all(union_set[adj8]), sum(union_set & !set5) == expected$adj8_not_in_set5)
  cov <- data.frame(set = names(sets), cells = sapply(sets, sum), km2 = sapply(sets, function(s) round(sum(cell_km2[s]))),
                    viirs_mask_cells_covered = sapply(sets, function(s) sum(s & in_mask)), viirs_mask_cells = sum(in_mask),
                    within5km_cells_covered = sapply(sets, function(s) sum(s & near5)), within5km_cells = sum(near5),
                    adjacent_cells_covered = sapply(sets, function(s) sum(s & adj8)), adjacent_cells = sum(adj8),
                    mask5_cells_covered = sapply(sets, function(s) sum(s & set5)), mask5_cells = sum(set5),
                    cells_not_in_mask5 = sapply(sets, function(s) sum(s & !set5)), mask5_cells_not_in_set = sapply(sets, function(s) sum(set5 & !s)),
                    atlantic_cells_excluded = sapply(sets_all, function(s) sum(s & atl)),
                    stringsAsFactors = FALSE)
  rownames(cov) <- NULL
  write.csv(cov, file.path(dir_tab, "set_coverage_issue15.csv"), row.names = FALSE)
  missed <- do.call(rbind, lapply(c("adj4", "adj8", "ring2", "adj8_mask"), function(k) {
    m <- which(in_mask & !sets[[k]])
    if (length(m) == 0) return(NULL)
    data.frame(set = k, cell = m, row = row5[m], col = col5[m], lon = round(xy5[m, 1], 4), lat = round(xy5[m, 2], 4), depth_m = round(dv[m], 1),
               dist_coast_km = round(dist_w[m], 2), in_mask5 = set5[m], top_row = row5[m] == 1, stringsAsFactors = FALSE)
  }))
  write.csv(missed, file.path(dir_tab, "set_missed_mask_cells_issue15.csv"), row.names = FALSE)
  cat(sprintf("Sets (Gulf domain): adj8 %d cells (%s km2; %d before excluding the %d Atlantic cells), adj4 %d, ring2 %d, VIIRS static mask %d, mask5 %d, adj8 or mask %d\n",
              sum(adj8), fmt_n(round(sum(cell_km2[adj8]))), sum(adj8_all), sum(adj8_all & atl), sum(adj4), sum(ring2), sum(in_mask), sum(set5), sum(adj8_mask)))
  cat(sprintf("Coverage: adj8 covers %d of %d VIIRS-mask cells (missed: %s) and %d of %d mask5 cells; %d adj8 cells are not in mask5; ring2 covers %d of %d mask cells\n",
              sum(adj8 & in_mask), sum(in_mask), paste(which(in_mask & !adj8), collapse = ", "), sum(adj8 & set5), sum(set5), sum(adj8 & !set5), sum(ring2 & in_mask), sum(in_mask)))

  # 3. The satellite months and the layers. S = the satellite-clipped layers of the last run
  # (= the delivered maps, checked against the 6 Oct 2026 combined stack), H = hull-clipped,
  # R = the raw sdmTMB projection (NA on water in months without a fit).
  cs <- read.csv(file_cs, stringsAsFactors = FALSE); cs$yrmo <- sub("^X", "", cs$yrmo)
  use_counts <- table(factor(cs$use, levels = c("viirs", "modis", "pred")))
  stopifnot(nrow(cs) == expected$n_sat + expected$n_hull, as.integer(use_counts) == c(expected$n_viirs, expected$n_modis, expected$n_hull),
            !any(cs$hybrid), !any(cs$hybrid_modis))
  all_yrmo <- sort(cs$yrmo); use_all <- cs$use[match(all_yrmo, cs$yrmo)]
  months_v <- sort(cs$yrmo[cs$use == "viirs"]); months_m <- sort(cs$yrmo[cs$use == "modis"]); months <- sort(c(months_v, months_m))
  is_sat <- use_all %in% c("viirs", "modis")
  V  <- read_mat(grd(one_file(dir_clipped, "_clipped_viirs[.]grd$", "VIIRS-clipped stack")))
  Mc <- read_mat(grd(one_file(dir_clipped, "_clipped_modis[.]grd$", "MODIS-clipped stack")))
  stopifnot(identical(colnames(V), months_v), all(months_m %in% colnames(Mc)))
  S <- norm_map(cbind(V, Mc[, months_m])[, months]); rm(V, Mc)
  H <- norm_map(read_mat(grd(one_file(dir_clipped, "_clipped_hull[.]grd$", "hull-clipped stack")))[, months])
  Rf <- read_mat(file_raw); stopifnot(identical(colnames(Rf), all_yrmo))
  R  <- Rf[, months]; rm(Rf)
  raw_fitted <- colSums(!is.na(R[water, ])) > 0                  # months with a surface
  stopifnot(all(colSums(is.na(R[water, ])) %in% c(0L, sum(water))))   # a layer is all NA on water or has no NA
  Rn <- norm_map(R)
  # The clipping relation: the satellite-clipped layer is the raw layer where the satellite
  # is positive and 0 elsewhere, so raw >= satellite-clipped on every water cell.
  pos <- !is.na(S) & S > 0
  stopifnot(all(Rn[water, ] >= S[water, ]), max(abs(Rn[pos] - S[pos])) < 1e-6, all(raw_fitted[colSums(pos) > 0]))
  C0f <- read_mat(grd(one_file(file.path(dir_hoard11, "before", "combined"), "_clipped_combined[.]grd$", "6 Oct 2026 combined stack")))
  CBf <- read_mat(grd(one_file(file.path(dir_hoard10, "after", "combined"), "_clipped_combined[.]grd$", "run B combined stack")))
  stopifnot(identical(colnames(C0f), all_yrmo), identical(colnames(CBf), all_yrmo), all(is.na(C0f) == land), all(is.na(CBf) == land),
            same(C0f[, months], S), same(C0f[, !is_sat], CBf[, !is_sat]))
  M5 <- S; M5[set5, ] <- pmax(S[set5, ], H[set5, ])
  stopifnot(same(M5, CBf[, months]))
  n_changed5 <- colSums(M5 != S, na.rm = TRUE)
  stopifnot(sum(n_changed5[months_v] > 0) == expected$n_changed_mask5_viirs, sum(n_changed5[months_m] > 0) == expected$n_changed_mask5_modis)
  A1 <- S; A1[adj8, ] <- pmax(S[adj8, ], Rn[adj8, ])
  A2 <- S; A2[adj8_mask, ] <- pmax(S[adj8_mask, ], Rn[adj8_mask, ])
  A3 <- S; A3[adj8, ] <- pmax(S[adj8, ], H[adj8, ])
  A4 <- S; A4[union_set, ] <- pmax(S[union_set, ], H[union_set, ])   # the union with the mask5 fill (Holden, 22 Oct 2026)
  stopifnot(same(A1[adj8, ], Rn[adj8, ]), same(A2[adj8_mask, ], Rn[adj8_mask, ]), same(A1[!adj8, ], S[!adj8, ]), same(A3[!adj8, ], S[!adj8, ]),
            all(A1[water, ] >= S[water, ]), all(A2[water, ] >= A1[water, ]), all(A3[water, ] >= S[water, ]), all(A1[water, ] >= A3[water, ]),
            all(colSums(A1 != S, na.rm = TRUE)[!raw_fitted] == 0), !any(A1[atl, ] != S[atl, ], na.rm = TRUE), !any(A2[atl, ] != S[atl, ], na.rm = TRUE),
            same(A4[!union_set, ], S[!union_set, ]), all(A4[water, ] >= M5[water, ]), all(A4[water, ] >= A3[water, ]), !any(A4[atl, ] != S[atl, ], na.rm = TRUE),
            same(A4[set5, ], M5[set5, ]), same(A4[adj8, ], A3[adj8, ]))
  Ms <- list(v6oct = S, mask5 = M5, adj8_sdm = A1, adj8m_sdm = A2, adj8_hull = A3, union_hull = A4)
  set_of <- list(v6oct = rep(FALSE, n5), mask5 = set5, adj8_sdm = adj8, adj8m_sdm = adj8_mask, adj8_hull = adj8, union_hull = union_set)
  variants <- c(v6oct = "6 Oct 2026 maps (satellite only)", mask5 = "mask5 hybrid, both sensors (#11, #10)",
                adj8_sdm = "land-adjacent set, raw sdmTMB fill (#15)", adj8m_sdm = "land-adjacent or VIIRS mask, raw sdmTMB fill",
                adj8_hull = "land-adjacent set, hull fill", union_hull = "union of mask5 and land-adjacent, hull fill")
  keys <- names(Ms)
  cat(sprintf("Satellite months: %d (%d VIIRS, %d MODIS); raw surface present in %d of them; mask5 changes %d VIIRS and %d MODIS months\n",
              length(months), length(months_v), length(months_m), sum(raw_fitted), sum(n_changed5[months_v] > 0), sum(n_changed5[months_m] > 0)))

  # 4. Per-month table, every variant side by side.
  pts <- load_samples(all_yrmo); pw <- pts[pts$water, ]; pws <- pw[pw$yrmo %in% months, ]
  per <- lapply(Ms, function(M) cbind(expo_of(M), samples_of(M, pws, months)[, -1], cells_changed = colSums(M != S, na.rm = TRUE)))
  m6 <- match(months, tab6$yrmo); stopifnot(!anyNA(m6), identical(tab6$use[m6], ifelse(months %in% months_v, "viirs", "modis")),
                                           all(per$v6oct$samples_ge10k == tab6$n_pos_1e4_water[m6]))
  em <- data.frame(yrmo = months, year = as.integer(substr(months, 1, 4)), month = as.integer(substr(months, 5, 6)),
                   use = tab6$use[m6], fit_status = tab6$fit_status[m6], raw_surface = raw_fitted, viirs_status = tab6$viirs_status[m6],
                   zeroed = months %in% zeroed, headline = months %in% headline, viirs_pos_fitted = months %in% sel3,
                   samples_ge10k = per$v6oct$samples_ge10k, samples_gt1M = per$v6oct$samples_gt1M, stringsAsFactors = FALSE)
  em$ge5 <- em$samples_ge10k >= min_samples_group
  metrics <- c("exposure", "n_ge10k", "km2_ge10k", "n_ge100k", "n_ge1M", "max_cells", "cells_changed", "in_ge10k", "in_gt1M")
  for (k in keys) { for (mt in metrics) em[[paste0(mt, "_", k)]] <- per[[k]][[mt]]; em[[paste0("share_ge10k_", k)]] <- share(per[[k]]$in_ge10k, em$samples_ge10k) }
  stopifnot(all(em$cells_changed_v6oct == 0), sum(em$zeroed) == expected$n_zeroed, sum(em$headline) == expected$n_headline, sum(em$viirs_pos_fitted) == expected$n_sel3,
            all(em$in_ge10k_mask5 >= em$in_ge10k_v6oct), all(em$in_ge10k_adj8_sdm >= em$in_ge10k_v6oct), all(em$in_ge10k_adj8m_sdm >= em$in_ge10k_adj8_sdm),
            all(em$exposure_adj8_sdm >= em$exposure_adj8_hull), all(em$exposure_adj8_hull >= em$exposure_v6oct))
  # The 6 Oct 2026 and mask5 figures equal the #11 and #10 tables.
  e11 <- read.csv(file_expo11, colClasses = c(yrmo = "character"), stringsAsFactors = FALSE); j11 <- match(months, e11$yrmo); stopifnot(!anyNA(j11))
  r10 <- read.csv(file_rec10, colClasses = c(yrmo = "character"), stringsAsFactors = FALSE); j10 <- match(months, r10$yrmo); stopifnot(!anyNA(j10))
  stopifnot(all(abs(em$exposure_v6oct - e11$exposure_before[j11]) <= 1), all(em$n_ge10k_v6oct == e11$n_ge1e4_before[j11]), all(em$in_ge10k_v6oct == e11$samples_ge1e4_in_before[j11]),
            all(abs(em$exposure_mask5 - r10$exposure_v10[j10]) <= 1), all(em$n_ge10k_mask5 == r10$n_ge1e4_v10[j10]), all(em$in_ge10k_mask5 == r10$in_ge1e4_v10[j10]),
            all(em$in_gt1M_mask5 == r10$in_high_v10[j10]))
  write.csv(round_cols(em), file.path(dir_tab, "examine_months_issue15.csv"), row.names = FALSE)

  # Sums by group and by year.
  sum_block <- function(d) {
    r <- data.frame(n_months = nrow(d), months_with_surface = sum(d$raw_surface))
    for (k in keys) {
      r[[paste0("months_changed_", k)]] <- sum(d[[paste0("cells_changed_", k)]] > 0)
      r[[paste0("months_ge10k_", k)]]   <- sum(d[[paste0("n_ge10k_", k)]] > 0)
      r[[paste0("exposure_", k)]]       <- sum(d[[paste0("exposure_", k)]])
      for (t in names(thr)) r[[paste0("cellmonths_", t, "_", k)]] <- sum(d[[paste0("n_", t, "_", k)]])
    }
    r$samples_ge10k <- sum(d$samples_ge10k); r$samples_gt1M <- sum(d$samples_gt1M)
    for (k in keys) { r[[paste0("in_ge10k_", k)]] <- sum(d[[paste0("in_ge10k_", k)]]); r[[paste0("share_ge10k_", k)]] <- share(r[[paste0("in_ge10k_", k)]], r$samples_ge10k) }
    for (k in keys) { r[[paste0("in_gt1M_", k)]] <- sum(d[[paste0("in_gt1M_", k)]]); r[[paste0("share_gt1M_", k)]] <- share(r[[paste0("in_gt1M_", k)]], r$samples_gt1M) }
    for (k in keys[-1]) r[[paste0("exposure_ratio_", k)]] <- share(r[[paste0("exposure_", k)]], r$exposure_v6oct)
    for (k in keys[-(1:2)]) r[[paste0("exposure_vs_mask5_", k)]] <- share(r[[paste0("exposure_", k)]], r$exposure_mask5)
    r
  }
  groups <- list(months, months_v, months_m, months[em$zeroed], months[em$headline], months[em$viirs_pos_fitted], months[em$ge5], months[em$raw_surface], months[!em$raw_surface])
  names(groups) <- c(sprintf("all %d satellite months", length(months)), sprintf("the %d VIIRS months", length(months_v)), sprintf("the %d MODIS months", length(months_m)),
                     sprintf("the %d zeroed months of #6", sum(em$zeroed)), sprintf("the %d headline months of #6", sum(em$headline)),
                     sprintf("the %d VIIRS-positive fitted months of #6", sum(em$viirs_pos_fitted)),
                     sprintf("the %d months with at least %d water samples >= 10k cells/L", sum(em$ge5), min_samples_group),
                     sprintf("the %d satellite months with a fitted surface", sum(em$raw_surface)), sprintf("the %d satellite months without one", sum(!em$raw_surface)))
  grp <- do.call(rbind, lapply(names(groups), function(lab) cbind(group = lab, sum_block(em[em$yrmo %in% groups[[lab]], ]), stringsAsFactors = FALSE)))
  rownames(grp) <- NULL
  write.csv(round_cols(grp), file.path(dir_tab, "examine_groups_issue15.csv"), row.names = FALSE)
  ann <- do.call(rbind, lapply(split(em, em$year), function(d) cbind(year = d$year[1], clip_sources = paste(sort(unique(d$use)), collapse = "/"), sum_block(d))))
  rownames(ann) <- NULL
  write.csv(round_cols(ann), file.path(dir_tab, "examine_annual_issue15.csv"), row.names = FALSE)
  g <- grp[1, ]
  stopifnot(g$months_with_surface == expected$n_surface, g$samples_ge10k == expected$samples_ge10k, g$samples_gt1M == expected$samples_gt1M,
            all(sapply(names(expected$exposure), function(k) abs(g[[paste0("exposure_", k)]] - expected$exposure[[k]]) <= 1 && g[[paste0("in_ge10k_", k)]] == expected$in_ge10k[[k]] &&
                                          g[[paste0("in_gt1M_", k)]] == expected$in_gt1M[[k]] && g[[paste0("months_changed_", k)]] == expected$months_changed[[k]] &&
                                          g[[paste0("cellmonths_ge10k_", k)]] == expected$cellmonths_ge10k[[k]])))
  for (k in keys) cat(sprintf("  %-10s exposure %s (x %.3f vs 6 Oct), cell-months >= 10k %s / >= 100k %s / >= 1M %s, samples >= 10k included %s of %s (%.1f%%), > 1M %s of %s (%.1f%%), months changed %d\n",
                              k, fmt_n(round(g[[paste0("exposure_", k)]])), g[[paste0("exposure_", k)]] / g$exposure_v6oct,
                              fmt_n(g[[paste0("cellmonths_ge10k_", k)]]), fmt_n(g[[paste0("cellmonths_ge100k_", k)]]), fmt_n(g[[paste0("cellmonths_ge1M_", k)]]),
                              fmt_n(g[[paste0("in_ge10k_", k)]]), fmt_n(g$samples_ge10k), 100 * g[[paste0("share_ge10k_", k)]],
                              fmt_n(g[[paste0("in_gt1M_", k)]]), fmt_n(g$samples_gt1M), 100 * g[[paste0("share_gt1M_", k)]], g[[paste0("months_changed_", k)]]))

  # 5. The whole record (504 months): the hull months are identical in every variant.
  Mf <- lapply(keys, function(k) { X <- C0f; X[, months] <- Ms[[k]]; X }); names(Mf) <- keys
  stopifnot(same(Mf$mask5, CBf)); rm(CBf)
  per_f <- lapply(Mf, function(M) cbind(expo_of(M), samples_of(M, pw, all_yrmo)[, -1]))
  rec <- data.frame(yrmo = all_yrmo, year = as.integer(substr(all_yrmo, 1, 4)), month = as.integer(substr(all_yrmo, 5, 6)), use = use_all,
                    fit_status = tab6$fit_status[match(all_yrmo, tab6$yrmo)], viirs_status = tab6$viirs_status[match(all_yrmo, tab6$yrmo)],
                    samples_ge10k = per_f$v6oct$samples_ge10k, samples_gt1M = per_f$v6oct$samples_gt1M, stringsAsFactors = FALSE)
  for (k in keys) for (mt in c("exposure", "n_ge10k", "n_ge100k", "n_ge1M", "in_ge10k", "in_gt1M")) rec[[paste0(mt, "_", k)]] <- per_f[[k]][[mt]]
  stopifnot(all(rec$exposure_adj8_sdm[!is_sat] == rec$exposure_v6oct[!is_sat]), all(rec$in_ge10k_adj8_sdm[!is_sat] == rec$in_ge10k_v6oct[!is_sat]))
  write.csv(round_cols(rec), file.path(dir_tab, "record_months_issue15.csv"), row.names = FALSE)
  rec_groups <- list(all_yrmo, all_yrmo[!is_sat], months)
  names(rec_groups) <- c(sprintf("all %d months 1985-2026", length(all_yrmo)), sprintf("the %d hull months", sum(!is_sat)), sprintf("the %d satellite months", length(months)))
  rec_block <- function(d) {
    r <- data.frame(n_months = nrow(d))
    for (k in keys) { r[[paste0("exposure_", k)]] <- sum(d[[paste0("exposure_", k)]]); for (t in names(thr)) r[[paste0("cellmonths_", t, "_", k)]] <- sum(d[[paste0("n_", t, "_", k)]]) }
    r$samples_ge10k <- sum(d$samples_ge10k); r$samples_gt1M <- sum(d$samples_gt1M)
    for (k in keys) { r[[paste0("in_ge10k_", k)]] <- sum(d[[paste0("in_ge10k_", k)]]); r[[paste0("share_ge10k_", k)]] <- share(r[[paste0("in_ge10k_", k)]], r$samples_ge10k) }
    for (k in keys) { r[[paste0("in_gt1M_", k)]] <- sum(d[[paste0("in_gt1M_", k)]]); r[[paste0("share_gt1M_", k)]] <- share(r[[paste0("in_gt1M_", k)]], r$samples_gt1M) }
    for (k in keys[-1]) r[[paste0("exposure_ratio_", k)]] <- share(r[[paste0("exposure_", k)]], r$exposure_v6oct)
    r
  }
  rgrp <- do.call(rbind, lapply(names(rec_groups), function(lab) cbind(group = lab, rec_block(rec[rec$yrmo %in% rec_groups[[lab]], ]), stringsAsFactors = FALSE)))
  rownames(rgrp) <- NULL
  stopifnot(abs(rgrp$exposure_mask5[3] - g$exposure_mask5) <= 1, rgrp$in_ge10k_adj8_sdm[3] == g$in_ge10k_adj8_sdm)
  write.csv(round_cols(rgrp), file.path(dir_tab, "record_groups_issue15.csv"), row.names = FALSE)

  # 6. What the fills write into their set cells: the cell-months the variant changes
  # against the delivered map, by class of the value written.
  fill_groups <- list(months, months_v, months_m)
  names(fill_groups) <- names(groups)[1:3]
  fill <- do.call(rbind, lapply(keys[-1], function(k) do.call(rbind, lapply(names(fill_groups), function(lab) {
    s <- set_of[[k]]; cols <- fill_groups[[lab]]
    v <- Ms[[k]][s, cols]; chg <- v != S[s, cols]
    vals <- v[chg]; cls <- cut(vals, class_brks, labels = class_lab, right = TRUE)
    r <- data.frame(variant = k, group = lab, set_cells = sum(s), cellmonths = length(v), cellmonths_changed = sum(chg),
                    share_changed = share(sum(chg), length(v)), stringsAsFactors = FALSE)
    for (cl in class_lab) r[[paste0("changed_", cl)]] <- sum(cls == cl)
    r$share_changed_below_10k <- share(sum(vals < thr_bloom), length(vals))
    r$median_value_changed <- if (length(vals)) median(vals) else NA_real_
    r$exposure_added <- sum(vals - S[s, cols][chg])
    r
  }))))
  rownames(fill) <- NULL
  stopifnot(all(fill$changed_zero == 0), all(abs(fill$exposure_added[fill$group == names(groups)[1]] - (g[paste0("exposure_", keys[-1])] - g$exposure_v6oct)) <= 1))
  write.csv(round_cols(fill), file.path(dir_tab, "fill_values_issue15.csv"), row.names = FALSE)

  # 7. The water samples >= 10k cells/L outside the delivered footprint, and which variant
  # includes them; by distance to the coast.
  j <- match(pws$yrmo, months); g10 <- pws$ge10k
  inc <- sapply(Ms, function(M) M[cbind(pws$cell5, j)] > 0)
  ex_rows <- which(g10 & !inc[, "v6oct"])
  excl <- data.frame(yrmo = pws$yrmo[ex_rows], use = em$use[j[ex_rows]], lon = round(pws$lon[ex_rows], 5), lat = round(pws$lat[ex_rows], 5), cells = pws$cells[ex_rows],
                     cell5 = pws$cell5[ex_rows], in_adj8 = adj8[pws$cell5[ex_rows]], in_viirs_mask = in_mask[pws$cell5[ex_rows]], in_mask5 = set5[pws$cell5[ex_rows]],
                     dist_coast_km = round(dist_coast_km(pws$lon[ex_rows], pws$lat[ex_rows]), 2), stringsAsFactors = FALSE)
  for (k in keys[-1]) excl[[paste0("included_", k)]] <- inc[ex_rows, k]
  stopifnot(nrow(excl) == expected$n_excluded, nrow(excl) == g$samples_ge10k - g$in_ge10k_v6oct, all(sapply(keys[-1], function(k) sum(excl[[paste0("included_", k)]]) == g[[paste0("in_ge10k_", k)]] - g$in_ge10k_v6oct)))
  write.csv(excl, file.path(dir_tab, "excluded_samples_issue15.csv"), row.names = FALSE)
  dist_g <- dist_coast_km(pws$lon[g10], pws$lat[g10]); bg <- band_of(dist_g)
  bands <- data.frame(band = band_lv, samples_ge10k = as.vector(table(bg)), in_adj8 = as.vector(table(bg[adj8[pws$cell5[g10]]])), in_mask5 = as.vector(table(bg[set5[pws$cell5[g10]]])),
                      excluded_v6oct = as.vector(table(bg[!inc[g10, "v6oct"]])), stringsAsFactors = FALSE)
  for (k in keys[-1]) bands[[paste0("recovered_", k)]] <- as.vector(table(bg[!inc[g10, "v6oct"] & inc[g10, k]]))
  tot <- data.frame(band = "all", t(colSums(bands[, -1])), stringsAsFactors = FALSE); names(tot) <- names(bands)
  bands <- rbind(bands, tot)
  for (k in keys) bands[[paste0("share_included_", k)]] <- share(bands$samples_ge10k - bands$excluded_v6oct + (if (k == "v6oct") 0 else bands[[paste0("recovered_", k)]]), bands$samples_ge10k)
  stopifnot(bands$excluded_v6oct[nrow(bands)] == nrow(excl))
  write.csv(bands, file.path(dir_tab, "excluded_bands_issue15.csv"), row.names = FALSE)
  cat(sprintf("Excluded samples >= 10k cells/L (satellite months): %d; recovered by mask5 %d, by adj8_sdm %d, by adj8m_sdm %d, by adj8_hull %d; median distance to the coast %.1f km\n",
              nrow(excl), sum(excl$included_mask5), sum(excl$included_adj8_sdm), sum(excl$included_adj8m_sdm), sum(excl$included_adj8_hull), median(excl$dist_coast_km)))

  # 8. The set cells: where they are, how often the satellite and the hull are positive there.
  any_set <- adj8_all | adj4_all | ring2_all | in_mask | set5
  land_rc <- cbind(row5[land], col5[land])
  nearest_land <- function(i) min(pmax(abs(land_rc[, 1] - row5[i]), abs(land_rc[, 2] - col5[i])))   # Chebyshev distance in cells
  cells_tab <- data.frame(cell = which(any_set), row = row5[any_set], col = col5[any_set], lon = round(xy5[any_set, 1], 4), lat = round(xy5[any_set, 2], 4),
                          depth_m = round(dv[any_set], 1), km2 = round(cell_km2[any_set], 1), dist_coast_km = round(dist_w[any_set], 2),
                          nearest_land_cells = sapply(which(any_set), nearest_land),
                          atlantic = atl[any_set], adj8 = adj8[any_set], adj4 = adj4[any_set], ring2 = ring2[any_set], viirs_mask = in_mask[any_set],
                          within5km = near5[any_set], mask5 = set5[any_set], adj8_mask = adj8_mask[any_set], union = union_set[any_set],
                          months_sat_positive = rowSums(S[any_set, ] > 0, na.rm = TRUE), months_hull_positive = rowSums(H[any_set, ] > 0, na.rm = TRUE),
                          months_raw_ge10k = rowSums(Rn[any_set, ] >= thr_bloom, na.rm = TRUE), stringsAsFactors = FALSE)
  write.csv(cells_tab, file.path(dir_tab, "set_cells_issue15.csv"), row.names = FALSE)

  # 9. Per water cell over the satellite months: cumulative exposure and cell-months at or
  # above 100k and 1M cells/L, v6oct, mask5, adj8_sdm.
  ck <- c("v6oct", "mask5", "adj8_sdm")
  cum <- lapply(Ms[ck], function(M) rowSums(M)); n5k <- lapply(Ms[ck], function(M) rowSums(M >= 1e5)); n1m <- lapply(Ms[ck], function(M) rowSums(M >= 1e6))
  cells <- data.frame(cell = which(water), lon = round(xy5[water, 1], 4), lat = round(xy5[water, 2], 4), depth_m = round(dv[water], 1), adj8 = adj8[water], mask5 = set5[water])
  for (k in ck) { cells[[paste0("exposure_", k)]] <- cum[[k]][water]; cells[[paste0("cellmonths_ge100k_", k)]] <- n5k[[k]][water]; cells[[paste0("cellmonths_ge1M_", k)]] <- n1m[[k]][water] }
  cells$exposure_adj8_sdm_minus_mask5 <- cells$exposure_adj8_sdm - cells$exposure_mask5
  cells$cellmonths_ge100k_adj8_sdm_minus_mask5 <- cells$cellmonths_ge100k_adj8_sdm - cells$cellmonths_ge100k_mask5
  write.csv(round_cols(cells), file.path(dir_tab, "cells_sat_issue15.csv"), row.names = FALSE)

  # Fig 1: the sets on the map.
  f_fig1 <- png_open(file.path(dir_fig, "fig1_sets_issue15.png"), width = 15, height = 7.2)
  par(mfrow = c(1, 2), mar = c(2.6, 2.8, 2.6, 0.6), oma = c(0, 0, 2.2, 0))
  set_cols <- c(both = "purple3", only_new = "darkorange2", only_mask5 = "deepskyblue3")
  draw_sets <- function(new, main) {
    z <- ifelse(new & set5, 1, ifelse(new, 2, ifelse(set5, 3, NA)))
    base_panel(main, axes = TRUE, cex_main = 0.9); rect(xlim[1], ylim[1], xlim[2], ylim[2], col = "white", border = NA)
    image(xs, ys, to_z(z), breaks = c(0.5, 1.5, 2.5, 3.5), col = unname(set_cols), add = TRUE, useRaster = TRUE)
    draw_land()
    half <- raster::res(depth) / 2
    mk <- which(in_mask); rect(xy5[mk, 1] - half[1], xy5[mk, 2] - half[2], xy5[mk, 1] + half[1], xy5[mk, 2] + half[2], border = "black", lwd = 0.5)
    mm <- which(in_mask & !new); if (length(mm)) points(xy5[mm, 1], xy5[mm, 2], pch = 4, col = "red", lwd = 1.6, cex = 1.1)
    abline(v = -82, h = 28.5, lty = 3, col = "gray40")
    legend("bottomleft", legend = c(sprintf("in both (%d)", sum(new & set5)), sprintf("this set only (%d)", sum(new & !set5)), sprintf("mask5 only (%d)", sum(set5 & !new)),
                                    sprintf("VIIRS static mask (%d cells, outlined)", sum(in_mask)), sprintf("mask cells this set misses (%d)", length(mm)), "Atlantic box (excluded)"),
           fill = c(unname(set_cols), NA, NA, NA), border = c(rep(NA, 3), "black", NA, NA), pch = c(NA, NA, NA, NA, 4, NA), col = c(NA, NA, NA, "black", "red", "gray40"),
           lty = c(rep(NA, 5), 3), cex = 0.8, bg = "white", box.col = "gray60")
    box()
  }
  draw_sets(adj8, sprintf("Land-adjacent (edge or corner): %d cells, %s km2; mask5: %d cells, %s km2", sum(adj8), fmt_n(round(sum(cell_km2[adj8]))), sum(set5), fmt_n(round(sum(cell_km2[set5])))))
  # Panel 2: the union = mask5 plus the adjacent-only cells; the mask5 cells adjacency
  # misses (bays cut by the map edge, barrier islands the 5-arcmin grid draws as water) ringed.
  z <- ifelse(set5, 1, ifelse(adj8, 2, NA))
  base_panel(sprintf("Union of mask5 and land-adjacent: %d cells, %s km2 (mask5 plus %d adjacent-only cells)", sum(union_set), fmt_n(round(sum(cell_km2[union_set]))), sum(adj8 & !set5)), axes = TRUE, cex_main = 0.9)
  rect(xlim[1], ylim[1], xlim[2], ylim[2], col = "white", border = NA)
  image(xs, ys, to_z(z), breaks = c(0.5, 1.5, 2.5), col = c("purple3", "darkorange2"), add = TRUE, useRaster = TRUE)
  draw_land()
  mo <- which(set5 & !adj8); points(xy5[mo, 1], xy5[mo, 2], pch = 1, col = "black", lwd = 1.6, cex = 1.4)
  text(xy5[mo, 1], xy5[mo, 2], labels = mo, pos = 4, offset = 0.45, cex = 0.55)
  abline(v = -82, h = 28.5, lty = 3, col = "gray40")
  legend("bottomleft", legend = c(sprintf("mask5: VIIRS mask or within 5 km of the coastline (%d)", sum(set5)), sprintf("added by land adjacency (%d; centres %.1f to %.1f km from the coastline)", sum(adj8 & !set5), min(dist_w[adj8 & !set5]), max(dist_w[adj8 & !set5])),
                                  sprintf("mask5 cells that touch no land cell (%d, labelled; bays cut by the map edge, barrier islands)", length(mo)), "Atlantic box (excluded)"),
         fill = c("purple3", "darkorange2", NA, NA), border = NA, pch = c(NA, NA, 1, NA), col = c(NA, NA, "black", "gray40"), lty = c(NA, NA, NA, 3), cex = 0.78, bg = "white", box.col = "gray60")
  box()
  mtext("Issue #15: the nearshore sets on the 5-arcmin Ecospace basemap (land = NODATA of the depth grid; gray = land, black line = Natural Earth coastline, the 5 km reference)", outer = TRUE, cex = 0.95, font = 2, line = 0.5)
  png_done(f_fig1)

  # Fig 2: the record from the first satellite month, the #10 fig 4 layout, four variants.
  use_col <- c(pred = grDevices::adjustcolor("gray40", 0.12), modis = grDevices::adjustcolor("steelblue", 0.18), viirs = grDevices::adjustcolor("gold", 0.22))
  zero_col <- grDevices::adjustcolor("gray40", 0.3); miss_col <- grDevices::adjustcolor("red", 0.25)
  vcol <- c(v6oct = "black", mask5 = "purple3", adj8_sdm = "darkorange2", adj8m_sdm = "darkorange2", adj8_hull = "forestgreen", union_hull = "forestgreen")
  vlty <- c(v6oct = 1, mask5 = 1, adj8_sdm = 1, adj8m_sdm = 2, adj8_hull = 1, union_hull = 2); vpch <- c(v6oct = 16, mask5 = 1, adj8_sdm = 2, adj8m_sdm = 6, adj8_hull = 0, union_hull = 5)
  draw_record <- function(d, title, keys = names(Ms)) {
    n <- nrow(d); x <- seq_len(n); few <- d$samples_ge10k < min_samples_group; nk <- length(keys)
    panel_of <- function(mt, lab, main, pts = FALSE, div = 1) list(y = lapply(keys, function(k) { y <- d[[paste0(mt, "_", k)]] / div; if (pts) { y <- y / d$samples_ge10k; y[few] <- NA }; y }), lab = lab, main = main, pts = pts)
    panels <- list(panel_of("exposure", "million cells/L (sum over water cells)", sprintf("Total exposure: cells/L summed over the %s water cells", fmt_n(sum(water))), div = 1e6),
                   panel_of("n_ge10k", "cells", "Grid cells at or above 10k cells/L"),
                   panel_of("n_ge100k", "cells", "Grid cells at or above 100k cells/L"),
                   panel_of("n_ge1M", "cells", "Grid cells at or above 1M cells/L"),
                   panel_of("in_ge10k", "share of samples", sprintf("Share of the in-situ samples >= 10k cells/L (water cells) that the projection includes, months with at least %d such samples", min_samples_group), pts = TRUE))
    par(mfrow = c(length(panels), 1), mar = c(2.8, 4.6, 2.2, 0.6), oma = c(0, 0, 1.8, 0), mgp = c(3, 0.6, 0))
    for (i in seq_along(panels)) {
      p <- panels[[i]]
      yl <- if (p$pts) c(0, 1.04) else c(0, max(c(unlist(p$y), 1), na.rm = TRUE) * 1.08)
      plot(NA, xlim = c(0.5, n + 0.5), ylim = yl, xlab = "", ylab = p$lab, main = p$main, cex.main = 0.95, axes = FALSE, xaxs = "i", yaxs = "i")
      for (u in names(use_col)) { w <- which(d$use == u); if (length(w)) rect(w - 0.5, yl[1], w + 0.5, yl[2], col = use_col[[u]], border = NA) }
      zm <- which(d$viirs_status == "zero"); mm2 <- which(d$viirs_status == "missing")
      rect(zm - 0.5, yl[1], zm + 0.5, yl[2], col = zero_col, border = NA); rect(mm2 - 0.5, yl[1], mm2 + 0.5, yl[2], col = miss_col, border = NA)
      for (k in rev(seq_len(nk))) {
        if (p$pts) points(x, p$y[[k]], col = vcol[[keys[k]]], pch = vpch[[keys[k]]], cex = if (k == 1) 0.6 else 0.8, lwd = 1.1) else
          lines(x, p$y[[k]], col = vcol[[keys[k]]], lwd = if (k == 1) 1.4 else 1.7, lty = vlty[[keys[k]]])
      }
      jan <- which(d$month == 1); axis(1, at = jan, labels = d$year[jan], cex.axis = 0.85)
      axis(2, las = 1, cex.axis = 0.85); box()
      if (i == 1) legend("topleft", legend = c(unname(variants[keys]), "hull months", "MODIS months", "VIIRS months", "VIIRS layer all zero", "VIIRS tif missing (2022-12)"),
                         col = c(unname(vcol[keys]), rep(NA, 5)), lwd = c(1.4, rep(1.7, nk - 1), rep(NA, 5)), lty = c(unname(vlty[keys]), rep(NA, 5)),
                         fill = c(rep(NA, nk), use_col[["pred"]], use_col[["modis"]], use_col[["viirs"]], zero_col, miss_col), border = NA, cex = 0.78, bg = "white", box.col = "gray60", ncol = 2)
      if (p$pts) legend("bottomleft", legend = unname(variants[keys]), col = unname(vcol[keys]), pch = unname(vpch[keys]), pt.cex = c(0.6, rep(0.8, nk - 1)), cex = 0.78, bg = "white", box.col = "gray60", ncol = 2)
    }
    mtext(title, outer = TRUE, cex = 0.95, font = 2, line = 0.4)
  }
  f_fig2 <- png_open(file.path(dir_fig, "fig2_record_2002-2026_issue15.png"), width = 15, height = 13.5)
  draw_record(rec[rec$yrmo >= months[1], ], sprintf("Red tide exposure per monthly map from the first satellite month (%s-%s) to %s: the 6 Oct 2026 maps, the mask5 hybrid, and the land-adjacent rule of #15 (plain and with the VIIRS mask added)",
                                                     substr(months[1], 1, 4), substr(months[1], 5, 6), max(rec$year)), keys = c("v6oct", "mask5", "adj8_sdm", "adj8m_sdm"))
  png_done(f_fig2)

  # Fig 3: the headline months of #6, then the months where adj8_sdm and mask5 differ most
  # in exposure: samples | delivered map | mask5 | adj8_sdm | raw sdmTMB (adj8 set shaded).
  dexp <- abs(em$exposure_adj8_sdm - em$exposure_mask5)
  top  <- em$yrmo[order(-dexp, em$yrmo)]; top <- setdiff(top, headline)[seq_len(fig3_top)]
  fig3_months <- c(sort(months[months %in% headline]), top)
  pts$in_before <- FALSE; pts$in_before[pts$water & pts$yrmo %in% months] <- inc[, "v6oct"]   # pws is pts[pts$water & sat, ] in the same order
  draw_samples_panel <- function(ym, main) {
    q <- pts[pts$yrmo == ym, ]
    base_panel(main); rect(xlim[1], ylim[1], xlim[2], ylim[2], col = "white", border = NA); draw_land()
    z0 <- q[q$cells == 0, ]; points(z0$lon, z0$lat, pch = ".", cex = 1.6, col = "gray45")
    pp <- q[q$cells > 0, ]; pp <- pp[order(pp$cells), ]
    bins <- cut(pp$cells, class_brks[-1], labels = FALSE, include.lowest = TRUE)
    bord <- ifelse(pp$ge10k & pp$water & !pp$in_before, "red", "black")
    points(pp$lon, pp$lat, pch = 21, bg = spal[bins], col = bord, cex = 0.75, lwd = 0.9)
    hi <- q[q$ge10k & q$water, ]
    info_box(c(class_lines(class_counts_v(q$cells)), sprintf(">= 10k on water: %d, %d outside the delivered footprint", nrow(hi), sum(!hi$in_before)), sprintf("%d on template land", sum(!q$water))))
    box()
  }
  draw_row <- function(ym) {
    lab <- paste0(substr(ym, 1, 4), "-", substr(ym, 5, 6)); k <- match(ym, months); r <- em[k, ]
    draw_samples_panel(ym, sprintf("%s: FWC samples (%s, fit %s%s)", lab, toupper(r$use), r$fit_status, if (r$headline) ", headline" else ""))
    draw_map_panel(S[, k], sprintf("delivered map (%s-clipped): %s km2 >= 10k", toupper(r$use), fmt_n(round(r$km2_ge10k_v6oct))),
                   extra = sprintf(">= 10k samples inside: %d / %d", r$in_ge10k_v6oct, r$samples_ge10k))
    draw_map_panel(M5[, k], sprintf("mask5 hybrid: %s km2 (+%s)", fmt_n(round(r$km2_ge10k_mask5)), fmt_n(round(r$km2_ge10k_mask5) - round(r$km2_ge10k_v6oct))),
                   diff_from = S[, k], extra = sprintf("inside: %d / %d; %d cells changed", r$in_ge10k_mask5, r$samples_ge10k, r$cells_changed_mask5))
    draw_map_panel(A1[, k], sprintf("land-adjacent, raw fill (#15): %s km2 (+%s)", fmt_n(round(r$km2_ge10k_adj8_sdm)), fmt_n(round(r$km2_ge10k_adj8_sdm) - round(r$km2_ge10k_v6oct))),
                   diff_from = S[, k], extra = sprintf("inside: %d / %d; %d cells changed", r$in_ge10k_adj8_sdm, r$samples_ge10k, r$cells_changed_adj8_sdm))
    draw_map_panel(Rn[, k], sprintf("raw sdmTMB: %s km2 >= 10k (adjacent set shaded)", fmt_n(round(expo_of(Rn[, k, drop = FALSE])$km2_ge10k))), shade = adj8,
                   extra = sprintf("inside: %d / %d; max %s", samples_of(Rn[, k, drop = FALSE], pws[pws$yrmo == ym, ], ym)$in_ge10k, r$samples_ge10k, fmt_n(signif(r$max_cells_adj8_sdm, 3))))
  }
  pages <- split(fig3_months, ceiling(seq_along(fig3_months) / fig3_per_page))
  draw_fig3_page <- function(i) {
    par(mfrow = c(fig3_per_page, 5), mar = c(0.4, 0.5, 1.5, 0.5), oma = c(0.3, 0, 4.4, 0))
    for (ym in pages[[i]]) draw_row(ym)
    mtext(sprintf("Issue #15: the %d headline months of #6, then the %d satellite months where the land-adjacent rule and mask5 differ most in exposure (page %d of %d): samples | delivered map | mask5 hybrid | land-adjacent, raw sdmTMB fill | raw sdmTMB",
                  sum(em$headline), fig3_top, i, length(pages)), outer = TRUE, cex = 0.85, font = 2, line = 2.9)
    mtext("km2 in the titles = area >= 10k cells/L (+ = added to the delivered map). Orange = cells the variant changed. Purple shading in the last column = the land-adjacent set (edge or corner with a land cell, Gulf domain).",
          outer = TRUE, cex = 0.7, line = 1.6)
    mtext("Samples: fill = FWC class (viridis, light = background to dark = > 1M cells/L); red border = a water sample >= 10k cells/L outside the delivered footprint. Maps: pipeline palette, white below 10k cells/L.",
          outer = TRUE, cex = 0.7, line = 0.5)
  }
  fig3_w <- 12.5; fig3_h <- 2.4 * fig3_per_page + 1.3
  file_fig3 <- file.path(dir_fig, "fig3_months_issue15.pdf")
  ok_pdf <- write_pdf(file_fig3, width = fig3_w, height = fig3_h, function() for (i in seq_along(pages)) draw_fig3_page(i))
  if (ok_pdf) message("Fig 3 written: ", file_fig3)
  png_dir <- Sys.getenv("RT_QA_PNG_DIR", "")
  if (nzchar(png_dir)) for (i in seq_along(pages)) {
    png(file.path(png_dir, sprintf("fig3_months_p%d.png", i)), width = fig3_w, height = fig3_h, units = "in", res = 70)
    draw_fig3_page(i); invisible(dev.off())
  }

  # Fig 4: per cell over the satellite months (the #10 fig 5 layout and palette).
  pal_fig1 <- colorRampPalette(colv[-1], bias = 2)
  f_fig4 <- png_open(file.path(dir_fig, "fig4_cells_issue15.png"), width = 15, height = 11.5)
  par(mfrow = c(2, 3), mar = c(2.5, 2.8, 2.6, 0.6), oma = c(0, 0, 2.0, 0))
  allpos <- unlist(lapply(cum, function(v) v[which(v > 0)]))
  lmax <- ceiling(max(log10(allpos))); lbrk <- seq(3, lmax, 0.5); lcol <- pal_fig1(length(lbrk) - 1)
  draw_log_map <- function(v, main) {
    lv <- ifelse(!is.na(v) & v > 0, pmax(log10(v), 3), NA)
    base_panel(main, axes = TRUE); rect(xlim[1], ylim[1], xlim[2], ylim[2], col = "white", border = NA)
    image(xs, ys, to_z(lv), breaks = lbrk, col = lcol, add = TRUE, useRaster = TRUE); draw_land(); box()
    at <- seq(3, lmax, 1); legend("bottomleft", legend = sprintf("1e%d", at), fill = lcol[pmin(match(at, lbrk), length(lcol))], border = "gray40", cex = 0.75, bg = "white", box.col = "gray60", title = "cells/L, summed")
  }
  draw_log_map(cum$v6oct, sprintf("6 Oct 2026 maps: cumulative exposure per cell over the %d satellite months (max %s)", length(months), fmt_n(signif(max(cum$v6oct, na.rm = TRUE), 3))))
  draw_log_map(cum$mask5, sprintf("mask5 hybrid: max %s", fmt_n(signif(max(cum$mask5, na.rm = TRUE), 3))))
  draw_log_map(cum$adj8_sdm, sprintf("land-adjacent, raw fill (#15): max %s", fmt_n(signif(max(cum$adj8_sdm, na.rm = TRUE), 3))))
  dd <- cum$adj8_sdm - cum$mask5
  draw_log_map(pmax(dd, 0), sprintf("#15 rule above mask5: %d cells, max %s", sum(dd > 0, na.rm = TRUE), fmt_n(signif(max(dd, na.rm = TRUE), 3))))
  draw_log_map(pmax(-dd, 0), sprintf("mask5 above the #15 rule: %d cells, max %s", sum(dd < 0, na.rm = TRUE), fmt_n(signif(max(-dd, na.rm = TRUE), 3))))
  d5 <- n5k$adj8_sdm - n5k$mask5; dmax5 <- max(abs(d5), na.rm = TRUE)
  base_panel(sprintf("cell-months >= 100k cells/L, #15 rule minus mask5: %d cells gain (up to %d), %d lose (up to %d)", sum(d5 > 0, na.rm = TRUE), max(d5, na.rm = TRUE), sum(d5 < 0, na.rm = TRUE), -min(d5, na.rm = TRUE)), axes = TRUE)
  rect(xlim[1], ylim[1], xlim[2], ylim[2], col = "white", border = NA)
  dpal <- colorRampPalette(c("deepskyblue3", "white", "darkorange2"))(2 * dmax5 + 1)
  image(xs, ys, to_z(d5), breaks = seq(-dmax5 - 0.5, dmax5 + 0.5, 1), col = dpal, add = TRUE, useRaster = TRUE); draw_land(); box()
  legend("bottomleft", legend = c(sprintf("+%d", dmax5), "0", sprintf("-%d", dmax5)), fill = dpal[c(length(dpal), dmax5 + 1, 1)], border = "gray40", cex = 0.75, bg = "white", box.col = "gray60", title = "months")
  mtext(sprintf("Per-cell exposure over the %d satellite months: cumulative cells/L (top: the delivered maps, mask5, the #15 rule) and the differences between the #15 rule and mask5 (bottom)", length(months)), outer = TRUE, cex = 0.95, font = 2, line = 0.5)
  png_done(f_fig4)

  # Markdown summary.
  g_cols <- c("group", "n_months", paste0("months_changed_", keys[-1]), paste0("exposure_", keys), paste0("exposure_ratio_", keys[-1]),
              paste0("cellmonths_ge10k_", keys), paste0("cellmonths_ge100k_", keys), paste0("cellmonths_ge1M_", keys),
              "samples_ge10k", paste0("share_ge10k_", keys), "samples_gt1M", paste0("share_gt1M_", keys))
  line_of <- function(gg, lab) sprintf("Over %s: total exposure %s (6 Oct 2026) -> %s (mask5, %+.1f%%) -> %s (land-adjacent, raw fill, %+.1f%%) -> %s (adjacent or VIIRS mask, %+.1f%%) -> %s (adjacent, hull fill, %+.1f%%); the share of the in-situ water samples >= 10k cells/L the projection includes %.1f%% -> %.1f%% -> %.1f%% -> %.1f%% -> %.1f%% (of %s); the samples > 1M cells/L %.1f%% -> %.1f%% -> %.1f%% -> %.1f%% -> %.1f%% (of %s).",
                                       lab, fmt_n(round(gg$exposure_v6oct)), fmt_n(round(gg$exposure_mask5)), 100 * (gg$exposure_ratio_mask5 - 1), fmt_n(round(gg$exposure_adj8_sdm)), 100 * (gg$exposure_ratio_adj8_sdm - 1),
                                       fmt_n(round(gg$exposure_adj8m_sdm)), 100 * (gg$exposure_ratio_adj8m_sdm - 1), fmt_n(round(gg$exposure_adj8_hull)), 100 * (gg$exposure_ratio_adj8_hull - 1),
                                       100 * gg$share_ge10k_v6oct, 100 * gg$share_ge10k_mask5, 100 * gg$share_ge10k_adj8_sdm, 100 * gg$share_ge10k_adj8m_sdm, 100 * gg$share_ge10k_adj8_hull, fmt_n(gg$samples_ge10k),
                                       100 * gg$share_gt1M_v6oct, 100 * gg$share_gt1M_mask5, 100 * gg$share_gt1M_adj8_sdm, 100 * gg$share_gt1M_adj8m_sdm, 100 * gg$share_gt1M_adj8_hull, fmt_n(gg$samples_gt1M))
  hm <- em[em$headline, c("yrmo", "samples_ge10k", paste0("in_ge10k_", keys), paste0("km2_ge10k_", keys), paste0("exposure_", keys), paste0("max_cells_", keys))]
  # mask5 against the union, both with the hull fill (the comparison Holden asked for, 22 Oct 2026).
  uk <- c(mask5 = "mask5", union_hull = "union"); gz <- grp[4, ]; gv <- grp[2, ]; gm <- grp[3, ]
  cov_u <- cov[match(uk, cov$set), ]
  ut <- data.frame(variant = c("mask5 (VIIRS mask or within 5 km), hull fill", "union of mask5 and land-adjacent, hull fill"),
                   cells = cov_u$cells, km2 = cov_u$km2, viirs_mask_covered = cov_u$viirs_mask_cells_covered, within5km_covered = cov_u$within5km_cells_covered, adjacent_covered = cov_u$adjacent_cells_covered,
                   exposure = sapply(names(uk), function(k) g[[paste0("exposure_", k)]]), exposure_ratio = sapply(names(uk), function(k) g[[paste0("exposure_ratio_", k)]]),
                   cellmonths_ge10k = sapply(names(uk), function(k) g[[paste0("cellmonths_ge10k_", k)]]), cellmonths_ge100k = sapply(names(uk), function(k) g[[paste0("cellmonths_ge100k_", k)]]),
                   cellmonths_ge1M = sapply(names(uk), function(k) g[[paste0("cellmonths_ge1M_", k)]]), months_changed = sapply(names(uk), function(k) g[[paste0("months_changed_", k)]]),
                   in_ge10k = sapply(names(uk), function(k) g[[paste0("in_ge10k_", k)]]), share_ge10k = sapply(names(uk), function(k) g[[paste0("share_ge10k_", k)]]),
                   share_gt1M = sapply(names(uk), function(k) g[[paste0("share_gt1M_", k)]]), share_ge10k_zeroed = sapply(names(uk), function(k) gz[[paste0("share_ge10k_", k)]]),
                   share_ge10k_viirs = sapply(names(uk), function(k) gv[[paste0("share_ge10k_", k)]]), share_ge10k_modis = sapply(names(uk), function(k) gm[[paste0("share_ge10k_", k)]]),
                   exposure_ratio_viirs = sapply(names(uk), function(k) gv[[paste0("exposure_ratio_", k)]]), exposure_ratio_modis = sapply(names(uk), function(k) gm[[paste0("exposure_ratio_", k)]]),
                   stringsAsFactors = FALSE)
  ut$exposure_viirs <- sapply(names(uk), function(k) gv[[paste0("exposure_", k)]]); ut$exposure_modis <- sapply(names(uk), function(k) gm[[paste0("exposure_", k)]])
  rownames(ut) <- NULL
  write.csv(round_cols(ut), file.path(dir_tab, "mask5_vs_union_issue15.csv"), row.names = FALSE)
  # Total exposure by era (Holden, 22 Oct 2026): all satellite months, the VIIRS months, the
  # MODIS months; the delivered maps, mask5 and the union, with the ratios and the samples included.
  ue <- do.call(rbind, lapply(list(g, gv, gm), function(r) data.frame(
    n_months = r$n_months, exposure_v6oct = r$exposure_v6oct, exposure_mask5 = r$exposure_mask5, exposure_union = r$exposure_union_hull,
    ratio_mask5_vs_v6oct = r$exposure_ratio_mask5, ratio_union_vs_v6oct = r$exposure_ratio_union_hull, ratio_union_vs_mask5 = round(r$exposure_union_hull / r$exposure_mask5, 3),
    cellmonths_ge10k_v6oct = r$cellmonths_ge10k_v6oct, cellmonths_ge10k_mask5 = r$cellmonths_ge10k_mask5, cellmonths_ge10k_union = r$cellmonths_ge10k_union_hull,
    samples_ge10k = r$samples_ge10k, share_ge10k_v6oct = r$share_ge10k_v6oct, share_ge10k_mask5 = r$share_ge10k_mask5, share_ge10k_union = r$share_ge10k_union_hull)))
  ue <- cbind(era = names(groups)[1:3], ue, stringsAsFactors = FALSE); rownames(ue) <- NULL
  stopifnot(abs(ue$exposure_union[2] + ue$exposure_union[3] - ue$exposure_union[1]) <= 1, abs(ue$exposure_mask5[2] + ue$exposure_mask5[3] - ue$exposure_mask5[1]) <= 1)
  write.csv(round_cols(ue), file.path(dir_tab, "exposure_by_era_issue15.csv"), row.names = FALSE)
  mo <- which(set5 & !adj8); ao <- which(adj8 & !set5)
  md <- c("# Issue #15: the land-adjacent nearshore rule against mask5 (examine stage)", "",
          sprintf("Produced by `docs/issue15_adjacent-land-hybrid/check_adjacent_hybrid_issue15.R` from the stacks on disk, no pipeline run. Five variants over the %d satellite months (%d VIIRS, %d MODIS; the %d hull months are identical in every variant): the delivered 6 Oct 2026 maps; the mask5 hybrid for both sensors (run B of #10); the land-adjacent set (%d Gulf-domain cells, %s km2) with the raw sdmTMB projection inside it (the #15 rule); the same with the %d cells of the static VIIRS no-data mask added (%d cells); and the land-adjacent set with the mask5 fill (max of the satellite- and hull-clipped maps). Total exposure = the plain sum of cells/L over the %s water cells; cell-months at or above 10k / 100k / 1M cells/L; samples included = water-cell samples >= 10k cells/L (and > 1M) whose cell is non-zero in the map. The Atlantic-side box is always excluded.",
                  length(months), length(months_v), length(months_m), sum(!is_sat), sum(adj8), fmt_n(round(sum(cell_km2[adj8]))), sum(in_mask), sum(adj8_mask), fmt_n(sum(water))),
          "", "## Coverage (`tables/set_coverage_issue15.csv`, `tables/set_missed_mask_cells_issue15.csv`)", "",
          sprintf("- The land-adjacent set (edge or corner) covers %d of the %d template cells in the static VIIRS no-data mask and %d of the %d mask5 cells; %d of its %d cells are not in mask5 (depth %s to %s m). The %d mask cells it misses: %s (%d in the top grid row, where the land to the north is off-grid). Adding the mask gives %d cells. Within 2 cells of land: %d cells (%s km2), covering %d of %d mask cells.",
                  sum(adj8 & in_mask), sum(in_mask), sum(adj8 & set5), sum(set5), sum(adj8 & !set5), sum(adj8), round(min(dv[adj8 & !set5]), 1), round(max(dv[adj8 & !set5]), 1),
                  sum(in_mask & !adj8), paste(which(in_mask & !adj8), collapse = ", "), sum(in_mask & !adj8 & row5 == 1), sum(adj8_mask), sum(ring2), fmt_n(round(sum(cell_km2[ring2]))), sum(ring2 & in_mask), sum(in_mask)),
          "", md_table(cov), "",
          "## mask5 against the union, hull fill (`tables/mask5_vs_union_issue15.csv`)", "",
          sprintf("- mask5 is exactly the VIIRS static mask or a centre within 5 km of the coastline (%d cells, recomposed and checked). The union adds the %d land-adjacent cells mask5 lacks (centres %.1f to %.1f km from the coastline, median %.1f; a cell is 8 to 9 km wide, so a corner-touching neighbour reaches further than 5 km on the open coast) and so covers the %d mask cells, the %d within-5-km cells and the %d adjacent cells by construction. The %d mask5 cells that touch no land cell (%s) all sit two cells from the nearest basemap land cell: bays cut by the map edge and barrier islands the 5-arcmin grid draws as water while the coastline draws them as land.",
                  sum(set5), length(ao), min(dist_w[ao]), max(dist_w[ao]), median(dist_w[ao]), sum(in_mask), sum(near5), sum(adj8), length(mo), paste(mo, collapse = ", ")),
          "", md_table(round_cols(ut), 3), "",
          "### Total exposure by era (`tables/exposure_by_era_issue15.csv`; cells/L summed over the water cells and the months)", "",
          md_table(round_cols(ue), 3), "",
          "## Overall", "",
          paste0("- ", line_of(grp[1, ], names(groups)[1])),
          paste0("- ", line_of(grp[2, ], names(groups)[2])),
          paste0("- ", line_of(grp[3, ], names(groups)[3])),
          "", "## Totals by month group (`tables/examine_groups_issue15.csv`)", "",
          md_table(round_cols(grp[, g_cols]), 3),
          "", "## What the fills write into their set cells (`tables/fill_values_issue15.csv`; cell-months the variant changes against the delivered map, by the value written)", "",
          md_table(round_cols(fill), 3),
          "", "## Samples >= 10k cells/L outside the delivered footprint, by distance to the coast (`tables/excluded_bands_issue15.csv`)", "",
          md_table(bands, 3),
          "", sprintf("## The %d headline months of #6 (`tables/examine_months_issue15.csv`)", sum(em$headline)), "",
          md_table(round_cols(hm), 0),
          "", "## By year (`tables/examine_annual_issue15.csv`; satellite months only, sums over the months)", "",
          md_table(round_cols(ann[, c("year", "clip_sources", g_cols[-1])]), 3),
          "", "## Per cell over the satellite months (`tables/cells_sat_issue15.csv`)", "",
          sprintf("- Cumulative exposure: the #15 rule is above mask5 in %d water cells (up to %s cells/L summed) and below it in %d (up to %s); %d cells gain cell-months >= 100k cells/L against mask5 (up to %d) and %d lose (up to %d).",
                  sum(dd > 0, na.rm = TRUE), fmt_n(signif(max(dd, na.rm = TRUE), 3)), sum(dd < 0, na.rm = TRUE), fmt_n(signif(max(-dd, na.rm = TRUE), 3)),
                  sum(d5 > 0, na.rm = TRUE), max(d5, na.rm = TRUE), sum(d5 < 0, na.rm = TRUE), -min(d5, na.rm = TRUE)),
          "")
  writeLines(md, file.path(dir_cmt, "examine_summary.md"))
  cat(md, sep = "\n")
  message("Stage examine done.")
}
cat("\nDone:", stage, "\n")
