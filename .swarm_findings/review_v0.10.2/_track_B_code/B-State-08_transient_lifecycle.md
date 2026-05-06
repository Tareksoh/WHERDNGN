# B-State-08 — Per-Round Transient Field Lifecycle Audit

Deep audit of the per-round transient list at `State.lua:103-119`,
verifying clear / restore / save coverage at every transition
boundary (`reset()`, `ApplyStart`, `ApplyTrickEnd`, `ApplyRoundEnd`,
`ApplyResyncSnapshot`, `SaveSession`, `ApplyLobby` newGame branch),
and re-validating D-RT-27's verdicts.

Cross-references: D-RT-27 (`_track_D_redteam`),
`audit_v0.9.0/05_m1_m2_timer_rearm.md`,
`audit_v0.9.0/15_v091_l5_resync.md`, D-RT-17 (Takweesh /reload race).

---

## Per-field verdict table

| Field                       | reset (l.103-119) | ApplyStart (752-823) | ApplyTrickEnd (1300-1336) | ApplyRoundEnd (1463-1585) | ApplyResyncSnapshot (490-540) | SaveSession (TRANSIENT_FIELDS, 191-248) | Verdict                       |
|-----------------------------|-------------------|----------------------|---------------------------|---------------------------|-------------------------------|----------------------------------------|-------------------------------|
| `redealing`                 | nil (l.103)       | nil (l.804)          | (n/a)                     | (n/a)                     | nil (l.530)                   | TRANSIENT (l.209)                       | **PARTIAL** — see F-01        |
| `lastTrick`                 | nil (l.104)       | nil (l.785)          | re-set (l.1316)           | (kept-by-design for peek) | nil (l.525)                   | TRANSIENT (l.239)                       | **CONFIRMED**                 |
| `peekedThisRound`           | nil (l.105)       | false (l.780)        | (n/a)                     | false (l.1469)            | (kept; not cleared)           | non-TRANSIENT (boolean)                 | **CONFIRMED**                 |
| `pendingPreemptContract`    | nil (l.106)       | (NOT cleared)        | (n/a)                     | (n/a)                     | nil (l.531)                   | non-TRANSIENT (intentional, l.240-247)  | **PARTIAL** — F-02            |
| `handRound`                 | nil (l.107)       | (kept; ApplyHand sets) | (n/a)                   | (n/a)                     | (kept)                        | non-TRANSIENT                           | **CONFIRMED** w/ guard        |
| `meldHoldUntil`             | nil (l.108)       | `{}` (l.800)         | (n/a)                     | (kept)                    | (NOT cleared)                 | TRANSIENT (l.221)                       | **UNDEFENDED-CLEARED** — F-03 |
| `localPlayedThisTrick`      | nil (l.109)       | (n/a; turn-driven)   | (cleared via ApplyTurn 848) | (n/a — turn=nil 1472)   | (n/a)                         | TRANSIENT (l.205)                       | **CONFIRMED**                 |
| `akaCalled`                 | nil (l.110)       | nil (l.795)          | nil (l.1327, canonical)   | (kept)                    | nil (l.524)                   | TRANSIENT (l.216)                       | **CONFIRMED**                 |
| `playedCardsThisRound`      | `{}` (l.111)      | `{}` (l.791)         | additive (l.1322)         | (kept)                    | `{}` rebuilt (l.343-353/517)  | TRANSIENT (l.217)                       | **CONFIRMED**                 |
| `lastRoundResult`           | nil (l.112)       | (NOT cleared)        | (n/a)                     | (kept)                    | nil (l.533)                   | TRANSIENT (l.237)                       | **PARTIAL** — F-04            |
| `lastRoundDelta`            | nil (l.113)       | (NOT cleared)        | (n/a)                     | overwrite (l.1467)        | nil (l.534)                   | TRANSIENT (l.238)                       | **CONFIRMED**                 |
| `takweeshResult`            | nil (l.114)       | nil (l.806)          | (n/a)                     | (kept-by-design SCORE banner) | nil (l.526)                | TRANSIENT (l.212)                       | **CONFIRMED**                 |
| `swaResult`                 | nil (l.115)       | nil (l.807)          | (n/a)                     | (kept; banner)            | nil (l.527)                   | TRANSIENT (l.224)                       | **CONFIRMED**                 |
| `swaRequest`                | nil (l.116)       | nil (l.813)          | (n/a)                     | (NOT cleared at trick 8)  | nil (l.528)                   | non-TRANSIENT (intentional, l.225-230)  | **PARTIAL** — F-05            |
| `swaDenied`                 | nil (l.117)       | nil (l.814)          | (n/a)                     | (kept; 3s C_Timer)        | nil (l.529)                   | TRANSIENT (l.233)                       | **UNDEFENDED-CLEARED** — F-06 |
| `pendingHost`               | nil (l.118)       | (n/a)                | (n/a)                     | (n/a)                     | (n/a)                         | TRANSIENT (l.192)                       | **CONFIRMED**                 |
| `hostDeckRemainder`         | nil (l.119)       | (n/a; HostDealInitial sets) | (n/a)              | (n/a)                     | (n/a)                         | non-TRANSIENT (intentional, l.193-198)  | **CONFIRMED**                 |
| `preemptEligible` *(l.61)*  | nil               | (NOT cleared)        | (n/a)                     | (n/a)                     | nil (l.532)                   | non-TRANSIENT (intentional, l.240-247)  | **PARTIAL** — F-02            |

