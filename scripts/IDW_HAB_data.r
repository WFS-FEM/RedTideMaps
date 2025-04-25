
#IDW prediction-------------------------------------------------------------------------
fn.hab_idw_monthly <- function(file.habRdat=paste0(dir.data,"/",file.habRdat),idw.wt=2, styr=1985){
  
  depth <- raster(file.depth)
  load(file.habRdat)
  class(filtered_points_df)
  hab.dat = as(filtered_points_df,'Spatial')
  hab.dat = hab.dat[hab.dat$year>=styr,]
  
  crs(hab.dat) = "+proj=robin"
  proj4string(hab.dat) = CRS("+proj=longlat +datum=WGS84")
  hab.dat = spTransform(hab.dat,CRS="+proj=utm +zone=16 +datum=WGS84 +units=km")
  hab.grid = projectRaster(depth,crs="+proj=utm +zone=16 +datum=WGS84 +units=km")
  hab.grid = as(hab.grid,"SpatialGridDataFrame")
  
  mindate = as.Date(paste0(min(hab.dat$year),"-",min(hab.dat$month[hab.dat$year==min(hab.dat$year)]),"-01"))
  maxdate = as.Date(paste0(max(hab.dat$year),"-",max(hab.dat$month[hab.dat$year==max(hab.dat$year)]),"-01"))
  times = seq.Date(from=mindate,to=maxdate, by='month')
  
  ne.extent = extent(1005,1169,2965,3500)
  
  idw.out  = stack()
  for(i in 1:length(times)){
    #i=30
    y = as.numeric(format(times[i],"%Y"))
    m = as.numeric(format(times[i],"%m"))
    hab.sub        = hab.dat[hab.dat$year==y & hab.dat$month==m,]
    if(length(hab.sub)>0){
      idw1        = idw(cells~1,hab.sub,hab.grid,idp=idw.wt)
      idw.rast   = raster(idw1)
      ne.idx = cellsFromExtent(idw.rast,ne.extent)
      na.idx = which(idw.rast[cellsFromExtent(idw.rast,ne.extent)]>0)
      idw.rast[cellsFromExtent(idw.rast,ne.extent)[na.idx]] <- 0
    } else{
      idw.rast = raster(hab.grid)
      idw.rast[] = 0
    }
      names(idw.rast)  = paste0("X",y,formatC(m,width=2,flag="0"))
      idw.out    = addLayer(idw.out,idw.rast)
  }
  
  #output raster
  stackname = gsub("X","",paste0(dir.idwout,"/IDW ",names(idw.out)[1],"-",tail(names(idw.out),1)))
  if(!dir.exists(dir.idwout)) dir.create(dir.idwout)
  writeRaster(idw.out,stackname,overwrite=T)
  hab.idw <<- idw.out
}

#Plot IDW-----------------------------------------------------------------------
fn.plot_idw <- function(file.idwstack=list.files(dir.idwout,pattern='.grd$',full.names=T)){
#idw.out.file = unique(gsub('.grd',"",gsub('.gri',"",list.files(dir.out,pattern="^IDW"))))[1]
#idw.out = stack(paste0(dir.out,"/",idw.out.file)); 
#names(idw.out)
idw.out = stack(file.idwstack)
#idw.out = projectRaster(from=idw.out,to=flh)
brks    = c(0,1,1000,seq(10000,4000000,10000),2e8)
colv    = c("white","light gray","purple", "blue", "darkblue", "cyan", "green","darkgreen", "yellow", "orange", "red", "darkred")
funpal  = colorRampPalette(colv,bias=2)
nbcols  = length(brks)-1
color   = funpal(nbcols)  

plt.stack = idw.out
plt.yrs = sort(unique(as.numeric(substr(names(plt.stack),2,5))))
pdf(paste0(dir.idwout,'/',gsub('.grd','.pdf',basename(file.idwstack))),onefile=T)
for(y in plt.yrs){
  #y=plt.yrs[1]
  yr.idx  = which(substr(names(plt.stack),2,5) == y)
  plt.yr  = plt.stack[[yr.idx]] 
  par(mfrow=c(4,3),mar=c(1,1,2,0),oma=c(2,2,0,6))
  for(i in 1:nlayers(plt.yr)){
    #i=1
    plot(plt.yr[[i]],legend=F,col=color,colNA='darkgray',breaks=brks,
         main=paste(month.abb[as.numeric(substr(names(plt.yr)[i],6,7))],substr(names(plt.yr)[i],2,5)))
    #overlay coastline map of Florida
    map(database='state',region='Florida',add=T,fill=T,col='wheat')
    #plot(coastp,add=T)
  }
  #add legend
  par(mfrow=c(1,1),mar=c(0,0,0,0),oma=c(0,0,0,1))
  image.plot(plt.yr,legend.only=T,breaks=brks[-length(brks)],col=color[-1],add=T,legend.width=1,legend.mar=4,legend.line=3,
             legend.lab = 'cells/L')
}
dev.off()
}







  
