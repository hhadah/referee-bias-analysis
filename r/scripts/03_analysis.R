# 03_analysis.R
# Main regression analysis: do some teams receive systematically more
# favorable referee decisions after controlling for match context?
#
# Models
# ------
# M1  Logistic regression (glm)        – baseline, no random effects
# M2  Mixed-effects logistic (lme4)    – random intercepts for team, referee
# M3  Two-way fixed-effects (fixest)   – team FE + referee FE (high-dimensional)
# M4  VAR-aware model                  – interaction with var_involved
#
# The outcome is decision_for_team (1 = decision favoured the team).
# Controls: home_away, score_state, match_phase, decision_type, competition,
#           season, referee_matches_before.

library(here)
library(tidyverse)
library(lme4)
library(lmerTest)
library(fixest)
library(broom)
library(broom.mixed)
library(modelsummary)

source(here("r", "scripts", "01_load_data.R"))

FIGURES_DIR <- here("r", "figures")
dir.create(FIGURES_DIR, showWarnings = FALSE, recursive = TRUE)

# ---------------------------------------------------------------------------
# Modelling data – filter to decisions with enough context information
# ---------------------------------------------------------------------------

model_data <- decisions |>
  filter(
    !is.na(decision_for_team),
    !is.na(home_away),
    !is.na(score_state),
    !is.na(match_phase),
    !is.na(decision_type)
  ) |>
  mutate(
    y          = as.integer(decision_for_team),
    team       = droplevels(team),
    referee    = droplevels(referee),
    competition = droplevels(competition)
  )

message("Model data: ", nrow(model_data), " decisions, ",
        nlevels(model_data$team), " teams, ",
        nlevels(model_data$referee), " referees.")

# ---------------------------------------------------------------------------
# M1: Baseline logistic regression
# ---------------------------------------------------------------------------

message("Fitting M1: baseline logistic regression...")
m1 <- glm(
  y ~ team + home_away + score_state + match_phase +
    decision_type + competition + season,
  data   = model_data,
  family = binomial(link = "logit")
)

# ---------------------------------------------------------------------------
# M2: Mixed-effects logistic regression (team + referee random intercepts)
# ---------------------------------------------------------------------------

message("Fitting M2: mixed-effects logistic regression...")
m2 <- lme4::glmer(
  y ~ home_away + score_state + match_phase + decision_type +
    competition + season + referee_matches_before +
    (1 | team) + (1 | referee),
  data    = model_data,
  family  = binomial(link = "logit"),
  control = lme4::glmerControl(optimizer = "bobyqa", optCtrl = list(maxfun = 2e5))
)

# ---------------------------------------------------------------------------
# M3: Two-way fixed-effects (team FE + referee FE)
# ---------------------------------------------------------------------------

message("Fitting M3: high-dimensional fixed-effects logistic regression...")
m3 <- fixest::feglm(
  y ~ home_away + score_state + match_phase + decision_type + season |
    team + referee,
  data   = model_data,
  family = "logit"
)

# ---------------------------------------------------------------------------
# M4: VAR-aware interaction model (add var_involved × team interaction)
# ---------------------------------------------------------------------------

message("Fitting M4: VAR-aware model...")
m4 <- fixest::feglm(
  y ~ home_away + score_state + match_phase + decision_type + season +
    var_involved + var_involved:home_away |
    team + referee,
  data   = model_data,
  family = "logit"
)

# ---------------------------------------------------------------------------
# Model summary table
# ---------------------------------------------------------------------------

modelsummary(
  list(
    "M1 Logit"   = m1,
    "M2 Mixed"   = m2,
    "M3 FE"      = m3,
    "M4 FE+VAR"  = m4
  ),
  output   = file.path(FIGURES_DIR, "model_summary.txt"),
  stars    = TRUE,
  statistic = "({std.error})"
)
message("Saved: model_summary.txt")

# ---------------------------------------------------------------------------
# Extract team random effects from M2 (bias ranking)
# ---------------------------------------------------------------------------

team_re <- ranef(m2)$team |>
  as_tibble(rownames = "team") |>
  rename(re_intercept = `(Intercept)`) |>
  arrange(desc(re_intercept))

readr::write_csv(team_re, file.path(FIGURES_DIR, "team_random_effects.csv"))
message("Saved: team_random_effects.csv")

# ---------------------------------------------------------------------------
# Plot team random effects (top/bottom 20)
# ---------------------------------------------------------------------------

library(ggplot2)

p_re <- team_re |>
  slice(c(1:20, (nrow(team_re) - 19):nrow(team_re))) |>
  mutate(team = reorder(team, re_intercept)) |>
  ggplot(aes(x = re_intercept, y = team,
             colour = re_intercept > 0)) +
  geom_point(size = 2.5) +
  geom_vline(xintercept = 0, linetype = "dashed", colour = "grey50") +
  scale_colour_manual(values = c("TRUE" = "#2166ac", "FALSE" = "#d1495b"),
                      guide = "none") +
  labs(
    title    = "Team-Level Random Effects (M2)",
    subtitle = "Positive = more favorable decisions than average",
    x        = "Random intercept (log-odds)",
    y        = NULL
  ) +
  theme_minimal(base_size = 11)

ggsave(
  file.path(FIGURES_DIR, "team_random_effects.pdf"),
  p_re, width = 9, height = 7
)
message("Saved: team_random_effects.pdf")

message("Analysis complete.")
