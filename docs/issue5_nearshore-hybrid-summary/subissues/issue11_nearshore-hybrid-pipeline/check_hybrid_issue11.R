#' QA for issue #11: the nearshore hybrid (mask5) in the pipeline.
#'
#' Verifies a pipeline run against the 6 October 2026 deliverables and the issue #8
#' prototype, and compares the VIIRS-only and hybrid maps. Three stages, chosen with
#' RT_QA_STAGE (default "none"). Each reads only what the last run left on disk and the
#' tracked tables, refits nothing and uses no RNG; CSVs and PNGs are byte-identical
#' from run to run (the PDF carries the two date lines every R pdf() device writes).
#'
#'   none     after a run with cfg$viirs_nearshore = "none" (and fwc_refresh = FALSE):
#'            the 504 ASCII files must equal the baseline byte for byte
#'            -> tables/md5_none_issue11.csv
#'   mask5    after a run with "mask5": only VIIRS months with a nearshore hull change,
#'            the set has 136 cells, and the per-month metrics equal the #8 prototype
#'            -> tables/md5_mask5_issue11.csv, tables/nearshore_set_issue11.csv,
#'               tables/hybrid_vs_prototype_issue11.csv,
#'               figures/fig1_headline_before_after_issue11.pdf
#'   compare  the VIIRS-only (before) and hybrid (after) deliverables, read from the
#'            local copies hoard/before/ and hoard/after/ (combined stacks and
#'            clipping_source.csv of the two runs; hoard/ is gitignored)
#'            -> tables/months_issue11.csv, tables/annual_issue11.csv,
#'               tables/climatology_issue11.csv, tables/groups_issue11.csv,
#'               tables/bloom_months_per_cell_issue11.csv,
#'               figures/fig2_area_2012-2024_issue11.png,
#'               figures/fig3_bloom_months_per_cell_issue11.png,
#'               comments/compare_summary.md
#'   exposure red tide exposure per monthly map as Ecospace reads it, both methods, all 504
#'            months 1985-2026 (from the same hoard copies): the sum of cells/L over the
#'            3,838 water cells and the cells at or above 10,000 / 100,000 / 1,000,000 cells/L
#'            -> tables/exposure_months_issue11.csv, tables/exposure_annual_issue11.csv,
#'               tables/exposure_climatology_issue11.csv, tables/exposure_groups_issue11.csv,
#'               tables/exposure_cells_issue11.csv,
#'               figures/fig4_exposure_1985-2026_issue11.png, figures/fig5_exposure_2012-2024_issue11.png,
#'               figures/fig6_exposure_cells_issue11.png, comments/exposure_summary.md
#'
#' Run from the repo root:
#'   RT_QA_STAGE=none    Rscript docs/issue5_nearshore-hybrid-summary/subissues/issue11_nearshore-hybrid-pipeline/check_hybrid_issue11.R
#'   RT_QA_STAGE=mask5   ...   RT_QA_STAGE=compare   ...   RT_QA_STAGE=exposure   ...
#' Baseline: tables/md5_baseline_issue11.csv, the MD5 of the 504 tracked ASCII files
#' at main 7f08076 (the 6 October 2026 run), written before any issue-11 run.

# Repo root: the working directory if it holds the .Rproj, else four levels above this script.
.root <- local({
  if (file.exists("RedTideMaps.Rproj")) return(normalizePath(getwd(), winslash = "/"))
  f <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE))
  if (length(f) == 1) {
    d <- normalizePath(file.path(dirname(f), "..", "..", "..", ".."), winslash = "/", mustWork = FALSE)
    if (file.exists(file.path(d, "RedTideMaps.Rproj"))) return(d)
  }
  stop("Run from the repo root: Rscript docs/issue5_nearshore-hybrid-summary/subissues/issue11_nearshore-hybrid-pipeline/check_hybrid_issue11.R", call. = FALSE)
})
source(file.path(.root, "scripts", "_setup.R"))   # sf, raster, viridis, ...
stage <- match.arg(Sys.getenv("RT_QA_STAGE", "none"), c("none", "mask5", "compare", "exposure"))
message("Issue #11 check, stage: ", stage)

# Parameters ---------------------------------------------------------------------
thr_bloom  <- 1e4      # cells/L: FWC "low"; first coloured bin of the pipeline PDFs
thr_high   <- 1e5      # cells/L: FWC "medium"
class_brks <- c(-Inf, 0, 1e3, 1e4, 1e5, 1e6, Inf)   # FWC classes, right-closed (as #6 and #8)
class_lv   <- c("negative", "background", "very_low", "low", "medium", "high")
status_lv  <- c("masked", "valid_zero", "valid_pos")
scol       <- c(masked = "red", valid_zero = "black", valid_pos = "deepskyblue3")
fig1_per_page <- 8L
coast_tol_m   <- 500
expected <- list(n_ascii = 504L, use_none = c(modis = 123L, pred = 226L, viirs = 155L),
                 use_mask5 = c(hybrid = 155L, modis = 123L, pred = 226L),
                 n_viirs = 155L, n_set = 136L, km2_set = 10227, n_changed = 121L,
                 n_zeroed = 58L, n_headline = 16L, n_sel3 = 60L)

# Paths --------------------------------------------------------------------------
dir_out      <- file.path(.root, "out", "5min")
dir_sdm      <- file.path(dir_out, "sdm")
dir_clipped  <- file.path(dir_out, "clipped")
dir_ascii    <- file.path(dir_out, "ecospace_ascii")
dir_sub      <- file.path(.root, "docs", "issue5_nearshore-hybrid-summary", "subissues")
dir_docs     <- file.path(dir_sub, "issue11_nearshore-hybrid-pipeline")
dir_tab      <- file.path(dir_docs, "tables")
dir_fig      <- file.path(dir_docs, "figures")
dir_cmt      <- file.path(dir_docs, "comments")
dir_hoard    <- file.path(dir_docs, "hoard")
for (d in c(dir_tab, dir_fig, dir_cmt)) dir.create(d, recursive = TRUE, showWarnings = FALSE)
one_file <- function(dir, pattern, what) {
  f <- list.files(dir, pattern = pattern, full.names = TRUE)
  if (length(f) != 1) stop("Expected one ", what, " in ", dir, " (found ", length(f), ").", call. = FALSE)
  f
}
grd <- function(f) sub("[.]grd$", "", f)
file_depth <- one_file(file.path(.root, "template rasters"), "^depth 5min .*[.]asc$", "depth template")
file_base  <- file.path(dir_tab, "md5_baseline_issue11.csv")
file_proto <- file.path(dir_sub, "issue8_nearshore-hybrid", "tables", "hybrid_months_long_issue8.csv")
file_tab6  <- file.path(dir_sub, "issue6_VIIRS-zeros", "tables", "clip_comparison_issue6.csv")
file_coast <- file.path(.root, "data", "coastline", "ne_10m_coastline_wfs.gpkg")
for (f in c(file_base, file_proto, file_tab6, file_coast))
  if (!file.exists(f)) stop("Missing ", f, call. = FALSE)

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
zeroed   <- tab6$yrmo[tab6$flag_zeroed_fit %in% TRUE]
headline <- tab6$yrmo[tab6$zeroed_material %in% TRUE]
sel3     <- tab6$yrmo[tab6$use == "viirs" & tab6$viirs_status == "positive" & tab6$fit_status == "fitted" & tab6$n_pos_1e4_water >= 5]
viirs_pos  <- tab6$yrmo[tab6$use == "viirs" & tab6$viirs_status == "positive"]
viirs_zero <- tab6$yrmo[tab6$use == "viirs" & tab6$viirs_status == "zero"]
stopifnot(length(zeroed) == expected$n_zeroed, length(headline) == expected$n_headline, length(sel3) == expected$n_sel3)

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

