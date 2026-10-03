################################################################################
# 05-build-team-match-panel.R
# Purpose: (i) Link football-data.co.uk matches (odds, fouls, cards) to ESPN
#          matches (penalties, possession, referee, Champions League);
#          (ii) compute pre-match Elo ratings from all results;
#          (iii) build the team-match panel used in the analysis (each match
#          enters twice, once from each team's perspective).
# Input:   data/datasets/espn-matches.csv, data/datasets/football-data-matches.csv
# Output:  data/datasets/matches.csv, data/datasets/team-match-panel.csv,
#          data/datasets/team-crosswalk.csv
# Date:    2026-10-02
################################################################################

ESPNMatches <- read_csv(file.path(datasets, "espn-matches.csv"),
                        col_types = cols(event_id = "c", home_id = "c", away_id = "c"),
                        show_col_types = FALSE)
FDMatches <- read_csv(file.path(datasets, "football-data-matches.csv"),
                      show_col_types = FALSE)

# 1. Team-name crosswalk (football-data name -> ESPN team id) ---------------------
# Candidate links: same league, date within one day, identical score. The
# modal ESPN id for each football-data name is kept.
Domestic <- ESPNMatches |> filter(league != "uefa.champions")

Candidates <- FDMatches |>
  select(league, date, fd_home, fd_away, home_goals_fd, away_goals_fd) |>
  inner_join(Domestic |>
               transmute(league, date_lo = date - 1, date_hi = date + 1,
                         home_id, away_id, home_score, away_score),
             by = join_by(league, home_goals_fd == home_score,
                          away_goals_fd == away_score,
                          between(date, date_lo, date_hi)))

TeamCrosswalk <- bind_rows(
  Candidates |> select(league, fd_name = fd_home, team_id = home_id),
  Candidates |> select(league, fd_name = fd_away, team_id = away_id)
) |>
  count(league, fd_name, team_id) |>
  group_by(league, fd_name) |>
  mutate(share = n / sum(n)) |>
  slice_max(n, n = 1, with_ties = FALSE) |>
  ungroup()

message("Crosswalk: ", nrow(TeamCrosswalk), " football-data names; minimum modal share = ",
        round(min(TeamCrosswalk$share), 2))

FDLinked <- FDMatches |>
  left_join(TeamCrosswalk |> select(league, fd_home = fd_name, home_id = team_id),
            by = c("league", "fd_home")) |>
  left_join(TeamCrosswalk |> select(league, fd_away = fd_name, away_id = team_id),
            by = c("league", "fd_away")) |>
  # A home-away pairing occurs once per league-season
  distinct(league, season_start, home_id, away_id, .keep_all = TRUE)

Matches <- ESPNMatches |>
  left_join(FDLinked |> select(-date),
            by = c("league", "season_start", "home_id", "away_id"))

message("Domestic ESPN matches linked to football-data: ",
        round(mean(!is.na(Matches$fd_home[Matches$league != "uefa.champions"])), 3))

# ESPN labels the 2002/03 semi-finals as quarter-finals: when a Champions League
# season shows more than eight quarter-final legs, the last four are semi-finals.
Matches <- Matches |>
  mutate(qf = league == "uefa.champions" & str_detect(coalesce(round_slug, ""), "quarter")) |>
  group_by(league, season_start) |>
  mutate(n_qf = sum(qf),
         recency = rank(if_else(qf, -as.numeric(date), Inf), ties.method = "first"),
         round_slug = if_else(qf & n_qf > 8 & recency <= 4,
                              str_replace(round_slug, "quarter-?finals", "semi-finals"),
                              round_slug)) |>
  ungroup() |>
  select(-qf, -n_qf, -recency)

