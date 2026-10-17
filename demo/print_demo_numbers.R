# print_demo_numbers.R
#
# Prints every number that demo/README.md quotes, by calling the same functions the app calls
# (app/qc.R, prep.R, survival.R, forecast.R, reliability.R, faulttree.R, sim.R, tasks.R) on
# data/baseline.csv, data/planted_shift.csv and data/edge_case.csv, with the app's default settings.
# No statistics are written here: this file only loads, calls and prints.
#
# Run from the repo root:   Rscript demo/print_demo_numbers.R
# It takes a few minutes (the planted_shift file is large). It starts no web server.

repo <- normalizePath(getwd(), winslash = "/")
if (!file.exists(file.path(repo, "app", "qc.R"))) stop("Run this from the repo root: Rscript demo/print_demo_numbers.R")

# Source the app files in the order app.R does (their working directory is the app folder).
setwd(file.path(repo, "app"))
for (f in c("qc.R", "survival.R", "prep.R", "sim.R", "forecast.R", "reliability.R", "faulttree.R", "tasks.R")) {
  source(f)
}
setwd(repo)

# App defaults (sidebar): stale_limit 2, early-warning 2, coverage 0.95, baseline share 0.5,
# target fill 0.5, van capacity 12, detour 1.3.
STALE <- 2; WARN_K <- 2; MIN_COV <- 0.95; BASE_SHARE <- 0.5; FILL <- 0.5; CAPACITY <- 12; DETOUR <- 1.3

say <- function(...) cat(..., "\n", sep = "")
head1 <- function(x) { say(""); say("==================== ", x, " ====================") }
head2 <- function(x) { say(""); say("---- ", x, " ----") }
show <- function(df, ...) print(as.data.frame(df, stringsAsFactors = FALSE), row.names = FALSE, ...)

load_all <- function(name) {
  sc <- load_scenario(file.path(repo, "data", paste0(name, ".csv")))
  d <- scenario_dates(sc$status, sc$attempts)
  g <- build_day_grids(sc$status, sc$stations, d, STALE)
  list(name = name, sc = sc, dates = d, grids = g, att = attempts_by_day(sc$attempts, d),
       fixed = fixed_station_set(sc$status, sc$stations, d))
}

overview <- function(S, date, minute = 5) {
  head2(paste("Overview KPIs", date))
  grid <- set_warning_threshold(S$grids[[date]], WARN_K)
  counts <- grid_window_counts(grid, NULL, date)
  att <- S$att[S$att$date == date, ]
  k <- kpi_summary(counts, att)
  say("Either-unusable share: ", sprintf("%.1f%%", k$either_share_pct), " (", counts$either_min, " of ", k$known, " known station-minutes)")
  say("Rent failure: ", sprintf("%.1f%%", k$rent_fail_pct), " (", k$rent_fail, "/", k$rent_n, ")")
  say("Return failure: ", if (is.na(k$return_fail_pct)) "n/a" else sprintf("%.1f%%", k$return_fail_pct), " (", k$return_fail, "/", k$return_n, ")")
  say("Known minutes: ", k$known, "; Unknown minutes: ", k$unknown, "; Coverage: ", sprintf("%.1f%%", 100 * k$coverage))
  head2(paste("Overview ranking (top 5), ", date))
  r <- station_table(rank_stations(unusable_summary(grid)), S$sc$stations)
  r$rank <- seq_len(nrow(r))
  show(head(r[, c("rank", "station_id", "station", "either_unusable_min", "warning_min", "known_min", "coverage_pct")], 5), digits = 1)
}

data_issues <- function(S) {
  head2("Data issues (Overview, bottom panel)")
  say("Rows per record type:"); show(table_health(S$sc))
  s <- issue_summary(S$sc$issues)
  say("Issues by record type and rule:"); if (nrow(s) == 0) say("No data issues found.") else show(s)
  if (nrow(S$sc$issues) > 0) { say("Issue rows:"); show(issue_detail(S$sc$issues, 200)) }
}

