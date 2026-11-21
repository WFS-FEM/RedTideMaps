# The color palettes of the red tide maps (issue #26). One definition, used by the pipeline's PDF maps
# (fn.plot_redtide_stack) and by the data bundle's style.json (fn.bundle_style, schema 1.1).
#
# A palette is a list of color stops by value (cells/L), linearly interpolated in RGB. The bins are
#   [0, eps)          exact zero: white (the lowest value in the data is above 100 cells/L; eps only
#                     separates zero from the first band)
#   [eps, 1e4)        one band 0 to 10k
#   10k steps to 4M   one color per 10k interval, at the interval's midpoint
#   [4M, Inf)         "4M+": the dark red of the top stop
# The legend (fn.draw_palette_legend) runs from 0 to 4M+ with its axis spaced by the square root of
# the value, so 10k and 100k have their own ticks and the 0 to 10k band shows; the colors of the maps
# stay linear in the value between the stops (Holden, 21 Nov 2026).
#
# rainbow: the default (Holden, 20 Nov 2026): whitish light blue to 10k, light green, yellow at 1M,
#          orange, red, dark red at 4M+ (the stops of the approved swatch).
# red:     the monochrome version: the lightest tint to 10k, through reds, to the same dark red.

redtide_palette_stops <- list(
  rainbow = list(
    value = c(0, 1e4, 2.5e5, 1e6, 2e6, 3e6, 4e6),
    color = c("#FFFFFF", "#E6F4FB", "#7BD389", "#F4E01E", "#F5961E", "#D7261E", "#8B0000")),
  red = list(
    value = c(0, 1e4, 1e6, 4e6),
    color = c("#FFFFFF", "#FDECEC", "#E8443C", "#8B0000"))
)

#' The palette by name: the breaks for image() and cut(), the colors (one per bin), the stops and the
#' top color, in one list.
#' @param name "rainbow" (default) or "red".
#' @param eps the upper edge of the exact-zero bin.
#' @return list(name, breaks, colors, stops, above): breaks has 403 values (the last is Inf), colors 402.
fn.redtide_palette <- function(name = c("rainbow", "red"), eps = 1e-9) {
  name <- match.arg(name)
  st <- redtide_palette_stops[[name]]
  brks <- c(0, eps, seq(1e4, 4e6, 1e4), Inf)
  lo <- brks[-length(brks)]
  hi <- brks[-1]
  mids <- (lo + pmin(hi, 4e6)) / 2                # the midpoint of each bin up to 4M
  mids[1] <- NA                                   # exact zero: white, set below
  mids[2] <- 1e4                                  # the 0-10k band takes the color of its top stop
  ch <- grDevices::col2rgb(st$color) / 255
  rgb_at <- function(v) {
    out <- vapply(1:3, function(k) stats::approx(st$value, ch[k, ], xout = v, rule = 2)$y, numeric(length(v)))
    toupper(grDevices::rgb(out[, 1], out[, 2], out[, 3]))
  }
  cols <- rgb_at(ifelse(is.na(mids), 0, mids))
  cols[1] <- "#FFFFFF"                            # exact zero
  cols[length(cols)] <- toupper(tail(st$color, 1)) # above 4M
  list(name = name, breaks = brks, colors = cols, stops = st, above = tail(st$color, 1))
}

#' The bundle's palette block (style.json, schema 1.1): the stops, the bins and the 402 hex colors.
fn.bundle_palette <- function(name = c("rainbow", "red")) {
  name <- match.arg(name)
  p <- fn.redtide_palette(name)
  list(type = "stops", name = name,
       stops = list(value = p$stops$value, color = toupper(p$stops$color)),
       breaks = list(zero = 0, eps = 1e-9, first_band_top = 10000, step = 10000, last = 4000000),
       above = toupper(p$above),
       colors_hex = toupper(p$colors))
}

#' The legend of the map PDFs, drawn in a region of the current page: the palette from just above
#' zero to 4M as a bar whose axis is spaced by the square root of the value (ticks at `at`), a block
#' of the top color above it ("4M+") and a separate white box for exact zero under it. The colors are
#' those of the maps; only the bar's axis is stretched, so the low values can be read.
#' The caller sets its own layout again afterwards (par(mfrow = ...)): the region is set with par(fig).
#' @param pal    a palette of fn.redtide_palette().
#' @param fig    the region in normalized device coordinates (x1, x2, y1, y2): the right outer margin of the 4 x 3 pages.
#' @param at,labels the ticks of the bar, in cells/L, and their labels in k and M.
fn.draw_palette_legend <- function(pal, fig = c(0.85, 1, 0.22, 0.80), at = c(1e4, 1e5, 1e6, 2e6, 3e6),
                                   labels = c("10k", "100k", "1M", "2M", "3M"), above = "4M+", zero = "0",
                                   title = "cells/L", cex = 1.2) {
  par(fig = fig, new = TRUE, mar = c(0, 0, 0, 0), oma = c(0, 0, 0, 0))
  plot.new()
  plot.window(xlim = c(0, 1), ylim = c(0, 1), xaxs = "i", yaxs = "i")
  n <- length(pal$colors)
  top <- pal$breaks[n]                                  # the last finite break, 4M
  x1 <- 0.10; x2 <- 0.34; xt <- 0.46
  y_zero <- c(0, 0.045); y0 <- 0.075; y1 <- 0.875; y2 <- 0.93
  rows <- 400
  v <- top * ((seq_len(rows) - 0.5) / rows)^2           # the value at each row of the bar
  cols <- pal$colors[findInterval(v, pal$breaks, left.open = TRUE)]
  rasterImage(as.raster(matrix(rev(cols), ncol = 1)), x1, y0, x2, y1, interpolate = FALSE)
  rect(x1, y1, x2, y2, col = pal$colors[n], border = NA)                 # 4M and above
  segments(x1, y1, x2, y1, col = "white", lwd = 0.6)
  rect(x1, y0, x2, y2, border = "gray30", lwd = 0.6)
  rect(x1, y_zero[1], x2, y_zero[2], col = pal$colors[1], border = "gray30", lwd = 0.6)   # exact zero
  ya <- y0 + sqrt(at / top) * (y1 - y0)
  segments(x2, ya, x2 + 0.05, ya, lwd = 0.6)
  text(xt, ya, labels, adj = 0, cex = cex)
  text(xt, (y1 + y2) / 2, above, adj = 0, cex = cex)
  text(xt, mean(y_zero), zero, adj = 0, cex = cex)
  text(x1, 0.97, title, adj = c(0, 0.5), cex = cex)
  invisible(NULL)
}
