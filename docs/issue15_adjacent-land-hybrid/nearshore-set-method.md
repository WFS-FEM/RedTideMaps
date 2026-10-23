# The nearshore set: how the cells are chosen

Decision of 22 October 2026 (Holden, [issue #15](https://github.com/WFS-FEM/RedTideMaps/issues/15)), after [#8](https://github.com/WFS-FEM/RedTideMaps/issues/8), [#11](https://github.com/WFS-FEM/RedTideMaps/issues/11), [#10](https://github.com/WFS-FEM/RedTideMaps/issues/10) and #15 under [#5](https://github.com/WFS-FEM/RedTideMaps/issues/5). This page states the rule in full so that it can be cited and reproduced. The set it defines is `tables/nearshore_set_issue15.csv` (189 cells) and `figures/fig5_nearshore_set_issue15.png`; the check script `check_adjacent_hybrid_issue15.R` builds both and asserts every count below.

## Why a nearshore set

In the months served from a satellite product (VIIRS from 2012, MODIS nFLH before it and where VIIRS is missing), the monthly map is the sdmTMB projection clipped to the cells where the satellite detected a bloom. The satellite cannot see the first few kilometres along the coast and in the bays, where most of the FWC water samples are taken, so in-situ blooms there never reached the maps ([#6](https://github.com/WFS-FEM/RedTideMaps/issues/6), #8). The nearshore set names the cells where the sample-based footprint (the buffered hulls) is allowed to add to the satellite clip. Everywhere else the satellite result stands, zeros included.

## The grid, land and the domain

- **The grid** is the 5-arcmin Ecospace basemap of the West Florida Shelf: 78 columns by 66 rows, cell size 1/12 degree (8 to 9 km), from 87.5 W to 81 W and 25 N to 30.5 N; `template rasters/depth 5min 66x78.asc`, numerically identical to `output/5min/depth/depth_5min.asc` of the [EcospaceBasemap](https://github.com/WFS-FEM/EcospaceBasemap) repository (checked cell for cell at run time).
- **Land** is a NODATA cell of that depth grid: ETOPO elevation above 0 m, as `make_WFS_basemaps.R` sets it. 1,310 of the 5,148 cells are land and 3,838 are water. Barrier islands and peninsulas thinner than a cell (Okaloosa Island, St George Island, Anna Maria Island, Captiva and others) are not land on this grid; they are water cells.
- **The domain** is the Gulf side only: every water cell outside the Atlantic-side box east of 82 W and north of 28.5 N (56 water cells), the box the pipeline drops samples from and the VIIRS product does not cover. The Atlantic cells are always excluded, whatever the rule. 3,782 water cells remain.

## The three criteria

A domain water cell is **nearshore** if it meets at least one of the following.

### 1. Masked by VIIRS

The VIIRS red-tide product (NOAA monthly 0.1-degree rasters produced by the University of South Florida Optical Oceanography Laboratory, `VIIRS/redtide_maps_0.1degree/*.tif`, 155 monthly layers from January 2012 to December 2024, stacked as `VIIRS/VIIRS_201201-202412.grd`) carries no data in a static band along the coast and in the bays. A 0.1-degree VIIRS cell is in the **static no-data mask** when it has no data (NA) in at least 90% of the 155 monthly layers (parameter `mask_share = 0.9`; #8 found 1,004 such cells, 1,001 of them with no data in every month; the 15 cells that miss a single month, 14 of them over deep water in the south-west corner, are a transient gap and not part of it). A template cell meets criterion 1 when its centre falls inside a masked 0.1-degree cell. **84 cells.** The mask is read from the stack itself at run time, so a new VIIRS delivery redefines it without a code change.

### 2. Within 5 km of the coast

The **coast** is the Natural Earth 1:10m physical coastline (public domain, https://www.naturalearthdata.com/downloads/10m-physical-vectors/), downloaded on 19 October 2026 with `rnaturalearth::ne_download(scale = 10, type = "coastline", category = "physical")`, cropped to the grid box and tracked as `data/coastline/ne_10m_coastline_wfs.gpkg` (one MULTILINESTRING feature; see `data/coastline/README.md`). At 1:10m it resolves the barrier islands and the large bays (Tampa Bay, Charlotte Harbor, Apalachicola Bay, Choctawhatchee Bay) but not every small inlet, so a distance taken from it is good to about 1 to 2 km. The line is projected to UTM zone 17N (EPSG:32617) and densified to a vertex every 200 m (`coast_step_m = 200`); a template cell meets criterion 2 when the distance from its centre, projected the same way, to the nearest vertex is at most 5 km (`coast_km = 5`). **132 cells.** Because the coastline draws the islands and the bay shores, this criterion reaches the cells that sit against a barrier island the basemap draws as water.

### 3. Adjacent to land

A template cell meets criterion 3 when it shares an edge or a corner with a land cell of the basemap: any of its eight neighbours is NODATA (`raster::adjacent(directions = 8)`, the mirror of `fn.build_coastal()` in the EcospaceBasemap repository, which runs the same adjacency from the land side). The grid is taken as it is: its borders are not treated as land, so a water cell in the top row whose land lies north of the map edge does not meet this criterion (the two such cells, in Choctawhatchee Bay, meet criteria 1 and 2). **177 cells.** Because a cell is 8 to 9 km wide, this criterion reaches further than 5 km on the open coast: 53 of its cells have their centre 5 to 12 km from the coastline (Big Bend, the Panhandle bays, the south-west coast) and meet neither of the other criteria.

## The set

The nearshore set is the union: **189 cells, 14,205 km2**, 4.9% of the water cells, a strip one cell wide along the whole Gulf coast and in the bays, 3.4 m deep at the median and 24 m at most (`fig5_nearshore_set_issue15.png`). By criteria met: 75 cells meet all three; 49 are in the VIIRS mask or within 5 km and also touch land (3 by the mask, 46 by the 5 km); 53 touch land only; 12 are in the VIIRS mask or within 5 km but touch no land cell (bays cut by the northern map edge, and Gulf-side cells against barrier islands the grid draws as water: Okaloosa Island, Shell Island, Crooked Island, St Joseph Peninsula, St George Island, Anna Maria Island, Captiva, Sanibel). Each of those 12 sits two cells from the nearest basemap land cell. Criteria 1 and 2 together are the `mask5` set of #8 (136 cells); criterion 3 adds the 53.

| parameter | value | where |
|---|---|---|
| grid | 5-arcmin Ecospace basemap, 78 x 66, 87.5 W to 81 W, 25 N to 30.5 N | `template rasters/depth 5min 66x78.asc` |
| land | NODATA of the depth grid (ETOPO elevation > 0 m) | EcospaceBasemap `make_WFS_basemaps.R` |
| domain | water cells outside the box east of 82 W and north of 28.5 N | `fn.nearshore_mask()` |
| VIIRS mask share | a 0.1-degree cell with no data in at least 90% of the 155 layers | `mask_share = 0.9` |
| coastline | Natural Earth 1:10m physical coastline, cropped to the grid box | `data/coastline/ne_10m_coastline_wfs.gpkg` |
| distance | cell centre to the nearest coastline vertex, UTM 17N, vertices every 200 m, at most 5 km | `coast_km = 5`, `coast_step_m = 200`, EPSG:32617 |
| adjacency | any of the eight neighbours is a land cell; grid borders are not land | `raster::adjacent(directions = 8)` |

## How the set is used

In every month served from a satellite (VIIRS or MODIS), outside the set the satellite-clipped map stands, zeros included: where the satellite looked, its result is kept (Yao Yao's condition). Inside the set a cell takes the maximum of the satellite-clipped and the hull-clipped projection of the month, the hull map being the pipeline's own buffered hulls (every positive FWC sample, single-linkage clustering at 75 km, concave hulls for clusters of 4 or more locations, a 10 km buffer; [#3](https://github.com/WFS-FEM/RedTideMaps/issues/3)). So the sample-based footprint is added nearshore and never removes a satellite detection; no cell is ever lowered. The hull months (no satellite coverage) are unchanged. With this set and fill, over the 278 satellite months, the maps include 94.2% of the water samples at or above 10k cells/L (the satellite clips alone: 63.2%; `mask5`: 93.0%) and the total exposure rises by 8.4% (`mask5`: 7.3%); see the README, question 3.

## Implementation

Criteria 1 and 2 were implemented in the pipeline as rule `"mask5"` of `fn.nearshore_mask()` in `scripts/process_hybrid.R` (issues #11 and #10). Criterion 3 was added in [issue #18](https://github.com/WFS-FEM/RedTideMaps/issues/18) (23 October 2026) as rule `"mask5adj"`: the same function with the adjacency part added and the `"mask5"` path untouched, selected by `cfg$viirs_nearshore` and `cfg$modis_nearshore` in `run_redtide_maps.R` and the default for both sensors since then. The pipeline run was verified against the prototype set (`tables/nearshore_set_issue15.csv`, cell for cell) and the per-month metrics of this folder (`union_hull` in `tables/examine_months_issue15.csv`: all 278 satellite months equal on 9 metrics; 210 months change, 121 VIIRS and 89 MODIS) in `docs/issue18_implement-hybrid-clipping/`, which also regenerated the deliverables and records the final decisions (the #5 closure).
