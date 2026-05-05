library(readr)
library(dplyr)
library(fs)

updated_dir <- "C:/Users/Jameson.Clements/source/VE_Models/models/updatedcsvs"

read_chr <- function(path) {
  read_csv(path, col_types = cols(.default = col_character()), show_col_types = FALSE)
}

write_chr <- function(df, path) {
  write_csv(df, path, na = "")
}

find_one <- function(pattern) {
  hits <- dir_ls(updated_dir, recurse = TRUE, type = "file", regexp = pattern)
  hits <- hits[!grepl("_backup", hits, ignore.case = TRUE)]
  if (length(hits) != 1) {
    stop("Expected exactly one file for pattern ", pattern, ", found: ", paste(hits, collapse = "; "))
  }
  hits[[1]]
}

latlon_path <- find_one("bzone_lat_lon\\.csv$")

backup_dir <- file.path(dirname(updated_dir), paste0("_backup_latlon_repair_", format(Sys.time(), "%Y%m%d_%H%M%S")))
dir_create(backup_dir)
file_copy(latlon_path, file.path(backup_dir, basename(latlon_path)), overwrite = TRUE)

latlon <- read_chr(latlon_path)

if (!all(c("Geo", "Year") %in% names(latlon))) {
  stop("bzone_lat_lon.csv must have Geo and Year columns.")
}

rows_2024 <- latlon %>% filter(Year == "2024")
rows_2045 <- latlon %>% filter(Year == "2045")

missing_2045_geo <- setdiff(rows_2024$Geo, rows_2045$Geo)

message("2024 rows: ", nrow(rows_2024))
message("Existing 2045 rows: ", nrow(rows_2045))
message("Missing 2045 Bzones: ", length(missing_2045_geo))

if (length(missing_2045_geo) > 0) {
  add_rows <- rows_2024 %>%
    filter(Geo %in% missing_2045_geo)

  add_rows$Year <- "2045"

  latlon <- bind_rows(latlon, add_rows) %>%
    arrange(Geo, Year)

  write_chr(latlon, latlon_path)
  message("Added 2045 rows: ", nrow(add_rows))
} else {
  message("No missing 2045 rows to add.")
}

message("Backup written to: ", backup_dir)
