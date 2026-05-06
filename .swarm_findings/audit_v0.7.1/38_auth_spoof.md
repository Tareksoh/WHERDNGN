# Net.lua v0.7.2 — Authorization & Spoofing Audit

## Authorization primitives (Net.lua:618-651)

- `fromHost(sender)` — normSender(sender) == S.s.hostName
- `fromSelf(sender)` — drops loopbacks via normSender(sender) == S.s.localName
- `authorizeSeat(seat, sender)`:
  - bot seat → `nsender == S.s.hostName` (only host signs)
  - human seat → normalized `info.name == nsender`
  - returns false if seat unknown / info.name nil

## 1. Bot-bid spoofing (MSG_BID, seat=bot)

**SAFE.** `_OnBid` (Net.lua:809-823) calls `authorizeSeat(seat, sender)`. For a bot seat, this requires `sender == hostName`. A non-host client cannot impersonate the host's character name on the addon channel — WoW stamps `sender` from the actual chat-frame source, not addon-controlled. Phase + turn + idempotence guards stack on top.

**Caveat:** trust collapses to "hostName cannot be spoofed at the wire", which is true for CHAT_MSG_ADDON. If `S.s.hostName` was bound to the wrong peer (see §6), bot-bid authority transfers to that peer.

## 2. Bel/Triple/Four/Gahwa/AKA/SWA call spoofing as another player

**SAFE for the per-seat human path.** `_OnDouble`/`_OnTriple`/`_OnFour`/`_OnGahwa`/`_OnPreempt`/`_OnSkipDouble`/`_OnSkipTriple`/`_OnSkipFour`/`_OnSkipGahwa`/`_OnAKA`/`_OnSWA`/`_OnSWAReq`/`_OnTakweesh` all gate via `authorizeSeat(seat, sender)`. `_OnSWAResp` likewise (except synthetic `__host__`).

**Soft AKA gap:** `_OnAKA` comment notes "spoofed AKA wouldn't change scoring but would mislead a partner." authorizeSeat blocks remote spoofs, so safe in HEAD.

## 3. MSG_CONTRACT spoofing mid-round (alter trump)

**SAFE.** `_OnContract` (Net.lua:825-831) requires `fromHost(sender)` and rejects on `S.s.isHost`. A non-host client's MSG_CONTRACT is dropped. Same pattern for `_OnTurn`, `_OnHand`, `_OnDealPhase`, `_OnTrick`, `_OnRound`, `_OnGameEnd`, `_OnTeams`, `_OnPause`, `_OnSWAOut`, `_OnTakweeshOut`, `_OnOvercallOpen`, `_OnOvercallResolve`, `_OnBidCard`, `_OnStart`.

## 4. MSG_PAUSE without being host

**SAFE.** `_OnPause` (Net.lua:2330-2337) gates on `fromHost(sender)`. Non-host MSG_PAUSE is silently dropped.

## 5. MSG_TURN to advance turn

**SAFE.** `_OnTurn` (Net.lua:801-807) requires `fromHost(sender)`. The self-heal in `_OnPlay` (Net.lua:1356-1366) does mutate `S.s.turn` from a non-MSG_TURN frame — but only when (a) sender IS the host, OR (b) `authorizeSeat(seat, sender)` passes (the seat owner playing a card is allowed to claim the turn). This is intentional for AFK recovery and is not a spoof vector — seat owner can advance only their own seat's turn during PLAY.

## 6. Lobby seat spoofing (claim occupied seat)

**SAFE on host side.** `S.HostHandleJoin` (State.lua:578-593) iterates all seats, returns nil if `info.name == name` already exists, else assigns first empty seat 2..4. A duplicate-name MSG_JOIN is no-op.

**Host-adoption note:** `_OnLobby` (Net.lua:704-739) hardens host adoption — only accepts new `hostName` via (a) already-known host, (b) pendingHost matching gameID, or (c) `WHEREDNGNDB.lastGameID` match. Stale-host-name binding mitigated.

## Replay-frame bypass (audit-relevant)

`_OnPlay`, `_OnMeld`, `_OnAKA` accept `replayFlag=="1"` to skip authorizeSeat — gated on `fromHost(sender)` AND `not S.s.isHost`. A non-host peer cannot weaponize the bypass since the gate requires host-sender; the host-target guard prevents host self-poisoning.

## Critical gap candidates (none confirmed)

- `_OnContract` accepts host-signed contract any time — if a malicious peer became `S.s.hostName`, they could rewrite trump. Mitigated by §6 host-adoption tightening.
- `_OnTakweesh`: only seat owner can call; `HostResolveTakweesh` validates phase + scans authoritative play log. No spoof vector.
- No per-message sequence numbers / nonces — replay of an old captured MSG_BID/MSG_PLAY against the wire is theoretically possible, but phase + turn + idempotence guards drop it (each seat plays/bids at most once per trick/round).

## Verdict

Authorization layer is consistent and tight in v0.7.2. No exploitable spoof vector found across the six targeted vectors. The single soft surface is the host-name-binding path; v0.4 audit (X9-3) already hardened it.
