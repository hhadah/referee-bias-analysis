# referee-bias-analysis

Do some clubs receive more favorable refereeing decisions than others? This
project assembles match-level refereeing data for the top-5 European leagues
(Premier League, La Liga, Serie A, Bundesliga, Ligue 1) and the UEFA Champions
League from 2001/02 to the present, and asks where FC Barcelona sits relative
to every other club, before and after the end of the reported Negreira
payments (2001–2018).

## Project layout

```
referee-bias-analysis/
├── programs/                 # numbered scripts, run in order by 95-make-all.R
│   ├── 00-functions.R        # labels, sample definition, theme, save helpers
│   ├── 01-download-football-data.R
│   ├── 02-download-espn-matches.py
│   ├── 03-clean-football-data.R
│   ├── 04-clean-espn.R
│   ├── 05-build-team-match-panel.R
│   ├── 06-table-one-summary-statistics.R
│   ├── 07-figure-one-barcelona-raw-differentials.R
│   ├── 08-table-two-team-fixed-effects.R
│   ├── 09-figure-two-team-favorability-ranking.R
│   ├── 10-table-three-domestic-vs-champions-league.R
│   ├── 11-figure-three-negreira-event-study.R
│   ├── 12-table-four-stoppage-time.R
│   ├── 13-table-five-exposure-adjusted-fouls.R
│   ├── 14-figures-four-to-seven-elite-clubs-by-season.R
│   ├── 15-table-six-real-madrid-champions-league-by-season.R
│   ├── 16-figure-eight-tables-seven-eight-real-madrid-champions-league-gaps.R
│   └── 95-make-all.R         # master script: directories + full pipeline
├── data/
│   ├── raw/                  # untouched downloads (git-ignored)
│   │   ├── football-data/    # football-data.co.uk league CSVs, 2000/01–2026/27
│   │   └── espn/             # ESPN match summaries (trimmed JSON) + event indexes
│   └── datasets/             # cleaned and derived data (git-ignored)
├── output/
│   ├── tables/               # .tex table fragments + .csv coefficient files
│   ├── figures/              # .pdf and .png figures
│   └── logs/
├── my_paper/                 # LaTeX manuscript: main.tex + fragments/ (sections),
│   ├── tables/  figure/      #   tables/ and figure/ are written by the R scripts
├── presentations/
└── notes/                    # data documentation, research design, findings memo
```

## Reproducing

1. Install R (≥ 4.3) and Python 3 (standard library only). R packages are loaded
   with `pacman::p_load()` in `programs/95-make-all.R`.
2. Set `run_downloads <- TRUE` in `programs/95-make-all.R` for a fresh run. The
   ESPN scrape covers about 50,000 match pages and takes 45–60 minutes. It is
   cached and idempotent, so re-running only adds new matches.
3. Run from the project root:

   ```bash
   Rscript programs/95-make-all.R
   ```

Every table and figure is written by code into `output/` and copied into
`my_paper/`. Nothing is edited by hand.

## Current findings

See `notes/findings-memo.md` for a summary and `my_paper/main.pdf` for the
draft paper.

## Data sources

| Source | Coverage | Variables used |
|---|---|---|
| [football-data.co.uk](https://www.football-data.co.uk/data.php) | Top-5 leagues, 2000/01–present | Results, fouls, yellow/red cards, shots, referee (England; Italy 2005/06–2006/07; Germany 2000/01–2001/02), pre-match bookmaker odds |
| ESPN site API (`site.api.espn.com/apis/site/v2/sports/soccer/...`) | Top-5 leagues + Champions League, 2001/02–present | Results, fouls, cards, possession, shots, penalties (key events), referee, attendance, first- and second-half stoppage time, competition round |

See `notes/data-documentation.md` for variable definitions, coverage by
league-season, and known data issues.

## Data notes

- Raw and derived data are not committed (see `.gitignore`). Re-create them with
  the download scripts.
- Both sources are public pages used here for non-commercial academic research.
  Check each provider's terms before redistributing data.
