#!/usr/bin/env python3
"""
WHEREDNGN calibration analyzer.

Reads SavedVariables/WHEREDNGN.lua and produces threshold-tuning
insights from the v0.8.3 telemetry table (`WHEREDNGNDB.history`).

USAGE
-----
    python tools/calibrate.py <path/to/WHEREDNGN.lua>
    python tools/calibrate.py file1.lua file2.lua file3.lua   # combined
    python tools/calibrate.py --paste            # paste from clipboard
    python tools/calibrate.py --json out.json    # dump parsed rows as JSON

    # Targeted breakdowns (printed in addition to the default report):
    python tools/calibrate.py --breakdown=bidcard      one.lua
    python tools/calibrate.py --breakdown=tier         one.lua
    python tools/calibrate.py --breakdown=escalation   one.lua
    python tools/calibrate.py --breakdown=r0           one.lua
    python tools/calibrate.py --breakdown=sweep-prog   one.lua
    python tools/calibrate.py --breakdown=round-dist   one.lua
    python tools/calibrate.py --breakdown=all          one.lua

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

  Extended (v2 schema rows + --breakdown):
  • Per-bidcard-rank make/fail (does bidcard=A vs bidcard=7 matter?)
  • Per-tier make/fail (Advanced/M3lm/Fzloky/SaudiMaster bot bidders)
  • Escalation chain progression (Hokm -> Bel -> Triple -> Four -> Gahwa)
  • R0 sub-categorization (forced/qaid/ashkal)
  • Round-1 vs Round-2 distribution with Wilson 95% CIs
  • Sweep-progression placeholder (requires schema extension; see
    SCHEMA_PROPOSAL.md)

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
import math
import re
import sys
from collections import Counter, defaultdict
from pathlib import Path
from typing import Any, Optional


# Pattern that matches a Lua-table key=value pair. Handles both bare
# (`key = value`) and bracket-string (`["key"] = value`) forms — WoW
# SavedVariables emits the latter for all named keys. Values may be
# strings, numbers, booleans, nil, or one-level-nested tables.
_KV_RE = re.compile(
    r'(?:\[\s*"(\w+)"\s*\]|(\w+))\s*=\s*'
    r'("(?:[^"\\]|\\.)*"|-?\d+\.?\d*|true|false|nil|\{[^{}]*\})'
)


def parse_lua_table_block(text: str) -> list[dict[str, Any]]:
    """
    Parse `WHEREDNGNDB.history = { {row}, {row}, ... }` into a list of dicts.

    Robust to row order, missing fields, hand-edits. Skips malformed rows.

    Handles both Lua-source forms WoW emits:
      * `history = { ... }`              (dot-or-bare key)
      * `["history"] = { ... }`          (bracketed-string key — actual WoW
                                          SavedVariables format)
    """
    # Locate the `history = {` opener. WoW emits `["history"] = {` for
    # subkeys of WHEREDNGNDB; bare `history = {` is the older form. Search
    # for either, then walk braces from the opening `{` to find the matching
    # close — non-greedy regex `.*?\n\s*\}` was wrong because it terminated
    # at the FIRST `\n}` (= the close of the first row, not the whole table).
    opener = re.search(
        r'(?:\[\s*"history"\s*\]|history)\s*=\s*\{',
        text,
    )
    if not opener:
        return []
    open_brace = opener.end() - 1   # index of the `{` itself

    # Walk forward from the opening brace, tracking depth, to find the
    # matching close. depth starts at 0 BEFORE reading the open brace;
    # when we read it, depth becomes 1; when matching close drops back
    # to 0, we've found the end.
    depth = 0
    close_brace = None
    in_string = False
    str_quote = None
    i = open_brace
    while i < len(text):
        ch = text[i]
        if in_string:
            if ch == "\\":
                i += 2
                continue
            if ch == str_quote:
                in_string = False
                str_quote = None
        else:
            if ch in ('"', "'"):
                in_string = True
                str_quote = ch
            elif ch == "{":
                depth += 1
            elif ch == "}":
                depth -= 1
                if depth == 0:
                    close_brace = i
                    break
        i += 1
    if close_brace is None:
        return []

    inner = text[open_brace + 1 : close_brace]

    # Split into row blocks. Each row is `{ key = val, key = val, ... },`
    rows: list[dict[str, Any]] = []
    depth = 0
    start = None
    in_string = False
    str_quote = None
    for i, ch in enumerate(inner):
        if in_string:
            if ch == "\\":
                continue
            if ch == str_quote:
                in_string = False
                str_quote = None
            continue
        if ch in ('"', "'"):
            in_string = True
            str_quote = ch
            continue
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
    for bracket_k, bare_k, v in _KV_RE.findall(text):
        key = bracket_k or bare_k
        if key:
            out[key] = parse_value(v)
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


# ---------------------------------------------------------------------
# Top-level WHEREDNGNDB flag parser. The history rows themselves do not
# carry `bidderTier`; we infer tier-at-dump-time from the global flags
# (`saudiMasterBots`, `fzlokyBots`, `m3lmBots`, `advancedBots`). This is
# a best-effort fallback — if the user toggled tiers MID-DUMP some rows
# will be mis-tagged. See SCHEMA_PROPOSAL.md for the proposed per-row
# fix.
# ---------------------------------------------------------------------
_TIER_FLAG_RE = re.compile(
    r'\[\s*"(saudiMasterBots|fzlokyBots|m3lmBots|advancedBots)"\s*\]\s*=\s*'
    r'(true|false)'
)


def parse_top_level_tier(text: str) -> Optional[str]:
    """Return the highest active tier flag at top-level scope, or None."""
    flags: dict[str, bool] = {}
    for m in _TIER_FLAG_RE.finditer(text):
        flags[m.group(1)] = (m.group(2) == "true")
    # Strict-extension order: SaudiMaster > Fzloky > M3lm > Advanced.
    # Mirrors Bot.IsAdvanced/IsM3lm/etc. which all return true if a higher
    # tier is set (Bot.lua:70-101).
    if flags.get("saudiMasterBots"): return "SaudiMaster"
    if flags.get("fzlokyBots"):      return "Fzloky"
    if flags.get("m3lmBots"):        return "M3lm"
    if flags.get("advancedBots"):    return "Advanced"
    if flags:  # all explicitly false
        return "Basic"
    return None


# ---------------------------------------------------------------------
# Stats helpers (stdlib only).
# ---------------------------------------------------------------------
def wilson_ci(successes: int, total: int, z: float = 1.96) -> tuple[float, float]:
    """Wilson score 95% CI for a proportion. Returns (lo, hi) in [0, 1].

    Better than normal-approx for small samples (which is the whole point —
    33 rounds is small). Pure stdlib.
    """
    if total == 0:
        return (0.0, 0.0)
    p = successes / total
    n = total
    denom = 1 + z * z / n
    centre = p + z * z / (2 * n)
    margin = z * math.sqrt(p * (1 - p) / n + z * z / (4 * n * n))
    lo = (centre - margin) / denom
    hi = (centre + margin) / denom
    return (max(0.0, lo), min(1.0, hi))


def fmt_pct_ci(n: int, total: int) -> str:
    if total == 0:
        return "n/a"
    p = 100 * n / total
    lo, hi = wilson_ci(n, total)
    return f"{p:5.1f}%  [95% CI {100*lo:4.1f}-{100*hi:4.1f}%]"


# bidcard rank parser. The schema stores e.g. "8H", "KH", "AS" (rank then
# suit, single-char each except 10 -> "T" or "10"). Older rows might be
# empty string if bidCard was nil. We strip suit and return rank only.
_BIDCARD_RE = re.compile(r"^([A234567891TJQK]+)([SHDC])$")


def parse_bidcard_rank(s: Any) -> Optional[str]:
    if not isinstance(s, str) or not s:
        return None
    m = _BIDCARD_RE.match(s)
    if not m:
        return None
    rank = m.group(1)
    if rank == "10":
        rank = "T"
    return rank


# ---------------------------------------------------------------------
# Reporting.
# ---------------------------------------------------------------------
def report(rows: list[dict[str, Any]],
           tier_hints: Optional[dict[str, str]] = None,
           breakdowns: Optional[set[str]] = None) -> None:
    """
    breakdowns: subset of {bidcard, tier, escalation, r0, sweep-prog,
                          round-dist, all}. Empty / None -> default report only.
    tier_hints: optional file-name -> tier mapping (used for per-tier
                inference when rows lack `bidderTier`). Currently only
                used for the global-tier fallback.
    """
    breakdowns = breakdowns or set()
    if "all" in breakdowns:
        breakdowns = {"bidcard", "tier", "escalation", "r0",
                      "sweep-prog", "round-dist"}

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
          f"(BOT_BEL_TH=35 post-v0.11.20; expect 10-25% in mixed-tier play)")
    print(f"  - Triple rate: {trp_rate:.1f}%  "
          f"(BOT_TRIPLE_TH=90; expect 5-15% downstream of Bel)")
    print(f"  - Gahwa rate: {gah_rate:.1f}%  "
          f"(BOT_GAHWA_TH=135; expect <2% - terminal commit)")
    print(f"  - sweep rate: {sweep_pct:.1f}%  "
          f"(typically 5-12% in skilled play)")
    print()

    # -----------------------------------------------------------------
    # Extended sections (gated on --breakdown).
    # -----------------------------------------------------------------
    if "round-dist" in breakdowns:
        _report_round_distribution(rows)
    if "bidcard" in breakdowns:
        _report_bidcard_breakdown(rows)
    if "tier" in breakdowns:
        _report_tier_breakdown(rows, tier_hints or {})
    if "escalation" in breakdowns:
        _report_escalation_chain(rows)
    if "r0" in breakdowns:
        _report_r0_breakdown(rows)
    if "sweep-prog" in breakdowns:
        _report_sweep_progression(rows)

    print("if any of these is dramatically off (especially fail-rate or"
          " Bel-rate), thresholds need tuning. send this output back"
          " for refit.")


# ---------------------------------------------------------------------
# Extended report sections.
# ---------------------------------------------------------------------
def _report_round_distribution(rows: list[dict[str, Any]]) -> None:
    """R1 vs R2 contract-type distribution with Wilson 95% CIs.

    Suggestion #6: 24/9 user split = R1 73% vs canonical 50-60%. Surface
    confidence intervals so we can tell whether the tilt is real or
    sample noise.
    """
    print("--- round-1 vs round-2 distribution (Wilson 95% CIs) ---")
    total = len(rows)
    r1 = [r for r in rows if r.get("bidRound") == 1]
    r2 = [r for r in rows if r.get("bidRound") == 2]
    r0 = [r for r in rows if r.get("bidRound") == 0]
    print(f"  R1 contracts: {len(r1):3d}/{total}  {fmt_pct_ci(len(r1), total)}")
    print(f"  R2 contracts: {len(r2):3d}/{total}  {fmt_pct_ci(len(r2), total)}")
    if r0:
        print(f"  R0 contracts: {len(r0):3d}/{total}  {fmt_pct_ci(len(r0), total)}")
    print()
    # Per-round contract type mix.
    for label, rs in (("R1", r1), ("R2", r2)):
        if not rs:
            continue
        types = Counter(r.get("type", "?") for r in rs)
        line = ", ".join(
            f"{t}={n}/{len(rs)} ({fmt_pct_ci(n, len(rs))})"
            for t, n in types.most_common()
        )
        print(f"  {label} type-mix: {line}")
    print("  (canonical R1 share for mixed-tier play: 50-60%; deviation")
    print("   beyond CI may indicate over-aggressive R1 bidding.)")
    print()


def _report_bidcard_breakdown(rows: list[dict[str, Any]]) -> None:
    """Per-bidcard-rank make/fail rate.

    Bot.PickBid uses `withBidcard` weighting; rank should affect outcomes.
    Useful for verifying that bidcard=A produces dramatically different
    make rates than bidcard=7.
    """
    print("--- per-bidcard-rank breakdown ---")
    have = [r for r in rows if parse_bidcard_rank(r.get("bidCard"))]
    missing = len(rows) - len(have)
    if missing:
        print(f"  ({missing} rows have no parseable bidCard -- pre-v0.9.6 or")
        print("   redeal/forced rounds. Excluded from this section.)")
    if not have:
        print("  no bidCard data available.")
        print()
        return

    # Rank order for display: A high, then K Q J T 9 8 7. (Plain order; trump
    # order J 9 A T K Q 8 7 isn't relevant to bidcard signaling.)
    rank_order = {r: i for i, r in enumerate(["A", "K", "Q", "J", "T", "9", "8", "7"])}

    by_rank: dict[str, dict[str, int]] = defaultdict(
        lambda: {"made": 0, "failed": 0, "na": 0,
                 "hokm": 0, "sun": 0, "ashkal": 0,
                 "bel": 0, "triple": 0, "four": 0, "gahwa": 0}
    )
    for r in have:
        rank = parse_bidcard_rank(r.get("bidCard"))
        if rank is None:
            continue
        s = by_rank[rank]
        outcome = r.get("bidderMade")
        if outcome == 1: s["made"] += 1
        elif outcome == 0: s["failed"] += 1
        else: s["na"] += 1
        t = r.get("type", "")
        if t == "HOKM": s["hokm"] += 1
        elif t == "SUN": s["sun"] += 1
        elif t == "ASHKAL": s["ashkal"] += 1
        if r.get("doubled") == 1: s["bel"] += 1
        if r.get("tripled") == 1: s["triple"] += 1
        if r.get("foured") == 1: s["four"] += 1
        if r.get("gahwa") == 1: s["gahwa"] += 1

    print(f"  {'rank':4s} {'n':>4s} {'made':>4s} {'fail':>4s} {'fail%':>16s}"
          f"  Hokm/Sun/Ashk  Bel/Trp/Four/Gah")
    for rank in sorted(by_rank, key=lambda r: rank_order.get(r, 99)):
        s = by_rank[rank]
        n = s["made"] + s["failed"] + s["na"]
        decisive = s["made"] + s["failed"]
        fail_str = fmt_pct_ci(s["failed"], decisive) if decisive else "n/a"
        type_str = f"{s['hokm']:2d}/{s['sun']:2d}/{s['ashkal']:2d}"
        esc_str = f"{s['bel']:2d}/{s['triple']:2d}/{s['four']:2d}/{s['gahwa']:2d}"
        print(f"  {rank:4s} {n:4d} {s['made']:4d} {s['failed']:4d} "
              f"{fail_str:>16s}  {type_str:>13s}  {esc_str}")
    print()


def _report_tier_breakdown(rows: list[dict[str, Any]],
                            tier_hints: dict[str, str]) -> None:
    """Per-tier bidder fail-rate split.

    The schema does NOT carry per-row `bidderTier`. We use two fallbacks:
      1. Per-row `bidderTier` if present (proposed schema addition).
      2. File-level top-level `saudiMasterBots`/etc. flag, applied to all
         BOT bidders in that file.

    Human bidders are reported separately under "human" tier label.
    """
    print("--- per-tier bidder breakdown ---")
    print("  (tier source: per-row 'bidderTier' field if present;")
    print("   else file-level flag at dump time. See SCHEMA_PROPOSAL.md.)")
    print()

    # Group by tier.
    by_tier: dict[str, list[dict[str, Any]]] = defaultdict(list)
    for r in rows:
        is_bot = r.get("bidderIsBot")
        if is_bot == 0:
            by_tier["human"].append(r)
            continue
        if is_bot == 1:
            tier = r.get("bidderTier")
            if not tier:
                tier = r.get("_inferredTier")  # injected by main()
            if not tier:
                tier = "bot(unknown-tier)"
            by_tier[tier].append(r)
        else:
            by_tier["unknown"].append(r)

    if not by_tier:
        print("  no bidder data.")
        print()
        return

    print(f"  {'tier':18s} {'n':>4s} {'made':>4s} {'fail':>4s} {'fail%':>20s}")
    # Order by descending sample size, then alpha.
    for tier in sorted(by_tier, key=lambda t: (-len(by_tier[t]), t)):
        rs = by_tier[tier]
        made = sum(1 for r in rs if r.get("bidderMade") == 1)
        failed = sum(1 for r in rs if r.get("bidderMade") == 0)
        decisive = made + failed
        fail_str = fmt_pct_ci(failed, decisive) if decisive else "n/a"
        print(f"  {tier:18s} {len(rs):4d} {made:4d} {failed:4d} {fail_str:>20s}")
    print()
    # Sanity gate: signal if SaudiMaster has notably worse fail rate
    # than Advanced.
    def _fail_rate(tier: str) -> Optional[float]:
        rs = by_tier.get(tier, [])
        if len(rs) < 5: return None
        m = sum(1 for r in rs if r.get("bidderMade") == 1)
        f = sum(1 for r in rs if r.get("bidderMade") == 0)
        if m + f == 0: return None
        return 100 * f / (m + f)
    sm = _fail_rate("SaudiMaster")
    adv = _fail_rate("Advanced")
    if sm is not None and adv is not None and sm > adv + 10:
        print("  >> CALIBRATION SIGNAL: SaudiMaster bot fail-rate is more")
        print("     than 10pp HIGHER than Advanced -- tier ordering may be")
        print("     inverted. Investigate BotMaster.PickPlay (ISMCTS).")
        print()


def _report_escalation_chain(rows: list[dict[str, Any]]) -> None:
    """Of N Hokm contracts, how many had Bel? Of those, Triple? etc.

    Bel/Triple/Four/Gahwa form a strict chain — Triple cannot fire without
    Bel having fired first, etc. This breakdown shows the per-rung
    progression rate.
    """
    print("--- escalation chain progression ---")
    hokm = [r for r in rows if r.get("type") == "HOKM"]
    sun = [r for r in rows if r.get("type") == "SUN"]

    def _chain(rs: list[dict[str, Any]], label: str):
        n = len(rs)
        if n == 0:
            print(f"  {label}: 0 contracts.")
            return
        bel = [r for r in rs if r.get("doubled") == 1]
        trp = [r for r in bel if r.get("tripled") == 1]
        four = [r for r in trp if r.get("foured") == 1]
        gah = [r for r in four if r.get("gahwa") == 1]
        # Per-rung breakdown — denominator is parent rung where applicable.
        print(f"  {label}: {n} contracts")
        print(f"    Bel    : {len(bel):3d}/{n}    ({fmt_pct_ci(len(bel), n)})")
        if len(bel):
            print(f"    Triple : {len(trp):3d}/{len(bel)} (of Bel)  ({fmt_pct_ci(len(trp), len(bel))})")
        if len(trp):
            print(f"    Four   : {len(four):3d}/{len(trp)} (of Trp)  ({fmt_pct_ci(len(four), len(trp))})")
        if len(four):
            print(f"    Gahwa  : {len(gah):3d}/{len(four)} (of Four) ({fmt_pct_ci(len(gah), len(four))})")
        # Outcome of escalated rounds — was the escalation justified?
        if bel:
            bel_made = sum(1 for r in bel if r.get("bidderMade") == 1)
            bel_failed = sum(1 for r in bel if r.get("bidderMade") == 0)
            decisive = bel_made + bel_failed
            if decisive:
                print(f"    Bel-round bidder outcome: made={bel_made} "
                      f"failed={bel_failed}  fail-rate={fmt_pct_ci(bel_failed, decisive)}")

    _chain(hokm, "Hokm")
    _chain(sun, "Sun")
    if not hokm and not sun:
        print("  (no Hokm or Sun contracts.)")
    print()


def _report_r0_breakdown(rows: list[dict[str, Any]]) -> None:
    """R0 sub-categorization: forced, qaid (round-2 forced), Ashkal.

    `bidRound=0` collapses three distinct paths in the current schema:
      1. forced=1 + type=HOKM/SUN: dealer forced to bid on R2-all-pass.
      2. type=ASHKAL: bidder declared Ashkal (cannot win 4 tricks).
      3. forced=1 + type=ASHKAL: forced Ashkal (qaid-style mandatory).

    With the current schema we can distinguish (1) vs (2/3) via the
    `forced` flag + `type`. Adding a `r0Reason` field would fully
    disambiguate (see SCHEMA_PROPOSAL.md).
    """
    print("--- R0 (forced/qaid/ashkal) sub-categorization ---")
    r0 = [r for r in rows if r.get("bidRound") == 0]
    if not r0:
        print("  no R0 rounds in dataset.")
        print()
        return
    print(f"  total R0: {len(r0)}/{len(rows)}  ({100*len(r0)/len(rows):.1f}%)")

    forced_hokm = [r for r in r0 if r.get("forced") == 1 and r.get("type") == "HOKM"]
    forced_sun = [r for r in r0 if r.get("forced") == 1 and r.get("type") == "SUN"]
    ashkal = [r for r in r0 if r.get("type") == "ASHKAL"]
    other = [r for r in r0 if r not in forced_hokm and r not in forced_sun
             and r not in ashkal]

    def _line(label: str, rs: list[dict[str, Any]]):
        if not rs: return
        made = sum(1 for r in rs if r.get("bidderMade") == 1)
        failed = sum(1 for r in rs if r.get("bidderMade") == 0)
        n = len(rs)
        decisive = made + failed
        fail = fmt_pct_ci(failed, decisive) if decisive else "n/a"
        print(f"    {label:18s}  n={n:3d}  made={made:3d} failed={failed:3d}  fail%={fail}")

    _line("forced Hokm",  forced_hokm)
    _line("forced Sun",   forced_sun)
    _line("Ashkal",       ashkal)
    _line("other R0",     other)
    print()


def _report_sweep_progression(rows: list[dict[str, Any]]) -> None:
    """Sweep / Al-Kaboot pursuit tracking.

    v1.0.0 (schema v=3): consumes the per-row `trickWinners` field
    (e.g. "ABBABBAB") plus `tricksA` / `tricksB` counts written by
    `S.ApplyRoundEnd`. Pre-v=3 rows omit these fields; the report
    falls back to final-outcome stats only for those rows.
    """
    print("--- sweep progression ---")
    total = len(rows)
    a_sweep = sum(1 for r in rows if r.get("sweep") == "A")
    b_sweep = sum(1 for r in rows if r.get("sweep") == "B")
    no_sweep = total - a_sweep - b_sweep

    print(f"  team-A sweep: {a_sweep:3d}/{total}  {fmt_pct_ci(a_sweep, total)}")
    print(f"  team-B sweep: {b_sweep:3d}/{total}  {fmt_pct_ci(b_sweep, total)}")
    print(f"  no sweep    : {no_sweep:3d}/{total}  {fmt_pct_ci(no_sweep, total)}")

    # Per-bidder-team sweep (was bidder's team the one that swept?).
    bid_team_sweep = 0
    bid_team_swept_against = 0
    for r in rows:
        b = r.get("bidder")
        sw = r.get("sweep", "")
        if not b or not sw: continue
        bid_team = "A" if b in (1, 3) else "B"
        if sw == bid_team:
            bid_team_sweep += 1
        else:
            bid_team_swept_against += 1
    swept_total = bid_team_sweep + bid_team_swept_against
    if swept_total:
        print(f"  of {swept_total} sweep rounds: bidder swept {bid_team_sweep}, "
              f"got swept {bid_team_swept_against}  (Al-Kaboot signal)")
    print()

    # v=3 per-trick progression. Each row's trickWinners is a string
    # like "ABBABBAB" (length 1-8). Only count v=3 rows that have the
    # field set (older v=2 rows would have it absent).
    v3_rows = [r for r in rows if r.get("trickWinners")]
    if not v3_rows:
        print("  (per-trick progression requires schema v=3; play more rounds")
        print("   on a v1.0.0+ install to populate trickWinners field)")
        print()
        return

    print(f"--- per-trick progression (v=3 rows: {len(v3_rows)}/{total}) ---")
    # For each trick index 1-8, count team A wins vs team B wins.
    by_trick_a = [0] * 9   # 1-indexed
    by_trick_b = [0] * 9
    for r in v3_rows:
        tw = r.get("trickWinners", "")
        for i, ch in enumerate(tw, start=1):
            if i > 8: break
            if ch == "A": by_trick_a[i] += 1
            elif ch == "B": by_trick_b[i] += 1
    print("  trick-by-trick team-A win rate:")
    for i in range(1, 9):
        n_a = by_trick_a[i]
        n_b = by_trick_b[i]
        total_i = n_a + n_b
        if total_i:
            print(f"    trick {i}: A={n_a:3d}/B={n_b:3d}  "
                  f"A-rate {fmt_pct_ci(n_a, total_i)}")
    print()

    # Bidder-team trick-1-win -> final-make rate (early-lead conversion).
    early_lead_makes = 0
    early_lead_total = 0
    early_loss_makes = 0
    early_loss_total = 0
    for r in v3_rows:
        b = r.get("bidder")
        tw = r.get("trickWinners", "")
        made = r.get("bidderMade", -1)
        if not b or not tw or made == -1: continue
        bid_team = "A" if b in (1, 3) else "B"
        if tw[0] == bid_team:
            early_lead_total += 1
            if made == 1: early_lead_makes += 1
        else:
            early_loss_total += 1
            if made == 1: early_loss_makes += 1
    if early_lead_total:
        print(f"  bidder team won trick 1 -> make rate "
              f"{fmt_pct_ci(early_lead_makes, early_lead_total)} "
              f"({early_lead_makes}/{early_lead_total})")
    if early_loss_total:
        print(f"  bidder team lost trick 1 -> make rate "
              f"{fmt_pct_ci(early_loss_makes, early_loss_total)} "
              f"({early_loss_makes}/{early_loss_total})")
    print()


# ---------------------------------------------------------------------
# Main.
# ---------------------------------------------------------------------
def main() -> int:
    p = argparse.ArgumentParser(description="WHEREDNGN calibration analyzer.")
    p.add_argument("paths", nargs="*",
                   help="path(s) to SavedVariables/WHEREDNGN.lua "
                        "(multiple files combine into one dataset)")
    p.add_argument("--json", metavar="OUT",
                   help="dump parsed rows as JSON")
    p.add_argument("--paste", action="store_true",
                   help="read Lua content from stdin (paste)")
    p.add_argument("--breakdown", default="",
                   help="comma-separated subset of "
                        "{bidcard,tier,escalation,r0,sweep-prog,round-dist,all}")
    args = p.parse_args()

    breakdowns: set[str] = set()
    if args.breakdown:
        for tok in args.breakdown.split(","):
            tok = tok.strip()
            if tok:
                breakdowns.add(tok)

    rows: list[dict[str, Any]] = []
    if args.paste:
        text = sys.stdin.read()
        new_rows = parse_lua_table_block(text)
        tier = parse_top_level_tier(text)
        if tier:
            for r in new_rows:
                if r.get("bidderIsBot") == 1 and not r.get("bidderTier"):
                    r["_inferredTier"] = tier
        rows.extend(new_rows)
    elif args.paths:
        for path in args.paths:
            text = Path(path).read_text(encoding="utf-8", errors="replace")
            new_rows = parse_lua_table_block(text)
            tier = parse_top_level_tier(text)
            if tier:
                for r in new_rows:
                    if r.get("bidderIsBot") == 1 and not r.get("bidderTier"):
                        r["_inferredTier"] = tier
                    r["_sourceFile"] = Path(path).name
            rows.extend(new_rows)
            print(f"# loaded {len(new_rows)} rows from {path}"
                  f"{' (tier='+tier+')' if tier else ''}",
                  file=sys.stderr)
    else:
        p.print_help()
        return 2

    if args.json:
        # Strip private `_inferredTier`/`_sourceFile` so JSON consumers
        # see only canonical fields plus the (also canonical) bidderTier
        # if it was set.
        clean = []
        for r in rows:
            d = {k: v for k, v in r.items() if not k.startswith("_")}
            clean.append(d)
        Path(args.json).write_text(json.dumps(clean, indent=2))
        print(f"wrote {len(clean)} rows to {args.json}")
    else:
        report(rows, breakdowns=breakdowns)
    return 0


if __name__ == "__main__":
    sys.exit(main())
