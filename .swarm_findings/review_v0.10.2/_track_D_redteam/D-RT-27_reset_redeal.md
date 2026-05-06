# D-RT-27 — Reset / Redeal State Transitions: Stale-State Corruption

Red-team probe of `reset()`, `S.ApplyStart`, `S.ApplyRoundEnd`,
`S.ApplyRedealAnnouncement`, `N._HostRedeal`, `N.HostStartRound`,
`N.HostResolveTakweesh`, `N.HostResolveSWA`, `S.ApplyResyncSnapshot`,
and `S.ApplyLobby` "newGame" branch — tracking how each per-round
transient is cleared at every transition boundary. Cross-references
D-RT-17 (mid-Takweesh /reload race), and the existing
`audit_v0.9.0/05_m1_m2_timer_rearm.md` and
`audit_v0.9.0/15_v091_l5_resync.md` work.

Verdict legend per field:
- **CONFIRMED-CLEARED**: cleared at every relevant transition; no leak.
- **PARTIAL**: cleared at some transitions, leaks at others.
- **UNDEFENDED-CLEARED**: cleared at the obvious transition, but a
  subtler race or timer can produce stale state for a window.

---

## Per-field verdict table

| Field | reset() | ApplyStart | ApplyRoundEnd | ApplyResyncSnapshot | ApplyTrickEnd | Verdict |
|---|---|---|---|---|---|---|
| `redealing` | nil | nil | (n/a) | nil | (n/a) | **PARTIAL** — race window in `_HostRedeal` 3s timer |
| `lastTrick` | nil | nil | (kept for peek) | nil | (re-set by trick end) | **CONFIRMED** with intent |
| `peekedThisRound` | nil | false | false | (kept) | (n/a) | **CONFIRMED** |
| `pendingPreemptContract` | nil | (n/a) | (n/a) | nil | (n/a) | **PARTIAL** — leaks across abandoned PREEMPT → next round |
| `handRound` | nil | (kept-set; new round bump) | (n/a) | (n/a) | (n/a) | **CONFIRMED** with mismatch guard |
| `meldHoldUntil` | nil | `{}` | (kept) | (n/a — not reset on resync) | (n/a) | **UNDEFENDED** — wall-clock collision on /reload |
| `localPlayedThisTrick` | nil | (n/a) | (n/a) | (n/a) | cleared on `ApplyTurn` | **CONFIRMED** |
| `akaCalled` | nil | nil | (kept) | nil | nil | **CONFIRMED** at trick end |
| `playedCardsThisRound` | `{}` | `{}` | (kept) | `{}` | (additive) | **CONFIRMED** |
| `lastRoundResult` | nil | (n/a) | (kept) | nil | (n/a) | **PARTIAL** — leaks across non-Takweesh round-end |
| `lastRoundDelta` | nil | (n/a) | overwritten | nil | (n/a) | **CONFIRMED** |
| `takweeshResult` | nil | nil | (kept for banner) | nil | (n/a) | **CONFIRMED** |
| `swaResult` | nil | nil | (kept for banner) | nil | (n/a) | **CONFIRMED** |
| `swaRequest` | nil | nil | (kept) | nil | (n/a) | **PARTIAL** — abandoned mid-round-end fork |
| `swaDenied` | nil | nil | (kept; 3s C_Timer) | nil | (n/a) | **UNDEFENDED** — wall-clock on /reload |
| `pendingHost` | nil | (n/a) | (n/a) | (n/a) | (n/a) | **CONFIRMED** (cleared in lobby join) |
| `hostDeckRemainder` | nil | (n/a — set in HostDealInitial) | (n/a) | (n/a) | (n/a) | **CONFIRMED** with persistence pairing |

---

## Detailed findings

### F-01 — `redealing` race window in `_HostRedeal` 3s timer (CONFIRMED-CLEARED at boundary, but UNDEFENDED post-spawn)

`State.lua:103, 137-158, 530, 804`. `Net.lua:1721-1781`.

The redeal banner is set in three places and cleared in five. The
clear paths look complete:
- `reset()` sets `s.redealing = nil` (line 103).
- `ApplyStart` sets `s.redealing = nil` (line 804) — a new round
  start auto-dismisses any banner.
- `ApplyResyncSnapshot` sets `s.redealing = nil` (line 530) — the
  rejoiner won't carry a stale banner.
