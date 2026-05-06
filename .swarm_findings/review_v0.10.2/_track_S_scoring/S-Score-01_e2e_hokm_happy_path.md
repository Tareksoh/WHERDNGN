# S-Score-01 — End-to-End Hokm Scoring Trace (Happy Path)

**Agent:** S-Score-01 (review swarm v0.10.2, track S — scoring)
**Scope:** Trace `R.ScoreRound` from inputs to per-team game points across six happy-path Hokm contracts. Composition-level audit; per-function audit was done in `B-Rules-02_scoreRound.md`.
**Read-only.** Sources: `Rules.lua` (post-v0.10.0 R2/R5/X5/M5 cascade), `Constants.lua`, `tests/test_rules.lua`, `docs/strategy/_transcripts/-QrykaZdosE_43_score_calculation.ar-orig.srt`.

---

## 1. TL;DR

**No new composition bug found. The pipeline produces the canonical values for all six scenarios.** The two arithmetic invariants the user is most likely to be confused about — *(a) "is Belote `+20` added before or after the `×N` multiplier?"* and *(b) "does the multiplier apply to both teams' card-points or only the bidder's?"* — both resolve correctly in code:

- **Belote `+20` is added AFTER the multiplier**, at `Rules.lua:939-943` (after the `(card + meld) * mult` at `Rules.lua:926-927`). So `Hokm + Bel + Belote` produces `(100×2) + 20 = 220 raw → 22 gp`, not the alternative `(100+20)×2 = 240 raw → 24 gp`.
- **The multiplier applies to BOTH teams' raw card-points**, at `Rules.lua:926-927` (`rawA = (cardA + meldPoints.A) * mult` and same for `rawB`). So under `Hokm + Bel`, defender's `62 raw` also gets ×2 → `124 raw → 12 gp`.
- **The fail/take branch awards `handTotal × mult` qaid to the winner and preserves each team's own melds at `Rules.lua:868-871` and `881-884`** — matches the "مشروعي لي ومشروعك لك" rule documented in the prior B-Rules-02 audit.
- **`div10` rounding is `math.floor((x + 5) / 10)`** at `Rules.lua:949`, which produces 5-up rounding consistent with video #43 lines 2080-2199 (1–4 down, 5–9 up).

The only behavioral notes worth surfacing (copies of findings already enumerated in `B-Rules-02`):
- F-01: sweep override + Belote cancellation order — out of scope for the six happy-path scenarios here, but if the user's "something is wrong" report turns out to be a sweep+belote case, see `B-Rules-02:32-56`.
- F-03: stale Sun-gahwa flag triggers `gahwaWonGame=true` despite R2 collapse — out of scope (no Sun in these traces).

The user's probable concern is most likely either (i) a UI/banner display issue, (ii) a Net.lua aggregation issue, or (iii) the F-01 sweep+belote interpretation. The arithmetic in `R.ScoreRound` itself is correct for the six canonical happy-path Hokm scenarios.

**Verdict: PASS** for the six scenarios traced.

---

## 2. Per-scenario traces

For each scenario I cite line:column references to `Rules.lua` (`R.ScoreRound` body at 692–984). Constants are at `Constants.lua:42–115` and used as `K.*` inside the function.

Notation: `tp` = `teamPoints` table after the trick-aggregation loop; `mp` = `meldPoints`; `mult` = the final multiplier; `raw{A,B}` = `(card + meldPoints) * mult [+ belote]`; `final{A,B}` = `div10(raw)`.

### Scenario 1 — Vanilla Hokm bidder-makes (90 vs 62)

**Setup.** `contract = { type=K.BID_HOKM, trump="H", bidder=1 }`. `bidderTeam = "A"`, `oppTeam = "B"`. No melds either side. No K+Q-of-trump in same hand. Tricks: bidder team takes raw 90 card-points + `K.LAST_TRICK_BONUS = 10` on trick 8 ⇒ `tp.A = 100`. Defender team `tp.B = 62`. Hand total 162 = 152 cards + 10 last-trick.