# ESPN never flags neutral venues. Champions League finals and the August 2020
# "final eight" in Lisbon (quarter-finals onward) were played at neutral grounds.
Matches <- Matches |>
  mutate(neutral_site = neutral_site |
           (league == "uefa.champions" & str_detect(coalesce(round_slug, ""), "(^|-)final$")) |
           (league == "uefa.champions" & season_start == 2019 & month(date) == 8 &
              str_detect(coalesce(round_slug, ""), "quarter|semi|final")))

# 2. Pre-match Elo ratings -------------------------------------------------------
# World Football Elo-style updating with a goal-difference multiplier. Teams
# enter at 1500; clubs promoted into a domestic league enter at the mean rating
# of the clubs relegated from that league at the end of the previous season.
elo_k <- 20; elo_hfa <- 65

Matches <- Matches |> arrange(date, as.numeric(event_id))
rating <- new.env()
league_members <- list()
n <- nrow(Matches)
elo_home_pre <- elo_away_pre <- numeric(n)
v_league <- Matches$league; v_season <- Matches$season_start
v_home <- Matches$home_id; v_away <- Matches$away_id
v_hs <- Matches$home_score; v_as <- Matches$away_score
v_neutral <- Matches$neutral_site

entry_rating <- function(lg, season) {
  if (lg == "uefa.champions") return(1500)
  prev <- league_members[[paste(lg, season - 1)]]
  curr <- league_members[[paste(lg, season)]]
  if (is.null(prev)) return(1500)
  relegated <- setdiff(prev, curr)
  vals <- unlist(mget(relegated, envir = rating, ifnotfound = NA))
  if (all(is.na(vals))) 1450 else mean(vals, na.rm = TRUE)
}

# Register each league-season's members first so relegated clubs are known
for (key in unique(paste(v_league, v_season))) {
  idx <- paste(v_league, v_season) == key
  league_members[[key]] <- unique(c(v_home[idx], v_away[idx]))
}

for (i in seq_len(n)) {
  for (tm in c(v_home[i], v_away[i])) {
    if (!exists(tm, envir = rating, inherits = FALSE)) {
      assign(tm, entry_rating(v_league[i], v_season[i]), envir = rating)
    }
  }
  rh <- get(v_home[i], envir = rating); ra <- get(v_away[i], envir = rating)
  elo_home_pre[i] <- rh; elo_away_pre[i] <- ra
  if (is.na(v_hs[i]) || is.na(v_as[i])) next
  hfa <- if (isTRUE(v_neutral[i])) 0 else elo_hfa
  expected <- 1 / (1 + 10^(-(rh + hfa - ra) / 400))
  result <- if (v_hs[i] > v_as[i]) 1 else if (v_hs[i] == v_as[i]) 0.5 else 0
  gd <- abs(v_hs[i] - v_as[i])
  mult <- if (gd <= 1) 1 else if (gd == 2) 1.5 else (11 + gd) / 8
  delta <- elo_k * mult * (result - expected)
  assign(v_home[i], rh + delta, envir = rating)
  assign(v_away[i], ra - delta, envir = rating)
}

Matches <- Matches |>
  mutate(home_elo = elo_home_pre, away_elo = elo_away_pre,
         elo_exp_home = 1 / (1 + 10^(-(home_elo + if_else(neutral_site, 0, elo_hfa) -
                                         away_elo) / 400)))

