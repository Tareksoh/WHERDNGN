# B-State-01 — Deep audit of `S.ApplyPlay` (v0.10.2)

Audit target: the central play-state-mutation function `S.ApplyPlay`
(`State.lua:1197-1298`). Every replica runs this on every play —
host (after `LocalPlay`/AFK/error-recovery directly invokes it) and
non-host (after `_OnPlay` decodes the wire frame). It is the *only*
place the in-flight trick is mutated, so any logic skewed by
`s.isHost` or by call-site (host-direct vs. wire-replay) creates a
divergence between replicas.

Files audited:
- `C:\CLAUDE\WHEREDNGN\State.lua` — `S.ApplyPlay` body
  (1197-1298), v0.10.2 M3 false-AKA check (1238-1265),
  `S.ApplyTrickEnd` (1300-1336), `S.HostValidatePlay` (1660-1666),
  `S.GetLegalPlays` (1961-1969), `S.ApplyAKA` (1443-1450),
  `s.akaCalled` lifecycle (110, 524, 795, 1257, 1263, 1327, 1446),
  `s.playedCardsThisRound` rebuild on resync (343-348).
- `C:\CLAUDE\WHEREDNGN\Rules.lua` — `R.IsLegalPlay` (89-210)
  including the AKA-relief gate (115-121, 175).
- `C:\CLAUDE\WHEREDNGN\Bot.lua` — `Bot.OnPlayObserved`
  (331-540), `wasIllegal` detection (342-345).
- `C:\CLAUDE\WHEREDNGN\Net.lua` — five `S.ApplyPlay` call sites:
  - `_OnPlay` wire dispatch (1454)
  - `LocalPlay` (2051)
  - `_HostTurnTimeout` AFK auto-play (3446)
  - bot-play dispatch with bot-error-recovery (4109)
  - bot-fallback path (4150)

Cross-references (already-filed reviews that touch ApplyPlay surface):
- `B-Net-01_onPlay_full.md` F-OP-03, F-OP-04, F-OP-08, F-OP-12 — host-only false-AKA mark, wire-format gap, observer parity, akaCalled wipe asymmetry.
- `B-Rules-01_isLegalPlay_aka.md` F2 — `S.HostValidatePlay` and `S.GetLegalPlays` omit `akaCalled`.
- `D-RT-19_false_aka_detection.md` — red-team replication of the M3 false-AKA Takweesh path.
- `D-RT-18_aka_simulator_mismatch.md` S2b — `HostValidatePlay` dead helper as refactor footgun.

Severity scale: **HIGH** = correctness/exploit; **MED** = exploitable
or behavioural divergence under realistic conditions; **LOW** =
cosmetic / documentation / latent.

---

## Summary verdict

`S.ApplyPlay` is well-instrumented for the common case but exposes
**12 distinct findings** across the 11-item audit scope. The most
load-bearing concern is the **host-only/everywhere asymmetry** that
runs through items 1, 5, 9, and 11: the `.illegal` mark, the
M3 false-AKA mark, and the `s.akaCalled` clear all depend on
`s.isHost`, but `ApplyTrickEnd`'s `s.akaCalled` clear (1327) does
not — so non-host replicas can have `s.akaCalled` leak across
tricks while the host correctly wipes it via either path.

The `wasIllegal` propagation to `OnPlayObserved` works, but it is
fragile: `OnPlayObserved` reads the LAST play in `s.trick.plays`
(populated by `ApplyPlay` immediately before the observer fires)
and matches by `seat==seat AND card==card`. This is correct under
the audit's call-order invariant (every Net.lua call site runs
`ApplyPlay` then immediately `OnPlayObserved`), but it depends on
nothing else mutating the trick between the two calls.

---

## Findings

---

### F-AP-01 [MED]: Card-to-hand removal is asymmetric — host-only `s.hostHands` mutation, plus a separate local-seat `s.hand` mutation, with no symmetric path for "host plays a non-localSeat human seat"

**Where:** `State.lua:1288-1297`

```lua
if seat == s.localSeat then
    for i, c in ipairs(s.hand) do
        if c == card then table.remove(s.hand, i); break end
    end
end
if s.isHost and s.hostHands and s.hostHands[seat] then
    for i, c in ipairs(s.hostHands[seat]) do
        if c == card then table.remove(s.hostHands[seat], i); break end
    end
end
```

