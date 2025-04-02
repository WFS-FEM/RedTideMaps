# Settings #####
#remove and empty objects
rm(list=ls());gc()

#load libraries
library(sdmTMB)
library(VAST)
library(lubridate)
library(ggplot2)
library(raster)
library(sf)
library(rnaturalearth)
library(cowplot)

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

# Prepare red tides dataset #####
# Load depth and exclusion depth rasters to be used as a sample raster
depth <- raster('./static drivers/depth/depth 4min 82x97.asc')
excl_depth <- raster('./static drivers/depth/excl layer 4min 82x97.asc')

# Get US polygon as an sf object
us <- ne_countries(country = "united states of america", scale = 10, returnclass = "sf")

# Plot original US polygon
plot(us$geometry)

# Remove all non-geometry columns
us <- us["geometry"]

# Convert raster extent to an sf-compatible bounding box
us_bbox <- st_as_sfc(st_bbox(depth))

# Crop to U.S. region using sf functions
us_cropped <- st_crop(us, us_bbox)
us_cropped <- st_cast(us_cropped, "POLYGON")
# Plot cropped version
plot(us_cropped$geometry)

#create data folder
dir.create('./ST drivers/red tides/',showWarnings = FALSE)
dir.create('./ST drivers/red tides/data/processed',showWarnings = FALSE)
setwd('./ST drivers/red tides/')

# Convert extent(depth) to an sf polygon
depth_extent <- st_as_sf(st_as_sfc(st_bbox(depth)))

# Convert exclusion depth raster to polygons and then to sf object
excl_depth <- rasterToPolygons(excl_depth, dissolve = TRUE)
excl_depth_sf <- st_as_sf(excl_depth)

# Perform intersection
us_clipped_sf <- st_intersection(us_cropped, depth_extent)

# Define coordinates of polygon, ensuring the first point is repeated as the last
coords <- matrix(c(-82, 28.5, 
                   -80.5, 28.5, 
                   -80.5, 31, 
                   -82, 31, 
                   -82, 28.5),  # Explicitly repeat the first point to close the polygon
                 ncol = 2, byrow = TRUE)

# Create the polygon (now properly closed)
Ps2_sf <- st_sf(geometry = st_sfc(st_polygon(list(coords))), crs = st_crs(depth))

# Ensure all geometries are in the same CRS
us_clipped_sf <- st_transform(us_clipped_sf, st_crs(depth))
excl_depth_sf <- st_transform(excl_depth_sf, st_crs(depth))
Ps2_sf <- st_transform(Ps2_sf, st_crs(depth))

#arrange polygons
us_clipped_sf <- st_make_valid(us_clipped_sf)
us_clipped_sf_polygons <- st_cast(us_clipped_sf, "POLYGON")

# Combine polygons sequentially using st_union
combined_polygons_1 <- st_union(us_clipped_sf, Ps2_sf)
all_polygons <- st_union(combined_polygons_1, excl_depth_sf)

#union of all polygons where we don't want sampling points (land, atlantic or excl cells)
all_polygons_single <- st_union(us_clipped_sf, Ps2_sf)
all_polygons_single <- st_union(all_polygons_single, excl_depth_sf)
all_polygons_single <- st_combine(all_polygons_single)
all_polygons_single <- st_cast(all_polygons_single, "POLYGON")

# Plot the combined polygons
plot(st_geometry(all_polygons))
plot(st_geometry(all_polygons_single))

# Load and process CSV files
lf <- list.files(mydir, pattern = 'habsos.*\\.csv', recursive = TRUE)
df <- read.csv(paste0(mydir,lf[length(lf)]))
# Convert SAMPLE_DATE to Date format
df$SAMPLE_DATE <- as.Date(df$SAMPLE_DATE)

# Extract year and month
df$year <- as.numeric(format(df$SAMPLE_DATE, "%Y"))
df$month <- as.numeric(format(df$SAMPLE_DATE, "%m"))

# Select and rename columns
df <- df[, c("LATITUDE", "LONGITUDE", "year", "CELLCOUNT", "month")]
colnames(df) <- c("lat", "lon", "year", "cells", "month")

# Convert data frame to sf object
obs_sf <- st_as_sf(df, coords = c("lon", "lat"), crs = st_crs(depth))

# Use st_within to identify points inside polygons
inside_polygons <- st_within(obs_sf, all_polygons_single, sparse = FALSE)
plot(inside_polygons)

# Filter points that are outside the polygons (i.e., where no intersection exists)
filtered_points_outside <- obs_sf[!apply(inside_polygons, 1, any), ]

# Apply another filter based on the raster extent
raster_extent <- st_as_sfc(st_bbox(depth))
# Precompute the bounding box of the raster extent
bbox_raster <- st_bbox(raster_extent)
# Apply st_crop once with the precomputed bounding box
filtered_points_outside <- st_crop(filtered_points_outside, bbox_raster)
# Extract coordinates and add them as columns
filtered_points_df <- cbind(filtered_points_outside, st_coordinates(filtered_points_outside))

# Create a ggplot of the filtered points and polygons
ggplot() +
  geom_sf(data = st_as_sf(us_clipped_sf_polygons), fill = 'lightgrey', color = 'black', alpha = 0.5) +
  geom_sf(data = filtered_points_df, aes(geometry = geometry), color = 'blue', size = 0.5,alpha=0.5) +
  labs(title = "Filtered RT sampling stations",
       x = "Longitude",
       y = "Latitude") +
  theme_minimal()+
  facet_wrap((~year))

#rename
names(filtered_points_df)<-c('year','cells','month','lon','lat','geometry')

# Save filtered observations
namefile <- sub("\\.csv$", "", basename(lf[length(lf)]))
save(filtered_points_df, file = paste0('./data/processed/filtered_', namefile, '.RData'))

