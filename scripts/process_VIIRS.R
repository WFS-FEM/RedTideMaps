#VIIRS, severity RT rasters and plot ####
#create folder
#setwd(paste0(mydir,'/ST drivers/red tides/'))
#dir.create('./RT severity rasters/')

# #first check if clipped raster stack already exists
# results.exist = ifelse(length(list.files(dir.sdmout,pattern="clipped.grd$"))>=1,TRUE,FALSE)#  file.exists(paste0(dir.sdmout,"clipped.grd$"))
# if(results.exist){
#   cat("Clipped raster stack already exists. \nRun anyway? \nEnter 'Y' to continue, 'N' to abort:\n")
#   user_input <- readline()
#   if(toupper(user_input)!='Y'){
#     stop("Aborted")
#   }
# }

library('raster')
file.habRdat <<- list.files(dir.data, pattern="filtered.RData$")
file.viirs <<- paste0(dirname(dir.viirs),'/VIIRS_freq_raster_stack')

#setwd(dir.viirs)
fn.viirs_tifs2stack <- function(dir.viirs=dir.viirs){
#set wd and load files
#setwd(mydir)
lf<-list.files(dir.viirs,pattern = 'tif',full.names = TRUE)
#load(file = './ST drivers/red tides/data/processed/pred_obs_RT.RData') #pred_obs

viirs.stack = stack()
#loop
for (f in lf) {
  
  cat(paste0('################ ',f,' ####\n'))
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
  names(r1) = paste0("X",y,m)
  viirs.stack = addLayer(viirs.stack,r1)
}

viirs.stack <<- viirs.stack
writeRaster(viirs.stack,filename=file.viirs, overwrite=T)
}


#get VIIRS and obs values-------------------------------------------------------
fn.get_viirs_obs <- function(file.habRdat=file.habRdat, dir.sdmout=dir.sdmout, viirs.stack=viirs.stack){

load(file.habRdat) #filtered_points_df

#ensure month column is two digits
filtered_points_df$month <- sprintf("%02d", filtered_points_df$month)

viirs_obs <- data.frame()

for(i in 1:nlayers(viirs.stack)){
  #i=1
  r1 = viirs.stack[[i]]
  y=as.numeric(substr(names(viirs.stack)[i],2,5))
  m=substr(names(viirs.stack)[i],6,7)
  ivalues<-c(values(r1))
  cat(paste0('################## ',y,m,'###\n'))
   if (mean(ivalues,na.rm=TRUE)==0) {
     cat("### JUMPING -------")
     next
   }
  
  #filter by month and year obs samples
  ydf<-subset(filtered_points_df,year==y & month ==m)
  
  if (nrow(ydf)==0) {
    next
  }
  #filter rows where cells >= 1000
  #filt_ydf <- ydf[ydf$cells >= 1000, ]
  
  #coordinates
  icoords <- data.frame(lon=ydf$lon, lat=ydf$lat,cells=ydf$cells)
  
  
  #reorder points based on cells values to plot higher values on top
  icoords <- icoords[order(icoords$cells), ]
  
  #spatial coords
  coordinates(icoords) <- ~lon+lat
  
  #extract values from raster
  values <- raster::extract(r1, icoords)
  
  #append results
  nrow(icoords)
  viirs_obs<-rbind(viirs_obs,
                   data.frame(year=y,
                              month=m,
                              lon = coordinates(icoords)[,1],
                              lat = coordinates(icoords)[,2] ,
                              viirs=values,
                              obs=ydf$cells))
  
  
} 
viirs_obs <<- viirs_obs
}

