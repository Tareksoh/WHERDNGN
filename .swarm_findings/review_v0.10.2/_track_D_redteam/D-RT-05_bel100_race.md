# D-RT-05: Bel-100 score-split rule — red-team v0.10.0 R1

**Target:** v0.10.0 R1's `R.CanBel` rewrite to score-split,
role-irrelevant: `caller.cum ≤ 100 AND opposite.cum ≥ 101`.

**Files inspected:**

- `C:\CLAUDE\WHEREDNGN\Rules.lua` 480–561 (`R.CanBel`)
- `C:\CLAUDE\WHEREDNGN\Net.lua` 60–83 (`N._SunBelAllowed`),
  860–913 (`N._OnDouble`), 1843–1871 (`N.LocalDouble`),
  2071–2314 (Takweesh resolution)
- `C:\CLAUDE\WHEREDNGN\Bot.lua` 3431–3543 (`Bot.PickDouble`)
- `C:\CLAUDE\WHEREDNGN\UI.lua` 1755–1790 (Bel button render)
- `C:\CLAUDE\WHEREDNGN\State.lua` 1463–1466 (`S.ApplyRoundEnd`)
- `C:\CLAUDE\WHEREDNGN\Constants.lua` 329 (`K.SUN_BEL_CUMULATIVE_GATE = 100`)
- `C:\CLAUDE\WHEREDNGN\tests\test_rules.lua` 767–847 (Section N)
- `C:\CLAUDE\WHEREDNGN\.swarm_findings\review_v0.10.2\_track_B_code\B-Rules-05_canBel.md`
- `C:\CLAUDE\WHEREDNGN\.swarm_findings\review_v0.10.0\_phase2_xref\reaudit_R1_bel100.md`

**Method:** read all five call-sites; trace control flow through
PHASE_DOUBLE entry → UI button render → host gate → bot decision;
walk integer boundary cases, tied-cumulative cases, nil-arg cases,
authority gate vs predicate gate, race scenarios between local/host.

---

## Scenario 1 — Tied 100/100 cumulative (boundary)

**Verdict:** CORRECT but NOT EXPLICITLY TESTED. Quiet documentation
gap.

**Repro:**

State after some round: `S.s.cumulative = { A = 100, B = 100 }`.
Sun contract enters PHASE_DOUBLE. Either team queries `R.CanBel`.

`Rules.lua:558-559`:

```
if mine     >  K.SUN_BEL_CUMULATIVE_GATE then return false end
if otherCum <= K.SUN_BEL_CUMULATIVE_GATE then return false end
```

For team A: `mine=100`, `100 > 100` is false (no return);
`otherCum=100`, `100 <= 100` is true → returns **false**. Same for
team B by symmetry. Neither team may Bel.

This matches the Saudi rule per PDF 07 line 12:
`بالصن : اليفتح الدبل ال بعد العدد 100` — "the Bel does not open
until after the count 100." At 100/100 nobody has crossed.

**However**, Section N has no explicit `{ A=100, B=100 }` fixture.
The semantics are correct by inference (covered by the asymmetric
100/0 cases) but not pinned. A future refactor that flipped one
inequality from `<=` to `<` would silently flip the 100/100 verdict
to "either team may Bel" without breaking any current test.

**Recommendation:** Add to Section N before line 805:

```lua
assertEq(R.CanBel("A", sun_bidA, { A = 100, B = 100 }), false,
         "Sun: 100/100 → no team has crossed gate, neither can Bel")
assertEq(R.CanBel("B", sun_bidA, { A = 100, B = 100 }), false,
         "Sun: 100/100 mirror → no team has crossed gate")
```

Severity: **LOW** (test gap, not a code bug).

---

## Scenario 2 — UI/wire authority mismatch on bidder-trailing case (the headline R1 fix)

**Verdict:** **MAJOR DIVERGENCE.** R1 advertised the bidder-trailing
fix, but `Net._OnDouble`/`Net.LocalDouble`/`UI.lua` all gate on
`seat == (bidder % 4) + 1` — i.e., only the seat to the bidder's
right may Bel. That's always a defender seat. The bidder team
**cannot route a Bel through the wire** even when `R.CanBel` says
yes.

