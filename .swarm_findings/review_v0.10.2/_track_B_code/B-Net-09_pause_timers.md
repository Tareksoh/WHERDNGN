# B-Net-09 — Deep Audit: Pause / AFK Timer Pipeline

**Audit version**: v0.10.2
**Track**: B (code-level)
**Date**: 2026-05-05
**Scope**: Pause/AFK timer interactions across `Net.lua`, `State.lua`,
`WHEREDNGN.lua`. **No code modifications.**

Cross-refs:
- `D-RT-32` — pause/timer race red-team summary
- `D-RT-13` — SWA permission race
- `D-RT-17` — resync edges
- `audit_v0.9.0/05_m1_m2_timer_rearm.md` — M1/M2 re-arm verification

---

## Verdict matrix (TL;DR)

| # | Scope | Severity | Status |
|---|---|---|---|
| 1 | Pause from non-host (validation drop) | OK | DEFENDED |
| 2 | PHASE_OVERCALL pause-aware re-arm (M1) | OK | DEFENDED |
| 3 | SWA host-self vs remote pause-aware re-arm | OK | DEFENDED |
| 4 | AFK turn timer pause-resume | OK | DEFENDED |
| 5 | Pause + /reload + resume soft-locks OVERCALL/SWA (RT-32.4-B NEW) | **MED** | **UNDEFENDED — soft-lock surface** |
| 6 | Bot-fired SWA timer pause asymmetry (Net.lua:4059) | **MED** | **UNDEFENDED — silent banner soft-lock** |
| 7 | M2 timer re-arm ignores expired window (Edge 5) | LOW | UNDEFENDED — spec divergence (10s window) |
| 8 | Rapid pause-toggle inner re-arm drop (RT-32.13) | LOW | UNDEFENDED — multi-cycle silent drop |
| 9 | HostResolveSWA + _OnSWAResp accept-path no pause guard (RT-32.14) | LOW | UNDEFENDED — pause-permeable resolve |
| 10 | _OnAKA missing pause guard | INFO | UNDEFENDED — cosmetic |
| 11 | Mid-trick 2.2s trick-resolution pause guard | OK | DEFENDED + resume re-fires |

**Headline**: 5 + 6 + 7 are all genuine soft-lock or
spec-divergence surfaces. 8/9 are narrow but exploitable. 10 is
cosmetic. 11 is a model citizen — the others should follow its
shape (timer + resume re-fire).

---

## Finding 1 — Pause from non-host (validation drop) — **DEFENDED**

**Severity**: OK (verifies D-RT-32 RT-32.8).

**Repro**: A non-host peer broadcasts `MSG_PAUSE;1`. Every receiver's
`_OnPause` runs through three gates and early-returns.

**Code (`Net.lua:2452-2459`)**:

```lua
function N._OnPause(sender, payload)
    if fromSelf(sender) then return end
    if not fromHost(sender) then return end          -- AUTH GATE
    if S.s.isHost then return end                    -- host-self bail
    local paused = (payload == "1")
    if S.s.paused == paused then return end
    S.ApplyPause(paused)
end
```

**Validation chain**:
1. `fromSelf(sender)` — drops loopback (`Net.lua:650-653`).
2. `fromHost(sender)` — `normSender(sender) == S.s.hostName`
   (`Net.lua:645-648`). `S.s.hostName` is captured from the legitimate
   host's lobby announcement; addon-channel `sender` is server-set,
   so spoofing the host's name+realm is not possible at the protocol
   layer.
3. `S.s.isHost` — defensive: the active host never applies a pause
   message from itself (would double-apply on top of `LocalPause`).

**Local-side gate**: `N.LocalPause` itself (`Net.lua:2401-2403`) and
the UI pause button (`UI.lua:1249-1263`) both gate on
`if not S.s.isHost then return end`. A non-host who clicks the
button gets nothing — no message broadcast, no state mutation.

**Verdict**: **DEFENDED**. Multi-layer host gate. Spoofed pause
broadcasts are dropped at `_OnPause`.

---

## Finding 2 — PHASE_OVERCALL pause-aware re-arm — **DEFENDED**

**Severity**: OK (verifies M1 fix and audit_v0.9.0/05 PASS).

**Repro**: Host bids Hokm; window opens; host pauses; window's 5s
timer fires.

**Code (`Net.lua:1189-1212`)**:

```lua
local function overcallTimerFn()
    if not S.s.isHost then return end
    if S.s.phase ~= K.PHASE_OVERCALL then return end
    if S.s.paused then
        -- Re-arm a fresh window when the host pauses through a
        -- timeout fire. The 5s resets — humans get a fresh shot
        -- after resume rather than auto-WLA on the resume tick.
        if S.s.overcall then
            S.s.overcall.startedAt = (GetTime and GetTime()) or 0
        end
        if C_Timer and C_Timer.After then
            C_Timer.After(K.OVERCALL_TIMEOUT_SEC, overcallTimerFn)
        end
        return
    end
    N._HostResolveOvercall()
end
C_Timer.After(K.OVERCALL_TIMEOUT_SEC, overcallTimerFn)
```

**Behavior on pause-during-fire**: re-arms fresh 5s, resets
`startedAt = GetTime()` so UI countdown anchor restarts at full 5s.
Comment is explicit about design intent.

**Behavior on pause-without-fire**: NOT compensated. If host pauses
at t=2 and resumes at t=4, fire at t=5 sees `s.paused == false` and
resolves immediately — human got a 4s effective window instead of 5.
This is acceptable per the M1 design (no mid-window cancel/restart
machinery).

**Verdict**: **DEFENDED**. Pause-on-fire = fresh window. Pause-
without-fire shrinks the human's effective window but doesn't
soft-lock (timer eventually fires to resolve).

---

## Finding 3 — SWA host-self vs remote pause-aware re-arm — **DEFENDED**

**Severity**: OK.

Two of the three SWA timer-arming sites are pause-aware:

### 3a — `N.LocalSWA` host-self timer (`Net.lua:2546-2576`)

```lua
C_Timer.After(windowSec, function()
    if not S.s.isHost then return end
    if S.s.paused then
        local req2 = S.s.swaRequest
        if req2 and req2.caller == mySeat then
            req2.ts = (GetTime and GetTime()) or req2.ts
            if C_Timer and C_Timer.After then
                C_Timer.After(K.SWA_TIMEOUT_SEC or 5, function()
                    if S.s.isHost and S.s.swaRequest
                       and S.s.swaRequest.caller == mySeat
                       and S.s.phase == K.PHASE_PLAY
                       and not S.s.paused then
                        S.s.swaRequest = nil
                        N.HostResolveSWA(mySeat, pinnedHand)
                    end
                end)
            end
        end
        return
    end
    local req = S.s.swaRequest
    if not req or req.caller ~= mySeat then return end
    if S.s.phase ~= K.PHASE_PLAY then return end
    S.s.swaRequest = nil
    N.HostResolveSWA(mySeat, pinnedHand)
end)
```

Pause-on-fire: writes new `req.ts`, schedules inner 5s re-arm. UI
countdown restarts. Inner re-arm self-gates on `not S.s.paused` at
fire — silently drops if pause is still on (see Finding 8).

### 3b — `N._OnSWAReq` remote-receive timer (`Net.lua:2693-2730`)

Same shape — outer pause-on-fire re-arms inner 5s; inner self-gates.

Comment at `Net.lua:2697-2700` is explicit:
"respect pause. Without this guard, the SWA timer fires during a
paused game and forcibly auto-approves mid-pause. Re-arm a fresh
5-sec window when the game resumes; until then, swaRequest stays
pending and opponents can still press Takweesh once unpaused."

**Verdict**: **DEFENDED** — both LocalSWA and _OnSWAReq paths
re-arm correctly on pause-fire. Inner re-arm has a known multi-cycle
seam (Finding 8).

---

## Finding 4 — AFK turn timer pause-resume — **DEFENDED**

**Severity**: OK.

**Pause path** (`Net.lua:2407-2408`): `LocalPause(true)` calls
`N.CancelTurnTimer()`. The shared `turnTimer` upvalue is explicitly
cancelled, so any pending AFK fire is dead.

**Resume path** (`Net.lua:2410-2425`):

```lua
N.MaybeRunBot()
if S.s.turn and S.s.turnKind then
    N.StartTurnTimer(S.s.turn, S.s.turnKind)
end
```

`StartTurnTimer` (`Net.lua:3376-3386`) self-gates on `S.s.paused`
(line 3379) and skips bot seats. Resume = fresh 60s, not remaining.

