# install_packages.R
# Run once to install all required R packages.
# Alternatively use renv::restore() if an renv.lock is present.

pkgs <- c(
  "tidyverse",
  "lme4",
  "lmerTest",
  "fixest",
  "broom",
  "broom.mixed",
  "arrow",
  "ggplot2",
  "ggeffects",
  "patchwork",
  "here",
  "janitor",
  "modelsummary"
)

install.packages(pkgs, repos = "https://cloud.r-project.org")
message("All packages installed.")
