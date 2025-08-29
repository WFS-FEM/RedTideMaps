# scripts/clip_setup.R
clip_setup <- function(wd,file.depth) {
  
  # load raster
  depth <- raster(file.depth)
  
  # create land mask
  land_mask <- calc(depth, function(x) ifelse(is.na(x) | x > 250, NA, 1))

  # load MODIS FLH stack
  flh_stack <- stack(file.path(dirname(wd), "MODIS/flh/flh_-98_-80.5_24_31_200301-20250601.gri"))
  flh_stack <- crop(flh_stack, extent(depth)) / 10
  
  # build polygons
  threshold <- 0.02
  flh_polys <- list()
  for (i in 1:nlayers(flh_stack)) {
    cat(paste0('#### ',i, ' out of ',nlayers(flh_stack),' #######\n'))
    flh.sub <- flh_stack[[i]]
    flh.sub[flh.sub >= threshold] <- 10
    flh.poly <- rasterToPolygons(flh.sub, fun = function(x) x == 10, dissolve = TRUE)
    flh.poly.sf <- st_polygonize(st_cast(st_as_sf(flh.poly), "MULTILINESTRING"))
    flh_polys[[i]] <- flh.poly.sf
    names(flh_polys)[i] <- names(flh_stack)[i]
  }
  
  # load HABSOS and build buffered hulls
  load(file.path(wd, "data/habsos_20240430_filtered.RData"))
  habyrs <- sort(unique(filtered_points_df$year[filtered_points_df$year %in% 1985:2025]))
  pol_list <- list()
  for (y in habyrs) {
    for (m in sort(unique(filtered_points_df$month[filtered_points_df$year == y]))) {
      cat(paste0('####### ', y, m, ' #######\n'))
      pts <- subset(filtered_points_df, year == y & month == m & cells != 0)
      if (nrow(pts) == 0) next
      hull <- concaveman(st_transform(pts, 32617))
      hab_pol <- st_transform(st_buffer(hull, 5000), 4326)
      pol_list[[sprintf("%d%02d", y, m)]] <- hab_pol
    }
  }
  
  return(list(flh_polys = flh_polys, pol_list = pol_list, land_mask = land_mask))
}

clip_apply <- function(wd, res, land_mask, flh_polys, pol_list, vars = c("log",'nb'), years = 1985:2025) {
  idir <- wd
  
  for (var in vars) {
    #var<-'log'
    # locate predictions
    r_pred_files <- list.files(
      path = file.path(idir, paste0(res, "min/sdm out/")),
      pattern = paste0("sdmTMB_", var, "_stack_1985.*\\.gri$"),
      full.names = TRUE
    )
    r_viirs_files <- list.files(
      path = file.path(idir, paste0(res, "min/sdm out/")),
      pattern = paste0("sdmTMB_", var, "_stack_.*viirs.gri$"),
      full.names = TRUE
    )
    
    pred.stack <- stack(r_pred_files)
    viirs.stack <- if(length(r_viirs_files)>0) stack(r_viirs_files) else NULL
    
    for (y in years) {
      for (m in 1:12) {
        #y<-1985
        #m<-9
        cat(paste0('############### ',y,m,'#############\n'))
        lyr_name <- paste0('X', sprintf("%d%02d", y, m))
        
        # polygon for this month
        p <- pol_list[[sprintf("%d%02d", y, m)]]
        
        # check prediction layer exists
        if(!lyr_name %in% names(pred.stack)) {
          cat("  - No prediction layer ", lyr_name, " - skipping\n")
          next
        }
        
        r_pred <- pred.stack[[lyr_name]]
        
        if (is.null(p)) {
          # create empty raster (all zeros) with same extent/res as prediction
          empty_raster <- r_pred
          values(empty_raster) <- 0
          
          outdir <- file.path(idir, paste0(res, "min/RT severity rasters/HAB"))
          dir.create(outdir, recursive = TRUE, showWarnings = FALSE)
          out_file <- file.path(outdir, sprintf("%d%02d_RTsev%s.asc", y, m, var))
          writeRaster(empty_raster, out_file, overwrite = TRUE)
          cat("  - No polygon, saved empty HAB raster: ", out_file, "\n")
          next
        }
        
        # transform polygon to raster CRS
        p <- st_transform(p, crs = crs(r_pred))
        mask_raster <- rasterize(p, r_pred, field = 1, background = NA)
        hab_raster <- mask(r_pred, mask_raster)
        hab_raster[is.na(hab_raster)] <- 0
        hab_raster <- mask(hab_raster, land_mask)
        
        # save HAB mask
        outdir <- file.path(idir, paste0(res, "min/RT severity rasters/HAB"))
        dir.create(outdir, recursive = TRUE, showWarnings = FALSE)
        out_file <- file.path(outdir, sprintf("%d%02d_RTsev%s.asc", y, m, var))
        writeRaster(hab_raster, out_file, overwrite = TRUE)
        cat("  -> HAB raster saved: ", out_file, "\n")
        
        # FLH mask only post-2003
        if(y >= 2003) {
          flh <- flh_polys[[lyr_name]]
          if(!is.null(flh)) {
            flh <- st_transform(flh, crs = crs(r_pred))
            flh <- st_collection_extract(flh, "POLYGON")
            flh$poly_id <- seq_len(nrow(flh))
            mask_raster <- rasterize(as(flh, "Spatial"), r_pred, field = 1, background = NA)
            flh_raster <- mask(r_pred, mask_raster)
            flh_raster[is.na(flh_raster)] <- 0
            flh_raster <- mask(flh_raster, land_mask)
            
            outdir <- file.path(idir, paste0(res, "min/RT severity rasters/FLH"))
            dir.create(outdir, recursive = TRUE, showWarnings = FALSE)
            out_file <- file.path(outdir, sprintf("%d%02d_RTsev%s.asc", y, m, var))
            writeRaster(flh_raster, out_file, overwrite = TRUE)
            cat("  -> FLH raster saved: ", out_file, "\n")
          }
        }
        
        # VIIRS mask post-2012
        if(y>=2012 && !is.null(viirs.stack) && lyr_name %in% names(viirs.stack)) {
          r_viirs <- viirs.stack[[lyr_name]]
          outdir <- file.path(idir, paste0(res, "min/RT severity rasters/VIIRS"))
          dir.create(outdir, recursive = TRUE, showWarnings = FALSE)
          out_file <- file.path(outdir, sprintf("%d%02d_RTsev%s.asc", y, m, var))
          writeRaster(r_viirs, out_file, overwrite = TRUE)
          cat("  -> VIIRS raster saved: ", out_file, "\n")
        }
      }
    }
  }
}
