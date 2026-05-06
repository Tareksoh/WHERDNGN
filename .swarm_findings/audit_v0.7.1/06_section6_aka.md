# Section 6 Audit — AKA / signaling (v0.7.2 HEAD)

## Scope
Section 6 of `docs/strategy/decision-trees.md` vs. `Bot.PickAKA`
(Bot.lua:2606) and `pickFollow` AKA-receiver branch (Bot.lua:2063+).

## Rule-by-rule verification

| # | Rule (abbrev) | Status | Evidence |
|---|---|---|---|
| 1 | Touching-honors: partner plays T under your A → infer K with partner | **NOT-WIRED** | No `_partnerStyle.toptouchSignal` ledger key; no inference of unseen K/Q/J from partner's followed honor. Greps for "touching", "Shayeb/Bint/Walad", "toptouch" return empty. Doc itself flags `(not yet wired)`. |
| 2 | Same; partner plays K → infer Q with partner | **NOT-WIRED** | Same as #1. |
| 3 | Same; partner plays Q → infer J with partner | **NOT-WIRED** | Same. |
| 4 | Partner plays low under your winning lead → "broke in suit's highs" inverse signal | **NOT-WIRED** | No sampler-side suppress; no anti-pin logic on partner-low observations. |
| 5 | AKA partner-call window + receiver convention (H-5 baseline) | **WIRED-CORRECT** | Sender: `Bot.PickAKA` Bot.lua:2606-2653. Receiver: `pickFollow` Bot.lua:2091-2124, gated on `explicitAKA = akaCalled.seat == Partner(seat) && suit == leadSuit && partnerWinning`, returns `lowestByRank(non-trump discards)`. |
| 6 | Implicit AKA on bare-Ace lead (Hokm, non-trump) — **refinement of v0.5.1 H-5** | **WIRED-CORRECT** | Bot.lua:2094-2111: `implicitAKA` fires when `not explicitAKA && contract.type == BID_HOKM && trump && leadSuit ~= trump && partnerWinning && trick.plays[1].seat == Partner(seat) && Rank == "A" && Suit == leadSuit`. Correctly checks the LEAD play (`plays[1]`), not "any partner Ace". Combined gate at line 2114 fires `(explicitAKA or implicitAKA)`. |
| 7 | Hokm pos-4, partner winning, void in led → released from must-ruff (legality) | **WIRED-CORRECT** (legality side) | Doc cites `Rules.lua:118-121` and `:147-149`. Heuristic-side bias toward non-trump discard when released remains `(not yet wired)` — out of audit scope (Rules-side only). |
| 8 | Hokm + partner verbal AKA = released from must-ruff (H-5) | **WIRED-CORRECT** | Same code path as #5. |
| 9 | AKA must be VERBAL — silent high-card play does NOT confer relief | **WIRED-CORRECT** | `pickFollow` only suppresses ruff on `explicitAKA` (state set by MSG_AKA broadcast) or the narrowly-defined `implicitAKA` (bare-Ace LEAD only). A silent high-card follow does not satisfy either gate. |
| 10 | AKA-call sender preconditions (a)-(g) | **WIRED-PARTIAL** | (a) Hokm: line 2608. (b) non-trump: line 2627. (c) not Ace: line 2634. (d) highest unplayed: line 2637 via `S.HighestUnplayedRank`. (e) leading + 0 plays: line 2609. (f) partner-not-void-in-trump: **NOT-WIRED** (no void-read on partner). (g) round_stage / scoreUrgency gating: **NOT-WIRED** — only crude `trickNum <= 1` skip at line 2649. Bot-partner gate (line 2623) and per-suit dedup (line 2643) are extras beyond the doc list. |

## Summary
- **WIRED-CORRECT:** 5, 6, 7 (legality), 8, 9 (4/10)
- **WIRED-PARTIAL:** 10 — (a)(b)(c)(d)(e) wired; (f)(g) missing (1/10)
- **NOT-WIRED:** 1, 2, 3, 4 (touching-honors family) (4/10)

## Headline
v0.5.16 implicit-AKA refinement and v0.5.1 H-5 receiver are correct
and verbal-only. Touching-honors inference family (rules 1-4) is
entirely absent. Sender preconditions (f) partner-trump-void and
(g) round_stage gating are still gaps.
