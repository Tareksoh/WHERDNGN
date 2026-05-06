# B-State-04 — Session Persistence Deep Audit (SaveSession / RestoreSession)

**Targets:**
- `C:/CLAUDE/WHEREDNGN/State.lua:191-247` — `TRANSIENT_FIELDS` table
- `C:/CLAUDE/WHEREDNGN/State.lua:250-287` — `S.SaveSession`
- `C:/CLAUDE/WHEREDNGN/State.lua:289-375` — `S.RestoreSession`
- `C:/CLAUDE/WHEREDNGN/State.lua:388-540` — `S.ApplyResyncSnapshot`
- `C:/CLAUDE/WHEREDNGN/WHEREDNGN.lua:130-296` — `PLAYER_LOGIN` handler

**Cross-refs:**
- `audit_v0.9.0/54_m4_partnerstyle_quirks.md` (M4 partnerStyle persistence)
- `audit_v0.9.0/52_telemetry_reload.md` (telemetry on /reload)
- `_track_D_redteam/D-RT-14_savedvars_attack.md` (hand-edit attack
  surface — ATK-7/ATK-9/ATK-11 most relevant here)
- `_track_D_redteam/D-RT-17_resync_edges.md` (13 edge probes)
- `_track_D_redteam/D-RT-27_reset_redeal.md` (transient field reset)
- `_track_B_code/B-Net-08_resync_replay.md` (CRIT-1 wire-tag collision +
  H2/H3/H4 confirmations)

This audit re-verifies each of the 10 listed items against the current
source. Per-finding format: severity / repro / quoted code.

---

## F-01 — Cross-character fail-closed guard (v0.9.2 #54) — **PASS**

**Severity: PASS / VERIFIED.** No regression.

The fix from `audit_v0.9.0/54_m4_partnerstyle_quirks.md §6` is intact.
Re-read at `State.lua:296-308`:

```
-- v0.9.2 #54 fail-closed (audit_v0.9.0/54_m4_partnerstyle_quirks.md):
-- previous predicate `if sess.owner and s.localName and ...` would
-- short-circuit to PASS when EITHER side was nil. If
-- PLAYER_LOGIN's RestoreSession path runs before the local-name
-- has resolved (`SetLocalName(GetUnitName("player", true))`),
-- s.localName is nil and any owner's session passes the guard
-- → cross-character data leak. Fail closed: require BOTH sides
-- present AND matching.
if not sess.owner or not s.localName then return false end
if sess.owner ~= s.localName then return false end
```

Both gates are defensive AND-conjunctions — either nil rejects.

### Init-order verification

`WHEREDNGN.lua:75-89` (`init()`):

```
local function init()
    ensureDB()
    B.State.s.target = tonumber(WHEREDNGNDB.target) or 152
    if WHEREDNGNDB.teamNames then
        B.State.ApplyTeamNames(WHEREDNGNDB.teamNames.A,
                               WHEREDNGNDB.teamNames.B)
    end
    B.State.SetLocalName(GetUnitName("player", true))
    L.Info("init", "local name: %s", tostring(B.State.s.localName))
end
```

`WHEREDNGN.lua:130-141` (PLAYER_LOGIN flow):

```
if event == "PLAYER_LOGIN" then
    init()
    ...
    if B.State.RestoreSession and B.State.RestoreSession() then
```

Sequence: `init()` → `SetLocalName(GetUnitName("player", true))` →
`RestoreSession()`. The local name is set BEFORE the guard executes.

**Residual edge** (D-RT-14 ATK-14, accepted): if
`GetUnitName("player", true)` returns nil during PLAYER_LOGIN
pre-PLAYER_ENTERING_WORLD timing, `s.localName` stays nil and ALL
restores reject — even legitimate same-character. Conservative; matches
fail-closed intent. **Not a leak.**

---

## F-02 — Type-check on `partnerStyle` / `memory` / `r1WasAllPass` (v0.9.2 #54 §5) — **PASS**

**Severity: PASS / VERIFIED.** Type guards landed.

`State.lua:354-373`:

```
-- v0.9.0 M4 fix: rehydrate Bot module-level state. Defensive nil
-- guards — older session snapshots won't have a `.bot` field.
-- v0.9.2 #54 fix (audit_v0.9.0/54_m4_partnerstyle_quirks.md):
-- TYPE-check each subfield before assigning. A corrupted
-- SavedVariables (hand-edited, partial-write crash, version
-- skew) could populate these as strings/numbers; assigning
-- them blindly causes downstream nil-index crashes the moment
-- any consumer indexes them. `type() == "table"` is the same
-- pattern WHEREDNGN.lua uses for the top-level `WHEREDNGNDB`.
if sess.bot and B.Bot then
    if type(sess.bot.partnerStyle) == "table" then
        B.Bot._partnerStyle = sess.bot.partnerStyle
    end
    if type(sess.bot.memory) == "table" then
        B.Bot._memory = sess.bot.memory
    end
    if type(sess.bot.r1WasAllPass) == "boolean" then
        B.Bot.r1WasAllPass = sess.bot.r1WasAllPass
    end
end
```

Each subfield's type-correctness gates the assignment. A corrupt string
in `partnerStyle` is silently ignored; consumers later see the
`Bot._partnerStyle` value left over from the fresh module load (or nil),
and the `Bot.OnEscalation` `if not Bot._partnerStyle` rebuild guard
takes over.

**Residual** (`audit_v0.9.0/54 §2`, NOT in scope here but worth noting):
the persistence is seat-keyed, not name-keyed. A saved-game restore
where seat→name mapping has shifted misapplies counters to the wrong
human. Out of scope; semantic-not-type defense.

