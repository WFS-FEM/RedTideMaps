#' QA for issue #8, step 2: hybrid VIIRS + hull footprints for five nearshore sets.
#'
#' For every VIIRS month (2012-01 to 2024-12, 155 months) builds, from the clipped
#' stacks of the last pipeline run, the footprint a hybrid rule would give:
#'
#'     hybrid_N[cell] = max(viirs_clipped[cell], hull_clipped[cell] * [cell in N])
#'
#' i.e. outside the nearshore set N the VIIRS result stands (including zeros);
#' inside N the buffered-hull footprint (the pipeline's own hull method, every
#' positive sample, 75 km linkage, 10 km buffer) is added to it and never removes
#' a VIIRS detection. Five sets N on the 5-arcmin Gulf-domain water cells:
#'   mask     cells whose 0.1-degree VIIRS cell is in the static no-data mask
#'   coast2   cells whose centre is within 2 km of the Natural Earth 1:10m coastline
#'   coast5   ... within 5 km
#'   mask5    mask or coast5 (every masked cell, plus the 2 to 5 km strip; added 20 Oct 2026)
#'   coast10  ... within 10 km
#' Comparators: `current` (the final combined map) and `hull` (the hull-clipped map,
#' what a full hull fallback would give). Nothing is refit or re-clipped.
#'
#' Sources check_nearshore_issue8.R (step 1, ~15 s, regenerates its outputs
#' byte-identically) and reuses its objects and drawing helpers.
#'
#' Run from the repo root:  Rscript docs/issue5_nearshore-hybrid-summary/subissues/issue8_nearshore-hybrid/hybrid_nearshore_issue8.R
#'   RT_QA_MONTHLY_PDF=0  skip the monthly PDF
#'
#' Output (docs/issue5_nearshore-hybrid-summary/subissues/issue8_nearshore-hybrid/):
#'   tables/hybrid_sets_issue8.csv          the five N sets: cells, km2, overlaps, depth, distance, region
#'   tables/hybrid_months_long_issue8.csv   155 months x 6 variants: areas, cells added, samples inside
#'   tables/hybrid_months_issue8.csv        the same, wide, one row per month
#'   tables/hybrid_groups_issue8.csv        totals by month group x variant
#'   figures/fig5_nearshore_sets.png        the five N sets on the map
#'   figures/fig6_hybrid_headline.pdf       headline, low_vs_hull and control months: 8 panels per month, 10 months per page
#'   figures/fig7_hybrid_area_2012-2024.png bloom area and sample coverage per month by variant
#'   hybrid_months_issue8.pdf               all 155 months, 12 rows (a calendar year) per page
#'   comments/hybrid_summary.md             the tables in markdown, for #8
#'
#' Deterministic: no RNG, no timestamps in any output (the two PDFs carry the
#' two date lines every R pdf() device writes).

# Repo root: the working directory if it holds the .Rproj, else four levels
# above this script (docs/issue5_nearshore-hybrid-summary/subissues/issue8_nearshore-hybrid/).
.root <- local({
  if (file.exists("RedTideMaps.Rproj")) return(normalizePath(getwd(), winslash = "/"))
  f <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE))
  if (length(f) == 1) {
    d <- normalizePath(file.path(dirname(f), "..", "..", "..", ".."), winslash = "/", mustWork = FALSE)
    if (file.exists(file.path(d, "RedTideMaps.Rproj"))) return(d)
  }
  stop("Run from the repo root: Rscript docs/issue5_nearshore-hybrid-summary/subissues/issue8_nearshore-hybrid/hybrid_nearshore_issue8.R", call. = FALSE)
})
message("Step 2: sourcing step 1 (check_nearshore_issue8.R; regenerates its outputs) ...")
dir_sub <- file.path(.root, "docs", "issue5_nearshore-hybrid-summary", "subissues")
source(file.path(dir_sub, "issue8_nearshore-hybrid", "check_nearshore_issue8.R"))
# Step 1 leaves in the workspace: depth, dv, land, cell_km2, n5, H, Vc, Fm, Vr, cell01_of5,
# domain, atl5, masked5_static, dist5, region5, region_lv, pts, t5, tab6, sel3, zeroed,
# headline, months, all_months, vz, class_lv, pos_lv, thr_bloom, thr_high, coast, the
# drawing helpers (base_panel, draw_land, info_box, draw_samples_panel, class_counts_v,
# class_lines, to_z, xs, ys, xlim, ylim, brks_img, color, fmt_n, md_table) and the
# output folders (dir_docs, dir_fig, dir_tab, dir_cmt). None of them is rebound here
# except `coast`, simplified around the PDF block and restored.
message("Step 2: hybrid footprints")

