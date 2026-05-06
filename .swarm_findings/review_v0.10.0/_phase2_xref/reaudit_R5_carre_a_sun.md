# Reaudit R5: Carré A in Sun (400 raw direct vs 200 × ×2 mult)

**Audit version**: v0.10.0
**Phase**: Phase 2 — Cross-reference / sanity check
**Source files inspected**:
- `C:\CLAUDE\WHEREDNGN\.swarm_findings\review_v0.10.0\_phase1_sources\source_I_melds_swa_scoring.md`
- `C:\CLAUDE\WHEREDNGN\docs\strategy\_transcripts\oEJjzIlMPeQ_32_melds_detailed.ar-orig.srt`
- `C:\CLAUDE\WHEREDNGN\docs\strategy\_transcripts\9hJEA_McqOA_38_melds_intro.ar-orig.srt`
- `C:\CLAUDE\WHEREDNGN\docs\strategy\_transcripts\-QrykaZdosE_43_score_calculation.ar-orig.srt`
- `C:\CLAUDE\WHEREDNGN\Constants.lua`
- `C:\CLAUDE\WHEREDNGN\Rules.lua`
- `C:\CLAUDE\WHEREDNGN\docs\strategy\saudi-rules.md`

---

## 1. Quoted Arabic from videos #32, #38 about the value

### Video #32 (`oEJjzIlMPeQ_32_melds_detailed`)

**Lines 235–248** (the dedicated 400 section):

| SRT line range | Arabic ≤15 words | English |
|---|---|---|
| 235–237 | "اكبر مشروع في اللعبه اللي هو 400 الاربعميه" | "Biggest meld in the game: 400 — the Four-Hundred" |
| 239–241 | "اقوى مشروع في اللعبه طبعا 400 فقط في الصن" | "Strongest meld in the game; 400 ONLY in Sun" |
| 243–245 | "في الحكم لو جاتك اربع عكك تعتبر ميه" | "In Hokm, four Aces count as 100" |
| 245–247 | "فلو قلت في الحكم 400 هذه قايد عليك" | "If you say 400 in Hokm, that's a qaid penalty on you" |
| 247 | "قول 100 لكن في الصن ب 400" | "Say 100 (in Hokm); but in Sun it's 400" |
| 249 | "واذا جاتك 400 في الصن مستحيل تخسر عليك" | "If you have 400 in Sun, impossible to lose this round" |

### Video #38 (`9hJEA_McqOA_38_melds_intro`)

**Lines 25–62** (the meld-introduction section):

| SRT line range | Arabic ≤15 words | English |
|---|---|---|
| 27–29 | "الاربعه الاكك ... معناته 400 هذا اقوى شيء في اللعبه" | "Four Aces … means 400, the strongest thing in the game" |
| 31 | "طبعا 400 في الصن" | "Of course, 400 in Sun" |
| 53–57 | "الفرق بين الصن والحكم ... 400 في السنه" | "Difference between Sun and Hokm: 400 in Sun" |
| 59–61 | "اربع عكك في الحكم ما تقولوا 400 تقول 100" | "Four Aces in Hokm — don't say 400; say 100" |
| 61 | "تعامل معامله الميه ونفس نقاط المياه" | "Treated like a 100, same point value as a 100" |

### Critical observation

**Both videos consistently use the LITERAL number 400 as the meld's value in Sun.** Neither video says "200 doubled because Sun multiplies", neither uses any "×2" framing for this meld. The number "200" never appears in either video in connection with Carré A. The meld's name itself (الأربعميه — "the Four-Hundred") is the value.

Source I summary corroborates (D9, A7): "Carré A in Sun = 400 raw — confirmed by 2 sources … both videos call it 400 directly as the raw value in Sun. There is NO 200 base + ×2 construction in either source."

---

## 2. Code trace: how 4-A meld + Sun mult interact in R.ScoreRound

### Constants (`C:\CLAUDE\WHEREDNGN\Constants.lua`)

```lua
-- Lines 68–71
K.MULT_BASE   = 1
K.MULT_SUN    = 2  -- sun contracts score x2
K.MULT_BEL    = 2  -- doubled (×2)
K.MULT_TRIPLE = 3
K.MULT_FOUR   = 4

-- Lines 91–103
K.MELD_SEQ3        = 20
K.MELD_SEQ4        = 50
K.MELD_SEQ5        = 100
K.MELD_CARRE_OTHER = 100
K.MELD_CARRE_A_SUN = 200   -- "Stored as 200 raw so the Sun ×2 multiplier
                           --  in R.ScoreRound brings the final raw to 400
                           --  (= 40 gp after div10)"
K.MELD_BELOTE      = 20
```

