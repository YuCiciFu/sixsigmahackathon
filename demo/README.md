# Demo: Rush Hour Autopilot on the three test datasets

A step-by-step walkthrough for a judge or a teammate, about 5 minutes per scenario. It uses the
three files in `data/`: `baseline.csv`, `planted_shift.csv` and `edge_case.csv`.

**Honesty first.** All data are simulated (`data_source=simulated`; see `data/README.md`). Nothing
here is a measurement of a real bikeshare system. Every number below was produced by running the
app's own functions on these files with the app's default settings; `demo/print_demo_numbers.R`
reprints all of them (see "Re-check the numbers"). Where the tool needs an assumption
(`stale_limit` = 2 min, 95% minimum coverage, baseline = first half of the weekdays, van speed,
and so on), the sidebar says it is a demo assumption.

## Start the app

From the repo root:

```
Rscript app/testme.R
```

then open http://127.0.0.1:5763/ (the first screen takes about 15-30 seconds). Stop it with Ctrl+C.

In the left sidebar, **Built-in scenario** chooses `baseline`, `planted_shift` or `edge_case`.
The **Date** box lists the weekdays of the scenario and starts on the first one (2026-09-21).
The **Observation minute** slider is minutes after 07:00 (the default 5 means 07:05).
Leave every other sidebar setting at its default; the numbers below use the defaults.

Tabs: Overview, Stations, Quality, Forecast, Diagnosis, Rebalancing. Every tab updates at once when a
sidebar setting changes, except Forecast, which runs only when you click **Run forecast**.

---

## Scenario 1: baseline (`data/baseline.csv`)

20 weekdays (2026-09-21 to 2026-10-16), 25 stations, 2 vans, no rejected rows.
Select **baseline** in the sidebar (it is the default).

### 1.1 Overview, KPIs for 2026-09-21

Tab **Overview**, Date 2026-09-21. The six boxes show:

| Box | Value |
|---|---|
| Either-unusable share | **29.9%** (1347 of 4500 known station-minutes) |
| Rent failure | **27.1%** (820/3025 rent attempts) |
| Return failure | **1.7%** (25/1484 return attempts) |
| Known minutes / Unknown minutes / Coverage | 4500 / 0 / 100.0% |

The ranking table (rank 1 = worst) starts with S001 (112 unusable minutes, 65 early-warning
minutes), S004 (140, 35), S019 (145, 28).

How to read this: an unusable minute is a station-minute with no bike to rent or no dock to return
to; the share is out of known minutes only, and unknown minutes are never counted as usable.
The bottom panel "Data issues" says "No data issues found" for this file.

### 1.2 Quality, p charts

Tab **Quality**. Limits come from the baseline: the first 10 of the 20 weekdays.

- **Rent p chart:** centre 26.79%; the first-day limits are LCL 24.37% and UCL 29.20%. 7 of the 20
  weekdays are marked **OUT OF CONTROL** (2026-09-29, 10-02, 10-08, 10-09, 10-12, 10-15, 10-16).
- **Return p chart:** centre 2.05%; limits LCL 0.95% and UCL 3.15% on the first day. 7 of 20 weekdays
  are marked **OUT OF CONTROL** (2026-09-23, 09-24, 09-28, 09-29, 10-07, 10-12, 10-16).

How to read this: the limits assume a binomial model, where every attempt in a window fails
independently with the same probability. This file was generated without a planted change, yet 7 of
20 weekdays fall outside the limits on each chart. That points to the assumption, not to 7 real
special causes: attempts at the same station and time are not independent, so the daily rate varies
more than the binomial limits allow, and the limits are too narrow. Treat these points as a prompt to
investigate. The tool states the assumption on the page but does not test it. We do **not** claim the
baseline p charts show a clean in-control process.

### 1.3 Quality, c chart

Same tab, "c chart". All 20 windows have enough coverage (fixed set of 25 stations). Counts of anomaly
onsets per window: centre **157.9**, UCL **195.597**, LCL **120.203**. All 20 windows are "within
limits" (range 133 to 188). Dispersion box: variance 300.77 / mean 157.90 = 1.90, a **warning**
(clusters of events: limits likely too narrow).

How to read this: it counts how many separate unusable episodes began in each window, not how long
they lasted. The Overview and Stations tabs show the level of unusable time.

### 1.4 Quality, X-bar/R and Cpu with USL = 12 (an example input)

Same tab, "X-bar and R chart" (van response time, minutes from assigned to arrived). 20 subgroups
of the first 3 completed tasks per window; the first three subgroups are 9, 10, 11 minutes (mean 10,
range 2). X-bar limits 7.954 to 12.046; R limits 0 to 5.148; all in control.