# Parameters ---------------------------------------------------------------
coast_km  <- c(coast2 = 2, coast5 = 5, coast10 = 10)   # distance-to-coast sets (km)
variants  <- c("current", "mask", "coast2", "coast5", "mask5", "coast10", "hull")   # mask5 = mask or within 5 km
hybrids   <- variants[2:6]
lowhull_months <- c("201801", "202104")   # VIIRS-positive months flagged low_vs_hull in #6
# Control months: VIIRS-positive fitted months of #6 with no flag, at least 80% of the
# water samples >= 10,000 cells/L inside the current footprint and a hull ratio within
# 0.75 to 1.33; the two with the highest share. Derived from the rule, frozen in expected2.
control_rule   <- list(min_frac_in_fp = 0.8, hull_ratio = c(0.75, 1.33), n = 2L)
rows_per_page  <- 12L                      # monthly PDF rows per page; pages are calendar years
fig6_per_page  <- 10L                      # fig6 PDF months per page
coast_tol_m    <- 500                      # coastline simplification for the two PDFs (fig6, monthly)
monthly_pdf    <- !identical(Sys.getenv("RT_QA_MONTHLY_PDF"), "0")
expected2 <- list(n_months = 155L,
                  n_sets = c(mask = 84L, coast2 = 64L, coast5 = 132L, mask5 = 136L, coast10 = 213L),   # from mask_band_issue8.csv (step 1); mask5 = 84 + 52
                  n_sel3 = 60L, n_viirs_pos = 66L, n_viirs_zero = 89L,
                  control = c("201408", "202109"))

# The five nearshore sets ----------------------------------------------------------
N <- c(list(mask = domain & masked5_static),
       lapply(coast_km, function(km) domain & !is.na(dist5) & dist5 <= km))
N$mask5 <- N$mask | N$coast5                        # the mask, or within 5 km of the coast
N <- N[hybrids]
stopifnot(identical(names(N), hybrids),
          all(N$coast2 <= N$coast5), all(N$coast5 <= N$mask5), all(N$mask <= N$mask5), all(N$mask5 <= N$coast10),   # nested
          all(vapply(N, function(s) all(domain[s]), logical(1))))      # water, Gulf domain only
n_sets <- vapply(N, sum, integer(1))
if (!identical(n_sets, expected2$n_sets))
  stop("Set sizes differ from expected2: ", paste(names(n_sets), n_sets, collapse = ", "), call. = FALSE)
message("Masked cells beyond 10 km of the coast (not in coast10): ", sum(N$mask & !N$coast10))
sets_tab <- do.call(rbind, lapply(hybrids, function(k) {
  s <- N[[k]]
  r <- data.frame(set = k, n_cells = sum(s), km2 = round(sum(cell_km2[s])),
                  share_of_domain_cells = round(sum(s) / sum(domain), 3),
                  n_in_mask = sum(s & N$mask), share_in_mask = round(mean(N$mask[s]), 2),
                  mask_cells_not_in_set = sum(N$mask & !s),
                  median_depth_m = round(median(dv[s]), 1), max_depth_m = round(max(dv[s]), 1),
                  median_dist_km = round(median(dist5[s]), 1), max_dist_km = round(max(dist5[s]), 1),
                  stringsAsFactors = FALSE)
  for (o in hybrids) r[[paste0("overlap_", o)]] <- sum(s & N[[o]])
  for (rg in region_lv) r[[paste0("n_", gsub("[^A-Za-z]+", "_", rg))]] <- sum(s & region5 == rg)
  r
}))
write.csv(sets_tab, file.path(dir_tab, "hybrid_sets_issue8.csv"), row.names = FALSE)

# The seven variant maps (cells x months) --------------------------------------------
stopifnot(identical(months, colnames(Vr)), length(months) == expected2$n_months, !("202212" %in% months),
          all(months %in% colnames(H)), all(months %in% colnames(Fm)),
          identical(sort(months), sort(tab6$yrmo[tab6$use == "viirs"])))
V <- Fm[, months]                                   # current final map: 0 outside the footprint, NA on land
norm_map <- function(M) { M[is.na(M)] <- 0; M[land, ] <- NA; M }
Hm  <- norm_map(H[, months])                        # hull-clipped, normalised the same way
Vcn <- norm_map(Vc[, months])
stopifnot(all(is.na(V) == land), isTRUE(all.equal(Vcn, V, check.attributes = FALSE)))   # the final map is the VIIRS-clipped layer in every VIIRS month
hyb <- function(Nk) { M <- V; M[Nk, ] <- pmax(V[Nk, , drop = FALSE], Hm[Nk, , drop = FALSE]); M }
maps <- c(list(current = V), lapply(N, hyb), list(hull = Hm))
stopifnot(identical(names(maps), variants))
valid5 <- !is.na(Vr[cell01_of5, ])                 # 5-arcmin cell x month: its VIIRS cell has data that month
stopifnot(identical(dim(valid5), dim(V)))

# Structural checks ------------------------------------------------------------------
U <- pmax(V, Hm)
for (k in hybrids) {
  M <- maps[[k]]; Nk <- N[[k]]
  stopifnot(all(is.na(M) == land),
            all(M[!land, ] >= V[!land, ]),                 # never shrinks the current footprint
            all(M[!land, ] <= U[!land, ]),                 # never exceeds the union with the hull
            identical(M[!Nk, ], V[!Nk, ]),                 # untouched outside N
            all(M[Nk, ] == U[Nk, ]))                       # the union inside N
}
stopifnot(identical(hyb(rep(FALSE, n5)), V), isTRUE(all.equal(hyb(domain)[domain, ], U[domain, ])))
rm(U)

