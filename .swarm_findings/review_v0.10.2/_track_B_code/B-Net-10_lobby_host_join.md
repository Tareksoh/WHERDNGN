# B-Net-10 — Lobby / host-announce / join handlers + version negotiation

**Scope:** All `_OnHost*`, `_OnJoin`, `_OnLobby`, `_OnTeams` handlers in
`Net.lua`, plus the senders `N.SendHostAnnounce` / `N.SendJoin` /
`N.SendLobby` / `N.SendTeams`, the host-side seating primitives in
`State.lua` (`S.HostBeginLobby`, `S.HostHandleJoin`, `S.HostAddBots`,
`S.ApplyLobby`, `S.ApplyTeamNames`), version-tag handling on the wire,
and the wire-tag table in `Constants.lua` (`K.MSG_HOST`, `K.MSG_JOIN`,
`K.MSG_LOBBY`, `K.MSG_TEAMS`, `K.MSG_RESYNC_REQ`,
`K.MSG_OVERCALL_RESOLVE`).

**Read:** `Net.lua` 1-130, 295-330, 467-680, 684-870, 1055-1230,
2455-2470, 3105-3170; `State.lua` 30-180, 320-470, 540-750;
`Constants.lua` 137-235, 268; `WHEREDNGN.toc` 1-32; commit `a3abe18`
(v0.7.0-pre1) for CRIT-1 origin.

**Method:** trace every host/join/lobby code path; cross-check seat
mutation against bot/human authorization; quote each finding from the
file and line cited; flag where v0.10.2 has no defensive code despite
known divergence (D-RT-16). **No code modified.**

---

## Severity legend

- **CRIT (BLOCKER)** — silently breaks a feature or admits a remote
  attack with current shipping wire format.
- **HIGH** — observable bug under common conditions; data integrity or
  authorization is at risk.
- **MED** — race or trust hazard requiring an unusual but plausible
  trigger sequence.
- **LOW** — defense-in-depth gap with no current exploit but no
  protection against future regression.

---

## CRIT — Wire-tag collision: `K.MSG_RESYNC_REQ` == `K.MSG_OVERCALL_RESOLVE` == `"?"`

**Severity:** CRIT (BLOCKER) — pre-existing in v0.7.0+, identified
also in D-RT-15 / D-RT-16. Re-confirmed here in scope-7 audit.

**Code:**

`Constants.lua:181` and `Constants.lua:229`:

```
K.MSG_RESYNC_REQ      = "?"  -- request state from host
…
K.MSG_OVERCALL_RESOLVE = "?"  -- v0.7 host announces the overcall window
                              -- closed and what happened. Payload:
                              -- taken(0|1);by(seat or 0);type
```

`Net.lua:489-490` (dispatch — pure `;`-split, no length disambiguation):

```
local fields = split(message, ";")
local tag = fields[1]
```

`Net.lua:543-547` and `Net.lua:620-621` — collision is order-decided:

```
elseif tag == K.MSG_OVERCALL_RESOLVE then
    -- v0.7 Sun-overcall: window closed; result follows.
    -- Payload: taken(0|1);by(seat or 0);type.
    N._OnOvercallResolve(sender, fields[2], tonumber(fields[3]),
                         fields[4])
…
elseif tag == K.MSG_RESYNC_REQ then
    N._OnResyncReq(sender, fields[2])
```

**Repro:**

1. A late-joiner runs `N.SendResyncReq(gameID)` →
   `Net.lua:316-317`:
   ```
   broadcast(("%s;%s"):format(K.MSG_RESYNC_REQ, gameID or ""))
   ```
   Wire frame is literally `?;<gameID>`.
2. Every receiver's dispatcher matches the first elseif arm
   (`tag == K.MSG_OVERCALL_RESOLVE`) and routes to
   `N._OnOvercallResolve(sender, gameID, nil, nil)`.
3. `_OnResyncReq` is unreachable from the wire. The
   `expectingResyncRes` 30-second window
   (`Net.lua:313` and `Net.lua:322-326`) ticks down with no response;
   v0.9.1 L5 then permanently rejects any late host response.
4. A peer who has been promoted to the recipient's `s.hostName` (via
   the `lastGameID` branch in `_OnLobby`, `Net.lua:750-757`) and who
   sends a resync request causes `_OnOvercallResolve` to silently
   write `S.s.overcall = nil; S.s.phase = K.PHASE_DOUBLE`
   (`Net.lua:1148-1149`) on every other client — possibly mid-PLAY,
   forcing them out of trick play.

**Origin:** `K.MSG_OVERCALL_RESOLVE = "?"` was introduced in commit
`a3abe18` (v0.7.0-pre1 — "Sun-overcall Phase 1") on top of the
pre-existing `K.MSG_RESYNC_REQ = "?"` (v0.1.x). The collision has been
in shipping releases since v0.7.0, so **resync-on-host has been
non-functional for every release v0.7.0 through v0.10.2 inclusive.**

