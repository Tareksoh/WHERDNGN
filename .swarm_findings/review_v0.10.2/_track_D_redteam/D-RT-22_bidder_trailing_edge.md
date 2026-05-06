# D-RT-22: Bidder-trailing case — red-team v0.10.0 R1's score-split rewrite

**Target:** v0.10.0 R1's `R.CanBel` rewrite to score-split,
role-irrelevant: `caller.cum ≤ 100 AND opposite.cum ≥ 101`. The
"bidder-trailing" case — bidder=A at 50, defender=B at 120, A bids
Sun, A could call Bel on its own contract — is the headline edge
case the R1 fix advertises. Look for surprises beyond D-RT-05
Scenario 2's UI/wire reachability mismatch.

**Files inspected:**

- `C:\CLAUDE\WHEREDNGN\Rules.lua` 523–561 (`R.CanBel`)
- `C:\CLAUDE\WHEREDNGN\Net.lua` 68–83 (`N._SunBelAllowed`),
  860–913 (`N._OnDouble`), 975–991 (`N._OnPreempt`),
  1038–1053 (`N._FinalizePreempt`), 1247–1265 (post-overcall),
  1583–1601 (post-bid `belPending`), 1843–1871 (`N.LocalDouble`),
  1923–1950 (`N.LocalPreempt`), 3473–3508 (`_HostBelTimeout`),
  3580–3648 (`MaybeRunBot` PHASE_DOUBLE branch),
  3825–3858 (preempt bot-claim branch)
- `C:\CLAUDE\WHEREDNGN\Bot.lua` 3431–3543 (`Bot.PickDouble`)
- `C:\CLAUDE\WHEREDNGN\UI.lua` 1756–1791 (Bel button render)
- `C:\CLAUDE\WHEREDNGN\Constants.lua` 329 (`K.SUN_BEL_CUMULATIVE_GATE = 100`)
- `C:\CLAUDE\WHEREDNGN\tests\test_rules.lua` 776–847 (Section N)
- `C:\CLAUDE\WHEREDNGN\docs\strategy\decision-trees.md` 82–85
- `C:\CLAUDE\WHEREDNGN\docs\strategy\glossary.md` 68–80
- `C:\CLAUDE\WHEREDNGN\.swarm_findings\review_v0.10.0\_phase2_xref\reaudit_R1_bel100.md` 137–204
- `C:\CLAUDE\WHEREDNGN\.swarm_findings\review_v0.10.2\_track_D_redteam\D-RT-05_bel100_race.md` 71–134

**Method:** trace every `R.CanBel` / `_SunBelAllowed` call site,
walk the bidder-trailing config end-to-end (predicate → bot →
wire → UI), check whether bot-strength heuristics interpret
"bidder-Bel" semantics correctly, audit doc/test coverage of the
self-Bel case, look for confused conventions where a permissive
predicate meets role-asymmetric behavioural code.

---

## Confirmation of D-RT-05 Scenario 2: bidder-trailing-Bel is wire-unreachable

The known finding stands and is reconfirmed in R1's released form.
Three call-sites all gate Bel on the defender seat:

1. `UI.lua:1758-1759`:

   ```
   local b = S.s.contract and S.s.contract.bidder
   local nextSeat = b and ((b % 4) + 1) or nil
   if nextSeat == S.s.localSeat then
       ...
   ```

   Bel buttons render *only* in the `nextSeat == localSeat`
   branch. Bidder team never sees a Bel button.

2. `Net.lua:1847-1848` (`N.LocalDouble`):

   ```
   local b = S.s.contract.bidder
   if S.s.localSeat ~= (b % 4) + 1 then return end
   ```

   Even a forced local invocation by a bidder-team seat returns
   silently before reaching the `R.CanBel` defense in depth at
   1853.

