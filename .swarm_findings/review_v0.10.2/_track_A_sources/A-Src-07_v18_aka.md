# A-Src-07 — Video #18 AKA Re-extraction

**Source:** `docs/strategy/_transcripts/V_xTjwSSKyQ_18_when_to_aka.ar-orig.srt`
**Title:** "When to AKA" (متى تقول اكا)
**Re-extraction context:** v0.10.2 M4 wired AKA-receiver legality relief (Part 2 of J-066/J-067). Part 1 (AKA-on-T trick lock) is **NOT** implemented in `R.CurrentTrickWinner` per X2 B5 + B-Net-01 F-AP-21. Comment at `Rules.lua:108-110` claims "10-substitutes-for-Ace semantic collapses to same rule" — this re-extraction tests that claim against #18.

---

## HEADLINE FINDING — AKA-on-T trick-locking is **NOT in #18**

**Question 2 (and 9): does the speaker explicitly say T (10) substitutes for A (Ace) and locks the trick?**

**Answer: NO.** Confidence: **HIGH**.

The speaker describes the **opposite** mechanism. T (العشره) is a *signaled* card that becomes *informationally equivalent* to "biggest remaining" — not a card that *legally substitutes* for A in any rules engine sense. AKA-on-T does NOT change who wins the trick under suit-following or trump-cut rules. The speaker is explicit that:

1. AKA-on-T announces "I have the biggest card available" (≈ AKA-on-A semantics for *signaling*)
2. The signal's *purpose* is to release the partner from the obligation to overtrump (يدق بالحكم) — i.e., it relaxes a **partner-side legality constraint**, not the trick-winner determination
3. An opponent **can still win the trick** by trumping over the T — see explicit example at 03:36–03:42

**Verbatim, lines 175–177 (~03:36–03:42):**
> "لو لعبت عشره الشريع وقلت اكا وهذا لعب البنت خويك لو لعب السبعه قطع بالحكم تمام راح ياخذ بالاكه في الاخير"
>
> EN: "If you played 10♥ and said AKA, and this [opp] played J, your partner — if he plays 7-trump cuts with trump, fine — will take with the Ace at the end."

That is, **opp can still cut over the AKA'd T with a trump**, and partner takes via separate Ace. The T does **not** lock the trick. AKA-on-T behaves as a **signal**, not a **substitution rule**.

**Doc misframing confirmed.** The comment at `Rules.lua:108-110` ("10-substitutes-for-Ace semantic collapses to same rule") is **misleading**. Video #18 supports a *signaling* equivalence (T-with-AKA ≈ A-without-AKA *for partner's overtrump-release*), not a *trick-resolution* equivalence. X2 B5 + B-Net-01 F-AP-21 audits are correct.

---

## Per-question findings

### Q1 — 3×3 decision matrix (G18-09)

The speaker structures the matrix in two halves of 3 rows each:

**Self-axis (3 rows) — at 04:23–04:50, lines 215–235:**
- (a) متاكد this is the biggest card
- (b) شاك (uncertain) whether biggest
- (c) متاكد this is NOT the biggest

> Lines 217–223 (~04:31–04:38): "اما تكون متاكد انه فعلا هذه العشره او هذه الورقه اكبر ورقه موجوده"
>
> EN: "Either you are certain that this 10 or this card is actually the biggest card present."

> Lines 223–227 (~04:38–04:43): "ثاني قسم انت شاك في العشره هذه انها اكبر ورقه"
>
> EN: "Second category: you are doubtful about this 10 being the biggest card."

> Lines 231–234 (~04:48–04:52): "ثالث شيء تكون متاكد انه هذه العشره مش اكبر ورقه موجوده"
>
> EN: "Third thing: you are certain that this 10 is not the biggest card present."

**Partner-axis (3 cols) — at 04:52–05:08, lines 237–251:**
- (i) متاكد partner has trump
- (ii) شاك about partner's trump
- (iii) متاكد partner has no trump

> Lines 237–241 (~04:55–05:00): "هل انت متاكد انه خويك معه اوراق حكم او ورقه حكم"
>
> EN: "Are you certain your partner has trump cards or a trump card?"

> Lines 241–245 (~05:00–05:04): "ثاني شيء هل انت شاك في خويك انه عنده اوراق حكم"
>
> EN: "Second: are you doubtful whether partner has trump cards?"

> Lines 245–251 (~05:04–05:08): "ثالث شيء انت متاكد انه خويك ما عنده اوراق حكم"
>
> EN: "Third: you are certain partner has no trump cards."

**The 9 cells (verbatim, with timestamps):**