# 3. Harmonized match-level decisions ------------------------------------------
# Fouls and cards: ESPN box score (covers all six competitions); football-data
# fills domestic matches where ESPN is missing. Penalties: ESPN key events.
Matches <- Matches |>
  mutate(
    competition = if_else(league == "uefa.champions", "Champions League", "Domestic league"),
    league_name = league_labels[league],
    # ESPN round slugs are inconsistent across seasons ("play-off-round",
    # "playoff-round", "playoffs" for the pre-group play-off; "second-phase" for
    # the 2001/02-2002/03 second group stage). The post-2024 "knockout-round-
    # playoffs" follow the league phase and are knockout matches.
    ucl_stage = case_when(
      league != "uefa.champions" ~ NA_character_,
      str_detect(round_slug, "qualifying|preliminary|play-?off-round") ~ "Qualifying",
      str_detect(round_slug, "playoffs$") & !str_detect(round_slug, "knockout") ~ "Qualifying",
      str_detect(round_slug, "group|league-phase|second-phase") ~ "Group/league phase",
      TRUE ~ "Knockout"
    ),
    home_fouls  = coalesce(home_foulsCommitted, home_fouls_fd),
    away_fouls  = coalesce(away_foulsCommitted, away_fouls_fd),
    home_yellow = coalesce(home_yellowCards, home_yellow_fd),
    away_yellow = coalesce(away_yellowCards, away_yellow_fd),
    home_red    = coalesce(home_redCards, home_red_fd),
    away_red    = coalesce(away_redCards, away_red_fd),
    home_shots  = coalesce(home_totalShots, home_shots_fd),
    away_shots  = coalesce(away_totalShots, away_shots_fd),
    home_possession = home_possessionPct,
    away_possession = away_possessionPct,
    home_passes = home_totalPasses,
    away_passes = away_totalPasses,
    home_pens = home_pens_ke, away_pens = away_pens_ke,
    referee = coalesce(referee, fd_referee)
  )

# October 2026 audit: reconcile goals including extra time, then reconstruct
# the score before second-half stoppage from regulation goals only.
# The end-clock marker documents event-log presence, not penalty completeness.
GoalEvents <- read_csv(file.path(datasets, "espn-key-events.csv"),
                       col_types = cols(event_id = "c", team_id = "c", clock = "c",
                                        type = "c"),
                       show_col_types = FALSE) |>
  filter(!shootout, str_detect(type, "^(Goal|Own Goal)") | type == "Penalty - Scored",
         is.na(period) | period <= 4) |>
  group_by(event_id, team_id) |>
  summarise(goals_ev = n(),
            goals_regulation = sum(is.na(period) | period <= 2),
            goals_2h = sum(period == 2, na.rm = TRUE),
            goals_stoppage = sum(period == 2 & str_detect(clock, "^90'\\+"), na.rm = TRUE),
            .groups = "drop")

Matches <- Matches |>
  left_join(GoalEvents |> rename_with(\(v) paste0("home_", v), -event_id) |>
              rename(home_id = home_team_id), by = c("event_id", "home_id")) |>
  left_join(GoalEvents |> rename_with(\(v) paste0("away_", v), -event_id) |>
              rename(away_id = away_team_id), by = c("event_id", "away_id")) |>
  mutate(across(matches("^(home|away)_goals_(ev|regulation|2h|stoppage)$"),
                \(v) replace_na(v, 0)),
         goals_ok = home_goals_ev == home_score & away_goals_ev == away_score,
         margin_90_home = if_else(goals_ok,
                                  (home_goals_regulation - home_goals_stoppage) -
                                    (away_goals_regulation - away_goals_stoppage),
                                  NA_real_),
         goals_2h_regulation = home_goals_2h + away_goals_2h - home_goals_stoppage -
           away_goals_stoppage)

# October 2026 audit: never select seasons by the penalty outcome itself.
# Eligibility requires a recorded regulation-end marker and reconciled goals.
# This detects absent/truncated logs, not every mislabeled or missing penalty.
Matches <- Matches |>
  group_by(league, season_start,
           qualifying = coalesce(ucl_stage == "Qualifying", FALSE)) |>
  mutate(pens_rate_ls = mean(home_pens + away_pens)) |>
  ungroup() |>
  mutate(pens_ok = event_log_has_end & goals_ok) |>
  select(-qualifying)

write_csv(Matches, file.path(datasets, "matches.csv"))
write_csv(TeamCrosswalk, file.path(datasets, "team-crosswalk.csv"))

# 4. Team-match panel ----------------------------------------------------------
side_vars <- c("id", "name", "score", "fouls", "yellow", "red", "shots",
               "possession", "passes", "pens", "elo")

