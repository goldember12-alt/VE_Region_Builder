# VE Region Builder

VE Region Builder is a standalone R helper project for creating region-specific VisionEval model input folders from a clean statewide VisionEval input model.

The project does not modify VisionEval source code, source statewide inputs, template model inputs, or existing model repositories. All generated model folders, reports, and logs are written under this repository's `outputs/` folder.

## What It Does

The workflow has two stages:

1. Assemble a clean statewide source model from a template VisionEval model and corrected statewide CSV inputs.
2. Build a regional VisionEval input folder by filtering statewide files to selected Mareas.

Regional membership is derived from the statewide geography crosswalk. The selected Mareas determine the allowed Mareas, and the allowed Azones, Bzones, and Czones are derived from the filtered geography file. The tool does not infer input geography automatically; file handling is controlled by `metadata/input_manifest.csv`.

## Requirements

Install R and these R packages:

```r
install.packages(c("readr", "dplyr", "yaml", "fs", "tibble"))
```

Run commands from the repository root.

## Repository Layout

```text
R/                         Reusable R functions
scripts/                   Command-line entry points
configs/                   Example configs to copy before editing
metadata/                  Manifest and approved mapping metadata
data_sources/filelist.txt  Expected statewide input file contract
tests/fixtures/            Small fixture model for smoke testing
outputs/                   Runtime output location, ignored by git
docs/PACKAGING.md          Release and packaging checklist
```

## Quick Smoke Test

Run the fixture smoke workflow to confirm the tool works without private or external data:

```powershell
Rscript scripts/run_fixture_smoke.R
```

Expected output:

```text
outputs/generated_models/fixture_smoke/
outputs/reports/fixture_smoke_validation.csv
```

The smoke workflow uses `tests/fixtures/statewide_model` and `metadata/input_manifest.csv`.

## Configure Statewide Assembly

Copy the example config and edit the copy:

```powershell
Copy-Item configs/statewide_assembly.example.yml configs/statewide_assembly.yml
```

Set these paths in `configs/statewide_assembly.yml`:

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

`template_model_dir` is copied into `outputs/generated_models/statewide_va_clean`. Approved or unambiguous corrected CSVs from `updated_csv_dir` are injected into that generated copy. Source folders are not modified.

Run assembly:

```powershell
Rscript scripts/assemble_statewide_model.R configs/statewide_assembly.yml
```

Review:

```text
outputs/reports/statewide_assembly_report.csv
outputs/reports/statewide_column_rename_report.csv
```

If the report shows missing, ambiguous, or unmapped files, resolve those before using the generated statewide model as a regional source.

## Configure A Region Build

Copy the region example and edit the copy:

```powershell
Copy-Item configs/region.example.yml configs/my_region.yml
```

Example:

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

Expected output:

```text
outputs/generated_models/my_region/
outputs/reports/my_region_validation.csv
```

## Manifest Rules

`metadata/input_manifest.csv` is the authority for file handling. It must contain:

```text
file,geo_level,action,notes
```

Allowed `geo_level` values:

```text
Region, Marea, Azone, Bzone, Czone
```

Allowed `action` values:

- `filter_geo`: require a `Geo` column and keep rows whose `Geo` value is allowed for the declared geography level.
- `copy`: copy the file unchanged and validate any `Geo` values present.
- `review`: skip the file and record it in the validation report.

The generated geography file is written directly from the filtered statewide geography crosswalk and should not be listed as a copied manifest row.

## Safety Boundaries

Generated content must stay under:

```text
outputs/generated_models/
outputs/reports/
outputs/logs/
```

Machine-specific configs such as `configs/statewide_assembly.yml` and `configs/my_region.yml` are ignored by git. Only `configs/*.example.yml` should be distributed.

Do not package source statewide inputs, template model inputs, generated model folders, VisionEval run results, local scratch files, or local path files.

## Packaging Check

Before creating a zip, release archive, or public clone:

```powershell
git status --short
rg "C:/Users/|VisionEval-dev|VE_Models" .
Get-ChildItem outputs -Recurse
```

Expected:

- `git status --short` shows only intentional source, metadata, config example, or documentation changes.
- Local path matches appear only in clearly marked internal instructions or local ignored configs, not distributable code defaults.
- `outputs/` is empty or contains only ignored runtime output that will be excluded from the archive.

See `docs/PACKAGING.md` for the fuller release checklist.