3. `Net.lua:867-868` (`N._OnDouble`):

   ```
   local eligibleSeat = (S.s.contract.bidder % 4) + 1
   if seat ~= eligibleSeat then return end
   ```

   Wire-injected `MSG_DOUBLE` from a bidder-team seat is silently
   rejected before authority/legality checks.

4. `Net.lua:3582` (`MaybeRunBot` PHASE_DOUBLE):

   ```
   local belSeat = (S.s.contract.bidder % 4) + 1
   if isBotSeat(belSeat) then ...
   ```

   Bot dispatcher only invokes `Bot.PickDouble` for the defender
   to the bidder's right. Bidder-team bots never receive the Bel
   prompt.

**Net effect:** the R1 score-split rule is correct in `R.CanBel`,
but the integration path effectively continues to enforce v0.9.2's
"defender-only" behavior. The headline edge case (bidder-trailing
A=50 vs defender-leading B=130, A bid Sun, A *should* be allowed
to Bel its own contract) cannot fire in live play.

This is not a regression — the `(bidder % 4) + 1` constraint
predates R1. It just means the celebrated R1 fix is, in
production, a no-op in its headline scenario. D-RT-22 below
documents *additional* surprises beyond this reachability gap.

---

## Scenario A — Confused convention: bidder-Bel risk vs defender-Bel risk

**Verdict:** RULE-CLARITY GAP. The R1 rewrite blurs an asymmetry
that is not blurred in Saudi convention.

In Saudi tournament play, "Bel" is colloquially understood as the
**defender's protest** against the bidder's contract. The
escalation chain — Bel (defender) → Triple (bidder) → Four
(defender) → Gahwa (bidder) — *literally bakes in* alternation
where defender opens. Source F1.07 (cited in
`reaudit_R1_bel100.md:163`): "the chain alternates: defender →
bidder → defender → bidder for Hokm."

In Sun, the chain has only one rung. R1's prose argument
(`reaudit_R1_bel100.md:170-176`) says: "Sun has only one rung
(Bel). There is no 'next escalation' to alternate to. So the
question 'who initiates' is the only question. The Saudi rule
under Sun is: only the trailing team initiates."

That argument is internally consistent for the predicate. But the
**risk semantics are role-asymmetric** even when legality is
score-split:

- A defender-Bel says: "I will hold you accountable." If defender
  is wrong, the bidder pockets `2× hand_total` for making.
- A bidder-Bel says: "I'm so confident I'll voluntarily double my
  own loss exposure." If the bidder is wrong, the bidder loses
  `2× hand_total`.

The two are mathematically inverse but tactically different.
Specifically, **bidder-Bel is dominated** by either letting the
contract play normally (no risk amplification) or by simply
playing better. There's no positive-EV reason for a trailing
bidder to Bel its own contract — the multiplier just doubles the
cost of failing while the bidder is *already* the team taking the
contract risk.

The `Bot.PickDouble` strength gate (Bot.lua:3442–3543) was
designed and tuned **assuming the caller is a defender**:

- Line 3458–3482 (`v0.5.1 C-3b: defender-aware strength
  additions`): explicitly comments "defender-aware" — voids and
  side-Aces signal *ruff capacity* and *trick-winning power
  outside the trump axis*. For a bidder-Bel of own Sun contract,
  these are not "ruff capacity" — they're the very strengths the
  bidder already has. Treating them as additional Bel-incentive
  is the wrong direction.

