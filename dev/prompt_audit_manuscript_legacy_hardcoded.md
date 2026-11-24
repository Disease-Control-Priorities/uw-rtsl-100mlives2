# Audit the 100 Million Lives manuscript for legacy content and hardcoded results

You are working in the `uw-rtsl-100mlives2` repository. Conduct a comprehensive, evidence-based audit of the manuscript and its artifact-generation workflow to identify everything that still reflects an older model version, contains hardcoded study results, lacks a reproducible source, or needs recalculation or new model runs.

**This task is an audit and an actionable update plan. Do not modify the manuscript, production scripts, inputs, or existing outputs, and do not launch full model, calibration, sensitivity, or comparison runs. Create only the audit deliverables specified below.** Small read-only checks of existing files are allowed. Do not render Rmd files in place if rendering would overwrite outputs.

## 1. Establish the current implementation and evidence

Read the repository instructions and inspect the current working tree, branch, and commit. Preserve all existing changes. Identify the actual current files rather than assuming numbered attachment suffixes represent repository filenames.

Start with:

- `manuscript/manuscript-100mlives2.Rmd`.
- `reports/manuscript-100mlives2-artifacts.Rmd`; locate it if its repository path differs.
- `manuscript/artifacts/`, `manuscript/tables/`, `manuscript/figures/`, and the tracking workbook `manuscript/manuscript-100mlives2.xlsx`, where available.
- `reports/UWRTSL-100MLivesRMD_Output.Rmd` and relevant helper scripts.
- The current pipeline runner, input preparation, calibration, baseline construction, mortality-trend code, and stage-7 intervention model, including `code/7. model_100_multiplicative_func_new3_gbd23_noaroc.R` if present.
- Existing sensitivity and comparison scripts, including `08_run_sensitivity.R` and `09_run_comparisons.R` **if they exist**. Do not assume previously proposed scripts were implemented.
- Calibration settings, `output/out_model/model_run_manifest.rds`, forecast diagnostics, provenance records, and run logs.
- `manuscript/references.bib` for cited evidence. Locate the actual bibliography if the filename differs.

Establish the current calibration, mortality-trend implementation, intervention effect calculations, scenario definitions, country/age/cause coverage, and analysis horizon from code and run metadata. Check whether outputs actually reflect the current implementation, including any recent blood-pressure relative-risk corrections. File modification times alone are insufficient proof of compatibility.

## 2. Audit every manuscript component end to end

Cover the abstract, Methods, Results, Discussion, supplement, mathematical description, all tables and figures, captions, notes, and inline numerical or qualitative claims.

Trace each item through:

`manuscript statement/table/figure → scalar key or artifact → generating expression → input/model output → producing script and run configuration`.

An inline `sc("...")`, generated table, or successful knit does **not** prove that a value is current. Inspect upstream literals, fallback values, manually assembled vectors, legacy workbook values, copied images, stale cached outputs, and assumptions read from source code rather than the run that generated the results. Search beyond existing `REPRO_PENDING` markers and status labels; audit those labels too.

Distinguish:

1. Current study results reproduced from compatible outputs.
2. Current study results that can be recomputed from existing outputs.
3. Legacy or hardcoded study results requiring new model runs.
4. Methods, equations, labels, or narrative inconsistent with the implementation.
5. Fixed external literature estimates or intentional scenario assumptions that can legitimately remain constants when their sources and meaning are clear.
6. Unverifiable items with missing provenance, inputs, or an undefined estimand.

Do not classify all numeric constants as errors. Conversely, do not accept a study result merely because it is tagged `reproduced` or `static_content`. Report mixed tables at the row, column, or cell-group level.

## 3. Priority: sensitivity analysis and Table S8

Audit **“Table S8. Background and CVD mortality trends sensitivity scenarios on million deaths that could be delayed by intervention, 2026–2050”**, plus every associated Methods, Results, and Discussion claim.

The attached artifact-generator snapshot contains a hardcoded `ts8_leg` table, refreshes only the base-case rows using coherent-trend outputs, and retains legacy alternative scenarios. It also sets `yr_s8_start <- 2025L` despite the 2026–2050 title and documents inconsistent annual divisors. Verify the repository's current state rather than assuming it is unchanged.

