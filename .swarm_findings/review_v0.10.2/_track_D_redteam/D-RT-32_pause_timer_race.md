# D-RT-32 — Pause / Resume / Timer Race Conditions

**Audit version**: v0.10.2
**Track**: D (red-team)
**Date**: 2026-05-05
**Scope**: Red-team WHEREDNGN's pause/resume interactions with the
multiple time-driven systems (PHASE_OVERCALL 5s, SWA 5s, AFK 60s,
Bel/Triple/Four/Gahwa AFK 60s, AKA banner 1-trick, redeal 3.0s,
swaDenied 3.0s, ApplyRedealAnnouncement 3.5s, _HostStepPlay 2.2s
trick resolution). **No code modifications.**

Cross-refs:
- `D-RT-13` (SWA permission race) — bot-fired SWA at Net.lua:4059
  drops on pause without re-arm.
- `audit_v0.9.0/05_m1_m2_timer_rearm.md` Edge 5 — M2 PLAYER_LOGIN
  re-arm ignores expired window.
- `audit_v0.9.0/56_afk_new_phases.md` — LocalPause(false) re-runs
  MaybeRunBot; pause cancels turn timer.
- `audit_v0.7.1/34_pause_afk.md` — pause is `s.paused` plain bool;
  `LocalPause` is idempotent on no-change.

---

## TL;DR (verdict at the top)

| # | Scenario | Verdict | Severity |
|---|---|---|---|
| 1 | Pause during PHASE_OVERCALL window | **DEFENDED** | OK |
| 2 | Pause during SWA window (host-self path / remote path) | **DEFENDED** | OK |
| 2b | Pause during SWA window (bot-fired path) | **UNDEFENDED** | MED (D-RT-13.4) |
| 3 | Multiple pauses inside one window — drift / nested re-arm | **PARTIALLY DEFENDED** | LOW (multi-cycle quirk) |
| 4 | Pause + /reload — paused state survives, timer paths re-check | **PARTIALLY DEFENDED** | LOW–MED |
| 5 | AFK turn timer pause-resume (StartTurnTimer / _HostTurnTimeout) | **DEFENDED** | OK |
| 5b | Bel/Triple/Four/Gahwa AFK timer pause-resume | **DEFENDED** | OK |
| 6 | AKA banner pause-resume | **UNDEFENDED** (no per-trick timer; **see body**) | INFO |
| 7 | PauseResume across clients (broadcast race) | **MOSTLY DEFENDED** | LOW |
| 8 | Pause from non-host (validation drop) | **DEFENDED** | OK |
| 9 | _HostStepPlay 2.2s trick resolution mid-pause | **DEFENDED** | OK |
| 10 | _HostRedeal 3.0s deal mid-pause | **DEFENDED** | OK |
| 11 | swaDenied 3.0s toast clears mid-pause | **UNDEFENDED** | INFO |
| 12 | ApplyRedealAnnouncement 3.5s clear mid-pause | **UNDEFENDED** | INFO |
| 13 | Toggle pause off-and-on rapidly without inner timer firing | **PARTIALLY DEFENDED** | LOW (silent mid-cycle drop) |
| 14 | HostResolveSWA called via _OnSWAResp accept while paused | **UNDEFENDED** | LOW (D-RT-13.11) |

**One genuinely new finding (RT-32.13)**: rapid pause-toggle within
one re-arm cycle silently drops the inner re-arm. Two confirmations
of D-RT-13's known bot-SWA gap. Several undefended-but-cosmetic
short-timer banners (RT-32.11/12).

---

## Scenario 1 — Pause during PHASE_OVERCALL — **DEFENDED**

**Code**: `Net.lua:1188-1218`

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

**Resume behavior**: Fresh 5s, NOT remaining 4s. Comment is explicit:
"The 5s resets — humans get a fresh shot after resume rather than
auto-WLA on the resume tick." `S.s.overcall.startedAt` is reset to
current `GetTime()` so the UI countdown anchor restarts at full 5s.

**Edge — pause exactly AT timer-fire moment**: WoW addons run
single-threaded. The `C_Timer` callback runs to completion before
any further input is processed. So if pause was applied 1ms before
the timer body executes, the body sees `S.s.paused == true` and
re-arms; if pause was applied 1ms after the body's `if S.s.paused`
check, the resolve runs to completion. **No race**, just timing.

**Edge — pause during early resolve check**: at line 1109,
`_OnOvercallDecision` may call `_HostResolveOvercall()` directly
when all 4 seats decided. There is **no pause check at line 1109**.
If the host pauses at the moment a final decision arrives,
`_HostResolveOvercall` runs through pause. Practical impact: **the
overcall resolves early through pause**. This is mild — the
contract was about to resolve anyway with all 4 votes in.

