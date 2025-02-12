# RedTideMaps

This repository provides scripts to produce raster files at monthly steps of red tides in the West Florida Shelf. The script folder includes:
1. **01_get_HAB_data.R**:
 - Connect to Harmful Algal Bloom (HAB) database website
 - Get and download the most recent HAB dataset product
2. **02_model_maps_red_tides.R**:
 - Filter HAB dataset (removing observations in land, Atlantic or <150m depth)
 - Create input grid to predict HAB over. Grid was created from depth 4min (template raster folder)
 - Fit VAST (Vector Autorregressive SpatioTemporal) and sdmTMB models at each month step (from 1985 to 2023) using cells/L 
 - Loop over monthly fitted models to predict cells/L over the entire WFS region and store predictions into an array
 - Read array to plot VAST and sdmTMB monthly spatial predictions side by side by creating a pdf file to store maps
 - Create red tides (cells/L) monthly raster to import to Ecospace

    
## Download K. brevis cell count data (cells/L)
## Conduct spatial extrapolation of K. brevis cell counts.
## Access satellite derived maps of red tide.
## Create spatial temporal drive maps for Ecospace.