**Residual** (`audit_v0.9.0/54 §4`, restated by
`D-RT-14 ATK-13`): no DEPTH-2 type guards. A corrupt
`partnerStyle[2].tahreebSent.S = "junk"` survives the depth-1 type
check. Crashes at first `ipairs(tahreebSent.S)` in
`Bot.OnPlayObserved`. Out of scope here (fix would be Bot.lua-side
guards), but a known gap.

---

## F-03 — D-RT-14 finding: blanket `pairs` overlay lets corrupt sub-fields through `sess.state` — **FAIL (UNDEFENDED)**

**Severity: HIGH (crash-on-restore for hand-edit; LOW for natural use).**
Confirmed UNFIXED. Exposed surface: every nested mutable table in
`s.state`.

### The defect

`State.lua:309-339`:

```
if not sess.state then return false end
-- Hard-reset s, then overlay the saved fields. Without the wipe a
-- field that was nil at save time would carry over from reset()'s
-- defaults instead of being explicitly absent.
for k in pairs(s) do s[k] = nil end
for k, v in pairs(sess.state) do s[k] = v end
...
-- A few field defaults need to be non-nil so the rest of the code
-- can index them without nil-check noise.
s.hand         = s.hand         or {}
s.bids         = s.bids         or {}
s.tricks       = s.tricks       or {}
s.meldsByTeam  = s.meldsByTeam  or { A = {}, B = {} }
s.meldsDeclared= s.meldsDeclared or {}
s.cumulative   = s.cumulative   or { A = 0, B = 0 }
s.seats        = s.seats        or { [1]=nil, [2]=nil, [3]=nil, [4]=nil }
```

Two distinct layers:
1. **Bulk pairs overlay** at line 314 — copies every saved field
   verbatim. **No type-check.** Hand-edited
   `WHEREDNGNDB.session.state.cumulative = "[]"` lands `s.cumulative`
   = string.
2. **Nil-fallback init** at lines 333-339 — uses `or` short-circuit.
   **A truthy non-table (string, number, true) bypasses the OR.**
   `s.cumulative or {A=0,B=0}` returns the string unchanged.

**Asymmetry with the bot path:** `State.lua:363-373` type-checks
`sess.bot.partnerStyle / memory / r1WasAllPass`. The state path
gets the unvalidated overlay. The v0.9.2 #54 fix landed for `sess.bot.*`
(F-02), but the equivalent fix for `sess.state.*` was never applied.

### Repro (D-RT-14 ATK-7)

1. Stop WoW.
2. Edit `WTF/Account/<acct>/SavedVariables/WHEREDNGN.lua` to set
   `WHEREDNGNDB.session.state.cumulative = "[]"` (string).
3. Restart WoW. PLAYER_LOGIN fires; RestoreSession runs.
4. Line 313 wipes `s`. Line 314 sets `s.cumulative = "[]"`.
5. Line 338's `s.cumulative or { A = 0, B = 0 }` returns `"[]"`
   (truthy).
6. First round-end: `Net.lua:1679` `S.s.cumulative.A + addA` —
   `("[]").A` → nil, `nil + addA` → "attempt to perform arithmetic on
   a nil value". Crash.

### Repro (D-RT-14 ATK-9)

1. Edit SavedVariables to set
   `WHEREDNGNDB.session.state.tricks = "[]"`.
2. PLAYER_LOGIN. RestoreSession runs. Line 314 sets `s.tricks = "[]"`.
3. Line 335's `s.tricks or {}` returns `"[]"`.
4. Line 344 `for _, tr in ipairs(s.tricks or {}) do` — Lua 5.1
   `ipairs` errors with "bad argument #1 to 'ipairs' (table expected,
   got string)". Crash mid-RestoreSession.
5. Function returns nothing. The PLAYER_LOGIN handler's
   `if B.State.RestoreSession()` evaluates the propagated error as a
   pcall failure (depending on engine wrapping) — typically the entire
   event handler unwinds. Subsequent `RegisterAddonMessagePrefix`,
   `MinimapIcon.Show`, the host re-arm block, and the
   `PLAYER_ENTERING_WORLD`-triggered `maybeRequestResync` may all be
   skipped.

### Quote (the gap)

`State.lua:333-339`:

```
s.hand         = s.hand         or {}
s.bids         = s.bids         or {}
s.tricks       = s.tricks       or {}
s.meldsByTeam  = s.meldsByTeam  or { A = {}, B = {} }
s.meldsDeclared= s.meldsDeclared or {}
s.cumulative   = s.cumulative   or { A = 0, B = 0 }
s.seats        = s.seats        or { [1]=nil, [2]=nil, [3]=nil, [4]=nil }
```

**The fix shape** (out of scope — code change forbidden) is the same
pattern used at `State.lua:74` and `State.lua:1530`:

```
if type(s.cumulative) ~= "table" then s.cumulative = {A=0,B=0} end
if type(s.tricks)     ~= "table" then s.tricks     = {} end
... (same for bids, hand, seats, meldsByTeam, meldsDeclared)
if s.contract ~= nil and type(s.contract) ~= "table" then s.contract = nil end
-- coerce numeric leaves
s.cumulative.A = tonumber(s.cumulative.A) or 0
s.cumulative.B = tonumber(s.cumulative.B) or 0
```

### Provenance

The pattern is well-known in the codebase — `WHEREDNGN.lua:69`
type-guards top-level `WHEREDNGNDB`, `State.lua:74` type-guards
`DB.target`, `State.lua:1530` type-guards `WHEREDNGNDB.history`. The
`sess.bot.*` subfields got it in v0.9.2. Only `sess.state.*` was
missed.

`D-RT-14 ATK-7` and `ATK-9` document this as **UNDEFENDED**. Marked for
P1 in `D-RT-14 §recommendations`. Confirmed STILL UNFIXED in current
source.

### Severity

