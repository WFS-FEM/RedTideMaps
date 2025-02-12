####################################################################
####################################################################
##
##    BUILDING A SINGLE-SPECIES VAST MODELS
##    DANIEL VILAS 2/10/2022
##
####################################################################
####################################################################

#load libraries
library(VAST)
library(sp)
library(sf)
library(raster)
library(concaveman)
library(dplyr)
library(tidyr)
library(rnaturalearth)
library(rnaturalearthdata)
library(rgdal)
library(wesanderson)
library(rgdal)
library(raster)
library(ggplot2)
library(ggspatial)
library(stringr)
library(withr)
library(gridExtra)
library(scales)
library(ggspatial)
library(cowplot)
library(ggpubr)
library(grid)

#color palette
pal <- wesanderson::wes_palette("Zissou1", 10, type = "continuous")

#florida polygon for plotting distribution maps
#setwd("E://GAM surveys/General data/")

#set directory
mydir<-'C:/Users/dvilasgonzalez/Downloads/'
setwd(paste0(mydir,'/VAST_DC/'))

#for mapping
githubURL<-('https://raw.githubusercontent.com/danielvilasgonzalez/redtideapp/main/cb_2018_us_nation_5m.shp')
download.file(githubURL,"cb_2018_us_nation_5m.shp", method="curl")
githubURL<-('https://raw.githubusercontent.com/danielvilasgonzalez/redtideapp/main/cb_2018_us_nation_5m.shx')
download.file(githubURL,"cb_2018_us_nation_5m.shx", method="curl")
githubURL<-('https://raw.githubusercontent.com/danielvilasgonzalez/redtideapp/main/cb_2018_us_nation_5m.dbf')
download.file(githubURL,"cb_2018_us_nation_5m.dbf", method="curl")
githubURL<-('https://raw.githubusercontent.com/danielvilasgonzalez/redtideapp/main/cb_2018_us_nation_5m.prj')
download.file(githubURL,"cb_2018_us_nation_5m.prj", method="curl")
us<- raster::shapefile('cb_2018_us_nation_5m.shp')

bbox = c(latN = 30.63428 , latS =  24.92816, lonW = -86.99201, lonE = -80.43161 )
FL <- extent(bbox[3],bbox[4], bbox[2],bbox[1])
fl <- crop(us, FL)

#################################################
# CREATE A EXTRAPOLATION GRID
#################################################

#create a new extrapolation grid
depth = raster(paste0(getwd(),"/crm_crm_vol3.nc"))
proj4string(depth) = CRS("+init=epsg:4269 +proj=longlat +ellps=GRS80 +datum=NAD83 +no_defs +towgs84=0,0,0")
dim(depth)
#1-minute grid cell resolution = 3-arc sec*20
depth2 =  aggregate(depth,fact=20,fun=mean)
depth2 =  aggregate(depth,fact=20,fun=mean)
depth2[depth2>0] = NA
depth2 = depth2*-1
plot(depth2,colNA='gray')
depth2[depth2>250] = NA

depth3<-depth2

depth2[depth2>0] = NA
Lon<--81.2
Lat<-26

#Take a data.frame of coordinates in longitude/latitude that define the outer limits of the region (the extent).
d<-as.matrix(depth3)
dd<-rasterToPolygons(depth3,)

region_extent <- data.frame(long=depth3@data, lat=LL$y)
str(region_extent)

#create a polygon to remove the east (atlantic) part of the rasters
coords = matrix(c(-81.2, 31,
                  -81.2, 26.5,
                  -80, 26.5,
                  -80, 31), 
                ncol = 2,byrow = T)
P1 = Polygon(coords)
Ps1 = SpatialPolygons(list(Polygons(list(P1), ID = "a")), proj4string=CRS("+proj=longlat +ellps=WGS84 +datum=WGS84 +no_defs"))

#depth<-mask(depth,Ps1,inverse=T)
depth4<-mask(depth3,Ps1,inverse=T)

coords = matrix(c(-82, 31,
                  -82, 28.5,
                  -80, 28.5,
                  -80, 31), 
                ncol = 2,byrow = T)
P1 = Polygon(coords)
Ps2 = SpatialPolygons(list(Polygons(list(P1), ID = "a")), proj4string=CRS("+proj=longlat +ellps=WGS84 +datum=WGS84 +no_defs"))

#depth<-mask(depth,Ps1,inverse=T)
depth5<-mask(depth4,Ps2,inverse=T)

plot(depth5)

