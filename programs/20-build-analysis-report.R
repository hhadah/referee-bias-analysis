#!/usr/bin/env Rscript

# Build an audit supplement from the analysis manifests, leaving the original
# manuscript and findings memo untouched. Run after 17-19, before 94.
# Results -> output/analysis-report.html, notes/findings-memo-possession-adjusted.md,
#            output/tables/analysis-headlines.csv/.dta, data-audit-*.csv/.dta,
#            my_paper/analysis-update.tex and fragments/analysis-update-*.tex
# Raw data and the author's original paper prose are never modified.

ar_read <- function(name) data.table::fread(file.path(tables_wd, name))
ar_b <- ar_read("barcelona-style-ladder.csv")
ar_o <- ar_read("barcelona-style-overlap.csv")
ar_e <- ar_read("barcelona-style-exposure.csv")
ar_era <- ar_read("barcelona-style-era.csv")
ar_r <- ar_read("rm-ucl-pooled-precision-estimates.csv")
ar_loso <- ar_read("rm-ucl-pooled-precision-loso.csv")
ar_cum <- ar_read("rm-ucl-pooled-precision-cumulative.csv")
ar_t <- ar_read("card-timing-results.csv")
ar_m <- data.table::fread(file.path(datasets, "matches.csv"))
ar_p <- data.table::as.data.table(load_panel())
ar_sample <- ar_m[season_start <= analysis_last_season &
  (is.na(ucl_stage) | ucl_stage != "Qualifying")]
ar_sample[, score_disagreement := !is.na(home_goals_fd) &
  !is.na(away_goals_fd) &
  (home_score != home_goals_fd | away_score != away_goals_fd)]
ar_score_audit <- ar_sample[score_disagreement == TRUE,
  .(event_id, league, season_start, home_name, away_name,
    home_score_espn = home_score, away_score_espn = away_score,
    home_score_fd = home_goals_fd, away_score_fd = away_goals_fd,
    possession_valid, goals_ok, run_id = run_id)]
data.table::fwrite(ar_score_audit,
  file.path(tables_wd, "data-audit-score-disagreements.csv"))
haven::write_dta(as.data.frame(ar_score_audit),
  file.path(tables_wd, "data-audit-score-disagreements.dta"))
ar_coverage <- ar_sample[, .(matches = .N,
  invalid_possession_masked = sum(possession_source_invalid),
  matches_with_possession = sum(possession_valid),
  penalty_eligible = sum(pens_ok),
  eligible_below_old_rate_screen = sum(pens_ok & pens_rate_ls < 0.15),
  score_disagreements = sum(score_disagreement),
  goal_timeline_mismatch = sum(!goals_ok)), by = .(league, season_start)]
ar_fd <- data.table::fread(file.path(datasets, "football-data-matches.csv"))
ar_fd <- ar_fd[season_start >= 2001 & season_start <= analysis_last_season,
  .(football_data_fixtures = .N), by = .(league, season_start)]
ar_coverage <- merge(ar_coverage, ar_fd,
  by = c("league", "season_start"), all.x = TRUE)
ar_coverage[, missing_vs_football_data := football_data_fixtures - matches]
ar_coverage[, `:=`(run_id = run_id,
  input_md5 = unname(tools::md5sum(file.path(datasets, "matches.csv"))))]
data.table::fwrite(ar_coverage,
  file.path(tables_wd, "data-audit-coverage.csv"))
haven::write_dta(as.data.frame(ar_coverage),
  file.path(tables_wd, "data-audit-coverage.dta"))

ar_bmain <- ar_b[rung == "L3" & contrast == "barca_minus_madrid"]
ar_rmain <- ar_r[spec == "style" & sample == "common" &
                   contrast == "rm_vs_other_elite"]
