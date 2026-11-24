# Audit: legacy content and hardcoded results in the 100 Million Lives manuscript

*Audit date: 2026-11-23. Read-only audit: no manuscript, script, input or output was changed, and no model, calibration, sensitivity or comparison run was launched. Companion register: [`audit_manuscript_legacy_hardcoded.csv`](audit_manuscript_legacy_hardcoded.csv) (one row per finding, same IDs).*

**Evidence strength.** **Confirmed** means verified against code, run metadata or a recomputation from existing outputs. **Suspected** means the inconsistency is likely but depends on information that is not in the repository. **Unverifiable** means no source exists in the repository.

**Classification codes** (task §2):

| Code | Meaning |
|---|---|
| C1 | Current study result, reproduced from compatible outputs |
| C2 | Current study result that can be recomputed from existing outputs (artifact-only fix) |
| C3 | Legacy or hardcoded study result that needs new model runs |
| C4 | Methods, equation, label or narrative inconsistent with the implementation |
| C5 | Fixed external estimate or intentional scenario assumption (legitimate constant) |
| C6 | Unverifiable: provenance, input or estimand missing |

---

## 1. Assessment

### State of the repository

- **Branch and commit:** `william` at `2c117f3` ("update calibration process"). The working tree has large uncommitted changes, all preserved by this audit:
  - modified: stages 0, 2, 6 and 7, the manuscript Rmd, the artifact generator, every model output, artifact, table and figure;
  - renamed but **untracked:** `code/4. prepare_interventions.R`;
  - new and untracked: the coherent-trend files and `output/out_model/model_run_manifest.rds`.
- **Production model run:** `20261123-191232-7e0f6eae` (2026-11-23 19:12–19:58 PST), plus one partial rerun (Norway, 20:02).
  - Run settings: coherent (reconciled) mortality trends, trend run `20261123-190928-2ab47d5f`; case fatality (CF) changes by 80% of the cause trend; calibration run `20261123-120744-3fcb9cbd` (single pass).
  - Scope: 190 countries, ages 20–95, four causes, eight scenarios.
  - Runner md5 `f4776e8b…`. This md5 equals the current file, which was last modified at 17:22 that day and already contains the hemorrhagic-stroke BP relative-risk fix (`code/7. model_100_multiplicative_func_new3_gbd23_noaroc.R:387,398`; the committed HEAD still has `RRi_HSTROKE := RRi_ISTROKE`).
  - **The current outputs therefore reflect the current calibration, the coherent trends and the RR fix (confirmed).**
- **Artifacts:** rebuilt at 20:53 from exactly the manifest's 190 output files. The generator checks md5s, run ids and trend ids at `reports/manuscript-100mlives2-artifacts.Rmd:680-713`. The Word document was knitted at 20:53.

### What is current

Every value tagged `reproduced` in `manuscript/artifacts/scalars.rds` (181 scalars), Table 2, Tables S1, S5, S6, S7, S10 and S11, and Figures 1–4 and S1–S6 come from the current run. This includes:

- the headline values: 85.8 M deaths delayed, 14.7%, 3.43 M per year, BAU 581.5 M;
- the cause, sex, age and region splits;
- the comparison ratios against the quoted Kontis and Pickersgill totals;
- the calibration and mortality-forecast numbers.

The cumulative window is 2026–2050 with a divisor of 25 (`reports/manuscript-100mlives2-artifacts.Rmd:51-59`). Deaths delayed in 2025 are exactly zero (recomputed from the outputs).

### What is legacy

Fourteen scalars and parts of four tables are hardcoded legacy values from **runs that no longer exist in the repository**:

- Table S8: 15 of 20 rows;
- Tables S2 and S3: the "This study – Kontis methods" column;
- "16.5 million" (hypertension target year 2040 vs 2050);
- India's TFA "four million";
- "41 million", "32 million", "just over 4.5 million over 24 years" and "about 10 million";
- the sensitivity scalars 116, 117, 102 and "17%–18%";
- the Table 1 hypertension baseline (37%).

These runs predate **four** changes, not two:

1. the single-pass calibration;
2. the coherent mortality trends;
3. the hemorrhagic-stroke RR normalization fix;
4. the current stage-4 inputs (the Indonesia TFA carry-forward, `code/4. prepare_interventions.R:292-300`, and the IHME-population weighting).

The manuscript discloses only the first two (`manuscript/manuscript-100mlives2.Rmd:234,279,678`).

### What blocks a fully current and reproducible manuscript

1. **No sensitivity or counterfactual machinery exists.**
   - The master sources `code/8. run_sensitivity.R` and `code/9. run_benchmark.R`, which do not exist (`code/0. master.R:392-401`). The `08_run_sensitivity.R` and `09_run_comparisons.R` named in the task do not exist either.
   - Stage 7 always writes to `output/out_model/` (`code/7. model_100_multiplicative_func_new3_gbd23_noaroc.R:2006,2056`), and the master always rewrites the manifest there (`code/0. master.R:319,380`). Any alternative run would overwrite the production outputs.
   - The scenario parameters are hard-assigned inside the runner (`…noaroc.R:1898-1918`), which CLAUDE.md says may not be edited without the author's approval.
2. **Table S8 mixes engines and windows.**
   - The base rows are current but summed over 2025–2050 (`yr_s8_start <- 2025L`, artifact Rmd line 62). For example, BAU is 598.4 M instead of 581.5 M, and the "All" row shows 14.3% instead of 14.7%.
   - The legacy rows are divided by 24.
3. **No replication code exists for the Kontis-methods column.** Thirteen of its 15 country values in Table S3 equal the legacy "This study" values, which suggests placeholders.
4. **Several Methods and supplement statements describe an older or different implementation** (§2, group G).
5. **Several Results labels misstate the estimand.** Values computed over all ages are described as "premature".

### Size of the legacy shift

