################################################################################
# 09-figure-two-team-favorability-ranking.R
# Purpose: Figure 2 -- team "favorability" fixed effects for every club with
#          at least 150 domestic-league matches, from equation (2):
#          net decision_im = alpha_team + mu_opponent + league-season FE +
#          win-probability FE + home + e. Barcelona's rank among all clubs is
#          the placebo (permutation) benchmark for its estimate.
# Input:   data/datasets/team-match-panel.csv
# Output:  output/figures/figure-two-team-favorability-ranking.pdf/.png
#          output/tables/team-favorability-ranks.csv
# Date:    2026-10-02
################################################################################

Panel <- load_panel() |> filter(domestic == 1)

rank_outcomes <- c("net_yellow", "net_red", "net_fouls", "net_pens")
min_matches <- 150

team_names <- Panel |>
  arrange(desc(date)) |>
  distinct(team_id, .keep_all = TRUE) |>
  select(team_id, team, home_league)

estimate_ranks <- function(y, style) {
  rhs <- if (style) "home + own_shots + opp_shots" else "home"
  fe <- if (style) "team_id + opp_id + league_season + pwin_bin + poss_bin" else
    "team_id + opp_id + league_season + pwin_bin"
  m <- feols(as.formula(paste(y, "~", rhs, "|", fe)), data = Panel)
  used <- Panel[obs(m), ]
  n_team <- count(used, team_id, name = "matches")
  tibble(team_id = names(fixef(m)$team_id), fe = unname(fixef(m)$team_id)) |>
    left_join(n_team, by = "team_id") |>
    left_join(team_names, by = "team_id") |>
    # Normalize within league: 0 = match-weighted average club in the league
    group_by(home_league) |>
    mutate(fe = fe - weighted.mean(fe, matches)) |>
    ungroup() |>
    filter(matches >= min_matches) |>
    mutate(outcome = y,
           spec = if_else(style, "Adding possession and shots", "Pre-match controls"),
           rank = rank(-fe, ties.method = "min"),
           n_teams = n(),
           percentile = 100 * (1 - (rank - 1) / n_teams))
}

Ranks <- expand_grid(y = rank_outcomes, style = c(FALSE, TRUE)) |>
  pmap(\(y, style) estimate_ranks(y, style)) |>
  list_rbind() |>
  left_join(elite_clubs |> select(team_id, club), by = "team_id") |>
  mutate(highlight = case_when(team_id == "83" ~ "Barcelona",
                               team_id == "86" ~ "Real Madrid",
                               !is.na(club) ~ "Other elite clubs",
                               TRUE ~ "All other clubs"),
         highlight = factor(highlight, levels = c("Barcelona", "Real Madrid",
                                                  "Other elite clubs", "All other clubs")),
         outcome_lab = factor(outcome_labels[outcome], levels = outcome_labels[rank_outcomes]),
         spec = factor(spec, levels = c("Pre-match controls", "Adding possession and shots")))

write_csv(Ranks, file.path(tables_wd, "team-favorability-ranks.csv"))

# Permutation-style benchmark: share of clubs at least as favored as Barcelona
BarcaRanks <- Ranks |>
  filter(team_id == "83") |>
  transmute(outcome, spec, fe, rank, n_teams, percentile,
            share_at_least_as_favored = rank / n_teams)
print(BarcaRanks)
write_csv(BarcaRanks, file.path(tables_wd, "barcelona-favorability-rank.csv"))

label_df <- Ranks |>
  filter(highlight %in% c("Barcelona", "Real Madrid")) |>
  mutate(label = paste0(if_else(team_id == "83", "Barcelona", "Real Madrid"),
                        " (", rank, "/", n_teams, ")"))

fig2 <- ggplot(Ranks |> arrange(desc(highlight)), aes(rank, fe)) +
  geom_hline(yintercept = 0, colour = "grey50") +
  geom_point(aes(colour = highlight, size = highlight)) +
  ggrepel::geom_text_repel(data = label_df, aes(label = label, colour = highlight),
                           size = 3, family = "Fira Sans", fontface = "bold",
                           min.segment.length = 0, box.padding = 0.6,
                           nudge_x = 25, show.legend = FALSE) +
  facet_wrap(vars(spec, outcome_lab), ncol = length(rank_outcomes), scales = "free_y",
             labeller = label_wrap_gen(multi_line = TRUE)) +
  scale_colour_manual(values = c("Barcelona" = colors_customs[["barca"]],
                                 "Real Madrid" = colors_customs[["madrid"]],
                                 "Other elite clubs" = colors_customs[["elite"]],
                                 "All other clubs" = colors_customs[["other"]])) +
  scale_size_manual(values = c(3, 3, 1.8, 1.1), guide = "none") +
  labs(x = "Rank (1 = most favorable)", y = "Club fixed effect (per match)", colour = NULL,
       title = "How favorable are referees to each club? Domestic leagues",
       subtitle = paste0("Club fixed effects relative to the average club in the same league; clubs with ",
                         min_matches, "+ matches"),
       caption = paste("Each point is a club's fixed effect from a regression of the net decision on club,",
                       "opponent, league-season, and pre-match win-probability fixed effects and a home indicator.",
                       "\nPositive values = more favorable decisions. Sources: ESPN, football-data.co.uk.")) +
  theme_customs(base_size = 10)

save_figure(fig2, "figure-two-team-favorability-ranking.pdf", width = 11, height = 6.5)
