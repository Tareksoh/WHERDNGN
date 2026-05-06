# D-RT-15 — Wire-level red-team of Net.lua malformed-message handling

**Scope:** `C_ChatInfo.SendAddonMessage` frame handling on the receive
path. We probe every `_On*` handler in `Net.lua` for tolerance to
malformed payloads, missing fields, type-coerced fields,
empty-string fields, bidder-seat injection (out-of-range / non-table
seats), forged source (peer claiming to be host), MSG_RESYNC_RES
injection (verifying the v0.9.1 L5 fix), version-tag stripping, and
WHISPER vs PARTY scope leak.

**Read:** `Net.lua` 1-200, 200-3220 (all `_On*` handlers, `split`,
`HandleMessage`, `authorizeSeat`, `fromHost`, `fromSelf`,
`normSender`); `Constants.lua` `K.MSG_*` definitions;
`State.lua` Apply functions for cross-checks.

**Method:** for each handler, walk the dispatch path from
`HandleMessage` → handler → `S.Apply*` and red-team against the
attack patterns. Code is quoted verbatim with `Net.lua:LINE`
provenance. **No code modified.**

---

## Critical findings (BLOCKER class)

### CRIT-1 — MSG_RESYNC_REQ tag collides with MSG_OVERCALL_RESOLVE; resync-on-host is dead

`Constants.lua:181` and `Constants.lua:229`:

```
K.MSG_RESYNC_REQ = "?" -- request state from host
…
K.MSG_OVERCALL_RESOLVE  = "?"  -- v0.7 host announces the overcall window
```

Both tags are the literal `"?"`. The dispatcher in `HandleMessage`
checks them in this order (`Net.lua:543` first, `Net.lua:620`
later):

```
elseif tag == K.MSG_OVERCALL_RESOLVE then
    N._OnOvercallResolve(sender, fields[2], tonumber(fields[3]),
                         fields[4])
…
elseif tag == K.MSG_RESYNC_REQ then
    N._OnResyncReq(sender, fields[2])
```

**Effect:** every `"?"` frame routes to `_OnOvercallResolve` and
`_OnResyncReq` is unreachable. A late-joiner who sends `MSG_RESYNC_REQ`
gets:

1. The host runs `_OnOvercallResolve` with `fields[2]` interpreted
   as `takenStr` (in reality their gameID), `fields[3]` (empty)
   coerced to `nil` for `by`, `fields[4]` (nil) for `otype`.
2. `_OnOvercallResolve` (`Net.lua:1123`) is gated by
   `if not fromHost(sender) then return end`, so for a non-host
   sender it bails out — **but** if the rejoiner happens to be the
   stored `s.hostName` from a prior session (lastGameID match
   path) the gate could pass and a stale rejoiner could clobber
   `S.s.overcall = nil; S.s.phase = K.PHASE_DOUBLE` on the
   real host.
3. The legitimate resync flow never fires, so a rejoiner stays
   soft-locked indefinitely. The 30-second `expectingResyncRes`
   window then expires with no response, and the v0.9.1 L5 guard
   then permanently rejects late host responses.

This is a **BLOCKER**: the entire mid-game-rejoin feature is broken
on the wire whenever `K.MSG_OVERCALL_RESOLVE` is also in the tag
table. Any code path that does
`broadcast(("%s;%s"):format(K.MSG_RESYNC_REQ, gameID))` produces a
frame indistinguishable from an overcall-resolve announcement.

**Quote of the dispatch ambiguity** (single-character tag, no
length-disambiguator): `Net.lua:489-490`:

```
local fields = split(message, ";")
local tag = fields[1]
```

The split is purely on `;`, so the tag is whatever string preceded
the first `;`. Both `"?"` strings are equivalent.

**Mitigation requires a code change** (rename one of the two tags).
Per task scope, no fix applied — flagged as discrepancy.

---

### CRIT-2 — `_OnOvercallResolve` silently demotes phase even with no payload

`Net.lua:1123`:

```
function N._OnOvercallResolve(sender, takenStr, by, otype)
    if fromSelf(sender) then return end
    if not fromHost(sender) then return end
    if S.s.isHost then return end
    …
    S.s.overcall = nil
    S.s.phase = K.PHASE_DOUBLE
```

There is **no payload validation**. A frame `"?"` with all fields
nil is accepted as long as `sender == hostName`. A peer who has
been promoted to `s.hostName` via the lobby-takeover path
(`_OnLobby`'s `lastGameID` branch, `Net.lua:750-757`) can broadcast
a single `"?"` and force every other client into `PHASE_DOUBLE`
mid-trick — including during PHASE_PLAY, where `S.s.contract` may
still be valid but `s.overcall` was never set.

Combined with **CRIT-1**, ANY `MSG_RESYNC_REQ` from the host
themselves hits this path on every other client and forcibly
rewrites their phase to DOUBLE. (The host calling `_OnResyncReq`
on themselves is gated by `fromSelf`, but the `MSG_RESYNC_REQ`
payload is `tag;gameID` — the `tag == "?"` wins overcall-resolve
routing on every other client first.)

**Severity:** HIGH. Ties to CRIT-1 — the same tag collision is the
attack vector and the symptom is the silent phase-rewrite.

---

## Per-handler results

Each row: handler → attack pattern → result, with code-quote
evidence. **PASS** = the gate stops the attack. **FAIL** = the
attack lands. **N/A** = pattern doesn't apply.

### `_OnHost` (host-announce, `Net.lua:684`)

```
function N._OnHost(sender, gameID, version)
    if fromSelf(sender) then return end
    if version and version ~= "" then
        local skey = (S.NormalizeName and S.NormalizeName(sender)) or sender
        S.s.peerVersions[skey] = version
    end
    if S.s.isHost then return end
    local p = S.s.phase
    if p ~= K.PHASE_IDLE and p ~= K.PHASE_LOBBY
       and p ~= K.PHASE_SCORE and p ~= K.PHASE_GAME_END then
        return
    end
    S.s.pendingHost = { name = sender, gameID = gameID }
```

| Attack | Result | Notes |
|---|---|---|
| Field-count tolerance (extra trailing fields) | PASS | Extra fields are split into the array but never read. |
| Field-count tolerance (missing version) | PASS | `if version and version ~= ""` short-circuits the `peerVersions` write. |
| Empty `gameID` | **FAIL (mild)** | An empty gameID gets stashed into `S.s.pendingHost.gameID = ""`. Later `_OnLobby` matches `gameID==""` against an empty pendingHost match (`pendingHost.gameID == gameID`), allowing host-binding for an empty gameID. Cosmetic — `_OnJoin` rejects `gameID ~= S.s.gameID` mismatches but the local lobby UI may show stale state. |
| Type coercion | N/A | `gameID` is a string, no `tonumber`. |
| Forged source (peer claiming to be host) | **FAIL (by design, but risky)** | Any peer can announce themselves as a candidate host while we're in IDLE/LOBBY/SCORE/GAME_END. `pendingHost` is overwritten on every received frame. A hostile peer can race the legitimate host's announce and grief the lobby gate. The actual hostName binding happens in `_OnLobby` and the X9-3 fix at `Net.lua:740-757` mitigates by requiring either pendingHost or trustGameID. **This handler itself does not gate sender authority** — that's intentional (host hasn't been chosen yet) but means the door is open during the passive phases. |

