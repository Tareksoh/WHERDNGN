# A-Src-26 — PDF 05: ماهو البلوت في لعبة البلوت (What is Baloot)

**Source:** `C:\CLAUDE\WHEREDNGN\.swarm_findings\_pdf_extracted\05_what_is_baloot.txt`
**Original PDF:** ماهو البلوت في لعبة البلوت.pdf
**Pages:** 2
**Phase 1 reference:** source_L L19-L24 (scoring basis)
**Extraction date:** 2026-05-05

---

## Document scope

This PDF is a **conceptual/historical exposition** of why the Belote (بلوت) bonus exists and how it balances Hokm (حكم) vs Sun (صن) point totals. It is NOT a comprehensive rules document. It directly addresses the per-suit point breakdown for Hokm trump suit and the conceptual origin/cancellation of the Belote bonus, but does NOT directly address several of the requested questions (last-trick bonus, escalation rungs, bidder threshold, off-trump values, 9-rank-2 ordering, Carré).

**Confidence legend:**
- **HIGH** — verbatim text in PDF directly answers the question
- **MED** — implied/derivable from PDF text but not stated explicitly
- **NOT FOUND** — PDF does not address this question

---

## Q1. Round = 162 / 130 totals (verbatim)

**Verbatim Arabic (≤15 words):**
> "مجموع اللعب ٢٦١"

(Reading right-to-left in Arabic numerals: ٢٦١ = 162)

**English:** "Total of the play [round] = 162"

