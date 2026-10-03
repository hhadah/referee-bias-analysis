# Data documentation

*Last updated: 2026-10-02. Data downloaded 2026-10-02.*

## Sources

### 1. football-data.co.uk (`programs/01-download-football-data.R`)

- Files: `https://www.football-data.co.uk/mmz4281/<YYZZ>/<DIV>.csv`, where DIV is
  E0 (Premier League), SP1 (La Liga), I1 (Serie A), D1 (Bundesliga) or F1
  (Ligue 1). Seasons 2000/01–2026/27 (2026/27 in progress): 135 files.
- Used for: pre-match bookmaker odds (all seasons), and fouls, cards and shots
  as a fallback where ESPN's box score is missing. Referee names are available
  for England (all seasons), Italy (2005/06–2006/07) and Germany
  (2000/01–2001/02).
- Odds: market average (`Avg*`/`BbAv*`) when reported (2005/06+), else Bet365,
  else William Hill, else Interwetten. Implied probabilities are normalized
  for the overround: `p_k = (1/odds_k) / sum_j (1/odds_j)`.
- Match statistics coverage: fouls and cards from 2000/01 (England),
  2003/04 (Germany), 2005/06 (Spain, Italy) and 2005/06 cards / 2007/08 fouls
  (France).

### 2. ESPN site API (`programs/02-download-espn-matches.py`)

- Endpoints (public JSON, no key):
  - `site.api.espn.com/apis/site/v2/sports/soccer/<league>/scoreboard?dates=YYYYMM`
    for the monthly event index;
  - `.../<league>/summary?event=<id>` for each match.
- Leagues: `eng.1`, `esp.1`, `ita.1`, `ger.1`, `fra.1`, `uefa.champions`.
  Seasons 2001/02–2026/27.
- Stored as trimmed, gzipped JSON (box score, game info, key events, header) in
  `data/raw/espn/json/<league>/<season>/<event_id>.json.gz`, plus
  `data/raw/espn/events-index-<league>.csv`.
- Variables: score, team ids (consistent across competitions, e.g.
  Barcelona = 83, Real Madrid = 86), fouls, yellow/red cards, possession,
  shots, referee, attendance, venue, competition round, and key events
  (goals, penalties scored/missed/saved, cards, VAR reviews) with match clock.
  First- and second-half stoppage time come from the clock of the "Halftime"
  and "End Regular Time" events (for example `90'+4'`).
- The download is idempotent: matches already on disk are skipped. It takes
  45–60 minutes from scratch, and longer when ESPN throttles requests.

## Derived datasets (`data/datasets/`)

| File | Unit | Built by |
|---|---|---|
| `football-data-matches.csv` | domestic match | `03-clean-football-data.R` |
| `espn-matches.csv` | match (all six competitions) | `04-clean-espn.R` |
| `espn-key-events.csv` | match event (goals, penalties, cards, VAR) | `04-clean-espn.R` |
| `team-crosswalk.csv` | football-data team name → ESPN team id | `05-build-team-match-panel.R` |
| `matches.csv` | match, with both sources merged, Elo, penalty flags | `05-build-team-match-panel.R` |
| `team-match-panel.csv` | team × match (each match twice) | `05-build-team-match-panel.R` |

### Key construction choices

- **Linking the sources.** Football-data team names are mapped to ESPN ids
  using matches with the same league, a date within one day, and the same
  score; each name takes its modal id. Domestic matches are then merged on
  (league, season, home id, away id), which is unique within a league-season.
  Over 99.9% of domestic ESPN matches link.
- **Fouls and cards.** ESPN box score first, football-data.co.uk otherwise.
  Where both exist, they agree exactly in 92–98% of matches (correlation
  > 0.97). ESPN reports zeros for statistics it did not track; a statistic is
  set to missing when both teams show zero.
