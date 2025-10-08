library('concaveman')
library('maps')
library('fields')
library('raster')
library('cluster')
library('segmented')


# scripts/clip_setup.R
fn.buffered_hulls <- function(file.habRdata=file.habRdat.filtered){
  load(file.habRdata)
  #habyrs <- sort(unique(filtered_points_df$year[filtered_points_df$year %in% 1985:2024]))
  habyrs <- sort(unique(filtered_points_df$year))
  depth <- raster(file.depth)
  land_mask <- calc(depth, function(x) ifelse(is.na(x), NA, 1))
  pol_list <- list()
  pts.utm = st_transform(filtered_points_df, 32617)
  
  for (y in habyrs) {
    for (m in sort(unique(filtered_points_df$month[filtered_points_df$year == y]))) {
      #y=2024;m=12
      cat(paste0('####### ', y, m, ' #######\n'))
      pts.ym <- subset(pts.utm, year == y & month == m & cells != 0)
      coords <- st_coordinates(pts.ym)
      #jitter lon/lat to remove duplicates
      dups <- duplicated(coords) | duplicated(coords, fromLast = TRUE)
      if(sum(dups)>1){
        coords_jittered <- coords
        coords_jittered[dups, ] <- coords[dups, ] * matrix(1+runif(sum(dups)*2, -1, 1)/1e6,ncol=2)
        cbind(coords[dups,],coords_jittered[dups,])
        # Create new geometry column
        new_geom <- st_sfc(lapply(1:nrow(coords_jittered), function(i) st_point(coords_jittered[i, ])), crs = 32617)
        
        # Replace geometry in original sf object
        pts.ym2 <- pts.ym
        st_geometry(pts.ym2) <- new_geom
        
      } else{
        pts.ym2=pts.ym
      }
      if (nrow(pts.ym2) < 4) next
      
      #identify number of polygons to create
      coords = st_coordinates(pts.ym2)
      wss <- sil_width <- numeric()
      for (k in 1:min(10,nrow(coords)/4)) {
        ktest <- kmeans(coords, centers = k)
        wss[k] <- ktest$tot.withinss
      }
      # x=1:length(wss)
      # lm_model <- lm(wss~x)
      # seg_model <- segmented(lm_model, seg.Z=~x, quant=T)
      # summary(seg_model)
      # ceiling(seg_model$psi[2])
      # ncenters = ceiling(seg_model$psi[2])
      ncenters = which.max(abs(diff(wss)))+1
      if(length(ncenters)!=0){
        kmeans_result <- kmeans(coords, centers=ncenters)
        pts.ym2$group <- as.factor(kmeans_result$cluster)
        if(min(table(pts.ym2$group))>=4){
          # Create polygons for each group
          polygons <- lapply(split(pts.ym2, pts.ym2$group), function(group_points) {
            hull <- concaveman(group_points)
            hull <- st_transform(st_buffer(hull, 10000), 4326)
            return(hull)})
          hab_pol <- do.call(rbind, polygons)
      }} else{
        hull <- concaveman(pts.ym2, concavity=1)
        hab_pol <- st_transform(st_buffer(hull, 10000), 4326)
      }
      plot(hab_pol)
      pol_list[[sprintf("%d%02d", y, m)]] <- hab_pol
    }
  }
  file.hullpolys <<- file.path(dir.sdmout,gsub("_filtered","_hullpolys",basename(file.habRdata)))
  save(pol_list, file=file.hullpolys, replace=T)
  return(list(pol_list=pol_list, land_mask = land_mask))
}