D-RT-27 classifications **all re-confirmed**. The matrix above
expands the row count from 17 to 18 (adds `preemptEligible` as its
own row — D-RT-27 lumped it with `pendingPreemptContract`).

---

## Save/restore alignment with TRANSIENT_FIELDS

The TRANSIENT_FIELDS set must include exactly the fields whose
clear-paths span /reload (i.e. timer-cleared, wall-clock-based, or
UI-only). The reset list at `State.lua:103-119` enumerates all
per-round fields; `TRANSIENT_FIELDS` (l.191-248) is a strict subset.
Verified subset relationship:

```
reset list: redealing, lastTrick, peekedThisRound,
            pendingPreemptContract, handRound, meldHoldUntil,
            localPlayedThisTrick, akaCalled,
            playedCardsThisRound, lastRoundResult, lastRoundDelta,
            takweeshResult, swaResult, swaRequest, swaDenied,
            pendingHost, hostDeckRemainder

TRANSIENT_FIELDS: pendingHost, localPlayedThisTrick, redealing,
                  takweeshResult, akaCalled, playedCardsThisRound,
                  meldHoldUntil, swaResult, swaDenied,
                  lastRoundResult, lastRoundDelta, lastTrick

Excluded (intentionally NOT transient):
  • swaRequest         — host needs to keep voting state across /reload (l.225-230)
  • pendingPreemptContract / preemptEligible — host keeps PREEMPT state (l.240-247)
  • hostDeckRemainder  — must persist with hostHands across DEAL phases (l.193-198)
  • peekedThisRound    — boolean; restoring true is OK (peek lockout reasonable)
  • handRound          — must persist so a /reload mid-deal doesn't wipe new hand
```

Alignment looks **correct by construction**. No misalignments where
a field is cleared by reset but persisted incorrectly across /reload.

---

## F-01 — `redealing` race window in `_HostRedeal` 3s timer (LOW)

`State.lua:103, 137-158, 530, 804`. `Net.lua:1721-1781`.

**D-RT-27 verdict re-confirmed.** Two timer loops (3.5s self-clear in
`ApplyRedealAnnouncement`, 3.0s callback in `_HostRedeal`) can
collide on a double-`_HostRedeal` invocation within the 3s window.
Gen-token guard at `Net.lua:1750-1753` invalidates the first
closure correctly when re-entered before fire, but if the first 3s
closure has already begun executing (rotated dealer + ApplyStart
in flight) when the second `_HostRedeal` arrives, the dealer can
double-rotate.

