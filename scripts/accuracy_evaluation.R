#accuracy evaluation

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
yyyymm<-substr(nbsev.files,1,6)

# make a regex pattern like "201209|201210|201211"
yyyymm1 <- paste(yyyymm, collapse = "|")

#subset
logsdm.files1 <- logsdm.files[grepl(yyyymm1, basename(logsdm.files))]
nbsdm.files1 <- nbsdm.files[grepl(yyyymm1, basename(nbsdm.files))]
logsev.files1 <- logsev.files[grepl(yyyymm1, basename(logsev.files))]
nbsev.files1 <- nbsev.files[grepl(yyyymm1, basename(nbsev.files))]

plot(raster(paste0(idir,'/RT severity rasters/',logsev.files1[2])))
plot(raster(paste0(idir,'/sdmTMB RT rasters/',logsdm.files1[2])))

library(dplyr)
library(stringr)
library(raster)
library(purrr)
library(tidyr)
library(pROC)

#accuracy obs - pred dens ####

# 1. Extract yyyymm from raster filenames
file_dates <- str_extract(logsdm.files1, "\\d{6}")

# 2. Create a table of filenames and their yyyymm
files_tbl1 <- tibble(filename = logsdm.files1, yyyymm = file_dates, sdm = 'log')
files_tbl2 <- tibble(filename = nbsdm.files1, yyyymm = file_dates, sdm = 'nb')
files_tbl<- rbind(files_tbl1,files_tbl2)
# 3. Function to calculate accuracy metrics for one year-month
evaluate_accuracy <- function(filename, yyyymm, points_df, raster_dir) {
  
  #i<-1
  
  #filename<-files_tbl[i,'filename']
  #yyyymm<-files_tbl[i,'yyyymm']
  
  # Parse year and month
  yr <- as.integer(substr(yyyymm, 1, 4))
  mo <- as.integer(substr(yyyymm, 5, 6))
  
  # Filter points for that year-month
  pts <- filter(filtered_points_df, year == yr, month == mo)
  
  if(nrow(pts) == 0) {
    message("No points for ", yyyymm)
    return(tibble(year = yr, month = mo, RMSE = NA_real_, Correlation = NA_real_, n_points = 0))
  }
  
  # Load raster
  r <- raster(file.path(raster_dir, filename))
  
  # Extract raster values at points
  pred_vals <- raster::extract(r, pts[, c("lon", "lat")])
  
  # Compute metrics only for points with predictions
  valid <- !is.na(pred_vals)
  obs <- pts$cells[valid]
  pred <- pred_vals[valid]
  mean_obs <- mean(obs)
  
  rmse <- sqrt(mean((obs - pred)^2))
  cor_val <- if(length(obs) > 1) cor(obs, pred) else NA_real_
  rrmse <- ifelse(mean_obs != 0, rmse / mean_obs, NA_real_)
  
  tibble(
    year = yr,
    month = mo,
    #RMSE = rmse,
    RRMSE = rrmse,
    correlation = cor_val,
    n_points = length(obs)
  )
}

# 4. Directory where rasters live
raster_dir <- (paste0(idir,'/sdmTMB RT rasters'))

# 5. Loop over all year-month raster files and compute accuracy
results1 <- files_tbl %>%
  mutate(metrics = map2(filename, yyyymm, ~evaluate_accuracy(.x, .y, filtered_points_df, raster_dir))) %>%
  unnest(metrics)
results1$clip<-FALSE
print(results1)


#accuracy obs - pred bin ####

library(dplyr)
library(stringr)
library(raster)
library(purrr)
library(tidyr)

# 1. Extract yyyymm from raster filenames
file_dates <- str_extract(logsdm.files1, "\\d{6}")

# 2. Create table of filenames and their yyyymm (including your sdm type)
files_tbl1 <- tibble(filename = logsdm.files1, yyyymm = file_dates, sdm = 'log')
files_tbl2 <- tibble(filename = nbsdm.files1, yyyymm = file_dates, sdm = 'nb')
files_tbl <- bind_rows(files_tbl1, files_tbl2)