quality <- function(S, usl = NA) {
  head2("Quality: p charts (rent, return)")
  for (kind in c("rent", "return")) {
    a <- S$att
    res <- p_chart(a[[paste0(kind, "_fail")]], a[[paste0(kind, "_n")]],
                   baseline = baseline_flags(a[[paste0(kind, "_n")]] > 0, BASE_SHARE))
    d <- res$data
    say(kind, " p chart: baseline = first ", baseline_count(sum(a[[paste0(kind, "_n")]] > 0), BASE_SHARE), " weekdays; note: '", res$note, "'")
    dd <- res$dispersion
    if (is.na(dd$ratio)) say("Dispersion: ", dd$note) else
      say("Dispersion: X2 = ", sprintf("%.1f", dd$chi_sq), " on ", dd$df, " df, ratio = ", sprintf("%.2f", dd$ratio),
          ", p ", format_p(dd$p_value), "; warning = ", dd$warning, "; ", dd$note)
    say("Out-of-control weekdays (", sum(d$out_of_control, na.rm = TRUE), " of ", nrow(d), "): ",
        paste(S$att$date[which(d$out_of_control)], collapse = ", "))
    say("Centre line ", sprintf("%.2f%%", 100 * d$center[1]), "; first-day limits LCL ", sprintf("%.2f%%", 100 * d$lcl[1]),
        ", UCL ", sprintf("%.2f%%", 100 * d$ucl[1]))
    if (kind == "return") show(data.frame(date = S$att$date, failures_over_n = paste0(d$failures, "/", d$n),
                                          percent = round(100 * d$p, 2), UCL_pct = round(100 * d$ucl, 2),
                                          signal = signal_label(d$out_of_control, dd$warning)))
  }
  head2("Quality: I-MR chart (either-unusable share, fixed station set)")
  w <- window_table(S$grids, S$fixed, S$dates, MIN_COV)
  inc <- w[w$included, ]
  say("Fixed station set: ", length(S$fixed), " stations; windows included: ", nrow(inc), " of ", nrow(w))
  if (nrow(inc) > 0) {
    res <- imr_chart(inc$either_share_pct, baseline = baseline_flags(rep(TRUE, nrow(inc)), BASE_SHARE))
    d <- res$data
    say("I-MR note: '", res$note, "'")
    say("Baseline = first ", baseline_count(nrow(inc), BASE_SHARE), " windows. Centre ", sprintf("%.2f", d$center[1]),
        "; UCL ", sprintf("%.2f", d$ucl[1]), "; LCL ", sprintf("%.2f", d$lcl[1]))
    show(data.frame(date = inc$window, share_pct = round(d$x, 2), UCL = round(d$ucl, 2), LCL = round(d$lcl, 2),
                    signal = ifelse(is.na(d$out_of_control), "not assessed", ifelse(d$out_of_control, "OUT OF CONTROL", "in control"))))
  }
  if (nrow(w) > nrow(inc)) { say("Excluded windows:"); show(w[!w$included, c("window", "known", "unknown", "coverage", "reason")]) }
  invisible(list(windows = w, inc = inc))
}

c_chart_demo <- function(S, w) {
  head2("Quality: c chart (anomaly onsets per window)")
  inc <- w[w$included, ]
  if (nrow(inc) == 0) { say("No included window."); return(invisible()) }
  counts <- onset_window_table(S$grids, S$fixed, inc$window)$onsets
  res <- c_chart(counts, baseline = baseline_flags(rep(TRUE, nrow(inc)), BASE_SHARE))
  d <- res$dispersion
  say("c chart note: '", res$note, "'")
  say("Dispersion: ", if (is.na(d$ratio)) d$note else paste0("variance ", sprintf("%.2f", d$variance), " / mean ",
                                                             sprintf("%.2f", d$mean), " = ", sprintf("%.2f", d$ratio), "; ", d$note))
  show(c_chart_table(inc, res), na = "n/a")
}

