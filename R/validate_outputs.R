unique_non_missing <- function(values) {
  unique(stats::na.omit(as.character(values)))
}

csv_row_count <- function(data) {
  if (is.null(data)) NA_integer_ else nrow(data)
}

csv_geo_count <- function(data) {
  if (is.null(data) || !"Geo" %in% names(data)) {
    return(NA_integer_)
  }
  length(unique_non_missing(data$Geo))
}

unexpected_geo_count <- function(data, allowed_values) {
  if (is.null(data) || !"Geo" %in% names(data)) {
    return(NA_integer_)
  }
  length(setdiff(unique_non_missing(data$Geo), allowed_values))
}

missing_allowed_geo_count <- function(data, allowed_values) {
  if (is.null(data) || !"Geo" %in% names(data)) {
    return(NA_integer_)
  }
  length(setdiff(allowed_values, unique_non_missing(data$Geo)))
}

read_csv_for_validation <- function(path) {
  if (!grepl("\\.csv$", path, ignore.case = TRUE)) {
    return(NULL)
  }

  readr::read_csv(
    path,
    col_types = readr::cols(.default = readr::col_character()),
    show_col_types = FALSE,
    progress = FALSE
  )
}

make_validation_row <- function(file,
                                geo_level,
                                action,
                                input_data,
                                output_data,
                                allowed_values,
                                status,
                                notes) {
  tibble::tibble(
    file = file,
    geo_level = geo_level,
    action = action,
    input_rows = csv_row_count(input_data),
    output_rows = csv_row_count(output_data),
    input_unique_geo_count = csv_geo_count(input_data),
    output_unique_geo_count = csv_geo_count(output_data),
    unexpected_output_geo_count = unexpected_geo_count(output_data, allowed_values),
    missing_allowed_geo_count = missing_allowed_geo_count(output_data, allowed_values),
    status = status,
    notes = notes
  )
}

assert_no_unexpected_output_geo <- function(file, output_data, allowed_values) {
  count <- unexpected_geo_count(output_data, allowed_values)
  if (!is.na(count) && count > 0) {
    unexpected <- setdiff(unique_non_missing(output_data$Geo), allowed_values)
    stop(
      "Generated file contains Geo value(s) outside the allowed set: ",
      file, " (", paste(unexpected, collapse = ", "), ")",
      call. = FALSE
    )
  }
  invisible(TRUE)
}

write_validation_report <- function(report, report_path) {
  fs::dir_create(fs::path_dir(report_path))
  readr::write_csv(report, report_path, na = "")
  report_path
}
