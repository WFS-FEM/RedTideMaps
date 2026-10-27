# RedTideMaps

Monthly red-tide severity rasters for the West Florida Shelf, as input to the **WFS Ecospace** model ([Vilas et al. 2023](https://www.nature.com/articles/s41598-023-29327-z)).

This repository produces monthly maps of *Karenia brevis* cell concentrations (cells / L) across a configurable spatial grid, by combining FWC in-situ cell counts, satellite-derived bloom polygons (VIIRS, MODIS nFLH), and species-distribution modeling with [sdmTMB](https://pbs-assess.github.io/sdmTMB/). Output is one ASCII raster per month, ready to be loaded as a spatial driver in **Ecopath with Ecosim / Ecospace**.

Developed as part of the *Operationalizing the West Florida Shelf ecosystem model and application to red tides, stock assessment, and catch advice for Gulf of Mexico reef fish* project (PI: David Chagaris).

![Example](example_201809.png)

*Example: predicted cells / L for September 2018, during the major K. brevis bloom on the West Florida Shelf.*

---

## Pipeline

```
                ArcGIS REST                                          Ecospace
   FWC HAB  ─────────────►  cell_counts/                             ST drivers
                              │                                          ▲
                              ▼                                          │ (opt)
                       spatial filter ──────► filtered HAB               │
                              │                                          │
                              ▼                                          │
                       sdmTMB monthly fits ──► pred_array                │
                              │                                          │
                              ▼                                          │
                      predict to grid ───────► sdmTMB_log_stack          │
                              │                                          │
                              ▼                                          │
   VIIRS tifs  ─┐                                                        │
   MODIS polys ─┼──► clip cascade (VIIRS > MODIS, +nearshore > hulls)    │
   buffered    ─┘            │                                           │
   hulls                     ▼                                           │
                       combined stack ──────► monthly ASCII ─────────────┘
```

Each step is one function in `scripts/`:

| Step | Function | File |
|---|---|---|
| Pull FWC HAB samples | `fn.get_fwc_data` | `get_HAB_data.R` |
| Spatially filter to the WFS grid | `fn.filter_hab_data` | `get_HAB_data.R` |
| Build prediction grid | `fn.make_input_grid` | `sdmTMB_HAB_data.R` |
| Fit monthly sdmTMB models | `fn.fit_monthly_sdmTMB` | `sdmTMB_HAB_data.R` |
| Predict to grid | `fn.predict_monthly_sdmTMB` | `sdmTMB_HAB_data.R` |
| Buffered concave hulls | `fn.buffered_hulls` | `polygon_clipping_rt.R` |
| Clip predictions to hulls | `fn.clip_2_hulls` | `polygon_clipping_rt.R` |
| Stack VIIRS tifs | `fn.viirs_tifs2stack` | `process_VIIRS.R` |
| Clip predictions to VIIRS | `fn.clip_2_viirs` | `process_VIIRS.R` |
| Nearshore set (VIIRS no-data mask, within 5 km of the coast, or touching a land cell) | `fn.nearshore_mask` | `process_hybrid.R` |
| Add the hull footprint to the VIIRS or MODIS clip inside that set (default; `"none"` switches it off) | `fn.clip_2_hybrid` | `process_hybrid.R` |
| Clip predictions to MODIS nFLH | `fn.clip_2_modis` | `process_MODIS.R` |
| Combine + write ASCII | `make_redtide_ascii` | `polygon_clipping_rt.R` |
| Copy to Ecospace drivers (opt-in) | `export_to_ecospace` | `polygon_clipping_rt.R` |

## Why the clipping cascade

Predicted cell concentrations from sdmTMB can extend across the entire shelf even when no bloom is actually present. The clipping step restricts the prediction to the actual bloom footprint for that month:

- **VIIRS (2012–2024)** — NOAA monthly red-tide probability rasters (0.1°); the tracked tifs run 2012-01 to 2024-12 (155 files) and new months are added by hand. Where any cell is > 0, the prediction in that month is masked to those cells. This is the highest-confidence source.  These maps are developed by the [University of South Florida Optical Oceanography Laboratory](https://optics.marine.usf.edu/). See [Yao et al. (2023)](https://doi.org/10.1016/j.rse.2023.113833) and [Hu et al. (2015)](https://doi.org/10.3390/s150202873) for details.
- **Nearshore hybrid for the VIIRS months (`viirs_nearshore = "mask5adj"`, the default)** — The VIIRS product carries no data in a 0 to about 5 km band along the coast and in the bays (the first row of 0.1° cells), where about two thirds of the FWC samples of every abundance class are taken, so in-situ blooms there never reached a VIIRS-clipped map (issue #8). The pipeline builds a static nearshore set: the water cells of the Gulf domain whose 0.1° VIIRS cell is in that no-data mask, or whose center lies within 5 km of the Natural Earth 1:10m coastline (`data/coastline/`), or that share an edge or a corner with a land cell of the basemap (189 cells, 14,205 km² at 5 arcmin; the rule in full: `docs/issue5_nearshore-hybrid-summary/subissues/issue15_adjacent-land-hybrid/nearshore-set-method.md`), and inside it takes the cell-wise maximum of the VIIRS-clipped and hull-clipped maps; outside it the VIIRS result stands, zeros included. So the sample-based footprint is added nearshore and never removes a VIIRS detection. `"mask5"` is the same set without the touching-land criterion (136 cells; issues #8, #11); `"none"` reproduces the VIIRS-only maps delivered before #18. Decisions in issues #8 and #15, implementation and checks in #11 and #18 (`docs/issue5_nearshore-hybrid-summary/subissues/issue11_nearshore-hybrid-pipeline/`, `docs/issue5_nearshore-hybrid-summary/subissues/issue18_implement-hybrid-clipping/`).
- **MODIS nFLH (2002–2025)** — Normalized fluorescence-line-height rasters thresholded at ≥ 0.02 mW cm⁻² μm⁻¹ sr⁻¹ (per [Hu et al. 2005](https://doi.org/10.1016/j.rse.2005.05.013), updated calibration via Chuanmin Hu, pers. comm.) are dissolved into polygons used as the clipping mask when VIIRS is unavailable.
- **Nearshore hybrid for the MODIS months (`modis_nearshore = "mask5adj"`, the default)** — The same set and rule applied to the months served from MODIS (2002-07 to 2011-12, 2022-12, 2025-01 to 2025-09): inside the set a cell takes the cell-wise maximum of the MODIS-clipped and hull-clipped maps, outside it the MODIS result stands. MODIS has no coastal no-data band, so the change is small in the aggregate, but the coastal strip is then treated the same way in every satellite era. Examination and checks in issue #10 (`docs/issue5_nearshore-hybrid-summary/subissues/issue10_modis-nearshore-hybrid/`).
- **Buffered concave hulls (all years, fallback)** — For months with no satellite coverage, positive in-situ observations define the bloom footprint. Positives are grouped by single-linkage clustering: two samples share a footprint when a chain of positives connects them with every link shorter than `hull_link_km` (default 75 km). Each cluster with at least `hull_min_pts` (4) distinct locations gets a concave hull; smaller clusters get the points themselves; every footprint is buffered by `hull_buffer_km` (10 km). Every month with at least one positive gets a footprint. The rule is deterministic. Each run writes `out/<res>min/sdm/hull_diagnostics.csv` (one row per month: positives, clusters, footprint area and span) and the run log flags months whose largest footprint spans more than `hull_warn_span_km` (300 km), counting only months the hull path actually serves (no VIIRS or MODIS coverage); a flag is a prompt to look at the panel, not a failure.

For each (year, month), the combined stack picks **VIIRS if available** (with the nearshore hull added inside the set unless `viirs_nearshore = "none"`, recorded as `hybrid`), otherwise **MODIS** (likewise unless `modis_nearshore = "none"`, recorded as `hybrid_modis`), otherwise **the buffered-hull-clipped prediction**. The decision per month is logged to `out/<res>min/clipped/clipping_source.csv` (columns `yrmo`, `pred`, `viirs`, `modis`, `hybrid`, `hybrid_modis`, `hybrid_changed` and `use`; `use` is one of `hybrid`, `viirs`, `hybrid_modis`, `modis` or `pred`, the last meaning the hull-clipped prediction, and `hybrid_changed` says whether the hybrid differs from the plain satellite clip that month). The evidence and decisions behind the nearshore hybrid are summarised in `docs/issue5_nearshore-hybrid-summary/README.md`; `docs/README.md` indexes the issue folders.

## Quick start

Requires **R ≥ 4.5** with the packages listed in [Reproducibility](#reproducibility).

```bash
git clone https://github.com/WFS-FEM/RedTideMaps.git
cd RedTideMaps
Rscript run_redtide_maps.R
```

The script finds the repo root itself: run it from the repo folder, open `RedTideMaps.Rproj` in RStudio and source it, or give `Rscript` the full path to `run_redtide_maps.R` from anywhere.

No paths need editing for a basic run. Machine-specific settings, such as the Ecospace export folder, go in a local `config.local.R`, which is gitignored:

```bash
cp config.local.example.R config.local.R   # then uncomment what you need
```

The first run takes about 20 minutes at the default 5-min resolution. It will:
1. Pull the full FWC HAB record from the ArcGIS REST endpoints (~3 min, ~216k records).
2. Filter to the WFS grid.
3. Fit monthly sdmTMB models for every (year, month) with more than 5 positive observations (~7 min).
4. Predict to the depth template grid.
5. Run the clipping cascade.
6. Write 12 ASCII files per year to `out/<res>min/ecospace_ascii/`.

## Monthly rerun

There is nothing to download by hand: the FWC records come from the ArcGIS REST API. (Older versions of this workflow asked for the "Recent HAB" CSV to be downloaded into `cell_counts/`. Don't do that now; `cell_counts/` holds only the merged file the script writes itself.)

1. Run the workflow:

   ```bash
   Rscript run_redtide_maps.R
   ```

2. Check that the run log, `out/<res>min/run_<yyyymmdd>.log`, ends with `Run complete.` Also read its `Hulls:` line, which lists the hull-served months (no satellite coverage) whose footprint spans more than `hull_warn_span_km`: if any are flagged, look at their panels in `out/<res>min/plots/*_clipped_combined.pdf` and at `out/<res>min/sdm/hull_diagnostics.csv` to confirm the footprint is a real coast-wide bloom rather than an artifact.
3. Commit the updated deliverables, `out/<res>min/ecospace_ascii/` and `out/<res>min/plots/`.

If `export_ecospace` is on in `config.local.R`, step 1 also copies the ASCII files to the Ecospace ST drivers folder.

Each rerun:

- Pulls the FWC records dated on or after the latest `SAMPLE_DATE` already in the local merged CSV, from the `Recent_` endpoint only.
- Refits only the (year, month) combinations that don't already have a fit on disk (incremental cache).
- Re-runs predict, hull, VIIRS, MODIS clip, the nearshore hybrid and ASCII for the full year range.

A monthly rerun takes about 9 minutes at 5-min resolution (measured: 8 min 50 s, with 0 months to refit), against about 20 minutes (measured: 19 min) for a first run. Most of that is fixed: steps 2–6 re-filter, re-predict from the cached fits, re-clip and rewrite every month since `styr`, however few records are new. The toggles change it:

| Toggle | Effect on a rerun |
|---|---|
| `fwc_force_full = TRUE` | +~3 min (full FWC pull) |
| `incremental_fit = FALSE` | +~6 min (refits every month) |
| `fit_nb = TRUE` | Roughly doubles fitting time for months that are (re)fit |
| `update_modis = TRUE` | Adds an ERDDAP download; the first one pulls everything since 2002 because the raw MODIS stack is not tracked |
| `export_ecospace = TRUE` | Seconds |

Each month that does need a new fit adds about a second.

**Known limits of the incremental rerun** (to be addressed):

- Records FWC adds or corrects with a `SAMPLE_DATE` earlier than the local latest date are not picked up. To catch them, set `cfg$fwc_force_full <- TRUE` in `config.local.R` for one run (a full pull takes ~3 min).
- A month that already has a fit is not refit when new data for it arrives. Delete its fit folder to force a refit (below).

**To force a refit of a specific month** (e.g., after data corrections):

```bash
rm -rf out/5min/sdm/OM_month/202503
Rscript run_redtide_maps.R
```

**To push the ASCII drop to the Ecospace ST drivers folder**, set `cfg$ecospace_root` and `cfg$export_ecospace <- TRUE` in `config.local.R`. The destination `<ecospace_root>/<res>min/red tide/sdmTMB/` must already exist; the run checks it before doing any work and stops if it is missing.

## Configuration

All knobs live in the `cfg` list at the top of `run_redtide_maps.R`. To change one on your machine only, set it in `config.local.R` (e.g. `cfg$res <- 15L`) rather than editing the driver:

| Key | Default | Purpose |
|---|---|---|
| `res` | `5L` | Output resolution in minutes. Tested at 5 and 15; `template rasters/` also ships templates for 4, 6 and 10. |
| `styr`, `enyr` | `1985`, current year | Year range to model. |
| `repo_dir` | detected automatically | Repo root: the working directory if it holds `RedTideMaps.Rproj`, otherwise the folder `Rscript` was pointed at. |
| `proj_dir` | `repo_dir` | Where inputs and outputs live. Override if data is outside the repo. |
| `bathy_dir` | `<repo>/template rasters` | Where the depth + excl ASCII templates live. |
| `ecospace_root` | `NULL` (set in `config.local.R`) | Ecospace "ST drivers" root, the target for `export_to_ecospace()`. |
| `use_viirs` | `TRUE` | Include VIIRS clipping. `FALSE` also needs `modis_nearshore = "none"` (the nearshore set is read from the VIIRS stack), or the run stops at the config check. |
| `use_modis` | `TRUE` | Include MODIS nFLH clipping (requires shipped FLH polys). `FALSE` also needs `modis_nearshore = "none"`, or the run stops at the config check. |
| `update_modis` | `FALSE` | Pull/update raw MODIS FLH from ERDDAP before clipping. Needs network. |
| `rebuild_nflh` | `FALSE` | Rebuild FLH polygons from raw stack. Set with `update_modis`. |
| `fwc_force_full` | `FALSE` | Ignore the local FWC CSV cache and pull every endpoint again. |
| `incremental_fit` | `TRUE` | Skip months that already have a fit on disk. Delete `OM_month/<yyyymm>/` to force a refit. |
| `fit_nb` | `FALSE` | Also fit the NB2 spatial model in addition to lognormal. Only lognormal is used downstream, so leaving this `FALSE` roughly halves cold-run fit time. |
| `export_ecospace` | `FALSE` | After the run, copy `ecospace_ascii/` into `<ecospace_root>/<res>min/red tide/sdmTMB/`. |
| `hull_link_km` | `75` | Buffered-hull fallback: single-linkage cut distance in km. Positives farther apart than this, with no chain of closer positives between them, get separate footprints. 50 km is the "only where sampled" sensitivity case. |
| `hull_buffer_km` | `10` | Buffer in km around each hull footprint. |
| `hull_min_pts` | `4L` | Distinct locations a cluster needs for a concave hull; smaller clusters get buffered points. |
| `hull_concavity` | `2` | `concaveman` concavity for every hull (lower = tighter). |
| `hull_warn_span_km` | `300` | Months whose largest footprint spans more than this are flagged in `sdm/hull_diagnostics.csv` and the run log. |
| `viirs_nearshore` | `"mask5adj"` | Nearshore hybrid for the VIIRS months. `"mask5adj"` adds the buffered-hull footprint inside the nearshore set (VIIRS no-data mask, within 5 km of the coast, or touching a land cell; 189 cells at 5 arcmin), taking the cell-wise maximum there; `"mask5"` uses the set without the touching-land criterion (136 cells); `"none"` uses the VIIRS-clipped map as it is. The run log names the rule, the set and the months it changed. |
| `modis_nearshore` | `"mask5adj"` | The same rule for the months served from MODIS nFLH polygons, with the same values (needs `use_viirs` and `use_modis`; both keys name the same set when both are on). |
| `fwc_refresh` | `TRUE` | Set `FALSE` to reuse the local merged FWC CSV without querying FWC, so a rerun sees exactly the samples of the previous run (reproducibility checks). A first run still pulls everything. |

## Inputs

**Tracked in the repo** (run from a fresh clone works without any external paths):

- `VIIRS/redtide_maps_0.1degree/*.tif` — NOAA monthly red-tide probability rasters (2012-01 to 2024-12, 155 tifs, with a PNG preview beside each).
- `MODIS/FLH polys *.Rdata` — pre-built nFLH-threshold polygons (2002-07 to 2025-09).
- `template rasters/depth *.asc`, `excl layer *.asc` — depth + exclusion templates for 4, 5, 6, 10, and 15-minute resolutions.
- `data/FWC HAB API query urls.txt` — list of 6 FWC ArcGIS REST endpoints.
- `data/coastline/ne_10m_coastline_wfs.gpkg` — Natural Earth 1:10m coastline cropped to the grid box, used by the nearshore set (source and date in the README beside it).

**Pulled from the FWC ArcGIS REST API** (not committed; the first run pulls every endpoint, later runs only the `Recent_` endpoint, and `fwc_refresh = FALSE` skips the query):

- `cell_counts/FWC HAB data <yyyymmdd>-<yyyymmdd>.{csv,Rdata}` — merged in-situ K. brevis cell counts from FWC.

## Outputs

```
out/<res>min/
  sdm/
    *_filtered.Rdata        # spatially filtered HAB observations
    OM_month/<yyyymm>/      # per-month sdmTMB fits (fit_sdmTMBlog.RData [+ fit_sdmTMBnb.RData])
    pred_SDMs_RT.RData      # 4-D pred_array (cell × model × month × year)
    RT_fit_matrix.RData     # convergence + RRMSE/MAE/AIC per (year, month, model)
    pred_obs_RT.RData       # observation-vs-prediction pairs
    fit_warnings.csv        # captured sdmTMB warnings with (year, month, model) context
    sdmTMB_log_stack_*.grd  # monthly prediction stack (cells/L)
    *_hullpolys.Rdata       # per-month buffered hull footprints
    hull_diagnostics.csv    # per-month hull QA: positives, clusters, footprint area and span, flagged
    plots/                  # sdm convergence.png and the fit-metric PNGs (rrmse, mae, aic, nll)
  clipped/
    *_clipped_hull.grd      # predictions masked to buffered hulls
    *_clipped_viirs.grd     # predictions masked to VIIRS positive cells
    *_clipped_modis.grd     # predictions masked to MODIS nFLH polygons
    nearshore_mask_<rule>.grd  # the nearshore set (1 nearshore, 0 other water): nearshore_mask_mask5adj.grd by default
    *_clipped_hybrid.grd    # VIIRS clip with the hull added inside the set; unless viirs_nearshore = "none"
    *_clipped_hybrid_modis.grd  # the same for the MODIS-served months; unless modis_nearshore = "none"
    clipping_source.csv     # per-month decision: hybrid / VIIRS / hybrid_modis / MODIS / hull, and whether the hybrid changed the month
  combined/
    *_clipped_combined.grd  # final merged stack (hybrid > VIIRS > hybrid_modis > MODIS > hull)
  ecospace_ascii/
    sdmTMB_log__<yyyymm>.asc  # one ASCII per month — the deliverable
  plots/
    sample locations by year.png
    N samples over time.png
    sdmTMB log maps.pdf
    *_clipped_combined.pdf
    hull_check_issue3.pdf   # 5 min only; written by scripts/qa/check_hulls_issue3.R, not the pipeline
  run_<yyyymmdd>.log        # the run log
```

Each run regenerates the contents. Only the deliverables, `ecospace_ascii/` and `plots/`, are tracked in git; the intermediates (`sdm/`, `clipped/`, `combined/`, run logs) are gitignored. Files named after an earlier FWC date range (`*_filtered.Rdata`, `*_hullpolys.Rdata`) or an earlier rule (`nearshore_mask_<rule>.grd`) are not removed by a later run.

## Reproducibility

Tested with **R 4.5.1** on Windows 11.

Required packages (CRAN unless noted): `sf`, `raster`, `terra`, `rnaturalearth`, `rnaturalearthdata`, `sdmTMB`, `lubridate`, `concaveman`, `cluster`, `ggplot2`, `viridis`, `scales`, `cowplot`, `ggh4x`, `maps`, `fields`, `rvest`, `httr`, `jsonlite`. The run checks for these first and, if any are missing, stops with the `install.packages()` line to fix it.

Optional (only for `update_modis = TRUE`): `rerddap`, `curl`, `data.table`, `rasterVis`, `colorRamps`.

Install with:

```r
install.packages(c(
  "sf","raster","terra","rnaturalearth","rnaturalearthdata","sdmTMB","lubridate",
  "concaveman","cluster","ggplot2","viridis","scales","cowplot",
  "ggh4x","maps","fields","rvest","httr","jsonlite"))
```

`sdmTMB` is version-sensitive (depends on TMB); if you hit fit/predict issues, check the installed `sdmTMB` version matches the model object stored in `OM_month/`. A safe move is to delete the affected month's `OM_month/<yyyymm>/` folder and let the next run refit under the current version.

## Authors

- [David Chagaris](https://github.com/dchagaris) — PI, workflow design
- [Daniel Vilas](https://github.com/danielvilasgonzalez) — original sdmTMB and clipping code
- [Holden Harris](https://github.com/holden-harris) — operationalization

## License

MIT — see [LICENSE](LICENSE).
