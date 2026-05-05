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

add_static_years <- function(data, label, years = c("2024", "2045")) {
  require_columns(data, "Geo", label)
  if ("Year" %in% names(data)) {
    validate_year_coverage(data, label, years)
    return(data %>% arrange(Geo, Year))
  }

  if (any(!nzchar(trimws(data$Geo)))) {
    stop(label, " has blank Geo values and cannot be expanded by year.", call. = FALSE)
  }
  duplicate_geo <- data %>% count(Geo, name = "n") %>% filter(n > 1)
  if (nrow(duplicate_geo) > 0) {
    stop(label, " has duplicate static Geo rows and cannot be expanded by year.", call. = FALSE)
  }

  expanded <- dplyr::bind_rows(lapply(years, function(year) {
    year_data <- data
    year_data$Year <- year
    year_data
  }))
  expanded <- expanded[, c("Geo", "Year", setdiff(names(expanded), c("Geo", "Year")))]
  add_summary(label, "repaired", paste("Added static Year rows:", paste(years, collapse = ", ")))
  expanded %>% arrange(Geo, Year)
}

normalize_nbsp_csv <- function(path, label) {
  raw <- readBin(path, what = "raw", n = file.info(path)$size)
  nbsp <- raw == as.raw(0xA0)
  if (!any(nbsp)) {
    data <- read_chr(path)
    attr(data, "needs_write") <- FALSE
    return(data)
  }

  raw[nbsp] <- charToRaw(" ")
  text <- rawToChar(raw)
  repaired <- readr::read_csv(
    I(text),
    col_types = readr::cols(.default = readr::col_character()),
    show_col_types = FALSE,
    progress = FALSE,
    trim_ws = TRUE
  )
  repaired[] <- lapply(repaired, function(column) {
    if (is.character(column)) {
      trimws(column)
    } else {
      column
    }
  })
  add_summary(label, "repaired", paste("Replaced NBSP artifacts:", sum(nbsp)))
  attr(repaired, "needs_write") <- TRUE
  repaired
}

cap_vehicle_mean_age <- function(data, label, cap = 13.99) {
  require_columns(data, c("Geo", "Year", "AutoMeanAge", "LtTrkMeanAge"), label)
  capped <- data
  count_values <- 0
  changed_keys <- character(0)

  for (column in c("AutoMeanAge", "LtTrkMeanAge")) {
    values <- suppressWarnings(as.numeric(capped[[column]]))
    invalid_numeric <- is.na(values) & nzchar(trimws(capped[[column]]))
    if (any(invalid_numeric)) {
      stop(label, " has nonnumeric ", column, " values.", call. = FALSE)
    }

    over_cap <- !is.na(values) & values >= 14
    if (any(over_cap)) {
      capped[[column]][over_cap] <- sprintf("%.2f", cap)
      count_values <- count_values + sum(over_cap)
      changed_keys <- union(changed_keys, paste(capped$Geo[over_cap], capped$Year[over_cap], sep = "/"))
    }
  }

  add_summary(
    label,
    if (count_values > 0) "repaired" else "unchanged",
    paste(
      "VisionEval compatibility cap AutoMeanAge/LtTrkMeanAge >= 14 to 13.99;",
      "changed rows:",
      length(changed_keys),
      "changed values:",
      count_values
    )
  )
  capped
}

assert_complete_group_or_all_na <- function(data, columns, label, group_label) {
  require_columns(data, columns, label)
  missing_count <- rowSums(is.na(data[, columns, drop = FALSE]) | data[, columns, drop = FALSE] == "")
  partial <- missing_count > 0 & missing_count < length(columns)
  if (any(partial)) {
    stop(
      label,
      " has partial ",
      group_label,
      " rows and cannot be repaired automatically.",
      call. = FALSE
    )
  }
  invisible(missing_count == length(columns))
}

