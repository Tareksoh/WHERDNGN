# v3.2.4 design pass — F2 pos-3 Sun «تخليه يمسك» deception relocation

**Repo:** `C:\CLAUDE\WHEREDNGN`
**Main / origin-main / v3.2.3 tag:** all at `c96f120`
**Baseline harness on `main`:** 1,258 / 0
**Scope:** read-only design + recommendation. No runtime, test, TOC,
packaging edits.

---

## §0 Executive recommendation (TL;DR)

**Defer F2 indefinitely. Reason: F5-3 (relocated in v3.2.3) already
implements F2's primary "duck-low" behaviour deterministically, via
its `not wouldWin(c, trick, contract, seat)` candidate filter. The
F2-unique territory (Smother override at tricks 4-5 with a 30%/40%
probabilistic gate) is narrow, has speculative EV without a
deception-play simulator, and requires the riskiest placement
option (before Smother).**

If you still want to proceed:

- **Preferred narrower batch:** add a v3.2.4 in-source comment-marker
  update to F2's dead block acknowledging the post-v3.2.3 redundancy
  with F5-3. Doc-only Bot.lua edit (or even just a `.swarm_findings/`
  doc), no test changes. Closes the loop on the v3.2.1 "deferred to
  separate audit" promise without bringing in probabilistic firing.
- **Full relocation:** Option A (before Smother). The
  Codex-approved deterministic `math.random` single-shot stubs
  from BE.1 / BF.9 are adequate for a narrow implementation —
  they pin fire vs no-fire reliably and have zero flakiness. But
  they do NOT prove the long-run **rate** parameter (whether the
  threshold is actually 0.30 / 0.40 versus, say, 0.20 / 0.50)
  and they do NOT prove the **EV** of the deception play. The
  lack of EV and long-run-rate confidence is part of why
  relocation is deferred — not a missing test framework. Adding
  a bounded-iteration statistical check to verify the rate is
  possible but explicitly discouraged in §5.2 (flakiness risk +
  iteration-count magic number) unless Codex specifically
  requests it.

---

## §1 Current code map (post-v3.2.3)

