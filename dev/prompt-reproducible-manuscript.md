# Claude Code prompt: make the 100M Lives manuscript reproducible (v2)

Do this task in the existing repository. Read the files and their dependencies, make the changes and check them. Do not stop at a plan. Start by writing the inventory (see "Trace the existing workflow") into the artifact-generation Rmd, then carry on with the build.

## Goal

Every result in the manuscript that existing project inputs and outputs can support should be reproducible from one standalone R Markdown file that generates the artifacts. The manuscript Rmd should only load prepared artifacts and display them. It should not calculate anything.

Some results cannot be recalculated yet, such as the sensitivity analyses. Keep those exactly as they are and mark each gap with a comment in the source code. Do not claim the manuscript is fully reproducible while any gap remains.

## Files to read first

- `manuscript/manuscript-100mlives2.Rmd` lists everything the manuscript and supplement use. Treat it as the authoritative inventory.
- `reports/UWRTSL-100MLivesRMD_Output.Rmd` holds the existing analysis and reporting logic and already makes many of the artifacts. Do not edit it.
- `manuscript/manuscript-100mlives2.xlsx` is the current tracker. It has an `Index` sheet, one sheet per table (`T1_Scenarios`, `T2_DeathsDelayed`, `TS1_Regions` … `TS9_Assumptions`) and a `Figures` sheet that maps each figure panel to its file. Each table sheet has a title in row 1, headers in row 3, data from row 4, then a blank row and a "Notes:" row. Read every sheet, including the titles and notes.

You may look at any other repository file or existing data/output file to work out dependencies.

## Files you may change

Source files: only these two.

1. **Modify** `manuscript/manuscript-100mlives2.Rmd`.
2. **Create** `reports/manuscript-100mlives2-artifacts.Rmd`. Use this path everywhere and do not create a second artifact Rmd.

Generated outputs: allowed only in these locations, and only the artifact Rmd writes them.

| Output | Location |
|---|---|
| Small R objects (scalars, display-ready tables, plot data, provenance) | `manuscript/artifacts/*.rds` |
| Every table the manuscript uses | `manuscript/tables/*.csv` |
| Every figure panel the manuscript references | `manuscript/figures/*.png` |
| Tracking workbook, regenerated | `manuscript/manuscript-100mlives2.xlsx` |

Do not change anything else: the reporting Rmd, model code, inputs, `references.bib`, `reference.docx`, `word-layout.lua`, `apa.csl`, configuration or `.gitignore`. Leave any unrelated changes already in the repo alone. Do not commit or push.

## Scope: only what the manuscript uses now

Only produce the figures, tables and numbers that the current manuscript and supplement use, plus the minimum supporting data and tracking metadata they need. Do not reproduce the whole report, export unrelated analyses or add new scientific outputs.

A workbook entry on its own does not count as a reason to produce an artifact. Things that stay out because the manuscript does not use them include the incidence/prevalence plots, the sodium and TFA input maps, the Kontis comparison map, the disaggregation bubble plot and the DT/plotly widgets.

**Tables** (CSV name = sheet name):

| Manuscript item | Sheet / CSV |
|---|---|
| Table 1 | `T1_Scenarios` |
| Table 2 | `T2_DeathsDelayed` |
| Table S1 | `TS1_Regions` |
| Table S2 | `TS2_CompareIntervention` |
| Table S3 | `TS3_CompareCountry` |
| Table S4 | `TS4_ModelCompare` |
| Table S5 | `TS5_Premature_Sex` |
| Table S6 | `TS6_Premature_Top30` |
| Table S7 | `TS7_ByCountry` |
| Table S8 | `TS8_Sensitivity` |
| Table S9 | `TS9_Assumptions` |

The math supplement also contains five pipe tables:

- case-fatality reduction factors;
- TFA age-specific relative risks;
- statin relative risks;
- transition rates;
- notation.

Export each one to CSV and keep its existing caption. Do not give it a new table number. Leave these tables as inline Markdown in the manuscript so the LaTeX math still renders. Check the parameter values in these tables against the constants in the model code and report any that do not match.

**Figures:** there are 16 panels. Keep these file names exactly:

