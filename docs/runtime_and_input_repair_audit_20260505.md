# Runtime and Input Repair Audit - 2026-05-05

## Scope

This audit consolidates the current VE_RegionBuilder runtime, statewide assembly,
updatedcsvs repair, and Greater Richmond model-run state after the rapid repair
work on 2026-05-05.

## Current Git State

Modified tracked files:

- `R/assemble_statewide_model.R`
- `R/build_geo_mask.R`
- `R/subset_inputs.R`
- `README.md`
- `configs/region.example.yml`
- `configs/statewide_assembly.example.yml`
- `metadata/statewide_manual_file_mappings.csv`
- `scripts/assemble_statewide_model.R`
- `scripts/build_region_model.R`

Untracked scripts under `scripts/`:

- `scripts/prepare_updatedcsvs_va_inputs.R`
- `scripts/repair_latlon_missing_2045.R`
- `scripts/repair_updatedcsvs_inputs.R`
- `scripts/repair_updatedcsvs_schema_years.R`

Generated outputs that should stay out of git:

- `outputs/generated_models/`
- `outputs/reports/`
- `outputs/logs/`

Backup folders under `C:/Users/Jameson.Clements/source/VE_Models/models`:

- `_backup_before_repairs_20260505_160431`
- `_backup_latlon_repair_20260505_161152`
- `_backup_schema_year_repairs_20260505_161441`
- `_backup_prepare_updatedcsvs_va_inputs_20260505_162422`

No backup folders were found under
`C:/Users/Jameson.Clements/source/VE_Models/models/updatedcsvs` during the final
audit check.

## Runtime and Runner Problems Solved

- VisionEval runtime loading works when `VE_HOME` points to the built
  VisionEval runtime and `VE_RSCRIPT` points to R 4.4.2.
- The Windows `.cmd` wrappers are the preferred run path when `VE_RSCRIPT` is
  set.
- The region runner uses the VE-3 API:
  `openModel(region_name)` followed by `model$run()`.
- The runner was not changed back to `initializeModel()`.

## Model Generation Problems Solved

- Region configs can carry `base_year: 2024` and `years: [2024, 2045]`.
- Generated `visioneval.cnf` is rewritten for `Region`, `Scenario`,
  `Description`, `BaseYear`, and `Years`.
- No-Czone geography mode is supported for the Virginia source geography.
  Generated `defs/geo.csv` writes VisionEval-compatible `NA` Czone values.
- Statewide assembly injects `deflators.csv` into `defs/deflators.csv` through
  explicit file injection.
- `defs/deflators.csv` is validated after statewide assembly for `Year`,
  `Value`, nonblank values, and required year `2024`.
- Statewide assembly report now marks unused updated CSVs as informational.
  Missing, ambiguous, and no-template-location expected files are
  review-blocking.
- Column renames are idempotent. If `old_column` is absent but `new_column`
  already exists, the rename is recorded as `already_satisfied` instead of
  failing. This fixes the stale `GeoIDTxt -> Geo` failure for
  `bzone_unprotected_area.csv`.

## Assembly Metadata Behavior

- `data_sources/filelist.txt` defines expected statewide input files.
- Expected file destinations are resolved from the template model. When multiple
  template files match, the assembler prefers a single `inputs/` match.
- `metadata/statewide_manual_file_mappings.csv` handles approved filename drift,
  including `bzone_travel_demand_mgt.csv` from
  `28_bzone_travel_demand_management.csv`.
- `configs/statewide_assembly.yml` now defines explicit file injections,
  including `deflators.csv -> defs/deflators.csv`.
- `geo.csv -> defs/geo.csv` remains an explicit geography injection.
- Updated CSVs not used by expected-file matching or explicit injection are
  appended to the assembly report as `unused_updated_csv` with informational
  severity.

## Upstream Input Issues Discovered

Known updatedcsvs issues repaired manually or by the consolidated script:

- `deflators.csv` needed to exist in `updatedcsvs` and include 2024.
- `21_bzone_dwelling_units.csv` had rows with zero total dwelling units; rows
  with `SFDU + MFDU + GQDU == 0` were repaired by setting `SFDU=1`.
- `23_bzone_hh_inc_qrtl_prop.csv` had corrupted or scientific-notation `Geo`
  values; `Geo` was repaired from `geo.csv` Bzone order by year after row-count
  validation.
- `24_bzone_lat_lon.csv` needed complete 2045 rows for every 2024 `Geo`. A
  previous coarse repair created duplicate 2045 rows; the consolidated script
  rebuilt 2045 rows from 2024 rows.
- `29_bzone_unprotected_area.csv` needed schema columns `Geo`, `UrbanArea`,
  `TownArea`, and `RuralArea`.
- `25_bzone_network_design.csv` needed `D3bpo4`; `D3bp04` is mapped when
  present.
- `28_bzone_travel_demand_management.csv` needed `Geo` repaired from `geo.csv`
  Bzone order by year and complete 2045 rows.
