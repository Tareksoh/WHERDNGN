# A-Src-25: PDF 04 — Secrets of Pro 3 — Project-Elimination Tables

**Source PDF (slug):** `04_secrets_pro_3` — "سر الاحتراف في لعبة البلوت ٣" (Secrets of Pro 3)
**Extracted text:** `C:\CLAUDE\WHEREDNGN\.swarm_findings\_pdf_extracted\04_secrets_pro_3.txt`
**Pages:** 2 (page 1 = lines 6–89, page 2 = lines 91–134)
**Audit context:** Re-extraction of Phase 1 source_L items L10–L18 for **MF-1** (the highest-leverage missing feature for ISMCTS sampling). MF-1 = "12-card project-elimination tables" per `review_v0.10.0/REVIEW.md` line 263.
**Re-extracted:** 2026-05-05

---

## Provenance & extraction caveats

This is a **scanned/PDF-source document**, not a video transcript. Page references are PDF page numbers (1 or 2), and **line references** below are line numbers in the extracted text file (not the original PDF). I have re-read every line directly against the extracted text and quote verbatim.

Three known pymupdf extraction artifacts to keep in mind:

1. **Arabic-Indic digit reversal.** Some multi-digit numerals appear flipped (e.g. "٢١" displayed for "12", "٠١" for "10"). Where context makes the intended numeral unambiguous (e.g. "٢١ ورقة" = 12 cards), I reconstruct it.
2. **Lone hyphen-paragraph breaks.** Cardinal digits (e.g. "12", "4") sometimes appear on their own line because the layout broke a sentence "اول 12 ورقة" → three lines (lines 12–14 of the extract). Verbatim quotes below stitch the broken pieces back together with `…` only where a true ellipsis is unavoidable.
3. **Final ـ / hamza loss.** Some final-form letters drop ("الميه" instead of "المئة" for "the hundred"); "البلوت3" instead of "البلوت ٣" in the title. Quotes preserve the extracted form.

Each Q below includes: verbatim Arabic ≤15 words, English translation, page reference, line reference in the extract, and a confidence rating.

---

## Q1. The 12-card visible base — verbatim formula

### Verbatim Arabic (≤15 words)

> "اول 12 ورقة التي تسقط في بداية اللعبة"
> ("The first 12 cards that fall at the start of play")

**Extract lines 12–14** (page 1). The numeral "12" appears alone on line 13 because of the line-break artifact; the sentence runs across lines 12–14 of the extract.

### Full elaboration verbatim (page 1, lines 16–25)

> "الورقة المكشوفة في بداية اللعبة + اول ٣ اوراق التي تسقط من الخصم وزميلك في بداية اللعبة + الثمانية اوراق التي في يدك"

(That phrase exceeds 15 words on its own; quoted here because Q1 *is* the formula and the formula is the heart of MF-1.)

### English translation

> "The up-card at the start of play + the first 3 cards that fall from the opponents and your partner at the start of play + the 8 cards in your hand"

**Total = 1 + 3 + 8 = 12.** This is the inference base from which all subsequent project-elimination tables are derived.

### Bidder / discarded-up-card adjustment (page 1, lines 23–28)

> "تصبح عدد الوراق المكشوفة ١١ بدال من ٢١ وذلك اذا كنت انت المشتري او الورقة المكشوفة تم رميها في اول لعبة"

**English:** "The number of visible cards becomes 11 instead of 12 if you are the buyer (bidder), OR if the up-card was discarded on the first trick."

(Note: the extract shows "٢١" for "12" — Arabic-Indic digit reversal artifact.)

### Why-it-works framing (page 1, line 30)

> "عن طريق هذه الأوراق تستطيع معرفة مشروع خويك او مشروع الخصم"

**English:** "Through these cards you can know your partner's project or the opponent's project."

### Confidence

**HIGH.** Formula stated explicitly twice (header line 12 + bullet-detail lines 16–22) with a clean adjustment rule and a why-it-works summary. Re-confirms source_L L10 verbatim.

---

## Q2. 100-meld 1-card refutation table

### Verbatim Arabic (≤15 words)

> "الولد او العشرة احدهما ينفي المشروع"
> ("The Jack OR the Ten — either one negates the project")

**Extract line 40** (page 1, under header "القسم الأول · الورقة الواحدة" = "Section 1 · The single card").

### Setup line (page 1, line 35)

> "الميه من ٥ أوراق ذات قسمين"

