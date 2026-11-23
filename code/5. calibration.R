#===============================================================================
# code/5. calibration.R  --  Stage 5: single in-sample calibration of the
#                            historical incidence (IR) and case-fatality (CF)
#                            transition probabilities
#-------------------------------------------------------------------------------
# Replaces the legacy two-pass chain (5. calibration_100_gbd23.R, which sourced
# 5. adjustments_100_gbd23.R and wrote adjustments2023_age.csv for stage 6 to
# apply a second time). Those files stay in code/ but nothing sources them.
#
# WHAT THIS STAGE DOES (one fit, one application)
#   1. Reads the stage-2 historical rates (tps_inpt_part*.rds) and the GBD 2023
#      Number targets for deaths and prevalent cases.
#   2. For every (m_IR, m_CF) pair on the grid it multiplies IR and CF of EVERY
#      location, sex, cause and age by that pair, projects the historical cohort
#      over the fitting window, sums simulated deaths and prevalent cases into
#      the GBD five-year age bands and scores each
#      location x sex x cause x age band (stratum) with
#          J = w_D * RMSE(deaths) + w_K * RMSE(prevalent cases)
#      (RMSEs of counts over the fitting years; a weighted sum of two RMSEs).
#   3. Selects, for each stratum, the pair with the smallest J. Ties (scores
#      within tie_rel_tol of the minimum) go to the pair nearest the identity:
#      smallest |m_IR-1|+|m_CF-1|, then |m_IR-1|, then m_IR, then m_CF.
#   4. Reruns the cohort twice on the same targets: uncalibrated (identity) and
#      with all selected pairs applied together exactly as saved. These joint
#      runs, not the per-stratum grid minima, are the reported before/after fit.
#   5. Applies the selected multipliers ONCE, constant over time, to the
#      stratum's IR/CF in every historical year (years_hist), and writes
#      data/processed/<out_stub><N>.rds for stage 6.
#   No secular trend, COVID-era term, forecast or future-population adjustment is
#   applied here; stage 6 owns all of them.
#
# COHORT (the recursion of project.all() in stage 7, which is NOT modified)
#   Seed year (fit_start, all ages) and every year's entry age (20) are set from
#   the population Nx:  sick = Nx*PREVt0, dead = Nx*DIS.mx.t0,
#   well = Nx*(1-(PREVt0+BG.mx)), pop = Nx, all.mx = Nx*DIS.mx.t0 + Nx*BG.mx.
#   For each year t > seed and origin age a < open_age (rates of age a, year t):
#     sick'  = sick*(1-(CF+BG.mx+covid.mx)) + well*IR        (floored at 0)
#     dead'  = sick*CF                                         (floored at 0)
#     pop'   = pop - all.mx                                    (floored at 0)
#     all.mx'= sum over the four causes of dead' + pop'*BG.mx.all + pop'*covid.mx
#     well'  = pop' - all.mx' - sick'                          (floored at 0)
#   recorded at age a+1, year t. The four causes share the population: pop and
#   all.mx are one shared pool repeated on each cause row (never summed over
#   causes), and background mortality BG.mx.all enters all.mx once.
#   Terminal age: as in stage 7, the open_age row of year t-1 is not carried
#   forward, so after the seed year age 95 holds only last year's 94-year-olds.
#   covid.mx is 0 in every historical year. The seed population is UN-WPP 2024
#   by single year with ages >= open_age summed into the open_age row, the same
#   construction stage 6 gives stage 7 (tps_inpt Nx holds single-year age 95).
#
# PROBABILITY RULE (identical in scoring, in the joint runs and in saved rates)
#   IR* = min(IR*m_IR, cap), CF* = min(CF*m_CF, cap),
#   cap = min(tp_cap, 1 - BG.mx - feas_margin)   (row-specific)
#   so IR*+BG.mx <= 1 and CF*+BG.mx <= 1 hold in every saved historical row.
#   Cells where the rule binds are counted in calibration_cap_audit.csv.
#
# SETTINGS
#   Every mandatory setting comes from cal_config, declared only in
#   code/0. master.R. Nothing here supplies a default; a missing or invalid
#   setting stops the run.
#
# OUTPUTS
#   <out_dir>/<out_stub><N>.rds   calibrated HISTORICAL rates only (years_hist),
#       chunked by whole location, same 13 columns and types as tps_inpt, full
#       cause names; attribute "calibration_run_id" on every chunk.
#   <diag_dir>/calibration_*      settings + fingerprints + session, coverage,
#       factors and scores, target/prediction panel, fit summaries, cap audit,
#       check log (all outside the adjusted_searo_part*.rds discovery pattern).
#   Pilot (cal_config$pilot_locations not NULL): both go under pilot_dir only.
#===============================================================================

suppressPackageStartupMessages({
  library(data.table)
  library(parallel)
})

message("\n== Stage 5: single in-sample calibration of historical IR/CF ==")
cal_t0 <- Sys.time()

#===============================================================================
# 0. SETTINGS (from code/0. master.R only)
#===============================================================================

if (!exists("cal_config", inherits = TRUE) || !is.list(cal_config)) {
  stop("code/5. calibration.R must be sourced after code/0. master.R has defined cal_config.",
       call. = FALSE)
}