#create grid from depth raster
# Convert to dataframe with latitude, longitude
input_grid <- as.data.frame(depth, xy = TRUE)  # Extract Lon & Lat
names(input_grid)[1:2] <- c("Lon", "Lat")  # Rename columns

# Compute area per cell based on latitude
earth_radius_km <- 6371  # Earth radius in km

# Function to compute cell area based on latitude
compute_area_km2 <- function(lat, res_x, res_y) {
  lat_rad <- lat * pi / 180  # Convert latitude to radians
  cell_width_km <- res_x * (pi / 180) * earth_radius_km * cos(lat_rad)  # Adjust longitude width
  cell_height_km <- res_y * (pi / 180) * earth_radius_km  # Latitude height
  return(cell_width_km * cell_height_km)
}

# Apply function to each row to get area
input_grid$Area_km2 <- mapply(compute_area_km2, input_grid$Lat, res(depth)[1], res(depth)[2])

#exclude deep cells for later
input_grid1<-input_grid

#filtered_points_outside <- obs_sf[!apply(inside_polygons, 1, any), ]

# Convert data frame to sf object
input_grid1 <- st_as_sf(input_grid1, coords = c("Lon", "Lat"), crs = st_crs(depth))

# Use st_within to identify points inside polygons
inside_polygons <- st_within(input_grid1, all_polygons_single, sparse = FALSE)

x<-input_grid1[!apply(inside_polygons, 1, any), ]
x1<-as.data.frame(x,xy=TRUE)
# Add an ID column to your data
#df$ID <- seq_len(nrow(df))  # Creates a sequential ID for each row

