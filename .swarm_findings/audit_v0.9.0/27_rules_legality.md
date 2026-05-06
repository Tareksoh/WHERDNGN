# Audit: R.IsLegalPlay vs saudi-rules.md (HEAD v0.9.0)

Source: `Rules.lua` lines 89-184; `docs/strategy/saudi-rules.md` lines 210-216.

## 1. Must-follow when able — PASS
`Rules.lua:104-109`: scans hand for any card matching `leadSuit`;
if `hasLead` and `cardSuit ~= leadSuit` returns `false, "must follow suit"`. Matches saudi-rules.md line 211 ("Must follow suit if able").

## 2. Must over-trump when trump led + can overcut + partner NOT winning — PASS
`Rules.lua:117-138`: gated by `contract.type == K.BID_HOKM and leadSuit == contract.trump`. Computes `highest` trump rank in `trick.plays` (lines 122-128), then scans hand for any trump with `TrickRank > highest` to set `canOvercut`. If `canOvercut` and the chosen card's rank is `<= highest`, returns `false, "must overcut"`. Matches saudi-rules.md line 213 ("Must over-trump if leading suit is trump and you can over-cut") — Saudi-strict, no under-trumping.

## 3. Must trump-ruff when void + Hokm + partner NOT winning — PASS
`Rules.lua:142-158`: void branch. Sun bypass at line 143 (`return true`). Hokm path checks `hasTrump` (lines 152-155); if has trump and chosen card is non-trump, returns `false, "must trump"`. Plus subsequent overcut requirement (lines 160-183) when partner is not winning. Matches saudi-rules.md line 215 ("Must trump-ruff if void in led suit (Hokm only) AND your team is not currently winning").

## 4. Over-trump-partner relief — PASS
`Rules.lua:117-121`: when trump is led and `R.Partner(seat) == curWinner`, returns `true` immediately, bypassing the overcut requirement. Implements the "never over-trump partner" Saudi-specific rule. Comment at lines 113-116 documents intent explicitly.

## 5. Partner-winning void relief — PASS
`Rules.lua:145-149`: void path computes `curWinner = R.CurrentTrickWinner(...)`; if `R.Partner(seat) == curWinner`, returns `true` (any card legal). Matches saudi-rules.md doc Q2 (line 145-149 cited verbatim) and the documented "partner is winning, you may discard freely".

## 6. AKA semantic — CONSISTENT (handled at picker layer)
`R.IsLegalPlay` is AKA-agnostic by design — it has zero references to `K.MSG_AKA`, `S.s.akaCalled`, or any AKA state. The AKA-receiver convention (saudi-rules.md line 215 caveat: "AKA receiver convention overrides this in some cases") lives in `Bot.PickAKA` / `pickFollow` per CLAUDE.md routing table. Consistency is correct: legality (`Rules.lua`) is enforced; convention (heuristic deviation) is decision-layer. AKA receiver still plays a *legal* card — the convention just narrows which legal card is preferred. No legality bypass needed.

## Verdict
All 5 mechanical rules + AKA layering match the documented Saudi convention. No discrepancies found at HEAD v0.9.0.
