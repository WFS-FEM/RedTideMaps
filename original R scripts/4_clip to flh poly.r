#-----------------------------------setup---------------------------------------
  rm(list=ls());graphics.off();rm(.SavedPlots);gc();windows(record=T)
  .libPaths("C:\\R\\win-library")
  library('rgeos')
  library('raster')
  library('rasterVis')
  library('gstat')
  library('data.table')
  library('fields') 
  library('colorRamps')
  library('maps')
  dir.base = getwd()
  #dir.wd = "C:/Users/dchagaris/OneDrive - University of Florida/WFS Fisheries Ecosystem Modeling/WFS EwE/red tide/red tide cell count data"
  dir.polys = paste0(dir.base,"/flh polygons")
  dir.flh = paste0(dirname(dir.base),"/data extraction/MODIS/flh")
  #dir.hab = "G:\\My Drive\\WFS EwE shared\\red tide\\map pub"
  #dir.vast = "G:\\My Drive\\WFS EwE shared\\red tide\\red tide cell count data\\VAST\\VAST static"
  #dir.out = paste0(dir.wd,"\\extrapolation output")
  dir.out = dir.base
  dir.ext = paste0(dir.base,"/cell counts/extrapolation output")
  #dir.plt = "G:\\My Drive\\WFS EwE shared\\red tide\\red tide cell count data\\plots"
  #dir.plt = paste0(dirname(dir.wd),"\\map pub\\supplemental")
  dir.plt = dir.base
  #dir.fwri  = "C:/dchagaris/RedTideMortality/FWRI HAB data"
  #source("G:\\My Drive\\WFS EwE shared\\red tide\\update scripts\\UtilityFunctions.r")
  
  bbox.gom = c(-98,-80.5,24,31)
  bbox.wfs = c(-88,-80.5,24.5,30.5)#c(-88,-80.5,25,30.5)
  bbox = bbox.wfs
  
#######################################################################################################
# Prepare data
#######################################################################################################
#bring in updated nFLH raster stack & polys------------------------------------------------
list.files(dir.flh)   
flh = stack(paste0(dir.flh,"\\flh_-98_-80.5_24_31_200301-20230912"))
flh = flh[[1]]
flh = crop(flh,extent(bbox))
flh;gc()
  
#load nFLH polygons------------------------------------------------------------------------------------
load(paste0(dir.polys,"/FLH polys 200207-202309.Rdata")) 
numpolys  = cbind(names(flh.polys),as.numeric(unlist(lapply(flh.polys,function(x) length(x)))))

#bring in extrapolated HAB data------------------------------------------------------------------------
#ext.method = "KRG"
idw = stack(paste0(dir.ext,"/idw/IDW 200207-202309"))
krg = stack(paste0(dir.ext,"/krg/KRG bt1 200207-202309"))
aniso = stack(paste0(dir.ext,"/aniso/aniso bt1 200207-202309"))
#vast = stack(paste0(dir.out,"\\VAST 4k 200301-202112"))
#krgv = stack(paste0(dir.out,"\\KRG var 200301-202112"))
#names(krgv)=names(vast)=names(krg)=names(aniso)=names(idw)
names(krg)=names(aniso)=names(idw)

nlayers(idw);nlayers(krg);nlayers(aniso)#;nlayers(vast);nlayers(krgv)
#hab.yrs  = as.numeric(sort(unique(substr(names(hab.idw),2,5))))
hab.yrs = 2002:2023
dim(idw);dim(krg);dim(aniso)#;dim(vast);dim(krgv)
summary(krg[[33]]);summary(aniso[[33]])

