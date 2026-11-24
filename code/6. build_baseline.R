#===============================================================================
# code/6. build_baseline.R  --  Stage 6: projection panel for the stage-7 runner
#-------------------------------------------------------------------------------
# In : <cal_config$out_dir>/<cal_config$out_stub><N>.rds from stage 5: calibrated
#      HISTORICAL rates (cal_config$years_hist) carrying one calibration run id.
#      They are read only; nothing here rewrites them.
#      Projection inputs: wpp.adj.Rda (COVID excess mortality), UN-WPP 2024
#      populations, bp_data6.csv, covfxn2.csv, and the mortality trend selected by
#      trend_config$method: tps_mortality_coherent_forecasted.rds (default) or the legacy
#      tps_bgmx_*_forecasted.rds; tps_bgmx_cvd_ihme.rds for the IHME CF alternative.
# Out: in-memory objects consumed by the unchanged stage-7 runner:
#      b_rates (years stage7_first_year-2050: calibrated historical + projection years,
#      abbreviated causes, covid.mx), data.in, inc, bpcats, repYear; and baseline_settings
#      (method, trend files, accounting checks), which the master saves with the stage-7 run.
#      All checks below run on the full 2000-2050 panel before it is trimmed.
#
# Order (all prospective adjustments live here, never in the calibration):
#   1. read and validate the calibrated historical chunks
#   2. attach UN-WPP 2024 populations and age-20 cohorts
#   3. blood-pressure and coverage inputs
#   4. extend the terminal observed year's rates to the projection years, once
#   5. COVID-era excess mortality (2020-2021)
#   6. prospective secular trends, applied once to the projection years (default: the
#      coherent forecast rebuilds each country's DIS.mx.t0, BG.mx.all, ALL.mx and BG.mx
#      and moves CF by 80% of the cause's relative change; or legacy; or IHME CF)
#   7. final probability guards, after every rate modification, then verified
# No calibration factor is applied here: the legacy second pass that multiplied
# IR/CF by adjustments2023_age.csv (run_adjustment_model) is removed.
#===============================================================================

#...........................................................
#add covid mx data ----
#...........................................................

setwd(wd_raw)
load(paste0(wd,"wpp.adj.Rda"))

wpp.adj<-wpp.adj%>%
  mutate(location_name = ifelse(location_name=="North Korea", "Democratic People's Republic of Korea", location_name))
#Covid mx ~= excess mortality

# check for names as GBD and UWPP 2024
locs_wpp.adj <- unique(wpp.adj$location_name)

#...........................................................
# 1. Calibrated historical rates (stage 5) ----
#...........................................................

if (!exists("cal_config")) stop("Stage 6 needs cal_config from code/0. master.R.", call. = FALSE)
yr_obs   <- cal_config$obs_end       # terminal observed year (2019)
yrs_hist <- cal_config$years_hist
yrs_proj <- cal_config$years_proj

cal_settings_file <- file.path(cal_config$diag_dir, "calibration_settings.rds")
if (!file.exists(cal_settings_file)) stop("Stage 6: ", cal_settings_file, " not found; run stage 5 first.", call. = FALSE)
cal_settings <- readRDS(cal_settings_file)
if (isTRUE(cal_settings$pilot)) stop("Stage 6: the saved calibration settings describe a pilot run.", call. = FALSE)

# anchored pattern: only this stub's chunks, never other files containing "adjusted"
files <- sort(list.files(
  path       = cal_config$out_dir,
  pattern    = paste0("^", cal_config$out_stub, "[0-9]+\\.rds$"),
  full.names = TRUE
))
if (!length(files)) stop("Stage 6: no ", cal_config$out_stub, "<N>.rds in ", cal_config$out_dir, call. = FALSE)
if (!setequal(basename(files), cal_settings$out_files))
  stop("Stage 6: the calibrated chunks on disk differ from those listed in calibration_settings.rds.", call. = FALSE)

dt_list <- lapply(files, function(f) {
  dt <- readRDS(f)
  if (!identical(attr(dt, "calibration_run_id"), cal_settings$run_id))
    stop("Stage 6: ", basename(f), " does not carry calibration run ", cal_settings$run_id, call. = FALSE)
  setDT(dt)  # convert to data.table by reference if it isn't already
  dt
})

# Bind them all together, matching columns by name
b_rates <- rbindlist(dt_list, use.names = TRUE)

rm(dt_list, files)

hist_cols <- c("age", "sex", "location", "year", "cause", "BG.mx.all", "ALL.mx", "BG.mx",
               "PREVt0", "DIS.mx.t0", "Nx", "IR", "CF")
if (length(setdiff(hist_cols, names(b_rates))))
  stop("Stage 6: calibrated rates lack columns ", paste(setdiff(hist_cols, names(b_rates)), collapse = ", "), call. = FALSE)
if (!setequal(unique(b_rates$year), yrs_hist))
  stop("Stage 6: calibrated rates must cover exactly ", min(yrs_hist), "-", max(yrs_hist), call. = FALSE)
if (anyDuplicated(b_rates, by = c("location", "year", "sex", "age", "cause")))
  stop("Stage 6: duplicated keys in the calibrated rates.", call. = FALSE)
