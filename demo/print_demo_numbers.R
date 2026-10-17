# print_demo_numbers.R
#
# Prints every number that demo/README.md quotes, by calling the same functions the app calls
# (app/qc.R, prep.R, sim.R, forecast.R) on
# data/baseline.csv, data/planted_shift.csv and data/edge_case.csv, with the app's default settings.
# No statistics are written here: this file only loads, calls and prints.
#
# Run from the repo root:   Rscript demo/print_demo_numbers.R
# It takes a few minutes (the planted_shift file is large). It starts no web server.

repo <- normalizePath(getwd(), winslash = "/")
if (!file.exists(file.path(repo, "app", "qc.R"))) stop("Run this from the repo root: Rscript demo/print_demo_numbers.R")

# Source the app files in the order app.R does (their working directory is the app folder).
setwd(file.path(repo, "app"))
for (f in c("qc.R", "prep.R", "sim.R", "forecast.R")) {
  source(f)
}
setwd(repo)

# App defaults (sidebar): stale_limit 2, early-warning 2, coverage 0.95, baseline share 0.5,
# detour 1.3 (the forecast's vans on the way).
STALE <- 2; WARN_K <- 2; MIN_COV <- 0.95; BASE_SHARE <- 0.5; DETOUR <- 1.3

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
    say("Out-of-control weekdays (", sum(d$out_of_control, na.rm = TRUE), " of ", nrow(d), "): ",
        paste(S$att$date[which(d$out_of_control)], collapse = ", "))
    say("Centre line ", sprintf("%.2f%%", 100 * d$center[1]), "; first-day limits LCL ", sprintf("%.2f%%", 100 * d$lcl[1]),
        ", UCL ", sprintf("%.2f%%", 100 * d$ucl[1]))
    if (kind == "return") show(data.frame(date = S$att$date, failures_over_n = paste0(d$failures, "/", d$n),
                                          percent = round(100 * d$p, 2), UCL_pct = round(100 * d$ucl, 2),
                                          signal = signal_label(d$out_of_control, FALSE)))
  }
  head2("Quality: windows for the c chart (fixed station set, minimum coverage)")
  w <- window_table(S$grids, S$fixed, S$dates, MIN_COV)
  inc <- w[w$included, ]
  say("Fixed station set: ", length(S$fixed), " stations; windows included: ", nrow(inc), " of ", nrow(w))
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
  say("Baseline = first ", baseline_count(nrow(inc), BASE_SHARE), " windows. c chart note: '", res$note, "'")
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

forecast_demo <- function(S, date, minute, R = 2000, seed = 1) {
  head2(paste("Forecast Now, t0 =", date, sprintf("%02d:%02d", 7 + minute %/% 60, minute %% 60), "R =", R, "seed", seed))
  params <- sim_params(detour = DETOUR, speed_kmh = 20)
  f <- forecast_now(S$sc, S$grids, date, S$dates, minute, R = R, seed = seed, params = params)
  if (!f$ok) { say("No forecast: ", f$reason); return(invisible()) }
  say("Stations forecast: ", sum(!is.na(f$table$p_rent_10)), " of ", nrow(f$table), " from ", length(f$source_days),
      " earlier weekdays (", f$n_attempts, " attempts)")
  ft <- forecast_table_display(f)
  keep <- c(1, 2, grep("-unusable) within 30", names(ft), fixed = TRUE), ncol(ft))
  show(head(ft[, keep], 5), na = "n/a")   # app column order: sorted by highest 30-minute risk
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
forecast_demo(B, "2026-10-05", 30)

head1("PLANTED_SHIFT (data/planted_shift.csv)")
P <- load_all("planted_shift")
say("Dates: ", length(P$dates), " weekdays; day 10 = ", P$dates[10], ", day 11 = ", P$dates[11])
qw_p <- quality(P)
c_chart_demo(P, qw_p$windows)

head1("EDGE_CASE (data/edge_case.csv)")
E <- load_all("edge_case")
say("Dates: ", paste(E$dates, collapse = ", "))
say("After validation: ", nrow(E$sc$stations), " stations, ", nrow(E$sc$status), " status rows, ", nrow(E$sc$attempts),
    " attempts, ", nrow(E$sc$tasks), " tasks")
overview(E, E$dates[1])
data_issues(E)
qw_e <- quality(E)
c_chart_demo(E, qw_e$windows)
forecast_demo(E, E$dates[1], 5)

say("")
say("Done in ", round(as.numeric(difftime(Sys.time(), t_start, units = "secs"))), " seconds.")