**Page reference:** Page 1, line 11
**Confidence:** HIGH for 162. NOT FOUND for 130 (PDF does not mention Sun's 130 total — only references 162 raw, and 182 with Belote added, and 262 with the "Hundred Project" added).

**Additional supporting verbatim (Page 1, line 32):**
> "عدد اوراق اللعبة الذي هو ٢٦١"
> "The card-count of the game which is 162"

---

## Q2. Per-suit point breakdowns Hokm + Sun (verbatim)

**Verbatim Arabic (≤15 words, Hokm trump per-suit breakdown):**
> "اكه ١١ + باشا ٤ + بنت ٣ + ولد ٠٢ + العشرة ٠١ + تسعة ٤١"

(Numbers right-to-left: ١١=11, ٤=4, ٣=3, ٠٢=20, ٠١=10, ٤١=14)

**English:** "Ace 11 + King 4 + Queen 3 + Jack 20 + Ten 10 + Nine 14"

**Page reference:** Page 1, lines 15–26
**Confidence:** HIGH for Hokm trump-suit breakdown.

**Hokm suit total (verbatim, Page 1, line 14):**
> "عدد الحكم ٢٦"
> "Hokm count = 62"

**Sun count (verbatim, Page 1, line 28):**
> "أصبح عدد الحكم ٢٦ وعدد الصن ٠٩ ل ٣ جهات المتبقية"
> "Hokm count became 62, and Sun count is 90 for the 3 remaining suits"

**Confidence:** HIGH for Hokm-trump suit (62 raw) and 90 for the remaining 3 suits combined in Sun. NOT FOUND for explicit per-card off-trump values in this PDF.

---

## Q3. Belote/Baloot conceptual origin as +20 K+Q-of-trump (verbatim)

**Verbatim Arabic (≤15 words):**
> "فقرروا بوضع هذه القيمة في ورقتين وهما بنت وشايب الحكم"

**English:** "They decided to place this value in two cards: the Queen and King of trump (Hokm)"

**Page reference:** Page 1, line 88
**Confidence:** HIGH for the K+Q-of-trump location of Belote.

**Note on +20 value:** PDF describes the Belote value as **+2** (not +20) in the per-suit point system. The "+20" figure in the question must be reconciled against this. PDF text (Page 1, line 84):
> "لذلك قاموا بإعطاء البلوت القيمة ٢"
> "So they gave Belote the value 2"

This +2 in raw per-suit math equals +20 in the 10-multiplied tournament scoring system used elsewhere. **Confidence:** HIGH for "+2 value placed on K+Q of trump"; the +20 mapping is conventional but not stated in this PDF.

---

## Q4. Belote multiplier-immunity (verbatim)

**Verbatim Arabic (≤15 words):**
> "واصبح هذا البلوت مفروضا على اللعبة والينفيه السرى او الخمسين او المئة واليدبل"

**English:** "Belote became fixed on the game; it is not negated by Sirah or 50 or 100, and does not double"

**Page reference:** Page 1, lines 93–95
**Confidence:** HIGH. The phrase "واليدبل" ("and does not double") is the verbatim multiplier-immunity statement.

**Continuation (Page 1, lines 95–96):**
> "وانما يعتبر ذو قيمة ثابتة التتغير"
> "Rather, it is considered a fixed value that does not change"

---

## Q5. Belote cancellation by 100-meld holder's side (verbatim)

**Verbatim Arabic (≤15 words):**
> "فيلغى البلوت على صاحب مشروع المئة"

**English:** "Belote is cancelled on the holder of the Hundred Project [100-meld]"

**Page reference:** Page 2, line 120
**Confidence:** HIGH.

**Supporting math (Page 2, lines 116–117):**
> "في مشروع المئة يصبح مجموع اللعب ٢٦٢ على ٢ يصبح ١٣١ ل ١٣١"
> "In the Hundred Project, total play becomes 262/2 = 131 to 131"
> "فلو أضيف البلوت لمجموع اللعب الصبح ٢٨٢ وال يقبل القسمة على ٢"
> "If Belote were added, total play would be 282 which is not divisible by 2"

The cancellation rationale: with 100-meld present, adding Belote breaks the symmetric 131/131 split, so Belote is removed from the 100-meld holder's side.

---

## Q6. Last-trick +10 bonus (verbatim)

**Verbatim Arabic (≤15 words):**
> "والمتبقي هو ٠١ لالرض"

**English:** "And the remaining is 10 for Al-Ardh [last trick]"

**Page reference:** Page 1, line 13 (and line 29: "والمتبقي هي الرض ٠١")
**Confidence:** HIGH for the +10 value associated with الرض (Al-Ardh = "the floor"/last trick).

**Note:** PDF establishes the 10-point allocation to الرض as part of the 162 budget breakdown (62 Hokm trump + 90 off-trump + 10 last-trick = 162). PDF does not explicitly say "to whoever wins the last trick" but Saudi convention treats الرض as the last-trick bonus. **Confidence on the +10 value:** HIGH. **Confidence on the "winner of trick 8" attribution:** MED (implied by convention, not stated verbatim in this PDF).

---

## Q7. Hokm 4-rung escalation (verbatim)

**Status:** **NOT FOUND** in PDF 05.

This PDF discusses the Belote-bonus origin and Hundred-Project cancellation only. The Bel → Bel×2 → Four → Gahwa escalation chain (بل / بل×2 / فور / قهوة) is **not** present in the extracted text.

---

## Q8. Bidder strict-majority threshold (≥81 vs >81, verbatim)

**Status:** **NOT FOUND** in PDF 05.

PDF mentions the 91-91 / 131-131 symmetry points as **balance/equality** points (التساوي بينهما بالعدد ١٩) but does NOT discuss bidder success/failure thresholds. The closest verbatim is (Page 1, line 86):
> "ويصبح التساوي بينهما بالعدد ١٩"
> "Equality between them becomes at the value 91"

This is the *balance point*, not the *bidder-pass threshold*. **Confidence:** NOT FOUND for the strict-majority bid rule.

---

## Q9. Card values: J=20, 9=14, A=11, T=10, K=4, Q=3 (trump Hokm, verbatim)

**Verbatim Arabic (≤15 words):**
> "اكه ١١ + باشا ٤ + بنت ٣ + ولد ٠٢ + العشرة ٠١ + تسعة ٤١"

**English mapping (per-card values for Hokm trump suit):**
- اكه (Ace) = ١١ → 11
- باشا (King) = ٤ → 4
- بنت (Queen) = ٣ → 3
- ولد (Jack) = ٠٢ → 20
- العشرة (Ten) = ٠١ → 10
- تسعة (Nine) = ٤١ → 14

**Page reference:** Page 1, lines 15–26
**Confidence:** HIGH. This is a direct, fully-verbatim per-card breakdown matching the question exactly: J=20, 9=14, A=11, T=10, K=4, Q=3.

**Note:** PDF lists 6 values (A, K, Q, J, T, 9) summing to 11+4+3+20+10+14 = 62, matching the stated "عدد الحكم ٢٦" (Hokm count = 62). The 7, 8 are implicitly 0 (not listed; the sum closes without them).

---

## Q10. Card values: A=11, T=10, K=4, Q=3, J=2, 9/8/7=0 (off-trump Hokm + all Sun, verbatim)

**Status:** **NOT FOUND** in PDF 05 as explicit per-card values.

PDF gives only the off-trump-suit *aggregate*: "عدد الصن ٠٩ ل ٣ جهات المتبقية" ("Sun count = 90 for the 3 remaining suits", Page 1, line 28). Per-suit aggregate is therefore 30 per off-trump suit, but the per-card decomposition (A=11, T=10, K=4, Q=3, J=2, 9=0, 8=0, 7=0) is **not** stated verbatim.

**Derivable check (MED confidence):** 11+10+4+3+2+0+0+0 = 30 per suit ✓ matches the 30/suit × 3 suits = 90 aggregate. The per-card decomposition is the standard Belote off-trump table and is consistent with the PDF arithmetic, but the PDF itself does not enumerate it.

**Confidence:** NOT FOUND for verbatim per-card. MED for arithmetic consistency.

---

## Q11. 9 of trump second-highest Hokm rank (verbatim)

**Status:** **NOT FOUND** verbatim as a *rank* statement in PDF 05.

PDF gives the 9 of trump a *point value* of 14 (second-highest after Jack=20), but does not explicitly state ordering/rank. The point value of 14 (placing it #2 after the Jack's 20) is the verbatim source for the "second-highest" rank by-convention, but this PDF does not say "ترتيب" (order) or "second" explicitly.

**Verbatim Arabic (≤15 words):**
> "تسعة ٤١"
> "Nine [of Hokm] = 14"

**Page reference:** Page 1, line 26
**Confidence:** HIGH for the 14-value. MED for the "rank-2" inference (derivable from value comparison only).

---

## Q12. Carré exclusions (9, 8, 7) (verbatim)

**Status:** **NOT FOUND** in PDF 05.

This PDF does not mention كاريه (Carré / four-of-a-kind) at all. The 9/8/7 exclusion list is governed by other source documents.

---

## Bonus extractions (not requested but present)

### B1. Origin justification of the Belote +2 value (Page 1, lines 41–84)

PDF presents the explicit reasoning for *why* Belote = 2 and not 3:
- If Belote were +3, total play = 192/2 = 96/96, but the 9-divisible-by-Hokm-system gives bidder 9-from-96 instead of 10-from-96, breaking balance.
- If Belote = +2, total play = 182/2 = 91/91, perfectly balanced.

**Verbatim (Page 1, line 60):**
> "القيمة ٨١ يكون مجموع اللعب ٢٨١ نقسم على ٢ ١٩ ل ١٩"
> "Value 18: total play = 182, divided by 2 = 91 to 91"

**Confidence:** HIGH for this specific math.

### B2. Conceptual summary (Page 2, lines 123–125)

**Verbatim Arabic (≤15 words):**
> "البلوت ليس اساسي في اللعبة وضع للموازنة والغي للموازنة"

**English:** "Belote is not essential in the game; it was added for balance and is cancelled for balance"

**Page reference:** Page 2, lines 123–125
**Confidence:** HIGH. This is the PDF's own one-sentence thesis statement.

---

## Summary table

| # | Question | PDF coverage | Confidence |
|---|---|---|---|
| 1 | Round = 162 / 130 | 162 verbatim; 130 not present | HIGH (162) / NOT FOUND (130) |
| 2 | Per-suit Hokm + Sun breakdown | Hokm trump per-card; Sun aggregate only | HIGH (Hokm) / MED (Sun aggregate) |
| 3 | Belote = +2 on K+Q of trump | Verbatim "بنت وشايب الحكم" + value 2 | HIGH |
| 4 | Belote multiplier-immune | "واليدبل" verbatim | HIGH |
| 5 | Belote cancelled by 100-meld | "فيلغى البلوت على صاحب مشروع المئة" verbatim | HIGH |
| 6 | Last-trick +10 (الرض) | "٠١ لالرض" verbatim | HIGH (value) / MED (attribution) |
| 7 | 4-rung escalation | Not in this PDF | NOT FOUND |
| 8 | Bidder strict-majority ≥81 vs >81 | Not in this PDF | NOT FOUND |
| 9 | Trump card values (J=20, 9=14, A=11, T=10, K=4, Q=3) | Verbatim per-card list | HIGH |
| 10 | Off-trump card values | Aggregate (90/suit × 3 = 90) only | NOT FOUND (verbatim) / MED (derivable) |
| 11 | 9 of trump = rank 2 | 9-value of 14 verbatim; rank inferred | HIGH (value) / MED (rank) |
| 12 | Carré exclusions | Not in this PDF | NOT FOUND |

**Net coverage:** 6 of 12 questions answered verbatim from this PDF (Q1 partial, Q2 partial, Q3, Q4, Q5, Q6 partial, Q9, Q11 partial). 4 of 12 are NOT FOUND in this source (Q7, Q8, Q10 verbatim, Q12). Q10/Q11 are derivable with MED confidence.

This PDF is the **definitive source for the Hokm trump-suit per-card point breakdown** (Q2/Q9) and **the Belote conceptual origin/cancellation logic** (Q3/Q4/Q5). Other questions require cross-reference to PDFs 01-04 / 06+.
