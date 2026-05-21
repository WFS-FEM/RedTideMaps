#' sdmTMB monthly red-tide modeling.
#'
#' Three functions:
#'   - fn.make_input_grid()      : build prediction grid from depth+excl.
#'   - fn.fit_monthly_sdmTMB()   : fit lognormal-on-positives + NB2 spatial
#'                                 models for each (year, month) with >5
#'                                 positive observations. Saves fits.
#'   - fn.predict_monthly_sdmTMB(): predict each fit onto the grid, write
#'                                  raster stacks (log + nb).
#'   - fn.plot_sdmTMB()          : two PDFs of monthly maps.
#'
#' All take explicit args. No <<- and no setwd().

set.seed(6)

# Make input grid -------------------------------------------------------

#' Build the sdmTMB prediction grid from the depth + excl templates.
#'
#' @param file_depth Path to depth ASCII for target resolution.
#' @param file_excl  Path to exclusion ASCII for target resolution (unused
#'                   here but kept in signature for symmetry with caller).
#' @return Data frame with columns Lon, Lat, depth, Area_km2.
fn.make_input_grid <- function(file_depth, file_excl = NULL) {
  depth <- raster(file_depth)
  input_grid <- as.data.frame(depth, xy = TRUE)
  names(input_grid)[1:2] <- c("Lon", "Lat")

  earth_radius_km <- 6371
  compute_area_km2 <- function(lat, res_x, res_y) {
    lat_rad <- lat * pi / 180
    cell_width_km  <- res_x * (pi / 180) * earth_radius_km * cos(lat_rad)
    cell_height_km <- res_y * (pi / 180) * earth_radius_km
    cell_width_km * cell_height_km
  }
  input_grid$Area_km2 <- mapply(compute_area_km2, input_grid$Lat,
                                res(depth)[1], res(depth)[2])
  names(input_grid)[3] <- "depth"
  input_grid
}

# Fit monthly sdmTMB models ---------------------------------------------

