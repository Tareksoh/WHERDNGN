# B-State-10 — `S.ApplyResyncSnapshot` Deep Audit

Targets:

- `C:/CLAUDE/WHEREDNGN/State.lua:388-540` — `S.ApplyResyncSnapshot`
- `C:/CLAUDE/WHEREDNGN/State.lua:289-375` — `S.RestoreSession`
  (comparison path)
- `C:/CLAUDE/WHEREDNGN/State.lua:31-126` — `reset()` (third
  comparison path)
- `C:/CLAUDE/WHEREDNGN/State.lua:191-247` — `TRANSIENT_FIELDS`
- `C:/CLAUDE/WHEREDNGN/Net.lua:333-465` — `packSnapshot` +
  `N.SendResyncRes` (host-side encoder + replay)
- `C:/CLAUDE/WHEREDNGN/Net.lua:3175-3220` — `_OnResyncRes` (the
  receiver-side caller)

Cross-refs read first:

- `audit_v0.9.0/15_v091_l5_resync.md` — L5 30-s resync window
  guard
- `_track_B_code/B-Net-08_resync_replay.md` — wire-side audit
  (CRIT-1 tag collision, H1 race, H2 winner, H3 meldsDeclared)
- `_track_D_redteam/D-RT-17_resync_edges.md` — 13 edge probes,
  notably #1 (meldsDeclared), #5 (Takweesh race), #7 (cross-char
  ghost), #12 (winner leak)

This finding focuses on the **receiver-side** decode + state
mutation. The wire-tag collision (B-Net-08 CRIT-1) means
`_OnResyncReq` is dead code in v0.7.0+, so in current source no
real `MSG_RESYNC_RES` ever flies — but `ApplyResyncSnapshot` is
nonetheless the planned import path and an attacker who satisfied
the four `_OnResyncRes` gates would still drive every issue
documented below.

---

## Wire format reference (29 fields, `|`-separated)

Per `Net.lua:354-383` (`packSnapshot`) and `State.lua:391-415`
(layout comment), the payload writes 29 fields:

| # | Field | Source | Notes |
|---|---|---|---|
| 1 | gameID | `s.gameID` | Validated against arg `gameID` at line 422 |
| 2 | phase | `s.phase` | Direct string copy |
| 3 | dealer | `s.dealer` | tonumber, 0 → falls back to `s.dealer` |
| 4 | roundNumber | `s.roundNumber` | tonumber |
| 5 | turn | `s.turn or 0` | 0 → nil; >0 → number |
| 6 | turnKind | `s.turnKind or ""` | "" → nil |
| 7 | contract.type | `c.type or ""` | "" → s.contract = nil |
| 8 | contract.trump | `c.trump or ""` | "" → trump = nil |
| 9 | contract.bidder | `c.bidder or 0` | tonumber |
| 10 | contract.doubled | `"0"`/`"1"` | Bel ×2 |
| 11 | contract.tripled | `"0"`/`"1"` | Bel ×3 |
| 12 | contract.foured | `"0"`/`"1"` | Four ×4 |
| 13 | contract.gahwa | `"0"`/`"1"` | match-win |
| 14 | contract.tripleOpen | `"0"`/`"1"` | escalation flag |
| 15 | contract.fourOpen | `"0"`/`"1"` | escalation flag |
| 16 | cumulative.A | `s.cumulative.A` | tonumber, default 0 |
| 17 | cumulative.B | `s.cumulative.B` | tonumber, default 0 |
| 18 | paused | `"0"`/`"1"` | direct |
| 19 | bidRound | `s.bidRound or 1` | tonumber |
| 20–23 | seat 1-4 names | `s.seats[i].name` | empty = unseated |
| 24–27 | bid 1-4 | `s.bids[i] or ""` | empty = no bid yet |
| 28 | botMask | 4-bit `seats[i].isBot` | 7th-audit fix |
| 29 | target | `s.target or 152` | Audit Tier 4 / B-69 |

**Fields NOT on the wire (gathered cumulatively from analysis):**

`s.localName`, `s.localSeat`, `s.hostName`, `s.isHost`, `s.hand`,
`s.hostHands`, `s.hostDeckRemainder`, `s.trick`, `s.tricks`,
`s.meldsByTeam`, `s.meldsDeclared`, `s.belPending`,
`s.belrePending`, `s.bidCard`, `s.preemptEligible`,
`s.pendingPreemptContract`, `s.overcall`, `s.swaRequest`,
`s.swaResult`, `s.swaDenied`, `s.takweeshResult`, `s.akaCalled`,
`s.lastTrick`, `s.lastRoundResult`, `s.lastRoundDelta`,
`s.peekedThisRound`, `s.handRound`, `s.localPlayedThisTrick`,
`s.meldHoldUntil`, `s.playedCardsThisRound`, `s.redealing`,
`s.winner`, `s.peerVersions`, `s.teamNames`, `s.pendingHost`.

The host's post-snapshot replay block (`Net.lua:386-465`) covers
**some** of these via secondary whispers: `MSG_HAND` (hand;
re-whispered at `Net.lua:3168` in `_OnResyncReq`),
`MSG_BIDCARD`, `MSG_MELD`×N, `MSG_PREEMPT_PASS`,
`MSG_OVERCALL_OPEN` + decisions, `MSG_TRICK`×N, `MSG_PLAY` for
in-flight plays, `MSG_AKA`. The snapshot+replay together only
**partially** rebuild the receiver — see findings below.

