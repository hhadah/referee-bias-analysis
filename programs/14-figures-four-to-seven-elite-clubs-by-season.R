################################################################################
# 14-figures-four-to-seven-elite-clubs-by-season.R
# Purpose: Figures 4-7 -- season-by-season refereeing gaps for Barcelona, Real
#          Madrid, and the twelve other elite clubs, each relative to the
#          average non-elite club in its own league-season (equation 4 extended
#          to all elite clubs and all five leagues):
#            y_im = sum_c sum_s b_cs 1[club = c, t = s] + home + league-season FE
#                   + opponent FE + win-prob FE + possession-bin FE + e
#          Figures 4-6: small multiples, one panel per elite club, with
#          Barcelona and Real Madrid overlaid (net yellow cards, net fouls,
#          net penalties). Figure 7: club x season heatmaps.
# Input:   data/datasets/team-match-panel.csv
# Output:  output/figures/figure-four-elite-net-yellow-by-season.pdf/.png
#          output/figures/figure-five-elite-net-fouls-by-season.pdf/.png
#          output/figures/figure-six-elite-net-penalties-by-season.pdf/.png
#          output/figures/figure-seven-elite-heatmap.pdf/.png
#          output/tables/elite-club-season-gaps.csv
# Date:    2026-10-02
################################################################################

Domestic <- load_panel() |>
  filter(domestic == 1) |>
  mutate(poss_bin = fct_na_value_to_level(poss_bin, "missing"),
         club_season = if_else(elite == 1, paste(team_id, season_start, sep = "_"), "ref"))

elite_outcomes <- c("net_yellow", "net_fouls", "net_pens")

# Each club-season coefficient is identified from one team-season, so standard
# errors are heteroskedasticity-robust (as in Figure 3)
fit_elite <- function(y) {
  feols(as.formula(paste(y, "~ i(club_season, ref = 'ref') + home |",
                         "league_season + opp_id + pwin_bin + poss_bin")),
        data = Domestic, vcov = "hetero")
}

EliteGaps <- map(elite_outcomes, \(y) {
  broom::tidy(fit_elite(y), conf.int = TRUE) |>
    filter(str_detect(term, "^club_season::")) |>
    mutate(outcome = y,
           team_id = str_extract(term, "(?<=::)\\d+"),
           season = as.integer(str_extract(term, "\\d{4}$")))
}) |>
  list_rbind() |>
  left_join(elite_clubs, by = "team_id") |>
  mutate(outcome_lab = factor(outcome_labels[outcome], levels = outcome_labels[elite_outcomes]))

write_csv(EliteGaps, file.path(tables_wd, "elite-club-season-gaps.csv"))

# Panel order: by league, then club
league_name_of <- c(England = "Premier League", Spain = "La Liga", Italy = "Serie A",
                    Germany = "Bundesliga", France = "Ligue 1")
comparison_clubs <- elite_clubs |>
  filter(!club %in% c("Barcelona", "Real Madrid")) |>
  mutate(country = factor(country, levels = c("Spain", "England", "Italy", "Germany", "France")),
         panel = paste0(club, " (", league_name_of[as.character(country)], ")")) |>
  arrange(country, club)

series_colors <- c("Barcelona" = colors_customs[["barca"]],
                   "Real Madrid" = colors_customs[["madrid"]],
                   "Club named in panel" = colors_customs[["elite"]])

small_multiples <- function(y, title, ylab) {
  ref <- EliteGaps |> filter(outcome == y, club %in% c("Barcelona", "Real Madrid"))
  # Repeat Barcelona and Real Madrid in every panel as reference series
  ref_panels <- tidyr::crossing(ref, panel = comparison_clubs$panel) |>
    mutate(series = club)
  comp <- EliteGaps |>
    filter(outcome == y) |>
    inner_join(comparison_clubs |> select(team_id, panel), by = "team_id") |>
    mutate(series = "Club named in panel")
  plot_df <- bind_rows(ref_panels, comp) |>
    mutate(panel = factor(panel, levels = comparison_clubs$panel),
           series = factor(series, levels = names(series_colors)))

  ggplot(plot_df, aes(season, estimate, colour = series)) +
    annotate("rect", xmin = -Inf, xmax = negreira_last_season + 0.5, ymin = -Inf, ymax = Inf,
             fill = colors_customs[["accent"]], alpha = 0.10) +
    geom_hline(yintercept = 0, colour = "grey55", linewidth = 0.4) +
    geom_line(aes(group = series), linewidth = 0.55) +
    geom_point(size = 0.9) +
    facet_wrap(~panel, ncol = 4) +
    scale_colour_manual(values = series_colors, breaks = names(series_colors)) +
    scale_x_continuous(breaks = c(2001, 2009, 2017, 2025), labels = \(x) season_label(x)) +
    labs(x = "Season", y = ylab, colour = NULL, title = title,
         subtitle = paste0("Each club relative to the average non-elite club in its own league and season. ",
                           "Shaded: through 2017/18 (Negreira payments)."),
         caption = paste0("Season-specific coefficients from a regression with home, league-season, opponent, ",
                          "pre-match win-probability and possession-bin fixed effects.\n",
                          "Positive = more favorable decisions. Sources: ESPN, football-data.co.uk.")) +
    theme_customs(base_size = 10) +
    theme(legend.position = "top", panel.spacing = unit(0.9, "lines"),
          axis.text.x = element_text(size = rel(0.8)))
}

