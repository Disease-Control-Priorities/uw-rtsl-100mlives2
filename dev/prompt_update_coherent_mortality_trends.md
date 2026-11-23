# Update mortality trends, model results, and manuscript reporting

Work in the `uw-rtsl-100mlives2` repository within work-uw-rtsl. Read its applicable `AGENTS.md` and project instructions first.

## Goal

Make the Li et al. (2019) forecast-reconciliation approach the default mortality trend method. Adapt the implementation in `023_get_tps_bgmx.R` from the WHO CVD project, integrate it with this project's actual projection pipeline, regenerate the affected results, and update the manuscript and its artifacts so every description and reported result matches the executed analysis.

Use `data.table` for data manipulation. Keep changes focused on mortality trends and the results and reporting directly affected by them.

## 1. Mandatory read-only preflight and scope approval

Initially, inspect files and trace dependencies only. Do not edit files, regenerate outputs, or run the production pipeline until this preflight establishes whether the authorized scope is sufficient.

These are the authorized source files to modify:

| File | Authorized work |
| --- | --- |
| `code/2. get_tps_bgmx_100_gbd23.R` | Add the reconciled forecast, saved diagnostics and provenance; retain supported alternatives. |
| `code/0. master.R` | Configure the coherent method as the default, validate settings and orchestrate the required stages. |
| `manuscript/manuscript-100mlives2.Rmd` | Update methods, supplementary methods, performance reporting, affected results and captions. |
| `reports/manuscript-100mlives2-artifacts.Rmd` | Build the affected numerical, table and figure artifacts reproducibly from saved inputs and outputs. |
| `manuscript/references.bib` | Add the Li et al. reference and connect its citation to the manuscript. |

The spelling in the request may omit spaces or extensions. Resolve the real tracked filenames before editing; for example, the supplied master script is named `0. master.R`. Do not create a duplicate master or bibliography because of a filename difference. If the requested bibliography is not the active one, identify the discrepancy and ask before changing another bibliography.

Read these for context, but **do not modify them without my explicit approval**:

- `code/6. build_baseline.R`: the baseline builder, which extends calibrated historical inputs and applies prospective trends.
- `code/7. model_100_multiplicative_func_new3_gbd23_noaroc.R`: the model runner and its state-transition, population and death accounting.
- The WHO reference `023_get_tps_bgmx.R`; locate the supplied reference copy if it is outside this repository. Its final coherent-forecast block is the implementation example, not its earlier independent forecast blocks.
- If supplied, WHO `031_calibration_trends.R` is additional read-only context for applying the reconciled forecast to country inputs. Do not create or transplant that WHO pipeline stage into this repository.
- The current calibration script and saved diagnostics, plus sensitivity/comparison scripts and helpers when needed to understand dependencies. Reading a file does not authorize editing it.

**Fallback if I forget to attach the WHO reference files:** consult the existing files in this local Windows folder:

```text
C:\Users\wrgar\OneDrive - UW\02Work\WHO-CVD\github\uw-who-cvdtargets\code
```

In particular, read `023_get_tps_bgmx.R` and, when useful, `031_calibration_trends.R` there. This WHO project is strictly read-only for this task: do not modify, create, delete or rename anything there, and do not run scripts that write outputs or otherwise change that project. Adapt the needed logic only within the authorized 100M Lives files. If the folder is unavailable in your execution environment and the necessary references were not attached, report that limitation and request the missing reference files; do not invent their contents.

**Known dependency to investigate before starting:** the supplied stage-6 builder reads only `tps_bgmx_forecasted.rds`, `tps_bgmx_all_forecasted.rds`, `tps_bgmx_cvd_forecasted.rds` and the IHME alternative. It independently scales `BG.mx`, `BG.mx.all` and `CF`; it has no branch that reads `tps_mortality_coherent_forecasted.rds` and rebuilds country mortality accounting. Adding a forecast file and a master flag alone is therefore unlikely to complete the intended integration.

If any additional script, helper, configuration, bibliography or other source file needs modification, **list every such file, state the exact proposed change and why it is necessary, then ask me to add it to scope before starting implementation or output regeneration**. Include `code/6. build_baseline.R` in that request if the checked-out version has the dependency above. Do the same for stage 7 if a runner change is genuinely necessary. Do not bypass this restriction using code injection, `assignInNamespace`, rewriting functions at runtime, or placing baseline/runner logic inside the master script or artifact report. Do not silently repurpose legacy filenames to disguise incomplete integration.

