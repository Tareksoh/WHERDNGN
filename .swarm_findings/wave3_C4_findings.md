# Wave 3 C4 Findings — pickFollow pos==2 and pos==3 logic

Auditor: code-review agent (claude-sonnet-4-6)
Source: Bot.lua v0.4.4, Rules.lua, Cards.lua, Constants.lua

---

## A-38 — Position-3 highest winner logic vs. overcut risk

**VERDICT: NOT-CONFIRMED (intended design; exception already implemented)**

**File:line:** `Bot.lua:1027-1045`

**Evidence:**

The prompt asks whether the bot wastes a high trump (e.g., 9-of-trump = TrickRank 7) at pos==3 when a lower trump would suffice to beat seat 4. The code at line 1034-1043 handles exactly this case:

```
if #trumpWinners > 0 and #trumpWinners == #winners then
    return lowestByRank(trumpWinners, contract)
end
```

When the ONLY winners available are trumps (forced-ruff scenario), the bot returns `lowestByRank(trumpWinners)`. The `RANK_TRUMP_HOKM` table ranks `7 < 8 < Q < K < T < A < 9 < J`, so "lowest trump winner" correctly conserves the J (rank 8) and 9 (rank 7) ahead of lower trump ranks, not behind them.

The scenario asked about — holding 9-of-trump and A-of-trump with only 7-of-trump in the field — produces trumpWinners = {9T, AT}. `lowestByRank` picks the one with the smaller TrickRank, which is A (rank 6) before 9 (rank 7) per the Hokm trump ranking. Wait: let us re-examine. RANK_TRUMP_HOKM = { 7=1, 8=2, Q=3, K=4, T=5, A=6, 9=7, J=8 }. So 9-of-trump has TrickRank 7, A-of-trump has TrickRank 6. `lowestByRank` returns A (rank 6 < rank 7). That means in a forced-trump-ruff, the bot plays the Ace over the 9 when both win. This is suboptimal: Ace scores 11 points and 9 scores 14 points; the economical play is to ruff with A (11 pts) and save the 9 (14 pts) — which is precisely what the code does since it plays the lowest-ranked trump. However the "overcut risk" frame of A-38 is different: A-38 worries about opponent seat 4 over-trumping with their own high trump.

The `lowestByRank(trumpWinners)` guard correctly plays the cheapest ruff that still wins, leaving J/9 for later forcing. The general non-forced case falls through to `highestByRank(winners)` at line 1045. For non-trump winners, playing highest is correct at pos==3 (prevent seat-4 overcut of a side-suit card). No defect.

**Recommendation:** None required. Optional: add a comment at line 1041 noting that `lowestByRank` over the trump-trump scale means A (rank 6) beats 9 (rank 7) in the hand-off sort, which is correctly frugal since the 9 outscores the A in trump.

---

## A-39 — Position-4 cheapest winner (last seat, lowest of winners)

**VERDICT: WARNING — cross-suit TrickRank comparison collapses non-trump and trump onto one scale incorrectly**

**File:line:** `Bot.lua:1048-1049`, `Cards.lua:107-113`, `Constants.lua:50-51`

**Evidence:**

At pos==4 (and pos!=2 and pos!=3 in Advanced mode, or non-Advanced mode), the code falls through to:

```lua
return lowestByRank(winners, contract)   -- line 1049
```

`lowestByRank` compares via `C.TrickRank(a, contract)`. `TrickRank` returns `RANK_TRUMP_HOKM[r]` (1-8) for trump cards, and `RANK_PLAIN[r]` (1-8) for non-trump. Both scales go from 1 to 8 with different orderings:

- RANK_PLAIN: 7=1, 8=2, 9=3, J=4, Q=5, K=6, T=7, A=8
- RANK_TRUMP_HOKM: 7=1, 8=2, Q=3, K=4, T=5, A=6, 9=7, J=8

The concern in A-39 is: a hand holds 7-of-trump (TrickRank=1, 0 pts) and A-of-side-suit (TrickRank=8, 11 pts). Both would win the trick at pos==4. `lowestByRank` picks 7-of-trump (rank 1) over A-of-side-suit (rank 8). The bot throws away the trump prematurely and nets 0 points where the A would win with 11 points and no trump expenditure.

