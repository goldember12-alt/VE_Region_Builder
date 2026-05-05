# Packaging VE Region Builder

This document describes how to prepare this repository for distribution to an external user. The package should contain the region-builder code, metadata contracts, fixtures, and example configuration files. It should not contain statewide source inputs, template model inputs, generated model folders, model results, or local machine paths.

The target user experience is:

1. Download or clone this repository.
2. Install the required R packages.
3. Copy an example config file.
4. Point the config at their local input data folders.
5. Assemble a clean statewide source model.
6. Build one or more regional VisionEval input folders.

## Distribution Boundary

Include:

- `R/`
- `scripts/`
- `configs/*.example.yml`
- `metadata/input_manifest.csv`
- `metadata/input_manifest_notes.md`
- `metadata/statewide_manual_file_mappings.csv`, if it contains only filename mapping logic
- `metadata/statewide_column_renames.csv`
- `data_sources/filelist.txt`, if it is only the expected-file contract
- `tests/fixtures/`, only if the fixture data is synthetic or otherwise safe to distribute
- `README.md`
- `AGENTS.md`
- `docs/`

Do not include:

- statewide source model inputs
- template model inputs
- generated regional model inputs
- generated statewide model inputs
- VisionEval run results
- local scratch files
- local absolute paths such as `C:/Users/...`
- `data_sources/paths.yml`, if it contains local data locations

Generated content must stay under:

- `outputs/generated_models/`
- `outputs/reports/`
- `outputs/logs/`

These folders are runtime outputs, not package contents.

## Git Ignore Rules

Before packaging, update `.gitignore` so generated output and local path files are not accidentally committed or zipped:

```gitignore
outputs/generated_models/**
outputs/reports/**
outputs/logs/**
work/**
data_sources/paths.yml

!outputs/generated_models/.gitkeep
!outputs/reports/.gitkeep
!outputs/logs/.gitkeep
```

If empty output folders are useful for orientation, keep `.gitkeep` files in those folders. Otherwise, omit the folders and let the scripts create them.

## Configuration Files

Do not distribute machine-specific configs as the default user-facing files. Convert distributable configs to templates:

```text
configs/statewide_assembly.example.yml
configs/region.example.yml
```

The example statewide assembly config should show placeholders or generic paths:

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

The example regional config should reference the assembled statewide source model:

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

External users should copy the examples before editing:

```powershell
Copy-Item configs/statewide_assembly.example.yml configs/statewide_assembly.yml
Copy-Item configs/region.example.yml configs/my_region.yml
```

Machine-specific configs may exist locally, but they should not be part of the distributable package unless they contain only generic paths.

## User Setup Workflow

Document this minimum setup flow for external users:

1. Install R.
2. Install required R packages:

   ```r
   install.packages(c("readr", "dplyr", "yaml", "fs", "tibble"))
   ```

3. Copy the example configs.
4. Edit `configs/statewide_assembly.yml` to point at:
   - their template VisionEval model folder
   - their statewide corrected CSV input folder
   - the expected geography CSV name
5. Assemble the clean statewide source model:

   ```powershell
   Rscript scripts/assemble_statewide_model.R configs/statewide_assembly.yml
   ```

6. Edit a region config to list selected Mareas and output paths.
7. Build the regional model:

   ```powershell
   Rscript scripts/build_region_model.R configs/my_region.yml
   ```

8. Review the validation report under `outputs/reports/`.

## Metadata Review

Before distribution, review metadata files as package contents:

- `metadata/input_manifest.csv` should remain the authority for file handling.
- Manifest rows should fail loudly through `review` where behavior is not implemented.
- Manual mappings should contain only expected filenames and replacement filenames, not private directories.
- Column rename metadata should contain only approved file and column transformations.
- Region-specific smoke manifests should be included only if they are useful examples and contain no sensitive assumptions.

The geography crosswalk remains authoritative. Region membership must be derived from selected Mareas, and lower-level Azone, Bzone, and Czone membership must be derived from the filtered geography file.

## Fixture Data

Only distribute test fixtures when they are small and safe:

- Prefer toy data that demonstrates the required schema.
- Do not include source statewide model inputs.
- Do not include template model inputs.
- Do not include generated real model inputs.
- Do not include VisionEval results.

If current fixtures are derived from restricted source data, replace them with synthetic fixtures before release.

## Pre-Release Checklist

Run these checks from the repository root before creating a ZIP, release archive, or public clone:

```powershell
git status --short
rg "C:/Users/Jameson.Clements|VisionEval-dev|VE_Models|VE_Models" .
Get-ChildItem outputs -Recurse
```

Expected result:

- `git status --short` should show only intentional packaging changes.
- The path search should find no private/local paths in distributable configs or docs, except clearly marked examples.
- `outputs/` should be empty or contain only ignored generated files and optional `.gitkeep` placeholders.

Also confirm:

- `.gitignore` excludes generated outputs.
- Example configs use generic paths.
- README setup instructions match the current scripts.
- The package can run against fixtures without external source data, if fixtures are shipped.
- The package can run against an external user's input data after they set config paths.

## Suggested Release Shape

A clean distributable package should look roughly like this:

```text
VE_RegionBuilder/
  AGENTS.md
  README.md
  docs/
    PACKAGING.md
  R/
  scripts/
  configs/
    statewide_assembly.example.yml
    region.example.yml
  metadata/
  data_sources/
    filelist.txt
    README.md
  tests/
    fixtures/
  outputs/
    generated_models/
    reports/
    logs/
```

The release should not require the recipient to have the original developer's directory layout. All user-specific paths should be configured after download.