In adversarial use (hand-edit attack): HIGH. A single edit to a single
sub-field crashes RestoreSession — partial-init failure, addon load
broken, /reload soft-locks the player out of any in-progress game.

In natural use: LOW. Garbage SavedVariables only arise from partial-
write crashes, version-skew migrations, or filesystem corruption —
rare. But the SHAPE of the failure is the same as `audit_v0.9.0/47`'s
history-table crash, which was deemed worth fixing.

---

## F-04 — Transient field reset confirmation (D-RT-27) — **PASS** (with three documented PARTIAL leaks)

**Severity: PASS for crash safety; PARTIAL for cosmetic clearing.**

D-RT-27's per-field verdict table covers all 17 transient fields.
Re-verified that every field listed in `TRANSIENT_FIELDS`
(`State.lua:191-247`) is either:
- Explicitly re-cleared by `reset()` (lines 103-119),
- Re-cleared by `ApplyStart` (lines 795, 800, 804-814),
- Re-cleared by `ApplyResyncSnapshot` (lines 524-534), or
- Re-cleared by the C_Timer.After closure that originally set it (e.g.
  `swaDenied` at `Net.lua:2627`, `Net.lua:2761`).

### TRANSIENT_FIELDS roster (from `State.lua:191-247`)

```
pendingHost
localPlayedThisTrick
redealing
takweeshResult
akaCalled
playedCardsThisRound
meldHoldUntil
swaResult
swaDenied
lastRoundResult
lastRoundDelta
lastTrick
```

12 entries, plus the explicit comments-as-documentation noting that
`hostDeckRemainder`, `swaRequest`, `preemptEligible`, and
`pendingPreemptContract` are **NOT** transient (4 fields). Total 16
discussed; the 17th in the audit prompt likely refers to
`expectingResyncRes` (module-local in Net.lua, not in TRANSIENT_FIELDS
since it lives outside `s`).

### D-RT-27 PARTIAL findings (carried forward)

- **F-01 redealing race**: `_HostRedeal` 3s timer collides if two
  redeal calls fire in <3s. Cosmetic; dealer rotation MAY double if
  first closure had time to apply before second invalidates it.
  `Net.lua:1750-1765`. Reachability: low.

- **F-02 `pendingPreemptContract` / `preemptEligible` survive
  ApplyStart**: marked NOT-transient (correct per host /reload mid-
  PREEMPT requirement) but `ApplyStart` doesn't clear them. Defended
  by `_FinalizePreempt`'s phase guard. Defense-in-depth gap.

- **F-04 `lastRoundResult` survives ApplyStart**: cosmetic banner
  field carries from round R into round R+1's bidding phase until
  R+1's resolution overwrites it.

- **F-05 `swaRequest` not cleared at trick-8 round-end**: relies on
  phase guards in `HostResolveSWA` and `_OnSWAReq`/`_OnSWAResp`.

These are all pre-existing PARTIAL findings in `D-RT-27`. **No new
crash surface; no new corruption surface**. No regression from prior
audit.

### Quote (TRANSIENT_FIELDS partial)