- The legacy base case was **118.1 M**: legacy calibration, independent Lee–Carter (LC) trends, pre-fix runner.
- The current base case is **85.8 M** (−27%).
- `output/benchmark/pre_change_legacy_trends_summary.csv` gives **94.9 M** with the current calibration, current inputs and current runner but the old independent-LC trends.
- So roughly 23 M of the shift comes from the calibration, inputs and runner changes, and about 9 M from the switch to coherent trends.

Every legacy number in the text (116, 117, 102, 16.5, 41, 32, 4, 10) belongs to the 118 M world, not the 86 M world.

---

## 2. Prioritized findings

Severity:

- **Critical:** a reported study result is wrong or not from the current model, and readers would take it as current.
- **High:** a material result, label or method is inconsistent.
- **Medium:** a secondary inconsistency or missing provenance.
- **Low:** wording, captions or documentation.

The CSV adds the producing script or input, the downstream items, the rerun group and the evidence strength for every row.

| ID | Sev. | Manuscript location | Artifact / scalar | Current value or claim | Class | Evidence | Required action | Verification |
|---|---|---|---|---|---|---|---|---|
| F01 | Critical | Table S8: LC, no-trend and Foresight rows (15 rows) | `TS8_Sensitivity`, `ts8_leg` | LC 117.7 M; no trend 115.9 M; Foresight 102.3 M; BAU 695.4 / 683.4 / 564.6 M | C3 | artifact Rmd 1474-1481 (literal table "from legacy workbook TS8_Sensitivity!A3:G23"); no outputs in repo | Run S1–S3 (§4) with the current calibration, runner and inputs; compute every row from scenario outputs; delete `ts8_leg` | Every S8 cell has `status = reproduced` and a scenario run id; no literal numbers in chunk `tableS8` |
| F02 | Critical | Results "Sensitivity analysis"; Methods "Sensitivity analyses" | `sens_no_trend_dd_M`, `sens_lc_dd_M`, `sens_foresight_dd_M`, `sens_pct_range` | 116, 117, 102 M; "17%–18%" | C3 | artifact Rmd 266-269 (`preserved_pending`, "TS8 legacy"); manuscript Rmd 234, 279 | Replace with lookups computed from S1–S3; rewrite both paragraphs | Scalars `reproduced`, with values equal to the S8 "All" rows |
| F03 | Critical | All legacy model results (S8 alternatives, Kontis-methods column, 16.5, 4, 41, 32, 4.5, 10) | all `preserved_pending` scalars and cells | — | C3 | runner diff: HEAD has `rris[, RRi_HSTROKE := RRi_ISTROKE]`, the current file uses own RRs (`…noaroc.R:387,398`); `tfa_policy_scenarios.rds` modified; calibration and trends replaced | Disclose all four engine changes, or remove the values until rerun; never combine them with the refreshed base case | Manuscript text either cites a current run id or contains no legacy model number |
| F04 | High | Table S8 base rows; Table S8 notes | `TS8_Sensitivity` base rows; `yr_s8_start` | BAU 598.4 M; projected 543.1 / 576.8 / 594.5 / 589.5 / 512.6 M; % 9.2 / 3.6 / 0.6 / 1.5 / 14.3 (2025–2050) | C2 | artifact Rmd 62, 1487-1488; recomputed: BAU 2025–2050 = 598.38 M, 2026–2050 = 581.46 M, BAU in 2025 = 16.92 M, DD in 2025 = 0 | Set the S8 window to 2026–2050 (drop `yr_s8_start`); the base rows then equal Table 2 | S8 base rows equal Table 2 all-CVD rows to full precision |
| F05 | High | Table S8 "per year" column; notes | `ts8_leg$per_year` | Legacy rows = DD / 24 (74.3 → 3.1); base rows = DD / 25 | C3 / C4 | artifact Rmd 1480, 1488; manuscript Rmd 678 | Divide every row by 25 (2026–2050) once all rows are regenerated | `per_year == dd / 25` for every row |
| F06 | High | Results sensitivity paragraph | `sens_lc_dd_M` | Text "117" vs table 117.7 (rounds to 118) | C3 / C4 | `scalars.rds` value 117 vs `ts8_leg` dd 117.7 | Derive from the table value | Text equals table rounding |
| F07 | High | Methods "Sensitivity analyses"; S8 row labels | — | "no background and CVD secular trends; independently forecast Lee–Carter trends; CVD trends from GBD 2019 Foresight reference scenario" | C4 / C6 | stage 6 `code/6. build_baseline.R:324-499`: the Foresight option replaces **only CF** with the Global both-sex age-standardized change, full (no 80%); background follows the chosen method; legacy LC trends BG.mx, BG.mx.all and CF independently | Define each scenario exactly (which of IR, CF, DIS.mx, BG.mx, BG.mx.all change, the CF share, the background pairing); author decisions in §5 | Methods text matches `model_run_manifest.rds$baseline` of each scenario run |
| F08 | High | S8 "IHME Foresight trends"; Figure S4; Validation paragraph | input files `data-raw/GBD/gbd2023_foresight_*` | Labelled GBD 2019 Foresight | C5 (label OK), C4 (file names) | the footer of every file cites "GBD Foresight… GBD Study 2019… 2020 (Accessed 8/24/2025)"; `code/2. get_tps_bgmx_100_gbd23.R:570-574` | Keep "GBD 2019 Foresight" in the text; rename the files or document them; decide whether to move to GBD 2021 Foresight (Vollset 2024, already cited) | File names or README state the release; S8 label matches |
| F09 | High | Stage 8/9 machinery (enables S8) | — | Scripts missing; outputs always overwrite production | C6 | `code/0. master.R:392-401`; `…noaroc.R:2006-2058`; `code/0. master.R:319,380` | Implement a scenario driver with isolated output folders and per-scenario manifests (§4, R0) | Production manifest md5s unchanged after a sensitivity run |
| F10 | Medium | S8 "independent LC" row | — | The current `mortality_trend_method = "legacy"` differs from the legacy run | C4 | stage-2 comment: the old merge made "every projected BG.mx change NA and stage 6 never applied it" (`code/2. get_tps_bgmx_100_gbd23.R:426-428`); LC fit on 2000–2015 only (lines 489-516); the accounting stop runs only for the coherent method (`code/6. build_baseline.R:524-526`) | Decide between "as was" (BG.mx inactive) and "as fixed"; document the accounting break | Scenario manifest records the choice and the accounting counts |
| F11 | Medium | (not in manuscript) | `output/benchmark/pre_change_legacy_trends_summary.csv` | Independent LC with the current calibration and runner: 94.9 M; BAU 659.7 M (2026–2050) | C6 | the CSV label: BG.mx trend inactive, CF 80%, calibration `20261123-120744-3fcb9cbd` | Do not paste into S8 (summary only; no per-country outputs or manifest kept); use as a cross-check for S2 | Rerun S2 "as was" reproduces 94.9 M within rounding |
| F12 | High | Tables S2 and S3, "This study – Kontis methods" column; S2/S3 notes ("red column") | `TS2_CompareIntervention`, `TS3_CompareCountry` | S2: 40.9 / 44 / 4.2 / 11 / 95.3; S3: 30.6, 13.6, … | C3 / C6 | artifact Rmd 1333, 1363; 13 of 15 S3 values equal legacy "This study" (`leg_ts3_this`, line 2405); S2 statins = 11 although Kontis modelled no statins | Implement and run a Kontis-methods replication (K1), or remove the column and its text; remove the "red column" wording | Column computed from replication outputs, or absent |
| F13 | High | Comparison: hypertension ("41 million"); sodium ("32 million") | `kontis_methods_htn_M_r0`, `kontis_methods_china_text_M` | 41 M (S2 shows 40.9); 32 M (S3 shows 30.6) | C3 | artifact Rmd 298, 301 | From K1 or remove | Text values equal the table values |
| F14 | High | Comparison: sodium, "our impact estimates are modestly lower than … our replication of the Kontis methods" | — | Current sodium 21.6 M vs replication 44 M (about half) | C4 | `TS2_CompareIntervention.csv` | Rewrite from K1 or drop | Qualitative claim checked in the artifact report |
| F15 | High | Comparison: TFA ("just over 4.5 million over 24 years", "about 10 million", "India … about 4 million") | `kontis_methods_tfa_text`, `tfa_bans_since_2017_M`, `tfa_india_ban_M` | Legacy; current TFA DD is 3.9 M over 25 years | C3 / C4 | artifact Rmd 303-305 | K1 and P2; fix "24 years" | Values from runs; horizon 2026–2050 |
| F16 | High | Discussion: "scaling up hypertension control by 2040 instead of by 2050 represents a gain of 16.5 million"; "Scenarios … reach targets by 2040–2050 consistently yield greater mortality reductions than more delayed trajectories" | `htn_2040_vs_2050_gain_M` | 16.5 M (legacy); no delayed-start runs exist | C3 / C6 | artifact Rmd 270; runner hard-codes `control_target_year <- 2040` (`…noaroc.R:1900`) | Run P1; drop or support the "delayed trajectories" claim with P3 | Scalar `reproduced` from P1 minus base |
| F17 | High | Discussion: India's TFA limit "reduced the estimated global deaths delayed … by roughly four million" | `tfa_india_ban_word` | "four" (legacy); current India TFA DD = 0 | C3 | artifact Rmd 271; `code/4. prepare_interventions.R:317-321` (bans passed ≤ 2023 → TFA = 0 from 2024); runner reads a fixed input path (`…noaroc.R:839`) | Run P2 (India counterfactual input) | Scalar `reproduced` from P2 minus base |
| F18 | High | Table 1: hypertension baseline "37 % of hypertensives treated to SBP < 140 mmHg" | `T1_Scenarios` | 37% | C6 / C4 | artifact Rmd 849; model input `hbp_control_data.rds` `baseline_ctrl` (2025, population-weighted) = 19.1% control; NCD-RisC 2019 treated = 37.6% (artifact Rmd 831-835; values from the 2026-11-03 knit, inputs unchanged since) | Author decision on the estimand; compute it in the artifact report; "treated to SBP < 140" conflates treatment and control | Table 1 baseline equals the model input that drives the HTN scenario |
| F19 | High | Results p2 ("reductions in deaths before age 70 years were similar by sex … 15% … 42.8 million"); HTN, sodium and TFA paragraphs ("premature"); Abstract conclusion ("one in seven premature CVD death events") | `pct_all_female_r0`, `dd_all_female_M`, `pct_htn`, `pct_sodium`, `pct_tfa`, `one_in_n_all` | All-age values labelled premature or <70 | C4 / C2 | inventory notes (artifact Rmd 218, 231, 241, 249); recomputed <70: women 16.2% (8.7 M), men 15.7% (14.1 M) | Either relabel as all ages or add <70 scalars | Each sentence's estimand matches the key (`u70` keys for "premature") |
| F20 | High | Abstract ("immediate elimination of artificial trans fatty acids"); Methods ("linear scale-up … 2026 to 2050"; "two years to fully implement the sodium reduction"; TFA "fall to 0% … by 2028"); Table 1 "Linear" for TFA; math ("instantaneous", default 2027) | `scenario_targets` | Implementation: HTN linear 2026→2040; sodium linear 2026→2030 (5 steps); TFA step from 2028; statins 2026→2050 | C4 | `…noaroc.R:142-149, 732-737, 1898-1918`; `parameter_check` rows 32-35 = NO | Rewrite the timing text and Table 1 from the run parameters | `parameter_check` has no "NO" rows; timing text generated from `mp` |
| F21 | High | Math supplement: HTN `T_start`/`T_end` defaults 2025/2050; salt start 2025; TFA start 2027; α_IR = α_CF = 1; w_DM = 0.1; HTN scale-up (t − T_start)/(T_end − T_start); time 2019–2050 and initial conditions in 2019; Table S9 "(2019–2050)" | `Math_*`, `TS9_Assumptions` | Run values: 2026/2040; 2026; 2028; 0.575/0.664; country diabetes prevalence; (t − T_start + 1)/(T_end − T_start + 1); cohort seeded in 2017 | C4 | `provenance.rds$parameter_check` (8 NO / n.a. rows); `…noaroc.R:142-149, 1236`; `code/0. master.R:112-115` | Update the equations and defaults to the run values; make the parameter check stop on mismatch | Parameter check all "yes" |
| F22 | Medium | Table 1 statin RR "IR: 0.78"; Methods "22% (RR 0.78) … CVD mortality RR 0.80" | `T1_Scenarios` | Model: IR 0.74 IHD and 0.80 ischemic stroke; CF 0.80 IHD and 0.96 ischemic stroke | C4 | `parameter_check` row 26 NO; artifact Rmd 847 | Align the table and text with the model RRs and cite their source | Parameter check "yes" |
| F23 | Medium | Table 1 statins: baseline "7 % coverage … as primary prevention" vs risk population "Adults 40+ with prior IHD or stroke (secondary)" and target "60%"; Comparison "we only consider primary prevention statins among persons with diabetes" | `T1_Scenarios` | The model uses one coverage for both IR (primary, AF-scaled) and CF (secondary) | C4 / C6 | manuscript Rmd 216-228, 574; math 1146-1242 | Author decision on the coverage estimand; fix the comparison sentence | Consistent definition across Table 1, Methods, Comparison |
| F24 | Medium | Table 1 TFA baseline "0.4% of energy intake (2025)"; note "population-weighted using 2019 population" | `T1_Scenarios` | GBD 2024 intake at ages 50–54, before the ban logic; model scenario baseline (TFAS 2025) is lower | C4 | artifact Rmd 812-814, 829 | Report the model's 2025 scenario baseline, or relabel the estimand | Label and estimand agree |
| F25 | Medium | Results TFA: "older adults (0.3–0.5%)", "South Asia (1%) … reflecting its high baseline TFA consumption" | `pct_tfa_o70_range`, `pct_tfa_reg_sa` | Current: 70–79 0.69%, 80–89 0.50%, 90+ 0.26%, 70+ pooled 0.52%; South Asia 0.25%; Southeast Asia/East Asia/Oceania 0.98% (largest) | C4 / C2 | recomputed from current outputs (read-only) | Choose the estimand; fix the region (South Asia is now the second-lowest) | Scalars `reproduced`; ranking check added |
| F26 | Medium | Discussion: TFA "1% reduction in IHD mortality in high-consumption regions" next to the global average (0.7%, all-CVD) | `tfa_ihd_high_regions_pct`, `pct_tfa` | IHD reduction from TFA: 1.5% global; 0.6–2.5% by region | C6 / C4 | recomputed; artifact Rmd 276 | Define the region set; compare like with like (IHD vs all-CVD) | Scalar `reproduced` |
| F27 | Medium | Discussion: Pickersgill hypertension "76 million" vs Table S2 Pickersgill HTN 67.4 M | `pick_htn_text_M`, `TS2` | Two different external values | C5 / C6 | artifact Rmd 275, 1335 | Check Pickersgill 2022 (scenario, period); use one value or explain both | Same value in text and table, or both explained |
| F28 | Medium | Comparison text: "Table S3 presents … the 15 countries with the largest cumulative impact"; S3 notes "approximately 70% of deaths delayed" | `TS3_CompareCountry` | The list is Kontis's top 15; current top 15 replaces United States and Mexico with Viet Nam and Iran; Kontis-15 share = 73.5% | C4 / C2 | recomputed; artifact Rmd 1360-1373, 2639 | Choose the list and state the rule; compute the share | Caption rule matches the selection; share scalar `reproduced` |
| F29 | Medium | Methods secular trends: "we did a post hoc adjustment of our projections based on observed excess mortality"; "it did not account for the impact of COVID-19" | — | COVID excess mortality enters stage 6 as `covid.mx` (2020–2021), inside the projection | C4 | `code/6. build_baseline.R:279-285, 534-589` | Rewrite to match | — |
| F30 | Medium | Figure 1 notes | `fig1a/b` | Stack of four separate effects = 89.6 M ≠ combined 85.8 M | C4 | artifact Rmd 1001-1002; recomputed | State in the notes that the stack is the sum of separate effects, not the combined package | Notes mention it |
| F31 | Medium | Introduction/Methods citations | `references.bib` | Fulcher 2015 (CTT LDL meta-analysis) cited for the TFA "2% → 21% IHD" claim; Schumacher 2024 (GBD 2021 demographics) cited as the "GBD 2023 release"; Gaziano 2010 and Stringhini 2016 cited as NCD-RisC sources | C4 | manuscript Rmd 143, 155, 208; bib titles | Replace with the correct sources | Citation key titles match the claims |
| F32 | Medium | Data and code availability | — | URL `…/UW-RTSL-100MLives` | C4 | `git remote`: `Disease-Control-Priorities/uw-rtsl-100mlives2` | Fix the URL or archive a release | Link resolves to the repository used |
| F33 | Medium | Provenance of the current run | `model_run_manifest.rds` | Results depend on uncommitted code (stages 0, 2, 6, 7; untracked stage 4); manifest `master_md5` 3a64… ≠ current 6d44… (master edited 20:00, between the main run and the Norway rerun) | C6 | git status; manifest | Commit the code state used; record the git commit in the manifest; regenerate after the commit | Manifest carries a commit hash equal to HEAD |
| F34 | Medium | Math "Model outputs … Life-years gained" | — | Outputs contain well, sick, newcases, dead, pop, all.mx; no life-years | C4 | artifact Rmd 552-553; runner (no life-year code found) | Remove or implement | — |
| F35 | Medium | Methods TFA: "implemented only in countries that had not yet enacted a comprehensive ban as of 2025"; "achieve the target intake level two years after the policy went into effect" | — | Code: bans **passed** ≤ 2023 → 0 from 2024; all others receive the common 2028 policy | C4 | `code/4. prepare_interventions.R:317-343` | Align text with code (or code with text, by author decision) | — |
| F36 | Medium | Stale cached report | `reports/manuscript-100mlives2-artifacts.html` | Knitted 2026-11-03 (pre-current run); its diagnostic tables are obsolete | C4 | file mtime | Do not cite it; re-knit to a tempdir and inspect, or delete | — |
| F37 | Medium | Table 1 RR column (sodium "IR per 1 g/day: IR 0.83 IHD …") | `T1_Scenarios` | Ettehad per-10 mmHg totals shown as per-gram sodium RRs | C4 | artifact Rmd 844-846 | Express sodium as Filippini mmHg/g mapped through Ettehad | — |
| F38 | Low | Table S5 and S6 captions "2025–2050" | `TS5`, `TS6` | Data are 2026–2050 | C4 | manuscript Rmd 626, 638; inventory W | Fix captions | — |
| F39 | Low | Comparison point 3 "We look at the period 2025-2050" | — | 2026–2050 | C4 | manuscript Rmd 531 | Fix | — |
| F40 | Low | Discussion: "e.g., 30% blood pressure control, 45% statin uptake, full implementation … by 2030 … tied to measurable mortality gains" | — | Not modelled | C6 | — | Mark as illustrative or model it | — |
| F41 | Low | CLAUDE.md "Known mismatch" for stage 4 | — | Resolved: the file is `4. prepare_interventions.R` and is sourced correctly (`code/0. master.R:289`) | C4 (docs) | git status | Update CLAUDE.md | — |
| F42 | Low | CF reduction factors 0.24 / 0.36 / 0.76 / 0.20 (math table) | `Math_CF_ReductionFactors` | No citation in the text | C5 / C6 | `…noaroc.R:568` | Cite the source | — |
| F43 | Low | Results qualitative claims not guarded by checks: HTN "relative reductions are similar across age groups … and the two sexes"; sodium "similar by age group and sex"; Abstract "hemorrhagic stroke showing the largest relative reduction" | — | Hold now: HTN <70 10.9% vs 70+ 9.1%, women 9.9% vs men 9.2%; sodium 3.1% vs 3.9%, 3.8% vs 3.6%; ICH 19.5% vs ≤ 15.0% | C1 (unguarded) | recomputed | Add checks so a rerun cannot silently contradict them | Checks in `results-numbers` |
| F44 | Low | Front matter: word count 7,932; date "October 31, 2026" | — | Static | C6 | manuscript Rmd 18, 119 | Update at submission | — |
| F45 | Low | Methods "≈ 99% of the world's population in 2019" | `pop_coverage_pct` | Computed on ages 20+ | C4 | artifact Rmd 802-805 | Say "adult population" | — |

