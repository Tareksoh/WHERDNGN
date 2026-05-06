# A-Src-22 — PDF 02: نظام اللعب في البلوت (Playing System)

**Source file**: `C:\CLAUDE\WHEREDNGN\.swarm_findings\_pdf_extracted\02_playing_system.txt`
**Source PDF**: `نظام اللعب في البلوت.pdf` (3 pages)
**Extracted**: 2026-05-05
**Mandate**: Re-extract foundational play rules; resolve Phase 1 K-finding contradictions.
**Quote rule**: Arabic verbatim ≤15 words per question.

---

## Q1. Target = 152 vs 251

**Verbatim (Arabic, ≤15 words):**
> "ًاوال: اللعب يكون ٢٥١"

**English:** "First: play is to 251."

**Adjacent context (line 11):** "أي يبدأ من الصفر وينتهي عند النقطة ٢٥١." — "i.e. starts from zero and ends at the point 251."

**Page reference:** Page 1, line 10–11 (item ًاوال / "First").

**Resolution of Phase 1 contradiction:** Phase 1 K-extraction said "251" — **PDF 02 confirms 251, NOT 152.** Number is unambiguous (٢٥١) and stated twice (header + clarifying sentence).

**Confidence:** **High**. Verbatim, twice-stated, unambiguous numerals.

---

## Q2. Bid order + Ashkal seat eligibility

**Verbatim (Arabic, ≤15 words):**
> "ًثالثا: يحق لالعب الثالث والرابع الشكل فقط"

**English:** "Third: only player 3 and player 4 are entitled to Ashkal."

**Page reference:** Page 1, line 19 (item ًثالثا / "Third").

**K-37 apparent contradiction context:** Page 1 lines 28–31 add a *condition* on the Ashkal call itself, not on which seats may call:

> Verbatim (≤15 words): "بشرط أن يكون المشترى ب الشكل الول وليس الثاني"
> English: "On condition that the purchase be by the first Ashkal, not the second."

This means: when player 3 issues an Ashkal, the buyer must take it on the **first** Ashkal call, because there is no third call (line 29: "بسبب ان ليس له ثالث" — "because there is no third for him"). Same logic applies to player 4 (line 30–31: "ونفس الكالم مع الالعب الثالث والرابع" — "the same applies to player 3 and player 4").

**Resolution of K-16 vs K-37:** No contradiction. **K-16 is correct (only seats 3 & 4 may Ashkal).** K-37's "first Ashkal vs second Ashkal" is a *transaction-level* constraint (buy must close on the first Ashkal because there's no third bid available to that seat), not a seat-eligibility constraint.

**Additional K-finding from page 3, line 199–200:**
> "يحق لالعب ان يشكل ب الول والثاني"
> English: "A player is entitled to Ashkal on the first and second [calls]."

This page-3 note refers to the **eligible buyer** (across whose call an Ashkal can target), not which seat *issues* the Ashkal. Reconciles cleanly: seats 3 & 4 issue; the Ashkal targets the first/second buyer.

**Confidence:** **High** for "only seats 3 & 4 may issue Ashkal." **Medium-High** for the buyer-side first/second nuance (Arabic phrasing terse).

---

## Q3. Sun-Double rule (caller ≤100 AND opposite ≥101)

**Verbatim (Arabic, ≤15 words):**
> "واليحق لالعب ان يدبل خصمة ال بعد ان يتجاوز المئة اي ١٠١"

**English:** "A player may not Double his opponent except after [the opponent] exceeds 100, i.e. 101."

**Page reference:** Page 2, line 81 (item ًسابعا / "Seventh").

**Adjacent context (line 77–80):** "ًسابعا: في حالة الدبل او الثري او الفور او :القهوة ففي الصن اليوجد الثري والفور والقهوة وانما يلعب ًدبال .فقط" — "Seventh: in the case of Double / Triple / Four / Gahwa: in Sun there is no Triple, no Four, no Gahwa — only Double is played."

