#!/usr/bin/env python3
"""Synthetic source data for a fictional crypto exchange.

Everything here is generated. No real users, no real company data.

This plays the part of the extract step: it writes what the source systems would return
on a given day into data/extract/. scripts/load_raw.py then appends those rows to the raw
tables in the warehouse.

The full timeline (START..END) is always generated from the same seed, then cut at
--as-of. A row is written only if the source system would have had it by then, and
mutable rows (users, deposits, withdrawals) show their state as of that moment. Running
with two different --as-of dates therefore behaves like two daily extracts, which is what
the snapshot (SCD2) and incremental models need to be demonstrated honestly.

Deliberate data problems, so the staging layer has something real to fix:
  * tracking events contain exact duplicates (client retries)
  * some events and trades arrive days late (received_at / updated_at > event time)
  * currency codes arrive in mixed case
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import random
from datetime import date, datetime, timedelta
from pathlib import Path

START = datetime(2026, 7, 1)
END = datetime(2026, 10, 31, 23, 59, 59)
N_USERS = 1500
SEED = 42

COUNTRIES = [("ID", 45), ("MY", 15), ("AE", 12), ("TR", 12), ("PK", 10), ("NG", 6)]
CHANNELS = [("organic", 40), ("referral", 25), ("paid_social", 20), ("paid_search", 15)]
PLATFORMS = [("android", 55), ("ios", 30), ("web", 15)]
CRYPTO = ["BTC", "ETH", "SOL"]
BASE_PRICE = {"BTC": 64000.0, "ETH": 3100.0, "SOL": 145.0}
REJECT_REASONS = ["blurry_document", "name_mismatch", "expired_document", "underage"]


def weighted(rng: random.Random, pairs):
    return rng.choices([p[0] for p in pairs], weights=[p[1] for p in pairs])[0]


def fmt(ts: datetime | None) -> str:
    return ts.strftime("%Y-%m-%d %H:%M:%S") if ts else ""


def messy_case(rng: random.Random, code: str) -> str:
    """Source systems disagree on casing. Staging normalises it."""
    return code.lower() if rng.random() < 0.08 else code


def make_id(prefix: str, *parts) -> str:
    digest = hashlib.md5("|".join(str(p) for p in parts).encode()).hexdigest()[:16]
    return f"{prefix}_{digest}"


def build_prices(rng: random.Random):
    prices = {}
    days = (END.date() - START.date()).days + 1
    for asset in CRYPTO:
        price = BASE_PRICE[asset]
        for i in range(days):
            price *= 1 + rng.gauss(0.0005, 0.025)
            prices[(START.date() + timedelta(days=i), asset)] = round(price, 2)
    for i in range(days):
        day = START.date() + timedelta(days=i)
        prices[(day, "USDT")] = 1.0
        prices[(day, "USD")] = 1.0
    return prices


def build_timeline():
    rng = random.Random(SEED)
    prices = build_prices(rng)
    span = (END - START).total_seconds()

    users, kyc, deposits, withdrawals, trades, events = [], [], [], [], [], []

    def add_event(ts, user_id, anon_id, name, platform, late_ok=True):
        if ts > END:
            return
        delay = timedelta(seconds=rng.randint(1, 90))
        if late_ok and rng.random() < 0.02:  # offline device syncing days later
            delay = timedelta(days=rng.randint(1, 4), hours=rng.randint(0, 23))
        row = {
            "event_id": make_id("evt", user_id, anon_id, name, ts.isoformat()),
            "event_name": name,
            "event_timestamp": ts,
            "received_at": ts + delay,
            "user_id": user_id,
            "anonymous_id": anon_id,
            "platform": platform,
        }
        events.append(row)
        if rng.random() < 0.01:  # client retry: same event sent twice
            dup = dict(row)
            dup["received_at"] = row["received_at"] + timedelta(seconds=rng.randint(1, 30))
            events.append(dup)

    for n in range(1, N_USERS + 1):
        user_id = 100000 + n
        # sqrt skews signups toward the recent end: a growing product.
        created = START + timedelta(seconds=span * (rng.random() ** 0.6))
        platform = weighted(rng, PLATFORMS)
        anon_id = make_id("anon", user_id)
        # (timestamp, field, value) - the user row's history.
        changes = []
        user = {
            "user_id": user_id,
            "email": f"user{user_id}@example.com",
            "country_code": weighted(rng, COUNTRIES),
            "signup_channel": weighted(rng, CHANNELS),
            "created_at": created,
            "changes": changes,
        }
        users.append(user)

        # Anonymous browsing before signup, then the signup itself.
        add_event(created - timedelta(minutes=rng.randint(2, 30)), None, anon_id, "page_view", platform)
        add_event(created, user_id, anon_id, "sign_up", platform, late_ok=False)

        if rng.random() < 0.03:  # user moved; a Type 2 change on the dimension
            moved = created + timedelta(days=rng.randint(10, 60))
            changes.append((moved, "country_code", weighted(rng, COUNTRIES)))

        # ---- KYC ----
        approved_at = None
        if rng.random() < 0.78:
            submitted = created + timedelta(hours=rng.randint(0, 120), minutes=rng.randint(0, 59))
            add_event(submitted - timedelta(minutes=5), user_id, anon_id, "kyc_started", platform)
            for attempt in range(1, 4):
                reviewed = submitted + timedelta(hours=rng.randint(1, 48))
                ok = rng.random() < (0.68 if attempt == 1 else 0.8)
                kyc.append({
                    "submission_id": make_id("kyc", user_id, attempt),
                    "user_id": user_id,
                    "attempt_number": attempt,
                    "document_type": rng.choice(["national_id", "passport", "driving_license"]),
                    "submitted_at": submitted,
                    "reviewed_at": reviewed,
                    "final_status": "approved" if ok else "rejected",
                    "rejection_reason": "" if ok else rng.choice(REJECT_REASONS),
                })
                add_event(submitted, user_id, anon_id, "kyc_submitted", platform)
                if ok:
                    approved_at = reviewed
                    changes.append((reviewed, "kyc_level", 1))
                    break
                if rng.random() > 0.6:
                    break
                submitted = reviewed + timedelta(hours=rng.randint(2, 96))

        # ---- Money movement (KYC-approved users only) ----
        if approved_at and rng.random() < 0.72:
            cursor = approved_at + timedelta(hours=rng.randint(1, 72))
            n_deposits = 1 + int(rng.expovariate(0.6))
            first_deposit = None
            for d in range(n_deposits):
                if cursor > END:
                    break
                currency = rng.choices(["USDT", "USD", "BTC", "ETH"], weights=[55, 25, 10, 10])[0]
                usd_value = round(rng.lognormvariate(5.3, 1.1), 2)
                px = prices[(cursor.date(), currency)]
                roll = rng.random()
                deposits.append({
                    "deposit_id": make_id("dep", user_id, d),
                    "user_id": user_id,
                    "currency": messy_case(rng, currency),
                    "amount": round(usd_value / px, 8),
                    "network_fee": 0 if currency == "USD" else round(rng.uniform(0.1, 2.0) / px, 8),
                    "final_status": "completed" if roll < 0.93 else "failed",
                    "created_at": cursor,
                    "settled_at": cursor + timedelta(minutes=rng.randint(2, 600)),
                })
                add_event(cursor, user_id, anon_id, "deposit_initiated", platform)
                first_deposit = first_deposit or cursor
                cursor += timedelta(days=rng.expovariate(1 / 9))

            # Trades
            if first_deposit and rng.random() < 0.85:
                t = first_deposit + timedelta(hours=rng.randint(1, 48))
                n_trades = int(rng.lognormvariate(1.6, 1.0)) + 1
                for k in range(n_trades):
                    if t > END:
                        break
                    base = rng.choices(CRYPTO, weights=[50, 30, 20])[0]
                    px = prices[(t.date(), base)] * (1 + rng.gauss(0, 0.004))
                    usd_value = rng.lognormvariate(4.6, 1.0)
                    filled = rng.random() < 0.94
                    # ~3% reach the warehouse late: matching engine replays, manual corrections.
                    late = rng.random() < 0.03
                    updated = t + (timedelta(days=rng.randint(1, 5)) if late else timedelta(seconds=rng.randint(1, 30)))
                    trades.append({
                        "trade_id": make_id("trd", user_id, k),
                        "user_id": user_id,
                        "base_asset": messy_case(rng, base),
                        "quote_asset": "USDT",
                        "side": rng.choices(["buy", "sell"], weights=[62, 38])[0],
                        "quantity": round(usd_value / px, 8),
                        "price": round(px, 2),
                        "fee_quote": round(usd_value * 0.001, 6),
                        "status": "filled" if filled else "cancelled",
                        "executed_at": t,
                        "updated_at": updated,
                    })
                    add_event(t, user_id, anon_id, "trade_placed", platform)
                    t += timedelta(hours=rng.expovariate(1 / 60))

            # Withdrawals
            if first_deposit and rng.random() < 0.4:
                w = first_deposit + timedelta(days=rng.randint(2, 40))
                for k in range(1 + int(rng.expovariate(1.2))):
                    if w > END:
                        break
                    currency = rng.choices(["USDT", "USD", "BTC", "ETH"], weights=[50, 30, 10, 10])[0]
                    usd_value = round(rng.lognormvariate(5.0, 1.0), 2)
                    px = prices[(w.date(), currency)]
                    roll = rng.random()
                    withdrawals.append({
                        "withdrawal_id": make_id("wdr", user_id, k),
                        "user_id": user_id,
                        "currency": messy_case(rng, currency),
                        "amount": round(usd_value / px, 8),
                        "fee": round(max(1.0, usd_value * 0.002) / px, 8),
                        "final_status": "completed" if roll < 0.9 else ("rejected" if roll < 0.96 else "failed"),
                        "created_at": w,
                        "settled_at": w + timedelta(minutes=rng.randint(10, 1440)),
                    })
                    add_event(w, user_id, anon_id, "withdrawal_requested", platform)
                    w += timedelta(days=rng.expovariate(1 / 14))

            if rng.random() < 0.02:  # compliance action
                changes.append((approved_at + timedelta(days=rng.randint(5, 50)), "account_status", "suspended"))

        # Background app usage.
        s = created
        for _ in range(int(rng.expovariate(1 / 12))):
            s += timedelta(hours=rng.expovariate(1 / 40))
            add_event(s, user_id, anon_id, rng.choice(["app_open", "page_view", "price_alert_viewed"]), platform)

    return prices, users, kyc, deposits, withdrawals, trades, events


def write_csv(path: Path, header, rows):
    with path.open("w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(header)
        writer.writerows(rows)
    print(f"  {path.name:<22} {len(rows):>7,} rows")


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--as-of", default=END.date().isoformat(), help="extract date, YYYY-MM-DD (end of that day)")
    parser.add_argument("--out", default="data/extract")
    args = parser.parse_args()

    as_of = datetime.combine(date.fromisoformat(args.as_of), datetime.max.time()).replace(microsecond=0)
    if not START <= as_of <= END:
        raise SystemExit(f"--as-of must be between {START.date()} and {END.date()}")
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)

    prices, users, kyc, deposits, withdrawals, trades, events = build_timeline()
    print(f"Extract as of {as_of}:")

    rows = []
    for u in users:
        if u["created_at"] > as_of:
            continue
        state = {"country_code": u["country_code"], "kyc_level": 0, "account_status": "active"}
        updated = u["created_at"]
        for ts, field, value in sorted(u["changes"]):
            if ts <= as_of:
                state[field] = value
                updated = max(updated, ts)
        rows.append([u["user_id"], u["email"], state["country_code"], u["signup_channel"],
                     state["kyc_level"], state["account_status"], fmt(u["created_at"]), fmt(updated)])
    write_csv(out / "users.csv",
              ["user_id", "email", "country_code", "signup_channel", "kyc_level", "account_status",
               "created_at", "updated_at"], rows)

    rows = []
    for k in kyc:
        if k["submitted_at"] > as_of:
            continue
        done = k["reviewed_at"] <= as_of
        rows.append([k["submission_id"], k["user_id"], k["attempt_number"], k["document_type"],
                     k["final_status"] if done else "pending", k["rejection_reason"] if done else "",
                     fmt(k["submitted_at"]), fmt(k["reviewed_at"]) if done else "",
                     fmt(k["reviewed_at"] if done else k["submitted_at"])])
    write_csv(out / "kyc_submissions.csv",
              ["submission_id", "user_id", "attempt_number", "document_type", "status", "rejection_reason",
               "submitted_at", "reviewed_at", "updated_at"], rows)

    rows = []
    for d in deposits:
        if d["created_at"] > as_of:
            continue
        done = d["settled_at"] <= as_of
        rows.append([d["deposit_id"], d["user_id"], d["currency"], d["amount"], d["network_fee"],
                     d["final_status"] if done else "pending", fmt(d["created_at"]),
                     fmt(d["settled_at"]) if done else "", fmt(d["settled_at"] if done else d["created_at"])])
    write_csv(out / "deposits.csv",
              ["deposit_id", "user_id", "currency", "amount", "network_fee", "status", "created_at",
               "completed_at", "updated_at"], rows)

    rows = []
    for w in withdrawals:
        if w["created_at"] > as_of:
            continue
        done = w["settled_at"] <= as_of
        rows.append([w["withdrawal_id"], w["user_id"], w["currency"], w["amount"], w["fee"],
                     w["final_status"] if done else "pending", fmt(w["created_at"]),
                     fmt(w["settled_at"]) if done else "", fmt(w["settled_at"] if done else w["created_at"])])
    write_csv(out / "withdrawals.csv",
              ["withdrawal_id", "user_id", "currency", "amount", "fee", "status", "created_at",
               "completed_at", "updated_at"], rows)

    # A trade is visible only once the trading system has written it (updated_at).
    rows = [[t["trade_id"], t["user_id"], t["base_asset"], t["quote_asset"], t["side"], t["quantity"],
             t["price"], t["fee_quote"], t["status"], fmt(t["executed_at"]), fmt(t["updated_at"])]
            for t in trades if t["updated_at"] <= as_of]
    write_csv(out / "trades.csv",
              ["trade_id", "user_id", "base_asset", "quote_asset", "side", "quantity", "price", "fee_quote",
               "status", "executed_at", "updated_at"], rows)

    rows = [[day.isoformat(), asset, price] for (day, asset), price in sorted(prices.items())
            if day <= as_of.date()]
    write_csv(out / "asset_prices.csv", ["price_date", "asset_code", "price_usd"], rows)

    rows = [[e["event_id"], e["event_name"], fmt(e["event_timestamp"]), fmt(e["received_at"]),
             e["user_id"] or "", e["anonymous_id"], e["platform"]]
            for e in sorted(events, key=lambda e: e["received_at"]) if e["received_at"] <= as_of]
    write_csv(out / "tracking_events.csv",
              ["event_id", "event_name", "event_timestamp", "received_at", "user_id", "anonymous_id", "platform"],
              rows)


if __name__ == "__main__":
    main()
