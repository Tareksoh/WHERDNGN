# B-Net-08 — Resync / Replay Wire-Path Deep Audit

Targets:
- `C:/CLAUDE/WHEREDNGN/Net.lua` — wire dispatch, `_OnResyncReq`,
  `_OnResyncRes`, `_OnOvercallResolve`, replay block
- `C:/CLAUDE/WHEREDNGN/Constants.lua` — `K.MSG_*` tag table
- `C:/CLAUDE/WHEREDNGN/State.lua` — `S.ApplyResyncSnapshot`,
  `S.RestoreSession`, transient-fields list
- `C:/CLAUDE/WHEREDNGN/WHEREDNGN.lua` — `maybeRequestResync`,
  PLAYER_LOGIN host re-arm

Cross-refs read first:
- `audit_v0.9.0/15_v091_l5_resync.md` (L5 resync-window guard)
- `audit_v0.9.0/52_telemetry_reload.md` (no telemetry on the wire)
- `audit_v0.9.0/05_m1_m2_timer_rearm.md` (M1/M2 timer pause-aware)
- `_track_D_redteam/D-RT-17_resync_edges.md` (13 edge probes)

---

## CRIT-1 — `MSG_RESYNC_REQ` UNREACHABLE (wire-tag collision with `MSG_OVERCALL_RESOLVE`)

**Severity: CRITICAL.** Resync request never reaches its handler when
overcall is enabled (default). Reload-rejoin completely broken.

### Evidence — both tags share `"?"`

`C:/CLAUDE/WHEREDNGN/Constants.lua:181`:
```
K.MSG_RESYNC_REQ = "?" -- request state from host
```

`C:/CLAUDE/WHEREDNGN/Constants.lua:229`:
```
K.MSG_OVERCALL_RESOLVE  = "?"  -- host announces the overcall window
```

Both literally equal `"?"`. Confirmed by direct read of the constants
table.

### Evidence — dispatch order makes `_OnResyncReq` UNREACHABLE

The dispatch chain in `N.HandleMessage` is a long `if/elseif`. The
FIRST match wins. `MSG_OVERCALL_RESOLVE` is checked at line **543**;
`MSG_RESYNC_REQ` is checked at line **620**.

`C:/CLAUDE/WHEREDNGN/Net.lua:543-547`:
```
elseif tag == K.MSG_OVERCALL_RESOLVE then
    -- v0.7 Sun-overcall: window closed; result follows.
    -- Payload: taken(0|1);by(seat or 0);type.
    N._OnOvercallResolve(sender, fields[2], tonumber(fields[3]),
                         fields[4])
```

`C:/CLAUDE/WHEREDNGN/Net.lua:620-622`:
```
elseif tag == K.MSG_RESYNC_REQ then
    N._OnResyncReq(sender, fields[2])
elseif tag == K.MSG_RESYNC_RES then
```

Because both K-constants resolve to the literal `"?"`, every inbound
`"?"` message dispatches to `_OnOvercallResolve` and the elseif chain
exits without ever testing `MSG_RESYNC_REQ`. **`_OnResyncReq` is dead
code**, even though it has its own implementation at `Net.lua:3109`.

### Repro

1. Host runs a normal multi-human game (default config — overcall is
   enabled; `WHEREDNGNDB.allowSunOvercall` is not `false`).
2. Non-host peer types `/reload` mid-trick.
3. On PLAYER_ENTERING_WORLD the rejoiner fires
   `WHEREDNGN.lua:110-111 → N.SendResyncReq(id)` which broadcasts
   `"?;<gameID>"`.
4. The host receives the broadcast (loopback comment at `Net.lua:13`:
   "SendAddonMessage delivers to the sender too").
5. Host's dispatch hits `_OnOvercallResolve` first (line 543), sees
   `not fromHost(sender)` (the sender is the non-host rejoiner) →
   **early return at `Net.lua:1125`**.
6. The elseif chain has consumed the message; `_OnResyncReq` never
   runs. **The host never sends a snapshot.** The rejoiner's local
   state remains stale; the 30-s `expectingResyncRes` window expires
   silently.

### Provenance