**Repro:**

- `S.s.contract = { type = K.BID_SUN, bidder = 2 }` (B bid Sun)
- `S.s.cumulative = { A = 130, B = 60 }` (A ahead, B trailing)
- Phase = `PHASE_DOUBLE`.

Predicate result: `R.CanBel("B", contract, cum)` → `60 > 100` false,
`130 <= 100` false → **true**. Per the R1 fix, team B (the bidder
team, trailing) is supposed to be able to Bel.

But `Net.LocalDouble` (Net.lua:1847-1848):

```
local b = S.s.contract.bidder
if S.s.localSeat ~= (b % 4) + 1 then return end
```

`(2 % 4) + 1 = 3`. Seat 3 is on team A. No team-B seat satisfies
this gate. Even if a B-seat player tried to fire `LocalDouble()`
locally, it returns silently before reaching `R.CanBel`.

`Net._OnDouble` (Net.lua:867-868): same restriction (`eligibleSeat
= (S.s.contract.bidder % 4) + 1`). A network-injected `MSG_DOUBLE`
from a B-seat would also be silently rejected.

`UI.lua` Bel buttons render only inside the `nextSeat == localSeat`
branch (UI.lua:1758-1759), so the bidder team never sees the Bel
button at all.

**Consequence:** The R1 fix's headline scenario — "trailing bidder
team may Bel" — does not surface in live play. The unit test at
`test_rules.lua:815-816` asserts `R.CanBel("A", sun_bidA, { A=50,
B=101 }) == true`, but no integration test wires this through
`LocalDouble`/`_OnDouble`/UI. Effective behavior matches v0.9.2
(role-anchored): bidder team cannot Bel its own contract regardless
of score position.

This is **not a regression introduced by R1** — the
`(bidder % 4) + 1` restriction predates the score-split rewrite.
But it is a quiet semantic mismatch between the predicate (correct,
score-split) and the live integration path (effectively
defender-only). The R1 changelog and reaudit document do not
acknowledge this.

**Recommendation:** Either (a) extend the wire/UI to allow any seat
on the trailing team — broaden `LocalDouble`/`_OnDouble` to admit
the partner of the bidder when bidder team is trailing; or (b)
document explicitly in `R.CanBel`'s comment block that the wire
is defender-only and the bidder-trailing predicate result is
effectively unreachable. Option (a) is the principled fix; option
(b) is a one-line documentation paste.

Severity: **MEDIUM**. Captures the only edge case the R1 fix was
advertised for, then doesn't deliver it.

---

## Scenario 3 — `_SunBelAllowed` skip-phase decision uses A-favoring tiebreak

**Verdict:** SUBTLE CORRECTNESS QUIRK. Consequence is correct,
reasoning is fragile.

**Repro:**

`Net.lua:79`:

```
local trailingTeam = (cumA <= cumB) and "A" or "B"
return R.CanBel(trailingTeam, ...)
```

Tiebreak `cumA <= cumB`: team A wins ties (cumA == cumB → trailing
= "A"). Trace cases:

| cumA | cumB | trailing | `R.CanBel(trailing, sun, cum)` | Saudi rule expected |
|------|------|----------|----|----|
| 50   | 50   | A        | A's `mine=50 ≤100`, `other=50 ≤100` → **false** | NO (no team crossed) |
| 100  | 100  | A        | A's `mine=100 ≤100`, `other=100 ≤100` → **false** | NO |
| 50   | 200  | A        | A's `mine=50 ≤100`, `other=200 ≥101` → **true** | YES |
| 200  | 50   | B        | B's `mine=50 ≤100`, `other=200 ≥101` → **true** | YES |
| 100  | 101  | A        | A's `mine=100 ≤100`, `other=101 ≥101` → **true** | YES |
| 101  | 101  | A        | A's `mine=101 >100` → **false** | NO (neither trailing) |

