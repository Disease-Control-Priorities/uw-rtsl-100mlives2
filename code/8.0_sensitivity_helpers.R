#===============================================================================
# code/8.0_sensitivity_helpers.R  --  Stage 8: shared execution of the deterministic
#                                     mortality-trend sensitivity analyses (DSA)
#-------------------------------------------------------------------------------
# Sourced by code/8. run_sensitivity.R and by each code/8.<n>_sensitivity_*.R file, after
# the setup section of code/0. master.R (paths, libraries, cal_config, trend_config,
# trend_cf_share(), check_trend_settings()). Defines:
#   dsa_spec()   one analysis: its five trend switches, a synchronised copy of trend_config
#                (method, cf_share) validated with the master's check_trend_settings(), labels
#   dsa_run()    runs one analysis in a fresh R process and checks the result
#   dsa_check()  re-checks a finished analysis folder against its manifest (no rerun)
#
# Each analysis runs in a child R process (this file run by Rscript with --dsa-child <spec>),
# so the parent session (e.g. the master) keeps its globals, switches, working directory
# and options. The child:
#   1. attaches the parent's packages in the parent's search order and sets the master's
#      globals from the spec, with the analysis's own switches and trend_config and
#      wd_outp = the analysis folder;
#   2. sources the unchanged code/6. build_baseline.R, which reads the stage-5 calibration
#      (read only) and builds a fresh prospective baseline with these switches (trends
#      applied once, to the calibrated terminal-year rates; existing probability guards and
#      checks), and checks that the baseline used exactly these switches and trend files;
#   3. sources the unchanged stage-7 runner. It writes only
#      <analysis>/out_model/model_output_part_<Country>.rds and log_<Country>.txt (the runner
#      appends out_model/ to wd_outp). A session-only makeCluster() wrapper attached ahead of
#      package:parallel caps the PSOCK workers (the runner hard-codes 8) and sets one
#      data.table thread per worker; the runner file is not changed;
#   4. validates every expected country file written by this run and saves
#      <analysis>/dsa_manifest.rds, whose status is "complete" only if every check passes.
#
# Layout (all under output/uncertainty/dsa/, ignored by Git):
#   out_model_<name>/dsa_spec.rds        resolved settings handed to the child
#   out_model_<name>/dsa_run.log         child console output (stages 6 and 7)
#   out_model_<name>/dsa_workers.log     PSOCK worker output
#   out_model_<name>/dsa_manifest.rds    provenance, file md5s, validation, status
#   out_model_<name>/out_model/          stage-7 country outputs and logs
# A pilot (countries = c(...)) writes the same layout under output/uncertainty/dsa/pilot/,
# has status "pilot", and is never read as manuscript results.
#
# Production outputs and inputs (output/out_model, output/calibration, output/benchmark,
# data/processed, and every input file the analysis reads) are hashed before and after each
# analysis; any change stops stage 8. Starting a complete analysis removes that analysis's own
# previous outputs (only the runner's file patterns and the dsa_* files in its folder), so a
# failed country can never leave a stale file that passes as part of the new run.
#===============================================================================

dsa_default_workers  <- 3L         # PSOCK workers per analysis (see the stage-7 stability notes)
dsa_reporting_window <- 2026:2050  # the manuscript's cumulative window, checked by the artifact builder
dsa_runner_name      <- "7. model_100_multiplicative_func_new3_gbd23_noaroc.R"
dsa_global_names     <- c("wd", "wd_code", "wd_raw", "wd_data", "wd_temp", "run_aod_par", "dx_include",
                          "cause_map", "cause_cols", "cal_config", "stage7_first_year")
dsa_packages_needed  <- c("data.table", "dplyr", "tidyr", "readxl", "parallel", "doParallel", "foreach")
dsa_mo_cols          <- c("scenario", "age", "cause", "sex", "year", "well", "sick", "newcases", "dead", "pop",
                          "all.mx", "intervention", "location", "eff_ir", "eff_cf")

#...........................................................
# Specification ----
#...........................................................