- Line 3485 (Sun bias `+10`): comment says "Sun is harder for
  the bidder." This was intended as a defender-Bel bias under Sun
  (defender doubling a *bidder's* harder contract). For
  self-Bel, this is an *anti*-incentive that wrongly cancels.

- Line 3494 (`combinedUrgency(R.TeamOf(seat), "defend")`): the
  context literal `"defend"` flips near-clinch math to
  aggressive. For a bidder calling Bel on its own contract,
  defender semantics no longer apply.

- Line 3504–3508 (B-95 opp-bidder desperation tweak): predicates
  on `contract.bidder` being on a different team — silently
  no-ops for bidder-Bel because `opponentUrgency(contract.bidder)`
  is querying our own team's urgency and the comparison is
  logically inverted.

So if the bidder-Bel reachability gap (D-RT-05 Scenario 2) were
ever closed at the wire/UI layer, **`Bot.PickDouble` would
silently apply defender semantics to a bidder-context decision**.
The bot would be more willing to Bel its own contract than the
correctness math justifies, because every heuristic was tuned
against "doubling the opponent's contract."

This is not a bug today (the wire blocks the case from
firing), but it's a load-bearing assumption nowhere documented
or tested. **A future patch that broadens the wire to follow R1's
rule literally would silently activate untuned bot behavior.**

**Severity: MEDIUM** (latent; surfaces only if the wire is
broadened, but R1's reaudit_R1_bel100.md *recommends exactly that
broadening* in its closing paragraphs without flagging the
heuristic mistuning).

---

## Scenario B — `Bot.PickDouble` does not enforce role-asymmetric thresholds

**Verdict:** DESIGN GAP. R1 made the *legality predicate*
role-irrelevant, but no commensurate change went into the
*decision picker*.

Concretely: `Bot.PickDouble` uses one `K.BOT_BEL_TH` threshold
(currently `70`, with floor `K.BOT_BEL_TH - 16 = 54`). It is
applied to defender-Bel by *every* current call site. With R1's
rule, the same threshold would also apply to bidder-Bel if the
wire were ever broadened.

That's wrong even within the score-split model. The breakeven
for self-Bel is *strictly higher* than for opponent-Bel:

- Defender-Bel breakeven: defender wins ⇔ bidder fails. The
  multiplier doubles the existing penalty if defender is right
  and doubles the existing reward if defender is wrong. Symmetric
  EV around 50% confidence.
- Bidder-Bel breakeven: bidder wins ⇔ bidder makes. Self-doubling
  doubles both make-bonus and fail-penalty. The bidder *was
  already* in this trade — the Bel is a pure variance-amplifier.
  EV-positive only at much higher confidence (since you're betting
  *additional* utility against your own already-uncertain contract).

A properly tuned bidder-Bel threshold would be substantially
higher (heuristically ~85+ vs the current 70 for defender-Bel,
since the multiplier amplifies the bidder's *own* downside
exposure as well as the upside). R1 did not introduce this split.

**Recommendation:** if the wire is ever broadened to honor the R1
predicate, add a `Bot.PickDouble` branch that distinguishes:

```lua
local isBidderTeam = R.TeamOf(seat) == R.TeamOf(contract.bidder)
local th = isBidderTeam and (K.BOT_BEL_TH + 15) or K.BOT_BEL_TH
```

(plus context flips for `combinedUrgency` and `partnerBidBonus`
which currently assume defender semantics).

**Severity: MEDIUM** (latent; same gating as Scenario A).

---

## Scenario C — Reachability test: bidder-trailing-Bel has *never* fired in production

**Verdict:** CONFIRMED UNREACHABLE in any released path. Test
fixture line 815-816 asserts the predicate but no integration
path exists.

Greppable evidence:

- Every call to `R.CanBel` outside Rules.lua passes either
  `R.TeamOf(localSeat)` (UI/LocalDouble: gated by
  `localSeat == defenderSeat`), `R.TeamOf(seat)` where `seat`
  was already constrained to `defenderSeat` upstream
  (`Bot.PickDouble` via MaybeRunBot's `belSeat = (bidder%4)+1`
  dispatch, `_OnDouble`'s `eligibleSeat` check), or
  `_SunBelAllowed`'s "trailing team" computation (used only to
  *skip* the PHASE_DOUBLE phase entirely when no team is eligible
  — never to *route* a Bel from a non-defender seat).
- `_SunBelAllowed` (Net.lua:68-83) returns `R.CanBel(trailingTeam,
  ...)` — but only the **boolean** result is consumed (4 call
  sites: 984, 1047, 1258, 1595, 1943). All four use it to decide
  whether to *suppress* the PHASE_DOUBLE phase (no Bel possible)
  or *enter* it (some-team-can-Bel). None of them route the Bel
  *to* the trailing team — the routing in PHASE_DOUBLE is still
  hardcoded `(bidder%4)+1`.

So in concrete terms: when bidder=A at 50 and defender=B at 130
and A bids Sun, `_SunBelAllowed` returns `true` (because team A
the trailer satisfies CanBel); PHASE_DOUBLE opens; the bot/UI
prompt goes to seat (A.bidder%4)+1 = a B-team seat; that seat's
team is B, which is *above* the gate, so `R.CanBel("B", ...)` →
false; the UI shows "Bel forbidden" and the player can only Skip.

The R1 rule asserts team A can Bel here. The wire offers no path.
PHASE_DOUBLE opens *and resolves with no Bel possible*. This is
behaviorally identical to v0.9.2's wrong-but-effective rejection,
except v0.9.2 would have silently skipped the entire phase via
`_SunBelAllowed = false` instead of opening PHASE_DOUBLE for a
forbidden-Bel non-decision.

**Note:** opening PHASE_DOUBLE only to immediately AFK-timeout
back into PHASE_PLAY is *worse UX* than just skipping the phase
— it adds a 30-second-or-so delay (the AFK skip timer at
`_HostBelTimeout` Net.lua:3473–3492) for no benefit. R1's R1
fix accidentally *worsens* the UX in this exact case versus
v0.9.2. v0.9.2 would skip the phase outright.

**Severity: MEDIUM** (UX regression in edge case; first identified
here). v0.9.2 took 0 seconds to advance through the bidder-trailing
case; v0.10.0 R1 takes ~30s of dead-air phase before timing out.

**Repro setup:**
- `S.s.cumulative = { A = 50, B = 130 }`
- A bids Sun
- v0.9.2: `_SunBelAllowed` checks `bidderCum (=50) > 100` → false
  → `S.s.belPending = nil; HostFinishDeal()` (Net.lua:1595–1599
  pattern). Phase advances immediately to PLAY.
- v0.10.0 R1: `_SunBelAllowed` queries `R.CanBel("A", ...)` (A is
  the trailer per Net.lua:79). A is below gate, B above → returns
  true. PHASE_DOUBLE *opens*. Routing goes to seat B (a defender
  seat). That defender's `R.CanBel("B", ...)` → false. UI shows
  "Bel forbidden." Player must click Skip, OR `_HostBelTimeout`
  fires after BEL timer (default ~30s). Then PHASE_PLAY.

Confirmed by code reading. No test catches this regression because
the test suite only checks `R.CanBel` boolean return, not the
phase-flow consequence.

---

## Scenario D — UI implications: "Bel forbidden (Sun >=100)" message is misleading on defender side

**Verdict:** RULE-CLARITY GAP, surfaces in production.

In the Scenario C config (cumA=50, cumB=130, A bids Sun), the B
defender sees the message at UI.lua:1775:

```
addAction("|cff999999Bel forbidden (Sun >=100)|r", function() end)
```

This message is **misleading**: the literal reason "Sun >=100" is
true (defender team B is at 130, ≥100), but the *real* reason the
defender can't Bel is "the rule lets your trailing-team partner
do it but the wire doesn't expose it." The message says "you
can't" without saying "and your partner can't either, because of
a different gate."

A Saudi-rules-fluent player reading the message would expect:
"Bel forbidden because B is ahead, but A (the bidder team,
trailing) should be able to Bel." That's the R1 rule. The message
gives no hint about why A's seat doesn't see the button.

