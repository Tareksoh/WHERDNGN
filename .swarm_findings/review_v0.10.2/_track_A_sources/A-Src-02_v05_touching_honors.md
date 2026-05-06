# A-Src-02: Re-extract of #05 Touching-Honors Signaling

**Source:** `docs/strategy/_transcripts/vkY55gg-39k_05_baloot_predictions_general.ar-orig.srt`
**Audit context:** v0.10.0 R6 K-singleton interpretation, cleared = {Q, J}
**Conflict:** D-RT-07 RT-07-I — video #41 (line 57) said "K → partner has Q (next-down)" with Definite confidence; this contradicts #05's K-singleton (Q/J BOTH elsewhere).
**Method:** verbatim quotes from SRT (each subtitle line repeats 3×; cite first occurrence by SRT line number).
**Important re-orientation:** the #05 corpus contains TWO distinct K-played scenarios. The audit-cited "lines 783-884" cover the **opponent-K** case. The **partner-K** case is at SRT line 963+ (timestamp 05:30+). Mapping these correctly is essential to resolving the K-singleton-vs-has-Q conflict.

---

## Q1. What does #05 say when follower plays K after partner's bare-A?

The video distinguishes two cases — **opponent plays K** vs **partner plays K** — and the inferences differ.

### Q1a. OPPONENT plays K (after your bare-A lead) — SRT lines 781-823, 04:48-04:56

The setup: YOU lead bare-A of spades (سبيد). Right opponent plays K (الشايب). Partner plays 10. Left opponent plays J. The speaker walks through the deduction.

**Quote 1** (SRT 783, **04:48-04:50**, ~13 words):
> العشراتك تمام شلنا العشره اذا هذا الخصم لعب الشايب احتمال يكون عنده عشره فقط
>
> EN: "Your 10's fine, we've removed the 10. So if this opponent played K, possibility he has only 10..."

**Quote 2** (SRT 793-803, **04:50-04:54**, ~14 words):
> فهو لعبه الشايب الاصغر من العشره لكن هل ممكن يكون عنده البنت ولا الولد لا مستحيل
>
> EN: "...so he played K the-smaller-than-10. But could he have Q or J? No, impossible."

**Quote 3** (SRT 813-823, **04:54-04:59**, ~14 words):
> لو عنده كان لعبها بدال الشايب لانها اصغر من الشايب
>
> EN: "If he had it [Q/J], he'd have played it instead of K, because it's smaller than K."

**Inference (opponent-K):** opponent who played K has neither Q nor J. cleared = {Q, J}. Confidence: **DEFINITE** (speaker uses مستحيل = "impossible").

### Q1b. PARTNER plays K (after your bare-A lead) — SRT lines 953-993, 05:30-05:42

A second, parallel example several seconds later. YOU lead bare-A. **Partner** (خويك, "your buddy") plays K. Right opponent had played J (ولد) before partner; left opponent plays 8.

**Quote 4** (SRT 953-963, **05:27-05:30**, ~10 words):
> الان لو انت لعبت اكه السويت خويك لعب الشايب
>
> EN: "Now if you played the bare-A of spades, your partner played K..."

**Quote 5** (SRT 973-993, **05:32-05:39**, ~14 words):
> قبله يفترض لعب ولد واللي على اليسار لعب ثمانيه كذا لعب الشايب مستحيل يكون عنده العشره
>
> EN: "Before it [partner played K], presumably J was played, and the one on the left played 8 — partner playing K thus, impossible he has the 10."

**Quote 6** (SRT 993-1013, **05:39-05:45**, ~12 words):
> هذه اهم معلومه تعرفها خلاص العشره مش عند خويك اذا العشره اما عند هذا اللاعب وعند هذا اللاعب
>
> EN: "This is the most important info you know: the 10 is NOT with your partner. So 10 is either with this opponent or that opponent."

**Inference (partner-K):** partner who played K does NOT have the 10. The speaker is silent about Q/J location for partner here. cleared = {10} for partner.
Confidence: **DEFINITE** (مستحيل + "اهم معلومه").

---

## Q2. K-singleton (Q/J elsewhere) OR has-Q (next-down)? OR both depending on context?

**RESOLUTION:** Both — but they are different rules applied to different players.

| Scenario | Inference about K-player | Inference about partner |
|---|---|---|
| **Opponent plays K** after your bare-A | Opponent has neither Q nor J (cleared {Q,J}) | Q and J go to {partner, other opponent} — speaker eventually concludes partner has Q (see Q4) |
| **Partner plays K** after your bare-A | Partner does NOT have the 10 | Speaker is silent on Q location |