# Per-month metrics ------------------------------------------------------------------
area_ge <- function(M, thr) colSums((!is.na(M) & M >= thr) * cell_km2)
metrics_of <- function(M) {
  add <- !is.na(M) & M > 0 & V == 0
  rem <- !is.na(M) & M == 0 & V > 0
  add4 <- !is.na(M) & M >= thr_bloom & V < thr_bloom
  add5 <- !is.na(M) & M >= thr_high  & V < thr_high
  data.frame(yrmo = months,
             fp_km2 = colSums((!is.na(M) & M > 0) * cell_km2),
             a1e4_km2 = area_ge(M, thr_bloom), a1e5_km2 = area_ge(M, thr_high),
             n_cells_fp = colSums(!is.na(M) & M > 0),
             max_cells = apply(M, 2, max, na.rm = TRUE),
             added_cells = colSums(add), removed_cells = colSums(rem),
             added_fp_km2 = colSums(add * cell_km2),
             added_fp_km2_masked = colSums((add & !valid5) * cell_km2),
             added_fp_km2_valid  = colSums((add &  valid5) * cell_km2),
             added_1e4_km2 = colSums(add4 * cell_km2),
             added_1e4_km2_masked = colSums((add4 & !valid5) * cell_km2),
             added_1e4_km2_valid  = colSums((add4 &  valid5) * cell_km2),
             added_1e5_km2 = colSums(add5 * cell_km2),
             removed_fp_km2 = colSums(rem * cell_km2),
             cells_changed = colSums(!is.na(M) & M != V),
             stringsAsFactors = FALSE)
}

# Sample coverage: water samples of the month, one matrix index per variant ------------
pw <- pts[pts$template == "water" & pts$yrmo %in% months, ]
j_pw <- match(pw$yrmo, months); ymf <- factor(pw$yrmo, levels = months)
pw$ge1e4 <- pw$cells >= thr_bloom
samples_of <- function(M) {
  inside <- M[cbind(pw$cell5, j_pw)] > 0
  stopifnot(!any(is.na(inside)))
  cnt <- function(sel) as.vector(table(ymf[sel]))
  hit <- function(sel) as.vector(table(ymf[sel & inside]))
  out <- data.frame(yrmo = months, stringsAsFactors = FALSE)
  for (k in c("low", "medium", "high")) { s <- pw$class == k; out[[paste0("n_", k)]] <- cnt(s); out[[paste0("in_", k)]] <- hit(s) }
  out$n_ge1e4 <- cnt(pw$ge1e4); out$in_ge1e4 <- hit(pw$ge1e4)
  out$share_ge1e4 <- ifelse(out$n_ge1e4 > 0, round(out$in_ge1e4 / out$n_ge1e4, 3), NA)
  out
}

# Long and wide tables ---------------------------------------------------------------
long <- do.call(rbind, lapply(variants, function(k) {
  m <- metrics_of(maps[[k]]); s <- samples_of(maps[[k]])
  stopifnot(identical(m$yrmo, s$yrmo))
  cbind(variant = k, m, s[-1], stringsAsFactors = FALSE)
}))
desc_cols <- c("use", "viirs_status", "fit_status", "zeroed_fit", "headline", "viirs_n_pos_cells", "n_pos")
desc <- t5[match(long$yrmo, t5$yrmo), desc_cols]
viirs_pos  <- tab6$yrmo[tab6$use == "viirs" & tab6$viirs_status == "positive"]
viirs_zero <- tab6$yrmo[tab6$use == "viirs" & tab6$viirs_status == "zero"]
# Control months from the rule (frozen in expected2 so the figure rows are stable).
cand <- tab6[tab6$yrmo %in% sel3 & !(tab6$any_flag %in% TRUE) &
             tab6$frac_pos_1e4_in_fp >= control_rule$min_frac_in_fp &
             tab6$hull_ratio_1e4 >= control_rule$hull_ratio[1] & tab6$hull_ratio_1e4 <= control_rule$hull_ratio[2], ]
cand <- cand[order(-cand$frac_pos_1e4_in_fp, cand$yrmo), ]
control_months <- head(cand$yrmo, control_rule$n)
message("Control months by the rule: ", paste(control_months, collapse = ", "),
        " (candidates: ", paste(cand$yrmo, collapse = ", "), ")")
stopifnot(identical(sort(control_months), sort(expected2$control)))
long <- cbind(long[, c("variant", "yrmo")], desc, long[, setdiff(names(long), c("variant", "yrmo"))],
              in_sel3 = long$yrmo %in% sel3, lowhull = long$yrmo %in% lowhull_months, control = long$yrmo %in% control_months,
              stringsAsFactors = FALSE)
rownames(long) <- NULL

# Checks against step 1 and #6 (sample counts, group sizes) ----------------------------
cur <- long[long$variant == "current", ]
t5m <- t5[match(cur$yrmo, t5$yrmo), ]
for (k in c("low", "medium", "high"))
  stopifnot(all(cur[[paste0("n_", k)]] == t5m[[paste0("n_", k, "_masked")]] + t5m[[paste0("n_", k, "_valid_zero")]] +
                  t5m[[paste0("n_", k, "_valid_pos")]] - t5m[[paste0("n_", k, "_land")]]))
