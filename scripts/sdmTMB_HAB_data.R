# Settings #####
#remove and empty objects
#rm(list=ls());gc()

# #first check if sdm has already been run
# results.exist = file.exists(paste0(dir.sdmout,"/RT_fit_matrix.RData"))
# if(results.exist){
#   cat("Results already exist. \nRunning the model will clear the output folder.  Run anyway? \nEnter 'Y' to continue, 'N' to abort:\n")
#   user_input <- readline()
#   if(toupper(user_input)!='Y'){
#     stop("Aborted")
#   }
# }

#load libraries
library(sdmTMB)
library(lubridate)
library(ggplot2)
library(raster)
library(sf)
library(rnaturalearth)
library(cowplot)
library(scales)
library('ggh4x')
library(viridis)
library(terra)

#set.seed
set.seed(6)
setwd(wd)




#Make input grid----------------------------------------------------------------
fn.make_input_grid <- function(file.depth=file.depth,file.excl=file.excl){

depth <- raster(file.depth)
excl_depth <- raster(file.excl)
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

#convert data frame to sf object
input_grid1 <- st_as_sf(input_grid1, coords = c("Lon", "Lat"), crs = st_crs(depth))

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
input_grid <<- input_grid
#return(input_grid)
}


#create a dataframe from the minimum to the maximum order at monthly steps-----
fn.fit_monthly_sdmTMB <- function(habdata=filtered_points_df, styr=1985,enyr=max(filtered_points_df$year)){

  #styr=1985
  #enyr=max(filtered_points_df$year)
  
  file.predsdm = paste0(dir.sdmout,"/pred_SDMs_RT.RData")
  
  #first check if sdm has already been run
   results.exist = file.exists(file.predsdm)
   if(results.exist){
     cat("Results already exist. \nRunning the model will clear the output folder.  Run anyway? \nEnter 'Y' to continue, 'N' to abort:\n")
     user_input <- readline()
     if(toupper(user_input)!='Y'){
       stop("Aborted")
     }
   }
   unlink(dir.sdmout, recursive=T)
   dir.create(dir.sdmout)
   dir.create(paste0(dir.sdmout,"/plots"))
    

habdata=filtered_points_df

yr<-rep(c(range(habdata$year)[1]:range(habdata$year)[2]),each=12)
month<-rep(1:12,times=length(c(range(habdata$year)[1]:range(habdata$year)[2])))
month<-sprintf("%02d", month)
df_time<-data.frame('year'=yr,
                    'month'=month,
                    'timestep'=1:length(yr))


#create folder to store fit objects
dir.om <<- paste0(dir.sdmout,"/OM month")
if(!dir.exists(dir.om)) dir.create(dir.om)
setwd(dir.om)

#styr=2018; enyr=2018
# Loop fitting sdmTMB and VAST models #####
for (iyear in styr:enyr) {
  
  #select year
  #iyear=2005
  
  ydf<-subset(habdata,year==iyear)
  
  # Filter rows where cells >= 1000
  filt_ydf <- ydf[ydf$cells > 0, ]
  
  # Count the number of rows (observations) for each month
  mm <- names(table(filt_ydf$month)[table(filt_ydf$month) > 5])
  
  for (imonth in 1:12) {
    
    #imonth<-9
    
    #print process
   cat(paste('################',iyear,'################\n',
              '################',imonth,'################\n'));flush.console()
    
    
    #if month has data
    if (imonth %in% as.numeric(mm)) {
      
      #subset by month
      mdf<-subset(ydf,month==imonth)
      
      # Assuming mdf is your sf object
      mdf_df <- st_drop_geometry(mdf)
      mdf_df_pos<- subset(mdf_df,cells!=0)
      names(mdf_df)[which(names(mdf_df)%in%c('X','Y'))] <- c('lon','lat')
      names(mdf_df_pos)[which(names(mdf_df_pos)%in%c('X','Y'))] <- c('lon','lat')
      
      #create folder
      mdir<-paste0(dir.om,"/",iyear,sprintf("%02d", imonth))
      if(!dir.exists(mdir)) dir.create(mdir)
      if(dir.exists(mdir)) unlink(mdir)
      
      #remove previous fit files
      #file.remove(paste0(mdir,c("/fit_sdmTMB0.RData", "/fit_sdmTMB1.RData",'/fit_VAST.RData')))
      
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
      save(fit_sdmTMBnb, file = paste0(mdir,'/fit_sdmTMBnb.RData')) #paste(yrs_region,collapse = "")
      
      #save fit
      save(fit_sdmTMBlog, file = paste0(mdir,'/fit_sdmTMBlog.RData')) #paste(yrs_region,collapse = "")
      
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
pred_array<-array(0,dim = c(nrow(input_grid),2+length(mods),12,length(styr:enyr)),
                  dimnames = list(1:nrow(input_grid),c('lon','lat',mods),month.abb,styr:enyr))

# #array to store predictions
pred_obs<- matrix(NA, nrow = 0, ncol = 5)
colnames(pred_obs) <- c("year", "month", 'obs','pred','mod')

# Loop getting predictions ####
for (iyear in styr:enyr) {
  
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
          results <- update_sdmTMB_predictions(fit, modname, prediction_data, pred_array, fit_matrix, imonth, match(iyear, styr:enyr))
          pred_array <- results$pred_array
          fit_matrix <- results$fit_matrix
          pred_obs <- results$pred_obs  
      }
      } else {
        # Store Year, Month, Model, and metrics in the results matrix
        fit_matrix <- rbind(fit_matrix,
                            c(iyear, imonth, NA, NA, NA, NA,NA,NA, 'no model'))
        
        for (j in 1:length(mods)) {
          pred_array[, j, imonth, match(iyear, styr:enyr)] <- rep(0, nrow(input_grid))
        }
        
    }
  }
}

#save array


#setwd(mydir)
save(fit_matrix, file = paste0(dir.sdmout,'/RT_fit_matrix.RData')) #paste(yrs_region,collapse = "")
save(pred_array, file = paste0(dir.sdmout,'/pred_SDMs_RT.RData')) #paste(yrs_region,collapse = "")
save(pred_obs, file = paste0(dir.sdmout,'/pred_obs_RT.RData')) #paste(yrs_region,collapse = "")

load(file = paste0(dir.sdmout,'/RT_fit_matrix.RData')) #paste(yrs_region,collapse = "")
load(file = paste0(dir.sdmout,'/pred_SDMs_RT.RData')) #paste(yrs_region,collapse = "")
load(file = paste0(dir.sdmout,'/pred_obs_RT.RData')) #paste(yrs_region,collapse = "")

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
png(paste0(dir.sdmout,"/plots/sdm convergence.png"),width=7,height=7,units='in',res=300)
ggplot(counts, aes(x = convergence, y = percentage, fill = convergence)) +
  geom_bar(stat = "identity") +
  scale_x_discrete(guide = guide_axis_nested(angle=0),labels = function(x) gsub("\\+", "\n", x))+
  labs(title = paste0("Convergence SDM RT"),
       x = "",
       y = "") +
  theme_minimal()
dev.off()

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
png(paste0(dir.sdmout,"/plots/sdm rmse log nb.png"),width=7,height=7,units='in',res=300)
ggplot()+
  geom_boxplot(data = na.omit(fit_matrix),aes(x=interaction(approach, submodel),y=as.numeric(RRMSE),fill=interaction(approach, submodel)),outlier.shape = NA)+
  #facet_wrap(~year)+
  theme_bw()+
  scale_x_discrete(guide = guide_axis_nested(angle = 0)) +
  labs(y='RRMSE',fill='SDM',x='')+
  ggthemes::scale_fill_tableau()+
  scale_y_continuous(limits = c(0,15))
dev.off()

#plot
png(paste0(dir.sdmout,"/plots/sdm nll log nb.png"),width=7,height=7,units='in',res=300)
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
dev.off()
#plot
png(paste0(dir.sdmout,"/plots/sdm mae log nb.png"),width=7,height=7,units='in',res=300)
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
dev.off()
#plot
png(paste0(dir.sdmout,"/plots/sdm aic log nb.png"),width=7,height=7,units='in',res=300)
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
dev.off()
# #variances
# sigma_G	IID random intercept variance
# sigma_E	Spatiotemporal random field marginal variance
# sigma_O	Spatial random field marginal variance
# sigma_Z	Spatially varying coefficient random field marginal variance

#create rasters (ascii file) to input Ecospace

#setwd
#setwd(paste0(mydir,'/ST drivers/red tides/'))
#dir.create('./VAST RT rasters/')
setwd(dir.sdmout)

}

