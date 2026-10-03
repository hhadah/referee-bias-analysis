################################################################################
# 18-champions-league-pooled-precision.R
# Purpose: Real Madrid in the Champions League with pooled, honestly bounded
#          inference. Replaces per-season significance hunting with:
#          (a) a same-sample ladder of raw / pre-match / style-adjusted gaps,
#              Real Madrid vs non-elite clubs, vs the other elite clubs, and
#              vs Barcelona, for net yellow cards, net fouls, net penalties,
#              net red cards, and net yellow cards conditional on fouls called;
#          (b) season-block cluster inference with t(G - 1) criticals, G the
#              number of seasons in the estimation sample, next to match-pair,
#              team-season and heteroskedasticity-robust SEs for comparison;
#          (c) minimum detectable effects (80 percent power, 5 percent two-
#              sided) per 10 matches and TOST equivalence against explicit
#              illustrative bounds, plus the smallest symmetric bound the 90
#              percent interval excludes;
#          (d) descriptive stage (group vs knockout) and VAR-era splits that do
#              not condition on title seasons;
#          (e) season-specific raw estimates next to empirical-Bayes shrinkage
#              with heterogeneity diagnostics, leave-one-season-out refits,
#              and the cumulative-pooling precision curve.
#          The unit is a team-match (120-minute matches count once). Same-match
#          possession is an endogenous control: the style-adjusted column is a
#          conditional association, not a causal bias estimate.
# Input:   data/datasets/team-match-panel.csv via load_panel()
# Output:  output/tables/rm-ucl-pooled-precision-estimates.csv/.dta
#          output/tables/rm-ucl-pooled-precision-equivalence.csv/.dta
#          output/tables/rm-ucl-pooled-precision-stage-era.csv/.dta
#          output/tables/rm-ucl-pooled-precision-by-season.csv/.dta
#          output/tables/rm-ucl-pooled-precision-loso.csv/.dta
#          output/tables/rm-ucl-pooled-precision-cumulative.csv/.dta
#          output/tables/rm-ucl-pooled-precision-run.csv
#          output/tables/table-rm-ucl-pooled-precision.tex (+ my_paper/tables)
#          output/figures/figure-rm-ucl-pooled-comparisons.pdf/.png
#          output/figures/figure-rm-ucl-precision-limits.pdf/.png
#          output/figures/figure-rm-ucl-season-stability.pdf/.png
#          my_paper/fragments/results-real-madrid-pooled-precision.tex
# Runner:  sourced by 95-make-all.R after the clean/build steps. Also runs
#          standalone: Rscript programs/18-champions-league-pooled-precision.R
#          [root], or with REFEREE_BIAS_ROOT set. Installs nothing.
# Date:    October 3rd, 2026
################################################################################

# ---- Standalone bootstrap ---------------------------------------------------
if (!exists("root")) {
  p18_args <- commandArgs(trailingOnly = TRUE)
  root <- if (length(p18_args) >= 1) p18_args[[1]] else
    Sys.getenv("REFEREE_BIAS_ROOT", unset = getwd())
  root <- normalizePath(root, mustWork = FALSE)
}
if (!file.exists(file.path(root, "programs", "00-functions.R"))) {
  stop(sprintf("18: root %s has no programs/00-functions.R; pass the project ",
               "root as the first argument or set REFEREE_BIAS_ROOT", root),
       call. = FALSE)
}
if (!exists("datasets"))      datasets      <- file.path(root, "data", "datasets")
if (!exists("tables_wd"))     tables_wd     <- file.path(root, "output", "tables")
if (!exists("figures_wd"))    figures_wd    <- file.path(root, "output", "figures")
if (!exists("paper_tables"))  paper_tables  <- file.path(root, "my_paper", "tables")
if (!exists("paper_figures")) paper_figures <- file.path(root, "my_paper", "figure")
p18_fragments <- file.path(root, "my_paper", "fragments")
for (p18_d in c(tables_wd, figures_wd, paper_tables, paper_figures,
                p18_fragments)) {
  if (!dir.exists(p18_d)) dir.create(p18_d, recursive = TRUE)
}

suppressPackageStartupMessages({
  library(data.table)
  library(haven)
  library(fixest)
  library(ggplot2)
  library(patchwork)
})
if (!exists("load_panel", mode = "function")) {
  # load_panel() and the theme are tidyverse-based; load only what they need.
  suppressPackageStartupMessages({
    library(tibble)
    library(readr)
    library(dplyr)
  })
  source(file.path(root, "programs", "00-functions.R"))
}
if (!exists("run_id")) run_id <- format(Sys.time(), "%Y%m%d-%H%M%S")

# Fira Sans is registered by the runner through showtext; standalone runs
# fall back to the default sans family instead of emitting font warnings.
p18_fira <- requireNamespace("sysfonts", quietly = TRUE) &&
  "Fira Sans" %in% sysfonts::font_families()
p18_theme <- function(base_size = 11) {
  th <- theme_customs(base_size = base_size)
  if (!p18_fira) th <- th + theme(text = element_text(family = "sans"))
  th
}

# ---- Design constants -------------------------------------------------------
p18_slug      <- "rm-ucl-pooled-precision"
p18_alpha     <- 0.05
p18_power     <- 0.80
p18_per_games <- 10L
# Author decision Oct 2026: the style-adjusted column is the headline because
# the question is whether gaps survive possession; the pre-match column is
# the cleaner (pre-determined controls only) estimate and is exported for
# every display. Flip here to switch the figures.
p18_main_spec <- "style"

p18_outcomes <- data.table(
  outcome   = c("net_yellow", "net_fouls", "net_pens", "net_red",
                "net_yellow_fouls"),
  var       = c("net_yellow", "net_fouls", "net_pens", "net_red", "net_yellow"),
  label     = c("Net yellow cards", "Net fouls", "Net penalties",
                "Net red cards", "Net yellow cards | fouls called"),
  unit      = c("cards", "fouls", "penalties", "red cards", "cards"),
  # Baseline for percent-of-baseline statements: the non-elite own-side rate
  baseline  = c("own_yellow", "own_fouls", "own_pens", "own_red", "own_yellow"),
  # Same-match fouls as controls: cards conditional on the fouls called. Not
  # a yellow/foul binomial, because cards for dissent etc. are not fouls.
  extra_rhs = c("", "", "", "", " + own_fouls + opp_fouls")
)
# Author decision Oct 2026: illustrative equivalence bounds in per-10-match
# units (small / medium / large). They are reporting anchors, not claims
# about what matters. One yellow card per 10 matches is about 5 percent of
# the non-elite rate; half a penalty per 10 matches is about a third of it.
p18_bounds <- list(
  net_yellow = c(0.5, 1, 2), net_fouls = c(2.5, 5, 10),
  net_pens = c(0.25, 0.5, 1), net_red = c(0.1, 0.25, 0.5),
  net_yellow_fouls = c(0.5, 1, 2)
)
p18_bound_labels <- c("small", "medium", "large")

p18_specs <- data.table(
  spec  = c("raw", "prematch", "style"),
  label = c("Raw", "Pre-match adjusted", "Style adjusted"),
  fe    = c("0",
            "season_start + ucl_stage + opp_id + p18_elo_bin",
            "season_start + ucl_stage + opp_id + p18_elo_bin + p18_poss_bin")
)
p18_rhs_base <- "real_madrid + barca + other_elite + p18_venue"

p18_contrasts <- data.table(
  contrast = c("rm_vs_nonelite", "rm_vs_other_elite", "rm_vs_barca",
               "barca_vs_nonelite", "other_elite_vs_nonelite"),
  label    = c("Real Madrid vs non-elite clubs",
               "Real Madrid vs other elite clubs",
               "Real Madrid vs Barcelona",
               "Barcelona vs non-elite clubs",
               "Other elite clubs vs non-elite clubs"),
  a = c("real_madrid", "real_madrid", "real_madrid", "barca", "other_elite"),
  b = c(NA, "other_elite", "barca", NA, NA)
)

