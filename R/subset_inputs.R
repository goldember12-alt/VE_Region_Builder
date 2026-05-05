valid_manifest_actions <- c("filter_geo", "copy", "review")

initialize_region_model_dir <- function(source_model_dir, output_model_dir) {
  normalized_source <- normalizePath(source_model_dir, winslash = "/", mustWork = TRUE)
  normalized_output <- normalizePath(output_model_dir, winslash = "/", mustWork = FALSE)

  if (normalized_source == normalized_output) {
    stop("paths.output_model_dir must be different from paths.source_model_dir.", call. = FALSE)
  }

  if (dir.exists(normalized_output)) {
    fs::dir_delete(normalized_output)
  }
  fs::dir_create(normalized_output)

  entries <- list.files(normalized_source, all.files = FALSE, full.names = TRUE, no.. = TRUE)
  scaffold_entries <- entries[!basename(entries) %in% c("inputs", "results")]

  for (entry in scaffold_entries) {
    destination <- fs::path(normalized_output, basename(entry))
    if (dir.exists(entry)) {
      fs::dir_copy(entry, destination)
    } else {
      fs::file_copy(entry, destination)
    }
  }

  fs::dir_create(fs::path(normalized_output, "inputs"))
  invisible(normalized_output)
}

replace_cnf_value <- function(lines, key, value) {
  pattern <- paste0("^", key, "\\s*:")
  replacement <- paste0(key, "         : ", value)
  matches <- grepl(pattern, lines)

  if (!any(matches)) {
    return(c(lines, replacement))
  }

  lines[matches] <- replacement
  lines
}

rewrite_visioneval_cnf <- function(
  output_model_dir,
  model_region,
  scenario,
  description,
  base_year = NULL,
  years = NULL
) {
  cnf_path <- fs::path(output_model_dir, "visioneval.cnf")
  if (!file.exists(cnf_path)) {
    return(NA_character_)
  }

  if (!is.null(base_year) || !is.null(years)) {
    model_years <- validate_model_years(
      base_year = base_year %||% 2024,
      years = years %||% c(base_year %||% 2024, 2045)
    )
    base_year <- model_years$base_year
    years <- model_years$years
  }

  lines <- readLines(cnf_path, warn = FALSE)
  lines <- replace_cnf_value(lines, "Region", model_region)
  lines <- replace_cnf_value(lines, "Scenario", scenario)
  lines <- replace_cnf_value(lines, "Description", description)

  if (!is.null(base_year)) {
    lines <- replace_cnf_value(lines, "BaseYear", as.character(base_year))
  }
  if (!is.null(years)) {
    lines <- replace_cnf_value(
      lines,
      "Years",
      paste0("[ ", paste(as.integer(years), collapse = ", "), " ]")
    )
  }

  writeLines(lines, cnf_path, useBytes = TRUE)
  cnf_path
}

read_input_manifest <- function(manifest_path) {
  if (!file.exists(manifest_path)) {
    stop("Input manifest not found: ", manifest_path, call. = FALSE)
  }

  manifest <- readr::read_csv(
    manifest_path,
    col_types = readr::cols(.default = readr::col_character()),
    show_col_types = FALSE,
    progress = FALSE
  )

  required_columns <- c("file", "geo_level", "action", "notes")
  missing_columns <- setdiff(required_columns, names(manifest))
  if (length(missing_columns) > 0) {
    stop(
      "Manifest is missing required column(s): ",
      paste(missing_columns, collapse = ", "),
      call. = FALSE
    )
  }

  manifest <- manifest[, required_columns]
  manifest$notes[is.na(manifest$notes)] <- ""

  invalid_actions <- setdiff(unique(manifest$action), valid_manifest_actions)
  if (length(invalid_actions) > 0) {
    stop(
      "Manifest contains invalid action value(s): ",
      paste(invalid_actions, collapse = ", "),
      call. = FALSE
    )
  }

  invalid_geo_levels <- setdiff(unique(manifest$geo_level), allowed_geo_levels)
  if (length(invalid_geo_levels) > 0) {
    stop(
      "Manifest contains invalid geo_level value(s): ",
      paste(invalid_geo_levels, collapse = ", "),
      ". Valid values are: ", paste(allowed_geo_levels, collapse = ", "),
      call. = FALSE
    )
  }

  manifest
}