tab6m <- tab6[match(cur$yrmo, tab6$yrmo), ]
stopifnot(all(cur$n_ge1e4 == tab6m$n_pos_1e4_water), all(cur$in_ge1e4 == tab6m$n_pos_1e4_in_fp),
          all((V[cbind(pw$cell5, j_pw)] > 0) == (pw$in_final_fp %in% TRUE)))
stopifnot(all(long$removed_cells[long$variant %in% hybrids] == 0),
          all(long$added_cells[long$variant == "current"] == 0))
a4 <- function(k) long$a1e4_km2[long$variant == k]
stopifnot(all(a4("current") <= a4("coast2")), all(a4("coast2") <= a4("coast5")), all(a4("coast5") <= a4("mask5")),
          all(a4("mask5") <= a4("coast10")), all(a4("current") <= a4("mask")), all(a4("mask") <= a4("mask5")))
stopifnot(length(sel3) == expected2$n_sel3, length(viirs_pos) == expected2$n_viirs_pos, length(viirs_zero) == expected2$n_viirs_zero,
          all(lowhull_months %in% months), all(tab6$flag_low_vs_hull[match(lowhull_months, tab6$yrmo)] %in% TRUE),
          all(control_months %in% sel3), length(zeroed) == 58L, length(headline) == 16L)
message("Checks passed.")

keep <- c("fp_km2", "a1e4_km2", "a1e5_km2", "added_1e4_km2", "added_1e4_km2_masked", "added_1e4_km2_valid",
          "removed_fp_km2", "cells_changed", "in_ge1e4", "share_ge1e4", "in_high")
wide <- reshape(long[, c("yrmo", "variant", keep)], idvar = "yrmo", timevar = "variant", direction = "wide", sep = "_")
attr(wide, "reshapeWide") <- NULL
wide <- cbind(cur[, c("yrmo", desc_cols, "in_sel3", "lowhull", "control", "n_low", "n_medium", "n_high", "n_ge1e4")],
              wide[match(cur$yrmo, wide$yrmo), -1])
rownames(wide) <- NULL
round_km2 <- function(df) { for (nm in grep("km2", names(df), value = TRUE)) df[[nm]] <- round(df[[nm]]); df }
write.csv(round_km2(long), file.path(dir_tab, "hybrid_months_long_issue8.csv"), row.names = FALSE)
write.csv(round_km2(wide), file.path(dir_tab, "hybrid_months_issue8.csv"), row.names = FALSE)

# Totals by month group --------------------------------------------------------------
groups <- list(months, zeroed, headline, sel3, viirs_pos, viirs_zero)
names(groups) <- c(sprintf("all %d VIIRS months", length(months)),
                   sprintf("the %d zeroed months", length(zeroed)),
                   sprintf("the %d headline months", length(headline)),
                   sprintf("the %d VIIRS-positive fitted months of #6", length(sel3)),
                   sprintf("the %d VIIRS-positive months", length(viirs_pos)),
                   sprintf("the %d VIIRS all-zero months", length(viirs_zero)))
grp <- do.call(rbind, lapply(names(groups), function(lab) {
  g <- groups[[lab]]
  hull_a4 <- sum(long$a1e4_km2[long$variant == "hull" & long$yrmo %in% g])
  cur_a4  <- sum(long$a1e4_km2[long$variant == "current" & long$yrmo %in% g])
  do.call(rbind, lapply(variants, function(k) {
    d <- long[long$variant == k & long$yrmo %in% g, ]
    data.frame(group = lab, variant = k, n_months = length(g),
               months_with_fp = sum(d$fp_km2 > 0), months_changed = sum(d$added_cells > 0),
               fp_km2 = round(sum(d$fp_km2)), a1e4_km2 = round(sum(d$a1e4_km2)), a1e5_km2 = round(sum(d$a1e5_km2)),
               a1e4_vs_current = if (cur_a4 > 0) round(sum(d$a1e4_km2) / cur_a4, 2) else NA_real_,
               a1e4_vs_hull = if (hull_a4 > 0) round(sum(d$a1e4_km2) / hull_a4, 2) else NA_real_,
               added_1e4_km2 = round(sum(d$added_1e4_km2)),
               added_1e4_km2_masked = round(sum(d$added_1e4_km2_masked)), added_1e4_km2_valid = round(sum(d$added_1e4_km2_valid)),
               removed_fp_km2 = round(sum(d$removed_fp_km2)),
               n_low = sum(d$n_low), in_low = sum(d$in_low), n_medium = sum(d$n_medium), in_medium = sum(d$in_medium),
               n_high = sum(d$n_high), in_high = sum(d$in_high), n_ge1e4 = sum(d$n_ge1e4), in_ge1e4 = sum(d$in_ge1e4),
               share_ge1e4 = round(sum(d$in_ge1e4) / max(sum(d$n_ge1e4), 1), 3),
               share_medium = round(sum(d$in_medium) / max(sum(d$n_medium), 1), 3),
               share_high = round(sum(d$in_high) / max(sum(d$n_high), 1), 3),
               stringsAsFactors = FALSE)
  }))
}))
rownames(grp) <- NULL
write.csv(grp, file.path(dir_tab, "hybrid_groups_issue8.csv"), row.names = FALSE)