This is a **genuine correctness issue**: the two scales are numerically comparable (both 1-8) but semantically incommensurable. An A-of-side-suit has rank 8 in RANK_PLAIN; a 7-of-trump has rank 1 in RANK_TRUMP_HOKM. So `lowestByRank` correctly prefers 7-of-trump (rank 1) — but that is the wrong card: you want to win with the A of side-suit (no trump spent, 11 points on your pile) not the 7-of-trump (trump spent, 0 points on your pile).

The correct selection policy at pos==4 with a mixed winner pool should be:
1. Prefer any side-suit winner (no trump spent) over any trump winner, picking lowest by rank among side-suit winners.
2. If only trump winners remain, pick lowest trump.

**Severity: warning** (suboptimal strategy, not a crash or illegal play — but it causes measurable loss by wasting trump and gaining 0 pts when an 11-pt non-trump win was available).

**Recommendation:** In the pos==4 (or default) cheapest-winner branch, partition `winners` into non-trump first, then trump. If non-trump winners exist, return `lowestByRank(nonTrumpWinners)`. Fall back to `lowestByRank(trumpWinners)` only when no non-trump winner is available. This avoids cross-scale rank comparison entirely.

---

## A-40 — partnerWinning path: lowestByRank vs. smother logic gate

**VERDICT: WARNING — `completed >= 3` smother gate activates at trick index 4 (not trick 4), potentially smothering A at trick 3 (actual trick 4)**

**File:line:** `Bot.lua:950-956`

**Evidence:**

```lua
local completed = #(S.s.tricks or {})
if #highInSuit >= 2 or completed >= 3 or lastSeat then
```

