rm(list=ls());rm(.SavedPlots);graphics.off();gc();windows(record=T)
.libPaths("C:\\R\\win-library")
library('raster')
#library('SDMTools')
#library('rasterVis')

#######################################################################################################
# Setup
#######################################################################################################
dir.base = getwd()
setwd(dir.base)

bbox.gom = c(-98,-80.5,24,31)
bbox.wfs = c(-88,-80.5,25,30.5)
bbox = bbox.wfs

#set directories for environmental drivers--------------------------------------------------------
dir.depth   = paste0(dirname(dir.base),"/bathymetry/")     #ascii grid
dir.ras.in = paste0(dirname(dir.base),"/red tide maps/")
dir.asc.out = paste0(dirname(dir.base),"/ST drivers/Red tide IDW/")

#get bathymetry map----------------------------------------------------------------------------------------
  depth               = raster(paste(dir.depth,'wfs10min-9207.asc',sep='\\'))
  summary(depth)
  depth[depth>=0]     = NA
  NEcorner            = extent(-82,-80,29,31)
  depth[NEcorner]     = NA
  depth = depth*-1
  plot(depth,colNA='black')
  
#read updated raster
  #ras = stack(paste0(dir.ras.in,"/chlaxZe_-98_-80.5_24_31_200301-20230912"))
  #ras = stack(paste0(dir.ras.in,"/temp_surf_-98_-78_23_32_200301-20230114"))
  #ras = stack(paste0(dir.ras.in,"/temp_bot_-98_-78_23_32_200301-20230114"))
  #ras = stack(paste0(dir.ras.in,"/saln_surf_-98_-78_23_32_200301-20230114"))
  ras = stack(paste0(dir.ras.in,"IDW 200201-202309 clipped"))
  ras.dates = data.frame(year=substr(gsub("_","",names(ras)),2,5),month=substr(gsub("_","",names(ras)),6,7))
  ras.dates$yrmo = paste0(ras.dates$year,ras.dates$month)
  
#get list of existing ascii files----------------------------------------------------------------------------------------  
  asc.files = list.files(dir.asc.out,pattern="*.asc")
  #asc.dates = data.frame(file=asc.files,year=substr(asc.files,26,29),month=substr(asc.files,32,33))
  #asc.dates = data.frame(file=asc.files,year=substr(asc.files,18,21),month=substr(asc.files,24,25))
  #asc.dates = data.frame(file=asc.files,year=substr(asc.files,17,20),month=substr(asc.files,23,24))
  asc.dates = data.frame(file=asc.files,
                         year=substr(asc.files,nchar(asc.files)-7,nchar(asc.files)-4),
                         month=formatC(match(substr(asc.files,nchar(asc.files)-10,nchar(asc.files)-8),month.abb),width=2,flag="0"))
  asc.dates$yrmo = paste0(asc.dates$year,asc.dates$month)
  asc.dates = asc.dates[asc.dates$year != '9999',]

#which ones need to be written out
  asc.need = paste0("X",ras.dates$yrmo[-which(ras.dates$yrmo%in%asc.dates$yrmo[-nrow(asc.dates)])])
  asc.need = asc.need[-c(1:6)]
#subset for stack
  names(ras)
  ras2 = ras[[asc.need]]
  dim(ras2)  
#crop and resample to basemap grid ---------------------------------------
  projection(ras2);projection(depth)
  ras2 = projectRaster(ras2,depth)
  ras2 = crop(ras2,depth)
  extent(depth);extent(ras2)
  ras2    = resample(ras2,depth)
  dim(depth);dim(ras2)
  names(ras2)
  names(ras2) = paste0(month.abb[as.numeric(substr(names(ras2),6,7))],substr(names(ras2),2,5))
  plot(ras2[[15:23]])
#write ascii
asc.dates$file
#ascnum = max(as.numeric(gsub("[^0-9.-]","",substr(asc.files,9,11))))-1
ascnum = max(as.numeric(gsub("[^0-9.-]","",substr(asc.dates$file[asc.dates$month!='NA'],9,11))))
sufx = paste0(ascnum+1:nlayers(ras2),'_',names(ras2))
#sufx = paste0(ascnum+1:nlayers(hab3),'_',month.abb[as.numeric(substr(names(hab3),6,7))],substr(names(hab3),2,5))
#sufx = paste0("y",substr(asc.need,2,5),"_m",substr(asc.need,6,7))
#writeRaster(ras2,paste0(dir.asc.out,'\\','CHLA_INT_EUPHOTIC_DEPTH'),bylayer=T,suffix=sufx,format='ascii',overwrite=T)
#writeRaster(ras2,paste0(dir.asc.out,'/hycom_temp_surf'),bylayer=T,suffix=sufx,format='ascii',overwrite=T)
#writeRaster(ras2,paste0(dir.asc.out,'/hycom_temp_bot'),bylayer=T,suffix=sufx,format='ascii',overwrite=T)
writeRaster(ras2,paste0(dir.asc.out,'/RedTide'),bylayer=T,suffix=sufx,format='ascii',overwrite=T)

 

  