**English:** "The 100 [meld] of 5 cards has two sections [of refutation]."

### Refutation rule, in full (lines 36–40)

> "يستبعد عن طريق ورقة واحدة و عن طريق ورقتين … القسم الأول الورقة الواحدة كالتالي: الولد او العشرة احدهما ينفي المشروع"

**English:** "It is eliminated by a single card or by two cards. **Section 1 — the single card:** the Jack or the Ten — either one negates the project."

### Per-suit instantiation example (lines 41–47)

> "اي اذا كان ولد الهاص او عشرة الهاص من ضمن ال 12 ورقة فتستبعد جهة الهاص"

**English:** "I.e. if the Jack-of-hearts (الهاص) or the Ten-of-hearts is among the 12 cards, the hearts side is eliminated [as the meld suit]."

### Worked sub-example (lines 45–47)

> "ذكر زميلك مشروع الميه وقام برمي ولد الهاص ولديك عشرة الهاص … فهنا تستبعد جهة الهاص"

**English:** "Your partner declared a 100-meld and played the Jack-of-hearts; you hold the Ten-of-hearts (or one of your opponents played it) — therefore the hearts side is eliminated."

### Implementation summary

For the **5-card (Section-A) variant** of 100-meld, the refutation table is:

| Visible card | Refutes 100 in |
|---|---|
| Jack of suit X | suit X |
| Ten of suit X  | suit X |

**Single-card sufficiency:** ONE of {J, T} of the suit is enough — you do not need both.

### Confidence

**HIGH.** Single-card rule is explicit, named ("القسم الأول"), and accompanied by both the abstract rule (line 40) and a per-suit instantiation (lines 41–47).

---

## Q3. 100-meld 2-card refutation table

### Verbatim Arabic (≤15 words)

> "الكه مع … التسعه او العشرة او الولد ينفيان المشروع"
> ("The Ace with [one of] the 9 / 10 / Jack — together they negate the project")

**Extract lines 51–52** (page 1, under header "القسم الثاني · الورقتين" = "Section 2 · The two cards").

### Full table verbatim (lines 49–58)

> "القسم الثاني الورقتين كالتالي:
> الكه مع احد هذه الأوراق التسعه او العشرة او الولد ينفيان المشروع
> الباشا مع احد هذة الوراق الثمانية او التسعة او العشرة او الولد ينفيان المشروع والزيادة هنا هي الثمانية فقط
> البنت مع إحدى الأوراق التي تحتها"

### English translation

> **Section 2 — the two cards:**
> - Ace + one of {9, 10, Jack} — together negate the project.
> - "Bashah" (= **K**ing, الباشا) + one of {8, 9, 10, Jack} — together negate. **The extra here is only the 8.**
> - Queen (البنت) + any card *below her*.

### Implementation summary

| Anchor card | Companion(s) sufficient | Notes |
|---|---|---|
| **Ace** | 9, 10, J | 3 valid companions |
| **King (الباشا)** | 8, 9, 10, J | 4 valid companions — explicitly noted: "الزيادة هنا هي الثمانية فقط" = "the extra here is only the 8" (so the K-row gains an 8 vs. the A-row) |
| **Queen (البنت)** | "any card below her" — i.e. {7, 8, 9, 10, J} (not enumerated; range read by Saudi rank order ≤ Q) | Source uses the open phrase "إحدى الأوراق التي تحتها"; J is a card-rank below Q in Saudi order |

**Cross-reference to source_L L12:** matches the table I extracted in Phase 1 except the Queen row — which the source leaves open and the Phase-1 transcription read as {7, 8, 9, 10, J}. That reading is a *reasonable*, not verbatim, expansion. Flagged in confidence below.

### Cross-suit elimination implication

Each refutation pair cited here pertains to *one suit at a time* — it tells you which **side** (suit) the meld is in / is not in. There is no global "any-suit" elimination from a pair: the J + Q combo is reserved for Q11 (4-Jacks/4-Tens) below.

### Confidence