**Issue:** Two independent removals — `s.hand` (the local view, only
when seat == localSeat) and `s.hostHands[seat]` (the host-side
authoritative bag, only when isHost). On the host, `s.hostHands[seat]`
is the source-of-truth for `R.IsLegalPlay` validation at line 1219.
On a non-host, the only hand visible to the player is `s.hand`. So:
- Host + localSeat == host's seat: both blocks fire — host's `s.hand` AND `hostHands[hostSeat]` both lose the card.
- Host + localSeat != seat (some other human seat playing through `_OnPlay`): only the second block fires — `s.hand` (host's own hand) is unchanged, `s.hostHands[seat]` updated. Correct, since it's not the host's card.
- Non-host + localSeat == seat: only the first block fires. `s.hand` updated. Correct.
- Non-host + localSeat != seat: neither block fires. The non-host has no view into the other seat's hand, so this is also correct.

The pattern is correct, but the lack of an explicit "what the
non-host knows about other seats" path means **any future feature
that wants to model an opponent's hand on a non-host (e.g.
sideline-spectator UI, replay export)** has to bolt on its own
hand-tracking outside `ApplyPlay`. Document the invariant.

**Verdict:** Not a bug, but the invariant is undocumented at the
call site. Consider a comment block explaining "two-replica hand
model" — also closes the latent gap if a refactor adds a third
hand-storage path.

---

### F-AP-02 [LOW]: `trick.plays` append + `leadSuit` set fires AFTER illegality determination but BEFORE the host-hand mutation — order is correct but the local `s.hand` removal is wedged between observer-visible state changes

**Where:** `State.lua:1267-1297`

```lua
if #s.trick.plays == 0 then s.trick.leadSuit = C.Suit(card) end
table.insert(s.trick.plays, {
    seat = seat, card = card,
    illegal = illegal or nil,
    illegalReason = (illegal and illegalWhy) or nil,
})
-- ...
s.playedCardsThisRound[card] = true
-- ...
if seat == s.localSeat then
    for i, c in ipairs(s.hand) do
        if c == card then table.remove(s.hand, i); break end
    end
end
if s.isHost and s.hostHands and s.hostHands[seat] then
    for i, c in ipairs(s.hostHands[seat]) do
        if c == card then table.remove(s.hostHands[seat], i); break end
    end
end
```

**Issue:** Order verified correct: validation → AKA check → `leadSuit` set → trick append → played-set add → audio cue → hand removal. The audio cue at line 1286 fires BEFORE the hand removal, so any UI hook listening to `B.Sound.Cue` would observe `s.hand` still containing the card. None of the current UI code does this, but if anything in the future hangs cleanup off the audio callback (e.g. card-flying-from-hand animation), the order will surprise it.

**Verdict:** No current bug. Worth a short ordering comment.

---

### F-AP-03 [HIGH]: M3 false-AKA detection is host-only but the `s.akaCalled = nil` side-effect has different reachability from the trick-end clear

**Where:** `State.lua:1238-1265` (M3 host-only) vs `State.lua:1327` (`ApplyTrickEnd`).

```lua
-- Host-only branch:
if not illegal and s.isHost and s.akaCalled
   and s.akaCalled.seat == seat
   and #s.trick.plays == 0
   and s.contract and s.contract.type == K.BID_HOKM then
    -- ...
    if not valid then
        illegal = true
        illegalWhy = "false AKA"
        s.akaCalled = nil
    end
    -- ...
end

-- Everywhere clear (ApplyTrickEnd):
s.akaCalled = nil
```

**Repro:**
1. Bot at seat 2 calls AKA-on-spades (`MSG_AKA;2;S` → `S.ApplyAKA` on every replica → `s.akaCalled = {seat=2, suit="S"}` on every replica).
2. Bot at seat 2 leads `7S` (false claim — Ace still out).
3. Host's `S.ApplyPlay` runs the M3 check. Block fires:
   - `illegal = true`, `illegalReason = "false AKA"`, `s.akaCalled = nil` on the **host only**.
4. Host broadcasts `MSG_PLAY ...;2;7S` (no illegal flag — see B-Net-01 F-OP-04).
5. Receivers run `S.ApplyPlay` with `s.isHost = false`. The M3 block is gated on `s.isHost`, so:
   - The `.illegal` mark never lands on receivers' `s.trick.plays[i]`.
   - `s.akaCalled` is **not cleared on receivers**.
