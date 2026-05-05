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

## Fresh post-consolidation model errors

Source log:

```text
outputs/generated_models/greater_richmond/results/Log_2026-05-05_16-25-28.014935.txt
```

Unique remaining errors from the fresh log:

| module | input_file | error_type | specific_fields_or_keys | likely root cause | safe automatic repair? | recommended fix location |
|---|---|---|---|---|---|---|
| `VELandUse::Calculate4DMeasures` | `bzone_unprotected_area.csv` | missing Year column / missing year coverage | `Year`; `Geo` present | Upstream static Bzone area file had no `Year`, but the module is grouped by `Year` or `RunYear`. | Yes. Static area rows were expanded to `2024` and `2045`. | `scripts/prepare_updatedcsvs_va_inputs.R` |
| `VEHouseholdVehicles::CreateVehicleTable` | `azone_carsvc_characteristics.csv` | encoding/text corruption | `0xA0` NBSP artifacts in numeric fields | Upstream `01_azone_carsvc_characteristic.csv` had raw NBSP bytes that caused base R CSV parsing to fail. | Yes. NBSP bytes were replaced with spaces and fields were trimmed before UTF-8 CSV output. | `scripts/prepare_updatedcsvs_va_inputs.R` |
| `VEHouseholdVehicles::AssignVehicleAge` | `azone_hh_veh_mean_age.csv` | invalid numeric values or domain constraints | `AutoMeanAge >= 14`, `LtTrkMeanAge >= 14`; includes `Powhatan County` `2045` in Greater Richmond | Source vehicle age values violate VisionEval prohibit constraints. | No. Clipping or substituting vehicle ages is analytically meaningful. | source data/manual review |
| `VEHouseholdVehicles::CalculateVehicleOwnCost` | `azone_payd_insurance_prop.csv` | missing geography/year rows | Greater Richmond Azones for `2024` and `2045` | No updated PAYD file exists in `updatedcsvs`; the template file only has non-VA placeholder Azones and filters to a header-only regional file. | No. PAYD values are policy-sensitive. | source data/manual review; optionally mark as review-blocking in `input_manifest.csv` behavior |
| `VEPowertrainsAndFuels::Initialize` | `marea_transit_fuel.csv` | incomplete fuel/powertrain/transit fields | `Van*` and `Bus*` fields | Selected Mareas have mixed coverage: Richmond City has values while other selected counties are blank. | No. Filling transit fuel shares would fabricate assumptions. | source data/manual review |
| `VEPowertrainsAndFuels::Initialize` | `marea_transit_powertrain_prop.csv` | incomplete fuel/powertrain/transit fields | `Van*` and `Bus*` fields | Selected Mareas have mixed coverage: Richmond City has values while other selected counties are blank. | No. Filling transit powertrain shares would fabricate assumptions. | source data/manual review |

Grouped categories:

- missing Year column / missing year coverage: `bzone_unprotected_area.csv`
- schema/field-name mismatch: none in this fresh log
- encoding/text corruption: `azone_carsvc_characteristics.csv`
- invalid numeric values or domain constraints: `azone_hh_veh_mean_age.csv`
- missing geography/year rows: `azone_payd_insurance_prop.csv`
- incomplete fuel/powertrain/transit fields: `marea_transit_fuel.csv`,
  `marea_transit_powertrain_prop.csv`

Repairs implemented after diagnosis:

- `scripts/prepare_updatedcsvs_va_inputs.R` now expands static
  `29_bzone_unprotected_area.csv` rows to required model years `2024` and
  `2045`.
- `scripts/prepare_updatedcsvs_va_inputs.R` now normalizes NBSP text artifacts
  in `01_azone_carsvc_characteristic.csv` and rewrites the CSV as parseable
  UTF-8.

Manual-review items intentionally left unchanged:

- Vehicle mean ages at or above 14.
- PAYD insurance rows for Virginia Azones and model years.
- Transit fuel and transit powertrain fields for selected Mareas.

Post-repair rerun:

