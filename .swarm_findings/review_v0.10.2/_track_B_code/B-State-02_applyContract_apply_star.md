# B-State-02 — Deep audit of contract / bid / escalation `Apply*` state mutations

Scope: `S.ApplyContract`, `S.ApplyBid`, `S.ApplyDouble`, `S.ApplyTriple`,
`S.ApplyFour`, `S.ApplyGahwa`, `S.FinalizeOvercall`, `S.BeginOvercall`,
`S.RecordOvercallDecision`, `S.ApplyPreempt`, `S.ApplyPreemptPass`,
`S.HostBeginRound2`, `S.HostAdvanceBidding` (incl. `parseBid`),
`R.CanBel`, `R.CanOvercall`, `R.ResolveOvercall`, plus the
`_OnOvercallResolve` companion handler.

**No code modified.** Each finding cites `file:line` from
`C:\CLAUDE\WHEREDNGN`.

Verified against / cross-references: B-Net-02 H1/M1/M2/M3/M4, B-Net-06
F12, D-RT-15 CRIT-2.

Some functions named in the brief (`S.ApplyPass`, `S.ApplyAshkal`,
`S.ApplyOvercallResolve`, `S.HostBeginRound1`) **do not exist** in the
codebase — see the "Functions named in scope but not present" section
at the end of this document. `S.ApplyPreemptDecline` is named
`S.ApplyPreemptPass` in production.

---

## CRITICAL findings

### B-State-02-CRIT-1 — `S.ApplyContract` does not clear `s.overcall` on contract finalize (echoes B-Net-02 M3)

**Severity: HIGH (functionally MEDIUM in the canonical flow; HIGH on
wire-loss + the CRIT collision under B-Net-02 CRIT-1).**

**Repro:**

`State.lua:1025-1070` (`S.ApplyContract`) constructs a fresh
`s.contract` and rolls phase to `PHASE_DOUBLE` unconditionally, but it
never touches `s.overcall`:

```
function S.ApplyContract(bidder, btype, trump)
    local trumpNorm = (trump ~= "" and trump) or nil
    if s.contract
       and s.contract.bidder == bidder
       and s.contract.type   == btype
       and s.contract.trump  == trumpNorm then
        return
    end
    s.contract = {
        type    = btype,
        trump   = trumpNorm,
        bidder  = bidder,
        doubled = false, tripled = false, foured = false, gahwa = false,
        belOpen    = false,
        tripleOpen = false,
        fourOpen   = false,
    }
    s.phase = K.PHASE_DOUBLE
    s.turn = nil
    s.turnKind = nil
    s.belPending = {}
    local oppA = bidder == 1 or bidder == 3
    if oppA then s.belPending = { 2, 4 } else s.belPending = { 1, 3 } end
    log("contract bidder=%d type=%s trump=%s", bidder, btype, tostring(trump))
    if B.Sound and B.Sound.Cue then B.Sound.Cue(K.SND_CONTRACT) end
    if B.Net and B.Net.StartLocalWarn then B.Net.StartLocalWarn("bel") end
end
```

Compare `S.FinalizeOvercall` (`State.lua:986-1023`) which DOES clear
`s.overcall = nil` before the same `s.phase = K.PHASE_DOUBLE`. The
canonical host-driven flow always emits `MSG_OVERCALL_RESOLVE` (which
clears `s.overcall` on the receiver via `Net.lua:1148`) BEFORE
`MSG_CONTRACT`. So in the happy path nothing leaks.

But:

1. `MSG_OVERCALL_RESOLVE` and `MSG_RESYNC_REQ` collide on tag `"?"`
   (B-Net-02 CRIT-1) — every resync request from a peer gets routed
   to `_OnOvercallResolve`. Conversely, a malformed/lost
   `MSG_OVERCALL_RESOLVE` frame leaves the receiver with `s.overcall`
   still populated.
2. CHAT_MSG_ADDON delivery is at-most-once and PARTY-channel ordering
   isn't strict — `MSG_CONTRACT` may arrive before the `MSG_OVERCALL_*`
   sequence completes.
3. A snapshot replay from `S.ApplyResync` (which DOES set
   `s.contract`, line 435) would also be inconsistent if a stale
   `s.overcall` is somehow alive.

If `s.contract` is overwritten with no `s.overcall` clear:
- UI render paths that branch on `s.overcall ~= nil` keep showing the
  overcall window's seat-decision strip on top of the new
  PHASE_DOUBLE state.
- `S.FinalizeOvercall` becomes callable even though the contract has
  already advanced (line 987 only checks `not s.overcall or not
  s.contract`); a stale finalize on top of a fresh contract would
  re-mutate `s.contract.type/bidder/trump`.

**Fix recommendation:**

Clear defensively in `S.ApplyContract`:

```
s.contract = { … }
s.phase = K.PHASE_DOUBLE
s.turn = nil
s.turnKind = nil
s.overcall = nil  -- contract finalize implies overcall closed
```

This is belt-and-braces — the canonical path already clears via
`_OnOvercallResolve`, but the gate matches the semantic invariant
"a contract is set ⇒ overcall is closed."

---

### B-State-02-CRIT-2 — `S.ApplyDouble` Sun → PHASE_PLAY shortcut leaves `s.belPending` cleared but does NOT run the AFK pre-warn that the bidder team's strategic decision implicitly requires

