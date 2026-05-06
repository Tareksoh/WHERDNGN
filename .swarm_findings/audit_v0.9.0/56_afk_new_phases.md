# 56_afk_new_phases — AFK timeout in PHASE_OVERCALL & PHASE_PREEMPT

## Q1. PHASE_OVERCALL — human AFK
**Timeout: 5s** (`K.OVERCALL_TIMEOUT_SEC`, Constants.lua:293).
On open, `_HostBeginOvercallWindow` (Net.lua:1188-1205) arms a single
`C_Timer.After(5, overcallTimerFn)`. **Host does NOT synthesize WAIVE per
seat.** On fire, it calls `_HostResolveOvercall` → `S.FinalizeOvercall` →
`R.ResolveOvercall(decisions, ...)`. Per Rules.lua:533 ("nil = WAIVE on
timeout"), missing decisions are **implicitly treated as WAIVE** by the
resolver — no per-seat MSG_OVERCALL_DECISION is sent. The host broadcasts
only MSG_OVERCALL_RESOLVE, then optionally MSG_CONTRACT.

## Q2. PHASE_PREEMPT — human AFK
**Timeout: 60s** (`K.TURN_TIMEOUT_SEC`). Net.lua:3873 arms
`StartBelTimer(seat, "preempt_pass")`. On fire, `_HostBelTimeout`
(Net.lua:3444-3456) **does** synthesize a pass: broadcasts
`MSG_PREEMPT_PASS`, calls `S.ApplyPreemptPass(seat)`, then either
`_FinalizePreempt` (last seat) or `MaybeRunBot` (next eligible). One-seat-
at-a-time chain (unlike OVERCALL's single global timer).

## Q3. Bot in PHASE_OVERCALL
Bot decisions are **NOT** routed through `MaybeRunBot` for OVERCALL —
Net.lua:3529 returns early with explicit comment ("decisions for bot
seats are recorded synchronously by `_HostBeginOvercallWindow` at
window-open time"). At window open (Net.lua:1166-1175), the host loops
seats 1-4 and for each bot calls `B.Bot.PickOvercall(seat)` →
`RecordOvercallDecision` → `SendOvercallDecision`. If all 4 are bots, it
short-circuits via `_OvercallAllDecided` → `_HostResolveOvercall` and
skips arming the 5s timer entirely.

## Q4. AFK + pause concurrent — OVERCALL
**Pause re-arms a fresh 5s window.** `overcallTimerFn` (Net.lua:1188-1204)
checks `S.s.paused` on fire: if paused, it resets `overcall.startedAt` to
GetTime() and re-arms a fresh `C_Timer.After(5, overcallTimerFn)`. After
resume, humans get a full 5s shot — **not** auto-resolved on the resume
tick. PREEMPT path is `StartBelTimer`, which guards `if S.s.paused then
return end` at arm time and `_HostBelTimeout` re-checks paused; on resume,
`LocalPause(false)` (Net.lua:2400-2403) runs `MaybeRunBot` which re-arms
`StartBelTimer` for the next eligible human.

## Q5. PHASE_OVERCALL refresh / pre-warn
**Pre-warn does NOT fire at T-10s for OVERCALL.** `StartLocalWarn`
(Net.lua:3279-3281) computes `warnAt = TURN_TIMEOUT_SEC - 10 = 50s`,
unconditional of `kind`. For OVERCALL the timeout is only **5s**, so the
50s warn would fire 45s AFTER the window already auto-WAIVE'd. The
`StartLocalWarn("overcall")` call exists (Net.lua:1079, 1209, plus
/reload re-arm at WHEREDNGN.lua:247) but is effectively a no-op timer
that never gets a chance to fire because OVERCALL resolves at T+5s.
**This is a known gap** — see audit_v0.7.1/34_pause_afk.md item 2,
flagged but only partially addressed (warnAt clamp wasn't applied).
Refresh path (WHEREDNGN.lua:243-247) re-arms StartLocalWarn but same
warnAt logic → same no-op.

## Q6. Early cancel — all seats decide
**OVERCALL: yes.** `_OnOvercallDecision` (Net.lua:1102-1104) and
`LocalOvercall` (Net.lua:1297) check `_OvercallAllDecided` after each
decision and call `_HostResolveOvercall` early. **However**, the 5s
`C_Timer.After` is **not** explicitly cancelled — it fires later but
guards via `if S.s.phase ~= K.PHASE_OVERCALL then return end` (Net.lua:1190),
so the late fire is a no-op. Note: "all 3 non-bidder seats decide" is
**not** sufficient — `_OvercallAllDecided` (Net.lua:1219-1224) requires
**all 4** seats including bidder (who can WAIVE under Ace-bid).
**PREEMPT: yes via natural drain.** `ApplyPreemptPass` removes the seat
from `preemptEligible`; once empty, `_FinalizePreempt` fires. `StartBelTimer`
calls `CancelTurnTimer` first (Net.lua:3413), so each new seat replaces
the prior timer cleanly.
