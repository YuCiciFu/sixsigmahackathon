# Methods: Rush Hour Autopilot (team 2027win)

The detailed design behind [`SPEC.md`](../SPEC.md). `SPEC.md` keeps the event template form and
links here; section numbers below match the `SPEC.md` sections so cross-references such as
"see 4.1" or "section 7" point inside this file. Where code and this file disagree, the code is
the bug: change `SPEC.md` / this file first, then the code. Task order lives in
[`plan.md`](plan.md).

## 1. Team and prompt
- **Team name:** 2027win
- **Track:** on-campus (24 hours). Submissions due Sat Oct 17, 1 PM ET. See [`docs/schedule.md`](docs/schedule.md).
- **Prompt we chose:** "Bikeshare Fleets": *A municipal bikeshare system is suffering from a "docks full / docks empty" crisis during rush hour. Maintenance vans are dispatched blindly. Design a system tool to track dock availability, when and where stations are unusable, and support the network's performance.*
- **Our public repo:** github.com/YuCiciFu/sixsigmahackathon (checked 2026-10-16: logged-out GitHub API and web page both return HTTP 200, so it is public)
- **Tool name:** Rush Hour Autopilot (web dashboard only in this phase)

## 2. User and use case (rubric: scope 5, user and use case 5)
- **User:** the municipal bikeshare dispatcher (operations controller) who plans the rebalancing vans for the weekday morning rush.
- **Decision the tool helps them make, and when:** before and during the 07:00-10:00 ET weekday rush: which stations to handle first; whether each problem needs a van move (rebalancing), a repair (maintenance) or a data check; which station to take bikes from, which to bring them to, and how many; and whether service is changing from week to week (control charts).
- **Why this matches the prompt:** it tracks dock availability from station status snapshots, shows when and where stations are unusable (empty or full), and replaces blind van dispatch with a ranked plan and a short-term risk forecast. The plan is a heuristic; its effect is not measured by the tool.

## 3. Inputs (rubric: minimal inputs 5)

All data in this version are **simulated** (seeded and reproducible) and labelled as such in
every row (`data_source = simulated`). The four tables are stored in our own **internal**
scenario format (section 7). That format is *not* native GBFS: its column names are close to
GBFS `station_information` / `station_status`, but real GBFS data needs an adapter, for example
`num_bikes_available` to `bikes_available`, `num_docks_available` to `docks_available`, and
`last_reported` (epoch seconds) to `timestamp`. The real GBFS adapter is out of scope in this phase.

| Stations: `station_id`, `station_name`, `latitude`, `longitude`, `capacity`, `region` | text; decimal degrees (WGS84); capacity in docks (integer > 0); region is text | the operator's station list (GBFS `station_information`) |
| Status: `timestamp`, `station_id`, `bikes_available`, `docks_available`, `is_renting`, `is_returning` | ISO 8601 timestamp with UTC offset, about one snapshot per station per minute; bikes and docks are counts (integer >= 0, `bikes + docks <= capacity`); flags are TRUE/FALSE | the system's status feed (GBFS `station_status`), polled every minute |
| Attempts: `attempt_id`, `timestamp`, `station_id`, `attempt_type`, `success`, `failure_reason` | one row per rent or return attempt; `attempt_type` in {rent, return}; `success` TRUE/FALSE; `failure_reason` is a code from the codebook, empty when `success` is TRUE | kiosk and app transaction logs. Failures are never inferred from inventory changes |
| Tasks: `task_id`, `van_id`, `source_station_id`, `destination_station_id`, `planned_quantity`, `actual_quantity`, `assigned_at`, `arrived_at`, `completed_at`, `status` | quantities in bikes (integer >= 0); times as ISO 8601 with offset; all durations converted to minutes; `status` in {planned, assigned, in_progress, completed, cancelled} | the dispatch system's van task log |
| Parameters (all have defaults and can be changed in the app) | rush window 07:00-10:00 America/New_York, weekdays; early-warning threshold 2 bikes / 2 docks; target fill 50% of capacity (demo heuristic, see 4.3); van capacity 12 bikes (demo assumption); detour factor 1.3 (demo assumption); `stale_limit` 2 min (demo assumption, see 4.1); minimum coverage for SPC 95% (demo assumption, see 4.1); optional response-time USL in minutes (no default) | the operator's own policy |

