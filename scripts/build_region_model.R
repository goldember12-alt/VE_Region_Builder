#!/usr/bin/env Rscript

script_path <- function() {
  file_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)
  if (length(file_arg) > 0) {
    return(normalizePath(sub("^--file=", "", file_arg[[1]]), winslash = "/", mustWork = TRUE))
  }
  normalizePath("scripts/build_region_model.R", winslash = "/", mustWork = TRUE)
}

repo_root <- normalizePath(file.path(dirname(script_path()), ".."), winslash = "/", mustWork = TRUE)

source(file.path(repo_root, "R", "build_geo_mask.R"))
source(file.path(repo_root, "R", "validate_outputs.R"))
source(file.path(repo_root, "R", "subset_inputs.R"))

check_required_packages()

args <- commandArgs(trailingOnly = TRUE)
config_path <- if (length(args) >= 1) args[[1]] else "configs/example_region.yml"

config <- read_region_config(config_path, repo_root = repo_root)

outputs_root <- normalizePath(file.path(repo_root, "outputs"), winslash = "/", mustWork = FALSE)
assert_path_under(config$output_model_dir, outputs_root, "paths.output_model_dir")
assert_path_under(config$validation_report, outputs_root, "paths.validation_report")

message("Building region model inputs for: ", config$region_name)
message("Source model inputs: ", config$source_model_dir)
message("Output model inputs: ", config$output_model_dir)
message("Geography file: ", config$geography_file)

geography <- read_statewide_geography(config$source_model_dir, config$geography_file)
geo_mask <- build_geo_mask(
  geography = geography,
  selected_mareas = config$selected_mareas,
  region_geo_values = config$region_geo_values
)

generated_geography <- write_generated_geography(
  geography = geo_mask$geography,
  output_model_dir = config$output_model_dir,
  geography_file = config$geography_file
)
message("Wrote generated geography: ", generated_geography)

manifest <- read_input_manifest(config$manifest)
report <- subset_inputs_from_manifest(
  manifest = manifest,
  source_model_dir = config$source_model_dir,
  output_model_dir = config$output_model_dir,
  allowed_geo = geo_mask$allowed_geo
)

report_path <- write_validation_report(report, config$validation_report)
message("Wrote validation report: ", report_path)
message("Complete.")