# ---- Sample -----------------------------------------------------------------
p18_panel_file <- file.path(datasets, "team-match-panel.csv")
p18_input_md5  <- unname(tools::md5sum(p18_panel_file))
p18_ucl <- as.data.table(load_panel())
p18_ucl <- p18_ucl[domestic == 0L & season_start >= box_first_season]

p18_required <- c("extra_time", "possession_valid", "pens_ok", "elo_exp",
                  "own_possession", "net_yellow", "net_fouls", "net_pens",
                  "net_red", "own_fouls", "opp_fouls", "event_id",
                  "team_season", "ucl_stage", "opp_id", "neutral_site")
p18_missing <- setdiff(p18_required, names(p18_ucl))
if (length(p18_missing) > 0) {
  stop(sprintf("18: team-match panel lacks column(s) %s; rebuild with 05",
               paste(p18_missing, collapse = ", ")), call. = FALSE)
}
if (nrow(p18_ucl) == 0L) stop("18: no Champions League rows", call. = FALSE)
if (any(p18_ucl[, .N, by = event_id]$N != 2L)) {
  stop("18: every Champions League match must appear exactly twice",
       call. = FALSE)
}

# Venue in {-1, 0, 1}: for net outcomes the two rows of a match are mirror
# images, so one antisymmetric venue regressor replaces home + away and
# leaves neutral venues at zero.
p18_ucl[, p18_venue := as.integer(home) - as.integer(away)]
p18_ucl[, extra_time := as.logical(extra_time)]
p18_ucl[, possession_valid := as.logical(possession_valid)]
p18_ucl[, p18_knockout := as.integer(ucl_stage == "Knockout")]
# Match-level introduction: knockout matches from 2018/19, then all stages.
# The split is institutional, not chosen on titles.
p18_ucl[, p18_var := as.integer(var_era)]
# Elo expected-score ventiles computed within the Champions League sample so
# that every bin is populated (the panel-wide ventiles in load_panel are
# dominated by domestic matches).
p18_elo_breaks <- unique(quantile(p18_ucl$elo_exp, probs = seq(0, 1, 0.05)))
p18_ucl[, p18_elo_bin := cut(elo_exp, p18_elo_breaks, include.lowest = TRUE)]
# Possession bins only where the cleaner validated both shares. No "missing"
# bin: rows without valid possession leave the style-adjusted sample and,
# to keep the ladder same-sample, the raw and pre-match columns too.
p18_ucl[, p18_poss_bin := cut(ifelse(possession_valid, own_possession, NA_real_),
                              c(0, seq(30, 75, 2.5), 100))]
p18_ucl[, p18_rm_group  := real_madrid * (1L - p18_knockout)]
p18_ucl[, p18_rm_ko     := real_madrid * p18_knockout]
p18_ucl[, p18_rm_prevar := real_madrid * (1L - p18_var)]
p18_ucl[, p18_rm_var    := real_madrid * p18_var]

# Row eligibility per outcome and sample
p18_rows <- function(oc, sample) {
  if (!sample %in% c("common", "no_extra_time", "all_outcome_rows")) {
    stop(sprintf("18: unknown sample %s", sample), call. = FALSE)
  }
  o <- p18_outcomes[outcome == oc]
  ok <- !is.na(p18_ucl[[o$var]])
  if (nzchar(o$extra_rhs)) {
    ok <- ok & !is.na(p18_ucl$own_fouls) & !is.na(p18_ucl$opp_fouls)
  }
  if (sample == "all_outcome_rows") return(ok)
  ok <- ok & p18_ucl$possession_valid & !is.na(p18_ucl$p18_poss_bin) &
    !is.na(p18_ucl$own_shots) & !is.na(p18_ucl$opp_shots)
  if (sample == "no_extra_time") ok <- ok & !p18_ucl$extra_time
  ok
}

# ---- Estimation helpers -----------------------------------------------------
p18_formula <- function(oc, sp, rhs = NULL) {
  o <- p18_outcomes[outcome == oc]
  s <- p18_specs[spec == sp]
  if (is.null(rhs)) rhs <- p18_rhs_base
  if (sp == "style") rhs <- paste(rhs, "+ own_shots + opp_shots")
  fe_part <- if (s$fe == "0") "" else paste(" |", s$fe)
  as.formula(sprintf("%s ~ %s%s%s", o$var, rhs, o$extra_rhs, fe_part))
}

p18_fit <- function(fml, data, key) {
  m <- tryCatch(feols(fml, data = data, notes = FALSE),
                error = function(e) e)
  if (inherits(m, "error")) {
    stop(sprintf("18: feols failed for %s: %s", key, conditionMessage(m)),
         call. = FALSE)
  }
  m
}

# Linear contrast a - b (or a alone) with the four variance estimators. The
# primary is the season block: it covers the two rows of a match and any
# within-season persistence, with t(G - 1) criticals. It still assumes
# independence across seasons, so persistent multi-season favoritism is
# estimated, not absorbed.
p18_contrast <- function(m, a, b, data_used) {
  bb <- coef(m)
  if (!a %in% names(bb) || (!is.na(b) && !b %in% names(bb))) {
    stop(sprintf("18: coefficient %s/%s not estimated", a, b), call. = FALSE)
  }
  est <- if (is.na(b)) bb[[a]] else bb[[a]] - bb[[b]]
  se_of <- function(V) {
    if (is.na(b)) sqrt(V[a, a]) else sqrt(V[a, a] + V[b, b] - 2 * V[a, b])
  }
  # Author decision Oct 2026: degrees of freedom count the seasons in which
  # the contrasted club(s) actually play, not every season in the sample. A
  # season with other clubs' matches but no Real Madrid match carries no
  # information about the Real Madrid coefficient.
  G <- uniqueN(data_used[get(a) == 1L]$season_start)
  if (!is.na(b)) G <- min(G, uniqueN(data_used[get(b) == 1L]$season_start))
  list(
    est = est,
    se_season = se_of(vcov(m, cluster = ~season_start)),
    se_match = se_of(vcov(m, cluster = ~event_id)),
    se_teamseason = se_of(vcov(m, cluster = ~team_season)),
    se_hetero = se_of(vcov(m, vcov = "hetero")),
    n_seasons = G, df = G - 1L
  )
}

# Standard interval and power quantities from (est, se, df)
p18_infer <- function(est, se, df) {
  tc95 <- qt(1 - p18_alpha / 2, df)
  tc90 <- qt(1 - p18_alpha, df)
  mde <- uniroot(function(delta) {
    pt(-tc95, df, ncp = delta / se) +
      pt(tc95, df, ncp = delta / se, lower.tail = FALSE) - p18_power
  }, c(0, 10 * se))$root
  tstat <- est / se
  list(
    t_crit_95 = tc95, p_value = 2 * pt(-abs(tstat), df),
    ci95_low = est - tc95 * se, ci95_high = est + tc95 * se,
    ci90_low = est - tc90 * se, ci90_high = est + tc90 * se,
    mde = mde,
    # Smallest symmetric bound B with TOST p < alpha: the 90 percent CI lies
    # inside (-B, B). Equivalence is relative to this bound, never "no bias".
    equiv_margin = max(abs(est - tc90 * se), abs(est + tc90 * se))
  )
}

p18_tost <- function(est, se, df, bound) {
  p_lower <- pt((est + bound) / se, df, lower.tail = FALSE)
  p_upper <- pt((est - bound) / se, df, lower.tail = TRUE)
  max(p_lower, p_upper)
}