**Bel/Triple/Four/Gahwa**: `StartBelTimer` and `_HostBelTimeout`
share the same `turnTimer` upvalue, so `CancelTurnTimer` covers them
too. Resume's `MaybeRunBot()` re-dispatches into the appropriate
phase branch (DOUBLE/TRIPLE/FOUR/GAHWA), which calls
`StartBelTimer(...)` for the human-eligible seat. Confirmed at
`Net.lua:3645/3699/3750/3794`.

**Defense-in-depth**: timeout bodies (`_HostTurnTimeout` line 3394,
`_HostBelTimeout` line 3476) each re-check `S.s.paused` to defend
against C_Timer queueing one extra callback after Cancel. Cited as
"Re-audit W13 fix" in comments.

**Verdict**: **DEFENDED**. Pause cancels via shared upvalue; resume
re-arms fresh budget via the host-gated paths.

---

## Finding 5 — Pause + /reload + resume soft-locks OVERCALL/SWA — **MED, UNDEFENDED**

**Severity**: MEDIUM (RT-32.4-B NEW; previously unflagged race
between M2 PLAYER_LOGIN re-arm and `LocalPause(false)` resume
re-arm).

**Repro**:
1. Host has an active PHASE_OVERCALL window.
2. Host clicks Pause at t=2 of the 5s window.
3. Host /reloads at t=10. `s.paused` survives (snapshot slot 18 in
   `State.lua:381/453`; not in TRANSIENT_FIELDS at `State.lua:191-
   247`).
4. PLAYER_LOGIN re-arm fires (`WHEREDNGN.lua:255-269`):

```lua
if B.State.s.phase == K.PHASE_OVERCALL
   and B.State.s.overcall then
    B.State.s.overcall.startedAt = (GetTime and GetTime()) or 0
    if C_Timer and C_Timer.After then
        C_Timer.After(K.OVERCALL_TIMEOUT_SEC, function()
            if not B.State.s.isHost then return end
            if B.State.s.phase ~= K.PHASE_OVERCALL then return end
            if B.State.s.paused then return end           -- BARE EARLY-EXIT
            B.Net._HostResolveOvercall()
        end)
    end
end
```

5. Re-armed timer fires at t=15. `s.paused == true` → silent return.
   No further re-arm.
6. Host clicks Resume → `LocalPause(false)`:

```lua
N.MaybeRunBot()
if S.s.turn and S.s.turnKind then
    N.StartTurnTimer(S.s.turn, S.s.turnKind)
end
```

`MaybeRunBot` doesn't have an OVERCALL re-arm branch. `StartTurnTimer`
checks `s.turn`, but PHASE_OVERCALL has no turn pointer.
**OVERCALL window soft-locks indefinitely.** Recovery: another
`/reload` (which would re-fire the M2 re-arm), or `/baloot reset`.

**Same flaw at SWA M2 re-arm** (`WHEREDNGN.lua:278-290`):

```lua
C_Timer.After(K.SWA_TIMEOUT_SEC or 5, function()
    if not B.State.s.isHost then return end
    if not B.State.s.swaRequest then return end
    if B.State.s.swaRequest.caller ~= req.caller then return end
    if B.State.s.phase ~= K.PHASE_PLAY then return end
    if B.State.s.paused then return end                 -- BARE EARLY-EXIT
    local hand = (req.encodedHand
                  and B.Cards.DecodeHand(req.encodedHand))
                 or {}
    local caller = req.caller
    B.State.s.swaRequest = nil
    B.Net.HostResolveSWA(caller, hand)
end)
```

Same bare early-exit on pause; no resume-pump path; SWA banner stuck.

**Why this is genuinely undefended**: the LocalPause(false) resume
branch (`Net.lua:2410-2425`) does not iterate `S.s.overcall` or
`S.s.swaRequest`. The SWA pause-respect was implemented at the
TIMER-CALLBACK layer (Finding 3 outer re-arm), not the
RESUME-PUMP layer. The M2 re-arm is a one-shot post-/reload — once
its bare early-exit fires, nothing else re-arms it.

**Severity**: LOW for the rare specific sequence; MEDIUM as a
soft-lock surface (host has to /baloot reset to recover).

**Files**: `C:\CLAUDE\WHEREDNGN\WHEREDNGN.lua:255-292`
(M2 re-arm), `C:\CLAUDE\WHEREDNGN\Net.lua:2410-2425` (resume branch).

---

## Finding 6 — Bot-fired SWA timer pause asymmetry — **MED, UNDEFENDED**

**Severity**: MEDIUM (D-RT-13.4 / D-RT-32.2c confirmed).

