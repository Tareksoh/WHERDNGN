# MaybeRunBot Dispatcher Audit (Net.lua line 3389)

## 1. Pause-gate — OK with one nuance
- L3392: top-level `if S.s.paused then return end` — correct NOP.
- L3429,3497,3548,3599,3653,3778,3832: every scheduled callback re-checks `S.s.paused` inside its pcall. Resume re-arms via the next dispatch trigger. Good.
- **Concern (B-1):** the inner C_Timer for bot-initiated SWA at L3896-3904 returns silently on `S.s.paused`. Because `S.s.swaRequest` is set at L3878 BEFORE the timer arms, a pause that crosses the SWA window leaves `swaRequest` non-nil indefinitely — and L3399 then permanently blocks ALL future bot dispatch on resume. There is no rescheduling. **Liveness bug.**

## 2. Phase routing — correct
- PHASE_OVERCALL → early-return (L3415); decisions made synchronously in `_HostBeginOvercallWindow`.
- PHASE_DOUBLE → PickDouble at defender (L3418).
- PHASE_TRIPLE → PickTriple at bidder (L3491).
- PHASE_FOUR → PickFour at defender (L3542).
- PHASE_GAHWA → PickGahwa at bidder (L3593).
- PHASE_PREEMPT → PickPreempt loop over preemptEligible (L3639).
- PHASE_DEAL1/DEAL2BID + turnKind="bid" → PickBid (L3770).
- PHASE_PLAY + turnKind="play" → PickPlay (L3821). All gated.

## 3. Tier dispatch (Saudi Master) — correct, single canonical entry
- L3928 calls `B.Bot.PickPlay(seat)` exclusively. Bot.lua:2693 internally delegates to `BotMaster.PickPlay` when active (per CLAUDE.md "Do NOT add a second explicit BotMaster.PickPlay call"). Confirmed: no duplicate path here. Recovery branch (L3978) also routes through `B.Bot` only.

## 4. pcall coverage — comprehensive, no bypass
Every callback wraps the body in `pcall`: bel L3428, triple L3496, four L3547, gahwa L3598, preempt L3652, bid L3776, play L3830. Each has a recovery branch using `applied`/`skipSent`/equivalent flags. **Issue (B-2):** the SWA inner timer body at L3896-3904 is NOT pcall-wrapped — a HostResolveSWA throw would bubble up. Same for the `else`-branch at L3908-3909 (no C_Timer). Low risk but inconsistent with rest of the dispatcher.

## 5. Bot SWA path (v0.5.1 C-2) — arms correctly, see B-1 above
Pause respected at scheduling and at fire time; entry guard (L3399) prevents re-dispatch during window. Pause-mid-window liveness gap is the only crack.

## 6. v0.7.0 Sun-overcall — handled by short-circuit
L3415 returns immediately during PHASE_OVERCALL. Bot decisions are made synchronously in `_HostBeginOvercallWindow` (Net.lua:1124-1136), which calls `_HostResolveOvercall` either via all-decided early close (L1138) or the 5s timeout (L1146). Resolver finalizes contract, then re-invokes `MaybeRunBot` (L1198) which now sees PHASE_DOUBLE/PLAY and routes correctly. Clean separation.

## 7. Re-entrancy — safe by design
MaybeRunBot is fully synchronous up to the point where it schedules a `C_Timer.After` and returns. Recursive calls (e.g., bel→Triple chain at L3447, preempt→next bot at L3681) all happen INSIDE timer callbacks AFTER the outer dispatch already returned. No re-entry on the same Lua stack frame. Each recursive call re-evaluates phase/turn, so stale dispatches are filtered. Safe.

## Severity summary
- **B-1 (high):** SWA pause-mid-window leaves `swaRequest` non-nil → permanent bot lockout on resume.
- **B-2 (low):** SWA inner timer body lacks pcall, unlike all other paths.
