rm(list=ls());graphics.off();rm(.SavedPlots);gc()

# SETUP ------------------------------------------------------------------------
# Get system user
user <- Sys.info()[["user"]]

# Define user-specific paths
if (user == "dchagaris") {
  wd <- "C:/Users/dchagaris/OneDrive - University of Florida/WFS Fisheries Ecosystem Modeling/red tide maps"
  wd.depth <- "C:/Users/dchagaris/OneDrive - University of Florida/WFS Fisheries Ecosystem Modeling/WFS EwE/Ecospace/maps/bathymetry"
  scripts_path <- "C:/Users/dchagaris/Documents/Github/RedTideMaps/scripts"
} else if (user == "dvilasgonzalez") {
  wd <- "C:/Users/dvilasgonzalez/Documents/WFS_DV2/WFS-FEM/ST drivers/red tides/"
  wd.depth <- "C:/Users/dvilasgonzalez/Documents/WFS_DV2/WFS-FEM/static drivers/depth/"
  scripts_path <- "C:/Users/dvilasgonzalez/Documents/Github/RedTideMaps/scripts/"
  scripts_path <- "C:/Users/dvilasgonzalez/Documents/Github/RedTideMaps/scripts"
} else if (user == "daniel") {
  wd <- "/Users/daniel/Work/WFS_DV2/WFS-FEM/ST drivers/red tides/"
  wd.depth <- "/Users/daniel/Work/WFS_DV2/WFS-FEM/static drivers/depth/"
  scripts_path <- "/Users/daniel/Documents/Github/RedTideMaps/scripts"
} else {
  message("User not recognized. Please select working and depth directories.")
  wd <- choose.dir(caption = "Select your red tide maps working directory")
  if (is.na(wd)) stop("No working directory selected. Exiting.")
  
  wd.depth <- choose.dir(caption = "Select your bathymetry maps directory")
  if (is.na(wd.depth)) stop("No depth map directory selected. Exiting.")
  
  scripts_path <- choose.dir(caption = "Select the directory containing your scripts")
  if (is.na(scripts_path)) stop("No scripts directory selected. Exiting.")
}

# Set working directory
setwd(wd)

## Directories ----
dir.data     <- file.path(wd, "data")
dir.stdriver <- file.path(dirname(wd), "WFS EwE", "Ecospace", "ST drivers", "red tide")
#dir.stdriver <- file.path(dirname(wd), "WFS EwE", "Ecospace", "ST drivers", "red tide")

dir.viirs    <- file.path(dir.data, 'raw', "VIIRS_redtide_maps_0.1degree", 'redtide_maps_0.1degree')
dir.modis0    <- file.path(wd, "MODIS")

## HAB url
url.habsos <- "https://www.ncei.noaa.gov/data/oceans/archive/arc0069/0120767/"

## Source Scripts ----
source(file.path(scripts_path, "get_HAB_data.R"))
source(file.path(scripts_path, "sdmTMB_HAB_data.R"))
source(file.path(scripts_path, "process_VIIRS.R"))
source(file.path(scripts_path, "process_MODIS.R"))
source(file.path(scripts_path, "IDW_HAB_data.R"))
source(file.path(scripts_path, "ordkrig_HAB_data.R"))
#source(file.path(scripts_path, "anisokrig_HAB_data.R"))
source(file.path(scripts_path, "polygon_clipping_rt_v2.R"))

