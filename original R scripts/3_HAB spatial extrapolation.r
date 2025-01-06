rm(list=ls());graphics.off();rm(.SavedPlots);gc();windows(record=T)
memory.limit(size=1e9)
.libPaths("C:\\R\\win-library")
library('rgeos')
library('raster')
library('rasterVis')
library('gstat')
library('data.table')
library('fields') 
library('automap')
library('maps')
library('maptools')
library('automap')
library('intamap')
library('gridExtra')
library('readr')

options("rgdal_show_exportToProj4_warnings=none") 
library("rgdal")

####################################################################################################
#   SETUP
####################################################################################################
bbox.gom = c(-98,-80.5,24,31)
bbox.wfs = c(-88,-80.5,24.5,30.5)#c(-88,-80.5,25,30.5)
bbox = bbox.wfs

dir.base = getwd()
dir.poly = "./flh polygons"
dir.cells = "./cell counts"
dir.flh = paste0(dirname(dir.base),"/data extraction/MODIS/flh")
dir.depth = paste0(dirname(dir.base),"/bathymetry")
dir.out = paste0(dir.cells,"/extrapolation output")
dir.plt = paste0(dir.cells,'/plots')
if(!exists(dir.out)){dir.create(dir.out)}
if(!exists(dir.plt)){dir.create(dir.plt)}

####################################################################################################
#   PREPARE DATA
####################################################################################################
#bring in updated nFLH raster stack & polys---------------------------------------------------------
list.files(dir.flh,pattern=".grd$")
flh = stack(paste(dir.flh,'flh_-98_-80.5_24_31_200301-20230912',sep='/'))
flh = crop(flh,extent(bbox))
flh = flh/10
extent(flh); flh; names(flh)

#get nFLH polygons----------------------------------------------------------------------------------
list.files(dir.poly)
load(paste0(dir.poly,"/FLH polys 200207-202309.Rdata"))

#check existing extrapolation output----------------------------------------------------------------
files.old = list.files(dir.out,recursive=F,include.dirs = F)
files.old = files.old[-which(files.old=='hoard')]

#-----------------------FWRI cell count data--------------------------------------------------------
#download habsos dataset from NOAA
#alternatively, can load cell count dataset provided by FWRI
path.habsos = "https://www.nodc.noaa.gov/archive/arc0069/0120767/7.7/data/0-data/habsos_20230714.csv"
#hab = read.csv(path.habsos)
#write.csv(hab,paste0(dir.habs,'/',basename(path.habsos)),row.names=F)
hab = read.csv(paste0(dir.cells,"/habsos_20230714.csv"))
names(hab) = tolower(names(hab))
names(hab); unique(hab$genus); range(hab$sample_date)
hab = hab[hab$genus=='Karenia',c(5,6,3,4,10)]
names(hab) = c('sample_date','depth','latitude','longitude','k_brevis')
hab$sample_date = as.Date(hab$sample_date,format="%m/%d/%Y")
hab$year         = format(hab$sample_date,"%Y")
hab$month        = format(hab$sample_date,"%m")
hab$yearmon      = paste(hab$year,hab$month,sep='-')
hab = hab[hab$longitude>=bbox[1] & hab$longitude<=bbox[2] & hab$latitude>=bbox[3] & hab$latitude<=bbox[4],]
ne.idx = which(hab$longitude>-82 & hab$latitude>29)
hab = hab[-ne.idx,]
hab = hab[order(hab$sample_date),]
hab.yrs  = unique(hab$year)

#get max cell concentration for a given site and month
hab.max        = aggregate(k_brevis~longitude+latitude+sample_date+year+month,FUN=max,na.rm=T,data=hab)

#which metric to use?    
hab.dat  = hab.max
coordinates(hab.dat) = ~longitude+latitude
projection(hab.dat);crs(hab.dat)

#read in depth rasters - sat data is 4km----------------------------------------------
depth.3s = raster(paste0(dir.depth,"\\depth_WFS_3sec"))
depth.4k = raster(paste0(dir.depth,"\\depth_WFS_4km"))
plot(depth.3s,colNA='gray')
plot(depth.4k,colNA='gray')

#prediction grid and data projected to UTM coordinates
hab.dat
crs(hab.dat) = "+proj=robin"
proj4string(hab.dat) = CRS("+proj=longlat +datum=WGS84")
hab.dat = spTransform(hab.dat,CRS="+proj=utm +zone=16 +datum=WGS84 +units=km")
hab.grid = projectRaster(depth.4k,crs="+proj=utm +zone=16 +datum=WGS84 +units=km")
hab.grid = as(hab.grid,"SpatialGridDataFrame")

table(hab$year,hab$month)

###########################################################################################
#  INVERSE DISTANCE WEIGHTING
###########################################################################################
#get existing IDW stack and identify months to update
files.idw = list.files(dir.out,pattern="^IDW")
print(files.idw)
idw.old = stack(paste0(dir.out,'/IDW 200301-202112'))
names(idw.old);names(flh.polys)
domonths = names(flh.polys)[which(!names(flh.polys)%in%names(idw.old)[-nlayers(idw.old)])]
doyears = as.numeric(unique(substr(domonths,2,5)))

#inverse distance weighting interpolation
brks.idw    = c(0,1000,seq(10000,2000000,10000),5000000000)
colv    = c("white","purple", "blue", "darkblue", "cyan", "green","darkgreen", "yellow", "orange", "red", "darkred")
funpal  = colorRampPalette(colv,bias=2)
nbcols.idw  = length(brks.idw)-1
color.idw   = funpal(nbcols.idw)  
ne.extent = extent(1005,1169,2965,3500)

