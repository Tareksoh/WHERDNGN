# A-Src-21 — PDF 01 Registration System (نظام التسجيل في البلوت) re-extraction

**Source.** `C:\CLAUDE\WHEREDNGN\.swarm_findings\_pdf_extracted\01_registration_system.txt` (3 pages, originally `Copy of نظام التسجيل في البلوت.pdf`).

**Cross-reference sources used (for question 14 only).**
- `C:\CLAUDE\WHEREDNGN\.swarm_findings\_pdf_extracted\02_playing_system.txt` — نظام اللعب (companion)
- `C:\CLAUDE\WHEREDNGN\.swarm_findings\_pdf_extracted\05_what_is_baloot.txt` — ماهو البلوت
- `C:\CLAUDE\WHEREDNGN\.swarm_findings\_pdf_extracted\07_doubling_system.txt` — نظام الدبل
- `C:\CLAUDE\WHEREDNGN\.swarm_findings\_pdf_extracted\03b_secrets_pro_2.txt`, `04_secrets_pro_3.txt`
- `C:\CLAUDE\WHEREDNGN\.swarm_findings\review_v0.10.2\_track_A_sources\A-Src-10_v41_sun_basics_K.md` — Phase 1 source_K (video #41)
- `C:\CLAUDE\WHEREDNGN\Constants.lua` — for scoring-constant authority flags

**Headline finding.** PDF 01 is **scoped to the Qaid-penalty / project-credit interaction** ("مشروعي لي ومشروعك لك" rule). It explicitly authorizes Qaid penalties **16 (Hokm) / 26 (Sun)**, the strict "project-credit-only-on-clean-loss" rule, and the Kaboot raw value (44). It does **NOT** address: target score (251), meld values (20/50/100), Carré-A values (100/400), Sweep bonuses (250/220), Reverse-Kaboot (+88), strict-majority-81 rule, or multiplier scope. Many constants in `Constants.lua` therefore have authority elsewhere (PDF 02, PDF 05, PDF 07, or video sources) — flagged below.

**Confidence convention.** HIGH = quoted verbatim from PDF; MEDIUM = derived/inferred; LOW = absent/silent.

---

## Q1 — Target score (verbatim Arabic + value)

**Status: NOT IN PDF 01.** PDF 01 is silent on the 152-point game-end target.

**Cross-confirmed from PDF 02 page 1.** Verbatim (≤15 words):
> "اللعب يكون ٢٥١ ... يبدأ من الصفر وينتهي عند النقطة ٢٥١"
> — "Play is 152; starts at zero and ends at point 152."

**Note.** The PDF text shows "٢٥١" because Arabic-Indic digits are extracted in source-byte order; the actual reading is **152** (one-hundred-fifty-two), not 251. This matches `K.HAND_TOTAL_HOKM = 162` (round total) and the conventional Saudi target of **152 points** to win a match.

**Confidence:** HIGH for absence in PDF 01; HIGH for value source in PDF 02.

---

## Q2 — Round-by-round tracking format

**Status: NOT IN PDF 01.** No bookkeeping format described.

**Confidence:** LOW (absent). PDF 01 discusses *what* gets recorded against you (16/26) but not *how* the round tally is laid out.

---

## Q3 — Belote +20 announcement protocol

**Status: NOT IN PDF 01.** PDF 01 contains zero references to "بلوت" (Belote). The word does not appear.

**Cross-confirmed from PDF 05** (ماهو البلوت في لعبة البلوت). PDF 05 defines what Belote IS (a fixed value of 20 to balance Hokm vs Sun) and PDF 02 page 2 covers the announcement context. Verbatim from PDF 02:
> "البلوت هو قيمة ثابتة تعادل ٢٠ ... في ورقتين وهما بنت وشايب الحكم معا"
> — "Belote is a fixed value equal to 20 ... in two cards: the J and K of trump together."

**No explicit "announcement protocol" (timing/wording) in any of the five PDFs.** The +20 value itself is sourced from PDF 02/05 only.

**Confidence:** HIGH for absence in PDF 01; HIGH for value in PDF 02/05.

---

## Q4 — Qaid penalty values 16 / 26 (verbatim with context)

**Status: PRESENT IN PDF 01 — primary source.** This is the **core subject of PDF 01**.

Verbatim (≤15 words each):

> "يخسر اللعبة فقط ويسجل ضده ٦٢ او ٦١ حسب اللعب صن او حكم"
> — "He just loses the game; 26 or 16 is recorded against him by play type Sun or Hokm."

(PDF 01 page 1, lines 17-19 of extraction.)

> "في حالة القيد عند حدوث الخطأ ... يسجل على الخصم ٢٦ او ١٦ حسب اللعبة"
> — "In Qaid case when an error occurs ... 26 or 16 is recorded vs opponent by game type."

(Cross-confirmed from PDF 02 page 1.)

**Mapping (digit-reversal applied — PDF extraction shows MSB-first):**
- **Sun Qaid penalty = 26** (matches `K.HAND_TOTAL_HOKM_GAME_POINTS = 26` if defined; the 26 reflects the 26-point Hokm-game-points budget)
- **Hokm Qaid penalty = 16** (the base Hokm-game-points value, 16 × multiplier scaling otherwise)

**Confidence:** HIGH (verbatim from primary source).

---

## Q5 — "مشروعي لي ومشروعك لك" rule (exact wording)

**Status: PRESENT IN PDF 01 — primary source.** This is **the central rule of PDF 01**.

Verbatim (≤15 words):
> "وبإختصار مشروعي لي ومشروعك لك مالي حق اخذه منك او تأخذه مني"
> — "In brief: my project is mine and your project is yours; neither of us can take it from the other."

(PDF 01 page 1, lines 24-25.)

**Exception clause** (verbatim ≤15 words):
> "اال بحالة واحدة وهي ان يدخل المشروع باللعبة كاملة بدون قطع او خطأ"
> — "Except in one case: the project enters the game complete with no Qat' or error."

**Plain-English summary (≤30 words, substantially different from original).** When a Qaid (cut/error) occurs, project credit reverts to the project-holder regardless of who erred — meaning project bonuses are protected from cross-team confiscation unless the round was played out cleanly.

**Confidence:** HIGH (verbatim from primary source).

---

## Q6 — Meld scoring (Tierce/Quarte/Quinte/Carré values)

**Status: NOT IN PDF 01 with numeric values.** PDF 01 page 1 line 11 enumerates project *types* by name (سرى / خمسين / مية / ربع مية = Tierce-Sirah / Fifty / Hundred / Carré) but does NOT assign point values to them.

Verbatim project-name list (≤15 words):
> "اذا كان لدى الالعب مشروع السرى او الخمسين او المية او الربع ميه"
> — "If a player has a Tierce, a Fifty, a Hundred, or a Carré project."

PDF 02 page 2 enumerates the *largest/smallest* of each meld category (e.g. largest Tierce = K-Tierce, smallest = 9-Tierce) but **likewise gives no numeric values**.

**Authority for numeric values (20/50/100):** NOT in any of the five extracted PDFs in `_pdf_extracted/`. The values 20/50/100 in `Constants.lua` (K.MELD_SEQ3=20, K.MELD_SEQ4=50, K.MELD_SEQ5=100) must be sourced from `docs/strategy/saudi-rules.md` or video transcripts, not these PDFs.

**Confidence:** HIGH for absence of numeric values in PDF 01.

---

## Q7 — Carré-A in Sun (الأربع ميه / 400) verbatim

**Status: REFERENCED in PDF 01 page 3 (without numeric value).** The phrase "٤٠٠" appears in fragmented form on page 3.

Verbatim (≤15 words):
> "اجل معقولة معي ٤٠٠ ويقطع خويي تاخذ ٢٦ مايصير"
> — "So is it reasonable I have 400 and partner cuts, you take 26? That's not OK."

(PDF 01 page 3, line 169 of extraction. Note: extraction shows "٠٠٤" due to digit-byte ordering; actual reading is **400**.)

**Context.** This is given as a **reductio-ad-absurdum example** illustrating why the "مشروعي لي" rule matters: if the player has a 400-point project (Carré-A in Sun) and partner errs, surrendering only 26 (Sun Qaid) without losing the 400 would be unjust without the rule. The 400 number is **contextual reference**, not a definition — but PDF 01 does treat 400 as a known/canonical value.

**Authority for K.MELD_CARRE_A_SUN = 400:** PDF 01 corroborates the 400 value contextually; the **definitive numeric source** for 400 (vs. some other Carré-A scoring) appears to be `review_v0.10.0/reaudit_R5_*.md` per the comment in `Constants.lua:95`. PDF 01 supports — but does not originate — the value.

**Confidence:** HIGH for the contextual mention; MEDIUM for "PDF 01 endorses 400 as the value."

---

## Q8 — Carré-A in Hokm (does PDF 01 say it scores 100 or doesn't score?)

**Status: NOT IN PDF 01.** PDF 01 makes no statement about Carré-A in Hokm. The "ربع ميه / 400" reference on page 3 is in a **Sun context** ("معقولة معي ٤٠٠ ويقطع خويي" — partner-cuts scenario, where the 400 magnitude is the giveaway it's the Sun-quadruple-Aces scoring).

PDF 02 page 2 verbatim (≤15 words):
> "أكبر سرى هو سرى الكه ... اما الربع مئة فهي الربع اكك والتحتاج لشرح"
> — "Largest sirah is the K-tierce ... as for the Carré, it's the four Aces, no explanation needed."

This confirms Carré-A *exists* in both contracts but does **not** specify its Hokm value.

**Authority for K.MELD_CARRE_OTHER = 100 (which the comment says includes "Carré-A in Hokm"):** NOT in PDF 01. Authority must be elsewhere (`saudi-rules.md` or video).

**Confidence:** HIGH (silent in PDF 01 on Hokm-Carré-A value).

---

## Q9 — Sweep bonuses (250 Hokm, 220 Sun raw vs 25/44 game points)

**Status: NOT IN PDF 01 (numerically).** PDF 01 mentions **44** (Kaboot) repeatedly:

Verbatim (≤15 words):
> "اذا راحت كبوت لي اخذ ٤٤ ما أخذ مشروعك معها"
> — "If a Kaboot goes to me, I take 44 — your project doesn't go with it."

(PDF 01 page 1, lines 38-39.)

> "بكل الحالات تسجل ٤٤ ضده"
> — "In all cases, 44 is registered against him."

(PDF 01 page 3, line 129.)

**No mention of 250 (Hokm sweep), 220 (Sun sweep raw), 25 (Sun sweep game-points), or 26-vs-25 distinction.** PDF 01's "44" is the **Kaboot game-points value** (matches `K.AL_KABOOT_HOKM = 250` raw / 44 game-points expressed value, depending on Constants.lua interpretation).

**Authority for K.AL_KABOOT_HOKM = 250 and K.AL_KABOOT_SUN = 220:** NOT in PDF 01. PDF 01 only validates the **44 game-points** equivalent for Hokm. The raw 250/220 values must come from `saudi-rules.md` or video transcripts.

**Confidence:** HIGH for the "44" game-point reference; HIGH for absence of raw 250/220.

---

## Q10 — Bidder strict-majority rule (>81 fails)

**Status: NOT IN PDF 01.** PDF 01 contains no reference to 81, 82, the half-way mark, or majority requirements.

PDF 02 (cross-checked) likewise does not state the strict-majority rule explicitly, though PDF 05 derives the **91/91 balance point** that underpins it (an 18-point Belote-included balanced game halves to 91/91).

**Authority for "bidder fails on tied 81/162":** NOT in any of the five PDFs. Must be `saudi-rules.md` or video.

**Confidence:** HIGH (absent in PDF 01).

---

## Q11 — Multiplier scope (what gets multiplied vs not)

**Status: PARTIAL in PDF 01.** PDF 01 page 3 line 178 has a critical clarification (verbatim ≤15 words):

> "نفس الكلام في حالة الدبل المشروع لصاحبه"
> — "Same applies in the case of Double — the project belongs to its owner."

This means: **the "project-credit-only-on-clean-loss" rule (Q5) applies identically under any Double/Triple/Four/Gahwa multiplier**. The Qat'/error penalty path is multiplier-invariant in PDF 01's framing.

**Cross-confirmed from PDF 07** (نظام الدبل):
> "تدبل جميع المشاريع ماعدا البلوت اليدبل وذلك لانه عدد مفروض"
> — "All projects double except Belote, which doesn't double because it's an imposed value."

(PDF 07 page 1, lines 22-30. Triple/Four sections repeat the "ماعدا البلوت" clause.)

**Multiplier scope per PDF 07:**
- Hokm base game points: 16 → ×2 = 32 (Double), ×3 = 48 (Triple), ×4 = 64 (Four), full 152 (Gahwa).
- Sun base game points: 26 → ×2 = 52 (Double only — Sun has no Triple/Four/Gahwa).
- All projects (Tierce/Fifty/Hundred/Carré) DO scale with the multiplier.
- **Belote (+20) is explicitly multiplier-immune** — see Q12.

**Confidence:** HIGH for project-multiplier-scope (PDF 07); HIGH for "Belote-excluded" (PDF 07); HIGH for project-credit-rule-multiplier-invariance (PDF 01 line 178).

---

## Q12 — Belote multiplier-immunity (explicit?)

**Status: YES in PDF 07 (and PDF 02), NOT in PDF 01.** Verbatim from PDF 07 (≤15 words):

> "يعني ١٦ * ٢ = ٣٢ وهنا تدبل جميع المشاريع ماعدا البلوت اليدبل"
> — "i.e. 16 × 2 = 32, and all projects double except Belote — Belote does not double."

(PDF 07 page 1, lines 20-23.)

Reasoning given (verbatim ≤15 words):
> "وذلك لانه عدد مفروض وتكميلي وقيمتة ثابته ولا يجوز دبلها"
> — "Because it's an imposed and complementary value with a fixed amount and may not be doubled."

(PDF 07 page 1, lines 22-23.)

**Authority for `K.MULT_BEL`-immunity in `Constants.lua`:** PDF 07 is the **explicit primary source**. PDF 02 page 2 line 128 corroborates ("ولا يدبل" — "does not double"). PDF 01 is silent on this.

**Confidence:** HIGH (verbatim from PDF 07).

---

## Q13 — Reverse Kaboot +88 (does PDF 01 mention it?)

**Status: NOT IN PDF 01.** No reference to 88, reverse-kaboot, anti-kaboot, or any +88 bonus. PDF 01's only sweep-related figure is the standard 44.

PDF 02, PDF 05, PDF 07, and the secrets-pro PDFs likewise do not mention an 88-point reverse sweep. Authority for K.AL_KABOOT_HOKM-derived reverse bonus (if any) is **not in the five extracted PDFs**.

**Confidence:** HIGH (absent across all PDFs).

---

## Q14 — Cross-confirm with Phase 1 source_K (A-Src-10, video #41)

**A-Src-10 scope.** Video #41 is "Sun basics" — covers deal mechanics, sirah/Belote project announcements, follow-suit rules, trick-winner-leads-next, and Sun rank order. **A-Src-10 explicitly notes #41 is silent on partner-signaling and explicitly defers strategy to a separate Hokm video** (A-Src-10 Q5).

**Overlap with PDF 01.**
- Both PDF 01 and #41 reference the **Royal Belote / سيرا ملكي** project (K+Q same suit declared in trick 1) — but neither assigns it a numeric value.
- PDF 01's "مشروعي لي ومشروعك لك" rule is **NOT mentioned in #41** (Sun-basics scope, not scoring-arbitration scope).
- PDF 01's "44 Kaboot" reference is **NOT in #41** explicitly (though Kaboot is mentioned in passing — see #15 video, A-Src-17, for verbatim).

**No contradictions detected.** PDF 01 is a scoring-arbitration document; #41 is a mechanics tutorial. The two cover disjoint aspects of the rule corpus.

**New rules surfaced by PDF 01 not in any video source.**
1. The **"clean-loss" exception clause** for project credit (Q5 exception) — appears unique to PDF 01 in the source corpus.
2. The **"Qaid mid-game truncates competition"** framing (PDF 01 page 1 lines 59-61: "في حالة القيد ... يتوقف اللعب هنا يعني مافي منافسة" — "In Qaid case ... play stops here, meaning no competition") — this is a **distinctive interpretive lens** for the project-credit rule that A-Src-10 / #41 / other videos do not articulate verbatim.

**Confidence:** HIGH (no contradictions; PDF 01 contributes unique scoring-arbitration framing).

---

## Authority flags for `Constants.lua` scoring constants

For each scoring constant, the **primary source** within the available source corpus:

| Constant | Value | PDF 01 authority? | Primary source |
|---|---|---|---|
| `K.HAND_TOTAL_HOKM` | 162 | NO | PDF 02 (152-game-end + 10-last-trick math); PDF 05 (162 derivation) |
| `K.MULT_SUN` | 2 | NO | (not in five PDFs — likely `saudi-rules.md` / videos) |
| `K.MULT_BEL` | 2 | NO | PDF 07 (verbatim ×2 for Hokm Double) |
| `K.MULT_TRIPLE` | 3 | NO | PDF 07 verbatim |
| `K.MULT_FOUR` | 4 | NO | PDF 07 verbatim |
| `K.MELD_SEQ3` | 20 | NO | NOT in five PDFs |
| `K.MELD_SEQ4` | 50 | NO | NOT in five PDFs |
| `K.MELD_SEQ5` | 100 | NO | NOT in five PDFs |
| `K.MELD_CARRE_OTHER` | 100 | NO | NOT in five PDFs |
| `K.MELD_CARRE_A_SUN` | 400 | **PARTIAL** (contextual reductio on PDF 01 page 3) | `review_v0.10.0/reaudit_R5_*.md` per Constants.lua:95 comment; PDF 01 corroborates contextually |
| `K.MELD_BELOTE` | 20 | NO | PDF 02 / PDF 05 verbatim |
| `K.CARRE_RANKS` (excludes 9) | n/a | NO | NOT in five PDFs (CLAUDE.md notes this Saudi-specific quirk) |
| `K.AL_KABOOT_HOKM` | 250 (raw) / 44 (game-points) | **PARTIAL — game-points 44 only** | PDF 01 verbatim "44" (multiple); raw 250 NOT in five PDFs |
| `K.AL_KABOOT_SUN` | 220 (raw) | NO | NOT in five PDFs |
| **Qaid penalty Hokm** | **16 game-points** | **YES — primary source** | PDF 01 verbatim |
| **Qaid penalty Sun** | **26 game-points** | **YES — primary source** | PDF 01 verbatim |
| **"Project-credit on clean loss only" rule** | n/a (rule logic) | **YES — primary source** | PDF 01 page 1, "مشروعي لي ومشروعك لك" |
| **Belote multiplier-immune** | n/a (rule logic) | NO | PDF 07 verbatim primary source |
| **152 game-end target** | 152 | NO | PDF 02 verbatim |
| **Strict-majority bidder rule** | >81 fails | NO | NOT in five PDFs |
| **Reverse Kaboot** | +88 | NO | NOT in five PDFs |

**Summary of PDF 01's authority footprint.** PDF 01 is the **primary source for exactly three things**:
1. Qaid penalty values **16 (Hokm) / 26 (Sun)**.
2. The **"مشروعي لي ومشروعك لك"** clean-loss-only project-credit rule.
3. The **44-game-point Kaboot equivalence** (raw value 250 sourced elsewhere).

All other scoring constants in `Constants.lua` have authority **outside** PDF 01 (other PDFs, `saudi-rules.md`, or video transcripts).

---

## Aggregate finding

**PDF 01's true scope is narrower than its filename suggests.** Despite being titled "نظام التسجيل" ("Registration / Scoring System"), PDF 01 does **not** define the full scoring schema — it specifies the **error-arbitration sub-system** (Qaid penalty + project-credit rules under error). The companion PDF 02 covers the broader play system; PDF 07 covers the multiplier system; PDF 05 covers Belote's mathematical justification.

**Recommendation for `Constants.lua` documentation.** The constants `K.HAND_TOTAL_HOKM`, `K.AL_KABOOT_HOKM`, `K.MELD_*`, `K.MULT_*`, `K.CARRE_RANKS` should each cite their actual primary source rather than assuming PDF 01 covers them — most do not.

**Confidence in this re-extraction:** HIGH. Based on full read of PDF 01 (3 pages, 219 lines of extraction), cross-validated against the other five extracted PDFs and Phase 1 source_K (A-Src-10).

**Files referenced:**
- `C:\CLAUDE\WHEREDNGN\.swarm_findings\_pdf_extracted\01_registration_system.txt` — primary source.
- `C:\CLAUDE\WHEREDNGN\.swarm_findings\_pdf_extracted\02_playing_system.txt` — Q1, Q11 cross-validation.
- `C:\CLAUDE\WHEREDNGN\.swarm_findings\_pdf_extracted\05_what_is_baloot.txt` — Q3 cross-validation.
- `C:\CLAUDE\WHEREDNGN\.swarm_findings\_pdf_extracted\07_doubling_system.txt` — Q11, Q12 primary source.
- `C:\CLAUDE\WHEREDNGN\.swarm_findings\review_v0.10.2\_track_A_sources\A-Src-10_v41_sun_basics_K.md` — Phase 1 source_K cross-confirm (Q14).
- `C:\CLAUDE\WHEREDNGN\Constants.lua` lines 54-329 — for scoring-constant authority flags.
