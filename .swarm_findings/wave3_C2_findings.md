# Wave 3 C2 — Trump Strength Continuation + Sun Specifics
## Auditor: code-review agent, 2026-05-03
## Codebase: v0.4.4 — C:/CLAUDE/WHEREDNGN/Bot.lua

---

### A-22 — suitCardsOutstanding calculation for trump-exhaustion detection

**VERDICT: WARNING**

**File:line:** `C:/CLAUDE/WHEREDNGN/Bot.lua:897-913`

**Evidence:**

`suitCardsOutstanding(hand, suit)` counts by walking `hand` (own cards) and then all cards in `Bot._memory[s].played` for every seat s=1..4. Memory is populated by `Bot.OnPlayObserved` (line 200-204), which is called from Net.lua "AFTER each ApplyPlay". The in-progress trick lives in `S.s.trick.plays`.

The function does NOT walk `S.s.trick.plays`. Cards that are part of the current in-progress trick (played by other seats earlier in the same trick) will already be in `mem.played` because `OnPlayObserved` is called after each individual `ApplyPlay`, not only after a trick completes. So in-progress plays from *other* seats are correctly reflected.

However, there is a self-exclusion bug: if the bot itself is deciding at position 2, 3, or 4 (i.e., the bot has not yet played this trick), the bot's own hand still contains the candidate card it may play next. The function subtracts own hand cards from 8 (line 899-901). This is correct — it means those cards are still "in the bot's hand and unplayed", so they do count toward "outstanding". The function's semantic is "how many cards in this suit have not yet been played AND are not in my hand", which is the count held by opponents and partner combined. This is the right figure for "could an opponent still hold trump?".

The one concrete gap: the function double-counts cards in `mem.played` if the same card appears in multiple seats' played maps. In practice this should not happen (a given card can only be played once), but the data structure does not enforce uniqueness globally — each seat has its own `played` table, and a card is recorded only in the playing seat's table. So there is no double-count in practice.

**Real gap:** the function is called at line 982 with `suitCardsOutstanding(hand, contract.trump)` where `hand` is the bot's current hand. At that call site, the bot is at position 2 (pos==2 branch, line 979). The trump cards played earlier in this trick (by the lead seat) are already in `Bot._memory[leadSeat].played`, so they are correctly subtracted. The bot's own trump cards are also subtracted (line 899-901). The result is the number of trump cards still held by the two opponent seats plus partner. This is the correct quantity for "is the J the only trump left in enemy hands?".

**However**, there is a subtle off-by-one in the trump-exhaustion heuristic itself (line 983): `trumpOut <= 1` is used to declare "sure stopper". If `trumpOut == 1`, that one remaining trump is held by one of the three other seats. The highest trump winner in our hand may not beat it (e.g., we hold Q of trump, but the one outstanding trump is J, which ranks higher). The heuristic should additionally verify that the winner card outranks all possible remaining trump. This is not checked.

**Recommendation:** After finding `sureStopper` as the highest trump winner, add a check that `C.TrickRank(sureStopper, contract)` is rank 8 (i.e., it IS the J of trump, the absolute top). If the only outstanding trump is exactly the J, our Q-level winner is not actually "sure". Alternatively, guard with `trumpOut == 0` (no outstanding trump at all) for full certainty, accepting that the heuristic fires less often.

---

### A-23 — highestTrump selection in bidder lead (line ~800)

**VERDICT: WARNING**

**File:line:** `C:/CLAUDE/WHEREDNGN/Bot.lua:800-801`, `Bot.lua:691-700`

**Evidence:**

`highestTrump(legal, contract)` at line 691 returns the trump with the maximum `TrickRank` value. Per `Constants.lua:50`, J of trump has rank 8 (the highest). The bidder lead at line 800 unconditionally returns the highest trump with no regard for how many trump the bot holds.

The audit prompt asks whether playing J immediately when holding J+9+A+T+K+Q of trump wastes the J-overforce on minor cards. The answer is yes. With 6 trump (J,9,A,T,K,Q), leading J on trick 1 causes opponents holding a single low trump (7 or 8) to play it — the J captures one 0-point card. A better line is to lead 9 first: 9 draws out Q/K/low trump, then J can be played later on a trick where it captures A or T of trump from an opponent forced to follow.

The current code has no trump-count check before calling `highestTrump`. The `trumpCount < 4` guard at line 793 only redirects when trump-poor; when trump-rich (>=4) it falls straight to `highestTrump` with no graduation. There is no "if we hold 5+ trump, step down to 9" path.

This is a strategic weakness rather than a crash bug. It primarily affects advanced/M3lm/Fzloky tiers where the extra heuristics are expected to be human-like. Basic mode bots are unlikely to hold 6 trump often enough to matter statistically, but when they do, the J is wasted.