### Rules.lua — meld detection (lines 230–253)

```lua
-- R.DetectMelds: only emits MELD_CARRE_A_SUN when isSun = (contract.type == K.BID_SUN)
if rank == "A" then
    if isSun then value = K.MELD_CARRE_A_SUN end   -- 200 raw, Sun only
else
    value = K.MELD_CARRE_OTHER                     -- 100 raw
end
```

So the value 200 is only emitted when the contract is Sun. In Hokm the carré-A is suppressed entirely (no meld emitted) — which differs from the videos' "Hokm: count it as 100" framing. *(Out of scope for this reaudit, but worth flagging — see §5 Side-finding.)*

### Rules.lua — `R.ScoreRound` multiplier path (lines 841–865)

```lua
local mult = K.MULT_BASE          -- 1
if contract.type == K.BID_SUN then mult = mult * K.MULT_SUN end       -- ×2
if     contract.gahwa   then mult = mult * K.MULT_FOUR
elseif contract.foured  then mult = mult * K.MULT_FOUR                -- ×4
elseif contract.tripled then mult = mult * K.MULT_TRIPLE              -- ×3
elseif contract.doubled then mult = mult * K.MULT_BEL end             -- ×2

local rawA = (cardA + meldPoints.A) * mult
local rawB = (cardB + meldPoints.B) * mult

-- Belote (independent +20) added AFTER multiplier (multiplier-immune)
if belote == "A" then rawA = rawA + K.MELD_BELOTE
elseif belote == "B" then rawB = rawB + K.MELD_BELOTE end

local function div10(x) return math.floor((x + 5) / 10) end
-- final = { A = div10(rawA), B = div10(rawB) }
```

**The meld points ARE multiplied by `mult`.** So in Sun, every meld's stored raw value gets ×2 applied — including `K.MELD_CARRE_A_SUN = 200`, which becomes 400 in the rawA/B sum, then divided by 10 → 40 game points (gp).

---

## 3. Test: do code outputs match video expected for baseline Sun?

### Scenario A: baseline Sun, no escalation, 4-Aces meld, no other points

Inputs:
- contract = `{ type = "SUN", bidder = 1 }` (no doubled/tripled/foured/gahwa)
- meldsByTeam.A = `{ { value = 200 } }` (the carré-A from `K.MELD_CARRE_A_SUN`)
- All trick/last-trick points = 0 (isolating the meld math)

Trace through `R.ScoreRound`:
- `meldA = 200`, `meldB = 0`
- `meldVerdict = "A"` → `effMeldA = 200`, `effMeldB = 0`
- bidder makes (their meld puts them above defenders) → `outcome_kind = "make"`
- `meldPoints.A = meldA = 200`, `meldPoints.B = 0`
- `mult = 1 * K.MULT_SUN = 2`
- `rawA = (cardA + 200) * 2 = 400` (with cardA = 0 for isolation)
- `rawB = 0`
- `final.A = div10(400) = math.floor((400+5)/10) = 40` gp
- `final.B = 0`

