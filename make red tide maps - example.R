rm(list=ls());graphics.off();rm(.SavedPlots);gc()

#SETUP----------------------------------------------------------------
#The working directory should be a parent directory where raw data and model outputs are stored.
##Directories----
###working directory ------ 
wd <<- "C:\\Users\\dchagaris\\OneDrive - University of Florida\\WFS Fisheries Ecosystem Modeling\\red tide maps"
setwd(wd)

###HAB cell count data directory-----
dir.data <<- paste0(getwd(),"/data")
#if(!dir.exists(dir.data)) dir.create(dir.data)
#files.data <- list.files(dir.data)

###spatial temporal driver directory
dir.stdriver <<- paste0(dirname(wd),"\\WFS EwE\\Ecospace\\ST drivers\\red tide")
###plot directory----
dir.plots <<- paste0(wd,"/plots")
###VIIRS directory----
dir.viirs <<-  paste0(wd,"/VIIRS/redtide_maps_0.1degree")
###MODIS directory----
dir.modis <- paste0(wd,"/MODIS")
###sdm output directory----
dir.sdmout <<- paste0(wd,"/sdm out")
###idw output directory----
dir.idwout <<- paste0(wd,"/idw out")
dir.ordkrig <<- paste0(wd,"/ordkrig out")
##Depth Map----
file.depth <<- paste0(dirname(wd),"\\WFS EwE\\Ecospace\\maps\\bathymetry\\depth 4min 82x97.asc")
file.excl <<- paste0(dirname(file.depth),"/",gsub("depth","excl layer",basename(file.depth)))
##HAB url
url.habsos <<- "https://www.ncei.noaa.gov/data/oceans/archive/arc0069/0120767/"

##Source Scripts----
source("C:\\Users\\dchagaris\\Github\\WFS-FEM\\RedTideMaps\\scripts\\get_HAB_data.R")
source("C:\\Users\\dchagaris\\Github\\WFS-FEM\\RedTideMaps\\scripts\\sdmTMB_HAB_data.R")
source("C:\\Users\\dchagaris\\Github\\WFS-FEM\\RedTideMaps\\scripts\\process_VIIRS.R")
source("C:\\Users\\dchagaris\\Github\\WFS-FEM\\RedTideMaps\\scripts\\process_MODIS.R")
source("C:\\Users\\dchagaris\\Github\\WFS-FEM\\RedTideMaps\\scripts\\IDW_HAB_data.R")

#HAB data processing-----------------------------------------------------------------------
#query the NOAA HABSOS repository for red tide cell count data, this also creates 
#some of the polygons needed for the modeling
fn.get_hab_data(url.habsos = url.habsos, dir.data=dir.data)
fn.filter_hab_data(file.habsos=file.habsos, file.depth=file.depth, file.excl=file.excl)
fn.plot_hab_data(file.habRdat=file.habRdat)

#Spatial extrapolation----------------------------------------------------------
##sdmTMB----
fn.make_input_grid(file.depth = file.depth, file.excl = file.excl)
fn.fit_monthly_sdmTMB(habdata=filtered_points_df, styr=1985, enyr=2024)
fn.predict_monthly_sdmTMB(file.sdmpred = paste0(dir.sdmout,'/pred_SDMs_RT.RData'), file.depth=file.depth)
fn.plot_sdmTMB()
sdm.log <- stack(paste0(dir.sdmout,"/sdmTMB_log_stack_198501-202412"))

##IDW----
#inverse distance weighting
fn.hab_idw_monthly(file.habRdat=paste0(dir.data,"/",file.habRdat))
fn.plot_idw(file.idwstack=list.files(dir.idwout,pattern=".grd",full.names=T))
idw <- stack(list.files(dir.idwout,pattern=".grd",full.names=T))

##Simple Ordinary Kriging----
#not yet working, need to finish back transformation
fn.hab_ordkrig_monthly(file.habRdat = file.habRdat)
ordkrig <- stack(list.files(dir.ordkrig,pattern=".grd",full.names=T)[1])

#clip to VIIRS----------------------------------------------------------
fn.viirs_tifs2stack(dir.viirs=dir.viirs)
fn.get_viirs_obs(file.habRdat = paste0(dir.data,"/",file.habRdat), dir.sdmout = dir.sdmout, viirs.stack=viirs.stack)
sdm.log.viirs <- fn.clip_2_viirs(file.pred=paste0(dir.sdmout,'/sdmTMB_log_stack_198501-202412'),file.viirs=file.viirs)
#fn.plot_viirs()

sdm.log.viirs <- stack(paste0(dir.sdmout,"/sdmTMB_log_stack_201201-202412_clipped_viirs"))

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

#combine and save ascii---------------------------------------------------------
sdm.log.modis <- stack(paste0(dir.sdmout,"/sdmTMB_log_stack_200207-202309_clipped_modis"))
sdm.log.viirs <- stack(paste0(dir.sdmout,"/sdmTMB_log_stack_201201-202412_clipped_viirs"))
#use modis where viirs is not available
keep.modis = which(!names(sdm.log.modis) %in% names(sdm.log.viirs))
sdm.log.comb <- stack(sdm.log.modis[[keep.modis]], sdm.log.viirs)
names(sdm.log.comb)

dir.stsdm <- paste0(dir.stdriver,"/sdmTMB")
if(!dir.exists(dir.stsdm)) dir.create(dir.stsdm)
writeRaster(sdm.log.comb, filename=paste0(dir.stsdm,'/red tide sdm'), bylayer=T,suffix=paste0(gsub("X","",names(sdm.log.comb))),format='ascii')