p18_counts <- function(d, oc) {
  base_var <- p18_outcomes[outcome == oc]$baseline
  list(
    n_rows = nrow(d), n_matches = uniqueN(d$event_id),
    n_seasons = uniqueN(d$season_start),
    season_first = min(d$season_start), season_last = max(d$season_start),
    season_first_rm = min(d[real_madrid == 1L]$season_start),
    season_last_rm = max(d[real_madrid == 1L]$season_start),
    n_rm_matches = sum(d$real_madrid), n_rm_seasons = uniqueN(d[real_madrid == 1L]$season_start),
    n_rm_knockout = sum(d$real_madrid * d$p18_knockout),
    n_rm_extra_time = sum(d$real_madrid * d$extra_time),
    n_barca_matches = sum(d$barca), n_other_elite_matches = sum(d$other_elite),
    n_nonelite_rows = sum(d$elite == 0L),
    baseline_nonelite = mean(d[elite == 0L][[base_var]])
  )
}

p18_extract <- function(m, data_used, oc, sp, smp) {
  cnt <- p18_counts(data_used, oc)
  rows <- lapply(seq_len(nrow(p18_contrasts)), function(i) {
    k <- p18_contrasts[i]
    ct <- p18_contrast(m, k$a, k$b, data_used)
    inf <- p18_infer(ct$est, ct$se_season, ct$df)
    data.table(
      outcome = oc, outcome_label = p18_outcomes[outcome == oc]$label,
      spec = sp, spec_label = p18_specs[spec == sp]$label, sample = smp,
      contrast = k$contrast, contrast_label = k$label,
      estimate = ct$est, se = ct$se_season, df = ct$df, t_crit_95 = inf$t_crit_95,
      p_value = inf$p_value, ci95_low = inf$ci95_low, ci95_high = inf$ci95_high,
      ci90_low = inf$ci90_low, ci90_high = inf$ci90_high,
      se_match_cluster = ct$se_match, se_team_season_cluster = ct$se_teamseason,
      se_hetero = ct$se_hetero,
      estimate_per10 = p18_per_games * ct$est,
      ci95_low_per10 = p18_per_games * inf$ci95_low,
      ci95_high_per10 = p18_per_games * inf$ci95_high,
      mde_per_match = inf$mde, mde_per10 = p18_per_games * inf$mde,
      mde_pct_baseline = 100 * inf$mde / cnt$baseline_nonelite,
      equiv_margin_per10 = p18_per_games * inf$equiv_margin,
      equiv_margin_pct_baseline = 100 * inf$equiv_margin / cnt$baseline_nonelite,
      as.data.table(cnt)
    )
  })
  rbindlist(rows)
}

# ---- Pooled ladder ----------------------------------------------------------
message("18: pooled ladder")
p18_models <- list()
p18_ladder <- rbindlist(lapply(seq_len(nrow(p18_outcomes)), function(i) {
  oc <- p18_outcomes$outcome[i]
  rbindlist(lapply(c("common", "no_extra_time", "all_outcome_rows"), function(smp) {
    specs <- if (smp == "all_outcome_rows") c("raw", "prematch") else p18_specs$spec
    d <- p18_ucl[p18_rows(oc, smp)]
    rbindlist(lapply(specs, function(sp) {
      key <- paste(oc, sp, smp, sep = "/")
      m <- p18_fit(p18_formula(oc, sp), d, key)
      d_used <- d[obs(m)]      # counts from the estimation sample only
      p18_models[[key]] <<- m
      p18_extract(m, d_used, oc, sp, smp)
    }))
  }))
}))
p18_ladder[, main_spec := as.integer(spec == p18_main_spec)]
if (any(p18_ladder[sample == "common", .(v = uniqueN(n_rows)), by = outcome]$v != 1L)) {
  stop("18: ladder specs do not share one sample within an outcome", call. = FALSE)
}

# ---- Equivalence against illustrative bounds ------------------------------
p18_equiv <- rbindlist(lapply(seq_len(nrow(p18_ladder)), function(i) {
  r <- p18_ladder[i]
  if (!(r$sample == "common" && r$contrast %in% c("rm_vs_nonelite", "rm_vs_other_elite"))) {
    return(NULL)
  }
  b10 <- p18_bounds[[r$outcome]]
  data.table(
    outcome = r$outcome, spec = r$spec, contrast = r$contrast,
    bound_label = p18_bound_labels, bound_per10 = b10,
    bound_per_match = b10 / p18_per_games,
    bound_pct_baseline = 100 * (b10 / p18_per_games) / r$baseline_nonelite,
    estimate_per10 = r$estimate_per10, df = r$df,
    tost_p = vapply(b10 / p18_per_games, function(b)
      p18_tost(r$estimate, r$se, r$df, b), numeric(1)),
    equiv_margin_per10 = r$equiv_margin_per10
  )
}))
p18_equiv[, equivalent_at_5pct := as.integer(tost_p < p18_alpha)]

# ---- Stage and VAR-era splits (descriptive) --------------------------------
message("18: stage and era splits")
p18_split_defs <- list(
  stage = c(p18_rm_group = "Group/league phase", p18_rm_ko = "Knockout"),
  var_era = c(p18_rm_prevar = "Before VAR",
              p18_rm_var = "VAR: 2018/19 knockouts onward")
)
p18_stage_era <- rbindlist(lapply(p18_outcomes$outcome, function(oc) {
  d <- p18_ucl[p18_rows(oc, "common")]
  rbindlist(lapply(names(p18_split_defs), function(sd) {
    terms <- names(p18_split_defs[[sd]])
    rhs <- paste(c(terms, "barca", "other_elite", "p18_venue"), collapse = " + ")
    m <- p18_fit(p18_formula(oc, p18_main_spec, rhs), d, paste(oc, sd))
    d_used <- d[obs(m)]
    V <- vcov(m, cluster = ~season_start)
    bb <- coef(m)
    G_cell <- vapply(terms, function(tm) uniqueN(d_used[get(tm) == 1L]$season_start), integer(1))
    G_diff <- min(G_cell)
    dd <- bb[[terms[2]]] - bb[[terms[1]]]
    se_dd <- sqrt(V[terms[1], terms[1]] + V[terms[2], terms[2]] - 2 * V[terms[1], terms[2]])
    rbindlist(lapply(terms, function(tm) {
      cell <- d_used[get(tm) == 1L]
      G <- G_cell[[tm]]
      inf <- p18_infer(bb[[tm]], sqrt(V[tm, tm]), G - 1L)
      data.table(
        outcome = oc, spec = p18_main_spec, split = sd,
        cell = p18_split_defs[[sd]][[tm]], contrast = "rm_vs_nonelite",
        estimate = bb[[tm]], se = sqrt(V[tm, tm]), df = G - 1L,
        p_value = inf$p_value, ci95_low = inf$ci95_low, ci95_high = inf$ci95_high,
        estimate_per10 = p18_per_games * bb[[tm]],
        ci95_low_per10 = p18_per_games * inf$ci95_low,
        ci95_high_per10 = p18_per_games * inf$ci95_high,
        mde_per10 = p18_per_games * inf$mde,
        n_rm_matches_cell = nrow(cell), n_rm_seasons_cell = uniqueN(cell$season_start),
        n_rm_extra_time_cell = sum(cell$extra_time),
        n_rows = nrow(d_used), n_seasons = uniqueN(d_used$season_start),
        diff_second_minus_first = dd, diff_se = se_dd, diff_df = G_diff - 1L,
        diff_p_value = 2 * pt(-abs(dd / se_dd), G_diff - 1L)
      )
    }))
  }))
}))

