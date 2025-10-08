rm(list=ls());graphics.off();rm(.SavedPlots);gc()
getwd()
#@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Setup ------------------------------------------------------------------------
## Directories ----
wd = getwd()
dir.cellcnts <- file.path(wd, "cell count data")
dir.stdriver <- file.path(dirname(wd), "WFS EwE", "Ecospace", "ST drivers")
scripts_path  <- "C:/Users/dchagaris/Github/WFS-FEM/RedTideMaps/scripts"
dir.viirs    <- file.path(wd, 'VIIRS')
dir.modis    <- file.path(wd, "MODIS")
dir.modis.raw <- file.path(dirname(dirname(dir.stdriver)),"ST data extraction","MODIS","flh")
dir.depth <- file.path(dirname(dir.stdriver), "maps/bathymetry/")

## Source Scripts----
source(file.path(scripts_path, "get_HAB_data.R"))
source(file.path(scripts_path, "sdmTMB_HAB_data.R"))
source(file.path(scripts_path, "process_VIIRS.R"))
source(file.path(scripts_path, "process_MODIS.R"))
source(file.path(scripts_path, "IDW_HAB_data.R"))
#source(file.path(scripts_path, "ordkrig_HAB_data.R"))
#source(file.path(scripts_path, "anisokrig_HAB_data.R"))
source(file.path(scripts_path, "polygon_clipping_rt.R"))

#spatial resolutions of 4, 6, and 10 minutes allowed
res<-'10'

# Build all dirs
dir.plots   <- paste0(wd,"/",res, 'min/plots')
dir.sdmout  <- paste0(wd, "/",res,"min/sdm out")
dir.idwout  <- paste0(wd, "/",res,'min/idw out')
dir.ordkrig <- paste0(wd, "/",res,'min/ordkrig out')
#dir.modis   <- dir.modis.raw
#dir.viirs   <- paste0(res, 'min', dir.viirs0)

# Collect them
all_dirs <- c(dir.plots, dir.sdmout, dir.idwout, dir.ordkrig)

# Create all if missing
for (d in all_dirs) {
  if (!dir.exists(d)) dir.create(d, recursive = TRUE)
}

#get bathymetry basemap and geographic extent of ecospace model
if(res==4) file.depth = file.path(paste0(dir.depth,"/depth 4min 82x97.asc"))
if(res==6) file.depth = file.path(paste0(dir.depth,"/depth 6min 55x65.asc"))
if(res==10) file.depth = file.path(paste0(dir.depth,"/depth 10min 33x39.asc"))
file.excl = gsub("/depth ","/excl layer ",file.depth)

#@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
#HAB data processing----------------------------------------------------------
#https://geodata.myfwc.com/datasets/myfwc::recent-harmful-algal-bloom-hab-events/explore?location=27.689864%2C-83.698850%2C7.27
#go to FWC website above and download the most recent HAB dataset and save in dir.cellcnts with historic datasets
##FWC data----
fn.get_fwc_data(dir.data=dir.cellcnts)
#file.habRdat = list.files(dir.cellcnts, pattern="\\.Rdata", full.names=T)
fn.filter_hab_data(file.hab=file.habRdat, file.depth=file.depth, file.excl=file.excl)
fn.plot_hab_data(file.habRdat=file.habRdat.filtered)

##HABSOS repository----
#alternatively, query the NOAA HABSOS repository for red tide cell count data, this also creates 
#some of the polygons needed for the modeling.  
#fn.get_habsos_data(url.habsos = url.habsos, dir.data=dir.cellcnts)

#@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
#Spatial extrapolation----------------------------------------------------------
##sdmTMB----
file.habRdat.filtered = list.files(dir.cellcnts,pattern='filtered.Rdata$',full.names=T)
load(file.habRdat.filtered)
fn.make_input_grid(file.depth = file.depth, file.excl = file.excl)
fn.fit_monthly_sdmTMB(habdata=filtered_points_df, styr=1985, enyr=2025)  #diagnostic plots not working
fn.predict_monthly_sdmTMB(file.sdmpred = file.path(dir.sdmout,'pred_SDMs_RT.RData'), 
                          file.depth=file.depth)
fn.plot_sdmTMB()

##IDW----
#fn.hab_idw_monthly(file.habRdat=file.habRdat)
#fn.plot_idw(file.idwstack=list.files(dir.idwout,pattern=".grd",full.names=T))
#idw <- stack(list.files(dir.idwout,pattern=".grd",full.names=T))

##Simple Ordinary Kriging----
#not yet working, need to finish back transformation
#fn.hab_ordkrig_monthly(file.habRdat = file.habRdat)
#ordkrig <- stack(list.files(dir.ordkrig,pattern=".grd",full.names=T)[1])

#@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
#Clipping-----------------------------------------------------------------------
##Clip to VIIRS-----
fn.viirs_tifs2stack(dir.viirs=dir.viirs)
file.viirs <- gsub(".gri","",list.files(dir.viirs, pattern='gri$', full.names=T))
file.pred <- list.files(dir.sdmout, pattern=".grd$", full.names=T)[1]
sdm.log.viirs <- fn.clip_2_viirs(file.pred=file.pred, file.viirs=file.viirs)
#fn.get_viirs_obs(file.habRdat = file.habRdat.filtered, dir.sdmout = dir.sdmout, viirs.stack=viirs.stack)

#fn.plot_viirs() #not working
#sdm.log.viirs <- stack(paste0(dir.sdmout,"/sdmTMB_log_stack_201201-202412_clipped_viirs"))

##Clip to MODIS nFLH------------------------------------------------------------
###make MODIS polygons
if(!dir.exists(dir.modis)) dir.create(dir.modis)
#fn.pull_MODIS_flh_erddap()
#fn.make_nflh_polys(dir.in=dir.modis.raw, dir.out=dir.modis)
#fn.plot_modis(dir.modis=dir.modis, file.flhpolys = list.files(dir.modis,pattern="^FLH polys", full.names=T)[2])
file.flhpolys = list.files(dir.modis,pattern="^FLH polys", full.names=T)[1]
file.pred <- list.files(dir.sdmout, pattern=".grd$", full.names=T)[1]
sdm.log.modis <- fn.clip_2_modis(file.pred=file.pred, file.flhpolys = file.flhpolys)
#sdm.log.modis <- stack(paste0(dir.sdmout,"/sdmTMB_log_stack_200207-202309_clipped_modis"))

##clip to buffered hulls--------------------------------------------------------
file.habRdat.filtered <- list.files(dir.cellcnts, pattern='filtered', full.names=T)
sdm.log.hullpolys <- fn.buffered_hulls(file.habRdata=file.habRdat.filtered)

file.hullpolys <- list.files(dir.sdmout, pattern="hullpolys", full.names=T)
file.pred <- list.files(dir.sdmout, pattern=".grd$", full.names=T)[1]
sdm.log.hull <- fn.clip_2_hulls(file.pred=file.pred, file.polys=file.hullpolys)

#@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
#Output-------------------------------------------------------------------------
#output ascii to ST driver folder
dir.create(file.path(dir.stdriver,paste0(res,'min')))
dir.create(file.path(dir.stdriver,paste0(res,'min'),'red tide'))
dir.stdriver.out <- file.path(dir.stdriver,paste0(res,'min'),'red tide','sdmTMB')
dir.create(dir.stdriver.out)
make_redtide_ascii(dir.pred=dir.sdmout, dir.out=dir.stdriver.out) 

#@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
#Plotting-----------------------------------------------------------------------
fn.plot_redtide_stack(file.stack = gsub(".gri","",list.files(dir.sdmout, pattern='combined.gri', full.names=T)))
