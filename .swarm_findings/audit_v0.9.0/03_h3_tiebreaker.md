# Audit v0.9.0 — H3 Tie-at-Target Tiebreaker

**Verdict: FIXED.** Tiebreaker order at `Net.lua:1685-1699` matches the
CHANGELOG v0.8.6 H3 claim and is verified by 5 regression pins.

## 1. Production code (Net.lua, `_HostStepAfterTrick`, lines 1685-1699)

```
if totA == totB then
    if res.gahwaWonGame and res.gahwaWinner then
        winner = res.gahwaWinner
    elseif S.s.contract and S.s.contract.bidder then
        local bidderTeam = R.TeamOf(S.s.contract.bidder)
        if res.bidderMade then
            winner = bidderTeam       -- bidder won round
        else
            winner = (bidderTeam == "A") and "B" or "A"
        end
    else
        winner = "A"                  -- defensive fallback
    end
elseif totA > totB then winner = "A"
elseif totB > totA then winner = "B"
else                    winner = "A" end
```

Order is canonical: **gahwaWinner → bidderMade-conditioned → fallback**.
Pre-v0.8.6 read raw `contract.bidder` and would award failing-bidder
team at cumA == cumB ≈ 148-152.

## 2. Test pins (tests/test_state_bot.lua:1484-1528)

The pure-function `tiebreaker(totA, totB, gahwaWonGame, gahwaWinner,
bidderMade, bidder)` mirrors the production predicate exactly.

| Pin   | totA | totB | gahwaWon | gahwaWinner | bidderMade | bidder | Expect | Pins                       |
|-------|------|------|----------|-------------|------------|--------|--------|----------------------------|
| I.1a  | 152  | 152  | false    | nil         | true       | 1 (A)  | A      | bidder-made → bidder team  |
| I.1b  | 152  | 152  | false    | nil         | false      | 1 (A)  | B      | **regression bug** (was A) |
| I.1c  | 152  | 152  | false    | nil         | false      | 2 (B)  | A      | symmetric of 1b            |
| I.1d  | 152  | 152  | true     | "B"         | false      | 1 (A)  | B      | Gahwa overrides bidderMade |
| I.1e  | 155  | 152  | false    | nil         | false      | 1 (A)  | A      | non-tie path unchanged     |

5 distinct decision-matrix cells covered: bidder-made, bidder-failed
either side, Gahwa-canonical, and the non-tie short-circuit. Each
toggles a different branch input.

## 3. Edge: gahwaWonGame=false AND bidderMade=false

`I.1b/I.1c` already pin this. Falls through to the `elseif bidder`
branch and inverts the bidder team. **Correct.**

## 4. Edge: simultaneous-target-cross with no Gahwa

If both teams cross target on the same round without a Gahwa,
`gahwaWonGame` is false and the bidderMade-conditioned path runs.
Bidder-made → bidder team; bidder-failed → opp. **Correct.**

Defense-in-depth note: the v0.8.6 H2 fix at lines 1662-1671 zeroes the
loser's delta when `gahwaWonGame` is true, so a Gahwa round can no
longer create a synthetic `totA == totB` collision at target. The
gahwaWinner branch in the tiebreaker is therefore mostly redundant
post-H2 — but kept as belt-and-braces. No risk identified.

**Status:** H3 ships clean. No additional finding.