#get depth coordinates to build mesh
coords.depth = as.data.frame(cbind(coordinates(depth5),getValues(depth5)))
#keep coordinates for WFS only, out to 250m depth
coords.depth = subset(coords.depth,V3<=250 & V3>0)
#ne.idx = which(coords.depth$y>26.68 & coords.depth$x>-81.9) #northeast cells removed
#coords.depth = coords.depth[-ne.idx,]
#matrix of coordinates
coords.depth = coords.depth[,1:2]

#get a polygon from points
pnts<-st_as_sf(coords.depth,coords = c("x", "y"), crs = 4326)
polygon <- concaveman(pnts)
plot(polygon, reset = FALSE)
#plot(pnts, add = TRUE)

polygon<-as(polygon, 'Spatial')

sps <- SpatialPolygonsDataFrame(polygon, data.frame(Id=factor('all')))
proj4string(sps)<- CRS("+proj=longlat +datum=WGS84")
sps <- spTransform(sps, CRS("+proj=longlat +lat_0=90 +lon_0=180 +x_0=0 +y_0=0 +datum=WGS84 +units=m +no_defs +ellps=WGS84 +towgs84=0,0,0 "))
### Get UTM zone for conversion to UTM projection
## retrieves spatial bounding box from spatial data [,1] is
## longitude
lon <- sum(bbox(sps)[1,])/2
## convert decimal degrees to utm zone for average longitude, use
## for new CRS
utmzone <- floor((lon + 180)/6)+1
crs_LL <- CRS('+proj=longlat +ellps=WGS84 +no_defs')
sps@proj4string <- crs_LL

### Create the VAST extroplation grid for method 1 and 2
## Convert the final in polygon to UTM
crs_UTM <- CRS(paste0("+proj=utm +zone=",utmzone," +ellps=WGS84 +datum=WGS84 +units=m +no_defs "))
region_polygon <- spTransform(sps, crs_UTM)

### Construct the extroplation grid for VAST using sf package
## Size of grid **in meters** (since working in UTM). Controls
## the resolution of the grid.
cell_size <- 10000 #2000
## This step is slow at high resolutions
region_grid <- st_make_grid(region_polygon, cellsize = cell_size, what = "centers")
## Convert region_grid to Spatial Points to SpatialPointsDataFrame
region_grid <- as(region_grid, "Spatial")
region_grid_sp <- as(region_grid, "SpatialPointsDataFrame")
## combine shapefile data (region_polygon) with Spatial Points
## (region_grid_spatial) & place in SpatialPointsDataFrame data
## (this provides you with your strata identifier (here called
## Id) in your data frame))
region_grid_sp@data <- over(region_grid, region_polygon)

## Convert back to lon/lat coordinates as that is what VAST uses
region_grid_LL <- as.data.frame(spTransform(region_grid_sp, crs_LL))
region_df <- with(region_grid_LL,
                  data.frame(Lon=coords.x1,
                             Lat=coords.x2, Id=factor('all'),
                             Area_km2=( (cell_size/1000)^2),
                             row=1:nrow(region_grid_LL)))
## Filter out the grid that does not overlap (outside extent)
region <- subset(region_df, !is.na(Id))

## This is the final file needed.
str(region)
plot(region_grid)
## > 'data.frame':	106654 obs. of  5 variables:
##  $ Lon     : num  -166 -166 -166 -166 -166 ...
##  $ Lat     : num  53.9 53.9 54 53.9 53.9 ...
##  $ Id      : Factor w/ 1 level "all": 1 1 1 1 1 1 1 1 1 1 ...
##  $ Area_km2: num  4 4 4 4 4 4 4 4 4 4 ...
##  $ row     : int  401 402 975 976 977 978 1549 1550 1551 1552 ...

### Save it to be read in and passed to VAST later.
saveRDS(region, file = "WFS.rds")
WFS<-readRDS('WFS.rds')
### End of creating user extrapolation region object
### --------------------------------------------------

#################################################
# SPECIES DATA (HERE KARENIA BREVIS CELL CONCENTRATION)
#################################################

#get csv files
lf<-list.files(getwd(),pattern = '.csv')

#bind rows for all csv files
df<-do.call(rbind,lapply(lf, read.csv))
names(df)

#create year factor
df$Year<-substr(df$Sample.Date,nchar(df$Sample.Date)-3,nchar(df$Sample.Date))

#create month factor
df$month<-substr(df$Sample.Date,1,nchar(df$Sample.Date)-7)
unique(df$month)
df$month<-gsub(pattern = '/',
               replacement = '',
               x = df$month)