# ---- Season-by-season estimates and partial pooling -----------------------
message("18: season-specific estimates and shrinkage")
# Correlated normal-normal empirical Bayes. Keep the full covariance of the
# jointly estimated season coefficients, including shared nuisance controls.
# Intervals condition on estimated heterogeneity; they are not headline CIs.
p18_meta <- function(theta, V) {
  S <- length(theta)
  one <- rep(1, S)
  identity <- diag(S)
  moments <- function(t2) {
    sigma <- V + t2 * identity
    ch <- chol(sigma)
    W <- chol2inv(ch)
    wone <- drop(W %*% one)
    information <- sum(wone)
    mu <- sum(wone * theta) / information
    residual <- theta - mu
    Q <- drop(crossprod(residual, W %*% residual))
    list(W = W, mu = mu, information = information, Q = Q,
         logdet = 2 * sum(log(diag(ch))), wone = wone)
  }
  at_zero <- moments(0)
  Q <- at_zero$Q
  q_p <- pchisq(Q, S - 1, lower.tail = FALSE)
  I2 <- if (Q > 0) max(0, (Q - (S - 1)) / Q) else 0
  P <- at_zero$W - tcrossprod(at_zero$wone) / at_zero$information
  tau2_dl <- max(0, (Q - (S - 1)) / sum(diag(P)))
  reml_nll <- function(t2) {
    m <- moments(t2)
    0.5 * (m$logdet + log(m$information) + m$Q)
  }
  top <- max(1e-6, 50 * var(theta))
  opt <- optimize(reml_nll, c(0, top))
  tau2_reml <- if (reml_nll(0) <= opt$objective) 0 else opt$minimum
  solve_tau2 <- function(target) {
    if (Q <= target) return(0)
    hi <- top
    while (moments(hi)$Q > target) hi <- hi * 10
    uniroot(function(t) moments(t)$Q - target, c(0, hi))$root
  }
  tau2_low <- solve_tau2(qchisq(1 - p18_alpha / 2, S - 1))
  tau2_high <- solve_tau2(qchisq(p18_alpha / 2, S - 1))
  shrink <- function(t2) {
    m <- moments(t2)
    A <- t2 * m$W
    mean_weight <- drop((identity - A) %*% one)
    posterior <- t2 * identity - t2^2 * m$W +
      tcrossprod(mean_weight) / m$information
    list(mu = m$mu, se_mu = sqrt(1 / m$information),
         B = mean_weight,
         est = m$mu + drop(A %*% (theta - m$mu)),
         sd = sqrt(diag(posterior)))
  }
  list(S = S, Q = Q, q_df = S - 1, q_p = q_p, I2 = I2,
       tau2_dl = tau2_dl, tau2_reml = tau2_reml,
       tau2_low = tau2_low, tau2_high = tau2_high,
       at_reml = shrink(tau2_reml), at_high = shrink(tau2_high))
}

p18_season <- rbindlist(lapply(p18_outcomes$outcome, function(oc) {
  d <- p18_ucl[p18_rows(oc, "common")]
  rhs <- "i(season_start, real_madrid) + barca + other_elite + p18_venue"
  m <- p18_fit(p18_formula(oc, p18_main_spec, rhs), d, paste(oc, "by season"))
  d_used <- d[obs(m)]
  bb <- coef(m)
  V <- vcov(m, cluster = ~event_id)     # match-pair clusters within season
  idx <- grep("^season_start::\\d{4}:real_madrid$", names(bb))
  seasons <- as.integer(sub("^season_start::(\\d{4}):real_madrid$", "\\1", names(bb)[idx]))
  n_s <- d_used[real_madrid == 1L, .N, by = season_start]
  n_s <- n_s[match(seasons, season_start)]$N
  theta <- unname(bb[idx])
  se <- sqrt(diag(V)[idx])
  # Raw intervals use t(n_s - 1): the effective clusters behind a season
  # coefficient are that season's Real Madrid matches, not the whole sample.
  tc <- qt(1 - p18_alpha / 2, n_s - 1L)
  meta <- p18_meta(theta, V[idx, idx, drop = FALSE])
  pooled <- p18_ladder[outcome == oc & spec == p18_main_spec & sample == "common" &
                         contrast == "rm_vs_nonelite"]
  data.table(
    outcome = oc, spec = p18_main_spec, season_start = seasons,
    season = season_label(seasons), n_rm_matches = n_s,
    raw_estimate = theta, raw_se = se, raw_df = n_s - 1L,
    raw_ci95_low = theta - tc * se, raw_ci95_high = theta + tc * se,
    shrunk_estimate = meta$at_reml$est, shrunk_sd = meta$at_reml$sd,
    shrink_weight_to_mean = meta$at_reml$B,
    shrunk_estimate_tau_high = meta$at_high$est, shrunk_sd_tau_high = meta$at_high$sd,
    re_mean = meta$at_reml$mu, re_mean_se = meta$at_reml$se_mu,
    tau2_reml = meta$tau2_reml, tau2_dl = meta$tau2_dl,
    tau2_ci_low = meta$tau2_low, tau2_ci_high = meta$tau2_high,
    tau_reml = sqrt(meta$tau2_reml), tau_ci_high = sqrt(meta$tau2_high),
    het_Q = meta$Q, het_Q_df = meta$q_df, het_Q_p = meta$q_p, het_I2 = meta$I2,
    n_seasons = meta$S,
    pooled_estimate = pooled$estimate, pooled_ci95_low = pooled$ci95_low,
    pooled_ci95_high = pooled$ci95_high
  )
}))
p18_season[, `:=`(raw_estimate_per10 = p18_per_games * raw_estimate,
                  raw_ci95_low_per10 = p18_per_games * raw_ci95_low,
                  raw_ci95_high_per10 = p18_per_games * raw_ci95_high,
                  shrunk_estimate_per10 = p18_per_games * shrunk_estimate,
                  shrunk_ci95_low_per10 = p18_per_games * (shrunk_estimate - qnorm(0.975) * shrunk_sd),
                  shrunk_ci95_high_per10 = p18_per_games * (shrunk_estimate + qnorm(0.975) * shrunk_sd),
                  tau_per10 = p18_per_games * tau_reml,
                  tau_ci_high_per10 = p18_per_games * tau_ci_high)]

# ---- Leave-one-season-out --------------------------------------------------
message("18: leave-one-season-out")
p18_loso <- rbindlist(lapply(p18_outcomes$outcome, function(oc) {
  d <- p18_ucl[p18_rows(oc, "common")]
  rbindlist(lapply(c("prematch", "style"), function(sp) {
    full <- p18_ladder[outcome == oc & spec == sp & sample == "common"]
    rbindlist(lapply(sort(unique(d[real_madrid == 1L]$season_start)), function(s) {
      ds <- d[season_start != s]
      m <- p18_fit(p18_formula(oc, sp), ds, sprintf("%s/%s/drop %d", oc, sp, s))
      ds_used <- ds[obs(m)]
      rbindlist(lapply(c("rm_vs_nonelite", "rm_vs_other_elite"), function(k) {
        kk <- p18_contrasts[contrast == k]
        ct <- p18_contrast(m, kk$a, kk$b, ds_used)
        inf <- p18_infer(ct$est, ct$se_season, ct$df)
        f <- full[contrast == k]
        data.table(
          outcome = oc, spec = sp, contrast = k, dropped_season_start = s,
          dropped_season = season_label(s),
          n_rm_matches_dropped = sum(d$real_madrid * (d$season_start == s)),
          estimate = ct$est, se = ct$se_season, df = ct$df,
          ci95_low = inf$ci95_low, ci95_high = inf$ci95_high, p_value = inf$p_value,
          estimate_per10 = p18_per_games * ct$est,
          ci95_low_per10 = p18_per_games * inf$ci95_low,
          ci95_high_per10 = p18_per_games * inf$ci95_high,
          full_estimate_per10 = f$estimate_per10,
          full_ci95_low_per10 = f$ci95_low_per10,
          full_ci95_high_per10 = f$ci95_high_per10,
          delta_per10 = p18_per_games * (ct$est - f$estimate),
          n_rm_matches = sum(ds_used$real_madrid), n_seasons = ct$n_seasons
        )
      }))
    }))
  }))
}))
p18_loso[, `:=`(loso_min_per10 = min(estimate_per10), loso_max_per10 = max(estimate_per10),
                loso_range_per10 = max(estimate_per10) - min(estimate_per10),
                loso_max_abs_delta_per10 = max(abs(delta_per10)),
                loso_sign_changes = sum(sign(estimate) != sign(full_estimate_per10)),
                loso_all_ci_cover_zero = as.integer(all(ci95_low <= 0 & ci95_high >= 0)),
                loso_none_ci_cover_zero = as.integer(all(ci95_low > 0 | ci95_high < 0))),
         by = .(outcome, spec, contrast)]