`MSG_RESYNC_REQ = "?"` was introduced when resync existed (early
version). `MSG_OVERCALL_RESOLVE = "?"` was added in v0.7.0. So the
collision exists in **every release v0.7.0+**. Pre-v0.7.0 was clean.
The audit prompt's claim "Exists in v0.7.0+" is correct.

### Reachability under overcall-disabled installs

If the user has set `WHEREDNGNDB.allowSunOvercall = false`,
`_HostBeginOvercallWindow` returns false at `Net.lua:1164-1166` so the
host NEVER broadcasts `MSG_OVERCALL_RESOLVE`. But that does NOT fix
the dispatch collision: the receive-side dispatch tests on tag, not on
whether the sender is the host. Any `"?"` payload still routes
`_OnOvercallResolve` first. **Disabling overcall does not unmask
`_OnResyncReq`.** The handler stays unreachable for all installs.

### Fix surface (do NOT modify; recommendation)

Change `K.MSG_RESYNC_REQ` to a unique tag (e.g. `"q"` — currently
unused). Audit also recommends: add a wire-tag uniqueness assert at
addon-load that walks the `K.MSG_*` table and panics on duplicates.

---

## CRIT-2 — `_OnOvercallResolve` corrupts state when fed a `MSG_RESYNC_REQ` payload

**Severity: CRITICAL** (latent — the `fromHost` guard at 1125
currently saves us). The handler's exit early on bad input is the only
thing protecting clients from a phase rewrite.

### What the handler does

`C:/CLAUDE/WHEREDNGN/Net.lua:1123-1151`:
```
function N._OnOvercallResolve(sender, takenStr, by, otype)
    if fromSelf(sender) then return end
    if not fromHost(sender) then return end
    if S.s.isHost then return end
    -- v0.8.6 H1 fix ... trust the wire. Just clear local overcall
    -- state and exit PHASE_OVERCALL.
    --
    -- The wire payload (takenStr/by/otype) is informational ... but
    -- not consulted for state mutation.
    S.s.overcall = nil
    S.s.phase = K.PHASE_DOUBLE
    if B.UI and B.UI.Refresh then B.UI.Refresh() end
end
```

The handler IGNORES `takenStr / by / otype` (per the v0.8.6 H1
comment) and unconditionally sets `S.s.overcall = nil` and
`S.s.phase = K.PHASE_DOUBLE`. So what the audit prompt calls "empty
payload demotes phase to PHASE_DOUBLE" is in fact "ANY payload demotes
phase." A nil/missing/garbage payload triggers the same rewrite.

### Why it isn't actively exploding right now (and why that's fragile)

Three defenses in the current source happen to neutralize the
collision:

1. `fromSelf(sender) → return` at 1124 short-circuits the host's
   loopback of a `MSG_OVERCALL_RESOLVE` it broadcast itself. (Doesn't
   protect against MSG_RESYNC_REQ from any other peer.)
2. `not fromHost(sender) → return` at 1125. Resync requests come from
   the rejoining peer, NOT from the host. So the request is rejected
   here. **This is the only thing preventing a phase wipe on the
   non-host side.**
3. `S.s.isHost → return` at 1126 prevents a host receiving the
   loopback from running the handler.

The "every MSG_RESYNC_REQ from a host triggers this rewrite" framing
in the audit prompt is technically incorrect for the current code:
hosts NEVER send MSG_RESYNC_REQ (gated at `WHEREDNGN.lua:108` —
`if B.State.s.isHost then return end`). However the framing is **right
in spirit**: the wire-tag collision means the handler exists on every
non-host receive path, and the only thing keeping it dormant is the
`fromHost` gate. If a future refactor:

- Allowed a host to call `SendResyncReq` (e.g. for spectator-mode
  re-sync), OR
- Removed the `fromHost` guard (e.g. someone "simplifies" since the
  wire payload is ignored anyway), OR
- The host AND the requester were both impersonated (server-side
  spoof) in a way that satisfies `fromHost` for the `"?"` path,

…then every rejoin attempt would silently wipe `S.s.overcall` and
demote `S.s.phase` to `PHASE_DOUBLE` on every non-host receiver, with
no error and no log.

### Repro (theoretical, current source)

Forge an addon-channel message: `"?;<rejoinerGameID>"` with
`sender == hostName`. The receiving non-host:

1. `fromSelf(hostName)` false → pass.
2. `fromHost(hostName)` true → pass.
3. `S.s.isHost` false → pass.
4. `S.s.overcall = nil; S.s.phase = K.PHASE_DOUBLE`.

The `takenStr=<gameID>` is ignored — no validation that it's `"0"` or
`"1"`. An attacker who has read access to the addon channel and can
spoof the host's name (only feasible via WoW client tampering, not
network MITM) can phase-wipe every non-host every 5 s.

### Repro (the practical bug — host-side soft-lock)

The chain that the audit prompt is really about: a non-host
broadcasts `MSG_RESYNC_REQ` via `N.SendResyncReq(id)`. The host
receives the broadcast loopback. Dispatch picks `_OnOvercallResolve`
(CRIT-1). `fromHost(sender)` is false (sender is the rejoiner) →
**handler returns silently**. Dispatch elseif chain has already
consumed the message. **`_OnResyncReq` never runs**. The host's
8th-audit cooldown table at `Net.lua:3107` is not even touched, log
line at 3153 never printed. The reload-rejoiner never gets a snapshot.

This is the load-bearing failure mode. CRIT-2 is the LATENT
catastrophe that becomes ACTIVE if any of the three defenses above are
removed.

### Fix surface

Same as CRIT-1: change `K.MSG_RESYNC_REQ` to a unique tag. Also: add
a positive `takenStr == "0" or takenStr == "1"` validator at the top
of `_OnOvercallResolve` so a malformed inbound (post-fix) is dropped
even if some other tag aliases `"?"` again.

---

## L1 — v0.9.1 L5 expectingResyncRes guard verified

**Severity: PASS / NO CHANGE.** Re-verified per
`audit_v0.9.0/15_v091_l5_resync.md`.

`C:/CLAUDE/WHEREDNGN/Net.lua:313-328`:
```
local expectingResyncRes = false
local resyncResExpiryTimer = nil

function N.SendResyncReq(gameID)
    broadcast(("%s;%s"):format(K.MSG_RESYNC_REQ, gameID or ""))
    expectingResyncRes = true
    if resyncResExpiryTimer and resyncResExpiryTimer.Cancel then
        resyncResExpiryTimer:Cancel()
    end
    if C_Timer and C_Timer.NewTimer then
        resyncResExpiryTimer = C_Timer.NewTimer(30, function()
            expectingResyncRes = false
            resyncResExpiryTimer = nil
        end)
    end
end
```

`C:/CLAUDE/WHEREDNGN/Net.lua:3185-3206`:
```
if S.s.isHost then return end
...
if not expectingResyncRes then return end
...
if WHEREDNGNDB and WHEREDNGNDB.lastGameID
   and WHEREDNGNDB.lastGameID ~= gameID then
    return
end
expectingResyncRes = false
if resyncResExpiryTimer and resyncResExpiryTimer.Cancel then
    resyncResExpiryTimer:Cancel()
    resyncResExpiryTimer = nil
end
```

All four gates intact: isHost short-circuit, flag check, gameID
match, flag-clear-on-consume. Timer cancellation order correct.
**No change recommended** beyond the existing audit nit (hoist 30 →
`K.RESYNC_RES_WINDOW_SEC`).

The CRIT-1 collision doesn't break this guard — `MSG_RESYNC_RES` uses
tag `"="` (line 182, no collision). The L5 fix protects the response
path, not the request path. The request path is what CRIT-1 broke.

---

## H1 — D-RT-15 race within 30-sec window: peer-overheard race against host

**Severity: HIGH (theoretical), LOW (practical).** Within the 30-s
window after a `SendResyncReq`, ANY peer who can spoof the host's
sender name AND knows the rejoiner's gameID can race the legitimate
host with a forged `MSG_RESYNC_RES`.

### Evidence

`Net.lua:3175-3219` checks (in order): `not fromSelf`, `not isHost`,
`expectingResyncRes`, `lastGameID == gameID`. Then trusts the sender
as the host:

`Net.lua:3218`:
```
S.s.hostName = (S.NormalizeName and S.NormalizeName(sender)) or sender
S.ApplyResyncSnapshot(gameID, payload)
```