for (res in c(4,6,10)) {
  
  #res<-'4'
  
  # Build all dirs
  dir.plots   <- paste0(wd,res, 'min/plots')
  #dir.viirs   <- paste0(res, 'min', dir.viirs0)
  dir.modis   <- dir.modis0
  dir.sdmout  <- paste0(wd, res,"min/sdm out")
  dir.idwout  <- paste0(wd, res,'min/idw out')
  dir.ordkrig <- paste0(wd, res,'min/ordkrig out')
  
  # Collect them
  all_dirs <- c(dir.plots, 
                dir.sdmout, dir.idwout, dir.ordkrig)
  
  # Create all if missing
  for (d in all_dirs) {
    if (!dir.exists(d)) dir.create(d, recursive = TRUE)
  }
  
  #get bathymetry basemap and geographic extent of ecospace model
  if(res==4) file.depth = file.path(paste0(wd.depth,"/depth 4min 82x97.asc"))
  if(res==6) file.depth = file.path(paste0(wd.depth,"/depth/depth 6min 55x65.asc"))
  if(res==10) file.depth = file.path(paste0(wd.depth,"/depth 10min 33x39.asc"))
  
  #get excl cells in ecospace bathymetry basemap and geographic extent of ecospace model
  if(res==4) file.excl = file.path(paste0(wd.depth,"/excl layer 4min 82x97.asc"))
  if(res==6) file.excl = file.path(paste0(wd.depth,"/excl layer 6min 55x65.asc"))
  if(res==10) file.excl = file.path(paste0(wd.depth,"/excl layer 10min 33x39.asc"))
    
  #HAB data processing-----------------------------------------------------------------------
  #query the NOAA HABSOS repository for red tide cell count data, this also creates 
  #some of the polygons needed for the modeling
  fn.get_hab_data(url.habsos = url.habsos, dir.data=paste0(dir.data))
  fn.filter_hab_data(file.habsos=file.habsos, file.depth=file.depth, file.excl=file.excl)
  fn.plot_hab_data(file.habRdat=file.habRdat)
  
  #Spatial extrapolation----------------------------------------------------------
  ##sdmTMB----
  
  fn.make_input_grid(file.depth = file.depth, file.excl = file.excl)
  fn.fit_monthly_sdmTMB(habdata=filtered_points_df, styr=1985, enyr=2024)
  fn.predict_monthly_sdmTMB(file.sdmpred = paste0(dir.sdmout,'/pred_SDMs_RT.RData'), file.depth=file.depth)
  fn.plot_sdmTMB()
  #sdm.log <- stack(paste0(dir.sdmout,"/sdmTMB_log_stack_198501-202412"))
  
  ##IDW----
  #inverse distance weighting
  fn.hab_idw_monthly(file.habRdat=file.habRdat)
  fn.plot_idw(file.idwstack=list.files(dir.idwout,pattern=".grd",full.names=T))
  #idw <- stack(list.files(dir.idwout,pattern=".grd",full.names=T))
  
  ##Simple Ordinary Kriging----
  #not yet working, need to finish back transformation
  fn.hab_ordkrig_monthly(file.habRdat = file.habRdat)
  #ordkrig <- stack(list.files(dir.ordkrig,pattern=".grd",full.names=T)[1])
  
  #clip to VIIRS----------------------------------------------------------
  fn.viirs_tifs2stack(dir.viirs=dir.viirs)
  fn.get_viirs_obs(file.habRdat = paste0(dir.data,"/",file.habRdat), dir.sdmout = dir.sdmout, viirs.stack=viirs.stack)
  sdm.log.viirs <- fn.clip_2_viirs(file.pred=paste0(dir.sdmout,'/sdmTMB_log_stack_198501-202412'),file.viirs=file.viirs)
  #fn.plot_viirs()
  #sdm.log.viirs <- stack(paste0(dir.sdmout,"/sdmTMB_log_stack_201201-202412_clipped_viirs"))
  
  #make MODIS polygons------------------------------------------------------------
  fn.make_nflh_polys(dir.modis=dir.modis)
  fn.plot_modis(dir.modis=dir.modis, file.flhpolys = list.files(dir.modis,pattern="^FLH polys", full.names=T)[2])
  
  #need to get the first 6 months from older file, b/c newest modis stack started in 2003
  # load(list.files(dir.modis,pattern="^FLH polys", full.names=T)[1])
  # load(list.files(dir.modis,pattern="^FLH polys", full.names=T)[2])
  # flh.polys = append(flh.polys1,flh.polys)
  # names(flh.polys)
  # save(flh.polys,file=paste0(dir.modis,gsub("X","",paste0('/FLH polys ',names(flh.polys)[1],'-',names(flh.polys)[length(flh.polys)],'.Rdata'))))
  # unlink(list.files(dir.modis,pattern="^FLH polys", full.names=T)[3])
  
  #clip to MODIS nFLH-------------------------------------------------------------
  sdm.log.modis <- fn.clip_2_modis(file.pred=gsub(".grd","",list.files(dir.sdmout,pattern='log_stack',full.names = T)[1]),
                                   file.flhpolys = list.files(dir.modis,pattern="^FLH polys", full.names=T)[2])
  
  sdm.log.modis <- stack(paste0(dir.sdmout,"/sdmTMB_log_stack_200207-202309_clipped_modis"))
  
  # #combine and save ascii---------------------------------------------------------
  # sdm.log.modis <- stack(paste0(dir.sdmout,"/sdmTMB_log_stack_200207-202309_clipped_modis"))
  # sdm.log.viirs <- stack(paste0(dir.sdmout,"/sdmTMB_log_stack_201201-202412_clipped_viirs"))
  # #use modis where viirs is not available
  # keep.modis = which(!names(sdm.log.modis) %in% names(sdm.log.viirs))
  # sdm.log.comb <- stack(sdm.log.modis[[keep.modis]], sdm.log.viirs)
  # names(sdm.log.comb)
  # 
  # dir.stsdm <- paste0(wd,"/sdmTMB")
  # if(!dir.exists(dir.stsdm)) dir.create(dir.stsdm)
  # writeRaster(sdm.log.comb, filename=paste0(dir.stsdm,'/red tide sdm'), bylayer=T,suffix=paste0(gsub("X","",names(sdm.log.comb))),format='ascii')
  
  # clip objects ####
  # Run clipping setup
  clip_objects <- clip_setup(wd = wd, wd.depth = wd.depth)
  #clip_objects <- clip_setup(wd, wd.depth)
  flh_polys <- clip_objects$flh_polys
  pol_list  <- clip_objects$pol_list
  land_mask <- clip_objects$land_mask
  # Run clipping setup
  #clip_objects <- clip_setup(wd = wd, wd.depth = wd.depth)
  
  # Clip and store RT severity ascii ####
  clip_apply(
    wd = wd,
    res = res,
    land_mask = clip_objects$land_mask,
    flh_polys = clip_objects$flh_polys,
    pol_list = clip_objects$pol_list,
    vars = c("log",'nb')       # or add other variables if needed
  )
}

