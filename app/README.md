# Rush Hour Autopilot: app folder and function reference

An R Shiny dashboard for the municipal bikeshare dispatcher's weekday morning rush (07:00-10:00
New York). All data are simulated. Overview, run steps and statistical limits are in the
[main README](../README.md); formulas and known answers are in [../docs/methods.md](../docs/methods.md).

Rule of the code: every statistic is a plain, tested function (mostly in `qc.R`). `prep.R` only
shapes data, `plots.R` only draws, `app.R` is screen and wiring only.

## The four-script contract

Run all of these from the repo root.

| File | Job | Command |
|---|---|---|
| `testme.R` | start the app locally | `Rscript app/testme.R`, then open http://127.0.0.1:5763/ |
| `manifestme.R` | write `manifest.json` for Posit Connect (bundles `app.R`, every file it `source()`s, and `app/data/*.csv.gz`) | `Rscript app/manifestme.R` (needs `rsconnect`) |
| `deployme.R` | push to the course Posit Connect server from your machine | `Rscript app/deployme.R` (needs `rsconnect`; reads `CONNECT_SERVER` and `CONNECT_API_KEY` from environment variables, never from a file) |
| `README.md` | this page | |

Also: `make_app_data.R` writes gzip copies of `data/*.csv` into `app/data/` (Connect receives only
files inside `app/`). Run `Rscript app/make_app_data.R`, then `Rscript app/manifestme.R`, whenever
`data/` changes; a test checks the copies match.

The GitHub Actions workflow `.github/workflows/deploy-shiny-r.yml` redeploys on every push to
`main`, using the repo secrets `CONNECT_SERVER` and `CONNECT_API_KEY`.

## File layout

| File | Contents |
|---|---|
| `app.R` | UI (7 tabs, sidebar) and `server`; sources the files below |
| `qc.R` | loader and validator, station-minute grid, all control charts, capability, rebalancing plan, paired intervals |
| `prep.R` | data shaping and display tables (no statistics) |
| `plots.R` | ggplot2 drawing helpers (no statistics) |
| `survival.R` | Kaplan-Meier |
| `sim.R` | demand estimate, seeded policy simulation, policy comparison |
| `forecast.R` | current-state risk forecast (Poisson, day bootstrap) |
| `reliability.R` | empirical availability and reliability |
| `faulttree.R` | failure classification and fault-tree numbers |
| `tasks.R` | simulated task statuses (session only) |
| `data/` | bundled scenario copies (`*.csv.gz`) |

## Function reference

Conventions: **NA rules** say when a value cannot be estimated; it then becomes `NA` with a reason,
never `Inf`, and valid observed values (counts, means, centre lines) are still returned. Unknown
(stale) minutes are never counted as usable or unusable. Wrappers and tiny helpers are in the file
headers; only the functions that carry a statistic or a rule are listed.

### qc.R

| Function | Input -> output | Statistic and NA rules |
|---|---|---|
| `parse_ts(x)` | ISO 8601 text with offset -> UTC time | UTC = local - offset; unparseable -> NA (row-level) |
| `read_scenario(path)` | CSV path -> data frame with `table` column | stops if missing/unreadable/no `table` column |
| `validate_scenario(sc)` | long-form data -> list(stations, status, attempts, tasks, issues) | structural problems stop; bad rows are rejected or flagged in `issues`, never replaced by 0 |
| `load_scenario(path)` | path -> same list | read + validate |
| `build_grid(status, stations, date, ...)` | cleaned tables -> one row per station x minute | latest snapshot at or before the minute; older than `stale_limit` -> unknown (state NA) |
| `unusable_summary(grid)` | grid -> per-station minute counts | rent/return/either-unusable and early-warning minutes, coverage = known/(known+unknown) |
| `window_summary(known, unknown, either_min, ...)` | counts per window -> coverage and `included` | included when coverage >= `min_coverage` |
| `p_chart(failures, n, baseline)` | counts -> limits and signals | p-bar +/- 3 sqrt(p-bar(1-p-bar)/n_i), capped to [0,1]; rules 1 and 4; NA limits if p-bar is 0 or 1 or fewer than 2 baseline subgroups |
| `p_dispersion(failures, n)` | baseline counts -> Pearson X2/df, p-value, warning | warning when ratio > 1.5; NA if fewer than 2 subgroups or p-bar is 0 or 1 |
| `imr_chart(x, baseline)` | values -> I and MR limits | sigma-hat = MR-bar/1.128; MR UCL = 3.267 MR-bar; NA limits if MR-bar = 0 or fewer than 2 baseline points |
| `count_onsets(grid, station_ids)` | grid -> number | usable minute followed by unusable minute, both known; not across unknown gaps |
| `c_chart(counts, baseline)` | counts -> limits | c-bar +/- 3 sqrt(c-bar), LCL >= 0; NA if c-bar = 0 or fewer than 2 windows |
| `c_dispersion(counts)` | counts -> variance/mean | warning when > 1.5; NA if mean 0 or fewer than 2 windows |
| `response_subgroups(tasks, dates, ...)` | tasks -> matrix of first 3 completed response times per window | response = arrived_at - assigned_at (min); windows with fewer than 3 are dropped and listed |
| `xbar_r_chart(values, baseline)` | matrix (rows = subgroups of 3) -> limits | A2, D3, D4, sigma-hat = R-bar/d2 (not the overall SD); NA if R-bar = 0 or fewer than 2 baseline subgroups |
| `capability_indices(xbr, usl, lsl)` | chart + operator spec limits -> Cpu, Cpl, Cp, Cpk | Cpu = (USL - X-double-bar)/(3 sigma-hat); NA with reason if no USL, chart not in control, R-bar = 0, or USL <= LSL |
| `normality_check(x)` | numbers -> Shapiro-Wilk W, p | NA unless 3 <= n <= 5000 and not all equal |
| `haversine_km(lat1, lon1, lat2, lon2)` | degrees -> km | great-circle distance |
| `rebalance_plan(state, stations, rank, ...)` | latest state -> list(moves, excluded, unmet) | greedy heuristic; target = round(target_fill x capacity); quantity = min(source surplus, destination deficit, free docks, van capacity); closed stations are excluded with a recommendation |
| `paired_diff_ci(d, conf, family_size)` | paired differences -> mean and t interval | level 1 - (1-conf)/family_size (Bonferroni); n < 2 -> mean kept, interval NA |

