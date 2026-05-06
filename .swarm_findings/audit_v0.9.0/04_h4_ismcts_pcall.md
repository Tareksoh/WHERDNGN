# H4 verification — ISMCTS pcall granularity

**Verdict: SHIPPED CORRECTLY.** v0.8.6 commit `0d0b4d0` moved the pcall inside the per-world loop; the regression pin in `tests/test_state_bot.lua` enforces source ordering; HEAD (v0.9.1) preserves the fix.

## 1. Diff (`git show 0d0b4d0 -- BotMaster.lua`)
Pre-fix structure (removed):
```
local ok, err = pcall(function()
    for w = 1, numWorlds do
        ...sample + score...
    end
end)
if not ok then return _restore(nil) end
```
Post-fix structure (added):
```
local rolloutErrors = 0
for w = 1, numWorlds do
    local ok, err = pcall(function()
        ...sample + score...
    end)
    if not ok then rolloutErrors = rolloutErrors + 1 end
end
if rolloutErrors == numWorlds then return _restore(nil) end
```

## 2. Current `BM.PickPlay` (BotMaster.lua:784-869)
Confirmed at lines 846-863 of `C:\CLAUDE\WHEREDNGN\BotMaster.lua`:
- Line 847: `for w = 1, numWorlds do`
- Line 848: `local ok, err = pcall(function()` — **inside** the loop.
- Line 856: `end)` closes the pcall.
- Line 857: error counter increments on failure.
- Line 861: 100%-failure fallback.

## 3. Test pin I.4 (tests/test_state_bot.lua)
The pin loads `BotMaster.lua`, isolates `BM.PickPlay`, asserts `forIdx < pcallIdx` — i.e. `for w = 1, numWorlds` MUST appear before `pcall(function()`. This is exactly the ordering required. Pin passes against current source.

## 4. Edge — 99 errors / 1 success
Returns the **1-world result** (not nil). `rolloutErrors == numWorlds` is the only fallback gate; `99 ~= 100`, so the function reaches the `argmax(scores)` block. Scores are accumulated only for successful worlds (the pcall body wraps the `scores[card] = scores[card] + rolloutValue(...)` line), so the surviving world's signal is intact, just very noisy. Aggregation is correct but statistically thin.

## 5. Outer pcall (Net.lua:3542)
`N.MaybeRunBot` still wraps the bot dispatch in its own pcall (`Net.lua` line 3542 in the bel-decision branch and similar guards elsewhere). Nested pcalls are safe in Lua 5.1 — inner pcall catches per-world errors silently; outer pcall is now redundant for ISMCTS world errors but still catches Bot.PickPlay-level failures (e.g., heuristic crashes). The `_inRollout` flag is restored via `_restore()` on every return path.

## 6. 100% failure case
Returns `_restore(nil)` (line 862), which restores `prevRollout` and returns `nil`. Caller (`Bot.PickPlay`) treats `nil` as "ISMCTS unavailable" and falls through to heuristic picker. **Not** an aggregate-of-zero result — the explicit gate prevents argmax-over-all-zeros from picking a meaningless first-legal card.
