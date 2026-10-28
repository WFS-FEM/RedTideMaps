#' QA for issue #18: the final nearshore hybrid (rule "mask5adj") in the pipeline and
#' the regenerated deliverables at 5 and 15 arcmin.
#'
#' Issue #15 decided the nearshore set (the union of mask5 and the land-adjacent cells,
#' 189 cells at 5 arcmin) and prototyped the maps from the stacks on disk; #18 puts the
#' rule into the pipeline, makes it the default for both sensors and regenerates the
#' deliverables. Stages, chosen with RT_QA_STAGE (default "rule"); the resolution with
#' RT_QA_RES (5, the default, or 15). Each stage reads only what the last pipeline run
#' left on disk, the local copies under hoard/ and the tracked tables; refits nothing,
#' uses no RNG; CSVs and PNGs are byte-identical from run to run (the PDF carries the
#' two date lines every R pdf() device writes).
#'
#'   baseline after nothing: MD5 of the ASCII files on disk at the given resolution, to
#'            be run before the first run at 15 arcmin (the tracked 15-min files predate
#'            the #3 hull rule) -> tables/md5_tracked<res>_issue18.csv
#'   rule     (5 arcmin) after run A, cfg$viirs_nearshore = cfg$modis_nearshore =
#'            "mask5adj" set in config.local.R, fwc_refresh = FALSE, the defaults still
#'            "none": exactly 210 of the 504 ASCII files differ from the 6 Oct 2026
#'            baseline (all months the hybrid changed: 121 VIIRS, 89 MODIS); the set
#'            raster has the 189 cells of the #15 table; the hybrid stacks equal the
#'            satellite clip outside the set and the cell-wise maximum inside it, never
#'            below; the per-month metrics equal the union_hull prototype of #15 in all
#'            278 satellite months; the hull months equal the 6 Oct combined stack
#'            -> tables/md5_runA_issue18.csv, tables/nearshore_set5_issue18.csv,
#'               tables/hybrid_vs_prototype_issue18.csv
#'   final    after the final run at the given resolution with the defaults (no nearshore
#'            key in config.local.R, fwc_refresh = FALSE, export_ecospace = TRUE): at
#'            5 arcmin the 504 files equal run A (hoard/runA/) byte for byte; at 15 arcmin
#'            they are compared with the tracked files; the set and the hybrid relations
#'            hold at either resolution; the files in the Ecospace ST drivers folder equal
#'            ecospace_ascii/ -> tables/md5_final<res>_issue18.csv,
#'               tables/nearshore_set<res>_issue18.csv
#'   record   (5 arcmin) the whole record as Ecospace reads it, from hoard/final5/ against
#'            the 6 Oct 2026 maps (the #11 folder, hoard/before/) and the mask5 run of #10
#'            (the #10 folder, hoard/after/): exposure, cell-months at or above 10k / 100k /
#'            1M cells/L, samples >= 10k and > 1M cells/L included, per month and by group;
#'            equal to the #15 prototype month by month
#'            -> tables/record_months_issue18.csv, tables/record_groups_issue18.csv,
#'               comments/record_summary.md, figures/fig1_headline_months_issue18.pdf,
#'               figures/fig2_record_2002-2026_issue18.png
#'   refresh  after the refresh run at the given resolution (fwc_refresh = TRUE, new FWC
#'            samples): the files differ from the frozen final run (hoard/final<res>/) only
#'            in hull-served months from the first month with new samples on; the satellite
#'            months are byte-identical; the export folder equals ecospace_ascii/
#'            -> tables/md5_refresh<res>_issue18.csv, tables/refresh_months<res>_issue18.csv
#'   (run 0, both "none", is checked by the unchanged issue #11 stage `none`.)
#'
#' Run from the repo root:
#'   RT_QA_STAGE=rule    Rscript docs/issue5_nearshore-hybrid-summary/subissues/issue18_implement-hybrid-clipping/check_final_hybrid_issue18.R
#'   RT_QA_STAGE=final   RT_QA_RES=15 Rscript docs/issue5_nearshore-hybrid-summary/subissues/issue18_implement-hybrid-clipping/check_final_hybrid_issue18.R
#'   RT_QA_PNG_DIR=<folder> adds PNG previews of the fig 1 pages (stage record).

# Repo root: the working directory if it holds the .Rproj, else four levels above this script.
.root <- local({
  if (file.exists("RedTideMaps.Rproj")) return(normalizePath(getwd(), winslash = "/"))
  f <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE))
  if (length(f) == 1) {
    d <- normalizePath(file.path(dirname(f), "..", "..", "..", ".."), winslash = "/", mustWork = FALSE)
    if (file.exists(file.path(d, "RedTideMaps.Rproj"))) return(d)
  }
  stop("Run from the repo root: Rscript docs/issue5_nearshore-hybrid-summary/subissues/issue18_implement-hybrid-clipping/check_final_hybrid_issue18.R", call. = FALSE)
})
source(file.path(.root, "scripts", "_setup.R"))   # sf, raster, viridis, ...
stage <- match.arg(Sys.getenv("RT_QA_STAGE", "rule"), c("baseline", "rule", "final", "record", "refresh"))
res   <- as.integer(Sys.getenv("RT_QA_RES", "5"))
if (!res %in% c(5L, 15L)) stop("RT_QA_RES must be 5 or 15.", call. = FALSE)
if (stage %in% c("rule", "record") && res != 5L) stop("Stage ", stage, " is defined at 5 arcmin only.", call. = FALSE)
message("Issue #18 check, stage: ", stage, ", resolution: ", res, " arcmin")

# Parameters ---------------------------------------------------------------------
rule_name  <- "mask5adj"
thr        <- c(ge10k = 1e4, ge100k = 1e5, ge1M = 1e6)   # cell thresholds (inclusive), as #11, #10 and #15
thr_bloom  <- thr[["ge10k"]]
class_brks <- c(-Inf, 0, 1e3, 1e4, 1e5, 1e6, Inf)       # FWC classes, right-closed
min_samples_group <- 5L   # a month enters the sample-share groups with at least this many water samples >= 10k cells/L
fig1_per_page <- 8L
coast_tol_m   <- 500      # coastline simplified for drawing
# Frozen numbers, asserted below: the record and the set at 5 arcmin (#15, 22 Oct 2026), the
# #6 month groups, and the first runs of this issue (filled in when each stage first passed).
expected <- list(n_ascii = 504L, n_viirs = 155L, n_modis = 123L, n_hull = 226L, n_sat = 278L,
                 use_hybrid = c(hybrid = 155L, hybrid_modis = 123L, pred = 226L),
                 n_changed = 210L, n_changed_viirs = 121L, n_changed_modis = 89L,
                 n_zeroed = 58L, n_headline = 16L, n_sel3 = 60L,
                 set5  = c(n_cells = 189L, km2 = 14205, n_mask = 84L, n_coast = 132L, n_adjacent = 177L, n_water = 3838L, n_atl = 56L),
                 # the set at 15 arcmin and the months the rule changes there (the first 15-arcmin run, 23 Oct 2026)
                 set15 = c(n_cells = 53L, km2 = 35890, n_mask = 13L, n_coast = 20L, n_adjacent = 48L, n_water = 428L, n_atl = 5L,
                           n_changed = 205L, n_changed_viirs = 118L, n_changed_modis = 87L),
                 # the #15 union_hull prototype over the 278 satellite months (its examine stage), and the
                 # 6 Oct 2026 maps and the mask5 run (#10 run B) on the same months
                 proto = list(samples_ge10k = 13280L, samples_gt1M = 1610L,
                              exposure = c(v6oct = 6494237122, mask5 = 6967296294, final = 7041082852),
                              in_ge10k = c(v6oct = 8391L, mask5 = 12351L, final = 12515L),
                              in_gt1M  = c(v6oct = 1137L, mask5 = 1563L, final = 1573L),
                              months_changed   = c(v6oct = 0L, mask5 = 208L, final = 210L),
                              cellmonths_ge10k = c(v6oct = 27970L, mask5 = 29962L, final = 30474L)))

