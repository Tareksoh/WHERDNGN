#!/usr/bin/env python3
"""
WHEREDNGN Sun bid-rate simulator.

Loads Bot.lua's *actual* sunStrength / sunMinShape under stubs and
runs N randomized 8-card deals to measure empirically:

  - what % of hands clear sunMinShape (the structural gate)
  - sunStrength score distribution
  - Sun fire rate under current TH_SUN_BASE + jitter
  - what-if fire rates under alternative TH_SUN_BASE values
  - MARDOOFA bonus efficacy

Why this exists: post-v0.11.10 calibration nudges (TH_SUN_BASE 50->47->40,
MARDOOFA_BONUS 5->10->20, void-cap 25->18->8) have been guesses without
empirical grounding. User-observed rate is ~2/52 bot bids ~ 4%. This
tool produces the actual distribution so calibration becomes data-driven.

Usage:
    python tools/sim_sun.py                    # 10000 hands, default
    python tools/sim_sun.py --n 100000         # bigger sample
    python tools/sim_sun.py --th 35,40,45,50   # what-if threshold sweep
    python tools/sim_sun.py --advanced         # advanced-tier (with void penalty)
    python tools/sim_sun.py --csv out.csv      # dump per-hand rows

Treat output as a guide, not gospel: real games include partner-bid
context, urgency, mardoofa bonuses applied per-pair, and Hokm-rivalry
filtering. This sim isolates the R1 direct-Sun gate (sunMinShape +
sun >= thSun without margin or partner factors).
"""
from __future__ import annotations

import argparse
import os
import random
import sys
from typing import Any


SUITS = ("S", "H", "D", "C")
RANKS = ("7", "8", "9", "T", "J", "Q", "K", "A")  # 32-card Saudi deck


def deal_hand(rng: random.Random, n_cards: int = 5) -> list[str]:
    """Deal n_cards from a 32-card Saudi deck.

    Default 5 = the R1 bidding state (HostDealInitial deals 5 to each
    seat, then bidcard handed off in HostDealRest AFTER bid resolution).
    R2 bidding ALSO uses these 5 cards. Use 8 only if simulating
    post-deal-2 evaluations (which the bot doesn't actually do).
    """
    deck = [r + s for s in SUITS for r in RANKS]
    rng.shuffle(deck)
    return deck[:n_cards]


# -- Pure-Python re-implementation of Bot.lua's sunStrength + sunMinShape ---
#
# Mirrors Bot.lua exactly (line refs to v0.11.13). Kept in Python instead
# of via lupa so the tool runs without the lupa dependency. If Bot.lua's
# logic changes, update here in lock-step (and ideally cross-check against
# the Lua via a one-shot lupa diff).

def sun_min_shape(hand: list[str]) -> bool:
    """Bot.lua:864-880. Sun bid requires 2+ Aces OR 1 Ace + mardoofa."""
    has_a = {s: False for s in SUITS}
    has_t = {s: False for s in SUITS}
    ace_count = 0
    for c in hand:
        r, su = c[0], c[1]
        if r == "A":
            has_a[su] = True
            ace_count += 1
        elif r == "T":
            has_t[su] = True
    if ace_count >= 2:
        return True
    if ace_count == 1:
        for su in SUITS:
            if has_a[su] and has_t[su]:
                return True  # mardoofa
    return False


def sun_strength(hand: list[str], advanced: bool, void_cap: int) -> int:
    """Bot.lua:930-987. Face-value + length bonus + AKQ stopper - void penalty."""
    s = 0
    count = {su: 0 for su in SUITS}
    honors = {su: False for su in SUITS}
    has_a = {su: False for su in SUITS}
    has_k = {su: False for su in SUITS}
    has_q = {su: False for su in SUITS}
    for card in hand:
        r, su = card[0], card[1]
        count[su] += 1
        if r in ("A", "T", "K"):
            honors[su] = True
        if r == "A":
            has_a[su] = True
        elif r == "K":
            has_k[su] = True
        elif r == "Q":
            has_q[su] = True
        if r == "A":
            s += 11
        elif r == "T":
            s += 10
        elif r == "K":
            s += 4
        elif r == "Q":
            s += 3
        elif r == "J":
            s += 2
    # Length walk + AKQ stopper
    for su in SUITS:
        if count[su] >= 5 and (has_a[su] or has_k[su]):
            s += (count[su] - 4) * 6
        if has_a[su] and has_k[su] and has_q[su]:
            s += 8
    # Advanced void penalty (capped)
    if advanced:
        penalty = 0
        for su in SUITS:
            if count[su] < 2 or not honors[su]:
                penalty += 10
        s -= min(penalty, void_cap)
    return s


