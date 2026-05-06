# B-State-07 — Deep audit of AKA-related state mutations + trick-end transition

**Scope.** Audit (read-only, no code modified) of `S.ApplyAKA`, `S.ApplyTrickEnd` (the AKA-clearing site), and every other `s.akaCalled` mutation in `State.lua`, plus the wire-side mutators (`N._OnAKA`, `N.LocalAKA`, resync replay frame at `Net.lua:461-463`) and the `R.IsLegalPlay` AKA-relief gate. Cross-references to D-RT-19, D-RT-04 surface (via D-RedTeam-01 / B-Net-05), D-RT-08, D-RT-32, B-Net-01 F-OP-12, B-Net-05 F3/F4/F12.

**Files inspected (verbatim line citations):**

- `C:\CLAUDE\WHEREDNGN\State.lua` — `S.ApplyAKA` (1443-1450), `S.ApplyTrickEnd` (1300-1336), false-AKA branches in `S.ApplyPlay` (1238-1265), TRANSIENT_FIELDS (213-217), `S.reset()` (110), `S.ApplyResyncSnapshot` (524), `S.ApplyStart` (795), `S.ApplyRoundEnd` (1463-1589), `S.ApplyRoundResult` (1591-1595), `S.HostBeginRound2` (1825-1857), `S.HostValidatePlay` (1660-1666), `S.GetLegalPlays` (1961-1969), `S.LocalAKAcandidate` (1387-1402)
- `C:\CLAUDE\WHEREDNGN\Net.lua` — `N.SendAKA` (208-210), resync replay (459-464), `N.LocalAKA` (2344-2372), `N._OnAKA` (3075-3096), bot AKA dispatch (4096-4102 area), AFK fallback (3412), Takweesh `scanIllegal` (~2150-2162)
- `C:\CLAUDE\WHEREDNGN\Rules.lua` — `R.IsLegalPlay` (89-210), AKA-relief gate (115-121, 175)
- `C:\CLAUDE\WHEREDNGN\Bot.lua` — `Bot.PickAKA` (3261-3370), `pickFollow` AKA-receiver (2484-2558), `legalPlaysFor` (1600-1614), touching-honors WRITE (475-508), `Bot.PickPlay` Saudi Master delegation (3372-3388)

---

## Reachability map: every `s.akaCalled` write site

| Line | Site | Operation | Notes |
|---|---|---|---|
| State.lua:110 | `S.reset()` | `= nil` | New game / clean slate |
| State.lua:216 | `TRANSIENT_FIELDS = { akaCalled = true, ... }` | save-suppress | Survives `/reload` only as nil |
| State.lua:524 | `S.ApplyResyncSnapshot` | `= nil` | Pre-replay clear so replay frames don't double-stamp |
| State.lua:795 | `S.ApplyStart` | `= nil` | Round-start defense-in-depth |
| State.lua:1257 | `S.ApplyPlay` M3 (rank-mismatch) | `= nil` | Host-only clear on false-AKA detect |
| State.lua:1263 | `S.ApplyPlay` M3 (suit-mismatch) | `= nil` | Host-only clear on false-AKA detect |
| State.lua:1327 | `S.ApplyTrickEnd` | `= nil` | Per-trick lifetime end (every client) |
| State.lua:1446 | `S.ApplyAKA` | `= { seat, suit }` | Unconditional overwrite |

`s.akaCalled` is a single struct (no per-trick array, no timestamp). Every write fully replaces the previous value.

---

## Findings

### F1 — `ApplyAKA` unconditionally overwrites `s.akaCalled` (multi-AKA bypass) — MEDIUM

