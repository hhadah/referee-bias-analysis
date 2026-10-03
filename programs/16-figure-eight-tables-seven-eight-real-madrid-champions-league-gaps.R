################################################################################
# 16-figure-eight-tables-seven-eight-real-madrid-champions-league-gaps.R
# Purpose: Real Madrid's refereeing gaps in the Champions League.
#          Figure 8 -- season-by-season conditional gaps (net yellow cards, net
#            fouls, net penalties) for Real Madrid, Barcelona and the other elite
#            clubs, each relative to the average non-elite team in the same
#            Champions League season (equation 6):
#              y_im = sum_s [r_s RM_i + b_s Barca_i + e_s Elite_i] 1[t = s]
#                     + home + season FE + stage FE + opponent FE
#                     + Elo-ventile FE + possession-bin FE + u
#          Table 7 -- pooled versions: overall, by stage (group vs knockout),
#            and by era (2001/02-2012/13, 2013/14-2017/18, 2018/19-2025/26).
#          Table 8 -- stoppage time in close Champions League matches when Real
#            Madrid leads vs trails at 90 minutes.
# Input:   data/datasets/team-match-panel.csv, data/datasets/matches.csv
# Output:  output/figures/figure-eight-real-madrid-champions-league-by-season.pdf/.png
#          output/tables/table-seven-real-madrid-champions-league-gaps.tex/.csv
#          output/tables/table-eight-real-madrid-champions-league-stoppage.tex/.csv
# Date:    2026-10-02
################################################################################

UCL <- load_panel() |>
  filter(domestic == 0) |>
  mutate(poss_bin = fct_na_value_to_level(poss_bin, "missing"),
         knockout = as.integer(ucl_stage == "Knockout"),
         rm_era = case_when(season_start <= 2012 ~ "2001/02-2012/13",
                            season_start <= 2017 ~ "2013/14-2017/18",
                            TRUE ~ "2018/19-2025/26"))

UCLMatches <- read_csv(file.path(datasets, "matches.csv"),
                       col_types = cols(event_id = "c", home_id = "c", away_id = "c"),
                       guess_max = 100000, show_col_types = FALSE) |>
  filter(league == "uefa.champions", season_start <= analysis_last_season,
         coalesce(ucl_stage, "") != "Qualifying")

rm_titles <- UCLMatches |>
  filter(str_detect(round_slug, "(^|-)final$"),
         (home_id == "86" & home_winner) | (away_id == "86" & away_winner)) |>
  pull(season_start)
message("Real Madrid Champions League titles in sample: ",
        paste(season_label(rm_titles), collapse = ", "))

fe_ucl <- "season_start + ucl_stage + opp_id + elo_bin + poss_bin"

# Figure 8: season-by-season gaps -----------------------------------------------
# Each club-season coefficient rests on 8-17 matches: standard errors are
# heteroskedasticity-robust and wide.
ucl_outcomes <- c("net_yellow", "net_fouls", "net_pens")

fit_season <- function(y) {
  feols(as.formula(paste(y, "~ i(season_start, real_madrid) + i(season_start, barca) +",
                         "i(season_start, other_elite) + home |", fe_ucl)),
        data = UCL, vcov = "hetero")
}

SeasonGaps <- map(ucl_outcomes, \(y) {
  broom::tidy(fit_season(y), conf.int = TRUE) |>
    filter(str_detect(term, "season_start::")) |>
    mutate(outcome = y,
           season = as.integer(str_extract(term, "(?<=::)\\d{4}")),
           series = case_when(str_detect(term, "real_madrid") ~ "Real Madrid",
                              str_detect(term, "barca") ~ "Barcelona",
                              TRUE ~ "Other elite clubs (pooled)"))
}) |>
  list_rbind() |>
  # Explicit missing seasons so lines and ribbons break where data are missing
  complete(outcome, series, season = 2001:analysis_last_season) |>
  mutate(outcome_lab = factor(outcome_labels[outcome], levels = outcome_labels[ucl_outcomes]),
         series = factor(series, levels = c("Real Madrid", "Barcelona", "Other elite clubs (pooled)")),
         title = series == "Real Madrid" & season %in% rm_titles & !is.na(estimate))

write_csv(SeasonGaps, file.path(tables_wd, "real-madrid-champions-league-season-gaps.csv"))

ucl_colors <- c("Real Madrid" = colors_customs[["madrid"]],
                "Barcelona" = colors_customs[["barca"]],
                "Other elite clubs (pooled)" = colors_customs[["elite"]])

