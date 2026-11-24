#===============================================================================
# code/2. get_tps_bgmx_100_gbd23.R  --  Stage 2 (trends): prospective mortality trends
#-------------------------------------------------------------------------------
# In : <trend_config$tps_dir>/tps_inpt_part<N>.rds (anchored pattern; written by
#      "2. get_tps_100_gbd23.R"): GBD 2023 rates for 2000-2019 by location, sex,
#      single age 20-95 (row 95 = 95+) and the four modelled CVD causes, with UN-WPP
#      2024 populations (Nx).
#      trend_config$pop_file: UN-WPP 2024 single-age populations (95+ weights).
#      trend_config$ihme_dir: GBD Foresight age-standardised CVD rates (IHME alternative).
# Out (all in trend_config$out_dir):
#   Default method (trend_config$method = "coherent"), read by stage 6:
#     tps_mortality_coherent_forecasted.rds   Global rates 2000-2050 by sex x age x year x
#        cause: observed 2000-2019, reconciled forecast 2020-2050, and cumulative changes
#        relative to the observed 2019 rate of each series.
#     tps_mortality_coherent_validation.rds   2016-2019 holdout errors by sex x series,
#        unreconciled (base) vs reconciled.
#     tps_mortality_coherent_diagnostics.rds  metadata (inputs, scope, windows, method,
#        run id), cell-level holdout, unreconciled production forecasts, LC/ETS and
#        covariance diagnostics.
#   Alternatives kept for trend_config$method = "legacy" and run_CF_trend_ihme:
#     tps_bgmx_forecasted.rds, tps_bgmx_all_forecasted.rds, tps_bgmx_cvd_forecasted.rds
#        (independent Lee-Carter forecasts of BG.mx, BG.mx.all and DIS.mx.t0), and
#     tps_bgmx_cvd_ihme.rds (GBD Foresight CVD age-standardised rate changes).
#
# Coherent method: an adaptation of the forecast-reconciliation approach of Li, Li, Lu
# and Panagiotelis (2019), Insurance: Mathematics and Economics 86:122-133,
# doi:10.1016/j.insmatheco.2019.02.011, following the implementation in the WHO CVD
# project (023_get_tps_bgmx.R). For each sex, every series in the hierarchy
#     ALL.mx = ihd + istroke + hstroke + hhd + BG.mx.all
# gets a Lee-Carter base forecast (SVD; k_t extrapolated with damped additive-trend
# exponential smoothing), and the six base forecasts are reconciled on the rate scale,
# by sex and single age, with the constraint form of the minimum-trace projection.
# The error covariance W is approximated from in-sample LC fitted-value residuals
# (the reference implementation's choice; it is not a rolling forecast-error estimate).
#===============================================================================

if (!exists("trend_config")) stop("Stage 2 (trends) needs trend_config from code/0. master.R.", call. = FALSE)
tcfg <- trend_config
trend_t0 <- Sys.time()

#...........................................................
# 0. Inputs (shared by every method) ----
#...........................................................
# Anchored pattern: only the historical input chunks, never the trend files this
# script writes to the same folder (the former pattern "tps" also matched those).
tps_files <- sort(list.files(tcfg$tps_dir, pattern = tcfg$tps_pattern, full.names = TRUE))
if (!length(tps_files)) stop("Stage 2 (trends): no files match ", tcfg$tps_pattern, " in ", tcfg$tps_dir, call. = FALSE)
tps <- rbindlist(lapply(tps_files, function(f) as.data.table(readRDS(f))), use.names = TRUE)
tps_need <- c("location", "sex", "year", "age", "cause", "Nx", "ALL.mx", "DIS.mx.t0", "BG.mx", "BG.mx.all")
if (length(setdiff(tps_need, names(tps))))
  stop("Stage 2 (trends): tps_inpt lacks columns ", paste(setdiff(tps_need, names(tps)), collapse = ", "), call. = FALSE)
tps[, `:=`(year = as.integer(year), age = as.integer(age), cause = trimws(as.character(cause)))]

#...........................................................
# 1. Coherent all-cause / CVD-cause / other-cause forecast (default) ----
#...........................................................

coh_cvd        <- names(tcfg$causes)                       # ihd, istroke, hstroke, hhd
coh_bottom     <- c(coh_cvd, "BG.mx.all")
coh_components <- c("ALL.mx", coh_bottom)                  # hierarchy order
coh_keys       <- c("location", "sex", "year", "age")
coh_ages       <- as.integer(tcfg$ages)
coh_years      <- as.integer(tcfg$years_hist)
coh_anchor     <- as.integer(tcfg$anchor_year)
coh_train_end  <- as.integer(tcfg$training_end)
coh_holdout    <- (coh_train_end + 1L):max(coh_years)
coh_until      <- as.integer(tcfg$forecast_end)
coh_tol        <- tcfg$rel_tol
if (coh_anchor != max(coh_years)) stop("Stage 2 (trends): anchor_year must be the last historical year.", call. = FALSE)
if (!(min(coh_years) < coh_train_end && coh_train_end < max(coh_years)))
  stop("Stage 2 (trends): training_end must fall inside years_hist.", call. = FALSE)

## 1a. Cause labels and scope ----
coh_cause_lookup <- c(setNames(coh_cvd, unname(tcfg$causes)), setNames(coh_cvd, coh_cvd))
ci <- tps[, c(coh_keys, "cause", "Nx", "ALL.mx", "DIS.mx.t0", "BG.mx", "BG.mx.all"), with = FALSE]
coh_unknown <- setdiff(unique(ci$cause), names(coh_cause_lookup))
if (length(coh_unknown))
  stop("Stage 2 (trends): unexpected causes in tps_inpt (", paste(coh_unknown, collapse = "; "),
       "); the hierarchy expects the four modelled CVD causes only.", call. = FALSE)
