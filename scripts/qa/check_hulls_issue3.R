#' QA for issue #3: spurious hull polygons in fallback months.
#'
#' Compares the pre-fix fn.buffered_hulls() (k-means clustering) with the
#' working-tree version (single-linkage clustering) for the ten months
#' flagged in issue #3 plus nine control months with real blooms, at
#' link_km = 50 and 75. Also runs a synthetic stopifnot() block (two
#' well-separated clusters must give two footprints; two calls on the same
#' input must give identical polygons).
#'
#' Setup, once: save the pre-fix code from main next to this script. The
#' copy is gitignored (scripts/qa/_*).
#'
#'   git show main:scripts/polygon_clipping_rt.R > scripts/qa/_polygon_clipping_rt_main.R
#'
#' Needs a previous pipeline run (out/5min/sdm/*_filtered.Rdata).
#'
#' Run from the repo root:  Rscript scripts/qa/check_hulls_issue3.R
#'
#' Output:
#'   out/5min/plots/hull_check_issue3.pdf   one page per month: samples
#'       coloured by cells/L, old hull, new footprints at 75 and 50 km
#'   console: hull_diagnostics rows for the 19 months at both distances,
#'       every month flagged (> 300 km span) at both distances, and the
#'       stopifnot() results.

# Repo root: the working directory if it holds the .Rproj, else two levels
# above this script (scripts/qa/).
.root <- local({
  if (file.exists("RedTideMaps.Rproj")) return(normalizePath(getwd(), winslash = "/"))
  f <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE))
  if (length(f) == 1) {
    d <- normalizePath(file.path(dirname(f), "..", ".."), winslash = "/", mustWork = FALSE)
    if (file.exists(file.path(d, "RedTideMaps.Rproj"))) return(d)
  }
  stop("Run from the repo root: Rscript scripts/qa/check_hulls_issue3.R", call. = FALSE)
})
source(file.path(.root, "scripts", "_setup.R"))   # libraries (sf, raster, concaveman, maps, viridis, ...)

file_old <- file.path(.root, "scripts", "qa", "_polygon_clipping_rt_main.R")
file_new <- file.path(.root, "scripts", "polygon_clipping_rt.R")
if (!file.exists(file_old))
  stop("Pre-fix code not found. From the repo root run:\n",
       "  git show main:scripts/polygon_clipping_rt.R > scripts/qa/_polygon_clipping_rt_main.R",
       call. = FALSE)
env_old <- new.env(); sys.source(file_old, envir = env_old)
env_new <- new.env(); sys.source(file_new, envir = env_new)

dir_sdm   <- file.path(.root, "out", "5min", "sdm")
dir_plots <- file.path(.root, "out", "5min", "plots")
file_filtered <- list.files(dir_sdm, pattern = "_filtered[.]Rdata$", full.names = TRUE)
if (length(file_filtered) != 1)
  stop("Expected one *_filtered.Rdata in ", dir_sdm, "; run the pipeline first.", call. = FALSE)
file_depth <- list.files(file.path(.root, "template rasters"),
                         pattern = "^depth 5min .*[.]asc$", full.names = TRUE)[1]
load(file_filtered)   # filtered_points_df
obs <- st_transform(filtered_points_df, 4326)

flagged  <- c("199101", "199608", "199609", "199610", "199701",
              "199802", "199803", "199911", "200202", "202512")
controls <- c("199607", "199611", "199612", "200201", "200203",
              "200509", "201809", "201810", "202107")
months <- c(flagged, controls)
yr <- function(ym) as.integer(substr(ym, 1, 4))
mo <- function(ym) as.integer(substr(ym, 5, 6))

quiet <- function(expr) { invisible(capture.output(res <- expr)); res }
tmp <- file.path(tempdir(), "hull_qa"); dir.create(tmp, showWarnings = FALSE)

