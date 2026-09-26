"""
Data ingestion placeholders for referee bias analysis.

This module provides loader stubs for the two main data sources:
  - match-level data (schedule, result, referee assignment)
  - decision-level data (individual referee decisions per match)

Replace the stub methods with real API calls or web-scraping logic
as the actual data sources are integrated.

Suggested data sources:
  - football-data.co.uk  (match results + referee names, free)
  - FBref / StatsBomb open data (match events, free)
  - understat.com        (xG, shots, enriched match data)
  - Transfermarkt        (referee profiles, scraped)
  - Opta / StatsBomb paid (professional, decision-level events)
"""

from __future__ import annotations

import logging
from pathlib import Path
from typing import Optional

import pandas as pd

logger = logging.getLogger(__name__)

RAW_DIR = Path(__file__).resolve().parents[2] / "data" / "raw"


# ---------------------------------------------------------------------------
# Match-level loader
# ---------------------------------------------------------------------------

class MatchDataLoader:
    """Load match-level data (schedule, result, referee assignment).

    Parameters
    ----------
    competition : str
        Competition identifier, e.g. ``"premier_league"``, ``"champions_league"``.
    season : str
        Season string, e.g. ``"2023-24"``.
    raw_dir : Path, optional
        Directory where raw data files are stored.
    """

    SUPPORTED_COMPETITIONS = [
        "premier_league",
        "la_liga",
        "bundesliga",
        "serie_a",
        "ligue_1",
        "champions_league",
    ]

    def __init__(
        self,
        competition: str,
        season: str,
        raw_dir: Optional[Path] = None,
    ) -> None:
        if competition not in self.SUPPORTED_COMPETITIONS:
            raise ValueError(
                f"Unknown competition '{competition}'. "
                f"Supported: {self.SUPPORTED_COMPETITIONS}"
            )
        self.competition = competition
        self.season = season
        self.raw_dir = raw_dir or RAW_DIR

    def load_from_file(self, filename: str) -> pd.DataFrame:
        """Load match data from a CSV / Parquet file in ``raw_dir``.

        Parameters
        ----------
        filename : str
            File name relative to ``raw_dir``.

        Returns
        -------
        pd.DataFrame
            Raw match-level data frame.
        """
        filepath = self.raw_dir / filename
        if not filepath.exists():
            raise FileNotFoundError(
                f"Raw data file not found: {filepath}. "
                "Download or place the raw data file before running."
            )
        if filepath.suffix == ".parquet":
            return pd.read_parquet(filepath)
        return pd.read_csv(filepath)

    def fetch_from_football_data_co_uk(self) -> pd.DataFrame:
        """Placeholder: fetch match data from football-data.co.uk.

        Returns
        -------
        pd.DataFrame
            Raw match frame (not yet implemented).

        Raises
        ------
        NotImplementedError
            Always, until the method body is filled in.
        """
        raise NotImplementedError(
            "Implement HTTP download from "
            "https://www.football-data.co.uk/data.php"
        )

    def fetch_from_fbref(self) -> pd.DataFrame:
        """Placeholder: scrape match-level data from FBref.

        Returns
        -------
        pd.DataFrame
            Raw match frame (not yet implemented).

        Raises
        ------
        NotImplementedError
            Always, until the method body is filled in.
        """
        raise NotImplementedError(
            "Implement scraping from https://fbref.com"
        )


# ---------------------------------------------------------------------------
# Decision-level loader
# ---------------------------------------------------------------------------

class DecisionDataLoader:
    """Load decision-level data (one row per referee decision per match).

    A *decision* can be a foul, yellow card, red card, penalty, VAR review,
    offside call, or any other discrete referee action.

    Parameters
    ----------
    raw_dir : Path, optional
        Directory where raw data files are stored.
    """

    def __init__(self, raw_dir: Optional[Path] = None) -> None:
        self.raw_dir = raw_dir or RAW_DIR

    def load_from_file(self, filename: str) -> pd.DataFrame:
        """Load decision data from a CSV / Parquet file in ``raw_dir``.

        Parameters
        ----------
        filename : str
            File name relative to ``raw_dir``.

        Returns
        -------
        pd.DataFrame
            Raw decision-level data frame.
        """
        filepath = self.raw_dir / filename
        if not filepath.exists():
            raise FileNotFoundError(
                f"Raw data file not found: {filepath}. "
                "Download or place the raw data file before running."
            )
        if filepath.suffix == ".parquet":
            return pd.read_parquet(filepath)
        return pd.read_csv(filepath)

    def fetch_from_statsbomb_open(self) -> pd.DataFrame:
        """Placeholder: fetch StatsBomb open event data.

        Returns
        -------
        pd.DataFrame
            Raw decision frame (not yet implemented).

        Raises
        ------
        NotImplementedError
            Always, until the method body is filled in.
        """
        raise NotImplementedError(
            "Implement download from "
            "https://github.com/statsbomb/open-data"
        )

    def fetch_from_understat(self) -> pd.DataFrame:
        """Placeholder: fetch enriched match/event data from understat.com.

        Returns
        -------
        pd.DataFrame
            Raw decision frame (not yet implemented).

        Raises
        ------
        NotImplementedError
            Always, until the method body is filled in.
        """
        raise NotImplementedError(
            "Implement scraping from https://understat.com"
        )
