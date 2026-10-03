#!/usr/bin/env Rscript
################################################################################
# 17-barcelona-style-adjusted-decisions.R
# Purpose: Does Barcelona receive more favorable La Liga decisions than its
#          playing style predicts? One COMMON SAMPLE carries a specification
#          ladder so that raw-versus-adjusted differences are not confounded
#          by sample changes:
#            L0 raw team indicators;
#            L1 pre-match: home, season FE, opponent FE, win-probability
#               ventile FE (bookmaker odds);
#            L2 + strictly lagged playing style: season-to-date mean possession
#               and shots of BOTH teams over their prior La Liga matches
#               (natural splines; no same-match information);
#            L3 L1 + same-match possession and shots, INSTEAD of lagged style
#               (descriptive: these can respond to referee decisions);
#            L4 + flexible called fouls (card severity given fouls; cards and
#               fouls are not treated as a binomial or as "correct" calls).
#          Contrasts: Barcelona vs non-elite La Liga teams, Real Madrid vs
#          non-elite, and Barcelona minus Real Madrid with the covariance.
#          Blocks: fouls with estimated (not imposed) possession exposure and
#          a same-sample proportionality test; pre/post 2018 descriptive era
#          split from one interacted model; style overlap diagnostics and a
#          possession common-support sensitivity.
#          Inference: season-block clusters (both rows of a match and the
#          within-season persistence sit in one cluster) with t(G-1) critical
#          values; two-way match + team-season clusters reported alongside.
#          Nothing here identifies favoritism: residual coefficients are
#          conditional associations.
# Runs:    sourced by 95-make-all.R after the panel is built (helpers and
#          directories already defined), or standalone from the project root
#          or REFEREE_BIAS_ROOT (loads packages, sources 00-functions.R).
# Input:   data/datasets/team-match-panel.csv (via load_panel)
# Results -> output/tables/barcelona-style-ladder.csv/.dta
#         -> output/tables/barcelona-style-exposure.csv/.dta
#         -> output/tables/barcelona-style-era.csv/.dta
#         -> output/tables/barcelona-style-overlap.csv/.dta
#         -> output/tables/barcelona-style-overlap-estimates.csv/.dta
#         -> output/tables/barcelona-style-sample-flow.csv/.dta
#         -> output/tables/barcelona-style-figure-ladder-data.csv
#         -> output/tables/barcelona-style-figure-possession-data.csv
#         -> output/tables/barcelona-style-figure-robustness-data.csv
#         -> output/tables/barcelona-style-ladder.tex (+ my_paper/tables)
#         -> output/figures/figure-barcelona-style-ladder.pdf/.png
#         -> output/figures/figure-barcelona-style-possession-diagnostic.pdf/.png
#         -> output/figures/figure-barcelona-style-robustness.pdf/.png
# Date:    October 3rd, 2026
################################################################################

# ---- Standalone bootstrap ---------------------------------------------------
# When sourced by 95-make-all.R, load_panel() and the directories exist and this
# block is skipped. Standalone: resolve the root, define the directories the
# shared helpers expect, load the packages 00-functions.R needs, source it.
bs17_standalone <- !exists("load_panel", mode = "function")
if (bs17_standalone) {
  bs17_root <- Sys.getenv("REFEREE_BIAS_ROOT", unset = "")
  if (!nzchar(bs17_root)) bs17_root <- getwd()
  root <- normalizePath(bs17_root, mustWork = TRUE)
  if (!file.exists(file.path(root, "programs", "00-functions.R"))) {
    stop(sprintf("17: programs/00-functions.R not found under %s; set REFEREE_BIAS_ROOT",
                 root), call. = FALSE)
  }
  suppressPackageStartupMessages({
    library(dplyr)
    library(readr)
    library(tibble)
    library(ggplot2)
  })
  datasets      <- file.path(root, "data", "datasets")
  tables_wd     <- file.path(root, "output", "tables")
  figures_wd    <- file.path(root, "output", "figures")
  paper_tables  <- file.path(root, "my_paper", "tables")
  paper_figures <- file.path(root, "my_paper", "figure")
  for (d in c(tables_wd, figures_wd, paper_tables, paper_figures)) {
    if (!dir.exists(d)) dir.create(d, recursive = TRUE)
  }
  source(file.path(root, "programs", "00-functions.R"))
}
suppressPackageStartupMessages({
  library(data.table)
  library(fixest)
  library(ggplot2)
  library(haven)
  library(splines)
})

bs17_run_id <- if (exists("run_id") && is.character(run_id) && nzchar(run_id[1])) {
  run_id[1]
} else {
  format(Sys.time(), "%Y%m%d-%H%M%S")
}
bs17_script <- "17-barcelona-style-adjusted-decisions.R"
bs17_input_path <- file.path(datasets, "team-match-panel.csv")
bs17_input_md5 <- unname(tools::md5sum(bs17_input_path))
bs17_ci_level <- 0.95
bs17_min_prior <- 3L   # prior matches needed before a lagged style value exists
bs17_assert <- function(cond, msg) if (!isTRUE(cond)) stop(sprintf("17: %s", msg), call. = FALSE)

# ---- Sample construction ----------------------------------------------------
bs17_panel <- as.data.table(load_panel())
bs17_assert(nrow(bs17_panel) > 0, "load_panel() returned no rows")
bs17_liga <- bs17_panel[league == "esp.1" & season_start >= box_first_season]
setorder(bs17_liga, team_id, season_start, date, event_id)

bs17_flow <- list()
bs17_flow_add <- function(step, dt) {
  bs17_flow[[length(bs17_flow) + 1L]] <<- data.frame(
    step = step, rows = nrow(dt), matches = uniqueN(dt$event_id),
    seasons = uniqueN(dt$season_start), barca_rows = sum(dt$barca == 1),
    madrid_rows = sum(dt$real_madrid == 1), stringsAsFactors = FALSE)
}
bs17_flow_add("La Liga rows, cards era (>= 2005/06), complete seasons", bs17_liga)

# Possession is valid only when both shares are strictly inside (0, 100) and
# sum to 100 within one point. Invalid values are excluded, never rescaled.
# The cleaner's possession_valid flag (when present) is required as well.
bs17_liga[, poss_ok := !is.na(own_possession) & !is.na(opp_possession) &
            own_possession > 0 & own_possession < 100 &
            opp_possession > 0 & opp_possession < 100 &
            abs(own_possession + opp_possession - 100) <= 1]
if ("possession_valid" %in% names(bs17_liga)) {
  bs17_liga[, poss_ok := poss_ok & !is.na(possession_valid) & as.logical(possession_valid)]
}