# Summary (console + markdown) ------------------------------------------------------
show_months <- c(headline, lowhull_months, control_months)
tag_of <- function(ym) if (ym %in% headline) "headline" else if (ym %in% zeroed) "zeroed" else if (ym %in% lowhull_months) "low_vs_hull" else if (ym %in% control_months) "control" else ""
wide_block <- function(col, ms) {
  d <- data.frame(yrmo = ms, tag = vapply(ms, tag_of, character(1)), stringsAsFactors = FALSE)
  for (k in variants) d[[k]] <- long[[col]][match(paste(k, ms), paste(long$variant, long$yrmo))]
  d
}
g_all <- grp[grp$group == names(groups)[1], ]
g_zero <- grp[grp$group == names(groups)[2], ]
g_pos <- grp[grp$group == names(groups)[4], ]
pick <- function(g, k, col) g[[col]][g$variant == k]
hdr2 <- c(
  "# Issue #8, step 2: hybrid footprints (VIIRS outside N, VIIRS or hull inside N)",
  "",
  sprintf("Produced by `docs/issue5_nearshore-hybrid-summary/subissues/issue8_nearshore-hybrid/hybrid_nearshore_issue8.R` from the clipped stacks of the 6 October 2026 run and the step-1 objects. For each of the %d VIIRS months and each nearshore set N, `hybrid_N = max(viirs_clipped, hull_clipped * [cell in N])`: outside N the VIIRS result stands, zeros included; inside N the hull footprint (the pipeline's hull method: every positive sample, 75 km linkage, 10 km buffer) is added and never removes a VIIRS detection. Comparators: `current` (the final map) and `hull` (the hull-clipped map, a full hull fallback). Bloom area is km2 of water cells at or above 10,000 cells/L (`a1e4`) or 100,000 cells/L (`a1e5`); `added` is area the variant adds to the current map, split by whether the 0.1-degree VIIRS cell is masked or valid that month; samples are water-cell samples whose 5-arcmin cell is non-zero in the variant.",
          length(months)),
  "",
  "## The five nearshore sets (`tables/hybrid_sets_issue8.csv`)",
  "",
  "`mask5` is the union of `mask` and `coast5`: every masked cell, plus the cells within 5 km of the coast.",
  "",
  md_table(sets_tab[, c("set", "n_cells", "km2", "share_in_mask", "mask_cells_not_in_set", "median_depth_m", "max_depth_m", "median_dist_km", "max_dist_km",
                        "overlap_mask", "overlap_coast2", "overlap_coast5", "overlap_mask5", "overlap_coast10")]),
  "",
  "## Totals by month group (`tables/hybrid_groups_issue8.csv`)",
  "")
grp_cols <- c("variant", "months_changed", "a1e4_km2", "a1e4_vs_hull", "a1e5_km2", "added_1e4_km2", "added_1e4_km2_masked", "added_1e4_km2_valid",
              "removed_fp_km2", "n_ge1e4", "in_ge1e4", "share_ge1e4", "share_medium", "share_high")
for (lab in names(groups)) hdr2 <- c(hdr2, paste0("### ", lab), "", md_table(grp[grp$group == lab, grp_cols], 3), "")
hdr2 <- c(hdr2,
  sprintf("Over all %d VIIRS months the `mask` rule changes %d months and adds %s km2 of bloom area (>= 10,000 cells/L), all of it in masked cells; `coast5` changes %d months and adds %s km2, of which %s km2 in VIIRS-valid cells; `mask5` (mask or within 5 km) changes %d months and adds %s km2, of which %s km2 in VIIRS-valid cells; the share of water samples >= 10,000 cells/L inside the footprint goes from %d%% (current) to %d%% (mask), %d%% (coast2), %d%% (coast5), %d%% (mask5), %d%% (coast10) and %d%% (hull). In the %d zeroed months the hybrids restore %d%% (mask), %d%% (coast2), %d%% (coast5), %d%% (mask5) and %d%% (coast10) of the hull-clipped bloom area; in the %d VIIRS-positive fitted months of #6 they add %s / %s / %s / %s / %s km2 against a current %s km2.",
          length(months), pick(g_all, "mask", "months_changed"), fmt_n(pick(g_all, "mask", "added_1e4_km2")),
          pick(g_all, "coast5", "months_changed"), fmt_n(pick(g_all, "coast5", "added_1e4_km2")), fmt_n(pick(g_all, "coast5", "added_1e4_km2_valid")),
          pick(g_all, "mask5", "months_changed"), fmt_n(pick(g_all, "mask5", "added_1e4_km2")), fmt_n(pick(g_all, "mask5", "added_1e4_km2_valid")),
          round(100 * pick(g_all, "current", "share_ge1e4")), round(100 * pick(g_all, "mask", "share_ge1e4")), round(100 * pick(g_all, "coast2", "share_ge1e4")),
          round(100 * pick(g_all, "coast5", "share_ge1e4")), round(100 * pick(g_all, "mask5", "share_ge1e4")), round(100 * pick(g_all, "coast10", "share_ge1e4")), round(100 * pick(g_all, "hull", "share_ge1e4")),
          length(zeroed), round(100 * pick(g_zero, "mask", "a1e4_vs_hull")), round(100 * pick(g_zero, "coast2", "a1e4_vs_hull")),
          round(100 * pick(g_zero, "coast5", "a1e4_vs_hull")), round(100 * pick(g_zero, "mask5", "a1e4_vs_hull")), round(100 * pick(g_zero, "coast10", "a1e4_vs_hull")),
          length(sel3), fmt_n(pick(g_pos, "mask", "added_1e4_km2")), fmt_n(pick(g_pos, "coast2", "added_1e4_km2")), fmt_n(pick(g_pos, "coast5", "added_1e4_km2")),
          fmt_n(pick(g_pos, "mask5", "added_1e4_km2")), fmt_n(pick(g_pos, "coast10", "added_1e4_km2")), fmt_n(pick(g_pos, "current", "a1e4_km2"))),
  "",
  sprintf("## The %d headline months, the two low_vs_hull months and the two control months (`tables/hybrid_months_issue8.csv`)", length(headline)),
  "",
  "Bloom area >= 10,000 cells/L (km2) by variant:",
  "",
  md_table(round_km2(wide_block("a1e4_km2", show_months)), 0),
  "",
  "Water samples >= 10,000 cells/L inside the footprint, by variant (the month's total is the `current` row's denominator, `n_ge1e4` in the tables):",
  "",
  md_table(cbind(wide_block("in_ge1e4", show_months), n_ge1e4 = cur$n_ge1e4[match(show_months, cur$yrmo)])),
  "",
  "## Checks",
  "",
  "- Every hybrid equals the current map outside its set and the cell-wise maximum of the current and hull-clipped maps inside it; never below the current map, never above that maximum; an empty set reproduces the current map and the whole domain the full union.",
  "- The sets are nested (coast2 in coast5 in mask5 in coast10; mask in mask5), so bloom areas are monotone; no hybrid removes a cell.",
  "- Per-month water-sample counts by class equal the step-1 month table; the counts of samples >= 10,000 cells/L on water and inside the current footprint equal the #6 month table; the step-1 `in_final_fp` flag is reproduced.",
  sprintf("- Control months by the rule (no #6 flag, >= %d%% of the samples >= 10,000 cells/L inside, hull ratio %.2f to %.2f, the two highest shares): %s.",
          round(100 * control_rule$min_frac_in_fp), control_rule$hull_ratio[1], control_rule$hull_ratio[2], paste(control_months, collapse = ", ")),
  "")
