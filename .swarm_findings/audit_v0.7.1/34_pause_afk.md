# 34 — Pause / Resume / AFK / State-Machine Audit (v0.7.2)

## Reference
- `S.ApplyPause` — `State.lua:128-130`
- `N.LocalPause` / `_OnPause` — `Net.lua:2279-2337`
- `N.MaybeRunBot` pause-gate — `Net.lua:3389-3399`
- `N.StartLocalWarn` — `Net.lua:3162-3211`
- `N.CancelTurnTimer` / `_HostTurnTimeout` / `_HostBelTimeout` — `Net.lua:3129-3344`
- Persistence — `State.lua:191-407` (snapshot replay restores `s.paused`)
- /reload re-arm — `WHEREDNGN.lua:137-238`

---

## Findings

### 1. Pause during a bot-arm window — OK
`MaybeRunBot` returns at line 3392 if `S.s.paused`. Per-branch pcall wrappers
re-check `if S.s.paused then return end` before ApplyX (`Net.lua:3429, 3497,
3548, 3599, 3653, 3778, 3832, 3898`). A pause that lands AFTER the
`C_Timer.After(BOT_DELAY_*)` is queued but BEFORE the closure runs is caught.
Resume re-pumps via `LocalPause` line 2299. **No issue.**

### 2. Pause during `StartLocalWarn("overcall")` — REAL BUG (NEW)
`K.OVERCALL_TIMEOUT_SEC = 5` (`Constants.lua:293`); `K.TURN_TIMEOUT_SEC = 60`.
`StartLocalWarn` computes `warnAt = timeout - 10 = 50` regardless of `kind`
(`Net.lua:3165-3167, 3210`). The warn timer is **never cancelled at window
close** — `_HostResolveOvercall` (`Net.lua:1169-1200`) clears state and broadcasts
`MSG_OVERCALL_RESOLVE` but no caller invokes `cancelLocalWarn`. The 50-sec
timer pings 45 s INTO the next phase (PHASE_DOUBLE / PHASE_PLAY) and pulses
the WRONG seat's UI. The earlier audit's flag is correct.

Fix: clamp warnAt to `min(50, OVERCALL_TIMEOUT_SEC - 1) = 4` for `kind=="overcall"`,
AND have `_HostResolveOvercall` + `_OnOvercallResolve` call `cancelLocalWarn()`
on window close.

### 3. Pause during SWA 5-sec timer — OK
Both `_OnSWAReq` (`Net.lua:2569-2608`) and `LocalSWA` (`Net.lua:2417-2454`)
arms self-rearm with caller-pinned hand if `S.s.paused` at fire. But neither
fires from `LocalPause` resume — they wait for the **next** scheduled tick
(another 5 s after resume). Acceptable: opponents can still Takweesh; just an
extra-quiet 5 s. Note: pinned `pinnedHand` / `encodedHand` correctly survive
the closure.

### 4. AFK during PHASE_DOUBLE (Bel window) — OK
`_HostBelTimeout` at `Net.lua:3310-3344` broadcasts `MSG_SKIP_DBL` then
`HostFinishDeal()`. Synthesizes a clean Bel-skip. Pause-guarded at line 3313.

### 5. AFK during PHASE_PLAY — OK with caveat
`_HostTurnTimeout("play")` (`Net.lua:3244-3289`) plays the lowest-trick-rank
legal card, calls `S.ApplyPlay`, fires `Bot.OnPlayObserved`, broadcasts, then
`N._HostStepPlay()`. Partial trick continues normally — host cancels its own
timer at 1404 once the auto-played seat reaches 4 plays it triggers the 2.2 s
resolver. Caveat: between AFK fire and the next `StartTurnTimer` arming
(via `ApplyTurn → SendTurn → Net.lua:148`), there's no re-arm INSIDE
`_HostTurnTimeout` itself — relies on the SendTurn path. Verified that path
runs (`_HostStepPlay` calls `S.ApplyTurn` → `N.SendTurn`). OK.

### 6. Multiple pause/resume cycles — OK
`s.paused` is a plain bool reset by `ApplyPause`. `LocalPause` is idempotent
(`Net.lua:2282`). No counters, no list state to leak. `cancelLocalWarn` is
called at every `StartLocalWarn` entry, so re-arms don't stack. **Caveat:** a
pause fired during the SWA pause-deferred re-arm (item 3) creates a chain of
nested 5 s timers — each pause-then-resume schedules another `C_Timer.After`.
Bounded by phase change but worth noting for stress tests.

### 7. /reload while paused — RISK
`packSnapshot` includes `paused` at slot 18; `ApplyResyncSnapshot`
(`State.lua:407`) and `SaveSession`/`RestoreSession` restore it. After
`PLAYER_LOGIN`, `WHEREDNGN.lua:149-209` unconditionally calls
`MaybeRunBot()`, `StartTurnTimer`, `StartBelTimer`, `StartLocalWarn` even when
`s.paused == true`. Each of those internal entries re-checks `S.s.paused` and
returns, so **functionally safe** — but the host-side `MaybeRunBot` /
`StartTurnTimer` calls at lines 153, 168, 178-187 only check `paused` inside
the callees, not at the call site. Recommendation: wrap the whole block in
`if not s.paused then ... end` for clarity. **Minor; not a bug.**

---

## Summary

One real bug (item 2: 50-sec warn for 5-sec overcall, never cancelled),
two clarity issues (3 & 7), four clean.
