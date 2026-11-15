#!/usr/bin/env python3
"""Append the day's extract to the raw (historical) tables.

Raw tables are append-only. Nothing is ever updated or deleted here:

  * each run selects extract rows by their update-time column, starting a little before the
    newest value already loaded (the overlap), and appends them with a _loaded_at timestamp
  * a row that changed at the source is appended again as a new version; the old one stays
  * the overlap, or running the same load twice, appends copies that are already there

That is deliberate. Deciding which version is current, and collapsing copies, is the
staging layer's job (latest row per key). Keeping raw append-only means a bad
transformation is fixed by rebuilding from raw, never by going back to the source, and
every version the source ever sent is still there to audit.

What this cannot see: a row hard-deleted at the source, or a row changed without its
update time being bumped. Those need a reconciliation against the source.
"""

from __future__ import annotations

import argparse
from datetime import date, datetime
from pathlib import Path

import duckdb

# table -> the column that says when the source last wrote the row
TABLES = {
    "users": "updated_at",
    "kyc_submissions": "updated_at",
    "deposits": "updated_at",
    "withdrawals": "updated_at",
    "trades": "updated_at",
    "asset_prices": "price_date",
    "tracking_events": "received_at",
}


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--as-of", required=True, help="extract date, YYYY-MM-DD; recorded as _loaded_at")
    parser.add_argument("--extract-dir", default="data/extract")
    parser.add_argument("--database", default="exchange.duckdb")
    parser.add_argument("--overlap-hours", type=int, default=24,
                        help="re-read this far behind the newest loaded row, to cover late commits")
    args = parser.parse_args()

    # The demo replays past days, so _loaded_at is the extract date, not the wall clock.
    # That keeps every run reproducible. A real loader would use the current time.
    loaded_at = datetime.combine(date.fromisoformat(args.as_of), datetime.max.time()).replace(microsecond=0)

    con = duckdb.connect(args.database)
    con.execute("create schema if not exists raw")
    print(f"Load into raw, _loaded_at = {loaded_at}:")

    for table, cursor in TABLES.items():
        path = Path(args.extract_dir) / f"{table}.csv"
        # Everything lands as text. Typing is an explicit decision made in staging.
        extract = f"read_csv('{path}', all_varchar = true, header = true)"
        con.execute(
            f"create table if not exists raw.{table} as "
            f"select *, cast(null as timestamp) as _loaded_at from {extract} limit 0"
        )
        watermark = con.execute(f"select max(cast({cursor} as timestamp)) from raw.{table}").fetchone()[0]
        where = ""
        if watermark is not None:
            where = (f"where cast({cursor} as timestamp) >= "
                     f"timestamp '{watermark}' - interval '{args.overlap_hours} hours'")
        before = con.execute(f"select count(*) from raw.{table}").fetchone()[0]
        con.execute(f"insert into raw.{table} select *, timestamp '{loaded_at}' from {extract} {where}")
        after = con.execute(f"select count(*) from raw.{table}").fetchone()[0]
        print(f"  raw.{table:<18} +{after - before:>6,} rows  (total {after:>7,})")

    con.close()


if __name__ == "__main__":
    main()