---

## 3. Table S8 and the sensitivity analysis

### 3.1 Row-level status

Window: the title says 2026–2050. The current generator sums all rows over 2025–2050. The values in the table below are the displayed values, in millions.

| Block (rows) | Projected | Baseline | DD | DD/yr | % | Status | Source |
|---|---|---|---|---|---|---|---|
| **Base: coherent trends, CF 80%** (HTN, Sodium, TFA, Statins, All) | 543.1 / 576.8 / 594.5 / 589.5 / 512.6 | 598.4 | 55.3 / 21.6 / 3.9 / 8.9 / 85.8 | 2.2 / 0.9 / 0.2 / 0.4 / 3.4 (÷25) | 9.2 / 3.6 / 0.6 / 1.5 / 14.3 | DD and DD/yr **current (C1)**; projected, baseline and % **current run, wrong window (C2)** | model run `20261123-191232-7e0f6eae` |
| **Background and CVD trend LC (legacy run)** | 621.1 / 659.3 / 690.9 / 684.4 / 577.7 | 695.4 | 74.3 / 36.1 / 4.5 / 10.9 / 117.7 | ÷24 | 10.7 / 5.2 / 0.6 / 1.6 / 16.9 | **Legacy (C3)**; run definition unverifiable (C6) | `ts8_leg`, artifact Rmd 1474-1481 |
| **No background and no CVD trend (legacy run)** | 610.7 / 647.4 / 679.0 / 672.7 / 567.5 | 683.4 | 72.8 / 36.0 / 4.4 / 10.7 / 115.9 | ÷24 | 10.6 / 5.3 / 0.6 / 1.6 / 17.0 | **Legacy (C3)** | same |
| **IHME Foresight trends (legacy run)** | 498.6 / 532.3 / 561.1 / 556.2 / 462.3 | 564.6 | 66.0 / 32.3 / 3.6 / 8.4 / 102.3 | ÷24 | 11.7 / 5.7 / 0.6 / 1.5 / 18.1 | **Legacy (C3)**; release GBD 2019 Foresight (file footer) | same |

