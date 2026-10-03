################################################################################
# 13-table-five-exposure-adjusted-fouls.R
# Purpose: Table 5 -- fouls normalized by exposure. A team can only be fouled
#          while it has the ball and can only commit fouls while the opponent
#          has it, so possession is the natural exposure measure:
#            (1)-(2) fouls per 10 minutes of possession (OLS on the rate);
#            (3)-(4) Poisson with log possession share as an offset, which
#                    imposes fouls proportional to possession;
#            (5)-(6) Poisson with log possession share as a regressor, which
#                    estimates the elasticity instead of imposing one;
#            (7)-(8) fouls per 100 passes, a volume-based exposure measure.
#          "Suffered" = fouls called on the opponent while the team has the
#          ball (exposure: own possession); "committed" = fouls called on the
#          team (exposure: opponent possession).
# Input:   data/datasets/team-match-panel.csv
# Output:  output/tables/table-five-exposure-adjusted-fouls.tex
# Date:    2026-10-02
################################################################################

Exposure <- load_panel() |>
  filter(domestic == 1, !is.na(own_possession), !is.na(own_fouls),
         own_possession > 0, opp_possession > 0) |>
  mutate(
    # Nominal possession minutes (90-minute match); ball-in-play time is not observed
    suffered_per10  = opp_fouls / (own_possession / 100 * 90) * 10,
    committed_per10 = own_fouls / (opp_possession / 100 * 90) * 10,
    suffered_per100_passes  = if_else(own_passes > 0, 100 * opp_fouls / own_passes, NA_real_),
    committed_per100_passes = if_else(opp_passes > 0, 100 * own_fouls / opp_passes, NA_real_),
    log_own_poss = log(own_possession / 100),
    log_opp_poss = log(opp_possession / 100)
  )

fe5 <- "league_season + opp_id + pwin_bin"
rhs5 <- "barca + real_madrid + other_elite + home"
vc5 <- ~team_season

# The exposure regressor enters under a common name so it shares one table row
with_exposure <- function(df, v) mutate(df, log_exposure = .data[[v]])

models5 <- list(
  "(1)" = feols(as.formula(paste("suffered_per10 ~", rhs5, "|", fe5)), Exposure, vcov = vc5),
  "(2)" = feols(as.formula(paste("committed_per10 ~", rhs5, "|", fe5)), Exposure, vcov = vc5),
  "(3)" = fepois(as.formula(paste("opp_fouls ~", rhs5, "|", fe5)), Exposure,
                 offset = ~log_own_poss, vcov = vc5),
  "(4)" = fepois(as.formula(paste("own_fouls ~", rhs5, "|", fe5)), Exposure,
                 offset = ~log_opp_poss, vcov = vc5),
  "(5)" = fepois(as.formula(paste("opp_fouls ~", rhs5, "+ log_exposure |", fe5)),
                 with_exposure(Exposure, "log_own_poss"), vcov = vc5),
  "(6)" = fepois(as.formula(paste("own_fouls ~", rhs5, "+ log_exposure |", fe5)),
                 with_exposure(Exposure, "log_opp_poss"), vcov = vc5),
  "(7)" = feols(as.formula(paste("suffered_per100_passes ~", rhs5, "|", fe5)), Exposure, vcov = vc5),
  "(8)" = feols(as.formula(paste("committed_per100_passes ~", rhs5, "|", fe5)), Exposure, vcov = vc5)
)

dep_mean5 <- function(m) {
  y <- model.matrix(m, type = "lhs")
  formatC(mean(y), format = "f", digits = 3)
}
rate_ratio <- function(m) {
  if (!inherits(m, "fixest") || m$method != "fepois") return("")
  sprintf("%.3f", exp(coef(m)["barca"]))
}

extra5 <- bind_rows(
  tibble(term = "Barcelona rate ratio, exp($\\hat\\beta$)", !!!map_chr(models5, rate_ratio)),
  tibble(term = "Mean of dependent variable", !!!map_chr(models5, dep_mean5)),
  tibble(term = "Estimator", "(1)" = "OLS", "(2)" = "OLS", "(3)" = "Poisson", "(4)" = "Poisson",
         "(5)" = "Poisson", "(6)" = "Poisson", "(7)" = "OLS", "(8)" = "OLS"),
  tibble(term = "League $\\times$ season, opponent, win-prob. FE",
         !!!set_names(rep("Yes", 8), names(models5)))
)

cm5 <- c(barca = "Barcelona", real_madrid = "Real Madrid",
         other_elite = "Other elite clubs", home = "Home",
         log_exposure = "log(possession share)")

tab5 <- modelsummary(
  models5, output = "latex", coef_map = cm5, gof_map = gof_customs,
  add_rows = extra5, stars = stars_customs, escape = FALSE, fmt = 3,
  title = "Fouls Normalized by Possession and Passes: Domestic Leagues \\label{tab:exposure}"
) |>
  add_header_above(c(" " = 1, rep(c("Suffered" = 1, "Committed" = 1), 4))) |>
  add_header_above(c(" " = 1, "Per 10 min. of possession" = 2,
                     "Possession as exposure" = 2, "log possession as regressor" = 2,
                     "Per 100 passes" = 2)) |>
  kable_styling(latex_options = c("hold_position", "scale_down")) |>
  footnote(general = paste0(
    "The sample is the domestic-league team-match panel, 2005/06--2025/26, restricted to ",
    "matches with possession data. Fouls suffered are fouls called on the opponent; their ",
    "exposure is the team's own possession. Fouls committed are fouls called on the team; their ",
    "exposure is the opponent's possession. Columns (1)--(2) divide fouls by nominal possession ",
    "minutes (possession share $\\\\times$ 90). Columns (3)--(4) are Poisson regressions with log ",
    "possession share as an offset, i.e., fouls are assumed proportional to possession; ",
    "coefficients are log rate ratios. Columns (5)--(6) estimate the elasticity of fouls with ",
    "respect to possession instead of imposing it. Columns (7)--(8) divide fouls by the passes ",
    "of the team in possession. All columns include league $\\\\times$ season, opponent, and ",
    "pre-match win-probability ventile fixed effects. Standard errors clustered at the ",
    "team-season level in parentheses."),
    threeparttable = TRUE, escape = FALSE, footnote_as_chunk = TRUE)

save_table(tab5, "table-five-exposure-adjusted-fouls.tex")

TableFiveCoefs <- imap(models5, \(m, k) broom::tidy(m) |> mutate(model = k)) |> list_rbind()
write_csv(TableFiveCoefs, file.path(tables_wd, "table-five-exposure-adjusted-fouls.csv"))
