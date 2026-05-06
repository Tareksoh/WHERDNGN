# Wave 1 — Cluster A2 Findings: ISMCTS / BotMaster Rollout Correctness

**Scope files audited:** BotMaster.lua, Bot.lua (heuristicPick callers), Rules.lua R.ScoreRound  
**Auditor:** swarm code-review agent  
**Date:** 2026-05-03

---

## Angle A-62 — seatHandSize: total = 8 hardcoded (BotMaster.lua:98)

**VERDICT: NOT-CONFIRMED**

**Evidence:** `seatHandSize` at BotMaster.lua:97-112 does hardcode `local total = 8`, and a comment on line 98-99 explicitly acknowledges this: "5 round-1 + 3 round-2 = 8 for full deal … (deal-1 only: 5 cards. but PHASE_PLAY implies all 8 dealt.)". The critical question is whether `BM.PickPlay` is ever invoked during PHASE_DEAL1 (before the 3-card second deal). Examining `BM.PickPlay` (BotMaster.lua:494-534), it returns early on `not S.s.contract` — no contract is set during PHASE_DEAL1 bidding. Since BM.PickPlay is a **play** picker only (bidding still flows through M3lm/Fzloky paths per the file header comment at line 25-27), it is unreachable until PHASE_PLAY, at which point all 8 cards have been dealt. The hardcoded 8 is therefore correct for its reachable code path. No bug exists.

**Fix recommendation:** None required. An optional defensive guard (`if S.s.phase ~= K.PHASE_PLAY then return nil end`) at the top of `BM.PickPlay` would make the invariant explicit and prevent any future caller from accidentally invoking play-picking in the wrong phase, but this is a defensive hardening suggestion, not a bug fix.

---

## Angle A-66 — Biased pick: 70% chance of taking "desired" cards for the bidder (BotMaster.lua:221)

**VERDICT: VARIANT-FOUND**

**Evidence:** The biased-pick phase at BotMaster.lua:211-231 works sequentially over seats 1-4 (the loop at line 197). The pool is populated from `unseen` before the loop begins (line 183), shuffled once (line 188), then seats consume from it in order. Because desired-card matching happens inline against the SAME `pool` slice that was just consumed by earlier seats, later seats (e.g., seat 4 when iterating 1→2→3→4) see a smaller and already-depleted pool after earlier seats have taken their shares. This means the 70% biased-take at line 221 is NOT applied uniformly across all seats — early-iterated seats (low seat numbers) see a full unfiltered pool, while late-iterated seats face residual cards after prior seats consumed theirs. This is a seat-ordering bias: in a typical game seat 1 is always sampled before seat 4 regardless of which seat is "bidder". The `desire` variable (line 213) assigns strong-card bias to `bidder` correctly, but if the bidder happens to be seat 3 or seat 4, earlier low-numbered seats have already depleted many of the strong cards from the pool before the bidder's phase-1 pick runs. Over 30 worlds this produces systematically weaker worlds for high-numbered bidders. The bug is not in the 70% probability itself — that value is reasonable — but in the sequential-depletion interaction with seat-ordering.

**Fix recommendation:** Before iterating seats in the inner assignment loop, compute two ordered passes: first iterate ONLY the bidder seat to give it priority access to the shuffled pool for its biased pick, then iterate the remaining seats in their natural order. Alternatively, pre-partition the pool into two lists (desired-for-bidder vs. remainder) before any seat iteration begins, so the bidder's 70% draw operates on the full desired-card set before any other seat depletes it. No change to the 70% probability value is needed.

---

## Angle A-70 — rolloutValue: team diff return (us - them) vs. raw score (BotMaster.lua:476-488)

**VERDICT: NOT-CONFIRMED**

**Evidence:** `rolloutValue` at BotMaster.lua:476-488 returns `diff = result.raw[myTeam] - result.raw[oppTeam]`, with a ±10000 overlay for Gahwa wins/losses. The prompt asks whether a non-Gahwa scenario can produce `diff > 10000` that would mask a Gahwa loss. Examining `R.ScoreRound` in Rules.lua:471-716, `result.raw` values are `(cardPts + meldPts) * mult + belote_bonus`. The maximum card total is `K.HAND_TOTAL_*` (one team wins all tricks). Even with the highest multiplier (×4 for Gahwa baseline), and adding the maximum realistic meld stack (Carré-of-Aces 200 in Sun + sweep), the raw for a single team stays well below 10000 game-currency units. In practice, `K.HAND_TOTAL_HOKM` and `K.HAND_TOTAL_SUN` are in the 100-200 raw-point range, multiplied by ≤4, giving at most ~800 raw per team. A diff of even `+800 - 0 = 800` is far below 10000. The Gahwa ±10000 cliff therefore reliably dominates all non-Gahwa raw diffs, as intended. No masking bug exists.