On 2026–2050 the base rows are exactly Table 2 (recomputed and confirmed):

| Intervention | Projected (M) | BAU (M) | DD (M) | DD per year (M) | % |
|---|---|---|---|---|---|
| HTN | 526.2 | 581.5 | 55.3 | 2.21 | 9.5 |
| Sodium | 559.9 | 581.5 | 21.6 | 0.86 | 3.7 |
| TFA | 577.6 | 581.5 | 3.9 | 0.15 | 0.66 |
| Statins | 572.6 | 581.5 | 8.9 | 0.36 | 1.5 |
| All | 495.7 | 581.5 | 85.8 | 3.43 | 14.7 |

### 3.2 Provenance of the sensitivity scalars

| Scalar | Text | Table | Status |
|---|---|---|---|
| `sens_no_trend_dd_M` | 116 | 115.9 | preserved; legacy |
| `sens_lc_dd_M` | **117** | **117.7** | preserved; legacy; **rounding is inconsistent** (F06) |
| `sens_foresight_dd_M` | 102 | 102.3 | preserved; legacy |
| `sens_pct_range` | "17%–18%" | 16.9 / 17.0 / 18.1 on legacy BAUs, window 2025–2050 | preserved; legacy |

All four are set as `preserved_pending` constants. They have no generating expression and the inventory notes "none in report" (artifact Rmd 266-269).

