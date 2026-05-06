# 64 — Phase / state out-of-sync hunt (v0.7.2)

## Verdict
Not clean. Found **3 real defects** + 1 minor; the v0.7.0 PHASE_OVERCALL
plumbing in particular has soft-lock / pause-bypass holes that the
older escalation phases do not.

---

## 1. PLAY → SCORE atomicity (trick-8) — minor

`Net.lua:1584 N._HostStepAfterTrick` does, after #tricks==8:
```
local res = S.HostScoreRoundResult()
if not res then return end           -- ← exits with phase still PLAY
S.ApplyRoundResult(res)
S.ApplyRoundEnd(...)                  -- only here phase=SCORE
N.SendRound(...)
```
If `HostScoreRoundResult` returns nil (no contract / not host) the
function returns silently with `s.phase=PHASE_PLAY` and 8 tricks
already in `s.tricks` — no further callsite re-fires. Belt-and-braces
guard worth adding (force phase=SCORE on the bail).

Wire-level race: the host sends MSG_TRICK (line 1577) BEFORE applying
RoundEnd. On a remote, between MSG_TRICK and MSG_ROUND, `s.tricks=8`
and `s.phase=PHASE_PLAY` simultaneously. Hands are empty so UI play
can't trigger, but `S.IsMyTurn()` (`State.lua:516`) does NOT gate on
phase — every `LocalPlay` and `LocalSWA` style entry-point relies on
the caller phase-checking. Fragile.

## 2. Takweesh during PHASE_PLAY → bot-after-takweesh — clean
`HostResolveTakweesh` (Net.lua:2033) cancels the turn timer, sets
phase=SCORE via ApplyRoundEnd, and the in-flight 2.2s `_HostStepPlay`
timer at line 1572 phase-checks (`if S.s.phase ~= K.PHASE_PLAY then
return end`). Bot-play timer at Net.lua:3833 also phase-checks. OK.

## 3. PHASE_OVERCALL — pause bypass + /reload soft-lock (NEW v0.7.0)
Two real defects:

**(a) Pause bypass.** `_HostBeginOvercallWindow`'s 5-sec timer
(`Net.lua:1143`):
```
C_Timer.After(K.OVERCALL_TIMEOUT_SEC, function()
    if not S.s.isHost then return end
    if S.s.phase ~= K.PHASE_OVERCALL then return end
    N._HostResolveOvercall()
end)
```
**Missing `if S.s.paused then return end`.** Compare to the SWA timers
at Net.lua:2430 and 2579 which both pause-defer with re-arm. Pausing
during the overcall window does NOT stop the timer — host pauses,
5s elapses, `_HostResolveOvercall` fires, mutates the contract, and
broadcasts MSG_OVERCALL_RESOLVE / MSG_CONTRACT mid-pause.

**(b) /reload soft-lock.** `s.overcall` is NOT in
`State.lua:191 TRANSIENT_FIELDS`, so SaveSession persists it and
`s.phase=PHASE_OVERCALL`. After /reload `RestoreSession` overlays the
phase, but:
  * The `C_Timer.After` callback is gone with the old Lua state.
  * `WHEREDNGN.lua:171-236` PLAYER_LOGIN re-arm covers DOUBLE / TRIPLE /
    FOUR / GAHWA / PREEMPT — **PHASE_OVERCALL is the only window
    omitted.** No `StartLocalWarn("overcall")`, no re-arm of the 5s
    resolution timer.
  * Same omission in `LocalPause`'s resume re-arm
    (`Net.lua:2310-2325`).

Result: a host who /reloads mid-PHASE_OVERCALL stays stuck — humans
get no countdown UI, the contract never finalizes, no AFK fallback.
Soft-lock until manual unstuck.

## 4. PHASE_PREEMPT — clean
`pendingPreemptContract` is cleared on every exit:
  - Claim (`Net.lua:949`): host sets nil before `ApplyContract`
  - All-waive (`_FinalizePreempt`, line 1015): nil before
    `ApplyContract`
  - 60s AFK (`Net.lua:3672, 3720`): nil before HostFinishDeal
`State.lua:240` correctly persists `preemptEligible` /
`pendingPreemptContract` for /reload, and PLAYER_LOGIN re-arms.

## 5. RestoreSession — see (3b); otherwise clean.

---

## Suggested fixes
1. Add `s.paused` check inside the OVERCALL 5s timer (line 1143).
2. Add `K.PHASE_OVERCALL` branch to PLAYER_LOGIN re-arm
   (WHEREDNGN.lua:229-235) **and** to `LocalPause`'s resume re-arm
   (Net.lua:2310-2325) **and** schedule a fresh 5s
   `_HostResolveOvercall` timer if the host is mid-OVERCALL.
3. In `_HostStepAfterTrick` (Net.lua:1587), set `s.phase=PHASE_SCORE`
   defensively before the `return` if `HostScoreRoundResult` ever
   returns nil.
4. Optional: add a `phase==PHASE_PLAY` gate in `S.IsMyTurn` (or in
   `LocalPlay`) so a stale turn pointer between MSG_TRICK and
   MSG_ROUND on remotes can't accept a click.