6. `ApplyTrickEnd` (line 1327) eventually clears `s.akaCalled` on every replica when the trick closes — but **for the duration of this trick** (3 more plays), receivers still see `s.akaCalled` set. This poisons:
   - `R.IsLegalPlay` AKA-relief on the receiver's local-play check (`Net.lua:2040` `LocalPlay`) — partner of seat-2 (seat 4) might be granted relief from must-trump-ruff for the rest of the trick on a *false* AKA banner. Their UI's `S.GetLegalPlays` at line 1962 would NOT grant relief (because that omits `akaCalled` per B-Rules-01 F2), but the warning gate at `Net.lua:2040` DOES pass `S.s.akaCalled` and would fail to warn about the must-trump-ruff violation. So the receiver-on-non-host-replica can play an under-trump or discard freely — and the host's `S.ApplyPlay:1219` validation will then mark *that play* illegal too, since the host's `s.akaCalled` was already nilled out.
   - Net result: a false-AKA caller on a non-host bot replica could trigger a *cascade* of `.illegal` marks on the partner's subsequent plays, since the host correctly clears `akaCalled` (no relief) while the receiver's local check still grants relief. Both teams' takweesh resolution outcomes diverge from receiver expectations.
7. The host-side authoritative trick log is correct, so Takweesh resolution WILL still classify the original false AKA + the cascaded illegal partner play as both illegal — a *Qaid double-stamp* against the AKA-caller's team. This is mathematically harsher than intended (the false-AKA Qaid penalty was supposed to be the only one).

**Confirmed by:** `D-RT-19` (false-AKA detection red-team), `B-Net-01 F-OP-12` (akaCalled wipe asymmetry).

**Fix recommendation:** Two options, complementary:
1. Fold the `s.akaCalled = nil` clear out of the host-only block so it runs everywhere when M3 detects a false call. Currently the entire M3 block is `s.isHost`-gated; lifting just the wipe out (using a deterministic check on `s.playedCardsThisRound`, which IS rebuilt on resync) would restore replica parity.
2. Plumb the `.illegal` flag through `MSG_PLAY` (B-Net-01 F-OP-04 fix) so non-host replicas can mark and Takweesh-test consistently.

---

### F-AP-04 [MED]: M3 false-AKA check uses `s.playedCardsThisRound` which is set BEFORE the AKA check on this same play — but the check still works because the lead-card test runs BEFORE the played-set add at line 1277

**Where:** `State.lua:1238-1265` and 1276-1277.

```lua
-- M3 check (line 1246):
s.playedCardsThisRound = s.playedCardsThisRound or {}
local valid = false
for _, r in ipairs(order) do
    if r == cardRank then valid = true; break end
    if not s.playedCardsThisRound[r .. cardSuit] then
        break  -- a higher rank is still out: false claim
    end
end
-- ...

-- Played set add (line 1276):
s.playedCardsThisRound = s.playedCardsThisRound or {}
s.playedCardsThisRound[card] = true
```

**Issue:** The M3 check looks for ranks higher than `cardRank` in
`s.playedCardsThisRound`. Since the line 1276 add hasn't happened
yet, the `card` itself isn't in the played set. This is correct
— we're asking "is the card I'm about to play the highest unplayed
card?", so we want to know what was played BEFORE this play.

**But:** The `s.playedCardsThisRound = s.playedCardsThisRound or {}`
defensive idiom appears at both 1246 and 1276. If the trickEnd
copy at line 1322 (`if s.playedCardsThisRound then s.playedCardsThisRound[p.card] = true end`)
is somehow nilled between the two `or {}` resets, the M3 check
would see an empty map at line 1248 — every rank looks "unplayed",
including ranks above what's actually live. The check would
correctly flag any rank below `A` as a false AKA (since `A` would
appear unplayed for non-trump), so this is *fail-safe* in the
direction of false-positive Qaid stamps.

The tighter concern is: line 1246's `or {}` *creates* the table if
it was nil, but the line 1322 trickEnd copy doesn't recreate from
`s.tricks` — it only writes to whatever `s.playedCardsThisRound`
already is. Combined with `S.ApplyResyncSnapshot` at line 343
explicitly rebuilding `s.playedCardsThisRound` from `s.tricks`, the
invariant holds across resyncs. But a future maintainer who nils
out `s.playedCardsThisRound` mid-round (e.g. a "hand-reset" debug
button) would silently flip every M3 check to false-claim verdicts.