- The 3.5s self-clear in `ApplyRedealAnnouncement` (lines 149-156).
- The `_HostRedeal` callback's own `if S.s.phase ~= ... and not
  S.s.redealing then return` early-return (lines 1758-1761).

But the gen-token guard in `_HostRedeal` at `Net.lua:1750-1753` only
defends against `/baloot reset`-during-countdown. Code:

```
B._redealGen = (B._redealGen or 0) + 1
local thisGen = B._redealGen
C_Timer.After(3.0, function()
    if thisGen ~= B._redealGen then return end
    if not S.s.isHost then return end
    if S.s.phase ~= K.PHASE_DEAL2BID and S.s.phase ~= K.PHASE_DEAL1
       and not S.s.redealing then
        return
    end
    if S.s.paused then return end
    S.s.dealer = nextDealer
    ...
    S.ApplyStart(S.s.roundNumber, nextDealer)
```

**Race**: another `_HostRedeal` invocation during the 3s window (e.g.
two Kawesh calls land within 3s, or all-pass redeal followed by a
mid-banner Kawesh from the new dealer's hand) bumps `_redealGen`, the
old callback no-ops via `thisGen ~= B._redealGen`, but the SECOND
`_HostRedeal` issues a fresh `S.ApplyRedealAnnouncement(nextDealer2)`
that overwrites `s.redealing.nextDealer`. Both `C_Timer.After(3.5)`
auto-clear closures still fire — the first checks
`s.redealing.nextDealer == nextDealerSeat` (its captured local) and
returns true if the dealer happens to coincide (4-cycle wraparound).

This is mostly cosmetic, but combined with the dealer-rotation
double-rotation possibility (each `_HostRedeal` advances `s.dealer`)
the second redeal can rotate dealer twice if the first callback is
allowed to set `s.dealer = nextDealer` before being invalidated.

**Quote** (`Net.lua:1762-1765`):
```
    if S.s.paused then return end
    S.s.dealer = nextDealer
    if B.Bot and B.Bot.ResetMemory then B.Bot.ResetMemory() end
    S.ApplyStart(S.s.roundNumber, nextDealer)
```

The `_redealGen` bump in `Net.lua:1750` happens BEFORE the
`C_Timer.After` arm, so a re-entrant call to `_HostRedeal` would
correctly invalidate the prior closure. But if `_HostRedeal` is
called twice rapidly enough that BOTH closures schedule before either
fires, the gen-bump makes the first a no-op and the second runs —
correct. The race is narrower: first closure has fired (dealer
rotated, ApplyStart begun) when the second `_HostRedeal` invocation
issues a new banner. The first round's setup races the second's
banner-drive. Verdict: **PARTIAL** with low real-world reachability.

---

### F-02 — `pendingPreemptContract` leaks across PREEMPT-abandon path (PARTIAL)

`State.lua:106, 240-247, 531, 1939`.

`pendingPreemptContract` is documented as NOT transient (lines
240-247), so it persists through /reload. ApplyResyncSnapshot
explicitly nils it (line 531) on resync. But `ApplyStart` does NOT
clear it (lines 752-823 don't touch it).

Scenario: round R ends in PHASE_PREEMPT (host /reload at
`HostFinishRound` time has already moved phase past PREEMPT, but the
field is set during `_BeginPreempt` — search Net.lua for the writer).
The next round's `ApplyStart` runs without clearing
`s.pendingPreemptContract`. If `_FinalizePreempt` later runs on stale
data, it would resurrect a previous round's bidder/contract.

**Code** (`State.lua:752-806` — what `ApplyStart` clears):
```
s.akaCalled    = nil
s.meldHoldUntil = {}
s.phase        = K.PHASE_DEAL1
s.redealing    = nil
s.takweeshResult = nil
s.swaResult      = nil
s.swaRequest     = nil
s.swaDenied      = nil
```
No mention of `pendingPreemptContract` or `preemptEligible`.

The protective layer is that `LocalPreempt` and `_FinalizePreempt`
gate on `S.s.phase == K.PHASE_PREEMPT`, and a fresh `ApplyStart` sets
`s.phase = K.PHASE_DEAL1`. So a finalize call would no-op.

**But**: `_OnPreempt` and the host-side `_BeginPreempt` are non-self
gated on `s.preemptEligible` not the phase. If a stale
`preemptEligible` survives an aborted Kawesh-during-PREEMPT path,
it could be acted on. Searching for `preemptEligible` clears...

`State.lua:61` declares `preemptEligible`. `State.lua:240-247` notes
it's NOT transient. ApplyResyncSnapshot clears it (line 532).
`ApplyStart` does NOT clear it.

If the round ends in any non-PREEMPT path (normal play, takweesh,
SWA) while `preemptEligible` was set during PREEMPT and the
finalization didn't clear it, the next round inherits the stale
list. The phase guard saves us, but it's a defense-in-depth gap.

**Quote** (`State.lua:240-247`):
```
-- NOTE: preemptEligible and pendingPreemptContract are NOT
-- transient. The HOST needs them to survive a /reload mid-
-- PHASE_PREEMPT — without persistence the host can't continue
-- the window and would soft-lock until the 60s AFK fires (and
-- even then, _FinalizePreempt wouldn't fire because pending-
-- PreemptContract is gone). Non-host clients overwrite their
-- copies on resync from the host (see N.SendResyncRes replay
-- block).
```

The TRANSIENT_FIELDS exclusion is intentional, but the round-boundary
clear in `ApplyStart` is missing. Verdict: **PARTIAL**.

---

### F-03 — `meldHoldUntil` wall-clock collision on /reload (UNDEFENDED-CLEARED)

`State.lua:108, 218-221, 800, 866-870`.

`meldHoldUntil` IS marked transient (line 221) per the comment "wall-
clock-based; restoring it after a /reload would either fire stale or
expire instantly." So `SaveSession` drops it. ApplyStart re-creates
the empty `{}` table (line 800). On /reload, `ApplyStart` doesn't run
again — so a /reload mid-trick-2 inside PHASE_PLAY restores with
`s.meldHoldUntil` undefined.

The UI guard (`UI.lua:2314`) reads `S.s.meldHoldUntil[seat]` after
checking `S.s.meldHoldUntil` is non-nil:
```
if not S.s.meldHoldUntil or not S.s.meldHoldUntil[seat] then
    return false
end
```

After /reload, `S.s.meldHoldUntil` is nil — UI safely returns false,
no crash. Verdict for crash safety: PASS.

But a different race exists: `S.ApplyTurn` sets
`s.meldHoldUntil[seat] = now + 5` (line 869). Within the 5-second
hold window, /reload causes the field to drop — UI immediately stops
rendering melds. On a fast /reload back, the player loses 5s of meld
display. Acceptable per the comment intent.

**However**: `ApplyTurn` line 867 reads `s.meldHoldUntil = s.meldHoldUntil
or {}` — defensive init. Good. But if a NON-/reload code path nils
`s.meldHoldUntil` mid-round (e.g. unintentional reset between the
ApplyStart and trick 2), no other code re-arms the table. ApplyStart
re-creates it; ApplyTurn's `or {}` re-creates it. Confirmed PASS for
the trick-2 path.

**Cross-round bleed**: `ApplyStart` re-creates `{}` so old timestamps
in the table don't leak into the new round. PASS.

Verdict: **UNDEFENDED-CLEARED** — works correctly under normal flow
but the wall-clock semantics mean a host /reload then immediate
return loses the 5-second visual cue. Acceptable.

---

### F-04 — `lastRoundResult` PARTIAL — leaks across NORMAL contract round-end

`State.lua:112, 237, 533, 1591-1595`. `Net.lua:2273, 2840, 3053`.

The TRANSIENT_FIELDS comment for `lastRoundResult` (lines 234-238):
> "Round-end display state: only meaningful within the round
>  they describe. After /reload they'd be stale and could
>  surface a previous round's banner unintentionally."

So /reload drops it. ApplyResyncSnapshot drops it (line 533). reset
drops it.

`S.ApplyRoundResult` SETS `s.lastRoundResult = result` (host-only,
line 1592). In `Net.lua` two paths explicitly nil it pre-set:
- `HostResolveTakweesh` line 2273: `S.s.lastRoundResult = nil`
- `_OnSWAOut` line 2840: `S.s.lastRoundResult = nil`
- `HostResolveSWA` line 3053: `S.s.lastRoundResult = nil`

The NORMAL round-end path (`_HostStepAfterTrick` at `Net.lua:1649-1714`)
calls `S.ApplyRoundResult(res)` BEFORE `S.ApplyRoundEnd`, which sets
the new lastRoundResult. So the new round's normal-path resolution
overwrites it.

**Gap**: a normal round-end followed by a TAKWEESH or SWA in the
NEXT round would not re-overwrite — but those paths do nil it before
setting `takweeshResult` / `swaResult`. Defense-in-depth holds.

**However**, between rounds (after `ApplyRoundEnd` of round R, before
`ApplyStart` of round R+1), the `lastRoundResult` field is what the
score banner reads. `ApplyStart` does NOT clear `lastRoundResult` —
a stale value from round R survives into round R+1's
PHASE_DEAL1 / BID phases until either:
- The round R+1 also finishes via NORMAL path (overwritten by
  ApplyRoundResult), OR
- A Takweesh/SWA in round R+1 explicitly nils it.

If the user opens the score-summary panel mid-bidding in round R+1,
they see ROUND R's result. UI surface is contained — no scoring
corruption.

`reset()` clears it (line 112). New game wipes via `ApplyLobby`
newGame branch which calls `S.Reset()` (Net.lua: see ApplyLobby
flow). Verdict: **PARTIAL** — survives ApplyStart for cosmetic banner.

---

### F-05 — `swaRequest` abandoned-round-end fork (PARTIAL)

`State.lua:116, 225-230, 528, 813`. `Net.lua:2144, 2491-2521,
2570-2575, 2727, 2754, 2862-3072`.

The TRANSIENT_FIELDS comment for `swaRequest` (lines 225-230) is
EXPLICITLY NOT transient:
> "If the HOST /reloads while opponents are voting, dropping the
>  request struct silently breaks the flow: clients still see
>  Accept/Deny buttons, but their MSG_SWA_RESP messages hit `if not
>  req` early-return and never resolve."

So `swaRequest` survives /reload. The PLAYER_LOGIN re-arm
(`WHEREDNGN.lua:270-292`) re-arms a 5s timer. Good.

`reset()` clears (line 116). ApplyStart clears (line 813).
ApplyResyncSnapshot clears (line 528). HostResolveTakweesh clears
(`Net.lua:2144`). HostResolveSWA implicitly resolves it.

**Gap**: if the round ends via NORMAL contract play
(`_HostStepAfterTrick` finishing trick 8 at `Net.lua:1649-1714`),
there's no `swaRequest = nil` clear. After ApplyRoundEnd sets phase
= SCORE, between SCORE and the next ApplyStart the field carries.

**Reachability**: the SWA permission window only opens during
PHASE_PLAY, and `_OnSWAReq` rejects messages outside PHASE_PLAY (line
2643). So no NEW request can arrive during SCORE. But an EXISTING
swaRequest set during PHASE_PLAY that didn't resolve before trick 8's
end would persist. Possible if:
- SWA window opens with bots auto-accepting; one human votes deny.
- Wait — deny clears `S.s.swaRequest = nil` immediately
  (`Net.lua:2754`).
- All accept → swaRequest cleared by the resolver.
- Timer expires → swaRequest cleared by the closure.

So under normal flow, `swaRequest` always resolves within PHASE_PLAY.
The unresolved-into-SCORE path is unreachable EXCEPT via direct
abuse: a malformed `MSG_SWA_REQ` injected during the SWA-resolve
window? No — `_OnSWAReq` line 2653 rejects when one's already
pending.

A more subtle path: trick 8 resolves, ApplyRoundEnd fires, phase →
SCORE. If a peer's `MSG_SWA_RESP` for a still-pending swaRequest is
in flight when trick 8 finishes (network arrives mid-resolve), the
host's `_OnSWAResp` (line 2735) would hit:
```
local req = S.s.swaRequest
if not req or req.caller ~= caller then return end
```
With swaRequest STILL set (because nobody cleared it on trick 8
resolution), the resp would attempt to apply against a finished
round. The phase guard in HostResolveSWA at 2864 (`if S.s.phase
~= K.PHASE_PLAY then return`) prevents the double-resolution. 
But the swaRequest field stays non-nil into SCORE → next round's
ApplyStart finally nils it.

Verdict: **PARTIAL** — relies on phase guards downstream rather than
explicit clear at the round-end source.

---

### F-06 — `swaDenied` wall-clock 3s closure on /reload (UNDEFENDED-CLEARED)

`State.lua:117, 232-233, 529, 814, 2620-2633, 2755-2768`.

`swaDenied` is marked transient (line 233): "Brief 'SWA denied' toast
struct, cleared by C_Timer 3 seconds after the deny. UI cue only."

reset clears. ApplyStart clears. ApplyResyncSnapshot clears. Two
C_Timer.After(3.0) closures clear it post-set:
- `Net.lua:2627`: caller-side responder path
- `Net.lua:2761`: host-side aggregator path

On /reload, swaDenied is dropped (transient) — toast disappears
immediately. Acceptable.

**Gap**: those C_Timer closures don't survive /reload. So if the
field were saved (it's not), the closure wouldn't fire post-reload.
Since it IS transient, the field is gone and there's nothing for the
ghost closure to operate on — `if S.s.swaDenied and ... == caller
then` no-ops. Safe.

Verdict: **UNDEFENDED-CLEARED** — works because of transient marking,
not because of explicit clearing logic.

---

### F-07 — `akaCalled` clears at trick end (CONFIRMED) — note D-RT-19 false-AKA path

`State.lua:110, 213-216, 524, 795, 1257, 1263, 1327, 1446`.

Cleared at:
- `reset()` line 110
- `ApplyStart` line 795 (round start)
- `ApplyResyncSnapshot` line 524
- `ApplyTrickEnd` line 1327 (trick boundary — the RIGHT semantic)
- `ApplyPlay` lines 1257, 1263 (false-AKA detection clears)

The instruction asked: "should clear at trick end, not just round
end". **Confirmed**: `ApplyTrickEnd` line 1327:
```
s.trick = { leadSuit = nil, plays = {} }
-- AKA banner only persists for the trick it was called on; clear it
-- so the next trick starts visually clean.
s.akaCalled = nil
```

This is the canonical clear. The round-end clears are belt-and-braces.

**No leak found**.

---

### F-08 — `playedCardsThisRound` clear timing (CONFIRMED)

`State.lua:111, 214-217, 343-353, 517, 791, 1246-1252, 1276-1277,
1322, 1369`.

The set is rebuilt deterministically from `s.tricks` and
`s.trick.plays` on resync (lines 343-353). Initialized in:
- `reset()` line 111 (empty table)
- `ApplyStart` line 791 (empty table — new round)
- `ApplyResyncSnapshot` line 517 (empty + replayed via tricks)

Additive writes during the round:
- `ApplyPlay` line 1277 keys card → true
- `ApplyTrickEnd` line 1322 belt-and-braces re-keys
- false-AKA-detection at line 1246 reads it

The instruction asked: "playedCardsThisRound clear timing". **Confirmed
correct**: the set is exactly the multiset of cards visible from the
round's trick log. No leak across round boundaries (ApplyStart wipes).
No leak across /reload (rebuilt from saved tricks).

---

### F-09 — `takweeshResult` clear post-Takweesh resolution mid-round (CONFIRMED)

`State.lua:114, 210-212, 526, 806, 2109, 2118, 2276, 2285`.

After Takweesh resolves, `takweeshResult` carries the banner struct
into PHASE_SCORE. It's intentional — the banner displays through the
score panel until the player clicks "Next Round," at which point
`HostStartRound` calls `S.ApplyStart(roundNum, dealer)` which nils
takweeshResult (line 806).

The instruction asked: "takweeshResult clear post-Takweesh resolution
mid-round". **Confirmed**: the field's lifecycle is precisely "set
by Takweesh resolver → display through SCORE → cleared at next
ApplyStart." No leak.

D-RT-17 found that a HOST /reload BETWEEN ApplyRoundEnd and
SendRound in HostResolveTakweesh (Net.lua:2264 → 2291) leaves the
host in PHASE_SCORE locally with takweeshResult set, but no
broadcast went out — soft-lock. That's a phase-level race, not a
takweeshResult clearing issue.

---

### F-10 — `swaResult` / `swaRequest` / `swaDenied` trick-end clear

`State.lua:115-117, 524-529, 805-814, 2491, 2836, 3048`.

The instruction asked: "swaResult / swaRequest / swaDenied trick-end
clear". `ApplyTrickEnd` at `State.lua:1300-1336` does NOT touch any
of these three fields.

This is **correct by design** — SWA banners and pending requests
should NOT clear at trick boundaries. They span tricks (request open
across opponents' deliberation, result displayed through SCORE,
denial toast for 3s wall-clock). So trick-end clearing would be
WRONG.

LocalSWA explicitly defends pre-set: line 2491 nils stale
`swaResult` before initiating a new claim. ApplyStart clears all
three at round boundaries. ApplyResyncSnapshot clears all three on
rejoin. **Confirmed correct**.

---

### F-11 — Redealing banner timer collisions (UNDEFENDED — see F-01)

`State.lua:142-158`. `Net.lua:1721-1781`.

Two timer loops can collide:
1. `ApplyRedealAnnouncement` arms a 3.5s self-clear at line 149.
2. `_HostRedeal` arms a 3.0s callback at line 1752.

The 3.5s callback checks `s.redealing.nextDealer == nextDealerSeat`
(line 152). If a SECOND `_HostRedeal` runs between t=0 and t=3.5,
calling `S.ApplyRedealAnnouncement(otherDealer)`, the first 3.5s
closure sees `s.redealing.nextDealer = otherDealer` (overwritten),
fails the `== nextDealerSeat` check, and no-ops. The new
`ApplyRedealAnnouncement` arms its own 3.5s. So banner clearing is
correct.

But the 3.0s `_HostRedeal` callback rotates dealer + ApplyStart at
line 1763-1765. The gen-token guard (line 1750-1753) protects
against `/baloot reset`-bumping `_redealGen`, but a second
`_HostRedeal` ALSO bumps `_redealGen` — so the first 3s closure
no-ops, the second's runs. The second has its OWN `nextDealer`
captured. But `S.s.dealer` may have already advanced if the FIRST
closure had time to run. (See F-01 for the narrow window.)

`paused` and `phase` guards inside the callback further mitigate.

**Verdict**: low-reachability race. Acceptable.

---

### F-12 — Mid-game game-end → reset race

`State.lua:1597-1607` (ApplyGameEnd), `Net.lua:1683-1712` (game-end
trigger), `State.lua:602-621` (HostBeginLobby calls reset).

The game-end transition path: `_HostStepAfterTrick` resolves trick 8,
calls `S.ApplyRoundEnd`, then if `totA >= s.target or totB >=
s.target` calls `S.ApplyGameEnd(winner)` and `N.SendGameEnd(winner)`.
ApplyGameEnd sets phase = PHASE_GAME_END.

Then if the user immediately `/baloot reset` or clicks "New Game" in
the lobby, `reset()` runs (or `S.HostBeginLobby` which calls reset).

`reset()` is comprehensive — clears all transients. `HostBeginLobby`
saves `localName`, calls `reset()`, restores `localName`,
`isHost=true`, `hostName`, `gameID`, `seats[1]`. Lines 602-621.

**Race**: `ApplyGameEnd` is idempotent (lines 1602-1604 — same
phase + same winner = no-op). But MSG_GAME_END can arrive at clients
from the host, who then immediately resets. The client's
`_OnGameEnd` would still apply, then a subsequent `MSG_LOBBY` from
the new host's `HostBeginLobby` would arrive. ApplyLobby line 711-727
detects `newGame` (different gameID OR phase==SCORE/GAME_END) and
calls `S.Reset()` preserving identity fields. **Looks correct**.

**Subtle gap**: between ApplyGameEnd and the next ApplyLobby, the
client carries `s.cumulative` from the just-finished game.
ApplyLobby's S.Reset() clears it (cumulative reset to {A=0,B=0} via
reset()). If the user OPENED the score panel between game-end and
new-lobby-broadcast, they'd see the final score — correct UX. PASS.

---

### F-13 — Saved session vs reset propagation timing

`State.lua:250-287` (SaveSession), `State.lua:289-375` (RestoreSession),
`WHEREDNGN.lua:130-296` (PLAYER_LOGIN), `WHEREDNGN.lua:298-303`
(PLAYER_LOGOUT).

PLAYER_LOGOUT calls SaveSession synchronously (line 302). SaveSession
checks phase: IDLE/LOBBY/GAME_END skip the save (line 252-256).
Otherwise dumps `s` minus TRANSIENT_FIELDS into
`WHEREDNGNDB.session`.

`reset()` itself sets `WHEREDNGNDB.lastGameID = nil` and
`WHEREDNGNDB.session = nil` (lines 122-125) — so a `/baloot reset`
followed by /reload will NOT restore.

**Race**: if `reset()` runs DURING PLAYER_LOGOUT (between
event-fire and SaveSession execution), there's no race because both
are on the same Lua main thread.

**Subtle gap**: `reset()` runs but PLAYER_LOGOUT fires LATER (e.g.
user presses /reload right after /baloot reset). Sequence:
1. `/baloot reset` → reset() → clears WHEREDNGNDB.session.
2. /reload triggers PLAYER_LOGOUT.
3. SaveSession runs: phase is IDLE → skip → no write.
4. PLAYER_LOGIN: RestoreSession runs: WHEREDNGNDB.session is nil → no
   restore.

**Correct**: /baloot reset across /reload is sticky.

But if the sequence is:
1. Mid-game state (PHASE_PLAY).
2. PLAYER_LOGOUT fires SaveSession → writes session.
3. PLAYER_LOGIN: RestoreSession runs → restores PHASE_PLAY.
4. User: /baloot reset → reset() → clears WHEREDNGNDB.session.
5. User: /reload again → PLAYER_LOGOUT → SaveSession → phase is IDLE
   → skip → no write.
6. PLAYER_LOGIN: no session → no restore.

**Correct**.

What if `reset()` doesn't fire but SaveSession is called with stale
state? Only PLAYER_LOGOUT triggers SaveSession; nothing else does.
So the only time stale state would write is if state mutation is
mid-flight when PLAYER_LOGOUT fires. WoW's logout flow is
synchronous, so the mutation either completes before SaveSession or
hasn't started.

**No race found**.

---

### F-14 — D-RT-17 verification: mid-Takweesh /reload race

`Net.lua:2127-2330` (HostResolveTakweesh).

The D-RT-17 finding identified the race: between
`S.ApplyRoundEnd(...)` at line 2264 and `N.SendRound(...)` at line
2291, a host /reload would persist phase=PHASE_SCORE locally with
updated cumulative, but no MSG_ROUND has been broadcast.

Verified by re-reading the code:
- Line 2264: `S.ApplyRoundEnd(addA, addB, totA, totB)` — sets phase
  = PHASE_SCORE, updates cumulative.
- Line 2273: `S.s.lastRoundResult = nil` (intentional clear).
- Line 2274: `S.s.trick = nil`.
- Lines 2276-2290: set `S.s.takweeshResult`.
- Line 2291: `N.SendRound(addA, addB, totA, totB)`.
- Line 2317: `broadcast(...)` for MSG_TAKWEESH_OUT.

PLAYER_LOGOUT mid-2264..2291 saves phase=SCORE, takweeshResult,
cumulative — all in WHEREDNGNDB.session (NOT transient).
`takweeshResult` IS transient (line 212), so it's dropped on save —
LOST.

PLAYER_LOGIN re-arm block (`WHEREDNGN.lua:157-217`) has NO branch
for `phase == PHASE_SCORE`. The host comes back with:
- phase = PHASE_SCORE (correct)
- cumulative = post-round (correct)
- takweeshResult = nil (DROPPED — UI shows generic "round done"
  banner instead of the Takweesh detail)
- Other clients still in PHASE_PLAY (no broadcast went out)

**Re-confirmed**: same finding D-RT-17. The takweeshResult-drop on
/reload is an additional mini-finding not in D-RT-17:

> The score banner on the host shows the GENERIC "round done"
> fallback instead of the Takweesh-detail (caller / offender / card
> / reason) — looks like an unrelated round-end to the host user
> until they realize MSG_ROUND never broadcast and clients are
> frozen.

This is a UI-degradation overlay on the soft-lock, but worth noting.

---

### F-15 — Related: SWA mid-resolve /reload

`Net.lua:2862-3072`. Same shape as Takweesh:
- Line 3058: `S.ApplyRoundEnd(addA, addB, totA, totB, sweepTeam,
  contractMade)`.
- Line 3059: `N.SendSWAOut(...)`.

Race window between 3058 and 3059. PLAYER_LOGOUT mid-window:
- phase = PHASE_SCORE saved.
- swaResult IS transient (line 224) → dropped.
- cumulative = post-round saved.
- contractMade flag pre-set on line 3048-3052 → swaResult is
  populated BEFORE ApplyRoundEnd. If logout fires BETWEEN line 3052
  set and line 3058 ApplyRoundEnd:
  - phase still PHASE_PLAY (ApplyRoundEnd not run).
  - swaResult set but DROPPED (transient).
  - cumulative pre-update.

PLAYER_LOGIN: phase=PLAY restored. swaResult=nil. swaRequest
restored (NOT transient — see F-05). PLAYER_LOGIN re-arm block
re-arms a fresh 5s SWA timer (`WHEREDNGN.lua:270-292`). The timer
fires → calls `HostResolveSWA(caller, hand)` AGAIN → re-runs the
entire scoring math. Could double-apply if the original ApplyRoundEnd
DID complete on the original host but the SaveSession already
captured pre-update state.

**Tighter window**: between `S.s.swaRequest = nil` at line 3057's
implicit (search exact) and `ApplyRoundEnd`. Actually, line 3057
isn't shown — let me re-quote:

```
3046:    local totB = (S.s.cumulative.B or 0) + addB
3047:
3048:    S.s.swaResult = {
3049:        caller = callerSeat, valid = valid,
3050:        contractMade = contractMade,
3051:        sweep = sweepTeam,
3052:    }
3053:    S.s.lastRoundResult = nil
3054:    S.s.trick = nil
3055:    -- Re-audit W1 + 4th-audit X4 fix: pass sweepTeam + contractMade
3056:    -- through so the BALOOT fanfare fires on host AND on remote
3057:    -- clients (MSG_SWA_OUT now carries the flags too).
3058:    S.ApplyRoundEnd(addA, addB, totA, totB, sweepTeam, contractMade)
3059:    N.SendSWAOut(callerSeat, valid, addA, addB, totA, totB,
3060:                 sweepTeam, contractMade)
```

`HostResolveSWA` does NOT clear `S.s.swaRequest = nil` inside its
body — the only swaRequest clears in the SWA resolve path are upstream
(in the timer / response handler that called HostResolveSWA). If
HostResolveSWA is reached via the timer path, the timer's closure
already set `S.s.swaRequest = nil` BEFORE calling HostResolveSWA
(Net.lua:2727, :2573). So at line 3058, swaRequest is nil.

**But**: If host /reloads BETWEEN line 3052 (swaResult set) and line
3058 (ApplyRoundEnd), then PLAYER_LOGOUT runs:
- phase still PHASE_PLAY.
- swaResult set BUT TRANSIENT — DROPPED.
- swaRequest already nil.
- cumulative still pre-update.

PLAYER_LOGIN restore: phase=PLAY, swaResult=nil, swaRequest=nil,
cumulative pre-update. PLAYER_LOGIN re-arm block at line 270 checks
`B.State.s.swaRequest and B.State.s.swaRequest.caller and
B.State.s.phase == K.PHASE_PLAY` — false (swaRequest=nil), so no
re-arm.

**Soft-lock identical to D-RT-17**: clients still see the SWA window
or have moved past, host is in PHASE_PLAY with no swaRequest to
resolve. Other clients' MSG_SWA_RESP broadcasts hit the host's
`_OnSWAResp` at line 2742-2743 which `if not req or req.caller ~=
caller then return` — silently dropped.

This is a NEW finding (related to D-RT-17 but on the SWA path):

**F-15 (NEW)**: Mid-`HostResolveSWA` /reload race window (lines
3052..3058) leaves host in PHASE_PLAY with swaResult dropped and
swaRequest already nilled. Clients are stuck waiting for either
MSG_SWA_OUT (never sent) or MSG_ROUND (never sent). PLAYER_LOGIN
re-arm has no recovery branch for "I was mid-resolve".

**Recommendation** (out of scope — code change forbidden): add a
`s.pendingSWAResolve` field set BEFORE line 3052 and cleared AFTER
line 3060, with a PLAYER_LOGIN re-arm branch.

---

## Summary of leaks worth addressing (informational only — no code change)

| ID | Severity | Field | Issue |
|---|---|---|---|
| F-01 | LOW | `redealing` | Double-`_HostRedeal` race during 3s window — narrow, ApplyStart clobbers |
| F-02 | LOW | `pendingPreemptContract` / `preemptEligible` | ApplyStart doesn't clear; defended by phase guards downstream |
| F-04 | LOW | `lastRoundResult` | Survives ApplyStart for cosmetic banner; UI may show stale R-1 result mid-R |
| F-05 | LOW | `swaRequest` | No explicit clear at trick-8 round-end; relies on phase guard |
| F-15 | **MEDIUM** | (host /reload mid-`HostResolveSWA`) | NEW finding — mirror of D-RT-17 on SWA resolve path; same soft-lock shape |

D-RT-17 already covers the Takweesh path; F-15 is the SWA-path twin.

---

## Cross-references

- D-RT-17 — Disconnect/Rejoin/Resync edge cases: covers the Takweesh
  /reload race at the same architectural layer.
- `audit_v0.9.0/05_m1_m2_timer_rearm.md`: PLAYER_LOGIN timer re-arm.
- `audit_v0.9.0/15_v091_l5_resync.md`: resync field clears.

## Files referenced
- `C:\CLAUDE\WHEREDNGN\State.lua` (reset, ApplyStart, ApplyRoundEnd,
  ApplyResyncSnapshot, ApplyTrickEnd, ApplyRedealAnnouncement,
  TRANSIENT_FIELDS, SaveSession, RestoreSession)
- `C:\CLAUDE\WHEREDNGN\Net.lua` (`_HostRedeal`, `HostStartRound`,
  `HostResolveTakweesh`, `HostResolveSWA`, `_OnSWAReq`, `_OnSWAResp`)
- `C:\CLAUDE\WHEREDNGN\WHEREDNGN.lua` (PLAYER_LOGIN re-arm,
  PLAYER_LOGOUT save)
- `C:\CLAUDE\WHEREDNGN\Slash.lua` (`/baloot reset`)
- `C:\CLAUDE\WHEREDNGN\UI.lua` (Reset button popup)