fig8 <- ggplot(SeasonGaps, aes(season, estimate, colour = series)) +
  geom_hline(yintercept = 0, colour = "grey55", linewidth = 0.4) +
  geom_ribbon(data = filter(SeasonGaps, series == "Real Madrid"),
              aes(ymin = conf.low, ymax = conf.high), fill = colors_customs[["madrid"]],
              alpha = 0.15, colour = NA) +
  geom_line(aes(group = series, linewidth = series)) +
  geom_point(data = filter(SeasonGaps, !title, !is.na(estimate)), size = 1.3) +
  geom_point(data = filter(SeasonGaps, title), aes(shape = "Real Madrid won the title"),
             size = 3.2, stroke = 0.9, fill = colors_customs[["madrid"]], colour = "grey15") +
  facet_wrap(~outcome_lab, ncol = 1, scales = "free_y") +
  scale_colour_manual(values = ucl_colors) +
  scale_linewidth_manual(values = c(0.9, 0.5, 0.5), guide = "none") +
  scale_shape_manual(values = c("Real Madrid won the title" = 23), name = NULL) +
  scale_x_continuous(breaks = seq(2001, analysis_last_season, 2), labels = \(x) season_label(x)) +
  labs(x = "Season", y = "Conditional gap vs. average non-elite team (per match)", colour = NULL,
       title = "Real Madrid in the Champions League: refereeing gaps by season",
       subtitle = paste0("Relative to the average non-elite team in the same season. Ribbon: 95% confidence ",
                         "interval for Real Madrid.\nEach season rests on 8-17 Real Madrid matches."),
       caption = paste0("Controls: home, season, stage, opponent, Elo expected-score and possession-bin fixed ",
                        "effects; heteroskedasticity-robust standard errors.\nGroup/league phase and knockout ",
                        "matches; cards and fouls from 2005/06. Positive = more favorable. Source: ESPN.")) +
  theme_customs(base_size = 11) +
  theme(axis.text.x = element_text(angle = 45, hjust = 1), legend.box = "horizontal")

save_figure(fig8, "figure-eight-real-madrid-champions-league-by-season.pdf", width = 8.5, height = 9.5)

# Table 7: pooled gaps ------------------------------------------------------------
outcomes7 <- c("own_yellow", "opp_yellow", "own_fouls", "opp_fouls", "own_pens", "opp_pens")
col_names7 <- paste0("(", seq_along(outcomes7), ")")

UCL <- UCL |>
  mutate(rm_group = real_madrid * (1 - knockout), rm_ko = real_madrid * knockout,
         rm_era1 = real_madrid * (rm_era == "2001/02-2012/13"),
         rm_era2 = real_madrid * (rm_era == "2013/14-2017/18"),
         rm_era3 = real_madrid * (rm_era == "2018/19-2025/26"))

fit7 <- function(y, rhs) {
  feols(as.formula(paste(y, "~", rhs, "+ barca + other_elite + home |", fe_ucl)),
        data = UCL, vcov = ~team_season)
}
models7 <- list(
  "Panel A: All matches" = map(outcomes7, fit7, rhs = "real_madrid") |> set_names(col_names7),
  "Panel B: By stage" = map(outcomes7, fit7, rhs = "rm_group + rm_ko") |> set_names(col_names7),
  "Panel C: By era" = map(outcomes7, fit7, rhs = "rm_era1 + rm_era2 + rm_era3") |> set_names(col_names7)
)

p_diff <- function(m, a, b) {
  bb <- coef(m); V <- vcov(m)
  d <- bb[b] - bb[a]
  formatC(2 * pnorm(-abs(d / sqrt(V[a, a] + V[b, b] - 2 * V[a, b]))), format = "f", digits = 3)
}
yes7 <- set_names(rep("Yes", length(outcomes7)), col_names7)

extra7 <- bind_rows(
  tibble(term = "Mean of dependent variable",
         !!!map_chr(models7[[1]], \(m) formatC(mean(fitted(m) + resid(m)), format = "f", digits = 3))),
  tibble(term = "p-value: Real Madrid = other elite clubs (A)",
         !!!map_chr(models7[[1]], p_diff, a = "real_madrid", b = "other_elite")),
  tibble(term = "p-value: knockout = group (B)", !!!map_chr(models7[[2]], p_diff, a = "rm_group", b = "rm_ko")),
  tibble(term = "p-value: 2013/14--2017/18 = 2018/19--2025/26 (C)",
         !!!map_chr(models7[[3]], p_diff, a = "rm_era2", b = "rm_era3")),
  tibble(term = "Season, stage, opponent FE", !!!yes7),
  tibble(term = "Elo-ventile and possession-bin FE", !!!yes7)
)