All timestamps are converted to America/New_York for display and for the rush-hour window.

## 4. The statistics, and why (rubric: valid QC analysis 25)

The work is split into three tiers. **Tier 1 (core) ships first** and is what H-03 delivers.
Tiers 2 and 3 are also in scope. Each gets its own CONTRACT task and acceptance check in
`docs/plan.md`, and is added one tested function at a time, only after tier 1 runs end to end.

### 4.1 Status data rules (used by every method)
These rules turn status snapshots into a station-minute grid.

- **Grid.** For each station, the rush window is cut into 1-minute intervals `[m, m+1)`, so 07:00-10:00 gives 180 intervals. All times are in America/New_York.
- **Which snapshot sets the state.** Interval `[m, m+1)` takes the state of the **most recent valid snapshot whose timestamp is at or before m**. A snapshot taken later inside the interval (for example at m + 30 s) is never used to fill that interval; it can only set later intervals.
- **Age.** `age = m - (actual snapshot timestamp)`, in minutes, using the real timestamp including seconds.
  - If `age <= stale_limit`, the snapshot sets the interval.
  - Otherwise the interval is **unknown**.
- **`stale_limit`.** The default is 2 minutes and it can be changed. It is a **demo assumption**, not a measured property of any real feed.
- **Unknown intervals.**
  - They are left out of both the numerator and the denominator of every rate.
  - They are never counted as usable or as unusable.
  - They raise a "data check" flag.
- **Last record.** There is no extrapolation past the stale limit, and nothing is extended past 10:00.
- **Duplicates.**
  - Rows that are identical (same `station_id`, `timestamp` and values) are kept once.
  - Rows with the same `station_id` and `timestamp` but different values are a conflict. **All** the conflicting rows are invalid and get a data-check flag; the interval then falls back to the most recent earlier valid snapshot, subject to the age rule.
- **Invalid rows.** A row with a negative count, a missing count, `bikes + docks > capacity`, or an unknown `station_id` is rejected, counted and flagged. Its counts are never replaced by 0.
- **Valid zeros are kept.** For example, `bikes_available = 0` is a real observation.
- **Coverage.** Every result reports known minutes, unknown minutes and `coverage = known / (known + unknown)`.
  - Windows or stations with different coverage are compared by **rates per known minute**, never by raw totals of unusable minutes.
- **SPC inclusion rule.**
  - A chart uses a **fixed station set**: the stations present on every weekday in the scenario.
  - A rush window is plotted on the c chart only when that set's coverage is at least 95% (adjustable demo assumption). Excluded windows are listed with their coverage, shown greyed out, and never used in the baseline.
  - The p charts use the attempt log, which does not depend on status coverage, so every weekday window with attempts is included.
- **Rent-unusable minute:** `bikes_available = 0` or `is_renting = FALSE`.
- **Return-unusable minute:** `docks_available = 0` or `is_returning = FALSE`.
- **Counting the two failure types.** Rent-unusable and return-unusable minutes are counted separately. *Either-unusable* is their union: a minute that is both counts once.
- **Cause, from the state:**
  - Zero bikes or zero docks points to rebalancing.
  - `is_renting = FALSE` or `is_returning = FALSE` points to maintenance or a data check, never rebalancing.
- **Early warning** (`0 < bikes_available <= 2` or `0 < docks_available <= 2`) is used for ranking only and is **never counted as a failure**.
- **Anomaly event:** a known usable interval followed by a known unusable interval. A switch across an unknown gap is not counted.

