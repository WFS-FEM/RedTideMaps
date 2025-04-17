# Settings #####
#remove and empty objects
rm(list=ls());gc()

#load libraries
library(sdmTMB)
library(lubridate)
library(ggplot2)
library(raster)
library(sf)
library(rnaturalearth)
library(cowplot)
library(scales)
library(ggh4x)
library(viridis)
library(terra)

#set.seed
set.seed(6)

#set directory based on user and OS
if (Sys.info()['user']=='daniel') {
  #mydir<-'/Users/daniel/Work/VAST_DC/'
  mydir<-'/Users/daniel/Work/WFS_DV2/WFS-FEM/'
  setwd(mydir)
} else if (Sys.info()['user']=='dvilasgonzalez') {
  #mydir<-'/Users/daniel/Work/VAST_DC/'
  mydir<-'C:/Users/dvilasgonzalez/Documents/WFS_DV2/WFS-FEM/'
  setwd(mydir)
} else {
  if (.Platform$OS.type == "windows") {setwd(choose.dir())} else {setwd(tcltk::tk_choose.dir())}
}

#Prepare red tides dataset #####
#load depth and exclusion depth rasters to be used as a sample raster
depth <- raster('./static drivers/depth/depth 4min 82x97.asc')
excl_depth <- raster('./static drivers/depth/excl layer 4min 82x97.asc')

#get US polygon as an sf object
us <- ne_countries(country = "united states of america", scale = 10, returnclass = "sf")

#plot original US polygon
plot(us$geometry)

# Remove all non-geometry columns
us <- us["geometry"]

#convert raster extent to an sf-compatible bounding box
us_bbox <- st_as_sfc(st_bbox(depth))

#crop to U.S. region using sf functions
us_cropped <- st_crop(us, us_bbox)
us_cropped <- st_cast(us_cropped, "POLYGON")
#plot cropped version
plot(us_cropped$geometry)

#create data folder
dir.create('./ST drivers/red tides/',showWarnings = FALSE)
dir.create('./ST drivers/red tides/data/processed',showWarnings = FALSE)
setwd('./ST drivers/red tides/')

#convert extent(depth) to an sf polygon
depth_extent <- st_as_sf(st_as_sfc(st_bbox(depth)))

#convert exclusion depth raster to polygons and then to sf object
excl_depth <- rasterToPolygons(excl_depth, dissolve = TRUE)
excl_depth_sf <- st_as_sf(excl_depth)

#perform intersection
us_clipped_sf <- st_intersection(us_cropped, depth_extent)

#define coordinates of polygon, ensuring the first point is repeated as the last
coords <- matrix(c(-82, 28.5, 
                   -80.5, 28.5, 
                   -80.5, 31, 
                   -82, 31, 
                   -82, 28.5),  # Explicitly repeat the first point to close the polygon
                 ncol = 2, byrow = TRUE)

#create the polygon (now properly closed)
Ps2_sf <- st_sf(geometry = st_sfc(st_polygon(list(coords))), crs = st_crs(depth))

#ensure all geometries are in the same CRS
us_clipped_sf <- st_transform(us_clipped_sf, st_crs(depth))
excl_depth_sf <- st_transform(excl_depth_sf, st_crs(depth))
Ps2_sf <- st_transform(Ps2_sf, st_crs(depth))

#arrange polygons
us_clipped_sf <- st_make_valid(us_clipped_sf)
us_clipped_sf_polygons <- st_cast(us_clipped_sf, "POLYGON")

#combine polygons sequentially using st_union
combined_polygons_1 <- st_union(us_clipped_sf, Ps2_sf)
all_polygons <- st_union(combined_polygons_1, excl_depth_sf)

#union of all polygons where we don't want sampling points (land, atlantic or excl cells)
all_polygons_single <- st_union(us_clipped_sf, Ps2_sf)
all_polygons_single <- st_union(all_polygons_single, excl_depth_sf)
all_polygons_single <- st_combine(all_polygons_single)
all_polygons_single <- st_cast(all_polygons_single, "POLYGON")

#plot the combined polygons
plot(st_geometry(all_polygons))
plot(st_geometry(all_polygons_single))

#load and process CSV files
lf <- list.files(mydir, pattern = 'habsos.*\\.csv', recursive = TRUE)
df <- read.csv(paste0(mydir,lf[length(lf)]))
#convert SAMPLE_DATE to Date format
df$SAMPLE_DATE <- as.Date(df$SAMPLE_DATE)

#extract year and month
df$year <- as.numeric(format(df$SAMPLE_DATE, "%Y"))
df$month <- as.numeric(format(df$SAMPLE_DATE, "%m"))

#select and rename columns
df <- df[, c("LATITUDE", "LONGITUDE", "year", "CELLCOUNT", "month")]
colnames(df) <- c("lat", "lon", "year", "cells", "month")

#convert data frame to sf object
obs_sf <- st_as_sf(df, coords = c("lon", "lat"), crs = st_crs(depth))

#use st_within to identify points inside polygons
inside_polygons <- st_within(obs_sf, all_polygons_single, sparse = FALSE)
plot(inside_polygons)

#filter points that are outside the polygons (i.e., where no intersection exists)
filtered_points_outside <- obs_sf[!apply(inside_polygons, 1, any), ]

#apply another filter based on the raster extent
raster_extent <- st_as_sfc(st_bbox(depth))
#precompute the bounding box of the raster extent
bbox_raster <- st_bbox(raster_extent)
#apply st_crop once with the precomputed bounding box
filtered_points_outside <- st_crop(filtered_points_outside, bbox_raster)
#extract coordinates and add them as columns
filtered_points_df <- cbind(filtered_points_outside, st_coordinates(filtered_points_outside))

#create a ggplot of the filtered points and polygons
p<-
  ggplot() +
  geom_sf(data = st_as_sf(us_clipped_sf_polygons), fill = 'lightgrey', color = 'black', alpha = 0.5) +
  geom_sf(data = subset(filtered_points_df,year >= 1985), aes(geometry = geometry), color = 'blue', size = 0.5,alpha=0.5) +
  labs(#title = "Filtered RT sampling stations",
    x = "longitude",
    y = "latitude") +
  theme_minimal()+
  scale_y_continuous(breaks=c(30,28,26))+
  scale_x_continuous(breaks=c(-86,-84,-82))+
  facet_wrap((~year),ncol=8)