**Verdict**: **DEFENDED** for the timer path. Mild gap in the
all-decided early-close path — `_HostResolveOvercall` itself has no
`S.s.paused` guard at Net.lua:1234. But every inbound decision
triggers it via `_OnOvercallDecision`, and pause-state is
unauthoritative here. No fix needed.

---

## Scenario 2 — Pause during SWA window — **DEFENDED (host & remote paths), UNDEFENDED (bot path)**

Three timer-arming sites for SWA permission window:

### 2a. `N.LocalSWA` host-self timer (Net.lua:2546-2576) — **DEFENDED**

```lua
C_Timer.After(windowSec, function()
    if not S.s.isHost then return end
    -- 50-agent playtest audit fix: pause-respecting
    -- re-arm. Same logic as _OnSWAReq's timer. If
    -- paused, defer the auto-approve to the next
    -- 5-sec window after resume.
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
    -- ... resolve path
end)
```

Fresh 5s on pause-fire. `req.ts` reset so UI countdown restarts.
Inner re-arm checks pause again; if still paused, **silently drops**
(bug seam — see RT-32.13 below).

### 2b. `N._OnSWAReq` remote-receive timer (Net.lua:2693-2730) — **DEFENDED (same shape)**

Same re-arm-on-pause pattern. Comment at Net.lua:2697-2700: "respect
pause. Without this guard, the SWA timer fires during a paused game
and forcibly auto-approves mid-pause. Re-arm a fresh 5-sec window
when the game resumes; until then, swaRequest stays pending and
opponents can still press Takweesh once unpaused."

### 2c. `MaybeRunBot` bot-fired SWA timer (Net.lua:4059-4067) — **UNDEFENDED**

```lua
C_Timer.After(K.SWA_TIMEOUT_SEC or 5, function()
    if not S.s.isHost then return end
    if S.s.paused then return end                   -- bare early-exit
    local req = S.s.swaRequest
    if not req or req.caller ~= seat then return end
    if S.s.phase ~= K.PHASE_PLAY then return end
    S.s.swaRequest = nil
    N.HostResolveSWA(seat, hand)
end)
```

Bare `if S.s.paused then return end` early-exit. **No re-arm.** If
the bot-fired SWA's 5s timer fires during a pause, the callback
returns silently and `swaRequest` stays set indefinitely. Resume
does NOT re-fire the resolution — the bot's SWA hangs the UI
banner forever until a human Takweeshes, the round ends another
way, or /reload triggers WHEREDNGN.lua:270-292 restore-rearm.

This is the **D-RT-13.4 finding (F-2 from C-Xref-01)** confirmed
again. Already on backlog.

**Resume behavior**:
- 2a / 2b: fresh 5s, NOT remaining time.
- 2c: timer is gone forever; soft-locked banner.

**Verdict**: 2a/2b DEFENDED, 2c UNDEFENDED — confirmed prior find.

---

## Scenario 3 — Multiple pauses in one window — drift? — **PARTIALLY DEFENDED**

Question: pause → wait 2s → resume → pause again. Does the OVERCALL
clock drift? Does SWA?

**OVERCALL** (Net.lua:1198-1208): the re-arm only fires if the
timer body executes during a pause. If the host pauses for 3s
without the timer body firing (timer was scheduled at t=0, fires
at t=5; pause at t=2, resume at t=4; fire at t=5), the body sees
`S.s.paused == false` at fire time and resolves IMMEDIATELY.
**No accounting for the 2 seconds spent paused.** Net effect: a
4s window for the human, not 5.

But: the comment at Net.lua:1198-1201 implies the design intent is
"if the timer FIRES during a pause, give a fresh window". Pause-
without-fire has no compensation. **This is acceptable per the
M1 design** (audit_v0.9.0/05_m1_m2_timer_rearm.md is silent on
mid-window pause-without-fire).

**SWA** (Net.lua:2546): same shape. Pause-without-fire → no
compensation; pause-during-fire → fresh window.

**Drift accumulation**: across multiple pause cycles within one
window:
- Each cycle that doesn't trigger a fire shaves elapsed-time off
  the human's effective window.
- Each cycle that DOES trigger a fire grants a fresh 5s.
- In the worst case (multiple 4.99-second pauses, each ending just
  before the timer body fires), the human gets a continuously-
  shrinking window. NOT a drift toward longer-than-5s; drift
  toward shorter.

**Verdict**: **PARTIALLY DEFENDED**. Pause-on-fire = fresh window.
Pause-without-fire = silent shrinkage. Acceptable design trade-off
(no mid-window timer cancel/restart machinery).

---

## Scenario 4 — Pause + /reload — paused state survives — **PARTIALLY DEFENDED**

**Pause survives /reload?** YES.
- `s.paused` is in the SaveSession snapshot (State.lua:381 wire
  layout slot 18, line 453 reads `s.paused = (f[18] == "1")`).
