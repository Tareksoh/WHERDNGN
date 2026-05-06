# 24 - pickLead trick-8 + Al-Kaboot pursuit (Bot.lua HEAD v0.7.2)

Function: `pickLead(legal, contract, seat)` at Bot.lua:1359. Sweep-pursuit
block at lines 1381-1444.

## 1. v0.5.2 boss-scan greedy fix - INTACT

Bot.lua:1423-1435. The boss-scan collects ALL qualifying safe bosses into
a `safeBosses` table, then picks the best with `highestByFaceValue`
(C.PointValue-aware via contract). Comment at lines 1410-1418 documents
the v0.5.3 fix (greedy first-match -> face-value selection).

## 2. v0.5.2 trumpExhausted check - INTACT

Bot.lua:1420-1422:
```
local trumpExhausted = (contract.type == K.BID_HOKM
                        and contract.trump
                        and S.HighestUnplayedRank(contract.trump) == nil)
```
`isSafe = (contract.type ~= K.BID_HOKM) or C.IsTrump(c, contract) or
trumpExhausted` (1428-1430). Non-trump bosses count as safe in Hokm when
no trump remains anywhere. Logic is correct.

## 3. Trick-8 partner-winning sweep-pursuit (myTeamSweepCount==7) - INTACT

Bot.lua:1397-1403, 1440-1442. After boss-lead miss, `sweepPursuit`
(`myTeamSweepCount == 7`) returns `highestByRank(legal, contract)` for
max over-trump resistance; otherwise `highestByFaceValue`. Note
`myTeamSweepCount` is recomputed inside the if-block independently of
the early gate's `mySwept`.

## 4. v0.5.19 trick-3+ Kaboot pursuit - PARTIAL

Bot.lua:1381-1391. New inline boolean `sweepPursuitEarly` (no new
`S.s.*` state flag — recomputed per call):
```
if trickNum >= 3 and trickNum <= 7 and isBidderTeam then
    local mySwept = 0
    for _, t in ipairs(S.s.tricks or {}) do
        if R.TeamOf(t.winner) == myTeam then mySwept = mySwept + 1 end
    end
    sweepPursuitEarly = (mySwept == trickNum - 1)
end
```
Then `if trickNum == 8 or sweepPursuitEarly then` enters the same
boss-scan/highestByFaceValue branch.

GAP vs prompt spec: the prompt asks for "bidder team won 1+2 cleanly +
hand-shape feasible". Code checks team + clean-prior count only — there
is NO hand-shape feasibility gate (no trump-strength or boss-count
filter before entering pursuit). `myTeamSweepCount==7` branch is
trick-8-only so the early trigger uses face-value, not the rank-tiebreak
path. Acceptable simplification, but note divergence.

## 5. AKA-aware lead - NOT WIRED IN pickLead

`pickLead` itself does NOT prefer AKA-eligible cards during pursuit.
The boss-scan returns highest-face-value, which often coincides with
an Ace, but no explicit AKA bias. AKA announcement is computed
post-hoc by `Bot.PickAKA(seat, leadCard)` at Bot.lua:2606 from the
already-chosen card, gated on rank!=A (line 2634, bare-Ace = implicit
AKA), suit==boss, trick>1, bot-partner only. Implicit AKA on bare-Ace
lead is recognised receiver-side (Bot.lua:2094-2110) but pickLead does
not actively prefer leading a bare Ace to trigger it.