#plot ts effort
sampling_effort<-as.data.frame(filtered_points_df)
#create a full sequence of monthly dates from Jan 1985 to the latest in the data
full_dates <- data.frame(
  date = seq(as.Date("1985-01-01"), 
             as.Date(paste(max(sampling_effort$year), 12, "01", sep = "-")), 
             by = "month")
)

#create a date column in your data
sampling_effort$date <- as.Date(paste(sampling_effort$year, sampling_effort$month, "01", sep = "-"))

ggplot(sampling_effort, aes(x = cells)) +
  geom_histogram(aes(y = after_stat(density)), fill = "skyblue", color = "white", bins = 30000) +
  labs(x = "Cells", y = "Proportion", title = "Proportional Distribution of Cells") +
  theme_minimal()

#count rows per month (using base R)
monthly_counts <- as.data.frame(table(sampling_effort$date))
colnames(monthly_counts) <- c("date", "n")
monthly_counts$date <- as.Date(monthly_counts$date)

# Merge with full date sequence to fill missing months with 0
plot_data <- merge(full_dates, monthly_counts, by = "date", all.x = TRUE)
plot_data$n[is.na(plot_data$n)] <- 0

#plot
ggplot(plot_data, aes(x = date, y = n)) +
  geom_line() +
  labs(x = "time", y = "n samples") +
  theme_minimal()


#rename
names(filtered_points_df)<-c('year','cells','month','lon','lat','geometry')

#save filtered observations
namefile <- sub("\\.csv$", "", basename(lf[length(lf)]))
save(filtered_points_df, file = paste0('./data/processed/filtered_', namefile, '.RData'))

#create grid from depth raster
# Convert to dataframe with latitude, longitude
input_grid <- as.data.frame(depth, xy = TRUE)  # Extract Lon & Lat
names(input_grid)[1:2] <- c("Lon", "Lat")  # Rename columns

#compute area per cell based on latitude
earth_radius_km <- 6371  # Earth radius in km

#function to compute cell area based on latitude
compute_area_km2 <- function(lat, res_x, res_y) {
  lat_rad <- lat * pi / 180  # Convert latitude to radians
  cell_width_km <- res_x * (pi / 180) * earth_radius_km * cos(lat_rad)  # Adjust longitude width
  cell_height_km <- res_y * (pi / 180) * earth_radius_km  # Latitude height
  return(cell_width_km * cell_height_km)
}

#apply function to each row to get area
input_grid$Area_km2 <- mapply(compute_area_km2, input_grid$Lat, res(depth)[1], res(depth)[2])

#exclude deep cells for later
input_grid1<-input_grid

#filtered_points_outside <- obs_sf[!apply(inside_polygons, 1, any), ]

#convert data frame to sf object
input_grid1 <- st_as_sf(input_grid1, coords = c("Lon", "Lat"), crs = st_crs(depth))

#use st_within to identify points inside polygons
inside_polygons <- st_within(input_grid1, all_polygons_single, sparse = FALSE)

x<-input_grid1[!apply(inside_polygons, 1, any), ]
x1<-as.data.frame(x,xy=TRUE)
total_area<-sum(na.omit(x1)[,'Area_km2'])
# Add an ID column to your data
#df$ID <- seq_len(nrow(df))  # Creates a sequential ID for each row

#create the plot
ggplot() +
  geom_point(color = "blue") +  # Scatter plot
  geom_sf(data = x1, aes(geometry = geometry), color = 'blue', size = 0.5,alpha=0.5) +
  #geom_text(aes(label = depth), vjust = -1, size = 3, color = "black") +  # Row number annotation
  labs(title = "Longitude-Latitude Plot with Row IDs",
       x = "Longitude",
       y = "Latitude") +
  theme_minimal()

#selected cells
sel_xy<-data.frame(st_coordinates(x))

#plot
ggplot() +
  geom_sf(data = st_as_sf(us_clipped_sf_polygons), fill = 'lightgrey', color = 'black', alpha = 0.5) +
  geom_point(data=sel_xy,aes(x=X,y=Y))+
  labs(title = "Filtered RT sampling stations",
       x = "Longitude",
       y = "Latitude") +
  theme_minimal()


#rename column
names(input_grid)[3] <- 'depth'

# Check result
head(input_grid)

#check grid
ggplot() +  
  geom_raster(data = as.data.frame(rasterToPoints(depth)), aes(x = x, y = y, fill = depth.4min.82x97)) +  # Depth raster
  scale_fill_viridis_c(name = "Depth") +  # Viridis color scale for depth
  geom_point(data = input_grid, aes(x = Lon, y = Lat), color = "black", size = 0.8,alpha=0.3) +  # Overlay points
  theme_minimal()

#check data
ggplot() +  
  geom_boxplot(data = filtered_points_df, aes(x = year, y = cells,group=year)) +  # Depth raster
  theme_minimal()

#create a dataframe from the minimum to the maximum order at monthly steps
yr<-rep(c(range(filtered_points_df$year)[1]:range(filtered_points_df$year)[2]),each=12)
month<-rep(1:12,times=length(c(range(filtered_points_df$year)[1]:range(filtered_points_df$year)[2])))
month<-sprintf("%02d", month)
df_time<-data.frame('year'=yr,
                    'month'=month,
                    'timestep'=1:length(yr))

#create folder to store fit objects
dir.create('./OM month/')
setwd('./OM month/')

