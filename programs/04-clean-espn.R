################################################################################
# 04-clean-espn.R
# Purpose: Parse the ESPN match summaries into (i) a match-level file with
#          teams, score, referee, attendance and stoppage time, (ii) team-match
#          box-score statistics (fouls, cards, possession, shots, penalties),
#          and (iii) an event-level file of penalties, cards and goals.
# Input:   data/raw/espn/json/<league>/<season>/<event_id>.json.gz
#          data/raw/espn/events-index-<league>.csv
# Output:  data/datasets/espn-matches.csv
#          data/datasets/espn-key-events.csv
# Date:    2026-10-02
################################################################################

espn_files <- list.files(file.path(raw, "espn", "json"), pattern = "\\.json\\.gz$",
                         recursive = TRUE, full.names = TRUE)
message("ESPN match files: ", length(espn_files))

`%||%` <- function(a, b) if (is.null(a)) b else a

stat_names <- c("foulsCommitted", "yellowCards", "redCards", "possessionPct",
                "totalShots", "shotsOnTarget", "wonCorners", "offsides",
                "penaltyKickGoals", "penaltyKickShots", "saves", "totalPasses",
                "accuratePasses")

parse_espn <- function(path) {
  d <- tryCatch(fromJSON(gzfile(path), simplifyVector = FALSE),
                error = function(e) stop(sprintf("Cannot parse %s: %s",
                  path, conditionMessage(e)), call. = FALSE))
  if (is.null(d$header)) {
    stop(sprintf("Missing match header in %s", path), call. = FALSE)
  }
  parts <- str_split(path, "/")[[1]]
  n <- length(parts)
  league <- parts[n - 2]
  season_start <- as.integer(parts[n - 1])
  event_id <- sub("\\.json\\.gz$", "", parts[n])

  comp <- d$header$competitions[[1]]
  teams <- comp$competitors
  side <- function(h) Filter(function(t) identical(t$homeAway, h), teams)[[1]]
  home <- side("home"); away <- side("away")

  # Referee: first official listed with position "Referee"
  offs <- d$gameInfo$officials %||% list()
  refs <- Filter(function(o) identical(o$position$name, "Referee"), offs)
  referee <- if (length(refs)) refs[[1]]$displayName %||% refs[[1]]$fullName else NA_character_

  # Box-score statistics by team id
  box <- d$boxscore$teams %||% list()
  get_stats <- function(team_id) {
    tb <- Filter(function(t) identical(t$team$id, team_id), box)
    out <- setNames(rep(NA_real_, length(stat_names)), stat_names)
    if (length(tb)) {
      for (s in tb[[1]]$statistics %||% list()) {
        if (s$name %in% stat_names) out[s$name] <- suppressWarnings(as.numeric(s$displayValue))
      }
    }
    out
  }
  hs <- get_stats(home$team$id); as_ <- get_stats(away$team$id)

  # Key events: penalties, cards, goals, and period-end clocks
  ke <- d$keyEvents %||% list()
  ev <- map(ke, function(k) list(
    type = k$type$text %||% NA_character_,
    clock = k$clock$displayValue %||% NA_character_,
    clock_sec = as.numeric(k$clock$value %||% NA_real_),
    period = as.integer(k$period$number %||% NA_integer_),
    shootout = isTRUE(k$shootout),
    team_id = k$team$id %||% NA_character_
  )) |> rbindlist()

  stoppage <- function(lbl) {
    if (!nrow(ev)) return(NA_real_)
    v <- ev[type == lbl, clock]
    if (!length(v)) return(NA_real_)
    add <- str_match(v[1], "\\+(\\d+)")[, 2]
    if (is.na(add)) 0 else as.numeric(add)
  }

  match_row <- data.table(
    league, season_start, event_id,
    date_utc = comp$date %||% NA_character_,
    neutral_site = isTRUE(comp$neutralSite),
    home_id = home$team$id, home_name = home$team$displayName,
    away_id = away$team$id, away_name = away$team$displayName,
    home_score = as.numeric(home$score %||% NA), away_score = as.numeric(away$score %||% NA),
    # Winner flags account for extra time and shoot-outs (e.g., two-legged ties, finals)
    home_winner = isTRUE(home$winner), away_winner = isTRUE(away$winner),
    home_shootout = as.numeric(home$shootoutScore %||% NA),
    away_shootout = as.numeric(away$shootoutScore %||% NA),
    match_status = comp$status$type$name %||% NA_character_,
    event_log_has_end = nrow(ev) > 0 &&
      any(ev$type == "End Regular Time", na.rm = TRUE),
    extra_time = comp$status$type$name %in%
      c("STATUS_FINAL_AET", "STATUS_FINAL_PEN") ||
      (nrow(ev) > 0 && any(ev$period %in% c(3L, 4L))),
    referee,
    attendance = as.numeric(d$gameInfo$attendance %||% NA),
    venue = d$gameInfo$venue$fullName %||% NA_character_,
    stoppage_1h = stoppage("Halftime"),
    stoppage_2h = stoppage("End Regular Time"),
    has_box = length(box) > 0 && !all(is.na(hs))
  )
  match_row[, paste0("home_", stat_names) := as.list(hs)]
  match_row[, paste0("away_", stat_names) := as.list(as_)]

  if (nrow(ev)) {
    ev <- ev[str_detect(type, "Penalty|Card|Goal")]
    ev[, `:=`(league = league, season_start = season_start, event_id = event_id)]
  }
  list(match = match_row, events = ev)
}