# #make prediction grid from depth
# depth = raster("G:\\My Drive\\WFS EwE shared\\Ecospace\\Bathymetry\\crm_crm_vol3.nc")
# #spatial reference system: urn:ogc:def:crs:EPSG::4269urn:ogc:def:crs:EPSG::5715
# #the below string is said to be standard for unprojected data in Fed agencies
# proj4string(depth) = CRS("+init=epsg:4269 +proj=longlat +ellps=GRS80 +datum=NAD83 +no_defs +towgs84=0,0,0")
# dim(depth)
# #1-minute grid cell resolution = 3-arc sec*20
# depth2 = aggregate(depth,fact=20,fun=mean)
# dim(depth2);depth2;depth
# depth2[depth2>0] = NA
# depth2 = depth2*-1
# #depth2[cellsFromExtent(depth2,extent(-82,-80,26.5,30.5))] <- NA
# plot(depth2,colNA='gray')
# 
# #make coastline polygon from depth raster
# coast = projectRaster(depth2,crs="+proj=utm +zone=16 +datum=WGS84 +units=km")
# plot(coast,colNA='black')
# coast[is.na(coast)] = -1
# coastp = rasterToPolygons(coast,fun=function(x){x<0},dissolve=T)



#######################################################################################################
# Make Polygons
#######################################################################################################
closeAllConnections()
#clip idw or krg maps to polygon regions to make red tide maps
  idw.clip = krg.clip = aniso.clip = stack()  #= vast.clip = krgv.clip
  for(y in hab.yrs){
    #y=hab.yrs[1]
    yr.idx.ply  = which(substr(names(flh.polys),2,5) == y)
    yr.idx.idw  = which(substr(names(idw),2,5) == y)
    yr.idx.krg  = which(substr(names(krg),2,5) == y)
    yr.idx.aniso  = which(substr(names(aniso),2,5) == y)
    #yr.idx.vast  = which(substr(names(vast),2,5) == y)
    #yr.idx.krgv  = which(substr(names(krgv),2,5) == y)
    poly.yr = flh.polys[yr.idx.ply]
    idw.yr = idw[[yr.idx.idw]]
    #vast.yr = vast[[yr.idx.vast]]
    krg.yr = krg[[yr.idx.krg]]
    aniso.yr = aniso[[yr.idx.aniso]]
    #krgv.yr = krgv[[yr.idx.krgv]]
    mos     = min(length(poly.yr),nlayers(idw.yr),nlayers(krg.yr),nlayers(aniso.yr))#,nlayers(vast.yr),nlayers(krga.yr))
    for(m in 1:mos){
      print(paste(y,m));flush.console();
      #m=9
      p = poly.yr[[m]]
      
      ri = idw.yr[[m]]
      pi = spTransform(p,crs(ri))  #transform polygons to raster projection
      pri  = rasterize(pi,ri)       #convert polygons to raster
      lri  = mask(x=ri,mask=pri)    #fill polygons with raster value, outside poly is NA
      
      rk = krg.yr[[m]]
      pk = spTransform(p,crs(rk))  #transform polygons to raster projection
      prk  = rasterize(pk,rk)       #convert polygons to raster
      lrk  = mask(x=rk,mask=prk)    #fill polygons with raster value, outside poly is NA
      
      rka = aniso.yr[[m]]
      pka = spTransform(p,crs(rka))  #transform polygons to raster projection
      prka  = rasterize(pka,rka)       #convert polygons to raster
      lrka  = mask(x=rka,mask=prka)    #fill polygons with raster value, outside poly is NA
      
      # rkv = krgv.yr[[m]]
      # pkv = spTransform(p,crs(rkv))  #transform polygons to raster projection
      # prkv  = rasterize(pkv,rkv)       #convert polygons to raster
      # lrkv  = mask(x=rkv,mask=prkv)    #fill polygons with raster value, outside poly is NA
      # 
      # rv = vast.yr[[m]]
      # pv = spTransform(p,crs(rv))  #transform polygons to raster projection
      # prv  = rasterize(pv,rv)       #convert polygons to raster
      # lrv  = mask(x=rv,mask=prv)

      names(lri) = names(lrk) = names(lrka) = paste0("X",y,formatC(m,width=2,flag="0"))#paste(month.abb[m],y,sep='') #= names(lrka) 
      idw.clip  = addLayer(idw.clip,lri)
      krg.clip  = addLayer(krg.clip,lrk)
      #vast.clip  = addLayer(vast.clip,lrv)
      aniso.clip  = addLayer(aniso.clip,lrka)
      #krgv.clip = addLayer(krgv.clip,lrkv)
      #names(hab.clip)
    }
  }
  names(idw.clip);names(aniso.clip);names(krg.clip)#;names(krgv.clip);names(vast.clip)
  dim(idw.clip);dim(aniso.clip);dim(krg.clip)#;dim(krgv.clip);dim(vast.clip)
  summary(krg.clip[[33]]);summary(aniso.clip[[33]])
  


