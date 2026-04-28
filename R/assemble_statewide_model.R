statewide_assembly_defaults <- list(
  template_model_dir = "C:/Users/Jameson.Clements/source/VE_Models/models/SayedMM",
  updated_csv_dir = "C:/Users/Jameson.Clements/source/VE_Models/models/updatedcsvs",
  filelist_path = "data_sources/filelist.txt",
  manual_mapping_path = NA_character_,
  output_model_dir = "outputs/generated_models/statewide_va_clean",
  report_path = "outputs/reports/statewide_assembly_report.csv",
  overwrite_output = TRUE
)

strip_order_prefix <- function(value) {
  sub("^[0-9]+_", "", value)
}

normalize_match_name <- function(value) {
  tolower(gsub("[^A-Za-z0-9]", "", value))
}

relative_path_from <- function(path, root) {
  path <- normalizePath(path, winslash = "/", mustWork = FALSE)
  root <- normalizePath(root, winslash = "/", mustWork = FALSE)
  prefix <- paste0(gsub("/+$", "", root), "/")

  if (path == root) {
    return("")
  }
  if (!startsWith(path, prefix)) {
    stop("Path is not under expected root: ", path, call. = FALSE)
  }

  substring(path, nchar(prefix) + 1)
}

read_statewide_assembly_config <- function(args, repo_root) {
  check_required_packages()

  config <- statewide_assembly_defaults
  config_args <- args[!grepl("=", args, fixed = TRUE)]
  override_args <- args[grepl("=", args, fixed = TRUE)]

  config_path <- if (length(config_args) > 0) config_args[[1]] else "configs/statewide_assembly.yml"
  resolved_config_path <- normalize_project_path(config_path, repo_root)

  if (file.exists(resolved_config_path)) {
    yaml_config <- yaml::read_yaml(resolved_config_path)
    if (!is.null(yaml_config)) {
      paths <- yaml_config$paths %||% list()
      config$template_model_dir <- paths$template_model_dir %||%
        yaml_config$template_model_dir %||%
        config$template_model_dir
      config$updated_csv_dir <- paths$updated_csv_dir %||%
        yaml_config$updated_csv_dir %||%
        config$updated_csv_dir
      config$filelist_path <- paths$filelist_path %||%
        yaml_config$filelist_path %||%
        config$filelist_path
      config$manual_mapping_path <- paths$manual_mapping_path %||%
        yaml_config$manual_mapping_path %||%
        config$manual_mapping_path
      config$output_model_dir <- paths$output_model_dir %||%
        yaml_config$output_model_dir %||%
        config$output_model_dir
      config$report_path <- paths$report_path %||%
        yaml_config$report_path %||%
        config$report_path
      config$overwrite_output <- yaml_config$overwrite_output %||%
        config$overwrite_output
    }
  } else if (length(config_args) > 0) {
    stop("Statewide assembly config not found: ", resolved_config_path, call. = FALSE)
  }

  for (arg in override_args) {
    key <- sub("=.*$", "", arg)
    value <- sub("^[^=]+=", "", arg)
    if (!key %in% names(config)) {
      stop("Unknown assembly argument: ", key, call. = FALSE)
    }
    if (key == "overwrite_output") {
      config[[key]] <- tolower(value) %in% c("true", "t", "1", "yes", "y")
    } else {
      config[[key]] <- value
    }
  }

  list(
    template_model_dir = normalize_project_path(config$template_model_dir, repo_root),
    updated_csv_dir = normalize_project_path(config$updated_csv_dir, repo_root),
    filelist_path = normalize_project_path(config$filelist_path, repo_root),
    manual_mapping_path = if (is.na(config$manual_mapping_path) || !nzchar(config$manual_mapping_path)) {
      NA_character_
    } else {
      normalize_project_path(config$manual_mapping_path, repo_root)
    },
    output_model_dir = normalize_project_path(config$output_model_dir, repo_root),
    report_path = normalize_project_path(config$report_path, repo_root),
    overwrite_output = isTRUE(config$overwrite_output)
  )
}

validate_statewide_assembly_paths <- function(config, repo_root) {
  if (!dir.exists(config$template_model_dir)) {
    stop("template_model_dir does not exist: ", config$template_model_dir, call. = FALSE)
  }
  if (!dir.exists(config$updated_csv_dir)) {
    stop("updated_csv_dir does not exist: ", config$updated_csv_dir, call. = FALSE)
  }
  if (!file.exists(config$filelist_path)) {
    stop("filelist_path does not exist: ", config$filelist_path, call. = FALSE)
  }
  if (!is.na(config$manual_mapping_path) && !file.exists(config$manual_mapping_path)) {
    stop("manual_mapping_path does not exist: ", config$manual_mapping_path, call. = FALSE)
  }

  outputs_root <- normalizePath(file.path(repo_root, "outputs"), winslash = "/", mustWork = FALSE)
  assert_path_under(config$output_model_dir, outputs_root, "output_model_dir")
  assert_path_under(config$report_path, outputs_root, "report_path")

  invisible(TRUE)
}

