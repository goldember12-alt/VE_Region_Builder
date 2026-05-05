#!/usr/bin/env Rscript

required_packages <- c("readr", "dplyr", "fs", "tibble")
missing_packages <- required_packages[!vapply(required_packages, requireNamespace, logical(1), quietly = TRUE)]
if (length(missing_packages) > 0) {
  stop("Missing required R packages: ", paste(missing_packages, collapse = ", "), call. = FALSE)
}

library(readr)
library(dplyr)
library(fs)

args <- commandArgs(trailingOnly = TRUE)
updated_dir <- if (length(args) >= 1) {
  args[[1]]
} else {
  "C:/Users/Jameson.Clements/source/VE_Models/models/updatedcsvs"
}
updated_dir <- normalizePath(updated_dir, winslash = "/", mustWork = TRUE)

timestamp <- format(Sys.time(), "%Y%m%d_%H%M%S")
backup_dir <- file.path(dirname(updated_dir), paste0("_backup_prepare_updatedcsvs_va_inputs_", timestamp))

summary_rows <- list()

add_summary <- function(file, action, detail) {
  summary_rows[[length(summary_rows) + 1]] <<- tibble::tibble(
    file = file,
    action = action,
    detail = detail
  )
}

read_chr <- function(path) {
  readr::read_csv(
    path,
    col_types = readr::cols(.default = readr::col_character()),
    show_col_types = FALSE,
    progress = FALSE
  )
}

write_chr <- function(data, path) {
  readr::write_csv(data, path, na = "")
}

find_one_file <- function(file_name) {
  hits <- list.files(updated_dir, recursive = TRUE, full.names = TRUE, all.files = FALSE)
  hits <- hits[file.info(hits)$isdir == FALSE]
  hits <- hits[basename(hits) == file_name]
  if (length(hits) != 1) {
    stop(
      "Expected exactly one updatedcsvs file named ",
      file_name,
      ", found ",
      length(hits),
      ": ",
      paste(hits, collapse = " | "),
      call. = FALSE
    )
  }
  normalizePath(hits[[1]], winslash = "/", mustWork = TRUE)
}

ensure_backup_dir <- function() {
  if (!dir.exists(backup_dir)) {
    fs::dir_create(backup_dir)
  }
}

backup_file <- function(path) {
  ensure_backup_dir()
  relative <- fs::path_rel(path, start = updated_dir)
  destination <- file.path(backup_dir, relative)
  fs::dir_create(dirname(destination))
  fs::file_copy(path, destination, overwrite = TRUE)
}

write_if_changed <- function(original, repaired, path, label) {
  if (!identical(original, repaired)) {
    backup_file(path)
    write_chr(repaired, path)
    add_summary(label, "updated", paste("Backup written under", backup_dir))
  } else {
    add_summary(label, "unchanged", "No repair needed.")
  }
}

rename_if_present <- function(data, old_column, new_column) {
  if (old_column %in% names(data) && !(new_column %in% names(data))) {
    names(data)[names(data) == old_column] <- new_column
  }
  data
}

require_columns <- function(data, columns, label) {
  missing_columns <- setdiff(columns, names(data))
  if (length(missing_columns) > 0) {
    stop(label, " missing required columns: ", paste(missing_columns, collapse = ", "), call. = FALSE)
  }
}

fail_on_duplicate_year_geo <- function(data, label) {
  duplicate_keys <- data %>%
    count(Year, Geo, name = "n") %>%
    filter(n > 1)
  if (nrow(duplicate_keys) > 0) {
    stop(label, " has duplicate Year/Geo rows.", call. = FALSE)
  }
}

drop_embedded_header_rows <- function(data, label) {
  if (!all(c("Geo", "Year") %in% names(data))) {
    return(data)
  }
  embedded_header <- data$Geo == "Geo" | data$Year == "Year"
  embedded_header[is.na(embedded_header)] <- FALSE
  if (any(embedded_header)) {
    add_summary(label, "repaired", paste("Dropped embedded header rows:", sum(embedded_header)))
    data <- data[!embedded_header, ]
  }
  data
}