n_cells_hist <- uniqueN(b_rates$location) * length(cal_config$sexes) * length(cal_config$causes) * length(cal_config$ages)
if (nrow(b_rates) != n_cells_hist * length(yrs_hist))
  stop("Stage 6: the calibrated rates are not a complete location x year x sex x cause x age grid.", call. = FALSE)
if (anyNA(b_rates[, ..hist_cols])) stop("Stage 6: missing values in the calibrated rates.", call. = FALSE)

locs_b_rates <- unique(b_rates$location)
b_rates[location=="United States of America",location:="United States"]
b_rates[location=="Bolivia (Plurinational State of)",location:="Bolivia"]
b_rates[location=="United Republic of Tanzania",location:="Tanzania"]

b_rates <- b_rates[!is.na(location),]
b_rates[, intersect(c("percent_lag","percent_diff"), names(b_rates)) := NULL]

# Immutable reference: the saved calibrated IR/CF, checked again after every step below.
b_hist_ref <- b_rates[, .(location, year, sex, age, cause, IR_cal = IR, CF_cal = CF)]

# (The former left_join with wpp.adj here only added a covid.mx column that section 5
#  drops and re-merges before any use, so it is not repeated.)

# Update to UNWPP 2024
dt_pop_unwpp <- as.data.table(readRDS(paste0(wd_data,"UN2024/","PopulationsSingleAge0050.rds")))

dt_pop_unwpp[age>=95, age:= 95]

setnames(dt_pop_unwpp, c("year_id"), c("year"))

dt_pop_unwpp <- dt_pop_unwpp[, .(Nx = sum(Nx)), by = .(location, year, sex, age)]

b_rates <- merge(b_rates,
                 dt_pop_unwpp[, .(location,year,age,sex,Nx2=Nx)],
                 by = c("location", "year", "age","sex"),
                 all.x = TRUE
)

# replace Nx with Nx2
b_rates <- b_rates[, Nx := ifelse(is.na(Nx2), Nx, Nx2)]

b_rates[,Nx2 := NULL]

# temp: test ihme instead UNWPP

# dt_pop_ihme <- readRDS(file = paste0(wd_raw,"GBD/","totalpop_baseline_ihme.rds"))
#
# b_rates <- merge(b_rates,
#   dt_pop_ihme[, .(location,year,age,sex,Nx2=Nx)],
#   by = c("location", "year", "age","sex"),
#   all.x = TRUE
# )
#
# # replace Nx with Nx2
# b_rates <- b_rates[, Nx := ifelse(is.na(Nx2), Nx, Nx2)]
#
# b_rates[,Nx2 := NULL]


locs <- unique(b_rates$location)

#...........................................................
# Population data from UNWPP
pop20 <- read.csv(paste0(wd_data,"UN2024/","PopulationsAge20_2050.csv"), stringsAsFactors = F)

b_rates<-left_join(b_rates, pop20%>%rename(Nx2=Nx, year=year_id)%>%filter(year>=2017),
                   by=c("location", "year", "sex", "age"))%>%
  mutate(Nx = ifelse(is.na(Nx2), Nx, Nx2), pop=Nx)%>%
  select(-c(Nx2))
setDT(b_rates)

#...........................................................
# Blood Pressure data ----
# blood pressure data calculated in file: "Blood pressure.R"
#...........................................................

data.in<-fread(paste0(wd,"bp_data6.csv"))%>%rename(location = location_gbd)%>%select(-Year, -Country)
#data.in<-fread("bp_data3.csv")%>%select(-Year, -V1)%>%rename(Lower95 = Low95CI, Upper95 = High95CI)
#data.in<-left_join(data.in, names)
data.in$salt[data.in$location=="China"]<-4.83*2.54
length(unique(data.in$location))

#...........................................................
# HTN add scale-up data ----
#...........................................................

inc <- read.csv(paste0(wd_data,"covfxn2.csv"), stringsAsFactors = F)%>%
  select(iso3, location, Year, aroc, p_change, a_change, refwsalt, aspwsalt, reach_base,
         aroc2, p_change2, a_change2, ideal)

bpcats<-c("<120", "120-129", "130-139",
          "140-149", "150-159", "160-169",
          "170-179", "180+")

data.in<-merge(bpcats, data.in)%>%rename(bp_cat = x)

data.in <- as.data.table(data.in)
# Fixes location names

name_map <- c(
  "Brunei"                            = "Brunei Darussalam",
  "Cape Verde"                        = "Cabo Verde",
  "Cote d'Ivoire"                     = "Ivory Coast",
  "Czech Republic"                    = "Czechia",
  "Federated States of Micronesia"    = "Micronesia (Federated States of)",
  "Iran"                              = "Iran (Islamic Republic of)",
  "Laos"                              = "Lao People's Democratic Republic",
  "Macedonia"                         = "North Macedonia",
  "Moldova"                           = "Republic of Moldova",
  "South Korea"                       = "Republic of Korea",
  "Swaziland"                         = "Eswatini",
  "Syria"                             = "Syrian Arab Republic",
  "The Bahamas"                       = "Bahamas",
  "The Gambia"                        = "Gambia",
  "Venezuela"                         = "Venezuela (Bolivarian Republic of)",
  "Vietnam"                           = "Viet Nam",
  "North Korea"                       = "Democratic People's Republic of Korea"
)

# 3. update your data.in in place, using fcoalesce() so that
#    any location not in name_map stays unchanged
data.in[, location := fcoalesce(name_map[location], location)]