**Severity: LOW (correctness-OK; flagged for verification consistency).**

**Repro:**

`State.lua:1075-1097`:

```
function S.ApplyDouble(seat, open)
    if not s.contract then return end
    s.contract.doubled = true
    s.contract.belOpen = (open ~= false)
    s.belPending = nil
    s.turn = nil
    s.turnKind = nil
    -- Sun rule (Saudi): "في الصن لايوجد الثري والفور والقهوة" — Sun
    -- has only Bel; no Triple/Four/Gahwa. Sun + Bel goes straight to
    -- PLAY regardless of open/closed (no rung to advance to).
    if s.contract.type == K.BID_SUN then
        s.phase = K.PHASE_PLAY
        return
    end
    -- Closed: chain ends; no Triple window.
    if not s.contract.belOpen then
        s.phase = K.PHASE_PLAY
        return
    end
    s.phase = K.PHASE_TRIPLE
    if B.Net and B.Net.StartLocalWarn then B.Net.StartLocalWarn("triple") end
end
```

The Sun → PHASE_PLAY shortcut and the closed-Bel → PHASE_PLAY shortcut
both correctly:
- Set `doubled = true`.
- Set `belOpen` per the `open` flag (Sun ignores it for downstream
  multiplier computation, since `R.ScoreRound` collapses Sun's
  multiplier to Sun-Bel only — `Rules.lua:884-887`).
- Clear `s.belPending`.
- Clear turn / turnKind.
- Roll `s.phase = K.PHASE_PLAY`.

Note: `R.ScoreRound:794-806` correctly normalizes Sun-with-stale-
tripled/foured/gahwa flags to "Bel only" — defense-in-depth against
a hand-edited save or a hostile peer that sets those flags directly.

The Sun-Bel branch correctly does NOT call `B.Net.StartLocalWarn` for
"triple" because Sun has no triple. **No issue here**, but flagged
because the equivalent positive case (`belOpen=true` → PHASE_TRIPLE)
DOES call StartLocalWarn — the asymmetry is intentional but worth a
sanity-check comment in the code.

**No fix recommended.** Confirmed correct against
`docs/strategy/escalation.md` and the v0.10.0 R2 rule fix.

---

### B-State-02-CRIT-3 — `_OnOvercallResolve` empty-payload phase demotion (echoes B-Net-06 F12 / D-RT-15 CRIT-2)