# Loop fitting sdmTMB and VAST models #####
for (iyear in 1985:max(yr)) {
  
  #select year
  #iyear=2008
  
  ydf<-subset(filtered_points_df,year==iyear)
  
  # Filter rows where cells >= 1000
  filt_ydf <- ydf[ydf$cells > 0, ]
  
  # Count the number of rows (observations) for each month
  mm <- names(table(filt_ydf$month)[table(filt_ydf$month) > 5])
  
  for (imonth in 1:12) {
    
    #imonth<-10
    
    #print process
    cat(paste('################',iyear,'################\n',
              '################',imonth,'################\n'))
    
    
    #if month has data
    if (imonth %in% as.numeric(mm)) {
      
      #subset by month
      mdf<-subset(ydf,month==imonth)
      
      # Assuming mdf is your sf object
      mdf_df <- st_drop_geometry(mdf)
      mdf_df_pos<- subset(mdf_df,cells!=0)
      
      #create folder
      mdir<-paste0(iyear,sprintf("%02d", imonth))
      dir.create(mdir)
      
      #remove previous fit files
      file.remove(paste0(mdir,c("/fit_sdmTMB0.RData", "/fit_sdmTMB1.RData",'/fit_VAST.RData')))
      
      # Initialize attempt counter
      attempt_counter <- 0
      max_attempts <- 2  # Set maximum number of attempts
      
      ## sdmTMB ####
      
      repeat {
        # Run model
        #fit model without intercept
        fit_sdmTMBnb <- tryCatch({
          sdmTMB(
            formula = cells ~ 1,  # Formula for the model (adjust as needed)
            data = mdf_df,
            mesh = sdmTMB::make_mesh(mdf_df, xy_cols = c("lon", "lat"), cutoff = 0.1),
            family = nbinom2(),  # Specify distribution family
            spatial = "on",  # Enable spatial effects
            spatiotemporal = "off"  # No temporal effects since you have one time step # Increase iterations if necessary
          )}, error = function(e) {
            message("Error in fit TMB nb")
            return(NULL)  # Return NULL so we can check and restart the loop
          })
        
        #fit model without intercept
        fit_sdmTMBlog <- tryCatch({
          sdmTMB(
            formula = cells ~ 1,  # Formula for the model (adjust as needed)
            data = mdf_df_pos,
            mesh = sdmTMB::make_mesh(mdf_df_pos, xy_cols = c("lon", "lat"), cutoff = 0.1),
            family = lognormal(),  # Specify distribution family
            spatial = "on",  # Enable spatial effects
            spatiotemporal = "off"  # No temporal effects since you have one time step # Increase iterations if necessary
          )}, error = function(e) {
            message("Error in fit TMB log")
            return(NULL)  # Return NULL so we can check and restart the loop
          })
    
        # Check if fit_VAST is NULL (indicating an error) or if fit_VAST$Report has length 1
        if (!is.null(fit_sdmTMBnb) | !is.null(fit_sdmTMBlog) ) {
          break  # Exit loop if fit was successful
        } else {
          message("fit_sdmTMB error, restarting loop...")
          attempt_counter <- attempt_counter + 1  # Increment attempt counter
          
          # Check if max attempts reached
          if (attempt_counter >= max_attempts) {
            message("Maximum number of attempts reached. Passing to the next repeat...")
            break  # Exit loop after max attempts 
          }
        }
      }
      
      #save fit
      save(fit_sdmTMBnb, file = paste0(getwd(),'/',mdir,'/fit_sdmTMBnb.RData')) #paste(yrs_region,collapse = "")
      
      #save fit
      save(fit_sdmTMBlog, file = paste0(getwd(),'/',mdir,'/fit_sdmTMBlog.RData')) #paste(yrs_region,collapse = "")
      
      #remove objects
      rm(fit_sdmTMBnb,fit_sdmTMBlog)
      gc()
      

      #if month no data  
    } else {
      NULL
    }
  }
}

# Pre-allocate a matrix to store the results (Year, Month, Model, RMSE, MAE, R_squared)
fit_matrix <- matrix(NA, nrow = 0, ncol = 9)
colnames(fit_matrix) <- c("year", "month", "model", "RRMSE", "MAE", 'aic',"aicc",'nll','convergence')

#names of model fit files
mods<-c("fit_sdmTMBlog.RData","fit_sdmTMBnb.RData")
mods<-gsub('.RData','',mods)

# #array to store predictions
pred_array<-array(0,dim = c(nrow(input_grid),2+length(mods),12,length(1985:max(yr))),
                  dimnames = list(1:nrow(input_grid),c('lon','lat',mods),month.abb,1985:max(df$year)))

# #array to store predictions
pred_obs<- matrix(NA, nrow = 0, ncol = 5)
colnames(pred_obs) <- c("year", "month", 'obs','pred','mod')

