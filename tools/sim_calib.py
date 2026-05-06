#!/usr/bin/env python3
"""
WHEREDNGN v0.11.19+ post-ship calibration math.

Three deferred items:
  1) sunStrength side-AKQ stopper bonus (Bot.lua:1044, currently +8)
     - target: Bel rate ~20-35% per Hokm contract (canonical Saudi)
  2) R1/R2 Hokm threshold gap (K.BOT_TH_HOKM_R1_BASE=42 / R2_BASE=36)
     - empirical: R1 fires 73% of contracts, target 50/50 split
  3) PickPreempt 2-Ace bonus (PE-1 — currently 0; PickBid R1 has +15)

Re-implements Bot.lua's strength formulas in Python, sweeps each
parameter, reports fire rates. Numbers are PR-ready.
"""
from __future__ import annotations
import argparse, random, statistics
from typing import List

SUITS = ("S", "H", "D", "C")
RANKS = ("7", "8", "9", "T", "J", "Q", "K", "A")  # 32-card Saudi deck

# -----------------------------------------------------------------------------
# Bot.lua mirrors. Line refs are v0.11.19 (post-9-fix ship).
# -----------------------------------------------------------------------------
def deal(rng: random.Random, n: int) -> List[str]:
    deck = [r + s for s in SUITS for r in RANKS]
    rng.shuffle(deck)
    return deck[:n]

def sun_strength(hand, advanced=True, void_cap=8, akq_bonus=8):
    """Bot.lua:1011-1068 sunStrength. akq_bonus is the swept parameter
    (line 1044 raw value: +8 currently)."""
    s = 0
    cnt = {x: 0 for x in SUITS}
    honors = {x: False for x in SUITS}
    has = {r: {x: False for x in SUITS} for r in ("A", "K", "Q")}
    for c in hand:
        r, su = c[0], c[1]
        cnt[su] += 1
        if r in ("A", "T", "K"):
            honors[su] = True
        if r in ("A", "K", "Q"):
            has[r][su] = True
        if r == "A": s += 11
        elif r == "T": s += 10
        elif r == "K": s += 4
        elif r == "Q": s += 3
        elif r == "J": s += 2
    for su in SUITS:
        if cnt[su] >= 5 and (has["A"][su] or has["K"][su]):
            s += (cnt[su] - 4) * 6
        if has["A"][su] and has["K"][su] and has["Q"][su]:
            s += akq_bonus
    if advanced:
        pen = 0
        for su in SUITS:
            if cnt[su] < 2 or not honors[su]:
                pen += 10
        s -= min(pen, void_cap)
    return s

def suit_strength_as_trump(hand, trump, advanced=True):
    """Bot.lua:728-762."""
    s, count = 0, 0
    hasJ = has9 = hasA = False
    for c in hand:
        r, su = c[0], c[1]
        if su == trump:
            count += 1
            if r == "J": hasJ = True; s += 20
            elif r == "9": has9 = True; s += 14
            elif r == "A": hasA = True; s += 11
            elif r == "T": s += 10
            elif r == "K": s += 4
            elif r == "Q": s += 3
            elif r == "8": s += 2
            elif r == "7": s += 2
    s += max(0, count - 2) * 5
    if hasJ and has9:
        s += 18 if advanced else 10
    if advanced and not hasJ and count < 5 and not (has9 and hasA):
        s = int(s * 0.4)
    return s, count

def hokm_min_shape(hand, trump, m3lm=False):
    """Bot.lua:804-891."""
    if not trump: return False
    count, hasJ, hasSideAce, hasAnyAce = 0, False, False, False
    hasTrumpA = hasTrumpNine = hasKsuit = hasQsuit = False
    for c in hand:
        r, su = c[0], c[1]
        if su == trump:
            count += 1
            if r == "J": hasJ = True
            if r == "A": hasAnyAce = True; hasTrumpA = True
            if r == "9": hasTrumpNine = True
            if r == "K": hasKsuit = True
            if r == "Q": hasQsuit = True
        elif r == "A":
            hasSideAce = True; hasAnyAce = True
    # K+Q-of-trump escape
    if hasKsuit and hasQsuit and count >= 2: return True
    if not hasJ: return False
    if count >= 4: return True
    if count >= 3 and hasTrumpNine: return True
    if m3lm and not hasAnyAce: return False
    if count == 3 and hasSideAce: return True
    if count == 2 and hasSideAce and (hasTrumpNine or hasTrumpA): return True
    return False

