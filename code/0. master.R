rm(list=ls())

# setwd(dirname(rstudioapi::getActiveDocumentContext()$path))
# setwd("C:/Users/wrgar/OneDrive - UW/02Work/ResolveToSaveLives/100mlives2/uw-rtsl-100mlives2/"))

#libraries
library(dplyr)
library(data.table)
library(tidyr)
library(ggplot2)
library(RColorBrewer)
library(readxl)
library(countrycode)
library(stringr)
library(parallel)
library(doParallel)
library(foreach)
library(gmodels)

# For forecasting mortality
library(forecast)

wd <- "C:/Users/wrgar/OneDrive - UW/02Work/ResolveToSaveLives/100mlives2/uw-rtsl-100mlives2/"

wd_code <- paste0(wd,"code/")

# Raw data not available on GitHub
wd_raw <- paste0(wd,"data-raw/")

# Processed data (from base rates and tps)
wd_data <- paste0(wd,"data/processed/")
wd_outp <- paste0(wd,"output/")

# Create a temporary directory for the processing data change to wd in final version
wd_temp <- paste0(wd,"temp/")
if (!dir.exists(wd_temp)) {
  dir.create(wd_temp, recursive = TRUE)
}

setwd(wd_code)

#...........................................................
# Stages to run ----
#...........................................................
# Default: every stage. From a terminal, pass stage numbers to run a subset, e.g.
#   Rscript "code/0. master.R" 5 6 7     (calibration, baseline, model)
# Stages 1-4 rebuild the processed inputs from data-raw/. Stage 8 runs the deterministic
# mortality-trend sensitivity analyses (code/8. run_sensitivity.R); each one rebuilds its own
# stage-6 baseline and runs stage 7 in a separate R process and writes only under
# output/uncertainty/dsa/. Stage 9 sources a script that is not in the repository yet.
# Option --stage2-trends-only: stage 2 runs only the mortality-trend script
# (2. get_tps_bgmx_100_gbd23.R) and leaves tps_inpt_part<N>.rds as they are, e.g.
#   Rscript "code/0. master.R" 2 6 7 --stage2-trends-only   (trends, baseline, model)

# Option --stage7-countries=<A>,<B>: rerun stage 7 for the named countries only, against a baseline
# identical to that of the run recorded in output/out_model/model_run_manifest.rds (for example when a
# country's output could not be saved), and record the rerun in that manifest, e.g.
#   Rscript "code/0. master.R" 6 7 "--stage7-countries=Norway"

# Stage 8 options (default: all three analyses, every modelled country):
#   --dsa=<a>,<b>            run only the named analyses: ihme_foresight, lc, no_trends
#   --dsa-pilot=<A>,<B>      execution check on the named countries only; written under
#                            output/uncertainty/dsa/pilot/ and never read as manuscript results
#   --dsa-workers=<n>        PSOCK workers per analysis (default 3; use 2 if workers die)
#   Rscript "code/0. master.R" 8                       (all three analyses)
#   Rscript "code/0. master.R" 8 "--dsa=lc"            (one analysis)
#   Rscript "code/0. master.R" 8 "--dsa-pilot=Norway"  (pilot of all three)

run_args  <- commandArgs(trailingOnly = TRUE)
run_flags <- run_args[startsWith(run_args, "--")]
bad_flags <- setdiff(sub("=.*$", "", run_flags), c("--stage2-trends-only", "--stage7-countries", "--dsa", "--dsa-pilot", "--dsa-workers"))
if (length(bad_flags)) stop("Unknown option(s): ", paste(bad_flags, collapse = ", "))
stage2_trends_only <- "--stage2-trends-only" %in% run_flags
flag_list <- function(name) {   # values of --<name>=a,b as a character vector, or NULL when absent
  f <- grep(paste0("^--", name, "="), run_flags, value = TRUE)
  if (!length(f)) NULL else trimws(unlist(strsplit(sub(paste0("^--", name, "="), "", f), ",")))
}
stage7_countries <- flag_list("stage7-countries")
dsa_analyses     <- flag_list("dsa")
dsa_pilot        <- flag_list("dsa-pilot")
dsa_workers      <- suppressWarnings(as.integer(flag_list("dsa-workers")))
run_stages <- local({
  a <- run_args[!startsWith(run_args, "--")]
  if (length(a)) as.integer(a) else 1:9
})
if (anyNA(run_stages) || !all(run_stages %in% 1:9)) stop("run_stages must be stage numbers 1-9.")
if (stage2_trends_only && !(2 %in% run_stages)) stop("--stage2-trends-only needs stage 2 in the run.")
if (!is.null(stage7_countries) && (!all(c(6, 7) %in% run_stages) || !length(stage7_countries) || any(!nzchar(stage7_countries))))
  stop("--stage7-countries needs stages 6 and 7 in the run and at least one country name.")
