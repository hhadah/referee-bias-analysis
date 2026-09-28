# 02_eda.R
# Exploratory data analysis of referee decisions.
# Produces summary tables and basic charts saved to r/figures/.

library(here)
library(tidyverse)
library(patchwork)

source(here("r", "scripts", "01_load_data.R"))

FIGURES_DIR <- here("r", "figures")
dir.create(FIGURES_DIR, showWarnings = FALSE, recursive = TRUE)

# ---------------------------------------------------------------------------
# 1. Decision counts by team
# ---------------------------------------------------------------------------

decisions_by_team <- decisions |>
  count(team, decision_for_team, name = "n_decisions") |>
  mutate(direction = if_else(decision_for_team, "For team", "Against team"))

p_decisions_team <- decisions_by_team |>
  group_by(team) |>
  mutate(total = sum(n_decisions)) |>
  slice_max(total, n = 30, with_ties = FALSE) |>
  ggplot(aes(x = reorder(team, total), y = n_decisions, fill = direction)) +
  geom_col(position = "stack") +
  coord_flip() +
  scale_fill_manual(values = c("For team" = "#2166ac", "Against team" = "#d1495b")) +
  labs(
    title    = "Referee Decisions by Team (top 30)",
    subtitle = "Stacked by direction of decision",
    x        = NULL,
    y        = "Number of decisions",
    fill     = NULL
  ) +
  theme_minimal(base_size = 11) +
  theme(legend.position = "bottom")

ggsave(
  file.path(FIGURES_DIR, "decisions_by_team.pdf"),
  p_decisions_team, width = 10, height = 8
)
message("Saved: decisions_by_team.pdf")

# ---------------------------------------------------------------------------
# 2. Favorable decision rate by team
# ---------------------------------------------------------------------------

fav_rate_by_team <- decisions |>
  group_by(team, competition) |>
  summarise(
    n_decisions   = n(),
    n_favorable   = sum(decision_for_team, na.rm = TRUE),
    fav_rate      = n_favorable / n_decisions,
    .groups       = "drop"
  ) |>
  filter(n_decisions >= 20)

p_fav_rate <- fav_rate_by_team |>
  slice_max(n_decisions, n = 30, with_ties = FALSE) |>
  ggplot(aes(x = reorder(team, fav_rate), y = fav_rate, colour = competition)) +
  geom_point(size = 2.5) +
  geom_hline(yintercept = mean(fav_rate_by_team$fav_rate), linetype = "dashed", colour = "grey40") +
  coord_flip() +
  scale_y_continuous(labels = scales::percent_format()) +
  labs(
    title    = "Favorable Decision Rate by Team",
    subtitle = "Dashed line = overall mean; min 20 decisions",
    x        = NULL,
    y        = "Favorable decision rate",
    colour   = "Competition"
  ) +
  theme_minimal(base_size = 11) +
  theme(legend.position = "bottom")

ggsave(
  file.path(FIGURES_DIR, "favorable_rate_by_team.pdf"),
  p_fav_rate, width = 10, height = 8
)
message("Saved: favorable_rate_by_team.pdf")

# ---------------------------------------------------------------------------
# 3. Decision timing histogram
# ---------------------------------------------------------------------------

p_timing <- decisions |>
  filter(!is.na(minute)) |>
  ggplot(aes(x = minute, fill = decision_for_team)) +
  geom_histogram(binwidth = 5, position = "identity", alpha = 0.6) +
  scale_fill_manual(values = c("TRUE" = "#2166ac", "FALSE" = "#d1495b"),
                    labels = c("Against", "For")) +
  labs(
    title = "Decision Timing Distribution",
    x     = "Match minute",
    y     = "Count",
    fill  = "Decision direction"
  ) +
  theme_minimal(base_size = 11)

ggsave(
  file.path(FIGURES_DIR, "decision_timing.pdf"),
  p_timing, width = 10, height = 5
)
message("Saved: decision_timing.pdf")

# ---------------------------------------------------------------------------
# 4. VAR involvement by competition
# ---------------------------------------------------------------------------

var_summary <- decisions |>
  group_by(competition) |>
  summarise(
    n_total    = n(),
    n_var      = sum(var_involved, na.rm = TRUE),
    var_rate   = n_var / n_total,
    .groups    = "drop"
  )

print(var_summary)

message("EDA complete. Figures saved to: ", FIGURES_DIR)
