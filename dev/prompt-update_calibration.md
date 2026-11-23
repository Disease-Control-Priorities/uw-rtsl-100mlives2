# Replace the 100 Million Lives calibration process

You are working in the `uw-rtsl-100mlives2` repository within the UW–RTSL project. Implement a single historical calibration process, update its downstream integration and results, and make the manuscript's calibration methods and in-sample performance reproducible. Prefer `data.table` for R data manipulation.

## 1. Read-only preflight and scope gate

Before changing files or executing the pipeline, read the repository instructions and inspect:

- The actual master entry point, referred to here as `code/0.master.R`. The supplied version is named `code/0. master.R`; my reference to “0.main” means the master orchestration script. Resolve this against the repository. Do not create duplicate master scripts. If these are distinct active entry points, ask which to modify.
- `code/5. calibration_100_gbd23.R` and its downstream call to `code/5. adjustments_100_gbd23.R`.
- `code/6. build_baseline.R`.
- `code/7. model_100_multiplicative_func_new3_gbd23_noaroc.R`, especially `project.all()`, initialization, incoming age-20 cohorts, annual transitions, probability caps, age-95 handling, and output contracts.
- `03_calibration_who.R` and the supplied `engine.R`, resolving their actual locations. These are methodological references, not authorization to change their source project.
- `manuscript/manuscript-100mlives2.Rmd`.
- `reports/manuscript-100mlives2-artifacts.Rmd`.
- Relevant upstream transition-probability files, target data, population inputs, forecast inputs, and helpers, read-only, as needed to establish the contracts.

Resolve attachment suffixes such as `(1)` and `(2)` to the canonical repository files. The WHO project's `00_run_model.R` is a settings example, not this project's master entry point.

The authorized source changes are limited to:

| File | Authorized work |
| --- | --- |
| `code/5. calibration.R` | Create the replacement calibrator, including necessary local helpers |
| Existing master entry point | Declare settings and update orchestration |
| `code/6. build_baseline.R` | Remove duplicate calibration adjustments; retain and correctly sequence projection preparation |
| `manuscript/manuscript-100mlives2.Rmd` | Update calibration methods, in-sample results, captions, and relevant limitations |
| `reports/manuscript-100mlives2-artifacts.Rmd` | Build the corresponding reproducible calibration artifacts and update affected result artifacts |

Generated calibration files, diagnostics, model outputs, and manuscript artifacts are permitted within the existing project output structure. Preserve unrelated files. Leave the legacy calibration and adjustment source files available but disconnected from the new active calibration path; do not delete or rewrite them.

**If any additional source file must be created or modified, list its exact path, required change, reason, and consequence of leaving it unchanged, then ask me to extend the scope BEFORE modifying files or executing the pipeline.** In particular, the stage-7 runner is read-only unless I explicitly approve a specific change. Treat any further scope expansion discovered later the same way. Read-only inspection can continue while awaiting my response.

An important compatibility issue must be assessed in preflight: the supplied `engine.R` seeds `well = Nx - sick`, retains the open 95+ stock, and exposes an age-0 entrant implementation, while the legacy runner seeds age 20 and uses different initialization and ageing conventions. The supplied WHO calibrator also contains its own `init_cohort()` and `run_cohort()` functions rather than automatically using that shared engine. Do not assume these implementations are interchangeable. Explain which transition implementation will be used and whether it is compatible with the unchanged runner. If adopting the requested engine requires runner or shared-engine edits, propose those exact edits and ask first. Do not silently calibrate a materially different model, rewrite the runner, or claim calibration and projection use one engine when they do not.

If the work fits entirely within the authorized scope, state the resolved paths and implementation approach and proceed without asking for redundant approval.

## 2. Required architecture

The active pipeline must become:

```text
Existing historical transition-probability inputs + observed calibration targets
    -> code/5. calibration.R
    -> data/processed/adjusted_searo_part*.rds
       [historical calibrated rates only; no projection adjustments]
    -> code/6. build_baseline.R
       [extend years, attach projection populations/COVID inputs,
        apply existing prospective trends and necessary probability guards]
    -> existing stage-7 runner, unchanged
    -> updated outputs and manuscript artifacts
```

There must be one calibration fit and one application of its selected multipliers. Remove the active second adjustment pass and the subsequent multiplication by `adjustments2023_age.csv` in stage 6. Do not replace them with another undocumented correction, rescaling, or residual-based epidemiological adjustment.

