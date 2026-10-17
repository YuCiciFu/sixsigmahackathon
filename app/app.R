# Rush Hour Autopilot - Shiny dashboard (team 2027win)
#
# app.R does the screen and the wiring ONLY:
#   app/qc.R    every statistic (loader, grid, p, c and X-bar/R charts, capability)
#   app/prep.R  data shaping (dates, counts of attempts, ranking, baseline choice)
#   app/plots.R ggplot drawing
#   app/sim.R   the demand model shared by the forecast (rates from earlier weekdays)
#   app/forecast.R  the current-state risk forecast, step 5a and the day bootstrap 5b (Forecast tab)
# Started from the demo in demos/shinyapp (one app.R with ui + server + shinyApp()).
#
# Run from the repo root:  Rscript app/testme.R

library(shiny)
library(bslib)
library(ggplot2)
library(leaflet)

source("qc.R", local = TRUE)      # the working directory is the app folder when the app runs
source("prep.R", local = TRUE)
source("plots.R", local = TRUE)
source("sim.R", local = TRUE)     # demand rates from earlier weekdays, used by the forecast
source("forecast.R", local = TRUE)   # the Now risk forecast, step 5a (H-13) and the day bootstrap 5b (H-14)

# Built-in scenarios (H-02 data): app/data/*.csv.gz in the deployed bundle, ../data/*.csv in a
# clone. With none, fall back to the tiny test fixture, else ask for an upload.
BUILTIN <- builtin_scenarios(".")
DEFAULT_PATH <- if (length(BUILTIN) > 0) unname(BUILTIN[1]) else default_scenario_path(".")
options(shiny.maxRequestSize = 100 * 1024^2)  # 100 MiB uploads (planted_shift.csv is about 47 MB)

# Shared by every session of this R process: a built-in scenario is loaded (and its minute
# grids built) once, not once per visitor. Uploads are never cached.
CACHE <- new.env(parent = emptyenv())
cached <- function(key, value) {
  if (!exists(key, envir = CACHE, inherits = FALSE)) assign(key, value, envir = CACHE)
  get(key, envir = CACHE, inherits = FALSE)
}

# What pauses when a record type cannot be used (see table_block_message in prep.R).
NEEDS_STATUS <- "the map, the minute grid, the station views, the c chart and the forecast"
NEEDS_ATTEMPTS <- "the failure rates and the p charts"
NEEDS_TASKS <- "the X-bar/R chart of response time and the capability indices"

help_text <- function(...) tags$p(class = "text-muted small", ...)
# A card that keeps its natural height (the page scrolls instead of squeezing cards).
panel_card <- function(...) card(..., fill = FALSE)
alert_box <- function(text, type = "warning") tags$div(class = paste0("alert alert-", type), text)
# A numeric box that starts EMPTY (the value is NA in R). numericInput(value = NA) writes value="NA"
# into the HTML, which browsers warn about; dropping the attribute gives the same empty box.
blank_numeric_input <- function(...) {
  htmltools::tagQuery(numericInput(..., value = NA))$find("input")$removeAttrs("value")$allTags()
}
# The c chart's Poisson check (computed in qc.R c_dispersion; shown here only).
c_dispersion_box <- function(d) {
  if (is.na(d$ratio)) return(alert_box(paste("Dispersion check:", d$note), "secondary"))
  alert_box(paste0("Dispersion check on the baseline: variance ", sprintf("%.2f", d$variance), " / mean ",
                   sprintf("%.2f", d$mean), " = ", sprintf("%.2f", d$ratio), ". ",
                   toupper(substr(d$note, 1, 1)), substring(d$note, 2), "."),
            if (isTRUE(d$warning)) "warning" else "info")
}

