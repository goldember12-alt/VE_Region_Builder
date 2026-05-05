library(readr)
library(dplyr)
library(fs)

updated_dir <- "C:/Users/Jameson.Clements/source/VE_Models/models/updatedcsvs"
backup_dir <- file.path(updated_dir, paste0("_backup_before_repairs_", format(Sys.time(), "%Y%m%d_%H%M%S")))
dir_create(backup_dir)

copy_with_backup <- function(path) {
  if (!file.exists(path)) stop("Missing file: ", path)
  file_copy(path, file.path(backup_dir, basename(path)), overwrite = TRUE)
}

read_chr <- function(path) {
  read_csv(path, col_types = cols(.default = col_character()), show_col_types = FALSE)
}

write_chr <- function(df, path) {
  write_csv(df, path, na = "")
}

find_one <- function(pattern) {
  hits <- dir_ls(updated_dir, recurse = TRUE, type = "file", regexp = pattern)
  if (length(hits) != 1) {
    stop("Expected exactly one file for pattern ", pattern, ", found: ", paste(hits, collapse = "; "))
  }
  hits[[1]]
}

geo_path <- find_one("geo\\.csv$")
du_path <- find_one("bzone_dwelling_units\\.csv$")
latlon_path <- find_one("bzone_lat_lon\\.csv$")
inc_path <- find_one("bzone_hh_inc_qrtl_prop\\.csv$")

message("Using:")
message("  geo:    ", geo_path)
message("  du:     ", du_path)
message("  latlon: ", latlon_path)
message("  inc:    ", inc_path)
message("Backup dir: ", backup_dir)

copy_with_backup(du_path)
copy_with_backup(latlon_path)
copy_with_backup(inc_path)

geo <- read_chr(geo_path)
if (!"Bzone" %in% names(geo)) stop("geo.csv lacks Bzone column.")
bzones <- as.character(geo$Bzone)

# 1. Fix dwelling rows with zero total units by setting SFDU to 1.
du <- read_chr(du_path)
required_du <- c("Geo", "Year", "SFDU", "MFDU", "GQDU")
missing_du <- setdiff(required_du, names(du))
if (length(missing_du) > 0) stop("bzone_dwelling_units missing columns: ", paste(missing_du, collapse = ", "))

du <- du %>%
  mutate(
    SFDU_num = suppressWarnings(as.numeric(SFDU)),
    MFDU_num = suppressWarnings(as.numeric(MFDU)),
    GQDU_num = suppressWarnings(as.numeric(GQDU)),
    total_du = coalesce(SFDU_num, 0) + coalesce(MFDU_num, 0) + coalesce(GQDU_num, 0)
  )

zero_count <- sum(du$total_du == 0, na.rm = TRUE)

du <- du %>%
  mutate(SFDU = if_else(total_du == 0, "1", as.character(SFDU))) %>%
  select(-SFDU_num, -MFDU_num, -GQDU_num, -total_du)

write_chr(du, du_path)

# 2. Duplicate 2024 lat/lon rows to 2045 if 2045 rows are missing.
latlon <- read_chr(latlon_path)
required_latlon <- c("Geo", "Year")
missing_latlon <- setdiff(required_latlon, names(latlon))
if (length(missing_latlon) > 0) stop("bzone_lat_lon missing columns: ", paste(missing_latlon, collapse = ", "))

latlon_2024 <- latlon %>% filter(Year == "2024")
latlon_2045 <- latlon %>% filter(Year == "2045")

if (nrow(latlon_2024) == 0) stop("bzone_lat_lon has no 2024 rows to duplicate.")

if (nrow(latlon_2045) == 0) {
  add_2045 <- latlon_2024
  add_2045$Year <- "2045"
  latlon <- bind_rows(latlon, add_2045)
  latlon_added <- nrow(add_2045)
} else {
  latlon_added <- 0
}

write_chr(latlon, latlon_path)

# 3. Repair bzone_hh_inc_qrtl_prop Geo values from geo.csv Bzone order.
inc <- read_chr(inc_path)
required_inc <- c("Geo", "Year")
missing_inc <- setdiff(required_inc, names(inc))
if (length(missing_inc) > 0) stop("bzone_hh_inc_qrtl_prop missing columns: ", paste(missing_inc, collapse = ", "))

years <- sort(unique(inc$Year))
if (length(years) == 0) stop("bzone_hh_inc_qrtl_prop has no Year values.")

repaired <- list()
for (yr in years) {
  part <- inc %>% filter(Year == yr)

  if (nrow(part) != length(bzones)) {
    stop(
      "Cannot safely repair Geo for bzone_hh_inc_qrtl_prop Year=", yr,
      ". Row count is ", nrow(part),
      " but geo.csv has ", length(bzones), " Bzones. ",
      "Do not rely on row order until this mismatch is understood."
    )
  }

  part$Geo <- bzones
  repaired[[yr]] <- part
}

inc <- bind_rows(repaired)
write_chr(inc, inc_path)

message("")
message("Repair complete.")
message("Zero-DU rows fixed by setting SFDU=1: ", zero_count)
message("Lat/lon 2045 rows added: ", latlon_added)
message("Income quartile rows repaired: ", nrow(inc))
message("Backup dir: ", backup_dir)