# check data HABSOS through API GEOJSON####
#libraryies
library(sf)
library(lubridate)
library(ggplot2)

# GeoJSON API URL
geojson_url <- "https://gis.myfwc.com/mapping/rest/services/Open_Data/Recent_Harmful_Algal_Bloom__HAB__Events_2015_present/MapServer/7/query?outFields=*&where=1%3D1&f=geojson"
#geojson_url <- "https://atoll.floridamarine.org/arcgis/rest/services/Projects_FWC/HAB_Current/MapServer/0/query?outFields=*&where=1%3D1&f=geojson"

# Read data directly into an sf object
hab_data <- st_read(geojson_url)

# Convert epoch milliseconds to POSIXct date-time
hab_data$SAMPLE_DATE <- as_datetime(hab_data$SAMPLE_DATE / 1000)

# Check result
head(hab_data$SAMPLE_DATE)

# Add year and month columns
hab_data$YEAR <- year(hab_data$SAMPLE_DATE)
hab_data$MONTH <- month(hab_data$SAMPLE_DATE, label = TRUE, abbr = TRUE)

#plot
ggplot(subset(hab_data,YEAR=='2024')) +
  geom_sf() +
  labs(title = "HAB samples 2024 by year",
       color = "Year") +
  theme_minimal()+
  facet_wrap(~MONTH)



