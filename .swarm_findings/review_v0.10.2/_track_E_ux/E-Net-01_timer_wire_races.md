# E-Net-01 — Net.lua Timer & Wire-Tag Race Audit

**Audit version**: v0.10.2 / cross-checked against v0.10.3 wire-tag fix
**Track**: E (UX / network correctness)
**Date**: 2026-05-05
**Scope**: Bid → Play → Resolve pipeline timer races, pause integration,
resync mid-window, wire-tag-collision verification (CRIT-1 fix), pre-empt
double-trigger, AKA stale-state, host-transition, bidderTeam fix at
`Bot.lua:2143`.
**Method**: Read-only audit. No code modifications.

Cross-refs: D-RT-13 (SWA permission race), D-RT-15 (CRIT-1 wire
collision), D-RT-16 (version skew), D-RT-17 (resync edges), D-RT-32
(comprehensive pause/timer matrix).

---

## TL;DR

| # | Scenario | Verdict | Severity |
|---|---|---|---|
| 1 | Pause race during phase windows | PARTIALLY DEFENDED | MED (bot-SWA + multi-cycle drift) |
| 2 | Resync mid-window (open at pack-time, closed at apply-time) | PARTIALLY DEFENDED | LOW–MED |
| 3 | Wire-tag collision (v0.10.3 OVERCALL_RESOLVE = "!") | DEFENDED | RESOLVED (was CRIT pre-v0.10.3) |
| 3X | v0.10.2 ↔ v0.10.3 cross-version overcall soft-lock | UNDEFENDED | HIGH (mixed clusters) |
| 4 | Double-trigger of pre-empt window | DEFENDED | LOW |
| 5 | AKA banner stale-state | DEFENDED (timing) / `_OnAKA` lacks pause guard | LOW (cosmetic) |
| 6 | Bot dispatch during host transition | NOT SUPPORTED | LOW (design gap) |
| 7 | bidderTeam fix at `Bot.lua:2143` | DEFENDED | OK (no new race) |

**Net new findings**:
- **E-Net-01.2** — resync replay can leave a joiner in zombie
  PHASE_OVERCALL when the host's all-decided early-close fires between
  `packSnapshot()` and the joiner's apply. Closing
  `MSG_OVERCALL_RESOLVE`/`MSG_CONTRACT` are NOT in the replay queue.
- **E-Net-01.3-X** — v0.10.2 ↔ v0.10.3 mixed parties soft-lock when
  `MSG_OVERCALL_RESOLVE` carries `taken=false` (no follow-up
  `MSG_CONTRACT` mitigation).

---

## Scenario 1 — Pause race during phase windows

`MaybeRunBot` (`Net.lua:3552-4164`) is the host's bot-dispatch entry.
Its pause guards:

| Site | Reference |
|---|---|
| `MaybeRunBot` entry | `Net.lua:3555` |
| Bel decision pcall body | `Net.lua:3592` |
| Triple decision body | `Net.lua:3660` |
| Four decision body | `Net.lua:3711` |
| Gahwa decision body | `Net.lua:3762` |
| Pre-empt decision body | `Net.lua:3816` |
| Bid decision body | `Net.lua:3941` |
| Play decision body | `Net.lua:3995` |

Every dispatched bot timer respects `S.s.paused` at fire time.
`StartLocalWarn` (`Net.lua:3305-3374`) bails on `S.s.paused` at entry
(line 3307).

`LocalPause(false)` resume branch at `Net.lua:2410-2447` re-arms (a)
`MaybeRunBot()`, (b) `StartTurnTimer` for the active turn, (c)
`_HostStepPlay` for a stuck 4-card trick, and (d) `StartLocalWarn` for
the matching phase. Bel/Triple/Four/Gahwa/Pre-empt re-pump piggybacks
on `MaybeRunBot`'s phase-driven dispatch.

### What pauses CORRECTLY

- Turn AFK timer (60s): cancelled on pause via `N.CancelTurnTimer`;
  resume re-arms fresh.
- `_HostStepPlay` 2.2s trick resolution (`Net.lua:1629`): bails on
  pause; resume detects the 4-play state and re-fires.
- `_HostBelTimeout` (`Net.lua:3473`): bails on pause; resume re-fires
  via MaybeRunBot.
- OVERCALL 5s (`Net.lua:1195-1212`): pause-aware re-arm — if timer
  body fires during pause, schedules a fresh 5s and resets
  `overcall.startedAt` so UI countdown re-anchors.

