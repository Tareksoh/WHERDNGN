# v3.2.11 — Private Raid-Lobby Support (DESIGN PASS — NOT IMPLEMENTED)

**Status:** Design only. No code written.
**Revision:** Codex review round 1 applied (opt-in transport; allowlist
semantics; authoritative join gate; normalization; explicit scope
boundary; resolved open questions). Awaiting Codex re-review.
**Goal:** Allow exactly 4 selected players to play WHEREDNGN while in a
**raid group** (or instance group) by running a **private lobby/invite/
join** flow that is not exposed to the rest of the raid, and that
prevents seat-theft by uninvited raid members.

**Scope is deliberately bounded** — see §1.1. v3.2.11 secures the
lobby/invite/join handshake and seat assignment. It does **not**
promise that in-progress gameplay frames are private from other raid
members; that is an explicit non-goal.

> Hard rules honored by this document: design only, no code edits, no
> branch/tag/release, `sprint-a-experimental` and `v0.5.1-experimental`
> untouched.

---

## 1. Feasibility verdict

**Feasible, medium effort, low transport risk.** The blocker identified
in the prior feasibility pass is *not* the network transport — it is
that the lobby trust model assumes a ≤5-person audience. This design
adds (a) a 1-helper channel selector, (b) an **opt-in** RAID/
INSTANCE_CHAT transport that is *off by default* and only engaged when
the host explicitly configures an invite allowlist, (c) a
host-**authoritative** invite-allowlist join gate, and (d) cosmetic
receiver-side self-suppression to stop popup/sound spam. Normal PARTY
behavior is byte-for-byte unchanged. The gameplay/data plane logic is
untouched; only the lobby control plane and the send-channel string
change.

> **Security boundary:** the host-side join gate (§3.3) is the *only*
> trust boundary. Receiver-side self-suppression (§3.4) is a cosmetic
> anti-spam convenience and is **never** relied on for correctness or
> seat-theft prevention.

Key confirmations from source:

- **Single send chokepoint.** Every outbound frame funnels through the
  file-local `broadcast()` (`Net.lua:37`). Channel selection is one
  edit there. `whisper()` (`Net.lua:94`) stays as-is for hands/resync.
- **Receive path is channel-agnostic.** `N.HandleMessage`
  (`Net.lua:1134`) accepts `(prefix, message, channel, sender)` but
  uses only `prefix` for filtering (`channel` is logged, never
  branched on). A RAID/INSTANCE_CHAT frame is processed identically to
  a PARTY one — **zero receive-dispatch changes**.
- **v3.2.8/9/10 loopback class does NOT reopen.** `RAID` and
  `INSTANCE_CHAT` have the same "no self-loopback" semantics as
  `PARTY`. The host-direct refresh fixes (`safeOnPlayObserved`,
  `_HostStepPlay`, `deferredRefresh`, the v3.2.9 bid-phase analogs) are
  channel-independent. Switching the channel string regresses none of
  them. **These sites must not be touched.**
- **Whisper-mesh is NOT required.** `RAID`/`INSTANCE_CHAT` *do* work;
  the only reason raid was unsupported is the deliberate guard at
  `Net.lua:40-43`, not a WoW API limitation. Per requirement 1,
  whisper-mesh is rejected for the data plane (it triples per-sender
  throttle pressure exactly during escalation/trick-resolve bursts —
  see `Net.lua:2216` which already flags the host nudging the
  ~4–6 msg/sec/sender ceiling).

---

## 1.1 Scope & non-goals (requirement 5)

**In scope for v3.2.11:**

- Private **lobby/invite/join** handshake in a raid/instance group:
  uninvited raid members cannot claim a seat (host-authoritative
  rejection), and do not receive the invite popup/sound (cosmetic
  suppression).
- **Seat-theft prevention**: only normalized-allowlisted names are
  seated, regardless of what any client UI does.
- Opt-in transport: no public lobby advertisement is emitted on
  RAID/INSTANCE_CHAT unless the host has explicitly configured an
  invite allowlist.

**Explicit non-goals (NOT promised in v3.2.11):**

- **Full gameplay-frame privacy is NOT provided.** Once the game
  starts, mid-game frames (`MSG_PLAY`, `MSG_BID`, `MSG_TURN`,
  `MSG_TRICK`, …) are still broadcast on RAID/INSTANCE_CHAT. Other
  raid members running WHEREDNGN will *receive* those frames; they are
  *ignored* (no state effect) only via the existing `fromHost` /
  `authorizeSeat` gates. A determined uninvited raider with the addon
  could therefore **passively observe** game state off the wire. This
  is accepted for v3.2.11 — see R10. Encrypted/whispered gameplay
  frames are deferred future work, explicitly out of scope.