Calibration is always **in sample**. Prospective secular trends, the 80% CVD-trend option, IHME Foresight alternatives, COVID-era adjustments, and future population adjustments belong in stage 6, not in the calibrator or its fit diagnostics. Historical population inputs needed to run the calibration cohort are appropriate.

## 3. All mandatory settings belong in the master script

Declare calibration configuration only in the actual master entry point, preferably as one clearly named configuration object that can be passed to the calibrator. Include:

- Historical input years, fitting window, terminal observed year, and projection years as separate concepts.
- Modelled locations, sexes, causes, ages, and five-year age-band definitions, including the terminal age group.
- IR and CF multiplier grids, death/prevalence objective weights, caps, probability tolerances, and tie-breaking rules.
- Input file patterns and target paths, output stub and paths, number of output chunks, diagnostic paths, parallel flag, worker limit, and pilot settings.
- Any configurable convergence/refinement settings only if an explicitly approved method requires them.

The historical fitting window in the supplied code is 2009–2019; verify against the current repository and make that the explicit default if unchanged. Historical rate coverage can extend beyond the fitting window, for example 2000–2019.

Use the WHO project's example defaults for the consolidated search unless inspection identifies an incompatibility requiring discussion:

```r
CAL_IR_GRID <- c(0.40, 0.50, 0.60, 0.70, 0.80, 0.85, 0.90, 0.95,
                 1.00, 1.05, 1.10, 1.20)
CAL_CF_GRID <- c(0.30, 0.40, 0.50, 0.60, 0.70, 0.80, 0.90, 0.95,
                 1.00, 1.05, 1.10, 1.20, 1.40, 1.60, 1.80)
W_DEATHS <- 2
W_PREV <- 1
CAL_TP_CAP <- 0.90
```

These give 180 candidate pairs and include `(1, 1)`. They are configuration declarations for the master, not defaults to repeat inside functions. The calibrator must fail clearly on missing or invalid mandatory settings; do not use fallback assignments, function defaults, or hidden options to create a second source of truth. Save the resolved configuration with the run outputs so the artifact report can read it without sourcing the pipeline-running master script.

## 4. Implement `code/5. calibration.R`

### Inputs and target scope

Use this project's existing historical transition-probability inputs and GBD 2023 **Number** targets for deaths and prevalent cases. Adapt the WHO example's search, loss, diagnostics, and cohort approach; do not switch this manuscript's target source to WHO merely because the example uses WHO. A change of target source requires my approval.

Validate unique keys, complete expected coverage, consistent location/cause names and units, and finite nonnegative inputs. Aggregate simulated single-age counts into the same five-year target bands. Preserve observed zero counts, distinguish them from missing observations, and fail with a useful coverage report on missing required targets. Do not silently drop strata or fill missing targets/rates/factors with zero or identity values.

### Cohort calculation and loss

Use the reference engine approach subject to the compatibility gate above. Match the approved conventions for initialization, annual timing, entrants at age 20, case fatality, background mortality, shared population mortality, and the terminal age interval. Process all four causes together wherever they jointly determine population survival. Never count the shared population or background mortality four times. Use keyed joins and explicit ordering instead of positional assignment of transition vectors.

For each candidate `(m_IR, m_CF)`, run the historical cohort over the configured fitting window. For country `l`, sex `s`, cause `c`, age band `g`, and year `t`, let `D` denote target deaths, `K` target prevalent cases, and hats their simulated counterparts. Score each stratum using:

\[
J_{lscg}(m_{IR},m_{CF}) =
w_D\sqrt{T^{-1}\sum_t(\widehat D_{lscgt}-D_{lscgt})^2}
+w_K\sqrt{T^{-1}\sum_t(\widehat K_{lscgt}-K_{lscgt})^2}.
\]

This is a weighted sum of two RMSEs in counts, not an RMSE of pooled death and prevalence errors, a relative-error objective, or a likelihood. Keep these distinctions accurate in the manuscript.

Follow the example's exhaustive grid strategy: apply each candidate pair globally in a candidate simulation, score by country–sex–cause–age band, and select the best pair for each stratum. Use deterministic ties, preferably choosing the identity or the pair nearest to identity among equal minima. Record the rule. Apply selected multipliers once to the historical rates, constant over time within each fitted stratum.

