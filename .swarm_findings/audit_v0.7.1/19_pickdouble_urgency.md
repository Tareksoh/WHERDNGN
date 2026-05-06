# 19 — PickDouble urgency stacking audit (v0.7.2 HEAD)

File: `C:/CLAUDE/WHEREDNGN/Bot.lua` — `Bot.PickDouble` at lines 2714–2811.
Helpers verified: `combinedUrgency` (lines 884–889, capped ±15) and
`Bot.IsM3lm` (lines 60–65).

## Floor cap

`th = K.BOT_BEL_TH - combinedUrgency(team, "defend")` at line 2777.
The v0.5.2 unconditional floor `if th < K.BOT_BEL_TH - 16 then th =
K.BOT_BEL_TH - 16 end` is intact at line 2801 — outside any tier gate,
applied after both the H-7 ±15 cap inside `combinedUrgency` and the
M3lm `defensiveSun` +8 raise (lines 2787–2793). Floor depth (-16)
covers the worst-case stack: combined urgency drop (-15) + jitter
floor (-10 from `BEL_JITTER`) against C-3b's max +31 strength push.
PASS.

## R.CanBel gate

Line 2725: `if R.CanBel and not R.CanBel(R.TeamOf(seat), contract,
S.s.cumulative) then return false, false end`. The Sun-only legality
predicate runs as the very first check, before any strength/urgency
math. The `R.CanBel and …` short-circuit handles older `Rules.lua`
without the predicate (no false-block on missing module). Hokm passes
through (no <100 gate) — correct per saudi-rules.md. PASS.

## Style-ledger gating

`defensiveSun` (line 2787): `if Bot.IsM3lm() and contract.type ==
K.BID_SUN and contract.bidder and Bot._partnerStyle then` — gated.
PASS for PickDouble's only style read.

For sibling pickers (verified for cross-reference consistency):
PickTriple `habitualBeler` (line 2863), PickFour `gahwaFailed` /
`triples` (line 2896) — both `Bot.IsM3lm()`-gated. PASS.

## wantOpen heuristic

Line 2809: `local wantOpen = strength >= jth + 20`. The +20 buffer is
exactly one Triple-counter's typical strength-gap, so we open Bel only
when we'd survive a ×3 challenge. Sun short-circuits earlier (line
2806: `return true, false` — open is moot, no Triple rung in Sun).
Open vs closed distinction is correct. PASS.

## C-3b formula

Lines 2749–2765 (Hokm-only branch):
- `voidCount * 5` — ✓ counts non-trump voids only (line 2758
  `if suit ~= contract.trump and suitCount[suit] == 0`).
- `(sideAces - 1) * 8` for sideAces ≥ 2 — ✓ Aces filtered to
  non-trump (line 2753 `C.Rank(c) == "A" and C.Suit(c) ~=
  contract.trump`); first Ace is the freebie, every Ace beyond
  scores 8.
Max additive: 3 voids × 5 + 3 extra Aces × 8 = +39. Floor cap of -16
plus BEL_JITTER -10 still leaves ~13-pt safety margin against the
70-base threshold. PASS.

## Verdict

All five mechanisms intact and correctly composed. No regressions
from v0.5.2 → v0.7.2. PickDouble urgency stacking is sound.