The paragraph then sets these legacy values beside a base case (85.8 M, 14.7%) that is **27% lower**. That makes the "17%–18%" range look like a sensitivity of the current estimate, which it is not.

### 3.3 What each scenario changes in the current code, and what it means for mortality accounting

The following hold in **every** scenario:

- calibration run `20261123-120744-3fcb9cbd`;
- stage-4 inputs as of 2026-11-23;
- runner md5 `f4776e8b…`;
- intervention parameters (`…noaroc.R:1898-1918`);
- 190 countries; `stage7_first_year = 2017`;
- COVID `covid.mx` for 2020–2021;
- the final probability guard;
- **IR held at 2019** (it is never trended);
- the UN-WPP 2024 age-20 entrants.

| Scenario | Master switches (current interface, `code/0. master.R:93-110`) | DIS.mx (age-20 seeding) | BG.mx.all (shared) | BG.mx (sick state) | CF | Accounting |
|---|---|---|---|---|---|---|
| **S0 Base** (exists) | `mortality_trend_method="coherent"`, `run_bgmx_trend=TRUE`, `run_CF_trend=TRUE`, `run_CF_trend_80=TRUE`, `run_CF_trend_ihme=FALSE` | × R_c(t) | (ALL₂₀₁₉ − ΣDIS₂₀₁₉) × R_o(t) | ALL − DIS | × (1 + 0.8 (R_c − 1)) | ALL = other + ΣCVD holds exactly before the guard; the guard breaks BG = ALL − DIS in 4,255 of 961,248 cells (manifest) |
| **S1 No background and no CVD trend** | coherent; `run_bgmx_trend=FALSE`; `run_CF_trend=FALSE` | 2019 | 2019 residual (now includes dementia; step at 2020 as in S0) | ALL − DIS | 2019 calibrated | Holds. Population inflow (UN-WPP entrants) still embeds UN mortality assumptions |
| **S2 Independent LC** | `mortality_trend_method="legacy"`; `run_bgmx_trend=TRUE`; `run_CF_trend=TRUE`; `run_CF_trend_80=TRUE` (decision) | **not trended** | × independent LC change (2000–2015 fit) | × independent LC change (**now active**; inactive in the legacy runs, F10) | × (1 + 0.8 × LC change in the cause rate) | **Breaks** ALL = other + ΣCVD and BG.mx = ALL − DIS (reported, not stopped: `code/6. build_baseline.R:521-526`). The historical BG.mx.all excludes dementia, and no rebuild happens |
| **S3 GBD Foresight CF** | `run_CF_trend_ihme=TRUE`, `run_CF_trend_80=FALSE` (required, `code/0. master.R:241-243`) **plus a background method (decision)** | per method | per method | per method | × (1 + Foresight ASMR change), Global, both sexes, **not age- or sex-specific**, full change | With coherent: DIS and BG follow the reconciled forecast while CF follows Foresight, so CF and population cause rates diverge. With legacy: the S2 break applies |