inc <- as.data.table(inc)
inc[, location := fcoalesce(name_map[location], location)]

unique(data.in$location)
any(is.na(data.in))

locs_data.in <- unique(data.in$location)

#...........................................................
###fxn ----
#...........................................................

repYear<-function(row){
  2017+floor((row-1)/224)
}

data.in<-data.table(data.in%>%select(-age)%>%rename(age=Age.group))
b_rates[, newcases:=0]

#...........................................................
# 4. Extend the terminal observed year to the projection years (once) ----
#...........................................................
##repeat rates for years 2020-2050 (cal_config$years_proj), from 2019 (cal_config$obs_end)

if (any(b_rates$year %in% yrs_proj)) stop("Stage 6: projection years already present before the extension.", call. = FALSE)
rep <- b_rates[year == yr_obs]
if (nrow(rep) != n_cells_hist) stop("Stage 6: the terminal observed year ", yr_obs, " is incomplete.", call. = FALSE)
b_rates <- rbindlist(c(list(b_rates), lapply(yrs_proj, function(i) copy(rep)[, year := i])), use.names = TRUE)
rm(rep)
if (anyDuplicated(b_rates, by = c("location", "year", "sex", "age", "cause")))
  stop("Stage 6: duplicated keys after extending to the projection years.", call. = FALSE)
if (nrow(b_rates) != n_cells_hist * (length(yrs_hist) + length(yrs_proj)))
  stop("Stage 6: incomplete grid after extending to the projection years.", call. = FALSE)

# rename causes to match abbreviated names
b_rates[,cause:=ifelse(cause=="Ischemic heart disease", "ihd",
                       ifelse(cause=="Ischemic stroke", "istroke",
                              ifelse(cause=="Intracerebral hemorrhage", "hstroke",
                                     ifelse(cause=="Hypertensive heart disease", "hhd",
                                            ifelse(cause=="Alzheimer's disease and other dementias", "aod",
                                                   cause)))))]
b_hist_ref[, cause := ifelse(cause=="Ischemic heart disease", "ihd",
                             ifelse(cause=="Ischemic stroke", "istroke",
                                    ifelse(cause=="Intracerebral hemorrhage", "hstroke",
                                           ifelse(cause=="Hypertensive heart disease", "hhd", cause))))]

# #...........................................................
# # Adjustments ----
# #...........................................................
# The legacy second calibration pass (run_adjustment_model: IR/CF multiplied by
# adjustments2023_age.csv) is removed. Stage 5 fits and applies the calibration once.

# #...........................................................
# # UNWPP 2024 Pop ----
# #...........................................................
# Adjust pop 20 to unwpp

b_rates<-left_join(b_rates, pop20%>%rename(Nx2=Nx, year=year_id)%>%filter(year>=2017),
                   by=c("location", "year", "sex", "age"))%>%
  mutate(Nx = ifelse(is.na(Nx2), Nx, Nx2), pop=Nx)%>%
  select(-c(Nx2))
setDT(b_rates)

# Testing Adjust Background mortality
# bg_diffs <- fread(file = paste0(wd,"bg_diffs.csv"))

# #...........................................................
# # 5. Covid 2020/2021 ----
# #...........................................................

if ("covid.mx" %in% names(b_rates)) b_rates[,covid.mx:=NULL]
b_rates <- merge(b_rates,wpp.adj[,c("location_name","year","sex","age","covid.mx"),with=F],
                 by.x=c("location","year","sex","age"),
                 by.y=c("location_name","year","sex","age"),all.x=T)

b_rates[is.na(covid.mx), covid.mx:=0]
b_rates[covid.mx>=1, covid.mx:=0.9]


#...........................................................
# 6. Prospective secular trends ----
#...........................................................
# trend_config (code/0. master.R) selects the method. Every projection row is still the
# copy of the terminal observed year made in section 4, so each cumulative factor below is
# applied once, to year > yr_obs only; the historical (calibrated) years are never trended,
# IR is never trended, and only one method's factors reach any column.

if (!exists("trend_config")) stop("Stage 6 needs trend_config from code/0. master.R.", call. = FALSE)
trend_method <- trend_config$method
cf_share     <- trend_config$cf_share
mx_tol       <- trend_config$rel_tol
cf_source <- if (!run_CF_trend) "none" else if (run_CF_trend_ihme) "GBD Foresight ASMR change (full)" else
  sprintf("%s cause trend x %.0f%%", trend_method, 100 * cf_share)
trend_files_used <- character(0)

# Historical mortality columns, to verify that no trend touches them.
b_hist_mx <- b_rates[year <= yr_obs, .(location, year, sex, age, cause, DIS_ref = DIS.mx.t0, ALL_ref = ALL.mx,
                                       BG_ref = BG.mx, BGA_ref = BG.mx.all)]
# Projection rows must start as exact copies of the terminal-year rates.
proj_start <- b_rates[year > yr_obs, .(location, sex, age, cause, year, DIS.mx.t0, ALL.mx, BG.mx, BG.mx.all, IR, CF)][
  b_rates[year == yr_obs, .(location, sex, age, cause, d0 = DIS.mx.t0, a0 = ALL.mx, b0 = BG.mx, g0 = BG.mx.all,
                            i0 = IR, c0 = CF)], on = .(location, sex, age, cause)]