# Loop getting predictions ####
for (iyear in 1985:max(yr)) {
  
  #select year
  #iyear=2005
  
  ydf<-subset(filtered_points_df,year==iyear)
  
  # Filter rows where cells >= 1000
  filt_ydf <- ydf[ydf$cells > 0, ]
  
  # Count the number of rows (observations) for each month
  mm <- names(table(filt_ydf$month)[table(filt_ydf$month) > 5])
  
  for (imonth in 1:12) {
    
    #imonth<-10
    
    #print process
    cat(paste('################',iyear,'################\n',
              '################',imonth,'################\n'))
    
    #check files - to see if VAST fit is there
    ifiles<-list.files(paste0(iyear,sprintf("%02d", imonth)),recursive = TRUE,full.names = TRUE,pattern = '.RData$')
    
    #if month has data
    if (imonth %in% as.numeric(mm)) {
      
      #filter for selection
      ifiles<-ifiles[grepl("fit_", ifiles) ]
      ifiles <- ifiles[sapply(ifiles, function(x) any(sapply(mods, grepl, x)))]
      
      #if month has data and has 3 fit files
      for (i in ifiles) {
        
        #i=ifiles[1]
        
        if (exists('fit')) {rm(fit)}
        if (exists('fit_VAST')) {rm(fit_VAST)}
        
        #subset by month
        mdf<-subset(ydf,month==imonth)
        
        #create folder
        mdir<-paste0(iyear,sprintf("%02d", imonth))
        
        #model name
        modname <- gsub("\\.RData$", "", basename(i))  # Remove .RData extension
        
        #load models
        load(file = i) 
        #fit<-get(modname)
        
        # Update predictions based on the availability of fit_sdmTMB0 and fit_sdmTMB1
        month <- month.abb[imonth]
        year <- as.character(iyear)
          
          #get fit objected
          fit<-get(modname)
          
          # Create prediction grid for each month
          prediction_data <- data.frame(
            lon = input_grid$Lon, 
            lat = input_grid$Lat, 
            month = imonth  # Add the month variable
          )
          
          # Function to update sdmTMB predictions
          update_sdmTMB_predictions <- function(fit, modname, pred_data, pred_array, fit_matrix, month, year) {
            if (!is.null(fit)) {
              predictions <- predict(fit, newdata = pred_data, type = 'response', t_i = pred_data$month, se_fit = FALSE)
              pred_array[, c('lon', 'lat', modname), month, year] <- cbind(pred_data$lon, pred_data$lat, predictions$est)
              
              # Compute evaluation metrics
              obs_sdmTMB <- fit$response
              pred_sdmTMB <- predict(fit, type = "response")[,'est']
              
              #df
              pred_obs<-
                rbind(pred_obs, 
                      data.frame("year"=iyear, 
                                 "month"=imonth,
                                 'obs'=obs_sdmTMB,
                                 'pred'=pred_sdmTMB,
                                 'mod'=modname))
              
              #calculate RRMSE and MAE
              rrmse <- (sqrt(mean((obs_sdmTMB - pred_sdmTMB)^2))) / mean(obs_sdmTMB)
              mae <- mean(abs(obs_sdmTMB - pred_sdmTMB))
              
              # Total number of parameters (fixed+random)
              k_value <- length(fit$tmb_obj$par) + length(fit$tmb_obj$env$random)
              # Number of observations
              n <- nrow(fit$response)
              # Calculate AICc
              aic<-AIC(fit)
              aicc <- AIC(fit) + (2 * k_value * (k_value + 1)) / (n - k_value - 1)
              
              #NLL
              nll<-fit$model$objective #NLL
              
              conv <- fit$model$convergence == 0
              
              fit_matrix <- rbind(fit_matrix, c(iyear, imonth, modname, rrmse, mae,aic, aicc,nll, conv))
              
              cat(modname, " model Evaluation:\n")
              cat(" RMSE: ", rrmse, "\n")
              cat(" MAE: ", mae, "\n")
              cat(" AIC: ", aic, "\n")
              cat(" AICc: ", aicc, "\n")
              cat(" NLL: ", nll, "\n")
            } else {
              fit_matrix <- rbind(fit_matrix, c(iyear, imonth, modname, NA, NA, NA,NA,NA, 'no model'))
              pred_array[, c('lon', 'lat', modname), month, year] <- cbind(pred_data$lon, pred_data$lat, rep(0, length(pred_data$lon)))
            }
            
            return(list(pred_array = pred_array, fit_matrix = fit_matrix,pred_obs=pred_obs))
          }
          
          #run fxn
          results <- update_sdmTMB_predictions(fit, modname, prediction_data, pred_array, fit_matrix, imonth, match(iyear, 1985:max(df$year)))
          pred_array <- results$pred_array
          fit_matrix <- results$fit_matrix
          pred_obs <- results$pred_obs  
      }
      } else {
        # Store Year, Month, Model, and metrics in the results matrix
        fit_matrix <- rbind(fit_matrix,
                            c(iyear, imonth, NA, NA, NA, NA,NA,NA, 'no model'))
        
        for (j in 1:length(mods)) {
          pred_array[, j, imonth, match(iyear, 1985:max(df$year))] <- rep(0, nrow(input_grid))
        }
        
    }
  }
}

#save array
setwd(mydir)
save(fit_matrix, file = './ST drivers/red tides/data/processed/RT_fit_matrix.RData') #paste(yrs_region,collapse = "")
save(pred_array, file = './ST drivers/red tides/data/processed/pred_SDMs_RT.RData') #paste(yrs_region,collapse = "")
save(pred_obs, file = './ST drivers/red tides/data/processed/pred_obs_RT.RData') #paste(yrs_region,collapse = "")
load(file = './ST drivers/red tides/data/processed/RT_fit_matrix.RData') #paste(yrs_region,collapse = "")

#check matrix
fit_matrix<-data.frame(fit_matrix)
table(fit_matrix$convergence)

# Change the value of x1 in the convergence column
fit_matrix$convergence <- ifelse(fit_matrix$convergence == "The model is likely not converged", "FALSE", fit_matrix$convergence)
fit_matrix$convergence <- ifelse(fit_matrix$convergence == "There is no evidence that the model is not converged", "TRUE", fit_matrix$convergence)
fit_matrix$convergence <- ifelse(fit_matrix$convergence == "no conv", "FALSE", fit_matrix$convergence)
Nno<-as.data.frame(table(fit_matrix$convergence))[2,'Freq']
tot<-sum(as.data.frame(table(fit_matrix$convergence))['Freq'])
fit_matrix<-fit_matrix[which(fit_matrix$convergence!='no model'),]

# Count the occurrences of TRUE and FALSE in the convergence column
counts <- as.data.frame(table(fit_matrix$convergence,fit_matrix$model))

# Calculate the percentage
counts$percentage <- (counts$Freq / sum(counts$Freq)) * 100

# Rename columns for clarity
colnames(counts) <- c("convergence",'model', "count", "percentage")

#count
counts$approach<-ifelse(grepl('VAST',counts$model),'VAST','sdmTMB')
counts$submodel<-gsub('fit_VAST','',counts$model)
counts$submodel<-gsub('fit_sdmTMB','',counts$submodel)
fit_matrix$approach<-ifelse(grepl('VAST',fit_matrix$model),'VAST','sdmTMB')
fit_matrix$submodel<-gsub('fit_VAST','',fit_matrix$model)
fit_matrix$submodel<-gsub('fit_sdmTMB','',fit_matrix$submodel)

#plot
ggplot(counts, aes(x = convergence, y = percentage, fill = convergence)) +
  geom_bar(stat = "identity") +
  scale_x_discrete(guide = guide_axis_nested(angle=0),labels = function(x) gsub("\\+", "\n", x))+
  labs(title = paste0("Convergence SDM RT"),
       x = "",
       y = "") +
  theme_minimal()

