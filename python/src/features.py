"""
Feature engineering for referee bias analysis.

Adds contextual features to the cleaned decision-level table that are
useful for regression / bias modelling in R.
"""

from __future__ import annotations

import numpy as np
import pandas as pd


def add_score_state(df: pd.DataFrame) -> pd.DataFrame:
    """Classify score state before the decision as winning / drawing / losing.

    Requires ``score_diff_before`` column (goal diff from *team*'s perspective).

    Parameters
    ----------
    df : pd.DataFrame
        Decision table with ``score_diff_before`` column.

    Returns
    -------
    pd.DataFrame
        Input data frame with new ``score_state`` column added.
    """
    if "score_diff_before" not in df.columns:
        return df
    conditions = [
        df["score_diff_before"] > 0,
        df["score_diff_before"] == 0,
        df["score_diff_before"] < 0,
    ]
    choices = ["winning", "drawing", "losing"]
    df = df.copy()
    df["score_state"] = np.select(conditions, choices, default="unknown")
    return df


def add_decision_counts(df: pd.DataFrame) -> pd.DataFrame:
    """Compute cumulative decision counts per team per match up to each decision.

    Parameters
    ----------
    df : pd.DataFrame
        Decision table with ``match_id``, ``team``, ``decision_type``, and
        ``minute`` columns.

    Returns
    -------
    pd.DataFrame
        Input data frame with ``cum_fouls_for``, ``cum_cards_for``, and
        ``cum_fouls_against`` columns added.
    """
    required = {"match_id", "team", "decision_type", "decision_for_team"}
    if not required.issubset(df.columns):
        return df
    df = df.copy().sort_values(["match_id", "team", "minute"], na_position="last")
    df = df.reset_index(drop=True)

    for dtype, col_suffix, for_team in [
        ("foul", "fouls_for", True),
        ("foul", "fouls_against", False),
        ("yellow_card", "yellow_cards_for", True),
    ]:
        mask = (df["decision_type"] == dtype) & (df["decision_for_team"] == for_team)
        df[f"cum_{col_suffix}"] = (
            mask.astype(int)
            .groupby([df["match_id"], df["team"]])
            .cumsum()
            .shift(fill_value=0)
        )
    return df


def add_referee_experience(df: pd.DataFrame) -> pd.DataFrame:
    """Add a referee experience proxy: number of matches refereed before this one.

    Parameters
    ----------
    df : pd.DataFrame
        Decision table with ``referee`` and ``match_date`` columns.
        Assumes one row per decision; de-duplicates to match level internally.

    Returns
    -------
    pd.DataFrame
        Input data frame with ``referee_matches_before`` column added.
    """
    required = {"match_id", "referee", "match_date"}
    if not required.issubset(df.columns):
        return df
    df = df.copy()

    match_ref = df[["match_id", "referee", "match_date"]].drop_duplicates("match_id")
    match_ref = match_ref.sort_values("match_date")
    match_ref["referee_matches_before"] = (
        match_ref.groupby("referee").cumcount()
    )
    df = df.merge(match_ref[["match_id", "referee_matches_before"]], on="match_id", how="left")
    return df


def add_home_advantage_flag(df: pd.DataFrame) -> pd.DataFrame:
    """Add a binary flag indicating whether the team was playing at home.

    Parameters
    ----------
    df : pd.DataFrame
        Decision table with ``home_away`` column.

    Returns
    -------
    pd.DataFrame
        Input data frame with boolean ``is_home`` column added.
    """
    if "home_away" not in df.columns:
        return df
    df = df.copy()
    df["is_home"] = df["home_away"] == "home"
    return df


def engineer_features(df: pd.DataFrame) -> pd.DataFrame:
    """Apply all feature engineering steps to the decision table.

    Parameters
    ----------
    df : pd.DataFrame
        Cleaned decision-level data frame.

    Returns
    -------
    pd.DataFrame
        Enriched data frame ready for export to R.
    """
    df = add_score_state(df)
    df = add_home_advantage_flag(df)
    df = add_referee_experience(df)
    df = add_decision_counts(df)
    return df