# Create the plot
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
  filt_ydf <- ydf[ydf$cells >= 1000, ]
  
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
      
        # Run model
      #fit model with intercept
      fit_sdmTMBtw <- tryCatch({
        sdmTMB(
        formula = cells ~ 1,  # Formula for the model (adjust as needed)
        data = mdf_df,
        mesh = sdmTMB::make_mesh(mdf_df, xy_cols = c("lon", "lat"), cutoff = 0.1),
        family = tweedie(link = "log"),  # Specify distribution family
        spatial = "on",  # Enable spatial effects
        spatiotemporal = "off"  # No temporal effects since you have one time step # Increase iterations if necessary
      )}, error = function(e) {
        message("Error in fit TMB tw")
        return(NULL)  # Return NULL so we can check and restart the loop
      })
      
      
      # Check if fit_VAST is NULL (indicating an error) or if fit_VAST$Report has length 1
      if (!is.null(fit_sdmTMBnb) | !is.null(fit_sdmTMBlog) | !is.null(fit_sdmTMBtw)) {
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
      
      #save fit
      save(fit_sdmTMBtw, file = paste0(getwd(),'/',mdir,'/fit_sdmTMBtw.RData')) #paste(yrs_region,collapse = "")
      
      #remove objects
      rm(fit_sdmTMBnb,fit_sdmTMBlog,fit_sdmTMBtw)
      gc()
      
      #model settings
      settings = make_settings( Region='User',
                                purpose="index2",
                                n_x=nrow(input_grid), #500 
                                knot_method='grid',
                                #n_categories=data$n_c,#iter.max=500,
                                ObsModel=c(2,0), #c(4,0)
                                RhoConfig=c("Beta1"=1,"Beta2"=1,"Epsilon1"=0,"Epsilon2"=0),
                                FieldConfig = c("Omega1"='IID', "Epsilon1"=0, "Omega2"='IID', "Epsilon2"=0),                                
                                use_anisotropy = FALSE,
                                bias.correct = FALSE,
                                Options = c("Calculate_Range" =  F, 
                                            "Calculate_effective_area" = F))
      
      # Initialize attempt counter
      attempt_counter <- 0
      
      ## VAST ####
      
      repeat {
        # Increment Newton steps with each attempt
        newtonsteps <- 1 + attempt_counter
        
        fit_VAST = tryCatch({
          fit_model(
            settings = settings,
            Lat_i = mdf$lat,
            Lon_i = mdf$lon,
            t_i = mdf$month,
            c_i = rep(0, nrow(mdf)),
            b_i = mdf$cells,
            a_i = rep(1, nrow(mdf)),
            newtonsteps = newtonsteps,
            test_fit = FALSE,
            fine_scale = FALSE,
            input_grid = input_grid,
            working_dir = paste0(getwd(),'/',mdir)
          )
        }, error = function(e) {
          message("Error in fit_model(): ", e$message)  # Print the error message
          return(NULL)
        })
        
        # Check if fit_VAST is NULL (indicating an error) or if fit_VAST$Report has length 1
        if (!is.null(fit_VAST) && length(fit_VAST$Report) > 1) {
          break  # Exit loop if fit was successful
        } else {
          message("fit_VAST$Report has length 1, restarting loop...")
          attempt_counter <- attempt_counter + 1  # Increment attempt counter
          
          # Check if max attempts reached
          if (attempt_counter >= max_attempts) {
            message("Maximum number of attempts reached. Passing to the next repeat...")
            break  # Exit loop after max attempts 
          }
        }
      }
      
      #save fit
      save(list = "fit_VAST", file = paste0(getwd(),'/',mdir,'/fit_VASTdeltalog.RData'))
      
      #remove objects
      rm(fit_VAST)
      
      # Initialize attempt counter
      attempt_counter <- 0
      
      ## VAST ####
      
      repeat {
        # Increment Newton steps with each attempt
        newtonsteps <- 1 + attempt_counter
        
        #deltagamma
        settings$bias.correct<-TRUE
        
        fit_VAST = tryCatch({
          fit_model(
            settings = settings,
            Lat_i = mdf$lat,
            Lon_i = mdf$lon,
            t_i = mdf$month,
            c_i = rep(0, nrow(mdf)),
            b_i = mdf$cells,
            a_i = rep(1, nrow(mdf)),
            newtonsteps = newtonsteps,
            test_fit = FALSE,
            fine_scale = FALSE,
            input_grid = input_grid,
            working_dir = paste0(getwd(),'/',mdir)
          )
        }, error = function(e) {
          message("Error in fit_model(): ", e$message)  # Print the error message
          return(NULL)
        })
        
        # Check if fit_VAST is NULL (indicating an error) or if fit_VAST$Report has length 1
        if (!is.null(fit_VAST) && length(fit_VAST$Report) > 1) {
          break  # Exit loop if fit was successful
        } else {
          message("fit_VAST$Report has length 1, restarting loop...")
          attempt_counter <- attempt_counter + 1  # Increment attempt counter
          
          # Check if max attempts reached
          if (attempt_counter >= max_attempts) {
            message("Maximum number of attempts reached. Passing to the next repeat...")
            break  # Exit loop after max attempts 
          }
        }
      }
      
      #save fit
      save(list = "fit_VAST", file = paste0(getwd(),'/',mdir,'/fit_VASTbias.RData'))
      
      #remove objects
      rm(fit_VAST)
      
      # Initialize attempt counter
      attempt_counter <- 0
      
      ## VAST ####
      
      repeat {
        # Increment Newton steps with each attempt
        newtonsteps <- 1 + attempt_counter
        
        #deltagamma
        settings$ObsModel<-c(1,0)
        
        fit_VAST = tryCatch({
          fit_model(
            settings = settings,
            Lat_i = mdf$lat,
            Lon_i = mdf$lon,
            t_i = mdf$month,
            c_i = rep(0, nrow(mdf)),
            b_i = mdf$cells,
            a_i = rep(1, nrow(mdf)),
            newtonsteps = newtonsteps,
            test_fit = FALSE,
            fine_scale = FALSE,
            input_grid = input_grid,
            working_dir = paste0(getwd(),'/',mdir)
          )
        }, error = function(e) {
          message("Error in fit_model(): ", e$message)  # Print the error message
          return(NULL)
        })
        
        # Check if fit_VAST is NULL (indicating an error) or if fit_VAST$Report has length 1
        if (!is.null(fit_VAST) && length(fit_VAST$Report) > 1) {
          break  # Exit loop if fit was successful
        } else {
          message("fit_VAST$Report has length 1, restarting loop...")
          attempt_counter <- attempt_counter + 1  # Increment attempt counter
          
          # Check if max attempts reached
          if (attempt_counter >= max_attempts) {
            message("Maximum number of attempts reached. Passing to the next repeat...")
            break  # Exit loop after max attempts 
          }
        }
      }
      
      #save fit
      save(list = "fit_VAST", file = paste0(getwd(),'/',mdir,'/fit_VASTdeltagam.RData'))
        
      #remove objects
      rm(fit_VAST)
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
mods<-c("fit_sdmTMBlog.RData","fit_sdmTMBnb.RData","fit_sdmTMBtw.RData","fit_VASTbias.RData","fit_VASTdeltagam.RData" ,"fit_VASTdeltalog.RData")
mods<-gsub('.RData','',mods)

# #array to store predictions
pred_array<-array(0,dim = c(nrow(input_grid),8,12,length(1985:max(yr))),
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
  filt_ydf <- ydf[ydf$cells >= 1000, ]
  
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
        
        #if sdmTMB model
        if (grepl("sdmTMB", i)) {
          
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
              
              pred_obs<-
              rbind(pred_obs, 
              data.frame("year"=iyear, 
                         "month"=imonth,
                         'obs'=obs_sdmTMB,
                         'pred'=pred_sdmTMB,
                         'mod'=modname))
              
              
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
        } else {
          
          # Function to update VAST predictions
          update_vast_predictions <- function(fit, pred_array, fit_matrix, month, year) {
            if (!(length(fit$Report) == 1 || length(fit$Report) == 0)) {
              obs_VAST <- fit$data_frame$b_i
              pred_VAST <- fit$Report$D_i
              
              pred_obs<-
                rbind(pred_obs, 
                      data.frame("year"=iyear, 
                                 "month"=imonth,
                                 'obs'=obs_VAST,
                                 'pred'=pred_VAST,
                                 'mod'=modname))
              
              rrmse <- (sqrt(mean((obs_VAST - pred_VAST)^2))) / mean(obs_VAST)
              mae <- mean(abs(obs_VAST - pred_VAST))
              #rsq <- 1 - sum((obs_VAST - pred_VAST)^2) / sum((obs_VAST - mean(obs_VAST))^2)
              
              # Total number of parameters (fixed+random)
              #k_value <- fit$parameter_estimates$number_of_coefficients[2] + fit$parameter_estimates$number_of_coefficients[3]
              k_value <- fit$parameter_estimates$number_of_coefficients[[1]] 
              
              #fit_VAST$parameter_estimates$par
              #fit_VAST$tmb_list
              #length(unlist(fit_VAST$ParHat))
              aic<-fit$parameter_estimates$AIC[1]
              # Number of observations
              n <- nrow(fit$data_frame)
              # Calculate AICc
              aicc <- fit$parameter_estimates$AIC[1] + (2 * k_value * (k_value + 1)) / (n - k_value - 1)
              
              #NLL
              nll<-fit$parameter_estimates$objective[[1]] #NLL
              
              conv <- ifelse(class(fit$Report) == 'list', fit$parameter_estimates$Convergence_check, FALSE)
              
              fit_matrix <- rbind(fit_matrix, c(iyear, imonth, modname, rrmse, mae,aic,aicc ,nll, conv))
              
              cat(modname, " model Evaluation:\n")
              cat(" RMSE: ", rrmse, "\n")
              cat(" MAE: ", mae, "\n")
              cat(" AICc: ", aicc, "\n")
              cat(" NLL: ", nll, "\n")
              
              D_gt <- drop_units(fit$Report$D_gct[, 1, ])
              D_gt <- data.frame('cell' = 1:fit$spatial_list$n_g, D_gt)
              colnames(D_gt) <- c('cell', fit$year_labels)
              D_gt1 <- reshape2::melt(D_gt, id = 'cell')
              mdl <- make_map_info(Region = fit$settings$Region, spatial_list = fit$spatial_list, Extrapolation_List = fit$extrapolation_list)
              D <- merge(D_gt1, mdl$PlotDF, by.x = 'cell', by.y = 'x2i')
              
              pred_array[, modname, month, year] <- D$value
            } else {
              fit_matrix <- rbind(fit_matrix, c(iyear, imonth, modname, NA, NA, NA,NA,NA, 'no conv'))
              pred_array[, modname, month, year] <- rep(0, length = nrow(input_grid))
            }
            
            return(list(pred_array = pred_array, fit_matrix = fit_matrix,pred_obs=pred_obs))
          }
          
          #run fxn
          results <- update_vast_predictions(fit_VAST, pred_array, fit_matrix, imonth, match(iyear, 1985:max(df$year)))
          pred_array <- results$pred_array
          fit_matrix <- results$fit_matrix
          pred_obs <- results$pred_obs
        }
      } 
      
    } else {
      
      # Store Year, Month, Model, and metrics in the results matrix
      fit_matrix <- rbind(fit_matrix,
                          c(iyear, imonth, modname, NA, NA, NA,NA,NA, 'no model'))
      
      # Append results with zeros
      pred_array[,, month.abb[imonth], as.character(iyear)] <- cbind(input_grid$Lon, input_grid$Lat, 
                                                                     rep(0, length(input_grid$Lon)), 
                                                                     rep(0, length(input_grid$Lon)), 
                                                                     rep(0, length(input_grid$Lon)), 
                                                                     rep(0, length(input_grid$Lon)), 
                                                                     rep(0, length(input_grid$Lon)), 
                                                                     rep(0, length(input_grid$Lon)))
      
    }
  }
}