**Recommendation:** In the `isBidderTeam and isBidder` branch (after the trumpCount check), if `Bot.IsAdvanced()` and `trumpCount >= 5`, prefer the 9 of trump over J as the first lead. Only fall back to J if the bot does not hold the 9. Concrete guard:

```
if Bot.IsAdvanced() and trumpCount >= 5 then
    -- prefer 9 over J when trump-rich
    for _, c in ipairs(legal) do
        if C.IsTrump(c, contract) and C.Rank(c) == "9" then return c end
    end
end
local t = highestTrump(legal, contract)
if t then return t end
```

---

### A-24 — Trump ruff conservation in pos-3 follow (lines ~1034-1044)

**VERDICT: INFO**

**File:line:** `C:/CLAUDE/WHEREDNGN/Bot.lua:1034-1045`

**Evidence:**

The pos-3 path (line 1027) normally calls `highestByRank(winners, contract)` (line 1045). The exception at lines 1034-1043 detects when ALL winners are trump and returns `lowestByRank(trumpWinners, contract)` instead.

With `K.RANK_TRUMP_HOKM` (Constants.lua:50), the trump ranks are 7=1, 8=2, Q=3, K=4, T=5, A=6, 9=7, J=8. If the bot holds only J of trump as its sole winner, `trumpWinners = {J}`, `#trumpWinners == 1 == #winners`, so `lowestByRank(trumpWinners)` returns J — the same card that `highestByRank` would return. The audit prompt's concern ("lowest trump winner could still be J if it's the only trump") is therefore a real but harmless case: the conditional fires correctly but produces no net change in card selected.

The audit prompt also asks about preferring Q/K of trump for ruffing to save J for forcing leads. This preference is NOT implemented. If `trumpWinners = {J, K}`, `lowestByRank` returns K (rank 4 < rank 8), which is correct — J is conserved. If `trumpWinners = {J}` only, J must be played because there is no alternative. So the conservation logic is already correct when the bot has multiple trump winners; it only "fails" when J is the sole remaining trump winner, at which point there is no better choice anyway.

**Actual gap:** the guard at line 1041 `#trumpWinners == #winners` requires that ALL winners are trump. If the bot has one trump winner (J) and one non-trump winner, it falls through to `highestByRank(winners)` which might return J anyway if J has the highest TrickRank. But since J of trump (rank 8) is a trump-suit card and TrickRank for non-trump tops out at A (RANK_PLAIN A=8), they could tie. The tie-break behavior of `highestByRank` is last-wins (line 672-676 uses strict `>`), so a tie between trump J and plain A would return the first encountered. This edge is benign — both cards win the trick.

**Recommendation:** The existing logic is sound for the common case. No urgent fix needed. A minor improvement would be to annotate the "J is the only trump winner" case explicitly in the comment at line 1029-1033 to clarify that the conservation is moot when J is the lone choice, avoiding future confusion.

---

### A-26 — sunStrength: distribution penalty cap lowered 25 to 18

**VERDICT: WARNING**

**File:line:** `C:/CLAUDE/WHEREDNGN/Bot.lua:389-397`

**Evidence:**

The penalty loop (lines 390-393) adds 10 per suit where `count[su] < 2 OR not honors[su]`. With 4 suits and an 8-card hand, a maximally lopsided distribution (e.g., 5-1-1-1) triggers the penalty for 3 suits (each with count==1, no honors) for a total raw penalty of 30. The cap at line 396 clamps this to 18.

The original intent per the comment (line 349-353) was "capped at the +25 range so a very lopsided hand still has *some* score floor." That cap was 25. It was subsequently softened to 18 per the inline comment "lopsided hands with a solid long suit shouldn't bleed all of their headroom."

The Saudi principle "a void suit kills your Sun" refers specifically to voids (count==0), not singletons. The current condition `count[su] < 2` penalizes singletons equally to voids, which is arguably too broad. A void is genuinely dangerous — opponents lead it and you have no stopper. A singleton of a non-honor card is only slightly worse than a doubleton. But this is a calibration question, not a structural bug.

The deeper issue: the cap is global. With 3 offending suits contributing -30 raw, the cap clips to -18. But the comment about "solid long suit" applies only when at least one suit has length. With a 5-1-1-1 distribution, the long suit (5 cards with A or K) gets the +6/card walk bonus (lines 382-385): `(5-4)*6 = +6`. So the hand scores: high-card component + 6 (walk bonus) - 18 (capped penalty). This seems reasonable — the hand has one good suit and three weak ones, and the net penalty is not catastrophic.

