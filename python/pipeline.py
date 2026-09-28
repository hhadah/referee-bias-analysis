"""
Referee Bias Analysis – Python pipeline entry point.

Usage
-----
  python -m python.pipeline --help

  # Use a local file already in data/raw/
  python -m python.pipeline \\
      --competition premier_league \\
      --season 2023-24 \\
      --source file \\
      --match-file matches_2023-24.csv \\
      --decision-file decisions_2023-24.csv

  # Download match data from football-data.co.uk + StatsBomb open events
  python -m python.pipeline \\
      --competition premier_league \\
      --season 2023-24 \\
      --source football_data_statsbomb

  # Download match data from FBref + understat context
  python -m python.pipeline \\
      --competition premier_league \\
      --season 2023-24 \\
      --source fbref_understat

Steps
-----
1. Ingest raw match and decision data (from file or live source).
2. Clean and normalise into the canonical game-referee-decision schema.
3. Engineer contextual features.
4. Export Parquet + CSV to ``data/processed/`` for R consumption.
"""

from __future__ import annotations

import argparse
import logging
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from python.src.ingest import DecisionDataLoader, MatchDataLoader
from python.src.clean import build_decision_table
from python.src.features import engineer_features
from python.src.export import export_for_r

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s  %(levelname)-8s  %(name)s  %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
)
logger = logging.getLogger(__name__)

SOURCES = ["file", "football_data_statsbomb", "fbref_understat"]


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Run the referee bias analysis data pipeline.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument(
        "--competition",
        required=True,
        choices=MatchDataLoader.SUPPORTED_COMPETITIONS,
        help="Competition identifier.",
    )
    parser.add_argument(
        "--season",
        required=True,
        help='Season string, e.g. "2023-24".',
    )
    parser.add_argument(
        "--source",
        choices=SOURCES,
        default="file",
        help=(
            "Data source. "
            "'file': load from local CSVs in data/raw/ (requires --match-file / --decision-file). "
            "'football_data_statsbomb': download match data from football-data.co.uk + "
            "StatsBomb open events. "
            "'fbref_understat': scrape match data from FBref + understat context."
        ),
    )
    parser.add_argument(
        "--match-file",
        default=None,
        help="Raw match data filename (relative to data/raw/). Required when --source=file.",
    )
    parser.add_argument(
        "--decision-file",
        default=None,
        help="Raw decision data filename (relative to data/raw/). Required when --source=file.",
    )
    # StatsBomb-specific filters
    parser.add_argument(
        "--sb-competition-id",
        type=int,
        default=None,
        help="StatsBomb competition_id filter (optional; used with --source=football_data_statsbomb).",
    )
    parser.add_argument(
        "--sb-season-id",
        type=int,
        default=None,
        help="StatsBomb season_id filter (optional; used with --source=football_data_statsbomb).",
    )
    parser.add_argument(
        "--output-stem",
        default="decisions",
        help="Base filename stem for processed output files.",
    )
    return parser.parse_args(argv)


def _ingest_file(args: argparse.Namespace):
    if not args.match_file or not args.decision_file:
        raise SystemExit(
            "ERROR: --source=file requires both --match-file and --decision-file."
        )
    match_loader = MatchDataLoader(args.competition, args.season)
    raw_match_df = match_loader.load_from_file(args.match_file)
    logger.info("Loaded %d raw matches from file.", len(raw_match_df))

    decision_loader = DecisionDataLoader()
    raw_decision_df = decision_loader.load_from_file(args.decision_file)
    logger.info("Loaded %d raw decisions from file.", len(raw_decision_df))
    return raw_match_df, raw_decision_df


def _ingest_football_data_statsbomb(args: argparse.Namespace):
    match_loader = MatchDataLoader(args.competition, args.season)
    raw_match_df = match_loader.fetch_from_football_data_co_uk(save=True)
    logger.info("Downloaded %d matches from football-data.co.uk.", len(raw_match_df))

    decision_loader = DecisionDataLoader()
    raw_decision_df = decision_loader.fetch_from_statsbomb_open(
        competition_id=args.sb_competition_id,
        season_id=args.sb_season_id,
        save=True,
    )
    logger.info("Downloaded %d decision events from StatsBomb.", len(raw_decision_df))
    return raw_match_df, raw_decision_df


def _ingest_fbref_understat(args: argparse.Namespace):
    match_loader = MatchDataLoader(args.competition, args.season)
    raw_match_df = match_loader.fetch_from_fbref(save=True)
    logger.info("Scraped %d rows from FBref.", len(raw_match_df))

    decision_loader = DecisionDataLoader()
    season_year = args.season.split("-")[0]
    raw_decision_df = decision_loader.fetch_from_understat(
        season=season_year,
        competition=args.competition,
        save=True,
    )
    logger.info("Scraped %d rows from understat.", len(raw_decision_df))
    return raw_match_df, raw_decision_df


_INGEST_DISPATCH = {
    "file": _ingest_file,
    "football_data_statsbomb": _ingest_football_data_statsbomb,
    "fbref_understat": _ingest_fbref_understat,
}


def run(args: argparse.Namespace) -> None:
    logger.info(
        "Pipeline start — competition=%s  season=%s  source=%s",
        args.competition,
        args.season,
        args.source,
    )

    # 1. Ingest
    ingest_fn = _INGEST_DISPATCH[args.source]
    raw_match_df, raw_decision_df = ingest_fn(args)

    if raw_decision_df.empty:
        logger.warning("Decision data is empty — nothing to process.")
        return

    # 2. Clean
    decision_df = build_decision_table(
        raw_match_df, raw_decision_df, args.competition, args.season
    )
    logger.info("Cleaned decision table: %d rows.", len(decision_df))

    # 3. Feature engineering
    decision_df = engineer_features(decision_df)
    logger.info("Feature engineering complete.")

    # 4. Export
    written = export_for_r(decision_df, stem=args.output_stem)
    for fmt, path in written.items():
        logger.info("  [%s] %s", fmt, path)

    logger.info("Pipeline complete.")


if __name__ == "__main__":
    run(parse_args())
