################################################################################
# 11-figure-three-negreira-event-study.R
# Purpose: Figure 3 -- season-by-season conditional decision gaps for
#          Barcelona and Real Madrid in La Liga relative to the average La Liga
#          club (equation 4), around the end of the reported Negreira payments
#          (2017/18) and the introduction of VAR (2018/19):
#            y_im = sum_s b_s Barca_i 1[t = s] + sum_s r_s RealMadrid_i 1[t = s]
#                   + home + season FE + opponent FE + win-prob FE
#                   + possession-bin FE + e
# Input:   data/datasets/team-match-panel.csv
# Output:  output/figures/figure-three-negreira-event-study.pdf/.png
#          output/tables/event-study-pre-post.csv
# Date:    2026-10-02
################################################################################

# Possession bins control for Barcelona's changing dominance over time; seasons
# without possession data (2001/02-2004/05) form their own category
LaLiga <- load_panel() |>
  filter(league == "esp.1") |>
  mutate(poss_bin = fct_na_value_to_level(poss_bin, "missing"))

es_outcomes <- c("net_yellow", "net_fouls", "net_pens")

# Each club-season coefficient is identified from a single team-season, so
# clustering at that level is degenerate here; use heteroskedasticity-robust
# standard errors for the season-specific coefficients. The pooled pre/post
# comparison below clusters at the team-season level.
fit_es <- function(y) {
  feols(as.formula(paste(y, "~ i(season_start, barca) + i(season_start, real_madrid) + home |",
                         "season_start + opp_id + pwin_bin + poss_bin")),
        data = LaLiga, vcov = "hetero")
}
es_models <- map(es_outcomes, fit_es) |> set_names(es_outcomes)

EventStudy <- imap(es_models, \(m, y) broom::tidy(m, conf.int = TRUE) |>
                     filter(str_detect(term, "season_start::")) |>
                     mutate(outcome = y,
                            season = as.integer(str_extract(term, "(?<=::)\\d{4}")),
                            club = if_else(str_detect(term, "barca"), "Barcelona", "Real Madrid"))) |>
  list_rbind() |>
  mutate(outcome_lab = factor(outcome_labels[outcome], levels = outcome_labels[es_outcomes]))

# Pre/post averages and the difference-in-differences (Barcelona vs Real Madrid)
fit_dd <- function(y) {
  LaLiga |>
    mutate(barca_post = barca * (1 - negreira_era),
           madrid_post = real_madrid * (1 - negreira_era)) |>
    feols(as.formula(paste(y, "~ barca + barca_post + real_madrid + madrid_post + home |",
                           "season_start + opp_id + pwin_bin + poss_bin")),
          data = _, vcov = ~team_season)
}
dd_models <- map(es_outcomes, fit_dd) |> set_names(es_outcomes)
PrePost <- imap(dd_models, \(m, y) {
  b <- coef(m); V <- vcov(m)
  dd <- b["barca_post"] - b["madrid_post"]
  se <- sqrt(V["barca_post", "barca_post"] + V["madrid_post", "madrid_post"] -
               2 * V["barca_post", "madrid_post"])
  tibble(outcome = y,
         barca_pre = b["barca"], barca_change = b["barca_post"],
         barca_change_se = sqrt(V["barca_post", "barca_post"]),
         madrid_pre = b["real_madrid"], madrid_change = b["madrid_post"],
         madrid_change_se = sqrt(V["madrid_post", "madrid_post"]),
         dd_barca_minus_madrid = dd, dd_se = se, dd_p = 2 * pnorm(-abs(dd / se)),
         n = nobs(m))
}) |> list_rbind()
print(PrePost)
write_csv(PrePost, file.path(tables_wd, "event-study-pre-post.csv"))
write_csv(EventStudy, file.path(tables_wd, "event-study-coefficients.csv"))

fig3 <- ggplot(EventStudy, aes(season, estimate, colour = club, fill = club)) +
  annotate("rect", xmin = -Inf, xmax = negreira_last_season + 0.5, ymin = -Inf, ymax = Inf,
           fill = colors_customs[["accent"]], alpha = 0.12) +
  geom_hline(yintercept = 0, colour = "grey50") +
  geom_vline(xintercept = negreira_last_season + 0.5, linetype = "dashed", colour = "grey30") +
  geom_ribbon(aes(ymin = conf.low, ymax = conf.high), alpha = 0.15, colour = NA) +
  geom_line(linewidth = 0.7) +
  geom_point(size = 1.5) +
  facet_wrap(~outcome_lab, ncol = 1, scales = "free_y") +
  scale_colour_manual(values = c("Barcelona" = colors_customs[["barca"]],
                                 "Real Madrid" = colors_customs[["madrid"]]),
                      aesthetics = c("colour", "fill")) +
  scale_x_continuous(breaks = seq(2001, analysis_last_season, 2), labels = \(x) season_label(x)) +
  labs(x = "Season", y = "Conditional gap vs. average La Liga club (per match)",
       colour = NULL, fill = NULL,
       title = "Barcelona and Real Madrid relative to the average La Liga club, by season",
       subtitle = paste0("Dashed line: last season of the reported Negreira payments (2017/18).\n",
                         "VAR enters La Liga in 2018/19; Messi leaves after 2020/21."),
       caption = paste0("Coefficients from equation (4) with 95% confidence intervals (heteroskedasticity-robust).\n",
                        "Controls: home, season, opponent, pre-match win-probability, and possession-bin fixed effects.\n",
                        "Positive values = more favorable decisions. Sources: ESPN, football-data.co.uk.")) +
  theme_customs(base_size = 11) +
  theme(axis.text.x = element_text(angle = 45, hjust = 1))

save_figure(fig3, "figure-three-negreira-event-study.pdf", width = 8, height = 8.5)
