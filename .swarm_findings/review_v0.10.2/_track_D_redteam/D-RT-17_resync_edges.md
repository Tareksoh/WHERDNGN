# D-RT-17 — Disconnect / Rejoin / Resync Edge Cases

Red-team probe of WHEREDNGN's persistence + resync code. Targets:
SaveSession / RestoreSession (`State.lua:250-375`),
ApplyResyncSnapshot (`State.lua:388-540`),
N.SendResyncReq / N.SendResyncRes / N._OnResyncReq / N._OnResyncRes
(`Net.lua:316-465`, `:3098-3220`),
PLAYER_LOGIN / PLAYER_ENTERING_WORLD (`WHEREDNGN.lua:130-313`).

Per-scenario verdicts plus 3 NEW findings beyond the prior
`audit_v0.9.0/05_m1_m2_timer_rearm.md` and
`audit_v0.9.0/15_v091_l5_resync.md` reports.

---

## 1. Mid-trick /reload restoration — PASS (with one latent UI gap)

A non-host who /reloads mid-PHASE_PLAY:

- `SaveSession` at PLAYER_LOGOUT writes `s` minus TRANSIENT_FIELDS
  (`State.lua:250-287`). `playedCardsThisRound` is transient, so it's
  rebuilt on restore by walking `s.tricks` + `s.trick.plays`
  (`State.lua:343-353`). `lastTrick` is also transient — peek button
  loses pre-/reload trick.