**Fix recommendation:** None required. Consider adding a comment near the 10000 constant documenting the expected raw-point ceiling so the invariant is obvious to future readers and does not require re-deriving it.

---

## Angle A-72 — BM.PickPlay nil fallback: returns nil, caller falls back to Bot.PickPlay (BotMaster.lua:495-507)

**VERDICT: NOT-CONFIRMED**

**Evidence:** The nil-return guards in `BM.PickPlay` at BotMaster.lua:495-507 are: (1) `not BM.IsActive()`, (2) `not S.s.contract`, (3) `not hand or #hand == 0`, (4) `#legal == 0`. Each is checked in order and returns nil before sampling begins. The early-exit for `#legal == 1` at line 507 returns the single card directly without sampling — this is correctly a short-circuit optimization, not a nil. The prompt notes this as "correct, line ~507" and it checks out: the code is `if #legal == 1 then return legal[1] end`. All four nil-return paths are well-formed. The caller (Net.lua is referenced but not in audit scope) is documented in the file header to fall back to Bot.PickPlay, and the conditions under which nil is returned are exhaustive and non-overlapping. No nil-return path is reachable in a normal PHASE_PLAY state with a non-empty legal set, meaning the fallback only fires in genuine edge cases where sampling would be wrong anyway.

**Fix recommendation:** None required. The nil-fallback design is sound. One minor defensive improvement: the guard `not S.s.contract` could be moved before the `hand` check (currently line 497 checks hand before contract at line 496 — reading order is already correct), but this is a style note only; in the current code contract is checked first (line 496) and hand second (line 497).

---

## Angle A-75 — Fzloky firstDiscard rollback: trump-ruff discards reverted (Bot.lua:262-269)

**VERDICT: BUG-CONFIRMED**

**Evidence:** The rollback block at Bot.lua:262-269 reads:

```lua
if not wasIllegal and leadSuit and cardSuit ~= leadSuit
   and contract and contract.type == K.BID_HOKM
   and contract.trump and cardSuit == contract.trump
   and mem.firstDiscard
   and mem.firstDiscard.suit == cardSuit
   and mem.firstDiscard.rank == C.Rank(card) then
    mem.firstDiscard = nil
end
```

This block fires only when `mem.firstDiscard.suit == cardSuit AND mem.firstDiscard.rank == C.Rank(card)`. The preceding void-inference block at Bot.lua:217-225 sets `mem.firstDiscard = { suit = cardSuit, rank = C.Rank(card) }` when `not mem.firstDiscard` (i.e., when no discard has been recorded yet). The rollback therefore compares the just-written discard against the values that were just written from the same `card` — it is structurally guaranteed to match on the very call that set it, effectively acting as a same-call self-cancel that immediately nils the discard. This is correct in intent: a trump ruff should not poison the Fzloky signal. **However**, there is a subtle ordering bug: the void inference at line 217-225 writes `mem.void[leadSuit] = true` BEFORE setting `firstDiscard`. The rollback only nils `firstDiscard`; it does NOT revert `mem.void[leadSuit]`. For a trump-ruff off a non-trump lead, voiding the seat in leadSuit is also incorrect — the seat failed to follow because they chose to ruff, NOT necessarily because they are void. Marking them void in leadSuit from a voluntary trump-ruff will corrupt the sampler's void-tracking for subsequent worlds. The rollback at line 268 is incomplete: it correctly removes the firstDiscard signal but leaves behind a spurious `mem.void[leadSuit] = true` entry set at line 218.

**Fix recommendation:** In the rollback block (Bot.lua:262-269), add `mem.void[leadSuit] = false` (or `nil`) alongside `mem.firstDiscard = nil`. This ensures that when a trump-ruff is recognized as non-preference-signal, both the firstDiscard AND the spurious void entry are retracted together. Alternatively, restructure `OnPlayObserved` so that the void-inference write at line 218 is guarded by "not a trump-ruff" before it executes, instead of relying on a post-hoc rollback. The rollback approach is acceptable if it is made complete: file Bot.lua, lines 262-269; add `mem.void[leadSuit] = false` immediately before or after `mem.firstDiscard = nil`.

---

## Summary Table

| Angle | Verdict         | File:Line(s) | Severity |
|-------|----------------|--------------|----------|
| A-62  | NOT-CONFIRMED  | BotMaster.lua:98 | — |
| A-66  | VARIANT-FOUND  | BotMaster.lua:197-245 | warning |
| A-70  | NOT-CONFIRMED  | BotMaster.lua:476-488 | — |
| A-72  | NOT-CONFIRMED  | BotMaster.lua:495-507 | — |
| A-75  | BUG-CONFIRMED  | Bot.lua:217-218, 262-269 | critical |
