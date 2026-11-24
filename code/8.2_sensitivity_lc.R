#===============================================================================
# code/8.2_sensitivity_lc.R  --  Stage 8, analysis "lc"
#-------------------------------------------------------------------------------
# Table S8 block "Background and CVD trend LC": the existing independent Lee-Carter pathway of
# stage 6 (mortality_trend_method = "legacy"). "legacy" names that forecast pathway only; the
# run uses the current calibration, baseline code, inputs and runner.
#   - Stage 2 forecasts three Global series separately (Lee-Carter fitted on 2000-2015, period
#     index by damped-trend ETS; no reconciliation): BG.mx of each cause row, BG.mx.all and the
#     cause-specific death rate (data/processed/tps_bgmx_forecasted.rds,
#     tps_bgmx_all_forecasted.rds, tps_bgmx_cvd_forecasted.rds).
#   - Background mortality (run_bgmx_trend = TRUE): each country's 2019 BG.mx and BG.mx.all times
#     the 2019-relative change of the matching series, by sex, age, cause and year.
#   - Case fatality (run_CF_trend = TRUE, run_CF_trend_80 = FALSE, cf_share = 1): the FULL
#     cumulative change in the cause's LC death rate, CF[t] = CF[2019] * (1 + d_c[t]).
#   - DIS.mx.t0 and ALL.mx are not trended, so the country accounting ALL = other + sum(CVD)
#     does not hold in the projection (stage 6 reports the breaks; it stops only for "coherent").
#   - Everything else (calibration, IR held at 2019, COVID-19 excess mortality, populations,
#     interventions, probability guards) is the base case's.
# Output: output/uncertainty/dsa/out_model_lc/
#   out_model/model_output_part_<Country>.rds and log_<Country>.txt (stage-7 schema),
#   dsa_manifest.rds, dsa_spec.rds, dsa_run.log, dsa_workers.log.
# Run (needs the setup of code/0. master.R):
#   Rscript "code/0. master.R" 8 "--dsa=lc"
#   or, in an R session where the master's setup section (everything before "# 1. Base rates")
#   has run: source(paste0(wd_code, "8.2_sensitivity_lc.R")); run_dsa_lc()
#   Pilot: run_dsa_lc(countries = c("Norway")) writes under output/uncertainty/dsa/pilot/.
#===============================================================================

if (!exists("dsa_spec", mode = "function")) source(paste0(wd_code, "8.0_sensitivity_helpers.R"))

dsa_spec_lc <- dsa_spec(
  name        = "lc",
  file        = "8.2_sensitivity_lc.R",
  table_label = "Background and CVD trend LC",
  description = paste("Independent (unreconciled) Global Lee-Carter forecasts: background mortality (BG.mx, BG.mx.all)",
                      "scaled by their own forecast changes and case fatality by the full forecast change in each",
                      "cause's death rate since 2019."),
  mortality_trend_method = "legacy",
  run_bgmx_trend         = TRUE,
  run_CF_trend           = TRUE,
  run_CF_trend_80        = FALSE,
  run_CF_trend_ihme      = FALSE)

run_dsa_lc <- function(countries = NULL, workers = dsa_default_workers)
  dsa_run(dsa_spec_lc, countries = countries, workers = workers)