- **Penalties.** Counted from ESPN key events ("Penalty - Scored/Missed/Saved/
  Hit Woodwork"), excluding shoot-outs and VAR review entries. ESPN's box-score
  penalty counts are unreliable and are not used. League-seasons with fewer
  than 0.15 recorded penalties per match are flagged `pens_ok = FALSE` and
  excluded (incomplete early event logs).
- **Score at 90 minutes.** Final score minus goals scored in second-half
  stoppage time (clock `90'+`). It is kept only when the event-log goals
  reconcile with the final score (`goals_ok`). VAR review entries ("VAR - Goal
  Awarded", etc.) are excluded from goal counts. Own goals are attributed to
  the benefiting team in ESPN's logs.
- **Duplicates.** ESPN occasionally lists a match twice under different ids
  (e.g. Premier League 2009/10). The record with box-score data, then the one
  whose round slug names the season, is kept.
- **Elo ratings.** Pre-match Elo from all ESPN results (domestic + Champions
  League) in date order; K = 20 with a goal-difference multiplier; home
  advantage 65 points (none at neutral venues). Teams enter at 1500. Clubs
  promoted into a league enter at the mean rating of that league's relegated
  clubs. Used as the strength control in Champions League comparisons, where
  odds are unavailable. (ClubElo's API was down at download time.)
- **Champions League stages.** `ucl_stage` ∈ {Qualifying, Group/league phase,
  Knockout}. Qualifying rounds are excluded from the analysis sample. ESPN's
  round slugs are inconsistent: the pre-group play-off appears as
  "play-off-round", "playoff-round" or "playoffs", and these are coded as
  qualifying. The 2001/02–2002/03 "second-phase" is coded as a group stage.
  The post-2024 "knockout-round-playoffs" are knockout matches. ESPN labels the
  2002/03 semi-finals as quarter-finals: when a season has more than eight
  quarter-final legs, the last four are recoded as semi-finals.
- **Neutral venues.** ESPN never flags neutral sites. Champions League finals
  and the August 2020 final tournament in Lisbon (quarter-finals onward) are
  coded as neutral (no home team; no Elo home advantage).
- **Winners.** `home_winner`/`away_winner` (ESPN header flags) account for
  extra time and shoot-outs; shoot-out scores are in `home_shootout`/`away_shootout`.
- **Analysis sample.** Complete seasons through 2025/26. Cards and fouls from
  2005/06; penalties from 2001/02 where `pens_ok`.

## Coverage by league-season

`output/tables/data-coverage-by-league-season.csv` reports, for every
league-season: matches, and the share of matches with fouls, cards,
possession, a referee name, stoppage time and odds, plus the penalty rate.

Known gaps (analysis sample: complete seasons, no Champions League qualifiers):

- **Fouls and cards** are missing before 2005/06 in Spain, Italy, France and the
  Champions League main stage (Germany from 2003/04, England throughout).
  Champions League main-stage coverage is 86–100% from 2005/06.
- **Possession** starts in 2005/06 (Spain) and 2007/08 (Italy, Germany,
  France, Champions League). In the Premier League it is missing for 2001/02 and
  2016/17, and partly for 2011/12 and 2022/23.
- **Penalty records** are flagged incomplete (`pens_ok = FALSE`, fewer than
  0.15 penalties per match) and excluded for: Premier League 2002/03; La Liga
  2004/05–2005/06; Bundesliga 2004/05–2005/06; Ligue 1 2003/04 and 2005/06;
  Champions League 2002/03–2006/07 and 2009/10.
- **Referee names** come from ESPN, plus football-data.co.uk for England. They
  are mostly missing after 2010/11 outside England, so referee fixed effects
  are not used in the main specifications.
- **Stoppage time** is recorded from 2005/06 (La Liga, Champions League),
  2006/07 (Serie A, Bundesliga, Ligue 1) and 2008/09 (Premier League), with
  scattered missing matches in later seasons.
- **Odds** are available for domestic leagues only. Champions League strength
  controls use the internally computed Elo ratings.
