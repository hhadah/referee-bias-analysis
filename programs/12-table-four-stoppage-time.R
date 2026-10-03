################################################################################
# 12-table-four-stoppage-time.R
# Purpose: Table 4 -- stoppage-time favoritism in the spirit of Garicano,
#          Palacios-Huerta and Prendergast (2005). In close matches (score
#          margin of at most one goal at 90 minutes), does the referee add
#          more time when Barcelona trails than when it leads? Match-level
#          regression (equation 5):
#            Stoppage_m = sum_g [a_g Leads_gm + c_g Trails_gm + d_g Tied_gm]
#                       + b_L HomeLeads_m + b_T HomeTrails_m + X_m pi
#                       + league-season FE + e_m,  g in {Barcelona, Real Madrid}
#          Favoritism toward club g implies c_g - a_g > 0.
# Input:   data/datasets/matches.csv
# Output:  output/tables/table-four-stoppage-time.tex
# Date:    2026-10-02
################################################################################

MatchesST <- read_csv(file.path(datasets, "matches.csv"),
                      col_types = cols(event_id = "c", home_id = "c", away_id = "c"),
                      guess_max = 100000, show_col_types = FALSE) |>
  filter(league != "uefa.champions", season_start <= analysis_last_season,
         !is.na(stoppage_2h), !is.na(margin_90_home), abs(margin_90_home) <= 1) |>
  mutate(
    league_season = paste(league, season_start),
    home_leads = as.integer(margin_90_home == 1),
    home_trails = as.integer(margin_90_home == -1)
  )

# Club-specific state at 90 minutes, from the club's own perspective
state_dummies <- function(df, id, prefix) {
  own_margin <- case_when(df$home_id == id ~ df$margin_90_home,
                          df$away_id == id ~ -df$margin_90_home,
                          TRUE ~ NA_real_)
  df[[paste0(prefix, "_leads")]]  <- as.integer(!is.na(own_margin) & own_margin == 1)
  df[[paste0(prefix, "_trails")]] <- as.integer(!is.na(own_margin) & own_margin == -1)
  df[[paste0(prefix, "_tied")]]   <- as.integer(!is.na(own_margin) & own_margin == 0)
  df
}

MatchesST <- MatchesST |>
  state_dummies("83", "barca") |>
  state_dummies("86", "madrid") |>
  mutate(total_yellow = home_yellow + away_yellow,
         total_red = home_red + away_red,
         total_pens = home_pens + away_pens,
         total_fouls = home_fouls + away_fouls)

rhs_base <- paste("barca_leads + barca_trails + barca_tied + madrid_leads + madrid_trails +",
                  "madrid_tied + home_leads + home_trails")
rhs_ctrl <- paste(rhs_base, "+ goals_2h_regulation + total_yellow + total_red + total_pens")

LaLigaST <- MatchesST |> filter(league == "esp.1")

models4 <- list(
  "(1)" = feols(as.formula(paste("stoppage_2h ~", rhs_base, "| league_season")),
                data = MatchesST, vcov = "hetero"),
  "(2)" = feols(as.formula(paste("stoppage_2h ~", rhs_ctrl, "| league_season")),
                data = MatchesST, vcov = "hetero"),
  "(3)" = feols(as.formula(paste("stoppage_2h ~", rhs_ctrl, "| league_season")),
                data = LaLigaST |> filter(season_start <= negreira_last_season), vcov = "hetero"),
  "(4)" = feols(as.formula(paste("stoppage_2h ~", rhs_ctrl, "| league_season")),
                data = LaLigaST |> filter(season_start > negreira_last_season), vcov = "hetero")
)

lin_diff <- function(m, a, b) {
  bb <- coef(m); V <- vcov(m)
  d <- bb[b] - bb[a]
  se <- sqrt(V[a, a] + V[b, b] - 2 * V[a, b])
  p <- 2 * pnorm(-abs(d / se))
  st <- if (p < 0.01) "***" else if (p < 0.05) "**" else if (p < 0.1) "*" else ""
  c(sprintf("%.3f%s", d, st), sprintf("(%.3f)", se))
}

seasons_range <- function(df) paste0(season_label(min(df$season_start)), "--",
                                     season_label(max(df$season_start)))
extra4 <- bind_rows(
  tibble(term = c("Barcelona: trails $-$ leads", ""),
         !!!map(models4, lin_diff, a = "barca_leads", b = "barca_trails")),
  tibble(term = c("Real Madrid: trails $-$ leads", ""),
         !!!map(models4, lin_diff, a = "madrid_leads", b = "madrid_trails")),
  tibble(term = c("Home team: trails $-$ leads", ""),
         !!!map(models4, lin_diff, a = "home_leads", b = "home_trails")),
  tibble(term = "Mean of dependent variable (minutes)",
         !!!map_chr(models4, \(m) sprintf("%.2f", mean(fitted(m) + resid(m))))),
  tibble(term = "Sample", "(1)" = "Top-5 leagues", "(2)" = "Top-5 leagues",
         "(3)" = "La Liga", "(4)" = "La Liga"),
  tibble(term = "Seasons", "(1)" = seasons_range(MatchesST), "(2)" = seasons_range(MatchesST),
         "(3)" = seasons_range(LaLigaST |> filter(season_start <= negreira_last_season)),
         "(4)" = seasons_range(LaLigaST |> filter(season_start > negreira_last_season))),
  tibble(term = "In-match controls", "(1)" = "No", "(2)" = "Yes", "(3)" = "Yes", "(4)" = "Yes"),
  tibble(term = "League $\\times$ season FE", "(1)" = "Yes", "(2)" = "Yes", "(3)" = "Yes", "(4)" = "Yes")
)

cm4 <- c(barca_leads = "Barcelona leads by 1", barca_trails = "Barcelona trails by 1",
         barca_tied = "Barcelona tied",
         madrid_leads = "Real Madrid leads by 1", madrid_trails = "Real Madrid trails by 1",
         madrid_tied = "Real Madrid tied",
         home_leads = "Home team leads by 1", home_trails = "Home team trails by 1")

tab4 <- modelsummary(
  models4, output = "latex", coef_map = cm4, gof_map = gof_customs,
  add_rows = extra4, stars = stars_customs, escape = FALSE, fmt = 3,
  title = "Second-Half Stoppage Time in Close Matches \\label{tab:stoppage}"
) |>
  kable_styling(latex_options = c("hold_position", "scale_down")) |>
  footnote(general = paste0(
    "This table includes the estimation results of equation (\\\\ref{eq:stoppage}). The unit is a ",
    "domestic-league match whose score margin at 90 minutes is at most one goal. The dependent ",
    "variable is second-half stoppage time in minutes, as recorded in the ESPN match log. The ",
    "omitted category is a tied match not involving Barcelona or Real Madrid. In-match controls ",
    "are second-half goals in regulation and total yellow cards, red cards and penalties. ",
    "Heteroskedasticity-robust standard errors in parentheses."),
    threeparttable = TRUE, escape = FALSE, footnote_as_chunk = TRUE)

save_table(tab4, "table-four-stoppage-time.tex")

TableFourCoefs <- imap(models4, \(m, k) broom::tidy(m) |> mutate(model = k)) |> list_rbind()
write_csv(TableFourCoefs, file.path(tables_wd, "table-four-stoppage-time.csv"))