# Strictly lagged style: season-to-date means over the team's PRIOR La Liga
# matches with valid possession and shots. The current match never enters.
bs17_liga[, style_ok := poss_ok & !is.na(own_shots)]
bs17_liga[, `:=`(
  lag_n     = shift(cumsum(style_ok), 1L, fill = 0L),
  lag_poss  = shift(cumsum(fifelse(style_ok, as.numeric(own_possession), 0)), 1L, fill = 0),
  lag_shots = shift(cumsum(fifelse(style_ok, as.numeric(own_shots), 0)), 1L, fill = 0)
), by = .(team_id, season_start)]
bs17_liga[, lag_poss  := fifelse(lag_n >= bs17_min_prior, lag_poss / lag_n, NA_real_)]
bs17_liga[, lag_shots := fifelse(lag_n >= bs17_min_prior, lag_shots / lag_n, NA_real_)]
# Strict dating: every prior match used in a lag precedes the current match
bs17_liga[, prev_date := shift(date, 1L), by = .(team_id, season_start)]
bs17_assert(bs17_liga[!is.na(lag_poss), all(prev_date < date)],
            "a lagged style value draws on a match not dated before the current one")
bs17_liga[, prev_date := NULL]
# Leakage check: the first match of every team-season has no prior matches, so
# its lag must be missing; a non-missing value would mean the current row leaked
bs17_assert(bs17_liga[, is.na(lag_poss[1L]) & lag_n[1L] == 0L,
                      by = .(team_id, season_start)][, all(V1)],
            "lagged possession is defined at the first match of a team-season")

# Opponent's lagged style comes from the opponent's own row of the same match
bs17_pairs <- bs17_liga[, .N, by = event_id]
bs17_liga <- bs17_liga[event_id %in% bs17_pairs[N == 2L, event_id]]
bs17_flow_add("Matches with both team rows present", bs17_liga)
bs17_opp <- bs17_liga[, .(event_id, opp_id = team_id, lag_opp_poss = lag_poss,
                          lag_opp_shots = lag_shots)]
bs17_liga <- merge(bs17_liga, bs17_opp, by = c("event_id", "opp_id"), all.x = TRUE)
bs17_assert(!anyDuplicated(bs17_liga[, .(event_id, team_id)]),
            "duplicate team-match rows after the opponent merge")

bs17_liga[, in_common := poss_ok &
            !is.na(own_shots) & !is.na(opp_shots) &
            !is.na(own_fouls) & !is.na(opp_fouls) &
            !is.na(own_yellow) & !is.na(opp_yellow) &
            !is.na(own_red) & !is.na(opp_red) &
            !is.na(prob_win) & !is.na(lag_poss) & !is.na(lag_opp_poss)]
bs17_flow_add("Rows passing possession, shots, cards, fouls, odds, lag checks",
              bs17_liga[in_common == TRUE])
bs17_liga[, both_ok := all(in_common), by = event_id]
bs17_common <- bs17_liga[in_common & both_ok]
bs17_flow_add("Common sample (cards and fouls): both rows of the match pass",
              bs17_common)
bs17_assert(bs17_common[, .N, by = event_id][, all(N == 2L)],
            "common sample is not match-paired")
bs17_assert(bs17_common[, sum(barca)] >= 100,
            "fewer than 100 Barcelona rows in the common sample")

# Penalties: the common sample restricted to independently eligible event logs.
# A complete goal timeline cannot verify that every penalty was labeled.
bs17_common[, pens_in := as.logical(pens_ok) & !is.na(net_pens) & !is.na(own_pens) &
              !is.na(opp_pens)]
bs17_common[, pens_both := all(pens_in), by = event_id]
bs17_pens <- bs17_common[pens_in & pens_both]
bs17_flow_add("Penalty sample: common sample with eligible event logs", bs17_pens)

# ---- Controls: strength ventiles, era, spline bases -------------------------
bs17_common[, pwin_bin17 := ceiling(20 * frank(prob_win, ties.method = "first") / .N)]
bs17_common[, post2018 := as.integer(season_start > negreira_last_season)]
bs17_common[, `:=`(barca_pre = barca * (1L - post2018), barca_post = barca * post2018,
                   madrid_pre = real_madrid * (1L - post2018),
                   madrid_post = real_madrid * post2018,
                   elite_pre = other_elite * (1L - post2018),
                   elite_post = other_elite * post2018)]
bs17_common[, log_own_poss := log(own_possession / 100)]
bs17_common[, log_opp_poss := log(opp_possession / 100)]
bs17_common[, group := fifelse(barca == 1, "Barcelona",
                        fifelse(real_madrid == 1, "Real Madrid",
                        fifelse(other_elite == 1, "Atletico Madrid", "Non-elite")))]

bs17_add_ns <- function(dt, var, df, prefix) {
  basis <- splines::ns(dt[[var]], df = df)
  nm <- sprintf("%s_ns%d", prefix, seq_len(ncol(basis)))
  for (j in seq_len(ncol(basis))) set(dt, j = nm[j], value = as.numeric(basis[, j]))
  paste(nm, collapse = " + ")
}
bs17_terms_lag <- paste(
  bs17_add_ns(bs17_common, "lag_poss", 4, "lagposs"),
  bs17_add_ns(bs17_common, "lag_shots", 3, "lagshots"),
  bs17_add_ns(bs17_common, "lag_opp_poss", 4, "lagoppposs"),
  bs17_add_ns(bs17_common, "lag_opp_shots", 3, "lagoppshots"), sep = " + ")
# Opponent possession is 100 minus own, so only own possession enters
bs17_terms_now <- paste(
  bs17_add_ns(bs17_common, "own_possession", 5, "poss"),
  bs17_add_ns(bs17_common, "own_shots", 3, "shots"),
  bs17_add_ns(bs17_common, "opp_shots", 3, "oppshots"), sep = " + ")
bs17_terms_fouls <- paste(
  bs17_add_ns(bs17_common, "own_fouls", 4, "ownfouls"),
  bs17_add_ns(bs17_common, "opp_fouls", 4, "oppfouls"), sep = " + ")
# Penalty rows are a subset of the common sample: carry the same bases over
bs17_pens <- bs17_common[pens_in & pens_both]

bs17_fe <- "season_start + opp_id + pwin_bin17"
bs17_teams <- "barca + real_madrid + other_elite"
bs17_specs <- list(
  L0 = list(label = "L0: raw difference",
            rhs = bs17_teams, fe = NULL,
            controls = "none"),
  L1 = list(label = "L1: + home, season, opponent, win-probability FE",
            rhs = paste(bs17_teams, "+ home"), fe = bs17_fe,
            controls = "home; season FE; opponent FE; pre-match win-probability ventile FE"),
  L2 = list(label = "L2: + prior-match style (lagged possession, shots; both teams)",
            rhs = paste(bs17_teams, "+ home +", bs17_terms_lag), fe = bs17_fe,
            controls = paste("L1 + natural splines of season-to-date prior-match",
                             "possession (df 4) and shots (df 3), own and opponent")),
  # October 2026 audit: prior possession has almost no cross-club overlap.
  # Keep L2 visible, but compare a same-match alternative rather than carrying
  # its extrapolation into every specification. This is not a causal remedy.
  L3 = list(label = "L3: same-match style instead of lagged style (descriptive)",
            rhs = paste(bs17_teams, "+ home +", bs17_terms_now),
            fe = bs17_fe,
            controls = paste("L1 + natural splines of same-match own possession (df 5),",
                             "own shots (df 3), opponent shots (df 3); endogenous to decisions")),
  L4 = list(label = "L4: + called fouls, both teams (card severity)",
            rhs = paste(bs17_teams, "+ home +", bs17_terms_now, "+",
                        bs17_terms_fouls),
            fe = bs17_fe,
            controls = paste("L3 + natural splines of own and opponent fouls called (df 4);",
                             "cards per foul are not modelled as binomial"))
)