---

## L1 — v0.9.1 L5 `expectingResyncRes` guard verified — PASS

**Severity: PASS / NO CHANGE.**

Re-verified per `audit_v0.9.0/15_v091_l5_resync.md` and
B-Net-08 §L1. All four gates intact:

`Net.lua:3185`:
```
if S.s.isHost then return end
```

`Net.lua:3191`:
```
if not expectingResyncRes then return end
```

`Net.lua:3196-3199`:
```
if WHEREDNGNDB and WHEREDNGNDB.lastGameID
   and WHEREDNGNDB.lastGameID ~= gameID then
    return
end
```

`Net.lua:3202-3206`:
```
expectingResyncRes = false
if resyncResExpiryTimer and resyncResExpiryTimer.Cancel then
    resyncResExpiryTimer:Cancel()
    resyncResExpiryTimer = nil
end
```

Order of gates is correct: host short-circuit first (so a host's
own loopback can never apply), then flag check, then gameID
match, then flag-clear-on-consume. Module-scoped flag at
`Net.lua:313` defaults to false on every `/reload` (not
persisted in SavedVariables), so a fresh client cannot accept
unsolicited snapshots. The 30-s `C_Timer.NewTimer` correctly
nils both the flag and the timer handle on expiry
(`Net.lua:322-326`). **No regression** since v0.9.1.

Only nit (carried over from `audit_v0.9.0/15`): the `30` literal
is hardcoded; recommended hoist to `K.RESYNC_RES_WINDOW_SEC`.

---

## H1 — Stale `s.winner` leak (D-RT-17 #12 / B-Net-08 H2)

**Severity: HIGH (cosmetic — phantom winner banner).** Confirmed.

### Quote

`State.lua:524-534` (cleanup block):
```
s.akaCalled             = nil
s.lastTrick             = nil
s.takweeshResult        = nil
s.swaResult             = nil
s.swaRequest            = nil
s.swaDenied             = nil
s.redealing             = nil
s.pendingPreemptContract= nil
s.preemptEligible       = nil
s.lastRoundResult       = nil
s.lastRoundDelta        = nil
```

`s.winner` is **not** in this cleanup block. The cleanup omits
it, the wire format omits it (no field 30), and the host's
post-snapshot replay in `Net.lua:386-465` does not whisper any
analogue of `MSG_GAME_END` for this purpose.

### Why it matters

`s.winner` is set by `S.ApplyGameEnd` at `State.lua:1606`:

```
s.winner = winnerTeam
```

`s.winner` is **NOT** in `TRANSIENT_FIELDS` (`State.lua:191-247`),
so `SaveSession` would persist it — but `SaveSession` skips
PHASE_GAME_END entirely (`State.lua:252-256`), so a /reload at
GAME_END nils the session. That path is safe.

