# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

R modeling project for the Resolve to Save Lives "100 million lives" paper. It estimates CVD deaths delayed in 2026–2050 from four interventions: hypertension control, sodium reduction, trans-fat (TFA) elimination and statins. It adapts the Kontis et al. (2019) multistate framework to GBD 2023 inputs and UN WPP 2024 populations. There is no package build, linter or automated test suite (`tests/` holds only a README). You check work by re-running scripts and inspecting the outputs (stage 5 and stage 6 also run their own validation checks and stop on failure).

## Running the pipeline

`code/0. master.R` is the single entry point. It loads the libraries, defines the path globals, sources `code/functions_review_6_100.R`, declares all settings, then sources each stage. It takes stage numbers as arguments (default: all):

```
Rscript "code/0. master.R" 5 6 7     # calibration, baseline, model
```

Stage scripts are **not standalone**: they need the globals `0. master.R` sets up (paths, libraries, `dx_include`, `cause_map`/`cause_cols`, the `run_*` flags, `cal_config`, `stage7_first_year`). Stage 6 builds `b_rates`, `data.in`, `inc`, `bpcats` and `repYear` **in memory** for stage 7, so stages 6 and 7 must run in the same R session. Some stages call `setwd()` (`wd_raw`, `wd_temp`, `wd`), so relative paths change between stages.

Paths are **absolute**, hardcoded to the author's OneDrive folder (`wd <- "C:/Users/wrgar/OneDrive - UW/.../uw-rtsl-100mlives2/"`):

- `wd_code` = `code/`
- `wd_raw` = `data-raw/`: original GBD, UN WPP, NCD-RisC, sodium, TFA and statin sources. Gitignored except `*.md`.
- `wd_data` = `data/processed/`: prepared model inputs.
- `wd_outp` = `output/`
- `wd_temp` = `temp/`: intermediate files and calibration pilots. Gitignored.

## Pipeline and data flow

| Stage | Script (`code/`) | Main outputs |
|---|---|---|
| 1 | `1. get_base_population_100.R` | `data/processed/UN2024/PopulationsSingleAge0050.rds`, `PopulationsAge20_*.csv`; `data-raw/GBD/totalpop_baseline_ihme.rds` |
| 1 | `1. get_base_rates_100_gbd23.R` | `baseline_rates_part{1..5}.rds`, root `locs.rds`, `data-raw/GBD/temp_1baseline_rates_gbd23.rds` (GBD targets, reused later) |
| 2 | `2. get_tps_100_gbd23.R` | `tps_inpt_part{1..5}.rds` (historical transition probabilities) |
| 2 | `2. get_tps_bgmx_100_gbd23.R` | `tps_bgmx_{,all_,cvd_}forecasted.rds`, `tps_bgmx_cvd_ihme.rds` (background-mortality forecasts) |
| 3 | `3. risk_factors_100.R` (+ `_sodium.R` validation vs older GBD rounds) | `Sodium/sodium_data.rds`, `TFAPolicy/tfa_data.rds`, `Statins/af_statins.rds` |
| 4 | `4.prepare_interventions.R` | `Sodium/sodium_policy_scenarios.rds`, `TFAPolicy/tfa_policy_scenarios.rds`, `Statins/statin_data.rds`, `BloodPressure/hbp_control_data.rds`, `covfxn2.csv` |
| 5 | `5. calibration.R` | `adjusted_searo_part{1..10}.rds` (calibrated historical IR/CF, 2000–2019) and `output/calibration/calibration_*` diagnostics |
| 6 | `6. build_baseline.R` | in-memory projection panel 2017–2050 for stage 7 (no files) |
| 7 | `7. model_100_multiplicative_func_new3_gbd23_noaroc.R` | `output/out_model/model_output_part_<Country>.rds` + `log_<Country>.txt` |

Stages 8 (`8. run_sensitivity.R`) and 9 (`9. run_benchmark.R`) are wired into the master script but the scripts do not exist yet.

Stage 4 is `4.prepare_interventions.R`. Compared with the older `4. interventions_100_tfa2_statins2.R` (kept for reference, not sourced), it:
- weights sodium and TFA means with the IHME baseline population (`totalpop_baseline_ihme.rds`, from stage 1) instead of `totalpop_ihme.rds`;
- carries Indonesia's 2022 TFA value forward to 2023–2050 and clears its policy dates, because GBD reports TFA = 0 from 2023 but Indonesia has passed no ban.

**Known mismatch:** `0. master.R` sources `"4. prepare_interventions.R"` (with a space), but the file is named `4.prepare_interventions.R`, so stage 4 fails when run from the master.

The old two-pass calibration (`5. calibration_100_gbd23.R` + `5. adjustments_100_gbd23.R`) has been deleted; root `adjustments2023_age.csv`, which it wrote, is no longer read by anything.

Large tables are split into `*_partN.rds` files and read back with `list.files(pattern=...)` followed by `rbindlist`. Some inputs live at the **repo root**: `bp_data6.csv` (`bp_data5.csv` in stage 4), `add_cov_data.csv`, `Country_groupings_extended.csv`, `ettehad_rr_bp_reduction_10mmHg.csv`, `ettehad_rr_bp_reduction_effects.xlsx`, `wpp.adj.Rda` (COVID excess mortality), `locs.rds`.

### Stage 5: calibration

