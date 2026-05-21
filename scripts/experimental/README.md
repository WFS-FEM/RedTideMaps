# Experimental scripts

These files are not part of the canonical monthly workflow (`run_redtide_maps.R`). They are kept here for reference and possible future use.

| File | Status | Notes |
|---|---|---|
| `IDW_HAB_data.R` | Unused | Inverse distance weighting alternative to sdmTMB. Functional but not currently sourced by the main workflow. |
| `ordkrig_HAB_data.R` | Incomplete | Simple ordinary kriging. Back-transformation step not finished. |
| `anisokrig_HAB_data.R` | Incomplete | Anisotropic kriging variant. |
| `accuracy_evaluation.R` | Not wired in | Obs-vs-pred accuracy diagnostics; never integrated into the main workflow. |
| `extract MODIS flh from errdap.R` | Superseded | Standalone MODIS FLH ERDDAP extraction. Now provided as `fn.pull_MODIS_flh_erddap()` inside `../process_MODIS.R`. |

Sourcing these directly will likely fail without the legacy globals set by the old monolithic workflow scripts.
