#accuracy evaluation

#setwd

#observations
load('/Users/daniel/Work/WFS_DV2/WFS-FEM/ST drivers/red tides/data/processed/filtered_habsos_20240430.RData')

#list files RT sdmTMB predictions
list.files('/Users/daniel/Work/WFS_DV2/WFS-FEM/ST drivers/red tides/sdmTMB RT rasters/')

#list files RT severity (after clipping)
list.files('/Users/daniel/Work/WFS_DV2/WFS-FEM/ST drivers/red tides/sdmTMB RT rasters/')



obs       <- c(...)  # observed values
pred      <- c(...)  # predicted values before clipping
pred_clip <- c(...)  # predicted values after clipping


rmse <- function(o, p) sqrt(mean((o - p)^2))
mae  <- function(o, p) mean(abs(o - p))
r2   <- function(o, p) 1 - sum((o - p)^2) / sum((o - mean(o))^2)
bias <- function(o, p) mean(p - o)

metrics <- data.frame(
  Metric     = c("RMSE", "MAE", "R2", "Bias"),
  BeforeClip = c(rmse(obs, pred),
                 mae(obs, pred),
                 r2(obs, pred),
                 bias(obs, pred)),
  AfterClip  = c(rmse(obs, pred_clip),
                 mae(obs, pred_clip),
                 r2(obs, pred_clip),
                 bias(obs, pred_clip))
)
metrics


err_before <- abs(obs - pred)
err_after  <- abs(obs - pred_clip)

t.test(err_before, err_after, paired = TRUE)


#check if the effect between clipping with MODIS, VIIRS, polygon

#check if the effect between using NB and LOG sdmTMB

#check if thats the same when using presence
presence_threshold <- 1000  # or any threshold suitable for your case
obs_bin  <- ifelse(obs  > presence_threshold, 1, 0)
pred_bin <- ifelse(pred > presence_threshold, 1, 0)
clip_bin <- ifelse(pred_clip > presence_threshold, 1, 0)

library(caret)

eval_presence <- function(obs_bin, pred_bin) {
  cm <- confusionMatrix(
    factor(pred_bin, levels = c(0, 1)),
    factor(obs_bin, levels = c(0, 1))
  )
  cm$overall[c("Accuracy")]
  cm$byClass[c("Sensitivity", "Specificity", "Precision", "F1")]
}

presence_metrics <- data.frame(
  Metric     = c("Accuracy", "Sensitivity", "Specificity", "Precision", "F1"),
  BeforeClip = as.numeric(eval_presence(obs_bin, pred_bin)),
  AfterClip  = as.numeric(eval_presence(obs_bin, clip_bin))
)
presence_metrics