There is NO check that `sender` matches the local `S.s.hostName` (or
the pre-existing host announcement). The first response to win the
race wins — even if the legitimate host's response is also in flight.

### Why this is mostly safe

Sender impersonation on the WoW addon channel is not feasible without
client-side tampering on the spoofer's end. Among legitimate peers,
no one has authority to claim to be host; the channel layer
authenticates each message with the SENDER's account. A forged
`MSG_RESYNC_RES` requires a tampered client (which already invalidates
many other guards).

### Cross-ref

D-RT-17 §7 marks this PASS but flags the cross-character ghost
request as a documented annoyance (covered in finding L2 below).

---

## H2 — `ApplyResyncSnapshot` leaks stale `s.winner` (D-RT-17 #12)

**Severity: HIGH (cosmetic).** Confirmed.

`s.winner` is written by `S.ApplyGameEnd` at `State.lua:1606`. It is
NOT in `TRANSIENT_FIELDS` (`State.lua:191-247`), so `SaveSession`
serializes it to `WHEREDNGNDB.session.state.winner`. `RestoreSession`
hard-resets `s` (line 313) before overlay, so cross-/reload it carries
correctly.

But `ApplyResyncSnapshot` does NOT hard-reset before applying. It
selectively writes parsed fields (lines 424-540). The wire format
contains 29 fields (gameID, phase, dealer, round, turn, turnKind,
contract.* x8, cumulative.A/B, paused, bidRound, 4 seats, 4 bids,
botMask, target). **`s.winner` is not on the wire.** The transient
cleanup block at lines 524-534 clears `akaCalled`, `lastTrick`,
`takweeshResult`, `swaResult`, `swaRequest`, `swaDenied`, `redealing`,
`pendingPreemptContract`, `preemptEligible`, `lastRoundResult`,
`lastRoundDelta` — but not `winner`.

### Repro

1. Game finishes. `S.ApplyGameEnd("A")` sets `s.winner = "A"`,
   `s.phase = K.PHASE_GAME_END`. SaveSession at line 252-256 nils the
   session for GAME_END phase, so `s.winner = "A"` does NOT survive a
   /reload through RestoreSession.
2. BUT: same WoW session, host starts a new lobby and plays a couple
   rounds. Now host /reloads (or another peer joins late). Their
   `s.winner` was never cleared — `S.HostBeginLobby` calls `reset()`
   (line 609) which sets `s.winner = nil` (line 39). Good.
3. The vulnerable path is: a non-host who never went through
   `reset()`. Specifically: a non-host whose previous game ended with
   `s.winner` set, then receives `MSG_RESYNC_RES` for a NEW game
   without `S.Reset()` being called between. `ApplyLobby` at 711-727
   calls `Reset()` for new-game branch — so the typical path is safe.
   The risk is mid-game resync from an earlier same-session game where
   the rejoiner skipped the lobby flow (e.g. a /reload after a
   completed game without explicit /baloot reset, then a new game).

### Cross-ref

D-RT-17 §12 already documents this. **Recommend** adding
`s.winner = nil` to the cleanup block at lines 524-534. One-line fix.

---

## H3 — `ApplyResyncSnapshot` wipes `meldsDeclared`, replay only rebuilds `meldsByTeam` (D-RT-17 #1)

**Severity: MEDIUM (UI-only).** Confirmed.

`ApplyResyncSnapshot` clears at `State.lua:514-517`:
```
s.tricks       = {}
s.meldsByTeam  = { A = {}, B = {} }
s.meldsDeclared= {}
s.playedCardsThisRound = {}
```

Then host's `SendResyncRes` replays:
- `MSG_BIDCARD` (line 397)
- `MSG_MELD` for each `meldsByTeam[team]` entry (lines 403-410) —
  replay flag `"1"` bypasses `authorizeSeat`
- `MSG_PREEMPT_PASS` if PHASE_PREEMPT (lines 416-420)
- `MSG_OVERCALL_OPEN` + decisions if PHASE_OVERCALL (lines 426-435)
- `MSG_TRICK` for each closed trick (lines 439-447)
- `MSG_PLAY` for in-flight plays (lines 453-458)
- `MSG_AKA` if active (lines 461-464)