if (nrow(proj_start) != n_cells_hist * length(yrs_proj) ||
    proj_start[, any(DIS.mx.t0 != d0 | ALL.mx != a0 | BG.mx != b0 | BG.mx.all != g0 | IR != i0 | CF != c0)])
  stop("Stage 6: projection rows do not start from the terminal observed year's rates.", call. = FALSE)
rm(proj_start)

## 6a. Coherent (default): Global reconciled 2019-relative changes applied to each
## country's own 2019 rates, with the country's totals rebuilt from its parts:
##   DIS[t]   = DIS[2019] * R_c[t]
##   OTHER[t] = (ALL[2019] - sum_c DIS[2019]) * R_other[t]
##   ALL[t]   = OTHER[t] + sum_c DIS[t];  BG.mx[t] = ALL[t] - DIS[t]
##   CF[t]    = CF[2019] * (1 + share * (R_c[t] - 1));  IR[t] = IR[2019]
coherent_trend <- NULL
dementia_gap <- NULL
if (trend_method == "coherent") {
  coh_file <- file.path(trend_config$out_dir, "tps_mortality_coherent_forecasted.rds")
  if (!file.exists(coh_file))
    stop("Stage 6: coherent forecast not found: ", coh_file, "; run stage 2 (trends) first.", call. = FALSE)
  trend_files_used <- coh_file
  coh_trend <- as.data.table(readRDS(coh_file))
  coh_trend_id <- attr(coh_trend, "trend_run_id")
  if (is.null(coh_trend_id)) stop("Stage 6: ", basename(coh_file), " carries no trend_run_id.", call. = FALSE)
  coh_need <- c("sex", "age", "year", "cause", "percent_diff_cvd", "percent_diff_bgmx_all")
  if (length(setdiff(coh_need, names(coh_trend))))
    stop("Stage 6: coherent forecast lacks ", paste(setdiff(coh_need, names(coh_trend)), collapse = ", "), call. = FALSE)
  if (!setequal(unique(coh_trend$cause), names(trend_config$causes)) ||
      anyDuplicated(coh_trend, by = c("sex", "age", "year", "cause")))
    stop("Stage 6: coherent forecast has unexpected causes or duplicated sex/age/year/cause rows.", call. = FALSE)
  n_trend_cells <- length(cal_config$sexes) * length(cal_config$ages) * length(trend_config$causes)
  if (coh_trend[year == yr_obs, .N] != n_trend_cells ||
      coh_trend[year == yr_obs, any(percent_diff_cvd != 0 | percent_diff_bgmx_all != 0)])
    stop("Stage 6: the coherent forecast's ", yr_obs, " change is missing or not zero.", call. = FALSE)
  coh_trend <- coh_trend[year > yr_obs, .(sex, age, year, cause, R_cvd = 1 + percent_diff_cvd,
                                          R_other = 1 + percent_diff_bgmx_all)]
  if (!setequal(unique(coh_trend$year), yrs_proj) || nrow(coh_trend) != n_trend_cells * length(yrs_proj) ||
      !setequal(unique(coh_trend$age), cal_config$ages) || !setequal(unique(coh_trend$sex), cal_config$sexes))
    stop("Stage 6: the coherent forecast does not cover every projected sex/age/year/cause.", call. = FALSE)
  if (coh_trend[, any(!is.finite(R_cvd) | !is.finite(R_other) | R_cvd < 0 | R_other < 0)])
    stop("Stage 6: invalid coherent trend factors.", call. = FALSE)
  if (coh_trend[, uniqueN(R_other), by = .(sex, age, year)][, any(V1 != 1L)])
    stop("Stage 6: the other-cause factor differs across cause rows.", call. = FALSE)

  # Each country's 2019 base: the all-cause rate once, the four causes summed, and other
  # causes as the residual (the calibrated BG.mx.all also subtracts dementia; see below).
  coh_base <- b_rates[year == yr_obs, .(ALL_base = ALL.mx[1L], ALL_spread = max(ALL.mx) - min(ALL.mx),
                                        cvd_base = sum(DIS.mx.t0), BGA_cal = BG.mx.all[1L], Nx = Nx[1L], n = .N),
                      by = .(location, sex, age)]
  if (coh_base[, any(n != length(trend_config$causes) | ALL_spread > mx_tol * ALL_base)])
    stop("Stage 6: ", yr_obs, " all-cause rates are incomplete or differ across cause rows.", call. = FALSE)
  coh_base[, other_base := ALL_base - cvd_base]
  if (coh_base[, any(other_base < 0)])
    stop("Stage 6: the four CVD rates exceed ALL.mx in ", coh_base[other_base < 0, .N], " ", yr_obs,
         " location/sex/age cells.", call. = FALSE)
  dementia_gap <- list(
    note = paste0("Calibrated BG.mx.all (stage 1 subtracts dementia too) vs ALL.mx - sum(4 CVD) in ", yr_obs,
                  "; the projection years use the residual, the historical years keep the calibrated column."),
    pct_of_deaths = coh_base[, 100 * sum(Nx * (other_base - BGA_cal)) / sum(Nx * ALL_base)],
    by_band = coh_base[, .(pct_of_all_deaths = 100 * sum(Nx * (other_base - BGA_cal)) / sum(Nx * ALL_base)),
                       keyby = .(sex, age_band = cut(age, c(19, 49, 69, 79, 89, 95)))])

  b_rates <- merge(b_rates, coh_trend, by = c("sex", "age", "year", "cause"), all.x = TRUE)
  b_rates <- merge(b_rates, coh_base[, .(location, sex, age, other_base)], by = c("location", "sex", "age"), all.x = TRUE)
  if (b_rates[year > yr_obs, anyNA(R_cvd) || anyNA(R_other) || anyNA(other_base)])
    stop("Stage 6: projected rows without a coherent trend factor or 2019 base.", call. = FALSE)
  mx_on <- isTRUE(run_bgmx_trend)   # off: the projection keeps the 2019 rates, rebuilt the same way
  b_rates[year > yr_obs, `:=`(DIS.mx.t0 = DIS.mx.t0 * (if (mx_on) R_cvd else 1),
                              BG.mx.all = other_base * (if (mx_on) R_other else 1))]
  b_rates[year > yr_obs, ALL.mx := BG.mx.all + sum(DIS.mx.t0), by = .(location, sex, age, year)]
  b_rates[year > yr_obs, BG.mx := ALL.mx - DIS.mx.t0]
  if (run_CF_trend && !run_CF_trend_ihme) b_rates[year > yr_obs, CF := CF * (1 + cf_share * (R_cvd - 1))]

  # Each factor applied once: every projected rate equals its 2019 rate times that year's factor.
  once <- b_rates[year > yr_obs, .(location, sex, age, cause, year, DIS.mx.t0, CF, R_cvd)][
    b_rates[year == yr_obs, .(location, sex, age, cause, d0 = DIS.mx.t0, c0 = CF)], on = .(location, sex, age, cause)]
  coherent_trend <- list(
    trend_run_id = coh_trend_id, mortality_trended = mx_on,
    max_rel_err_dis = once[d0 > 0, max(abs(DIS.mx.t0 / d0 - (if (mx_on) R_cvd else 1)))],
    max_rel_err_cf = if (run_CF_trend && !run_CF_trend_ihme)
      once[c0 > 0, max(abs(CF / c0 - (1 + cf_share * (R_cvd - 1))))] else NA_real_)
  if (coherent_trend$max_rel_err_dis > 1e-12 ||
      (!is.na(coherent_trend$max_rel_err_cf) && coherent_trend$max_rel_err_cf > 1e-12))
    stop("Stage 6: projected rates are not the 2019 rates times one cumulative factor.", call. = FALSE)
  b_rates[, c("R_cvd", "R_other", "other_base") := NULL]
  rm(coh_trend, coh_base, once)
}