ci[, cause := unname(coh_cause_lookup[cause])]
if (!setequal(unique(ci$cause), coh_cvd))
  stop("Stage 2 (trends): tps_inpt does not contain all four modelled CVD causes.", call. = FALSE)
coh_n_global_rows <- ci[location == "Global", .N]
if (coh_n_global_rows) {
  message("Stage 2 (trends): dropping ", coh_n_global_rows, " pre-aggregated Global rows from tps_inpt.")
  ci <- ci[location != "Global"]
}
if (!setequal(unique(ci$year), coh_years) || !setequal(unique(ci$age), coh_ages) ||
    !setequal(unique(ci$sex), tcfg$sexes))
  stop("Stage 2 (trends): tps_inpt years, ages or sexes differ from trend_config.", call. = FALSE)

## 1b. Input checks. Nothing is imputed; an incomplete location stops the run rather
## than being dropped (which would change the Global country mix between years).
coh_bad <- ci[, lapply(.SD, function(v) sum(!is.finite(v) | v < 0)),
              .SDcols = c("Nx", "ALL.mx", "DIS.mx.t0", "BG.mx", "BG.mx.all")]
if (any(unlist(coh_bad) > 0L))
  stop("Stage 2 (trends): missing, non-finite or negative inputs (rows): ",
       paste(names(coh_bad), unlist(coh_bad), sep = " = ", collapse = ", "), call. = FALSE)
if (anyDuplicated(ci, by = c(coh_keys, "cause")))
  stop("Stage 2 (trends): duplicated location/sex/year/age/cause rows in tps_inpt.", call. = FALSE)
coh_n_grid <- length(tcfg$sexes) * length(coh_years) * length(coh_ages) * length(coh_cvd)
coh_incomplete <- ci[, .N, by = location][N != coh_n_grid, location]
if (length(coh_incomplete))
  stop("Stage 2 (trends): incomplete sex/year/age/cause grid for ", paste(coh_incomplete, collapse = ", "), call. = FALSE)
coh_spread <- ci[, .(ALL = max(ALL.mx) - min(ALL.mx), Nx = max(Nx) - min(Nx)), by = coh_keys][ALL > 0 | Nx > 0]
if (nrow(coh_spread))
  stop("Stage 2 (trends): Nx or ALL.mx differ across cause rows in ", nrow(coh_spread), " cells.", call. = FALSE)
coh_bg_mismatch <- ci[abs(BG.mx + DIS.mx.t0 - ALL.mx) > coh_tol * ALL.mx, .N]
if (coh_bg_mismatch)
  stop("Stage 2 (trends): BG.mx != ALL.mx - DIS.mx.t0 in ", coh_bg_mismatch,
       " rows, so DIS.mx.t0 is not a population death rate.", call. = FALSE)

## 1c. One row per location/sex/year/age: the common Nx and ALL.mx once, the four
## cause rates side by side, and other-cause mortality as the residual.
coh_loc <- dcast(ci, location + sex + year + age ~ cause, value.var = "DIS.mx.t0")
coh_loc <- merge(coh_loc, unique(ci[, c(coh_keys, "Nx", "ALL.mx", "BG.mx.all"), with = FALSE]), by = coh_keys)
if (nrow(coh_loc) != uniqueN(ci$location) * coh_n_grid / length(coh_cvd))
  stop("Stage 2 (trends): cause rows did not collapse to one row per location/sex/year/age.", call. = FALSE)
setnames(coh_loc, "BG.mx.all", "BG.mx.all_tps_inpt")
coh_loc[, BG.mx.all := ALL.mx - rowSums(.SD), .SDcols = coh_cvd]
coh_negative <- coh_loc[BG.mx.all < 0]
if (nrow(coh_negative))
  stop("Stage 2 (trends): the four CVD rates exceed ALL.mx in ", nrow(coh_negative), " cells (first: ",
       paste(unlist(coh_negative[1L, coh_keys, with = FALSE]), collapse = ", "), ").", call. = FALSE)
# The tps_inpt column comes from stage 1, whose cause list also subtracts dementia.
# This forecast uses ALL.mx - sum(4 CVD causes) and reports the difference.
coh_loc[, gap_share := (BG.mx.all - BG.mx.all_tps_inpt) / ALL.mx]
coh_gap <- list(
  n_cells = nrow(coh_loc), n_differ = coh_loc[abs(gap_share) > coh_tol, .N],
  median_pct = 100 * coh_loc[, stats::median(gap_share)], max_pct = 100 * coh_loc[, max(abs(gap_share))],
  pct_deaths_anchor = coh_loc[year == coh_anchor, 100 * sum(Nx * (BG.mx.all - BG.mx.all_tps_inpt)) / sum(Nx * ALL.mx)],
  by_band_anchor = coh_loc[year == coh_anchor, .(pct_of_all_deaths = 100 * sum(Nx * (BG.mx.all - BG.mx.all_tps_inpt)) / sum(Nx * ALL.mx)),
                           keyby = .(sex, age_band = cut(age, c(19, 49, 69, 79, 89, 95)))])
if (coh_gap$n_differ)
  message("Stage 2 (trends): tps_inpt BG.mx.all differs from ALL.mx - sum(4 CVD) in ", coh_gap$n_differ, " of ",
          coh_gap$n_cells, " cells (", signif(coh_gap$pct_deaths_anchor, 3), "% of adult deaths in ", coh_anchor,
          "; stage 1 also subtracts dementia). This forecast uses ALL.mx - sum(4 CVD).")
coh_loc[, c("BG.mx.all_tps_inpt", "gap_share") := NULL]