# MD5 of the 504 ASCII files against the baseline, joined to clipping_source.csv.
md5_table <- function() {
  base <- read.csv(file_base, colClasses = "character")
  f <- file.path(dir_ascii, base$file)
  stopifnot(nrow(base) == expected$n_ascii, all(file.exists(f)))
  extra <- setdiff(list.files(dir_ascii, pattern = "[.]asc$"), base$file)
  if (length(extra) > 0) stop("Unexpected ASCII files: ", paste(extra, collapse = ", "), call. = FALSE)
  cs <- read.csv(file.path(dir_clipped, "clipping_source.csv"), stringsAsFactors = FALSE)
  cs$yrmo <- sub("^X", "", cs$yrmo)
  stopifnot(identical(sort(cs$yrmo), sort(base$yrmo)), all(c("hybrid", "hybrid_changed", "use") %in% names(cs)))
  m <- match(base$yrmo, cs$yrmo)
  d <- data.frame(yrmo = base$yrmo, use = cs$use[m], hybrid = cs$hybrid[m], hybrid_changed = cs$hybrid_changed[m],
                  md5_before = base$md5, md5_after = unname(tools::md5sum(f)), stringsAsFactors = FALSE)
  d$changed <- d$md5_after != d$md5_before
  d
}

# Samples of the VIIRS months on the template, as the #8 prototype counted them:
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

# Drawing helpers (the #8 panel style) -------------------------------------------
xs <- raster::xFromCol(depth, 1:nc); ys <- rev(raster::yFromRow(depth, 1:nr))
xlim <- c(-87.5, -81); ylim <- c(25, 30.5); asp <- 1 / cos(27.5 * pi / 180)
to_z   <- function(v) matrix(v, nrow = nc)[, nr:1]
colv   <- c("white", "purple", "blue", "darkblue", "cyan", "green", "darkgreen", "yellow", "orange", "red", "darkred")
funpal <- colorRampPalette(colv, bias = 2)
brks   <- c(0, 1e4 - 1, seq(1e4, 4e6, 10000), Inf); brks_img <- brks; brks_img[length(brks_img)] <- 1e12
color  <- c(funpal(length(brks) - 2), "darkred")
land_z <- to_z(ifelse(land, 1, NA))
spal   <- viridis::viridis(5, direction = -1)
coast  <- suppressWarnings(sf::st_simplify(sf::st_read(file_coast, quiet = TRUE), dTolerance = coast_tol_m))
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

# Stage none ---------------------------------------------------------------------
if (stage == "none") {
  d <- md5_table()
  write.csv(d[, c("yrmo", "use", "md5_before", "md5_after", "changed")], file.path(dir_tab, "md5_none_issue11.csv"), row.names = FALSE)
  use_counts <- table(factor(d$use, levels = names(expected$use_none)))
  cat("clipping_source.csv use:", paste(names(use_counts), as.integer(use_counts), collapse = ", "), "\n")
  cat("ASCII files changed vs the 6 Oct 2026 baseline:", sum(d$changed), "of", nrow(d), "\n")
  cat("Run log:", if (length(run_block)) paste0(length(run_block), " lines, ", run_minutes, " min") else "not found", "\n")
  cat(grep("Nearshore|Step 1|Hulls:|Run complete", run_block, value = TRUE), sep = "\n")
  stopifnot(sum(d$changed) == 0, all(as.integer(use_counts) == expected$use_none),
            !any(d$hybrid %in% TRUE), !any(d$hybrid_changed %in% TRUE),
            any(grepl("Nearshore rule: none", run_block)), any(grepl("fwc_refresh = FALSE", run_block)))
  message("Stage none OK: 0 of ", nrow(d), " ASCII files differ from the baseline; use counts unchanged.")
}