# One analysis. trend_config is copied and its method and cf_share are set from this
# analysis's switches (trend_cf_share() is the master's rule); the master's own trend_config
# and switches are not modified.
dsa_spec <- function(name, file, table_label, description, mortality_trend_method, run_bgmx_trend,
                     run_CF_trend, run_CF_trend_80, run_CF_trend_ihme) {
  for (f in c("check_trend_settings", "trend_cf_share"))
    if (!exists(f, mode = "function", envir = globalenv()))
      stop("Stage 8: ", f, "() not found; run the setup of code/0. master.R first.", call. = FALSE)
  if (!grepl("^[a-z][a-z_]*$", name)) stop("Stage 8: invalid analysis name ", name, call. = FALSE)
  sw <- list(mortality_trend_method = mortality_trend_method, run_bgmx_trend = run_bgmx_trend,
             run_CF_trend = run_CF_trend, run_CF_trend_80 = run_CF_trend_80, run_CF_trend_ihme = run_CF_trend_ihme)
  tc <- get("trend_config", envir = globalenv())
  tc$method   <- sw$mortality_trend_method
  tc$cf_share <- trend_cf_share(sw$run_CF_trend_80)
  check_trend_settings(sw, tc, get("cal_config", envir = globalenv()))
  list(name = name, file = file, table_label = table_label, description = description, switches = sw, trend_config = tc)
}

#...........................................................
# Paths and fingerprints ----
#...........................................................

dsa_norm <- function(p) normalizePath(p, winslash = "/", mustWork = FALSE)

dsa_paths <- function(name, pilot = FALSE) {
  if (!grepl("^[a-z][a-z_]*$", name)) stop("Stage 8: invalid analysis name ", name, call. = FALSE)
  root <- paste0(wd_outp, "uncertainty/dsa/")
  dir  <- paste0(root, if (pilot) "pilot/" else "", "out_model_", name, "/")
  # The analysis folder must sit inside output/uncertainty/dsa/ and never be a production folder.
  nd <- tolower(sub("/+$", "", gsub("/+", "/", dir))); nr <- tolower(sub("/+$", "", gsub("/+", "/", root)))
  prod <- tolower(sub("/+$", "", gsub("/+", "/", c(wd_outp, paste0(wd_outp, c("out_model", "calibration", "benchmark")), wd_data))))
  if (!startsWith(nd, paste0(nr, "/")) || grepl("\\.\\.", dir) || nd %in% prod)
    stop("Stage 8: unsafe output folder ", dir, call. = FALSE)
  list(root = root, dir = dir, out_model = paste0(dir, "out_model/"), spec = paste0(dir, "dsa_spec.rds"),
       manifest = paste0(dir, "dsa_manifest.rds"), log = paste0(dir, "dsa_run.log"),
       workers_log = paste0(dir, "dsa_workers.log"))
}

dsa_md5 <- function(f) unname(tools::md5sum(f))

dsa_file_table <- function(f) {
  data.table(file = sub(paste0(dsa_norm(wd), "/"), "", dsa_norm(f), fixed = TRUE), md5 = dsa_md5(f),
             mtime = format(file.mtime(f), "%Y-%m-%d %H:%M:%S"), path = dsa_norm(f))
}

# Trend files stage 6 reads for a set of switches (sections 6a-6d of code/6. build_baseline.R).
dsa_trend_files <- function(sw) {
  f <- character(0)
  if (sw$mortality_trend_method == "coherent") f <- c(f, "tps_mortality_coherent_forecasted.rds")
  if (sw$mortality_trend_method == "legacy" && sw$run_bgmx_trend) f <- c(f, "tps_bgmx_forecasted.rds", "tps_bgmx_all_forecasted.rds")
  if (sw$run_CF_trend && sw$run_CF_trend_ihme) f <- c(f, "tps_bgmx_cvd_ihme.rds")
  if (sw$mortality_trend_method == "legacy" && sw$run_CF_trend && !sw$run_CF_trend_ihme) f <- c(f, "tps_bgmx_cvd_forecasted.rds")
  paste0(wd_data, f)
}

# Non-trend inputs read by stages 6 and 7 (calibrated chunks, populations, BP, coverage,
# COVID, intervention inputs and relative risks).
dsa_input_files <- function() {
  cal_chunks <- sort(list.files(cal_config$out_dir, pattern = paste0("^", cal_config$out_stub, "[0-9]+\\.rds$"), full.names = TRUE))
  c(cal_chunks, file.path(cal_config$diag_dir, "calibration_settings.rds"),
    paste0(wd, c("wpp.adj.Rda", "bp_data6.csv", "ettehad_rr_bp_reduction_10mmHg.csv", "ettehad_rr_bp_reduction_effects.xlsx")),
    paste0(wd_data, c("UN2024/PopulationsSingleAge0050.rds", "UN2024/PopulationsAge20_2050.csv", "covfxn2.csv",
                      "BloodPressure/hbp_control_data.rds", "Sodium/sodium_policy_scenarios.rds",
                      "TFAPolicy/tfa_policy_scenarios.rds", "Statins/statin_data.rds", "Statins/af_statins.rds")),
    paste0(wd_raw, "GBD/IHME_GBD_2019_RELATIVE_RISKS_Y2020M10D15_HTN.xlsx"))
}

