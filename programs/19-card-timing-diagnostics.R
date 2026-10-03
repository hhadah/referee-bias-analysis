#!/usr/bin/env Rscript

# Compare net yellow cards in the first 30 minutes with full-match net cards
# on the same independently reconciled event-log sample. Run after 17 and 18
# in 95-make-all.R. This diagnostic is not a test of whether calls were correct.
# Results -> output/tables/card-timing-*.csv/.dta,
#            output/figures/card-timing-diagnostic.pdf/.png
# Raw event logs are read only; missing card timelines are never zero-filled
# unless their total reconciles to the box score on both sides of the match.

ct_panel <- data.table::as.data.table(load_panel())
ct_events <- data.table::fread(file.path(datasets, "espn-key-events.csv"),
  colClasses = c(event_id = "character", team_id = "character"))
ct_hash <- unname(tools::md5sum(file.path(datasets, "team-match-panel.csv")))
ct_event_hash <- unname(tools::md5sum(
  file.path(datasets, "espn-key-events.csv")))
ct_cards <- ct_events[type == "Yellow Card" & !shootout &
                       (is.na(period) | period <= 4),
  .(logged_yellow = .N,
    early_yellow = sum(period == 1 & clock_sec > 0 & clock_sec <= 1800,
                       na.rm = TRUE),
    clocks_valid = all(is.finite(clock_sec) & clock_sec > 0 &
                         !is.na(period))), by = .(event_id, team_id)]
ct_panel <- merge(ct_panel, ct_cards, by = c("event_id", "team_id"),
                  all.x = TRUE, sort = FALSE)
ct_panel[is.na(logged_yellow), `:=`(logged_yellow = 0L,
  early_yellow = 0L, clocks_valid = TRUE)]
ct_panel[, card_timeline_ok := all(clocks_valid &
  !is.na(own_yellow) & logged_yellow == own_yellow) &
  all(goals_ok & event_log_has_end), by = event_id]
ct_other <- ct_panel[, .(event_id, opp_id = team_id,
                         opponent_early_yellow = early_yellow)]
ct_panel <- merge(ct_panel, ct_other, by = c("event_id", "opp_id"),
                  all.x = TRUE, sort = FALSE)
ct_panel[, early_net_yellow := opponent_early_yellow - early_yellow]

# Only information from the preceding five matches in this competition.
# Reset within season so a promoted/new entrant is not assigned stale style.
data.table::setorder(ct_panel, league, team_id, season_start, date, event_id)
ct_panel[, `:=`(
  lag_possession = data.table::shift(data.table::frollmean(own_possession, 5)),
  lag_shots = data.table::shift(data.table::frollmean(own_shots, 5))
), by = .(league, team_id, season_start)]
ct_lags <- ct_panel[, .(event_id, opp_id = team_id,
  opp_lag_possession = lag_possession, opp_lag_shots = lag_shots)]
ct_panel <- merge(ct_panel, ct_lags, by = c("event_id", "opp_id"),
                  all.x = TRUE, sort = FALSE)
ct_panel[, competition_group := ifelse(league == "esp.1", "La Liga",
  ifelse(league == "uefa.champions", "Champions League", NA_character_))]
