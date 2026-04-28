allowed_geo_levels <- c("Region", "Marea", "Azone", "Bzone", "Czone")

required_packages <- c("readr", "dplyr", "yaml", "fs", "tibble")

check_required_packages <- function(packages = required_packages) {
  missing <- packages[!vapply(packages, requireNamespace, logical(1), quietly = TRUE)]
  if (length(missing) > 0) {
    stop(
      "Missing required R package(s): ", paste(missing, collapse = ", "),
      ". Install them before running this pipeline.",
      call. = FALSE
    )
  }
  invisible(TRUE)
}

`%||%` <- function(x, y) {
  if (is.null(x)) y else x
}

is_absolute_path <- function(path) {
  grepl("^([A-Za-z]:[/\\\\]|[/\\\\]{2}|/)", path)
}

normalize_project_path <- function(path, base_dir) {
  if (is.null(path) || length(path) != 1 || is.na(path) || path == "") {
    stop("Expected a single non-empty path.", call. = FALSE)
  }
  resolved <- if (is_absolute_path(path)) path else fs::path(base_dir, path)
  normalizePath(resolved, winslash = "/", mustWork = FALSE)
}

assert_path_under <- function(path, parent, label) {
  normalized_path <- normalizePath(path, winslash = "/", mustWork = FALSE)
  normalized_parent <- normalizePath(parent, winslash = "/", mustWork = FALSE)
  prefix <- paste0(gsub("/+$", "", normalized_parent), "/")

  if (!(normalized_path == normalized_parent || startsWith(normalized_path, prefix))) {
    stop(
      label, " must be under ", normalized_parent, ". Got: ", normalized_path,
      call. = FALSE
    )
  }

  invisible(normalized_path)
}

clean_values <- function(values) {
  unique(stats::na.omit(as.character(values)))
}

read_region_config <- function(config_path, repo_root = getwd()) {
  check_required_packages()

  config_path <- normalize_project_path(config_path, repo_root)
  if (!file.exists(config_path)) {
    stop("Region config not found: ", config_path, call. = FALSE)
  }

  config <- yaml::read_yaml(config_path)
  if (is.null(config)) {
    stop("Region config is empty: ", config_path, call. = FALSE)
  }

  region <- config$region %||% list()
  paths <- config$paths %||% list()

  selected_mareas <- region$mareas %||% config$selected_mareas %||% config$mareas
  selected_mareas <- clean_values(selected_mareas)
  if (length(selected_mareas) == 0) {
    stop("Region config must list at least one selected Marea.", call. = FALSE)
  }

  region_name <- region$name %||% config$region_name %||% "region"
  region_geo_values <- region$region_geo_values %||%
    config$region_geo_values %||%
    region$geo_values %||%
    region_name
  region_geo_values <- clean_values(region_geo_values)

  source_model_dir <- paths$source_model_dir %||% config$source_model_dir
  output_model_dir <- paths$output_model_dir %||% config$output_model_dir
  validation_report <- paths$validation_report %||% config$validation_report
  manifest <- paths$manifest %||% config$manifest %||% "metadata/input_manifest.csv"

  if (is.null(source_model_dir) || is.null(output_model_dir) || is.null(validation_report)) {
    stop(
      "Region config must define paths.source_model_dir, paths.output_model_dir, ",
      "and paths.validation_report.",
      call. = FALSE
    )
  }

  list(
    config_path = config_path,
    region_name = as.character(region_name),
    selected_mareas = selected_mareas,
    region_geo_values = region_geo_values,
    source_model_dir = normalize_project_path(source_model_dir, repo_root),
    output_model_dir = normalize_project_path(output_model_dir, repo_root),
    validation_report = normalize_project_path(validation_report, repo_root),
    manifest = normalize_project_path(manifest, repo_root)
  )
}

read_statewide_geography <- function(source_model_dir) {
  geography_path <- fs::path(source_model_dir, "defs", "geography.csv")
  if (!file.exists(geography_path)) {
    stop("Statewide geography file not found: ", geography_path, call. = FALSE)
  }

  readr::read_csv(
    geography_path,
    col_types = readr::cols(.default = readr::col_character()),
    show_col_types = FALSE,
    progress = FALSE
  )
}

build_geo_mask <- function(geography, selected_mareas, region_geo_values) {
  required_columns <- c("Marea", "Azone", "Bzone", "Czone")
  missing_columns <- setdiff(required_columns, names(geography))
  if (length(missing_columns) > 0) {
    stop(
      "defs/geography.csv is missing required column(s): ",
      paste(missing_columns, collapse = ", "),
      call. = FALSE
    )
  }

  selected_mareas <- clean_values(selected_mareas)
  geography_mareas <- clean_values(geography$Marea)
  missing_mareas <- setdiff(selected_mareas, geography_mareas)
  if (length(missing_mareas) > 0) {
    stop(
      "Selected Marea value(s) not found in defs/geography.csv: ",
      paste(missing_mareas, collapse = ", "),
      call. = FALSE
    )
  }

  filtered_geography <- dplyr::filter(geography, .data$Marea %in% selected_mareas)
  if (nrow(filtered_geography) == 0) {
    stop("Selected Mareas produced an empty geography mask.", call. = FALSE)
  }

  allowed_geo <- list(
    Region = clean_values(region_geo_values),
    Marea = clean_values(filtered_geography$Marea),
    Azone = clean_values(filtered_geography$Azone),
    Bzone = clean_values(filtered_geography$Bzone),
    Czone = clean_values(filtered_geography$Czone)
  )

  list(
    geography = filtered_geography,
    allowed_geo = allowed_geo
  )
}

write_generated_geography <- function(geography, output_model_dir) {
  output_path <- fs::path(output_model_dir, "defs", "geography.csv")
  fs::dir_create(fs::path_dir(output_path))
  readr::write_csv(geography, output_path, na = "")
  output_path
}