#predict sdm over grid----------------------------------------------------------
fn.predict_monthly_sdmTMB <- function(file.sdmpred = paste0(dir.sdmout,'/pred_SDMs_RT.RData'), file.depth=file.depth){
  
  # file.predsdm = list.files(dir.sdmout,pattern="^sdmTMB_log_stack")
  # 
  # #first check if sdm has already been run
  # results.exist = ifelse(length(file.predsdm)==0,F,T)
  # if(results.exist){
  #   #cat("Results already exist. \nRun anyway? \nEnter 'Y' to continue, 'N' to abort:\n")
  #   user_input <- readline("Results already exist. Run anyway (Y/N)?")
  #   if(toupper(user_input)!='Y'){
  #     stop("Aborted")
  #   }
  # }
  
  
  #file.sdmpred = paste0(dir.sdmout,'/pred_SDMs_RT.RData')
  depth = raster(file.depth)
  load(file.sdmpred)

#loop over years and months
sdm.nb = sdm.log = stack()
for(iyear in dimnames(pred_array)[[4]]) {
  for (imonth in dimnames(pred_array)[[3]]) {
    #iyear=2005
    #imonth='Sep'
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
    
    names(r.sdmTMB1) = names(r.sdmTMB2) = paste0(iyear,formatC(match(imonth,month.abb),width=2,flag=0))
    #add to stack
    sdm.log <- addLayer(sdm.log,r.sdmTMB1)
    sdm.nb <- addLayer(sdm.nb, r.sdmTMB2)
    #names(sdm.log)
    #save rasters
    #writeRaster(r.sdmTMB1, paste0(iyear,sprintf("%02d", match(imonth, month.abb)),'_predsdmTMBlog.asc'), format="ascii", overwrite=TRUE)
    #writeRaster(r.sdmTMB2, paste0('./sdmTMB RT rasters/',iyear,sprintf("%02d", match(imonth, month.abb)),'_predsdmTMBnb.asc'), format="ascii", overwrite=TRUE)
  }
}
sdm.log <<- sdm.log
sdm.nb <<- sdm.nb
file.sdmlog <- paste0(dir.sdmout,"/sdmTMB_log_stack_",gsub("X","",names(sdm.log)[1]),'-',gsub("X","",names(sdm.log)[nlayers(sdm.log)]))
file.sdmnb <- paste0(dir.sdmout,"/sdmTMB_nb_stack_",gsub("X","",names(sdm.nb)[1]),'-',gsub("X","",names(sdm.nb)[nlayers(sdm.nb)]))
writeRaster(sdm.log,file.sdmlog, overwrite=T)
writeRaster(sdm.nb,file.sdmnb, overwrite=T)
}
#plotting-----------------------------------------------------------------------
fn.plot_sdmTMB <- function(){
library('maps')
library('fields')

colv <- c("white", "purple", "blue", "darkblue", "cyan", "green", "darkgreen", "yellow", "orange", "red", "darkred")
funpal <- colorRampPalette(colv, bias = 2)
brks <-c(0, 1e4 - 1, seq(1e4, 4e6, 10000), 1e8)
nbcols <- length(brks) -1
color <- funpal(nbcols)

graphics.off();windows(record=T)
pdf(paste0(dir.sdmout,"/plots/sdmTMB log maps.pdf"),onefile=T)
par(mfrow=c(4,3),mar=c(1,1,2,0),oma=c(2,2,0,6))
for(i in 1:nlayers(sdm.log)){
  plot(sdm.log[[i]], main="", breaks=brks, col=color, colNA='darkgray', legend=F)
  map(database='state',region='Florida',add=T,fill=T,col='wheat')
  text(-86,26,gsub("X","",names(sdm.log)[i]),cex=1.5)
  if(substr(names(sdm.log)[i],6,7)=='12'){
   par(mfrow=c(1,1),mar=c(0,0,0,0),oma=c(0,0,0,1))
   image.plot(sdm.log[[i]],legend.only=T,breaks=brks[-length(brks)],col=color[-1],add=T,legend.width=1,legend.mar=4,legend.line=3,
   legend.lab = 'cells/L')
   par(mfrow=c(4,3),mar=c(1,1,2,0),oma=c(2,2,0,6))
   
  }
  if(i==nlayers(sdm.log)) dev.off()
}

pdf(paste0(dir.sdmout,"/plots/sdmTMB nb maps.pdf"),onefile=T)
for(i in 1:nlayers(sdm.nb)){
  plot(sdm.nb[[i]], main="", breaks=brks, col=color, colNA='darkgray', legend=F)
  map(database='state',region='Florida',add=T,fill=T,col='wheat')
  text(-86,26,gsub("X","",names(sdm.log)[i]),cex=1.5)
  if(substr(names(sdm.log)[i],6,7)=='12'){
    par(mfrow=c(1,1),mar=c(0,0,0,0),oma=c(0,0,0,1))
    image.plot(sdm.nb[[i]],legend.only=T,breaks=brks[-length(brks)],col=color[-1],add=T,legend.width=1,legend.mar=4,legend.line=3,
               legend.lab = 'cells/L')
    par(mfrow=c(4,3),mar=c(1,1,2,0),oma=c(2,2,0,6))
    
  }
 if(i==nlayers(sdm.nb)) dev.off()
  }

rm(list=setdiff(ls(),c('wd','dir.data','dir.plots','file.depth','file.excl','file.habsos','file.habRdat','url.habsos',
                       'inside_polygons','us_clipped_sf_polygons','dir.viirs','dir.sdmout')));gc()  #cleanup
}
# #VIIRS, severity RT rasters and plot ####
# #create folder
# setwd(paste0(mydir,'/ST drivers/red tides/'))
# dir.create('./RT severity rasters/')
# 
# #set wd and load files
# setwd(mydir)
# lf<-list.files('./ST drivers/red tides/data/raw/VIIRS_redtide_maps_0.1degree/redtide_maps_0.1degree/',pattern = 'tif',full.names = TRUE)
# #load(file = './ST drivers/red tides/data/processed/pred_obs_RT.RData') #pred_obs
# load(file = paste0('./ST drivers/red tides/data/processed/filtered_', namefile, '.RData')) #filtered_points_df
# 
# #ensure month column is two digits
# filtered_points_df$month <- sprintf("%02d", filtered_points_df$month)
# 
# #array to store predictions
# viirs_obs<- matrix(NA, nrow = 0, ncol = 4)
# colnames(viirs_obs) <- c("year", "month", 'viirs','obs')
# 
# #list
# plot_list<-list()
# 
# #loop
# for (f in lf) {
#   
#   #f<-lf[81]
#   
#   #get raster
#   r<-raster(f)
#   
#   #year and month
#   y<-substr(names(r),2,5)
#   m<-substr(names(r),7,8)
#   
#   #print
#   cat(paste0('################## ',y,m,'###\n'))
#   
#   # Set the extent manually
#   extent(r) <- c(-87.5, -81, 25, 30.5)
#   
#   # Set the CRS manually
#   crs(r) <- "+proj=longlat +datum=WGS84 +no_defs"
#   
#   # Flip the raster vertically
#   r1 <- flip(r, direction = "y")
#   #plot(r1)
#   
#   ivalues<-c(values(r1))
#   if (mean(ivalues,na.rm=TRUE)==0) {
#     cat("### JUMPING -------")
#     next
#   }
#   
#   #convert all 0 values to NA
#   r2<-r1
#   r2[r2 == 0] <- NA
#   
#   #convert raster cells with values to polygons
#   r2pol <- rasterToPolygons(r2, fun = function(x) !is.na(x) & x != 0, dissolve = TRUE)
#   #convert to sf object
#   r2pol <- st_as_sf(r2pol)
#   #merge all polygons into a single polygon
#   r2pol <- st_union(r2pol)
#   
#   #plot
#   #plot(r2)
#   #plot(r2pol,add=T)
#   
#   #ensure r2pol is an sf object
#   r2pol <- st_sf(geometry = r2pol)
#   
#   #assign the CRS from r2 (assuming r2 has a CRS)
#   st_crs(r2pol) <- st_crs(r2)
#   
#   #filter by month and year obs samples
#   ydf<-subset(filtered_points_df,year==y & month ==m)
#   
#   if (nrow(ydf)==0) {
#     next
#   }
#   #filter rows where cells >= 1000
#   #filt_ydf <- ydf[ydf$cells >= 1000, ]
#   
#   #coordinates
#   icoords <- data.frame(lon=ydf$lon, lat=ydf$lat,cells=ydf$cells)
#   
#   #convert raster to data frame for ggplot
#   raster_df <- as.data.frame(rasterToPoints(r2))
#   colnames(raster_df)[ncol(raster_df)]<-'freq'
#   
#   #reorder points based on cells values to plot higher values on top
#   icoords <- icoords[order(icoords$cells), ]
#   
#   #add raster data
#   ifile<-list.files(path = mydir,pattern = paste0(y,m,'_predsdmTMBlog.asc'),recursive = TRUE)
#   r.sdmTMB1<-raster(ifile)
#   
#   # Convert raster to data frame for ggplot
#   raster_cells1 <- as.data.frame(rasterToPoints(r.sdmTMB1))
#   colnames(raster_cells1)[ncol(raster_cells1)]<-'cells'
#   
#   #add raster data
#   ifile<-list.files(path = mydir,pattern = paste0(y,m,'_predsdmTMBnb.asc'),recursive = TRUE)
#   r.sdmTMB2<-raster(ifile)
#   
#   #convert raster to data frame for ggplot
#   raster_cells2 <- as.data.frame(rasterToPoints(r.sdmTMB2))
#   colnames(raster_cells2)[ncol(raster_cells2)]<-'cells'
#   
#   #create a color palette with white at the start
#   my_magma <- viridis::magma(100, direction = -1)
#   my_colors <- c("white", my_magma)
#   #prepare point type for shape mapping
#   icoords$point_type <- ifelse(icoords$cells == 0, "Zero cell count (X)", "Sampled (O)")
#   
#   #define color breaks
#   n_breaks <- 5
#   max_fill <- max(raster_cells2$cells, na.rm = TRUE)
#   max_color <- max(icoords$cells, na.rm = TRUE)
#   common_breaks <- pretty(c(0, max(max_fill, max_color)), n = n_breaks)
#   
#   #convert RasterLayer to SpatRaster
#   r.sdmTMB1_terra <- rast(r.sdmTMB1)
#   r.sdmTMB2_terra <- rast(r.sdmTMB2)
#   
#   #reproject polygon to match the raster CRS if needed
#   r2pol <- st_transform(r2pol, crs(r.sdmTMB1_terra))
#   
#   #convert the polygon to a SpatVector object
#   r2pol_vect <- vect(r2pol)
#   
#   #apply mask using terra package
#   r.sdmTMB1_clipped <- mask(r.sdmTMB1_terra, r2pol_vect)
#   r.sdmTMB2_clipped <- mask(r.sdmTMB2_terra, r2pol_vect)
#     
#   #set values outside the polygon to zero
#   r.sdmTMB1_clipped[is.na(r.sdmTMB1_clipped)] <- 0
#   r.sdmTMB2_clipped[is.na(r.sdmTMB2_clipped)] <- 0
#   
#   # Save as .asc file
#   writeRaster(r.sdmTMB1_clipped, 
#               filename = paste0("./ST drivers/red tides/RT severity rasters/", y, m, "_RTsevlog.asc"), 
#               filetype = "AAIGrid", 
#               overwrite = TRUE)
#   
#   # Save as .asc file
#   writeRaster(r.sdmTMB2_clipped, 
#               filename = paste0("./ST drivers/red tides/RT severity rasters/", y, m, "_RTsevnb.asc"), 
#               filetype = "AAIGrid", 
#               overwrite = TRUE)
#   
#   #convert raster to data frame for ggplot
#   sev_cells1 <- as.data.frame(r.sdmTMB1_clipped, xy = TRUE)
#   colnames(sev_cells1)[ncol(sev_cells1)]<-'cells'
#   #convert raster to data frame for ggplot
#   sev_cells2 <- as.data.frame(r.sdmTMB2_clipped, xy = TRUE)
#   colnames(sev_cells2)[ncol(sev_cells2)]<-'cells'
#   #convert raster to data frame for ggplot
#   pred_cells1 <- as.data.frame(r.sdmTMB1_terra, xy = TRUE)
#   colnames(pred_cells1)[ncol(pred_cells1)]<-'cells'
#   #convert raster to data frame for ggplot
#   pred_cells2 <- as.data.frame(r.sdmTMB2_terra, xy = TRUE)
#   colnames(pred_cells2)[ncol(pred_cells2)]<-'cells'
#   
#   #plot
#   p<-
#   ggplot() +
#     # Raster layer
#     #geom_raster(data = pred_cells2, aes(x = x, y = y, fill = cells)) +
#     geom_raster(data = sev_cells2, aes(x = x, y = y, fill = cells)) +
#     # Polygon border
#     #geom_raster(data = raster_df, aes(x = x, y = y, fill = freq)) +
#     #geom_sf(data = r2pol, fill = 'transparent', color = 'darkblue', linewidth = 0.7) +  # r2pol filled with color
#     
#     #scale_fill_gradient(low = "white", high = "#AEC936") +      
#     # Main colored points
#     #geom_point(data = icoords, aes(x = lon, y = lat, color = cells),
#     #         shape = 19, size = 2, stroke = 0.5) +
#     
#     # Circle outlines and Xs using shape map
#     #geom_point(data = icoords, aes(x = lon, y = lat, shape = point_type),
#     #       size = 3, stroke = 0.5, color = 'black', fill = NA) +
#     
#     # US base polygon
#     geom_sf(data = st_as_sf(us_clipped_sf_polygons), fill = 'grey80', color = 'black') +
#     # Shared color scales
#     scale_fill_gradientn(
#       colors = my_colors,
#       values = scales::rescale(common_breaks),  # Use scales::rescale
#       #breaks = common_breaks,
#       labels = scales::scientific_format(),
#       name = "cells/L (pred)"
#     ) +
#     scale_color_gradientn(
#       colors = my_colors,
#       values = scales::rescale(common_breaks),  # Use scales::rescale
#       #breaks = common_breaks,
#       labels = scales::scientific_format(),
#       name = "cells/L (obs)"
#     ) +
#     
#     # Manual shape legend
#     scale_shape_manual(
#       values = c("Zero cell count (X)" = 13, "Sampled (O)" = 1), 
#       labels = c('sample', '0 cells/L'),
#       name = "obs"
#     ) +
#     
#     # Titles and themes
#     theme_minimal() +
#     labs(x = '', y = '') +
#     annotate("text", x = -82, y = 30,
#              label = paste0(m, ' - ', y), hjust = 1,
#              size = 5, fontface = "bold") +
#     
#     # Theme and legend layout
#     theme(
#       legend.box = "horizontal",  # Change to vertical
#       legend.position = c(0.25, 0.25),  # Adjust legend position as needed
#       legend.box.just = "bottom",  # Center the legend box
#       legend.text = element_text(size = 10)) +
#     guides(
#       fill = guide_colorbar(order = 1,
#                             frame.colour = "black",  # bar frame color
#                             frame.linetype = "solid", frame.linewidth=1, # bar frame linetype
#                             ticks = T,  # show the ticks on the bar
#                             ticks.colour = "white"),  # tick color
#       color = guide_colorbar(order = 2,
#                              frame.colour = "black",  # bar frame color
#                              frame.linetype = "solid",  # bar frame linetype
#                              ticks = T,  # show the ticks on the bar
#                              ticks.colour = "white"),  # tick color
#       shape = guide_legend(order = 3, override.aes = list(size = 3))
#     )
#   
#   plot_list[[paste0(m,y)]]<-p
#   
#   
#   
#   
#   #spatial coords
#   coordinates(icoords) <- ~lon+lat
#   
#   #extract values from raster
#   values <- raster::extract(r1, icoords)
#   
#   #append results
#   viirs_obs<-rbind(viirs_obs,
#                    data.frame(year=y,
#                               month=m,
#                               viirs=values,
#                               obs=ydf$cells))
#   
# }
# 
# 
# #check example to see 2018 severity maps
# #y<-'2018'
# #ilist<-plot_list[grepl(paste0(y), names(plot_list))]
# #do.call(gridExtra::grid.arrange, c(ilist, ncol = 3))  # Adjust ncol as needed