### Gaps

#### 1.A — Bot-fired SWA timer (Net.lua:4059-4067) — MED

```lua
C_Timer.After(K.SWA_TIMEOUT_SEC or 5, function()
    if not S.s.isHost then return end
    if S.s.paused then return end          -- BARE EXIT, no re-arm
    local req = S.s.swaRequest
    if not req or req.caller ~= seat then return end
    if S.s.phase ~= K.PHASE_PLAY then return end
    S.s.swaRequest = nil
    N.HostResolveSWA(seat, hand)
end)
```

**Repro**:
1. Bot decides to SWA at `t=0`; timer scheduled for `t=5`.
2. Host pauses at `t=2`.
3. At `t=5` body fires, sees `S.s.paused == true`, returns silently.
4. Host resumes at `t=10`. `LocalPause(false)` does NOT iterate
   `S.s.swaRequest`. Only `MaybeRunBot()` runs and bails at
   `Net.lua:3562` because `swaRequest.caller` is set.

**Effect**: `swaRequest` hangs forever; SWA banner stuck. Recovery
only via Takweesh, /reset, or another round-end path.

Confirmed RT-13.4 / RT-32.2c. **Fix sketch**: copy the pause-aware
re-arm pattern from `LocalSWA` (`Net.lua:2546-2569`), or — better —
add an SWA re-pump to `LocalPause(false)` covering all 3 arming
sites + the M2 PLAYER_LOGIN restore.

#### 1.B — Multi-cycle pause within one window — LOW

Both `LocalSWA` and `_OnSWAReq` arm a one-shot inner re-arm timer when
the outer timer fires during a pause. The inner re-arm bare-exits on
pause-at-fire. Sequence:

```
t=0 outer timer armed
t=2 pause
t=5 outer fires, pause=true, schedules inner for t=10
t=6 resume
t=8 pause again
t=10 inner fires, pause=true, silent return
swaRequest hangs.
```

Same shape in OVERCALL (`Net.lua:1195-1212`). Confirmed RT-32.13.
Fix as 1.A.

#### 1.C — `HostResolveSWA` semi-permeable — LOW

`HostResolveSWA` (`Net.lua:2862+`) lacks an `S.s.paused` check. When
both opponents accept (synchronous bot accepts at `_OnSWAReq` body),
`accepts >= 2` at `Net.lua:2800-2806` calls `HostResolveSWA` directly
through pause. Confirmed RT-13.11. Fix: guard at entry, or in
`_OnSWAResp` accept-path.

---

## Scenario 2 — Resync mid-window

Late joiner sends `MSG_RESYNC_REQ` (now `"?"` after v0.10.3 freed it).
Host runs `_OnResyncReq` (`Net.lua:3109-3170`):

1. Authorize sender (gameID + roster + 5-sec cooldown).
2. `N.SendResyncRes(sender, gameID)` (`Net.lua:386-465`):
   - Pack snapshot synchronously via `packSnapshot()`.
   - Whisper MSG_BIDCARD, MSG_MELD (winning + losing teams),
     MSG_PREEMPT_PASS;0 (window-open frame), MSG_OVERCALL_OPEN +
     MSG_OVERCALL_DECISION × n, MSG_TRICK history, in-flight MSG_PLAY,
     MSG_AKA, then MSG_HAND.

`packSnapshot` reads `S.s.*` synchronously. Replay frames whisper
separately. Between pack and apply, host state can mutate.

### 2.A — OVERCALL closed between pack and apply (E-Net-01.2 NEW) — LOW–MED

**Repro**:
1. PHASE_OVERCALL open with all 4 bots. `_HostBeginOvercallWindow`
   queues 4 decisions synchronously (`Net.lua:1173-1182`). Each
   decision runs `_OvercallAllDecided` on completion (`Net.lua:1109`)
   which fires `_HostResolveOvercall` synchronously — advancing phase
   to PHASE_DOUBLE.
2. A late joiner's `MSG_RESYNC_REQ` arrives mid-flight, BEFORE the
   4th bot decision triggers the all-decided check.
3. `_OnResyncReq` packs the snapshot at this exact frame: phase =
   "overcall", `S.s.overcall` non-nil, 3 of 4 decisions recorded.
