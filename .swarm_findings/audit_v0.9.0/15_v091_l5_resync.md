# 15 — v0.9.1 L5 Resync-Window Guard Verification

## State of the change

The "uncommitted change" is in fact already committed as `83717be`
(v0.9.1). Working tree is clean. Diff verified via `git show
83717be -- Net.lua` against the live `C:/CLAUDE/WHEREDNGN/Net.lua`
(lines 297–321 + 3146–3177).

## Original L5 finding

> `_OnResyncRes` accepts any snapshot whose gameID matches
> `WHEREDNGNDB.lastGameID` — a peer who overheard the gameID can
> fabricate a response. No "did I request this?" gate.

## Verification

### a. `expectingResyncRes` initialized correctly

YES. `local expectingResyncRes = false` at line 306 — module-scoped,
defaults to false. A fresh `/reload` cannot accept a resync until
`SendResyncReq` runs.

### b. Set true only when WE send `MSG_RESYNC_REQ`

YES. Set inside `N.SendResyncReq` (line 311) immediately after the
`broadcast()` call. No other write site exists for `true`
(grep-confirmed: only assignments are line 311 = true, lines 317
& 3173 = false).

### c. Timer correctly clears `expectingResyncRes` after 30 s

YES. `C_Timer.NewTimer(30, function() expectingResyncRes = false;
resyncResExpiryTimer = nil end)`. Closure correctly nils both flag
and the timer handle.

### d. `_OnResyncRes` checks the flag before accepting

YES. Line 3162: `if not expectingResyncRes then return end` is
positioned AFTER `S.s.isHost` early-out and BEFORE the gameID
comparison. Order is correct — host-itself short-circuits without
even consulting the flag.

### e. Flag clears on first valid response

YES. Lines 3173–3177: flag set false, timer cancelled, handle
nilled. A subsequent unsolicited `MSG_RESYNC_RES` (forged or stale)
hits the `not expectingResyncRes` guard and is dropped.

### f. Edge — multiple resync requests in quick succession

CORRECTLY HANDLED. Lines 312–314 cancel any prior pending timer
before re-arming, so the new 30-s window starts from the most
recent `SendResyncReq` rather than expiring early. Flag stays true
across re-requests, which is desired (any response in window is
valid).

### g. Edge — host's response arrives AFTER 30 s

Caller must manually re-request. Behaviour is correct-by-design:
the late response is dropped silently. Practical impact is
negligible — resync round-trips are sub-second on healthy realms;
30 s is generous.

### h. Edge — host-itself receives `MSG_RESYNC_RES`

`if S.s.isHost then return` (line 3156, 11th-audit fix) precedes
the new flag check. Host never even consults `expectingResyncRes`,
so the flag is never spuriously cleared by inbound traffic the
host shouldn't be processing. Clean.

## Recommendation

**Hoist the 30-s literal into `K.RESYNC_RES_WINDOW_SEC = 30`** in
`Constants.lua` next to `K.MSG_RESYNC_REQ`/`K.MSG_RESYNC_RES`
(lines 177–178). One magic-number now, but if a future tweak
extends the window or adds a unit-test stub, having the constant
co-located with the message tags is cheap insurance. Non-blocking.

## Verdict

**READY-TO-SHIP.** All six gates pass; multi-request and host-self
edges handled. Only nit is the hardcoded `30` literal.
