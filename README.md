# uw-rtsl-100mlives2

This project estimates the future health impact of implementing Resolve to Save Lives interventions for hypertension treatment, statin treatment, sodium reduction, and trans-fat elimination at global and national levels over 2025–2050.

The repository contains the modeling framework and materials for the **100 million lives paper**. The workflow constructs baseline rates and transition probabilities, incorporates risk factors and interventions, calibrates the model, runs country-level simulations, and generates manuscript tables and figures. It adapts the Kontis framework using GBD 2023 inputs and includes the updated statin model.

## Repository structure

The repository is organized into the following top-level folders. Their intended responsibilities are described below; the analytical execution order remains separate from the folder layout.

| Folder | Intended contents |
| --- | --- |
| `code/` | Ordered analysis scripts and the main pipeline orchestrator. |
| `config/` | Model settings, scenario definitions, and configuration files. |
| `data-raw/` | Original source inputs and scripts or documentation for preparing them. |
| `data/` | Prepared inputs and intermediate or processed datasets used by the model. |
| `R/` | Reusable model functions and supporting utilities called by analysis scripts. |
| `output/` | Generated simulation results, country-level outputs, and exported tables and figures. |
| `reports/` | R Markdown analyses and reporting scripts that summarize model outputs. |
| `manuscript/` | Active manuscript source files and manuscript-specific supplementary materials. |
| `paper/` | Paper-related drafts and submission materials; keep the active analytical manuscript source in `manuscript/`. |
| `docs/` | Model documentation, methodological notes, and robustness documentation. |
| `library/` | Bibliographic resources and reference materials. |
| `tests/` | Model validation and testing scripts. |
| `vignettes/` | Worked examples and longer explanations of model use. |
| `dev/` | Development scripts and exploratory work. |
| `temp/` | Temporary files and disposable working outputs. |

The repository root also contains `README.md`, `.gitignore`, and the RStudio project file `uw-rtsl-100mlives2.Rproj`.

## Modeling workflow

The existing model sequence is listed below. These are the script identifiers documented in the previous README; confirm their current filenames and locations within `code/` before execution.

| Order | Script identifier | Role |
| --- | --- | --- |
| Entry point | `0.master` | Orchestrates the full pipeline. |
| 1 | `1.get_base_rates_100_gbd23` | Constructs baseline rates from GBD 2023 inputs. |
| 2 | `2.get_tps_100_gbd23` | Constructs disease transition probabilities. |
| 3 | `2.get_tps_bgmx_100_gbd23` | Prepares background mortality components. |
| 4 | `3.risk_factors_100_sodium` | Prepares sodium-related risk-factor inputs. |
| 5 | `4.interventions_100_tfa2_statins2` | Defines intervention effects, including trans-fat elimination and updated statin treatment. |
| 6 | `5.calibration_100_gbd23` | Calibrates the model. |
| 7 | `6.adjustments_100_gbd23` | Applies model adjustments before simulation. |
| 8 | `7.model_*` | Runs the intervention scenarios and country-level simulations. |

The primary model identifier is `7.model_100_multiplicative_func_new3_gbd23_noaroc`. It contains the multiplicative model specification, runs country-level simulations, and exports the core results for downstream reporting.

Reusable utilities, such as `functions_review_6_100`, belong in `R/`. Analysis-specific processing, such as `coverage_newfig`, belongs in `code/` or `reports/`, according to whether it prepares model inputs or generates report figures.

## Running the analysis

1. Open `uw-rtsl-100mlives2.Rproj` and work from the repository root.
2. Confirm that the required source inputs are available and that configuration and file paths match the reorganized folders.
3. Run the baseline, transition-probability, risk-factor, intervention, calibration, and adjustment steps in the order above. Validate intermediate outputs before continuing.
4. Run the primary `7.model_*` script to generate country-level results in `output/`.
5. Run the reporting workflow to compile results and generate manuscript-ready tables and figures.
6. Update the manuscript and supplementary materials in `manuscript/` using the corresponding model outputs.

The full workflow can be orchestrated through `0.master`, but complete replication is computationally intensive. Running stages separately and retaining their intermediate outputs makes debugging and restarting easier. Country-level simulations can be run independently when supported by the model.

Use repository-relative paths throughout the scripts. Keep original inputs in `data-raw/`, prepared model data in `data/`, and generated results in `output/`. Reusable functions should be sourced from `R/`; temporary working files should go in `temp/`.

## Reports and manuscript outputs

The existing reporting identifier is `UWRTSL-100MLivesRMD_Outputv2`. Its reporting source belongs in `reports/` and compiles model outputs into an HTML report and the tables and figures used in the manuscript.

Run reporting only after the required country-level outputs are available. Export generated tables and figures to `output/` and use them in the active manuscript under `manuscript/`. Keep reporting paths aligned with the new layout rather than relying on the previous root-level organization.

## Computational considerations and reproducibility

- Calibration and multi-country simulations can require substantial memory and runtime.
- Retain validated intermediate data so later stages can restart without repeating expensive calibration.
- Use parallel execution only where the implementation supports independent simulations.
- Record input versions, scenario settings, and any random seeds alongside each analysis run.
- Use the checks in `tests/` to validate model inputs and outputs before reporting results.
- Review `.gitignore` so large source datasets, temporary files, and generated artifacts are handled consistently with the project's sharing and replication needs.

The folder layout above reflects the supplied repository screenshot. The script identifiers reflect the existing README; this documentation update does not establish that those scripts have already been moved or renamed.

