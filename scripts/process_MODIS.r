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
  library('curl')
  library('rerddap')

#pull MODIS from ERDDAP---------------------------------------------------------
fn.pull_MODIS_flh_erddap <- function(){
  bbox = extent(raster(file.depth))#bbox.gom
  
  #date label for naming output files
  today.lab = format(Sys.Date(),"%Y%m%d")
  currmonth = substr(today.lab,1,6)
  
  varname = 'flh' #varlist$var[i]
  
  ##get erddap dataset info----
  url.erddap = 'https://coastwatch.pfeg.noaa.gov/erddap/'
  ed_datasets = cbind(do.call(rbind.data.frame,ed_search(query=paste0(varname,' global modis'),url=url.erddap)$alldata),var=varname)
  ed_datasets = ed_datasets[,c('dataset_id','var','institution','title')]
  ed_datasets = ed_datasets[which(substr(ed_datasets$dataset_id,1,4)=='erdM'),]
  
  drops = c(grep("DEPRECATED|8 Day|5 Day|EXPERIMENTAL|Lon0360",ed_datasets$title),which(substr(ed_datasets$title,1,3) %in% c('Dif','Pho')),grep('NotMasked',ed_datasets$dataset_id))
  ed_datasets = ed_datasets[-drops,]
  dup.ids = ed_datasets$dataset_id[duplicated(ed_datasets$dataset_id)]
  rem.ids = which(ed_datasets$dataset_id %in% dup.ids & ed_datasets$var=='chla')
  if(length(rem.ids)>0) ed_datasets = ed_datasets[-rem.ids,]
  ed_datasets$res = ifelse(grepl("1day",ed_datasets$dataset_id),'day',ifelse(grepl("mday",ed_datasets$dataset_id),'month','other'))
  ed_datasets$t_end = ed_datasets$t_start = as.Date(NA); 
  
  #get times available
  for(i in 1:nrow(ed_datasets)){
    #i=1
    tmp.info = info(ed_datasets$dataset_id[i],url=url.erddap)$alldata$time
    t0 = as.Date(substr(tmp.info$value[which(tmp.info$attribute_name=='time_origin')],1,11),format="%d-%b-%Y")
    t1 = as.numeric(unlist(strsplit(tmp.info$value[which(tmp.info$attribute_name=='actual_range')],split=',')))
    t2 = as.Date(as.POSIXct(t1,origin=t0,tz='GMT'))
    ed_datasets$t_start[i] = t2[1]
    ed_datasets$t_end[i] = t2[2]
  }
  ed_datasets = ed_datasets[order(ed_datasets$var,ed_datasets$res,ed_datasets$dataset_id),c(1,2,5:7,3,4)]
  
  write.csv(ed_datasets,paste0(dir.modis,'/erddap_modis_datasets_',today.lab,'.csv'),row.names=F)
  
  print(paste0('Now processing ',varname));flush.console()
  dir.out = dir.modis.raw
  var_datasets.m = ed_datasets[ed_datasets$var==varname & ed_datasets$res=='month',]
  var_datasets.d = ed_datasets[ed_datasets$var==varname & ed_datasets$res=='day',]
  
  avail.months = format(seq.Date(min(var_datasets.m$t_start),max(var_datasets.m$t_end),'month'),"%Y%m")
  avail.months = data.frame(yrmo=avail.months, datid=NA)
  for(m in 1:nrow(avail.months)){
    #m=278
    mm = as.numeric(avail.months$yrmo[m])
    t1 = as.numeric(gsub("-","",substr(var_datasets.m$t_start,1,7)))<=mm
    t2 = as.numeric(gsub("-","",substr(var_datasets.m$t_end,1,7)))>=mm
    dat.idx = max(which(t1&t2))
    avail.months$datid[m]=var_datasets.m$dataset_id[dat.idx]
  }
  avail.days = seq.Date(min(var_datasets.d$t_start),max(var_datasets.d$t_end),'day')
  
  
  #get existing stack-----------------------------------------------------------------------------------
  files.flh = list.files(path=dir.modis.raw, pattern=".gri$",full.names=T)
  if(length(files.flh)>0) {
    stack.in = stack(gsub(".gri","",files.flh[length(files.flh)]))
    stack.in = stack.in[[sort(names(stack.in))]]
    have.months = gsub("X","",names(stack.in))
    do.months = avail.months[which(!avail.months$yrmo %in% as.numeric(have.months)),]
    last.day = as.Date(substr(basename(files.flh),nchar(basename(files.flh))-11,nchar(basename(files.flh))-4),format="%Y%m%d")
    update.days = ifelse(max(do.days)>last.day,TRUE,FALSE)
  } else{
    stack.in = stack()
    do.months = avail.months
    update.days = TRUE
  }
  do.days = avail.days[which(!as.numeric(gsub("-","",substr(avail.days,1,7)))%in%avail.months$yrmo)]
  
  #monthly layers-----------------------------------------------------------------------------------
  #first, update with available monthly stacks, will always pull the last month from existing stack again
  s.m = stack()
  for(d in unique(do.months$datid)){
    #d = "erdMH1cflhmday_R2022SQ"
    do.months.d = do.months$yrmo[do.months$datid==d]
    erd.info1 <- griddap(info(d,url=url.erddap),latitude = c('last','last'),longitude = c('last','last'))
    erd.time1 = data.frame(time=erd.info1$data$time)
    erd.time1$month = substr(erd.time1$time,6,7)
    erd.time1$yrmo = gsub("-","",substr(erd.time1$time,1,7))
    erd.time1 = erd.time1[which(as.numeric(erd.time1$yrmo)>=do.months.d[1]),]
    erd1 <- griddap(info(d,url=url.erddap),latitude = bbox[3:4],longitude = bbox[1:2],time = erd.time1$time[c(1,nrow(erd.time1))])
    stack.d = stack(erd1$summary$filename,quick=T)#,varname='chlorophyll'
    names(stack.d) = erd.time1$yrmo
    keepers = which(gsub("X","",names(stack.d))%in%do.months.d)
    if(length(keepers)>0) {
      stack.d = stack.d[[keepers]]
      s.m = addLayer(s.m,stack.d)
    }
  }
  dim(s.m); names(s.m)
  
  #daily layers-------------------------------------------------------------------------------------
  #next, get NRT daily data for current or incomplete months
  #do.days = c(as.Date(paste0(as.numeric(tail(erd.time1$yrmo,1))+1,'01'),format="%Y%m%d"),var_datasets.d$t_end[which.max(var_datasets.d$t_end)])
  s.m2=stack()
  if(update.days){
    do.datid.d = var_datasets.d$dataset_id[which.max(var_datasets.d$t_end)]
    erd.info2 <- griddap(info(do.datid.d,url=url.erddap),latitude = c('last','last'),longitude = c('last','last'))
    erd.time2 = data.frame(time=erd.info2$data$time)
    erd.time2$month = substr(erd.time2$time,6,7)
    erd.time2$yrmo = gsub("-","",substr(erd.time2$time,1,7))
    erd.time2$date = as.Date(erd.time2$time)
    erd.time2 = erd.time2[which(erd.time2$date>=do.days[1]),]
    erd2 <- griddap(info(do.datid.d,url=url.erddap),latitude = bbox[3:4],longitude = bbox[1:2],time = erd.time2$time[c(1,nrow(erd.time2))])
    s.d = stack(erd2$summary$filename,quick=T)#,varname='chlorophyll'
    names(s.d) = erd.time2$date
    #monthly average
    s.m2 = stackApply(s.d,indices=erd.time2$yrmo,fun=mean,na.rm=T)
    dim(s.m2)
    names(s.m2) = sort(unique(erd.time2$yrmo))
  }
  
  #full stack-------------------------------------------------------------------
  dim(stack.in);dim(s.m);dim(s.m2);
  if(dim(stack.in)[3]==0){
    if(dim(s.m)[3]>0 & dim(s.m2)[3]>0) stack.out = stack(s.m,s.m2)#addLayer(stack.in[[-nlayers(stack.in)]],s.m)
    if(dim(s.m)[3]>0 & dim(s.m2)[3]==0) stack.out = s.m #addLayer(stack.in[[-nlayers(stack.in)]],s.m)
    if(dim(s.m)[3]==0 & dim(s.m2)[3]>0) stack.out = s.m2 #addLayer(stack.in[[-nlayers(stack.in)]],s.m)
  }
  if(dim(stack.in)[3]>0){
    if(dim(s.m)[3]>0 & dim(s.m2)[3]>0) stack.out = stack(stack.in,s.m,s.m2)#addLayer(stack.in[[-nlayers(stack.in)]],s.m)
    if(dim(s.m)[3]>0 & dim(s.m2)[3]==0) stack.out = stack(stack.in,s.m) #addLayer(stack.in[[-nlayers(stack.in)]],s.m)
    if(dim(s.m)[3]==0 & dim(s.m2)[3]>0) stack.out = stack(stack.in,s.m2) #addLayer(stack.in[[-nlayers(stack.in)]],s.m)
  }
  dim(stack.out)
  names(stack.out)
  plot(stack.out)
  
  #write raster-----------------------------------------------------------------
  file.modis.raw =  file.path(dir.modis.raw,paste0(varname,'_',paste(round(as.matrix(bbox),1),collapse="_"),"_",gsub("X","",names(stack.out)[1]),"-",gsub("-","",tail(erd.time2$date,1))))
  writeRaster(stack.out,filename=file.modis.raw,overwrite=T)
  if(length(files.flh)>0){
    unlink(files.flh)
    unlink(gsub(".gri",".grd",files.flh))
  }
  return(file.modis.raw)
}

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
  
  #file.clipped2 <<- paste0(dir.sdmout,"/",gsub("[0-9-]","",basename(file.pred)),gsub("X","",names(pred.clipped)[1]),"-",gsub("X","",names(pred.clipped)[nlayers(pred.clipped)]),"_clipped_modis")
  file.clipped.modis <- gsub("X","",paste0(gsub(".grd","",paste0(gsub("[0-9-]","",basename(file.pred))) ),names(pred.clipped)[1],"-",names(pred.clipped)[nlayers(pred.clipped)],"_clipped_modis"))
  writeRaster(pred.clipped,file.path(dir.sdmout,file.clipped.modis),overwrite=T)
  return(pred.clipped)
}
  
#make nFLH polygons------------------------------------------------------------------
#Hu et al (2005) suggest nFLH values >= .012 are indicative of high Chl-a;  Due
#to changes in calibration algorithms the threshold to detect HABs is now 0.02 (personal communication with Chaunmin)
fn.make_nflh_polys <- function(dir.in=dir.modis.raw, dir.out=dir.modis){
  #dir.in=dir.modis.raw; dir.out=dir.modis
  
#add a check to only execute function if existing poly file is outdated compared to existing flh stack.  
#bring in nFLH raster stack from MODIS
files.flhstack = list.files(dir.in, pattern='.grd$', full.names=T)
flh = stack(gsub(".grd","",files.flhstack))
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
file.flhpolys = paste0(dir.modis,"/FLH polys ",substr(basename(files.flhstack),nchar(basename(files.flhstack))-18,nchar(basename(files.flhstack))-4),".Rdata")
save(flh.polys, file=file.flhpolys)
modis.numpolys  <<- data.frame(yrmo=names(flh),
                             npolys=sapply(1:length(flh.polys),function(x) length(flh.polys[[x]][[1]])))
return(file.flhpolys)
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

