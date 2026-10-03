################################################################################
# 06-table-one-summary-statistics.R
# Purpose: Table 1 -- per-match refereeing decisions for Barcelona, Real
#          Madrid, the other elite clubs, and all other teams, separately for
#          domestic leagues and the Champions League.
# Input:   data/datasets/team-match-panel.csv
# Output:  output/tables/table-one-summary-statistics.tex
# Date:    2026-10-02
################################################################################

Panel <- load_panel()

Panel <- Panel |>
  mutate(group = case_when(
    barca == 1 & domestic == 1       ~ "Barcelona, La Liga",
    barca == 1 & domestic == 0       ~ "Barcelona, UCL",
    real_madrid == 1 & domestic == 1 ~ "Real Madrid, La Liga",
    league == "esp.1"                ~ "Other La Liga teams",
    other_elite == 1 & domestic == 1 ~ "Other elite clubs, domestic",
    domestic == 1                    ~ "All other teams, domestic",
    other_elite == 1 & domestic == 0 ~ "Other elite clubs, UCL",
    TRUE                             ~ NA_character_
  )) |>
  filter(!is.na(group))

group_order <- c("Barcelona, La Liga", "Real Madrid, La Liga", "Other La Liga teams",
                 "Other elite clubs, domestic", "All other teams, domestic",
                 "Barcelona, UCL", "Other elite clubs, UCL")

sum_vars <- c(
  own_yellow = "Yellow cards received", opp_yellow = "Yellow cards to opponent",
  own_red = "Red cards received", opp_red = "Red cards to opponent",
  own_fouls = "Fouls committed", opp_fouls = "Fouls suffered",
  yellow_per_foul = "Yellow cards per foul committed",
  own_pens = "Penalties awarded", opp_pens = "Penalties conceded",
  own_possession = "Possession (\\%)", own_shots = "Shots",
  prob_win = "Pre-match win probability (odds)", elo_exp = "Elo expected score",
  goal_diff = "Goal difference"
)

SumStats <- Panel |>
  group_by(group) |>
  summarise(across(all_of(names(sum_vars)), \(v) mean(v, na.rm = TRUE)),
            matches = n(), .groups = "drop") |>
  mutate(group = factor(group, levels = group_order)) |>
  arrange(group)

TableOne <- SumStats |>
  pivot_longer(-group, names_to = "variable") |>
  pivot_wider(names_from = group, values_from = value) |>
  mutate(variable = coalesce(sum_vars[variable], "Team-matches"),
         across(-variable, \(v) if_else(variable == "Team-matches",
                                        formatC(v, format = "d", big.mark = ","),
                                        formatC(v, format = "f", digits = 2))),
         across(-variable, \(v) str_replace(v, "^NaN$|^NA$", "--")))

present <- intersect(group_order, names(TableOne))
TableOne <- TableOne |> select(variable, all_of(present))
n_dom <- sum(!str_detect(present, "UCL"))

tab1 <- kbl(TableOne, format = "latex", booktabs = TRUE, escape = FALSE,
            col.names = linebreak(c("", str_replace(present, ", ", "\n")),
                                  align = "c"),
            align = c("l", rep("c", length(present))),
            caption = "Refereeing Decisions per Match: Barcelona in Perspective \\label{tab:sumstats}") |>
  add_header_above(c(" " = 1, "Domestic leagues" = n_dom,
                     "Champions League" = length(present) - n_dom)) |>
  kable_styling(latex_options = c("hold_position", "scale_down")) |>
  footnote(general = paste0(
    "This table reports per-match means at the team-match level. Elite clubs are the ",
    "14 perennial Champions League participants listed in the text. Cards and fouls cover ",
    "2005/06--2025/26; penalties cover all league-seasons from 2001/02 with complete ",
    "penalty records in the ESPN event logs. Pre-match win probabilities are implied by ",
    "bookmaker odds (domestic leagues only). Champions League qualifying rounds are excluded. ",
    "Sources: ESPN match summaries and football-data.co.uk."),
    threeparttable = TRUE, escape = FALSE, footnote_as_chunk = TRUE)

save_table(tab1, "table-one-summary-statistics.tex")
write_csv(SumStats, file.path(tables_wd, "table-one-summary-statistics.csv"))