cal_validate_config <- function(cfg) {
  need <- c("years_hist", "fit_start", "fit_end", "obs_end", "years_proj",
            "locations", "sexes", "causes", "ages", "entry_age", "open_age",
            "age_band_breaks", "age_band_labels",
            "ir_grid", "cf_grid", "w_deaths", "w_prev", "tp_cap", "feas_margin",
            "tie_rel_tol", "tie_rule", "score_tol", "prob_tol",
            "tps_dir", "tps_pattern", "pop_file", "target_file", "target_source",
            "target_metric", "target_measures",
            "out_dir", "out_stub", "n_out_chunks", "diag_dir",
            "parallel", "max_workers", "pilot_locations", "pilot_dir")
  miss <- setdiff(need, names(cfg))
  if (length(miss)) stop("cal_config is missing settings: ", paste(miss, collapse = ", "), call. = FALSE)
  extra <- setdiff(names(cfg), need)
  if (length(extra)) stop("cal_config has unknown settings: ", paste(extra, collapse = ", "), call. = FALSE)
  nul <- need[vapply(cfg[need], is.null, logical(1))]
  nul <- setdiff(nul, "pilot_locations")
  if (length(nul)) stop("cal_config settings are NULL: ", paste(nul, collapse = ", "), call. = FALSE)
  bad <- function(msg) stop("cal_config: ", msg, call. = FALSE)
  is_int_vec <- function(x) is.numeric(x) && length(x) > 0 && all(is.finite(x)) && all(x == round(x))
  is_scalar_num <- function(x) is.numeric(x) && length(x) == 1L && is.finite(x)

  for (nm in c("years_hist", "years_proj", "ages")) {
    if (!is_int_vec(cfg[[nm]])) bad(paste(nm, "must be a vector of whole numbers"))
    if (anyDuplicated(cfg[[nm]]) || is.unsorted(cfg[[nm]])) bad(paste(nm, "must be sorted and unique"))
    if (any(diff(cfg[[nm]]) != 1)) bad(paste(nm, "must be consecutive"))
    cfg[[nm]] <- as.integer(cfg[[nm]])
  }
  for (nm in c("fit_start", "fit_end", "obs_end", "entry_age", "open_age", "n_out_chunks", "max_workers")) {
    if (!is_int_vec(cfg[[nm]]) || length(cfg[[nm]]) != 1L) bad(paste(nm, "must be one whole number"))
    cfg[[nm]] <- as.integer(cfg[[nm]])
  }
  if (cfg$fit_start >= cfg$fit_end) bad("fit_start must be before fit_end")
  if (!all(c(cfg$fit_start, cfg$fit_end) %in% cfg$years_hist)) bad("the fitting window must lie inside years_hist")
  if (cfg$obs_end != max(cfg$years_hist)) bad("obs_end must be the last year of years_hist")
  if (cfg$fit_end > cfg$obs_end) bad("fit_end cannot be after obs_end")
  if (min(cfg$years_proj) != cfg$obs_end + 1L) bad("years_proj must start the year after obs_end")
  if (cfg$entry_age != min(cfg$ages)) bad("entry_age must be the first model age")
  if (cfg$open_age != max(cfg$ages)) bad("open_age must be the last model age")
  if (cfg$n_out_chunks < 1L || cfg$max_workers < 1L) bad("n_out_chunks and max_workers must be >= 1")

  for (nm in c("locations", "sexes", "causes", "age_band_labels")) {
    if (!is.character(cfg[[nm]]) || !length(cfg[[nm]]) || anyNA(cfg[[nm]]) || anyDuplicated(cfg[[nm]]))
      bad(paste(nm, "must be a non-empty character vector without duplicates"))
  }
  br <- cfg$age_band_breaks
  if (!is.numeric(br) || is.unsorted(br, strictly = TRUE) || br[1] != min(cfg$ages) || !is.infinite(br[length(br)]))
    bad("age_band_breaks must increase strictly, start at the first age and end at Inf")
  if (length(cfg$age_band_labels) != length(br) - 1L) bad("age_band_labels needs one label per band")
  bands <- as.character(cut(cfg$ages, breaks = br, labels = cfg$age_band_labels, right = FALSE))
  if (anyNA(bands)) bad("some model ages fall outside the age bands")
  if (!setequal(unique(bands), cfg$age_band_labels)) bad("some age bands contain no model age")
  if (bands[length(bands)] != cfg$age_band_labels[length(cfg$age_band_labels)] ||
      sum(bands == bands[length(bands)]) != 1L)
    bad("the terminal age band must contain only open_age")

  for (nm in c("ir_grid", "cf_grid")) {
    g <- cfg[[nm]]
    if (!is.numeric(g) || !length(g) || any(!is.finite(g)) || any(g <= 0)) bad(paste(nm, "must be positive finite numbers"))
    if (anyDuplicated(g) || is.unsorted(g)) bad(paste(nm, "must be sorted and unique"))
    if (!any(abs(g - 1) < 1e-12)) bad(paste(nm, "must contain the identity multiplier 1"))
  }
  for (nm in c("w_deaths", "w_prev", "tp_cap", "feas_margin", "tie_rel_tol", "score_tol", "prob_tol")) {
    if (!is_scalar_num(cfg[[nm]])) bad(paste(nm, "must be one finite number"))
  }
  if (cfg$w_deaths < 0 || cfg$w_prev < 0 || cfg$w_deaths + cfg$w_prev <= 0) bad("objective weights must be >= 0, not both 0")
  if (cfg$tp_cap <= 0 || cfg$tp_cap > 1) bad("tp_cap must be in (0, 1]")
  if (cfg$feas_margin < 0 || cfg$feas_margin >= 1) bad("feas_margin must be in [0, 1)")
  if (cfg$tie_rel_tol < 0 || cfg$score_tol <= 0 || cfg$prob_tol < 0) bad("tolerances must be >= 0 (score_tol > 0)")
  if (!identical(cfg$tie_rule, "nearest_identity")) bad("tie_rule must be \"nearest_identity\" (the only implemented rule)")

  for (nm in c("tps_dir", "pop_file", "target_file", "target_source", "target_metric", "out_dir",
               "out_stub", "diag_dir", "pilot_dir", "tps_pattern")) {
    if (!is.character(cfg[[nm]]) || length(cfg[[nm]]) != 1L || !nzchar(cfg[[nm]])) bad(paste(nm, "must be one string"))
  }
  if (!grepl("^\\^", cfg$tps_pattern) || !grepl("\\$$", cfg$tps_pattern)) bad("tps_pattern must be anchored (^...$)")
  if (!grepl("^[A-Za-z0-9_.-]+$", cfg$out_stub)) bad("out_stub may contain only letters, digits, '_', '.', '-'")
  tm <- cfg$target_measures
  if (!is.character(tm) || !setequal(names(tm), c("deaths", "prevalence")) || anyNA(tm))
    bad("target_measures must be c(deaths = <measure_name>, prevalence = <measure_name>)")
  if (!dir.exists(cfg$tps_dir)) bad(paste("tps_dir does not exist:", cfg$tps_dir))
  for (nm in c("pop_file", "target_file")) if (!file.exists(cfg[[nm]])) bad(paste(nm, "not found:", cfg[[nm]]))
  if (!is.logical(cfg$parallel) || length(cfg$parallel) != 1L || is.na(cfg$parallel)) bad("parallel must be TRUE or FALSE")
  if (!is.null(cfg$pilot_locations)) {
    if (!is.character(cfg$pilot_locations) || !length(cfg$pilot_locations) || anyDuplicated(cfg$pilot_locations))
      bad("pilot_locations must be NULL or a character vector of model locations")
    if (length(setdiff(cfg$pilot_locations, cfg$locations)))
      bad(paste("pilot_locations not in locations:", paste(setdiff(cfg$pilot_locations, cfg$locations), collapse = ", ")))
  }
  cfg
}
cfg <- cal_validate_config(cal_config)

cal_pilot <- !is.null(cfg$pilot_locations)
cal_out_dir  <- if (cal_pilot) file.path(cfg$pilot_dir, "data") else cfg$out_dir
cal_diag_dir <- if (cal_pilot) file.path(cfg$pilot_dir, "diagnostics") else cfg$diag_dir
if (cal_pilot && normalizePath(cal_out_dir, mustWork = FALSE) == normalizePath(cfg$out_dir, mustWork = FALSE))
  stop("Stage 5: pilot_dir must not resolve to the production out_dir.", call. = FALSE)
dir.create(cal_out_dir,  recursive = TRUE, showWarnings = FALSE)
dir.create(cal_diag_dir, recursive = TRUE, showWarnings = FALSE)

cal_locs  <- sort(if (cal_pilot) cfg$pilot_locations else cfg$locations)
cal_key   <- c("location", "sex", "cause", "age_group")
cal_years <- cfg$fit_start:cfg$fit_end
cal_band_of_age <- function(age) {
  as.character(cut(age, breaks = cfg$age_band_breaks, labels = cfg$age_band_labels, right = FALSE))
}
cat(sprintf("  Scope: %d location(s)%s | %s | fit %d-%d | historical years %d-%d\n",
            length(cal_locs), if (cal_pilot) " [PILOT]" else "", paste(cfg$causes, collapse = ", "),
            cfg$fit_start, cfg$fit_end, min(cfg$years_hist), max(cfg$years_hist)))

#===============================================================================
# 1. HISTORICAL RATES (stage 2, read only)
#===============================================================================