4. Bot 4's decision lands → `_HostResolveOvercall` runs → phase to
   PHASE_DOUBLE. The host broadcasts `MSG_OVERCALL_RESOLVE` and
   (if `taken`) `MSG_CONTRACT` to the addon channel — but the late
   joiner missed those broadcasts (joined too late on the channel).
5. The whispered replay frames in `SendResyncRes` do NOT include a
   closing `MSG_OVERCALL_RESOLVE`. The receiver's
   `ApplyResyncSnapshot` lands at PHASE_OVERCALL with
   `s.overcall` populated. Subsequent whispered
   `MSG_OVERCALL_OPEN`/`MSG_OVERCALL_DECISION × 3` reaffirm the open
   window state.
6. **Receiver soft-locks at PHASE_OVERCALL.** `_OvercallAllDecided`
   is host-only logic. The next legitimate non-host wire frame that
   advances phase is `MSG_TURN` for `play` kind, but `_OnTurn`
   doesn't change phase. `_OnPlay` checks `phase != PHASE_PLAY` and
   bails.

**Mitigation**: only if the resolve was `taken=true`, the missed
`MSG_CONTRACT` mitigation would have advanced phase via
`S.ApplyContract`. But `taken=false` (no upgrade/take) is the common
case → no mitigation.

**Severity**: LOW–MED. Window is microseconds (single-frame's worth
between bot-decision return and synchronous resolve). Realistic only
under host CPU saturation.

**Fix sketch**: in `SendResyncRes`, after `packSnapshot` and after
queueing replay frames, re-check `S.s.phase`; if it advanced past
PHASE_OVERCALL, also whisper a synthetic `MSG_OVERCALL_RESOLVE` and
the current `MSG_CONTRACT`. Or: pack snapshot AFTER yielding to the
event queue (no `C_Timer.After(0, ...)` is universally available;
practical alternative is to make the resolve side broadcast a
follow-up `MSG_TURN`/`MSG_CONTRACT` always — already does for
`taken=true` but not for `taken=false`).

### 2.B — Pre-empt mid-window resync — PASS

`SendResyncRes` (`Net.lua:416-419`) replays
`MSG_PREEMPT_PASS;0;<eligCsv>` when host is at PHASE_PREEMPT.
Receiver's `_OnPreemptPass(sender, 0, eligCsv)`
(`Net.lua:1003-1018`) special-cases seat=0 explicitly and seeds
`s.preemptEligible` + arms `StartLocalWarn`. Idempotent re-validation
in `_OnPreempt` (`Net.lua:967-971`). PASS.

### 2.C — AKA banner during resync replay — PASS (cosmetic)

`SendResyncRes` line 461-464 replays `MSG_AKA;...;1` when
`s.akaCalled` is set. Replay flag bypasses authorize. If host's
trick advanced between pack and apply, the joiner's banner shows the
prior trick's AKA briefly. Next `MSG_TRICK`'s `S.ApplyTrickEnd`
(`State.lua:1327`) clears it. Cosmetic.

---

## Scenario 3 — Wire-tag collision (v0.10.3 fix verification)

### Verification

`Constants.lua:181` — `K.MSG_RESYNC_REQ = "?"` (unchanged).
`Constants.lua:229` — `K.MSG_OVERCALL_RESOLVE = "!"` (changed from
`"?"`). Comment block at `Constants.lua:236-245` documents the v0.10.3
wire-tag fix and pre-fix CRIT-1 lineage.

`Net.lua:543` — `elseif tag == K.MSG_OVERCALL_RESOLVE then` →
`_OnOvercallResolve`.
`Net.lua:620` — `elseif tag == K.MSG_RESYNC_REQ then` →
`_OnResyncReq`.

Dispatch order matters: OVERCALL_RESOLVE at 543 PRECEDES RESYNC_REQ
at 620. With both = `"?"` in v0.10.2, every `"?"` matched 543 first
→ `_OnResyncReq` dead. With `"!"` in v0.10.3, the two cases are
distinct.

### All call sites use the constant

```
Net.lua:317   broadcast(("%s;%s"):format(K.MSG_RESYNC_REQ, gameID or ""))
Net.lua:543   elseif tag == K.MSG_OVERCALL_RESOLVE then
Net.lua:620   elseif tag == K.MSG_RESYNC_REQ then
Net.lua:1067-1072  N.SendOvercallResolve uses K.MSG_OVERCALL_RESOLVE
Net.lua:1246  via N.SendOvercallResolve in _HostResolveOvercall
```

