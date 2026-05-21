# Archive

Historical workflow scripts. Kept for reference. The canonical entry point is `../run_redtide_maps.R`.

| File | Notes |
|---|---|
| `make red tide maps 202509.R` | Sept 2025 monolithic workflow. |
| `make red tide maps 202510.R` | Oct 2025 monolithic workflow. |
| `make red tide maps 202603.R` | Mar 2026 monolithic workflow. Last pre-refactor copy. |
| `make red tide maps - example.R` | Earlier "example" workflow referenced from the old README. Superseded by `../run_redtide_maps.R`. |

These all source the legacy globals pattern (`<<-`, `setwd()`, etc.) and will not work against the refactored function files in `../scripts/`.