manifest_file_path <- function(root_dir, relative_file) {
  if (is.na(relative_file) || relative_file == "") {
    stop("Manifest contains an empty file path.", call. = FALSE)
  }
  if (is_absolute_path(relative_file)) {
    stop("Manifest file paths must be relative: ", relative_file, call. = FALSE)
  }

  parts <- unlist(strsplit(relative_file, "[/\\\\]+"))
  if (".." %in% parts) {
    stop("Manifest file paths may not contain '..': ", relative_file, call. = FALSE)
  }

  normalizePath(fs::path(root_dir, relative_file), winslash = "/", mustWork = FALSE)
}

read_input_csv <- function(path) {
  readr::read_csv(
    path,
    col_types = readr::cols(.default = readr::col_character()),
    show_col_types = FALSE,
    progress = FALSE
  )
}

write_output_csv <- function(data, path) {
  fs::dir_create(fs::path_dir(path))
  readr::write_csv(data, path, na = "")
}

process_manifest_row <- function(row, source_model_dir, output_model_dir, allowed_geo) {
  file <- row$file[[1]]
  geo_level <- row$geo_level[[1]]
  action <- row$action[[1]]
  notes <- row$notes[[1]]
  allowed_values <- allowed_geo[[geo_level]]

  source_path <- manifest_file_path(source_model_dir, file)
  output_path <- manifest_file_path(output_model_dir, file)

  if (!file.exists(source_path)) {
    stop("Manifest references a missing source file: ", source_path, call. = FALSE)
  }

  if (action == "review") {
    input_data <- read_csv_for_validation(source_path)
    return(make_validation_row(
      file = file,
      geo_level = geo_level,
      action = action,
      input_data = input_data,
      output_data = NULL,
      allowed_values = allowed_values,
      status = "review_required",
      notes = notes
    ))
  }

  if (action == "copy") {
    fs::dir_create(fs::path_dir(output_path))
    fs::file_copy(source_path, output_path, overwrite = TRUE)

    input_data <- read_csv_for_validation(source_path)
    output_data <- read_csv_for_validation(output_path)
    assert_no_unexpected_output_geo(file, output_data, allowed_values)

    return(make_validation_row(
      file = file,
      geo_level = geo_level,
      action = action,
      input_data = input_data,
      output_data = output_data,
      allowed_values = allowed_values,
      status = "ok",
      notes = notes
    ))
  }

  input_data <- read_input_csv(source_path)
  if (!"Geo" %in% names(input_data)) {
    stop("filter_geo file lacks required Geo column: ", source_path, call. = FALSE)
  }

  output_data <- dplyr::filter(input_data, as.character(.data$Geo) %in% allowed_values)
  write_output_csv(output_data, output_path)

  generated_data <- read_csv_for_validation(output_path)
  assert_no_unexpected_output_geo(file, generated_data, allowed_values)

  make_validation_row(
    file = file,
    geo_level = geo_level,
    action = action,
    input_data = input_data,
    output_data = generated_data,
    allowed_values = allowed_values,
    status = "ok",
    notes = notes
  )
}

subset_inputs_from_manifest <- function(manifest, source_model_dir, output_model_dir, allowed_geo) {
  report_rows <- vector("list", nrow(manifest))

  for (row_index in seq_len(nrow(manifest))) {
    report_rows[[row_index]] <- process_manifest_row(
      manifest[row_index, ],
      source_model_dir = source_model_dir,
      output_model_dir = output_model_dir,
      allowed_geo = allowed_geo
    )
  }

  dplyr::bind_rows(report_rows)
}
