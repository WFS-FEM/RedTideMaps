# Issue #10: the nearshore hybrid for the MODIS months

Examination, implementation and checks for [WFS-FEM/RedTideMaps#10](https://github.com/WFS-FEM/RedTideMaps/issues/10), the follow-up of [#8](https://github.com/WFS-FEM/RedTideMaps/issues/8) and [#11](https://github.com/WFS-FEM/RedTideMaps/issues/11) under [#5](https://github.com/WFS-FEM/RedTideMaps/issues/5). Issue #11 put the `mask5` nearshore rule into the pipeline for the 155 VIIRS months; this issue asks whether the 123 months served from MODIS nFLH polygons (2002-07 to 2011-12, 2022-12, 2025-01 to 2025-09) need the same, examines it from the stacks on disk, and, on a go, applies the same set and rule to them behind `cfg$modis_nearshore`. Branch `10-modis-nearshore-hybrid`, October 2026. The plan, with the decisions it rests on and a preview of the numbers, is `issue10-modis-hybrid-plan.md`.

**Status (22 October 2026): step 1 (examine) in progress; nothing in the pipeline has changed yet.** The tracked deliverables (`out/5min/ecospace_ascii/`, `out/5min/plots/`) are still the 6 October 2026 maps.

## How to run

```
# from the repo root; needs the stacks of the last pipeline run in out/5min/ and the
# nearshore_mask_mask5.grd of a "mask5" run (issue #11)
RT_QA_STAGE=examine Rscript docs/issue10_modis-nearshore-hybrid/check_modis_hybrid_issue10.R
```

## Files

| File | What |
|---|---|
| `issue10-modis-hybrid-plan.md` | the plan: context and preview numbers, GitHub workflow, the four steps, verification |
| `check_modis_hybrid_issue10.R` | the check script (stage `examine` first; the other stages follow the pipeline change) |
| `tables/`, `figures/`, `comments/` | written by the script; listed here as the stages land |

## Results

Filled in at checkpoint 1 (examine) and checkpoint 2 (runs and checks).