```text
fig1a_annual_deaths_delayed.png      fig1b_cumulative_deaths_delayed.png
fig2_deaths_delayed_sex_age.png      fig3a_map_pct_delayed_female.png
fig3b_map_pct_delayed_male.png       fig4_deaths_delayed_sex_age_region.png
figS1a_traj_hypertension_control.png figS1b_traj_sodium.png
figS1c_traj_tfa.png                  figS1d_traj_statins.png
figS2a_required_htn_scaleup.png      figS2b_historical_cascade_changes.png
figS3_asmr_by_cause.png              figS4a_asmr_index_vs_foresight.png
figS4b_deaths_vs_foresight.png       figS5_deaths_vs_unwpp.png
```

## Trace the existing workflow

List every manuscript-specific number in the abstract, results, discussion, comparisons, figure notes and supplement text (for example the Validation paragraph and the "Comparison to previous work" section), not only the table cells. Give each item:

- an artifact ID;
- where it appears in the manuscript;
- its input files and the columns it needs;
- its scenario, population, filters and units;
- how it is calculated;
- the report chunk it comes from;
- its output path;
- its status, using one of these:
  - `reproduced`: calculated by the artifact Rmd from repo inputs or outputs.
  - `fixed_external`: a value quoted from published literature, such as the Kontis et al. and Pickersgill et al. columns in Tables S2/S3. Hard-code it with a citation comment.
  - `static_content`: author-written text that is not a calculation, such as Table S4, Table S9, the descriptive columns of Table 1 (RR, risk population, target, scale-up pattern) and the math pipe tables.
  - `preserved_pending`: a model result that cannot be recalculated yet. Keep the current value and mark the gap.

Keep this inventory in the artifact Rmd and in the workbook. Do not write a separate report.

Literature figures in the Introduction (75% of NCD deaths, 17.9 million, 66 countries, 34 million patients, and so on) and the front-matter word count are citations or metadata. Leave them as they are and do not track them as results.

**Where each item probably comes from.** Check each of these against the actual dependencies; do not copy whole chunks without checking them.

| Manuscript item | Likely chunk(s) in `reports/UWRTSL-100MLivesRMD_Output.Rmd` |
|---|---|
| Table 2, Results and Abstract numbers | `output-data`, `output-functions`, `output-table1`, `out-tab-int-caut`, `out-tab-int-cau` |
| Fig 1a/1b | `output-tsplot` (`out_deaths_time`, `out_deaths_time_cum`) |
| Fig 2 | `1out-int-age` (`out_barplot_deaths_delayed_age`) |
| Fig 3a/3b | `out-map-mx`. That chunk saves *death-rate* maps, but these files must show the **% reduction in deaths vs BAU**, as the caption says |
| Fig 4 | `out-int-region` and the age/sex/region plot |
| Table S1 | `output-countrylist` |
| Tables S5, S6 | the `ADD: <70 outputs` block near the end |
| Table S7 | `out-tab-loc` |
| Tables S2/S3, "This study" column | totals by intervention and by country from the same outputs |
| Table 1 baseline column | 2025 baselines from the policy scenario inputs, weighted by 2019 UN-WPP population (as the Table 1 note says) |
| Fig S1a–d | `out-policy-bp`, `out-policy-salt`, `out-policy-tfa-scenarios`, `out-policy-statins` |
| Fig S2a/S2b | `out-policy-bp-past` (beeswarm of required AROC; boxplot of historical NCD-RisC changes) |
| Fig S3 | the ASMR-by-cause section of `output-mortality` |
| Fig S4a/S4b | `valida-ihme-foresight`, `valida-ihme-foresight2` |
| Fig S5 | `output-mortality` (`out_unwpp_model_deaths`) |

**Inputs that probably exist:** `output/out_model/*.rds`, `Country_groupings_extended.csv`, and processed files under `data/processed/UN2024/`, `BloodPressure/`, `Sodium/`, `TFAPolicy/` and `Statins/`. Find the actual paths and schemas in the repo.

**Inputs outside the repo.** Some chunks read files from absolute OneDrive paths:

- `C:/Users/wrgar/OneDrive - UW/.../100MLives/data/raw/NCD-RisC/` for Fig S2b;
- `.../data/raw/GBD` (Foresight) for Fig S4 and the Validation numbers;
- the Powles sodium file.

For each one:

1. Look for an equivalent file inside the repo (`data-raw/`, `data/processed/`).
2. If you find one, use it through a relative path.
3. If you don't, mark the item `preserved_pending`. Do not invent data or substitute a different source.

## Build `reports/manuscript-100mlives2-artifacts.Rmd`

This file must be the only executable source for manuscript-specific calculations, summaries, table preparation and figures. It reads existing inputs and simulation outputs and does not rerun the model.

**Environment**

- Use R with **`data.table`** for all data work and **`ggplot2`** for all figures.
- Use other packages only where needed: `readxl`, `openxlsx`, `sf`/`rnaturalearth` for the Fig 3 maps, `here`/`rprojroot`.
- Do not use tidyverse or dplyr pipelines. Rewrite any logic you take from the report. Do not install packages automatically.
- It must run in a clean R session: no `.RData`, no objects left over from earlier, and no sourcing or rendering of the reporting Rmd. Comment where each piece of adapted logic came from.
- Build paths from the repository root with `here::here()` or `rprojroot`, so the file works whether it is run from the repo root, `reports/` or `manuscript/`. No machine-specific paths and no permanent `setwd()`.
- Put all settings in one setup chunk, so every downstream chunk uses the same ones:
  - the analysis window;
  - intervention labels;
  - the cause map;
  - age groups;
  - region map;
  - excluded locations;
  - the WHO standard population.
- Keep all helper functions and constants inside this Rmd. Do not create helper scripts.
- Lay the file out as one section per manuscript item, in manuscript order. Each section header should say what it produces and what it reads.

**Inputs and calculations**

- Check each input before using it: required files, schema, keys, units and scenario coverage.
- Select inputs narrowly so alternate runs or uncertainty draws are never combined by accident.
- Keep full precision through the calculations. Prepare all display values here, including rounding, %, millions, annual averages, row order, blank repeated labels and bold rows. Store full-precision and display values side by side.

**Saving outputs**

- **Scalars:** save `manuscript/artifacts/scalars.rds` as one named list or data.table with these columns: `key`, `value` (full precision), `display` (formatted string as it appears in the text), `unit`, `status` and `source`. Use clear keys such as `dd_all_total_M`, `dd_all_pct`, `bau_total_M`, `dd_all_per_year_M`, `dd_htn_total_M`, `dd_u70_pct` and `dd_region_ssa_pct`.
- **Tables:** write every manuscript table with `fwrite()` to `manuscript/tables/<sheet>.csv` as numeric values. Save display-ready versions, ready to render, in a compact RDS (for example `artifacts/tables_display.rds`).
- **Figures:** build every reproducible figure with `ggplot2` and save it with `ggsave()`. Use explicit dimensions and dpi of 300 or lower. Match the existing scientific content, panels, labels, units and look. Copying an existing PNG does not count as reproducing it.
- Save objects with `saveRDS(..., compress = "xz")`.

**Size: the `manuscript/` folder is tracked on GitHub**

- Never save `data.out`, single-age or country-year panels, raw inputs, map geometry, cached objects, images embedded in Excel, or duplicate formats of the same data.
- Aim for less than about 1 MB per file and a few MB in total under `manuscript/artifacts/`.

### Check the estimands and catch inconsistencies

Check the following for each result rather than carrying them over from the report: time window, age range, cause aggregation, population weighting and denominator.

- **Window and annual-average divisor.** The manuscript mostly uses **2026–2050 inclusive** (25 years; for example 74.4/25 = 2.98). Some other places imply a different window:
  - Table S8 "per year" values imply a divisor of **24** (74.4 → 3.1);
  - the TFA comparison mentions "24 years";
  - the captions of Tables S5/S6 and parts of the report say **2025–2050**.

  Settle the window for each item from the scenario metadata and the intended estimand. Never mix windows silently. If an item stays ambiguous, keep its legacy value, mark it pending and report it.
