#!/usr/bin/env Rscript

find_repo_root <- function(start_dir = getwd()) {
  current <- normalizePath(start_dir, winslash = "/", mustWork = TRUE)
  repeat {
    if (file.exists(file.path(current, "README.md")) &&
        dir.exists(file.path(current, "outputs", "generated_models"))) {
      return(current)
    }
    parent <- dirname(current)
    if (identical(parent, current)) {
      stop("Could not find VE_RegionBuilder repo root from: ", start_dir, call. = FALSE)
    }
    current <- parent
  }
}

read_local_runtime_config <- function(repo_root) {
  config_path <- file.path(repo_root, "configs", "local_runtime.yml")
  if (!file.exists(config_path)) {
    return(list())
  }

  if (!requireNamespace("yaml", quietly = TRUE)) {
    message("configs/local_runtime.yml exists, but the active R library does not have package 'yaml' installed.")
    message("Using a simple fallback parser for ve_home, ve_runtime, and rscript.")
    message("For full YAML support, install it with:")
    message('  install.packages("yaml")')
    message("or set VE_HOME and VE_RUNTIME as environment variables.")

    config <- parse_simple_runtime_config(config_path)
    if (length(config) == 0) {
      stop(
        "configs/local_runtime.yml exists, but the active R library does not have package 'yaml' installed.\n",
        "Install it with:\n",
        '  install.packages("yaml")\n',
        "or set VE_HOME and VE_RUNTIME as environment variables.",
        call. = FALSE
      )
    }
    return(config)
  }

  config <- yaml::read_yaml(config_path)
  if (is.null(config)) list() else config
}

parse_simple_runtime_config <- function(config_path) {
  lines <- readLines(config_path, warn = FALSE)
  config <- list()
  for (line in lines) {
    line <- sub("\\s+#.*$", "", line)
    if (!nzchar(trimws(line))) {
      next
    }

    match <- regexec("^\\s*(ve_home|ve_runtime|rscript)\\s*:\\s*(.*?)\\s*$", line, perl = TRUE)
    parts <- regmatches(line, match)[[1]]
    if (length(parts) != 3) {
      next
    }

    value <- trimws(parts[[3]])
    if ((startsWith(value, "\"") && endsWith(value, "\"")) ||
        (startsWith(value, "'") && endsWith(value, "'"))) {
      value <- substr(value, 2, nchar(value) - 1)
    }
    config[[parts[[2]]]] <- value
  }
  config
}

runtime_value <- function(name, config_name, config) {
  env_value <- Sys.getenv(name, unset = "")
  if (nzchar(env_value)) {
    return(env_value)
  }

  config_value <- config[[config_name]]
  if (is.null(config_value) || length(config_value) != 1 || is.na(config_value) || !nzchar(config_value)) {
    return("")
  }
  as.character(config_value)
}

is_absolute_path <- function(path) {
  grepl("^([A-Za-z]:[/\\\\]|[/\\\\]{2}|/)", path)
}

print_item <- function(label, value) {
  cat(label, ": ", value, "\n", sep = "")
}

path_ends_with_startup_file <- function(path) {
  grepl("(^|[/\\\\])VisionEval\\.R$", path, ignore.case = TRUE)
}

active_r_version <- function() {
  paste(R.version$major, R.version$minor, sep = ".")
}

runtime_path_value <- function(repo_root, ve_runtime) {
  if (!nzchar(ve_runtime)) {
    return(normalizePath(file.path(repo_root, "outputs", "generated_models"), winslash = "/", mustWork = TRUE))
  }
  runtime_input <- if (is_absolute_path(ve_runtime)) {
    ve_runtime
  } else {
    file.path(repo_root, ve_runtime)
  }
  normalizePath(runtime_input, winslash = "/", mustWork = FALSE)
}

expected_r_from_runtime <- function(ve_home) {
  version_file <- file.path(ve_home, "r.version")
  if (file.exists(version_file)) {
    lines <- readLines(version_file, warn = FALSE)
    match <- sub("^that\\.R\\s*:\\s*", "", grep("^that\\.R\\s*:", lines, value = TRUE))
    if (length(match) > 0 && nzchar(match[[1]])) {
      return(match[[1]])
    }
  }

  normalized <- gsub("\\\\", "/", ve_home)
  match <- regmatches(normalized, regexpr("(^|/)[0-9]+\\.[0-9]+\\.[0-9]+/runtime/?$", normalized))
  if (length(match) > 0 && nzchar(match)) {
    return(sub("^/", "", sub("/runtime/?$", "", match)))
  }

  NA_character_
}

