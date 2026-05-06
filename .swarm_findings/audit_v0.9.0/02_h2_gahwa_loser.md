# H2 Verification — Failed-Gahwa loser keeps melds

**Verdict:** FIXED (with caveat on the test pin's strength).

## Where the fix landed
Commit `0d0b4d0` (v0.8.6). Diff touches `Net.lua` and `tests/test_state_bot.lua` only. **`Rules.lua` was NOT modified** — `R.ScoreRound` still emits `final.A/B` including the loser's own meld points via the `outcome_kind=="fail"` branch. The CHANGELOG correctly attributes the fix to `Net.lua` (`_HostStepAfterTrick`).

## Source verification (Net.lua:1662-1671)
```
if res.gahwaWonGame and res.gahwaWinner then
    local target = S.s.target or 152
    if res.gahwaWinner == "A" then
        addA = math.max(addA, target - (S.s.cumulative.A or 0))
        addB = 0  -- v0.8.6 H2: zero loser's delta
    else
        addB = math.max(addB, target - (S.s.cumulative.B or 0))
        addA = 0  -- v0.8.6 H2: zero loser's delta
    end
end
```
Both branches confirmed. Loser's `addX` is unconditionally zeroed AFTER the winner's `math.max` jump. Order is correct (loser zeroing can't accidentally clobber the winner since they're different variables).

## Test pin I.3a/I.3b (test_state_bot.lua:1554-1569)
The pin is **source-level** (regex on `Net.lua` body), NOT behavioral:
```
assertTrue(fn:find("addB%s*=%s*0") ~= nil, "I.3a (H2): ...")
assertTrue(fn:find("addA%s*=%s*0") ~= nil, "I.3b (H2): ...")
```
**Constructive:** if someone reverts the two `addB = 0`/`addA = 0` lines, the regex misses → assertion fires → test fails. **Caveat:** the regex matches `addA = 0` / `addB = 0` *anywhere* inside `_HostStepAfterTrick`, not specifically inside the gahwa branch. A future refactor that introduced an unrelated `addA = 0` elsewhere in the function could mask a regression. Current code has only one match each, so today the pin is sound.

## Edge case: failed Gahwa with neither team at target
Not reachable. The winner branch uses `addX = math.max(addX, target - cumulative)` which guarantees `cumulative + addX >= target` post-bump. Game-end branch (`if totA >= target or totB >= target`) therefore **always** fires when `gahwaWonGame=true`. Even if the loser's add were left non-zero (pre-fix), the loser couldn't "tie at target" with the winner because the winner is forced to exactly `max(naturalAdd, target-gap)`, and the loser is now zeroed. The H3 tiebreaker race that H2 fed into is closed.

## Tests
330/330 pass at HEAD (v0.9.1+).