| Self \ Partner | (i) Has trump | (ii) Uncertain trump | (iii) No trump |
|---|---|---|---|
| **(a) Certain biggest** | "لازم تقول اكه" — MUST say AKA (05:13–05:19) | "لازم تقول اكا" — MUST say AKA (05:33–05:36) | "لا تقول اك ابدا" — NEVER say AKA (05:39–05:43) |
| **(b) Uncertain** | "الافضل ما تقول اكا" — best NOT to say (05:55–06:01) | "الافضل انك ما تقول اكه" — best NOT to say (06:42–06:49) | "الافضل انك ما تقول اكه" — best NOT to say (06:42–06:49) |
| **(c) Certain NOT biggest** | "ما تقولك ليش تقول اك" — DO NOT say (06:49–06:55) | DO NOT say (same line) | DO NOT say (same line) |

**Key verbatim quotes (each ≤15 words):**
- Cell (a,i): "في هذه الحاله لازم تقول اكه" — "in this case you must say AKA" (05:15–05:19)
- Cell (a,ii): "لازم تقول اكا ما انت خسران" — "must say AKA, you lose nothing" (05:33–05:38)
- Cell (a,iii): "نهائيا لا تقول اك ابدا" — "absolutely never say AKA" (05:43–05:45)
- Cell (b,i): "الافضل ما تقول اكا لانه لو غلطت" — "best not say AKA in case wrong" (05:57–06:03)
- Cell (b,ii)+(b,iii): "في كلت الحالتين الافضل انك ما تقول اكه" — "in both cases, best not to say AKA" (06:44–06:49)
- Cell (c,*): "ما لها داعي" — "no reason [to say it]" (06:55)

**Confidence: HIGH** for matrix structure. Confidence: HIGH for verbatim cell content.

---

### Q2 — AKA-on-T trick-locking

**See HEADLINE FINDING above. NOT explicitly described.** Confidence: **HIGH** (negative).

The closest the speaker comes is lines 203–207 (~04:08–04:15):

> "لانها اكا في النهايه اكبر ورقه موجوده فالاكه هي تاكك نفسها بنفسها كانك قلت عليها اكه"
>
> EN: "Because in the end it [the played card] is the biggest card present, so the AKA tags itself, as if you'd said AKA on it."

This is about **playing the actual Ace** auto-counting as AKA for the partner-overtrump-release purpose. It is **NOT** about T substituting for A. The speaker says the *Ace* is "self-tagging"; he never says T can be played-and-treated-as-Ace for trick resolution.

---

### Q3 — Implicit AKA via bare-A lead (G18-08)

**CONFIRMED.** Verbatim, lines 195–211 (~04:02–04:20):

> Lines 197–203 (~04:04–04:10): "لعبت اكت الشريه هذا لعب العشره خويك هنا هل مجبر يدق بحكم لا مش مجبر يدق بحكم"
>
> EN: "You played A♥, this [opp] played 10, your partner here — must he overtrump? No, he is not forced to overtrump."

> Lines 205–211 (~04:13–04:20): "اذا قلت اك لاي ورقه خويك مش مجبر يدق بالحكم"
>
> EN: "If you say AKA on any card, your partner is not forced to overtrump."

The speaker frames bare-A lead as "self-tagging AKA" — the partner-overtrump-release effect applies *automatically* without verbal AKA on the Ace.

**Confidence: HIGH.**

---

### Q4 — Risk-tolerance dispersal (G18-10)

**CONFIRMED — explicit early-vs-late dispersal.**

> Lines 311–317 (~06:24–06:31): "اذا كان بدايه الجيم … ممكن تجازف تقول هيك حتى لو طلع كلام غلط"
>
> EN: "If it is the start of the round … you may gamble and say AKA even if it turns out wrong."

> Lines 319–325 (~06:31–06:40): "اذا اللعب حساس ولا الخصم مره فوق صعبه فهنا غلطتك حتاثر عليكم اكثر"
>
> EN: "If the game is tense or opponents are way ahead/difficult, here your mistake will hurt you more."

The doubled/sensitive context is explicitly conservative; opening-game permissive. **No explicit "doubled = even more conservative" phrase**, but حساس (sensitive/tense) is the closest descriptor and the speaker pairs it with "mistakes hurt more."

**Confidence: HIGH** for early permissive. **MEDIUM** for "doubled-specifically conservative" (speaker says حساس / مشدود, not specifically "doubled").

---

### Q5 — AKA Hokm-only

**EXPLICIT.** Lines 15–19 (~00:24–00:29):

> "اول شرط لازم اللعب يكون حكم يعني في الصن ما في شيء اسمه تاكيك فقط في الحكم"
>
> EN: "First condition: play must be Hokm. In Sun there is nothing called AKA — only in Hokm."

**Confidence: HIGH.**

---

### Q6 — Partner-trump-void precondition

**Strictly speaking, NOT a precondition — it is a *don't-bother* heuristic.** The speaker treats partner-trump-void as the (a,iii) and (c,*) cells where AKA is pointless/forbidden, not as a hard legality precondition. The four hard preconditions (Q5+Q7+others) are listed at 00:20–02:34 as exactly four:
1. Hokm only
2. Non-trump suits only
3. Biggest available (excluding the Ace itself)
4. On-lead only

Partner-trump-void is **not** in those four. It is in the *when-to* heuristic.