# Paths --------------------------------------------------------------------------
dir_out      <- file.path(.root, "out", paste0(res, "min"))
dir_sdm      <- file.path(dir_out, "sdm")
dir_clipped  <- file.path(dir_out, "clipped")
dir_combined <- file.path(dir_out, "combined")
dir_ascii    <- file.path(dir_out, "ecospace_ascii")
dir_sub      <- file.path(.root, "docs", "issue5_nearshore-hybrid-summary", "subissues")
dir_docs     <- file.path(dir_sub, "issue18_implement-hybrid-clipping")
dir_tab      <- file.path(dir_docs, "tables")
dir_fig      <- file.path(dir_docs, "figures")
dir_cmt      <- file.path(dir_docs, "comments")
dir_hoard    <- file.path(dir_docs, "hoard")
dir_hoard11  <- file.path(dir_sub, "issue11_nearshore-hybrid-pipeline", "hoard")
dir_hoard10  <- file.path(dir_sub, "issue10_modis-nearshore-hybrid", "hoard")
dir_tab11    <- file.path(dir_sub, "issue11_nearshore-hybrid-pipeline", "tables")
dir_tab15    <- file.path(dir_sub, "issue15_adjacent-land-hybrid", "tables")
for (d in c(dir_tab, dir_fig, dir_cmt)) dir.create(d, recursive = TRUE, showWarnings = FALSE)
one_file <- function(dir, pattern, what) {
  f <- list.files(dir, pattern = pattern, full.names = TRUE)
  if (length(f) != 1) stop("Expected one ", what, " in ", dir, " (found ", length(f), ").", call. = FALSE)
  f
}
grd <- function(f) sub("[.]grd$", "", f)
need <- function(...) for (f in c(...)) if (!file.exists(f)) stop("Missing ", f, call. = FALSE)
file_depth <- one_file(file.path(.root, "template rasters"), sprintf("^depth %dmin .*[.]asc$", res), "depth template")
file_cs    <- file.path(dir_clipped, "clipping_source.csv")
file_mask  <- file.path(dir_clipped, paste0("nearshore_mask_", rule_name, ".grd"))
file_base  <- file.path(dir_tab11, "md5_baseline_issue11.csv")
file_set15 <- file.path(dir_tab15, "nearshore_set_issue15.csv")
file_em15  <- file.path(dir_tab15, "examine_months_issue15.csv")
file_rec15 <- file.path(dir_tab15, "record_months_issue15.csv")
file_tab6  <- file.path(dir_sub, "issue6_VIIRS-zeros", "tables", "clip_comparison_issue6.csv")
file_coast <- file.path(.root, "data", "coastline", "ne_10m_coastline_wfs.gpkg")
file_local <- file.path(.root, "config.local.R")

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
row5 <- raster::rowFromCell(depth, seq_len(n5)); col5 <- raster::colFromCell(depth, seq_len(n5))
read_mat <- function(f) {
  b <- raster::brick(f)
  stopifnot(raster::compareRaster(depth, b))
  m <- raster::values(b); colnames(m) <- sub("^X", "", names(b)); m
}
norm_map <- function(M) { M[is.na(M)] <- 0; M[land, ] <- NA; M }   # as make_redtide_ascii() writes every layer
same  <- function(a, b) all((a == b) | (is.na(a) & is.na(b)))
fmt_n <- function(x) format(x, big.mark = ",", trim = TRUE, scientific = FALSE)
share <- function(num, den) ifelse(den > 0, round(num / den, 3), NA_real_)
round_cols <- function(df) {
  for (nm in grep("km2|exposure", names(df), value = TRUE))
    df[[nm]] <- round(df[[nm]], if (grepl("ratio", nm)) 3 else 0)
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
read_cs <- function(f) { cs <- read.csv(f, stringsAsFactors = FALSE); cs$yrmo <- sub("^X", "", cs$yrmo); cs[order(cs$yrmo), ] }
# MD5 of the monthly ASCII files in a folder, keyed by month. In the pipeline folders
# every .asc file must be a monthly file (strict); in the Ecospace export folder other
# .asc files may sit beside them (a sync service's conflict copies, for one), so they
# are left out and reported as the "extra" attribute.
md5_dir <- function(dir, strict = TRUE) {
  f <- sort(list.files(dir, pattern = "[.]asc$"))
  if (length(f) == 0) stop("No ASCII files in ", dir, call. = FALSE)
  ok <- grepl("^sdmTMB_log__[0-9]{6}[.]asc$", f)
  if (strict) stopifnot(all(ok))
  d <- data.frame(yrmo = substr(f[ok], 13, 18), file = f[ok], md5 = unname(tools::md5sum(file.path(dir, f[ok]))), stringsAsFactors = FALSE)
  attr(d, "extra") <- f[!ok]
  d
}
# The local overrides, as the driver reads them (the export destination lives there).
local_cfg <- local({ cfg <- list(); if (file.exists(file_local)) source(file_local, local = TRUE); cfg })
export_dir <- if (is.character(local_cfg$ecospace_root)) file.path(local_cfg$ecospace_root, paste0(res, "min"), "red tide", "sdmTMB") else NA_character_
# The run log: the block of the latest run in the newest run_<date>.log of this resolution.
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
has_log <- function(txt) any(grepl(txt, run_block, fixed = TRUE))
report_log <- function() {
  cat("Run log:", if (length(run_block)) paste0(length(run_block), " lines, ", run_minutes, " min") else "not found", "\n")
  cat(grep("Nearshore|Hybrid|Step 1|Step 8|Hulls:|Run complete", run_block, value = TRUE), sep = "\n")
}

# Samples on the template, as #8, #11, #10 and #15 counted them: water cells only, off-grid
# samples dropped; ge10k = at or above 10,000 cells/L, gt1M = above 1,000,000 cells/L.
load_samples <- function(months, dir = dir_sdm) {
  ff <- list.files(dir, pattern = "_filtered[.]Rdata$", full.names = TRUE)
  if (length(ff) == 0) stop("No *_filtered.Rdata in ", dir, call. = FALSE)
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
  pts$file  <- basename(file_filtered)
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
# Exposure per map as Ecospace reads it: the sum of cells/L over the water cells, the cells
# (and km2) at or above each threshold, the maximum.
expo_of <- function(M) {
  out <- data.frame(exposure = colSums(M[water, , drop = FALSE]))
  for (k in names(thr)) {
    hit <- !is.na(M) & M >= thr[[k]]
    out[[paste0("n_", k)]] <- colSums(hit); out[[paste0("km2_", k)]] <- colSums(hit * cell_km2)
  }
  out$max_cells <- apply(M, 2, max, na.rm = TRUE)
  out
}

# The set raster of the last run: NA exactly on land, 0 or 1 on water, nothing in the
# Atlantic box. At 5 arcmin it must be the #15 table cell for cell.
check_set <- function() {
  need(file_mask)
  m <- raster::raster(file_mask); stopifnot(raster::compareRaster(depth, m))
  mv <- raster::values(m); set <- mv %in% 1
  stopifnot(all(is.na(mv) == land), all(mv[water] %in% c(0, 1)), !any(atl[set]), all(domain[set]), sum(set) > 0)
  tab <- data.frame(cell = which(set), row = row5[set], col = col5[set], lon = round(xy5[set, 1], 4), lat = round(xy5[set, 2], 4),
                    depth_m = round(dv[set], 1), km2 = round(cell_km2[set], 1), stringsAsFactors = FALSE)
  if (res == 5L) {
    s15 <- read.csv(file_set15, stringsAsFactors = FALSE)
    stopifnot(nrow(s15) == expected$set5[["n_cells"]], setequal(tab$cell, s15$cell), sum(set) == expected$set5[["n_cells"]],
              round(sum(cell_km2[set])) == expected$set5[["km2"]], sum(water) == expected$set5[["n_water"]], sum(water & atl) == expected$set5[["n_atl"]])
    j <- match(tab$cell, s15$cell)
    tab$viirs_mask <- s15$viirs_mask[j]; tab$within5km <- s15$within5km[j]; tab$adjacent <- s15$adjacent[j]; tab$n_criteria <- s15$n_criteria[j]
    stopifnot(sum(tab$viirs_mask) == expected$set5[["n_mask"]], sum(tab$within5km) == expected$set5[["n_coast"]], sum(tab$adjacent) == expected$set5[["n_adjacent"]])
  }
  write.csv(tab, file.path(dir_tab, sprintf("nearshore_set%d_issue18.csv", res)), row.names = FALSE)
  cat(sprintf("Nearshore set %s at %d arcmin: %d cells, %s km2 of the %s water cells (%d in the Atlantic box excluded); depth median %.1f m, max %.1f m\n",
              rule_name, res, sum(set), fmt_n(round(sum(cell_km2[set]))), fmt_n(sum(water)), sum(water & atl), median(dv[set]), max(dv[set])))
  list(set = set, tab = tab)
}
# The hybrid stacks of the last run against the satellite- and hull-clipped stacks: outside
# the set the satellite clip, inside it the cell-wise maximum, never below. Returns the
# normalised satellite and hybrid matrices of the satellite months.
check_hybrids <- function(set) {
  V  <- read_mat(grd(one_file(dir_clipped, "_clipped_viirs[.]grd$", "VIIRS-clipped stack")))
  Mc <- read_mat(grd(one_file(dir_clipped, "_clipped_modis[.]grd$", "MODIS-clipped stack")))
  H  <- read_mat(grd(one_file(dir_clipped, "_clipped_hull[.]grd$", "hull-clipped stack")))
  Hv <- read_mat(grd(one_file(dir_clipped, "_clipped_hybrid[.]grd$", "VIIRS hybrid stack")))
  Hm <- read_mat(grd(one_file(dir_clipped, "_clipped_hybrid_modis[.]grd$", "MODIS hybrid stack")))
  months_v <- colnames(Hv); months_m <- colnames(Hm)
  stopifnot(identical(colnames(V), months_v), all(months_m %in% colnames(Mc)), !any(months_m %in% months_v),
            all(c(months_v, months_m) %in% colnames(H)), length(months_v) == expected$n_viirs, length(months_m) == expected$n_modis)
  Sv <- norm_map(V); Sm <- norm_map(Mc[, months_m]); Hn <- norm_map(H)
  stopifnot(all(is.na(Hv) == land), same(Hv[!set, ], Sv[!set, ]), same(Hv[set, ], pmax(Sv[set, ], Hn[set, months_v])), all(Hv[water, ] >= Sv[water, ]),
            all(is.na(Hm) == land), same(Hm[!set, ], Sm[!set, ]), same(Hm[set, ], pmax(Sm[set, ], Hn[set, months_m])), all(Hm[water, ] >= Sm[water, ]))
  months <- sort(c(months_v, months_m))
  S  <- cbind(Sv, Sm)[, months]; Hy <- cbind(Hv, Hm)[, months]
  chg <- colSums(Hy != S, na.rm = TRUE)
  cat(sprintf("Hybrid stacks: %d VIIRS months (%d changed by the rule), %d MODIS-served months (%d changed); the satellite clip outside the set, the maximum inside it, never below\n",
              length(months_v), sum(chg[months_v] > 0), length(months_m), sum(chg[months_m] > 0)))
  list(S = S, Hy = Hy, months = months, months_v = months_v, months_m = months_m, cells_changed = chg)
}
# The combined stack of the last run equals the hybrid stacks in the satellite months.
check_combined <- function(hy) {
  Cb <- read_mat(grd(one_file(dir_combined, "_clipped_combined[.]grd$", "combined stack")))
  stopifnot(ncol(Cb) == expected$n_ascii, all(is.na(Cb) == land), same(Cb[, hy$months], hy$Hy))
  Cb
}
# The ASCII files of the run against a reference MD5 table, joined to clipping_source.csv.
md5_against <- function(ref, ref_name) {
  cs  <- read_cs(file_cs)
  now <- md5_dir(dir_ascii)
  stopifnot(nrow(now) == expected$n_ascii, setequal(now$yrmo, ref$yrmo), setequal(now$yrmo, cs$yrmo),
            all(c("hybrid", "hybrid_modis", "hybrid_changed", "use") %in% names(cs)))
  m <- match(now$yrmo, cs$yrmo); j <- match(now$yrmo, ref$yrmo)
  d <- data.frame(yrmo = now$yrmo, file = now$file, use = cs$use[m], hybrid = cs$hybrid[m], hybrid_modis = cs$hybrid_modis[m],
                  hybrid_changed = cs$hybrid_changed[m], md5_now = now$md5, stringsAsFactors = FALSE)
  d[[paste0("md5_", ref_name)]] <- ref$md5[j]
  d[[paste0("changed_vs_", ref_name)]] <- d$md5_now != ref$md5[j]
  d
}
use_counts_of <- function(d) { u <- table(factor(d$use, levels = names(expected$use_hybrid))); as.integer(u) }
# The export folder holds the same 504 files as ecospace_ascii/ (MD5), when the export is on.
check_export <- function(now) {
  if (!isTRUE(local_cfg$export_ecospace)) stop("config.local.R has export_ecospace FALSE: the final runs export to the Ecospace ST drivers (decision D12).", call. = FALSE)
  if (is.na(export_dir) || !dir.exists(export_dir)) stop("Export folder not found: ", export_dir, call. = FALSE)
  ex <- md5_dir(export_dir, strict = FALSE)
  extra <- c(setdiff(ex$file, now$file), attr(ex, "extra"))
  j <- match(now$file, ex$file)
  stopifnot(!anyNA(j), all(ex$md5[j] == now$md5))
  cat(sprintf("Export: %d of %d files in %s equal ecospace_ascii/ byte for byte%s\n", sum(ex$md5[j] == now$md5), nrow(now), export_dir,
              if (length(extra)) sprintf(" (%d other file(s) there: %s)", length(extra), paste(head(extra, 5), collapse = ", ")) else ""))
  all(ex$md5[j] == now$md5)
}

# Drawing helpers (the #8 / #10 / #15 panel style) --------------------------------
if (stage == "record") {
  xs <- raster::xFromCol(depth, 1:nc); ys <- rev(raster::yFromRow(depth, 1:nr))
  xlim <- c(raster::xmin(depth), raster::xmax(depth)); ylim <- c(raster::ymin(depth), raster::ymax(depth)); asp <- 1 / cos(mean(ylim) * pi / 180)
  to_z   <- function(v) matrix(v, nrow = nc)[, nr:1]
  colv   <- c("white", "purple", "blue", "darkblue", "cyan", "green", "darkgreen", "yellow", "orange", "red", "darkred")
  funpal <- colorRampPalette(colv, bias = 2)
  brks   <- c(0, 1e4 - 1, seq(1e4, 4e6, 10000), Inf); brks_img <- brks; brks_img[length(brks_img)] <- 1e12
  color  <- c(funpal(length(brks) - 2), "darkred")
  land_z <- to_z(ifelse(land, 1, NA))
  spal   <- viridis::viridis(5, direction = -1)
  need(file_coast)
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
  png_open <- function(file_png, ...) { file_tmp <- sub("[.]png$", "_tmp.png", file_png); png(file_tmp, ...); file_tmp }
  png_done <- function(file_png) { invisible(dev.off()); file_tmp <- sub("[.]png$", "_tmp.png", file_png)
    if (file.exists(file_png) && !file.remove(file_png)) { warning("Could not replace ", file_png, " (open in a viewer?); the new file is ", file_tmp, call. = FALSE); return(invisible(FALSE)) }
    file.rename(file_tmp, file_png); invisible(TRUE) }
}

# Stage baseline -------------------------------------------------------------------
if (stage == "baseline") {
  now <- md5_dir(dir_ascii)
  stopifnot(nrow(now) == expected$n_ascii)
  f_out <- file.path(dir_tab, sprintf("md5_tracked%d_issue18.csv", res))
  write.csv(now, f_out, row.names = FALSE)
  message("Stage baseline OK: MD5 of the ", nrow(now), " ASCII files in ", dir_ascii, " written to ", basename(f_out),
          " (take it before the first run at this resolution, from the tracked files).")
}

# Stage rule -------------------------------------------------------------------------
if (stage == "rule") {
  need(file_cs, file_base, file_set15, file_em15, file_tab6)
  base <- read.csv(file_base, colClasses = "character")
  d <- md5_against(base, "6oct")
  write.csv(d, file.path(dir_tab, "md5_runA_issue18.csv"), row.names = FALSE)
  report_log()
  uc <- use_counts_of(d); chg <- d$changed_vs_6oct
  cat("clipping_source.csv use:", paste(names(expected$use_hybrid), uc, collapse = ", "), "\n")
  cat("ASCII files changed vs the 6 Oct 2026 baseline:", sum(chg), "of", nrow(d), "\n")
  stopifnot(all(uc == expected$use_hybrid), all(d$hybrid == (d$use == "hybrid")), all(d$hybrid_modis == (d$use == "hybrid_modis")),
            identical(chg, d$hybrid_changed %in% TRUE), sum(chg) == expected$n_changed,
            sum(chg & d$use == "hybrid") == expected$n_changed_viirs, sum(chg & d$use == "hybrid_modis") == expected$n_changed_modis,
            has_log(sprintf("Nearshore rule %s: %d cells, %s km2 (%d in the VIIRS no-data mask, %d within 5 km of the coast, %d adjacent to land)", rule_name,
                            expected$set5[["n_cells"]], fmt_n(expected$set5[["km2"]]), expected$set5[["n_mask"]], expected$set5[["n_coast"]], expected$set5[["n_adjacent"]])),
            has_log(sprintf("Hybrid: %d of %d VIIRS months changed", expected$n_changed_viirs, expected$n_viirs)),
            has_log(sprintf("Hybrid (MODIS): %d of %d MODIS-served months changed", expected$n_changed_modis, expected$n_modis)),
            has_log("fwc_refresh = FALSE"), has_log("Run complete."))

  st <- check_set()
  hy <- check_hybrids(st$set)
  stopifnot(identical(unname(hy$cells_changed > 0), chg[match(hy$months, d$yrmo)]), sum(hy$cells_changed > 0) == expected$n_changed)
  Cb <- check_combined(hy)
  # The hull months equal the 6 Oct 2026 combined stack (the #11 local copy).
  C0 <- read_mat(grd(one_file(file.path(dir_hoard11, "before", "combined"), "_clipped_combined[.]grd$", "6 Oct 2026 combined stack")))
  hull_months <- setdiff(colnames(Cb), hy$months)
  stopifnot(identical(colnames(C0), colnames(Cb)), length(hull_months) == expected$n_hull, same(Cb[, hull_months], C0[, hull_months]),
            same(C0[, hy$months], hy$S))
  cat(sprintf("Combined stack: the %d hull months equal the 6 Oct 2026 maps; the satellite clips of the run equal the 6 Oct maps in the %d satellite months\n",
              length(hull_months), length(hy$months)))

  # Per-month metrics against the #15 union_hull prototype (9 metrics; the prototype table
  # rounds exposure and km2 to whole numbers).
  em <- read.csv(file_em15, colClasses = c(yrmo = "character"), stringsAsFactors = FALSE)
  stopifnot(identical(em$yrmo, hy$months), identical(em$use, ifelse(hy$months %in% hy$months_v, "viirs", "modis")))
  e <- expo_of(hy$Hy)
  pts <- load_samples(hy$months); pw <- pts[pts$water, ]
  s <- samples_of(hy$Hy, pw, hy$months)
  stopifnot(all(s$samples_ge10k == em$samples_ge10k), all(s$samples_gt1M == em$samples_gt1M))
  cmp <- data.frame(yrmo = hy$months, use = em$use,
                    exposure = round(e$exposure), exposure_proto = em$exposure_union_hull,
                    n_ge10k = e$n_ge10k, n_ge10k_proto = em$n_ge10k_union_hull,
                    km2_ge10k = round(e$km2_ge10k), km2_ge10k_proto = em$km2_ge10k_union_hull,
                    n_ge100k = e$n_ge100k, n_ge100k_proto = em$n_ge100k_union_hull,
                    n_ge1M = e$n_ge1M, n_ge1M_proto = em$n_ge1M_union_hull,
                    max_cells = signif(e$max_cells, 10), max_cells_proto = signif(em$max_cells_union_hull, 10),
                    cells_changed = unname(hy$cells_changed), cells_changed_proto = em$cells_changed_union_hull,
                    in_ge10k = s$in_ge10k, in_ge10k_proto = em$in_ge10k_union_hull,
                    in_gt1M = s$in_gt1M, in_gt1M_proto = em$in_gt1M_union_hull,
                    samples_ge10k = s$samples_ge10k, samples_gt1M = s$samples_gt1M,
                    removed_cells = colSums(hy$Hy == 0 & hy$S > 0, na.rm = TRUE),
                    ascii_changed = chg[match(hy$months, d$yrmo)], stringsAsFactors = FALSE)
  pairs <- c("exposure", "n_ge10k", "km2_ge10k", "n_ge100k", "n_ge1M", "max_cells", "cells_changed", "in_ge10k", "in_gt1M")
  cmp$equal <- Reduce(`&`, lapply(pairs, function(k) { tol <- if (k == "exposure") 1 else 0; abs(cmp[[k]] - cmp[[paste0(k, "_proto")]]) <= tol }))
  write.csv(cmp, file.path(dir_tab, "hybrid_vs_prototype_issue18.csv"), row.names = FALSE)
  cat("Months equal to the #15 prototype on all", length(pairs), "metrics:", sum(cmp$equal), "of", nrow(cmp), "\n")
  if (any(!cmp$equal)) print(cmp[!cmp$equal, ])
  tot <- list(exposure = sum(cmp$exposure), in_ge10k = sum(cmp$in_ge10k), in_gt1M = sum(cmp$in_gt1M), cellmonths_ge10k = sum(cmp$n_ge10k), months_changed = sum(cmp$cells_changed > 0))
  stopifnot(all(cmp$equal), all(cmp$removed_cells == 0), identical(cmp$ascii_changed, cmp$cells_changed > 0),
            abs(tot$exposure - expected$proto$exposure[["final"]]) <= 1, tot$in_ge10k == expected$proto$in_ge10k[["final"]],
            tot$in_gt1M == expected$proto$in_gt1M[["final"]], tot$cellmonths_ge10k == expected$proto$cellmonths_ge10k[["final"]],
            tot$months_changed == expected$proto$months_changed[["final"]],
            sum(cmp$samples_ge10k) == expected$proto$samples_ge10k, sum(cmp$samples_gt1M) == expected$proto$samples_gt1M)
  cat(sprintf("Satellite months (%d): exposure %s, cell-months >= 10k %s, samples >= 10k included %s of %s (%.1f%%), > 1M %s of %s (%.1f%%), months changed %d: the #15 union_hull prototype\n",
              nrow(cmp), fmt_n(tot$exposure), fmt_n(tot$cellmonths_ge10k), fmt_n(tot$in_ge10k), fmt_n(sum(cmp$samples_ge10k)), 100 * tot$in_ge10k / sum(cmp$samples_ge10k),
              fmt_n(tot$in_gt1M), fmt_n(sum(cmp$samples_gt1M)), 100 * tot$in_gt1M / sum(cmp$samples_gt1M), tot$months_changed))
  message("Stage rule OK: ", sum(chg), " of ", nrow(d), " ASCII files changed against the 6 Oct 2026 maps, all months the hybrid changed (",
          expected$n_changed_viirs, " VIIRS, ", expected$n_changed_modis, " MODIS); set ", sum(st$set), " cells = the #15 table; the hybrid equals the prototype in every satellite month; hull months untouched.")
}

# Stage final ------------------------------------------------------------------------
if (stage == "final") {
  need(file_cs)
  if (res == 5L) {
    need(file_base)
    ref <- md5_dir(file.path(dir_hoard, "runA", "ecospace_ascii")); ref_name <- "runA"
  } else {
    f_tracked <- file.path(dir_tab, sprintf("md5_tracked%d_issue18.csv", res)); need(f_tracked)
    ref <- read.csv(f_tracked, colClasses = "character"); ref_name <- "tracked"
  }
  d <- md5_against(ref, ref_name)
  if (res == 5L) {
    base <- read.csv(file_base, colClasses = "character"); j <- match(d$yrmo, base$yrmo)
    d$md5_6oct <- base$md5[j]; d$changed_vs_6oct <- d$md5_now != d$md5_6oct
  }
  d$exported_equal <- check_export(data.frame(yrmo = d$yrmo, file = d$file, md5 = d$md5_now, stringsAsFactors = FALSE))
  write.csv(d, file.path(dir_tab, sprintf("md5_final%d_issue18.csv", res)), row.names = FALSE)
  report_log()
  uc <- use_counts_of(d); chg <- d[[paste0("changed_vs_", ref_name)]]
  cat("clipping_source.csv use:", paste(names(expected$use_hybrid), uc, collapse = ", "), "\n")
  cat(sprintf("ASCII files changed vs %s: %d of %d%s\n", ref_name, sum(chg), nrow(d),
              if (res == 5L) sprintf("; vs the 6 Oct 2026 baseline: %d", sum(d$changed_vs_6oct)) else ""))
  stopifnot(all(uc == expected$use_hybrid), all(d$hybrid == (d$use == "hybrid")), all(d$hybrid_modis == (d$use == "hybrid_modis")),
            has_log(paste0("Nearshore rule ", rule_name, ":")), has_log("Hybrid:"), has_log("Hybrid (MODIS):"),
            has_log("fwc_refresh = FALSE"), has_log("Step 8: export"), has_log("Run complete."), all(d$exported_equal))
  if (res == 5L) stopifnot(sum(chg) == 0, sum(d$changed_vs_6oct) == expected$n_changed, identical(d$changed_vs_6oct, d$hybrid_changed %in% TRUE))
  st <- check_set()
  hy <- check_hybrids(st$set)
  stopifnot(identical(unname(hy$cells_changed > 0), d$hybrid_changed[match(hy$months, d$yrmo)] %in% TRUE))
  invisible(check_combined(hy))
  if (res == 5L) stopifnot(sum(hy$cells_changed > 0) == expected$n_changed)
  if (!is.null(expected$set15) && res == 15L) {
    e15 <- expected$set15
    stopifnot(sum(st$set) == e15[["n_cells"]], round(sum(cell_km2[st$set])) == e15[["km2"]], sum(water) == e15[["n_water"]], sum(water & atl) == e15[["n_atl"]],
              sum(hy$cells_changed > 0) == e15[["n_changed"]], sum(hy$cells_changed[hy$months_v] > 0) == e15[["n_changed_viirs"]],
              sum(hy$cells_changed[hy$months_m] > 0) == e15[["n_changed_modis"]],
              has_log(sprintf("Nearshore rule %s: %d cells, %s km2 (%d in the VIIRS no-data mask, %d within 5 km of the coast, %d adjacent to land)", rule_name,
                              e15[["n_cells"]], fmt_n(e15[["km2"]]), e15[["n_mask"]], e15[["n_coast"]], e15[["n_adjacent"]])),
              identical(d$changed_vs_tracked, d$changed_vs_tracked))
  }
  cat(sprintf("Months changed by the rule at %d arcmin: %d (%d VIIRS, %d MODIS)\n", res, sum(hy$cells_changed > 0),
              sum(hy$cells_changed[hy$months_v] > 0), sum(hy$cells_changed[hy$months_m] > 0)))
  message("Stage final OK at ", res, " arcmin: ", if (res == 5L) "0 of 504 ASCII files differ from run A; " else sprintf("%d of %d ASCII files differ from the tracked (22 May 2026) files; ", sum(chg), nrow(d)),
          "set ", sum(st$set), " cells; the hybrid relations hold; the export folder equals ecospace_ascii/.")
}

# Stage record -----------------------------------------------------------------------
if (stage == "record") {
  need(file_tab6, file_rec15, file_em15)
  f_final <- one_file(file.path(dir_hoard, "final5", "combined"),   "_clipped_combined[.]grd$", "final combined stack (hoard/final5)")
  f_6oct  <- one_file(file.path(dir_hoard11, "before", "combined"), "_clipped_combined[.]grd$", "6 Oct 2026 combined stack")
  f_m5    <- one_file(file.path(dir_hoard10, "after", "combined"),  "_clipped_combined[.]grd$", "mask5 run B combined stack")
  cs <- read_cs(file.path(dir_hoard, "final5", "clipping_source.csv"))
  Mf <- read_mat(grd(f_final)); M0 <- read_mat(grd(f_6oct)); M5 <- read_mat(grd(f_m5))
  all_yrmo <- colnames(M0)
  stopifnot(identical(colnames(Mf), all_yrmo), identical(colnames(M5), all_yrmo), identical(cs$yrmo, all_yrmo), length(all_yrmo) == expected$n_ascii,
            all(is.na(Mf) == land), all(is.na(M0) == land), all(is.na(M5) == land), all(Mf[water, ] >= M0[water, ]), all(Mf[water, ] >= M5[water, ]))
  use_all <- cs$use; is_sat <- use_all %in% c("hybrid", "hybrid_modis")
  months <- all_yrmo[is_sat]; months_v <- all_yrmo[use_all == "hybrid"]; months_m <- all_yrmo[use_all == "hybrid_modis"]
  stopifnot(length(months) == expected$n_sat, same(Mf[, !is_sat], M0[, !is_sat]), same(M5[, !is_sat], M0[, !is_sat]))
  tab6 <- read.csv(file_tab6, colClasses = c(yrmo = "character"), stringsAsFactors = FALSE)
  zeroed <- tab6$yrmo[tab6$flag_zeroed_fit %in% TRUE]; headline <- tab6$yrmo[tab6$zeroed_material %in% TRUE]
  sel3 <- tab6$yrmo[tab6$use == "viirs" & tab6$viirs_status == "positive" & tab6$fit_status == "fitted" & tab6$n_pos_1e4_water >= 5]
  stopifnot(length(zeroed) == expected$n_zeroed, length(headline) == expected$n_headline, length(sel3) == expected$n_sel3)
  Ms <- list(v6oct = M0, mask5 = M5, final = Mf); keys <- names(Ms)
  variants <- c(v6oct = "6 Oct 2026 maps (satellite only)", mask5 = "mask5 hybrid, both sensors (#11, #10)", final = "the delivered maps: mask5adj hybrid, both sensors (#18)")

  pts <- load_samples(all_yrmo, dir = file.path(dir_hoard, "final5", "sdm")); pw <- pts[pts$water, ]
  per <- lapply(Ms, function(M) cbind(expo_of(M), samples_of(M, pw, all_yrmo)[, -1], cells_changed = colSums(M != M0, na.rm = TRUE)))
  m6 <- match(all_yrmo, tab6$yrmo); stopifnot(!anyNA(m6), all(per$v6oct$samples_ge10k[is_sat] == tab6$n_pos_1e4_water[m6][is_sat]))
  rec <- data.frame(yrmo = all_yrmo, year = as.integer(substr(all_yrmo, 1, 4)), month = as.integer(substr(all_yrmo, 5, 6)), use = use_all,
                    fit_status = tab6$fit_status[m6], viirs_status = tab6$viirs_status[m6],
                    zeroed = all_yrmo %in% zeroed, headline = all_yrmo %in% headline, viirs_pos_fitted = all_yrmo %in% sel3,
                    samples_ge10k = per$v6oct$samples_ge10k, samples_gt1M = per$v6oct$samples_gt1M, stringsAsFactors = FALSE)
  rec$ge5 <- rec$samples_ge10k >= min_samples_group
  metrics <- c("exposure", "n_ge10k", "km2_ge10k", "n_ge100k", "n_ge1M", "max_cells", "cells_changed", "in_ge10k", "in_gt1M")
  for (k in keys) { for (mt in metrics) rec[[paste0(mt, "_", k)]] <- per[[k]][[mt]]; rec[[paste0("share_ge10k_", k)]] <- share(per[[k]]$in_ge10k, rec$samples_ge10k) }
  # Month by month, the three variants equal the #15 record table (v6oct, mask5, union_hull).
  r15 <- read.csv(file_rec15, colClasses = c(yrmo = "character"), stringsAsFactors = FALSE); stopifnot(identical(r15$yrmo, all_yrmo))
  for (k in keys) {
    k15 <- c(v6oct = "v6oct", mask5 = "mask5", final = "union_hull")[[k]]
    stopifnot(all(abs(rec[[paste0("exposure_", k)]] - r15[[paste0("exposure_", k15)]]) <= 1),
              all(rec[[paste0("n_ge10k_", k)]] == r15[[paste0("n_ge10k_", k15)]]), all(rec[[paste0("n_ge100k_", k)]] == r15[[paste0("n_ge100k_", k15)]]),
              all(rec[[paste0("n_ge1M_", k)]] == r15[[paste0("n_ge1M_", k15)]]), all(rec[[paste0("in_ge10k_", k)]] == r15[[paste0("in_ge10k_", k15)]]),
              all(rec[[paste0("in_gt1M_", k)]] == r15[[paste0("in_gt1M_", k15)]]), all(rec$samples_ge10k == r15$samples_ge10k), all(rec$samples_gt1M == r15$samples_gt1M))
  }
  cat("Per month, the 6 Oct maps, the mask5 run and the delivered maps equal the #15 record table (v6oct, mask5, union_hull) in all", nrow(rec), "months\n")
  write.csv(round_cols(rec), file.path(dir_tab, "record_months_issue18.csv"), row.names = FALSE)

  sum_block <- function(d) {
    r <- data.frame(n_months = nrow(d))
    for (k in keys) {
      r[[paste0("months_changed_", k)]] <- sum(d[[paste0("cells_changed_", k)]] > 0)
      r[[paste0("months_ge10k_", k)]]   <- sum(d[[paste0("n_ge10k_", k)]] > 0)
      r[[paste0("exposure_", k)]]       <- sum(d[[paste0("exposure_", k)]])
      for (t in names(thr)) r[[paste0("cellmonths_", t, "_", k)]] <- sum(d[[paste0("n_", t, "_", k)]])
      r[[paste0("km2_ge10k_", k)]] <- sum(d[[paste0("km2_ge10k_", k)]])
    }
    r$samples_ge10k <- sum(d$samples_ge10k); r$samples_gt1M <- sum(d$samples_gt1M)
    for (k in keys) { r[[paste0("in_ge10k_", k)]] <- sum(d[[paste0("in_ge10k_", k)]]); r[[paste0("share_ge10k_", k)]] <- share(r[[paste0("in_ge10k_", k)]], r$samples_ge10k) }
    for (k in keys) { r[[paste0("in_gt1M_", k)]] <- sum(d[[paste0("in_gt1M_", k)]]); r[[paste0("share_gt1M_", k)]] <- share(r[[paste0("in_gt1M_", k)]], r$samples_gt1M) }
    for (k in keys[-1]) r[[paste0("exposure_ratio_", k)]] <- share(r[[paste0("exposure_", k)]], r$exposure_v6oct)
    r$exposure_ratio_final_vs_mask5 <- share(r$exposure_final, r$exposure_mask5)
    r
  }
  groups <- list(all_yrmo, all_yrmo[!is_sat], months, months_v, months_m, all_yrmo[rec$zeroed], all_yrmo[rec$headline], all_yrmo[rec$viirs_pos_fitted], all_yrmo[rec$ge5])
  names(groups) <- c(sprintf("all %d months 1985-2026", length(all_yrmo)), sprintf("the %d hull months", sum(!is_sat)), sprintf("the %d satellite months", length(months)),
                     sprintf("the %d VIIRS months", length(months_v)), sprintf("the %d MODIS months", length(months_m)),
                     sprintf("the %d zeroed VIIRS months of #6", sum(rec$zeroed)), sprintf("the %d headline months of #6", sum(rec$headline)),
                     sprintf("the %d VIIRS-positive fitted months of #6", sum(rec$viirs_pos_fitted)),
                     sprintf("the %d months with at least %d water samples >= 10k cells/L", sum(rec$ge5), min_samples_group))
  grp <- do.call(rbind, lapply(names(groups), function(lab) cbind(group = lab, sum_block(rec[rec$yrmo %in% groups[[lab]], ]), stringsAsFactors = FALSE)))
  rownames(grp) <- NULL
  write.csv(round_cols(grp), file.path(dir_tab, "record_groups_issue18.csv"), row.names = FALSE)
  ann <- do.call(rbind, lapply(split(rec, rec$year), function(d) cbind(year = d$year[1], clip_sources = paste(sort(unique(d$use)), collapse = "/"), sum_block(d))))
  rownames(ann) <- NULL
  write.csv(round_cols(ann), file.path(dir_tab, "record_annual_issue18.csv"), row.names = FALSE)
  g <- grp[3, ]   # the satellite months: the #15 prototype totals
  stopifnot(g$samples_ge10k == expected$proto$samples_ge10k, g$samples_gt1M == expected$proto$samples_gt1M,
            all(sapply(keys, function(k) abs(g[[paste0("exposure_", k)]] - expected$proto$exposure[[k]]) <= 1 && g[[paste0("in_ge10k_", k)]] == expected$proto$in_ge10k[[k]] &&
                                     g[[paste0("in_gt1M_", k)]] == expected$proto$in_gt1M[[k]] && g[[paste0("months_changed_", k)]] == expected$proto$months_changed[[k]] &&
                                     g[[paste0("cellmonths_ge10k_", k)]] == expected$proto$cellmonths_ge10k[[k]])),
            grp$months_changed_final[2] == 0, grp$months_changed_mask5[2] == 0)
  for (i in c(1, 3, 4, 5, 6, 7)) {
    gg <- grp[i, ]; cat(gg$group, "\n")
    for (k in keys) cat(sprintf("  %-6s exposure %s (x %.3f vs 6 Oct), cell-months >= 10k %s / >= 100k %s / >= 1M %s, samples >= 10k included %s of %s (%.1f%%), > 1M %s of %s (%.1f%%), months changed %d\n",
                                k, fmt_n(round(gg[[paste0("exposure_", k)]])), gg[[paste0("exposure_", k)]] / gg$exposure_v6oct,
                                fmt_n(gg[[paste0("cellmonths_ge10k_", k)]]), fmt_n(gg[[paste0("cellmonths_ge100k_", k)]]), fmt_n(gg[[paste0("cellmonths_ge1M_", k)]]),
                                fmt_n(gg[[paste0("in_ge10k_", k)]]), fmt_n(gg$samples_ge10k), 100 * gg[[paste0("share_ge10k_", k)]],
                                fmt_n(gg[[paste0("in_gt1M_", k)]]), fmt_n(gg$samples_gt1M), 100 * gg[[paste0("share_gt1M_", k)]], gg[[paste0("months_changed_", k)]]))
  }

  # Fig 1: the 16 headline months of #6, one row each: samples | the 6 Oct map | the delivered map.
  pts$in_6oct <- FALSE; pts$in_6oct[pts$water] <- M0[cbind(pw$cell5, match(pw$yrmo, all_yrmo))] > 0
  set_tab <- read.csv(file.path(dir_tab, "nearshore_set5_issue18.csv"), stringsAsFactors = FALSE)
  set <- rep(FALSE, n5); set[set_tab$cell] <- TRUE
  draw_samples_panel <- function(ym, main) {
    q <- pts[pts$yrmo == ym, ]
    base_panel(main); rect(xlim[1], ylim[1], xlim[2], ylim[2], col = "white", border = NA); draw_land()
    z0 <- q[q$cells == 0, ]; points(z0$lon, z0$lat, pch = ".", cex = 1.6, col = "gray45")
    pp <- q[q$cells > 0, ]; pp <- pp[order(pp$cells), ]
    bins <- cut(pp$cells, class_brks[-1], labels = FALSE, include.lowest = TRUE)
    bord <- ifelse(pp$ge10k & pp$water & !pp$in_6oct, "red", "black")
    points(pp$lon, pp$lat, pch = 21, bg = spal[bins], col = bord, cex = 0.75, lwd = 0.9)
    hi <- q[q$cells >= thr_bloom & q$water, ]
    info_box(c(class_lines(class_counts_v(q$cells)), sprintf(">= 10,000 on water: %d, %d outside the 6 Oct footprint", nrow(hi), sum(!hi$in_6oct)),
               sprintf("%d on template land", sum(!q$water))))
    box()
  }
  hm <- all_yrmo[rec$headline]
  draw_fig1 <- function() {
    pages <- split(hm, ceiling(seq_along(hm) / fig1_per_page))
    for (pg in pages) {
      par(mfrow = c(fig1_per_page, 3), mar = c(0.4, 0.4, 1.6, 0.4), oma = c(0.5, 0.5, 2.2, 0.5))
      for (ym in pg) {
        r <- rec[rec$yrmo == ym, ]; lab <- paste0(substr(ym, 1, 4), "-", substr(ym, 5, 6))
        draw_samples_panel(ym, sprintf("%s: FWC samples (fit %s, VIIRS %s)", lab, r$fit_status, r$viirs_status))
        draw_map_panel(M0[, ym], sprintf("6 Oct 2026 map (%s): %s km2 >= 10k, exposure %s", toupper(sub("hybrid_modis", "modis", sub("^hybrid$", "viirs", r$use))), fmt_n(round(r$km2_ge10k_v6oct)), fmt_n(signif(r$exposure_v6oct, 3))),
                       extra = sprintf("samples >= 10k inside: %d / %d", r$in_ge10k_v6oct, r$samples_ge10k))
        draw_map_panel(Mf[, ym], sprintf("delivered map (mask5adj hybrid): %s km2 >= 10k (+%s), exposure %s", fmt_n(round(r$km2_ge10k_final)), fmt_n(round(r$km2_ge10k_final) - round(r$km2_ge10k_v6oct)), fmt_n(signif(r$exposure_final, 3))),
                       diff_from = M0[, ym], shade = set, extra = sprintf("inside: %d / %d; %d cells changed", r$in_ge10k_final, r$samples_ge10k, r$cells_changed_final))
      }
      mtext("Issue #18: the 16 headline months of #6 (fitted surface, VIIRS layer all zero). Left: samples (red border = >= 10k cells/L on water, outside the 6 Oct footprint). Middle: the 6 Oct 2026 map. Right: the delivered map (nearshore set shaded, changed cells in orange).",
            outer = TRUE, cex = 0.62, font = 2, line = 0.6)
    }
  }
  write_pdf(file.path(dir_fig, "fig1_headline_months_issue18.pdf"), width = 11, height = 2.75 * fig1_per_page, draw_fig1)
  png_dir <- Sys.getenv("RT_QA_PNG_DIR", "")
  if (nzchar(png_dir)) {
    dir.create(png_dir, recursive = TRUE, showWarnings = FALSE)
    pages <- split(hm, ceiling(seq_along(hm) / fig1_per_page))
    for (i in seq_along(pages)) {
      png(file.path(png_dir, sprintf("fig1_page%d.png", i)), width = 11, height = 2.75 * fig1_per_page, units = "in", res = 110)
      hm_page <- pages[[i]]; hm_save <- hm; hm <- hm_page; draw_fig1(); hm <- hm_save; dev.off()
    }
  }

  # Fig 2: the record from the first satellite month, the #5 summary layout (plot_summary_issue5.R).
  sat_all <- rec$use %in% c("viirs", "modis", "hybrid", "hybrid_modis")
  d2 <- rec[rec$yrmo >= min(rec$yrmo[sat_all]), ]
  d2$era <- ifelse(d2$use %in% c("viirs", "hybrid"), "VIIRS", ifelse(d2$use %in% c("modis", "hybrid_modis"), "MODIS", "hull"))
  era_col  <- c(hull = grDevices::adjustcolor("gray40", 0.12), MODIS = grDevices::adjustcolor("steelblue", 0.18), VIIRS = grDevices::adjustcolor("gold", 0.22))
  zero_col <- grDevices::adjustcolor("gray40", 0.3); miss_col <- grDevices::adjustcolor("red", 0.25)
  k2 <- c(v6oct = "6 Oct 2026 maps (satellite only)", final = "the delivered maps: nearshore hybrid, the decided set (#15) with the hull fill")
  vcol <- c(v6oct = "black", final = "purple3"); vpch <- c(v6oct = 16, final = 1)
  n2 <- nrow(d2); x2 <- seq_len(n2); few <- d2$samples_ge10k < min_samples_group
  panel_of <- function(stem, lab, main, pts = FALSE, div = 1) list(
    y = lapply(names(k2), function(k) { y <- d2[[paste0(stem, "_", k)]] / div; if (pts) { y <- y / d2$samples_ge10k; y[few] <- NA }; y }), lab = lab, main = main, pts = pts)
  panels <- list(panel_of("exposure", "million cells/L (sum over water cells)", sprintf("Total exposure: cells/L summed over the %s water cells", fmt_n(sum(water))), div = 1e6),
                 panel_of("n_ge10k", "cells", "Grid cells at or above 10,000 cells/L"),
                 panel_of("n_ge100k", "cells", "Grid cells at or above 100,000 cells/L"),
                 panel_of("n_ge1M", "cells", "Grid cells at or above 1,000,000 cells/L"),
                 panel_of("in_ge10k", "share of samples", sprintf("Share of the in-situ samples >= 10,000 cells/L (water cells) that the projection includes, months with at least %d such samples", min_samples_group), pts = TRUE))
  file_png <- file.path(dir_fig, "fig2_record_2002-2026_issue18.png")
  png_open(file_png, width = 15, height = 13.5, units = "in", res = 150)
  par(mfrow = c(length(panels), 1), mar = c(2.8, 4.6, 2.2, 0.6), oma = c(0, 0, 1.8, 0), mgp = c(3, 0.6, 0))
  for (i in seq_along(panels)) {
    p <- panels[[i]]
    yl <- if (p$pts) c(0, 1.04) else c(0, max(c(unlist(p$y), 1), na.rm = TRUE) * 1.08)
    plot(NA, xlim = c(0.5, n2 + 0.5), ylim = yl, xlab = "", ylab = p$lab, main = p$main, cex.main = 0.95, axes = FALSE, xaxs = "i", yaxs = "i")
    for (u in names(era_col)) { w <- which(d2$era == u); if (length(w)) rect(w - 0.5, yl[1], w + 0.5, yl[2], col = era_col[[u]], border = NA) }
    zm <- which(d2$viirs_status == "zero"); mm <- which(d2$viirs_status == "missing")
    rect(zm - 0.5, yl[1], zm + 0.5, yl[2], col = zero_col, border = NA); rect(mm - 0.5, yl[1], mm + 0.5, yl[2], col = miss_col, border = NA)
    for (k in rev(seq_along(k2))) {
      if (p$pts) points(x2, p$y[[k]], col = vcol[[k]], pch = vpch[[k]], cex = if (k == 1) 0.6 else 0.8, lwd = 1.1) else
        lines(x2, p$y[[k]], col = vcol[[k]], lwd = if (k == 1) 1.4 else 1.7)
    }
    jan <- which(d2$month == 1); axis(1, at = jan, labels = d2$year[jan], cex.axis = 0.85)
    axis(2, las = 1, cex.axis = 0.85); box()
    if (i == 1) legend("topleft", legend = c(unname(k2), "hull months", "MODIS months", "VIIRS months", "VIIRS layer all zero", "VIIRS tif missing (2022-12)"),
                       col = c(unname(vcol), rep(NA, 5)), lwd = c(1.4, 1.7, rep(NA, 5)),
                       fill = c(NA, NA, era_col[["hull"]], era_col[["MODIS"]], era_col[["VIIRS"]], zero_col, miss_col), border = NA, cex = 0.78, bg = "white", box.col = "gray60", ncol = 2)
    if (p$pts) legend("bottomleft", legend = unname(k2), col = unname(vcol), pch = unname(vpch), pt.cex = c(0.6, 0.8), cex = 0.78, bg = "white", box.col = "gray60", ncol = 2)
  }
  mtext(sprintf("Red tide exposure per monthly map from the first satellite month (%s-%s) to %d: the 6 Oct 2026 maps and the delivered maps (nearshore hybrid, rule mask5adj, both sensors; issue #18)",
                substr(d2$yrmo[1], 1, 4), substr(d2$yrmo[1], 5, 6), max(d2$year)), outer = TRUE, cex = 0.95, font = 2, line = 0.4)
  png_done(file_png)

  # The summary in markdown.
  gsel <- grp[c(1, 3, 4, 5, 2, 6, 7), ]
  gt <- data.frame(group = gsel$group, months_changed = gsel$months_changed_final,
                   exposure_6oct = gsel$exposure_v6oct, exposure_final = gsel$exposure_final, exposure_ratio = gsel$exposure_ratio_final, exposure_ratio_mask5 = gsel$exposure_ratio_mask5,
                   cellmonths_ge10k_6oct = gsel$cellmonths_ge10k_v6oct, cellmonths_ge10k_final = gsel$cellmonths_ge10k_final,
                   cellmonths_ge100k_6oct = gsel$cellmonths_ge100k_v6oct, cellmonths_ge100k_final = gsel$cellmonths_ge100k_final,
                   cellmonths_ge1M_6oct = gsel$cellmonths_ge1M_v6oct, cellmonths_ge1M_final = gsel$cellmonths_ge1M_final,
                   samples_ge10k = gsel$samples_ge10k, share_ge10k_6oct = gsel$share_ge10k_v6oct, share_ge10k_final = gsel$share_ge10k_final,
                   samples_gt1M = gsel$samples_gt1M, share_gt1M_6oct = gsel$share_gt1M_v6oct, share_gt1M_final = gsel$share_gt1M_final, stringsAsFactors = FALSE)
  ht <- rec[rec$headline, c("yrmo", "samples_ge10k", "in_ge10k_v6oct", "in_ge10k_final", "km2_ge10k_v6oct", "km2_ge10k_final", "exposure_v6oct", "exposure_final", "cells_changed_final")]
  md <- c("# Issue #18, stage record: the delivered maps against the 6 Oct 2026 maps (and the mask5 run of #10)", "",
          sprintf("From the combined stacks of the final 5-arcmin run (hoard/final5, FWC samples frozen at the %s pull) and the 6 Oct 2026 run; %d months, %d of them satellite months (%d VIIRS, %d MODIS), %d hull months byte-identical.",
                  sub("^.*([0-9]{8})_filtered.*$", "\\1", pts$file[1]), length(all_yrmo), length(months), length(months_v), length(months_m), sum(!is_sat)), "",
          "## By group (`tables/record_groups_issue18.csv`)", "", md_table(round_cols(gt), 3), "",
          "## The 16 headline months of #6 (`tables/record_months_issue18.csv`; figure 1)", "", md_table(round_cols(ht), 0), "")
  writeLines(md, file.path(dir_cmt, "record_summary.md"))
  message("Stage record OK: the delivered maps equal the #15 prototype month by month; satellite months exposure x",
          round(g$exposure_ratio_final, 3), " vs 6 Oct, samples >= 10k included ", round(100 * g$share_ge10k_v6oct, 1), "% -> ", round(100 * g$share_ge10k_final, 1), "%.")
}

# Stage refresh ----------------------------------------------------------------------
if (stage == "refresh") {
  need(file_cs)
  dir_frozen <- file.path(dir_hoard, sprintf("final%d", res))
  ref <- md5_dir(file.path(dir_frozen, "ecospace_ascii"))
  d <- md5_against(ref, "frozen")
  d$exported_equal <- check_export(data.frame(yrmo = d$yrmo, file = d$file, md5 = d$md5_now, stringsAsFactors = FALSE))
  report_log()
  uc <- use_counts_of(d); chg <- d$changed_vs_frozen
  cs_frozen <- read_cs(file.path(dir_frozen, "clipping_source.csv")); cs_now <- read_cs(file_cs)
  stopifnot(identical(cs_frozen$yrmo, cs_now$yrmo), identical(cs_frozen$use, cs_now$use), identical(cs_frozen$hybrid_changed, cs_now$hybrid_changed))
  # The samples: the frozen run's filtered file against the new one, per month.
  cnt_by_month <- function(dir) { p <- load_samples(d$yrmo, dir); p <- p[p$water, ]; list(file = p$file[1], n = as.vector(table(factor(p$yrmo, levels = d$yrmo))),
                                                                                              n_pos = as.vector(table(factor(p$yrmo[p$cells > 0], levels = d$yrmo)))) }
  s0 <- cnt_by_month(file.path(dir_frozen, "sdm")); s1 <- cnt_by_month(dir_sdm)
  rm <- data.frame(yrmo = d$yrmo, use = d$use, samples_frozen = s0$n, samples_refresh = s1$n, positives_frozen = s0$n_pos, positives_refresh = s1$n_pos,
                   ascii_changed = chg, stringsAsFactors = FALSE)
  rm$samples_changed <- rm$samples_frozen != rm$samples_refresh | rm$positives_frozen != rm$positives_refresh
  first_new <- if (any(rm$samples_changed)) min(rm$yrmo[rm$samples_changed]) else NA_character_
  write.csv(d, file.path(dir_tab, sprintf("md5_refresh%d_issue18.csv", res)), row.names = FALSE)
  write.csv(rm[rm$samples_changed | rm$ascii_changed, ], file.path(dir_tab, sprintf("refresh_months%d_issue18.csv", res)), row.names = FALSE)
  cat("clipping_source.csv use:", paste(names(expected$use_hybrid), uc, collapse = ", "), "\n")
  cat(sprintf("FWC samples: frozen %s -> refreshed %s; months with new or changed water samples: %d (from %s); ASCII files changed vs the frozen run: %d of %d: %s\n",
              s0$file, s1$file, sum(rm$samples_changed), first_new, sum(chg), nrow(d), paste(d$yrmo[chg], collapse = ", ")))
  stopifnot(all(uc == expected$use_hybrid), has_log("ingest FWC HAB data from ArcGIS REST"), has_log(paste0("Nearshore rule ", rule_name, ":")),
            has_log("Step 8: export"), has_log("Run complete."), all(d$exported_equal),
            all(d$use[chg] == "pred"), is.na(first_new) || all(d$yrmo[chg] >= first_new), all(rm$samples_refresh >= rm$samples_frozen))
  message("Stage refresh OK at ", res, " arcmin: ", sum(chg), " of ", nrow(d), " ASCII files changed, all hull-served months from ", first_new,
          " on; the satellite months are byte-identical to the frozen run; the export folder equals ecospace_ascii/.")
}
