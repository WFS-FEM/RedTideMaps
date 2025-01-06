rm(list=ls());gc()
.libPaths("C:\\R\\win-library")
library('curl')
library('raster')
library('rerddap')
#remotes::install_github("ropensci/rerddap")

####################################################################################################
# SETUP
####################################################################################################
dir.base = getwd()

#geographic extent
bbox.gom = c(-98,-80.5,24,31)
bbox.wfs = c(-88,-80.5,25,30.5)
bbox = bbox.gom

#get existing inventory of queried data to update---------------------------------------------------
dir.modis = "./MODIS"
dir.vars = list.dirs(dir.modis,recursive=F)
varlist = data.frame(var=basename(dir.vars),dir=dir.vars)
varlist = varlist[varlist$var!="Zd",]
varlist$date.en = varlist$date.st = as.Date(NA,format="%Y%m%d")

for(i in 1:nrow(varlist)){
  #i=1
  st1 = list.files(varlist$dir[i], pattern=".gri$")[1]
  date1 = substr(st1,  tail(unlist(gregexpr("_",st1)),1)+1,nchar(st1)-4)
  varlist$date.st[i] = as.Date(paste0(substr(date1,1,unlist(gregexpr("-",date1))-1),'01'),format="%Y%m%d")
  varlist$date.en[i] = as.Date(paste0(substr(date1,unlist(gregexpr("-",date1))+1,nchar(date1))),format="%Y%m%d")
}

#date label for naming output files
today.lab = format(Sys.Date(),"%Y%m%d")

####################################################################################################
# CREATE FULL LIST OF ERDDAP DATA TO QUERY
#######################################################################################################
url.erddap = 'https://coastwatch.pfeg.noaa.gov/erddap/'
ed_datasets = cbind(do.call(rbind.data.frame,ed_search(query=paste0(varlist$var[1],' global modis'),url=url.erddap)$alldata),var=varlist$var[1])
for(i in 2:nrow(varlist)){
  ed_datasets = rbind(ed_datasets,cbind(do.call(rbind.data.frame,ed_search(query=paste0(varlist$var[i],' global modis'),url=url.erddap)$alldata),var=varlist$var[i]))
}
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
#ed_datasets = read.csv(paste0(dir.modis,'/erddap_modis_datasets_20230914.csv'))
varlist
for(i in 2:nrow(varlist)){
  #i=5
  setwd(dir.base)
  varname = varlist$var[i]
  print(paste0('Now processing ',i,' of ',nrow(varlist),': ',varname));flush.console()
  dir.out = varlist$dir[i]
  var_datasets.m = ed_datasets[ed_datasets$var==varname & ed_datasets$res=='month',]
  var_datasets.d = ed_datasets[ed_datasets$var==varname & ed_datasets$res=='day',]
  #var_datasets = var_datasets[order(var_datasets$use),]
  setwd(dir.out)
  getwd()

  #get existing stack-----------------------------------------------------------------------------------
  stack.in = stack(list.files(pattern=".gri$",full.names=F)[1])
  
  #monthly layers-----------------------------------------------------------------------------------
  #first, update with available monthly stacks, will always pull the last month from existing stack again
  do.months = gsub("-","",c(substr(varlist$date.en[i],1,7),substr(var_datasets.m$t_end[which.max(var_datasets.m$t_end)],1,7)))
  do.datid.m = var_datasets.m$dataset_id[which.max(var_datasets.m$t_end)]
  
  erd.info1 <- griddap(info(do.datid.m,url=url.erddap),latitude = c('last','last'),longitude = c('last','last'))
  erd.time1 = data.frame(time=erd.info1$data$time)
  erd.time1$month = substr(erd.time1$time,6,7)
  erd.time1$yrmo = gsub("-","",substr(erd.time1$time,1,7))
  erd.time1 = erd.time1[which(erd.time1$yrmo>=do.months[1]),]
  erd1 <- griddap(info(do.datid.m,url=url.erddap),latitude = bbox[3:4],longitude = bbox[1:2],time = erd.time1$time[c(1,nrow(erd.time1))])
  s.m = stack(erd1$summary$filename,quick=T)#,varname='chlorophyll'
  names(s.m) = erd.time1$yrmo
  
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
  
  #add to existing stack
  dim(stack.in);dim(s.m);dim(s.m2);
  stack.out = addLayer(stack.in[[-nlayers(stack.in)]],addLayer(s.m,s.m2))
  dim(stack.out)
  names(stack.out)
  
  #write raster
  ras.name =  paste0(varname,'_',paste(bbox,collapse="_"),"_",gsub("X","",names(stack.out)[1]),"-",gsub("-","",tail(erd.time2$date,1)))
  writeRaster(stack.out,filename=ras.name,overwrite=T)
  
  #Integrate surface cholorphyll over euphotic depth-------------------------------------------------
  if(varname == 'chla'){
    Zd.m = calc(stack.out, function(x) 34*(x^-0.39)) #Lee (2007) z1%
    
    #total cholorphyll in euphotic zone from surface chlorophyll: equations 3b and 3c in Morel and Berthon (1989)
    Ctot = calc(stack.out,function(x) ifelse(x<=1,38*x^0.423,40.3*x^0.505))  
    
    #euphotic depth calculated from total chlorophyll: Equation 6 in Morel and Maritorena (2001), updated equations from M&B 1989 
    Zehat1 = 912.5*Ctot^-0.839  #for Ze<102m
    Zehat2 = 426.3*Ctot^-0.547  #for Ze>102m
    #if Ze is > 102, replace with second equation
    Zehat = Zehat1
    Zehat[] = ifelse(Zehat1[]>102,Zehat2[],Zehat[])
    
    #mean concentration in euphotic depth
    Cze = Ctot/Zehat
    
    #integrated over true euphotic depth from satellite
    Cint = Cze*Zd.m
    names(Cint) = names(stack.out)
    
    #write raster
    ras.name =  paste0('chlaxZe_',paste(bbox,collapse="_"),"_",gsub("X","",names(stack.out)[1]),"-",gsub("-","",tail(erd.time2$date,1)))
    writeRaster(Cint,filename=ras.name,overwrite=T)
  }
  rm(s.d,s.m,s.m2,stack.out,erd1,erd2,Zd.m,Ctot,Zehat1,Zehat2,Zehat,Cze,Cint,erd.info1,erd.info2,erd.time1,erd.time2);gc()
}










