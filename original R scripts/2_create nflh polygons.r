rm(list=ls());graphics.off();gc();windows(record=T)
.libPaths("C:\\R\\win-library")
library('raster')
library('rgdal')
library('reshape')
library('RCurl')
library('rgeos')

########################################################################################################
# SETUP
########################################################################################################
dir.base = getwd()
dir.poly = "./flh polygons"
dir.flh = paste0(dirname(dir.base),"/data extraction/MODIS/flh")

#dir.map = "G:\\My Drive\\WFS EwE shared\\red tide\\red tide maps"
#dir.ncdf = paste0(getwd(),"/netcdf") #"C:\\dchagaris\\RedTideMortality\\MODIS FLH\\netcdf"

bbox.gom = c(-98,-80.5,24,31)
bbox.wfs = c(-88,-80.5,24.5,30.5)#c(-88,-80.5,25,30.5)
bbox = bbox.wfs
  
#bring in existing, most recent stack of polygons--------------------------------------------------------------------
load(paste0(dir.poly,'/FLH polys 200207-202206.Rdata'))
names(flh.polys)

#bring in nFLH raster stack from MODIS-------------------------------------------------------
list.files(dir.flh)
flh = stack(paste0(dir.flh,'/flh_-98_-80.5_24_31_200301-20230912'))

#subset for months to update
do.months = names(flh)[which(!names(flh)%in%names(flh.polys)[-length(flh.polys)])]
do.months.idx = which(!names(flh)%in%names(flh.polys)[-length(flh.polys)])
#idx.todo = 1:nlayers(flh)  #or do all months
flh = flh[[do.months.idx]]
flh = crop(flh,extent(bbox))
flh = flh/10
  
########################################################################################################
# Create red tide polygons this is slow so only update if possible - need to go parallel
########################################################################################################  
#create polygons---------------------------------------------------------------------------------------
#Hu et al (2005) suggest nFLH values >= .012 are indicative of high Chl-a;  Due
#to changes in calibration algorithms the threshold to detect HABs is now 0.02 (personal communication with Chaunmin)
threshold = 0.02 
flh.polys.new = list()
for(i in 1:nlayers(flh)){
  #i=1
  print(names(flh)[i]);flush.console()
  flh.sub         = flh[[i]]
  flh.sub[flh.sub>=threshold] = 10
  flh.poly        = rasterToPolygons(flh.sub,n=16,fun=function(x){x==10},dissolve=T)
  flh.lines       = as(flh.poly,'SpatialLinesDataFrame')
  flh.poly        = gPolygonize(list(flh.lines))
  flh.polys.new[[i]]  = flh.poly
  names(flh.polys.new)[i] = names(flh)[i]
  rm(flh.sub,flh.poly,flh.lines);gc()
}

#add to old polygon list and save
names(flh.polys)
names(flh.polys.new)  
flh.polys = c(flh.polys[-length(flh.polys)],flh.polys.new)
#flh.polys = flh.polys.new  #if doing all months
names(flh.polys)
getwd()
save(flh.polys,file=paste0(dir.poly,gsub("X","",paste0('/FLH polys ',names(flh.polys)[1],'-',names(flh)[dim(flh)[3]],'.Rdata'))))
numpolys  = cbind(names(flh),as.numeric(unlist(lapply(flh.polys,function(x) length(x)))))
  
  
  
  
  
  
  