### prep.R (shaping and display, no statistics)

| Function | Job |
|---|---|
| `scenario_dates`, `window_bounds`, `attempts_by_day` | weekdays of the scenario, window times, attempt and failure counts per day |
| `fixed_station_set`, `build_day_grids`, `window_table` | stations present every weekday, one grid per day, per-window coverage via `window_summary` |
| `state_at`, `rank_stations`, `station_table`, `kpi_summary` | one-day state, ranking (unusable + early-warning minutes), KPIs |
| `hour_station_matrix`, `pareto_order` | inputs for the heatmap and Pareto |
| `baseline_count`, `baseline_flags` | which weekdays set the limits (default first half) |
| `builtin_scenarios`, `default_scenario_path` | locate the bundled `app/data/*.csv.gz` scenarios |
| `table_health`, `issue_summary`, `issue_detail` | data-issue messages |
| `c_chart_table`, `xbar_r_table`, `capability_table` | tables for the Quality tab |
| `paired_table_display`, `policy_summary_display` | tables for Improvement |
| `km_*`, `forecast_*`, `reliability_display`, `fault_*_display`, `tasks_display` | text and tables for the History, Now, reliability, Diagnosis and task views |

### plots.R (drawing only)

`plot_trend`, `plot_heatmap`, `plot_pareto`, `plot_p`, `plot_i`, `plot_mr`, `plot_c`, `plot_xbar`,
`plot_r`, `plot_response_hist`, `plot_km`, `plot_forecast_risk`, `plot_fault_tree`,
`plot_paired_diff`, `plot_paired_diffs`. Each takes already computed numbers and returns a ggplot.

### survival.R

| Function | Input -> output | Statistic and NA rules |
|---|---|---|
| `station_day_obs(grid, failure)` | one day's grid -> time to first failure, event/censored | origin 07:00 at a station usable then; censored at 10:00 or at an unknown gap; others excluded and listed |
| `km_fit(time, event, conf)` | times -> Kaplan-Meier table | Greenwood variance; interval NA before the first failure and where S = 0 |
| `km_at(fit, t)` | curve at times t | NA with reason beyond the last observed time while S > 0 |
| `km_rmst(fit, tau)` | curve -> restricted mean (minutes) | NA beyond the last time if the curve has not reached 0 |
| `km_summary(time, event, ...)` | -> F(10/20/30) = 1 - S, RMST, MTTF | MTTF only if the curve reaches 0 |
| `km_history(grids, dates, failure, ...)` | per-day grids -> pooled observations and summary | station-days treated as independent |

### forecast.R

| Function | Input -> output | Statistic and NA rules |
|---|---|---|
| `forecast_rates(...)`, `forecast_day_counts(...)`, `forecast_rates_from_counts(...)` | attempts + grids -> Poisson rate per station, type, 15-min bin | attempts / known station-minutes over weekdays strictly before the date; 0 is valid |
| `forecast_simulate(world, lambda, ...)` | state + rates -> P(unusable within 10/20/30 min) and its simulation SE | Monte Carlo, SE = sqrt(p(1-p)/R); event includes the state at t0; seeded |
| `forecast_in_transit(tasks, stations, t0, params)` | task log -> vans on the way | uses only information at or before t0 |
| `forecast_bootstrap(counts, world, ...)` | -> 2.5-97.5 percentile range of p over B resampled rate sets | resamples source days with replacement; range collapses if all days are identical |
| `forecast_now(sc, grids, date, dates, minute, R, seed, ...)` | scenario -> table per station | NA with reason if the start state is stale/unknown or there is no earlier weekday; the three uncertainty sources are reported separately |
| `forecast_uncertainty(boot)` | -> text of the three sources | demand randomness, simulation error, parameter uncertainty |