# GBD Foresight files behind tps_bgmx_cvd_ihme.rds and the release named in their citation footer.
dsa_foresight_sources <- function() {
  f <- sort(list.files(get("trend_config", envir = globalenv())$ihme_dir, pattern = "gbd2023_foresight_asr_.*20\\+\\.csv$",
                       full.names = TRUE))
  footer <- vapply(f, function(x) { l <- readLines(x, warn = FALSE); l[length(l)] }, "")
  release <- unique(regmatches(footer, regexpr("Global Burden of Disease \\(GBD\\) Study [0-9]{4}", footer)))
  list(files = dsa_file_table(f), release = release, footer = unique(unname(footer)))
}

dsa_code_files <- function(spec) {
  paste0(wd_code, c("0. master.R", "8. run_sensitivity.R", "8.0_sensitivity_helpers.R", spec$file,
                    "6. build_baseline.R", dsa_runner_name, "functions_review_6_100.R"))
}

# Production files that no analysis may change.
dsa_protected_files <- function(extra = character(0)) {
  d <- c(paste0(wd_outp, c("out_model", "calibration", "benchmark")), wd_data)
  f <- unlist(lapply(d, list.files, recursive = TRUE, full.names = TRUE))
  sort(unique(dsa_norm(c(f, extra))))
}
dsa_snapshot <- function(extra = character(0)) {
  f <- dsa_protected_files(extra)
  data.table(file = f, size = file.size(f), md5 = dsa_md5(f))
}
dsa_compare_snapshots <- function(before, after) {
  x <- merge(before, after, by = "file", all = TRUE, suffixes = c("_before", "_after"))
  x[is.na(md5_before) | is.na(md5_after) | md5_before != md5_after | size_before != size_after]
}

# md5 of a table's content (sorted rows, columns in name order, plain column vectors), for comparing
# inputs across runs. Column order is ignored: stage 6 merges on different keys in each trend path.
dsa_fingerprint <- function(x, keys = names(x)) {
  x <- copy(as.data.table(x))
  setorderv(x, keys)
  setcolorder(x, sort(names(x)))
  tf <- tempfile(); on.exit(unlink(tf))
  writeBin(serialize(lapply(as.list(x), as.vector), NULL, xdr = TRUE), tf)
  dsa_md5(tf)
}

#...........................................................
# Parent side: prerequisites, launch, checks ----
#...........................................................

dsa_require_master <- function() {
  fns <- c("check_trend_settings", "trend_cf_share")
  miss <- c(setdiff(c(dsa_global_names, "wd_outp", "trend_config"), ls(globalenv())),
            fns[!vapply(fns, exists, logical(1), mode = "function", envir = globalenv())])
  if (length(miss)) stop("Stage 8 needs the setup of code/0. master.R (missing: ", paste(miss, collapse = ", "), ").", call. = FALSE)
  pk <- setdiff(dsa_packages_needed, .packages())
  if (length(pk)) stop("Stage 8: attach the master's packages first (missing: ", paste(pk, collapse = ", "), ").", call. = FALSE)
  invisible(TRUE)
}