**Recommendation:** `R.CanBel` should expose a *reason* field
(or a sibling diagnostic predicate) that the UI can render
contextually. Or, more pragmatically: the message should be
context-aware:

- If neither team can Bel (both above OR neither crossed): "Bel
  forbidden — score gate not met."
- If the trailing team is the bidder team: "Bel only available
  to bidder team (Saudi rule); however, this addon does not
  surface a bidder-team Bel button."

The second reason is **important** because it documents a
deliberate convention deviation (the wire is defender-only by
design, regardless of the rule predicate). Today this deviation
is undocumented in the player-facing UI.

**Severity: MEDIUM** (player confusion in edge case).

---

## Scenario E — Test fixture coverage: "kept permissive for now" comment is now stale

**Verdict:** STALE DOC ARTIFACT.

`reaudit_R1_bel100.md:170-175` mentions:

> Test fixture line 783–784 in `tests/test_rules.lua` even
> comments this: "bidder team itself can also call — kept
> permissive for now."

That comment no longer exists in the updated test_rules.lua
Section N (lines 776–847 in the post-R1 file). The R1 release
replaced it with explicit assertions:

- Line 810-811: `R.CanBel("A", sun_bidA, { A=101, B=50 }) == false`
  with note "Sun: bidder=A at 101 → A canNOT Bel own contract
  (above gate)" — *this is the bidder-leading case, where A is
  forbidden by being above the gate*.