def belote_suit(hand):
    hasK = {x: False for x in SUITS}
    hasQ = {x: False for x in SUITS}
    for c in hand:
        r, su = c[0], c[1]
        if r == "K": hasK[su] = True
        elif r == "Q": hasQ[su] = True
    for su in SUITS:
        if hasK[su] and hasQ[su]: return su
    return None

def side_suit_ace_bonus(hand, trump, advanced=True):
    if not advanced: return 0
    n = sum(1 for c in hand if c[0] == "A" and c[1] != trump)
    return min(n, 3) * 8

def ace_count(hand): return sum(1 for c in hand if c[0] == "A")

def void_count_excluding(hand, trump):
    cnt = {x: 0 for x in SUITS}
    for c in hand:
        cnt[c[1]] += 1
    return sum(1 for su in SUITS if su != trump and cnt[su] == 0)

def side_aces(hand, trump):
    return sum(1 for c in hand if c[0] == "A" and c[1] != trump)

# -----------------------------------------------------------------------------
# Defender Bel strength (Bot.lua:3946-3982)
# -----------------------------------------------------------------------------
def defender_bel_strength(hand, trump, akq_bonus=8):
    s = sun_strength(hand, akq_bonus=akq_bonus)
    ts, _ = suit_strength_as_trump(hand, trump)
    s += ts
    vc = void_count_excluding(hand, trump)
    sa = side_aces(hand, trump)
    s += vc * 5
    if sa >= 2:
        s += (sa - 1) * 8
    return s

# -----------------------------------------------------------------------------
# Jitter helper (uniform integer band averaging)
# -----------------------------------------------------------------------------
def jitter_fire_prob(strength, th, jit):
    """P(strength >= th + uniform[-jit..jit])."""
    band_lo = th - jit
    band_hi = th + jit
    if strength >= band_hi: return 1.0
    if strength <  band_lo: return 0.0
    return (strength - band_lo + 1) / (2 * jit + 1)

# -----------------------------------------------------------------------------
# (1) AKQ-stopper sweep — Bel fire rate as defender
# -----------------------------------------------------------------------------
def sim_bel_rate(n=20000, seed=42, akq_bonuses=(8, 12, 16, 20, 24),
                 bel_th=45, jit=10):
    """Simulate defender Bel rate against random Hokm contracts.

    For each iteration: deal 4 hands of 5 + 1 bidcard. Pick a bidder
    seat with the strongest hokmMinShape-passing trump suit (proxy
    for who buys the contract). The OTHER team has 2 defender hands;
    each independently runs PickDouble. Bel fires if EITHER fires.
    """
    rng = random.Random(seed)
    out = {b: {"any_bel": 0, "per_seat": 0} for b in akq_bonuses}
    contracts = 0
    for _ in range(n):
        deck = [r + s for s in SUITS for r in RANKS]
        rng.shuffle(deck)
        hands = [deck[i*5:(i+1)*5] for i in range(4)]
        bidcard = deck[20]
        # Pick a bidder: best Hokm score post-bidcard, requires shape.
        best_seat, best_trump, best_score = None, None, -1
        for seat in range(4):
            hyp = hands[seat] + [bidcard]
            for trump in SUITS:
                if not hokm_min_shape(hyp, trump, m3lm=False): continue
                sc, _ = suit_strength_as_trump(hyp, trump)
                sc += side_suit_ace_bonus(hyp, trump)
                if belote_suit(hyp) == trump: sc += 20
                if sc > best_score:
                    best_score, best_seat, best_trump = sc, seat, trump
        if best_seat is None: continue
        # Apply 42 R1-base threshold gate (rough check of "is this
        # bid actually accepted at our R1 threshold range").
        if best_score < 42 - 6: continue  # sub-jitter gate
        contracts += 1
        # Defenders: the 2 seats not in bidder's team. Saudi pairs
        # are (0,2) and (1,3) typically — assume seat0+seat2 vs 1+3.
        defenders = [s for s in range(4) if (s % 2) != (best_seat % 2)]
        for b in akq_bonuses:
            fired = False
            for d in defenders:
                strength = defender_bel_strength(hands[d], best_trump, akq_bonus=b)
                p = jitter_fire_prob(strength, bel_th, jit)
                # Probabilistic OR
                if rng.random() < p:
                    fired = True
                    out[b]["per_seat"] += 1
            if fired:
                out[b]["any_bel"] += 1
    return contracts, out