# 3. Function to calculate binary accuracy metrics for one year-month
evaluate_binary_accuracy <- function(filename, yyyymm, points_df, raster_dir, threshold = 1000) {
  
  yr <- as.integer(substr(yyyymm, 1, 4))
  mo <- as.integer(substr(yyyymm, 5, 6))
  
  # Filter points for that year-month
  pts <- filter(points_df, year == yr, month == mo)
  
  if (nrow(pts) == 0) {
    message("No points for ", yyyymm)
    return(tibble(year = yr, month = mo, Accuracy = NA_real_, Sensitivity = NA_real_, Specificity = NA_real_, Kappa = NA_real_, n_points = 0))
  }
  
  # Load raster
  r <- raster(file.path(raster_dir, filename))
  
  # Extract predicted values at points
  pred_vals <- raster::extract(r, pts[, c("lon", "lat")])
  
  # Valid indices (non-NA)
  valid <- !is.na(pred_vals)
  
  obs <- pts$cells[valid]     # Observed values — adjust if different col name
  pred <- pred_vals[valid]    # Predicted values
  
  # Convert to binary presence/absence using threshold
  obs_bin <- ifelse(obs > threshold, 1, 0)
  pred_bin <- ifelse(pred > threshold, 1, 0)
  
  # Confusion matrix components
  TP <- sum(pred_bin == 1 & obs_bin == 1)
  TN <- sum(pred_bin == 0 & obs_bin == 0)
  FP <- sum(pred_bin == 1 & obs_bin == 0)
  FN <- sum(pred_bin == 0 & obs_bin == 1)
  
  # Metrics
  Accuracy <- (TP + TN) / (TP + TN + FP + FN)
  Sensitivity <- ifelse((TP + FN) > 0, TP / (TP + FN), NA_real_)
  Specificity <- ifelse((TN + FP) > 0, TN / (TN + FP), NA_real_)
  
  # Cohen's Kappa
  total <- TP + TN + FP + FN
  po <- Accuracy
  pe <- (((TP + FP) * (TP + FN)) + ((FN + TN) * (FP + TN))) / (total^2)
  Kappa <- ifelse((1 - pe) != 0, (po - pe) / (1 - pe), NA_real_)
  
  # Calculate AUC with pROC package (only if there is variation in obs_bin)
  AUC <- NA_real_
  if(length(unique(obs_bin)) > 1) {  # Need both classes present
    roc_obj <- try(pROC::roc(obs_bin, pred, quiet = TRUE), silent = TRUE)
    if (!inherits(roc_obj, "try-error")) {
      AUC <- pROC::auc(roc_obj)[1]  # numeric value
    }
  }
  
  tibble(
    year = yr,
    month = mo,
    accuracy = Accuracy,
    sensitivity = Sensitivity,
    specificity = Specificity,
    kappa = Kappa,
    AUC = AUC,
    n_points = length(obs_bin)
  )
}

# 4. Directory where rasters live
raster_dir <- paste0(idir, '/sdmTMB RT rasters')

# 5. Loop over all year-month raster files and compute binary accuracy
results_binary1 <- files_tbl %>%
  mutate(metrics = map2(filename, yyyymm, ~evaluate_binary_accuracy(.x, .y, filtered_points_df, raster_dir))) %>%
  unnest(metrics)
results_binary1$clip<-FALSE
print(results_binary1)

#accuracy obs - pred+clip dens ####

# 1. Extract yyyymm from raster filenames
file_dates <- str_extract(logsev.files1, "\\d{6}")