- Line 815-816: `R.CanBel("A", sun_bidA, { A=50, B=101 }) == true`
  with note "Sun: bidder=A trailing at 50, defender=B at 101 → A
  (bidder team) can Bel" — *this is the bidder-trailing case,
  where R1 says A is allowed*.

So the predicate is well-tested. But the **integration test
suite** has zero coverage of the bidder-trailing config. There
is no test that:

1. Sets up `S.s.cumulative = {A=50, B=130}`, bidder=1 (team A),
   contract=Sun.
2. Triggers PHASE_DOUBLE entry.
3. Verifies that PHASE_DOUBLE *correctly handles* the case (either
   advances straight to PLAY because no eligible seat exists, OR
   routes Bel to a team-A seat per the R1 intent).

`tests/test_rules.lua` is unit-level only. There is no test in
the harness that exercises `_SunBelAllowed` → `MaybeRunBot` → bot
dispatch end-to-end for the bidder-trailing case.

**Recommendation:** add at least:

1. A "predicate vs flow" test that verifies: when `cumA=50,
   cumB=130, bidder=A.seat, type=Sun`, then either (a) the phase
   is skipped OR (b) the routed seat's `R.CanBel` returns true.
   Currently neither holds — the phase opens but the routed seat
   says "forbidden."
2. A regression test for the v0.9.2-vs-v0.10.0 phase timing: the
   bidder-trailing case should not introduce a 30-second dead-air
   phase versus the v0.9.2 "skip phase" behavior.

**Severity: LOW** (test gap; the unit predicate is solid).

---

## Scenario F — Saudi rule documentation: explicit case missing

**Verdict:** RULE-CLARITY GAP. The case "bidder team is trailing
and Bels its own contract" is **not documented in the strategy
docs at all**.

`docs/strategy/decision-trees.md:82` reads:

> Sun contract, your team's cumulative score is ≥100 → **Bel is
> FORBIDDEN** — legality gate, not heuristic. Hard Saudi rule:
> only the team <100 may Bel in Sun. Hokm has no such gate.

This row predates R1 and frames the gate as a single condition
("your team ≥100 ⇒ forbidden"). It does not enumerate:

1. The case where the bidder team is trailing.
2. Whether a bidder team is permitted to Bel its own contract.
3. Whether convention says yes-but-rare or no-by-tradition or
   yes-because-trailing-team-only.

`docs/strategy/glossary.md:68-80` also frames the rule as a
single condition with no role discussion.

The **only** doc that addresses bidder-self-Bel is the
`reaudit_R1_bel100.md` analysis (`.swarm_findings/`), which is
internal-process documentation, not the user-facing strategy
docs. A player or contributor reading `decision-trees.md` would
not know the bidder-trailing case is supported by R1.

