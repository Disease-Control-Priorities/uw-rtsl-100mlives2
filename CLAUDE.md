# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

R modeling project for the Resolve to Save Lives "100 million lives" paper. It estimates CVD deaths delayed in 2025–2050 from four interventions: hypertension control, sodium reduction, trans-fat (TFA) elimination and statins. It adapts the Kontis et al. (2019) multistate framework to GBD 2023 inputs and UN WPP 2024 populations. There is no package build, linter or automated test suite (`tests/` holds only a README). You check work by re-running scripts and inspecting the outputs.

## Running things

All scripts use **absolute paths** that are hardcoded to the author's OneDrive folder (`wd <- "C:/Users/wrgar/OneDrive - UW/.../uw-rtsl-100mlives2/"`). Path globals are defined in `code/0. master.R` and redefined in the reporting Rmd:

- `wd_raw` = `data-raw/`: original GBD, UN WPP, NCD-RisC, sodium, TFA and statin sources. These are gitignored except `*.md`, so they are not in the repo.
- `wd_data` = `data/processed/`: prepared model inputs.
- `wd_outp` = `output/`
- `wd_temp` = `temp/`: per-location intermediate files. Gitignored.

The pipeline stage scripts in `code/` are **not standalone**. They expect the globals that `0. master.R` sets up: the path variables, the loaded libraries, `dx_include`, `cause_map`/`cause_cols`, the `run_*` flags, and the functions from `functions_review_6_100.R`. Several stages also call `setwd()` (to `wd_raw`, `wd_temp` or `wd`), so relative paths change from one stage to the next. To run a single stage, first run the setup section of `0. master.R` (through `source("functions_review_6_100.R")`) and then source that stage.

**Known mismatch:** the `source()` calls in `0. master.R` use old filenames such as `"1.get_base_rates_100_gbd23.R"`, `"5.calibration_100.R"` and `"7.model_100_multiplicative_func_new3.R"`. The real files have a space after the number and some carry a `_gbd23`/`_noaroc` suffix (for example `"5. calibration_100_gbd23.R"`). Use the real filenames.

Render reports and the manuscript with rmarkdown:

```
Rscript -e "rmarkdown::render('reports/UWRTSL-100MLivesRMD_Output.Rmd')"
Rscript -e "rmarkdown::render('manuscript/manuscript-100mlives2.Rmd')"   # → Word via reference.docx + word-layout.lua
```

## Pipeline and data flow

| Stage | Script (`code/`) | Main outputs |
|---|---|---|
| 1 | `1. get_base_population_100.R` | `data/processed/UN2024/PopulationsSingleAge0050.rds`, `PopulationsAge20_*.csv`; `data-raw/GBD/totalpop_baseline_ihme.rds` |
| 1 | `1. get_base_rates_100_gbd23.R` | `baseline_rates_part{1..5}.rds`, root `locs.rds`, `data-raw/GBD/temp_1baseline_rates_gbd23.rds` (reused by stages 2, 5, 6) |
| 2 | `2. get_tps_100_gbd23.R` | `tps_inpt_part{1..5}.rds` |
| 2 | `2. get_tps_bgmx_100_gbd23.R` | `tps_bgmx_{,all_,cvd_}forecasted.rds`, `tps_bgmx_cvd_ihme.rds` (background-mortality forecasts) |
| 3 | `3. risk_factors_100.R` (+ `_sodium.R` validation vs older GBD rounds) | `Sodium/sodium_data.rds`, `TFAPolicy/tfa_data.rds`, `Statins/af_statins.rds` |
| 4 | `4. interventions_100_tfa2_statins2.R` | `Sodium/sodium_policy_scenarios.rds`, `TFAPolicy/tfa_policy_scenarios.rds`, `Statins/statin_data.rds`, HTN coverage functions (`covfxn2.csv`) |
| 5 | `5. calibration_100_gbd23.R` | parallel calibration (`makeCluster(14)`) → `adjusted_searo_part{1..10}.rds` |
| 6 | `6. adjustments_100_gbd23.R` | root `adjustments2023_age.csv` |
| 7 | `7. model_100_multiplicative_func_new3_gbd23_noaroc.R` | `output/out_model/model_output_part_<Country>.rds` + `log_<Country>.txt` |

Large tables are split into `*_partN.rds` files and read back with `list.files(pattern=...)` followed by `rbindlist`. Some inputs live at the **repo root**, not under `data/`: `bp_data6.csv`, `add_cov_data.csv`, `Country_groupings_extended.csv`, `ettehad_rr_bp_reduction_10mmHg.csv`, `adjustments2023_age.csv`, `wpp.adj.Rda`, `locs.rds`.

## Model (stage 7) structure

- `project.all(Country, ...)` runs the multistate well/sick/dead projection for one country. Causes are IHD, ischemic stroke, intracerebral hemorrhage and hypertensive heart disease. Intervention modules adjust incidence (`eff_ir`) and case fatality (`eff_cf`) multiplicatively:
  - `calculate_antihypertensive_impact_etihad`, which uses Ettehad BP-reduction RRs
  - `calculate_sodium_impact_etihad`
  - `calculate_tfa_impact`
  - `calculate_statins_impact`
- `run_multiple_scenarios()` loops over the named `scenarios` list: `baseline`, `bp_only`, `sodium_only`, `tfa_only`, `statins_only`, `bp_sodium`, `bp_sodium_tfa` and `all_four`.
- Scenario parameters are globals defined just before the parallel run. They include `target_control` (0.5 by 2040), `salteff` (30% by 2030), the TFA target (0 starting 2028), statin coverage (0.60 by 2050), the adherence values and `drugcov`.
- Countries run in parallel with `foreach`/`doParallel` (`ncores <- 8`). **Any new helper function or data object used inside `project.all` must be added to the `clusterExport` varlist**, otherwise the workers fail. Errors are caught per country and written to that country's log file.
- `validate_intervention_results()` checks for negative or NA states, mismatches in population conservation, and effect multipliers outside [0, 2].

`R/functions_review_6_100.R` duplicates `code/functions_review_6_100.R`. The master script sources the `code/` copy. `R/coverage_newfig.R` contains coverage-figure code.

## Reporting and manuscript

- `reports/UWRTSL-100MLivesRMD_Output.Rmd` is the main analysis/report. It reads `output/out_model/*.rds` and the processed data, and it writes `output/out_*.png` figures and tables.
- `manuscript/manuscript-100mlives2.Rmd` knits to Word. Its tables are read from `manuscript/manuscript-100mlives2.xlsx`, the "single source of truth". That workbook has one sheet per table (`T1_Scenarios`, `T2_DeathsDelayed`, `TS1_Regions` … `TS9_Assumptions`) plus `Index` and `Figures` sheets. Each table sheet has its title in row 1, headers in row 3, data from row 4, then a blank row and a Notes row. Figures come from `manuscript/figures/`.
- `dev/prompt-reproducible-manuscript.md` describes a planned refactor. The goal is a new `reports/manuscript-100mlives2-artifacts.Rmd` that generates all manuscript artifacts (`manuscript/artifacts/*.rds`, `manuscript/tables/*.csv`, `manuscript/figures/*.png`, the regenerated xlsx), so that the manuscript Rmd only loads and displays them. Read that file before working on manuscript reproducibility.