**Reading:** The threshold is on the **opponent** (the side being doubled), not the caller. The PDF says you may not Double the opponent **until that opponent has crossed 100 (i.e. ≥101).** This is the inverse framing of the Phase 1 K phrasing "caller ≤100 AND opposite ≥101"; the Arabic only states the opponent-≥101 condition explicitly. The "caller ≤100" half is **not stated verbatim** in PDF 02.

**Resolution:** Verbatim PDF text supports only the **opponent-≥101 condition.** The "caller ≤100" half of the K-finding is *not* sourced to PDF 02 and must be confirmed elsewhere or treated as inferred.

**Confidence:** **High** for opponent-≥101. **Low** for caller-≤100 (not in PDF 02).

---

## Q4. Sun escalation truncation (Triple/Four/Gahwa)

**Verbatim (Arabic, ≤15 words):**
> "ففي الصن اليوجد الثري والفور والقهوة وانما يلعب ًدبال .فقط"

**English:** "In Sun there is no Triple, no Four, no Gahwa — only Double is played."

**Page reference:** Page 2, line 78–80 (item ًسابعا / "Seventh").

**Page-3 nuance (line 174–177):**
> Verbatim (≤15 words): "كما هو الحال في .الصن اليحق لالعب ان يعطي الثري"
> English: "As in Sun, a player is not entitled to give the Triple..."
> Continuation (line 175–177): "ماهو ممنوع ولكن ماله داعي" — "it is not forbidden, but there is no point."

**Resolution of K-21 vs K-33:** Both are partly right.
- **Page 2 (rule-section, ًسابعا)** says authoritatively: in Sun there is no Triple/Four/Gahwa — supports K-21 ("no Triple/Four/Gahwa in Sun").
- **Page 3 (commentary, "بعض المالحظات")** softens this for Triple specifically: "not forbidden, just pointless" — supports K-33.
- **Reconciled:** As a *legality* rule, the page-2 text uses "اليوجد" ("does not exist") which is structural exclusion. The page-3 author's clarification ("ماهو ممنوع ولكن ماله داعي" — "not forbidden, but no point") narrows it: Triple is technically *callable* in Sun but redundant because Sun's Double already saturates the multiplier ladder for that contract.
- **For Four/Gahwa:** Page 2 explicitly excludes them; page 3 only addresses Triple. So Four/Gahwa remain forbidden in Sun.

**Confidence:** **High** for "no Four, no Gahwa in Sun." **Medium** for "Triple in Sun = pointless not forbidden" (depends on which authority the implementation honors — page-2 rule vs page-3 commentary).

---

## Q5. Foul penalty 16/26 — verbatim with Sun vs Hokm

**Verbatim (Arabic, ≤15 words):**
> "يسجل على الخصم ٦٢ او ٦١ حسب اللعبة"

**English:** "Records against the opponent: 26 or 16 depending on the game."

**Page reference:** Page 1, line 60 (item ًسادسا / "Sixth: in the case of qayd [foul] when an error occurs").

**Adjacent context (line 60–62):**
> Verbatim (≤15 words): "واما المشروع فيكون لصاحبه اويحرم منه واليقيد عليه ال في حالة .الخسارة"
> English: "As for the meld, it [stays] with its owner or he is denied it; it is not recorded against him except in case of loss."

**Reading on Sun vs Hokm penalty values:**
- The PDF text "٦٢ او ٦١" gives **two values: 26 and 16**.
- The phrase "حسب اللعبة" ("depending on the game") is the only mapping cue. PDF 02 does **not** say verbatim which value is Sun and which is Hokm.
- Conventional reading (and consistent with Sun being a ×2 contract): 26 = Sun penalty, 16 = Hokm penalty. **Not directly verbatim from PDF 02.**

**Resolution:** The "26 or 16 depending on the game" phrasing is verbatim. The Sun→26 / Hokm→16 *binding* is **not** verbatim in PDF 02 and is inferred from the multiplier convention.

**Confidence:** **High** for "16 or 26 exists, depending on game." **Medium** for the specific Sun=26 / Hokm=16 mapping (not in PDF 02 verbatim).

---

## Q6. Meld-during-foul — stays with owner vs forfeit

