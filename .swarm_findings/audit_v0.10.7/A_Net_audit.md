# Net.lua audit — v0.10.7 (commit 3a70423)

Comprehensive audit of `C:\CLAUDE\WHEREDNGN\Net.lua` (4293 lines). Cross-referenced
against `Constants.lua`, `State.lua`, `Rules.lua`, `WHEREDNGN.lua`, and
`tests/test_rules.lua` / `tests/test_state_bot.lua`.

Findings are severity-tagged: **CRIT** (correctness/security; ship-blocker),
**HIGH** (data corruption / soft-lock under realistic conditions), **MED**
(edge-case bug or correctness drift), **LOW** (nit / latent / unused code).

---

## Section 1 — Wire dispatch (lines 486-649)

### CRIT-A1 — `_OnDouble` accepts host-broadcasts from non-host peers
**Site:** `Net.lua:878-931` (`_OnDouble`)

**Finding:** Unlike every other host-broadcast handler in this file
(`_OnStart`, `_OnDealPhase`, `_OnHand`, `_OnBidCard`, `_OnTurn`,
`_OnContract`, `_OnTrick`, `_OnRound`, `_OnGameEnd`, `_OnPause`,
`_OnTeams`, `_OnSWAOut`, `_OnTakweeshOut`), the escalation-window
handlers `_OnDouble`, `_OnTriple`, `_OnFour`, `_OnGahwa`,
`_OnSkipDouble/Triple/Four/Gahwa`, `_OnPreempt`, `_OnPreemptPass`,
`_OnTakweesh`, `_OnSWA`, `_OnSWAReq`, `_OnSWAResp`, `_OnAKA`, and
`_OnMeld` all rely solely on `authorizeSeat(seat, sender)`.

That helper accepts any sender that owns the seat — but for a **bot**
seat it accepts only `S.s.hostName`. So a hostile peer who is `seats[3]`
(human) and forges `MSG_DOUBLE;3;1` for their *own* seat will pass.
That's not a vuln in itself.

The real exposure is the host-side post-apply branch at line 924:
```
if S.s.isHost then
    if wasSun or not open then
        N.HostFinishDeal()
    else
        N.MaybeRunBot()
    end
end
```
A peer can freely Bel by their own authorisation regardless of whether
the *peer's seat* is the eligible-defender seat. The pre-check at line
885 already catches mismatch-seat (`if seat ~= eligibleSeat then return end`),
so this is fine. False alarm — but worth noting that the pattern
diverges from the strict `if not fromHost(sender) then return end`
gate used elsewhere. **This is not a bug, just a maintainability concern;
the security boundary is `authorizeSeat + seat==eligibleSeat`.**
Demoting to LOW.

**Severity:** LOW
**Fix shape:** documented; no change needed.

---

### MED-A2 — Unknown-tag dispatch is a silent drop, but `B.UI.Refresh()` still fires
**Site:** `Net.lua:486-649` (`HandleMessage`)

**Finding:** The dispatch is a long `if/elseif` chain followed at line
648 by:
```
if B.UI and B.UI.Refresh then B.UI.Refresh() end
```
Every CHAT_MSG_ADDON with prefix `BLT` triggers a UI refresh, even if
the tag was unknown (no branch matched). This is wasteful (party-channel
chatter from corrupted clients pumps the UI), and it also masks dispatch
gaps — there's no log line for "unknown tag X received". A future
addition to `K.MSG_*` that's forgotten in the dispatcher will fail
silently in production.

**Repro:** broadcast `BLT` prefix message with an unknown 1-char tag.
**Impact:** silent drop with no diagnostic; UI churn on every malformed
or future-unknown frame.
**Fix shape:** add an `else` branch with `log("Debug", "unknown tag: %s", tag)`
and conditionally skip the refresh when no handler ran.

---

### MED-A3 — `_OnPlay` self-heal trusts host-signed plays for *any* seat without phase coherence check
**Site:** `Net.lua:1413-1510` (`_OnPlay`, especially 1454-1469)

**Finding:** The v0.4.6 self-heal block is well-documented:
```
if S.s.turn ~= seat then
    if not fromHost(sender) and not authorizeSeat(seat, sender) then
        return
    end
    S.s.turn     = seat
    S.s.turnKind = "play"
end
```
The intent is "if the host-vouched seat doesn't match local turn,
patch local turn". But this fires even when `S.s.turn` was correctly
nil (e.g., in the brief window between `S.ApplyTrickEnd` clearing
`s.turn` and `S.ApplyTurn(winner, "play")` running). On a slow
client that processes `MSG_PLAY` for the new trick *before* its
own `MSG_TURN` arrives, the local turn pointer gets stomped to
`seat`, which is fine in isolation — but if a same-frame `MSG_TURN`
follows pointing at a *different* seat (e.g., a human host's
auto-play recovery), the second `_OnTurn` apply correctly overwrites.
So this is OK in steady state.

**Latent risk:** the block does not check whether `S.s.contract`
exists. In the rare race where `MSG_PLAY` arrives during phase
transition (after `MSG_DEAL "play"` but before
`S.ApplyContract` had a chance to run on this client),
`R.IsLegalPlay` (called inside `S.ApplyPlay` via the
host-only branch — never on remote clients) is bypassed, but
the play still goes onto the trick struct. Not a corruption bug
on remote clients, but `S.ApplyPlay` on a remote without
`S.s.contract` set will skip the AKA-false detection and the
`hostHands` mutation (both gated on `s.isHost`). Net effect: trick
state is correct.

**Severity:** LOW.
**Fix shape:** add `if S.s.phase ~= K.PHASE_PLAY then return end`
to the self-heal block (mirroring line 1417 above).

---

### LOW-A4 — `K.MSG_KICK = "K"` declared but never sent or handled
**Site:** `Constants.lua:183`

**Finding:** Grep confirms `MSG_KICK` is set in Constants but has no
sender (`N.Send*`) and no handler (`_On*`). It's not in the dispatcher
chain. Either dead code (host kick was planned but unimplemented) or a
silently-removed feature. Take up a unique byte value (K) and is
included in the `R.2` uniqueness test, but otherwise inert.

**Repro:** `grep -nr K.MSG_KICK` produces only the declaration.
**Impact:** `R.2` uniqueness test still passes, so adding a real
new tag using `K` would silently collide — and the test wouldn't
catch it because `MSG_KICK` already owns it.
**Fix shape:** delete `K.MSG_KICK` until the feature ships, or wire
up a stub handler that logs and rejects.

---

### MED-A5 — Dispatch order asymmetry: `MSG_OVERCALL_OPEN`, `MSG_OVERCALL_DECISION` route by exact tag, but `MSG_OVERCALL_RESOLVE` shares a payload-disambiguation branch with `MSG_RESYNC_REQ`
**Site:** `Net.lua:543-547` and `Net.lua:620-639`

**Finding:** The dispatch table has TWO independent branches that may
fire `_OnOvercallResolve`:

1. `tag == K.MSG_OVERCALL_RESOLVE` ("!") at line 543 — canonical post-v0.10.3.
2. `tag == K.MSG_RESYNC_REQ` ("?") with `#fields >= 4` at line 634 — legacy
   v0.10.2 cross-version compat.

The second branch is documented as the dual-emit benign-double-fire
path: "_OnOvercallResolve is idempotent (clears state, exits phase)".

However, `_OnOvercallResolve` does NOT explicitly check that
`S.s.phase == K.PHASE_OVERCALL` at entry (line 1186):
```
S.s.overcall = nil
S.s.phase = K.PHASE_DOUBLE
```
This is unconditional — it overwrites *any* current phase to
`PHASE_DOUBLE` if the conditions at lines 1162-1164 pass:
```
if fromSelf(sender) then return end
if not fromHost(sender) then return end
if S.s.isHost then return end
```

A v0.10.3+ host emits BOTH "!" and "?" forms. A v0.10.3 client receives:
- "!" → routes to first branch → calls `_OnOvercallResolve` → sets `phase = PHASE_DOUBLE`
- "?" → routes to second branch (4 fields detected) → also calls `_OnOvercallResolve`

