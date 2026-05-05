# Input Manifest Notes

`metadata/input_manifest.csv` is the authority for how each statewide input file is handled.

Required columns:

- `file`: path to the source file relative to `paths.source_model_dir`
- `geo_level`: one of `Region`, `Marea`, `Azone`, `Bzone`, or `Czone`
- `action`: one of `filter_geo`, `copy`, or `review`
- `notes`: human-readable context copied into the validation report

The generated `defs/geography.csv` is built directly from the statewide geography crosswalk and should not be listed as a `copy` row in the manifest.

Current Virginia statewide inputs do not define meaningful Czones. RegionBuilder
treats Czone as absent for those inputs and writes VisionEval's literal `NA`
sentinel in `defs/geo.csv`.
