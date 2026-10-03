# referee-bias-analysis

Do some clubs receive more favorable refereeing decisions than others? This
project assembles match-level refereeing data for the top-5 European leagues
(Premier League, La Liga, Serie A, Bundesliga, Ligue 1) and the UEFA Champions
League from 2001/02 to the present, and asks where FC Barcelona sits relative
to every other club, before and after the end of the reported Negreira
payments (2001–2018).

## October 2026 update

The [analysis supplement](my_paper/analysis-update.pdf) and
[browser report](output/analysis-report.html) add possession-adjusted
comparisons and pooled Champions League estimates. These remain descriptive
comparisons, not estimates of incorrect decisions.
[Next-step recommendations](notes/next-steps.md) prioritize source completeness,
comparable playing styles, incident-level outcomes and small-sample inference.
They distinguish completed work from changes still needed before updating
the original manuscript.

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
│   ├── 17-barcelona-style-adjusted-decisions.R
│   ├── 18-champions-league-pooled-precision.R
│   ├── 19-card-timing-diagnostics.R
│   ├── 20-build-analysis-report.R
│   ├── 94-verify-analysis.R
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

R 4.5.2 was used with data.table 1.18.2.1, fixest 0.12.1, ggplot2 4.0.2,
haven 2.5.5 and patchwork 1.3.1. The runner checks required packages and
installs nothing. It uses local fonts and does not fetch a Google font.

From the project root:

```bash
Rscript programs/95-make-all.R
latexmk -cd -pdf -interaction=nonstopmode -halt-on-error my_paper/analysis-update.tex
```

The first command rebuilds the data from cached sources, runs programs
17–20 and verifies the data and inference invariants in program 94.
`REFEREE_BIAS_ROOT` can point to another checkout. Seed: `20261003`.
Logs and package versions go to `output/logs/analysis-<run-id>.log` and
`session-<run-id>.txt`. Every main result has CSV and DTA output;
`output/tables/artifact-manifest.csv` records output hashes.

Options:

- `--analysis-only`: reuse the already rebuilt panel and rerun 17–20 and 94.
- `--download`: refresh public source downloads before rebuilding.
- `--legacy`: also regenerate exploratory programs 06–16. Their old
  significance claims and rankings are not the current evidence report.
  This option requires the original table-rendering packages.

## Current findings and figures

- [Browser report with seven figures](output/analysis-report.html)
- [PDF analysis supplement](my_paper/analysis-update.pdf)
- [Generated findings memo](notes/findings-memo-possession-adjusted.md)
- [Headline estimates and multiple-testing adjustment](output/tables/analysis-headlines.csv)
- [Data coverage audit](output/tables/data-audit-coverage.csv)

The original `my_paper/main.tex`, its authored fragments and
`notes/findings-memo.md` are preserved. They predate this audit; use the
separate supplement for updated estimates and qualifications.

The Barcelona specifications hold the sample fixed, compare prior-match
and same-match style controls, report called-foul-adjusted card outcomes,
and show where comparable possession observations are missing. The
Champions League analysis pools seasons, reports detectable effect sizes
and equivalence bounds, checks leave-one-season-out stability, and labels
seasonal shrinkage intervals as conditional model-based summaries.

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