If the current checkout already supports the required handoff within the authorized scope, explain the evidence briefly and proceed. Otherwise, finish the read-only assessment and wait for my answer. Once I approve the specific scope expansion, carry the work through implementation, result regeneration and manuscript rendering.

## 2. Coherent mortality forecast

### Inputs and accounting

Adapt the WHO implementation to the 100M Lives data and configuration; do not assume WHO paths, targets, country lists or settings apply here.

- Read the original historical transition-input chunks using an anchored pattern such as `^tps_inpt_part[0-9]+\\.rds$`. The existing broad `pattern = "tps"` also matches generated trend files on reruns and must not contaminate the input list.
- Use GBD 2023-derived population mortality rates for 2000–2019, Female and Male, single ages 20–95, treating the terminal row as 95+. Check consistency with the actual project settings and record the resolved values.
- The four disjoint modelled causes are IHD (`ihd`), ischaemic stroke (`istroke`), intracerebral haemorrhage (`hstroke`) and hypertensive heart disease (`hhd`). Dementia is excluded under the current default. Normalize the actual cause labels explicitly and validate the cause set.
- `DIS.mx.t0` is deaths from the cause divided by population; it is not `CF`, which applies to people living with the disease. `BG.mx` on a cause row means all causes except that cause. `BG.mx.all` means causes outside the four modelled CVD causes.
- For each country × sex × age × year, construct other-cause mortality as `ALL.mx - sum(DIS.mx.t0)` over the four causes. Check the supplied `BG.mx.all` against this residual and report discrepancies. Do not exclude dementia a second time or silently accept a residual defined using a different cause set.
- Deduplicate the common population and all-cause rate across cause rows before aggregating. Compute global age/sex/year rates as `sum(Nx * rate) / sum(Nx)` using a consistent country set and denominator for all components. Exclude any pre-aggregated Global row to avoid double counting. Record the countries represented; label a restricted-country aggregate accurately if it does not represent the full global input set.
- Validate complete grids, unique keys, consistent `Nx` and `ALL.mx` across causes, finite nonnegative inputs, nonnegative residual mortality and positive aggregate exposure. Retain valid zero-population country cells with zero weight. Fail with useful details for missing or incompatible data rather than changing the country composition or silently imputing values.

The six-series hierarchy, separately for each age and sex, is:

```text
ALL.mx = ihd + istroke + hstroke + hhd + BG.mx.all
```

### Base forecasts and reconciliation

1. For each sex and each of the six series, fit a Lee–Carter model across ages using SVD:

   `log(m[j,x,t]) = a[j,x] + b[j,x] * k[j,t] + e[j,x,t]`.

2. Forecast the period index with additive damped-trend exponential smoothing, matching `forecast::ets(..., model = "AAN", damped = TRUE)` in the example. Keep normalization and reconstruction internally consistent. Do not substitute an ARIMA extrapolation and describe it as this implementation. Do not claim that ETS was selected by a comparison unless that comparison was actually run.

3. Reconcile the six independent forecasts on the **rate scale**, separately by age and sex, with the constraint-form minimum-trace projection used in the example:

   `y_reconciled = y_base - W %*% t(C) %*% solve(C %*% W %*% t(C), C %*% y_base)`

   where the series order is `(ALL.mx, ihd, istroke, hstroke, hhd, BG.mx.all)` and `C = (1, -1, -1, -1, -1, -1)`.

4. Estimate `W` from in-sample LC fitted-value residuals on the rate scale at each age, shrinking halfway toward its diagonal: `W = 0.5 * cov(errors) + 0.5 * diag(diag(cov(errors)))`. State that this is the reference implementation's approximation to forecast-error covariance, not a rolling forecast-error estimate or a universal requirement of Li et al. Estimate it separately within each fit window. Check degeneracy and numerical conditioning; do not add an arbitrary large variance floor or silently replace the method.

5. Require finite, nonnegative reconciled rates and verify the additive identity with a declared relative tolerance, matching `1e-10` where numerically appropriate. Linear reconciliation does not guarantee nonnegativity: stop with the offending cells if negatives occur. Do not independently truncate components and break coherence. Handle zero rates explicitly wherever logs or ratios require positive values; do not hide invalid cells with `na.rm = TRUE`.

This is an adaptation of Li et al.'s forecast-reconciliation approach using the WHO example's LC/ETS base models and covariance approximation. Do not confuse it with a Li–Lee common-factor model or add clustering, new causes or a new forecasting framework.