cm7 <- c(real_madrid = "Real Madrid",
         rm_group = "Real Madrid $\\times$ group/league phase",
         rm_ko = "Real Madrid $\\times$ knockout",
         rm_era1 = "Real Madrid $\\times$ 2001/02--2012/13",
         rm_era2 = "Real Madrid $\\times$ 2013/14--2017/18",
         rm_era3 = "Real Madrid $\\times$ 2018/19--2025/26",
         barca = "Barcelona", other_elite = "Other elite clubs")

tab7 <- modelsummary(
  models7, shape = "rbind", output = "latex", coef_map = cm7, gof_map = gof_customs,
  add_rows = extra7, stars = stars_customs, escape = FALSE, fmt = 3,
  title = "Real Madrid's Refereeing Gaps in the Champions League \\label{tab:rmuclreg}"
) |>
  add_header_above(c(" " = 1, "Against" = 1, "For" = 1, "Against" = 1, "For" = 1,
                     "Awarded" = 1, "Conceded" = 1), line = FALSE) |>
  add_header_above(c(" " = 1, "Yellow cards" = 2, "Fouls" = 2, "Penalties" = 2)) |>
  kable_styling(latex_options = c("hold_position", "scale_down")) |>
  footnote(general = paste0(
    "This table includes the estimation results of equation (\\\\ref{eq:rmucl}), pooled across ",
    "seasons, on the Champions League team-match panel (group/league phase and knockouts). ",
    "Coefficients are per-match differences relative to the average non-elite team in the same ",
    "season, stage, and Elo-ventile, facing the same opponent. 2013/14--2017/18 covers Real ",
    "Madrid's four titles in five seasons. Cards and fouls cover 2005/06--2025/26; penalties cover ",
    "seasons with complete event logs. Standard errors clustered at the team-season level in ",
    "parentheses."),
    threeparttable = TRUE, escape = FALSE, footnote_as_chunk = TRUE)

save_table(tab7, "table-seven-real-madrid-champions-league-gaps.tex")

TableSevenCoefs <- imap(models7, \(ms, panel)
  imap(ms, \(m, k) broom::tidy(m) |>
         mutate(outcome = outcomes7[match(k, col_names7)], panel = panel)) |>
    list_rbind()
) |> list_rbind()
write_csv(TableSevenCoefs, file.path(tables_wd, "table-seven-real-madrid-champions-league-gaps.csv"))

# Table 8: stoppage time in close Champions League matches -----------------------
state_dummies_ucl <- function(df, ids, prefix) {
  own_margin <- case_when(df$home_id %in% ids ~ df$margin_90_home,
                          df$away_id %in% ids ~ -df$margin_90_home,
                          TRUE ~ NA_real_)
  df[[paste0(prefix, "_leads")]]  <- as.integer(!is.na(own_margin) & own_margin == 1)
  df[[paste0(prefix, "_trails")]] <- as.integer(!is.na(own_margin) & own_margin == -1)
  df[[paste0(prefix, "_tied")]]   <- as.integer(!is.na(own_margin) & own_margin == 0)
  df
}

other_elite_ids <- setdiff(elite_clubs$team_id, c("83", "86"))

StoppageUCL <- UCLMatches |>
  # In matches between two elite clubs, each club's own state is coded
  filter(!is.na(stoppage_2h), !is.na(margin_90_home), abs(margin_90_home) <= 1) |>
  mutate(home_leads = as.integer(margin_90_home == 1 & !neutral_site),
         home_trails = as.integer(margin_90_home == -1 & !neutral_site),
         knockout = as.integer(ucl_stage == "Knockout"),
         total_yellow = home_yellow + away_yellow, total_red = home_red + away_red,
         total_pens = home_pens + away_pens) |>
  state_dummies_ucl("86", "madrid") |>
  state_dummies_ucl("83", "barca") |>
  state_dummies_ucl(other_elite_ids, "elite")

rhs8 <- paste("madrid_leads + madrid_trails + madrid_tied + barca_leads + barca_trails + barca_tied +",
              "elite_leads + elite_trails + elite_tied + home_leads + home_trails +",
              "goals_2h_regulation + total_yellow + total_red + total_pens | season_start + ucl_stage")

