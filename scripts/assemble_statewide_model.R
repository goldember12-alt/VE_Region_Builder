#!/usr/bin/env Rscript

script_path <- function() {
  file_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)
  if (length(file_arg) > 0) {
    return(normalizePath(sub("^--file=", "", file_arg[[1]]), winslash = "/", mustWork = TRUE))
  }
  normalizePath("scripts/assemble_statewide_model.R", winslash = "/", mustWork = TRUE)
}

repo_root <- normalizePath(file.path(dirname(script_path()), ".."), winslash = "/", mustWork = TRUE)

source(file.path(repo_root, "R", "build_geo_mask.R"))
source(file.path(repo_root, "R", "assemble_statewide_model.R"))

check_required_packages()

args <- commandArgs(trailingOnly = TRUE)
config <- read_statewide_assembly_config(args, repo_root)

message("Assembling statewide source model.")
message("Template model: ", config$template_model_dir)
message("Updated CSVs: ", config$updated_csv_dir)
message("Expected file list: ", config$filelist_path)
if (!is.na(config$manual_mapping_path)) {
  message("Manual mappings: ", config$manual_mapping_path)
}
if (!is.na(config$geography_file) && nzchar(config$geography_file)) {
  message("Explicit geography: ", config$geography_file, " -> ", config$geography_destination)
}
if (length(config$explicit_file_injections) > 0) {
  for (injection in config$explicit_file_injections) {
    message("Explicit file injection: ", injection$source, " -> ", injection$destination)
  }
}
message("Output model: ", config$output_model_dir)

result <- assemble_statewide_model(config, repo_root)
summary <- result$summary

message("Wrote statewide assembly report: ", result$report_path)
message("Wrote statewide column rename report: ", result$column_rename_report_path)
message("Expected files: ", summary$expected_count)
message("Injected files: ", summary$injected_count)
message("Manual mappings injected: ", summary$manual_mapping_count)
message("Explicit geography injections: ", summary$explicit_geography_count)
message("Explicit file injections: ", summary$explicit_file_injection_count)
message("Template existing files: ", summary$template_existing_count)
message("Missing files: ", summary$missing_count)
message("Ambiguous files: ", summary$ambiguous_count)
message("No template location: ", summary$no_template_location_count)
message("Unused updated CSVs: ", summary$unused_updated_csv_count)

if (summary$missing_count > 0 || summary$ambiguous_count > 0 || summary$no_template_location_count > 0) {
  message("Generated statewide model needs review before using it as source_model_dir.")
} else {
  message("Generated statewide model has no missing or ambiguous expected CSV replacements.")
}