### 4.2 Methods
- **Method:**
  - *Tier 1 (core):*
    1. **Unusable minutes** per station and per rush window, using the 4.1 rules: rent-unusable, return-unusable, either-unusable, and early-warning minutes. Each is shown with the number of known minutes. These feed the station ranking.
    2. **p charts**, one for the rent-failure proportion and one for the return-failure proportion. Each subgroup is one weekday rush window, network-wide.
       - Limits: `p-bar +/- 3*sqrt(p-bar*(1-p-bar)/n_i)`. They vary with each day's number of attempts `n_i`; the LCL is truncated at 0 and the UCL at 1.
       - `p-bar` is estimated **only from the baseline subgroups** passed to the function.
    3. **Observed unusable share and coverage** on the Overview: unusable minutes per known minute, with known minutes, unknown minutes and coverage (4.1).
    4. **Rebalancing plan**, a greedy heuristic: it is not claimed to be optimal (see 4.3). It is not evaluated: the tool makes no claim that the moves reduce unusable minutes.
  - *Tier 2:*
    1. **c chart** of anomaly events per rush window for a fixed station set: `c-bar +/- 3*sqrt(c-bar)` from baseline windows, LCL truncated at 0.
    2. **X-bar and R chart** of van response time (`arrived_at - assigned_at`, minutes).
       - Rational subgroups: the first n = 3 completed tasks in each rush window, using constants A2, D3, D4 and d2.
       - Windows with fewer than 3 tasks are dropped and reported.
    3. **Cpu** = `(USL - X-double-bar) / (3*R-bar/d2)`, computed only when the operator enters a USL and the X-bar and R chart is in control. Cp and Cpk are computed only when both a USL and an LSL are entered.
    4. **Current-state risk forecast.** It gives the probability that a station is rent-unusable (or return-unusable) at a forecast origin t0 or at least once within the next 10, 20 and 30 minutes.
       - **Inputs.** The forecast starts from the station's inventory in the latest valid snapshot at or before t0, which must pass the age rule; otherwise it is `NA`. Vans already scheduled to arrive are included.
       - **Demand model.** Rents and returns arrive as independent Poisson processes per station.
         - The rate is `lambda(station, 15-min bin) = attempts (successful + failed) / known station-minutes in that bin` over the eligible weekdays.
         - A rate of 0 is valid and is shown as such.
       - **No look-ahead.** The eligible weekdays are those **strictly before** t0's date. No data later than t0 is ever used.
       - **Built in two steps:**
         - *Step 5a (fixed rates):* the rates are taken as known.
         - *Step 5b (day bootstrap), added only after 5a passes its tests:* the eligible days are resampled with replacement B times (default 200), the rates are re-estimated each time, and each set is simulated.
       - **Uncertainty, reported as three separate things**, never lumped together:
         - (i) **Demand randomness.** This is what the probability itself describes: the same rates can give different futures.
         - (ii) **Simulation error.** This is the Monte Carlo standard error `sqrt(p(1-p)/R)` from using a finite R (default 2000). It is not a statement about the real world.
         - (iii) **Parameter-estimation uncertainty.** This exists in step 5b only: the 2.5-97.5 percentile range of the risk across the bootstrap rate sets.
       - **Shown with each forecast:** the source days, the bin rates and the assumptions. The forecast ignores interactions between stations and riders who give up without trying (unobserved demand).
  - *Tier 3:*
    1. **Qualitative fault trees** for rent failure and for return failure. Cause shares come from the `failure_reason` codes, and each cause is mapped to rebalancing, maintenance or data check. Probabilities are added only if probability data exist.
    2. **Task status updates** from the web page.