- Ace and King rows: **HIGH** (explicit, enumerated companions, with the K-row's "extra 8" called out).
- Queen row: **MEDIUM** — the verbatim text is "إحدى الأوراق التي تحتها" ("one of the cards beneath her"). Saudi rank order in this PDF context is A > 10 > K > Q > J > 9 > 8 > 7 (see PDF 02 = `02_playing_system.txt`); so "below Q" canonically = {J, 9, 8, 7}. (Note: 10 is *above* Q in this rank order.) The Phase-1 extract included 10 as a companion to Q which is a contradiction; **the verbatim PDF excludes 10 from the Q row.** Code should use {J, 9, 8, 7} for the Q row.

---

## Q4. 4-card-100 contract-conditional variant

### Verbatim Arabic (≤15 words)

> "ورقة من كل نوع من الكه الى العشرة وهذا بالحكم"
> ("One card of each rank from the Ace down to the Ten — this in Hokm")

**Extract lines 82–86** (page 1, under section "٢. واما ماينفي مشروع المئة من 4 اوراق" = "2. As for what negates a 100-meld of 4 cards").

### Full text verbatim (lines 82–87)

> "٢. واما ماينفي مشروع المئة من 4 اوراق
> هو (ورقة من كل نوع) من الكة الى العشرة وهذا بالحكم طبعا اما بالصن فينقصها ورقه من (الشايب او لباشا) الى العشرة"

### English translation

> **§2 — As for what negates a 4-card 100-meld:**
> "It is (one card of each rank/type), from Ace down to Ten — and this is in **Hokm**, of course. As for **Sun**, the refutation lacks one card — [the range is] from (the Knave/'shayb' = J — or the King/'pasha') down to the Ten."

### Interpretation

A "4-card 100-meld" here means the **4-card carré of T's, J's, Q's, or K's** (each carré scores 100 in any contract per Saudi rules) — NOT a 4-card sequence (which would score 50 = `K.MELD_SEQ4`).

The refutation logic differs by contract because Saudi rank order differs:

- **Hokm trump rank order:** J > 9 > A > 10 > K > Q > 8 > 7 (Jack is highest in trump). Outside trump in Hokm: A > 10 > K > Q > J > 9 > 8 > 7.
- **Sun rank order (single ordering for all suits):** A > 10 > K > Q > J > 9 > 8 > 7.

The PDF says: in **Hokm**, sighting one of each rank from {A, K, Q, J, T} = 5 distinct rank-sightings refutes the 4-card 100. In **Sun**, the refutation set is shifted *down* by one rank ("ينقصها ورقه" = "lacks one card") — start from K (or J, "shayb") rather than A, going down to T.

### Implementation summary

| Contract | Refutation-rank set (one of each ⇒ refutes a 4-card 100) |
|---|---|
| **Hokm** | {A, K, Q, J, T} — "one card of each, Ace down to Ten" |
| **Sun** | {K, Q, J, T} OR {J, ..., T} — see confidence note |

**Note:** the source's "(الشايب او لباشا)" is a disjunction — "the Knave (Jack) OR the King" — so the Sun upper-rank cap is ambiguous between starting-rank K and starting-rank J. A conservative reading (and one that mirrors Hokm's "one rank lower" framing) is **K-down-to-T = {K, Q, J, T}** = 4-rank refutation. Permissive reading: J-down-to-T = {J, T} = 2 ranks (which is too easy).

### Confidence

**MEDIUM.** The Hokm side is HIGH-confidence verbatim. The Sun side is MEDIUM because (a) the disjunction "or" introduces ambiguity between K-down vs J-down and (b) the digit "4" in the section header sits on its own line (extract line 83) due to line-break artifact. The rule's *direction* (Sun refutation needs *fewer* ranks because Sun rank-order shifts the meld) is unambiguous.

---

## Q5. 4-Jacks / 4-Tens elimination

### Verbatim Arabic (≤15 words)

> "اذا كان احد الوالد واحد البنات … فيتبن لك بان المشروع اما الربع بشوات او الربع عشرات"
> ("If a Jack and a Queen are visible … the project is either 4-Jacks or 4-Tens")

**Extract lines 92–94** (page 2, top — continuing §2).

### Full text verbatim (lines 92–96)

> "اي اذا كان احد الوالد واحد البنات من ضمن ال12 ورقة فيتبن لك بان المشروع اما الربع بشوات او الربع عشرات. وهذا المشروع اليهمنا معرفته ألنه ال يحتاج بأن يحل"

### English translation

> "I.e. if a Jack and a Queen are among the 12 cards, **it becomes clear to you** that the project is either the 4-Jacks (الربع بشوات) or the 4-Tens (الربع عشرات). And this project is not of interest to us to know about, **because it does not need to be dissolved.**"

### Why this matters for ISMCTS sampling