#replace NA with 0 and then make land values NA
  idw.clip2 = krg.clip2 = aniso.clip2  = stack() #= vast.clip2 = krgv.clip2
  for(i in 1:min(nlayers(idw.clip),nlayers(krg.clip),nlayers(aniso.clip))){ #,nlayers(vast.clip),nlayers(krgv.clip)
    #i=33
    print(names(idw.clip)[i]);flush.console();
    tmpi = idw.clip[[i]]
    tmpi[is.na(tmpi)] = 0
    tmpi[is.na(idw[[i]])] = NA
  
    tmpk = krg.clip[[i]]
    tmpk[is.na(tmpk)] = 0
    tmpk[is.na(krg[[i]])] = NA
    
    tmpka = aniso.clip[[i]]
    tmpka[is.na(tmpka)] = 0
    tmpka[is.na(aniso[[i]])] = NA
    
    # tmpkv = krgv.clip[[i]]
    # tmpkv[is.na(tmpkv)] = 0
    # tmpkv[is.na(krgv[[i]])] = NA
    # 
    # tmpv = vast.clip[[i]]
    # tmpv[is.na(tmpv)] = 0
    # tmpv[is.na(vast[[i]])] = NA
    names(tmpi) = names(tmpk)= names(tmpka) = names(idw.clip)[i]
    
    idw.clip2 = addLayer(idw.clip2,tmpi)
    krg.clip2 = addLayer(krg.clip2,tmpk)
    aniso.clip2 = addLayer(aniso.clip2,tmpka)
    #vast.clip2 = addLayer(vast.clip2,tmpv)
    #krgv.clip2 = addLayer(krgv.clip2,tmpkv)
    rm(tmpi,tmpv,tmpk,tmpka,tmpkv);gc()
  }

#save raster stacks
  names(idw.clip2);names(krg.clip2);names(aniso.clip2);#names(krgv.clip2);names(vast.clip2);
  dim(idw.clip2);dim(krg.clip2);dim(aniso.clip2)#;dim(krgv.clip2);dim(vast.clip2);
  idw.clip2
  stacknamei = gsub("X","",paste0(dir.out,"\\IDW ", names(idw.clip2)[1],"-",names(idw.clip2)[nlayers(idw.clip2)]," clipped"))
  #stacknamev = gsub("X","",paste0(dir.out,"\\VAST 4k ",names(vast.clip2)[1],"-",names(vast.clip2)[nlayers(vast.clip2)]," clipped"))
  stacknamek = gsub("X","",paste0(dir.out,"\\KRG bt1 ", names(krg.clip2)[1],"-",names(krg.clip2)[nlayers(krg.clip2)]," clipped"))
  stacknameka = gsub("X","",paste0(dir.out,"\\aniso bt1 ", names(aniso.clip2)[1],"-",names(aniso.clip2)[nlayers(aniso.clip2)]," clipped"))
  #stacknamekv = gsub("X","",paste0(dir.out,"\\KRG var ", names(krgv.clip2)[1],"-",names(krgv.clip2)[nlayers(krgv.clip2)]," clipped"))
  
  writeRaster(idw.clip2,stacknamei,overwrite=T)
  #writeRaster(vast.clip2,stacknamev,overwrite=T)
  writeRaster(krg.clip2,stacknamek,overwrite=T)
  writeRaster(aniso.clip2,stacknameka,overwrite=T)
  #writeRaster(krgv.clip2,stacknamekv,overwrite=T)
  
#######################################################################################################
# Plot
#######################################################################################################
  depth.3s = raster("C:\\Users\\dchagaris\\OneDrive - University of Florida\\WFS Fisheries Ecosystem Modeling\\WFS EwE\\Ecospace\\Bathymetry\\depth_WFS_3sec")
  idw.clip2 = stack(stacknamei)
  #vast.clip2 = stack(paste0(dir.out,"\\VAST 4k 200301-202112 clipped"))
  krg.clip2 = stack(stacknamek)
  aniso.clip2 = stack(stacknameka) 
  #krgv.clip2 = stack(paste0(dir.out,"\\KRG var 200301-202112 clipped")) 
  