| Branch | File:lines | Reachable? |
|---|---|---|
| Sun pos-4 Faranka (pre-block) | `Bot.lua:3175-3360` | yes — gated on `lastSeat` |
| **`if partnerWinning then`** opens | `Bot.lua:3366` | live |
| Smother (Takbeer) | `Bot.lua:3367-3532` | live |
| Tahreeb sender | `Bot.lua:3534-3737` | live (v1.4.5 removed the partner-bot gate) |
| **F5-3 (v3.2.3 relocated)** | `Bot.lua:3739-3788` | **live** — pos-3 Sun Takbeer/Tasgheer donate; uses `not wouldWin` filter + `highestByRank` |
| Rule 1B (biggest mistake) | `Bot.lua:3790-3849` | live |
| v3.1.9 trump-led-fragile-lock | `Bot.lua:3851-3918` | live (Hokm only — won't shadow F2) |
| Hokm non-trump preference | `Bot.lua:3925-3935` | live (Hokm only) |
| Fallback `lowestByRank(legal)` | `Bot.lua:3937` | live |
| `end` (partnerWinning block ends) | `Bot.lua:3938` | — |
| ... opp-winning block ... | `Bot.lua:3940+` | — |
| **F2 «تخليه يمسك» (still dead)** | `Bot.lua:4510-4670` | **UNREACHABLE per v3.2.1 F2 marker** |

Final live partnerWinning ordering after v3.2.3:

```
Smother → Tahreeb → F5-3 → Rule 1B → trump-fragile-lock → Hokm non-trump → fallback
```

F2 sits in the opp-winning region at L4510-4670, **still flagged
unreachable** by the v3.2.1 F2 comment marker (L4533-4547). v3.2.3
deliberately did not touch this branch.

---

## §2 Original F2 intent

Source: `Bot.lua:4510-4670` (current dead location).

### §2.1 Trigger gates (all must hold)

| Code line | Gate | Notes |
|---|---|---|
| L4548 | `Bot.IsM3lm()` | tier gate; Saudi-Master fires harder |
| L4549 | `contract.type == K.BID_SUN` | Sun only |
| L4550 | `trick.plays and #trick.plays >= 2` | implies pos ≥ 3 |
| L4551 | `#winners > 0` (required by enclosing `if #winners > 0` at L4181) | this is the reachability blocker — implies opp-winning context |
| L4565 | `partnerLed` (`pos1.seat == R.Partner(seat)`) | partner is the leader |
| L4567-68 | `partnerLedMid` — pos1 rank ∈ {8, 9, J, Q} | partner led mid, not boss/low |
| L4571-77 | `pos2Lower` (pos-2 played lower OR off-suit Sun-loses) | implies `partnerWinning == true` |
| L4584 | `hasK` (K of led in hand) | hand-shape |
| L4585-90 | `lowCard` (highest of 7/8/9 of led in hand) | duck target |
| L4596-4615 | `hasIndependentStrength` (≥1 A in another suit OR a 3+-card non-trump elsewhere) | not betting the round on this K |
| L4617-18 | `midRound` (trick number 2-5) | window |
| L4620-26 | `nonClutch` (both teams below `target - 26`) | score gate |
| L4646-52 | `pos4CannotBeat` (`Bot._memory[pos4].void[lead] == true`) | strict pos-4 void |
| L4653-57 | `fireRate = 0.30 (M3lm) / 0.40 (Saudi Master)`; `math.random() < fireRate` | **probabilistic** |

### §2.2 Return behaviour

```lua
-- Hold-back FIRES: duck with the low, save K
-- for "next round" psychological play.
return lowCard
```

`lowCard` is the **highest** card in led suit with rank in {7,8,9}.

### §2.3 Saudi convention in plain terms

«تخليه يمسك» (≈ "let him think he's holding"): partner is currently
winning the trick with a mid card (8/9/J/Q); opp pos-2 already played
lower; pos-4 is confirmed void in led suit, so partner WILL win the
trick regardless of what we play. We have the K of led plus a low
(7/8/9). Rather than dump the K onto partner's pile as Takbeer
(Smother) would, we **duck low** so that opp pos-4 — observing our
"low play after partner's mid lead" — models us as void / weak in
that suit. Next time they get the lead, they may re-open the same
suit thinking it's safe; we then crush with the saved K.

### §2.4 Differs from Smother / F5-3 / Rule 1B in this specific shape

Compare cards returned for the same fixture (Sun, pos-3, hand
`{KS, 9S}` after partner JS + pos-2 8S; pos-4 void in S):

| Branch | Returned card | Intent |
|---|---|---|
| Smother | `KS` (if `gateOk` passes) | Takbeer point-donate to partner's pile |
| **F5-3 (v3.2.3)** | `9S` (filter rejects KS as wouldWin; pool = {9S}) | Takbeer/Tasgheer certainty donate; **same low card** as F2 |
| Rule 1B | `9S` (`follow = {KS, 9S}`, sorted ascending → sorted[2]=KS but KS wouldWin → falls to fallback; fallback returns lowestByRank → `9S`) | re-entry signal (or fallback if 2nd-lowest wouldWin) |
| **F2 (this design)** | `9S` (lowCard = highest of 7/8/9 = 9) | deception: low duck, save K |

**All four branches converge on `9S` for this shape.** F2 is therefore
functionally REDUNDANT with F5-3 in the must-follow case where K
beats partner. See §3 for where they diverge.

---

## §3 Conflict analysis

### §3.1 F2 vs Smother — the real conflict

Smother iterates pointCards in led suit = {A, T, K, Q, J of led}. K
is a smother point card. Smother's outer `gateOk` = `(#pointCards >=
2) or (completed >= 3) or lastSeat`.

F2's intended fire shape has `hasK = true` and `lowCard ≠ nil` →
`#pointCards = 1` (just K of led; we don't usually hold J as well in
this narrow shape, but it's possible). F2 also requires `midRound`
(trick 2-5 → `completed = 1..4`) and is at pos-3 (`lastSeat = false`).

**Smother's gateOk passes at**:
- `#pointCards >= 2`: rare in F2's shape; possible if hand has K + J
  of led (both point cards). In that case Smother fires regardless
  of placement.
- `completed >= 3`: F2's midRound window of trick 2-5 maps to
  `completed = 1-4`. So at completed = 3 or 4 (trick 4-5), Smother's
  gateOk passes and Smother returns K.
- `lastSeat`: pos-3, false.

**Smother shadows F2** at tricks 4-5 in F2's intended shape (unless
F2 placed before Smother).

