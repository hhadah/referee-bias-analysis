"""
Export utilities – write analysis-ready data for consumption in R.

Writes the decision-level data frame to ``data/processed/`` as both
Parquet (preferred for large data) and CSV (for quick inspection).
"""

from __future__ import annotations

import logging
from pathlib import Path

import pandas as pd

logger = logging.getLogger(__name__)

PROCESSED_DIR = Path(__file__).resolve().parents[2] / "data" / "processed"


def export_for_r(
    df: pd.DataFrame,
    stem: str = "decisions",
    processed_dir: Path | None = None,
    formats: tuple[str, ...] = ("parquet", "csv"),
) -> dict[str, Path]:
    """Write the analysis-ready data frame to disk.

    Parameters
    ----------
    df : pd.DataFrame
        Enriched decision-level data frame.
    stem : str
        Base file name without extension.
    processed_dir : Path, optional
        Output directory.  Defaults to ``data/processed/``.
    formats : tuple of str
        Which file formats to write.  Supported: ``"parquet"``, ``"csv"``.

    Returns
    -------
    dict[str, Path]
        Mapping of format string to written file path.
    """
    out_dir = processed_dir or PROCESSED_DIR
    out_dir.mkdir(parents=True, exist_ok=True)

    written: dict[str, Path] = {}
    for fmt in formats:
        if fmt == "parquet":
            path = out_dir / f"{stem}.parquet"
            df.to_parquet(path, index=False)
        elif fmt == "csv":
            path = out_dir / f"{stem}.csv"
            df.to_csv(path, index=False)
        else:
            logger.warning("Unknown format '%s'; skipping.", fmt)
            continue
        logger.info("Exported %s rows → %s", len(df), path)
        written[fmt] = path
    return written
