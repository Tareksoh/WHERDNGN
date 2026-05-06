# S-Score-02 — End-to-end Sun scoring trace (v0.10.2)

## TL;DR

- The Sun ÷10 pipeline composes correctly with the ×2 multiplier — `K.MULT_SUN = 2` is applied in the same `mult` register as `K.MULT_BEL` (Rules.lua:914-924), then `rawA / rawB = (cardA + meldPoints.A) * mult` (Rules.lua:926-927), then `div10 = math.floor((x + 5) / 10)` (Rules.lua:949). All 6 scenarios produce the canonical Saudi values.
- **Sun-Bel composition (Scenario 2): COMPOUNDS to ×4 in code** (`K.MULT_SUN * K.MULT_BEL = 4`). This matches the test fixture at `test_rules.lua:715` ("Sun × Bel = 4 (Sun's only rung)") and the line 904-924 multiplier block.
- The "intentionally ignore tripled/foured/gahwa on Sun" comment at `Rules.lua:918` does NOT touch the Bel rung — the Sun branch explicitly applies `mult = mult * K.MULT_BEL` if `contract.doubled` (line 917). Doubled is preserved; only Triple/Four/Gahwa are silently collapsed.
- **The Belote-in-Sun gate (CLAUDE.md task said "Rules.lua:694") is at `Rules.lua:725`** (`if contract.type == K.BID_HOKM and contract.trump then`). Sun never assigns `belote`. saudi-rules.md Q1 still has the line-694 reference; that's stale doc-drift (also seen in `B-Rules-02_scoreRound.md` where line numbers in task description differ by ~30 from current head).
- One known **doc-vs-test arithmetic mismatch in CLAUDE.md**: CLAUDE.md says "Sun contracts have a ×2 multiplier" + "Bidder fails on tied 81/162" — the 81/162 phrasing is Hokm-specific. For Sun, the strict-majority threshold is 65 raw of 130 (pre-Sun-mult). Confirmed by Section I tests at `test_rules.lua:553-559` ("Tie no-escalation: defender raw = 130 × 2 = 260").
- All 6 scenarios trace cleanly to expected values; no new bugs found beyond the issues already catalogued in `B-Rules-02_scoreRound.md` (F-01 sweep+belote-cancellation order, F-03 Sun+stale-gahwa, F-04/F-08 nil defenses).

---

## Per-scenario trace

### Scenario 1 — Vanilla Sun, bidder makes (90 raw bidder / 40 raw defender)

**Setup.** Hokm-style 8-trick play; bidder team takes 80 raw + 10 last-trick = 90 raw of card points; defenders take 40 raw. No melds, no belote (Sun has no Belote per Rules.lua:725 gate). Contract: `{ type = K.BID_SUN, bidder = 1 }` (no doubled flag).

**Code path through `R.ScoreRound`:**

| Step | Line | Computation | Result |
|---|---|---|---|
| `handTotal` | 707 | `K.HAND_TOTAL_SUN` (because `contract.type == K.BID_SUN`) | `130` |
| `bidderTeam` | 708 | `R.TeamOf(1)` | `"A"` |
| Belote detection | 723-740 | gated on `K.BID_HOKM` | `belote = nil` |
| Sweep detection | 742-745 | neither team won 8/8 | `sweepTeam = nil` |
| Threshold | 794-797 | `bidderTotal = 90 + 0 = 90`, `oppTotal = 40 + 0 = 40` | bidder > opp |
| `outcome_kind` | 806-807 | `bidderTotal > oppTotal` | `"make"` |
| `bidderMade` | 845 | `outcome_kind == "make"` | `true` |
| Branch (make) | 885-892 | `cardA = 90`, `cardB = 40`, no meldPoints | |
| Multiplier | 914-918 | Sun branch: `mult = K.MULT_BASE * K.MULT_SUN = 1 * 2` | `mult = 2` |
| `rawA` | 926 | `(90 + 0) * 2` | `180` |
| `rawB` | 927 | `(40 + 0) * 2` | `80` |
| `final.A` | 949, 982 | `floor((180 + 5)/10)` | `18` ✓ |
| `final.B` | 949, 982 | `floor((80 + 5)/10)` | `8` ✓ |