#' Fit monthly sdmTMB lognormal (positives only) and NB2 (all) models.
#'
#' For each (year, month) with >5 positive observations, fits two spatial
#' sdmTMB models with intercept-only formula. Writes per-month fit Rdata
#' files into `dir_om` and an evaluation matrix + prediction array into
#' `dir_sdmout`.
#'
#' Confirmation prompt: if `pred_SDMs_RT.RData` exists in `dir_sdmout`,
#' the user is asked whether to overwrite.
#'
#' @param habdata sf data frame of filtered HAB observations.
#' @param input_grid Output of fn.make_input_grid().
#' @param dir_sdmout Directory for stacks, fit_matrix, pred_array, plots.
#' @param dir_om Directory for per-month fit files. Created if missing.
#' @param styr,enyr Year range to model.
#' @return List of paths written: fits dir, fit_matrix, pred_array, pred_obs.
fn.fit_monthly_sdmTMB <- function(habdata,
                                  input_grid,
                                  dir_sdmout,
                                  dir_om = file.path(dir_sdmout, "OM_month"),
                                  styr = 1985,
                                  enyr = max(habdata$year)) {

  file_predsdm <- file.path(dir_sdmout, "pred_SDMs_RT.RData")
  if (file.exists(file_predsdm) && interactive()) {
    cat("Results already exist. Running clears the output folder.\n",
        "Run anyway? Enter 'Y' to continue, anything else to abort:\n")
    if (toupper(readline()) != "Y") stop("Aborted")
  }
  unlink(dir_sdmout, recursive = TRUE)
  dir.create(dir_sdmout, recursive = TRUE)
  dir.create(file.path(dir_sdmout, "plots"), recursive = TRUE)
  if (!dir.exists(dir_om)) dir.create(dir_om, recursive = TRUE)

  # Fit loop -----
  for (iyear in styr:enyr) {
    ydf <- subset(habdata, year == iyear)
    filt_ydf <- ydf[ydf$cells > 0, ]
    mm <- names(table(filt_ydf$month)[table(filt_ydf$month) > 5])

    for (imonth in 1:12) {
      cat(sprintf("################ %s %02d ################\n", iyear, imonth))

      if (!(imonth %in% as.numeric(mm))) next

      mdf <- subset(ydf, month == imonth)
      mdf_df <- st_drop_geometry(mdf)
      mdf_df_pos <- subset(mdf_df, cells != 0)
      names(mdf_df)[which(names(mdf_df) %in% c("X","Y"))]     <- c("lon","lat")
      names(mdf_df_pos)[which(names(mdf_df_pos) %in% c("X","Y"))] <- c("lon","lat")

      mdir <- file.path(dir_om, sprintf("%d%02d", iyear, imonth))
      if (dir.exists(mdir)) unlink(mdir, recursive = TRUE)
      dir.create(mdir, recursive = TRUE)

      max_attempts <- 2
      attempt_counter <- 0
      repeat {
        fit_sdmTMBnb <- tryCatch(
          sdmTMB(formula = cells ~ 1, data = mdf_df,
                 mesh = sdmTMB::make_mesh(mdf_df, xy_cols = c("lon","lat"), cutoff = 0.1),
                 family = nbinom2(), spatial = "on", spatiotemporal = "off"),
          error = function(e) { message("Error in fit TMB nb"); NULL })
        fit_sdmTMBlog <- tryCatch(
          sdmTMB(formula = cells ~ 1, data = mdf_df_pos,
                 mesh = sdmTMB::make_mesh(mdf_df_pos, xy_cols = c("lon","lat"), cutoff = 0.1),
                 family = lognormal(), spatial = "on", spatiotemporal = "off"),
          error = function(e) { message("Error in fit TMB log"); NULL })

        if (!is.null(fit_sdmTMBnb) | !is.null(fit_sdmTMBlog)) break
        attempt_counter <- attempt_counter + 1
        if (attempt_counter >= max_attempts) {
          message("Max attempts reached, moving on.")
          break
        }
      }

      save(fit_sdmTMBnb,  file = file.path(mdir, "fit_sdmTMBnb.RData"))
      save(fit_sdmTMBlog, file = file.path(mdir, "fit_sdmTMBlog.RData"))
      rm(fit_sdmTMBnb, fit_sdmTMBlog); gc()
    }
  }

  # Prediction + evaluation loop -----
  fit_matrix <- matrix(NA, nrow = 0, ncol = 9)
  colnames(fit_matrix) <- c("year","month","model","RRMSE","MAE","aic","aicc","nll","convergence")

  mods <- gsub(".RData", "", c("fit_sdmTMBlog.RData", "fit_sdmTMBnb.RData"))

  pred_array <- array(0,
                      dim = c(nrow(input_grid), 2 + length(mods), 12, length(styr:enyr)),
                      dimnames = list(seq_len(nrow(input_grid)),
                                      c("lon","lat", mods),
                                      month.abb,
                                      styr:enyr))

  pred_obs <- matrix(NA, nrow = 0, ncol = 5)
  colnames(pred_obs) <- c("year","month","obs","pred","mod")

  for (iyear in styr:enyr) {
    ydf <- subset(habdata, year == iyear)
    filt_ydf <- ydf[ydf$cells > 0, ]
    mm <- names(table(filt_ydf$month)[table(filt_ydf$month) > 5])

    for (imonth in 1:12) {
      cat(sprintf("################ %s %02d ################\n", iyear, imonth))

      mdir <- file.path(dir_om, sprintf("%d%02d", iyear, imonth))
      ifiles <- list.files(mdir, recursive = TRUE, full.names = TRUE,
                           pattern = "\\.RData$")

      if (imonth %in% as.numeric(mm)) {
        ifiles <- ifiles[grepl("fit_", ifiles)]
        ifiles <- ifiles[sapply(ifiles, function(x) any(sapply(mods, grepl, x)))]

        for (i in ifiles) {
          if (exists("fit")) rm(fit)

          modname <- gsub("\\.RData$", "", basename(i))
          load(i)
          fit <- get(modname)

          prediction_data <- data.frame(lon = input_grid$Lon,
                                        lat = input_grid$Lat,
                                        month = imonth)

          month_lbl <- month.abb[imonth]
          year_lbl  <- as.character(iyear)

          if (!is.null(fit)) {
            predictions <- predict(fit, newdata = prediction_data, type = "response",
                                   t_i = prediction_data$month, se_fit = FALSE)
            pred_array[, c("lon","lat", modname), month_lbl, year_lbl] <-
              cbind(prediction_data$lon, prediction_data$lat, predictions$est)

            obs_sdmTMB <- fit$response
            pred_sdmTMB <- predict(fit, type = "response")[, "est"]

            pred_obs <- rbind(pred_obs,
                              data.frame(year = iyear, month = imonth,
                                         obs = obs_sdmTMB, pred = pred_sdmTMB,
                                         mod = modname))

            rrmse <- sqrt(mean((obs_sdmTMB - pred_sdmTMB)^2)) / mean(obs_sdmTMB)
            mae   <- mean(abs(obs_sdmTMB - pred_sdmTMB))

            k_value <- length(fit$tmb_obj$par) + length(fit$tmb_obj$env$random)
            n <- nrow(fit$response)
            aic  <- AIC(fit)
            aicc <- aic + (2 * k_value * (k_value + 1)) / (n - k_value - 1)
            nll  <- fit$model$objective
            conv <- fit$model$convergence == 0

            fit_matrix <- rbind(fit_matrix,
                                c(iyear, imonth, modname, rrmse, mae, aic, aicc, nll, conv))
          } else {
            fit_matrix <- rbind(fit_matrix,
                                c(iyear, imonth, modname, NA, NA, NA, NA, NA, "no model"))
            pred_array[, c("lon","lat", modname), month_lbl, year_lbl] <-
              cbind(prediction_data$lon, prediction_data$lat,
                    rep(0, length(prediction_data$lon)))
          }
        }
      } else {
        fit_matrix <- rbind(fit_matrix,
                            c(iyear, imonth, NA, NA, NA, NA, NA, NA, "no model"))
        for (j in seq_along(mods)) {
          pred_array[, j, imonth, match(iyear, styr:enyr)] <-
            rep(0, nrow(input_grid))
        }
      }
    }
  }

  file_fitmat <- file.path(dir_sdmout, "RT_fit_matrix.RData")
  file_predarr <- file.path(dir_sdmout, "pred_SDMs_RT.RData")
  file_predobs <- file.path(dir_sdmout, "pred_obs_RT.RData")
  save(fit_matrix, file = file_fitmat)
  save(pred_array, file = file_predarr)
  save(pred_obs,   file = file_predobs)

  # Diagnostic plots ------
  .plot_fit_diagnostics(fit_matrix, dir_sdmout)

  list(fits_dir = dir_om,
       fit_matrix = file_fitmat,
       pred_array = file_predarr,
       pred_obs   = file_predobs)
}