idw.wt        = 2
idw.new  = stack()
for(i in 1:length(domonths)){
  #i=1
  print(paste("Now Doing IDW",domonths[i]));flush.console()
  y = (substr(domonths[i],2,5))
  m = (substr(domonths[i],6,7))
  #y=2005;m=9
  hab.sub        = hab.dat[hab.dat$year==y & hab.dat$month==m,]
  if(length(hab.sub)>0){
    idw1        = idw(k_brevis~1,hab.sub,hab.grid,idp=idw.wt)
    idw.rast   = raster(idw1)
    ne.idx = cellsFromExtent(idw.rast,ne.extent)
    na.idx = which(idw.rast[cellsFromExtent(idw.rast,ne.extent)]>0)
    idw.rast[cellsFromExtent(idw.rast,ne.extent)[na.idx]] <- 0
    names(idw.rast)  = paste0("X",y,formatC(m,width=2,flag="0"))
    idw.new    = addLayer(idw.new,idw.rast)
  } else{
    idw.rast = raster(hab.grid)
    idw.rast[] = 0
    names(idw.rast)  = paste0("X",y,formatC(m,width=2,flag="0"))
    idw.new    = addLayer(idw.new,idw.rast)
  }
  #plot(fwri.idw.rast,colNA='lightgray',col=color.idw,breaks=brks.idw,main=names(fwri.idw.rast),legend=F,axes=F)
  #plot(coastp,add=T)
}

#output raster
names(idw.old); names(idw.new); dim(idw.old); dim(idw.new)
idw.out = addLayer(idw.new[[1:6]],idw.old[[-nlayers(idw.old)]]);names(idw.out)
idw.out = addLayer(idw.out,idw.new[[-c(1:6)]]);names(idw.out)
stackname = gsub("X","",paste0(dir.out,"/IDW ",names(idw.out)[1],"-",tail(names(idw.out),1)))
writeRaster(idw.out,stackname,overwrite=T)
#writeRaster(fwri.idw.new,filename='Kbrevis IDW 4k 200301-202110')

#plots-----------------------------------------------------------------------------------
#idw.out.file = unique(gsub('.grd',"",gsub('.gri',"",list.files(dir.out,pattern="^IDW"))))[1]
#idw.out = stack(paste0(dir.out,"/",idw.out.file)); 
#names(idw.out)
idw.out = projectRaster(from=idw.out,to=flh)
sort(maxValue(idw.out))
brks.idw    = c(0,1,1000,seq(10000,4000000,10000),2e8)
colv    = c("white","light gray","purple", "blue", "darkblue", "cyan", "green","darkgreen", "yellow", "orange", "red", "darkred")
funpal  = colorRampPalette(colv,bias=2)
nbcols.idw  = length(brks.idw)-1
color.idw   = funpal(nbcols.idw)  

plt.stack = idw.out
plt.years = 2002:2023
pdf(paste0(dir.plt,'/',basename(stackname),'.pdf'),onefile=T)
for(y in plt.years){
  #y=doyears[3]
  yr.idx  = which(substr(names(plt.stack),2,5) == y)
  plt.yr  = plt.stack[[yr.idx]] 
  par(mfrow=c(4,3),mar=c(1,1,2,0),oma=c(2,2,0,6))
  for(i in 1:nlayers(plt.yr)){
    #i=1
    plot(plt.yr[[i]],legend=F,col=color.idw,colNA='darkgray',breaks=brks.idw,
         main=paste(month.abb[as.numeric(substr(names(plt.yr)[i],6,7))],substr(names(plt.yr)[i],2,5)))
    #overlay coastline map of Florida
    map(database='state',region='Florida',add=T,fill=T,col='wheat')
    #plot(coastp,add=T)
  }
  #add legend
  par(mfrow=c(1,1),mar=c(0,0,0,0),oma=c(0,0,0,1))
  image.plot(plt.yr,legend.only=T,breaks=brks.idw[-length(brks.idw)],col=color.idw[-1],add=T,legend.width=1,legend.mar=4,legend.line=3,
             legend.lab = 'cells/L')
}
dev.off()
  
#cleanup old files----------------------------------------------------------------------------------
files.hoard = files.idw
file.copy(from=paste0(dir.out,'/',files.hoard), to=paste0(dir.out,'/hoard/',files.hoard),overwrite = T)
file.remove(from=paste0(dir.out,'/',files.hoard))

####################################################################################################
#   SIMPLE ORDINARY KRIGING
####################################################################################################
#get existing KRG stack and identify months to update
dir.out = "C:\\Users\\dchagaris\\OneDrive - University of Florida\\WFS Fisheries Ecosystem Modeling\\WFS EwE\\Ecospace\\red tide maps\\cell counts\\extrapolation output\\krg"
files.krg = list.files(dir.out,pattern="^KRG")
print(unique(trimws(gsub('clipped','',gsub('.gri','',gsub('.grd','',files.krg))))))
krg.old.pred = stack(paste0(dir.out,'/KRG pred 200301-202112'))
krg.old.bt = stack(paste0(dir.out,'/KRG bt 200301-202112'))
krg.old.bt1 = stack(paste0(dir.out,'/KRG bt1 200301-202112'))
krg.old.bt2 = stack(paste0(dir.out,'/KRG bt2 200301-202112'))
krg.old.var = stack(paste0(dir.out,'/KRG var 200301-202112'))

names(krg.old.pred);names(flh.polys)
names(krg.old.pred) = paste0("X",substr(names(krg.old.pred),4,7),formatC(match(substr(names(krg.old.pred),1,3),month.abb),digits=1,flag="0"))
names(krg.old.bt) = names(krg.old.bt1) = names(krg.old.bt2) = names(krg.old.var) = names(krg.old.pred)
domonths = names(flh.polys)[which(!names(flh.polys)%in%names(krg.old.pred)[-nlayers(krg.old.pred)])]
doyears = as.numeric(unique(substr(domonths,2,5)))
domonths = 'X202110'
#kriging----------------------------------------------------------------------
hab.nkb1000 = aggregate(k_brevis~month+year,data=hab,FUN=function(x) length(x[x>=1000]))
vgmmods = as.character(vgm()$short)

