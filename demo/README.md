# Demo: Rush Hour Autopilot on the three test datasets

A step-by-step walkthrough for a judge or a teammate, about 5 minutes per scenario. It uses the
three files in `data/`: `baseline.csv`, `planted_shift.csv` and `edge_case.csv`.

**Honesty first.** All data are simulated (`data_source=simulated`; see `data/README.md`). Nothing
here is a measurement of a real bikeshare system. Every number below was produced by running the
app's own functions on these files with the app's default settings; `demo/print_demo_numbers.R`
reprints all of them (see "Re-check the numbers"). Where the tool needs an assumption
(`stale_limit` = 2 min, 95% minimum coverage, baseline = first half of the weekdays, vans, speed,
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

Tabs: Overview, Stations, Quality, Forecast & Reliability, Diagnosis, Rebalancing, Improvement.

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

### 1.2 Quality, p charts, with the dispersion warning

Tab **Quality**. Limits come from the baseline: the first 10 of the 20 weekdays.

- **Rent p chart:** centre 26.79%; the first-day limits are LCL 24.37% and UCL 29.20%. Dispersion box:
  X2 = 49.0 on 9 df, ratio 5.45, p < 0.0001, **warning**. 7 of the 20 weekdays are drawn beyond the
  limits (2026-09-29, 10-02, 10-08, 10-09, 10-12, 10-15, 10-16).
- **Return p chart:** centre 2.05%; limits LCL 0.95% and UCL 3.15% on the first day. Dispersion:
  X2 = 126.5 on 9 df, ratio 14.06, p < 0.0001, **warning**. 7 of 20 weekdays are beyond the limits
  (2026-09-23, 09-24, 09-28, 09-29, 10-07, 10-12, 10-16).

How to read this: the warning says the daily failure rate varies more than a pure binomial model
allows, so the limits are too narrow. The tool therefore labels such points "beyond binomial limit
(investigate; not a confirmed special cause)" and does not call them real special causes.
So on the baseline file the p charts do **not** show a clean in-control process, and we do not claim
they do. That is the tool being honest about its own assumption.

### 1.3 Quality, I-MR chart in control

Same tab, "I-MR chart". Fixed station set of 25 stations; all 20 windows have enough coverage.
Baseline = first 10 windows: centre **29.08**, UCL **37.43**, LCL **20.73** (% of known
station-minutes). All 20 points read **in control** (the highest is 34.36% on 2026-09-29).

How to read this: one point per weekday rush window; a point beyond the limits (or a run of 8 on one
side) would be red. None is, so the daily unusable share is stable here.

### 1.4 Quality, c chart

Same tab, "c chart". Counts of anomaly onsets per window: centre **157.9**, UCL **195.597**, LCL
**120.203**. All 20 windows are "within limits" (range 133 to 188). Dispersion box: variance 300.77
/ mean 157.90 = 1.90, a **warning** (clusters of events: limits likely too narrow).

How to read this: it counts how many separate unusable episodes began in each window, not how long
they lasted. Read the I-MR chart for the level and this chart for how often problems start.

### 1.5 Quality, X-bar/R and Cpu with USL = 12 (an example input)

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

### 1.6 Forecast & Reliability, History (Kaplan-Meier)

Tab **Forecast & Reliability**, panel "History". Failure type: Either unusable; Days used: all
weekdays. Numbers: 20 weekdays; **n = 471** station-days usable at 07:00; 337 failures; 134 censored at
10:00; 29 left out because already unusable at 07:00.

| Minutes after a usable 07:00 | F(t) = share failed by t [95% CI] |
|---|---|
| 10 | 0.132 [0.104, 0.166] |
| 20 | 0.231 [0.196, 0.272] |
| 30 | 0.333 [0.293, 0.378] |

RMST to 180 min: **87.05 min**. MTTF: n/a (the curve does not reach 0).

How to read this: descriptive about past days, not a forecast. About one usable station in three has had
its first unusable minute within 30 minutes of 07:00.

### 1.7 Forecast & Reliability, Now forecast at 2026-10-05 07:30

Set Date **2026-10-05** and slide Observation minute to **30**. In panel "Now" keep R = 2000 and seed
1, then click **Run forecast**. The banner says 25 of 25 stations forecast from 10 earlier weekdays
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

### 1.8 Improvement, three policies on 2026-10-05

Keep Date **2026-10-05**. Tab **Improvement**: Seeds R = **30**, Base seed = **1**, then click **Run
comparison** (about half a minute). Result banner: seeds 1 to 30, 25 stations, 2 vans, 4474 true
attempts, predictive history = 10 earlier weekdays.

Per-policy means over the 30 seeds:

| Policy | Mean either-unusable station-minutes | Mean failed attempts % | Mean van km |
|---|---|---|---|
| none (no rebalancing) | 1982.50 | 29.55 | 0.00 |
| reactive | 1978.43 | 29.52 | 14.47 |
| predictive | 1978.10 | 29.52 | 14.31 |

Primary metric, paired differences (first minus second; positive means the second policy is better),
Bonferroni 98.333% intervals:

| Pair | Mean difference | CI low | CI high |
|---|---|---|---|
| none - reactive | 4.067 | -0.8924 | 9.026 |
| none - predictive | 4.4 | -0.1332 | 8.933 |
| reactive - predictive | 0.3333 | -1.02 | 1.686 |

**Every one of the three primary intervals contains 0: no difference was detected between the
policies.** That is not evidence that the policies are equivalent, and we do not claim any policy
wins. How to read this: the tool judges all three policies on the same simulated riders (paired seeds).
Demand is replayed from that morning's own rates, the predictive policy only knows earlier days, and
the intervals cover simulation seeds only, not estimation error in the rates. All of it is simulated.

---

## Scenario 2: planted_shift (`data/planted_shift.csv`)

Same 25 stations. The first 10 weekdays are normal; **from weekday 11 (2026-10-05)** the generator
plants return-side dock faults and a demand surge. This is engineered, to show the tool reacting.
Select **planted_shift** (the first screen after switching can take longer; the file is large).

### 2.1 Quality, the I-MR chart jumps from 2026-10-05

Tab **Quality**, "I-MR chart". Baseline = first 10 windows: centre **28.69**, UCL **35.44**, LCL
**21.94**. Weekdays 1 to 10 are in control (24.93% to 30.96%). From 2026-10-05 every window is **OUT OF
CONTROL** (10 windows, from 89.53% to 91.04%).

How to read this: red points far above the upper limit mean the share of unusable station-minutes has
shifted from about 29% to about 90% and stayed there. Also, the return p chart shows 32.0% to 32.04%
return failures on every weekday from 2026-10-05 against a UCL of 3.77%; the dispersion warnings
(rent ratio 3.90, return ratio 10.11) still apply to the baseline limits. In this file the return p chart
also signals on some baseline days (2026-09-21, 09-30, 10-01, 10-02), a reminder that its limits are narrow.

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

### 2.3 Forecast & Reliability, History: days 1-10 versus all weekdays

Panel "History", failure type Either unusable.

1. Days used: choose **"Weekdays up to and including the sidebar date"** with Date **2026-10-02** (day 10).
2. Then choose **"All weekdays in the file"**.

| Days used | n (usable at 07:00) | F(10) | F(20) | F(30) [95% CI] | RMST to 180 min |
|---|---|---|---|---|---|
| Days 1-10 (to 2026-10-02) | 238 | 0.101 | 0.214 | 0.353 [0.296, 0.417] | 86.89 min |
| All 20 weekdays | 403 | 0.221 | 0.447 | 0.610 [0.563, 0.658] | 56.87 min |

(Station-days already unusable at 07:00 and so left out: 12 for days 1-10, 97 for all 20 weekdays.)

How to read this: after the shift, stations fail sooner. The share failed within 30 minutes rises from
about 35% to 61%, and the average minutes before the first failure (RMST) drop from about 87 to
57. The 20-day curve mixes both regimes, so it is a blend, not the new regime alone.

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
- I-MR chart (2 stations, 1 window, 18.16%): "fewer than 2 baseline points: limits cannot be estimated"; the
  point reads "not assessed".

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

It takes one to two minutes. Output is deterministic (the simulations use fixed seeds); two runs gave
identical numbers. Numbers in this README were produced with R 4.5.2 on 2026-10-17.

## Checked by a teammate who did not write this

A teammate who did not write this page follows it from "Start the app" and compares the numbers on
screen (or in the script output) with the numbers above.

- Name: ____________________
- Date: ____________________
- Numbers matched (yes / no): ____________
- Notes (any number that differed, and the step): ______________________________