ar_head <- data.table::rbindlist(list(
  ar_bmain[, .(target = "Barcelona", comparator = "Real Madrid",
    outcome, estimate_per10 = 10 * estimate_signed,
    ci_low_per10 = 10 * ci_low_signed, ci_high_per10 = 10 * ci_high_signed,
    p_value, n_target_matches = n_barca, n_seasons,
    specification = "L3: same-match style alternative")],
  ar_rmain[, .(target = "Real Madrid", comparator = "Other elite UCL clubs",
    outcome, estimate_per10, ci_low_per10 = ci95_low_per10,
    ci_high_per10 = ci95_high_per10, p_value,
    n_target_matches = n_rm_matches, n_seasons = n_rm_seasons,
    specification = "Style: possession and both teams' shots")]))
# Family covers all six Barcelona L3 endpoints versus Madrid and all five
# pooled Madrid style endpoints versus elite peers, regardless of sign.
ar_head[, `:=`(p_holm_family11 = p.adjust(p_value, "holm"), run_id = run_id,
  input_md5 = unname(tools::md5sum(file.path(datasets, "team-match-panel.csv"))))]
data.table::fwrite(ar_head, file.path(tables_wd, "analysis-headlines.csv"))
haven::write_dta(as.data.frame(ar_head),
  file.path(tables_wd, "analysis-headlines.dta"))

ar_labels <- c(own_yellow = "Fewer yellow cards received",
  opp_yellow = "More opponent yellow cards", net_yellow = "Net yellow cards",
  net_fouls = "Net fouls", net_pens = "Net penalties", net_red = "Net red cards",
  net_yellow_fouls = "Net yellow cards, given called fouls")
ar_fmt <- function(x, digits = 2) formatC(x, format = "f", digits = digits)
ar_ci <- function(est, lo, hi) sprintf("%s [%s, %s]",
  ar_fmt(est), ar_fmt(lo), ar_fmt(hi))
ar_bcell <- function(outcome_name, rung_name, contrast_name) {
  r <- ar_b[outcome == outcome_name & rung == rung_name & contrast == contrast_name]
  if (nrow(r) == 0L) return("Not applicable")
  stopifnot(nrow(r) == 1L)
  ar_ci(10 * r$estimate_signed, 10 * r$ci_low_signed, 10 * r$ci_high_signed)
}
ar_btable <- function(contrast_name) {
  data.frame(Outcome = unname(ar_labels[unique(ar_b$outcome)]),
    Raw = vapply(unique(ar_b$outcome), ar_bcell, character(1),
                 rung_name = "L0", contrast_name = contrast_name),
    Prior_style = vapply(unique(ar_b$outcome), ar_bcell, character(1),
                 rung_name = "L2", contrast_name = contrast_name),
    Same_match_style = vapply(unique(ar_b$outcome), ar_bcell, character(1),
                 rung_name = "L3", contrast_name = contrast_name),
    Given_called_fouls = vapply(unique(ar_b$outcome), ar_bcell, character(1),
                 rung_name = "L4", contrast_name = contrast_name),
    check.names = FALSE)
}
ar_bt <- ar_btable("barca_minus_madrid")
ar_bn <- ar_btable("barca")
ar_rt <- data.frame(Outcome = unname(ar_labels[ar_rmain$outcome]),
  Gap_and_95CI = ar_ci(ar_rmain$estimate_per10,
                       ar_rmain$ci95_low_per10, ar_rmain$ci95_high_per10),
  MDE_80pct = ar_fmt(ar_rmain$mde_per10),
  Madrid_matches = ar_rmain$n_rm_matches, Seasons = ar_rmain$n_rm_seasons,
  Baseline_per10 = ar_fmt(10 * ar_rmain$baseline_nonelite),
  check.names = FALSE)
ar_et <- ar_era[outcome == "net_yellow" &
  contrast %in% c("barca_minus_madrid_pre", "barca_minus_madrid_post", "gap_change"),
  .(Comparison = contrast_label,
    Gap_and_95CI = ar_ci(10 * estimate, 10 * ci_low, 10 * ci_high),
    p_value = ar_fmt(p_value, 3))]
ar_tt <- ar_t[, .(Comparison = paste(target, "vs", comparator),
  Period = ifelse(outcome == "early_net_yellow", "First 30 minutes", "Full match"),
  Gap_and_95CI = ar_ci(10 * estimate, 10 * conf_low, 10 * conf_high),
  Target_matches = n_target_matches, Seasons = n_seasons)]
