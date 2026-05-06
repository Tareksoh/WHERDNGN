# 22 — pickFollow ruff branches (Hokm trump play when void in led suit)

Source: `C:/CLAUDE/WHEREDNGN/Bot.lua` lines 2063-2597 (HEAD=v0.7.2);
`C:/CLAUDE/WHEREDNGN/Rules.lua` lines 100-149.

## 1. AKA-receiver suppress-ruff (H-5 + S6-6 implicit)

Lines 2091-2124 (Bot.lua). Verdict: **CORRECT, both fire.**

- **Explicit AKA** (2091-2093): `S.s.akaCalled.seat == Partner(seat)
  AND .suit == leadSuit`.
- **Implicit AKA** (2094-2111): gate requires Hokm + non-trump
  leadSuit + partnerWinning + `trick.plays[1]` exists (the LEAD,
  not a follow). Inner check: lead.seat==Partner, Rank=="A",
  Suit==leadSuit. Doc-true to S6-6 (the `lead.seat` guard
  prevents firing on partner-followed-Ace).
- **Suppress block** (2112-2124): gated `IsAdvanced + Hokm + trump
  + leadSuit + partnerWinning + (explicit OR implicit)`. Builds
  `discards` of all non-trump legal cards; if non-empty returns
  `lowestByRank`. Falls through to normal logic only when no
  non-trump exists in `legal` — and at that point R.IsLegalPlay
  has already exempted us from must-trump (curWinner==Partner →
  line 147-148 returns true), so the `legal` set must contain
  non-trump cards if we hold any. **No path ruffs when AKA-
  suppress should fire.** ✓

## 2. Partner-winning ruff-relief — heuristic vs. R.IsLegalPlay

R.IsLegalPlay:145-149: `void+Hokm+partnerWinning → return true`
(no must-trump). pickFollow does NOT have its own predicate — it
trusts whatever `legal` contains. Since `partnerWinning` is
checked at line 2065 via the same `R.CurrentTrickWinner`, and the
entire `if partnerWinning then ...` block (2181-2362) ends in
`lowestByRank(legal)` (2361), a void-in-led + partner-winning
seat will pick the cheapest legal card — which is a non-trump
discard if any exists in `legal`. **Heuristic matches predicate.** ✓

## 3. Section 11 implicit pos-4 partner-winning discard

Same flow as #2: R.IsLegalPlay returns true for non-trump when
void+partnerWinning, so non-trump cards are in `legal`. The
partnerWinning branch (2181-2362) includes smother (2198-2229),
T-1 Bargiya / T-4 Tahreeb (2257-2325), Sun re-entry (2343-2358),
and finally `lowestByRank(legal)`. None of these force a trump
play. lastSeat=true is the canonical case. **Honored.** ✓

## 4. Over-trump partner — Saudi rule

R.IsLegalPlay:117-121 (trump-led overcut) and 145-149 (off-lead
must-trump) both bypass over-trump requirement when partner wins.
pickFollow's heuristic enters the `winners` block (2364-2468)
**only when NOT partnerWinning** (gated by `if partnerWinning
then ... return ...` at 2181, which ALWAYS returns inside the
block). So pickFollow's wouldWin/winners path is unreachable when
partner is winning. **No over-trump-partner violation possible
via pickFollow.** ✓

## Summary

All four branches honor the rule contract. Implicit-AKA
correctly distinguishes lead-Ace from followed-Ace (2106 `lead.seat
== Partner`). Partner-winning short-circuits at line 2181 before
any winner-search — pickFollow cannot over-trump partner.