#clip predictions---------------------------------------------------------------
fn.clip_2_viirs <- function(file.pred=list.files(dir.sdmout,pattern='log_stack',full.names = T)[1],
                            file.viirs=list.files(dirname(dir.viirs),pattern=".grd$",full.names=T)){
  #file.viirs=list.files(dirname(dir.viirs),pattern=".grd$",full.names=T)
  viirs<-stack(file.viirs)
  pred <- stack(file.pred)
pred.clipped = stack()

do.viirs_clip = which(names(pred) %in% names(viirs))

for(i in do.viirs_clip){
  #i=do.viirs_clip[1]
  y=substr(names(pred)[i],2,5)
  m=substr(names(pred)[i],6,7)
  ipred <- pred[[i]]
  
  r1<-viirs[[which(names(viirs)==paste0("X",y,m))]]
  ivalues<-c(values(r1))
  
  cat(paste0('################## ',y,m,'###\n'))
  if (mean(ivalues,na.rm=TRUE)==0 | nlayers(ipred)==0) {
    ipred[] = 0
    pred.clipped = addLayer(pred.clipped,ipred)
    cat("### JUMPING -------")
    next
  }
  
  #convert all 0 values to NA
  r2 <- r1
  r2[r2 == 0] <- NA
  
  #convert raster to data frame for ggplot
  raster_df <- as.data.frame(rasterToPoints(r2))
  colnames(raster_df)[ncol(raster_df)]<-'freq'
  
  #convert raster cells with values to polygons
  r2pol <- rasterToPolygons(r2, fun = function(x) !is.na(x) & x != 0, dissolve = TRUE)
  #convert to sf object
  r2pol <- st_as_sf(r2pol)
  #merge all polygons into a single polygon
  r2pol <- st_union(r2pol)
  
  #ensure r2pol is an sf object
  r2pol <- st_sf(geometry = r2pol)
  
  #assign the CRS from r2 (assuming r2 has a CRS)
  st_crs(r2pol) <- st_crs(r2)
  
  #add raster data
  #ifile<-list.files(path = mydir,pattern = paste0(y,m,'_predsdmTMBlog.asc'),recursive = TRUE)
  #r.sdmTMB1<-raster(ifile)

  # Convert raster to data frame for ggplot
  raster_cells1 <- as.data.frame(rasterToPoints(ipred))
  colnames(raster_cells1)[ncol(raster_cells1)]<-'cells'
  
  #convert RasterLayer to SpatRaster
  ipred.terra <- rast(as.matrix(ipred),crs=projection(ipred), extent=extent(ipred))
  
  #reproject polygon to match the raster CRS if needed
  r2pol <- st_transform(r2pol, crs(ipred.terra))
  
  #convert the polygon to a SpatVector object
  r2pol_vect <- vect(r2pol)
  
  #apply mask using terra package
  ipred.clipped <- mask(ipred.terra, r2pol_vect)
  
  #set values outside the polygon to zero
  ipred.clipped[is.na(ipred.clipped)] <- 0
  #plot(r.sdmTMB2_clipped)
  
  names(ipred.clipped) = paste0("X",y,m)
  pred.clipped = addLayer(pred.clipped,raster(ipred.clipped))
}
#file.clipped = paste0(dir.sdmout,"/",gsub("[0-9-]","",basename(file.pred)),gsub("X","",names(pred.clipped)[1]),"-",gsub("X","",names(pred.clipped)[nlayers(pred.clipped)]),"_clipped_viirs")
file.clipped <- paste0(dir.sdmout,
       '/',gsub("\\.grd$","",basename(file.pred)),  # remove .grd only
       #gsub("X","",names(pred.clipped)[1]), "-",
       #gsub("X","",names(pred.clipped)[nlayers(pred.clipped)]),
       "_clipped_viirs.grd"
   )
writeRaster(pred.clipped,file.clipped,overwrite=T)
return(pred.clipped)
}
  # Save as .asc file
  # writeRaster(r.sdmTMB1_clipped, 
  #             filename = paste0("./ST drivers/red tides/RT severity rasters/", y, m, "_RTsevlog.asc"), 
  #             filetype = "AAIGrid", 
  #             overwrite = TRUE)
  # 
  # # Save as .asc file
  # writeRaster(r.sdmTMB2_clipped, 
  #             filename = paste0("./ST drivers/red tides/RT severity rasters/", y, m, "_RTsevnb.asc"), 
  #             filetype = "AAIGrid", 
  #             overwrite = TRUE)

fn.plot_viirs <- function(){

#plot loop
plot_list<-list()

#create a color palette with white at the start
my_magma <- viridis::magma(100, direction = -1)
my_colors <- c("white", my_magma)
#prepare point type for shape mapping
#icoords$point_type <- ifelse(icoords$cells == 0, "Zero cell count (X)", "Sampled (O)")

#define color breaks
n_breaks <- 5
max_fill <- max(raster_cells2$cells, na.rm = TRUE)
max_color <- max(icoords$cells, na.rm = TRUE)
common_breaks <- pretty(c(0, max(max_fill, max_color)), n = n_breaks)

  
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
  p
  
  

}
#dim(viirs.stack)

#writeRaster(sdm.log.clipped,filename=paste0(dir.sdmout,'/sdmTMB_log_raster_stack_clipped'), overwrite=T)
#writeRaster(sdm.nb.clipped,filename=paste0(dir.sdmout,'/sdmTMB_nb_raster_stack_clipped'), overwrite=T)

#graphics.off();windows(record=T)
#par(mfrow=c(4,3))
#for(i in 1:length(plot_list)){
#print(plot_list[[i]])
#}

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
