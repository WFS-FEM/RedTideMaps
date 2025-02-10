# Settings #####
#remove and empty objects
rm(list=ls());gc()

#load libraries
library('rvest')

#set directory based on user and OS
if (Sys.info()['user']=='daniel') {
  #mydir<-'/Users/daniel/Work/VAST_DC/'
  mydir<-'/Users/daniel/Work/WFS_DV2/WFS-FEM/'
  setwd(mydir)
} else {
  if (.Platform$OS.type == "windows") {setwd(choose.dir())} else {setwd(tcltk::tk_choose.dir())}
}

#create dir
dir.create('./ST drivers/red tides/data/raw')
setwd('./ST drivers/red tides/data/raw')

# get HAB data #####
#find most recent data product
directory_url <- "https://www.ncei.noaa.gov/data/oceans/archive/arc0069/0120767/"

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

# Print the list of .xml files
cat("List of .csv files in the directory:\n")
print(csv_files)

# Define the URL of the file
csv_url <- paste0(data_url,csv_files)

# Define the destination file path (adjust this to your preferred location)
destination_file <- csv_files

# Download the file
download.file(url = csv_url, destfile = destination_file, mode = "wb")

# Confirm completion
cat("File downloaded successfully to", destination_file, "\n")