ApplyStart's `s.redealing = nil` (l.804) clears the banner cleanly,
but the dealer rotation race remains. Mitigations: `paused` and
`phase` guards inside the 3s callback.

**Severity**: LOW. Real-world reachability requires rapid
back-to-back redeal triggers (all-pass + Kawesh from new dealer
within 3s, plus the first 3s callback already executing).

```lua
-- State.lua:803-804
s.phase        = K.PHASE_DEAL1
-- A redeal announcement banner (all-pass) is dismissed by the
-- arrival of a real ApplyStart for the new round.
s.redealing    = nil
```

```lua
-- Net.lua:1762-1765
    if S.s.paused then return end
    S.s.dealer = nextDealer
    if B.Bot and B.Bot.ResetMemory then B.Bot.ResetMemory() end
    S.ApplyStart(S.s.roundNumber, nextDealer)
```

---

## F-02 — `pendingPreemptContract` / `preemptEligible` ApplyStart gap (LOW)

`State.lua:61, 106, 240-247, 531-532, 1900-1920`.

**D-RT-27 verdict re-confirmed.** Both fields are intentionally
NOT transient (host needs them to survive /reload mid-PHASE_PREEMPT
— see comment l.240-247). But `ApplyStart` does NOT clear either
field. If round R ends in any non-PREEMPT path (normal contract,
takweesh, SWA) while preempt fields were set during the prior
PHASE_PREEMPT but not finalized cleanly, the next round inherits
stale values.

The phase-guard saves us in practice: `ApplyPreempt` and
`ApplyPreemptPass` both gate on `s.preemptEligible` non-nil, and
`_FinalizePreempt` gates on `S.s.phase == K.PHASE_PREEMPT`. A
fresh ApplyStart sets phase=PHASE_DEAL1 so finalize would no-op.

```lua
-- State.lua:1900-1907
function S.ApplyPreempt(seat)
    if not s.preemptEligible then return end
    ...
    s.preemptEligible = nil
```

```lua
-- State.lua:1909-1920 (handles partial pass-list cleanup)
function S.ApplyPreemptPass(seat)
    if not s.preemptEligible then return end
    for i, s2 in ipairs(s.preemptEligible) do
        if s2 == seat then table.remove(s.preemptEligible, i); break end
    end
    if #s.preemptEligible == 0 then
        s.preemptEligible = nil
```

**Severity**: LOW. Defense-in-depth gap; phase guards catch it.

---

## F-03 — `meldHoldUntil` wall-clock collision on /reload (UNDEFENDED-CLEARED)

`State.lua:108, 218-221, 800, 866-870`.