`grep '"!"\|"?"' Net.lua` — verified no hardcoded `"?"` or `"!"`
literals in dispatch code. PASS.

### `_OnResyncReq` reachable

Late joiner's `N.SendResyncReq(gameID)` → `"?;<gameID>"` →
`HandleMessage` splits, `tag = "?"` → `Net.lua:620` fires
`_OnResyncReq(sender, fields[2])` → roster check + cooldown gate +
`SendResyncRes` whisper. PASS.

Pre-v0.10.3, the `"?"` matched line 543 first as
`_OnOvercallResolve(sender, "<gameID>", nil, nil)`. The
`fromHost(sender)` gate at line 1125 rejected non-host senders so the
function bailed — but `_OnResyncReq` was never invoked. Late joiners
stayed soft-locked indefinitely (until `expectingResyncRes` 30s
expiry).

### `_HostResolveOvercall` and downstream sends

`_HostResolveOvercall` (`Net.lua:1234-1265`) calls
`N.SendOvercallResolve(...)` at line 1246 (uses `K.MSG_OVERCALL_RESOLVE`
= `"!"`), then `N.SendContract(...)` at line 1252 (uses
`K.MSG_CONTRACT` = `"C"`). Both via constants. PASS.

### Cross-version compatibility — E-Net-01.3-X (HIGH)

**v0.10.3 host + v0.10.2 client**: v0.10.3 host emits
`MSG_OVERCALL_RESOLVE` as `"!"`. v0.10.2 client's
`K.MSG_OVERCALL_RESOLVE` = `"?"` so `"!"` matches NOTHING in the
dispatcher → silent drop. v0.10.2 client stays at PHASE_OVERCALL with
populated `s.overcall`.

**v0.10.2 host + v0.10.3 client**: v0.10.2 host emits
`MSG_OVERCALL_RESOLVE` as `"?"`. v0.10.3 client's dispatcher tries
line 543 (`"!"` != `"?"`) → fall-through to line 620 (`"?"` ==
`K.MSG_RESYNC_REQ`) → routes to `_OnResyncReq`, which bails
immediately at `Net.lua:3111`: `if not S.s.isHost then return end`.
v0.10.3 client stays at PHASE_OVERCALL.

**Mitigation**: only `taken=true` triggers a follow-up `MSG_CONTRACT`
which `_OnContract` applies via `S.ApplyContract` (advances phase to
PHASE_DOUBLE). For `taken=false`, no follow-up — soft-locked.

**Severity**: HIGH for mixed-version parties. Both directions produce
identical soft-lock shape.

**Fix sketch**: gate party formation on addon version equality at
`_OnLobby` / `_OnHost`. The `K.GetAddonVersion` info is currently
informational and doesn't refuse cross-version lobbies. Or a weaker
patch: have v0.10.3 hosts dual-emit `"?"` AND `"!"` for one cycle so
v0.10.2 clients can keep up.

**Documentation gap**: `Constants.lua:236-245` documents the v0.10.3
fix but does NOT warn about cross-version compatibility. Recommend
amending.

### Verdict (Scenario 3)

Wire-tag fix DEFENDED in homogeneous v0.10.3 cluster. **HIGH
cross-version risk** on `taken=false` overcall resolves.

---

## Scenario 4 — Double-trigger of pre-empt window — DEFENDED

PHASE_PREEMPT entered exclusively at `Net.lua:1550` inside
`_HostStepBid`'s `action == "contract"` branch:

```lua
if enablePreempt and S.s.bidRound == 2
   and payload.type == K.BID_SUN and bidRank == "A" then
    local elig = S.PreemptEligibleSeats(...)
    if elig and #elig > 0 then
        S.s.preemptEligible = elig
        S.s.pendingPreemptContract = { ... }
        S.s.phase = K.PHASE_PREEMPT
        broadcast(("%s;0;%s"):format(K.MSG_PREEMPT_PASS, eligCsv))
        N.MaybeRunBot()
        return
    end
end
```

Exit paths: `_OnPreempt` claim → `S.ApplyContract` (advances phase),
`_OnPreemptPass` final pass → `_FinalizePreempt` → `S.ApplyContract`,
or AFK timeout via `_HostBelTimeout` "preempt_pass".