# 2. Create a table of filenames and their yyyymm
files_tbl1 <- tibble(filename = logsev.files1, yyyymm = file_dates, sdm = 'log')
files_tbl2 <- tibble(filename = nbsev.files1, yyyymm = file_dates, sdm = 'nb')
files_tbl<- rbind(files_tbl1,files_tbl2)
# 3. Function to calculate accuracy metrics for one year-month
evaluate_accuracy <- function(filename, yyyymm, points_df, raster_dir) {
  
  #i<-1
  
  #filename<-files_tbl[i,'filename']
  #yyyymm<-files_tbl[i,'yyyymm']
  
  # Parse year and month
  yr <- as.integer(substr(yyyymm, 1, 4))
  mo <- as.integer(substr(yyyymm, 5, 6))
  
  # Filter points for that year-month
  pts <- filter(filtered_points_df, year == yr, month == mo)
  
  if(nrow(pts) == 0) {
    message("No points for ", yyyymm)
    return(tibble(year = yr, month = mo, RMSE = NA_real_, Correlation = NA_real_, n_points = 0))
  }
  
  # Load raster
  r <- raster(file.path(raster_dir, filename))
  
  # Extract raster values at points
  pred_vals <- raster::extract(r, pts[, c("lon", "lat")])
  
  # Compute metrics only for points with predictions
  valid <- !is.na(pred_vals)
  obs <- pts$cells[valid]
  pred <- pred_vals[valid]
  mean_obs <- mean(obs)
  
  rmse <- sqrt(mean((obs - pred)^2))
  cor_val <- if(length(obs) > 1) cor(obs, pred) else NA_real_
  rrmse <- ifelse(mean_obs != 0, rmse / mean_obs, NA_real_)
  
  tibble(
    year = yr,
    month = mo,
    #RMSE = rmse,
    RRMSE = rrmse,
    correlation = cor_val,
    n_points = length(obs)
  )
}

# 4. Directory where rasters live
raster_dir <- (paste0(idir,'/RT severity rasters'))

# 5. Loop over all year-month raster files and compute accuracy
results2 <- files_tbl %>%
  mutate(metrics = map2(filename, yyyymm, ~evaluate_accuracy(.x, .y, filtered_points_df, raster_dir))) %>%
  unnest(metrics)
results2$clip<-TRUE

print(results2)


#accuracy obs - pred+clip bin ####

library(dplyr)
library(stringr)
library(raster)
library(purrr)
library(tidyr)

# 1. Extract yyyymm from raster filenames
file_dates <- str_extract(logsev.files1, "\\d{6}")

# 2. Create a table of filenames and their yyyymm
files_tbl1 <- tibble(filename = logsev.files1, yyyymm = file_dates, sdm = 'log')
files_tbl2 <- tibble(filename = nbsev.files1, yyyymm = file_dates, sdm = 'nb')
files_tbl<- rbind(files_tbl1,files_tbl2)

# 3. Function to calculate binary accuracy metrics for one year-month
evaluate_binary_accuracy <- function(filename, yyyymm, points_df, raster_dir, threshold = 1000) {
  
  yr <- as.integer(substr(yyyymm, 1, 4))
  mo <- as.integer(substr(yyyymm, 5, 6))
  
  # Filter points for that year-month
  pts <- filter(points_df, year == yr, month == mo)
  
  if (nrow(pts) == 0) {
    message("No points for ", yyyymm)
    return(tibble(year = yr, month = mo, Accuracy = NA_real_, Sensitivity = NA_real_, Specificity = NA_real_, Kappa = NA_real_, n_points = 0))
  }
  
  # Load raster
  r <- raster(file.path(raster_dir, filename))
  
  # Extract predicted values at points
  pred_vals <- raster::extract(r, pts[, c("lon", "lat")])
  
  # Valid indices (non-NA)
  valid <- !is.na(pred_vals)
  
  obs <- pts$cells[valid]     # Observed values — adjust if different col name
  pred <- pred_vals[valid]    # Predicted values
  
  # Convert to binary presence/absence using threshold
  obs_bin <- ifelse(obs > threshold, 1, 0)
  pred_bin <- ifelse(pred > threshold, 1, 0)
  
  # Confusion matrix components
  TP <- sum(pred_bin == 1 & obs_bin == 1)
  TN <- sum(pred_bin == 0 & obs_bin == 0)
  FP <- sum(pred_bin == 1 & obs_bin == 0)
  FN <- sum(pred_bin == 0 & obs_bin == 1)
  
  # Metrics
  Accuracy <- (TP + TN) / (TP + TN + FP + FN)
  Sensitivity <- ifelse((TP + FN) > 0, TP / (TP + FN), NA_real_)
  Specificity <- ifelse((TN + FP) > 0, TN / (TN + FP), NA_real_)
  
  # Cohen's Kappa
  total <- TP + TN + FP + FN
  po <- Accuracy
  pe <- (((TP + FP) * (TP + FN)) + ((FN + TN) * (FP + TN))) / (total^2)
  Kappa <- ifelse((1 - pe) != 0, (po - pe) / (1 - pe), NA_real_)
  
  # Calculate AUC with pROC package (only if there is variation in obs_bin)
  AUC <- NA_real_
  if(length(unique(obs_bin)) > 1) {  # Need both classes present
    roc_obj <- try(pROC::roc(obs_bin, pred, quiet = TRUE), silent = TRUE)
    if (!inherits(roc_obj, "try-error")) {
      AUC <- pROC::auc(roc_obj)[1]  # numeric value
    }
  }
  
  tibble(
    year = yr,
    month = mo,
    accuracy = Accuracy,
    sensitivity = Sensitivity,
    specificity = Specificity,
    kappa = Kappa,
    AUC = AUC,
    n_points = length(obs_bin)
  )
}