check_runtime_startup <- function(repo_root, ve_home, ve_runtime) {
  expected_r <- expected_r_from_runtime(ve_home)
  this_r <- active_r_version()

  if (!is.na(expected_r) && expected_r != this_r) {
    stop(
      "VisionEval runtime found, but it expects R ", expected_r,
      " and your active Rscript is R ", this_r, ". ",
      "Run with the matching Rscript, for example R-", expected_r,
      "/bin/Rscript.exe, or point ve_home to a VisionEval runtime built for R ",
      this_r, ".",
      call. = FALSE
    )
  }

  if (!nzchar(Sys.getenv("VE_HOME", unset = ""))) {
    Sys.setenv(VE_HOME = normalizePath(ve_home, winslash = "/", mustWork = TRUE))
  }
  if (!nzchar(Sys.getenv("VE_RUNTIME", unset = ""))) {
    Sys.setenv(VE_RUNTIME = runtime_path_value(repo_root, ve_runtime))
  }

  startup_file <- file.path(ve_home, "VisionEval.R")
  old_wd <- setwd(normalizePath(ve_home, winslash = "/", mustWork = TRUE))
  on.exit(setwd(old_wd), add = TRUE)
  tryCatch(
    source(startup_file),
    error = function(error) {
      stop(
        "VisionEval runtime was found, but startup failed. ",
        conditionMessage(error),
        call. = FALSE
      )
    }
  )

  TRUE
}

repo_root <- find_repo_root()
local_config <- read_local_runtime_config(repo_root)
ve_home_raw <- runtime_value("VE_HOME", "ve_home", local_config)
ve_runtime <- runtime_value("VE_RUNTIME", "ve_runtime", local_config)
ve_home_points_to_file <- nzchar(ve_home_raw) && path_ends_with_startup_file(ve_home_raw)
ve_home_interpreted <- if (ve_home_points_to_file) {
  dirname(ve_home_raw)
} else {
  ve_home_raw
}
ve_home_exists <- nzchar(ve_home_interpreted) && dir.exists(ve_home_interpreted)
startup_file <- if (nzchar(ve_home_interpreted)) file.path(ve_home_interpreted, "VisionEval.R") else ""
startup_file_exists <- nzchar(startup_file) && file.exists(startup_file)
expected_r <- if (ve_home_exists) expected_r_from_runtime(ve_home_interpreted) else NA_character_
package_visible <- requireNamespace("visioneval", quietly = TRUE)
generated_models_exists <- dir.exists(file.path(repo_root, "outputs", "generated_models"))

print_item("R executable", file.path(R.home("bin"), "R"))
print_item("R version", R.version.string)
print_item("Working directory", normalizePath(getwd(), winslash = "/", mustWork = TRUE))
print_item("Repo root", repo_root)
print_item(".libPaths()", paste(.libPaths(), collapse = " | "))
print_item("VE_HOME raw value", if (nzchar(ve_home_raw)) ve_home_raw else "<unset>")
print_item("VE_HOME interpreted path", if (nzchar(ve_home_interpreted)) ve_home_interpreted else "<unset>")
print_item("VE_RUNTIME", if (nzchar(ve_runtime)) ve_runtime else "<unset>")
print_item("VE_HOME exists", ve_home_exists)
print_item("VE_HOME/VisionEval.R exists", startup_file_exists)
print_item("VisionEval expected R version", if (!is.na(expected_r)) expected_r else "<unknown>")
print_item("Active Rscript version", active_r_version())
print_item("Package 'visioneval' visible", package_visible)
print_item("outputs/generated_models exists", generated_models_exists)

if (ve_home_points_to_file) {
  stop(
    "VE_HOME appears to point to the VisionEval.R file. ",
    "Set VE_HOME to its containing folder instead. Suggested value: ",
    gsub("\\\\", "/", dirname(ve_home_raw)),
    call. = FALSE
  )
}

if (!package_visible && !startup_file_exists) {
  stop(
    "VisionEval runtime not found. Set VE_HOME to the VisionEval installation folder ",
    "that contains VisionEval.R, or install package 'visioneval' into this R library. ",
    "You can also copy configs/local_runtime.example.yml to configs/local_runtime.yml ",
    "and set ve_home there.",
    call. = FALSE
  )
}

if (startup_file_exists) {
  check_runtime_startup(repo_root, ve_home_interpreted, ve_runtime)
  print_item("VisionEval startup check", TRUE)
}

cat("VisionEval runtime check passed.\n")