- TRANSIENT_FIELDS (State.lua:191-247) does NOT include `paused`.
- So a /reload during a paused game restores `s.paused = true`.

**What re-arms on the host's PLAYER_LOGIN?** WHEREDNGN.lua:130-217:

```
- Line 161: MaybeRunBot
- Line 172-178: StartTurnTimer for active human turn
- Line 179-197: StartBelTimer for DOUBLE/TRIPLE/FOUR/GAHWA
- Line 206-217: _HostStepPlay re-fire for stuck 4-play tricks
- Line 250-269: M2 OVERCALL re-arm
- Line 270-292: M2 SWA re-arm
```

**Each re-armed timer's pause guard:**

| Timer | Pause check at fire time? | Re-arm on pause? |
|---|---|---|
| StartTurnTimer (Net.lua:3376-3386) | `if S.s.paused then return end` at entry (line 3379) | NO — bare early-return |
| _HostTurnTimeout (Net.lua:3388-3454) | `if S.s.paused then return end` at line 3394 | NO — bare early-return |
| StartBelTimer (Net.lua:3461-3471) | line 3464 | NO |
| _HostBelTimeout (Net.lua:3473-3508) | line 3476 | NO |
| _HostStepPlay 2.2s (Net.lua:1629) | line 1634 | NO |
| _HostRedeal 3.0s (Net.lua:1752) | line 1762 | NO |
| WHEREDNGN.lua:262-267 OVERCALL re-arm | line 265 | NO |
| WHEREDNGN.lua:278-290 SWA re-arm | line 283 | NO |

**Critical insight**: NONE of the post-/reload re-armed timers do
pause-aware re-arm. They all bare-early-exit on pause. So a host
who:

1. Pauses the game.
2. /reloads.
3. Restore fires PLAYER_LOGIN re-arm (StartTurnTimer for active
   seat); the timer is created.
4. 60 seconds later, the AFK timer fires its body.
5. Body checks `S.s.paused == true` → returns silently.
6. **No re-arm**. Resume does not fire AFK auto-action.

The *resume path* (`N.LocalPause(false)` at Net.lua:2410-2425) calls
`MaybeRunBot()` and `StartTurnTimer(s.turn, s.turnKind)`. That
re-arms a fresh 60s. So effectively: **as long as the host actively
clicks Resume on the pause button, AFK timers re-arm correctly.**
If the host never clicks Resume (quits the game), the timer is gone
along with the addon.

**Subtle gap (RT-32.4-A, NEW LOW)**: if the host /reloads while
paused, then /reloads AGAIN while still paused (without ever
clicking Resume between the two reloads), the second /reload's
PLAYER_LOGIN re-arm fires StartTurnTimer with full 60s budget. The
human at the active seat had effectively unlimited AFK time as long
as the host kept /reloading. Not exploitable (host griefing
themselves), but architecturally surprising.

**Subtle gap (RT-32.4-B, NEW MED)**: Edge 5 from
audit_v0.9.0/05 is still FAIL: `WHEREDNGN.lua:262-267` OVERCALL
re-arm doesn't check `GetTime() - startedAt >= 5`. If the host
/reload-ed at second 6 of a 5s window that should already have
auto-resolved, the fix re-arms ANOTHER fresh 5s window instead of
immediately resolving. Same flaw at line 278-290 for SWA.

**With pause added to the mix**: host pauses at t=2 of a 5s
OVERCALL window, /reloads at t=10. Restore fires re-arm at fresh 5s.
But `s.paused == true` from the snapshot → re-arm timer body checks
`if B.State.s.paused then return end` (line 265) → silent return.
Then host clicks Resume → `LocalPause(false)` resume branch fires
`MaybeRunBot` (line 2421) and `StartTurnTimer(...)` (line 2423).
**But these don't cover OVERCALL** — the OVERCALL re-arm was the
restore-time one-shot, which already fired-and-dropped silently.

So: pause + /reload + resume can SOFT-LOCK the OVERCALL window. The
contract sits in PHASE_OVERCALL forever. Recovery: another
pause-toggle (still won't fire OVERCALL — there's no path that
re-arms OVERCALL on resume), or /baloot reset.

**This is a previously-unflagged race** between the M2 PLAYER_LOGIN
re-arm and the LocalPause resume re-arm. **Severity LOW** (requires
specific pause + /reload + resume sequence + OVERCALL window) but
**MEDIUM** as a soft-lock surface.

**Verdict**: **PARTIALLY DEFENDED**. Pause survives /reload (good),
but OVERCALL/SWA re-arms post-/reload are bare-early-exit with no
wakeup path on resume. The LocalPause resume branch covers turn
timers but NOT OVERCALL/SWA permission timers.

---

## Scenario 5 — AFK turn timer pause-resume — **DEFENDED**

**Pause path**: `N.LocalPause(true)` → `N.CancelTurnTimer()` at
Net.lua:2408. The turn timer is explicitly cancelled, NOT just
guarded.