All cases match the Saudi rule. So the predicate is **functionally
correct**. But the proof relies on the "either team eligible iff
that team is the trailer, and the gate is mutually exclusive"
property in Net.lua:73-74. The reasoning is right, but it's two
layers deep and unobvious — the comment on Net.lua:79 only mentions
"trailing team" without explaining why ties cleanly default to A.

The fragile part: if either of the inequalities in `R.CanBel` ever
flipped to a strict version while preserving the "≤100/≥101" pair,
this delegation would break for the tied-not-eligible cases. E.g.,
if someone "tightened" the gate to `mine < 100` (strict), the
50/50 case would still return false (50 < 100 true, but 50 ≤ 100
true → otherCum check fails), but **101/101 would change**: A's
`mine=101`, `101 < 100` false, `otherCum=101 ≥101` true → would
return true. That would be wrong (neither team is below the gate)
and the inferred-from-trailing-team logic would silently propagate
the bug.

**Recommendation:** Either:

1. Add a 50/50 + 100/100 + 101/101 fixture to Section N to pin the
   reasoning (so a future flip catches the test).
2. Inline the dual-team check in `_SunBelAllowed` directly rather
   than picking-trailer-then-delegating, e.g.:

   ```lua
   if cumA <= 100 and cumB >= 101 then return true end
   if cumB <= 100 and cumA >= 101 then return true end
   return false
   ```

   This makes the predicate's intent surface-visible and removes
   the inferred-tiebreak hop.

Severity: **LOW** (works today, brittle to future changes).

---

## Scenario 4 — Off-by-one boundary stress at 99/100/101/102

**Verdict:** CORRECT at every transition, no surprises.

**Repro:** Walk a 4-row table at the gate boundary:

| caller | other | `mine > 100` | `other <= 100` | Result |
|--------|-------|--------------|----------------|--------|
| 99     | 100   | F            | T              | false  |
| 99     | 101   | F            | F              | TRUE   |
| 100    | 100   | F            | T              | false  |
| 100    | 101   | F            | F              | TRUE   |
| 101    | 100   | T            | (short-circuit)| false  |
| 101    | 101   | T            | (short-circuit)| false  |
| 102    | 99    | T            | (short-circuit)| false  |
| 99     | 102   | F            | F              | TRUE   |

All eight match the Saudi rule. The 99→100 (caller side) and
100→101 (other side) transitions are clean: neither side has a
"true at 99 but false at 100" or vice versa anomaly. The boundary
is set by `K.SUN_BEL_CUMULATIVE_GATE = 100` (Constants.lua:329) and
`R.CanBel` evaluates `>100` and `<=100` consistently.

Section N pins the most important: line 800 (caller=B, A=100,
B=0 → false), line 801 (A=101, B=0 → true), line 803 (A=101, B=100
→ true), line 805 (A=101, B=101 → false), line 810 (caller=A=101,
B=50 → false). Every "side of the gate" transition is covered.

Severity: **NONE**. Solid.

---

## Scenario 5 — Hokm allows Bel from any caller team unconditionally — partner-Bel?

**Verdict:** CORRECT but UNVERIFIED at the role gate. Wire still
locks Bel to the defender seat, so partner-Bel is unreachable.

**Repro:**

`Rules.lua:525-527`:

```
if contract.type ~= K.BID_SUN then
    return true                         -- Hokm: always allowed
end
```

For Hokm, `R.CanBel` returns `true` for any team at any score.
That mirrors video #11 @ 00:07:43-47:
`الحكم مفتوح في الدبل` ("Hokm is open in the doubling"). No
score-split exists for Hokm. ✓

But "any team can Bel" interacts with the same wire restriction
from Scenario 2. Even in Hokm, `Net.LocalDouble`/`_OnDouble` gate
on `seat == (bidder % 4) + 1`. So:

- The defender to the bidder's right may Bel: ✓
- The defender's partner (the OTHER defender) may NOT Bel via the
  wire: blocked by seat-routing