ensure_2045_from_2024 <- function(data, label) {
  require_columns(data, c("Geo", "Year"), label)
  data <- drop_embedded_header_rows(data, label)

  rows_2024 <- data %>% filter(Year == "2024")
  rows_2045 <- data %>% filter(Year == "2045")
  if (nrow(rows_2024) == 0) {
    stop(label, " has no 2024 rows to duplicate.", call. = FALSE)
  }
  duplicate_2024 <- rows_2024 %>% count(Geo, name = "n") %>% filter(n > 1)
  if (nrow(duplicate_2024) > 0) {
    stop(label, " has duplicate 2024 Geo rows.", call. = FALSE)
  }

  missing_2045_geo <- setdiff(rows_2024$Geo, rows_2045$Geo)
  duplicate_2045 <- rows_2045 %>% count(Geo, name = "n") %>% filter(n > 1)
  invalid_2045_geo <- scientific_notation(rows_2045$Geo) | !nzchar(trimws(rows_2045$Geo))
  invalid_2045_geo[is.na(invalid_2045_geo)] <- TRUE

  if (length(missing_2045_geo) == 0 && nrow(duplicate_2045) == 0 && !any(invalid_2045_geo)) {
    return(data %>% arrange(Geo, Year))
  }

  add_rows <- rows_2024
  add_rows$Year <- "2045"
  add_summary(
    label,
    "repaired",
    paste(
      "Rebuilt 2045 rows from 2024 rows; missing Geo count:",
      length(missing_2045_geo),
      "duplicate 2045 Geo count:",
      nrow(duplicate_2045),
      "invalid 2045 Geo rows:",
      sum(invalid_2045_geo)
    )
  )

  bind_rows(data %>% filter(Year != "2045"), add_rows) %>% arrange(Geo, Year)
}

repair_geo_from_bzone_order_by_year <- function(data, bzones, label) {
  require_columns(data, c("Geo", "Year"), label)
  years <- sort(unique(data$Year))
  if (length(years) == 0) {
    stop(label, " has no Year values.", call. = FALSE)
  }

  repaired <- list()
  for (year in years) {
    part <- data %>% filter(Year == year)
    if (nrow(part) != length(bzones)) {
      stop(
        "Cannot safely repair Geo for ",
        label,
        " Year=",
        year,
        ". Row count is ",
        nrow(part),
        " but geo.csv has ",
        length(bzones),
        " Bzones.",
        call. = FALSE
      )
    }
    part$Geo <- bzones
    repaired[[year]] <- part
  }

  bind_rows(repaired)
}

scientific_notation <- function(values) {
  grepl("^[+-]?[0-9]+(\\.[0-9]+)?[eE][+-]?[0-9]+$", trimws(values))
}

validate_no_backup_dirs_under_updatedcsvs <- function() {
  dirs <- list.dirs(updated_dir, recursive = TRUE, full.names = TRUE)
  backup_dirs <- dirs[grepl("backup|bak", basename(dirs), ignore.case = TRUE)]
  if (length(backup_dirs) > 0) {
    stop(
      "Backup folders must not exist under updatedcsvs: ",
      paste(backup_dirs, collapse = " | "),
      call. = FALSE
    )
  }
}

validate_year_coverage <- function(data, label, years = c("2024", "2045")) {
  require_columns(data, c("Geo", "Year"), label)
  missing_years <- setdiff(years, unique(data$Year))
  if (length(missing_years) > 0) {
    stop(label, " missing required years: ", paste(missing_years, collapse = ", "), call. = FALSE)
  }

  rows_2024 <- data %>% filter(Year == "2024")
  rows_2045 <- data %>% filter(Year == "2045")
  missing_2045_geo <- setdiff(rows_2024$Geo, rows_2045$Geo)
  if (length(missing_2045_geo) > 0) {
    stop(label, " still has 2024 Geo values without 2045 rows.", call. = FALSE)
  }
}

validate_bzone_geo_values <- function() {
  bzone_files <- list.files(updated_dir, pattern = "bzone.*\\.csv$", recursive = TRUE, full.names = TRUE, ignore.case = TRUE)
  for (path in bzone_files) {
    data <- read_chr(path)
    if ("Geo" %in% names(data) && any(scientific_notation(data$Geo))) {
      stop("Scientific-notation Geo values remain in ", basename(path), ".", call. = FALSE)
    }
  }
}

validate_deflators <- function(path) {
  data <- read_chr(path)
  require_columns(data, c("Year", "Value"), "deflators.csv")
  if (!"2024" %in% trimws(data$Year)) {
    stop("deflators.csv does not include required deflator year 2024.", call. = FALSE)
  }
}

validate_preconditions <- function() {
  validate_no_backup_dirs_under_updatedcsvs()
  expected_files <- c(
    "geo.csv",
    "deflators.csv",
    "20_bzone_carsvc_availability.csv",
    "21_bzone_dwelling_units.csv",
    "23_bzone_hh_inc_qrtl_prop.csv",
    "24_bzone_lat_lon.csv",
    "25_bzone_network_design.csv",
    "28_bzone_travel_demand_management.csv",
    "29_bzone_unprotected_area.csv"
  )
  invisible(vapply(expected_files, find_one_file, character(1)))
}

