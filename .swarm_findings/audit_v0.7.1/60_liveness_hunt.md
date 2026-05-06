# 60 — Liveness / Unbounded-Loop Hunt (v0.7.2)

**Verdict: PASS** — no infinite loops or liveness deadlocks found in the targets. All identified liveness paths are bounded by phase guards, idempotence flags, AFK timers, or hard iteration caps.

---

## Targets reviewed

### 1. `BotMaster.sampleConsistentDeal` — bounded
- `BotMaster.lua:320` — `local maxAttempts = 15` cap on the primary biased-sampling loop.
- Inside each attempt: per-seat single-pass over `pool` (`for _, c in ipairs(pool) do …`) and a single-pass `leftovers` reassign — no nested unbounded loops.
- Fallback (line 480) is a single-pass uniform deal with `idx` increment over `pool` — guaranteed termination.
- Outer ISMCTS caller (`BotMaster.lua:795-805`) wraps in `pcall` + uses fixed `numWorlds ∈ {30, 60, 100}`. The earlier B-fix already guarantees `_inRollout` is restored even on error.

### 2. AFK / pause / SWA timer interactions — bounded
- `N.StartTurnTimer` (Net.lua:3213) cancels any prior timer before arming. No stacking.
- `LocalPause(true)` cancels turn timer; resume re-arms exactly once and re-dispatches `_HostStepPlay` if a 4-card trick froze in flight (Net.lua:2294-2297). Pause-during-2.2s-trick path is correctly resumed.
- SWA timer self-reschedules on pause (Net.lua:2569-2607 and 2424-2453) — could in principle stack across rapid pause/unpause, but every callback re-checks `swaRequest.caller == seat AND phase == PHASE_PLAY AND not paused`, so excess timers are no-ops. Worst case: extra benign C_Timer callbacks; not a liveness bug.
- `_HostTurnTimeout` defers when `swaRequest` is in flight (Net.lua:3236) — and `_OnSWAResp`/`HostResolveSWA`/`HostResolveTakweesh` all clear `swaRequest`, so the AFK timer eventually re-arms.

### 3. `_HostStepBid` redeal cycle — bounded yields, not a tight loop
- R1 all-pass → `HostBeginRound2` → R2 all-pass → `_HostRedeal("allpass")`.
- `_HostRedeal` uses `C_Timer.After(3.0, ...)` (Net.lua:1658) before dealing — every cycle yields ≥3s to the WoW frame loop. Even an adversarial sequence of all-pass redeals is not a tight loop; the dealer rotates by `(s.dealer % 4) + 1` so the deck distribution shifts each cycle. Bot.PickBid eventually returns non-PASS for stronger hands. No unbounded synchronous loop possible.
- `_redealGen` token (Net.lua:1656) invalidates pending callbacks on `/baloot reset`, preventing ghost rounds.

### 4. Sun-overcall window — both timer and early-close cover all paths
- `_HostBeginOvercallWindow` (Net.lua:1111): bots' decisions recorded synchronously at window-open (lines 1127-1136). If all 4 already decided → immediate `_HostResolveOvercall`. Otherwise `C_Timer.After(K.OVERCALL_TIMEOUT_SEC, _HostResolveOvercall)` at line 1143 — guaranteed close.
- `_OvercallAllDecided` short-circuits the timer when humans complete early (line 1239).
- No path where neither host nor clients advance: even if every human ignores the window, the 5s timeout fires `_HostResolveOvercall`, which calls `MaybeRunBot` or `HostFinishDeal`. **Safe.**

### 5. Bel/Triple/Four/Gahwa malformed-fire defense — idempotent
- Each `_On{Double,Triple,Four,Gahwa}` (Net.lua:833,888,904,921) checks (a) phase matches, (b) caller seat matches the eligible role (defender for Bel/Four, bidder for Triple/Gahwa), (c) flag not yet set (`contract.tripled`, `.foured`, `.gahwa`). A bot firing Bel after host says skip would either (i) fail the phase check (phase already advanced via HostFinishDeal) or (ii) fail the flag check. **Re-fire impossible.**
- `S.ApplyDouble/Triple/Four/Gahwa` advance phase before any subsequent dispatch.

### 6. Trick-resolution 2.2s wait — phase-guarded
- `C_Timer.After(2.2, ...)` body (Net.lua:1564-1581) explicitly checks `paused`, `phase == PHASE_PLAY`, contract presence, and `#trick.plays >= 4` before resolving.
- If Takweesh fires during the 2.2s window, `HostResolveTakweesh` (Net.lua:2033) sets `phase = PHASE_SCORE` via `S.ApplyRoundEnd` (State.lua:1359-1362), and the deferred 2.2s timer correctly bails on the phase check — but `HostResolveTakweesh` itself drives the round-end transition. **No path where the timer fires but `_HostStepAfterTrick` doesn't advance** — either the timer body advances normally, or Takweesh has already advanced it, or pause defers to resume which calls `_HostStepPlay` (Net.lua:2297).

---

## Reply
- All six target areas are bounded; redeal "loop" is rate-limited at 3s/cycle with rotating dealer.
- Pause/SWA timer reschedule may stack timers transiently but each callback is idempotent on the guard checks; no soft-lock or runaway.
- Escalation chain cannot re-fire because of phase + flag guards on every receiver.