---

### `_OnJoin` (`Net.lua:710`)

```
function N._OnJoin(sender, gameID, version)
    if fromSelf(sender) then return end
    if version and version ~= "" then …
    if not S.s.isHost or S.s.phase ~= K.PHASE_LOBBY then return end
    if gameID ~= S.s.gameID then return end
    local seat = S.HostHandleJoin(sender)
```

| Attack | Result |
|---|---|
| Field-count tolerance | PASS — extra fields ignored, missing version short-circuits. |
| Empty gameID | PASS — `gameID ~= S.s.gameID` fails on `"" ~= "active-id"`. |
| Forged source | PASS — `S.HostHandleJoin(sender)` uses `sender` as roster name, but `s.phase==LOBBY` is the only phase where this is meaningful. |

---

### `_OnLobby` (`Net.lua:731`)

```
function N._OnLobby(sender, gameID, names, botMask, hostVersion)
    if fromSelf(sender) then return end
    if S.s.isHost then return end           -- 12th-audit X
    if not fromHost(sender) and not S.s.pendingHost then
        local trustGameID = (WHEREDNGNDB and WHEREDNGNDB.lastGameID == gameID)
        if trustGameID then
            S.s.hostName = sender
        end
    elseif S.s.pendingHost and S.s.pendingHost.gameID == gameID then
        S.s.hostName = sender
    end
    …
    S.ApplyLobby(gameID, names, botMask)
```

`HandleMessage` builds names with **defaulted-to-empty fields**
(`Net.lua:498-500`):

```
N._OnLobby(sender, fields[2],
    { fields[3] or "", fields[4] or "", fields[5] or "", fields[6] or "" },
    fields[7], fields[8])
```

| Attack | Result | Notes |
|---|---|---|
| Field-count tolerance (N+1 extra) | PASS — surplus fields ignored. |
| Field-count tolerance (N-1 missing seats) | PASS — empty strings fall through to `if n and n ~= ""` in `ApplyLobby` (`State.lua:732`). |
| Empty `botMask` | PASS — `botMask:sub(i,i) == "1"` on empty string returns false; all seats default to non-bot. |
| Type coercion | N/A — names are raw strings. |
| Bidder-seat injection (seat 5+) | N/A — only 4 seats are read regardless of how many fields come over the wire. |
| **Forged source: peer claims to be host while we have NO pendingHost** | **FAIL (mitigated)** | If `WHEREDNGNDB.lastGameID == gameID`, `S.s.hostName = sender` runs even though `sender` may be an unrelated party member. The X9-3 comment acknowledges this is a deliberate trade-off. A hostile peer who knows our `lastGameID` (e.g. has been in our previous lobby) can forge a `MSG_LOBBY` frame with the matching gameID and claim hostName. From there the rest of `_On*Host*` accepts their broadcasts. |
| MSG_LOBBY with **botMask of length > 4** | PASS — `:sub(i,i)` only reads positions 1-4. |
| **Empty seatNames + valid botMask** | **FAIL (subtle)** | `S.ApplyLobby` clears all seats (`s.seats[i] = nil`). A peer can blank the local roster mid-lobby with a forged MSG_LOBBY (mitigated by the `if not passive then return end` gate at `State.lua:703` — only IDLE/LOBBY/SCORE/GAME_END accept). |

---

### `_OnStart` (`Net.lua:769`)

```
function N._OnStart(sender, roundNumber, dealer)
    if fromSelf(sender) then return end
    if not fromHost(sender) then return end
    if S.s.isHost then return end
    S.ApplyStart(roundNumber, dealer)
```

| Attack | Result | Notes |
|---|---|---|
| Type coercion: `roundNumber="abc"` | **FAIL** | `tonumber("abc") = nil`. `S.ApplyStart(nil, …)` is reached. State.lua's ApplyStart was not read in detail here, but the function signature accepts nil and may write `s.roundNumber = nil`, which would then break every `forRound < s.roundNumber` guard in `S.ApplyHand`. **Recommend explicit `if not roundNumber or not dealer then return end` gate at handler entry.** |
| Type coercion: `dealer="abc"` | Same as above. |
| Field count: missing both | Same as above. |
| Forged source | PASS — `fromHost` gate. |
| Negative `roundNumber` | **FAIL (by omission)** | `tonumber("-5") = -5`. No range check. State may accept a negative round and then fail every `forRound < s.roundNumber` test. |
| Out-of-range `dealer` (5,6,…,99) | **FAIL** | No range check; `S.ApplyStart` may store dealer=99 then later `(dealer % 4) + 1` arithmetic still works (so this is largely cosmetic) but a `dealer=0` produces `(0%4)+1 = 1`, which silently overrides the actual dealer. |

---

### `_OnDealPhase` (`Net.lua:783`)

```
elseif phase == "redeal" then
    local nextDealer = tonumber(extra)
    S.ApplyRedealAnnouncement(nextDealer)
```

