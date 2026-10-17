# Rush Hour Autopilot

A web dashboard for the **municipal bikeshare dispatcher** who plans the rebalancing vans for the
weekday morning rush (07:00-10:00 New York time). It shows where and when stations are unusable
(empty or full), checks with control charts whether service is really getting worse, and forecasts
which stations are about to become unusable, so the dispatcher knows where to send a van first.

**Live app (public, no login): https://connect.systems-apps.com/content/d242b1d3-484c-484f-a581-8e4a67845434/**

Team 2027win, Cornell Six Sigma Hackathon, on-campus track. Prompt "Bikeshare Fleets": *A municipal
bikeshare system is suffering from a "docks full / docks empty" crisis during rush hour.
Maintenance vans are dispatched blindly. Design a system tool to track dock availability, when and
where stations are unusable, and support the network's performance.*
Repo: github.com/YuCiciFu/sixsigmahackathon

**All data are simulated.** Nothing here measures a real bikeshare system. The numbers show how the
tool works, not how any city performs.

## Quick start

1. Install R 4.5 or newer, then the packages (once):

   ```
   Rscript -e 'install.packages(c("shiny","bslib","ggplot2","leaflet","testthat"), repos = "https://cloud.r-project.org")'
   ```

2. From the repo root, start the app with one command:

   ```
   Rscript app/testme.R
   ```

3. Open http://127.0.0.1:5763/ (the first screen takes 15-30 seconds). Stop with Ctrl+C.

Run the tests (from the repo root):

```
Rscript -e "testthat::test_dir('tests')"
```

A guided walkthrough on the three test datasets, with every number it quotes, is in
[demo/README.md](demo/README.md). `Rscript demo/print_demo_numbers.R` reprints those numbers.

## What each tab does

| Tab | What you see | Statistic behind it |
|---|---|---|
| Overview | Station map by state at the chosen minute, KPIs, station ranking, data issues | Unusable minutes per known minute (rent-unusable: 0 bikes or renting off; return-unusable: 0 docks or returning off); early warning is ranking only, never a failure |
| Stations | Inventory trend, unusable minutes, hour-by-station heatmap | Same station-minute grid |
| Quality | p charts (rent and return failures), c chart of failure onsets, X-bar/R chart of van response time with Cp, Cpk and Cpu | p chart limits p-bar +/- 3 sqrt(p-bar(1-p-bar)/n_i) under a binomial assumption; c chart c-bar +/- 3 sqrt(c-bar) with a variance/mean check of the Poisson assumption; X-bar/R with constants A2, D3, D4; Cpu = (USL - X-double-bar)/(3 R-bar/d2) (Cp and Cpk also need an LSL), computed only when you enter a USL and the chart is in control. Signals: Western Electric rules 1 and 4 |
| Forecast | **Now:** risk that a station becomes unusable now or within 10, 20, 30 minutes | Poisson demand per station and 15-minute bin from the earlier weekdays, step 5a (fixed rates) plus an optional day bootstrap, with three uncertainty sources shown separately |

Every chart or number shows its unit and its sample size or coverage, plus a one-line "how to read
this". The full formulas and the hand-worked known answers are in [docs/methods.md](docs/methods.md).

## Inputs and parameters

**One input file:** a long-form scenario CSV with a `table` column (`stations`, `status`,
`attempts`, `tasks`). Upload it in the sidebar, or pick a built-in scenario. Schema and validation
rules: [docs/methods.md](docs/methods.md) section 7. Codebook: [data/README.md](data/README.md).

Everything else is a sidebar setting. "Demo assumption" means the value is not measured from any
real feed; change it and read the result accordingly.

| Setting | Default | Demo assumption? |
|---|---|---|
| `stale_limit` (oldest snapshot, minutes, that still counts) | 2 | yes |
| Early-warning threshold (bikes or docks, ranking only) | 2 | yes |
| Detour factor (road km = straight line x factor; forecast, vans on the way) | 1.3 | yes |
| Minimum coverage for SPC (known / all minutes) | 0.95 | yes |
| Baseline share (first part of the weekdays sets the limits) | 0.5 | yes |
| USL, LSL for Cpu / Cp / Cpk (minutes) | blank (no USL, no index) | you enter it |
| Forecast: paths R / seed | 2000 / 1 | simulation settings |
| Forecast: van speed (vans on the way at t0) | 20 km/h | yes |
| Forecast bootstrap: sets B / paths per set R_b | 200 / 200 (off until ticked) | simulation settings |

The Forecast tab runs only when you click **Run forecast**; every other setting takes effect at once.
It needs at least one weekday before the chosen date (no look-ahead): on the first date of a file it
says so and offers buttons for the first date with history and the latest date.

## Data