#IDW
  colv.idw    = c("white","purple", "blue", "darkblue", "cyan", "green","darkgreen", "yellow", "orange", "red", "darkred")
  funpal.idw  = colorRampPalette(colv.idw,bias=2)
  brks.idw    = c(0,1e4-1,seq(1e4,4e6,10000),1e8)
  nbcols.idw  = length(brks.idw)-1
  color.idw   = funpal.idw(nbcols.idw)  
  
  plt.stack = idw.clip2
  plt.stack = projectRaster(from=plt.stack,to=flh)
  pdf(gsub("X","",paste0(dir.plt,'/IDW ',names(plt.stack)[1],"-",names(plt.stack)[nlayers(plt.stack)],' clipped.pdf')),onefile=T)
  for(y in hab.yrs){
    #y=hab.yrs[3]
    yr.idx  = which(substr(names(plt.stack),2,5) == y)
    plt.yr  = plt.stack[[yr.idx]] 
    par(mfrow=c(4,3),mar=c(1,1,2,0),oma=c(2,2,2,6))
    for(i  in 1:nlayers(plt.yr)){
      #i=1
      plot(plt.yr[[i]],legend=F,col=color.idw,colNA='darkgray',breaks=brks.idw)
      #main=paste(month.abb[as.numeric(substr(names(plt.yr)[i],6,7))],substr(names(plt.yr)[i],2,5)))
      text(-86.5,25.5,paste(month.abb[as.numeric(substr(names(plt.yr)[i],6,7))],substr(names(plt.yr)[i],2,5)),cex=1.1)
      #overlay coastline map of Florida
      #map(database='county',add=T,fill=T,col='wheat',border='gray')
      map(database='state',add=T,fill=T,col='wheat')
    }
    #add legend
    par(mfrow=c(1,1),mar=c(0,0,0,0),oma=c(0,0,0,1))
    image.plot(plt.yr,legend.only=T,breaks=brks.idw[-length(brks.idw)],col=color.idw[-1],add=T,legend.width=1,legend.mar=4,legend.line=3,
               legend.lab = 'cells/L')
    title('Inverse Distance Weighting',outer=T,line=-1.5)
  }
  dev.off()