## 1d. Weights. Nx in tps_inpt is the UN-WPP 2024 population; its age-95 row holds the
## single-age-95 count while the rates there are GBD 95+ rates, so the open row is
## weighted with the UN-WPP population aged 95+ from the same file.
coh_pop <- as.data.table(readRDS(tcfg$pop_file))
if ("year_id" %in% names(coh_pop)) setnames(coh_pop, "year_id", "year")
if (length(setdiff(c("location", "sex", "year", "age", "Nx"), names(coh_pop))))
  stop("Stage 2 (trends): ", tcfg$pop_file, " lacks location/sex/year/age/Nx.", call. = FALSE)
coh_pop95 <- coh_pop[age >= tcfg$open_age & year %in% coh_years,
                     .(N95plus = sum(Nx), N95 = sum(Nx[age == tcfg$open_age])), by = .(location, sex, year)]
coh_w95 <- merge(coh_loc[age == tcfg$open_age, .(location, sex, year, Nx)], coh_pop95,
                 by = c("location", "sex", "year"), all.x = TRUE)
if (anyNA(coh_w95$N95plus))
  stop("Stage 2 (trends): no UN-WPP 95+ population for ", coh_w95[is.na(N95plus), uniqueN(location)],
       " locations (first: ", coh_w95[is.na(N95plus), location][1L], ").", call. = FALSE)
coh_same <- function(a, b) abs(a - b) <= 1e-8 * pmax(abs(b), 1)
if (coh_w95[, all(coh_same(Nx, N95plus))]) {
  coh_weight95 <- "tps_inpt Nx at age 95 already equals the UN-WPP population aged 95+"
} else if (coh_w95[, all(coh_same(Nx, N95))]) {
  coh_loc[coh_w95, Nx := fifelse(age == tcfg$open_age, i.N95plus, Nx), on = .(location, sex, year)]
  coh_weight95 <- "tps_inpt Nx at age 95 is the single-age-95 count; replaced by the UN-WPP population aged 95+"
} else {
  stop("Stage 2 (trends): tps_inpt Nx at age 95 matches neither the UN-WPP single-age-95 nor the 95+ population.",
       call. = FALSE)
}
# Zero-population cells are valid: they add no exposure and no deaths to the Global
# rates. They are reported, not imputed or removed.
coh_zero_nx <- coh_loc[Nx == 0, .N, by = location][order(-N)]
if (nrow(coh_zero_nx))
  message("Stage 2 (trends): ", sum(coh_zero_nx$N), " location/sex/year/age cells have Nx = 0 and carry zero weight (",
          paste(coh_zero_nx$location, coh_zero_nx$N, collapse = ", "), ").")
coh_locations <- sort(unique(coh_loc$location))

## 1e. Global rate = total deaths / total population over one fixed location set, so
## the additive identity carries over to the aggregate.
coh_wide <- coh_loc[, c(list(Nx = sum(Nx)), lapply(.SD, function(rate) sum(rate * Nx) / sum(Nx))),
                    by = .(sex, year, age), .SDcols = coh_components]
setorder(coh_wide, sex, year, age)
if (nrow(coh_wide) != length(tcfg$sexes) * length(coh_years) * length(coh_ages) || coh_wide[, any(!(Nx > 0))])
  stop("Stage 2 (trends): Global population is missing or zero in some cells.", call. = FALSE)
coh_obs_error <- coh_wide[, max(abs(ALL.mx - rowSums(.SD)) / ALL.mx), .SDcols = coh_bottom]
if (!(coh_obs_error <= coh_tol))
  stop("Stage 2 (trends): observed Global rates break the all-cause identity (max relative error ",
       signif(coh_obs_error, 3), ").", call. = FALSE)
rm(ci, coh_spread, coh_negative, coh_pop, coh_pop95)

## 1f. Base forecasts: Lee-Carter on log rates (SVD, b_x normalised to sum to one,
## k_t rescaled so the fitted surface is unchanged) and damped additive-trend ETS for
## k_t. No floor: a non-positive rate stops the forecast.
coh_lc <- function(panel, component, end_year, forecast_end) {
  wide <- dcast(panel[year <= end_year], age ~ year, value.var = component)
  mat <- as.matrix(wide[, -1L, with = FALSE])
  rownames(mat) <- wide$age
  if (!identical(as.integer(wide$age), coh_ages) ||
      !identical(colnames(mat), as.character(min(coh_years):end_year)) || anyNA(mat))
    stop("Stage 2 (trends): incomplete Lee-Carter matrix for ", component, call. = FALSE)
  if (any(mat <= 0))
    stop("Stage 2 (trends): ", component, " has ", sum(mat <= 0),
         " non-positive Global rates; the log-rate model is undefined.", call. = FALSE)
  log_rates <- log(mat)
  ax <- rowMeans(log_rates)
  dec <- svd(sweep(log_rates, 1L, ax, "-"), nu = 1L, nv = 1L)
  bx <- dec$u[, 1L]
  kt <- dec$d[1L] * dec$v[, 1L]
  s <- sum(bx)
  if (!is.finite(s) || abs(s) < 1e-12) stop("Stage 2 (trends): cannot normalise b_x for ", component, call. = FALSE)
  bx <- bx / s; kt <- kt * s
  kt_fit <- forecast::ets(kt, model = "AAN", damped = TRUE)
  future_kt <- as.numeric(forecast::forecast(kt_fit, h = forecast_end - end_year)$mean)
  fitted <- exp(ax + bx %o% kt)
  future <- exp(ax + bx %o% future_kt)
  dimnames(fitted) <- dimnames(mat)
  dimnames(future) <- list(rownames(mat), as.character((end_year + 1L):forecast_end))
  list(fitted = fitted, future = future, observed = mat,
       summary = data.table(component = component, fit_end = end_year,
                            var_explained = dec$d[1L]^2 / sum(dec$d^2),
                            alpha = unname(kt_fit$par["alpha"]), beta = unname(kt_fit$par["beta"]),
                            phi = unname(kt_fit$par["phi"]), kt_first = kt[1L], kt_last = kt[length(kt)],
                            kt_end = future_kt[length(future_kt)], ets_method = kt_fit$method))
}