#colors for plotting krg maps
colv    = c("white","purple", "blue", "darkblue", "cyan", "green","darkgreen", "yellow", "orange", "red", "darkred")
funpal  = colorRampPalette(colv,bias=2)
brks.krg    = c(0,1000,seq(10000,2000000,10000),5000000000)
nbcols.krg  = length(brks.krg)-1
color.krg   = funpal(nbcols.krg)

#graphics.off();rm(.SavedPlots);gc();windows(record=T)
plotkrig=F
krg.bt = krg.bt1 = krg.bt2 = krg.pred = krg.var = stack()
vgpars.out = data.frame()
start.time = gsub(":","",Sys.time())
#dev.off()
windows(record=T)
pdf(paste0(dir.plt,'/KRG variograms ',gsub("X","",domonths)[1],"-",tail(gsub("X","",domonths),1),'.pdf'),onefile=T)
for(m in 1:length(domonths)){
  #mos = unique(fwri.maxk$month[fwri.maxk$year==y])
  #par(mfrow=c(4,3))
  #for(m in mos){
  m=1
  do.m = domonths[m]
  #y=2005;m=9  #error thrown for March 2016 EXp,nug=9.6,sill=11,range=0.01
  kdat = hab.dat[paste0("X",hab.dat$year,hab.dat$month)==do.m,]#.maxk$year==y & fwri.maxk$month==m,]
  idx.dup = which(duplicated(kdat@coords))
  if(length(idx.dup)>0){
    kdat@coords[idx.dup,1] = kdat@coords[idx.dup,1]*runif(length(idx.dup),min=0.995,1.005)
    kdat@coords[idx.dup,2] = kdat@coords[idx.dup,2]*runif(length(idx.dup),min=0.995,1.005)
  }
  nkb = length(kdat$k_brevis[kdat$k_brevis>=1000])
  print(paste("Now kriging",do.m));flush.console()
  #table(kdat$k_brevis)
  if(nkb>=5){
    if(do.m=="X201603"){
      kb.krig = autoKrige(log(k_brevis+1)~1,input_data=kdat,new_data=hab.grid,model='Exp',fix.values=c(9.6,NA,NA),verbose=F) #fix.values=c(9.6,.01,11)
      plot(kb.krig,sub=do.m)
    } else {
      kb.krig = autoKrige(log(k_brevis+1)~1,input_data=kdat,new_data=hab.grid,model=c('Sph','Exp','Ste'),verbose = F)
      plot(kb.krig,sub=do.m)
    }
    krast = raster(kb.krig$krige_output)
    vgpars.out = rbind(vgpars.out,data.frame(year=substr(do.m,2,5),month=substr(do.m,6,7),
                         nug=kb.krig$var_model$psill[1],
                         psill=kb.krig$var_model$psill[2],
                         range=kb.krig$var_model$range[2]))

    #backtransform-----------------------------------------------------------------
    out.pred = kb.krig$krige_output
    backtran.df = cbind(coordinates(out.pred),out.pred@data)
    names(backtran.df) = c('long','lat','pred1','pred1.var')
    
    #1. do cross-validation procedure to get Number of Interpolation Standard Deviations
    v.fit = kb.krig$var_model
    crossval = krige.cv(log(k_brevis+1)~1,nfold=5,kdat,model=v.fit)
    crossval = data.frame(longitude=coordinates(kdat)[,1],latitude=coordinates(kdat)[,2],Nisd=crossval$residual/sqrt(crossval$var1.var))
    coordinates(crossval) = ~longitude+latitude
    proj4string(crossval) = proj4string(kdat)
    summary(crossval)
    
    #2. krige the cross-validation Nisd
    k.Nisd = krige(Nisd~1,crossval,hab.grid,model=v.fit)
    out.pred$Nisd = k.Nisd$var1.pred
    out.pred$Nisd.var = k.Nisd$var1.var
    summary(out.pred);
    
    #3. apply first correction term
    out.pred$NisdSo = out.pred$Nisd*sqrt(out.pred$var1.var)
    out.pred$cor1 = out.pred$var1.pred+out.pred$NisdSo
    out.pred$cor1[out.pred$cor1<0] = 0
    summary(out.pred$cor1)
    
    #correct for mean
    mu.obs = mean(log(kdat$k_brevis+1),na.rm=T)
    mu.pred = mean(out.pred$cor1,na.rm=T)
    out.pred$cor2 = out.pred$cor1*(mu.obs/mu.pred)
    summary(out.pred$cor2)
    
    #plot prediction and corrections
    names(out.pred)
    if(plotkrig==T){
      p1 = spplot(out.pred['var1.pred'],main='Prediction (log scale)') #,col.regions=col.regions,cuts=length(col.regions)-1
      p2 = spplot(out.pred['cor1'],main='Pred + NisdSo')#,col.regions=col.regions,cuts=length(col.regions)-1)
      p3 = spplot(out.pred['cor2'],main='(Pred + NisdSo)*MeanCor')
      p4 = spplot(out.pred['Nisd'],main='Nisd')
      grid.arrange(p1,p2,p3,p4)
    }
    
    #save as raster
    krast.pred = raster(out.pred['var1.pred'])
    krast.cor1 = raster(out.pred['cor1'])
    krast.cor2 = raster(out.pred['cor2'])
    krast.var = raster(out.pred['var1.var'])
    krast.bt = exp(krast.pred)-1
    krast.bt1 = exp(krast.cor1)-1
    krast.bt2 = exp(krast.cor2)-1
    krast.bt[krast.bt<0] = 0
    krast.bt1[krast.bt1<0] = 0
    krast.bt2[krast.bt2<0] = 0
    
    } else {
      krast = raster(hab.grid)
      krast[!is.na(krast)] = 0
      krast.bt2 = krast.bt1 = krast.bt = krast.pred = krast.var = krast
    }
    
    names(krast.bt2) = names(krast.bt1) = names(krast.bt) = names(krast.pred) = names(krast.var) = do.m
    krg.bt = addLayer(krg.bt,krast.bt)
    krg.bt1 = addLayer(krg.bt1,krast.bt1)
    krg.bt2 = addLayer(krg.bt2,krast.bt2)
    krg.pred = addLayer(krg.pred,krast.pred)
    krg.var = addLayer(krg.var,krast.var)
    

    rm(vgm.list,out.pred);gc()
}


