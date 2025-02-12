.libPaths("C:\\R\\win-library")

#library('devtools')
#install_github("james-thorson/VAST", INSTALL_opts="--no-staged-install")
library('VAST')
library('raster')
library('sf')
library('concaveman')

setwd("G:\\My Drive\\WFS EwE shared\\red tide\\red tide cell count data\\VAST")

#################################################
# CREATE A EXTRAPOLATION GRID
#################################################

#create a new extrapolation grid
#depth = raster(paste0(getwd(),"/crm_crm_vol3.nc"))
depth = raster("G:\\My Drive\\WFS EwE shared\\Ecospace\\Bathymetry\\depth_WFS_4km")
depth
depth2 = depth
depth2[depth2>250] = NA
plot(depth2,colNA='gray')

#proj4string(depth) = CRS("+init=epsg:4269 +proj=longlat +ellps=GRS80 +datum=NAD83 +no_defs +towgs84=0,0,0")
#1-minute grid cell resolution = 3-arc sec*20
#depth2 =  aggregate(depth,fact=20,fun=mean)
#depth2 =  aggregate(depth,fact=20,fun=mean)
#depth2[depth2>0] = NA
#depth2 = depth2*-1
#plot(depth2,colNA='gray')
#depth2[depth2>250] = NA
#depth3<-depth2
#depth2[depth2>0] = NA
#Lon<--81.2
Lat<-26

#Take a data.frame of coordinates in longitude/latitude that define the outer limits of the region (the extent).
d<-as.matrix(depth2)
dd<-rasterToPolygons(depth2)

#region_extent <- data.frame(long=depth2@data, lat=Lat)
region_extent = extent(depth2)
str(region_extent)

#create a polygon to remove the east (atlantic) part of the rasters
coords = matrix(c(-81.2, 31,
                  -81.2, 26.5,
                  -80, 26.5,
                  -80, 31), 
                ncol = 2,byrow = T)
P1 = Polygon(coords)
Ps1 = SpatialPolygons(list(Polygons(list(P1), ID = "a")), proj4string=CRS("+proj=longlat +ellps=WGS84 +datum=WGS84 +no_defs"))

depth3<-mask(depth2,Ps1,inverse=T)

coords = matrix(c(-82, 31,
                  -82, 28.5,
                  -80, 28.5,
                  -80, 31), 
                ncol = 2,byrow = T)
P1 = Polygon(coords)
Ps2 = SpatialPolygons(list(Polygons(list(P1), ID = "a")), proj4string=CRS("+proj=longlat +ellps=WGS84 +datum=WGS84 +no_defs"))

depth4<-mask(depth3,Ps2,inverse=T)
plot(depth4,colNA='black')


#get depth coordinates to build mesh
depth5 = depth4
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
df = read.csv("G:\\My Drive\\WFS EwE shared\\red tide\\red tide cell count data\\FL Kb salinity temp 2002-2021.10.26.csv")
#lf<-list.files(getwd(),pattern = '.csv')

#bind rows for all csv files
#df<-do.call(rbind,lapply(lf, read.csv))
names(df)

#create year factor
#df$Year<-substr(df$Sample.Date,nchar(df$Sample.Date)-3,nchar(df$Sample.Date))
df$Sample.Date = as.Date(df$Sample.Date,"%m/%d/%Y")
df$Year = format(df$Sample.Date,"%Y")
df$month = format(df$Sample.Date,"%m")

#create month factor
# df$month<-substr(df$Sample.Date,1,nchar(df$Sample.Date)-7)
# unique(df$month)
# df$month<-gsub(pattern = '/',
#                replacement = '',
#                x = df$month)
# df$month<-ifelse(nchar(df$month)==1,paste0('0',df$month),paste0(df$month))

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

#################################################
# VAST MODEL - simple and september2005
#################################################
#pdf('red_tide.pdf',width = 10,height = 8,onefile = T)
par(oma=c(0,0,2,0))

#df<-subset(df,Year>=1978)
for (selyear in as.character(c(min(df$Year):max(df$Year)))) {
  
  #select year
  selyear='2002'
  
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
    #ObsModel = c(1,1): first column is distribution of positive catch rates and second is for encounter probabilities; 
    #ObsModel[2]=1 corresponds to a Poiosson-link delta model that approximates a Tweedie
    settings = make_settings( Region='User',
                              purpose="EOF3",
                              n_x=500,
                              knot_method='grid',
                              n_categories=data$n_c,
                              ObsModel=c(1,1), #c(0,1)
                              RhoConfig=c("Beta1"=0,"Beta2"=0,"Epsilon1"=0,"Epsilon2"=0),
                              FieldConfig = c("Omega1"=1, "Epsilon1"=1, "Omega2"=1, "Epsilon2"=1),
                              #Omega1 = 1: 
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
  