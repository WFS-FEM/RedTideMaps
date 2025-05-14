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

- Predict with SAnisotropic Kriging and output raster.
- Backtransform.
- Produce monthly red tide concentration raster
- Plot kriging predictions.

### 5. Clip to VIIRS (Visible Infrared Imaging Radiometer Suite) - (2012-present)
``process_VIIRS.R``

- Get VIIRS and Observed data.
- VIIRS data represent is raster probability data in which 1 indicates 100% percent of a red tide occurred in that cell in that month.
- Clip Predicted data with VIIRS>0 data.
- Plot red tide severity maps.

### 6. Process and Clip to MODIS - (2003-2012)
``process_MODIS.R``

- Make MODIS polygons.
- Clip rasters.
- Make nFLH polygons.
- Plot results.

### 7. Select approach by year 
(currently at ``scripts/make red tide maps - example.R``)

### 8. 1985 - 2002 - (as buffer?)

## Repository Structure

```
EnvironmentalDrivers2EwE/
├── data/ #
      └── MODIS/
            ├── chla
            ├── sst
            ├── poc
            ├── pic
            └── flh
├── scripts/ # Core R scripts with modular functions and example code
└── README.md # This file
```

## Getting Started

To use the tools in this repository, you will need R (>= 4.0). It requires to previously download [MODIS data](https://modis.gsfc.nasa.gov/tools/).

Example R script is included in  ``scripts/make red tide maps - example.R``.

