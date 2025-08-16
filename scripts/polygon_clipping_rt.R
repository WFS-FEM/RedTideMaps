#Spatial clipping to restrict the HAB extrapolations using FLH and convex hull

#load libraries
library(raster)
library(reticulate)
library(ncdf4)
library(ggplot2)
library(viridis)
library(sf)
library(dplyr)
library(concaveman)  
library(dplyr)

# Get system user
user <- Sys.info()[["user"]]

# Define user-specific paths
if (user == "dchagaris") {
  wd <- "C:/Users/dchagaris/OneDrive - University of Florida/WFS Fisheries Ecosystem Modeling/red tide maps"
  wd.depth <- "C:/Users/dchagaris/OneDrive - University of Florida/WFS Fisheries Ecosystem Modeling/WFS EwE/Ecospace/maps/bathymetry"
  scripts_path <- "C:/Users/dchagaris/Documents/Github/RedTideMaps/scripts"
} else if (user == "dvilasgonzalez") {
  wd <- "C:/Users/dvilasgonzalez/Documents/WFS_DV2/WFS-FEM/ST drivers/red tides/"
  wd.depth <- "C:/Users/dvilasgonzalez/Documents/WFS_DV2/WFS-FEM/static drivers/depth/"
  scripts_path <- "C:/Users/dvilasgonzalez/Documents/Github/RedTideMaps/scripts"
} else {
  message("User not recognized. Please select working and depth directories.")
  wd <- choose.dir(caption = "Select your red tide maps working directory")
  if (is.na(wd)) stop("No working directory selected. Exiting.")
  
  wd.depth <- choose.dir(caption = "Select your bathymetry maps directory")
  if (is.na(wd.depth)) stop("No depth map directory selected. Exiting.")
  
  scripts_path <- choose.dir(caption = "Select the directory containing your scripts")
  if (is.na(scripts_path)) stop("No scripts directory selected. Exiting.")
}

#MODIS FHL polygons (2003-2012) ####
#threshold to 0.02 (Soto 2013; Hu personal communication).
s<-stack(paste0(dirname(wd),'/MODIS/flh/flh_-98_-80.5_24_31_200301-20250601.gri'))
#plot(s)

# Define the extent to clip to: xmin, xmax, ymin, ymax
# For example, clip to: longitude -95 to -85, latitude 25 to 30
depth<-raster(paste0(wd.depth,'/depth 4min 82x97.asc'))
clip_extent <- extent(depth)
#land mask
land_mask <- calc(depth, fun = function(x) {
  ifelse(is.na(x) | x > 250, NA, 1)
})
plot(land_mask)

# Crop the stack
s1 <- crop(s, clip_extent)

#adjust units
flh<-s1
flh = flh/10
#Hu et al (2005) suggest nFLH values >= .012 are indicative of high Chl-a;  Due
#to changes in calibration algorithms the threshold to detect HABs is now 0.02 (personal communication with Chaunmin)
threshold = 0.02 
flh.polys.new = list()

# for(i in 1:nlayers(flh)){
#   i=1
#   print(names(flh)[i]);flush.console()
#   flh.sub         = flh[[i]]
#   flh.sub[flh.sub>=threshold] = 10
#   flh.poly        = rasterToPolygons(flh.sub,n=16,fun=function(x){x==10},dissolve=T)
#   flh.lines       = as(flh.poly,'SpatialLinesDataFrame')
#   flh.poly        = rgeos::gPolygonize(list(flh.lines))
#   flh.polys.new[[i]]  = flh.poly
#   names(flh.polys.new)[i] = names(flh)[i]
#   rm(flh.sub,flh.poly,flh.lines);gc()
# }

for (i in 1:length(names(flh))) {
  
  #i<-33
  
  print(names(flh)[i]);flush.console()
  # 1. Threshold raster
  flh.sub <- flh[[i]]
  flh.sub[flh.sub >= threshold] <- 10
  #flh.sub[flh.sub <= threshold] <- NA
  #plot(flh.sub)
  # 2. Convert to polygons (RasterLayer → SpatialPolygonsDataFrame)
  flh.poly <- rasterToPolygons(flh.sub, n = 16, fun = function(x) x == 10, dissolve = TRUE)
  
  # 3. Convert to sf and extract boundaries (polygon to lines)
  flh.lines <- sf::st_as_sf(flh.poly) |> sf::st_cast("MULTILINESTRING")
  
  # 4. Polygonize lines
  flh.poly.sf <- sf::st_polygonize(flh.lines)
  
  # 5. Store output
  flh.polys.new[[i]] <- flh.poly.sf
  names(flh.polys.new)[i] <- names(flh)[i]
  
  # 6. Clean up
  rm(flh.sub, flh.poly, flh.lines); gc()
}