Between the two arrivals, the receiver may have ALREADY transitioned past
`PHASE_DOUBLE` (e.g., received `MSG_CONTRACT` for the new Sun, processed it,
moved into `MaybeRunBot`'s post-contract `if Sun and not _SunBelAllowed
then HostFinishDeal`, advanced phase to `PHASE_PLAY` via `S.ApplyPlayPhase`).
When the second "?" arrives, `_OnOvercallResolve` *unconditionally* reverts
phase back to `PHASE_DOUBLE`.

**Repro:** v0.10.3+ host with one v0.10.3+ client. Host UPGRADES Hokm to
Sun in the overcall window. Wire sequence:
1. `! ;1 ;2 ;UPGRADE` → client sets phase=DOUBLE, clears overcall.
2. `C ;2 ;SUN;` → client `_OnContract` → `ApplyContract` → phase=DOUBLE (no change).
3. Sun-Bel-100 gate fires (via `MaybeRunBot` if isHost — but wait,
   that's host-only; on remote, `_OnContract` just sets phase=DOUBLE).
   Then host emits `MSG_DEAL play` via `HostFinishDeal`.
4. Client `_OnDealPhase("play")` → `S.ApplyPlayPhase` → phase=PLAY.
5. Host emits `MSG_TURN` — client `_OnTurn` accepts.
6. (Network reorder: the legacy "?" arrives now, late.)
7. Client `_OnOvercallResolve` → phase=DOUBLE, `s.overcall = nil`.

Now the client is stuck at PHASE_DOUBLE while the host has moved on
to PHASE_PLAY. Local UI shows the Bel button (Sun + score gate would
hide it, but the local cumulative might allow), and any subsequent
`MSG_TURN` from the host will route through `_OnTurn` → `S.ApplyTurn`
which doesn't touch phase, so phase stays at DOUBLE indefinitely.

**Impact:** rare under tight network ordering (party channel is
roughly FIFO per-sender), but cross-frame reorder exists in WoW under
contention. v0.10.3 client + v0.10.3 host, with addon-channel
reordering: client soft-locks at PHASE_DOUBLE.

**Fix shape:** make `_OnOvercallResolve` idempotent across phases —
guard with `if S.s.phase ~= K.PHASE_OVERCALL then return end`. The
state fields (`s.overcall`, `s.phase`) should only mutate when we're
actually in the overcall window. A late-arriving duplicate frame
becomes a true no-op.

```lua
function N._OnOvercallResolve(sender, takenStr, by, otype)
    if fromSelf(sender) then return end
    if not fromHost(sender) then return end
    if S.s.isHost then return end
    -- Idempotency: only mutate phase if we're STILL in the overcall window.
    if S.s.phase ~= K.PHASE_OVERCALL then return end
    S.s.overcall = nil
    S.s.phase = K.PHASE_DOUBLE
    if B.UI and B.UI.Refresh then B.UI.Refresh() end
end
```

**Severity:** HIGH — correctness violation under reordering; the
v0.10.3 dual-emit comment claims "second arrival is a benign no-op"
but it isn't.

---

### CRIT-A6 — `MSG_OVERCALL_DECISION` host branch never validates `S.s.overcall` exists
**Site:** `Net.lua:1128-1158` (`_OnOvercallDecision`)

**Finding:**
```
function N._OnOvercallDecision(sender, seat, decision)
    if not seat or not decision then return end
    if S.s.phase ~= K.PHASE_OVERCALL then return end
    if S.s.isHost then
        if fromSelf(sender) then return end
        if not authorizeSeat(seat, sender) then return end
        if S.RecordOvercallDecision and S.RecordOvercallDecision(seat, decision) then
            ...
```
Phase check is present (line 1130), but `RecordOvercallDecision` at
`State.lua:967` does:
```
if not s.overcall then return false end
```
So the call is safe. However, a hostile peer who knows the wire
format can broadcast `MSG_OVERCALL_DECISION` while
`S.s.phase == K.PHASE_OVERCALL` is true on the host (a real overcall
is in flight) but *for a different seat than their own* — `authorizeSeat`
catches that, so this is fine for self-spoof.

**Latent issue:** `_OnOvercallDecision` does NOT call
`N._SunBelAllowed` or any other Saudi-rule gate. It trusts the
decision string entirely. `S.RecordOvercallDecision` validates the
string format (UPGRADE / TAKE / WAIVE / TAKE_HOKM_<S|H|D|C>), but
doesn't validate semantic eligibility (e.g., bidder UPGRADE while
bidCard is an Ace). That gate lives in `R.CanOvercall` and is checked
at `R.ResolveOvercall` time during `S.FinalizeOvercall`. So an
ineligible decision gets recorded but discarded at resolve. This is
correct — but the wire still echoes the decision via line 1139:
```
N.SendOvercallDecision(seat, decision)
```
So all clients see "seat 2 decided UPGRADE" even when seat 2's UPGRADE
is illegal (Ace-bid bidder). The eventual resolution clears it via
`MSG_OVERCALL_RESOLVE`, but the UI banner during the 5s window shows
the spurious decision.

**Severity:** LOW — cosmetic; resolution is correct.
**Fix shape:** call `R.CanOvercall(seat, S.s.contract, S.s.overcall.bidCard)`
in the host branch BEFORE `RecordOvercallDecision`, and reject ineligible
seats' decisions silently (or echo a WAIVE).

---

## Section 2 — Host-side flow correctness

### MED-B1 — `HostStartRound` does not gate on phase; can re-deal mid-round
**Site:** `Net.lua:1833-1880` (`HostStartRound`)

**Finding:** `HostStartRound` runs unconditionally on call. It computes
`dealer`, `roundNum`, calls `S.ApplyStart`, deals new hands, and broadcasts.
There is NO phase check. The function is invoked from:
- `Slash.lua` (probably `/baloot start`)
- UI's "Next Round" button (PHASE_SCORE)
- (no direct re-entry from inside `HostStartRound` itself)

If a host clicks "Next Round" twice rapidly (or `/baloot start` during a
live round), `HostStartRound` will overwrite all in-flight state — wiping
hands, melds, tricks, contract — and re-deal. There's no guard against
double-fire.

**Repro:** host, mid-PHASE_PLAY, types `/baloot start` (or rebinds the
"Next Round" button to fire on PHASE_PLAY). Round state silently wiped.
**Impact:** data loss; remote clients see fresh `MSG_START` and
`MSG_DEAL "1"` for a round number that increments unexpectedly.
**Fix shape:** add a phase gate at the top:
```
if S.s.phase ~= K.PHASE_IDLE
   and S.s.phase ~= K.PHASE_LOBBY
   and S.s.phase ~= K.PHASE_SCORE then
    return
end
```

---

### HIGH-B2 — `HostFinishDeal` returns silently on missing `hostHands` without resetting any timers — leaves PHASE_DOUBLE/TRIPLE/FOUR/GAHWA stuck
**Site:** `Net.lua:2057-2084` (`HostFinishDeal`)

**Finding:**
```
local hands = S.HostDealRest()
if not hands then
    log("Error", "HostFinishDeal: HostDealRest returned nil ...")
    return
end
```
The `Log "Error"` is informative, but the function does not roll back
any state. Caller paths into HostFinishDeal include:

- `_OnDouble`, `_OnTriple`, `_OnFour`, `_OnGahwa` (closed escalation)
- `_OnSkipDouble/Triple/Four/Gahwa` (skip vote)
- `_OnPreempt`, `_OnPreemptPass`, `_FinalizePreempt`
- `_HostBelTimeout` (AFK skip)
- `MaybeRunBot`'s bel/triple/four/gahwa branches
- The `_HostStepBid` "contract" branch's Sun-Bel-disallowed shortcut
- `LocalDouble` / `LocalTriple` / `LocalFour` / `LocalGahwa` (closed)
- `_HostResolveOvercall` (Sun-Bel-disallowed shortcut)

If `S.s.hostHands` or `S.s.hostDeckRemainder` is nil at any of these
entry points, the round freezes. The phase is already `PHASE_DOUBLE`
or beyond, no AFK timer is armed (turnTimer was cancelled inside
`HostFinishDeal`'s callers, e.g., `LocalBid` line 1888, or the
escalation handlers don't arm one), and no `Refresh` fires.

`hostHands == nil` happens after a `S.Reset()` mid-round, after a
session restore where the snapshot didn't carry `hostHands` (resync
snapshots don't pack hostHands — only the host's own SaveSession
persists it via `TRANSIENT_FIELDS`), or after a partial host /reload
with a corrupted SavedVariables.

**Repro:** host /reload mid-PHASE_DOUBLE. PLAYER_LOGIN restore
brings back `s.contract`, `s.phase = PHASE_DOUBLE`, but if
`hostHands` was lost (pre-v0.10.6 fix; post-v0.10.6 the field is
not transient — see `State.lua:194-200`), the next `HostFinishDeal`
returns silently. Game frozen.

**Impact:** soft-lock with no recovery path. The user's only out is
`/baloot reset`.
**Fix shape:**
1. After the Log "Error", attempt recovery: if any in-flight contract
   exists, fall back to `S.s.phase = PHASE_PLAY` and `S.ApplyPlayPhase()`,
   even if cards aren't dealt — the user can `/baloot reset` from PLAY
   without confusion.
2. Alternatively, surface a user-facing chat message: `print("|cffff0000WHEREDNGN|r
   internal error: HostDealRest failed, please /baloot reset")`.

---

### HIGH-B3 — `_HostStepPlay`'s 2.2s C_Timer body re-checks `s.paused` but not `s.phase` for SCORE/GAME_END transitions during the wait
**Site:** `Net.lua:1652-1685` (`_HostStepPlay`)

**Finding:**
```
C_Timer.After(2.2, function()
    if not S.s.isHost then return end
    if S.s.paused then return end
    if S.s.phase ~= K.PHASE_PLAY then return end
    if not S.s.contract then return end
    if not S.s.trick or #S.s.trick.plays < 4 then return end
    ...
```
The phase check at `phase ~= K.PHASE_PLAY` is correct — covers
Takweesh during the window.

**However:** if a Takweesh fires DURING the 2.2s wait → phase
becomes SCORE → the timer body bails. Good. But the AFK turn timer
is still cancelled at the start of the function (line 1657 calls
`N.SendTurn` which calls `StartTurnTimer` — but the trick is
complete, so no new turn is being started; rather, the LAST play's
`_OnPlay`'s `N.CancelTurnTimer` (line 1507) cancelled it). After
the 2.2s body bails, no new timer is armed, and the next-trick
flow never starts because the function returned without calling
`N._HostStepAfterTrick`. So a Takweesh-during-the-wait correctly
short-circuits, but the host's `HostResolveTakweesh` already
handled the round-end transition. So this is fine.

**Latent issue:** if `S.s.contract` is unset between play 4 landing
and the 2.2s firing (e.g., via a race with `HostResolveSWA` in a
parallel request, which calls `S.s.lastRoundResult = nil` and
`S.s.trick = nil`), the body bails. Same outcome — the SWA-resolve
path advances the round. So the bail is correct.

**Real risk:** if a 4-play trick lands AND THEN the host is
disconnected or paused for >2.2s before the timer fires (timer
runs in real time, not paused-clock), AND then resumes... actually
the timer body checks `s.paused` so it bails. After resume, NOTHING
re-triggers the resolution — except `LocalPause`'s resume branch
at `Net.lua:2493-2496`:
```
if S.s.phase == K.PHASE_PLAY
   and S.s.trick and S.s.trick.plays
   and #S.s.trick.plays >= 4 then
    N._HostStepPlay()
end
```
which re-arms a fresh 2.2s timer. So pause-during-2.2s recovers.

**However:** PLAYER_LOGIN restore at `WHEREDNGN.lua:206-217` ALSO
re-fires `N._HostStepPlay` with a 0.5s delay if the trick has 4
plays. So /reload-during-2.2s recovers.

**Verdict:** this path is well-covered. Note the asymmetry between
LocalPause re-arm (fires `_HostStepPlay` directly, which adds
ANOTHER 2.2s) vs PLAYER_LOGIN (also fires `_HostStepPlay`). Both
add 2.2s; the wait gets re-extended. Likely intentional — gives
the user a chance to read the trick.

**Severity:** LOW — coverage is correct, but the 2.2s extension
may surprise users who expected the trick to resolve immediately
on resume. Not a bug.

---

### MED-B4 — `_HostStepBid`'s "redeal" action path doesn't validate `S.s.dealer`
**Site:** `Net.lua:1647-1649`, `Net.lua:1784-1829` (`_HostRedeal`)

**Finding:**
```
elseif action == "redeal" then
    N._HostRedeal("allpass")
```
`_HostRedeal` then computes `nextDealer = (S.s.dealer % 4) + 1`. If
`S.s.dealer` is nil (post-Reset or corrupted state), `nil % 4` errors
out. There's no guard. The bot recovery branch at line 4040 (`pcall`)
for bid decisions catches Bot errors, but `_HostStepBid`'s callers
(e.g., `_OnBid` line 867, `LocalBid` line 1892) don't pcall the call.

**Repro:** force `S.s.dealer = nil` (test harness or corrupted
SavedVariables) → call `_HostStepBid` from a bid that completes the
round → "redeal" action → `_HostRedeal` errors at line 1793.
**Impact:** one error in the Lua VM; round freezes if not caught
upstream.
**Fix shape:** add `if not S.s.dealer then return end` at the top
of `_HostRedeal`.

---

### LOW-B5 — `HostStartRound` and `HostFinishDeal` both have the v0.10.5 `B.UI.Refresh()` tail, but redeal path (`_HostRedeal`) does not refresh after the announcement broadcast
**Site:** `Net.lua:1784-1829` (`_HostRedeal`)

**Finding:** `_HostRedeal` calls `S.ApplyRedealAnnouncement(nextDealer)`
at line 1798 (which sets `s.redealing`), then `broadcast(... MSG_DEAL
;redeal;...)` at 1799 (which loops back through `_OnDealPhase("redeal")`
on the host's own loopback, calling `S.ApplyRedealAnnouncement` again),
then `print(...)`, then `B.UI.Refresh()` at 1806. Looks correct.

**However:** `_HostExecuteRedeal` (the v0.10.6 helper) at line 1750
ends at line 1781:
```
N.MaybeRunBot()
if B.UI and B.UI.Refresh then B.UI.Refresh() end
```
But the inner `S.s.phase = K.PHASE_DEAL1` at line 1775 changes phase
without triggering a Refresh until line 1781. Between phase-change and
Refresh, `S.ApplyTurn` at line 1779 fires, which internally calls
`B.Net.StartLocalWarn` via `S.ApplyTurn` at `State.lua:887`. But UI is
not refreshed in between. Net effect: `Refresh` runs once at end. Fine.

**Severity:** LOW — no bug.

---

## Section 3 — Pause/resume completeness

### HIGH-C1 — Multiple unprotected `C_Timer.After` callbacks lack pause-aware re-arm
**Site:** various (see below)

**Finding:** v0.10.3 introduced recursive re-arm for SWA timers (3 sites)
and v0.10.6 extended to redeal recovery. The audit identifies the
following timers that DO check `s.paused` and bail, but DO NOT re-arm:

1. **`Net.lua:1667`** — `_HostStepPlay`'s 2.2s wait. Bails on `paused`.
   Recovery via LocalPause resume + PLAYER_LOGIN restore (covered).

2. **`Net.lua:2715`** — `LocalSWAResp` 3s deny banner clear. Doesn't check
   `paused` at all; uses `S.s.swaDenied.caller == denyCaller` guard.
   If pause hits during the 3s, the timer fires and clears `swaDenied`
   anyway (just a UI banner). Fine.

3. **`Net.lua:2840`** — `_OnSWAResp` 3s deny banner clear. Same as #2.

4. **`Net.lua:3689`, `3761`, `3812`, `3863`, `3909`, `4040`, `4091`,
   `4144`, `4196`** — bot-decision `C_Timer.After(BOT_DELAY_*)` bodies.
   These ALL check `S.s.paused` first (e.g., line 3696: `if S.s.paused then return end`).
   If pause fires during the 1.4-1.6s delay, the bot turn is silently
   skipped. **Recovery path:** LocalPause resume calls `N.MaybeRunBot()`
   at line 2509 which redispatches the bot. ✓ covered.

5. **`Net.lua:1825`** — `_HostRedeal`'s 3s timer. Has v0.10.6 recovery
   via `LocalPause` (line 2497-2507) and PLAYER_LOGIN (`WHEREDNGN.lua:227-241`).
   ✓ covered.

6. **`Net.lua:323`** — `resyncResExpiryTimer` 30s timer. Doesn't check
   pause; just clears `expectingResyncRes`. If pause hits and resume
   fires, it should be cancelled at LocalPause. **Not** cancelled; it
   keeps counting. So a host who pauses for 30s+ after a peer asked
   for resync will lose the response window. **MED severity**.

7. **`Net.lua:814`** — `_OnDealPhase("2")` 0.5s voice cue. Doesn't check
   pause. If the round-2 announce voice plays during a paused state,
   the user might be confused. Cosmetic.

8. **`Net.lua:3477`** (StartLocalWarn's `localWarnTimer`) — no pause
   check. If pause fires between StartLocalWarn and the warnAt fire,
   the audio ping plays during pause. Cosmetic.

**Site #6** is the most concerning:
```
if C_Timer and C_Timer.NewTimer then
    resyncResExpiryTimer = C_Timer.NewTimer(30, function()
        expectingResyncRes = false
        resyncResExpiryTimer = nil
    end)
end
```

**Repro:** rejoiner sends `MSG_RESYNC_REQ`. Pause hits on rejoiner side
within 30s. Resume after 30s+. `expectingResyncRes` already false. Host's
`MSG_RESYNC_RES` (when it eventually arrives) is rejected at line 3295:
```
if not expectingResyncRes then return end
```
**Impact:** rejoiner stuck in IDLE/LOBBY state; manual `/baloot resync`
required.
**Fix shape:** in `LocalPause` resume branch, if `expectingResyncRes`
is set, re-arm a fresh 30s timer to be safe. Alternatively, store a
GetTime() anchor on the request and check it lazily on every `_OnResyncRes`.

---

### MED-C2 — Pause+resume during PHASE_OVERCALL does not re-broadcast `MSG_OVERCALL_OPEN` or refresh the 5s anchor for clients
**Site:** `Net.lua:2468-2538` (`LocalPause`), `Net.lua:1233-1249` (overcallTimerFn)

**Finding:** `overcallTimerFn` re-arms itself when paused (correct).
However, the `s.overcall.startedAt` field is only refreshed on the
HOST side (line 1241):
```
if S.s.overcall then
    S.s.overcall.startedAt = (GetTime and GetTime()) or 0
end
```
Remote clients keep their stale `startedAt` from when the window
first opened. When pause is released, the host's countdown shows
"5 seconds left" while the remote's UI countdown reads negative
(stale anchor + elapsed real time). Remote UI displays "expired" or
runs a wrong countdown.

**Repro:** host opens overcall window. Pauses 10 seconds in. Resumes.
Remote clients see countdown like "−5 seconds" or auto-hidden buttons.
**Impact:** remote humans miss their window. The host's auto-resolve
is correct, but the user experience is wrong.
**Fix shape:** in the host-side overcallTimerFn pause branch, also
broadcast a fresh `MSG_OVERCALL_OPEN` so remote clients reset their
local `s.overcall.startedAt` via `S.BeginOvercall`. (Or add a new
`MSG_OVERCALL_TICK` to push the new anchor without resetting decisions.)

---

### MED-C3 — `LocalPause` resume's redeal recovery uses `s.redealing.nextDealer` directly without re-checking `s.dealer`
**Site:** `Net.lua:2497-2507`

**Finding:**
```
elseif S.s.redealing
   and (S.s.phase == K.PHASE_DEAL2BID or S.s.phase == K.PHASE_DEAL1) then
    local nextDealer = S.s.redealing.nextDealer
    if nextDealer and C_Timer and C_Timer.After then
        ...
        C_Timer.After(3.0, function()
            if thisGen ~= B._redealGen then return end
            N._HostExecuteRedeal(nextDealer)
        end)
    end
end
```
The `nextDealer` was computed at the original `_HostRedeal` time
based on `s.dealer`. If between redeal-announcement and resume,
the dealer somehow changed (e.g., a /reload during the 3s window
restored a stale dealer), `nextDealer` may now be wrong (off by one).
Pre-v0.10.6 this couldn't happen because the timer was an inline
closure capturing `nextDealer`; v0.10.6 stores it on
`s.redealing.nextDealer` which persists across /reload.
`_HostExecuteRedeal` at line 1762 falls back to
`s.redealing.nextDealer` if not passed, so consistency is maintained.

**Verdict:** correctly designed. No bug.

---

## Section 4 — Session restore (PLAYER_LOGIN ↔ State.RestoreSession)

### HIGH-D1 — Session restore does NOT re-arm the Takweesh-pending state, but `swaRequest` is recoverable — asymmetric coverage
**Site:** `WHEREDNGN.lua:130-320`

**Finding:** PLAYER_LOGIN re-arms:
- AFK turn timer (humans only) — ✓
- Bel/Triple/Four/Gahwa AFK timers — ✓
- 2.2s `_HostStepPlay` re-fire for stuck 4-play tricks — ✓
- v0.10.6 redeal 3s — ✓
- Local pre-warn (StartLocalWarn) — ✓
- v0.9.0 PHASE_OVERCALL `_HostResolveOvercall` 5s — ✓
- v0.9.0 SWA permission auto-resolve 5s — ✓

**Missing re-arms:**
- **`expectingResyncRes` 30s window** (Net.lua:313). If a host /reload
  happens between sending RESYNC_REQ and receiving RESYNC_RES, the flag
  is on the rejoiner not the host — but on a rejoiner /reload, the flag
  is wiped (`local` to Net.lua module). After /reload, any RESYNC_RES
  is rejected. Need a fresh `SendResyncReq` at PLAYER_LOGIN.
  WHEREDNGN.lua:333+ does have `One-shot resync attempt after world load`.
  Need to verify.
- **`takweeshResult` and `swaResult` banners** are transient (not
  persisted), so they vanish on /reload. Acceptable — they're cosmetic.
- **`s.preemptEligible` and `s.pendingPreemptContract`** are NOT
  transient (per State.lua:242-249 comment). The host's PHASE_PREEMPT
  AFK timer is NOT re-armed on PLAYER_LOGIN. If the user /reloads
  mid-pre-emption window, no AFK fires for human eligible seats; bot
  eligible seats are re-dispatched via `MaybeRunBot()` at line 161.
  Human pre-empt windows soft-lock until manual action.

**Repro:** four-player game with humans 1+3 and bots 2+4. Round-2
SUN bid on Ace. Human at seat 1 is eligible to pre-empt. /reload
seat-1 client. After restore, seat 1 sees the pre-empt UI but no
60s AFK timer is armed. Seat 1 abandons. Game freezes (other
peers waiting on seat 1's decision; only the host's own AFK timer
matters but the host didn't re-arm either).

Wait — re-checking: WHEREDNGN.lua:179-197 covers DOUBLE/TRIPLE/FOUR/GAHWA
but NOT PHASE_PREEMPT. The pre-empt re-arm is missing.

**Impact:** soft-lock if a host /reloads mid-PHASE_PREEMPT with a
human eligible seat.
**Fix shape:** add to WHEREDNGN.lua:197 region:
```lua
elseif s.phase == K.PHASE_PREEMPT and s.preemptEligible then
    -- Re-arm AFK preempt-pass timer for the FIRST human-eligible seat.
    -- (MaybeRunBot at line 161 dispatches bot eligibles, but humans
    --  need StartBelTimer to arm AFK auto-pass.)
    for _, seat in ipairs(s.preemptEligible) do
        if s.seats[seat] and not s.seats[seat].isBot then
            B.Net.StartBelTimer(seat, "preempt_pass")
            break
        end
    end
end
```

**Severity:** HIGH — soft-lock + game stall in a real scenario.

---

### MED-D2 — `_HostBeginOvercallWindow`'s pause-aware `overcallTimerFn` does NOT survive PLAYER_LOGIN
**Site:** `Net.lua:1233-1250`, `WHEREDNGN.lua:280-292`

**Finding:** PLAYER_LOGIN restore arms a NEW timer at `WHEREDNGN.lua:286`:
```lua
C_Timer.After(K.OVERCALL_TIMEOUT_SEC, function()
    if not B.State.s.isHost then return end
    if B.State.s.phase ~= K.PHASE_OVERCALL then return end
    if B.State.s.paused then return end
    B.Net._HostResolveOvercall()
end)
```
This is a SINGLE-SHOT timer, NOT the recursive `overcallTimerFn`. If
the user /reloads, then pauses+resumes during the new 5s window, this
timer fires once after pause and `_HostResolveOvercall` runs without
re-arming. Pre-v0.10.3 OVERCALL had this same one-step-re-arm bug.

**Repro:** host opens overcall. /reload. Window re-opens (PLAYER_LOGIN
arms new timer with 5s). Host pauses at 3s in. The single-shot fires
at the 5s mark, sees paused, returns. Resume — no further timer. Soft-lock.

**Impact:** matches the v0.10.3 SWA pause re-arm fix scenario but for
overcall after a /reload.
**Fix shape:** make WHEREDNGN.lua's PLAYER_LOGIN overcall re-arm use
a recursive function (or, cleaner, expose `Net._ArmOvercallTimer()`
from Net.lua and call it from both `_HostBeginOvercallWindow` and
PLAYER_LOGIN restore).

---

### MED-D3 — Session restore can leave `B._redealGen` at zero while a stale generation token from a prior session is still in scope
**Site:** `Net.lua:1823-1828`, `Net.lua:2501-2506`, `WHEREDNGN.lua:232-240`

**Finding:** `B._redealGen` is on `WHEREDNGN` (the global addon table),
not in SavedVariables. It resets to nil/0 on /reload. The persisted
`s.redealing` field is restored, but no in-flight C_Timer captured
the token (timers don't survive /reload). PLAYER_LOGIN bumps
`B._redealGen = (B._redealGen or 0) + 1` and arms a fresh timer.
This is correct.

**Latent risk:** if `S.Reset` is called during the new 3s wait (e.g.,
user types `/baloot reset`), `Reset` should bump `B._redealGen` to
invalidate the pending callback. Confirm Reset does this.

<no Reset audit performed in this scope; recommend cross-check>

**Severity:** LOW — likely covered, but warrants verification.

---

## Section 5 — Authority checks consistency

### MED-E1 — Pre-v0.10.4 inconsistency between `_OnAKA` and `LocalAKA` was patched, but the `replayFlag` bypass means a forged "1" replay flag from a non-host could spoof
**Site:** `Net.lua:3159-3200` (`_OnAKA`)

**Finding:**
```
local isReplay = (replayFlag == "1") and fromHost(sender)
```
This requires BOTH `replayFlag == "1"` AND `fromHost(sender)`. Correct.

But — if `S.s.hostName` is nil (host hasn't been determined yet, e.g.,
fresh /reload before MSG_LOBBY arrives), `fromHost` returns false (line
664-666). So replay bypass requires hostName known. Defensive.

**Verdict:** correct.

---

### LOW-E2 — `_OnSWA` does not check `swaRequest` mutex, allowing fresh SWA wires to race with permission flow
**Site:** `Net.lua:2888-2906` (`_OnSWA`)

**Finding:** `_OnSWA` is the wire for direct (instant) SWA claims —
the ≤3-card path. With v0.5.17, ALL SWA flows route through
`_OnSWAReq` (permission flow), and `_OnSWA` is now legacy (no internal
caller). However, if a v0.5.16 client (no permission gate) is in the
same party, they would still send `MSG_SWA` directly. The host's
`_OnSWA` doesn't check `S.s.swaRequest` — so a `MSG_SWA` arriving
while a permission request is in flight would call `HostResolveSWA`
without resolving the permission request. The permission request's
auto-approve timer would still fire later, attempting to resolve the
already-resolved hand.

**Repro:** v0.5.17+ host, v0.5.16 client. Client's UI sends `MSG_SWA`.
Host's `_OnSWA` calls `HostResolveSWA`. If a separate permission
request was pending, both flows fire.
**Impact:** double-resolve; second `HostResolveSWA` may operate on
already-cleared `s.trick`/`s.contract` and produce wrong scoring or
errors.
**Fix shape:** add `if S.s.swaRequest and S.s.swaRequest.caller then return end`
at the top of `_OnSWA`'s host branch.

---

### MED-E3 — `LocalSWAResp` ALWAYS sends `MSG_SWA_RESP`, even when the local seat is the caller (which the early-return blocks) but the wire-frame is built before that check
**Site:** `Net.lua:2678-2727`

**Finding:** Reading carefully:
```
function N.LocalSWAResp(accept)
    if S.s.paused then return end
    local req = S.s.swaRequest
    if not req or not req.caller then return end
    if S.s.localSeat == req.caller then return end
    ...
    N.SendSWAResp(S.s.localSeat, accept, req.caller)
```
The caller-check at line 2683 returns BEFORE `SendSWAResp`. ✓ correct.

**Verdict:** no bug.

---

## Section 6 — Cross-version compat (v0.10.3 dual-emit)

### MED-F1 — Only `MSG_OVERCALL_RESOLVE` got the dual-emit treatment. Other v0.10.x wire reassignments (none) are not dual-emitted.
**Site:** `Net.lua:1085-1111` (`SendOvercallResolve`)

**Finding:** Per `Constants.lua:248-264`, only `K.MSG_OVERCALL_RESOLVE`
was reassigned ("?"→"!"). No other tag value changed in v0.10.x. So
dual-emit applies only to this one tag. Verified by reading
`Constants.lua` v0.10.7 against git history (mentioned in code comments).

The `R.2` test at `tests/test_rules.lua:1548-1564` enforces uniqueness
of every K.MSG_* value. ✓ adequate guard.

**Verdict:** no other dual-emit needed. The dual-emit will be
removable in v0.11.0 per code comment at 1100-1102.

---

### MED-F2 — `R.2` uniqueness test does not detect the `K.MSG_KICK = "K"` dead constant occupying a byte
**Site:** `tests/test_rules.lua:1548-1564`

**Finding:** R.2 iterates all `K.MSG_*` and asserts uniqueness. Since
`MSG_KICK` is the only constant with value "K", uniqueness holds. But
if a future maintainer adds `K.MSG_KICK_PLAYER = "K"` (assuming
"K" is free since they don't see a handler), the test catches it
(`MSG_KICK ↔ MSG_KICK_PLAYER`). ✓ test is correct.

But the test does NOT detect "byte value reserved by an unused
constant" — a deliberately-unused MSG name burns a byte. Acceptable.

**Verdict:** test is fit-for-purpose; suggest adding a comment or
deleting `MSG_KICK` (see LOW-A4).

---

### LOW-F3 — The dispatcher's `K.MSG_RESYNC_REQ` branch payload disambiguator hard-codes `#fields >= 4` without checking that fields[3] is numeric
**Site:** `Net.lua:633-638`

**Finding:**
```
if #fields >= 4 then
    N._OnOvercallResolve(sender, fields[2], tonumber(fields[3]),
                         fields[4])
```
A v0.10.3 host emits `?;<takenStr>;<by>;<type>` where `by` is the seat
number. If a malformed RESYNC_REQ arrives with 4+ fields somehow
(e.g., a future protocol extension that adds `?;<gameID>;<flag>;<value>`),
this branch would mis-route. Currently no such extension exists, but
the dispatcher is making an assumption based on field count alone.

**Severity:** LOW — paranoid future-proofing.
**Fix shape:** disambiguate by content: a takenStr is "0" or "1"; a
gameID is non-numeric (or hashed). Could check
`fields[2] == "0" or fields[2] == "1"` to confirm overcall-shape.

---

## Section 7 — AFK turn timer (`StartTurnTimer` / `CancelTurnTimer`)

### MED-G1 — `StartTurnTimer` is host-only-armed, but `CancelTurnTimer` is called on every client without checking `isHost`
**Site:** `Net.lua:3376-3381` (`CancelTurnTimer`), various callers

**Finding:** The `turnTimer` upvalue is shared between
`StartTurnTimer`, `_HostTurnTimeout`, `StartBelTimer`, and the recovery
paths. All of these are host-only flows in practice. `CancelTurnTimer`
fires from:
- `_OnBid` line 866 (every client receives bid → cancels)
- `_OnPlay` line 1507 (every client receives play → cancels)
- `LocalBid` line 1888 (local action)
- `LocalPlay` line 2109 (local action)
- `LocalPause` line 2475 (host pause)
- And inside `HostResolveTakweesh` line 2194, `HostResolveSWA` line 2944, etc.

On non-host clients, `turnTimer` is nil (since StartTurnTimer
returned early), so `CancelTurnTimer` is a no-op via line 3377:
```
if turnTimer then turnTimer:Cancel(); turnTimer = nil end
```
✓ no harm.

**Verdict:** correct.

---

### MED-G2 — `_HostTurnTimeout`'s SWA-defer branch does not re-arm a timer on resolve
**Site:** `Net.lua:3492-3503`

**Finding:**
```
if S.s.swaRequest and S.s.swaRequest.caller then return end
```
The `_HostTurnTimeout` body returns silently when SWA is in flight.
This is correct — don't auto-act mid-SWA-vote.

**However:** when the SWA resolves (whether valid/invalid/denied),
the turn timer is NOT re-armed. The seat whose turn was deferred by
the SWA still has a stale timer that already fired (and bailed).
After SWA resolves, if it was a DENY, the round resumes — but
`_OnSWAResp`'s deny branch at line 2855-2864 attempts to re-arm:
```
if N.StartTurnTimer
   and S.s.seats[S.s.turn] and not S.s.seats[S.s.turn].isBot
then
    N.StartTurnTimer(S.s.turn, S.s.turnKind)
end
```
✓ covered.

If the SWA was VALID, the round ends — no need for the timer.
If INVALID, round ends as Qaid penalty — same.

**Verdict:** correct.

---

### MED-G3 — `_HostTurnTimeout` for play-turn AFK auto-plays the lowest legal card by `TrickRank` — does not consider partner-coordination (AKA-relief)
**Site:** `Net.lua:3511-3556`

**Finding:**
```
if R.IsLegalPlay(c, hand, S.s.trick, S.s.contract, seat, S.s.akaCalled) then
    legal[#legal + 1] = c
end
```
Legal-play check passes `s.akaCalled`. ✓ honors AKA-receiver relief.

The "lowest by TrickRank" choice is a simple heuristic — it doesn't
match the bot's `Bot.PickPlay` strategic output. AFK humans get a
weak default play. Acceptable for v1.

**Verdict:** intentional; not a bug.

---

## Section 8 — Race conditions in C_Timer.After bodies

### HIGH-H1 — Bot Triple/Four/Gahwa `pcall` recovery branches don't re-check `S.s.contract` before `S.ApplyXxx`
**Site:** `Net.lua:3766-3742`, `3782-3798`, `3833-3849`, `3884-3892`

**Finding:** The bot bel/triple/four/gahwa pcall bodies follow this pattern:
```
if S.s.paused then return end
if S.s.phase ~= K.PHASE_TRIPLE then return end
local yes, wantOpen = false, true
if B.Bot.PickTriple then
    yes, wantOpen = B.Bot.PickTriple(bidder)
end
if yes then
    S.ApplyTriple(bidder, wantOpen)
    ...
```
The `S.ApplyTriple` etc. all start with `if not s.contract then return end`,
so a nil contract is safe. ✓

However, the recovery branch:
```
elseif S.s.phase == K.PHASE_TRIPLE then
    broadcast(("%s;%d"):format(K.MSG_SKIP_TRP, bidder))
    N.HostFinishDeal()
end
```
calls `HostFinishDeal` directly. If `S.s.hostHands` is nil at that
point (e.g., S.Reset fired between the timer arming and the body),
`HostFinishDeal` returns silently with the Log "Error" (see HIGH-B2).
The skip was broadcast but the deal-finish failed → soft-lock.

**Repro:** corner case requiring S.Reset mid-bot-decision.
**Impact:** soft-lock, requires manual reset.
**Fix shape:** before `HostFinishDeal`, validate `S.s.hostHands` and
fail loud if missing.

---

### MED-H2 — `MaybeRunBot`'s play-decision body checks `S.s.swaRequest` at fire time (line 4110), but does NOT re-check `S.s.contract` between `BOT_DELAY_PLAY` arming and fire
**Site:** `Net.lua:4091-4103`

**Finding:**
```
local ok, err = pcall(function()
    if not S.s.isHost then return end
    if S.s.paused then return end
    if S.s.phase ~= K.PHASE_PLAY then return end
    if S.s.turn ~= seat or S.s.turnKind ~= "play" then return end
    if S.s.swaRequest and S.s.swaRequest.caller then return end
    ...
```
No `S.s.contract` check. Phase=PLAY implies contract exists in steady
state, but a Reset mid-flight would null contract. `B.Bot.PickPlay` would
then crash (it indexes `c.trump` etc.).

**Severity:** LOW — Reset mid-flight is exceptional.
**Fix shape:** add `if not S.s.contract then return end`.

---

### MED-H3 — `LocalSWA`'s host-side bot auto-accept loop dispatches `_OnSWAResp("__host__", ...)` BEFORE the auto-approve C_Timer is armed; if all 4 opponents are bots, the timer becomes unnecessary but is still scheduled
**Site:** `Net.lua:2614-2664`

**Finding:**
```
if S.s.isHost then
    local callerTeam = R.TeamOf(S.s.localSeat)
    for s2 = 1, 4 do
        local info = S.s.seats[s2]
        if info and info.isBot and R.TeamOf(s2) ~= callerTeam then
            N._OnSWAResp("__host__", s2, true, S.s.localSeat)
        end
    end
    -- 5-sec auto-approve timer
    if C_Timer and C_Timer.After then
        ...
        C_Timer.After(windowSec, localSWAResolveFn)
    end
end
```
The `_OnSWAResp` calls run synchronously. After the loop, both
opponent bots have voted accept. `_OnSWAResp` at line 2879 detects
`accepts >= 2` and calls `HostResolveSWA`, which clears
`S.s.swaRequest` to nil at line 2883.

Then `C_Timer.After(windowSec, localSWAResolveFn)` is armed. When
it fires:
```
local req = S.s.swaRequest
if not req or req.caller ~= mySeat then return end
```
`swaRequest` is nil → bail. ✓ correct.

**Verdict:** wasteful but correct. 5s of scheduling overhead per
all-bot-opponent SWA.

---

## Section 9 — Cross-tag CRIT-1 sweep

### CRIT-I1 — Verified: all K.MSG_* values are unique post-v0.10.3
**Site:** `Constants.lua:180-264`, `tests/test_rules.lua:1548-1564`

Manual enumeration of all 30 K.MSG_* values:
| Tag | Value |
|---|---|
| MSG_HOST | "H" |
| MSG_JOIN | "J" |
| MSG_LOBBY | "L" |
| MSG_KICK | "K" (DEAD — see LOW-A4) |
| MSG_START | "S" |
| MSG_DEAL | "D" |
| MSG_HAND | "h" |
| MSG_BIDCARD | "b" |
| MSG_TURN | "T" |
| MSG_BID | "B" |
| MSG_CONTRACT | "C" |
| MSG_DOUBLE | "X" |
| MSG_TRIPLE | "3" |
| MSG_FOUR | "4" |
| MSG_GAHWA | "5" |
| MSG_MELD | "M" |
| MSG_PLAY | "P" |
| MSG_TRICK | "W" |
| MSG_ROUND | "R" |
| MSG_GAMEEND | "G" |
| MSG_RESYNC_REQ | "?" |
| MSG_RESYNC_RES | "=" |
| MSG_SKIP_DBL | "n" |
| MSG_SKIP_TRP | "u" |
| MSG_SKIP_FOR | "v" |
| MSG_SKIP_GHW | "w" |
| MSG_TAKWEESH | "k" |
| MSG_TAKWEESH_OUT | "z" |
| MSG_KAWESH | "a" |
| MSG_PAUSE | "p" |
| MSG_TEAMS | "t" |
| MSG_AKA | "e" |
| MSG_SWA | "Q" |
| MSG_SWA_OUT | "Z" |
| MSG_SWA_REQ | "I" |
| MSG_SWA_RESP | "O" |
| MSG_PREEMPT | "@" |
| MSG_PREEMPT_PASS | "%" |
| MSG_OVERCALL_OPEN | ">" |
| MSG_OVERCALL_DECISION | "<" |
| MSG_OVERCALL_RESOLVE | "!" |

All distinct. No collision in v0.10.7. ✓ R.2 test pin holds.

**Near-collisions (visual confusion only — not wire-level):**
- "k" (MSG_TAKWEESH, lowercase) vs "K" (MSG_KICK, uppercase) — same letter.
- "h" (MSG_HAND) vs "H" (MSG_HOST) — same.

These are case-distinct so wire-safe. Maintainability concern only.

**Verdict:** v0.10.3 fix is valid; the test pin is adequate.

---

## Section 10 — `MaybeRunBot` dispatch coverage

### HIGH-J1 — `MaybeRunBot` does NOT dispatch a play-turn bot when phase is PHASE_PLAY but turnKind is unset/wrong, even when host knows the turn should advance
**Site:** `Net.lua:4087-4092`

**Finding:**
```
if S.s.phase == K.PHASE_PLAY
   and S.s.turn and S.s.turnKind == "play" and isBotSeat(S.s.turn) then
```
All four conditions must hold. If any clears, the dispatch silently
returns at the bottom of the function (no further branch).

**Failure case:** after `_HostStepAfterTrick` at line 1738:
```
local lastWinner = S.s.tricks[#S.s.tricks].winner
S.ApplyTurn(lastWinner, "play")
N.SendTurn(lastWinner, "play")
N.MaybeRunBot()
```
`ApplyTurn` sets `s.turn=lastWinner, s.turnKind="play"`. Then
`MaybeRunBot` runs. ✓

But for the ROUND-END case (8 tricks complete, line 1688-1736),
`MaybeRunBot` is NOT called after game-end / round-end transitions.
That's correct (no turn to act).

**Possible failure:** if `ApplyTurn` set `turnKind="play"` but a
race fired `S.s.turnKind = nil` (e.g., `S.ApplyContract` clearing turn at line 1064
between trick-end and the `MaybeRunBot` call), then `MaybeRunBot`
exits silently and the turn never advances.

**Concrete repro requires Reset/race during `_HostStepAfterTrick` —
unlikely in production.**

**Verdict:** robust enough.

---

### MED-J2 — `MaybeRunBot` returns silently if `S.s.swaRequest.caller` is set, even in PHASE_DOUBLE/TRIPLE/FOUR/GAHWA
**Site:** `Net.lua:3666` (entry check)

**Finding:**
```
if S.s.swaRequest and S.s.swaRequest.caller then return end
```
This is at the top of `MaybeRunBot`, before the phase-driven dispatches.
A `swaRequest` is theoretically only valid during PHASE_PLAY. But if
a stale `swaRequest` survives a phase transition (e.g., bug elsewhere),
all bot dispatches stall.

`HostResolveTakweesh` at line 2204 explicitly nils `swaRequest`. ✓
`S.ApplyStart` at line 818 clears it. ✓
`HostResolveSWA` at line 2883 clears it. ✓
`_OnSWAResp` deny at line 2833 clears it. ✓

**Verdict:** all known clear-paths exist. Robust.

---

### MED-J3 — `MaybeRunBot`'s PHASE_OVERCALL guard returns immediately, blocking bot dispatch in any other phase that happens to coincide
**Site:** `Net.lua:3682`

**Finding:**
```
if S.s.phase == K.PHASE_OVERCALL then return end
```
This is correct — overcall decisions are recorded synchronously at
window-open. The 5s timer or all-decided early-close calls
`_HostResolveOvercall`. So `MaybeRunBot` shouldn't be doing anything
in PHASE_OVERCALL.

**Verdict:** correct.

---

### MED-J4 — `MaybeRunBot` does NOT consider PHASE_DEAL3 (skipped phase per HostFinishDeal)
**Site:** `Net.lua:4037-4038`

**Finding:** Bidding dispatch:
```
if (S.s.phase == K.PHASE_DEAL1 or S.s.phase == K.PHASE_DEAL2BID)
   and ...
```
Doesn't include `PHASE_DEAL3`. That's because per `HostFinishDeal`
line 2074, `S.ApplyPlayPhase()` is called immediately without a brief
DEAL3 transition (comment at line 2072-2073 confirms: "Skip the brief
DEAL3 phase and go straight to PLAY"). PHASE_DEAL3 only exists if a
remote client receives `MSG_DEAL "3"`, which is broadcast from where?

Searching: no `SendDealPhase("3")` in Net.lua. So PHASE_DEAL3 is
effectively dead.

**Verdict:** dead phase value. Comment at line 2072-2073 contradicts
the constant declaration in Constants.lua:151:
```
K.PHASE_DEAL3    = "deal3"       -- final 3 cards out, optional meld declarations
```
The comment claims the phase exists; the actual flow skips it. LOW
severity inconsistency.

---

## Section 11 — `HostResolveOvercall` flow

### CRIT-K1 — `HostResolveOvercall` calls `S.FinalizeOvercall()` which mutates contract; if MSG_CONTRACT broadcast fails (e.g., not in group), wire-state diverges from host-state
**Site:** `Net.lua:1272-1303` (`_HostResolveOvercall`)

**Finding:**
```
local result = S.FinalizeOvercall()
if not result then return end
N.SendOvercallResolve(result.taken, result.by, result.type)
if result.taken then
    N.SendContract(S.s.contract.bidder, S.s.contract.type,
                   S.s.contract.trump or "")
end
```
`SendContract` calls `broadcast` at line 163, which has a
`if not IsInGroup() then return end` early-out at line 39. If the
host left the group between window-open and resolve, `SendContract`
returns silently. Host's local state has the new Sun contract; remote
clients still have the original Hokm contract.

**Repro:** host opens overcall window. User clicks "Leave Party"
during the 5s window. Window resolves (timer fires). Host applies
Sun upgrade locally; broadcast no-ops. Host now plays out the round
in solo mode (no peers to broadcast to anyway, since group is empty).

**Impact:** edge case (host leaves group mid-window). No real harm
since group is empty. But if there were peers, they would never see
the new contract.

**Severity:** LOW — host leaving group during play is already chaos.

---

### MED-K2 — `_HostResolveOvercall` dispatches `MaybeRunBot` after `SendContract`, but does NOT call `B.UI.Refresh()` immediately — relies on `MaybeRunBot`'s eventual Refresh chain
**Site:** `Net.lua:1300-1303`

**Finding:**
```
N.MaybeRunBot()
if B.UI and B.UI.Refresh then B.UI.Refresh() end
```
Refresh fires at the end. ✓ correct.

But if `MaybeRunBot` returned early (e.g., human at bel-decision seat,
StartBelTimer armed, no bot fires), the user UI may show the still-pending
overcall window briefly until the next state change. Cosmetic.

**Verdict:** acceptable.

---

### MED-K3 — `LocalOvercall`'s TAKE_HOKM_<suit> branch validates suit ≠ current trump but does NOT validate that the local seat is allowed to TAKE_HOKM
**Site:** `Net.lua:1306-1349`

**Finding:**
```
if not R.CanOvercall(S.s.localSeat, S.s.contract,
                     S.s.overcall.bidCard) then
    return false
end
```
`R.CanOvercall` returns `true` for non-bidder seats. So any non-bidder
can submit `TAKE_HOKM_<suit>`. ✓ matches the v0.8 design intent.

The Bot tier gating (M3lm+ only) is enforced in `Bot.PickOvercall`,
not on the wire. A human can always submit any decision; the bot
strategy is the threshold.

**Verdict:** correct. No bug.

---

### MED-K4 — Idempotency under reconnection mid-window: `S.RecordOvercallDecision` rejects re-decisions for the same seat
**Site:** `State.lua:980` (`RecordOvercallDecision`)

**Finding:**
```
if s.overcall.decisions[seat] then return false end
```
Locks decisions on first record. ✓ correct.

**Repro of reconnect race:** seat 2 (human) decides UPGRADE → broadcast
loops back → host records → broadcast again. Seat 2 reconnects via
`_OnResyncRes`, snapshot includes overcall window state (replayed
via `MSG_OVERCALL_OPEN` + `MSG_OVERCALL_DECISION` per Net.lua:426-435).
Seat 2's local state is rebuilt with their UPGRADE decision recorded.
If they click again, `LocalOvercall` calls `S.RecordOvercallDecision`
on the host; host already has the decision → returns false → no echo.
✓ idempotent.

**Verdict:** correct.

---

## Section 12 — Architectural concerns

### LOW-L1 — `MaybeRunBot` is 638 lines and the largest function in the file
**Site:** `Net.lua:3656-4293`

**Finding:** The bot dispatcher contains 6 distinct branches (bel,
triple, four, gahwa, preempt, bid+play turn), each ~50-150 lines
including the pcall recovery logic. Code is not obviously buggy, but
the function's size and coupling to game-flow state make it hard to
reason about — especially the recovery branches that re-emit broadcasts
on error.

**Suggestion:** factor each branch into a private helper
(`N._RunBotDouble(belSeat)`, `N._RunBotTriple(bidder)`, etc.) returning
true/false to indicate dispatch occurred. The outer `MaybeRunBot`
then becomes a 30-line dispatcher.

---

### LOW-L2 — Wire-format strings hard-coded across send functions
**Site:** various (`Send*` functions)

**Finding:** Each `N.Send*` function builds a wire frame with
`("%s;%d;%s"):format(...)`. The format strings are embedded inline.
A future addition that expands a payload requires touching the sender,
the receiver dispatcher, AND the receiver handler. Three sites.

**Suggestion (defer):** introduce a `WireSpec` table keyed by tag with
field names + types; `Send` and the dispatcher both index into it.
Heavy refactor; LOW priority.

---

### LOW-L3 — Authority + phase + idempotence + replay-flag boilerplate is repeated across 20+ handlers
**Site:** `_On*` handlers throughout

**Finding:** Every host-broadcast handler has the pattern:
```
if fromSelf(sender) then return end
if not fromHost(sender) then return end
if S.s.isHost then return end
```
And every per-seat handler has:
```
if fromSelf(sender) then return end
if not seat or seat < 1 or seat > 4 then return end
if S.s.phase ~= K.PHASE_X then return end
if not authorizeSeat(seat, sender) then return end
```
Refactoring these into helpers would catch missed checks at a glance.

**Suggestion (defer):** wrap with `N._authedHostHandler(handler)` and
`N._authedSeatHandler(phase, handler)`.

---

## Section 13 — Untested paths

The test suite has solid coverage for:
- Bot decision logic (sections B-D, Q in test_state_bot.lua)
- Rules helpers (test_rules.lua sections A-Q+)
- Wire-tag uniqueness (R)
- v0.7-v0.10.5 specific regressions (sections H, I, J, K)

**Untested in tests/:**

| Area | Coverage |
|---|---|
| `_OnPlay` self-heal block (turn-mismatch + host-vouch) | Not tested |
| `_OnPlay` replay-flag bypass during resync | Not tested |
| `HostResolveOvercall` dual-emit benign-double-fire | Not tested |
| `_OnOvercallResolve` idempotency across phases | Not tested (related to MED-A5) |
| `MaybeRunBot` SWA-pending guard | Not tested |
| `HostFinishDeal` nil-hostHands recovery | Not tested |
| `_HostStepPlay` 2.2s pause+/reload re-fire | Not tested |
| `_HostExecuteRedeal` recovery from LocalPause + PLAYER_LOGIN | Not tested |
| `LocalSWAResp` deny-then-resume turn timer | Not tested |
| `_HostBeginOvercallWindow` all-bots-decide-immediately | Tested (section H) |
| Bot pcall recovery on PickBid/PickPlay/PickDouble error | Not tested |
| `expectingResyncRes` 30s window expiry + clearing | Not tested |
| `_resyncCooldown` 5s per-sender throttle | Not tested |
| `_OnSWAResp` accept-counting (need 2 accepts) | Not tested |
| `_OnPreemptPass` seat=0 "window-open" frame | Not tested |
| `MSG_TAKWEESH_OUT` outcome propagation | Not tested |
| `_HostBelTimeout` AFK auto-skip for each rung | Not tested |

These could all be added to a new section in `test_state_bot.lua`.

---

## Section 14 — Notes on prior v0.10.x changes

### v0.10.3 K.MSG_OVERCALL_RESOLVE wire-tag CRIT-1 fix
- ✓ Tag value reassigned to "!" (Constants.lua:248).
- ✓ Dual-emit at `N.SendOvercallResolve` (Net.lua:1110).
- ✓ Payload-shape disambiguator at dispatcher (Net.lua:634-639).
- **CONCERN (MED-A5):** `_OnOvercallResolve` lacks an idempotency guard
  on phase. The dual-emit comment claims benign-double-fire, but the
  unconditional phase mutation creates a real reorder hazard. **HIGH
  severity in this audit.**

### v0.10.3 SWA pause re-arm (3 sites: ~2546, ~2693, ~4067)
- ✓ All three sites verified using recursive named-function pattern.
- ✓ Sites at Net.lua:2644 (`localSWAResolveFn`), 2785 (`reqSWAResolveFn`),
  and 4177 (`botSWAResolveFn`) all re-arm self when paused.
- ✓ Pattern matches `overcallTimerFn` at line 1233.

### v0.10.4 E1 trump-AKA wire reject + E2 mid-trick lead-only gate at N._OnAKA
- ✓ E1: line 3190 `if suit == S.s.contract.trump then return end`.
- ✓ E2: line 3198 `if S.s.trick and S.s.trick.plays and #S.s.trick.plays > 0 then return end`.
- ✓ Both fire before any state mutation.

### v0.10.4 GetLegalPlays AKA-blind fix (akaCalled now passed)
- ✓ Verified at State.lua:2185 (passes 6th arg to R.IsLegalPlay).
- ✓ Same in `_HostTurnTimeout` Net.lua:3516 and bot recovery
  Net.lua:4265. All AFK / recovery paths honor AKA.

### v0.10.5 H3 tied-target tiebreak shared helper R.GameEndWinner
- ✓ Three call sites verified:
  - Net.lua:1725 (`_HostStepAfterTrick`)
  - Net.lua:2393 (`HostResolveTakweesh`)
  - Net.lua:3147 (`HostResolveSWA`)
- ✓ All three pass adapter object with `gahwaWinner`/`bidderTeam`/`bidderMade`.

### v0.10.5 Belote-cancellation team-level shared helper R.IsBeloteCancelled
- ✓ Three call sites verified:
  - Rules.lua (in R.ScoreRound)
  - Net.lua:2303 (`HostResolveTakweesh`)
  - Net.lua:3052 (`HostResolveSWA`)

### v0.10.6 HostExecuteRedeal helper extracted
- ✓ `N._HostExecuteRedeal` at Net.lua:1750.
- ✓ Idempotent — bails on missing `s.redealing`, wrong phase, or paused.
- ✓ Called from `_HostRedeal` 3s timer (line 1827), LocalPause resume
  (line 2505), and PLAYER_LOGIN restore (WHEREDNGN.lua:238).

### v0.10.6 LocalPause + PLAYER_LOGIN re-arms for redeal-stuck recovery
- ✓ LocalPause at Net.lua:2497-2507.
- ✓ PLAYER_LOGIN at WHEREDNGN.lua:227-241.
- ✓ Both use generation token `B._redealGen` for invalidation.

### v0.10.6 B.UI.Refresh() at HostStartRound + HostFinishDeal tail
- ✓ Net.lua:1879 (HostStartRound) and Net.lua:2083 (HostFinishDeal).

---

## Summary by Severity

**CRIT (1):** I1 (sweep verified — no actual collision; pin holds).

**HIGH (4):**
- A5 — `_OnOvercallResolve` lacks phase-idempotency under reorder.
- B2 — `HostFinishDeal` silent failure on nil hostHands.
- C1 (#6 — resyncResExpiryTimer) — pause-during-30s window kills resync.
- D1 — PLAYER_LOGIN missing PHASE_PREEMPT AFK re-arm.
- H1 — Bot pcall recovery doesn't validate hostHands.
- J1 — (downgraded to robust on review).

**MED (15):**
- A2 — Unknown-tag silent drop + spurious Refresh.
- A3 — `_OnPlay` self-heal lacks phase check (LOW on review).
- A6 — `_OnOvercallDecision` doesn't pre-validate `R.CanOvercall`.
- B1 — `HostStartRound` lacks phase gate.
- B4 — `_HostRedeal` doesn't validate `S.s.dealer`.
- C2 — Pause+resume during PHASE_OVERCALL doesn't refresh remote anchor.
- D2 — PLAYER_LOGIN overcall re-arm is single-shot, not pause-aware.
- E2 — `_OnSWA` doesn't check `swaRequest` mutex (legacy v0.5.16 client).
- F2 — R.2 test doesn't catch dead-MSG byte reservation (working as designed).
- F3 — Dispatcher payload disambiguator hard-codes field count.
- G2 — `_HostTurnTimeout` SWA-defer doesn't re-arm on resolve (covered by `_OnSWAResp` deny path).
- G3 — AFK auto-play uses lowest-rank, not strategic.
- H2 — `MaybeRunBot` play body doesn't re-check `S.s.contract`.
- H3 — Useless 5s timer when all opponents are bots (perf only).
- J2 — `MaybeRunBot` SWA guard is robust given clear-paths.
- J3 — `MaybeRunBot` PHASE_OVERCALL guard is correct.
- J4 — PHASE_DEAL3 is dead; constant retained.
- K2 — `_HostResolveOvercall` Refresh placement (cosmetic).

**LOW (6):**
- A1 — Authority pattern divergence (documented; not a bug).
- A4 — `K.MSG_KICK` dead constant burns "K" byte.
- B5 — `_HostExecuteRedeal` Refresh order (no bug).
- D3 — `B._redealGen` reset/Reset interaction (recommend Reset audit).
- E1 — `_OnAKA` replay flag relies on hostName known.
- F1 — Dual-emit only applies to OVERCALL_RESOLVE (correct).
- L1 — `MaybeRunBot` is 638 lines (refactor candidate).
- L2 — Inline wire-format strings (refactor candidate).
- L3 — Authority/phase boilerplate repetition (refactor candidate).
- K1 — Host leaves group mid-window (chaos already).
- K3 — `LocalOvercall` TAKE_HOKM correctness (fine).
- K4 — Reconnect-mid-window idempotency (fine).

---

## Top 3 actionable fixes

1. **HIGH-A5** — Add `if S.s.phase ~= K.PHASE_OVERCALL then return end`
   to `_OnOvercallResolve` (Net.lua:1162). 1-line change. Closes a
   reorder hazard in the dual-emit path. **Critical for v0.10.8.**

2. **HIGH-D1** — Add PHASE_PREEMPT AFK re-arm to PLAYER_LOGIN restore
   (WHEREDNGN.lua:197). 8-line change. Closes a soft-lock on
   /reload-during-pre-emption.

3. **HIGH-B2** — Add user-facing error surfacing to `HostFinishDeal`'s
   nil-hands silent return (Net.lua:2065). 5-line change. Converts a
   silent freeze into an actionable error.

---
*End of audit. 4293 lines reviewed; 11 audit areas covered; 27
findings logged.*