fig4 <- small_multiples("net_yellow", "Net yellow cards by season: Barcelona and Real Madrid vs. Europe's elite clubs",
                        "Net yellow cards per match (opp. - own)")
fig5 <- small_multiples("net_fouls", "Net fouls by season: Barcelona and Real Madrid vs. Europe's elite clubs",
                        "Net fouls per match (opp. - own)")
fig6 <- small_multiples("net_pens", "Net penalties by season: Barcelona and Real Madrid vs. Europe's elite clubs",
                        "Net penalties per match (for - against)")

save_figure(fig4, "figure-four-elite-net-yellow-by-season.pdf", width = 11, height = 8)
save_figure(fig5, "figure-five-elite-net-fouls-by-season.pdf", width = 11, height = 8)
save_figure(fig6, "figure-six-elite-net-penalties-by-season.pdf", width = 11, height = 8)

# Figure 7: club x season heatmaps (one per outcome, own diverging scale) -------
row_order <- c("Barcelona", "Real Madrid", comparison_clubs$club)

heatmap_panel <- function(y) {
  df <- EliteGaps |>
    filter(outcome == y) |>
    mutate(club = factor(club, levels = rev(row_order)))
  lim <- quantile(abs(df$estimate), 0.95, na.rm = TRUE)
  ggplot(df, aes(season, club, fill = pmax(pmin(estimate, lim), -lim))) +
    geom_tile(colour = "white", linewidth = 0.6) +
    geom_hline(yintercept = length(row_order) - 1.5, colour = "grey20", linewidth = 0.5) +
    geom_vline(xintercept = negreira_last_season + 0.5, linetype = "dashed", colour = "grey20") +
    scale_fill_gradient2(low = "#d95926", mid = "#f0efec", high = "#1c5cab", midpoint = 0,
                         limits = c(-lim, lim), name = "Per match",
                         guide = guide_colourbar(barheight = unit(5, "lines"))) +
    scale_x_continuous(breaks = seq(2001, analysis_last_season, 2), labels = \(x) season_label(x),
                       expand = c(0, 0)) +
    labs(x = NULL, y = NULL, title = outcome_labels[[y]]) +
    theme_customs(base_size = 10) +
    theme(legend.position = "right", panel.grid = element_blank(),
          axis.text.x = element_text(angle = 45, hjust = 1),
          plot.title = element_text(size = rel(1)))
}

fig7 <- patchwork::wrap_plots(map(elite_outcomes, heatmap_panel), ncol = 1) +
  patchwork::plot_annotation(
    title = "Refereeing gaps by club and season: Europe's elite clubs",
    subtitle = paste0("Blue = more favorable than the average non-elite club in the same league-season; ",
                      "orange = less favorable.\nDashed line: end of the reported Negreira payments (2017/18). ",
                      "Colors capped at the 95th percentile of |gap|."),
    caption = paste0("Same estimates as Figures 4-6. Cards and fouls from 2005/06; penalties from 2001/02 ",
                     "where records are complete. Sources: ESPN, football-data.co.uk."),
    theme = theme(plot.title = element_text(face = "bold", size = 14),
                  plot.subtitle = element_text(colour = "grey30", size = 11),
                  plot.caption = element_text(colour = "grey40", hjust = 0, size = 8))
  )

# patchwork 1.3.1 warns spuriously about annotation themes under ggplot2 4.0
# (fixed in patchwork 1.3.2); the theme is applied correctly
suppressWarnings(save_figure(fig7, "figure-seven-elite-heatmap.pdf", width = 11, height = 12))