**Severity:** MEDIUM (requires hostile/buggy peer; D-RT-19 #7 + B-Net-05 F4).

**Code (State.lua:1443-1450):**
```lua
function S.ApplyAKA(seat, suit)
    if not seat or not suit or suit == "" then return end
    -- Display state for the rest of the current trick.
    s.akaCalled = { seat = seat, suit = suit }
    -- Voice cue fires on every client. The Sound.Cue path is shared
    -- with the existing escalation cues so timing/ducking matches.
    if B.Sound and B.Sound.Cue then B.Sound.Cue(K.SND_VOICE_AKA) end
end
```

**Issue.** Line 1446 unconditionally overwrites whatever `s.akaCalled` already holds. The combination with the lack of lead-context guards in `N._OnAKA` (Net.lua:3075-3096 — no `seat == S.s.turn` / `#S.s.trick.plays == 0` check; only `LocalAKA` (Net.lua:2358-2363) has those gates) creates a clobber primitive.

**Repro (B-Net-05 F4 / D-RT-19 #7).** Hokm contract. Seat 2 about to lead, fires legitimate `MSG_AKA;2;S` via `N.LocalAKA` (passes lead-context gate, sets banner `{2,"S"}`). **Before** seat 2's `MSG_PLAY` arrives at the host's `S.ApplyPlay`, seat 4 (a hostile or buggy non-host bot at its own seat) sends `MSG_AKA;4;D` directly via the wire:
1. `N._OnAKA` (Net.lua:3075-3096): `fromSelf` → no, seat range OK, suit non-empty, phase==PLAY, contract==HOKM, `authorizeSeat(4, sender_owns_seat_4)` passes.
2. `S.ApplyAKA(4, "D")` runs. Line 1446 overwrites: `s.akaCalled = {4, "D"}`.
3. Seat 2 then leads, e.g., `K♠` while `A♠` is unplayed — a false AKA.
4. Host's M3 gate at `State.lua:1238-1241`:
   ```lua
   if not illegal and s.isHost and s.akaCalled
      and s.akaCalled.seat == seat
      and #s.trick.plays == 0
      and s.contract and s.contract.type == K.BID_HOKM then
   ```
   `s.akaCalled.seat == seat` evaluates `4 == 2` → **FALSE**. M3 short-circuits. **Seat 2's false AKA is never validated; no `.illegal` mark, no Qaid deterrent.**

**Secondary impact.** The clobbered banner `{4,"D"}` may also activate touching-honors-WRITE (Bot.lua:489-491) on partner seat 2 of seat 4 — but the receiver-relief gate at Bot.lua:2512-2514 demands `akaCalled.suit == trick.leadSuit`, mismatch-suppressed. Net effect: M3 detection is the actual victim; the false-AKA play stays in `s.tricks` without `.illegal`, so `HostResolveTakweesh.scanIllegal` (Net.lua:2150-2162) finds nothing.

**Quote** (verbatim, the offending line):
```
state.lua:1446    s.akaCalled = { seat = seat, suit = suit }
```

**Mitigation suggestion (out-of-scope per brief).** Either (a) refuse to overwrite when `s.akaCalled` is already set within the same trick (FIFO-first-call-wins), (b) add `if S.s.turn ~= seat or S.s.turnKind ~= "play" or #S.s.trick.plays > 0 then return end` to `_OnAKA` mirroring `LocalAKA`, or (c) tag `s.akaCalled` with `trickIdx = #(s.tricks or {})` so M3 can detect a clobber.

---

### F2 — `ApplyAKA` contract-type guard MISSING (defense-in-depth gap) — LOW

**Severity:** LOW. Currently only HOKM is reachable via the *outer* gates; this finding is purely defense-in-depth (D-RT-04 F6 — alias for the gap surfaced in D-RedTeam-01 / D-RT-29 / B-Net-05 F1+F8a).

**Code (State.lua:1443-1450):** as quoted above. **No `s.contract.type == K.BID_HOKM` check, no `suit ~= s.contract.trump` check.**

**Outer gates that currently shield `ApplyAKA` from non-HOKM input:**
- `Bot.PickAKA` Bot.lua:3263 — `if not S.s.contract or S.s.contract.type ~= K.BID_HOKM then return nil end`
- `N.LocalAKA` Net.lua:2347 — same predicate
- `N._OnAKA` Net.lua:3094 — same predicate (wire-side)
- `S.LocalAKAcandidate` State.lua:1388 — same (UI gate)

**Why this is a defense-in-depth gap.** `ApplyAKA` is the single funnel that all wire-receive paths AND the local sender path all converge on. A future code change that calls `ApplyAKA` from a new caller without re-applying the HOKM gate (e.g., a refactor that consolidates AKA dispatch, or a future test harness) would silently allow Sun-contract AKA banners to render. Per Saudi rule, AKA has no meaning in Sun — there's no trump to over-trump. The only catch keeping Sun AKA clean today is the four upstream sites.

**Trump-suit AKA leak (B-Net-05 F8a / D-RedTeam-01 E1).** Same pattern more dangerous: `ApplyAKA` does NOT validate `suit ~= contract.trump`. The UI helper `LocalAKAcandidate` at State.lua:1394 does (`if su ~= trump`), but the wire path (`_OnAKA`) does not. A skilled human or hostile peer wire-bypassing the UI can broadcast `MSG_AKA;<seat>;<trumpSuit>`. `_OnAKA` accepts → `ApplyAKA(seat, trumpSuit)` writes the banner unconditionally. Downstream consequences:
- M3 detector (State.lua:1245) walks plain-rank order `{"A","T","K","Q","J","9","8","7"}` — wrong for trump (TRUMP_HOKM_ORDER is `{J, 9, A, T, K, Q, 8, 7}`). False-positive validation if the AKA caller leads `J♠` on trump=Spades after A/T/K/Q are exhausted.
- M4 receiver-relief in Rules.lua:115-121 has no `akaCalled.suit ~= contract.trump` gate; will spuriously fire `akaRelief = true` for the partner of the trump-AKA-caller, exempting them from must-trump-ruff on a trump-led trick.

**Quote** (the funnel that should but doesn't gate):
```
state.lua:1443  function S.ApplyAKA(seat, suit)
state.lua:1444      if not seat or not suit or suit == "" then return end
state.lua:1445      -- Display state for the rest of the current trick.
state.lua:1446      s.akaCalled = { seat = seat, suit = suit }
```

**Mitigation suggestion.** Add `if not s.contract or s.contract.type ~= K.BID_HOKM then return end` AND `if s.contract.trump and suit == s.contract.trump then return end` at the top of `ApplyAKA`. Defense-in-depth on the funnel; closes the wire-bypass on trump-AKA categorically.

---

### F3 — `ApplyTrickEnd` clears `s.akaCalled` (line 1327) — CONFIRMED CORRECT

**Severity:** none.

**Code (State.lua:1300-1336):**
```lua
function S.ApplyTrickEnd(winner, points)
    if not s.trick or not s.trick.plays or #s.trick.plays == 0 then return end
    if #s.trick.plays ~= 4 then
        L.Debug("state", "ApplyTrickEnd ignored partial trick (%d plays)",
                #s.trick.plays)
        return
    end
    s.trick.winner = winner
    s.trick.points = points
    table.insert(s.tricks, s.trick)
    -- Stash a shallow copy ...
    s.lastTrick = { ... }
    for _, p in ipairs(s.trick.plays) do
        s.lastTrick.plays[#s.lastTrick.plays + 1] = { seat = p.seat, card = p.card }
        if s.playedCardsThisRound then s.playedCardsThisRound[p.card] = true end
    end
    s.trick = { leadSuit = nil, plays = {} }
    -- AKA banner only persists for the trick it was called on; clear it
    -- so the next trick starts visually clean.
    s.akaCalled = nil
    ...
end
```

**Verification:**
- Line 1327 fires after `s.tricks` append (line 1313) — so `.illegal` marks (M3) survive into trick history; `HostResolveTakweesh.scanIllegal` walks `S.s.tricks` (Net.lua:2156-2159) and still catches the false-AKA after trick close.
- Partial-trick guard (line 1306-1310) prevents premature `s.akaCalled` wipe on a malformed broadcast; only complete 4-play tricks trigger the clear. Good.
- Runs on **every** client (host + non-hosts) — so the banner clears symmetrically. Compare with the host-only M3 wipes at lines 1257/1263 (F4 below).

**Verdict:** Correct. `ApplyTrickEnd` is the canonical per-trick clear and runs on every replica.

**Quote** (the canonical clear):
```
state.lua:1327      s.akaCalled = nil
```

---

### F4 — Banner persistence past round-end (defense-in-depth via HostBeginRound2:795 / ApplyStart) — LOW (CORRECT BUT FRAGILE)

**Severity:** LOW. D-RT-04 F8 / D-RT-08 surface; banner DOES get cleared, but only via the next round's `ApplyStart` defense. There is no explicit clear in `ApplyRoundEnd` or in the SWA / Takweesh resolution paths.

**Code traces.**

`S.ApplyRoundEnd` (State.lua:1463-1589) — read in full. **Does NOT clear `s.akaCalled`.** Sets phase to `PHASE_SCORE`, mutates cumulative, fires audio cues. Relies entirely on the next `S.ApplyStart` (or `S.reset()`) to wipe.

`S.ApplyRoundResult` (State.lua:1591-1595) — sets `s.lastRoundResult` only. No AKA clear.

`S.HostBeginRound2` (State.lua:1825-1857) — round-2 *bidding* re-init (NOT round-end / round-start). Does NOT clear `s.akaCalled`. Note: the prompt referenced "HostBeginRound2:795" but line 795 is actually in `S.ApplyStart` (where `s.akaCalled = nil` IS explicit). `HostBeginRound2` itself spans 1825-1857 and does no AKA clearing — this is correct because round-2 bidding follows redeal; the prior round's `ApplyStart` already cleared `s.akaCalled`.

**Verified clear path post-round-end:**
- Round ends → `ApplyRoundEnd` (no clear). `s.akaCalled` may still be set (e.g., trick 7 AKA followed by SWA-resolution that ends the round before trick 8).
- Phase becomes `PHASE_SCORE`. **No bot/UI consults `s.akaCalled` in `PHASE_SCORE`** (`pickFollow`, `legalPlaysFor`, `_OnAKA`, `LocalAKA` all gate on `PHASE_PLAY`). So the persistence is cosmetic-only.
- Next round → `S.ApplyStart` (line 752-823) → line 795 explicitly: `s.akaCalled = nil`. Cleaned.

**The persistence window** is `PHASE_SCORE → next ApplyStart`. During this window:
- No play decisions fire (`pickFollow` etc. gate on `PHASE_PLAY`).
- `Bot.PickAKA` itself gates on `#S.s.trick.plays > 0` and Hokm contract type — no new AKA fires.
- UI may render the stale banner if the SCORE phase shows the previous trick's display state, but the banner-render site (UI.lua:3239) consults `S.s.akaCalled` directly and would show stale info briefly.

**SWA mid-trick edge case (D-RT-04 F8 / D-RedTeam-01 E1-related).** If SWA resolution / Takweesh fires mid-trick on a trick where `s.akaCalled` is set:
1. Host invokes the relevant `Send*` flow → broadcasts `MSG_ROUND` → all clients call `S.ApplyRoundEnd` (no AKA wipe).
2. Trick was never completed; `ApplyTrickEnd` did not run; `s.akaCalled` is still `{seat, suit}`.
3. Phase transitions to `PHASE_SCORE`. No PHASE_PLAY decision runs. Cosmetic-only.
4. Next round → `S.ApplyStart` line 795 → cleared.

**Verdict.** Correct outcome via defense-in-depth, BUT relies on `ApplyStart` running. If a developer path were ever to skip `ApplyStart` (e.g., a hypothetical "abandon game post-SCORE" code path that goes straight to `S.reset()`), `s.reset()` line 110 also clears, so we're double-defended. **No exploitable path identified**, but the absence of an explicit clear in `ApplyRoundEnd` is a documentation/clarity gap.

**Mitigation suggestion (out of scope).** Add `s.akaCalled = nil` to `ApplyRoundEnd` for belt-and-suspenders clarity. Same comment pattern as `ApplyResyncSnapshot:524` ("clear remaining transient round state so stale per-trick banners ... don't leak").

**Quote** (`ApplyRoundEnd` opening — note absence of AKA wipe):
```
state.lua:1463  function S.ApplyRoundEnd(addA, addB, totA, totB, sweep, bidderMade)
state.lua:1464      s.cumulative.A = totA
state.lua:1465      s.cumulative.B = totB
state.lua:1466      s.phase = K.PHASE_SCORE
state.lua:1467      s.lastRoundDelta = { A = addA, B = addB }
state.lua:1468      -- Reset peek allowance for the next hand
state.lua:1469      s.peekedThisRound = false
state.lua:1470      -- Round is over; nobody is "up". Clears stale UI glow on whichever
state.lua:1471      -- seat won the last trick.
state.lua:1472      s.turn = nil
state.lua:1473      s.turnKind = nil
```

---

### F5 — Mid-trick `/reload` restoration of `akaCalled` (TRANSIENT_FIELDS) — CONFIRMED CORRECT

**Severity:** none.

**Code (State.lua:213-217):**
```lua
-- AKA call banner is per-trick; its lifetime ends with the trick.
-- We rebuild s.playedCardsThisRound from s.tricks on resync, so
-- both fields are transient w.r.t. SaveSession.
akaCalled = true,
playedCardsThisRound = true,
```

**Verification.** `akaCalled` is in the TRANSIENT_FIELDS table, so `SaveSession` strips it before persisting `WHEREDNGNDB.session`. On `/reload`, `RestoreSession` reads back `WHEREDNGNDB.session` with `akaCalled` absent → `s.akaCalled` restored as nil.

**Edge case A — local player /reload mid-trick after AKA called.**
1. Trick 4 mid-flight: `s.akaCalled = {1, "H"}`. Local player /reloads.
2. `SaveSession` strips `akaCalled`. `RestoreSession` → `s.akaCalled = nil`.
3. Resync request → host's replay frame at Net.lua:459-464 re-broadcasts `s.akaCalled` IF host's banner is still set. If the host's trick advanced past the AKA trick, host's `s.akaCalled` is also nil (cleared by `ApplyTrickEnd`) — the replay condition (`if S.s.akaCalled then ...`) short-circuits. **No replay frame.** Rejoiner's banner stays nil. **Cosmetic-only divergence.**

**Edge case B — host /reload mid-trick after AKA called.**
1. Host's `s.akaCalled = {1, "H"}` set at trick 4. Host /reloads.
2. Host's `SaveSession` strips `akaCalled`. `RestoreSession` → `s.akaCalled = nil`.
3. Other clients still have the banner (their `_OnAKA` ran before; their `s.akaCalled` was saved as transient and is now nil locally too post-/reload IF they /reloaded; otherwise live).
4. Trick continues. When the host's `ApplyTrickEnd` eventually fires, line 1327 sets `s.akaCalled = nil` — already nil, idempotent.
5. M3 false-AKA detection: host /reloaded mid-trick → `s.akaCalled = nil` post-restore → M3 gate at State.lua:1238 (`s.akaCalled` truthy) fails → **false AKA NOT detected on the lead-already-played**. **Cosmetic for that single round** (defender can still call Takweesh manually).

**Verdict.** Correct semantics for `/reload`. The transient-fields list correctly excludes `akaCalled` from persistence. Edge case B's M3 gap is a pre-existing condition unrelated to the funnel structure — fundamentally the host's authority is preserved by the trick-history (`s.tricks`) being persisted, but per-trick-mid-flight detective state is intentionally ephemeral.

**Quote**:
```
state.lua:213      -- AKA call banner is per-trick; its lifetime ends with the trick.
state.lua:214      -- We rebuild s.playedCardsThisRound from s.tricks on resync, so
state.lua:215      -- both fields are transient w.r.t. SaveSession.
state.lua:216      akaCalled = true,
```

---

### F6 — Resync replay path (Net.lua:461-463) whispers banner — CONFIRMED CORRECT

**Severity:** none.

**Code (Net.lua:459-464):**
```lua
-- Replay AKA banner if active this trick. Trailing "1" tells
-- _OnAKA to bypass authorizeSeat (sender is host, not seat owner).
if S.s.akaCalled then
    whisper(target, ("%s;%d;%s;1"):format(
        K.MSG_AKA, S.s.akaCalled.seat or 0, S.s.akaCalled.suit or ""))
end
```

**Verification.**
1. Replay flag `"1"` → `_OnAKA` (Net.lua:3081) sets `isReplay = (replayFlag == "1") and fromHost(sender)`. Bypasses the `authorizeSeat` check (sender is host, not the AKA's seat-owner).
2. Defensive: `if isReplay and S.s.isHost then return end` (Net.lua:3083) — host should never receive its own replay frame.
3. Phase + contract checks still apply on the rejoiner (lines 3090, 3094) → if rejoiner is for some reason in non-PHASE_PLAY or non-HOKM, the replay is dropped silently. Correct.
4. `S.ApplyAKA(seat, suit)` runs on the rejoiner → banner set; voice cue plays (cosmetic).

**Edge case — replay-after-host-M3-clear.** If host detected false AKA mid-trick and cleared its `s.akaCalled = nil` (lines 1257/1263), the replay condition (`if S.s.akaCalled then`) short-circuits. No replay frame fires for a cleared banner. **Correct behavior** — rejoiner does not see a stale banner if the host already invalidated it.

**Edge case — partial trick mid-resync.** Replay frame fires after the per-play `MSG_PLAY` replay loop (Net.lua:453-458). Order: plays first (with their `.illegal` marks if any), then AKA banner. Correct sequencing — rejoiner state mirrors host's at snapshot time.

**Verdict.** Resync replay is mechanically correct. The only known propagation issue — non-host divergence from M3 host-only wipe (F-OP-12 / B-Net-05 F3) — is a pre-existing wire-broadcast issue unrelated to the resync replay specifically. The replay correctly gates on the host's CURRENT `s.akaCalled` at resync time.

**Quote**:
```
net.lua:459      -- Replay AKA banner if active this trick. Trailing "1" tells
net.lua:460      -- _OnAKA to bypass authorizeSeat (sender is host, not seat owner).
net.lua:461      if S.s.akaCalled then
net.lua:462          whisper(target, ("%s;%d;%s;1"):format(
net.lua:463              K.MSG_AKA, S.s.akaCalled.seat or 0, S.s.akaCalled.suit or ""))
net.lua:464      end
```

---

### F7 — v0.10.2 M3 false-AKA host-only wipe vs non-host clients keeping stale — MEDIUM

**Severity:** MEDIUM (B-Net-01 F-OP-12 / B-Net-05 F3 / D-RT-19 #6 — extended).

**Code (State.lua:1238-1265):**
```lua
if not illegal and s.isHost and s.akaCalled
   and s.akaCalled.seat == seat
   and #s.trick.plays == 0  -- this play IS the lead
   and s.contract and s.contract.type == K.BID_HOKM then
    local cardSuit = card:sub(2, 2)
    if cardSuit == s.akaCalled.suit then
        local cardRank = card:sub(1, 1)
        local order = { "A", "T", "K", "Q", "J", "9", "8", "7" }
        s.playedCardsThisRound = s.playedCardsThisRound or {}
        local valid = false
        for _, r in ipairs(order) do
            if r == cardRank then valid = true; break end
            if not s.playedCardsThisRound[r .. cardSuit] then
                break  -- a higher rank is still out: false claim
            end
        end
        if not valid then
            illegal = true
            illegalWhy = "false AKA"
            s.akaCalled = nil
        end
    else
        -- AKA on suit X but lead is suit Y → trivially false.
        illegal = true
        illegalWhy = "false AKA"
        s.akaCalled = nil
    end
end
```

**Issue.** The whole branch is gated on `s.isHost`. Both `s.akaCalled = nil` writes (lines 1257, 1263) only execute on the host. Non-host clients run `S.ApplyPlay` with `s.isHost = false`, the M3 block is skipped entirely, and their `s.akaCalled` keeps its `{seat, suit}` value until `S.ApplyTrickEnd` line 1327 organically wipes it at trick close (which fires symmetrically across all clients — see F3).

**Window.** Between the false-AKA lead-MSG_PLAY arrival at the non-host client AND the same trick's `MSG_TRICK` (which triggers `ApplyTrickEnd`), three more plays happen (positions 2, 3, 4). Those three plays' decisions on non-host clients see the stale banner:

- `pickFollow` (Bot.lua:2512-2514) reads `S.s.akaCalled` to decide receiver-relief — applies it to a non-existent claim. Bot at the partner-of-the-false-caller-seat may DISCARD low non-trump under M4 relief when they should be ruffing per Saudi rule.
- `legalPlaysFor` (Bot.lua:1607-1610) passes `S.s.akaCalled` to `R.IsLegalPlay`; non-host bot's legal-set may permissively include cards that the host's authoritative validator (which has cleared `akaCalled`) would correctly reject.
- Touching-honors WRITE (Bot.lua:489-491) reads `S.s.akaCalled.suit` — pollutes `topTouchSignal` with phantom signals about cards the false-caller doesn't actually hold (B-Net-05 F11 connection).
- Banner displayed to humans on non-host clients for the rest of the trick — misleading UI.

**Repro.** Hokm, trump=Diamonds. Host seat 1; non-host clients at seats 2-4. Bot at seat 3 (non-host) sends `MSG_AKA;3;S` (somehow — see F1 multi-AKA primitive). Banner = `{3,"S"}` on every client. Seat 3 leads `K♠` while `A♠` is unplayed:
- Host runs `S.ApplyPlay(3, K♠)`. M3 detects: order walk `{A,T,K,Q,...}` — `A♠` not in `playedCardsThisRound` → break — `valid = false` → `illegal = true; s.akaCalled = nil` host-side.
- Non-host clients run `S.ApplyPlay(3, K♠)` with `s.isHost = false`. M3 block at line 1238 short-circuits on the gate. Their `s.akaCalled` still `{3,"S"}`.
- Bot at seat 1 (partner of seat 3, host but operationally indexed at seat 1 — actually seat 1 is host so this combo is fine for the example; pick any partner-of-3 = seat 1 for the test). Wait — seat 1 IS host in this example. To make the divergence land, let host = seat 2 instead. Trick: seat 3 (false-AKA caller, non-host) leads K♠. Seat 4 follows. Seat 1 (partner of seat 3, non-host) consults `S.s.akaCalled` (stale `{3,"S"}`) via `pickFollow` and applies receiver-relief. Their card choice may diverge from what the host would have chosen.

**Strategic impact.**
- The false-AKA caller gets a free relief on partner-bot (non-host). Host's bots get correct gameplay; non-host bots and humans get the wrong gameplay.
- Touching-honors WRITE persists stale signals on non-host clients for the rest of the trick.
- Banner stays visible to humans on non-host clients until trick-end, misleading.
- Authoritative game state (host's `s.tricks`, host's score resolution) is correct. But replicated state is divergent until `MSG_TRICK` fires.

**Quote** (the host-only gate that creates the divergence):
```
state.lua:1238      if not illegal and s.isHost and s.akaCalled
state.lua:1239         and s.akaCalled.seat == seat
```

**Mitigation suggestion (out-of-scope).** Host explicitly broadcasts a "clear AKA" wire frame on M3 detection — e.g., `N.SendAKA(0, "")` interpreted as banner-clear by `_OnAKA`. OR propagate a `wasIllegal` bit on the MSG_PLAY frame so non-host's `S.ApplyPlay` can re-derive the clear (currently the wire format for MSG_PLAY does include some defensive flags but not the M3 outcome).

---

### F8 — Late-game conservatism + v0.10.2 L3 doubled-contract — sender-side only — MEDIUM

**Severity:** MEDIUM for the timing-window asymmetry (B-Net-05 F12 / D-RedTeam-01 E7).

**Code (Bot.lua:3321-3366):**
```lua
-- v0.10.2 AKA doubled-contract conservatism (review_v0.10.0
-- xref_X2_aka.md B3 / G18-10 paragraph 2). G18-10 explicitly
-- distinguishes regular vs doubled hands: "اللعب طبيعي مش
-- دبل" = early permissiveness applies in NORMAL play, not
-- doubled. ...
if S.s.contract and S.s.contract.doubled then return nil end
...
if trickNum >= 6 then
    if S.s.cumulative then
        local myTeam = R.TeamOf(seat)
        local meCum = S.s.cumulative[myTeam] or 0
        local oppCum = S.s.cumulative[(myTeam == "A") and "B" or "A"] or 0
        local target = S.s.target or 152
        local clutch = (oppCum >= target - 25)  -- opp near-win
                       or (meCum >= target - 25)  -- we near-clinch
                       or (math.abs(oppCum - meCum) <= 20)  -- close race
        if not clutch then return nil end
    else
        return nil
    end
end
```

**Issue.** Both gates are sender-side guards in `Bot.PickAKA` only. They prevent the BOT from CHOOSING to send AKA in a doubled / late-non-clutch round. Neither gate runs on the receiver / banner side: once an AKA IS broadcast, **changes to `S.s.contract.doubled` after the fact do NOT retroactively retract `s.akaCalled`.** No code path clears `s.akaCalled` on `S.ApplyDouble` / `ApplyTriple` / `ApplyFour` / `ApplyGahwa`.

**Repro (D-RedTeam-01 E7 / B-Net-05 F12).**
1. Trick 4: Bot at seat 1 sends legitimate AKA on hearts (not doubled; trickNum=4; passes all sender gates). `S.ApplyAKA(1, "H")` → `s.akaCalled = {1, "H"}` everywhere. Banner live.
2. Mid-trick or between tricks: opp seat 4 calls Bel via `N.LocalDouble`. Host runs `S.ApplyDouble(4, true)` → `s.contract.doubled = true`.
3. **`ApplyDouble` does NOT clear `s.akaCalled`.** No banner retraction. Ts continues.
4. Bot partner of seat 1 at seat 3 still applies receiver-relief based on the now-stale-by-policy banner via `pickFollow`. The L3 gate runs only at the next `Bot.PickAKA` call (i.e., next time anyone considers sending AKA), not retroactively on the live banner.
5. Opps observe the banner and now know "team A holds the boss of suit H" → can plan trump-tempo to exploit.

**Worse-case reading.** A skilled human team-A seat 1 calls AKA legitimately. Human at seat 4 (opp) immediately calls Bel — **every legitimate AKA-call becomes an instant ×2 setup if opps are willing to Bel.** The L3 conservatism is sender-side only; the BANNER isn't policy-aware about its own retraction.

**Verdict.** L3 mechanism is correct *in isolation* (sender-side decision is right) but the asymmetric timing window means a determined opp can convert any legitimate AKA into a coordinated ×2 trap.

**Quote**:
```
bot.lua:3332      if S.s.contract and S.s.contract.doubled then return nil end
```

(The gate fires at sender-time only. No corresponding clear in `S.ApplyDouble`.)

**Mitigation suggestion (out-of-scope).** Add `s.akaCalled = nil` clear in `S.ApplyDouble(seat, true)` (and `ApplyTriple` / `ApplyFour` / `ApplyGahwa` for transitive consistency) when the contract becomes doubled mid-round. The banner would be informationally hostile to its caller post-double; retract it. Symmetric: bot's `PickDouble` should also consult `s.akaCalled` and avoid auto-doubling when partner has called AKA (that's a separate gap; PickDouble doesn't read `s.akaCalled` today).

---

## Summary table

| # | Finding | Severity | Source xref |
|---|---|---|---|
| F1 | `ApplyAKA` unconditional overwrite (multi-AKA bypass) | MEDIUM | D-RT-19 #7, B-Net-05 F4 |
| F2 | `ApplyAKA` contract-type guard MISSING (def-in-depth) | LOW | D-RT-04 / D-RedTeam-01 E1, B-Net-05 F1+F8a |
| F3 | `ApplyTrickEnd` clears `s.akaCalled` (line 1327) | OK | D-RT-19 #6, D-RT-27 F-07 |
| F4 | Banner persistence past round-end (def-in-depth via ApplyStart:795) | LOW | D-RT-04 F8, D-RT-08, D-RedTeam-01 E1 |
| F5 | Mid-trick `/reload` restoration (TRANSIENT_FIELDS) | OK | D-RedTeam-01 (resync section) |
| F6 | Resync replay path (Net.lua:461-463) | OK | B-Net-05 F9 |
| F7 | v0.10.2 M3 host-only wipe vs non-host stale | MEDIUM | D-RT-19 #6, B-Net-01 F-OP-12, B-Net-05 F3 |
| F8 | Late-game + L3 doubled — sender-side only | MEDIUM | D-RedTeam-01 E7, B-Net-05 F12 |

---

## Mutation-call ordering recap (the canonical happy path on host)

```
[seat S calls AKA legitimately]
  N.LocalAKA(suit)          [Net.lua:2344]
    ├─ phase=PLAY, Hokm, lead-context, turn==localSeat all check
    ├─ S.LocalAKAcandidate verifies hand actually has the boss
    ├─ S.ApplyAKA(seat, suit) [State.lua:1443] → s.akaCalled = {seat, suit}
    └─ N.SendAKA(seat, suit)  [Net.lua:208]   → MSG_AKA broadcast
       └─ wire loopback / receivers → N._OnAKA  [Net.lua:3075]
            ├─ fromSelf rejected (host already applied)
            ├─ phase / contract / authorize gates
            └─ S.ApplyAKA on each replica → s.akaCalled = {seat, suit}

[seat S then plays the lead card]
  S.ApplyPlay(S, card)       [State.lua:1197]
    ├─ host-only: R.IsLegalPlay validates against hostHands (line 1219)
    ├─ host-only M3: false-AKA detection (line 1238-1265)
    │   └─ on mismatch: illegal=true, illegalReason="false AKA",
    │      s.akaCalled = nil  [HOST ONLY — F7 hole]
    └─ append to s.trick.plays

[other seats play out the trick]

[4th play arrives, host eventually calls]
  S.ApplyTrickEnd(winner, points)  [State.lua:1300]
    └─ s.akaCalled = nil  [line 1327, all clients]

[round eventually ends]
  S.ApplyRoundEnd(...)  [State.lua:1463]
    └─ no AKA wipe (relies on next ApplyStart)

[next round]
  S.ApplyStart(roundNumber, dealer)  [State.lua:752]
    └─ s.akaCalled = nil  [line 795]
```

---

## Confidence

**HIGH confidence:**
- F1 (`ApplyAKA` line 1446 unconditional overwrite — verbatim quote of the line).
- F2 (`ApplyAKA` 1443-1450 has zero contract-type / trump-suit checks — full function read).
- F3 (`ApplyTrickEnd` 1327 verbatim verified; `#s.trick.plays ~= 4` partial-trick rejection at 1306-1310 verified).
- F4 (`ApplyRoundEnd` 1463-1589 read in full — no `s.akaCalled = nil`; `ApplyRoundResult` 1591-1595 also no clear; `HostBeginRound2` 1825-1857 also no clear — `ApplyStart` line 795 is the cleanup site).
- F5 (TRANSIENT_FIELDS line 216 — `akaCalled = true` literal verified).
- F6 (replay frame Net.lua:459-464 verbatim verified; `_OnAKA` replay-flag bypass at line 3081-3083 verified).
- F7 (the `s.isHost` gate at State.lua:1238 is the SAME condition that gates the entire false-AKA branch including the two `s.akaCalled = nil` writes at 1257/1263; non-host clients skip the whole block).
- F8 (`Bot.PickAKA` line 3332 sender-side gate verified; `S.ApplyDouble` 1075-onward read — no `s.akaCalled = nil` line).

**MEDIUM confidence:**
- F1 multi-AKA timing window in real network conditions (depends on actual MSG_AKA → MSG_PLAY ordering observed under realistic latency).
- F7 strategic impact magnitude (bot-decision divergence quantified via `pickFollow` paths but exact frequency under realistic play untested).
- F8 ApplyDouble / ApplyTriple / ApplyFour / ApplyGahwa sites all separately verified for AKA clear absence — pattern is consistent across the four escalation handlers.