**Trace.**

| Step | Line(s) | Computation | Value |
|---|---|---|---|
| trick aggregation | 696–705 | sum + last-trick bonus | `tp.A=100, tp.B=62` |
| handTotal | 707 | `K.HAND_TOTAL_HOKM` | `162` |
| bidderTeam | 708 | `R.TeamOf(1)` | `"A"` |
| meld sums | 711–712 | empty lists | `meldA=0, meldB=0` |
| belote scan | 723–740 | no K+Q-trump in same hand | `belote=nil` |
| sweep | 743–745 | `tp.{A,B}` count = 4/4 (or any non-8) | `sweepTeam=nil` |
| meldVerdict | 791 | both empty | `"tie"` |
| effMelds | 792–793 | tie ⇒ both 0 | `effMeldA=0, effMeldB=0` |
| beloteA, beloteB | 789–790 | none | `0, 0` |
| bidderTotal | 794–795 | `100 + 0 + 0` | `100` |
| oppTotal | 796–797 | `62 + 0 + 0` | `62` |
| **outcome_kind** | 805–807 | `100 > 62` strict | `"make"` |
| bidderMade | 845 | true | `true` |
| **make branch** | 885–893 | `cardA, cardB = tp.A, tp.B` (line 889); meld winner-takes-all (tied ⇒ both 0) | `cardA=100, cardB=62, mp.A=0, mp.B=0` |
| mult | 914–924 | Hokm, no escalation | `mult=1` |
| rawA, rawB | 926–927 | `(100+0)×1, (62+0)×1` | `100, 62` |
| Belote add | 939–943 | none | unchanged |
| **div10** | 949 | `floor((100+5)/10)`, `floor((62+5)/10)` | `final.A=10, final.B=6` |

**Expected per the question.** `bidder=10 gp, defender=6 gp`.