- The bidder may NOT Bel its own Hokm: blocked by seat-routing
- The bidder's partner may NOT Bel: blocked by seat-routing

Per Saudi tradition, "Bel" in Hokm is always a defender action
(the chain is Bel-Triple-Four-Gahwa, alternating defender→bidder),
and the canonical defender-of-record is the seat to the bidder's
right (Saudi anticlockwise convention). So this is the right
behavior — even though `R.CanBel` itself is permissive, the wire
correctly enforces "Bel comes from the seat to bidder's right." No
red-team finding here.

What this does highlight: `R.CanBel` is more permissive than the
addon ever needs. The function returns true for cases the wire
will never accept. This is a defensive "rule says yes, integration
narrows it" pattern — fine if intentional, but means
test_rules.lua's "any seat may Bel Hokm at any score" assertions
(lines 789-793) over-promise relative to live behavior. A reader
glancing at the test could mistakenly conclude that bidder-team
Bel of own Hokm is supported.

**Recommendation:** Add a one-line comment near `Rules.lua:526`:

```
-- Hokm: predicate always allows; wire authority gate
-- (Net.lua _OnDouble: seat == (bidder%4)+1) further restricts
-- to a single defender seat. The permissive predicate matches
-- the verbatim Saudi rule (الحكم مفتوح في الدبل); the seat
-- restriction encodes the Bel→Triple→Four→Gahwa alternation.
```

Severity: **LOW** (documentation clarity, not a bug).

---

## Scenario 6 — `Bot.PickDouble` strength gate when R1 admits a marginal Bel

**Verdict:** SAFE. Bot strength gate independently floors the
decision, so an admitted-by-rule Bel still requires hand strength.

**Repro:**

`Bot.lua:3442`:

```
if R.CanBel and not R.CanBel(R.TeamOf(seat), contract, S.s.cumulative) then
    return false, false
end
```

After `R.CanBel` passes, `Bot.PickDouble` continues to
`strength = sunStrength(hand)` and applies a threshold cascade
(BEL_TH ± urgency adjustments + ±10 jitter, Bot.lua:3447-3536).
An admitted-by-rule Bel does NOT auto-fire — bot still needs
~70 hand-strength to clear the threshold.

The R1 score-split rule mostly **adds** legality cases (the
bidder-trailing edge case at A=50,B=101). It can't push the bot
into "always Bel" territory because:

1. A trailing team's Bel decision still gates on hand strength.
2. The Sun bias `+10` (Bot.lua:3485) is unchanged from pre-R1.
3. `combinedUrgency` (Bot.lua:3494) is the same scoreUrgency the
   bot used pre-R1 — no behavioral surprise.