#plot
ggplot(counts, aes(x = interaction(approach, submodel), y = count, fill = convergence)) +
  geom_bar(stat = "identity") +
  geom_text(aes(label = ifelse(convergence == TRUE, count, "")), 
            vjust = -0.5) +
  scale_x_discrete(guide = guide_axis_nested(angle = 0)) +
  labs(title = "Convergence SDM RT",
       x = "",
       y = "") +
  theme_minimal()

#plot
ggplot()+
  geom_boxplot(data = na.omit(fit_matrix),aes(x=interaction(approach, submodel),y=as.numeric(RRMSE),fill=interaction(approach, submodel)),outlier.shape = NA)+
  #facet_wrap(~year)+
  theme_bw()+
  scale_x_discrete(guide = guide_axis_nested(angle = 0)) +
  labs(y='RRMSE',fill='SDM',x='')+
  ggthemes::scale_fill_tableau()+
  scale_y_continuous(limits = c(0,15))

#plot
ggplot()+
  geom_boxplot(data = fit_matrix,
               aes(x=interaction(approach, submodel),y=as.numeric(nll),fill=interaction(approach, submodel)),
               outlier.shape = NA)+
  #facet_wrap(~year)+
  theme_bw()+
  scale_x_discrete(guide = guide_axis_nested(angle = 0)) +
  labs(y='NLL',fill='SDM',x='')+
  ggthemes::scale_fill_tableau()+
  scale_y_continuous(limits = c(0,6000))

#plot
ggplot()+
  geom_boxplot(data = fit_matrix,
               aes(x=interaction(approach, submodel),y=as.numeric(MAE),fill=interaction(approach, submodel)),
               outlier.shape = NA)+
  #facet_wrap(~year)+
  theme_bw()+
  scale_x_discrete(guide = guide_axis_nested(angle = 0)) +
  labs(y='MAE',fill='SDM',x='')+
  ggthemes::scale_fill_tableau()+
  scale_y_continuous(limits = c(0,200000))

#plot
ggplot()+
  geom_boxplot(data = fit_matrix,
               aes(x=interaction(approach, submodel),y=as.numeric(aic),fill=interaction(approach, submodel)),
               outlier.shape = NA)+
  #facet_wrap(~year)+
  theme_bw()+
  scale_x_discrete(guide = guide_axis_nested(angle = 0)) +
  labs(y='AIC',fill='SDM',x='')+
  ggthemes::scale_fill_tableau()+
  scale_y_continuous(limits = c(0,10000))

# #variances
# sigma_G	IID random intercept variance
# sigma_E	Spatiotemporal random field marginal variance
# sigma_O	Spatial random field marginal variance
# sigma_Z	Spatially varying coefficient random field marginal variance

#create rasters (ascii file) to input Ecospace

#setwd
setwd(paste0(mydir,'/ST drivers/red tides/'))
dir.create('./sdmTMB RT rasters/')
#dir.create('./VAST RT rasters/')

#loop over years and months
for (iyear in dimnames(pred_array)[[4]]) {
  for (imonth in dimnames(pred_array)[[3]]) {
    
    #print
    cat(paste('################',iyear,'################\n',
              '################',imonth,'################\n'))
    
    #iyear<-2018
    #imonth<-'Sep'
    
    #extract prediction
    ypred <- pred_array[,,imonth,as.character(iyear)]
    ypred1 <- as.data.frame(ypred)
    
    #create raster template based on depth raster
    r_template <- raster(extent(depth), resolution = res(depth), crs = crs(depth))
    
    #remove NAs and check spatial coverage
    ypred1 <- ypred1[complete.cases(ypred1[, c("lon", "lat", "fit_sdmTMBlog", "fit_sdmTMBnb")]), ]
    
    if (nrow(ypred1) < 2 || length(unique(ypred1$lon)) < 2 || length(unique(ypred1$lat)) < 2) {
      cat("Insufficient spatial data: writing empty rasters\n")
      r.sdmTMB1 <- setValues(r_template, NA)
      r.sdmTMB2 <- setValues(r_template, NA)
    } else {
      #convert to spatial points
      coordinates(ypred1) <- ~ lon + lat
      gridded(ypred1) <- TRUE
      
      #rasterize
      r.sdmTMB1 <- rasterize(ypred1, r_template, field = 'fit_sdmTMBlog', fun = mean)
      r.sdmTMB2 <- rasterize(ypred1, r_template, field = 'fit_sdmTMBnb', fun = mean)
    }
    
    #save rasters
    writeRaster(r.sdmTMB1, paste0('./sdmTMB RT rasters/',iyear,sprintf("%02d", match(imonth, month.abb)),'_predsdmTMBlog.asc'), format="ascii", overwrite=TRUE)
    writeRaster(r.sdmTMB2, paste0('./sdmTMB RT rasters/',iyear,sprintf("%02d", match(imonth, month.abb)),'_predsdmTMBnb.asc'), format="ascii", overwrite=TRUE)
  }
}

#check
#plot(raster('./sdmTMB RT rasters/200909_predsdmTMBlog.asc'))

#VIIRS, severity RT rasters and plot ####
#create folder
setwd(paste0(mydir,'/ST drivers/red tides/'))
dir.create('./RT severity rasters/')

#set wd and load files
setwd(mydir)
lf<-list.files('./ST drivers/red tides/data/raw/VIIRS_redtide_maps_0.1degree/redtide_maps_0.1degree/',pattern = 'tif',full.names = TRUE)
#load(file = './ST drivers/red tides/data/processed/pred_obs_RT.RData') #pred_obs
load(file = paste0('./ST drivers/red tides/data/processed/filtered_', namefile, '.RData')) #filtered_points_df

#ensure month column is two digits
filtered_points_df$month <- sprintf("%02d", filtered_points_df$month)

#array to store predictions
viirs_obs<- matrix(NA, nrow = 0, ncol = 4)
colnames(viirs_obs) <- c("year", "month", 'viirs','obs')

#list
plot_list<-list()