`State.lua:225-230` (swaRequest's intentional-non-transient annotation):

```
-- NOTE: swaRequest is NOT transient. If the HOST /reloads while
-- opponents are voting, dropping the request struct silently
-- breaks the flow: clients still see Accept/Deny buttons, but
-- their MSG_SWA_RESP messages hit `if not req` early-return and
-- never resolve. Persisting lets the host's _OnSWAResp continue
-- collating votes after restore.
```

The TRANSIENT_FIELDS architecture is clearly designed and reasoned.
**PASS overall**.

---

## F-05 — Stale `s.winner` leak via ApplyResyncSnapshot (D-RT-17 #12, B-Net-08 H2) — **FAIL (UNFIXED)**

**Severity: HIGH (cosmetic).** Confirmed STILL UNFIXED.

### The gap

`s.winner` is set by `S.ApplyGameEnd` (`State.lua:1597-1607`):

```
function S.ApplyGameEnd(winnerTeam)
    if s.phase == K.PHASE_GAME_END and s.winner == winnerTeam then
        return
    end
    s.phase = K.PHASE_GAME_END
    s.winner = winnerTeam
end
```

It is NOT in `TRANSIENT_FIELDS`, so SaveSession serializes it. But
SaveSession early-returns at GAME_END (`State.lua:252-256`), so
GAME_END phase doesn't actually reach SaveSession's body. The only
surviving path is a **same-WoW-session game restart**:

1. Game ends. `ApplyGameEnd("A")` sets `s.winner = "A"`,
   `s.phase = K.PHASE_GAME_END`.
2. Host clicks "New Game" → `S.HostBeginLobby` (`State.lua:602-621`)
   calls `reset()` → `s.winner = nil` (line 39). Host's `s.winner`
   cleared.
3. **For non-host clients**: `MSG_LOBBY` from the new lobby triggers
   `S.ApplyLobby` (`State.lua:690-750`). The `newGame` branch at
   `:711-727` calls `S.Reset()`. Their `s.winner` cleared too.

That covers the lobby flow. The vulnerable path is:

4. Non-host whose previous game ended with `s.winner` set, then mid-
   new-game /reload → RestoreSession brings phase back, then
   maybeRequestResync fires 2s later → MSG_RESYNC_RES arrives →
   `ApplyResyncSnapshot` runs.

### `ApplyResyncSnapshot` does NOT clear `s.winner`

`State.lua:519-534` is the explicit transient cleanup block:

```
-- Audit fix: clear remaining transient round state so stale
-- per-trick banners (AKA, Takweesh outcome, SWA result, redeal
-- announcement) and pre-emption state from before the rejoin
-- don't leak through the snapshot. The host will re-broadcast any
-- of these that are still active right after the snapshot.
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

11 fields explicitly cleared. **`s.winner` is missing.**

The wire payload (29 fields documented at `State.lua:399-415`) does
NOT include `winner` either. So a stale `s.winner = "A"` from the
previous game survives the resync snapshot application unchanged.

### Repro

1. Same-WoW-session: finish game with team A winning. Host calls
   `ApplyGameEnd("A")` → `s.winner = "A"`. Broadcast received by
   non-host → `_OnGameEnd` → ApplyGameEnd → non-host has
   `s.winner = "A"`.
2. Host starts new game with `HostBeginLobby` → broadcasts MSG_LOBBY.
3. Non-host: `_OnLobby` → ApplyLobby → newGame branch →
   `S.Reset()` → `s.winner = nil`. **At this stage all is well.**
4. Non-host /reloads mid-bid. PLAYER_LOGOUT writes
   `WHEREDNGNDB.session` (state includes phase=PHASE_DEAL2BID,
   `s.winner = nil` at that moment).
5. PLAYER_LOGIN. RestoreSession brings back phase + `s.winner = nil`
   (because line 314 only overlays SAVED fields; nil at save = nil
   at restore).

So the typical-path doesn't bite. But:

- **Variant repro**: a non-host who SKIPS the lobby flow. E.g., the
  rejoiner restored from RestoreSession with phase=PHASE_GAME_END
  (winner="A"), then maybeRequestResync fires for the OLD gameID, the
  host responds with the NEW game's snapshot — `ApplyResyncSnapshot`
  applies new gameID, phase=PLAY, but does NOT clear winner.

  This is the precise sequence D-RT-17 §12 documents:
  > "If a rejoiner has a stale `s.winner = "A"` from an earlier game
  >  in the same session (e.g., they finished one game, their host
  >  started another, they /reloaded mid-bid), `ApplyResyncSnapshot`
  >  won't clear it."

### Severity

Cosmetic. UI consumes `s.winner` only when `s.phase == PHASE_GAME_END`
— which the snapshot rewrite would set to PHASE_PLAY (or whatever the
host is in) before the UI renders. So the phantom banner is masked by
the phase check.

But: any future code path that reads `s.winner` independent of
`s.phase` (for stats, logging, telemetry) would see a ghost value.

### Fix surface (out of scope — code change forbidden)

Add `s.winner = nil` to the cleanup block at `State.lua:524-534`. One
line. `B-Net-08 H2 §recommendation` and `D-RT-17 §12 recommendation`
both cite this exact change.

---

## F-06 — `meldsDeclared` wiped but replay only rebuilds `meldsByTeam` (D-RT-17 #1, B-Net-08 H3) — **FAIL (UI-only)**

**Severity: MEDIUM (UI-only).** Confirmed STILL UNFIXED.

### The gap

`ApplyResyncSnapshot` at `State.lua:514-517` clears all four trick-
related round-history structures:

```
s.tricks       = {}
s.meldsByTeam  = { A = {}, B = {} }
s.meldsDeclared= {}
s.playedCardsThisRound = {}
```

The host's `SendResyncRes` (`Net.lua:386-465`) then replays:
- MSG_BIDCARD (line 397)
- MSG_MELD per `meldsByTeam[team]` entry (lines 403-410, replay
  flag "1")
- MSG_PREEMPT_PASS for PHASE_PREEMPT (lines 416-420)
- MSG_OVERCALL_OPEN + decisions (lines 426-435)
- MSG_TRICK per closed trick (lines 439-447)
- MSG_PLAY for in-flight plays (lines 453-458)
- MSG_AKA if active (lines 461-464)

**No replay reseeds `meldsDeclared`.** `S.ApplyMeld` does NOT write
to `meldsDeclared` either — it only writes to `meldsByTeam`. The
`meldsDeclared[seat] = true` writes happen in:
- `Net.lua:2046-2048` (LocalDeclareMeld — local UI path)
- `Net.lua:3433-3441` (host AFK auto-declare for the meld window)
- `Net.lua:4076-4082`, `Net.lua:4126-4130` (bot decision dispatchers)
- `UI.lua:1987` ("Done" button)

After a non-host /reload mid-PHASE_DEAL3 (still inside trick-1's
meld-declare window), the rejoiner's resynced state has:
- `meldsByTeam` correctly rebuilt by replayed MSG_MELDs.
- `meldsDeclared = {}` (the empty post-clear state).

### Quote

`State.lua:514-517` (the wipe):

```
-- Round history is not snapshotted; it arrives via replayed
-- MSG_MELD / MSG_TRICK broadcasts right after the snapshot.
-- Clear any local state (including RestoreSession leftovers)
-- so the replayed history doesn't duplicate.
s.tricks       = {}
s.meldsByTeam  = { A = {}, B = {} }
s.meldsDeclared= {}
s.playedCardsThisRound = {}
```

`Net.lua:403-410` (the partial replay — only meldsByTeam):

```
for _, team in ipairs({ "A", "B" }) do
    for _, m in ipairs((S.s.meldsByTeam and S.s.meldsByTeam[team]) or {}) do
        local enc = (m.cards and C.EncodeHand(m.cards)) or ""
        whisper(target, ("%s;%d;%s;%s;%s;%s;1"):format(
            K.MSG_MELD, m.declaredBy or 0,
            m.kind or "", m.suit or "", m.top or "", enc))
    end
end
```

The `MSG_MELD` handler at `Net.lua:556-560` calls `_OnMeld` which
calls `S.ApplyMeld`. Read `S.ApplyMeld` (`State.lua:1149+`, walking
through Grep result): writes to `s.meldsByTeam` and dedupes — does
NOT mark `s.meldsDeclared[seat] = true`.

### Repro

1. 4-human PHASE_DEAL3 game. Each seat declares one meld; flags
   stamped at `Net.lua:2046` and similar. `meldsByTeam.A = {melds...}`
   and `meldsDeclared = {[1]=true, [2]=true, [3]=true, [4]=true}`.
2. Seat 3 /reloads mid-window before clicking Done.
3. PLAYER_LOGIN. RestoreSession brings back `meldsDeclared[3] = true`
   from the saved session (line 314). UI hides "Declare" button —
   correct.
4. PLAYER_ENTERING_WORLD → 2s → maybeRequestResync. Host responds
   with snapshot.
5. ApplyResyncSnapshot at line 516 wipes `meldsDeclared = {}`.
6. Replayed MSG_MELDs rebuild `meldsByTeam` correctly. **But
   `meldsDeclared` stays `{}`.**
7. UI consumes `S.s.meldsDeclared[s.localSeat]` (e.g.
   `State.lua:1932`). Returns nil. UI shows "Declare" button as if
   seat 3 hadn't declared yet.
8. Player clicks Declare again → MSG_MELD broadcast → `S.ApplyMeld`
   dedupes via `(seat, kind, top, suit)` check at `State.lua:1159` —
   no double-meld in state. The trick-1 wire gate at
   `State.lua:1154` further protects post-trick-1.

### Severity

State is protected (dedupe + trick-1 gate). The exposed harm is UI:
- The rejoiner sees the declare picker reappear.
- They re-declare a meld they already declared.
- The wire dedupe accepts the duplicate broadcast as a no-op.

No state corruption, no double-scoring. Just confusion + a
re-broadcast of a redundant MSG_MELD.

### Fix surface (out of scope)

Two equivalent shapes (both proposed in `B-Net-08 H3 §recommendation`):

1. Inside the rebuild loop at `Net.lua:403-410`, after the whisper,
   also stamp `S.s.meldsDeclared[m.declaredBy] = true` on the
   sender side — but the sender already has it stamped, so the real
   fix is a parallel walk on the receiver in `ApplyResyncSnapshot`
   AFTER the MSG_MELDs have replayed.
2. OR set `meldsDeclared[seat] = true` inside `S.ApplyMeld` itself as
   part of standard meld application.

Option (2) is one-line and eliminates the divergence between
"local-declare" and "replay-declare" code paths.

---

## F-07 — Cross-character ghost `lastGameID` (D-RT-17 #7, B-Net-08 L2) — **FAIL (THIRD CONFIRMATION)**

**Severity: LOW.** Confirmed STILL UNFIXED. Originally documented in
`audit_v0.7.1/35_save_restore.md`. Re-flagged in `D-RT-17 §7`. Now
re-flagged again here as the third audit cycle to find this defect.

### The gap

The cross-character early-returns at `State.lua:307-308` do NOT clear
`WHEREDNGNDB.lastGameID`:

```
if not sess.owner or not s.localName then return false end
if sess.owner ~= s.localName then return false end
```

`WHEREDNGNDB` is per-account, not per-character. After character A's
in-game /reload, `WHEREDNGNDB.lastGameID = "ABC123"` is written for
restore. If the user then logs in as character B (or character C, or
any non-A), the cross-character guard at line 307-308 rejects the
session — but `lastGameID` survives.

`PLAYER_ENTERING_WORLD` fires unconditionally on every login
(`WHEREDNGN.lua:305-313`):

```
if event == "PLAYER_ENTERING_WORLD" then
    B.State.SetLocalName(GetUnitName("player", true))
    C_Timer.After(2.0, maybeRequestResync)
    return
end
```

`maybeRequestResync` (`WHEREDNGN.lua:100-113`):

```
local function maybeRequestResync()
    if not WHEREDNGNDB then return end
    local id = WHEREDNGNDB.lastGameID
    if not id or id == "" then return end
    if not IsInGroup() then return end
    if B.State.s.isHost then return end
    L.Info("resync", "requesting state for game %s", id)
    if B.Net and B.Net.SendResyncReq then
        B.Net.SendResyncReq(id)
    end
end
```

Character B (in a party) reads character A's surviving `lastGameID`
and broadcasts MSG_RESYNC_REQ on the wrong character's gameID.

### Defense layer

Even when the request arrives, the host's `_OnResyncReq` at
`Net.lua:3147-3155` rejects it because nsender (character B) is not in
the seat roster of game ABC123. **No data leak.**

But:
- The wire request goes out (consumes one cycle of the 5s per-sender
  cooldown table at `Net.lua:3107-3134`).
- A `L.Info("resync", "requesting state for game %s", id)` log line
  fires for the wrong gameID.

### Compounded by B-Net-08 CRIT-1

`B-Net-08` CRIT-1 documents that `K.MSG_RESYNC_REQ = "?"` collides
with `K.MSG_OVERCALL_RESOLVE = "?"`, making `_OnResyncReq` dead code.
So in current source, the ghost request reaches `_OnOvercallResolve`,
fails the `fromHost` guard (sender is rejoiner-character-B, not the
host), and dies silently. The cooldown table is never consulted.
**Practical effect even smaller than D-RT-17 documented** — but only
because resync is fully broken end-to-end.

### Provenance

- `audit_v0.7.1/35_save_restore.md` line 25: documented, marked
  unfixed.
- `D-RT-17 §7`: re-confirmed unfixed.
- `B-Net-08 L2`: re-confirmed unfixed.
- **This audit (B-State-04)**: third confirmation. STILL UNFIXED.

### Fix surface (out of scope)

One line: insert `WHEREDNGNDB.lastGameID = nil` into the cross-
character early-return:

```
if not sess.owner or not s.localName then
    WHEREDNGNDB.lastGameID = nil
    return false
end
if sess.owner ~= s.localName then
    WHEREDNGNDB.lastGameID = nil
    return false
end
```

---

## F-08 — Mid-Takweesh /reload PHASE_SCORE race (D-RT-17 #5, B-N3-6, B-Net-08 H4) — **FAIL (UNFIXED)**

**Severity: HIGH (rare).** Confirmed STILL UNFIXED.

### The race window

`Net.lua:HostResolveTakweesh` (around line 2127+, per D-RT-17):
- Line 2264: `S.ApplyRoundEnd(addA, addB, totA, totB)` — sets
  `s.phase = PHASE_SCORE`, updates `s.cumulative`.
- Line 2273: `S.s.lastRoundResult = nil`.
- Lines 2276-2290: set `S.s.takweeshResult` (TRANSIENT — dropped by
  SaveSession).
- Line 2291: `N.SendRound(addA, addB, totA, totB)` (broadcast).
- Line 2317: `broadcast(...)` for `MSG_TAKWEESH_OUT`.

Between line 2264 and line 2291: the host has phase=PHASE_SCORE +
updated cumulative locally. **No MSG_ROUND broadcast yet.** Other
clients still see phase=PHASE_PLAY waiting for resolution.

### After /reload

PLAYER_LOGOUT fires SaveSession — phase=SCORE, cumulative, persistent
fields all written. `takweeshResult` is in `TRANSIENT_FIELDS`
(`State.lua:212`), DROPPED.

PLAYER_LOGIN. RestoreSession overlays phase=SCORE. PLAYER_LOGIN host
re-arm block at `WHEREDNGN.lua:155-217`:

```
if B.State.s.isHost then
    if B.Net and B.Net.SendLobby then
        B.Net.SendLobby(B.State.s.seats, B.State.s.gameID)
    end
    if B.Net and B.Net.MaybeRunBot then B.Net.MaybeRunBot() end
    -- StartTurnTimer for PHASE bid/play
    -- StartBelTimer for PHASE_DOUBLE/TRIPLE/FOUR/GAHWA
    -- _HostStepPlay for stuck 4-play
    -- M2 re-arm for PHASE_OVERCALL + swaRequest
end
```

**There is NO branch for `phase == K.PHASE_SCORE`.** Nothing
re-broadcasts MSG_ROUND.

### Result

- Host UI shows score panel (correct phase locally).
- Clients still in PHASE_PLAY waiting for trick advance.
- Host's SWA timer was already cancelled at `Net.lua:2144` before
  ApplyRoundEnd.
- The takweesh-detail banner is gone (transient field dropped).
- Soft-lock: clients have no future broadcast incoming.

Recovery: host runs `/baloot reset` (`Slash.lua:129`) or some other
state-mutating action.

### Quote

`WHEREDNGN.lua:155-217` (the re-arm block — phases listed):

```
if B.State.s.isHost then
    if B.Net and B.Net.SendLobby then ... end
    if B.Net and B.Net.MaybeRunBot then B.Net.MaybeRunBot() end
    ...
    -- Bel / Triple / Four / Gahwa eligibility
    if s.phase == K.PHASE_DOUBLE and ... then
        B.Net.StartBelTimer(defSeat, "double")
    elseif s.phase == K.PHASE_TRIPLE and ... then
        B.Net.StartBelTimer(bidder, "triple")
    elseif s.phase == K.PHASE_FOUR and ... then
        B.Net.StartBelTimer(defSeat, "four")
    elseif s.phase == K.PHASE_GAHWA and ... then
        B.Net.StartBelTimer(bidder, "gahwa")
    end
    ...
    if B.State.s.phase == K.PHASE_PLAY and s.trick
       and s.trick.plays and #s.trick.plays >= 4 then
        ... C_Timer.After(0.5, _HostStepPlay) ...
    end
    ...
    if B.State.s.phase == K.PHASE_OVERCALL ... then
        ... _HostResolveOvercall re-arm ...
    end
    if B.State.s.swaRequest ... B.State.s.phase == K.PHASE_PLAY then
        ... HostResolveSWA re-arm ...
    end
end
```

**No branch for PHASE_SCORE.** Confirmed STILL UNFIXED.

### Reachability

The race window is microseconds — PLAYER_LOGOUT must fire between two
adjacent Lua statements. /reload typing latency makes this almost
impossible by hand, but:
- WoW client crash mid-resolve.
- OS-level kill (kill -9, power loss).
- Rare CHAT_MSG_ADDON event re-entrancy.

Probability low. Severity HIGH on the rare hit because there's no
auto-recovery.

### Cross-ref

- `D-RT-17 §5` — original finding. Recommended either re-broadcast
  branch on PLAYER_LOGIN, or move SendRound earlier in
  HostResolveTakweesh.
- `D-RT-27 §F-14` — re-confirmed.
- `B-Net-08 H4` — confirmed.
- This audit (`B-State-04 §F-08`): fourth confirmation. UNFIXED.

`D-RT-27 §F-15` extends the same shape to `HostResolveSWA` (lines
3052-3058) — a parallel race on the SWA path. Equivalent unfixed
defect.

---

## F-09 — Mid-deal /reload (B-Net-07 F12) — **PASS** for host internal consistency, **PARTIAL** for peer view

**Severity: PARTIAL.** Host state internally consistent;
non-host peers may diverge briefly.

### The setup

`HostDealInitial` (`State.lua:1611+`) populates `s.hostHands` and
`s.hostDeckRemainder`, sets the bid card. `HostDealRest` (later, at
PHASE_DEAL3) reads both to deal the final 3 cards.

`State.lua:191-247` (TRANSIENT_FIELDS commentary):

```
-- NOTE: hostDeckRemainder is NOT transient — it pairs with
-- hostHands across PHASE_DEAL1..PHASE_DEAL3. A host /reload after
-- the initial 5-card deal but before the final 3-card deal would
-- restore hostHands without hostDeckRemainder; then HostDealRest
-- short-circuits on the missing remainder and the round soft-
-- locks. Both fields must persist together.
```

Both `hostHands` and `hostDeckRemainder` are persistent (NOT
transient). They co-survive a /reload.

### Host /reload mid-DEAL2BID — PASS

- SaveSession writes both fields.
- RestoreSession brings both back.
- HostDealRest at `State.lua:1624+` (per D-RT-17 §4, around line
  1625 with the nil-guard) succeeds.
- D-RT-17 §4 explicitly verifies this case as PASS.

### The peer-divergence concern

`B-Net-07 F12` is referenced as the underlying finding. The structure
is: a host deal-phase /reload preserves the host's internal
consistency, but the timing of the deal broadcast (`MSG_DEAL`,
`MSG_HAND` per-seat whispers) may have started or completed for some
clients before the /reload but not others.

After PLAYER_LOGIN, the host's re-arm block at `WHEREDNGN.lua:157-159`:

```
if B.Net and B.Net.SendLobby then
    B.Net.SendLobby(B.State.s.seats, B.State.s.gameID)
end
```

SendLobby refreshes the seat list but does NOT re-fire the deal phase
or re-whisper MSG_HAND. Clients who already received cards have them.
Clients who hadn't yet: silent gap. The bid card may also not be
re-broadcast.

`MaybeRunBot` (`Net.lua:158-161`-pattern) resumes bot scheduling but
doesn't re-deal.

`_HostStepPlay` re-fire at `WHEREDNGN.lua:206-217` only handles stuck
4-play tricks, not stuck deals.

### Quote

`WHEREDNGN.lua:155-160` (post-restore host):

```
if B.State.s.isHost then
    if B.Net and B.Net.SendLobby then
        B.Net.SendLobby(B.State.s.seats, B.State.s.gameID)
    end
    if B.Net and B.Net.MaybeRunBot then B.Net.MaybeRunBot() end
```

**No re-deal.** Peers who missed MSG_DEAL or MSG_HAND don't get a
re-fire. Their hands stay empty. They send MSG_RESYNC_REQ on
PLAYER_ENTERING_WORLD if they /reloaded too — and the host's
SendResyncRes whispers MSG_HAND for the rejoiner (per `B-Net-08 §reply
chain`). But peers who DIDN'T /reload (just sat there waiting for the
deal) get no re-fire. They wait silently.

### Severity

PARTIAL — host internally consistent (the documented invariant), but
non-host peers can land in a "no hand" state with no recovery
mechanism short of their own /reload.

In healthy flow, the deal phase happens in <100ms — the window for a
host /reload mid-deal-broadcast is tiny. Probability low; severity
MEDIUM if hit because the peers have no UX prompt to /reload.

### Cross-ref

- `B-Net-07 F12` — documented. Out of scope here (this audit covers
  persistence layer; the deal-broadcast layer is B-Net-07's
  jurisdiction).

---

## F-10 — Multi-character session-overwrite at IDLE/LOBBY/GAME_END (D-RT-17 #10) — **FAIL (PARTIAL)**

**Severity: LOW (footgun for multi-character users).** Confirmed.

### The defect

`State.lua:250-256`:

```
function S.SaveSession()
    WHEREDNGNDB = WHEREDNGNDB or {}
    if s.phase == K.PHASE_IDLE or s.phase == K.PHASE_LOBBY
       or s.phase == K.PHASE_GAME_END then
        WHEREDNGNDB.session = nil
        return
    end
    ...
```

`WHEREDNGNDB.session = nil` UNCONDITIONALLY at IDLE/LOBBY/GAME_END
phases. **Does NOT check `s.localName == sess.owner`.**

### Repro

1. Character A: starts a game, plays some rounds. /reload mid-PLAY.
2. PLAYER_LOGOUT → SaveSession → phase==PHASE_PLAY → snap written
   with owner=A.
3. PLAYER_LOGIN as character A → RestoreSession succeeds → phase=PLAY.
4. Character A logs out for the day (game still mid-PLAY).
5. PLAYER_LOGOUT → SaveSession → owner=A persists. **All good so far.**
6. User logs in as character B (different toon, same WoW account).
7. PLAYER_LOGIN. init() → SetLocalName("B"). RestoreSession:
   `sess.owner = "A" ~= s.localName = "B"` → returns false. Session
   stays in WHEREDNGNDB.session. **Still fine; A's data preserved.**
8. Character B is in PHASE_IDLE (no restore happened).
9. Character B logs out at PHASE_IDLE.
10. PLAYER_LOGOUT → SaveSession. Phase is IDLE → line 254
    `WHEREDNGNDB.session = nil`. **A's saved game is now obliterated.**
11. User logs in as character A. PLAYER_LOGIN. RestoreSession:
    `if not WHEREDNGNDB.session then return false`. **A's saved game
    is gone with no recovery.**

### The defect-line

`State.lua:252-256`:

```
if s.phase == K.PHASE_IDLE or s.phase == K.PHASE_LOBBY
   or s.phase == K.PHASE_GAME_END then
    WHEREDNGNDB.session = nil
    return
end
```

The unconditional nil-write doesn't gate on whether the session
belongs to the CURRENT character. Any character logging out at
IDLE/LOBBY/GAME_END nukes any other character's mid-game save.

### Severity

LOW — multi-character users only. But silent: the user has no warning
that switching characters destroys their mid-game state. In single-
character households this never bites.

### Cross-ref

- `D-RT-17 §10` — original finding. Recommended either:
  - Per-character session scoping:
    `WHEREDNGNDB.session[ownerName]` keyed map.
  - OR conditional nil:
    `if s.localName == sess.owner then WHEREDNGNDB.session = nil end`.
- `D-RT-14 ATK-14 §residual` — references this footgun.

This audit (`B-State-04 §F-10`): re-confirms. STILL UNFIXED.

### Fix surface (out of scope)

Conditional clear is one extra line:

```
if s.phase == K.PHASE_IDLE or s.phase == K.PHASE_LOBBY
   or s.phase == K.PHASE_GAME_END then
    if WHEREDNGNDB.session
       and WHEREDNGNDB.session.owner == s.localName then
        WHEREDNGNDB.session = nil
    end
    return
end
```

Per-character scoping is more invasive — every read/write to
`WHEREDNGNDB.session` would need to switch to `[ownerName]` keyed
access.

---

## Findings summary table

| # | Audit-prompt item | Severity | Status |
|---|---|---|---|
| F-01 | Cross-character fail-closed (#54) | PASS | VERIFIED |
| F-02 | Type-check on partnerStyle/memory/r1WasAllPass (#54) | PASS | VERIFIED |
| F-03 | **D-RT-14: blanket pairs overlay through `sess.state`** | **FAIL HIGH (hand-edit)** | **STILL UNFIXED** |
| F-04 | Transient field reset (D-RT-27) | PASS | All 17 confirmed; 3 PARTIAL leaks documented in D-RT-27 |
| F-05 | Stale `s.winner` via ApplyResyncSnapshot (D-RT-17 #12, B-Net-08 H2) | FAIL HIGH (cosmetic) | STILL UNFIXED |
| F-06 | meldsDeclared replay gap (D-RT-17 #1, B-Net-08 H3) | FAIL MEDIUM (UI) | STILL UNFIXED |
| F-07 | Cross-character ghost lastGameID (D-RT-17 #7, B-Net-08 L2) | FAIL LOW | **THIRD confirmation; STILL UNFIXED** |
| F-08 | Mid-Takweesh /reload PHASE_SCORE race (D-RT-17 #5, B-Net-08 H4) | FAIL HIGH (rare) | STILL UNFIXED |
| F-09 | Mid-deal /reload (B-Net-07 F12) | PARTIAL | Host-consistent; peer divergence possible |
| F-10 | Multi-character session-overwrite (D-RT-17 #10) | FAIL LOW (footgun) | STILL UNFIXED |

---

## Fix-priority order (consistent with B-Net-08 §critical-path)

1. **F-03 (sess.state subfield type guards)** — biggest crash-on-
   restore surface. Same one-shape fix as ATK-7/ATK-9. After the bulk
   pairs overlay at `State.lua:314`, replace the `or {}` fallbacks at
   `:333-339` with `if type(...) ~= "table" then ... end` guards.
   Mirrors the v0.9.2 #54 fix on the bot-subfield path. P1 priority
   per `D-RT-14 §recommendations`.

2. **F-08 (Mid-Takweesh PHASE_SCORE)** — host PLAYER_LOGIN re-arm
   needs PHASE_SCORE branch that re-broadcasts MSG_ROUND. OR shrink
   the race window by moving `N.SendRound` to immediately after
   `S.ApplyRoundEnd` in HostResolveTakweesh and HostResolveSWA. Same
   architectural pattern as the v0.9.0 M1/M2 fixes.

3. **F-05 (s.winner cleanup)** — one-line addition to
   `State.lua:524-534` cleanup block. `s.winner = nil` along with
   the other transient cleanups.

4. **F-06 (meldsDeclared replay)** — set
   `s.meldsDeclared[seat] = true` inside `S.ApplyMeld` as part of
   standard meld-application. Eliminates the local-vs-replay path
   divergence.

5. **F-07 (cross-character ghost lastGameID)** — one-line: clear
   `WHEREDNGNDB.lastGameID = nil` in the cross-character early-return
   at `State.lua:307-308`. Originally flagged in
   `audit_v0.7.1/35_save_restore.md`; this is the third audit cycle
   to find it.

6. **F-10 (multi-character session-overwrite)** — guard the IDLE/
   LOBBY/GAME_END nil-write with
   `WHEREDNGNDB.session.owner == s.localName`.

7. **F-09 (mid-deal peer divergence)** — out of scope for this
   audit; properly belongs to B-Net-07 §deal-broadcast. Recovery
   channel for non-host peers in deal-phase desync is the broader
   question.

---

## Files referenced

- `C:\CLAUDE\WHEREDNGN\State.lua` — primary subject (SaveSession,
  RestoreSession, ApplyResyncSnapshot, TRANSIENT_FIELDS, reset)
- `C:\CLAUDE\WHEREDNGN\WHEREDNGN.lua` — PLAYER_LOGIN handler,
  init(), maybeRequestResync, ensureDB
- `C:\CLAUDE\WHEREDNGN\Net.lua` — SendResyncRes replay block,
  HostResolveTakweesh, HostResolveSWA, _OnResyncReq
- `C:\CLAUDE\WHEREDNGN\.swarm_findings\audit_v0.9.0\54_m4_partnerstyle_quirks.md`
- `C:\CLAUDE\WHEREDNGN\.swarm_findings\audit_v0.9.0\52_telemetry_reload.md`
- `C:\CLAUDE\WHEREDNGN\.swarm_findings\audit_v0.7.1\35_save_restore.md`
- `C:\CLAUDE\WHEREDNGN\.swarm_findings\review_v0.10.2\_track_D_redteam\D-RT-14_savedvars_attack.md`
- `C:\CLAUDE\WHEREDNGN\.swarm_findings\review_v0.10.2\_track_D_redteam\D-RT-17_resync_edges.md`
- `C:\CLAUDE\WHEREDNGN\.swarm_findings\review_v0.10.2\_track_D_redteam\D-RT-27_reset_redeal.md`
- `C:\CLAUDE\WHEREDNGN\.swarm_findings\review_v0.10.2\_track_B_code\B-Net-07_hand_deal.md`
- `C:\CLAUDE\WHEREDNGN\.swarm_findings\review_v0.10.2\_track_B_code\B-Net-08_resync_replay.md`