xbar_demo <- function(S, usl) {
  head2("Quality: X-bar/R of van response time, and capability")
  sub <- response_subgroups(S$sc$tasks, S$dates)
  say("Subgroups (windows with 3 completed tasks): ", nrow(sub$values))
  if (nrow(sub$values) == 0) { say("none"); return(invisible()) }
  res <- xbar_r_chart(sub$values, baseline = baseline_flags(rep(TRUE, nrow(sub$values)), BASE_SHARE))
  say("X-bar/R note: '", res$note, "'")
  show(head(xbar_r_table(sub, res), 3), na = "n/a")
  say("(first 3 of ", nrow(sub$values), " subgroup rows shown)")
  cap <- capability_indices(res, usl = usl, lsl = NA_real_)
  say("sigma-hat = R-bar/d2 = ", sprintf("%.3f", cap$sigma_hat), " min; X-double-bar = ", sprintf("%.3f", cap$xbarbar), " min; USL = ", usl, " (example input)")
  show(capability_table(cap), na = "n/a")
  nc <- normality_check(as.vector(sub$values)); say("Normality check: ", nc$note)
}

km_demo <- function(S, label, days, failure = "either") {
  h <- km_history(S$grids, days, failure)
  head2(paste("Kaplan-Meier History,", label, "(", failure, ")"))
  say("Weekdays: ", length(h$dates), " (", h$dates[1], " to ", h$dates[length(h$dates)], ")")
  show(km_counts_table(h))
  if (h$summary$n > 0) { show(km_horizon_table(h$summary), na = "n/a"); show(km_mean_table(h$summary), na = "n/a") }
  else say("No estimate: ", h$summary$reason)
}

forecast_demo <- function(S, date, minute, R = 2000, seed = 1) {
  head2(paste("Forecast Now, t0 =", date, sprintf("%02d:%02d", 7 + minute %/% 60, minute %% 60), "R =", R, "seed", seed))
  params <- sim_params(vans = default_van_count(S$sc$tasks), detour = DETOUR, speed_kmh = 20)
  f <- forecast_now(S$sc, S$grids, date, S$dates, minute, R = R, seed = seed, params = params)
  if (!f$ok) { say("No forecast: ", f$reason); return(invisible()) }
  say("Stations forecast: ", sum(!is.na(f$table$p_rent_10)), " of ", nrow(f$table), " from ", length(f$source_days),
      " earlier weekdays (", f$n_attempts, " attempts)")
  ft <- forecast_table_display(f)
  keep <- c(1, 2, grep("-unusable) within 30", names(ft), fixed = TRUE), ncol(ft))
  show(head(ft[, keep], 5), na = "n/a")   # app column order: sorted by highest 30-minute risk
}

diag_demo <- function(S, label, dates) {
  head2(paste("Diagnosis, scope:", label))
  a <- scope_attempts(S$sc$attempts, dates); g <- pooled_grid(S$grids, dates)
  for (type in c("rent", "return")) {
    ft <- fault_tree(a, type, g)
    say(type, " failed: ", fault_summary_text(ft))
    show(fault_action_display(ft), na = "n/a")
    show(fault_reason_display(ft), na = "n/a")
  }
}

improvement_demo <- function(S, date, n_seeds = 30, base_seed = 1) {
  head2(paste("Improvement,", date, "R =", n_seeds, "seeds, base seed", base_seed))
  params <- sim_params(vans = default_van_count(S$sc$tasks), van_capacity = CAPACITY, target_fill = FILL, detour = DETOUR)
  r <- compare_policies(S$sc, S$grids, date, S$dates, n_seeds = n_seeds, base_seed = base_seed, params = params)
  if (!r$ok) { say("No comparison: ", r$reason); return(invisible()) }
  say("Seeds ", min(r$seeds), " to ", max(r$seeds), "; ", length(r$stations), " stations; ", r$params$vans, " van(s); true attempts ",
      r$true_attempts, "; predictive history = ", length(r$demand_days), " earlier weekday(s), ", r$demand_attempts, " attempts")
  show(policy_summary_display(r$summary), na = "n/a")
  p <- paired_table_display(r$paired)
  say("Paired differences (first minus second; positive = second better), primary rows:")
  show(p[p$role == "primary", c("pair", "metric", "seeds_used", "mean_difference", "CI_low", "CI_high", "CI_level")], na = "n/a")
  say("Primary intervals that contain 0: ",
      sum(r$paired$role == "primary" & r$paired$ci_low <= 0 & r$paired$ci_high >= 0, na.rm = TRUE), " of ", sum(r$paired$role == "primary"))
}

