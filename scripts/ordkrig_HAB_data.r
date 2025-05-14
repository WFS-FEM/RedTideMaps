library('automap')

#kriging----------------------------------------------------------------------
fn.hab_ordkrig_monthly <- function(file.habRdat=paste0(dir.data,"/",file.habRdat),styr=1985){
  
  depth <- raster(file.depth)
  load(file.habRdat)
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
  
hab.nkb1000 = aggregate(cells~month+year,data=hab.dat,FUN=function(x) length(x[x>=1000]))
vgmmods = as.character(vgm()$short)
#plotkrig=F
krg.pred.bt = krg.pred = krg.var = stack()
vgpars.out = data.frame()
start.time = gsub(":","",Sys.time())
#dev.off()
windows(record=T)
dir.create(dir.ordkrig)
pdf(paste0(dir.ordkrig,'/ordkrig variograms ',times[1],"-",tail(times,1),'.pdf'),onefile=T)
for(i in 1:length(times)){
  #mos = unique(fwri.maxk$month[fwri.maxk$year==y])
  #par(mfrow=c(4,3))
  #for(m in mos){
  #i=1
  y = as.numeric(format(times[i],"%Y"))
  m = as.numeric(format(times[i],"%m"))
  hab.sub        = hab.dat[hab.dat$year==y & hab.dat$month==m,]
  
  if(length(which(hab.sub$cells>=1000))>5){
    
  #y=2005;m=9  #error thrown for March 2016 EXp,nug=9.6,sill=11,range=0.01
  kdat = hab.sub
  idx.dup = which(duplicated(kdat@coords))
  if(length(idx.dup)>0){
    kdat@coords[idx.dup,1] = kdat@coords[idx.dup,1]*runif(length(idx.dup),min=0.995,1.005)
    kdat@coords[idx.dup,2] = kdat@coords[idx.dup,2]*runif(length(idx.dup),min=0.995,1.005)
  }
  nkb = length(kdat$cells[kdat$cells>=1000])
  print(paste("Now kriging",format(times[i],"%Y-%m")));flush.console()
  #table(kdat$k_brevis)
  if(y==2016 & m==3){
    kb.krig = autoKrige(log(cells+1)~1,input_data=kdat,new_data=hab.grid,model='Exp',fix.values=c(9.6,NA,NA),verbose=F) #fix.values=c(9.6,.01,11)
  } else {
    kb.krig = autoKrige(log(cells+1)~1,input_data=kdat,new_data=hab.grid,model=c('Sph','Exp','Ste'),verbose = F)
  }
  plot(kb.krig,xlab=as.character(times[i]))
  krast = raster(kb.krig$krige_output)
  krast.var = raster(kb.krig$krige_output['var1.var'])
  vgpars.out = rbind(vgpars.out,data.frame(year=y,month=m,
                         nug=kb.krig$var_model$psill[1],
                         psill=kb.krig$var_model$psill[2],
                         range=kb.krig$var_model$range[2]))
  #backtransform----
  #I want to pull the backtransform out as a separate function
  out.pred = kb.krig$krige_output
  mu = out.pred$var1.pred  
  sigma2 = out.pred$var1.var
  out.pred.bt = exp(mu+0.5*sigma2)
  kb.krig$krige_output$pred.bt = out.pred.bt
  krast.bt = raster(kb.krig$krige_output['pred.bt'])
    
  } else{
    krast = krast.bt = krast.var = raster(hab.grid)
    krast[] = 0
    krast.bt[] = 0
    krast.var[] = 0
  }
  names(krast) = names(krast.bt) = names(krast.var) = paste0("X",y,formatC(m,width=2,flag=0))
  krg.pred.bt = addLayer(krg.pred.bt,krast.bt)
  krg.pred = addLayer(krg.pred,krast)
  krg.var = addLayer(krg.var,krast.var)
  rm(vgm.list,out.pred);gc()
  if(i==length(times)) dev.off()
}
dev.off()
write.csv(vgpars.out,paste0(dir.ordkrig,'/ordkrig vg pars ',times[1],"-",tail(times,1),'.csv'),row.names=F)
writeRaster(krg.pred, paste0(dir.ordkrig,'/ordkrig pred ',times[1],"-",tail(times,1)),overwrite=T)
writeRaster(krg.pred.bt, paste0(dir.ordkrig,'/ordkrig bt ',times[1],"-",tail(times,1)),overwrite=T)
writeRaster(krg.var, paste0(dir.ordkrig,'/ordkrig var ',times[1],"-",tail(times,1)),overwrite=T)
ordkrig.bt <<-krg.pred.bt

}

#Back transformation------------------------------------------------------------
#need to work on this
fn.ordkrig_backtran <- function(){
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
}


#Plot IDW-----------------------------------------------------------------------
fn.plot_ordkrig <- function(file.ordkrigstack=list.files(dir.ordkrig,pattern="^ordkrig bt",full.names=T)[1]){
  #idw.out.file = unique(gsub('.grd',"",gsub('.gri',"",list.files(dir.out,pattern="^IDW"))))[1]
  #idw.out = stack(paste0(dir.out,"/",idw.out.file)); 
  #names(idw.out)
  file.ordkrigstack = list.files(dir.ordkrig,pattern=".grd",full.names=T)[2]
  krg.out = stack(file.ordkrigstack)
  #idw.out = projectRaster(from=idw.out,to=flh)
  krg.vals = getValues(krg.out)
  krg.vals = krg.vals[!is.na(krg.vals)]
  krg.vals = krg.vals[!is.infinite(krg.vals)]
  brks    = c(0,1000,seq(10000,10000000,100000),max(krg.vals))
  colv    = c("white","light gray","purple", "blue", "darkblue", "cyan", "green","darkgreen", "yellow", "orange", "red", "darkred")
  funpal  = colorRampPalette(colv,bias=2)
  nbcols  = length(brks)-1
  color   = funpal(nbcols) 

  plt.stack = krg.out
  plt.yrs = sort(unique(as.numeric(substr(names(plt.stack),2,5))))
  #pdf(paste0(dir.ordkrig,'/',gsub('.grd','.pdf',basename(file.ordkrigstack))),onefile=T)
  #windows(record=T)
  for(y in plt.yrs){
    #y=plt.yrs[1]
    #y=2005
    yr.idx  = which(substr(names(plt.stack),2,5) == y)
    plt.yr  = plt.stack[[yr.idx]] 
    par(mfrow=c(4,3),mar=c(1,1,2,0),oma=c(2,2,0,6))
    for(i in 1:nlayers(plt.yr)){
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







  