#save array
setwd(mydir)
save(fit_matrix, file = './ST drivers/red tides/data/processed/RT_fit_matrix.RData') #paste(yrs_region,collapse = "")
save(pred_array, file = './ST drivers/red tides/data/processed/pred_SDMs_RT.RData') #paste(yrs_region,collapse = "")
save(pred_obs, file = './ST drivers/red tides/data/processed/pred_obs_RT.RData') #paste(yrs_region,collapse = "")
load(file = './ST drivers/red tides/data/processed/RT_fit_matrix.RData') #paste(yrs_region,collapse = "")


fit_matrix<-data.frame(fit_matrix)
table(fit_matrix$year,fit_matrix$month,fit_matrix$convergence)




aggregate(RRMSE~convergence+model,fit_matrix,FUN=length)


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
library('ggh4x')

counts$approach<-ifelse(grepl('VAST',counts$model),'VAST','sdmTMB')
counts$submodel<-gsub('fit_VAST','',counts$model)
counts$submodel<-gsub('fit_sdmTMB','',counts$submodel)
fit_matrix$approach<-ifelse(grepl('VAST',fit_matrix$model),'VAST','sdmTMB')
fit_matrix$submodel<-gsub('fit_VAST','',fit_matrix$model)
fit_matrix$submodel<-gsub('fit_sdmTMB','',fit_matrix$submodel)
# Create a boxplot using ggplot2
ggplot(counts, aes(x = convergence, y = percentage, fill = convergence)) +
  geom_bar(stat = "identity") +
  scale_x_discrete(guide = guide_axis_nested(angle=0),labels = function(x) gsub("\\+", "\n", x))+
  labs(title = paste0("Convergence SDM RT"),
       x = "",
       y = "") +
  theme_minimal()

ggplot(counts, aes(x = interaction(approach, submodel), y = count, fill = convergence)) +
  geom_bar(stat = "identity") +
  geom_text(aes(label = ifelse(convergence == TRUE, count, "")), 
            vjust = -0.5) +
  scale_x_discrete(guide = guide_axis_nested(angle = 0)) +
  labs(title = "Convergence SDM RT",
       x = "",
       y = "") +
  theme_minimal()


ggplot()+
  geom_boxplot(data = fit_matrix,aes(x=interaction(approach, submodel),y=as.numeric(RRMSE),fill=interaction(approach, submodel)),outlier.shape = NA)+
  #facet_wrap(~year)+
  theme_bw()+
  scale_x_discrete(guide = guide_axis_nested(angle = 0)) +
  labs(y='RRMSE',fill='SDM',x='')+
  ggthemes::scale_fill_tableau()+
  scale_y_continuous(limits = c(0,15))


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






#load array
setwd(mydir)
load(file = './ST drivers/red tides/data/processed/pred_SDMs_RT.RData') #pred_array

# #same scale for all years and both approaches
# pred_max<-max(pred_array[])
# max_index <- which(pred_array == max(pred_array), arr.ind = TRUE)

#color scale from previous analysis
# Set up the color scale and breaks as you already have
colv.kb <- c("white", "purple", "blue", "darkblue", "cyan", "green", "darkgreen", "yellow", "orange", "red", "darkred")
funpal.kb <- colorRampPalette(colv.kb, bias = 2)

brks.idw <- c(0, 1e4 - 1, seq(1e4, 4e6, 10000), 1e8)
nbcols.idw <- length(brks.idw) -1
color.idw <- funpal.kb(nbcols.idw)


# Set up the PDF device
pdf(paste0(mydir,"/ST drivers/red tides/outputs/RT OM prediction maps_scale.pdf"), width = 11, height = 6)  # Landscape: Width > Height