### sim.R

| Function | Input -> output | Statistic and NA rules |
|---|---|---|
| `sim_params(...)` | -> parameter list | vans 2, capacity 12, target fill 0.5, detour 1.3, speed 20 km/h, stop 2 min, 0.1 min/bike, risk threshold 0.5 (all demo assumptions) |
| `sim_world(state0, stations)` | 07:00 state -> world | flags stay at their 07:00 values |
| `estimate_demand(attempts, grids, source_days, station_ids)` | -> rates per station x type x bin | attempts / known minutes; a bin with no known minute uses the station's pooled rate |
| `make_demand_stream(lambda, station_ids, seed)` | -> rider events for one seed | Poisson counts; same stream for every policy |
| `van_pickup_amount`, `van_dropoff_amount` | -> bikes moved | pickup min(planned, bikes there, van free); drop-off min(load, free docks) |
| `predictive_risk_table(world, lambda)`, `predictive_risk(tab, minute, bikes)` | -> exact 30-minute risk per station | Markov chain, no random numbers |
| `run_policy(world, stream, policy, params, ...)` | -> metrics for one run | policies none, reactive, predictive; primary metric = either-unusable station-minutes; bikes are conserved at every event (checked) |
| `recovery_episodes(unusable)` | -> recovery durations | open episodes at 10:00 are censored, counted not averaged |
| `paired_table(diffs)`, `paired_tables(...)` | per-seed differences -> intervals | primary: Bonferroni 98.333% t interval (family of 3); others exploratory, unadjusted 95%; n < 2 -> interval NA |
| `compare_policies(sc, grids, date, dates, n_seeds, base_seed, params)` | scenario -> per-seed results, summary, paired table | true demand = that morning's own rates; predictive policy sees only earlier weekdays; `ok = FALSE` with a reason if there is no earlier weekday |

### reliability.R

| Function | Input -> output | Statistic and NA rules |
|---|---|---|
| `reliability_summary(M, structure, k, tau)` | minutes x stations 0/1 matrix -> availability and R(tau) | availability = share of known minutes the condition holds; R(tau) = share of start minutes (m + tau <= window end) holding in every minute of [m, m+tau); unknown minutes drop out; independence value shown only as a contrast |
| `grid_usable_matrix(grid, station_ids, usable)` | grid -> matrix | unknown minutes stay NA |
| `reliability_from_grid(grid, ...)`, `reliability_from_grids(grids, ...)` | one or many days -> summary | series (origin rent-usable at m and destination return-usable at m + d), parallel, k-out-of-n; days are separated by NA rows |

### faulttree.R

| Function | Input -> output | Statistic and NA rules |
|---|---|---|
| `cause_action(reason)` | failure code -> rebalancing / maintenance / data check | unknown code stops with a message |
| `classify_failures(attempts, type, grid)` | failed attempts -> logged and final action | a "no_bike" failure whose minute shows bikes > 0 becomes a data check |
| `fault_tree(attempts, type, grid)` | -> counts and shares by reason and action | share NA when there are no failures |
| `fault_tree_by_station(attempts, type, grid)` | -> failures and top cause per station | ties shown as "tie: a / b" |

### tasks.R

| Function | Job |
|---|---|
| `empty_tasks()`, `new_tasks_from_plan(moves, created_at, existing)` | start a task table; make planned tasks `SIM-001`, `SIM-002`, ... from the plan |
| `validate_task_row(row)` | check one task against the status rules of methods section 7 |
| `task_transition(tasks, task_id, to, ...)` | move a task to a new status; returns `ok`, the table, a message; the table is unchanged on failure |
| `task_van_choices(tasks)` | van ids to offer |

## How `app.R` wires the tabs

`app.R` sources the files above, loads the built-in scenarios once, then builds `nav_panel`s in
this order: Overview, Stations, Quality, Forecast & Reliability, Diagnosis, Rebalancing,
Improvement. Inside `server`, reactives read the scenario (upload or built-in), build the day
grids at the chosen `stale_limit`, and each tab calls the functions above and renders the result.
No formula is written in `app.R`.

## Where to add a tab

1. Put the statistic in its own file as a plain function with a known-answer test and a degenerate
   case in `../tests/`. Never inside `app.R`.
2. Add display helpers to `prep.R` and a plot helper to `plots.R` if needed.
3. In `app.R`, add `source("yourfile.R", local = TRUE)`, then a `nav_panel(...)` in the UI and its
   outputs in `server`. `manifestme.R` reads the `source()` calls, so the new file is bundled.
4. Run the tests, then `Rscript app/manifestme.R`, and commit the new `manifest.json`.
