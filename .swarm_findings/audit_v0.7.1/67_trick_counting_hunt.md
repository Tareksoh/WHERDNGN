# 67 — Trick counting off-by-one hunt (v0.7.2)

## Verdict

**No off-by-one bugs found.** All seven sites are consistent with the
convention `#S.s.tricks` = *completed* tricks. The current trick number
is `#tricks + 1`. Code uses the convention uniformly.

## Site-by-site

### 1. `pickLead` trick-1 branch — N/A
There is no explicit `#tricks == 0` branch in `pickLead`. The function
falls through to default lead picking on trick 1 (line 1435+). No bug.

### 2. `pickLead` trick-8 branch (Bot.lua:1457-1468) — CORRECT
```lua
local trickNum = #(S.s.tricks or {}) + 1   -- 1..8
...
if trickNum == 8 or sweepPursuitEarly then
```
`trickNum == 8` ↔ `#tricks == 7` (7 completed, currently playing 8th).
`pickFollow` mirrors this at Bot.lua:2693. Correct.

### 3. v0.5.19 trick-3 sweep-pursuit (Bot.lua:1459-1466) — CORRECT
```lua
if trickNum >= 3 and trickNum <= 7 and isBidderTeam then
    ...
    sweepPursuitEarly = (mySwept == trickNum - 1)
```
At trick 3, `#tricks == 2`, `trickNum == 3`, requires `mySwept == 2`
(i.e., team won both completed tricks). Boundary check at trick 3 is
sound — earliest-fire when 2 prior tricks both won.

### 4. v0.5.0 C-5 numWorlds scaling (BotMaster.lua:781-785) — CORRECT
```lua
local numTricks = #(S.s.tricks or {})
if numTricks <= 2 then numWorlds = 100
elseif numTricks <= 5 then numWorlds = 60
else numWorlds = BASE_NUM_WORLDS end   -- 30
```
Uses *completed* count: 100 worlds for tricks 1-3 (numTricks 0-2);
60 for tricks 4-6 (3-5); 30 for tricks 7-8 (6-7). Aligns with the
comment "trick 6+ only 2-4 cards remain unseen". Correct.

### 5. `_HostStepAfterTrick` round-end gate (Net.lua:1585) — CORRECT
```lua
if #S.s.tricks >= 8 then
```
Fires when 8 completed. `>=` rather than `==` is defensive but
identical here (the array can never exceed 8 in normal flow). Correct.

### 6. Last-trick bonus (Rules.lua:602-610) — CORRECT
```lua
for i, t in ipairs(tricks) do
    ...
    if i == #tricks then
        lastTrickTeam = team
        teamPoints[team] = teamPoints[team] + K.LAST_TRICK_BONUS
    end
end
```
`#tricks` here is the local parameter `tricks` (8-entry array), and
`i == #tricks` ↔ `i == 8` ↔ last iteration. `K.LAST_TRICK_BONUS = 10`.
Correct.

### 7. Al-Kaboot detection (Rules.lua:600-651) — CORRECT
```lua
local trickCount = { A = 0, B = 0 }
for i, t in ipairs(tricks) do
    ...
    trickCount[team] = trickCount[team] + 1
end
...
if trickCount.A == 8 then sweepTeam = "A"
elseif trickCount.B == 8 then sweepTeam = "B" end
```
Counter increments per won trick; comparison `== 8` ↔ all 8 tricks won.
Correct.

## Convention consistency

All call sites uniformly treat `#S.s.tricks` as "completed tricks
count" (range 0-8) and derive current trick via `+ 1`. No site mixes
"trick number" semantics with the array length.

Wave 7 finding (`wave7_C4_findings.md:35`) and wave 5 finding
(`wave5_C1_findings.md:55`) independently confirm the convention is
sound.

## Bullets
- All 7 sites pass; convention `#tricks == completed` applied uniformly
- Trick 8 entry: `trickNum == 8` ↔ `#S.s.tricks == 7` (correct)
- Al-Kaboot: per-team counter `== 8` is exact (correct)