**Verbatim (Arabic, ≤15 words):**
> "واما المشروع فيكون لصاحبه اويحرم منه"

**English:** "As for the meld, it [stays] with its owner OR he is denied it."

**Page reference:** Page 1, line 60 (item ًسادسا).

**Full sentence (line 60–62):** "واما المشروع فيكون لصاحبه اويحرم منه واليقيد عليه ال في حالة .الخسارة" — "As for the meld, it [stays] with its owner or he is denied it; it is not recorded against him except in case of loss."

**Resolution of K vs D-RT-06+B-N3-1 / v0.10.1 M1 arbitration:**
- The PDF text gives a **disjunction**: "لصاحبه" (with owner) **OR** "يحرم منه" (he is denied = forfeit).
- "اويحرم منه" literally is "or [the owner] is deprived of it." This is the **forfeit branch**.
- The PDF does **not** say which branch applies in which situation; the rule is left as either-or with the qualifier that it is only *recorded against* (penalized) in case of loss.
- Phase 1 K's "stays with owner" captures only the first branch; the user-arbitrated "forfeit" captures the second branch. **Both are verbatim in PDF 02 — they coexist as the rule's two outcomes.**

**Reconciliation:** PDF 02 itself says **EITHER outcome is valid** (the disjunction is the rule). The user's arbitration to "forfeit" picks the second branch as the addon's behavior. That choice is *consistent with* PDF 02 (not contradicted), but PDF 02 alone doesn't pick a branch.

**Confidence:** **High** for "PDF allows both outcomes (disjunction)." **Medium** for which branch is canonical — PDF 02 leaves it ambiguous; user arbitration is needed and was given.

---

## Q7. Third privilege rules

**Verbatim (Arabic, ≤15 words):**
> "ًرابعا: اللعب يكون فيه ثالث بشرط"

**English:** "Fourth: play has a Third on condition..."

**Page reference:** Page 1, line 34–38 (item ًرابعا / "Fourth").

**Conditions verbatim (line 36–38):**
> Verbatim (≤15 words): "ان تكون الورقة المكشوفة الكه ويصبح الثالث من حق الالعب الول والثاني فقط"
> English: "That the revealed card be the Ace, and the Third becomes the right of player 1 and player 2 only."

**Additional condition (line 36–38):**
> Verbatim (≤15 words): "بشرط ان تشترى صن وليس .حكم"
> English: "On condition that it is bought as Sun, not Hokm."

**Page-3 corroboration (line 189–191):**
> Verbatim (≤15 words): "الكه ماتقلب صن اذا حكمت ًنهائيا وليس عليها .ثالث"
> English: "The Ace does not flip to Sun if Hokm was called definitively, and there is no Third on it."

**Reading — Third privilege requires ALL of:**
1. Revealed (turn-up) card is the Ace ("الورقة المكشوفة الكه").
2. The contract bought is Sun ("صن"), not Hokm ("حكم").
3. Privilege belongs to **seats 1 and 2 only** ("الالعب الول والثاني فقط").
4. If Hokm is called definitively (not flipped to Sun), Third is unavailable.

**Resolution of Phase 1 K-39 to K-48:** Page 1 + page 3 are mutually consistent. The Phase-1 K range is supported verbatim. **No contradictions found within PDF 02.**

**Confidence:** **High**. Two passages (page 1 rule + page 3 commentary) align verbatim.

---

## Q8. Round-2 Hokm-to-Sun flip

**Verbatim (Arabic, ≤15 words):**
> "الكه ماتقلب صن اذا حكمت ًنهائيا"

**English:** "The Ace does not flip to Sun if Hokm has been called definitively."

**Page reference:** Page 3, line 189–190 (commentary section).

**Reading:** The construction "ماتقلب صن اذا حكمت ًنهائيا" (does-not-flip Sun if Hokm-was-called definitively) describes a **flip mechanic that exists in Hokm-not-yet-definitive states.** The negation in this sentence implies the flip *is* a thing — it is being suppressed *only* once Hokm is final. This is an oblique, indirect reference to a Hokm→Sun flip.

