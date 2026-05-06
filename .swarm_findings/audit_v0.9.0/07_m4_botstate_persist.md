# M4 — Bot module state persistence across /reload

**Verdict: SHIPPED, with one minor edge-case gap (no defensive type-check).**

## Diff (commit 9c32c50)

### `State.lua` `S.SaveSession` (lines 269-285)
```lua
local botModuleState = nil
if B.Bot then
    botModuleState = {
        partnerStyle = B.Bot._partnerStyle,
        memory       = B.Bot._memory,
        r1WasAllPass = B.Bot.r1WasAllPass,
    }
end
WHEREDNGNDB.session = {
    ts    = time(),
    owner = s.localName,
    state = snap,
    bot   = botModuleState,  -- new
}
```
All three module-level vars are captured. Good.

### `State.lua` `S.RestoreSession` (lines 346-358)
```lua
if sess.bot and B.Bot then
    if sess.bot.partnerStyle then B.Bot._partnerStyle = sess.bot.partnerStyle end
    if sess.bot.memory       then B.Bot._memory       = sess.bot.memory       end
    if sess.bot.r1WasAllPass ~= nil then
        B.Bot.r1WasAllPass = sess.bot.r1WasAllPass
    end
end
```
Rehydrates back to module scope. Good.

## Edge cases

### 4. Hand-edited SavedVariables — defensive typing? **PARTIAL**
The `if sess.bot.partnerStyle then` truthy guard rejects only `nil`/`false`. A
hand-edit to `partnerStyle = "string"` or `partnerStyle = 5` would land in
`Bot._partnerStyle` and crash on first index (`Bot._partnerStyle[seat]`). No
`type(... ) == "table"` check. **Minor risk** — hand-editing SV is uncommon and
self-inflicted, but the comment claims "defensive nil guards" which oversells.

### 5. Game restart (new game in same session) — RESET correctly? **YES**
`RestoreSession` line 292 enforces `(time() - sess.ts) > 3600` → snapshot
expires after 1 hour, scrubs `WHEREDNGNDB.session = nil`, returns false. A new
game session past that window starts fresh. Cross-character guard at line 298
(`sess.owner ~= s.localName`) also bails. Within the hour on the same character,
restore IS the intended behavior — matches the existing `s` snapshot semantics.

### 6. Missing `WHEREDNGNDB.session.bot` on first /reload after upgrade — clean init? **YES**
- `if sess.bot and B.Bot then` short-circuits when `sess.bot` is nil.
- Bot.lua line 171/106 declares `Bot._partnerStyle = nil` / `Bot._memory = nil` at
  module load.
- Lazy initializers at Bot.lua 252, 274, 295, 314, 380 (`if not Bot._partnerStyle
  then Bot._partnerStyle = emptyStyle() end`) handle the nil case on first read.
- `r1WasAllPass` is only consulted inside `Bot._memory` paths (line 137, 1148),
  also nil-safe via the memory guards.

Upgrade path is clean.

## Files
- `C:/CLAUDE/WHEREDNGN/State.lua` (lines 250-287, 289-360)
- `C:/CLAUDE/WHEREDNGN/Bot.lua` (lines 106, 137, 142, 171, 239, 252, 274, 295, 314, 380, 1148)