Then, in "Capability of response time", type **12** into **Upper spec limit USL**:

| Item | Value |
|---|---|
| sigma-hat = R-bar/d2 | 1.181 min |
| X-double-bar | 10.000 min |
| **Cpu** | **0.564** |
| Cpl, Cp, Cpk | not computed: "no LSL entered: Cpl, Cp and Cpk need both limits" |

The normality box warns (Shapiro-Wilk W = 0.793, p = 9.19e-08 on 60 response times).

How to read this: **USL 12 is our example input, not a real specification.** In the built-in files
every subgroup is the same 9, 10 and 11 minutes, so this Cpu only demonstrates the arithmetic
(Cpu = (USL - mean) / (3 x sigma-hat) = (12 - 10) / (3 x 1.181)). It says nothing about a real fleet.
Sigma-hat comes from the average range (R-bar/d2), so these are Cp/Cpk, not Pp/Ppk.

### 1.5 Forecast, Now at 2026-10-05 07:30

First, with the default Date **2026-09-21** (the first weekday), open tab **Forecast**: a yellow box
says there are no earlier weekdays to estimate demand from and offers two buttons, "Use the first date
with history (2026-09-22)" and "Use the latest date (2026-10-16)". The tool never uses the chosen day or
later days for the forecast (no look-ahead).

Now set Date **2026-10-05** and slide Observation minute to **30**. Keep R = 2000, seed 1 and van speed
20 km/h, then click **Run forecast** (about 3 seconds). The banner says 25 of 25 stations forecast from 10 earlier weekdays
(45153 attempts). Sample rows (probability of at least one unusable minute within 30 minutes, with the
simulation SE):

| Station | Bikes / docks at 07:30 | P(rent-unusable) in 30 min | P(return-unusable) in 30 min |
|---|---|---|---|
| S006 | 0 / 20 | 1.000 (SE 0.000) | 0.000 (SE 0.000) |
| S008 | 20 / 0 | 0.054 (SE 0.005) | 1.000 (SE 0.000) |
| S010 | 0 / 20 | 1.000 (SE 0.000) | 0.000 (SE 0.000) |

How to read this: a station that is already empty (or full) at 07:30 has risk 1 by definition and says
so in the last column; the model (Poisson demand from earlier weekdays only, stations independent) matters
for stations that are not yet unusable. It is a model, not a measurement.

---

## Scenario 2: planted_shift (`data/planted_shift.csv`)

Same 25 stations. The first 10 weekdays are normal; **from weekday 11 (2026-10-05)** the generator
plants return-side dock faults and a demand surge. This is engineered, to show the tool reacting.
Select **planted_shift** (the first screen after switching can take longer; the file is large).

### 2.1 Quality, the return p chart jumps from 2026-10-05

Tab **Quality**, "p chart: return failure proportion". Baseline = first 10 weekdays: centre **3.00%**
(first-day limits 1.67% to 4.33%). From 2026-10-05 every weekday is **OUT OF CONTROL**: 32.00% to 32.04%
return failures (1440 to 1442 of 4500 attempts) against a UCL of 3.77%.

How to read this: the return failure rate has shifted from about 3% to about 32% and stayed there,
far beyond the limits. In this file the return p chart also marks 4 baseline days (2026-09-21, 09-30,
10-01, 10-02), a reminder that the binomial limits are narrow (see 1.2); the jump from 2026-10-05 is
about ten times larger than those. The rent p chart marks 11 of 20 weekdays, including every weekday
from 2026-10-05 (the planted demand surge).

The c chart does **not** flag the shift (all 20 windows in control, centre 157.6, variance/mean 0.92).
That is expected: a dock that stays faulty adds one onset and then none, so this chart counts how often
stations break, not how long they stay broken.

### 2.2 Diagnosis, return failures point to dock_fault / maintenance

Tab **Diagnosis**. Scope "Sidebar date" with Date 2026-10-05:

- Return failed: **1440 of 4500 attempts failed (32.0%)**, all of them `dock_fault`, which maps to
  **maintenance (100.0%, 1440)**.
- Rent failed: 5284 of 9000 (58.7%), all logged `no_bike`, which maps to **rebalancing (100.0%)**.

Scope "All weekdays": return 14857 of 60047 failed (24.7%): dock_fault 14400 (**96.9%, maintenance**), no_dock
457 (3.1%, rebalancing). Rent 60340 of 120234 failed (50.2%), all no_bike (rebalancing).

How to read this: each logged failure reason is mapped to one action (no_bike and no_dock to
rebalancing; bike_fault, dock_fault and station_closed to maintenance; app_error to data check).
After 2026-10-05 the returns cannot be fixed by moving bikes, a technician is needed. The trees are
qualitative: they give shares of logged failures, not probabilities.