**Re-entry analysis**: `_HostStepBid` is invoked only from `_OnBid`
(`Net.lua:849`). Re-entry would require a 2nd round-2 SUN-Ace bid.
After `S.ApplyContract`, `S.HostAdvanceBidding()` no longer returns
`"contract"` for new bids — bidding is closed. Cannot re-enter.

**Malformed-sequence probe**: peer sends MSG_BID frames; `_OnBid`
authorizes the seat against sender, validates, and only proceeds on
successful `S.ApplyBid` which itself rejects bids past contract. No
injection vector.

**Internal idempotency**: `S.s.phase == K.PHASE_PREEMPT` is set
BEFORE the broadcast at line 1561; `S.s.bids` saturation prevents
repeat `"contract"` returns from `HostAdvanceBidding`.

**Latent gap (LOW)**: if the host crashes between line 1545 (state
write) and line 1561 (broadcast), state is set but no peer sees the
window. /reload's M2 SaveSession restores `s.preemptEligible` (NOT in
TRANSIENT_FIELDS), but the window-open frame is not rebroadcast.
RT-17.11 confirms `MaybeRunBot`'s preempt branch covers transitively
for humans (AFK timer) and bots (direct dispatch); joiners don't
re-open. LOW.

---

## Scenario 5 — AKA banner stale-state — DEFENDED (timing) / `_OnAKA` no-pause-guard (LOW cosmetic)

`s.akaCalled` is set by `S.ApplyAKA(seat, suit)` and cleared in
`S.ApplyTrickEnd` (`State.lua:1327`). **There is NO timer on the AKA
banner.** Lifetime = current trick.

`Bot.PickAKA` fires at lead time only (`Net.lua:4096-4102`). The
banner persists for the rest of THAT trick. Subsequent partner/
opponent plays in the same trick are correctly accompanied by the
banner.

**Path 1 — pause mid-trick**: partial trick frozen with banner
showing. Resume re-fires `_HostStepPlay` only when the trick was
complete (4 plays); for 1-3 plays, `MaybeRunBot` re-dispatches via
the active turn. Banner stays correct.

**Path 2 — Takweesh during AKA**: false-AKA detection at
`State.lua:1238-1265` flags illegality; `LocalTakweesh` →
`HostResolveTakweesh` → `S.ApplyRoundEnd` → phase=PHASE_SCORE.
`s.akaCalled` not explicitly cleared by `ApplyRoundEnd`; cleared on
next round's reset (`State.lua:110, 524`). Banner is rendered
PHASE_PLAY-only by UI — cosmetic non-issue.

**Path 3 — `_OnAKA` lacks pause guard (RT-32.6)**: peer broadcasts
MSG_AKA mid-pause; `_OnAKA` (`Net.lua:3075-3096`) checks phase,
contract type, replay flag, but NOT `S.s.paused`. `S.ApplyAKA` writes
`s.akaCalled` + voice cue + UI refresh runs.

**Severity**: cosmetic only. No state corruption.

**Fix sketch**: add `if S.s.paused then return end` at `Net.lua:3076`
for consistency with peer handlers.

---

## Scenario 6 — Bot dispatch ordering during host transition — NOT SUPPORTED

WHEREDNGN does NOT support host migration. `grep` for
`PromoteToHost|hostMigration|migrateHost|HostPromote` returns
nothing. `S.s.hostName` is set ONCE at `_OnLobby` (`Net.lua:753-756`)
and stays bound to whoever broadcast `MSG_LOBBY` first.

When the actual host disconnects:
- `S.s.hostName` is still the old name. Peers' `_OnPause`,
  `_OnResyncRes`, `_OnContract`, etc. all gate on `fromHost(sender)`
  (`Net.lua:646`). No new wire frames are accepted from a new
  "primary" peer.
- OVERCALL 5s timer was armed on old host's `_HostBeginOvercallWindow`
  via `C_Timer.After`. The C_Timer object dies with the addon
  process. Survivors stuck in PHASE_OVERCALL with no resolve.
- Bot-dispatch timers were armed on old host only. Survivors don't
  drive bots (they lack `hostHands` and `isHost`).
- Pre-empt: only old host had `pendingPreemptContract`; survivors
  have it from `MSG_PREEMPT_PASS;0;...` open-frame, but
  `_FinalizePreempt` is host-only.

**Severity**: LOW. Known design gap. The intended recovery is for the
new lobby owner to call `/baloot reset` and start fresh.

**Verdict**: NOT SUPPORTED. Document as design limitation. No code
change recommended unless host-migration is on the roadmap.