for (f in c("dsa", "dsa-pilot", "dsa-workers")) {
  v <- flag_list(f)
  if (!is.null(v) && (!(8 %in% run_stages) || !length(v) || any(!nzchar(v))))
    stop("--", f, " needs stage 8 in the run and at least one name.")
}
if (length(dsa_workers) && (length(dsa_workers) != 1L || is.na(dsa_workers) || dsa_workers < 1L))
  stop("--dsa-workers needs one positive integer.")
rm(f, v)

#...........................................................
# 0. Functions and parameters-----
#...........................................................

source(paste0(wd_code, "functions_review_6_100.R"))

run_aod_par <- FALSE # set to TRUE to run model with dementia

# Stage 6 projection assumptions (prospective only; never used by the calibration)

# Mortality trend method (stage 2 builds the forecasts, stage 6 applies them):
#   "coherent" (default): reconciled forecast of all-cause, the four CVD causes and other
#              causes (Li et al. 2019 forecast reconciliation; tps_mortality_coherent_forecasted.rds).
#              Each country's 2019 cause and other-cause rates are scaled by the Global
#              2019-relative changes, and ALL.mx and BG.mx are rebuilt from them.
#   "legacy":  the earlier independent Lee-Carter forecasts (tps_bgmx_*_forecasted.rds),
#              which scale BG.mx, BG.mx.all and CF separately.
mortality_trend_method <- "coherent"

# Trend the projected mortality inputs:
# coherent: DIS.mx.t0, BG.mx.all, ALL.mx, BG.mx;
# legacy: BG.mx and BG.mx.all.
run_bgmx_trend <- TRUE

# Trend case fatality with the projected change in the cause's population death rate.
run_CF_trend <- TRUE

# Modelling assumption: 20% of historical improvement was explained by HTN
# control improvements; apply 80% of the cumulative relative change to CF:
# CF[t] = CF[2019] * (1 + 0.8 * (R[t] - 1)).
run_CF_trend_80 <- TRUE

# Alternative CF trend: full GBD Foresight ASMR change (replaces the CF trend of either method).
# Mutually exclusive with run_CF_trend_80.
run_CF_trend_ihme <- FALSE

# These five switches define the main (production) run. Stage 8 never changes them: each
# sensitivity analysis declares its own five values in code/8.<n>_sensitivity_*.R and passes
# them, with a synchronised copy of trend_config, to a separate R process.

# First year stage 7 reads from b_rates: project.all() uses b_rates[location == Country & year>= 2017]
# and seeds its cohort there. Stage 6 checks this against the stage-7 code and passes only these years
# on, which keeps the eight parallel workers' copies of b_rates small.
stage7_first_year <- 2017L

# Remove unnecessary dx
# dx_include <- c("All causes","Ischemic heart disease",
#                 "Ischemic stroke","Intracerebral hemorrhage",
#                 "Alzheimer's disease and other dementias","Hypertensive heart disease")

dx_include <- c("All causes",
                "Ischemic heart disease",
                "Ischemic stroke",
                "Intracerebral hemorrhage",
                "Hypertensive heart disease")

cause_map <- c(
  ihd      = "Ischemic heart disease",
  istroke  = "Ischemic stroke",
  hstroke  = "Intracerebral hemorrhage",
  hhd      = "Hypertensive heart disease",
  all      = "All causes"
)

# AFTER  – define the vector once, reuse it
cause_cols <- names(cause_map)