# Stage mask5 --------------------------------------------------------------------
if (stage == "mask5") {
  d <- md5_table()
  write.csv(d, file.path(dir_tab, "md5_mask5_issue11.csv"), row.names = FALSE)
  use_counts <- table(factor(d$use, levels = names(expected$use_mask5)))
  cat("clipping_source.csv use:", paste(names(use_counts), as.integer(use_counts), collapse = ", "), "\n")
  cat("ASCII files changed vs the 6 Oct 2026 baseline:", sum(d$changed), "of", nrow(d),
      "; by use:", paste(names(table(d$use[d$changed])), as.integer(table(d$use[d$changed])), collapse = ", "), "\n")
  cat("Run log:", if (length(run_block)) paste0(length(run_block), " lines, ", run_minutes, " min") else "not found", "\n")
  cat(grep("Nearshore|Hybrid:|Step 1|Run complete", run_block, value = TRUE), sep = "\n")
  stopifnot(all(as.integer(use_counts) == expected$use_mask5), all(d$hybrid == (d$use == "hybrid")),
            all(d$use[d$changed] == "hybrid"), identical(d$changed, d$hybrid_changed %in% TRUE),
            sum(d$changed) == expected$n_changed, any(grepl("Nearshore rule mask5", run_block)))

  # The set.
  mask_r <- raster::raster(file.path(dir_clipped, "nearshore_mask_mask5.grd"))
  stopifnot(raster::compareRaster(depth, mask_r))
  mv  <- raster::values(mask_r); set <- mv %in% 1
  stopifnot(all(is.na(mv) == land), sum(set) == expected$n_set, round(sum(cell_km2[set])) == expected$km2_set)
  set_tab <- data.frame(cell = which(set), lon = round(xy5[set, 1], 4), lat = round(xy5[set, 2], 4),
                        depth_m = round(dv[set], 1), km2 = round(cell_km2[set], 1))
  write.csv(set_tab, file.path(dir_tab, "nearshore_set_issue11.csv"), row.names = FALSE)
  cat("Nearshore set:", sum(set), "cells,", fmt_n(round(sum(cell_km2[set]))), "km2\n")

  # The hybrid stack against the VIIRS- and hull-clipped stacks and the prototype.
  H  <- read_mat(one_file(dir_clipped, "_clipped_hull[.]grd$", "hull-clipped stack"))
  Vc <- read_mat(one_file(dir_clipped, "_clipped_viirs[.]grd$", "VIIRS-clipped stack"))
  Hy <- read_mat(one_file(dir_clipped, "_clipped_hybrid[.]grd$", "hybrid stack"))
  months <- colnames(Hy)
  stopifnot(identical(months, colnames(Vc)), length(months) == expected$n_viirs, all(months %in% colnames(H)))
  V <- norm_map(Vc); Hm <- norm_map(H[, months])
  stopifnot(all(is.na(Hy) == land), same(Hy[!set, ], V[!set, ]), same(Hy[set, ], pmax(V[set, ], Hm[set, ])),
            all(Hy[water, ] >= V[water, ]))
  proto <- read.csv(file_proto, colClasses = c(yrmo = "character"), stringsAsFactors = FALSE)
  pm <- proto[proto$variant == "mask5", ]
  stopifnot(identical(pm$yrmo, months))
  pts <- load_samples(months); pw <- pts[pts$water, ]
  m_h <- metrics_of(Hy); s_h <- samples_of(Hy, pw, months)
  cmp <- data.frame(yrmo = months,
                    fp_km2 = round(m_h$fp_km2), fp_km2_proto = pm$fp_km2,
                    a1e4_km2 = round(m_h$a1e4_km2), a1e4_km2_proto = pm$a1e4_km2,
                    a1e5_km2 = round(m_h$a1e5_km2), a1e5_km2_proto = pm$a1e5_km2,
                    cells_changed = colSums(Hy != V, na.rm = TRUE), cells_changed_proto = pm$cells_changed,
                    added_cells = colSums(Hy > 0 & V == 0, na.rm = TRUE), added_cells_proto = pm$added_cells,
                    removed_cells = colSums(Hy == 0 & V > 0, na.rm = TRUE),
                    n_ge1e4 = s_h$n_ge1e4, n_ge1e4_proto = pm$n_ge1e4, in_ge1e4 = s_h$in_ge1e4, in_ge1e4_proto = pm$in_ge1e4,
                    n_high = s_h$n_high, n_high_proto = pm$n_high, in_high = s_h$in_high, in_high_proto = pm$in_high,
                    in_medium = s_h$in_medium, in_medium_proto = pm$in_medium, in_low = s_h$in_low, in_low_proto = pm$in_low,
                    ascii_changed = d$changed[match(months, d$yrmo)], stringsAsFactors = FALSE)
  pairs <- c("fp_km2", "a1e4_km2", "a1e5_km2", "cells_changed", "added_cells", "n_ge1e4", "in_ge1e4", "n_high", "in_high", "in_medium", "in_low")
  cmp$equal <- Reduce(`&`, lapply(pairs, function(k) cmp[[k]] == cmp[[paste0(k, "_proto")]]))
  write.csv(cmp, file.path(dir_tab, "hybrid_vs_prototype_issue11.csv"), row.names = FALSE)
  cat("Months equal to the prototype on all", length(pairs), "metrics:", sum(cmp$equal), "of", nrow(cmp), "\n")
  if (any(!cmp$equal)) print(cmp[!cmp$equal, ])
  stopifnot(all(cmp$equal), all(cmp$removed_cells == 0), identical(cmp$ascii_changed, cmp$cells_changed > 0),
            sum(cmp$cells_changed > 0) == expected$n_changed)
  cat(sprintf("Over the %d VIIRS months: bloom area >= 10,000 cells/L %s km2 (VIIRS only) -> %s km2 (hybrid); water samples >= 10,000 cells/L inside %d%% -> %d%%; high samples inside %d%% -> %d%%\n",
              length(months), fmt_n(round(sum(area_ge(V, thr_bloom)))), fmt_n(round(sum(m_h$a1e4_km2))),
              round(100 * sum(samples_of(V, pw, months)$in_ge1e4) / sum(s_h$n_ge1e4)), round(100 * sum(s_h$in_ge1e4) / sum(s_h$n_ge1e4)),
              round(100 * sum(samples_of(V, pw, months)$in_high) / sum(s_h$n_high)), round(100 * sum(s_h$in_high) / sum(s_h$n_high))))

  # Fig 1: the 16 headline months of #6: samples | before (VIIRS-clipped) | after (hybrid) | hull-clipped.
  Vraw <- raster::brick(grd(one_file(file.path(.root, "VIIRS"), "^VIIRS_[0-9]{6}-[0-9]{6}[.]grd$", "VIIRS stack")))
  Vr <- raster::values(Vraw); colnames(Vr) <- sub("^X", "", names(Vraw))
  pts$cell01 <- raster::cellFromXY(Vraw, cbind(pts$lon, pts$lat))
  li <- match(pts$yrmo, colnames(Vr)); ok <- !is.na(li) & !is.na(pts$cell01)
  fr <- rep(NA_real_, nrow(pts)); fr[ok] <- Vr[cbind(pts$cell01[ok], li[ok])]
  pts$viirs_cell <- ifelse(is.na(fr), "masked", ifelse(fr > 0, "valid_pos", "valid_zero"))
  s_v <- samples_of(V, pw, months)
  draw_samples_panel <- function(ym, main) {
    q <- pts[pts$yrmo == ym, ]
    base_panel(main); rect(xlim[1], ylim[1], xlim[2], ylim[2], col = "white", border = NA); draw_land()
    z0 <- q[q$cells == 0, ]; points(z0$lon, z0$lat, pch = ".", cex = 1.6, col = "gray45")
    pp <- q[q$cells > 0, ]; pp <- pp[order(pp$cells), ]
    bins <- cut(pp$cells, class_brks[-1], labels = FALSE, include.lowest = TRUE)
    points(pp$lon, pp$lat, pch = 21, bg = spal[bins], col = scol[pp$viirs_cell], cex = 0.75, lwd = 0.9)
    hi <- q[q$cells >= thr_bloom, ]
    info_box(c(class_lines(class_counts_v(q$cells)),
               sprintf(">= 10,000: %d masked, %d valid-0, %d valid+", sum(hi$viirs_cell == "masked"), sum(hi$viirs_cell == "valid_zero"), sum(hi$viirs_cell == "valid_pos")),
               sprintf("%d on template land", sum(!q$water))))
    box()
  }
  draw_row <- function(ym) {
    lab <- paste0(substr(ym, 1, 4), "-", substr(ym, 5, 6)); r <- tab6[tab6$yrmo == ym, ]; k <- match(ym, months)
    draw_samples_panel(ym, sprintf("%s: FWC samples (VIIRS layer %s, %d positive cells)", lab, r$viirs_status, r$viirs_n_pos_cells))
    draw_map_panel(V[, k], sprintf("before (VIIRS-clipped): %s km2", fmt_n(round(area_ge(V[, k, drop = FALSE], thr_bloom)))),
                   extra = sprintf(">= 10k samples inside: %d / %d", s_v$in_ge1e4[k], s_v$n_ge1e4[k]))
    draw_map_panel(Hy[, k], sprintf("after (hybrid mask5): %s km2 (+%s)", fmt_n(cmp$a1e4_km2[k]), fmt_n(cmp$a1e4_km2[k] - round(area_ge(V[, k, drop = FALSE], thr_bloom)))),
                   diff_from = V[, k], extra = c(sprintf("inside: %d / %d; +%d cells", cmp$in_ge1e4[k], cmp$n_ge1e4[k], cmp$added_cells[k])))
    draw_map_panel(Hm[, k], sprintf("hull-clipped: %s km2 (set shaded)", fmt_n(round(area_ge(Hm[, k, drop = FALSE], thr_bloom)))), shade = set,
                   extra = sprintf("inside: %d / %d", samples_of(Hm[, k, drop = FALSE], pw[pw$yrmo == ym, ], ym)$in_ge1e4, s_v$n_ge1e4[k]))
  }
  pages <- split(headline, ceiling(seq_along(headline) / fig1_per_page))
  draw_fig1_page <- function(i) {
    par(mfrow = c(fig1_per_page, 4), mar = c(0.4, 0.5, 1.5, 0.5), oma = c(0.3, 0, 4.4, 0))
    for (ym in pages[[i]]) draw_row(ym)
    mtext(sprintf("Issue #11: the %d headline months of #6 before and after the nearshore hybrid (page %d of %d): samples | VIIRS-clipped (the 6 Oct 2026 map) | hybrid mask5 | hull-clipped",
                  length(headline), i, length(pages)), outer = TRUE, cex = 0.9, font = 2, line = 2.9)
    mtext("km2 in the titles = bloom area >= 10,000 cells/L (+ = added by the hybrid). Orange = cells the hybrid changed. Purple shading in the hull column = the mask5 set (VIIRS no-data mask or within 5 km of the coast).",
          outer = TRUE, cex = 0.7, line = 1.6)
    mtext("Samples: fill = FWC class (viridis, light = background to dark = > 1,000,000 cells/L), border = VIIRS cell that month (red masked, black valid with no detection, blue valid with a detection). Maps: pipeline palette, white below 10,000 cells/L.",
          outer = TRUE, cex = 0.7, line = 0.5)
  }
  fig1_w <- 10; fig1_h <- 2.4 * fig1_per_page + 1.3
  file_fig1 <- file.path(dir_fig, "fig1_headline_before_after_issue11.pdf")
  ok_pdf <- write_pdf(file_fig1, width = fig1_w, height = fig1_h, function() for (i in seq_along(pages)) draw_fig1_page(i))
  if (ok_pdf) message("Fig 1 written: ", file_fig1)
  # Optional PNG preview of the pages (RT_QA_PNG_DIR=<folder>), for a quick look without a PDF viewer.
  png_dir <- Sys.getenv("RT_QA_PNG_DIR", "")
  if (nzchar(png_dir)) for (i in seq_along(pages)) {
    png(file.path(png_dir, sprintf("fig1_headline_p%d.png", i)), width = fig1_w, height = fig1_h, units = "in", res = 70)
    draw_fig1_page(i); invisible(dev.off())
  }
  message("Stage mask5 OK: ", sum(d$changed), " ASCII files changed, all hybrid months; set ", sum(set), " cells; prototype matched in every month.")
}