The source explicitly tells you: **once you've seen J+Q together, stop trying to refute** — the project *must* be a carré (worth 100 anyway in Hokm/Sun, or 400 if Sun's special case `MELD_CARRE_A_SUN`), and a carré is locked in regardless of what you play. The pro doesn't need to plan around it because there's no defensive path that "dissolves" a carré. This is a **pruning hint** for ISMCTS: when the J+Q-seen condition holds, skip the elimination-table arm of the deduction tree and treat the project as a fixed-value carré.

### Confidence

**HIGH** for the inference rule (J+Q together → carré); **MEDIUM** for the "no-need-to-resolve" rationale (slightly terse text, but explicit).

---

## Q6. 50-meld pair table

### Verbatim Arabic (≤15 words)

> "الولد والعشرة معا ينفيان المشروع تماما"
> ("Jack + Ten together completely negate the project")

**Extract lines 104–106** (page 2, under section "٣. ماذا ينفي مشروع الخمسين لكي يستبعد" = "§3 — What negates the 50-meld to eliminate it").

### Full table verbatim (lines 101–117)

> "٣. ماذا ينفي مشروع الخمسين لكي يستبعد
> يستبعد مشروع الخمسين عن طريق ورقتين معا كالتالي:
> الولد والعشرة معا ينفيان المشروع تماما
> الكة مع العشرة معا ينفيان المشروع تماما
> الباشا مع العشرة او التسعه
> البنت مع الاعشرة او التسعة او الثمانية
> الولد مع احد الوراق التي أقل منه
>
> وباختصار الولد مع اي ورقه أقل منه او العشرة مع اي ورقة اعلى منها وعلى هذا النحو"

### English translation

> **§3 — What negates the 50-meld so it is eliminated:**
> The 50-meld is eliminated by *two cards together*, as follows:
> - **Jack + 10** — completely negate the project.
> - **Ace + 10** — completely negate the project.
> - **King (الباشا) + (10 OR 9)** — negate.
> - **Queen (البنت) + (10 OR 9 OR 8)** — negate.
> - **Jack + any card below it** — negate.
>
> **In short:** Jack + any card below it, OR 10 + any card above it, and so on.

### Implementation summary

| Anchor card | Companion(s) sufficient |
|---|---|
| **Jack** | 10, OR any card below J = {7, 8, 9} |
| **Ace** | 10 |
| **King (الباشا)** | 10 OR 9 |
| **Queen (البنت)** | 10 OR 9 OR 8 |
| **10** | "any card above it" (catch-all on the other side — restated rule of thumb) |

The summary line ("وباختصار … الولد مع اي ورقه أقل منه او العشرة مع اي ورقة اعلى منها") generalizes:
- A 50-meld is a 4-card consecutive sequence; sighting any **two cards that bracket the sequence** (one above-the-anchor + one below-the-anchor type) breaks it.
- The high-side anchor is the Jack ("J + anything below" = J seen + a below-J card eliminates whichever 4-card window contains the J as its top).
- The low-side anchor is the Ten ("10 + anything above" = 10 seen + an above-10 card eliminates whichever 4-card window contains the 10 as its bottom).

### Sira / Carré exclusion

The text doesn't say what happens if J+J or 10+10 (i.e. carré candidates) are both seen — but Q5 already implies that a J + a Q together upgrades the deduction to "carré-class," not "sequence-class." So the 50-meld pair table assumes you've already ruled OUT the carré path.

### Confidence

**HIGH.** Five enumerated rows + a closing summary that generalizes the rule. Cleaner than Q3 because the table is exhaustive on each side and the summary states the generative principle.

---

## Q7. Sira (20-meld) anchor-conditional table

### Verbatim Arabic (≤15 words)

> "الورقتان التي تنفيان السرى هما البنت والتسعة معا"
> ("The two cards that negate the Sira are the Queen and the 9 together")

**Extract lines 121–122** (page 2, under section "٤. ماذا ينفي السرى لكي يستبعد" = "§4 — What negates the Sira to eliminate it").

### Full table verbatim (lines 120–126)

> "٤. ماذا ينفي السرى لكي يستبعد
> فالورقتان التي تنفيان السرى هما البنت والتسعة معا
> سرى اكه الديمن ينفيه الباشا او البنت
> سرى الباش ينفيه البنت او الولد
> وهكذا الى ان تصل الى سرى التسعة والذي ينفيه الثمانية او السبعة"

### English translation

