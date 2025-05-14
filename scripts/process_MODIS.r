#Setup--------------------------------------------------------------------------
#library("rgeos")
  library('raster')
  library('rasterVis')
  library('gstat')
  library('data.table')
  library('fields') 
  library('colorRamps')
  library('maps')
  library('terra')
  library('sf')


#Clip rasters-------------------------------------------------------------------
fn.clip_2_modis <- function(file.pred=list.files(dir.sdmout,pattern='log_raster_stack',full.names = T)[1],
                            file.flhpolys = list.files(dir.modis,pattern="^FLH polys", full.names=T)){
  #file.pred = gsub(".grd","",list.files(dir.sdmout,pattern='log_stack',full.names = T)[1])
  #file.flhpolys = list.files(dir.modis,pattern="^FLH polys", full.names=T)[2]
  
  load(file.flhpolys)
  pred = stack(file.pred)
  pred.clipped = stack()
  depth = raster(file.depth)
  
  do.modis.clip = which(names(pred) %in% names(flh.polys))
  
  for(i in do.modis.clip){
    #i=do.modis.clip[1]
    #i=216
    names(pred)[i]
    y=substr(names(pred)[i],2,5)
    m=substr(names(pred)[i],6,7)
    print(paste(y,m));flush.console();
    
    p = flh.polys[[which(names(flh.polys)==names(pred)[i])]]
    ri = pred[[i]]
    pi = spTransform(p,crs(ri))  #transform polygons to raster projection
    pri  = rasterize(pi,ri)       #convert polygons to raster
    lri  = mask(x=ri,mask=pri)    #fill polygons with raster value, outside poly is NA
    names(lri) = paste0("X",y,m)#paste(month.abb[m],y,sep='') #= names(lrka) 
    
    #replace NA with 0 and then make land values NA
    lri[is.na(lri)] = 0
    lri[is.na(depth)] = NA
    pred.clipped = addLayer(pred.clipped,lri)
  }
  
  file.clipped2 <<- paste0(dir.sdmout,"/",gsub("[0-9-]","",basename(file.pred)),gsub("X","",names(pred.clipped)[1]),"-",gsub("X","",names(pred.clipped)[nlayers(pred.clipped)]),"_clipped_modis")
  writeRaster(pred.clipped,file.clipped2,overwrite=T)
  return(pred.clipped)
}
  
#make nFLH polygons------------------------------------------------------------------
#Hu et al (2005) suggest nFLH values >= .012 are indicative of high Chl-a;  Due
#to changes in calibration algorithms the threshold to detect HABs is now 0.02 (personal communication with Chaunmin)
fn.make_nflh_polys <- function(dir.modis=dir.modis){
#bring in nFLH raster stack from MODIS
files.flhstack = list.files(dir.modis, pattern='.grd$', full.names=T)
flh = stack(files.flhstack)
flh = flh/10
depth = raster(file.depth)
flh = crop(flh,depth)

threshold = 0.02 
flh.polys.out = list()
for(i in 1:nlayers(flh)){
  #i=1
  print(names(flh)[i]);flush.console()
  flh.sub         = flh[[i]]
  flh.sub[flh.sub>=threshold] = 10
  

  iflh.poly        = rasterToPolygons(flh.sub,n=16,function(x){x==10},dissolve=T)
  flh.lines       = as(iflh.poly,'SpatialLinesDataFrame')
  flh.sflines     = st_as_sf(flh.lines)
  flh.sfunion     = st_union(flh.sflines)
  flh.poly        = st_polygonize(flh.sfunion)
  flh.poly        = st_sf(flh.poly)
  flh.poly <- flh.poly[!st_is_empty(flh.poly), ]
  flh.poly <- st_collection_extract(flh.poly, "POLYGON")
  flh.poly <- st_cast(flh.poly, "POLYGON", group_or_split = TRUE)
  # Ensure each polygon has a unique ID (sp requires this)
  flh.poly$ID <- as.character(1:nrow(flh.poly))
  # Convert to SpatialPolygonsDataFrame
  flh.poly.sp <- as(flh.poly, "Spatial")
  flh.polys.out[[i]]  = flh.poly.sp
  names(flh.polys.out)[i] = names(flh)[i]
  rm(flh.sub,flh.poly,flh.lines);gc()
}

#add to old polygon list and save
flh.polys = flh.polys.out

#flh.polys = flh.polys.new  #if doing all months
save(flh.polys,file=paste0(dir.modis,gsub("X","",paste0('/FLH polys ',names(flh.polys)[1],'-',names(flh)[dim(flh)[3]],'.Rdata'))))
modis.numpolys  <<- data.frame(yrmo=names(flh),
                             npolys=sapply(1:length(flh.polys),function(x) length(flh.polys[[x]][[1]])))

}
  
  
#Plot---------------------------------------------------------------------------
fn.plot_modis <- function(dir.modis=dir.modis, file.flhpolys = list.files(dir.modis,pattern="^FLH polys", full.names=T)){
  
  #file.flhpolys = list.files(dir.modis,pattern="^FLH polys", full.names=T)[2]
  files.flhstack = list.files(dir.modis, pattern='.grd$', full.names=T)
  flh = stack(files.flhstack)
  flh = flh/10
  depth = raster(file.depth)
  flh = crop(flh,depth)
  flh.yrs = sort(unique(as.numeric(substr(names(flh),2,5))))
    
  load(file.flhpolys)
  
  #plot NFLH images
  colv    = c("purple", "blue", "darkblue", "cyan", "green","darkgreen", "yellow", "orange", "red", "darkred")
  funpal  = colorRampPalette(colv,bias=2)
  brks    = seq(0,.1,.001)
  nbcols  = length(brks)-1
  color   = funpal(nbcols)
  
  
  
  #plot with polygons
  pdf(paste0(dir.modis,'/FLH_',gsub("X","",names(flh)[1]),'_to_',gsub("X","",names(flh))[dim(flh)[3]],'_monthly_with_polygons.pdf'),onefile=TRUE)
  for(y in flh.yrs){
    #y=flh.yrs[1]
    yr.idx  = which(as.numeric(substr(names(flh),2,5)) == y)
    yr.idx.polys = which(as.numeric(substr(names(flh.polys),2,5)) == y)
    flh.yr  = flh[[yr.idx]]  
    poly.yr = flh.polys[yr.idx.polys] 
    par(mfrow=c(4,3),mar=c(1,1,2,0),oma=c(2,2,0,6))
    for(i in 1:nlayers(flh.yr)){
      #i=1
      plot(flh.yr[[i]],legend=F,col=color,colNA='black',zlim=c(0,.1),breaks=brks,
           main=gsub("X","",names(flh.yr)[i]),axes=F)
      #plot(flcoast,add=T,col='gray')  
      if(i %in% c(1,4,7,10)){
        axis(2,at=24:30,labels=24:30)
      } else {axis(2,at=24:30,labels=NA)}
      if(i %in% c(10:12)){
        axis(1,at=seq(-88,-81,2),labels=seq(-88,-81,2))
      } else {axis(1,at=seq(-88,-81,2),labels=NA)}
      plot(poly.yr[[i]],add=T,border='red')
    }
    par(mfrow=c(1,1),mar=c(0,0,0,0),oma=c(0,0,0,1))
    image.plot(flh.yr,legend.only=T,zlim=c(0,.1),col=color,add=T,legend.width=1,legend.mar=4,legend.line=3,
               legend.lab = expression('mW cm'^-2*' ?m'^-1*' sr'^-1))
  }   
  dev.off()
}

