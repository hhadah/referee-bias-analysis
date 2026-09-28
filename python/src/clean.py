"""
Data cleaning and normalisation for referee bias analysis.

Transforms raw match-level and decision-level data frames into a
game-referee-decision level table with a consistent schema.

Decision-level schema
---------------------
Each row represents a single referee decision in a single match.

Column                  Type        Description
----------------------  ----------  -----------------------------------------
match_id                str         Unique match identifier
competition             str         Competition name (e.g. "premier_league")
season                  str         Season (e.g. "2023-24")
match_date              date        Date of the match
home_team               str         Home team name
away_team               str         Away team name
team                    str         Team that the decision concerns
opponent                str         Opponent team
home_away               str         "home" or "away" (from team's perspective)
referee                 str         Main referee name
var_referee             str | None  VAR referee name if available
decision_type           str         "foul", "yellow_card", "red_card",
                                    "penalty", "offside", "var_review", etc.
decision_for_team       bool        True if decision favoured *team*
var_involved            bool        True if VAR was part of the decision
minute                  int | None  Match minute
score_diff_before       int | None  Goal diff (team - opponent) before decision
match_phase             str | None  "first_half", "second_half", "extra_time"
"""

from __future__ import annotations

import logging
from typing import Optional

import numpy as np
import pandas as pd

logger = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# Column name maps – adjust to match actual raw data column names
# ---------------------------------------------------------------------------

MATCH_COLUMN_MAP: dict[str, str] = {
    # raw name -> canonical name
    "HomeTeam": "home_team",
    "AwayTeam": "away_team",
    "Referee": "referee",
    "Date": "match_date",
    "Div": "competition",
}

DECISION_COLUMN_MAP: dict[str, str] = {
    "match_id": "match_id",
    "team": "team",
    "opponent": "opponent",
    "type": "decision_type",
    "minute": "minute",
    "for_team": "decision_for_team",
    "var": "var_involved",
}

VALID_DECISION_TYPES = {
    "foul",
    "yellow_card",
    "red_card",
    "penalty",
    "offside",
    "var_review",
    "stoppage",
    "other",
}


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _parse_date(series: pd.Series) -> pd.Series:
    return pd.to_datetime(series, dayfirst=True, errors="coerce").dt.date


def _infer_match_phase(minute: pd.Series) -> pd.Series:
    m = minute.astype(float)  # convert nullable Int64 to float so NaN comparisons work
    conditions = [
        m <= 45,
        (m > 45) & (m <= 90),
        m > 90,
    ]
    choices = ["first_half", "second_half", "extra_time"]
    return np.select(conditions, choices, default=None)


# ---------------------------------------------------------------------------
# Cleaners
# ---------------------------------------------------------------------------

class MatchCleaner:
    """Normalise a raw match-level data frame.

    Parameters
    ----------
    competition : str
        Competition identifier used to fill the ``competition`` column when
        the raw data does not contain it.
    season : str
        Season string used to fill the ``season`` column.
    """

    def __init__(self, competition: str, season: str) -> None:
        self.competition = competition
        self.season = season

    def clean(self, df: pd.DataFrame) -> pd.DataFrame:
        """Return a normalised match data frame.

        Parameters
        ----------
        df : pd.DataFrame
            Raw match-level data frame.

        Returns
        -------
        pd.DataFrame
            Normalised data frame with canonical column names.
        """
        df = df.copy()
        df = df.rename(columns={k: v for k, v in MATCH_COLUMN_MAP.items() if k in df.columns})

        if "match_date" in df.columns:
            df["match_date"] = _parse_date(df["match_date"])

        if "competition" not in df.columns:
            df["competition"] = self.competition
        if "season" not in df.columns:
            df["season"] = self.season

        if "referee" in df.columns:
            df["referee"] = df["referee"].str.strip().str.title()

        if "home_team" in df.columns:
            df["home_team"] = df["home_team"].str.strip()
        if "away_team" in df.columns:
            df["away_team"] = df["away_team"].str.strip()

        if "match_id" not in df.columns:
            df["match_id"] = (
                df["match_date"].astype(str)
                + "_"
                + df["home_team"].str.replace(" ", "_", regex=False)
                + "_vs_"
                + df["away_team"].str.replace(" ", "_", regex=False)
            )

        return df


class DecisionCleaner:
    """Normalise and validate a raw decision-level data frame."""

    def clean(self, df: pd.DataFrame, match_df: Optional[pd.DataFrame] = None) -> pd.DataFrame:
        """Return a normalised decision-level data frame.

        Parameters
        ----------
        df : pd.DataFrame
            Raw decision-level data frame.
        match_df : pd.DataFrame, optional
            Normalised match data frame used to enrich decisions with
            context fields (competition, season, referee, date …).

        Returns
        -------
        pd.DataFrame
            Normalised decision data frame.
        """
        df = df.copy()
        df = df.rename(columns={k: v for k, v in DECISION_COLUMN_MAP.items() if k in df.columns})

        if "decision_type" in df.columns:
            df["decision_type"] = df["decision_type"].str.lower().str.strip()
            unknown = ~df["decision_type"].isin(VALID_DECISION_TYPES)
            if unknown.any():
                logger.warning(
                    "Replacing %d unknown decision types with 'other'.",
                    unknown.sum(),
                )
                df.loc[unknown, "decision_type"] = "other"

        if "decision_for_team" in df.columns:
            df["decision_for_team"] = df["decision_for_team"].astype(bool)

        if "var_involved" in df.columns:
            df["var_involved"] = df["var_involved"].fillna(False).astype(bool)
        else:
            df["var_involved"] = False

        if "minute" in df.columns:
            df["minute"] = pd.to_numeric(df["minute"], errors="coerce").astype("Int64")
            df["match_phase"] = _infer_match_phase(df["minute"])
            # Leave match_phase as None/NaN where minute is unknown
            df.loc[df["minute"].isna(), "match_phase"] = None

        if "team" in df.columns and "opponent" in df.columns:
            is_home_col = df.get("is_home", pd.Series(False, index=df.index))
            df["home_away"] = np.where(is_home_col.fillna(False), "home", "away")

        if match_df is not None and "match_id" in df.columns:
            merge_cols = [
                c for c in ["match_id", "competition", "season", "match_date",
                             "referee", "var_referee", "home_team", "away_team"]
                if c in match_df.columns
            ]
            df = df.merge(match_df[merge_cols], on="match_id", how="left")

        return df


# ---------------------------------------------------------------------------
# Pipeline convenience function
# ---------------------------------------------------------------------------

def build_decision_table(
    raw_match_df: pd.DataFrame,
    raw_decision_df: pd.DataFrame,
    competition: str,
    season: str,
) -> pd.DataFrame:
    """End-to-end clean + merge into a game-referee-decision table.

    Parameters
    ----------
    raw_match_df : pd.DataFrame
        Raw match data frame from a :class:`MatchDataLoader`.
    raw_decision_df : pd.DataFrame
        Raw decision data frame from a :class:`DecisionDataLoader`.
    competition : str
        Competition identifier.
    season : str
        Season string.

    Returns
    -------
    pd.DataFrame
        Analysis-ready decision table.
    """
    match_df = MatchCleaner(competition, season).clean(raw_match_df)
    decision_df = DecisionCleaner().clean(raw_decision_df, match_df=match_df)
    return decision_df