p18_loso[, main_spec := as.integer(spec == p18_main_spec)]

# ---- Cumulative pooling: precision as seasons accumulate -------------------
# Chronological accumulation only, no reordering and no significance scan:
# the manifest keeps the point estimates, the figure plots interval widths.
message("18: cumulative precision")
p18_cumulative <- rbindlist(lapply(p18_outcomes$outcome, function(oc) {
  d <- p18_ucl[p18_rows(oc, "common")]
  seasons <- sort(unique(d[real_madrid == 1L]$season_start))
  if (length(seasons) < 3L) stop(sprintf("18: fewer than 3 seasons for %s", oc), call. = FALSE)
  season_ref <- p18_season[outcome == oc]
  single <- median(p18_per_games * qt(1 - p18_alpha / 2, season_ref$raw_df) * season_ref$raw_se)
  rbindlist(lapply(3:length(seasons), function(k) {
    dk <- d[season_start <= seasons[k]]
    m <- p18_fit(p18_formula(oc, p18_main_spec), dk, sprintf("%s/cumulative %d", oc, k))
    dk_used <- dk[obs(m)]
    rbindlist(lapply(c("rm_vs_nonelite", "rm_vs_other_elite"), function(ctr) {
      kk <- p18_contrasts[contrast == ctr]
      ct <- p18_contrast(m, kk$a, kk$b, dk_used)
      inf <- p18_infer(ct$est, ct$se_season, ct$df)
      data.table(
        outcome = oc, spec = p18_main_spec, contrast = ctr,
        seasons_pooled = ct$n_seasons, through_season_start = seasons[k],
        through_season = season_label(seasons[k]),
        n_rm_matches = sum(dk_used$real_madrid), n_rows = nrow(dk_used),
        estimate = ct$est, se = ct$se_season, df = ct$df,
        ci95_half_width_per10 = p18_per_games * inf$t_crit_95 * ct$se_season,
        mde_per10 = p18_per_games * inf$mde,
        single_season_half_width_per10 = single,
        estimate_per10 = p18_per_games * ct$est,
        ci95_low_per10 = p18_per_games * inf$ci95_low,
        ci95_high_per10 = p18_per_games * inf$ci95_high
      )
    }))
  }))
}))

# ---- Manifests --------------------------------------------------------------
p18_script_md5 <- unname(tools::md5sum(
  file.path(root, "programs", "18-champions-league-pooled-precision.R")))
p18_provenance <- function(dt) {
  dt <- copy(dt)
  dt[, `:=`(run_id = run_id, input_md5 = p18_input_md5, script_md5 = p18_script_md5,
            inference_primary = "season-block cluster, CR1, t(G-1)",
            unit = "team-match (120-minute matches count once)",
            alpha = p18_alpha, power = p18_power, per_games = p18_per_games,
            generated = format(Sys.time(), "%Y-%m-%d %H:%M:%S"))]
  dt
}
p18_write <- function(dt, name) {
  dt <- p18_provenance(dt)
  if (name == "by-season") {
    dt[, inference_primary := paste(
      "Raw: match-cluster t(n_RM-1); EB: correlated normal model,",
      "conditional on estimated REML heterogeneity")]
  }
  if (any(nchar(names(dt)) > 32L)) {
    stop(sprintf("18: Stata-incompatible column names in %s: %s", name,
                 paste(names(dt)[nchar(names(dt)) > 32L], collapse = ", ")),
         call. = FALSE)
  }
  path <- file.path(tables_wd, sprintf("%s-%s", p18_slug, name))
  fwrite(dt, paste0(path, ".csv"))
  df <- as.data.frame(dt)
  for (v in names(df)) {
    if (is.logical(df[[v]])) df[[v]] <- as.integer(df[[v]])
    if (is.factor(df[[v]])) df[[v]] <- as.character(df[[v]])
  }
  haven::write_dta(df, paste0(path, ".dta"))
  invisible(path)
}
p18_write(p18_ladder, "estimates")
p18_write(p18_equiv, "equivalence")
p18_write(p18_stage_era, "stage-era")
p18_write(p18_season, "by-season")
p18_write(p18_loso, "loso")
p18_write(p18_cumulative, "cumulative")

# ---- Figures ----------------------------------------------------------------
p18_outcome_levels <- p18_outcomes$label
p18_ladder[, outcome_f := factor(outcome_label, levels = p18_outcome_levels)]
p18_season[, outcome_f := factor(p18_outcomes$label[match(outcome, p18_outcomes$outcome)],
                                 levels = p18_outcome_levels)]
p18_loso[, outcome_f := factor(p18_outcomes$label[match(outcome, p18_outcomes$outcome)],
                               levels = p18_outcome_levels)]
p18_cumulative[, outcome_f := factor(p18_outcomes$label[match(outcome, p18_outcomes$outcome)],
                                     levels = p18_outcome_levels)]
p18_main <- p18_ladder[sample == "common" & spec == p18_main_spec & contrast == "rm_vs_nonelite"]
p18_fmt <- function(x, d = 2) formatC(x, format = "f", digits = d)
# Subtitles and captions are long; wrap to the figure width (characters)
p18_wrap <- function(x, width) paste(strwrap(x, width = width), collapse = "\n")
p18_nmat <- sprintf("%s Real Madrid matches in %d seasons (%s to %s)",
                    formatC(max(p18_main$n_rm_matches), big.mark = ","),
                    max(p18_main$n_rm_seasons),
                    season_label(min(p18_main$season_first_rm)),
                    season_label(max(p18_main$season_last_rm)))
p18_inference_note <- paste0(
  "Intervals: 95% season-block cluster (CR1) with t criticals on seasons minus one. ",
  "Positive = favorable to Real Madrid. Unit: team-match; matches with extra time count once.")

# Figure 1: pooled ladder, three contrasts
p18_fig1_dt <- p18_ladder[sample == "common" &
                            contrast %in% c("rm_vs_nonelite", "rm_vs_other_elite", "rm_vs_barca")]
p18_fig1_dt[, spec_f := factor(spec_label, levels = rev(p18_specs$label))]
p18_fig1_dt[, contrast_f := factor(contrast_label,
                                   levels = p18_contrasts$label[1:3])]
p18_fig1_colors <- c(colors_customs[["madrid"]], colors_customs[["elite"]], colors_customs[["barca"]])
names(p18_fig1_colors) <- p18_contrasts$label[1:3]
p18_fig1 <- ggplot(p18_fig1_dt, aes(x = estimate_per10, y = spec_f, colour = contrast_f)) +
  geom_vline(xintercept = 0, colour = "grey55", linewidth = 0.4) +
  geom_errorbar(aes(xmin = ci95_low_per10, xmax = ci95_high_per10),
                width = 0, linewidth = 0.6, position = position_dodge(width = 0.6)) +
  geom_point(size = 2.1, position = position_dodge(width = 0.6)) +
  facet_wrap(~outcome_f, scales = "free_x", ncol = 3) +
  scale_colour_manual(values = p18_fig1_colors) +
  labs(x = sprintf("Real Madrid gap per %d matches", p18_per_games), y = NULL, colour = NULL,
       title = "Real Madrid in the Champions League: pooled refereeing gaps",
       subtitle = p18_wrap(paste0("Same sample across the three columns: matches with valid ",
                                  "possession and shots. ", p18_nmat, "."), 120),
       caption = p18_wrap(paste0(
         "Raw: venue only. Pre-match: season, stage, opponent and Elo expected-score ventile ",
         "fixed effects. Style: adds own-possession bins and both teams' shots. These ",
         "same-match controls respond to decisions; the style column is descriptive. ",
         "'| fouls called' conditions net yellow cards on own and opponent fouls. ",
         p18_inference_note, " Source: ESPN."), 150)) +
  p18_theme(11) +
  theme(legend.position = "bottom")