ct_panel <- ct_panel[!is.na(competition_group) & season_start >= 2011]
ct_coverage <- ct_panel[, .(n_team_matches = .N,
  n_matches = uniqueN(event_id),
  matches_with_reconciled_cards = uniqueN(event_id[card_timeline_ok]),
  non_extra_time_matches = uniqueN(event_id[card_timeline_ok & !extra_time])
), by = .(competition_group, season_start)]
ct_rows <- list()
ct_index <- 0L
for (ct_comp in c("La Liga", "Champions League")) {
  ct_data <- ct_panel[competition_group == ct_comp & card_timeline_ok &
                       !extra_time]
  ct_strength <- if (ct_comp == "La Liga") "prob_win" else "elo_exp"
  ct_required <- c(ct_strength, "lag_possession", "lag_shots",
    "opp_lag_possession", "opp_lag_shots", "net_yellow", "early_net_yellow")
  ct_data <- ct_data[complete.cases(ct_data[, ..ct_required])]
  ct_target <- if (ct_comp == "La Liga") "barca" else "real_madrid"
  ct_g <- uniqueN(ct_data$season_start)
  if (ct_g < 6L || sum(ct_data[[ct_target]]) < 30L) {
    stop(sprintf("Insufficient card timeline support for %s", ct_comp),
         call. = FALSE)
  }
  ct_stage <- if (ct_comp == "Champions League") " + ucl_stage" else ""
  ct_rhs <- paste0("barca + real_madrid + other_elite + home + ",
    "splines::ns(", ct_strength, ", 3) + ",
    "lag_possession + opp_lag_possession + lag_shots + opp_lag_shots",
    " | season_start + opp_id", ct_stage)
  for (ct_y in c("early_net_yellow", "net_yellow")) {
    ct_fit <- tryCatch(fixest::feols(
      as.formula(paste(ct_y, "~", ct_rhs)), data = ct_data,
      vcov = ~season_start, fixef.rm = "none", notes = FALSE),
      error = function(e) stop(sprintf("Card timing %s/%s: %s", ct_comp,
        ct_y, conditionMessage(e)), call. = FALSE))
    if (nobs(ct_fit) != nrow(ct_data)) {
      stop("Card timing sample changed during estimation.", call. = FALSE)
    }
    ct_b <- coef(ct_fit)
    ct_v <- vcov(ct_fit)
    ct_w <- setNames(numeric(length(ct_b)), names(ct_b))
    ct_w[ct_target] <- 1
    ct_comparator <- if (ct_comp == "La Liga") "Real Madrid" else "Other elite clubs"
    ct_w[if (ct_comp == "La Liga") "real_madrid" else "other_elite"] <- -1
    ct_est <- sum(ct_w * ct_b)
    ct_se <- sqrt(drop(t(ct_w) %*% ct_v %*% ct_w))
    ct_crit <- qt(0.975, ct_g - 1L)
    ct_index <- ct_index + 1L
    ct_rows[[ct_index]] <- data.frame(
      competition = ct_comp,
      target = if (ct_comp == "La Liga") "Barcelona" else "Real Madrid",
      comparator = ct_comparator, outcome = ct_y,
      estimate = ct_est, std_error = ct_se,
      conf_low = ct_est - ct_crit * ct_se,
      conf_high = ct_est + ct_crit * ct_se,
      p_value = 2 * pt(-abs(ct_est / ct_se), ct_g - 1L),
      n_rows = nobs(ct_fit), n_matches = uniqueN(ct_data$event_id),
      n_target_matches = sum(ct_data[[ct_target]]), n_seasons = ct_g,
      first_season = min(ct_data$season_start),
      last_season = max(ct_data$season_start),
      baseline_own_yellow = mean(ct_data$own_yellow[ct_data[[ct_target]] == 0]),
      estimator = "OLS; pre-match strength and prior-five-match style",
      inference = "Season-block cluster; t(G-1); descriptive selected sample",
      scale = "Net opponent-minus-own yellows per match; positive favorable",
      run_id = run_id, input_md5 = ct_hash, events_md5 = ct_event_hash,
      stringsAsFactors = FALSE)
  }
}
ct_results <- data.table::rbindlist(ct_rows)
ct_results[, p_holm := p.adjust(p_value, "holm")]
ct_coverage[, `:=`(run_id = run_id, input_md5 = ct_hash)]
for (ct_name in c("results", "coverage")) {
  ct_out <- if (ct_name == "results") ct_results else ct_coverage
  data.table::fwrite(ct_out,
    file.path(tables_wd, paste0("card-timing-", ct_name, ".csv")))
  haven::write_dta(as.data.frame(ct_out),
    file.path(tables_wd, paste0("card-timing-", ct_name, ".dta")))
}
ct_results[, period_label := factor(outcome,
  levels = c("net_yellow", "early_net_yellow"),
  labels = c("Full match", "First 30 minutes"))]
ct_results[, comparison_label := paste(target, "versus", comparator)]
ct_plot <- ggplot(ct_results,
  aes(x = estimate * 10, y = period_label, colour = target)) +
  geom_vline(xintercept = 0, colour = "grey55", linewidth = 0.4) +
  geom_errorbar(aes(xmin = conf_low * 10, xmax = conf_high * 10),
    orientation = "y", width = 0.15, linewidth = 0.7) +
  geom_point(size = 2.8) +
  facet_wrap(~comparison_label, ncol = 1) +
  scale_colour_manual(values = c("Barcelona" = "#A50044",
                                 "Real Madrid" = "#8C6300")) +
  labs(title = "Does the card gap appear early in the match?",
    subtitle = "Same matches in each panel; prior-match style, not final possession, is held fixed.",
    x = "Additional net yellow cards per 10 matches (positive favors target)",
    y = NULL,
    caption = paste("Bars: 95% season-block clustered intervals. Event totals must match both box scores; extra time excluded.",
      "First 30 minutes and full-match counts have different exposure. Timing does not establish whether calls were correct.",
      sep = "\n")) +
  theme_customs(11) + theme(legend.position = "none")
save_figure(ct_plot, "card-timing-diagnostic.pdf", width = 10, height = 5.7)
print(ct_results[, .(target, comparator, outcome, estimate, conf_low,
                     conf_high, n_target_matches, n_seasons)])