# Covariance: LC fitted-value residuals on the rate scale, per age, shrunk halfway to
# their diagonal (16-20 years cannot identify a stable unrestricted 6 x 6 covariance).
# This is the reference implementation's proxy for the unknown base-forecast error
# covariance, estimated within each fit window. No additive jitter is added.
coh_fit <- function(panel, end_year, forecast_end) {
  if (max(panel$year) != end_year) stop("Stage 2 (trends): training data do not end in ", end_year, call. = FALSE)
  fits <- lapply(coh_components, function(cp) coh_lc(panel, cp, end_year, forecast_end))
  names(fits) <- coh_components
  cov_diag <- vector("list", length(coh_ages))
  covariance <- lapply(seq_along(coh_ages), function(i) {
    errors <- sapply(coh_components, function(cp) fits[[cp]]$observed[i, ] - fits[[cp]]$fitted[i, ])
    W <- stats::cov(errors)
    W <- (1 - tcfg$cov_shrinkage) * W + tcfg$cov_shrinkage * diag(diag(W), nrow(W))
    if (anyNA(W) || any(diag(W) <= 0))
      stop("Stage 2 (trends): degenerate error covariance at age ", coh_ages[i], call. = FALSE)
    ev <- eigen(W, symmetric = TRUE, only.values = TRUE)$values
    if (min(ev) <= 0) stop("Stage 2 (trends): error covariance not positive definite at age ", coh_ages[i], call. = FALSE)
    cov_diag[[i]] <<- data.table(age = coh_ages[i], kappa = max(ev) / min(ev), min_var = min(diag(W)),
                                 max_var = max(diag(W)))
    W
  })
  list(fits = fits, covariance = covariance, cov_diag = rbindlist(cov_diag),
       lc_summary = rbindlist(lapply(fits, `[[`, "summary")))
}

# Minimum-trace reconciliation (Li et al. 2019, eqs. 16 and 22) in its constraint form,
# y~ = y^ - W C'(C W C')^-1 C y^, where C y = 0 is ALL.mx - sum(bottom) = 0. This avoids
# inverting W. Linear reconciliation does not bound rates below: a negative reconciled
# rate stops the run (truncating it would break the identity).
coh_C <- matrix(c(1, rep(-1, length(coh_bottom))), nrow = 1L, dimnames = list(NULL, coh_components))
coh_reconcile <- function(fit, years, label) {
  rbindlist(lapply(seq_along(coh_ages), function(i) {
    base <- do.call(rbind, lapply(fit$fits, function(f) f$future[i, as.character(years)]))
    WC <- fit$covariance[[i]] %*% t(coh_C)
    CWC <- coh_C %*% WC
    if (!(CWC[1, 1] > 0)) stop("Stage 2 (trends): C W C' is not positive (", label, ", age ", coh_ages[i], ").", call. = FALSE)
    rec <- base - WC %*% solve(CWC, coh_C %*% base)
    bottom <- rec[coh_bottom, , drop = FALSE]
    total <- colSums(bottom)
    if (any(!is.finite(rec)) || max(abs(rec["ALL.mx", ] - total) / total) > coh_tol)
      stop("Stage 2 (trends): reconciled forecast is not coherent (", label, ", age ", coh_ages[i], ").", call. = FALSE)
    if (any(!(bottom >= 0))) {
      neg <- which(!(bottom >= 0), arr.ind = TRUE)
      stop("Stage 2 (trends): ", nrow(neg), " negative reconciled rate(s) (", label, ", age ", coh_ages[i], "): ",
           paste(coh_bottom[neg[, 1]], years[neg[, 2]], collapse = "; "), call. = FALSE)
    }
    out <- as.data.table(t(bottom))
    out[, `:=`(year = years, age = coh_ages[i], ALL.mx = total)]
    base_out <- as.data.table(t(base))
    setnames(base_out, paste0(names(base_out), "_base"))
    cbind(out, base_out)
  }))
}