save_figure(p18_fig1, "figure-rm-ucl-pooled-comparisons.pdf", width = 10, height = 7)

# Figure 2: what the design can resolve, pooled vs single season
p18_bounds_dt <- rbindlist(lapply(names(p18_bounds), function(oc) {
  data.table(outcome = oc, bound_label = p18_bound_labels, bound_per10 = p18_bounds[[oc]])
}))
p18_bounds_dt[, outcome_f := factor(p18_outcomes$label[match(outcome, p18_outcomes$outcome)],
                                    levels = p18_outcome_levels)]
p18_bounds_dt[, bound_f := factor(bound_label, levels = p18_bound_labels)]
p18_fig2_dt <- p18_cumulative[contrast == "rm_vs_nonelite"]
p18_fig2_single <- unique(p18_fig2_dt[, .(outcome_f, single_season_half_width_per10)])
p18_fig2 <- ggplot(p18_fig2_dt, aes(x = seasons_pooled)) +
  geom_hline(data = p18_bounds_dt, aes(yintercept = bound_per10, linetype = bound_f),
             colour = "grey45", linewidth = 0.4) +
  geom_hline(data = p18_fig2_single, aes(yintercept = single_season_half_width_per10),
             colour = colors_customs[["barca"]], linewidth = 0.5) +
  geom_line(aes(y = ci95_half_width_per10), colour = colors_customs[["madrid"]], linewidth = 0.9) +
  geom_line(aes(y = mde_per10), colour = colors_customs[["madrid"]], linewidth = 0.6,
            linetype = "dotdash") +
  geom_point(aes(y = ci95_half_width_per10), colour = colors_customs[["madrid"]], size = 1.6) +
  facet_wrap(~outcome_f, scales = "free_y", ncol = 3) +
  scale_linetype_manual(values = c(small = "dotted", medium = "dashed", large = "longdash"),
                        name = "Illustrative bound") +
  scale_x_continuous(breaks = seq(3, max(p18_fig2_dt$seasons_pooled), 2)) +
  expand_limits(y = 0) +
  labs(x = "Seasons pooled (chronological, from the first season with possession data)",
       y = sprintf("Per %d matches", p18_per_games),
       title = "What the Champions League sample can resolve for Real Madrid",
       subtitle = p18_wrap(paste0(
         "Gold solid: 95% CI half-width of the pooled style-adjusted gap vs non-elite clubs. ",
         "Gold dot-dash: minimum detectable effect (80% power, 5% two-sided). ",
         "Red: median single-season 95% CI half-width. Grey lines: illustrative ",
         "equivalence bounds, not claims about relevance."), 120),
       caption = p18_wrap(paste0(
         "Each point refits the pooled model on all matches through that season; ",
         "no matches are added or reweighted. Precision gains come from more seasons and ",
         "from larger t criticals relaxing as clusters grow. ",
         p18_inference_note, " Source: ESPN."), 150)) +
  p18_theme(11) +
  theme(legend.position = "bottom")
save_figure(p18_fig2, "figure-rm-ucl-precision-limits.pdf", width = 10, height = 7)

# Figure 3: season estimates with shrinkage (left) and leave-one-season-out (right)
p18_het <- unique(p18_season[, .(outcome, outcome_f, het_Q_p, het_I2, tau_per10,
                                 tau_ci_high_per10, n_seasons)])
p18_het[, lab := sprintf("Q p = %s; I2 = %s%%; tau = %s per %d (upper %s)",
                         p18_fmt(het_Q_p, 2), p18_fmt(100 * het_I2, 0),
                         p18_fmt(tau_per10, 2), p18_per_games, p18_fmt(tau_ci_high_per10, 2))]
# One band per facet: mapping the band from the season rows would stack
# alpha layers and darken the band with the number of seasons.
p18_fig3a_band <- unique(p18_season[, .(outcome_f, pooled_estimate, pooled_ci95_low,
                                        pooled_ci95_high)])
p18_fig3a <- ggplot(p18_season, aes(x = season_start)) +
  geom_rect(data = p18_fig3a_band,
            aes(xmin = -Inf, xmax = Inf, ymin = p18_per_games * pooled_ci95_low,
                ymax = p18_per_games * pooled_ci95_high),
            fill = colors_customs[["madrid"]], alpha = 0.15, inherit.aes = FALSE) +
  geom_hline(data = p18_fig3a_band, aes(yintercept = p18_per_games * pooled_estimate),
             colour = colors_customs[["madrid"]], linewidth = 0.5) +
  geom_hline(yintercept = 0, colour = "grey55", linewidth = 0.4) +
  geom_linerange(aes(ymin = raw_ci95_low_per10, ymax = raw_ci95_high_per10),
                 colour = "grey60", linewidth = 0.5) +
  geom_point(aes(y = raw_estimate_per10, shape = "Raw season estimate, 95% CI, t(n - 1)"),
             colour = "grey35", size = 1.6) +
  geom_linerange(aes(ymin = shrunk_ci95_low_per10, ymax = shrunk_ci95_high_per10),
                 colour = colors_customs[["elite"]], linewidth = 0.9,
                 position = position_nudge(x = 0.3)) +
  geom_point(aes(y = shrunk_estimate_per10,
                 shape = "Empirical-Bayes shrunk estimate (model-based interval)"),
             colour = colors_customs[["elite"]], size = 1.8, position = position_nudge(x = 0.3)) +
  geom_text(data = p18_het, aes(x = -Inf, y = Inf, label = lab), hjust = -0.02, vjust = 1.4,
            size = 2.6, colour = "grey30", inherit.aes = FALSE) +
  facet_wrap(~outcome_f, scales = "free_y", ncol = 1) +
  scale_shape_manual(values = c(16, 18), name = NULL) +
  scale_x_continuous(breaks = seq(min(p18_season$season_start), max(p18_season$season_start), 2),
                     labels = season_label) +
  labs(x = "Season", y = sprintf("Real Madrid gap vs non-elite clubs, per %d matches", p18_per_games),
       title = "A. Season estimates and partial pooling") +
  p18_theme(10) +
  theme(axis.text.x = element_text(angle = 45, hjust = 1), legend.position = "bottom",
        legend.direction = "vertical")
p18_fig3b_dt <- p18_loso[spec == p18_main_spec & contrast == "rm_vs_nonelite"]
p18_fig3b_band <- unique(p18_fig3b_dt[, .(outcome_f, full_estimate_per10, full_ci95_low_per10,
                                          full_ci95_high_per10)])
