#!/usr/bin/env Rscript

script_path <- function() {
  file_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)
  if (length(file_arg) > 0) {
    return(normalizePath(sub("^--file=", "", file_arg[[1]]), winslash = "/", mustWork = TRUE))
  }
  normalizePath("scripts/run_fixture_smoke.R", winslash = "/", mustWork = TRUE)
}

repo_root <- normalizePath(file.path(dirname(script_path()), ".."), winslash = "/", mustWork = TRUE)

source(file.path(repo_root, "R", "build_geo_mask.R"))
source(file.path(repo_root, "R", "validate_outputs.R"))
source(file.path(repo_root, "R", "subset_inputs.R"))

check_required_packages()

config <- list(
  region_name = "fixture_smoke",
  selected_mareas = "North",
  region_geo_values = "Fixture",
  source_model_dir = normalize_project_path("tests/fixtures/statewide_model", repo_root),
  output_model_dir = normalize_project_path("outputs/generated_models/fixture_smoke", repo_root),
  validation_report = normalize_project_path("outputs/reports/fixture_smoke_validation.csv", repo_root),
  manifest = normalize_project_path("metadata/input_manifest.csv", repo_root),
  geography_file = "defs/geography.csv"
)

outputs_root <- normalizePath(file.path(repo_root, "outputs"), winslash = "/", mustWork = FALSE)
assert_path_under(config$output_model_dir, outputs_root, "output_model_dir")
assert_path_under(config$validation_report, outputs_root, "validation_report")

if (dir.exists(config$output_model_dir)) {
  fs::dir_delete(config$output_model_dir)
}

message("Running fixture smoke build.")
geography <- read_statewide_geography(config$source_model_dir, config$geography_file)
geo_mask <- build_geo_mask(
  geography = geography,
  selected_mareas = config$selected_mareas,
  region_geo_values = config$region_geo_values
)

generated_geography <- write_generated_geography(
  geography = geo_mask$geography,
  output_model_dir = config$output_model_dir,
  geography_file = config$geography_file,
  czone_mode = geo_mask$czone_mode
)
message("Wrote generated geography: ", generated_geography)

manifest <- read_input_manifest(config$manifest)
report <- subset_inputs_from_manifest(
  manifest = manifest,
  source_model_dir = config$source_model_dir,
  output_model_dir = config$output_model_dir,
  allowed_geo = geo_mask$allowed_geo
)

if (!all(report$status %in% c("ok", "review_required"))) {
  stop("Fixture smoke build produced unexpected status values.", call. = FALSE)
}

validation_report <- write_validation_report(report, config$validation_report)
message("Fixture smoke build complete: ", validation_report)