## 1g. Holdout (fit 2000-training_end only; its own covariance) and production
## (refit on the full history) by sex.
coh_by_sex <- lapply(tcfg$sexes, function(sx) {
  panel <- coh_wide[sex == sx]
  hfit <- coh_fit(panel[year <= coh_train_end], coh_train_end, max(coh_holdout))
  hrec <- coh_reconcile(hfit, coh_holdout, paste(sx, "holdout"))
  rec_long <- melt(hrec[, c("year", "age", coh_components), with = FALSE], id.vars = c("year", "age"),
                   variable.name = "component", value.name = "reconciled", variable.factor = FALSE)
  base_long <- melt(hrec[, c("year", "age", paste0(coh_components, "_base")), with = FALSE], id.vars = c("year", "age"),
                    variable.name = "component", value.name = "base", variable.factor = FALSE)
  base_long[, component := sub("_base$", "", component)]
  obs_long <- melt(panel[year %in% coh_holdout, c("year", "age", coh_components), with = FALSE],
                   id.vars = c("year", "age"), variable.name = "component", value.name = "observed", variable.factor = FALSE)
  cells <- merge(merge(rec_long, base_long, by = c("component", "year", "age")), obs_long, by = c("component", "year", "age"))
  n_expected <- length(coh_components) * length(coh_ages) * length(coh_holdout)
  if (nrow(cells) != n_expected || anyNA(cells))
    stop("Stage 2 (trends): holdout forecasts and observations do not align (", sx, ").", call. = FALSE)
  if (cells[, any(!(observed > 0) | !(base > 0) | !(reconciled > 0))])
    stop("Stage 2 (trends): non-positive holdout rates; log-scale errors are undefined (", sx, ").", call. = FALSE)
  cells[, sex := sx]
  summ <- cells[, .(n = .N, n_expected = length(coh_ages) * length(coh_holdout),
                    rmse_rate = sqrt(mean((reconciled - observed)^2)), rmse_rate_base = sqrt(mean((base - observed)^2)),
                    rmse_log = sqrt(mean((log(reconciled) - log(observed))^2)),
                    rmse_log_base = sqrt(mean((log(base) - log(observed))^2))), by = component]
  summ[, sex := sx]
  pfit <- coh_fit(panel, max(coh_years), coh_until)
  prec <- coh_reconcile(pfit, (max(coh_years) + 1L):coh_until, paste(sx, "projection"))
  prec[, sex := sx]
  list(projection = prec, cells = cells, summary = summ,
       lc = rbind(hfit$lc_summary[, window := "holdout"], pfit$lc_summary[, window := "production"])[, sex := sx],
       cov = rbind(hfit$cov_diag[, window := "holdout"], pfit$cov_diag[, window := "production"])[, sex := sx])
})

## 1h. Final panel: observed history + reconciled forecast, and cumulative changes
## relative to each series' observed anchor-year (2019) Global rate.
coh_future_all <- rbindlist(lapply(coh_by_sex, `[[`, "projection"), use.names = TRUE)
coh_base_future <- coh_future_all[, c("sex", "year", "age", paste0(coh_components, "_base")), with = FALSE]
setnames(coh_base_future, paste0(coh_components, "_base"), coh_components)
coh_future <- coh_future_all[, c("sex", "year", "age", coh_components), with = FALSE][, source := "reconciled_forecast"]
coh_history <- coh_wide[, c("sex", "year", "age", coh_components), with = FALSE][, source := "observed"]
coh_rates <- rbindlist(list(coh_history, coh_future), use.names = TRUE)
setorder(coh_rates, sex, age, year)
if (nrow(coh_rates) != length(tcfg$sexes) * length(coh_ages) * length(min(coh_years):coh_until) ||
    anyDuplicated(coh_rates, by = c("sex", "age", "year")))
  stop("Stage 2 (trends): output grid is incomplete or duplicated.", call. = FALSE)
if (coh_rates[, any(!is.finite(as.matrix(.SD)) | as.matrix(.SD) < 0), .SDcols = coh_components])
  stop("Stage 2 (trends): negative or non-finite rates in the output.", call. = FALSE)
coh_identity <- coh_rates[, abs(ALL.mx - rowSums(.SD)) / ALL.mx, .SDcols = coh_bottom]
if (!(max(coh_identity) <= coh_tol))
  stop("Stage 2 (trends): all-cause aggregation identity failed (max relative error ",
       signif(max(coh_identity), 3), ").", call. = FALSE)
message("Stage 2 (trends): identity holds in all ", nrow(coh_rates), " sex/age/year cells (max relative error ",
        signif(max(coh_identity), 3), ").")

coh_long <- melt(coh_rates, id.vars = c("sex", "age", "year", "source", "ALL.mx", "BG.mx.all"),
                 measure.vars = coh_cvd, variable.name = "cause", value.name = "DIS.mx.t0", variable.factor = FALSE)
coh_long[, BG.mx := ALL.mx - DIS.mx.t0]
if (coh_long[, any(!(BG.mx >= 0))]) stop("Stage 2 (trends): negative BG.mx in the output.", call. = FALSE)
if (coh_long[year == coh_anchor, .N, by = .(sex, age, cause)][, any(N != 1L)] ||
    coh_long[year == coh_anchor, any(!(DIS.mx.t0 > 0) | !(BG.mx > 0) | !(BG.mx.all > 0))])
  stop("Stage 2 (trends): anchor-year denominators are missing, duplicated or not positive.", call. = FALSE)
coh_long[, `:=`(
  percent_diff_cvd      = DIS.mx.t0 / DIS.mx.t0[year == coh_anchor] - 1,
  percent_diff_bgmx     = BG.mx / BG.mx[year == coh_anchor] - 1,
  percent_diff_bgmx_all = BG.mx.all / BG.mx.all[year == coh_anchor] - 1), by = .(sex, age, cause)]
if (coh_long[year == coh_anchor, any(percent_diff_cvd != 0 | percent_diff_bgmx != 0 | percent_diff_bgmx_all != 0)])
  stop("Stage 2 (trends): the anchor-year change is not zero.", call. = FALSE)
coh_long[, location := "Global"]
setcolorder(coh_long, c("location", "sex", "age", "year", "source", "cause", "DIS.mx.t0", "ALL.mx", "BG.mx", "BG.mx.all"))
setorder(coh_long, sex, cause, age, year)

coh_validation <- rbindlist(lapply(coh_by_sex, `[[`, "summary"), use.names = TRUE)
setcolorder(coh_validation, c("sex", "component"))
coh_validation[, component := factor(component, levels = coh_components)]
setorder(coh_validation, sex, component)
coh_validation[, component := as.character(component)]
coh_cells <- rbindlist(lapply(coh_by_sex, `[[`, "cells"), use.names = TRUE)
setcolorder(coh_cells, c("sex", "component", "age", "year", "observed", "base", "reconciled"))