**Verification against video #43 (lines 1480-1505):** speaker says "احنا قلنا عدد نقاط الصن 26 انت اخذت ثمانيه كم باقي من 26 26 ناقص ثمانيه باقي 18 نقطه راح ياخذها المشتري" — "Sun's total points are 26, you took 8, 26 - 8 = 18 game points to the buyer". For an 18 gp bidder + 8 gp defender split, opponent had 40 raw card points (and bidder 90 raw). Matches my trace exactly. ✓

**Sun×2-and-÷10 vs Hokm composition.** The two contract types share the same `(rawA + 5) / 10` rounding (line 949). For Sun the multiplier (2) is baked into raw BEFORE `div10`. The user's question "does ×2 compose with `(x+5)/10` the same as Hokm?" — yes, because both follow the formula `final = floor((raw + 5)/10)` and `raw = teamPoints * mult`. The Sun handling is a `mult` adjustment, not a separate division pipe. (The deferred "abnat" rule mentioned at v0.4.3 CHANGELOG:4249-4256 — "round to nearest 10 preserving units-5, then ÷5" — is a known ±1 boundary defect for raw values ending in 3 or 6, but is NOT the canonical pipeline implemented today.)

---

### Scenario 2 — Sun + Bel (Sun-Bel allowance, 90 raw bidder)