df$month<-ifelse(nchar(df$month)==1,paste0('0',df$month),paste0(df$month))

#subset for univariate standardization
#df<-subset(df,SPECIESNAME==unique(df$SPECIESNAME)[1:5])

#select relevant information
df<-df[,c("Latitude","Longitude",'Year',"Karenia.brevis.abundance..cells.L.",'month')]

#add sp column
df$species<-'Karenia'

#rename df
names(df)<-c('Lat','Lon','Year','Catch_KG','month','species')
df$Year<-as.numeric(df$Year)

#add non informative swept area and species_number
df$AreaSwept_km2<-0.1
df$species_number<-as.numeric(as.factor(df$species))

plot(df$Lon,df$Lat)
#remove data points out of the EBS
#df<-df[which(df$Lat>=50),]
#df<-df[which(df$Lon<=0),]

#create data
data<-list()

ind<-c(paste0('00',1:9),paste0('0',10:99),100:(12*19))

stack<-stack()
plist<-list()

pdf('red_tide.pdf',width = 10,height = 8,onefile = T)
par(oma=c(0,0,2,0))

#df<-subset(df,Year>=1978)
for (selyear in as.character(c(min(df$Year):max(df$Year)))) {

#select year
#selyear='2002'

#################################################
# VAST MODEL - simple and september2005
#################################################

#subset data
dm<-subset(df,Year==selyear)
dm$month<-as.numeric(as.character(dm$month))

for (j in unique(dm$month)) {
  mm<-subset(dm,month==j)
  #hist(mm[,'Catch_KG'],breaks=25)
}

#check years with 0% encounter
check<-aggregate(dm$Catch_KG,by = list('sp'=dm$species,'month'=dm$month),FUN = sum)
year<-check[which(check$x!=0),'Year']

#keep years with >0% encounter
#df<-df[which(df$Year %in% year),]
data$sampling_data<-dm

#settings
#categories
data$n_c<-length(unique(data$sampling_data$species))
#save(data, file="VAST_redtide.rda")
#load('./VAST_redtide.rda')

if (0 %in% check$x) {
  #model settings
  settings = make_settings( Region='User',
                            purpose="EOF3",
                            n_x=500,
                            knot_method='grid',
                            n_categories=data$n_c,
                            ObsModel=c(1,1), #c(0,1)
                            RhoConfig=c("Beta1"=1,"Beta2"=1,"Epsilon1"=0,"Epsilon2"=0),
                            FieldConfig = c("Omega1"=1, "Epsilon1"=1, "Omega2"=1, "Epsilon2"=1),
                            bias.correct = FALSE,use_anisotropy = TRUE)
  
  } else{
#model settings
settings = make_settings( Region='User',
                          purpose="EOF3",
                          n_x=500,
                          knot_method='grid',
                          n_categories=data$n_c,
                          ObsModel=c(1,1), #c(0,1)
                          RhoConfig=c("Beta1"=0,"Beta2"=0,"Epsilon1"=0,"Epsilon2"=0),
                          FieldConfig = c("Omega1"=1, "Epsilon1"=1, "Omega2"=1, "Epsilon2"=1),
                          bias.correct = FALSE,use_anisotropy = TRUE)
}
#there ase some years with 0% encounter, so we need to provide some structure to the intercepts (Betas)
#https://github.com/nwfsc-assess/geostatistical_delta-GLMM/wiki/What-to-do-with-a-species-with-0%25-or-100%25-encounters-in-any-year

#creating extrapolation grid
#Extrapolation_List = make_extrapolation_info( Region='Other', grid_dim_km = c(6000,6000),
#                                              observations_LL = data$sampling_data[,c("Lat","Lon")])

#Kmeans_Config=list("randomseed"=1,"nstart"=100,"iter.max"=1e3)

#generating the information used for conducting spatio-temporal parameter estimation
#Spatial_List = make_spatial_info( grid_size_km=50,n_x=500, Method="Mesh", 
#                                 Lon=data$sampling_data[,'Lon'], Lat=data$sampling_data[,'Lat'], 
#                                  Extrapolation_List=Extrapolation_List, DirPath=getwd(),
#                                  Save_Results=FALSE, randomseed = Kmeans_Config[["randomseed"]],
#                                  nstart = Kmeans_Config[["nstart"]],iter.max = Kmeans_Config[["itermax"]] )

#adding knots to Data_Geostat
#data$sampling_data = cbind( data$sampling_data, "knot_i"=Spatial_List$knot_i)

# Run model
fit = fit_model( settings=settings,
                 Lat_i=data$sampling_data[,'Lat'],
                 Lon_i=data$sampling_data[,'Lon'],
                 t_i=data$sampling_data[,'month'],
                 c_i=data$sampling_data[,'species_number']-1,
                 b_i=data$sampling_data[,'Catch_KG'],
                 a_i=data$sampling_data[,'AreaSwept_km2'],
                 newtonsteps=0,
                 test_fit = FALSE,
                 getsd=FALSE,
                 Use_REML=TRUE,
                 input_grid=WFS)
                 #spatial_list = Spatial_List,
                 #observations_LL = data$sampling_data[,c("Lat","Lon")]) #,test_fit = FALSE 

# Plot results, including spatial term Omega1
#results = plot( fit,
#                check_residuals=FALSE,
#                category_names = c("Karenia brevis") )


#plot( fit,
#      plot_set=c(1),
#      check_residuals=FALSE,
#      category_names = c("Karenia brevis") )

D_gt <- fit$Report$D_gct[,1,] # drop the category
dimnames(D_gt) <- list(cell=1:nrow(D_gt), year=c(1:12))
## tidy way of doing this, reshape2::melt() does
## it cleanly but is deprecated

D_gt<-data.frame('cell'=c(1:fit$spatial_list$n_g),units::drop_units(D_gt))
colnames(D_gt)<-c('cell',fit$year_labels)

D_gt1<-reshape2::melt(D_gt,id=c('cell'))

mdl <- make_map_info(Region = settings$Region,
                     spatial_list = fit$spatial_list,
                     Extrapolation_List = fit$extrapolation_list)

D <- merge(D_gt1, mdl$PlotDF, by.x='cell', by.y='x2i')

months<-c("Jan",'Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov',"Dec")
plot_list<-list()

#color transparent grid
col_grid <- rgb(235, 235, 235, 100, maxColorValue = 255)

m<-sort(unique(D$variable))

for (i in m) {
#i=1  

D1<-subset(D,variable==i)
D2<-D1[,c("value","Lat","Lon")]
coordinates(D2) <- ~ Lon + Lat
crs(D2)<-c("+proj=longlat +datum=NAD83 +no_defs")
# coerce to SpatialPixelsDataFrame
# coerce to raster
r <- raster(ncol=64, nrow=63)
extent(r)<-extent(D2)
rr<-rasterize(D2,r,'value', fun=max)
#extent(rr)<-extent(D2)


#values(rasterDF)<-D1$value
#extent(rasterDF)<-FL
#names(rasterDF)
#r<-rasterDF
#names(r)<-'value'
#rr<-flip(r,direction='y')
#plot(rr)
#plot(fl,add=T)

#blank polygon
x_coord <- c(-82,  -82, -80, -80)
y_coord <- c(30.5823, 28, 28, 30.5823)
xym <- cbind(x_coord, y_coord)
#xym
##       x_coord  y_coord
## [1,] 16.48438 59.73633
## [2,] 17.49512 55.12207
## [3,] 24.74609 55.03418
## [4,] 22.59277 61.14258
## [5,] 16.48438 59.73633

p = Polygon(xym)
ps = Polygons(list(p),1)
sps = SpatialPolygons(list(ps))
#plot(sps)

## crop and mask
myRaster3 <- resample(depth5, rr, method='bilinear')
#r2 <- crop(r, myRaster3)

#r3<-extend(r,myRaster3,values=NA)
r1 <- overlay(rr, myRaster3, fun = function(x, y) {
  x[is.na(y[])] <- NA
  return(x)
})

p<-rasterVis::gplot(r1) +
  geom_tile(aes(fill=value))+
  geom_polygon(data = sps, aes(x = long, y = lat),fill='white')+
  #geom_sf(data=world,fill = 'grey60', color='grey60',lwd = 0)+
  coord_sf(crs ="+proj=longlat +datum=NAD83 +no_defs", 
           xlim = c(extent(r1)[1],extent(r1)[2]), ylim = c(extent(r1)[4],extent(r1)[3]))+
  #geom_point(data=D1, aes(Lon, Lat, color=log(value), group=NULL),
            ## These settings are necessary to avoid
            ## overlplotting which is a problem here. May need
            ## to be tweaked further.
   #         size=2, stroke=0,shape=16)+
  geom_polygon(data = fl, aes(x = long, y = lat,group = group),
               fill = 'grey60', size = 1)+
  #theme_minimal()+
  theme(legend.title = element_blank(),
        plot.title = element_text(margin = margin(t = 10, b = -20),hjust = 0.9))+ #legend.position=c(1,1)plot.title = element_text(margin = margin(t = 10, b = -20))
  #scale_x_continuous(expand=c(0,0))+
  #scale_y_continuous(expand=c(0,0))+
  #ggtitle(label=j)+
  ggtitle(toupper(months[as.numeric(i)]))+
  xlab('')+
  ylab('')+
  #scale_fill_gradient(values = pal  ,na.value = 'white')+
  scale_fill_gradientn(colours = c("#3B9AB2",  "#EBCC2A", "#E1AF00", "#F21A00"),na.value = 'white',
                       values = scales::rescale(c(-0.5, -0.05, 0, 0.05,0.25, 0.5)), limits=c(0,max(D$value)/4),oob=squish) + #
  
  #scale_fill_gradientn(colours = pal,na.value = 'white')+
  labs(fill = "% of occurrence")+
  annotation_north_arrow(location = "tr", which_north = "true",pad_x = unit(0.01, 'in'), pad_y = unit(0.4, 'in'),
                         style = north_arrow_fancy_orienteering(line_width = 1.5, text_size =6))+
  theme(panel.grid.major = element_line(color = col_grid, linetype = 'dashed', size = 0.5), 
        panel.background = element_rect(fill = NA),panel.ontop = TRUE,text = element_text(size=10),
        plot.margin = unit(c(0.1,0.1,0.1,0.1), "lines"),
        legend.background =  element_rect(fill = "transparent", colour = "transparent"),
        plot.title = element_text(hjust = 0.75,vjust=-1))+
  guides(fill = guide_colorbar(size = 0.5,barwidth = 0.5, barheight = 4,ticks=FALSE))
#+

plot_list[[as.character(i)]]<-p 

ind1<-ind[match(selyear,c(min(df$Year):max(df$Year)))*as.numeric(i)]

names(r1)<-paste0('VASTredtide_',ind1,'_',months[as.numeric(i)],selyear)

#save raster

stack <- addLayer(stack, r1)

}


prow <- plot_grid(
  plot_list$`1`+ theme(legend.position="none"),
  plot_list$`2`+ theme(legend.position="none"),
  plot_list$`3`+ theme(legend.position="none"),
  plot_list$`4`+ theme(legend.position="none"),
  plot_list$`5`+ theme(legend.position="none"),
  plot_list$`6`+ theme(legend.position="none"),
  plot_list$`7`+ theme(legend.position="none"),
  plot_list$`8`+ theme(legend.position="none"),
  plot_list$`9`+ theme(legend.position="none"),
  plot_list$`10`+ theme(legend.position="none"),
  plot_list$`11`+ theme(legend.position="none"),
  plot_list$`12`+ theme(legend.position="none"),
  align = 'vh',
  hjust = -1,
  nrow = 3)

# extract the legend from one of the plots
legend <- get_legend(
  # create some space to the left of the legend
  plot_list$`8` + theme(legend.box.margin = margin(0,0,0,0))
)


plots<-plot_grid(prow, legend, rel_widths = c(3, .25))

#grid::grid.newpage()
title <- ggdraw() + draw_label(paste0(selyear), fontface='bold')
# add the legend to the row we made earlier. Give it one-third of 
# the width of one plot (via rel_widths).
#tiff(filename = paste0('./red_tide ',selyear,'.tif'),res = 300,width = 3200,height = 2100)
plist[[selyear]]<-plot_grid(title,plots, ncol=1, rel_heights=c(0.1, 1))
#grid::grid.newpage()
#dev.off()

#tiff(filename = paste0('./red_tide ',selyear,'.tif'),res = 300,width = 3200,height = 2100)
#plot_grid(title,plots, ncol=1, rel_heights=c(0.1, 1))
#dev.off()
#if (selyear=='2003') {
  
#  pdf('red_tide.pdf',width = 10,height = 8,onefile = T)}

#grid::grid.newpage()
#plot_grid(title,plots, p, ncol=1, rel_heights=c(0.1, 1))
#grid::grid.newpage()
#dev.off()
}

dev.off()
#

writeRaster(stack,"VASTredtide.grd")


for (i in 1:length(plist)) {
  #i=1
  selyear<-names(plist)[i]
  tiff(filename = paste0('./red_tide ',selyear,'.tif'),res = 300,width = 3200,height = 2100)
  plot(plist[[selyear]])
  dev.off()
  
  
}