# Everything an analysis needs, checked before anything is removed or launched.
dsa_prerequisites <- function(spec, countries) {
  pilot <- !is.null(countries)
  stopx <- function(...) stop("Stage 8 (", spec$name, "): ", ..., call. = FALSE)
  cal_file <- file.path(cal_config$diag_dir, "calibration_settings.rds")
  if (!file.exists(cal_file)) stopx("no stage-5 calibration settings at ", cal_file)
  cal <- readRDS(cal_file)
  if (isTRUE(cal$pilot)) stopx("the saved calibration is a pilot run")
  chunks <- sort(list.files(cal_config$out_dir, pattern = paste0("^", cal_config$out_stub, "[0-9]+\\.rds$")))
  if (!length(chunks) || !setequal(chunks, cal$out_files)) stopx("calibrated chunks on disk differ from calibration run ", cal$run_id)
  mrm_file <- paste0(wd_outp, "out_model/model_run_manifest.rds")
  if (!file.exists(mrm_file)) stopx("no production model run manifest at ", mrm_file)
  mrm <- readRDS(mrm_file)
  if (!all(mrm$files$written_this_run)) stopx("the production model run manifest lists files not written by its run")
  if (!identical(mrm$baseline$calibration_run_id, cal$run_id))
    stopx("the production run used calibration ", mrm$baseline$calibration_run_id, ", the saved calibration is ", cal$run_id)
  runner_md5 <- dsa_md5(paste0(wd_code, dsa_runner_name))
  same_runner <- identical(mrm$runner_md5, runner_md5)
  prod_countries <- sub("^model_output_part_(.+)\\.rds$", "\\1", mrm$files$file)
  trend_files <- dsa_trend_files(spec$switches)
  inputs <- dsa_input_files()
  miss <- c(trend_files, inputs, dsa_code_files(spec))
  miss <- miss[!file.exists(miss)]
  if (length(miss)) stopx("missing input or code files:\n  ", paste(miss, collapse = "\n  "))
  prod_started <- as.POSIXct(substr(mrm$started, 1, 19), format = "%Y-%m-%d %H:%M:%S")
  # Inputs and model code must be those of the production run (the Table S8 base case); the
  # master and the stage-8 files are not part of the model and may be newer.
  dep <- c(trend_files, inputs, paste0(wd_code, c("6. build_baseline.R", dsa_runner_name, "functions_review_6_100.R")))
  newer <- dep[file.mtime(dep) >= prod_started]
  if (!pilot) {
    if (!same_runner) stopx("the stage-7 runner differs from the production run's (md5 ", mrm$runner_md5, "); rerun stage 7 first")
    if (length(newer)) stopx("inputs or model code changed after the production run started (", mrm$started, "):\n  ",
                             paste(newer, collapse = "\n  "))
    expected <- sort(prod_countries)
  } else {
    if (!same_runner || length(newer)) warning("Stage 8 pilot (", spec$name, "): inputs or runner differ from the production run.", call. = FALSE)
    bad <- setdiff(countries, prod_countries)
    if (length(bad)) stopx("pilot countries not in the production run: ", paste(bad, collapse = ", "))
    expected <- sort(unique(countries))
  }
  list(calibration_run_id = cal$run_id, calibration_completed = cal$completed, trend_files = trend_files, inputs = inputs,
       expected = expected,
       production = list(manifest = mrm_file, run_id = mrm$run_id, started = mrm$started, runner_md5 = mrm$runner_md5,
                         baseline_id = mrm$baseline$baseline_id, calibration_run_id = mrm$baseline$calibration_run_id,
                         countries = sort(prod_countries), same_runner = same_runner, inputs_newer = newer))
}

# Remove this analysis's previous outputs (its own folder only, the runner's file patterns and
# the dsa_* files), so no stale country file can pass as part of the new run.
dsa_clear_outputs <- function(p) {
  old <- c(list.files(p$out_model, pattern = "^(model_output_part_.+\\.rds|log_.+\\.txt)$", full.names = TRUE),
           list.files(p$dir, pattern = "^dsa_(spec|manifest)\\.rds$|^dsa_(run|workers)\\.log$", full.names = TRUE))
  if (length(old)) {
    if (!all(startsWith(tolower(dsa_norm(old)), paste0(tolower(dsa_norm(p$dir)), "/"))))
      stop("Stage 8: refusing to remove files outside ", p$dir, call. = FALSE)
    if (!all(file.remove(old))) stop("Stage 8: could not remove the previous outputs in ", p$dir, call. = FALSE)
    cat(sprintf("Stage 8: removed %d previous output file(s) of this analysis from %s\n", length(old), p$dir))
  }
  dir.create(p$out_model, recursive = TRUE, showWarnings = FALSE)
  invisible(length(old))
}

dsa_rscript <- function() file.path(R.home("bin"), if (.Platform$OS.type == "windows") "Rscript.exe" else "Rscript")
dsa_quote <- function(x) if (.Platform$OS.type == "windows") shQuote(x, type = "cmd") else shQuote(x)

