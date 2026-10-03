#!/usr/bin/env Rscript

# Validate consumer-visible data and inference invariants after the analysis.
# Results -> output/tables/analysis-verification.csv and artifact-manifest.csv
# Does not modify raw data, estimates, or figures. Run last in 95-make-all.R.

av_checks <- list()
av_assert <- function(condition, check, detail) {
  if (!isTRUE(condition)) stop(sprintf("FAIL: %s: %s", check, detail),
                               call. = FALSE)
  av_checks[[length(av_checks) + 1L]] <<- data.frame(
    check = check, passed = TRUE, detail = detail, run_id = run_id,
    stringsAsFactors = FALSE)
}
av_p <- data.table::fread(file.path(datasets, "team-match-panel.csv"))
av_m <- data.table::fread(file.path(datasets, "matches.csv"))
av_assert(!anyDuplicated(av_p[, .(event_id, team_id)]),
  "Unique team-match keys", "No duplicate team perspective enters a model.")
av_pairs <- av_p[, .(n = .N, teams = uniqueN(team_id),
  yellow_sum = sum(net_yellow), red_sum = sum(net_red),
  foul_sum = sum(net_fouls), penalty_sum = sum(net_pens)), by = event_id]
av_assert(all(av_pairs$n == 2L & av_pairs$teams == 2L),
  "Two distinct teams per match", sprintf("%d match pairs", nrow(av_pairs)))
av_assert(all(unlist(av_pairs[, .(yellow_sum, red_sum, foul_sum,
  penalty_sum)]) == 0, na.rm = TRUE), "Mirrored net outcomes",
  "Opponent-minus-own outcomes sum to zero within every observed match.")
av_assert(all(is.na(av_p$own_possession) == is.na(av_p$opp_possession)) &&
  all(av_p$own_possession > 0 & av_p$own_possession < 100 &
    abs(av_p$own_possession + av_p$opp_possession - 100) <= 1, na.rm = TRUE),
  "Valid possession pairs", "Both shares are observed and valid, or both missing.")
av_assert(!any(grepl("ABANDONED|SCHEDULED", av_m$match_status)),
  "Completed fixtures only", "Abandoned and scheduled fixtures excluded.")
av_assert(all(av_m$pens_ok == (av_m$event_log_has_end & av_m$goals_ok)),
  "Penalty sample independent of penalty rate",
  "Eligibility uses an end marker and goal reconciliation, not outcome frequency.")
av_assert(all(av_m$home_goals_ev[av_m$goals_ok] ==
                av_m$home_score[av_m$goals_ok]) &&
          all(av_m$away_goals_ev[av_m$goals_ok] ==
                av_m$away_score[av_m$goals_ok]),
  "Goal totals reconcile", "Extra-time goals count in final-score validation.")
av_et <- av_m[extra_time & goals_ok]
av_assert(nrow(av_et) > 0L && all(av_et$margin_90_home ==
  av_et$home_goals_regulation - av_et$home_goals_stoppage -
  av_et$away_goals_regulation + av_et$away_goals_stoppage),
  "Regulation score excludes extra time",
  sprintf("%d reconciled extra-time matches", nrow(av_et)))
av_files <- list.files(tables_wd, pattern =
  "^(barcelona-style|rm-ucl-pooled-precision|card-timing).*\\.csv$", full.names = TRUE)
for (av_file in av_files) {
  av_d <- data.table::fread(av_file)
  av_lo <- intersect(c("conf_low", "ci_low", "ci95_low"), names(av_d))
  av_hi <- intersect(c("conf_high", "ci_high", "ci95_high"), names(av_d))
  if ("estimate" %in% names(av_d) && length(av_lo) == 1L &&
      length(av_hi) == 1L) {
    av_obs <- is.finite(av_d$estimate)
    av_assert(all(av_d[[av_lo]][av_obs] <= av_d$estimate[av_obs] &
                  av_d[[av_hi]][av_obs] >= av_d$estimate[av_obs]),
      paste("Ordered intervals:", basename(av_file)),
      sprintf("%d estimated contrasts", sum(av_obs)))
  }
}
av_b <- data.table::fread(file.path(tables_wd, "barcelona-style-ladder.csv"))
av_r <- data.table::fread(file.path(tables_wd,
                                  "rm-ucl-pooled-precision-estimates.csv"))
av_assert(all(av_b[, uniqueN(n_obs), by = outcome]$V1 == 1L) &&
  all(av_r[sample == "common", uniqueN(n_rows), by = outcome]$V1 == 1L),
  "Common samples across ladders",
  "Changing controls does not change estimation rows within an outcome.")
av_nonelite <- av_r[sample == "common" & contrast == "rm_vs_nonelite"]
av_power <- mapply(function(mde, se, df) {
  critical <- qt(0.975, df)
  pt(-critical, df, ncp = mde / se) +
    pt(critical, df, ncp = mde / se, lower.tail = FALSE)
}, av_nonelite$mde_per_match, av_nonelite$se, av_nonelite$df)
av_assert(all(abs(av_power - 0.8) < 0.002),
  "Detectable-effect calibration",
  "Reported MDE attains 80 percent two-sided power under the stated t approximation.")
av_assert(isTRUE(all.equal(av_r$ci95_low_per10, 10 * av_r$ci95_low,
                           tolerance = 1e-12)) &&
          isTRUE(all.equal(av_r$ci95_high_per10, 10 * av_r$ci95_high,
                           tolerance = 1e-12)),
  "Units reconcile", "Per-ten-match intervals scale both endpoints consistently.")
av_table <- data.table::rbindlist(av_checks)
data.table::fwrite(av_table, file.path(tables_wd, "analysis-verification.csv"))
haven::write_dta(as.data.frame(av_table),
                 file.path(tables_wd, "analysis-verification.dta"))
av_artifacts <- c(list.files(tables_wd,
  pattern = "^(barcelona-style|rm-ucl-pooled-precision|card-timing|data-audit|analysis-).*\\.(csv|dta)$",
  full.names = TRUE), list.files(figures_wd,
  pattern = "^(figure-barcelona-style|figure-rm-ucl|card-timing).*\\.(pdf|png)$",
  full.names = TRUE), file.path(root, "output", "analysis-report.html"))
av_manifest <- data.frame(path = substring(av_artifacts, nchar(root) + 2L),
  md5 = unname(tools::md5sum(av_artifacts)), run_id = run_id,
  stringsAsFactors = FALSE)
if (anyNA(av_manifest$md5)) stop("Missing generated artifact.", call. = FALSE)
data.table::fwrite(av_manifest, file.path(tables_wd, "artifact-manifest.csv"))
cat(sprintf("PASS: %d data/inference invariants; %d artifact hashes.\n",
            nrow(av_table), nrow(av_manifest)))