The only real change in bot behavior: **a trailing-bidder
defender-bot will no longer trigger a Bel when its own team is at
≥101**. Pre-R1, with v0.9.2 #45 anchored on bidder, a defender at
50 vs bidder at 130 would Bel. Post-R1 with cumA=130/cumB=50, B
bid Sun: `R.CanBel("A", sun_bidB, {A=130, B=50})` → A's `mine=130
> 100` → false. Defender A can NOT Bel. **Wait — this is correct
per the score-split rule (defender team is above gate)** but is a
*behavior change* relative to v0.9.2. A bot tuned against v0.9.2
might miss what was previously a legitimate Bel opportunity.

In practice this case is rare (Sun bids by trailing teams are
uncommon, and the defender being above 100 with bidder below 100
is rarer still). But it's a subtle bot-behavior shift not flagged
in the R1 changelog or reaudit.

Severity: **LOW** (behavior change for an uncommon configuration;
correctness is improved, but not announced).

---

## Scenario 7 — `R.CanBel` nil-arg handling

**Verdict:** CORRECT and DEFENSIVELY TESTED.

**Repro:**

`Rules.lua:524`:

```
if not contract or not team then return false end
```

| Inputs | Result | Reason |
|---|---|---|
| `R.CanBel(nil, sun, {A=50,B=50})` | false | guard at 524 |
| `R.CanBel("A", nil, {A=50,B=50})` | false | guard at 524 |
| `R.CanBel(nil, nil, ...)` | false | guard at 524 |
| `R.CanBel("A", sun, nil)` | false | mine=0, otherCum=0; `0 > 100` false, `0 <= 100` true → false ✓ |
| `R.CanBel("A", sun, {A=nil, B=200})` | true | mine=0, otherCum=200; `0 > 100` false, `200 <= 100` false → true ✓ |
| `R.CanBel(1, sun, {A=50, B=50})` (numeric team) | false | `cum[1]` → nil → mine=0; `otherTeam = 1 == "A" ? "B" : "A" = "A"` (since `1 ~= "A"`); otherCum = 50; `0 > 100` false, `50 <= 100` true → false ✓ |
| `R.CanBel("C", sun, {A=50, B=200})` (invalid team) | false | mine=0; otherTeam="A"; otherCum=50; `50 <= 100` true → false. Returns false (defensive but meaningless) |

Section N pins the first three at lines 842-846. Numeric / invalid
team cases are not pinned but evaluate to safe defaults.

One subtle point on the numeric `team` case: `R.CanBel(1, ...)` is
caught by the `not team` guard? **No — Lua treats `1` as truthy.**
The guard only catches `nil`/`false`. So a numeric `team` falls
through to the score-check, where `cum[1]` is nil (table is keyed
by string "A"/"B"). Result is consistent (`mine = 0` defaults), but
this is silent rather than rejected. A defensive type check would
be cleaner:

```
if type(team) ~= "string" then return false end
```

Severity: **NONE** (current behavior is safe; type tightening would
be a polish improvement, not a bug fix).

---

## Scenario 8 — Race: client `LocalDouble` → host `_OnDouble` cumulative-state divergence

**Verdict:** SAFE PATH EXISTS, but DOES NOT CATCH ALL DESYNC
SHAPES. Specific failure mode below.

**Repro setup:**

- Round N has just ended with a Takweesh resolution that pushed
  team A's cumulative from 95 to 105.
- Host has applied `S.ApplyRoundEnd` (cumulative.A = 105) and
  broadcast `MSG_ROUND`.
- Round N+1 deals; bidding completes with team A bidding Sun
  (so bidder=A, on team A which is now at 105).
- Phase advances to PHASE_DOUBLE.
- A defender on team B (still at 50) clicks Bel.

In normal operation `MSG_ROUND` reaches the B-defender client
before the deal finishes, so the client's `S.s.cumulative.A`
is already 105 when `LocalDouble` runs. `R.CanBel("B", sun_bidA,
{A=105, B=50})` → true → `MSG_DOUBLE` sent → host re-checks → true.
Clean.

**Failure mode:** `MSG_ROUND` is delayed by the addon-message
broker (WoW C_ChatInfo throttling: 10 msgs/sec). If the
B-defender's client is processing a stale snapshot (cumulative.A
= 95 from before the Takweesh) when it queries `R.CanBel`:
`R.CanBel("B", sun_bidA, {A=95, B=50})` → A's other-cum 95,
otherCum=95, `95 <= 100` true → **false**. The Bel button is hidden
on the B client (`UI.lua:1774`). The user can't even click.

Inverse: B-defender's client received MSG_ROUND but the host's
cumulative is stale (host applied a Takweesh penalty THIS round
that hasn't been mirrored). Highly unlikely since host is the
authoritative source — but a host that crashed mid-Takweesh
resolution and rebooted from saved state could in theory have
diverged-then-stale-rebooted state. The wire-side gate at
`Net.lua:887` would re-check against host's view.

**Currently mitigated by:**

1. UI gate (UI.lua:1774) → button hidden if local view says false.
2. Local gate (Net.lua:1854) → defense in depth, drops local Bel.
3. Host gate (Net.lua:887) → if illegal at host, broadcasts
   MSG_SKIP_DBL and finishes deal — explicit recovery (see
   Net.lua:889-893).

The MSG_SKIP_DBL recovery is documented at Net.lua:877-884 (v0.5.11
Race-A fix). But it only fires when the host REJECTS — i.e., when
the host's view says false but the local client's view said true.
The reverse case (local view says false, but host's view says
true → user never clicks because button never renders) has NO
recovery path. The Bel just silently doesn't happen.

**Failure mode 2 (worse):** Phase machine race where PHASE_DOUBLE
is entered on host side AFTER cumulative is updated, but the
client's PHASE_DOUBLE-entry message arrived before its
cumulative-update. Symptom: Bel UI renders but uses stale
cumulative.

In current code: `MSG_ROUND` (which carries new cumulative) and
`MSG_CONTRACT` (which advances phase to DOUBLE) are separate
messages. If they arrive out-of-order on a client (network jitter
+ `C_ChatInfo` is FIFO per-channel but cross-message ordering
isn't guaranteed across host's broadcast batch), there's a
window where:

- Client has phase=DOUBLE
- Client has cumulative reflecting round N (not N+1)
- UI renders Bel button using stale cumulative
- User clicks → MSG_DOUBLE → host checks against round N+1
  cumulative (different) → may reject

This rejection IS recoverable via MSG_SKIP_DBL → HostFinishDeal,
but the user experience is "I clicked Bel and nothing happened."
No visible error.

**Recommendation:**

1. The MSG_SKIP_DBL recovery path is solid for the
   wire-rejected-Bel case. No change needed.
2. Consider adding a one-shot host-side broadcast on PHASE_DOUBLE
   entry that re-asserts the cumulative state alongside the phase
   marker — eliminates the cross-message ordering race. Or
   piggyback cumulative onto the PHASE_DOUBLE message.
3. UX polish: when `LocalDouble` is silently dropped by the local
   `R.CanBel` gate (Net.lua:1853-1856), show a brief "Bel not
   currently legal — refresh state" toast to the user. Currently
   it just `return`s. The user thinks the click was lost.

Severity: **MEDIUM** (recovery exists for the wire-side case;
silent UI-stale case is real but rare).

---

## Scenario 9 — Bidder-trailing cumulative-flip mid-window

**Verdict:** NOT POSSIBLE under current architecture; flagging for
future-architecture awareness.

**Repro attempt:**

- Cumulative.A = 99, cumulative.B = 50 at PHASE_DOUBLE entry.
- B (defender, trailing) sees Bel button. `R.CanBel("B", sun_bidA,
  {A=99, B=50})` → A's mine=99, `99 > 100` false, but otherCum=50,
  `50 <= 100` true → **false**. Bel button HIDDEN.
- Hypothetically, mid-window something flips A from 99 to 105.
  Now `R.CanBel("B", ...)` → otherCum=105, `105 <= 100` false →
  true. Bel becomes legal.

**Why this can't happen in practice:** Cumulative is only mutated
inside `S.ApplyRoundEnd` (State.lua:1463-1465), which sets
`phase = K.PHASE_SCORE` (line 1466). A round can only be in
PHASE_DOUBLE OR PHASE_SCORE, not both. There is no mid-PHASE_DOUBLE
mutation of cumulative.

Takweesh? Net.lua:2129 requires `phase == K.PHASE_PLAY` —
Takweesh CANNOT fire during PHASE_DOUBLE. SWA? Same phase
restriction. So the cumulative state is genuinely frozen across
the entire PHASE_DOUBLE window from a single client's perspective
(modulo the cross-message-ordering race in Scenario 8).

The "freshness" question in the prompt is thus answered: at the
moment `R.CanBel` is queried inside PHASE_DOUBLE, `S.s.cumulative`
reflects the score AT THE END OF THE PREVIOUS ROUND, full stop.
No mid-round Takweesh adjustment possible.

**One sneaky case:** What if a host crashes during PHASE_DOUBLE
and the cumulative gets restored from `WHEREDNGNDB.history`
(history.lua telemetry export)? Looking at State.lua:450-452, the
restore path reads `s.cumulative.A = tonumber(f[16]) or 0`. If
the crash-restore landed mid-PHASE_DOUBLE with stale cumulative
(history was written before round N+1's pre-double cumulative
update), the predicate result could differ. But this is a
crash-recovery edge case, not a runtime race.

Severity: **NONE** under current architecture; **MEDIUM** for
future architecture changes that add async cumulative mutation
(e.g., voluntary score adjustments, deal-undo, dispute resolution).

---

## Scenario 10 — Off-by-one: opposite at exactly 100 (not 101)

**Verdict:** CORRECT but PRONE TO USER MISCONCEPTION.

**Repro:**

Cumulative `{A=50, B=100}`, B bid Sun. Defender A at 50.
`R.CanBel("A", sun_bidB, {A=50, B=100})` → mine=50, `50 > 100`
false; otherCum=100, `100 <= 100` true → **false**.

A player in this state, looking at the score, might reasonably
think: "B has 100 — they're at the gate. I'm at 50, way behind. I
should be able to Bel." But the Saudi rule per PDF 02 is precise:
`اي 101` ("that is 101"). The opponent must have STRICTLY crossed
100, not just touched it.

The `<=` in `if otherCum <= K.SUN_BEL_CUMULATIVE_GATE then return
false` is the correct integer encoding (a team at exactly 100 has
not crossed). Section N pins this at line 799-800: `R.CanBel("B",
sun_bidA, { A=100, B=0 }) == false`.

**However, the UI presents no explanation.** UI.lua:1775 just
prints "Bel forbidden (Sun >=100)" — which is **misleading** in
the inverse direction. Suppose A=50, B=100 and the local player is
on team A (trailing). The UI evaluates `R.CanBel("A", sun, {A=50,
B=100})` → false. Button shows "Bel forbidden (Sun >=100)". But
team A is NOT >=100. The user reads the message and thinks "huh,
my team is at 50, why does it say >=100?" The message refers to
"the >=100 RULE", not to the player's team's score, but the
phrasing is ambiguous.

A clearer label:

- "Bel forbidden — opponent must cross 100"
  (when blocked because otherCum <= 100)
- "Bel forbidden — your team is past 100"
  (when blocked because mine > 100)

Or a single neutral phrasing:

- "Bel forbidden — Sun gate not satisfied"

**Recommendation:** Refactor UI.lua:1775 to compute the specific
reason and surface it. Cheap change:

```lua
local mine = (S.s.cumulative and S.s.cumulative[R.TeamOf(S.s.localSeat)]) or 0
local otherTeam = (R.TeamOf(S.s.localSeat) == "A") and "B" or "A"
local other = (S.s.cumulative and S.s.cumulative[otherTeam]) or 0
local label
if mine > 100 then
    label = "|cff999999Bel forbidden — your team past 100|r"
