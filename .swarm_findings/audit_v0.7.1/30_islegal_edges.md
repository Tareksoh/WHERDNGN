# R.IsLegalPlay edge-case audit (Rules.lua, HEAD = v0.7.2)

Source: `C:/CLAUDE/WHEREDNGN/Rules.lua` lines 89–184.

## 1. Must-follow-suit when able to follow — CORRECT
Lines 104–109. Scans hand for `Suit(c) == leadSuit`; if any present and
`cardSuit ~= leadSuit`, returns `false, "must follow suit"`. Standard
behaviour, no edge issues.

## 2. Must-trump (Hokm) when void in led suit AND not partner-winning — CORRECT
Lines 145–158. Partner-winning shortcut at 146–149 short-circuits to
`true` BEFORE the trump check. Otherwise scans for `IsTrump(c)` (152–155)
and rejects non-trump with `"must trump"` if any trump exists in hand.
Implicit Sun branch at line 143 already returned, so 158 is Hokm-only.

## 3. Must-over-trump (Hokm) when partner NOT winning and overcut available — CORRECT
Lines 160–183. Computes highest trump played, scans hand for any trump
`> highest`, requires the chosen card to clear `highest` (180). If no
overcut available, any trump is allowed (under-trump fallback, 183).

## 4. Saudi "never over-trump partner" — BOTH SITES OK, BUT ASYMMETRIC
- Lines 117–121 (trump LED, partner-winning): returns `true` UNCONDITIONALLY.
  This means a hand holding ONLY a low trump and a higher trump is NOT
  forced to follow-suit-with-the-higher one when partner is winning. Since
  must-follow-suit was already enforced at 109, the player must still play
  trump (suit-following) but is free to under-cut. Intended.
- Lines 145–149 (off-lead, partner-winning): returns `true` UNCONDITIONALLY,
  fully exempting the seat from must-trump. Player may discard any side-suit.

Both branches are FULLY EXEMPT from over-trump, AND the off-lead branch is
also exempt from must-trump entirely. Matches Saudi rule "you don't ruff
your partner". CORRECT but worth noting the off-lead exemption is broader
than the on-lead one (which is constrained by must-follow-suit, not by
this branch).

## 5. Sun: any-card-OK when void — CORRECT
Line 143: `if contract.type == K.BID_SUN then return true end` — short-
circuits before any trump logic. Void-in-Sun discards freely.

## 6. Bidder-must-name-trump invariant — VULNERABLE
`R.IsLegalPlay` reads `contract.trump` indirectly via `C.IsTrump` and
directly at line 117 (`leadSuit == contract.trump`). If `contract.type ==
K.BID_HOKM` but `contract.trump == nil`, line 117 evaluates `leadSuit ==
nil` → false (skipping the on-lead overcut block), and `C.IsTrump` likely
returns false for everything (causing `hasTrump=false` at 156 → any-card
permitted). NO explicit assert. A malformed contract silently degrades to
"Sun-like" behaviour. Caller (bidding flow) must guarantee trump is set
before any trick begins.

## 7. `S.s.akaCalled` partner-winning interaction — NOT HANDLED HERE
Grep confirms `akaCalled` is NOT referenced in Rules.lua. `R.IsLegalPlay`
makes legality decisions purely from `(card, hand, trick, contract, seat)`.
The partner-winning shortcut at 146–149 already suppresses must-ruff
whenever `R.Partner(seat) == curWinner` regardless of why partner is
winning (AKA-driven or otherwise). AKA-call semantics (e.g. partner asked
me to ruff anyway) live at the picker layer (`Bot.lua` / `BotMaster.lua`),
not here. Correct separation of concerns; no edge defect.

## Summary
Five paths verified correct; #4 noted asymmetric-but-intentional; #6 is
the only real fragility — `R.IsLegalPlay` trusts `contract.trump` to be
non-nil for Hokm and silently does the wrong thing if it isn't.