- **Labels before joining.** Confirm the BAU and intervention labels before any join. The report maps `baseline` to `b.a.u` and `BP + Salt + TFA + Statins` to `All Interventions`, and it drops `Both`, `BP + Salt + TFA` and `BP + Salt`. Deaths delayed = BAU − intervention, calculated within matching strata.
- **Combined effect.** Use the simulated combined scenario for the combined effect. Never add up the four separate effects.
- **Fig 1 stacking.** Fig 1 stacks the separate effects. State this in a code comment. Do not present the top of the stack as the combined effect, and do not rescale or invent weights to make it match.
- **Causes and populations.** Keep the four modelled CVD causes separate from all-cause/background mortality. Avoid double-counting a pre-aggregated `all` cause, and avoid counting population more than once when it repeats across cause-specific models.
- **Percentages in Tables S5/S6.** A % reduction relative to BAU premature deaths is different from the share of delayed deaths that occur before age 70. Make sure each column uses the meaning stated in its note.
- **Groups and comparators.** Keep the existing country and region definitions. Reproduce age-standardisation and validation comparators only when the weights, age ranges and inputs are verified.

**Text and number inconsistencies to check and report.** Do not rewrite the narrative to fix these. Report them to me.

- **Statins:** the text gives a total of 10.9M, but the IHD (10.6M) and ischemic stroke (0.7M) figures add up to 11.3M.
- **Results order:** the sentence says most deaths delayed are from IHD (42.3M), "followed by" ischemic stroke (21.7M) and then ICH (45.0M), but 45.0M is the largest.
- **Sex paragraph:** "17% reduction for women (61.1 million)" is introduced as deaths *before age 70*, but 61.1M looks like the all-age total (Table S5 shows about 14.2M for women under 70).
- **"Premature CVD mortality"** is used for all-age percentages (10.7%, 5.2%, 0.6%, 1.6%).
- **One in six vs one in five:** the Abstract says "one in six", the Discussion says "one in five".
- **TFA reduction:** 0.6% in the Results, 0.7% in the Discussion. The TFA per-year figure is "190,000" while 4.5/25 = 0.18M.
- **Figure reference:** the age-group comparison in the Results cites **Figure 4**; check whether it should be Figure 2.

Do not change scientific assumptions or model code to make numbers agree. When a verified calculation differs from the manuscript, update that reproduced value everywhere it appears and explain the difference. If the difference depends on an unresolved methods choice, keep the old value and mark it pending.

### Keep legacy content without reading the workbook back in

The workbook is regenerated, so it cannot also be an input. For `fixed_external`, `static_content` and `preserved_pending` items:

- Write the current values into the artifact Rmd as explicit `data.table` constants, with their provenance (sheet/cell or manuscript line) and status.
- Write them to the same CSV/RDS outputs, clearly marked as not calculated.
- Never read the generated workbook, or any earlier artifact build, as an input.

## Make `manuscript/manuscript-100mlives2.Rmd` presentation-only

Keep the narrative, structure, authors, citations, equations, captions, table numbering, figure links and widths, `{=openxml}` page breaks and Word formatting. The only changes should be reproducibility substitutions and any supported number updates.

**Setup chunk**

- It may only load artifacts: `readRDS()` for scalars and display tables, and lookups by name.
- Keep the purely presentational helpers needed for Word layout (`show_tab` with column widths, `bold_rows`).
- Remove `read_tab()` and the xlsx dependence completely. Every table, including pending and static ones, now comes from the artifacts.
- If an artifact is missing, `stop()` with a clear instruction to run the artifact Rmd first.

**Inline numbers**

- Replace every reproduced number with an inline lookup of its prepared display string, for example `` `r S$display[["dd_all_total_M"]]` ``. This includes repeated mentions in the Abstract, Results, Discussion and supplement.
- Keep the wording and displayed precision exactly as they are.

**Not allowed in the manuscript:** sums, differences, ratios, percentages, rounding or formatting of raw values, annual means, cumulative totals, rankings, reshaping, subgroup summaries, `ggplot()` and inline arithmetic. Number formatting belongs in the artifact Rmd.

**Header comment and setup comment**

- Replace the setup comment that calls Excel the "single source of truth". The new comment should say: the generated artifacts drive the numbers, and the workbook is for tracking and review only.
- Add a short header comment that covers:
  - the run order: knit the artifact Rmd first, then the manuscript;
  - the exact commands to run;
  - how to find the remaining gaps by searching for `REPRO_PENDING`.

**Pending markers.** Put a hidden chunk (`include=FALSE`) immediately before each affected paragraph, table or figure. It must not print in the Word output. Use the `REPRO_PENDING` tag every time so the markers are easy to search for. For example:

