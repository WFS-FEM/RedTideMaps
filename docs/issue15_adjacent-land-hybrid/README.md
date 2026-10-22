# Issue #15: the land-adjacent nearshore rule on the Ecospace basemap

Examination for [WFS-FEM/RedTideMaps#15](https://github.com/WFS-FEM/RedTideMaps/issues/15), the test Holden asked for before the [#5](https://github.com/WFS-FEM/RedTideMaps/issues/5) call: an alternative to the `mask5` nearshore set of [#8](https://github.com/WFS-FEM/RedTideMaps/issues/8), [#11](https://github.com/WFS-FEM/RedTideMaps/issues/11) and [#10](https://github.com/WFS-FEM/RedTideMaps/issues/10). The rule: a water cell of the Ecospace basemap that shares an edge or a corner with a land cell is nearshore; in satellite months (VIIRS or MODIS) those cells take the sdmTMB projection unclipped; hull months are untouched. Two questions: does the set cover the cells the VIIRS no-data mask hides (if not, adapt the rule), and what the rule does to the metrics (in-situ samples included, total exposure, cells added at >=10k, >=100k and >1M cells/L). Branch `15-test-adjacent-land-cells-hybrid`, 22 October 2026. The plan, with the decisions it rests on, is `issue15-adjacent-land-plan.md`.

**Nothing in the pipeline changes here, and no pipeline run is needed.** The check script prototypes every variant from the stacks the last run left on disk and from the local copies of the #11 and #10 runs. The tracked deliverables (`out/5min/ecospace_ascii/`, `out/5min/plots/`) stay the 6 October 2026 maps; the #5 call then chooses between `mask5` and a rule from here, and only then does a rule go into the pipeline.

## What is compared

The land cells of the basemap are the NODATA cells of `template rasters/depth 5min 66x78.asc`, which is numerically the EcospaceBasemap grid `output/5min/depth/depth_5min.asc` (asserted cell for cell at run time). The Gulf domain is every water cell outside the Atlantic-side box east of -82 E and north of 28.5 N, which is always excluded (the pipeline drops its samples and VIIRS does not cover it).

| variant | nearshore set | fill inside the set, satellite months |
|---|---|---|
| `v6oct` | none | the satellite-clipped layer (the delivered maps) |
| `mask5` | `mask5` (VIIRS no-data mask or within 5 km of the coast; 136 cells) | max(satellite-clipped, hull-clipped), both sensors (#11 and #10) |
| `adj8_sdm` | land-adjacent (edge or corner), the issue's rule | the raw sdmTMB projection |
| `adj8m_sdm` | land-adjacent or in the VIIRS no-data mask | the raw sdmTMB projection |
| `adj8_hull` | land-adjacent | max(satellite-clipped, hull-clipped), the `mask5` fill |

## How to run

```
# no pipeline run; needs out/5min/sdm/, out/5min/clipped/ and VIIRS/ from the last run,
# the nearshore_mask_mask5.grd of a run with a nearshore rule on, the 6 Oct 2026 combined
# stack in docs/issue11_nearshore-hybrid-pipeline/hoard/before/combined/, the run-B
# combined stack in docs/issue10_modis-nearshore-hybrid/hoard/after/combined/, and the
# EcospaceBasemap checkout beside this repository (env RT_BASEMAP_DEPTH overrides the path)
RT_QA_STAGE=examine Rscript docs/issue15_adjacent-land-hybrid/check_adjacent_hybrid_issue15.R   # RT_QA_PNG_DIR=<dir> adds PNG previews of fig 3
```

## Files

(filled in with the results)

## Results

(pending: checkpoint 1)
