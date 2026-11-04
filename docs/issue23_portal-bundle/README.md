# Issue #23: the data bundle for WFS-Portal

The producer side of [WFS-FEM/RedTideMaps#23](https://github.com/WFS-FEM/RedTideMaps/issues/23) (Holden, 3 Nov 2026), the issue that asks for an R Shiny visualization tool and data portal for the monthly red tide maps. The decisions taken during planning (`issue23-portal-bundle-plan.md`, D1 to D18) put the application in a new repository, [WFS-FEM/WFS-Portal](https://github.com/WFS-FEM/WFS-Portal) (to be created at step P0 of the plan), built as the future integrated portal for the Ecospace outputs with the red tide maps as its first product, and leave this repository one job: write, at the end of every pipeline run, a tracked, data-only bundle of the delivered maps that the portal fetches at a pinned commit. The bundle is specified in `bundle-schema.md` (schema 1.0) and lives at `out/<res>min/bundle/`, beside the Ecospace ASCII files it describes. Branch `23-portal-bundle`, PR #NN, November 2026.

**The tracked deliverables (`out/5min/ecospace_ascii/`, `out/15min/ecospace_ascii/`, the plots beside them) do not change in this issue.** The bundle is a new deliverable derived from them, written text for text from the ASCII files plus the run's own outputs (the clipping method of each month, the FWC samples, the fit records, the nearshore set).

## What changed in the pipeline

(Filled in at step 3. Planned, as the plan states:)

- **`scripts/write_bundle.R`** (new): `fn.write_bundle()` and its helpers, step 9 of the driver. It reads the ASCII files of the run (the deliverable), the template, `clipping_source.csv`, the filtered FWC samples, the unclipped stack, the raw VIIRS stack, the VIIRS- and MODIS-clipped stacks, the fit record, the nearshore raster and the hull diagnostics, and compares its values with the combined stack when that is given; computes the monthly summary; writes the bundle to `out/<res>min/bundle_tmp/`, reads every file back and asserts it is identical to what was computed, asserts no carriage return byte, then swaps the folder into place. Run time: measured at step 2 from the `seconds` the writer returns and at step 5 from the run log (the plan's unmeasured estimate is about 10 s on a 9-minute run).
- **`run_redtide_maps.R`**: the step-9 line of the header comment, `cfg$write_bundle` (default `TRUE`), the source line, `nearshore <- NULL` before the nearshore block (a run with both rules `"none"` has no such object), and the step-9 block after the optional export, before `Run complete.`; one run-log line names the bundle, its months, samples, files, size and the ASCII commit.
- **`scripts/_setup.R`**: `rt_paths()` gains `bundle`.
- **`config.local.example.R`**: `cfg$write_bundle <- FALSE` for an experimental run whose maps will not be committed.
- **`.gitignore`**: `out/*/bundle/` tracked, as `ecospace_ascii/` and `plots/` are.

## How to run

`Rscript` is not on the PATH of the machine the pipeline runs on; the commands use the generic name, and the local call is `"C:/Program Files/R/R-4.5.1/bin/x64/Rscript.exe"`.

```
# a pipeline run writes the bundle as its step 9 (cfg$write_bundle TRUE by default):
Rscript run_redtide_maps.R
# the check script, from the repository root (reads the run on disk, the tracked tables and the bundle):
RT_QA_STAGE=frozen Rscript docs/issue23_portal-bundle/check_bundle_issue23.R   # the default stage: files, values, the #18 regression tables, the frozen counts, the figures
RT_QA_STAGE=rerun  Rscript docs/issue23_portal-bundle/check_bundle_issue23.R   # writes the bundle again into hoard/rerun/ and compares byte for byte
# RT_QA_BUNDLE_DIR=<dir> checks a bundle other than the tracked one (the trial of step 2: docs/issue23_portal-bundle/hoard/trial/);
# RT_QA_RES=15 checks out/15min/ and skips the #18 comparisons, which exist at 5 arcmin only.
```

The writer can also be called from the console against the run on disk, without a pipeline run (step 2 of the plan, and a schema change): source `scripts/_setup.R` and `scripts/write_bundle.R`, then `fn.write_bundle(..., mode = "standalone")` with the paths of `rt_paths()`; the appendix of the plan gives the signature (its section 2.1) and the call of step 9 with the paths the pipeline passes (its section 2.2).

## Files

| File | What |
|---|---|
| `issue23-portal-bundle-plan.md` | the plan as approved (4 Nov 2026): the findings, the decisions D1 to D18, the design summary, the step list with checkpoints, the verification; the full design document as its appendix |
| `bundle-schema.md` | the specification of the bundle, schema 1.0, with its version history; written into every bundle as `SCHEMA.md` |
| `check_bundle_issue23.R` | the check script, stages `frozen` and `rerun` (`RT_QA_STAGE`), resolution `RT_QA_RES`, `RT_QA_BUNDLE_DIR` (step 4) |
| `tables/bundle_vs_issue18_issue23.csv` | per month, the bundle's summary beside the `final_*` and `fwc_*` columns of the #18 class-count table, their differences and `equal` (step 4) |
| `tables/bundle_vs_record_issue23.csv` | per month, the threshold metrics beside the #18 record table, `equal`, `refreshed` (step 4) |
| `tables/bundle_rerun_issue23.csv` | per file, the md5 of the tracked copy, of the copy on disk and of the rerun, `equal` (step 5) |
| `tables/bundle_files_issue23.csv` | file, bytes, rows of the tracked bundle (step 4) |
| `figures/fig1_bundle_quicklook_issue23.png` | four months drawn from the bundle alone with base `image()`: the orientation and the self-sufficiency of the files (step 4) |
| `figures/fig2_summary_record_issue23.png` | the exposure and the cells at or above 10k cells/L, 1985 to 2026, from `summary/redtide.csv` (step 4) |
| `.gitignore`, `comments/` | `hoard/` and the comment drafts (`issue23-*-comment.md`) are ignored; `comments/` holds the drafts |
| `hoard/` (gitignored) | local copies the stages read: `trial/` (the writer called standalone at step 2), `rerun/` (stage `rerun`) |

## Results

(Filled in at steps 4 and 5 from the tables the check script writes.)

## Checks the script enforces

(Filled in at step 4. Planned: the file set equals the manifest and every md5 matches, on disk and in the git blob; no carriage return byte; the ASCII md5 guard holds; the grid equals the template; `months.csv` holds the contiguous months of the run with the two placeholder months of today marked; the ASCII md5 gate decides whether the two #18 comparisons run (they are skipped with a message once a later run has changed the maps); the values rebuilt from the year files are identical to the text of every ASCII file and within tolerance of the float32 readings; the summary recomputed from the ASCII equals the written one; all 504 months equal the #18 class-count table on the positives, the five bands, the exposure, the clip source, the fit and VIIRS status, the cells changed and the sample bands; 502 months equal the #18 record table on the threshold metrics, the two months the October refresh changed reported; the samples equal the filtered file; the frozen counts; a rerun byte-identical except the volatile keys.)
