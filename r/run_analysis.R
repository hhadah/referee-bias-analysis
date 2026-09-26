# run_analysis.R
# Entry-point script – runs the full R analysis pipeline in order.
#
# Usage (from repository root):
#   Rscript r/run_analysis.R
#
# Prerequisites:
#   - Processed data in data/processed/ (run Python pipeline first)
#   - R packages installed (Rscript r/scripts/install_packages.R)

library(here)

message("=== Referee Bias Analysis: R pipeline ===")
message("Working directory: ", here())

scripts <- here("r", "scripts", c("01_load_data.R", "02_eda.R", "03_analysis.R"))

for (s in scripts) {
  message("\n--- Running: ", basename(s), " ---")
  source(s)
}

message("\n=== Pipeline complete ===")