**BAU.** Every scenario must take its BAU from its own run. The stage-7 `scenarios` list already includes `baseline` (`…noaroc.R:1987-1996`), so a complete run of all eight scenarios under one stage-6 configuration provides the matched BAU automatically. Never subtract a scenario's intervention deaths from S0's BAU.

### 3.4 How to regenerate Table S8 consistently

1. **R0 (implementation, needs author approval):** build a scenario driver; details in §4.
2. **Run S1, S2 and S3:** all eight scenarios, 190 countries, current calibration and inputs.
3. **Change the artifact generator:**
   - read each scenario folder;
   - verify its manifest (calibration id, runner md5, input md5s, switches);
   - compute projected, BAU, DD, DD/25 and DD/BAU over **2026–2050** with the same `summ()` used for Table 2;
   - delete `ts8_leg` and `yr_s8_start`;
   - set the sensitivity scalars from the new rows (`sens_*`, plus a `sens_pct_range` derived from all four scenarios, base included).
4. **Rewrite the text:** the Methods and Results sensitivity paragraphs and the S8 notes. Remove "legacy run" and the ÷24 note, and define each scenario as in §3.3.

Knitting the generator again without steps 1–2 regenerates nothing.

---

## 4. Minimum rerun matrix

**Shared prerequisites (R0, implementation, not a run).** Do not edit `…noaroc.R` without the author's explicit approval (CLAUDE.md). R0 needs:

- **(a) Isolated output folders.** A driver (proposed name `code/8. run_sensitivity.R`, which the master already expects at `code/0. master.R:392-394`) that, per scenario:
  - sets the trend switches and `trend_config`;
  - sources stage 6;
  - sets `wd_outp` to a scenario folder before sourcing stage 7, so that `out_model/` and the logs land there. The runner builds its paths from `wd_outp` (`…noaroc.R:2006,2056`).
- **(b) A per-scenario manifest,** replicating the master's stage-7 block (`code/0. master.R:338-385`) with the scenario folder.
- **(c) Parameter overrides for the intervention-timing counterfactuals.** The runner assigns `control_target_year` and the other parameters unconditionally (`…noaroc.R:1898-1918`), so P1 needs either an approved runner change (for example `if (!exists(...))` guards) or an approved parameterized copy.
- **(d) An input override for P2.** The runner reads `TFAPolicy/tfa_policy_scenarios.rds` from `wd_data` (`…noaroc.R:839`). Either write the counterfactual file into a scenario data folder and point `wd_data` at it for that run (all other inputs must be copied or linked), or add an approved input-path override.

