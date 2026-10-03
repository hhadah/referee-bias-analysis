################################################################################
# 01-download-football-data.R
# Purpose: Download match-level results, match statistics (fouls, cards,
#          shots), referee (England, Italy from 2005/06) and pre-match
#          betting odds for the top-5 European leagues from
#          football-data.co.uk, seasons 2000/01 to present.
# Output:  data/raw/football-data/<div>-<season>.csv
# Date:    2026-10-02
################################################################################

fd_divisions <- c(E0 = "England", SP1 = "Spain", I1 = "Italy",
                  D1 = "Germany", F1 = "France")
fd_first_season <- 2000
fd_last_season  <- 2026   # 2026/27 is in progress at the time of writing

season_code <- function(y) {
  sprintf("%02d%02d", y %% 100, (y + 1) %% 100)
}

fd_grid <- expand_grid(div = names(fd_divisions),
                       season_start = fd_first_season:fd_last_season) |>
  mutate(code = season_code(season_start),
         url  = glue::glue("https://www.football-data.co.uk/mmz4281/{code}/{div}.csv"),
         dest = file.path(raw, "football-data", glue::glue("{div}-{code}.csv")))

# Download each file once; the current season is always refreshed
for (i in seq_len(nrow(fd_grid))) {
  g <- fd_grid[i, ]
  if (file.exists(g$dest) && g$season_start < fd_last_season) next
  resp <- request(g$url) |>
    req_user_agent("Mozilla/5.0 (research; referee-bias-analysis)") |>
    req_retry(max_tries = 4) |>
    req_error(is_error = \(r) FALSE) |>
    req_perform()
  if (resp_status(resp) == 200) {
    writeBin(resp_body_raw(resp), g$dest)
  } else {
    message("Not available: ", g$url, " (HTTP ", resp_status(resp), ")")
  }
  Sys.sleep(0.5)
}

message("football-data.co.uk files on disk: ",
        length(list.files(file.path(raw, "football-data"), pattern = "\\.csv$")))