#loop
for (f in lf) {
  
  #f<-lf[81]
  
  #get raster
  r<-raster(f)
  
  #year and month
  y<-substr(names(r),2,5)
  m<-substr(names(r),7,8)
  
  #print
  cat(paste0('################## ',y,m,'###\n'))
  
  # Set the extent manually
  extent(r) <- c(-87.5, -81, 25, 30.5)
  
  # Set the CRS manually
  crs(r) <- "+proj=longlat +datum=WGS84 +no_defs"
  
  # Flip the raster vertically
  r1 <- flip(r, direction = "y")
  #plot(r1)
  
  ivalues<-c(values(r1))
  if (mean(ivalues,na.rm=TRUE)==0) {
    cat("### JUMPING -------")
    next
  }
  
  #convert all 0 values to NA
  r2<-r1
  r2[r2 == 0] <- NA
  
  #convert raster cells with values to polygons
  r2pol <- rasterToPolygons(r2, fun = function(x) !is.na(x) & x != 0, dissolve = TRUE)
  #convert to sf object
  r2pol <- st_as_sf(r2pol)
  #merge all polygons into a single polygon
  r2pol <- st_union(r2pol)
  
  #plot
  #plot(r2)
  #plot(r2pol,add=T)
  
  #ensure r2pol is an sf object
  r2pol <- st_sf(geometry = r2pol)
  
  #assign the CRS from r2 (assuming r2 has a CRS)
  st_crs(r2pol) <- st_crs(r2)
  
  #filter by month and year obs samples
  ydf<-subset(filtered_points_df,year==y & month ==m)
  
  if (nrow(ydf)==0) {
    next
  }
  #filter rows where cells >= 1000
  #filt_ydf <- ydf[ydf$cells >= 1000, ]
  
  #coordinates
  icoords <- data.frame(lon=ydf$lon, lat=ydf$lat,cells=ydf$cells)
  
  #convert raster to data frame for ggplot
  raster_df <- as.data.frame(rasterToPoints(r2))
  colnames(raster_df)[ncol(raster_df)]<-'freq'
  
  #reorder points based on cells values to plot higher values on top
  icoords <- icoords[order(icoords$cells), ]
  
  #add raster data
  ifile<-list.files(path = mydir,pattern = paste0(y,m,'_predsdmTMBlog.asc'),recursive = TRUE)
  r.sdmTMB1<-raster(ifile)
  
  # Convert raster to data frame for ggplot
  raster_cells1 <- as.data.frame(rasterToPoints(r.sdmTMB1))
  colnames(raster_cells1)[ncol(raster_cells1)]<-'cells'
  
  #add raster data
  ifile<-list.files(path = mydir,pattern = paste0(y,m,'_predsdmTMBnb.asc'),recursive = TRUE)
  r.sdmTMB2<-raster(ifile)
  
  #convert raster to data frame for ggplot
  raster_cells2 <- as.data.frame(rasterToPoints(r.sdmTMB2))
  colnames(raster_cells2)[ncol(raster_cells2)]<-'cells'
  
  #create a color palette with white at the start
  my_magma <- viridis::magma(100, direction = -1)
  my_colors <- c("white", my_magma)
  #prepare point type for shape mapping
  icoords$point_type <- ifelse(icoords$cells == 0, "Zero cell count (X)", "Sampled (O)")
  
  #define color breaks
  n_breaks <- 5
  max_fill <- max(raster_cells2$cells, na.rm = TRUE)
  max_color <- max(icoords$cells, na.rm = TRUE)
  common_breaks <- pretty(c(0, max(max_fill, max_color)), n = n_breaks)
  
  #convert RasterLayer to SpatRaster
  r.sdmTMB1_terra <- rast(r.sdmTMB1)
  r.sdmTMB2_terra <- rast(r.sdmTMB2)
  
  #reproject polygon to match the raster CRS if needed
  r2pol <- st_transform(r2pol, crs(r.sdmTMB1_terra))
  
  #convert the polygon to a SpatVector object
  r2pol_vect <- vect(r2pol)
  
  #apply mask using terra package
  r.sdmTMB1_clipped <- mask(r.sdmTMB1_terra, r2pol_vect)
  r.sdmTMB2_clipped <- mask(r.sdmTMB2_terra, r2pol_vect)
    
  #set values outside the polygon to zero
  r.sdmTMB1_clipped[is.na(r.sdmTMB1_clipped)] <- 0
  r.sdmTMB2_clipped[is.na(r.sdmTMB2_clipped)] <- 0
  
  # Save as .asc file
  writeRaster(r.sdmTMB1_clipped, 
              filename = paste0("./ST drivers/red tides/RT severity rasters/", y, m, "_RTsevlog.asc"), 
              filetype = "AAIGrid", 
              overwrite = TRUE)
  
  # Save as .asc file
  writeRaster(r.sdmTMB2_clipped, 
              filename = paste0("./ST drivers/red tides/RT severity rasters/", y, m, "_RTsevnb.asc"), 
              filetype = "AAIGrid", 
              overwrite = TRUE)
  
  #convert raster to data frame for ggplot
  sev_cells1 <- as.data.frame(r.sdmTMB1_clipped, xy = TRUE)
  colnames(sev_cells1)[ncol(sev_cells1)]<-'cells'
  #convert raster to data frame for ggplot
  sev_cells2 <- as.data.frame(r.sdmTMB2_clipped, xy = TRUE)
  colnames(sev_cells2)[ncol(sev_cells2)]<-'cells'
  #convert raster to data frame for ggplot
  pred_cells1 <- as.data.frame(r.sdmTMB1_terra, xy = TRUE)
  colnames(pred_cells1)[ncol(pred_cells1)]<-'cells'
  #convert raster to data frame for ggplot
  pred_cells2 <- as.data.frame(r.sdmTMB2_terra, xy = TRUE)
  colnames(pred_cells2)[ncol(pred_cells2)]<-'cells'
  
  #plot
  p<-
  ggplot() +
    # Raster layer
    #geom_raster(data = pred_cells2, aes(x = x, y = y, fill = cells)) +
    geom_raster(data = sev_cells2, aes(x = x, y = y, fill = cells)) +
    # Polygon border
    #geom_raster(data = raster_df, aes(x = x, y = y, fill = freq)) +
    #geom_sf(data = r2pol, fill = 'transparent', color = 'darkblue', linewidth = 0.7) +  # r2pol filled with color
    
    #scale_fill_gradient(low = "white", high = "#AEC936") +      
    # Main colored points
    #geom_point(data = icoords, aes(x = lon, y = lat, color = cells),
    #         shape = 19, size = 2, stroke = 0.5) +
    
    # Circle outlines and Xs using shape map
    #geom_point(data = icoords, aes(x = lon, y = lat, shape = point_type),
    #       size = 3, stroke = 0.5, color = 'black', fill = NA) +
    
    # US base polygon
    geom_sf(data = st_as_sf(us_clipped_sf_polygons), fill = 'grey80', color = 'black') +
    # Shared color scales
    scale_fill_gradientn(
      colors = my_colors,
      values = scales::rescale(common_breaks),  # Use scales::rescale
      #breaks = common_breaks,
      labels = scales::scientific_format(),
      name = "cells/L (pred)"
    ) +
    scale_color_gradientn(
      colors = my_colors,
      values = scales::rescale(common_breaks),  # Use scales::rescale
      #breaks = common_breaks,
      labels = scales::scientific_format(),
      name = "cells/L (obs)"
    ) +
    
    # Manual shape legend
    scale_shape_manual(
      values = c("Zero cell count (X)" = 13, "Sampled (O)" = 1), 
      labels = c('sample', '0 cells/L'),
      name = "obs"
    ) +
    
    # Titles and themes
    theme_minimal() +
    labs(x = '', y = '') +
    annotate("text", x = -82, y = 30,
             label = paste0(m, ' - ', y), hjust = 1,
             size = 5, fontface = "bold") +
    
    # Theme and legend layout
    theme(
      legend.box = "horizontal",  # Change to vertical
      legend.position = c(0.25, 0.25),  # Adjust legend position as needed
      legend.box.just = "bottom",  # Center the legend box
      legend.text = element_text(size = 10)) +
    guides(
      fill = guide_colorbar(order = 1,
                            frame.colour = "black",  # bar frame color
                            frame.linetype = "solid", frame.linewidth=1, # bar frame linetype
                            ticks = T,  # show the ticks on the bar
                            ticks.colour = "white"),  # tick color
      color = guide_colorbar(order = 2,
                             frame.colour = "black",  # bar frame color
                             frame.linetype = "solid",  # bar frame linetype
                             ticks = T,  # show the ticks on the bar
                             ticks.colour = "white"),  # tick color
      shape = guide_legend(order = 3, override.aes = list(size = 3))
    )
  
  plot_list[[paste0(m,y)]]<-p
  
  
  
  
  #spatial coords
  coordinates(icoords) <- ~lon+lat
  
  #extract values from raster
  values <- raster::extract(r1, icoords)
  
  #append results
  viirs_obs<-rbind(viirs_obs,
                   data.frame(year=y,
                              month=m,
                              viirs=values,
                              obs=ydf$cells))
  
}