#' Internal: convergence + RRMSE/MAE/AIC/NLL diagnostic plots.
#' @keywords internal
.plot_fit_diagnostics <- function(fit_matrix, dir_sdmout) {
  fit_matrix <- as.data.frame(fit_matrix)
  fit_matrix$convergence <- ifelse(fit_matrix$convergence == "The model is likely not converged", "FALSE",
                            ifelse(fit_matrix$convergence == "There is no evidence that the model is not converged", "TRUE",
                            ifelse(fit_matrix$convergence == "no conv", "FALSE",
                                   fit_matrix$convergence)))
  fit_matrix <- fit_matrix[fit_matrix$convergence != "no model", ]
  counts <- as.data.frame(table(fit_matrix$convergence, fit_matrix$model))
  counts$percentage <- counts$Freq / sum(counts$Freq) * 100
  colnames(counts) <- c("convergence", "model", "count", "percentage")
  counts$approach <- ifelse(grepl("VAST", counts$model), "VAST", "sdmTMB")
  counts$submodel <- gsub("fit_VAST|fit_sdmTMB", "", counts$model)
  fit_matrix$approach <- ifelse(grepl("VAST", fit_matrix$model), "VAST", "sdmTMB")
  fit_matrix$submodel <- gsub("fit_VAST|fit_sdmTMB", "", fit_matrix$model)

  d_plots <- file.path(dir_sdmout, "plots")

  png(file.path(d_plots, "sdm convergence.png"), 7, 7, units = "in", res = 300)
  print(ggplot(counts, aes(x = convergence, y = percentage, fill = convergence)) +
          geom_bar(stat = "identity") +
          labs(title = "Convergence SDM RT", x = "", y = "") +
          theme_minimal())
  dev.off()

  for (metric in c("RRMSE", "MAE", "aic", "nll")) {
    ylim <- switch(metric, RRMSE = c(0, 15), MAE = c(0, 200000),
                   aic = c(0, 10000), nll = c(0, 6000))
    fname <- file.path(d_plots, paste0("sdm ", tolower(metric), " log nb.png"))
    png(fname, 7, 7, units = "in", res = 300)
    print(ggplot(fit_matrix,
                 aes(x = interaction(approach, submodel),
                     y = as.numeric(.data[[metric]]),
                     fill = interaction(approach, submodel))) +
            geom_boxplot(outlier.shape = NA) +
            theme_bw() +
            labs(y = metric, x = "", fill = "SDM") +
            scale_y_continuous(limits = ylim))
    dev.off()
  }
  invisible(NULL)
}

# Predict monthly sdmTMB onto grid --------------------------------------