**Recommendation:** decision-trees.md row 82 should be split into
two rows or expanded to:

| Sun contract, *your team* is ≥101 cumulative | **Bel is FORBIDDEN** for your team — Hard Saudi rule. | Bidder/defender role does not enter — only score position. | …
| Sun contract, *your team* is ≤100 AND opposing team is ≥101 | **You may Bel** — even if your team is the bidder team. | Score-split rule per video #11 + PDF 02 + PDF 07. | (Note: addon's wire/UI currently routes Bel only to the seat-right-of-bidder, so the bidder-team Bel button is not surfaced. See `R.CanBel` legality vs `Net.LocalDouble` routing.)

Glossary.md should similarly add: "**Note on bidder-team Bel**:
the rule does *not* exclude the bidder team. If the bidder is on
the trailing team, the bidder team is the only side eligible.
The addon currently does not expose a bidder-team Bel button
(routing is hardcoded to the defender seat), so this case is
predicate-correct but UX-unreachable."

**Severity: MEDIUM** (doc-vs-implementation drift; new
contributors will not know about this).

---

## Scenario G — `_SunBelAllowed` skip-phase decision is correct *but the routing afterward is wrong*

**Verdict:** SUBTLE ASYMMETRY between gate-on-phase-entry and
gate-on-action-route.

`Net.lua:79`:

```
local trailingTeam = (cumA <= cumB) and "A" or "B"
return R.CanBel(trailingTeam,
                { type = K.BID_SUN, bidder = bidderSeat },
                S.s.cumulative)
```

`_SunBelAllowed` uses the trailing team as the *probe* for "can
ANYONE Bel in this configuration?" The result is correctly
score-split.

But after `_SunBelAllowed` returns true, the actual Bel routing
falls back to `(bidder%4)+1`. There's no symmetric "_SunBelRoute"
helper that returns the eligible seat. So the codebase has:

- `_SunBelAllowed`: score-split, role-irrelevant, R1-correct.
- Routing (4 call sites): defender-only, role-anchored,
  v0.9.2-shape.

**These two cooperate correctly only when the trailing team is
the defender team.** When the trailing team is the bidder team,
`_SunBelAllowed` says "yes, trailing team eligible" and the
routing says "ask the defender" — defender's `R.CanBel` then
correctly returns false (defender team is above gate), and the
phase silently AFK-times-out.

**Recommendation:** add a sibling helper

```lua
function N._SunBelRoutedSeat()
    -- returns the seat eligible to Bel under R1 rule, or nil
    -- if no seat is eligible.
end
```

and route to it instead of the hardcoded `(bidder%4)+1`. If this
ever returns a bidder-team seat, the UI/wire/bot flow should fire
*there* instead of the defender seat. This closes D-RT-05
Scenario 2 properly while keeping `_SunBelAllowed` semantically
clean.

Alternatively, document the asymmetry: `_SunBelAllowed`'s
"yes" answer is only reachable when the trailing team happens to
be the defender team, and the bidder-team-trailing case should
be added to the comment block.

**Severity: MEDIUM** (architecture clarity; ties together
Scenarios A–F).

---

## Scenario H — `_HostBelTimeout` AFK fallback masks the unreachability

**Verdict:** INFRASTRUCTURAL OBSERVATION.

When PHASE_DOUBLE opens for the bidder-trailing case (Scenario
C), the routed-defender's UI shows "Bel forbidden" but the player
must still click Skip. If they don't:

`Net.lua:3473-3493`:

```
function N._HostBelTimeout(seat, kind)
    if not S.s.isHost or not S.s.contract then return end
    if S.s.paused then return end
    if kind == "double" and S.s.phase == K.PHASE_DOUBLE then
        log("Info", "AFK timeout: bel skip seat=%d", seat)
        broadcast(("%s;%d"):format(K.MSG_SKIP_DBL, seat))
        N.HostFinishDeal()
    ...
```