#...........................................................
# Calibration settings (stage 5) ----
#...........................................................
# The single source of truth for code/5. calibration.R, which validates every
# entry and stops on a missing or invalid one. Stage 6 reads the period and
# output entries. The resolved copy of this list is saved with each run in
# <diag_dir>/calibration_settings.rds, which the manuscript artifact report reads.

cal_config <- list(
  ## Periods (separate concepts)
  years_hist   = 2000:2019,  # historical rate years read from stage 2 and written by stage 5
  fit_start    = 2009L,      # first fitted year = seed year of the calibration cohort
  fit_end      = 2019L,      # last fitted year (fitting window 2009-2019)
  obs_end      = 2019L,      # terminal observed year; stage 6 carries its rates forward
  years_proj   = 2020:2050,  # projection years assembled by stage 6

  ## Scope
  locations    = sort(as.character(readRDS(paste0(wd, "locs.rds"))$location)),  # stage-1 location list
  sexes        = c("Female", "Male"),
  causes       = unname(cause_map[c("ihd", "istroke", "hstroke", "hhd")]),
  ages         = 20:95,
  entry_age    = 20L,        # incoming cohort, re-seeded every year (as in stage 7)
  open_age     = 95L,        # terminal age row; stage 7 does not carry its stock forward
  age_band_breaks = c(seq(20, 95, by = 5), Inf),                                   # [20,25) ... [95,Inf)
  age_band_labels = c(paste0(seq(20, 90, by = 5), "-", seq(24, 94, by = 5)), "95+"), # GBD age_name without " years"

  ## Search and objective: J = w_deaths*RMSE(deaths) + w_prev*RMSE(prevalent cases), counts
  ir_grid      = c(0.40, 0.50, 0.60, 0.70, 0.80, 0.85, 0.90, 0.95,
                   1.00, 1.05, 1.10, 1.20),
  cf_grid      = c(0.30, 0.40, 0.50, 0.60, 0.70, 0.80, 0.90, 0.95,
                   1.00, 1.05, 1.10, 1.20, 1.40, 1.60, 1.80),   # 12 x 15 = 180 pairs, identity included
  w_deaths     = 2,
  w_prev       = 1,
  tp_cap       = 0.90,       # IR, CF <= tp_cap in scoring, joint runs and saved rates
  feas_margin  = 0,          # and IR, CF <= 1 - BG.mx - feas_margin (feasible well/sick exits)
  tie_rel_tol  = 1e-9,       # J within this relative distance of the minimum counts as a tie
  tie_rule     = "nearest_identity",  # ties: smallest |m_IR-1|+|m_CF-1|, then |m_IR-1|, then m_IR, then m_CF
  score_tol    = 1e-8,       # reruns must reproduce saved scores/predictions within this relative tolerance
  prob_tol     = 1e-12,      # numerical tolerance for probability-bound checks

  ## Inputs (read only)
  tps_dir      = wd_data,
  tps_pattern  = "^tps_inpt_part[0-9]+\\.rds$",
  pop_file     = paste0(wd_data, "UN2024/PopulationsSingleAge0050.rds"),
  target_file  = paste0(wd_raw, "GBD/temp_1baseline_rates_gbd23.rds"),
  target_source   = "GBD 2023",
  target_metric   = "Number",
  target_measures = c(deaths = "Deaths", prevalence = "Prevalence"),

  ## Outputs
  out_dir      = wd_data,                      # <out_dir>/<out_stub><N>.rds, historical years only
  out_stub     = "adjusted_searo_part",
  n_out_chunks = 10L,
  diag_dir     = paste0(wd_outp, "calibration/"),

  ## Execution
  parallel     = TRUE,
  max_workers  = 12L,

  ## Pilot: NULL = production. A vector of locations calibrates only those and writes
  ## every output under pilot_dir/data and pilot_dir/diagnostics (never out_dir/diag_dir).
  pilot_locations = NULL,
  pilot_dir    = paste0(wd_temp, "calibration_pilot/")
)

#...........................................................
# Mortality trend settings (stage 2 forecast, stage 6 application) ----
#...........................................................
# The single source of truth for code/2. get_tps_bgmx_100_gbd23.R and the trend step of
# code/6. build_baseline.R. Validated below against the switches above and cal_config.

