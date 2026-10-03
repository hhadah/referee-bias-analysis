################################################################################
# 07-figure-one-barcelona-raw-differentials.R
# Purpose: Figure 1 -- raw per-match net refereeing decisions by season for
#          Barcelona (La Liga and Champions League) and Real Madrid (La Liga).
#          Net = decisions in the team's favor minus decisions against it.
# Input:   data/datasets/team-match-panel.csv
# Output:  output/figures/figure-one-barcelona-raw-differentials.pdf/.png
# Date:    2026-10-02
################################################################################

Panel <- load_panel()

series <- Panel |>
  filter(barca == 1 | real_madrid == 1) |>
  mutate(series = case_when(
    barca == 1 & domestic == 1       ~ "Barcelona, La Liga",
    barca == 1 & domestic == 0       ~ "Barcelona, Champions League",
    real_madrid == 1 & domestic == 1 ~ "Real Madrid, La Liga",
    TRUE ~ NA_character_
  )) |>
  filter(!is.na(series)) |>
  group_by(series, season_start) |>
  summarise(across(c(net_yellow, net_fouls, net_pens), \(v) mean(v, na.rm = TRUE)),
            n = n(), .groups = "drop") |>
  pivot_longer(c(net_yellow, net_fouls, net_pens), names_to = "outcome") |>
  filter(is.finite(value)) |>
  mutate(outcome = factor(outcome_labels[outcome],
                          levels = outcome_labels[c("net_yellow", "net_fouls", "net_pens")]))

fig1 <- ggplot(series, aes(season_start, value, colour = series)) +
  annotate("rect", xmin = -Inf, xmax = negreira_last_season + 0.5, ymin = -Inf, ymax = Inf,
           fill = colors_customs[["accent"]], alpha = 0.12) +
  geom_hline(yintercept = 0, colour = "grey50") +
  geom_vline(xintercept = negreira_last_season + 0.5, linetype = "dashed", colour = "grey30") +
  geom_line(linewidth = 0.7) +
  geom_point(size = 1.4) +
  facet_wrap(~outcome, ncol = 1, scales = "free_y") +
  scale_colour_manual(values = c("Barcelona, La Liga" = colors_customs[["barca"]],
                                 "Barcelona, Champions League" = "#E58FA8",
                                 "Real Madrid, La Liga" = colors_customs[["madrid"]])) +
  scale_x_continuous(breaks = seq(2001, analysis_last_season, 2),
                     labels = \(x) season_label(x)) +
  labs(x = "Season", y = "Per-match mean (favorable minus unfavorable)", colour = NULL,
       title = "Net refereeing decisions per match, Barcelona and Real Madrid",
       subtitle = "Shaded: seasons covered by the reported Negreira payments (through 2017/18)",
       caption = paste0("Net yellow cards = opponent's minus own; net fouls = fouls called on the opponent minus\n",
                        "fouls called on the team; net penalties = awarded minus conceded. Cards and fouls from 2005/06.\n",
                        "Sources: ESPN, football-data.co.uk.")) +
  theme_customs(base_size = 11) +
  theme(axis.text.x = element_text(angle = 45, hjust = 1))

save_figure(fig1, "figure-one-barcelona-raw-differentials.pdf", width = 8, height = 8.5)