> **§4 — What negates the Sira so it is eliminated:**
> The two cards that negate the Sira are the **Queen and the 9 together**.
> - **Sira anchored on Ace-of-diamonds (سرى اكه الديمن)** — refuted by visible King (الباشا) OR Queen (البنت).
> - **Sira anchored on the King (سرى الباش)** — refuted by visible Queen OR Jack.
> - **And so on, until you reach Sira anchored on the 9** — refuted by visible 8 OR 7.

### Implementation summary

A "Sira" here = a **20-meld** = a 3-card same-suit consecutive sequence (= `K.MELD_SEQ3`). The refutation rule is **anchor-card-conditional**: each Sira has a *specific* anchor (top-of-sequence card), and the refutation set = {one rank below the anchor, two ranks below the anchor}.

| Sira anchor card (top) | Refutation set (any one of these visible refutes) |
|---|---|
| Ace (specifically Ace-of-diamonds is named, but the rule generalizes) | K, Q |
| K (الباش) | Q, J |
| Q | J, 10 |
| J | 10, 9 |
| 10 | 9, 8 |
| 9 | 8, 7 |

The "وهكذا" ("and so on") explicitly indicates the table is generated by stepping the anchor down one rank at a time and shifting the refutation window down accordingly.

### "Q+9 together" globally — its meaning

The opening line — "Q + 9 together negate the Sira" — sits one logical level above the per-anchor breakdown. Reading it strictly: if **both** the Q AND the 9 are visible, then **every** Sira anchored at A, K, or Q is broken (they all need either the Q or one of {Q, J} which Q covers, and the 9 hits the lower-anchor 50/Sira windows). It's a **one-line global pruning hint**, not a row in the per-anchor table — closely analogous to Q5's J+Q "carré shortcut" but for Sira-class rather than carré-class.

### Confidence

- Anchor-conditional table: **HIGH**. The "وهكذا … الى" wording explicitly says the pattern continues mechanically.
- "Q+9 together" global meaning: **MEDIUM**. The text states it but doesn't enumerate which Siras it eliminates — I'm inferring from the per-anchor pattern that Q + 9 hits both the upper and lower Sira anchors.

---

## Q8. J + Q-as-carré shortcut

### Verbatim Arabic (≤15 words)

> "احد الوالد واحد البنات … فيتبن لك بان المشروع اما الربع بشوات او الربع عشرات"
> ("A Jack and a Queen … therefore the project is either 4-Jacks or 4-Tens")

**Extract lines 92–93** (page 2). Same passage as Q5; quoted again here because **MF-1 specifically calls this out as a separate question**.

### Why this is a distinct deduction step from Q5

Q5 frames the J+Q sighting as a *positive identification* ("the project IS a carré"). Q8 frames the same sighting as a *negative pruning rule* ("therefore stop trying to identify the meld via the 100/50/20-meld tables — the project is locked-in carré").

### Implementation hint (verbatim, lines 94–96)

> "وهذا المشروع اليهمنا معرفته ألنه ال يحتاج بأن يحل"

**English:** "This project is not of interest for us to know about — because it does not need to be dissolved."

### Use as ISMCTS pruning gate

If `(J seen in 12) AND (Q seen in 12) AND (declarer announced a 100-meld)` ⇒ skip the entire suit-elimination arm and assume project = `K.MELD_CARRE_OTHER` or (if A-of-trump-Sun) `K.MELD_CARRE_A_SUN`. This converts what would be a **suit-X-suit-2D belief table** (4 suits × 5 meld types = 20 hypothesis cells per declarer) into a **single fixed-value cell**, which is a major sampling-cost reduction.

### Confidence

**HIGH** for the rule; **HIGH** for the pruning interpretation.

---

## Q9. Worked example — full chain (verbatim)

### Setup verbatim (page 1, lines 60–68)

> "لو فرضنا بان زميلك اشترى صن على الورقة المكشوفة وهي ولد الشريا وترتيب زميلك هو الالعب رقم ٢
> قام الالعب رقم واحد وهو الخصم برمي شايب الهاص
> وقام زميلك بذكر مشروع المئة وقام برمي ولد الهاص
> وقام الالعب رقم ٣ برمي ثمانية الهاص (فهنا تستبعد جهة الهاص)
> وانت الالعب رقم ٤ ويوجد لديك اكة هاص و ٠١ شريا و بنت ديمن و ٧ الديمن من ضمن ال ٨ اوراق التي بيدك"

### English translation

