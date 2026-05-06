# Reaudit R7: Glossary collisions

Resolution of four naming collisions surfaced in Phase 1 sources A, B, E, F. Output is advisory: code-side tasks listed in "Recommended actions" require user approval before execution per CLAUDE.md.

---

## Takbeer — escalation vs play-signal

### What "Takbeer" actually means in source material
- **Video #21 (Sun magnification, `Xxsf2QvaiU0`):** the word **التكبير** appears 25+ times across the transcript. Every occurrence refers to **playing your highest card on a partner-led trick** to donate point cards (ابناء). Source E Rule E21-1 quotes line 11: `تكبير يعني تعطيه اكبر الاوراق اللي معك` ("Takbeer means giving them the biggest cards you have"). Anti-pattern at lines 114-123: playing Q when you also hold J = "ما كبرت خويك" (you did NOT magnify your partner).
- **Video #22 (Hokm magnification, `Rmx3GipsNuo`):** Identical semantics, applied to Hokm trump rank order. Lines 24-73 explicitly: `التكبير في الحكم` ("magnification in Hokm") = same play-time concept under Hokm's J>9>A>10>K>Q>8>7 ordering.
- **Source E Rule EX-1** explicitly flags: "Takbeer in these videos refers to **partner-direction card play** (play your highest), NOT the contract escalation chain Bel→Bel×2→Four→Gahwa."

### What the speaker actually calls Bel-x2 in video #11
- **Video #11 (`21fN1IEm5Xk`)** uses these terms exclusively for the escalation chain (lines 24-200+):
  - **الدبل (Dabal)** = Bel = ×2
  - **ثري (Theri)** = ×3
  - **فور (Four)** = ×4
  - **القهوة (Gahwa)** = match-win
- **The word "تكبير" never appears in video #11.** Speaker also does NOT use "مكبر" (mukabbar / "magnified") or "مثلث" (muthallath / "tripled") for the ×3 rung. The ×3 rung is **ثري (Theri)**, a loan-word from English "three", or alternatively **الدبل** (when escalating "the Dabal again").

### Code-side identifier audit
- `Constants.lua:71` — `K.MULT_TRIPLE = 3  -- ثري — bidder's response after Bel (×3)`
- `Constants.lua:125-127` — `K.PHASE_TRIPLE`, `K.PHASE_FOUR`, `K.PHASE_GAHWA`
- `Constants.lua:169-171` — `K.MSG_TRIPLE = "3"`, `K.MSG_FOUR = "4"`, `K.MSG_GAHWA = "5"`
- `Constants.lua:168` — `K.MSG_DOUBLE = "X"` (the ×2 "Bel" message, NOT MSG_BEL)
- `Bot.lua:3412` `Bot.PickTriple`, `Bot.lua:3443` `Bot.PickFour`, `Bot.lua:3488` `Bot.PickGahwa`, `Bot.lua:3265` `Bot.PickDouble`
- `Bot.lua:2516` — comment correctly uses `Takbeer / التكبير = donate HIGHEST point card to partner's [trick]`
- `Bot.lua:2457-2460` — comments reference "Takbeer" with the correct play-signal meaning
- `tests/test_state_bot.lua:762, 791` — Takbeer tests verify play-signal semantics

### Verdict — DISAMBIGUATE (no rename needed)

The code identifiers `MULT_TRIPLE` / `PHASE_TRIPLE` / `MSG_TRIPLE` / `PickTriple` are English shorthand and **are NOT named "Takbeer" in code**. The collision exists only in a hypothetical: if anyone were to rename them to "Takbeer", that would conflict with the play-signal usage already established in Bot.lua comments and tests.

**Glossary already gets it right** (`glossary.md:38-66`):
- Saudi name for ×3 listed as **بل×2 (Bel x2)** OR **ثري (Theri)** — both confirmed by video #11.
- "Theri" is explicitly noted as in active use; previous claims to the contrary corrected.

The existing `glossary.md` "Takbeer / Tasgheer" section at lines 267-277 correctly defines Takbeer as the magnify play-signal, NOT escalation.

**No code rename is required.** What IS missing: an explicit one-line warning in the escalation table that **"Takbeer" is NEVER the name of the ×3 rung** — to prevent future contributors from "fixing" the perceived gap by renaming.

---

## Bargiya / Burqia

### Are these spelling variants of the same Arabic word?

**YES — same Arabic word, same concept, transliteration variants.**