- Ran `Rscript scripts/prepare_updatedcsvs_va_inputs.R`.
- Ran `Rscript scripts/assemble_statewide_model.R configs/statewide_assembly.yml`.
- Ran `Rscript scripts/build_region_model.R configs/greater_richmond.yml`.
- Ran `scripts/run_region_model.cmd greater_richmond` with `VE_RSCRIPT` set to
  R 4.4.2.

New log:

```text
outputs/generated_models/greater_richmond/results/Log_2026-05-05_16-39-45.199563.txt
```

The model progressed past the repaired Bzone `Year` error and Azone
car-service encoding error. Remaining errors are narrower and match the
manual-review items above: vehicle mean ages prohibited by VisionEval, missing
PAYD rows for Greater Richmond Azones in `2024` and `2045`, and incomplete
Marea transit fuel/powertrain fields.

## Vehicle age, PAYD, and transit validation update

Source log addressed:

```text
outputs/generated_models/greater_richmond/results/Log_2026-05-05_16-39-45.199563.txt
```

Vehicle mean age:

- `scripts/prepare_updatedcsvs_va_inputs.R` now applies a deliberate
  VisionEval compatibility cap to `09_azone_hh_veh_mean_age.csv`.
- `AutoMeanAge` and `LtTrkMeanAge` values `>= 14` are capped to `13.99`.
- The first cap pass changed 42 rows and 84 values.
- A follow-up idempotency pass found zero rows still `>= 14` and made no file
  changes.

PAYD status:

- The current updated source file is
  `C:/Users/Jameson.Clements/source/VE_Models/models/updatedcsvs/azone_payd_insurance_prop.csv`.
- It has columns `Geo`, `Year`, `PaydHhProp`.
- It has 266 rows, 133 Geo values, and years `2024` and `2045`.
- It includes all 16 required Greater Richmond Geo/Year combinations.
- After rerunning assembly, `outputs/reports/statewide_assembly_report.csv`
  shows `azone_payd_insurance_prop.csv` as an exact injected match. No
  synthetic PAYD rows were created.

Marea transit investigation:

- Compared updatedcsvs, assembled statewide, generated Greater Richmond, and
  SayedMM template versions of `marea_transit_fuel.csv` and
  `marea_transit_powertrain_prop.csv`.
- Updated and assembled statewide files have matching `Geo`/`Year` coverage:
  266 rows, 133 Geo values, years `2024` and `2045`.
- Generated Greater Richmond files have matching `Geo`/`Year` coverage:
  16 rows for 8 selected Mareas and 2 years.
- Schemas match the SayedMM template columns for Van and Bus fields.
- The updated source files were row-consistent: no partial Van rows and no
  partial Bus rows.
- VisionEval's `VEPowertrainsAndFuels::Initialize` checks these mode groups
  globally: every value in a Van or Bus field group must be populated, or the
  entire field group must be NA.
- For Greater Richmond, non-Richmond selected counties have zero `DRRevMi`,
  `VPRevMi`, `MBRevMi`, and `RBRevMi`; Richmond City has real Van and Bus fuel
  and powertrain values.
- The deterministic transit repair fills only all-NA Van or Bus rows where the
  corresponding transit service is zero. It uses VisionEval defaults:
  Van fuel `0/1/0`, Bus fuel `1/0/0`, Van powertrain `1/0/0`, and Bus
  powertrain `1/0/0`.
- The repair does not overwrite populated Richmond City transit values.
- Statewide source rows with all-NA Bus values and nonzero bus service remain
  manual-review items. The prepare summary reports these and leaves them
  unchanged.

Post-update rerun:

- `Rscript scripts/prepare_updatedcsvs_va_inputs.R`: passed. A second pass was
  idempotent and created no backup directory.
- `Rscript scripts/assemble_statewide_model.R configs/statewide_assembly.yml`:
  passed with 51 injected files, 1 template-existing file, 0 missing files, and
  0 ambiguous files.
- `Rscript scripts/build_region_model.R configs/greater_richmond.yml`: passed
  with no-Czone mode still reported as absent.