p18_fig3b <- ggplot(p18_fig3b_dt, aes(x = dropped_season_start)) +
  geom_rect(data = p18_fig3b_band,
            aes(xmin = -Inf, xmax = Inf, ymin = full_ci95_low_per10, ymax = full_ci95_high_per10),
            fill = colors_customs[["madrid"]], alpha = 0.15, inherit.aes = FALSE) +
  geom_hline(data = p18_fig3b_band, aes(yintercept = full_estimate_per10),
             colour = colors_customs[["madrid"]], linewidth = 0.5) +
  geom_hline(yintercept = 0, colour = "grey55", linewidth = 0.4) +
  geom_linerange(aes(ymin = ci95_low_per10, ymax = ci95_high_per10),
                 colour = colors_customs[["madrid"]], linewidth = 0.6) +
  geom_point(aes(y = estimate_per10), colour = colors_customs[["madrid"]], size = 1.6) +
  facet_wrap(~outcome_f, scales = "free_y", ncol = 1) +
  scale_x_continuous(breaks = seq(min(p18_fig3b_dt$dropped_season_start),
                                  max(p18_fig3b_dt$dropped_season_start), 2),
                     labels = season_label) +
  labs(x = "Season dropped", y = NULL, title = "B. Leave-one-season-out pooled estimates") +
  p18_theme(10) +
  theme(axis.text.x = element_text(angle = 45, hjust = 1))
p18_fig3 <- (p18_fig3a | p18_fig3b) +
  plot_annotation(
    title = "Does the pooled Real Madrid estimate depend on one season?",
    subtitle = p18_wrap(paste0(
      "Gold line and band: pooled style-adjusted estimate with its 95% season-block CI. ",
      "Shrinkage is empirical Bayes at the REML tau; its intervals condition on ",
      "the estimated tau and understate uncertainty when tau is near zero. ",
      "Q tests heterogeneity; I2 summarizes dispersion beyond sampling noise."), 150),
    caption = p18_wrap(paste0(
      "Left: season coefficients from one model with season x Real Madrid interactions, ",
      "match-pair clustered SEs, t(n - 1) with n the season's Real Madrid matches. ",
      "Right: refits of the pooled model without each season. ",
      p18_inference_note, " Source: ESPN."), 180))
# Trap (Oct 2026): patchwork 1.3.1 rejects any `theme =` argument under
# ggplot2 4.0 ("annotation$theme is not a valid theme") and falls back to
# theme_get(); style the annotation by setting the default theme briefly.
p18_theme_prev <- theme_set(p18_theme(12) +
                              theme(plot.subtitle = element_text(size = 10),
                                    plot.caption = element_text(size = 8)))
save_figure(p18_fig3, "figure-rm-ucl-season-stability.pdf", width = 12, height = 12)
theme_set(p18_theme_prev)

# ---- LaTeX table ------------------------------------------------------------
p18_stars <- function(p) if (p < 0.01) "$^{***}$" else if (p < 0.05) "$^{**}$" else if (p < 0.1) "$^{*}$" else ""
p18_cell <- function(r) {
  c(sprintf("%s%s", p18_fmt(r$estimate_per10, 2), p18_stars(r$p_value)),
    sprintf("[%s, %s]", p18_fmt(r$ci95_low_per10, 2), p18_fmt(r$ci95_high_per10, 2)))
}
p18_tex_rows <- unlist(lapply(p18_outcomes$outcome, function(oc) {
  cells <- lapply(c("rm_vs_nonelite", "rm_vs_other_elite"), function(k) {
    lapply(p18_specs$spec, function(sp) {
      p18_cell(p18_ladder[outcome == oc & spec == sp & sample == "common" & contrast == k])
    })
  })
  main <- p18_ladder[outcome == oc & spec == p18_main_spec & sample == "common" &
                       contrast == "rm_vs_nonelite"]
  line1 <- c(p18_outcomes[outcome == oc]$label,
             vapply(unlist(cells, recursive = FALSE), `[`, character(1), 1),
             sprintf("%d / %d", main$n_rm_matches, main$n_rm_seasons),
             p18_fmt(main$mde_per10, 2), p18_fmt(main$equiv_margin_per10, 2))
  line2 <- c("", vapply(unlist(cells, recursive = FALSE), `[`, character(1), 2),
             "", "", "")
  c(paste(paste(line1, collapse = " & "), "\\\\"),
    paste(paste(line2, collapse = " & "), "\\\\[2pt]"))
}))
p18_tex <- c(
  "\\begin{table}[H]",
  "\\centering",
  sprintf("\\caption{Real Madrid's Champions League Gaps per %d Matches: Pooled Estimates and Detectable Effects \\label{tab:rmuclpooled}}", p18_per_games),
  "\\resizebox{\\textwidth}{!}{%",
  "\\begin{tabular}{lcccccccccc}",
  "\\toprule",
  " & \\multicolumn{3}{c}{vs non-elite clubs} & \\multicolumn{3}{c}{vs other elite clubs} & RM matches & MDE & Equiv. \\\\",
  "\\cmidrule(lr){2-4} \\cmidrule(lr){5-7}",
  " & Raw & Pre-match & Style & Raw & Pre-match & Style & / seasons & per 10 & margin \\\\",
  "\\midrule",
  p18_tex_rows,
  "\\bottomrule",
  "\\end{tabular}}",
  "\\begin{minipage}{\\textwidth}\\footnotesize\\raggedright",
  paste0("\\textit{Notes:} Champions League group/league-phase and knockout team-matches with valid ",
         "possession shares; Real Madrid plays in ", season_label(min(p18_main$season_first_rm)),
         "--", season_label(max(p18_main$season_last_rm)), ". Coefficients are per-match gaps multiplied ",
         "by ", p18_per_games, ", positive when favorable to Real Madrid; a match that went to ",
         "extra time counts once. Raw controls for venue only; pre-match adds season, stage, ",
         "opponent and Elo expected-score ventile fixed effects; style adds 2.5-point ",
         "own-possession bins and both teams' shots, a conditional association rather than a bias estimate. ",
         "``Net yellow cards $|$ fouls called'' adds own and opponent fouls as controls. ",
         "Brackets: 95 percent confidence intervals from standard errors clustered by season ",
         "with $t$ criticals on the number of seasons minus one. MDE: minimum detectable effect ",
         "at 80 percent power and 5 percent two-sided size for the style column vs non-elite ",
         "clubs. Equiv.\\ margin: the smallest symmetric bound within which the style estimate is ",
         "TOST-equivalent at 5 percent (the wider end of the 90 percent interval). ",
         "$^{*}p<0.1$, $^{**}p<0.05$, $^{***}p<0.01$ against the season-block $t$ distribution. ",
         "Source: ESPN. Run ", run_id, "."),
  "\\end{minipage}",
  "\\end{table}"
)
for (p18_d in c(tables_wd, paper_tables)) {
  writeLines(p18_tex, file.path(p18_d, "table-rm-ucl-pooled-precision.tex"))
}

# ---- Results fragment -------------------------------------------------------
p18_verdict <- function(p) {
  if (p < 0.01) "statistically significant at the one percent level"
  else if (p < 0.05) "statistically significant at the five percent level"
  else if (p < 0.1) "marginally significant at the ten percent level"
  else "statistically indistinguishable from zero"
}
p18_num <- function(x, d = 2) sprintf("$%s$", p18_fmt(x, d))
p18_ci <- function(r) sprintf("95 percent CI $%s$ to $%s$", p18_fmt(r$ci95_low_per10, 2),
                              p18_fmt(r$ci95_high_per10, 2))
p18_row <- function(oc, k = "rm_vs_nonelite", sp = p18_main_spec, smp = "common") {
  p18_ladder[outcome == oc & spec == sp & sample == smp & contrast == k]
}
p18_sentence <- function(oc) {
  r <- p18_row(oc); rp <- p18_row(oc, sp = "prematch"); re <- p18_row(oc, k = "rm_vs_other_elite")
  o <- p18_outcomes[outcome == oc]
  sprintf(paste0(
    "For %s, the style-adjusted gap is %s %s per %d matches (%s), equal in magnitude to %s percent of the ",
    "non-elite rate of %s per match, and %s; the pre-match estimate is %s, and the gap ",
    "relative to the other elite clubs is %s (%s, $p = %s$)."),
    tolower(o$label), p18_num(r$estimate_per10), o$unit, p18_per_games, p18_ci(r),
    p18_fmt(abs(100 * r$estimate / r$baseline_nonelite), 0), p18_fmt(r$baseline_nonelite, 2),
    p18_verdict(r$p_value), p18_num(rp$estimate_per10), p18_num(re$estimate_per10),
    p18_ci(re), p18_fmt(re$p_value, 3))
}
p18_loso_main <- unique(p18_loso[spec == p18_main_spec & contrast == "rm_vs_nonelite",
                                 .(outcome, loso_min_per10, loso_max_per10, loso_sign_changes,
                                   loso_all_ci_cover_zero, loso_none_ci_cover_zero)])
