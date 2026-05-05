# VE Region Builder

VE Region Builder is a standalone R project for creating region-specific VisionEval input folders from a statewide VisionEval model assembled from a template model and corrected statewide CSV inputs.

The project is non-destructive. It does not modify VisionEval source code, statewide source inputs, template model folders, or existing model repositories. It writes generated models, reports, and logs under this repository’s `outputs/` folder.

## What This Project Does

The workflow has two main steps.

First, it creates a statewide source model. It copies a template VisionEval model and adds corrected statewide CSV inputs to the generated copy.

Second, it creates a regional model folder. It filters the statewide model inputs to a selected set of Mareas and writes a region-specific VisionEval input folder.

The statewide geography file defines which zones belong to each region. You select the Mareas, and the workflow finds the related Azones, Bzones, and Czones from that file.

File handling is controlled by `metadata/input_manifest.csv`. The workflow does not guess how each file should be filtered or copied.

## Requirements

Install R and these R packages:

```r
install.packages(c("readr", "dplyr", "yaml", "fs", "tibble"))
```

Run all commands from the repository root.

## Repository Layout

```text
R/                         Reusable R functions
scripts/                   Command-line entry points
configs/                   Example configs to copy before editing
metadata/                  Input manifest and approved mapping metadata
data_sources/filelist.txt  Expected statewide input file list
tests/fixtures/            Small fixture model for smoke testing
outputs/                   Runtime outputs; ignored by git
```

## Quick Smoke Test

Run the fixture smoke test to confirm that the project works without private or external data:

```powershell
Rscript scripts/run_fixture_smoke.R
```

Expected outputs:

```text
outputs/generated_models/fixture_smoke/
outputs/reports/fixture_smoke_validation.csv
```

The smoke test uses:

```text
tests/fixtures/statewide_model
metadata/input_manifest.csv
```

## Step 1: Configure Statewide Assembly

Copy the example statewide assembly config:

```powershell
Copy-Item configs/statewide_assembly.example.yml configs/statewide_assembly.yml
```

Edit `configs/statewide_assembly.yml`:

```yaml
paths:
  template_model_dir: C:/path/to/template_model
  updated_csv_dir: C:/path/to/statewide_csv_inputs
  filelist_path: data_sources/filelist.txt
  manual_mapping_path: metadata/statewide_manual_file_mappings.csv
  column_renames_path: metadata/statewide_column_renames.csv
  geography_file: geo.csv
  geography_destination: defs/geo.csv
  output_model_dir: outputs/generated_models/statewide_va_clean
  report_path: outputs/reports/statewide_assembly_report.csv

overwrite_output: true
```

The assembly step copies `template_model_dir` into:

```text
outputs/generated_models/statewide_va_clean
```

Then it adds approved or clearly matched corrected CSVs from `updated_csv_dir` to that generated copy.

The original template model and statewide CSV folders are not modified.

Run the assembly step:

```powershell
Rscript scripts/assemble_statewide_model.R configs/statewide_assembly.yml
```

Review the reports:

```text
outputs/reports/statewide_assembly_report.csv
outputs/reports/statewide_column_rename_report.csv
```

Fix any missing, ambiguous, or unmapped files before using the generated statewide model for regional builds.

## Step 2: Configure a Regional Build

Copy the region example config:

```powershell
Copy-Item configs/region.example.yml configs/my_region.yml
```

Edit `configs/my_region.yml`:

```yaml
region:
  name: my_region
  mareas:
    - Example Marea
  region_geo_values:
    - Virginia

paths:
  source_model_dir: outputs/generated_models/statewide_va_clean
  output_model_dir: outputs/generated_models/my_region
  validation_report: outputs/reports/my_region_validation.csv
  manifest: metadata/input_manifest.csv
  geography_file: defs/geo.csv
```

Run the regional build:

```powershell
Rscript scripts/build_region_model.R configs/my_region.yml
```

Expected outputs:

```text
outputs/generated_models/my_region/
outputs/reports/my_region_validation.csv
```

## Manifest Rules

`metadata/input_manifest.csv` tells the workflow how to handle each input file.

It must contain these columns:

```text
file,geo_level,action,notes
```

Allowed `geo_level` values are:

```text
Region, Marea, Azone, Bzone, Czone
```

Allowed `action` values are:

| Action | Meaning |
|---|---|
| `filter_geo` | The file must have a `Geo` column. The workflow keeps only rows whose `Geo` value belongs to the allowed geography list for that file. |
| `copy` | The workflow copies the file unchanged. If the file has `Geo` values, it checks them during validation. |
| `review` | The workflow skips the file and records it in the validation report for manual review. |

The generated geography file is written from the filtered statewide geography file. It should not be listed as a copied manifest row.

## Generated Files and Local Configs

This repository contains the code, metadata, and example configs needed to run the workflow. It does not include statewide input data, template VisionEval models, generated regional models, or VisionEval run outputs.

Generated files are written under `outputs/`:

```text
outputs/generated_models/
outputs/reports/
outputs/logs/
```

Local config files are excluded from git because they contain machine-specific paths. To run the workflow, copy the example configs and edit the copies for your local setup:

```text
configs/statewide_assembly.example.yml  ->  configs/statewide_assembly.yml
configs/region.example.yml              ->  configs/my_region.yml
```

Only the example config files are intended to be shared in the repository.