**Repro**:
1. Bot's turn arrives during PHASE_PLAY.
2. `MaybeRunBot`'s play branch fires.
3. `B.Bot.PickSWA(seat)` returns true (bot holds an unbeatable
   position).
4. The branch creates `swaRequest`, broadcasts MSG_SWA_REQ,
   auto-accepts opponent bots, and arms a 5s timer.
5. Host clicks Pause before the 5s elapses.
6. Timer body fires.

**Code (`Net.lua:4059-4067`)**:

```lua
C_Timer.After(K.SWA_TIMEOUT_SEC or 5, function()
    if not S.s.isHost then return end
    if S.s.paused then return end                         -- BARE EARLY-EXIT
    local req = S.s.swaRequest
    if not req or req.caller ~= seat then return end
    if S.s.phase ~= K.PHASE_PLAY then return end
    S.s.swaRequest = nil
    N.HostResolveSWA(seat, hand)
end)
```

Compare to the pause-aware shape at `_OnSWAReq` (Finding 3b) and
`LocalSWA` (Finding 3a): both re-arm a fresh 5s on pause-fire. This
one-shot does not.

**Asymmetry**: human-fired SWAs (LocalSWA + _OnSWAReq) survive pause
correctly; bot-fired SWAs go silent forever.

**Soft-lock outcome**: `swaRequest` never clears. UI banner stuck.
Resume does NOT re-fire any SWA timer (LocalPause(false) doesn't
re-pump SWA — same gap as Finding 5). Recovery: a human Takweeshes,
the round ends some other way, or /reload triggers WHEREDNGN.lua's
M2 re-arm — which has its own bare-early-exit (Finding 5/7).

**Severity**: MEDIUM — bot SWA is a regular gameplay event in
endgame; pause is a regular host action; combined incidence is non-
trivial for groups that use both. Already on backlog as D-RT-13.4
(F-2 from C-Xref-01).

**Files**: `C:\CLAUDE\WHEREDNGN\Net.lua:4040-4075` (bot-fired SWA
branch).

---

## Finding 7 — M2 timer re-arm ignores expired window (Edge 5) — **LOW, UNDEFENDED**

**Severity**: LOW (D-RT-17 #6 still unfixed; verifies
audit_v0.9.0/05 Edge 5 FAIL).

**Repro**:
1. Host opens PHASE_OVERCALL at t=0.
2. Host /reloads at t=10 (5 seconds AFTER the window should have
   already auto-resolved).
3. PLAYER_LOGIN re-arm fires (`WHEREDNGN.lua:256-269`):

```lua
if B.State.s.phase == K.PHASE_OVERCALL
   and B.State.s.overcall then
    B.State.s.overcall.startedAt = (GetTime and GetTime()) or 0
    if C_Timer and C_Timer.After then
        C_Timer.After(K.OVERCALL_TIMEOUT_SEC, function()
            if not B.State.s.isHost then return end
            if B.State.s.phase ~= K.PHASE_OVERCALL then return end
            if B.State.s.paused then return end
            B.Net._HostResolveOvercall()
        end)
    end
end
```

**No `GetTime() - startedAt >= OVERCALL_TIMEOUT_SEC` pre-check**.
Code unconditionally:
- Resets `startedAt` to current `GetTime()`.
- Arms a fresh 5s timer.

**Effective behavior**: human gets a 10s effective window across the
reload boundary (5s pre-/reload + 5s post-/reload re-arm). Spec
divergence — the OVERCALL contract is "5s to decide", not 10s.

**Same flaw at SWA M2 re-arm** (`WHEREDNGN.lua:270-292`):

```lua
local req = B.State.s.swaRequest
req.ts = (GetTime and GetTime()) or req.ts
if C_Timer and C_Timer.After then
    C_Timer.After(K.SWA_TIMEOUT_SEC or 5, function()
        ...
    end)
end
```

Resets `req.ts`, arms fresh 5s, no expired-check.

**Not a soft-lock** — timers do eventually fire — but spec-divergent.
The audit_v0.9.0/05 recommendation stands: pre-check elapsed and
synchronously call `_HostResolveOvercall()` / `HostResolveSWA()`
when already past deadline; only re-arm when within window.

**Severity**: LOW — humans benefit from the extra window (no harm
to defenders); bot-decided seats might surprise the host (extra 5s
for a human to undo a borderline situation).