cal_rate_cols <- c("age", "sex", "location", "year", "cause", "BG.mx.all", "ALL.mx",
                   "BG.mx", "PREVt0", "DIS.mx.t0", "Nx", "IR", "CF")
tps_files <- sort(list.files(cfg$tps_dir, pattern = cfg$tps_pattern, full.names = TRUE))
if (!length(tps_files)) stop("Stage 5: no files match ", cfg$tps_pattern, " in ", cfg$tps_dir, call. = FALSE)
rates <- rbindlist(lapply(tps_files, function(f) { d <- readRDS(f); setDT(d); d }), use.names = TRUE, fill = TRUE)
miss <- setdiff(cal_rate_cols, names(rates))
if (length(miss)) stop("Stage 5: historical rates lack columns: ", paste(miss, collapse = ", "), call. = FALSE)
rates <- rates[, ..cal_rate_cols]
rates[, `:=`(age = as.integer(age), year = as.integer(year), sex = as.character(sex),
             location = as.character(location), cause = as.character(cause))]

cal_check_set <- function(found, expected, what) {
  if (!setequal(found, expected)) {
    stop("Stage 5: ", what, " differ from cal_config. Missing: ",
         paste(head(setdiff(expected, found), 20), collapse = ", "), " | unexpected: ",
         paste(head(setdiff(found, expected), 20), collapse = ", "), call. = FALSE)
  }
}
cal_check_set(unique(rates$location), cfg$locations, "historical-rate locations")
cal_check_set(unique(rates$sex),      cfg$sexes,     "historical-rate sexes")
cal_check_set(unique(rates$cause),    cfg$causes,    "historical-rate causes")
cal_check_set(unique(rates$age),      cfg$ages,      "historical-rate ages")
cal_check_set(unique(rates$year),     cfg$years_hist, "historical-rate years")
if (anyDuplicated(rates, by = c("location", "year", "sex", "cause", "age")))
  stop("Stage 5: historical rates have duplicated location x year x sex x cause x age keys.", call. = FALSE)
n_expect <- length(cfg$locations) * length(cfg$years_hist) * length(cfg$sexes) * length(cfg$causes) * length(cfg$ages)
if (nrow(rates) != n_expect)
  stop("Stage 5: historical rates have ", nrow(rates), " rows; the complete grid has ", n_expect, ".", call. = FALSE)
num_cols <- setdiff(cal_rate_cols, c("age", "sex", "location", "year", "cause"))
for (v in num_cols) {
  x <- rates[[v]]
  if (!is.numeric(x) || any(!is.finite(x))) stop("Stage 5: historical rates column ", v, " has missing or non-finite values.", call. = FALSE)
  if (any(x < 0)) stop("Stage 5: historical rates column ", v, " has negative values.", call. = FALSE)
  if (v != "Nx" && any(x > 1)) stop("Stage 5: historical rates column ", v, " has probabilities above 1.", call. = FALSE)
}
shared_dev <- rates[, .(d = (max(Nx) - min(Nx)) + (max(BG.mx.all) - min(BG.mx.all)) + (max(ALL.mx) - min(ALL.mx))),
                    by = .(location, year, sex, age)][, max(d)]
if (shared_dev > 1e-9)
  stop("Stage 5: Nx, ALL.mx or BG.mx.all differ across causes within location x year x sex x age.", call. = FALSE)
if (any(rates$BG.mx > 1 - cfg$feas_margin))
  stop("Stage 5: BG.mx exceeds 1 - feas_margin in some rows; no feasible IR/CF exists there.", call. = FALSE)
rm(shared_dev, num_cols, n_expect, miss)

rates <- rates[location %in% cal_locs]
setkeyv(rates, c("location", "year", "sex", "cause", "age"))
cat(sprintf("  Historical rates: %d rows from %d file(s)\n", nrow(rates), length(tps_files)))

#===============================================================================
# 2. SEED POPULATION (UN-WPP 2024 single year; ages >= open_age summed)
#===============================================================================

pop <- readRDS(cfg$pop_file); setDT(pop)
miss <- setdiff(c("location", "year_id", "sex", "age", "Nx"), names(pop))
if (length(miss)) stop("Stage 5: population file lacks columns: ", paste(miss, collapse = ", "), call. = FALSE)
pop <- pop[location %in% cal_locs & year_id %in% cal_years & sex %in% cfg$sexes & age >= min(cfg$ages),
           .(location = as.character(location), year = as.integer(year_id), sex = as.character(sex),
             age = as.integer(pmin(age, cfg$open_age)), Nx = as.numeric(Nx))]
pop <- pop[, .(Nx_seed = sum(Nx)), keyby = .(location, year, sex, age)]
pop_grid <- CJ(location = cal_locs, year = cal_years, sex = cfg$sexes, age = cfg$ages)
if (nrow(pop) != nrow(pop_grid) || nrow(pop[!pop_grid, on = .(location, year, sex, age)]) ||
    nrow(pop_grid[!pop, on = .(location, year, sex, age)])) {
  stop("Stage 5: the population file does not cover every location x year x sex x age of the fitting window.",
       call. = FALSE)
}
if (any(!is.finite(pop$Nx_seed)) || any(pop$Nx_seed < 0)) stop("Stage 5: invalid seed population values.", call. = FALSE)
# Below the open age the seed population must be the Nx already in the stage-2 rates.
pop_chk <- unique(rates[year %in% cal_years & age < cfg$open_age, .(location, year, sex, age, Nx)])[
  pop, on = .(location, year, sex, age), nomatch = NULL]
pop_dev <- pop_chk[, max(abs(Nx - Nx_seed) / pmax(Nx_seed, 1))]
if (pop_dev > 1e-6) stop("Stage 5: the population file and tps_inpt Nx disagree below the open age (max rel. diff ",
                         signif(pop_dev, 3), ").", call. = FALSE)
open_ratio <- merge(unique(rates[year %in% cal_years & age == cfg$open_age, .(location, year, sex, Nx)]),
                    pop[age == cfg$open_age], by = c("location", "year", "sex"))[, sum(Nx_seed) / sum(Nx)]
cat(sprintf("  Seed population: UN-WPP single year; open age %d+ / single-year %d in tps_inpt = %.2f\n",
            cfg$open_age, cfg$open_age, open_ratio))
rm(pop_grid, pop_chk, miss)

#===============================================================================
# 3. TARGETS: GBD Number of deaths and prevalent cases by band x year
#===============================================================================

tg <- readRDS(cfg$target_file); setDT(tg)
miss <- setdiff(c("measure_name", "metric_name", "location_name", "sex_name", "age_name", "cause_name", "year", "val"),
                names(tg))
if (length(miss)) stop("Stage 5: target file lacks columns: ", paste(miss, collapse = ", "), call. = FALSE)
tg <- tg[metric_name == cfg$target_metric & measure_name %in% cfg$target_measures &
           cause_name %in% cfg$causes & location_name %in% cal_locs & sex_name %in% cfg$sexes &
           year >= cfg$fit_start & year <= cfg$fit_end,
         .(location = as.character(location_name), sex = as.character(sex_name),
           cause = as.character(cause_name), age_group = sub(" years$", "", as.character(age_name)),
           year = as.integer(year), measure = names(cfg$target_measures)[match(measure_name, cfg$target_measures)],
           val = as.numeric(val))]