writeLines(hdr2, file.path(dir_cmt, "hybrid_summary.md"))
cat(hdr2, sep = "\n")

# Figures ---------------------------------------------------------------------------
add_col <- grDevices::adjustcolor("orangered", 0.4)
draw_variant_panel <- function(v, cur, main, extra = NULL, cex_info = 0.5) {
  base_panel(main); rect(xlim[1], ylim[1], xlim[2], ylim[2], col = "white", border = NA)
  image(xs, ys, to_z(v), breaks = brks_img, col = color, add = TRUE, useRaster = TRUE)
  if (!is.null(cur)) {
    d <- ifelse(!is.na(v) & ((v > 0 & cur == 0) | (v == 0 & cur > 0)), 1, NA)
    if (any(!is.na(d))) image(xs, ys, to_z(d), col = add_col, add = TRUE, useRaster = TRUE)
  }
  draw_land(); info_box(c(class_lines(class_counts_v(v)), extra), cex = cex_info); box()
}
row_of <- function(ym, k) long[long$yrmo == ym & long$variant == k, ]
draw_row <- function(ym, tag = "") {
  lab <- paste0(substr(ym, 1, 4), "-", substr(ym, 5, 6)); r <- t5[t5$yrmo == ym, ]
  draw_samples_panel(ym, sprintf("%s%s: samples", lab, tag))
  g <- row_of(ym, "current")
  draw_variant_panel(V[, ym], NULL, sprintf("current: %s km2 (VIIRS %s, %d cells)", fmt_n(round(g$a1e4_km2)), r$viirs_status, r$viirs_n_pos_cells),
                     extra = sprintf(">= 10k samples inside: %d / %d", g$in_ge1e4, g$n_ge1e4))
  for (k in hybrids) {
    g <- row_of(ym, k)
    draw_variant_panel(maps[[k]][, ym], V[, ym], sprintf("%s: %s km2 (+%s)", k, fmt_n(round(g$a1e4_km2)), fmt_n(round(g$added_1e4_km2))),
                       extra = c(sprintf("inside: %d / %d; +%d cells", g$in_ge1e4, g$n_ge1e4, g$added_cells),
                                 sprintf("+%s km2 masked, +%s valid", fmt_n(round(g$added_1e4_km2_masked)), fmt_n(round(g$added_1e4_km2_valid)))))
  }
  g <- row_of(ym, "hull")
  draw_variant_panel(Hm[, ym], V[, ym], sprintf("hull: %s km2", fmt_n(round(g$a1e4_km2))),
                     extra = sprintf("inside: %d / %d; drops %s km2 of VIIRS fp", g$in_ge1e4, g$n_ge1e4, fmt_n(round(g$removed_fp_km2))))
}