- No anti-griefing beyond seat-theft (e.g., a malicious invited player
  is still trusted exactly as in party play today).

The privacy guarantee delivered is precisely: *uninvited raiders are
not spammed and cannot participate or steal a seat* — not *uninvited
raiders cannot see the game*.

---

## 2. Exact WoW API shape (requirement 1)

| API | Signature | Use here |
|---|---|---|
| `IsInGroup([category])` | `→ boolean` | `IsInGroup()` = any group. `IsInGroup(LE_PARTY_CATEGORY_INSTANCE)` = in an instance group (LFR/LFD/premade-in-instance). |
| `IsInRaid([category])` | `→ boolean` | `IsInRaid()` = home group is a raid. |
| `IsInInstance()` | `→ inInstance(boolean), instanceType(string)` | **Informational cross-check only.** NOT the channel discriminator — you can be physically in an instance while your group is still a "home" raid (4 friends walk into an old raid), and you can be in an instance *group* while not yet zoned in (LFR forming). |
| `LE_PARTY_CATEGORY_INSTANCE` | global enum `= 2` (`_HOME = 1`) | Discriminator for INSTANCE_CHAT. Reference defensively as `(LE_PARTY_CATEGORY_INSTANCE or 2)` for the headless test env. |

**Canonical channel discriminator** (the AceComm/LibSpecialization
pattern; order matters):

```
function groupChannel()
    if IsInGroup(LE_PARTY_CATEGORY_INSTANCE or 2) then return "INSTANCE_CHAT" end
    if IsInRaid()    then return "RAID"  end
    if IsInGroup()   then return "PARTY" end
    return nil   -- not grouped → no send (preserves today's behavior)
end
```

**INSTANCE_CHAT is mandatory, not optional:** when the group is an
instance group, `RAID`/`PARTY` addon messages are **not delivered** to
instance-group members. The user's two scenarios actually span both
channels: "raid building in the open world" → `RAID`; "waiting inside
the raid instance / queued LFR" → `INSTANCE_CHAT`. Both branches are
required for the stated goal.

`return nil` exactly reproduces the current `if not IsInGroup() then
return end` early-out (solo host + bots: not grouped → no send →
unchanged).

**`groupChannel()` only *names* the channel — it does not authorize the
send.** Whether a `RAID`/`INSTANCE_CHAT` frame is actually transmitted
is decided by the **opt-in gate inside `broadcast()`** (§3.1): RAID/
INSTANCE traffic is suppressed unless the session is in private
raid-lobby mode. `"PARTY"` and `nil` are never gated (legacy behavior
preserved).

---

## 3. Implementation plan

### 3.1 Transport — opt-in RAID/INSTANCE (Net.lua) (requirement 1)

**RAID/INSTANCE_CHAT is opt-in and off by default.** A new boolean
session marker `s.raidLobby` (§3.2) is the transport opt-in switch.
Normal PARTY play never sets it and is byte-for-byte unchanged.

- **Add** file-local `groupChannel()` near the top of the Send section
  (just before `broadcast`, `Net.lua:~36`). Expose
  `N._GroupChannel = groupChannel` as a test handle (mirrors the
  `N._SafeOnPlayObserved` convention introduced in v3.2.10).
- **Rewrite** `broadcast()` (`Net.lua:37-56`): replace the
  `if not IsInGroup() then return end` + `if IsInRaid() then …skip…
  return end` block with the **channel + opt-in gate**:
  ```
  local ch = groupChannel()
  if not ch then return end                       -- ungrouped: unchanged
  if ch ~= "PARTY" and not S.s.raidLobby then
      return    -- raid/instance but NOT a private raid-lobby session:
                -- suppress. No public advertisement leaks to the raid.
  end
  local ok, err = pcall(C_ChatInfo.SendAddonMessage, K.PREFIX, msg, ch)
  ```
  - `ch == "PARTY"` → always sent (legacy, never gated).
  - `ch == nil` → no send (ungrouped; reproduces today's
    `not IsInGroup()` early-out — solo host + bots unchanged).
  - `ch == "RAID"|"INSTANCE_CHAT"` and `not S.s.raidLobby` →
    **suppressed**. This is the opt-in enforcement: a host who simply
    `/baloot host`s while in a raid emits **nothing** to the raid.
  - `ch == "RAID"|"INSTANCE_CHAT"` and `S.s.raidLobby` → sent.
  The freezeDebug `TX` instrumentation (`Net.lua:49-55`) is preserved
  verbatim; it should additionally record `ch`.
