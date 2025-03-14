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
    
    #imonth<-1
    
    #print process
    cat(paste('################',iyear,'################\n',
              '################',imonth,'################\n'))
    
    
    #if month has data
    if (imonth %in% as.numeric(mm)) {
      
      #subset by month
      mdf<-subset(ydf,month==imonth)
      
      # Assuming mdf is your sf object
      mdf_df <- st_drop_geometry(mdf)
      
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
      fit_sdmTMB0 <- tryCatch({
        sdmTMB(
        formula = cells ~ 0,  # Formula for the model (adjust as needed)
        data = mdf_df,
        mesh = sdmTMB::make_mesh(mdf_df, xy_cols = c("lon", "lat"), cutoff = 0.1),
        family = tweedie(link = "log"),  # Specify distribution family
        spatial = "on",  # Enable spatial effects
        spatiotemporal = "off"  # No temporal effects since you have one time step # Increase iterations if necessary
      )}, error = function(e) {
        message("Error in fit TMB0")
        return(NULL)  # Return NULL so we can check and restart the loop
      })

        # Run model
      #fit model with intercept
      fit_sdmTMB1 <- tryCatch({
        sdmTMB(
        formula = cells ~ 1,  # Formula for the model (adjust as needed)
        data = mdf_df,
        mesh = sdmTMB::make_mesh(mdf_df, xy_cols = c("lon", "lat"), cutoff = 0.1),
        family = tweedie(link = "log"),  # Specify distribution family
        spatial = "on",  # Enable spatial effects
        spatiotemporal = "off"  # No temporal effects since you have one time step # Increase iterations if necessary
      )}, error = function(e) {
        message("Error in fit TMB1")
        return(NULL)  # Return NULL so we can check and restart the loop
      })
      
      
      # Check if fit_VAST is NULL (indicating an error) or if fit_VAST$Report has length 1
      if (!is.null(fit_sdmTMB1) | !is.null(fit_sdmTMB0)) {
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
      save(fit_sdmTMB0, file = paste0(getwd(),'/',mdir,'/fit_sdmTMB0.RData')) #paste(yrs_region,collapse = "")
      
      #save fit
      save(fit_sdmTMB1, file = paste0(getwd(),'/',mdir,'/fit_sdmTMB1.RData')) #paste(yrs_region,collapse = "")
      
      #remove objects
      rm(fit_sdmTMB0,fit_sdmTMB1)
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
      save(list = "fit_VAST", file = paste0(getwd(),'/',mdir,'/fit_VAST.RData'))
        
      #remove objects
      rm(fit_VAST)
      gc()
      
      #if month no data  
    } else {
      NULL
    }
    }
}

# #array to store predictions
pred_array<-array(0,dim = c(nrow(input_grid),5,12,length(1985:max(yr))),
                  dimnames = list(1:nrow(input_grid),c('lon','lat','cells_sdmTMB0',"cells_sdmTMB1",'cells_VAST'),month.abb,1985:max(df$year)))