**Confirmed cross-version impact (D-RT-16 Change 9):** the breakage
is identical in v0.9.6 and v0.10.2 — no version of the wire protocol
delivers a resync request to the host's `_OnResyncReq` handler. A fix
must rename one of the two tags (free single-byte codes available:
e.g., `"!"`, `"#"`, `"$"`, `"&"`) and that rename is itself a
wire-protocol break — any pre-fix client mixed with a post-fix host
will continue to mis-route.

**Quote of the receive-path harm** (`Net.lua:1123-1151`):

```
function N._OnOvercallResolve(sender, takenStr, by, otype)
    if fromSelf(sender) then return end
    if not fromHost(sender) then return end
    if S.s.isHost then return end
    …
    S.s.overcall = nil
    S.s.phase = K.PHASE_DOUBLE
    if B.UI and B.UI.Refresh then B.UI.Refresh() end
end
```

There is **no payload validation** — a frame `?;` (only the tag
character + a separator) with all subsequent fields nil is accepted as
long as `sender == hostName`. So even a single tag-only frame on the
collision path forcibly demotes phase to DOUBLE.

---

## HIGH — Version-skew unenforced; v0.9.6 host marks v0.10.2 client's M4 plays illegal

**Severity:** HIGH — actively dangerous in mixed-version play
(D-RT-16 Change 6, hard-blocking).

**Code:**

`Net.lua:691, 714, 764` — peer-version table is populated for
host/join/lobby:

```
-- _OnHost (line 689-692)
if version and version ~= "" then
    local skey = (S.NormalizeName and S.NormalizeName(sender)) or sender
    S.s.peerVersions[skey] = version
end

-- _OnJoin (line 712-715)
if version and version ~= "" then
    local skey = (S.NormalizeName and S.NormalizeName(sender)) or sender
    S.s.peerVersions[skey] = version
end

-- _OnLobby (line 762-765)
local skey = (S.NormalizeName and S.NormalizeName(sender)) or sender
if hostVersion and hostVersion ~= "" then
    S.s.peerVersions[skey] = hostVersion
end
```

`Net.lua:710-729` (`_OnJoin`) — host accepts a join request and
seats the peer **without checking `S.s.peerVersions[sender]`**:

```
function N._OnJoin(sender, gameID, version)
    if fromSelf(sender) then return end
    if version and version ~= "" then
        local skey = (S.NormalizeName and S.NormalizeName(sender)) or sender
        S.s.peerVersions[skey] = version
    end
    if not S.s.isHost or S.s.phase ~= K.PHASE_LOBBY then return end
    if gameID ~= S.s.gameID then return end
    local seat = S.HostHandleJoin(sender)
    if seat then
        N.SendLobby(S.s.seats, S.s.gameID)
        …
    end
end
```

`State.lua:624-639` (`S.HostHandleJoin`) — same: no version
check at the seating layer either:

```
function S.HostHandleJoin(name)
    if not s.isHost or s.phase ~= K.PHASE_LOBBY then return end
    if not name or name == s.localName then return end
    -- already seated?
    for _, info in pairs(s.seats) do
        if info and info.name == name then return end
    end
    -- find first empty seat (2..4)
    for seat = 2, 4 do
        if not s.seats[seat] then
            s.seats[seat] = { name = name }
            log("HostHandleJoin %s -> seat %d", name, seat)
            return seat
        end
    end
end
```

The grep `MIN_PEER|RejectPeer|seatGate|CompareVersion` returns zero
hits in the live codebase; no helper exists.

**Repro (Change 6, hard-blocking M4 case):**

1. v0.9.6 client and v0.10.2 host start a lobby. UI in
   `UI.lua:2803-2811` displays version mismatch (red badge), but the
   host does not refuse the seat.
2. Lobby fills, deal proceeds. A round arrives where AKA is signalled
   on a non-trump suit and the AKA-receiver (v0.10.2 client) is void
   in that suit but holds trump.
3. v0.10.2 receiver's `Bot.legalPlaysFor` invokes `R.IsLegalPlay` with
   the M4-aware 6-param signature (`card, hand, trick, contract, seat,
   akaCalled`) — discarding a low non-trump is now legal.
4. v0.10.2 client's bot picks the discard, broadcasts `MSG_PLAY`.
5. v0.9.6 host's `S.ApplyPlay` runs the **5-param** `R.IsLegalPlay`
   (no `akaCalled` arg). The discard is rejected as
   "must-trump-ruff" violation. The host marks the play
   `.illegal=true`.
6. Any seat (or v0.9.6 host-side bot) calling Takweesh in the window
   sees the `.illegal=true` flag and resolves the Qaid against the
   v0.10.2 client's team — a wrong score-affecting penalty against a
   correctly-played card.