# Outcomes, with the sign that makes a positive coefficient favorable to the
# team. Fewer yellows received is favorable, so own_yellow is signed -1.
bs17_outcomes <- data.frame(
  outcome = c("own_yellow", "opp_yellow", "net_yellow", "net_fouls", "net_red", "net_pens"),
  label = c("Yellow cards received", "Yellow cards to opponent",
            "Net yellow cards (opp. - own)", "Net fouls (opp. - own)",
            "Net red cards (opp. - own)", "Net penalties (for - against)"),
  favorable_sign = c(-1, 1, 1, 1, 1, 1),
  sample = c("common", "common", "common", "common", "common", "pens"),
  severity_rung = c(TRUE, TRUE, TRUE, FALSE, TRUE, FALSE),
  stringsAsFactors = FALSE)

# ---- Estimation helpers -----------------------------------------------------
bs17_fit_ols <- function(y, rhs, fe, dt, key) {
  f <- if (is.null(fe)) as.formula(paste(y, "~", rhs)) else
    as.formula(paste(y, "~", rhs, "|", fe))
  tryCatch(feols(f, data = dt, vcov = ~season_start),
           error = function(e) stop(sprintf("17: feols failed for %s: %s", key,
                                            conditionMessage(e)), call. = FALSE))
}

bs17_contrast_weights <- function(coef_names, plus, minus = character(0)) {
  w <- setNames(numeric(length(coef_names)), coef_names)
  bs17_assert(all(c(plus, minus) %in% coef_names),
              sprintf("coefficients %s not in model", paste(c(plus, minus), collapse = ",")))
  w[plus] <- 1
  w[minus] <- -1
  w
}

# Linear contrasts with season-cluster covariance; t(G-1) critical values.
bs17_contrasts <- function(m, dt, contrasts, y, require_full = TRUE) {
  used <- dt[obs(m)]
  # Reported counts are the rows fixest actually used. OLS rungs must keep the
  # full sample so every rung within an outcome rests on identical rows; the
  # Poisson exposure models may legitimately drop a fixed-effect cell with all
  # zeros, and that drop is recorded in n_dropped instead of being fatal.
  bs17_assert(nrow(used) == nobs(m), sprintf("obs()/nobs mismatch for %s", y))
  if (require_full) {
    bs17_assert(nrow(used) == nrow(dt),
                sprintf("model for %s dropped %d of %d rows; rungs would not share a sample",
                        y, nrow(dt) - nrow(used), nrow(dt)))
  }
  b <- coef(m)
  V1 <- vcov(m)
  V2 <- tryCatch(vcov(m, vcov = ~event_id + team_season),
    error = function(e) stop(sprintf("17: secondary covariance for %s: %s",
      y, conditionMessage(e)), call. = FALSE))
  G <- uniqueN(used$season_start)
  dfree <- G - 1L
  tcrit <- qt(1 - (1 - bs17_ci_level) / 2, dfree)
  nonelite <- used[elite == 0]
  out <- lapply(names(contrasts), function(k) {
    w <- bs17_contrast_weights(names(b), contrasts[[k]]$plus, contrasts[[k]]$minus)
    est <- sum(w * b)
    se <- sqrt(as.numeric(t(w) %*% V1 %*% w))
    se2 <- sqrt(as.numeric(t(w) %*% V2 %*% w))
    data.frame(
      contrast = k, contrast_label = contrasts[[k]]$label,
      estimate = est, se = se, t_stat = est / se,
      p_value = 2 * pt(-abs(est / se), dfree),
      ci_low = est - tcrit * se, ci_high = est + tcrit * se,
      se_twoway_match_teamseason = se2,
      n_obs = nrow(used), n_input = nrow(dt), n_dropped = nrow(dt) - nrow(used),
      n_matches = uniqueN(used$event_id), n_seasons = G,
      n_barca = sum(used$barca), n_madrid = sum(used$real_madrid),
      n_other_elite = sum(used$other_elite), n_nonelite = nrow(nonelite),
      df_t = dfree, t_crit = tcrit,
      dep_mean = mean(used[[y]]), dep_sd = sd(used[[y]]),
      baseline_nonelite_mean = mean(nonelite[[y]]),
      baseline_nonelite_sd = sd(nonelite[[y]]),
      stringsAsFactors = FALSE)
  })
  do.call(rbind, out)
}

bs17_team_contrasts <- list(
  barca = list(plus = "barca", label = "Barcelona vs non-elite La Liga teams"),
  madrid = list(plus = "real_madrid", label = "Real Madrid vs non-elite La Liga teams"),
  barca_minus_madrid = list(plus = "barca", minus = "real_madrid",
                            label = "Barcelona minus Real Madrid"))

bs17_provenance <- function(df) {
  df$run_id <- bs17_run_id
  df$script <- bs17_script
  df$input_md5 <- bs17_input_md5
  df$ci_level <- bs17_ci_level
  df$inference_primary <- "cluster: season (t with G-1 df)"
  df$inference_secondary <- "two-way cluster: match + team-season (SE only)"
  df
}

bs17_write_manifest <- function(df, slug) {
  df <- bs17_provenance(df)
  write.csv(df, file.path(tables_wd, sprintf("%s.csv", slug)), row.names = FALSE)
  haven::write_dta(df, file.path(tables_wd, sprintf("%s.dta", slug)))
  invisible(df)
}

bs17_sample_for <- function(name) if (name == "pens") bs17_pens else bs17_common