`S.s.tricks` is the list of already-completed tricks. At the start of trick 4, `completed == 3` (tricks 1, 2, 3 are done). So the gate fires from trick 4 onwards — meaning any A or T of the lead suit (if it's the only one held) can be smothered on partner's trick starting at trick 4.

A-40 asks whether smothering the A at trick 3 is aggressive. The check actually fires starting at trick 4 (`completed >= 3` means 3 done = 4th trick in progress). At trick 3 in progress, `completed == 2`, so the gate does NOT fire unless `#highInSuit >= 2` or `lastSeat`. The A-40 concern about "smothering the A at trick 3" is therefore not triggered by `completed >= 3` alone.

However there is a subtler issue: the condition `completed >= 3` makes no distinction between A (11 pts) and T (10 pts). When `highInSuit` has exactly one element and it is an A, and `completed >= 3`, the smother fires. This is contextually aggressive in early-mid game because:

- An isolated A in a side suit is often better saved for a later trick where it can lead and collect points from the opposition.
- Smothering it on trick 4 sacrifices the ability to lead that suit later when opponents are void.

The code sorts `highInSuit` by ascending TrickRank and returns `highInSuit[1]`, which is the T before the A (RANK_PLAIN: T=7, A=8). So if both A and T are held, the T is smothered first. This is correct priority ordering. But when only one remains and `completed >= 3`, the A is sacrificed unconditionally.

**Severity: warning** (points gain is correct for the current trick, but can cause positional loss in subsequent tricks by eliminating a suit-boss that could otherwise lead to a free trick later).

**Recommendation:** Under Advanced mode, tighten the single-high-card smother gate to also check that the suit is "dead" (all other outstanding cards in the suit have been accounted for, making the A no longer a future lead weapon). `suitCardsOutstanding(hand, lead)` already exists and could serve this check: only smother the last A if `suitCardsOutstanding(hand, lead) == 0` (no opponents hold more cards in that suit to threaten it), meaning it won't ever be a winner on lead anyway.

---

## A-41 — Discard from short non-trump when can't win and not last seat

**VERDICT: NOT-CONFIRMED (under-ruff fallthrough is correct; the edge case is legal and intentional)**

**File:line:** `Bot.lua:1057-1068`

**Evidence:**

```lua
if not lastSeat and contract.type == K.BID_HOKM and contract.trump then
    local discardable = {}
    for _, c in ipairs(legal) do
        if not C.IsTrump(c, contract) then
            discardable[#discardable + 1] = c
        end
    end
    if #discardable > 0 then
        return lowestByRank(discardable, contract)
    end
end
return lowestByRank(legal, contract)
```

The scenario is: bot cannot win the trick, is not lastSeat, holds only trumps (no non-trump to discard). `#discardable == 0`, so the inner `if` does not fire. Fall-through to `lowestByRank(legal, contract)` — which is all trumps, so it plays the lowest trump.

A-41 asks whether this constitutes problematic "under-ruffing". The answer is nuanced:

1. In Saudi Hokm, if a player cannot follow lead and their partner is not winning, they are **legally required to trump** (Rules.lua line 151-157). If the bot holds only trumps and `#winners == 0` (meaning all trumps it holds are below the current trump winner), the legal set is still all trumps — and playing the lowest is the mandatory under-ruff.
2. If the bot holds trumps and one of them would win, the code would have found it in the `winners` loop above (lines 963-966) and returned earlier. The only way we reach the "can't win, not lastSeat, only trumps" path is when the bot genuinely cannot beat the current winner.
3. There is no alternative legal play — the rules force a trump. The fallthrough to `lowestByRank(legal)` is correct: playing lowest trump preserves higher trump for later.

**Recommendation:** None for correctness. An optional comment at line 1067 could document: "bot holds only trumps, none beat the current winner — under-ruff with lowest trump as required by Saudi rules."

---

## A-42 — pickFollow winner selection: wouldWin via full trick simulation

**VERDICT: NOT-CONFIRMED (leadSuit is correctly populated before wouldWin is called)**

**File:line:** `Bot.lua:712-718`, `State.lua:1070`

**Evidence:**

```lua
local function wouldWin(card, trick, contract, seat)
    local plays = {}
    for _, p in ipairs(trick.plays) do plays[#plays + 1] = p end
    plays[#plays + 1] = { seat = seat, card = card }
    local sim = { leadSuit = trick.leadSuit, plays = plays }
    return R.CurrentTrickWinner(sim, contract) == seat
end
```

A-42 asks whether `trick.leadSuit` is correctly set when seat-1 plays an off-suit trump (i.e., position-1 trumps in from the lead seat itself). The critical question is: does `trick.leadSuit` reflect the original lead suit or the trump?

In `State.ApplyPlay` (State.lua line 1070):

```lua
if #s.trick.plays == 0 then s.trick.leadSuit = C.Suit(card) end
```

`leadSuit` is set to the suit of the very first card played. If seat-1 leads with the 7-of-trump (trump as opening lead), `trick.leadSuit == trump`. The `wouldWin` sim correctly copies this value. `CurrentTrickWinner` then processes: `trumpPlayed = true` (since the lead card is trump), all subsequent trumps are eligible, non-trumps are not eligible. This is correct.

The A-42 scenario (position-1 plays an off-suit trump) is actually impossible: if seat-1 is leading the trick, any card they play becomes the leadSuit by definition (the lead card sets leadSuit). There is no "off-suit trump lead" at position-1 — the trump IS the lead suit if played first.

For positions 2-4, `trick.leadSuit` was already set by the lead card and is passed as-is into `wouldWin`'s sim. The sim mirrors the real trick's `leadSuit` exactly. `CurrentTrickWinner` uses `trick.leadSuit` only to determine eligibility in the non-trump-played case (line 51: `eligible = (s == leadSuit)`). Once any trump appears, eligibility switches to trump-only, making `leadSuit` irrelevant to winner resolution. Either way the `sim.leadSuit` is correctly inherited.

**Recommendation:** None. The `wouldWin` helper is sound. Optional: add a comment noting that `sim.leadSuit` is copied verbatim from the live trick so winner simulation stays consistent with the real evaluation.

---

## Summary Table

| Angle | VERDICT | Severity | File:line |
|-------|---------|----------|-----------|
| A-38 | NOT-CONFIRMED | — | Bot.lua:1027-1045 |
| A-39 | WARNING | warning | Bot.lua:1048-1049, Cards.lua:107-113 |
| A-40 | WARNING | warning | Bot.lua:950-956 |
| A-41 | NOT-CONFIRMED | — | Bot.lua:1057-1068 |
| A-42 | NOT-CONFIRMED | — | Bot.lua:712-718 |