**Fix recommendation:** Add an assertion / debug-log at line 1246
if `s.playedCardsThisRound` is empty during M3 evaluation — or
remove the defensive `or {}` here, since it can mask the bug.

---

### F-AP-05 [HIGH]: M3 false-AKA suit mismatch (line 1259-1264) does not use the boss-rank check — but more importantly, it's only host-side, AND `s.akaCalled = nil` clears asymmetrically

**Where:** `State.lua:1259-1264`

```lua
else
    -- AKA on suit X but lead is suit Y → trivially false.
    illegal = true
    illegalWhy = "false AKA"
    s.akaCalled = nil
end
```

**Issue:** This branch fires when the card's suit does not match
the announced AKA suit. Logically correct — AKA on spades but you
lead clubs is trivially false. But:
1. It's still inside the `s.isHost` guard at line 1238, so non-host replicas don't run it.
2. The `s.akaCalled = nil` clear is host-only, same as F-AP-03.
3. Unlike the rank-too-low case, this branch fires unconditionally — there's no test for whether the AKA caller MIGHT have legitimately called AKA on a different suit (they can't; AKA is one-shot per trick). So the trivially-false case is correctly stamped, but only on the host.

Additionally, the M3 block does NOT detect a *legitimately
unrelated* AKA: if seat 2 calls AKA on spades and then *seat 4*
leads clubs, the M3 block at 1238-1241 doesn't fire (because
`s.akaCalled.seat == seat` requires the LEAD seat to be the AKA
caller). This is correct — only the AKA caller's own lead is
inspected for false-AKA. But the receiver-relief side at
`Rules.lua:115-121` also requires `seat == R.Partner(akaCalled.seat)`,
so a non-partner non-caller lead correctly does not trigger
relief. No bug here, but the interaction is subtle.

**Fix recommendation:** Same as F-AP-03 — lift the `s.akaCalled = nil`
clear out of the host-only block.

---

### F-AP-06 [LOW]: One-play-per-seat-per-trick guard rejects identical seats but cannot detect "host self-heal turn patch + duplicate play"

**Where:** `State.lua:1199-1206`

```lua
for _, p in ipairs(s.trick.plays) do
    if p.seat == seat then return end
end
```

**Issue:** The guard correctly stops a second play from the same
seat. But it fires AFTER the function entry `if not s.trick then
s.trick = { leadSuit = nil, plays = {} } end`, so a malformed call
where `s.trick` was nil could still slip through... actually no,
the iteration over an empty table returns immediately, and the
host self-heal at `Net.lua:1421-1431` already gates by
`authorizeSeat`. The guard is fine, but the silent `return` here
swallows the error — no log line, no debug breadcrumb. A
maintainer chasing "why didn't my play register?" sees nothing.

**Fix recommendation:** Add a `L.Debug` line for the rejection
case. Combined with `Net.lua:1434-1438`'s outer idempotence guard
(also silent), there's no observability into duplicate play
suppression.

---

### F-AP-07 [LOW]: Host-side `R.IsLegalPlay` validation copies `s.trick.plays` into a `trickBefore` shallow array — but reuses the original play references, not deep copies

**Where:** `State.lua:1215-1218`

```lua
local trickBefore = { leadSuit = s.trick.leadSuit, plays = {} }
for _, p in ipairs(s.trick.plays) do
    trickBefore.plays[#trickBefore.plays + 1] = p
end
```

**Issue:** The shallow copy creates a new outer table but each
`p` slot holds the same play-record reference as `s.trick.plays`.
`R.IsLegalPlay` only reads `p.seat`, `p.card`, and via
`R.CurrentTrickWinner` recursive reads — none mutate. So this is
safe today. But if a future audit-trail feature mutates the play
record (e.g. annotates with timestamps post-hoc), `trickBefore`
would observe the mutations.

