# 01_load_data.R
# Load the processed decision-level data produced by the Python pipeline.
# Outputs a cleaned tibble: `decisions`

library(here)
library(arrow)
library(tidyverse)
library(janitor)

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------

PROCESSED_DIR <- here("data", "processed")

parquet_file <- file.path(PROCESSED_DIR, "decisions.parquet")
csv_file     <- file.path(PROCESSED_DIR, "decisions.csv")

# ---------------------------------------------------------------------------
# Load (prefer Parquet for speed; fall back to CSV)
# ---------------------------------------------------------------------------

if (file.exists(parquet_file)) {
  decisions_raw <- arrow::read_parquet(parquet_file)
  message("Loaded from Parquet: ", nrow(decisions_raw), " rows")
} else if (file.exists(csv_file)) {
  decisions_raw <- readr::read_csv(csv_file, show_col_types = FALSE)
  message("Loaded from CSV: ", nrow(decisions_raw), " rows")
} else {
  stop(
    "No processed data found in ", PROCESSED_DIR, ".\n",
    "Run the Python pipeline first:\n",
    "  python -m python.pipeline --competition <comp> --season <season> ",
    "--match-file <file> --decision-file <file>"
  )
}

# ---------------------------------------------------------------------------
# Clean column names and types
# ---------------------------------------------------------------------------

decisions <- decisions_raw |>
  janitor::clean_names() |>
  mutate(
    match_date        = as.Date(match_date),
    decision_for_team = as.logical(decision_for_team),
    var_involved      = as.logical(var_involved),
    is_home           = as.logical(is_home),
    minute            = as.integer(minute),
    score_diff_before = as.integer(score_diff_before),
    decision_type     = factor(decision_type),
    score_state       = factor(score_state, levels = c("losing", "drawing", "winning")),
    match_phase       = factor(match_phase, levels = c("first_half", "second_half", "extra_time")),
    home_away         = factor(home_away, levels = c("away", "home")),
    competition       = factor(competition),
    season            = factor(season),
    team              = factor(team),
    referee           = factor(referee)
  )

message("Dimensions: ", paste(dim(decisions), collapse = " x "))
message("Competitions: ", paste(levels(decisions$competition), collapse = ", "))
message("Seasons: ", paste(levels(decisions$season), collapse = ", "))
message("Decision types: ", paste(levels(decisions$decision_type), collapse = ", "))