Settings for every run: 2–3 workers and `data.table::setDTthreads(1)` per worker (see the project memory on stage-7 stability). The production run took about 46 minutes with the current settings.

| Group | Run | Settings (vs S0) | BAU | Prerequisites | Output location (**proposed**, not existing) | Dependent artifacts | Order |
|---|---|---|---|---|---|---|---|
| — | **S0 base** | as in the manifest | own (`baseline`) | exists | `output/out_model/` (verified) | everything current | done |
| Sensitivity | **S1 no trends** | `run_bgmx_trend=FALSE`, `run_CF_trend=FALSE` | own | R0 a, b | `output/sensitivity/no_trend/out_model/` | S8 block 3; `sens_no_trend_dd_M`; `sens_pct_range`; Methods and Results text | 1 |
| Sensitivity | **S2 independent LC** | `mortality_trend_method="legacy"`; CF share 0.8 (decision); BG.mx trend active or inactive (decision) | own | R0 a, b; stage-2 legacy files exist (`tps_bgmx_*_forecasted.rds`, 2026-11-23 19:09) | `output/sensitivity/lc_independent/out_model/` | S8 block 2; `sens_lc_dd_M`; text | 2 |
| Sensitivity | **S3 Foresight CF** | `run_CF_trend_ihme=TRUE`, `run_CF_trend_80=FALSE`, background method (decision); release decision (GBD 2019 vs 2021 Foresight) | own | R0 a, b; `tps_bgmx_cvd_ihme.rds` (exists; GBD 2019 Foresight) | `output/sensitivity/foresight_cf/out_model/` | S8 block 4; `sens_foresight_dd_M`; text | 3 |
| Policy/timing | **P1 HTN target 2050** | `control_target_year=2050`; other parameters unchanged; all eight scenarios (or at least `baseline`, `bp_only`) | own (identical to S0 BAU if baseline id and runner match; recompute anyway) | R0 a, b, c | `output/counterfactual/htn_target_2050/out_model/` | `htn_2040_vs_2050_gain_M` = DD(bp_only, S0) − DD(bp_only, P1), 2026–2050; Discussion timing paragraph | 4 |
| Policy/timing | **P2 India TFA, no 2021 limit** | India's `tfa_current` carried at its pre-ban GBD level and policy dates cleared (as done for Indonesia, `code/4. prepare_interventions.R:292-300`); `tfa_only` (and `all_four` if the package effect is reported). **India only**: countries are simulated independently, so the global difference equals India's difference | own | R0 a, b, d; author definition of the pre-ban level | `output/counterfactual/india_tfa_noban/out_model/` | `tfa_india_ban_word`, `tfa_india_ban_M`; Discussion and Comparison TFA text | 5 |
| Policy/timing | **P3 delayed start** (optional) | for example start 2030 | own | R0 a–c | `output/counterfactual/delayed_start/…` | supports "more delayed trajectories" (F16) or the claim is dropped | 6 (optional) |
| Comparison | **K1 Kontis-methods replication** | no implementation exists: needs Kontis' mean-SBP-shift/PAF hypertension model, the instantaneous sodium mortality effect and the Kontis TFA target, run on current inputs over 2026–2050, with its own BAU | own | new code (cannot be configured from the current interfaces) | `output/comparison/kontis_methods/` | S2 and S3 column 3; `kontis_methods_*`; `tfa_bans_since_2017_M`; Comparison text | 7, or remove |
| Artifact-only | **A1** | no model run | — | none | `manuscript/artifacts`, `tables`, `figures` | F04 (S8 window, for the base rows), F19, F24–F26, F28, F30, F38, F39, F43, F45; T1 HTN baseline once its estimand is decided (F18) | after the runs it depends on; F19/F28/F30/F38/F39/F43/F45 can be done now |
| Text-only | **T1** | — | — | author decisions | manuscript Rmd | F07, F14, F20–F23, F29, F31, F32, F34, F35, F37, F40–F42, F44 | any time |

**Order of execution:**

R0 → S1, S2, S3 (independent; run sequentially for memory) → P1 → P2 → K1 (or drop) → A1 (artifact report; the render writes `manuscript/artifacts/*`, as intended) → knit the manuscript → §6 checklist.

The only existing interface command is the production base run, `Rscript "code/0. master.R" 6 7`. It overwrites `output/out_model/` and must not be used for S1–P3.

---

## 5. Legitimate fixed values, and questions for the author

### 5.1 Constants that may stay (C5), if cited

- **External study results:** Kontis 2019 (94.3 M overall; 39.4 / 40 / 14.8 M by intervention; country values; 3.7 M per year); Pickersgill 2022 (88.5 M overall; 67.4 / 24.1 M; country values; 2.7–3.9 M per year; 76 M, which conflicts with 67.4 — see Q6); Chong 2024 (35.6 M CVD deaths in 2050); the Introduction context figures (75% of deaths from NCDs, 17.9 M CVD deaths, 27–36 M by 2050, GIFNA 66 countries and 3.2 billion people, HEARTS 40 countries and 34 M patients).
- **Effect sizes:** Ettehad BP RRs; Filippini (2.8 / 1.0 mmHg per g); TFA RRs 1.21–1.07 (Wang 2016); statin RRs 0.74 / 0.80 / 0.80 / 0.96 (the source must be cited; the text cites RR 0.78); ψ_athero = 0.60; adherence 0.575 / 0.664 (Basios 2025); CF reduction factors 0.24 / 0.36 / 0.76 / 0.20 (source not cited).
- **Scenario assumptions:** 50% control by 2040; −30% sodium by 2030 with a 2 g/day floor; TFA 0%E from 2028; statins 60% by 2050, starting 2026.
- **Calibration and projection settings:** the CF share of 80% (Ford 2007; Critchley 2004); the WHO World Standard Population; the calibration grid and weights (from `cal_config`, already reproduced).

