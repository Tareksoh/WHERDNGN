# A-Src-23 — Re-extraction of PDF 03 (سر الاحتراف في لعبة البلوت ١ / Secrets of Pro 1) for v0.10.2 advanced-strategy audit

**Source.** `C:\CLAUDE\WHEREDNGN\.swarm_findings\_pdf_extracted\03_secrets_pro_1.txt` (full file read — 1 page total, 50 lines, single-page PDF).

**Trigger.** Phase 1 source_L extraction (`review_v0.10.0/_phase1_sources/source_L_pdf_secrets_doubling.md:18-74`) catalogued items L01-L06 from this PDF as "card-counting fundamentals." This re-extraction independently re-verifies each L01-L06 quote against the underlying PDF text, confirms verbatim Arabic, looks for any rules missed by Phase 1, and answers the v0.10.2-specific questions on tier-distinguishing rules, hand-shape categories, and cross-references to the other Pro PDFs (03b, 04).

**Headline finding (Confidence: HIGH).**

PDF 03 is **a single-page, six-rule introductory primer on card-counting** in Saudi Baloot. The author opens with a foundational principle ("متابعة مايسقط من الوراق و عدها ومعرفة ماتبقى منها" — "tracking what falls of the cards, counting them, and knowing what remains") then enumerates five numbered "احترافيات" (pro-isms / advanced techniques). All six rules concern *card-counting and slough/escape (تهريب) reading*; none discuss bidding-card requirements (which appear in PDF 03b), meld project-elimination (which appears in PDF 04), conceptual scoring (PDF 05), or doubling escalation (PDF 07). **No hand-shape category names (محشور, مكشوف, مردوف, etc.) appear in PDF 03 at all** — those are sourced from other documents in the corpus. The PDF establishes that card-counting is the *defining* skill that separates a pro from a non-pro player ("لن يصبح محترفا بهذه اللعبة" — "[without it] he will not become a pro at this game"), making the entire content tier-distinguishing-by-construction.

The Phase 1 L01-L06 cataloguing is **fully accurate**. This re-extraction surfaces no new rules in PDF 03 itself, but identifies one verbatim-corrected reading (the L42 anomaly "44") and re-verifies all six quotes are within the ≤15-word ceiling.

---

## Q1 — Card-counting fundamentals (per Phase 1 source_L L01-L06)

### Q1a — L01: Card-counting is the foundational pro skill (the master equation)

**Status. PRESENT — verbatim verified.**

The PDF opens by stating an explicit "معادلة أساسية" (fundamental equation) without which a player cannot become a pro.

- **Verbatim Arabic (≤15 words):** «متابعة مايسقط من الوراق و عدها ومعرفة ماتبقى منها»
- **English:** "Tracking what falls of the cards, counting them, and knowing what remains."
- **Page reference:** PDF 03, page 1, lines 14-16 of extracted text.
- **Surrounding context (lines 10-16):** Author frames it as «معادلة اساسية البد من معرفتها وتطبيقها في هذه اللعبة واذا تجاهلها الالعب لن يصبح محترفا بهذه اللعبة» — "a fundamental equation that must be known and applied in this game; if a player ignores it he will not become a pro at this game." Then explains: the deck is 4 suits, all four similar, running from King down to Seven (lines 15-16: «اربع جهات فقط وهذه الأربع جهات متشابهة تبدأ من الكه وتنتهي بالسبعة»).
- **Confidence:** HIGH (direct verbatim from primary source).

### Q1b — L02 (Tracking strength): Count your own *strength cards* falling from opponents and partner

**Status. PRESENT — verbatim verified.**

This is the *first* of five numbered "احترافيات" (pro techniques). It narrows the L01 doctrine specifically to *strength cards* (أوراق قوته) — i.e. the high cards in the suits the player holds.

