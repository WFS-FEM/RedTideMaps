# Settings #####
#remove and empty objects
#rm(list=ls());gc()
setwd(wd)
#load libraries
library('rvest')
library('raster')
library('sf')
library('ggplot2')
library(rnaturalearth)

#create directories


#Get HAB data-------------------------------------------------------------------
#find most recent data product
fn.get_hab_data <- function(url.habsos=url.habsos, dir.data=dir.data){
directory_url <- url.habsos

# Read the HTML content of the directory
web_page <- read_html(directory_url)

# Extract the links from the directory listing
links <- web_page %>%
  html_nodes("a") %>%
  html_attr("href")

# Filter for .xml files
xml_files <- links[grepl("\\.xml$", links)]

# Print the list of .xml files
cat("List of .xml files in the directory:\n")
print(xml_files)

#get data version
data_version = substr(gsub(".xml","",tail(sort(xml_files),1)),nchar(gsub(".xml","",tail(sort(xml_files),1)))-2,nchar(gsub(".xml","",tail(sort(xml_files),1))))

# Define the URL of the file
data_url <- paste0(directory_url,data_version,"/data/0-data/")

# Read the HTML content of the directory
web_page <- read_html(data_url)

# Extract the links from the directory listing
links <- web_page %>%
  html_nodes("a") %>%
  html_attr("href")

# Filter for .xml files
csv_files <- links[grepl("\\.csv$", links)]
file.habsos <<- csv_files

# Print the list of .xml files
cat("List of .csv files in the directory:\n")
print(csv_files)

if(csv_files %in% list.files(dir.data)){
  print(paste0('File ',csv_files,' already exists in data directory.  Download aborted.'));flush.console()
} else{

# Define the URL of the file
csv_url <- paste0(data_url,csv_files)

# Define the destination file path (adjust this to your preferred location)
destination_file <- paste0(dir.data,"/",csv_files)

# Download the file
download.file(url = csv_url, destfile = destination_file, mode = "wb")

# Confirm completion
cat("File downloaded successfully to\n", destination_file, "\n")
}
#out=list(file.habsos)
return(file.habsos)
}
#@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
#Filter HAB data----
#filter, code brought over from script 03
fn.filter_hab_data <- function(file.habsos=file.habsos, file.depth=file.depth, file.excl=file.excl){
#namefile <- gsub(".csv","_filtered.RData",file.habsos)
file.habRdat <<- paste0(dir.data,"/",gsub(".csv","_filtered.RData",file.habsos))

##read habsos file----
depth <- raster(file.depth)
df <- read.csv(paste0(dir.data,"/",file.habsos))
df$SAMPLE_DATE <- as.Date(df$SAMPLE_DATE) #convert SAMPLE_DATE to Date format
df$year <- as.numeric(format(df$SAMPLE_DATE, "%Y"))
df$month <- as.numeric(format(df$SAMPLE_DATE, "%m"))
df <- df[, c("LATITUDE", "LONGITUDE", "year", "CELLCOUNT", "month")]
colnames(df) <- c("lat", "lon", "year", "cells", "month")
obs_sf <- st_as_sf(df, coords = c("lon", "lat"), crs = st_crs(depth))

##create polygons---- 
excl_depth <- raster(file.excl)
us <- ne_countries(country = "united states of america", scale = 10, returnclass = "sf")
# Remove all non-geometry columns
us <- us["geometry"]
#convert raster extent to an sf-compatible bounding box
us_bbox <- st_as_sfc(st_bbox(depth))
#crop to U.S. region using sf functions
us_cropped <- st_crop(us, us_bbox)
us_cropped <- st_cast(us_cropped, "POLYGON")

depth_extent <- st_as_sf(st_as_sfc(st_bbox(depth)))
#convert data frame to sf object
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
us_clipped_sf <- st_transform(us_clipped_sf, st_crs(depth))
us_clipped_sf <- st_make_valid(us_clipped_sf)
us_clipped_sf_polygons <<- st_cast(us_clipped_sf, "POLYGON")

#combine polygons sequentially using st_union
combined_polygons_1 <- st_union(us_clipped_sf, Ps2_sf)
all_polygons <- st_union(combined_polygons_1, excl_depth_sf)

#union of all polygons where we don't want sampling points (land, atlantic or excl cells)
all_polygons_single <- st_union(us_clipped_sf, Ps2_sf)
all_polygons_single <- st_union(all_polygons_single, excl_depth_sf)
all_polygons_single <- st_combine(all_polygons_single)
all_polygons_single <- st_cast(all_polygons_single, "POLYGON")

##filter data----
#use st_within to identify points inside polygons
inside_polygons <<- st_within(obs_sf, all_polygons_single, sparse = FALSE)

#filter points that are outside the polygons (i.e., where no intersection exists)
filtered_points_outside <- obs_sf[!apply(inside_polygons, 1, any), ]

#apply another filter based on the raster extent
raster_extent <- st_as_sfc(st_bbox(depth))
#precompute the bounding box of the raster extent
bbox_raster <- st_bbox(raster_extent)
#apply st_crop once with the precomputed bounding box
filtered_points_outside <- st_crop(filtered_points_outside, bbox_raster)
#extract coordinates and add them as columns
filtered_points_df <<- cbind(filtered_points_outside, st_coordinates(filtered_points_outside))
#rename
names(filtered_points_df)<<-c('year','cells','month','lon','lat','geometry')

##save filtered observations----
#namefile <- sub("\\.csv$", "", basename(lf[length(lf)]))
save(filtered_points_df, file = file.habRdat)

print(paste0(basename(file.habRdat), " saved to ",dir.data));flush.console()
#outlist = list(filtered_points_df, inside_polygons,us_clipped_sf_polygons)
#return(filtered_points_df)
}

