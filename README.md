# VE Region Builder

VE Region Builder is a standalone R project for creating region-specific
VisionEval model folders from a statewide VisionEval template model and a user
supplied folder of corrected statewide CSV inputs.

The workflow is non-destructive. It does not modify VisionEval source code, the
template model, or the source input package. Generated models, reports, and logs
are written under `outputs/`.

## Workflow Overview

```text
prepare VA updated CSVs → assemble statewide source model → build regional model → configure VisionEval runtime → run generated region
```

The repository contains code, metadata, and example configs. It does not ship
the Virginia source data, template VisionEval models, or generated results.

The Greater Richmond example has been tested end to end with the prepared
Virginia updated CSV workflow. Other regions should use the same preparation,
assembly, build, and run sequence and may reveal additional source-data issues.

## Requirements

Install R and the RegionBuilder support packages:

```r
install.packages(c("readr", "dplyr", "yaml", "fs", "tibble"))
```

Install these packages into the same R version you will use for RegionBuilder
and VisionEval. If your VisionEval runtime requires R 4.4.2, install the
packages into R 4.4.2.

```powershell
& "$env:LOCALAPPDATA\Programs\R\R-4.4.2\bin\Rscript.exe" -e "install.packages(c('yaml','readr','dplyr','fs','tibble'), repos='https://cloud.r-project.org')"
```

Some R installations use `bin\x64`:

```powershell
& "$env:LOCALAPPDATA\Programs\R\R-4.4.2\bin\x64\Rscript.exe" -e "install.packages(c('yaml','readr','dplyr','fs','tibble'), repos='https://cloud.r-project.org')"
```

Run commands from the repository root.

## Repository Layout

```text
R/                         Reusable R functions
scripts/                   Command-line entry points
configs/                   Example configs to copy before editing
metadata/                  Input manifest and mapping metadata
data_sources/filelist.txt  Expected statewide input file list
tests/fixtures/            Small fixture model for smoke testing
outputs/                   Generated outputs; ignored by git
```

## Quick Smoke Test

Run the fixture smoke test to confirm that RegionBuilder works without external
data:

```powershell
Rscript scripts/run_fixture_smoke.R
```

Expected outputs:

```text
outputs/generated_models/fixture_smoke/
outputs/reports/fixture_smoke_validation.csv
```

## Prepare Virginia Updated CSVs

Before assembling the statewide source model, normalize the Virginia updated CSV
folder into the input contract expected by this project.

```powershell
Rscript scripts/prepare_updatedcsvs_va_inputs.R "C:/path/to/updatedcsvs"
```

Pass your own `updatedcsvs` path explicitly. Do not rely on machine-specific
defaults.

This step is safe to rerun. It validates and standardizes the updated CSVs used
by the statewide assembly step. When changes are needed, it writes backups
outside the updated CSV folder so backup files are not mistaken for model
inputs.

The preparation step is intended for Virginia statewide input packages. It
preserves geography IDs as text, checks required year coverage, applies
documented VisionEval compatibility adjustments, and verifies that required
support files such as `deflators.csv` are available.

If you are using an already prepared input package, this step should complete
without changes and serves as a validation check.

## Assemble Statewide Source Model

Copy the example statewide assembly config:

```powershell
Copy-Item configs/statewide_assembly.example.yml configs/statewide_assembly.yml
```

Edit `configs/statewide_assembly.yml` for your template model and prepared
updated CSV folder:

```yaml
paths:
  template_model_dir: C:/path/to/template_model
  updated_csv_dir: C:/path/to/updatedcsvs
  filelist_path: data_sources/filelist.txt
  manual_mapping_path: metadata/statewide_manual_file_mappings.csv
  column_renames_path: metadata/statewide_column_renames.csv
  geography_file: geo.csv
  geography_destination: defs/geo.csv
  output_model_dir: outputs/generated_models/statewide_va_clean
  report_path: outputs/reports/statewide_assembly_report.csv

explicit_file_injections:
  - source: deflators.csv
    destination: defs/deflators.csv
    notes: Inject updated deflators file into defs/deflators.csv.

required_deflator_years:
  - 2024

overwrite_output: true
```

Run statewide assembly:

```powershell
Rscript scripts/assemble_statewide_model.R configs/statewide_assembly.yml
```

The assembly script copies the template model into:

```text
outputs/generated_models/statewide_va_clean
```

Then it injects the prepared statewide CSVs into that generated copy according
to `data_sources/filelist.txt`, metadata mappings, column rename rules, and
explicit file injections.

Review the reports before building regions:

```text
outputs/reports/statewide_assembly_report.csv
outputs/reports/statewide_column_rename_report.csv
```

Resolve missing, ambiguous, or unmapped required files before continuing.

## Build a Regional Model

Copy the example region config:

```powershell
Copy-Item configs/region.example.yml configs/my_region.yml
```

Edit `configs/my_region.yml`:

```yaml
region:
  name: my_region
  model_region: My Region
  scenario: Base
  description: VERSPM for My Region model
  base_year: 2024
  years:
    - 2024
    - 2045
  mareas:
    - Example Marea
  region_geo_values:
    - Virginia
  czone_mode: auto

paths:
  source_model_dir: outputs/generated_models/statewide_va_clean
  output_model_dir: outputs/generated_models/my_region
  validation_report: outputs/reports/my_region_validation.csv
  manifest: metadata/input_manifest.csv
  geography_file: defs/geo.csv
```

The geography crosswalk is authoritative. Select the region by listing Mareas;
RegionBuilder derives the allowed Azones and Bzones from the filtered geography
file. `czone_mode: auto` writes VisionEval-compatible `NA` Czone values when
the source geography has no meaningful Czone values.

Run the regional build:

```powershell
Rscript scripts/build_region_model.R configs/my_region.yml
```

Expected outputs:

```text
outputs/generated_models/my_region/
outputs/reports/my_region_validation.csv
```

The generated folder is a runnable VisionEval model structure. VisionEval
creates `results/` when the model is run.

## Configure VisionEval Runtime

VisionEval is not included in this repository. Configure the local runtime by
copying the example config:

```powershell
Copy-Item configs/local_runtime.example.yml configs/local_runtime.yml
```

`configs/local_runtime.yml` is ignored by git and may contain paths specific to
your computer.

Set `ve_home` to the folder that contains `VisionEval.R`, not to the file
itself:

```yaml
ve_home: "C:/Path/To/Folder/Containing/VisionEval.R"
ve_runtime: "outputs/generated_models"

# Optional. PowerShell wrappers can use this path to launch the matching Rscript.
rscript: "C:/Path/To/R-4.4.2/bin/Rscript.exe"
```

Use forward slashes in YAML paths.

On Windows, the `.cmd` wrappers are the recommended run path. They avoid common
PowerShell script execution-policy blocks and use `VE_RSCRIPT` when it is set.

Set `VE_RSCRIPT` to the R version required by your installed VisionEval runtime:

```powershell
$env:VE_RSCRIPT = "$env:LOCALAPPDATA\Programs\R\R-4.4.2\bin\Rscript.exe"
```

Some R installations put `Rscript.exe` under `bin\x64`:

```powershell
$env:VE_RSCRIPT = "$env:LOCALAPPDATA\Programs\R\R-4.4.2\bin\x64\Rscript.exe"
```

Check the runtime:

```cmd
scripts\check_visioneval_runtime.cmd
```

A usable runtime should report that `VE_HOME` exists, `VisionEval.R` exists,
and VisionEval startup succeeds.

PowerShell `.ps1` wrappers are optional advanced alternatives. They may require
per-command execution-policy handling:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\check_visioneval_runtime.ps1
```

The `.cmd` wrappers remain the primary recommended Windows path.

## Run a Generated Region

After preparing inputs, assembling the statewide model, building the region, and
configuring the runtime, run the generated region model:

```cmd
scripts\run_region_model.cmd greater_richmond
```

Replace `greater_richmond` with the generated model folder name.

The wrapper sets the VisionEval runtime context and runs the VE-3 model object
API internally:

```r
model <- openModel("greater_richmond")
model$run()
```

Results are written under:

```text
outputs/generated_models/<region_name>/results/
```

Recommended Windows command sequence:

```powershell
Rscript scripts/prepare_updatedcsvs_va_inputs.R "C:/path/to/updatedcsvs"
Rscript scripts/assemble_statewide_model.R configs/statewide_assembly.yml
Rscript scripts/build_region_model.R configs/greater_richmond.yml
$env:VE_RSCRIPT = "$env:LOCALAPPDATA\Programs\R\R-4.4.2\bin\Rscript.exe"
```

```cmd
scripts\check_visioneval_runtime.cmd
scripts\run_region_model.cmd greater_richmond
```

## Manifest Rules

The regional build uses the configured manifest to determine how each file is
handled. A manifest row has:

```text
file,geo_level,action,notes
```

Allowed `geo_level` values:

```text
Region, Marea, Azone, Bzone, Czone
```

Allowed `action` values:

| Action | Meaning |
| --- | --- |
| `filter_geo` | Keep rows whose `Geo` value belongs to the allowed geography list for that file. |
| `copy` | Copy the file unchanged. |
| `review` | Skip the file and record it in the validation report. |

The generated geography file is written from the filtered statewide geography
file and should not be listed as a copied manifest row.

## Generated Files and Local Configs

Generated files are written under:

```text
outputs/generated_models/
outputs/reports/
outputs/logs/
```

Local configs are excluded from git because they contain machine-specific
paths. Copy the examples and edit the copies:

```text
configs/statewide_assembly.example.yml -> configs/statewide_assembly.yml
configs/region.example.yml             -> configs/my_region.yml
configs/local_runtime.example.yml      -> configs/local_runtime.yml
```

Only example config files are intended to be shared in the repository.