**Recommendation (D-RT-16):** add a host-side seating gate in
`_OnJoin` (or `S.HostHandleJoin`) that compares
`S.s.peerVersions[sender]` against a `K.MIN_PEER_VERSION` threshold
(set to `v0.10.2` per M4 hard-block). Below the floor: silently drop
the join request and log; do not allocate a seat. The peer-version
write at `Net.lua:691, 714` already runs **before** `HostHandleJoin`
(see line ordering 712-718), so the data is available at the gate
point.

The current code has comment lines describing the version handshake
intent (`Net.lua:88-92` "old clients just ignore the extra field —
backward compatible") but no enforcement of the lower bound.

**Cross-version legality divergence (Change 6 specifically) is the
hard-block.** Other changes (R5, M3, M1) are score-divergent but
host-authoritative; mixed-version desync rounds out at ~10-20 gp per
Qaid round (D-RT-16 #8). Change 6 produces *wrong-team Qaid
penalties*, which is in a different severity class (game-decision-
affecting wrong-team scoring).

---

## HIGH — Peer claims `hostName` via `WHEREDNGNDB.lastGameID` (X9-3 trade-off documented)

**Severity:** HIGH — known trade-off; the v0.7.1 4th-audit X9-3 fix
acknowledged the residual hazard but accepted it.

**Code:**

`Net.lua:740-757` (`_OnLobby`):

```
-- 4th-audit X9-3 fix: tighten host adoption. Previously any peer
-- who broadcast MSG_LOBBY first could claim hostName when our
-- pendingHost was unset (e.g., post-/reload before we got a
-- MSG_HOST). Now require either:
--   (a) sender already known as host (idempotent re-bind), or
--   (b) we have a pendingHost record matching this gameID, or
--   (c) the gameID matches the one we previously joined
--       (WHEREDNGNDB.lastGameID surviving /reload).
-- Otherwise leave hostName alone — better to mis-render a lobby
-- than to grant host authority to an arbitrary peer.
if not fromHost(sender) and not S.s.pendingHost then
    local trustGameID = (WHEREDNGNDB and WHEREDNGNDB.lastGameID == gameID)
    if trustGameID then
        S.s.hostName = sender
    end
elseif S.s.pendingHost and S.s.pendingHost.gameID == gameID then
    S.s.hostName = sender
end
```

**Repro (residual attack with trust path (c)):**

1. Victim and attacker are previously in a real lobby together (game
   id `ABC123`); attacker has overheard the gameID. Victim later
   `/reload`s — `WHEREDNGNDB.lastGameID == "ABC123"` survives.
2. Attacker (not the original host) broadcasts `L;ABC123;<seats>;…`
   first, beating the real host's re-broadcast.
3. Victim's `_OnLobby` runs the trust-(c) branch: `not fromHost
   and not pendingHost and lastGameID == gameID` → assigns
   `S.s.hostName = attacker`.
4. Subsequent `fromHost(attacker)` returns true on the victim. The
   attacker can now broadcast any host-only frame (`MSG_TURN`,
   `MSG_DEAL`, `MSG_TEAMS`, `MSG_BIDCARD`, `MSG_CONTRACT`,
   `MSG_OVERCALL_RESOLVE`, `MSG_TRICK`, `MSG_ROUND`, `MSG_GAMEEND`,
   `MSG_PAUSE`) and the victim accepts it.
5. Notably — combined with **CRIT-1 above** — the attacker can broadcast
   a single `?;` frame (which routes through `_OnOvercallResolve`) and
   silently force `S.s.phase = K.PHASE_DOUBLE` on the victim mid-trick.

**Mitigation present (still partial):** trust path (c) is gated by
having the same `lastGameID`. An attacker must (a) have been in the
prior lobby, or (b) have observed the gameID by passive monitoring
(addon-channel messages are visible to anyone with the addon prefix).
No cryptographic proof is required.

The X9-3 fix comment explicitly acknowledges the residual: "Otherwise
leave hostName alone — better to mis-render a lobby than to grant
host authority to an arbitrary peer." — but path (c) still grants
authority to a specific peer once `lastGameID` matches.

**Out-of-scope mitigation:** the recommended host-side seating gate
(see HIGH above) does NOT close this — `_OnLobby` is run by the joining
peer, not by the host, and the trust handoff happens at the
joining-peer side based on a saved-vars value. A defense would require
the host to sign / chain hostnames over the wire, which is beyond v1.

---

## HIGH — `_OnHost` overwrites `pendingHost` on every host announce

**Severity:** HIGH — multiple-host race during HostAnnounce conflict.

**Code:**

`Net.lua:684-708` (`_OnHost`):

```
function N._OnHost(sender, gameID, version)
    if fromSelf(sender) then return end
    -- Track the host's addon version so the lobby can flag mismatches.
    if version and version ~= "" then
        local skey = (S.NormalizeName and S.NormalizeName(sender)) or sender
        S.s.peerVersions[skey] = version
    end
    if S.s.isHost then return end
    -- Accept host announcements during any "passive" phase: IDLE, LOBBY,
    -- SCORE (round-end banner) and GAME_END.
    local p = S.s.phase
    if p ~= K.PHASE_IDLE and p ~= K.PHASE_LOBBY
       and p ~= K.PHASE_SCORE and p ~= K.PHASE_GAME_END then
        return
    end
    S.s.pendingHost = { name = sender, gameID = gameID }
    log("Info", "host announce from %s gameID=%s ver=%s",
        sender, tostring(gameID), tostring(version))
end
```

**Repro (multiple-host race):**

1. Two players `A` and `B` both run `/baloot host` simultaneously
   (e.g., in a 5-player party where two of them are racing to host).
2. Both call `S.HostBeginLobby` (`State.lua:602-621`), which generates
   independent random gameIDs and starts independent lobby tickers
   (`Slash.lua:65-74` / `UI.lua:773-789`).
3. Both broadcast `H;<theirGameID>;<version>` on a `K.LOBBY_BROADCAST_SEC`
   = 3.0s ticker.
4. Victim `C` (non-host, in PHASE_IDLE) receives both frames. Each
   `_OnHost` call overwrites `S.s.pendingHost = { name, gameID }`
   with the **most recent** sender. The two hosts' announces alternate
   on roughly 3-second intervals; whichever host's frame
   `C` saw last wins, which `C` proceeds to `/baloot join` with.
5. The losing host stays in PHASE_LOBBY indefinitely; their lobby
   ticker re-broadcasts every 3s. If `C` joins host `A`, host `B`'s
   lobby has only itself, eventually `B` quits. Until then, `C`'s UI
   `lobbyTicker`-driven refresh shows an unstable host name.

**Quote of the issue** (`Net.lua:705`):

```
S.s.pendingHost = { name = sender, gameID = gameID }
```

No deduplication, no precedence (e.g., "first host announce wins
until the user explicitly joins one"). The replacement is
last-writer-wins and there is no churn dampening.

**Out-of-scope mitigation:** a fix could check
`if S.s.pendingHost and S.s.pendingHost.gameID ~= gameID then
return end` to lock to the first-heard host until the user clears it.
This trades multi-host UX (rare) for stability (common). Not
applied per task scope.

---

## HIGH — Seat reassignment race during lobby join

**Severity:** HIGH — race between concurrent join requests can result
in a stale seat assignment surviving past the next lobby broadcast.

**Code:**

`State.lua:624-639` (`S.HostHandleJoin`):

```
function S.HostHandleJoin(name)
    if not s.isHost or s.phase ~= K.PHASE_LOBBY then return end
    if not name or name == s.localName then return end
    -- already seated?
    for _, info in pairs(s.seats) do
        if info and info.name == name then return end
    end
    -- find first empty seat (2..4)
    for seat = 2, 4 do
        if not s.seats[seat] then
            s.seats[seat] = { name = name }
            log("HostHandleJoin %s -> seat %d", name, seat)
            return seat
        end
    end
end
```

`Net.lua:710-729` (`_OnJoin`):

```
function N._OnJoin(sender, gameID, version)
    …
    if not S.s.isHost or S.s.phase ~= K.PHASE_LOBBY then return end
    if gameID ~= S.s.gameID then return end
    local seat = S.HostHandleJoin(sender)
    if seat then
        N.SendLobby(S.s.seats, S.s.gameID)
        …
    end
end
```

**Repro 1 — duplicate name identity check uses raw equality:**

1. Three players `Alice-Realm1`, `Alice-Realm2`, `Alice` (no realm)
   join the same lobby.
2. `S.HostHandleJoin` line 629:
   `if info and info.name == name then return end` — strict equality,
   no `S.NormalizeName` comparison.
3. The same logical player joining twice from a `/reload` (where
   `sender` arrives once as `"Alice"` (same-realm) and once as
   `"Alice-Realm"` (cross-realm chat dispatch quirk)) would seat both
   variants. The roster shows Alice in seats 2 and 3. The next
   `SendLobby` broadcasts both names. Alice's own client matches the
   Realm-suffixed seat via `S.SeatOf` (line 568 — *which is normalized*),
   so the *non-normalized* duplicate stays as a phantom seat occupied
   by what looks like Alice but no longer maps to a player.

**Repro 2 — late-join overlay during seat-2 → seat-3 swap:**

1. Host swaps seats 2 and 3 via `S.HostSwapSeats(2, 3)`
   (`State.lua:669-678`).
2. Before the next `N.SendLobby` is broadcast, a third player's
   `MSG_JOIN` arrives. `_OnJoin` calls `S.HostHandleJoin`, which
   iterates `for seat = 2, 4 do`. Seat 2 is now empty (because the
   swap moved seat 2's previous occupant to seat 3); the new joiner
   is seated at 2. The swap is then no longer reflected — what looked
   like a swap-then-fill on the host produces seat 2 occupied by
   the late joiner, which is correct but lost the swap intent.
3. **More serious variant:** if `HostSwapSeats` is called twice in
   quick succession (e.g., the host clicks two swap buttons in an
   adjacent UI element), the second swap is applied to the post-first-
   swap state, and a join arriving in between produces a 3-seat
   reordering that the host did not request.

The second variant is a UI race (no separate input lock) and the
first is a normalization bug at line 629 (`info.name == name` should
be a `nameEq` helper like `_OnResyncReq` at `Net.lua:3141-3146`).

**Quote of the un-normalized identity check** (`State.lua:629`):

```
if info and info.name == name then return end
```

The corresponding fix pattern already exists in `_OnResyncReq`:

```
local function nameEq(infoName, target)
    if not infoName or not target then return false end
    if infoName == target then return true end
    local n = (S.NormalizeName and S.NormalizeName(infoName)) or infoName
    return n == target
end
```

This helper is local to `_OnResyncReq` — `HostHandleJoin` does not
share it.

---

## HIGH — Seat-claim authentication: anybody on the addon channel can claim

**Severity:** HIGH — `_OnJoin` accepts join requests with no
verification beyond `gameID`.

**Code:**

`Net.lua:710-729` (`_OnJoin`):

```
function N._OnJoin(sender, gameID, version)
    if fromSelf(sender) then return end
    if version and version ~= "" then
        local skey = (S.NormalizeName and S.NormalizeName(sender)) or sender
        S.s.peerVersions[skey] = version
    end
    if not S.s.isHost or S.s.phase ~= K.PHASE_LOBBY then return end
    if gameID ~= S.s.gameID then return end
    local seat = S.HostHandleJoin(sender)
    …
end
```

The only gates are:

1. The host is hosting (`S.s.isHost`).
2. The host is in PHASE_LOBBY.
3. The wire-claimed `gameID` matches the host's local `gameID`.

There is no party-membership check — `IsInGroup()` is checked at
`broadcast` send-time (`Net.lua:39`) but not at receive-time. A
player who has the addon prefix and broadcasts on the right channel
can self-seat in any open lobby they observe. Within a real WoW
party, the channel is party-only, so the attacker must be in the
victim's party — but that's the *only* check.

**Quote of the missing authentication** (`Net.lua:716-718`):

```
if not S.s.isHost or S.s.phase ~= K.PHASE_LOBBY then return end
if gameID ~= S.s.gameID then return end
local seat = S.HostHandleJoin(sender)
```

**Plausible attack:** a party member who has not been invited to the
game (e.g., was in the lobby for a previous match, didn't /baloot
host themselves) can fire `MSG_JOIN` with the host's gameID and self-
seat into one of seats 2-4 if open. Because the host's bot-fill is
also an opt-in (the `Fill Bots` button), the malicious player can
race the host's intended bot-fill and claim the seat first.

**Mitigation present:** `s.localName` check in `S.HostHandleJoin`
(`State.lua:626`) prevents the host from being kicked into seat 2-4
themselves; nothing else applies.

**Why this isn't already blocked by `authorizeSeat`:**
`authorizeSeat` (`Net.lua:661-678`) is for **per-seat actions**
post-seating (bid, play, meld, etc.). Seating itself is not gated
through it. A defense would require the host to maintain a
"pre-invited" allowlist (the party member roster?) and reject join
requests from senders not in it.

---

## MED — `_OnTeamNames` (`_OnTeams`) re-broadcast on lobby-join can race with concurrent player-set

**Severity:** MED — a player setting team names via the lobby UI
while a join request lands can cause a rollback to the prior names.

**Code:**

`Net.lua:710-729` (`_OnJoin` re-broadcasts teams on every join):

```
local seat = S.HostHandleJoin(sender)
if seat then
    N.SendLobby(S.s.seats, S.s.gameID)
    -- Re-broadcast custom team labels so the late joiner doesn't
    -- see the default "Team A"/"Team B" — SendLobby's payload
    -- doesn't carry team names (kept compact), and the lobby
    -- ticker only re-broadcasts SendHostAnnounce.
    if S.s.teamNames and N.SendTeams then
        N.SendTeams(S.s.teamNames.A or "", S.s.teamNames.B or "")
    end
end
```

`Net.lua:300-302` (`SendTeams` — broadcasts on PARTY):

```
function N.SendTeams(teamA, teamB)
    broadcast(("%s;%s;%s"):format(K.MSG_TEAMS, teamA or "", teamB or ""))
end
```

`Net.lua:2461-2466` (`_OnTeams` — receivers apply blindly):

```
function N._OnTeams(sender, teamA, teamB)
    if fromSelf(sender) then return end
    if not fromHost(sender) then return end
    if S.s.isHost then return end
    S.ApplyTeamNames(teamA, teamB)
end
```

`State.lua:163-175` (`S.ApplyTeamNames`):

```
function S.ApplyTeamNames(teamA, teamB)
    s.teamNames = s.teamNames or { A = "Team A", B = "Team B" }
    if teamA and teamA ~= "" then s.teamNames.A = teamA:sub(1, 20) end
    if teamB and teamB ~= "" then s.teamNames.B = teamB:sub(1, 20) end
    -- Persist per-account so the host's chosen names survive between
    -- sessions; the lobby UI pre-fills from this on next /reload.
    if WHEREDNGNDB then
        WHEREDNGNDB.teamNames = {
            A = s.teamNames.A,
            B = s.teamNames.B,
        }
    end
end
```

**Repro:**

1. Host enters team A name `"Aces"` in the lobby UI but has not yet
   pressed Enter / blur (so `S.s.teamNames.A` is still `"Team A"` —
   the UI's text input has a local buffer that propagates only on
   blur or Enter).
2. A player's MSG_JOIN arrives. `_OnJoin`'s seat-grant branch fires
   `N.SendTeams(S.s.teamNames.A or "", …)` — broadcasting the **stale**
   name.
3. Receivers apply the stale name immediately; on a fast network,
   the late joiner now sees "Team A" forever (until the host changes
   the name and the broadcast happens again).
4. Worse — `S.ApplyTeamNames` persists into `WHEREDNGNDB.teamNames`
   on **every** receiver. The receiver's own next-session pre-fill is
   "Team A", overwriting whatever they had. Note: the persistence is
   gated on `if teamA and teamA ~= "" then …` so an empty-string
   broadcast doesn't overwrite, but a stale `"Team A"` (not empty)
   does.

**Quote of the empty-string filter** (`State.lua:165-166`):

```
if teamA and teamA ~= "" then s.teamNames.A = teamA:sub(1, 20) end
if teamB and teamB ~= "" then s.teamNames.B = teamB:sub(1, 20) end
```

The empty-string filter exists, but the issue is the *non-empty
default* `"Team A"` / `"Team B"` is broadcast even when the host
hasn't customized; the re-broadcast on join overwrites a receiver's
locally-customized cosmetic (which they shouldn't normally have, but
saved-vars hydration can produce one).

---

## MED — `_OnLobby` resets `peerVersions` when seeing a new game ID

**Severity:** MED — minor data loss but documented as a deliberate
trade-off (line 717 / 724).

**Code:**

`State.lua:710-727` (`S.ApplyLobby`):

```
local newGame = (s.gameID and s.gameID ~= "" and s.gameID ~= gameID)
             or (p == K.PHASE_SCORE or p == K.PHASE_GAME_END)
if newGame then
    local savedName   = s.localName
    local savedTarget = s.target
    local savedNames  = s.teamNames
    local savedPeers  = s.peerVersions
    local savedHost   = s.hostName
    local savedPend   = s.pendingHost
    S.Reset()
    s.localName     = savedName
    s.target        = savedTarget or s.target
    s.teamNames     = savedNames or s.teamNames
    s.peerVersions  = savedPeers or {}
    s.hostName      = savedHost
    s.pendingHost   = savedPend
end
```

The `peerVersions` table is preserved across the new-game `S.Reset()`,
which is correct. However, the preserved entries are keyed by
normalized sender names that may include peers from the **previous**
game who are no longer in the party. There is no GC pass.

**Repro:**

1. Player joins lobby A; peerVersions has 4 entries.
2. Game A ends; phase → GAME_END. Player joins lobby B (different
   gameID). The `newGame` branch preserves the 4 entries.
3. Lobby B has a different roster — say 3 of the 4 names overlap.
   Lobby B's join handshakes refresh those 3 entries. The 4th entry
   (a player who left) lingers indefinitely.

**Severity is low because** the lingering entries don't affect
networking decisions (they're only consulted by the UI lobby badge in
`UI.lua:2803-2811`). Eventually the entry is consulted only if that
former peer rejoins, which would refresh it.

---

## LOW — Version-tag stripping (D-RT-15 X9-4 contained but not exhaustively): empty `version` falls through to UI as "unknown"

**Severity:** LOW — UX-only.

**Code:**

`Net.lua:684-708` (`_OnHost`):

```
if version and version ~= "" then
    local skey = (S.NormalizeName and S.NormalizeName(sender)) or sender
    S.s.peerVersions[skey] = version
end
```

A peer whose `K.GetAddonVersion()` returns `""` (e.g., a hand-rolled
client that omits the version trailer) writes nothing to
`peerVersions`, and the UI badge for that peer reads as a missing
table entry — `nil` in `UI.lua:2803-2811` is rendered as no-color (or
default), distinguishable from an explicit "dev" returned by
`Constants.lua:153-156`:

```
if not meta or meta == "" or meta == "@project-version@" then
    return "dev"
end
```

So: a peer using the addon as-shipped reports `"dev"` (legitimate) or
a tagged version. A peer-without-version-trailer is a non-conforming
client — the lack of a UI distinguishment makes it invisible to the
host whether the peer is "dev unpackaged" vs "tampered/strip".

**Quote of the asymmetric filter** (`Net.lua:689`):

```
if version and version ~= "" then
```

(absent: `else` branch that records the peer as `"unknown"`)

---

## Handler-by-handler audit summary

| Handler | Wire frame | Authorization gate | Mutation |
|---|---|---|---|
| `_OnHost` | `H;gameID;version` | `not isHost`, phase passive | writes `peerVersions[sender]`, `pendingHost` |
| `_OnJoin` | `J;gameID;version` | `isHost` and PHASE_LOBBY, gameID match | writes `peerVersions[sender]`, calls `HostHandleJoin`, broadcasts SendLobby + SendTeams |
| `_OnLobby` | `L;gameID;n1;n2;n3;n4;mask;ver` | `not isHost`, PHASE in passive set; trust=fromHost OR pendingHost OR lastGameID match | writes `peerVersions[sender]`, calls `S.ApplyLobby` |
| `_OnTeams` | `t;A;B` | `not isHost`, fromHost(sender) | calls `S.ApplyTeamNames` |
| `_OnResyncReq` | `?;gameID` | **unreachable** due to CRIT-1 collision | (would call `SendResyncRes`) |
| `_OnOvercallResolve` | `?;taken;by;type` | `not isHost`, fromHost(sender) | clears `s.overcall`, sets `phase = PHASE_DOUBLE` |

---

## Recap by audit point (1-10)

1. **Host-announce broadcasts (with addon version trailing field)** —
   `Net.lua:88-93`. The trailer is parsed in `_OnHost` (line 689-692)
   and stored under normalized key. ✅ Mechanism present.

2. **Peer claims hostName via `WHEREDNGNDB.lastGameID` (D-RT-15
   X9-3 trade-off documented)** — see HIGH finding above. ⚠ Trade-off
   is in code (`Net.lua:750-757`); residual host-takeover hazard
   accepted.

3. **Seat reassignment race during lobby join** — see HIGH finding
   above. ⚠ Two race classes documented (un-normalized name eq;
   swap-then-join interleaving).

4. **Version-skew (D-RT-16) — recommendation: host-side seating gate
   in `_OnJoin`/`HostHandleJoin` rejecting peers below
   MIN_PEER_VERSION (set to v0.10.2 per M4 hard-block)** — **NOT
   implemented in any released version including v0.10.2**. See HIGH
   finding above. The peerVersions table is populated; no consumer
   reads it for gating. Action item: `K.MIN_PEER_VERSION = "0.10.2"`
   plus a `compareVersion` helper, called from `_OnJoin` before
   `S.HostHandleJoin`.

5. **M4 cross-version legality divergence (D-RT-16 #6
   hard-blocking)** — confirmed in HIGH finding above. The v0.9.6
   host's `R.IsLegalPlay` (5-param) marks v0.10.2 client's correct
   M4 discard `.illegal=true`. Score-affecting wrong-team Qaid.

6. **CRIT-1 wire tag collision exists in v0.7.0+ (introduced commit
   a3abe18)** — confirmed in CRIT finding above. Origin in
   `Constants.lua:181, 229`; collision in `Net.lua:543, 620`. Resync
   broken on the host receive path since v0.7.0.

7. **Peer-version table population at `Net.lua:691, 714, 764` (per
   D-RT-16)** — verified line-exact:
   - 691: `_OnHost` (line 684-708)
   - 714: `_OnJoin` (line 710-729)
   - 764: `_OnLobby` (line 731-767)

8. **teamNames broadcast (`_OnTeamNames`)** — wire is `K.MSG_TEAMS`
   (`"t"`); receiver is `_OnTeams` (`Net.lua:2461-2466`); apply is
   `S.ApplyTeamNames` (`State.lua:163-175`). Re-broadcast on every
   join (line 725-727). See MED finding for race exposure.

9. **Seat-claim authentication (anybody can claim?)** — see HIGH
   finding above. Gate is `gameID match + isHost + PHASE_LOBBY`. No
   per-peer pre-invitation list; any party member with the addon
   prefix can self-seat.

10. **Multiple-host race during HostAnnounce conflict** — see HIGH
    finding above. `_OnHost` last-writer-wins on `pendingHost`
    (`Net.lua:705`), no first-host-lock.

---

## Cross-reference to existing track findings

- **D-RT-15 CRIT-1** — same wire-tag collision; this audit re-confirms
  in scope of lobby/join handlers and adds the dispatch-line
  evidence.
- **D-RT-16 Change 9** — same collision, viewed through cross-version
  lens; this audit cross-references the v0.7.0 origin in commit
  `a3abe18`.
- **D-RT-16 Change 6** — M4 AKA-receiver legality divergence
  (HARD-BLOCKING). This audit confirms the missing `MIN_PEER_VERSION`
  enforcement.
- **D-RT-08 trust_asymmetry_audit** — separately documents the
  `fromHost` / `authorizeSeat` model. This audit notes that the
  seating layer (`_OnJoin` / `HostHandleJoin`) is *outside* that model
  — `authorizeSeat` only applies to per-seat actions, not to seat
  acquisition itself.

---

## Files referenced (absolute paths)

- `C:\CLAUDE\WHEREDNGN\Net.lua` — handlers `_OnHost`, `_OnJoin`,
  `_OnLobby`, `_OnTeams`, `_OnResyncReq`, `_OnOvercallResolve`;
  senders `SendHostAnnounce`, `SendJoin`, `SendLobby`, `SendTeams`,
  `SendResyncReq`; dispatcher `HandleMessage`; auth helpers
  `fromHost`, `authorizeSeat`, `normSender`, `fromSelf`.
- `C:\CLAUDE\WHEREDNGN\State.lua` — `s.peerVersions`, `s.seats`,
  `s.pendingHost`, `s.hostName`, `S.HostBeginLobby`, `S.HostHandleJoin`,
  `S.HostAddBots`, `S.HostKickSeat`, `S.HostSwapSeats`, `S.ApplyLobby`,
  `S.ApplyTeamNames`, `S.NormalizeName`, `S.SeatOf`.
- `C:\CLAUDE\WHEREDNGN\Constants.lua` — `K.MSG_HOST` (`"H"`),
  `K.MSG_JOIN` (`"J"`), `K.MSG_LOBBY` (`"L"`), `K.MSG_TEAMS` (`"t"`),
  `K.MSG_RESYNC_REQ` (`"?"`), `K.MSG_OVERCALL_RESOLVE` (`"?"`),
  `K.LOBBY_BROADCAST_SEC` (3.0), `K.GetAddonVersion`.
- `C:\CLAUDE\WHEREDNGN\WHEREDNGN.toc` — `## Version: @project-version@`.
- `C:\CLAUDE\WHEREDNGN\.swarm_findings\review_v0.10.2\_track_D_redteam\D-RT-15_wire_malformed.md`
  — CRIT-1 origin documentation.
- `C:\CLAUDE\WHEREDNGN\.swarm_findings\review_v0.10.2\_track_D_redteam\D-RT-16_version_skew.md`
  — cross-version skew analysis and seating-gate recommendation.

---

## Summary of action items (NO CODE CHANGES — task scope is audit only)

| Severity | Issue | Suggested fix | File:Line |
|---|---|---|---|
| CRIT | Wire-tag `"?"` collision | Rename `K.MSG_OVERCALL_RESOLVE` (or `K.MSG_RESYNC_REQ`) to a free single-byte tag | `Constants.lua:181, 229`; `Net.lua:543, 620` |
| HIGH | No version-skew seating gate | Add `K.MIN_PEER_VERSION = "0.10.2"` + version comparator; gate in `_OnJoin` before `HostHandleJoin` | `Net.lua:716-718`; `State.lua:624-639` |
| HIGH | `lastGameID`-based host adoption | Augment with sender allowlist or limit trust path (c) to recently-active hosts | `Net.lua:750-757` |
| HIGH | Multiple-host race | First-heard `pendingHost` wins until user clears | `Net.lua:705` |
| HIGH | Seat reassignment race | Use `nameEq` helper instead of raw `info.name == name` | `State.lua:629` |
| HIGH | Anybody can claim seat | Add party-roster gate or pre-invite allowlist in `_OnJoin` | `Net.lua:710-729` |
| MED | teamNames re-broadcast race | Skip rebroadcast when teamNames are at default values | `Net.lua:725-727` |
| MED | peerVersions GC | Drop entries not in current `s.seats` after Reset | `State.lua:716-727` |
| LOW | Version-tag stripping | Record stripped peers as `"unknown"` for UI distinguishability | `Net.lua:689, 712, 763` |

**Out of scope per task instruction: no code modified. Findings above
are advisory and do not constitute a patch plan; they document
existing risk surface only.**