make_side <- function(df, own, opp, is_home) {
  own_cols <- setNames(paste0(own, "_", side_vars), paste0("own_", side_vars))
  opp_cols <- setNames(paste0(opp, "_", side_vars), paste0("opp_", side_vars))
  df |>
    select(event_id, league, league_name, competition, ucl_stage, season_start,
           date, neutral_site, referee, attendance, stoppage_1h, stoppage_2h,
           extra_time, event_log_has_end, goals_ok, possession_valid,
           pens_ok, margin_90_home, goals_2h_regulation,
           all_of(c(own_cols, opp_cols)),
           prob_home, prob_away, elo_exp_home) |>
    mutate(home = as.integer(is_home & !neutral_site),
           away = as.integer(!is_home & !neutral_site),
           prob_win = if (is_home) prob_home else prob_away,
           prob_lose = if (is_home) prob_away else prob_home,
           elo_exp = if (is_home) elo_exp_home else 1 - elo_exp_home,
           own_margin_90 = if (is_home) margin_90_home else -margin_90_home) |>
    select(-prob_home, -prob_away, -elo_exp_home, -margin_90_home)
}

TeamMatch <- bind_rows(
  make_side(Matches, "home", "away", TRUE),
  make_side(Matches, "away", "home", FALSE)
) |>
  rename(team_id = own_id, team = own_name, opponent = opp_name) |>
  mutate(
    goal_diff      = own_score - opp_score,
    net_yellow     = opp_yellow - own_yellow,    # positive = favorable
    net_red        = opp_red - own_red,
    net_fouls      = opp_fouls - own_fouls,
    net_pens       = own_pens - opp_pens,
    yellow_per_foul = if_else(own_fouls > 0, own_yellow / own_fouls, NA_real_),
    barca          = as.integer(team_id == "83"),
    real_madrid    = as.integer(team_id == "86"),
    negreira_era   = as.integer(season_start <= negreira_last_season),
    var_era        = as.integer(season_start >= var_first_season[league] &
                       !(league == "uefa.champions" & season_start == 2018 &
                           ucl_stage != "Knockout")),
    league_season  = paste(league, season_start),
    team_season    = paste(team_id, season_start)
  ) |>
  left_join(elite_clubs |> select(team_id, elite_club = club), by = "team_id") |>
  mutate(elite = as.integer(!is.na(elite_club)))

# Attach each team's domestic league (modal league over the sample) so that
# Champions League rows can be compared within country
DomesticLeague <- TeamMatch |>
  filter(league != "uefa.champions") |>
  count(team_id, league) |>
  slice_max(n, n = 1, by = team_id, with_ties = FALSE) |>
  select(team_id, home_league = league)

TeamMatch <- TeamMatch |> left_join(DomesticLeague, by = "team_id")

message("Team-match panel: ", nrow(TeamMatch), " rows; ",
        n_distinct(TeamMatch$team_id), " teams; seasons ",
        min(TeamMatch$season_start), "-", max(TeamMatch$season_start))

write_csv(TeamMatch, file.path(datasets, "team-match-panel.csv"))

# 5. Coverage by league-season (documented in notes/data-documentation.md) ------
Coverage <- Matches |>
  group_by(league, season_start) |>
  summarise(matches = n(),
            fouls = mean(!is.na(home_fouls)),
            cards = mean(!is.na(home_yellow)),
            possession = mean(!is.na(home_possession)),
            penalties_per_match = mean(home_pens + away_pens),
            penalties_ok = first(pens_ok),
            referee = mean(!is.na(referee)),
            stoppage_time = mean(!is.na(stoppage_2h)),
            odds = mean(!is.na(prob_home)),
            .groups = "drop") |>
  mutate(across(fouls:odds, \(v) round(v, 2)))
write_csv(Coverage, file.path(tables_wd, "data-coverage-by-league-season.csv"))
