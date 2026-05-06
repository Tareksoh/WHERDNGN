# 41_db_persistence — WHEREDNGNDB persistence corner cases (HEAD = v0.7.2)

## 1. Type-confusion defense — UNGUARDED reads abound
`ensureDB()` (WHEREDNGN.lua:69) coerces non-tables to `{}` at PLAYER_LOGIN, so post-init reads are safe **as long as ensureDB ran**. But several reads happen at module load before init OR via paths that bypass ensureDB:

- **Sound.lua:17** `WHEREDNGNDB.sound == false` — guarded by `if not WHEREDNGNDB then return true end`, but does NOT check `type == "table"`. If a corrupt save sets `WHEREDNGNDB = "x"`, `WHEREDNGNDB.sound` indexes a string and crashes Lua.
- **Bot.lua:51-78**, **BotMaster.lua:133**, **UI.lua:850/858/868/877/2696-2699/3416/3423**, **MinimapIcon.lua:24**, **Net.lua:724/3060** all use the pattern `WHEREDNGNDB and WHEREDNGNDB.foo`. Truthy non-table (`"x"` / number) bypasses the short-circuit and indexes a non-table.
- **Slash.lua:135/142/150/158/166/175/184/223** force `WHEREDNGNDB = WHEREDNGNDB or {}` then index — same flaw: a string truthy DB stays a string.
- **State.lua:74** is the *only* call site that uses the audit-blessed `type(WHEREDNGNDB) == "table"` pattern. State.lua:122/169/251/272/572/699 use the weaker `if WHEREDNGNDB then` / `if WHEREDNGNDB and …`.

**Severity:** low in practice (ensureDB runs first), but the v0.7.0 sun-overcall path (`Net.lua:1118`) and the Slash toggle paths execute later and would still segfault on a hand-corrupted save where ensureDB succeeded but a subsequent reset left the DB malformed. Worth normalizing.

## 2. Array-vs-scalar drift
`Slash target` (Slash.lua:222-224) writes `tonumber(tNum)` so the DB stays numeric. But **State.lua:75** defends against hand-edits: `tonumber(DB.target) or 152` — good. **WHEREDNGN.lua:77 / 146** do NOT: `B.State.s.target = WHEREDNGNDB.target or 152`. A hand-edited `target = "100"` propagates as a string into `s.target`, then `totA >= s.target` (Saudi rules score check) becomes `number >= string` — Lua 5.1 raises. **Bug.**

## 3. Reset preserves user prefs (line 64-90)
Confirmed correct: `S.reset()` reads target+teamNames from DB, never overwrites them. Slash.lua /reset path (line 126) also routes through `S.Reset()` → `reset()` → re-reads DB. Holds across `HostBeginLobby` (saves+restores `localName`).

## 4. Cross-version compatibility
- `ensureDB` only ADDS missing defaults; never deletes legacy keys. A v0.5.5 user keeps stale `WHEREDNGNDB.cardTheme` until the UI.lua:162-180 migrator drops it (only on theme path). `WHEREDNGNDB.preemptOnAce`, `swaRequiresPermission` default to true on first load via DEFAULTS.
- `RestoreSession` runs a v0.2.0 upgrader (line 297-303) for `redoubled`/`belrePending`/`PHASE_REDOUBLE`. Older fields outside `session.state` are NOT pruned.
- Resync wire decodes pre-v0.4.5 hosts via `f[29]` guard at line 459-462 — preserves local target. OK.

## 5. Session staleness
`SaveSession` (250-269) clears `WHEREDNGNDB.session = nil` on IDLE/LOBBY/GAME_END. `S.ApplyGameEnd` sets phase=GAME_END (line 1425), so the NEXT PLAYER_LOGOUT save clears it. **Gap:** if the addon is force-quit between game-end and the next /reload, no save fires; on next login `RestoreSession` sees stale GAME_END session — but its 3600s TTL gates it, and even if fresh, restored phase=GAME_END means `s.localSeat`-dependent UI just shows the win banner. Acceptable.

## 6. swaRequiresPermission default
DEFAULTS sets it true (line 54). Reads at Net.lua:2365-2366 use `(WHEREDNGNDB == nil) or (WHEREDNGNDB.swaRequiresPermission ~= false)` — so undefined / nil / true → permission required (safe Saudi-convention default). Only literal `false` skips the gate. OK.

## Summary of findings
- **Real bug:** WHEREDNGN.lua:77/146 don't `tonumber` the target read; hand-edit corrupts comparisons.
- **Latent risk:** every non-State.lua DB read uses `if WHEREDNGNDB and DB.foo` rather than `type(DB)=="table"`; survives ensureDB, fragile to runtime corruption.
- **OK:** reset prefs preservation, swaRequiresPermission default, session clear on GAME_END, v0.4.5 target wire-format guard.