read_manual_file_mappings <- function(manual_mapping_path) {
  required_columns <- c("expected_file", "updated_file", "approved", "notes")

  if (is.na(manual_mapping_path) || !nzchar(manual_mapping_path)) {
    return(tibble::tibble(
      expected_file = character(),
      updated_file = character(),
      approved = logical(),
      notes = character()
    ))
  }

  mappings <- readr::read_csv(manual_mapping_path, show_col_types = FALSE)
  missing_columns <- setdiff(required_columns, names(mappings))
  if (length(missing_columns) > 0) {
    stop(
      "manual_mapping_path is missing required columns: ",
      paste(missing_columns, collapse = ", "),
      call. = FALSE
    )
  }

  mappings <- mappings[, required_columns]
  mappings$expected_file <- trimws(mappings$expected_file)
  mappings$updated_file <- trimws(mappings$updated_file)
  mappings$approved <- tolower(trimws(as.character(mappings$approved))) %in% c("true", "t", "1", "yes", "y")
  mappings$notes <- trimws(mappings$notes)
  mappings <- mappings[mappings$approved, ]

  empty_values <- !nzchar(mappings$expected_file) | !nzchar(mappings$updated_file)
  if (any(empty_values)) {
    stop("Approved manual mappings must include expected_file and updated_file.", call. = FALSE)
  }

  duplicated_expected <- unique(mappings$expected_file[duplicated(mappings$expected_file)])
  if (length(duplicated_expected) > 0) {
    stop(
      "Approved manual mappings contain duplicate expected_file values: ",
      paste(duplicated_expected, collapse = ", "),
      call. = FALSE
    )
  }

  tibble::as_tibble(mappings)
}

resolve_manual_mapping <- function(expected_row, updated_csvs, manual_mappings) {
  mapping <- manual_mappings[tolower(manual_mappings$expected_file) == tolower(expected_row$expected_file), ]
  if (nrow(mapping) == 0) {
    return(NULL)
  }

  requested <- mapping$updated_file[[1]]
  candidates <- updated_csvs[updated_csvs$updated_relative_path == requested, ]
  if (nrow(candidates) == 0) {
    candidates <- updated_csvs[updated_csvs$updated_file == requested, ]
  }

  if (nrow(candidates) == 1) {
    return(list(
      matched_updated_file = candidates$updated_relative_path[[1]],
      matched_updated_path = candidates$updated_path[[1]],
      match_type = "manual_mapping",
      ambiguous_candidates = "",
      notes = paste("Approved manual mapping:", mapping$notes[[1]])
    ))
  }

  if (nrow(candidates) > 1) {
    return(list(
      matched_updated_file = NA_character_,
      matched_updated_path = NA_character_,
      match_type = "manual_mapping",
      ambiguous_candidates = paste(candidates$updated_relative_path, collapse = " | "),
      notes = paste("Approved manual mapping is ambiguous for updated_file:", requested)
    ))
  }

  list(
    matched_updated_file = NA_character_,
    matched_updated_path = NA_character_,
    match_type = "manual_mapping",
    ambiguous_candidates = "",
    notes = paste("Approved manual mapping target was not found under updated_csv_dir:", requested)
  )
}

parse_expected_filelist <- function(filelist_path) {
  lines <- readLines(filelist_path, warn = FALSE)
  lines <- trimws(lines)
  lines <- lines[nzchar(lines)]

  expected_lines <- lines[grepl("^[0-9]+_.+\\.(csv|json)$", lines, ignore.case = TRUE)]
  if (length(expected_lines) == 0) {
    stop("No numbered expected input files found in: ", filelist_path, call. = FALSE)
  }

  orders <- as.integer(sub("^([0-9]+)_.*$", "\\1", expected_lines))
  expected_files <- strip_order_prefix(expected_lines)

  tibble::tibble(
    order = orders,
    filelist_entry = expected_lines,
    expected_file = expected_files
  )[order(orders), ]
}

