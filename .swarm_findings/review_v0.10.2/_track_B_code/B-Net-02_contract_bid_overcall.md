# B-Net-02 — Deep audit of `_OnContract` + bid-resolution + overcall pipeline

Scope: Net.lua handlers `_OnContract`, `_OnBid`, `_OnPass` (= `_OnBid` with
`bid==K.BID_PASS`), `_OnAshkal` (= `_OnBid` with `bid==K.BID_ASHKAL`),
`_OnPreempt`, `_OnOvercallResolve`, host orchestration `HostAdvanceBidding`,
`_HostStepBid`, `HostFinishDeal`, plus state-layer applies and
`R.CanOvercall`/`R.ResolveOvercall`. Bot-side picks reviewed for tier
gating and contract-construction edge cases.

**No code modified.** Each finding cites `file:line` from
`C:\CLAUDE\WHEREDNGN`.

---

## Critical findings (BLOCKER class)

### B-Net-02-CRIT-1 — `K.MSG_RESYNC_REQ` and `K.MSG_OVERCALL_RESOLVE` both `"?"` — `_OnResyncReq` is unreachable

**Severity: BLOCKER (confirmed; matches D-RT-15 CRIT-1).**

**Repro:**

`Constants.lua:181, 229`:
```
K.MSG_RESYNC_REQ        = "?" -- request state from host
…
K.MSG_OVERCALL_RESOLVE  = "?"  -- host announces the overcall window
```

`Net.lua:543-547, 620-621`:
```
elseif tag == K.MSG_OVERCALL_RESOLVE then
    N._OnOvercallResolve(sender, fields[2], tonumber(fields[3]),
                         fields[4])
…
elseif tag == K.MSG_RESYNC_REQ then
    N._OnResyncReq(sender, fields[2])
```

`split` (`Net.lua:471-483`) tokenises only on `;`. `tag = fields[1]`
(`Net.lua:489-490`). Both tags are the literal `"?"`. The dispatcher
elseif-ladder hits `MSG_OVERCALL_RESOLVE` first (line 543), so every
`"?"` frame routes to `_OnOvercallResolve` and the `MSG_RESYNC_REQ`
branch (line 620) is dead.

**Effect:** the host can never respond to a rejoiner's
`MSG_RESYNC_REQ`. The frame `?;<gameID>` arrives at the host's
dispatcher, gets routed to `_OnOvercallResolve(sender, gameID, nil, nil)`,
which immediately bails on the `if S.s.isHost then return end` gate at
`Net.lua:1126`. `_OnResyncReq` (`Net.lua:3109`) is never invoked.

**Compounding effects:**
1. The rejoiner's 30-second `expectingResyncRes` window (`Net.lua:313,
   322-327`) expires with no response from the host.
2. The v0.9.1 L5 guard (`Net.lua:3191`: `if not expectingResyncRes
   then return end`) then permanently rejects any late host response.
3. Mid-hand `/reload` rejoin is therefore broken globally.

**Quote of the dispatch ambiguity** (`Net.lua:486-491`):
```
function N.HandleMessage(prefix, message, channel, sender)
    if prefix ~= K.PREFIX then return end
    if not message or #message == 0 then return end
    local fields = split(message, ";")
    local tag = fields[1]
```
No length-disambiguator, no payload-shape check before tag dispatch.

**Fix recommendation:**

Rename one of the two tags. `MSG_OVERCALL_RESOLVE` was added later
(v0.7), so renaming it is the lower-blast-radius option. Suggested:
`K.MSG_OVERCALL_RESOLVE = "?+"` or `"$"` (any 1-2 char string not
already in `K.MSG_*`). Confirm no collision with the existing
single-char tags `<`, `>`, `?`, `=`, `+`, `*`, `@`, `%`, `Q`, `Z`, `O`,
`I`, `e`, `t`, `p`, `a`, `k`, `z`, `n`, `u`, `v`, `w` defined in
`Constants.lua:175-235`.

After rename, no handler logic changes are required — the existing
`_OnOvercallResolve` and `_OnResyncReq` bodies are correct.

---

### B-Net-02-CRIT-2 — `_OnOvercallResolve` silently demotes phase even with empty payload

**Severity: HIGH (confirmed; matches D-RT-15 CRIT-2).**

**Repro:**

`Net.lua:1123-1151`:
```
function N._OnOvercallResolve(sender, takenStr, by, otype)
    if fromSelf(sender) then return end
    if not fromHost(sender) then return end
    if S.s.isHost then return end
    -- v0.8.6 H1 fix: trust the wire …
    S.s.overcall = nil
    S.s.phase = K.PHASE_DOUBLE
    if B.UI and B.UI.Refresh then B.UI.Refresh() end