#add to old polygon list and save
names(flh.polys.new)  
#flh.polys = flh.polys.new  #if doing all months
save(flh.polys.new,file=paste0(dirname(wd),'/MODIS/flh/',gsub("X","",paste0('/FLH polys ',names(flh.polys.new)[1],'-',names(flh)[dim(flh)[3]],'.Rdata'))))

#HABSOS polygons (1985-2024) ####
# from HABSOS to polygons to restrict spatially with buffer (set to 5km)
#read data
load(paste0(wd,'/data/habsos_20240430_filtered.RData'))

#check
head(filtered_points_df)
unique(filtered_points_df$year)

#check years with data
habyrs<-unique(filtered_points_df$year)
habyrs<-sort(habyrs[which(habyrs %in% 1985:2025)])

# Create an empty list to store buffered hulls
pol_list <- list()

for (y in habyrs) {
  
  #y<-habyrs[1]
  
  ypoints<-subset(filtered_points_df,year==y)
  
  months<- sort(unique(ypoints$month))
  
  for (m in months) {
    
    #m<-months[1]
    
    cat(paste('##################### ',m,y,' ###\n'))
    
    
    mpoints<-subset(ypoints,month==m)
    
    pospoints<-subset(mpoints,cells!=0)
    
    if (nrow(pospoints)==0) {
      next
    }
    
    # Assuming your points are in an sf object called pospoints
    # Check the CRS
    st_crs(pospoints)
    
    # Step 1: Project to a metric CRS (for accurate buffering)
    # Use UTM zone 17N (covers Florida area)
    pospoints_proj <- st_transform(pospoints, crs = 32617)
    
    # Step 2: Create a convex hull (or concave if preferred)
    # Concave hull (more precise shape)
    hull <- concaveman(pospoints_proj)
    
    # Step 3: Add a buffer (e.g., 5 km)
    buffer_km <- 5
    hull_buffered <- st_buffer(hull, dist = buffer_km * 1000)
    
    # Step 4: Transform back to WGS84 if needed
    hab_pol <- st_transform(hull_buffered, crs = 4326)
    
    # # Step 5: Plot
    # ggplot() +
    #   geom_sf(data = hull_buffered_wgs84, fill = 'lightblue', alpha = 0.4) +
    #   geom_sf(data = pospoints, color = 'red', size = 2) +
    #   theme_minimal()
    
    # Save to list with name like "1985_09"
    list_name <- sprintf("%d%02d", y, m)
    pol_list[[list_name]] <- hab_pol
    
  }
}

dir.create(paste0(wd,'/hab_pols'))
save(flh.polys.new,file=paste0(wd,'/hab_pols/pol_list.RData'))

#setwd
idir<-wd

#observations
load(paste0(idir,'/data/habsos_20240430_filtered.RData'))
filtered_points_df

#list files RT sdmTMB predictions
logsdm.files<-list.files(paste0(idir,'/sdmTMB RT rasters'),pattern = '*log.asc$')
nbsdm.files<-list.files(paste0(idir,'/sdmTMB RT rasters'),pattern = '*nb.asc$')

#list files RT severity (after clipping)
logsev.files<-list.files(paste0(idir,'/RT severity rasters/VIIRS'),pattern = '*log.asc$')
nbsev.files<-list.files(paste0(idir,'/RT severity rasters/VIIRS'),pattern = '*nb.asc$')

#get matching years
yyyymm<-substr(nbsev.files,1,6)

# make a regex pattern like "201209|201210|201211"
yyyymm1 <- paste(yyyymm, collapse = "|")

#subset
logsdm.files1 <- logsdm.files[grepl(yyyymm1, basename(logsdm.files))]
nbsdm.files1 <- nbsdm.files[grepl(yyyymm1, basename(nbsdm.files))]
logsev.files1 <- logsev.files[grepl(yyyymm1, basename(logsev.files))]
nbsev.files1 <- nbsev.files[grepl(yyyymm1, basename(nbsev.files))]