**Video expected**: 400 raw (Source I, A7) → /5 (per video #43 line 309: "تقسم على خمسه") → 80 gp? Or /10 ?

Wait — let me reconcile divisors. Video #43 explicitly states two parallel framings:
- **Sun**: divide raw by 5 (line 318: "في السن تقسم على خمسه"; line 308: tierce 20 / 5 = 4 nq)
- **Hokm**: divide raw by 10 (line 539/541: "في الحكم تقسم على عشره")

But the code does `div10` for **both** contract types and inserts `×2` into the multiplier for Sun. Algebraically:
- Video Sun framing: `gp = rawSun / 5`
- Code Sun framing: `gp = (rawSun_stored × 2) / 10 = rawSun_stored / 5` ✓

These are mathematically identical PROVIDED that what the code calls "raw" equals what the video calls "raw". The code's `K.MELD_CARRE_A_SUN = 200` is **half** the video's "400 raw" — and the code's ×2 multiplier brings it back up.

So:
- Video: meld raw = 400, gp = 400/5 = **80 gp**
- Code: stored = 200, ×2 (Sun mult) = 400 effective raw, /10 (div10) = **40 gp**

**MISMATCH.** 80 gp vs 40 gp. The factor of 2 discrepancy comes from the code applying `/10` to all contracts while the video applies `/5` for Sun.

### Reconciling the discrepancy — `K.HAND_TOTAL_SUN` cross-check

`K.HAND_TOTAL_SUN = 130` (Constants.lua line 55). Video #43 line 163 confirms 130 raw, then says "تقسمها على خمسه حيطلع 26" (divide by 5 → 26 nq).

Apply the code's logic: `130 × 2 / 10 = 26`. ✓ The code's effective Sun divisor IS 5 (just expressed as ×2/10). For card-trick points, the framings reconcile.

Apply the same to the Carré-A stored value 200: `200 × 2 / 10 = 40` gp. But the video's stated raw 400 with `/5` gives 80 gp.

**The 80-vs-40 discrepancy proves that the video describes the Carré-A meld's raw value as 400 IN THE SAME UNITS as 130 (the Sun trick-total raw).** For 130 the framings agree; for 400 they would too — IF the meld stored 400 raw. The code currently stores 200, which (being a half-raw) gets the ×2 mult and yields 400 raw, which is half what the video implies.

**Wait — let me recheck against the video source carefully.** Video #43 line 309 says: "السره فيها عشرين بنط ... تقسم على خمسه يعني باربع نقاط" (tierce: 20 raw / 5 = 4 nq). Line 313: 50/5 = 10 nq. Line 520: 100/5 = 20 nq.

These are explicit. So if video says Carré-A = 400 raw in Sun and uses the same /5 divisor, video expects 400/5 = **80 nq**.

Code currently produces 40 nq.

**Critical finding**: The current code's "200 stored × 2 Sun mult = 400 then /10 = 40 nq" is HALF of what video #43's framing implies (400 raw /5 = 80 nq). Either:
- (a) code is WRONG by factor 2 — Carré-A should produce 80 nq in Sun, not 40
- (b) code is RIGHT and the videos' "400" terminology means "the historical name of the meld" not its arithmetic raw value, and the actual scoring is half the named value (similar to how the meld is also called "أربعميه" but its trick-equivalence is debatable)

This is now a SUBSTANTIVE question, not a framing-only question.

### Cross-check against `MELD_CARRE_OTHER = 100` and named "ميه"

`K.MELD_CARRE_OTHER = 100` (carré of K/Q/J/T). Apply same code path in Sun:
- 100 × 2 / 10 = 20 nq

Video #43 line 520 explicit: "الميه فيها عشره نقاط" (the hundred = 10 nq) — but this line is a *Hokm* example (preceded by "في الحكم"). For Sun: line 308–309 implies 100/5 = 20 nq.

**100 raw / 5 (Sun) = 20 nq.** Code produces (100 × 2)/10 = 20 nq. ✓

So `K.MELD_CARRE_OTHER = 100` matches video framing exactly: stored value = video's "raw value", and code's ×2/10 reproduces video's /5.

Now apply the SAME logic to Carré-A. Video says raw = 400 in Sun. By analogy with carré-other, the stored value SHOULD be 400 (the video's raw), giving (400 × 2)/10 = 80 nq.

The current code stores 200, which gives 40 nq — half the analogous result.

### Phase 1 Source I confirmation

Source I, section A7: "Carré of Aces (الاربع ميه) — value 200 raw, **400 only in Sun**". The "200 raw" appears in Source I's table heading, but reading further: "The transcripts do NOT phrase it that way [200 + ×2]. Both videos call it 400 directly as the raw value in Sun. There is NO '200 base + ×2' construction in either source."

Source I's table heading "200 raw" appears to be a code-side reconciliation note retrofitted into the heading, NOT what the videos actually say. The video transcripts and Source I's textual analysis agree: **the videos consistently say 400 in Sun**.

---

## 4. Test: Sun + Bel? Sun + Bel-x2?

### Scenario B: Sun, Bel'd (×2 escalation), 4-Aces meld

(Note: Sun-Bel chain itself is contested per other reaudits — but if/when it resolves to "allowed", how does code score it?)

Inputs:
- contract = `{ type = "SUN", bidder = 1, doubled = true }`
- meldsByTeam.A = `{ { value = 200 } }`

Trace:
- `mult = 1 × K.MULT_SUN × K.MULT_BEL = 1 × 2 × 2 = 4`
- `rawA = (cardA + 200) × 4 = 800` (cardA = 0)
- `final.A = div10(800) = 80` gp

Video framing for the same: Carré-A raw 400 in Sun → 400/5 = 80 nq baseline; then Bel ×2 escalation → 160 nq. Code produces 80, half of expected.

### Scenario C: Sun, Bel-x2 (Triple — ×3 escalation), 4-Aces meld

Inputs:
- contract = `{ type = "SUN", bidder = 1, tripled = true }`
- meldsByTeam.A = `{ { value = 200 } }`

Trace:
- `mult = 1 × K.MULT_SUN × K.MULT_TRIPLE = 1 × 2 × 3 = 6`
- `rawA = (0 + 200) × 6 = 1200`
- `final.A = div10(1200) = 120` gp

Video framing: 400/5 × 3 = 240 nq. Code produces 120. Same factor-of-2 deficit.

The pattern is consistent: in EVERY Sun scenario (baseline, Bel'd, Bel-x2, Four), the current code under-scores Carré-A by exactly 2× the intended amount.

### CRITICAL question: are melds in Sun multiplied by 2 alongside trick points, or treated independently?

Looking at the code (lines 848–865), `meldPoints.A` is added to `cardA` BEFORE multiplying — so melds ARE multiplied by `mult` (which includes the Sun ×2 and any escalation factor). This is consistent with video #43's framing where ALL Sun raw points (cards + melds) get the same /5 divisor (equivalently ×2/10) — melds are NOT independent of the Sun framing.

The video does NOT have a special case where melds are unmultiplied for Sun. Belote (+20) IS the only multiplier-immune meld, applied AFTER `mult` (line 861–865). So:

- Trick points in Sun: ÷5 (or equivalently ×2/10) ✓
- Sequence/Carré-other melds in Sun: ÷5 (or equivalently ×2/10) ✓
- **Carré-A in Sun**: should be 400/5 = 80 nq; code produces 200×2/10 = 40 nq ✗
- Belote: +20 raw, multiplier-immune (added after mult, then /10) → 2 nq always ✓

So melds ARE multiplied alongside trick points in Sun (independent treatment is only for Belote). The mismatch is solely in the Carré-A stored value (200 vs the video's 400 raw).

---

## 5. Verdict

### Mathematical reconciliation

The current code's framing ("200 stored × 2 Sun mult = 400 effective") is **internally consistent** (the code's framework is self-consistent: stored values are pre-Sun-mult, Sun mult is applied to all melds and cards, /10 final divisor). It would correctly produce a "400-named, 40-nq-valued" Carré-A in Sun.

But this **does NOT match the video transcripts' arithmetic**, which by analogy with Carré-other (100 raw → 20 nq) and tierce (20 raw → 4 nq) imply Carré-A (400 raw → 80 nq).

### Saudi-rules.md Q3's claim (lines 150–154) is INCORRECT

> "K.MELD_CARRE_A_SUN = 200 (raw); R.ScoreRound applies K.MULT_SUN = 2 to round multiplier; multiplies meld points. So 200 raw × 2 Sun = 400 effective — exactly what video #38 says. No change needed."

The claim **conflates two different "400"s**:
- Video #38's 400 is the **raw value** that, divided by 5 (Sun divisor), produces 80 nq game points.
- Code's "400 effective" is the post-multiplier `rawA` value that, divided by 10, produces 40 nq.

The video's "400" and the code's effective "400" agree as numbers but disagree as game-point yields by exactly 2×. The Q3 reconciliation does not catch this.

### Constants.lua comment (lines 95–102) makes the same error

```
K.MELD_CARRE_A_SUN = 200   -- "Four Hundred" (الأربع مئة) — four Aces in Sun.
                           -- Stored as 200 raw so the Sun ×2 multiplier
                           -- in R.ScoreRound brings the final raw to 400
                           -- (= 40 gp after div10), matching the canonical
                           -- "أربع مئة" Saudi value.
```

The comment claims 40 gp matches the canonical "أربع مئة" (Four Hundred). But the canonical value is the *raw* 400, which under Sun /5 yields **80 gp**, not 40. The comment is wrong about the conversion.

### Verdict table

| Question | Answer |
|---|---|
| Current code is correct (math reconciles): | **N — the code under-scores Carré-A by exactly 2×** (40 gp instead of 80 gp) |
| Naming/framing should change: | Y (constant should be 400, not 200) |
| Action needed: | **Change `K.MELD_CARRE_A_SUN` from 200 to 400** |

### Detailed action

**Required change** (single constant):
```lua
K.MELD_CARRE_A_SUN = 400   -- was 200 (under-scored by 2×)
```

**Reasoning**:
- The code applies Sun mult (×2) and the final /10 to ALL meld values uniformly. This works for tierce (20 → 8 raw → /10 = 0.8?... wait, this needs re-checking — see below)
- Code's stored values for OTHER melds equal the video's raw values: SEQ3=20 (video raw 20), SEQ4=50 (video raw 50), SEQ5=100 (video raw 100), CARRE_OTHER=100 (video raw 100). All produce video-matching nq under code's ×mult/10 path.
- Only CARRE_A_SUN deviates: stored 200, video raw 400.
- Setting it to 400 brings it in line with the rest, and produces the video-correct 80 nq.

### Re-verifying with the SEQ3 cross-check

To make sure my analysis isn't wrong about the divisor framing, let me trace SEQ3 = 20 in Sun:

- `meldsByTeam.A = { { value = 20 } }`
- `meldPoints.A = 20`
- `mult = 2` (Sun, no escalation)
- `rawA = (0 + 20) × 2 = 40`
- `final.A = div10(40) = math.floor((40+5)/10) = 4` gp

Video #43 line 309: "السره فيها عشرين بنط ... تقسم على خمسه يعني باربع نقاط" — tierce 20 raw, /5 = **4 nq** in Sun. ✓ Code matches.

The code framework IS correct. The issue is solely that `K.MELD_CARRE_A_SUN = 200` was set as if it was double the storage (perhaps under a misreading where someone thought "400 in Sun" implied "200 + Sun-mult"; in fact "400 in Sun" was the raw value before the divisor, fully analogous to 20 raw for tierce).

### Historical note

The Constants.lua comment references a "Gemini scoring-audit catch" that previously changed it FROM 400 TO 200, claiming the 400 form "double-counted with Sun mult and produced 800 raw / 80 gp — twice the intended value". That earlier audit was itself wrong. The 80 gp output IS the intended value per video #43's /5 divisor on the video's stated 400 raw. The "fix" in fact introduced a 2× under-scoring bug. This reaudit reverses the earlier fix.

### Confirmation against video #43 absence-of-evidence

Video #43 (the score-calculation video) does NOT directly worked-example a 4-A Sun meld. It DOES work-example tierce (20→4), quarte (50→10), quinte (100→20), and confirms the /5 Sun divisor. By inductive analogy, 400 raw / 5 = 80 nq for Carré-A in Sun is the only consistent reading. No worked counter-example exists in #43 supporting 40 nq.

### Side-finding (out of scope but flag)

`R.DetectMelds` does NOT emit a Carré-A meld in Hokm (line 240–242: "if rank == "A" then if isSun then value = K.MELD_CARRE_A_SUN end"). Per video #32 line 245 and #38 line 61, in Hokm Carré-A should be valued AS A 100 (تعامل معامله الميه) — i.e., it should still emit a meld worth `K.MELD_CARRE_OTHER = 100`. The code currently emits NOTHING for Carré-A in Hokm, dropping the player's 100-meld entirely. This is a SECOND bug (separate from R5's 200-vs-400 issue) and should be a separate reaudit/spawn.

---

## Confidence

**HIGH** on the verdict. The discrepancy is arithmetic, not interpretive: each step of the reconciliation is independently verifiable (constants file, R.ScoreRound code path, video #43's worked tierce/quarte/quinte examples, internal consistency check via SEQ3→4nq matching).

The two videos (#32, #38) are unanimous on "400 in Sun". Video #43 is unanimous on "/5 Sun divisor". The product 400/5=80 is the only consistent reading. Code currently produces 40, which is exactly half. The fix is a one-line change to a single constant.

Suggested follow-up: update `Constants.lua` line 95 to `K.MELD_CARRE_A_SUN = 400`, update its comment to remove the "stored as 200 so Sun mult brings it to 400" reasoning, update `saudi-rules.md` Q3 to acknowledge the prior reconciliation was wrong, and add a regression test ensuring carré-A in Sun (no escalation) yields 80 nq raw final.
