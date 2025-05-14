# RedTideMaps

This repository provides tools to download and process red tide concentration data from the Harmful Algal Bloom (HAB) Florida Fish & Wildlife Comission (FWC) monitoring program into monthly raster files to input red tide severity maps into EwE formats compatible with **Ecopath with Ecosim (EwE)** and **Ecospace**. It was developed as part of the *Operationalizing the West Florida Shelf ecosystem model and application to red tides, stock assessment, and catch advice for Gulf of Mexico reef fish* project (PI: David Chagaris).

![image](https://github.com/user-attachments/assets/1272f2f3-61ff-4ac9-8c6b-347b8eca335a)

## Features

### 1. HAB Data Processing
``get_HAB_data.R``

- Download HAB FWC data.
- Spatially filter for the WFS region.
- Plot observations.

### 2. Spatial Extrapolation
``sdmTMB_HAB_data.R``

- Make input grid for prediction purposes
- Fit GLMM monthly models using sdmTMB log and nb.
- Output predicted, observed red tide concentration and fit data objects.
- Produce monthly red tide concentration raster
- Plot red tide concentration maps into a pdf file.

### 3. Inverse Distance Weighting
``IDW_HAB_data.R``

- Predict with IDW and output raster.
- Produce monthly red tide concentration raster
- Plot IDW predictions.

### 4. Simple Ordinary Kriging
``ordkrig_HAB_data.R``

- Predict with Simple Ordinary Kriging and output raster.
- Backtransform.
- Produce monthly red tide concentration raster
- Plot kriging predictions.

### 4. Anisotropic Kriging
``anisokrig_HAB_data.R``

- 

### 5. Clip to VIIRS (Visible Infrared Imaging Radiometer Suite)
``process_VIIRS.R``

- 

### 6. Clip/Process to MODIS  
``process_MODIS.R``

- 




### 1 – Extract MODIS Data




from the HAB FWC monitoring program stored in the NOAA HABSOS.  




















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