### Temporal holdout and final production fit

Keep evaluation and final forecasting separate:

- **Holdout:** fit only on 2000–2015, estimate its covariance only from those data, and forecast/reconcile 2016–2019. Compare the unreconciled and reconciled predictions with the same observed global age/sex/component cells. Never use 2016–2019 rates for fitting, tuning, reconciliation covariance or forecast rescaling in this evaluation.
- Save cell-level observed, base and reconciled rates and summary errors for each sex × component: rate-scale RMSE, log-scale RMSE and valid cell count. With the complete 20:95 grid and four holdout years, expect 304 cells per sex/component; derive this count from the grid rather than hardcoding it.
- **Production:** refit on the full 2000–2019 history and forecast 2020–2050. Do not keep using the 2000–2015 fit for production after evaluating the holdout.
- Preserve observed 2000–2019 rates in the final panel. Calculate cumulative changes relative to each series' observed 2019 rate, so the 2019 change is zero and its ratio is one. Check denominators and explicitly document the anchor.
- Keep the unreconciled forecast as the direct forecasting benchmark. Preserve the project's explicit legacy and IHME alternatives where supported; do not silently use them when the coherent forecast is missing.

Write a clear saved output contract, using the WHO example's filenames where suitable:

- `data/processed/tps_mortality_coherent_forecasted.rds`: global rates and changes, with unique sex × age × year × cause keys, historical/projected source labels, `DIS.mx.t0`, `ALL.mx`, `BG.mx`, `BG.mx.all`, and the relevant cumulative changes (`percent_diff_cvd`, `percent_diff_bgmx`, `percent_diff_bgmx_all`).
- `data/processed/tps_mortality_coherent_validation.rds`: base/reconciled holdout summaries.
- The minimum additional cell-level diagnostics and metadata needed for the manuscript and auditing, under an existing processed-data or diagnostics directory. Record inputs/fingerprints, country scope, windows, cause mapping, age convention, method, covariance rule, anchor, tolerances and run identity.

Use explicit output paths and rerunnable input selection. Correct any lag-change calculation retained for compatibility: order by year and group by age as well as sex/cause/location. These are cumulative 2019-relative trends for application, not year-to-year multipliers.

## 3. Default configuration and country-level handoff

Add a clearly named central method setting in `code/0. master.R`, defaulting to `coherent`, with validation and an explicit legacy alternative. Preserve the meaning of `run_bgmx_trend`, `run_CF_trend`, `run_CF_trend_80` and `run_CF_trend_ihme`; default to background trends on, CF trends on, 80% share on, IHME CF alternative off. Resolve contradictory settings explicitly. Do not label the method active unless the baseline actually consumes it.

The intended application, to implement **only in an authorized baseline location after any required approval**, is the following. For country `l`, age/sex `x`, cause `c` and future year `t`, let `R[c,x,t]` be the global reconciled cause rate divided by its observed 2019 global rate, and similarly for other causes:

```text
DIS[l,c,x,t]   = DIS[l,c,x,2019] * R[c,x,t]
OTHER[l,x,t]   = (ALL[l,x,2019] - sum_c(DIS[l,c,x,2019])) * R[other,x,t]
ALL[l,x,t]     = OTHER[l,x,t] + sum_c(DIS[l,c,x,t])
BG[l,c,x,t]    = ALL[l,x,t] - DIS[l,c,x,t]
CF[l,c,x,t]    = CF[l,c,x,2019] * (1 + share * (R[c,x,t] - 1))
IR[l,c,x,t]    = IR[l,c,x,2019]
```

The default `share` is 0.8; the existing full-trend setting uses 1.0. This is 80% of the cumulative relative change, including increases where projected; it is not `0.8 * R`, an 80% annual decline, or exponentiation of the ratio. Keep the rationale as a modelling assumption about overlap with intervention effects, not a causal attribution established by the forecast.

Each future row starts from the calibrated terminal-year inputs and receives its cumulative factor **once**. Do not compound factors across years, trend the historical calibration period, recalibrate IR/CF, or apply both legacy and coherent factors. All countries share age/sex/cause-specific relative trends; their absolute rates remain country-specific. Reconstructing country residuals and totals matters: global cause-specific `BG` ratios alone do not guarantee coherent country inputs because cause mixes differ.