ar_support <- ar_o[style_var == "lag_poss" & target == "Barcelona" &
                     reference == "Non-elite"]
ar_support_madrid <- ar_o[style_var == "lag_poss" & target == "Barcelona" &
                     reference == "Real Madrid"]
ar_exposure <- unique(ar_e[exposure_treatment == "estimated_elasticity",
  .(side, elasticity, elasticity_ci_low, elasticity_ci_high,
    p_elasticity_equals_1)])
ar_elasticity_text <- paste(vapply(seq_len(nrow(ar_exposure)), function(i) {
  x <- ar_exposure[i]
  sprintf("Fouls %s have estimated possession elasticity %s, 95%% CI [%s, %s], with p %s against proportionality of one.",
    x$side, ar_fmt(x$elasticity), ar_fmt(x$elasticity_ci_low),
    ar_fmt(x$elasticity_ci_high), if (x$p_elasticity_equals_1 < 0.001)
      "< 0.001" else paste("=", ar_fmt(x$p_elasticity_equals_1, 3)))
}, character(1)), collapse = " ")
ar_overlap_text <- sprintf(paste(
  "Barcelona's prior-match possession lies above the non-elite 95th percentile in %.1f%% of its eligible matches.",
  "Only %.1f%% lies inside Real Madrid's central 90%% range.",
  "The lagged-style models therefore depend on extrapolation, especially against non-elite clubs.",
  "L3 therefore uses same-match style instead of lagged style. It has more support but conditions on variables refereeing can change."),
  100 * ar_support$share_target_above_ref_p95,
  100 * ar_support_madrid$share_target_within_ref_p05_p95)
ar_audit_text <- sprintf(paste(
  "The rebuilt sample contains %s completed matches across the six competitions through 2025/26.",
  "%s recorded possession pairs were invalid and were masked, not rescaled.",
  "%s penalty-eligible matches would have been lost to the old low-penalty-rate rule.",
  "Finished seasons are not necessarily complete source coverage; data-audit-coverage.csv reports missing fixtures.",
  "%d matches have conflicting ESPN and football-data scores, listed in data-audit-score-disagreements.csv.",
  "No source is declared correct by this audit. The internal Elo still uses ESPN results, so score errors can affect that strength control."),
  formatC(nrow(ar_sample), big.mark = ",", format = "d"),
  formatC(sum(ar_sample$possession_source_invalid), big.mark = ",", format = "d"),
  formatC(sum(ar_sample$pens_ok & ar_sample$pens_rate_ls < 0.15),
          big.mark = ",", format = "d"), nrow(ar_score_audit))
ar_method_text <- paste(
  "Tables use effects per 10 matches; figures label their own units. Positive means more favorable to the target club.",
  "Main comparison intervals are pointwise 95% season-block clustered intervals with small-sample t critical values.",
  "The two team rows from a match are not treated as independent games.",
  "Season blocks allow arbitrary dependence within a season but assume independence across seasons.",
  "Models compare recorded decisions, not correct and incorrect calls.")
ar_limit_text <- paste(
  "Possession is a proxy for opportunities, not a count of comparable tackles or penalty-area incidents.",
  "Fouls can occur off the ball. Yellow cards include dissent and time-wasting, so cards divided by fouls are not a binomial probability.",
  "Called fouls, final possession and shots can themselves respond to earlier decisions.",
  "The cached data lack foul severity, uncalled incidents, complete box touches and independently judged decision correctness.",
  "They also lack sufficiently complete referee identities for a modern referee-fixed-effect design.",
  "A residual gap cannot establish favoritism or rule out bias in a small number of decisive incidents.")
ar_precision_text <- paste(
  "Pooling all eligible seasons estimates a persistent average gap rather than a different effect in every small season.",
  "It adds information without inventing matches or treating domestic and UEFA officials as interchangeable.",
  "The MDE is calibrated under a noncentral-t approximation at 80% power and 5% two-sided size, using the estimated clustered SE.",
  "Equivalence results use explicit illustrative bounds and 90% intervals; failure to reject zero is not equivalence.",
  "Seasonal empirical-Bayes estimates retain the full covariance of jointly estimated season coefficients.",
  "Their intervals condition on estimated between-season heterogeneity and can understate uncertainty.",
  "Unpooled estimates, heterogeneity sensitivity, and leave-one-season-out fits remain available. Shrinkage intervals are not the headline evidence.")
