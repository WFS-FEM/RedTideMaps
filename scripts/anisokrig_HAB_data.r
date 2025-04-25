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

##########################################################################################
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






  
