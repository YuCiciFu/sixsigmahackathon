# app/sim.R - demand model and van parameters shared by the Now forecast (team 2027win)
#
# Plain base-R functions (base, stats only). No Shiny, no plotting.
# The rules are written out in docs/methods.md sections 4.1 and 4.2 (item 5, D-2).
# Everything marked "demo assumption" is adjustable and is NOT a measured property of a real system.
#
# History: this file used to hold the seeded three-policy simulation (H-10, H-15). That comparison
# was removed in the H-19 scope reduction; only the pieces the forecast (app/forecast.R) uses remain.
#
# Contents
#   1. parameters and the world         sim_params, sim_world
#   2. demand (no look-ahead)           estimate_demand, demand_lambda
#
# Time: minutes after 07:00 (0 ... 180). The state of minute [m, m+1) is read at time m (methods 4.1).

SIM_N_MIN <- 180                 # 07:00-10:00
SIM_BIN_MIN <- 15                # demand rates are constant inside a 15-minute bin
SIM_TZ <- "America/New_York"

# ---------------------------------------------------------------- 1. parameters and the world

#' Van parameters for the forecast's "vans on the way" estimate (all demo assumptions, adjustable).
#' detour       road distance = straight line x detour
#' speed_kmh    van speed; travel minutes = km / speed_kmh x 60
sim_params <- function(detour = 1.3, speed_kmh = 20) {
  ok <- function(x, lower, name) {
    if (!is.numeric(x) || length(x) != 1 || is.na(x) || x < lower) {
      stop(name, " must be a single number of at least ", lower, ".", call. = FALSE)
    }
  }
  ok(detour, 1, "detour"); ok(speed_kmh, 1e-6, "speed_kmh")
  list(detour = detour, speed_kmh = speed_kmh)
}

#' The starting world: stations, their capacity and position, the inventory and flags at the start.
#' Input : state0 = station_id, bikes_available, docks_available, is_renting, is_returning (the
#'         forecast passes the state at t0); stations = station_id, latitude, longitude, capacity.
#' Station flags stay at their starting values for the whole forecast (demo assumption).
sim_world <- function(state0, stations) {
  state0 <- state0[order(state0$station_id, method = "radix"), ]
  pos <- match(state0$station_id, stations$station_id)
  if (anyNA(pos)) stop("state0 has a station_id that is not in stations.", call. = FALSE)
  list(ids = state0$station_id, lat = stations$latitude[pos], lon = stations$longitude[pos],
       cap = stations$capacity[pos], bikes = state0$bikes_available, docks = state0$docks_available,
       renting = as.logical(state0$is_renting), returning = as.logical(state0$is_returning))
}

# ---------------------------------------------------------------- 2. demand (no look-ahead)

#' Poisson demand rates per station x type x 15-minute bin (methods 4.2 item 5, D-2).
#' Method: rate = attempts (successful + failed) / known station-minutes in that bin, summed over
#'         `source_days`. The forecast passes only weekdays STRICTLY BEFORE the chosen date (no
#'         look-ahead).
#'         A rate of 0 is valid (known minutes, no attempts).
#' Input : attempts (timestamp, station_id, attempt_type, success), grids = list of minute grids
#'         named by date (qc.R build_grid), source_days, station_ids.
#' Output: list(rates = array [station, "rent"/"return", bin 1..12] in attempts per station-minute,
#'         has_rate = TRUE where the station has any known minute on the source days,
#'         source_days, n_attempts, n_fallback_cells).
#' Demo assumption: a bin with no known station-minute uses the station's pooled rate over all bins
#'         (counted in n_fallback_cells). A station with no known minute at all has no rate (NA) and
#'         is left out of the forecast (n/a with a reason).
estimate_demand <- function(attempts, grids, source_days, station_ids, tz = SIM_TZ) {
  ns <- length(station_ids)
  n_bins <- SIM_N_MIN %/% SIM_BIN_MIN
  known_min <- matrix(0, ns, n_bins)
  att <- array(0, c(ns, 2, n_bins))
  secs <- as.numeric(attempts$timestamp)
  for (d in source_days) {
    start <- as.numeric(as.POSIXct(paste(d, "07:00"), tz = tz, format = "%Y-%m-%d %H:%M"))
    g <- grids[[d]]
    g <- g[g$known & g$station_id %in% station_ids, ]
    bin <- floor((as.numeric(g$minute) - start) / 60 / SIM_BIN_MIN) + 1
    tab <- table(factor(match(g$station_id, station_ids), seq_len(ns)), factor(bin, seq_len(n_bins)))
    known_min <- known_min + matrix(as.vector(tab), ns, n_bins)

    in_day <- !is.na(secs) & secs >= start & secs < start + 60 * SIM_N_MIN &
      attempts$station_id %in% station_ids
    a <- attempts[in_day, ]
    abin <- floor((secs[in_day] - start) / 60 / SIM_BIN_MIN) + 1
    atype <- ifelse(a$attempt_type == "rent", 1, 2)
    tab <- table(factor(match(a$station_id, station_ids), seq_len(ns)), factor(atype, 1:2),
                 factor(abin, seq_len(n_bins)))
    att <- att + array(as.vector(tab), c(ns, 2, n_bins))
  }
  rates <- array(NA_real_, c(ns, 2, n_bins),
                 dimnames = list(station_ids, c("rent", "return"), seq_len(n_bins)))
  pooled_known <- rowSums(known_min)
  n_fallback <- 0
  for (ty in 1:2) {
    pooled <- ifelse(pooled_known > 0, rowSums(att[, ty, , drop = FALSE]) / pooled_known, NA_real_)
    for (b in seq_len(n_bins)) {
      own <- ifelse(known_min[, b] > 0, att[, ty, b] / known_min[, b], NA_real_)
      fallback <- is.na(own) & !is.na(pooled)
      n_fallback <- n_fallback + sum(fallback)
      rates[, ty, b] <- ifelse(is.na(own), pooled, own)
    }
  }
  list(rates = rates, has_rate = pooled_known > 0, source_days = source_days,
       n_attempts = sum(att), n_fallback_cells = n_fallback)
}

# Expand rates [station, type, bin] to a per-minute array [minute, station, type].
demand_lambda <- function(rates) {
  lambda <- array(0, c(SIM_N_MIN, dim(rates)[1], 2))
  for (m in seq_len(SIM_N_MIN)) lambda[m, , ] <- rates[, , (m - 1) %/% SIM_BIN_MIN + 1]
  lambda
}