So the timeout *does* recover, but the recovery duration depends
on `BOT_DELAY_BEL` and AFK timer settings. Bots `Bot.PickDouble`
also handle the case gracefully — `R.CanBel` returns false at line
3442, so the bot returns `(false, false)` and the dispatcher sends
`MSG_SKIP_DBL` (Net.lua:3613).

But: **a human player at the routed defender seat** sees the
"Bel forbidden" message and may be confused why this case opened
the phase at all. The recovery path is solid, the experience is
not.

**Severity: LOW** (UX-only).

---

## Verdict summary

| Scenario | Severity | Type |
|---|---|---|
| (D-RT-05 Sc.2 reconfirmed) | MEDIUM | Reachability gap |
| A — Bot.PickDouble heuristics tuned for defender semantics | MEDIUM | Latent bug if wire broadens |
| B — No role-asymmetric BOT_BEL_TH | MEDIUM | Latent bug if wire broadens |
| C — PHASE_DOUBLE opens unnecessarily, ~30s dead-air | MEDIUM | UX regression vs v0.9.2 |
| D — "Bel forbidden" message misleading | MEDIUM | UI/UX clarity |
| E — Integration test gap | LOW | Test coverage |
| F — Saudi rule docs missing the case | MEDIUM | Doc-vs-impl drift |
| G — `_SunBelAllowed` vs routing asymmetry | MEDIUM | Architecture clarity |
| H — AFK timeout masks the issue | LOW | UX-only |

**Bottom line:** R1's `R.CanBel` predicate is correct in
isolation, but the integration around it has at least eight
distinct surprises in the bidder-trailing case beyond the known
UI/wire reachability gap. The most impactful is **Scenario C**:
the v0.9.2 fast-skip behavior was lost when R1 changed
`_SunBelAllowed` to query the trailing team — the predicate now
returns true (correctly per R1), so PHASE_DOUBLE opens, but the
routed defender seat has no legal Bel, so the phase silently
dead-airs ~30s before AFK-skipping. A user-visible regression
that no v0.10.x release notes acknowledge.

---

## Recommendations (ranked, no-code-change)

1. **Document the integration gap explicitly in the codebase.**
   Add a comment block to `R.CanBel` (Rules.lua near line 540)
   noting:

   > NOTE: this predicate is score-split, role-irrelevant per
   > Saudi rule, but the wire/UI in v0.10.x routes Bel
   > exclusively to the seat-right-of-bidder via Net.LocalDouble
   > / Net._OnDouble / Net.MaybeRunBot. The bidder-trailing case
   > (where the predicate admits a bidder-team Bel) is therefore
   > predicate-correct but UX-unreachable in the current release.
   > See D-RT-22 / D-RT-05 Scenario 2.

2. **Document the bot-heuristic dependency on defender
   semantics.** Add a comment to `Bot.PickDouble` near line 3442
   that the strength gate, sun-bias, and combinedUrgency are all
   tuned for the defender-Bel role and would need re-tuning if
   the wire ever broadens to admit bidder-Bel.

3. **Add the bidder-trailing case to `decision-trees.md` and
   `glossary.md`.** Either describe it as supported-but-unrouted
   or supported-and-routed, but do not leave readers to discover
   the case from `.swarm_findings/`.

4. **Add a regression test** covering the v0.9.2-vs-v0.10.0
   phase-timing: when `_SunBelAllowed` returns true but the
   routed seat cannot Bel, the phase should still transition
   quickly to PLAY (currently waits for AFK timeout).

5. **Consider closing the wire/UI gap properly** by adding a
   `_SunBelRoutedSeat()` helper (Scenario G). Defer the bot-
   heuristic re-tuning (Scenarios A/B) until that lands.

6. **Optional:** improve the "Bel forbidden" message to
   distinguish "your team is above gate" from "no seat on your
   team can route a Bel" (Scenario D).