# Jump-off: ratio of the first forecast year to the observed anchor year (the LC fit
# does not pass through the observed 2019 rate).
coh_jumpoff <- merge(coh_future[year == coh_anchor + 1L, c("sex", "age", coh_components), with = FALSE],
                     coh_history[year == coh_anchor, c("sex", "age", coh_components), with = FALSE],
                     by = c("sex", "age"), suffixes = c("_next", "_anchor"))
coh_jumpoff <- rbindlist(lapply(coh_components, function(cp)
  coh_jumpoff[, .(component = cp, ratio = get(paste0(cp, "_next")) / get(paste0(cp, "_anchor"))), by = sex][
    , .(min = min(ratio), median = stats::median(ratio), max = max(ratio)), by = .(sex, component)]))

## 1i. Run identity, metadata and outputs.
coh_inputs <- c(tps_files, tcfg$pop_file)
coh_md5 <- tools::md5sum(coh_inputs)
coh_sig <- tempfile(fileext = ".rds")
saveRDS(list(tcfg[setdiff(names(tcfg), c("tps_dir", "out_dir", "ihme_dir"))], unname(coh_md5)), coh_sig)
coh_run_id <- paste0(format(trend_t0, "%Y%m%d-%H%M%S"), "-", substr(unname(tools::md5sum(coh_sig)), 1, 8))
unlink(coh_sig)

coh_meta <- list(
  run_id = coh_run_id, started = format(trend_t0, "%Y-%m-%d %H:%M:%S %Z"),
  completed = format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z"),
  method = paste("Forecast reconciliation (adaptation of Li, Li, Lu and Panagiotelis 2019):",
                 "Lee-Carter base forecasts per series and sex, k_t by damped additive-trend ETS,",
                 "reconciled on the rate scale by sex and age with the constraint form of the minimum-trace projection"),
  reference = "Li H, Li H, Lu Y, Panagiotelis A. Insurance: Mathematics and Economics 2019;86:122-133. doi:10.1016/j.insmatheco.2019.02.011",
  hierarchy = "ALL.mx = ihd + istroke + hstroke + hhd + BG.mx.all", components = coh_components,
  cause_map = tcfg$causes,
  other_cause = "BG.mx.all = ALL.mx - sum of the four CVD DIS.mx.t0 (the tps_inpt BG.mx.all, which also subtracts dementia, is not used)",
  bg_mx_all_gap = coh_gap,
  ages = coh_ages,
  age_convention = paste0("single ages ", min(coh_ages), "-", tcfg$open_age - 1L, "; row ", tcfg$open_age,
                          " = open interval ", tcfg$open_age, "+ (GBD ", tcfg$open_age, "+ rates)"),
  weight_95 = coh_weight95, sexes = tcfg$sexes,
  aggregation = "Global rate = sum(Nx * rate) / sum(Nx) over one fixed location set; Nx = UN-WPP 2024 population from tps_inpt",
  locations = coh_locations, n_locations = length(coh_locations), n_global_rows_dropped = coh_n_global_rows,
  zero_population_cells = coh_zero_nx,
  years_hist = coh_years, holdout = list(train = min(coh_years):coh_train_end, test = coh_holdout),
  production = list(train = coh_years, forecast = (max(coh_years) + 1L):coh_until),
  lee_carter = "log m[x,t] = a[x] + b[x] k[t]; a = row means of log rates; b, k = first SVD component; sum(b) = 1",
  kt_model = 'forecast::ets(k, model = "AAN", damped = TRUE)',
  covariance = paste0("W = ", 1 - tcfg$cov_shrinkage, " * cov(e) + ", tcfg$cov_shrinkage,
                      " * diag(cov(e)); e = in-sample LC fitted-value residuals on the rate scale, per sex and age, ",
                      "estimated within each fit window (holdout: ", min(coh_years), "-", coh_train_end,
                      "; production: ", min(coh_years), "-", max(coh_years), ")"),
  reconciliation = "y~ = y^ - W C'(C W C')^-1 C y^, C = (1, -1, -1, -1, -1, -1) on (ALL.mx, ihd, istroke, hstroke, hhd, BG.mx.all)",
  anchor = paste0("observed ", coh_anchor, " Global rate of each series: percent_diff = rate[t] / rate[", coh_anchor, "] - 1"),
  rel_tol = coh_tol, max_identity_error = max(coh_identity), observed_identity_error = coh_obs_error,
  n_negative_reconciled = 0L,
  inputs = data.table(file = coh_inputs, md5 = unname(coh_md5), mtime = format(file.mtime(coh_inputs))),
  r_version = R.version.string, forecast_version = as.character(utils::packageVersion("forecast")),
  data_table_version = as.character(utils::packageVersion("data.table")))

coh_out <- file.path(tcfg$out_dir, c(forecast = "tps_mortality_coherent_forecasted.rds",
                                     validation = "tps_mortality_coherent_validation.rds",
                                     diagnostics = "tps_mortality_coherent_diagnostics.rds"))
names(coh_out) <- c("forecast", "validation", "diagnostics")
setattr(coh_long, "trend_run_id", coh_run_id)
setattr(coh_validation, "trend_run_id", coh_run_id)
saveRDS(coh_long, coh_out[["forecast"]])
saveRDS(coh_validation, coh_out[["validation"]])
saveRDS(list(meta = coh_meta, holdout_cells = coh_cells, base_forecast = coh_base_future,
             global_observed = coh_wide, lc = rbindlist(lapply(coh_by_sex, `[[`, "lc")),
             covariance = rbindlist(lapply(coh_by_sex, `[[`, "cov")), jumpoff = coh_jumpoff),
        coh_out[["diagnostics"]])
print(coh_validation)
cat(sprintf("Stage 2 (trends): coherent forecast run %s, %d locations, holdout %d-%d, production fit %d-%d -> %d.\n",
            coh_run_id, length(coh_locations), min(coh_holdout), max(coh_holdout), min(coh_years), max(coh_years), coh_until))