Specifically:

- Trace the base case, independent Lee–Carter, no-background/no-CVD-trend, and IHME/GBD Foresight scenarios to their actual runs or constants.
- Verify the provenance of the sensitivity scalars `sens_no_trend_dd_M`, `sens_lc_dd_M`, `sens_foresight_dd_M`, and `sens_pct_range`; the snapshot preserves approximately 116, 117, and 102 million and 17%–18%.
- Check the exact Foresight release: labels mentioning GBD 2019 may conflict with input filenames mentioning GBD 2023. Identify the actual source and whether it is used for a scenario or only an external comparison.
- Specify the missing runs needed to regenerate the entire table with the current calibration and intervention engine. Every sensitivity scenario must have a matching scenario-specific BAU; do not subtract intervention deaths from an unrelated base-case BAU.
- Keep non-trend assumptions identical across these scenarios. Explain precisely how each alternative changes background mortality, cause-specific mortality, incidence, or case fatality, and identify any mortality-accounting implications.
- Standardize cumulative results to **2026–2050 inclusive**, with annual averages divided by **25 years**. Audit projected deaths, baseline deaths, deaths delayed, percentages, units, and denominators.
- Explain which parts require rerunning the model versus only rebuilding artifacts. Relabeling old values or knitting the generator again does not regenerate sensitivity analyses.

## 4. Other known leads—verify and extend

Investigate at least these snapshot-identified gaps, without limiting the audit to them:

- Tables S2/S3: the “This study – Kontis methods” replication column, distinguished from published Kontis/Pickersgill estimates.
- Hypertension target timing: the claimed **16.5 million** difference between reaching the target in 2040 versus 2050.
- India's TFA policy counterfactual and claims of **roughly four million** deaths affected.
- Comparison claims about **41 million** hypertension deaths delayed, **32 million** sodium deaths delayed in China, and TFA effects attributed to policy changes.
- Table 1's **37%** hypertension-control baseline: source, year, weighting, and denominator.
- TFA regional and age-specific percentages with unclear estimands.
- All remaining 2025/2026 start-year, 24/25-year divisor, calibration, and independent/coherent-trend inconsistencies.
- Qualitative claims about rankings, timing, regional differences, mechanisms, and external agreement that may no longer follow from current results.

## 5. Deliverables

Save the audit as a Markdown file at `dev/audit_manuscript_legacy_hardcoded.md` and the matching findings register at `dev/audit_manuscript_legacy_hardcoded.csv`. Create the `dev/` folder if it does not exist. The Markdown report is a required deliverable; do not provide the audit only in the chat response.

The report must include:

1. A concise assessment of what is current, what is legacy, and what prevents the manuscript from being fully current and reproducible.
2. A prioritized findings table with: ID; severity; manuscript location; affected artifact/scalar; current value or claim; classification; evidence (`path:line`, chunk, workbook cell, or metadata field); required action; producing script/input; downstream text/tables/figures affected; and verification criterion.
3. A dedicated Table S8 section identifying exactly which rows are current, legacy, or unverifiable and how to regenerate them consistently.
4. A minimum rerun matrix grouping findings that share a required run. Include scenario settings, corresponding BAU, current prerequisites, expected output locations (verified or explicitly proposed), dependent artifacts, and execution order. Separate sensitivity runs, comparison replications, policy/timing counterfactuals, and artifact-only recalculations.
5. A short list of legitimate fixed external values and intentional assumptions, plus unresolved questions that genuinely require an author decision.
6. A checklist for confirming, after future implementation, that all affected outputs and manuscript statements were refreshed together.

Use **confirmed**, **suspected**, or **unverifiable** for the evidence strength. Never invent missing results, script names, commands, or provenance. Give executable rerun commands only when the existing interfaces support them; otherwise describe the required implementation. Reuse existing provenance inventories, but reconcile them against the actual dependencies.

Finish with a concise summary of the highest-priority findings and the minimum work needed to update the manuscript. **Do not implement fixes or run the proposed analyses in this task.**