**F2 shadows Smother** at tricks 2-3 only when:
- `#pointCards = 1` (just K) AND `completed < 3` AND not lastSeat
- → Smother falls through naturally
- F2 fires probabilistically; when it doesn't fire, F5-3 or Rule 1B
  takes over.

So the F2-unique behaviour is **"at trick 4-5, with the F2 shape,
replace Smother's K-donate with a low duck 30%/40% of the time."**

### §3.2 F2 vs Tahreeb sender — non-overlapping

Tahreeb's gate at `Bot.lua:3584`: `Bot.IsM3lm() and voidInLed`. F2
requires the bot to **hold** K of led + low of led → `voidInLed =
false`. So Tahreeb's outer gate fails when F2's conditions match.
No overlap.

### §3.3 F2 vs F5-3 (v3.2.3) — functional redundancy

F5-3's gates: `Sun + M3lm + pos-3 + leadSuit + Bot._memory + pos4Void`.
F2's gates are a **strict subset** of F5-3's plus the
deception-specific narrowing (partner-led-mid, pos2-lower, hasK,
lowCard, indep-strength, midRound, nonClutch, RNG).

**Critical observation:** in F2's intended must-follow shape (we
hold K + low of led, partner leads mid, partner currently winning,
pos-4 void), F5-3's candidate-pool construction produces the SAME
result as F2 would:

1. F5-3 iterates legal: K (suit=lead) → `wouldWin(K)` = K rank > J/Q/9/8 rank → **K rejected by filter**.
2. F5-3 iterates legal: low (suit=lead, rank 7/8/9) → `wouldWin(low)` = low rank < mid rank → **low eligible**.
3. F5-3 pool = `{low}`. `highestByRank({low})` returns low.

Same `lowCard` as F2 wants to return. The behavioural difference is:
- F5-3 returns it deterministically (no RNG).
- F2 returns it probabilistically (30%/40%).

So at tricks 2-3 in F2's shape (where Smother also falls through),
F5-3 already does the duck. F2 placed before Smother would ALSO
duck (matching F5-3). F2 placed after F5-3 would never fire because
F5-3 returned first.

### §3.4 F2 vs Rule 1B — different intent, similar output

Rule 1B returns the **second-lowest** in led suit when smother fell
through. F2 returns the **highest of 7/8/9** (specifically the
"duck" card by design).

For F2's narrow shape (K + 7/8/9 of led, e.g., `{KS, 9S}`):
- Rule 1B: `follow = {KS, 9S}`, sorted ascending → `[9S, KS]`,
  `sorted[2] = KS`. `wouldWin(KS) = true` → falls through to
  fallback → `lowestByRank({KS, 9S}) = 9S`.
- F2: returns `lowCard = 9S`.

Same card for this shape. For richer shapes (e.g., `{KS, 9S, 8S}`):
- Rule 1B: sorted `[8S, 9S, KS]`, sorted[2] = 9S. wouldWin(9S)=false → returns 9S.
- F2: lowCard = highest of {9S, 8S} = 9S.

Same card again. The "biggest mistake" semantic is partner-readable
either way.

### §3.5 F2 vs v3.1.9 trump-led-fragile-lock — Hokm-only, no conflict

v3.1.9 is Hokm-only (`contract.type == K.BID_HOKM`). F2 is Sun-only.
No overlap.

---

## §4 Placement options