# New footprints at 75 and 50 km over the full modelled range (1985 on), so
# the diagnostics table covers every hull month, not just the 19 plotted.
run_new <- function(link_km, tag) {
  d <- file.path(tmp, tag); dir.create(d, showWarnings = FALSE)
  p <- quiet(env_new$fn.buffered_hulls(file_filtered, file_depth, d,
                                       styr = 1985, enyr = NULL,
                                       link_km = link_km))
  load(p)
  list(polys = pol_list,
       diag  = read.csv(file.path(d, "hull_diagnostics.csv"),
                        colClasses = c(yrmo = "character")))
}
message("Building new footprints at 75 km ...")
new75 <- run_new(75, "new75")
message("Building new footprints at 50 km ...")
new50 <- run_new(50, "new50")

# Stats for the old hulls (UTM 17N), matching the diagnostics definitions.
old_stats <- function(p) {
  if (is.null(p)) return(c(n = 0, area = 0, span = 0))
  u <- st_transform(p, 32617)
  spans <- vapply(seq_len(nrow(u)), function(i) {
    b <- st_bbox(u[i, ])
    as.numeric(sqrt((b["xmax"] - b["xmin"])^2 + (b["ymax"] - b["ymin"])^2)) / 1000
  }, numeric(1))
  c(n = nrow(u), area = sum(as.numeric(st_area(u))) / 1e6, span = max(spans))
}

# Figure -----------------------------------------------------------------
brks <- c(0, 1e3, 1e4, 1e5, 1e6, Inf)
labs <- c("<= 1,000 (background)", "1,000-10,000 (very low)", "10,000-100,000 (low)",
          "100,000-1,000,000 (medium)", "> 1,000,000 (high)")
pal  <- viridis::viridis(5, direction = -1)
xlim <- c(-87.5, -81); ylim <- c(25, 30.5)

panel <- function(pts, polys, main, fill, legend = FALSE) {
  plot(NA, xlim = xlim, ylim = ylim, xlab = "", ylab = "", asp = 1 / cos(27.5 * pi / 180),
       main = main, cex.main = 0.9, xaxs = "i", yaxs = "i")
  if (!is.null(polys))
    plot(st_geometry(polys), add = TRUE, col = adjustcolor(fill, 0.35), border = fill, lwd = 1.5)
  maps::map("state", region = "Florida", add = TRUE, fill = TRUE, col = "wheat", border = "gray40")
  bins <- cut(pts$cells, brks, labels = FALSE, include.lowest = TRUE)
  plot(st_geometry(pts), add = TRUE, pch = 21, bg = pal[bins], col = "black", cex = 0.9)
  if (legend)
    legend("bottomleft", legend = labs, pt.bg = pal, pch = 21, cex = 0.7,
           title = "cells/L", bg = "white")
}

# Other months flagged at 75 km that the hull path actually serves (no
# VIIRS before 2012-01, no MODIS before 2002-07 or after 2025-09): plotted
# after the 19 planned months so the PDF carries their inspection too.
hull_era <- function(ym) ym < "200207" | ym > "202509"
other_flagged <- setdiff(new75$diag$yrmo[new75$diag$flagged & hull_era(new75$diag$yrmo)],
                         months)
page_label <- function(ym) {
  if (ym %in% flagged) return("flagged in issue #3")
  if (ym %in% controls) return("control: real bloom")
  "flagged at 75 km in a hull-fallback month: inspect"
}
plot_months <- c(months, other_flagged)

# Old hulls: k-means is unseeded, so seed each call to make the old result
# repeatable for the figure.
message("Building old (k-means) hulls ...")
old_polys <- list()
for (y in sort(unique(yr(plot_months)))) {
  d <- file.path(tmp, paste0("old_", y)); dir.create(d, showWarnings = FALSE)
  set.seed(1)
  p <- tryCatch(quiet(env_old$fn.buffered_hulls(file_filtered, file_depth, d,
                                                styr = y, enyr = y)),
                error = function(e) { message("  old code failed for ", y, ": ",
                                              conditionMessage(e)); NULL })
  if (is.null(p)) next
  load(p)   # pol_list
  for (ym in intersect(names(pol_list), plot_months)) old_polys[[ym]] <- pol_list[[ym]]
}

