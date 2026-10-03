################################################################################
# 08-table-two-team-fixed-effects.R
# Purpose: Table 2 -- conditional differences in refereeing decisions for
#          Barcelona, Real Madrid, and the other elite clubs relative to the
#          average team in the same league-season (domestic leagues), holding
#          fixed home status, opponent identity, and pre-match expected
#          strength (equation 1). Panel B adds in-game style controls.
# Input:   data/datasets/team-match-panel.csv
# Output:  output/tables/table-two-team-fixed-effects.tex
# Date:    2026-10-02
################################################################################

Panel <- load_panel() |> filter(domestic == 1)

# Columns (9)-(10): yellow cards conditional on called fouls. This is a
# descriptive sanction comparison, not a probability of a card per foul:
# dissent/time-wasting cards and uncalled or differently severe fouls remain.
outcomes <- c("own_yellow", "opp_yellow", "own_red", "opp_red",
              "own_fouls", "opp_fouls", "own_pens", "opp_pens",
              "own_yellow", "opp_yellow")
foul_ctrl <- c(rep("", 8), "+ own_fouls", "+ opp_fouls")
n_col <- length(outcomes)

rhs_a <- "barca + real_madrid + other_elite + home {ctrl} | league_season + opp_id + pwin_bin"
rhs_b <- paste("barca + real_madrid + other_elite + home + own_shots + opp_shots {ctrl} |",
               "league_season + opp_id + pwin_bin + poss_bin")

fit <- function(y, ctrl, rhs) {
  feols(as.formula(paste(y, "~", glue::glue(rhs, ctrl = ctrl))), data = Panel,
        vcov = ~team_season)
}
models_a <- map2(outcomes, foul_ctrl, fit, rhs = rhs_a)
models_b <- map2(outcomes, foul_ctrl, fit, rhs = rhs_b)

# Wald test of Barcelona = Real Madrid
p_equal <- function(m) {
  b <- coef(m); V <- vcov(m)
  d <- b["barca"] - b["real_madrid"]
  se <- sqrt(V["barca", "barca"] + V["real_madrid", "real_madrid"] - 2 * V["barca", "real_madrid"])
  formatC(2 * pnorm(-abs(d / se)), format = "f", digits = 3)
}
dep_mean <- function(m) formatC(mean(fitted(m) + resid(m)), format = "f", digits = 3)

col_names <- paste0("(", seq_len(n_col), ")")
models_a <- set_names(models_a, col_names)
models_b <- set_names(models_b, col_names)
yes <- set_names(rep("Yes", n_col), col_names)

extra <- bind_rows(
  tibble(term = "Mean of dependent variable", !!!map_chr(models_a, dep_mean)),
  tibble(term = "p-value: Barcelona = Real Madrid (A)", !!!map_chr(models_a, p_equal)),
  tibble(term = "p-value: Barcelona = Real Madrid (B)", !!!map_chr(models_b, p_equal)),
  tibble(term = "League $\\times$ season FE", !!!yes),
  tibble(term = "Opponent FE", !!!yes),
  tibble(term = "Win-probability ventile FE", !!!yes),
  tibble(term = "Possession-bin FE (Panel B)", !!!yes)
)

cm <- c(barca = "Barcelona", real_madrid = "Real Madrid",
        other_elite = "Other elite clubs", home = "Home",
        own_fouls = "Fouls committed", opp_fouls = "Fouls suffered",
        own_shots = "Own shots", opp_shots = "Opponent shots")

panels <- list("Panel A: Pre-match controls" = models_a,
               "Panel B: Adding in-game style controls (possession bins, shots)" = models_b)

tab2 <- modelsummary(
  panels, shape = "rbind", output = "latex",
  coef_map = cm, gof_map = gof_customs, add_rows = extra,
  stars = stars_customs, escape = FALSE, fmt = 3,
  title = "Refereeing Decisions: Barcelona Relative to the Average Team in Its League \\label{tab:teamfe}"
) |>
  add_header_above(c(" " = 1, "Against" = 1, "For" = 1, "Against" = 1, "For" = 1,
                     "Against" = 1, "For" = 1, "Awarded" = 1, "Conceded" = 1,
                     "Against" = 1, "For" = 1),
                   line = FALSE) |>
  add_header_above(c(" " = 1, "Yellow cards" = 2, "Red cards" = 2, "Fouls" = 2,
                     "Penalties" = 2, "Yellow cards given fouls" = 2)) |>
  kable_styling(latex_options = c("hold_position", "scale_down")) |>
  footnote(general = paste0(
    "This table includes the estimation results of equation (\\\\ref{eq:teamfe}) on the ",
    "team-match panel of the top-5 domestic leagues. Each column is a separate regression; the ",
    "dependent variable is the per-match count named in the column header from the team's ",
    "perspective (``against'' = decisions against the team; ``for'' = decisions against its ",
    "opponent). Barcelona, Real Madrid and Other elite clubs are team indicators, so each ",
    "coefficient is the difference relative to the average non-elite team in the same ",
    "league-season facing the same opponent at the same pre-match win probability. Cards and ",
    "fouls cover 2005/06--2025/26; penalties use matches with ",
    "eligible penalty event logs. Columns (9) and (10) condition on called fouls ",
    "but cannot hold foul severity or non-foul misconduct fixed. Panel B adds ",
    "possession bins and both teams' shots, which can respond to refereeing decisions. ",
    "Standard errors clustered at the team-season level in parentheses."),
    threeparttable = TRUE, escape = FALSE, footnote_as_chunk = TRUE)

save_table(tab2, "table-two-team-fixed-effects.tex")

# Machine-readable coefficients for the write-up
TableTwoCoefs <- imap(list(A = models_a, B = models_b), \(ms, panel)
  imap(ms, \(m, k) broom::tidy(m) |>
         mutate(column = k, outcome = outcomes[match(k, col_names)],
                foul_control = foul_ctrl[match(k, col_names)] != "", panel = panel)) |>
    list_rbind()
) |> list_rbind()
write_csv(TableTwoCoefs, file.path(tables_wd, "table-two-team-fixed-effects.csv"))
