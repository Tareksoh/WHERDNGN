# S-Score-04 — Belote multiplier-immunity across the escalation ladder

**Agent:** S-Score-04
**Scope:** Verify CLAUDE.md / saudi-rules.md claim that Belote (K+Q of trump, +20) is multiplier-immune across the Bel ×2 → Triple ×3 → Four ×4 ladder. Belote +20 must be ADDED OUTSIDE the multiplier.
**Files:** `C:\CLAUDE\WHEREDNGN\Rules.lua`, `C:\CLAUDE\WHEREDNGN\Constants.lua`, `C:\CLAUDE\WHEREDNGN\docs\strategy\saudi-rules.md`
**Read-only.**

---

## 1. TL;DR

**YES — Belote IS multiplier-immune.** The arithmetic in `R.ScoreRound` is structurally correct and matches the canonical reading. The decisive lines are:

- `Rules.lua:926-927` — `rawA = (cardA + meldPoints.A) * mult` — cards + non-Belote melds get scaled.
- `Rules.lua:939-943` — `if belote == "A" then rawA = rawA + K.MELD_BELOTE` — Belote is added to `rawA` AFTER the multiplication, so it never sees `mult`.
- `Rules.lua:929-938` — explicit comment: *"Belote: independent +20 raw, applied AFTER the multiplier… Pagat: 'Baloot always 2 points unaffected' — Bel/Triple/Four/Sun multipliers do NOT scale the Belote bonus."*

The discriminating ×2/×3/×4 cases (Scenarios 2-4 below) all produce the multiplier-immune answer (22 / 32 / 42 gp), not the buggy "multiplied" answer (24 / 36 / 48 gp). The Sun gate at line 725 correctly prevents Belote scoring in Sun. The v0.9.0 M5 team-level cancellation is correctly wired at lines 769-777 and behaves correctly for the partner-quarte cancellation case.

**One pre-existing edge defect carries forward** from `B-Rules-02`: the sweep-override-then-cancellation order at lines 752-777 can resurrect a previously-cancelled Belote on a sweep. This is `F-01` in B-Rules-02; it does NOT change the multiplier-immunity verdict but is the only Belote-side bug in this code path. See §5.

**No new bugs found** specific to multiplier-immunity. The CLAUDE.md statement holds end-to-end across all four rungs.

---

## 2. Per-scenario arithmetic trace