**The audit's K-singleton interpretation (cleared={"Q","J"}) is correct ONLY for the opponent-K case.**

For partner-K, #05 only clears the 10 from partner — it does NOT clear Q or J from partner. Indeed, at lines 871-883 (timestamp 05:08-05:13) the speaker concludes the OPPOSITE: that partner DOES have Q, in the opponent-K branch (see Q4 below).

**The #41 "K → partner has Q (next-down)" inference is also present in #05** — at lines 871-883, in the opponent-K branch, applied AFTER the K-singleton clears Q/J from the K-player. Confidence: **STRONG** (غالبا = "usually").

So the conflict is **resolved by recognizing they are sequential deductions, not contradictions**:

1. Opponent plays K → opponent has neither Q nor J (#05 K-singleton, definite)
2. Therefore Q/J ∈ {partner, other-opp}
3. Then by "your partner gives you the next consecutive card" rule, partner usually has Q (#41 next-down rule, strong/usually)

Both rules are RT-07 valid, but represent **different moves in the deduction chain**. v0.10.0 R6's `cleared={"Q","J"}` correctly clears the K-player but should NOT clear partner.

---

## Q3. Trust-asymmetry quote (R3f at 03:17-03:22)

**Quote 7** (SRT 412-433, **03:15-03:24**, ~14 words):
> ولو عند خويك طلع سبيت هذا قد عليه طبعا انت ما تقيد على خويك لكن هذا خصم ممكن يقيد عليه
>
> EN: "And if at your partner's the spade came up, this is at-his-edge for him. Of course you don't constrain on (تقيد) your partner, but this is an opponent — possibly you constrain on him."

**Note:** the speaker uses تقيد ("constrain on / restrict to / pin down by"), meaning treat the play as a hard constraint when reading the hand. The asymmetry: opponent plays *can* be pinned down (he played his lowest, you read constraints); partner plays *cannot* be pinned the same way (partner may signal, may finesse, may play oddly to communicate).

This is the **trust-asymmetry rule** R3f. Confidence: **DEFINITE** (طبعا = "of course").

**IMPORTANT terminological clarification:** Saudi تقيد in this context means "treat as constraint" — i.e. the speaker is saying you SHOULD apply rigid constraint-reading to opponents but NOT to your partner. v0.10.0's "trust partner signals at face value, discount opponent signals" is **opposite-polarity** to the literal Arabic. Re-check whether the v0.10.0 R3f implementation has the polarity backwards: per #05, partner's plays are the LESS constrained (they might be tactical), and opponent's plays are MORE constrained (they're playing their lowest). Confidence on the polarity flag: **HIGH** — verbatim Arabic supports the opponent-is-constrained reading.

---

## Q4. R3a-f granularity per honor

Mapping each honor → what #05 says when follower plays it after a bare-A lead:

### R3a: T (10) played

**Quote 8** (SRT 463-483, **03:29-03:36**, ~14 words):
> اذا الخصم لعب ورق وانت ماكل حله معناته ما عنده اسهر منها ما عنده اسر من عشره ما عنده الشايب ما عنده البيت
>
> EN: "If opponent plays a card and you're winning the trick, it means he has nothing higher: no smaller-than-10 [reads strange — see note], no K, no Q [البيت = البنت]."

**Note:** the SRT contains an ASR transcription error — "اسر من عشره" should be "اسرع من عشره" or possibly is a phonetic confusion. The intended meaning, given the context of plays-after-bare-A, is "no card more-senior than 10" = "10 was his max". The K-and-Q exclusion is explicit.

**Quote 9** (SRT 483-498, **03:33-03:38**, ~10 words):
> راح تفهم انه العشره تك عند هذا اللاعب
>
> EN: "You'll understand that the 10 is at-his-edge / his max at this player."

**Quote 10** (SRT 533-563, **03:46-03:54**, ~13 words):
> في اصول البلوت اذا خويك لعب عشره يعني انت لعبت في البدايه وخويك لعب عشره معناته مع الشايب
>
> EN: "In the principles of Baloot, if your partner plays 10 — i.e. you played at the start and partner played 10 — it means he has K with him."

**T-rule:** T played → player has the next-up (K). Confidence: **DEFINITE** (في اصول البلوت = "in the principles of Baloot").
- Partner-T: partner has K (Q4-line 553).
- Opponent-T: opponent has nothing higher (Q4-line 463), and partner can be inferred to hold K (line 533 generalizes).

### R3b: K played

See Q1 (above). Two sub-cases:
- Opponent-K: opponent cleared of {Q, J}. **DEFINITE**.
- Partner-K: partner cleared of {10}. **DEFINITE**.

### R3c: Q (البنت) played

**Quote 11** (SRT 1854-1873, **09:03-09:11**, ~14 words):
> اذا هذا اللاعب لعب البنت احتمال يكون عنده الشايب والعشاء واذا خويك يلعب الولد
>
> EN: "If this player [= opponent] played Q, possibility he has K and 10 [العشاء = العشره], and if your partner plays J..."

**Q-rule (opponent-Q):** Q played → player likely has K and 10 (i.e. Q is from K-Q-T sequence head, played to lure). Confidence: **STRONG** (احتمال = "possibility/likely").

This is the OPPOSITE inference from K-rule: K-played clears Q/J from player; Q-played adds K and 10 to player. The asymmetry is because Q is mid-rank and could be a holdup, while K is unambiguous (only card above K is A).

### R3d: J (الولد) played

No explicit J-as-signal rule in #05 found in the touching-honors section. J appears mainly as the "next card down to give partner" reference (see SRT 1233-1273) and as the smallest-after-Q option (SRT 1854-1864).

**Note:** D-RT-07 should mark J-signal as **NOT_COVERED** in #05.

### R3e: 9 (التسعه) played

**Quote 12** (SRT 1944-1963, **09:25-09:32**, ~14 words):
> اذا كانت سبعه يبدا يزيد احتمال انه يكون عنده العشره عند خويك تمام
>
> EN: "If it [the small card] was a 7, the probability begins to rise that the 10 is with your partner..."

**9-rule:** small cards (9, 8, 7) all signal "no high-honor cards"; smaller = stronger signal that the 10 lives elsewhere (with partner). Confidence: **MODERATE** (يبدا يزيد احتمال = "probability begins to rise").

### R3f: 8, 7 played

**Quote 13** (SRT 2533-2553, **11:54-12:00**, ~14 words):
> لو لعبه سبعه بعكس لما يلعب مثلا واحد منا ملعب عشره ويلعب مثلا شايب لا هنا احتمال يقل عنده احكام
>
> EN: "If he played 7, the opposite of when he plays e.g. 10 [or] then plays K — there the probability of-him-having-trumps decreases."

**8/7-rule:** 7 most strongly signals "I have nothing"; 8 slightly less strong; descending honors signal less depletion. Confidence: **STRONG**.

---

## Q5. Hokm-specific vs Sun-specific framing — which contract does the K-rule apply to?

The video has explicit section transitions:

**Quote 14** (SRT 64-73, **00:19-00:21**, ~10 words):
> ناخذ الحكم اول شيء عندنا في اربع اشكال
>
> EN: "Take Hokm — first thing we have, four suits..."

Wait — re-checking sequence. The video starts with the first ~9 minutes on **Sun (basics with examples in spades)**, then transitions:

**Quote 15** (SRT 2034-2043, **09:48-09:53**, ~10 words):
> الان نبغى ناخذ الحكم دائما عندنا الحكم خاص اذا خويك لعب ورقه مستحيل يكون عنده اكبر منه
>
> EN: "Now we want to take Hokm — always with us Hokm is special. If your partner plays a card, impossible he has higher than it..."

**Section structure:**
- 00:00 - ~09:48: **Sun framing** (الصن / السميد in spade-form examples, generic across 4 non-trump suits — see SRT 350: "في الاربعه الاشكال" = "in the four suits")
- 09:48 - end: **Hokm framing** (الحكم — explicit contract switch)

**The K-rule lines 781-993 (the Q1a + Q1b core) are in the SUN section.** Confidence: **DEFINITE** (Hokm transition is at SRT 2034 / 09:48, well after the K example's 04:48).

The opener (SRT 22-44, 00:05-00:14) explicitly says: "نشرح باذن الله على التوقع في البلوت ... راح نبدا نشرح في الصن وبعدين راح ناخذ الحكم" = "we'll explain prediction in Baloot ... we'll start with Sun then take Hokm".

**Implication for v0.10.0 R6:** the K-singleton rule originates from **Sun-context analysis**. Hokm has its own signaling (next-down rules, 8 SRT lines later at 2043 says "in Hokm if partner plays X impossible he has larger" — this is the Hokm-specific version of the rule).

The video #41 line-57 "K → partner has Q (next-down)" is for **Sun basics** per its own context. Both #05 and #41 are in Sun framing for this rule.

---

## Q6. Partner-still-winning precondition (D-RT-07 RT-07-H)

Does the speaker require partner's bare-A to STILL be winning when the follower plays?

**Quote 16** (SRT 463-483, **03:29-03:36**, ~13 words — partial of Q8):
> اذا الخصم لعب ورق وانت ماكل حله معناته ما عنده اسهر منها
>
> EN: "If opponent plays a card and you're winning the trick (انت ماكل حله), it means he has nothing higher..."

**Quote 17** (SRT 1894-1913, **09:13-09:21**, ~14 words):
> طبعا بشرط تكون انت ماكل لك زي هذا المثال خويك لعب الثمانيه
>
> EN: "Of course, conditional that you are winning [الحله], as in this example your partner played 8..."

**Precondition: YES.** The speaker explicitly conditions the inference on "you/your-side currently winning the trick" (انت ماكل حله / ماكل لك = "you're eating the trick" = your side is current winner).

In the bare-A scenarios (Q1a + Q1b), bare-A is the LEAD itself — by definition still winning when followers play. So the precondition is implicit in the bare-A example but is an explicit general rule. Confidence: **DEFINITE** (طبعا بشرط = "of course conditional").

**Implication for D-RT-07 RT-07-H:** the K-singleton (and all touching-honor signals) require "your side still winning" precondition. Bare-A leads satisfy this by construction. If a sequence breaks the precondition (e.g. partner trumped before opponent K-played), the inference does NOT apply.

---

## Q7. Implicit AKA via bare-A — does #05 cover this or only #18?

**Quote 18** (SRT 1983-2024, **09:33-09:48**, ~14 words):
> فاذا هذا لعب اكه معناته عنده عشره عنده شاي واذا خويك زي كذا واذا هذا اللاعب نفس الكلام
>
> EN: "...so if this [player] played [implicit] AKA, it means he has 10, has K [شاي = شايب shortened]. And if your partner [does] like this — same. And if this player [the other] — same talk."

**Note:** this section is at the SUN→HOKM section transition (Hokm officially starts at 09:48). The substantive content: any player who plays an A in non-leading position effectively signals "I have 10 and K (KA holdup-protected) next to it." The speaker says it applies generically: "this [opponent], partner, this [other player] — same talk."

**Implicit-AKA coverage in #05: PARTIAL but generic.** #05 has a brief mention at 09:33-09:48 stating the rule applies to ANY player (not just partner). The full Implicit-AKA framework lives in #18 (per audit notes).

**What #05 contributes:** confirms that an implicit AKA (any player playing A as a non-lead, non-trump high) signals "I have 10 and K with the A." The rule is symmetric across all positions. This is consistent with v0.10.0's implicit-AKA logic if it applies to all players (not just partner). Confidence in the partial mention: **MODERATE** (the SRT is rough but the K + 10 deduction is unambiguous and the generic application is explicit via "خويك زي كذا واذا هذا اللاعب نفس الكلام").

---

## Resolution of D-RT-07 RT-07-I (K-singleton vs has-Q conflict)

**The conflict is APPARENT, not real.** Both #05 (K-singleton) and #41 (K → partner has Q) are correct, and **both are present in #05**.

The sequence in #05 lines 781-883 is:

| Step | SRT lines | Inference |
|---|---|---|
| 1 | 781-823 | Opponent plays K → opponent has neither Q nor J (cleared {Q, J}) |
| 2 | 833-853 | Therefore K is opponent's max |
| 3 | 853-883 | Now compute Q location: "partner usually has Q because ... what's after them in power? Q" (lines 871-883) |

So #05 contains BOTH: K-singleton at the K-player AND Q-at-partner as a downstream inference. v0.10.0 R6's `cleared={"Q","J"}` is correct for the K-PLAYER but the implementation may need an additional step that PUTS Q at partner (with strong/usually confidence).

**Recommended action for v0.10.2 audit:**
1. Keep `cleared={"Q","J"}` for the K-player (opponent-K case).
2. Add `addedAuras` (or equivalent) Q-at-partner signal with strong/usually confidence (#05 lines 871-883 + #41 line 57 corroborate).
3. Distinguish opponent-K from partner-K: partner-K should clear ONLY {10} from partner.
4. Verify trust-asymmetry R3f polarity (Q3 above): #05 reads the OPPOSITE direction from how v0.10.0 worded it; partner plays are LESS constrained, opponent plays are MORE constrained.