end
```

There is **no payload validation**. An invocation with all of
`takenStr/by/otype = nil` proceeds straight to the unconditional
phase rewrite. The v0.8.6 H1 audit-fix comment explicitly notes the
wire payload is "informational only — kept in the function signature
for forward-compat / debug logging — but not consulted for state
mutation" (`Net.lua:1144-1147`). That intent is correct for the
"trust MSG_CONTRACT" architecture, but it leaves the phase rewrite
unconditional.

**Effect (combined with CRIT-1):** every `MSG_RESYNC_REQ` from a
peer routes through `_OnOvercallResolve`. The handler bails on
`fromHost` for non-host senders — but **if the requester's name has
been promoted to `s.hostName` via the lobby-takeover path
(`Net.lua:740-757`, X9-3 `lastGameID` branch), the gate passes** and
the receiver's phase is force-rewritten to `PHASE_DOUBLE` mid-trick.

**Standalone effect:** a name-spoofed host (or a peer who legitimately
holds `hostName` after a host-handover) sending a single bare `"?"`
frame demotes every other client into `PHASE_DOUBLE`, regardless of
their actual phase (PLAY, OVERCALL, PREEMPT, …). `s.contract` may
still be valid but `s.overcall` is wiped, the Bel/Triple/Four flow
re-arms, and the trick state desyncs.

**Fix recommendation:**

Two layers of defense:
1. **Tag rename** per CRIT-1 — eliminates the resync-req false-fire
   completely.
2. **Payload validation** at handler entry:
   ```
   if not takenStr or (takenStr ~= "0" and takenStr ~= "1") then return end
   ```
   This rejects bare `"?"` (no payload) and any `takenStr` that isn't
   the documented `0`/`1` flag (`Constants.lua:230-234`).

Defense-in-depth: also gate on phase — the host only sends
`MSG_OVERCALL_RESOLVE` from `PHASE_OVERCALL`, so the receiver should
require `S.s.phase == K.PHASE_OVERCALL` at entry (mirroring the gate
at `_OnOvercallDecision`, `Net.lua:1092`):
```
if S.s.phase ~= K.PHASE_OVERCALL then return end
```

---

## High-severity findings

### B-Net-02-H1 — Forced/Takweesh-recovery contract path: `forced` flag is read in 3 places but never set anywhere in production code

**Severity: HIGH (latent — currently masked by absent feature, but the
guard logic is misleading).**

**Repro:**

The `contract.forced` flag is checked at:
- `Net.lua:1161` (`_HostBeginOvercallWindow`): `if S.s.contract.forced
  then return false end` — gates overcall window off for forced contracts.
- `State.lua:948` (`S.BeginOvercall`): same gate inside the state primitive.
- `Rules.lua:576` (`R.CanOvercall`): per-seat eligibility rejects forced
  contracts.

Audit search across the entire codebase:
```
grep -r 'forced *= *true' WHEREDNGN/  → nothing in production.
grep -r 'forced.*=' WHEREDNGN/        → only test_rules.lua:950 sets it.
```

`S.ApplyContract` (`State.lua:1040-1054`) constructs the contract
struct without a `forced` field at all. There is no caller anywhere
in `Net.lua`, `State.lua`, `Bot.lua`, or `Rules.lua` that sets
`contract.forced = true`. The Takweesh recovery path
(`HostResolveTakweesh`, `Net.lua:2127`) does NOT construct a forced
contract — it consumes the existing contract and goes straight to
score (`S.ApplyRoundEnd` at `Net.lua:2264`).

**Effect:** the three "forced contract" gates are dead branches. They
were presumably written for a future Takweesh-or-Saneen-recovery
contract construction that never landed. The code reads as if forced
contracts exist; they do not. A future contributor reading
`R.CanOvercall` will assume forced-contract semantics are wired and
may build on a false premise.

This finding extends the prior xref D-RT-03 observation. The xref
flagged "contract.bidder=nil edge per D-RT-03" — that edge can never
fire today because no code constructs a contract without a bidder
(`HostAdvanceBidding` always returns `winning.seat`, which is
always set when `winning` itself is set; see `State.lua:1813`).

**Fix recommendation:**

Either:
- **Remove the dead `forced` checks** at the three sites if there's no
  near-term plan to support forced-contract recovery — keeps the
  invariant "every contract is overcall-eligible per type/non-Ace
  rules". Document the absence in CHANGELOG.
- **Or** wire up the actual feature: the documented use case
  (Takweesh during bidding → forced contract) requires
  `S.ApplyContract` to accept a `forced` flag and set it on the
  contract table. The state-machine plumbing is already in place.

Recommend Option 2 (wire it up) only if a near-term feature request
needs it; Option 1 (remove) otherwise. **No urgency** — current
behavior is correct, the gates are simply unreachable.

---

### B-Net-02-H2 — `_OnContract` accepts out-of-range bidder seat (`bidder=9`) and stores it verbatim

**Severity: HIGH (matches D-RT-15 row).**

**Repro:**

`Net.lua:852-858`:
```
function N._OnContract(sender, bidder, btype, trump)
    if fromSelf(sender) then return end
    if not fromHost(sender) then return end
    if S.s.isHost then return end
    if not bidder or not btype then return end
    S.ApplyContract(bidder, btype, trump)