> Line 279–281 (~05:41–05:45): "اذا انت متاكد انه خويك ما عنده حكم نهائيا لا تقول اك ابدا"
>
> EN: "If you are certain partner has absolutely no trump, never say AKA."

**Confidence: HIGH** that partner-trump-void is a *heuristic* not a *precondition*. If `Rules.lua` enforces it as legality, that's an over-restriction relative to #18.

---

### Q7 — Boss-of-suit precondition

**EXPLICIT.** Lines 35–39 (~00:48–00:54):

> "ثالث شرط مهم عندنا تقول اكه على اكبر ورقه موجوده عندك غير الاكه"
>
> EN: "Third important condition: say AKA on the biggest card you hold besides the Ace."

> Lines 81–87 (~01:41–01:48): "تعرفها بالاكه يعني هذه اكبر ورقه واذا كانت الاكه عند احد اللاعبين ممنوع تقول اك على العشره"
>
> EN: "[AKA] tags it as the biggest card; if the Ace is with another player, forbidden to AKA on the 10."

**Confidence: HIGH.**

---

### Q8 — False-AKA penalty (Qaid)

**MENTIONED, not by the formal name "Qaid" but using قد / قيد (caid/qaid variants).**

> Lines 33–35 (~00:45–00:51): "ولو قلت عليها اكا طبعا هذا قد"
>
> EN: "If you say AKA on it [trump], of course this is qaid [penalty]."

> Lines 49–55 (~01:08–01:15): "اذا كان اللعب مشدود طبعا اكيد قيت اذا كان اللعب حبه في ناس تقيد وفي ناس لا"
>
> EN: "If play is tight, definitely qaid; if play is loose, some people qaid and some don't."

> Lines 297–299 (~06:03–06:08): "وتقيد عليك هنا خويك حيلومك وحيفصل عليك"
>
> EN: "And you get qaid'd; here your partner will blame you and split [scold] you."

**Confidence: HIGH** that the qaid penalty mechanism is explicit. Note the speaker uses قد / قيد / تقيد forms interchangeably — these are dialect variants of قَيْد.

---

### Q9 — AKA-on-T in suit-leading-context

**See HEADLINE FINDING.** The speaker says T-with-AKA *announces* "I have the biggest" but does **not** say T legally substitutes for A in trick resolution. Worked example at 03:36–03:42 has opp cut the AKA'd T with a trump.

**Confidence: HIGH** (negative).

---

### Q10 — Trick-1 categorical skip vs G18-10 "early-game permissive"

**No explicit "skip trick 1" rule in #18.** The speaker's contradiction-resolving content:

> Lines 311–317 (~06:24–06:31): "بدايه الجيم لسه تو في البدايه … ممكن تجازف"
>
> EN: "Start of the round, just at the beginning … you may gamble."

This **contradicts** any code rule that categorically skips AKA on trick-1. #18 explicitly *encourages* AKA at game-start when uncertain. If `Bot.PickAKA` has a categorical `if trickIndex == 1 then return nil`, that conflicts with #18's permissive guidance.

**Confidence: HIGH** that #18 does NOT support a categorical trick-1 skip. Resolution: the trick-1 skip (if present in code) is an addon construct, not from #18.

---

## Summary table

| # | Question | Verbatim found? | Confidence |
|---|---|---|---|
| 1 | 3×3 matrix | YES, all 9 cells | HIGH |
| 2 | AKA-on-T locks trick | **NO** (negative) | HIGH |
| 3 | Implicit AKA via bare-A | YES | HIGH |
| 4 | Early permissive / late conservative | YES | HIGH (early); MEDIUM (doubled-specifically) |
| 5 | Hokm-only | YES | HIGH |
| 6 | Partner-trump-void precondition | NO (heuristic, not precondition) | HIGH |
| 7 | Boss-of-suit precondition | YES | HIGH |
| 8 | Qaid penalty | YES (as قد / قيد) | HIGH |
| 9 | AKA-on-T substitutes for A | **NO** (negative) | HIGH |
| 10 | Trick-1 categorical skip | **NO** — contradicts G18-10 | HIGH |

---

## Doc-misframing verdict

**The `Rules.lua:108-110` comment "10-substitutes-for-Ace semantic collapses to same rule" is misleading.**

Video #18 supports:
- T-with-AKA = signaling equivalent to "biggest available" (informational)
- T-with-AKA releases partner from overtrump obligation (legality-relief, partner-side)

Video #18 does **NOT** support:
- T legally substituting for A in trick-winner determination
- AKA-on-T preventing opponents from cutting with trump
- Any "trick lock" semantic

**X2 B5 + B-Net-01 F-AP-21 audit conclusion stands.** Part 1 (AKA-on-T trick lock) is correctly absent from `R.CurrentTrickWinner`. The doc comment should be revised to say something like: *"AKA-on-T provides partner-overtrump-release equivalent to AKA-on-A (per video #18 03:36–04:20); it does NOT alter trick resolution."*