# Share of the cumulative relative CF change applied (coherent and legacy LC): 80% with
# run_CF_trend_80, otherwise the full change. It scales the cumulative change, not an annual rate.
trend_cf_share <- function(run_CF_trend_80) if (isTRUE(run_CF_trend_80)) 0.8 else 1

trend_config <- list(
  method        = mortality_trend_method,
  cf_share      = trend_cf_share(run_CF_trend_80),   # share of the cumulative CF change (coherent and legacy LC)
  ## Data and windows
  years_hist    = 2000:2019,  # Global series fitted (GBD 2023 x UN-WPP 2024, from tps_inpt)
  training_end  = 2015L,      # holdout: fit 2000-2015 only, forecast and score 2016-2019
  anchor_year   = 2019L,      # cumulative changes are relative to the observed rate of this year
  forecast_end  = 2050L,      # production: refit on years_hist, forecast anchor_year+1 to forecast_end
  ages          = 20:95,
  open_age      = 95L,        # terminal row = 95+
  sexes         = c("Female", "Male"),
  causes        = cause_map[c("ihd", "istroke", "hstroke", "hhd")],   # the four disjoint modelled causes
  ## Method
  cov_shrinkage = 0.5,        # W = (1 - s) * cov(e) + s * diag(cov(e))
  rel_tol       = 1e-10,      # relative tolerance for the additive identities
  ## Inputs (read only) and outputs
  tps_dir       = wd_data,
  tps_pattern   = "^tps_inpt_part[0-9]+\\.rds$",
  pop_file      = paste0(wd_data, "UN2024/PopulationsSingleAge0050.rds"),
  ihme_dir      = paste0(wd_raw, "GBD/"),
  out_dir       = wd_data
)

# Checks one set of switches against a trend_config (method and cf_share must be synchronised
# with the switches) and against cal_config. Used here for the main run and by stage 8 for each
# sensitivity analysis's own switches; it only reads its arguments.
trend_switch_names <- c("mortality_trend_method", "run_bgmx_trend", "run_CF_trend", "run_CF_trend_80", "run_CF_trend_ihme")
check_trend_settings <- function(sw, tc = trend_config, cc = cal_config) {
  bad <- function(msg) stop("Trend settings: ", msg, call. = FALSE)
  if (!setequal(names(sw), trend_switch_names)) bad(paste("switches must be exactly", paste(trend_switch_names, collapse = ", ")))
  for (v in trend_switch_names[-1]) {
    x <- sw[[v]]
    if (!is.logical(x) || length(x) != 1L || is.na(x)) bad(paste(v, "must be TRUE or FALSE"))
  }
  if (!is.character(sw$mortality_trend_method) || length(sw$mortality_trend_method) != 1L ||
      !sw$mortality_trend_method %in% c("coherent", "legacy"))
    bad("mortality_trend_method must be \"coherent\" or \"legacy\"")
  if (!identical(tc$method, sw$mortality_trend_method)) bad("trend_config$method differs from mortality_trend_method")
  if (!identical(tc$cf_share, trend_cf_share(sw$run_CF_trend_80))) bad("trend_config$cf_share differs from run_CF_trend_80")
  if (sw$run_CF_trend_ihme && !sw$run_CF_trend) bad("run_CF_trend_ihme = TRUE needs run_CF_trend = TRUE")
  if (sw$run_CF_trend_ihme && sw$run_CF_trend_80)
    bad("run_CF_trend_ihme applies the full Foresight change; set run_CF_trend_80 = FALSE to use it")
  if (!identical(as.integer(tc$years_hist), as.integer(cc$years_hist))) bad("years_hist differs from cal_config")
  if (tc$anchor_year != cc$obs_end) bad("anchor_year differs from cal_config$obs_end")
  if (tc$forecast_end != max(cc$years_proj)) bad("forecast_end differs from cal_config$years_proj")
  if (!identical(as.integer(tc$ages), as.integer(cc$ages)) ||
      tc$open_age != cc$open_age) bad("ages differ from cal_config")
  if (!identical(tc$sexes, cc$sexes)) bad("sexes differ from cal_config")
  if (!identical(unname(tc$causes), cc$causes)) bad("causes differ from cal_config")
  invisible(TRUE)
}
check_trend_settings(mget(trend_switch_names))

