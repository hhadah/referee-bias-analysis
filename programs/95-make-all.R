#!/usr/bin/env Rscript

# Rebuild the cached-source data and current refereeing analysis. Downloads
# require --download; superseded exploratory exhibits require --legacy.
# Results -> data/datasets/, output/tables/, output/figures/, my_paper/
# Raw downloads are never modified by the cleaning or estimation scripts.

args <- commandArgs(trailingOnly = TRUE)
allowed <- c("--download", "--legacy", "--analysis-only")
if (any(!args %in% allowed)) stop("Unknown runner option.", call. = FALSE)
root <- normalizePath(Sys.getenv("REFEREE_BIAS_ROOT", unset = getwd()),
                      mustWork = TRUE)
programs <- file.path(root, "programs")
raw <- file.path(root, "data", "raw")
datasets <- file.path(root, "data", "datasets")
tables_wd <- file.path(root, "output", "tables")
figures_wd <- file.path(root, "output", "figures")
logs_wd <- file.path(root, "output", "logs")
paper_tables <- file.path(root, "my_paper", "tables")
paper_figures <- file.path(root, "my_paper", "figure")
for (d in c(datasets, tables_wd, figures_wd, logs_wd,
            paper_tables, paper_figures)) {
  dir.create(d, recursive = TRUE, showWarnings = FALSE)
}
run_id <- format(Sys.time(), "%Y%m%d-%H%M%S")
sink(file.path(logs_wd, paste0("analysis-", run_id, ".log")), split = TRUE)
cat(sprintf("Run %s\nRoot %s\n", run_id, root))

# Keep the legacy cleaner's packages; install nothing during an analysis run.
packages <- c("tidyverse", "data.table", "jsonlite", "fixest", "haven",
              "patchwork", "scales")
if ("--legacy" %in% args) {
  packages <- c(packages, "modelsummary", "kableExtra", "ggrepel", "glue")
}
if ("--download" %in% args) packages <- c(packages, "httr2")
for (p in packages) {
  if (!requireNamespace(p, quietly = TRUE)) {
    stop(sprintf("Required R package is missing: %s", p), call. = FALSE)
  }
  suppressPackageStartupMessages(library(p, character.only = TRUE))
  cat(sprintf("%-20s %s\n", p, as.character(packageVersion(p))))
}
set.seed(20261003)
fixest::setFixest_nthreads(1)
source(file.path(programs, "00-functions.R"))

if ("--download" %in% args) {
  source(file.path(programs, "01-download-football-data.R"))
  status <- system2("python3", c(
    shQuote(file.path(programs, "02-download-espn-matches.py")),
    "--first", "2001", "--last", "2026",
    "--root", shQuote(file.path(raw, "espn"))))
  if (status != 0L) stop("ESPN download failed.", call. = FALSE)
}

scripts <- character()
if (!"--analysis-only" %in% args) {
  scripts <- c("03-clean-football-data.R", "04-clean-espn.R",
               "05-build-team-match-panel.R")
}
# October 2026 decision: old ranks, title-season scans and final-whistle
# regressions remain reproducible, but are not the current evidence report.
if ("--legacy" %in% args) {
  scripts <- c(scripts, sort(list.files(programs,
    pattern = "^(0[6-9]|1[0-6])-.*\\.R$")))
}
scripts <- c(scripts, "17-barcelona-style-adjusted-decisions.R",
  "18-champions-league-pooled-precision.R", "19-card-timing-diagnostics.R",
  "20-build-analysis-report.R", "94-verify-analysis.R")
for (script in scripts) {
  cat(sprintf("\nRUN %s\n", script))
  started <- Sys.time()
  source(file.path(programs, script))
  cat(sprintf("OK  %s [%.1f seconds]\n", script,
    as.numeric(difftime(Sys.time(), started, units = "secs"))))
}
writeLines(capture.output(sessionInfo()),
           file.path(logs_wd, paste0("session-", run_id, ".txt")))
cat(sprintf("\nPASS: completed %d scripts, run %s\n", length(scripts), run_id))
sink()
