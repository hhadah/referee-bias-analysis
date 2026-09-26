# Referee Bias Analysis

> **Research question:** Do some soccer teams receive systematically more favorable referee decisions than others, after controlling for match context (home advantage, score state, match phase, decision type, competition, and season)?

This repository provides a fully reproducible pipeline that uses **Python** for data ingestion and processing and **R** for statistical analysis and figures.

---

## Repository structure

```
referee-bias-analysis/
├── data/
│   ├── raw/            # Place raw downloaded data here (not committed)
│   └── processed/      # Analysis-ready files produced by the Python pipeline
├── python/
│   ├── src/
│   │   ├── ingest.py   # Data loader classes (match-level & decision-level)
│   │   ├── clean.py    # Cleaning & normalisation → canonical schema
│   │   ├── features.py # Feature engineering (score state, experience, etc.)
│   │   └── export.py   # Export to Parquet/CSV for R
│   └── pipeline.py     # CLI entry point for the full Python pipeline
├── r/
│   ├── scripts/
│   │   ├── install_packages.R  # One-time package installation
│   │   ├── 01_load_data.R      # Load & type-check processed data
│   │   ├── 02_eda.R            # Exploratory analysis & figures
│   │   └── 03_analysis.R       # Regression models (logit, mixed-effects, FE)
│   ├── figures/        # Output figures (PDF/PNG) and tables
│   ├── run_analysis.R  # Entry-point: runs all R scripts in order
│   └── DESCRIPTION     # R package dependency manifest
├── notebooks/          # Optional Jupyter notebooks for exploration
├── requirements.txt    # Python dependencies
└── README.md
```

---

## Data schema

The pipeline produces a **decision-level** table where every row is one referee decision in one match.

| Column | Type | Description |
|---|---|---|
| `match_id` | str | Unique match identifier |
| `competition` | str | e.g. `premier_league`, `champions_league` |
| `season` | str | e.g. `2023-24` |
| `match_date` | date | Date of the match |
| `home_team` | str | Home team name |
| `away_team` | str | Away team name |
| `team` | str | Team the decision concerns |
| `opponent` | str | Opponent team |
| `home_away` | str | `"home"` or `"away"` (from `team`'s perspective) |
| `referee` | str | Main referee name |
| `var_referee` | str \| null | VAR referee (when available) |
| `decision_type` | str | `foul`, `yellow_card`, `red_card`, `penalty`, `offside`, `var_review`, `stoppage`, `other` |
| `decision_for_team` | bool | `True` if the decision favoured `team` |
| `var_involved` | bool | Whether VAR was involved |
| `minute` | int | Match minute of the decision |
| `score_diff_before` | int | Goal diff (team − opponent) before the decision |
| `match_phase` | str | `first_half`, `second_half`, `extra_time` |
| `score_state` | str | `winning`, `drawing`, `losing` |
| `is_home` | bool | Derived from `home_away` |
| `referee_matches_before` | int | Referee experience proxy |

---

## Suggested data sources

| Source | What it contains | Cost |
|---|---|---|
| [football-data.co.uk](https://www.football-data.co.uk/data.php) | Match results + referee names, all top leagues, long history | Free |
| [StatsBomb Open Data](https://github.com/statsbomb/open-data) | Match events (passes, fouls, cards) for selected competitions | Free |
| [FBref](https://fbref.com) | Match-level and player stats with referee info | Free (scraping) |
| [understat.com](https://understat.com) | xG-enriched match data | Free (scraping) |
| [Transfermarkt](https://www.transfermarkt.com) | Referee profiles, match assignments | Free (scraping) |
| Opta / StatsBomb paid | Professional decision-level event data | Commercial |

> **Note:** No data is included in this repository. Use `--source football_data_statsbomb` or `--source fbref_understat` in the pipeline command (see **How to run** below) to download data automatically.

---

## How to run

### 1. Install Python dependencies

```bash
python -m venv .venv
source .venv/bin/activate   # Windows: .venv\Scripts\activate
pip install -r requirements.txt
```

### 2. Obtain data

There are three ways to get data into the pipeline.

#### Option A – Download automatically (recommended)

**football-data.co.uk + StatsBomb open events** (Premier League, La Liga, Bundesliga, Serie A, Ligue 1):

```bash
python -m python.pipeline \
    --competition premier_league \
    --season 2023-24 \
    --source football_data_statsbomb \
    --sb-competition-id 2 \
    --sb-season-id 27
```

Use `statsbombpy.sb.competitions()` to look up valid `competition_id` / `season_id` values.

**FBref + understat** (includes Champions League; understat provides xG context):

```bash
python -m python.pipeline \
    --competition champions_league \
    --season 2023-24 \
    --source fbref_understat
```

Downloaded files are cached in `data/raw/` automatically.

#### Option B – Use a local file

Place CSV or Parquet files in `data/raw/` and pass their names explicitly:

```bash
python -m python.pipeline \
    --competition premier_league \
    --season 2023-24 \
    --source file \
    --match-file matches_2023-24.csv \
    --decision-file decisions_2023-24.csv
```

### 3. Run the Python pipeline

After data is available (either downloaded above or placed manually), the same command runs the full clean → feature → export chain:

```bash
python -m python.pipeline \
    --competition premier_league \
    --season 2023-24 \
    --source football_data_statsbomb
```

This writes `data/processed/decisions.parquet` and `data/processed/decisions.csv`.

### 4. Install R packages (one-time)

```r
source("r/scripts/install_packages.R")
```

### 5. Run the R analysis

```bash
Rscript r/run_analysis.R
```

Or run individual scripts in order:

```r
source("r/scripts/01_load_data.R")
source("r/scripts/02_eda.R")
source("r/scripts/03_analysis.R")
```

Output figures and model summary tables are written to `r/figures/`.

---

## Models

| Model | Description |
|---|---|
| M1 Logit | Baseline logistic regression with team fixed effects |
| M2 Mixed | Mixed-effects logistic with random intercepts for team and referee |
| M3 FE | High-dimensional two-way fixed-effects logit (team + referee) via `fixest` |
| M4 FE+VAR | M3 extended with VAR-involvement interaction term |

The primary quantity of interest is the team-level random effect (M2) or fixed effect (M3), which captures systematic bias in referee decisions toward or against each team after controlling for all covariates.

---

## Reproducibility

- Python 3.10+ recommended; see `requirements.txt`.
- R 4.2+ recommended; see `r/DESCRIPTION`.
- All figure/table outputs are written to `r/figures/` and are not committed.
- Raw data files are not committed; see `data/raw/` (git-ignored).

