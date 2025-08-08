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
depth<-raster('/Users/dvilasgonzalez/Documents/WFS_DV2/WFS-FEM/static drivers/depth/depth 4min 82x97.asc')
clip_extent <- extent(depth)
#land mask
land_mask <- calc(depth, fun = function(x) {
  ifelse(is.na(x) | x > 250, NA, 1)
})
plot(land_mask)

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
load('/Users/dvilasgonzalez/Documents/WFS_DV2/WFS-FEM/ST drivers/red tides/data/habsos_20240430_filtered.RData')

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

save(pol_list, file = '/Users/dvilasgonzalez/Documents/WFS_DV2/WFS-FEM/ST drivers/red tides/hab_pols/pol_list.RData')

library(raster)
library(sf)

#setwd
idir<-'/Users/dvilasgonzalez/Documents/WFS_DV2/WFS-FEM/ST drivers/red tides/'

#observations
load(paste0(idir,'/data/habsos_20240430_filtered.RData'))
filtered_points_df

#list files RT sdmTMB predictions
logsdm.files<-list.files(paste0(idir,'/sdmTMB RT rasters'),pattern = '*log.asc$')
nbsdm.files<-list.files(paste0(idir,'/sdmTMB RT rasters'),pattern = '*nb.asc$')

#list files RT severity (after clipping)
logsev.files<-list.files(paste0(idir,'/RT severity rasters'),pattern = '*log.asc$')
nbsev.files<-list.files(paste0(idir,'/RT severity rasters'),pattern = '*nb.asc$')

#get matching years
yyyymm<-substr(sev.files,1,6)

# make a regex pattern like "201209|201210|201211"
yyyymm1 <- paste(yyyymm, collapse = "|")

#subset
logsdm.files1 <- logsdm.files[grepl(yyyymm1, basename(logsdm.files))]
nbsdm.files1 <- nbsdm.files[grepl(yyyymm1, basename(nbsdm.files))]
logsev.files1 <- logsev.files[grepl(yyyymm1, basename(logsev.files))]
nbsev.files1 <- nbsev.files[grepl(yyyymm1, basename(nbsev.files))]

library(raster)
library(sf)
library(dplyr)
library(pROC)

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


