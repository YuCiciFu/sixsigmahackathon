# Tests for app/sim.R: the demand model and van parameters shared by the Now forecast.
# The seeded policy simulation (H-10, H-15) and its tests were removed in the H-19 scope reduction.
# Checked here: parameter validation, the starting world, demand rates that never look ahead,
# the pooled-rate fallback, and the per-minute expansion of the 15-minute bin rates.
# helper-qc.R has already loaded app/qc.R.
source(testthat::test_path("..", "app", "sim.R"), local = TRUE)

# ---------------------------------------------------------------- small builders

mini_stations <- function(ids, cap, lat, lon) {
  data.frame(station_id = ids, latitude = lat, longitude = lon, capacity = cap,
             stringsAsFactors = FALSE)
}
# The same rate for every station, type and 15-minute bin.
flat_rate <- function(n_stations, rent, ret) {
  r <- array(0, c(n_stations, 2, 12))
  r[, 1, ] <- rent
  r[, 2, ] <- ret
  r
}


# ---------------------------------------------------------------- demand rates (no look-ahead)

day_start <- function(date) as.POSIXct(paste(date, "07:00"), tz = "America/New_York",
                                       format = "%Y-%m-%d %H:%M")
fake_grid <- function(date, ids, bikes, cap, known = TRUE) {
  do.call(rbind, lapply(seq_along(ids), function(i) {
    k <- rep_len(known[[min(i, length(known))]], 180)
    data.frame(station_id = ids[i], minute = day_start(date) + 60 * (0:179), known = k,
               bikes_available = ifelse(k, bikes[i], NA), docks_available = ifelse(k, cap[i] - bikes[i], NA),
               is_renting = ifelse(k, TRUE, NA), is_returning = ifelse(k, TRUE, NA),
               stringsAsFactors = FALSE)
  }))
}
fake_attempts <- function(date, clock, station, type, n, success = TRUE) {
  data.frame(timestamp = rep(day_start(date) + 60 * clock, n), station_id = station,
             attempt_type = type, success = success, stringsAsFactors = FALSE)
}

ids4 <- paste0("T", 1:4)
cap4 <- rep(10, 4)
days3 <- c("2026-10-05", "2026-10-06", "2026-10-07")      # Monday to Wednesday
grids3 <- setNames(lapply(days3, function(d) fake_grid(d, ids4, c(0, 10, 5, 3), cap4)), days3)
att3 <- rbind(
  fake_attempts(days3[1], 5, "T1", "rent", 3),                       # 3 rents in bin 1 on day 1
  fake_attempts(days3[2], 6, "T1", "rent", 2),                       # 2 successful + ...
  fake_attempts(days3[2], 7, "T1", "rent", 1, success = FALSE),      # ... 1 failed rent: all count
  fake_attempts(days3[1], 20, "T3", "return", 15),                   # bin 2: 15 returns on day 1
  fake_attempts(days3[3], 8, "T2", "rent", 100)                      # the CHOSEN day: must be ignored
)

test_that("demand rates = attempts / known station-minutes over earlier weekdays only", {
  d <- estimate_demand(att3, grids3, source_days = days3[1:2], station_ids = ids4)
  # T1 rent, bin 1: (3 + 3) attempts / (15 + 15) known minutes = 0.2
  expect_equal(d$rates["T1", "rent", 1], 6 / 30)
  # T3 return, bin 2: 15 attempts / 30 known minutes = 0.5
  expect_equal(d$rates["T3", "return", 2], 0.5)
  # a rate of 0 is valid
  expect_equal(d$rates["T4", "rent", 1], 0)
  # the chosen day (10-07) has 100 rents at T2 in bin 1: they must not be used
  expect_equal(d$rates["T2", "rent", 1], 0)
  expect_equal(d$source_days, days3[1:2])
  expect_true(all(d$has_rate))
})

test_that("a bin with no known minute falls back to the station's pooled rate; no known minute at all -> no rate", {
  g <- grids3
  for (k in 1:2) {   # T1 has no known minute in 07:00-07:14 on the two earlier days
    first15 <- g[[k]]$station_id == "T1" & g[[k]]$minute < day_start(days3[k]) + 15 * 60
    g[[k]]$known[first15] <- FALSE
  }
  d <- estimate_demand(att3, g, source_days = days3[1:2], station_ids = ids4)
  expect_false(anyNA(d$rates))
  # pooled T1 rent rate = 6 rent attempts / (2 days x 165 known minutes) = 6/330
  expect_equal(d$rates["T1", "rent", 1], 6 / 330)
  expect_equal(d$n_fallback_cells, 2)   # T1 rent and T1 return in bin 1
  none_known <- setNames(lapply(days3, function(dd) fake_grid(dd, ids4, c(0, 10, 5, 3), cap4,
                                                                known = c(TRUE, TRUE, TRUE, FALSE))), days3)
  d2 <- estimate_demand(att3, none_known, source_days = days3[1:2], station_ids = ids4)
  expect_equal(d2$has_rate, c(TRUE, TRUE, TRUE, FALSE))
})


# ---------------------------------------------------------------- parameters, world, per-minute rates

test_that("sim_params keeps detour and speed, and rejects impossible values", {
  p <- sim_params()
  expect_equal(p, list(detour = 1.3, speed_kmh = 20))
  expect_equal(sim_params(detour = 2, speed_kmh = 10), list(detour = 2, speed_kmh = 10))
  expect_error(sim_params(detour = 0.5), "detour must be")
  expect_error(sim_params(speed_kmh = 0), "speed_kmh must be")
  expect_error(sim_params(detour = NA), "detour must be")
})

test_that("sim_world sorts by station and takes position and capacity from the stations table", {
  st <- mini_stations(c("B", "A"), c(8, 10), c(42.45, 42.44), c(-76.49, -76.50))
  w <- sim_world(data.frame(station_id = c("B", "A"), bikes_available = c(3, 0), docks_available = c(5, 10),
                            is_renting = c(TRUE, FALSE), is_returning = TRUE, stringsAsFactors = FALSE), st)
  expect_equal(w$ids, c("A", "B"))
  expect_equal(w$cap, c(10, 8))
  expect_equal(w$bikes, c(0, 3))
  expect_equal(w$renting, c(FALSE, TRUE))
  expect_error(sim_world(data.frame(station_id = "Z", bikes_available = 1, docks_available = 1,
                                    is_renting = TRUE, is_returning = TRUE), st), "not in stations")
})

test_that("demand_lambda repeats each 15-minute bin rate for its 15 minutes", {
  r <- flat_rate(2, rent = 0.1, ret = 0.2)
  r[1, 1, 2] <- 0.7                     # station 1, rent, bin 2 = minutes 15-29
  l <- demand_lambda(r)
  expect_equal(dim(l), c(180, 2, 2))
  expect_equal(l[15, 1, 1], 0.1)        # minute 14 (row 15) is still bin 1
  expect_equal(l[16, 1, 1], 0.7)        # minute 15 starts bin 2
  expect_equal(l[30, 1, 1], 0.7)
  expect_equal(l[31, 1, 1], 0.1)
  expect_equal(l[100, 2, 2], 0.2)
})