**Nothing replays `meldsDeclared`.** `S.ApplyMeld` at `State.lua:1149`
does NOT write to `meldsDeclared` either — it only writes to
`meldsByTeam`. The `meldsDeclared` flags are stamped by:
- `Net.lua:2046-2048` (LocalDeclareMeld)
- `Net.lua:3440` (host AFK auto-declare)
- `Net.lua:4082, 4129` (bot-decision sites)
- `UI.lua:1987` ("Done" button)

A rejoiner during PHASE_DEAL3 (still in trick-1 meld window) ends up
with `meldsDeclared = {}` even though `meldsByTeam` correctly carries
declarations. UI consequences:
- `S.GetMeldsForLocal()` at `State.lua:1932` checks
  `s.meldsDeclared[s.localSeat]` — if false, it offers a fresh meld
  picker. The trick-1 wire gate at `State.lua:1154` prevents an
  invalid meld from being applied (after first trick closes), but
  during the open window the rejoiner could theoretically re-declare a
  meld they already declared — `S.ApplyMeld` then dedupes via the
  `(seat, kind, top, suit)` check at line 1159.

So state is protected (dedupe + trick-1 gate) but the local UI may
re-show the declare picker even though the seat already declared.
**Recommend**: replay walks `meldsByTeam.A ∪ meldsByTeam.B` and
stamps `meldsDeclared[m.declaredBy] = true` for each entry as the
post-replay reseed step. One short loop in the receiver, OR set
`meldsDeclared[seat] = true` inside `S.ApplyMeld` at line 1185 as
part of the standard meld-application.

---

## L2 — Cross-character ghost request: `RestoreSession` owner-mismatch returns false but doesn't clear `lastGameID` (D-RT-17 #7)

**Severity: LOW.** Confirmed.

`State.lua:307-308`:
```
if not sess.owner or not s.localName then return false end
if sess.owner ~= s.localName then return false end
```

Both early-returns bail without touching `WHEREDNGNDB.lastGameID`.
`WHEREDNGNDB` is per-account, so character A's saved `lastGameID`
persists into character B's login. PLAYER_ENTERING_WORLD then fires
`maybeRequestResync` 2s later; on character B's login,
`WHEREDNGN.lua:102` reads the surviving `WHEREDNGNDB.lastGameID` and
broadcasts `MSG_RESYNC_REQ` on character A's gameID.

The host's `_OnResyncReq` (when it eventually executes — see CRIT-1)
rejects this at `Net.lua:3147-3155` because `nsender` is character B
and B is not in the seat roster. So no leak. But:
- The wire request goes out anyway, consuming one cycle of the 5-s
  per-sender cooldown at `Net.lua:3107-3134`.
- This finding has been documented in `audit_v0.7.1/35_save_restore.md`
  line 25 and re-flagged in `D-RT-17 §7`. **Still unfixed.**

**Recommend**: add `WHEREDNGNDB.lastGameID = nil` to the
cross-character early-return at `State.lua:307-308`. One line.

Compounded by CRIT-1: `_OnResyncReq` is unreachable, so the in-roster
check that would have rejected this never runs. The request just
reaches `_OnOvercallResolve`, fails the `fromHost` guard, and dies
silently. The cooldown table is never updated either. So in current
code the practical effect is even smaller than D-RT-17 documented —
but only because resync is fully broken.

---

## H4 — Mid-Takweesh /reload race: PHASE_SCORE without re-broadcast (D-RT-17 #5)

**Severity: HIGH (rare).** Confirmed.

The Takweesh resolution flow at `Net.lua:2127+`: ApplyRoundEnd sets
`s.phase = PHASE_SCORE` (`State.lua:1466`), then `S.s.takweeshResult`
is set, MSG_ROUND broadcast, MSG_TAKWEESH_OUT broadcast. There is a
microsecond window between `S.ApplyRoundEnd` and `N.SendRound` during
which a host /reload would persist `phase=PHASE_SCORE` but no MSG_ROUND
went out.

After /reload: `RestoreSession` brings phase=SCORE back. The host
PLAYER_LOGIN re-arm block at `WHEREDNGN.lua:155-217` covers
PHASE_OVERCALL, PHASE_DOUBLE, PHASE_TRIPLE, PHASE_FOUR, PHASE_GAHWA,
PHASE_PREEMPT (transitively via MaybeRunBot), and the stuck-4-play
PHASE_PLAY edge. **There is NO branch for PHASE_SCORE.**

