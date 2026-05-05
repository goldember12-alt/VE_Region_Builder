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

backup_dir <- file.path(dirname(updated_dir), paste0("_backup_schema_year_repairs_", format(Sys.time(), "%Y%m%d_%H%M%S")))
dir_create(backup_dir)

backup_file <- function(path) {
  file_copy(path, file.path(backup_dir, basename(path)), overwrite = TRUE)
}

geo_path <- find_one("geo\\.csv$")
unprotected_path <- find_one("29_bzone_unprotected_area\\.csv$")
network_path <- find_one("25_bzone_network_design\\.csv$")
tdm_path <- find_one("28_bzone_travel_demand_management\\.csv$")
carsvc_path <- find_one("20_bzone_carsvc_availability\\.csv$")

geo <- read_chr(geo_path)
if (!"Bzone" %in% names(geo)) stop("geo.csv lacks Bzone column.")
bzones <- as.character(geo$Bzone)

message("Backup dir: ", backup_dir)

# 1. bzone_unprotected_area schema repair.
backup_file(unprotected_path)
unprotected <- read_chr(unprotected_path)

rename_if_present <- function(df, old, new) {
  if (old %in% names(df) && !(new %in% names(df))) {
    names(df)[names(df) == old] <- new
  }
  df
}

unprotected <- rename_if_present(unprotected, "GeoIDTxt", "Geo")
unprotected <- rename_if_present(unprotected, "Urban", "UrbanArea")
unprotected <- rename_if_present(unprotected, "Town", "TownArea")
unprotected <- rename_if_present(unprotected, "Rural", "RuralArea")

required_unprotected <- c("Geo", "UrbanArea", "TownArea", "RuralArea")
missing_unprotected <- setdiff(required_unprotected, names(unprotected))
if (length(missing_unprotected) > 0) {
  stop("bzone_unprotected_area still missing: ", paste(missing_unprotected, collapse = ", "))
}

write_chr(unprotected, unprotected_path)

# 2. bzone_network_design D3bp04 -> D3bpo4.
backup_file(network_path)
network <- read_chr(network_path)

if ("D3bp04" %in% names(network) && !("D3bpo4" %in% names(network))) {
  names(network)[names(network) == "D3bp04"] <- "D3bpo4"
}

if (!"D3bpo4" %in% names(network)) {
  stop("bzone_network_design still lacks D3bpo4.")
}

write_chr(network, network_path)

# Helper: duplicate missing future rows from 2024 to 2045 by Geo.
ensure_2045_from_2024 <- function(df, file_label) {
  if (!all(c("Geo", "Year") %in% names(df))) {
    stop(file_label, " must have Geo and Year columns.")
  }

  rows_2024 <- df %>% filter(Year == "2024")
  rows_2045 <- df %>% filter(Year == "2045")

  if (nrow(rows_2024) == 0) {
    stop(file_label, " has no 2024 rows to duplicate.")
  }

  missing_2045_geo <- setdiff(rows_2024$Geo, rows_2045$Geo)

  if (length(missing_2045_geo) > 0) {
    add_rows <- rows_2024 %>% filter(Geo %in% missing_2045_geo)
    add_rows$Year <- "2045"
    df <- bind_rows(df, add_rows)
  }

  df %>% arrange(Geo, Year)
}

# 3. Repair bzone_travel_demand_management Geo from geo.csv Bzone order, then ensure 2045.
backup_file(tdm_path)
tdm <- read_chr(tdm_path)

if (!all(c("Geo", "Year") %in% names(tdm))) {
  stop("bzone_travel_demand_management must have Geo and Year columns.")
}

years <- sort(unique(tdm$Year))
if (length(years) == 0) stop("bzone_travel_demand_management has no Year values.")

tdm_repaired <- list()
for (yr in years) {
  part <- tdm %>% filter(Year == yr)

  if (nrow(part) != length(bzones)) {
    stop(
      "Cannot safely repair Geo for bzone_travel_demand_management Year=", yr,
      ". Row count is ", nrow(part),
      " but geo.csv has ", length(bzones), " Bzones."
    )
  }

  part$Geo <- bzones
  tdm_repaired[[yr]] <- part
}

tdm <- bind_rows(tdm_repaired)
tdm <- ensure_2045_from_2024(tdm, "bzone_travel_demand_management")
write_chr(tdm, tdm_path)

# 4. bzone_carsvc_availability: ensure 2045 from 2024.
backup_file(carsvc_path)
carsvc <- read_chr(carsvc_path)
carsvc <- ensure_2045_from_2024(carsvc, "bzone_carsvc_availability")
write_chr(carsvc, carsvc_path)

message("")
message("Repairs complete.")
message("Unprotected columns: ", paste(names(unprotected), collapse = ", "))
message("Network columns: ", paste(names(network), collapse = ", "))
message("TDM rows: ", nrow(tdm))
message("Car service rows: ", nrow(carsvc))
message("Backup dir: ", backup_dir)