file_pdf <- file.path(dir_plots, "hull_check_issue3.pdf")
pdf(file_pdf, width = 13, height = 5.2, onefile = TRUE)
for (ym in plot_months) {
  pts <- subset(obs, year == yr(ym) & month == mo(ym) & cells != 0)
  os  <- old_stats(old_polys[[ym]])
  d75 <- new75$diag[new75$diag$yrmo == ym, ]
  d50 <- new50$diag[new50$diag$yrmo == ym, ]
  par(mfrow = c(1, 3), mar = c(2.5, 2.5, 3.5, 0.5), oma = c(0, 0, 2.5, 0))
  panel(pts, old_polys[[ym]],
        sprintf("Current code (k-means, seed 1)\n%d hull(s), %s km2, max span %s km",
                os["n"], format(round(os["area"]), big.mark = ","), round(os["span"])),
        fill = "firebrick", legend = TRUE)
  panel(pts, new75$polys[[ym]],
        sprintf("New: single linkage, 75 km (default)\n%d footprint(s), %s km2, max span %s km",
                d75$n_clusters, format(round(d75$total_area_km2), big.mark = ","), round(d75$max_span_km)),
        fill = "steelblue")
  panel(pts, new50$polys[[ym]],
        sprintf("New: single linkage, 50 km (sensitivity)\n%d footprint(s), %s km2, max span %s km",
                d50$n_clusters, format(round(d50$total_area_km2), big.mark = ","), round(d50$max_span_km)),
        fill = "darkgreen")
  mtext(sprintf("%s-%s: %d positive samples at %d locations  [%s]",
                substr(ym, 1, 4), substr(ym, 5, 6), nrow(pts), d75$n_locations,
                page_label(ym)),
        outer = TRUE, cex = 1.1, font = 2)
}
dev.off()
message("PDF written: ", file_pdf)

# Console tables ---------------------------------------------------------
show_cols <- c("yrmo", "n_pos", "n_locations", "n_clusters", "cluster_sizes",
               "n_polys", "total_area_km2", "max_area_km2", "max_span_km", "flagged")
old_tab <- do.call(rbind, lapply(months, function(ym) {
  s <- old_stats(old_polys[[ym]])
  data.frame(yrmo = ym, old_n_hulls = s["n"], old_area_km2 = round(s["area"], 1),
             old_max_span_km = round(s["span"], 1), row.names = NULL)
}))
cat("\n=== Old code (k-means, seed 1): flagged months then controls ===\n")
print(old_tab, row.names = FALSE)
cat("\n=== New, link_km = 75 (default): flagged months then controls ===\n")
print(new75$diag[match(months, new75$diag$yrmo), show_cols], row.names = FALSE)
cat("\n=== New, link_km = 50 (sensitivity): flagged months then controls ===\n")
print(new50$diag[match(months, new50$diag$yrmo), show_cols], row.names = FALSE)
cat("\n=== Other hull-fallback months flagged at 75 km (also in the PDF) ===\n")
cat("    (before 2002-07 or after 2025-09, i.e. months the hull path serves)\n")
other_tab <- new75$diag[match(other_flagged, new75$diag$yrmo), show_cols]
other_tab$old_n_hulls <- other_tab$old_max_span_km <- NA_real_
for (i in seq_along(other_flagged)) {
  ym <- other_flagged[i]
  s <- tryCatch(old_stats(if (ym %in% names(old_polys)) old_polys[[ym]] else NULL),
                error = function(e) stop("old_stats failed for ", ym, ": ",
                                         conditionMessage(e), call. = FALSE))
  other_tab$old_n_hulls[i]     <- s[["n"]]
  other_tab$old_max_span_km[i] <- round(s[["span"]], 1)
}
print(other_tab, row.names = FALSE)
cat(sprintf("\nFlagged months in total: %d at 75 km, %d at 50 km (of %d months with samples);\n",
            sum(new75$diag$flagged), sum(new50$diag$flagged), nrow(new75$diag)))
cat(sprintf("  of these, hull-fallback months: %d at 75 km, %d at 50 km. The rest are VIIRS/MODIS months\n",
            sum(new75$diag$flagged & hull_era(new75$diag$yrmo)),
            sum(new50$diag$flagged & hull_era(new50$diag$yrmo))))
cat("  where the hull is not used in the combined output.\n")
cat(sprintf("\nMonths with a footprint: %d at 75 km, %d at 50 km (old code: hull only if >= 4 positives).\n",
            length(new75$polys), length(new50$polys)))