find_template_files <- function(template_model_dir) {
  files <- list.files(template_model_dir, recursive = TRUE, full.names = TRUE, all.files = FALSE)
  files <- files[file.info(files)$isdir == FALSE]

  tibble::tibble(
    template_path = normalizePath(files, winslash = "/", mustWork = TRUE),
    expected_file = basename(files),
    expected_relative_path = vapply(files, relative_path_from, character(1), root = template_model_dir)
  )
}

attach_expected_relative_paths <- function(expected, template_files) {
  expected$expected_relative_path <- NA_character_
  expected$template_path <- NA_character_
  expected$location_notes <- ""

  for (row_index in seq_len(nrow(expected))) {
    matches <- template_files[tolower(template_files$expected_file) == tolower(expected$expected_file[[row_index]]), ]
    input_matches <- matches[grepl("^inputs/", matches$expected_relative_path, ignore.case = TRUE), ]
    selected <- if (nrow(input_matches) == 1) input_matches else matches

    if (nrow(selected) == 1) {
      expected$expected_relative_path[[row_index]] <- selected$expected_relative_path[[1]]
      expected$template_path[[row_index]] <- selected$template_path[[1]]
    } else if (nrow(selected) > 1) {
      expected$location_notes[[row_index]] <- paste(
        "Multiple template locations found:",
        paste(selected$expected_relative_path, collapse = " | ")
      )
    } else {
      expected$location_notes[[row_index]] <- "Expected file was not found in template model."
    }
  }

  expected
}

inspect_updated_csvs <- function(updated_csv_dir) {
  csvs <- list.files(updated_csv_dir, pattern = "\\.csv$", recursive = TRUE, full.names = TRUE, ignore.case = TRUE)

  tibble::tibble(
    updated_path = normalizePath(csvs, winslash = "/", mustWork = TRUE),
    updated_file = basename(csvs),
    updated_relative_path = vapply(csvs, relative_path_from, character(1), root = updated_csv_dir),
    lower_file = tolower(basename(csvs)),
    normalized_file = normalize_match_name(basename(csvs))
  )
}

select_single_match <- function(candidates, match_type) {
  if (nrow(candidates) == 1) {
    return(list(
      matched_updated_file = candidates$updated_relative_path[[1]],
      matched_updated_path = candidates$updated_path[[1]],
      match_type = match_type,
      ambiguous_candidates = ""
    ))
  }

  if (nrow(candidates) > 1) {
    return(list(
      matched_updated_file = NA_character_,
      matched_updated_path = NA_character_,
      match_type = match_type,
      ambiguous_candidates = paste(candidates$updated_relative_path, collapse = " | ")
    ))
  }

  NULL
}

match_expected_to_updated <- function(expected_row, updated_csvs, manual_mappings) {
  manual_match <- resolve_manual_mapping(expected_row, updated_csvs, manual_mappings)
  if (!is.null(manual_match)) {
    return(manual_match)
  }

  candidates <- unique(c(expected_row$filelist_entry, expected_row$expected_file))
  lower_candidates <- tolower(candidates)
  normalized_candidates <- normalize_match_name(candidates)

  exact <- updated_csvs[updated_csvs$updated_file %in% candidates, ]
  exact_match <- select_single_match(exact, "exact")
  if (!is.null(exact_match)) {
    return(exact_match)
  }

  case_insensitive <- updated_csvs[updated_csvs$lower_file %in% lower_candidates, ]
  case_match <- select_single_match(case_insensitive, "case_insensitive")
  if (!is.null(case_match)) {
    return(case_match)
  }

  normalized <- updated_csvs[updated_csvs$normalized_file %in% normalized_candidates, ]
  normalized_match <- select_single_match(normalized, "normalized")
  if (!is.null(normalized_match)) {
    return(normalized_match)
  }

  list(
    matched_updated_file = NA_character_,
    matched_updated_path = NA_character_,
    match_type = "none",
    ambiguous_candidates = "",
    notes = ""
  )
}