# ---- Block 1: specification ladder on the common sample ---------------------
bs17_ladder <- do.call(rbind, lapply(seq_len(nrow(bs17_outcomes)), function(i) {
  y <- bs17_outcomes$outcome[i]
  dt <- bs17_sample_for(bs17_outcomes$sample[i])
  rungs <- names(bs17_specs)
  if (!bs17_outcomes$severity_rung[i]) rungs <- setdiff(rungs, "L4")
  do.call(rbind, lapply(rungs, function(r) {
    sp <- bs17_specs[[r]]
    m <- bs17_fit_ols(y, sp$rhs, sp$fe, dt, sprintf("ladder %s %s", y, r))
    res <- bs17_contrasts(m, dt, bs17_team_contrasts, y)
    res$outcome <- y
    res$outcome_label <- bs17_outcomes$label[i]
    res$favorable_sign <- bs17_outcomes$favorable_sign[i]
    res$estimate_signed <- res$estimate * res$favorable_sign
    res$ci_low_signed <- ifelse(res$favorable_sign < 0, -res$ci_high, res$ci_low)
    res$ci_high_signed <- ifelse(res$favorable_sign < 0, -res$ci_low, res$ci_high)
    res$rung <- r
    res$rung_label <- sp$label
    res$controls <- sp$controls
    res$fixed_effects <- if (is.null(sp$fe)) "none" else "season; opponent; win-probability ventile"
    res$estimator <- "OLS (feols)"
    res$estimand <- "conditional mean difference per match, La Liga"
    res$sample <- bs17_outcomes$sample[i]
    # Percent of the non-elite baseline is meaningful only for level outcomes
    res$pct_of_nonelite_baseline <- ifelse(
      y %in% c("own_yellow", "opp_yellow"), 100 * res$estimate / res$baseline_nonelite_mean,
      NA_real_)
    res
  }))
}))
bs17_assert(as.data.table(bs17_ladder)[, uniqueN(n_obs), by = outcome][, all(V1 == 1L)],
            "ladder rows differ across rungs within an outcome")
bs17_write_manifest(bs17_ladder, "barcelona-style-ladder")

# ---- Block 2: fouls with estimated possession exposure ----------------------
# Fouls committed are exposed to the opponent's possession, fouls suffered to
# the team's own. Three treatments on one sample: no exposure, exposure as a
# Poisson offset (elasticity fixed at 1), exposure as a regressor (elasticity
# estimated). Same-match possession is endogenous, so these are descriptive.
bs17_fit_pois <- function(y, rhs, offset, key) {
  f <- as.formula(paste(y, "~", rhs, "|", bs17_fe))
  tryCatch(
    if (is.null(offset)) fepois(f, data = bs17_common, vcov = ~season_start) else
      fepois(f, data = bs17_common, offset = as.formula(paste("~", offset)),
             vcov = ~season_start),
    error = function(e) stop(sprintf("17: fepois failed for %s: %s", key,
                                     conditionMessage(e)), call. = FALSE))
}
bs17_exposure_grid <- data.frame(
  side = rep(c("committed", "suffered"), each = 3),
  outcome = rep(c("own_fouls", "opp_fouls"), each = 3),
  exposure_var = rep(c("log_opp_poss", "log_own_poss"), each = 3),
  treatment = rep(c("none", "offset_elasticity_1", "estimated_elasticity"), 2),
  stringsAsFactors = FALSE)
bs17_exposure <- do.call(rbind, lapply(seq_len(nrow(bs17_exposure_grid)), function(i) {
  g <- bs17_exposure_grid[i, ]
  rhs <- paste(bs17_teams, "+ home")
  offset <- NULL
  if (g$treatment == "offset_elasticity_1") offset <- g$exposure_var
  if (g$treatment == "estimated_elasticity") rhs <- paste(rhs, "+", g$exposure_var)
  m <- bs17_fit_pois(g$outcome, rhs, offset, sprintf("exposure %s %s", g$side, g$treatment))
  res <- bs17_contrasts(m, bs17_common, bs17_team_contrasts, g$outcome, require_full = FALSE)
  res$rate_ratio <- exp(res$estimate)
  res$rate_ratio_ci_low <- exp(res$ci_low)
  res$rate_ratio_ci_high <- exp(res$ci_high)
  res$side <- g$side
  res$outcome <- g$outcome
  res$outcome_label <- if (g$side == "committed") "Fouls called against the team" else
    "Fouls called against the opponent"
  res$exposure_treatment <- g$treatment
  res$exposure_var <- g$exposure_var
  res$estimator <- "Poisson (fepois)"
  res$estimand <- "log rate ratio of fouls per match, La Liga"
  res$fixed_effects <- "season; opponent; win-probability ventile"
  res$elasticity <- NA_real_
  res$elasticity_se <- NA_real_
  res$elasticity_ci_low <- NA_real_
  res$elasticity_ci_high <- NA_real_
  res$p_elasticity_equals_1 <- NA_real_
  if (g$treatment == "estimated_elasticity") {
    b <- coef(m)[g$exposure_var]
    s <- sqrt(vcov(m)[g$exposure_var, g$exposure_var])
    res$elasticity <- b
    res$elasticity_se <- s
    res$elasticity_ci_low <- b - res$t_crit * s
    res$elasticity_ci_high <- b + res$t_crit * s
    res$p_elasticity_equals_1 <- 2 * pt(-abs((b - 1) / s), res$df_t)
  }
  if (g$treatment == "offset_elasticity_1") res$elasticity <- 1
  res
}))
bs17_write_manifest(bs17_exposure, "barcelona-style-exposure")

# ---- Block 3: pre/post 2018 descriptive split (one interacted model) --------
# 2018 is both the end of the reported Negreira payments and the first VAR
# season in La Liga. The split is descriptive; it does not isolate either.
bs17_era_contrasts <- list(
  barca_pre = list(plus = "barca_pre", label = "Barcelona vs non-elite, 2005/06-2017/18"),
  barca_post = list(plus = "barca_post", label = "Barcelona vs non-elite, 2018/19-2025/26"),
  barca_post_minus_pre = list(plus = "barca_post", minus = "barca_pre",
                              label = "Barcelona: post minus pre 2018"),
  madrid_pre = list(plus = "madrid_pre", label = "Real Madrid vs non-elite, 2005/06-2017/18"),
  madrid_post = list(plus = "madrid_post", label = "Real Madrid vs non-elite, 2018/19-2025/26"),
  madrid_post_minus_pre = list(plus = "madrid_post", minus = "madrid_pre",
                               label = "Real Madrid: post minus pre 2018"),
  barca_minus_madrid_pre = list(plus = "barca_pre", minus = "madrid_pre",
                                label = "Barcelona minus Real Madrid, 2005/06-2017/18"),
  barca_minus_madrid_post = list(plus = "barca_post", minus = "madrid_post",
                                 label = "Barcelona minus Real Madrid, 2018/19-2025/26"),
  gap_change = list(plus = c("barca_post", "madrid_pre"), minus = c("barca_pre", "madrid_post"),
                    label = "Change in (Barcelona minus Real Madrid) after 2018"))
bs17_era_rhs <- paste("barca_pre + barca_post + madrid_pre + madrid_post + elite_pre +",
                      "elite_post + home +", bs17_terms_lag)