## 6b. Legacy: independent Global Lee-Carter changes applied to BG.mx, BG.mx.all and CF.
if (trend_method == "legacy" && run_bgmx_trend) {

  trend_files_used <- c(trend_files_used, paste0(wd_data, c("tps_bgmx_forecasted.rds", "tps_bgmx_all_forecasted.rds")))
  bgmx_fcst <- readRDS(file = paste0(wd_data,"tps_bgmx_forecasted.rds"))

  bgmx_fcst[, intersect("BG.mx.all", names(bgmx_fcst)) := NULL]

  bgmx_fcst <- bgmx_fcst[year>yr_obs,]

  bgmx_fcst <- unique(bgmx_fcst,by=c("age","sex","cause","year"))

  bgmx_fcst[, cause := fcase(
    cause == "Ischemic heart disease", "ihd",
    cause == "Ischemic stroke", "istroke",
    cause == "Intracerebral hemorrhage", "hstroke",
    cause == "Hypertensive heart disease", "hhd",
    cause == "Alzheimer's disease and other dementias", "aod",
    default = cause
  )]

  summary(b_rates$BG.mx)

  b_rates <- merge(b_rates,bgmx_fcst,,by=c("age","sex","cause","year"),all.x = T)

  b_rates[year>yr_obs & !is.na(percent_diff),BG.mx:=BG.mx*(1+percent_diff)]
  b_rates[,c("percent_lag","percent_diff"):=NULL]

  summary(b_rates$BG.mx)

  # All dead envelope
  bgmx_fcst <- readRDS(file = paste0(wd_data,"tps_bgmx_all_forecasted.rds"))

  bgmx_fcst <- bgmx_fcst[year>yr_obs,]

  bgmx_fcst[, intersect("BG.mx.all", names(bgmx_fcst)) := NULL]

  bgmx_fcst <- unique(bgmx_fcst,by=c("age","sex","cause","year"))

  bgmx_fcst[, cause := fcase(
    cause == "Ischemic heart disease", "ihd",
    cause == "Ischemic stroke", "istroke",
    cause == "Intracerebral hemorrhage", "hstroke",
    cause == "Hypertensive heart disease", "hhd",
    cause == "Alzheimer's disease and other dementias", "aod",
    default = cause
  )]

  summary(b_rates$BG.mx.all)

  b_rates <- merge(b_rates,bgmx_fcst,by=c("age","sex","cause","year"),all.x = T)

  b_rates[year>yr_obs & !is.na(percent_diff),BG.mx.all:=BG.mx.all*(1+percent_diff)]
  b_rates[,c("percent_lag","percent_diff"):=NULL]

  summary(b_rates$BG.mx.all)
}