**Resume path**: `N.LocalPause(false)` at Net.lua:2410-2425:

```lua
N.MaybeRunBot()
if S.s.turn and S.s.turnKind then
    N.StartTurnTimer(S.s.turn, S.s.turnKind)
end
```

A fresh 60s timer is re-armed. **Resume = fresh 60s, not remaining**.
Defensible: a player who was at 5s before pause shouldn't be
penalised by a 5s post-resume.

**StartTurnTimer's own pause guard** at Net.lua:3379 (`if S.s.paused
then return end`) prevents arming a fresh timer DURING pause. So
the resume re-arm at line 2423 only succeeds because `s.paused` is
already `false` by line 2405 (`S.ApplyPause(paused)` flipped it).

**Edge — _HostStepPlay 2.2s mid-pause**: `N.LocalPause(false)` at
Net.lua:2416-2419:

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

If a 4-play trick was complete when pause hit, the 2.2s timer body
returned silently (line 1634 `if S.s.paused then return end`).
**On resume, _HostStepPlay re-fires.** This is the v0.7.1 audit #4
fix explicitly called out at Net.lua:2412-2415.

**Verdict**: **DEFENDED**. Resume re-arms fresh 60s; trick-resolution
re-fires on resume.

### 5b. Bel/Triple/Four/Gahwa AFK — **DEFENDED**

`StartBelTimer` (Net.lua:3461) and `_HostBelTimeout` (Net.lua:3473)
both check `S.s.paused` at entry. **However**, `StartBelTimer` is
NOT explicitly cancelled by `N.LocalPause(true)` — the function uses
the same `turnTimer` upvalue as `StartTurnTimer`, and
`N.CancelTurnTimer()` cancels it. So pause cancels Bel timers via
the shared `turnTimer` slot.

**Resume re-arm**: `N.LocalPause(false)` doesn't have an explicit
Bel re-arm branch. Instead, `MaybeRunBot()` is called, which checks
phase and routes to:
- PHASE_DOUBLE: bot path C_Timer'd (line 3585) or human path
  `StartBelTimer(belSeat, "double")` (line 3645).
- PHASE_TRIPLE: line 3699 `StartBelTimer(bidder, "triple")` for
  human bidder.
- etc.

So MaybeRunBot's call inside LocalPause's resume branch ALSO arms
the Bel timer for human seats. **Defended** by the MaybeRunBot
re-dispatch.

**Verdict**: **DEFENDED**.

---

## Scenario 6 — AKA banner pause-resume — **NO TIMER (informational)**

**There is no AKA banner timer.** AKA is set via `S.ApplyAKA(seat,
suit)` (State.lua:1443) which writes `s.akaCalled = { seat, suit }`.
The banner clears via `S.ApplyTrickEnd` (State.lua:1327) when the
trick advances.

**Pause behavior**: pausing during PHASE_PLAY mid-trick freezes
`s.akaCalled` indefinitely (visually). The 2.2s `_HostStepPlay`
timer is the only path that calls `ApplyTrickEnd` after a 4th play,
and it bails on pause (Net.lua:1634). Resume re-fires
`_HostStepPlay` (Net.lua:2419), which advances the trick and clears
the AKA banner.

`_OnAKA` (Net.lua:3075-3096) does NOT have an `S.s.paused` guard. So
a remote AKA call DURING pause would still apply via
`S.ApplyAKA` → `s.akaCalled = {...}` and the voice cue would fire
(line 1449 `B.Sound.Cue(K.SND_VOICE_AKA)`). Then `B.UI.Refresh()`
would render the banner over the PAUSED overlay.

**Subtle exploit (RT-32.6-A, NEW INFO)**: a non-host malicious peer
could spam MSG_AKA frames during a paused game to spawn AKA voice
cues and banner flashes. The peer would need to be a seat owner
(authorizeSeat at line 3087 gates on seat ownership), so this is
self-grief at worst. Cosmetic, not exploitable.

**Verdict**: **NO TIMER, NO RACE, but `_OnAKA` is missing a `paused`
guard for cosmetic correctness.** Compare to other handlers that
DO have it: `_OnPause` itself (idempotent), `_OnKawesh` (line 3244
post-W8 fix), `_HostTurnTimeout` (line 3394 post-W13 fix), etc. Add
a `paused` guard at `_OnAKA` for consistency.

---

## Scenario 7 — PauseResume race across clients — **MOSTLY DEFENDED**

**Scenario**: host clicks Pause → `N.LocalPause(true)` runs, calls
`S.ApplyPause(true)` locally, calls `N.SendPause(true)` which
broadcasts `MSG_PAUSE;1`. Each client's `_OnPause` (Net.lua:2452)
applies pause locally.

**Race 1**: host's broadcast is in flight. A client's bot-action
broadcast is also in flight (from before pause). Host receives the
client's bot-action first, applies it; the bot-action is processed
through (turn timer, MaybeRunBot, etc.) BEFORE pause arrives at host.

But: `N.LocalPause(true)` at Net.lua:2401 is host-gated (line 2402
`if not S.s.isHost then return end`). The HOST is the one applying
pause locally first, BEFORE broadcasting. So the host's local
`s.paused == true` at the moment `N.SendPause` broadcasts. Any
incoming MSG_PLAY that arrives at host AFTER `S.ApplyPause(true)`
has been written hits handlers like `_OnPlay` (via dispatch table in
Net.lua) — but most handlers DON'T explicitly check `s.paused`. They
check phase and route to host-side path which then runs MaybeRunBot.
MaybeRunBot's bot-dispatch branches all check `S.s.paused` (e.g.
Net.lua:3592, 3660, 3711).

**Race 2**: client clicks something between local-paint of
`PAUSE_OVERLAY` and applying `s.paused = true`. WoW addons are
single-threaded, so there's NO window between `S.ApplyPause(true)`
(line 2458) and the next event. UI clicks queue as separate events;
they process AFTER pause is applied.

**Race 3 (the real one)**: host pauses while a client is in the
middle of typing a SWA Accept. Client's UI emits MSG_SWA_RESP;1 at
the same moment host broadcasts MSG_PAUSE;1. Both arrive at all
clients' `_OnSWAResp` and `_OnPause` handlers. Order depends on the
network channel ordering. WoW addon channel is FIFO per-sender, so
the host's MSG_PAUSE is ordered with respect to host's other
messages, but client's SWA_RESP is independent.

**Order A**: SWA_RESP arrives at host first → `_OnSWAResp` runs,
maybe writes `req.responses[responder] = true` and counts accepts.
If accepts >= 2 (other bots may have already accepted), calls
`HostResolveSWA(caller, hand)` IMMEDIATELY. **HostResolveSWA has
NO pause check (Net.lua:2862).** SWA resolves synchronously.
THEN MSG_PAUSE arrives, `S.ApplyPause(true)` flips `s.paused`. But
the round may already be in PHASE_SCORE.

**Order B**: MSG_PAUSE arrives at host first → `s.paused = true`.
Then SWA_RESP arrives → `_OnSWAResp` line 2737 dispatches without
a pause check at the entry. Line 2742 reads `S.s.swaRequest` (still
non-nil). Line 2747 writes `req.responses[responder] = accept`.
Counter at line 2794 finds 2+ accepts → calls
`HostResolveSWA(caller, hand)`. **STILL NO pause check.** SWA
resolves through pause.

**Verdict on Race 3**: order doesn't matter — both produce the
same result (SWA resolves through pause). This is **D-RT-13.11
confirmed**: `HostResolveSWA` is missing an `S.s.paused` check at
line 2864, and `_OnSWAResp` accept-path at line 2800 is missing
one too. Pause is semi-permeable to already-consenting SWAs.

**Practical impact**: a host who clicks Pause expecting to veto a
borderline SWA may find the SWA already resolved if both opponent
accepts arrive on the wire before the host's pause broadcast does.

**Verdict**: **MOSTLY DEFENDED** for cross-client race ordering;
`HostResolveSWA` semi-permeability is the documented gap.

---

## Scenario 8 — Pause from non-host (validation drop) — **DEFENDED**

**Code (`N._OnPause` at Net.lua:2452-2459)**:

```lua
function N._OnPause(sender, payload)
    if fromSelf(sender) then return end
    if not fromHost(sender) then return end           -- AUTH GATE
    if S.s.isHost then return end                     -- host-self bail
    local paused = (payload == "1")
    if S.s.paused == paused then return end
    S.ApplyPause(paused)
