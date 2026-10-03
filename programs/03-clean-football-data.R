################################################################################
# 03-clean-football-data.R
# Purpose: Stack the football-data.co.uk league files, harmonize variable
#          names, and convert pre-match betting odds into implied outcome
#          probabilities (normalized for the bookmaker overround).
# Input:   data/raw/football-data/<div>-<season>.csv
# Output:  data/datasets/football-data-matches.csv
# Date:    2026-10-02
################################################################################

fd_league <- c(E0 = "eng.1", SP1 = "esp.1", I1 = "ita.1", D1 = "ger.1",
               F1 = "fra.1")

read_fd <- function(f) {
  x <- suppressWarnings(suppressMessages(
    read_csv(f, col_types = cols(.default = "c"), show_col_types = FALSE,
             locale = locale(encoding = "latin1"), name_repair = "minimal")
  ))
  # Some files carry empty trailing columns
  x <- x[, names(x) != "" & !duplicated(names(x))]
  x$file <- basename(f)
  x
}

fd_files <- list.files(file.path(raw, "football-data"), pattern = "\\.csv$",
                       full.names = TRUE)
FDRaw <- map(fd_files, read_fd) |> list_rbind() |>
  filter(!is.na(HomeTeam), HomeTeam != "")

num <- function(v) suppressWarnings(as.numeric(v))
col_or_na <- function(df, v) if (v %in% names(df)) df[[v]] else NA_character_

# Pre-match odds: market average when reported (2005/06+), else Bet365,
# else William Hill, else Interwetten.
pick_odds <- function(df, side) {
  coalesce(num(col_or_na(df, paste0("Avg", side))),
           num(col_or_na(df, paste0("BbAv", side))),
           num(col_or_na(df, paste0("B365", side))),
           num(col_or_na(df, paste0("WH", side))),
           num(col_or_na(df, paste0("IW", side))))
}

FDMatches <- FDRaw |>
  mutate(
    div          = str_extract(file, "^[A-Z0-9]+"),
    league       = fd_league[div],
    season_code  = str_extract(file, "[0-9]{4}"),
    season_start = 2000L + as.integer(substr(season_code, 1, 2)),
    date         = parse_date_time(Date, orders = c("dmy", "dmY")) |> as_date(),
    odds_h = pick_odds(FDRaw, "H"),
    odds_d = pick_odds(FDRaw, "D"),
    odds_a = pick_odds(FDRaw, "A"),
    overround = 1 / odds_h + 1 / odds_d + 1 / odds_a,
    prob_home = (1 / odds_h) / overround,
    prob_draw = (1 / odds_d) / overround,
    prob_away = (1 / odds_a) / overround
  ) |>
  transmute(
    league, season_start, date,
    fd_home = HomeTeam, fd_away = AwayTeam,
    fd_referee = col_or_na(FDRaw, "Referee"),
    home_goals_fd = num(FTHG), away_goals_fd = num(FTAG),
    home_ht_goals_fd = num(HTHG), away_ht_goals_fd = num(HTAG),
    home_shots_fd = num(col_or_na(FDRaw, "HS")), away_shots_fd = num(col_or_na(FDRaw, "AS")),
    home_sot_fd = num(col_or_na(FDRaw, "HST")), away_sot_fd = num(col_or_na(FDRaw, "AST")),
    home_fouls_fd = num(col_or_na(FDRaw, "HF")), away_fouls_fd = num(col_or_na(FDRaw, "AF")),
    home_corners_fd = num(col_or_na(FDRaw, "HC")), away_corners_fd = num(col_or_na(FDRaw, "AC")),
    home_yellow_fd = num(col_or_na(FDRaw, "HY")), away_yellow_fd = num(col_or_na(FDRaw, "AY")),
    home_red_fd = num(col_or_na(FDRaw, "HR")), away_red_fd = num(col_or_na(FDRaw, "AR")),
    prob_home, prob_draw, prob_away
  )

stopifnot(!any(is.na(FDMatches$date)))
message("football-data matches: ", nrow(FDMatches),
        " | share with odds: ", round(mean(!is.na(FDMatches$prob_home)), 3))

write_csv(FDMatches, file.path(datasets, "football-data-matches.csv"))