- **Why it fits the use case:** the dispatcher's question is "is rush-hour service getting worse, where, why, and which stations need a van now". Attempts are pass/fail, so failure proportions use p charts. Anomaly onsets are counts over a fixed area of opportunity, so they use a c chart. Response times come in natural per-rush groups, so they use X-bar and R. "Will this station fail in the next 30 minutes from where it is now" depends on the current inventory, so it is simulated forward rather than read off history.
- **Assumptions and how the tool checks them:**
  - **Phases.** Control limits come from a baseline (phase I) and are applied to later days (phase II). In the app the default baseline is the first half of the weekdays, and this can be changed. Every chart function takes the baseline rows as an explicit argument, so the tests state exactly which rows they use.
  - **Run rules.** Out-of-control means Western Electric rule 1 (a point beyond 3 sigma) or rule 4 (8 points in a row on one side of the center line).
  - **Comparable windows.** Only weekdays are compared, and each subgroup is the same 07:00-10:00 window.
  - **Binomial for the p charts.** The limits assume that within a window every attempt fails independently with one common failure probability. This is stated on the page, not tested by the tool. Attempts at one station and time may not be independent; then the limits are too narrow, so a point beyond them is a prompt to investigate, not a confirmed special cause.
  - **Poisson for the c chart.** The tool shows the dispersion ratio variance/mean and warns when it is above 1.5.
  - **Capability.** It needs an in-control process and an approximately normal distribution. The tool shows a histogram and a Shapiro-Wilk test, and warns that response times are often right-skewed. Spec limits are never invented: there is no USL means no Cpu.
  - **Forecast.** Poisson arrivals with rates that are constant within each 15-minute bin, stations independent; checked by comparing the observed variance/mean of attempts per bin. The three uncertainty sources are reported separately (item 4).
  - **Fault tree.** It stays qualitative unless probability data exist.
- **Degenerate and small-sample rules:**
  - **Only what cannot be estimated becomes `NA`.** That means control limits, standard deviations, standard errors, confidence intervals and capability indices, each with a plain reason. Examples: `p-bar = 0` or `p-bar = 1`; `c-bar = 0`; `R-bar = 0` (constant data); `n < 2`; fewer than 2 baseline subgroups. The tool never returns `Inf` or a made-up number.
  - **Valid observed values are always kept and shown.** This covers raw observations, counts, proportions, means, center lines and differences.
    - With zero failures the tool shows the failure count and `n`, for example 0/300, and the proportion 0.
    - With constant data it shows the observations and the center line.
    - With n = 1 it shows the observed value; only the spread, the standard error and the limits are `NA`.
  - **No observed failures does not mean no future risk.** The text says so explicitly: "no failures were observed in these n attempts; this does not show the risk is zero".
  - **Missing values** are excluded and counted. They are never treated as 0.