Apply the **same** probability caps and historical feasibility rules during scoring, after selection, and in the saved rates. The reference caps rates inside candidate simulations but multiplies output rates without the same cap; do not reproduce that discrepancy. Report any changed cells and avoid hiding infeasible rates behind downstream clipping. Historical guards are model feasibility constraints, not projection adjustments.

### Selection scores versus final joint fit

The per-stratum best scores come from different global candidate simulations. Ageing and shared mortality couple strata. Combining all selected pairs does **not** guarantee the final joint simulation improves every stratum, even with `(1, 1)` in the grid.

Therefore, rerun the historical cohort twice: with uncalibrated rates and with all selected factors applied together exactly as saved. Use these runs for the reported before/after fit. Check that the identity run reproduces its saved grid scores within a declared tolerance. Report selection-stage and joint-fit improvements separately, including worsened strata and boundary hits. Do not assert universal joint improvement or introduce a second calibration pass to force it. If joint performance warrants a different fitting algorithm, propose it and ask before changing the requested method.

### Output contract and audit files

Write calibrated historical rates directly to `data/processed/adjusted_searo_part<N>.rds`, compatible with stage 6. Preserve required columns and types, including:

```text
location, year, sex, cause, age,
BG.mx.all, ALL.mx, BG.mx, PREVt0, DIS.mx.t0, Nx, IR, CF
```

Verify the actual upstream/downstream schema and retain any additional required fields. Preserve full cause names at this interface; stage 6 can retain its existing abbreviation step. Chunk by complete locations, sort deterministically, and validate complete coverage and unique keys. Do not write future years or forecast-adjusted rates into these files. Do not overwrite raw inputs. Replace only stale chunks matching this exact output stub, after successful validation; pilot runs must not mix with or overwrite production calibration outputs.

Also save compact machine-readable outputs, for example under `output/calibration/`, with paths declared in the master:

- Resolved settings, target source and coverage, input fingerprints, run identity, and software/session information.
- Selected factors and bounds, per-stratum identity and selected grid scores, and final joint scores.
- A target-versus-prediction panel keyed by country, sex, cause, age band, year, and measure, with observed, uncalibrated, and calibrated counts.
- Aggregate, country-level, and subgroup diagnostics.

These diagnostics must have names outside the `adjusted_searo_part*.rds` discovery pattern. The artifact report should consume saved results, not rerun the grid search.

## 5. Update stage 6 and master orchestration

Source the new calibrator once from the master and stop calling the legacy calibration/adjustment chain. Remove obsolete active flags and dependencies used solely for duplicate calibration, including the stage-6 `run_adjustment_model` block reading `adjustments2023_age.csv`.

Read historical calibrated chunks with an anchored pattern such as `^adjusted_searo_part[0-9]+\\.rds$`, rather than a broad `"adjusted"` match. Assert the expected historical coverage. Extend the final observed rates to projection years exactly once, without duplicate keys, and then attach year-specific population and COVID inputs and apply the existing prospective trend options. Historical IR/CF must remain the saved calibrated values, subject only to explicitly documented necessary feasibility handling.

Preserve the scientific assumptions and numerical formulas of the existing projection adjustments; this task moves their responsibility clearly into stage 6. Inspect ordering: the current code has probability checks before later rate adjustments. Ensure final guards run after all relevant prospective modifications and verify their constraints. Keep the calibrated historical RDS files immutable while preparing the in-memory projection panel. Verify that stage 6 still creates every object and column consumed by the unchanged runner.

## 6. Update manuscript methods and supplementary in-sample performance

The WHO manuscript example will **not** be provided with this request. Its relevant section, “Calibration methods and performance,” has the structure below. Reproduce that reporting approach for this project's actual GBD targets and implemented method; do not copy WHO-specific claims or numbers.

In the main Methods, replace the outdated two-step calibration description with a concise account of the historical inputs, target source, fitting period, country–sex–cause–age-band multipliers, weighted RMSE loss, and single application of fitted factors. Describe prospective secular trends separately as stage-6 projection assumptions. Include a short, artifact-driven statement of in-sample fit and a link to the supplement.

Add a dedicated supplementary subsection with:

1. **Uncalibrated rates:** how upstream prevalence/death data yield initial IR/CF and how five-year ages become single-age inputs; verify the actual formulas and end-age treatment rather than assuming those in the WHO project.
2. **Targets and coverage:** source/version, deaths and prevalence as counts, countries, sexes, causes, age bands, years, number of target cells, and handling of missing values and observed zeros.
3. **Objective and search:** the equation above; actual weights, grid values and pair count; caps, initialization, entrants, age handling, deterministic ties, time-constant factors, and historical years receiving them. Distinguish exhaustive selection from the final joint run. State whether there is any refinement or stopping rule; do not invent one.
4. **Performance measures:** before/after runs on exactly the same targets and cells. For each measure, report `WAPE = sum(abs(predicted - observed)) / sum(observed)` and `aggregate bias = sum(predicted) / sum(observed) - 1`. When the denominator is zero, report the percentage measure as undefined and retain absolute error; do not add an arbitrary denominator or label undefined values as zero. Also retain the weighted RMSE objective diagnostics.
5. **Results:** overall WAPE and bias; median and IQR of country WAPE; numbers of countries improving for each outcome; selection-stage versus joint objective changes; fraction of strata improving jointly; IR/CF multiplier summaries and counts/proportions at each grid boundary. Report deterioration where present.
6. **Supplementary table:** before/after WAPE and bias for deaths and prevalent cases, with rows for all manuscript countries, cause, sex, age group, and the geographic/income groupings already supported by this project. Include subgroup coverage. Do not add new external classification dependencies without approval. Save detailed country results as a machine-readable companion.
7. **Supplementary figure:** annual target, uncalibrated-model, and final calibrated-model deaths and prevalent cases, summed across the manuscript countries and faceted by cause and measure, restricted to the fitting period. The caption must state that aggregate agreement can conceal stratum-level errors.
8. **Limitations:** in-sample fit is not external or temporal validation; calibration targets are themselves estimates; grid boundaries, time-constant multipliers, and coupled-stratum selection may limit fit. Separate these results from future comparisons against UN-WPP, GBD Foresight, or published intervention estimates.

All numerical claims, labels, periods, counts, tables, and figures must be generated from the new calibration outputs and saved settings through `reports/manuscript-100mlives2-artifacts.Rmd`. The manuscript should load saved artifacts, not run calibration calculations. Integrate new items into the existing inventory, scalar/table/plot stores, provenance, tracking workbook, and cross-references. Do not use legacy hardcoded values as substitutes for missing new calibration results.

The current artifact report derives some historical “observed” deaths from `Nx * DIS.mx.t0`; that is not simulated calibration performance. Use the saved target/prediction panel for the new benchmarks, and label existing historical observations correctly. Do not use stage-7 future outputs or trend-adjusted stage-6 rates as the source of in-sample fit.

Keep existing external projection comparisons separate and preserve unrelated manuscript content. Refresh affected model-derived results after the approved rerun; do not combine new calibration claims with stale intervention outputs. If a full rerun or render is blocked, identify affected results explicitly and do not claim they were updated.

## 7. Run, verify, and deliver

After resolving any scope questions:

1. Parse changed R files and check their dependencies. Verify the runner and all other protected source files remain unchanged.
2. Run a small deterministic pilot in isolated output paths. Check key uniqueness, input/target coverage, age-boundary and entrant behavior, identity-score reproduction, cap consistency, and whether saved rates reproduce the reported joint fit. Compare sequential and parallel results where parallel execution is used.
3. Verify stage 6 consumes the new chunks, extends years without duplicates, applies no second calibration factors, leaves historical calibration files unchanged, and supplies the runner's required objects. Check final probability constraints and shared-population/background-death accounting.
4. Run the full calibration and rebuild stage 6. Rerun affected model scenarios through the existing runner unchanged, then rebuild the artifact report and render the manuscript in its existing supported format. Preserve unrelated outputs and use run provenance to prevent stale/new mixtures. If inputs or execution resources are unavailable, stop only the blocked steps and state precisely what remains unverified.
5. Check that every new table/figure/scalar agrees with the saved predictions and configuration, all captions say **in-sample**, and no obsolete two-pass calibration description or live adjustment dependency remains.

Finish with the files changed, resolved master path, actual settings and target source, concise before/after joint-fit results, boundary diagnostics, checks performed, and exact commands to reproduce calibration, projections, artifacts, and manuscript. Distinguish successful execution from checks that could not run. List any additional source changes still requiring my approval.
