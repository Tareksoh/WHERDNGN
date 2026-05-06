# pickFollow partner-winning audit (v0.7.2 HEAD)

File: `Bot.lua` lines 2063-2362.

## Order of evaluation (verified)

1. AKA-receiver suppress-ruff (Hokm only) — 2112-2124
2. Sun pos-4 Faranka (lastSeat + 2-card A+cover) — 2150-2179
3. **Smother / Takbeer** (point-card donate) — 2198-2229
4. **Tahreeb signals** — Bargiya (Sun A from cover ≥2), T-4 dump-larger — 2257-2325 (gated on void in led suit)
5. **v0.7.2 rule 1B** Sun must-follow second-lowest — 2343-2358
6. Default `lowestByRank(legal)` — 2361

Order Smother → Tahreeb → 1B → default is correct. Note: Tahreeb fires only when `voidInLed`, while 1B requires in-suit follow ≥ 2 — they are mutually exclusive by precondition, so apparent ordering inversion is moot.

## Findings

### Smother gate — CORRECT but not what you described
Gate is `#pointCards >= 2 OR completed >= 3 OR lastSeat` (2223). The "≥2 in-suit cards" framing is imprecise — it is "≥2 POINT cards (A/T/K/Q/J) of led suit", not generic in-suit cards. K/Q/J inclusion is the v0.5.18 Takbeer expansion. Sort-desc + [1] returns the highest point card. Correct.

### v0.7.2 rule 1B — MISSING wouldWin / can't-beat predicate (BUG CONFIRMED)
Lines 2343-2358 fire when `Sun + partnerWinning + leadSuit + #follow ≥ 2`. There is **no check** that the in-suit cards cannot beat partner. The previous-audit flag is correct: 1B was specified as "must-follow + can't-beat → second-lowest" but the implementation drops the can't-beat predicate. Consequence: if you hold (e.g.) `K + 7` of led suit and partner is winning with a Q, second-lowest returns the K — burning a re-entry/winner instead of the 7. Should add `wouldWin(c, trick, contract, seat) == false` filter on `follow` before sort.

### Single A or T of led suit, partner winning — A LEAKS THROUGH
Walk-through: hand has lone A of led, partner winning, early round, not last seat.
- Smother: `pointCards = {A}` → `#pointCards >= 2` false, `completed >= 3` false, `lastSeat` false → gate fails, no return.
- Tahreeb: `voidInLed` false (we have the A) → skip.
- 1B: `#follow == 1` → fails the `>= 2` gate.
- Falls to `lowestByRank(legal)` at 2361 — returns A as the only in-suit card (must-follow forces it). Actually correct here: legality forces A, no waste.

Single T case: identical, T forced by must-follow. Safe.

The dangerous case is **A + 7 of led suit, early, not last seat, partner winning with Q**:
- Smother: `#pointCards = 1` (A), gates all fail → no return.
- 1B fires: `#follow = 2`, second-lowest of {A,7} sorted asc = A. **Wastes the Ace.**

This is the leak. Fix: either tighten 1B to require `#follow ≥ 2` AND `none of follow wouldWin`, or relax smother to fire on lone-A when `lastSeat OR completed >= 3` (already covered) — the gap is mid-round, mid-seat, lone-A doubleton.

## Files
- `C:/CLAUDE/WHEREDNGN/Bot.lua` 2181-2362 (partner-winning block)
