# A-Src-28: PDF 07 — Doubling System (نظام الدبل في لعبة البلوت)

**Source PDF:** `نظام الدبل في لعبة البلوت.pdf`
**Extracted text:** `C:\CLAUDE\WHEREDNGN\.swarm_findings\_pdf_extracted\07_doubling_system.txt`
**Pages:** 1
**Re-extracted:** 2026-05-05
**Audit context:** v0.10.2 Track A — authoritative source for the escalation chain (Bel → Triple → Four → Gahwa) per Phase 1 source_L L25–L36.

---

## Numeral key (Arabic-Indic → Western)

The PDF uses Arabic-Indic digits in right-to-left contexts. Resolved values used throughout this document:

| Arabic-Indic (as printed) | Reads RTL as | Decimal |
|---|---|---|
| `٢٥١` | 152 | **152** (game target) |
| `٦١` | 16 | **16** (Hokm hand total) |
| `٠٠١` | 100 | **100** (Sun score gate) |
| `٢٣` | 32 | **32** (16 × 2) |
| `٨٤` | 48 | **48** (16 × 3) |
| `٤٦` | 64 | **64** (16 × 4) |
| `٢٥` | 25 | **25** (Sun half — wins by majority over 25) |
| `٦٢` | 26 | **26** (Sun hand total ÷ 2 reference; also penalty 26/16) |