def mardoofa_count(hand: list[str]) -> int:
    """Count A+T pairs in same suit. Used for S-8 mardoofa bonus."""
    has_a = {s: False for s in SUITS}
    has_t = {s: False for s in SUITS}
    for c in hand:
        r, su = c[0], c[1]
        if r == "A":
            has_a[su] = True
        elif r == "T":
            has_t[su] = True
    return sum(1 for s in SUITS if has_a[s] and has_t[s])


def ace_count(hand: list[str]) -> int:
    return sum(1 for c in hand if c[0] == "A")


# -- Simulation -----------------------------------------------------------

def simulate(
    n: int,
    seed: int,
    advanced: bool,
    void_cap: int,
    mardoofa_bonus: int,
    mardoofa_pair_cap: int,
    three_ace_bonus: int,
    two_ace_bonus: int,
    th_bases: list[int],
    jitter: int,
    n_cards: int = 5,
) -> dict[str, Any]:
    """
    Generate `n` random hands; for each, compute the bid-decision inputs
    (sunStrength + bonuses + sunMinShape). Then for each candidate
    threshold in `th_bases`, compute the expected fire rate (averaged
    over the symmetric jitter band [th-jitter, th+jitter]).

    Returns a dict with histograms and fire rates.
    """
    rng = random.Random(seed)
    rows = []
    shape_pass = 0
    sun_with_bonus_dist: list[int] = []
    for _ in range(n):
        hand = deal_hand(rng, n_cards)
        shape = sun_min_shape(hand)
        s = sun_strength(hand, advanced=advanced, void_cap=void_cap)
        # Bot.lua adds bonuses BEFORE comparing to threshold:
        #   S-3 (3+ Aces): +three_ace_bonus
        #   S-8 (per-mardoofa pair): +mardoofa_bonus
        ac = ace_count(hand)
        mc = mardoofa_count(hand)
        s_with_bonus = s
        if ac >= 3:
            s_with_bonus += three_ace_bonus
        elif ac == 2:
            s_with_bonus += two_ace_bonus
        s_with_bonus += min(mc, mardoofa_pair_cap) * mardoofa_bonus
        rows.append({
            "hand": hand, "ace_count": ac, "mardoofa": mc,
            "shape": shape, "sun_raw": s, "sun_total": s_with_bonus,
        })
        if shape:
            shape_pass += 1
            sun_with_bonus_dist.append(s_with_bonus)

    # Fire-rate computation: jitter is uniform [-jitter, +jitter]. For
    # threshold th and hand-score x, P(x >= th + jit) = clamp((x - th + jitter)
    # / (2*jitter + 1), 0, 1) when jit is integer-uniform. We just sample.
    fire_rates = {}
    for th in th_bases:
        fires = 0
        for row in rows:
            if not row["shape"]:
                continue
            # Average over jitter band: count what fraction of jit values
            # in [-jitter, jitter] would let this hand fire. Closed form:
            x = row["sun_total"]
            band_lo = th - jitter
            band_hi = th + jitter
            band_width = band_hi - band_lo + 1  # integer-uniform
            if x >= band_hi:
                fires += 1.0
            elif x < band_lo:
                fires += 0.0
            else:
                fires += (x - band_lo + 1) / band_width
        fire_rates[th] = fires / n

    return {
        "n": n,
        "shape_pass_rate": shape_pass / n,
        "fire_rates": fire_rates,
        "score_dist_eligible": sun_with_bonus_dist,
        "rows": rows,
    }