| Attack | Result | Notes |
|---|---|---|
| Field-count tolerance | PASS — `extra` is read only on `phase=="redeal"`. |
| Type coercion: `extra="abc"` | **FAIL (mild)** | `tonumber("abc")=nil` → `S.ApplyRedealAnnouncement(nil)`. Whether that's safe depends on the apply function (not audited inline). |
| Forged source | PASS — `fromHost` gate. |
| Empty `phase` | PASS — none of the four `phase=="X"` branches fire. |
| Phase string with leading space `" 1"` | PASS by failure — `" 1" ~= "1"` so the comparison drops. |

---

### `_OnHand` (`Net.lua:811`)

```
function N._OnHand(sender, encodedCards, forRound)
    if fromSelf(sender) then return end
    if not fromHost(sender) then return end
    if S.s.isHost then return end
    S.ApplyHand(C.DecodeHand(encodedCards), forRound)
```

| Attack | Result | Notes |
|---|---|---|
| **WHISPER vs PARTY scope leak** | **PASS (with caveat)** | Hands are sent via `whisper(target, …)` (`Net.lua:127`). `HandleMessage`'s `channel` parameter is logged but **not validated** (`Net.lua:486, 491`). A malicious host could send the same `MSG_HAND` payload over PARTY instead of WHISPER, leaking another player's hand to all four. The receiver does NOT check that `channel == "WHISPER"`. **Cosmetic risk on the read side, but a malicious sender doesn't need addon-level cooperation to leak — they can already see all four hands as host.** Still, defense-in-depth: a non-host who somehow forges `fromHost` (impossible without name spoofing, but) could broadcast an encoded hand to PARTY and overwrite every receiver's `s.hand` via `S.ApplyHand`. |
| Empty encoded cards | PASS-ish | `C.DecodeHand("")` returns `{}` (empty hand). `S.ApplyHand({}, forRound)` then sets `s.hand = {}`. Combined with `forRound = nil` (legacy path at `Net.lua:511`), no stale-round guard fires, and the local hand gets wiped. **A forged whisper with `"h;1;"` and `forRound = current` would wipe the receiver's hand mid-hand.** Mitigated by `fromHost` gate, but if name-spoofing landed it would land. |
| Stale-round whisper | PASS — `S.ApplyHand`'s `if forRound < s.roundNumber then return` (`State.lua:828-830`). |
| Type coercion: `forRound="abc"` | PASS — `tonumber("abc")=nil`, the legacy single-field path is taken (`Net.lua:511`), which is intended back-compat behavior. |

---

### `_OnBidCard` (`Net.lua:821`)

```
if fromSelf(sender) then return end
if not fromHost(sender) then return end
if S.s.isHost then return end
S.ApplyBidCard(card)
```

| Attack | Result |
|---|---|
| Empty card | PASS — `S.ApplyBidCard("")` stores empty string. UI's truthy check would treat empty string as truthy (it does in Lua). The `SendBidCard` defensive coalescing at `Net.lua:148` was specifically the Cl22 audit fix, but the receiver does NOT validate. **MILD FAIL**: a forged `"b;"` (no card) sets `s.bidCard = nil` (split returns "", but `fields[2]=""`); UI may render an empty card slot. |
| Forged source | PASS — `fromHost` gate. |

---

### `_OnTurn` (`Net.lua:828`)

```
if fromSelf(sender) then return end
if not fromHost(sender) then return end
if S.s.isHost then return end
if not seat then return end
S.ApplyTurn(seat, kind)
```

| Attack | Result |
|---|---|
| Bidder-seat injection (seat=9) | **FAIL** | `if not seat then return end` accepts any non-nil number including 9, 0, -1, 99. `S.ApplyTurn(9, kind)` will store `s.turn=9`. Later `(turn % 4) + 1` arithmetic in `_HostStepPlay` produces 2 from `9%4+1=2`, silently corrupting the turn machinery. **Recommend `if not seat or seat < 1 or seat > 4 then return end`** — same gate already used in `_OnSWA / _OnSWAReq / _OnAKA` (`Net.lua:2642, 2811, 3077`). |
| Type coercion: `seat="abc"` | PASS — `tonumber=nil`, gate fires. |
| Empty `kind` | PASS-ish | `S.ApplyTurn(seat, "")` — kind becomes empty. Downstream `s.turnKind == "play"` checks fail for `""`, so plays will be silently dropped. Cosmetic break. |
| Forged source | PASS — `fromHost`. |

---

### `_OnBid` (`Net.lua:836`)

```
function N._OnBid(sender, seat, bid)
    if fromSelf(sender) then return end
    if not seat or not bid then return end
    if S.s.phase ~= K.PHASE_DEAL1 and S.s.phase ~= K.PHASE_DEAL2BID then return end
    if S.s.turn ~= seat or S.s.turnKind ~= "bid" then return end
    if S.s.bids and S.s.bids[seat] ~= nil then return end
    if not authorizeSeat(seat, sender) then return end
    S.ApplyBid(seat, bid)
```

| Attack | Result |
|---|---|
| Bidder-seat injection (seat=9) | PASS — `S.s.turn ~= seat` rejects (turn is in 1-4). The phase + turn gate is doing the work that an explicit range check would. |
| Authority forge | PASS — `authorizeSeat`. |
| Empty `bid=""` | PASS-ish | `not bid` is false for `""` (empty string is truthy in Lua). `S.ApplyBid(seat, "")` is reached. `S.ApplyBid` at `State.lua:889-928` writes `s.bids[seat] = ""` and runs `bid:sub(1, #K.BID_HOKM) == K.BID_HOKM` which on an empty string returns false-but-no-crash. **Cosmetic break**: UI may render the empty bid as "PASS" or similar. |
| Bid string `"HOKM_X"` (invalid trump) | **FAIL (no validation)** | The handler doesn't validate the bid format. `S.ApplyBid` stores it verbatim. Later `S.HostAdvanceBidding` may use it. Mitigated by phase+turn ordering — a malformed bid usually causes the bidder to be skipped — but not authoritatively. |
| Idempotence | PASS — `s.bids[seat] ~= nil`. |

---

### `_OnContract` (`Net.lua:852`)