# 4. Directory where rasters live
raster_dir <- paste0(idir, '/RT severity rasters')

# 5. Loop over all year-month raster files and compute binary accuracy
results_binary2 <- files_tbl %>%
  mutate(metrics = map2(filename, yyyymm, ~evaluate_binary_accuracy(.x, .y, filtered_points_df, raster_dir))) %>%
  unnest(metrics)
results_binary2$clip<-TRUE
print(results_binary2)

#plot comparisons ####

results<-rbind(results1,results2)
results_binary<-rbind(results_binary1,results_binary2)
head(results)
head(results_binary)

library(ggplot2)
library(dplyr)

# Create a combined factor for x-axis: sdm + clip
results <- results %>%
  mutate(sdm_clip = paste0(sdm, "_", ifelse(clip, "clip", "no_clip")))

ggplot(results, aes(x = sdm_clip, y = RRMSE, fill = sdm_clip)) +
  geom_boxplot(alpha = 0.7, outlier.shape = NA) +
  labs(
    title = "RRMSE relative to observations (pred and sev relative to obs HABSOS)",
    x = "",
    y = "Relative RMSE"
  ) +
  theme_minimal() +
  theme(legend.position = "none") +
  scale_x_discrete(labels=c('log_VIIRS','log_pred','nb_VIIRS','nb_pred'))+
  scale_y_continuous(limits=c(0,20))+
  scale_fill_brewer(palette = "Set2")


results_binary <- results_binary %>%
  mutate(sdm_clip = paste0(sdm, "_", ifelse(clip, "clip", "no_clip")))

ggplot(results_binary, aes(x = sdm_clip, y = AUC, fill = sdm_clip)) +
  geom_boxplot(alpha = 0.7, outlier.shape = NA) +
  labs(
    title = "AUC relative to observations (pred and sev relative to obs HABSOS)",
    x = "SDM and Clip",
    y = "AUC"
  ) +
  theme_minimal() +
  theme(legend.position = "none") +
  scale_x_discrete(labels=c('log_VIIRS','log_pred','nb_VIIRS','nb_pred'))+
  scale_fill_brewer(palette = "Set2")



# conclusions 1 #####
# no clip is more accurate (more similar to observations)
# nb is more accurate than log

#lets see if clipping by polygon how it compares to VIIRS