PDF 02 does **not** explicitly describe the round-2 mechanic step-by-step. It only states the *negative* boundary: once Hokm is definitive, the Ace cannot be flipped to Sun.

**Resolution:** PDF 02 alone is insufficient to fully describe the Round-2 Hokm-to-Sun flip mechanic. The boundary condition is verbatim ("does not flip if Hokm definitive"), but the affirmative flip procedure must come from another source (likely PDFs 03/04/05 or videos).

**Confidence:** **Medium-High** for the boundary statement. **Low** for the full flip mechanic from PDF 02 alone.

---

## Q9. Belote cancellation by 100-meld

**Verbatim (Arabic, ≤15 words):**
> "ويلغى اذا كان معه مشروع المئة .فقط"

**English:** "It [the Belote] is cancelled if there is a 100-meld with it, only."

**Page reference:** Page 2, line 140–141 (item ًتاسعا / "Ninth: the Belote").

**Adjacent context (line 127–139):** Belote = K+Q of trump valued at 2; "مفروضا على اللعبة ان تحقق" — "imposed on the game to be achieved."

**Reading:** The Belote is **mandatory to declare** ("imposed"), but it is **cancelled** (its 2-point value is voided) if the same player also has a 100-meld in that round. The qualifier ".فقط" (only) restricts the cancellation trigger to *the 100-meld specifically* — not other melds.

**Resolution of K-31 (single-source):** PDF 02 **independently confirms** K-31 verbatim. K-31 is no longer single-source.

**Confidence:** **High**. Direct verbatim, single sentence in the rule book.

---

## Q10. Strict-majority threshold

**No verbatim hit.**

**Reading:** PDF 02 contains no explicit phrase about strict majority / 81-162 tie loss / who wins on a tied bid. This is a Round-scoring rule, while PDF 02 is the *playing-system* rule book. The strict-majority rule (per CLAUDE.md: "Bidder fails on tied 81/162") must be sourced from another PDF (likely PDF 04 "secrets pro 3" or PDF 06 "third") or video.

**Resolution:** **PDF 02 is silent on strict-majority threshold.** Cannot verbatim-confirm from this source.

**Confidence:** **N/A** — not present.

---

## Q11. Multiplier scope and Belote-immunity

**Indirect verbatim:**

Belote definition (Page 2, line 128–129): "البلوت هو قيمة ثابتة تعادل ٢"
- English: "Belote is a fixed value equal to 2."
- The phrase "قيمة ثابتة" ("fixed value") implies it is **not multiplier-scaled** — i.e. immune to ×2/×4/×8 multipliers. This is consistent with CLAUDE.md's "Belote (K+Q of trump, +20) is multiplier-immune" but PDF 02 says the value is **2**, not 20.

**Note on +2 vs +20:** PDF 02 says "تعادل ٢" (equals 2). CLAUDE.md says "+20." This is likely a units-difference (PDF uses raw small units; addon code uses score-scaled units where everything ×10). **PDF 02 verbatim = 2.**

**Multiplier scope:** PDF 02 only **mentions** Double exists in Sun (line 80–81) and Double/Triple/Four/Gahwa exist in Hokm (line 83–84). It does **not** explicitly state how multipliers apply to base-vs-meld-vs-belote scoring. **No verbatim multiplier-scope statement.**

**Resolution:**
- Belote-immunity to multipliers is **inferred** from "قيمة ثابتة" (fixed value) but **not stated verbatim** as immunity.
- Multiplier scope (what gets multiplied) is **not in PDF 02**.

**Confidence:** **Medium** for Belote-fixed-value-implies-immunity. **Low** for full multiplier scope.

---

## Q12. Phase 1 K single-source flags — independent verification