**Files**: `C:\CLAUDE\WHEREDNGN\WHEREDNGN.lua:255-292`.

---

## Finding 8 — Rapid pause-toggle inner re-arm drop — **LOW, UNDEFENDED**

**Severity**: LOW (D-RT-32 RT-32.13 NEW concrete race).

**Repro**:
1. `t=0`: `N.LocalSWA` (or `_OnSWAReq`) arms outer 5s timer.
2. `t=2`: host pauses. `s.paused = true`.
3. `t=5`: outer timer body executes. Sees `s.paused == true`. Arms
   inner one-shot 5s timer (scheduled for `t=10`). Returns.
4. `t=6`: host resumes. `s.paused = false`.
5. `t=8`: host pauses again. `s.paused = true`.
6. `t=10`: inner timer body executes. Sees `s.paused == true` →
   silent return. **No further re-arm.**
7. `t=15`: host resumes. **Nothing fires.** `swaRequest` hangs.

**Code (inner re-arm at `Net.lua:2553-2566`)**:

```lua
if S.s.paused then
    local req2 = S.s.swaRequest
    if req2 and req2.caller == mySeat then
        req2.ts = (GetTime and GetTime()) or req2.ts
        if C_Timer and C_Timer.After then
            C_Timer.After(K.SWA_TIMEOUT_SEC or 5, function()
                if S.s.isHost and S.s.swaRequest
                   and S.s.swaRequest.caller == mySeat
                   and S.s.phase == K.PHASE_PLAY
                   and not S.s.paused then     -- inner pause check
                    S.s.swaRequest = nil
                    N.HostResolveSWA(mySeat, pinnedHand)
                end
            end)
        end
    end
    return
end
```

The inner re-arm is **a one-shot**. If at inner-fire time
`S.s.paused == true`, all four predicates fail (`not S.s.paused`),
the body silently returns, and nothing schedules a second-level
re-arm.

**Same shape at three sites**:
- `N.LocalSWA` host-self timer (`Net.lua:2546-2576`).
- `N._OnSWAReq` remote-receive timer (`Net.lua:2693-2730`).
- `WHEREDNGN.lua:262-292` M2 reload re-arm (also one-shot;
  Finding 5 covers the resume gap).

**The PHASE_OVERCALL re-arm at `Net.lua:1195-1212` does NOT have
this bug** — its `overcallTimerFn` recursively schedules another
call to itself on each pause-fire, so multi-cycle pause keeps
re-arming forever. The SWA paths instead schedule a different inner
closure that drops on second pause.

**Recommendation per D-RT-32**: `LocalPause(false)` resume branch
should inspect `S.s.swaRequest` and re-arm the SWA auto-resolve
timer if present, mirroring the `_HostStepPlay` re-fire at line
2419. Same for OVERCALL.

**Severity**: LOW — requires pause-resume-pause within ~5s window
plus inner timer fires mid-second-pause. Rare in practice. Triggered
by hosts who toggle pause to think.

**Files**: `C:\CLAUDE\WHEREDNGN\Net.lua:2546-2576`, 2693-2730.

---

## Finding 9 — HostResolveSWA + _OnSWAResp accept-path no pause guard — **LOW, UNDEFENDED**

**Severity**: LOW (D-RT-32 RT-32.14 / D-RT-13.11 confirmed).