#krg  
  colv.idw    = c("white","light gray","purple", "blue", "darkblue", "cyan", "green","darkgreen", "yellow", "orange", "red", "darkred")
  funpal.idw  = colorRampPalette(colv.idw,bias=2)
  brks.krg    =  c(0,1,1e4-1,seq(1e4,1e6,1e4),1e15)
  nbcols.krg  = length(brks.krg)-1
  color.krg   = funpal.idw(nbcols.krg)
  
  plt.stack = krg.clip2
  plt.stack = projectRaster(from=plt.stack,to=flh)
  pdf(gsub("X","",paste0(dir.plt,'\\KRG ',names(plt.stack)[1],"-",names(plt.stack)[nlayers(plt.stack)],' clipped.pdf')),onefile=T)
  for(y in hab.yrs){
    #y=hab.yrs[3]
    yr.idx  = which(substr(names(plt.stack),2,5) == y)
    plt.yr  = plt.stack[[yr.idx]] 
    par(mfrow=c(4,3),mar=c(1,1,2,0),oma=c(2,2,2,6))
    for(i in 1:nlayers(plt.yr)){
      #i=1
      plot(plt.yr[[i]],legend=F,col=color.krg,colNA='darkgray',breaks=brks.krg)
      #main=paste(month.abb[as.numeric(substr(names(plt.yr)[i],6,7))],substr(names(plt.yr)[i],2,5)))
      text(-86.5,25.5,paste(month.abb[as.numeric(substr(names(plt.yr)[i],6,7))],substr(names(plt.yr)[i],2,5)),cex=1.1)
      #overlay coastline map of Florida
      #map(database='county',add=T,fill=T,col='wheat',border='gray')
      map(database='state',add=T,fill=T,col='wheat')
    }
    #add legend
    par(mfrow=c(1,1),mar=c(0,0,0,0),oma=c(0,0,0,1))
    image.plot(plt.yr,legend.only=T,breaks=brks.krg[-length(brks.krg)],col=color.krg[-1],add=T,legend.width=1,legend.mar=4,legend.line=3,
               legend.lab = 'cells/L')
    title('Ordinary Kriging',outer=T,line=-1.5)
  }
  dev.off()
  
  plt.stack = aniso.clip2
  plt.stack = projectRaster(from=plt.stack,to=flh)
  pdf(gsub("X","",paste0(dir.plt,'\\aniso ',names(plt.stack)[1],"-",names(plt.stack)[nlayers(plt.stack)],' clipped.pdf')),onefile=T)
  for(y in hab.yrs){
    #y=hab.yrs[3]
    yr.idx  = which(substr(names(plt.stack),2,5) == y)
    plt.yr  = plt.stack[[yr.idx]] 
    par(mfrow=c(4,3),mar=c(1,1,2,0),oma=c(2,2,2,6))
    for(i in 1:nlayers(plt.yr)){
      #i=1
      plot(plt.yr[[i]],legend=F,col=color.krg,colNA='darkgray',breaks=brks.krg)
      #main=paste(month.abb[as.numeric(substr(names(plt.yr)[i],6,7))],substr(names(plt.yr)[i],2,5)))
      text(-86.5,25.5,paste(month.abb[as.numeric(substr(names(plt.yr)[i],6,7))],substr(names(plt.yr)[i],2,5)),cex=1.1)
      #overlay coastline map of Florida
      #map(database='county',add=T,fill=T,col='wheat',border='gray')
      map(database='state',add=T,fill=T,col='wheat')
    }
    #add legend
    par(mfrow=c(1,1),mar=c(0,0,0,0),oma=c(0,0,0,1))
    image.plot(plt.yr,legend.only=T,breaks=brks.krg[-length(brks.krg)],col=color.krg[-1],add=T,legend.width=1,legend.mar=4,legend.line=3,
               legend.lab = 'cells/L')
    title('Anisotropic Kriging',outer=T,line=-1.5)
  }
  dev.off()


#vast
  brks.vst    = c(0,1e4-1,seq(1e4,4e7,10000),1e15)
  nbcols.vst  = length(brks.vst)-1
  color.vst   = funpal.idw(nbcols.vst)
  
  plt.stack = vast.clip2[[which(substr(names(vast.clip2),2,5)%in%hab.yrs)]]
  plt.stack = projectRaster(from=plt.stack,to=flh)
  names(plt.stack)
  windows(record=T)
  pdf(gsub("X","",paste0(dir.plt,'\\SP-GLMM 4k ',names(plt.stack)[1],"-",names(plt.stack)[nlayers(plt.stack)],' clipped.pdf')),onefile=T)
  for(y in hab.yrs){
    #y=doyears[3]
    yr.idx  = which(substr(names(plt.stack),2,5) == y)
    plt.yr  = plt.stack[[yr.idx]] 
    par(mfrow=c(4,3),mar=c(1,1,2,0),oma=c(2,2,2,6))
    for(i in 1:nlayers(plt.yr)){
      #i=1
      plot(plt.yr[[i]],legend=F,col=color.vst,colNA='white',breaks=brks.vst)
      #main=paste(month.abb[as.numeric(substr(names(plt.yr)[i],6,7))],substr(names(plt.yr)[i],2,5)))
      text(-86.5,25.5,paste(month.abb[as.numeric(substr(names(plt.yr)[i],6,7))],substr(names(plt.yr)[i],2,5)),cex=1.1)
      #overlay coastline map of Florida
      #map(database='county',add=T,fill=T,col='wheat',border='gray')
      map(database='state',add=T,fill=T,col='wheat')
    }
    #add legend
    par(mfrow=c(1,1),mar=c(0,0,0,0),oma=c(0,0,0,1))
    image.plot(plt.yr,legend.only=T,breaks=brks.vst[-length(brks.vst)],col=color.vst[-1],add=T,legend.width=1,legend.mar=4,legend.line=3,
               legend.lab = 'cells/L')
    title('SP-GLMM',outer=T,line=-1.5)
  }
  dev.off()
  