# #Plot predictions ####
# #color scale from previous analysis
# #set up the color scale and breaks as you already have
# colv.kb <- c("white", "purple", "blue", "darkblue", "cyan", "green", "darkgreen", "yellow", "orange", "red", "darkred")
# funpal.kb <- colorRampPalette(colv.kb, bias = 2)
# 
# brks.idw <- c(0, 1e4 - 1, seq(1e4, 4e6, 10000), 1e8)
# nbcols.idw <- length(brks.idw) -1
# color.idw <- funpal.kb(nbcols.idw)
# 
# #set up the PDF device
# dir.create(paste0(mydir,"/ST drivers/red tides/outputs/"))
# pdf(paste0(mydir,"/ST drivers/red tides/outputs/RT OM prediction maps_scale.pdf"), width = 11, height = 6)  # Landscape: Width > Height
# 
# #loop
# for (iyear in 2012:max(yr)) {
#   
#   #iyear=2013
# 
#   cat(paste0("############# ",iyear,' \n' ))
#   #list months you want (example: January to December)
#   months <- sprintf("%02d", 1:12)  # "01", "02", ..., "12"
#   
#   #build expected filenames
#   files1 <-  paste0("./ST drivers/red tides/RT severity rasters/", iyear, months, "_RTsevlog.asc")
#   files2 <-  paste0("./ST drivers/red tides/RT severity rasters/", iyear, months, "_RTsevnb.asc")
#   
#   names(files1) <- months  # Name them by month
#   names(files2) <- months  # Name them by month
#   
#   #load rasters into a list (some might not exist)
#   raster_list1 <- lapply(files1, function(f) {
#     if (file.exists(f)) {
#       rast(f)
#     } else {
#       NULL  # If not found, keep NULL
#     }
#   })
#   
#   #load rasters into a list (some might not exist)
#   raster_list2 <- lapply(files2, function(f) {
#     if (file.exists(f)) {
#       rast(f)
#     } else {
#       NULL  # If not found, keep NULL
#     }
#   })
#   
#   #function to convert raster to dataframe for ggplot
#   raster_to_df <- function(r, month) {
#     if (is.null(r)) {
#       return(data.frame(x = NA, y = NA, value = NA, month = month))
#     } else {
#       df <- as.data.frame(r, xy = TRUE, na.rm = FALSE)
#       names(df) <- c("x", "y", "value")
#       df$month <- month
#       return(df)
#     }
#   }
#   
#   #apply to all rasters
#   df_list1 <- Map(raster_to_df, raster_list1, names(raster_list1))
#   df_list2 <- Map(raster_to_df, raster_list2, names(raster_list2))
#   
#   # Combine all into one big dataframe
#   all_df1 <- dplyr::bind_rows(df_list1)
#   all_df2 <- dplyr::bind_rows(df_list2)
# 
#   #generate plot
#   plot_sdmTMB1 <- 
#     ggplot() +
#     geom_raster(data=all_df1, aes(x = x, y = y, fill = value),na.rm = TRUE) +
#     #geom_tile(data = sf_df, aes(x = X, y = Y, fill = sdmTMBlog), height = res(depth)[2], width = res(depth)[1]) +  # Use clipped predictions
#     #geom_raster(data = sf_df, aes(x = X, y = Y, fill = log(cells_sdmTMB1))) +  # Use clipped predictions
#     coord_sf(crs = crs(depth),
#              xlim = c(-87.99999, -80.49999), ylim = c(24.51496, 30.5)) +
#     geom_sf(data = us_clipped_sf,
#             fill = 'grey60', size = 1) +
#     theme() +
#     labs(x='',y='',title='sdmTMB LOG')+
#     theme_minimal() +
#     scale_fill_gradientn(colors = color.idw, na.value = "white",limits = c(0, 10000000),
#                          oob = scales::squish) +
#     #scale_fill_gradientn(colors = color.idw, breaks = brks.idw, labels = c("0", "10K", "100K", "1M", "4M", "10M"), na.value = "white") +
#     # scale_fill_gradient(low = "white", high = "red", na.value = 'transparent',
#     #                     limits = c(0, 10000000),  # Ensure max cap
#     #                     oob = scales::squish  ) +# Ensures values > 1,000,000 stay at max color
#     scale_x_continuous(breaks = c(-86, -82), expand = c(0, 0)) +
#     scale_y_continuous(breaks = c(30, 28, 26), expand = c(0, 0)) +
#     labs(fill = "cells/L") +
#     theme(panel.grid.major = element_line(color = rgb(235, 235, 235, 100, maxColorValue = 255),
#                                           linetype = 'dashed', linewidth  = 0.5),
#           legend.position = "right",legend.title = element_text(angle=90,hjust=0.5),
#           panel.background = element_rect(fill = NA), panel.ontop = TRUE, text = element_text(size = 10),
#           plot.margin = unit(c(0.1, 0.1, 0.1, 0.1), "lines"),
#           legend.background = element_rect(fill = "transparent", colour = "transparent"),
#           plot.title = element_text(hjust = 0.50, vjust = -1),
#           legend.key = element_rect(color = "black"),
#           legend.key.size = unit(1, "lines")) +  # Adjusting the legend key contour to black
#     guides(fill = guide_colorbar(size = 0.5, barwidth = 0.5, barheight = unit(1, "npc"),  # Full height of the plot
#                                  frame.colour = "black", ticks = element_line(color = 'black'),
#                                  ticks.colour = "black",
#                                  ticks.linewidth = 0.2,
#                                  title.position = "right",  # Moves the legend title to the right of the color bar
#                                  label.position = "right",  # Ensures the labels are also aligned with the color bar
#                                  frame.linewidth = 0.2)) +  # Change ticks to black
#     facet_wrap(~month, ncol = 3)  # Use first three letters of the month
#   
#   plot_sdmTMB2 <- 
#     ggplot() +
#     geom_raster(data=all_df2, aes(x = x, y = y, fill = value),na.rm = TRUE) +
#     #geom_tile(data = sf_df, aes(x = X, y = Y, fill = sdmTMBlog), height = res(depth)[2], width = res(depth)[1]) +  # Use clipped predictions
#     #geom_raster(data = sf_df, aes(x = X, y = Y, fill = log(cells_sdmTMB1))) +  # Use clipped predictions
#     coord_sf(crs = crs(depth),
#              xlim = c(-87.99999, -80.49999), ylim = c(24.51496, 30.5)) +
#     geom_sf(data = us_clipped_sf,
#             fill = 'grey60', size = 1) +
#     theme() +
#     labs(x='',y='',title='sdmTMB NB')+
#     theme_minimal() +
#     scale_fill_gradientn(colors = color.idw, na.value = "white",limits = c(0, 10000000),
#                          oob = scales::squish) +
#     #scale_fill_gradientn(colors = color.idw, breaks = brks.idw, labels = c("0", "10K", "100K", "1M", "4M", "10M"), na.value = "white") +
#     # scale_fill_gradient(low = "white", high = "red", na.value = 'transparent',
#     #                     limits = c(0, 10000000),  # Ensure max cap
#     #                     oob = scales::squish  ) +# Ensures values > 1,000,000 stay at max color
#     scale_x_continuous(breaks = c(-86, -82), expand = c(0, 0)) +
#     scale_y_continuous(breaks = c(30, 28, 26), expand = c(0, 0)) +
#     labs(fill = "cells/L") +
#     theme(panel.grid.major = element_line(color = rgb(235, 235, 235, 100, maxColorValue = 255),
#                                           linetype = 'dashed', linewidth  = 0.5),
#           legend.position = "right",legend.title = element_text(angle=90,hjust=0.5),
#           panel.background = element_rect(fill = NA), panel.ontop = TRUE, text = element_text(size = 10),
#           plot.margin = unit(c(0.1, 0.1, 0.1, 0.1), "lines"),
#           legend.background = element_rect(fill = "transparent", colour = "transparent"),
#           plot.title = element_text(hjust = 0.50, vjust = -1),
#           legend.key = element_rect(color = "black"),
#           legend.key.size = unit(1, "lines")) +  # Adjusting the legend key contour to black
#     guides(fill = guide_colorbar(size = 0.5, barwidth = 0.5, barheight = unit(1, "npc"),  # Full height of the plot
#                                  frame.colour = "black", ticks = element_line(color = 'black'),
#                                  ticks.colour = "black",
#                                  ticks.linewidth = 0.2,
#                                  title.position = "right",  # Moves the legend title to the right of the color bar
#                                  label.position = "right",  # Ensures the labels are also aligned with the color bar
#                                  frame.linewidth = 0.2)) +  # Change ticks to black
#     facet_wrap(~month, ncol = 3)  # Use first three letters of the month
#   
#   #create the combined plot
#   final_plot <- plot_grid(
#     ggdraw() + 
#       draw_label(iyear, 
#                  fontface = "bold", size = 16, hjust = 0.5), # Title
#     plot_grid(plot_sdmTMB1,plot_sdmTMB2,nrow = 1),           # Combined plots
#     ncol = 1,                                              # Arrange title and plots vertically
#     rel_heights = c(0.1, 1)                                # Adjust title-to-plot height ratio
#   )
#   
#   #print the final combined plot
#   print(final_plot)
# }
# 
# #close pdf
# dev.off()