## 6c. CF alternative for either method: GBD Foresight age-standardised CVD change (full change).
if (run_CF_trend && run_CF_trend_ihme) {

    trend_files_used <- c(trend_files_used, paste0(wd_data, "tps_bgmx_cvd_ihme.rds"))
    bgmx_fcst <- readRDS(file = paste0(wd_data,"tps_bgmx_cvd_ihme.rds"))

    bgmx_fcst <- bgmx_fcst[year>yr_obs,]

    bgmx_fcst <- unique(bgmx_fcst,by=c("cause","year"))

    b_rates <- merge(b_rates,bgmx_fcst,by=c("cause","year"),all.x = T)

    b_rates[year>yr_obs & !is.na(percent_diff),CF:=CF*(1+percent_diff)]
    b_rates[,c("percent_diff"):=NULL]

}

## 6d. Legacy CF trend: independent Global LC change in the CVD death rate x cf_share.
if (trend_method == "legacy" && run_CF_trend && !run_CF_trend_ihme) {

    trend_files_used <- c(trend_files_used, paste0(wd_data, "tps_bgmx_cvd_forecasted.rds"))
    bgmx_fcst <- readRDS(file = paste0(wd_data,"tps_bgmx_cvd_forecasted.rds"))

    bgmx_fcst <- bgmx_fcst[year>yr_obs,]

    bgmx_fcst[, intersect("BG.mx.all", names(bgmx_fcst)) := NULL]

    bgmx_fcst <- unique(bgmx_fcst,by=c("age","sex","cause","year"))

    bgmx_fcst[, cause := fcase(
      cause == "Ischemic heart disease", "ihd",
      cause == "Ischemic stroke", "istroke",
      cause == "Intracerebral hemorrhage", "hstroke",
      cause == "Hypertensive heart disease", "hhd",
      cause == "Alzheimer's disease and other dementias", "aod",
      default = cause
    )]


    b_rates <- merge(b_rates,bgmx_fcst,by=c("age","sex","cause","year"),all.x = T)

    b_rates[year>yr_obs & !is.na(percent_diff),CF:=CF*(1+percent_diff*cf_share)]

    b_rates[,c("percent_lag","percent_diff"):=NULL]

}

## 6e. Accounting checks on the projected rates, before the final guard.
# Historical mortality columns are untouched by any trend.
hist_mx_chk <- b_hist_mx[b_rates[year <= yr_obs], on = .(location, year, sex, age, cause), nomatch = NULL]
if (nrow(hist_mx_chk) != nrow(b_hist_mx) ||
    hist_mx_chk[, any(DIS.mx.t0 != DIS_ref | ALL.mx != ALL_ref | BG.mx != BG_ref | BG.mx.all != BGA_ref)])
  stop("Stage 6: a trend changed the historical mortality rates.", call. = FALSE)
rm(hist_mx_chk)
# Per location/sex/age/year: one all-cause and one other-cause rate across the cause rows,
# ALL = other + sum of the four causes, and BG.mx = ALL - DIS on every cause row.
mx_accounting <- function(dt) {
  a <- dt[year > yr_obs, .(all_spread = (max(ALL.mx) - min(ALL.mx)) / ALL.mx[1L],
                           other_spread = (max(BG.mx.all) - min(BG.mx.all)) / ALL.mx[1L],
                           total_gap = abs(ALL.mx[1L] - BG.mx.all[1L] - sum(DIS.mx.t0)) / ALL.mx[1L],
                           bg_gap = max(abs(BG.mx - (ALL.mx - DIS.mx.t0))) / ALL.mx[1L]),
          by = .(location, sex, age, year)]
  list(cells = nrow(a), n_all_spread = a[all_spread > mx_tol, .N], n_other_spread = a[other_spread > mx_tol, .N],
       n_total_gap = a[total_gap > mx_tol, .N], n_bg_gap = a[bg_gap > mx_tol, .N],
       max_total_gap = a[, max(total_gap)], max_bg_gap = a[, max(bg_gap)],
       bg_gap_by_year = a[bg_gap > mx_tol, .(cells = .N), keyby = year])
}
mx_check_pre <- mx_accounting(b_rates)
cat(sprintf("Stage 6 trends (%s): projected mortality accounting before the guard: %d of %d cells break ALL = other + sum(CVD), %d break BG.mx = ALL - DIS\n",
            trend_method, mx_check_pre$n_total_gap, mx_check_pre$cells, mx_check_pre$n_bg_gap))
if (trend_method == "coherent" &&
    (mx_check_pre$n_all_spread + mx_check_pre$n_other_spread + mx_check_pre$n_total_gap + mx_check_pre$n_bg_gap > 0))
  stop("Stage 6: the coherent projection breaks the country mortality accounting before the guard.", call. = FALSE)
if (b_rates[year > yr_obs, any(!is.finite(DIS.mx.t0) | DIS.mx.t0 < 0 | !is.finite(BG.mx.all) | BG.mx.all < 0 |
                                 !is.finite(ALL.mx) | !is.finite(BG.mx) | BG.mx < 0 | !is.finite(CF) | CF < 0)])
  stop("Stage 6: invalid projected mortality or CF after the trends.", call. = FALSE)

