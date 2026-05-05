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
  model_region: My Region
  scenario: Base
  description: VERSPM for My Region model
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

The generated model folder is a runnable VisionEval model structure. It includes the scaffold copied from the assembled statewide source model, filtered regional inputs, generated regional geography, `queries/`, `scripts/`, and root model files such as `visioneval.cnf`. It does not copy `results/`; VisionEval creates `results/` when the model runs.

## Running a Generated Region Model

Before RegionBuilder can run a generated model, it must know where VisionEval is installed. VisionEval is not included in this repository.

Configure VisionEval with a local file:

```powershell
Copy-Item configs/local_runtime.example.yml configs/local_runtime.yml
```

`configs/local_runtime.yml` is ignored by git, so it can contain paths that are specific to your computer.

The correct VisionEval folder is the folder that contains this file:

```text
VisionEval.R
```

VisionEval is often installed somewhere like:

```text
C:/VisionEval
C:/Users/<your-name>/Documents/VisionEval
C:/Users/<your-name>/source/VisionEval
```

To find `VisionEval.R`, search your user folder first:

```powershell
Get-ChildItem "$env:USERPROFILE" -Recurse -Filter "VisionEval.R" -ErrorAction SilentlyContinue |
  Select-Object FullName
```

If that does not find it, search `C:\`. This can take a while:

```powershell
Get-ChildItem "C:\" -Recurse -Filter "VisionEval.R" -ErrorAction SilentlyContinue |
  Select-Object FullName
```

The PowerShell search returns the full path to the `VisionEval.R` file. `ve_home` must be the folder that contains `VisionEval.R`, not the file itself. Do not include `/VisionEval.R` at the end of `ve_home`.

For example, if PowerShell returns:

```text
C:\VisionEval\VisionEval.R
```

then `ve_home` is:

```text
C:/VisionEval
```

Another example:

```text
C:\...\runtime\VisionEval.R
```

becomes:

```yaml
ve_home: "C:/.../runtime"
```

Use forward slashes in YAML paths, even on Windows. Edit `configs/local_runtime.yml`:

```yaml
ve_home: "C:/Path/To/Folder/Containing/VisionEval.R"
ve_runtime: "outputs/generated_models"
# Optional: used by PowerShell wrappers when VisionEval needs a specific R version.
rscript: "C:/Path/To/R-4.4.2/bin/Rscript.exe"
```

`ve_runtime` can stay as `outputs/generated_models` when you run commands from the RegionBuilder repository root.

Check the runtime:

```cmd
scripts\check_visioneval_runtime.cmd
```

The `.cmd` wrappers are recommended on Windows because they avoid common PowerShell script execution-policy blocks. They use `VE_RSCRIPT` when it is set; otherwise they use plain `Rscript` from `PATH`.

A configured runtime should show:

```text
VE_HOME exists: TRUE
VE_HOME/VisionEval.R exists: TRUE
VisionEval startup check: TRUE
```

It is okay if this line is `FALSE`:

```text
Package 'visioneval' visible: FALSE
```

Run a generated region model:

```cmd
scripts\run_region_model.cmd greater_richmond
```

Replace `greater_richmond` with another generated folder name, such as `hampton_roads` or `wppdc`.

After a successful run, outputs are written under:

```text
outputs/generated_models/<region_name>/results/
```

### Find the Matching Rscript

RegionBuilder uses the Rscript executable that launches the script. If VisionEval was built for R 4.4.2, use the `Rscript.exe` from an R 4.4.2 installation.

List installed R versions in common Windows locations:

```powershell
Get-ChildItem "$env:LOCALAPPDATA\Programs\R" -Directory
Get-ChildItem "C:/Program Files/R" -Directory -ErrorAction SilentlyContinue
```

Find available `Rscript.exe` files:

```powershell
Get-ChildItem "$env:LOCALAPPDATA\Programs\R" -Recurse -Filter "Rscript.exe" -ErrorAction SilentlyContinue |
  Select-Object FullName

Get-ChildItem "C:/Program Files/R" -Recurse -Filter "Rscript.exe" -ErrorAction SilentlyContinue |
  Select-Object FullName