- **Known-answer check:** each check below is hand-worked, and the R function must reproduce it to 3 decimals. **Unless a check says otherwise, it passes all of its subgroups as the baseline.** These are formula tests: they prove the arithmetic and the edge-case rules, and they do **not** show that any real or simulated process is stable.
  - **KA-1, grid and unusable minutes:** station capacity 10, ten snapshots taken exactly on the minute (07:00:00 to 07:09:00, so every age is 0) with `bikes_available` = 2, 1, 0, 0, 0, 1, 2, 8, 10, 10, so `docks_available` = 8, 9, 10, 10, 10, 9, 8, 2, 0, 0, with all flags TRUE.
    - Rent-unusable = 3 minutes and return-unusable = 2 minutes, so either-unusable = 5.
    - Bike early-warning = 4 minutes and dock early-warning = 1 minute. Neither counts as a failure.
  - **KA-1b, grid rules:** each case starts from KA-1 with `stale_limit` = 2.
    - (a) The 07:04:00 snapshot is removed. Interval 07:04 uses 07:03:00 (age 1) and is rent-unusable. The totals are unchanged: 3 / 2 / 5, with 10 known minutes.
    - (b) The 07:03, 07:04 and 07:05 snapshots are removed. 07:03 and 07:04 use 07:02:00 (ages 1 and 2). 07:05 would be age 3, which is more than 2, so it is unknown.
      - Rent-unusable = 3 of 9 known minutes (coverage 90%), with 1 unknown minute.
    - (c) A second 07:02:00 row with `bikes_available` = 3 conflicts with the first, so both rows are invalid and flagged. Interval 07:02 falls back to 07:01:00 (age 1, 1 bike) and is usable.
      - Rent-unusable = 2 (07:03, 07:04) of 10 known minutes, with 1 conflict flagged.
    - (d) An extra snapshot at 07:05:30 with `bikes_available` = 0 is added.
      - Interval 07:05 still uses 07:05:00 (1 bike), because the later snapshot is never used to fill the minute it falls in.
      - Interval 07:06 uses 07:06:00, which is more recent.
      - The totals are unchanged.
  - **KA-2, p chart:** 5 rush windows, each with n = 100 rent attempts and 4, 6, 5, 3, 7 failures; all 5 are the baseline.
    - p-bar = 25/500 = 0.050.
    - sigma = sqrt(0.05 x 0.95 / 100) = 0.021794.
    - UCL = 0.05 + 3 x 0.021794 = 0.115383. LCL = max(0, 0.05 - 0.065383) = 0.
    - No point is out of control.
  - **KA-2b, UCL cap:** baseline p-bar = 0.5, with n = 4 in the subgroup being checked.
    - 0.5 +/- 3 x sqrt(0.25/4) = 0.5 +/- 0.75, which gives 1.25 and -0.25.
    - Reported as UCL = 1 and LCL = 0.
  - **KA-2c, zero failures:** 3 windows with n = 100 and 0 failures each.
    - Shown: failures 0, n = 300, p = 0.
    - Limits are `NA` with the message "p-bar = 0: limits cannot be estimated; no failures observed does not mean zero risk".
  - **KA-4, rebalancing:** station A (capacity 20, 18 bikes) and station B (capacity 20, 1 bike, 19 free docks), with target fill 0.5 (so target 10), an empty van and van capacity 12.
    - Surplus 8, deficit 9.
    - Plan: move min(8, 9, 19, 12) = 8 bikes from A to B.
  - **KA-11, coverage and inclusion:** on a fixed set of 25 stations x 180 min = 4500 station-minutes per window.
    - Window X: 4500 known, coverage 100%, 450 unusable, share 10.0%. Included.
    - Window Y: 4200 known and 300 unknown, coverage 93.3%, 441 unusable, share 10.5%. Excluded from the c chart, listed and greyed out.
    - Comparing raw totals (450 vs 441) would wrongly make Y look better.
  - **KA-6, c chart (tier 2):** baseline events per window = 3, 5, 2, 4, 6.
    - c-bar = 4, UCL = 4 + 3 x 2 = 10, LCL = 0.
  - **KA-7, X-bar and R plus Cpu (tier 2):** subgroups of n = 3 response times (10, 12, 14), (11, 13, 15) and (9, 12, 15) minutes; all 3 subgroups are the baseline.
    - X-double-bar = 12.333 and R-bar = 4.667.
    - X-bar UCL = 12.333 + 1.023 x 4.667 = 17.107 and LCL = 7.559.
    - R UCL = 2.574 x 4.667 = 12.012 and R LCL = 0.
    - sigma-hat = 4.667/1.693 = 2.756.
    - With a test USL = 20 entered as input: Cpu = (20 - 12.333)/(3 x 2.756) = 0.927.
  - **KA-8b, forecast (tier 2):** a station with 2 bikes, plenty of docks, a rent rate of 0.1 per minute (Poisson) and no returns. P(rent-unusable within t) = P(N >= 2) with N ~ Poisson(0.1t):
    - t = 10: 1 - e^-1 x 2 = 0.264;
    - t = 20: 1 - 3e^-2 = 0.594;
    - t = 30: 1 - 4e^-3 = 0.801.
    - The fixed-rate simulator (step 5a) with a fixed seed and R = 20000 must land within 4 simulation standard errors of each value.
  - **KA-8c, no look-ahead (tier 2):** a forecast with t0 on weekday 6 must give identical rates whether or not the attempts of weekdays 6-20 exist in the input.
  - **KA-8d, bootstrap sanity (tier 2, step 5b):** when every eligible day has the same attempts, every bootstrap rate set is identical, so the parameter-uncertainty range collapses to a single point, apart from simulation error.
  - **KA-10, fault tree cause shares (tier 3):** 10 failed rents with reasons no_bike x 6, dock_fault x 3, app_error x 1.
    - Rebalancing 60%, maintenance 30%, data check 10%.
    - In addition, a failed rent with reason no_bike in a minute whose valid snapshot shows `bikes_available` > 0 is reclassified as a data check (status/attempt contradiction).
  - **Removed in H-19 (2026-10-17, team request).** These known answers belonged to features that are no longer in the tool: KA-3 (I-MR chart), KA-4b (van pickup and drop-off in the policy simulation), KA-5 and KA-5b (paired policy differences with Bonferroni intervals), KA-8 (historical Kaplan-Meier and RMST) and KA-9 (empirical availability and R(tau)). So did the p-chart dispersion example under KA-2 and decision D-4. Their hand-worked values and tests are kept in git history (commit ff1181b, `docs/methods.md` and `tests/`).

