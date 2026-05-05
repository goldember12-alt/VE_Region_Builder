allowed_geo_levels <- c("Region", "Marea", "Azone", "Bzone", "Czone")
allowed_czone_modes <- c("auto", "absent", "defined")

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

validate_relative_file_path <- function(path, label) {
  if (is_absolute_path(path)) {
    stop(label, " must be relative: ", path, call. = FALSE)
  }

  parts <- unlist(strsplit(path, "[/\\\\]+"))
  if (".." %in% parts || any(!nzchar(parts))) {
    stop(label, " must be a clean relative file path: ", path, call. = FALSE)
  }

  invisible(TRUE)
}

clean_values <- function(values) {
  unique(stats::na.omit(as.character(values)))
}

is_missing_geo_value <- function(values) {
  value <- trimws(as.character(values))
  is.na(values) | !nzchar(value) | toupper(value) == "NA"
}

infer_czone_mode <- function(geography, requested_mode = "auto") {
  requested_mode <- tolower(as.character(requested_mode))
  if (length(requested_mode) != 1 || is.na(requested_mode) || !nzchar(requested_mode)) {
    requested_mode <- "auto"
  }
  if (!(requested_mode %in% allowed_czone_modes)) {
    stop(
      "czone_mode must be one of: ",
      paste(allowed_czone_modes, collapse = ", "),
      call. = FALSE
    )
  }

  czone_absent <- !("Czone" %in% names(geography)) || all(is_missing_geo_value(geography$Czone))
  if (requested_mode == "auto") {
    return(if (czone_absent) "absent" else "defined")
  }
  if (requested_mode == "defined" && czone_absent) {
    stop(
      "czone_mode is defined, but the geography file has no meaningful Czone values.",
      call. = FALSE
    )
  }
  if (requested_mode == "absent" && !czone_absent) {
    stop(
      "czone_mode is absent, but the geography file contains meaningful Czone values.",
      call. = FALSE
    )
  }
  requested_mode
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
  model_region <- region$model_region %||% config$model_region %||% region_name
  scenario <- region$scenario %||% config$scenario %||% "Base"
  description <- region$description %||%
    config$description %||%
    paste("VERSPM for", model_region, "model")
  region_geo_values <- region$region_geo_values %||%
    config$region_geo_values %||%
    region$geo_values %||%
    region_name
  region_geo_values <- clean_values(region_geo_values)
  czone_mode <- region$czone_mode %||% config$czone_mode %||% "auto"

  source_model_dir <- paths$source_model_dir %||% config$source_model_dir
  output_model_dir <- paths$output_model_dir %||% config$output_model_dir
  validation_report <- paths$validation_report %||% config$validation_report
  manifest <- paths$manifest %||% config$manifest %||% "metadata/input_manifest.csv"
  geography_file <- paths$geography_file %||% config$geography_file %||% "defs/geography.csv"

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
    model_region = as.character(model_region),
    scenario = as.character(scenario),
    description = as.character(description),
    selected_mareas = selected_mareas,
    region_geo_values = region_geo_values,
    czone_mode = tolower(as.character(czone_mode)),
    source_model_dir = normalize_project_path(source_model_dir, repo_root),
    output_model_dir = normalize_project_path(output_model_dir, repo_root),
    validation_report = normalize_project_path(validation_report, repo_root),
    manifest = normalize_project_path(manifest, repo_root),
    geography_file = as.character(geography_file)
  )
}

read_statewide_geography <- function(source_model_dir, geography_file = "defs/geography.csv") {
  validate_relative_file_path(geography_file, "paths.geography_file")
  geography_path <- fs::path(source_model_dir, geography_file)
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

build_geo_mask <- function(geography, selected_mareas, region_geo_values, czone_mode = "auto") {
  required_columns <- c("Marea", "Azone", "Bzone")
  missing_columns <- setdiff(required_columns, names(geography))
  if (length(missing_columns) > 0) {
    stop(
      "Geography file is missing required column(s): ",
      paste(missing_columns, collapse = ", "),
      call. = FALSE
    )
  }
  if (!("Czone" %in% names(geography))) {
    # Czone support can be added later if a source geography with real Czones is introduced.
    geography$Czone <- NA_character_
  }

  selected_mareas <- clean_values(selected_mareas)
  geography_mareas <- clean_values(geography$Marea)
  missing_mareas <- setdiff(selected_mareas, geography_mareas)
  if (length(missing_mareas) > 0) {
    stop(
      "Selected Marea value(s) not found in geography file: ",
      paste(missing_mareas, collapse = ", "),
      call. = FALSE
    )
  }

  filtered_geography <- dplyr::filter(geography, .data$Marea %in% selected_mareas)
  if (nrow(filtered_geography) == 0) {
    stop("Selected Mareas produced an empty geography mask.", call. = FALSE)
  }

  czone_mode <- infer_czone_mode(filtered_geography, czone_mode)
  czone_values <- if (czone_mode == "absent") character(0) else clean_values(filtered_geography$Czone)

  allowed_geo <- list(
    Region = clean_values(region_geo_values),
    Marea = clean_values(filtered_geography$Marea),
    Azone = clean_values(filtered_geography$Azone),
    Bzone = clean_values(filtered_geography$Bzone),
    Czone = czone_values
  )

  list(
    geography = filtered_geography,
    allowed_geo = allowed_geo,
    czone_mode = czone_mode
  )
}

prepare_generated_geography <- function(geography, czone_mode = "auto") {
  czone_mode <- infer_czone_mode(geography, czone_mode)
  required_columns <- c("Azone", "Bzone", "Czone", "Marea")
  if (!("Czone" %in% names(geography))) {
    # VisionEval 4.4.2 requires a Czone column; all literal NA values mean unspecified.
    geography$Czone <- NA_character_
  }
  missing_columns <- setdiff(required_columns, names(geography))
  if (length(missing_columns) > 0) {
    stop(
      "Generated geography is missing required column(s): ",
      paste(missing_columns, collapse = ", "),
      call. = FALSE
    )
  }

  geography <- geography[, required_columns, drop = FALSE]
  if (czone_mode == "absent") {
    geography$Czone <- "NA"
  } else {
    if (any(is_missing_geo_value(geography$Czone))) {
      stop(
        "Generated geography has missing Czone values while czone_mode is defined.",
        call. = FALSE
      )
    }
    duplicated_czones <- unique(geography$Czone[duplicated(geography$Czone)])
    if (length(duplicated_czones) > 0) {
      stop(
        "Generated geography has duplicated Czone values: ",
        paste(duplicated_czones, collapse = ", "),
        call. = FALSE
      )
    }
  }

  attr(geography, "czone_mode") <- czone_mode
  geography
}

write_generated_geography <- function(geography, output_model_dir, geography_file = "defs/geography.csv", czone_mode = "auto") {
  validate_relative_file_path(geography_file, "paths.geography_file")
  output_path <- fs::path(output_model_dir, geography_file)
  fs::dir_create(fs::path_dir(output_path))
  generated_geography <- prepare_generated_geography(geography, czone_mode)
  readr::write_csv(generated_geography, output_path, na = "")
  output_path
}
