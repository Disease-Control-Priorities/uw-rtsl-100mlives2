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
# Stages 1-4 rebuild the processed inputs from data-raw/. Stages 8-9 source
# scripts that are not in the repository yet.

run_stages <- local({
  a <- commandArgs(trailingOnly = TRUE)
  if (length(a)) as.integer(a) else 1:9
})
if (anyNA(run_stages) || !all(run_stages %in% 1:9)) stop("run_stages must be stage numbers 1-9.")

#...........................................................
# 0. Functions and parameters-----
#...........................................................

source(paste0(wd_code, "functions_review_6_100.R"))

run_aod_par <- FALSE # set to TRUE to run model with dementia

# Stage 6 projection assumptions (prospective only; never used by the calibration)

run_bgmx_trend <- TRUE

run_CF_trend   <- TRUE

# Baseline scenario 80% of secular trend. 20% historically explained by
# HTN control improvements

run_CF_trend_80   <- TRUE

run_CF_trend_ihme  <- FALSE

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
  source(paste0(wd_code, "2. get_tps_100_gbd23.R"))
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
  source(paste0(wd_code, "4. interventions_100_tfa2_statins2.R"))
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
  source(paste0(wd_code, "7. model_100_multiplicative_func_new3_gbd23_noaroc.R"))
}

#...........................................................
# 8. sensitivity-----
#...........................................................

if (8 %in% run_stages) {
  source(paste0(wd_code, "8. run_sensitivity.R"))
}

#...........................................................
# 9. comparisons benchmark-----
#...........................................................

if (9 %in% run_stages) {
  source(paste0(wd_code, "9. run_benchmark.R"))
}
