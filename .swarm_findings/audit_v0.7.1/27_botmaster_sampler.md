# Audit: BotMaster.sampleConsistentDeal (v0.7.2 HEAD)

File: `C:/CLAUDE/WHEREDNGN/BotMaster.lua` lines 198-495.

## 1. Role-weighted desire maps (H-1/H-2/H-3) — CORRECT

Lines 358-367 dispatch desire by role:
- bidder -> `strong` (getStrongCards: J/9/A/T/K/Q trump + side Aces, or Sun A/T/K).
- defender (opp team AND not bidder) -> `defenderDesire` (non-trump A=8, K=4, suit-flag for length fallback weight 20).
- bidderPartner (line 209: `R.Partner(bidder)`, distinct from caller's partner) -> `partnerDesire` (trump suit-flag + side A=5 in Hokm; A=8/K=4 in Sun).
- everyone else (caller's own seat handled separately at 338-339) -> `{}`.

Role logic is sound: `isDefender` uses absolute team comparison (R.TeamOf(s) ~= R.TeamOf(bidder)), so both defender seats share the bias regardless of caller. `bidderPartner` is captured BEFORE the loop (line 209), so it's the bidder's partner — not a caller-relative confusion.

## 2. v0.5.22 pigeonhole pin (Section 11 rule 3) — CORRECT

Lines 285-318. Builds `trumpEligible` from non-self seats lacking observed trump-void; if exactly one remains, pins ALL unseen-trump cards (suit==trump) to that seat via `meldPins`. Excludes pinCard and already-pinned. This catches K/Q/T/A/8/7 of trump that H-1's J/9-only pin missed. Hard constraint, applied before pool build (line 322 filters `meldPins`).

## 3. v0.6.1 leadCount bias — CORRECT but COARSE

Lines 411-418. For opponent seats (sIsOpponent && not likelyKawesh), iterates `style.leadCount` and sets `desire[suit] = 1` when count >= 3. The `1` is a *flag*, not a numeric weight — it triggers the suit-fallback path at line 423: `desire[C.Suit(c)] and 20`. So magnitude is 20 per matching card, same as defender suit-flag fallback. Guarded against overwriting an existing `desire[suit]` (Fzloky signal). Threshold 3 reasonable. Note: `1` is truthy in Lua, indistinguishable from `true` — works, but slightly fragile if anyone later reads desire numerically.

## 4. Sun-bidder partner concentration — CORRECT

`getPartnerCards` Sun branch (lines 121-127): A=8, K=4 across all 4 suits. This biases highs onto the partner, matching the "both partners can carry trick-pulling weight" Saudi convention. Length emerges from random fill — no suit-flag set in Sun, which is right because we don't know which suit is long.

## 5. Random fill on weight starvation — CORRECT

Two-phase fill per seat (lines 420-447). Phase 1: weighted pick at pickProb (0.7 / 0.5 if A-hoarder); skipped cards land in `remainingInPool`. Phase 2 (lines 439-447): unconditional fill from leftover pool subject to void/used. If still under-target after phase 2, sets `ok = false` and the outer attempt loop retries (up to 15). Falls through to uniform fallback (lines 467-494) if all attempts fail. Fallback now respects meldPins (H-6 regression fix) but still ignores voids — acceptable as a last resort.

## Bugs / risks found

None blocking. Minor:
- Line 311 `local pinSeat` shadows the outer `pinSeat` (line 219). Both used correctly within their scopes, but the shadowing is easy to misread.
- Line 415 sets `desire[suit] = 1`. The pool loop at 423 reads `desire[c]` first (card-keyed) then falls back to `desire[C.Suit(c)] and 20`. So `1` and `true` produce identical behavior. Consistency with defenderDesire (uses `true`) would be cleaner.