### 4.3 Rebalancing plan (a demo heuristic, not an optimiser)
- **Excluded stations.** A station that is closed (`is_renting` or `is_returning` FALSE) or has fault codes is left out of moves. It gets a maintenance or data-check recommendation instead.
- **Target.** `target = round(target_fill * capacity)`, where `target_fill` defaults to 0.5. This is an adjustable demonstration heuristic, not a claimed optimum.
- **Surplus and deficit.**
  - Surplus stations hold more bikes than their target.
  - Deficit stations hold fewer bikes than their target.
- **Pairing.** Each deficit station, worst first by ranking, is paired with the nearest surplus station by haversine distance x a detour factor.
  - The detour factor defaults to 1.3. It is adjustable and is a **demo assumption**.
  - The result is labelled "estimated travel distance", not an actual road route.
  - **Ties** are broken by `station_id` in ascending order: ties in ranking pick the deficit station, ties in distance pick the surplus station. This makes the plan deterministic.
- **Van capacity** defaults to 12 bikes. It is adjustable and is a **demo assumption**.
- **Quantity.** `quantity = min(source surplus, destination deficit, destination free docks, van free capacity)`.
- **Reservations.** Bikes and docks planned for one task are reserved so that a second task cannot plan them again. Each van holds only one active task at a time.

### 4.4 Vans in the forecast
- **Vans on the way at t0.** A task counts as on the way when it was assigned by t0 and not completed by t0. It arrives at `assigned_at + straight-line km x detour factor / speed`; speed (default 20 km/h) and the detour factor (default 1.3) are demo assumptions and can be changed. Its planned bikes are added to the destination then, capped by the free docks. Logged arrival times are never used, because they may lie after t0.

## 5. Delivery (rubric: working tool 25)
- **Stack:** dashboard, R Shiny (one deployable app; statistics in `app/qc.R`, tested with testthat).
  Packages needed: shiny, bslib, ggplot2, leaflet, testthat, rsconnect. No separate API unless a later task truly needs one.
- **Starting demo:** `demos/shinyapp/` copied to `app/`. The demo has no `testme`, `manifestme` or `deployme`, so we add R versions modelled on `demos/plumber/`.

