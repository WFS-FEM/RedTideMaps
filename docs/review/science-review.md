# Science and Objectives Review: RedTideMaps

## 0. Header

```
Repository: WFS-FEM/RedTideMaps (main at a875d64). Original authors: Daniel Vilas (sdmTMB
and clipping code), David Chagaris (PI, workflow design), Holden Harris (operationalisation).
Reviewer: Holden Harris, with Claude Code. Date: 6 Oct 2026.
Status: draft (review-only audit; Phase 2 orientation, to be corrected in Phase 5).
Cite as: Harris, H. E. (2026). Science and Objectives Review: RedTideMaps. docs/review/science-review.md, WFS-FEM/RedTideMaps.
Version history: 2026-10-06 first draft (review-only audit, docs/review/draft-repo-audit-log.md).
```

Sources are cited in square brackets: `[file:line]` for code, `[README "section"]`, `[commit sha]`, `[plan §n]` for `docs/issue3-hull-fix-plan.md`, `[run 2026-09-30]` for the intermediates left by the last pipeline run on the reviewer's machine (`out/5min/`), and `[unexplained]` where neither the code nor the documentation gives a reason.

## 1. Summary

RedTideMaps produces one map per month of *Karenia brevis* concentration, in cells per litre, on the West Florida Shelf Ecospace grid (5 arc-minute cells, 66 rows by 78 columns, 87.5°W to 81°W and 25°N to 30.5°N), for every month from January 1985 to December of the current year [`template rasters/depth 5min 66x78.asc`; `run_redtide_maps.R:40-44`]. The maps are written as ESRI ASCII rasters and are the red-tide spatial-temporal driver of the WFS Ecospace model [README "Pipeline"; Vilas et al. 2023].

Each map is built in two parts. A species-distribution model (sdmTMB) is fitted separately for each year and month to the positive in-situ cell counts from FWC's harmful algal bloom monitoring, and predicts an expected concentration at every grid cell [`scripts/sdmTMB_HAB_data.R:61-320`]. That prediction is then masked to the bloom footprint for the month, taken from the best available source: VIIRS satellite red-tide frequency (2012 to 2024), else MODIS fluorescence-line-height polygons (July 2002 to September 2025), else buffered hulls around the positive samples themselves [`scripts/polygon_clipping_rt.R:195-245`; README "Why the clipping cascade"].

Two things a user of the outputs must know. First, the map value is the model's expected concentration *given that the month's bloom footprint covers the cell*, multiplied by a 0/1 footprint; it is not a probability-weighted expectation. Second, a month is modelled only when it has more than five positive samples; months with one to five positives (87 of the 421 months with any positive since 1985) and months whose fit failed (5) are written as all-zero maps [`scripts/sdmTMB_HAB_data.R:118`, `302-306`; run 2026-09-30].

## 2. Objectives

**Product.** Monthly *K. brevis* concentration surfaces on the Ecospace grid, as ASCII drivers, from FWC cell counts, satellite bloom products and a species-distribution model, with a monthly rerun that an operator can run unattended from the command line [README "Pipeline", "Monthly rerun"].

**Consumer and what it needs.** The WFS Ecospace model (Ecopath with Ecosim, Vilas et al. 2023; operational update under the NOAA RESTORE project "Operationalizing the West Florida Shelf ecosystem model", PI Chagaris) reads one ASCII file per month as a spatial-temporal driver. In the model, red tide acts through a direct mortality response (logistic in cells/L, inflection points 50,000 to 400,000 cells/L) and a foraging-avoidance response (inflection 12,500 to 300,000 cells/L) [plan §5, citing Chagaris et al. 2025 and Vilas et al. 2023]. So the consumer needs: cells/L units; the Ecospace 5-min grid and no-data convention; a complete monthly series from the model start year (1985) with no gaps; and a value of zero, not missing, where there is no bloom.

