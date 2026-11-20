# The color palettes of the red tide maps (issue #26). One definition, used by the pipeline's PDF maps
# (fn.plot_redtide_stack) and by the data bundle's style.json (fn.bundle_style, schema 1.1).
#
# A palette is a list of color stops by value (cells/L), linearly interpolated in RGB. The bins are
#   [0, eps)          exact zero: white (the lowest value in the data is above 100 cells/L; eps only
#                     separates zero from the first band)
#   [eps, 1e4)        one band 0 to 10k
#   10k steps to 4M   one color per 10k interval, at the interval's midpoint
#   [4M, Inf)         "4M+": the dark red of the top stop
# and the legend runs from 0 to 4M+ on the same linear scale.
#
# rainbow: the default (Holden, 20 Nov 2026): whitish light blue to 10k, light green, yellow at 1M,
#          orange, red, dark red at 4M+. The 250k, 2M and 3M stops are candidates (the swatch of 21 Nov).
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