- `scripts/run_region_model.cmd greater_richmond` with `VE_RSCRIPT` set to
  `C:/Users/Jameson.Clements/AppData/Local/Programs/R/R-4.4.2/bin/Rscript.exe`
  progressed through initialization and the prior input-validation failures.

Latest log:

```text
outputs/generated_models/greater_richmond/results/Log_2026-05-05_17-29-40.813554.txt
```

Latest result:

- Previous errors for vehicle mean age, PAYD coverage, and incomplete transit
  Van/Bus groups are gone.
- The run reached 2045 `VETravelPerformance::CalculateRoadPerformance`.
- New failure:
  `missing value where TRUE/FALSE needed` in
  `if (abs(1 - LastDvmtRatio/DvmtRatio) < 1e-04) (break)()`.
- The log also records a 2045 high-density warning for Bzone `517600205022`
  with density `104.22`, but the terminal failure is the missing-value error in
  road performance.

## Road performance convergence failure

Source failure log:

```text
outputs/generated_models/greater_richmond/results/Log_2026-05-05_17-29-40.813554.txt
```

Failure location:

- Module: `VETravelPerformance::CalculateRoadPerformance`
- Year: `2045`
- Source: `VETravelPerformance/R/CalculateRoadPerformance.R`
- Failing expression near line 1693:
  `if(abs(1 - LastDvmtRatio / DvmtRatio) < 0.0001) break()`

Diagnostic report:

```text
outputs/reports/greater_richmond_road_performance_diagnostics.csv
```

Findings:

- `CalculateRoadPerformance` computes
  `DvmtRatio <- Dvmt_Rc["Fwy"] / Dvmt_Rc["Art"]`.
- The failing run had non-finite heavy-truck road DVMT values before that
  convergence check:
  `HvyTrkFwyDvmt = NaN` for all Greater Richmond Mareas and
  `HvyTrkArtDvmt = NaN/Inf`.
- Those values were created upstream by
  `VETravelPerformance::CalculateRoadDvmt`.
- The root input was `inputs/region_base_year_dvmt.csv`, copied from
  `updatedcsvs/marearegion/region_base_year_dvmt.csv`.
- The file had `HvyTrkDvmt = NA` and blank `StateAbbrLookup`.
- With blank `StateAbbrLookup`, VisionEval used its metropolitan fallback for
  regional heavy-truck DVMT. That fallback divided nonzero
  `UrbanHvyTrkDvmt` by zero modeled `UrbanPop` for some selected Mareas,
  creating `Inf` regional heavy-truck DVMT and `Inf` growth factors.
- Zero freeway lane miles and zero freeway heavy-truck split proportions were
  also present, but they were not the root non-finite source after the repair.

Repair:

- `scripts/prepare_updatedcsvs_va_inputs.R` now repairs
  `region_base_year_dvmt.csv` only when `StateAbbrLookup` is blank and
  `HvyTrkDvmt` is NA.
- In that case it sets `StateAbbrLookup` to `VA`, matching the generated model
  state and allowing VisionEval to compute regional heavy-truck DVMT from its
  state default rates rather than the broken metropolitan fallback.
- This does not fabricate a road-capacity or VMT value directly; it selects
  VisionEval's documented default calculation path for a Virginia model.

Post-repair rerun:

- `Rscript scripts/prepare_updatedcsvs_va_inputs.R`: passed. A second pass was
  idempotent.
- `Rscript scripts/assemble_statewide_model.R configs/statewide_assembly.yml`:
  passed.
- `Rscript scripts/build_region_model.R configs/greater_richmond.yml`: passed.
- `scripts/run_region_model.cmd greater_richmond` with `VE_RSCRIPT` set to
  `C:/Users/Jameson.Clements/AppData/Local/Programs/R/R-4.4.2/bin/Rscript.exe`
  completed successfully.

Successful run log:

```text
outputs/generated_models/greater_richmond/results/Log_2026-05-05_17-49-42.667864.txt
```

The road performance error is gone. The model status is `Run Complete` for
stage `greater_richmond`. The remaining log warning is the existing 2045
high-density warning for Bzone `517600205022`.
