################################################################################
# 95-make-all.R
# Purpose: Master script. Defines project directories, loads packages, and
#          runs the full pipeline (download -> clean -> build -> exhibits)
#          top to bottom.
# Date:    2026-10-02
################################################################################

if (!require("pacman")) install.packages("pacman")
pacman::p_load(tidyverse, data.table, httr2, jsonlite, glue, janitor, here,
               fixest, modelsummary, kableExtra, showtext, camcorder, scales,
               ggrepel, patchwork)

set.seed(20260930)

# Directories ------------------------------------------------------------------
root          <- here::here()
programs      <- file.path(root, "programs")
raw           <- file.path(root, "data", "raw")
datasets      <- file.path(root, "data", "datasets")
tables_wd     <- file.path(root, "output", "tables")
figures_wd    <- file.path(root, "output", "figures")
logs_wd       <- file.path(root, "output", "logs")
paper_tables  <- file.path(root, "my_paper", "tables")
paper_figures <- file.path(root, "my_paper", "figure")

# Fonts for figures
font_add_google("Fira Sans", "Fira Sans")
showtext_auto()
showtext_opts(dpi = 300)

# Switches: set to FALSE to reuse raw data already on disk
run_downloads <- FALSE

# Pipeline ---------------------------------------------------------------------
source(file.path(programs, "00-functions.R"))

if (run_downloads) {
  source(file.path(programs, "01-download-football-data.R"))
  # ESPN scrape (~50,000 match pages, ~45 minutes, cached and idempotent)
  system2("python3", c(file.path(programs, "02-download-espn-matches.py"),
                       "--first", "2001", "--last", "2026"))
}

source(file.path(programs, "03-clean-football-data.R"))
source(file.path(programs, "04-clean-espn.R"))
source(file.path(programs, "05-build-team-match-panel.R"))

# Exhibits
source(file.path(programs, "06-table-one-summary-statistics.R"))
source(file.path(programs, "07-figure-one-barcelona-raw-differentials.R"))
source(file.path(programs, "08-table-two-team-fixed-effects.R"))
source(file.path(programs, "09-figure-two-team-favorability-ranking.R"))
source(file.path(programs, "10-table-three-domestic-vs-champions-league.R"))
source(file.path(programs, "11-figure-three-negreira-event-study.R"))
source(file.path(programs, "12-table-four-stoppage-time.R"))
source(file.path(programs, "13-table-five-exposure-adjusted-fouls.R"))
source(file.path(programs, "14-figures-four-to-seven-elite-clubs-by-season.R"))
source(file.path(programs, "15-table-six-real-madrid-champions-league-by-season.R"))
source(file.path(programs, "16-figure-eight-tables-seven-eight-real-madrid-champions-league-gaps.R"))
