# pickLead trick-1 audit (Bot.lua HEAD = v0.7.2)

`pickLead` defined at **Bot.lua:1359** (Section 3 doc says 1289 — stale).
Trick-1 = `trickNum == 1`, so trick-8/sweep-pursuit (1381-1444) and
several memory-gated branches (≥3 prior tricks) are skipped.

## 1. Hokm bidder leads at trick 1
Branch: `isBidderTeam and isBidder` (Bot.lua:1633-1794). Trick-1 skips
B-96 ace-exhaustion (≥3 tricks), B-98 J+9-lock (memory-empty). Live paths:
- **trumpCount<4 + non-trump A in hand** (1681-1687) → cash side-suit Ace.
- **conservativeOpp via styleTrumpTempo == -1** (1705-1722) → cash
  non-trump Ace; M3lm-only and requires prior-round signal (no-op trick 1
  round 1).
- **default** → `highestByRank(trump)` (1771-1793), with H-6 reserving
  A-of-trump while non-Ace trump exists and tricks<5.

So the bidder typically leads **highest non-Ace trump** (J or 9) — the
"draw trump" pull. Doc-claimed "J of trump or A of side-suit" is only
hit when (trump<4 + side A) or styleTempo signals fire.

## 2. Sun trick-1 lead — H-7 shortest-suit
Wired at Bot.lua:1958-1979 inside `BID_SUN`. Counts non-trump suits,
picks the shortest with cards, returns `lowestByRank` from it. **Still
wired correctly.**

## 3. AKA on non-trump A at trick 1?
`Bot.PickAKA` (2606-2653) explicitly **bars trick 1**: line 2649 `if
trickNum <= 1 then return nil`. Also bars Aces (`r == "A"` line 2634) —
A leads are the *implicit* AKA, never explicit. So the bot does NOT
call AKA at trick 1. Section 6 rule 5 sender precondition (g)
"round_stage gating" is still NOT-WIRED beyond this crude trick-1 skip.

## 4. Tahreeb-lead-first / strong-card-hold (Section 3 rule 1)
**NOT-WIRED** (per 03_section3 audit). No branch withholds a side-suit
T pending end-of-round, and the SENDER-side Tahreeb signaling lives in
`pickFollow`, not `pickLead`. Receiver-side reads (1461-1548) do bias
toward partner's signaled suit, but require *prior* signals — empty at
trick 1.

## 5. Implicit AKA via bare-Ace lead — prefer or avoid?
Bidder branch (#1 above) actively **prefers** non-trump Ace leads when
trump is short or styleTempo fires; defender branches at trick 1
prioritise opp-void/singleton/longest, all *low* preferences. So the
bot occasionally leads a bare A from the bidder branch (which the
receiver-side `implicitAKA` at 2094-2111 catches), but does not
strategise around it as a deliberate signal — there is no
"prefer bare-A lead specifically to invoke implicit AKA" branch.