fn.clip_2_hulls <- function(file.pred=file.pred,file.polys=file.hullpolys){
  # create land mask
  depth <- raster(file.depth)
  land_mask <- calc(depth, function(x) ifelse(is.na(x), NA, 1))  
  load(file.polys)
  polys <- pol_list
  pred.stack <- stack(file.pred)

  pred.clipped = stack()
  for(i in 1:nlayers(pred.stack)){
    #i=355
    yrmo = gsub("X","",names(pred.stack)[i])
    print(yrmo);flush.console()
    if(yrmo %in% names(polys)){
      p = polys[[which(names(polys)==yrmo)]]
      r = pred.stack[[i]]
      
      p <- st_transform(p, crs = crs(r))
      mask_raster <- rasterize(p, r, field = 1, background = NA)
      hab_raster <- mask(r, mask_raster)
      hab_raster[is.na(hab_raster)] <- 0
      hab_raster <- mask(hab_raster, land_mask)
    } else{
      hab_raster <- depth 
      names(hab_raster) = names(pred.stack)[i]
      hab_raster[!is.na(depth)] <- 0
    }
    names(hab_raster) = names(pred.stack)[i]
    #plot(hab_raster)
    pred.clipped = addLayer(pred.clipped, hab_raster)
  }
 # par(mfrow=c(4,3),mar=c(2,2,1,1)) 
 # for(n in 1:nlayers(clipped.stack)){
 #   plot(clipped.stack[[n]], colNA='gray')
 # }
  names(pred.clipped)
  writeRaster(pred.clipped, gsub(".grd","_clipped_hull",file.pred), overwrite=T)
  return(pred.clipped)  
}

clip_setup <- function(wd,file.depth,file.habRdat) {
  #file.depth = file.depth
  #file.habRdat = file.habRdat.filtered
  # load raster
  depth <- raster(file.depth)
  
  # create land mask
  land_mask <- calc(depth, function(x) ifelse(is.na(x) | x > 250, NA, 1))

  # load MODIS FLH stack
  # find the MODIS FLH stack automatically
  f.flh <- list.files(
    file.path(dir.modis.raw),
    pattern = "flh_.*\\.gri$",
    full.names = TRUE)
  flh_stack <- stack(f.flh[length(f.flh)])
  flh_stack <- crop(flh_stack, extent(depth)) / 10
  
  # build polygons
  # threshold <- 0.02
  # flh_polys <- list()
  # for (i in 1:nlayers(flh_stack)) {
  #   cat(paste0('#### ',i, ' out of ',nlayers(flh_stack),' #######\n'))
  #   flh.sub <- flh_stack[[i]]
  #   flh.sub[flh.sub >= threshold] <- 10
  #   flh.poly <- rasterToPolygons(flh.sub, fun = function(x) x == 10, dissolve = TRUE)
  #   flh.poly.sf <- st_polygonize(st_cast(st_as_sf(flh.poly), "MULTILINESTRING"))
  #   flh_polys[[i]] <- flh.poly.sf
  #   names(flh_polys)[i] <- names(flh_stack)[i]
  # }
  load(list.files(dir.modis,"^FLH polys",full.names = T))
  
  # load HABSOS and build buffered hulls
  load(file.habRdat)
  #habyrs <- sort(unique(filtered_points_df$year[filtered_points_df$year %in% 1985:2024]))
  habyrs <- sort(unique(filtered_points_df$year))
  pol_list <- list()
  for (y in habyrs) {
    for (m in sort(unique(filtered_points_df$month[filtered_points_df$year == y]))) {
      cat(paste0('####### ', y, m, ' #######\n'))
      pts <- subset(filtered_points_df, year == y & month == m & cells != 0)
      pts.utm <- st_transform(pts, 32617)
      coords <- st_coordinates(pts.utm)
      dups <- duplicated(coords) | duplicated(coords, fromLast = TRUE)
      if(sum(dups)>1){
        coords_jittered <- coords
        coords_jittered[dups, ] <- coords[dups, ] * matrix(1+runif(sum(dups)*2, -1, 1)/1e3,ncol=2)
        
        # Create new geometry column
        new_geom <- st_sfc(lapply(1:nrow(coords_jittered), function(i) st_point(coords_jittered[i, ])), crs = 32617)
        
        # Replace geometry in original sf object
        pts.utm2 <- pts.utm
        st_geometry(pts.utm2) <- new_geom
        
      } else{
          pts.utm2=pts.utm
      }
      
      if (nrow(pts.utm2) < 4) next
      hull <- concaveman(pts.utm2)
      hab_pol <- st_transform(st_buffer(hull, 5000), 4326)
      pol_list[[sprintf("%d%02d", y, m)]] <- hab_pol
    }
  }
  
  return(list(flh_polys = flh.polys, pol_list = pol_list, land_mask = land_mask))
}