---

## Scenario 3: edge_case (`data/edge_case.csv`)

2 stations, 1 weekday (2026-09-21), gaps in the status feed and a conflicting duplicate. Select
**edge_case**. Some panels pause or say "n/a" on purpose.

### 3.1 Overview, Data issues: 3 conflicting rows rejected

Tab **Overview**, bottom panel "Data issues". Rows per record type:

| Record type | In file | Valid | Rejected |
|---|---|---|---|
| stations | 2 | 2 | 0 |
| status | 599 | 596 | **3** |
| attempts | 355 | 355 | 0 |
| tasks | 0 | 0 | 0 (state: no records) |

Issue summary: status, rule "conflicting duplicate", action rejected, 3 rows (rows 554, 555, 556, station
S002). A yellow banner also says some rows were rejected. KPIs for 2026-09-21: either-unusable share
18.2% (65 of 358 known station-minutes), rent failure 18.3% (65/355), return failure n/a (0/0 return
attempts), 2 unknown minutes, coverage 99.4%.

How to read this: when two snapshots for the same station and minute disagree, the tool rejects both and
reports them, instead of silently choosing one. Minutes without a recent valid snapshot stay unknown (here 2 unknown minutes).

### 3.2 Rebalancing at 07:12, S002 is stale

Set the Observation minute slider to **12** (07:12) and open tab **Rebalancing**. No move is recommended.
Under "Stations left out of moves": **S002**, reason "stale station data: last valid snapshot is 3 min old
(stale_limit 2 min); 3 invalid status row(s) rejected (see Data issues)"; recommendation "data check, not a
rebalancing move".

How to read this: the tool will not send a van on a reading it cannot trust. It tells the dispatcher to
check the data first.

### 3.3 Quality, one-day SPC limits are NA, with the reason

Tab **Quality** (Date 2026-09-21). With one weekday there is nothing to estimate limits from:

- Rent p chart: centre 18.31% but limits not drawn: "fewer than 2 baseline subgroups: limits cannot be estimated".
- Return p chart: "n = 0 for some subgroups: p is NA for those subgroups; fewer than 2 baseline subgroups:
  limits cannot be estimated".
- c chart (2 stations, 1 window, 4 onsets): "fewer than 2 baseline windows: limits cannot be estimated"; the
  point reads "not assessed", and the dispersion check says it cannot be estimated.
- Forecast: the only date has no earlier weekday, so the tab shows the yellow box and no forecast runs
  ("no earlier weekday to estimate demand").

How to read this: the tool prints NA with a reason, rather than a confident-looking number from too little data.

---

## Rebalancing task-status demo (simulated)

Any scenario works; the numbers here are from **baseline**, Date **2026-09-21**, Observation minute **5**
(07:05, the defaults). Tab **Rebalancing**:

1. "Recommended moves" lists 14 moves, the first being S002 to S001 (2 bikes, 0.58 km estimated).
2. Click **Create simulated tasks from these moves**. Result: "Created 14 planned task(s): SIM-001 ...
   SIM-014", all with status `planned` (SIM-001: S002 to S001, 2 bikes; SIM-002: S003 to S004, 1 bike; SIM-003:
   S014 to S019, 7 bikes).
3. Task **SIM-001**, Move to status **assigned**, Van **V1**, time **07:05**, click **Apply**:
   "Accepted: SIM-001 planned -> assigned." (valid).
4. Task SIM-001 again, Move to status **completed**, time 07:30, Bikes actually moved 1, click **Apply**:
   "Rejected: invalid transition: assigned -> completed; allowed from assigned: in_progress, cancelled."
   The table is unchanged.

How to read this: tasks move forward only (planned, assigned, in_progress, completed; cancelled is also
allowed before completion), a step cannot be skipped. The tasks are session-only simulations; they are not saved
and do not feed the charts.

---

## Re-check the numbers

`demo/print_demo_numbers.R` loads the three files and prints every number above, using the same
functions and defaults as the app (it starts no server). From the repo root:

```
Rscript demo/print_demo_numbers.R
```

It takes about one minute. Output is deterministic (the forecast uses a fixed seed). Numbers in this
README were produced with R 4.5.2 on 2026-10-17, after the H-19 scope reduction.

## Checked by a teammate who did not write this

A teammate who did not write this page follows it from "Start the app" and compares the numbers on
screen (or in the script output) with the numbers above.

- Name: ____________________
- Date: ____________________
- Numbers matched (yes / no): ____________
- Notes (any number that differed, and the step): ______________________________