build_statewide_assembly_plan <- function(expected, updated_csvs, manual_mappings) {
  rows <- vector("list", nrow(expected))

  for (row_index in seq_len(nrow(expected))) {
    match <- match_expected_to_updated(expected[row_index, ], updated_csvs, manual_mappings)

    status <- "injected"
    notes <- trimws(paste(expected$location_notes[[row_index]], match$notes %||% ""))

    if (match$match_type == "none") {
      if (is.na(expected$expected_relative_path[[row_index]])) {
        status <- "missing"
        notes <- paste(c(notes, "No updated CSV match found and no template location exists."), collapse = " ")
      } else {
        status <- "template_existing"
        match$match_type <- "template_existing"
        notes <- paste(c(notes, "No updated CSV match found; copied template file is retained."), collapse = " ")
      }
    } else if (nzchar(match$ambiguous_candidates)) {
      status <- "ambiguous"
      notes <- paste(
        c(notes, "Ambiguous updated CSV candidates:", match$ambiguous_candidates),
        collapse = " "
      )
    } else if (is.na(expected$expected_relative_path[[row_index]])) {
      status <- "no_template_location"
      notes <- paste(c(notes, "Matched CSV was not injected."), collapse = " ")
    }

    rows[[row_index]] <- tibble::tibble(
      order = expected$order[[row_index]],
      expected_file = expected$expected_file[[row_index]],
      expected_relative_path = expected$expected_relative_path[[row_index]],
      matched_updated_file = match$matched_updated_file,
      matched_updated_path = match$matched_updated_path,
      match_type = match$match_type,
      status = status,
      notes = trimws(notes)
    )
  }

  dplyr::bind_rows(rows)
}

copy_template_model <- function(template_model_dir, output_model_dir, overwrite_output) {
  if (dir.exists(output_model_dir)) {
    if (!overwrite_output) {
      stop("Output model directory already exists: ", output_model_dir, call. = FALSE)
    }
    fs::dir_delete(output_model_dir)
  }

  fs::dir_create(fs::path_dir(output_model_dir))
  fs::dir_copy(template_model_dir, output_model_dir)
  invisible(output_model_dir)
}

inject_updated_csvs <- function(plan, output_model_dir) {
  injected <- plan[plan$status == "injected", ]

  for (row_index in seq_len(nrow(injected))) {
    destination <- fs::path(output_model_dir, injected$expected_relative_path[[row_index]])
    fs::dir_create(fs::path_dir(destination))
    fs::file_copy(injected$matched_updated_path[[row_index]], destination, overwrite = TRUE)
  }

  nrow(injected)
}

append_unused_updated_csvs <- function(plan, updated_csvs) {
  used_paths <- stats::na.omit(plan$matched_updated_path[plan$status == "injected"])
  unused <- updated_csvs[!updated_csvs$updated_path %in% used_paths, ]

  unused_rows <- tibble::tibble(
    order = NA_integer_,
    expected_file = NA_character_,
    expected_relative_path = NA_character_,
    matched_updated_file = unused$updated_relative_path,
    matched_updated_path = unused$updated_path,
    match_type = "unused_updated_csv",
    status = "unused_updated_csv",
    notes = "Updated CSV was not injected into the generated model."
  )

  dplyr::bind_rows(plan, unused_rows)
}

write_statewide_assembly_report <- function(report, report_path) {
  report_out <- report[, c(
    "order",
    "expected_file",
    "expected_relative_path",
    "matched_updated_file",
    "match_type",
    "status",
    "notes"
  )]

  fs::dir_create(fs::path_dir(report_path))
  readr::write_csv(report_out, report_path, na = "")
  report_path
}

summarize_statewide_assembly <- function(report) {
  expected_rows <- report[!is.na(report$order), ]
  unused_rows <- report[report$status == "unused_updated_csv", ]

  list(
    expected_count = nrow(expected_rows),
    injected_count = sum(expected_rows$status == "injected"),
    manual_mapping_count = sum(expected_rows$match_type == "manual_mapping" & expected_rows$status == "injected"),
    template_existing_count = sum(expected_rows$status == "template_existing"),
    missing_count = sum(expected_rows$status == "missing"),
    ambiguous_count = sum(expected_rows$status == "ambiguous"),
    no_template_location_count = sum(expected_rows$status == "no_template_location"),
    unused_updated_csv_count = nrow(unused_rows)
  )
}

assemble_statewide_model <- function(config, repo_root) {
  validate_statewide_assembly_paths(config, repo_root)

  expected <- parse_expected_filelist(config$filelist_path)
  template_files <- find_template_files(config$template_model_dir)
  expected <- attach_expected_relative_paths(expected, template_files)
  updated_csvs <- inspect_updated_csvs(config$updated_csv_dir)
  manual_mappings <- read_manual_file_mappings(config$manual_mapping_path)
  plan <- build_statewide_assembly_plan(expected, updated_csvs, manual_mappings)

  copy_template_model(
    template_model_dir = config$template_model_dir,
    output_model_dir = config$output_model_dir,
    overwrite_output = config$overwrite_output
  )

  inject_updated_csvs(plan, config$output_model_dir)
  report <- append_unused_updated_csvs(plan, updated_csvs)
  report_path <- write_statewide_assembly_report(report, config$report_path)

  list(
    report = report,
    report_path = report_path,
    summary = summarize_statewide_assembly(report)
  )
}