---

## Scenario 7 — bidderTeam fix at Bot.lua:2143 — DEFENDED (no new race)

Code at `Bot.lua:2134-2159`:

```lua
if Bot.IsM3lm() and contract.type == K.BID_HOKM
   and contract.trump and contract.bidder then    -- bidder gate
    -- v0.10.3 audit (B-Bot-08, HIGH): pre-v0.10.3 the loop body
    -- referenced an undefined `bidderTeam`...
    local bidderTeam = R.TeamOf(contract.bidder)
    local conservativeOpp = false
    for s2 = 1, 4 do
        if R.TeamOf(s2) ~= bidderTeam
           and styleTrumpTempo(s2) == -1 then
            conservativeOpp = true; break
        end
    end
    -- ...
end
```

The outer gate `and contract.bidder then` is the safety boundary.
`R.TeamOf(contract.bidder)` is only computed when `contract.bidder`
is non-nil. **The fix does not introduce a new race when
`contract.bidder` is nil** — entire block skipped.

**When can `contract.bidder` be nil at `Bot.PickPlay` entry?**
- `PickPlay` is called from `MaybeRunBot`'s play branch
  (`Net.lua:4091`), gated on `S.s.phase == K.PHASE_PLAY`
  (line 3996). Phase only advances to PHASE_PLAY after
  `S.ApplyContract` sets `S.s.contract.bidder`. By the time
  `PickPlay` runs from a play-dispatch, `contract.bidder` is
  invariant non-nil.
- AFK timeout recovery path at `Net.lua:3417-3420` calls its own
  legal-card scan, NOT `PickPlay`. No path to `pickLead` /
  `pickFollow` from there.
- Test harness `tests/run.py` may invoke `PickPlay` directly
  without a contract — but this is test-only, not production.

**Pre-existing latent (orthogonal to this fix)**: `pickLead` at
`Bot.lua:1714` has unconditional `local isBidderTeam = (myTeam ==
R.TeamOf(contract.bidder))`. `R.TeamOf(nil)` returns `"B"` (`nil ~=
1 and nil ~= 3`), so `isBidderTeam` = `(myTeam == "B")`. Wrong but
non-crashing. NOT introduced by the v0.10.3 fix.

**Verdict**: PASS. Fix is correct, tightens an N=1 latent
undefined-`bidderTeam` no-op, and adds no race surface.

---

## Cross-cutting summary

| Site | Pause guard | Re-arm on pause | Resume re-fire | Wire-tag |
|---|---|---|---|---|
| OVERCALL 5s (`Net.lua:1195`) | YES | YES (fresh 5s) | NO direct (relies on next phase) | `"!"` (v0.10.3) |
| `_HostResolveOvercall` (`1234`) | NO | N/A | N/A | sends `"!"` |
| Bot-fired SWA timer (`4059`) | YES (bare) | NO | NO | — |
| LocalSWA timer (`2546`) | YES (re-arm) | YES (one-shot) | NO | — |
| `_OnSWAReq` timer (`2693`) | YES (re-arm) | YES (one-shot) | NO | — |
| `HostResolveSWA` (`2862`) | NO | N/A | N/A | — |
| `_HostStepPlay` 2.2s (`1629`) | YES | NO | YES (LocalPause(false)) | — |
| Turn 60s timer (`3376`) | YES (gate) | NO | YES (resume re-arm) | — |
| Bel/Triple/Four/Gahwa AFK (`3461`) | YES | NO | YES (via MaybeRunBot) | — |
| Pre-empt AFK (`3493`) | YES | NO | YES (via MaybeRunBot) | — |
| `_OnAKA` (`3075`) | NO | N/A | N/A | `"e"` |
| `_OnPause` (`2452`) | host gate | N/A | N/A | `"p"` |
| `_OnResyncReq` (`3109`) | host-only | N/A | N/A | `"?"` (now reachable) |
| `_OnOvercallResolve` (`1123`) | non-host only | N/A | N/A | `"!"` |

---

## Recommendations (ordered by severity)

1. **HIGH**: gate party formation on addon version equality to avoid
   v0.10.2 ↔ v0.10.3 mixed-cluster soft-lock at OVERCALL_RESOLVE
   `taken=false`.