## 6. Outputs
- **What the user sees:** one Shiny page with tabs. Each chart or number carries its unit, the
  sample size or the number of known minutes, and a one-line "how to read this". The core loop runs
  through the tabs in order: find the problem, check whether it is a real change, predict the risk,
  find the cause, plan the moves and run the simulated tasks.
  - **Overview** *(tier 1)*: a station map coloured by state, the KPIs (unusable share, rent and return failure %, and known minutes, unknown minutes and coverage), and the station ranking by unusable minutes plus early-warning minutes.
  - **Stations** *(tier 1)*: the inventory trend for each station, rent-unusable and return-unusable minutes, an hour-by-station heatmap, and a Pareto chart of unusable minutes.
  - **Quality** *(tier 1 / 2)*: the p charts, then the c chart, X-bar/R and Cpu (Cp and Cpk with an LSL). Each chart has a panel showing the baseline used and whether the assumptions are met, plus plain-language text.
  - **Forecast** *(tier 2)*: the "Now" panel: the forward-simulated risk for each station, with the simulation standard error and (after step 5b) the bootstrap parameter range shown separately, plus the source days and the assumptions. It runs only on a click and needs at least one earlier weekday.
  - **Diagnosis** *(tier 3)*: the qualitative fault tree, with cause shares and the action they point to (rebalancing, maintenance or data check).
  - **Rebalancing** *(tier 1)*: the recommended moves (from, to, how many bikes, distance), labelled "heuristic", with a button that creates simulated tasks.

## 7. Test datasets and codebook (rubric: demo 10, datasets 5, codebook 5)
- **Datasets:** three simulated scenarios, produced by one seeded generator script.
  - **`baseline`** (in control): 25 stations, 2 vans, 20 weekdays, 06:00-11:00 ET.
  - **`planted_shift`** (the same network, with a planted dock fault plus a demand surge from weekday 11): the return-failure p chart, with weekdays 1-10 as the baseline, must flag it from day 11.
  - **`edge_case`** (tiny): 2 stations, 1 day, one station never fails, plus a missing minute, a conflicting duplicate and a stale gap.
  - **Layout (decision D-1).** Exactly three files sit at the top of `data/`: `data/baseline.csv`, `data/planted_shift.csv` and `data/edge_case.csv`. That keeps the H-02 check (`ls data/*.csv` lists 2 or 3 files) unchanged.
    - Each file holds all four tables in long form, told apart by a `table` column. The columns are the union of the four tables, and a column that does not apply to a row is left empty.
    - The generator script (`data/generate_data.R`) and `data/README.md` are not CSVs.
  - The small known-answer tables for the formula tests live in `tests/`, not in `data/`.

**Scenario file schema** (the contract between the dataset, the codebook and the loader):

| `table` value | Required fields (type) | Must be empty | Key | Rules |
|---|---|---|---|---|
| all rows | `table` (text, one of the four values), `data_source` (text, always `simulated`) | - | - | UTF-8, comma separated, header row, `TRUE`/`FALSE` for booleans, timestamps ISO 8601 with offset, e.g. `2026-10-05T07:03:00-04:00` |
| `stations` | `station_id` (text), `station_name` (text), `latitude` (num, -90..90), `longitude` (num, -180..180), `capacity` (int > 0), `region` (text) | status, attempt and task columns | `station_id` unique | every other table's station ids must exist here |
| `status` | `timestamp`, `station_id`, `bikes_available` (int >= 0), `docks_available` (int >= 0), `is_renting` (bool), `is_returning` (bool) | attempt and task columns | (`station_id`, `timestamp`); duplicates are allowed only in `edge_case`, to test 4.1 | `bikes + docks <= capacity` |
| `attempts` | `attempt_id` (text), `timestamp`, `station_id`, `attempt_type` (`rent` or `return`), `success` (bool) | status and task columns; `failure_reason` when `success` is TRUE | `attempt_id` unique | `failure_reason` is required when `success` is FALSE. For rent it is one of `no_bike`, `bike_fault`, `dock_fault`, `station_closed`, `app_error`; for return, one of `no_dock`, `dock_fault`, `station_closed`, `app_error` |
| `tasks` | `task_id` (text), `source_station_id`, `destination_station_id`, `planned_quantity` (int > 0), `status` (`planned`, `assigned`, `in_progress`, `completed`, `cancelled`) | status and attempt columns | `task_id` unique | see the task-status rules below |

