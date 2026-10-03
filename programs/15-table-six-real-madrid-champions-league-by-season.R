################################################################################
# 15-table-six-real-madrid-champions-league-by-season.R
# Purpose: Table 6 -- Real Madrid in the Champions League, season by season:
#          furthest round reached, cards, fouls, penalties and red cards for
#          and against, with per-match benchmarks for the other elite clubs.
# Input:   data/datasets/team-match-panel.csv, data/datasets/matches.csv
# Output:  output/tables/table-six-real-madrid-champions-league-by-season.tex/.csv
# Date:    2026-10-02
################################################################################

UCL <- load_panel() |> filter(domestic == 0)

UCLMatches <- read_csv(file.path(datasets, "matches.csv"),
                       col_types = cols(event_id = "c", home_id = "c", away_id = "c"),
                       guess_max = 100000, show_col_types = FALSE) |>
  filter(league == "uefa.champions")

# Round reached, ordered; "Winner" when Real Madrid won the final (the ESPN
# winner flag accounts for extra time and shoot-outs)
round_of <- function(slug) {
  case_when(
    str_detect(slug, "(^|-)final$") ~ "Final",
    str_detect(slug, "semi") ~ "Semi-finals",
    str_detect(slug, "quarter") ~ "Quarter-finals",
    str_detect(slug, "round-of-16") ~ "Round of 16",
    str_detect(slug, "knockout-round-playoffs") ~ "Knockout play-offs",
    str_detect(slug, "second-phase") ~ "Second group stage",
    TRUE ~ "Group/league phase"
  )
}
round_levels <- c("Group/league phase", "Second group stage", "Knockout play-offs",
                  "Round of 16", "Quarter-finals", "Semi-finals", "Final", "Winner")

finals_won <- UCLMatches |>
  filter(str_detect(round_slug, "(^|-)final$"),
         (home_id == "86" & home_winner) | (away_id == "86" & away_winner)) |>
  pull(season_start)

Furthest <- UCL |>
  filter(real_madrid == 1) |>
  left_join(UCLMatches |> select(event_id, round_slug), by = "event_id") |>
  mutate(round = factor(round_of(round_slug), levels = round_levels, ordered = TRUE)) |>
  group_by(season_start) |>
  summarise(furthest = as.character(max(round)), .groups = "drop") |>
  mutate(furthest = if_else(season_start %in% finals_won, "Winner", furthest))

na_dash <- function(v, digits = 2) if_else(is.na(v), "--", formatC(v, format = "f", digits = digits))
int_dash <- function(v) if_else(is.na(v), "--", formatC(v, format = "d"))
sum_or_na <- function(v) if (all(is.na(v))) NA_integer_ else as.integer(sum(v, na.rm = TRUE))

BySeason <- UCL |>
  filter(real_madrid == 1) |>
  group_by(season_start) |>
  summarise(matches = n(), knockout = sum(ucl_stage == "Knockout"),
            own_yellow = mean(own_yellow), opp_yellow = mean(opp_yellow),
            own_fouls = mean(own_fouls), opp_fouls = mean(opp_fouls),
            own_pens = sum_or_na(own_pens), opp_pens = sum_or_na(opp_pens),
            own_red = sum_or_na(own_red), opp_red = sum_or_na(opp_red),
            .groups = "drop") |>
  left_join(Furthest, by = "season_start")

write_csv(BySeason, file.path(tables_wd, "table-six-real-madrid-champions-league-by-season.csv"))

# Per-match averages over all seasons: Real Madrid vs. the other elite clubs
per_match <- function(df, label) {
  df |>
    summarise(across(c(own_yellow, opp_yellow, own_fouls, opp_fouls, own_pens, opp_pens,
                       own_red, opp_red), \(v) mean(v, na.rm = TRUE)),
              matches = n()) |>
    transmute(Season = label, Matches = formatC(matches, format = "d", big.mark = ","),
              `Furthest round` = "",
              across(c(own_yellow, opp_yellow, own_fouls, opp_fouls), \(v) na_dash(v)),
              across(c(own_pens, opp_pens, own_red, opp_red), \(v) na_dash(v)))
}

season_rows <- BySeason |>
  transmute(Season = season_label(season_start),
            Matches = paste0(matches, " (", knockout, ")"),
            `Furthest round` = furthest,
            own_yellow = na_dash(own_yellow), opp_yellow = na_dash(opp_yellow),
            own_fouls = na_dash(own_fouls, 1), opp_fouls = na_dash(opp_fouls, 1),
            own_pens = int_dash(own_pens), opp_pens = int_dash(opp_pens),
            own_red = int_dash(own_red), opp_red = int_dash(opp_red))

summary_rows <- bind_rows(
  per_match(UCL |> filter(real_madrid == 1), "Real Madrid"),
  per_match(UCL |> filter(barca == 1), "Barcelona"),
  per_match(UCL |> filter(other_elite == 1), "Other elite clubs"),
  per_match(UCL |> filter(elite == 0), "All other clubs")
)

TableSix <- bind_rows(season_rows, summary_rows)
n_season_rows <- nrow(season_rows)

tab6 <- kbl(TableSix, format = "latex", booktabs = TRUE, escape = FALSE, longtable = FALSE,
            col.names = c("Season", "Matches (KO)", "Furthest round",
                          "Received", "To opp.", "Committed", "Suffered",
                          "Awarded", "Conceded", "Received", "To opp."),
            align = c("l", "c", "l", rep("c", 8)),
            caption = "Real Madrid in the Champions League, Season by Season \\label{tab:rmucl}") |>
  add_header_above(c(" " = 3, "Yellow cards per match" = 2, "Fouls per match" = 2,
                     "Penalties (total)" = 2, "Red cards (total)" = 2)) |>
  pack_rows("Season by season", 1, n_season_rows) |>
  pack_rows("Per-match averages, all seasons", n_season_rows + 1, nrow(TableSix)) |>
  row_spec(which(season_rows$`Furthest round` == "Winner"), bold = TRUE) |>
  kable_styling(latex_options = c("hold_position", "scale_down"), font_size = 9) |>
  footnote(general = paste0(
    "Champions League group/league-phase and knockout matches; qualifying rounds excluded. ",
    "Matches (KO) reports all matches and, in parentheses, knockout matches. Bold rows are ",
    "seasons Real Madrid won the competition. Cards and fouls are recorded from 2005/06; ",
    "penalties are reported only for seasons with complete ESPN event logs (``--'' otherwise). ",
    "In the bottom panel, penalties and red cards are per-match rates. Other elite clubs are the ",
    "twelve perennial Champions League clubs other than Barcelona and Real Madrid. ",
    "Sources: ESPN match summaries."),
    threeparttable = TRUE, escape = FALSE, footnote_as_chunk = TRUE)

save_table(tab6, "table-six-real-madrid-champions-league-by-season.tex")