- `RestoreSession` (PLAYER_LOGIN) brings phase, contract, hand, tricks,
  trick.plays back. Cross-character guard fails closed (#54 fix).
- `maybeRequestResync` fires 2s post-PLAYER_ENTERING_WORLD; host's
  `_OnResyncReq` whispers `MSG_RESYNC_RES` + replays MELD/TRICK/PLAY.
- `ApplyResyncSnapshot` wipes `s.tricks={}`, `s.meldsByTeam={A={},B={}}`,
  `s.meldsDeclared={}` (`State.lua:514-516`) and the replay restores
  authoritative state.

> "Round history is not snapshotted; it arrives via replayed
>  MSG_MELD / MSG_TRICK broadcasts right after the snapshot."
> (`State.lua:510-516`)

**Latent UI gap**: `meldsDeclared` is wiped by ApplyResyncSnapshot but
the resync replay does NOT reseed it. Only `meldsByTeam` is
reconstructed. `meldsDeclared` is host-side AFK auto-declare bookkeeping
(`Net.lua:3433-3441`); for a non-host rejoiner it's UI-only state.
Ineffective consequence in current code, but if the rejoiner's UI uses
`meldsDeclared[seat]` to gate the local meld picker after rejoin during
a still-open trick-1 window, melds won't show declared. Verified the
trick-1 wire gate in `S.ApplyMeld` (`State.lua:1154`) protects state
from corruption — only UI rendering is at risk.

---

## 2. Mid-bidding /reload — PASS

PHASE_DEAL1 / PHASE_DEAL2BID persist through SaveSession (only
IDLE/LOBBY/GAME_END skip per `State.lua:252-256`). Restored s.bids,
s.bidRound, s.bidCard, s.dealer all carry. Resync snapshot reconfirms.

Host re-arm: PLAYER_LOGIN → if `s.turn` and `s.turnKind == "bid"` and
seat is human, `StartTurnTimer(s.turn, "bid")` fires
(`WHEREDNGN.lua:174-177`). MaybeRunBot reschedules bot bid pending.

---

## 3. Mid-meld-declaration /reload — PARTIAL

PHASE_DEAL3 persists. Hand carries. Already-declared melds in
`s.meldsByTeam` are saved (NOT in TRANSIENT_FIELDS).

But: `s.meldsDeclared` is also persisted (not transient). If the local
seat declared one meld then /reloaded, on restore `meldsDeclared[mySeat]`
is true — UI hides the "Declare" button. This is correct behavior.

Note: "skip" doesn't write `meldsDeclared[seat]=true` until the player
explicitly clicks Done or commits a card. A /reload mid-deliberation
loses the implicit "I'm thinking" state; player resumes with same hand
and the declare panel still open. Acceptable.

---

## 4. Host /reload (hostHands restore) — PASS

`s.hostHands` is in `s` and NOT in TRANSIENT_FIELDS (`State.lua:191-247`).
`s.hostDeckRemainder` is explicitly NOT transient (comment at lines
193-198 calls out the reason — pairs with hostHands across DEAL1..3).

Verified: a host /reload mid-DEAL2BID restores hostHands, hostDeckRemainder,
contract.bidder. `HostDealRest` at `State.lua:1624-1656` reads both —
guard at line 1625 prevents partial deal if either is nil.

> "A host /reload after the initial 5-card deal but before the final
>  3-card deal would restore hostHands without hostDeckRemainder; then
>  HostDealRest short-circuits on the missing remainder and the round
>  soft-locks. Both fields must persist together."
> (`State.lua:193-198`)

Both persist. PASS.

The PLAYER_LOGIN re-arm block (`WHEREDNGN.lua:157-217`) covers:
- `SendLobby` re-broadcast for reconnected peers
- `MaybeRunBot` to resume bot scheduling
- `StartTurnTimer` for human turn AFK (`:172-178`)
- `StartBelTimer` for DOUBLE/TRIPLE/FOUR/GAHWA (`:179-197`)
- `_HostStepPlay` re-fire for stuck 4-play tricks (`:206-217`)

---

## 5. Mid-Takweesh /reload — PARTIAL (NEW finding: race window)

Takweesh path: `LocalTakweesh` → broadcast MSG_TAKWEESH →
`HostResolveTakweesh` (`Net.lua:2127`). Within HostResolveTakweesh:
ApplyRoundEnd sets `s.phase = PHASE_SCORE`, then `S.s.takweeshResult`
is set, MSG_ROUND broadcast, MSG_TAKWEESH_OUT broadcast.

**FAIL window**: if the host /reloads BETWEEN `S.ApplyRoundEnd` (line
2264) and `N.SendRound` (line 2291), the host has phase=PHASE_SCORE
locally with updated cumulative, but no round broadcast yet went out.
Other clients still see phase=PHASE_PLAY waiting for the resolution.

After /reload: phase=SCORE persists (SaveSession). Host PLAYER_LOGIN
re-arm runs — but the re-arm block has NO branch for
phase==PHASE_SCORE. SendLobby re-broadcasts (clients ignore mid-game)
but no MSG_ROUND retransmit. **Soft-lock**: clients stuck in PHASE_PLAY
waiting for a trick advance the host won't drive, with the SWA timer
already cancelled at `Net.lua:2144`. Host's UI shows score panel; clients
show stuck table.

The window is small (microseconds between ApplyRoundEnd and SendRound)
but this is the same class of bug as the v0.9.0 M1/M2 fixes — race
between local apply and broadcast straddling persistence.

`s.takweeshResult` is in TRANSIENT_FIELDS (`State.lua:212`) so the
banner is lost on /reload but that's a UI nicety.

**Recommend**: PLAYER_LOGIN host branch should detect PHASE_SCORE +
recent lastRoundDelta and re-broadcast MSG_ROUND, OR have the host
proactively SaveSession after the ApplyRoundEnd/SendRound pair.

---

## 6. Mid-overcall /reload (M2 re-arm edge cases) — PARTIAL

The prior `audit_v0.9.0/05_m1_m2_timer_rearm.md` audit already flagged
**Edge 5 (already-EXPIRED window before /reload) as FAIL**. Re-verified
in current source:

> "Neither M2 block checks `GetTime() - startedAt >= 5` before re-arming.
>  If the host /reload-ed at second 6 of a 5s window that should already
>  have auto-resolved, the fix re-arms ANOTHER fresh 5s window instead
>  of immediately resolving."

`WHEREDNGN.lua:256-269`:

```
if B.State.s.phase == K.PHASE_OVERCALL
   and B.State.s.overcall then
    B.State.s.overcall.startedAt = (GetTime and GetTime()) or 0
    if C_Timer and C_Timer.After then
        C_Timer.After(K.OVERCALL_TIMEOUT_SEC, function()
            ...
            B.Net._HostResolveOvercall()
        end)
    end
end
```

No elapsed check before re-arm. STILL FAIL.

`WHEREDNGN.lua:270-292` (SWA) has the same shape — re-arms another full
5s window without checking original ts. STILL FAIL.

**NEW related finding**: the SWA re-arm at line 273-292 reads
`req.encodedHand` and falls back to `{}`. If a /reload happens just
after SendSWAReq before encodedHand was stashed in swaRequest, the
re-arm fires HostResolveSWA(caller, {}). HostResolveSWA's IsValidSWA
check would judge an empty-hand SWA as invalid → **SWA caller's team
is penalized through no fault of their own**. Mitigated by line 2516
`encodedHand = enc` being set in the synchronous `LocalSWA` write —
the order is encodedHand-first then SendSWAReq, so the persisted
swaRequest always carries encodedHand. PASS in current code, but the
fall-through to `{}` is a footgun if any future refactor reorders.

---

## 7. Resync window L5 30s late-arriving response — PASS (verified)

The prior `audit_v0.9.0/15_v091_l5_resync.md` verified the
`expectingResyncRes` flag, 30s expiry, and gameID gate. Re-verified
post-/reload:

- `Net.lua:313` `local expectingResyncRes = false` — module-scoped,
  NOT persisted. A /reload starts the flag at false again.
- `Net.lua:316-328` SendResyncReq sets flag=true and arms 30s timer.
- `Net.lua:3191` `_OnResyncRes` checks `if not expectingResyncRes
  then return`.
- `Net.lua:3196-3199` gameID-match against `WHEREDNGNDB.lastGameID`.

**NEW edge (cross-character ghost request)**: `RestoreSession` on a
character mismatch returns false WITHOUT clearing
`WHEREDNGNDB.lastGameID` (`State.lua:307-308`). PLAYER_ENTERING_WORLD
unconditionally fires maybeRequestResync 2s later on every login;
the cross-character login still has `lastGameID` from the original
character, so it broadcasts MSG_RESYNC_REQ on the wrong character's
gameID. The host `_OnResyncReq` rejects this (sender not in roster,
`Net.lua:3147-3155`) — confirmed safe — but the request goes on the
wire and consumes one cycle of the 5s per-sender cooldown
(`Net.lua:3107`).

This is the same finding as `audit_v0.7.1/35_save_restore.md` line 25
(unfixed). Low severity, but the fix is one line:
`WHEREDNGNDB.lastGameID = nil` in the cross-character early-return.

---

## 8. Seat reassignment after rejoin — PASS

Same-realm /reload: WoW party membership persists across /reload, no
GROUP_ROSTER_UPDATE fires for a /reloading party member. Verified by
inspecting WHEREDNGN.lua:326-355 — `HostKickSeat` only fires when
`UnitExists("partyN")` returns false for the seat owner, which won't
happen during a /reload window.

`ApplyResyncSnapshot` re-derives `s.localSeat` via `S.SeatOf(s.localName)`
(`State.lua:489-494`) using the normalized name match, so even if the
saved session had a non-suffixed name and the new live session has
realm-suffixed, the seat lookup succeeds (8th-audit fix at
`State.lua:577`).

**Edge — actual disconnect (not /reload)**: if the player drops party
for >server timeout (e.g., crash, ISP drop), `HostKickSeat(seat)` fires
on host, the seat goes nil in s.seats, and a SendLobby broadcast empties
the seat for everyone. The disconnected player rejoins party,
RestoreSession brings them to PHASE_PLAY locally, they resync — but the
host's snapshot has their seat already empty. ApplyResyncSnapshot at
`State.lua:471-472` sets `s.seats[seat] = nil` for empty seats. The
rejoiner's localSeat re-derive (`State.lua:489-494`) returns nil. They
land in a phantom phase=PLAY with localSeat=nil — UI in soft-lock.
Recovery is /reset (`Slash.lua:129`) but no UX prompt surfaces this.

---

## 9. GAME_END /reload restore behavior — PASS

`SaveSession` skips persistence when `phase == PHASE_GAME_END`
(`State.lua:252-256`). Restored: s gets reset() defaults via
RestoreSession early-return (line 290 `if not WHEREDNGNDB.session
then return false`). PHASE_IDLE.

`WHEREDNGNDB.lastGameID` is NOT cleared by `ApplyGameEnd` — it persists
until next reset() invocation. After /reload at PHASE_GAME_END the
PLAYER_ENTERING_WORLD still fires maybeRequestResync. If the host
hasn't yet started a new lobby, the host's gameID still matches; the
host responds with a GAME_END snapshot. ApplyResyncSnapshot lands
phase=GAME_END which clobbers the rejoiner's clean PHASE_IDLE state
back to GAME_END (with stale winner), but the bid card / hand / etc.
all clear. UI shows a stale "X team wins" banner.

This is harmless — the winner banner is correct content. Once the host
starts a new lobby (HostBeginLobby calls reset() and assigns a new
gameID), the OLD gameID-mismatch gate at `Net.lua:3196-3199` correctly
rejects any late-arriving MSG_RESYNC_RES bound to the old gameID.

---

## 10. Cross-character /reload (M4 fail-closed) — PASS

`State.lua:307-308`:

```
if not sess.owner or not s.localName then return false end
if sess.owner ~= s.localName then return false end
```

The v0.9.2 #54 fix correctly fails closed when EITHER sess.owner OR
s.localName is nil. Pre-v0.9.2 the OR-short-circuit allowed
cross-character data leak when localName was transiently nil. Now
verified safe.

**NEW finding (PII leak adjacent — minor)**: SaveSession at PLAYER_LOGOUT
uses `s.localName` as `owner` (`State.lua:283-286`). If character A
finishes a hand and logs out while phase==PHASE_GAME_END, SaveSession
nils session (line 254) — character A's session is gone. Login as
character B → no session to restore. Login back as character A → no
session to restore (correct). 

But: if character A logs out at phase==PHASE_PLAY with an unfinished
hand, session persists. Login as character B → cross-character guard
rejects. Login as character C → also rejects. **However**, on character B's
PLAYER_LOGOUT at PHASE_IDLE, SaveSession nils the session
unconditionally (`State.lua:254`). Character A's mid-hand state is
overwritten by character B's clean logout. Character A returns to find
no save.

This is a minor footgun for multi-character users: any other character
logging out clears your in-progress save. The fix would be to scope
`WHEREDNGNDB.session` per-character (e.g., `WHEREDNGNDB.session[ownerName]`)
or only nil it when `s.localName == sess.owner`. Not security-critical.

---

## 11. NEW finding: Host /reload mid-PHASE_PREEMPT misses AFK timer

`WHEREDNGN.lua:179-197` re-arms StartBelTimer for DOUBLE/TRIPLE/FOUR/GAHWA
on host PLAYER_LOGIN. There is NO branch for `phase == K.PHASE_PREEMPT`.

The re-arm block at line 161 calls `MaybeRunBot()`, which DOES include a
PREEMPT branch at `Net.lua:3802-3924`. Inside that branch:
- For each seat in preemptEligible: if bot, dispatch via timer + return.
- If human, call `StartBelTimer(seat, "preempt_pass")` + return.

So the FIRST eligible seat (by iteration order) gets dispatched/timed,
and the function returns. If the first eligible is a bot that hasn't
yet acted, MaybeRunBot fires correctly. If the first is human, their
timer is armed. Subsequent eligibles are picked up in turn via the
ApplyPreemptPass → MaybeRunBot chain. **PASS** for normal flow.

**Edge case**: if the FIRST eligible is a HUMAN but their decision was
already in flight (claim broadcast going out at the moment of /reload),
the post-restore MaybeRunBot re-arms a fresh AFK timer for them. They
may or may not see their own pre-/reload broadcast applied (loopback
delivery). If their broadcast was on the wire but not yet looped back,
the host's restored state still has them as eligible. They re-act,
duplicating the broadcast. The receiver-side handlers (`_OnPreempt`,
`_OnPreemptPass`) check `S.s.preemptEligible` for membership and
ApplyPreemptPass removes the seat from the list — duplicates are
idempotent. PASS.

---

## 12. NEW finding: ApplyResyncSnapshot clears `winner` only via field-omission

`State.lua:39` reset() sets `s.winner = nil`. RestoreSession overlays
saved fields without explicitly nilling unset ones because line 313
hard-resets first (`for k in pairs(s) do s[k] = nil end`). Good.

But `ApplyResyncSnapshot` does NOT hard-reset before applying — it
selectively writes fields parsed from the wire (`State.lua:424-540`).
The wire format includes 29 fields: gameID, phase, dealer, round, turn,
turnKind, contract.* (8 fields), cumulative.A/B, paused, bidRound,
4 seat names, 4 bids, botMask, target. **`s.winner` is NOT in the
snapshot.**

If a rejoiner has a stale `s.winner = "A"` from an earlier game in the
same session (e.g., they finished one game, their host started another,
they /reloaded mid-bid), `ApplyResyncSnapshot` won't clear it. The
PHASE_GAME_END check in UI consumes `s.winner` — could surface a
phantom "A team wins" banner over a live game. Mitigated because most
flows route through ApplyLobby's "newGame" branch at `State.lua:711-727`
which calls `S.Reset()`, but the resync path doesn't.

**Recommend**: `ApplyResyncSnapshot` should explicitly clear
`s.winner = nil` alongside the other transient cleanup at lines
524-534, OR include `winner` in the snapshot payload as field 30.

---

## 13. NEW finding: late MSG_TRICK during resync replay can race local trick close

`SendResyncRes` whispers MSG_TRICK frames (lines 439-447) for closed
tricks. `_OnTrick` at `Net.lua:1474-1501` accepts these (sender == host,
not self, not isHost). It rebuilds `s.trick` from encoded plays, then
calls `S.ApplyTrickEnd(winner, points)`.

But ApplyTrickEnd has a guard at `State.lua:1306-1310`:

```
if #s.trick.plays ~= 4 then
    L.Debug("state", "ApplyTrickEnd ignored partial trick (%d plays)",
            #s.trick.plays)
    return
end
```

The guard is correct but assumes `s.trick.plays` has 4 entries. The
replay rebuilds `s.trick.plays` from `encPlays` then calls ApplyTrickEnd.
If a malformed (truncated) MSG_TRICK arrives — `encPlays` length isn't
divisible by 3, or contains an invalid seat — `_OnTrick` only inserts
plays that pass the per-iteration validation. If only 3 valid plays
were extracted, ApplyTrickEnd returns early. **The trick is DROPPED.**
It does NOT enter `s.tricks`. The receiver's tricks count is now 1
short of host's. The next round of replay continues, but the receiver
ends up with `#s.tricks == 7` while host has 8.

Probability: extremely low (would require corrupted addon channel
payload). The only way this matters in practice is a buggy host
serializer; standard wire format always packs 4 plays per trick.
PASS in healthy code.

---

## Summary table

| # | Scenario | Verdict |
|---|---|---|
| 1 | Mid-trick /reload | PASS (UI gap on meldsDeclared) |
| 2 | Mid-bidding /reload | PASS |
| 3 | Mid-meld /reload | PARTIAL (acceptable UX) |
| 4 | Host /reload (hostHands) | PASS |
| 5 | Mid-Takweesh /reload | **FAIL** (race window between ApplyRoundEnd and SendRound) |
| 6 | Mid-overcall /reload (M2 edge 5) | **FAIL** (already-flagged elapsed-check bug, still unfixed) |
| 7 | Resync 30s window | PASS (cross-character ghost request annoyance) |
| 8 | Seat reassignment | PASS (full-disconnect-then-rejoin soft-lock with localSeat=nil) |
| 9 | GAME_END /reload | PASS (stale winner banner cosmetic) |
| 10 | Cross-character /reload (M4) | PASS (multi-character session-overwrite minor footgun) |
| 11 | Host /reload mid-PREEMPT | PASS (covered transitively by MaybeRunBot) |
| 12 | ApplyResyncSnapshot leaks `s.winner` | **FAIL** (phantom winner banner) |
| 13 | Resync MSG_TRICK truncation | PASS (host serializer always correct) |

## Recommendations (ordered by severity)

1. **Mid-Takweesh /reload (#5)** — host PLAYER_LOGIN should detect
   `phase==PHASE_SCORE && lastRoundDelta` and re-broadcast MSG_ROUND
   to clients still in PHASE_PLAY. Or move SendRound earlier in
   HostResolveTakweesh to shrink the race window.

2. **M2 edge 5 (#6)** — add elapsed-time precheck before re-arm in
   both `WHEREDNGN.lua:256-269` (overcall) and `:270-292` (SWA):

   ```
   local elapsed = (GetTime() or 0) - (S.s.overcall.startedAt or 0)
   if elapsed >= K.OVERCALL_TIMEOUT_SEC then
       N._HostResolveOvercall()
   else
       -- existing re-arm
   end
   ```

3. **Phantom winner (#12)** — add `s.winner = nil` to the transient
   cleanup at `State.lua:524-534`.

4. **Cross-character ghost request (#7)** — clear `WHEREDNGNDB.lastGameID`
   in the cross-character early-return at `State.lua:307-308`. Already
   flagged in `audit_v0.7.1/35_save_restore.md`; still unfixed.

5. **Per-character session scoping (#10)** — defensive change for
   multi-character users. Replace `WHEREDNGNDB.session` with
   `WHEREDNGNDB.session[ownerName]` keyed map. Non-blocking.