# ------------------------------------------------------------------ UI
ui <- page_navbar(
  id = "tabs",
  title = "Rush Hour Autopilot",
  fillable = FALSE,
  sidebar = sidebar(
    width = 320,
    tags$b("Data (simulated)"),
    if (length(BUILTIN) > 0) {
      selectInput("scenario", "Built-in scenario (simulated test data)", choices = names(BUILTIN))
    },
    fileInput("upload", "Or upload a scenario CSV (long form, with a `table` column)",
              accept = c(".csv", "text/csv", ".gz")),
    uiOutput("data_info"),
    tags$hr(),
    tags$b("Rush window"),
    selectInput("date", "Date (weekdays in the scenario)", choices = character(0)),
    sliderInput("minute", "Observation minute (minutes after 07:00)", min = 0, max = 179,
                value = 5, step = 1),
    textOutput("clock"),
    tags$hr(),
    tags$b("Parameters"),
    numericInput("stale_limit", "stale_limit, minutes (demo assumption)", 2, min = 0, step = 1),
    numericInput("warn_k", "Early-warning threshold, bikes or docks (ranking only)", 2, min = 1, step = 1),
    numericInput("detour", "Detour factor (demo assumption; forecast, vans on the way)", 1.3, min = 1, max = 3, step = 0.1),
    sliderInput("min_coverage", "Minimum coverage for SPC (demo assumption)", 0.5, 1, 0.95, step = 0.01),
    sliderInput("baseline_share", "Baseline share (first part of the weekdays)", 0.1, 1, 0.5, step = 0.05)
  ),

  nav_panel("Overview",
    uiOutput("upload_help"),
    uiOutput("health_banner"),
    help_text("How to read this: the map shows each station's state at the chosen date and minute,",
              " from the minute grid (most recent snapshot at or before that minute, no older than",
              " stale_limit). Grey = unknown/stale data; it is never shown as normal."),
    uiOutput("kpis"),
    layout_columns(
      fill = FALSE,
      col_widths = c(7, 5),
      panel_card(card_header("Station map at the chosen minute"), uiOutput("map_note"),
                 leafletOutput("map", height = 450)),
      panel_card(card_header("Station ranking (whole 07:00-10:00 window of the chosen date)"),
           help_text("Rank 1 = worst: either-unusable minutes + early-warning minutes; ties by station_id."),
           tableOutput("ranking"))
    ),
    panel_card(card_header("Data issues (rows rejected or flagged when the file was loaded)"),
         help_text("Rows per record type: in the file, valid after loading, rejected, and identical copies kept once."),
         tableOutput("health_tbl"),
         help_text("Issues counted by record type and rule:"),
         tableOutput("issue_summary_tbl"),
         textOutput("issue_detail_caption"),
         tableOutput("issues"))
  ),

  nav_panel("Stations",
    selectInput("station", "Station", choices = character(0)),
    panel_card(card_header("Inventory trend"),
         help_text("How to read this: bikes and docks minute by minute; gaps = unknown/stale minutes."),
         plotOutput("trend", height = 350)),
    panel_card(card_header("Unusable and warning minutes per station"),
         help_text("Minutes are counted over KNOWN minutes only; compare stations by coverage-aware",
                   " numbers, not raw totals. Early warning is for ranking and is not a failure."),
         tableOutput("station_tbl")),
    panel_card(card_header("Heatmap: either-unusable minutes by hour and station"),
         help_text("How to read this: darker = more unusable minutes in that hour."),
         plotOutput("heatmap", height = 400))
  ),

  nav_panel("Quality",
    uiOutput("baseline_info"),
    panel_card(card_header("p chart: rent failure proportion"),
         help_text("How to read this: each point is one weekday rush window (% of rent attempts that failed);",
                   " red points are beyond the 3-sigma limits from the baseline (dashed) or in a run of 8.",
                   " Assumes a binomial model: within a window every attempt fails independently with the same",
                   " probability. Attempts at the same station and time may not be independent; then the",
                   " limits are too narrow and a point beyond them is a prompt to investigate."),
         uiOutput("p_rent_note"), plotOutput("p_rent_plot", height = 350), tableOutput("p_rent_tbl")),
    panel_card(card_header("p chart: return failure proportion"),
         help_text("How to read this: same as above for return attempts."),
         uiOutput("p_return_note"), plotOutput("p_return_plot", height = 350), tableOutput("p_return_tbl")),
    panel_card(card_header("Windows excluded from the c chart (coverage below the minimum)"), tableOutput("excluded_tbl")),
    panel_card(card_header("c chart: anomaly onsets per rush window (fixed station set)"),
         help_text("An anomaly onset is a station-minute that is unusable (empty, full or switched off) right",
                   " after a minute that was known and usable at the same station. A switch across a gap of",
                   " unknown data is not counted. One point per included weekday window (windows below the",
                   " minimum coverage are left out and listed above); red points are beyond the 3-sigma limits",
                   " or in a run of 8.",
                   " The box below checks the Poisson assumption behind the limits.",
                   " In control here does NOT mean the stations are healthy: a long outage adds only one onset",
                   " and then none, so this chart counts how often stations break, not how long they stay",
                   " broken. The Overview and Stations tabs show the level of unusable time."),
         uiOutput("c_note"), plotOutput("c_plot", height = 350), tableOutput("c_tbl")),
    panel_card(card_header("X-bar and R chart: van response time (minutes from assigned to arrived)"),
         help_text("Each point is one weekday rush window (07:00-10:00 New York). A subgroup is the first 3",
                   " completed tasks of the window, ordered by assigned_at; windows with fewer than 3 are",
                   " dropped and listed below. Limits use the baseline subgroups only: X-bar limits",
                   " X-double-bar +/- A2*R-bar, R limits D3*R-bar and D4*R-bar (n = 3: A2 = 1.023, D3 = 0,",
                   " D4 = 2.574, d2 = 1.693)."),
         uiOutput("xr_note"), plotOutput("xbar_plot", height = 330), plotOutput("r_plot", height = 300),
         tableOutput("xr_tbl"),
         help_text("Windows dropped (fewer than 3 usable completed tasks):"),
         tableOutput("xr_dropped_tbl")),
    panel_card(card_header("Capability of response time (needs your specification limits)"),
         help_text("The USL and LSL below are YOUR inputs in minutes, not measured specifications; the tool",
                   " never invents them. With no USL nothing is computed. Capability is computed only when the",
                   " X-bar/R chart is in control. sigma-hat = R-bar/d2 (within-subgroup spread, so these are",
                   " Cp/Cpk, not Pp/Ppk). Assumes an approximately normal process; see the check below.",
                   " In the built-in simulated files every subgroup is the same 9, 10 and 11 minutes, so an",
                   " index here only demonstrates the arithmetic; it is not a capability claim about any real fleet."),
         layout_columns(
           fill = FALSE, col_widths = c(3, 3, 6),
           blank_numeric_input("usl", "Upper spec limit USL, minutes (your input)", step = 0.5),
           blank_numeric_input("lsl", "Lower spec limit LSL, minutes (your input, optional)", step = 0.5),
           uiOutput("cap_head")),
         tableOutput("cap_tbl"),
         uiOutput("normality_box"),
         plotOutput("cap_hist", height = 300))
  ),

  nav_panel("Forecast",
    panel_card(card_header("Now: risk forecast from the current state (a model, step 5a fixed rates; step 5b day bootstrap on request)"),
      help_text("A model, not a measurement. Question: starting from each station's inventory at the",
                " origin t0 (sidebar date + observation minute), what is the probability that the station is",
                " rent-unusable now or at least once within the next 10, 20 and 30 minutes (and separately",
                " return-unusable)? A station already unusable at t0 is 1. It is simulated forward R times with the",
                " demand rates of the earlier weekdays."),
      uiOutput("fc_date_hint"),
      layout_columns(
        fill = FALSE, col_widths = c(3, 3, 3, 3),
        numericInput("fc_R", "Simulated paths R", 2000, min = 100, max = 20000, step = 100),
        numericInput("fc_seed", "Seed", 1, step = 1),
        numericInput("fc_speed", "Van speed, km/h (demo assumption, vans on the way)", 20, min = 1, step = 1),
        tags$div(help_text("Also uses the sidebar date, observation minute, stale_limit and detour factor.",
                           " Runs only when you click."),
                 actionButton("run_fc", "Run forecast", class = "btn-primary"))),
      layout_columns(
        fill = FALSE, col_widths = c(6, 3, 3),
        tags$div(checkboxInput("fc_boot", "Add parameter uncertainty (day bootstrap)", FALSE),
                 help_text("Step 5b. Resamples the earlier weekdays with replacement, re-estimates the rates and",
                           " simulates each set. Takes about 20 s for 25 stations at the defaults.")),
        numericInput("fc_B", "Bootstrap sets B", 200, min = 2, max = 1000, step = 50),
        numericInput("fc_Rb", "Paths per bootstrap set", 200, min = 20, max = 2000, step = 50)),
      uiOutput("fc_head"),
      tableOutput("fc_tbl"),
      help_text("How to read this: each cell is the share of R simulated futures with at least one unusable minute",
                " in the horizon, and (SE) is the simulation error (ii). Sorted by the highest 30-minute risk. A station",
                " that is already unusable at t0 says so in the last column. * = the horizon extends past 10:00 and",
                " reuses the last 15-minute bin rate (09:45-10:00). n/a = no forecast, with the reason. With the day",
                " bootstrap on, the (iii) columns give the 2.5-97.5% range of the risk when the rates are re-estimated",
                " from resampled days; it is a separate statement from the SE and is never added to it."),
      plotOutput("fc_plot", height = 380),
      tags$b("Day bootstrap details (all horizons)"), tableOutput("fc_boot_tbl"),
      help_text("(iii) = percentile range over the bootstrap rate sets. 'mean SE inside sets' is the average Monte Carlo",
                " error of each set: the range still contains some simulation error from the paths per set, so a range",
                " not much wider than that SE says little about the rates. Common random numbers are used in every set,",
                " but they only partly cancel that noise, so the range can be somewhat wider than the rate uncertainty",
                " alone, and the 5a estimate (from R paths) can fall just outside it. With fewer than about 5 earlier",
                " weekdays the resampled rates take only a few values, so the range is very rough."),
      tags$b("Vans on the way at t0"), tableOutput("fc_transit_tbl"),
      help_text("A van counts as on the way when its task was assigned by t0 and not completed by t0. Demo assumption:",
                " it arrives at assigned_at + straight-line km x detour / speed, the pickup has already happened",
                " (its effect is in the source's snapshot) and the planned bikes are added to the destination then,",
                " capped by its free docks. The logged arrival times are never used, because they may lie after t0."),
      tags$b("Uncertainty, reported as three separate things"), uiOutput("fc_uncertainty"),
      tags$b("Assumptions"),
      tags$ul(
        tags$li("Rents and returns arrive as independent Poisson processes per station; the rate is constant inside each",
                " 15-minute bin; stations are independent (no interaction between stations)."),
        tags$li("Rate = attempts (successful + failed) / known station-minutes in that bin, over the weekdays STRICTLY",
                " BEFORE t0's date; nothing after t0 is used (no look-ahead). A rate of 0 is valid and does not show",
                " that the risk is zero."),
        tags$li("Riders who gave up without trying are not in the log, so demand may be understated."),
        tags$li("Start inventory = the latest valid snapshot at or before t0 that passes the stale_limit age rule;",
                " otherwise no forecast (n/a). Renting and returning flags stay at their t0 values."),
        tags$li("The event is: unusable at t0 itself OR at any minute from t0+1 to t0+h (events of all h minutes",
                " applied). So a station that is already unusable at t0 (0 bikes, 0 docks or a flag off) has risk",
                " exactly 1 on that side, by definition, and says so in the last column."),
        tags$li("The simulation SE sqrt(p(1-p)/R) is only a rough guide near 0 or 1 (e.g. 0.999 at R = 2000 can",
                " be about 0.997 in a longer run); raise R for such stations."),
        tags$li("Day bootstrap (step 5b, only when ticked): the unit is an earlier weekday, resampled with replacement;",
                " the rates are re-estimated with the same definition (a day drawn twice counts twice in numerator and",
                " denominator); days are treated as exchangeable (no weekday or trend effect). With few earlier days",
                " the resampled rates take few distinct values, so the range is rough; with fewer than 2 it is n/a."),
        tags$li("A van's estimated arrival is rounded down to the start of its minute (up to 1 minute early);",
                " demo assumption.")),
      tags$b("Source days (weekdays before t0's date)"), textOutput("fc_days"),
      tags$b("Bin rates used (network mean over the stations forecast)"), tableOutput("fc_rates_tbl"))
  )
)