- `20_bzone_carsvc_availability.csv` had stale scientific-notation 2045 rows
  and an embedded header row after earlier repairs. The consolidated script
  dropped the embedded header and rebuilt 2045 rows from 2024 rows.

## Repair Scripts

One-off scripts currently present:

- `scripts/repair_updatedcsvs_inputs.R`
- `scripts/repair_latlon_missing_2045.R`
- `scripts/repair_updatedcsvs_schema_years.R`

Durable replacement:

- `scripts/prepare_updatedcsvs_va_inputs.R`

The durable script:

- operates only on `updatedcsvs`;
- writes backups outside `updatedcsvs`, under the parent `models` folder;
- reads CSV columns as character;
- repairs the known VA updatedcsvs issues listed above;
- validates row counts before row-order `Geo` replacement;
- validates no backup folders exist under `updatedcsvs`;
- validates repaired files and required columns;
- validates no scientific-notation `Geo` values remain in Bzone CSVs;
- validates required 2024/2045 coverage for files that need derived 2045 rows;
- validates `deflators.csv` includes 2024;
- prints a repair summary.

The one-off scripts should be treated as superseded audit artifacts unless a
specific comparison against their previous behavior is needed.

## Commands Run In Final Chain

Prepare updatedcsvs:

```powershell
Rscript scripts/prepare_updatedcsvs_va_inputs.R
```

Statewide assembly:

```powershell
Rscript scripts/assemble_statewide_model.R configs/statewide_assembly.yml
```

Final assembly result:

- Expected files: 52
- Injected files: 50
- Missing files: 0
- Ambiguous files: 0
- No template location: 0
- Unused updated CSVs: 3, all informational
- `deflators.csv` status: `injected`
- `bzone_unprotected_area.csv` column rename status: `already_satisfied`

Region build:

```powershell
Rscript scripts/build_region_model.R configs/greater_richmond.yml
```

Model run:

```powershell
$env:VE_RSCRIPT = "$env:LOCALAPPDATA\Programs\R\R-4.4.2\bin\Rscript.exe"
scripts\run_region_model.cmd greater_richmond
```

The first run attempt without `VE_RSCRIPT` failed before model load because
plain `Rscript` was not R 4.4.2. With `VE_RSCRIPT` set, VisionEval loaded and
the generated `greater_richmond` model opened through `openModel()`.

## Remaining Errors From Fresh Run

Fresh log:

```text
outputs/generated_models/greater_richmond/results/Log_2026-05-05_16-25-28.014935.txt
```

Remaining VisionEval input errors:

- `bzone_unprotected_area.csv` is missing required `Year` and/or `Geo` for a
  module grouped by `Year` or `RunYear`. The current file has `Geo` but no
  `Year`.
- `azone_carsvc_characteristics.csv` has an invalid multibyte string at
  `<a0>`.
- `azone_hh_veh_mean_age.csv` has `AutoMeanAge` and `LtTrkMeanAge` values
  prohibited by VisionEval because they are `>= 14`.
- `azone_payd_insurance_prop.csv` is missing required 2024 and 2045 rows for
  the Greater Richmond Azones.
- `marea_transit_fuel.csv` has incomplete `Van` and `Bus` fields.
- `marea_transit_powertrain_prop.csv` has incomplete `Van` and `Bus` fields.

These failures are from a clean prepare, assemble, build, and run chain. They
are not from stale or incomplete generated artifacts.

## Cleanup Candidates

- Decide whether to remove or archive the three one-off repair scripts after
  reviewing `scripts/prepare_updatedcsvs_va_inputs.R`.
- Remove the obsolete `deflators.csv` manual mapping from
  `metadata/statewide_manual_file_mappings.csv`; explicit file injection now
  owns that behavior.
- Consider adding `rscript:` to `configs/local_runtime.yml` or teaching the
  `.cmd` wrappers to read it, so plain `.cmd` runs do not accidentally use the
  wrong R version when `VE_RSCRIPT` is unset.
- Keep all backup folders outside `updatedcsvs`; do not commit backup folders.
- Keep generated outputs under `outputs/` out of git.

## Recommended Next Steps

1. Review and keep `scripts/prepare_updatedcsvs_va_inputs.R` as the durable VA
   updatedcsvs preparation step.
2. Do not patch generated model files directly. Fix remaining model-run errors
   in upstream updatedcsvs or manifest/config rules, then rerun the full chain.
3. Address `bzone_unprotected_area.csv` first by determining whether Year should
   be added upstream from model years or whether the manifest/action for that
   file should change.
4. Repair or replace the invalid text in `azone_carsvc_characteristics.csv`
   upstream using character-safe CSV handling.
5. Decide the policy for vehicle mean age values `>= 14` before clipping or
   replacing them.
6. Fill or explicitly mark missing PAYD insurance, transit fuel, and transit
   powertrain fields according to VisionEval expectations.
7. Rerun, in order:
   `prepare_updatedcsvs_va_inputs.R`, statewide assembly, assembly report
   inspection, Greater Richmond build, and Greater Richmond model run.