(The PDF's text-extraction stage reverses bidirectional digit clusters; visible glyph order is opposite of decimal value. All numerical claims below cite the resolved value alongside the original glyph.)

---

## Q1. Hokm chain Bel→Triple→Four→Gahwa with multipliers ×2/×3/×4

### Verbatim Arabic (≤15 words)

> "نظام الدبل بالحكم ( دبل - ثري - فور - قهوة )"

**Source:** PDF 07, page 1, lines 14–15.

### Multiplier definitions (verbatim, segmented)

**Bel (Doubling) ×2** — page 1, lines 17–22:

> "الدبل معناه : بان مجموع عدد الحكم مضروب باثنين"

**English:** "Bel means: the Hokm's total count multiplied by two."

Arithmetic: `٦١ * ٢ = ٢٣` → **16 × 2 = 32**.

> "وهنا تدبل جميع المشاريع ماعدا البلوت اليدبل"

**English:** "Here all projects (mashārīʿ) double, except Belote which does not double."

**Triple (Thrī) ×3** — page 1, lines 25–33:

> "الثري معناه : بان مجموع عدد الحكم مضروب بثالثة"

**English:** "Thrī means: the Hokm's total count multiplied by three."

Arithmetic: `٦١ * ٣ = ٨٤` → **16 × 3 = 48**.

> "وتدبل جميع المشاريع ماعدا البلوت يعني ٦١ + المشروع * ٣"

**English:** "All projects double except Belote, meaning 16 + project × 3."

**Four (Fōr) ×4** — page 1, lines 35–43:

> "الفور معناه : بأن مجموع عدد الحكم مضروب بأربعة"

**English:** "Fōr means: the Hokm's total count multiplied by four."

Arithmetic: `٦١ * ٤ = ٤٦` → **16 × 4 = 64**.

> "وتدبل جميع المشاريع ماعدا البلوت يعني ٦١ + المشروع * ٤"

**English:** "All projects double except Belote, meaning 16 + project × 4."

### Confirmation

**CONFIRMED verbatim.** The chain (دبل → ثري → فور → قهوة) is named explicitly with all three multipliers (×2, ×3, ×4). PDF 02 cross-confirms the chain by name (page 2, lines 77–78, 83–84): "في حالة الدبل او الثري او الفور او القهوة ... فيكون الدبل أو الثري أو الفور أو القهوة مسموح بهما للفريقين من بداية اللعبة" — "in the case of Bel/Thrī/Fōr/Gahwa ... Bel/Thrī/Fōr/Gahwa are permitted to both teams from the start of the game."

### Confidence

**VERY HIGH.** The PDF's section header explicitly names the chain in chain-order with parentheses, then defines each rung's multiplier with arithmetic. PDF 02 names the same four rungs in the same order.

---

## Q2. Gahwa = match-win (target = 152)

### Verbatim Arabic (≤15 words)

> "القهوة معناها : تؤخذ اللعبة كاملة يعني ٢٥١"

**Source:** PDF 07, page 1, line 44.

### English translation

> "Gahwa means: the entire game is taken, that is 152."

### Resolution

`٢٥١` reads RTL as **152**. This is the complete game target — calling Gahwa wins the entire match outright at the contract's resolution (not merely a hand-multiplier).

### Confirmation

**CONFIRMED verbatim.** PDF 02 page 1 line 10–11 cross-confirms the 152 target: "اللعب يكون ٢٥١ أي يبدأ من الصفر وينتهي عند النقطة ٢٥١" — "play is to 152, starting from zero and ending at point 152."

### Confidence

**VERY HIGH.** Direct numeric statement, cross-confirmed by PDF 02's game-target rule.

---

## Q3. Sun's restricted single-rung Bel (chain truncated to Bel-only)

### Verbatim Arabic (≤15 words)

> "نظام الدبل بالصن ( دبل فقط)"

**Source:** PDF 07, page 1, lines 57–59.

### Reasoning passage (verbatim, segmented)

> "الن الدبل يكون بعد المئة وال يحتاج المشتري أن يطلب الثري ألنه يكتفي بالعدد ٢٥ لكي يفوز على خصمه"

**Source:** PDF 07, page 1, lines 61–62.

**English:** "Because Bel happens after 100 and the buyer doesn't need to request Thrī, since 25 [points] suffice to win against his opponent."

### Confirmation

**CONFIRMED verbatim.** Sun has **Bel only** — the Triple/Four/Gahwa rungs are **not available** under Sun. PDF 02 page 2 lines 77–80 cross-confirms: "في حالة الدبل او الثري او الفور او القهوة ففي الصن اليوجد الثري والفور والقهوة وانما يلعب دبال فقط" — "in the case of Bel/Thrī/Fōr/Gahwa, in Sun, Thrī/Fōr/Gahwa do not exist; only Bel is played."

### Confidence

**VERY HIGH.** Both PDFs explicitly enumerate the unavailable rungs ("اليوجد الثري والفور والقهوة") and the available one ("دبل فقط").

---

## Q4. Score-100 gate (Sun-Bel)

### Verbatim Arabic (≤15 words)

> "بالصن : اليفتح الدبل ال بعد العدد ٠٠١"

**Source:** PDF 07, page 1, line 12.

### English translation

> "In Sun: Bel is not opened until after the count 100."

### Resolution

`٠٠١` reads RTL as **100**. Bel under Sun requires the score gate of 100 to have been crossed.

### Confirmation

**CONFIRMED verbatim.** PDF 02 page 2 line 81 cross-confirms with the exact threshold: "واليحق لالعب ان يدبل خصمة ال بعد ان يتجاوز المئة اي ١٠١" — "the player is not entitled to Bel his opponent unless [the opponent] has surpassed 100, i.e. 101." Together the two PDFs establish the rule as: **opposite team must be ≥101** (PDF 02's "تجاوز المئة" — "surpassed 100" = strict majority over 100). Video #11 (A-Src-04) refines this further to a **score-split predicate**: caller-team ≤100 AND opposite-team ≥101.

### Confidence

**VERY HIGH** on the score gate. **Cross-source note:** PDF 07 phrases it loosely ("بعد العدد ٠٠١"); PDF 02 sharpens it ("تجاوز المئة اي ١٠١"); video #11 expresses both halves of the split. No contradiction — each source elaborates within the same rule frame.

---

## Q5. Trailing-side-only rule for Sun-Bel

### Verbatim Arabic (≤15 words)

> "ويكون الدبل للمتأخر فقط وهو الذي لم يتجاوز عدده ٠٠١"

**Source:** PDF 07, page 1, line 68.

### English translation

> "Bel is for the trailing [team] only — the one whose count has not surpassed 100."

### Confirmation

**CONFIRMED verbatim.** "للمتأخر فقط" — "for the trailing [team] only" — is the explicit, role-irrelevant predicate. The qualifier is **purely score-based** (whose count has not exceeded 100), not role-based (bidder vs defender).

### Cross-confirm with video #11 (A-Src-04)

The PDF's "للمتأخر فقط" matches video #11's framing precisely. From A-Src-04 Q2 verbatim: "الفريق اللي اقل من 100 لوحه حقيقيه يدبل لكن الفريق اللي فوق الميه ما يدبل" — "the team below 100 has the genuine right to Bel, but the team above 100 does not Bel." Both sources frame it as **score-split, role-irrelevant**.

### Confidence

**VERY HIGH.** Two independent sources (PDF 07 + video #11 A-Src-04) state the trailing-side-only rule in pure-score language with no bidder/defender qualifier. This is the canonical statement of the rule.

### D-RT-22 implication

The PDF supports `R.CanBel`'s current role-irrelevant predicate. The PDF does **not** support a defender-seat gate at the network layer (`Net._OnDouble`). This corroborates A-Src-04's verdict.

---

## Q6. Open/closed quadrupling election

### Verbatim Arabic (≤15 words)

> "ويفتح التربيع حسب طلب الالعب او يقفل"

**Source:** PDF 07, page 1, lines 46–47.

### Full passage (verbatim, segmented)

> "أي من يطلب الدبل يختار مفتوح او مغلق ومن يطلب الثري او الفور يختار ًايضا"

**Source:** PDF 07, page 1, line 47.

**English:** "That is, whoever requests Bel chooses [it as] open or closed; whoever requests Thrī or Fōr chooses [it] also."

### Confirmation

**CONFIRMED verbatim.** Each escalation rung's caller (Bel, Thrī, Fōr) elects open vs. closed independently at the moment of the call. The election is the caller's prerogative.

### Confidence

**VERY HIGH.** Direct, unambiguous statement. The mechanic is well-defined for Bel/Thrī/Fōr.

---

## Q7. Forced-open at Gahwa

### Verbatim Arabic (≤15 words)

> "ماعدا القهوة فيكون فيها التربيع ًمفتوحا"

**Source:** PDF 07, page 1, lines 50–51.

### English translation

> "Except for Gahwa — in Gahwa the squaring is [forced to be] open."

### Confirmation

**CONFIRMED verbatim.** Gahwa is the **only** rung where the open/closed election is removed — it is **forced open**. This is a hard rule, not a session variant.

### Confidence

**VERY HIGH.** The "ماعدا" ("except") construction unambiguously carves Gahwa out of the elective-open rule from Q6.

---

## Q8. Bnaat (Belote +20) always-on under Hokm

### Verbatim Arabic (≤15 words)

> "الحكم يلعب ب البناط ًسواء كان اللعب دبل او بدون دبل"

**Source:** PDF 07, page 1, lines 54–55.

### English translation

> "Hokm is played with the Bnaat — whether the play is Bel [doubled] or without Bel."

### Confirmation

**CONFIRMED verbatim.** Bnaat (the K+Q-of-trump +20 announcement) is **always live under Hokm**, regardless of whether the round is undoubled or under any escalation rung. PDF 02 page 1 lines 47–49 cross-confirms: "يلعب الحكم ب البناط ًسواء دبل او بدون الدبل ويلعب الصن بدون ابناط" — "Hokm is played with Bnaat whether doubled or not, and Sun is played without Bnaat."

PDF 07 also adds at page 1, line 70: "والصن اليوجد به أبناط" — "and Sun has no Bnaat" — symmetric with PDF 02.

### Bnaat ≠ Bnaat-doubling

PDF 07 page 1, lines 22–23 explicitly note Belote does **not** double under Bel: "تدبل جميع المشاريع ماعدا البلوت اليدبل وذلك النه عدد مفروض وتكميلي وقيمتة ثابته وال يجوز دبلها" — "all projects double except Belote, which does not double, because it is an imposed and complementary number with a fixed value, and it cannot be doubled." Same statement repeats for Thrī (line 30) and Fōr (line 40). This is consistent with `K.MULT_BEL` being multiplier-immune in Constants.lua.

### Confidence

**VERY HIGH on always-on under Hokm.** **VERY HIGH on multiplier-immunity** — stated three separate times across the chain.

---

## Q9. Bel call by bidder team allowed?

### Verdict

**NOT EXPLICITLY ADDRESSED IN PDF 07** — but the PDF's role-irrelevant phrasing (Q5) **admits** the bidder-trailing case by direct application.

### Verbatim phrasing that controls

From Q5: "ويكون الدبل للمتأخر فقط وهو الذي لم يتجاوز عدده ٠٠١" — "Bel is for the trailing [team] only — the one whose count has not surpassed 100."

The PDF predicate is **trailing-side**, not **defender-side**. There is no "خصم" (opponent/defender) qualifier; the rule is pure score-split. By direct application, **if the bidder team is the trailing team (≤100) and the defender team has surpassed 100 (≥101), the bidder team can Bel its own contract.**

### Cross-confirm with video #11 (A-Src-04)

A-Src-04 Q3 Q4 explicitly addresses this: video #11's speaker uses second-person "you" continuous with an earlier "you bought Sun" example, never adds a buyer-exclusion clause, and never says the rule is defender-only. A-Src-04's verdict: "by direct application of the verbatim rule. The speaker uses second-person 'you' pronouns continuous with an earlier 'you bought Sun' example, and never adds a buyer-exclusion clause."

### What PDF 07 does NOT say

- PDF 07 does **not** say only the defender team can Bel under Sun.
- PDF 07 does **not** say the buyer cannot Bel his own contract.
- PDF 07 does **not** introduce "خصم" / "مشتري" / role qualifiers in the Bel-rule statement.

### Hokm context (PDF 02 cross-reference)

PDF 02 page 2 lines 83–84: "واما في الحكم فيكون الدبل أو الثري أو الفور أو القهوة مسموح بهما للفريقين من بداية اللعبة" — "in Hokm, Bel/Thrī/Fōr/Gahwa are permitted to **both teams** from the start of the game." So under Hokm, **both teams** (bidder and defender alike) may escalate from round-start. The bidder team may absolutely call its own Bel under Hokm.

### Confidence

**HIGH on the inference for Sun.** PDF 07 omits a role qualifier from a rule it states multiple ways; the natural reading is the role-irrelevant one, which video #11 confirms. **VERY HIGH on Hokm** — PDF 02's "للفريقين" ("for both teams") is explicit.

### D-RT-22 implication

PDF 07 + PDF 02 + video #11 (A-Src-04) all converge on the same answer: **the bidder team can Bel** when the score-split predicate is satisfied. The defender-seat gate in `Net._OnDouble` has no basis in any of the three authoritative sources.

---

## Q10. Cards-revealed lockout

### Verdict

**NOT ADDRESSED IN PDF 07.** The PDF's mandate is the **escalation-chain mechanics** (rungs, multipliers, score gates, open/closed elections, forced-open at Gahwa, Bnaat preservation). The cards-revealed lockout (kashf al-waraq) is **not mentioned**.

### Cross-source coverage

The cards-revealed lockout is covered authoritatively by **video #11 (A-Src-04 Q6)**, where the speaker states: "اذا كشفت الورق خلاص وما قلت دبل ممنوع تدبل" — "if you've revealed cards and didn't say Bel, you're forbidden to Bel" — and notes a per-session variant where ANY player's reveal locks the table (strict-house) vs. only your own reveal locks you (lenient-house).

### No contradiction

PDF 07's silence on the cards-revealed lockout is **consistent** with video #11 — the lockout is a timing/session rule, not part of the escalation-chain mechanics that PDF 07 enumerates. **No contradiction** arises.

### Confidence

**HIGH.** PDF 07's silence is non-contradictory; the rule is sourced from video #11.

---

## Q11. "Maqfūl" (مقفول) under even-multiplier Hokm

### Verdict

**NOT ADDRESSED IN PDF 07.** The PDF defines what each rung **multiplies** but does not specify the **lead-restriction** that even-multiplier Hokm imposes.

### Cross-source coverage

Maqfūl is covered authoritatively by **video #11 (A-Src-04 Q7)**:
- Even multipliers (Bel ×2, Four ×4) under Hokm = **maqfūl** (closed) — "ما يلعب اول ورقه في الارض حكم" (no opening with trump).
- Odd multiplier (Three ×3) and Gahwa = **مفتوح / open** — natural play.
- Some sessions also play Bel/Four as open — partially session-dependent.

### No contradiction with PDF 07

PDF 07's open/closed election (Q6) is about the **quadrupling election** ("التربيع") — a separate concept from maqfūl-vs-open lead-restriction. The two open/closed concepts are distinct:
- **PDF 07 "open/closed" (تربيع)** — whether the rung's multiplier can be quadrupled by the opposing team's counter-call.
- **Video #11 "maqfūl/open"** — lead-restriction (no opening with trump under even multiplier).

PDF 07 does not contradict video #11 on either dimension. PDF 07 simply does not address the lead-restriction layer.

### Cross-confirm with PDF 07's odd-multiplier exemption

PDF 07's chain `Bel(×2) → Thrī(×3) → Four(×4) → Gahwa(target=152)` aligns with video #11's parity rule: ×2 and ×4 are even (maqfūl), ×3 is odd (open), and Gahwa is a match-win not a multiplier. The numeric structure in PDF 07 is consistent with the parity-based maqfūl rule from video #11.

### Confidence

**HIGH on the absence in PDF 07** — the PDF is silent. **HIGH on no-contradiction** — the two "open/closed" concepts are distinct dimensions of the same escalation system.

---

## Q12. Cross-confirm with video #11 + PDF 02 — contradictions?

### Convergence summary

| Topic | PDF 07 | PDF 02 | Video #11 (A-Src-04) | Verdict |
|---|---|---|---|---|
| Hokm chain Bel→Thrī→Fōr→Gahwa | Named verbatim with ×2/×3/×4 (Q1) | Named verbatim, "للفريقين" allowed from round-1 | Names rungs in beginner walkthrough | **CONVERGENT** |
| Sun chain restricted to Bel-only | Verbatim "دبل فقط" (Q3) | Verbatim "اليوجد الثري والفور والقهوة وانما يلعب دبال فقط" | Implicit; speaker only discusses Bel under Sun | **CONVERGENT** |
| Score-100 gate (Sun) | "بعد العدد ٠٠١" (Q4) | "تجاوز المئة اي ١٠١" — sharper (≥101) | Score-split: caller ≤100 AND opposite ≥101 | **CONVERGENT, refined cumulatively** |
| Trailing-side-only / role-irrelevance | "للمتأخر فقط" (Q5) | (silent on role) | "الفريق اللي اقل من 100 ... الفريق اللي فوق الميه" — pure score | **CONVERGENT** |
| Bidder team can Bel its own Sun? | Admitted by direct application (Q9) | (silent specifically; Hokm allows for "للفريقين") | YES — second-person "you" framing continuous with buyer | **CONVERGENT** |
| Open/closed quadrupling election | Caller elects (Q6); Gahwa forced-open (Q7) | (silent) | (silent on quadrupling) | **PDF 07 unique authoritative source** |
| Bnaat under Hokm | Always-on (Q8); Belote multiplier-immune | "الحكم ب البناط سواء دبل او بدون / الصن بدون ابناط" | (silent) | **CONVERGENT** between PDFs |
| Cards-revealed lockout | (silent) | (silent) | "اذا كشفت الورق ... ممنوع تدبل" + session variant | **Video #11 unique authoritative source** |
| Maqfūl under even-multiplier Hokm | (silent — only addresses تربيع election) | (silent) | "ما يلعب اول ورقه في الارض حكم" + parity rule | **Video #11 unique authoritative source** |
| Game target = 152 | "يعني ٢٥١" at Gahwa (Q2) | "اللعب يكون ٢٥١ ... ينتهي عند النقطة ٢٥١" (page 1) | (game target not directly quoted in #11) | **CONVERGENT between PDFs** |

### Contradictions found

**NONE.** All three sources are mutually consistent. Each fills different parts of the rule space:
- **PDF 07** is authoritative on **escalation-chain mechanics** (rungs, multipliers, open/closed quadrupling, forced-open at Gahwa, Sun's Bel-only restriction).
- **PDF 02** is authoritative on **bilateral availability under Hokm** ("للفريقين") and **game target** confirmation.
- **Video #11** is authoritative on **cards-revealed lockout, maqfūl, and the role-irrelevance fine point** (uses pure-score language).

### Cross-source overlap on Sun-Bel score gate

The three sources state the same rule with progressively sharper formulations:
- **PDF 07:** "اليفتح الدبل ال بعد العدد ٠٠١" — "Bel does not open until after 100."
- **PDF 02:** "واليحق لالعب ان يدبل خصمة ال بعد ان يتجاوز المئة اي ١٠١" — "the player has no right to Bel his opponent until [opponent] surpasses 100, i.e. 101."
- **Video #11:** "في الصن لازم يكون فريق 100 نقطه او اعلى والفريق الثاني يكون اقل من 100" — both halves of the score-split predicate stated.

**Synthesis:** the operational predicate is `caller.cum ≤ 100 AND opposite.cum ≥ 101`, role-irrelevant. PDF 07 corroborates the trailing-side framing; PDF 02 corroborates the ≥101 threshold sharpening; video #11 states both halves. No source contradicts any other.

### Confidence

**VERY HIGH on convergence.** Three independent authoritative sources tested across 12 questions yield zero contradictions. Each source's silences are non-contradictory (PDF 07 doesn't address timing-lockout/maqfūl; video #11 doesn't address quadrupling; PDF 02 doesn't address quadrupling or maqfūl).

---

## Numerical thresholds and conditions extracted (verbatim)

| Threshold | Verbatim Arabic | Decimal | Where it applies |
|---|---|---|---|
| Hokm hand total | `٦١` | 16 | Multiplier base for ×2/×3/×4 (Q1) |
| Bel multiplier (Hokm) | `٦١ * ٢ = ٢٣` | 16 × 2 = 32 | Q1 |
| Thrī multiplier (Hokm) | `٦١ * ٣ = ٨٤` | 16 × 3 = 48 | Q1 |
| Fōr multiplier (Hokm) | `٦١ * ٤ = ٤٦` | 16 × 4 = 64 | Q1 |
| Gahwa target | `٢٥١` | **152 (full match)** | Q2 |
| Sun-Bel score gate (caller side) | `٠٠١` (≤100 implied by "للمتأخر") | ≤100 | Q4, Q5 |
| Sun-Bel score gate (opposite side, PDF 02 sharpening) | `١٠١` | ≥101 | Q4 (cross-source) |
| Sun half-target | `٢٥` | 25 (Sun majority) | Q3 (referenced in reasoning) |
| Belote bonus | `٢` (fixed) | 2 (multiplier-immune) | Q8 (PDF 07) + PDF 02 page 2 line 128 |

### Conditions extracted (verbatim)

- **Hokm round-1 availability:** "مفتوح من اول لعبه" — "open from round 1" (PDF 07 page 1 lines 9–10, cross-confirmed PDF 02 "للفريقين من بداية اللعبة").
- **Sun round-1 lockout:** "اليفتح الدبل ال بعد العدد ٠٠١" — "Bel does not open until after 100" (PDF 07 line 12).
- **Sun chain restriction:** "دبل فقط" — "Bel only" (PDF 07 line 59).
- **Trailing-only condition:** "للمتأخر فقط وهو الذي لم يتجاوز عدده ٠٠١" — "for the trailing [team] only — whose count has not surpassed 100" (PDF 07 line 68).
- **Sun has no Bnaat:** "الصن اليوجد به أبناط" (PDF 07 line 70).
- **Hokm always has Bnaat:** "الحكم يلعب ب البناط ًسواء كان اللعب دبل او بدون دبل" (PDF 07 lines 54–55).
- **Belote multiplier-immune:** "ماعدا البلوت اليدبل ... وقيمتة ثابته وال يجوز دبلها" (PDF 07 lines 22–23, restated for Thrī line 30, Fōr line 40).
- **Forced-open at Gahwa:** "ماعدا القهوة فيكون فيها التربيع ًمفتوحا" (PDF 07 lines 50–51).
- **Open/closed election by caller:** "من يطلب الدبل يختار مفتوح او مغلق ومن يطلب الثري او الفور يختار ًايضا" (PDF 07 line 47).

---

## Provenance

- **Source PDF text:** `C:\CLAUDE\WHEREDNGN\.swarm_findings\_pdf_extracted\07_doubling_system.txt` (1 page, 73 lines)
- **Cross-reference 1:** `C:\CLAUDE\WHEREDNGN\.swarm_findings\_pdf_extracted\02_playing_system.txt` (3 pages)
- **Cross-reference 2:** `C:\CLAUDE\WHEREDNGN\.swarm_findings\review_v0.10.2\_track_A_sources\A-Src-04_v11_bel100.md`
- **Re-extract date:** 2026-05-05
- **Audit context:** v0.10.2 Track A — re-extracting authoritative escalation-chain rules from the canonical PDF source per Phase 1 source_L L25–L36.
- **No code modified per audit instructions.**

---

## Aggregate confidence

**OVERALL: VERY HIGH.**

PDF 07 is the canonical primary source for the Saudi Baloot escalation chain. The PDF's structure (named-rung header → per-rung definition with arithmetic → Sun-restriction section) is purpose-built for exactly the audit questions asked. Every numerical threshold, every multiplier, every condition is stated explicitly in Arabic, with PDF 02 + video #11 (A-Src-04) providing zero-contradiction triangulation. The three silences in PDF 07 (cards-revealed lockout, maqfūl, exact ≥101 sharpening) are all filled by the cross-references without conflict.