bad_age <- setdiff(unique(tg$age_group), cfg$age_band_labels)
if (length(bad_age)) stop("Stage 5: target age labels outside the model bands: ", paste(bad_age, collapse = ", "),
                          call. = FALSE)
if (anyDuplicated(tg, by = c(cal_key, "year", "measure")))
  stop("Stage 5: targets have duplicated location x sex x cause x band x year x measure cells.", call. = FALSE)
if (any(!is.na(tg$val) & (!is.finite(tg$val) | tg$val < 0)))
  stop("Stage 5: targets contain non-finite or negative counts.", call. = FALSE)

tgt_grid <- CJ(location = cal_locs, sex = cfg$sexes, cause = cfg$causes, age_group = cfg$age_band_labels,
               year = cal_years)
tgt <- copy(tgt_grid)
tgt[tg[measure == "deaths"],     on = c(cal_key, "year"), obs_deaths := i.val]
tgt[tg[measure == "prevalence"], on = c(cal_key, "year"), obs_prev   := i.val]
tcov <- tgt[, .(cells = .N,
               deaths_present = sum(!is.na(obs_deaths)), deaths_missing = sum(is.na(obs_deaths)),
               deaths_zero = sum(obs_deaths == 0, na.rm = TRUE),
               prev_present = sum(!is.na(obs_prev)), prev_missing = sum(is.na(obs_prev)),
               prev_zero = sum(obs_prev == 0, na.rm = TRUE)), keyby = location]
tcov[, `:=`(target_source = cfg$target_source, target_metric = cfg$target_metric,
           years = paste0(cfg$fit_start, "-", cfg$fit_end))]
fwrite(tcov, file.path(cal_diag_dir, "calibration_target_coverage.csv"))
if (tcov[, sum(deaths_missing + prev_missing)] > 0) {
  stop("Stage 5: ", tcov[, sum(deaths_missing)], " death and ", tcov[, sum(prev_missing)],
       " prevalence target cells are missing (see calibration_target_coverage.csv); first location: ",
       tcov[deaths_missing + prev_missing > 0, location][1], call. = FALSE)
}
n_extra <- nrow(tg[!tgt_grid, on = c(cal_key, "year")])
if (n_extra) stop("Stage 5: ", n_extra, " target cells fall outside the model key grid.", call. = FALSE)
cat(sprintf("  Targets: %s %s, %d cells x 2 measures | zeros: deaths %d, prevalence %d (kept as observed zeros)\n",
            cfg$target_source, cfg$target_metric, nrow(tgt), tcov[, sum(deaths_zero)], tcov[, sum(prev_zero)]))
rm(tg, tgt_grid, bad_age, miss, n_extra)

#===============================================================================
# 4. ENGINE: the stage-7 recursion with keyed joins (no positional assignment)
#===============================================================================

# r: one row per location x sex x cause x age x year (y0..y1) with final IR, CF and
# BG.mx, BG.mx.all, PREVt0, DIS.mx.t0, Nx_seed, covid.mx. Returns recorded states.
cal_project <- function(r, y0, y1, entry_age, open_age) {
  seed_states <- function(x) {
    x[, .(location, sex, cause, age,
          sick  = Nx_seed * PREVt0,
          dead  = Nx_seed * DIS.mx.t0,
          well  = Nx_seed * (1 - (PREVt0 + BG.mx)),
          pop   = Nx_seed,
          allmx = Nx_seed * DIS.mx.t0 + Nx_seed * BG.mx)]
  }
  st <- seed_states(r[year == y0])
  out <- vector("list", y1 - y0 + 1L)
  out[[1L]] <- st[, year := y0]
  for (k in seq_len(y1 - y0)) {
    t <- y0 + k
    rt <- r[year == t, .(location, sex, cause, age, IR, CF, BG.mx, BG.mx.all, covid.mx)]
    o  <- st[age < open_age, .(location, sex, cause, age, sick, well, pop, allmx)]
    m  <- rt[o, on = .(location, sex, cause, age), nomatch = NULL]
    if (nrow(m) != nrow(o)) stop("cal_project: missing rates for some origin cells in ", t, call. = FALSE)
    m[, `:=`(sick2 = sick * (1 - (CF + BG.mx + covid.mx)) + well * IR,
             dead2 = sick * CF,
             pop2  = pop - allmx)]
    m[sick2 < 0, sick2 := 0]
    m[dead2 < 0, dead2 := 0]
    m[pop2  < 0, pop2  := 0]
    m[, allmx2 := sum(dead2), by = .(location, sex, age)]            # the four causes, one shared pool
    m[, allmx2 := allmx2 + pop2 * BG.mx.all + pop2 * covid.mx]
    m[allmx2 < 0, allmx2 := 0]
    m[, well2 := pop2 - allmx2 - sick2]
    m[well2 < 0, well2 := 0]
    nxt <- m[, .(location, sex, cause, age = age + 1L, sick = sick2, dead = dead2,
                 well = well2, pop = pop2, allmx = allmx2)]
    st <- rbindlist(list(seed_states(r[year == t & age == entry_age]), nxt), use.names = TRUE)
    out[[k + 1L]] <- st[, year := t]
  }
  rbindlist(out, use.names = TRUE)
}

# Simulated deaths and prevalent cases by stratum x year (bands of the recorded age).
cal_predict <- function(r, core) {
  s <- cal_project(r, core$fit_start, core$fit_end, core$entry_age, core$open_age)
  s[, age_group := core$band_by_age[age - core$entry_age + 1L]]
  s[, .(pred_deaths = sum(dead), pred_prev = sum(sick)), keyby = .(location, sex, cause, age_group, year)]
}

# Per-stratum objective: J = w_D * RMSE(deaths) + w_K * RMSE(prevalent cases), counts, over years.
cal_score <- function(pr, tgt, core) {
  j <- tgt[pr, on = .(location, sex, cause, age_group, year)]
  if (nrow(j) != nrow(tgt) || anyNA(j$obs_deaths) || anyNA(j$obs_prev))
    stop("cal_score: predictions and targets do not cover the same cells.", call. = FALSE)
  j[, .(rmse_deaths = sqrt(mean((pred_deaths - obs_deaths)^2)),
        rmse_prev   = sqrt(mean((pred_prev   - obs_prev)^2))),
    keyby = .(location, sex, cause, age_group)][
      , error := core$w_deaths * rmse_deaths + core$w_prev * rmse_prev][]
}