#...........................................................
# 2. Legacy independent Lee-Carter forecasts (alternative) ----
#...........................................................
# Kept for trend_config$method = "legacy". Each Global series (BG.mx and BG.mx.all by
# cause row, DIS.mx.t0) is forecast on its own: LC fitted on 2000-2015, k_t by damped
# ETS, and that 2000-2015 fit is used for the projection years. Fixes relative to the
# earlier version: anchored inputs (above); the 2019 anchor is merged on explicit keys
# (the old merge also matched on BG.mx.all, which is NA in projected rows, so every
# projected BG.mx change was NA and stage 6 never applied it); percent_lag is computed
# in year order within age.

dt_bgmx <- tps[location != "Global", .(location, year, age, sex, cause, BG.mx, Nx, BG.mx.all, ALL.mx, DIS.mx.t0)]

# Build an ages x years rate matrix with proper dimnames
make_rate_matrix <- function(d, ages, years) {
  # ensure full grid (mean in case of duplicates)
  m <- tapply(d$BG.mx, list(d$age, d$year), mean)
  # coerce to requested rectangular grid
  row_missing <- setdiff(ages, as.numeric(rownames(m)))
  col_missing <- setdiff(years, as.numeric(colnames(m)))
  if (length(row_missing)) {
    m <- rbind(m, matrix(NA_real_, nrow = length(row_missing), ncol = ncol(m),
                         dimnames = list(as.character(row_missing), colnames(m))))
  }
  if (length(col_missing)) {
    m <- cbind(m, matrix(NA_real_, nrow = nrow(m), ncol = length(col_missing),
                         dimnames = list(rownames(m), as.character(col_missing))))
  }
  m <- m[order(as.numeric(rownames(m))), order(as.numeric(colnames(m))), drop = FALSE]
  # guard against zeros/negatives
  m[m <= 0 | is.na(m)] <- NA_real_
  m
}

# Classical LC on log-rates via SVD
lc_fit_on_rates <- function(mx_mat) {
  logm <- log(mx_mat)
  ax   <- rowMeans(logm, na.rm = TRUE)
  M <- sweep(logm, 1, ax, "-")
  good_cols <- which(colSums(!is.na(M)) == nrow(M))
  if (!length(good_cols)) stop("No complete years to run SVD.")
  Ms <- M[, good_cols, drop = FALSE]
  sv <- svd(Ms)
  bx <- sv$u[, 1]
  kt_partial <- sv$d[1] * sv$v[, 1]
  kt <- rep(NA_real_, ncol(M))
  kt[good_cols] <- kt_partial
  # normalize so sum(bx)=1
  s <- sum(bx)
  bx <- bx / s
  kt <- kt * s
  list(ax = ax, bx = bx, kt = kt, good_cols = good_cols)
}

# Forecast kt with damped-trend ETS and reconstruct log m(x,t)
lc_forecast <- function(ax, bx, kt, years_train, last_proj_year) {
  obs_idx <- which(!is.na(kt))
  kt_obs  <- kt[obs_idx]
  yrs_obs <- years_train[obs_idx]
  fit.kt  <- forecast::ets(kt_obs, model = "AAN", damped = TRUE)
  h_years <- last_proj_year - max(years_train)
  kt_fc   <- forecast::forecast(fit.kt, h = h_years)
  kt_all  <- c(kt_obs, as.numeric(kt_fc$mean))
  years_all <- c(yrs_obs, max(years_train) + seq_len(h_years))
  logm_all <- ax + bx %o% kt_all
  dimnames(logm_all) <- list(age = names(ax), year = as.character(years_all))
  list(logm_all = logm_all, years_all = years_all, kt_fit = kt_obs, kt_fc = kt_fc)
}

# Per-group wrapper: train 2000-2015, RMSE on 2016-2019 (log scale), project 2016-2050
fit_forecast_group <- function(dg) {
  train_years <- 2000:2015
  test_years  <- 2016:2019
  proj_until  <- 2050
  ages_all <- sort(unique(dg$age))
  ages_use <- ages_all[ages_all >= 20 & ages_all <= 95]
  mx_train <- make_rate_matrix(dg[year %in% train_years], ages_use, train_years)
  mx_test  <- make_rate_matrix(dg[year %in% test_years],  ages_use, test_years)
  keep_age <- which(rowSums(is.na(mx_train)) == 0)
  if (!length(keep_age)) return(list(rmse = NA_real_, proj = data.table()))
  mx_train <- mx_train[keep_age, , drop = FALSE]
  mx_test  <- mx_test[rownames(mx_train), , drop = FALSE]
  lc <- lc_fit_on_rates(mx_train)
  yrs_train <- as.integer(colnames(mx_train))
  fc <- lc_forecast(lc$ax, lc$bx, lc$kt, yrs_train, proj_until)
  need_cols <- as.character(test_years)
  has_cols <- need_cols[need_cols %in% colnames(fc$logm_all)]
  if (length(has_cols)) {
    logm_hat_test <- fc$logm_all[rownames(mx_test), has_cols, drop = FALSE]
    obs_test <- log(mx_test[, has_cols, drop = FALSE])
    rmse <- sqrt(mean((obs_test - logm_hat_test)^2, na.rm = TRUE))
  } else {
    rmse <- NA_real_
  }
  proj_years <- (max(train_years) + 1L):proj_until
  mat_proj <- exp(fc$logm_all[, as.character(proj_years), drop = FALSE])
  proj_dt <- as.data.table(as.table(mat_proj))
  setnames(proj_dt, c("age", "year", "BG.mx_proj"))
  proj_dt[, age  := as.numeric(as.character(age))]
  proj_dt[, year := as.integer(as.character(year))]
  setorder(proj_dt, age, year)
  list(rmse = rmse, proj = proj_dt)
}