**What "correct" means.** The repository states no numerical acceptance test for the maps. The working definition used in the previous fix was byte-identity of every month the change should not touch, plus visual inspection of the monthly panel PDF for the months it should [plan §8]. This review adopts the same standard and adds: every zero map must have a stated cause (no samples, too few positives, failed fit, or an empty satellite footprint).

**Scope and non-goals.** The pipeline estimates concentration maps. It does not estimate red tide mortality (that happens in Ecospace), does not forecast, and does not validate the maps against independent data; an accuracy-evaluation script exists but is not wired in [`scripts/experimental/README.md`].

## 3. Introduction and context

*K. brevis* blooms on the West Florida Shelf cause fish kills and change fish behaviour, and the WFS ecosystem model represents both as functions of cell concentration. The model runs monthly from 1985, so it needs a monthly concentration map for every month since then, including the decades before satellite bloom products exist and the months after the latest satellite product has been published [plan §1, §5].

The code has three generations [git history]. Monolithic scripts by Daniel Vilas (`archive/make red tide maps *.R`, September 2025 to March 2026) chained MODIS extraction, polygon building, sdmTMB fitting, clipping and ASCII writing with global state. In May 2026 the workflow was refactored into one driver and six function files, the FWC ingest was rewritten to pull from the ArcGIS REST API, and the repository was made standalone [`f6e0cf2`, `d99fe33`]. In September 2026 two fixes landed through pull requests: fresh-clone portability (a tracked project file, a gitignored local config, an up-front package check, an opt-in Ecospace export; PR #2) and a replacement of the k-means hull clustering that was producing spurious coast-long polygons in satellite-free months (issue #3, PR #4) [`69fad70`, `baa7dc8`, `23a5935`].

Related work: the Ecospace model and its red-tide response functions (Vilas et al. 2023; Chagaris et al. 2025, SEDAR 88 working paper); the VIIRS red-tide products of the USF Optical Oceanography Laboratory (Hu et al. 2015; Yao et al. 2023); the MODIS nFLH bloom detection method (Hu et al. 2005). Sibling repositories under WFS-FEM (EcospaceBasemap, GFISHER) produce the other Ecospace inputs on the same grid; this pipeline reads its grid template from a copy of the basemap depth layer shipped in `template rasters/` [README "Inputs"; provenance of the templates: unexplained].

## 4. Data sources

| Source | Provider and method | Coverage used | Vintage in the repository | Limitations known to the code | Access |
|---|---|---|---|---|---|
| FWC HAB cell counts | Florida Fish and Wildlife Conservation Commission, Fish and Wildlife Research Institute. In-situ water samples, *K. brevis* cells/L, with date, position and depth. Served as six ArcGIS REST layers (1980s, 1990s, 2000-2006, 2007-2014, 2015-2023, 2024-present) | 1980-01-02 to 2026-09-17 in the local cache; modelled from 1985 | Pulled at every run; local merged CSV refreshed incrementally from the "Recent" layer only | Late additions or corrections to older records are not picked up by an incremental pull [README "Known limits"]; counts at or below 1,000 cells/L are "background" in FWC's own scale but count as positive here [plan §3] | Public API; `data/FWC HAB API query urls.txt` |
| VIIRS monthly red-tide frequency | USF Optical Oceanography Laboratory with NOAA; monthly rasters at 0.1° giving the frequency of red-tide detection (README calls them probability rasters) | 2012-01 to 2024-12; December 2022 is missing (PNG present, TIF absent), so that month falls through to MODIS | Shipped in the repository (155 GeoTIFFs); no download code | The code overwrites each file's georeferencing with the fixed WFS box and flips it vertically [`scripts/process_VIIRS.R:34-36`]; the threshold "any cell > 0 is bloom" is the code's choice [unexplained] | Tracked; original URL not recorded |
| MODIS nFLH bloom polygons | NASA MODIS Aqua normalised fluorescence line height from NOAA CoastWatch ERDDAP, thresholded at 0.02 mW cm⁻² µm⁻¹ sr⁻¹ and dissolved to polygons per month | 2002-07 to 2025-09 | Pre-built polygon list shipped as one Rdata (built 26 Sept 2025); raw rasters not tracked, rebuildable with `update_modis` | Threshold per Hu et al. 2005 updated to 0.02 by personal communication [`scripts/process_MODIS.R:11-13`]; the ERDDAP dataset discovery is heuristic (string filters on titles) | Tracked polygons; ERDDAP public |
| Grid templates | Depth and exclusion ASCII rasters for 4, 5, 6, 10 and 15 arc-minute grids | 5 min used by default; 15 min supported | Tracked | Source and vintage of the templates: unexplained; the exclusion layer is loaded but never used [`scripts/sdmTMB_HAB_data.R:21-24`] | Tracked |
| Coastline | Natural Earth 1:50m countries via `rnaturalearth` | Plotting only | Package data | None | Package |
| HABSOS archive (NOAA NCEI) | Historical *K. brevis* observations compiled by NCEI | Not read by the driver; a download helper exists [`scripts/get_HAB_data.R:180-215`] | Two CSVs tracked in `data/` (30 MB), April 2024 vintage; used only by the issue #3 emulation [plan §4] | Not used | Tracked |

## 5. Scientific methods

### 5.1 Ingest and spatial filter (stage 1-2)

All six FWC layers are paged through the REST API and merged; duplicates are removed on the key (HAB_ID, OBJECTID, SAMPLE_DATE, latitude, longitude) [`scripts/get_HAB_data.R:150-152`]. Observations are then kept if they fall inside the depth template's bounding box and outside an Atlantic-side exclusion box (82°W to 80.5°W, 28.5°N to 31°N) [`scripts/get_HAB_data.R:273-295`]. Points on land (estuaries, rivers) are deliberately kept; a comment records that land polygons are no longer used to exclude them [`:259`]. On the 30 Sept 2026 run this left 183,133 observations for 1980-2026, of which 39,908 are positive (cells > 0) [run 2026-09-30]. A positive sample is any count other than zero; FWC's own "background" class (up to 1,000 cells/L) is included, which the previous fix flagged as a science question for the author [plan §6.4].

### 5.2 Prediction grid (stage 3a)

The prediction grid is the set of cell centres of the depth template; a per-cell area in km² is computed with a spherical formula but not used downstream [`scripts/sdmTMB_HAB_data.R:24-40`]. The exclusion template is passed in but unused.

### 5.3 Monthly species-distribution models (stage 3b)

For every (year, month) with more than five positive samples, an intercept-only spatial model is fitted with sdmTMB to the positive samples only: `cells ~ 1`, a lognormal observation family, a spatial Gaussian random field on an SPDE mesh with cutoff 0.1° (about 11 km), and no spatiotemporal term [`scripts/sdmTMB_HAB_data.R:118-176`]. The fit is attempted twice on failure, which cannot change the outcome because nothing in the fit is random: four fits of the same month with different seeds and with none gave identical parameters, as did the fit cached on 30 Sept [Doc C §3, S1]. An optional second model (negative binomial type 2 on all samples, zeros included) is off by default and is not used downstream [`run_redtide_maps.R:70`].

Assumptions implied by this choice: concentration given presence is log-normally distributed around a smooth spatial surface; the surface is stationary and isotropic within the month; samples are independent given the field; sampling locations are not informative beyond their values (FWC sampling is event-driven, so this is doubtful during blooms); and there is no information shared between months or years. None of these is stated in the code or README [assumptions not stated]. The threshold of more than five positives, the mesh cutoff, and the absence of covariates (depth is available in the grid) are parameter choices with no recorded justification [unexplained].

Diagnostics saved per fit: relative RMSE and MAE of in-sample predictions, AIC, a hand-computed AICc whose parameter count includes every random-effect node (so k can exceed n), the negative log-likelihood, and "convergence" meaning the optimiser's return code was zero [`:243-258`]. Warnings during fitting are captured to a CSV [`:181-189`]. On the last run, 334 months were fitted, 326 converged by this criterion, 3 did not, and 5 produced no model after two attempts; 2,011 warnings were captured, 1,852 of them "NA/NaN function evaluation" [run 2026-09-30]. The optimiser's return code is a weak criterion: sdmTMB's own `sanity()` checks, run on the 334 cached fits for this review, pass only 229 of them (80 fail the Hessian check, 79 have missing standard errors, 92 have a variance parameter at a bound), and the pass rate falls with sample size: 33% of months with ten or fewer positives, 43% for 11 to 30, 69% for 31 to 100, 97% above 100 [Doc C §3, M4]. A month that fails these checks still produces a map.

### 5.4 Prediction to the grid (stage 4)

Each fitted model predicts the response-scale mean at every cell centre, which is rasterised onto the template [`:235-241`, `:343-357`]. Months without a model get an all-zero layer by way of a code path that writes zeros into the longitude and latitude columns of the prediction array and so trips the "insufficient spatial data" branch; verified on the stored array, where every column of January 1985 is zero [`:275-277`, `:362-369`; Doc C B3]. The result is a stack of 504 monthly layers of predicted cells/L, unmasked, extending across the whole shelf wherever a fit exists.

### 5.5 Bloom footprint and clipping cascade (stage 5-6)

The unmasked prediction can cover the entire shelf even when the bloom is local, so each month is masked to a footprint [README "Why the clipping cascade"]. Three footprints are built, and one is chosen per month:

1. **Buffered hulls** (every month with at least one positive). Positive samples are grouped by single-linkage clustering cut at 75 km; each cluster with at least four distinct locations gets a concave hull (concavity 2), smaller clusters get the points themselves, and every footprint is buffered by 10 km, all in UTM zone 17N [`scripts/polygon_clipping_rt.R:60-150`]. The 75 km cut, the buffer and the minimum were set in the issue #3 fix with a sensitivity case at 50 km [plan §6.2, §6.5]. A per-month diagnostics file records cluster counts, footprint area and span, and flags spans over 300 km.
2. **VIIRS** (2012-01 to 2024-12 except 2022-12). Cells with frequency greater than zero are dissolved to a polygon; a month whose VIIRS layer is entirely zero gets an all-zero map even if in-situ positives exist [`scripts/process_VIIRS.R:114-119`]. This is not a corner case: 89 of the 155 VIIRS months have no positive cell, 58 of those had a fitted model, and 14 had a hundred or more positive samples (January to April 2017 with 274, 320, 258 and 168; June 2021 with 376) [Doc C §3, M1]. The product's 0.1° cells may not resolve the nearshore and estuarine samples that dominate those months; whether a satellite non-detection should override them is a methods question (§7).
3. **MODIS nFLH** (2002-07 to 2025-09). The pre-built polygons are rasterised on the template and used as the mask [`scripts/process_MODIS.R:175-200`].

Preference per month is VIIRS, else MODIS, else hull [`scripts/polygon_clipping_rt.R:215-218`]. On the last run this gave 155 VIIRS, 123 MODIS and 226 hull months out of 504 [run 2026-09-30]. Inside the footprint the cell keeps the model's value; outside it the cell is zero; land cells are no-data. So the final map is E[cells/L | model, positive samples] × 1{cell in footprint}.

### 5.6 Output (stage 7)

One ASCII per month, `sdmTMB_log__<yyyymm>.asc`, on the template grid, with no-data written as -3.4e+38 (the template uses -9999) [run 2026-09-30; `template rasters/depth 5min 66x78.asc`]. Months after the latest sample (October to December 2026 on the last run) are written as zero maps so that every calendar year is complete.

## 6. Results

The product is 504 monthly maps for 1985 to 2026 on the 5-min grid, committed in `out/5min/ecospace_ascii/` from the 30 Sept 2026 run (data through 2026-09-17). The example figure in the README (September 2018, `example_201809.png`) shows what a modelled bloom month looks like: predicted concentrations up to several million cells/L along the southwest coast inside the VIIRS footprint, zero elsewhere on the shelf, land in grey. What to look for in any month: whether the coloured area sits where samples were taken that month (`plots/sample locations by year.png`), whether its edge follows a satellite footprint (blocky 0.1° cells) or a hull (rounded 10 km buffers), and whether a month that should be quiet is quiet.

**Where each month's map comes from** (30 Sept run; Doc B §9 for the 6 Oct repeat):

| Months 1985-2026 | Count | Footprint | Map content |
|---|---|---|---|
| VIIRS month with a positive cell | 66 | VIIRS polygon | model prediction inside, zero outside |
| VIIRS month with no positive cell | 89 | none | all zero, whatever the samples (58 had a fitted model) |
| MODIS month (2002-07 to 2011-12, 2025-01 to 2025-09, plus 2022-12) | 123 | nFLH polygon | model prediction inside, zero outside |
| Hull month with a converged model | 114 | buffered hulls | model prediction inside, zero outside |
| Hull month whose fit failed | 3 | buffered hulls | all zero |
| Hull month not modelled: 33 with one to five positives, 76 with none | 109 | hull or none | all zero |
| Total | 504 | | |

(MODIS months: 93 converged, 1 not converged, 1 failed, 28 not modelled. VIIRS months: 119 converged, 2 not converged, 1 failed, 33 not modelled; the 89 all-zero VIIRS months cut across these.) Fit status over the whole range: 334 months with at least six positives were fitted; by the code's criterion 326 converged, 3 did not and 5 failed; by sdmTMB's `sanity()` 229 are sound (§5.3). In-sample relative RMSE of the fitted months has median 2.29 (quartiles 1.31 and 3.50), so the monthly surfaces reproduce the sampled values only roughly; this is expected for an intercept-only spatial model fitted to a few dozen event-driven samples and is not by itself a defect.

**QC the code performs.** The hull diagnostics flag months whose largest footprint spans more than 300 km; on the 30 Sept run 10 of the 226 hull-served months were flagged (1990-09, 1996-04, 1996-06, 1997-11, 1999-09, 2000-09, 2000-10, 2001-10, 2001-12, 2002-01) and the run log names them. Fit warnings are captured to a file. Nothing else is checked.

**Verification against the committed outputs.** Pending the 6 Oct baseline (Doc B §9.1). Expected drift: the incremental FWC pull advanced the data from 2026-09-17 to 2026-09-22, so the September 2026 fit and map may differ; every other month should be byte-identical because the pipeline is deterministic (Doc B §6).

## 7. Discussion

**Intended use.** The maps are a driver for a monthly ecosystem model, not an estimate of bloom extent or biomass in their own right. Read a cell value as "the concentration a sample would likely have shown here, if this cell was inside the month's bloom footprint", and a zero as "outside the footprint or not modelled". The model's responses are logistic in cells/L with inflection points from 12,500 to 400,000 cells/L (§2), so what matters most downstream is which cells are non-zero and whether they sit above or below those thresholds.

**Caveats, ranked by how much they could move a downstream result** (each has a Doc C row):

1. **Satellite non-detection overrides sampled blooms (M1).** 58 modelled months in 2012-2024 are written as zero because the VIIRS layer has no positive cell; several are documented blooms with hundreds of positive samples (early 2017, June 2021). For those months Ecospace sees no red tide at all.
2. **Months with one to five positives are zero maps (M2).** 87 such months since 1985. Most are quiet months, but the rule is a literal in the code and is not documented.
3. **Fits that fail sdmTMB's sanity checks are used (M4).** 100 of 329 fits; concentrated in months with few positives, which are also the months where a single sample can dominate the surface.
4. **"Positive" includes background counts (M3, carried over from issue #3).** A sample of 1,000 cells/L or less defines a footprint and enters the lognormal fit alongside 10⁶ cells/L samples.
5. **The model specification is unexamined (M5).** Intercept-only, no depth, nothing shared across months; mesh cutoff 0.1°. Alternatives (a depth covariate, a shared spatial field with monthly deviations, a delta model that estimates presence instead of masking it) were not tried in the current code; `scripts/experimental/` holds abandoned kriging and IDW variants.
6. **Future months are zeros (M6).** The current year's remaining months are written as "no red tide".
7. **The no-data value differs from the template (R6)** and two satellite months are silently missing (R1). Neither changes a value, but both should be stated where the outputs are described.

**Methods questions for the author** (mirrored in Doc C §8): for each of M1 to M5, the options are laid out in Doc C; the arithmetic is unchanged in this review so that the committed maps stay comparable.

**Suggested scientific follow-ups.** (a) Decide the VIIRS override rule, for example "VIIRS footprint, unioned with the hull footprint of any month with at least k positives". (b) Expose the positive threshold and the mesh cutoff in `cfg` and run the sensitivity. (c) Replace the convergence flag with `sanity()` and decide what a failing month gets (zero, hull-filled mean, or the previous month). (d) Open the positive-definition issue promised in issue #3. (e) Validate against the held-out samples the code already pairs (`pred_obs_RT.RData`) using the dormant `scripts/experimental/accuracy_evaluation.R`.

## 8. References

- Chagaris, D., et al. 2025. Red tide mortality in the West Florida Shelf ecosystem model. SEDAR 88 working paper. [cited from plan §5]
- Hu, C., Muller-Karger, F. E., Taylor, C., Carder, K. L., Kelble, C., Johns, E., and Heil, C. A. 2005. Red tide detection and tracing using MODIS fluorescence data: a regional example in SW Florida coastal waters. Remote Sensing of Environment 97: 311-321. https://doi.org/10.1016/j.rse.2005.05.013
- Hu, C., Barnes, B. B., Qi, L., and Corcoran, A. A. 2015. A harmful algal bloom of *Karenia brevis* in the northeastern Gulf of Mexico as revealed by MODIS and VIIRS: a comparison. Sensors 15: 2873-2887. https://doi.org/10.3390/s150202873
- Vilas, D., Chagaris, D., et al. 2023. Red tide effects on the West Florida Shelf ecosystem. Scientific Reports. https://www.nature.com/articles/s41598-023-29327-z
- Yao, Y., et al. 2023. VIIRS red tide products for the West Florida Shelf. Remote Sensing of Environment. https://doi.org/10.1016/j.rse.2023.113833
- Anderson, S. C., Ward, E. J., English, P. A., and Barnett, L. A. K. 2022. sdmTMB: an R package for fast, flexible, and user-friendly generalized linear mixed effects models with spatial and spatiotemporal random fields. bioRxiv. https://pbs-assess.github.io/sdmTMB/
- Park, J.-S. and Oh, S.-J. 2012. A new concave hull algorithm and concaveness measure for n-dimensional datasets. Journal of Information Science and Engineering 28: 587-600. [concaveman]
- FWC red tide status scale: https://myfwc.com/research/redtide/statewide/
- Repository history: WFS-FEM/RedTideMaps issues #1, #3; pull requests #2, #4; `docs/issue3-hull-fix-plan.md`.

## 9. Appendices

### 9.1 Glossary (to be completed in Phase 5)

| Term in the code | Meaning | Units |
|---|---|---|
| `cells`, `COUNT_` | *K. brevis* cell concentration from an FWC water sample | cells per litre |
| `fit_sdmTMBlog` | lognormal sdmTMB model on positive samples for one (year, month) | |
| `pred_array` | predicted concentration at each grid cell, per model, month and year | cells per litre |
| `pol_list` | per-month buffered footprint polygons from positive samples | EPSG:4326 |
| `flh.polys` | per-month MODIS nFLH bloom polygons | |
| `clipping_source.csv` | which footprint each month used (`viirs`, `modis`, `pred` = hull) | |
| `hull_diagnostics.csv` | per-month hull cluster counts, area, span and flag | km², km |

### 9.2 Figures and tables: pending.

### 9.3 Version history: see §0.