end
```

`if not bidder` rejects nil but accepts any number including `9`,
`-1`, `0`, `99`. `S.ApplyContract(9, …)` then runs:

`State.lua:1063`:
```
local oppA = bidder == 1 or bidder == 3
if oppA then s.belPending = { 2, 4 } else s.belPending = { 1, 3 } end
```

`bidder=9` evaluates `oppA=false` → defenders `{1,3}`. The bidder
seat is stored as `9`. Subsequent `(contract.bidder % 4) + 1` arithmetic
in `_OnDouble`/`_OnTriple`/`_OnFour` etc. yields `(9%4)+1 = 2`, which
silently picks seat 2 as the "Bel-eligible defender" — wrong.

**Mitigation in practice:** the `fromHost` gate blocks non-host frames,
so a name-spoofed host is the only realistic attacker. Nevertheless,
the defense-in-depth pattern that `_OnAKA`, `_OnSWA`, `_OnSWAReq`,
`_OnTrick` already follow (explicit `seat >= 1 and seat <= 4` check)
is missing here.

**Fix recommendation:**

Add an explicit range gate at handler entry:
```
if not bidder or bidder < 1 or bidder > 4 then return end
```

Same pattern recommended for `_OnTurn` (`Net.lua:828`), `_OnMeld`
(`Net.lua:1354`), `_OnPlay` (`Net.lua:1375`), `_OnSWAResp`
(`Net.lua:2735` responder seat) — see D-RT-15 §"Bidder-seat injection
summary" for the full uniform gate recommendation.

---

## Medium-severity findings

### B-Net-02-M1 — `_OnBid` accepts `bid=""` and stores it verbatim

**Severity: MEDIUM.**

**Repro:**

`Net.lua:836-850`:
```
function N._OnBid(sender, seat, bid)
    if fromSelf(sender) then return end
    if not seat or not bid then return end
    if S.s.phase ~= K.PHASE_DEAL1 and S.s.phase ~= K.PHASE_DEAL2BID then return end
    if S.s.turn ~= seat or S.s.turnKind ~= "bid" then return end
    if S.s.bids and S.s.bids[seat] ~= nil then return end
    if not authorizeSeat(seat, sender) then return end
    S.ApplyBid(seat, bid)
    N.CancelTurnTimer()
    if S.s.isHost then N._HostStepBid() end