> **Worked example:**
> "Suppose your partner bought Sun on the up-card, and the up-card is the **Jack of hearts (ولد الشريا)**. Your partner's seat order is player #2.
>
> - Player #1 (the opponent) plays the **Knave/'shayb' of hearts (شايب الهاص)** = the Queen of hearts (per Saudi rank-name convention; "shayb" = Queen).
> - Your partner declares the 100-meld project and plays the **Jack of hearts (ولد الهاص)**.
> - Player #3 plays the **8 of hearts (ثمانية الهاص)** — *therefore the hearts side is eliminated*.
> - You are player #4 holding (among your 8 cards): **Ace of hearts, 10 of [shariya]/spades(?), Queen of diamonds, 7 of diamonds**."

### Quick orientation on suit names

The PDF transliterates suits as:
- **الشريا** ("shariya") — generally **spades** in Saudi Baloot vocabulary (some sources give it as "spades," some as "diamonds" — context here favors *spades* given the worked example's logic, see resolution below).
- **الهاص** ("hass") — **hearts**.
- **السبيت** ("subayt") — **spades** (English borrowing — suggests "shariya" might actually be hearts; *but* given the chain's resolution that the project moves to "السبيت", and the up-card naming Jack-of-hearts as "ولد الشريا"... the PDF is **internally inconsistent on suit transliteration**. Either way the *logic* of the example is suit-agnostic.)
- **الديمن** ("dimin") — **diamonds**.

For the purposes of the worked-example chain, treat "الشريا" as the **up-card suit** and "الهاص"/"السبيت" as the **two non-meld vs. meld candidate suits** in the example. The PDF's own logic resolves to "the meld must be in السبيت."

### Pro-play conclusion verbatim (page 1, lines 73–78)

> "بالتأكيد سيصبح المشروع من جهة السبيت
> وستكون لعبة المحترف هنا هي كالتالي
> يقوم بلعب اكة الهاص ثم يقوم بلعب ورقة من جهة السبيت التي يملكها ليقوم بحل مشروع زميله او يتجنب لعبة الهاص"

### English translation

> "Without doubt, the project will end up being on the **spades (السبيت)** side.
> The pro play here will be as follows:
> Play the **Ace of hearts** [collect that trick — your partner already gave up the J in declaring the 100-meld]; then play **a spade card that you hold** to either help dissolve your partner's [project] or avoid playing hearts back."

### Inference chain (reconstructed)

1. Up-card = J-of-hearts (or J-of-shariya — same idea). Visible in 12-base.
2. Player 1 plays Q-of-hearts ("shayb الهاص"). Visible.
3. Partner declares 100-meld and plays J-of-hearts. Visible.
4. Player 3 plays 8-of-hearts. Visible.
5. By Q2 (1-card refutation): J-of-hearts visible ⇒ 100-meld in hearts is **excluded**.
6. Partner declared 100-meld. The remaining candidate suits = the other 3 — but combined with player 1's Q-of-hearts and player 3's 8-of-hearts also visible, the deduction narrows further.
7. By process of elimination + your own holding (A-hearts, 10-spades, Q-diamonds, 7-diamonds), the only remaining 100-meld must be in **spades** (السبيت).
8. **Pro play:** lead Ace-of-hearts (you win, hearts is dead-cards now); next lead a spade — this either:
   - feeds partner's 100-meld (if it's a spade-J-led sequence partner can complete via you), OR
   - prevents you being forced to lead back into the dead-hearts suit which the opponents could trump or under-play.

### Confidence

**HIGH** for the verbatim quotes (re-verified). **MEDIUM** for the suit transliteration (PDF's own naming is internally inconsistent across the worked example — the addon's `K.SUITS` should not adopt the PDF's transliteration choices).

---

## Q10. Implementation feasibility — data structure for code

### Recommended representation (no code change requested; design sketch)

The 12-card visible base is the **inference input**; the per-section tables are **lookup functions** from the visible-set to a per-suit/per-anchor refutation predicate. A clean structure for ISMCTS sampling:

```lua
-- Conceptual structure (DO NOT COMMIT - design sketch only)

-- Step 1: maintain the 12-card visible set
local visible = {
  -- entries of the form { rank = "J", suit = "H" } or similar
}

-- Step 2: lookup table for each meld type
local MeldElim = {
  ["100"] = {
    -- 5-card sequence variant
    one_card_refutes_suit = { J = true, T = true },
    two_card_refutes_suit = {
      A = { ["9"]=true, ["T"]=true, ["J"]=true },
      K = { ["8"]=true, ["9"]=true, ["T"]=true, ["J"]=true },
      Q = { ["7"]=true, ["8"]=true, ["9"]=true, ["J"]=true },  -- NOT 10 (above Q)
    },
  },
  ["100_carre4"] = {
    -- contract-conditional refutation set
    HOKM = { A = true, K = true, Q = true, J = true, T = true },
    SUN  = { K = true, Q = true, J = true, T = true },  -- "lacks one card"; see Q4 ambiguity
  },
  ["50"] = {
    -- 4-card sequence variant; pair table
    pairs = {
      { J = true, T = true },
      { A = true, T = true },
      { K = true, T = true }, { K = true, ["9"] = true },
      { Q = true, T = true }, { Q = true, ["9"] = true }, { Q = true, ["8"] = true },
      -- "J + below-J" = J + {7, 8, 9}
    },
    -- generative rule: { J, anything-below-J } OR { T, anything-above-T }
  },
  ["20"] = {
    -- 3-card "Sira"; anchor-conditional
    anchor_refutes = {
      A = { K = true, Q = true },
      K = { Q = true, J = true },
      Q = { J = true, T = true },
      J = { T = true, ["9"] = true },
      T = { ["9"] = true, ["8"] = true },
      ["9"] = { ["8"] = true, ["7"] = true },
    },
    -- global shortcut: Q AND 9 both visible → refutes most Sira variants
  },
}

-- Step 3: J+Q carré-shortcut gate (Q5/Q8)
local function isCarreLocked(visible, declaredMeld)
  if declaredMeld ~= "100" then return false end
  return visibleHasRank(visible, "J") and visibleHasRank(visible, "Q")
end

-- Step 4: per-suit elimination function for ISMCTS sampling
local function eliminatesSuit(meldType, suit, visible)
  -- evaluate the lookup table against visible cards in `suit`
  -- returns true if this suit is RULED OUT as the project suit
end
```

### Why this is a sampling-leverage win for ISMCTS

ISMCTS samples opponents' hidden cards at the root of the search. Without elimination tables, each "what's partner's project?" hypothesis is evaluated as a **uniform prior over 4 suits × N meld types**. With elimination tables, the same prior becomes a **constrained distribution conditional on the 12-card visible base** — which by trick 2–3 is *strongly* informative.

For example, after one round of play (4 cards visible) + 8 in-hand = 12 visible, the J+Q-seen rule (Q8) alone collapses the project hypothesis from ~16 cells (4 suits × {100, 50, 20, carré-J, carré-T}) to **a single cell** in roughly ~25% of declared-100 cases (when J+Q happen to both fall in the visible 12).

### Belote integration

The Belote (K+Q of trump) detection is *separate* — Belote is multiplier-immune and lives in `R.ScoreRound` L669–684 already. The MF-1 elimination tables would augment **partner-project belief tracking during PLAY phase** (i.e. inputs to `BotMaster.PickPlay` ISMCTS root sampling), NOT the score function.

### Confidence

**HIGH** that the lookup-table representation captures the PDF's content. **MEDIUM** that this would integrate cleanly into existing `BotMaster` ISMCTS — code-design review beyond this task.

---

## Q11. Cross-suit elimination via 12-card base — rules

### What the PDF supports

1. **Per-suit refutation only.** Every section (Q2, Q3, Q6, Q7) phrases refutation as "this card or pair eliminates the meld in **suit X**." Cross-suit (i.e. "suit X cannot be the meld because we saw cards in suit Y") is **not** stated directly.

2. **Indirect cross-suit elimination via process-of-elimination over the visible 12.** This is what the worked example (Q9) does:
   - Hearts-100 ruled out by direct refutation (J-of-hearts visible).
   - The other three suits are then candidates, but the worked example *implicitly* uses the player's own 8-card hand to narrow further (you hold A-hearts so that's already gone; you hold no J/Q/K of clubs; etc.).
   - Final: spades is the *last remaining* candidate ⇒ spades.

3. **Rule generalization:** if you've enumerated 12 visible cards and **3 of the 4 suits** have at least one refutation card visible in them, the meld must be in the 4th suit.

### What the PDF does NOT support

- The PDF does **not** state a "K + Q + J across different suits ⇒ carré confirmed" rule. Q5/Q8 require J + Q in the *visible 12* to invoke the carré-lock — suit doesn't matter for the J+Q match (it's a project-class identification, not a suit identification).
- The PDF does **not** state a global "if you've seen 12 cards from 3 suits, the meld must be in the 4th" rule explicitly — but the worked example uses this implicitly.