**Setup.** Sun contract, `contract.doubled = true` (Sun-Bel triggered per the score-split gate `R.CanBel`). Bidder team takes 90 raw; defenders 40 raw. (Whether this is legally reachable per cumulative gate is enforced upstream by `R.CanBel`, Rules.lua:554-592 — the score-split predicate. We trust the ScoreRound assumes it's been validly called.)

**Multiplier register (Rules.lua:914-918):**

```lua
local mult = K.MULT_BASE                       -- 1
if contract.type == K.BID_SUN then
    mult = mult * K.MULT_SUN                   -- 1 * 2 = 2
    if contract.doubled then
        mult = mult * K.MULT_BEL               -- 2 * 2 = 4
    end
    -- intentionally ignore tripled/foured/gahwa on Sun
else ...
end
```

**Final:** `mult = 4`, `rawA = 90 * 4 = 360`, `final.A = floor((360+5)/10) = 36`. Defender side `rawB = 40 * 4 = 160`, `final.B = 16`.

**Sun-Bel composition verdict: COMPOUNDS, not collapses.** The "Sun ALSO collapses Bel" hypothesis from the task description is FALSE. The line 918 comment "intentionally ignore tripled/foured/gahwa on Sun" omits doubled by design — the line 917 conditional explicitly applies `mult * K.MULT_BEL` for Sun-doubled. The pre-comment block at lines 904-913 is explicit: "Sun has NO Triple/Four/Gahwa rungs ... the multiplier path applied K.MULT_SUN * K.MULT_TRIPLE (×6) etc. — encoded an invariant violation ... Now those rungs are silently ignored on Sun." Triple/Four/Gahwa collapse; Bel does not.

Test pin: `test_rules.lua:712-716`:
```lua
local c = sun(1, { doubled = true })
local res = R.ScoreRound(sweptTricks(1), c, { A = {}, B = {} })
assertEq(res.multiplier, K.MULT_SUN * K.MULT_BEL,
         "Sun × Bel = 4 (Sun's only rung)")
```

So the task's "should be 90 × 2 (Sun) × 2 (Bel) ÷ 10 = 36 gp?" expectation is correct — this is the actual code behavior. ✓

**Tie inversion under Sun-Bel** (also tested at `test_rules.lua:561-569`):
- Tied 65/65: bidder is no longer the buyer (defender doubled), so tie inverts to `take`. Bidder takes `handTotal × mult = 130 * 4 = 520 raw / div10 = 52 gp`.
- This is verified by the assertion `res.raw.A == K.HAND_TOTAL_SUN * K.MULT_SUN * K.MULT_BEL` (= 520). ✓

---

### Scenario 3 — Sun + Carré-A = 400

**Setup.** Bidder seat 1 holds 4 Aces; declares meld in trick 1. `meldsByTeam.A = { { kind="carre", value=400, top="A", ... } }`. Sun contract un-doubled. Bidder takes 90 raw card points (assume same trick distribution as scenario 1).

**Code path:**

| Step | Line | Computation | Result |
|---|---|---|---|
| `R.DetectMelds` (called pre-ScoreRound) | 304-318 | rank=A, count=4, isSun=true → `value = K.MELD_CARRE_A_SUN = 400` | `{ value=400, kind="carre" }` |
| `meldA` | 711 | `R.SumMeldValue(meldsByTeam.A)` | `400` |
| `meldVerdict` | 791 | `R.CompareMelds`: A has carré (rank ≥1000), B has none | `"A"` |
| `effMeldA` | 792 | `(meldVerdict == "A") and 400 or 0` | `400` |
| `bidderTotal` | 794 | `90 + 400` (bidder is A, +effMeldA) | `490` |
| `oppTotal` | 796 | `40 + 0` | `40` |
| `outcome_kind` | 806 | `bidderTotal > oppTotal` | `"make"` |
| Branch (make, line 885-892) | | `cardA = 90, cardB = 40, meldPoints.A = 400` | |
| `mult` (Sun, no Bel) | 914-918 | `1 * 2` | `2` |
| `rawA` | 926 | `(90 + 400) * 2` | `980` |
| `rawB` | 927 | `(40 + 0) * 2` | `80` |
| `final.A` | 982 | `floor((980+5)/10)` | `98` |
| `final.B` | 982 | `floor((80+5)/10)` | `8` |

**Carré-A standalone (no other tricks):** the task asks specifically about the `400 × 2 / 10 = 80 gp` claim. That works **only if `cardA = 0`** (Carré-A meld and zero card points). With 90 raw of card points, A also gets the trick share. The 80 gp value is the **meld's contribution alone** — confirmed by B-Rules-02 F-09 verification ("With cardA = 0 (hypothetical), rawA = 800. div10 = 80"). So:

- **Carré-A meld alone, Sun, no doubling:** `(0 + 400) * 2 / 10 = 80 gp` ✓
- **Carré-A meld + 90 raw card points, Sun, no doubling:** `(90 + 400) * 2 / 10 = 98 gp` (real round)
- **Carré-A meld + Sun + Bel (×4):** `(0 + 400) * 4 / 10 = 160 gp` (purely meld; or with cardA=90 → `490 * 4 / 10 = 196 gp`)

**Re Rules.lua:887 / "intentionally ignore tripled/foured/gahwa on Sun" — does it skip Sun's ×2 anywhere?** **No.** The Sun ×2 mult is applied unconditionally at line 916 (`mult = mult * K.MULT_SUN`). The "ignore" comment at line 918 applies only to the four `tripled / foured / gahwa` conditionals — and those are completely absent from the `if contract.type == K.BID_SUN then` block. The Bel rung is preserved at line 917. So `K.MULT_SUN` always multiplies; the Carré-A pipeline produces 80 raw at the meld level → 80 gp final, exactly as CHANGELOG v0.10.0 R5 promised.

---

### Scenario 4 — Sun bidder fails (tied 65/130)

**Setup.** Bidder team A and defender team B each take 65 raw card points (tied). 60 raw of trick + 10 last-trick goes to whoever wins trick 8; let's say B gets last-trick (so trickPoints.A = 65 from cards, trickPoints.B = 55 + 10 = 65). No melds, no doubling, no Belote (Sun).

**Code path:**

| Step | Line | Computation | Result |
|---|---|---|---|
| `bidderTotal` | 794 | `65 + 0` (no melds) | `65` |
| `oppTotal` | 796 | `65 + 0` | `65` |
| Tied path | 810-843 | `highest = "none"` (Sun, not doubled) | |
| Tied: highest="none" → "fail" | 838-842 | `outcome_kind = "fail"` | |
| `bidderMade` | 845 | `false` | |
| Branch (fail, line 854-871) | | `cardA = 0, cardB = 130 (handTotal)` | |
| `meldPoints` | 870-871 | each team keeps own melds (here: zero) | |
| `mult` (Sun, un-doubled) | 916 | `1 * 2` | `2` |
| `rawA` | 926 | `(0 + 0) * 2` | `0` |
| `rawB` | 927 | `(130 + 0) * 2` | `260` |
| `final.A` | 982 | `0` | `0` |
| `final.B` | 982 | `floor((260+5)/10)` | `26` ✓ |

**Comparison Sun-fail vs Hokm-fail:**
- Sun: `130 * 2 / 10 = 26 gp` defender qaid
- Hokm: `162 * 1 / 10 = 16 gp` defender qaid

The task notes "Sun fail is MORE PUNISHING (26 vs 16)". This is **correct per source** — Sun has higher stakes both ways. CHANGELOG v0.4.3:4262 confirms the hand-total split (162 Hokm, 130 Sun). Video #43 framing: defender takes 26 nq for Sun, 16 nq for Hokm — exact match.

The strict-majority logic: **bidder must STRICTLY beat defender** (line 779-788 + 806-810). 65/65 is a tie. Tie under no-escalation → "fail" (line 837-842, "no escalation → bidder is buyer → fail (def takes)"). This is the Saudi 4-10 rule.

The bidder's melds are PRESERVED on fail (line 870-871, `meldPoints.A = meldA, meldPoints.B = meldB`) per v0.4.3 "مشروعي لي ولك مشروعك". Here both are zero. ✓

---

### Scenario 5 — Sun bidder fails + bidder Bel'd (rule 4-10 inversion at 64/130)

**Wait — re-read the scenario.** "Bidder Bel'd" — but in code, only DEFENDERS Bel (the bidder team responds to a defender's Bel by Tripling). For Sun though, only Bel exists per "intentionally ignore tripled/foured/gahwa". So the scenario as worded is impossible: the bidder cannot Bel their own contract. Re-interpreting as "bidder failed at 64/130 with Sun-Bel contract (defender Bel'd)":

**Setup.** Defender Bel'd (legally, via score-split — say A=70, B=120 cumulative; B is bidder, A is at <100 trailing → A may Bel. Wait, B is bidder. For Bel: caller ≤ 100 AND opposite > 100. So defender team A (cum=70) Bels B's Sun. Bidder = team B's seat. Bidder takes 64 raw card points. Defenders take 66 raw (= 56 + 10 last). `contract.doubled = true`.

**Code path:**

| Step | Line | Computation | Result |
|---|---|---|---|
| `bidderTotal` | 794 | `64 + 0` (no melds) | `64` |
| `oppTotal` | 796 | `66 + 0` | `66` |
| `outcome_kind` | 808 | `bidderTotal < oppTotal` | `"fail"` |
| Branch (fail, line 854-871) | | `cardA(B) = 0, cardB(A=opp) = 130` | |
| `mult` (Sun + Bel) | 916-917 | `1 * 2 * 2` | `4` |
| `rawB(opp=A)` | 927 | `(130 + 0) * 4` | `520` |
| `final.A` (defender) | 982 | `floor((520+5)/10)` | `52` |

But the task scenario says "Bidder Bel'd, then failed at 64/130 → doubled tie inversion". A 64 vs 66 is NOT tied — it's a clean fail. **A doubled-tie inversion only triggers on EXACT TIE.** Re-interpret as 65/65 + bidder doubled:

**Re-trace, tied 65/65 + Sun-Bel:**

| Step | Computation | Result |
|---|---|---|
| `bidderTotal` | `65` | |
| `oppTotal` | `65` | |
| Tied → `highest` | Sun + doubled → `"double"` (line 832) | `"double"` |
| `outcome_kind` | line 838-839: `if highest == "double" or "four" then take` | `"take"` |
| `bidderMade` | true | |
| Branch (take, line 872-884) | `cardA(bidder=A) = 130, cardB(opp) = 0`, melds preserved | |
| `mult` | Sun + Bel | `4` |
| `rawA` | `(130 + 0) * 4` | `520` |
| `final.A` | `floor((520+5)/10)` | `52` |
| `final.B` | `0` | `0` |

This matches `test_rules.lua:561-569` ("Tie doubled: bidder raw = 130×2×2 = 520"). The take branch correctly applies Sun×Bel multiplier. ✓

**Re Rules.lua:891 / "elseif contract.tripled then mult = mult * K.MULT_TRIPLE":** that line 922 conditional is in the **Hokm branch** (line 919 `else`). It's never reached for Sun. The Sun→Bel composition at line 917 is the only path the Sun multiplier takes. Correctly handled.

**Re cardA/cardB attribution flips per the task's "Bidder takes the full handTotal":** YES, line 881-884. The "take" branch sets `cardA = (bidderTeam == "A") and handTotal or 0`. Since bidder is team B in our re-interpretation (or team A in the test fixture), the bidder team gets the handTotal qaid. Then the multiplier (Sun×Bel = 4) applies, then div10. 130 × 4 / 10 = 52. ✓

---

### Scenario 6 — Sun + Belote? (Belote is Hokm-only)

**Setup.** Sun contract, regardless of whether seat 1 holds K+Q of any suit (Sun has no trump). Verify the gate at Rules.lua:725 rejects Sun.

**Code:**
```lua
-- Belote (K+Q of trump in same hand) — Hokm only, scored independently
-- of the contract result. Detect by scanning who played which card.
...
local belote = nil
local kWho
if contract.type == K.BID_HOKM and contract.trump then     -- Rules.lua:725
    -- ... scan plays for K and Q of trump ...
end
```

For Sun: the entire `if`-block is skipped. `belote = nil` permanently. Subsequent code:
- Line 752 sweep override: `if sweepTeam and belote and ...` → `belote = nil`, no effect.
- Line 769 cancellation check: `if belote and kWho then` → `belote = nil`, no effect.
- Line 789-790 threshold beloteA/B: both 0.
- Line 939-942 post-mult belote +20: neither branch fires.

**Verdict:** Sun never gets a Belote bonus. Saudi-rules.md Q1 documents this as "single-source from video #41 says K+Q meld scores in Sun. Could be regional house variant. Open question." The current code is canonical: Belote is Hokm-only. Confirmed.

(Side note: the saudi-rules.md Q1 line reference says `R.ScoreRound line 694` but the actual gate is line 725. This is doc-drift from before v0.10.x — the function has shifted by ~30 lines since the doc was written. Worth noting in F-06 follow-up.)

---

## Sun-Bel composition verdict (consolidated)

**Sun-Bel COMPOUNDS (×4), not collapses.**

| Multiplier path | Code line | Sun-doubled | Sun-tripled (stale) | Sun-foured (stale) | Sun-gahwa (stale) |
|---|---|---|---|---|---|
| Hokm | 919-923 | ×2 | ×3 | ×4 | ×4 (mult kept; gahwa wins match) |
| Sun | 914-918 | **×4** (Sun×Bel) | **×4** (collapsed via doubled) | **×4** (collapsed via doubled) | **×4** (collapsed via doubled) |

The Sun branch's only multiplier inputs are `K.MULT_SUN` (always) and `K.MULT_BEL` (if doubled). Triple/Four/Gahwa flags are silently ignored. If a Sun contract somehow has `tripled = true` but `doubled = false` (an off-canonical state — phase machine prevents it but stale resync could surface it), `mult` would be just `K.MULT_SUN = 2` because the Triple branch never fires.

This means:
- **Sun-Triple-without-Bel (stale):** mult=2 (only Sun ×2)
- **Sun-Bel-Triple (stale):** mult=4 (Sun×Bel; Triple ignored)
- **Sun-Bel-Triple-Four (stale):** mult=4 (Sun×Bel; Four ignored)
- **Sun-Bel-Triple-Four-Gahwa (stale):** mult=4 (Sun×Bel; Four ignored)

But — important asymmetry — `gahwaWonGame` at line 957-967 fires unconditionally on `if contract.gahwa then`. **A Sun contract with stale `gahwa = true` STILL triggers a match-win signal**, because the Gahwa branch was not parallel-collapsed by the R2 fix. This is `B-Rules-02_scoreRound.md` F-03 (medium severity).

---

## Bugs / open questions

### Confirmed pre-existing

1. **F-03 from B-Rules-02 (HIGH confidence on gap, MEDIUM on impact):** Sun + stale `gahwa = true` flag triggers `gahwaWonGame = true` despite Sun having no Gahwa rung. The R2 multiplier collapse (line 904-913) and the inversion-collapse (line 825-832) BOTH explicitly normalize stale Sun rungs, but the gahwa match-win branch (line 957-967) does not. Recommend wrapping line 959 in `if contract.type == K.BID_HOKM and contract.gahwa then`. Re-confirmed for S-Score-02; impact would be a phantom match-win on a Sun resync edge case.

2. **F-01 from B-Rules-02 (MEDIUM confidence):** Sweep override of belote then cancellation can resurrect a previously-cancelled belote. Sun is unaffected (no belote in Sun). Hokm-only.

### New findings (S-Score-02 specific)

3. **Doc-drift: saudi-rules.md Q1 cites `R.ScoreRound line 694` but the actual Belote gate is at `Rules.lua:725`.** The function has migrated since the comment was written. Fix: update the line reference. Confidence HIGH.

4. **CLAUDE.md text says "Bidder fails on tied 81/162" without distinguishing Sun's 65/130 strict-majority threshold.** Sun strict-majority threshold for "tied → fail" branch is 65 raw of 130 (NOT 81/162). For Sun-Bel-tied (the scenario 5 inversion): also 65/130, but inversion gives bidder 130 × Sun×Bel = 520 raw → 52 gp. The 81/162 phrasing is exactly half of Hokm's 162; the corresponding Sun-equivalent half is 65 of 130. Recommend clarifying CLAUDE.md to mention both thresholds. Confidence HIGH.

5. **Carré-A in Sun pipeline self-consistency: 400 raw × Sun-mult-2 ÷ 10 = 80 gp.** Verified at the meld level with cardA=0. With realistic card points, the meld and tricks both flow through `(card + meld) * mult / 10`. The R5 fix's promise holds. Confidence HIGH (matches video #38 line 27-31 "الأربع مئة" = 80 nq).

6. **Sun divisor framing: video #43 says "÷5" for Sun melds, code says "× 2 ÷ 10".** These are mathematically equivalent (`× 2 ÷ 10 = ÷ 5`). The inline comment at Constants.lua:97-106 makes this explicit ("Per video #43 the Sun divisor is 5; raw 400 ÷ 5 = 80 game points. Code's `meldRaw × Sun×2 / div10` pipeline correctly produces 80 gp"). The two formulations are interchangeable for this rounding direction. Confidence HIGH.

### Test coverage gap (re-flagged from B-Rules-02 F-07)

7. **No test passes a non-trivial meld `{value=400}` through `ScoreRound` for an integration test of the Carré-A in Sun pipeline.** Section J tests use `value=100` directly; Section K tests don't include meld values. R5 verification is mathematical (calculator) not integration-tested. Recommend adding to Section K:
   ```lua
   do
       local c = sun(1)
       local meldsByTeam = {
           A = { { kind="carre", value=400, top="A" } },
           B = {},
       }
       local res = R.ScoreRound(sweptTricks(2), c, meldsByTeam)
       -- B sweeps; A's melds are forfeited per sweep branch (line 852-853)
       -- but if A wins, expect: rawA = (cardA + 400) * 2
       ...
   end
   ```

### Open question (deferred)

8. **Sun-Bel allowance condition (per video #11 "post-overcall AND behind team OR cumulative ≥100").** The task description references this. Code's `R.CanBel` (Rules.lua:554-592) implements the score-split predicate (caller ≤ 100, opposite > 100). The "post-overcall" gating is enforced upstream in the phase machine (PHASE_OVERCALL → PHASE_DOUBLE), not in `R.CanBel` itself. ScoreRound only sees the resolved `doubled` boolean. Verified: if `R.CanBel` lets it through, ScoreRound's multiplier composition is correct.

---

## Recommendations

1. **(LOW — doc only):** Update `saudi-rules.md` Q1 line reference from "694" to "725". Drift is innocuous but misleading for future readers.

2. **(LOW — doc only):** Update CLAUDE.md "Important non-obvious rules" section to add Sun strict-majority threshold (65/130) alongside the existing Hokm 81/162 statement. Two sibling lines:
   - "Bidder fails on tied 81/162 in Hokm" (existing)
   - "Bidder fails on tied 65/130 in Sun (raw, pre-multiplier)" (new)

3. **(MEDIUM — defensive code):** Wrap the gahwa match-win branch (Rules.lua:959-967) in `if contract.type == K.BID_HOKM and contract.gahwa then` to parallel-collapse stale Sun-gahwa flags, mirroring the R2 multiplier collapse and inversion collapse. (Re-flagging B-Rules-02 F-03.)

4. **(LOW — coverage):** Add Section K tests for Carré-A in Sun (value=400 through `R.ScoreRound`) and Sun + stale Gahwa (assertion `gahwaWonGame == false`).

5. **(NONE — no action):** Sun×2 ÷10 composition is mathematically correct end-to-end. Sun-Bel ×4 composition is correct. Carré-A=400 in Sun produces 80 gp at the meld level. Tied-Sun-fail produces 26 gp defender qaid. Tied-Sun-Bel inversion produces 52 gp bidder take. All canonical Saudi values match.

---

## Cross-references confirmed

- `Rules.lua:707` — `handTotal = K.HAND_TOTAL_SUN` for Sun contracts.
- `Rules.lua:725` — Belote gate `if contract.type == K.BID_HOKM and contract.trump`.
- `Rules.lua:825-832` — Sun's tied-inversion branch: `highest = contract.doubled and "double" or "none"` (no Triple/Four/Gahwa lookup).
- `Rules.lua:849` — sweep bonus uses `K.AL_KABOOT_HOKM` or `K.AL_KABOOT_SUN`.
- `Rules.lua:914-918` — Sun multiplier branch: `mult = mult * K.MULT_SUN`, then optional `* K.MULT_BEL` if doubled. Triple/Four/Gahwa explicitly omitted.
- `Rules.lua:949` — `div10 = floor((x+5)/10)` (5 rounds up per video #43, applied to both Hokm and Sun raw values).
- `Constants.lua:55` — `K.HAND_TOTAL_SUN = 130`.
- `Constants.lua:69` — `K.MULT_SUN = 2`.
- `Constants.lua:95` — `K.MELD_CARRE_A_SUN = 400` (per v0.10.0 R5).
- `Constants.lua:115` — `K.AL_KABOOT_SUN = 220` (220 × 2 / 10 = 44 gp; matches video #43).
- `Constants.lua:352` — `K.SUN_BEL_CUMULATIVE_GATE = 100`.
- `tests/test_rules.lua:553-559, 561-569, 583-601, 691-724` — Sun-related ScoreRound assertions, all green per the v0.10.2 baseline (340/340 tests passing per CHANGELOG v0.10.0:651).