```
if fromSelf(sender) then return end
if not fromHost(sender) then return end
if S.s.isHost then return end
if not bidder or not btype then return end
S.ApplyContract(bidder, btype, trump)
```

| Attack | Result |
|---|---|
| Bidder-seat injection (bidder=9) | **FAIL** | `if not bidder` rejects nil, accepts 9. `S.ApplyContract(9, …)` runs `(9 == 1 or 9 == 3)` test (`State.lua:1063`) — false → defenders=`{1,3}`. The bidder's seat is recorded as 9. Later `(contract.bidder % 4) + 1 = (9%4)+1 = 2` produces a wrong defender for Bel/Triple/Four windows. Severity: HIGH if reached, but MITIGATED by the `fromHost` gate. |
| `btype="GARBAGE"` | **FAIL (silent)** — `S.ApplyContract` stores it. Subsequent `c.type == K.BID_HOKM`/`K.BID_SUN` checks all fail, leaving the contract neither — UI/Bot logic may mis-render or no-op. |
| Empty `trump=""` | PASS — handled at `State.lua:1033`: `local trumpNorm = (trump ~= "" and trump) or nil`. |
| Type coercion `bidder="abc"` | PASS — gate fires. |

---

### `_OnDouble` (`Net.lua:860`)

```
if fromSelf(sender) then return end
if not seat then return end
if not S.s.contract or S.s.contract.doubled then return end
if S.s.phase ~= K.PHASE_DOUBLE then return end
local eligibleSeat = (S.s.contract.bidder % 4) + 1
if seat ~= eligibleSeat then return end
if not authorizeSeat(seat, sender) then return end
```

| Attack | Result |
|---|---|
| Bidder-seat injection (seat=9) | PASS — `seat ~= eligibleSeat` (eligibleSeat ∈ 1..4). |
| Authority forge | PASS — `authorizeSeat`. |
| Idempotence | PASS — `S.s.contract.doubled` guard. |
| Phase forge | PASS — phase gate. |
| Open/closed flag | PASS — `(openField == nil) or (openField ~= "0")`; defaults open=true safely. |
| Empty `openField=""` | PASS — `""` ~= `"0"` so default open. |

---

### `_OnTriple` (`Net.lua:915`), `_OnFour` (`Net.lua:931`), `_OnGahwa` (`Net.lua:948`)

Symmetric to `_OnDouble` — all share the same gate pattern. All
PASS the seat-injection / authority / phase / idempotence patterns.

---

### `_OnPreempt` / `_OnPreemptPass` (`Net.lua:962, 993`)

```
function N._OnPreempt(sender, seat)
    if fromSelf(sender) then return end
    if not seat then return end
    if S.s.phase ~= K.PHASE_PREEMPT then return end
    if not S.s.preemptEligible then return end
    local eligible = false
    for _, s2 in ipairs(S.s.preemptEligible) do
        if s2 == seat then eligible = true; break end
    end
    if not eligible then return end
    if not authorizeSeat(seat, sender) then return end
```

| Attack | Result |
|---|---|
| Bidder-seat injection (seat=9) | PASS — eligibility membership check. |
| **`_OnPreemptPass` seat=0 special case** | PASS-ish | Seat=0 is the host's "window open" frame and requires `fromHost(sender)` (`Net.lua:1004`). The CSV is parsed via `eligCsv:gmatch("(%d+)")` and clamped `v >= 1 and v <= 4`. Multi-digit numbers like `12` would match the regex but be rejected by the range gate. **Subtle FAIL**: the regex `(%d+)` is greedy on digits, so `"1,12,3"` parses as `[1,12,3]` then drops `12` — preserving `[1,3]`. Same as expected. |
| Forged source for seat=0 | PASS — `fromHost` gate. |

---

### `_OnSkipDouble / Triple / Four / Gahwa` (`Net.lua:1313-1352`)

Each gates on phase + eligible seat + `authorizeSeat`. All PASS.

---

### `_OnMeld` (`Net.lua:1354`)

```
if fromSelf(sender) then return end
if not seat or not kind then return end
local isReplay = (replayFlag == "1") and fromHost(sender)
if isReplay and S.s.isHost then return end
if S.s.phase ~= K.PHASE_PLAY and S.s.phase ~= K.PHASE_DEAL3 then return end
if not isReplay and not authorizeSeat(seat, sender) then return end
S.ApplyMeld(seat, kind, suit, top, encodedCards)
```

| Attack | Result |
|---|---|
| Bidder-seat injection (seat=9) | **FAIL** | `if not seat` rejects nil only. `S.ApplyMeld(9, …)` runs `R.TeamOf(9)` which would yield nil, then `s.meldsByTeam[nil] = …` would error or overwrite. **State.lua:1155**: `local team = R.TeamOf(seat)` — if R.TeamOf is hardened to clamp 1..4, this is OK; otherwise this is a wire-side hole. **Recommend explicit seat range check at handler.** |
| Replay forge | PASS — `replayFlag == "1"` AND `fromHost` AND non-host receiver. |
| Empty `kind` | PASS — `if not seat or not kind then return end`. (`""` is truthy in Lua, so `not kind` is false for `""`. Wait — re-reading: `not ""` is `false`. So empty string PASSES the not-kind check.) **MILD FAIL**: `kind=""` passes the gate. `S.ApplyMeld(seat, "", suit, top, enc)` then runs the `kind == "seq3"` etc. branch chain which all fail — `value` stays nil → `if not value then return end` short-circuits at `State.lua:1184`. So this self-defends. PASS in practice. |
| Forged `kind="carre"` with `top="A"` in Sun (no actual Aces) | **FAIL** | `S.ApplyMeld` does NOT verify `encodedCards` actually contains a four-of-Aces. It writes the meld with the host-supplied value directly. A peer claiming an Ace-carré in Sun adds 400 raw to their team's meld pile. **MITIGATED by `authorizeSeat`** — the seat owner is the only one who can forge their own meld, and the host's hostHands cross-check happens elsewhere. But on the wire, content is trusted. |

---

### `_OnPlay` (`Net.lua:1375`)

The complex case. Quote:

```
if fromSelf(sender) then return end
if not seat or not card then return end
if S.s.phase ~= K.PHASE_PLAY then return end
local isReplay = (replayFlag == "1") and fromHost(sender)
if isReplay and S.s.isHost then return end
if not isReplay then
    if S.s.turnKind ~= "play" then return end
    if S.s.turn ~= seat then
        if not fromHost(sender) and not authorizeSeat(seat, sender) then
            return
        end
        S.s.turn     = seat
        S.s.turnKind = "play"
    end
end
…
if S.s.trick and S.s.trick.plays then
    for _, p in ipairs(S.s.trick.plays) do
        if p.seat == seat then return end
    end
end
if not isReplay and not fromHost(sender)
   and not authorizeSeat(seat, sender) then return end
…
S.ApplyPlay(seat, card)
```

| Attack | Result |
|---|---|
| Bidder-seat injection (seat=9) | **FAIL (caveat)** | `if not seat` accepts 9. `S.s.turn ~= seat` is true (turn ∈ 1..4), so the self-heal branch fires. Without `fromHost`, `authorizeSeat(9, sender)` looks up `S.s.seats[9]` — `info` is nil → `return false`. So a non-host attacker is blocked. **A forged-host frame with seat=9** would set `S.s.turn = 9; S.s.turnKind = "play"` then idempotence-check passes and `S.ApplyPlay(9, card)` is reached — corrupting the trick. **MITIGATED only by `fromHost`**. Recommend explicit seat range check (paralleling `_OnSWA`'s gate at `Net.lua:2811`). |
| Empty `card=""` | PASS-ish | `not card` is false for `""` so not blocked. `S.ApplyPlay(seat, "")` — depends on whether ApplyPlay validates length. The trick decoder at `Net.lua:1487` uses `card and #card == 2` so MSG_TRICK at least gates length, but MSG_PLAY does not. |
| Replay forge | PASS — replayFlag+fromHost+non-host receiver. |
| Self-heal turn-pointer hijack | **CONCERN** | The self-heal block at `Net.lua:1421-1431` rewrites `S.s.turn = seat` if `fromHost` OR `authorizeSeat`. A peer who forges fromHost (impossible w/o name match, but…) can hijack turn-state. Mitigated by `authorizeSeat` requiring host-name for bot seats AND seat-owner-name for human seats. PASS under `authorizeSeat` semantics. |

---

### `_OnTrick` (`Net.lua:1474`)

```
if fromSelf(sender) then return end
if not fromHost(sender) then return end
if S.s.isHost then return end
if encPlays and #encPlays >= 3 then
    local plays = {}
    for i = 1, #encPlays, 3 do
        local card = encPlays:sub(i, i + 1)
        local seat = tonumber(encPlays:sub(i + 2, i + 2))
        if card and #card == 2 and seat and seat >= 1 and seat <= 4 then
            plays[#plays + 1] = { seat = seat, card = card }
        end
    end
```

| Attack | Result |
|---|---|
| Forged source | PASS — `fromHost`. |
| Bad encPlays length (`#encPlays = 4`, not divisible by 3) | PASS — sub-slicing reads what's there; trailing partial chunk parses to invalid card/seat and is filtered. |
| Bidder-seat injection in encPlays (`seat=9`) | PASS — explicit `seat >= 1 and seat <= 4` check (this is the only handler that does this gate). **The pattern that `_OnPlay/_OnTurn/_OnContract/_OnMeld` should follow.** |

---

### `_OnRound` (`Net.lua:1503`)

```
if fromSelf(sender) then return end
if not fromHost(sender) then return end
if S.s.isHost then return end
S.ApplyRoundEnd(addA, addB, totA, totB, sweep, bidderMade)
```

| Attack | Result |
|---|---|
| Forged source | PASS — `fromHost`. |
| Type coercion (`addA="abc"`) | **FAIL (silent)** | `tonumber=nil`. `S.ApplyRoundEnd(nil, …)` is reached. State.ApplyRoundEnd was not audited inline but a nil add would corrupt cumulative tracking. |
| Negative deltas | **FAIL** | `addA = -9999` is accepted. `S.ApplyRoundEnd` may then write `cumulative.A = current + -9999`, allowing a malicious host to negative-score the receiver's display. (Host is server-of-truth, so this is largely cosmetic — but a name-spoofed peer could grief.) |

---

### `_OnGameEnd` (`Net.lua:1510`)

```
if fromSelf(sender) then return end
if not fromHost(sender) then return end
if S.s.isHost then return end
S.ApplyGameEnd(winner)
```

PASS the source-forge gate. Empty `winner=""` would set
`s.gameEndWinner = ""` — cosmetic.

---

### `_OnTakweesh` / `_OnTakweeshOut` (`Net.lua:2079, 2091`)

```
function N._OnTakweesh(sender, callerSeat)
    if fromSelf(sender) then return end
    if not callerSeat then return end
    if S.s.phase ~= K.PHASE_PLAY then return end
    if not authorizeSeat(callerSeat, sender) then return end
```

| Attack | Result |
|---|---|
| Bidder-seat injection (callerSeat=9) | **FAIL (mitigated)** | `authorizeSeat(9, sender)` returns false (seat 9 has no entry). PASS in practice — the gate works **only** because `S.s.seats[9]` is nil. If an attacker also forged a MSG_LOBBY adding seat 9 (impossible — seats array only has 1-4 slots), this would land. PASS under current data model. |
| Forged source | PASS. |

`_OnTakweeshOut` (`Net.lua:2091`):

```
local cName = S.s.seats[callerSeat] and (S.s.seats[callerSeat].name:match …
```

| Attack | Result |
|---|---|
| `callerSeat=nil` (missing field) | PASS-ish | `S.s.seats[nil]` returns nil; `cName = "?"` fallback. No crash. The print fires with `"?"` — cosmetic only. |
| `callerSeat=9` (out of range) | PASS — `S.s.seats[9]=nil`, falls back to `"?"`. |
| Empty `card=""` | PASS — `if card and #card >= 2 then` gates the rank/glyph extraction. |
| Empty `reason=""` | PASS — explicitly checked: `(reason ~= nil and reason ~= "") and reason or "illegal play"`. |

---

### `_OnPause` (`Net.lua:2452`)

```
if fromSelf(sender) then return end
if not fromHost(sender) then return end
if S.s.isHost then return end
local paused = (payload == "1")
if S.s.paused == paused then return end
S.ApplyPause(paused)
```

| Attack | Result |
|---|---|
| Forged source | PASS — `fromHost`. |
| Empty/malformed payload | PASS — anything not `"1"` decodes as `false`. Idempotence guard. |

---

### `_OnTeams` (`Net.lua:2461`)

```
if fromSelf(sender) then return end
if not fromHost(sender) then return end
if S.s.isHost then return end
S.ApplyTeamNames(teamA, teamB)
```

| Attack | Result |
|---|---|
| Forged source | PASS. |
| **Empty teamA/teamB** | PASS-ish | `S.ApplyTeamNames("", "")` — depends on impl, but likely defaults. Cosmetic. |
| **Long team name (denial-of-service via 200-char team name)** | **MILD CONCERN** | UI text may overflow. Wire-byte limit (255) is the only cap. |

---

### `_OnAKA` (`Net.lua:3075`)

```
if fromSelf(sender) then return end
if not seat or seat < 1 or seat > 4 then return end
if not suit or suit == "" then return end
local isReplay = (replayFlag == "1") and fromHost(sender)
if isReplay and S.s.isHost then return end
if not isReplay and not authorizeSeat(seat, sender) then return end
if S.s.phase ~= K.PHASE_PLAY then return end
if not S.s.contract or S.s.contract.type ~= K.BID_HOKM then return end
S.ApplyAKA(seat, suit)
```

| Attack | Result |
|---|---|
| Bidder-seat injection (seat=9) | PASS — explicit range gate. **Best-in-class pattern.** |
| Empty suit | PASS — explicit check. |
| Forged AKA on non-Hokm | PASS — Hokm-only gate. |
| Replay forge | PASS. |
| Authority forge | PASS — `authorizeSeat`. |

---

### `_OnSWA` / `_OnSWAReq` / `_OnSWAResp` / `_OnSWAOut` (`Net.lua:2640-2845`)

```
function N._OnSWAReq(sender, seat, encodedHand)
    if fromSelf(sender) then return end
    if not seat or seat < 1 or seat > 4 then return end
    if S.s.phase ~= K.PHASE_PLAY then return end
    if not authorizeSeat(seat, sender) then return end
    …
    if S.s.swaRequest and S.s.swaRequest.caller then return end
```

| Attack | Result |
|---|---|
| Bidder-seat injection | PASS — explicit range gate. |
| Empty hand | PASS-ish | `(encodedHand and (#encodedHand / 2)) or 0` — handCount=0. The 6th-audit overwrite-guard at `Net.lua:2653` rejects a duplicate request, so a follow-up real claim fails. **CONCERN**: a forged empty-hand SWA blocks legitimate SWAs for the rest of the round. |
| Forged source | PASS — `authorizeSeat`. |

`_OnSWAResp` (`Net.lua:2735`):

```
if sender ~= "__host__" then
    if fromSelf(sender) then return end
    if not authorizeSeat(responder, sender) then return end
end
local req = S.s.swaRequest
if not req or req.caller ~= caller then return end
if not responder or R.TeamOf(responder) == R.TeamOf(caller) then return end
```

| Attack | Result |
|---|---|
| `__host__` synthetic sender from wire | **FAIL (subtle)** | The wire frame `"O;<resp>;<acc>;<caller>"` arrives via `HandleMessage` with `sender = <party-member-name>`. `__host__` is a sentinel used only for in-process calls (`Net.lua:2531, 2604, 2683`) — **the wire path always reaches the `if sender ~= "__host__"` true branch**. PASS in practice; the sentinel string would only collide if a player named themselves `__host__-Realm`, which WoW name validation prevents (no underscores). |
| Bidder-seat injection (responder=9) | PASS-ish | `not responder` is false for 9 (truthy). `R.TeamOf(9)` may return nil or error; if nil, the `R.TeamOf(responder) == R.TeamOf(caller)` test compares nil-to-A/B → false → handler proceeds. **Then `req.responses[9] = accept`** — corrupts the request struct (mostly inert because `accepts >= 2` only counts seats 1..4). **Recommend explicit responder range gate.** |
| Authority forge | PASS — `authorizeSeat`. |

`_OnSWAOut` (`Net.lua:2829`): forged-source PASS via `fromHost`.

---

### `_OnResyncReq` (`Net.lua:3109`) — verifying v0.9.1 L5 fix

```
if fromSelf(sender) then return end
if not S.s.isHost then return end
if not gameID or gameID == "" then return end
if S.s.gameID ~= gameID then return end
…
local nsender = normSender(sender)
do
    local key = nsender or sender
    local now = (GetTime and GetTime()) or 0
    local last = _resyncCooldown[key] or 0
    if (now - last) < RESYNC_COOLDOWN_SEC then return end
    _resyncCooldown[key] = now
end
…
local found = false
for i = 1, 4 do
    local info = S.s.seats[i]
    if info and nameEq(info.name, nsender) then found = true; break end
end
if not found then …
N.SendResyncRes(sender, gameID)
```

| Attack | Result |
|---|---|
| Spam (>1 req/5sec from same peer) | PASS — `_resyncCooldown` per-sender 5-sec gate. |
| Spam (across multiple peers, all in roster) | **PARTIAL FAIL** | Each peer has independent 5-sec budget. 3 peers × 1/5sec = 36 packs/min. Mitigated by addon-channel rate limit but not by handler. |
| Non-roster spammer | PASS — `if not found` reject. |
| Unknown gameID | PASS — `S.s.gameID ~= gameID`. |
| Empty gameID | PASS — explicit check. |
| **CRITICAL: tag collision with MSG_OVERCALL_RESOLVE** | **FAIL** | See CRIT-1. The handler is **never invoked** because `K.MSG_OVERCALL_RESOLVE = "?"` (same as `K.MSG_RESYNC_REQ`) takes priority in dispatch. |

---

### `_OnResyncRes` (`Net.lua:3175`) — verifying v0.9.1 L5 fix

```
if fromSelf(sender) then return end
if not gameID or not payload then return end
if S.s.isHost then return end
if not expectingResyncRes then return end
if WHEREDNGNDB and WHEREDNGNDB.lastGameID
   and WHEREDNGNDB.lastGameID ~= gameID then
    return
end
expectingResyncRes = false
if resyncResExpiryTimer and resyncResExpiryTimer.Cancel then
    resyncResExpiryTimer:Cancel()
    resyncResExpiryTimer = nil
end
S.s.hostName = (S.NormalizeName and S.NormalizeName(sender)) or sender
S.ApplyResyncSnapshot(gameID, payload)
```

| Attack | Result |
|---|---|
| **Injection without prior request (v0.9.1 L5 attack)** | **PASS** | `if not expectingResyncRes then return end` blocks. |
| Injection within 30-sec window after legitimate request | **PASS (mitigated)** | The `expectingResyncRes = false` consumption ensures only ONE response is honored. A first-arrival attacker wins, but they need to know: (a) the gameID, (b) a valid snapshot payload. The host's payload is broadcast-able (snapshot fields can be observed during normal play), so a sufficiently informed attacker could craft a snapshot. **CONCERN**: the only gating is the request-flag and a gameID match — there's no signature or nonce. A peer who saw the original `MSG_RESYNC_REQ` go out can race the legitimate host. Severity: MEDIUM — requires active observation + crafted payload. |
| Forged hostName via this handler | **FAIL (by design)** | `S.s.hostName = sender` runs unconditionally inside the gated branch. A first-arrival attacker captures hostName. From there, every subsequent `fromHost(attacker)` returns true, locking them in as authority. Severity: HIGH if the race is won. |
| Active host applying a peer's res | PASS — `if S.s.isHost then return end` (11th-audit fix at `Net.lua:3185`). |
| Different gameID | PASS — `WHEREDNGNDB.lastGameID ~= gameID` reject. |

**Recommendation (out of scope — no code change):** the v0.9.1 fix
correctly closes the unsolicited-injection vector but does NOT
defend against a race within the 30-sec window. A nonce in the
request that the response must echo would close that gap.

---

### `_OnKawesh` (`Net.lua:3236`)

```
if fromSelf(sender) then return end
if not seat then return end
if S.s.paused then return end
if S.s.phase ~= K.PHASE_DEAL1 then return end
if not authorizeSeat(seat, sender) then return end
```

| Attack | Result |
|---|---|
| Bidder-seat injection (seat=9) | PASS-ish | `authorizeSeat(9, sender)` rejects (seat 9 has no entry). Same reliance on data-model integrity as `_OnTakweesh`. |
| Authority forge | PASS — `authorizeSeat`. |
| Phase forge | PASS. |

---

## Cross-cutting concerns

### Channel scope leak (WHISPER vs PARTY)

`Net.lua:486`:
```
function N.HandleMessage(prefix, message, channel, sender)
    if prefix ~= K.PREFIX then return end
    if not message or #message == 0 then return end
```

The `channel` argument is logged but **never consulted** for
routing decisions. Implications:

1. `MSG_HAND` is sent via WHISPER but a forged PARTY copy from a
   non-host attacker is rejected via `fromHost` — PASS.
2. **A name-spoofed host could broadcast `MSG_HAND` over PARTY**,
   leaking another player's hand to all four. The receiver's
   `_OnHand` does NOT verify `channel == "WHISPER"`. Mitigated by
   the addon-message API (only the actual host can pass
   `fromHost`), but if an attacker compromises the host's name
   they have already-leaked hands.
3. `MSG_RESYNC_RES` is whispered but receivers don't verify
   `channel == "WHISPER"`. A PARTY-broadcast snapshot would race
   every other client into applying a snapshot for their own
   session.

**Recommendation:** add `channel` checks to `_OnHand`,
`_OnResyncRes` — they are the only WHISPER-only handlers. All
other handlers are PARTY-broadcast and receiving them on WHISPER
should also probably reject (defense in depth).

### Empty-string field handling

`split` (`Net.lua:471-483`) is **correct** in preserving
empty-trailing fields:

```
while true do
    local i = s:find(sep, start, true)
    if not i then out[#out + 1] = s:sub(start); break end
    out[#out + 1] = s:sub(start, i - 1)
    start = i + 1
end
```

This is the correct manual splitter (vs `gmatch` which would lose
trailing empties). Empty-string handling per-handler:

- Handlers that compare `field == "1"` / `"0"`: PASS, "" decodes
  as default.
- Handlers that pass strings to `S.Apply*` directly: usually PASS
  via downstream defaults (`(x ~= "" and x) or nil` in
  `S.ApplyContract`, `S.ApplyMeld`).
- `_OnBid` accepts `bid=""` and stores it — MILD FAIL (cosmetic).
- `_OnPlay` accepts `card=""` and reaches `S.ApplyPlay` — PASS only
  because ApplyPlay's later legality checks reject; defense-in-
  depth would add `if #card ~= 2 then return end` at handler.

### Type coercion (tonumber → nil propagation)

Handlers that check `if not seat then return end` are protected
against `tonumber("abc")=nil`. Handlers that do NOT have explicit
range gates:
- `_OnTurn` — `if not seat`. **MISSING range gate.**
- `_OnPlay` — `if not seat`. **MISSING range gate.**
- `_OnContract` — `if not bidder or not btype`. **MISSING range gate on bidder.**
- `_OnMeld` — `if not seat or not kind`. **MISSING range gate on seat.**
- `_OnSWAResp` — `if not responder`. **MISSING range gate on responder.**
- `_OnRound` — `tonumber("abc")=nil` for addA/addB/totA/totB → silently passes nil to `S.ApplyRoundEnd`.

The handlers that DO range-gate are `_OnSWA`, `_OnSWAReq`,
`_OnAKA`, and the `_OnTrick` encPlays decoder. **The
range-gate pattern should be uniform.**

### Version-tag stripping (back-compat)

`_OnHost`, `_OnJoin`, `_OnLobby` all do
`if version and version ~= ""` — surplus version field ignored
gracefully. `_OnDouble`/`_OnTriple`/`_OnFour` handle the v0.2.0
open/closed flag with the `(openField == nil) or (openField ~= "0")`
default-open pattern. `_OnRound`/`_OnSWAOut` handle the v0.3.0
sweep/bidderMade three-state encoding correctly. PASS across the
back-compat surface.

### Bidder-seat injection summary

| Handler | Range-gates seat? |
|---|---|
| `_OnTurn` | NO — only `not seat` |
| `_OnBid` | indirect (turn check) |
| `_OnContract` | NO (bidder) |
| `_OnDouble` | indirect (eligibleSeat compare) |
| `_OnTriple/Four/Gahwa` | indirect |
| `_OnPreempt` | indirect (eligibility membership) |
| `_OnPreemptPass` | seat=0 special; otherwise no explicit gate, relies on `authorizeSeat` |
| `_OnSkip*` | indirect |
| `_OnMeld` | NO |
| `_OnPlay` | NO (relies on authorizeSeat) |
| `_OnTrick` (encPlays) | YES — `seat >= 1 and seat <= 4` |
| `_OnTakweesh` | NO (relies on authorizeSeat) |
| `_OnSWA / SWAReq` | YES — `seat >= 1 and seat <= 4` |
| `_OnSWAResp` (responder) | NO |
| `_OnAKA` | YES — `seat >= 1 and seat <= 4` |
| `_OnKawesh` | NO (relies on authorizeSeat) |

The seats-table sparseness (`s.seats[9] == nil`) is what saves
the no-explicit-gate handlers. If `s.seats[9]` were ever
populated (it can't be via legitimate flow but a forged
`MSG_LOBBY` with extra fields was checked above and only reads
1..4, so PASS), the gate would land. The robust pattern is the
explicit `seat >= 1 and seat <= 4` gate seen in `_OnSWA*` and
`_OnAKA`.

---

## Summary table

| Handler | Field-count | Type coerce | Empty field | Seat injection | Forged source | Replay/version |
|---|---|---|---|---|---|---|
| _OnHost | PASS | N/A | mild | N/A | mild (by design) | PASS |
| _OnJoin | PASS | N/A | PASS | N/A | PASS | PASS |
| _OnLobby | PASS | N/A | PASS | PASS | mitigated (X9-3) | PASS |
| _OnStart | PASS | **FAIL** | PASS | **FAIL** | PASS | N/A |
| _OnDealPhase | PASS | mild | PASS | N/A | PASS | N/A |
| _OnHand | PASS | PASS | mild | N/A | PASS | PASS |
| _OnBidCard | PASS | N/A | mild | N/A | PASS | N/A |
| _OnTurn | PASS | PASS | mild | **FAIL** | PASS | N/A |
| _OnBid | PASS | PASS | mild | PASS (turn) | PASS | N/A |
| _OnContract | PASS | PASS | PASS | **FAIL** | PASS | N/A |
| _OnDouble | PASS | PASS | PASS | PASS | PASS (auth) | PASS |
| _OnTriple/Four/Gahwa | PASS | PASS | PASS | PASS | PASS | PASS |
| _OnPreempt | PASS | PASS | PASS | PASS | PASS | N/A |
| _OnPreemptPass | PASS | PASS | PASS | PASS | PASS | N/A |
| _OnSkip* | PASS | PASS | PASS | PASS | PASS | N/A |
| _OnMeld | PASS | mild | PASS | **FAIL** (no range) | PASS | PASS |
| _OnPlay | PASS | PASS | mild | **FAIL** (no range) | PASS | PASS |
| _OnTrick | PASS | PASS | PASS | PASS (range gate) | PASS | PASS |
| _OnRound | PASS | **FAIL** | PASS | N/A | PASS | PASS |
| _OnGameEnd | PASS | N/A | mild | N/A | PASS | N/A |
| _OnTakweesh | PASS | PASS | PASS | mitigated | PASS | N/A |
| _OnTakweeshOut | PASS | PASS | PASS | PASS | PASS | PASS |
| _OnPause | PASS | N/A | PASS | N/A | PASS | N/A |
| _OnTeams | PASS | N/A | mild | N/A | PASS | N/A |
| _OnAKA | PASS | PASS | PASS | PASS | PASS | PASS |
| _OnSWA | PASS | PASS | mild | PASS | PASS | N/A |
| _OnSWAReq | PASS | PASS | mild | PASS | PASS | N/A |
| _OnSWAResp | PASS | PASS | PASS | **FAIL** (responder) | PASS | N/A |
| _OnSWAOut | PASS | PASS | PASS | N/A | PASS | PASS |
| _OnResyncReq | **DEAD** (CRIT-1) | — | — | — | — | — |
| _OnResyncRes | PASS | N/A | PASS | N/A | medium (race) | N/A |
| _OnKawesh | PASS | PASS | PASS | mitigated | PASS | N/A |

---

## Top recommendations (no code changes applied; flagged only)

1. **CRIT-1 (BLOCKER): Rename `K.MSG_RESYNC_REQ`** away from `"?"`.
   Current collision with `K.MSG_OVERCALL_RESOLVE` makes resync
   unreachable.
2. **CRIT-2 (HIGH): Add payload validation to `_OnOvercallResolve`**
   so a missing-field frame doesn't blindly demote phase.
3. **Uniform seat range-gating**: add `seat >= 1 and seat <= 4`
   checks to `_OnTurn`, `_OnContract`, `_OnMeld`, `_OnPlay`,
   `_OnSWAResp` (parallel to `_OnSWA`/`_OnAKA`/`_OnTrick`).
4. **Type coercion on `_OnStart`/`_OnRound`**: explicit nil-check
   on every numeric field before calling `S.Apply*`.
5. **Empty-field validation on `_OnPlay`/`_OnBid`/`_OnBidCard`**:
   reject `""` at handler entry.
6. **Channel scope check**: `_OnHand` and `_OnResyncRes` should
   verify `channel == "WHISPER"` (defense in depth).
7. **MSG_RESYNC_RES nonce**: the v0.9.1 L5 fix closes
   unsolicited-injection but a 30-sec race window remains. A
   per-request nonce in `MSG_RESYNC_REQ` echoed in
   `MSG_RESYNC_RES` would close the race.

End.
