#D:/WFS_DV/Ecospace/Drivers from ZS/Scripts/03_Extract_nFLH.R



#load libraries
library(raster)
library('reticulate')
library('raster')
library(ncdf4)
library(ggplot2)
library(viridis)
library(sf)
library(dplyr)
library(ggplot2)
library(concaveman)  

#MODIS FHL as VIIRS (2003-2012) ####
#threshold to 0.02 (Soto 2013; Hu personal communication).
s<-stack('C:/Users/dvilasgonzalez/Documents/WFS_DV2/WFS-FEM/ST drivers/MODIS/flh/flh_-98_-80.5_24_31_200301-20250601.gri')
#plot(s)

# Define the extent to clip to: xmin, xmax, ymin, ymax
# For example, clip to: longitude -95 to -85, latitude 25 to 30
depth<-raster('/Users/dvilasgonzalez/Documents/WFS_DV2/WFS-FEM/static drivers/depth/depth 1min 330x390.asc')
clip_extent <- extent(depth)

# Crop the stack
s1 <- crop(s, clip_extent)

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
  plot(flh.sub)
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
getwd()
save(flh.polys.new,file=paste0('./ST drivers/MODIS/flh/',gsub("X","",paste0('/FLH polys ',names(flh.polys.new)[1],'-',names(flh)[dim(flh)[3]],'.Rdata'))))



# from HABSOS to polygons to restrict spatially with buffer ####

#read data
load('./ST drivers/red tides/data/habsos_20240430_filtered.RData')

#check
head(filtered_points_df)
unique(filtered_points_df$year)

#check years with data
habyrs<-unique(filtered_points_df$year)
habyrs<-sort(habyrs[which(habyrs %in% 1985:1993)])

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
    list_name <- sprintf("%d_%02d", y, m)
    pol_list[[list_name]] <- hab_pol
    
  }
}

save(pol_list, file = './ST drivers/red tides/hab_pols/pol_list.RData')



# Chuanmin approach accuracy pre-clipping ####
library(terra)
library(pROC)
library(dplyr)

# Load VIIRS FLH stack
flh_stack <- rast("/Users/dvilasgonzalez/Documents/WFS_DV2/WFS-FEM/ST drivers/red tides/data/raw/VIIRS_redtide_maps_0.1degree/VIIRS_freq_raster_stack.grd")
names(flh_stack) <- gsub("X", "", names(flh_stack))  # clean layer names like "X201201" → "201201"

# Path to your new SDM prediction rasters
pred_path <- "/Users/dvilasgonzalez/Documents/WFS_DV2/WFS-FEM/ST drivers/red tides/sdmTMB RT rasters/"
pred_files <- list.files(pred_path, pattern = "predsdmTMB.*\\.asc$", full.names = TRUE)

# Filter only files for 2012 and after (FLH only available post-2012)
post2012_files <- pred_files[as.numeric(substr(basename(pred_files), 1, 6)) >= 201201]

# Function to evaluate accuracy of a prediction raster vs. VIIRS
evaluate_accuracy <- function(pred_file, flh_layer_name, threshold = 10000) {
  pred <- rast(pred_file)
  flh <- flh_stack[[flh_layer_name]]
  
  # Resample to match FLH resolution
  pred <- resample(pred, flh, method = "bilinear")
  
  pred_vals <- values(pred)
  flh_vals <- values(flh)
  
  # Convert FLH to binary red tide: presence = 1, absence = 0
  flh_bin <- ifelse(!is.na(flh_vals) & flh_vals != 0, 1, 0)
  
  # Remove NAs
  idx <- which(!is.na(pred_vals) & !is.na(flh_bin))
  pred_vals <- pred_vals[idx]
  flh_bin <- flh_bin[idx]
  
  # Threshold SDM prediction to binary
  pred_bin <- ifelse(pred_vals > threshold, 1, 0)
  
  # Confusion matrix
  TP <- sum(pred_bin == 1 & flh_bin == 1)
  TN <- sum(pred_bin == 0 & flh_bin == 0)
  FP <- sum(pred_bin == 1 & flh_bin == 0)
  FN <- sum(pred_bin == 0 & flh_bin == 1)
  
  # AUC
  roc_obj <- tryCatch({
    roc(flh_bin, pred_vals)
  }, error = function(e) NA)
  
  auc_val <- if (inherits(roc_obj, "roc")) auc(roc_obj) else NA
  
  list(
    TP = TP, TN = TN, FP = FP, FN = FN,
    Sensitivity = TP / (TP + FN),
    Specificity = TN / (TN + FP),
    AUC = auc_val
  )
}

# Evaluate each file and track model type (log or nb)
results <- list()
for (file in post2012_files) {
  yyyymm <- substr(basename(file), 1, 6)
  model_type <- ifelse(grepl("log", file), "log", "nb")
  
  if (yyyymm %in% names(flh_stack)) {
    cat("Evaluating:", yyyymm, "-", model_type, "\n")
    res <- evaluate_accuracy(file, flh_layer_name = yyyymm)
    results[[paste0(yyyymm, "_", model_type)]] <- c(res, Model = model_type, Month = yyyymm)
  } else {
    cat("Skipping (no FLH layer):", yyyymm, "\n")
  }
}

# Combine into a dataframe
df <- bind_rows(results)

# Summarize by model type
summary_stats <- df %>%
  group_by(Model) %>%
  summarise(
    Mean_AUC = mean(AUC, na.rm = TRUE),
    Mean_Sensitivity = mean(Sensitivity, na.rm = TRUE),
    Mean_Specificity = mean(Specificity, na.rm = TRUE),
    n = n()
  )

print(summary_stats)