dev.off()
names(krg.bt);names(krg.bt1);names(krg.bt2);names(krg.pred);names(krg.var)
write.csv(vgpars.out,paste0(dir.out,'/KRG variogram pars ',gsub("X","",domonths)[1],"-",tail(gsub("X","",domonths),1),'.csv'),row.names=F)

#add new layers to existing stacks
names(krg.old.pred); names(krg.pred)
krg.pred.out = addLayer(addLayer(krg.pred[[1:6]],krg.old.pred[[-nlayers(krg.old.pred)]]),krg.pred[[-c(1:6)]])
krg.bt.out = addLayer(addLayer(krg.bt[[1:6]],krg.old.bt[[-nlayers(krg.old.bt)]]),krg.bt[[-c(1:6)]])
krg.bt1.out = addLayer(addLayer(krg.bt1[[1:6]],krg.old.bt1[[-nlayers(krg.old.bt1)]]),krg.bt1[[-c(1:6)]])
krg.bt2.out = addLayer(addLayer(krg.bt2[[1:6]],krg.old.bt2[[-nlayers(krg.old.bt2)]]),krg.bt2[[-c(1:6)]])
krg.var.out = addLayer(addLayer(krg.var[[1:6]],krg.old.var[[-nlayers(krg.old.var)]]),krg.var[[-c(1:6)]])

#save stacks
suffixlab = gsub("X","",paste0(names(krg.pred.out)[1],"-",tail(names(krg.pred.out),1)))
writeRaster(krg.pred.out,paste0(dir.out,'/KRG pred ',suffixlab),overwrite=T)
writeRaster(krg.bt.out,  paste0(dir.out,'/KRG bt ',suffixlab),overwrite=T)
writeRaster(krg.bt1.out, paste0(dir.out,'/KRG bt1 ',suffixlab),overwrite=T)
writeRaster(krg.bt2.out, paste0(dir.out,'/KRG bt2 ',suffixlab),overwrite=T)
writeRaster(krg.var.out, paste0(dir.out,'/KRG var ',suffixlab),overwrite=T)

#cleanup old files----------------------------------------------------------------------------------
files.hoard = files.krg
file.copy(from=paste0(dir.out,'/',files.hoard), to=paste0(dirname(dir.out),'/hoard/',files.hoard),overwrite = T)
file.remove(from=paste0(dir.out,'/',files.hoard))
closeAllConnections()

#plot-----------------------------------------------------------------------------------------------
colv    = c("white","purple", "blue", "darkblue", "cyan", "green","darkgreen", "yellow", "orange", "red", "darkred")
funpal  = colorRampPalette(colv,bias=2)
brks.krg    = c(0,1000,seq(10000,1000000,10000),1e20)
nbcols.krg  = length(brks.krg)-1
color.krg   = funpal(nbcols.krg)

plt.stack = stack(paste0(dir.out,'/KRG bt1 200207-202309'))
names(plt.stack)
doyears = sort(unique(substr(names(plt.stack),2,5)))
#plt.stack = projectRaster(from=plt.stack,to=flh,alignOnly = F)
#names(plt.stack);dim(plt.stack)
#pdf(paste0(dir.plt,'\\KRG bt2 ',suffixlab,'.pdf'))
graphics.off();windows(record=T)
for(y in doyears){
  #y=doyears[2]
  yr.idx  = which(substr(names(plt.stack),2,5) == y)
  plt.yr  = plt.stack[[yr.idx]] 
  par(mfrow=c(4,3),mar=c(1,1,2,0),oma=c(2,2,0,6))
  for(i in 1:nlayers(plt.yr)){
    #i=1
    plot(plt.yr[[i]],legend=F,col=color.krg,colNA='darkgray',breaks=brks.krg,main=names(plt.yr)[i])
    #overlay coastline map of Florida
    map(database='state',region='Florida',add=T,fill=T,col='wheat')
    #plot(coastp,add=T)
  }
  #add legend
  par(mfrow=c(1,1),mar=c(0,0,0,0),oma=c(0,0,0,1))
  image.plot(plt.yr,legend.only=T,breaks=brks.krg[-length(brks.krg)],col=color.krg[-1],add=T,legend.width=1,legend.mar=4,legend.line=3,
             legend.lab = 'cells/L')
}
dev.off()