for (i in yyyymm) {
  
  #i<-yyyymm[1]
  
  cat("Processing:", i, "\n")
  
  # Extract polygon
  p <- pol_list[[i]]
  
  y <- substr(i, 1, 4)
  m <- substr(i, 5, 6)
  
  # Load predicted raster
  r_pred <- raster(paste0(idir, '/sdmTMB RT rasters/', y, m, '_predsdmTMBnb.asc'))
  
  # Transform polygon CRS to raster CRS
  p <- st_transform(p, crs = crs(r_pred))
  
  # Rasterize polygon (1 inside polygon, NA outside)
  mask_raster <- rasterize(p, r_pred, field=1, background=NA)
  
  # Mask predicted raster with polygon mask: outside polygon to NA
  r_pol <- mask(r_pred, mask_raster)
  # Set NA outside polygon to 0
  r_pol[is.na(r_pol)] <- 0
  
  # Load severity raster
  r_sev <- raster(paste0(idir, '/RT severity rasters/', y, m, '_RTsevnb.asc'))
  
  # Apply land mask from depth raster to exclude shallow/land pixels
  r_pred <- mask(r_pred, land_mask)
  r_pol <- mask(r_pol, land_mask)
  r_sev <- mask(r_sev, land_mask)
  
  # Extract values from rasters as vectors
  pred_vals <- getValues(r_pred)
  mean_pred<-mean(pred_vals,na.rm=TRUE)
  pol_vals <- getValues(r_pol)
  sev_vals <- getValues(r_sev)
  
  # Remove NA pairs to compare for continuous metrics
  valid_pred_pol <- !is.na(pred_vals) & !is.na(pol_vals)
  valid_pred_sev <- !is.na(pred_vals) & !is.na(sev_vals)
  
  # Continuous metrics for r_pol vs r_pred
  rmse_pol <- sqrt(mean((pred_vals[valid_pred_pol] - pol_vals[valid_pred_pol])^2))/mean_pred
  cor_pol <- cor(pred_vals[valid_pred_pol], pol_vals[valid_pred_pol])
  r2_pol <- cor_pol^2
  
  # Continuous metrics for r_sev vs r_pred
  rmse_sev <- sqrt(mean((pred_vals[valid_pred_sev] - sev_vals[valid_pred_sev])^2))/mean_pred
  cor_sev <- cor(pred_vals[valid_pred_sev], sev_vals[valid_pred_sev])
  r2_sev <- cor_sev^2
  
  # Convert to binary presence/absence with threshold = 1000
  bin_threshold <- 1000
  
  pred_bin <- ifelse(pred_vals > bin_threshold, 1, 0)
  pol_bin <- ifelse(pol_vals > bin_threshold, 1, 0)
  sev_bin <- ifelse(sev_vals > bin_threshold, 1, 0)
  
  # Remove NA pairs for binary metrics
  valid_bin_pol <- !is.na(pred_bin) & !is.na(pol_bin)
  valid_bin_sev <- !is.na(pred_bin) & !is.na(sev_bin)
  
  # Binary accuracy for r_pol vs r_pred
  TP_pol <- sum(pol_bin[valid_bin_pol] == 1 & pred_bin[valid_bin_pol] == 1)
  TN_pol <- sum(pol_bin[valid_bin_pol] == 0 & pred_bin[valid_bin_pol] == 0)
  FP_pol <- sum(pol_bin[valid_bin_pol] == 1 & pred_bin[valid_bin_pol] == 0)
  FN_pol <- sum(pol_bin[valid_bin_pol] == 0 & pred_bin[valid_bin_pol] == 1)
  
  Accuracy_pol <- (TP_pol + TN_pol) / length(pred_bin[valid_bin_pol])
  
  # Binary accuracy for r_sev vs r_pred
  TP_sev <- sum(sev_bin[valid_bin_sev] == 1 & pred_bin[valid_bin_sev] == 1)
  TN_sev <- sum(sev_bin[valid_bin_sev] == 0 & pred_bin[valid_bin_sev] == 0)
  FP_sev <- sum(sev_bin[valid_bin_sev] == 1 & pred_bin[valid_bin_sev] == 0)
  FN_sev <- sum(sev_bin[valid_bin_sev] == 0 & pred_bin[valid_bin_sev] == 1)
  
  Accuracy_sev <- (TP_sev + TN_sev) / length(pred_bin[valid_bin_sev])
  
  # Calculate AUC for pol vs pred
  auc_pol <- tryCatch({
    roc_obj <- roc(pol_bin[valid_bin_pol], pred_bin[valid_bin_pol], quiet = TRUE)
    auc(roc_obj)
  }, error = function(e) NA_real_)
  
  # Calculate AUC for sev vs pred
  auc_sev <- tryCatch({
    roc_obj <- roc(sev_bin[valid_bin_sev], pred_bin[valid_bin_sev], quiet = TRUE)
    auc(roc_obj)
  }, error = function(e) NA_real_)
  
  # Append row to dataframe
  results_df <- bind_rows(results_df, tibble(
    yyyymm = i,
    rrmse_pol = rmse_pol,
    r2_pol = r2_pol,
    accuracy_pol = Accuracy_pol,
    auc_pol = as.numeric(auc_pol),
    n_cells_pol = sum(valid_pred_pol),
    
    rrmse_sev = rmse_sev,
    r2_sev = r2_sev,
    accuracy_sev = Accuracy_sev,
    auc_sev = as.numeric(auc_sev),
    n_cells_sev = sum(valid_pred_sev)
  ))
}

# Combine results into a dataframe
library(tidyr)
library(ggplot2)

# Reshape results_df to long format for AUC and RRMSE
results_long <- results_df %>%
  pivot_longer(
    cols = c(auc_pol, auc_sev, rrmse_pol, rrmse_sev),
    names_to = c("metric", "method"),
    names_sep = "_",
    values_to = "value"
  )

# Check the reshaped data (optional)
head(results_long)

# Plot boxplot for AUC
ggplot(filter(results_long, metric == "auc"), aes(x = method, y = value, fill = method)) +
  geom_boxplot(outlier.shape = NA) +  # no outliers shown, adjust if you want
  geom_jitter(width = 0.15, alpha = 0.5) +  # add points
  labs(title = "AUC (Polygon vs VIIRS) relative predictions", x = "Method", y = "AUC") +
  theme_minimal() +
  theme(legend.position = 'none')+
  scale_x_discrete(labels=c('polygon','viirs'))+
  scale_fill_brewer(palette = "Set1")

# Plot boxplot for RRMSE
ggplot(filter(results_long, metric == "rrmse"), aes(x = method, y = value, fill = method)) +
  geom_boxplot(outlier.shape = NA) +
  geom_jitter(width = 0.15, alpha = 0.5) +
  labs(title = "RRMSE (Polygon vs VIIRS) relative predictions", x = "Method", y = "RRMSE") +
  theme_minimal() +
  scale_y_continuous(limits=c(0,10))+
  theme(legend.position = 'none')+
  scale_x_discrete(labels=c('polygon','viirs'))+
  scale_fill_brewer(palette = "Set1")