def histogram(values: list[int], lo: int, hi: int, bin_size: int) -> dict[int, int]:
    bins: dict[int, int] = {}
    for b in range(lo, hi + 1, bin_size):
        bins[b] = 0
    for v in values:
        if v < lo:
            bins[lo] = bins.get(lo, 0) + 1
        elif v > hi:
            bins[hi] = bins.get(hi, 0) + 1
        else:
            bucket = lo + ((v - lo) // bin_size) * bin_size
            bins[bucket] = bins.get(bucket, 0) + 1
    return bins


def render_histogram(bins: dict[int, int], width: int = 40) -> None:
    if not bins:
        return
    max_count = max(bins.values()) or 1
    for lo, count in sorted(bins.items()):
        bar = "#" * int(width * count / max_count)
        print(f"  {lo:4d}+  {count:6d}  {bar}")


def main() -> int:
    p = argparse.ArgumentParser(description="Sun bid-rate simulator")
    p.add_argument("--n", type=int, default=10000,
                   help="number of random hands to deal (default 10000)")
    p.add_argument("--seed", type=int, default=42,
                   help="RNG seed (default 42)")
    p.add_argument("--advanced", action="store_true",
                   help="enable advanced-tier void penalty (else basic Sun)")
    p.add_argument("--void-cap", type=int, default=8,
                   help="K.BOT_SUN_VOID_PENALTY_CAP (default 8 = current)")
    p.add_argument("--mardoofa-bonus", type=int, default=20,
                   help="K.BOT_SUN_MARDOOFA_BONUS (default 20 = current)")
    p.add_argument("--mardoofa-pair-cap", type=int, default=2,
                   help="K.BOT_SUN_MARDOOFA_PAIR_CAP (default 2)")
    p.add_argument("--three-ace-bonus", type=int, default=15,
                   help="K.BOT_SUN_3ACE_BONUS (default 15 = current)")
    p.add_argument("--two-ace-bonus", type=int, default=0,
                   help="K.BOT_SUN_2ACE_BONUS (proposed v0.11.14, default 0=disabled)")
    p.add_argument("--th", type=str, default="34,38,40,42,46,50",
                   help="comma-separated TH_SUN_BASE values to evaluate")
    p.add_argument("--jitter", type=int, default=6,
                   help="K.BOT_BID_JITTER (default 6 = current)")
    p.add_argument("--n-cards", type=int, default=5,
                   help="cards per hand (default 5 = R1 bidding state; "
                        "8 = post-deal-2 simulation, only useful for diagnostics)")
    p.add_argument("--csv", type=str, default=None,
                   help="optional path to dump per-hand CSV rows")
    args = p.parse_args()

    th_bases = [int(x) for x in args.th.split(",") if x.strip()]
    res = simulate(
        n=args.n, seed=args.seed,
        advanced=args.advanced, void_cap=args.void_cap,
        mardoofa_bonus=args.mardoofa_bonus,
        mardoofa_pair_cap=args.mardoofa_pair_cap,
        three_ace_bonus=args.three_ace_bonus,
        two_ace_bonus=args.two_ace_bonus,
        th_bases=th_bases, jitter=args.jitter,
        n_cards=args.n_cards,
    )

    print(f"=== Sun bid-rate simulation ({res['n']} hands, seed={args.seed}) ===")
    print()
    tier = "advanced" if args.advanced else "basic"
    print(f"settings: tier={tier}  void_cap={args.void_cap}  "
          f"mardoofa_bonus={args.mardoofa_bonus}  3ace_bonus={args.three_ace_bonus}  "
          f"jitter=+/-{args.jitter}")
    print()
    print(f"sunMinShape pass rate: {res['shape_pass_rate']*100:.2f}%  "
          f"(theoretical max — hands without 2+A or 1A+mardoofa cannot bid Sun)")
    print()
    print("score distribution (eligible hands only, post-bonus):")
    bins = histogram(res["score_dist_eligible"], 10, 80, 5)
    render_histogram(bins)
    print()
    print(f"fire rate per TH_SUN_BASE (jitter +/-{args.jitter} averaged):")
    print(f"  {'th':>5}  {'rate':>7}  {'per-bot per-round':>20}  {'observed user data':>22}")
    for th in th_bases:
        rate = res["fire_rates"][th]
        marker = " <-- current" if th == 40 else ""
        print(f"  {th:>5}  {rate*100:>6.2f}%  "
              f"{rate*100:>15.2f}% per bid  ~{rate*52:>5.1f}/52{marker}")
    print()
    print("interpretation:")
    print("  - 'rate' = probability that a randomly-dealt 8-card hand fires R1 Sun")
    print("    under the given threshold + symmetric jitter band.")
    print("  - 'per-bot per-round' is the same number, framed as: in 13 rounds")
    print("    (= 52 bot bids), how many fires you'd expect.")
    print("  - User-observed: 2/52 ~ 3.85% per-bot per-round.")
    print("  - target: depends on the canonical Saudi rate. Tournament data")
    print("    suggests ~10-20% Sun rate of all CONTRACTS, which is ~2.5-5%")
    print("    per individual bot bid (since only one contract per round).")
    print("  - if our simulated rate matches user-observed (~4%), the issue")
    print("    isn't a bug — it's the structural rarity of strong Sun shapes.")
    print("    if our simulated rate is HIGHER than observed (e.g. 8%+) but")
    print("    user sees 4%, then partner-suppression / Hokm-rivalry margin /")
    print("    other R2 gates are filtering Sun bids more than expected.")
    print()

    if args.csv:
        import csv
        with open(args.csv, "w", newline="", encoding="utf-8") as f:
            w = csv.writer(f)
            w.writerow(["hand", "ace_count", "mardoofa", "shape", "sun_raw", "sun_total"])
            for r in res["rows"]:
                w.writerow([" ".join(r["hand"]), r["ace_count"], r["mardoofa"],
                            int(r["shape"]), r["sun_raw"], r["sun_total"]])
        print(f"wrote {len(res['rows'])} rows to {args.csv}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