#check example to see 2018 severity maps
#y<-'2018'
#ilist<-plot_list[grepl(paste0(y), names(plot_list))]
#do.call(gridExtra::grid.arrange, c(ilist, ncol = 3))  # Adjust ncol as needed

# Plot predictions ####
#color scale from previous analysis
# Set up the color scale and breaks as you already have
colv.kb <- c("white", "purple", "blue", "darkblue", "cyan", "green", "darkgreen", "yellow", "orange", "red", "darkred")
funpal.kb <- colorRampPalette(colv.kb, bias = 2)

brks.idw <- c(0, 1e4 - 1, seq(1e4, 4e6, 10000), 1e8)
nbcols.idw <- length(brks.idw) -1
color.idw <- funpal.kb(nbcols.idw)

# Set up the PDF device
dir.create(paste0(mydir,"/ST drivers/red tides/outputs/"))
pdf(paste0(mydir,"/ST drivers/red tides/outputs/RT OM prediction maps_scale.pdf"), width = 11, height = 6)  # Landscape: Width > Height

#loop
for (iyear in 2012:max(yr)) {
  
  #iyear=2013

  cat(paste0("############# ",iyear,' \n' ))
  # List months you want (example: January to December)
  months <- sprintf("%02d", 1:12)  # "01", "02", ..., "12"
  
  # Build expected filenames
  files1 <-  paste0("./ST drivers/red tides/RT severity rasters/", iyear, months, "_RTsevlog.asc")
  files2 <-  paste0("./ST drivers/red tides/RT severity rasters/", iyear, months, "_RTsevnb.asc")
  
  names(files1) <- months  # Name them by month
  names(files2) <- months  # Name them by month
  
  # Load rasters into a list (some might not exist)
  raster_list1 <- lapply(files1, function(f) {
    if (file.exists(f)) {
      rast(f)
    } else {
      NULL  # If not found, keep NULL
    }
  })
  
  # Load rasters into a list (some might not exist)
  raster_list2 <- lapply(files2, function(f) {
    if (file.exists(f)) {
      rast(f)
    } else {
      NULL  # If not found, keep NULL
    }
  })
  
  # Function to convert raster to dataframe for ggplot
  raster_to_df <- function(r, month) {
    if (is.null(r)) {
      return(data.frame(x = NA, y = NA, value = NA, month = month))
    } else {
      df <- as.data.frame(r, xy = TRUE, na.rm = FALSE)
      names(df) <- c("x", "y", "value")
      df$month <- month
      return(df)
    }
  }
  
  # Apply to all rasters
  df_list1 <- Map(raster_to_df, raster_list1, names(raster_list1))
  df_list2 <- Map(raster_to_df, raster_list2, names(raster_list2))
  
  # Combine all into one big dataframe
  all_df1 <- dplyr::bind_rows(df_list1)
  all_df2 <- dplyr::bind_rows(df_list2)

  #generate plot
  plot_sdmTMB1 <- 
    ggplot() +
    geom_raster(data=all_df1, aes(x = x, y = y, fill = value),na.rm = TRUE) +
    #geom_tile(data = sf_df, aes(x = X, y = Y, fill = sdmTMBlog), height = res(depth)[2], width = res(depth)[1]) +  # Use clipped predictions
    #geom_raster(data = sf_df, aes(x = X, y = Y, fill = log(cells_sdmTMB1))) +  # Use clipped predictions
    coord_sf(crs = crs(depth),
             xlim = c(-87.99999, -80.49999), ylim = c(24.51496, 30.5)) +
    geom_sf(data = us_clipped_sf,
            fill = 'grey60', size = 1) +
    theme() +
    labs(x='',y='',title='sdmTMB LOG')+
    theme_minimal() +
    scale_fill_gradientn(colors = color.idw, na.value = "white",limits = c(0, 10000000),
                         oob = scales::squish) +
    #scale_fill_gradientn(colors = color.idw, breaks = brks.idw, labels = c("0", "10K", "100K", "1M", "4M", "10M"), na.value = "white") +
    # scale_fill_gradient(low = "white", high = "red", na.value = 'transparent',
    #                     limits = c(0, 10000000),  # Ensure max cap
    #                     oob = scales::squish  ) +# Ensures values > 1,000,000 stay at max color
    scale_x_continuous(breaks = c(-86, -82), expand = c(0, 0)) +
    scale_y_continuous(breaks = c(30, 28, 26), expand = c(0, 0)) +
    labs(fill = "cells/L") +
    theme(panel.grid.major = element_line(color = rgb(235, 235, 235, 100, maxColorValue = 255),
                                          linetype = 'dashed', linewidth  = 0.5),
          legend.position = "right",legend.title = element_text(angle=90,hjust=0.5),
          panel.background = element_rect(fill = NA), panel.ontop = TRUE, text = element_text(size = 10),
          plot.margin = unit(c(0.1, 0.1, 0.1, 0.1), "lines"),
          legend.background = element_rect(fill = "transparent", colour = "transparent"),
          plot.title = element_text(hjust = 0.50, vjust = -1),
          legend.key = element_rect(color = "black"),
          legend.key.size = unit(1, "lines")) +  # Adjusting the legend key contour to black
    guides(fill = guide_colorbar(size = 0.5, barwidth = 0.5, barheight = unit(1, "npc"),  # Full height of the plot
                                 frame.colour = "black", ticks = element_line(color = 'black'),
                                 ticks.colour = "black",
                                 ticks.linewidth = 0.2,
                                 title.position = "right",  # Moves the legend title to the right of the color bar
                                 label.position = "right",  # Ensures the labels are also aligned with the color bar
                                 frame.linewidth = 0.2)) +  # Change ticks to black
    facet_wrap(~month, ncol = 3)  # Use first three letters of the month
  
  plot_sdmTMB2 <- 
    ggplot() +
    geom_raster(data=all_df2, aes(x = x, y = y, fill = value),na.rm = TRUE) +
    #geom_tile(data = sf_df, aes(x = X, y = Y, fill = sdmTMBlog), height = res(depth)[2], width = res(depth)[1]) +  # Use clipped predictions
    #geom_raster(data = sf_df, aes(x = X, y = Y, fill = log(cells_sdmTMB1))) +  # Use clipped predictions
    coord_sf(crs = crs(depth),
             xlim = c(-87.99999, -80.49999), ylim = c(24.51496, 30.5)) +
    geom_sf(data = us_clipped_sf,
            fill = 'grey60', size = 1) +
    theme() +
    labs(x='',y='',title='sdmTMB NB')+
    theme_minimal() +
    scale_fill_gradientn(colors = color.idw, na.value = "white",limits = c(0, 10000000),
                         oob = scales::squish) +
    #scale_fill_gradientn(colors = color.idw, breaks = brks.idw, labels = c("0", "10K", "100K", "1M", "4M", "10M"), na.value = "white") +
    # scale_fill_gradient(low = "white", high = "red", na.value = 'transparent',
    #                     limits = c(0, 10000000),  # Ensure max cap
    #                     oob = scales::squish  ) +# Ensures values > 1,000,000 stay at max color
    scale_x_continuous(breaks = c(-86, -82), expand = c(0, 0)) +
    scale_y_continuous(breaks = c(30, 28, 26), expand = c(0, 0)) +
    labs(fill = "cells/L") +
    theme(panel.grid.major = element_line(color = rgb(235, 235, 235, 100, maxColorValue = 255),
                                          linetype = 'dashed', linewidth  = 0.5),
          legend.position = "right",legend.title = element_text(angle=90,hjust=0.5),
          panel.background = element_rect(fill = NA), panel.ontop = TRUE, text = element_text(size = 10),
          plot.margin = unit(c(0.1, 0.1, 0.1, 0.1), "lines"),
          legend.background = element_rect(fill = "transparent", colour = "transparent"),
          plot.title = element_text(hjust = 0.50, vjust = -1),
          legend.key = element_rect(color = "black"),
          legend.key.size = unit(1, "lines")) +  # Adjusting the legend key contour to black
    guides(fill = guide_colorbar(size = 0.5, barwidth = 0.5, barheight = unit(1, "npc"),  # Full height of the plot
                                 frame.colour = "black", ticks = element_line(color = 'black'),
                                 ticks.colour = "black",
                                 ticks.linewidth = 0.2,
                                 title.position = "right",  # Moves the legend title to the right of the color bar
                                 label.position = "right",  # Ensures the labels are also aligned with the color bar
                                 frame.linewidth = 0.2)) +  # Change ticks to black
    facet_wrap(~month, ncol = 3)  # Use first three letters of the month
  
  # Create the combined plot
  final_plot <- plot_grid(
    ggdraw() + 
      draw_label(iyear, 
                 fontface = "bold", size = 16, hjust = 0.5), # Title
    plot_grid(plot_sdmTMB1,plot_sdmTMB2,nrow = 1),           # Combined plots
    ncol = 1,                                              # Arrange title and plots vertically
    rel_heights = c(0.1, 1)                                # Adjust title-to-plot height ratio
  )
  
  # Print the final combined plot
  print(final_plot)
}

#close pdf
dev.off()