# Plot predictions ####
for (iyear in 1985:max(yr)) {
  
  #iyear=2005
  
  #year predictions
  ypred<-pred_array[,,,as.character(iyear)]
  #summary(ypred)
  
  # Get the dimensions of the array
  nrow <- dim(ypred)[1] # 7954
  ncol <- dim(ypred)[2] # 5
  nslice <- dim(ypred)[3] # 12
  
  # Create a dataframe
  dfpred <- data.frame(
    lon = as.vector(ypred[, 1, ]),      # Extract lat
    lat = as.vector(ypred[, 2, ]),      # Extract lon
    cells_sdmTMB0 = as.vector(ypred[, 3, ]),   # Extract cells1
    cells_sdmTMB1 = as.vector(ypred[, 4, ]),   # Extract cells1
    cells_VAST = as.vector(ypred[, 5, ]),   # Extract cells2
    month = rep(month.abb, each = nrow)  # Add slice (time) column
  )
  
  #sums for annotation 
  sumdf<-aggregate(cbind(cells_sdmTMB0,cells_sdmTMB1,cells_VAST) ~ month,dfpred,FUN=sum)
  # Ensure the 'month' column is a factor with levels in month.abb order
  sumdf$month <- factor(sumdf$month, levels = month.abb)
  # Sort the dataframe based on month order
  sumdf <- sumdf[order(sumdf$month), ]
  na_tmb0<-sumdf[which(sumdf$cells_sdmTMB0==0),]
  na_tmb1<-sumdf[which(sumdf$cells_sdmTMB1==0),]
  na_vast<-sumdf[which(sumdf$cells_VAST==0),]
  
  
  # Ensure predictions are in the correct sf format
  predictions_sf <- st_as_sf(dfpred, coords = c("lon", "lat"), crs = 4326)
  
  # Assuming `sf_object` is your sf object
  sf_df <- st_as_sf(predictions_sf)  # Ensure it is an sf object if not already
  
  # Extract the coordinates (Lon, Lat) as a data frame
  sf_df_coords <- st_coordinates(sf_df)
  
  # # Convert to a data frame and add it to the original sf object
  sf_df <- cbind(as.data.frame(sf_df), sf_df_coords)
  
  # #sort factors just in case
  sf_df$month<-factor(sf_df$month,levels=c(month.abb))
  
  # #plot sdmTMB
  # plot_sdmTMB0<-
  #   ggplot() +
  #   geom_tile(data = sf_df, aes(x = X, y = Y, fill = log(cells_sdmTMB0)), height = res(depth)[2], width = res(depth)[1]) +  # Use clipped predictions
  #   #geom_raster(data = sf_df, aes(x = X, y = Y, fill = log(cells_sdmTMB0))) +  # Use clipped predictions
  #   coord_sf(crs = crs(depth),
  #            xlim = c(-87.99999, -80.49999), ylim = c(24.51496, 30.5)) +
  #   geom_sf(data = us_clipped_sf,
  #                fill = 'grey60', size = 1) +
  #   theme() +
  #   labs(x='',y='',title='sdmTMB')+
  #   theme_minimal() +
  #   scale_fill_gradient(low = "white", high = "red", na.value = 'transparent') +
  #   scale_x_continuous(breaks = c(-86, -82), expand = c(0, 0)) +
  #   scale_y_continuous(breaks = c(30, 28, 26), expand = c(0, 0)) +
  #   labs(fill = "log(cells/L)") +
  #   theme(panel.grid.major = element_line(color = rgb(235, 235, 235, 100, maxColorValue = 255),
  #                                         linetype = 'dashed', size = 0.5),
  #         panel.background = element_rect(fill = NA), panel.ontop = TRUE, text = element_text(size = 10),
  #         plot.margin = unit(c(0.1, 0.1, 0.1, 0.1), "lines"),
  #         legend.background = element_rect(fill = "transparent", colour = "transparent"),
  #         plot.title = element_text(hjust = 0.50, vjust = -1),
  #         legend.key = element_rect(color = "black"),
  #         legend.key.size = unit(1, "lines")) +  # Adjusting the legend key contour to black
  #   guides(fill = guide_colorbar(size = 0.5, barheight = 4,
  #                                frame.colour = "black", ticks=element_line(color='black'),
  #                                ticks.colour = "black",
  #                                ticks.linewidth = 0.2,
  #                                frame.linewidth=0.2)) +  # Change ticks to black
  #   facet_wrap(~month, ncol = 3)  # Use first three letters of the month
  # 
  # if (nrow(na_tmb0)!=0) {
  #   plot_sdmTMB0<-plot_sdmTMB0+
  #     geom_text(data = na_tmb0, aes(x = -86, y = 25.7, label = 'NO FIT'), color = "black", size = 3, fontface = "bold")
  # }

  #plot sdmTMB
  plot_sdmTMB1<-
    ggplot() +
    geom_tile(data = sf_df, aes(x = X, y = Y, fill = cells_sdmTMB1), height = res(depth)[2], width = res(depth)[1]) +  # Use clipped predictions
    #geom_raster(data = sf_df, aes(x = X, y = Y, fill = log(cells_sdmTMB1))) +  # Use clipped predictions
    coord_sf(crs = crs(depth),
             xlim = c(-87.99999, -80.49999), ylim = c(24.51496, 30.5)) +
    geom_sf(data = us_clipped_sf,
            fill = 'grey60', size = 1) +
    theme() +
    labs(x='',y='',title='sdmTMB')+
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

  if (nrow(na_tmb1)!=0) {
    plot_sdmTMB1<-plot_sdmTMB1+
      geom_text(data = na_tmb1, aes(x = -86, y = 25.7, label = 'NO FIT'), color = "black", size = 3, fontface = "bold")
  }
  
  #plot VAST
  plot_VAST<-
    ggplot() +
    geom_tile(data = sf_df, aes(x = X, y = Y, fill = cells_VAST), height = res(depth)[2], width = res(depth)[1]) +  # Use clipped predictions
    #geom_raster(data = sf_df, aes(x = X, y = Y, fill = log(cells_VAST))) +  # Use clipped predictions
    coord_sf(crs = crs(depth), 
             xlim = c(-87.99999, -80.49999), ylim = c(24.51496, 30.5)) +
    geom_sf(data = us_clipped_sf, 
            fill = 'grey60', size = 1) +
    theme() +
    labs(x='',y='',title='VAST')+
    theme_minimal() +
    scale_fill_gradientn(colors = color.idw, na.value = "white",limits = c(0, 10000000),
                           oob = scales::squish) +
    # scale_fill_gradient(low = "white", high = "red", na.value = 'transparent',
    #                     limits = c(0, 10000000),  # Ensure max cap
    #                     oob = scales::squish  ) +# Ensures values > 1,000,000 stay at max color
    scale_x_continuous(breaks = c(-86, -82), expand = c(0, 0)) +
    scale_y_continuous(breaks = c(30, 28, 26), expand = c(0, 0)) + 
    labs(fill = "cells/L") +
    theme(panel.grid.major = element_line(color = rgb(235, 235, 235, 100, maxColorValue = 255),
                                          linetype = 'dashed', size = 0.5),  legend.position = "right",legend.title = element_text(angle=90,hjust=0.5),
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

  if (nrow(na_vast)!=0) {
    plot_VAST<-plot_VAST+
      geom_text(data = na_vast, aes(x = -86, y = 25.7, label = 'NO FIT'), color = "black", size = 3, fontface = "bold")
  }
  
  # Create the combined plot
  final_plot <- plot_grid(
    ggdraw() + 
      draw_label(iyear, 
                 fontface = "bold", size = 16, hjust = 0.5), # Title
    plot_grid(plot_sdmTMB1, plot_VAST, nrow = 1),           # Combined plots
    ncol = 1,                                              # Arrange title and plots vertically
    rel_heights = c(0.1, 1)                                # Adjust title-to-plot height ratio
  )

  # Print the final combined plot
  print(final_plot)
}

#close pdf
dev.off()

# #variances
# sigma_G	IID random intercept variance
# sigma_E	Spatiotemporal random field marginal variance
# sigma_O	Spatial random field marginal variance
# sigma_Z	Spatially varying coefficient random field marginal variance

#create rasters (ascii file) to input Ecospace

#setwd
setwd(paste0(mydir,'/ST drivers/red tides/'))
dir.create('./sdmTMB RT rasters/')
dir.create('./VAST RT rasters/')

# Create red tides rasters ####
#loop over years and months
for (iyear in dimnames(pred_array)[[4]]) {
  for (imonth in dimnames(pred_array)[[3]]) {
    
    
    #select year and month
    #iyear=1990;imonth<-7
    
    #print process
    cat(paste('################',iyear,'################\n',
              '################',imonth,'################\n'))
    
    #year predictions
    ypred<-pred_array[,,imonth,as.character(iyear)]
    ypred1<-as.data.frame(ypred)
    
    # Create raster template based on depth raster
    r_template <- raster(extent(depth), resolution = res(depth), crs = crs(depth))
    
    # Convert dataframe to spatial points
    coordinates(ypred1) <- ~ lon + lat
    gridded(ypred1) <- TRUE
    
    # Convert to raster
    r.sdmTMB <- rasterize(ypred1, r_template, field = 'cells_sdmTMB1', fun = mean)  # Change field as needed
    r.VAST <- rasterize(ypred1, r_template, field = 'cells_VAST', fun = mean)  # Change field as needed
    
    #save rasters
    writeRaster(r.sdmTMB, paste0('./sdmTMB RT rasters/',iyear,sprintf("%02d", match(imonth, month.abb)),'_RTsdmTMB.asc'), format="ascii", overwrite=TRUE)
    writeRaster(r.VAST, paste0('./VAST RT rasters/',iyear,sprintf("%02d", match(imonth, month.abb)),'_RTVAST.asc'), format="ascii", overwrite=TRUE)
      
  }
}

#check
#plot(raster('./sdmTMB RT rasters/200909_RTsdmTMB.asc'))

#VIIRS ####

setwd(mydir)
lf<-list.files('./ST drivers/red tides/data/raw/VIIRS_redtide_maps_0.1degree/redtide_maps_0.1degree/',pattern = 'tif',full.names = TRUE)
#load(file = './ST drivers/red tides/data/processed/pred_obs_RT.RData') #pred_obs
load(file = paste0('./data/processed/filtered_', namefile, '.RData')) #filtered_points_df


# Ensure month column is two digits
filtered_points_df$month <- sprintf("%02d", filtered_points_df$month)

# #array to store predictions
viirs_obs<- matrix(NA, nrow = 0, ncol = 4)
colnames(viirs_obs) <- c("year", "month", 'viirs','obs')


for (f in lf) {
  
  #f<-lf[1]
  
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
  
  na.omit(ivalues)
  
  
  if (mean(ivalues,na.rm=TRUE)==0) {
    cat("### JUMPING -------")
    next
  }
  
  # Convert all 0 values to NA
  r2<-r1
  r2[r2 == 0] <- NA

  # Convert raster cells with values to polygons
  r2pol <- rasterToPolygons(r2, fun = function(x) !is.na(x) & x != 0, dissolve = TRUE)
  # Convert to sf object
  r2pol <- st_as_sf(r2pol)
  # Merge all polygons into a single polygon
  r2pol <- st_union(r2pol)
  
  #plot
  plot(r2)
  plot(r2pol,add=T)
  
  #filter by month and year obs samples
  ydf<-subset(filtered_points_df,year==y & month ==m)
  
  # Filter rows where cells >= 1000
  #filt_ydf <- ydf[ydf$cells >= 1000, ]
  
  #coordinates
  icoords <- data.frame(lon=ydf$lon, lat=ydf$lat)
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
  
  
  viirs_obs1<-na.omit(viirs_obs)

  second_max<-sort(viirs_obs1$obs, decreasing = TRUE)[2]
  first_max<-max(viirs_obs1$obs)  
  
  library(scales)
  
  # Normalize viirs values between 0 and 1
  #viirs_obs1$obs <- rescale(viirs_obs1$obs, to = c(0, 1))
  viirs_obs1$obs <- viirs_obs1$obs/first_max
  viirs_obs1$obs<-ifelse(viirs_obs1$obs>1,1,viirs_obs1$obs)
  viirs_obs1$viirs <- rescale(viirs_obs1$viirs, to = c(0, 1)) 
  
  library(tidyr)
  
  # Reshape the data to long format
  viirs_obs_long <- reshape(viirs_obs1,
                            varying = list(c("viirs", "obs")),
                            v.names = "value",
                            timevar = "variable",
                            times = c("viirs", "obs"),
                            direction = "long")
  

  ggplot(viirs_obs_long, aes(x = variable, y = value, fill = variable)) +
    geom_boxplot(alpha = 0.5) +
    labs(title = "Boxplot of Normalized VIIRS and Observations by Year",
         x = "Variable",
         y = "Value",
         fill = "Variable") +
    theme_minimal() +
    facet_wrap(~year, scales = 'free_y')
  
  
#check value


#check values and predicted values ####

setwd(mydir)
load(file = './ST drivers/red tides/data/processed/pred_obs_RT.RData') #pred_obs

head(pred_obs)

obs1<-subset(pred_obs,mod=='fit_sdmTMBlog')[,c('year','month','obs')]
pred_obs1<-pred_obs[,c("year","month","pred","mod")]

obs2<-
data.frame('year'=obs1$year,
           'month'=obs1$month,
           'pred'=obs1$obs,
           'mod'='obs')


pred_obs2<-rbind(obs2,pred_obs1)


ggplot()+
  geom_boxplot(data=pred_obs2,aes(x=mod,y=pred),fill=mod)+
  scale_y_continuous(limits=c(0,100000000))+
  facet_wrap(~year,scales='free_y')

ggplot()+
  geom_boxplot(data=pred_obs2,aes(x=mod,y=pred,fill=mod))+
  scale_y_continuous(limits=c(0,1000000000))

ggplot()+
  geom_boxplot(data=pred_obs2,aes(x=mod,y=log(1+pred),fill=mod))+
  #scale_y_continuous(limits=c(0,100000000))
  facet_wrap(~year,scales='free_y')

ggplot()+
  geom_boxplot(data=pred_obs2,aes(x=mod,y=log(1+pred),fill=mod))#+
  #scale_y_continuous(limits=c(0,100000000))


#load predarray as dataframe
#load array
setwd(mydir)
load(file = './ST drivers/red tides/data/processed/pred_SDMs_RT.RData') #pred_array
load(file = paste0('./ST drivers/red tides/data/processed/filtered_', namefile, '.RData'))
obs_df<-filtered_points_df

# Extract lon and lat (same for all months/years)
lon_vec <- pred_array[, "lon", 1, 1]  # Take first month/year as reference
lat_vec <- pred_array[, "lat", 1, 1]

# Extract model prediction data
selected_columns <- pred_array[, c('fit_sdmTMBlog', 'fit_sdmTMBnb' ,'fit_sdmTMBtw' ,'fit_VASTbias', 'fit_VASTdeltagam','fit_VASTdeltalog'), , ]

# Convert the 4D array into a dataframe
preds_df <- as.data.frame(as.table(selected_columns))

# Rename columns for clarity
colnames(preds_df) <- c("id", "mod", "month", "year", "cells")

# Convert id to numeric for merging
preds_df$id <- as.numeric(as.character(preds_df$id))

# Create a dataframe for lon and lat
lat_lon_df <- data.frame(
  id = as.numeric(names(lon_vec)),  # Extract IDs correctly
  lon = lon_vec,
  lat = lat_vec
)

# Merge lat/lon with predictions
preds_df <- merge(preds_df, lat_lon_df, by = "id")

# View the first rows
head(preds_df)

df1<-obs_df
df1<-sf::st_drop_geometry(df1)
df2<-preds_df

# Combine lat/lon columns into matrix for RANN::nn2
coords_df1 <- cbind(df1$lat, df1$lon)

for (pr in unique(df2$mod)) {
  
  pr<-unique(df2$mod)[1]
  
  
  
  df3<-subset(df2,mod==pr)
  coords_df3 <- cbind(df3$lat, df3$lon)

  if (!'closest_id' %in% names(df1)) {
    
  # Use RANN to find the closest matches
  nearest_neighbors <- RANN::nn2(coords_df3, coords_df1, k = 1)  # k=1 for nearest neighbor

  # Extract the indices of the closest neighbors
  closest_matches <- nearest_neighbors$nn.idx
  
  # Merge the closest match values from df2 into df1
  df1$closest_id <- closest_matches
  #names(df1)[ncol(df1)]<-paste0(names(df1)[ncol(df1)],'_',pr)
  
  }
  
  df1 <- cbind(df1, df3[df1$closest_id, "cells"])
  
  # View the merged dataframe
  #print(df1)
  names(df1)[ncol(df1)]<-pr

}

#reshape for plotting
df11<-reshape2::melt(df1,id.vars=c('year', 'month','lon','lat', 'closest_id'))
df111<-reshape2::melt(df1,id.vars=c('cells','year', 'month','lon','lat', 'closest_id'))

#plot log
ggplot()+
  geom_boxplot(data=subset(df11,year>=1985),aes(x=variable,y=log(1+value),color=variable))+
  facet_wrap(~year,scales='free_y')+
  theme(axis.text.x = element_blank())
#scale_y_continuous(limits = c(0,10000000))

ggplot()+
  geom_boxplot(data=subset(df11,year>=1985),aes(x=variable,y=log(1+value),color=variable))#+
  #facet_wrap(~year,scales='free_y')#+


#plot
ggplot()+
  geom_boxplot(data=subset(df11,year>=1985 & value <100000000000), #& variable %in% c('cells_obs','cells_sdmTMB1','cells_VAST')
               aes(x=variable,y=value,color=variable))+
  facet_wrap(~year,scales='free_y')+
  theme(axis.text.x = element_blank())


#plot
ggplot()+
  geom_boxplot(data=subset(df11,year>=1985 & value <100000000000), #& variable %in% c('cells_obs','cells_sdmTMB1','cells_VAST')
               aes(x=variable,y=value,color=variable))

#plot
ggplot() +
  geom_point(data = subset(df111, year >= 1985), aes(x = cells, y = value, color = variable)) +
  facet_wrap(~year, scales = 'free_y') +
  geom_abline(slope = 1, intercept = 0, linetype = "dashed", color = "red") #+  # 1:1 diagonal line
  #geom_smooth(data = subset(df111, year >= 1985), aes(x = cells_obs, y = value, color = variable), 
  #            method = "lm", se = FALSE, linetype = "solid")  # Regression line for each facet

# 
# preds_df[] <- lapply(preds_df, function(x) if (is.factor(x)) as.character(x) else x)
# obs_df[] <- lapply(obs_df, function(x) if (is.factor(x)) as.character(x) else x)
# 
# all_df <- rbind(preds_df, obs_df)
# 
# ggplot()+
#   geom_boxplot(data=subset(all_df,year>=1985),aes(x=mod,y=log(cells),color=mod))+
#   facet_wrap(~year,scales='free_y')#+
#   #scale_y_continuous(limits = c(0,10000000))
# 
# ggplot()+
#   geom_boxplot(data=subset(all_df,year>=1985),aes(x=mod,y=cells,color=mod))+
#   facet_wrap(~year,scales='free_y')+
#   scale_y_continuous(limits = c(0,10000000))
#    
# ggplot()+
#   geom_boxplot(data=subset(all_df,year>=1985),aes(x=mod,y=cells,color=mod))+
#   facet_wrap(~year,scales='free_y')+
#   scale_y_continuous(limits = c(10000000,NA))


dff<-pred_array[,,'Oct','2005']

# Convert dff to a data frame
dff <- as.data.frame(dff)

# Add an ID column
dff$ID <- seq_len(nrow(dff))


# Create the plot
ggplot(dff, aes(x = lon, y = lat)) +
  geom_point(color = "blue") +  # Scatter plot
  geom_text(aes(label = ID), vjust = -1, size = 3, color = "black") +  # Row number annotation
  labs(title = "Longitude-Latitude Plot with Row IDs",
       x = "Longitude",
       y = "Latitude") +
  theme_minimal()

#
#dff
#sel_xy

dff_filtered <- merge(dff, sel_xy, by.x = c("lat", "lon"),by.y=c('Y','X'))
print(sort(dff_filtered$ID))
op_cells<-sort(dff_filtered$ID)

# Create the plot
ggplot(dff_filtered, aes(x = lon, y = lat)) +
  geom_point(color = "blue") +  # Scatter plot
  geom_text(aes(label = ID), vjust = -1, size = 3, color = "black") +  # Row number annotation
  labs(title = "Longitude-Latitude Plot with Row IDs",
       x = "Longitude",
       y = "Latitude") +
  theme_minimal()


# Let's first extract the desired columns and time slice
selected_columns <- pred_array[op_cells, c("cells_sdmTMB0", "cells_sdmTMB1", "cells_VAST"), ,]

# Convert the 4D array into a dataframe
preds_df <- as.data.frame(as.table(selected_columns))

# Rename the columns for clarity
colnames(preds_df) <- c("id", "mod", "month", "year",'cells')

# View the dataframe
head(df)

preds_df<-
  data.frame(mod=preds_df$mod,
             cells=preds_df$cells,
             year=preds_df$year)

preds_df<-preds_df[which(preds_df$cells!=0),]



obs_df<-df
obs_df<-
  data.frame(mod='obs',
             cells=obs_df$cells,
             year=obs_df$year)
obs_df<-obs_df[which(obs_df$cells!=0),]
preds_df[] <- lapply(preds_df, function(x) if (is.factor(x)) as.character(x) else x)
obs_df[] <- lapply(obs_df, function(x) if (is.factor(x)) as.character(x) else x)

all_df <- rbind(preds_df, obs_df)

ggplot()+
  theme_minimal()+
  theme(legend.title = element_blank())+
  scale_x_discrete(labels = function(x) gsub("cells_", "", x)) +
  ggthemes::scale_fill_tableau()+
  geom_boxplot(data=subset(all_df,year>=1985 & mod %in% c('cells_sdmTMB1','cells_VAST','obs')),aes(x=mod,y=log(cells),fill=mod),color='black')+
  facet_wrap(~year,scales='free_y')#+
#scale_y_continuous(limits = c(0,10000000))

ggplot()+
  theme_minimal()+
  theme(legend.title = element_blank())+
  scale_x_discrete(labels = function(x) gsub("cells_", "", x)) +
  ggthemes::scale_fill_tableau()+
  geom_boxplot(data=subset(all_df,year>=1985 & mod %in% c('cells_sdmTMB1','cells_VAST','obs')),aes(x=mod,y=log(cells),fill=mod),color='black')#+
  #facet_wrap(~year,scales='free_y')#+


ggplot()+
  geom_boxplot(data=subset(all_df,year>=1985),aes(x=mod,y=cells,color=mod),color='black')+
  facet_wrap(~year,scales='free_y')+
  theme_minimal()+
  theme(legend.title = element_blank())+
  scale_x_discrete(labels = function(x) gsub("cells_", "", x)) +
  ggthemes::scale_fill_tableau()+
  scale_y_continuous(limits = c(0,10000000))

ggplot()+
  geom_boxplot(data=subset(all_df,year>=1985),aes(x=mod,y=cells,color=mod))+
  facet_wrap(~year,scales='free_y')+
  scale_y_continuous(limits = c(10000000,NA))