bs17_era <- do.call(rbind, lapply(seq_len(nrow(bs17_outcomes)), function(i) {
  y <- bs17_outcomes$outcome[i]
  dt <- bs17_sample_for(bs17_outcomes$sample[i])
  m <- bs17_fit_ols(y, bs17_era_rhs, bs17_fe, dt, sprintf("era %s", y))
  res <- bs17_contrasts(m, dt, bs17_era_contrasts, y)
  used <- dt[obs(m)]
  res$outcome <- y
  res$outcome_label <- bs17_outcomes$label[i]
  res$favorable_sign <- bs17_outcomes$favorable_sign[i]
  res$estimate_signed <- res$estimate * res$favorable_sign
  res$ci_low_signed <- ifelse(res$favorable_sign < 0, -res$ci_high, res$ci_low)
  res$ci_high_signed <- ifelse(res$favorable_sign < 0, -res$ci_low, res$ci_high)
  res$rung <- "L2_era"
  res$rung_label <- paste0(bs17_specs$L2$label, ", team indicators interacted with era (pre/post 2018)")
  res$controls <- bs17_specs$L2$controls
  res$fixed_effects <- "season; opponent; win-probability ventile"
  res$estimator <- "OLS (feols), team indicators interacted with era"
  res$estimand <- "conditional mean difference per match by era, La Liga"
  res$sample <- bs17_outcomes$sample[i]
  res$n_barca_pre <- sum(used$barca_pre)
  res$n_barca_post <- sum(used$barca_post)
  res$n_seasons_pre <- uniqueN(used[post2018 == 0, season_start])
  res$n_seasons_post <- uniqueN(used[post2018 == 1, season_start])
  res$era_cut <- sprintf("post = season_start > %d (Negreira exit; VAR start)", negreira_last_season)
  res
}))
bs17_write_manifest(bs17_era, "barcelona-style-era")

# ---- Block 4: style overlap and possession common-support sensitivity ------
bs17_overlap_stat <- function(var, target, reference) {
  ref <- bs17_common[group == reference, get(var)]
  tgt <- bs17_common[group == target, get(var)]
  q <- quantile(ref, c(0.01, 0.05, 0.95, 0.99), names = FALSE)
  data.frame(
    style_var = var, target = target, reference = reference,
    n_target = length(tgt), n_reference = length(ref),
    target_min = min(tgt), target_p50 = median(tgt), target_max = max(tgt),
    reference_p01 = q[1], reference_p05 = q[2], reference_p50 = median(ref),
    reference_p95 = q[3], reference_p99 = q[4],
    share_target_within_ref_p05_p95 = mean(tgt >= q[2] & tgt <= q[3]),
    share_target_within_ref_p01_p99 = mean(tgt >= q[1] & tgt <= q[4]),
    share_target_above_ref_p95 = mean(tgt > q[3]),
    stringsAsFactors = FALSE)
}
bs17_overlap <- do.call(rbind, c(
  lapply(c("lag_poss", "own_possession", "lag_shots", "own_shots"), function(v) rbind(
    bs17_overlap_stat(v, "Barcelona", "Non-elite"),
    bs17_overlap_stat(v, "Real Madrid", "Non-elite"),
    bs17_overlap_stat(v, "Barcelona", "Real Madrid")))))
bs17_overlap$style_var_label <- c(
  lag_poss = "Prior-match possession (season to date)",
  own_possession = "Same-match possession",
  lag_shots = "Prior-match shots (season to date)",
  own_shots = "Same-match shots")[bs17_overlap$style_var]

# Common support on same-match possession: rows whose possession lies where
# both Barcelona and non-elite teams have support (1st-99th percentiles of
# both). This keeps the possession-dominant side of most matches, so match
# pairs break by construction; season clusters still contain both rows.
bs17_q_barca <- quantile(bs17_common[group == "Barcelona", own_possession], c(0.01, 0.99),
                         names = FALSE)
bs17_q_nonelite <- quantile(bs17_common[group == "Non-elite", own_possession], c(0.01, 0.99),
                            names = FALSE)
bs17_support <- c(lo = max(bs17_q_barca[1], bs17_q_nonelite[1]),
                  hi = min(bs17_q_barca[2], bs17_q_nonelite[2]))
bs17_assert(bs17_support[["hi"]] > bs17_support[["lo"]], "empty possession common support")
bs17_common[, in_support := own_possession >= bs17_support[["lo"]] &
              own_possession <= bs17_support[["hi"]]]
bs17_trim <- bs17_common[in_support == TRUE]
bs17_pens[, in_support := own_possession >= bs17_support[["lo"]] &
            own_possession <= bs17_support[["hi"]]]
bs17_trim_pens <- bs17_pens[in_support == TRUE]
bs17_flow_add(sprintf("Possession common support [%.1f, %.1f], cards and fouls",
                      bs17_support[["lo"]], bs17_support[["hi"]]), bs17_trim)
bs17_flow_add("Possession common support, penalty sample", bs17_trim_pens)

bs17_overlap_est <- do.call(rbind, lapply(seq_len(nrow(bs17_outcomes)), function(i) {
  y <- bs17_outcomes$outcome[i]
  full <- bs17_sample_for(bs17_outcomes$sample[i])
  dt <- if (bs17_outcomes$sample[i] == "pens") bs17_trim_pens else bs17_trim
  do.call(rbind, lapply(c("L1", "L3"), function(r) {
    sp <- bs17_specs[[r]]
    m <- bs17_fit_ols(y, sp$rhs, sp$fe, dt, sprintf("support %s %s", y, r))
    res <- bs17_contrasts(m, dt, bs17_team_contrasts, y)
    res$outcome <- y
    res$outcome_label <- bs17_outcomes$label[i]
    res$favorable_sign <- bs17_outcomes$favorable_sign[i]
    res$estimate_signed <- res$estimate * res$favorable_sign
    res$ci_low_signed <- ifelse(res$favorable_sign < 0, -res$ci_high, res$ci_low)
    res$ci_high_signed <- ifelse(res$favorable_sign < 0, -res$ci_low, res$ci_high)
    res$rung <- r
    res$rung_label <- sp$label
    res$controls <- sp$controls
    res$fixed_effects <- "season; opponent; win-probability ventile"
    res$estimator <- "OLS (feols)"
    res$estimand <- "conditional mean difference per match, possession common support"
    res$sample <- paste0(bs17_outcomes$sample[i], "_possession_support")
    res$support_lo <- bs17_support[["lo"]]
    res$support_hi <- bs17_support[["hi"]]
    res$n_barca_full_sample <- sum(full$barca)
    res$n_barca_lost <- sum(full$barca) - res$n_barca
    res$share_barca_lost <- res$n_barca_lost / sum(full$barca)
    res$n_madrid_full_sample <- sum(full$real_madrid)
    res$n_madrid_lost <- sum(full$real_madrid) - res$n_madrid
    res
  }))
}))
bs17_write_manifest(bs17_overlap_est, "barcelona-style-overlap-estimates")
bs17_write_manifest(bs17_overlap, "barcelona-style-overlap")
bs17_write_manifest(do.call(rbind, bs17_flow), "barcelona-style-sample-flow")

# ---- Figure A: specification ladder ----------------------------------------
bs17_series_colors <- c("Barcelona vs non-elite" = colors_customs[["barca"]],
                        "Real Madrid vs non-elite" = colors_customs[["madrid"]],
                        "Barcelona minus Real Madrid" = "grey25")
