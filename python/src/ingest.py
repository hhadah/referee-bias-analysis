"""
Data ingestion for referee bias analysis.

This module provides two loader classes:

``MatchDataLoader``
    Loads *match-level* data (schedule, result, referee assignment).
    Supports local files, football-data.co.uk HTTP downloads, and FBref
    referee-fixture tables.

``DecisionDataLoader``
    Loads *decision-level* data (one row per referee decision per match).
    Supports local files, StatsBomb open-data events, and understat.com
    embedded-JSON event streams.

Data sources
------------
- football-data.co.uk  – free CSV downloads, long history, referee column
- FBref                – referee-fixture table via pandas.read_html
- StatsBomb open data  – structured JSON events (fouls, cards, VAR)
- understat.com        – embedded JS JSON with shot/match events
"""

from __future__ import annotations

import io
import json
import logging
import re
import time
from pathlib import Path
from typing import Optional

import pandas as pd
import requests
from bs4 import BeautifulSoup

logger = logging.getLogger(__name__)

RAW_DIR = Path(__file__).resolve().parents[2] / "data" / "raw"

# ---------------------------------------------------------------------------
# Shared HTTP helpers
# ---------------------------------------------------------------------------

_SESSION = requests.Session()
_SESSION.headers.update(
    {
        "User-Agent": (
            "Mozilla/5.0 (compatible; referee-bias-analysis/0.1; "
            "+https://github.com/hhadah/referee-bias-analysis)"
        )
    }
)

_REQUEST_DELAY = 2.0  # seconds between outbound requests (be polite)


def _get(url: str, **kwargs) -> requests.Response:
    """Perform a polite GET request with retry on transient errors."""
    for attempt in range(3):
        try:
            resp = _SESSION.get(url, timeout=30, **kwargs)
            resp.raise_for_status()
            return resp
        except requests.HTTPError as exc:
            if exc.response is not None and exc.response.status_code == 404:
                raise
            logger.warning("HTTP error on attempt %d for %s: %s", attempt + 1, url, exc)
            time.sleep(5 * (attempt + 1))
        except requests.RequestException as exc:
            logger.warning("Request error on attempt %d for %s: %s", attempt + 1, url, exc)
            time.sleep(5 * (attempt + 1))
    raise RuntimeError(f"Failed to fetch {url} after 3 attempts")


# ---------------------------------------------------------------------------
# football-data.co.uk helpers
# ---------------------------------------------------------------------------

# Map our competition identifiers to the two-character league codes used
# in football-data.co.uk URLs, e.g.
#   https://www.football-data.co.uk/mmz4281/2324/E0.csv
_FDCO_LEAGUE_CODE: dict[str, str] = {
    "premier_league": "E0",
    "la_liga": "SP1",
    "bundesliga": "D1",
    "serie_a": "I1",
    "ligue_1": "F1",
}

_FDCO_BASE = "https://www.football-data.co.uk/mmz4281"


def _fdco_season_code(season: str) -> str:
    """Convert ``"2023-24"`` → ``"2324"`` (football-data.co.uk format)."""
    parts = season.split("-")
    if len(parts) != 2:
        raise ValueError(f"Season must be in 'YYYY-YY' format, got '{season}'")
    return parts[0][2:] + parts[1].zfill(2)


# ---------------------------------------------------------------------------
# FBref helpers
# ---------------------------------------------------------------------------

# Map our competition identifiers to FBref referee schedule page IDs.
# These are the stable URL slugs on fbref.com.
_FBREF_COMP_ID: dict[str, str] = {
    "premier_league": "9",
    "la_liga": "12",
    "bundesliga": "20",
    "serie_a": "11",
    "ligue_1": "13",
    "champions_league": "8",
}

_FBREF_BASE = "https://fbref.com/en/comps"


# ---------------------------------------------------------------------------
# understat helpers
# ---------------------------------------------------------------------------

_UNDERSTAT_LEAGUE: dict[str, str] = {
    "premier_league": "EPL",
    "la_liga": "La_liga",
    "bundesliga": "Bundesliga",
    "serie_a": "Serie_A",
    "ligue_1": "Ligue_1",
}

_UNDERSTAT_BASE = "https://understat.com/league"


def _understat_season_year(season: str) -> str:
    """Convert ``"2023-24"`` → ``"2023"`` (understat uses start year)."""
    return season.split("-")[0]