#accuracy pred - pred+clip (VIIRS) pos+bin ####
for (i in yyyymm) {
  
  #i<-yyyymm[1]
  
  cat("Processing:", i, "\n")
  
  #year and month
  y <- substr(i, 1, 4)
  m <- substr(i, 5, 6)
  
  # Load predicted raster
  r_pred <- raster(paste0(idir, '/sdmTMB RT rasters/', y, m, '_predsdmTMBnb.asc'))
  
  for (r in c('HAB','FLH','VIIRS')) {
    
    #r<-'FLH'
    
    # Load severity raster
    r_sev <- raster(paste0(idir, '/RT severity rasters/', r,'/',y, m, '_RTsevnb.asc'))
    
    # Apply land mask from depth raster to exclude shallow/land pixels
    r_pred <- mask(r_pred, land_mask)
    r_sev <- mask(r_sev, land_mask)
    
    # Extract values from rasters as vectors
    pred_vals <- getValues(r_pred)
    mean_pred<-mean(pred_vals,na.rm=TRUE)
    sev_vals <- getValues(r_sev)
    
    # Remove NA pairs to compare for continuous metrics
    valid_pred_sev <- !is.na(pred_vals) & !is.na(sev_vals)
    
     # Continuous metrics for r_sev vs r_pred
    rmse_sev <- sqrt(mean((pred_vals[valid_pred_sev] - sev_vals[valid_pred_sev])^2))/mean_pred
    cor_sev <- cor(pred_vals[valid_pred_sev], sev_vals[valid_pred_sev])
    r2_sev <- cor_sev^2
    
    # Convert to binary presence/absence with threshold = 1000
    bin_threshold <- 1000
    
    pred_bin <- ifelse(pred_vals > bin_threshold, 1, 0)
    sev_bin <- ifelse(sev_vals > bin_threshold, 1, 0)
    
    # Remove NA pairs for binary metrics
    valid_bin_sev <- !is.na(pred_bin) & !is.na(sev_bin)
    
    # Binary accuracy for r_sev vs r_pred
    TP_sev <- sum(sev_bin[valid_bin_sev] == 1 & pred_bin[valid_bin_sev] == 1)
    TN_sev <- sum(sev_bin[valid_bin_sev] == 0 & pred_bin[valid_bin_sev] == 0)
    FP_sev <- sum(sev_bin[valid_bin_sev] == 1 & pred_bin[valid_bin_sev] == 0)
    FN_sev <- sum(sev_bin[valid_bin_sev] == 0 & pred_bin[valid_bin_sev] == 1)
    Accuracy_sev <- (TP_sev + TN_sev) / length(pred_bin[valid_bin_sev])
    
     # Calculate AUC for sev vs pred
    auc_sev <- tryCatch({
      roc_obj <- pROC::roc(sev_bin[valid_pred_sev], pred_vals[valid_pred_sev], quiet = TRUE)
      auc(roc_obj)
    }, error = function(e) NA_real_)
    
    # Append row to dataframe
    results_df <- bind_rows(results_df, tibble(
      yyyymm = i,
      rrmse_sev = rmse_sev,
      r2_sev = r2_sev,
      accuracy_sev = Accuracy_sev,
      auc_sev = as.numeric(auc_sev),
      n_cells_sev = sum(valid_pred_sev),
      pols=r
    ))
    
  }

}

# Combine results into a dataframe

# Reshape results_df to long format for AUC and RRMSE
results_long <- results_df %>%
  pivot_longer(
    cols = c(auc_sev, rrmse_sev),
    names_to = c("metric", "method"),
    names_sep = "_",
    values_to = "value"
  )

# Check the reshaped data (optional)
head(results_long)

# Plot boxplot for AUC
ggplot(filter(results_long, metric == "auc"), aes(x = pols, y = value, fill = pols)) +
  geom_boxplot(outlier.shape = NA) +  # no outliers shown, adjust if you want
  geom_jitter(width = 0.15, alpha = 0.5) +  # add points
  labs(title = "AUC (Polygon vs VIIRS) relative predictions", x = "Method", y = "AUC") +
  theme_minimal() +
  theme(legend.position = 'none')+
  #scale_x_discrete(labels=c('polygon','viirs'))+
  scale_fill_brewer(palette = "Set1")

# Plot boxplot for RRMSE
ggplot(filter(results_long, metric == "rrmse"), aes(x = pols, y = value, fill = pols)) +
  geom_boxplot(outlier.shape = NA) +
  geom_jitter(width = 0.15, alpha = 0.5) +
  labs(title = "RRMSE (Polygon vs VIIRS) relative predictions", x = "Method", y = "RRMSE") +
  theme_minimal() +
  scale_y_continuous(limits=c(0,10))+
  theme(legend.position = 'none')+
  #scale_x_discrete(labels=c('polygon','viirs'))+
  scale_fill_brewer(palette = "Set1")

#conclusions 2 ####
#VIIRS similar to other polygon changes on accuracy