ar_retracted_text <- paste(
  "The earlier draft's causal language is not supported by this audit.",
  "Club ranks are descriptive, not permutation tests, because club labels are not exchangeable.",
  "The 2018 split is descriptive, not an identified effect of the reported payments.",
  "The stoppage variable measures the final-whistle clock rather than the announced minimum, and injury, substitution and time-wasting exposure is incomplete.",
  "I do not treat the earlier stoppage association as the clearest evidence of favoritism.")

ar_html_escape <- function(x) {
  x <- gsub("&", "&amp;", as.character(x), fixed = TRUE)
  x <- gsub("<", "&lt;", x, fixed = TRUE)
  gsub(">", "&gt;", x, fixed = TRUE)
}
ar_html_table <- function(d) {
  d <- as.data.frame(d)
  header <- paste(sprintf("<th>%s</th>",
    ar_html_escape(gsub("_", " ", names(d), fixed = TRUE))), collapse = "")
  rows <- vapply(seq_len(nrow(d)), function(i) paste0("<tr>",
    paste(sprintf("<td>%s</td>", ar_html_escape(unlist(d[i, ]))), collapse = ""),
    "</tr>"), character(1))
  paste0("<div class='table-scroll'><table><thead><tr>", header,
    "</tr></thead><tbody>", paste(rows, collapse = "\n"), "</tbody></table></div>")
}
ar_md_table <- function(d) {
  d <- as.data.frame(d)
  c(paste0("| ", paste(gsub("_", " ", names(d), fixed = TRUE), collapse = " | "), " |"),
    paste0("| ", paste(rep("---", ncol(d)), collapse = " | "), " |"),
    vapply(seq_len(nrow(d)), function(i)
      paste0("| ", paste(unlist(d[i, ]), collapse = " | "), " |"), character(1)))
}
ar_figs <- c("figure-barcelona-style-ladder",
  "figure-barcelona-style-possession-diagnostic", "figure-barcelona-style-robustness",
  "figure-rm-ucl-pooled-comparisons", "figure-rm-ucl-precision-limits",
  "figure-rm-ucl-season-stability", "card-timing-diagnostic")
ar_fig_titles <- c("Barcelona: raw and adjusted differences",
  "Possession and the observed decision rates", "Barcelona: eras and overlap",
  "Madrid: pooled Champions League comparisons", "Madrid: what the sample can detect",
  "Madrid: seasonal uncertainty and stability", "Early-card diagnostic")
ar_figure_html <- vapply(seq_along(ar_figs), function(i) sprintf(
  "<figure><a href='figures/%s.pdf'><img src='figures/%s.png' alt='%s'></a><figcaption>%s. Click for PDF.</figcaption></figure>",
  ar_figs[i], ar_figs[i], ar_fig_titles[i], ar_fig_titles[i]), character(1))