def _extract_understat_json(html: str, var_name: str) -> list[dict]:
    """Pull a JSON blob from understat's embedded ``var name = JSON`` script."""
    pattern = re.compile(
        rf"var\s+{re.escape(var_name)}\s*=\s*JSON\.parse\('(.+?)'\)",
        re.DOTALL,
    )
    match = pattern.search(html)
    if not match:
        raise ValueError(f"Could not find '{var_name}' in understat HTML")
    raw = match.group(1).encode("utf-8").decode("unicode_escape")
    return json.loads(raw)


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
        Directory where raw data files are stored/cached.
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
        """Load match data from a local CSV / Parquet file in ``raw_dir``.

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

    def fetch_from_football_data_co_uk(self, save: bool = True) -> pd.DataFrame:
        """Download season CSV from football-data.co.uk and return a DataFrame.

        The CSV is saved to ``raw_dir`` for future offline use unless
        ``save=False``.

        Parameters
        ----------
        save : bool
            If ``True`` (default), write the downloaded CSV to ``raw_dir``.

        Returns
        -------
        pd.DataFrame
            Raw match-level data frame with columns including ``HomeTeam``,
            ``AwayTeam``, ``Referee``, ``Date``, result columns, and many
            betting-odds columns that can be ignored.

        Raises
        ------
        ValueError
            If the competition is ``"champions_league"`` (not hosted on
            football-data.co.uk).
        requests.HTTPError
            On HTTP failures.
        """
        if self.competition == "champions_league":
            raise ValueError(
                "football-data.co.uk does not host Champions League data. "
                "Use fetch_from_fbref() or fetch_from_statsbomb_open() instead."
            )

        league_code = _FDCO_LEAGUE_CODE[self.competition]
        season_code = _fdco_season_code(self.season)
        url = f"{_FDCO_BASE}/{season_code}/{league_code}.csv"

        logger.info("Fetching match data from %s", url)
        time.sleep(_REQUEST_DELAY)
        resp = _get(url)

        # football-data.co.uk CSVs are ISO-8859-1 encoded
        df = pd.read_csv(
            io.BytesIO(resp.content),
            encoding="ISO-8859-1",
            on_bad_lines="skip",
        )
        # Drop rows with no date (sometimes trailing blank rows)
        df = df.dropna(subset=["Date"])
        logger.info(
            "Downloaded %d matches for %s %s from football-data.co.uk",
            len(df),
            self.competition,
            self.season,
        )

        if save:
            self.raw_dir.mkdir(parents=True, exist_ok=True)
            out_path = (
                self.raw_dir
                / f"fdco_{self.competition}_{self.season.replace('-', '_')}.csv"
            )
            df.to_csv(out_path, index=False)
            logger.info("Saved to %s", out_path)

        return df

    def fetch_from_fbref(self, save: bool = True) -> pd.DataFrame:
        """Scrape the referee-fixture table from FBref for this competition/season.

        Fetches the fixtures page for the competition and parses the HTML table
        that includes referee names.  Returns one row per match.

        Parameters
        ----------
        save : bool
            If ``True`` (default), write the result as CSV to ``raw_dir``.

        Returns
        -------
        pd.DataFrame
            Data frame with at least ``Date``, ``Home``, ``Away``, and
            ``Referee`` columns (actual column names depend on FBref).

        Raises
        ------
        ValueError
            If no table with referee data is found on the page.
        requests.HTTPError
            On HTTP failures.
        """
        comp_id = _FBREF_COMP_ID.get(self.competition)
        if comp_id is None:
            raise ValueError(
                f"No FBref competition ID for '{self.competition}'. "
                f"Known: {list(_FBREF_COMP_ID)}"
            )

        season_start = self.season.split("-")[0]
        url = f"{_FBREF_BASE}/{comp_id}/{season_start}-{int(season_start)+1}/schedule/"

        logger.info("Fetching FBref schedule from %s", url)
        time.sleep(_REQUEST_DELAY)
        resp = _get(url)

        soup = BeautifulSoup(resp.text, "lxml")
        # FBref wraps data tables in <div id="div_sched_...">
        tables = soup.find_all("table", id=re.compile(r"sched"))
        if not tables:
            raise ValueError(
                f"No schedule table found at {url}. "
                "FBref may have changed its page structure."
            )

        # Pick the first schedule table and parse it with pandas
        df = pd.read_html(str(tables[0]), encoding="utf-8")[0]
        # Drop rows that are header repetitions (some columns repeat mid-table)
        df = df[df["Date"].notna() & (df["Date"] != "Date")].copy()
        df = df.reset_index(drop=True)
        logger.info(
            "Scraped %d rows from FBref for %s %s",
            len(df),
            self.competition,
            self.season,
        )

        if save:
            self.raw_dir.mkdir(parents=True, exist_ok=True)
            out_path = (
                self.raw_dir
                / f"fbref_{self.competition}_{self.season.replace('-', '_')}.csv"
            )
            df.to_csv(out_path, index=False)
            logger.info("Saved to %s", out_path)

        return df


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
        Directory where raw data files are stored/cached.
    """

    # StatsBomb event types that map to referee decisions
    _SB_DECISION_TYPES: set[str] = {
        "Foul Committed",
        "Foul Won",
        "Yellow Card",
        "Red Card",
        "Second Yellow",
        "Penalty Shootout",
        "Offside",
        "Bad Behaviour",
        "50/50",
    }

    def __init__(self, raw_dir: Optional[Path] = None) -> None:
        self.raw_dir = raw_dir or RAW_DIR

    def load_from_file(self, filename: str) -> pd.DataFrame:
        """Load decision data from a local CSV / Parquet file in ``raw_dir``.

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

    def fetch_from_statsbomb_open(
        self,
        competition_id: Optional[int] = None,
        season_id: Optional[int] = None,
        save: bool = True,
    ) -> pd.DataFrame:
        """Fetch referee-relevant events from the StatsBomb open-data repository.

        Downloads match metadata and event JSONs directly from the public
        StatsBomb GitHub repository.  Filters to foul, card, and penalty
        events that represent referee decisions.

        Parameters
        ----------
        competition_id : int, optional
            StatsBomb competition ID.  If omitted, fetches all available
            competitions (slow – use ``season_id`` filter too).
        season_id : int, optional
            StatsBomb season ID.  Used together with ``competition_id`` to
            select a specific season.
        save : bool
            If ``True`` (default), save the result as Parquet to ``raw_dir``.

        Returns
        -------
        pd.DataFrame
            Decision-level data frame with columns: ``match_id``,
            ``competition``, ``season``, ``match_date``, ``home_team``,
            ``away_team``, ``referee``, ``team``, ``decision_type``,
            ``minute``, ``var_involved``, ``decision_for_team``.

        Raises
        ------
        requests.HTTPError
            On network failure.
        """
        try:
            from statsbombpy import sb  # type: ignore[import]
        except ImportError as exc:
            raise ImportError(
                "Install statsbombpy: pip install statsbombpy"
            ) from exc

        logger.info("Loading StatsBomb competition index…")
        comps = sb.competitions()

        if competition_id is not None:
            comps = comps[comps["competition_id"] == competition_id]
        if season_id is not None:
            comps = comps[comps["season_id"] == season_id]

        if comps.empty:
            raise ValueError(
                "No competitions matched the given competition_id / season_id. "
                "Run statsbombpy.sb.competitions() to see available entries."
            )

        all_decisions: list[pd.DataFrame] = []

        for _, row in comps.iterrows():
            cid = int(row["competition_id"])
            sid = int(row["season_id"])
            comp_name = row["competition_name"]
            season_name = row["season_name"]
            logger.info("Fetching matches for %s %s…", comp_name, season_name)

            try:
                matches = sb.matches(competition_id=cid, season_id=sid)
            except Exception as exc:  # noqa: BLE001
                logger.warning("Could not fetch matches for cid=%d sid=%d: %s", cid, sid, exc)
                continue

            for _, match in matches.iterrows():
                mid = int(match["match_id"])
                logger.debug("  match_id=%d", mid)
                try:
                    events = sb.events(match_id=mid)
                except Exception as exc:  # noqa: BLE001
                    logger.warning("Could not fetch events for match %d: %s", mid, exc)
                    continue

                decision_events = events[events["type"].isin(self._SB_DECISION_TYPES)].copy()
                if decision_events.empty:
                    continue

                decision_events["match_id"] = str(mid)
                decision_events["competition"] = comp_name
                decision_events["season"] = season_name
                decision_events["match_date"] = match.get("match_date")
                decision_events["home_team"] = match.get("home_team")
                decision_events["away_team"] = match.get("away_team")
                decision_events["referee"] = match.get("referee")

                # Map StatsBomb type names → our canonical decision_type
                type_map = {
                    "Foul Committed": "foul",
                    "Foul Won": "foul",
                    "Yellow Card": "yellow_card",
                    "Red Card": "red_card",
                    "Second Yellow": "red_card",
                    "Penalty Shootout": "penalty",
                    "Offside": "offside",
                    "Bad Behaviour": "yellow_card",
                    "50/50": "foul",
                }
                decision_events["decision_type"] = decision_events["type"].map(type_map)

                # decision_for_team: True when the decision benefits the team in possession
                # For fouls: "Foul Won" benefits the team; "Foul Committed" costs them
                decision_events["decision_for_team"] = decision_events["type"].isin(
                    {"Foul Won", "Offside"}
                )
                # StatsBomb open data does not reliably expose VAR flags;
                # set var_involved=False and let it be enriched from match-level sources.
                decision_events["var_involved"] = False

                cols = [
                    "match_id", "competition", "season", "match_date",
                    "home_team", "away_team", "referee", "team",
                    "decision_type", "minute", "var_involved", "decision_for_team",
                ]
                available = [c for c in cols if c in decision_events.columns]
                all_decisions.append(decision_events[available])

        if not all_decisions:
            logger.warning("No decision events found for the selected competitions/seasons.")
            return pd.DataFrame()

        df = pd.concat(all_decisions, ignore_index=True)
        logger.info("Total StatsBomb decisions collected: %d", len(df))

        if save:
            self.raw_dir.mkdir(parents=True, exist_ok=True)
            out_path = self.raw_dir / "statsbomb_decisions.parquet"
            df.to_parquet(out_path, index=False)
            logger.info("Saved to %s", out_path)

        return df

    def fetch_from_understat(
        self,
        season: Optional[str] = None,
        competition: str = "premier_league",
        save: bool = True,
    ) -> pd.DataFrame:
        """Scrape match-level data from understat.com.

        Understat embeds match metadata (teams, xG, result, date) as a JSON
        blob inside a ``<script>`` tag.  This method extracts that blob and
        returns one row per match.

        Note: understat provides match-level xG/result data, not individual
        referee decision events.  Use this to enrich match context; combine
        with football-data.co.uk for referee names.

        Parameters
        ----------
        season : str, optional
            Season start year, e.g. ``"2023"`` for 2023-24.  Defaults to the
            current calendar year.
        competition : str
            Competition identifier (must be in ``_UNDERSTAT_LEAGUE`` map).
        save : bool
            If ``True`` (default), save the result as CSV to ``raw_dir``.

        Returns
        -------
        pd.DataFrame
            One row per match with columns: ``id``, ``h`` (home team info),
            ``a`` (away team info), ``goals``, ``xG``, ``datetime``, etc.

        Raises
        ------
        ValueError
            If ``competition`` is not supported or the JSON cannot be parsed.
        requests.HTTPError
            On network failure.
        """
        league_key = _UNDERSTAT_LEAGUE.get(competition)
        if league_key is None:
            raise ValueError(
                f"No understat league key for '{competition}'. "
                f"Supported: {list(_UNDERSTAT_LEAGUE)}"
            )

        import datetime as _dt

        season_year = season or str(_dt.date.today().year - 1)
        url = f"{_UNDERSTAT_BASE}/{league_key}/{season_year}"

        logger.info("Fetching understat data from %s", url)
        time.sleep(_REQUEST_DELAY)
        resp = _get(url)

        raw_matches = _extract_understat_json(resp.text, "datesData")
        df = pd.json_normalize(raw_matches)
        logger.info(
            "Scraped %d matches from understat for %s %s",
            len(df),
            competition,
            season_year,
        )

        if save:
            self.raw_dir.mkdir(parents=True, exist_ok=True)
            out_path = (
                self.raw_dir
                / f"understat_{competition}_{season_year}.csv"
            )
            df.to_csv(out_path, index=False)
            logger.info("Saved to %s", out_path)

        return df