**Fix recommendation:** No action; document the invariant ("`R.IsLegalPlay`
must not mutate trick.plays entries").

---

### F-AP-08 [MED]: `Bot.OnPlayObserved` reads `S.s.trick.plays[#plays]` to compute `wasIllegal` — but the order is "ApplyPlay then OnPlayObserved", so the lookup hits the just-inserted play

**Where:** `Bot.lua:342-345` and `State.lua:1268-1272`.

```lua
-- ApplyPlay:
table.insert(s.trick.plays, {
    seat = seat, card = card,
    illegal = illegal or nil,
    illegalReason = (illegal and illegalWhy) or nil,
})

-- OnPlayObserved (called immediately after ApplyPlay):
local lastPlay = S.s.trick and S.s.trick.plays
                 and S.s.trick.plays[#S.s.trick.plays]
local wasIllegal = lastPlay and lastPlay.seat == seat
                   and lastPlay.card == card and lastPlay.illegal
```

**Issue:** The pattern requires that NOTHING ELSE has touched
`s.trick.plays` between `ApplyPlay`'s `table.insert` and the
observer call. All five Net.lua call sites correctly call
`ApplyPlay` then `OnPlayObserved` back-to-back without any
intervening Lua. But:
- The `lastPlay.seat == seat AND lastPlay.card == card` check
  defends against the case where `ApplyPlay`'s one-play-per-seat
  guard returned early (no insert), so the actual last play is from
  someone else. Good defensive logic.
- HOWEVER, `lastPlay.illegal` is `nil` on **non-host** replicas
  even when the host stamped it — see F-AP-03. So
  `OnPlayObserved`'s "skip void/discard inference for illegal
  plays" gate is host-only. On non-host bot replicas (rare but
  possible if `B.Bot` is loaded), the void poisoning protection is
  inert.
- Non-host replicas typically don't run bot decision code, so the
  practical impact is small. But the comment at `Bot.lua:336-341`
  (`"if the play was ILLEGAL (host marked it p.illegal=true in S.ApplyPlay)"`)
  accurately states host marks; what it doesn't say is "and only
  the host". A non-host bot would silently be poisoned.

**Confirmed by:** `B-Net-01 F-OP-08` (`B.Bot.OnPlayObserved` runs
on every replica that has Bot loaded).

**Fix recommendation:** Either restrict `Bot.OnPlayObserved` to
host (`if not S.s.isHost then return end` at function entry — the
current bot-on-non-host case is latent), or plumb `.illegal` through
`MSG_PLAY` (B-Net-01 F-OP-04). The first is cheaper and matches
the actual invariant.

---

### F-AP-09 [LOW]: `s.playedCardsThisRound` write at line 1276-1277 is symmetric, but `s.tricks` (closed tricks) and `s.trick.plays` (in-flight) are not unified — `ApplyTrickEnd:1322` re-adds played cards even though `ApplyPlay` already added them

**Where:** `State.lua:1276-1277` (ApplyPlay) and `State.lua:1322` (ApplyTrickEnd).

```lua
-- ApplyPlay (per-play):
s.playedCardsThisRound = s.playedCardsThisRound or {}
s.playedCardsThisRound[card] = true

-- ApplyTrickEnd (per-trick close):
for _, p in ipairs(s.trick.plays) do
    s.lastTrick.plays[#s.lastTrick.plays + 1] = { seat = p.seat, card = p.card }
    if s.playedCardsThisRound then s.playedCardsThisRound[p.card] = true end
end
```

**Issue:** `ApplyTrickEnd:1322` sets `s.playedCardsThisRound[p.card] = true`
for cards that were already added by `ApplyPlay:1277`. The duplicate
write is idempotent (set semantics). The rationale is presumably
defensive — if a future bug nilled `s.playedCardsThisRound`
mid-trick, the trick-close would restore it. But the M3 false-AKA
check at line 1246 would have already operated on the empty map,
producing wrong verdicts mid-trick.

