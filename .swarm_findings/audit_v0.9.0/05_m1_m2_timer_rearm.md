# M1 + M2 Timer Re-arm Audit (v0.9.0, commit 9c32c50)

## Verdict: PARTIAL PASS — M1 PASS, M2 PARTIAL (edge-5 bug)

## M1 — PHASE_OVERCALL pause-blind timer (Net.lua:1188-1205)

PASS. The new `overcallTimerFn` checks `S.s.paused`; if true, it
resets `S.s.overcall.startedAt = GetTime()` and re-arms a fresh
`C_Timer.After(OVERCALL_TIMEOUT_SEC, overcallTimerFn)` (recursion-by-
re-schedule, not call). On resume the 5s clock restarts cleanly.
Phase + isHost guards present. Mirrors the SWA pattern at Net.lua:
2680-2698 (M1 changelog references ~2627; actual is :2680).

## M2 — PLAYER_LOGIN re-arm of OVERCALL + SWA (WHEREDNGN.lua:250-293)

Both windows re-armed. OVERCALL block (256-269) gated on
`phase==PHASE_OVERCALL && overcall`; resets `startedAt = GetTime()`,
arms new resolve timer with phase + paused + isHost guards. SWA block
(270-292) gated on `swaRequest.caller && phase==PHASE_PLAY`; resets
`req.ts = GetTime()`, arms HostResolveSWA with caller-match + phase +
paused guards. Pre-warn `StartLocalWarn("overcall")` also added
(243-247) for client-side ping.

## Edge 4 — startedAt/ts after re-arm

PASS for both. M1: `startedAt = GetTime()` before re-arm (Net.lua:
1196). M2: `startedAt = GetTime()` (WHEREDNGN.lua:260) and `req.ts =
GetTime()` (276). UI countdown reads from these anchors so banners
restart at full 5s, not stale-elapsed.

## Edge 5 — already-EXPIRED window before /reload

**FAIL.** Neither M2 block checks `GetTime() - startedAt >= 5` before
re-arming. If the host /reload-ed at second 6 of a 5s window that
should already have auto-resolved, the fix re-arms ANOTHER fresh 5s
window instead of immediately resolving. Effective behavior: human
gets a 10s window across the reload boundary; opponents see the SWA
banner for an extra 5s after reload. Not a soft-lock (timer DOES
fire), but spec-divergent. Recommend: pre-check elapsed and call
`_HostResolveOvercall()` / `HostResolveSWA()` synchronously when
already past deadline, only re-arm when within window.

## Edge 6 — SWA path regression check

PASS. The original SWA timer at Net.lua:2670-2708 is unchanged. The
M2 PLAYER_LOGIN re-arm is a separate Lua closure scoped to the
PLAYER_LOGIN handler — does not interact with the original
SendOvercallOpen/swaRequest creation timer. Caller-match guard
(`swaRequest.caller ~= req.caller`) prevents double-fire if a new
SWA request races the re-armed one. No regression.

## Files referenced

- C:/CLAUDE/WHEREDNGN/Net.lua:1182-1205 (M1)
- C:/CLAUDE/WHEREDNGN/Net.lua:2670-2708 (SWA pause pattern, mirror source)
- C:/CLAUDE/WHEREDNGN/WHEREDNGN.lua:250-293 (M2)
- C:/CLAUDE/WHEREDNGN/WHEREDNGN.lua:243-247 (M2 client pre-warn)