###########################################################################################
#   KRIGING with anisotropy and fancy back transformation
###########################################################################################
#get existing KRG stack and identify months to update
dir.out = "C:\\Users\\dchagaris\\OneDrive - University of Florida\\WFS Fisheries Ecosystem Modeling\\WFS EwE\\Ecospace\\red tide maps\\cell counts\\extrapolation output\\aniso"
files.aniso = list.files(dir.out,pattern="^KRG aniso")
print(unique(trimws(gsub('clipped','',gsub('.gri','',gsub('.grd','',files.aniso))))))
aniso.old.pred = stack(paste0(dir.out,'/KRG aniso pred 200301-202112'))
aniso.old.bt = stack(paste0(dir.out,'/KRG aniso bt 200301-202112'))
aniso.old.bt1 = stack(paste0(dir.out,'/KRG aniso bt1 200301-202112'))
aniso.old.bt2 = stack(paste0(dir.out,'/KRG aniso bt2 200301-202112'))
aniso.old.var = stack(paste0(dir.out,'/KRG aniso var 200301-202112'))

names(aniso.old.pred);names(flh.polys)
names(aniso.old.pred) = paste0("X",substr(names(aniso.old.pred),4,7),formatC(match(substr(names(aniso.old.pred),1,3),month.abb),digits=1,flag="0"))
names(aniso.old.bt) = names(aniso.old.bt1) = names(aniso.old.bt2) = names(aniso.old.var) = names(aniso.old.pred)
domonths = names(flh.polys)[which(!names(flh.polys)%in%names(aniso.old.pred)[-nlayers(aniso.old.pred)])]
doyears = as.numeric(unique(substr(domonths,2,5)))

domonths = paste0("X",rep(2021,12),formatC(1:12,width=2,flag="0"))

#reproject data----------------------------------------------------------------------
# fwri.maxk              = aggregate(k_brevis~longitude+latitude+year+month,FUN=max,na.rm=T,data=fwri)
# fwri.nkb1000 = aggregate(k_brevis~month+year,data=fwri,FUN=function(x) length(x[x>=1000]))
# coordinates(fwri.maxk) = ~longitude+latitude
# crs(fwri.maxk) = "+proj=robin"
# proj4string(fwri.maxk) = CRS("+proj=longlat +datum=WGS84")
# fwri.maxk = spTransform(fwri.maxk,CRS="+proj=utm +zone=16 +datum=WGS84 +units=km")
#use hab.dat
vgmmods = as.character(vgm()$short)