# Calibrate one group of locations: exhaustive grid, deterministic selection, joint runs.
cal_fit_group <- function(g, core) {
  data.table::setDTthreads(core$dt_threads)
  b <- data.table::copy(g$base); tgt <- g$tgt     # copy(): over-allocated, safe to add columns by reference
  key <- c("location", "sex", "cause", "age_group")
  grid <- data.table::CJ(ir_mult = core$ir_grid, cf_mult = core$cf_grid)
  sc <- vector("list", nrow(grid))
  for (k in seq_len(nrow(grid))) {
    data.table::set(b, j = "IR", value = pmin(b$IR0 * grid$ir_mult[k], b$cap))
    data.table::set(b, j = "CF", value = pmin(b$CF0 * grid$cf_mult[k], b$cap))
    s <- cal_score(cal_predict(b, core), tgt, core)
    s[, `:=`(ir_mult = grid$ir_mult[k], cf_mult = grid$cf_mult[k])]
    sc[[k]] <- s
  }
  sc <- data.table::rbindlist(sc)
  ident <- sc[abs(ir_mult - 1) < 1e-12 & abs(cf_mult - 1) < 1e-12,
              .(location, sex, cause, age_group, id_grid_error = error,
                id_grid_rmse_deaths = rmse_deaths, id_grid_rmse_prev = rmse_prev)]
  # deterministic selection: minimum J; ties within tie_rel_tol go to the pair nearest the identity
  sc[, min_error := min(error), by = key]
  sc <- sc[error <= min_error * (1 + core$tie_rel_tol) + 1e-300]
  sc[, `:=`(d_l1 = round(abs(ir_mult - 1) + abs(cf_mult - 1), 10), d_ir = round(abs(ir_mult - 1), 10))]
  data.table::setorderv(sc, c(key, "d_l1", "d_ir", "ir_mult", "cf_mult"))
  best <- sc[, .(ir_mult = ir_mult[1L], cf_mult = cf_mult[1L], sel_error = error[1L],
                 sel_rmse_deaths = rmse_deaths[1L], sel_rmse_prev = rmse_prev[1L], n_tied = .N), by = key]
  best <- merge(best, ident, by = key)
  # joint runs on the same targets: identity (per-row multipliers = 1) and all selected pairs together
  data.table::set(b, j = "age_group", value = core$band_by_age[b$age - core$entry_age + 1L])
  run_joint <- function(fac) {
    b[, c("m_ir", "m_cf") := NULL]
    b[fac, on = key, `:=`(m_ir = i.ir_mult, m_cf = i.cf_mult)]
    if (anyNA(b$m_ir) || anyNA(b$m_cf)) stop("cal_fit_group: rows without a multiplier in the joint run.", call. = FALSE)
    data.table::set(b, j = "IR", value = pmin(b$IR0 * b$m_ir, b$cap))
    data.table::set(b, j = "CF", value = pmin(b$CF0 * b$m_cf, b$cap))
    cal_predict(b, core)
  }
  b[, `:=`(m_ir = NA_real_, m_cf = NA_real_)]
  pr_id  <- run_joint(best[, .(location, sex, cause, age_group, ir_mult = 1, cf_mult = 1)])
  pr_cal <- run_joint(best[, .(location, sex, cause, age_group, ir_mult, cf_mult)])
  s_id  <- cal_score(pr_id,  tgt, core)
  s_cal <- cal_score(pr_cal, tgt, core)
  best[s_id,  on = key, `:=`(id_joint_error = i.error, id_joint_rmse_deaths = i.rmse_deaths,
                             id_joint_rmse_prev = i.rmse_prev)]
  best[s_cal, on = key, `:=`(joint_error = i.error, joint_rmse_deaths = i.rmse_deaths,
                             joint_rmse_prev = i.rmse_prev)]
  panel <- tgt[pr_id, on = .(location, sex, cause, age_group, year)][
    , .(location, sex, cause, age_group, year, obs_deaths, obs_prev,
        uncal_deaths = pred_deaths, uncal_prev = pred_prev)]
  panel[pr_cal, on = .(location, sex, cause, age_group, year),
        `:=`(cal_deaths = i.pred_deaths, cal_prev = i.pred_prev)]
  list(factors = best, panel = panel)
}

#===============================================================================
# 5. PREPARE THE FITTING-WINDOW PANEL AND RUN THE GRID
#===============================================================================

cal_cap_of <- function(bg) pmin(cfg$tp_cap, 1 - bg - cfg$feas_margin)
base <- rates[year %in% cal_years, .(location, sex, cause, age, year, IR0 = IR, CF0 = CF, BG.mx, BG.mx.all,
                                     PREVt0, DIS.mx.t0)]
base[pop, on = .(location, year, sex, age), Nx_seed := i.Nx_seed]
if (anyNA(base$Nx_seed)) stop("Stage 5: rows without a seed population.", call. = FALSE)
base[, `:=`(cap = cal_cap_of(BG.mx), covid.mx = 0, IR = NA_real_, CF = NA_real_)]
setkeyv(base, c("location", "sex", "cause", "age", "year"))

core <- list(fit_start = cfg$fit_start, fit_end = cfg$fit_end, entry_age = cfg$entry_age,
             open_age = cfg$open_age, band_by_age = cal_band_of_age(cfg$ages),
             ir_grid = cfg$ir_grid, cf_grid = cfg$cf_grid, w_deaths = cfg$w_deaths, w_prev = cfg$w_prev,
             tie_rel_tol = cfg$tie_rel_tol, dt_threads = if (cfg$parallel) 1L else 0L)

n_workers <- if (cfg$parallel) max(1L, min(cfg$max_workers, parallel::detectCores() - 1L, length(cal_locs))) else 1L
# Locations never interact in the cohort, so grouping changes run time, not results.
# Parallel: about three groups per worker (load balance); sequential: one group.
n_groups  <- if (n_workers > 1L) max(1L, min(length(cal_locs), 3L * n_workers)) else 1L
grp_of    <- setNames(if (n_groups == 1L) rep(1L, length(cal_locs)) else
                        cut(seq_along(cal_locs), breaks = n_groups, labels = FALSE), cal_locs)
groups    <- lapply(seq_len(n_groups), function(i) {
  gl <- names(grp_of)[grp_of == i]
  list(base = base[location %in% gl], tgt = tgt[location %in% gl])
})
cat(sprintf("  Grid: %d IR x %d CF = %d pairs (identity included) | J = %g*RMSE(deaths) + %g*RMSE(prevalence) | cap min(%.2f, 1 - BG.mx%s)\n",
            length(cfg$ir_grid), length(cfg$cf_grid), length(cfg$ir_grid) * length(cfg$cf_grid),
            cfg$w_deaths, cfg$w_prev, cfg$tp_cap,
            if (cfg$feas_margin > 0) sprintf(" - %g", cfg$feas_margin) else ""))

t_grid <- Sys.time()
if (cfg$parallel && n_groups > 1L && n_workers > 1L) {
  cat(sprintf("  Running %d location groups on %d workers...\n", n_groups, n_workers))
  cl <- parallel::makeCluster(n_workers)
  fits <- tryCatch({
    parallel::clusterEvalQ(cl, suppressPackageStartupMessages(library(data.table)))
    parallel::clusterExport(cl, c("cal_project", "cal_predict", "cal_score", "cal_fit_group"),
                            envir = environment())
    parallel::parLapplyLB(cl, groups, cal_fit_group, core = core)
  }, finally = parallel::stopCluster(cl))
} else {
  cat(sprintf("  Running %d location group(s) sequentially...\n", n_groups))
  fits <- lapply(groups, cal_fit_group, core = core)
}
cat(sprintf("  Grid search done in %.1f min\n", as.numeric(difftime(Sys.time(), t_grid, units = "mins"))))
rm(groups); invisible(gc(FALSE))

factors <- rbindlist(lapply(fits, `[[`, "factors"), use.names = TRUE)
panel   <- rbindlist(lapply(fits, `[[`, "panel"),   use.names = TRUE)
rm(fits)
setkeyv(factors, cal_key)
setkeyv(panel, c(cal_key, "year"))
strata_grid <- CJ(location = cal_locs, sex = cfg$sexes, cause = cfg$causes, age_group = cfg$age_band_labels)
if (nrow(factors) != nrow(strata_grid) || nrow(strata_grid[!factors, on = cal_key]))
  stop("Stage 5: selected factors do not cover every stratum.", call. = FALSE)
