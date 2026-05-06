# 43 — Lobby + Game-Start Handshake Audit (Net.lua, v0.7.2 HEAD)

Scope: `MSG_HOST/JOIN/LOBBY/START/DEAL_PHASE/HAND` and host-lobby + apply
functions in `State.lua`.

## Findings

### 1. Race — 4 simultaneous joins  (LOW / OK)
`N._OnJoin` (Net.lua:683) → `S.HostHandleJoin` (State.lua:578).
WoW addon-channel delivery is single-threaded into the host's event loop;
each `_OnJoin` mutates `s.seats` and rebroadcasts `MSG_LOBBY` before the
next message dispatches. `HostHandleJoin` linearly scans seats 2..4 for
the first empty slot, idempotent on duplicate names. **No race.**
Each successful seating broadcasts a fresh `MSG_LOBBY`; the 4th join
that arrives after seats fill silently no-ops (function returns nil) —
joiner gets no rejection signal but cannot collide. Acceptable.

### 2. Late-join after game start  (HIGH — bug)
`_OnJoin` (Net.lua:689) gates on `phase == PHASE_LOBBY`, so direct joins
post-start are correctly dropped. **However**, `_OnResyncReq`
(Net.lua:2979) only verifies the requester is in **the host's seat
roster**. A late-joiner whose name was never added cannot resync
(correct). But `S.ApplyResyncSnapshot` (State.lua:342) does **not gate
on phase or membership** — any peer that fabricates a `MSG_RESYNC_RES`
with a matching `gameID` rebuilds `s.seats` from snapshot field 28's
`botMask` and 20..23's names, making them a spectator with full snapshot.
Since `_OnResyncRes` (Net.lua:3045) only checks `WHEREDNGNDB.lastGameID
== gameID`, a peer who happened to overhear the gameID and never
joined gets full game state including bid/contract/cumulative — no hand
(whisper-gated) but observation leak. **Recommend**: gate
`_OnResyncRes` on `S.s.gameID ~= "" → must match` AND require the local
client to have actually issued a `SendResyncReq` recently (e.g.
short-lived nonce / pending flag).

### 3. Spectator (`localSeat == nil`)  (LOW / OK)
`S.ApplyLobby` (State.lua:644) handles nil cleanly: line 695 only
assigns `localSeat` if `SeatOf` returns non-nil; line 699/703 guard
on `s.localSeat`. Apply paths (`ApplyStart`, `ApplyHand`) do not deref
`localSeat` without a `if s.localSeat then` guard except in UI; spot-
checked paths (lines 832, 1199, 1241, 1389, 1751) all guard. **OK.**

### 4. MSG_HAND cross-talk  (LOW / OK)
`N.SendHand` (Net.lua:120) uses WHISPER channel exclusively;
`dealHandsToHumans` (line 126) skips bots and self. `_OnHand`
(Net.lua:784) gates on `fromHost(sender)` and `not S.s.isHost`. WoW's
WHISPER addon channel only delivers to the named target — no cross-talk
risk. The `forRound` tag (line 119) prevents stale-round hand replays.
**OK.**

### 5. peerVersions populates  (LOW / OK)
`_OnHost`, `_OnJoin`, `_OnLobby` (lines 657, 683, 704) all write to
`S.s.peerVersions` keyed by `NormalizeName(sender)`. `_OnLobby` writes
the **host's** version under the **sender's** key (line 737) — cosmetic
flaw: a peer relaying lobby would map host-version onto themselves.
Since `isHost` guard (line 712) blocks self-applies, only non-host
clients hit this — and in v1 only the host broadcasts `MSG_LOBBY`, so
sender == host. **OK in practice but fragile.**

### 6. `s.winner` clearing on restart  (OK — verified)
State.lua:39 clears `s.winner` in `reset()`. `S.ApplyLobby`'s newGame
branch (State.lua:667) calls `S.Reset()` before re-seeding lobby state,
so a post-`PHASE_GAME_END` lobby announcement clears stale winner.
`HostBeginLobby` (State.lua:556) also calls `reset()` at line 563. C30
fix intact.

## Highest-priority issue
**#2** — `ApplyResyncSnapshot` accepts unsolicited snapshots if gameID
matches `WHEREDNGNDB.lastGameID`. Add a "pending resync request"
nonce/flag set by `SendResyncReq` and required by `_OnResyncRes`.
