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

path_ends_with_startup_file <- function(path) {
  grepl("(^|[/\\\\])VisionEval\\.R$", path, ignore.case = TRUE)
}

require_model_contents <- function(model_dir) {
  required <- c("defs", "inputs", "queries", "scripts", "visioneval.cnf")
  missing <- required[!file.exists(file.path(model_dir, required))]
  if (length(missing) > 0) {
    stop(
      "Generated model is missing required content: ",
      paste(missing, collapse = ", "),
      ". Rebuild it with scripts/build_region_model.R.",
      call. = FALSE
    )
  }
}

load_visioneval_runtime <- function(repo_root, generated_models_dir) {
  local_config <- read_local_runtime_config(repo_root)
  ve_home <- runtime_value("VE_HOME", "ve_home", local_config)
  if (nzchar(ve_home) && path_ends_with_startup_file(ve_home)) {
    stop(
      "VE_HOME appears to point to the VisionEval.R file. ",
      "Set VE_HOME to its containing folder instead. Suggested value: ",
      gsub("\\\\", "/", dirname(ve_home)),
      call. = FALSE
    )
  }
  startup_file <- if (nzchar(ve_home)) file.path(ve_home, "VisionEval.R") else ""

  Sys.setenv(VE_RUNTIME = generated_models_dir)

  if (nzchar(startup_file) && file.exists(startup_file)) {
    if (!nzchar(Sys.getenv("VE_HOME", unset = ""))) {
      Sys.setenv(VE_HOME = normalizePath(ve_home, winslash = "/", mustWork = TRUE))
    }

    old_wd <- setwd(normalizePath(ve_home, winslash = "/", mustWork = TRUE))
    on.exit(setwd(old_wd), add = TRUE)
    tryCatch(
      source(startup_file),
      error = function(error) {
        stop(
          "Failed to load VisionEval runtime from VE_HOME: ",
          normalizePath(ve_home, winslash = "/", mustWork = FALSE),
          ". ", conditionMessage(error),
          call. = FALSE
        )
      }
    )
    return("VE_HOME")
  }

  if (requireNamespace("visioneval", quietly = TRUE)) {
    library(visioneval)
    return("package")
  }

  stop(
    "VisionEval runtime not found. Set VE_HOME to the VisionEval installation folder ",
    "that contains VisionEval.R, or install package 'visioneval' into this R library. ",
    "You can also copy configs/local_runtime.example.yml to configs/local_runtime.yml ",
    "and set ve_home there.",
    call. = FALSE
  )
}

function_available <- function(name) {
  exists(name, mode = "function", inherits = TRUE)
}

args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 1 || !nzchar(args[[1]])) {
  stop("Usage: Rscript scripts/run_region_model.R <region_name>", call. = FALSE)
}

region_name <- args[[1]]
repo_root <- find_repo_root()
generated_models_dir <- normalizePath(
  file.path(repo_root, "outputs", "generated_models"),
  winslash = "/",
  mustWork = TRUE
)
model_dir <- normalizePath(
  file.path(generated_models_dir, region_name),
  winslash = "/",
  mustWork = FALSE
)

if (!dir.exists(model_dir)) {
  stop(
    "Generated region model not found: ", model_dir,
    ". Build it first with scripts/build_region_model.R.",
    call. = FALSE
  )
}

require_model_contents(model_dir)
runtime_method <- load_visioneval_runtime(repo_root, generated_models_dir)
message("Loaded VisionEval runtime via: ", runtime_method)

open_model_available <- function_available("openModel")
message("Model name: ", region_name)
message("Generated models directory: ", generated_models_dir)
message("VE_RUNTIME: ", Sys.getenv("VE_RUNTIME", unset = "<unset>"))
message("Run strategy: openModel/model$run")
message("openModel available: ", open_model_available)

if (!open_model_available) {
  stop(
    "VisionEval runtime loaded, but openModel() is not available. ",
    "This runner expects the VE-3 VisionEval API. ",
    "Check that VE_HOME points to a compatible VisionEval runtime.",
    call. = FALSE
  )
}

old_wd <- setwd(generated_models_dir)
on.exit(setwd(old_wd), add = TRUE)

model <- openModel(region_name)
model$run()

results_dir <- file.path(model_dir, "results")
message("Model run complete. Results directory:")
message(results_dir)

log_files <- list.files(results_dir, pattern = "^Log_.*\\.txt$", full.names = TRUE)
if (length(log_files) > 0) {
  message("Log files:")
  for (log_file in log_files) {
    message("  ", normalizePath(log_file, winslash = "/", mustWork = FALSE))
  }
} else {
  message("No Log_*.txt files found yet.")
}
