################################################################################
# 00-functions.R
# Purpose: Helper functions, labels, and the figure theme shared by all
#          scripts. Sourced by 95-make-all.R after directories are defined.
# Date:    2026-10-02
################################################################################

# League labels -----------------------------------------------------------------
league_labels <- c(
  "eng.1" = "Premier League", "esp.1" = "La Liga", "ita.1" = "Serie A",
  "ger.1" = "Bundesliga", "fra.1" = "Ligue 1", "uefa.champions" = "Champions League"
)
league_country <- c(
  "eng.1" = "England", "esp.1" = "Spain", "ita.1" = "Italy",
  "ger.1" = "Germany", "fra.1" = "France"
)

# Season label from start year (2008 -> "2008/09")
season_label <- function(y) sprintf("%d/%02d", y, (y + 1) %% 100)

# Benchmark clubs (ESPN team ids). These are the perennial domestic champions
# and Champions League regulars used to put Barcelona in perspective.
elite_clubs <- tribble(
  ~team_id, ~club,               ~country,
  "83",     "Barcelona",         "Spain",
  "86",     "Real Madrid",       "Spain",
  "1068",   "Atletico Madrid",   "Spain",
  "132",    "Bayern Munich",     "Germany",
  "124",    "Borussia Dortmund", "Germany",
  "111",    "Juventus",          "Italy",
  "103",    "AC Milan",          "Italy",
  "110",    "Internazionale",    "Italy",
  "160",    "Paris Saint-Germain","France",
  "360",    "Manchester United", "England",
  "382",    "Manchester City",   "England",
  "364",    "Liverpool",         "England",
  "363",    "Chelsea",           "England",
  "359",    "Arsenal",           "England"
)

# Key regime dates ----------------------------------------------------------------
# Negreira payments: FC Barcelona's reported payments to companies linked to
# the vice-president of Spain's referees' committee (CTA) ran 2001-2018; he
# left the CTA in 2018. La Liga introduced VAR in 2018/19 -- the same season.
negreira_last_season <- 2017        # 2017/18 is the last season "in" the window
var_first_season <- c("eng.1" = 2019, "esp.1" = 2018, "ita.1" = 2017,
                      "ger.1" = 2017, "fra.1" = 2018, "uefa.champions" = 2019)

# Analysis sample ----------------------------------------------------------------
# Complete seasons only (2026/27 is in progress); Champions League qualifying
# rounds are dropped. Fouls and cards are reliably recorded from 2005/06.
analysis_last_season <- 2025
box_first_season <- 2005

load_panel <- function() {
  read_csv(file.path(datasets, "team-match-panel.csv"),
           col_types = cols(event_id = "c", team_id = "c", opp_id = "c",
                            referee = "c", ucl_stage = "c", elite_club = "c"),
           show_col_types = FALSE) |>
    filter(season_start <= analysis_last_season,
           is.na(ucl_stage) | ucl_stage != "Qualifying") |>
    mutate(
      domestic = as.integer(league != "uefa.champions"),
      other_elite = as.integer(elite == 1 & barca == 0 & real_madrid == 0),
      # Decisions are set to missing outside their reliable coverage
      across(c(own_fouls, opp_fouls, own_yellow, opp_yellow, own_red, opp_red,
               net_yellow, net_red, net_fouls, yellow_per_foul),
             \(v) if_else(season_start >= box_first_season, v, NA_real_)),
      across(c(own_pens, opp_pens, net_pens), \(v) if_else(pens_ok, v, NA_real_)),
      # Ventiles of the pre-match win probability (bookmaker odds) and of the
      # Elo expected score, used as flexible strength controls
      pwin_bin = ntile(prob_win, 20),
      elo_bin = ntile(elo_exp, 20),
      # Possession in 2.5-point bins: a flexible control for playing style
      poss_bin = cut(own_possession, c(0, seq(30, 75, 2.5), 100)),
      era = if_else(negreira_era == 1, "2001/02-2017/18", "2018/19-2025/26")
    )
}

# Outcome labels used across tables and figures
outcome_labels <- c(
  own_yellow = "Yellow cards received",
  opp_yellow = "Yellow cards to opponent",
  own_red    = "Red cards received",
  opp_red    = "Red cards to opponent",
  own_fouls  = "Fouls called against",
  opp_fouls  = "Fouls called for",
  own_pens   = "Penalties awarded",
  opp_pens   = "Penalties conceded",
  net_yellow = "Net yellow cards (opp. - own)",
  net_red    = "Net red cards (opp. - own)",
  net_fouls  = "Net fouls (opp. - own)",
  net_pens   = "Net penalties (for - against)",
  yellow_per_foul = "Yellow cards per foul"
)

# Figure theme ------------------------------------------------------------------
theme_customs <- function(base_size = 12) {
  theme_minimal(base_size = base_size, base_family = "Fira Sans") +
    theme(
      plot.title = element_text(face = "bold", size = rel(1.15)),
      plot.subtitle = element_text(colour = "grey30"),
      plot.caption = element_text(colour = "grey40", hjust = 0, size = rel(0.75)),
      axis.title = element_text(face = "bold"),
      legend.position = "bottom",
      panel.grid.minor = element_blank(),
      strip.text = element_text(face = "bold")
    )
}

# Validated with the dataviz palette checker (all-pairs CVD and contrast on a
# light surface): Barcelona, Real Madrid, other elite clubs
colors_customs <- c(barca = "#A50044", madrid = "#B8860B", elite = "#2a78d6",
                    other = "grey70", accent = "#EDBB00")

# Table helpers -----------------------------------------------------------------
# modelsummary >= 2.0 builds LaTeX with tinytable by default; use kableExtra so
# tables can be piped to kable_styling() and footnote(threeparttable = TRUE)
options(modelsummary_factory_latex = "kableExtra",
        modelsummary_format_numeric_latex = "plain")
stars_customs <- c("***" = 0.01, "**" = 0.05, "*" = 0.1)
gof_customs <- list(list(raw = "nobs", clean = "Observations",
                         fmt = \(x) formatC(x, format = "d", big.mark = ",")))

# Save a modelsummary/kableExtra table to output/tables and my_paper/tables
save_table <- function(tab, file) {
  for (d in c(tables_wd, paper_tables)) {
    kableExtra::save_kable(tab, file.path(d, file))
  }
  invisible(tab)
}

save_figure <- function(plot, file, width = 8, height = 5) {
  for (d in c(figures_wd, paper_figures)) {
    ggsave(file.path(d, file), plot, width = width, height = height,
           device = cairo_pdf)
    ggsave(file.path(d, sub("\\.pdf$", ".png", file)), plot, width = width,
           height = height, dpi = 300, bg = "white")
  }
  invisible(plot)
}