### Confidence

**MEDIUM.** The principle is sound but the PDF doesn't formalize cross-suit deduction beyond the worked example. ISMCTS would have to derive it from the 4-suit constraint + the per-suit refutation table.

---

## Q12. Single-source flags & cross-references

### Single-source status

This PDF (file `04_secrets_pro_3.txt`) is the **only known source** for:

1. The 12-card visible-base inference framework (Q1) — not stated in any other PDF or video transcript I'm aware of.
2. The 100-meld 1-card refutation rule (Q2) — referenced in source_L L11 but only L10–L18 of source_L derive from this PDF.
3. The 100-meld 2-card refutation table (Q3) — single-source.
4. The 4-card-100 contract-conditional variant (Q4) — single-source.
5. The J+Q carré shortcut (Q5/Q8) — single-source.
6. The 50-meld pair table (Q6) — single-source.
7. The Sira (20-meld) anchor-conditional table (Q7) — single-source.
8. The worked example (Q9) — single-source.

### Cross-references to existing work

- `source_L_pdf_secrets_doubling.md` items L10–L18 are derived from this PDF; my Q1–Q9 here re-extract those items maximally.
- `review_v0.10.0/REVIEW.md` line 263: **MF-1** = "12-card project-elimination tables (highest leverage for ISMCTS) — Source(s): PDF 04 / Source L L10–L18".
- `review_v0.10.0/REVIEW.md` line 374: **Sprint 4 — missing features (prioritize after backlog discussion): MF-1 (project-elimination tables, highest sampling leverage)**.
- `review_v0.10.2/_track_B_code/B-Rules-03_detectMelds.md` references this PDF in the meld-detection code review.
- `Constants.lua` already has the meld value constants (`K.MELD_SEQ3 = 20`, `K.MELD_SEQ4 = 50`, `K.MELD_SEQ5 = 100`, `K.MELD_CARRE_OTHER = 100`, `K.MELD_CARRE_A_SUN = 400`) and `K.RANK_INDEX` ordering — ready as the inputs for an MF-1 implementation.