2. **MED**: add an SWA-timer re-pump at `LocalPause(false)` resume
   branch (`Net.lua:2410-2447`) covering bot-fired path
   (`Net.lua:4059`), rapid pause-toggle (RT-32.13), and PLAYER_LOGIN
   restore (`WHEREDNGN.lua:270-292`).
3. **MED**: amend `Constants.lua:236-245` to document the v0.10.2 ↔
   v0.10.3 cross-version compatibility caveat.
4. **LOW–MED**: `SendResyncRes` should re-check phase after packing
   the snapshot and emit a closing `MSG_OVERCALL_RESOLVE` /
   `MSG_CONTRACT` if host's phase advanced between pack-and-whisper.
5. **LOW**: add `S.s.paused` guard at `HostResolveSWA` entry
   (RT-13.11) AND in `_OnSWAResp` `accepts >= 2` branch.
6. **LOW (cosmetic)**: add `S.s.paused` guard at `_OnAKA` entry
   (RT-32.6 / E-Net-01.5).
7. **INFO**: surface a UI message when `S.s.hostName` peer
   disconnects mid-game (avoid silent soft-lock).

---

## Confidence

**HIGH** on:
- Wire-tag fix verification (Scenario 3) — every call site cross-
  checked against the constants; both dispatcher branches reachable.
- `Bot.lua:2143` fix safety (Scenario 7) — gated on `contract.bidder`
  non-nil; no new race surface.
- Pre-empt single-trigger guarantee (Scenario 4) — phase mutation
  precedes broadcast; contract-set blocks re-entry.
- Cross-version compatibility soft-lock (Scenario 3X) — both
  directions verified by dispatcher walk.

**MEDIUM** on:
- Resync mid-OVERCALL race (Scenario 2.A) — depends on host CPU
  scheduling between bot decisions and synchronous resolve. Verified
  the absence of closing-frame replay in `SendResyncRes` by full
  read of lines 386-465; couldn't empirically confirm timing.
- Bot dispatch + host transition (Scenario 6) — claim is "no formal
  migration" verified by absence of code, not by a designed gap.

---

## Files referenced

- `C:\CLAUDE\WHEREDNGN\Constants.lua:181, 229, 236-245`
- `C:\CLAUDE\WHEREDNGN\Net.lua`:
  - 300-385 (resync senders, `expectingResyncRes`, packSnapshot)
  - 386-465 (SendResyncRes + replay queue)
  - 489-628 (HandleMessage dispatcher; line 543 OVERCALL,
    line 620 RESYNC)
  - 821-961 (_OnContract, _OnDouble, _OnTriple, _OnFour, _OnGahwa)
  - 962-1052 (_OnPreempt / _OnPreemptPass / _FinalizePreempt)
  - 1056-1265 (overcall send/receive/resolve, _HostBeginOvercallWindow)
  - 1503-1612 (_HostStepBid, contract → preempt vs overcall branch)
  - 1614-1719 (_HostStepPlay, _HostStepAfterTrick, 2.2s trick resolve)
  - 2401-2467 (LocalPause / _OnPause)
  - 2473-2733 (LocalSWA / _OnSWAReq pause-aware re-arm pattern)
  - 2735-2807 (_OnSWAResp accept/deny)
  - 3075-3096 (_OnAKA)
  - 3098-3220 (_OnResyncReq, _OnResyncRes)
  - 3270-3508 (turn / Bel timer machinery + AFK timeouts)
  - 3552-4164 (MaybeRunBot, all phase-driven branches with pause
    guards, bot-fired SWA at 4040-4075)
- `C:\CLAUDE\WHEREDNGN\State.lua`:
  - 100-130 (initState, ApplyPause)
  - 388-540 (ApplyResyncSnapshot wire layout + transient cleanup)
  - 1300-1340 (ApplyTrickEnd; aka clear at 1327)
- `C:\CLAUDE\WHEREDNGN\Bot.lua`:
  - 1703-1796 (pickLead entry; isBidderTeam at 1714)
  - 2134-2159 (v0.10.3 bidderTeam local fix, B-Bot-08)
  - 3403-3433 (Bot.PickPlay entry, BotMaster delegation)
- `C:\CLAUDE\WHEREDNGN\WHEREDNGN.lua:130-313` (PLAYER_LOGIN
  re-arms; 250-269 OVERCALL re-arm, 270-292 SWA re-arm)
- Cross-refs: `_track_D_redteam/D-RT-13`, D-RT-15, D-RT-17, D-RT-32.