# Synthetic checks -------------------------------------------------------
cat("\n=== stopifnot() checks ===\n")
# 3 positives near Apalachicola (-85, 29.7) and 12 near Tampa Bay / Sarasota
# (-82.4, 27.0), about 330 km apart. Fixed offsets, no RNG.
syn <- rbind(
  data.frame(lon = -85.00 + c(0, -0.05, 0.05), lat = 29.70 + c(0, 0.02, -0.02)),
  expand.grid(lon = -82.4 + c(-0.2, -0.1, 0.1, 0.2), lat = 27.0 + c(-0.15, 0, 0.15)))
syn_sf <- st_as_sf(data.frame(year = 2000, month = 6, cells = 1000, syn),
                   coords = c("lon", "lat"), crs = 4326, remove = FALSE)
syn_dir <- file.path(tmp, "syn"); dir.create(syn_dir, showWarnings = FALSE)
syn_file <- file.path(syn_dir, "syn_filtered.Rdata")
filtered_points_df <- syn_sf; save(filtered_points_df, file = syn_file)

p_syn <- quiet(env_new$fn.buffered_hulls(syn_file, file_depth, syn_dir, link_km = 75))
load(p_syn)
syn_diag <- read.csv(file.path(syn_dir, "hull_diagnostics.csv"),
                     colClasses = c(yrmo = "character"))
stopifnot(
  length(pol_list) == 1,
  names(pol_list) == "200006",
  nrow(pol_list[["200006"]]) == 2,                 # two footprints
  syn_diag$n_clusters == 2,
  syn_diag$cluster_sizes == "12;3",
  syn_diag$max_span_km < 100,                      # neither spans > 100 km
  !syn_diag$flagged,
  all(st_geometry_type(pol_list[["200006"]]) == "MULTIPOLYGON"),
  st_crs(pol_list[["200006"]])$epsg == 4326
)
cat("synthetic 3 + 12 points at 75 km: 2 footprints, max span",
    syn_diag$max_span_km, "km  ... OK\n")

# For reference, what the old code does with the same input.
set.seed(1)
old_syn_dir <- file.path(tmp, "syn_old"); dir.create(old_syn_dir, showWarnings = FALSE)
p_old_syn <- tryCatch(quiet(env_old$fn.buffered_hulls(syn_file, file_depth, old_syn_dir)),
                      error = function(e) NULL)
if (!is.null(p_old_syn)) {
  load(p_old_syn)
  s <- old_stats(pol_list[["200006"]])
  cat(sprintf("  (old code on the same input: %d hull(s), max span %s km)\n",
              s["n"], round(s["span"])))
}

# Determinism: two calls on the same input give identical polygon lists.
det_a <- file.path(tmp, "det_a"); det_b <- file.path(tmp, "det_b")
dir.create(det_a, showWarnings = FALSE); dir.create(det_b, showWarnings = FALSE)
load(quiet(env_new$fn.buffered_hulls(file_filtered, file_depth, det_a, styr = 1996, enyr = 1999)))
pl_a <- pol_list
load(quiet(env_new$fn.buffered_hulls(file_filtered, file_depth, det_b, styr = 1996, enyr = 1999)))
pl_b <- pol_list
stopifnot(identical(pl_a, pl_b))
cat("determinism (1996-1999, two calls identical()):", identical(pl_a, pl_b), " ... OK\n")

# For reference, the old code without a seed.
old_a <- file.path(tmp, "old_det_a"); old_b <- file.path(tmp, "old_det_b")
dir.create(old_a, showWarnings = FALSE); dir.create(old_b, showWarnings = FALSE)
load(quiet(env_old$fn.buffered_hulls(file_filtered, file_depth, old_a, styr = 1996, enyr = 1996)))
ol_a <- pol_list
load(quiet(env_old$fn.buffered_hulls(file_filtered, file_depth, old_b, styr = 1996, enyr = 1996)))
ol_b <- pol_list
cat("  (old code, 1996, two unseeded calls identical():", identical(ol_a, ol_b), ")\n")

cat("\nAll checks passed.\n")
