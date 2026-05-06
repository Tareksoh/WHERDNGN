# Audit: AKA + SWA + Takweesh rules vs HEAD v0.9.0

Cross-references `docs/strategy/saudi-rules.md` against live code.

## 1. `Bot.PickAKA` (Bot.lua:2960-3007) — PASS

Precondition gates correctly enforced:
- L2962 contract == HOKM
- L2963 lead-only (`#trick.plays == 0`)
- L2977 partner is bot (signal-leak suppression — over-strict but defensive)
- L2981 non-trump only
- L2988 `rank ~= "A"` — explicit AKA on bare Ace suppressed (correct: that's the *implicit* signal)
- L2991 highest-unplayed-of-suit — caller really holds the boss
- L2997 per-suit dedup
- L3003 `trickNum > 1` — skip trick-1 lead

**Implicit AKA** lives on receiver side at Bot.lua:2289-2305 (H-5 receiver), which fires `implicitAKA=true` when partner LED bare Ace non-trump. Independent of any `MSG_AKA` wire. Matches v0.9.0 update.

**Verbal-required**: A silent high-card play does NOT set `S.s.akaCalled` (only `S.ApplyAKA` at State.lua:1388 does). Receiver gate at Bot.lua:2285-2287 keys on `akaCalled.seat == partner && suit == leadSuit`. Silent boss-play never matches → no relief conferred. Correctly enforced.

## 2. `Bot.PickSWA` (Bot.lua:3494-3566) — PASS

- L3499 cards-remaining ≤4 (extra `> 4` reject is conservative; 5+ goes through `R.IsValidSWA` which still validates)
- L3520 delegates legality to `R.IsValidSWA` (single source of truth)
- L3534-3563 belt-and-suspenders Hokm gate: rejects if any opponent's trump rank > caller's top trump (v0.5.21 user-reported safety net)

## 3. `R.IsValidSWA` (Rules.lua:349-467) — PASS (deterministic-or-bust)

- L363-370 V14 fix: 4th-play full-trick resolution before caller-empty short-circuit
- L384 inter-trick caller-empty success gate (v0.5.17 `#plays==0` requirement)
- L460-465 **strict universal quantifier**: ALL legal plays for opp AND partner must lead to caller win. Partner is treated adversarially (no "duck-low" cooperation). Saudi-strict deterministic-or-bust per video #35.

## 4. `Net.HostResolveTakweesh` (Net.lua:2100-2298) — PASS w/ minor note

- L2150 handTotal: 26 raw Sun / 16 raw Hokm via K.HAND_TOTAL_SUN / K.HAND_TOTAL_HOKM
- L2158-2163 multiplier ladder (Bel ×2 / Triple ×3 / Four ×4); Gahwa coerced to ×4 for forfeit math
- L2176-2177 **forfeit-not-transfer**: `mpA = meldA; mpB = meldB` — both teams keep their own melds (14th-audit fix). Caller does NOT inherit offender's melds.
- L2218 div10 = `(rawX + 5)/10` (5-rounds-UP, aligned with v0.5.21 fix)
- L2117 clears in-flight `swaRequest` (Takweesh preempts SWA)

**Note**: Code does NOT zero offender's melds — it leaves them with their owner. This is the corrected Saudi rule per "نظام التسجيل" doc (saudi-rules.md L119 says "forfeited (zeroed) but NOT transferred", but the code's "kept-with-owner" semantics matches the Codex+Gemini 14th-audit interpretation cited inline). **Doc-vs-code drift here** — saudi-rules.md should be updated to match code, OR code should zero `mpX` for the loser. Flag for resolution.

## 5. `Net.LocalAKA` (Net.lua:2303-2331) — PASS (v0.9.0 turn-aware gate)

- L2305 PHASE_PLAY only
- L2306 HOKM only
- L2317-2319 **v0.9.0 L4 fix**: refuse if `#trick.plays > 0` (must call BEFORE leading, not retroactively mid-trick)
- L2320 turn-aware: `S.s.turn == localSeat && turnKind == "play"`
- L2326 `LocalAKAcandidate()` sanity (anti-cheat)

## 6. `Bot.PickBid` R2 G-4 (Bot.lua:1314-1327) — PASS

Partner-Hokm-suppression block: reads `S.s.bids[R.Partner(seat)]`, checks prefix == `K.BID_HOKM`. If partner already bid Hokm: only Sun overcall allowed (different contract type), otherwise PASS. R1 path not gated since R2 is the second window where this matters.

## Summary

6/6 rule areas correctly wired. One **doc-vs-code discrepancy** on Takweesh meld semantics (forfeit-zero vs keep-with-owner) — code follows the corrected interpretation; saudi-rules.md L119 still cites the older "zeroed" wording.