Result: clients still sit in PHASE_PLAY waiting for a trick/round
broadcast. The host's UI shows the score panel; clients show the stuck
table. SWA timer was already cancelled at `Net.lua:2144`.

Probability: race window is small (microseconds between
`S.ApplyRoundEnd` and `N.SendRound`). Recovery: host can `/baloot
reset` or trigger a new round transition.

**Recommend** (per D-RT-17 §5): host PLAYER_LOGIN should detect
`phase==PHASE_SCORE && s.lastRoundDelta` and re-broadcast MSG_ROUND
to clients. Or move SendRound earlier in `HostResolveTakweesh` to
shrink the race window (preferred — reduces the size, makes the
re-arm a non-emergency).

---

## M1 — M2 overcall/SWA timer re-arm ignores expired window (D-RT-17 #6, audit_v0.9.0/05 edge 5)

**Severity: MEDIUM.** Confirmed STILL UNFIXED.

`WHEREDNGN.lua:256-269` (overcall re-arm):
```
if B.State.s.phase == K.PHASE_OVERCALL
   and B.State.s.overcall then
    B.State.s.overcall.startedAt = (GetTime and GetTime()) or 0
    if C_Timer and C_Timer.After then
        C_Timer.After(K.OVERCALL_TIMEOUT_SEC, function()
            ...
        end)
    end
end
```

`WHEREDNGN.lua:270-292` (SWA re-arm):
```
if B.State.s.swaRequest and B.State.s.swaRequest.caller
   and B.State.s.phase == K.PHASE_PLAY then
    local req = B.State.s.swaRequest
    req.ts = (GetTime and GetTime()) or req.ts
    if C_Timer and C_Timer.After then
        C_Timer.After(K.SWA_TIMEOUT_SEC or 5, function()
            ...
```

Neither block compares `GetTime() - startedAt` against the timeout
constant before re-arming. If a host /reload-ed at second 6 of a 5-s
window, the human got a 10-s effective window across the reload
boundary instead of immediately auto-resolving.

`audit_v0.9.0/05_m1_m2_timer_rearm.md` flagged this as Edge 5 FAIL.
D-RT-17 §6 re-verified it as STILL FAIL. Confirmed in current source
(no fix landed).

**Recommend** elapsed-time precheck:
```
local elapsed = (GetTime() or 0) - (S.s.overcall.startedAt or 0)
if elapsed >= K.OVERCALL_TIMEOUT_SEC then
    N._HostResolveOvercall()
else
    -- existing re-arm
end
```
Same shape for SWA.

---

## L3 — AKA banner replay through resync (Net.lua:461-463)

**Severity: LOW (informational).** Behavior is correct.

`Net.lua:459-464`:
```
-- Replay AKA banner if active this trick. Trailing "1" tells
-- _OnAKA to bypass authorizeSeat (sender is host, not seat owner).
if S.s.akaCalled then
    whisper(target, ("%s;%d;%s;1"):format(
        K.MSG_AKA, S.s.akaCalled.seat or 0, S.s.akaCalled.suit or ""))
end
```

`_OnAKA` at `Net.lua:3075-3096` honors the replay flag:
```
local isReplay = (replayFlag == "1") and fromHost(sender)
-- 13th-audit defense: hosts are never the target of a replay frame.
if isReplay and S.s.isHost then return end
if not isReplay and not authorizeSeat(seat, sender) then return end
```

The `fromHost(sender)` extra requirement on `isReplay` defends
against a peer forging `replayFlag=="1"`. The host-ignore guard
prevents host loopback re-application. PHASE check at line 3090
restricts to `PHASE_PLAY`. Contract type check at 3094 restricts to
HOKM (AKA only meaningful in HOKM). All four gates intact.

`s.akaCalled` is in `TRANSIENT_FIELDS` (`State.lua:216`), so a
non-host /reload during PHASE_PLAY with an active AKA needs the
resync replay to restore the banner — which is exactly what this
block does. **PASS**, no change.