# Forecast one Global series (column BG.mx of dt) and write its 2019-relative changes.
legacy_trend_file <- function(dt, file) {
  dt <- as.data.table(dt)
  dt[, `:=`(year = as.integer(year), age = as.integer(age))]
  setkey(dt, location, sex, cause, year, age)
  res <- dt[, {
    out <- fit_forecast_group(.SD)
    .(rmse = out$rmse, proj = list(out$proj))
  }, by = .(location, sex, cause)]
  proj <- res[, rbindlist(proj), by = .(location, sex, cause)]
  setnames(proj, "BG.mx_proj", "BG.mx")
  proj[, age := as.integer(age)]
  dt <- rbind(dt[, .(location, sex, cause, year, age, BG.mx)], proj[year > 2019L, .(location, sex, cause, year, age, BG.mx)])
  if (anyDuplicated(dt, by = c("location", "sex", "cause", "age", "year")))
    stop("Stage 2 (trends): duplicated rows in legacy forecast ", basename(file), call. = FALSE)
  anchor <- dt[year == 2019L, .(location, sex, cause, age, BG.mx_2019 = BG.mx)]
  dt <- merge(dt, anchor, by = c("location", "sex", "cause", "age"), all.x = TRUE)
  setorder(dt, location, sex, cause, age, year)
  dt[, percent_lag := BG.mx / shift(BG.mx, 1L, type = "lag") - 1, by = .(location, sex, cause, age)]
  dt[, percent_diff := (BG.mx - BG.mx_2019) / BG.mx_2019]
  if (dt[year > 2019L, anyNA(percent_diff)])
    stop("Stage 2 (trends): missing projected changes in legacy forecast ", basename(file), call. = FALSE)
  dt[, c("BG.mx_2019", "location", "BG.mx") := NULL]
  setcolorder(dt, c("age", "sex", "cause", "year", "percent_lag", "percent_diff"))
  saveRDS(dt, file = file)
  invisible(res[, .(sex, cause, rmse)])
}

## Background mortality of each cause row (all causes except that cause)
legacy_rmse_bgmx <- legacy_trend_file(
  dt_bgmx[, list(BG.mx = weighted.mean(BG.mx, Nx)), by = list(year, age, sex, cause)][, location := "Global"],
  file.path(tcfg$out_dir, "tps_bgmx_forecasted.rds"))

## Shared other-cause envelope (tps_inpt BG.mx.all)
legacy_rmse_bgmx_all <- legacy_trend_file(
  dt_bgmx[, list(BG.mx = weighted.mean(BG.mx.all, Nx)), by = list(year, age, sex, cause)][, location := "Global"],
  file.path(tcfg$out_dir, "tps_bgmx_all_forecasted.rds"))

## CVD cause-specific death rates (used for the CF trend)
legacy_rmse_cvd <- legacy_trend_file(
  dt_bgmx[, list(BG.mx = weighted.mean(DIS.mx.t0, Nx)), by = list(year, age, sex, cause)][, location := "Global"],
  file.path(tcfg$out_dir, "tps_bgmx_cvd_forecasted.rds"))

#...........................................................
# 3. IHME Foresight CVD trend for CF (alternative) ----
#...........................................................
# Repository copies of the Foresight age-standardised rate files (byte-identical to the
# former 100MLives/data/raw/GBD copies). Their footer cites the GBD 2019 Foresight
# visualisation; "gbd2023" in the file names is the download batch, not the release.

files <- list.files(path = tcfg$ihme_dir, pattern = "gbd2023_foresight_asr_.*20\\+\\.csv$", full.names = TRUE)
if (length(files) != 4L) stop("Stage 2 (trends): expected four Foresight ASR files in ", tcfg$ihme_dir, call. = FALSE)

# Read and bind them (fread drops the one-line citation footer with a warning)
dt_gbd_fore <- rbindlist(lapply(files, function(f) suppressWarnings(fread(f))), fill = TRUE, idcol = "source")

setnames(dt_gbd_fore, tolower(gsub(" ", "_", names(dt_gbd_fore))))

dt_gbd_fore <- dt_gbd_fore[year >= 2000 & scenario %in% c("Past", "Reference") & !is.na(value),
                           c("year", "cause_of_death_or_injury", "value"), with = F]

dt_gbd_fore[, source := "GBD Foresight"]

setnames(dt_gbd_fore, c("cause_of_death_or_injury", "value"), c("cause", "ASMR"))

dt_gbd_fore[, cause := fcase(
  cause == "Ischemic heart disease", "ihd",
  cause == "Ischemic stroke", "istroke",
  cause == "Intracerebral hemorrhage", "hstroke",
  cause == "Hypertensive heart disease", "hhd",
  cause == "Alzheimer's disease and other dementias", "aod",
  default = cause
)]

dt_2019 <- dt_gbd_fore[year == 2019, ]
dt_2019[, year := NULL]

setnames(dt_2019, "ASMR", "ASMRB")

dt <- merge(dt_gbd_fore, dt_2019, by = c("cause", "source"), all.x = T)

dt[, percent_diff := (ASMR - ASMRB) / ASMRB]

dt <- dt[, c("year", "cause", "percent_diff"), with = F]

saveRDS(dt, file = file.path(tcfg$out_dir, "tps_bgmx_cvd_ihme.rds"))

rm(tps, dt_bgmx, dt, dt_2019, dt_gbd_fore, files, coh_loc, coh_wide, coh_rates, coh_long, coh_history, coh_future,
   coh_future_all, coh_base_future, coh_cells, coh_by_sex, coh_w95)
invisible(gc(FALSE))
