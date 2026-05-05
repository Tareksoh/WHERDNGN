#!/usr/bin/env python3
"""
WHEREDNGN calibration analyzer.

Reads SavedVariables/WHEREDNGN.lua and produces threshold-tuning
insights from the v0.8.3 telemetry table (`WHEREDNGNDB.history`).

USAGE
-----
    python tools/calibrate.py <path/to/WHEREDNGN.lua>
    python tools/calibrate.py --paste            # paste from clipboard
    python tools/calibrate.py --json out.json    # dump parsed rows as JSON

Where to find SavedVariables on Windows:
    World of Warcraft\\_retail_\\WTF\\Account\\<ID>\\SavedVariables\\WHEREDNGN.lua

The script is ZERO-DEPENDENCY: only stdlib. Parsing is hand-written
because Lua-table syntax is simple enough for the row schema.

WHAT THIS PRODUCES
------------------
  • Bid-rate breakdown: R1 vs R2, contract-type mix
  • Bel/Triple/Four/Gahwa fire rates (vs the calibrated thresholds)
  • Bidder make/fail rate by contract type and tier
  • Score-position urgency: how often the bot was in clinch / desperate
  • Sweep frequency
  • Calibration recommendations vs current K.* thresholds

INTERPRETATION
--------------
The bot's thresholds (K.BOT_BEL_TH, K.BOT_GAHWA_TH, etc.) were
calibrated on theory + symmetric-distribution playtest. Real game
telemetry from human-asymmetric deals will reveal whether:
  - thresholds are too high (low fire rate --> bot under-bids)
  - thresholds are too low (high fail rate --> bot over-bids)
  - tier ordering holds (higher tiers should win more)

Send the dumped output (or just the SavedVariables file) back and
we'll tune from real data.
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from collections import Counter, defaultdict
from pathlib import Path
from typing import Any


# Pattern that matches a Lua-table key=value pair. Handles strings,
# numbers, and nested tables (one level deep is enough for history rows).
_KV_RE = re.compile(r'(\w+)\s*=\s*("(?:[^"\\]|\\.)*"|-?\d+\.?\d*|true|false|nil|\{[^{}]*\})')


def parse_lua_table_block(text: str) -> list[dict[str, Any]]:
    """
    Parse `WHEREDNGNDB.history = { {row}, {row}, ... }` into a list of dicts.

    Robust to row order, missing fields, hand-edits. Skips malformed rows.
    """
    # Locate the history table assignment.
    history_match = re.search(
        r'(?:WHEREDNGNDB\s*=\s*\{[^}]*?)?'  # WHEREDNGNDB outer (optional)
        r'history\s*=\s*\{(.*?)^\s*\}\s*,?\s*$',
        text,
        re.DOTALL | re.MULTILINE,
    )
    if not history_match:
        # Fallback: simpler pattern, accept whatever's between history = { ... }
        m = re.search(r'\["?history"?\]\s*=\s*\{(.*?)\n\s*\}', text, re.DOTALL)
        if m:
            inner = m.group(1)
        else:
            return []
    else:
        inner = history_match.group(1)

    # Split into row blocks. Each row is `{ key = val, key = val, ... },`
    rows: list[dict[str, Any]] = []
    depth = 0
    start = None
    for i, ch in enumerate(inner):
        if ch == "{":
            if depth == 0:
                start = i
            depth += 1
        elif ch == "}":
            depth -= 1
            if depth == 0 and start is not None:
                row_text = inner[start + 1 : i]
                row = parse_row(row_text)
                if row:
                    rows.append(row)
                start = None
    return rows


def parse_row(text: str) -> dict[str, Any]:
    out: dict[str, Any] = {}
    for k, v in _KV_RE.findall(text):
        out[k] = parse_value(v)
    return out


def parse_value(v: str) -> Any:
    if v.startswith('"') and v.endswith('"'):
        return v[1:-1].encode("utf-8").decode("unicode_escape")
    if v == "true":
        return True
    if v == "false":
        return False
    if v == "nil":
        return None
    try:
        if "." in v:
            return float(v)
        return int(v)
    except ValueError:
        return v


def report(rows: list[dict[str, Any]]) -> None:
    if not rows:
        print("no telemetry rows found.")
        print()
        print("if you ran some games:")
        print("  • check that `/baloot history off` wasn't run")
        print("  • verify the SavedVariables path matches your character")
        print("  • try `/baloot history` in-game to see the dump count")
        return

    print(f"=== telemetry analyzer ({len(rows)} rows) ===")
    print()

    # Contract-type mix.
    types = Counter(r.get("type", "?") for r in rows)
    print("contract-type mix:")
    for t, n in types.most_common():
        pct = 100 * n / len(rows)
        print(f"  {t:6s}  {n:4d}  ({pct:5.1f}%)")
    print()

    # Bid round.
    rounds = Counter(r.get("bidRound", 0) for r in rows)
    print("bid-round breakdown (R0=forced/qaid):")
    for br, n in sorted(rounds.items()):
        pct = 100 * n / len(rows)
        print(f"  R{br}    {n:4d}  ({pct:5.1f}%)")
    print()

    # Bidder make/fail.
    made = Counter(r.get("bidderMade", -1) for r in rows)
    print("bidder make/fail (1=made, 0=failed, -1=N/A):")
    for code in (1, 0, -1):
        n = made.get(code, 0)
        pct = 100 * n / len(rows) if rows else 0
        label = {1: "made", 0: "failed", -1: "n/a"}[code]
        print(f"  {label:6s}  {n:4d}  ({pct:5.1f}%)")
    print()

    # Multiplier flags.
    mult_fires = {
        "doubled": sum(1 for r in rows if r.get("doubled") == 1),
        "tripled": sum(1 for r in rows if r.get("tripled") == 1),
        "foured":  sum(1 for r in rows if r.get("foured")  == 1),
        "gahwa":   sum(1 for r in rows if r.get("gahwa")   == 1),
    }
    print("escalation fire rates (Bel/Triple/Four/Gahwa):")
    for k, n in mult_fires.items():
        pct = 100 * n / len(rows) if rows else 0
        print(f"  {k:8s}  {n:4d}  ({pct:5.1f}%)")
    print()

    # Sweeps.
    sweeps = Counter(r.get("sweep", "") for r in rows if r.get("sweep"))
    sweep_total = sum(sweeps.values())
    sweep_pct = 100 * sweep_total / len(rows) if rows else 0
    print(f"sweeps: {sweep_total} ({sweep_pct:.1f}%)")
    for team, n in sweeps.most_common():
        if team:
            print(f"  team {team}  {n:4d}")
    print()

    # Per-bidder seat performance.
    by_bidder = defaultdict(lambda: {"made": 0, "failed": 0, "delta": 0})
    for r in rows:
        b = r.get("bidder")
        if b is None:
            continue
        outcome = r.get("bidderMade")
        team = "A" if b in (1, 3) else "B"
        if outcome == 1:
            by_bidder[b]["made"] += 1
        elif outcome == 0:
            by_bidder[b]["failed"] += 1
        addX = r.get("addA" if team == "A" else "addB", 0)
        addO = r.get("addB" if team == "A" else "addA", 0)
        by_bidder[b]["delta"] += addX - addO
    print("per-bidder make/fail + cumulative delta:")
    for b in sorted(by_bidder):
        stats = by_bidder[b]
        total = stats["made"] + stats["failed"]
        rate = 100 * stats["made"] / total if total else 0
        print(f"  seat {b}  bids={total:3d}  made={stats['made']:3d}  "
              f"failed={stats['failed']:3d}  rate={rate:4.0f}%  "
              f"deltaSum={stats['delta']:+5d}")
    print()

    # v0.9.6+ Bot-vs-human bidder split (requires v>=2 rows). Pre-v0.9.6
    # rows lack `bidderIsBot`; we skip them. This is the most important
    # signal for calibration: distinguishes "bot bidding too aggressive"
    # from "human bidding too aggressive."
    bot_v2 = [r for r in rows if r.get("v", 1) >= 2 and "bidderIsBot" in r]
    if bot_v2:
        bot_bids = [r for r in bot_v2 if r.get("bidderIsBot") == 1]
        human_bids = [r for r in bot_v2 if r.get("bidderIsBot") == 0]
        def _stats(rs):
            if not rs:
                return None
            made = sum(1 for r in rs if r.get("bidderMade") == 1)
            failed = sum(1 for r in rs if r.get("bidderMade") == 0)
            total = made + failed
            rate = 100 * made / total if total else 0
            return total, made, failed, rate
        print("bot vs human bidder (v>=2 rows only):")
        bs = _stats(bot_bids)
        if bs:
            t, m, f, r = bs
            print(f"  bot bidders   bids={t:3d}  made={m:3d}  failed={f:3d}  fail-rate={100-r:4.1f}%")
        hs = _stats(human_bids)
        if hs:
            t, m, f, r = hs
            print(f"  human bidders bids={t:3d}  made={m:3d}  failed={f:3d}  fail-rate={100-r:4.1f}%")
        if bs and hs and bs[0] >= 5 and hs[0] >= 5:
            bot_fail = 100 - bs[3]
            human_fail = 100 - hs[3]
            spread = abs(bot_fail - human_fail)
            print(f"  spread        |bot - human| fail-rate = {spread:.1f}pp")
            if spread > 15:
                print("    >> CALIBRATION SIGNAL: large bot/human gap suggests")
                print("       a tier or threshold mismatch worth investigating.")
        print()
    elif rows:
        v1_count = sum(1 for r in rows if r.get("v", 1) == 1)
        if v1_count == len(rows):
            print("(all rows are v=1, pre-v0.9.6 schema; no bot/human split"
                  " available. Play more rounds with v0.9.6+ to enable.)")
            print()

    # Calibration recommendations.
    print("calibration signals:")
    bid_rate = 100 * (len(rows) - rounds.get(0, 0) if isinstance(rounds.get(0), int) else len(rows)) / len(rows) if rows else 0
    fail_rate = 100 * made.get(0, 0) / max(1, made.get(0, 0) + made.get(1, 0))
    bel_rate = 100 * mult_fires["doubled"] / len(rows)
    trp_rate = 100 * mult_fires["tripled"] / len(rows)
    gah_rate = 100 * mult_fires["gahwa"] / len(rows)

    print(f"  - bidder fail rate: {fail_rate:.1f}%  "
          f"(target ~30-40% on competitive bidding; lower --> too conservative)")
    print(f"  - Bel rate: {bel_rate:.1f}%  "
          f"(BOT_BEL_TH=60; expect 20-35% in mixed-tier play)")
    print(f"  - Triple rate: {trp_rate:.1f}%  "
          f"(BOT_TRIPLE_TH=90; expect 5-15% downstream of Bel)")
    print(f"  - Gahwa rate: {gah_rate:.1f}%  "
          f"(BOT_GAHWA_TH=135; expect <2% - terminal commit)")
    print(f"  - sweep rate: {sweep_pct:.1f}%  "
          f"(typically 5-12% in skilled play)")
    print()

    print("if any of these is dramatically off (especially fail-rate or"
          " Bel-rate), thresholds need tuning. send this output back"
          " for refit.")


def main() -> int:
    p = argparse.ArgumentParser(description="WHEREDNGN calibration analyzer.")
    p.add_argument("path", nargs="?",
                   help="path to SavedVariables/WHEREDNGN.lua")
    p.add_argument("--json", metavar="OUT",
                   help="dump parsed rows as JSON")
    p.add_argument("--paste", action="store_true",
                   help="read Lua content from stdin (paste)")
    args = p.parse_args()

    if args.paste:
        text = sys.stdin.read()
    elif args.path:
        text = Path(args.path).read_text(encoding="utf-8", errors="replace")
    else:
        p.print_help()
        return 2

    rows = parse_lua_table_block(text)
    if args.json:
        Path(args.json).write_text(json.dumps(rows, indent=2))
        print(f"wrote {len(rows)} rows to {args.json}")
    else:
        report(rows)
    return 0


if __name__ == "__main__":
    sys.exit(main())