- `cal_config` in `0. master.R` is the **single source of truth** for every calibration setting (periods, grids, objective weights, caps, inputs, outputs, workers, pilot). `5. calibration.R` supplies no defaults and stops on any missing or invalid entry. Stage 6 reads its period and output entries.
- One fit: for each location × sex × cause × GBD 5-year age band, a grid search over (m_IR, m_CF) minimizes `w_deaths·RMSE(deaths) + w_prev·RMSE(prevalent cases)` against GBD 2023 counts over 2009–2019. Ties go to the pair nearest the identity. The selected multipliers are applied once, constant over time, to the historical years only.
- The calibration cohort **reproduces the recursion of `project.all()` in stage 7** (shared population across causes, age-20 re-seeding, the open-age-95 row not carried forward). If you change one, change the other.
- Probability rule everywhere: `IR, CF ≤ min(tp_cap, 1 − BG.mx − feas_margin)`.
- Each run writes `output/calibration/calibration_settings.rds` with a run id. Every `adjusted_searo_part*.rds` carries that id as an attribute, and stage 6 refuses chunks that don't match, or settings from a pilot run.
- Set `cal_config$pilot_locations` to calibrate a few countries; pilot output goes under `temp/calibration_pilot/` and never overwrites production files.

### Stage 6: baseline

Reads the calibrated historical rates (read only), attaches UN WPP 2024 populations and age-20 cohorts, BP and coverage inputs, extends 2019 rates to 2020–2050, adds COVID excess mortality (2020–2021), applies the prospective secular trends (`run_bgmx_trend`, `run_CF_trend`, `run_CF_trend_80` = 80% of the CF trend, `run_CF_trend_ihme`) and final probability guards. All prospective assumptions belong here, never in the calibration. It checks that `stage7_first_year` matches the year stage 7 filters on, then trims `b_rates` to that year onward.

### Stage 7: model

- `project.all(Country, ...)` runs the multistate well/sick/dead projection for one country. Causes are IHD, ischemic stroke, intracerebral hemorrhage and hypertensive heart disease. Intervention modules adjust incidence (`eff_ir`) and case fatality (`eff_cf`) multiplicatively: `calculate_antihypertensive_impact_etihad` (Ettehad BP-reduction RRs), `calculate_sodium_impact_etihad`, `calculate_tfa_impact`, `calculate_statins_impact`.
- `calculate_baseline_incidence_gbd()` splits incidence across BP bins as `prob × RRi / alpha`, where `alpha = Σ prob × RRi`. Both the bin RRs and their normaliser must use the **same cause-specific** GBD RR. Hemorrhagic stroke used to take ischemic-stroke RRs in the bins (`RRi_HSTROKE := RRi_ISTROKE`) but its own RRs in `alpha`, so its bins did not sum to the baseline rate. This was fixed in 2026-11 and should not be reintroduced.
- Sourcing the script defines everything and runs the parallel country loop; the old top-level single-country test run (China) is commented out.
- `run_multiple_scenarios()` loops over the `scenarios` list: `baseline`, `bp_only`, `sodium_only`, `tfa_only`, `statins_only`, `bp_sodium`, `bp_sodium_tfa`, `all_four`.
- Scenario parameters are globals set just before the parallel run: `target_control` (0.5 by 2040), `salteff` (30% by 2030), TFA target (0 from 2028), statin coverage (0.60 by 2050, start 2026), adherence and `drugcov`.
- Countries run in parallel with `foreach`/`doParallel` (`ncores <- 8`). **Any new helper or data object used inside `project.all` must be added to the `clusterExport` varlist**, otherwise the workers fail. Errors are caught per country and written to its log.
- Don't edit the stage-7 runner without the user's explicit approval. If workers die mid-run ("error reading from connection"), reduce workers and set `data.table::setDTthreads(1)` per worker from the calling session rather than changing the file.
- `validate_intervention_results()` checks for negative or NA states, population-conservation mismatches and effect multipliers outside [0, 2].

`R/functions_review_6_100.R` duplicates `code/functions_review_6_100.R` (the master sources the `code/` copy). `R/coverage_newfig.R` holds coverage-figure code.

## Reporting and manuscript

Two-step reproducible build, run from the repository root:

```
Rscript -e "rmarkdown::render('reports/manuscript-100mlives2-artifacts.Rmd', output_dir = tempdir())"
Rscript -e "rmarkdown::render('manuscript/manuscript-100mlives2.Rmd')"   # → Word via reference.docx + word-layout.lua
```

- `reports/manuscript-100mlives2-artifacts.Rmd` is the **only** place manuscript numbers, tables and figures are calculated. It reads project inputs, `output/out_model/*.rds` and `output/calibration/*` (it never reruns the model) and writes `manuscript/artifacts/*.rds` (scalars, display tables, plot data, provenance), `manuscript/tables/*.csv` (T1, T2, TS1–TS10, Math_*), `manuscript/figures/*.png` (fig1–4, figS1–S6) and regenerates `manuscript/manuscript-100mlives2.xlsx` for tracking and review only. Conventions: data.table and ggplot2, no tidyverse, no `setwd()`, paths from the repo root via `rprojroot`. Takes about 3 minutes.
- `manuscript/manuscript-100mlives2.Rmd` only loads those artifacts and displays them; it calculates nothing and never reads the xlsx. Uses `references.bib` and `apa.csl`.
- Results that can't be recalculated yet keep legacy values tagged `REPRO_PENDING` in both Rmds.
- Analysis windows: interventions start in 2026; cumulative totals use 2026–2050 (Table S8 keeps the legacy 2025–2050 window).
- `reports/UWRTSL-100MLivesRMD_Output.Rmd` is the older exploratory analysis report. It writes `output/out_*.png` figures and tables.

`dev/` holds the task prompts behind past and planned changes (`prompt-reproducible-manuscript.md`, `prompt-update_calibration.md`, `prompt_update_coherent_mortality_trends.md`). Read the relevant one before working in that area. `docs/` holds the math documentation and working-group drafts (gitignored except `*.md`).