# Fig 5: the five sets on the map.
png(file.path(dir_fig, "fig5_nearshore_sets.png"), width = 17, height = 7.6, units = "in", res = 150)
par(mfrow = c(2, 5), mar = c(2.5, 2.8, 2.6, 0.6), oma = c(0, 0, 2.2, 0))
set_col <- c("white", "orangered", "gold", "mediumpurple", "gray55")
for (zoom in c(FALSE, TRUE)) for (k in hybrids) {
  s <- N[[k]]
  cat5 <- ifelse(land, NA, ifelse(atl5, 4, ifelse(s & N$mask, 1, ifelse(s, 2, ifelse(N$mask, 3, 0)))))
  xl <- if (zoom) c(-83.6, -81.4) else xlim; yl <- if (zoom) c(26.0, 28.6) else ylim
  base_panel(if (zoom) sprintf("%s, zoom", k) else sprintf("%s: %d cells, %s km2 (%d%% in the mask)", k, sum(s), fmt_n(round(sum(cell_km2[s]))), round(100 * mean(N$mask[s]))),
             xl, yl, axes = TRUE)
  image(xs, ys, to_z(cat5), breaks = c(-0.5, 0.5, 1.5, 2.5, 3.5, 4.5), col = set_col, add = TRUE, useRaster = TRUE)
  draw_land()
  if (zoom) abline(v = seq(-87.5, -81, 0.1), h = seq(25, 30.5, 0.1), col = "gray70", lwd = 0.3)
  if (!zoom && k == "mask") legend("bottomleft", legend = c("in the set and in the VIIRS mask", "in the set only", "in the VIIRS mask only", "outside the Gulf domain", "template land", "coastline (Natural Earth 1:10m)"),
                                   fill = c(set_col[2:5], "gray82", NA), border = c(rep("gray40", 5), NA), lty = c(rep(NA, 5), 1), col = c(rep(NA, 5), "gray30"),
                                   cex = 0.7, bg = "white", box.col = "gray60")
  box()
}
mtext("Nearshore sets handed to the hull: the VIIRS no-data mask, the Gulf water cells within 2, 5 and 10 km of the coast, and mask5 = mask or within 5 km (bottom row: zoom with the 0.1-degree VIIRS grid)",
      outer = TRUE, cex = 0.9, font = 2, line = 0.6)
invisible(dev.off())

# Fig 6 and the monthly PDF are vector output: the coastline is drawn simplified to
# coast_tol_m (invisible at 8 panels per row) to keep the files small. draw_land()
# reads `coast` from the global environment; it is restored after the monthly PDF.
coast_full <- coast
coast <- suppressWarnings(sf::st_simplify(coast_full, dTolerance = coast_tol_m))

# Write a PDF to a temporary file and rename it into place, so a copy open in a
# viewer does not kill the run (pattern of check_clipping_issue6.R). draw() draws
# every page; returns TRUE when the file was written.
write_pdf <- function(file_pdf, width, height, draw) {
  file_tmp <- sub("\\.pdf$", "_tmp.pdf", file_pdf)
  opened <- tryCatch({ pdf(file_tmp, width = width, height = height, onefile = TRUE); TRUE },
                     error = function(e) { warning("Cannot open ", file_tmp, ": ", conditionMessage(e), call. = FALSE); FALSE })
  if (!opened) return(invisible(FALSE))
  tryCatch(draw(), finally = invisible(dev.off()))
  if (file.exists(file_pdf) && !file.remove(file_pdf)) {
    warning("Could not replace ", file_pdf, " (open in a viewer?); the new file is ", file_tmp, call. = FALSE)
    return(invisible(FALSE))
  }
  file.rename(file_tmp, file_pdf)
  invisible(TRUE)
}

# Fig 6: headline, low_vs_hull and control months, 8 panels per month, as a PDF
# of fig6_per_page months per page.
fig6_rows  <- show_months
fig6_pages <- split(fig6_rows, ceiling(seq_along(fig6_rows) / fig6_per_page))
draw_fig6_page <- function(ch, i) {
  par(mfrow = c(fig6_per_page, 8), mar = c(0.4, 0.5, 1.5, 0.5), oma = c(0.3, 0, 4.2, 0))
  for (ym in ch) draw_row(ym, paste0(" [", tag_of(ym), "]"))
  mtext(sprintf("Hybrid footprints, %d headline months of #6 + two low_vs_hull + two control months (page %d of %d): samples | current | mask | coast2 | coast5 | mask5 | coast10 | hull",
                length(headline), i, length(fig6_pages)),
        outer = TRUE, cex = 0.95, font = 2, line = 2.8)
  mtext("km2 in the titles = bloom area >= 10,000 cells/L (+ = added to the current map). Orange = cells where the variant differs from the current map (hybrids: cells the hull adds; hull column: cells where the hull and VIIRS footprints differ).",
        outer = TRUE, cex = 0.72, line = 1.5)
  mtext("Samples: fill = FWC class, border = VIIRS cell status (red masked, black valid-0, blue valid+). Map colours as the pipeline PDFs, white below 10,000 cells/L.",
        outer = TRUE, cex = 0.72, line = 0.4)
}
file_fig6 <- file.path(dir_fig, "fig6_hybrid_headline.pdf")
if (write_pdf(file_fig6, width = 18, height = 2.4 * fig6_per_page + 1.2,
              function() for (i in seq_along(fig6_pages)) draw_fig6_page(fig6_pages[[i]], i)))
  message("Fig 6 written: ", file_fig6, " (", length(fig6_pages), " pages, ", round(file.size(file_fig6) / 1e6, 1), " MB)")