models8 <- list(
  "(1)" = feols(as.formula(paste("stoppage_2h ~", rhs8)), data = StoppageUCL, vcov = "hetero"),
  "(2)" = feols(as.formula(paste("stoppage_2h ~", rhs8)), data = filter(StoppageUCL, knockout == 0),
                vcov = "hetero"),
  "(3)" = feols(as.formula(paste("stoppage_2h ~", rhs8)), data = filter(StoppageUCL, knockout == 1),
                vcov = "hetero")
)

lin_diff8 <- function(m, a, b) {
  bb <- coef(m); V <- vcov(m)
  d <- bb[b] - bb[a]
  se <- sqrt(V[a, a] + V[b, b] - 2 * V[a, b])
  p <- 2 * pnorm(-abs(d / se))
  st <- if (p < 0.01) "***" else if (p < 0.05) "**" else if (p < 0.1) "*" else ""
  c(sprintf("%.3f%s", d, st), sprintf("(%.3f)", se))
}
n_state <- function(df, v) as.character(sum(df[[v]]))

extra8 <- bind_rows(
  tibble(term = c("Real Madrid: trails $-$ leads", ""),
         !!!map(models8, lin_diff8, a = "madrid_leads", b = "madrid_trails")),
  tibble(term = c("Barcelona: trails $-$ leads", ""),
         !!!map(models8, lin_diff8, a = "barca_leads", b = "barca_trails")),
  tibble(term = c("Other elite clubs: trails $-$ leads", ""),
         !!!map(models8, lin_diff8, a = "elite_leads", b = "elite_trails")),
  tibble(term = "Real Madrid matches leading / trailing by one",
         "(1)" = paste(n_state(StoppageUCL, "madrid_leads"), "/", n_state(StoppageUCL, "madrid_trails")),
         "(2)" = paste(n_state(filter(StoppageUCL, knockout == 0), "madrid_leads"), "/",
                       n_state(filter(StoppageUCL, knockout == 0), "madrid_trails")),
         "(3)" = paste(n_state(filter(StoppageUCL, knockout == 1), "madrid_leads"), "/",
                       n_state(filter(StoppageUCL, knockout == 1), "madrid_trails"))),
  tibble(term = "Mean of dependent variable (minutes)",
         !!!map_chr(models8, \(m) sprintf("%.2f", mean(fitted(m) + resid(m))))),
  tibble(term = "Sample", "(1)" = "All", "(2)" = "Group/league phase", "(3)" = "Knockout"),
  tibble(term = "Season and stage FE; in-match controls", "(1)" = "Yes", "(2)" = "Yes", "(3)" = "Yes")
)

cm8 <- c(madrid_leads = "Real Madrid leads by 1", madrid_trails = "Real Madrid trails by 1",
         madrid_tied = "Real Madrid tied",
         barca_leads = "Barcelona leads by 1", barca_trails = "Barcelona trails by 1",
         elite_leads = "Other elite club leads by 1", elite_trails = "Other elite club trails by 1",
         home_leads = "Home team leads by 1", home_trails = "Home team trails by 1")

tab8 <- modelsummary(
  models8, output = "latex", coef_map = cm8, gof_map = gof_customs,
  add_rows = extra8, stars = stars_customs, escape = FALSE, fmt = 3,
  title = "Second-Half Stoppage Time in Close Champions League Matches \\label{tab:rmuclstoppage}"
) |>
  kable_styling(latex_options = c("hold_position", "scale_down")) |>
  footnote(general = paste0(
    "The unit is a Champions League match (group/league phase or knockout) whose score margin at ",
    "90 minutes is at most one goal and whose stoppage time is recorded (2005/06 onward). The ",
    "dependent variable is second-half stoppage time in minutes. The omitted category is a tied ",
    "match not involving an elite club. Home-team indicators are zero at neutral venues (finals and ",
    "the 2020 final tournament). In-match controls are second-half goals in regulation and total ",
    "yellow cards, red cards and penalties. Heteroskedasticity-robust standard errors in ",
    "parentheses."),
    threeparttable = TRUE, escape = FALSE, footnote_as_chunk = TRUE)

save_table(tab8, "table-eight-real-madrid-champions-league-stoppage.tex")

TableEightCoefs <- imap(models8, \(m, k) broom::tidy(m) |> mutate(model = k)) |> list_rbind()
write_csv(TableEightCoefs, file.path(tables_wd, "table-eight-real-madrid-champions-league-stoppage.csv"))