bs17_series_label <- c(barca = "Barcelona vs non-elite",
                       madrid = "Real Madrid vs non-elite",
                       barca_minus_madrid = "Barcelona minus Real Madrid")
bs17_fig_ladder <- as.data.table(bs17_ladder)[, .(
  outcome, outcome_label, rung, rung_label, contrast,
  series = bs17_series_label[contrast],
  estimate_signed, ci_low_signed, ci_high_signed, se, p_value,
  n_obs, n_matches, n_seasons, n_barca, n_madrid, n_nonelite, favorable_sign)]
bs17_fig_ladder[, outcome_label := factor(outcome_label, levels = bs17_outcomes$label)]
bs17_fig_ladder[, rung_short := factor(rung, levels = rev(names(bs17_specs)),
  labels = rev(c("L0 raw", "L1 pre-match FE", "L2 prior style",
                 "L3 same-match style", "L4 L3 + called fouls")))]
bs17_fig_ladder[, series := factor(series, levels = names(bs17_series_colors))]
write.csv(bs17_fig_ladder, file.path(tables_wd, "barcelona-style-figure-ladder-data.csv"),
          row.names = FALSE)

bs17_n_common <- bs17_flow[[which(vapply(bs17_flow, function(x) startsWith(x$step, "Common"),
                                         logical(1)))[1]]]
bs17_n_pens <- bs17_flow[[which(vapply(bs17_flow, function(x) startsWith(x$step, "Penalty"),
                                       logical(1)))[1]]]
bs17_plot_ladder <- ggplot(bs17_fig_ladder,
                           aes(estimate_signed, rung_short, colour = series)) +
  geom_vline(xintercept = 0, colour = "grey50") +
  geom_errorbar(aes(xmin = ci_low_signed, xmax = ci_high_signed),
                width = 0, position = position_dodge(width = 0.65), linewidth = 0.5) +
  geom_point(position = position_dodge(width = 0.65), size = 1.7) +
  facet_wrap(~outcome_label, ncol = 3, scales = "free_x") +
  scale_colour_manual(values = bs17_series_colors) +
  labs(x = "Per-match difference, signed so that positive = favorable to the team",
       y = NULL, colour = NULL,
       title = "Barcelona's La Liga decisions across a common-sample specification ladder",
       subtitle = paste0("Same matches; L2 and L3 are alternative style controls. ",
                         "95% season-block CIs with t(G-1) critical values."),
       caption = sprintf(paste0(
         "Common sample: %s La Liga matches (%s team-match rows, %d seasons, %d Barcelona ",
         "rows); penalties on %s matches with eligible event logs.\nL2 uses season-to-date ",
         "possession and shots of both teams over prior matches only. L3 uses same-match ",
         "style instead; these controls respond to decisions.\nCoefficients are conditional ",
         "associations, not estimates of favoritism. Sources: ESPN, football-data.co.uk."),
         formatC(bs17_n_common$matches, big.mark = ","),
         formatC(bs17_n_common$rows, big.mark = ","), bs17_n_common$seasons,
         bs17_n_common$barca_rows, formatC(bs17_n_pens$matches, big.mark = ","))) +
  theme_customs(base_size = 11) +
  theme(legend.position = "bottom", panel.spacing.x = unit(1.2, "lines"))
save_figure(bs17_plot_ladder, "figure-barcelona-style-ladder.pdf", width = 10, height = 7)

# ---- Figure B: possession-versus-fouls diagnostic with data support ---------
# Binned means by same-match possession for Barcelona, Real Madrid and
# non-elite teams. If Barcelona's line sits apart from non-elite teams at the
# same possession level, possession alone does not account for the gap.
bs17_bin_width <- 5
bs17_common[, poss_bin17 := floor(own_possession / bs17_bin_width) * bs17_bin_width]
bs17_diag_groups <- c("Non-elite", "Real Madrid", "Barcelona")
bs17_diag_outcomes <- c(own_fouls = "Fouls called against the team",
                        opp_fouls = "Fouls called against the opponent",
                        own_yellow = "Yellow cards received",
                        net_yellow = "Net yellow cards (opp. - own)")
bs17_diag <- rbindlist(lapply(names(bs17_diag_outcomes), function(y) {
  bs17_common[group %in% bs17_diag_groups,
              .(outcome = y, panel = bs17_diag_outcomes[[y]],
                mean = mean(get(y)), se = sd(get(y)) / sqrt(.N), n = .N),
              by = .(group, poss_bin17)]
}))
bs17_diag_min_n <- 15L
bs17_diag_plot <- bs17_diag[n >= bs17_diag_min_n]
bs17_diag_plot[, `:=`(ci_low = mean - 1.96 * se, ci_high = mean + 1.96 * se,
                      poss_mid = poss_bin17 + bs17_bin_width / 2)]
bs17_support_share <- bs17_common[group %in% bs17_diag_groups, .(n = .N), by = .(group, poss_bin17)]
bs17_support_share[, share := n / sum(n), by = group]
bs17_support_share[, `:=`(outcome = "support", panel = "Share of the group's matches in each bin",
                          poss_mid = poss_bin17 + bs17_bin_width / 2)]
bs17_fig_poss <- rbind(
  bs17_diag_plot[, .(outcome, panel, group, poss_bin17, poss_mid, value = mean, ci_low, ci_high, n)],
  bs17_support_share[, .(outcome, panel, group, poss_bin17, poss_mid, value = share,
                         ci_low = NA_real_, ci_high = NA_real_, n)])
bs17_fig_poss[, panel := factor(panel, levels = c(unname(bs17_diag_outcomes),
                                                  "Share of the group's matches in each bin"))]
bs17_fig_poss[, group := factor(group, levels = bs17_diag_groups)]
write.csv(bs17_fig_poss, file.path(tables_wd, "barcelona-style-figure-possession-data.csv"),
          row.names = FALSE)
bs17_group_colors <- c("Non-elite" = "grey45", "Real Madrid" = colors_customs[["madrid"]],
                       "Barcelona" = colors_customs[["barca"]])
bs17_elast <- as.data.table(bs17_exposure)[exposure_treatment == "estimated_elasticity" &
                                             contrast == "barca"]