#' Rasterize the prediction array onto the depth template grid.
#'
#' @param file_sdmpred Path to pred_SDMs_RT.RData (loads `pred_array`).
#' @param file_depth Path to depth ASCII.
#' @param dir_sdmout Directory to write the two stacks into.
#' @return List with file_log, file_nb paths (without extension; .grd/.gri).
fn.predict_monthly_sdmTMB <- function(file_sdmpred, file_depth, dir_sdmout) {
  depth <- raster(file_depth)
  load(file_sdmpred)  # provides pred_array

  sdm_nb <- sdm_log <- stack()
  for (iyear in dimnames(pred_array)[[4]]) {
    for (imonth in dimnames(pred_array)[[3]]) {
      cat(sprintf("################ %s %s ################\n", iyear, imonth))

      ypred <- as.data.frame(pred_array[, , imonth, as.character(iyear)])
      r_template <- raster(extent(depth), resolution = res(depth), crs = crs(depth))
      ypred <- ypred[complete.cases(ypred[, c("lon","lat","fit_sdmTMBlog","fit_sdmTMBnb")]), ]

      if (nrow(ypred) < 2 ||
          length(unique(ypred$lon)) < 2 ||
          length(unique(ypred$lat)) < 2) {
        message("Insufficient spatial data: writing empty rasters")
        r1 <- setValues(r_template, NA)
        r2 <- setValues(r_template, NA)
      } else {
        coordinates(ypred) <- ~ lon + lat
        gridded(ypred) <- TRUE
        r1 <- rasterize(ypred, r_template, field = "fit_sdmTMBlog", fun = mean)
        r2 <- rasterize(ypred, r_template, field = "fit_sdmTMBnb",  fun = mean)
      }
      names(r1) <- names(r2) <- paste0(iyear, formatC(match(imonth, month.abb),
                                                     width = 2, flag = 0))
      sdm_log <- addLayer(sdm_log, r1)
      sdm_nb  <- addLayer(sdm_nb,  r2)
    }
  }

  rng_log <- paste0(gsub("X","", names(sdm_log)[1]), "-",
                    gsub("X","", names(sdm_log)[nlayers(sdm_log)]))
  rng_nb  <- paste0(gsub("X","", names(sdm_nb)[1]), "-",
                    gsub("X","", names(sdm_nb)[nlayers(sdm_nb)]))
  file_log <- file.path(dir_sdmout, paste0("sdmTMB_log_stack_", rng_log))
  file_nb  <- file.path(dir_sdmout, paste0("sdmTMB_nb_stack_",  rng_nb))
  writeRaster(sdm_log, file_log, overwrite = TRUE)
  writeRaster(sdm_nb,  file_nb,  overwrite = TRUE)

  list(file_log = file_log, file_nb = file_nb)
}

# Plot monthly sdmTMB maps ----------------------------------------------

#' Two PDFs of monthly raster maps (one per model).
#' @param file_log,file_nb Paths returned by fn.predict_monthly_sdmTMB().
#' @param dir_plots Directory for PDFs.
fn.plot_sdmTMB <- function(file_log, file_nb, dir_plots) {
  if (!dir.exists(dir_plots)) dir.create(dir_plots, recursive = TRUE)

  colv <- c("white","purple","blue","darkblue","cyan","green","darkgreen","yellow","orange","red","darkred")
  funpal <- colorRampPalette(colv, bias = 2)
  brks <- c(0, 1e4 - 1, seq(1e4, 4e6, 10000), 1e8)
  color <- funpal(length(brks) - 1)

  for (info in list(list(file = file_log, lbl = "log"),
                    list(file = file_nb,  lbl = "nb"))) {
    if (is.null(info$file) || !file.exists(paste0(info$file, ".grd"))) next
    stk <- stack(info$file)
    pdf(file.path(dir_plots, paste0("sdmTMB ", info$lbl, " maps.pdf")), onefile = TRUE)
    par(mfrow = c(4, 3), mar = c(1, 1, 2, 0), oma = c(2, 2, 0, 6))
    for (i in seq_len(nlayers(stk))) {
      plot(stk[[i]], main = "", breaks = brks, col = color,
           colNA = "darkgray", legend = FALSE)
      map(database = "state", region = "Florida", add = TRUE, fill = TRUE, col = "wheat")
      text(-86, 26, gsub("X", "", names(stk)[i]), cex = 1.5)
      if (substr(names(stk)[i], 6, 7) == "12") {
        par(mfrow = c(1, 1), mar = c(0, 0, 0, 0), oma = c(0, 0, 0, 1))
        image.plot(stk[[i]], legend.only = TRUE,
                   breaks = brks[-length(brks)], col = color[-1],
                   add = TRUE, legend.width = 1, legend.mar = 4,
                   legend.line = 3, legend.lab = "cells/L")
        par(mfrow = c(4, 3), mar = c(1, 1, 2, 0), oma = c(2, 2, 0, 6))
      }
    }
    dev.off()
  }
  invisible(NULL)
}