**Repro**:
1. Host has a PHASE_PLAY game; SWA permission request is in flight.
2. Two opponents accept (humans, or one human + an auto-accepting
   bot from `_OnSWAReq`'s `S.s.isHost` block at `Net.lua:2678-
   2685`).
3. Host clicks Pause before the second accept lands.
4. `_OnSWAResp` fires for the second accept. `s.paused == true`.

**Code (`_OnSWAResp` accept-tally at `Net.lua:2792-2806`)**:

```lua
if not S.s.isHost then return end
local oppTeam = (R.TeamOf(caller) == "A") and "B" or "A"
local accepts = 0
for s2 = 1, 4 do
    if R.TeamOf(s2) == oppTeam and req.responses[s2] == true then
        accepts = accepts + 1
    end
end
if accepts >= 2 then
    local hand = C.DecodeHand(req.encodedHand or "")
    S.s.swaRequest = nil
    N.HostResolveSWA(caller, hand)
end
```

**No `S.s.paused` check** at the entry of `_OnSWAResp` (line 2735),
nor in the accept-tally branch above.

**Code (`HostResolveSWA` entry at `Net.lua:2862-2866`)**:

```lua
function N.HostResolveSWA(callerSeat, callerHand)
    if not S.s.isHost or not S.s.contract then return end
    if S.s.phase ~= K.PHASE_PLAY then return end
    N.CancelTurnTimer()
    ...
```

**No `S.s.paused` check.** SWA resolves through pause once accepts
land.

**Practical exploit**: a host expecting to veto a borderline SWA via
pause finds the SWA already resolved if both opponent accepts arrive
on the wire before the host's pause broadcast does. With auto-
accepting opponent bots, the resolution is synchronous within
`_OnSWAReq` (Net.lua:2678-2685) — pause cannot stop a
bot-only-opponent SWA at all.

**Severity**: LOW — race-window-dependent for human opponents;
"impossible" for bot opponents (synchronous resolution at request
creation; pause arrives after).

**Recommendation**: add `if S.s.paused then return end` at
`HostResolveSWA` entry for defense-in-depth. Optionally defer the
accept-tally if paused, queuing the resolve until resume.

**Files**: `C:\CLAUDE\WHEREDNGN\Net.lua:2735-2807` (_OnSWAResp),
2862+ (HostResolveSWA).

---

## Finding 10 — _OnAKA missing pause guard — **INFO, UNDEFENDED (cosmetic)**

**Severity**: INFO (D-RT-32 RT-32.6-A).

**Repro**: A non-host seat owner broadcasts MSG_AKA during a paused
game. Receivers run `_OnAKA`.

**Code (`Net.lua:3075-3096`)**:

```lua
function N._OnAKA(sender, seat, suit, replayFlag)
    if fromSelf(sender) then return end
    if not seat or seat < 1 or seat > 4 then return end
    if not suit or suit == "" then return end
    local isReplay = (replayFlag == "1") and fromHost(sender)
    if isReplay and S.s.isHost then return end
    if not isReplay and not authorizeSeat(seat, sender) then return end
    if S.s.phase ~= K.PHASE_PLAY then return end
    if not S.s.contract or S.s.contract.type ~= K.BID_HOKM then return end
    S.ApplyAKA(seat, suit)
end
```

**No `S.s.paused` check.** A remote AKA call during pause writes
`s.akaCalled = {seat, suit}` via `S.ApplyAKA` (`State.lua:1443-
1450`) and triggers the AKA voice cue (`B.Sound.Cue(K.SND_VOICE_AKA)`).
Then `B.UI.Refresh()` paints the banner OVER the pause overlay.

**Compare to other handlers that DO guard pause**:
- `_OnPause` itself — idempotent guard.
- `_OnKawesh` (`Net.lua:3244`) — explicit `if S.s.paused then return
  end` per "Re-audit W8 fix".
- `_HostTurnTimeout` (`Net.lua:3394`) — Re-audit W13 fix.
- `_HostBelTimeout` (`Net.lua:3476`) — same.

`_OnAKA` is the odd one out. **Cosmetic only** — AKA doesn't change
scoring; banner cleared on next `ApplyTrickEnd`. Authorization gate
(line 3087) limits the spam to legitimate seat owners.

**Severity**: INFO — cosmetic inconsistency, not exploitable.

**Recommendation**: add `if S.s.paused then return end` after the
phase check at line 3090 for behavioral consistency with the other
guarded handlers.

**Files**: `C:\CLAUDE\WHEREDNGN\Net.lua:3075-3096`.

---

## Finding 11 — Mid-trick 2.2s trick-resolution timer pause guard — **DEFENDED + RESUME RE-FIRES**

**Severity**: OK.

**Repro**: All 4 plays in trick land; `_HostStepPlay` schedules a
2.2s C_Timer. Host pauses during the 2.2s window.

**Code (`Net.lua:1629-1646`)**:

```lua
C_Timer.After(2.2, function()
    if not S.s.isHost then return end
    -- Pause-state guard: if the host paused during the 2.2s
    -- window, don't resolve the trick into a paused state — wait
    -- for resume to fire the next StepPlay.
    if S.s.paused then return end
    if S.s.phase ~= K.PHASE_PLAY then return end
    if not S.s.contract then return end
    if not S.s.trick or #S.s.trick.plays < 4 then return end
    local winner = R.TrickWinner(S.s.trick, S.s.contract)
    local points = R.TrickPoints(S.s.trick, S.s.contract)
    N.SendTrick(winner, points)
    S.ApplyTrickEnd(winner, points)
    N._HostStepAfterTrick()
    if B.UI then B.UI.Refresh() end
end)
```

**Resume re-fire** (`Net.lua:2416-2425`):

```lua
if S.s.phase == K.PHASE_PLAY
   and S.s.trick and S.s.trick.plays
   and #S.s.trick.plays >= 4 then
    N._HostStepPlay()
else
    N.MaybeRunBot()
    if S.s.turn and S.s.turnKind then
        N.StartTurnTimer(S.s.turn, S.s.turnKind)
    end
end
```

This is the v0.7.1 audit #4 fix explicitly called out at Net.lua:
2412-2415. **`LocalPause(false)` detects the stuck-4-card state and
re-fires `_HostStepPlay()`**, which schedules a fresh 2.2s timer.

**This is the canonical pattern that the SWA / OVERCALL re-arms
should follow.** Bare early-exit at the timer callback +
explicit resume-side re-fire is structurally cleaner than the
"pause-aware re-arm at callback" patterns in Findings 3 and 5 —
which both have the multi-cycle drop seam (Finding 8) and the
post-/reload soft-lock seam (Finding 5).

**Coverage**: Pause + /reload restores `s.paused == true`. The
PLAYER_LOGIN re-arm at `WHEREDNGN.lua:206-217` covers exactly this
case:

```lua
if s.phase == K.PHASE_PLAY and s.trick
   and s.trick.plays and #s.trick.plays >= 4
   and B.Net and B.Net._HostStepPlay then
    C_Timer.After(0.5, function()
        if not B.State.s.isHost then return end
        if B.State.s.phase ~= K.PHASE_PLAY then return end
        if B.State.s.paused then return end
        if not B.State.s.trick then return end
        if #B.State.s.trick.plays < 4 then return end
        B.Net._HostStepPlay()
    end)
end
```

`if B.State.s.paused then return end` (bare early-exit) — but the
RESUME branch at `Net.lua:2416-2419` will catch the still-stuck
state and re-fire `_HostStepPlay` anyway. **No soft-lock surface
because the resume-pump exists for this case.**

**Verdict**: **DEFENDED**, with the cleanest pattern in the codebase.

**Files**: `C:\CLAUDE\WHEREDNGN\Net.lua:1629-1647`,
2412-2419 (resume re-fire), `WHEREDNGN.lua:206-217` (post-/reload
re-arm).

---

## Cross-cutting summary table

| Site | Pause guard at fire? | Re-arm on pause? | Resume re-pump? |
|---|---|---|---|
| OVERCALL timer (`Net.lua:1188`) | YES | YES (recursive) | NO |
| `_HostResolveOvercall` (`Net.lua:1234`) | NO | N/A | N/A |
| SWA `LocalSWA` outer (`Net.lua:2546`) | YES | YES (one-shot) | NO |
| SWA `_OnSWAReq` outer (`Net.lua:2693`) | YES | YES (one-shot) | NO |
| SWA bot-fired (`Net.lua:4059`) | YES | **NO** (Finding 6) | NO |
| SWA M2 reload re-arm (`WHEREDNGN.lua:278`) | YES | NO (Finding 5) | NO |
| OVERCALL M2 reload re-arm (`WHEREDNGN.lua:262`) | YES | NO (Finding 5) | NO |
| `HostResolveSWA` (`Net.lua:2862`) | **NO** (Finding 9) | N/A | N/A |
| `_OnSWAResp` accept (`Net.lua:2800`) | **NO** (Finding 9) | N/A | N/A |
| `StartTurnTimer` (`Net.lua:3376`) | YES (gate) | NO | YES (resume re-arms via 2423) |
| `_HostTurnTimeout` (`Net.lua:3388`) | YES | NO | YES (resume) |
| `StartBelTimer` (`Net.lua:3461`) | YES (gate) | NO | YES (via MaybeRunBot in resume) |
| `_HostBelTimeout` (`Net.lua:3473`) | YES | NO | YES (via MaybeRunBot) |
| `_HostStepPlay` 2.2s (`Net.lua:1629`) | YES | NO | YES (Finding 11) |
| `_HostRedeal` 3.0s (`Net.lua:1752`) | YES | NO | NO (rare soft-lock) |
| `_OnAKA` (`Net.lua:3075`) | **NO** (Finding 10) | N/A | N/A (cosmetic) |
| `_OnPause` auth gate (`Net.lua:2452`) | YES (host gate) | N/A | N/A |

**Key patterns**:

1. **Resume re-pump asymmetry** (Findings 5, 6, 8): turn / Bel /
   trick-resolution all re-fire on resume via `LocalPause(false)`.
   OVERCALL / SWA permission timers do NOT — they rely on
   timer-body's one-shot (or recursive) re-arm. The asymmetry is
   the source of the soft-lock surfaces.
2. **One-shot vs recursive re-arm** (Finding 8): OVERCALL uses
   recursive `overcallTimerFn` re-scheduling itself; SWA paths use
   inner closures that drop on second pause-fire.
3. **Resolve-path pause-permeability** (Finding 9):
   `HostResolveSWA` and `_OnSWAResp` accept-tally bypass pause
   entirely. Synchronous resolution paths can complete through pause.
4. **Cosmetic timer leakage** (Finding 10): `_OnAKA` writes state +
   plays voice cue mid-pause. Cosmetic only.

**Recommendation cluster**: add a `LocalPause(false)` resume-side
re-pump for OVERCALL and SWA windows mirroring the `_HostStepPlay`
re-fire pattern (`Net.lua:2416-2419`). This single change addresses
Findings 5, 6, and 8 simultaneously and matches the cleanest
existing pattern (Finding 11).

---

## Confidence

**HIGH** on:
- Findings 1, 2, 4 DEFENDED with explicit code citations.
- Findings 5, 6, 8 UNDEFENDED with reproducible step sequences.
- Finding 11 DEFENDED — same pattern as the recommended fix shape.
- Findings 9, 10 UNDEFENDED but bounded (synchronous / cosmetic).

**MEDIUM** on:
- Finding 7 spec-divergence — depends on whether 10s effective
  window across reload boundary is acceptable per spec; the M2
  fix as written grants this.

---

## Files referenced

- `C:\CLAUDE\WHEREDNGN\Net.lua` — 296-298 (SendPause), 590-591
  (MSG_PAUSE dispatch), 1090-1218 (overcall + M1 re-arm), 1234-1265
  (_HostResolveOvercall — no pause guard), 1629-1647 (_HostStepPlay
  2.2s), 1752-1780 (_HostRedeal 3.0s), 2401-2459 (LocalPause /
  _OnPause), 2473-2586 (LocalSWA + 2546 pause-aware re-arm),
  2640-2733 (_OnSWAReq + 2693 pause-aware re-arm), 2735-2807
  (_OnSWAResp), 2862+ (HostResolveSWA — no pause guard), 3075-3096
  (_OnAKA), 3270-3508 (turn / Bel timers + timeouts), 4040-4075
  (MaybeRunBot bot-fired SWA — bare pause early-exit).
- `C:\CLAUDE\WHEREDNGN\State.lua` — 95-130 (init, ApplyPause),
  191-247 (TRANSIENT_FIELDS — paused NOT transient), 381 / 453
  (resync wire layout slot 18 = paused), 137-158
  (ApplyRedealAnnouncement), 1443-1450 (ApplyAKA).
- `C:\CLAUDE\WHEREDNGN\WHEREDNGN.lua` — 130-217 (PLAYER_LOGIN
  re-arms), 250-292 (M2 OVERCALL + SWA reload re-arm).
- `C:\CLAUDE\WHEREDNGN\Constants.lua` — K.OVERCALL_TIMEOUT_SEC=5
  (line 297), K.SWA_TIMEOUT_SEC=5 (line 281), K.TURN_TIMEOUT_SEC=60
  (line 269).
- `C:\CLAUDE\WHEREDNGN\.swarm_findings\audit_v0.9.0\05_m1_m2_timer_rearm.md`
  — Edge 5 FAIL.
- `C:\CLAUDE\WHEREDNGN\.swarm_findings\review_v0.10.2\_track_D_redteam\D-RT-32_pause_timer_race.md`
  — RT-32.4-B / RT-32.13 / RT-32.14 cross-refs.
- `C:\CLAUDE\WHEREDNGN\.swarm_findings\review_v0.10.2\_track_D_redteam\D-RT-13_swa_permission_race.md`
  — RT-13.4 / RT-13.11 cross-refs.
- `C:\CLAUDE\WHEREDNGN\.swarm_findings\review_v0.10.2\_track_D_redteam\D-RT-17_resync_edges.md`
  — Edge 5 re-verification.