# Stage compare ------------------------------------------------------------------
if (stage == "compare") {
  f_before <- one_file(file.path(dir_hoard, "before", "combined"), "_clipped_combined[.]grd$", "before combined stack")
  f_after  <- one_file(file.path(dir_hoard, "after", "combined"),  "_clipped_combined[.]grd$", "after combined stack")
  Bf <- norm_map(read_mat(f_before)); Af <- norm_map(read_mat(f_after))
  stopifnot(identical(colnames(Bf), colnames(Af)), ncol(Bf) == expected$n_ascii)
  cs_after <- read.csv(file.path(dir_hoard, "after", "clipping_source.csv"), stringsAsFactors = FALSE)
  cs_after$yrmo <- sub("^X", "", cs_after$yrmo)
  months <- cs_after$yrmo[cs_after$use == "hybrid"]
  stopifnot(length(months) == expected$n_viirs, all(months %in% colnames(Bf)))
  other <- setdiff(colnames(Bf), months)
  stopifnot(same(Bf[, other], Af[, other]))        # MODIS and hull months untouched
  B <- Bf[, months]; A <- Af[, months]
  stopifnot(all(A[water, ] >= B[water, ]))
  pts <- load_samples(months); pw <- pts[pts$water, ]
  mB <- metrics_of(B); mA <- metrics_of(A); sB <- samples_of(B, pw, months); sA <- samples_of(A, pw, months)
  m6 <- match(months, tab6$yrmo)
  mon <- data.frame(yrmo = months, year = as.integer(substr(months, 1, 4)), month = as.integer(substr(months, 5, 6)),
                    viirs_status = tab6$viirs_status[m6], fit_status = tab6$fit_status[m6],
                    zeroed = months %in% zeroed, headline = months %in% headline, in_sel3 = months %in% sel3,
                    stringsAsFactors = FALSE)
  for (k in names(mB)) { mon[[paste0(k, "_before")]] <- mB[[k]]; mon[[paste0(k, "_after")]] <- mA[[k]] }
  mon$a1e4_added_km2 <- mA$a1e4_km2 - mB$a1e4_km2
  mon$a1e5_added_km2 <- mA$a1e5_km2 - mB$a1e5_km2
  mon$cells_changed  <- colSums(A != B, na.rm = TRUE)
  mon$changed <- mon$cells_changed > 0
  for (k in c("n_low", "in_low", "n_medium", "in_medium", "n_high", "in_high", "n_ge1e4", "in_ge1e4", "share_ge1e4")) {
    if (startsWith(k, "n_")) mon[[k]] <- sB[[k]] else { mon[[paste0(k, "_before")]] <- sB[[k]]; mon[[paste0(k, "_after")]] <- sA[[k]] }
  }
  write.csv(round_cols(mon), file.path(dir_tab, "months_issue11.csv"), row.names = FALSE)
  stopifnot(sum(mon$changed) == expected$n_changed)

  # Annual totals (km2-months of bloom area; samples summed; domain mean averaged over the months).
  ann <- do.call(rbind, lapply(split(mon, mon$year), function(d) data.frame(
    year = d$year[1], n_months = nrow(d), months_changed = sum(d$changed), viirs_zero_months = sum(d$viirs_status == "zero"),
    a1e4_km2_before = sum(d$a1e4_km2_before), a1e4_km2_after = sum(d$a1e4_km2_after),
    a1e5_km2_before = sum(d$a1e5_km2_before), a1e5_km2_after = sum(d$a1e5_km2_after),
    months_with_bloom_before = sum(d$a1e4_km2_before > 0), months_with_bloom_after = sum(d$a1e4_km2_after > 0),
    mean_cells_water_before = mean(d$mean_cells_water_before), mean_cells_water_after = mean(d$mean_cells_water_after),
    n_ge1e4 = sum(d$n_ge1e4), in_ge1e4_before = sum(d$in_ge1e4_before), in_ge1e4_after = sum(d$in_ge1e4_after),
    n_high = sum(d$n_high), in_high_before = sum(d$in_high_before), in_high_after = sum(d$in_high_after),
    stringsAsFactors = FALSE)))
  ann$a1e4_ratio <- ifelse(ann$a1e4_km2_before > 0, round(ann$a1e4_km2_after / ann$a1e4_km2_before, 2), NA)
  rownames(ann) <- NULL
  write.csv(round_cols(ann), file.path(dir_tab, "annual_issue11.csv"), row.names = FALSE)

  # Climatology: mean by calendar month over 2012-2024 (2022-12 has no VIIRS layer and is absent).
  clim <- do.call(rbind, lapply(split(mon, mon$month), function(d) data.frame(
    month = d$month[1], n_years = nrow(d), viirs_zero_years = sum(d$viirs_status == "zero"), years_changed = sum(d$changed),
    a1e4_km2_before = mean(d$a1e4_km2_before), a1e4_km2_after = mean(d$a1e4_km2_after),
    a1e5_km2_before = mean(d$a1e5_km2_before), a1e5_km2_after = mean(d$a1e5_km2_after),
    mean_cells_water_before = mean(d$mean_cells_water_before), mean_cells_water_after = mean(d$mean_cells_water_after),
    share_ge1e4_before = round(sum(d$in_ge1e4_before) / max(sum(d$n_ge1e4), 1), 3), share_ge1e4_after = round(sum(d$in_ge1e4_after) / max(sum(d$n_ge1e4), 1), 3),
    stringsAsFactors = FALSE)))
  rownames(clim) <- NULL
  write.csv(round_cols(clim), file.path(dir_tab, "climatology_issue11.csv"), row.names = FALSE)

  # Bloom months per cell (months at or above 10,000 cells/L over the 155 VIIRS months).
  nB <- rowSums(B >= thr_bloom, na.rm = TRUE); nA <- rowSums(A >= thr_bloom, na.rm = TRUE)
  nB[land] <- NA; nA[land] <- NA
  pc <- data.frame(cell = which(water), lon = round(xy5[water, 1], 4), lat = round(xy5[water, 2], 4), depth_m = round(dv[water], 1),
                   km2 = round(cell_km2[water], 1), n_before = nB[water], n_after = nA[water])
  pc$diff <- pc$n_after - pc$n_before
  write.csv(pc, file.path(dir_tab, "bloom_months_per_cell_issue11.csv"), row.names = FALSE)

  # Group totals.
  groups <- list(months, zeroed, headline, sel3, viirs_pos, viirs_zero)
  names(groups) <- c(sprintf("all %d VIIRS months", length(months)), sprintf("the %d zeroed months", length(zeroed)),
                     sprintf("the %d headline months", length(headline)), sprintf("the %d VIIRS-positive fitted months of #6", length(sel3)),
                     sprintf("the %d VIIRS-positive months", length(viirs_pos)), sprintf("the %d VIIRS all-zero months", length(viirs_zero)))
  grp <- do.call(rbind, lapply(names(groups), function(lab) {
    d <- mon[mon$yrmo %in% groups[[lab]], ]
    data.frame(group = lab, n_months = nrow(d), months_changed = sum(d$changed),
               a1e4_km2_before = sum(d$a1e4_km2_before), a1e4_km2_after = sum(d$a1e4_km2_after),
               a1e4_ratio = if (sum(d$a1e4_km2_before) > 0) round(sum(d$a1e4_km2_after) / sum(d$a1e4_km2_before), 2) else NA_real_,
               a1e5_km2_before = sum(d$a1e5_km2_before), a1e5_km2_after = sum(d$a1e5_km2_after),
               months_with_bloom_before = sum(d$a1e4_km2_before > 0), months_with_bloom_after = sum(d$a1e4_km2_after > 0),
               mean_cells_water_before = mean(d$mean_cells_water_before), mean_cells_water_after = mean(d$mean_cells_water_after),
               n_ge1e4 = sum(d$n_ge1e4), share_ge1e4_before = round(sum(d$in_ge1e4_before) / max(sum(d$n_ge1e4), 1), 3),
               share_ge1e4_after = round(sum(d$in_ge1e4_after) / max(sum(d$n_ge1e4), 1), 3),
               n_high = sum(d$n_high), share_high_before = round(sum(d$in_high_before) / max(sum(d$n_high), 1), 3),
               share_high_after = round(sum(d$in_high_after) / max(sum(d$n_high), 1), 3), stringsAsFactors = FALSE)
  }))
  rownames(grp) <- NULL
  write.csv(round_cols(grp), file.path(dir_tab, "groups_issue11.csv"), row.names = FALSE)

  # Fig 2: per-month series, before vs after.
  all_months <- sprintf("%d%02d", rep(2012:2024, each = 12), 1:12)
  xpos <- match(months, all_months); vz <- tab6$viirs_status[match(all_months, tab6$yrmo)]
  series <- function(v) { y <- rep(NA_real_, length(all_months)); y[xpos] <- v; y }
  png(file.path(dir_fig, "fig2_area_2012-2024_issue11.png"), width = 13, height = 11, units = "in", res = 150)
  par(mfrow = c(4, 1), mar = c(2.8, 4.4, 2.2, 0.6), oma = c(0, 0, 1.8, 0), mgp = c(2.8, 0.6, 0))
  panels <- list(list(b = mon$a1e4_km2_before, a = mon$a1e4_km2_after, lab = "km2", main = "Bloom area at or above 10,000 cells/L (km2 of water cells)"),
                 list(b = mon$a1e5_km2_before, a = mon$a1e5_km2_after, lab = "km2", main = "Bloom area at or above 100,000 cells/L"),
                 list(b = mon$mean_cells_water_before, a = mon$mean_cells_water_after, lab = "cells/L", main = "Mean concentration over all template water cells (what Ecospace reads, land excluded)"),
                 list(b = mon$share_ge1e4_before, a = mon$share_ge1e4_after, lab = "share", main = "Share of the water samples >= 10,000 cells/L inside the footprint (months with at least 5 such samples)", pts = TRUE))
  for (p in panels) {
    yb <- series(p$b); ya <- series(p$a)
    if (isTRUE(p$pts)) { few <- series(mon$n_ge1e4) < 5; yb[few] <- NA; ya[few] <- NA }
    ymax <- if (isTRUE(p$pts)) 1 else max(c(yb, ya), na.rm = TRUE) * 1.05
    plot(NA, xlim = c(0.5, length(all_months) + 0.5), ylim = c(0, ymax), xlab = "", ylab = p$lab, main = p$main, cex.main = 0.95, axes = FALSE, xaxs = "i")
    zm <- which(vz == "zero"); mm <- which(is.na(vz) | vz == "missing")
    rect(zm - 0.5, 0, zm + 0.5, ymax, col = grDevices::adjustcolor("gray40", 0.15), border = NA)
    rect(mm - 0.5, 0, mm + 0.5, ymax, col = grDevices::adjustcolor("red", 0.25), border = NA)
    if (isTRUE(p$pts)) { points(seq_along(all_months), ya, col = "purple3", pch = 1, cex = 0.8); points(seq_along(all_months), yb, col = "black", pch = 16, cex = 0.7) } else {
      lines(seq_along(all_months), ya, col = "purple3", lwd = 1.8); lines(seq_along(all_months), yb, col = "black", lwd = 1.8) }
    jan <- which(substr(all_months, 5, 6) == "01"); axis(1, at = jan, labels = substr(all_months[jan], 1, 4), cex.axis = 0.85); axis(2, las = 1, cex.axis = 0.85); box()
    if (p$main == panels[[1]]$main) legend("topleft", legend = c("before: VIIRS only (6 Oct 2026 maps)", "after: nearshore hybrid mask5", "VIIRS layer all zero", "VIIRS tif missing (2022-12)"),
                                           col = c("black", "purple3", NA, NA), lwd = c(1.8, 1.8, NA, NA), fill = c(NA, NA, grDevices::adjustcolor("gray40", 0.15), grDevices::adjustcolor("red", 0.25)),
                                           border = NA, cex = 0.8, bg = "white", box.col = "gray60", ncol = 2)
  }
  mtext("VIIRS-only vs nearshore-hybrid maps, 2012-2024, from the two pipeline runs (shaded = VIIRS layer all zero)", outer = TRUE, cex = 0.95, font = 2, line = 0.4)
  invisible(dev.off())

  # Fig 3: bloom months per cell, before, after, difference.
  png(file.path(dir_fig, "fig3_bloom_months_per_cell_issue11.png"), width = 15, height = 6.2, units = "in", res = 150)
  par(mfrow = c(1, 3), mar = c(2.5, 2.8, 2.6, 0.6), oma = c(0, 0, 2.0, 0))
  nmax <- max(c(nB, nA), na.rm = TRUE)
  cnt_col <- c("white", viridis::viridis(nmax, direction = -1))
  for (what in c("before", "after", "diff")) {
    v <- switch(what, before = nB, after = nA, diff = nA - nB)
    main <- switch(what, before = sprintf("before: months >= 10,000 cells/L per cell (max %d of %d)", max(nB, na.rm = TRUE), length(months)),
                   after = sprintf("after (hybrid): max %d of %d", max(nA, na.rm = TRUE), length(months)),
                   diff = sprintf("added by the hybrid: %d cells gain 1 to %d months", sum(v > 0, na.rm = TRUE), max(v, na.rm = TRUE)))
    base_panel(main, axes = TRUE); rect(xlim[1], ylim[1], xlim[2], ylim[2], col = "white", border = NA)
    if (what == "diff") { dmax <- max(v, na.rm = TRUE); image(xs, ys, to_z(v), breaks = seq(-0.5, dmax + 0.5, 1), col = c("white", viridis::magma(dmax, direction = -1, end = 0.9)), add = TRUE, useRaster = TRUE) } else
      image(xs, ys, to_z(v), breaks = seq(-0.5, nmax + 0.5, 1), col = cnt_col, add = TRUE, useRaster = TRUE)
    draw_land(); box()
  }
  mtext(sprintf("Bloom months per 5-arcmin cell over the %d VIIRS months: VIIRS-only maps, hybrid maps, and the months the hybrid adds", length(months)), outer = TRUE, cex = 0.95, font = 2, line = 0.5)
  invisible(dev.off())

  # Markdown summary for #11.
  g <- grp; pick <- function(lab_i, col) g[[col]][lab_i]
  md <- c("# Issue #11: VIIRS-only vs nearshore-hybrid maps (from the two pipeline runs)", "",
          sprintf("Produced by `docs/issue5_nearshore-hybrid-summary/subissues/issue11_nearshore-hybrid-pipeline/check_hybrid_issue11.R` (stage `compare`) from the combined stacks of the `none` run (the 6 October 2026 maps) and the `mask5` run. Bloom area is km2 of water cells at or above 10,000 (`a1e4`) or 100,000 cells/L (`a1e5`); `mean_cells_water` is the mean of the map over every template water cell (what Ecospace reads); samples are FWC water-cell samples whose 5-arcmin cell is non-zero in the map. MODIS and hull months are identical in the two runs (checked); the %d VIIRS months are compared.", length(months)),
          "", "## Totals by month group (`tables/groups_issue11.csv`)", "",
          md_table(grp[, c("group", "n_months", "months_changed", "a1e4_km2_before", "a1e4_km2_after", "a1e4_ratio", "a1e5_km2_before", "a1e5_km2_after",
                           "months_with_bloom_before", "months_with_bloom_after", "mean_cells_water_before", "mean_cells_water_after",
                           "n_ge1e4", "share_ge1e4_before", "share_ge1e4_after", "n_high", "share_high_before", "share_high_after")] |> round_cols(), 3),
          "", "## By year (`tables/annual_issue11.csv`; km2 summed over the months of the year)", "",
          md_table(ann[, c("year", "months_changed", "viirs_zero_months", "a1e4_km2_before", "a1e4_km2_after", "a1e4_ratio", "months_with_bloom_before", "months_with_bloom_after",
                           "mean_cells_water_before", "mean_cells_water_after", "n_ge1e4", "in_ge1e4_before", "in_ge1e4_after", "n_high", "in_high_before", "in_high_after")] |> round_cols(), 3),
          "", "## By calendar month (`tables/climatology_issue11.csv`; means over 2012-2024)", "",
          md_table(round_cols(clim), 3),
          "", sprintf("## The %d headline months (`tables/months_issue11.csv`)", length(headline)), "",
          md_table(mon[mon$headline, c("yrmo", "a1e4_km2_before", "a1e4_km2_after", "a1e5_km2_before", "a1e5_km2_after", "mean_cells_water_before", "mean_cells_water_after",
                                        "n_ge1e4", "in_ge1e4_before", "in_ge1e4_after", "n_high", "in_high_before", "in_high_after", "cells_changed")] |> round_cols(), 3),
          "", "## Bloom months per cell (`tables/bloom_months_per_cell_issue11.csv`)", "",
          sprintf("- %d water cells reach 10,000 cells/L in at least one VIIRS month before, %d after; %d cells gain months (1 to %d; median %d), none lose any.",
                  sum(nB > 0, na.rm = TRUE), sum(nA > 0, na.rm = TRUE), sum(nA > nB, na.rm = TRUE), max(nA - nB, na.rm = TRUE), as.integer(median((nA - nB)[which(nA > nB)]))),
          sprintf("- Cells with the most bloom months: before max %d, after max %d (of %d).", max(nB, na.rm = TRUE), max(nA, na.rm = TRUE), length(months)),
          "")
  writeLines(md, file.path(dir_cmt, "compare_summary.md"))
  cat(md, sep = "\n")
  message("Stage compare done.")
}