However, for a 2-2-2-2 distribution (perfectly balanced but no honors in some suits), a hand with no A/K/T in two suits gets -20 raw, capped to -18. This is mathematically the same as having 3 offending suits, which seems wrong: a flat hand with honors in two suits is less dangerous than a 5-1-1-1 hand with honors in one suit, yet both receive approximately the same penalty cap.

**The "per-void" question from the prompt:** the cap should arguably be per-void (count==0) rather than global. A void in one suit is a hard catastrophe; having two weak suits is softer. Per-void capping would look like: penalty += min(perSuitPenalty, 10) per suit rather than applying one global min. The current global cap means the first offending suit contributes its full 10 but the third offending suit contributes 0 (once the cap is reached). This under-penalizes a 3-void hand relative to a 1-void hand.

**Recommendation (warning severity):** Consider changing the penalty accumulation to per-suit capping: each suit contributes min(10, remaining_headroom) where headroom is tracked per offending suit, OR replace the global cap with a distinction between voids (count==0, full -10) and singletons/no-honor suits (count==1 or no honors, -5 each), with separate caps. The current global cap of 18 is materially too soft for a hand with 2+ voids.

---

### A-27 — Long-suit walk bonus: count >= 5 AND (hasA or hasK)

**VERDICT: INFO**

**File:line:** `C:/CLAUDE/WHEREDNGN/Bot.lua:382-386`

**Evidence:**

The walk bonus fires when `count[su] >= 5 and (hasA[su] or hasK[su])` (line 383). With 8 cards dealt per player in a 4-player game, holding 5+ cards in one suit means the other 3 suits share the remaining 3 cards. A 5-1-1-1 distribution is possible; 6-1-1-0 is possible. In a 32-card Saudi Baloot deck (8 cards per suit), a player holding 6 of one suit and 2 others total is rare but legal (roughly combinatorial probability ~0.5%).

The bonus formula: `(count[su] - 4) * 6`. For count=5: +6. For count=6: +12. For count=7: +18. For count=8 (entire suit): +24.

The prompt asks whether the bonus fires on realistic hands. For count=5: yes, this is plausible (5-1-1-1 or 5-2-1-0 distributions). For count=6+: extremely rare with 8-card hands but mathematically possible.

The bonus requires A or K, which is the correct guard — a 5-card suit of 9-Q-J-7-8 does not walk against prepared opponents. With A or K it can force out higher cards and establish lower cards as winners.

One potential correctness issue: the walk bonus does not check whether the A/K in the long suit has already been considered in the base score. The base score at lines 371-376 already awards 11 for A and 4 for K. The walk bonus is ADDITIONAL. For a hand like A-K-Q-x-x in spades (5 spades), the base scores A(11)+K(4)+Q(3)=18, plus walk bonus +6 = 24 for this suit alone. This is additive — a 5-card A-K-Q suit in Sun contributes 24 toward the bidding threshold of ~50. This seems intentionally generous and consistent with the design goal noted in the comment (lines 378-381: "a 6-card suit AKQxxx scored barely above 18; should be ~30+").

**One structural concern:** the walk bonus uses `hasA[su] or hasK[su]` but the honors[] map at line 367 uses `A or T or K`. A long suit with T but no A/K (e.g., T-Q-J-x-x) does not get the walk bonus. This is correct: a 10-high 5-card suit does not walk reliably — opponents' A and K both beat it.

**Recommendation:** No fix needed. The bonus is intentionally designed for rare hands and the guard is correct. Add a comment noting that count=6+ cases are combinatorially rare (~0.5%) so the large bonus values for count=6,7,8 are effectively cosmetic in practice but harmless.

---

## Summary Table

| Angle | Verdict   | Severity | File:Line              |
|-------|-----------|----------|------------------------|
| A-22  | WARNING   | warning  | Bot.lua:897-913, 982-983 |
| A-23  | WARNING   | warning  | Bot.lua:800-801, 691-700 |
| A-24  | INFO      | info     | Bot.lua:1034-1045      |
| A-26  | WARNING   | warning  | Bot.lua:389-397        |
| A-27  | INFO      | info     | Bot.lua:382-386        |

---

## Cross-cutting notes

- The `suitCardsOutstanding` function (A-22) is only called once in the codebase (line 982). It is not used for the general trump-exhaustion signal that drives leading decisions — that relies on `S.HighestUnplayedRank` (line 731). The limited call site reduces the blast radius of the off-by-one in the "sure stopper" heuristic.
- The `highestTrump` strategy (A-23) is the single most actionable fix: adding a 5+ trump count guard to prefer the 9 over J on the first lead is a one-liner change that would materially improve bidder-team trump extraction in rich-trump hands.
- The sunStrength penalty cap (A-26) has the widest correctness impact because it affects every Sun bid evaluation. The global cap under-penalizes multi-void hands and warrants a per-suit accumulation change.