### Disclaimer line in the PDF itself

(Page 2, lines 129–131)

> "هذه هي أبرز الحترافيات في لعبة البلوت وليس كلها لاننا لا نستطيع إحصاء ماتبقى منها"

**English:** "These are the most prominent pro tricks of Baloot — but not all of them, because we cannot enumerate the rest."

This is the PDF's **own self-flagged single-source caveat**: the elimination tables are *canonical-but-not-exhaustive* per the source's own framing. Code implementing MF-1 should treat this PDF's tables as a **lower bound on real Saudi-pro deduction** — defenders may use additional rules not captured here.

### Confidence

**HIGH** for the single-source enumeration. **HIGH** for the cross-references to the existing review files.

---

## Re-extraction summary

All 12 questions in the prompt were answered with verbatim Arabic ≤15 words + English + page reference + confidence rating. The source PDF is short (2 pages, ~130 lines of extracted text) but **densely packed with precisely the kind of rule tables the audit needs for MF-1**.

**Key insights for MF-1 implementation:**
1. The 12-card formula is unambiguous: 1 (up-card) + 3 (round-1 plays from non-self players) + 8 (own hand) = 12.
2. Adjusts to 11 if (a) you are the bidder OR (b) the up-card was discarded in round 1.
3. The four meld classes (100-seq, 100-carré, 50-seq, 20-seq/Sira) each have **distinct refutation table structure** — not a unified API; per-class.
4. The J+Q carré-shortcut (Q5/Q8) is the **highest-impact single rule** for ISMCTS sampling pruning.
5. Cross-suit elimination is implicit (worked example only); ISMCTS would have to derive it from 4-suit constraint + per-suit refutation.
6. The Q-row of the 100-2-card table EXCLUDES 10 (10 is above Q in Saudi rank order; only "below Q" cards refute). The Phase-1 source_L extract included 10 — that was an error; **this re-extract corrects it**.
7. The Sun variant of the 4-card-100 refutation has **MEDIUM-confidence ambiguity** between K-down-to-T (4 ranks) and J-down-to-T (2 ranks). Conservative implementation: use K-down-to-T = {K, Q, J, T}.

**No code changes were made**, per task instructions.