| Phase 1 K finding | Verbatim hit in PDF 02? | Status |
|---|---|---|
| K (target=251) | **Yes** — line 10 "اللعب يكون ٢٥١" | **Confirmed** |
| K-16 (only seats 3 & 4 may Ashkal) | **Yes** — line 19 "يحق لالعب الثالث والرابع الشكل فقط" | **Confirmed** |
| K-21 (no Triple/Four/Gahwa in Sun) | **Yes** — line 78–80 "في الصن اليوجد الثري والفور والقهوة" | **Confirmed** (with page-3 commentary nuance) |
| K-31 (Belote cancelled by 100-meld) | **Yes** — line 140–141 "ويلغى اذا كان معه مشروع المئة" | **Confirmed — no longer single-source** |
| K-33 (Triple in Sun = pointless not forbidden) | **Yes** — page 3 line 175–177 "ماهو ممنوع ولكن ماله داعي" | **Confirmed (page-3 commentary)** |
| K-37 (Ashkal first vs second contradiction) | **Yes (resolved)** — line 28 "بشرط أن يكون المشترى ب الشكل الول" | **Confirmed — buyer-side rule, NOT seat-eligibility** |
| K-39 to K-48 (Third privilege rules) | **Yes** — line 34–38 + page 3 line 189–191 | **Confirmed** |
| K (Round-2 Hokm→Sun flip) | **Indirect** — line 189–190 negative boundary only | **Partial** — boundary verbatim, mechanic absent |
| K (foul penalty 16/26) | **Yes (split)** — line 60 "٦٢ او ٦١ حسب اللعبة" | **Confirmed — values verbatim, mapping inferred** |
| K (meld-during-foul → owner) | **Disjunction in source** — line 60 "لصاحبه اويحرم منه" | **PDF gives both — user arbitrated to forfeit branch** |
| K (Sun-Double opp ≥101) | **Yes** — line 81 "ال بعد ان يتجاوز المئة اي ١٠١" | **Confirmed for opp-side; caller-side not in PDF 02** |
| K (strict-majority 81/162) | **No** | **Not in PDF 02** — must source elsewhere |
| K (Belote multiplier-immune) | **Indirect** — line 128 "قيمة ثابتة" (fixed value) | **Inferred, not verbatim immunity claim** |
| K (no Carré on 9s) | **No** | **Not in PDF 02** — likely PDF 04/05 |
| K (last trick = +10) | **No** | **Not in PDF 02** |
| K (AKA explicit signal) | **No** | **Not in PDF 02** |
| K (SWA permission flow) | **No** | **Not in PDF 02** |

---

## Additional foundational rules from PDF 02 not in Phase-1 K register

These appeared in PDF 02 verbatim and should be cross-checked against the addon's `Rules.lua`:

### A. Faraar (free-deal / open-buy)

**Verbatim (≤15 words):** "ًثانيا: اللعب او التوزيع يكون فرار" — Page 1 line 14.
**English:** "Second: play / dealing is faraar [free-buy]."
**Adjacent (lines 15–18):** "الن المشترى من حق الجميع وال يكون حكر على فريق معين" — "because the purchase is the right of everyone and is not exclusive to a particular team."

### B. Hokm uses banat (melds/projects); Sun does not

**Verbatim (≤15 words):** "ًخامسا: يلعب الحكم ب البناط ًسواء دبل او بدون الدبل" — Page 1 line 47–48.
**English:** "Fifth: Hokm is played with banat [projects], whether Double or without Double."
**Continuation:** "ويلعب الصن بدون ابناط" — "And Sun is played without banat."
**Note:** This is a major rule — Sun contracts have **no melds counting** — that should be reflected in `Rules.lua` scoring.

### C. Meld hierarchy

**Verbatim (≤15 words, one of):** "أكبر سرى هو سرى الكه وأصغرها سرى التسعة" — Page 2 line 96.
**English:** "The biggest sirree is the Ace-sirree and the smallest is the 9-sirree."
**Other tiers (line 97–101):**
- 50: K-50 biggest, 10-50 smallest.
- 100: 5-Aces (5 Aces) is biggest 100; "4 tens of quarter-cards" is smallest 100.
- Quarter-100 = quarter-Aces (no further explanation).

### D. Sirree disclosure rule (privacy of meld between same team)

**Verbatim (≤15 words):** "عند ذكر سرى من الفريقين فاليحق لالعب التالي الفصاح عن سراه" — Page 2 line 109–110.
**English:** "When a sirree is announced [by] both teams, the next player may not disclose his sirree..."
**Continuation (line 111–119):** "...لكي اليكشف قوته" — "so as not to reveal his strength" — except if his is bigger than the prior. **Applies to all melds.**