# -----------------------------------------------------------------------------
# (2) R1 vs R2 Hokm fire-rate sweep
# -----------------------------------------------------------------------------
def sim_r1_r2(n=20000, seed=42, r1=42, r2_options=(36, 38, 40, 42, 44),
              jit=6, advanced=True):
    """Per-seat fire rate at R1 (Hokm-on-flipped) and R2 (best-of-3-suits).

    R1 fires when bidcardSuit has hokmMinShape on hand+bidcard
    AND strength >= jitter(r1, jit).
    R2 fires when ANY non-bidcardSuit has hokmMinShape and best
    strength >= jitter(r2, jit).
    """
    rng = random.Random(seed)
    r1_fires = 0
    r2_fires = {r: 0 for r in r2_options}
    for _ in range(n):
        hand = deal(rng, 5)
        bidcard = [c for c in (r + s for s in SUITS for r in RANKS) if c not in hand]
        rng.shuffle(bidcard)
        bidcard = bidcard[0]
        bcs = bidcard[1]
        hyp = hand + [bidcard]
        # R1
        if hokm_min_shape(hyp, bcs):
            sc, _ = suit_strength_as_trump(hyp, bcs)
            sc += side_suit_ace_bonus(hyp, bcs, advanced=advanced)
            if belote_suit(hyp) == bcs: sc += 20
            p1 = jitter_fire_prob(sc, r1, jit)
            r1_fires += p1
        else:
            p1 = 0.0
        # R2 best-of-3 (excluding bidcard suit)
        for r2_th in r2_options:
            if p1 >= 1.0:
                # If R1 already fires deterministically, R2 doesn't get
                # evaluated (PickBid returns at R1). For probabilistic
                # contributions, count R2 only on the (1-p1) mass.
                pass
            best = -1
            for trump in SUITS:
                if trump == bcs: continue
                if not hokm_min_shape(hyp, trump): continue
                sc, _ = suit_strength_as_trump(hyp, trump)
                sc += side_suit_ace_bonus(hyp, trump, advanced=advanced)
                if belote_suit(hyp) == trump: sc += 20
                if sc > best: best = sc
            if best < 0:
                p2 = 0
            else:
                p2 = jitter_fire_prob(best, r2_th, jit)
            r2_fires[r2_th] += (1 - p1) * p2
    r1_rate = r1_fires / n
    r2_rates = {r: v / n for r, v in r2_fires.items()}
    return r1_rate, r2_rates

# -----------------------------------------------------------------------------
# (3) PickPreempt 2-Ace bonus
# -----------------------------------------------------------------------------
def sim_preempt(n=20000, seed=42, two_ace_bonuses=(0, 8, 12, 15, 20),
                pe_ths=(60, 65, 70, 75), jit=10):
    """PickPreempt fires when bidcard.rank=='A' (Net.lua-gated). The
    pre-empter's hand has 5 cards + receives the Ace bidcard. Bot.lua
    Bot.PickPreempt (~4251) currently does NOT mirror PickBid R1 Sun's
    +15 2-Ace bonus. We simulate the case where the pre-empter ALSO
    holds an ace (so post-bidcard hand has 2 Aces minimum).
    """
    rng = random.Random(seed)
    rows = []
    for _ in range(n):
        # Deal 5 + bidcard, force bidcard to be an Ace (the gate).
        hand = deal(rng, 5)
        # Find any Ace not in hand for bidcard (if hand has all 4
        # Aces we skip — PickPreempt wouldn't fire because no other
        # seat has the bidcard Ace anyway).
        ace_choices = [a + s for a in ("A",) for s in SUITS
                       if (a + s) not in hand]
        if not ace_choices: continue
        bidcard = rng.choice(ace_choices)
        sun_hand = hand + [bidcard]
        ac_post = ace_count(sun_hand)
        rows.append({"sun_hand": sun_hand, "ac_post": ac_post})
    # Now sweep
    out = {}
    for tab in two_ace_bonuses:
        for th in pe_ths:
            fires = 0
            two_ace_subset = 0
            for r in rows:
                strength = sun_strength(r["sun_hand"])
                if r["ac_post"] == 2:
                    strength += tab
                    two_ace_subset += 1
                # No 3-Ace bonus path needed — PickPreempt's preempt
                # signal is structurally a "weak preemptor with bid-A"
                # case; 3+ Aces is rare here.
                p = jitter_fire_prob(strength, th, jit)
                fires += p
            out[(tab, th)] = (fires / len(rows), two_ace_subset / len(rows))
    return len(rows), out