Keep COVID adjustments and intervention assumptions as implemented in this project. Do not copy WHO COVID surveillance inputs or alter the current COVID process. Inspect final probability guards and report whether they change projected mortality identities; do not change guard rules or the runner without approval. Validate accounting before and after any guards, and qualify claims if a guard breaks it.

Coherence is a property of these mortality-rate inputs. Modelled CVD deaths arise from `CF` applied to simulated prevalent cases, and incidence is held constant. Therefore simulated cause-specific deaths need not reproduce the reconciled population mortality forecasts. Audit the runner's shared population and all-cause death accounting without changing its equations.

## 4. Artifact report and supplementary benchmark reporting

The WHO manuscript will not be supplied. Use this self-contained specification of its reporting structure and adapt it to this project's evidence; do not copy its numerical results or WHO GHE calibration targets.

### A. Mortality projection methods and forecast performance

Add a concise main-text explanation and a supplementary **Mortality projection: methods and performance** subsection covering: input source and country scope; population weighting; six-series hierarchy; LC and damped ETS; rate-scale reconciliation and covariance approximation; holdout versus full-history refit; the 2019-relative country application; fixed incidence; CF share; and limitations. Distinguish global forecast accuracy, historical calibration fit and external projection comparisons.

Add one supplementary forecast-performance table, six rows in the hierarchy order, with these columns:

| Series | Female holdout log RMSE: reconciled / base | Male holdout log RMSE: reconciled / base | Female ASMR change, 2019–2050 | Male ASMR change, 2019–2050 |
| --- | --- | --- | --- | --- |
| All causes; IHD; ischaemic stroke; intracerebral haemorrhage; hypertensive heart disease; other causes | Computed values | Computed values | Computed percentage change | Computed percentage change |

Explain the train/test years, ages and cell counts in a footnote; define RMSE, the base forecast and the ASMR standard. Save underlying numeric values, including rate-scale RMSE, with provenance. Report the maximum relative aggregation error and any positivity failures/guard effects. Describe whether accuracy improves, worsens or is similar only after inspecting results. A four-year global holdout is not validation of country forecasts or intervention effects.

Use verified WHO world-standard weights rescaled to adults 20–95+, documenting single-age allocation and the 95+ tail. Use the same fixed weights for 2019 and 2050 and one population denominator per age/sex/year when computing model rates. The current artifact report explicitly marks its old step weights as unverified and notes a fourfold population denominator issue in legacy ASMR figures. Do not reuse those weights or label legacy PNGs as refreshed. Resolve the weights from a verifiable source, document it, and regenerate the affected existing ASMR figures; if that cannot be done, identify the exact missing input and withhold claims of completion for those figures.

### B. Historical calibration methods and performance

Use the WHO supplement's structure, with **this project's** saved calibration evidence:

1. **Uncalibrated rates:** explain how cohort-based incidence and case fatality were derived and interpolated, based on the actual code.
2. **Targets:** identify source, measures, country/cause/sex/age coverage and fitting years. This project's supplied configuration uses GBD 2023 deaths and prevalence; do not change it to WHO GHE or import the WHO country's count or error values.
3. **Objective and search:** describe the saved weighted sum of deaths-count and prevalent-case-count RMSE, multiplier grids, feasibility/cap rules, tie rule and candidate selection. Derive parameters from `calibration_settings.rds`, not stale text such as a ±5% search or a separate second calibration pass. Distinguish the age-band selection objective from the result when selected multipliers are applied together.
4. **Performance:** report before/after `WAPE = sum(abs(predicted - target)) / sum(target)` and `bias = sum(predicted) / sum(target) - 1`, over matching cells, with documented treatment of zero totals. Report overall errors, relevant existing stratified results, country medians/IQRs, countries improved, objective reduction, multiplier summaries and boundary frequency where supported by saved diagnostics.
5. **Table/figure and limitations:** reuse/update the existing calibration performance table and target-versus-uncalibrated-versus-calibrated figure. Totals can agree while individual strata have error. These are in-sample calibration measures, not temporal or external validation. Calibration is separate from prospective forecasting and should remain unchanged by a trend-only update.

The current artifact report already has stage-5 provenance checks, `TS10_Calibration`, calibration scalars and `figS6_calibration_fit.png`. Extend and correct that existing machinery instead of making duplicate calibration tables or rerunning calibration inside the report. Missing necessary stage-5 outputs are a dependency to disclose and, if source edits are needed, seek approval for.

### C. Reproducible results and external comparisons