# ------------------------------------------------------------------ server
server <- function(input, output, session) {

  # ---- data source: the latest choice wins (an upload, or a built-in scenario picked after it);
  # with neither, the default file; with no default file, an upload panel.
  use_upload <- reactiveVal(FALSE)
  observeEvent(input$upload, use_upload(TRUE))
  observeEvent(input$scenario, use_upload(FALSE), ignoreInit = TRUE)
  scn <- reactive({
    upload <- use_upload() && !is.null(input$upload)
    path <- if (upload) input$upload$datapath else if (!is.null(input$scenario) &&
                                                       input$scenario %in% names(BUILTIN)) {
      unname(BUILTIN[input$scenario])
    } else DEFAULT_PATH
    label <- if (upload) input$upload$name else if (is.na(path)) NA else basename(path)
    if (is.na(path)) {
      return(list(ok = FALSE, label = NA, message = paste(
        "No scenario file found. Upload a long-form scenario CSV with a `table` column",
        "(record types: stations, status, attempts, tasks; schema in docs/methods.md section 7).")))
    }
    key <- if (upload) NULL else normalizePath(path, winslash = "/")
    tryCatch(list(ok = TRUE, label = label, key = key, fixture = !upload && grepl("fixtures", path),
                  data = if (is.null(key)) load_scenario(path) else cached(paste("scenario", key), load_scenario(path))),
             error = function(e) list(ok = FALSE, label = label, message = conditionMessage(e)))
  })

  # the loaded data, or a message shown in place of every output
  sc <- reactive({
    s <- scn()
    validate(need(isTRUE(s$ok), if (isTRUE(s$ok)) "" else s$message))
    s$data
  })
  # Rows per record type. Stations are required for everything; status and attempts each
  # pause only the features that need them (tasks: the X-bar/R chart and capability).
  health <- reactive(table_health(sc()))
  stations_ok <- reactive({
    msg <- table_block_message(health(), sc()$issues, "stations", "no part of the scenario")
    validate(need(is.null(msg), msg))
    TRUE
  })
  status_msg <- reactive(table_block_message(health(), sc()$issues, "status", NEEDS_STATUS))
  attempts_msg <- reactive(table_block_message(health(), sc()$issues, "attempts", NEEDS_ATTEMPTS))
  tasks_msg <- reactive(table_block_message(health(), sc()$issues, "tasks", NEEDS_TASKS))

  dates <- reactive({
    stations_ok()
    d <- scenario_dates(sc()$status, sc()$attempts)
    validate(need(length(d) > 0, paste(c("The scenario has no weekday status or attempt rows.",
                                         status_msg(), attempts_msg()), collapse = " ")))
    d
  })

  # A new file first clears the date list, so dates of the previous file never linger.
  observeEvent(sc(), updateSelectInput(session, "date", choices = character(0)), priority = 10)

  observeEvent(dates(), {
    updateSelectInput(session, "date", choices = dates(), selected = dates()[1])
  })

  # The forecast uses only weekdays BEFORE the sidebar date (no look-ahead), so the first
  # weekday has no history. Say so before the user clicks Run, and offer
  # one-click dates that do have history. Nothing here reads data after the chosen date.
  date_hint <- function(prefix, needs) {
    renderUI({
      req(input$date)
      h <- history_info(dates(), input$date)
      buttons <- tags$div(class = "mb-2",
        if (!is.na(h$first_with_history)) actionButton(paste0(prefix, "_first"),
          paste("Use the first date with history (", h$first_with_history, ")"), class = "btn-sm btn-outline-primary"),
        if (!is.na(h$first_with_history)) actionButton(paste0(prefix, "_latest"),
          paste("Use the latest date (", h$latest, ")"), class = "btn-sm btn-outline-primary"))
      if (is.na(h$first_with_history)) {        # one weekday only: no date in this file has history
        alert_box(paste0("This file has only one weekday (", input$date, "), so no date has earlier weekdays to",
                         " estimate demand from and ", needs, " cannot run. Load a file with at least two weekdays.",
                         " The tool never uses the chosen day or later days for this (no look-ahead)."), "warning")
      } else if (h$n_before == 0) {
        tagList(alert_box(paste0(input$date, " is the first weekday in the file: there are no earlier weekdays to",
                                 " estimate demand from, so ", needs, " cannot run for this date. Pick a later date in the",
                                 " sidebar or click a button below. The tool never uses the chosen day or later days for",
                                 " this (no look-ahead)."), "warning"), buttons)
      } else {
        tagList(help_text(paste0("History for ", input$date, ": ", h$n_before, " earlier weekday(s).",
                                 if (h$n_before < 2) " The day bootstrap needs at least 2." else "")), buttons)
      }
    })
  }
  output$fc_date_hint <- date_hint("fc", "the forecast")
  pick_date <- function(which) {
    h <- history_info(dates(), input$date)
    d <- if (which == "first") h$first_with_history else h$latest
    if (!is.na(d)) updateSelectInput(session, "date", selected = d)
  }
  observeEvent(input$fc_first, pick_date("first"))
  observeEvent(input$fc_latest, pick_date("latest"))
  observeEvent(sc(), {
    ids <- sc()$stations$station_id
    names(ids) <- paste(ids, "-", sc()$stations$station_name)
    updateSelectInput(session, "station", choices = ids)
  })

  stale_limit <- reactive({ req(input$stale_limit >= 0); input$stale_limit })
  grids <- reactive({
    validate(need(is.null(status_msg()), status_msg()))
    key <- scn()$key
    if (is.null(key)) return(build_day_grids(sc()$status, sc()$stations, dates(), stale_limit()))
    cached(paste("grids", key, stale_limit()), build_day_grids(sc()$status, sc()$stations, dates(), stale_limit()))
  })
  grid <- reactive({           # the chosen day, with the chosen early-warning threshold
    req(input$date, input$date %in% names(grids()), input$warn_k)
    set_warning_threshold(grids()[[input$date]], input$warn_k)
  })
  summ <- reactive(rank_stations(unusable_summary(grid())))
  att_all <- reactive({
    validate(need(is.null(attempts_msg()), attempts_msg()))
    attempts_by_day(sc()$attempts, dates())
  })
  state <- reactive({
    req(input$minute)
    state_at(grid(), input$minute)
  })
  fixed_ids <- reactive(fixed_station_set(sc()$status, sc()$stations, dates()))
  windows <- reactive({
    window_table(grids(), fixed_ids(), dates(), input$min_coverage)
  })

  # ---- sidebar
  output$data_info <- renderUI({
    s <- scn()
    if (isTRUE(s$ok)) {
      n <- sc()
      tagList(help_text("Source: ", s$label, ". All data in this version are simulated."),
              help_text(nrow(n$stations), " stations, ", nrow(n$status), " status rows, ",
                        nrow(n$attempts), " attempts, ", nrow(n$tasks), " tasks after validation."))
    } else if (!is.na(s$label)) {
      alert_box(s$message, "danger")
    }
  })
  output$clock <- renderText({
    m <- input$minute
    if (is.null(m)) return("")
    sprintf("Observation time: %02d:%02d (New York). Window 07:00-10:00.", 7 + m %/% 60, m %% 60)
  })

  # ---- Overview
  output$upload_help <- renderUI({
    s <- scn()
    if (isTRUE(s$ok)) {
      if (isTRUE(s$fixture)) {
        alert_box(paste("Showing the tiny test fixture (edge_small.csv) because data/baseline.csv was not",
                        "found. Most minutes are unknown there on purpose. Simulated data."), "info")
      }
    } else {
      panel_card(card_header("Provide a scenario file"),
           tags$p(s$message),
           tags$p("Use the upload box in the sidebar. The file must be UTF-8 CSV with a header row and a",
                  tags$code("table"), "column whose values are", tags$code("stations"), ",",
                  tags$code("status"), ",", tags$code("attempts"), ",", tags$code("tasks"),
                  ". Example: data/baseline.csv in the project repository (simulated)."))
    }
  })

  output$kpis <- renderUI({
    req(input$date)
    # Each half pauses on its own: status feeds the minute boxes, attempts the failure boxes.
    s_ok <- is.null(status_msg())
    a_ok <- is.null(attempts_msg())
    counts <- if (s_ok) grid_window_counts(grid(), NULL, input$date) else
      data.frame(known = 0, unknown = 0, either_min = 0)
    att <- if (a_ok) att_all()[att_all()$date == input$date, ] else
      data.frame(rent_n = 0, rent_fail = 0, return_n = 0, return_fail = 0)
    k <- kpi_summary(counts, att)
    pct <- function(x) if (is.na(x)) "n/a" else sprintf("%.1f%%", x)
    box <- function(title, value, detail) value_box(title, value, tags$small(detail))
    paused <- function(title, what) box(title, "paused", paste("no valid", what, "records"))
    layout_column_wrap(
      width = 1 / 3, fill = FALSE,
      if (s_ok) box("Either-unusable share", pct(k$either_share_pct),
                    paste0(counts$either_min, " of ", k$known, " known station-minutes"))
      else paused("Either-unusable share", "status"),
      if (a_ok) box("Rent failure", pct(k$rent_fail_pct), paste0(k$rent_fail, "/", k$rent_n, " rent attempts"))
      else paused("Rent failure", "attempts"),
      if (a_ok) box("Return failure", pct(k$return_fail_pct), paste0(k$return_fail, "/", k$return_n, " return attempts"))
      else paused("Return failure", "attempts"),
      if (s_ok) box("Known minutes", format(k$known), "station-minutes with a valid recent snapshot")
      else paused("Known minutes", "status"),
      if (s_ok) box("Unknown minutes", format(k$unknown), "left out of every rate; never counted as usable")
      else paused("Unknown minutes", "status"),
      if (s_ok) box("Coverage", pct(100 * k$coverage), "known / (known + unknown)")
      else paused("Coverage", "status")
    )
  })

  output$health_banner <- renderUI({
    req(isTRUE(scn()$ok))
    h <- health()
    msgs <- c(table_block_message(h, sc()$issues, "stations", "no part of the scenario"),
              status_msg(), attempts_msg())
    partial <- h[h$state == "some rejected", ]
    tagList(
      lapply(msgs, function(m) alert_box(m, "danger")),
      if (nrow(partial) > 0) {
        alert_box(paste0("Some rows were rejected and left out: ",
                         paste0(partial$rejected, " of ", partial$in_file, " ", partial$table, collapse = "; "),
                         ". The rest of the file is used. See Data issues."), "warning")
      }
    )
  })

  # The map widget is built ONCE (tiles + legend) and never rebuilt; markers and the view are
  # updated through leafletProxy. Rebuilding the whole widget on every minute/date/file change
  # while the Overview tab was hidden left a stale resize handler on a removed map
  # ("Cannot read properties of undefined (reading '_leaflet_pos')").
  output$map <- renderLeaflet({
    leaflet() |>
      addTiles() |>
      setView(lng = -76.5, lat = 42.44, zoom = 13) |>
      addLegend("bottomright", colors = unname(STATE_COLOURS[STATE_LEVELS]), labels = STATE_LEVELS,
                title = "Station state", opacity = 1)
  })
  map_ready <- reactiveVal(FALSE)          # TRUE once the browser has drawn the map
  observeEvent(input$map_zoom, map_ready(TRUE), once = TRUE)

  # Fit the view to the stations of each new file, once, and only while the Overview tab is
  # shown: a hidden map has zero size, so fitting it then would zoom out to the whole world.
  # Not on every minute or tab change, so a user's own zoom stays.
  fit_pending <- reactiveVal(FALSE)
  observeEvent(sc(), fit_pending(TRUE))
  observeEvent(list(fit_pending(), map_ready(), input$tabs), {
    req(fit_pending(), map_ready(), identical(input$tabs, "Overview"))
    stn <- sc()$stations
    req(nrow(stn) > 0)
    pad <- 0.005
    leafletProxy("map") |>
      fitBounds(min(stn$longitude) - pad, min(stn$latitude) - pad,
                max(stn$longitude) + pad, max(stn$latitude) + pad)
    fit_pending(FALSE)
  })

  # Station markers for the chosen date and minute. Old markers are cleared first, so a file
  # without valid status rows never keeps the previous file's stations on the map.
  observe({
    req(map_ready())
    proxy <- leafletProxy("map") |> clearMarkers()
    req(isTRUE(scn()$ok), is.null(status_msg()))
    st <- state()
    stn <- sc()$stations
    m <- stn[match(st$station_id, stn$station_id), ]
    m$state <- factor(st$state, levels = STATE_LEVELS)
    pal <- colorFactor(unname(STATE_COLOURS[STATE_LEVELS]), domain = factor(STATE_LEVELS, levels = STATE_LEVELS))
    popup <- station_popup(m$station_name, m$station_id, as.character(m$state),
                           st$bikes_available, st$docks_available)
    proxy |>
      addCircleMarkers(data = m, lng = ~longitude, lat = ~latitude, radius = 9, color = "black", weight = 1,
                       fillColor = ~pal(state), fillOpacity = 0.9, popup = popup)
  })
  output$map_note <- renderUI({
    req(isTRUE(scn()$ok))
    if (!is.null(status_msg())) alert_box(status_msg(), "danger")
  })

  output$ranking <- renderTable({
    r <- station_table(summ(), sc()$stations)
    r$rank <- seq_len(nrow(r))
    r[, c("rank", "station_id", "station", "either_unusable_min", "warning_min", "known_min", "coverage_pct")]
  }, digits = 1)

  output$health_tbl <- renderTable(health())
  output$issue_summary_tbl <- renderTable({
    s <- issue_summary(sc()$issues)
    if (nrow(s) == 0) data.frame(note = "No data issues found.") else s
  })
  output$issue_detail_caption <- renderText({
    n <- nrow(sc()$issues)
    if (n == 0) "" else sprintf("Issue rows: showing the first %d of %d.", min(n, 200), n)
  })
  output$issues <- renderTable({
    iss <- sc()$issues
    if (nrow(iss) == 0) NULL else issue_detail(iss, 200)
  })

  # ---- Stations
  output$trend <- renderPlot({
    req(input$station)
    g <- grid()[grid()$station_id == input$station, ]
    nm <- sc()$stations$station_name[sc()$stations$station_id == input$station]
    plot_trend(g, paste0(input$station, " ", nm, ", ", input$date,
                         " (", sum(g$known), " known, ", sum(!g$known), " unknown minutes)"))
  })
  output$station_tbl <- renderTable(station_table(summ(), sc()$stations), digits = 1)
  output$heatmap <- renderPlot(plot_heatmap(hour_station_matrix(grid())))

  # ---- Quality
  output$baseline_info <- renderUI({
    d <- dates()
    p_part <- if (is.null(attempts_msg())) {
      n_p <- sum(att_all()$rent_n > 0)
      paste0("p charts: first ", baseline_count(n_p, input$baseline_share), " of ", n_p, " weekdays with attempts. ")
    } else "p charts: paused (no valid attempts records). "
    c_part <- if (is.null(status_msg())) {
      inc <- windows()$included
      paste0("c chart: first ", baseline_count(sum(inc), input$baseline_share), " of ", sum(inc), " included windows. ")
    } else "c chart: paused (no valid status records). "
    x_part <- if (is.null(tasks_msg())) {
      n_x <- nrow(response_subgroups(sc()$tasks, d)$values)
      paste0("X-bar/R: first ", baseline_count(n_x, input$baseline_share), " of ", n_x, " subgroups. ")
    } else "X-bar/R: paused (no valid tasks records). "
    alert_box(paste0("Baseline (limits are estimated from these only): the first ", input$baseline_share * 100,
                     "% of weekdays, at least 1. ", p_part, c_part,
                     x_part, length(d), " weekdays in the scenario."), "info")
  })

  p_panel <- function(kind) {
    n_col <- paste0(kind, "_n")
    fail_col <- paste0(kind, "_fail")
    res <- reactive({
      a <- att_all()
      p_chart(a[[fail_col]], a[[n_col]], baseline = baseline_flags(a[[n_col]] > 0, input$baseline_share))
    })
    out <- list()
    out$note <- renderUI({
      r <- res()
      if (nzchar(r$note)) alert_box(paste("Control limits not drawn or limited:", r$note), "warning")
    })
    out$plot <- renderPlot({
      validate(need(any(!is.na(res()$data$p)), paste("No", kind, "attempts in the weekday windows: nothing to plot.")))
      plot_p(res(), att_all()$date, paste0(kind, " failure (%)"), paste("p chart:", kind, "failures"),
             ooc_label = signal_label(TRUE, FALSE), ok_label = signal_label(FALSE, FALSE))
    })
    out$tbl <- renderTable({
      d <- res()$data
      data.frame(date = att_all()$date, failures_over_n = paste0(d$failures, "/", d$n),
                 percent = round(100 * d$p, 2), center_pct = round(100 * d$center, 2),
                 UCL_pct = round(100 * d$ucl, 2), LCL_pct = round(100 * d$lcl, 2),
                 signal = signal_label(d$out_of_control, FALSE))
    }, na = "n/a")
    out
  }
  rent <- p_panel("rent")
  ret <- p_panel("return")
  output$p_rent_note <- rent$note;   output$p_rent_plot <- rent$plot;   output$p_rent_tbl <- rent$tbl
  output$p_return_note <- ret$note;  output$p_return_plot <- ret$plot;  output$p_return_tbl <- ret$tbl

  output$excluded_tbl <- renderTable({
    w <- windows()
    ex <- w[!w$included, ]
    if (nrow(ex) == 0) return(data.frame(note = "No window is excluded."))
    data.frame(date = ex$window, known_min = ex$known, unknown_min = ex$unknown,
               coverage_pct = round(100 * ex$coverage, 1), reason = ex$reason)
  }, na = "n/a")

  # ---- c chart: anomaly onsets (counted in qc.R count_onsets, limits in qc.R c_chart)
  onsets <- reactive({
    validate(need(is.null(status_msg()), status_msg()))
    inc <- windows()[windows()$included, ]
    validate(need(nrow(inc) > 0, "No window has enough coverage for the c chart (see the excluded list above)."))
    counts <- onset_window_table(grids(), fixed_ids(), inc$window)$onsets
    list(windows = inc,
         res = c_chart(counts, baseline = baseline_flags(rep(TRUE, nrow(inc)), input$baseline_share)))
  })
  output$c_note <- renderUI({
    r <- onsets()$res
    tagList(
      if (nzchar(r$note)) alert_box(paste("Control limits not drawn or limited:", r$note), "warning"),
      c_dispersion_box(r$dispersion))
  })
  output$c_plot <- renderPlot({
    o <- onsets()
    w <- o$res$dispersion$warning
    plot_c(o$res, o$windows$window, "anomaly onsets per window", "c chart: anomaly onsets",
           ooc_label = signal_label(TRUE, w, model = "Poisson"), ok_label = signal_label(FALSE, w, model = "Poisson"))
  })
  output$c_tbl <- renderTable(c_chart_table(onsets()$windows, onsets()$res), na = "n/a")

  # ---- X-bar and R chart of response time, and capability
  resp <- reactive({
    validate(need(is.null(tasks_msg()), tasks_msg()))
    sub <- response_subgroups(sc()$tasks, dates())
    list(sub = sub,
         res = xbar_r_chart(sub$values, baseline = baseline_flags(rep(TRUE, nrow(sub$values)), input$baseline_share)))
  })
  resp_ok <- reactive({            # the subgroups, or a message when no window has 3 usable tasks
    r <- resp()
    validate(need(nrow(r$sub$values) > 0,
                  "No rush window has 3 completed tasks with both times: nothing to chart (see the dropped list)."))
    r
  })
  output$xr_note <- renderUI({
    r <- resp()$res
    if (nrow(resp()$sub$values) > 0 && nzchar(r$note)) {
      alert_box(paste("Control limits not drawn:", r$note), "warning")
    }
  })
  output$xbar_plot <- renderPlot({
    r <- resp_ok()
    plot_xbar(r$res, r$sub$windows, "mean response time (minutes)", "X-bar chart")
  })
  output$r_plot <- renderPlot({
    r <- resp_ok()
    plot_r(r$res, r$sub$windows, "range of response time (minutes)", "R chart")
  })
  output$xr_tbl <- renderTable({
    r <- resp_ok()
    xbar_r_table(r$sub, r$res)
  }, na = "n/a")
  output$xr_dropped_tbl <- renderTable({
    dr <- resp()$sub$dropped
    if (nrow(dr) == 0) data.frame(note = "No window was dropped.") else dr
  })

  cap <- reactive(capability_indices(resp_ok()$res, usl = input$usl, lsl = input$lsl))
  output$cap_head <- renderUI({
    r <- resp_ok()
    cp <- cap()
    num <- function(x) if (is.na(x)) "n/a" else sprintf("%.3f", x)
    help_text("sigma-hat = R-bar/d2 = ", num(cp$sigma_hat), " min; X-double-bar = ", num(cp$xbarbar), " min; ",
              nrow(r$sub$values), " subgroups. USL and LSL: your inputs, not measured specs.")
  })
  output$cap_tbl <- renderTable(capability_table(cap()), na = "n/a")
  output$normality_box <- renderUI({
    nc <- normality_check(as.vector(resp_ok()$sub$values))
    alert_box(paste0("Normality check: ", nc$note, "."), if (is.na(nc$p_value)) "secondary" else
      if (nc$p_value < 0.05) "warning" else "info")
  })
  output$cap_hist <- renderPlot({
    r <- resp_ok()
    cp <- cap()
    plot_response_hist(as.vector(r$sub$values), cp$xbarbar, cp$usl, cp$lsl)
  })

  # ---- Forecast: Now (statistics in forecast.R, wording in prep.R, drawing in plots.R)
  # Runs only on the button. A paused data type shows its message instead of running.
  fc_res <- eventReactive(input$run_fc, {
    validate(need(is.null(status_msg()), status_msg()), need(is.null(attempts_msg()), attempts_msg()))
    req(input$date, input$date %in% names(grids()))
    validate(need(isTRUE(input$fc_R >= 1), "Simulated paths R must be at least 1."),
             need(!is.na(input$fc_seed), "Seed must be a number."))
    boot <- isTRUE(input$fc_boot)
    if (boot) {
      validate(need(isTRUE(input$fc_B >= 2), "Bootstrap sets B must be at least 2."),
               need(isTRUE(input$fc_Rb >= 1), "Paths per bootstrap set must be at least 1."))
    }
    params <- tryCatch(sim_params(detour = input$detour, speed_kmh = input$fc_speed),
                       error = function(e) conditionMessage(e))
    validate(need(is.list(params), params))
    withProgress(message = if (boot) "Running the forecast and the day bootstrap (about 20 s)" else "Running the forecast",
                 value = 0.5, {
      forecast_now(sc(), grids(), input$date, dates(), input$minute, R = input$fc_R,
                   seed = input$fc_seed, params = params,
                   bootstrap = boot, B = if (boot) input$fc_B else 200, R_b = if (boot) input$fc_Rb else 200)
    })
  })
  output$fc_head <- renderUI({
    f <- fc_res()
    clock <- format(f$t0, "%Y-%m-%d %H:%M", tz = APP_TZ)
    if (!f$ok) return(alert_box(paste0("No forecast for t0 = ", clock, ": ", f$reason, "."), "warning"))
    tagList(
      alert_box(paste0("Origin t0 = ", clock, ". ", sum(!is.na(f$table$p_rent_10)), " of ", nrow(f$table),
                     " stations forecast from ", length(f$source_days), " earlier weekday(s) (", f$n_attempts,
                     " attempts), R = ", f$R, " paths, seed ", f$seed, ". Simulated; inputs changed since the click",
                     " are not reflected until you run again."), "info"),
      if (isTRUE(f$bootstrap$ok) && f$bootstrap$n_days < 5) {
        alert_box(paste0("Only ", f$bootstrap$n_days, " earlier weekday(s) to resample: the day-bootstrap range (iii)",
                         " can take only a few distinct values and is very rough."), "warning")
      }
    )
  })
  output$fc_tbl <- renderTable(forecast_table_display(fc_res()), na = "n/a")
  output$fc_plot <- renderPlot({
    f <- fc_res()
    d <- forecast_plot_data(f)
    validate(need(!is.null(d), f$reason))
    h <- max(f$horizons)
    plot_forecast_risk(d, paste0("Risk within ", h, " min of ", format(f$t0, "%H:%M", tz = APP_TZ), ": top stations"),
                       paste0("Bars = probability of at least one unusable minute; thin black whisker = +/- 1 simulation SE (ii, R = ",
                              f$R, ")",
                              if (isTRUE(f$bootstrap$ok)) paste0("; wide orange bracket = 2.5-97.5% parameter range (iii, day bootstrap, B = ",
                                                                 f$bootstrap$B, ", R_b = ", f$bootstrap$R_b, ")")
                              else "; no parameter range (day bootstrap off or not available)",
                              ". A model, not a measurement."))
  })
  output$fc_boot_tbl <- renderTable(forecast_boot_display(fc_res()), na = "n/a")
  output$fc_transit_tbl <- renderTable(forecast_transit_display(fc_res()), na = "n/a")
  output$fc_uncertainty <- renderUI({
    f <- fc_res()
    tags$ul(lapply(f$uncertainty, tags$li))
  })
  output$fc_days <- renderText({
    f <- fc_res()
    if (length(f$source_days) == 0) return("none: no earlier weekday")
    paste0(length(f$source_days), " weekday(s): ", paste(f$source_days, collapse = ", "))
  })
  output$fc_rates_tbl <- renderTable(forecast_rate_display(fc_res()), na = "n/a")
}

shinyApp(ui = ui, server = server)