make_redtide_ascii <- function(dir.pred=dir.sdmout, dir.out=dir.stdriver.out, var='log') {

  r_hull_files <- list.files(dir.pred, pattern=paste0("^sdmTMB_", var,".*\\hull.gri$"),full.names = TRUE)
  r_viirs_files <- list.files(dir.pred, pattern=paste0("^sdmTMB_", var,".*\\viirs.gri$"),full.names = TRUE)
  r_modis_files <- list.files(dir.pred, pattern=paste0("^sdmTMB_", var,".*\\modis.gri$"),full.names = TRUE)
  
  hull.stack <-  if(length(r_hull_files)>0) stack(gsub(".gri","",r_hull_files)) else stack()
  viirs.stack <- if(length(r_viirs_files)>0) stack(gsub(".gri","",r_viirs_files)) else stack()
  modis.stack <- if(length(r_modis_files)>0) stack(gsub(".gri","",r_modis_files)) else stack()
    
  clip.source <- data.frame(yrmo = sort(unique(c(names(hull.stack),names(viirs.stack),names(modis.stack)))))
  clip.source$pred <- ifelse(clip.source$yrmo %in% names(hull.stack), TRUE, FALSE)
  clip.source$viirs <- ifelse(clip.source$yrmo %in% names(viirs.stack), TRUE, FALSE)
  clip.source$modis <- ifelse(clip.source$yrmo %in% names(modis.stack), TRUE, FALSE)
  clip.source$use <- ifelse(clip.source$viirs,'viirs',ifelse(clip.source$modis,'modis','pred'))
  write.csv(clip.source, file.path(dir.sdmout,'clipping source.csv'),row.names=F)
    
  full.stack = stack()
  for(i in 1:nrow(clip.source)){
    #i=249
    yrmo.i = clip.source$yrmo[i]
    print(yrmo.i);flush.console()
    source.i = clip.source$use[i]
    
    y=as.numeric(substr(yrmo.i,2,5))
    m=as.numeric(substr(yrmo.i,6,7))
    
    if(source.i=='pred') raster.i = hull.stack[[which(names(hull.stack)==yrmo.i)]]
    if(source.i=='modis') raster.i = modis.stack[[which(names(modis.stack)==yrmo.i)]]
    if(source.i=='viirs') raster.i = viirs.stack[[which(names(viirs.stack)==yrmo.i)]]
    
    raster.i[is.na(raster.i)] = 0
    raster.i[is.na(depth)] = NA
    
    full.stack = addLayer(full.stack,raster.i)
  }
  print('saving rasters and acii files');flush.console()
  writeRaster(full.stack, filename=gsub(".gri","",gsub("hull","combined",r_hull_files)),overwrite=T)
  writeRaster(full.stack, filename=paste0(dir.out,"/sdmTMB_log_"), bylayer=T, suffix=gsub("X","",names(full.stack)), format='ascii', overwrite=T)
}

fn.plot_redtide_stack <- function(file.stack=file.pred){
  #file.stack = gsub(".gri","",list.files(dir.sdmout, pattern='combined.gri', full.names=T))
  habstack = stack(file.stack)
  
  colv <- c("white", "purple", "blue", "darkblue", "cyan", "green", "darkgreen", "yellow", "orange", "red", "darkred")
  funpal <- colorRampPalette(colv, bias = 2)
  brks <-c(0, 1e4 - 1, seq(1e4, 4e6, 10000), 1e8)
  nbcols <- length(brks) -1
  color <- funpal(nbcols)
  
  file.pdf = paste0(dirname(file.stack),'/plots/',basename(file.stack),".pdf")
  pdf(file.pdf,onefile=T)
  par(mfrow=c(4,3),mar=c(1,1,2,0),oma=c(2,2,0,6))
  for(i in 1:nlayers(habstack)){
    hab.i = habstack[[i]]
    name.i = names(habstack)[i]
    plot(hab.i, main="", breaks=brks, col=color, colNA='darkgray', legend=F)
    map(database='state',region='Florida',add=T,fill=T,col='wheat')
    text(-86,26,gsub("X","",name.i),cex=1.5)
    if(substr(name.i,6,7)=='12'){
      par(mfrow=c(1,1),mar=c(0,0,0,0),oma=c(0,0,0,1))
      image.plot(hab.i,legend.only=T,breaks=brks[-length(brks)],col=color[-1],add=T,legend.width=1,legend.mar=4,legend.line=3,
                 legend.lab = 'cells/L')
      par(mfrow=c(4,3),mar=c(1,1,2,0),oma=c(2,2,0,6))
      
    }
    if(i==nlayers(habstack)) dev.off()
  }
  print(paste0('pdf file saved at: ',file.pdf));flush.console()
}