- The Arabic root is **برق** (b-r-q, "lightning/telegraph"). The noun form is **بَرقيّة** (barqiyya, "telegram") — the message a card sends.
- Diacritic-free Arabic spelling is identical in both transcripts: **برقيه** / **برقية** (same letters, different ya' final form is allographic).

### Source-by-source spelling check
- **Video #14 (`n1FBrNNVUAA`):** uses **البرقيه** consistently (lines 24, 38, 94, 304, 314, 524, 1984, 2244, 2474, 2544+ — 30+ occurrences). Source B Rule 1 quotes verbatim: `اقوى تهريب في البلوت الا وهو تهريب الاكه او البرقيه`.
- **Source A (videos 01-10):** uses **بَرقيه / burqia** (Source A's transliteration choice). Source A explicitly notes "Speakers do NOT use the word 'Bargiya' explicitly in this cluster, but the form-4 = burqia" — this is a **transliteration disagreement between the two analysts**, NOT a different Arabic word.
- **Source B Rule 1** quote and **Source A Rule 19** quote both reference Form 4 (Ace-as-tahreeb signal). Identical mechanic. Identical Arabic word.

### Code-side identifier audit
- `Bot.lua:1575` — `"bargiya" — partner discarded the Ace; lead-this-back signal`
- `Bot.lua:1612` — `return "bargiya_hint"`
- `Bot.lua:243, 562, 1572, 1584, 1589, 1593, 1597, 1609, 1737, 1741, 1767, 1773, 1789, 1796, 1798, 1808, 2553, 2591, 2599` — all use **bargiya** spelling consistently

### Verdict — KEEP "bargiya" as canonical

Code already standardized on **bargiya** (single canonical spelling). Source B uses Bargiya. Source A uses burqia but they refer to the same Arabic word. No ambiguity in the underlying concept. Glossary entry at `glossary.md:225` correctly uses Bargiya.

**Recommended:** add a one-line note to glossary that **burqia** is an alternative romanization of the same Arabic word **برقيّة**, so future contributors reading Source A don't think it's a different concept.

---

## Mathlooth

### Concept definition

**مثلوث (mathlooth)** = "tripled" = a 3-card hand-shape in a single suit. The Arabic root ث-ل-ث (th-l-th, "three"). The CANONICAL referent is **J + 2 sidekicks under SUN contract**, where J becomes the 3rd-highest card (after A, T) once those higher cards are exhausted.

Per Source F Rule F3.01:
- Title "K-tripled" is a romanization artifact in the video filename — the actual referent is the **JACK** (الشايب = Shayeb), not the King.
- The 3-card holding lets you survive tricks 1-2 (sidekicks burn), then deploy J on trick 3.

Per Source A Rule 18, the term is also used for a **3-card non-stacked** holding (e.g. 10 + Q + 8 with a gap), where the cards are NOT a connected sequence — distinct from مردوفة (mardoofa, 2-card stacked) and سرد (sard, 3-card stacked).

These two usages are compatible: مثلوث simply means "3-card shape in a suit"; the Sun-J-with-2-sidekicks case is the most strategically named instance.

### In glossary? YES (partially)

`glossary.md:333` already has:
- `مثلوث (mathlooth) | "Tripled" — 3 cards in a suit | 02, 17`

This is correct but **minimal**. Source F Rules F3.01–F3.20 (20 rules!) develop the J-Mathlooth as a major concept: it's a defensive formation against Kabūt, has specific deployment patterns (trick 3 capture), and is the subject of an entire video.

`decision-trees.md:123-128` has a "K-tripled (مثلوث الشايب) — 3-card K-holding" section — this uses the **wrong English label**. Per Source F Rule F3.01 the canonical case is **J-tripled** (Shayeb = J, NOT K). The decision-trees label is the mistranslation Source F flagged.

### Should be added/updated? YES — needs correction

Update `glossary.md:333` to expand:
- Note that "مثلوث الشايب" specifically = J + 2 sidekicks under Sun (the canonical strategic case), with J becoming top-card after A and T are spent (Sun rank order A>T>J).
- Note that الشايب = J (already covered in card-name slang at `glossary.md:322` — but cross-link this).
- Cite videos #02 and #17.

Update `decision-trees.md:123` heading from "K-tripled" to "J-tripled (Mathlooth)" — the K label is the wrong romanization and Source F explicitly corrects it.

### NOT tied to Bel-x2

Source F Rule F3 (entire cluster) confirms: Mathlooth is a **hand-shape concept**, NOT a multiplier mechanic. The user's prompt question "is Mathlooth missing concept that needs adding to glossary?" — answer: it's already there at minimal depth, but **the J-vs-K labeling bug in decision-trees.md needs fixing**.

---

## Tanfeer (تنفير vs تنفيذ)

### Glossary entry
- `glossary.md:234-241` (Tanfeer section) and `glossary.md:236-240` carry the exact warning needed:
  > "Caption-error warning: YouTube auto-captions for Saudi Arabic frequently render تنفير (tanfeer, 'repulsion') as **تنفيذ** (tanfeedh, 'execution'). The two words sound nearly identical to ASR. The correct term is **تنفير** throughout."

### Source video confirms

- **Video #12 transcript** (the Tanfeer-explained video, F2 cluster) actually contains BOTH spellings in the auto-captions:
  - Line 24: `نتكلم على مصطلح التنفيذ` (mislabeled)
  - Line 54: `التنفير او كلمه تنفر في اللغه العربيه` (the correct word, with verb form **تنفر** confirming the root ن-ف-ر)
  - Line 84: `التهريب والتنفيذ` (mislabeled)
  - Line 384: `التنفيذ نوعين اما يكون تنفير بقصد` (BOTH in same line — auto-caption inconsistency)

This is exactly the ASR homophone error pattern the glossary warns about. The narrator says **تنفير** (tanfeer = "repulsion/scaring-away/discarding"), and ASR sometimes hears it as **تنفيذ** (tanfeedh = "execution") because the consonants sound similar in fast speech.

The correct root is **ن-ف-ر** (n-f-r, "to flee/repel/scare-away"), matching the strategic concept: discarding cards you want to push away. The wrong root **ن-ف-ذ** (n-f-dh, "to execute/carry out") makes no semantic sense as a Baloot strategy term.

### Source A's "tanfeer/التنفيذ" entry

Source A line 653 lists `التنفيذ (tanfeer/tanfeedh)` as a glossary candidate — but this is the **mistranscribed** form. Source A's analyst quoted the captions verbatim without realizing they're the homophone error. Source B Rule 21 and the Source B terminology section at line 450 already get this right: `Tanfeer (تنفير) / Tanfeez (تنفيذ) — opposite-direction discard (the SAME word — both spellings used interchangeably in the source)`.

### Code-side identifier audit
- `Bot.lua:3033, 3037, 3048` — comments use **Tanfeer / تنفير** with the correct spelling and root
- `tests/test_state_bot.lua:968, 980` — `v0.5.14 Section 9 Tanfeer (تنفير)` — correct
- No code identifier uses "tanfeedh" or "tanfeez"

### Verdict — KEEP تنفير as canonical, no change needed

Code and glossary already correct. Source A's listing of `التنفيذ` was Source A's analyst error inheriting the YouTube auto-caption mistake. The glossary already documents this as a known caption-error pattern.

---

## Recommended actions

### glossary.md updates (low risk, doc-only)

1. **Add anti-rename warning to escalation table (`glossary.md:38-66`):** add a one-line note: "Note: Saudi speakers never use تكبير (Takbeer) for the ×3 rung. تكبير is exclusively the magnification play-signal (see Strategy Terms section below). Do not rename `MSG_TRIPLE` / `PHASE_TRIPLE` to anything containing 'Takbeer'."

2. **Add burqia transliteration alias to Bargiya entry (`glossary.md:225`):** add: "Alternative romanizations: **burqia** (used in some sources). Same Arabic word برقيّة."

3. **Expand Mathlooth entry (`glossary.md:333`):** expand from one line to specify: canonical case = J + 2 sidekicks under Sun (J becomes top after A and T are exhausted, taking trick 3); applies to general 3-card-in-suit shapes; cite videos #02 and #17. Cross-link to شايب (Shayeb = J) at `glossary.md:322`.

4. **Tanfeer entry: no change needed.** Existing caption-error warning at `glossary.md:236-240` is the correct fix.

### Code identifier renames

**None required.** The code uses English shorthand (TRIPLE/FOUR/GAHWA/DOUBLE) for the escalation rungs and Arabic-derived names (bargiya, tanfeer) for play signals. There is no current code identifier collision because:
- `MULT_TRIPLE`/`PickTriple` are NOT named "Takbeer" — only the comments would have been wrong, and they're already correct
- `bargiya` is already the single canonical spelling in code
- `Tanfeer` (when referenced) uses the correct spelling
- Mathlooth is not a code identifier (it's a hand-shape concept used in comments only)

### decision-trees.md updates

1. **Fix mistranslation at `decision-trees.md:123`:** change heading `K-tripled (مثلوث الشايب) — 3-card K-holding` to `J-tripled (Mathlooth, مثلوث الشايب) — 3-card J-holding`. Update the two table rows below (lines 127, 128) to reference J (Shayeb) instead of K. The Sun rank order A>T>J makes the J become top-card on trick 3 — that's the entire mechanic; calling it K-tripled inverts the rank logic.

2. **Optional:** the existing Takbeer/Tasgheer rows at `decision-trees.md:112-119` are already correct — no change needed.

---

## Confidence

- **Takbeer disambiguation: HIGH.** Direct verbatim quote check across video #11 (escalation, no تكبير occurrences) and videos #21/22 (play-signal, 25+ تكبير occurrences). Cross-confirmed by Source E Rule EX-1 explicit flag.
- **Bargiya/Burqia same-word: HIGH.** Diacritic-free Arabic identical (برقيه = برقية = برقيّة). Both Source A's "burqia" and Source B's "Bargiya" cite the same form-4 Ace-tahreeb mechanic with the same Arabic phrase quote.
- **Mathlooth = J-tripled (not K-tripled): HIGH.** Source F Rule F3.01 directly states the title was a mistranslation; rank-logic confirms (Sun A>T>J makes J the relevant card on trick 3, not K which has lower point/rank value).
- **Tanfeer root = تنفير (not تنفيذ): HIGH.** Verb form `تنفر` (line 54 of video #12) confirms the n-f-r root. Both Source B's terminology table and the existing glossary caption-error warning corroborate.
- **No code renames required: HIGH.** Direct grep of Constants.lua and Bot.lua confirms: no `Takbeer*` identifier exists for escalation; `bargiya` is the sole spelling in code; `Tanfeer` only appears in comments with correct spelling.