````
```{r pending-tableS8, include=FALSE}
# REPRO_PENDING [Table S8 + Sensitivity analysis paragraph]
# Status: preserved_pending. Values carried over from the legacy workbook (TS8_Sensitivity!A3:G23).
# Missing: alternative-trend simulation outputs (no trends, LC trends, GBD Foresight) and scenario mapping.
# To update: supply those outputs, implement the calculation in
# reports/manuscript-100mlives2-artifacts.Rmd, switch this text/table to artifact lookups,
# then delete this marker.
```
````

Write a specific marker for each gap. Likely gaps are listed below; resolve as many of them as the existing outputs support.

- Table S8 and the Sensitivity analysis paragraph.
- The "This study – Kontis methods" column in Tables S2/S3, which needs the replication runs.
- Discussion: the 16.5M gain from reaching the target in 2040 rather than 2050.
- Discussion: India's TFA ban (about 4M).
- Discussion: China's ~40% share of the sodium effect, and the 7.04 vs 4.83 g/day comparison.
- Discussion: the 1% vs 0.7% TFA comparison.
- The Validation paragraph (34M in 2050, 23M in GBD Foresight, 87.4M from UN-WPP) and Fig S2b/S4, if their inputs are outside the repo.

Never invent a calculation, substitute the main scenario, drop content quietly or overwrite a valid legacy PNG with a placeholder. If both a legacy figure file and its inputs are missing, keep the reference, mark the gap and report that rendering is blocked.

## Regenerate the tracking workbook

Build `manuscript/manuscript-100mlives2.xlsx` with `openxlsx`, from the same prepared objects used for the RDS, CSV and PNG outputs.

- Keep the existing sheet names, titles and notes, and the layout (title in row 1, headers in row 3, data from row 4, a blank row, then the Notes row).
- Keep and update `Index` and `Figures`.
- Add two compact sheets:
  - `Scalars`: every number used in the text, with key, display string, manuscript location, unit and status.
  - `Provenance`: artifact ID, inputs, chunk, output path, status and the pending dependency.
- In tables that mix calculated and legacy cells, mark which cells were regenerated and which were preserved.
- Do not embed images or raw data. Updating reproduced results must never require editing Excel by hand.

## Check and finish

1. Run the artifact Rmd in a fresh R process. Give the exact command. Send any incidental knit output to a temporary directory, for example: `Rscript -e 'rmarkdown::render("reports/manuscript-100mlives2-artifacts.Rmd", output_dir = tempdir())'`.
2. Confirm that:
   - every generated file corresponds to current manuscript content;
   - every table the manuscript uses has a CSV;
   - every figure either regenerates or has a tracked gap.
3. Check data integrity:
   - matching BAU/intervention keys;
   - duplicates;
   - aggregation by cause and population;
   - inclusive year counts and divisors;
   - percentage units;
   - missing or non-finite values;
   - consistency between scalars, tables and plot data.
4. At the end of the artifact Rmd, add a chunk that compares every reproduced value with the old manuscript and workbook at their displayed precision. It should print a discrepancy table in the knitted output only, without saving it to the repo. Flag differences larger than rounding, and explain them rather than forcing them to match.
5. Confirm that each reproduced number is the same everywhere it appears (Abstract, text, tables, figures, supplement), that pending markers are hidden, and that unsupported results are unchanged.
6. Render the manuscript to Word in a separate fresh R process, with the output outside the tracked source tree. Use the existing Word dependencies unchanged. If packages, Pandoc, inputs or templates block a run, say exactly what ran and what is still unchecked.
7. Run a second artifact build to show it does not depend on the generated workbook or on earlier artifacts. The numbers should match; the workbook bytes and timestamps do not need to.
8. Review `git status`/`git diff` and the output sizes. The only source changes should be the two allowed Rmd files, and generated outputs should be only in the approved paths.

**Final response.** Keep it short and include:

- the changes you made;
- the exact commands to build the artifacts and render the manuscript;
- a table of file sizes;
- the inventory summary, with counts by status;
- the discrepancy table and the text inconsistencies you found;
- every `REPRO_PENDING` item with what it needs.

Do not describe preserved results as recalculated, and do not claim end-to-end success if any required content is unchecked.
