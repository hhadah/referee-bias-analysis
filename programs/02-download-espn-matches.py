"""
02-download-espn-matches.py

Purpose : Download match-level refereeing data (fouls, cards, penalties,
          possession, stoppage time, referee, attendance) from ESPN's public
          site API for the top-5 European leagues and the UEFA Champions
          League, 2001/02 to present.
Output  : data/raw/espn/json/<league>/<season>/<event_id>.json.gz  (trimmed
          raw responses, one per match) and
          data/raw/espn/events-index-<league>.csv (scoreboard index).
Date    : 2026-10-02

Usage   : python3 programs/02-download-espn-matches.py [--first 2001] [--last 2026]
          [--leagues esp.1 uefa.champions] [--workers 6]

The script is idempotent: matches already on disk are skipped, so it can be
re-run to top up the current season.
"""

import argparse
import csv
import gzip
import json
import os
import random
import sys
import time
import urllib.error
import urllib.request
from concurrent.futures import ThreadPoolExecutor, as_completed

try:
    from tqdm import tqdm
except ImportError:  # tqdm is optional
    def tqdm(x, **kwargs):
        return x

BASE = "https://site.api.espn.com/apis/site/v2/sports/soccer"
LEAGUES = ["eng.1", "esp.1", "ita.1", "ger.1", "fra.1", "uefa.champions"]
HEADERS = {"User-Agent": "Mozilla/5.0 (research; referee-bias-analysis)",
           "Accept-Encoding": "gzip"}

# Keys kept from the match summary; the rest (news, videos, commentary,
# standings, rosters) is dropped to keep the raw archive small.
KEEP_SUMMARY = ["boxscore", "gameInfo", "keyEvents", "header", "format"]


def get_json(url, tries=6):
    """Fetch a URL and return parsed JSON, retrying with backoff on errors."""
    for k in range(tries):
        try:
            req = urllib.request.Request(url, headers=HEADERS)
            with urllib.request.urlopen(req, timeout=40) as f:
                body = f.read()
                if f.headers.get("Content-Encoding") == "gzip":
                    body = gzip.decompress(body)
            return json.loads(body)
        except urllib.error.HTTPError as e:
            if e.code in (400, 404):
                return None
            wait = (2 ** k) + random.random()
        except Exception:
            wait = (2 ** k) + random.random()
        time.sleep(wait)
    print(f"  [warn] giving up on {url}", file=sys.stderr)
    return None


def season_months(start_year):
    """Return the YYYYMM strings spanning a European season.

    June of the start year through August of the following year, so that the
    Covid-delayed end of 2019/20 (July-August 2020) is included. Events are
    assigned to seasons by ESPN's season.year, so overlapping months are safe.
    """
    months = [f"{start_year}{m:02d}" for m in range(6, 13)]
    months += [f"{start_year + 1}{m:02d}" for m in range(1, 9)]
    return months


def index_season(league, start_year):
    """List all ESPN events for one league-season from the monthly scoreboards."""
    rows, seen = [], set()
    months = season_months(start_year)
    with ThreadPoolExecutor(max_workers=len(months)) as ex:
        boards = list(ex.map(
            lambda ym: get_json(f"{BASE}/{league}/scoreboard?dates={ym}&limit=1000"), months))
    for d in boards:
        if not d:
            continue
        for e in d.get("events", []):
            # Skip malformed scoreboard entries (no id or no competition block)
            if "id" not in e or not e.get("competitions") or e["id"] in seen:
                continue
            season = e.get("season", {})
            if season.get("year") != start_year:
                continue
            seen.add(e["id"])
            comp = e["competitions"][0]
            teams = {c.get("homeAway"): c for c in comp.get("competitors", [])}
            notes = comp.get("notes") or []
            rows.append({
                "league": league,
                "season_start": start_year,
                "event_id": e["id"],
                "date": e["date"],
                "round_slug": season.get("slug"),
                "note": notes[0].get("headline") if notes else None,
                "status": comp.get("status", {}).get("type", {}).get("name"),
                "home_id": teams.get("home", {}).get("team", {}).get("id"),
                "home_name": teams.get("home", {}).get("team", {}).get("displayName"),
                "away_id": teams.get("away", {}).get("team", {}).get("id"),
                "away_name": teams.get("away", {}).get("team", {}).get("displayName"),
            })
    return rows


def fetch_match(league, start_year, event_id, out_root):
    """Download one match summary and store a trimmed, gzipped copy."""
    path = os.path.join(out_root, league, str(start_year), f"{event_id}.json.gz")
    if os.path.exists(path):
        return "cached"
    d = get_json(f"{BASE}/{league}/summary?event={event_id}")
    if d is None:
        return "missing"
    slim = {k: d.get(k) for k in KEEP_SUMMARY}
    os.makedirs(os.path.dirname(path), exist_ok=True)
    try:
        with gzip.open(path + ".tmp", "wt", encoding="utf-8") as f:
            json.dump(slim, f, separators=(",", ":"))
        os.replace(path + ".tmp", path)
    except OSError as err:
        print(f"  [error] could not write {path}: {err}", file=sys.stderr)
        return "error"
    return "ok"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--first", type=int, default=2001)
    ap.add_argument("--last", type=int, default=2026)
    ap.add_argument("--leagues", nargs="+", default=LEAGUES)
    ap.add_argument("--workers", type=int, default=6)
    ap.add_argument("--reuse-index", action="store_true",
                    help="skip re-indexing a league whose events index already exists")
    ap.add_argument("--root", default=os.path.join(
        os.path.dirname(os.path.abspath(__file__)), "..", "data", "raw", "espn"))
    args = ap.parse_args()

    root = os.path.normpath(args.root)
    json_root = os.path.join(root, "json")
    os.makedirs(json_root, exist_ok=True)

    for league in args.leagues:
        index_path = os.path.join(root, f"events-index-{league}.csv")
        if args.reuse_index and os.path.exists(index_path):
            try:
                with open(index_path, newline="", encoding="utf-8") as f:
                    index_rows = list(csv.DictReader(f))
            except OSError as err:
                print(f"  [error] could not read index {index_path}: {err}", file=sys.stderr)
                continue
            print(f"[{league}] reusing index with {len(index_rows)} events")
        else:
            index_rows = []
            print(f"[{league}] indexing seasons {args.first}-{args.last}")
            for yr in range(args.first, args.last + 1):
                rows = index_season(league, yr)
                print(f"  {league} {yr}/{str(yr + 1)[-2:]}: {len(rows)} events")
                index_rows += rows
            try:
                with open(index_path, "w", newline="", encoding="utf-8") as f:
                    w = csv.DictWriter(f, fieldnames=list(index_rows[0].keys()))
                    w.writeheader()
                    w.writerows(index_rows)
            except (OSError, IndexError) as err:
                print(f"  [error] could not write index {index_path}: {err}", file=sys.stderr)
                continue

        todo = [r for r in index_rows if r["status"] == "STATUS_FULL_TIME"
                or "FINAL" in (r["status"] or "") or "END" in (r["status"] or "")]
        print(f"[{league}] {len(index_rows)} indexed, {len(todo)} completed matches to fetch")
        tally = {}
        with ThreadPoolExecutor(max_workers=args.workers) as ex:
            futs = [ex.submit(fetch_match, league, r["season_start"], r["event_id"], json_root)
                    for r in todo]
            for fu in tqdm(as_completed(futs), total=len(futs), desc=league, mininterval=30):
                res = fu.result()
                tally[res] = tally.get(res, 0) + 1
        print(f"[{league}] done: {tally}")


if __name__ == "__main__":
    main()