#@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
#Plotting----
#create a ggplot of the filtered points and polygons
fn.plot_hab_data <- function(file.habRdat=file.habRdat){
#if(!dir.exists(dir.plots)) dir.create(dir.plots)
load(file.habRdat)
habdata=filtered_points_df
p<-
  ggplot() +
  geom_sf(data = st_as_sf(us_clipped_sf_polygons), fill = 'lightgrey', color = 'black', alpha = 0.5) +
  geom_sf(data = subset(habdata,year >= 1985), aes(geometry = geometry), color = 'blue', size = 0.5,alpha=0.5) +
  labs(#title = "Filtered RT sampling stations",
    x = "longitude",
    y = "latitude") +
  theme_minimal()+
  scale_y_continuous(breaks=c(30,28,26))+
  scale_x_continuous(breaks=c(-86,-84,-82))+
  facet_wrap((~year),ncol=8)
png(paste0(dir.data,"/sample locations by year.png"),width=12, height=10, units='in', res=300)
print(p)
dev.off()

#plot ts effort
sampling_effort<-as.data.frame(habdata)
#create a full sequence of monthly dates from Jan 1985 to the latest in the data
full_dates <- data.frame(
  date = seq(as.Date("1985-01-01"), 
             as.Date(paste(max(sampling_effort$year), 12, "01", sep = "-")), 
             by = "month")
)

#create a date column in your data
sampling_effort$date <- as.Date(paste(sampling_effort$year, sampling_effort$month, "01", sep = "-"))

# ggplot(sampling_effort, aes(x = cells)) +
#   geom_histogram(aes(y = after_stat(density)), fill = "skyblue", color = "white", bins = 30000) +
#   labs(x = "Cells", y = "Proportion", title = "Proportional Distribution of Cells") +
#   theme_minimal()

#count rows per month (using base R)
monthly_counts <- as.data.frame(table(sampling_effort$date))
colnames(monthly_counts) <- c("date", "n")
monthly_counts$date <- as.Date(monthly_counts$date)

# Merge with full date sequence to fill missing months with 0
plot_data <- merge(full_dates, monthly_counts, by = "date", all.x = TRUE)
plot_data$n[is.na(plot_data$n)] <- 0

#plot
png(paste0(dir.data,"/N samples over time.png"),width=7, height=7, units='in', res=300)
print(
ggplot(plot_data, aes(x = date, y = n)) +
  geom_line() +
  labs(x = "time", y = "n samples") +
  theme_minimal())
dev.off()
}
#Cleanup----
#rm(list=setdiff(ls(),c('wd','dir.data','dir.plots','file.depth','file.excl','file.habsos','file.habRdat','url.habsos',
#                       'inside_polygons','us_clipped_sf_polygons','dir.viirs','dir.sdmout')));gc()  #cleanup