ar_html <- c("<!doctype html><html lang='en'><meta charset='utf-8'>",
  "<meta name='viewport' content='width=device-width,initial-scale=1'>",
  "<title>Refereeing gaps: Barcelona and Real Madrid</title>",
  "<style>body{max-width:1180px;margin:40px auto;padding:0 24px;color:#20252b;font:17px/1.55 system-ui,sans-serif}h1{line-height:1.15}h2{margin-top:2.5em}p{max-width:95ch}table{border-collapse:collapse;width:100%;font-size:14px}th,td{text-align:left;padding:10px;border-bottom:1px solid #dbe0e5;white-space:nowrap}thead{background:#f3f5f7}.table-scroll{overflow:auto}figure{margin:28px 0}img{width:100%;height:auto;border:1px solid #e0e3e7}figcaption,small{color:#535e68}.warning{border-left:4px solid #a50044;padding:12px 20px;background:#faf2f5}a{color:#175b90}</style>",
  "<h1>Refereeing gaps after accounting for playing style</h1>",
  sprintf("<small>Generated run %s. Sources: ESPN and football-data.co.uk.</small>", run_id),
  paste0("<p class='warning'>", ar_limit_text, "</p>"),
  paste0("<p>", ar_method_text, "</p>"),
  "<h2>Barcelona versus Real Madrid in La Liga</h2>",
  "<p>Each cell is a gap per 10 matches followed by its 95% interval. The ladder holds the sample fixed within each outcome; penalties have their own event-log sample.</p>",
  ar_html_table(ar_bt), paste0("<p class='warning'>", ar_overlap_text, "</p>"),
  "<h3>Barcelona versus non-elite La Liga clubs</h3>", ar_html_table(ar_bn),
  paste0("<p>", ar_elasticity_text, " Do not assume fouls are proportional to possession.</p>"),
  ar_figure_html[1:3], "<h3>Before and after 2018</h3>",
  "<p>Prior-style-adjusted net yellows. This is a descriptive era split, not a treatment-effect design.</p>",
  ar_html_table(ar_et), "<h2>Real Madrid in the Champions League</h2>",
  "<p>Style-adjusted comparisons against the other elite clubs, excluding Barcelona. Baseline_per10 is the non-elite own-side count, provided as a scale benchmark, not the comparator mean.</p>",
  ar_html_table(ar_rt), paste0("<p>", ar_precision_text, "</p>"),
  ar_figure_html[4:6], "<h2>Do differences appear early?</h2>",
  "<p>These first-30-minute and whole-match estimates use the same matches within each comparison. Both teams' card totals must reconcile to the box score. Exposure differs between the two windows, so this is a timing diagnostic, not a rate comparison.</p>",
  ar_html_table(ar_tt), ar_figure_html[7],
  "<h2>Multiplicity</h2>",
  "<p>The CSV below reports Holm-adjusted p-values across the 11 headline endpoints. Other specifications, eras and seasons are sensitivity analyses, not separate discoveries.</p>",
  ar_html_table(ar_head[, .(target, outcome, p_value = ar_fmt(p_value, 3),
    Holm_p = ar_fmt(p_holm_family11, 3))]),
  "<h2>Data and audit corrections</h2>", paste0("<p>", ar_audit_text, "</p>"),
  paste0("<p>", ar_retracted_text, "</p>"),
  "<p>Penalty eligibility now requires a regulation-end marker and goals that reconcile through extra time. That does not prove all missed penalties or penalty labels are recorded. Abandoned matches are excluded; regulation scores no longer subtract goals from a final score that includes extra time.</p>",
  "<p>Definitions: <a href='https://www.theifab.com/laws/latest/fouls-and-misconduct/'>IFAB Law 12</a>; <a href='https://www.theifab.com/laws/latest/the-duration-of-the-match/'>IFAB Law 7</a>.</p>",
  "<p><a href='tables/analysis-headlines.csv'>Headline estimates CSV</a> | <a href='tables/data-audit-coverage.csv'>Coverage audit CSV</a> | <a href='tables/artifact-manifest.csv'>Artifact hashes</a></p>",
  "</html>")
writeLines(ar_html, file.path(root, "output", "analysis-report.html"))
ar_memo <- c("# Findings memo: possession-adjusted refereeing gaps", "",
  sprintf("Generated by programs/20-build-analysis-report.R, run %s.", run_id), "",
  "## Interpretation", "", ar_method_text, "", ar_limit_text, "",
  "## Barcelona versus Real Madrid, La Liga", "", ar_md_table(ar_bt), "",
  ar_overlap_text, "", "## Barcelona versus non-elite clubs", "",
  ar_md_table(ar_bn), "", ar_elasticity_text, "",
  "## Descriptive era split", "", ar_md_table(ar_et), "",
  "## Madrid versus other elite clubs, Champions League", "",
  ar_md_table(ar_rt), "", ar_precision_text, "",
  "## Card timing", "", ar_md_table(ar_tt), "",
  "## Data corrections and withdrawn claims", "", ar_audit_text, "",
  ar_retracted_text, "",
  "## Reading the outputs", "",
  "Open `output/analysis-report.html` for all seven charts and the tables.",
  "All main estimates have CSV and DTA manifests. `analysis-headlines.csv` applies Holm correction across the 11 headline endpoints.",
  "The penalty log rule establishes eligibility, not verified correctness or complete penalty recording.",
  "Legacy programs 06-16 are exploratory and opt-in with `--legacy`; their previous prose is superseded.", "",
  "Rules: [IFAB Law 12](https://www.theifab.com/laws/latest/fouls-and-misconduct/) and [IFAB Law 7](https://www.theifab.com/laws/latest/the-duration-of-the-match/).")