#...........................................................
# 1. Base rates (State and Risks)-----
#...........................................................

if (1 %in% run_stages) {
  source(paste0(wd_code, "1. get_base_population_100.R"))
  source(paste0(wd_code, "1. get_base_rates_100_gbd23.R"))
}

#...........................................................
# 2. Transition Probabilities-----
#...........................................................

if (2 %in% run_stages) {
  if (!stage2_trends_only) source(paste0(wd_code, "2. get_tps_100_gbd23.R"))
  # Mortality trends: the coherent forecast (default) plus the legacy and IHME alternatives
  source(paste0(wd_code, "2. get_tps_bgmx_100_gbd23.R"))
}

#...........................................................
# 3. Risk Factors-----
#...........................................................

if (3 %in% run_stages) {
  source(paste0(wd_code, "3. risk_factors_100.R"))

  # Compare with fromer GBD estimates used in Kontis et al
  source(paste0(wd_code, "3. risk_factors_100_sodium.R"))
}

#...........................................................
# 4. Interventions-----
#...........................................................

if (4 %in% run_stages) {
  #source(paste0(wd_code, "4. interventions_100_tfa2_statins2.R"))
  source(paste0(wd_code, "4. prepare_interventions.R"))
}

#...........................................................
# 5. Calibration-----
#...........................................................
# One in-sample fit of historical IR/CF; writes data/processed/adjusted_searo_part<N>.rds
# (historical years only) and output/calibration/calibration_*. Replaces the legacy
# "5. calibration_100_gbd23.R" + "5. adjustments_100_gbd23.R" chain (kept, not sourced).

if (5 %in% run_stages) {
  source(paste0(wd_code, "5. calibration.R"))
}

#...........................................................
# 6. Baseline-----
#...........................................................
# Extends the calibrated 2019 rates to 2020-2050 and applies the prospective
# assumptions (populations, COVID excess mortality, secular trends, final guards).

if (6 %in% run_stages) {
  source(paste0(wd_code, "6. build_baseline.R"))
}

#...........................................................
# 7. Model-----
#...........................................................