| Option | Position | What it overrides | What shadows it | EV impact | Testability | Recommendation |
|---|---|---|---|---|---|---|
| **A** | Before Smother | Smother's K-donate at tricks 4-5 (probabilistic 30%/40% override) | Nothing in the partnerWinning block (it would be the first arm). At earlier branches before partnerWinning (e.g., Sun pos-4 Faranka at L3175) — irrelevant, those gate on lastSeat | **Speculative.** The unique-to-F2 case is "trick 4-5 K-replace-with-duck." Deception EV depends on opp's read of our discard, which Saudi-Master sims can probably estimate but isn't currently measured. | Deterministic stubs (math.random → 0.0 / 0.99) handle fire-case and no-fire-case (§5.2 Strategy 1). Source pins on `fireRate = 0.30 / 0.40` literals (Strategy 3) catch refactors. **Neither approach proves long-run rate or EV** — that gap is part of the deferral rationale, not a separate test-framework requirement. | NOT recommended for v3.2.4 without a deception-EV simulator. |
| **B** | After Smother, before Tahreeb | Tahreeb (irrelevant: voidInLed-mutually-exclusive with F2's hand-shape) | Smother — when its gateOk passes (`#pointCards >= 2` OR `completed >= 3` OR `lastSeat`), Smother returns K and F2 never fires. | F2 reaches only when Smother falls through (`#pointCards = 1` AND `completed < 3` AND not lastSeat) — tricks 2-3 with single point card. In this same window, **F5-3 also fires deterministically** and returns the same low card (per §3.3). F2's probabilistic gate adds nothing observable beyond F5-3. | Easy fire/no-fire stub, but the test would need to detect that F2 fired vs F5-3 fired — they produce identical cards, so observability is zero at the card level. Source-pin can confirm structural insertion but not behavioural effect. | NOT recommended — functionally indistinguishable from F5-3 in the reachable window. |
| **C** | After Tahreeb, before F5-3 | F5-3 — when F2 fires, F5-3 never reached. | Smother — same as Option B, Smother shadows when its gateOk passes. | Same as B: when F2 fires probabilistically and returns the duck low, F5-3 would have returned the same duck low. Observable effect is zero in the typical case. Only difference: F2 has narrower gates (partner-led-mid, indep-strength, etc.) so it would skip MORE often than F5-3 would; when F2 skips, F5-3 runs and returns the same low anyway. | Same as B. | NOT recommended — F5-3 already covers this; replacing it with F2 adds gating complexity for no behaviour change. |
| **D** | After F5-3, before Rule 1B | Rule 1B — when F2 fires, Rule 1B never reached. | F5-3 — F5-3 fires deterministically on F2's intended shape, so F2 is unreachable after F5-3. | Zero. F5-3 returns the low card first; F2 never gets a chance. | F2 wire-proof would **always fail post-relocation** (test asserts F2-specific output, but F5-3 returns first with the same output). Pre-relocation F2 is dead, post-relocation F2 is still dead-by-shadowing. | NOT recommended — F2 is dead-by-shadowing in this position. |

### §4.1 Summary

Only **Option A** produces observable F2-unique behaviour (Smother
override at tricks 4-5). Options B/C/D either shadow F2 by Smother
or render F2 indistinguishable from F5-3. The unique behaviour
under A is also the riskiest gameplay change (overriding the
canonical Takbeer donation 30%/40% of the time on a specific shape).

---

## §5 Probability / test framework

The 30%/40% RNG gate is the main test-design challenge.

### §5.1 Three test strategies considered

**Strategy 1: deterministic single-shot stubs (preferred where it works).**
Stub `math.random` to return `0.0` (forces fire) or `0.99` (forces
no-fire) before calling `Bot.PickPlay`. Same arity-aware shim used
in BE.1 / BF.9. Asserts the bot's return path:
- Fire stub → F2 returns lowCard
- No-fire stub → F2 falls through to next branch (whatever fires
  there — F5-3 under Option A, Smother under Option B-D — depends on
  placement and ordering)

**Pros:** zero flakiness, single-line assertion, matches existing
harness pattern.

**Cons:** doesn't verify the **rate** (30% vs 40% vs some other
threshold). If the runtime uses `math.random() < 0.20` by mistake,
the deterministic test stub still passes — the fire/no-fire boundary
is the same either way.

**Strategy 2: bounded multi-iteration statistical check.**
Loop the same fixture N times with `math.randomseed(known)`, count
fires, assert `fires/N` within `[fireRate - δ, fireRate + δ]`.

**Pros:** verifies the actual rate parameter.

**Cons:** slow (N=1000+ to keep δ < 5%), uses many `math.random` calls,
can be flaky if the seed is not perfectly controlled. Iteration count
becomes a magic number in the test.

**Strategy 3: source-pin the rate literals.**
`assertTrue(botSrc:find("fireRate = 0.30") ~= nil)`. Pins the literal
values 0.30 and 0.40 in source.

**Pros:** zero runtime cost, deterministic, catches refactors that
change the literal.

**Cons:** doesn't verify behaviour (the literal could be 0.30 but
the comparison flipped to `math.random() > fireRate` accidentally).

### §5.2 Recommended approach

Combine **Strategy 1 + Strategy 3** — same pattern as v3.2.2 BE
tests:

- 1 behavioural test with stub `math.random() = 0.0` → assert F2's
  lowCard is returned.
- 1 behavioural test with stub `math.random() = 0.99` → assert F2's
  fall-through branch returns instead (which under Option A is
  Smother's K).
- 1 behavioural test with `math.random()` returning some value
  between 0.30 and 0.40 → assert M3lm doesn't fire, Saudi-Master
  does. Two-state proof of the tier-graded rate.
- Source-pins on `fireRate = 0.30` and `fireRate = 0.40`.

Do **not** ship a bounded-iteration statistical check unless Codex
explicitly requests one. The Strategy 1 + Strategy 3 combination
gives full deterministic coverage with the harness pattern already
proven; flakiness risk is zero.

---

## §6 Behavioural test plan

If v3.2.4 proceeds with **Option A** (the only placement that
produces observable F2-unique behaviour):

Proposed section: **BG.** Test IDs BG.1 - BG.9.

| ID | Type | Fixture | Pre-relocation | Post-relocation |
|---|---|---|---|---|
| **BG.1** | behavioural | Sun pos-3, M3lm bidder team, partner led `JS`, opp pos-2 `7S`, hand `{KS, 9S, AH, ...}` (indep strength via AH; trick 4 so `completed=3`, Smother's gateOk via `completed>=3`). Stub `math.random()=0.0`. | **FAIL** (F2 dead → Smother returns KS) | **PASS** (F2 fires, returns 9S — overrides Smother) |
| **BG.2** | behavioural | Same as BG.1 but stub `math.random()=0.99` (no-fire). | PASS by accident (Smother returns KS, F2 doesn't fire either way pre-relocation) | PASS (F2 doesn't fire; Smother returns KS) |
| **BG.3** | behavioural | Saudi-Master variant: same fixture as BG.1 but `WHEREDNGNDB.saudiMasterBots=true`; stub `math.random()=0.35` (above 0.30, below 0.40). | depends on tier-routing; F2 dead → BotMaster.PickPlay path → unclear | **PASS** (F2 fires at 40% threshold; returns 9S) |
| **BG.4** | behavioural | M3lm variant: same fixture as BG.3 but `m3lmBots=true`, NOT `saudiMasterBots`. Stub `math.random()=0.35`. | FAIL (F2 dead) | **PASS** (F2 does NOT fire at 30% threshold, 0.35 > 0.30; Smother returns KS) |
| **BG.5** | behavioural | F5-3 + F2 overlap regression: Sun pos-3, M3lm, partner-led-mid, pos-4 void, hand `{KS, 9S, AH, ...}` at trick 2 (`completed=1`, Smother gateOk=false). Stub `math.random()=0.0`. | FAIL (F2 dead → F5-3 returns 9S anyway) | **PASS** if F2 wire-proof checks the *cause* (F2 marker present in trace), else **PASS BUT NOT WIRE-PROOF** (both F2 and F5-3 would return 9S). |
| **BG.6** | behavioural | Tahreeb non-overlap regression: Sun pos-3, M3lm, void in led (no K of led) → F2's `hasK=false` → F2 doesn't fire. Tahreeb's T-1/T-4 arms fire based on bySuit shape. | PASS pre-fix (Tahreeb fires regardless of F2) | PASS post-fix (F2's gate fails on hasK; Tahreeb fires) |
| **BG.7** | behavioural | Rule 1B semantic guard: same fixture as BG.1 but `pos4Void=false` (memory unset) → F2's `pos4CannotBeat=false` → F2 doesn't fire. | FAIL (Smother fires at completed>=3 → returns KS) | PASS (F2 doesn't fire; Smother returns KS) — Rule 1B not reached |
| **BG.8** | behavioural | non-clutch gate: same fixture but `S.s.cumulative.A = target - 5` (clutch) → F2's `nonClutch=false`. | n/a | PASS (F2 doesn't fire; Smother returns KS) |
| **BG.9** | source-pin (**5 sub-asserts**) | (a) marker `v3.2.4 F2`; (b) relocation noted; (c) `fireRate = 0.30` literal present; (d) `fireRate = 0.40` literal present; (e) old `v3.2.1 F2 UNREACHABLE` marker comment updated to point at relocation. | FAIL (markers absent) | PASS |

### §6.1 Test count + harness delta

8 behavioural assertion blocks (BG.1-BG.8) emitting **8 harness
checks** (each with one `assertEq` or `assertTrue`), plus BG.9
source-pin block with **5 sub-asserts**.

Total: **13 new harness checks**. Expected harness: 1,258 → **1,271**.

### §6.2 Pre-runtime failure expectation

**Exactly 10 failing checks** expected pre-runtime:
- BG.1, BG.3, BG.4, BG.5, BG.7 — behavioural (5 fails)
- BG.9a, BG.9b, BG.9c, BG.9d, BG.9e — source-pins (5 fails, all
  markers absent until relocation lands)

That gives **10 pre-runtime fails**, not 8. (BG.2, BG.6, BG.8 pass
pre-runtime because F2 dead = current behaviour matches their
expected outcomes.)

> **v0.2 amendment (post-Codex review):** v0.1 of this doc said
> "exactly 8 fails" but the listed BG fails sum to 10 (5
> behavioural + 5 source-pin sub-asserts). The arithmetic now
> agrees: 8 behavioural blocks (8 checks) + 5 source-pin sub-
> asserts = 13 new harness checks; 5 of the 8 behavioural checks
> + all 5 source-pin sub-asserts fail pre-runtime = 10 pre-runtime
> fails.

### §6.3 Test design concerns

- **BG.5 is not a wire-proof** under Option A: both F2-fire (returns
  9S) and F2-dead-but-F5-3-fires (also returns 9S) give the same
  card. A source-pin or marker-flag check would need to disambiguate.
- **BG.3 / BG.4 assume tier-graded probability** — if Saudi-Master's
  `BotMaster.PickPlay` ISMCTS-rollout path is active, the heuristic-
  layer F2 might never be reached. Need to verify `Bot._inRollout`
  semantics in the test fixture. This may require explicitly setting
  `Bot._inRollout = true` to force the heuristic-only path, or
  disabling Saudi-Master rollouts via `WHEREDNGNDB.saudiMasterBots =
  nil` for BG.3.

---

## §7 Stop conditions

If v3.2.4 proceeds, the implementation branch must STOP and re-design
if any of:

1. **BG.1 passes pre-runtime.** That means F2 is firing somewhere
   else (impossible — branch is currently unreachable). Fixture bug.
2. **BG.5's card-level assertion fails to distinguish F2 from F5-3
   post-relocation.** Both produce 9S in this shape; the test must
   either use a marker-flag check or be reclassified as
   "regression-guard, not wire-proof" (mirroring the v3.2.3 BF.7
   reclassification).
3. **BG.3 / BG.4 are flaky** because `math.random` stub doesn't
   fully control the fire-rate branch. Probability tests are the
   biggest flakiness risk; fall back to deterministic 0.0 / 0.99
   stubs and accept that the rate parameter isn't behaviourally
   verified.
4. **Any of the v3.2.3 BF.1-BF.9 tests regress** (F5-3 relocation
   tests). F2 sitting before F5-3 (Option A places F2 even before
   Smother) shouldn't affect F5-3's gates directly, but a placement
   mistake (e.g., F2 inside F5-3's enclosing block) could.
5. **Tahreeb sender tests (AS.* / AQ.*) regress.** Same logic — F2
   should be before Tahreeb in Option A, not inside it.
6. **F2 relocation touches anything outside Bot.lua + tests/test
   _state_bot.lua.** Per established v3.2.x scope discipline.
7. **The old dead F2 block at L4510-4670 isn't removed** as part of
   the relocation. Two copies would be a maintenance hazard.
8. **The v3.2.1 F2 unreachable marker comment isn't updated** to
   reflect the new state (either "relocated" or "remains
   intentionally dead pending future audit"). BG.9e source-pins this.

---

## §8 Recommendation

**Defer F2 indefinitely.** Specifically:

1. v3.2.3's F5-3 relocation already produces the canonical "duck low
   when K beats partner" behaviour deterministically on the must-
   follow case that constitutes ~95% of F2's intended fire window.
   See §3.3 for the side-by-side trace.

2. The F2-unique territory — Smother-override at tricks 4-5 with
   probabilistic firing — has speculative EV. The «تخليه يمسك»
   deception works only if opp doesn't already see we have K. At
   tricks 4-5 (after 3-4 prior plays), the opp's hand-distribution
   model is much better-informed than at trick 1; the deception
   value is diminished.

3. The only placement that produces F2-unique behaviour (Option A,
   before Smother) is the riskiest placement — it overrides the
   canonical Saudi Takbeer/Tasgheer donation. Codex review of this
   placement is non-trivial: it would need a deception-EV
   simulator to estimate the gain/loss tradeoff, and the harness
   doesn't currently have that.

4. The probabilistic gate (30%/40%) is testable enough at the
   fire / no-fire level via the deterministic stubs already proven
   in BE.1 / BF.9, plus source-pin coverage of the rate literals.
   What's NOT testable with that combination is the **long-run
   rate** (verifying that `0.30` is actually the observed fire
   frequency over many trials) — a bounded-iteration statistical
   check could pin it but is explicitly discouraged in §5.2
   (flakiness risk + iteration-count magic number). More
   importantly, neither approach measures **EV** — whether
   ducking K 30%/40% of the time is a net point gain or loss for
   the partnership. The EV gap, not a test-framework gap, is the
   primary deferral rationale.

### §8.1 Alternative narrow batch — RECOMMENDED if you want any v3.2.4 close-out

Doc-only update to the v3.2.1 F2 unreachable marker at
`Bot.lua:4533-4547`. Replace its "decision deferred to a separate
design pass" wording with a final-state note pointing at this design
doc and noting the v3.2.3 F5-3 redundancy. No runtime/test behaviour
change; the branch stays dead but the comment is no longer a TODO.

Estimated cost: 1 commit, ~15-20 lines of comment edit in Bot.lua,
0 new tests, harness delta 0. Branch name suggestion:
`f2-deferred-finalize-v3.2.4`.

### §8.2 Less-recommended alternative — full relocation Option A

If you decide F2's deception-play EV warrants a real attempt:

- Branch `f2-deception-relocation-v3.2.4` off `c96f120`.
- Place F2 **before Smother**, near the start of the live
  `if partnerWinning then` block at ~`Bot.lua:3367`. This is
  Option A from §4 — the only placement that produces observable
  F2-unique behaviour (Smother override at tricks 4-5 with a
  probabilistic gate).
- New ordering after Option A relocation:
  `F2 → Smother → Tahreeb → F5-3 → Rule 1B → trump-fragile-lock → Hokm non-trump → fallback`.
- Risks: see §4 (Option A row) and §7.
- Test budget: 13 new checks per §6.1, with 10 pre-runtime fails
  per §6.2.
- Codex would need to review whether the trick-4-5 K-donate
  replacement is a net EV gain, which needs a deception-EV
  simulator that doesn't exist yet.
- Recommended only if a deception-EV sim is built first.

### §8.3 Deferred questions / risks

1. **Deception-EV measurement gap.** No current sim can estimate
   the «تخليه يمسك» payoff vs Smother's K-donate. Without it, F2's
   Option A relocation is a guess.
2. **Tier-routing for Saudi-Master.** Saudi-Master plays through
   `BotMaster.PickPlay` (ISMCTS). The heuristic-layer F2 might be
   reached only via rollout policy. BG.3 fixture needs to clarify
   this — is F2 active during ISMCTS rollouts? If so, the 40% rate
   compounds against 30 worlds × 8 candidates × ~25 plays.
3. **Pre-flop / pre-bid memory state.** F2 requires `Bot._memory
   [pos4].void[lead]` set, which is populated by `OnPlayObserved`
   on observed plays. Fresh-deal fixtures need to manually seed
   this — same pattern as v3.2.3 BF tests.
4. **Bot.lua line drift.** F2's dead block is currently at L4510-
   4670. Removal would shift L4670+ upward by ~160 lines. Any
   v3.2.4 implementation needs to re-anchor its insertion points
   against post-v3.2.3 line numbers, not pre-v3.2.3.

---

## §9 Constraint compliance

- ✅ Design pass only.
- ✅ No edits to `Bot.lua`, tests, `.toc`, `.pkgmeta`, workflow,
  packaging.
- ✅ No CHANGELOG entry.
- ✅ No tag.
- ✅ No release.
- ✅ No branch cleanup.
- ✅ Experimental branches (`sprint-a-experimental`,
  `v0.5.1-experimental`) untouched.
- ✅ `.swarm_findings/v3_2_0_botlua_comment_audit.md` untouched.

Stop here for Codex review. Doc remains uncommitted unless the
prompt explicitly asks to commit after review.