# Fig 7: per-month bloom area and sample coverage by variant, 2012-2024.
vcol <- c(current = "black", mask = "orangered", coast2 = "gold3", coast5 = "darkorange3", mask5 = "purple3", coast10 = "saddlebrown", hull = "gray40")
vlty <- c(current = 1, mask = 1, coast2 = 1, coast5 = 1, mask5 = 1, coast10 = 1, hull = 2)
vlwd <- c(current = 2.2, mask = 1.6, coast2 = 1.2, coast5 = 1.4, mask5 = 1.6, coast10 = 1.6, hull = 1.4)
xpos <- match(months, all_months)
series <- function(col, k) { y <- rep(NA_real_, length(all_months)); y[xpos] <- long[[col]][long$variant == k]; y }
png(file.path(dir_fig, "fig7_hybrid_area_2012-2024.png"), width = 13, height = 9.5, units = "in", res = 150)
par(mfrow = c(3, 1), mar = c(2.8, 4.2, 2.2, 0.6), oma = c(0, 0, 1.8, 0), mgp = c(2.6, 0.6, 0))
panels <- list(list(col = "a1e4_km2", lab = "bloom area >= 10,000 cells/L (km2)", main = "Bloom area at or above 10,000 cells/L"),
               list(col = "a1e5_km2", lab = "bloom area >= 100,000 cells/L (km2)", main = "Bloom area at or above 100,000 cells/L"),
               list(col = "share_ge1e4", lab = "share of samples inside", main = "Share of the water samples >= 10,000 cells/L inside the footprint (months with at least 5 such samples)"))
for (p in panels) {
  Y <- sapply(variants, function(k) series(p$col, k))
  if (p$col == "share_ge1e4") { few <- series("n_ge1e4", "current") < 5; Y[few, ] <- NA }
  ymax <- if (p$col == "share_ge1e4") 1 else max(Y, na.rm = TRUE) * 1.05
  plot(NA, xlim = c(0.5, length(all_months) + 0.5), ylim = c(0, ymax), xlab = "", ylab = p$lab, main = p$main, cex.main = 0.95, axes = FALSE, xaxs = "i")
  zero_m <- which(vz == "zero"); miss_m <- which(vz == "missing")
  rect(zero_m - 0.5, 0, zero_m + 0.5, ymax, col = grDevices::adjustcolor("gray40", 0.15), border = NA)
  rect(miss_m - 0.5, 0, miss_m + 0.5, ymax, col = grDevices::adjustcolor("red", 0.25), border = NA)
  for (k in variants) if (p$col == "share_ge1e4") points(seq_along(all_months), Y[, k], col = vcol[[k]], pch = if (k == "current") 16 else 1, cex = 0.7) else
                       lines(seq_along(all_months), Y[, k], col = vcol[[k]], lty = vlty[[k]], lwd = vlwd[[k]])
  jan <- which(substr(all_months, 5, 6) == "01"); axis(1, at = jan, labels = substr(all_months[jan], 1, 4), cex.axis = 0.85); axis(2, las = 1, cex.axis = 0.85); box()
  if (p$col == "a1e4_km2") legend("topleft", legend = c(variants, "VIIRS layer all zero", "VIIRS tif missing"), col = c(vcol, NA, NA), lty = c(vlty, NA, NA), lwd = c(vlwd, NA, NA),
                                  fill = c(rep(NA, 6), grDevices::adjustcolor("gray40", 0.15), grDevices::adjustcolor("red", 0.25)), border = NA, cex = 0.75, bg = "white", box.col = "gray60", ncol = 2)
}
mtext(sprintf("Current map vs the five hybrids and the hull-clipped map, %d-%d; shaded = VIIRS layer all zero, red = no tif (2022-12)", viirs_era[1], viirs_era[2]),
      outer = TRUE, cex = 0.9, font = 2, line = 0.4)
invisible(dev.off())

# The monthly PDF: all VIIRS months, one calendar year per page ---------------------------
page_chunks <- split(months, substr(months, 1, 4))
draw_month_page <- function(ch) {
  par(mfrow = c(rows_per_page, 8), mar = c(0.4, 0.5, 1.5, 0.5), oma = c(0.3, 0, 2.0, 0))
  for (ym in ch) draw_row(ym, { t <- tag_of(ym); if (nzchar(t)) paste0(" [", t, "]") else "" })
  mtext(sprintf("%s   |   samples  |  current  |  mask  |  coast2  |  coast5  |  mask5  |  coast10  |  hull   (km2 = bloom area >= 10,000 cells/L; orange = cells where the variant differs from the current map)", substr(ch[1], 1, 4)),
        outer = TRUE, cex = 1, font = 2, line = 0.5)
}
page_w <- 18; page_h <- 2.4 * rows_per_page + 0.9
if (monthly_pdf) {
  file_pdf <- file.path(dir_docs, "hybrid_months_issue8.pdf")
  if (write_pdf(file_pdf, width = page_w, height = page_h, function() for (ch in page_chunks) draw_month_page(ch)))
    message("Monthly PDF written: ", file_pdf, " (", length(page_chunks), " pages, ", round(file.size(file_pdf) / 1e6, 1), " MB)")
}
coast <- coast_full
cat("\nStep 2 done.\n")