#old code below here, it think -----------------------------------------------------------------
#crop and resample to Ecospace domain and resolution (based on 10 min depth map)
s2 = crop(s2,depth)
s2 = resample(s2,depth)

#add to NASA stack
s3 = stack(s,s2)
names(s3)

#######################################################################################################
# ADD RECENT 8d SATELLITE IMAGERY FROM ERDAP SERVER (ZACH'S PULLDOWN)
#######################################################################################################
#s3 = stack('Chla WFS stack 200207-202106')
erd.info1 = info("erdMH1chla8day")
erd.info <- griddap(info("erdMH1chla8day"),
                    latitude = c('last','last'),longitude = c('last','last'))
erd.time = data.frame(time=erd.info$data$time)
erd.time$month = substr(erd.time$time,6,7)
erd.time$yrmo = gsub("-","",substr(erd.time$time,1,7))
erd.time = erd.time[which(!erd.time$yrmo %in% gsub("X","",names(s))),]


#GOM grid (big pull takes awhile)
erd <- griddap(erd.info1,
               latitude = c(22,31),
               longitude = c(-100, -80),
               time = erd.time$time[c(1,nrow(erd.time))])

#raster stack
s2 = stack(erd$summary$filename,quick=T)#,varname='chlorophyll'
names(s2) 

#monthly average
s2 = stackApply(s2,indices=erd.time$yrmo,fun=mean,na.rm=T)
names(s2) = unique(erd.time$yrmo)
#crop and resample to Ecospace domain and resolution (based on 10 min depth map)
s2 = crop(s2,depth)
s2 = resample(s2,depth)

#add to NASA stack
s3 = stack(s,s2)
names(s3)

#######################################################################################################
# OUTPUT
#######################################################################################################
#save raster stacks
writeRaster(s3,gsub("X","",paste0(var.label,' WFS stack ',names(s3)[1],'-',names(s3)[nlayers(s3)])),overwrite=T)
s3 = stack("CHLA WFS stack 200207-202108")

#identify which ascii files need to be written
asc.files = list.files(dir.asc.out,pattern="*.asc")
idx.ascdate = c(gregexpr("_y",asc.files[1])[[1]][1]+2,gregexpr("_m",asc.files[1])[[1]][1]+2)
asc.have = paste0(substr(asc.files,idx.ascdate[1],idx.ascdate[1]+3),substr(asc.files,idx.ascdate[2],idx.ascdate[2]+1))
asc.need = names(s3)[which(!gsub("X","",names(s3)) %in% asc.have)]

#subset stack for needed files
names(s3)
s4 = s3[[asc.need]]
dim(s4)

#write ascii
sufx = paste0('y',substr(asc.need,2,5),'_m',substr(asc.need,6,7))
writeRaster(s4,paste0(dir.asc.out,'\\',var.label),bylayer=T,suffix=sufx,format='ascii')

#######################################################################################################
# EUPHOTIC DEPTH
#######################################################################################################
dir.ed = "C:\\Users\\dchagaris\\Google Drive\\WFS EwE shared\\Ecospace\\data extraction\\MODIS Aqua\\euphotic depth"
Ze1 = stack(paste0(dir.ed,"\\EUPHOTIC_DEPTH WFS stack 200207-202106"))
dim(Ze1);names(Ze1)
if(var.label=='CHLA'){
  fn.Ze = function(x) 34.0*(x^-0.39)
  beginCluster()
   Ze = clusterR(s3,calc,args=list(fun=fn.Ze))
  endCluster()
  dim(Ze);names(Ze)
  names(Ze) = names(s3)
}

Ze = Ze[[which(!names(Ze) %in% names(Ze1))]]
Ze2 = stack(Ze1,Ze)
dim(Ze2);names(Ze2)
writeRaster(Ze2,paste0(dir.ed,"\\EUPHOTIC_DEPTH WFS stack ",gsub("X","",names(Ze2)[1]),"-",gsub("X","",names(Ze2)[nlayers(Ze2)])),overwrite=T)
