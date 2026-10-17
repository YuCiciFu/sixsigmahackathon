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
| `app.R` | UI (4 tabs, sidebar) and `server`; sources the files below |
| `qc.R` | loader and validator, station-minute grid, p, c and X-bar/R charts, capability, great-circle distance |
| `prep.R` | data shaping and display tables (no statistics) |
| `plots.R` | ggplot2 drawing helpers (no statistics) |
| `sim.R` | demand rates from earlier weekdays and van parameters, shared by the forecast |
| `forecast.R` | current-state risk forecast (Poisson, day bootstrap) |
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
| `p_chart(failures, n, baseline)` | counts -> limits and signals | p-bar +/- 3 sqrt(p-bar(1-p-bar)/n_i), capped to [0,1]; rules 1 and 4; NA limits if p-bar is 0 or 1 or fewer than 2 baseline subgroups; assumes binomial attempts (independent, same failure probability within a window) |
| `count_onsets(grid, station_ids)` | grid -> number | usable minute followed by unusable minute, both known; not across unknown gaps |
| `c_chart(counts, baseline)` | counts -> limits | c-bar +/- 3 sqrt(c-bar), LCL >= 0; NA if c-bar = 0 or fewer than 2 windows |
| `c_dispersion(counts)` | counts -> variance/mean | warning when > 1.5; NA if mean 0 or fewer than 2 windows |
| `response_subgroups(tasks, dates, ...)` | tasks -> matrix of first 3 completed response times per window | response = arrived_at - assigned_at (min); windows with fewer than 3 are dropped and listed |
| `xbar_r_chart(values, baseline)` | matrix (rows = subgroups of 3) -> limits | A2, D3, D4, sigma-hat = R-bar/d2 (not the overall SD); NA if R-bar = 0 or fewer than 2 baseline subgroups |
| `capability_indices(xbr, usl, lsl)` | chart + operator spec limits -> Cpu, Cpl, Cp, Cpk | Cpu = (USL - X-double-bar)/(3 sigma-hat); NA with reason if no USL, chart not in control, R-bar = 0, or USL <= LSL |
| `normality_check(x)` | numbers -> Shapiro-Wilk W, p | NA unless 3 <= n <= 5000 and not all equal |
| `haversine_km(lat1, lon1, lat2, lon2)` | degrees -> km | great-circle distance (used for the forecast's vans on the way) |

### prep.R (shaping and display, no statistics)

| Function | Job |
|---|---|
| `scenario_dates`, `window_bounds`, `attempts_by_day` | weekdays of the scenario, window times, attempt and failure counts per day |
| `fixed_station_set`, `build_day_grids`, `window_table` | stations present every weekday, one grid per day, per-window coverage via `window_summary` |
| `state_at`, `rank_stations`, `station_table`, `kpi_summary` | one-day state, ranking (unusable + early-warning minutes), KPIs |
| `hour_station_matrix` | input for the heatmap |
| `baseline_count`, `baseline_flags` | which weekdays set the limits (default first half) |
| `builtin_scenarios`, `default_scenario_path` | locate the bundled `app/data/*.csv.gz` scenarios |
| `table_health`, `issue_summary`, `issue_detail` | data-issue messages |
| `c_chart_table`, `xbar_r_table`, `capability_table` | tables for the Quality tab |
| `history_info` | how many earlier weekdays the chosen date has (for the forecast's date hint) |
| `forecast_*` | text and tables for the Forecast tab |

### plots.R (drawing only)

`plot_trend`, `plot_heatmap`, `plot_p`, `plot_c`, `plot_xbar`, `plot_r`, `plot_response_hist`,
`plot_forecast_risk`. Each takes already computed numbers and returns a ggplot.

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
| `sim_params(detour, speed_kmh)` | -> parameter list | detour 1.3, speed 20 km/h (demo assumptions; used for vans on the way) |
| `sim_world(state0, stations)` | start state -> world | flags stay at their starting values |
| `estimate_demand(attempts, grids, source_days, station_ids)` | -> rates per station x type x bin | attempts / known minutes; a bin with no known minute uses the station's pooled rate |
| `demand_lambda(rates)` | bin rates -> per-minute rates | each 15-minute bin rate repeated for its minutes |

## How `app.R` wires the tabs

`app.R` sources the files above, loads the built-in scenarios once, then builds `nav_panel`s in
this order: Overview, Stations, Quality, Forecast. Inside `server`, reactives read the scenario
(upload or built-in), build the day grids at the chosen `stale_limit`, and each tab calls the functions above and renders the result.
No formula is written in `app.R`.

## Where to add a tab

1. Put the statistic in its own file as a plain function with a known-answer test and a degenerate
   case in `../tests/`. Never inside `app.R`.
2. Add display helpers to `prep.R` and a plot helper to `plots.R` if needed.
3. In `app.R`, add `source("yourfile.R", local = TRUE)`, then a `nav_panel(...)` in the UI and its
   outputs in `server`. `manifestme.R` reads the `source()` calls, so the new file is bundled.
4. Run the tests, then `Rscript app/manifestme.R`, and commit the new `manifest.json`.