#and finaly krig with anisotropy --------------------------------------------------------------------------------
dev.off()
plotkrig=T
graphics.off();rm(.SavedPlots);gc();windows(record=T)
aniso.bt = aniso.bt1 = aniso.bt2 = aniso.pred = aniso.var = stack()
vgpars.out=data.frame()
start.time = gsub(":","",Sys.time())
if(plotkrig==T) pdf(paste0(dir.plt,"\\aniso variograms ",gsub("X","",paste(domonths[c(1,length(domonths))],collapse="-")),".pdf"),onefile=T)
for(t in 1:length(domonths)){
  t=12
  do.m = domonths[t]
  y=as.numeric(substr(do.m,2,5))
  m=as.numeric(substr(do.m,6,7))
  
  #mos = unique(fwri.maxk$month[fwri.maxk$year==y])
  #for(m in mos){
    #y=2005;m=9
    print(paste0("Now kriging ",do.m));flush.console()
    kdat = hab.dat[hab.dat$year==substr(do.m,2,5) & hab.dat$month==substr(do.m,6,7),]
    #kdat$k_brevis.tran = log(1+(kdat$k_brevis)/median(kdat$k_brevis))
    idx.dup = which(duplicated(kdat@coords))
    if(length(idx.dup)>0){
      kdat@coords[idx.dup,1] = kdat@coords[idx.dup,1]*runif(length(idx.dup),min=0.995,1.005)
      kdat@coords[idx.dup,2] = kdat@coords[idx.dup,2]*runif(length(idx.dup),min=0.995,1.005)
    }
    
    nkb = length(kdat$k_brevis[kdat$k_brevis>=1000])
    table(kdat$k_brevis)
    if(nkb>=5){  #& (y!=2012&m!=6)&(y!=2012&m!=8)
      #test for isotropy
      aniso = estimateAnisotropy(kdat,depVar = "k_brevis")
      doaniso = aniso$doRotation
      print(paste0("anisotropy significance ",doaniso))
      
      diag = spDists(t(bbox(kdat)))[1,2]
      bndy = c(2, 4, 6, 9, 12, 15, 25, 35, 50, 65, 80, 100) * diag * 0.35/100
      
      #calculate variogram
      if(doaniso){
        anis.dirs = 90-aniso$direction
        anis.ratios = 1/aniso$ratio
      } else{
        anis.dirs=0
        anis.ratios=0
      }
      v = variogram(log(k_brevis+1)~1,data=kdat,boundaries=bndy,alpha=anis.dirs)
      #v = variogram(k_brevis.tran~1,data=kdat,boundaries=bndy,alpha=anis.dirs)
      #par(mfrow=c(1,1));plot(v,table=T)
      
      #get initial values for model fitting
      isill = mean(max(v$gamma),median(v$gamma))#mean(tail(v$gamma,5))
      inug  = min(v$gamma)#mean(v$gamma[1:3])
      irange = 0.1*diag#max(v$dist)/3
      print(c(inug,isill,irange))
      
      #fit variogram models
      v.models = c("Ste","Sph","Exp")
      sserr.list = expand.grid(model=v.models,dir.hor=anis.dirs,dir.rat=anis.ratios,SSer=NA,stringsAsFactors = F)
      sserr.list$range = sserr.list$psill = sserr.list$nug = NA
      vgm.list = fit.vgm.list = list()  
      
      for(i in 1:nrow(sserr.list)){
        #i=1
        dir = sserr.list$dir.hor[i]
        rat = sserr.list$dir.rat[i]
        vmod = sserr.list$model[i]
        
        if(doaniso){
          vgmod = vgm(model=vmod,psill=isill-inug,range=irange,nugget=inug,anis=c(dir,rat))
        } else {
          vgmod = vgm(model=vmod,psill=isill-inug,range=irange,nugget=inug) #kappa=0.2
        }
        vgm.list[[i]] = vgmod
        

        if((y==2003&m==6)|(y==2003&m==11)|(y==2004&m==10)|(y==2005&m==1 )|(y==2005&m==4 )|(y==2005&m==7 )|(y==2005&m==9)|
           (y==2006&m==1)|(y==2007&m==3 )|(y==2007&m==9)|(y==2008&m==10)|(y==2008&m==11)|(y==2009&m==12)|
           (y==2011&m==9)|(y==2012&m==9)|(y==2013&m==4)|(y==2013&m==9 )|(y==2014&m==7 )|(y==2017&m==4 )|(y==2017&m==5 )|(y==2017&m==12)|
           (y==2018&m==2 )|(y==2018&m==7)){
          estpars=c(F,T,T)
        } else if((y==9999&m==0)){        
          estpars=c(T,F,T)
        } else if((y==9999&m==0)|(y==2012&m==6)|(y==2009&m==5)|(y==2011&m==4 )|(y==2011&m==7 )){        
          estpars=c(T,T,F)
        } else if((y==2008&m==4)|(y==2015&m==9)){        
          estpars=c(F,T,F)
        } else if((y==2011&m==3)){        
          estpars=c(F,F,T)
        } else if((y==9999&m==0)){        
          estpars=c(T,F,F)
        } else if((y==9999&m==0)|(y==2017&m==10)){        
          estpars=c(F,F,F)
        } else estpars=c(T,T,T)
        
        mod.tmp = fit.variogram(v,vgmod,fit.ranges=estpars[1],fit.sills=estpars[2:3],debug.level=1,cutoff=200)#, fit.kappa=c(0.05, seq(0.2, 2, 0.1),5,10))
        
        fit.vgm.list[[i]] = mod.tmp
        sserr.list[i,4] = attr(mod.tmp,"SSErr")
        sserr.list$nug[i] = mod.tmp$psill[1]
        sserr.list$psill[i] = mod.tmp$psill[2]
        sserr.list$range[i] = mod.tmp$range[2]
      }
      
      #get best fit model
      vgmods = subset(sserr.list,psill>1 & range<1000) #vgmods = subset(sserr.list,psill>1 & nug>1 & range<10000)
      if(nrow(vgmods)==0){
        vgmods = sserr.list
      }
      mod.idx = which.min(vgmods$SSer)
      bestmod = vgmods[mod.idx,]
      bestmod.vgm = vgm.list[[mod.idx]]
      v.fit = fit.vgm.list[[mod.idx]]
      v.pred = variogramLine(v.fit,maxdist=max(v$dist))
      v = v[v$dir.hor==bestmod$dir.hor,]
      
      #krige response variable
      out.pred = krige(log(k_brevis+1)~1, kdat, hab.grid, model=v.fit)
      #out.tg = krigeTg(k_brevis~1,kdat,fwri.grid,model=v.fit)
      
      #plot
      if(plotkrig==T){
        p1 = spplot(out.pred['var1.pred'],main='Prediction (log scale)') #,col.regions=col.regions,cuts=length(col.regions)-1
        p2 = spplot(out.pred['var1.var'],main='Variance')#,col.regions=col.regions,cuts=length(col.regions)-1)
        par(mfrow=c(2,1))
        plot(v$dist,v$gamma,main=paste(month.name[m],y),xlab='Distance (km)',ylab='Semivariance',ylim=c(0,max(v$gamma,v.pred[,2])))
        lines(v.pred[,1],v.pred[,2])
        legend('bottomright',cex=.75,legend=c(paste0('model = ',bestmod$model),
                                              paste0('nugget = ',round(bestmod$nug,2)),
                                              paste0('sill = ',round(bestmod$psill+bestmod$nug,2)),
                                              paste0('range = ',round(bestmod$range,2)),
                                              paste0('dir = ',round(bestmod$dir.hor,2)),
                                              paste0('ratio = ',round(bestmod$dir.rat,2))),col='white')
        print(p1,position=c(0,0,.5,.5),more=T,newpage=F)
        print(p2,position=c(.5,0,1,.5),more=F,newpage=F)
      }
      #dev.off()
      #convert prediction and variance to raster
      #r.pred = raster(out.pred['var1.pred'])
      #r.var = raster(out.pred['var1.var'])
      #summary(r.pred);summary(r.var)
      #windows(record=T)
      #plot(r.pred);plot(r.var)
      
      #backtransform-----------------------------------------------------------------
      backtran.df = cbind(coordinates(out.pred),out.pred@data)
      names(backtran.df) = c('long','lat','pred1','pred1.var')
      
      #1. do cross-validation procedure to get Number of Interpolation Standard Deviations
      crossval = krige.cv(log(k_brevis+1)~1,nfold=5,kdat,model=v.fit)
      crossval = data.frame(longitude=coordinates(kdat)[,1],latitude=coordinates(kdat)[,2],Nisd=crossval$residual/sqrt(crossval$var1.var))
      coordinates(crossval) = ~longitude+latitude
      crs(crossval) = crs(kdat)
      #proj4string(crossval) = proj4string(kdat)
      summary(crossval)

      #2. krige the cross-validation Nisd
      k.Nisd = krige(Nisd~1,crossval,hab.grid,model=v.fit)
      out.pred$Nisd = k.Nisd$var1.pred
      out.pred$Nisd.var = k.Nisd$var1.var
      summary(out.pred);

      #3. apply first correction term
      out.pred$NisdSo = out.pred$Nisd*sqrt(out.pred$var1.var)
      out.pred$cor1 = out.pred$var1.pred+out.pred$NisdSo
      out.pred$cor1[out.pred$cor1<0] = 0
      summary(out.pred$cor1)

      #correct for mean
      mu.obs = mean(log(kdat$k_brevis+1),na.rm=T)
      mu.pred = mean(out.pred$cor1,na.rm=T)
      out.pred$cor2 = out.pred$cor1*(mu.obs/mu.pred)
      summary(out.pred$cor2)
      
      #plot prediction and corrections
      names(out.pred)
      #windows(record=T)
      if(plotkrig==T){
        p1 = spplot(out.pred['var1.pred'],main='Prediction (log scale)') #,col.regions=col.regions,cuts=length(col.regions)-1
        p2 = spplot(out.pred['cor1'],main='Pred + NisdSo')#,col.regions=col.regions,cuts=length(col.regions)-1)
        p3 = spplot(out.pred['cor2'],main='(Pred + NisdSo)*MeanCor')
        p4 = spplot(out.pred['Nisd'],main='Nisd')
        grid.arrange(p1,p2,p3,p4)
      }
      
      #save as raster
      krast.pred = raster(out.pred['var1.pred'])
      krast.cor1 = raster(out.pred['cor1'])
      krast.cor2 = raster(out.pred['cor2'])
      krast.var = raster(out.pred['var1.var'])
      krast.bt = exp(krast.pred)-1
      krast.bt1 = exp(krast.cor1)-1
      krast.bt2 = exp(krast.cor2)-1
      krast.bt[krast.bt<0] = 0
      krast.bt1[krast.bt1<0] = 0
      krast.bt2[krast.bt2<0] = 0
      vgpars.out = rbind(vgpars.out,data.frame('year'=y,'month'=m,
                                               'nug'=bestmod$nug,
                                               'psill'=bestmod$psill,
                                               'range'=bestmod$range,
                                               'dir'=bestmod$dir.hor,
                                               'rat'=bestmod$dir.rat,
                                               'singular'=attr(v.fit,'singular'),
                                               'serr'=bestmod$SSer,
                                               'inug'=inug,
                                               'isill'=isill,
                                               'ipsill'=isill-inug,
                                               'irange'=irange,
                                               'est.ran.nug.sil' = paste(substr(estpars,1,1),collapse="")))
      
    } else {
      krast = raster(hab.grid)
      krast[!is.na(krast)] = 0
    }
    
    names(krast.bt1) = names(krast.bt2) = names(krast.bt) = names(krast.pred) = names(krast.var) = do.m
    aniso.bt = addLayer(aniso.bt,krast.bt)
    aniso.bt1 = addLayer(aniso.bt1,krast.bt1)
    aniso.bt2 = addLayer(aniso.bt2,krast.bt2)
    aniso.pred = addLayer(aniso.pred,krast.pred)
    aniso.var = addLayer(aniso.var,krast.var)
    rm(vgm.list,out.pred);gc()
    
    # p5 = spplot(krast.bt,main='bt') #,col.regions=col.regions,cuts=length(col.regions)-1
    # p6 = spplot(krast.bt1,main='bt1')
    # p7 = spplot(krast.bt2,main='bt2')
    # grid.arrange(p1,p2,p3,p5,p6,p7)
}
dev.off()