end
```

`not bid` is **false** for `""` (empty string is truthy in Lua). A
`MSG_BID;<seat>;` (no payload) frame passes the gate.
`S.ApplyBid(seat, "")` (`State.lua:889-928`) writes
`s.bids[seat] = ""`. Subsequent dispatch:

- `S.HostAdvanceBidding` (`State.lua:1700-1701`) reads `s.bids[seat]`
  → `parseBid("")` returns `nil` (no match) → falls through to "next
  bidder" without recording the seat as having bid (because
  `parseBid` returns nil and the `if btype` branch doesn't enter).
  But `s.bids[seat]` is non-nil, so the `if not s.bids[seat]` check
  at line 1821 finds it and skips that seat.
- Net effect: a seat that wires `bid=""` is treated as having "bid
  nothing" but is still counted in `count` (line 1702) — could trip
  the `count >= 4` early-resolution and force a redeal.

Additionally, `S.ApplyBid` runs the voice cue dispatch
(`State.lua:903-927`); for `bid=""` none of the `bid:sub(...) ==
K.BID_HOKM` etc. match, so no cue fires. Cosmetic only there.

**Effect:** with 3 valid bids + 1 wired empty bid, the round resolves
incorrectly (fewer than 4 valid bids but `count==4`).

**Fix recommendation:**

Add an explicit non-empty + format gate at handler entry:
```
if not seat or not bid or bid == "" then return end
local validBid = (bid == K.BID_PASS) or (bid == K.BID_SUN)
              or (bid == K.BID_ASHKAL)
              or (bid:sub(1, #K.BID_HOKM) == K.BID_HOKM
                  and #bid == #K.BID_HOKM + 2
                  and bid:sub(#K.BID_HOKM + 1, #K.BID_HOKM + 1) == ":"
                  and ({S=1,H=1,D=1,C=1})[bid:sub(-1)])
if not validBid then return end
```

This rejects empty bids, malformed Hokm bids (e.g. `HOKM:Z`,
`HOKM:`, `HOKM:Spades`), and any other unexpected payload.

---

### B-Net-02-M2 — Illegal Ashkal from seats 1/2 plays voice cue but is silently dropped at contract resolution

**Severity: MEDIUM (cosmetic + audio).**

**Repro:**

`State.lua:921-924`:
```
elseif bid == K.BID_ASHKAL then  snd = K.SND_VOICE_ASHKAL
elseif bid:sub(1, #K.BID_HOKM) == K.BID_HOKM then
    snd = K.SND_VOICE_HOKM
end
```

`S.ApplyBid` plays `SND_VOICE_ASHKAL` for any seat that bids ASHKAL,
including seats 1 and 2 in turn order who are NOT eligible per
`HostAdvanceBidding` (lines 1751-1757):

```
local bidPosition = 0
for i, ord in ipairs(order) do
    if ord == seat then bidPosition = i; break end
end
if bidPosition < 3 then
    -- Silently drop — 1st and 2nd bidders can't legally call Ashkal.
```

So an Ashkal from a seat-1 player or bot **plays the audio cue on
every client**, the bid is recorded in `s.bids[seat]`, but the
contract-resolution code drops it. The next bidder is dispatched
normally; `s.bids[1] = "ASHKAL"` lingers through the rest of the
round.

**Compounding factor:** `Bot.PickBid` correctly gates Ashkal at
`bidPos >= 3` (`Bot.lua:1306`), so bots will not generate this. But
a human player at seat 1 can click the Ashkal button (UI permitting)
and it lands on the wire.

**Fix recommendation:**

Either:
- Add a wire-side gate in `_OnBid` that rejects illegal Ashkal:
  ```
  if bid == K.BID_ASHKAL then
      local d = S.s.dealer or 1
      local order = { (d%4)+1, ((d+1)%4)+1, ((d+2)%4)+1, d }
      local bp = 0
      for i, st in ipairs(order) do if st == seat then bp = i; break end end
      if bp < 3 then return end
      if S.s.bidRound ~= 1 then return end  -- Ashkal is round-1 only
  end
  ```
- Or move the eligibility check INTO `S.ApplyBid` so the audio-cue
  fires only on accepted bids.

The UI side should ALSO hide the Ashkal button on seats 1/2 to
prevent the click in the first place — but the wire defense remains
necessary for hostile clients.

---

### B-Net-02-M3 — `_OnContract` arrives during PHASE_OVERCALL, leaves stale `s.overcall` on receiver if MSG_OVERCALL_RESOLVE was lost

**Severity: MEDIUM.**

**Repro:**

`S.ApplyContract` (`State.lua:1025-1070`) sets `s.phase = K.PHASE_DOUBLE`
unconditionally but does **not** clear `s.overcall`. The host's
post-overcall flow always sends `MSG_OVERCALL_RESOLVE` first, then
`MSG_CONTRACT` (`Net.lua:1246, 1252`).

If `MSG_OVERCALL_RESOLVE` is dropped on the wire (CHAT_MSG_ADDON
PARTY-channel is at-most-once under server contention) but
`MSG_CONTRACT` arrives:
- `_OnContract` calls `S.ApplyContract` → phase rolls from
  `PHASE_OVERCALL` to `PHASE_DOUBLE`.
- `s.overcall` (the table set by `S.BeginOvercall`, `State.lua:951-956`)
  is NOT cleared.

Other code paths that read `s.overcall`:
- UI: any rendering that checks `s.overcall ~= nil` may continue to
  display the overcall window's seat-decision strip.
- `N._OnOvercallDecision` (`Net.lua:1092`): only fires if
  `S.s.phase == K.PHASE_OVERCALL`, so a late decision frame is
  dropped — but if a stale frame DOES arrive while phase happened
  to roll back (say, on a resync replay), the stale `s.overcall`
  table accepts the decision write.

**Fix recommendation:**

Clear `s.overcall` defensively in `S.ApplyContract`:
```
s.contract = { … }
s.phase = K.PHASE_DOUBLE
s.turn = nil
s.turnKind = nil
s.overcall = nil  -- defensive: contract-finalize implies overcall closed
```

Belt-and-braces: the canonical path always clears via
`_OnOvercallResolve` first, so this is just covering wire-loss cases.

---

### B-Net-02-M4 — `parseBid` does not validate trump suit; `HOKM:Z` is accepted as Hokm with `trump="Z"`

**Severity: MEDIUM.**

**Repro:**

`State.lua:1671-1679` (inside `S.HostAdvanceBidding`):
```
local function parseBid(b)
    if b == K.BID_PASS then return K.BID_PASS, nil end
    if b == K.BID_SUN then return K.BID_SUN, nil end
    if b == K.BID_ASHKAL then return K.BID_ASHKAL, nil end
    if b and b:sub(1, 4) == K.BID_HOKM then
        return K.BID_HOKM, b:sub(6, 6)
    end
    return nil
end
```

`b:sub(6, 6)` returns whatever character is at position 6, regardless
of validity. `parseBid("HOKM:Z")` returns `(K.BID_HOKM, "Z")`.
`parseBid("HOKM:")` returns `(K.BID_HOKM, "")`.

`HostAdvanceBidding` then treats this as a winning Hokm bid (line
1775-1776):
```
elseif btype == K.BID_HOKM and not winning then
    winning = { seat = seat, type = btype, trump = trump }
end
```

Contract finalizes with `trump="Z"` (or `""`). Trick play uses
`C.IsTrump(card, contract)` which checks `C.Suit(card) == contract.trump`
— no card has suit "Z", so trumping is impossible → game becomes
effectively Sun without the multiplier. Bel/Triple/Four windows still
open. Score calculation runs.

**Mitigation in practice:** `S.ApplyContract` does store the
`trumpNorm = (trump ~= "" and trump) or nil` (`State.lua:1033`), so
`HOKM:` (empty trump) collapses to `trump=nil` → contract becomes
type=HOKM with trump=nil. That's a malformed state nothing else handles.

`HOKM:Z` survives the normalization (Z is non-empty) and writes a
contract with `trump="Z"`.

**Fix recommendation:**

Add suit validation in `parseBid`:
```
if b and b:sub(1, 4) == K.BID_HOKM and #b == 6 and b:sub(5, 5) == ":" then
    local suit = b:sub(6, 6)
    if suit == "S" or suit == "H" or suit == "D" or suit == "C" then
        return K.BID_HOKM, suit
    end
end
```

And at `_OnBid` entry — see B-Net-02-M1. The two layers should be
consistent: the wire accepts only well-formed bids; the parser is
defense-in-depth.

---

## Low-severity findings / observations

### B-Net-02-L1 — Sun overcall window post-Hokm-bid (PHASE_OVERCALL 5s) is correctly gated and pause-aware

**Status: NO ISSUE FOUND.**

The 5-second window (`Net.lua:1157-1219`) is correctly:
- Gated on `S.s.contract.type == K.BID_HOKM` and `not S.s.contract.forced`
  (lines 1160-1161; the forced gate is dead per H1 but harmless).
- Pause-aware via `overcallTimerFn` (lines 1195-1212): on timer fire,
  if `S.s.paused`, re-arm a fresh window.
- Early-resolved when all 4 seats have decided (line 1184, 1109-1111).
- Properly broadcast via `MSG_OVERCALL_OPEN` then per-seat
  `MSG_OVERCALL_DECISION` then `MSG_OVERCALL_RESOLVE`.
- Bot decisions recorded synchronously at window-open time
  (`Net.lua:1173-1182`) so bots act immediately and only humans wait
  the full 5s.

`S.BeginOvercall` (`State.lua:946-959`) initializes the table
correctly. `R.CanOvercall` (`Rules.lua:573-586`) correctly:
- Allows bidder UPGRADE only on non-Ace bid card (line 579).
- Allows non-bidder TAKE for any non-bidder seat.
- Returns false for non-Hokm contracts and forced contracts.

`R.ResolveOvercall` (`Rules.lua:611-643`) correctly prioritizes
bidder UPGRADE first, then earliest-in-bid-order TAKE/TAKE_HOKM_<suit>.

The **CRIT-2 phase-demotion** is the only attack surface here, and
it's wire-side, not logic-side.

---

### B-Net-02-L2 — Triple-on-Ace pre-emption (الثالث) sequencing is correct

**Status: NO ISSUE FOUND.**

`_HostStepBid` (`Net.lua:1535-1574`) gates pre-emption on:
- `WHEREDNGNDB.preemptOnAce ~= false` (toggleable, default ON).
- `S.s.bidRound == 2` (round-2 only).
- `payload.type == K.BID_SUN` (Sun bids only).
- `bidRank == "A"` (Ace bid card only).
- `S.PreemptEligibleSeats(payload.bidder, payload.bidder)` returns
  ≥1 eligible seat.

`S.PreemptEligibleSeats` (`State.lua:1873-1898`) correctly:
- Uses dealer-relative bidding order.
- Excludes the buyer.
- Excludes the buyer's partner ("can't Triple your partner").
- Includes only seats with a recorded R2 bid (`s.bids[seat] ~= nil`).
- Walks order positions 1..4 and breaks at `seat == buyerSeat`.

The seat=0 broadcast carries the eligible-seat CSV (`Net.lua:1561`)
so remote clients can render UI.

`_OnPreempt` and `_OnPreemptPass` (`Net.lua:962-1033`) handle the
claim and pass paths correctly. The "all eligible passed → finalize
original" path (`_FinalizePreempt`, `Net.lua:1038-1053`) correctly
restores the original buyer's contract.

The bot side (`Bot.PickPreempt`, `Bot.lua:3686-3727`) is NOT
tier-gated — every bot tier including Basic can preempt. This is
arguably intentional (the rule is structural, not strategic), but
note that the user-spec for `Bot.PickOvercall` IS tier-gated to
M3lm+ (per `CLAUDE.md` and `Bot.lua:3745`); the inconsistency isn't
a bug but worth flagging.

---

### B-Net-02-L3 — Ashkal seat eligibility (3rd/4th in turn order = dealer + dealer's-LEFT) is correct

**Status: NO ISSUE FOUND.**

`HostAdvanceBidding` (`State.lua:1751-1757`) computes `bidPosition`
from `dealer`-relative `order = [(d%4)+1, ((d+1)%4)+1, ((d+2)%4)+1, d]`.
Position 4 is the dealer; position 3 is `(d+2)%4)+1 = d-1 mod 4 + 1`,
which (per `R.NextSeat = (seat % 4) + 1` = RIGHT in this seat geometry,
per `UI.lua:223-225` and `CLAUDE.md`) is dealer's LEFT.

The check `if bidPosition < 3 then -- silently drop` correctly rejects
positions 1 and 2.

`Bot.PickBid` (`Bot.lua:1295-1306`) computes the same `bidPos` and
gates Ashkal on `bidPos >= 3`. Mirror-correct.

The v0.5.6 → v0.5.7 fix mentioned in the comment (lines 1746-1750)
corrected an earlier inversion (positions 1+4) — current code is
post-fix and correct.

---

### B-Net-02-L4 — Bidding turn order across rounds 1 and 2 is correct

**Status: NO ISSUE FOUND.**

Round 1: `HostStartRound` (`Net.lua:1820-1822`) seeds first turn at
`(dealer % 4) + 1` = seat to dealer's right (RIGHT per R.NextSeat).
After `S.HostAdvanceBidding` returns "next", `_HostStepBid`
(`Net.lua:1521-1526`) calls `S.ApplyTurn(payload.seat, "bid")` for the
next bidder. The order array `{(d%4)+1, ((d+1)%4)+1, ((d+2)%4)+1, d}`
is consistent across `HostAdvanceBidding`, `Bot.PickBid`,
`PreemptEligibleSeats`.

Round 2: `_HostStepBid` "round2" branch (`Net.lua:1602-1608`) calls
`S.HostBeginRound2` then re-seeds turn at the same `first = (dealer %
4) + 1`. Snapshot of `r1AllPass` is captured in `HostBeginRound2`
(`State.lua:1834-1846`) BEFORE clearing `s.bids` — correct.

Both rounds wait for all 4 bids (`if count >= 4 then …`,
`State.lua:1811`), which correctly handles the Sun-overcalls-Hokm
window within bidding (separate from the post-bid overcall feature).

---

### B-Net-02-L5 — Pass-all-→-redeal vs round-2-flip transition is correct

**Status: NO ISSUE FOUND.**

`HostAdvanceBidding` returns "round2" when `bidRound == 1` and no
winner (`State.lua:1815`). `_HostStepBid` "round2" branch
(`Net.lua:1602-1608`) advances to `PHASE_DEAL2BID`.

`HostAdvanceBidding` returns "redeal" when `bidRound == 2` and no
winner (`State.lua:1816`). `_HostStepBid` "redeal" branch
(`Net.lua:1609-1610`) calls `N._HostRedeal("allpass")` which advances
to next dealer and starts a fresh deal.

The "trap-pass" carry-forward (R1 all-pass detection) into Bot.PickBid
R2 thresholds (`Bot.lua:1252`) is correctly snapshot in
`HostBeginRound2` (`State.lua:1834-1846`) and consumed in
`Bot.r1WasAllPass`.

---

### B-Net-02-L6 — Bot tier dispatch — Hokm-needs-Ace gate (X4/L07 v0.10.0) is correctly tier-gated

**Status: NO ISSUE FOUND (B-Bot-01 confirms the same).**

`Bot.lua:782-806` `hokmMinShape`:
```
if not hasJ then return false end          -- B-4 absolute floor
-- v0.10.0 L07 tier-gated requirement: any Ace in hand.
if Bot.IsM3lm and Bot.IsM3lm() and not hasAnyAce then
    return false
end
if count >= 4 then return true end         -- B-2 self-sufficient
if count == 3 and hasSideAce then return true end  -- B-1 minimum
return false
```

This addresses MF-1 from `xref_X4_pro2_deal.md`:
- M3lm+ at count==4 with no Ace anywhere: now returns false (FIXED).
- M3lm+ at count==4 with trump-Ace only: `hasAnyAce=true`, gate
  bypassed, returns true.
- Basic/Advanced at count==4 with no Ace: gate skipped (`Bot.IsM3lm()`
  false), returns true (preserved permissive behavior for lower tiers).
- All tiers at count==3: still requires `hasSideAce` (B-1 minimum
  unchanged).

The `Bot.IsM3lm and Bot.IsM3lm()` guard pattern is the correct early-
load defensive form.

---

### B-Net-02-L7 — M8 mardoofa probe lead — pickLead branch position is now correctly placed BEFORE singleton/free-trick fallthroughs

**Status: NO ISSUE FOUND (B-Bot-04 confirms the same).**

`Bot.lua:1790-1823` v0.10.2 implementation of L08:
```
if Bot.IsAdvanced() and contract.type == K.BID_SUN
   and trickNum == 1
   and contract.bidder
   and myTeam == R.TeamOf(contract.bidder) then
    -- detect A+T mardoofa, return the Ace card
```

This block is positioned AT line 1790, AFTER the trick-8 sweep-pursuit
branch (1736-1788) and BEFORE the suite of opening-lead heuristics
(`free-trick` at 2298, `singleton low` at 2348, etc.). Per the comment
at lines 1797-1804, the placement supersedes the LOW-card fallthroughs
which would contradict the L08 HIGH-probe intent.

The xref D-RT-10/24 concern (mardoofa probe lead missing) is
addressed.

---

### B-Net-02-L8 — Ashkal bidder reassignment in HostAdvanceBidding correctly produces winning.seat = R.Partner(seat)

**Status: NO ISSUE FOUND.**

`State.lua:1767-1772`:
```
winning = {
    seat  = R.Partner(seat),
    type  = K.BID_SUN,
    trump = nil,
    viaAshkal = true,
}
```

`R.Partner(seat)` always returns 1..4 for any seat 1..4 (`Rules.lua:16-21`),
so `payload.bidder` reaching `_HostStepBid` is well-formed. The
`viaAshkal = true` flag enables the round-1 logic that allows a later
direct Sun to overcall Ashkal-Sun (line 1716-1718:
`local priorDirectSun = winning and winning.type == K.BID_SUN and not
winning.viaAshkal`).

---

### B-Net-02-L9 — `_OnPreemptPass` seat=0 special-case CSV parsing is robust

**Status: MILD ISSUE (matches D-RT-15 row).**

`Net.lua:1003-1018` parses the eligible-seat CSV via
`eligCsv:gmatch("(%d+)")`. This greedy-digit regex would match
multi-digit numbers (`"12"`) but the subsequent range gate `v >= 1
and v <= 4` rejects them. So `"1,12,3"` parses as `[1,12,3]` then
filters to `[1,3]`. Functionally correct but unintuitive.

**Fix recommendation:** tighten the regex to single digit:
`eligCsv:gmatch("(%d)")` — same outcome, clearer intent. Low priority.

---

## Summary table

| ID | Severity | Area | Status |
|---|---|---|---|
| **CRIT-1** | BLOCKER | Tag collision `MSG_RESYNC_REQ` ⇄ `MSG_OVERCALL_RESOLVE` | confirmed |
| **CRIT-2** | HIGH | `_OnOvercallResolve` empty-payload phase demotion | confirmed |
| H1 | HIGH (latent) | `forced` flag never set; 3 dead gates | latent |
| H2 | HIGH | `_OnContract` no bidder seat range gate | confirmed |
| M1 | MEDIUM | `_OnBid` accepts `bid=""` | confirmed |
| M2 | MEDIUM | Illegal Ashkal voice cue from seats 1/2 | confirmed |
| M3 | MEDIUM | `_OnContract` doesn't clear `s.overcall` | confirmed |
| M4 | MEDIUM | `parseBid` doesn't validate trump suit | confirmed |
| L1 | NO ISSUE | PHASE_OVERCALL window correctness | confirmed correct |
| L2 | NO ISSUE | Triple-on-Ace pre-emption sequencing | confirmed correct |
| L3 | NO ISSUE | Ashkal seat eligibility (3/4 in turn order) | confirmed correct |
| L4 | NO ISSUE | Bidding turn order R1/R2 | confirmed correct |
| L5 | NO ISSUE | All-pass redeal vs R2 flip | confirmed correct |
| L6 | NO ISSUE | M3lm Hokm-Ace gate (X4/L07) | confirmed correct |
| L7 | NO ISSUE | M8 mardoofa probe lead position | confirmed correct |
| L8 | NO ISSUE | Ashkal bidder reassignment via R.Partner | confirmed correct |
| L9 | MILD | `_OnPreemptPass` CSV regex greedy-digit | low priority |

---

## Top recommendations (no code changes applied; flagged only)

1. **CRIT-1 (BLOCKER): Rename `K.MSG_OVERCALL_RESOLVE`** away from `"?"`.
   Current collision with `K.MSG_RESYNC_REQ` makes resync-on-host
   unreachable. Suggested rename: `"?+"` or any 1-2 char string not
   in `K.MSG_*`.
2. **CRIT-2 (HIGH): Add payload validation to `_OnOvercallResolve`** —
   reject empty `takenStr` and require `S.s.phase == K.PHASE_OVERCALL`
   at handler entry.
3. **H2 (HIGH): Add `bidder >= 1 and bidder <= 4` gate to `_OnContract`**.
4. **M1 (MEDIUM): Add bid-format validation to `_OnBid`** — reject `""`,
   malformed `HOKM:<x>` payloads.
5. **M2 (MEDIUM): Wire-side reject illegal Ashkal** from seats 1/2
   (mirrors `HostAdvanceBidding` silent-drop logic; UI fix recommended too).
6. **M3 (MEDIUM): `S.ApplyContract` defensively clear `s.overcall`** to
   handle wire-loss of `MSG_OVERCALL_RESOLVE`.
7. **M4 (MEDIUM): Validate trump suit in `parseBid`** — reject
   `HOKM:Z` and similar.
8. **H1 (latent): Decide whether to wire forced contracts or remove
   the dead gates** at `R.CanOvercall:576`, `S.BeginOvercall:948`,
   `_HostBeginOvercallWindow:1161`.
9. **L9 (low): Tighten `_OnPreemptPass` CSV regex to `(%d)`** for
   clarity.

End.
