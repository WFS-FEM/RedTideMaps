# RedTideMaps
code to make red tide maps for WFS-FEM
## To Do:
1. write function to access HAB data from https://habsos.noaa.gov/about.  Function should check version of existing file in directory and download a new file if an updated version is available.  Extract the .csv file and save in /cell_count_data directory with through date.
2. Write function for VAST model of cell count data, inputs should be the cell count data the ascii basemap bathymetry grid, environmental covariate data grids (if used), and probably some options/switches for model controls.
3. Write function for ordinary and anisotropic kriging of cell count data, inputs should be the cell count data the ascii basemap bathymetry grid, environmental covariate data grids (if used), and probably some options/switches for model controls..
4. Write function for simple inverse distance weighting extrapolation of cell count data, inputs should be the cell count data the ascii basemap bathymetry grid, environmental covariate data grids (if used), and probably some options/switches for model controls..
5. Write function to access MODIS satellite data.  The MODIS data will be replaced with VIIRS, but we still need this function.  Inputs will be vector of months to download and the ascii basemap bathymetry grid.  Should check dates of existing data and only download and process the more recent maps.
6. Write function to access VIIRS satellite data.  When the product is ready from Chuanmin.
7. Finaly, write a function to clip krig/VAST extrapolated cell count data (cells/L) to red tide polygons from MODIS or VIIRS and write Ecospace ST ascii files, or update the stack of existing files. 