```

Choose the `Rscript.exe` under the R version expected by your VisionEval runtime, such as `R-4.4.2`.

The expected sequence is:

1. Find installed R versions.
2. Find `Rscript.exe` files.
3. Pick the `Rscript.exe` under the R version expected by VisionEval.
4. Set `VE_RSCRIPT`.
5. Run `scripts\check_visioneval_runtime.cmd`.
6. Run `scripts\run_region_model.cmd greater_richmond`.

For Windows users, the `.cmd` wrappers are the recommended way to use a matching Rscript without changing PowerShell execution policy. Set `VE_RSCRIPT`, then run:

```powershell
$env:VE_RSCRIPT = "$env:LOCALAPPDATA\Programs\R\R-4.4.2\bin\Rscript.exe"
```

Some R installations put `Rscript.exe` under `bin\x64`:

```powershell
$env:VE_RSCRIPT = "$env:LOCALAPPDATA\Programs\R\R-4.4.2\bin\x64\Rscript.exe"
```

Then run:

```cmd
scripts\check_visioneval_runtime.cmd
scripts\run_region_model.cmd greater_richmond
```

If you use the PowerShell wrappers, they can also read `rscript:` from `configs/local_runtime.yml`:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\check_visioneval_runtime.ps1
powershell -ExecutionPolicy Bypass -File .\scripts\run_region_model.ps1 greater_richmond
```

Direct Rscript commands still work if you prefer them:

```powershell
& "C:/Path/To/R-4.4.2/bin/Rscript.exe" scripts/check_visioneval_runtime.R
& "C:/Path/To/R-4.4.2/bin/Rscript.exe" scripts/run_region_model.R greater_richmond
```

### Optional: Save the Matching Rscript Path

To save `VE_RSCRIPT` for your Windows user:

```powershell
[Environment]::SetEnvironmentVariable(
  "VE_RSCRIPT",
  "$env:LOCALAPPDATA\Programs\R\R-4.4.2\bin\Rscript.exe",
  "User"
)
```

Close and reopen PowerShell after setting it permanently.

### Runtime Troubleshooting

`VisionEval.R` not found:

VisionEval may not be installed on this machine, or it may be installed somewhere outside your user folder. Try the broader `C:\` search above, or reinstall VisionEval and note the install folder.

`check_visioneval_runtime.R` still says `VE_HOME` is unset:

Make sure you copied `configs/local_runtime.example.yml` to exactly `configs/local_runtime.yml`. Check that the file has a `ve_home:` line and that the path uses forward slashes.

`Package 'visioneval' visible` is `FALSE`:

That is normal for many VisionEval installs. RegionBuilder can still run models if `VE_HOME/VisionEval.R exists` and `VisionEval startup check` are both `TRUE`.

`Incorrect R version for this VisionEval installation`:

RegionBuilder uses whichever `Rscript` command you run. If plain `Rscript` points to R 4.5.2, but your VisionEval runtime was built for R 4.4.2, the runtime check or model run will fail.

Use the matching Rscript explicitly, for example:

```cmd
scripts\check_visioneval_runtime.cmd
scripts\run_region_model.cmd greater_richmond
```

The `.cmd` wrappers use `VE_RSCRIPT` first, then plain `Rscript` from `PATH`. The optional `.ps1` wrappers also support `configs/local_runtime.yml` field `rscript:`. You can also point `ve_home` to a VisionEval runtime built for the active R version reported by:

```powershell
Rscript --version
```

`incomplete final line found on configs/local_runtime.yml`:

This warning is harmless. Open `configs/local_runtime.yml`, put your cursor at the end of the file, press Enter once, and save it so the YAML file ends with a final blank line.

Advanced option:

Instead of `configs/local_runtime.yml`, you can set environment variables in PowerShell. The local config file is usually simpler.

```powershell
$env:VE_HOME = "C:/VisionEval"
$env:VE_RUNTIME = "outputs/generated_models"
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
configs/local_runtime.example.yml       ->  configs/local_runtime.yml
```

Only the example config files are intended to be shared in the repository.