fill_zero_service_transit_defaults <- function(data, service, columns, defaults, service_columns, label, group_label) {
  require_columns(data, c("Geo", "Year", columns), label)
  require_columns(service, c("Geo", "Year", service_columns), "marea_transit_service.csv")

  all_na_group <- assert_complete_group_or_all_na(data, columns, label, group_label)
  service_key <- service[, c("Geo", "Year", service_columns)]
  joined <- data %>%
    mutate(.row_id = dplyr::row_number()) %>%
    left_join(service_key, by = c("Geo", "Year"))

  missing_service <- is.na(joined[[service_columns[[1]]]])
  if (any(missing_service)) {
    stop(label, " has Geo/Year rows missing from marea_transit_service.csv.", call. = FALSE)
  }

  service_total <- Reduce(
    `+`,
    lapply(service_columns, function(column) suppressWarnings(as.numeric(joined[[column]])))
  )
  if (any(is.na(service_total))) {
    stop("marea_transit_service.csv has nonnumeric service values for ", group_label, ".", call. = FALSE)
  }

  needs_default <- all_na_group & service_total == 0
  unsafe_missing <- all_na_group & service_total != 0

  repaired <- data
  for (column in names(defaults)) {
    repaired[[column]][needs_default] <- defaults[[column]]
  }
  add_summary(
    label,
    if (any(needs_default)) "repaired" else "unchanged",
    paste(
      "Filled all-NA",
      group_label,
      "rows with VisionEval defaults only where corresponding transit service is zero; rows:",
      sum(needs_default),
      "all-NA rows with nonzero service left for manual review:",
      sum(unsafe_missing)
    )
  )
  repaired
}

repair_region_base_year_dvmt <- function(data, label, state_abbr = "VA") {
  require_columns(data, c("StateAbbrLookup", "HvyTrkDvmt"), label)
  if (nrow(data) != 1) {
    stop(label, " must have exactly one Region row.", call. = FALSE)
  }

  missing_state <- !nzchar(trimws(data$StateAbbrLookup)) | is.na(data$StateAbbrLookup)
  missing_hvy <- !nzchar(trimws(data$HvyTrkDvmt)) | is.na(data$HvyTrkDvmt) | toupper(trimws(data$HvyTrkDvmt)) == "NA"
  if (missing_state && missing_hvy) {
    data$StateAbbrLookup <- state_abbr
    add_summary(
      label,
      "repaired",
      paste(
        "Set blank StateAbbrLookup to",
        state_abbr,
        "so VisionEval computes NA HvyTrkDvmt from state default rates."
      )
    )
  } else {
    add_summary(label, "unchanged", "StateAbbrLookup/HvyTrkDvmt combination does not need repair.")
  }
  data
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
    "01_azone_carsvc_characteristic.csv",
    "09_azone_hh_veh_mean_age.csv",
    "20_bzone_carsvc_availability.csv",
    "21_bzone_dwelling_units.csv",
    "23_bzone_hh_inc_qrtl_prop.csv",
    "24_bzone_lat_lon.csv",
    "25_bzone_network_design.csv",
    "28_bzone_travel_demand_management.csv",
    "29_bzone_unprotected_area.csv",
    "marea_transit_service.csv",
    "marea_transit_fuel.csv",
    "marea_transit_powertrain_prop.csv",
    "region_base_year_dvmt.csv"
  )
  invisible(vapply(expected_files, find_one_file, character(1)))
}

validate_preconditions()

geo_path <- find_one_file("geo.csv")
deflators_path <- find_one_file("deflators.csv")
azone_carsvc_characteristic_path <- find_one_file("01_azone_carsvc_characteristic.csv")
hh_veh_mean_age_path <- find_one_file("09_azone_hh_veh_mean_age.csv")
carsvc_path <- find_one_file("20_bzone_carsvc_availability.csv")
du_path <- find_one_file("21_bzone_dwelling_units.csv")
inc_path <- find_one_file("23_bzone_hh_inc_qrtl_prop.csv")
latlon_path <- find_one_file("24_bzone_lat_lon.csv")
network_path <- find_one_file("25_bzone_network_design.csv")
tdm_path <- find_one_file("28_bzone_travel_demand_management.csv")
unprotected_path <- find_one_file("29_bzone_unprotected_area.csv")
marea_transit_service_path <- find_one_file("marea_transit_service.csv")
marea_transit_fuel_path <- find_one_file("marea_transit_fuel.csv")
marea_transit_powertrain_path <- find_one_file("marea_transit_powertrain_prop.csv")
region_base_year_dvmt_path <- find_one_file("region_base_year_dvmt.csv")

geo <- read_chr(geo_path)
require_columns(geo, "Bzone", "geo.csv")
bzones <- as.character(geo$Bzone)
if (any(!nzchar(trimws(bzones)))) {
  stop("geo.csv contains blank Bzone values.", call. = FALSE)
}