if (7 %in% run_stages) {
  if (!exists("baseline_settings")) stop("Stage 7 needs stage 6 in the same R session (b_rates, baseline_settings).")
  manifest_file <- paste0(wd_outp, "out_model/model_run_manifest.rds")
  runner_file <- paste0(wd_code, "7. model_100_multiplicative_func_new3_gbd23_noaroc.R")
  # What must match for a partial rerun to belong to the run in the manifest.
  baseline_signature <- function(b, runner_md5) {
    list(b[c("trend_method", "cf_share", "run_bgmx_trend", "run_CF_trend", "run_CF_trend_80", "run_CF_trend_ihme",
             "calibration_run_id", "trend_run_id", "stage7_first_year", "n_locations")],
         b$trend_files[, .(file, md5)], runner_md5)
  }
  if (!is.null(stage7_countries)) {
    if (!file.exists(manifest_file)) stop("--stage7-countries: no ", manifest_file, " to add the rerun to.")
    prev_manifest <- readRDS(manifest_file)
    if (!identical(baseline_signature(prev_manifest$baseline, prev_manifest$runner_md5),
                   baseline_signature(baseline_settings, unname(tools::md5sum(runner_file)))))
      stop("--stage7-countries: the baseline settings, trend files or runner differ from the run in the manifest; rerun all countries.")
    unknown <- setdiff(stage7_countries, unique(data.in$location))
    if (length(unknown)) stop("--stage7-countries: not in the stage-6 country list: ", paste(unknown, collapse = ", "))
    # The runner models every location in data.in (minus its own exclusions); keep only the named ones.
    data.in <- data.in[location %in% stage7_countries]
  }
  stage7_started <- Sys.time()
  source(runner_file)

  # Provenance: the baseline this run used and the output files it wrote. A country whose
  # run fails keeps its earlier file, which is listed here as not written by this run.
  local({
    mo_files <- sort(list.files(paste0(wd_outp, "out_model"), pattern = "^model_output_part_.+\\.rds$", full.names = TRUE))
    written <- file.mtime(mo_files) >= stage7_started
    runner <- runner_file
    if (!is.null(stage7_countries)) {
      # Partial rerun: update the rerun countries' rows of the existing manifest and log the rerun.
      rerun_files <- paste0("model_output_part_", stage7_countries, ".rds")
      idx <- match(rerun_files, basename(mo_files))
      if (anyNA(idx)) stop("--stage7-countries: output file missing for ", paste(rerun_files[is.na(idx)], collapse = ", "))
      m <- prev_manifest
      rows <- match(rerun_files, m$files$file)
      m$files[rows, `:=`(written_this_run = written[idx], mtime = format(file.mtime(mo_files[idx]), "%Y-%m-%d %H:%M:%S"),
                         md5 = unname(tools::md5sum(mo_files[idx])))]
      if (!"written_by" %in% names(m$files)) m$files[, written_by := "main run"]
      m$files[rows, written_by := ifelse(written[idx], paste("rerun", format(stage7_started, "%Y-%m-%d %H:%M:%S")), written_by)]
      m$reruns <- rbind(m$reruns, data.table(started = format(stage7_started, "%Y-%m-%d %H:%M:%S %Z"),
                                             completed = format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z"),
                                             countries = paste(stage7_countries, collapse = "; "), written = sum(written[idx]),
                                             baseline_id = baseline_settings$baseline_id,
                                             master_md5 = unname(tools::md5sum(paste0(wd_code, "0. master.R")))))
      saveRDS(m, manifest_file)
      cat(sprintf("Model run manifest %s: rerun of %s added; %d of %d files now written by the run or its reruns\n",
                  m$run_id, paste(stage7_countries, collapse = ", "), sum(m$files$written_this_run), nrow(m$files)))
      if (any(!written[idx])) warning("Rerun outputs not written: ", paste(rerun_files[!written[idx]], collapse = ", "), call. = FALSE)
      return(invisible())
    }
    manifest <- list(
      started = format(stage7_started, "%Y-%m-%d %H:%M:%S %Z"), completed = format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z"),
      baseline = baseline_settings,
      runner_md5 = unname(tools::md5sum(runner)), master_md5 = unname(tools::md5sum(paste0(wd_code, "0. master.R"))),
      files = data.table(file = basename(mo_files), written_this_run = written,
                         mtime = format(file.mtime(mo_files), "%Y-%m-%d %H:%M:%S"),
                         md5 = unname(tools::md5sum(mo_files))))
    sig <- tempfile(fileext = ".rds")
    saveRDS(list(manifest$runner_md5, baseline_settings$baseline_id, manifest$files$md5), sig)
    manifest$run_id <- paste0(format(stage7_started, "%Y%m%d-%H%M%S"), "-", substr(unname(tools::md5sum(sig)), 1, 8))
    unlink(sig)
    saveRDS(manifest, paste0(wd_outp, "out_model/model_run_manifest.rds"))
    cat(sprintf("Model run manifest: %d output files written by this run, %d not rewritten (baseline %s, trends: %s)\n",
                sum(written), sum(!written), baseline_settings$baseline_id, baseline_settings$trend_method))
    if (any(!written)) warning("Model outputs not rewritten by this run: ",
                               paste(head(basename(mo_files[!written]), 10), collapse = ", "), call. = FALSE)
  })
}

#...........................................................
# 8. sensitivity-----
#...........................................................
# Deterministic mortality-trend sensitivity analyses for Table S8 (default: all three of
# code/8.1_sensitivity_ihme_foresight.R, 8.2_sensitivity_lc.R and 8.3_sensitivity_no_trends.R).
# Each reuses the stage-5 calibration, rebuilds its own stage-6 baseline from it and runs the
# unchanged stage-7 runner in a fresh R process, writing only under output/uncertainty/dsa/;
# the main-run switches, configuration and outputs above are not changed. Options: --dsa, --dsa-pilot,
# --dsa-workers.

if (8 %in% run_stages) {
  source(paste0(wd_code, "8. run_sensitivity.R"))
}

#...........................................................
# 9. comparisons benchmark-----
#...........................................................

if (9 %in% run_stages) {
  source(paste0(wd_code, "9. run_benchmark.R"))
}