t0 <- Sys.time()
parsed <- map(espn_files, parse_espn, .progress = list(clear = FALSE, show_after = 10))
message("Parsed in ", round(difftime(Sys.time(), t0, units = "mins"), 1), " minutes")

ESPNMatches <- rbindlist(map(parsed, "match"), fill = TRUE)
ESPNEvents  <- rbindlist(map(parsed, "events"), fill = TRUE)
rm(parsed)

# Round (group stage, knockout, qualifying) from the scoreboard index
ESPNIndex <- list.files(file.path(raw, "espn"), pattern = "^events-index-.*\\.csv$",
                        full.names = TRUE) |>
  map(\(f) read_csv(f, col_types = cols(.default = "c"), show_col_types = FALSE)) |>
  list_rbind() |>
  distinct(event_id, .keep_all = TRUE) |>
  select(event_id, round_slug, note)

ESPNMatches <- ESPNMatches |>
  as_tibble() |>
  left_join(ESPNIndex, by = "event_id") |>
  mutate(date = as_date(substr(date_utc, 1, 10)))

# Penalties awarded from key events (excluding shoot-outs). This series covers
# all seasons, whereas the box-score penalty counts start in 2005/06.
PenaltyCounts <- ESPNEvents |>
  as_tibble() |>
  filter(str_detect(type, "^Penalty"), !shootout, is.na(period) | period <= 4) |>
  count(event_id, team_id, name = "pens_awarded")

ESPNMatches <- ESPNMatches |>
  left_join(PenaltyCounts |> rename(home_id = team_id, home_pens_ke = pens_awarded),
            by = c("event_id", "home_id")) |>
  left_join(PenaltyCounts |> rename(away_id = team_id, away_pens_ke = pens_awarded),
            by = c("event_id", "away_id")) |>
  mutate(across(c(home_pens_ke, away_pens_ke), \(v) replace_na(v, 0)))

# ESPN occasionally lists the same match twice under two event ids. Keep the
# record with box-score data, then the one whose round slug names the season.
ESPNMatches <- ESPNMatches |>
  mutate(slug_ok = str_detect(coalesce(round_slug, ""), as.character(season_start)) |
                   !str_detect(coalesce(round_slug, ""), "\\d{4}"),
         dup_key = if_else(league == "uefa.champions",
                           paste(league, season_start, home_id, away_id, date),
                           paste(league, season_start, home_id, away_id))) |>
  arrange(dup_key, desc(has_box), desc(slug_ok), as.numeric(event_id)) |>
  distinct(dup_key, .keep_all = TRUE) |>
  select(-dup_key, -slug_ok)


# October 2026 audit: an abandoned fixture is not a completed full match.
ESPNMatches <- ESPNMatches |>
  filter(match_status %in% c("STATUS_FULL_TIME", "STATUS_FINAL_AET",
                             "STATUS_FINAL_PEN", "STATUS_FINAL_AGT"))
# Stoppage time is not recorded in early seasons (every match shows "90'").
# Treat a league-season as missing when fewer than 5% of matches show added time.
ESPNMatches <- ESPNMatches |>
  group_by(league, season_start) |>
  mutate(stoppage_ok = mean(stoppage_2h > 0, na.rm = TRUE) > 0.05) |>
  ungroup() |>
  mutate(across(c(stoppage_1h, stoppage_2h), \(v) if_else(stoppage_ok, v, NA_real_))) |>
  select(-stoppage_ok)

# ESPN reports zeros, not missing values, for statistics it did not track
# (e.g., fouls and possession in early seasons). A statistic is missing when
# both teams show zero; cards are missing when the box score is absent. The
# box-score penalty counts are unreliable (zeros in seasons with penalties in
# the event log), so penalties are taken from the key events only.
both_zero_na <- function(df, stat) {
  h <- paste0("home_", stat); a <- paste0("away_", stat)
  miss <- coalesce(df[[h]], 0) == 0 & coalesce(df[[a]], 0) == 0
  df[[h]][miss] <- NA; df[[a]][miss] <- NA
  df
}
for (s in c("foulsCommitted", "possessionPct", "totalShots", "shotsOnTarget",
            "wonCorners", "offsides", "saves", "totalPasses", "accuratePasses")) {
  ESPNMatches <- both_zero_na(ESPNMatches, s)
}

# October 2026 audit: one-sided zeros and 100/0 splits are source errors,
# not extreme playing styles. Do not manufacture possession by rescaling.
ESPNMatches <- ESPNMatches |>
  mutate(possession_valid = !is.na(home_possessionPct) &
           !is.na(away_possessionPct) &
           home_possessionPct > 0 & home_possessionPct < 100 &
           away_possessionPct > 0 & away_possessionPct < 100 &
           abs(home_possessionPct + away_possessionPct - 100) <= 1,
         possession_source_invalid =
           (!is.na(home_possessionPct) | !is.na(away_possessionPct)) &
           !possession_valid,
         home_possessionPct = if_else(possession_valid,
                                       home_possessionPct, NA_real_),
         away_possessionPct = if_else(possession_valid,
                                       away_possessionPct, NA_real_))
ESPNMatches <- ESPNMatches |>
  mutate(across(matches("_(yellowCards|redCards)$"), \(v) if_else(has_box, v, NA_real_))) |>
  select(-matches("penaltyKick"))

message("ESPN matches after de-duplication: ", nrow(ESPNMatches))
print(ESPNMatches |> count(league, has_box) |> pivot_wider(names_from = has_box, values_from = n))

write_csv(ESPNMatches, file.path(datasets, "espn-matches.csv"))
write_csv(ESPNEvents, file.path(datasets, "espn-key-events.csv"))
