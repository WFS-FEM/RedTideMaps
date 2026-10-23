#' Figure for the issue #5 summary: exposure per monthly map from the first satellite
#' month to the end of the record, the delivered 6 October 2026 maps against the
#' decided nearshore rule (the union set of #15 with the hull fill).
#'
#' Reads one tracked table and draws it; nothing is computed afresh:
#'   docs/issue15_adjacent-land-hybrid/tables/record_months_issue15.csv
#'   (columns *_v6oct and *_union_hull, written and asserted by
#'   check_adjacent_hybrid_issue15.R, stage examine).
#' Writes figures/fig1_record_2002-2026_issue5.png (byte-identical on rerun).
#'
#' Run from the repo root:
#'   Rscript docs/issue5_nearshore-hybrid-summary/plot_summary_issue5.R

.root <- local({
  if (file.exists("RedTideMaps.Rproj")) return(normalizePath(getwd(), winslash = "/"))
  f <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE))
  if (length(f) == 1) {
    d <- normalizePath(file.path(dirname(f), "..", ".."), winslash = "/", mustWork = FALSE)
    if (file.exists(file.path(d, "RedTideMaps.Rproj"))) return(d)
  }
  stop("Run from the repo root: Rscript docs/issue5_nearshore-hybrid-summary/plot_summary_issue5.R", call. = FALSE)
})
dir_docs <- file.path(.root, "docs", "issue5_nearshore-hybrid-summary")
dir_fig  <- file.path(dir_docs, "figures")
dir.create(dir_fig, showWarnings = FALSE)
file_rec <- file.path(.root, "docs", "issue15_adjacent-land-hybrid", "tables", "record_months_issue15.csv")
rec <- read.csv(file_rec, colClasses = c(yrmo = "character"), stringsAsFactors = FALSE)
stopifnot(nrow(rec) == 504, all(c("exposure_v6oct", "exposure_union_hull", "n_ge10k_union_hull", "in_ge10k_union_hull", "samples_ge10k", "use", "viirs_status") %in% names(rec)))
n_water <- 3838L
sat <- rec$use %in% c("viirs", "modis", "hybrid", "hybrid_modis")
d <- rec[rec$yrmo >= min(rec$yrmo[sat]), ]
d$era <- ifelse(d$use %in% c("viirs", "hybrid"), "VIIRS", ifelse(d$use %in% c("modis", "hybrid_modis"), "MODIS", "hull"))
fmt_n <- function(x) format(x, big.mark = ",", trim = TRUE, scientific = FALSE)

era_col  <- c(hull = grDevices::adjustcolor("gray40", 0.12), MODIS = grDevices::adjustcolor("steelblue", 0.18), VIIRS = grDevices::adjustcolor("gold", 0.22))
zero_col <- grDevices::adjustcolor("gray40", 0.3); miss_col <- grDevices::adjustcolor("red", 0.25)
keys <- c(v6oct = "6 Oct 2026 maps (satellite only)", union_hull = "nearshore hybrid, the decided set (#15) with the hull fill")
vcol <- c(v6oct = "black", union_hull = "purple3"); vpch <- c(v6oct = 16, union_hull = 1)
min_samples_share <- 5L
n <- nrow(d); x <- seq_len(n); few <- d$samples_ge10k < min_samples_share
panel_of <- function(stem, lab, main, pts = FALSE, div = 1) list(
  y = lapply(names(keys), function(k) { y <- d[[paste0(stem, "_", k)]] / div; if (pts) { y <- y / d$samples_ge10k; y[few] <- NA }; y }),
  lab = lab, main = main, pts = pts)
panels <- list(panel_of("exposure", "million cells/L (sum over water cells)", sprintf("Total exposure: cells/L summed over the %s water cells", fmt_n(n_water)), div = 1e6),
               panel_of("n_ge10k", "cells", "Grid cells at or above 10,000 cells/L"),
               panel_of("n_ge100k", "cells", "Grid cells at or above 100,000 cells/L"),
               panel_of("n_ge1M", "cells", "Grid cells at or above 1,000,000 cells/L"),
               panel_of("in_ge10k", "share of samples", sprintf("Share of the in-situ samples >= 10,000 cells/L (water cells) that the projection includes, months with at least %d such samples", min_samples_share), pts = TRUE))
file_png <- file.path(dir_fig, "fig1_record_2002-2026_issue5.png")
png(file_png, width = 15, height = 13.5, units = "in", res = 150)
par(mfrow = c(length(panels), 1), mar = c(2.8, 4.6, 2.2, 0.6), oma = c(0, 0, 1.8, 0), mgp = c(3, 0.6, 0))
for (i in seq_along(panels)) {
  p <- panels[[i]]
  yl <- if (p$pts) c(0, 1.04) else c(0, max(c(unlist(p$y), 1), na.rm = TRUE) * 1.08)
  plot(NA, xlim = c(0.5, n + 0.5), ylim = yl, xlab = "", ylab = p$lab, main = p$main, cex.main = 0.95, axes = FALSE, xaxs = "i", yaxs = "i")
  for (u in names(era_col)) { w <- which(d$era == u); if (length(w)) rect(w - 0.5, yl[1], w + 0.5, yl[2], col = era_col[[u]], border = NA) }
  zm <- which(d$viirs_status == "zero"); mm <- which(d$viirs_status == "missing")
  rect(zm - 0.5, yl[1], zm + 0.5, yl[2], col = zero_col, border = NA); rect(mm - 0.5, yl[1], mm + 0.5, yl[2], col = miss_col, border = NA)
  for (k in rev(seq_along(keys))) {
    if (p$pts) points(x, p$y[[k]], col = vcol[[k]], pch = vpch[[k]], cex = if (k == 1) 0.6 else 0.8, lwd = 1.1) else
      lines(x, p$y[[k]], col = vcol[[k]], lwd = if (k == 1) 1.4 else 1.7)
  }
  jan <- which(d$month == 1); axis(1, at = jan, labels = d$year[jan], cex.axis = 0.85)
  axis(2, las = 1, cex.axis = 0.85); box()
  if (i == 1) legend("topleft", legend = c(unname(keys), "hull months", "MODIS months", "VIIRS months", "VIIRS layer all zero", "VIIRS tif missing (2022-12)"),
                     col = c(unname(vcol), rep(NA, 5)), lwd = c(1.4, 1.7, rep(NA, 5)),
                     fill = c(NA, NA, era_col[["hull"]], era_col[["MODIS"]], era_col[["VIIRS"]], zero_col, miss_col), border = NA, cex = 0.78, bg = "white", box.col = "gray60", ncol = 2)
  if (p$pts) legend("bottomleft", legend = unname(keys), col = unname(vcol), pch = unname(vpch), pt.cex = c(0.6, 0.8), cex = 0.78, bg = "white", box.col = "gray60", ncol = 2)
}
mtext(sprintf("Red tide exposure per monthly map from the first satellite month (%s-%s) to %d: the 6 Oct 2026 maps and the nearshore hybrid with the decided set (#15, hull fill)",
              substr(d$yrmo[1], 1, 4), substr(d$yrmo[1], 5, 6), max(d$year)), outer = TRUE, cex = 0.95, font = 2, line = 0.4)
invisible(dev.off())
message("Written: ", file_png)