#add new layers to existing stacks
#names(aniso.bt1) = names(aniso.bt2) = names(aniso.bt) = names(aniso.pred) = names(aniso.var) = domonths
names(aniso.old.pred); names(aniso.pred)
aniso.pred.out = addLayer(addLayer(aniso.pred[[1:6]],aniso.old.pred[[-nlayers(aniso.old.pred)]]),aniso.pred[[-c(1:6)]])
aniso.bt.out = addLayer(addLayer(aniso.bt[[1:6]],aniso.old.bt[[-nlayers(aniso.old.bt)]]),aniso.bt[[-c(1:6)]])
aniso.bt1.out = addLayer(addLayer(aniso.bt1[[1:6]],aniso.old.bt1[[-nlayers(aniso.old.bt1)]]),aniso.bt1[[-c(1:6)]])
aniso.bt2.out = addLayer(addLayer(aniso.bt2[[1:6]],aniso.old.bt2[[-nlayers(aniso.old.bt2)]]),aniso.bt2[[-c(1:6)]])
aniso.var.out = addLayer(addLayer(aniso.var[[1:6]],aniso.old.var[[-nlayers(aniso.old.var)]]),aniso.var[[-c(1:6)]])

#save stacks
suffixlab = gsub("X","",paste0(names(aniso.pred.out)[1],"-",tail(names(aniso.pred.out),1)))
writeRaster(aniso.pred.out,paste0(dir.out,'/aniso pred ',suffixlab),overwrite=T)
writeRaster(aniso.bt.out,  paste0(dir.out,'/aniso bt ',suffixlab),overwrite=T)
writeRaster(aniso.bt1.out, paste0(dir.out,'/aniso bt1 ',suffixlab),overwrite=T)
writeRaster(aniso.bt2.out, paste0(dir.out,'/aniso bt2 ',suffixlab),overwrite=T)
writeRaster(aniso.var.out, paste0(dir.out,'/aniso var ',suffixlab),overwrite=T)

write.csv(vgpars.out,paste0(dir.out,'/aniso variogram pars ',gsub("X","",domonths)[1],"-",tail(gsub("X","",domonths),1),'.csv'),row.names=F)