### 5.2 Questions that need an author decision

- **Q1. Table S8 scenario definitions.**
  - Should "independent LC" use CF 80% (as the legacy base did) or 100%?
  - Should it reproduce the old inactive BG.mx trend, or use the fixed one?
  - Which background trend should be paired with the Foresight CF?
  - Should the analysis keep GBD 2019 Foresight (pre-COVID) or switch to GBD 2021 Foresight (Vollset 2024)?
- **Q2. Kontis-methods column:** implement a replication (K1), or drop the column and its three text claims?
- **Q3. Table 1 hypertension baseline:** which estimand should it report? The model uses 19.1% control among all hypertensives in 2025; 37% is unsourced.
- **Q4. TFA estimands:** which older-age range, which region (South Asia is now 0.25%), and which "high-consumption regions"?
- **Q5. Statin coverage:** primary-prevention uptake or secondary-prevention coverage? What population does the 60% target cover?
- **Q6. Pickersgill hypertension figure:** 76 M (text) or 67.4 M (table)?
- **Q7. Table S3 country set:** Kontis's top 15 or this study's top 15? The current top 15 includes Viet Nam and Iran instead of the United States and Mexico.
- **Q8. Timing claims:** keep "delayed trajectories" (needs P3) and the 2030 targets sentence, or remove them?
- **Q9. India counterfactual:** what pre-ban TFA level should be assumed (GBD 2020 intake, or the 2024 value without the ban)?
- **Q10. Runner changes:** approve them for R0 c/d, or use parameterized copies?

---

## 6. Checklist after implementation

- [ ] Every row of `provenance.rds$inventory` is `reproduced`, `fixed_external` or `static_content`. No `preserved_pending` or `mixed` rows remain, and `grep REPRO_PENDING` finds nothing in either Rmd.
- [ ] Each sensitivity and counterfactual folder has a manifest whose `calibration_run_id`, `runner_md5`, stage-4 input md5s and trend files equal the base run's, except for the documented switch.
- [ ] The production `output/out_model/model_run_manifest.rds` md5s are unchanged after the sensitivity runs.
- [ ] Table S8: every cell is computed; the window is 2026–2050; DD/yr = DD/25; the base rows equal Table 2; each block's BAU comes from its own run; there are no literal numbers in chunk `tableS8`.
- [ ] `sens_*` scalars equal the S8 "All" rows at the displayed precision; `sens_pct_range` covers the scenarios it names.
- [ ] Tables S2 and S3 column 3 come from K1 outputs, or the column and the Comparison claims (41, 32, 4.5, 10, 4, "modestly lower") are gone.
- [ ] `htn_2040_vs_2050_gain_M` and `tfa_india_ban_*` are computed from P1 and P2 minus the base, over 2026–2050.
- [ ] `parameter_check` has no "NO" rows, and the math supplement and Table S9 state the run's years (2026/2040, 2026–2030, 2028, 2017 seeding), the adherence values and the scale-up formula.
- [ ] Every "premature" or "<70" sentence uses a `u70` scalar; the TS5 and TS6 captions read 2026–2050.
- [ ] Table 1: the HTN baseline is computed from a stated input; the TFA baseline label matches its estimand; the statin RRs match the model.
- [ ] Rank and direction checks cover every qualitative claim in Results, Discussion and Comparison (age/sex similarity, region order, "largest" statements, the Kontis/Pickersgill direction).
- [ ] Citations are fixed (TFA claim, GBD 2023 source, NCD-RisC); the repository URL is correct; the Foresight release is named consistently in the files, Methods, S8 and Figure S4.
- [ ] Code is committed, and the manifest and provenance record the commit hash.
- [ ] Re-knit both Rmds in fresh R sessions. The integrity checks pass, and the Word document, CSVs, figures and xlsx share the same timestamp and run ids.

---

## 7. Summary

**Highest-priority findings**

1. **Table S8 (F01–F07).**
   - 15 of its 20 rows and all four sensitivity scalars (116 / 117 / 102 M; 17–18%) are literal legacy values from runs with the old calibration, independent-LC base trends, the pre-fix hemorrhagic-stroke RRs and older inputs. They sit beside a current base case that is 27% lower.
   - The base rows are current but summed over 2025–2050, so BAU is 598.4 M instead of 581.5 M and "All" is 14.3% instead of 14.7%.
   - Legacy rows are divided by 24, and "117" contradicts the 117.7 in the table.
2. **No sensitivity or counterfactual runner exists (F09).** Any alternative run would overwrite `output/out_model/`, and timing parameters are hard-coded in the runner.
3. **Other legacy model numbers in the text (F03, F12–F17):** the Kontis-methods column (it looks like placeholders), 41 M, 32 M, 16.5 M, India's "four million", and the "4.5 / 10 / 4 million" TFA statements.
4. **Labels and methods that do not match the implementation (F18–F23):**
   - the "premature" labels on all-age results;
   - the Table 1 hypertension baseline (37% vs the 19% model input);
   - the intervention timing and math defaults;
   - the statin RRs and coverage definition.

**Minimum work to make the manuscript current**

1. Build R0, the isolated scenario driver.
2. Run S1–S3 (about 46 minutes each), P1, and P2 for India only.
3. Decide K1 (implement or drop).
4. Make the artifact-only fixes (the S8 window and divisor, labels, captions, Table S3 rule, checks).
5. Make the text-only fixes to Methods, the math supplement and citations.
6. Rebuild the artifacts and knit the manuscript.

The artifact-only and text-only items can start now. The S8 base-row window fix should wait until the alternative rows exist, so that the table never mixes windows.