- **Host-facing message (requirement 1, bullet 3).** Suppression must
  be *visible to the host*, not silent. At the host advertisement call
  sites — the **Host Game** button (`UI.lua:858-891`) and the lobby
  ticker (`UI.lua:881-887`) — when `groupChannel()` is
  `RAID`/`INSTANCE_CHAT` and the host is **not** in a ready private
  raid-lobby (see §3.2 readiness), print a one-time host-only chat
  line, e.g.:
  > *"You are in a raid/instance. WHEREDNGN does not broadcast a
  > public raid invite. Open the lobby and add invitees to start a
  > private game."*
  Use the existing one-shot-print idiom (cf. `_OnHost`'s
  `_versionWarnedFor` guard, `Net.lua:1392`) so the ticker does not
  spam it every `K.LOBBY_BROADCAST_SEC`. The lobby is still created
  locally (host can add invitees); only the *broadcast* is withheld.
- **Non-host opt-in.** A non-host sets `s.raidLobby = true` only when it
  **accepts a private-mode invite** for the current gameID (received a
  `MSG_HOST` whose `allowCSV` is present *and* lists this player —
  §3.4). Until then a non-host in a raid transmits nothing (it has no
  reason to: it hasn't been invited to anything). Cleared on
  reset/new-game with everything else.
- **No change** to `whisper()`, `broadcastWithRetry()`,
  `HandleMessage`, or any handler.

### 3.2 Invite allowlist — state & semantics (State.lua) (requirement 2)

Two new fields. **The allowlist tri-state is the heart of the design —
read this precisely:**

**`s.inviteAllow`** (host-only authority for *who* may join):

| Value | Meaning | Join gate behavior |
|---|---|---|
| `nil` | **Legacy unrestricted PARTY mode ONLY.** Not a private game. | Gate disabled — anyone may join, exactly as v3.2.10. This is the only backward-compat state. |
| `{}` (empty table) | **Private raid-lobby mode engaged, but no one invited yet / not ready.** | Gate active, membership set empty ⇒ **every** non-host join is rejected. **Empty is never "unrestricted".** |
| `{ ["Name-Realm"]=true, … }` | Private raid-lobby mode, invitees configured. | Gate active ⇒ only listed normalized names seated. |

The distinction `nil` vs `{}` is load-bearing: `nil` ⇒ "party, allow
all" (legacy); `{}` ⇒ "raid, allow none yet" (closed). They must never
be conflated. Code must test `s.inviteAllow ~= nil` (not truthiness of
contents) to detect "private mode engaged", and table membership for
"is this name allowed".

**`s.raidLobby`** (boolean, both host & non-host — the transport opt-in
marker consumed by `broadcast()` §3.1):

- Host: set `true` at the moment `s.inviteAllow` transitions
  `nil → {}` (entering raid-lobby mode — see "opt-in transition").
- Non-host: set `true` only on accepting a private-mode invite (§3.4).
- Invariant (host): `s.raidLobby == (s.inviteAllow ~= nil)`.

**"Ready to advertise" predicate** (host): `s.inviteAllow ~= nil and
next(s.inviteAllow) ~= nil` (mode engaged **and** ≥1 invitee). The
lobby ticker/Host button only broadcast `MSG_HOST`/`MSG_LOBBY` when
ready; otherwise the host-facing message (§3.1) is shown and nothing is
sent. (`{}` engaged-but-empty ⇒ not ready ⇒ no public invite — this is
exactly requirement 1 bullet 3.)

**Opt-in transition (how `nil → {}` happens):** entering raid-lobby
mode is an explicit host act, never automatic. It occurs when the host,
**while in a raid/instance group and in `PHASE_LOBBY`**, adds the first
invitee via the lobby editor or `/baloot invite` (§3.5). `HostAddInvitee`
performs the transition: `if s.inviteAllow == nil then s.inviteAllow =
{}; s.raidLobby = true end` then inserts. In a plain **party**, the
invitee editor is hidden and `/baloot invite` refuses with a message
("invitees apply to raid/instance play only") — so a party host can
**never** accidentally flip `s.inviteAllow` away from `nil`, guaranteeing
"normal PARTY behavior unchanged" (requirement 1 bullet 1). *(Codex
option: a dedicated explicit `S.HostEnterRaidLobby()` toggle instead of
implicit-on-first-invitee — see Open Question Q2.)*

**Lifecycle:**

- Initialize `s.inviteAllow = nil` and `s.raidLobby = nil` in `reset()`
  (`State.lua:~135`, next to `s.pendingHost = nil`) and in the
  state-init block (`State.lua:~110`).
- `S.HostBeginLobby()` (`State.lua:674`) calls `reset()` then sets
  fresh state ⇒ both fields cleared on every new lobby, and `gameID`
  regenerated each call. **Structurally prevents a stale allowlist
  bleeding into a new gameID** (R4).
- `inviteAllow` is host-only; non-hosts never set it. The `ApplyLobby`
  newGame save/restore list (`State.lua:806-820`) does **not** need it
  (it restores non-host session identity only). `s.raidLobby` on a
  non-host is re-derived from the next private-mode `MSG_HOST` (§3.4),
  so it also need not survive the newGame reset.

**New host API** (all no-op unless `s.isHost and
s.phase==K.PHASE_LOBBY`):

- `S.HostAddInvitee(name)` → normalize via `S.NormalizeName`; perform
  the `nil→{}` opt-in transition if needed; insert normalized key.
- `S.HostRemoveInvitee(name)` → normalize, delete. (Removing the last
  invitee leaves `{}` — still "engaged, not ready"; does **not** revert
  to `nil`. Reverting to legacy party mode requires `reset()`/new
  lobby, keeping the tri-state unambiguous.)
- `S.HostInvitees()` → ordered list of normalized names for UI/slash
  display (UI may render friendly short names — §3.5 / requirement 4).

### 3.3 Host-authoritative join gate — the ONLY trust boundary (State.lua) (requirement 3)

> Receiver-side suppression (§3.4) stops popup/sound spam **only**. It
> is cosmetic and must **never** be treated as a security control. A
> hostile or modified client can ignore it entirely and still emit a
> `MSG_JOIN`. **Seat-theft prevention lives exclusively here**, on the
> host, in the authoritative join path.

- **`S.HostHandleJoin(name)`** (`State.lua:708-732`) is the single
  authoritative join chokepoint: the network path
  `_OnJoin → S.HostHandleJoin` (`Net.lua:1445`) **and** any UI/slash
  join funnel through it. The gate goes here so no caller can bypass
  it. After the existing `isHost`/`phase`/self/dedup checks and
  **before** the "find first empty seat" loop, add:
  ```
  if s.inviteAllow ~= nil then               -- private mode engaged
      local nn = S.NormalizeName(name) or name
      if not s.inviteAllow[nn] then
          log("HostHandleJoin REJECT (not invited) %s", tostring(name))
          return            -- no seat granted, regardless of sender UI
      end
  end
  ```
  - Condition is **`s.inviteAllow ~= nil`** (not Lua-truthiness of
    contents). `{}` (engaged, empty) ⇒ gate active, membership lookup
    fails for everyone ⇒ **all** non-host joins rejected (closed
    lobby). `nil` (legacy party) ⇒ gate skipped ⇒ anyone joins,
    **byte-for-byte unchanged** (requirement 1 bullet 1; backward
    compat keystone).
  - `name` is the WoW-server-stamped `CHAT_MSG_ADDON` sender (or the
    local actor for UI/slash) — it is the trust root, not payload
    (R2). The gate's decision cannot be influenced by what the joining
    client's UI chose to do.
  - **Normalization (requirement 4):** the lookup key is
    `S.NormalizeName(name)`, the *same* normalization
    `normSender`/`authorizeSeat`/`S.SeatOf` already use
    (`State.lua:621`). Allowlist entries are stored normalized at
    insert time (§3.2 `HostAddInvitee`), so both sides of the
    comparison are in canonical `Name-Realm` form. UI/slash may accept
    and display friendly short names, but the gate only ever compares
    normalized full names. Test CA.8 pins the bare-vs-suffixed cases.
- **`S.HostAddBots()`** (`State.lua:743`) is unaffected: it only fills
  empty seats 2-4 with local bot stubs and never consults the network
  or the allowlist. Requirement 2 ("bots fill remaining allowed empty
  seats only when host chooses Fill Bots") already holds — Fill Bots is
  an explicit host button (`UI.lua:898`), and any seat a bot occupies
  is simply unavailable to a (non-)invited human regardless.

### 3.4 Receiver-side self-suppression — cosmetic anti-spam ONLY (Net.lua + wire)

> **Not a security boundary.** This section exists solely so uninvited
> raiders are not bombarded with the invite popup + `SND_TURN_PING`
> every `K.LOBBY_BROADCAST_SEC`. All seat-theft prevention is the host
> gate (§3.3). If this suppression were entirely removed, the design
> would still be *correct* — just noisier for uninvited raiders.

A populated `allowCSV` is only ever broadcast when the host is
**ready** (mode engaged **and** ≥1 invitee — §3.2). So the wire never
carries an empty allowlist: an uninvited raider either receives a
populated `allowCSV` (and self-suppresses) or, before the host is
ready, receives nothing at all (opt-in gate §3.1 withholds the
broadcast).

The invitee must know whether it is invited *before* `_OnHost` shows
the popup/sound. Carry the allowlist as an **optional trailing field**
on `MSG_HOST` (the frame that drives `_OnHost`'s
pendingHost/print/sound). This follows the codebase's well-worn
"append optional trailing field; old clients ignore it" pattern (the
version field on H/J/L, replay flags on M/P/W, etc.).

- **Wire format** `K.MSG_HOST` today: `H;<gameID>;<version>`
  → fields[2]=gameID, fields[3]=version.
  **New (private mode only):** `H;<gameID>;<version>;<allowCSV>`
  where `allowCSV` = comma-joined normalized names
  (`Alice-Realm,Bob-Realm,Cara-Realm`). Comma is safe: the field
  delimiter is `;`, names contain `-` but never `;` or `,`.
  **Party mode: field 4 is omitted → message is byte-identical to
  v3.2.10** (no trailing `;`).
- **`N.SendHostAnnounce(gameID)`** (`Net.lua:240`): if `S.s.inviteAllow`
  is set, append `;<allowCSV>`; else send the 3-field form unchanged.
- **`N._OnHost`** (`Net.lua:1374`): new signature
  `_OnHost(sender, gameID, version, allowCSV)`; dispatcher
  (`Net.lua:1145`) passes `fields[4]`. Logic:
  - `version` handling (peerVersions, mismatch warning): unchanged,
    runs first as today.
  - **If `allowCSV` is present and non-empty** (private mode): parse to
    a normalized set; compute `me = S.NormalizeName(S.s.localName)`.
    - **`me` ∉ set** → `return` before touching `pendingHost`, before
      the invite `print`, before `B.Sound.Try`. Uninvited raiders go
      fully silent (cosmetic only — they were already barred by §3.3).
    - **`me` ∈ set** → this is the **non-host opt-in point**: set
      `S.s.raidLobby = true` (so this client's subsequent `MSG_JOIN`/
      gameplay frames transmit on RAID/INSTANCE per §3.1), then proceed
      with the existing `pendingHost`/print/sound path.
  - **If `allowCSV` absent** (party mode / pre-3.2.11 host): existing
    path verbatim, `s.raidLobby` untouched. Zero behavior change for
    parties.
- **`N.SendLobby` / `N._OnLobby`** (`Net.lua:251` / `1458`):
  *Optional, secondary.* Appending `allowCSV` to `MSG_LOBBY` lets a
  late refresh re-confirm suppression, but `MSG_HOST` is the primary
  and sufficient gate (it is what fires the popup/sound and is
  re-broadcast every `K.LOBBY_BROADCAST_SEC`). Recommend **deferring**
  the MSG_LOBBY change unless Codex wants belt-and-suspenders;
  MSG_HOST-only keeps the surface minimal.

### 3.5 UX (UI.lua + Slash.lua) — requirement 4

Minimal, host-only, raid-only. **Zero change to the normal party
flow** — the editor is hidden, and the slash verbs refuse, when not in
a raid/instance group, so a party host can never flip `s.inviteAllow`
off `nil`.

- In `buildLobby()` (`UI.lua:690`), add a host-only **invitee editor**
  block, shown only when `S.s.isHost and S.s.phase==K.PHASE_LOBBY and
  groupChannel() ~= "PARTY" and groupChannel() ~= nil`:
  - One `EditBox` + **Add** button (type a name). **Add performs the
    `nil→{}` opt-in transition** (§3.2) on first use — this is the
    explicit host act that engages raid-lobby mode and sets
    `s.raidLobby`.
  - A **Target+Add** button (`UnitName("target", true)` convenience) —
    avoids building a full raid-roster picker (requirement 4 explicitly
    permits this).
  - A short list of current invitees rendered with **friendly short
    names** (`shortName()`), each with a small ✕ remove button.
    Display is cosmetic; the stored/compared key is the normalized
    full name (§3.3, requirement 4). Reuse `makeButton`,
    `setLobbyTooltip`, and the existing `seatRows` styling helpers.
  - Hidden/`:SetShown(false)` for non-hosts and in plain parties.
  - When the host is in a raid/instance lobby but **not ready**
    (`s.inviteAllow` is `nil` or `{}`), show the §3.1 host-facing
    message inline near the editor (e.g. greyed helper text:
    *"No public raid invite is sent. Add invitees to start a private
    game."*) in addition to the one-shot chat line.
- `renderLobby()` (`UI.lua:3479`) gains a refresh of the invitee list +
  show/hide gating, alongside the existing kick-button/Fill-Bots
  show/hide logic (`UI.lua:3499-3515`).
- `Slash.lua`: `/baloot invite <name>`, `/baloot uninvite <name>`,
  `/baloot invites` (list). In a plain party these print
  *"Invitees apply to raid/instance play only"* and make no state
  change (preserves `s.inviteAllow == nil`). Mirrors the UI and honors
  the "every toggle mirrors a slash subcommand" convention
  (`WHEREDNGN.lua:188`).

### 3.6 Constants (Constants.lua)

- **No new `K.MSG_*` tag. No protocol-version bump.** The change is an
  optional trailing field on an existing tag — the established
  backward-compatible mechanism. Add a one-line doc comment on
  `K.MSG_HOST` (`Constants.lua:269`) noting the optional field 4.
- No new tunables required (`K.LOBBY_BROADCAST_SEC = 3.0` re-broadcast
  cadence is fine on the raid channel: <1 msg/s, prefix-filtered).

---

## 4. Risk table

| # | Risk | Severity | Mitigation |
|---|---|---|---|
| R1 | Name normalization mismatch (same-realm bare `Alice` vs `Alice-Realm`) lets an invited player be rejected, or a dedup miss | High | Normalize **both** at add-time (`HostAddInvitee`) and compare-time (`HostHandleJoin`, `_OnHost`) via `S.NormalizeName` — the exact pattern already used by `normSender`/`authorizeSeat`/`SeatOf` (`State.lua:621,640`). Test CA.8. |
| R2 | 5th raider forges `MSG_JOIN` with a spoofed allowlisted name | Medium | WoW stamps `sender` on `CHAT_MSG_ADDON` server-side; it cannot be forged. `HostHandleJoin` keys off the frame `sender`, not payload. Trust root is identical to existing `fromHost`/`authorizeSeat`. Documented as inherent to WoW. |
| R3 | Non-allowlisted raider on **old client** (≤v3.2.10) ignores field 4, still shows a stale invite | Low | That client's own `broadcast()` still hard-returns in a raid, so it physically cannot send `MSG_JOIN`; even if it could, the §3.3 host gate rejects it. Worst case: a dead invite popup it can't action. Existing version-mismatch warning (`_OnHost`, `Net.lua:1391`) already nudges users to match versions. Clean requirement: all 4 on v3.2.11+. |
| R4 | Stale allowlist carried into a new gameID | Medium | `reset()` clears `s.inviteAllow`; `HostBeginLobby()` calls `reset()` and regenerates `gameID` every time. Structurally impossible to carry. Test CA.5. |
| R5 | Invitee names visible on the raid wire (privacy) | Low | Names only, within the same raid, addon-message channel (invisible to non-addon users, prefix-filtered). Acceptable. *Optional hardening (deferred):* broadcast salted hashes instead of names; receiver hashes its own name to compare. Not recommended for v3.2.11 — adds complexity for marginal gain. |
| R6 | Empty allowlist while hosting in a raid (host opened lobby, added nobody) | Low | **Resolved by the opt-in gate.** `s.inviteAllow == {}` ⇒ "engaged, not ready" ⇒ the "ready to advertise" predicate (§3.2) is false ⇒ `broadcast()` (§3.1) emits **nothing** to the raid (not even a self-suppressed frame) and the host sees the §3.1 message. No wire traffic, no public invite, host informed. Bots may still fill seats locally for a private solo+bots game, but no advertisement leaks. |
| R7 | INSTANCE_CHAT vs RAID misclassification (wrong API order) | Medium | Use the canonical discriminator order (instance-category first). Tests CA.1/CA.2 cover all group states + the opt-in send gate under stubs. |
| R8 | Regression of v3.2.8/9/10 loopback/refresh | High if mishandled | Channel string change only; no self-loopback semantics differ between PARTY/RAID/INSTANCE_CHAT. Explicit no-touch list: `safeOnPlayObserved`, `_HostStepPlay`, `_HostStepBid`, `deferredRefresh`, all `B.UI.Refresh` host-direct paths. Add a source-pin (CA.10) asserting these are unmodified by the diff scope. |
| R9 | Party flow behavior drift | High if mishandled | `inviteAllow == nil` short-circuits the join gate; `"PARTY"` is never opt-in-gated in `broadcast()`; `MSG_HOST` omits field 4 ⇒ byte-identical wire; party hosts cannot reach the invitee editor/slash. Tests CA.6 (back-compat) + CA.7 (wire pin) pin this. |
| R10 | Uninvited raider passively observes in-progress gameplay frames off the RAID/INSTANCE_CHAT wire | Low (accepted) | **Explicit non-goal for v3.2.11** (§1.1, requirement 5). Mid-game frames are broadcast and only *ignored* (no state effect) by non-participants via existing `fromHost`/`authorizeSeat` gates; they are not hidden. Documented in scope; encrypted/whispered gameplay deferred. Not a regression (party play has the same property within the party). |

---

## 5. Test plan & expected harness delta

All new tests live in the **AZ Net-harness `do…end` block** in
`tests/test_state_bot.lua` (the only block that loads `Net.lua`;
setup at L7444-7479, teardown at L8896-8899), placed **before** stub
restoration, after the existing BQ section. New section id: **`CA`**
(BQ was the last 2-letter section).

**Harness delta required (additive, inside the AZ block):**

- The current stubs are `IsInGroup=function() return true end`,
  `IsInRaid=function() return false end` (L7453-7454) — they ignore
  arguments. Add **category-aware** stubs so `IsInGroup(2)` /
  `IsInGroup(LE_PARTY_CATEGORY_INSTANCE)` can be answered distinctly,
  plus an `IsInInstance` stub and a `LE_PARTY_CATEGORY_INSTANCE = 2`
  define, all save/restored exactly like the existing
  `_origIsInGroup/_origIsInRaid` pair (L7450-7451, 8898-8899). Provide
  small per-case setters (e.g. `setGroup("party"|"raid"|"instance"|
  "solo")`).
- `broadcastLog` already captures `channel` (L7463) — channel-selector
  assertions need no harness change beyond the stubs above. The opt-in
  gate is tested by **asserting `#broadcastLog == 0`** when suppressed.
- For the §3.1 host-facing one-shot message, assert on the **guard
  flag/state** the implementation sets (deterministic), not on printed
  text. Codex to name the flag (suggest `s._raidLobbyHintShown`) so the
  test can verify it is set once and not re-set on a second ticker
  call. A lightweight `print` spy may supplement but the flag is the
  stable assertion.
- Tests toggle `S.s.raidLobby` / `S.s.inviteAllow` directly to set up
  states; no new production hooks needed beyond `N._GroupChannel`.

**Cases (≈33 new checks):**

| ID | Kind | Asserts |
|---|---|---|
| CA.1 | Behavioral | `groupChannel()` (via `N._GroupChannel`) → `"PARTY"` (party), `"RAID"` (home raid), `"INSTANCE_CHAT"` (instance group), `nil` (ungrouped). (4) |
| CA.2 | Behavioral | **Opt-in gate.** raid + `S.s.raidLobby` falsey ⇒ a `broadcast()` call produces **`#broadcastLog == 0`**; raid + `raidLobby=true` ⇒ one entry, `channel=="RAID"`; instance + `raidLobby=true` ⇒ `channel=="INSTANCE_CHAT"`; **party + `raidLobby` falsey ⇒ still sent on `"PARTY"`** (PARTY never gated). (4) |
| CA.3 | Behavioral | **Allowlist tri-state join gate.** `inviteAllow=nil` ⇒ joiner seated (legacy); `inviteAllow={}` ⇒ join **rejected**, seats unchanged; `inviteAllow={["X-R"]=true}` ⇒ `X-R` seated 2..4; same list ⇒ `Y-R` **rejected**. (4) |
| CA.4 | Behavioral | **Receiver suppression + non-host opt-in.** `_OnHost` allowCSV excluding `localName` ⇒ `pendingHost` stays `nil`, `S.s.raidLobby` stays falsey, no print/sound; allowCSV including `localName` ⇒ `pendingHost` set **and** `S.s.raidLobby==true`. (4) |
| CA.5 | Behavioral | **Reset.** Set `inviteAllow` + `raidLobby`; `reset()` ⇒ both `nil`. `HostBeginLobby()` twice ⇒ both `nil` and `gameID` differs (R4). (3) |
| CA.6 | Behavioral | **Party back-compat.** `inviteAllow=nil`, party channel: `_OnJoin`→`HostHandleJoin` seats joiner exactly as v3.2.10; `broadcast` uses `"PARTY"`; no path divergence. (3) |
| CA.7 | Wire pin | `SendHostAnnounce` in party ⇒ message `== "H;<id>;<ver>"` (no trailing `;`, no field 4). Raid + ready (≥1 invitee) ⇒ `== "H;<id>;<ver>;<csv>"`. Raid + not-ready (`{}`) ⇒ **`#broadcastLog == 0`** (gate withholds). (3) |
| CA.8 | Behavioral | **Normalization (req 4).** Invitee added bare `Alice`; join arrives `Alice-Realm` ⇒ accepted. Added suffixed; join bare ⇒ accepted. (2) |
| CA.9 | Behavioral | **Ready predicate + one-shot hint.** `inviteAllow={}` ⇒ `SendHostAnnounce` yields no `broadcastLog` entry and sets the host-hint guard flag; calling the ticker path again does **not** re-set/re-print (one-shot); `inviteAllow={X}` ⇒ entry present, no hint. (3) |
| CA.10 | Source pins | `broadcast()` body has **no** `IsInRaid()` early-`return` "skip" branch; `groupChannel` is the sole source of the `SendAddonMessage` channel arg; the raid/instance branch is gated by `S.s.raidLobby`; `_OnHost` reads `fields[4]` and sets `s.raidLobby` on self-match; `HostHandleJoin` tests `s.inviteAllow ~= nil` (not truthiness); negative pin: no raw `"RAID"`/`"INSTANCE_CHAT"`/`"PARTY"` channel literal outside `groupChannel`. (5) |

**Expected harness total:** `1320 → ~1353` passed, `0` failed
(±3 depending on Codex's final case granularity). H1
(`test_H1_pin_J9_trump` = 11/0) and H7
(`test_H7_sun_shortest_lead` = 9/0) are **unaffected** (no Bot/Rules
changes) and must still pass unchanged.

---

## 6. Files touched (implementation scope summary)

| File | Functions / lines | Nature |
|---|---|---|
| `Net.lua` | new `groupChannel()` + `N._GroupChannel`; rewrite `broadcast()` L37-56 (channel select **+ `S.s.raidLobby` opt-in gate**); `SendHostAnnounce` L240 (optional `allowCSV`, ready-gated); `_OnHost` L1374 (read `fields[4]`, set `s.raidLobby` on self-match) + dispatcher L1145 | Opt-in channel selector + optional wire field + cosmetic receiver suppression |
| `State.lua` | `reset()` L~135 & init L~110 (`s.inviteAllow`, `s.raidLobby`); `HostHandleJoin` L708 (`~= nil` authoritative gate); new `HostAddInvitee` (incl. `nil→{}` opt-in transition) `/RemoveInvitee/Invitees`; "ready" predicate helper | Allowlist tri-state + transport marker + authoritative gate |
| `UI.lua` | `buildLobby()` L690 (raid-only invitee editor; short-name display); `renderLobby()` L3479 (gating + not-ready helper text); Host-button/lobby-ticker call sites L858-891 (one-shot host-facing message + ready-gate) | Host-only, raid-only invitee editor + host-facing message |
| `Slash.lua` | new `invite`/`uninvite`/`invites`; party ⇒ refuse with message (preserve `inviteAllow==nil`) | Slash mirror |
| `Constants.lua` | doc comment on `K.MSG_HOST` L269 | No tag, no protocol bump |
| `tests/test_state_bot.lua` | AZ block: category-aware group stubs + host-hint guard flag + CA.1–CA.10 | ~33 checks |

**Not touched (explicit):** `whisper()`, `HandleMessage` dispatch core,
`broadcastWithRetry`, `safeOnPlayObserved`, `_HostStepPlay`,
`_HostStepBid`, `deferredRefresh`, all v3.2.8/9/10 host-direct refresh
paths, `Bot.lua`, `BotMaster.lua`, `Rules.lua`. No protocol version
bump. `sprint-a-experimental` / `v0.5.1-experimental` preserved.

---

## 7. Open questions for Codex review

**RESOLVED in this revision (Codex round 1):**

- **R-Q4 — Channel selector scope: RESOLVED → opt-in required.** The
  prior recommendation (unconditional `groupChannel()`) is **rejected**
  per Codex review. RAID/INSTANCE_CHAT is now off by default and gated
  behind `S.s.raidLobby`, engaged only by an explicit host act
  (configuring an invite allowlist). Normal PARTY is byte-for-byte
  unchanged. This is now the design basis (§3.1/§3.2/§3.5); it is no
  longer an open question.
- **R-Q6/empty-allowlist:** resolved by the opt-in "ready" predicate —
  `{}` withholds all advertisement and surfaces a host-facing message
  (§3.1/§3.2/R6). No hard-block of the Host button needed.

**Genuinely still open (need a Codex decision):**

1. **Opt-in trigger shape (§3.2):** implicit — adding the first
   invitee performs `nil→{}` — versus an explicit
   `S.HostEnterRaidLobby()` toggle/button the host must press first.
   Recommendation: **implicit-on-first-invitee** (fewer clicks, one
   obvious affordance); flag if Codex wants an explicit gesture for
   clarity/auditability.
2. **MSG_LOBBY mirroring (§3.4):** ship MSG_HOST-only (minimal), or
   also append `allowCSV` to `MSG_LOBBY` for late-join refresh
   robustness? Recommendation: MSG_HOST-only for v3.2.11; revisit if
   field testing shows late-joiner suppression gaps.
3. **Privacy hardening / scope (§1.1, R5, R10):** confirm that
   plaintext invitee names on the raid wire **and** observable
   in-progress gameplay frames are both **accepted** for v3.2.11, with
   encrypted/whispered gameplay and name-hashing deferred to a future
   version. Recommendation: accept & defer; v3.2.11 scope is
   lobby/join safety + seat-theft prevention only.

---

**STOP — Codex review required before any implementation.**
No branch, no code, no tag. Implementation begins only after this
document is reviewed and amended/approved.
