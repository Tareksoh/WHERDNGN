### A-62 — seatHandSize: total = 8 hardcoded (line ~98)

Inspect seatHandSize (line ~98: `local total = 8`). This assumes all cards are dealt. Verify: in PHASE_DEAL1 (5 cards dealt), the total should be 5, not 8. Check whether BM.PickPlay is ever called during deal1 (bidding phase) or only during PHASE_PLAY when all 8 cards are dealt.

### A-66 — Biased pick: 70% chance of taking "desired" cards for the bidder

Inspect the 0.7 probability in Phase 1 biased pick (line ~221). At 70%, the bidder gets most of their "strong" cards but not always. Audit: over 30 worlds, the bidder's average strong-card assignment converges but with high variance per world. Check whether 70% or a deterministic "always take desired if available" produces better world quality.

### A-70 — rolloutValue: team diff return (us - them) vs. raw score

Inspect the return value (lines ~476-488): the function now returns team diff (my_points - opp_points). The 26th-audit fix comment explains this correctly. Audit: with Gahwa bonus of ±10000, a rollout that simulates a Gahwa win dominates all other considerations. Verify: can a non-Gahwa rollout scenario produce a diff > 10000 that would mask a Gahwa loss?

### A-72 — BM.PickPlay nil fallback: returns nil, caller falls back to Bot.PickPlay

Inspect what happens when BM.PickPlay returns nil (lines ~495-507). Callers fall back to Bot.PickPlay (M3lm / Fzloky heuristic). Verify: the BM.PickPlay nil-return conditions are `not BM.IsActive()`, `not S.s.contract`, `not hand or #hand == 0`, and `#legal == 0`. Check whether there is a case where `#legal == 1` (single legal play) returns the card directly without sampling — correct, line ~507.

### A-75 — Fzloky firstDiscard rollback: trump-ruff discards reverted

Inspect the trump-ruff rollback (lines ~262-269). If the first discard was a trump-ruff (off-suit trump), it's reverted to nil. Audit: the rollback checks `mem.firstDiscard.suit == cardSuit AND rank == C.Rank(card)`. This compares the just-stored discard against itself — it should always match. Verify: is this correctly reverting the discard set three lines earlier, or is there a timing/reference issue?