Task-status rules:
- **Stations.** `source_station_id` and `destination_station_id` must differ.
- **`van_id`** is required unless the status is `planned`.
- **Times by status.**
  - `assigned_at` is required from `assigned` on.
  - `arrived_at` is required from `in_progress` on.
  - `completed_at` is required for `completed`.
  - `assigned_at <= arrived_at <= completed_at`.
- **`actual_quantity`** is an integer between 0 and `planned_quantity`, and is required for `completed`.

Cause mapping for the fault tree and the recommendations:
- `no_bike` and `no_dock` point to **rebalancing**.
- `bike_fault`, `dock_fault` and `station_closed` point to **maintenance**.
- `app_error` points to a **data check**.

**Validation levels** (the same rules apply in the loader and in the 4.1 grid, so `edge_case` can be shown, not just rejected):
- **Structural errors stop loading** with a clear message, because the file cannot be read safely:
  - the file is missing or unreadable;
  - there is no `table` column, or a required column is missing for a record type that is present;
  - a `table` value is outside the four record types;
  - there are no `stations` rows;
  - a `station_id` is duplicated in `stations` (capacity would be ambiguous).
- **Row-level data problems never stop loading.** The row is either **rejected** (left out of every calculation) or **flagged** (kept, with a mark), and listed in a data-issues table (record type, row, id, rule, action) that the app shows. Examples:
  - **Rejected:**
    - an unparseable timestamp;
    - a negative or missing count;
    - `bikes + docks > capacity`;
    - an unknown `station_id`;
    - status rows that conflict (4.1);
    - repeated `attempt_id` or `task_id` with different values;
    - `success` inconsistent with `failure_reason`;
    - task times out of order.
  - **Flagged:**
    - identical repeated rows, which are kept once;
    - unknown or stale minutes, which come from the grid.
- **Counts that stay visible.** Every rejected or flagged row is counted in the data-issues figures and is never silently dropped.
  - Status coverage is computed only from the station-minute grid in 4.1, as known minutes over known plus unknown minutes.
  - Problem rows from attempts or tasks are reported as data issues. They are never added to coverage.

## 9. Out of scope
- No live GBFS feed connection in this phase: only a loader that reads GBFS-shaped CSVs. No mobile app. No vehicle-routing optimiser: the moves are greedy and use straight-line distance times a detour factor. No machine-learning demand forecast. No real dispatch integration: tasks are simulated. Tier 2 and tier 3 are in scope but are not started until tier 1 runs end to end and has passed review.

## Decisions (team answers, 2026-10-16)
- Stack: R Shiny dashboard from `demos/shinyapp`; no separate API unless a later task needs one.
- Scope: three tiers; tier 1 runs end to end and passes review before tier 2 starts.
- Failure definition: strict zero or a closed flag; early warning (2 bikes / 2 docks) is ranking only.
- USL for Cpu: entered by the operator; no USL means no Cpu; a demo value is labelled as an assumption.
- D-1: three long-form scenario CSVs at the top of `data/`, told apart by a `table` column; an internal format, not native GBFS.
- D-2: Poisson demand per station x 15-min bin; fixed rates first (5a), then day bootstrap (5b); demand randomness, simulation error and parameter uncertainty are reported separately; no look-ahead.
- D-3: `stale_limit` = 2 min (adjustable demo assumption); interval [m, m+1) uses the latest valid snapshot at or before m.
- D-4: primary metric = unusable minutes, Bonferroni 98.333% CIs for the 3 pairwise policy comparisons; secondary metrics exploratory, unadjusted 95%. **Withdrawn in H-19 (2026-10-17):** the policy comparison was removed from the tool.