clip_apply <- function(wd, res, land_mask, flh_polys, pol_list, vars = c("log",'nb')[1], years = 1985:2025) {
  idir <- wd

  # wd = wd;
  # res = res;
  # land_mask = clip_objects$land_mask;
  # flh_polys = clip_objects$flh_polys;
  # pol_list = clip_objects$pol_list;
  # years = 1985:2025
  # vars = c("log",'nb')[1]
  
  for (var in vars) {
    #var<-'log'
    # locate predictions
    r_pred_files <- list.files(
      path = file.path(idir, paste0(res, "min/sdm out/")),
      pattern = paste0("^sdmTMB_", var,".*\\.gri$"),
      full.names = TRUE
    )
    
    r_viirs_files <- list.files(
      path = file.path(idir, paste0(res, "min/sdm out/")),
      pattern = paste0("^sdmTMB_", var, ".*clipped_viirs\\.gri$"),
      full.names = TRUE
    )
    
    r_modis_files <- list.files(
      path = file.path(idir, paste0(res, "min/sdm out/")),
      pattern = paste0("^sdmTMB_", var, ".*clipped_modis\\.gri$"),
      full.names = TRUE
    )
    
    r_pred_files <- gsub(".gri","",r_pred_files[!grepl("_clipped", r_pred_files)])
    pred.stack <- stack(r_pred_files)
    viirs.stack <- if(length(r_viirs_files)>0) stack(gsub(".gri","",r_viirs_files)) else stack()
    modis.stack <- if(length(r_modis_files)>0) stack(gsub(".gri","",r_modis_files)) else stack()
    
    for (y in years) {
      for (m in 1:12) {
        
        cat(paste0('############### ',sprintf("%d%02d", y, m),'#############\n'))
        lyr_name <- paste0('X', sprintf("%d%02d", y, m))
        # check prediction layer exists
        
        if(!lyr_name %in% names(pred.stack)) {
          cat("  - No prediction layer ", lyr_name, " - skipping\n")
          next
        }

        
        r_pred <- pred.stack[[lyr_name]]
        
        if (is.null(p) |  all(is.na(values(r_pred)))) {
          # create empty raster (all zeros) with same extent/res as prediction
          empty_raster <- r_pred
          values(empty_raster) <- 0
          
          outdir <- file.path(idir, paste0(res, "min/RT severity rasters/HAB"))
          dir.create(outdir, recursive = TRUE, showWarnings = FALSE)
          out_file <- file.path(outdir, sprintf("%d%02d_RTsev%s.asc", y, m, var))
          writeRaster(empty_raster, out_file, overwrite = TRUE)
          cat("  - No polygon, saved empty HAB raster: ", out_file, "\n")
          
        } else {
          
          # transform polygon to raster CRS
          p <- st_transform(p, crs = crs(r_pred))
          mask_raster <- rasterize(p, r_pred, field = 1, background = NA)
          hab_raster <- mask(r_pred, mask_raster)
          hab_raster[is.na(hab_raster)] <- 0
          hab_raster <- mask(hab_raster, land_mask)
          
          # save HAB mask
          outdir <- file.path(idir, paste0(res, "min/RT severity rasters"))
          dir.create(outdir, recursive = TRUE, showWarnings = FALSE)
          out_file <- file.path(outdir, sprintf("%d%02d_RTsev%s.asc", y, m, var))
          writeRaster(hab_raster, out_file, overwrite = TRUE)
          cat("  -> HAB raster saved: ", out_file, "\n")
          }
        
        
        
        
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
        if(y>=2012 && !is.null(viirs.stack)) {
          
          if(all(is.na(values(r_pred)))) {
          
            # create empty raster (all zeros) with same extent/res as prediction
            empty_raster <- r_pred
            values(empty_raster) <- 0
            r_pred<- empty_raster
          }
          
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