bs17_plot_poss <- ggplot() +
  geom_col(data = bs17_fig_poss[outcome == "support"],
           aes(poss_mid, value, fill = group), position = position_dodge(width = 4.2),
           width = 4.2, alpha = 0.85) +
  geom_errorbar(data = bs17_fig_poss[outcome != "support"],
                aes(poss_mid, ymin = ci_low, ymax = ci_high, colour = group),
                width = 0, linewidth = 0.4, position = position_dodge(width = 1.5)) +
  geom_line(data = bs17_fig_poss[outcome != "support"],
            aes(poss_mid, value, colour = group), linewidth = 0.6,
            position = position_dodge(width = 1.5)) +
  geom_point(data = bs17_fig_poss[outcome != "support"],
             aes(poss_mid, value, colour = group), size = 1.6,
             position = position_dodge(width = 1.5)) +
  facet_wrap(~panel, ncol = 2, scales = "free_y") +
  scale_colour_manual(values = bs17_group_colors, aesthetics = c("colour", "fill")) +
  scale_x_continuous(breaks = seq(20, 90, 10)) +
  labs(x = "Same-match possession share (%), 5-point bins", y = "Per-match mean / share",
       colour = NULL, fill = NULL,
       title = "Fouls and cards by possession: Barcelona against teams at the same possession",
       subtitle = sprintf(paste0(
         "Bins with at least %d matches per group; bars show where each group's matches sit. ",
         "Poisson elasticity of fouls against the team\nwith respect to opponent possession: ",
         "%.2f [%.2f, %.2f]; fouls against the opponent w.r.t. own possession: %.2f [%.2f, %.2f]"),
         bs17_diag_min_n,
         bs17_elast[side == "committed", elasticity], bs17_elast[side == "committed", elasticity_ci_low],
         bs17_elast[side == "committed", elasticity_ci_high],
         bs17_elast[side == "suffered", elasticity], bs17_elast[side == "suffered", elasticity_ci_low],
         bs17_elast[side == "suffered", elasticity_ci_high]),
       caption = paste0("Means with unclustered 95% intervals, descriptive only; same-match ",
                        "possession responds to decisions. Common sample as in the ladder figure.\n",
                        "Elasticities from Poisson regressions with season, opponent and ",
                        "win-probability FE; season-cluster CIs. Sources: ESPN, football-data.co.uk.")) +
  theme_customs(base_size = 11) +
  theme(legend.position = "bottom")
save_figure(bs17_plot_poss, "figure-barcelona-style-possession-diagnostic.pdf",
            width = 10, height = 7.5)

# ---- Figure C: era and common-support robustness ----------------------------
bs17_rob_era <- as.data.table(bs17_era)[contrast %in% c("barca_pre", "barca_post",
                                                         "barca_minus_madrid_pre",
                                                         "barca_minus_madrid_post")]
bs17_rob_era[, series := fifelse(grepl("minus", contrast), "Barcelona minus Real Madrid",
                                 "Barcelona vs non-elite")]
bs17_rob_era[, sample_label := fifelse(grepl("_pre", contrast),
                                       sprintf("%s-%s, L2", season_label(box_first_season),
                                               season_label(negreira_last_season)),
                                       sprintf("%s-%s, L2", season_label(negreira_last_season + 1L),
                                               season_label(analysis_last_season)))]
bs17_rob_all <- as.data.table(bs17_ladder)[rung == "L2" & contrast %in% c("barca", "barca_minus_madrid")]
bs17_rob_all[, series := bs17_series_label[contrast]]
bs17_rob_all[, sample_label := "All seasons, L2"]
bs17_rob_sup <- as.data.table(bs17_overlap_est)[rung == "L3" & contrast %in% c("barca", "barca_minus_madrid")]
bs17_rob_sup[, series := bs17_series_label[contrast]]
bs17_rob_sup[, sample_label := sprintf("Possession support [%.0f, %.0f], L3",
                                       bs17_support[["lo"]], bs17_support[["hi"]])]
bs17_rob_cols <- c("outcome", "outcome_label", "contrast", "series", "sample_label",
                   "estimate_signed", "ci_low_signed", "ci_high_signed", "se", "p_value",
                   "n_obs", "n_matches", "n_seasons", "n_barca", "n_madrid")
bs17_fig_rob <- rbind(bs17_rob_all[, ..bs17_rob_cols], bs17_rob_era[, ..bs17_rob_cols],
                      bs17_rob_sup[, ..bs17_rob_cols])
bs17_rob_levels <- unique(c("All seasons, L2", bs17_rob_era$sample_label, bs17_rob_sup$sample_label))
bs17_fig_rob[, sample_label := factor(sample_label, levels = rev(bs17_rob_levels))]
bs17_fig_rob[, outcome_label := factor(outcome_label, levels = bs17_outcomes$label)]
bs17_fig_rob[, series := factor(series, levels = names(bs17_series_colors))]
write.csv(bs17_fig_rob, file.path(tables_wd, "barcelona-style-figure-robustness-data.csv"),
          row.names = FALSE)
bs17_barca_lost <- as.data.table(bs17_overlap_est)[rung == "L3" & contrast == "barca" &
                                                     outcome == "net_yellow"]
bs17_plot_rob <- ggplot(bs17_fig_rob, aes(estimate_signed, sample_label, colour = series)) +
  geom_vline(xintercept = 0, colour = "grey50") +
  geom_errorbar(aes(xmin = ci_low_signed, xmax = ci_high_signed), width = 0,
                position = position_dodge(width = 0.6), linewidth = 0.5) +
  geom_point(position = position_dodge(width = 0.6), size = 1.7) +
  facet_wrap(~outcome_label, ncol = 3, scales = "free_x") +
  scale_colour_manual(values = bs17_series_colors) +
  labs(x = "Per-match difference, signed so that positive = favorable to the team",
       y = NULL, colour = NULL,
       title = "Era split and possession common support: Barcelona's conditional gaps",
       subtitle = paste0("Eras use prior-match style controls. The overlap sample uses same-match style.\n",
                         "Both comparisons are descriptive; trimming changes the population."),
       caption = sprintf(paste0(
         "2018 separates the reported payment period and first VAR season; it does not identify a payment effect.\n",
         "Possession support drops %d of %d Barcelona rows (%.0f%%) and the low-possession side of most matches.\n",
         "95%% season-block CIs with t(G-1) critical values. Sources: ESPN, football-data.co.uk."),
         bs17_barca_lost$n_barca_lost, bs17_barca_lost$n_barca_full_sample,
         100 * bs17_barca_lost$share_barca_lost)) +
  theme_customs(base_size = 11) +
  theme(legend.position = "bottom", panel.spacing.x = unit(1.2, "lines"),
        plot.title.position = "plot", plot.caption.position = "plot")
save_figure(bs17_plot_rob, "figure-barcelona-style-robustness.pdf", width = 10, height = 7)

# ---- LaTeX fragment: ladder table -------------------------------------------
bs17_fmt <- function(x, d = 3) formatC(x, format = "f", digits = d)
bs17_stars <- function(p) ifelse(p < 0.01, "$^{***}$", ifelse(p < 0.05, "$^{**}$",
                                 ifelse(p < 0.1, "$^{*}$", "")))