#to store results
results_df <- tibble(
  yyyymm = character(),
  rrmse_pol = numeric(),
  r2_pol = numeric(),
  accuracy_pol = numeric(),
  auc_pol = numeric(),
  n_cells_pol = integer(),
  rrmse_sev = numeric(),
  r2_sev = numeric(),
  accuracy_sev = numeric(),
  auc_sev = numeric(),
  n_cells_sev = integer()
)

#save stack of severity with polygon for all years
ifiltered_points_df<-subset(filtered_points_df,year>=1985)
allyyyymm<-paste0(ifiltered_points_df$year,sprintf("%02d", ifiltered_points_df$month))
sort(unique(allyyyymm))

for (res in c(4,6,10)) {
  
  #create folders
  dir.create(paste0(idir,'/RT severity rasters/',res,'min/FLH/'))
  dir.create(paste0(idir,'/RT severity rasters/',res,'min/HAB'))
  
  
  #clipping ####
  for (i in sort(unique(allyyyymm))) {
    
    #i<-sort(unique(allyyyymm))[3]
    
    cat("Processing:", i, "\n")
    
    # Extract polygon
    p <- pol_list[[i]]
    
    #year and month
    y <- substr(i, 1, 4)
    m <- substr(i, 5, 6)
    
    for (res in c(4,6,10)) {
      
      dir.sdmout  <- paste0(wd, res,"min/sdm out")
      
      #log and nb extrapolations
      for (var in c('log','nb')) {
    
        r_pred <- raster(paste0(idir, '/sdmTMB RT rasters/', y, m, '_predsdmTMB',var,'.asc')) #make more sense to choose log (only positives) instead of nb, because the filtering of presence is done by VIIRS, MODIS FLH and convex hull

        if (var=='log') {
          pred.stack<-list.files(dir.sdmout,"/sdmTMB_log_stack_")
          
        } else if (var=='nb') {
          pred.stack<-list.files(dir.sdmout,"/sdmTMB_nb_stack_")
        }
        
        r_pred <-pred_stack[[paste0(y,m)]]
        #if no raster or polygon
        if (is.null(p) | is.null(r_pred)) {
          next
        }
        
        # Transform polygon CRS to raster CRS
        p <- st_transform(p, crs = crs(r_pred))
        
        # Rasterize polygon (1 inside polygon, NA outside)
        mask_raster <- rasterize(p, r_pred, field=1, background=NA)
        
        # Mask predicted raster with polygon mask: outside polygon to NA
        hab_raster <- mask(r_pred, mask_raster)
        
        # Set NA outside polygon to 0
        hab_raster[is.na(hab_raster)] <- 0
        
        # Apply land mask from depth raster to exclude shallow/land pixels
        hab_raster <- mask(hab_raster, land_mask)
        #plot(hab_raster)
        
        #save raster
        writeRaster(hab_raster,paste0(idir,'RT severity rasters/',res,'min/HAB/',y,m,'_RTsev',var,'.asc'),overwrite=TRUE)
        
        if (y>=2003) {
          
          #select flh polygon
          flh<-flh.polys.new[[paste0('X', y, m)]]
          
          # Transform polygon CRS to raster CRS
          flh <- st_transform(flh, crs = crs(r_pred))
          
          #rasterize
          flh <- st_collection_extract(flh, "POLYGON")
          flh$poly_id <- seq_len(nrow(flh))
          mask_raster <- rasterize(as(flh, "Spatial"), r_pred, field = 1, background = NA)
          
          # Mask predicted raster with polygon mask: outside polygon to NA
          fhl_raster <- mask(r_pred, mask_raster)
          # Set NA outside polygon to 0
          fhl_raster[is.na(fhl_raster)] <- 0
          
          # Apply land mask from depth raster to exclude shallow/land pixels
          fhl_raster <- mask(fhl_raster, land_mask)
          
          #save raster
          writeRaster(hab_raster,paste0(idir,'RT severity rasters/',res,'min/FLH/',y,m,'_RTsev',var,'.asc'),overwrite=TRUE)
        }
      }
    }
  }
}
