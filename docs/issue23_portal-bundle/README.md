# Issue #23: the data bundle for WFS-Portal

The producer side of [WFS-FEM/RedTideMaps#23](https://github.com/WFS-FEM/RedTideMaps/issues/23) (Holden, 3 Nov 2026), the issue that asks for an R Shiny visualization tool and data portal for the monthly red tide maps. The decisions taken during planning (`issue23-portal-bundle-plan.md`, D1 to D18) put the application in a new repository, [WFS-FEM/WFS-Portal](https://github.com/WFS-FEM/WFS-Portal) (to be created at step P0 of the plan), built as the future integrated portal for the Ecospace outputs with the red tide maps as its first product, and leave this repository one job: write, at the end of every pipeline run, a tracked, data-only bundle of the delivered maps that the portal fetches at a pinned commit. The bundle is specified in `bundle-schema.md` (schema 1.0) and lives at `out/<res>min/bundle/`, beside the Ecospace ASCII files it describes. Branch `23-portal-bundle`, [PR #24](https://github.com/WFS-FEM/RedTideMaps/pull/24), November 2026.

**The tracked deliverables (`out/5min/ecospace_ascii/`, `out/15min/ecospace_ascii/`, the plots beside them) do not change in this issue.** The bundle is a new deliverable derived from them, written text for text from the ASCII files plus the run's own outputs (the clipping method of each month, the FWC samples, the fit records, the nearshore set). One rule of the project is applied in the bundle that the delivered maps do not yet apply: the Atlantic-side box (east of -82 E, north of 28.5 N) carries no data, so the bundle omits its cells and every metric runs over the Gulf domain (decision D19, 4 Nov 2026); zeroing the box in the delivered maps is a separate issue after this one (D20).

## What changed in the pipeline

- **`scripts/write_bundle.R`** (new): `fn.write_bundle()`, step 9 of the driver, and its helpers (`fn.read_ascii_dir`, `fn.layer_summary`, `fn.band_counts`, `fn.n_changed`, `fn.samples_table`, `fn.fmt_num`, `fn.write_csv_lf`, `fn.write_json_lf`, `fn.write_text_lf`, `fn.md5_lf`, `fn.md5_string`, `fn.git_state`, `fn.bundle_style`, `fn.bundle_manifest`, `fn.assert_no_cr`, `fn.rel_to_repo`). It reads the ASCII files of the run as text (the deliverable; the NODATA token below -1e30), the template, `clipping_source.csv`, the filtered FWC samples, the unclipped stack, the raw VIIRS stack, the VIIRS- and MODIS-clipped stacks, the fit record, the nearshore raster and the hull diagnostics, and compares its values with the combined stack (within tolerance, the stack being float32); treats the Atlantic-side box as land (D19); computes the monthly summary; writes the bundle to `out/<res>min/bundle_tmp/` through binary connections (LF, 15-digit numbers with the 17-digit fallback, the character columns quoted), reads every table back and asserts it identical to what was computed, rebuilds the values matrix and asserts it identical to the ASCII text on the domain, asserts no carriage return or non-ASCII byte, refuses a nearshore raster that contradicts the run and a samples file without the expected object, then swaps the folder into place (the previous bundle restored if the swap fails). Every optional input that is missing leaves `NA` in the columns derived from it. 37 s inside the pipeline run of 4 Nov 2026 (11 to 35 s standalone, depending on the load on the machine).
- **`run_redtide_maps.R`**: the step-9 line of the header, `cfg$write_bundle` (default `TRUE`), the source line, a guard that records `cfg$viirs_nearshore` as `"none"` when a run has no VIIRS stack (so the bundle's metadata states the rule applied), `nearshore <- NULL` before the nearshore block (a run with both rules `"none"` assigned no such object), and the step-9 block after the optional export, before `Run complete.`; one run-log line names the bundle, its months, placeholders, domain cells, samples, files, size, the ASCII commit (with a "modified, not yet committed" suffix on a monthly run) and the seconds.
- **`scripts/_setup.R`**: `rt_paths()` gains `bundle`.
- **`config.local.example.R`**: `cfg$write_bundle <- FALSE` for an experimental run whose maps will not be committed.
- **`.gitignore`**: `out/*/bundle/` tracked, as `ecospace_ascii/` and `plots/` are.
- **The deliverables are unchanged**: the verification run of 4 Nov 2026 (FWC samples frozen) rewrote the ASCII files byte for byte and the plots PDFs by their date lines only (restored before the commits).

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
| `tables/bundle_rerun5_issue23.csv` | per file, the md5 of the bundle under check and of the rerun, `equal` (stage `rerun`; the resolution in the name) |
| `tables/bundle_files5_issue23.csv` | file, bytes, rows of every file of the bundle, the manifest included (step 4) |
| `figures/fig1_bundle_quicklook5_issue23.png` | four months drawn from the bundle's own files with base `image()` (land and the Atlantic-side box from `grid.csv`, the maps from `values/`, the samples from `samples/`, the counts from `summary/`, the palette from `style.json`): the orientation and the self-sufficiency of the files (step 4) |
| `figures/fig2_summary_record5_issue23.png` | the exposure and the cells at or above 10k cells/L, 1985 to 2026, from `summary/redtide.csv`, the clip source shaded (step 4) |
| `.gitignore`, `comments/` | `hoard/` and the comment drafts (`issue23-*-comment.md`) are ignored; `comments/` holds the drafts |
| `hoard/` (gitignored) | local copies the stages read: `trial/` (the writer called standalone at step 2), `rerun/` (stage `rerun`) |

## Results

### Step 2: the writer against the run on disk (4 Nov 2026)

The writer called standalone against the run of 23 October 2026 (the delivered maps; `hoard/trial/bundle`) passes every assertion. The check script's frozen stage on that trial: all 29 assertions pass, and its tables are the ones under `tables/` except the two the step-5 run regenerated (below). Reviewed by four read-only reviewers (schema conformance, an independent recomputation of every month, R and Windows pitfalls, the hook); their findings applied and re-tested.

### Step 5: the pipeline run and the tracked bundle (4 Nov 2026)

The pipeline run with the FWC samples frozen (`cfg$fwc_refresh <- FALSE`; 38 min on a machine short of memory, against about 9 min usually) rewrote the 504 ASCII files byte for byte (the gate of the check script: the LF digest equals the frozen digest of the #18 refresh run) and wrote `out/5min/bundle/` in step 9 in 37 s, with a clean provenance (`ascii_commit` 543bc8e, `ascii_dirty` false). From the tables the check script wrote against the tracked bundle:

| What | Value | Table |
|---|---|---|
| Files, bytes | 94 files, 9,936,086 bytes of LF text (`.gitattributes` and the manifest included) | `bundle_files5_issue23.csv` |
| Values | 51,872 positive cell-months on the 3,782 cells of the Gulf domain, in 42 year files; 173 of the 504 months all zero | `bundle_files5_issue23.csv`, `bundle_vs_issue18_issue23.csv` |
| Samples | 181,411 rows in 42 year files (93 off the grid, none in the Atlantic-side box) | `bundle_files5_issue23.csv` |
| Against the #18 class-count table | all 504 months equal once the Atlantic-box contribution is added back (D19): the positives, the five classes, the exposure (largest difference 5.1e-7 cells/L), the clip source, the fit and VIIRS status, the cells changed, the sample positives and classes | `bundle_vs_issue18_issue23.csv` |
| The Atlantic-side box in the delivered maps | positive cells in 94 months (2,503 cell-months, 1.05% of the record's exposure), all MODIS-served; the bundle carries no data there | `bundle_vs_issue18_issue23.csv` (`box_*` columns) |
| Against the #18 record table | 502 of 504 months equal on the cells and km2 at or above 10k, the cells at or above 100k and 1M cells/L, the maximum, the samples at or above 10k and how many the map includes; the two months the October refresh changed (202609, 202610) differ, as expected | `bundle_vs_record_issue23.csv` |
| Rerun | the writer called standalone reproduces the tracked bundle byte for byte in 92 of 94 files; `meta.json` differs in `build.built_at`, `build.run_log`, `build.mode` and the volatile `source` keys only, and `manifest.csv` in the row that hashes it | `bundle_rerun5_issue23.csv` |
| Frozen counts (asserted) | clip source hybrid 155 / viirs 0 / hybrid_modis 123 / modis 0 / pred 226; 210 months changed by the nearshore rule (n_changed > 0 exactly there); fit status fitted 331 / failed 5 / none 168; converged 328 TRUE / 3 FALSE / 173 NA; hull_flagged exactly the ten months of the run log (199009, 199604, 199606, 199711, 199909, 200009, 200010, 200110, 200112, 200201), NA in the 19 months without samples; placeholders 202611 and 202612 | the `expected` list of the script |
| 2018-09 | exposure 310,492,554 cells/L; 648 positives (0 / 0 / 127 / 450 / 71 by class); 648 cells at or above 10k over 49,160 km2; maximum 7,746,619 cells/L at cell 2864; 32 cells changed by the nearshore rule; 1,026 samples, 525 positive (54 / 105 / 132 / 158 / 76), 290 at or above 10k with 289 inside the map | `bundle_vs_issue18_issue23.csv`, `bundle_vs_record_issue23.csv` |

The figures: `fig1_bundle_quicklook5_issue23.png` draws 2018-09, 2012-02, 2005-10 and 2026-10 from the bundle's own files (the orientation, the land and the box from `grid.csv`, the samples, the count boxes), `fig2_summary_record5_issue23.png` the exposure and the cells at or above 10k cells/L over the record with the clip source shaded. Only `meta.json` and its manifest row differ between the pipeline's bundle and the standalone trial of step 2.

A note for the first monthly rerun after this issue: the gate closes (the maps change), the two #18 comparisons stop running, and the writer-independent checks (the values against the ASCII text, the key metrics recomputed, the samples) carry the verification from then on.

## Checks the script enforces

`check_bundle_issue23.R` reads only the run on disk, the tracked #18 tables and the bundle, never sources the driver (the configuration comes from the bundle's `meta.json`), and writes its tables and figures byte-identically on rerun. It stops at the first failure.

Stage `frozen`:

1. **The gate.** A line-ending-independent digest of the ASCII files (the `ascii_md5` the writer computes) equals the frozen digest of the #18 refresh run of 23 October 2026, so the maps on disk are the delivered ones; the raw md5s of the #18 refresh table are reported as a fact (a CRLF checkout differs from an LF one there). When the digest differs (a later run), the #18 comparisons (4, 5, 7) do not run and their stale tables are removed.
2. **The files.** The file set equals `manifest.csv` (`.gitattributes` included, C-locale order) and every md5 and byte count matches, both raw and after removing carriage returns (so the files are LF on disk); no carriage return or non-ASCII byte in any file; when the bundle is tracked and the working copy equals HEAD, every md5 equals the git blob; `ascii_md5.csv` equals the LF md5 and byte count of the ASCII files on disk and `meta.source.ascii_md5` is their concatenated digest (the staleness guard); `meta.grid` equals the template header; `grid.csv` equals the template cell for cell (rows, columns, centers, depths, water, domain, the Atlantic-box flag, km2); the nearshore cells equal the run's mask raster, lie outside the box, and equal the #18 set table of the resolution; `layers.csv` names one layer, `redtide`, `long_sparse`, with its values and samples files present for every year; `months.csv` holds the contiguous months of the run with year and month as the key; `style.json` carries the band columns of the summary, the labels in k and M, 402 palette colors and the band breaks.
3. **The values.** The matrix rebuilt from the year files is identical to the text of every ASCII file on the Gulf domain; every row is a domain cell, unique within its month, strictly positive, sorted; the rebuilt values are within a relative 1e-9 of every cell of the GDAL float32 reading of the ASCII files and of the combined stack; the exposure, the bands, the thresholds, the maximum and its cell recomputed in the script with its own arithmetic equal the summary in every month; the bands sum to the positives and the positives to the value rows. The contribution of the Atlantic-side box in the delivered maps is reported (D19).
4. **Against `clip_class_counts_hybrid_issue18.csv`** (5 arcmin, behind the gate), all 504 months: the bundle's positives, five bands and exposure plus the box's own contribution equal the table's `final_*` columns (exposure within 1e-3 cells/L); the clip source, the derived satellite source, the hybrid flag, the fit and VIIRS status and the cells changed equal; the sample positives and bands equal the `fwc_*` columns. Table `bundle_vs_issue18_issue23.csv`.
5. **Against `record_months_issue18.csv`** (5 arcmin, behind the gate): the cells and km2 at or above 10k, the cells at or above 100k and 1M cells/L, the maximum and the samples at or above 10k and how many the map includes equal the `*_final` columns in the 502 months the October refresh did not change; the two refreshed months are reported. Table `bundle_vs_record_issue23.csv`.
6. **The samples.** The file on disk is the one the bundle names; the sample rows equal the filtered file's rows with a count in the product years, with the cell of `raster::cellFromXY()`; the per-month counts equal `n_samples`; no sample lies in the box; the placeholder months are exactly the months after the last sample month.
7. **The frozen counts** of the run of 23 October 2026 (5 arcmin, behind the gate), quoted under Results, and the files table `bundle_files<res>_issue23.csv`.

Then the two figures, drawn from the bundle's own files only.

Stage `rerun`: the writer is called standalone, with the configuration and the inputs the bundle names, into `hoard/rerun/bundle`; the same files; every file byte-identical except `meta.json` (only `build.built_at`, `build.run_log`, `build.mode` and the volatile `source` keys differ) and the manifest row that hashes it; no carriage return or non-ASCII byte. Table `bundle_rerun<res>_issue23.csv`.