### E. Ace cannot be Ashkal'd (page-3 commentary)

**Verbatim (≤15 words):** "الكة ماعليها اشكل" — Page 3 line 161.
**English:** "The Ace, no Ashkal upon it."
**Reasoning (line 162–172):** A player who Ashkal's the Ace is "ghashim" (a fool) because there's no project incentive that would make Ashkal'ing the Ace strategic.

### F. No "two strengths" / qootain — except in Sun

**Verbatim (≤15 words):** "مافي شي اسمه قوتين .بالبلوت يستطيع الالعب ان يأخذها قبل زميله وذلك بالصن .فقط"
- Page 3 line 194–196.
**English:** "There is no thing called 'two strengths' in Baloot — a player [can take it before his partner] only in Sun."
**Reading:** In Sun, a player may pre-empt his partner's bid (take it first / ahead of the partner's call). This is unique to Sun.

### G. Kasho is forbidden except for card-count verification

**Verbatim (≤15 words):** "ممنوع مايسمى بالكاشو .باللعب ال في حالة نقص او زيادة"
- Page 3 line 180–181.
**English:** "What is called 'Kasho' is forbidden in play except in case of deficit or excess [of cards]."
**Reading:** Kasho = a verification action; only the buyer may invoke it, only to confirm 8-cards-per-player, and only when there's a count mismatch. Otherwise forbidden.

---

## Summary — answer to mandate

| # | Question | Answer | Confidence |
|---|---|---|---|
| 1 | Target = 152 vs 251 | **251** (verbatim, twice-stated) | High |
| 2 | Bid order + Ashkal seats | **Only seats 3 & 4 issue Ashkal**; first/second-Ashkal nuance is buyer-side | High |
| 3 | Sun-Double rule | **Opp ≥101 verbatim**; caller ≤100 NOT in PDF 02 | High / Low |
| 4 | Sun escalation truncation | **No Triple/Four/Gahwa per page-2**; page-3 says Triple "pointless not forbidden" | High / Medium |
| 5 | Foul penalty | **16 or 26 verbatim**; Sun=26 / Hokm=16 inferred | High / Medium |
| 6 | Meld-during-foul | **PDF gives disjunction: stays-with-owner OR forfeit**; user arbitrated to forfeit | High |
| 7 | Third privilege | **Ace turn-up + Sun contract + seats 1 & 2 only** | High |
| 8 | Round-2 Hokm→Sun flip | Boundary statement only ("not after Hokm definitive"); full mechanic absent | Medium-High / Low |
| 9 | Belote cancelled by 100-meld | **Verbatim confirmed** — no longer single-source | High |
| 10 | Strict majority 81/162 | **NOT in PDF 02** | N/A |
| 11 | Multiplier scope / Belote-immune | Belote = "fixed value 2" → immunity inferred; scope not stated | Medium / Low |
| 12 | Phase-1 K verification | See table — most confirmed; several not in PDF 02 (must source elsewhere) | per-row |

---

## Notes for downstream consumers

1. **No code modified.** This is extraction only.
2. **Number system:** Arabic-Indic digits in PDF: ٠ ١ ٢ ٣ ٤ ٥ ٦ ٧ ٨ ٩ → 0 1 2 3 4 5 6 7 8 9. Note PDF text shows reversed-direction tokens like "٢٥١" = 251 and "٦٢" = 26 and "٦١" = 16 (right-to-left rendering of digit pairs).
3. **PDF text ordering issues:** The extractor produced some rearranged Arabic word/punctuation orderings (e.g. ".غشيم" with leading period). Quotes are preserved as-extracted; reconstruct semantically when in doubt.
4. **PDF 02 scope:** This file is the **base rule book** — it defines counts, seats, contracts, melds. Strategy / signal / SWA / AKA / Carré rules are NOT here and must come from PDFs 03/04/05/06/07 or videos.
5. **All page references** are to the extracted text file (`02_playing_system.txt`), where pages are demarcated by `--- page N ---` headers.