elseif other <= 100 then
    label = "|cff999999Bel forbidden — opponent below 101|r"
else
    label = "|cff999999Bel forbidden|r"
end
addAction(label, function() end)
```

Severity: **LOW** (UX polish, no correctness issue).

---

## Scenario 11 — Bot.PickDouble for trailing-bidder edge case (bot perspective)

**Verdict:** UNTESTED at the bot-decision integration layer.

**Repro:**

- `S.s.contract = { type = K.BID_SUN, bidder = 1 }` (A bid Sun)
- `S.s.cumulative = { A = 50, B = 130 }` (A trailing, bidder team)
- A's bot partner (seat 3, team A) is asked: should I PickDouble?

`Bot.PickDouble(3)`:
- Line 3442: `R.CanBel("A", contract, {A=50, B=130})` → true.
- Line 3446-3486: hand strength evaluation.
- If strength > threshold, bot fires Bel.

But — same as Scenario 2 — the wire blocks bidder-team Bels:
`Net.LocalDouble` requires `localSeat == (bidder%4)+1 = 2`. Seat
3 is the bidder's partner, not the seat to bidder's right. So
even if `Bot.PickDouble` says "yes, Bel," the bot's call to
`N.LocalDouble` (or whatever wire-send the bot dispatcher uses)
will silently drop it.

**Worse — does the bot even get asked at seat 3?** In
`MaybeRunBot` host-side dispatch (Net.lua), the bot is queried
when its turn comes up. For PHASE_DOUBLE, the eligible-seat is
hardcoded `(bidder%4)+1`. Seat 3 in a bidder=1 contract is NEVER
asked to PickDouble — it's not the eligible seat. So
`Bot.PickDouble(3)` is never called in practice.

This means the entire predicate-says-yes-but-wire-says-no
divergence (Scenario 2) is also a never-asked-but-could-have-said-
yes divergence at the bot layer.

Section N has no fixture for `Bot.PickDouble` invocation; that's
a bot-test concern, not a rules-test concern. But searching
`tests/test_bot.lua` and similar for `PickDouble` invocations on
bidder-team seats would close the loop. None observed in the test
suite.

Severity: **LOW** (consistent with Scenario 2; no new bug, just
the same predicate-vs-wire mismatch at the bot layer).

---

## Cross-cutting verdict

`R.CanBel` itself is **correct** post-R1. All four boundary cases
in the prompt evaluate per the Saudi rule:

- `mine > 100`: false ✓
- `otherCum <= 100`: false ✓
- exactly 100/101: rule respects strict-cross ✓
- 99→100→101 sequence: clean transitions ✓

Tied 100/100, 50/50, 101/101: all return false (no team crossed
the gate or both teams above the gate). Saudi-rule conforming.
Hokm path: always-true predicate, with the wire encoding the
"defender to bidder's right" alternation convention.

The **substantive findings** are:

1. **MEDIUM — Scenario 2/11 wire-vs-predicate mismatch.** The
   bidder-trailing edge case (R1's headline fix) is admitted by
   `R.CanBel` but blocked by the wire's `(bidder%4)+1` seat
   restriction. The R1 changelog and reaudit don't acknowledge
   this. Either broaden the wire to admit the partner of a
   trailing bidder, or document that `R.CanBel`'s permissive
   answer is a predicate-only correctness; the wire intentionally
   narrows it.

2. **MEDIUM — Scenario 8 cross-message ordering race.** PHASE
   transition and cumulative update arrive as separate addon
   messages. There's a small window where a client's view of
   PHASE=DOUBLE and stale cumulative coexist. The
   wire-side host re-check + MSG_SKIP_DBL recovery handles the
   "local says yes, host says no" case cleanly. The "local says
   no, host says yes" case (button never rendered) has no
   recovery — silent UX failure. Mitigation: piggyback cumulative
   onto the phase-transition message.

3. **LOW — Scenarios 1, 5, 7, 10.** Documentation/test/UX gaps:
   no 100/100 explicit fixture; Hokm permissiveness over-promises
   relative to wire; numeric/invalid `team` arg silent; UI
   "Bel forbidden (Sun >=100)" message ambiguous when the local
   team is below 100 but opponent hasn't crossed.

4. **NONE — Scenarios 4, 9.** Off-by-one boundary handling and
   cumulative-state freshness are correct.

The code itself does not need to change for correctness. It needs
to change for **clarity** (Scenarios 1, 5, 7, 10) and for
**delivery of the R1 headline benefit** (Scenarios 2, 11). Both
are post-correctness polish.

## Confidence

**HIGH** for Scenarios 1, 4, 6, 7, 9, 10 — pure logic; verified
by tracing the integer predicates and grep-ing all call sites.

**HIGH** for Scenarios 2, 5, 11 — verified by reading
Net.lua:867-868 (`eligibleSeat = (S.s.contract.bidder % 4) + 1`)
and walking the seat arithmetic for both `bidder=1` and `bidder=2`.

**MEDIUM** for Scenarios 3, 8 — depend on
inter-message-ordering and host-broker delivery semantics that
this audit verified by reading code, not by running scenarios in
WoW.

**Tests run:** Section N test fixture (test_rules.lua:776-847)
inspected; not re-executed in this audit. The B-track audit
(`B-Rules-05_canBel.md`) already confirmed 362/362 pass under the
post-R1 test suite.