writeLines(ar_memo, file.path(root, "notes", "findings-memo-possession-adjusted.md"))

# Separate audit supplement. The author's main.tex, literature review, and
# original paper fragments remain untouched.
ar_tex_escape <- function(x) {
  x <- gsub("%", "\\%", x, fixed = TRUE)
  gsub("<", "\\textless{}", x, fixed = TRUE)
}
ar_tex_rows <- vapply(seq_len(nrow(ar_head)), function(i) {
  x <- ar_head[i]
  sprintf("%s & %s & %s & %s \\\\", x$target,
    ar_labels[[x$outcome]], ar_ci(x$estimate_per10, x$ci_low_per10,
      x$ci_high_per10), ar_fmt(x$p_holm_family11, 3))
}, character(1))
ar_tex_table <- c("\\begin{table}[htbp]\\centering\\small",
  "\\caption{Style-adjusted comparisons per ten matches}\\label{tab:headlines}",
  "\\resizebox{\\textwidth}{!}{\\begin{tabular}{llrr}\\toprule",
  "Target & Outcome & Gap [95 percent CI] & Holm p \\\\", "\\midrule",
  ar_tex_rows, "\\bottomrule\\end{tabular}}",
  "\\par\\medskip\\begin{minipage}{\\textwidth}\\footnotesize",
  "Barcelona is compared with Real Madrid in La Liga; Real Madrid is compared with other elite clubs excluding Barcelona in the Champions League. Positive values favor the target, including the sign-reversed own-yellow outcome. Intervals are pointwise season-block clustered intervals. Holm p-values adjust the family of eleven displayed endpoints. These are conditional associations, not estimates of incorrect decisions.",
  "\\end{minipage}\\end{table}")