if (anyNA(factors$ir_mult) || anyNA(factors$cf_mult)) stop("Stage 5: missing selected factors.", call. = FALSE)
if (nrow(panel) != nrow(tgt) || anyNA(panel)) stop("Stage 5: incomplete target/prediction panel.", call. = FALSE)

#===============================================================================
# 6. CHECKS ON THE FIT
#===============================================================================

rel_diff <- function(a, b) abs(a - b) / pmax(abs(b), 1)
chk <- list()
chk$identity_rerun_max_rel_diff <- factors[, max(rel_diff(id_joint_error, id_grid_error))]
if (chk$identity_rerun_max_rel_diff > cfg$score_tol)
  stop("Stage 5: the identity joint run does not reproduce its grid score (max rel. diff ",
       signif(chk$identity_rerun_max_rel_diff, 3), ").", call. = FALSE)
chk$selection_never_worse <- factors[, all(sel_error <= id_grid_error * (1 + cfg$score_tol))]
if (!chk$selection_never_worse) stop("Stage 5: a selected pair scores worse than the identity in the grid.", call. = FALSE)
chk$max_tied_pairs <- factors[, max(n_tied)]

#===============================================================================
# 7. APPLY THE SELECTED FACTORS ONCE TO EVERY HISTORICAL YEAR
#===============================================================================

out <- copy(rates)
out[, age_group := cal_band_of_age(age)]
out[factors, on = cal_key, `:=`(m_ir = i.ir_mult, m_cf = i.cf_mult)]
if (anyNA(out$m_ir) || anyNA(out$m_cf)) stop("Stage 5: historical rows without selected factors.", call. = FALSE)
out[, cap := cal_cap_of(BG.mx)]
out[, `:=`(IR_new = pmin(IR * m_ir, cap), CF_new = pmin(CF * m_cf, cap))]

# cap audit: where the probability rule binds, for uncalibrated (identity) and calibrated rates
out[, in_fit := year %in% cal_years]
cap_audit <- rbindlist(lapply(c("uncalibrated", "calibrated"), function(set_nm) {
  rbindlist(lapply(c("IR", "CF"), function(p) {
    raw <- if (set_nm == "uncalibrated") out[[p]] else out[[p]] * out[[if (p == "IR") "m_ir" else "m_cf"]]
    bind_cap  <- raw > out$cap & out$cap == cfg$tp_cap
    bind_feas <- raw > out$cap & out$cap <  cfg$tp_cap
    data.table(rates = set_nm, parameter = p,
               years = c(sprintf("%d-%d (fit)", cfg$fit_start, cfg$fit_end),
                         sprintf("%d-%d (all historical)", min(cfg$years_hist), max(cfg$years_hist))),
               n_cells = c(sum(out$in_fit), nrow(out)),
               n_capped_tp_cap = c(sum(bind_cap & out$in_fit), sum(bind_cap)),
               n_capped_feasibility = c(sum(bind_feas & out$in_fit), sum(bind_feas)))
  }))
}))
cap_audit[, share_capped := (n_capped_tp_cap + n_capped_feasibility) / n_cells]
cap_audit[, rule := sprintf("min(%.2f, 1 - BG.mx - %g)", cfg$tp_cap, cfg$feas_margin)]

out[, `:=`(IR = IR_new, CF = CF_new)]
out[, c("age_group", "m_ir", "m_cf", "cap", "IR_new", "CF_new", "in_fit") := NULL]
setcolorder(out, cal_rate_cols)
setorderv(out, c("location", "year", "sex", "cause", "age"))
if (any(out$IR + out$BG.mx > 1 - cfg$feas_margin + cfg$prob_tol) ||
    any(out$CF + out$BG.mx > 1 - cfg$feas_margin + cfg$prob_tol) ||
    any(out$IR > cfg$tp_cap + cfg$prob_tol) || any(out$CF > cfg$tp_cap + cfg$prob_tol) ||
    any(out$IR < 0) || any(out$CF < 0))
  stop("Stage 5: calibrated rates violate the probability rule.", call. = FALSE)
unchanged_cols <- setdiff(cal_rate_cols, c("IR", "CF"))
if (!isTRUE(all.equal(out[, ..unchanged_cols], rates[order(location, year, sex, cause, age), ..unchanged_cols],
                      check.attributes = FALSE)))
  stop("Stage 5: a non-calibrated column changed.", call. = FALSE)
rm(unchanged_cols)

#===============================================================================
# 8. RUN IDENTITY, FINGERPRINTS AND RESOLVED SETTINGS
#===============================================================================

in_files <- c(tps_files, cfg$target_file, cfg$pop_file)
fingerprints <- data.table(file = in_files, md5 = unname(tools::md5sum(in_files)),
                           bytes = file.size(in_files), modified = format(file.mtime(in_files), "%Y-%m-%d %H:%M:%S"))
tmp_sig <- tempfile(fileext = ".rds")
saveRDS(list(cfg, fingerprints$md5, cal_locs), tmp_sig)
cal_run_id <- paste0(format(cal_t0, "%Y%m%d-%H%M%S"), "-", substr(unname(tools::md5sum(tmp_sig)), 1, 8))
unlink(tmp_sig)

#===============================================================================
# 9. WRITE THE CALIBRATED HISTORICAL CHUNKS (staged, validated, then swapped in)
#===============================================================================

out_locs <- sort(unique(out$location))
n_chunks <- max(1L, min(cfg$n_out_chunks, length(out_locs)))
chunk_of <- if (n_chunks == 1L) rep(1L, length(out_locs)) else cut(seq_along(out_locs), breaks = n_chunks, labels = FALSE)
stage_dir <- file.path(cal_out_dir, paste0(".staging_", cal_run_id))
dir.create(stage_dir, showWarnings = FALSE)
for (i in seq_len(n_chunks)) {
  part <- out[location %in% out_locs[chunk_of == i]]
  setattr(part, "calibration_run_id", cal_run_id)
  saveRDS(part, file.path(stage_dir, paste0(cfg$out_stub, i, ".rds")))
}
staged <- sort(list.files(stage_dir, pattern = paste0("^", cfg$out_stub, "[0-9]+\\.rds$"), full.names = TRUE))
back <- rbindlist(lapply(staged, function(f) {
  d <- readRDS(f)
  if (!identical(attr(d, "calibration_run_id"), cal_run_id)) stop("Stage 5: staged chunk lacks the run id.", call. = FALSE)
  d
}), use.names = TRUE)
setorderv(back, c("location", "year", "sex", "cause", "age"))
if (length(staged) != n_chunks || anyDuplicated(back, by = c("location", "year", "sex", "cause", "age")) ||
    !isTRUE(all.equal(back, out, check.attributes = FALSE)) ||
    !identical(vapply(back, class, ""), vapply(rates[, ..cal_rate_cols], class, "")))
  stop("Stage 5: staged chunks failed validation; production chunks were left untouched.", call. = FALSE)
