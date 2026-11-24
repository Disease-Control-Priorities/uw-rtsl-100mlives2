#===============================================================================
# code/8.1_sensitivity_ihme_foresight.R  --  Stage 8, analysis "ihme_foresight"
#-------------------------------------------------------------------------------
# Table S8 block "IHME Foresight trends": a GBD Foresight CF alternative with coherent
# background assumptions. It is not an IHME-based population or mortality model.
#   - Background and cause-specific population mortality: the coherent forecast, as in the
#     base case (mortality_trend_method = "coherent", run_bgmx_trend = TRUE): each country's
#     2019 DIS.mx.t0 and other-cause rates times the Global reconciled 2019-relative changes,
#     with ALL.mx and BG.mx rebuilt from them.
#   - Case fatality: replaced by the full cumulative change in the GBD Foresight age-standardized
#     death rate of each cause relative to 2019 (run_CF_trend_ihme = TRUE, so
#     run_CF_trend_80 = FALSE): CF[t] = CF[2019] * (1 + d_c[t]). One Global factor per cause
#     and year (both sexes, age-standardized), not age- or sex-specific (stage 2 builds it as
#     data/processed/tps_bgmx_cvd_ihme.rds).
#   - Release: data-raw/GBD/gbd2023_foresight_asr_<cause>20+.csv. Their citation footer names the
#     GBD Foresight visualisation of the GBD Study 2019 (accessed 2025-08-24), i.e. GBD 2019
#     Foresight, Reference scenario; "gbd2023" in the file names is the download batch. The run
#     records the footer and the md5 of these files in its manifest.
#   - Everything else (calibration, IR held at 2019, COVID-19 excess mortality, populations,
#     interventions, probability guards) is the base case's.
# Output: output/uncertainty/dsa/out_model_ihme_foresight/
#   out_model/model_output_part_<Country>.rds and log_<Country>.txt (stage-7 schema),
#   dsa_manifest.rds, dsa_spec.rds, dsa_run.log, dsa_workers.log.
# Run (needs the setup of code/0. master.R):
#   Rscript "code/0. master.R" 8 "--dsa=ihme_foresight"
#   or, in an R session where the master's setup section (everything before "# 1. Base rates")
#   has run: source(paste0(wd_code, "8.1_sensitivity_ihme_foresight.R")); run_dsa_ihme_foresight()
#   Pilot: run_dsa_ihme_foresight(countries = c("Norway")) writes under output/uncertainty/dsa/pilot/.
#===============================================================================

if (!exists("dsa_spec", mode = "function")) source(paste0(wd_code, "8.0_sensitivity_helpers.R"))

dsa_spec_ihme_foresight <- dsa_spec(
  name        = "ihme_foresight",
  file        = "8.1_sensitivity_ihme_foresight.R",
  table_label = "IHME Foresight trends",
  description = paste("Coherent background and cause-specific mortality trends as in the base case; case fatality",
                      "changed by the full cumulative change in the GBD 2019 Foresight (Reference) Global age-standardized",
                      "death rate of each cause since 2019 instead of 80% of the coherent cause trend."),
  mortality_trend_method = "coherent",
  run_bgmx_trend         = TRUE,
  run_CF_trend           = TRUE,
  run_CF_trend_80        = FALSE,
  run_CF_trend_ihme      = TRUE)

run_dsa_ihme_foresight <- function(countries = NULL, workers = dsa_default_workers)
  dsa_run(dsa_spec_ihme_foresight, countries = countries, workers = workers)