#plot-----------------------------------------------------------------------------------------------
plot(aniso.bt1)
#colv    = c("white","purple", "blue", "darkblue", "cyan", "green","darkgreen", "yellow", "orange", "red", "darkred")
#funpal  = colorRampPalette(colv,bias=2)
# brks.krg    = c(0,1,1000,seq(10000,1e7,1e4),1e40)
# nbcols.krg  = length(brks.krg)-1
# color.krg   = funpal(nbcols.krg)
colv.kb    = c("white","purple", "blue", "darkblue", "cyan", "green","darkgreen", "yellow", "orange", "red", "darkred")
funpal.kb  = colorRampPalette(colv.kb,bias=2)
brks.krg    =  c(0,1e4-1,seq(1e4,1e6,1e4),1e15) #for bt and bt1
#brks.krg    =  c(0,1e4,seq(1e5,1e10,1e5),1e40) #for bt2
nbcols.krg  = length(brks.krg)-1
color.krg   = funpal.kb(nbcols.krg)

#plt.stack = stack(paste0(dir.out,'/aniso bt1 200207-202309'))
plt.stack = aniso.bt1
pdf(paste0(dir.plt,'/aniso bt1 ',suffixlab,'.pdf'))
graphics.off();windows(record=T)
names(plt.stack)
doyears = sort(unique(substr(names(plt.stack),2,5)))
for(y in doyears){
  #y=doyears[4]
  yr.idx  = which(substr(names(plt.stack),2,5) == y)
  plt.yr  = plt.stack[[yr.idx]] 
  par(mfrow=c(4,3),mar=c(1,1,2,0),oma=c(2,2,0,6))
  for(i in 1:nlayers(plt.yr)){
    #i=1
    plot(plt.yr[[i]],legend=F,col=color.krg,colNA='darkgray',breaks=brks.krg,main=names(plt.yr)[i])
    #overlay coastline map of Florida
    map(database='state',region='Florida',add=T,fill=T,col='wheat')
    #plot(coastp,add=T)
  }
  #add legend
  par(mfrow=c(1,1),mar=c(0,0,0,0),oma=c(0,0,0,1))
  image.plot(plt.yr,legend.only=T,breaks=brks.krg[-length(brks.krg)],col=color.krg[-1],add=T,legend.width=1,legend.mar=4,legend.line=3,
             legend.lab = 'cells/L')
}
dev.off()


#cleanup old files----------------------------------------------------------------------------------
files.hoard = files.aniso
file.copy(from=paste0(dir.out,'/',files.hoard), to=paste0(dirname(dir.out),'/hoard/',files.hoard),overwrite = T)
file.remove(from=paste0(dir.out,'/',files.hoard))
closeAllConnections()


###########################################################################################
#   VAST
###########################################################################################
#bring in VAST and plot only
vast = stack(paste0(dir.vast,'\\VASTredtide_static_last_v2'))
vast.dates = data.frame(year=substr(names(vast),20,23),month=substr(names(vast),17,19),
                        date = as.Date(paste0(substr(names(vast),20,23),"-",match(toupper(substr(names(vast),17,19)),toupper(month.abb)),"-01")))
seq.dates = seq.Date(from=vast.dates$date[1],to=as.Date("2021-12-01"),by='month')
miss.dates = which(!seq.dates %in% vast.dates$date)
seq.dates[miss.dates]
if(length(miss.dates)>0){
  vast.dummy = vast[[1]]
  vast.dummy[] = 0
  vast = stack(vast[[1:(miss.dates[1]-1)]],vast.dummy,vast.dummy,vast[[(miss.dates[1]):nlayers(vast)]],vast.dummy,vast.dummy)
}
names(vast) = paste0("X",substr(as.character(seq.dates),1,4),substr(as.character(seq.dates),6,7))


#resample to finer resolution
res(vast)
vast2 = resample(vast,depth.4k)
dim(vast);dim(vast2)    
res(vast);res(vast2)

range(vast)
colv    = c("white","purple", "blue", "darkblue", "cyan", "green","darkgreen", "yellow", "orange", "red", "darkred")
funpal  = colorRampPalette(colv,bias=3)
brks.krg    = c(0,1e3,seq(1e4,1e7,1e4),4e8)
nbcols.krg  = length(brks.krg)-1
color.krg   = funpal(nbcols.krg)


plt.stack = vast2[[which(substr(names(vast2),2,5)%in%doyears)]]
names(plt.stack)
#windows(record=T)
pdf(gsub("X","",paste0(dir.plt,'\\VAST ',names(plt.stack)[1],"-",names(plt.stack)[nlayers(plt.stack)],'.pdf')),onefile=T)
for(y in doyears){
  #y=doyears[3]
  yr.idx  = which(substr(names(plt.stack),2,5) == y)
  plt.yr  = plt.stack[[yr.idx]] 
  par(mfrow=c(4,3),mar=c(1,1,2,0),oma=c(2,2,0,6))
  for(i in 1:nlayers(plt.yr)){
    #i=1
    plot(plt.yr[[i]],legend=F,col=color.krg,colNA='darkgray',breaks=brks.krg,
         main=paste(month.abb[as.numeric(substr(names(plt.yr)[i],6,7))],substr(names(plt.yr)[i],2,5)))
    #overlay coastline map of Florida
    map(database='state',region='Florida',add=T,fill=T,col='wheat')
    #plot(coastp,add=T)
  }
  #add legend
  par(mfrow=c(1,1),mar=c(0,0,0,0),oma=c(0,0,0,1))
  image.plot(plt.yr,legend.only=T,breaks=brks.krg[-length(brks.krg)],col=color.krg[-1],add=T,legend.width=1,legend.mar=4,legend.line=3,
             legend.lab = 'cells/L')
}
dev.off()

names(vast2)
stackname = gsub("X","",paste0(dir.out,"\\VAST 4k ",names(vast2)[1],"-",names(vast2)[nlayers(vast2)]))
writeRaster(vast2,stackname)






  