**Severity: HIGH (already documented; restated for completeness on
this audit's scope).**

**Repro:**

`Net.lua:1123-1151`:

```
function N._OnOvercallResolve(sender, takenStr, by, otype)
    if fromSelf(sender) then return end
    if not fromHost(sender) then return end
    if S.s.isHost then return end
    -- v0.8.6 H1 fix: trust the wire, don't re-derive locally
    S.s.overcall = nil
    S.s.phase = K.PHASE_DOUBLE
    if B.UI and B.UI.Refresh then B.UI.Refresh() end
end
```

There is **no payload validation** and **no phase guard**. Any
`MSG_OVERCALL_RESOLVE` (or `MSG_RESYNC_REQ`-mistargeted via the `"?"`
tag collision) frame from a `fromHost`-passing sender, regardless of
the current phase, demotes the receiver to `PHASE_DOUBLE`. If the
receiver was already in PHASE_PLAY, mid-trick state desyncs.

Fix is the one-line phase guard:

```
if S.s.phase ~= K.PHASE_OVERCALL then return end
```

(Plus the tag rename per B-Net-02 CRIT-1.)

**Fix recommendation:** see B-Net-02 CRIT-2 / B-Net-06 F12 for full
recommendation. No new finding; restated to keep this audit
self-contained.

---

## HIGH-severity findings

### B-State-02-H1 — `S.ApplyBid` does not validate the `bid` value (echoes B-Net-02 M1/M2/M4)

**Severity: HIGH (latent — the wire-side handler `_OnBid` partially
validates, but the state primitive accepts any string).**

**Repro:**

`State.lua:889-928`:

```
function S.ApplyBid(seat, bid)
    if s.bids[seat] == bid then return end
    s.bids[seat] = bid
    log("bid seat=%d bid=%s", seat, bid)
    if B.Sound and B.Sound.Cue and bid then
        local snd
        if bid == K.BID_PASS then
            local anyNonPass = false
            for seat2, b in pairs(s.bids) do
                if seat2 ~= seat and b and b ~= K.BID_PASS then
                    anyNonPass = true; break
                end
            end
            if not anyNonPass then
                snd = (s.bidRound == 2) and K.SND_VOICE_WLA or K.SND_VOICE_PASS
            end
        elseif bid == K.BID_SUN then     snd = K.SND_VOICE_SUN
        elseif bid == K.BID_ASHKAL then  snd = K.SND_VOICE_ASHKAL
        elseif bid:sub(1, #K.BID_HOKM) == K.BID_HOKM then
            snd = K.SND_VOICE_HOKM
        end
        if snd then B.Sound.Cue(snd) end
    end
end
```

Issues at the state-layer:

1. **Empty bid (`""`) accepted** — Lua's `not bid` is false for `""`,
   so an empty wire payload writes `s.bids[seat] = ""`. `parseBid("")`
   returns nil downstream (`State.lua:1671-1679`); the seat is treated
   as "bid nothing" but its `s.bids[seat]` slot is non-nil. The next-
   bidder walker (`State.lua:1820-1822`) skips this seat (since
   `s.bids[seat] ~= nil`), but the count in `HostAdvanceBidding`
   includes it (line 1702). With 3 valid bids + 1 empty, `count==4`
   triggers premature redeal. **Confirmed as B-Net-02 M1.**

2. **Malformed Hokm trump suit (`HOKM:Z`) accepted** — `parseBid`
   (`State.lua:1675-1677`) does:
   ```
   if b and b:sub(1, 4) == K.BID_HOKM then
       return K.BID_HOKM, b:sub(6, 6)
   end
   ```
   so `parseBid("HOKM:Z")` returns `(K.BID_HOKM, "Z")`. This survives
   into `s.contract.trump = "Z"` (the `trumpNorm` filter in
   `S.ApplyContract:1033` only collapses `""` to nil, not invalid
   non-empty suits). Trick play then has no card with suit "Z" — the
   game becomes effective Sun without the multiplier. **Confirmed as
   B-Net-02 M4.**

3. **Illegal Ashkal voice cue from seats 1/2** — `S.ApplyBid` plays
   `SND_VOICE_ASHKAL` regardless of bid position. `HostAdvanceBidding`
   silently drops it at lines 1755-1757 if `bidPosition < 3`, but the
   audio cue has already played on every client. **Confirmed as
   B-Net-02 M2.**

4. **Idempotence is `s.bids[seat] == bid`** — same-string re-apply is
   correctly suppressed. But two DIFFERENT bids from the same seat
   (e.g. a duplicate frame from a network race writing `HOKM:S` then
   `HOKM:H`) would BOTH write — only the second persists (overwrite).
   The wire-side gate `if S.s.bids and S.s.bids[seat] ~= nil then
   return end` (`Net.lua:844`) catches this for non-host receivers,
   but the host's authoritative call-path `_HostStepBid → … →
   S.ApplyBid` doesn't pass through `_OnBid`, so a buggy host bot or
   `LocalBid` race could overwrite. The state primitive itself doesn't
   defend.

**Fix recommendation:**

Either (option A — fully defensive at state layer):

```
function S.ApplyBid(seat, bid)
    if not seat or seat < 1 or seat > 4 then return end
    if not bid or bid == "" then return end
    -- Validate bid format
    local ok = (bid == K.BID_PASS) or (bid == K.BID_SUN)
            or (bid == K.BID_ASHKAL)
            or (bid:sub(1, #K.BID_HOKM) == K.BID_HOKM
                and #bid == #K.BID_HOKM + 2
                and bid:sub(#K.BID_HOKM+1, #K.BID_HOKM+1) == ":"
                and ({S=1,H=1,D=1,C=1})[bid:sub(-1)])
    if not ok then return end
    -- Stronger idempotence: reject any second bid from the same seat
    if s.bids[seat] ~= nil then return end
    s.bids[seat] = bid
    -- ... rest of voice-cue logic
end
```

Or option B (validate at wire only, document state primitive as
"trusted-input"). Mixed coverage right now is the worst of both.

---

### B-State-02-H2 — `S.ApplyContract` does not validate `bidder` seat range (echoes B-Net-02 H2)

**Severity: HIGH.**

**Repro:**

`State.lua:1025-1070`:

```
function S.ApplyContract(bidder, btype, trump)
    local trumpNorm = (trump ~= "" and trump) or nil
    if s.contract
       and s.contract.bidder == bidder
       and s.contract.type   == btype
       and s.contract.trump  == trumpNorm then
        return
    end
    s.contract = {
        type    = btype, trump = trumpNorm, bidder = bidder, …
    }
    …
    local oppA = bidder == 1 or bidder == 3
    if oppA then s.belPending = { 2, 4 } else s.belPending = { 1, 3 } end
```

`bidder=9` evaluates `oppA=false` (9 is neither 1 nor 3), so defenders
`{1,3}`. The bidder seat is stored as `9`. Later
`(s.contract.bidder % 4) + 1 = 2` is used in `_OnDouble` (`Net.lua:867`)
and similar handlers — silently picks seat 2 as Bel-eligible defender,
which contradicts the just-derived `belPending = {1,3}`.

Also: `bidder=nil` would write `s.contract.bidder=nil`, and the `oppA`
check would be `nil == 1 or nil == 3` (both false), still routing to
the `{1,3}` defender pair. But `R.TeamOf(nil)` (called from
`R.ScoreRound:677`) returns nil, breaking score computation.

**Mitigation:** `_OnContract` (`Net.lua:856`) gates on `if not bidder
or not btype` — rejects nil. But out-of-range numbers pass. **Confirmed
as B-Net-02 H2.**

**Fix recommendation:**

Add range gate at state-layer entry:

```
if not bidder or bidder < 1 or bidder > 4 then return end
if not btype then return end
```

---

### B-State-02-H3 — `contract.forced` field is read in 3 places but never set anywhere in production code (echoes B-Net-02 H1)

**Severity: HIGH (latent — the gates are dead branches).**

**Repro:**

`contract.forced` is checked at:

1. `Rules.lua:576` (`R.CanOvercall`):
   ```
   if contract.forced then return false end
   ```
2. `State.lua:948` (`S.BeginOvercall`):
   ```
   if s.contract.forced then return false end
   ```
3. `Net.lua:1161` (`N._HostBeginOvercallWindow`):
   ```
   if S.s.contract.forced then return false end
   ```

`S.ApplyContract:1040-1054` constructs the contract table without a
`forced` field. The state-resync path `S.ApplyResync:435-445`
deserializes type / trump / bidder / doubled / tripled / foured /
gahwa / tripleOpen / fourOpen — but **NOT `forced`**. The history-row
serializer at `State.lua:1566` (`forced = s.contract.forced and 1 or
0`) reads-and-writes the field for round-history archival, but
nothing ever sets `s.contract.forced = true` outside test code:

```
$ grep -r 'contract\.forced *=' WHEREDNGN/ → only test_state_bot.lua,
                                              test_rules.lua
$ grep -r 'forced *= *true' WHEREDNGN/    → only test_rules.lua:950
```

Comments at `Rules.lua:569-572` document the intent:

> Forced/Takweesh-recovery contracts (`contract.forced == true`) do
> NOT trigger the overcall window; the predicate returns false for
> every seat in that case.

But the Takweesh recovery path (`HostResolveTakweesh`,
`Net.lua:2127`) does NOT construct a forced contract — it consumes
the existing contract and goes straight to score (`S.ApplyRoundEnd`
at `Net.lua:2264`).

**Effect:** the three gates are dead. A future contributor reading
`R.CanOvercall` will assume forced-contract semantics are wired and
may build on a false premise.

**Fix recommendation:**

Either:
- **Remove the dead gates** — keeps the invariant "every contract
  is overcall-eligible per type/non-Ace rules" and removes the
  `forced` field from the contract struct + history serializer.
- **Or wire up the actual feature:** the documented use case
  (Takweesh during bidding → forced contract) requires
  `S.ApplyContract` to accept a `forced` flag and propagate it. The
  history serializer is already in place; the state primitives are
  already gated; only the constructor + caller-site need extension.

No urgency — current behavior is correct because the gates simply
never fire. **Confirmed as B-Net-02 H1.**

---

## MEDIUM-severity findings

### B-State-02-M1 — `S.ApplyContract` idempotence check uses `(bidder, type, trump)` only — ignores `forced` and `belOpen` flags

**Severity: MEDIUM (latent given H3, but a bug if/when forced wires
in).**

**Repro:**

`State.lua:1034-1039`:

```
if s.contract
   and s.contract.bidder == bidder
   and s.contract.type   == btype
   and s.contract.trump  == trumpNorm then
    return
end
```

If a future caller wires up forced contracts (per H3), the
idempotence check would consider a forced and a non-forced contract
with the same `(bidder, type, trump)` IDENTICAL — early-returns
without resetting `forced`. So a regular contract that gets re-
applied as forced (e.g. mid-round Takweesh recovery) would silently
keep the old `forced=nil` and the gates wouldn't fire.

Today this is moot (forced is never set), but if H3 is fixed by
wiring the feature, this idempotence check is the second bug to fix.

**Fix recommendation:**

Either fold `forced` into the idempotence comparison, OR (preferred)
make the idempotence early-return only happen when ALL contract
fields match — including `doubled/tripled/foured/gahwa/openClosed
flags`. Currently a duplicate `MSG_CONTRACT` arriving AFTER an
escalation has been applied would fall through the idempotence check
(because all 4 escalation flags are false on the new construct)
which is intentional per the comment at lines 1027-1032 — but then
the comment claims this preserves escalations, which it does ONLY
because the `(bidder,type,trump)` triple matches.

**Confirmed correct in current behavior; flagged for forced/migration
edge.**

---

### B-State-02-M2 — `S.ApplyDouble/Triple/Four/Gahwa` do not validate `seat` argument

**Severity: MEDIUM.**

**Repro:**

`State.lua:1075-1097` (`S.ApplyDouble`):

```
function S.ApplyDouble(seat, open)
    if not s.contract then return end
    s.contract.doubled = true
    …
end
```

The `seat` argument is **not used** inside the function body — only
the `open` flag is consumed. The wire-side handler `_OnDouble`
(`Net.lua:867-868`) gates on `seat == eligibleSeat` where
`eligibleSeat = (S.s.contract.bidder % 4) + 1`. So only the eligible
defender can fire the wire frame. But the state primitive itself
takes `seat` as an unused arg — an internal direct call from a future
caller could pass any value (including nil) and the function would
proceed.

Same pattern in `S.ApplyTriple` (`State.lua:1101`), `S.ApplyFour`
(`State.lua:1119`), `S.ApplyGahwa` (`State.lua:1140`) — all take
`seat` but ignore it.

**Effect:** today, harmless. But if the wire-side `seat` gate is ever
weakened (e.g. accepting any defender, not just the eligible one),
the state primitive provides no defense.

**Fix recommendation:**

Either remove the unused `seat` parameter (cleaner), or actually use
it for an eligibility assertion (defense-in-depth). Recommend the
former — the state-machine invariants (current phase + bidder seat
position) are sufficient; the seat parameter is misleading.

---

### B-State-02-M3 — `S.FinalizeOvercall` Sun-take case re-derives `belPending` from `result.by` — but doesn't reset `s.contract.doubled/tripled/foured/gahwa` flags

**Severity: MEDIUM (latent).**

**Repro:**

`State.lua:986-1023`:

```
function S.FinalizeOvercall()
    if not s.overcall or not s.contract then return nil end
    local result = R.ResolveOvercall(…)
    if result.taken then
        if result.type == "UPGRADE" then
            s.contract.type  = K.BID_SUN
            s.contract.trump = nil
        elseif result.type == "TAKE" then
            s.contract.type   = K.BID_SUN
            s.contract.trump  = nil
            s.contract.bidder = result.by
            local oppA = result.by == 1 or result.by == 3
            s.belPending = oppA and { 2, 4 } or { 1, 3 }
        elseif result.type == "TAKE_HOKM" then
            s.contract.type   = K.BID_HOKM
            s.contract.trump  = result.trump
            s.contract.bidder = result.by
            local oppA = result.by == 1 or result.by == 3
            s.belPending = oppA and { 2, 4 } or { 1, 3 }
        end
    end
    s.overcall = nil
    s.phase = K.PHASE_DOUBLE
    return result
end
```

Critique:
- The mutation rewrites `type/trump/bidder` but NOT `doubled/tripled/
  foured/gahwa/belOpen/tripleOpen/fourOpen`. The contract was just
  newly created at `S.ApplyContract` (right before BeginOvercall), so
  these flags are all false — no actual bug today. But if the
  overcall window were ever invoked AFTER an escalation (which would
  violate the phase machine but a bug elsewhere could enable it), the
  flags would leak through.
- `s.contract.openClosed` is mentioned in a comment (`State.lua:47`)
  but the actual stored fields are `belOpen / tripleOpen / fourOpen`
  — no `openClosed`. Minor doc/code drift.

**Fix recommendation:**

Add a defensive reset of escalation flags inside the take branches:

```
elseif result.type == "TAKE" then
    s.contract.type   = K.BID_SUN
    s.contract.trump  = nil
    s.contract.bidder = result.by
    s.contract.doubled = false
    s.contract.tripled = false
    s.contract.foured  = false
    s.contract.gahwa   = false
    s.contract.belOpen    = false
    s.contract.tripleOpen = false
    s.contract.fourOpen   = false
    …
```

Alternatively, refactor to call `S.ApplyContract(result.by, K.BID_SUN,
nil)` (which already constructs the fresh struct) and let the
idempotence check from M1 not match because `bidder` differs.

---

### B-State-02-M4 — `S.HostAdvanceBidding` parseBid does not validate trump suit (echoes B-Net-02 M4)

**Severity: MEDIUM.**

Already covered under H1 #2 above. Confirmed.

---

### B-State-02-M5 — `S.ApplyContract` does NOT clear `s.bidPosition` or `s.peekedThisRound` — but also doesn't need to

**Severity: NO ISSUE (verified clean).**

The audit-scope item 10 asks about side-effects on `bidPosition`,
`peekedThisRound`, etc. Verified:

- `s.bidPosition` does **not exist** as a state field (the variable
  by that name only appears as a LOCAL inside
  `S.HostAdvanceBidding:1751`). Nothing to clear.
- `s.peekedThisRound` is correctly reset at `S.ApplyStart:780` (round
  start), at `S.ApplyContract` it should NOT reset (the peek allowance
  spans across the contract decision — the player peeks AT bid time,
  before contract finalize). Correct.
- `s.bidCard` is NOT cleared in `S.ApplyContract`. Inspected — correct,
  the bid card persists into PHASE_PLAY for the bidder's hand
  composition (`S.HostDealRest:1626-1627`). Cleared at `S.ApplyStart:759`.
- `s.bids` is NOT cleared in `S.ApplyContract`. Correct — the bids
  table is read by `R.ScoreRound`-adjacent inspection logic and the
  trap-pass detection in `S.HostBeginRound2:1834-1846` already happens
  before `s.bids = {}` clears at line 1849. Cleared at `S.ApplyStart`
  (line 761).

**No fix needed.**

---

### B-State-02-M6 — `S.HostBeginRound2` does NOT clear `s.bidCard` — semantically OK because R2 reuses the same card

**Severity: NO ISSUE (verified clean).**

`State.lua:1825-1857`:

```
function S.HostBeginRound2()
    -- snapshot r1AllPass
    …
    s.bidRound = 2
    s.bids = {}
    s.phase = K.PHASE_DEAL2BID
    …
end
```

`s.bidCard` remains the same card flipped at deal-1; in round 2 it's
no longer the "Hokm-suit constraint" — instead, the constraint is
"trump cannot equal the flipped suit" (`State.lua:1796-1797`):

```
local flippedSuit = s.bidCard and C.Suit(s.bidCard) or nil
if not (flippedSuit and trump == flippedSuit) then
    winning = { seat = seat, type = btype, trump = trump }
end
```

Correct. The same `s.bidCard` is consulted for the R1-vs-R2 trump
restriction. Clearing it would break R2 logic.

---

### B-State-02-M7 — Triple-on-Ace pre-emption `S.ApplyPreempt` clears `s.contract` but the new contract is rebuilt by `_HostStepBid` only after _another_ bid comes in

**Severity: LOW (sequencing observation; functionally correct).**

**Repro:**

`State.lua:1900-1907`:

```
function S.ApplyPreempt(seat)
    if not s.preemptEligible then return end
    s.contract = nil
    s.preemptEligible = nil
    s.phase = K.PHASE_DEAL2BID
    if B.Sound and B.Sound.Cue then B.Sound.Cue(K.SND_VOICE_SUN) end
end
```

After preempt, `s.contract = nil` and phase rolls back to
`PHASE_DEAL2BID`. The host-side `_HostStepBid` then resumes bidding
with the preempting seat's claim as a Sun bid (per `Net.lua` flow
around lines 3826-3895). During the gap between `ApplyPreempt` and
the next `_HostStepBid → S.ApplyContract`, `s.contract` is briefly
nil — any code path that indexes `s.contract.X` during that window
will nil-error.

Spot-check: the only code that runs synchronously inside
`ApplyPreempt` is the sound cue. `B.UI.Refresh` is called by the
caller (`Net.lua:3836`). UI render gates on `s.contract` existence
(searched: `if s.contract then` is the dominant pattern), so nil
windows are tolerated.

**Mitigation:** functionally fine. **No fix recommended.**

---

### B-State-02-M8 — `S.ApplyPreemptPass` (the audit-scope `ApplyPreemptDecline`) walks `s.preemptEligible` array with mid-iteration table mutation

**Severity: LOW (correct in single-decline case; correct by accident
otherwise).**

**Repro:**

`State.lua:1909-1919`:

```
function S.ApplyPreemptPass(seat)
    if not s.preemptEligible then return end
    for i, s2 in ipairs(s.preemptEligible) do
        if s2 == seat then table.remove(s.preemptEligible, i); break end
    end
    if #s.preemptEligible == 0 then
        s.preemptEligible = nil
    end
end
```

`table.remove` inside the `ipairs` loop is correct ONLY because of
the `break` immediately after — the loop terminates before the next
iteration would see the shifted index. If the `break` were ever
removed (or moved outside the if), this would be a classic
mid-iteration mutation bug.

**Mitigation:** `break` is the correct guard. **No fix needed.** Just
flagged for future-edit safety.

---

### B-State-02-M9 — `S.ApplyDouble/Triple/Four/Gahwa` set the escalation flag BEFORE checking `s.contract` exists — wait, actually they DO check first; verify

**Severity: NO ISSUE.**

All four functions correctly start with `if not s.contract then
return end`. Confirmed at:
- `State.lua:1076` (`ApplyDouble`)
- `State.lua:1102` (`ApplyTriple`)
- `State.lua:1120` (`ApplyFour`)
- `State.lua:1141` (`ApplyGahwa`)

No nil-deref risk.

---

## LOW-severity findings / observations

### B-State-02-L1 — `S.ApplyDouble` Sun shortcut to PHASE_PLAY (audit-scope item 1) — confirmed correct per v0.10.0 R2 collapse

**Status: NO ISSUE.**

Per the v0.10.0 R2 fix referenced in `Rules.lua:794-887` (Sun has no
Triple/Four/Gahwa rungs), `S.ApplyDouble:1085-1088` correctly routes
Sun + Bel directly to `PHASE_PLAY`:

```
if s.contract.type == K.BID_SUN then
    s.phase = K.PHASE_PLAY
    return
end
```

The `belOpen` flag is set per the wire `open` arg (line 1078) but
ignored in this path — Sun has no follow-up rung, so the flag's value
is a no-op. `R.ScoreRound` defensively normalizes any stale tripled/
foured/gahwa flags on Sun (`Rules.lua:800-806`).

`R.CanBel` (`Rules.lua:523-561`) correctly enforces the Sun-Bel-100
score-split gate (caller team ≤100 AND opposite team >100). Hokm has
no gate (line 526: `return true`).

**Confirmed correct.**

---

### B-State-02-L2 — Triple-on-Ace pre-emption `S.ApplyPreempt + S.ApplyPreemptPass` (audit-scope item 7) — confirmed correct (B-Net-02 L2)

**Status: NO ISSUE.**

Pre-emption sequencing:
1. R2 Sun bid arrives with `bidCard.rank == "A"`.
2. `_HostStepBid` (`Net.lua:1535-1574`) computes
   `S.PreemptEligibleSeats(buyerSeat, bidder)` — returns earlier-bid-
   order seats excluding buyer's partner (`State.lua:1873-1898`).
3. If non-empty, host broadcasts MSG_PREEMPT_OPEN; sets
   `S.s.preemptEligible = elig` (line 1544); rolls phase to
   `PHASE_PREEMPT` via the wire frame.
4. Each eligible seat decides: claim (`S.ApplyPreempt`) or pass
   (`S.ApplyPreemptPass`).
5. If `s.preemptEligible` empties via passes (line 1916), the buyer's
   original Sun contract is finalized via `_FinalizePreempt`
   (`Net.lua:1038-1053`) → `S.ApplyContract(pc.bidder, pc.type,
   pc.trump)`.
6. If a seat claims, `S.ApplyPreempt` clears `s.contract` and `s.
   preemptEligible`; phase rolls back to `PHASE_DEAL2BID`; the host
   then re-resolves bidding via `_HostStepBid` (which re-runs
   `S.HostAdvanceBidding`).

The "all eligible passed → finalize original" path AND the "earliest
eligible claims" path are correctly distinguished. Cross-validated
against B-Net-02 L2.

**Confirmed correct.**

---

### B-State-02-L3 — R2-flip vs all-pass redeal sequencing (audit-scope item 8) — confirmed correct (B-Net-02 L5)

**Status: NO ISSUE.**

Path:
1. R1 ends with all 4 bids in (`count >= 4`); winner=nil →
   `HostAdvanceBidding` returns `"round2"` (`State.lua:1815`).
2. `_HostStepBid` "round2" branch calls `S.HostBeginRound2`
   (`State.lua:1825-1857`).
3. `HostBeginRound2` snapshots `r1AllPass` BEFORE clearing `s.bids`
   (correct ordering — line 1834-1849).
4. Re-seeds turn at `(dealer % 4) + 1` for first R2 bidder.

Path:
1. R2 ends with all 4 bids in; winner=nil → `HostAdvanceBidding`
   returns `"redeal"` (`State.lua:1816`).
2. `_HostStepBid` "redeal" branch calls `N._HostRedeal("allpass")`
   which advances dealer and starts a fresh deal.

The `Bot.r1WasAllPass` carry-forward into R2 thresholds
(`Bot.lua:1252`) reads correctly. Confirmed.

---

### B-State-02-L4 — PHASE machine transitions (audit-scope item 9) — confirmed correct

**Status: NO ISSUE.**

Verified the transition graph:

```
IDLE → LOBBY → DEAL1 → [bidding] → (DEAL2BID for R2) → [PHASE_PREEMPT for R2 Sun-Ace] →
                                                       → [contract finalized via S.ApplyContract] →
                                                       → PHASE_OVERCALL (for Hokm via BeginOvercall) →
                                                       → PHASE_DOUBLE (after FinalizeOvercall or directly via ApplyContract) →
                                                       → PHASE_TRIPLE (if Bel and belOpen) →
                                                       → PHASE_FOUR (if Triple and tripleOpen) →
                                                       → PHASE_GAHWA (if Four and fourOpen) →
                                                       → PHASE_PLAY (after escalations resolve OR Sun-Bel shortcut OR closed-Bel) →
                                                       → PHASE_SCORE → IDLE (round) or → GAME_END (match)
```

Each transition is gated correctly:
- `S.HostBeginLobby:611` — `IDLE/SCORE/GAME_END → LOBBY` (line 252-253
  passive-gate).
- `S.ApplyStart:801` — sets `PHASE_DEAL1`.
- `S.HostBeginRound2:1850` — sets `PHASE_DEAL2BID`.
- `S.ApplyContract:1055` — sets `PHASE_DOUBLE`.
- `S.BeginOvercall:957` — sets `PHASE_OVERCALL`.
- `S.FinalizeOvercall:1021` — sets `PHASE_DOUBLE`.
- `S.ApplyDouble:1086/1091/1094` — branches to PLAY or TRIPLE.
- `S.ApplyTriple:1109/1111` — branches to PLAY or FOUR.
- `S.ApplyFour:1127/1129` — branches to PLAY or GAHWA.
- `S.ApplyGahwa:1140-1147` — does NOT set phase (caller `HostFinishDeal`
  proceeds to PHASE_PLAY via `S.ApplyPlayPhase:1192-1195`).
- `S.ApplyPreempt:1905` — sets `PHASE_DEAL2BID`.

The single demotion attack surface (`_OnOvercallResolve` →
`PHASE_DOUBLE` regardless of prior phase) is documented under
B-State-02-CRIT-3 (= B-Net-06 F12).

The **DEAL3 phase** between PHASE_PLAY entry and trick play is
referenced in `S.GetMeldsForLocal:1933` but not in this audit's
escalation scope. Cross-checked: `S.HostFinishDeal` (the host-side
function that runs after Gahwa) calls `S.ApplyPlayPhase` after
dealing the final 3 cards.

**Confirmed correct.**

---

### B-State-02-L5 — Side-effects on `S.ApplyContract` (audit-scope item 10) — partial issues already covered

**Status: see CRIT-1 (s.overcall not cleared) and M5/M6 (verified
clean for bidPosition, peekedThisRound, bidCard, bids).**

`S.ApplyContract` mutations:
- `s.contract = { … }` (the new struct).
- `s.phase = K.PHASE_DOUBLE`.
- `s.turn = nil` (correct — clears the bidder's last-turn glow).
- `s.turnKind = nil`.
- `s.belPending = { … }` (defender pair derived from bidder).

Things `S.ApplyContract` does **NOT** clear, with assessment:
- `s.overcall` — **bug** (CRIT-1 / B-Net-02 M3).
- `s.preemptEligible` — should not be set at this point (`S.ApplyPreempt`
  cleared it before phase rolled to DEAL2BID); confirmed safe.
- `s.bids` — correct (cleared at `S.ApplyStart`).
- `s.bidCard` — correct (preserved for `HostDealRest`).
- `s.bidPosition` — does not exist as state.
- `s.peekedThisRound` — correct (preserved across contract).
- Per-trick state (`s.trick`, `s.tricks`) — correct (cleared at
  `S.ApplyStart`).

---

### B-State-02-L6 — `S.ApplyOvercallResolve` (audit-scope item 5) — function does not exist; the wire-handler `_OnOvercallResolve` is what was meant; covered by CRIT-3

**Status: terminology clarification.**

The audit scope mentions `S.ApplyOvercallResolve` as the unconditional
phase=PHASE_DOUBLE setter. No such state primitive exists. The
unconditional phase setter is the wire handler `N._OnOvercallResolve`
(`Net.lua:1123-1151`). The state-primitive equivalent is
`S.FinalizeOvercall` (`State.lua:986-1023`), which IS conditional
(only mutates `s.contract` if `result.taken`) but always sets
`s.phase = K.PHASE_DOUBLE` and clears `s.overcall`.

Both unconditional-phase issues are tracked under B-State-02-CRIT-3
and B-Net-06 F12 / D-RT-15 CRIT-2.

---

## Functions named in scope but not present in production code

These were listed in the audit brief but do not exist in
`State.lua`. Likely renamed or never landed:

| Audit-scope name | Actual name in code | Status |
|---|---|---|
| `S.ApplyPass` | (absent — passes go through `S.ApplyBid(seat, K.BID_PASS)`) | NOT a separate primitive |
| `S.ApplyAshkal` | (absent — Ashkal is a bid: `S.ApplyBid(seat, K.BID_ASHKAL)`) | NOT a separate primitive |
| `S.ApplyOvercallResolve` | `N._OnOvercallResolve` (wire) + `S.FinalizeOvercall` (state) | renamed/split |
| `S.HostBeginRound1` | (absent — round-1 setup is in `S.ApplyStart` + `Net.HostStartRound`) | NOT a separate primitive |
| `S.ApplyPreemptDecline` | `S.ApplyPreemptPass` | renamed |

---

## Summary table

| ID | Severity | Area | Status |
|---|---|---|---|
| **CRIT-1** | HIGH | `S.ApplyContract` doesn't clear `s.overcall` | confirmed (= B-Net-02 M3) |
| CRIT-2 | LOW (no issue) | `S.ApplyDouble` Sun→PLAY shortcut | confirmed correct |
| CRIT-3 | HIGH | `_OnOvercallResolve` empty-payload phase demotion | confirmed (= B-Net-06 F12 / D-RT-15 CRIT-2) |
| H1 | HIGH (latent) | `S.ApplyBid` no value validation; empty/malformed bids | confirmed (= B-Net-02 M1/M2/M4) |
| H2 | HIGH | `S.ApplyContract` no bidder-seat range gate | confirmed (= B-Net-02 H2) |
| H3 | HIGH (latent) | `contract.forced` read in 3 places, never set | confirmed (= B-Net-02 H1) |
| M1 | MEDIUM | `S.ApplyContract` idempotence ignores forced/escalation flags | latent |
| M2 | MEDIUM | `S.ApplyDouble/Triple/Four/Gahwa` `seat` arg unused but accepted | latent |
| M3 | MEDIUM | `S.FinalizeOvercall` take-branches don't reset escalation flags | latent |
| M4 | MEDIUM | `parseBid` doesn't validate trump suit | (see H1 #2) |
| M5 | NO ISSUE | `S.ApplyContract` side-effects: bidPosition/peeked/bidCard/bids | verified clean |
| M6 | NO ISSUE | `S.HostBeginRound2` doesn't clear `bidCard` | correct (R2 needs it) |
| M7 | LOW | `S.ApplyPreempt` clears contract; brief nil window | tolerated |
| M8 | LOW | `S.ApplyPreemptPass` mid-iteration mutation safety relies on `break` | flagged |
| M9 | NO ISSUE | Apply* nil-contract guards | correct |
| L1 | NO ISSUE | Sun→PLAY shortcut (item 1) | confirmed |
| L2 | NO ISSUE | Triple-on-Ace preempt sequencing (item 7) | confirmed |
| L3 | NO ISSUE | R2-flip vs all-pass redeal (item 8) | confirmed |
| L4 | NO ISSUE | PHASE machine transitions (item 9) | confirmed |
| L5 | NO ISSUE / CRIT-1 | `S.ApplyContract` side-effects (item 10) | partial issue |
| L6 | clarification | `S.ApplyOvercallResolve` is `_OnOvercallResolve` (wire) | renamed |

---

## Top recommendations (no code changes applied; flagged only)

1. **CRIT-1 (HIGH):** add `s.overcall = nil` to `S.ApplyContract` for
   wire-loss / replay defense.
2. **CRIT-3 (HIGH):** add phase-guard `if S.s.phase ~= K.PHASE_OVERCALL
   then return end` to `_OnOvercallResolve` (already in B-Net-06 F12).
3. **H1 (HIGH):** validate bid format at `S.ApplyBid` entry (or strictly
   enforce at wire-side `_OnBid` AND document state primitive as
   trusted-input only). Reject `""`, malformed `HOKM:<x>` payloads.
4. **H2 (HIGH):** add `if not bidder or bidder < 1 or bidder > 4 then
   return end` to `S.ApplyContract`.
5. **H3 (latent):** decide whether to wire forced contracts (Takweesh
   recovery construction) or remove the dead gates. No urgency.
6. **M1 (latent):** if H3 wires forced, fold `forced` into the
   idempotence check or rebuild the struct unconditionally.
7. **M2 (cleanup):** drop the unused `seat` parameter from
   `S.ApplyDouble/Triple/Four/Gahwa`.
8. **M3 (defense-in-depth):** in `S.FinalizeOvercall` take branches,
   reset escalation flags (or refactor to `S.ApplyContract`).

End.
