# VE Region Builder

This standalone helper project generates region-specific VisionEval model input folders from accurate statewide Virginia inputs.

It does not modify VisionEval source code, statewide model inputs, or faulty regional model inputs. Generated files are written under this repository's `outputs/` folder.

## Purpose

The prototype builds a regional input folder by:

1. Reading a YAML config that lists selected Mareas.
2. Reading the statewide `defs/geography.csv`.
3. Filtering geography rows to the selected Mareas.
4. Deriving allowed Marea, Azone, Bzone, and Czone values from that filtered geography.
5. Writing a generated `defs/geography.csv`.
6. Applying `metadata/input_manifest.csv` to filter, copy, or skip input files.
7. Writing a validation report.

The statewide geography crosswalk is authoritative. The pipeline does not assume Marea, Azone, Bzone, or Czone names are interchangeable.

## Folder Layout

```text
R/
  assemble_statewide_model.R
  build_geo_mask.R
  subset_inputs.R
  validate_outputs.R
scripts/
  assemble_statewide_model.R
  build_region_model.R
configs/
  statewide_assembly.example.yml
  region.example.yml
metadata/
  input_manifest.csv
  input_manifest_notes.md
outputs/
  generated_models/
  reports/
  logs/
tests/
  fixtures/
```

For packaging and distribution guidance, see `docs/PACKAGING.md`.

## Config Format

Copy the example configs before editing machine-specific paths:

```powershell
Copy-Item configs/statewide_assembly.example.yml configs/statewide_assembly.yml
Copy-Item configs/region.example.yml configs/my_region.yml
```

Statewide assembly config:

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

The assembly output paths must resolve under this repository's `outputs/` folder. Existing assembly output is replaced when `overwrite_output: true`.

Regional subsetting config:

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

`region.mareas` selects the planning region. `region.region_geo_values` is used only for manifest rows declared as `geo_level: Region`; lower geography levels are derived from `paths.geography_file`.

`paths.geography_file` is optional and defaults to `defs/geography.csv` for fixture compatibility. For real VisionEval models using the assembled statewide source, set it to `defs/geo.csv`. `paths.output_model_dir` and `paths.validation_report` must resolve under this repository's `outputs/` folder.

## Manifest Format

`metadata/input_manifest.csv` must contain:

```text
file,geo_level,action,notes
```

Allowed `geo_level` values are `Region`, `Marea`, `Azone`, `Bzone`, and `Czone`.

Allowed `action` values are:

- `filter_geo`: read the statewide CSV, require a `Geo` column, keep rows whose `Geo` is allowed for the declared `geo_level`, and write the generated CSV.
- `copy`: copy the source file unchanged.
- `review`: skip the file and record it in the validation report.

The generated geography file is created from the configured statewide geography crosswalk and should not be copied from the manifest.

## Run

Install the lightweight R dependencies if needed:

```r
install.packages(c("readr", "dplyr", "yaml", "fs", "tibble"))
```

Assemble the clean statewide source model first:

```powershell
Rscript scripts/assemble_statewide_model.R configs/statewide_assembly.yml
```

The assembly step copies the template model to `outputs/generated_models/statewide_va_clean`, matches expected inputs from `data_sources/filelist.txt` against corrected CSVs, injects only approved or unambiguous matches, and writes `outputs/reports/statewide_assembly_report.csv`. It does not perform regional filtering.

Matching priority is:

- Approved manual mappings in `metadata/statewide_manual_file_mappings.csv`.
- Exact filename match.
- Case-insensitive filename match.
- Normalized filename match.

Manual mappings are only used when `approved` is true. The mapped updated CSV must exist under `updated_csv_dir`; it is copied into the expected template location while preserving the expected filename in the generated model.

If an expected file has no updated CSV match but already exists in the copied template model, assembly records `status = template_existing` and leaves the template file in place. This is expected for files such as non-CSV model parameters or inputs with no approved replacement.

The statewide geography crosswalk is injected explicitly from `paths.geography_file` under `updated_csv_dir` to `paths.geography_destination` in the generated model. This supports VisionEval models that use `defs/geo.csv` even though `geo.csv` is not part of `data_sources/filelist.txt`.

Approved column renames in `metadata/statewide_column_renames.csv` are applied only after files are copied into the generated statewide model. This normalizes known geography key headings to `Geo` without modifying the source template or updated CSV files, and writes `outputs/reports/statewide_column_rename_report.csv`.

You can also override config values with `key=value` arguments, for example:

```powershell
Rscript scripts/assemble_statewide_model.R output_model_dir=outputs/generated_models/statewide_va_clean
```

Run a regional build from the repository root after editing a region config:

```powershell
Rscript scripts/build_region_model.R configs/my_region.yml
```

Expected generated paths:

```text
outputs/generated_models/my_region/
outputs/reports/my_region_validation.csv
```

## Current Scope

This first version only subsets, copies, skips, and validates files listed in `metadata/input_manifest.csv`. It does not infer file geography automatically, transform units, recalculate totals, or repair data values.

The statewide assembly stage is also conservative: it preserves the template model structure, treats `data_sources/filelist.txt` as the expected-file contract, and refuses to inject ambiguous filename matches.