# Loop getting predictions ####
for (iyear in 1985:max(yr)) {
  
  #select year
  #iyear=1985
  
  ydf<-subset(filtered_points_df,year==iyear)
  
  # Filter rows where cells >= 1000
  filt_ydf <- ydf[ydf$cells >= 1000, ]
  
  # Count the number of rows (observations) for each month
  mm <- names(table(filt_ydf$month)[table(filt_ydf$month) > 5])
  
  for (imonth in 1:12) {
    
    #imonth<-9
    
    #print process
    cat(paste('################',iyear,'################\n',
              '################',imonth,'################\n'))
    
    #check files - to see if VAST fit is there
    ifiles<-list.files(paste0(iyear,sprintf("%02d", imonth)),recursive = TRUE,full.names = TRUE)
    ifiles<-ifiles[grepl("fit_", ifiles) ]
    
    
    #if month has data
    if (imonth %in% as.numeric(mm)) {
    
      #if month has data and has 3 fit files
      for (i in ifiles) {
        
        #i=ifiles[2]
        
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
          vcov(fit)
          se<-sqrt(diag(vcov(fit)))
          fit$sd_report
          fit$sd_report$
          #b_j      10.691409  0.6741630 #intercept vector
          #ln_tau_O  2.887421        NaN #SD spatial
          #ln_kappa  3.763843        NaN #spatial decorrelation rate
          #thetaf    1.282290  0.3864381 #temporal autorocrrelation???
          #ln_phi    5.246758  0.5108104 #dispersion ???
          #Hessian
          #gradient
          
          # Create prediction grid for each month
          prediction_data <- data.frame(
            lon = input_grid$Lon, 
            lat = input_grid$Lat, 
            month = imonth  # Add the month variable
          )
          
          #update pred_array
          update_predictions <- function(fit, pred_col, pred_data, pred_array, month, year) {
            if (!is.null(fit)) {
              predictions <- predict(fit, newdata = pred_data, type = 'response', t_i = pred_data$month, se_fit = FALSE)
              pred_array[, c('lon', 'lat', pred_col), month, year] <- cbind(pred_data$lon, pred_data$lat, predictions$est)
            } else {
              pred_array[, c('lon', 'lat', pred_col), month, year] <- cbind(pred_data$lon, pred_data$lat, rep(0, length(pred_data$lon)))
            }
            return(pred_array)  # Ensure changes persist
          }
          
          #col
          col_cells<-ifelse(grepl("sdmTMB1", i),'cells_sdmTMB1','cells_sdmTMB0')
          
          #append
          pred_array <- update_predictions(fit, col_cells, prediction_data, pred_array, imonth, match(iyear, 1985:max(df$year)))
          #head(pred_array[,,month.abb[imonth],as.character(iyear)])
          
  
        } else {
          
          # Function to handle VAST fit and update the array
          update_vast_predictions <- function(fit, pred_array, month, year) {
            if (!(length(fit$Report) == 1 || length(fit$Report) == 0)) {
            
              #fit<-fit_VAST
              # Get densities
              D_gt <- drop_units(fit$Report$D_gct[, 1, ])
              D_gt <- data.frame('cell' = 1:fit$spatial_list$n_g, D_gt)
              colnames(D_gt) <- c('cell', fit$year_labels)
              D_gt1 <- reshape2::melt(D_gt, id = 'cell')
              
              # Get spatial info
              mdl <- make_map_info(Region = fit$settings$Region,
                                   spatial_list = fit$spatial_list,
                                   Extrapolation_List = fit$extrapolation_list)
              
              # Merge densities and spatial info
              D <- merge(D_gt1, mdl$PlotDF, by.x = 'cell', by.y = 'x2i')
              
              # Append results
              pred_array[, 'cells_VAST', month, year] <- D$value
              
            } else {
              # Append results with zeros
              pred_array[, 'cells_VAST', month, year] <- rep(0, length = nrow(input_grid))
            }
            return(pred_array)  # Ensure changes persist
          }
          
          # Update VAST predictions
          pred_array <- update_vast_predictions(fit_VAST, pred_array, imonth, match(iyear, 1985:max(df$year)))
        }
      } 
      
    } else {
      
      # Append results with zeros
      pred_array[,, month.abb[imonth], as.character(iyear)] <- cbind(input_grid$Lon, input_grid$Lat, rep(0, length(input_grid$Lon)), rep(0, length(input_grid$Lon)), rep(0, length(input_grid$Lon)))
      
    }
  }
}

#save array
setwd(mydir)
save(pred_array, file = './ST drivers/red tides/data/processed/pred_SDMs_RT.RData') #paste(yrs_region,collapse = "")

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
  
  iyear=2005
  
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
plot(raster('./sdmTMB RT rasters/200909_RTsdmTMB.asc'))

   