One minor nit (informational): the resync replay block has no
analogous restoration for `swaRequest` or `swaResult`. `swaRequest` is
non-transient (per State.lua:225-227 comment) so RestoreSession
brings it back; `swaResult` is transient and not replayed. The
non-host rejoiner mid-SWA-vote would lose the SWA pending banner
visually, but the host's flow continues correctly via RestoreSession's
swaRequest survival on the host side. Acceptable.

---

## Findings summary table

| # | ID | Severity | Status |
|---|---|---|---|
| 1 | CRIT-1 wire-tag collision MSG_RESYNC_REQ ↔ MSG_OVERCALL_RESOLVE | **CRITICAL** | Confirmed v0.7.0+, dispatch makes _OnResyncReq dead code |
| 2 | CRIT-2 _OnOvercallResolve unconditional phase rewrite | **CRITICAL (latent)** | Confirmed; only the fromHost guard keeps it dormant |
| 3 | L1 expectingResyncRes guard verification | PASS | All 4 gates intact (audit_v0.9.0/15) |
| 4 | H1 30-s window peer race | HIGH theoretical / LOW practical | Confirmed; addon-channel auth limits exploit |
| 5 | H2 stale s.winner leak through ApplyResyncSnapshot | HIGH (cosmetic) | Confirmed (D-RT-17 #12); 1-line fix |
| 6 | H3 meldsDeclared not replayed | MEDIUM (UI) | Confirmed (D-RT-17 #1); replay-loop fix |
| 7 | L2 cross-character ghost lastGameID | LOW | Confirmed (audit_v0.7.1/35 + D-RT-17 #7); STILL UNFIXED, 1-line |
| 8 | H4 mid-Takweesh /reload PHASE_SCORE soft-lock | HIGH (rare) | Confirmed (D-RT-17 #5); race window microseconds |
| 9 | M1 M2 timer re-arm no elapsed-precheck | MEDIUM | Confirmed (audit_v0.9.0/05 Edge 5 + D-RT-17 #6); STILL UNFIXED |
| 10 | L3 AKA banner resync replay | PASS | All gates intact, 4 defenses |

---

## Critical-path top-priority fix order

1. **CRIT-1** — change `K.MSG_RESYNC_REQ` from `"?"` to a unique
   character (e.g. `"q"` is free; `"?"` is unfortunately one of the
   most syntactically-typo'd chars in the wire-format design — picking
   any other ASCII char that doesn't already collide is fine). Add a
   wire-tag uniqueness assert at addon load.
2. **CRIT-2** — same fix (de-collision). Then add a positive
   `takenStr ∈ {"0","1"}` validator at the top of `_OnOvercallResolve`
   to defend against future tag aliasing or refactor regression.
3. **H4 (mid-Takweesh race)** — host PLAYER_LOGIN re-arm block must
   handle `phase==PHASE_SCORE` by re-broadcasting `MSG_ROUND` based on
   `s.lastRoundDelta`. Or move `N.SendRound` earlier in
   `HostResolveTakweesh` to shrink the race window to nothing.
4. **H2 (stale winner)** — add `s.winner = nil` to the cleanup block
   at `State.lua:524-534`. One-line.
5. **H3 (meldsDeclared replay)** — set `meldsDeclared[seat]=true`
   inside `S.ApplyMeld` at line 1185 as part of standard meld-apply,
   or have the resync replay loop walk the team buckets and stamp
   declared seats post-replay.
6. **M1 (timer re-arm elapsed precheck)** — add elapsed-time gate
   before re-arm in `WHEREDNGN.lua:256-269` and `:270-292`.
7. **L2 (cross-char ghost request)** — add
   `WHEREDNGNDB.lastGameID = nil` to the cross-character early-return
   at `State.lua:307-308`.

Tests to add (run as `python tests/run.py`):
- `test_wire_tag_uniqueness.lua` — assert all `K.MSG_*` values are
  pairwise distinct.
- `test_resync_round_trip.lua` — drive a full SendResyncReq +
  _OnResyncReq + ApplyResyncSnapshot loop with overcall ENABLED and
  assert `_OnResyncReq` actually executed (e.g., observe a side
  effect in the cooldown table).
- `test_overcall_resolve_payload_validation.lua` — assert
  `_OnOvercallResolve` rejects non-`"0"`/`"1"` `takenStr` values.