**Match.** ✓ Yes (note: the question said "raw 90 + 10 = 100 ⇒ 100/10 = 10 gp" without explicit prompt about Hokm divisor; the math for Hokm is direct `÷10` because `mult=1`. The Sun divisor of 5 from video #43 line 814 is replicated by Sun's multiplier ×2 baked-in at line 916 followed by `÷10`).

**Strict-majority gate verified.** `100 > 62` is strict (`>`, not `≥`) at line 806. The "tied 81/162" gate is enforced; see scenario 5.

---

### Scenario 2 — Hokm + Belote +20 (bidder holds K+Q of trump)

**Setup.** Same as scenario 1, plus seat 1 (team A) plays both KH and QH during the round. No melds.

**Trace divergences from scenario 1.**

| Step | Line(s) | Computation | Value |
|---|---|---|---|
| belote scan | 725–739 | KH played by seat 1, QH played by seat 1 ⇒ `kWho=qWho=1` | `belote = R.TeamOf(1) = "A"` |
| beloteA, beloteB | 789–790 | belote="A" ⇒ MELD_BELOTE | `20, 0` |
| bidderTotal | 794–795 | `100 + 0 + 20` | `120` |
| oppTotal | 796–797 | `62` | `62` |
| outcome | 805–807 | `120 > 62` strict | `"make"` |
| make branch | 889–893 | `cardA=100, cardB=62, mp.A=mp.B=0` | unchanged |
| mult | 914 | `K.MULT_BASE = 1` | `1` |
| rawA, rawB | 926–927 | `(100+0)×1, (62+0)×1` | `100, 62` |
| **Belote add** | **939–943** | `rawA = 100 + 20` | `rawA=120, rawB=62` |
| **div10** | 949 | `floor((120+5)/10), floor((62+5)/10)` | `final.A=12, final.B=6` |

**Expected per the question.** `bidder=12 gp, defender=6 gp`.

**Match.** ✓ Yes.

**Verification — "Belote add is OUTSIDE the multiplier loop":**
- `rawA, rawB` are computed at `Rules.lua:926-927` as `(card + meldPoints) * mult`. Belote is NOT in this expression.
- The Belote `+K.MELD_BELOTE` (=20) addition is a separate statement at `Rules.lua:939-943`:
  ```lua
  if belote == "A" then
      rawA = rawA + K.MELD_BELOTE
  elseif belote == "B" then
      rawB = rawB + K.MELD_BELOTE
  end
  ```
  This is structurally **outside** the multiplier — `rawA` and `rawB` already have `* mult` baked in by line 926-927; the Belote constant is added flat afterward. The comment at `Rules.lua:929-938` documents this explicitly: *"Belote: independent +20 raw, applied AFTER the multiplier. Pagat: 'Baloot always 2 points unaffected'."*

**Note on `R.DetectMelds`.** The user's task description said "R.DetectMelds returns Belote=20." That is **not how the code works**. `R.DetectMelds` (Rules.lua:251-321) emits sequence and carré melds only; it does NOT emit Belote. The Belote +20 is detected entirely inside `R.ScoreRound` by scanning `tricks[*].plays` for who played K and Q of trump (Rules.lua:723-740). This separation is correct because Belote is multiplier-immune and is never declared as a meld during play; the `R.DetectMelds` melds enter the multiplier loop via `meldPoints` while Belote does not.

---

### Scenario 3 — Hokm + Bel (defenders Bel) ×2

**Setup.** `contract = { type=K.BID_HOKM, trump="H", bidder=1, doubled=true }`. Defender team Bel'd. No K+Q-of-trump. No melds. Same 90+10 vs 62 raw card-points.

**Trace divergences from scenario 1.**

| Step | Line(s) | Computation | Value |
|---|---|---|---|
| outcome | 805–807 | `100 > 62` strict | `"make"` |
| **mult** | 914–924 | Hokm, `contract.doubled=true` ⇒ `mult = 1 * K.MULT_BEL = 2` | `2` |
| **rawA** | 926 | `(100+0) × 2` | `200` |
| **rawB** | 927 | `(62+0) × 2` | `124` |
| Belote add | 939–943 | belote=nil | unchanged |
| div10 | 949 | `floor(205/10), floor(129/10)` | `final.A=20, final.B=12` |

**Expected per the question.**
- `bidder: 100 × 2 ÷ 10 = 20 gp` ✓
- `defender: 62 × 2 ÷ 10 = 12 gp` (the question asked "does defender team also get ×2?")

**Match.** ✓ Yes.

**Verification — "does the multiplier apply to BOTH teams' card-points":**
The multiplier applies symmetrically. `Rules.lua:926-927`:
```lua
local rawA = (cardA + meldPoints.A) * mult
local rawB = (cardB + meldPoints.B) * mult
```
There is **no branch** that scopes `mult` to bidder-only or winner-only. Whatever `cardA, cardB, mp.A, mp.B` are after the make/fail/take dispatch (lines 847-893), they are both multiplied by the same `mult` constant. So defender team's card-points absolutely get the ×2.

This matches `tests/test_rules.lua:496` (`Sun sweep: raw B = K.AL_KABOOT_SUN * K.MULT_SUN = 440`) and `tests/test_rules.lua:600` (`Sun stale-foured: bidder raw = 130×2×2 = 520`).

---

### Scenario 4 — Hokm + Bel + Belote (×2 with K+Q in bidder hand)

**Setup.** Same as scenario 3 plus seat 1 plays KH and QH. Bidder makes 90+10 raw. Bel'd ×2.

**Trace divergences from scenario 3.**

| Step | Line(s) | Computation | Value |
|---|---|---|---|
| belote | 725–740 | seat 1 KH+QH | `"A"` |
| beloteA, beloteB | 789–790 | belote="A" | `20, 0` |
| bidderTotal | 794–795 | `100 + 0 + 20` | `120` |
| outcome | 806 | `120 > 62` | `"make"` |
| mult | 923 | `doubled=true` | `2` |
| **rawA** (pre-Belote) | 926 | `(100+0) × 2` | `200` |
| **rawB** (pre-Belote) | 927 | `(62+0) × 2` | `124` |
| **Belote add** | 939–943 | `rawA = 200 + 20` (NOT 200 + 40) | `rawA=220, rawB=124` |
| div10 | 949 | `floor(225/10), floor(129/10)` | `final.A=22, final.B=12` |

**Expected per the question (the critical disambiguation).**
- Correct (Belote added AFTER mult): `(100×2 + 20) ÷ 10 = 22 gp` ✓
- BUG path (Belote multiplied): `(100+20)×2 ÷ 10 = 24 gp` ✗

**Match.** ✓ Code produces `final.A = 22 gp` — the Belote-AFTER-multiplier path.

**Cited proof:**
1. `Rules.lua:926-927` computes `rawA = (cardA + meldPoints.A) * mult` — Belote is NOT in this expression.
2. `Rules.lua:939-943` adds Belote post-multiplier:
   ```lua
   if belote == "A" then
       rawA = rawA + K.MELD_BELOTE
   elseif belote == "B" then
       rawB = rawB + K.MELD_BELOTE
   end
   ```
3. `Rules.lua:929-938` carries the docstring assertion: *"Bel/Triple/Four/Sun multipliers do NOT scale the Belote bonus. Always +2 game points to that team."*

This matches `CLAUDE.md` line 47: *"Belote (K+Q of trump, +20) is multiplier-immune. A ×4 round doesn't ×4 the Belote bonus."*

---

### Scenario 5 — Hokm bidder fails (tied 81/162)

**Setup.** `contract = { type=K.BID_HOKM, trump="H", bidder=1 }`. No melds, no K+Q-of-trump. Tricks aggregate to `tp.A=81, tp.B=81` (e.g. bidder team takes 71 raw + last-trick 10 = 81; defender 81). Hand total = 162 = 81+81. Bidder must STRICTLY exceed defender for "make".

**Trace.**

| Step | Line(s) | Computation | Value |
|---|---|---|---|
| tp | 696–705 | even split + last-trick to bidder | `tp.A=81, tp.B=81` |
| meld sums | 711–712 | empty | `meldA=0, meldB=0` |
| belote | 723–740 | none | `nil` |
| sweep | 743–745 | 4/4 | `nil` |
| beloteA, beloteB, effMelds | 789–793 | all zero | `0, 0, 0, 0` |
| bidderTotal, oppTotal | 794–797 | `81, 81` | tied |
| **outcome dispatch** | 805–842 | `bidderTotal == oppTotal` ⇒ tie branch (810–842). `contract.type==BID_HOKM`, no escalation flags ⇒ `highest="none"` (line 837). `highest != "double" and != "four"` ⇒ falls through to `outcome_kind = "fail"` (line 841). | `outcome_kind="fail"` |
| bidderMade | 845 | false | `false` |
| **fail branch** | 854–871 | `oppTeam="B"`. `cardA = (oppTeam=="A") and handTotal or 0` ⇒ 0. `cardB = (oppTeam=="B") and handTotal or 0` ⇒ 162. `mp.A = meldA = 0`, `mp.B = meldB = 0`. | `cardA=0, cardB=162, mp.A=0, mp.B=0` |
| mult | 914–923 | no escalation | `1` |
| rawA, rawB | 926–927 | `(0+0)×1, (162+0)×1` | `0, 162` |
| Belote add | 939–943 | none | unchanged |
| div10 | 949 | `floor(5/10)=0, floor(167/10)=16` | `final.A=0, final.B=16` |

**Expected per the question.** Defender team takes the FULL hand-total qaid (162×1 = 162 raw → 16 gp). Bidder team retains their own melds (none here, so 0).

**Match.** ✓ Yes.

**Verification — "مشروعي لي ومشروعك لك" rule + meldA/meldB attribution at lines 868-871:**

```lua
elseif outcome_kind == "fail" then
    cardA = (oppTeam == "A") and handTotal or 0   -- line 868
    cardB = (oppTeam == "B") and handTotal or 0   -- line 869
    meldPoints.A = meldA                           -- line 870
    meldPoints.B = meldB                           -- line 871
```

Lines 870-871 attribute `meldA` to A and `meldB` to B unconditionally — i.e., **each team keeps their own declared melds even on a failed contract**. This matches the v0.4.3+ "مشروعي لي ومشروعك لك" rule documented in the inline comment block at `Rules.lua:854-867`:
> *"Failed contract: defender team takes the handTotal qaid penalty. Per Saudi rule "مشروعي لي ومشروعك لك" each team KEEPS their own declared melds (the same rule we already apply to qaid/takweesh and invalid-SWA per v0.4.3). The penalty is the handTotal × multiplier awarded to the winner; the loser's melds are NOT confiscated."*

To verify the meld preservation independently: if bidder team A had declared `meldA=50` (a `seq4`) and still failed at 81/81, the trace would be:
- Fail branch: `cardA=0, cardB=162, mp.A=50, mp.B=0`.
- mult=1; `rawA=(0+50)×1=50; rawB=162×1=162`.
- `final.A=floor(55/10)=5, final.B=floor(167/10)=16`.

So the bidder team would still get +5 gp from their own seq4 even on a failed contract. This matches the test pin `tests/test_rules.lua:443-446` (raw.B = handTotal, raw.A = 0 with no melds present).

---

### Scenario 6 — Hokm bidder fails 80-82 (genuine fail)

**Setup.** Same as scenario 5 but with unambiguous fail: `tp.A=80, tp.B=82`. (Note: Hand total is 162. With last-trick bonus already in `tp`, this means raw cards split as e.g. A=80, B=72+10=82, or A=70+10=80 if A took trick 8 with B taking 82 raw cards. Either way the totals add to 162.) No melds, no K+Q-of-trump.

**Trace divergences from scenario 5.**

| Step | Line(s) | Computation | Value |
|---|---|---|---|
| tp | 696–705 | given | `tp.A=80, tp.B=82` |
| bidderTotal, oppTotal | 794–797 | `80, 82` | strict inequality |
| **outcome** | 805–809 | `bidderTotal=80 < oppTotal=82` strict ⇒ falls into line 808-809 directly | `outcome_kind="fail"` |
| (rest identical to scenario 5) | 854–871, 914–949 | identical fail-branch dispatch | `final.A=0, final.B=16` |

**Expected per the question.** Identical scoring shape to scenario 5: defender takes `162 raw → 16 gp`, bidder gets 0 (or own melds if any).

**Match.** ✓ Yes. The two failure paths (tied at 81 vs 80<82 strict) converge on the same scoring branch at line 854. The only difference is which conditional resolves `outcome_kind="fail"`:
- Scenario 5 tied: line 810–842 tie branch with `highest="none"` (line 837) ⇒ line 841.
- Scenario 6 strict: line 808 direct.

Both arrive at the same `cardA, cardB, mp.A, mp.B = 0, 162, meldA, meldB` assignment.

---

## 3. Verbatim source comparison — video #43 rounding rule

The "5 rounds UP" rule is explicit in the Saudi-tournament source video #43 (file: `docs/strategy/_transcripts/-QrykaZdosE_43_score_calculation.ar-orig.srt`).

Direct citations:

- Lines 2093-2094: "كان من واحد الى اربعه راح تقربه للواحد" — *"if [the digit] was 1 to 4, you round it down."*
- Lines 2103-2104: "واذا كان العدد من خمسه الى تسعه راح تقربه للعشره" — *"and if the digit was 5 to 9, you round it up to ten."*
- Lines 2123-2124: "العدد 67 ... راح تقربها لسبعين" — *"67 rounds to 70."*
- Lines 2143-2144: "65 راح تقربها للسبعين" — *"65 rounds to 70."*
- Lines 2167-2168: "64 راح تقربها للستين" — *"64 rounds to 60."*
- Lines 2177-2178: "62 راح تقربها ل 60" — *"62 rounds to 60."*

The corresponding code at `Rules.lua:949`:
```lua
local function div10(x) return math.floor((x + 5) / 10) end
```

Numerical verification:
- `div10(67) = floor(72/10) = 7` (= 70 raw / 10) ✓ matches transcript line 2124.
- `div10(65) = floor(70/10) = 7` ✓ matches line 2144.
- `div10(64) = floor(69/10) = 6` ✓ matches line 2168.
- `div10(62) = floor(67/10) = 6` ✓ matches line 2178.

The inline comment at `Rules.lua:945-948` documents the 5-up convention and notes the pre-fix bug (`(x+4)/10` rounded 5 down):
> *"Saudi convention: round to nearest 10, **'5 rounds UP'**, then /10. Per video #43 'حساب النقاط في البلوت للمبتدئين': 65 raw → 70, 67 raw → 70, 64 raw → 60. Earlier code rounded 5 DOWN (`(x + 4) / 10`); the corrected formula is `(x + 5) / 10`."*

The test pins at `tests/test_rules.lua:762-764` lock in this direction:
```lua
assertEq(math.floor((65 + 5) / 10), 7, "div10(65) = 7 (5 rounds UP)")
assertEq(math.floor((15 + 5) / 10), 2, "div10(15) = 2 (5 rounds UP)")
assertEq(math.floor((64 + 5) / 10), 6, "div10(64) = 6 (4 rounds DOWN)")
```

**Verdict.** The rounding rule in code matches the Saudi source verbatim. ✓

Additional cross-check — Hokm hand total `162`:
- Lines 853-854: "تحسب كل الورق حق الحكم وراح يطلع 162 بلط" — *"count all the Hokm cards and you'll get 162 points."*
- Line 964: "162 اقسم على عشره حيطلع 16.2 خلاص قرب اذا قربت حيطلع 16 نقطه" — *"162 divided by 10 = 16.2, round it and you get 16 points."*
- Code: `K.HAND_TOTAL_HOKM = 162` at `Constants.lua:54`. `div10(162) = floor(167/10) = 16` ✓ matches line 964.

Sun hand total `130` and divisor `5`:
- Line 814: "130 هذه تقسمها على خمسه حيطلع ... 26" — *"130 divided by 5 = 26."*
- Code: `K.HAND_TOTAL_SUN = 130` at `Constants.lua:55`. With Sun mult ×2 baked in (`mult = K.MULT_SUN = 2` at `Rules.lua:916`), the pipeline computes `raw = 130 × 2 = 260` then `div10(260) = floor(265/10) = 26` ✓. The `÷5` from the transcript is replicated as `÷10 with mult=2` in code — algebraically equivalent.

---

## 4. Bugs found

**None in the six happy-path scenarios.** The arithmetic, branch dispatch, multiplier scope, Belote-after-multiplier ordering, fail-branch meld preservation, and `div10` rounding all produce canonical values matching video #43, PDF 02, PDF 07, and `CLAUDE.md` line 47.

Out-of-scope notes (these are NOT triggered by the six happy-path scenarios but are pre-existing audit findings worth keeping in mind if the user's "scoring is wrong" report turns out to involve a different code path):

| Tag | Severity | Location | Status |
|---|---|---|---|
| F-01 | MEDIUM | `Rules.lua:752-777` (sweep override + Belote cancellation order) | Pre-existing finding from `B-Rules-02_scoreRound.md:32-56`. Out of scope (no sweeps in scenarios 1–6). |
| F-03 | MEDIUM | `Rules.lua:957-968` (Sun stale-gahwa flag) | Pre-existing. Out of scope (no Sun, no gahwa in scenarios 1–6). |
| F-06 | LOW | `Rules.lua:680-691` (docstring missing 5 fields) | Pre-existing doc-drift. |

---

## 5. Recommendations

1. **Mark this trace ✓-PASS in the v0.10.2 review summary.** The six canonical happy-path Hokm scenarios produce the expected game points end-to-end. If the user reports "scoring is wrong" for one of these specific shapes, the bug is NOT in `R.ScoreRound` — look downstream in `Net.lua` (cumulative aggregation, `HostStepAfterTrick`), `State.lua` (cumulative-score persistence), or `UI.lua` (banner rendering).

2. **Add an explicit `Hokm 81/81 tied → fail` test pin to `tests/test_rules.lua` Section G** (currently only the larger-magnitude Sun ties at section I exercise the strict-majority code path with last-trick-bonus arithmetic; the 81/81 Hokm boundary is the canonical Saudi rule and deserves a direct pin for human-readability of the fixture). The pin would mirror scenario 5 of this trace: trip the tied-no-escalation tie-inversion fall-through to `outcome_kind="fail"`, assert `final.A=0, final.B=16`. *(This duplicates F-07 from `B-Rules-02`.)*

3. **Add a direct integration pin for `Hokm + Bel + Belote` (scenario 4) to `tests/test_rules.lua` Section J or K.** Currently Section K verifies multipliers in isolation and Section J verifies Belote attribution / cancellation in isolation; no pin exercises the **interaction** that distinguishes `(100×2)+20=220` from `(100+20)×2=240`. A test like:
   ```lua
   local c = hokm("H", 1, { doubled = true })
   local tricks = tricksWithSeat1Belote({1,1,1,1,1,2,2,2})
   local res = R.ScoreRound(tricks, c, { A = {}, B = {} })
   assertEq(res.belote, "A")
   assertEq(res.multiplier, 2)
   -- The critical pin: Belote NOT scaled by mult.
   assertEq(res.raw.A % 2, 0, "raw.A even => belote was added AFTER ×2")
   -- Or pin the exact value once tricksWithSeat1Belote's deterministic output is settled.
   ```
   This would lock in the Belote-after-multiplier ordering against any future refactor of the `(card+meld)*mult` line.

4. **No code change needed for the six scenarios audited.** The arithmetic invariants are correct.

5. **If the user can be more specific about "scoring is wrong",** ask for: (a) was it a Bel'd round? (b) was there a Belote (K+Q of trump in same hand)? (c) was there a sweep? (d) was the bidder side or defender side affected? Answers (c)+(d) would pinpoint F-01; answers (a)+(b) would test scenario 4 specifically; absence of any of those would push the investigation to Net.lua or UI.lua.

---

## Appendix — Line-by-line `R.ScoreRound` map (for cross-reference)

| Line range | Section |
|---|---|
| 692 | function signature |
| 693–705 | trick aggregation + last-trick bonus |
| 707–710 | `handTotal`, `bidderTeam`, `oppTeam` |
| 711–713 | meld sums + `meldPoints` init |
| 715–740 | Belote scan (K+Q-of-trump in same hand) |
| 742–754 | sweep detection + sweep-override-belote |
| 756–777 | Belote cancellation by ≥100 meld (team-level, M5) |
| 779–797 | bidder-threshold computation (effMelds + belote) |
| 799–843 | outcome_kind dispatch (make / fail / take) |
| 845 | bidderMade |
| 847–893 | per-branch `cardA, cardB, meldPoints` assignment |
| 895–924 | multiplier computation (Sun×Bel-only collapse, R2) |
| 926–927 | `rawA, rawB = (card + meldPoints) * mult` |
| 929–943 | Belote +20 raw, **outside** the multiplier |
| 945–949 | `div10` definition (5-up rounding) |
| 951–968 | Gahwa match-win flag (F-03 scope) |
| 970–984 | return struct |

End of trace.