# Stage exposure -----------------------------------------------------------------
# Red tide exposure as Ecospace reads the driver: per monthly map, the plain sum of
# cells/L over the 3,838 water cells (Ecospace works per cell, so no area weighting)
# and the number of cells at or above 10,000 / 100,000 / 1,000,000 cells/L; both
# methods, all 504 months (identical outside the 155 VIIRS months).
if (stage == "exposure") {
  f_before <- one_file(file.path(dir_hoard, "before", "combined"), "_clipped_combined[.]grd$", "before combined stack")
  f_after  <- one_file(file.path(dir_hoard, "after", "combined"),  "_clipped_combined[.]grd$", "after combined stack")
  Bf <- read_mat(f_before); Af <- read_mat(f_after)
  all_yrmo <- colnames(Bf)
  # NA exactly on the land cells and a value on every water cell, in every month of both runs.
  stopifnot(identical(all_yrmo, colnames(Af)), ncol(Bf) == expected$n_ascii,
            all(is.na(Bf) == land), all(is.na(Af) == land))
  cs_after <- read.csv(file.path(dir_hoard, "after", "clipping_source.csv"), stringsAsFactors = FALSE)
  cs_after$yrmo <- sub("^X", "", cs_after$yrmo)
  m_cs <- match(all_yrmo, cs_after$yrmo); stopifnot(!anyNA(m_cs))
  use_after <- cs_after$use[m_cs]; hyb_chg <- cs_after$hybrid_changed[m_cs] %in% TRUE
  use_counts <- table(factor(use_after, levels = names(expected$use_mask5)))
  stopifnot(all(as.integer(use_counts) == expected$use_mask5), sum(hyb_chg) == expected$n_changed,
            same(Bf[, !hyb_chg], Af[, !hyb_chg]), all(Af[water, ] >= Bf[water, ]))
  n_water <- sum(water)
  thr <- c(ge1e4 = 1e4, ge1e5 = 1e5, ge1e6 = 1e6)
  expo_of <- function(M) {
    out <- data.frame(exposure = colSums(M[water, , drop = FALSE]), max_cells = apply(M, 2, max, na.rm = TRUE))
    for (k in names(thr)) {
      hit <- !is.na(M) & M >= thr[[k]]
      out[[paste0("n_", k)]] <- colSums(hit); out[[paste0("km2_", k)]] <- colSums(hit * cell_km2)
    }
    out
  }
  eB <- expo_of(Bf); eA <- expo_of(Af)
  m6 <- match(all_yrmo, tab6$yrmo); stopifnot(!anyNA(m6))
  ex <- data.frame(yrmo = all_yrmo, year = as.integer(substr(all_yrmo, 1, 4)), month = as.integer(substr(all_yrmo, 5, 6)),
                   use = use_after, hybrid_changed = hyb_chg, fit_status = tab6$fit_status[m6], viirs_status = tab6$viirs_status[m6],
                   zeroed = all_yrmo %in% zeroed, headline = all_yrmo %in% headline, in_sel3 = all_yrmo %in% sel3,
                   stringsAsFactors = FALSE)
  for (k in names(eB)) { ex[[paste0(k, "_before")]] <- eB[[k]]; ex[[paste0(k, "_after")]] <- eA[[k]] }
  ex$exposure_added <- eA$exposure - eB$exposure
  ex$exposure_ratio <- ifelse(eB$exposure > 0, eA$exposure / eB$exposure, NA_real_)
  for (k in names(thr)) ex[[paste0("n_", k, "_added")]] <- eA[[paste0("n_", k)]] - eB[[paste0("n_", k)]]
  # A changed month has a cell the hybrid raised, so its exposure rises; nothing else moves.
  stopifnot(all(ex$exposure_added >= 0), identical(ex$exposure_added > 0, hyb_chg),
            all(ex$n_ge1e4_added >= 0), all(ex$n_ge1e5_added >= 0), all(ex$n_ge1e6_added >= 0))
  # In-situ samples at or above 10,000 cells/L (and the high class, above 1,000,000) that
  # the projection includes, i.e. that sit in a non-zero cell of the month's map: the
  # converse of the samples the footprint cuts. Water-cell samples, all 504 months.
  pts <- load_samples(all_yrmo); pw <- pts[pts$water, ]
  sB <- samples_of(Bf, pw, all_yrmo); sA <- samples_of(Af, pw, all_yrmo)
  stopifnot(identical(sB$n_ge1e4, sA$n_ge1e4), all(sA$in_ge1e4 >= sB$in_ge1e4), all(sA$in_high >= sB$in_high))
  ex$samples_ge1e4 <- sB$n_ge1e4; ex$samples_ge1e4_in_before <- sB$in_ge1e4; ex$samples_ge1e4_in_after <- sA$in_ge1e4
  ex$share_samples_ge1e4_before <- sB$share_ge1e4; ex$share_samples_ge1e4_after <- sA$share_ge1e4
  ex$samples_high <- sB$n_high; ex$samples_high_in_before <- sB$in_high; ex$samples_high_in_after <- sA$in_high
  # Against the compare-stage table for the VIIRS months (same cells, thresholds and samples).
  mon <- read.csv(file.path(dir_tab, "months_issue11.csv"), colClasses = c(yrmo = "character"), stringsAsFactors = FALSE)
  mm <- match(mon$yrmo, ex$yrmo); stopifnot(!anyNA(mm), length(mm) == expected$n_viirs)
  stopifnot(all(round(ex$km2_ge1e4_before[mm]) == mon$a1e4_km2_before), all(round(ex$km2_ge1e4_after[mm]) == mon$a1e4_km2_after),
            all(round(ex$km2_ge1e5_before[mm]) == mon$a1e5_km2_before), all(round(ex$km2_ge1e5_after[mm]) == mon$a1e5_km2_after),
            all(abs(ex$exposure_before[mm] - mon$mean_cells_water_before * n_water) <= 0.05 * n_water + 1e-6),
            all(abs(ex$exposure_after[mm]  - mon$mean_cells_water_after  * n_water) <= 0.05 * n_water + 1e-6),
            all(ex$samples_ge1e4[mm] == mon$n_ge1e4), all(ex$samples_ge1e4_in_before[mm] == mon$in_ge1e4_before),
            all(ex$samples_ge1e4_in_after[mm] == mon$in_ge1e4_after))
  write.csv(round_cols(ex), file.path(dir_tab, "exposure_months_issue11.csv"), row.names = FALSE)
  cat(sprintf("Exposure (cells/L summed over %d water cells): %d months, %d changed; all months before %s, after %s (x %.3f)\n",
              n_water, nrow(ex), sum(hyb_chg), fmt_n(round(sum(ex$exposure_before))), fmt_n(round(sum(ex$exposure_after))),
              sum(ex$exposure_after) / sum(ex$exposure_before)))

  # By year (sums over the months: cell-months of cells/L and of cells above each threshold).
  sum_block <- function(d) {
    r <- data.frame(n_months = nrow(d), months_changed = sum(d$hybrid_changed),
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
  ann <- do.call(rbind, lapply(split(ex, ex$year), function(d) cbind(year = d$year[1], clip_sources = paste(sort(unique(d$use)), collapse = "/"), sum_block(d))))
  rownames(ann) <- NULL
  write.csv(round_cols(ann), file.path(dir_tab, "exposure_annual_issue11.csv"), row.names = FALSE)

  # By calendar month over the VIIRS era (means over the years; 2022-12 has no VIIRS layer and is a MODIS month).
  exv <- ex[ex$use == "hybrid", ]
  clim <- do.call(rbind, lapply(split(exv, exv$month), function(d) {
    r <- data.frame(month = d$month[1], n_years = nrow(d), viirs_zero_years = sum(d$viirs_status == "zero"), years_changed = sum(d$hybrid_changed),
                    exposure_before = mean(d$exposure_before), exposure_after = mean(d$exposure_after),
                    exposure_ratio = if (mean(d$exposure_before) > 0) mean(d$exposure_after) / mean(d$exposure_before) else NA_real_)
    for (k in names(thr)) { r[[paste0("n_", k, "_before")]] <- mean(d[[paste0("n_", k, "_before")]]); r[[paste0("n_", k, "_after")]] <- mean(d[[paste0("n_", k, "_after")]]) }
    r$samples_ge1e4 <- sum(d$samples_ge1e4)
    r$share_samples_ge1e4_before <- if (r$samples_ge1e4 > 0) round(sum(d$samples_ge1e4_in_before) / r$samples_ge1e4, 3) else NA_real_
    r$share_samples_ge1e4_after  <- if (r$samples_ge1e4 > 0) round(sum(d$samples_ge1e4_in_after)  / r$samples_ge1e4, 3) else NA_real_
    r
  }))
  rownames(clim) <- NULL
  write.csv(round_cols(clim), file.path(dir_tab, "exposure_climatology_issue11.csv"), row.names = FALSE)

  # Group totals.
  egroups <- list(all_yrmo, ex$yrmo[ex$use == "pred"], ex$yrmo[ex$use == "modis"], ex$yrmo[ex$use == "hybrid"], zeroed, headline, sel3)
  names(egroups) <- c(sprintf("all %d months 1985-2026", length(all_yrmo)), sprintf("the %d hull months", sum(ex$use == "pred")),
                      sprintf("the %d MODIS months", sum(ex$use == "modis")), sprintf("the %d VIIRS months", sum(ex$use == "hybrid")),
                      sprintf("the %d zeroed months", length(zeroed)), sprintf("the %d headline months", length(headline)),
                      sprintf("the %d VIIRS-positive fitted months of #6", length(sel3)))
  egrp <- do.call(rbind, lapply(names(egroups), function(lab) cbind(group = lab, sum_block(ex[ex$yrmo %in% egroups[[lab]], ]), stringsAsFactors = FALSE)))
  rownames(egrp) <- NULL
  write.csv(round_cols(egrp), file.path(dir_tab, "exposure_groups_issue11.csv"), row.names = FALSE)

  # Per cell over the VIIRS months: cumulative exposure and cell-months above 100,000 and 1,000,000 cells/L.
  vm <- ex$use == "hybrid"
  cum_b <- rowSums(Bf[, vm]); cum_a <- rowSums(Af[, vm])
  n5_b <- rowSums(Bf[, vm] >= 1e5); n5_a <- rowSums(Af[, vm] >= 1e5); n6_b <- rowSums(Bf[, vm] >= 1e6); n6_a <- rowSums(Af[, vm] >= 1e6)
  cells <- data.frame(cell = which(water), lon = round(xy5[water, 1], 4), lat = round(xy5[water, 2], 4), depth_m = round(dv[water], 1),
                      exposure_before = cum_b[water], exposure_after = cum_a[water], exposure_added = (cum_a - cum_b)[water],
                      cellmonths_ge1e5_before = n5_b[water], cellmonths_ge1e5_after = n5_a[water],
                      cellmonths_ge1e6_before = n6_b[water], cellmonths_ge1e6_after = n6_a[water])
  write.csv(round_cols(cells), file.path(dir_tab, "exposure_cells_issue11.csv"), row.names = FALSE)

  # Figs 4 and 5: the series, full record and VIIRS era, all panels on a linear
  # axis (exposure in millions of cells/L); the fifth panel is the share of the
  # in-situ samples >= 10,000 cells/L the projection includes.
  use_col <- c(pred = grDevices::adjustcolor("gray40", 0.12), modis = grDevices::adjustcolor("steelblue", 0.18), hybrid = grDevices::adjustcolor("gold", 0.22))
  zero_col <- grDevices::adjustcolor("gray40", 0.3); miss_col <- grDevices::adjustcolor("red", 0.25)
  min_samples_share <- 5L
  draw_series <- function(rows, title, era_shading) {
    d <- ex[rows, ]; n <- nrow(d); x <- seq_len(n)
    few <- d$samples_ge1e4 < min_samples_share
    panels <- list(list(b = d$exposure_before / 1e6, a = d$exposure_after / 1e6, lab = "million cells/L (sum over water cells)", main = "Total exposure: cells/L summed over the 3,838 water cells"),
                   list(b = d$n_ge1e4_before, a = d$n_ge1e4_after, lab = "cells", main = "Grid cells at or above 10,000 cells/L"),
                   list(b = d$n_ge1e5_before, a = d$n_ge1e5_after, lab = "cells", main = "Grid cells at or above 100,000 cells/L"),
                   list(b = d$n_ge1e6_before, a = d$n_ge1e6_after, lab = "cells", main = "Grid cells at or above 1,000,000 cells/L"),
                   list(b = replace(d$share_samples_ge1e4_before, few, NA), a = replace(d$share_samples_ge1e4_after, few, NA), lab = "share of samples",
                        main = sprintf("Share of the in-situ samples >= 10,000 cells/L (water cells) that the projection includes, months with at least %d such samples", min_samples_share), pts = TRUE))
    par(mfrow = c(length(panels), 1), mar = c(2.8, 4.6, 2.2, 0.6), oma = c(0, 0, 1.8, 0), mgp = c(3, 0.6, 0))
    for (i in seq_along(panels)) {
      p <- panels[[i]]; yb <- p$b; ya <- p$a
      yl <- if (isTRUE(p$pts)) c(0, 1.04) else c(0, max(c(yb, ya), 1) * 1.08)
      plot(NA, xlim = c(0.5, n + 0.5), ylim = yl, xlab = "", ylab = p$lab, main = p$main, cex.main = 0.95, axes = FALSE, xaxs = "i", yaxs = "i")
      if (era_shading) for (u in names(use_col)) { w <- which(d$use == u); if (length(w)) rect(w - 0.5, yl[1], w + 0.5, yl[2], col = use_col[[u]], border = NA) }
      zm <- which(d$viirs_status == "zero"); mm2 <- which(d$viirs_status == "missing")
      rect(zm - 0.5, yl[1], zm + 0.5, yl[2], col = zero_col, border = NA); rect(mm2 - 0.5, yl[1], mm2 + 0.5, yl[2], col = miss_col, border = NA)
      if (isTRUE(p$pts)) { points(x, ya, col = "purple3", pch = 1, cex = 0.8, lwd = 1.2); points(x, yb, col = "black", pch = 16, cex = 0.7) } else {
        lines(x, ya, col = "purple3", lwd = 1.8); lines(x, yb, col = "black", lwd = 1.6) }
      jan <- which(d$month == 1); axis(1, at = jan, labels = d$year[jan], cex.axis = 0.85)
      axis(2, las = 1, cex.axis = 0.85)
      box()
      if (i == 1) legend("topleft", legend = c("before: VIIRS only (6 Oct 2026 maps)", "after: nearshore hybrid mask5", if (era_shading) c("hull months", "MODIS months", "VIIRS months"), "VIIRS layer all zero", "VIIRS tif missing (2022-12)"),
                         col = c("black", "purple3", rep(NA, if (era_shading) 5 else 2)), lwd = c(1.6, 1.8, rep(NA, if (era_shading) 5 else 2)),
                         fill = c(NA, NA, if (era_shading) unname(use_col), zero_col, miss_col), border = NA, cex = 0.78, bg = "white", box.col = "gray60", ncol = 2)
      if (isTRUE(p$pts)) legend("bottomleft", legend = c("before: VIIRS only", "after: hybrid"), col = c("black", "purple3"), pch = c(16, 1), pt.cex = c(0.7, 0.8), cex = 0.78, bg = "white", box.col = "gray60", ncol = 2)
    }
    mtext(title, outer = TRUE, cex = 0.95, font = 2, line = 0.4)
  }
  png(file.path(dir_fig, "fig4_exposure_1985-2026_issue11.png"), width = 15, height = 13.5, units = "in", res = 150)
  draw_series(seq_len(nrow(ex)), "Red tide exposure per monthly map, 1985-2026, VIIRS-only vs nearshore-hybrid (identical outside the VIIRS months)", era_shading = TRUE)
  invisible(dev.off())
  png(file.path(dir_fig, "fig5_exposure_2012-2024_issue11.png"), width = 13, height = 13.5, units = "in", res = 150)
  draw_series(which(ex$year >= 2012 & ex$year <= 2024), "Red tide exposure per monthly map, 2012-2024 (the VIIRS era), VIIRS-only vs nearshore-hybrid (shaded = VIIRS layer all zero)", era_shading = FALSE)
  invisible(dev.off())

  # Fig 6: per cell over the VIIRS months: cumulative exposure (log colour) and cell-months >= 100,000 cells/L.
  png(file.path(dir_fig, "fig6_exposure_cells_issue11.png"), width = 15, height = 11.5, units = "in", res = 150)
  par(mfrow = c(2, 3), mar = c(2.5, 2.8, 2.6, 0.6), oma = c(0, 0, 2.0, 0))
  lmax <- ceiling(max(log10(c(cum_a[which(cum_a > 0)], cum_b[which(cum_b > 0)]))))
  lbrk <- seq(3, lmax, 0.5); lcol <- viridis::viridis(length(lbrk) - 1, direction = -1)
  draw_log_map <- function(v, main) {
    lv <- ifelse(!is.na(v) & v > 0, pmax(log10(v), 3), NA)
    base_panel(main, axes = TRUE); rect(xlim[1], ylim[1], xlim[2], ylim[2], col = "white", border = NA)
    image(xs, ys, to_z(lv), breaks = lbrk, col = lcol, add = TRUE, useRaster = TRUE); draw_land(); box()
    at <- seq(3, lmax, 1); legend("bottomleft", legend = sprintf("1e%d", at), fill = lcol[pmin(match(at, lbrk), length(lcol))], border = "gray40", cex = 0.75, bg = "white", box.col = "gray60", title = "cells/L, summed")
  }
  draw_log_map(cum_b, sprintf("before: cumulative exposure per cell over the %d VIIRS months (max %s)", sum(vm), fmt_n(signif(max(cum_b, na.rm = TRUE), 3))))
  draw_log_map(cum_a, sprintf("after (hybrid): max %s", fmt_n(signif(max(cum_a, na.rm = TRUE), 3))))
  draw_log_map(cum_a - cum_b, sprintf("added by the hybrid: %d cells, max %s", sum(cum_a > cum_b, na.rm = TRUE), fmt_n(signif(max(cum_a - cum_b, na.rm = TRUE), 3))))
  nmax5 <- max(c(n5_a, n5_b), na.rm = TRUE); cnt_col5 <- c("white", viridis::viridis(nmax5, direction = -1))
  draw_cnt_map <- function(v, main, vmax, cols) {
    base_panel(main, axes = TRUE); rect(xlim[1], ylim[1], xlim[2], ylim[2], col = "white", border = NA)
    image(xs, ys, to_z(v), breaks = seq(-0.5, vmax + 0.5, 1), col = cols, add = TRUE, useRaster = TRUE); draw_land(); box()
  }
  draw_cnt_map(n5_b, sprintf("before: cell-months at or above 100,000 cells/L (max %d of %d)", max(n5_b, na.rm = TRUE), sum(vm)), nmax5, cnt_col5)
  draw_cnt_map(n5_a, sprintf("after (hybrid): max %d", max(n5_a, na.rm = TRUE)), nmax5, cnt_col5)
  d5 <- n5_a - n5_b; dmax5 <- max(d5, na.rm = TRUE)
  draw_cnt_map(d5, sprintf("added by the hybrid: %d cells gain 1 to %d months", sum(d5 > 0, na.rm = TRUE), dmax5), dmax5, c("white", viridis::magma(max(dmax5, 1), direction = -1, end = 0.9)))
  mtext(sprintf("Per-cell exposure over the %d VIIRS months: cumulative cells/L (top) and months at or above 100,000 cells/L (bottom); VIIRS-only, hybrid, and the difference", sum(vm)), outer = TRUE, cex = 0.95, font = 2, line = 0.5)
  invisible(dev.off())

  # Markdown summary for #11.
  g_cols <- c("group", "n_months", "months_changed", "exposure_before", "exposure_after", "exposure_ratio", "months_ge1e4_before", "months_ge1e4_after",
              "cellmonths_ge1e4_before", "cellmonths_ge1e4_after", "cellmonths_ge1e5_before", "cellmonths_ge1e5_after", "cellmonths_ge1e6_before", "cellmonths_ge1e6_after",
              "samples_ge1e4", "share_samples_ge1e4_before", "share_samples_ge1e4_after", "samples_high", "share_samples_high_before", "share_samples_high_after")
  gain <- cells$exposure_added > 0
  overall <- function(lab) {
    g <- egrp[egrp$group == lab, ]
    sprintf("Over %s the hybrid raises total exposure by %.1f%% (%s to %s cells/L summed) and the share of the in-situ water samples >= 10,000 cells/L that the projection includes from %.1f%% to %.1f%% (%s to %s of %s; +%.1f percentage points, x %.2f); for the high samples (> 1,000,000 cells/L) from %.1f%% to %.1f%% (of %s).",
            lab, 100 * (g$exposure_ratio - 1), fmt_n(round(g$exposure_before)), fmt_n(round(g$exposure_after)),
            100 * g$share_samples_ge1e4_before, 100 * g$share_samples_ge1e4_after, fmt_n(g$samples_ge1e4_in_before), fmt_n(g$samples_ge1e4_in_after), fmt_n(g$samples_ge1e4),
            100 * (g$share_samples_ge1e4_after - g$share_samples_ge1e4_before), g$share_samples_ge1e4_after / g$share_samples_ge1e4_before,
            100 * g$share_samples_high_before, 100 * g$share_samples_high_after, fmt_n(g$samples_high))
  }
  md <- c("# Issue #11: red tide exposure per monthly map, VIIRS-only vs nearshore hybrid", "",
          sprintf("Produced by `docs/issue5_nearshore-hybrid-summary/subissues/issue11_nearshore-hybrid-pipeline/check_hybrid_issue11.R` (stage `exposure`) from the combined stacks of the `none` run (the 6 October 2026 maps) and the `mask5` run, all %d months 1985-2026. **Total exposure** of a monthly map is the plain sum of cells/L over the %d template water cells (Ecospace works per cell, so no area weighting; the water-cell count is the same in every map). **Cell counts** are the grid cells at or above 10,000, 100,000 and 1,000,000 cells/L. **Samples included** are the in-situ water-cell samples at or above 10,000 cells/L (and the high class) whose 5-arcmin cell is non-zero in the map, the converse of the samples the footprint cuts. Yearly and group totals are sums over the months (cell-months). The two methods are identical outside the %d VIIRS months (checked).",
                  nrow(ex), n_water, sum(vm)),
          "", "## Overall", "",
          paste0("- ", overall(names(egroups)[4])),
          paste0("- ", overall(names(egroups)[1])),
          "", "## Totals by month group (`tables/exposure_groups_issue11.csv`)", "",
          md_table(round_cols(egrp[, g_cols]), 3),
          "", "## By year (`tables/exposure_annual_issue11.csv`; sums over the months of the year)", "",
          md_table(round_cols(ann[, c("year", "clip_sources", g_cols[-1])]), 3),
          "", "## By calendar month over the VIIRS era (`tables/exposure_climatology_issue11.csv`; means over 2012-2024)", "",
          md_table(round_cols(clim), 3),
          "", sprintf("## The %d headline months (`tables/exposure_months_issue11.csv`)", length(headline)), "",
          md_table(round_cols(ex[ex$headline, c("yrmo", "exposure_before", "exposure_after", "n_ge1e4_before", "n_ge1e4_after", "n_ge1e5_before", "n_ge1e5_after", "n_ge1e6_before", "n_ge1e6_after", "max_cells_before", "max_cells_after",
                                                "samples_ge1e4", "samples_ge1e4_in_before", "samples_ge1e4_in_after")]), 0),
          "", "## Per cell over the VIIRS months (`tables/exposure_cells_issue11.csv`)", "",
          sprintf("- Cumulative exposure: %d of the %d water cells gain (1 to %s cells/L summed over the months, median %s); the cell maximum goes from %s to %s.",
                  sum(gain), n_water, fmt_n(signif(max(cells$exposure_added), 3)), fmt_n(signif(median(cells$exposure_added[gain]), 3)), fmt_n(signif(max(cum_b, na.rm = TRUE), 3)), fmt_n(signif(max(cum_a, na.rm = TRUE), 3))),
          sprintf("- Cell-months at or above 100,000 cells/L: %s before, %s after; %d cells gain 1 to %d months. At or above 1,000,000 cells/L: %s before, %s after; %d cells gain.",
                  fmt_n(sum(n5_b, na.rm = TRUE)), fmt_n(sum(n5_a, na.rm = TRUE)), sum(d5 > 0, na.rm = TRUE), dmax5,
                  fmt_n(sum(n6_b, na.rm = TRUE)), fmt_n(sum(n6_a, na.rm = TRUE)), sum(n6_a > n6_b, na.rm = TRUE)),
          "")
  writeLines(md, file.path(dir_cmt, "exposure_summary.md"))
  cat(md, sep = "\n")
  message("Stage exposure done.")
}
cat("\nDone:", stage, "\n")
