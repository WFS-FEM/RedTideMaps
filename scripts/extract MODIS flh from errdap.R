#rm(list=ls());gc()
library('curl')
library('raster')
library('rerddap')
#remotes::install_github("ropensci/rerddap")

####################################################################################################
# SETUP
####################################################################################################
#dir.base = getwd()

#geographic extent
#bbox.gom = c(-98,-80.5,24,31)
#bbox.wfs = c(-88,-80.5,25,30.5)
bbox = extent(raster(file.depth))#bbox.gom

#date label for naming output files
today.lab = format(Sys.Date(),"%Y%m%d")
currmonth = substr(today.lab,1,6)

####################################################################################################
# CREATE FULL LIST OF ERDDAP DATA TO QUERY
#######################################################################################################
url.erddap = 'https://coastwatch.pfeg.noaa.gov/erddap/'
#ed_datasets = cbind(do.call(rbind.data.frame,ed_search(query=paste0(varlist$var[1],' global modis'),url=url.erddap)$alldata),var=varlist$var[1])
ed_datasets = cbind(do.call(rbind.data.frame,ed_search(query=paste0('flh global modis'),url=url.erddap)$alldata),var='flh')
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

#######################################################################################################
# EXTRACT MODIS DATA FROM NOAA ERDDAP SERVER https://coastwatch.pfeg.noaa.gov/erddap/index.html
#######################################################################################################
  varname = 'flh' #varlist$var[i]
  print(paste0('Now processing ',varname));flush.console()
  dir.out = dir.modis.raw
  var_datasets.m = ed_datasets[ed_datasets$var==varname & ed_datasets$res=='month',]
  var_datasets.d = ed_datasets[ed_datasets$var==varname & ed_datasets$res=='day',]
  #var_datasets = var_datasets[order(var_datasets$use),]
  #setwd(dir.out)
  getwd()
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
  stack.in = stack(files.flh[length(files.flh)])
  have.months = gsub("X","",names(stack.in))
  do.months = avail.months[which(!avail.months$yrmo %in% as.numeric(have.months)),]
  #do.months = avail.months
  do.days = avail.days[which(!as.numeric(gsub("-","",substr(avail.days,1,7)))%in%avail.months$yrmo)]
  #erdMH1cflh1day_R2022NRT
  
  
  #monthly layers-----------------------------------------------------------------------------------
  #first, update with available monthly stacks, will always pull the last month from existing stack again
  s.m = stack()
  for(d in unique(do.months$datid)){
    #d = "erdMH1cflhmday_R2022NRT"
    do.months.d = do.months$yrmo[do.months$datid==d]
    erd.info1 <- griddap(info(d,url=url.erddap),latitude = c('last','last'),longitude = c('last','last'))
    erd.time1 = data.frame(time=erd.info1$data$time)
    erd.time1$month = substr(erd.time1$time,6,7)
    erd.time1$yrmo = gsub("-","",substr(erd.time1$time,1,7))
    erd.time1 = erd.time1[which(as.numeric(erd.time1$yrmo)>=do.months.d[1]),]
    erd1 <- griddap(info(d,url=url.erddap),latitude = bbox[3:4],longitude = bbox[1:2],time = erd.time1$time[c(1,nrow(erd.time1))])
    stack.d = stack(erd1$summary$filename,quick=T)#,varname='chlorophyll'
    names(stack.d) = erd.time1$yrmo
    s.m = addLayer(s.m,stack.d)
  }
  dim(s.m); names(s.m)
  
  #daily layers-------------------------------------------------------------------------------------
  #next, get NRT daily data for current or incomplete months
  do.days = c(as.Date(paste0(as.numeric(tail(erd.time1$yrmo,1))+1,'01'),format="%Y%m%d"),
              var_datasets.d$t_end[which.max(var_datasets.d$t_end)])
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
  
  #full stack-------------------------------------------------------------------
  dim(stack.in);dim(s.m);dim(s.m2);
  stack.out = addLayer(stack.in[[-nlayers(stack.in)]],addLayer(s.m,s.m2))
  #stack.out = stack(s.m, s.m2)
  dim(stack.out)
  names(stack.out)
  #write raster
  file.modis.raw =  file.path(dir.modis.raw,paste0(varname,'_',paste(round(as.matrix(bbox),1),collapse="_"),"_",gsub("X","",names(stack.out)[1]),"-",gsub("-","",tail(erd.time2$date,1))))
  writeRaster(stack.out,filename=file.modis.raw,overwrite=T)
  unlink(files.flh)
  unlink(gsub(".gri",".grd",files.flh))
  return(file.modis.raw)