rebalance_demo <- function(S, date, minute) {
  head2(paste("Rebalancing,", date, sprintf("%02d:%02d", 7 + minute %/% 60, minute %% 60)))
  grid <- set_warning_threshold(S$grids[[date]], WARN_K)
  summ <- rank_stations(unusable_summary(grid))
  st <- state_at(grid, minute)
  plan <- rebalance_plan(st, S$sc$stations, rank = summ[, c("station_id", "rank")], target_fill = FILL,
                         van_capacity = CAPACITY, detour = DETOUR)
  mv <- plan$moves
  if (nrow(mv) == 0) say("No move is recommended at this minute.") else
    show(data.frame(from = mv$from_station, to = mv$to_station, bikes = as.integer(round(mv$quantity)), est_distance_km = mv$est_distance_km))
  ex <- plan$excluded
  if (nrow(ex) == 0) say("Stations left out: none.") else {
    ex <- explain_exclusion(ex, S$sc$status, st$minute[1], STALE, S$sc$issues)
    say("Stations left out of moves:"); show(data.frame(station_id = ex$station_id, reason = ex$detail, recommendation = ex$recommendation))
  }
  invisible(plan)
}

task_demo <- function(plan, date, minute) {
  head2("Rebalancing: simulated task status demo")
  mv <- plan$moves
  if (nrow(mv) == 0) { say("No moves, so no tasks."); return(invisible()) }
  at0 <- as.POSIXct(paste(date, "07:00:00"), tz = APP_TZ) + 60 * minute
  tk <- new_tasks_from_plan(mv, at0)
  say("Created ", nrow(tk), " planned task(s): ", paste(tk$task_id, collapse = ", "))
  show(tasks_display(tk)[1:3, c("task_id", "status", "from", "to", "planned_bikes")])
  id <- tk$task_id[1]
  t <- function(hhmm) task_time_parse(date, hhmm)
  r1 <- task_transition(tk, id, "assigned", van_id = "V1", at = t("07:05")); say(r1$message)
  r2 <- task_transition(r1$tasks, id, "completed", at = t("07:30"), actual_quantity = 1); say(r2$message)
  show(tasks_display(r1$tasks)[1:3, c("task_id", "status", "from", "to", "planned_bikes", "van_id", "assigned")])
}

# ---------------------------------------------------------------- run
t_start <- Sys.time()

head1("BASELINE (data/baseline.csv)")
B <- load_all("baseline")
say("Dates: ", length(B$dates), " weekdays, ", B$dates[1], " to ", B$dates[length(B$dates)])
say("After validation: ", nrow(B$sc$stations), " stations, ", nrow(B$sc$status), " status rows, ", nrow(B$sc$attempts),
    " attempts, ", nrow(B$sc$tasks), " tasks")
overview(B, "2026-09-21")
data_issues(B)
qw <- quality(B)
c_chart_demo(B, qw$windows)
xbar_demo(B, usl = 12)
km_demo(B, "all weekdays", B$dates)
forecast_demo(B, "2026-10-05", 30)
improvement_demo(B, "2026-10-05")
plan_b <- rebalance_demo(B, "2026-09-21", 5)
task_demo(plan_b, "2026-09-21", 5)

head1("PLANTED_SHIFT (data/planted_shift.csv)")
P <- load_all("planted_shift")
say("Dates: ", length(P$dates), " weekdays; day 10 = ", P$dates[10], ", day 11 = ", P$dates[11])
quality(P)
diag_demo(P, "all weekdays", P$dates)
diag_demo(P, "2026-10-05 only", "2026-10-05")
km_demo(P, "days 1-10 (up to 2026-10-02)", km_days(P$dates, "upto", P$dates[10]))
km_demo(P, "all 20 weekdays", P$dates)

head1("EDGE_CASE (data/edge_case.csv)")
E <- load_all("edge_case")
say("Dates: ", paste(E$dates, collapse = ", "))
say("After validation: ", nrow(E$sc$stations), " stations, ", nrow(E$sc$status), " status rows, ", nrow(E$sc$attempts),
    " attempts, ", nrow(E$sc$tasks), " tasks")
overview(E, E$dates[1])
data_issues(E)
rebalance_demo(E, E$dates[1], 12)
quality(E)

say("")
say("Done in ", round(as.numeric(difftime(Sys.time(), t_start, units = "secs"))), " seconds.")