Three simulated scenarios, made by one seeded script ([data/generate_data.R](data/generate_data.R);
data by Fangziyue Zhang, generated with Codex). Each file holds all four record types.

| File | Purpose |
|---|---|
| `data/baseline.csv` | 25 stations, 2 vans, 20 weekdays, in control |
| `data/planted_shift.csv` | same network; a planted dock fault and demand surge from weekday 11 |
| `data/edge_case.csv` | 2 stations, 1 day, with a gap and a conflicting duplicate, to test the rules |

The app bundles gzip copies in `app/data/` (made by `app/make_app_data.R`) because Posit Connect
only receives files inside `app/`.

## Statistical limits

Read these before trusting any number.

- **Simulated data.** Charts show behaviour of the method, not of a real system. The planted shift
  is engineered.
- **p charts (binomial assumption).** The limits assume that within a window every attempt fails
  independently with the same probability. Attempts at the same station and time may not be
  independent; then the limits are too narrow and a point beyond them is a prompt to investigate,
  not a confirmed special cause. The tool does not test this assumption.
- **c chart** counts failure onsets, not how long a failure lasts. A variance/mean check warns
  above 1.5 when the counts vary more than a Poisson model allows.
- **Cpu on the built-in data** only demonstrates the arithmetic. The tool never invents a spec
  limit; no USL means no Cpu. It needs an in-control, roughly normal process.
- **Forecast.** A Poisson model: rates constant within 15-minute bins, stations independent, riders
  who gave up without trying are not in the log. The event includes the state at t0 (a station
  already unusable has probability 1). The standard error is rough near 0 and 1. The bootstrap
  range is partly inflated by simulation noise. Only earlier weekdays are used (no look-ahead).
- **No move plan and no cause analysis.** The tool shows where and when stations fail and which are
  at risk; it does not recommend van moves, does not diagnose causes and does not measure whether
  rebalancing helps.
- **No observed failures does not mean zero risk.** Values that cannot be estimated show `NA` with
  a reason, never `Inf` or a made-up number.

## How it was checked

- testthat suites in [tests/](tests/) reproduce the hand-worked known answers of the features kept
  (KA-1, KA-1b, KA-2 to KA-2c, KA-6, KA-7, KA-8b to KA-8d, KA-11) from
  [docs/methods.md](docs/methods.md) section 4.2, plus degenerate cases (constant data, n = 1,
  missing values). Last full run: 458 passing, 0 failing.
- Independent statistics reviews of each statistic, Playwright checks of the screens, and a
  logged-out check of the live URL (HTTP 200).
- Scope: the I-MR chart, the p chart's dispersion test, Kaplan-Meier, availability/R(tau), the
  three-policy comparison, the Pareto chart, the Diagnosis tab (fault trees) and the Rebalancing tab
  (move plan and simulated task statuses) were removed on 2026-10-17 at the team's request (task
  H-19); their earlier checks are in git history and [CONTRACT.yaml](CONTRACT.yaml).

## Project status (what is NOT done)

- H-01: the method sentence from the other teammates is not yet in.
- H-05: a teammate has not yet followed [demo/README.md](demo/README.md) end to end.
- H-07 (this README): needs a teammate to follow it from a fresh clone.
- H-08: the Devpost submission is not done.

The task ledger is [CONTRACT.yaml](CONTRACT.yaml); the tool definition is [SPEC.md](SPEC.md).

## Deploy (brief)

The app is deployed to the course Posit Connect server by
`.github/workflows/deploy-shiny-r.yml` on every push to `main`. The repo secrets
`CONNECT_SERVER` and `CONNECT_API_KEY` live in GitHub repo secrets, never in files. After any code
or data change, run `Rscript app/manifestme.R` and commit the new `app/manifest.json`. Details:
[app/README.md](app/README.md).

## Repo map

```
app/        the Shiny app and its R code (function reference: app/README.md)
tests/      testthat suites and fixtures
data/       three simulated scenarios, codebook, generator
demo/       walkthrough (README.md) and print_demo_numbers.R
docs/       methods.md (formulas, known answers), plus the event pages (criteria.md, schedule.md)
SPEC.md, CONTRACT.yaml   tool definition and task ledger
```

Event rules and the judging rubric stay in [docs/criteria.md](docs/criteria.md) and
[docs/schedule.md](docs/schedule.md).

## Credits

- Course textbook: https://timothyfraser.com/sigma/
- SPC constants (A2, D3, D4, d2) from Montgomery, *Introduction to Statistical
  Quality Control*, as cited in the comments of [app/qc.R](app/qc.R).
- Data layout inspired by GBFS (https://github.com/MobilityData/gbfs); it is an internal format,
  not a native GBFS feed ([data/README.md](data/README.md)).
- R packages: shiny, bslib, ggplot2, leaflet; testthat for tests; rsconnect for deploy.