old <- list.files(cal_out_dir, pattern = paste0("^", cfg$out_stub, "[0-9]+\\.rds$"), full.names = TRUE)
if (length(old)) file.remove(old)
moved <- file.rename(staged, file.path(cal_out_dir, basename(staged)))
if (!all(moved)) stop("Stage 5: could not move staged chunks into ", cal_out_dir, call. = FALSE)
unlink(stage_dir, recursive = TRUE)
rm(back, staged, old, moved)
cat(sprintf("  Wrote %d chunk(s) %s<N>.rds to %s (run %s)\n", n_chunks, cfg$out_stub, cal_out_dir, cal_run_id))

#===============================================================================
# 10. REPRODUCE THE JOINT FIT FROM THE SAVED RATES
#===============================================================================

saved <- rbindlist(lapply(file.path(cal_out_dir, paste0(cfg$out_stub, seq_len(n_chunks), ".rds")), readRDS))
saved <- saved[year %in% cal_years, .(location, sex, cause, age, year, IR, CF, BG.mx, BG.mx.all, PREVt0, DIS.mx.t0)]
saved[pop, on = .(location, year, sex, age), Nx_seed := i.Nx_seed]
saved[, covid.mx := 0]
saved[, `:=`(IR = pmin(IR, cal_cap_of(BG.mx)), CF = pmin(CF, cal_cap_of(BG.mx)))]   # idempotent on saved rates
data.table::setDTthreads(0L)
repro <- cal_predict(saved, core)
repro <- repro[panel, on = c(cal_key, "year")]
chk$saved_rates_max_rel_diff <- repro[, max(rel_diff(pred_deaths, cal_deaths), rel_diff(pred_prev, cal_prev))]
if (chk$saved_rates_max_rel_diff > cfg$score_tol)
  stop("Stage 5: the saved rates do not reproduce the calibrated joint fit (max rel. diff ",
       signif(chk$saved_rates_max_rel_diff, 3), ").", call. = FALSE)
rm(saved, repro)

#===============================================================================
# 11. DIAGNOSTICS
#===============================================================================

lo_ir <- min(cfg$ir_grid); hi_ir <- max(cfg$ir_grid); lo_cf <- min(cfg$cf_grid); hi_cf <- max(cfg$cf_grid)
factors[, `:=`(ir_at_lower = abs(ir_mult - lo_ir) < 1e-12, ir_at_upper = abs(ir_mult - hi_ir) < 1e-12,
               cf_at_lower = abs(cf_mult - lo_cf) < 1e-12, cf_at_upper = abs(cf_mult - hi_cf) < 1e-12,
               is_identity = abs(ir_mult - 1) < 1e-12 & abs(cf_mult - 1) < 1e-12)]
cmp3 <- function(new, old, tol) fifelse(new < old * (1 - tol), "improved", fifelse(new > old * (1 + tol), "worsened", "unchanged"))
factors[, `:=`(selection_change = cmp3(sel_error, id_grid_error, cfg$score_tol),
               joint_change     = cmp3(joint_error, id_joint_error, cfg$score_tol))]
setcolorder(factors, c(cal_key, "ir_mult", "cf_mult", "is_identity", "ir_at_lower", "ir_at_upper",
                       "cf_at_lower", "cf_at_upper", "n_tied",
                       "id_grid_error", "id_grid_rmse_deaths", "id_grid_rmse_prev",
                       "sel_error", "sel_rmse_deaths", "sel_rmse_prev", "selection_change",
                       "id_joint_error", "id_joint_rmse_deaths", "id_joint_rmse_prev",
                       "joint_error", "joint_rmse_deaths", "joint_rmse_prev", "joint_change"))
fwrite(factors, file.path(cal_diag_dir, "calibration_factors.csv"))

# long target/prediction panel: observed, uncalibrated (identity) and calibrated counts
panel_long <- rbind(
  panel[, .(location, sex, cause, age_group, year, measure = "deaths",
            observed = obs_deaths, uncalibrated = uncal_deaths, calibrated = cal_deaths)],
  panel[, .(location, sex, cause, age_group, year, measure = "prevalence",
            observed = obs_prev, uncalibrated = uncal_prev, calibrated = cal_prev)])
panel_long[, seed_year := year == cfg$fit_start]
setkeyv(panel_long, c("measure", cal_key, "year"))
saveRDS(panel_long, file.path(cal_diag_dir, "calibration_fit_panel.rds"), compress = "xz")

# fit summaries (WAPE and aggregate bias; undefined when the observed total is 0)
fit_stats <- function(d, by) {
  d[, .(n_cells = .N, n_locations = uniqueN(location), observed = sum(observed),
        uncalibrated = sum(uncalibrated), calibrated = sum(calibrated),
        abs_err_uncal = sum(abs(uncalibrated - observed)), abs_err_cal = sum(abs(calibrated - observed))),
    keyby = by][
      , `:=`(wape_uncal = fifelse(observed > 0, abs_err_uncal / observed, NA_real_),
             wape_cal   = fifelse(observed > 0, abs_err_cal / observed, NA_real_),
             bias_uncal = fifelse(observed > 0, uncalibrated / observed - 1, NA_real_),
             bias_cal   = fifelse(observed > 0, calibrated / observed - 1, NA_real_))][]
}
fit_summary <- rbindlist(list(
  fit_stats(panel_long, "measure")[, `:=`(level = "overall", group = "All")],
  fit_stats(panel_long, c("measure", "cause"))[, `:=`(level = "cause", group = cause)][, cause := NULL],
  fit_stats(panel_long, c("measure", "sex"))[, `:=`(level = "sex", group = sex)][, sex := NULL],
  fit_stats(panel_long, c("measure", "age_group"))[, `:=`(level = "age_group", group = age_group)][, age_group := NULL],
  fit_stats(panel_long, c("measure", "location"))[, `:=`(level = "location", group = location)][, location := NULL]
), use.names = TRUE)
setcolorder(fit_summary, c("measure", "level", "group"))
fwrite(fit_summary, file.path(cal_diag_dir, "calibration_fit_summary.csv"))

obj_summary <- rbind(
  factors[, .(stage = "selection (grid minimum)", n_strata = .N,
              J_identity = sum(id_grid_error), J_new = sum(sel_error),
              n_improved = sum(selection_change == "improved"), n_unchanged = sum(selection_change == "unchanged"),
              n_worsened = sum(selection_change == "worsened"))],
  factors[, .(stage = "joint (all selected pairs together)", n_strata = .N,
              J_identity = sum(id_joint_error), J_new = sum(joint_error),
              n_improved = sum(joint_change == "improved"), n_unchanged = sum(joint_change == "unchanged"),
              n_worsened = sum(joint_change == "worsened"))])
obj_summary[, rel_change_J := J_new / J_identity - 1]
fwrite(obj_summary, file.path(cal_diag_dir, "calibration_objective_summary.csv"))

bounds <- factors[, .(n_strata = .N, n_identity = sum(is_identity),
                      n_ir_lower = sum(ir_at_lower), n_ir_upper = sum(ir_at_upper),
                      n_cf_lower = sum(cf_at_lower), n_cf_upper = sum(cf_at_upper),
                      n_any_bound = sum(ir_at_lower | ir_at_upper | cf_at_lower | cf_at_upper),
                      n_tied = sum(n_tied > 1L),
                      ir_median = median(ir_mult), ir_q1 = quantile(ir_mult, 0.25), ir_q3 = quantile(ir_mult, 0.75),
                      cf_median = median(cf_mult), cf_q1 = quantile(cf_mult, 0.25), cf_q3 = quantile(cf_mult, 0.75)),
                  keyby = .(cause)]