#...........................................................
# 7. Final probability guards (after every rate modification) ----
#...........................................................
# Moved here from before the extension, where it ran on covid.mx = NA (so never
# changed a row) and before the trends and the COVID merge. Same purpose:
# rebalance TPs w/ covid such that they sum to at most 1
# especially @ old ages where covid deaths are high.
# covid.mx is the excess mortality applied to the population the four cause models
# share (stage 7 adds pop*covid.mx to all.mx on every cause row), so it must stay
# identical across causes. The former per-row formula also scaled covid.mx, which
# would give each cause model a different population once the guard is active.
# So: (1) the shared envelope first, covid.mx <= 1 - BG.mx.all (the shared-pool form of
# the former first step "ensure that background mortality + covid < 1"); then
# (2) covid.mx is kept and the cause-specific rates are reduced proportionally:
#   IR + BG.mx + covid.mx > 1  ->  IR, BG.mx  *= (1 - covid.mx) / (IR + BG.mx)
#   CF + BG.mx + covid.mx > 1  ->  CF, BG.mx  *= (1 - covid.mx) / (CF + BG.mx)
# (sick-state check recomputed after the well step), so each sum is at most 1.

guard_tol <- cal_config$prob_tol
b_rates[,check_well := BG.mx+covid.mx+IR]
b_rates[,check_sick := BG.mx+covid.mx+CF]
guard_log <- b_rates[, .(n_rows = .N, n_bgall_covid_gt1 = sum(BG.mx.all + covid.mx > 1),
                         n_well_gt1 = sum(check_well > 1), n_sick_gt1 = sum(check_sick > 1)),
                     keyby = .(period = fifelse(year <= yr_obs, "historical", "projection"))]
guard_rows <- b_rates[check_well > 1 | check_sick > 1 | BG.mx.all + covid.mx > 1, .N,
                      keyby = .(year, cause, age_band = cut(age, c(19, 69, 79, 89, 95)))]

#first ensure that background mortality + covid <= 1 on the shared population
b_rates[BG.mx.all + covid.mx > 1, covid.mx := 1 - BG.mx.all]
b_rates[,check_well := BG.mx+covid.mx+IR]
b_rates[,check_sick := BG.mx+covid.mx+CF]

#proportionally reduce the cause-specific rates by check_well
b_rates[, f_guard := fifelse(check_well > 1, (1 - covid.mx) / (BG.mx + IR), 1)]
b_rates[, `:=`(BG.mx = BG.mx * f_guard, IR = IR * f_guard)]

#same process for check_sick (recomputed after the well step)
b_rates[,check_sick := BG.mx+covid.mx+CF]
b_rates[, f_guard := fifelse(check_sick > 1, (1 - covid.mx) / (BG.mx + CF), 1)]
b_rates[, `:=`(BG.mx = BG.mx * f_guard, CF = CF * f_guard)]
b_rates[, f_guard := NULL]

b_rates[,check_well := BG.mx+covid.mx+IR]
b_rates[,check_sick := BG.mx+covid.mx+CF]
if (b_rates[, uniqueN(covid.mx), by = .(location, year, sex, age)][, any(V1 != 1)] ||
    b_rates[, uniqueN(BG.mx.all) + uniqueN(Nx), by = .(location, year, sex, age)][, any(V1 != 2)])
  stop("Stage 6: covid.mx, BG.mx.all or Nx differ across the four cause rows (shared population).", call. = FALSE)

# verify the constraints and the shared all-cause envelope
prob_cols <- c("IR", "CF", "BG.mx", "BG.mx.all", "covid.mx")
for (v in prob_cols) {
  if (any(!is.finite(b_rates[[v]])) || any(b_rates[[v]] < 0) || any(b_rates[[v]] > 1 + guard_tol))
    stop("Stage 6: ", v, " outside [0, 1] after the final guard.", call. = FALSE)
}
if (b_rates[, any(check_well > 1 + guard_tol) || any(check_sick > 1 + guard_tol)])
  stop("Stage 6: IR + BG.mx + covid.mx or CF + BG.mx + covid.mx exceeds 1 after the final guard.", call. = FALSE)
#check that no BG.mx.all+covid>1
if (b_rates[, any(covid.mx + BG.mx.all > 1 + guard_tol)])
  stop("Stage 6: BG.mx.all + covid.mx exceeds 1 after the final guard.", call. = FALSE)
b_rates[, c("check_well", "check_sick") := NULL]
print(guard_log)
cat("Rows changed by the final guard, by year (projection only):\n")
print(guard_rows[, .(rows = sum(N)), keyby = year])

# The guard rescales BG.mx (with IR or CF) where the exits would exceed one; it never
# changes DIS.mx.t0, ALL.mx or BG.mx.all. Report where it breaks BG.mx = ALL - DIS.
mx_check_post <- mx_accounting(b_rates)
cat(sprintf("Stage 6 trends (%s): after the guard: %d of %d projected cells break ALL = other + sum(CVD), %d break BG.mx = ALL - DIS (max relative gap %.3g)\n",
            trend_method, mx_check_post$n_total_gap, mx_check_post$cells, mx_check_post$n_bg_gap, mx_check_post$max_bg_gap))
if (nrow(mx_check_post$bg_gap_by_year)) print(mx_check_post$bg_gap_by_year)
if (trend_method == "coherent" &&
    (mx_check_post$n_all_spread + mx_check_post$n_other_spread + mx_check_post$n_total_gap > 0))
  stop("Stage 6: the final guard changed the shared all-cause or other-cause rates.", call. = FALSE)