Keep `reports/manuscript-100mlives2-artifacts.Rmd` as the executable source for manuscript calculations; the manuscript should load its artifacts for tables, figures and inline numbers. The artifact report reads saved results and diagnostics; it must not refit forecasts, rerun calibration or invoke the model. Add only artifacts used in the revised manuscript/supplement, and update their inventory, scalar registry, table/figure metadata, provenance and tracking workbook through the existing mechanisms.

After the approved integration and rerun, refresh affected abstract, main results, discussion comparisons, tables and figures from the same model run. Preserve the 2026–2050 intervention reporting window and its inclusive 25-year divisor. Audit hardcoded sensitivity rows and replication columns: update only from genuine matching scenario outputs. Never relabel old independent-LC runs as coherent runs or mix old sensitivity numbers with a refreshed base case without an explicit unresolved status.

Retain existing IHME Foresight and UN-WPP comparisons where used. Verify release, country coverage, sex, ages, causes, units and period before drawing comparisons; do not call a forecast-to-forecast comparison external validation. Separate population mortality forecasts, model-simulated deaths and age-standardised rates. Previously published Kontis/Pickersgill reference values stay attributed to their original periods; refresh only this study's matching results. Do not build new sensitivity/benchmark source scripts or expand their scenarios without scope approval.

## 5. Bibliography

Add this entry to `manuscript/references.bib` unless an equivalent DOI entry already exists; reuse an existing correct key if so:

```bibtex
@article{Li2019ForecastReconciliation,
  author  = {Li, Han and Li, Hong and Lu, Yang and Panagiotelis, Anastasios},
  title   = {A forecast reconciliation approach to cause-of-death mortality modeling},
  journal = {Insurance: Mathematics and Economics},
  year    = {2019},
  volume  = {86},
  pages   = {122--133},
  doi     = {10.1016/j.insmatheco.2019.02.011},
  url     = {https://doi.org/10.1016/j.insmatheco.2019.02.011}
}
```

Metadata source: [Monash University publication record](https://research.monash.edu/en/publications/a-forecast-reconciliation-approach-to-cause-of-death-mortality-mo/).

Cite it in the main-text and supplementary forecast descriptions. Use `manuscript/references.bib` as the bibliography; the manuscript YAML should resolve it as `bibliography: references.bib` from the manuscript directory. Preserve unrelated entries. Reuse existing appropriate Lee–Carter, forecasting and MinT references where available; verify any necessary additional methodological citation before adding it.

## 6. Execution, verification and completion

After preflight and any required approval:

1. Preserve a clearly labelled pre-change summary of the current BAU and intervention totals and key mortality benchmark figures, with the inputs/run identified. Do not treat an already stale run as a controlled comparator.
2. Implement the authorized changes and generate forecasts and diagnostics. Verify that a second run cannot read its own generated files as original inputs.
3. Use targeted checks for complete grids, valid rates and ratios, unchanged historical calibrated IR/CF, 2019 factors equal to one, no compounded or duplicate trend application, holdout isolation, coherent global/country rate identities, probability guards and unchanged runner source. Check model outputs retain one shared population/all-cause envelope across cause rows and aggregate deaths without counting that envelope four times.
4. Rerun the required trend/baseline/model stages in dependency order, retaining the stage-7 code unchanged unless separately approved. Do not blindly run the master's default stages 1–9: its supplied comments note that stages 8–9 may be absent. Verify available stage names and dependencies first; avoid rebuilding unrelated raw inputs or refitting the historical calibration unnecessarily.
5. Confirm saved model outputs postdate the new forecast and baseline execution and belong to that configuration; calibration timestamps alone do not prove the new trends were used. Use the existing provenance system and extend it within approved files. If stronger provenance requires another source change, request approval rather than asserting a link that has not been checked.
6. Render the artifact report in a fresh R process, then render the manuscript in its configured format. Validate new table/figure links, citation resolution, inline scalars and agreement among abstract, results and supplements. Keep unrelated unresolved artifact statuses truthful. Report missing data/packages and any checks or renders that could not run; do not fabricate results or substitute old artifacts.
7. Provide a concise completion report: files changed, resolved method/windows/configuration, holdout base-versus-reconciled accuracy, coherence error, changes in BAU and intervention totals, calibration stability, checks/renders completed and any remaining dependency. Include exact commands needed to reproduce the results.

Do not stop at adding a forecast function or revising prose. Completion requires the active default, its baseline handoff, refreshed results and manuscript artifacts to agree—subject to the explicit scope-approval gate above.