bounds <- rbind(bounds,
                factors[, .(cause = "All", n_strata = .N, n_identity = sum(is_identity),
                            n_ir_lower = sum(ir_at_lower), n_ir_upper = sum(ir_at_upper),
                            n_cf_lower = sum(cf_at_lower), n_cf_upper = sum(cf_at_upper),
                            n_any_bound = sum(ir_at_lower | ir_at_upper | cf_at_lower | cf_at_upper),
                            n_tied = sum(n_tied > 1L),
                            ir_median = median(ir_mult), ir_q1 = quantile(ir_mult, 0.25), ir_q3 = quantile(ir_mult, 0.75),
                            cf_median = median(cf_mult), cf_q1 = quantile(cf_mult, 0.25), cf_q3 = quantile(cf_mult, 0.75))])
fwrite(bounds, file.path(cal_diag_dir, "calibration_multiplier_summary.csv"))
fwrite(cap_audit, file.path(cal_diag_dir, "calibration_cap_audit.csv"))

chk$n_strata <- nrow(factors)
chk$n_target_cells <- nrow(tgt)
chk$n_seed_year_cells <- nrow(tgt[year == cfg$fit_start])
chk$open_age_seed_ratio <- open_ratio
chk$seed_population <- sprintf("UN-WPP single year (%s), ages >= %d summed into age %d", basename(cfg$pop_file),
                               cfg$open_age, cfg$open_age)
chk$n_workers <- n_workers
chk$n_location_groups <- n_groups
check_log <- data.table(check = names(chk), value = vapply(chk, function(v) format(v, digits = 6), ""))
fwrite(check_log, file.path(cal_diag_dir, "calibration_check_log.csv"))

settings <- list(
  run_id = cal_run_id, pilot = cal_pilot, started = format(cal_t0, "%Y-%m-%d %H:%M:%S %Z"),
  completed = format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z"),
  config = cfg, locations_calibrated = cal_locs,
  out_dir = normalizePath(cal_out_dir, winslash = "/"), diag_dir = normalizePath(cal_diag_dir, winslash = "/"),
  out_files = basename(file.path(cal_out_dir, paste0(cfg$out_stub, seq_len(n_chunks), ".rds"))),
  inputs = fingerprints, target = list(source = cfg$target_source, metric = cfg$target_metric,
                                       measures = cfg$target_measures, cells = nrow(tgt),
                                       zeros_deaths = tcov[, sum(deaths_zero)], zeros_prev = tcov[, sum(prev_zero)],
                                       missing = 0L),
  engine = "stage-7 project.all() recursion (age-20 entrants; open age not carried forward), keyed joins",
  checks = chk, objective = obj_summary, multipliers = bounds, cap_audit = cap_audit,
  r_version = R.version.string, data_table = as.character(packageVersion("data.table")),
  session = paste(capture.output(sessionInfo()), collapse = "\n"))
saveRDS(settings, file.path(cal_diag_dir, "calibration_settings.rds"))
flat <- data.table(
  setting = c("run_id", "pilot", "started", "completed", "target", "fit_window", "years_hist", "years_proj",
          "n_locations", "sexes", "causes", "ages", "age_bands", "ir_grid", "cf_grid", "n_pairs",
          "w_deaths", "w_prev", "tp_cap", "feasibility", "tie_rule", "tie_rel_tol", "score_tol",
          "seed_population", "engine", "out_dir", "out_stub", "n_chunks", "r_version"),
  value = c(cal_run_id, cal_pilot, settings$started, settings$completed,
            paste(cfg$target_source, cfg$target_metric, paste(cfg$target_measures, collapse = " + ")),
            paste0(cfg$fit_start, "-", cfg$fit_end), paste0(min(cfg$years_hist), "-", max(cfg$years_hist)),
            paste0(min(cfg$years_proj), "-", max(cfg$years_proj)), length(cal_locs),
            paste(cfg$sexes, collapse = ", "), paste(cfg$causes, collapse = ", "),
            paste0(min(cfg$ages), "-", max(cfg$ages)), paste(cfg$age_band_labels, collapse = ", "),
            paste(cfg$ir_grid, collapse = ", "), paste(cfg$cf_grid, collapse = ", "),
            length(cfg$ir_grid) * length(cfg$cf_grid), cfg$w_deaths, cfg$w_prev, cfg$tp_cap,
            sprintf("IR, CF <= min(tp_cap, 1 - BG.mx - %g)", cfg$feas_margin), cfg$tie_rule, cfg$tie_rel_tol,
            cfg$score_tol, chk$seed_population, settings$engine, settings$out_dir, cfg$out_stub, n_chunks,
            R.version.string))
fwrite(flat, file.path(cal_diag_dir, "calibration_settings.csv"))

#===============================================================================
# 12. CONSOLE SUMMARY
#===============================================================================

ov <- fit_summary[level == "overall"]
for (ms in c("deaths", "prevalence")) {
  r <- ov[measure == ms]
  cat(sprintf("  %-10s WAPE %.1f%% -> %.1f%% | bias %+.1f%% -> %+.1f%%\n", ms,
              100 * r$wape_uncal, 100 * r$wape_cal, 100 * r$bias_uncal, 100 * r$bias_cal))
}
cat(sprintf("  Objective (sum of J): selection %+.1f%%, joint %+.1f%% | joint: %d improved, %d unchanged, %d worsened of %d strata\n",
            100 * obj_summary$rel_change_J[1], 100 * obj_summary$rel_change_J[2],
            obj_summary$n_improved[2], obj_summary$n_unchanged[2], obj_summary$n_worsened[2], nrow(factors)))
cat(sprintf("  Boundaries: IR %.2f in %d, IR %.2f in %d, CF %.2f in %d, CF %.2f in %d strata | identity selected in %d\n",
            lo_ir, sum(factors$ir_at_lower), hi_ir, sum(factors$ir_at_upper), lo_cf, sum(factors$cf_at_lower),
            hi_cf, sum(factors$cf_at_upper), sum(factors$is_identity)))
cat(sprintf("  Checks: identity rerun %.1e, saved-rate rerun %.1e (tolerance %.0e)\n",
            chk$identity_rerun_max_rel_diff, chk$saved_rates_max_rel_diff, cfg$score_tol))
cat(sprintf("Stage 5 complete in %.1f min: calibrated HISTORICAL rates %d-%d in %s; diagnostics in %s\n",
            as.numeric(difftime(Sys.time(), cal_t0, units = "mins")), min(cfg$years_hist), max(cfg$years_hist),
            file.path(cal_out_dir, paste0(cfg$out_stub, "<N>.rds")), cal_diag_dir))

rm(rates, pop, tgt, base, out, panel, panel_long, factors, fit_summary, obj_summary, bounds, cap_audit,
   check_log, settings, flat, fingerprints, tcov, core, grp_of, strata_grid, ov, chk, in_files, lo_ir, hi_ir,
   lo_cf, hi_cf, n_chunks, chunk_of, out_locs, stage_dir, open_ratio, pop_dev, tps_files, n_groups, n_workers,
   t_grid, cmp3, rel_diff, fit_stats, cal_cap_of, cfg)
invisible(gc(FALSE))
