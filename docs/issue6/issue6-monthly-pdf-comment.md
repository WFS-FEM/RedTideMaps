## Monthly comparison PDF: every month, one row, five maps (PR #7)

**Method.** The same script as before, [`scripts/qa/check_clipping_issue6.R`](https://github.com/WFS-FEM/RedTideMaps/blob/aa9eaee/scripts/qa/check_clipping_issue6.R), now also draws [`docs/issue6/clip_months_issue6.pdf`](https://github.com/WFS-FEM/RedTideMaps/blob/aa9eaee/docs/issue6/clip_months_issue6.pdf). Nothing is refit or re-clipped: each row is read from the stacks the 6 Oct 2026 run left on disk (the unclipped sdmTMB surface, the VIIRS-, MODIS- and hull-clipped stacks, `clipping_source.csv`) and from the filtered FWC samples. Maps use the palette and breaks of the pipeline PDFs (white below 10,000 cells/L, 10,000 to 4,000,000 on the colour bar). Footprint outlines are the pipeline's own objects, the dissolved positive VIIRS cells, the MODIS nFLH polygons and the buffered hulls, simplified to 1 km for drawing only. The run takes about 50 s and its outputs are byte-identical from run to run.

**What is on a page.** All 504 months from 1985-01 to 2026-12, twelve rows per page so each page is one calendar year (42 pages; the page of a month is its year minus 1984). The five columns of a row:

| Col | Panel |
|---|---|
| A | FWC samples of the month, filled by abundance class (legend bottom-left) |
| B | sdmTMB prediction, unclipped |
| C | prediction clipped to the VIIRS positive cells |
| D | prediction clipped to the MODIS nFLH polygons |
| E | prediction clipped to the buffered hulls |

The clipped panel the final map actually uses has a red frame (VIIRS if a tif exists for the month, else MODIS, else hulls, the current cascade). Every panel carries a count box with the positives and the five FWC classes (at most 1,000; 1,000 to 10,000; 10,000 to 100,000; 100,000 to 1,000,000; above 1,000,000 cells/L): samples in column A, grid cells of that map in columns B to E. Each raster panel has its own cells/L colour bar. A month with no samples, no fit, no VIIRS tif or no MODIS polygon keeps its row with a note in the empty panel, so the sequence is unbroken. The count-box numbers for every month and map are also in [`clip_class_counts_issue6.csv`](https://github.com/WFS-FEM/RedTideMaps/blob/aa9eaee/docs/issue6/clip_class_counts_issue6.csv) (columns `<map>_<class>`, maps `fwc`, `unclip`, `viirs`, `modis`, `hull`, `final`).

**Example, 2012-01 to 2012-04** ([`fig5_monthly_rows_example.png`](https://github.com/WFS-FEM/RedTideMaps/blob/aa9eaee/docs/issue6/fig5_monthly_rows_example.png)):

![Example rows 2012-01 to 2012-04](https://raw.githubusercontent.com/WFS-FEM/RedTideMaps/aa9eaee/docs/issue6/fig5_monthly_rows_example.png)

Reading it: in 2012-01 the VIIRS layer has positive cells, so the final map (red frame) keeps 85 cells, 9 of them at or above 100,000 cells/L, from a fitted surface that covers the shelf. In 2012-02 to 2012-04 the VIIRS layer is all zero, so the final map is all zero (0 positives in the red-framed panel) although the hull clip of the same surface would keep 83, 146 and 49 cells and the MODIS clip 189, 113 and 101; in 2012-03 the hull-clipped map holds 13 cells at or above 100,000 cells/L next to 8 samples in that class. This is the pattern behind #5, visible month by month.

**Files** (all in [`docs/issue6/`](https://github.com/WFS-FEM/RedTideMaps/tree/aa9eaee/docs/issue6); the per-month four-panel PDF from the first pass, `clip_check_issue6.pdf`, is kept there too for now):

| File | What |
|---|---|
| [`clip_months_issue6.pdf`](https://github.com/WFS-FEM/RedTideMaps/blob/aa9eaee/docs/issue6/clip_months_issue6.pdf) | the monthly PDF, 42 pages, 7.5 MB |
| [`clip_class_counts_issue6.csv`](https://github.com/WFS-FEM/RedTideMaps/blob/aa9eaee/docs/issue6/clip_class_counts_issue6.csv) | the count-box numbers, one month per row |
| [`fig5_monthly_rows_example.png`](https://github.com/WFS-FEM/RedTideMaps/blob/aa9eaee/docs/issue6/fig5_monthly_rows_example.png) | the four rows above |
| [`README.md` §1.3](https://github.com/WFS-FEM/RedTideMaps/blob/aa9eaee/docs/issue6/README.md#13-the-monthly-pdf-clip_months_issue6pdf) | how to read the PDF and the CSV |

To regenerate everything: `Rscript scripts/qa/check_clipping_issue6.R` from the repo root (`RT_QA_PDF=0` skips the older per-month PDF; `RT_QA_MONTHLY_PDF=0` skips this one).