# -----------------------------------------------------------------------------
# Main report
# -----------------------------------------------------------------------------
def main():
    p = argparse.ArgumentParser(description="Calibration math for v0.11.19+")
    p.add_argument("--n", type=int, default=20000)
    p.add_argument("--seed", type=int, default=42)
    args = p.parse_args()

    print("=" * 70)
    print(f"WHEREDNGN calibration math — n={args.n} hands per sweep")
    print("=" * 70)
    print()

    # === (1) Bel rate sweep ===
    print("### Finding 1: Side-AKQ-stopper bonus (sunStrength)")
    print(f"  Hokm contract Bel rate at BOT_BEL_TH=45, jitter=±10")
    print()
    contracts, bel = sim_bel_rate(n=args.n, seed=args.seed)
    print(f"  Hokm contracts simulated: {contracts}")
    print(f"  {'akq':>5}  {'bel-rate':>10}  {'per-seat':>10}  Saudi target 20-35%")
    for b, d in sorted(bel.items()):
        rate = d["any_bel"] / contracts
        per = d["per_seat"] / (contracts * 2)
        marker = " <-- current (+8)" if b == 8 else ""
        print(f"  {b:>5}  {rate*100:>8.2f}%  {per*100:>8.2f}%{marker}")
    print()

    # Also re-run at TH=50 and 55 for sensitivity
    print(f"  Sensitivity: BOT_BEL_TH alternative values, akq=+8 vs +16:")
    for th in (40, 45, 50, 55):
        for b in (8, 16):
            contracts2, bel2 = sim_bel_rate(n=args.n//2, seed=args.seed+1,
                                             akq_bonuses=(b,), bel_th=th)
            r = bel2[b]["any_bel"] / contracts2 if contracts2 else 0
            print(f"    th={th} akq={b}: bel-rate={r*100:.2f}% (n={contracts2} contracts)")
    print()

    # === (2) R1/R2 sweep ===
    print("### Finding 2: R1/R2 Hokm threshold gap")
    print(f"  Per-seat fire rates, R1=42, jitter=±6, advanced=True")
    print()
    r1_rate, r2_rates = sim_r1_r2(n=args.n, seed=args.seed)
    print(f"  R1 fire rate: {r1_rate*100:.2f}%")
    print(f"  {'r2':>4}  {'R2-rate':>10}  {'R1+R2':>10}  {'R1-share':>10}")
    for r2_th, rate in sorted(r2_rates.items()):
        total = r1_rate + rate
        r1_share = (r1_rate / total * 100) if total > 0 else 0
        marker = " <-- current (38)" if r2_th == 38 else ""
        print(f"  {r2_th:>4}  {rate*100:>8.2f}%  {total*100:>8.2f}%  {r1_share:>8.1f}%{marker}")
    print()

    # === (3) PickPreempt sweep ===
    print("### Finding 3: PickPreempt 2-Ace bonus (PE-1)")
    print(f"  Bidcard=A forced; sweep 2-Ace bonus & threshold")
    print()
    n_eff, preempt = sim_preempt(n=args.n, seed=args.seed)
    print(f"  Effective trials: {n_eff}")
    # First show 2-Ace subset rate
    one_row = next(iter(preempt.values()))
    print(f"  2-Ace subset (post-bidcard ac==2): {one_row[1]*100:.2f}%")
    print()
    print(f"  fire-rate matrix (rows=2ace_bonus, cols=PE_TH):")
    pe_ths_sorted = sorted({k[1] for k in preempt})
    print(f"  {'2A':>4}  " + "  ".join(f"th={t:>3}" for t in pe_ths_sorted))
    for tab in sorted({k[0] for k in preempt}):
        row = [f"{preempt[(tab, t)][0]*100:>5.2f}%" for t in pe_ths_sorted]
        marker = " <-- current (0)" if tab == 0 else ""
        print(f"  {tab:>4}  " + "  ".join(row) + marker)
    print()

if __name__ == "__main__":
    main()