The vulnerable path (per B-Net-08 H2 / D-RT-17 #12) is the
in-memory carryover within a single WoW session: previous game
ended → `s.winner = "A"` → host starts a new game without
calling `S.Reset()` on the rejoiner → rejoiner /reloads or
joins late → `_OnResyncRes` calls `ApplyResyncSnapshot` → all
29 wire fields get rewritten but `s.winner = "A"` still holds.

### Repro

1. Game finishes. `S.ApplyGameEnd("A")` sets `s.winner = "A"`,
   `s.phase = K.PHASE_GAME_END`.
2. Same WoW session, host runs `/baloot reset` and
   `HostBeginLobby` for game #2. Host's local `reset()` clears
   their `s.winner`. Other peers receive `MSG_LOBBY` (newGame
   branch in `ApplyLobby`, `State.lua:711-727`), which does
   call `S.Reset()` — so the typical path clears it on every
   peer.
3. **Vulnerable seam**: a peer who was OFFLINE when the lobby
   broadcast went out, then re-joins mid-bid via
   `MSG_RESYNC_REQ`. They never received the reset.
   `ApplyResyncSnapshot` runs and writes the 29 wire fields —
   `s.winner = "A"` from the prior game persists.
4. UI consumes `s.winner` (via `S.Winner()` accessor or any
   `if s.winner` check) and surfaces a phantom "Team A wins"
   banner over the live game until the next reset cycle.

### Fix surface (do NOT modify)

Add one line to the cleanup block at `State.lua:524-534`:

```
s.winner = nil
```

Alternatively, include `winner` as field 30 in `packSnapshot`
(but additive wire format changes are usually heavier than a
local cleanup line; cleanup is cheaper).

---

## H2 — `meldsDeclared` wiped, replay only rebuilds `meldsByTeam` (D-RT-17 #1 / B-Net-08 H3)

**Severity: MEDIUM (UI-only on receiver).** Confirmed.

### Quote

`State.lua:514-517`:
```
s.tricks       = {}
s.meldsByTeam  = { A = {}, B = {} }
s.meldsDeclared= {}
s.playedCardsThisRound = {}
```

The cleanup wipes `s.meldsDeclared` to an empty table. The
host's post-snapshot replay block `Net.lua:403-410` walks
`s.meldsByTeam[A]` ∪ `s.meldsByTeam[B]` and whispers
`MSG_MELD;<seat>;<kind>;<suit>;<top>;<enc>;1` for each.

`_OnMeld` → `S.ApplyMeld` (`State.lua:1149`) writes to
`meldsByTeam` only:

```
table.insert(s.meldsByTeam[team], { ... })
```

There is **no** `s.meldsDeclared[seat] = true` write inside
`ApplyMeld`. The flag is stamped at four caller sites instead:
`Net.lua:2046-2048` (`LocalDeclareMeld`), `Net.lua:3440` (host
AFK auto-declare), `Net.lua:4082, 4129` (bot decision sites),
`UI.lua:1987` ("Done" button).

Since the replay drives `_OnMeld` → `ApplyMeld` (NOT any of the
four caller sites), `meldsDeclared` stays at `{}` after the
replay completes. Only `meldsByTeam` is reseeded.

### Repro

1. Player at seat 3 declares a meld during the trick-1 window
   (`s.meldsDeclared[3] = true`).
2. They /reload mid-window. `RestoreSession` carries
   `meldsDeclared[3] = true` (it's NOT in `TRANSIENT_FIELDS`).
3. They send `MSG_RESYNC_REQ`.
4. Host whispers `MSG_RESYNC_RES`. Receiver runs
   `ApplyResyncSnapshot`, which **wipes** `meldsDeclared` to
   `{}` (line 516).
5. Host whispers each `MSG_MELD` — `ApplyMeld` writes to
   `meldsByTeam` but does NOT restamp `meldsDeclared[3]`.
6. Final state: `meldsDeclared = {}` even though seat 3 (and
   possibly others) already declared. UI gates that consume
   `meldsDeclared[localSeat]` (e.g., the local meld picker)
   may now offer a fresh declare to a seat who already
   declared.

### Why state is protected (UI is not)

`S.ApplyMeld` has a dedupe guard at `State.lua:1159`:
```
-- already in the team list?
```
combined with the trick-1 wire gate at `State.lua:1154`. So
even if the user clicks "declare" a second time, the duplicate
gets rejected and `s.meldsByTeam` doesn't double-count.
**State remains correct**; only the picker visibility is wrong.

### Fix surface

Two equivalent options:

1. Replay loop walks `meldsByTeam.A ∪ meldsByTeam.B` in the
   receiver after the snapshot lands and stamps
   `meldsDeclared[m.declaredBy] = true`.
2. Add `s.meldsDeclared[m.declaredBy or 0] = true` at the end
   of `S.ApplyMeld` (around line 1185). Symmetric for AFK
   auto-declare and player-driven declare.

Option 2 is simpler and centralizes the invariant. **Pick
option 2.**

---

## H3 — Idempotency: `ApplyResyncSnapshot` is NOT idempotent without the post-snapshot replay

**Severity: MEDIUM (latent — never observed standalone, but a
defensive design property is missing).**

### Test: run `ApplyResyncSnapshot(gid, payload)` twice, no replay

Field-by-field analysis of what the second call writes vs the
first:

| Field | First call | Second call | Idempotent? |
|---|---|---|---|
| `s.gameID` | `gameID` (line 424) | same | YES |
| `s.phase` | wire phase (line 425) | same | YES |
| `s.dealer` | wire (line 426) | same | YES |
| `s.roundNumber` | wire (line 427) | same | YES |
| `s.turn` | `(turnNum > 0) and turnNum or nil` (line 430) | same | YES |
| `s.turnKind` | wire (line 431) | same | YES |
| `s.contract` | full struct rebuilt (lines 434-448) | same | YES |
| `s.cumulative` | wire A/B (lines 451-452) | same | YES |
| `s.paused` | wire (line 453) | same | YES |
| `s.bidRound` | wire (line 454) | same | YES |
| `s.seats` | full struct rebuilt (lines 462-473) | same | YES |
| `s.isHost` | `false` unconditional (line 488) | same | YES |
| `s.localSeat` | `S.SeatOf(s.localName)` (lines 489-494) | same | YES |
| `s.bids` | wire 1-4 (lines 496-500) | same | YES |
| `s.target` | wire if present (lines 505-508) | same | YES |
| `s.tricks` | `{}` (line 514) | `{}` | YES (wiped) |
| `s.meldsByTeam` | `{ A={}, B={} }` (line 515) | same | YES (wiped) |
| `s.meldsDeclared` | `{}` (line 516) | same | YES (wiped) |
| `s.playedCardsThisRound` | `{}` (line 517) | same | YES (wiped) |
| 11-field cleanup (lines 524-534) | `nil` | `nil` | YES |
| `s.trick` | `nil` (line 538) | same | YES |
| `s.hand` | `s.hand or {}` (line 539) | same on 1st re-run | YES |

**Conclusion: the snapshot decoder itself IS idempotent.**
Running `ApplyResyncSnapshot(gid, payload)` twice in a row,
with no other state mutation between, produces the same
post-state.

### But the snapshot+replay sequence is NOT idempotent

The host's `SendResyncRes` (`Net.lua:386-465`) sends:
1. `MSG_RESYNC_RES` (snapshot)
2. `MSG_BIDCARD` if `s.bidCard`
3. `MSG_MELD` × N (bypassing authorizeSeat)
4. `MSG_PREEMPT_PASS` if PHASE_PREEMPT
5. `MSG_OVERCALL_OPEN` + decisions if PHASE_OVERCALL
6. `MSG_TRICK` × N (closed tricks)
7. `MSG_PLAY` × N (in-flight plays, replay flag "1")
8. `MSG_AKA` if active

If the receiver is mid-replay when a SECOND
`MSG_RESYNC_RES` arrives (e.g., from a forged spoof during the
30-s window — but the L1 gate at `Net.lua:3191` clears the
flag on first apply, so this is normally impossible), the
second `ApplyResyncSnapshot` would re-wipe `s.tricks`,
`s.meldsByTeam`, `s.meldsDeclared`, `s.playedCardsThisRound`
mid-way through the first replay. Already-applied
`MSG_TRICK`/`MSG_MELD` frames would be discarded. Subsequent
replay frames from the first sequence would re-stuff them
back. End-state correctness depends on replay-frame ordering
being deterministic across both sequences (it is, since both
host-initiated sequences walk the same in-memory tables). So
final state is "still correct after both sequences finish",
but transient intermediate states could surface a partial /
inconsistent UI.

### Why this isn't actively a bug

The L1 flag-clear-on-consume at `Net.lua:3202` ensures only
ONE `MSG_RESYNC_RES` ever passes the gate per
`SendResyncReq` cycle. So in practice the double-apply edge
needs an attacker who can race the legit host's response (see
H4 below for that scenario).

### Idempotency note for `s.localSeat`

Line 489-494 re-derives `s.localSeat` via `S.SeatOf`. If
between the two snapshot applies, `s.localName` changed (e.g.,
WoW renamed the player; not a real scenario), the second apply
would produce a different `localSeat`. In the steady-state
case where `s.localName` is stable, idempotent.

### Idempotency note for `s.hand`

Line 539: `s.hand = s.hand or {}`. **Idempotent**. If the
post-snapshot `MSG_HAND` whisper landed between two
`ApplyResyncSnapshot` calls, the second call would NOT clobber
`s.hand` — `s.hand` is non-nil non-empty, so `or {}` is a
no-op. Good.

---

## H4 — Race within 30-s window: peer who observed request can race host (B-Net-08 H1)

**Severity: HIGH (theoretical), LOW (practical).** Confirmed.

### Quote

`Net.lua:3215-3219`:
```
S.s.hostName = (S.NormalizeName and S.NormalizeName(sender)) or sender
S.ApplyResyncSnapshot(gameID, payload)
```

There is NO check at this site that `sender` matches the
pre-existing `S.s.hostName` (or the `s.seats[1].name` host
slot). The first response to arrive within the 30-s window —
that satisfies the four gates above — wins. Whoever gets to
the rejoiner first **becomes** the rejoiner's local
authoritative host (line 3218 overwrites `S.s.hostName`).

### Repro (theoretical)

1. Legitimate host receives `MSG_RESYNC_REQ` from rejoiner.
2. Adversary peer also observes the request (broadcast on the
   addon channel — every party member receives it).
3. Adversary spoofs the host's name on the addon channel
   (requires WoW-client tampering on the adversary's side,
   not network MITM) and races a forged `MSG_RESYNC_RES;<gameID>;<payload>`.
4. Adversary's response arrives first.
5. Receiver passes all four gates (not isHost ✓, expectingResyncRes ✓,
   gameID match ✓, flag-cleared on consume).
6. `S.s.hostName = adversaryName`. Adversary now drives the
   rejoiner's gameplay state via subsequent crafted broadcasts
   that pass `fromHost(sender)` checks.

### Why mostly safe

WoW addon-channel sender authentication is enforced at the
client level (each message is tagged with the SENDER account
name by the server). Forgery requires client-side tampering on
the spoofer's machine. Among legitimate peers, no one has
authority to claim to be host. So the practical exposure is
low.

### Why it's still worth noting

A defensive sanity check would be:

```
if S.s.hostName and S.s.hostName ~= "" and
   S.NormalizeName(sender) ~= S.NormalizeName(S.s.hostName) then
    return  -- silent reject; the L5 flag is consumed but mismatch
end
```

placed BEFORE line 3218. Note: on a fresh /reload with no
prior `s.hostName`, this gate would reject the legit host too,
so the gate must allow `S.s.hostName == nil` to pass through
(it's the rejoiner's first contact). The trade-off: the
defensive check tightens the race-window edge but slightly
weakens the "we don't know who the host is yet" cold-start
path. Cross-ref the `Net.lua:3210-3214` comment which
explicitly trusts the sender on cold start.

**Cross-ref**: `_track_D_redteam/D-RT-17 §7` marks this PASS
overall but flags the cross-character edge separately
(see L1 below in this finding).

---

## H5 — Cross-character resync request with stale `lastGameID` (D-RT-17 §7)

**Severity: LOW (cosmetic — request goes on the wire but is
rejected).** Confirmed STILL UNFIXED.

### Quote

`State.lua:307-308`:
```
if not sess.owner or not s.localName then return false end
if sess.owner ~= s.localName then return false end
```

Both early-returns bail without touching `WHEREDNGNDB.lastGameID`.

### Repro

1. Character A plays a round. `WHEREDNGNDB.lastGameID =
   "ABC123"`. `WHEREDNGNDB.session.owner = A`.
2. `/reload` or relog as character B (same account, different
   character). `WHEREDNGNDB` is per-account, so it persists.
3. PLAYER_LOGIN runs `S.RestoreSession()`. Cross-character
   guard hits: `sess.owner == "A" ≠ s.localName == "B"` →
   returns false. **`WHEREDNGNDB.lastGameID` is NOT cleared.**
4. PLAYER_ENTERING_WORLD fires `maybeRequestResync` 2s later
   (`WHEREDNGN.lua:311`). Reads `WHEREDNGNDB.lastGameID =
   "ABC123"`, broadcasts `MSG_RESYNC_REQ;ABC123`.
5. Host receives request from character B. Without the wire-
   tag collision, `_OnResyncReq` would reject at
   `Net.lua:3147-3155` (sender not in seat roster). But with
   the v0.7.0+ wire-tag collision (B-Net-08 CRIT-1), the
   request lands in `_OnOvercallResolve`, fails the
   `fromHost(sender)` gate at 1125, and dies silently.
6. Either way the rejoiner's `expectingResyncRes` flag is set
   to true with no response coming. 30 s later it expires
   silently. Cosmetic loss only.

### Compounding with B-Net-08 CRIT-1

Per B-Net-08 §L2: "in current code the practical effect is
even smaller than D-RT-17 documented — but only because
resync is fully broken." Once CRIT-1 is fixed, this finding
becomes more visible (a logged "request rejected: sender not
in roster" warning at `Net.lua:3153` per cross-character
login).

### Fix surface

One line in `State.lua` cross-character early-return at line
307-308:
```
if not sess.owner or not s.localName then
    if WHEREDNGNDB then WHEREDNGNDB.lastGameID = nil end
    return false
end
if sess.owner ~= s.localName then
    if WHEREDNGNDB then WHEREDNGNDB.lastGameID = nil end
    return false
end
```

---

## L1 — Snapshot vs Replay vs RestoreSession field-coverage table

Three different state-rehydration paths cover different sets of
fields. This is informational; it documents the asymmetry.

| Field | reset() | RestoreSession | ApplyResyncSnapshot+replay |
|---|---|---|---|
| `s.gameID` | nil | persisted | wire field 1 |
| `s.phase` | IDLE | persisted | wire field 2 |
| `s.isHost` | false | persisted | **forced false** (line 488) |
| `s.hostName` | nil | persisted | set by `_OnResyncRes` to `sender` |
| `s.localName` | (kept) | persisted | not written (kept) |
| `s.localSeat` | nil | persisted | re-derived (lines 489-494) |
| `s.dealer` | 1 | persisted | wire field 3 |
| `s.roundNumber` | 0 | persisted | wire field 4 |
| `s.turn` | nil | persisted | wire field 5 |
| `s.turnKind` | nil | persisted | wire field 6 |
| `s.contract` | nil | persisted | wire fields 7-15 |
| `s.cumulative` | {0,0} | persisted | wire fields 16-17 |
| `s.paused` | false | persisted | wire field 18 |
| `s.bidRound` | 1 | persisted | wire field 19 |
| `s.seats` | {} | persisted | wire fields 20-23 + 28 (botMask) |
| `s.bids` | {} | persisted | wire fields 24-27 |
| `s.target` | DB.target or 152 | persisted | wire field 29 (Audit Tier 4) |
| `s.bidCard` | nil | persisted | replay `MSG_BIDCARD` |
| `s.preemptEligible` | nil | **persisted** (NOT transient) | replay `MSG_PREEMPT_PASS` |
| `s.pendingPreemptContract` | nil | **persisted** (NOT transient) | **WIPED at line 531; not replayed** |
| `s.overcall` | nil | persisted | replay `MSG_OVERCALL_OPEN` + decisions |
| `s.swaRequest` | nil | **persisted** (NOT transient) | **WIPED at line 528; not replayed** |
| `s.swaResult` | nil | **transient** | wiped at line 527; not replayed (UI-only loss OK) |
| `s.swaDenied` | nil | **transient** | wiped at line 529; not replayed (3-s toast loss OK) |
| `s.takweeshResult` | nil | **transient** | wiped at line 526; not replayed (banner loss OK) |
| `s.akaCalled` | nil | **transient** | wiped at line 524; replay `MSG_AKA` |
| `s.lastTrick` | nil | **transient** | wiped at line 525; not replayed (peek loss OK) |
| `s.lastRoundResult` | nil | **transient** | wiped at line 533; not replayed |
| `s.lastRoundDelta` | nil | **transient** | wiped at line 534; not replayed |
| `s.redealing` | nil | **transient** | wiped at line 530; not replayed |
| `s.tricks` | {} | persisted | wiped + replay `MSG_TRICK`×N |
| `s.trick` | nil | persisted | wiped + replay `MSG_PLAY`×N |
| `s.meldsByTeam` | {A={},B={}} | persisted | wiped + replay `MSG_MELD`×N |
| `s.meldsDeclared` | {} | persisted | **wiped, NOT replayed** (H2) |
| `s.playedCardsThisRound` | {} | **transient** (rebuilt from tricks) | wiped, rebuilt by `_OnTrick` handlers |
| `s.belPending` | nil | persisted | **not written, not wiped** |
| `s.belrePending` | nil | persisted (cleared by upgrader) | **not written, not wiped** |
| `s.peekedThisRound` | nil | persisted | **not written, not wiped** |
| `s.handRound` | nil | persisted | **not written, not wiped** |
| `s.localPlayedThisTrick` | nil | **transient** | not written, not wiped |
| `s.meldHoldUntil` | nil | **transient** | not written, not wiped |
| `s.hand` | {} | persisted | preserved (`s.hand or {}` line 539); re-whispered via `SendHand` at `Net.lua:3168` |
| `s.hostHands` | nil | persisted (NOT transient) | not written; only host has it |
| `s.hostDeckRemainder` | nil | persisted (NOT transient) | not written; only host has it |
| `s.peerVersions` | {} | persisted | not written, not wiped |
| `s.teamNames` | from DB | persisted | not written, not wiped |
| `s.pendingHost` | nil | **transient** | not written, not wiped |
| **`s.winner`** | nil | persisted (NOT transient) | **NOT WIPED, NOT REPLAYED** (H1) |

### Anomalies surfaced by the table

1. **H1 reaffirmed**: `s.winner` is persisted but has no
   wire/replay/cleanup coverage in the resync path.
2. **H2 reaffirmed**: `s.meldsDeclared` is persisted but the
   resync path wipes it without replay reseed.
3. **`s.pendingPreemptContract` (line 531)**: cleanup wipes it.
   The replay (lines 416-420) only sends `MSG_PREEMPT_PASS`
   with the eligible CSV — it does NOT carry the
   `pendingPreemptContract` struct. The handler
   `_OnPreemptPass` at `Net.lua:3960+` rebuilds
   `s.preemptEligible` from the CSV but does NOT rebuild
   `s.pendingPreemptContract`. Result: a non-host rejoiner
   mid-PHASE_PREEMPT has `preemptEligible` set but
   `pendingPreemptContract = nil`. If they then click
   "claim", `LocalPreempt` would lookup
   `pendingPreemptContract` for the rung → nil → no-op. UI
   button visible but inert. **This is a separate finding
   not previously catalogued**; see new finding M1 below.
4. **`s.swaRequest` (line 528)**: same pattern as #3. Cleanup
   wipes it; replay doesn't reseed. The non-host rejoiner
   loses the SWA pending banner. The host's flow continues
   correctly via `RestoreSession`'s swaRequest survival on
   the host side (per the comment at `State.lua:225-227`).
   The non-host's MSG_SWA_RESP buttons are gone. Cross-ref
   B-Net-08 §L3 (informational note about swaRequest). **Not
   a state-corruption bug** because the host is the
   resolution authority; non-host is just visually
   disconnected from the in-flight vote. UI-only loss.
   Recommend including swaRequest in the snapshot wire
   format OR adding a `MSG_SWA_REPLAY` whisper in
   `SendResyncRes`. Non-blocking.
5. **`s.belPending`, `s.belrePending`** (NOT in cleanup):
   stale carryover risk. If a previous game left these set
   on a non-host, and the rejoiner enters a fresh game's
   PHASE_DOUBLE phase via resync, the stale `belPending` /
   `belrePending` could trigger spurious UI prompts. Wire
   format doesn't carry them; cleanup doesn't clear them. In
   practice cleared by `S.Reset()` between games — but the
   resync path skips `Reset()`. **Same class of bug as H1
   (winner)**.

---

## M1 — `pendingPreemptContract` wiped, replay doesn't reseed (NEW)

**Severity: MEDIUM (rare — only matters mid-PREEMPT
rejoin).**

### Quote

`State.lua:531`:
```
s.pendingPreemptContract= nil
```

`Net.lua:416-420` (host-side replay block during PREEMPT):
```
if S.s.phase == K.PHASE_PREEMPT and S.s.preemptEligible
   and #S.s.preemptEligible > 0 then
    local eligCsv = table.concat(S.s.preemptEligible, ",")
    whisper(target, ("%s;0;%s"):format(K.MSG_PREEMPT_PASS, eligCsv))
end
```

The replay sends a `MSG_PREEMPT_PASS;0;<eligCsv>` frame —
seat=0 marks it as the eligibility-list reseed (per the
"7th-audit fix" comment). This rebuilds `s.preemptEligible`
on the receiver but does NOT rebuild `s.pendingPreemptContract`.

`s.pendingPreemptContract` is the contract struct the
preempting seat would claim (e.g., HOKM with the bid card's
suit, or SUN). Without it, the rejoiner's
`LocalPreempt` button-click handler — which reads
`s.pendingPreemptContract` to construct the broadcast — has
no payload to send.

### Repro

1. Game enters PHASE_PREEMPT (round-2 SUN bid lands on Ace).
2. Eligible seats include the rejoiner.
3. Rejoiner /reloads. `RestoreSession` brings back
   `s.pendingPreemptContract` because it's NOT in
   `TRANSIENT_FIELDS` (per `State.lua:240-243` comment).
4. Rejoiner sends `MSG_RESYNC_REQ`.
5. `_OnResyncRes` → `ApplyResyncSnapshot` → cleanup at line
   531 sets `s.pendingPreemptContract = nil`.
6. Replay only sends `MSG_PREEMPT_PASS;0;<eligCsv>`. Receiver
   rebuilds `s.preemptEligible` only.
7. UI shows "claim Hokm/Sun" button (because
   `s.preemptEligible[localSeat]` is true). Click does
   nothing because `s.pendingPreemptContract = nil`.

### Why pre-/reload `RestoreSession` works but resync doesn't

`RestoreSession` overlays the saved fields without nilling
unset ones (because of the hard-reset at line 313 — every
field starts nil and gets overlaid). So
`s.pendingPreemptContract` survives /reload PROVIDED the
session was persisted (which the non-transient flag ensures).

`ApplyResyncSnapshot` does NOT hard-reset. It selectively
writes / wipes specific fields. The cleanup at line 531
treats `pendingPreemptContract` as transient-on-resync but
the replay protocol does not provide it. **Asymmetry between
SaveSession's transient list and the resync cleanup list.**

### Fix surface

Two options:

1. Don't wipe `pendingPreemptContract` in
   `ApplyResyncSnapshot` cleanup (line 531). Trust the
   persisted value to be correct OR trust that a rejoiner
   would have entered PHASE_PREEMPT freshly via the lobby
   path.
2. Augment the host-side replay to whisper a frame carrying
   the contract struct, and add a receiver-side handler to
   reseed it.

Option 1 changes one line. Option 2 changes the wire format.
**Option 1 is preferred** but requires verifying the
persisted value can never be stale relative to the
authoritative host's view (e.g., a host who advanced the
PREEMPT window during the rejoiner's offline gap).

---

## M2 — `belPending`, `belrePending`, `peekedThisRound`, `handRound` not in cleanup

**Severity: LOW (latent staleness).** New, found via the field
table.

### Quote

The cleanup at `State.lua:519-540` lists:
```
s.akaCalled             = nil
s.lastTrick             = nil
s.takweeshResult        = nil
s.swaResult             = nil
s.swaRequest            = nil
s.swaDenied             = nil
s.redealing             = nil
s.pendingPreemptContract= nil
s.preemptEligible       = nil
s.lastRoundResult       = nil
s.lastRoundDelta        = nil
```

Fields NOT in this cleanup that the rejoiner could carry
stale via `RestoreSession`:

- `s.belPending` — escalation phase struct; would mid-game
  trigger spurious double/triple prompt when rejoiner enters
  a fresh PHASE_DOUBLE.
- `s.belrePending` — pre-v0.2.0 leftover; the upgrader at
  line 329 nils this in `RestoreSession` only.
  `ApplyResyncSnapshot` does not.
- `s.peekedThisRound` — peek-last-trick gate. Stale `true`
  from prior round means the rejoiner's first peek attempt
  this round silently denied.
- `s.handRound` — pairs with `s.hand` to gate stale-deal
  detection. `ApplyHand` at line 768 checks
  `s.handRound ~= newRoundNum`; a stale value could either
  pass-through a fresh hand or reject a legit one.
- `s.localPlayedThisTrick` — per-trick double-click guard.
  Stale `true` could lock the rejoiner out of their next
  play. (TRANSIENT in `SaveSession`, but NOT in resync
  cleanup. So a rejoiner whose `RestoreSession` already nilled
  it via the transient list is safe; but a rejoiner who
  didn't go through `RestoreSession` first — e.g., a peer
  who was already running and just lost mid-hand sync — has
  no protection.)

### Practical impact

These are mostly bookkeeping fields that get cleared at the
next round transition (`ApplyStart` at `State.lua:759`+
nils most of them). The danger is the in-between window: a
rejoiner who lands mid-trick has stale flags until the next
trick boundary fires.

**Recommend** extending the cleanup at lines 524-534 to
include all `RestoreSession`-persistent state-y fields that
the snapshot does NOT carry. Specifically:

```
s.winner                = nil  -- H1
s.belPending            = nil
s.belrePending          = nil
s.peekedThisRound       = nil
s.handRound             = nil
s.localPlayedThisTrick  = nil
s.meldHoldUntil         = nil
```

Note that several of these (`localPlayedThisTrick`,
`meldHoldUntil`) are already TRANSIENT_FIELDS — they're
nilled by `SaveSession` not surviving /reload. But a peer
who NEVER /reloaded (e.g., just rejoined party after a
brief disconnect) doesn't go through `SaveSession` /
`RestoreSession`. So these still need clearing in
`ApplyResyncSnapshot`.

---

## L2 — Snapshot vs RestoreSession: `s.isHost` semantics differ

**Severity: PASS / INFORMATIONAL.**

### Quote

`State.lua:481-488`:
```
-- 10th-audit fix: clear s.isHost UNCONDITIONALLY when applying a
-- snapshot — the rejoiner sent MSG_RESYNC_REQ, so the host is
-- whoever is responding (sender), not us. ...
s.isHost = false
```

`RestoreSession` (`State.lua:289-375`) does NOT explicitly
set `s.isHost`. The hard-reset at line 313 nils everything,
then the saved fields overlay. If the saved `s.isHost = true`,
it carries over.

### Implications

- A peer who was host pre-/reload remains host post-/reload.
  Correct.
- A peer who was not host pre-/reload remains not-host
  post-/reload. Correct.
- A peer who applies a resync snapshot becomes not-host
  unconditionally. Correct (per the 10th-audit fix
  rationale: a rejoiner is by definition NOT the
  authoritative source).
- **Edge**: a host who somehow consumes a snapshot would
  demote themselves. Defense at `Net.lua:3185`
  (`if S.s.isHost then return end`) blocks this — host's
  short-circuit precedes the snapshot apply.

The 10th-audit fix correctly removed the conditional gating
on `mySeat` lookup (previously `s.isHost = false` was inside
`if mySeat`, leaving stale `isHost = true` on a SeatOf
miss).

PASS, no change.

---

## L3 — `s.hand` preservation across resync

**Severity: PASS / INFORMATIONAL.**

### Quote

`State.lua:539`:
```
s.hand  = s.hand or {}
```

The snapshot does not carry `s.hand`. Cleanup at lines 524-534
doesn't touch it. Line 539 ensures `s.hand` is at least an
empty table (so subsequent `ipairs(s.hand)` doesn't crash if
nil).

After `ApplyResyncSnapshot` runs, `_OnResyncReq` host-side
re-whispers the hand via `N.SendHand(sender,
S.s.hostHands[seat])` at `Net.lua:3168`. The receiver's
`_OnHand` → `ApplyHand` at `State.lua:830+` writes the live
hand.

Race window: between `ApplyResyncSnapshot` finishing and the
`MSG_HAND` whisper arriving, the receiver has the OLD
pre-resync hand (carried over from `RestoreSession` or
mid-session memory). This window is sub-second on healthy
realms. The rejoiner cannot play during this window because
`s.turn` may not be on them; if turn IS on them, their
`LocalPlay` validates against `s.hand` (which is the old
hand — but the host-side host validates plays against
`s.hostHands[seat]` which is correct). Net effect: the
rejoiner sees their stale hand briefly, then it refreshes.

PASS, no change.

---

## Findings summary

| # | ID | Severity | Status |
|---|---|---|---|
| 1 | L1 expectingResyncRes guard verification | PASS | Re-verified per `audit_v0.9.0/15`; all 4 gates intact |
| 2 | H1 stale `s.winner` leak through cleanup | HIGH cosmetic | **Confirmed** D-RT-17 #12 / B-Net-08 H2; 1-line fix |
| 3 | H2 `meldsDeclared` wiped, replay doesn't reseed | MEDIUM UI | **Confirmed** D-RT-17 #1 / B-Net-08 H3; 1-line fix |
| 4 | H3 idempotency analysis | INFORMATIONAL | Snapshot-decoder IS idempotent; snapshot+replay sequence has transient inconsistency under double-apply but L1 gate prevents this in practice |
| 5 | H4 30-s window peer race | HIGH theoretical / LOW practical | **Confirmed** B-Net-08 H1; addon-channel auth limits exploit |
| 6 | H5 cross-character ghost request | LOW | **Confirmed** D-RT-17 §7; `WHEREDNGNDB.lastGameID` not cleared in cross-char early-return; STILL UNFIXED, 1-line fix |
| 7 | L1 (table) snapshot vs replay vs RestoreSession asymmetry | INFORMATIONAL | Documents full field-coverage matrix |
| 8 | M1 `pendingPreemptContract` wiped, replay doesn't reseed | MEDIUM | **NEW**; non-host rejoiner mid-PHASE_PREEMPT loses claim payload |
| 9 | M2 belPending/belrePending/peekedThisRound/handRound not in cleanup | LOW | **NEW**; latent staleness for rejoiners who didn't /reload |
| 10 | L2 `s.isHost` semantics | PASS | 10th-audit fix correctly forces false unconditionally |
| 11 | L3 `s.hand` preservation | PASS | Sub-second window before MSG_HAND arrives is acceptable |

---

## Critical-path fix priority (do NOT modify)

1. **H1 (stale winner)** — add `s.winner = nil` to the cleanup
   block at `State.lua:524-534`. One line.
2. **H2 (meldsDeclared replay)** — add
   `s.meldsDeclared[m.declaredBy or 0] = true` at the end of
   `S.ApplyMeld` (around line 1185). One line.
3. **M1 (pendingPreemptContract)** — remove line 531 from
   the cleanup block (rely on persisted value), or augment
   replay to whisper the contract struct. One-line removal
   is cheaper.
4. **M2 (extended cleanup list)** — extend cleanup block to
   nil `belPending`, `belrePending`, `peekedThisRound`,
   `handRound`, `localPlayedThisTrick`, `meldHoldUntil`.
5. **H5 (cross-character)** — `WHEREDNGNDB.lastGameID = nil`
   in the cross-character early-return at
   `State.lua:307-308`. Already flagged in
   `audit_v0.7.1/35_save_restore.md`; one line.
6. **H4 (peer race)** — defensive
   `S.s.hostName == S.NormalizeName(sender)` check before
   `Net.lua:3218`, allowing `s.hostName == nil` cold-start
   pass-through. Optional hardening.

## Tests to add (run as `python tests/run.py`)

- `test_apply_resync_idempotent.lua` — invoke
  `ApplyResyncSnapshot(gid, payload)` twice; assert deep
  equal for all 29 wire-driven fields and the cleanup-block
  fields.
- `test_apply_resync_winner_cleared.lua` — set
  `s.winner = "A"` pre-call; assert `s.winner == nil`
  post-call (currently FAILS; would pass after H1 fix).
- `test_apply_resync_melds_declared_reseeded.lua` — host has
  `meldsByTeam.A = { {declaredBy=2, ...}, {declaredBy=3, ...} }`,
  send snapshot+replay; assert `s.meldsDeclared[2] == true`
  and `s.meldsDeclared[3] == true` on the receiver
  (currently FAILS; would pass after H2 fix).
- `test_resync_pending_preempt_contract_preserved.lua` —
  set up rejoiner mid-PHASE_PREEMPT with
  `s.pendingPreemptContract` populated; apply snapshot;
  assert it survives (currently FAILS; would pass after M1
  fix).
- `test_resync_winner_stale_carryover.lua` — pre-state:
  `s.winner = "A"`, then apply a snapshot for a fresh game;
  assert no winner banner surfaces (currently FAILS).
- `test_resync_cross_character_lastgameid_cleared.lua` —
  RestoreSession with `sess.owner != s.localName`; assert
  `WHEREDNGNDB.lastGameID == nil` post-call (currently
  FAILS; would pass after H5 fix).