**D-RT-27 verdict re-confirmed.** `meldHoldUntil` is transient
(l.221: "wall-clock-based; restoring it after a /reload would
either fire stale or expire instantly"). `SaveSession` drops it.
ApplyStart re-creates `{}` (l.800). Mid-trick-2 /reload restores
with `s.meldHoldUntil = nil`.

UI guard at `UI.lua:2314` checks `not S.s.meldHoldUntil or not
S.s.meldHoldUntil[seat]` so no crash. The 5s hold is lost across
/reload — acceptable per the field's intent comment.

**Cross-round bleed check**: ApplyStart re-creates `{}` so old
timestamps don't leak into the new round. PASS.

**Resync gap re-flagged**: `ApplyResyncSnapshot` does NOT clear
`meldHoldUntil`. A non-host rejoiner hitting a host that's currently
holding a non-empty meld table would inherit nothing (the field
isn't snapshotted). But if the rejoiner had a pre-/reload
`meldHoldUntil` carrying stale keys, those leak across the resync
because there's no clear there. Severity LOW — wall-clock
re-evaluates each frame, stale timestamps are filtered as
`now > t` immediately on UI render.

**Severity**: LOW. Acceptable per design.

---

## F-04 — `lastRoundResult` survives ApplyStart for cosmetic banner (PARTIAL)

`State.lua:112, 234-238, 533, 1591-1595`. `Net.lua:2273, 2840, 3053`.

**D-RT-27 verdict re-confirmed.** `lastRoundResult` is transient
(l.237). `reset()` and `ApplyResyncSnapshot` clear. But
**`ApplyStart` does NOT clear it** — between `ApplyRoundEnd` of
round R (which sets it via `S.ApplyRoundResult(res)` upstream) and
`ApplyStart` of round R+1, the field carries.

In the new round, three Net.lua paths nil it pre-set:

```lua
Net.lua:2273:    S.s.lastRoundResult = nil   -- HostResolveTakweesh
Net.lua:2840:    S.s.lastRoundResult = nil   -- _OnSWAOut
Net.lua:3053:    S.s.lastRoundResult = nil   -- HostResolveSWA
```

If round R+1 ends via NORMAL contract play (`_HostStepAfterTrick`
finishing trick 8), `S.ApplyRoundResult(res)` overwrites cleanly.
If R+1 ends via Takweesh/SWA, the pre-nil at 2273/3053 fires.

**Gap**: between PHASE_DEAL1/BID/PLAY of R+1 (after ApplyStart)
and the new round-end, opening the score-summary panel reads
ROUND R's `lastRoundResult`. Cosmetic only; no scoring corruption.

**Severity**: LOW.

---

## F-05 — `swaRequest` no explicit clear at trick-8 round-end (PARTIAL)

`State.lua:116, 225-230, 528, 813`. `Net.lua:2144, 2491-2521,
2570-2575, 2727, 2754, 2862-3072`.

**D-RT-27 verdict re-confirmed.** `swaRequest` is intentionally NOT
transient (l.225-230). The clear sites are exhaustively:

```
State.lua:813   -- ApplyStart
Net.lua:2144    -- HostResolveTakweesh (pre-clear)
Net.lua:2562    -- DENY collation, immediate clear
Net.lua:2573    -- 5s timer expired, deny path
Net.lua:2619    -- caller-side responder DENY
Net.lua:2712    -- aggregator final-vote ACCEPT
Net.lua:2727    -- aggregator timer expiry ACCEPT
Net.lua:2754    -- caller-side responder DENY toast
Net.lua:2804    -- HostResolveTakweesh secondary
Net.lua:4065    -- (unrelated; teardown path)
```

**No clear at trick-8 normal round-end** (`_HostStepAfterTrick`).
Reachability of stale `swaRequest` into PHASE_SCORE: the SWA window
only opens during PHASE_PLAY, and `_OnSWAReq` rejects messages
outside PHASE_PLAY (Net.lua:2643). New requests can't arrive
during SCORE. An EXISTING swaRequest unresolved before trick 8
would persist through ApplyRoundEnd into PHASE_SCORE.

The unresolved-into-SCORE path is unreachable except via in-flight
`MSG_SWA_RESP` whose `_OnSWAResp` body sees swaRequest set (no
clear at trick 8) — but the phase guard in HostResolveSWA at
Net.lua:2864 (`if S.s.phase ~= K.PHASE_PLAY then return`) prevents
double-resolution.

**Severity**: LOW. Defense-in-depth issue; relies on phase guards
downstream rather than explicit clear at the round-end source.

---

## F-06 — `swaDenied` wall-clock 3s closure on /reload (UNDEFENDED-CLEARED)

`State.lua:117, 232-233, 529, 814`. `Net.lua:2627, 2761`.

**D-RT-27 verdict re-confirmed.** `swaDenied` is transient (l.233).
Two `C_Timer.After(3.0)` closures clear it post-set. On /reload,
field is dropped → toast disappears immediately. The C_Timer
closures don't survive /reload but the field is gone, so the ghost
closure no-ops on `if S.s.swaDenied and ... == caller then`.

**Severity**: LOW. Works because of transient marking, not because
of explicit clearing logic.

---

## F-07 — `akaCalled` cleared at trick end (CONFIRMED)

`State.lua:110, 213-216, 524, 795, 1257, 1263, 1327, 1446`.

`ApplyTrickEnd:1327` is the **canonical clear** — the AKA banner
should clear at trick end (the trick it was called on), not just
round end. Confirmed:

```lua
-- State.lua:1324-1327
s.trick = { leadSuit = nil, plays = {} }
-- AKA banner only persists for the trick it was called on; clear it
-- so the next trick starts visually clean.
s.akaCalled = nil
```

Belt-and-braces clears at reset, ApplyStart, ApplyResyncSnapshot,
and false-AKA detection in `ApplyPlay` (1257, 1263).

**No leak**.

---

## F-08 — `playedCardsThisRound` reconstructed from tricks (CONFIRMED)

`State.lua:111, 214-217, 343-353, 517, 791, 1246-1252, 1276-1277,
1322, 1369`.

The set is rebuilt deterministically on resync from `s.tricks`
(plus `s.trick.plays`). All initialization paths reset to `{}`.
Trick-end re-keys belt-and-braces. False-AKA detection reads it.

```lua
-- State.lua:343-353 (RestoreSession rebuild)
s.playedCardsThisRound = {}
for _, tr in ipairs(s.tricks or {}) do
    for _, p in ipairs(tr.plays or {}) do
        s.playedCardsThisRound[p.card] = true
    end
end
if s.trick and s.trick.plays then
    for _, p in ipairs(s.trick.plays) do
        s.playedCardsThisRound[p.card] = true
    end
end
```

No leak.

---

## F-09 — `takweeshResult` lifecycle (CONFIRMED)

`State.lua:114, 210-212, 526, 806, 2109, 2118, 2276, 2285`.

Lifecycle: set by Takweesh resolver → display through SCORE →
cleared at next `ApplyStart`. Mid-Takweesh /reload (D-RT-17)
drops the banner due to TRANSIENT marking — degrades to generic
"round done" UI but no double-resolution.

No leak.

---

## F-10 — SWA banners trick-end behavior (CORRECT BY DESIGN)

`State.lua:115-117, 524-529, 805-814`. `Net.lua:2491, 2836, 3048`.

`ApplyTrickEnd` does NOT touch `swaResult`/`swaRequest`/`swaDenied`.
**Correct by design**: SWA banners span tricks (request open across
opponents' deliberation, result displayed through SCORE, denial
toast for 3s wall-clock). Trick-end clearing would be wrong.

---

## F-11 — Multi-game session-overwrite at IDLE/LOBBY/GAME_END

`State.lua:122-125, 252-256, 690-727`.

`SaveSession` skips when `phase == PHASE_IDLE | PHASE_LOBBY |
PHASE_GAME_END` — no save during passive phases. `reset()`
explicitly nils `WHEREDNGNDB.lastGameID` and `WHEREDNGNDB.session`
(l.122-125), so `/baloot reset` is sticky across /reload.

`ApplyLobby` newGame branch at l.711-727 detects different gameID
(or phase==SCORE/GAME_END) and calls `S.Reset()`. Identity fields
(localName, target, teamNames, peerVersions, hostName,
pendingHost) saved/restored around the reset:

```lua
-- State.lua:713-727
if newGame then
    local savedName   = s.localName
    local savedTarget = s.target
    local savedNames  = s.teamNames
    local savedPeers  = s.peerVersions
    local savedHost   = s.hostName
    local savedPend   = s.pendingHost
    S.Reset()
    s.localName     = savedName
    s.target        = savedTarget or s.target
    s.teamNames     = savedNames or s.teamNames
    s.peerVersions  = savedPeers or {}
    s.hostName      = savedHost
    s.pendingHost   = savedPend
end
```

All transient round fields cleared by `S.Reset()`. **No
multi-game state bleed**.

---

## F-12 — Phase machine integrity if reset misses a field

`State.lua:103-119`.

The reset list is exhaustively cross-checked against all reads:
no field is consumed by the phase machine that isn't in the reset
list. The `peekedThisRound`, `redealing`, `takweeshResult`,
`swaResult`, `swaRequest`, `swaDenied`, and `lastRoundResult`
fields all gate UI states; their reset clears prevent stale UI on
new rounds.

`pendingHost` is consumed only in lobby join flow; cleared in
ApplyLobby (l.749) and reset.

`hostDeckRemainder` paired with `hostHands` — cleared in reset
(`s.hostHands = nil` at ApplyStart but hostHands is also cleared
in ApplyStart at l.771) — the Net.lua HostDealInitial sets both
together. **No phase-machine integrity gap**.

---

## F-13 — `pendingPreemptContract` writer location

`State.lua:106, 240-247, 1900-1920`. `Net.lua:_BeginPreempt /
_FinalizePreempt`.

**Verified**: writer is `Net.lua:_BeginPreempt` (per D-RT-27 l.117).
Field stays set until `_FinalizePreempt` clears it. ApplyStart
gap remains (F-02). Reachability: low — only mid-PHASE_PREEMPT
abandonment triggers the leak; phase guard saves us downstream.

---

## F-14 — Re-confirmation of D-RT-17 (Takweesh /reload)

`Net.lua:2127-2330`.

Re-verified: between `S.ApplyRoundEnd(...)` at line 2264 and
`N.SendRound(...)` at line 2291, host /reload would persist
phase=PHASE_SCORE locally with updated cumulative, but no
MSG_ROUND broadcast. `takweeshResult` IS transient (l.212), so
dropped on save → host shows generic "round done" instead of
Takweesh detail. Clients still in PHASE_PLAY (no broadcast went
out). Soft-lock.

PLAYER_LOGIN re-arm block at `WHEREDNGN.lua:157-292` has NO
branch for `phase == PHASE_SCORE`. **D-RT-17 verdict stands**.

---

## F-15 — **NEW**: Mid-`HostResolveSWA` /reload race (MEDIUM)

`Net.lua:3045-3072`. Mirror of D-RT-17 on the SWA path.

Quoting the critical region:

```lua
-- Net.lua:3045-3060
local totA = (S.s.cumulative.A or 0) + addA
local totB = (S.s.cumulative.B or 0) + addB

S.s.swaResult = {
    caller = callerSeat, valid = valid,
    contractMade = contractMade,
    sweep = sweepTeam,
}
S.s.lastRoundResult = nil
S.s.trick = nil
-- Re-audit W1 + 4th-audit X4 fix: pass sweepTeam + contractMade
-- through so the BALOOT fanfare fires on host AND on remote
-- clients (MSG_SWA_OUT now carries the flags too).
S.ApplyRoundEnd(addA, addB, totA, totB, sweepTeam, contractMade)
N.SendSWAOut(callerSeat, valid, addA, addB, totA, totB,
             sweepTeam, contractMade)
```

`HostResolveSWA` is reached via three call sites; in all three the
upstream timer/response handler nils `S.s.swaRequest` BEFORE
calling `HostResolveSWA` (Net.lua:2562, 2573, 2712, 2727). At
line 3058, swaRequest is nil.

**Race window**: host /reloads BETWEEN line 3052 (swaResult set)
and line 3058 (ApplyRoundEnd). PLAYER_LOGOUT runs:
- phase still PHASE_PLAY (ApplyRoundEnd not run).
- swaResult set BUT TRANSIENT → DROPPED.
- swaRequest already nil.
- cumulative still pre-update.

PLAYER_LOGIN restore: phase=PLAY, swaResult=nil, swaRequest=nil,
cumulative pre-update. PLAYER_LOGIN re-arm block at
`WHEREDNGN.lua:270-292` checks `B.State.s.swaRequest and
B.State.s.swaRequest.caller and B.State.s.phase == K.PHASE_PLAY`
→ false (swaRequest=nil), **no re-arm**.

**Soft-lock identical shape to D-RT-17**: clients still see the
SWA window or have moved past, host is in PHASE_PLAY with no
swaRequest to resolve. Other clients' MSG_SWA_RESP messages hit
host's `_OnSWAResp` at line 2742-2743:

```lua
local req = S.s.swaRequest
if not req or req.caller ~= caller then return end
```

With `req == nil`, all responses silently dropped.

**Tighter race**: window is just 6 lines (3053..3058) — narrow
but not negligible given any user-action-driven /reload at this
moment.

**Severity**: **MEDIUM** — same shape as D-RT-17, same impact
class (host soft-lock requires manual `/baloot reset`). Recovery:
no PLAYER_LOGIN branch covers it.

**Recommendation** (out of scope — code change forbidden): add
`s.pendingSWAResolve = { caller, hand }` BEFORE l.3052 (or set
right at start of HostResolveSWA after the early-return guards),
clear AFTER l.3060. Add a PLAYER_LOGIN re-arm branch that detects
the field and re-invokes HostResolveSWA. Same approach for
HostResolveTakweesh (D-RT-17).

---

## Summary of leaks

| ID    | Severity | Field / Issue                                                        |
|-------|----------|----------------------------------------------------------------------|
| F-01  | LOW      | `redealing` double-`_HostRedeal` race within 3s window               |
| F-02  | LOW      | `pendingPreemptContract` / `preemptEligible` ApplyStart gap          |
| F-03  | LOW      | `meldHoldUntil` wall-clock loss on /reload (acceptable per design)   |
| F-04  | LOW      | `lastRoundResult` survives ApplyStart; cosmetic banner stale         |
| F-05  | LOW      | `swaRequest` no explicit clear at trick-8 round-end                  |
| F-06  | LOW      | `swaDenied` wall-clock loss on /reload (acceptable per design)       |
| F-15  | **MEDIUM** | **NEW**: Mid-`HostResolveSWA` /reload race (mirror of D-RT-17)    |

D-RT-27 categorizations all re-confirmed. F-15 is the SWA-path
twin of D-RT-17's Takweesh-path finding.

---

## Files referenced

- `C:\CLAUDE\WHEREDNGN\State.lua` (reset l.31-126, ApplyStart l.752-823,
  ApplyTrickEnd l.1300-1336, ApplyRoundEnd l.1463-1585, ApplyResyncSnapshot
  l.388-540, TRANSIENT_FIELDS l.191-248, SaveSession l.250-287,
  RestoreSession l.289-375, ApplyLobby l.690-750, ApplyTurn l.841-887,
  ApplyRedealAnnouncement l.137-158, ApplyGameEnd l.1597-1607,
  ApplyPreempt l.1900-1907, ApplyPreemptPass l.1909-1920)
- `C:\CLAUDE\WHEREDNGN\Net.lua` (HostStartRound l.1785-1824,
  HostResolveSWA l.2862-3072, HostResolveTakweesh l.2127-2330,
  swaRequest clear sites l.2144/2562/2573/2619/2712/2727/2754/2804,
  _HostRedeal l.1721-1781)
- `C:\CLAUDE\WHEREDNGN\WHEREDNGN.lua` (PLAYER_LOGIN re-arm l.130-296,
  swaRequest re-arm l.270-292, PLAYER_LOGOUT save l.298-303)
- `C:\CLAUDE\WHEREDNGN\.swarm_findings\review_v0.10.2\_track_D_redteam\D-RT-27_reset_redeal.md`