end
```

A non-host peer broadcasts `MSG_PAUSE;1`. Every receiver's
`_OnPause` runs:
- `fromSelf(sender)` returns false (sender is not me).
- `fromHost(sender)` returns false (sender is not the host).
- **Early return.** Pause not applied.

Spoofing requires impersonating the host's name+realm. The
`fromHost` check uses `S.s.hostName` (`Net.lua:646`), which was
captured from the legitimate host's lobby announcement. To spoof, an
attacker would need to broadcast addon messages with the host's
exact name — which WoW's addon channel does NOT permit (sender
field is server-set).

**`N.LocalPause` itself** (Net.lua:2401-2403):

```lua
function N.LocalPause(paused)
    if not S.s.isHost then return end                 -- HOST GATE
    ...
end
```

UI's pause button (UI.lua:1252) also gates on `if not S.s.isHost
then return end`. So a non-host client clicking Pause locally gets
nothing — no message sent, no state mutated.

**Verdict**: **DEFENDED**. Multi-layer host gate.

---

## Scenario 9 — _HostStepPlay 2.2s mid-pause — **DEFENDED**

Already covered in Scenario 5 (resume re-fires). Quoting Net.lua:1629-1646:

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

Resume path (LocalPause(false) at Net.lua:2416-2419) detects the
stuck-4-card state and re-fires `_HostStepPlay()`, which schedules a
fresh 2.2s timer. Confirmed.

**Verdict**: **DEFENDED**.

---

## Scenario 10 — _HostRedeal 3.0s mid-pause — **DEFENDED**

Code at Net.lua:1752-1780:

```lua
C_Timer.After(3.0, function()
    if thisGen ~= B._redealGen then return end
    if not S.s.isHost then return end
    -- Reset / pause guards: if the user reset or paused during
    -- the 3s redeal banner, abort the deal — otherwise we'd
    -- write fresh round state into a wiped or paused game.
    if S.s.phase ~= K.PHASE_DEAL2BID and S.s.phase ~= K.PHASE_DEAL1
       and not S.s.redealing then
        return
    end
    if S.s.paused then return end
    -- ... fire deal
end)
```

Pause guard at line 1762. **NO RE-ARM** — bare early-exit.
**However**, the resume path doesn't re-fire the redeal either.
LocalPause(false) at Net.lua:2410 calls MaybeRunBot, which doesn't
have a redeal branch.

**Soft-lock potential**: if pause hits during the 3s redeal banner,
the deal silently aborts. Resume does NOT re-deal. The player must
manually restart via /baloot reset.

But: `s.redealing` (the redeal banner state) clears via the 3.5s
auto-clear at State.lua:150 (`ApplyRedealAnnouncement`), which
also lacks a pause check. The banner clears mid-pause, leaving the
host in `phase == PHASE_DEAL2BID` or whatever was active before
redeal. **The next host action (any phase change, pause toggle)
won't redeal on its own.**

**Severity**: LOW (rare — pause must hit within the 3s redeal
window, which only happens after all-pass or Kawesh). User-
recoverable via /baloot reset.

**Verdict**: **DEFENDED** at fire-time; **soft-lock surface** if
pause + (no resume action). Recommend: `LocalPause(false)` resume
branch could detect `S.s.redealing ~= nil` and re-fire the redeal.
Already on backlog spirit.

---

## Scenario 11 — swaDenied 3.0s toast clears mid-pause — **UNDEFENDED (cosmetic)**

Code at Net.lua:2627-2633 (LocalSWAResp deny path) and Net.lua:2761-2767 (_OnSWAResp deny path):

```lua
C_Timer.After(3.0, function()
    if S.s.swaDenied
       and S.s.swaDenied.caller == denyCaller then
        S.s.swaDenied = nil
        if B.UI and B.UI.Refresh then B.UI.Refresh() end
    end
end)
```

No pause check. If the host pauses 1s after a SWA deny, the 3.0s
timer fires 3s later (mid-pause) and clears the toast. The user
sees the deny toast for 1s instead of 3s. Cosmetic only.

**Verdict**: **UNDEFENDED, cosmetic**. INFO-only.

---

## Scenario 12 — ApplyRedealAnnouncement 3.5s clear mid-pause — **UNDEFENDED (cosmetic)**

Code at State.lua:150-156:

```lua
C_Timer.After(3.5, function()
    if s.redealing
       and s.redealing.nextDealer == nextDealerSeat then
        s.redealing = nil
        if B.UI and B.UI.Refresh then B.UI.Refresh() end
    end
end)
```

Same pattern. Banner auto-clears mid-pause; cosmetic only. The
actual deal is gated separately by `_HostRedeal`'s pause check
(Scenario 10).

**Verdict**: **UNDEFENDED, cosmetic**.

---

## Scenario 13 — Rapid pause-toggle within one re-arm cycle (NEW finding) — **PARTIALLY DEFENDED**

**This is the genuine new race.**

`N.LocalSWA`'s pause-aware re-arm at Net.lua:2546-2569:

```lua
C_Timer.After(windowSec, function()
    if not S.s.isHost then return end
    if S.s.paused then
        local req2 = S.s.swaRequest
        if req2 and req2.caller == mySeat then
            req2.ts = (GetTime and GetTime()) or req2.ts
            if C_Timer and C_Timer.After then
                C_Timer.After(K.SWA_TIMEOUT_SEC or 5, function()  -- INNER RE-ARM
                    if S.s.isHost and S.s.swaRequest
                       and S.s.swaRequest.caller == mySeat
                       and S.s.phase == K.PHASE_PLAY
                       and not S.s.paused then       -- pause check at inner-fire
                        S.s.swaRequest = nil
                        N.HostResolveSWA(mySeat, pinnedHand)
                    end
                end)
            end
        end
        return
    end
    -- ... normal resolve
end)
```

**The inner re-arm is a one-shot.** If at inner-fire time
`S.s.paused == false`, it resolves. If `S.s.paused == true`, it
silently drops (no second re-arm).

**Sequence to break it**:

1. `t=0`: `N.LocalSWA` arms outer 5s timer.
2. `t=2`: host pauses. State: `s.paused = true`.
3. `t=5`: outer timer body executes. Sees `s.paused == true`. Arms
   inner 5s timer (scheduled for `t=10`). Returns.
4. `t=6`: host resumes. `s.paused = false`. (LocalPause(false)'s
   resume branch doesn't pump SWA timers.)
5. `t=8`: host pauses again. `s.paused = true`.
6. `t=10`: inner timer body executes. Sees `s.paused == true` →
   silent return. **No further re-arm.**
7. `t=15`: host resumes. **Nothing fires.** swaRequest hangs.
8. SWA banner stuck until manual Takweesh, /reload, or
   pause-toggle (which won't help — LocalPause(false) doesn't
   re-pump SWA).

**Verification** that this is actually a race seam:

- The outer pause-handler arms the inner timer ONCE, at the moment
  it observes `s.paused == true`. That's a single point of detection.
- The inner timer body is the ONLY thing that knows about the
  pending SWA's deferred resolve. If it drops silently (due to
  pause-at-fire), there's no other mechanism that re-arms it.
- `LocalPause(false)` resume branch (Net.lua:2410-2447) doesn't
  iterate `S.s.swaRequest` and doesn't re-arm any SWA timer. The
  SWA pause-respect was implemented at the timer-callback layer,
  not the resume-pump layer.

**Same bug in `_OnSWAReq`** (Net.lua:2693-2718) and the M2 reload
re-arm (WHEREDNGN.lua:270-292). All three sites use the
"re-arm-once-on-pause-fire-then-bare-exit-on-second-pause" pattern.

**This is RT-13.4-B from D-RT-13** flagged as a "silent integer-
overflow risk in extreme cases" — confirmed here as a concrete
exploitable race for soft-locking SWA banners.

**Severity**: LOW — requires the player to pause-resume-pause
within a ~5s window, AND for the inner timer to fire mid-second-
pause. Rare in practice, but not impossible. Can be triggered by
a host who's nervously toggling pause to think.

**Recommendation**: `LocalPause(false)` resume branch should
inspect `S.s.swaRequest` and re-arm the SWA auto-resolve timer if
present, mirroring the `_HostStepPlay` re-fire at line 2419.
Similarly for OVERCALL window.

**Verdict**: **PARTIALLY DEFENDED**. Single pause cycle = OK.
Multi-cycle within one outer-fire = silent drop.

---

## Scenario 14 — HostResolveSWA called via _OnSWAResp accept while paused — **UNDEFENDED**

Already covered as **D-RT-13.11**. `HostResolveSWA` (Net.lua:2862)
does not check `S.s.paused`. The accept-path at `_OnSWAResp` line
2800-2806 calls `HostResolveSWA(caller, hand)` directly when
accepts >= 2.

```lua
if accepts >= 2 then
    local hand = C.DecodeHand(req.encodedHand or "")
    S.s.swaRequest = nil
    N.HostResolveSWA(caller, hand)