writeLines(ar_tex_table, file.path(paper_tables, "analysis-headlines.tex"))
writeLines(ar_tex_table, file.path(tables_wd, "analysis-headlines.tex"))
ar_fragments <- list(
  abstract = paste("I compare recorded refereeing decisions for Barcelona in La Liga and Real Madrid in the Champions League, accounting for strength, opponent and playing style. A common-sample specification ladder separates changes in controls from changes in sample composition. Pooled Champions League comparisons improve precision relative to annual estimates, while power calculations state what remains detectable. The evidence describes differences in decisions. Without comparable incident opportunities and independent assessments of correctness, it does not establish favoritism."),
  introduction = c("\\section{Introduction}",
    "Possession-dominant teams face different opportunities to commit and suffer fouls. Raw differences in cards and fouls therefore do not identify favorable refereeing. I compare Barcelona with Real Madrid and non-elite La Liga clubs, and Real Madrid with other Champions League participants. The analysis reports adverse, favorable and imprecise estimates rather than selecting outcomes that support a claim about either club."),
  data = c("\\section{Data}", ar_tex_escape(ar_audit_text),
    "I use the cached ESPN match summaries and football-data.co.uk league files. Penalties require a recorded regulation-end marker and goal totals that reconcile through extra time. This rule avoids selecting seasons using the number of penalties, but does not establish that every penalty event is correctly labeled. Table manifests report the outcome-specific estimation samples."),
  `empirical-strategy` = c("\\section{Empirical strategy}",
    ar_tex_escape(ar_method_text),
    "For Barcelona, L0 reports raw club indicators, L1 adds home, season, opponent and pre-match win-probability controls, and L2 adds splines in both teams' season-to-date possession and shots from strictly earlier matches. L3 instead adds same-match possession and shots to L1; L4 adds both teams' called fouls to L3 for card outcomes. The sample is held fixed across specifications within an outcome.",
    ar_tex_escape(ar_overlap_text),
    "The Champions League models hold fixed venue, season, stage, opponent, Elo expected-score bins, possession bins and both teams' shots. The other-elite comparison excludes Barcelona, which has its own indicator. No domestic referee effects are transferred into this competition.",
    ar_tex_escape(ar_precision_text),
    "The before/after-2018 comparison is descriptive. The timing also coincides with VAR and changes in squads and performance. It is not an identified treatment effect and is not presented as a causal event study."),
  results = c("\\section{Results}",
    "Table \\ref{tab:headlines} reports the style-adjusted contrasts and their pointwise intervals. The browser report presents the complete specification ladder, exposure diagnostics, era contrasts and early-card comparisons. All reported numbers are generated from machine-readable manifests.",
    ar_tex_escape(ar_elasticity_text),
    "\\input{tables/analysis-headlines}",
    "\\subsection{Pooled Champions League comparisons}",
    "\\input{fragments/results-real-madrid-pooled-precision}"),
  conclusion = c("\\section{Interpretation and limits}",
    ar_tex_escape(ar_limit_text), ar_tex_escape(ar_retracted_text),
    "A sharper correctness outcome would require an independently adjudicated set of comparable incidents, including no-calls, with foul severity, location, score state and time at risk. The present sources cannot supply that denominator. Official definitions distinguish misconduct from fouls and announced minimum added time from elapsed time: \\href{https://www.theifab.com/laws/latest/fouls-and-misconduct/}{IFAB Law 12} and \\href{https://www.theifab.com/laws/latest/the-duration-of-the-match/}{IFAB Law 7}."))
for (ar_name in names(ar_fragments)) {
  writeLines(c("% Generated by programs/20-build-analysis-report.R; do not edit.",
    ar_fragments[[ar_name]]), file.path(root, "my_paper", "fragments",
                                      paste0("analysis-update-", ar_name, ".tex")))
}
ar_tex_figlabels <- c("barcelona-ladder", "barcelona-possession", "barcelona-robustness",
  "rmuclcomparisons", "rmuclprecision", "rmuclstability", "card-timing")
ar_main <- c("\\pdfminorversion=7", "\\documentclass[11pt]{article}",
  "\\usepackage[margin=1in]{geometry}",
  "\\usepackage{amsmath,booktabs,graphicx,float,hyperref}",
  "\\hypersetup{hidelinks}",
  "\\title{Refereeing Gaps after Accounting for Playing Style}",
  "\\author{Hussain Hadah}\\date{\\today}",
  "\\begin{document}\\maketitle",
  "\\begin{abstract}\\input{fragments/analysis-update-abstract}\\end{abstract}",
  "\\input{fragments/analysis-update-introduction}\\input{fragments/analysis-update-data}",
  "\\input{fragments/analysis-update-empirical-strategy}\\input{fragments/analysis-update-results}",
  "\\input{fragments/analysis-update-conclusion}",
  "\\clearpage\\input{tables/table-rm-ucl-pooled-precision}")
for (ar_i in seq_along(ar_figs)) {
  ar_main <- c(ar_main, "\\clearpage\\begin{figure}[p]\\centering",
    sprintf("\\caption{%s}\\label{fig:%s}", ar_fig_titles[ar_i], ar_tex_figlabels[ar_i]),
    sprintf("\\includegraphics[width=\\textwidth,height=.85\\textheight,keepaspectratio]{figure/%s.pdf}", ar_figs[ar_i]),
    "\\end{figure}")
}
writeLines(c(ar_main, "\\end{document}"),
           file.path(root, "my_paper", "analysis-update.tex"))
cat(sprintf("Report: %s\n%s\n%s\n", file.path(root, "output", "analysis-report.html"),
            ar_audit_text, ar_overlap_text))