- **Verbatim Arabic (≤15 words):** «أن ينتبه ويعد أوراق قوته التي تسقط من الخصم ومن زميله»
- **English:** "[The player] must pay attention to and count his strength cards that fall from the opponent and from his partner."
- **Page reference:** PDF 03, page 1, lines 20-21 (rule #1).
- **Tail of rule (line 21):** «وكم المتبقي منها» — "and how many remain of them."
- **Confidence:** HIGH.

### Q1c — L03 (Escape-reading): Watch what partner *escapes* (هرّب) to read partner's intent and opponent strength

**Status. PRESENT — verbatim verified.**

Rule #2. The author explicitly states the dual purpose: read partner's intent AND read opponent strength.

- **Verbatim Arabic (≤15 words):** «ينتبه للأوراق التي هربها زميله»
- **English:** "[The player] must pay attention to the cards his partner escapes/discards."
- **Page reference:** PDF 03, page 1, lines 24-26 (rule #2).
- **Surrounding context (lines 24-26):** The full rule explains the WHY — «وذلك لكي يعرف ماذا يريد زميله وماذا عليه ان يمسك من الأوراق لكي يحافظ على اللعبة ويعرف قوة الخصم» — "so that he knows what his partner wants, what cards he must hold to preserve the round, and learns the opponent's strength." (≤15-word verbatim alternative: «يعرف ماذا يريد زميله وماذا عليه ان يمسك من الأوراق».)
- **Confidence:** HIGH.

### Q1d — L04 (Deficit-aware sloughing): Know your accumulated points before round-end so you can decide what to escape

**Status. PRESENT — verbatim verified.**

Rule #3. This is the most operationally specific rule in the PDF — it gives a worked example.

- **Verbatim Arabic (≤15 words):** «يعرف العدد الذي حصل عليه من أوراق اللعبة قبل نهايتها»
- **English:** "[The player] must know the number/count he has obtained from the round's cards before its end."
- **Page reference:** PDF 03, page 1, lines 28-32 (rule #3).
- **Worked example (lines 30-32):** «فمثلا المتبقي على الخسارة هو العدد عشرة فيقوم بتهريب الكه لزميله بدلا من الاحتفاظ بها» — "for example: if the deficit-to-loss is the number 10, he sloughs the King to his partner instead of retaining it."
- **Precondition (lines 34-35):** «بشرط أن يكون الخصم احل اللعب مسبقا» — "*on condition that the opponent has bought / claimed the round in advance*" (i.e. the player applying this rule is the **defender**, not the bidder).
- **Confidence:** HIGH.

### Q1e — L05: When partner reveals his need, send him your biggest card

**Status. PRESENT — verbatim verified.**

Rule #4. The companion to L03 — having read partner's escapes, *act* on it by sending the highest card.

- **Verbatim Arabic (≤15 words):** «يأتيه بأكبر ما لديه من ورقة»
- **English:** "He brings him the biggest card he has."
- **Page reference:** PDF 03, page 1, lines 38-39 (rule #4).
- **Surrounding context (line 38):** «اذا تابع اللاعب ما يهربه زميله من الأوراق وتبين له ماذا يريد زميله» — "if the player has followed his partner's escapes and what his partner wants has become clear to him."
- **Confidence:** HIGH.

### Q1f — L06: Hold opponent's strength suit; do NOT escape your own strength prematurely

**Status. PRESENT — verbatim verified (with one extraction-text anomaly).**

Rule #5. This is the most strategically loaded rule and contains the corrupted "44" string flagged in Phase 1 L42.

- **Verbatim Arabic (≤15 words):** «يحتفظ بها ولا يهربها حتى لو اضطر لتهريب قوته»
- **English:** "He retains them [opponent's strength cards] and does not escape them, even if he is compelled to escape his own strength."
- **Page reference:** PDF 03, page 1, lines 42-46 (rule #5).
- **Tail with anomaly (lines 43-46):** «لكي يتفادى ال 44 ولا يهرب قوته إلا بعد عد ماسقط منها وكم تبقى منها مع الخصم وذلك عن طريق التهريب» — "so as to avoid the (44?) and does not escape his strength except after counting what has fallen of [opponent's strength] and what remains of it with the opponent, by means of escape." The "44" is most plausibly a corrupted rendering of «الفل» / «الفلة» (failing) or a literal "4-4" tied-trick scenario; the surrounding logic clearly establishes that the goal is to *avoid losing the round*.
- **Confidence:** HIGH on the rule semantics; MEDIUM on the literal "44" reading (matches Phase 1 L42 caveat).

---

## Q2 — Verbatim Arabic for each rule

Consolidated table of the six fundamental quotes (each within the 15-word ceiling):

| ID | Verbatim Arabic | Word count | Page |
|---|---|---|---|
| L01 | «متابعة مايسقط من الوراق و عدها ومعرفة ماتبقى منها» | 8 | 03:1 line 14 |
| L02 | «أن ينتبه ويعد أوراق قوته التي تسقط من الخصم ومن زميله» | 11 | 03:1 line 20 |
| L03 | «ينتبه للأوراق التي هربها زميله» | 5 | 03:1 line 24 |
| L04 | «يعرف العدد الذي حصل عليه من أوراق اللعبة قبل نهايتها» | 10 | 03:1 line 28 |
| L05 | «يأتيه بأكبر ما لديه من ورقة» | 6 | 03:1 line 39 |
| L06 | «يحتفظ بها ولا يهربها حتى لو اضطر لتهريب قوته» | 9 | 03:1 line 42 |

All six quotes are well within the ≤15-word ceiling. **All six are verbatim from the PDF text** with only minor diacritical normalization (PDF 03 lacks consistent hamzas / shadda — adjusted to standard MSA spelling for matching against canonical references).

---

## Q3 — New rules NOT in Phase 1 — list with confidence

**Status. NONE FOUND — verbatim verified.**

After full re-read of `03_secrets_pro_1.txt` (lines 1-50), the PDF contains exactly **six numbered teachings** (the master equation L01 + five numbered rules L02-L06). Phase 1 source_L correctly enumerated all six. No additional rules, sub-rules, examples, or exception-clauses are present in the PDF that were missed by Phase 1.

The three near-rules that *could* have been split out as separate items but weren't:

| Possible split | Where it appears | Why Phase 1 was right not to split |
|---|---|---|
| **N1.** "The deck has 4 similar suits, K-down-to-7" | line 15-16 (intro paragraph) | This is a Baloot definitional fact, not a strategy rule. Confidence: HIGH that it's not a separate rule. |
| **N2.** "Defender precondition for L04" — «بشرط أن يكون الخصم احل اللعب» | line 34-35 (after rule #3) | This is a *qualifier* on L04, not a free-standing rule. Phase 1 captured it in the L04 entry's note. Confidence: HIGH. |
| **N3.** "Escape-after-counting" sub-clause in L06 — «ولا يهرب قوته إلا بعد عد ماسقط منها» | line 45 (within rule #5) | This is part of L06's body, not a separate teaching. Confidence: HIGH. |

**Conclusion: Phase 1's six-rule enumeration (L01-L06) is canonical and complete for PDF 03.**

---

## Q4 — Tier-distinguishing rules (advanced-tier-only)

**Status. PRESENT — entire PDF is tier-distinguishing by construction (Confidence: HIGH).**

The PDF *explicitly frames itself* as the threshold between non-pro and pro play. The opening paragraph (lines 10-16) states:

- **Verbatim Arabic (≤15 words):** «اذا تجاهلها اللاعب لن يصبح محترفا بهذه اللعبة»
- **English:** "If a player ignores it [the master equation], he will not become a pro at this game."
- **Page reference:** PDF 03, page 1, lines 11-12.
- **Confidence:** HIGH.

This frames **every rule in the PDF as tier-distinguishing by construction** — Basic-tier bots (random-legal) ignore card-counting entirely; Advanced-tier bots track card-counts; M3lm/Fzloky/Saudi-Master add escape-reading and deficit-awareness on top. Mapping to the codebase tier ladder (per `CLAUDE.md` "Bot tier dispatch"):

| PDF 03 rule | Earliest tier where the rule should activate | Code locus |
|---|---|---|
| L01 (track all cards falling) | Advanced (`WHEREDNGNDB.advancedBots`) | `Bot.PickPlay` per-trick state tracking |
| L02 (track *own strength* falling specifically) | Advanced | `Bot.PickPlay` strength-suit awareness |
| L03 (escape-reading partner) | M3lm (`m3lmBots`) | `Bot.PickPlay` partner-style ledger |
| L04 (deficit-aware sloughing, defender-only) | M3lm | `Bot.PickAKA` / `pickFollow` deficit calculation |
| L05 (send biggest to partner once need is read) | M3lm | `Bot.PickPlay` biggest-card-to-partner heuristic |
| L06 (hold opp's strength, defer own strength) | Fzloky (`fzlokyBots`) | `Bot.PickPlay` extended slough logic |

L06 is the most demanding (requires combined opponent-strength tracking + own-strength tracking + sequencing logic) and is the most plausible candidate for a Fzloky/Saudi-Master-only gate.

**No rule in PDF 03 explicitly names a tier** — the tiering above is inferred from operational complexity, not stated.

---

## Q5 — Cross-references to other Pro PDFs

**Status. NONE — PDF 03 stands alone (Confidence: HIGH).**

The PDF contains **no internal references** to PDFs 03b (Secrets of Pro 2), 04 (Secrets of Pro 3), 05 (What is Baloot), or 07 (Doubling System). The author closes after rule #5 (line 46) without preview/forward-reference language.

However, the *thematic* relationship to the other Pro PDFs is clear and is captured at the source-L cross-cluster level:

| PDF 03 rule | Cross-references in the corpus (added by re-extractor, not in PDF 03) |
|---|---|
| L01 (master equation) | L10 (PDF 04) "12 visible cards" inference base — operationalizes L01 for early-trick deduction |
| L02 (track own strength) | L20-L21 (PDF 05) — the per-suit point tables that *define* what "strength" means |
| L03 (read partner's escapes) | Cross-thematic with the AKA signal in #18 / source_G — but **AKA is NOT mentioned in PDF 03**. PDF 03's "escape-reading" is informational reading from voluntary slough, distinct from the explicit AKA convention. |
| L04 (deficit-aware sloughing) | L34 (PDF 07) "bidder needs only 52 raw to win in Sun" — gives the dual deficit math for Sun |
| L06 (hold opp's strength) | L11-L17 (PDF 04) project-negation tables — *what* opp's strength suit might be, deducible from visible cards |

**No bidirectional reference exists in either direction** — PDFs 04, 05, and 07 likewise do not reference back to PDF 03. The cluster is *thematically* unified by source_L's Phase 1 framing, not by author cross-referencing.

---

## Q6 — Hand-shape categories named (محشور, مكشوف, مردوف, etc.) — verbatim

**Status. NONE PRESENT in PDF 03 (Confidence: HIGH).**

A targeted grep for the canonical Saudi hand-shape category terms returned **zero hits** in PDF 03:

- `محشور` (mahshoor / "crammed/heavy") — 0 hits
- `مكشوف` (makshoof / "exposed/open") — 0 hits
- `مردوف` (mardoof / "backed-up", as in Ace+10) — 0 hits
- `بشاش` / `ضحاب` / `بارجي` (other hand-shape coinages) — 0 hits

The PDF uses only generic strategic vocabulary:
- «أوراق قوته» (his strength cards)
- «أوراقه» (his cards)
- «الكه» (the King)
- «التهريب» / «هرب» / «هربها» (escape / sloughing)
- «الخصم» (opponent), «زميله» (partner)
- «اللعبة» (the round/game)
- «حل اللعب» (claimed/bought the round)

**Hand-shape categorization terminology comes from elsewhere in the corpus**, primarily:
- `مردوف` — defined in PDF 03b L08 («الاكه المردوفة بعشرة») as "Ace backed by Ten" — see source_L L08 (`review_v0.10.0/_phase1_sources/source_L_pdf_secrets_doubling.md:91-99`).
- `محشور` / `مكشوف` — sourced from video transcripts (e.g. video #14 hand-shape, see `A-Src-05_v14_bargiya_hand_shape.md`), NOT from PDF 03.

If the audit needs canonical hand-shape terminology, **PDF 03 is not a source** — refer instead to the video re-extractions in `A-Src-05` (#14) and to PDF 03b (`A-Src-22` if extracted, or source_L L08 directly).

---

## J. Re-extraction summary count

| Question | Item | Status | Confidence |
|---|---|---|---|
| Q1a | L01 master equation | PRESENT, verbatim verified | HIGH |
| Q1b | L02 tracking strength | PRESENT, verbatim verified | HIGH |
| Q1c | L03 escape-reading | PRESENT, verbatim verified | HIGH |
| Q1d | L04 deficit-aware sloughing | PRESENT, verbatim verified | HIGH |
| Q1e | L05 send biggest to partner | PRESENT, verbatim verified | HIGH |
| Q1f | L06 hold opp strength / defer own | PRESENT, verbatim verified (44 anomaly noted) | HIGH (rule) / MEDIUM (44 reading) |
| Q2 | All 6 verbatim ≤15 words | TABULATED above | HIGH |
| Q3 | New rules not in Phase 1 | NONE FOUND | HIGH |
| Q4 | Tier-distinguishing rules | ALL 6 are tier-distinguishing by construction | HIGH (framing) / MEDIUM (specific tier mapping) |
| Q5 | Cross-references to other Pro PDFs | NONE in PDF 03 itself; thematic only | HIGH |
| Q6 | Hand-shape categories (محشور / مكشوف / مردوف) | NONE PRESENT in PDF 03 | HIGH |

---

## K. Audit hooks for v0.10.2 review

Re-extraction confirms the source_L L01-L06 cataloguing is canonical for PDF 03. The highest-leverage **code touchpoints** flagged by these rules:

| Rule | Code touchpoint to verify |
|---|---|
| L01 | Per-trick card-counting state — does any tier maintain "cards seen" outside of `BotMaster.PickPlay` ISMCTS rollouts? |
| L02 | *Strength-specific* tracking (count Aces/Tens/Kings remaining per suit) — `Bot.PickPlay` advanced-tier check |
| L03 | Partner escape-reading — `Bot.PickPlay` reading partner's voluntary sloughs, distinct from AKA signal |
| L04 | Defender-side deficit calculation — verify gated on `S.s.contract.bidder ~= player.team` |
| L05 | "Biggest card to partner once need is read" — `Bot.PickAKA` / `pickFollow` AKA-receiver heuristic |
| L06 | Opp-strength-suit retention — verify `Bot.PickPlay` *holds* opponent strength cards before sloughing own; tier gate likely Fzloky |

The 44-anomaly in L06 (Phase 1 L42) remains unresolved at the source level; **audit team should consult the original PDF visually if a rule depends on the literal "44" string.**

This concludes the A-Src-23 re-extraction.