end
```

**No pause check.** If both opponents accept while host is paused,
the SWA resolves anyway.

**Bot accept-path**: `_OnSWAReq` (Net.lua:2683) auto-accepts opponent
bots SYNCHRONOUSLY at request-creation. So a host-with-bots SWA
that creates the request fires _OnSWAResp("__host__", bot_seat,
true, caller) twice in quick succession. The second one trips
accepts >= 2 and calls HostResolveSWA — all before the host has any
chance to pause.

**Practical impact**: pause cannot stop a bot-only opponent SWA
because the resolution is synchronous within `_OnSWAReq`'s body.
This is by design.

**Verdict**: **UNDEFENDED but largely impractical.** Recommend
adding `S.s.paused` guard at `HostResolveSWA` entry for
defense-in-depth.

---

## Cross-cutting summary

| Site | Pause guard at fire? | Re-arm on pause? | Resume re-fire? |
|---|---|---|---|
| OVERCALL timer (Net.lua:1188) | YES | YES (re-arm fresh 5s) | NO (no resume re-arm path) |
| `_HostResolveOvercall` (Net.lua:1234) | NO | N/A | N/A |
| SWA LocalSWA timer (2546) | YES | YES (one-shot inner re-arm) | NO (resume doesn't re-pump) |
| SWA _OnSWAReq timer (2693) | YES | YES (one-shot inner re-arm) | NO |
| SWA bot-fired timer (4059) | YES | **NO** (bare early-exit) | NO |
| SWA M2 reload re-arm (WHEREDNGN.lua:278) | YES | NO (bare early-exit) | NO |
| HostResolveSWA (2862) | **NO** | N/A | N/A |
| `_OnSWAResp` accept path (2800) | **NO** | N/A | N/A |
| StartTurnTimer (3376) | YES (gate) | NO | YES (LocalPause(false) re-arms via 2423) |
| _HostTurnTimeout (3388) | YES | NO | YES (via resume re-arm) |
| StartBelTimer (3461) | YES (gate) | NO | YES (via MaybeRunBot in resume) |
| _HostBelTimeout (3473) | YES | NO | YES (via MaybeRunBot in resume) |
| _HostStepPlay 2.2s (1629) | YES | NO | YES (LocalPause(false) re-fires via 2419) |
| _HostRedeal 3.0s (1752) | YES | NO | NO (soft-lock potential) |
| ApplyRedealAnnouncement 3.5s (State.lua:150) | NO | N/A | N/A (cosmetic only) |
| swaDenied 3.0s toast (2627, 2761) | NO | N/A | N/A (cosmetic only) |
| _OnAKA (3075) | NO | N/A | N/A (cosmetic only) |
| _OnPause auth gate (2452) | YES (host gate) | N/A | N/A |

**Patterns**:

- **Resume re-arm coverage is asymmetric.** Turn/Bel/4-trick
  resolution all re-fire on resume. OVERCALL/SWA permission timers
  do NOT — they rely on the timer-body's one-shot re-arm.
- **Multi-cycle pause within one window** silently drops the
  inner re-arm (RT-32.13). True for OVERCALL, both pause-aware
  SWA paths, and the M2 reload re-arm.
- **`HostResolveSWA` and `_OnSWAResp` accept** are pause-permeable.
  Synchronous resolution paths bypass pause once consents land.
- **Cosmetic timers** (3.0/3.5s banners) all bypass pause.
  Acceptable.

---

## Confidence

**HIGH** on:

- Scenario 1, 2 (DEFENDED with explicit code citations).
- Scenario 2c bot-fired SWA UNDEFENDED — D-RT-13.4 confirmation.
- Scenario 4-B M2 OVERCALL/SWA reload re-arm + pause + resume
  soft-lock race (NEW).
- Scenario 8 host-only validation gate.
- Scenario 13 rapid pause-toggle silently drops inner re-arm
  (NEW concrete race).
- Scenario 14 _OnSWAResp accept resolves through pause
  (D-RT-13.11 confirmation).

**MEDIUM** on:

- Scenario 3 mid-window drift — depends on whether design intent
  was "pause-without-fire compensation"; current code is
  pause-on-fire only.
- Scenario 6 _OnAKA pause guard absence — verified, but cosmetic.
- Scenario 10 _HostRedeal soft-lock — verified absent resume
  re-fire, but rare trigger.

---

## Files referenced

- `C:\CLAUDE\WHEREDNGN\State.lua` — lines 95-130 (init, ApplyPause),
  137-158 (ApplyRedealAnnouncement), 191-247 (TRANSIENT_FIELDS),
  381-453 (resync snapshot wire layout), 1300-1340 (ApplyTrickEnd),
  1443-1450 (ApplyAKA).
- `C:\CLAUDE\WHEREDNGN\Net.lua` — lines 296-298 (SendPause),
  590-591 (MSG_PAUSE dispatch), 1090-1218 (overcall handlers + M1
  re-arm), 1234-1265 (_HostResolveOvercall — no pause guard),
  1629-1647 (_HostStepPlay 2.2s), 1752-1780 (_HostRedeal 3.0s),
  2401-2459 (LocalPause/_OnPause), 2473-2586 (LocalSWA + 2546
  pause-aware re-arm), 2640-2733 (_OnSWAReq + 2693 pause-aware
  re-arm), 2735-2807 (_OnSWAResp), 2862+ (HostResolveSWA — no
  pause guard), 2627-2633 / 2761-2767 (swaDenied toast),
  3075-3096 (_OnAKA), 3270-3508 (turn/Bel timers + timeouts),
  4040-4075 (MaybeRunBot bot-fired SWA — bare pause early-exit).
- `C:\CLAUDE\WHEREDNGN\WHEREDNGN.lua` — lines 130-217 (PLAYER_LOGIN
  re-arms), 250-292 (M2 OVERCALL + SWA reload re-arm).
- `C:\CLAUDE\WHEREDNGN\UI.lua` — line 1249-1263 (host-gated pause
  button).
- `C:\CLAUDE\WHEREDNGN\.swarm_findings\audit_v0.9.0\05_m1_m2_timer_rearm.md`
  — Edge 5 FAIL.
- `C:\CLAUDE\WHEREDNGN\.swarm_findings\review_v0.10.2\_track_D_redteam\D-RT-13_swa_permission_race.md`
  — RT-13.4 / RT-13.11 cross-refs.
- `C:\CLAUDE\WHEREDNGN\.swarm_findings\review_v0.10.2\_track_D_redteam\D-RT-17_resync_edges.md`
  — Edge 5 re-verification.