azone_carsvc_characteristic <- normalize_nbsp_csv(
  azone_carsvc_characteristic_path,
  "01_azone_carsvc_characteristic.csv"
)
if (isTRUE(attr(azone_carsvc_characteristic, "needs_write"))) {
  attr(azone_carsvc_characteristic, "needs_write") <- NULL
  azone_carsvc_characteristic_original <- read_chr(azone_carsvc_characteristic_path)
  write_if_changed(
    azone_carsvc_characteristic_original,
    azone_carsvc_characteristic,
    azone_carsvc_characteristic_path,
    "01_azone_carsvc_characteristic.csv"
  )
} else {
  attr(azone_carsvc_characteristic, "needs_write") <- NULL
  add_summary("01_azone_carsvc_characteristic.csv", "unchanged", "No NBSP artifacts found.")
}

hh_veh_mean_age <- read_chr(hh_veh_mean_age_path)
hh_veh_mean_age_original <- hh_veh_mean_age
hh_veh_mean_age <- cap_vehicle_mean_age(hh_veh_mean_age, "09_azone_hh_veh_mean_age.csv")
write_if_changed(
  hh_veh_mean_age_original,
  hh_veh_mean_age,
  hh_veh_mean_age_path,
  "09_azone_hh_veh_mean_age.csv"
)

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
unprotected <- add_static_years(unprotected, "bzone_unprotected_area.csv")
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

marea_transit_service <- read_chr(marea_transit_service_path)
marea_transit_fuel <- read_chr(marea_transit_fuel_path)
marea_transit_fuel_original <- marea_transit_fuel
marea_transit_fuel <- fill_zero_service_transit_defaults(
  marea_transit_fuel,
  marea_transit_service,
  c("VanPropDiesel", "VanPropGasoline", "VanPropCng"),
  c(VanPropDiesel = "0", VanPropGasoline = "1", VanPropCng = "0"),
  c("DRRevMi", "VPRevMi"),
  "marea_transit_fuel.csv",
  "Van"
)
marea_transit_fuel <- fill_zero_service_transit_defaults(
  marea_transit_fuel,
  marea_transit_service,
  c("BusPropDiesel", "BusPropGasoline", "BusPropCng"),
  c(BusPropDiesel = "1", BusPropGasoline = "0", BusPropCng = "0"),
  c("MBRevMi", "RBRevMi"),
  "marea_transit_fuel.csv",
  "Bus"
)
write_if_changed(
  marea_transit_fuel_original,
  marea_transit_fuel,
  marea_transit_fuel_path,
  "marea_transit_fuel.csv"
)

marea_transit_powertrain <- read_chr(marea_transit_powertrain_path)
marea_transit_powertrain_original <- marea_transit_powertrain
marea_transit_powertrain <- fill_zero_service_transit_defaults(
  marea_transit_powertrain,
  marea_transit_service,
  c("VanPropIcev", "VanPropHev", "VanPropBev"),
  c(VanPropIcev = "1", VanPropHev = "0", VanPropBev = "0"),
  c("DRRevMi", "VPRevMi"),
  "marea_transit_powertrain_prop.csv",
  "Van"
)
marea_transit_powertrain <- fill_zero_service_transit_defaults(
  marea_transit_powertrain,
  marea_transit_service,
  c("BusPropIcev", "BusPropHev", "BusPropBev"),
  c(BusPropIcev = "1", BusPropHev = "0", BusPropBev = "0"),
  c("MBRevMi", "RBRevMi"),
  "marea_transit_powertrain_prop.csv",
  "Bus"
)
write_if_changed(
  marea_transit_powertrain_original,
  marea_transit_powertrain,
  marea_transit_powertrain_path,
  "marea_transit_powertrain_prop.csv"
)

region_base_year_dvmt <- read_chr(region_base_year_dvmt_path)
region_base_year_dvmt_original <- region_base_year_dvmt
region_base_year_dvmt <- repair_region_base_year_dvmt(region_base_year_dvmt, "region_base_year_dvmt.csv")
write_if_changed(
  region_base_year_dvmt_original,
  region_base_year_dvmt,
  region_base_year_dvmt_path,
  "region_base_year_dvmt.csv"
)

validate_no_backup_dirs_under_updatedcsvs()
validate_bzone_geo_values()
validate_year_coverage(latlon, "bzone_lat_lon.csv")
validate_year_coverage(unprotected, "bzone_unprotected_area.csv")
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
