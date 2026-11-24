#===============================================================================
# code/8.3_sensitivity_no_trends.R  --  Stage 8, analysis "no_trends"
#-------------------------------------------------------------------------------
# Table S8 block "No background and no CVD trend": no prospective secular trend in the
# mortality rates or case fatality.
#   - mortality_trend_method = "coherent" with run_bgmx_trend = FALSE: every projected year keeps
#     the country's 2019 cause-specific and other-cause death rates (stage 6 rebuilds ALL.mx and
#     BG.mx from them in the same way as the base case, with trend factors of one).
#   - run_CF_trend = FALSE (run_CF_trend_80 and run_CF_trend_ihme FALSE): CF stays at its
#     calibrated 2019 value. IR is held at 2019, as in every analysis.
#   - "No trends" refers to these secular rate assumptions only. Death counts still change over
#     time: the UN-WPP 2024 population grows and ages, COVID-19 excess mortality applies in
#     2020-2021, the cohorts evolve through the model, and the probability guards still apply.
#     Calibration, populations, interventions and all other inputs are the base case's.
# Output: output/uncertainty/dsa/out_model_no_trends/
#   out_model/model_output_part_<Country>.rds and log_<Country>.txt (stage-7 schema),
#   dsa_manifest.rds, dsa_spec.rds, dsa_run.log, dsa_workers.log.
# Run (needs the setup of code/0. master.R):
#   Rscript "code/0. master.R" 8 "--dsa=no_trends"
#   or, in an R session where the master's setup section (everything before "# 1. Base rates")
#   has run: source(paste0(wd_code, "8.3_sensitivity_no_trends.R")); run_dsa_no_trends()
#   Pilot: run_dsa_no_trends(countries = c("Norway")) writes under output/uncertainty/dsa/pilot/.
#===============================================================================

if (!exists("dsa_spec", mode = "function")) source(paste0(wd_code, "8.0_sensitivity_helpers.R"))

dsa_spec_no_trends <- dsa_spec(
  name        = "no_trends",
  file        = "8.3_sensitivity_no_trends.R",
  table_label = "No background and no CVD trend",
  description = paste("No prospective secular trend: the 2019 cause-specific and other-cause death rates and the",
                      "calibrated 2019 case fatality are held constant over 2020-2050 (population change, COVID-19 excess",
                      "mortality in 2020-2021 and the interventions still apply)."),
  mortality_trend_method = "coherent",
  run_bgmx_trend         = FALSE,
  run_CF_trend           = FALSE,
  run_CF_trend_80        = FALSE,
  run_CF_trend_ihme      = FALSE)

run_dsa_no_trends <- function(countries = NULL, workers = dsa_default_workers)
  dsa_run(dsa_spec_no_trends, countries = countries, workers = workers)
