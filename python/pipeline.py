"""
Referee Bias Analysis – Python pipeline entry point.

Usage
-----
  python -m python.pipeline --help
  python -m python.pipeline \\
      --competition premier_league \\
      --season 2023-24 \\
      --match-file matches_2023-24.csv \\
      --decision-file decisions_2023-24.csv

Steps
-----
1. Load raw match and decision data from ``data/raw/``.
2. Clean and normalise into the canonical game-referee-decision schema.
3. Engineer contextual features.
4. Export Parquet + CSV to ``data/processed/`` for R consumption.
"""

from __future__ import annotations

import argparse
import logging
import sys
from pathlib import Path

# Ensure the project root is importable when run as a script.
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


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Run the referee bias analysis data pipeline."
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
        "--match-file",
        required=True,
        help="Raw match data filename (relative to data/raw/).",
    )
    parser.add_argument(
        "--decision-file",
        required=True,
        help="Raw decision data filename (relative to data/raw/).",
    )
    parser.add_argument(
        "--output-stem",
        default="decisions",
        help="Base filename stem for processed output files.",
    )
    return parser.parse_args(argv)


def run(args: argparse.Namespace) -> None:
    logger.info(
        "Pipeline start — competition=%s  season=%s",
        args.competition,
        args.season,
    )

    # 1. Ingest
    match_loader = MatchDataLoader(args.competition, args.season)
    raw_match_df = match_loader.load_from_file(args.match_file)
    logger.info("Loaded %d raw matches.", len(raw_match_df))

    decision_loader = DecisionDataLoader()
    raw_decision_df = decision_loader.load_from_file(args.decision_file)
    logger.info("Loaded %d raw decisions.", len(raw_decision_df))

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