bs17_tex_block <- function(contrast_key, header) {
  L <- as.data.table(bs17_ladder)[contrast == contrast_key]
  rows <- c(sprintf("\\multicolumn{%d}{l}{\\textit{%s}} \\\\", length(bs17_specs) + 1, header))
  for (i in seq_len(nrow(bs17_outcomes))) {
    y <- bs17_outcomes$outcome[i]
    cells_est <- cells_se <- character(length(bs17_specs))
    for (j in seq_along(bs17_specs)) {
      r <- L[outcome == y & rung == names(bs17_specs)[j]]
      if (nrow(r) == 1L) {
        cells_est[j] <- paste0(bs17_fmt(r$estimate), bs17_stars(r$p_value))
        cells_se[j] <- sprintf("(%s)", bs17_fmt(r$se))
      } else {
        cells_est[j] <- "--"
        cells_se[j] <- ""
      }
    }
    rows <- c(rows,
              sprintf("%s & %s \\\\", bs17_outcomes$label[i], paste(cells_est, collapse = " & ")),
              sprintf(" & %s \\\\", paste(cells_se, collapse = " & ")))
  }
  rows
}
bs17_n_row <- vapply(names(bs17_specs), function(r) {
  x <- as.data.table(bs17_ladder)[rung == r & contrast == "barca" & outcome == "net_yellow"]
  formatC(x$n_obs, format = "d", big.mark = ",")
}, character(1))
bs17_n_pens_row <- vapply(names(bs17_specs), function(r) {
  x <- as.data.table(bs17_ladder)[rung == r & contrast == "barca" & outcome == "net_pens"]
  if (nrow(x) == 1L) formatC(x$n_obs, format = "d", big.mark = ",") else "--"
}, character(1))
bs17_tex <- c(
  "\\begin{table}[htbp]\\centering",
  "\\caption{Barcelona's La Liga Decisions Across a Common-Sample Specification Ladder",
  "\\label{tab:barcelona-style-ladder}}",
  "\\footnotesize",
  sprintf("\\begin{tabular}{l%s}", strrep("c", length(bs17_specs))),
  "\\toprule",
  sprintf(" & %s \\\\", paste(sprintf("(%d)", seq_along(bs17_specs)), collapse = " & ")),
  sprintf(" & %s \\\\", paste(names(bs17_specs), collapse = " & ")),
  "\\midrule",
  bs17_tex_block("barca", "Panel A: Barcelona relative to non-elite La Liga teams"),
  "\\midrule",
  bs17_tex_block("barca_minus_madrid", "Panel B: Barcelona minus Real Madrid"),
  "\\midrule",
  sprintf("Observations, cards and fouls & %s \\\\", paste(bs17_n_row, collapse = " & ")),
  sprintf("Observations, penalties & %s \\\\", paste(bs17_n_pens_row, collapse = " & ")),
  sprintf("Seasons & %s \\\\", paste(rep(bs17_n_common$seasons, length(bs17_specs)), collapse = " & ")),
  sprintf("Home, season, opponent, win-prob. FE & %s \\\\",
          paste(ifelse(names(bs17_specs) == "L0", "No", "Yes"), collapse = " & ")),
  sprintf("Prior-match style (both teams) & %s \\\\",
          paste(ifelse(names(bs17_specs) == "L2", "Yes", "No"), collapse = " & ")),
  sprintf("Same-match possession and shots & %s \\\\",
          paste(ifelse(names(bs17_specs) %in% c("L3", "L4"), "Yes", "No"), collapse = " & ")),
  sprintf("Called fouls, both teams & %s \\\\",
          paste(ifelse(names(bs17_specs) == "L4", "Yes", "No"), collapse = " & ")),
  "\\bottomrule",
  "\\end{tabular}",
  "\\begin{minipage}{\\linewidth}\\footnotesize\\vspace{0.5em}",
  paste0("\\textit{Notes:} Each cell is a separate OLS regression on the same La Liga ",
         "team-match rows (", formatC(bs17_n_common$rows, big.mark = ","), " rows, ",
         formatC(bs17_n_common$matches, big.mark = ","), " matches, ", bs17_n_common$seasons,
         " seasons, ", bs17_n_common$barca_rows, " Barcelona rows); penalties use the ",
         formatC(bs17_n_pens$matches, big.mark = ","), " matches with eligible event logs. ",
         "The dependent variable is the per-match count named in the row; net outcomes are ",
         "decisions against the opponent minus decisions against the team. Column L2 adds ",
         "natural splines of both teams' season-to-date possession and shots over prior ",
         "matches only. Column L3 instead controls for same-match ",
         "possession and both teams' shots, which respond to the referee's decisions, and is ",
         "descriptive. Column L4 adds splines of both teams' called fouls and applies to card ",
         "outcomes only. Coefficients are conditional associations and do not identify ",
         "favoritism. Standard errors in parentheses are clustered by season; stars use ",
         "$t$ critical values with $G-1$ degrees of freedom. ",
         "$^{*}p<0.1$, $^{**}p<0.05$, $^{***}p<0.01$."),
  "\\end{minipage}",
  "\\end{table}")
for (d in c(tables_wd, paper_tables)) {
  writeLines(bs17_tex, file.path(d, "barcelona-style-ladder.tex"))
}

# ---- Completion message -----------------------------------------------------
bs17_key <- as.data.table(bs17_ladder)[contrast %in% c("barca", "barca_minus_madrid") &
                                         rung %in% c("L1", "L2", "L3")]
bs17_key_lines <- bs17_key[, sprintf("  %-32s %s %s: %+.3f [%+.3f, %+.3f]", outcome_label,
                                     rung, fifelse(contrast == "barca", "Barca-nonelite",
                                                   "Barca-Madrid  "),
                                     estimate_signed, ci_low_signed, ci_high_signed)]
bs17_lag_overlap <- as.data.table(bs17_overlap)[style_var == "lag_poss" & target == "Barcelona" &
                                                  reference == "Non-elite"]
bs17_now_overlap <- as.data.table(bs17_overlap)[style_var == "own_possession" &
                                                  target == "Barcelona" & reference == "Non-elite"]
message(paste(c(
  sprintf("17: run %s, input md5 %s", bs17_run_id, substr(bs17_input_md5, 1, 8)),
  sprintf("17: common sample %s rows / %s matches / %d seasons; Barcelona %d, Real Madrid %d rows",
          formatC(bs17_n_common$rows, big.mark = ","),
          formatC(bs17_n_common$matches, big.mark = ","), bs17_n_common$seasons,
          bs17_n_common$barca_rows, bs17_n_common$madrid_rows),
  sprintf("17: penalty sample %s matches; possession support [%.1f, %.1f] drops %d Barcelona rows",
          formatC(bs17_n_pens$matches, big.mark = ","), bs17_support[["lo"]],
          bs17_support[["hi"]], bs17_barca_lost$n_barca_lost),
  sprintf("17: Barcelona prior-match possession above non-elite p95 in %.1f%% of rows; same-match within non-elite p01-p99 in %.1f%%",
          100 * bs17_lag_overlap$share_target_above_ref_p95,
          100 * bs17_now_overlap$share_target_within_ref_p01_p99),
  "17: signed estimates (positive = favorable), season-cluster 95% CI:",
  bs17_key_lines,
  sprintf("17: wrote %d ladder, %d exposure, %d era, %d support rows to %s",
          nrow(bs17_ladder), nrow(bs17_exposure), nrow(bs17_era), nrow(bs17_overlap_est),
          tables_wd)), collapse = "\n"))