# the calibrated historical IR/CF reach stage 7 exactly as saved by stage 5
hist_chk <- b_hist_ref[b_rates[year <= yr_obs], on = .(location, year, sex, age, cause), nomatch = NULL]
if (nrow(hist_chk) != nrow(b_hist_ref) ||
    hist_chk[, max(abs(IR - IR_cal), abs(CF - CF_cal))] > guard_tol)
  stop("Stage 6: historical IR/CF differ from the calibrated rates saved by stage 5.", call. = FALSE)

# final grid and the columns stage 7 reads
if (anyDuplicated(b_rates, by = c("location", "year", "sex", "age", "cause")))
  stop("Stage 6: duplicated keys in the projection panel.", call. = FALSE)
if (nrow(b_rates) != n_cells_hist * (length(yrs_hist) + length(yrs_proj)))
  stop("Stage 6: incomplete projection panel.", call. = FALSE)
runner_cols <- c("age", "sex", "location", "year", "cause", "IR", "CF", "BG.mx", "BG.mx.all", "PREVt0",
                 "DIS.mx.t0", "Nx", "pop", "covid.mx", "newcases")
if (length(setdiff(runner_cols, names(b_rates))))
  stop("Stage 6: b_rates lacks columns for stage 7: ", paste(setdiff(runner_cols, names(b_rates)), collapse = ", "),
       call. = FALSE)
for (obj in c("data.in", "inc", "bpcats", "repYear")) {
  if (!exists(obj)) stop("Stage 6: stage-7 input object ", obj, " was not created.", call. = FALSE)
}
#...........................................................
# 8. Hand stage 7 only the years it reads ----
#...........................................................
# project.all() reads b_rates[location == Country & year>= <first year>] and nothing earlier;
# confirm the year in the stage-7 code, then drop earlier rows and large temporaries so the
# eight parallel workers (each receiving b_rates) stay within memory. Projections are unchanged.
s7_txt <- readLines(paste0(wd_code, "7. model_100_multiplicative_func_new3_gbd23_noaroc.R"), warn = FALSE)
s7_hit <- regmatches(s7_txt, regexpr("b_rates\\[location == Country & year *>= *[0-9]{4}\\]", s7_txt))
s7_year <- unique(as.integer(sub(".*>= *([0-9]{4})\\]$", "\\1", s7_hit)))
if (!exists("stage7_first_year") || length(s7_year) != 1L || s7_year != stage7_first_year)
  stop("Stage 6: stage7_first_year (code/0. master.R) does not match the year stage 7 reads from b_rates.", call. = FALSE)
n_full <- nrow(b_rates)
b_rates <- b_rates[year >= stage7_first_year]

# Settings and checks of this baseline, kept in memory; code/0. master.R saves them with the
# stage-7 outputs (output/out_model/model_run_manifest.rds).
baseline_settings <- list(
  built = format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z"), calibration_run_id = cal_settings$run_id,
  trend_method = trend_method, run_bgmx_trend = run_bgmx_trend, run_CF_trend = run_CF_trend,
  run_CF_trend_80 = run_CF_trend_80, run_CF_trend_ihme = run_CF_trend_ihme, cf_share = cf_share, cf_source = cf_source,
  trend_files = data.table(file = basename(trend_files_used), md5 = unname(tools::md5sum(trend_files_used)),
                           mtime = format(file.mtime(trend_files_used), "%Y-%m-%d %H:%M:%S")),
  trend_run_id = if (is.null(coherent_trend)) NA_character_ else coherent_trend$trend_run_id,
  coherent_trend = coherent_trend, dementia_gap = dementia_gap,
  accounting_before_guard = mx_check_pre, accounting_after_guard = mx_check_post,
  guard_log = guard_log, stage7_first_year = stage7_first_year, n_locations = uniqueN(b_rates$location),
  years = range(b_rates$year))
baseline_settings$baseline_id <- local({
  f <- tempfile(); on.exit(unlink(f))
  writeLines(paste(c(cal_settings$run_id, baseline_settings$trend_files$md5, trend_method, cf_share,
                     run_bgmx_trend, run_CF_trend, run_CF_trend_ihme), collapse = "|"), f)
  paste0(format(Sys.time(), "%Y%m%d-%H%M%S"), "-", substr(unname(tools::md5sum(f)), 1, 8))
})
rm(dt_pop_unwpp, pop20, wpp.adj, guard_rows, s7_txt, s7_hit, s7_year)
invisible(gc(FALSE))

cat(sprintf("Stage 6 complete: b_rates %d rows (of %d; years %d-%d passed to stage 7), %d locations (calibration run %s; trends %s, CF %s; baseline %s)\n",
            nrow(b_rates), n_full, min(b_rates$year), max(b_rates$year), uniqueN(b_rates$location), cal_settings$run_id,
            trend_method, cf_source, baseline_settings$baseline_id))
rm(hist_chk, b_hist_ref, b_hist_mx, prob_cols, runner_cols, obj, v, n_cells_hist, hist_cols, guard_tol, n_full,
   mx_accounting, mx_check_pre, mx_check_post, coherent_trend, dementia_gap, trend_files_used)
