#===============================================================================
# code/8. run_sensitivity.R  --  Stage 8: deterministic mortality-trend sensitivity analyses
#-------------------------------------------------------------------------------
# Sourced by code/0. master.R (stage 8) after its setup section. Runs the alternative trend
# blocks of Table S8, one after another (memory), each in its own R process:
#   ihme_foresight  code/8.1_sensitivity_ihme_foresight.R  -> output/uncertainty/dsa/out_model_ihme_foresight/
#   lc              code/8.2_sensitivity_lc.R              -> output/uncertainty/dsa/out_model_lc/
#   no_trends       code/8.3_sensitivity_no_trends.R       -> output/uncertainty/dsa/out_model_no_trends/
# The base case is the production run (output/out_model/, stage 7); it is not rerun here.
# Shared execution, isolation and validation: code/8.0_sensitivity_helpers.R.
# Master options: --dsa=<names> (subset), --dsa-pilot=<countries> (execution check only),
# --dsa-workers=<n> (PSOCK workers per analysis; default dsa_default_workers = 3).
#===============================================================================

local({
  if (!exists("check_trend_settings", mode = "function") || !exists("cal_config") || !exists("wd_code"))
    stop("Stage 8 needs the setup of code/0. master.R.", call. = FALSE)
  source(paste0(wd_code, "8.0_sensitivity_helpers.R"))
  subfiles <- c(ihme_foresight = "8.1_sensitivity_ihme_foresight.R", lc = "8.2_sensitivity_lc.R",
                no_trends = "8.3_sensitivity_no_trends.R")
  for (f in subfiles) source(paste0(wd_code, f))

  sel   <- if (exists("dsa_analyses") && !is.null(dsa_analyses)) dsa_analyses else names(subfiles)
  pilot <- if (exists("dsa_pilot")) dsa_pilot else NULL
  workers <- if (exists("dsa_workers") && length(dsa_workers)) dsa_workers else dsa_default_workers
  if (length(setdiff(sel, names(subfiles))))
    stop("Stage 8: unknown analyses ", paste(setdiff(sel, names(subfiles)), collapse = ", "),
         "; choose from ", paste(names(subfiles), collapse = ", "), call. = FALSE)

  t0 <- Sys.time()
  res <- rbindlist(lapply(sel, function(a) get(paste0("run_dsa_", a))(countries = pilot, workers = workers)))

  # Completion: every analysis passed its own validation, and the inputs no trend switch
  # touches (populations, prevalence, historical rates, BP and coverage data) are identical.
  inv <- rbindlist(lapply(res$analysis, function(a) {
    f <- dsa_paths(a, !is.null(pilot))$manifest
    if (!file.exists(f)) return(NULL)
    m <- readRDS(f)
    if (is.null(m$invariant)) return(NULL)
    data.table(analysis = a, nontrend = m$invariant$nontrend_columns, historical = m$invariant$historical_rows,
               data_in = m$invariant$data_in, inc = m$invariant$inc)
  }))
  same_inputs <- nrow(inv) <= 1L || all(vapply(inv[, -1], uniqueN, integer(1)) == 1L)
  cat(sprintf("\n==== Stage 8 summary (%.1f min)%s ====\n", as.numeric(difftime(Sys.time(), t0, units = "mins")),
              if (is.null(pilot)) "" else " [pilot: not manuscript results]"))
  print(res[, .(analysis, status, run_id, countries, trend_method, cf_share,
                bau_2026_2050_M = round(bau_2026_2050_M, 2), all_four_dd_M = round(all_four_dd_M, 2),
                all_four_pct = round(100 * all_four_pct, 2), detail)])
  cat("Non-trend inputs identical across these analyses:", same_inputs, "\n")
  ok_status <- if (is.null(pilot)) "complete" else "pilot"
  if (any(res$status != ok_status) || !same_inputs)
    stop("Stage 8: not every analysis completed and validated: ",
         paste(res[status != ok_status, analysis], collapse = ", "), call. = FALSE)
  assign("dsa_results", res, envir = globalenv())
  invisible(res)
})