#krg variance-------------------------------------------------------------------
krgv.clip2 = krgv.clip2[[which(names(krgv.clip2)=="X200801"):which(names(krgv.clip2)=="X202112")]]
range(krgv.clip2)
vals = getValues(krgv.clip2)
vals[vals==0] = NA
qtl = quantile(vals,probs=c(seq(0,.9,0.1),.95,1),na.rm=T)
brks.krg =   c(0,seq(qtl[1],qtl[11],length.out=10000))
nbcols.krg  = length(brks.krg)-1
color.krg   = funpal.idw(nbcols.krg)
  
#mean variance layer, over all years
krgv.clip2 = projectRaster(krgv.clip2,crs = crs(flh))
meanvar = mean(krgv.clip2)
tiff(paste0(dir.plt,'/KRG mean var layer.tif'),width=7,height=7,units='in',res=600,compression='lzw')
plot(meanvar,col=color.krg,main='Mean Variance from Ordinary Kriging')
map(database='county',add=T,fill=T,col='wheat',border='gray')
map(database='state',add=T,fill=F)
dev.off()

vals = as.numeric(getValues(krgv.clip2))
vals[vals==0] = NA
mean(vals,na.rm=T)
mean(getValues(meanvar),na.rm=T)

#mean var for each month
meanvar.mo = data.frame()
for(i in 1:nlayers(krgv.clip2)){
  #i=1
  vals = getValues(krgv.clip2[[i]])
  vals[vals==0] = NA
  avg = mean(vals,na.rm=T)
  meanvar.mo = rbind(meanvar.mo,data.frame(time=names(krgv.clip2)[i],mean.var=avg))
  
}

mean(meanvar.mo$mean.var)
range(meanvar.mo$mean.var)
quantile(meanvar.mo$mean.var,probs=seq(0,1,0.05))

#plot stack
plt.stack = krgv.clip2
vals = getValues(plt.stack)
vals[vals==0] = NA
qtl = quantile(vals,probs=c(seq(0,.9,0.1),.95,1),na.rm=T)
brks.krg =   c(0,seq(qtl[1],qtl[11],length.out=10000),500)
nbcols.krg  = length(brks.krg)-1
color.krg   = funpal.idw(nbcols.krg)



  plt.stack = projectRaster(from=plt.stack,to=flh)
  hab.yrs = 2008:2021
  plt.stack = plt.stack[[which(substr(names(plt.stack),2,5)%in%hab.yrs)]]
  graphics.off();rm(.SavedPlots);gc();windows(record=T)
  pdf(gsub("X","",paste0(dir.plt,'\\Ordinary Kriging Variance ',names(plt.stack)[1],'-',names(plt.stack)[nlayers(plt.stack)],' clipped.pdf')),onefile=T)
  for(y in hab.yrs){
    #y=hab.yrs[14]
    yr.idx  = which(substr(names(plt.stack),2,5) == y)
    plt.yr  = plt.stack[[yr.idx]] 
    par(mfrow=c(4,3),mar=c(1,1,2,0),oma=c(2,2,2,6))
    for(i in 1:nlayers(plt.yr)){
      #i=1
      plot(plt.yr[[i]],col=color.krg, breaks=brks.krg,legend=F,colNA='darkgray')
      #main=paste(month.abb[as.numeric(substr(names(plt.yr)[i],6,7))],substr(names(plt.yr)[i],2,5)))
      text(-86.5,25.5,paste(month.abb[as.numeric(substr(names(plt.yr)[i],6,7))],substr(names(plt.yr)[i],2,5)),cex=1.1)
      #overlay coastline map of Florida
      map(database='county',add=T,fill=T,col='wheat',border='gray')
      map(database='state',add=T,fill=F,)
    }
    #add legend
    par(mfrow=c(1,1),mar=c(0,0,0,0),oma=c(0,0,0,1))
    image.plot(plt.yr,legend.only=T,breaks=brks.krg[-length(brks.krg)],col=color.krg[-1],add=T,legend.width=1,legend.mar=4,legend.line=3,
               legend.lab = 'cell/L Var in log space')
    title('Ordinary Kriging Variance',outer=T,line=-1.5)
  }
  dev.off()
  