validate_preconditions()

geo_path <- find_one_file("geo.csv")
deflators_path <- find_one_file("deflators.csv")
carsvc_path <- find_one_file("20_bzone_carsvc_availability.csv")
du_path <- find_one_file("21_bzone_dwelling_units.csv")
inc_path <- find_one_file("23_bzone_hh_inc_qrtl_prop.csv")
latlon_path <- find_one_file("24_bzone_lat_lon.csv")
network_path <- find_one_file("25_bzone_network_design.csv")
tdm_path <- find_one_file("28_bzone_travel_demand_management.csv")
unprotected_path <- find_one_file("29_bzone_unprotected_area.csv")

geo <- read_chr(geo_path)
require_columns(geo, "Bzone", "geo.csv")
bzones <- as.character(geo$Bzone)
if (any(!nzchar(trimws(bzones)))) {
  stop("geo.csv contains blank Bzone values.", call. = FALSE)
}

du <- read_chr(du_path)
du_original <- du
require_columns(du, c("Geo", "Year", "SFDU", "MFDU", "GQDU"), "bzone_dwelling_units.csv")
du_totals <- suppressWarnings(as.numeric(du$SFDU)) +
  suppressWarnings(as.numeric(du$MFDU)) +
  suppressWarnings(as.numeric(du$GQDU))
zero_du <- is.na(du_totals) | du_totals == 0
du$SFDU[zero_du] <- "1"
write_if_changed(du_original, du, du_path, "21_bzone_dwelling_units.csv")
add_summary("21_bzone_dwelling_units.csv", "validated", paste("Zero-DU rows set to SFDU=1:", sum(zero_du)))

inc <- read_chr(inc_path)
inc_original <- inc
inc <- repair_geo_from_bzone_order_by_year(inc, bzones, "bzone_hh_inc_qrtl_prop.csv")
write_if_changed(inc_original, inc, inc_path, "23_bzone_hh_inc_qrtl_prop.csv")

latlon <- read_chr(latlon_path)
latlon_original <- latlon
latlon <- ensure_2045_from_2024(latlon, "bzone_lat_lon.csv")
write_if_changed(latlon_original, latlon, latlon_path, "24_bzone_lat_lon.csv")

unprotected <- read_chr(unprotected_path)
unprotected_original <- unprotected
unprotected <- rename_if_present(unprotected, "GeoIDTxt", "Geo")
unprotected <- rename_if_present(unprotected, "Urban", "UrbanArea")
unprotected <- rename_if_present(unprotected, "Town", "TownArea")
unprotected <- rename_if_present(unprotected, "Rural", "RuralArea")
require_columns(unprotected, c("Geo", "UrbanArea", "TownArea", "RuralArea"), "bzone_unprotected_area.csv")
write_if_changed(unprotected_original, unprotected, unprotected_path, "29_bzone_unprotected_area.csv")

network <- read_chr(network_path)
network_original <- network
network <- rename_if_present(network, "D3bp04", "D3bpo4")
require_columns(network, "D3bpo4", "bzone_network_design.csv")
write_if_changed(network_original, network, network_path, "25_bzone_network_design.csv")

tdm <- read_chr(tdm_path)
tdm_original <- tdm
tdm <- repair_geo_from_bzone_order_by_year(tdm, bzones, "bzone_travel_demand_management.csv")
tdm <- ensure_2045_from_2024(tdm, "bzone_travel_demand_management.csv")
write_if_changed(tdm_original, tdm, tdm_path, "28_bzone_travel_demand_management.csv")

carsvc <- read_chr(carsvc_path)
carsvc_original <- carsvc
carsvc <- ensure_2045_from_2024(carsvc, "bzone_carsvc_availability.csv")
write_if_changed(carsvc_original, carsvc, carsvc_path, "20_bzone_carsvc_availability.csv")

validate_no_backup_dirs_under_updatedcsvs()
validate_bzone_geo_values()
validate_year_coverage(latlon, "bzone_lat_lon.csv")
validate_year_coverage(tdm, "bzone_travel_demand_management.csv")
validate_year_coverage(carsvc, "bzone_carsvc_availability.csv")
validate_deflators(deflators_path)

summary <- dplyr::bind_rows(summary_rows)
message("Prepared VA updatedcsvs inputs: ", updated_dir)
if (dir.exists(backup_dir)) {
  message("Backups written outside updatedcsvs: ", backup_dir)
} else {
  message("No file changes were needed; no backup directory was created.")
}
print(summary, n = nrow(summary))
