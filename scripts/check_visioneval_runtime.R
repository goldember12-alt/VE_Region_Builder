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
  if (!file.exists(config_path) || !requireNamespace("yaml", quietly = TRUE)) {
    return(list())
  }

  config <- yaml::read_yaml(config_path)
  if (is.null(config)) list() else config
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

print_item <- function(label, value) {
  cat(label, ": ", value, "\n", sep = "")
}

repo_root <- find_repo_root()
local_config <- read_local_runtime_config(repo_root)
ve_home <- runtime_value("VE_HOME", "ve_home", local_config)
ve_runtime <- runtime_value("VE_RUNTIME", "ve_runtime", local_config)
ve_home_exists <- nzchar(ve_home) && dir.exists(ve_home)
startup_file <- if (nzchar(ve_home)) file.path(ve_home, "VisionEval.R") else ""
startup_file_exists <- nzchar(startup_file) && file.exists(startup_file)
package_visible <- requireNamespace("visioneval", quietly = TRUE)
generated_models_exists <- dir.exists(file.path(repo_root, "outputs", "generated_models"))

print_item("R executable", file.path(R.home("bin"), "R"))
print_item("R version", R.version.string)
print_item("Working directory", normalizePath(getwd(), winslash = "/", mustWork = TRUE))
print_item("Repo root", repo_root)
print_item(".libPaths()", paste(.libPaths(), collapse = " | "))
print_item("VE_HOME", if (nzchar(ve_home)) ve_home else "<unset>")
print_item("VE_RUNTIME", if (nzchar(ve_runtime)) ve_runtime else "<unset>")
print_item("VE_HOME exists", ve_home_exists)
print_item("VE_HOME/VisionEval.R exists", startup_file_exists)
print_item("Package 'visioneval' visible", package_visible)
print_item("outputs/generated_models exists", generated_models_exists)

if (!package_visible && !startup_file_exists) {
  stop(
    "VisionEval runtime not found. Set VE_HOME to the VisionEval installation folder ",
    "that contains VisionEval.R, or install package 'visioneval' into this R library. ",
    "You can also copy configs/local_runtime.example.yml to configs/local_runtime.yml ",
    "and set ve_home there.",
    call. = FALSE
  )
}

cat("VisionEval runtime check passed.\n")