p18_loso_phrase <- function(oc) {
  l <- p18_loso_main[outcome == oc]
  stab <- if (l$loso_all_ci_cover_zero == 1L) "every refit covers zero"
          else if (l$loso_none_ci_cover_zero == 1L) "no refit covers zero"
          else "the refits straddle the five percent boundary"
  sprintf("%s ($%s$ to $%s$; %s)", tolower(p18_outcomes[outcome == oc]$label),
          p18_fmt(l$loso_min_per10, 2), p18_fmt(l$loso_max_per10, 2), stab)
}
p18_yel <- p18_row("net_yellow"); p18_pen <- p18_row("net_pens")
p18_het_y <- p18_het[outcome == "net_yellow"]
p18_ne <- p18_ladder[sample == "no_extra_time" & spec == p18_main_spec & contrast == "rm_vs_nonelite"]
p18_fragment <- c(
  "% Generated by programs/18-champions-league-pooled-precision.R; do not edit by hand.",
  sprintf("%% run_id %s, input md5 %s", run_id, p18_input_md5),
  "",
  paste0(
    "Table \\ref{tab:rmuclpooled} pools every Champions League season with possession data and ",
    "reports Real Madrid's gaps per ", p18_per_games, " matches, with intervals clustered by season ",
    "and $t$ criticals on ", max(p18_main$n_rm_seasons) - 1L, " degrees of freedom; the sample is ",
    formatC(max(p18_main$n_rm_matches), big.mark = ","), " Real Madrid matches in ",
    max(p18_main$n_rm_seasons), " seasons, with the same matches behind the raw, pre-match and ",
    "style-adjusted columns. ",
    paste(vapply(c("net_yellow", "net_fouls", "net_pens", "net_red"), p18_sentence, character(1)),
          collapse = " "), " ",
    "Conditional on the fouls called, the net yellow-card gap is ",
    p18_num(p18_row("net_yellow_fouls")$estimate_per10), " cards per ", p18_per_games, " matches (",
    p18_ci(p18_row("net_yellow_fouls")), "), ", p18_verdict(p18_row("net_yellow_fouls")$p_value), ". ",
    "Dropping the ", p18_yel$n_rm_extra_time, " Real Madrid matches that went to extra time moves the net ",
    "yellow-card estimate to ", p18_num(p18_ne[outcome == "net_yellow"]$estimate_per10),
    " and the net penalty estimate to ", p18_num(p18_ne[outcome == "net_pens"]$estimate_per10), "."),
  "",
  paste0(
    "A null is informative only in proportion to what the sample could detect, so Figure ",
    "\\ref{fig:rmuclprecision} traces precision as seasons accumulate. Pooled over all seasons, ",
    "the design detects, with 80 percent power, a net yellow-card gap of ",
    p18_num(p18_yel$mde_per10), " cards per ", p18_per_games, " matches (",
    p18_fmt(p18_yel$mde_pct_baseline, 0), " percent of the non-elite rate) and a net penalty gap of ",
    p18_num(p18_pen$mde_per10), " penalties per ", p18_per_games, " matches (",
    p18_fmt(p18_pen$mde_pct_baseline, 0), " percent); a single season resolves roughly ",
    p18_num(p18_cumulative[outcome == "net_yellow"]$single_season_half_width_per10[1]),
    " cards and ", p18_num(p18_cumulative[outcome == "net_pens"]$single_season_half_width_per10[1]),
    " penalties at the same confidence. The 90 percent intervals rule out net yellow-card gaps ",
    "beyond ", p18_num(p18_yel$equiv_margin_per10), " cards and net penalty gaps beyond ",
    p18_num(p18_pen$equiv_margin_per10), " penalties per ", p18_per_games,
    " matches in either direction; these are equivalence margins against stated bounds, not ",
    "evidence of no bias. Figure \\ref{fig:rmuclstability} shows that the pooled estimates do not ",
    "rest on one season: leaving out each season in turn moves the net yellow-card gap across ",
    p18_loso_phrase("net_yellow"), ", net fouls across ", p18_loso_phrase("net_fouls"),
    ", and net penalties across ", p18_loso_phrase("net_pens"), ". The season estimates themselves ",
    "are ", if (p18_het_y$het_Q_p < 0.05) "more dispersed than sampling noise alone implies"
            else "statistically indistinguishable from a common mean", " for net yellow cards ",
    "(heterogeneity $Q$ test $p = ", p18_fmt(p18_het_y$het_Q_p, 2), "$, $I^2 = ",
    p18_fmt(100 * p18_het_y$het_I2, 0), "$ percent, between-season standard deviation ",
    p18_num(p18_het_y$tau_per10), " cards per ", p18_per_games, " matches with an upper bound of ",
    p18_num(p18_het_y$tau_ci_high_per10), "), which is why the shrunk season estimates in the ",
    "figure sit close to the pooled line; their intervals condition on the estimated between-season ",
    "variance and are model-based rather than design-based.")
)
writeLines(p18_fragment, file.path(p18_fragments, "results-real-madrid-pooled-precision.tex"))

# ---- Run metadata -----------------------------------------------------------
p18_run <- data.table(
  run_id = run_id, script = "18-champions-league-pooled-precision.R",
  script_md5 = p18_script_md5, input_file = "data/datasets/team-match-panel.csv",
  input_md5 = p18_input_md5, r_version = R.version.string,
  fixest_version = as.character(packageVersion("fixest")),
  data_table_version = as.character(packageVersion("data.table")),
  main_spec = p18_main_spec, alpha = p18_alpha, power = p18_power,
  per_games = p18_per_games,
  n_ucl_rows = nrow(p18_ucl), n_ucl_matches = uniqueN(p18_ucl$event_id),
  n_common_rows_net_yellow = p18_main[outcome == "net_yellow"]$n_rows,
  n_rm_matches_net_yellow = p18_main[outcome == "net_yellow"]$n_rm_matches,
  n_rm_seasons_net_yellow = p18_main[outcome == "net_yellow"]$n_rm_seasons,
  n_rm_matches_net_pens = p18_main[outcome == "net_pens"]$n_rm_matches,
  n_rm_seasons_net_pens = p18_main[outcome == "net_pens"]$n_rm_seasons,
  n_rm_extra_time = p18_main[outcome == "net_yellow"]$n_rm_extra_time,
  n_models = length(p18_models) + nrow(p18_loso) / 2L +
    nrow(p18_cumulative) / 2L + nrow(p18_stage_era) / 2L + nrow(p18_outcomes),
  generated = format(Sys.time(), "%Y-%m-%d %H:%M:%S")
)
fwrite(p18_run, file.path(tables_wd, sprintf("%s-run.csv", p18_slug)))

message(sprintf("18: done. Real Madrid style-adjusted gaps per %d matches (vs non-elite):",
                p18_per_games))
for (i in seq_len(nrow(p18_main))) {
  message(sprintf("    %-32s %6.2f [%6.2f, %6.2f]  p = %.3f  seasons = %d  matches = %d",
                  p18_main$outcome_label[i], p18_main$estimate_per10[i],
                  p18_main$ci95_low_per10[i], p18_main$ci95_high_per10[i],
                  p18_main$p_value[i], p18_main$n_rm_seasons[i], p18_main$n_rm_matches[i]))
}