# Run one analysis in a fresh R process; returns a one-row summary. Stops on a missing
# prerequisite or a changed production file; a failed run returns status "failed".
dsa_run <- function(spec, countries = NULL, workers = dsa_default_workers) {
  dsa_require_master()
  old_wd <- getwd(); on.exit(setwd(old_wd), add = TRUE)
  pilot <- !is.null(countries)
  p <- dsa_paths(spec$name, pilot)
  pre <- dsa_prerequisites(spec, countries)
  workers <- as.integer(workers)
  if (length(workers) != 1L || is.na(workers) || workers < 1L) stop("Stage 8: workers must be a positive integer.", call. = FALSE)
  cat(sprintf("\n==== Stage 8: %s%s (%s) ====\n%s\nOutput: %s\n", spec$name, if (pilot) " [pilot]" else "", spec$table_label,
              paste(sprintf("%s = %s", names(spec$switches), unlist(spec$switches)), collapse = "; "), p$dir))
  snap0 <- dsa_snapshot(c(pre$inputs, pre$trend_files))
  dsa_clear_outputs(p)
  pk <- .packages()
  run_spec <- c(spec, list(
    pilot = pilot, countries = countries, expected_countries = pre$expected, workers = workers, paths = p,
    globals = mget(dsa_global_names, envir = globalenv()), packages = rev(pk), lib_paths = .libPaths(),
    calibration_run_id = pre$calibration_run_id, production = pre$production,
    trend_files = pre$trend_files, input_files = pre$inputs, code_files = dsa_code_files(spec),
    md5_at_launch = list(code = dsa_file_table(dsa_code_files(spec)), inputs = dsa_file_table(pre$inputs),
                         trends = dsa_file_table(pre$trend_files)),
    foresight = if (spec$switches$run_CF_trend_ihme) dsa_foresight_sources() else NULL,
    reporting_window = dsa_reporting_window, created = format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z")))
  saveRDS(run_spec, p$spec)
  t0 <- Sys.time()
  exit <- system2(dsa_rscript(), c(dsa_quote(paste0(wd_code, "8.0_sensitivity_helpers.R")), "--dsa-child", dsa_quote(p$spec)),
                  stdout = p$log, stderr = p$log)
  cat(sprintf("Stage 8: %s child process finished with exit status %s after %.1f min\n", spec$name, exit,
              as.numeric(difftime(Sys.time(), t0, units = "mins"))))
  changed <- dsa_compare_snapshots(snap0, dsa_snapshot(c(pre$inputs, pre$trend_files)))
  if (nrow(changed)) {
    print(changed)
    stop("Stage 8 (", spec$name, "): production outputs or inputs changed during the analysis.", call. = FALSE)
  }
  cat("Stage 8: production outputs and inputs unchanged (", nrow(snap0), " files hashed before and after)\n", sep = "")
  res <- dsa_check(spec$name, pilot = pilot)
  if (exit != 0 || !res$status %in% c("complete", "pilot")) {
    if (file.exists(p$log)) { cat("---- last lines of", p$log, "----\n"); cat(tail(readLines(p$log, warn = FALSE), 25), sep = "\n") }
    res[, status := "failed"]
  }
  res
}

# Check a finished analysis folder against its manifest (no rerun): status, provenance and
# md5 of every country file. Returns a one-row summary.
dsa_check <- function(name, pilot = FALSE) {
  p <- dsa_paths(name, pilot)
  out <- data.table(analysis = name, pilot = pilot, status = "missing", run_id = NA_character_, countries = 0L,
                    calibration_run_id = NA_character_, trend_method = NA_character_, cf_share = NA_real_,
                    bau_2026_2050_M = NA_real_, all_four_dd_M = NA_real_, all_four_pct = NA_real_, detail = "")
  if (!file.exists(p$manifest)) { out[, detail := paste("no manifest in", p$dir)]; return(out) }
  m <- readRDS(p$manifest)
  out[, `:=`(status = m$status, run_id = m$run_id %||% NA_character_, calibration_run_id = m$calibration_run_id %||% NA_character_,
             trend_method = m$switches$mortality_trend_method, cf_share = m$trend_config$cf_share)]
  if (!identical(m$status, if (pilot) "pilot" else "complete")) {
    fails <- if (is.null(m$validation)) character(0) else m$validation$checks[passed == FALSE, check]
    out[, detail := paste(c(m$error, fails), collapse = "; ")]
    if (out$status != "failed") out[, status := "failed"]
    return(out)
  }
  f <- paste0(p$out_model, m$files$file)
  ok <- file.exists(f)
  ok[ok] <- dsa_md5(f[ok]) == m$files$md5[ok]
  if (!all(ok)) {
    out[, `:=`(status = "failed", detail = sprintf("%d country file(s) missing or changed since the run", sum(!ok)))]
    return(out)
  }
  tt <- m$totals[year %in% m$reporting_window, .(dead = sum(dead)), by = scenario]
  bau <- tt[scenario == "baseline", dead]; all4 <- tt[scenario == "all_four", dead]
  out[, `:=`(countries = nrow(m$files), bau_2026_2050_M = bau / 1e6, all_four_dd_M = (bau - all4) / 1e6,
             all_four_pct = (bau - all4) / bau, detail = "files match the manifest")]
  out
}
`%||%` <- function(a, b) if (is.null(a)) b else a

#...........................................................
# Child side: one analysis in a fresh R process ----
#...........................................................

# makeCluster() wrapper, attached ahead of package:parallel for this process only: caps the
# runner's hard-coded worker count, logs worker output and sets one data.table thread per worker.
dsa_install_cluster_cap <- function(workers, outfile) {
  e <- new.env()
  e$makeCluster <- local({
    n_max <- workers; log <- outfile
    function(spec, ...) {
      n <- min(as.integer(spec), n_max)
      cat(sprintf("Stage 8: makeCluster(%s) -> %d PSOCK workers, 1 data.table thread each\n", spec, n))
      cl <- parallel::makeCluster(n, outfile = log)
      parallel::clusterEvalQ(cl, data.table::setDTthreads(1L))
      cl
    }
  })
  attach(e, name = "dsa_cluster_cap", warn.conflicts = FALSE)
}

# Validate the country files of this run.
dsa_validate_outputs <- function(out_model, expected, started, scen_names) {
  files <- list.files(out_model, pattern = "^model_output_part_.+\\.rds$", full.names = TRUE)
  found <- sub("^model_output_part_(.+)\\.rds$", "\\1", basename(files))
  n_grid <- 4L * 2L * length(20:95) * length(2019:2050)
  logs <- vector("list", length(files)); tot <- vector("list", length(files))
  for (i in seq_along(files)) {
    x <- readRDS(files[i]); setDT(x)
    cols_ok <- all(dsa_mo_cols %in% names(x))
    lg <- data.table(country = found[i], rows = nrow(x), cols_ok = cols_ok, location_ok = FALSE, scen_ok = FALSE,
                     scope_ok = FALSE, bau_ok = FALSE, dup_strata = NA_integer_, neg_dead = NA_integer_,
                     nonfinite_rows = NA_integer_, nonfinite_in = "")
    if (cols_ok) {
      fin <- is.finite(x$well) & is.finite(x$sick) & is.finite(x$dead) & is.finite(x$pop) & is.finite(x$all.mx)
      bau <- x[scenario == "baseline" & year >= 2019]
      lg[, `:=`(
        location_ok = identical(unique(x$location), found[i]),
        scen_ok = setequal(unique(x$scenario), scen_names),
        scope_ok = setequal(unique(x$cause), c("ihd", "istroke", "hstroke", "hhd")) && setequal(unique(x$sex), c("Female", "Male")) &&
          min(x$age) == 20 && max(x$age) == 95 && min(x$year) <= 2019 && max(x$year) == 2050,
        bau_ok = nrow(bau) == n_grid && nrow(unique(bau, by = c("cause", "sex", "age", "year"))) == n_grid &&
          all(is.finite(bau$well) & is.finite(bau$sick) & is.finite(bau$dead) & is.finite(bau$pop) & is.finite(bau$all.mx)),
        dup_strata = nrow(x[fin]) - nrow(unique(x[fin], by = c("scenario", "cause", "sex", "age", "year"))),
        neg_dead = sum(x$dead[fin] < 0),
        nonfinite_rows = sum(!fin),
        nonfinite_in = paste(unique(x$scenario[!fin]), collapse = ","))]
      tot[[i]] <- x[fin & year >= 2019, .(dead = sum(dead)), by = .(scenario, year)]
    }
    logs[[i]] <- lg
  }
  file_log <- rbindlist(logs)
  ftab <- data.table(file = basename(files), country = found, written_this_run = file.mtime(files) >= started,
                     mtime = format(file.mtime(files), "%Y-%m-%d %H:%M:%S"), md5 = dsa_md5(files))
  chk <- function(check, passed, detail = "") data.table(check = check, passed = isTRUE(passed), detail = detail)
  checks <- rbind(
    chk("every expected country has an output file", all(expected %in% found),
        paste(setdiff(expected, found), collapse = ", ")),
    chk("no output file for an unexpected country", all(found %in% expected), paste(setdiff(found, expected), collapse = ", ")),
    chk("every file written by this run (mtime >= stage-7 start)", length(files) > 0 && all(ftab$written_this_run),
        paste(ftab[written_this_run == FALSE, country], collapse = ", ")),
    chk("stage-7 output schema", nrow(file_log) > 0 && all(file_log$cols_ok)),
    chk("location column matches the file name", all(file_log$location_ok)),
    chk("scenarios = the runner's scenario list", all(file_log$scen_ok), paste(scen_names, collapse = ", ")),
    chk("causes, sexes, ages 20-95 and years to 2050", all(file_log$scope_ok)),
    chk("BAU grid 2019-2050 complete, unique and finite", all(file_log$bau_ok)),
    chk("no duplicated strata among finite rows", all(file_log$dup_strata == 0, na.rm = FALSE)),
    chk("no negative deaths", all(file_log$neg_dead == 0, na.rm = FALSE)))
  totals <- rbindlist(c(list(data.table(scenario = character(0), year = integer(0), dead = numeric(0))), tot),
                      use.names = TRUE)[, .(dead = sum(dead)), keyby = .(scenario, year)]
  list(checks = checks, file_log = file_log, files = ftab, totals = totals,
       nonfinite = file_log[nonfinite_rows > 0, .(country, nonfinite_rows, nonfinite_in)])
}

dsa_child_run <- function(spec) {
  started <- Sys.time()
  .libPaths(spec$lib_paths)
  for (pk in spec$packages) suppressPackageStartupMessages(library(pk, character.only = TRUE))
  ge <- globalenv()
  list2env(spec$globals, envir = ge)
  list2env(spec$switches, envir = ge)
  assign("trend_config", spec$trend_config, envir = ge)
  assign("wd_outp", spec$paths$dir, envir = ge)
  setwd(spec$globals$wd_code)                                     # as the master does before its stages
  source(paste0(spec$globals$wd_code, "functions_review_6_100.R"))  # as the master does
  dsa_install_cluster_cap(spec$workers, spec$paths$workers_log)
  cat(sprintf("Stage 8 child: %s%s, started %s\n", spec$name, if (spec$pilot) " [pilot]" else "", format(started)))
  cat(sprintf("  %s = %s\n", c(names(spec$switches), "trend_config$method", "trend_config$cf_share", "wd_outp"),
              c(unlist(spec$switches), spec$trend_config$method, spec$trend_config$cf_share, get("wd_outp", ge))), sep = "")

  # Stage 6: a fresh prospective baseline from the calibrated historical rates.
  source(paste0(spec$globals$wd_code, "6. build_baseline.R"))
  bs <- get("baseline_settings", envir = ge)
  sw <- spec$switches
  if (!identical(bs$trend_method, sw$mortality_trend_method) || !identical(bs$cf_share, spec$trend_config$cf_share) ||
      !identical(bs$run_bgmx_trend, sw$run_bgmx_trend) || !identical(bs$run_CF_trend, sw$run_CF_trend) ||
      !identical(bs$run_CF_trend_80, sw$run_CF_trend_80) || !identical(bs$run_CF_trend_ihme, sw$run_CF_trend_ihme))
    stop("the stage-6 baseline does not record this analysis's switches")
  if (!identical(bs$calibration_run_id, spec$calibration_run_id))
    stop("the stage-6 baseline used calibration ", bs$calibration_run_id, ", expected ", spec$calibration_run_id)
  if (!setequal(bs$trend_files$file, basename(spec$trend_files)))
    stop("the stage-6 baseline read trend files ", paste(bs$trend_files$file, collapse = ", "), ", expected ",
         paste(basename(spec$trend_files), collapse = ", "))
  # Inputs that no trend switch touches, for comparison across the analyses (and the IR check:
  # IR is never trended, only lowered by the final probability guard).
  b <- get("b_rates", envir = ge); yr_obs <- spec$globals$cal_config$obs_end
  ir <- b[year > yr_obs, .(location, sex, age, cause, year, IR)][b[year == yr_obs, .(location, sex, age, cause, IR0 = IR)],
                                                                     on = .(location, sex, age, cause)]
  invariant <- list(
    nontrend_columns = dsa_fingerprint(b[, .(location, year, sex, age, cause, Nx, pop, PREVt0, newcases)],
                                       c("location", "year", "sex", "age", "cause")),
    historical_rows  = dsa_fingerprint(b[year <= yr_obs], c("location", "year", "sex", "age", "cause")),
    data_in = dsa_fingerprint(get("data.in", envir = ge)), inc = dsa_fingerprint(get("inc", envir = ge)),
    ir_projection_raised = ir[IR > IR0 * (1 + 1e-12), .N], ir_projection_lowered = ir[IR < IR0, .N],
    guard_well_rows_projection = bs$guard_log[period == "projection", n_well_gt1])
  rm(b, ir)
  if (invariant$ir_projection_raised > 0) stop("projected IR exceeds its ", yr_obs, " value in ", invariant$ir_projection_raised, " rows")
  di <- get("data.in", envir = ge)
  miss <- setdiff(spec$expected_countries, unique(di$location))
  if (length(miss)) stop("expected countries missing from the stage-6 data.in: ", paste(miss, collapse = ", "))
  if (spec$pilot) assign("data.in", di[location %in% spec$countries], envir = ge)   # as --stage7-countries does
  rm(di)

  # Stage 7: the unchanged runner, writing under wd_outp/out_model/.
  runner <- paste0(spec$globals$wd_code, dsa_runner_name)
  runner_md5 <- dsa_md5(runner)
  stage7_started <- Sys.time()
  source(runner)
  stage7_completed <- Sys.time()
  scen_names <- names(get("scenarios", envir = ge))
  if (exists("results_list", envir = ge)) rm("results_list", envir = ge)
  invisible(gc(FALSE))

  val <- dsa_validate_outputs(spec$paths$out_model, spec$expected_countries, stage7_started, scen_names)
  # Provenance: the code, inputs and trend files hashed at launch are unchanged after the run.
  same <- vapply(c("code", "inputs", "trends"), function(k) {
    t0 <- spec$md5_at_launch[[k]]; identical(dsa_md5(t0$path), t0$md5)
  }, logical(1))
  val$checks <- rbind(val$checks, data.table(check = "code, inputs and trend files unchanged since launch",
                                             passed = all(same), detail = paste(names(same)[!same], collapse = ", ")))
  ok <- all(val$checks$passed)
  sig <- tempfile(); saveRDS(list(spec$name, bs$baseline_id, runner_md5, val$files$md5), sig)
  run_id <- paste0(format(stage7_started, "%Y%m%d-%H%M%S"), "-", substr(dsa_md5(sig), 1, 8)); unlink(sig)
  m <- list(
    analysis = spec$name, table_label = spec$table_label, description = spec$description, pilot = spec$pilot,
    status = if (!ok) "failed" else if (spec$pilot) "pilot" else "complete",
    run_id = run_id, started = format(started, "%Y-%m-%d %H:%M:%S %Z"),
    stage7_started = format(stage7_started, "%Y-%m-%d %H:%M:%S %Z"), completed = format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z"),
    switches = spec$switches, trend_config = spec$trend_config[c("method", "cf_share")],
    calibration_run_id = bs$calibration_run_id, baseline = bs, invariant = invariant,
    runner_md5 = runner_md5, master_md5 = spec$md5_at_launch$code[basename(path) == "0. master.R", md5],
    code_files = spec$md5_at_launch$code, input_files = spec$md5_at_launch$inputs,
    trend_files = spec$md5_at_launch$trends, foresight = spec$foresight,
    production = spec$production, expected_countries = spec$expected_countries, countries = spec$countries,
    scenarios = scen_names, reporting_window = spec$reporting_window, workers = spec$workers,
    files = val$files, validation = val[c("checks", "file_log", "nonfinite")], totals = val$totals,
    stage7_minutes = as.numeric(difftime(stage7_completed, stage7_started, units = "mins")),
    session = list(R = R.version.string, packages = spec$packages))
  saveRDS(m, spec$paths$manifest)
  print(val$checks)
  if (nrow(val$nonfinite)) { cat("Rows with non-finite states (left out by the artifact builder, as in the main run):\n"); print(val$nonfinite) }
  cat(sprintf("Stage 8 child: %s status %s, run %s, %d files, stage 7 %.1f min\n", spec$name, m$status, run_id,
              nrow(val$files), m$stage7_minutes))
  if (!ok) stop("validation failed: ", paste(val$checks[passed == FALSE, check], collapse = "; "))
  invisible(m)
}

dsa_child_main <- function(spec_file) {
  spec <- readRDS(spec_file)
  ok <- tryCatch({ dsa_child_run(spec); TRUE }, error = function(e) {
    msg <- conditionMessage(e)
    cat("Stage 8 child ERROR:", msg, "\n")
    if (!file.exists(spec$paths$manifest) || !identical(readRDS(spec$paths$manifest)$status, "failed"))
      saveRDS(list(analysis = spec$name, pilot = spec$pilot, status = "failed", error = msg, switches = spec$switches,
                   trend_config = spec$trend_config[c("method", "cf_share")],
                   completed = format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z")), spec$paths$manifest)
    FALSE
  })
  quit(save = "no", status = if (ok) 0L else 1L)
}

# Entry point of the child process: Rscript "code/8.0_sensitivity_helpers.R" --dsa-child <spec.rds>
local({
  a <- commandArgs(trailingOnly = TRUE)
  # No package is attached here: dsa_child_run() attaches the parent's packages in its order.
  if (length(a) == 2L && identical(a[1], "--dsa-child")) dsa_child_main(a[2])
})
