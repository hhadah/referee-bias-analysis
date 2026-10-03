################################################################################
# 10-table-three-domestic-vs-champions-league.R
# Purpose: Table 3 -- within-club comparison of refereeing decisions in the
#          domestic league (Spanish referees for Spanish clubs) versus the
#          Champions League (UEFA-appointed referees, never from the clubs'
#          own federation), by period (equation 3):
#            y_im = b_pre  Barca x Domestic x Pre
#                 + b_post Barca x Domestic x Post
#                 + (same for Real Madrid)
#                 + team x period FE + home-league x domestic x period FE
#                 + competition x season FE + Elo-ventile FE + home + e
#          Sample: clubs from the top-5 leagues with 40+ Champions League
#          matches (Champions League regulars), all of their domestic and
#          Champions League (group/league phase and knockout) matches.
# Input:   data/datasets/team-match-panel.csv
# Output:  output/tables/table-three-domestic-vs-champions-league.tex
# Date:    2026-10-02
################################################################################

Panel <- load_panel()

ucl_regulars <- Panel |>
  filter(domestic == 0, !is.na(home_league)) |>
  count(team_id) |>
  filter(n >= 40) |>
  pull(team_id)

Regulars <- Panel |>
  filter(team_id %in% ucl_regulars) |>
  mutate(post = 1L - negreira_era,
         barca_dom_pre   = barca * domestic * negreira_era,
         barca_dom_post  = barca * domestic * post,
         madrid_dom_pre  = real_madrid * domestic * negreira_era,
         madrid_dom_post = real_madrid * domestic * post,
         team_era = paste(team_id, era),
         league_dom_era = paste(home_league, domestic, era),
         comp_season = paste(domestic, season_start))

message("Champions League regulars: ", length(ucl_regulars), " clubs; ",
        nrow(Regulars), " team-matches")

outcomes3 <- c("own_yellow", "opp_yellow", "own_fouls", "opp_fouls", "own_pens", "opp_pens")

fit3 <- function(y, style) {
  fe <- paste("team_era + league_dom_era + comp_season + elo_bin",
              if (style) "+ poss_bin" else "")
  feols(as.formula(paste(y, "~ barca_dom_pre + barca_dom_post + madrid_dom_pre +",
                         "madrid_dom_post + home |", fe)),
        data = Regulars, vcov = ~team_season)
}
col_names3 <- paste0("(", seq_along(outcomes3), ")")
models3a <- map(outcomes3, fit3, style = FALSE) |> set_names(col_names3)
models3b <- map(outcomes3, fit3, style = TRUE) |> set_names(col_names3)

# Triple difference: change in Barcelona's domestic-vs-UCL gap after 2017/18
diff_row <- function(m, a, b) {
  bb <- coef(m); V <- vcov(m)
  d <- bb[b] - bb[a]
  se <- sqrt(V[a, a] + V[b, b] - 2 * V[a, b])
  p <- 2 * pnorm(-abs(d / se))
  st <- if (p < 0.01) "***" else if (p < 0.05) "**" else if (p < 0.1) "*" else ""
  c(sprintf("%.3f%s", d, st), sprintf("(%.3f)", se))
}
yes3 <- set_names(rep("Yes", length(outcomes3)), col_names3)

extra3 <- bind_rows(
  tibble(term = c("Barcelona: post $-$ pre (A)", ""),
         !!!map(models3a, diff_row, a = "barca_dom_pre", b = "barca_dom_post")),
  tibble(term = c("Barcelona: post $-$ pre (B)", ""),
         !!!map(models3b, diff_row, a = "barca_dom_pre", b = "barca_dom_post")),
  tibble(term = c("Real Madrid: post $-$ pre (A)", ""),
         !!!map(models3a, diff_row, a = "madrid_dom_pre", b = "madrid_dom_post")),
  tibble(term = c("Real Madrid: post $-$ pre (B)", ""),
         !!!map(models3b, diff_row, a = "madrid_dom_pre", b = "madrid_dom_post")),
  tibble(term = "Mean of dependent variable",
         !!!map_chr(models3a, \(m) formatC(mean(fitted(m) + resid(m)), format = "f", digits = 3))),
  tibble(term = "Club $\\times$ period FE", !!!yes3),
  tibble(term = "League $\\times$ domestic $\\times$ period FE", !!!yes3),
  tibble(term = "Competition $\\times$ season FE", !!!yes3),
  tibble(term = "Elo expected-score ventile FE", !!!yes3),
  tibble(term = "Possession-bin FE (Panel B)", !!!yes3)
)

cm3 <- c(barca_dom_pre = "Barcelona $\\times$ Domestic $\\times$ 2001/02--2017/18",
         barca_dom_post = "Barcelona $\\times$ Domestic $\\times$ 2018/19--2025/26",
         madrid_dom_pre = "Real Madrid $\\times$ Domestic $\\times$ 2001/02--2017/18",
         madrid_dom_post = "Real Madrid $\\times$ Domestic $\\times$ 2018/19--2025/26",
         home = "Home")

panels3 <- list("Panel A: Pre-match controls" = models3a,
                "Panel B: Adding possession-bin fixed effects" = models3b)

tab3 <- modelsummary(
  panels3, shape = "rbind", output = "latex", coef_map = cm3, gof_map = gof_customs,
  add_rows = extra3, stars = stars_customs, escape = FALSE, fmt = 3,
  title = "Domestic League versus Champions League Refereeing: Champions League Regulars \\label{tab:ddd}"
) |>
  add_header_above(c(" " = 1, "Against" = 1, "For" = 1, "Against" = 1, "For" = 1,
                     "Awarded" = 1, "Conceded" = 1)) |>
  add_header_above(c(" " = 1, "Yellow cards" = 2, "Fouls" = 2, "Penalties" = 2)) |>
  kable_styling(latex_options = c("hold_position", "scale_down")) |>
  footnote(general = paste0(
    "This table includes the estimation results of equation (\\\\ref{eq:ddd}). The sample contains all ",
    "domestic-league and Champions League (group/league phase and knockout) matches of the ",
    length(ucl_regulars), " clubs from the top-5 leagues with at least 40 Champions League matches. ",
    "Each coefficient is the club's domestic-league decision gap relative to its own Champions ",
    "League decisions, net of the same gap for the other Champions League regulars from its ",
    "league. The rows ``post $-$ pre'' report the change in that gap after 2017/18, the last ",
    "season of the reported Negreira payments and the season before VAR entered La Liga. ",
    "Panel B adds fixed effects for 2.5-point possession bins to absorb differences in playing ",
    "style between the two competitions. Cards and fouls cover 2005/06--2025/26; penalties cover ",
    "2001/02--2025/26 (Panel B: seasons with possession data). Standard errors ",
    "clustered at the team-season level in parentheses."),
    threeparttable = TRUE, escape = FALSE, footnote_as_chunk = TRUE)

save_table(tab3, "table-three-domestic-vs-champions-league.tex")

TableThreeCoefs <- imap(list(A = models3a, B = models3b), \(ms, panel)
  imap(ms, \(m, k) broom::tidy(m) |>
         mutate(outcome = outcomes3[match(k, col_names3)], panel = panel)) |>
    list_rbind()
) |> list_rbind()
write_csv(TableThreeCoefs, file.path(tables_wd, "table-three-domestic-vs-champions-league.csv"))