All scenarios assume:
- Hokm contract, trump = H (unless noted).
- Bidder = team A. Bidder takes 7 of 8 tricks but defender takes 1 zero-point trick (so it's not a sweep).
- `cardA = 90` cards + `K.LAST_TRICK_BONUS = 10` last-trick = `100` raw (line 698-704).
- `cardB = 30` cards (defender takes one trick worth 30 raw — actually let's set cards so trick total checks out: card values sum to 152 in Hokm, defender takes 22, last-trick = 10 to bidder → bidder = 130, defender = 22; but for this trace we'll use bidder=100, defender=62 to match prompt math regardless of detailed card-value distribution. The exact split is not load-bearing — what matters is the multiplier behavior on bidder's side.).
- meldsByTeam = `{ A = {}, B = {} }` — no declared sequences/carrés.
- `meldA = meldB = 0` (line 711-712).
- `meldPoints.A = 0`, `meldPoints.B = 0` (line 713; in "made" branch they stay 0 because `R.CompareMelds` returns nil for empty sets at line 891-892).
- A holds K+Q of H → `belote = "A"` (line 736).
- `bidderTotal > oppTotal` → `outcome_kind = "make"` (line 807) → "made" branch at 885-893 → `cardA = teamPoints.A = 100`, `cardB = teamPoints.B = 62`.

**`div10(x) = math.floor((x + 5) / 10)`** (line 949).

`K.MULT_BASE = 1`, `K.MULT_BEL = 2`, `K.MULT_TRIPLE = 3`, `K.MULT_FOUR = 4`, `K.MELD_BELOTE = 20`. (`Constants.lua:68-71, 107`).

### Scenario 1 — Hokm + Belote (no escalation)

`mult = K.MULT_BASE = 1` (line 914; nothing escalated).

```
rawA = (100 + 0) * 1 = 100      ; line 926
rawA = rawA + 20    = 120        ; line 940 (belote = "A")
final.A = div10(120) = floor(125/10) = 12 gp   ; line 982
```

| Path | Answer |
|---|---|
| Multiplier-immune | `100×1÷10 + 20÷10 = 10 + 2 = 12` gp |
| Multiplied (alt) | `(100+20)×1÷10 = 12` gp |
| **Code-output** | **`12` gp** ← indistinguishable at ×1 |

Result: **CORRECT**. As prompt notes, the two formulations agree at ×1 — this case alone cannot discriminate.

### Scenario 2 — Hokm + Belote + Bel ×2 (THE DISCRIMINATING TEST)

Defenders Bel. `contract.doubled = true`. Line 923 (`elseif contract.doubled then mult = mult * K.MULT_BEL`) → `mult = 1 * 2 = 2`.

```
rawA = (100 + 0) * 2 = 200      ; line 926 — multiplier scales tricks
rawA = rawA + 20     = 220       ; line 940 — Belote added AFTER, multiplier-immune
final.A = div10(220) = floor(225/10) = 22 gp   ; line 982
```

| Path | Answer |
|---|---|
| Multiplier-immune (CLAUDE.md / saudi-rules.md claim) | `200÷10 + 20÷10 = 20 + 2 = 22` gp |
| Multiplied (BUG case) | `(100+20)×2÷10 = 240÷10 = 24` gp |
| **Code-output** | **`22` gp** ← matches multiplier-immune |

Result: **CORRECT**. This is the load-bearing test — code's `rawA = rawA + K.MELD_BELOTE` at line 940 happens AFTER `(cardA + meldPoints.A) * mult` at line 926, so the Belote +20 sees mult=1 effectively. Verdict: Belote is multiplier-immune at ×2.

### Scenario 3 — Hokm + Belote + Triple ×3

Bidder team Triples (counter to defender's Bel). `contract.tripled = true`. Line 922 → `mult = 1 * 3 = 3`.

```
rawA = (100 + 0) * 3 = 300      ; line 926
rawA = rawA + 20     = 320       ; line 940
final.A = div10(320) = floor(325/10) = 32 gp   ; line 982
```

| Path | Answer |
|---|---|
| Multiplier-immune | `300÷10 + 20÷10 = 30 + 2 = 32` gp |
| Multiplied (BUG) | `120×3÷10 = 36` gp |
| **Code-output** | **`32` gp** |

Result: **CORRECT**. Multiplier-immune at ×3.

### Scenario 4 — Hokm + Belote + Four ×4

Defenders counter the Triple with Four. `contract.foured = true`. Line 921 → `mult = 1 * 4 = 4`.

```
rawA = (100 + 0) * 4 = 400      ; line 926
rawA = rawA + 20     = 420       ; line 940
final.A = div10(420) = floor(425/10) = 42 gp   ; line 982
```

| Path | Answer |
|---|---|
| Multiplier-immune | `400÷10 + 20÷10 = 40 + 2 = 42` gp |
| Multiplied (BUG) | `120×4÷10 = 48` gp |
| **Code-output** | **`42` gp** |

Result: **CORRECT**. Multiplier-immune at ×4.

### Scenario 5 — Belote-cancellation (M5 follow-through)

Setup: Hokm-H. Seat 1 (team A) holds KH+QH; seat 3 (also team A — partner) declares a quarte-T (carré of Tens) worth `K.MELD_CARRE_T = 100`. So `meldsByTeam.A = { { value = 100, ... } }`. A wins the contract.

Line 711: `meldA = R.SumMeldValue(meldsByTeam.A) = 100`.
Line 736: `belote = "A"` (KH+QH same hand).
Line 745: no sweep.
Line 752-754: sweep-override skipped.
Lines 769-777: cancellation loop walks `meldsByTeam[belote] = meldsByTeam.A`. First meld has `value = 100 ≥ 100`, so `belote = nil; break`.

`mult = 2` (assume Bel'd round). `meldPoints.A = 100` (made branch + meldVerdict = "A").

```
rawA = (100 + 100) * 2 = 400    ; line 926
        ; line 939-943 skipped because belote == nil
final.A = div10(400) = 40 gp    ; line 982
```

**Pre-fix vs post-fix.** Per `B-Rules-02_scoreRound.md` line 53 and `saudi-rules.md` Q3b cascade note (lines 172-181), pre-v0.9.0 the cancellation predicate required `m.declaredBy == kWho` (same player), which:

1. Silently failed when `m.declaredBy` was nil (common — `R.DetectMelds` doesn't always populate declaredBy).
2. Silently ignored partner's ≥100 meld (this scenario — partner of K+Q-holder declared the quarte).

Pre-fix would have left `belote = "A"`, giving `rawA = 400 + 20 = 420`, `final.A = 42 gp` — a silent **+2 gp over-score**. Per the saudi rule "≥100 subsumes belote", the +20 should not exist this round. Post-fix v0.9.0 M5 is correct: walks the **team's** melds, ignores `declaredBy` entirely, cancels on any team-side `value ≥ 100`.

| Path | Answer |
|---|---|
| Pre-v0.9.0 (BUG) | `(100+100)×2÷10 + 20÷10 = 42` gp |
| Post-v0.9.0 M5 (correct) | `(100+100)×2÷10 = 40` gp |
| **Code-output (current)** | **`40` gp** |

Result: **CORRECT**. M5 fix is in place at lines 769-777. Player-level → team-level cancellation granularity is the documented v0.9.0 fix; current code matches the post-fix behavior.

**Cross-ref `B-State-05`:** confirms the pre-fix cascade — `declaredBy == kWho` predicate is gone, replaced with team-list walk. `_track_B_code/B-Rules-02_scoreRound.md` §"Belote cancellation" line 38 ("Cancellation: walk `meldsByTeam[belote]` and zero `belote` if any meld value ≥ 100") matches lines 769-777 verbatim. M5 is verified end-to-end.

### Scenario 6 — Belote in Sun (gate verification)

Setup: Sun contract (`contract.type == K.BID_SUN`). Seat 1 holds KH and QH (suit doesn't matter — there's no trump in Sun). Bidder makes the contract.

Line 725: `if contract.type == K.BID_HOKM and contract.trump then` — branch NOT taken because `contract.type ~= K.BID_HOKM`. The whole K+Q-of-trump scan at 727-734 is skipped. `belote` and `kWho` both stay nil.

Lines 752, 769, 789-790, 939-942 — all guarded by `belote ~= nil`. None fire.

```
rawA = (cardA + meldPoints.A) * mult    ; mult includes K.MULT_SUN = 2
       ; NO +20 anywhere
final.A = div10(rawA)
```

Result: **CORRECT**. Sun-K+Q does NOT score Belote in code. Matches `saudi-rules.md` Q1 (line 146-151): *"Q1: Belote (K+Q of trump) in Sun? ✗ NOT in code. R.ScoreRound line 694 gates Belote scoring on contract.type == K.BID_HOKM."* (Note: the line number drift — Q1 says 694, current code is 725. The gate has moved as the function grew, but the gate itself is intact.)

The single-source video #41 "ملكي K+Q in Sun" is an open question per Q1; deferred until a second Saudi source confirms. Current code's Hokm-only stance is the cautious default and is internally consistent.

---

## 3. Specific line citations

### Belote attribution and gate
- `Rules.lua:725` — `if contract.type == K.BID_HOKM and contract.trump then` — Hokm-only gate (Sun ✗).
- `Rules.lua:730-731` — scan all played cards; record `kWho`, `qWho` if trump K or Q.
- `Rules.lua:735-739` — same-seat check; if not same hand, clear `kWho` to disable cancellation lookup downstream.

### Sweep override
- `Rules.lua:752-754` — if a team sweeps and they're not the K+Q-holder team, redirect Belote to the sweeper. Saudi "winner takes all" reading.

### Belote cancellation (v0.9.0 M5 fix)
- `Rules.lua:769` — `if belote and kWho then` — only run if Belote exists and original holder was identified.
- `Rules.lua:770` — `local list = (meldsByTeam and meldsByTeam[belote]) or {}` — walks the **belote-target team's** melds (post-sweep-override). This is the F-01 pre-existing edge defect: should walk the **original** holder's team, not the post-redirect team. (Pre-v0.9.0 used `m.declaredBy == kWho`, which was player-level. v0.9.0 fixed it to team-level, but didn't address the sweep-redirect interaction.)
- `Rules.lua:771-776` — first meld with `value ≥ 100` cancels Belote.

### The multiplier (line 914-924)
- `Rules.lua:914` — `local mult = K.MULT_BASE` (= 1).
- `Rules.lua:915-918` — Sun branch: `mult = mult * K.MULT_SUN` then optional `* K.MULT_BEL`. **Sun ignores Triple/Four/Gahwa** per v0.10.0 R2.
- `Rules.lua:919-924` — Hokm branch: pick highest of Gahwa/Four/Triple/Bel via mutually-exclusive `elseif` chain. Only ONE escalation multiplier applies — they replace each other.

### THE LOAD-BEARING ARITHMETIC (lines 926-943)
- `Rules.lua:926` — **`local rawA = (cardA + meldPoints.A) * mult`** — multiplier scales `cardA + meldPoints.A`. **Belote NOT in `meldPoints` here**; it's a separate variable above.
- `Rules.lua:927` — same for B.
- `Rules.lua:929-938` — comment block declaring multiplier-immunity intent + audit-fix rationale (do NOT mutate meldPoints with the bonus, because the result struct exports meldPoints and a downstream caller could double-apply).
- `Rules.lua:939-943` — **`if belote == "A" then rawA = rawA + K.MELD_BELOTE elseif belote == "B" then rawB = rawB + K.MELD_BELOTE end`** — Belote +20 added AFTER the `* mult`. **This is the multiplier-immunity site.**
- `Rules.lua:949` — `local function div10(x) return math.floor((x + 5) / 10) end` — Saudi 5-rounds-UP.
- `Rules.lua:982` — `final = { A = div10(rawA), B = div10(rawB) }` — final game points.

### Constants
- `Constants.lua:107` — `K.MELD_BELOTE = 20` — the +20 raw.
- `Constants.lua:68-71` — `MULT_BASE = 1, MULT_SUN = 2, MULT_BEL = 2, MULT_TRIPLE = 3, MULT_FOUR = 4`.

---

## 4. Belote-cancellation correctness (M5 follow-through)

Reviewed against `_track_B_code/B-Rules-02_scoreRound.md` §F-01 + §"Belote cancellation" + saudi-rules.md Q3b cascade.

### What v0.9.0 M5 fixed (correctly)

Pre-v0.9.0 cancellation predicate: `if m.declaredBy == kWho and (m.value or 0) >= 100 then belote = nil`.

Two silent failure modes:
1. `m.declaredBy` was often nil (DetectMelds didn't always set it).
2. Partner's ≥100 meld was ignored — only the K+Q-holder's own ≥100 meld would cancel.

Post-v0.9.0 M5 fix (lines 769-777): walks `meldsByTeam[belote]` (the entire belote-target team's meld list) and cancels if ANY meld has `value ≥ 100`. Player-level → team-level granularity. **Verified correct in code.**

### What v0.9.0 M5 did NOT fix (F-01, pre-existing)

`B-Rules-02_scoreRound.md` §F-01 (medium severity): the cancellation walk happens AFTER the sweep-override (line 752-754), so it walks the **post-redirect** team's melds, not the **original** K+Q-holder's team's melds. Per PDF 02 line 140 ("ويلغى اذا كان معه مشروع المئة فقط"), Saudi cancellation is a property of the original Belote declaration — it should be cancelled at declaration, not contingent on which team eventually receives the +20.

**Concrete failure case from B-Rules-02:**
- Hokm-H. Seat 2 (team B) holds KH+QH AND a 5-card heart sequence (seq5 = 100). Per Saudi: B's belote is cancelled at declaration.
- A sweeps (8/8 tricks).
- Code: `belote = "B"` → sweep-override → `belote = "A"` → cancellation walks `meldsByTeam.A` (which is empty) → `belote` stays "A" → `rawA = 250 + 20 = 270`.
- Per Saudi (cancellation-is-permanent reading): no +20 should exist. `rawA = 250`.
- **Off by +2 gp** in this rare configuration.

**This bug pre-dates v0.10.2** and is documented in `B-Rules-02 §F-01`. **Not introduced by M5 fix; not a multiplier-immunity bug.** F-01 is the same `belote` reference being read twice (sweep-redirect target vs. cancellation lookup) — the M5 fix changed the cancellation predicate (player→team) but kept the sweep-then-cancel ordering.

### Recommended (out of scope for this audit)

Per B-Rules-02 §F-01: cache `originalBeloteTeam = R.TeamOf(kWho)` BEFORE the sweep override, then run cancellation against the original-holder team's melds. Or move the cancellation entirely BEFORE the sweep override.

---

## 5. Bugs found

### New bugs introduced by this audit

**None.** The multiplier-immunity invariant is structurally and arithmetically correct across all 6 scenarios.

### Pre-existing edge defect (cross-referenced from B-Rules-02 §F-01)

| Severity | Location | Description |
|---|---|---|
| MEDIUM | `Rules.lua:752-777` | Sweep-override happens BEFORE Belote-cancellation lookup. If K+Q-holder's team has a ≥100 meld but loses the contract via sweep, the cancellation check walks the sweeper's melds (not the K+Q-holder's), so a previously-cancelled Belote can be resurrected. Off by **+2 gp** when triggered. Saudi-rule reading: cancellation should be permanent at declaration. **This is F-01 in B-Rules-02_scoreRound.md, already documented; NOT a multiplier-immunity issue.** |

### CLAUDE.md / saudi-rules.md verbiage check

CLAUDE.md (lines 50-51): *"Belote (K+Q of trump, +20) is multiplier-immune. A ×4 round doesn't ×4 the Belote bonus."* — **HOLDS.**

saudi-rules.md (lines 60-61, 56, 247-248): *"Belote is multiplier-immune. Even if the round goes ×4, the +20 K+Q-of-trump bonus stays at +20."*, *"Belote (K+Q trump) | 20 — K.MELD_BELOTE, scored independently of multiplier"*, *"Multiplier scope: ×2/×3/×4 applies to the trick-point side of the score. Belote +20 is multiplier-immune."* — **ALL HOLD.**

video #43 (`-QrykaZdosE_43_score_calculation`): tutorial confirms `÷10` for Hokm, `÷5` for Sun (= ×Sun÷10 algebraically), and Belote = 20 raw → 2 nuqat in Hokm, 4 nuqat in Sun. The video doesn't explicitly call out multiplier-immunity (the tutorial doesn't cover Bel/Triple/Four), but the per-meld conversion table at line 30 of `43_score_calculation_extracted.md` matches code.

### Test-coverage gap (cross-ref B-Rules-02 §F-07)

`tests/test_rules.lua` Section J covers Belote attribution, sweep-override, holder's-own-100-meld cancels, and partner's-100-meld cancels (M5 verified). **BUT** there is no test that pins the multiplier-immunity property at ×3 (Triple) or ×4 (Four) specifically. Section J only exercises ×1 base + ×2 Bel implicitly through other tests. **Recommend adding a discriminating ×4 test** that asserts `final = 42` (immune) vs `final = 48` (multiplied) — this would lock down the invariant against future regressions in the multiplier path.

Suggested test (illustrative, not patch):
```lua
-- Hokm + Bel + Triple + Four chain, A holds K+Q trump, A makes 90+10
local res = R.ScoreRound(tricks, hokmFoured("H", 1), { A = {}, B = {} })
assertEq(res.multiplier, 4, "Four mult = 4")
assertEq(res.belote, "A", "A holds K+Q of H")
assertEq(res.raw.A, 100 * 4 + 20, "Four ×4 + Belote immune raw = 420")
assertEq(res.final.A, 42, "Four ×4 + Belote immune final = 42 gp (NOT 48)")
```

---

## Cross-references

- `_track_B_code/B-Rules-02_scoreRound.md` — base ScoreRound walk-through; §F-01 sweep+cancellation order defect; §"Belote cancellation" M5 verification.
- `_track_B_code/B-State-05_scoreRound_full.md` — state-machine view of ScoreRound entry.
- `_track_B_code/B-Rules-05_canBel.md` — Bel-call legality (≥100 gate); not directly multiplier-related but adjacent in Bel/Belote terminology.
- `review_v0.10.0/REVIEW.md:306` — *"✅ Belote team-level cancellation (v0.9.0 M5) at Rules.lua:713-721"* (line numbers have drifted to 769-777 in current code).
- `docs/strategy/saudi-rules.md:56, 60-61, 146-151, 247-248` — multiplier-immunity claim + Sun-Belote Q1 + scoring quirks.
- `docs/strategy/_transcripts/43_score_calculation_extracted.md` — video #43 Saudi scoring verbatim; rows 9-10 of rule table give the per-contract ÷5/÷10 and Belote 20→2/4 conversion.
- `CLAUDE.md:50-51` — explicit multiplier-immunity statement in repo guidance.
- `Constants.lua:68-71, 107` — multiplier and Belote-value constants.
- `tests/test_rules.lua:486` — single existing assertion that consumes `K.MELD_BELOTE` against `res.raw.A`; covers sweep+belote attribution but not the multiplier-immunity property at ×3/×4.

---

## Verdict

CLAUDE.md and saudi-rules.md both hold: **Belote +20 is multiplier-immune.** Code at `Rules.lua:926-943` implements this correctly via post-multiplication addition. All four rungs of the escalation ladder (×1 / ×2 / ×3 / ×4) produce the immune answer. M5 team-level cancellation is correctly wired. Sun gate at line 725 correctly suppresses Belote in non-Hokm contracts.

The only Belote-side defect in this code path is the pre-existing F-01 sweep-override-then-cancellation order issue — which is documented in B-Rules-02, is not a multiplier-immunity bug, and falls outside this audit's scope.

**No new bugs found. The end-to-end invariant holds.**