**Fix recommendation:** Either remove the duplicate write (relying on
`ApplyPlay`'s addition) or document the redundancy as a defensive
backstop. The duplicate is cheap; the inconsistency it papers over
is more important to surface.

---

### F-AP-10 [LOW]: 4-play trick boundary detection is implicit — `ApplyPlay` does not check `#s.trick.plays == 4` and trigger `ApplyTrickEnd`; that's `_HostStepPlay`'s job (Net.lua:1623-1647) on a 2.2s timer

**Where:** `Net.lua:1614-1647`

```lua
function N._HostStepPlay()
    if not S.s.trick then return end
    if #S.s.trick.plays < 4 then
        local last = S.s.trick.plays[#S.s.trick.plays].seat
        local nxt = (last % 4) + 1
        S.ApplyTurn(nxt, "play")
        N.SendTurn(nxt, "play")
        N.MaybeRunBot()
        return
    end
    -- 2.2s wait before resolving
    C_Timer.After(2.2, function()
        -- ...
        S.ApplyTrickEnd(winner, points)
        N._HostStepAfterTrick()
    end)
end
```

**Issue:** `ApplyPlay` itself does not transition out of the trick.
It just appends and returns. The trick-end is host-driven via
`_HostStepPlay`, with a 2.2s wait window for visual hold. During
the wait:
- A Takweesh call (`_OnTakweesh`) can move phase to `K.PHASE_SCORE`,
  in which case the C_Timer.After body's `if S.s.phase ~= K.PHASE_PLAY then return end`
  guard at line 1637 prevents the trick-end. Good.
- A pause (`s.paused = true`) blocks at line 1634. Good.
- A host disconnect mid-window leaves the 4-play trick in
  `s.trick.plays` permanently (until rejoiner). Resync replays the
  in-flight plays via MSG_PLAY (Net.lua:453-458), which would
  rebuild `s.trick.plays` to 4 entries on the rejoiner; the
  rejoiner doesn't run `_HostStepPlay`, so the trick-end fires only
  when a NEW host completes the wait. **This is host-driven only**.

The implicit dependence on `_HostStepPlay`'s 2.2s timer means:
- On a non-host replica, the 4-play trick is observable via
  `s.trick.plays`, but `s.akaCalled` (per F-AP-03) only clears
  when `ApplyTrickEnd` runs. Non-hosts run `ApplyTrickEnd` only
  when `_OnTrick` fires (line 1499). If `MSG_TRICK` is dropped or
  delayed, non-hosts retain `s.akaCalled` past the trick boundary.
- Belt-and-braces: non-host `_OnTrick` rebuilds `s.trick` from the
  encoded plays at line 1482-1497, then calls `ApplyTrickEnd`. So
  unless MSG_TRICK is dropped, non-hosts converge.

**Fix recommendation:** Document the host-driven trick-boundary
invariant. Consider an `_OnPlay` self-check: when `#s.trick.plays
== 4` after the call, and the replica is non-host, log a debug
breadcrumb if MSG_TRICK doesn't arrive within ~3s. This at least
gives observability for drop scenarios.

---

### F-AP-11 [LOW]: `ApplyTrickEnd:1306` rejects partial tricks — but `ApplyPlay` itself does not, so a malformed broadcast with a 5th seat play would silently extend `s.trick.plays` to 5 and `_HostStepPlay`'s `< 4` check at line 1616 would fall through to `>= 4` and resolve

**Where:** `State.lua:1199-1206` (per-seat guard) and `Net.lua:1614-1623`.

```lua
-- ApplyPlay:
for _, p in ipairs(s.trick.plays) do
    if p.seat == seat then return end
end

-- _HostStepPlay:
if #S.s.trick.plays < 4 then
    -- next-turn dispatch
    return
end
-- otherwise resolve
```

**Issue:** The per-seat guard prevents seat 1 from playing twice,
but a malformed call with 4 distinct seats already in trick.plays
plus a 5th seat (e.g. seat = 5 from a corrupted host frame) would:
1. The per-seat guard finds no `p.seat == 5` match, allows the call.
2. `R.IsLegalPlay` would presumably fail or behave unpredictably with seat=5.
3. `s.trick.plays` grows to length 5.
4. `_HostStepPlay` enters the resolve branch (`>= 4`).
5. `ApplyTrickEnd` itself has the `#s.trick.plays ~= 4` check at line 1306, but it would now fire on the 5-entry array and **drop the trick silently** (`L.Debug` only).

**Confirmed by:** `B-Net-01 F-OP-05` (seat==0 fall-through).

**Fix recommendation:** Add a `seat ∈ {1,2,3,4}` range check at
`S.ApplyPlay:1198`. Cheap, defensive, closes the malformed-host
frame case symmetrically with the Net.lua-side check.

---

### F-AP-12 [MED]: Network-replay vs host-direct distinction is invisible to `S.ApplyPlay` — same code runs in both call contexts, but the host-only branches (line 1214, 1238) only fire in host-direct calls

**Where:** `State.lua:1214` (illegal-mark gate) and `State.lua:1238` (M3 gate).

**Issue:** `S.ApplyPlay` does NOT receive an `isReplay` parameter.
On the host, `_OnPlay` will not even reach `ApplyPlay` for replay
frames (`Net.lua:1390` early return), so the host's `ApplyPlay`
runs only in host-authoritative contexts. On non-host replicas:
- Regular MSG_PLAY frames: `s.isHost == false`, so the line 1214
  illegal mark and the line 1238 M3 check both no-op.
- Replay frames: same — `s.isHost == false`, same behavior. The
  replay is not distinguishable to `ApplyPlay`.
- A future host migration (D-RT-29) that promotes a non-host to
  host mid-round: `s.isHost` flips to true, and now the (new)
  host's `ApplyPlay` would start marking illegality. But the
  `s.hostHands` table on the new host might be stale or empty
  (resync didn't deliver hostHands), so the line 1214 gate
  `s.hostHands[seat]` is nil → mark skipped. Silently. The new
  host would then mis-resolve any subsequent Takweesh.

**Confirmed by:** Currently no host-migration mechanism in v0.10.2,
so this is latent. But the lack of distinction inside `ApplyPlay`
means future host-migration adds correctness debt.

**Fix recommendation:** Consider adding an explicit `replayPath`
opt-in flag to `S.ApplyPlay(seat, card, isReplay)`. When `isReplay
== true`, skip the line 1238 M3 check entirely (the result is
already in the trick log being replayed). When `isReplay == false
and s.isHost`, run the full host-side logic. This decouples replay
behavior from `s.isHost` and removes a class of host-migration
correctness bugs. Currently latent — defer until host migration
ships.

---

## Audit-scope coverage summary

| # | Item | Status |
|---|---|---|
| 1 | Card-to-hand removal (host-only `s.hostHands`) | F-AP-01 (LOW), F-AP-02 (LOW) |
| 2 | trick.plays append + leadSuit set on first play | F-AP-02, F-AP-11 |
| 3 | M3 false-AKA host-only gate (1238-1265) | F-AP-03 (HIGH), F-AP-04 (MED), F-AP-05 (HIGH) |
| 4 | `.illegal` flag mark on play struct + reason string | F-AP-03, F-AP-08 |
| 5 | `s.akaCalled` clear on host (1257-1263) | F-AP-03, F-AP-05 |
| 6 | `Bot.OnPlayObserved` callback timing post-mutation | F-AP-08 (MED) |
| 7 | `mem.played` + `s.playedCardsThisRound` writes (symmetric) | F-AP-04 (MED), F-AP-09 (LOW) |
| 8 | trickEnd detection (4th play triggers `ApplyTrickEnd`) | F-AP-10 (LOW), F-AP-11 (LOW) |
| 9 | `ApplyTrickEnd`'s `s.akaCalled` clear (1327) | F-AP-03 — runs on every replica regardless of `s.isHost`, asymmetric with `ApplyPlay`'s host-only clear |
| 10 | `wasIllegal` propagation to `OnPlayObserved` | F-AP-08 (MED) — works on host, fails on non-host bot |
| 11 | Network-replay vs host-direct call distinction | F-AP-12 (MED) — `ApplyPlay` unaware of replay context |

---

## Cross-references and de-duplication

The following findings overlap with already-filed reviews:
- F-AP-03 ≡ B-Net-01 F-OP-03 + F-OP-12 (M3 host-only mark + akaCalled wipe asymmetry).
- F-AP-08 partially overlaps B-Net-01 F-OP-08 (observer parity on non-host bot).
- F-AP-12 dependent on B-Net-01 F-OP-04 (wire format for `.illegal`).

This audit's unique contributions:
- F-AP-01, F-AP-02 — hand-removal/append ordering invariants.
- F-AP-04 — defensive `or {}` masks `s.playedCardsThisRound` nil cases inside M3.
- F-AP-05 — trivially-false-suit branch of M3 has the same host-only asymmetry as the rank-too-low branch.
- F-AP-06 — silent rejection of duplicate-seat plays has no observability.
- F-AP-07 — `trickBefore` shallow-copy invariant.
- F-AP-09 — `ApplyTrickEnd:1322` redundant `playedCardsThisRound` write masks bugs.
- F-AP-10 — host-driven 4-play boundary timing.
- F-AP-11 — out-of-range seat falls through to ApplyPlay.
- F-AP-12 — replay-vs-direct context unknown to ApplyPlay; latent host-migration debt.
