# A-Src-09 — Video #35 SWA Term Detailed (re-extraction)

**Source:** `docs/strategy/_transcripts/IMJIrhW4qOA_35_swa_term_detailed.ar-orig.srt`
**Video ID:** `IMJIrhW4qOA` (yt watch?v=IMJIrhW4qOA)
**Title slug:** `35_swa_term_detailed`
**Re-extracted:** 2026-05-05 for v0.10.2 R3 D-RT-13 / D-RT-31 arbitration.
**File size:** 3,345 SRT lines covering ~21 minutes of the talk.

---

## Headline arbitrations resolved

| Finding | Authority verdict | Confidence |
|---|---|---|
| **D-RT-13 / RT-13.1** — addon's 5-second auto-approve violates Saudi rule | **CONFIRMED.** Video #35 contains **zero** timing/timer/seconds vocabulary across all 3,345 lines. The 5+-card mandatory-permission rule is verbal-negotiation; permission is the explicit verbal "نسمح" (we allow) or a counter-demand of شرح (proof). No timer, no clock, no auto-yield. The addon's 5s auto-approve is a UX construct only, not a rule. | High |
| **D-RT-31 + B-Net-04** — `R.IsValidSWA` partner-adversarial may over-reject Hokm two-hand SWA | **CONTRADICTED in spirit.** Video #35 line ~564–565 explicitly says "خويك راح يجي دائما ثق تماما" (your partner WILL come through, trust completely). For Hokm two-hand SWA the bidder relies on a cooperative partner-comes-through assumption — not a "partner-might-betray-you" strict-rejection model. **However**, the same speaker at line ~232–294 lists explicit *conditions* that must hold (partner must have trump, partner must hold A or top-suit card, you must hold "second-largest after partner"); these conditions are objective and non-adversarial. Saudi authority = strict objective conditions + cooperative trust within those conditions. The partner-adversarial branch in `Rules.lua` over-tightens by treating partner's hand as hostile evidence. | High for cooperative-trust reading; Medium for "over-rejects" claim — the video does not litigate this directly, it asserts the cooperative norm. |

---

## Per-question verbatim findings

### Q1 — Verbatim line 2244 "سوا من اول يد"

**SRT location:** subtitle #449, timestamp 00:10:03,640 → 00:10:06,590 (continued at #451 00:10:06,600 → 00:10:10,030).
**Verbatim Arabic (≤15 words across the two cues):**
> «اكثر من اربع اوراق في شيء اسمه سوا من اول يد من اول ثمانيه اوراق في يدك»

**English:** "More than four cards — there's a thing called *SWA from the first hand*, from the first eight cards in your hand."
**Context:** Speaker is enumerating the card-count hierarchy for SWA (3, 4, ≥5) and now introduces the special 8-card opening-deal SWA where you have EVERYTHING from the moment cards are dealt. This is the maximum-power SWA and the flagship example for the "must ask permission" rule.
**Confidence:** High.

---

### Q2 — Verbatim line 2404 "هنا تستالن طبعا ما تساوي"

**SRT location:** subtitle #481, timestamp 00:10:49,680 → 00:10:52,310.
**Verbatim Arabic (≤15 words):**
> «فانت هنا تستالن طبعا ما ت ما تساوي لو ساويت»

**English:** "So here you ask permission, of course — you don't [just] SWA. If you SWA…"
**Translation note:** «تستالن» here is a colloquial verb form of «تستأذن» = "you ask for permission". The double «ما ت ما تساوي» is a self-correction by the speaker (he begins «ما ت» then restarts as «ما تساوي»). This is the explicit declaration that the 8-cards-everything SWA scenario REQUIRES asking permission first.
**Confidence:** High.

---

### Q3 — Verbatim line 2414 "لو ساويت بدون ما تستاذن... مستحيل يمشونها"

**SRT location:** subtitles #483 (00:10:52,320 → 00:10:55,230) + #485 (00:10:55,240 → 00:10:57,990).
**Verbatim Arabic (split across two cues, full sentence ≤25 words):**
> «لو ساويت بدون ما تستاذن يا سلام هذه مستحيل يمشونها لانه ورق زي كذا مفجر مستحيل يمشونه»

**Single ≤15-word excerpt:**
> «لو ساويت بدون ما تستاذن يا سلام هذه مستحيل يمشونها»

**English:** "If you SWA without asking permission — wow! It's *impossible* they'd let it pass, because cards like this are explosive, impossible they let it through."
**Why it matters:** This is the single load-bearing sentence behind the v0.10.0 R3 / RT-13.1 finding. "مستحيل يمشونها" ("impossible they'd let it pass") is the cultural-rule-strict assertion: the opposing team will *always* exercise the قيد (qaid / lock-in / failed-proof) penalty against unauthorised 5+-card SWA. There is **zero** mention of any timer or "if they don't respond". The flow is purely verbal-negotiation: SWA-er asks, opps either say نسمح (we allow) or demand شرح (proof) or refuse outright.
**Confidence:** Very high.

---

### Q4 — Verbatim line 2814 "ثق تماما انه خويك راح يجي دائما" + lines 2800–2870 surrounding context

**SRT location:** subtitle #563 (00:08:34,990 → 00:08:35,000) + #565 (00:08:37,320 → 00:08:40,430).

**Verbatim Arabic of the headline line (≤15 words):**
> «ثق تماما انه خويك راح يجي دائما ثق تماما»

**English:** "Trust completely that your partner WILL come through with diamonds. Trust completely."

**Surrounding context (subtitles 561–577, ≈ 00:08:34 → 00:08:56):**
The speaker is in the section on partner-cooperative SWA inside Hokm. The setup he describes:
- You have «سوا مثلا ثلاث اشكال تمام في يدك» — SWA on three suits in your hand.
- Lead is on partner's side («واللعب كان على يد خويك»).
- He then says: «ثق تماما انه خويك راح يجي دائما ثق تماما هذ دائما تصير في البلوت» — "Trust completely your partner will come through with diamonds, trust completely; this always happens in Baloot."
- Continues: «واحيانا ما تلم خويك يعني اذا كان اللعب مو واضح في البدايه فممكن خويك يلعب دائما تخيل وانت قل سوا فانت قل سوا خلاص اثبت انه سوا ما في سوا يتقيد عليك ممكن يمشونه عادي لكن في ناس ما يمشون هذه الاشياء فهذا برضه خطا» — "Sometimes you don't gather your partner — i.e. if the play wasn't clear at the start, your partner might lead diamonds (imagine); you say SWA, you said SWA, fine, prove it, no SWA can be locked-in against you, they might let it pass normally, but some people don't let these things pass, so this is also a mistake."

**Reading:** The Saudi rule for partner-cooperative SWA is **trust your partner** — the bidder's side relies on the cooperative partner-comes-through assumption to justify the SWA claim. BUT the speaker **also** flags a sub-case where partner played the *wrong* lead (partner played a card instead of waiting for the bidder), and notes some opps will *still* call qaid even though SWA was technically possible. So the cultural authority is: **trust + objective conditions met = valid SWA**; trust alone (without conditions) = mistake.

**Verdict for D-RT-31:** Authority strongly supports the cooperative-partner reading. `R.IsValidSWA` should NOT model the partner's hand as adversarially worst-case for the bidder's-team SWA — it should assume partner plays cooperatively, subject to the explicit objective conditions (partner has trump in Hokm, partner holds the top-suit card, bidder holds second-largest after partner — see Q15).
**Confidence:** Very high for the trust-partner principle; High for application to `R.IsValidSWA` partner-adversarial branch.

---

### Q5 — Verbatim line 2864 "خلاص اثبت انه سوا"

**SRT location:** subtitle #573, timestamp 00:08:48,320 → 00:08:50,710.
**Verbatim Arabic (≤15 words across the cue, the headline span):**
> «وانت قل سوا فانت قل سوا خلاص اثبت انه سوا ما في سوا يتقيد عليك»

**English:** "And you say SWA — you say SWA, fine, prove it (اثبت = prove); no SWA can be locked-in against you."

**Note:** «اثبت» is imperative "prove [it]" — the speaker is voicing what the bidder says to the opps to confirm the claim is sound after partner has (off-script) played a diamonds lead. In context: even when partner plays before you can SWA, you claim SWA, prove its objective validity, and no qaid penalty applies.
**Confidence:** High.

---

### Q6 — ≤3 cards instant claim

**SRT location:** subtitles #21–#43, 00:00:28,240 → 00:00:56,229.
**Verbatim (≤15 words):**
> «انت هنا من حقك انك تقول سوا يعني ترمي الورق زي كذا وتقول سوا»

**English:** "Here it's your right to say SWA — i.e. throw the cards like this and say SWA."
**Stronger sentence (≤15 words):** «خلاص هم يفهمون انها سوا فانت راح تاخذ كل الاكلات» — "Done, they understand it's SWA, so you'll take all the tricks."
**Context:** Setup is "the bid was Sun, lead is on this player, he played, the eater ate, and each player has THREE cards left in hand". Speaker says player "from his right" can claim SWA by throwing cards face-up and saying "سوا", or even silently throwing — opps "understand it's SWA". **No permission is mentioned for ≤3 cards.** The benefit clause that follows («فايده السوا انك تختصر الوقت» — "the benefit of SWA is you save time") frames SWA at this stage as a pure UX-shortcut.
**Confidence:** Very high.

---

### Q7 — 4-card permission

**SRT location:** subtitles #429 → #443 (00:09:36,320 → 00:09:58,710).
**Verbatim (≤15 words):**
> «في جلسات ما يسمح ان تقيد باربعه الا لم تستاذن يعني لازم تستاذن من باب الاحترام»

**English (≤30 words, displacive limit):** "In some sittings they don't allow you to claim four-card SWA unless you ask permission first — i.e. you must ask permission, as a matter of respect."
**Permission verbal pattern (subtitles #441–#443):** «فتقول مثلا تسمحوا لي اساوي خلاص قالوا لك نسمح راح تساوي» — "So you say e.g. *will you allow me to SWA?* Done, they tell you *we allow* (نسمح), then you SWA."
**Context flag:** The word «جلسات» (sittings/sessions) signals this is **session-dependent**: some sittings allow 4-card SWA without permission, others require it. The 5+-card rule (Q3) is universal; the 4-card rule is sitting-dependent. The addon should treat 4-card as the boundary where permission is *recommended* but not absolute, and 5+ as the strict-permission floor.
**Confidence:** High.

---

### Q8 — ≥5 cards mandatory permission (the headline rule)

**SRT location:** subtitles #481–#487 (00:10:49,680 → 00:11:00,310). Already covered Q2–Q3 above. Adding the second authority span:

**Verbatim (≤15 words from line 2444):**
> «العمر والسلامه تلعب ورقه ورقه لين ما يبقى لك اخر ثلاث اوراق تساوي»

**English:** "Long life and safety [colloquial = better safe than sorry] — play card-by-card until you have your last three cards, [then] SWA."

**Context:** This sentence appears immediately AFTER the "مستحيل يمشونها" assertion. The speaker's recommendation when you'd otherwise want a powerful 8-card SWA is: **don't do it without permission** — instead, play card-by-card down to the last three, then claim safe SWA. So the 5+-card mandatory permission isn't just a strict rule; it's contextualised with the "play down to safety" practical guidance. This makes the addon's behaviour even more important: a player who declines permission on a 5+-card SWA should NOT lose their hand — they should be able to fall back to playing card-by-card.
**Confidence:** Very high.

---

### Q9 — Auto-approve timer / timing vocabulary search

**Search terms used (regex over full SRT):** `ثوان|ثانيه|توقيت|تايمر|ينتظر|انتظار|عداد|ينتظر|تنتظر|انتظر|يستنى|تستنى|استنى|مده|دقايق|دقيقه|ثواني|ساعه`

**Hits found:** **Zero** lexical matches for "second(s) as a unit of time", "timer", "timeout", "wait-counter", or any timing vocabulary across all 3,345 lines.

The 6 hits that did surface are all unrelated:
- Line 1774, 1778, 1783 — «الحاله الثانيه» = "the **second** [case / scenario]" (ordinal, not seconds-as-time).
- Line 284, 288, 293 — «تنتظر دورك» = "wait your turn" (turn order in trick-play, not a permission timer).
- Line 314, 318, 323 — «ما تستنى دورك» = "don't wait your turn" (same context).

**Verdict for D-RT-13 / RT-13.1:** **Confirmed.** The 5-second auto-approve timer in `Net.lua` / `Rules.lua` has **no authority basis** in video #35. Permission is verbal: it's either granted ("نسمح"), counter-demanded ("اشرح"), or refused — and the speaker treats refusal-then-claim as guaranteed-qaid ("مستحيل يمشونها"). The addon's auto-approve is correctly understood as a UX-only construct to prevent network deadlock when opp humans don't respond, and CLAUDE.md already documents this. The arbitration question is whether the auto-approve threshold should ever be the path that *grants* the SWA — Saudi authority says no, but addon practicality says yes for non-AFK reliability. Recommend: keep the timer for human-AFK fallback, but log it as "auto-approved (no human response)" so that bot players never hit it as their default code path.
**Confidence:** Very high.

---

### Q10 — Permission verbal "نسمح" / "خلينا نلعب"

**SRT location for «نسمح»:** subtitle #443 (00:09:58,720 → 00:10:01,389).
**Verbatim (≤15 words):**
> «قالوا لك نسمح راح تساوي زي كذا تسوي تشرح»

**English:** "They told you *we allow* (نسمح), so you'll SWA like this — you do, you prove."

**SRT location for «خلينا نلعب»:** subtitles #519 (00:11:33,800 → 00:11:36,350).
**Verbatim (≤15 words):**
> «لكن هو ما يخليك تساوي ليش ممكن يقول خلينا نلعب نلعب لعب عادي»

**English:** "But he won't let you SWA — why? He might say *let's play, just play normally* (خلينا نلعب)."

**Context for «خلينا نلعب»:** This is the *refusal* verbal — opp denies permission. Speaker explains opp's motivation: "ممكن يصير في الجيم خويك يغلط يعني فرصه انت تغلط" — refusal preserves the chance the bidder or partner will mistake-play and create a قيد/penalty opportunity. So permission is a strategic decision, not a courtesy. This is direct authority for the addon's permission-decline logic.
**Confidence:** Very high.

---

### Q11 — Failed-proof = Qaid (قيد)

**SRT location for "fails proof → qaid":** subtitles #167 (00:03:44,560 → 00:03:47,509) + #199 (00:04:22,960 → 00:04:25,590).

**Verbatim 1 (≤15 words from line 833):**
> «ما ينفع لو قلت سوا ورميت الورق بهذا الشكل من حق الفريق الخصم انه يقيد عليك»

**English:** "It's not valid — if you said SWA and threw cards this way, the opp team has the right to قيد (qaid / lock-in) against you."

**Verbatim 2 (≤15 words from line 994):**
> «لو سويت زي كذا ورميت الورق هذه فيها قيد ليش لانه يقول لك هنا ما شرحت سواك»

**English:** "If you SWA'd like this and threw the cards, this gets قيد. Why? Because he tells you: here you didn't prove your SWA."

**Context:** The قيد flow has TWO trigger conditions both confirmed in transcript:
1. SWA without asking permission when permission was required (Q3).
2. SWA but failed to prove it correctly (e.g., didn't lay cards out in the demanded order to show no hidden risk). Subtitles #167 and #199 both confirm.

**Confidence:** Very high.

---

### Q12 — مثلوث (3-of-suit-with-K) breaks SWA

**SRT location:** subtitles #597–#609 (00:13:18,360 → 00:13:35,389).

**Verbatim definition (≤15 words from line 2994):**
> «الخصم عنده مثلوث يعني عنده ثلاث اوراق من نفس الشكل»

**English:** "Opp has *مثلوث* — i.e. he has three cards of the same suit."

**Verbatim qualified definition (≤15 words from line 3014):**
> «غالبا مثلوث تنقال اذا كانت ثلاث اوراق من نفس الشكل ومعاها شايب»

**English:** "Usually *مثلوث* is called when there are three cards of the same suit *with a K* (شايب = old-man = K)."

**Verbatim consequence (≤15 words from line 3034):**
> «شايب ومعه ورقتين يسمونه مثلوث فهذه الحاله سو خاط»

**English:** "K with two other [same-suit] cards is called *مثلوث* — and this case is *false-SWA* (سو خاط = mistaken/dirty SWA)."

**Mechanic explained in subtitles #609–#612:** If you SWA a non-K top card (e.g. you have A of suit but not K), and opp has K plus two same-suit cards (مثلوث), opp can play their lower same-suit card → you eat your A → opp later plays the K to win that round → your SWA is broken because you no longer have a-top-card-in-every-suit.

**Authority for `R.IsValidSWA`:** When the bidder has the A but **not** the K of a suit, and there exist 3+ unseen cards of that suit, the SWA must be rejected — that suit is مثلوث-vulnerable. `Rules.lua` should encode this case explicitly (or document it as a known sub-case the partner-adversarial branch already covers).
**Confidence:** High.

---

### Q13 — شرح (proof) demand

**SRT location:** subtitles #169 → #181 (00:03:47,519 → 00:04:05,030), #547 (00:10:18,470 → 00:10:21,470), and recurring throughout.

**Verbatim demand-trigger (≤15 words from line 2734):**
> «دورك وقلت سوا لو الفريق الخصم قال اشرح سواك»

**English:** "It's your turn, you said SWA, [if] the opp team said *prove your SWA* (اشرح)…"

**Verbatim proof-action (≤15 words from line 853):**
> «ما ترمي الورق زي كذا تقول سوا السوا الطبيعي لا هنا توضح اللعب»

**English:** "You don't [just] throw cards saying SWA — natural SWA, no — here you clarify the play [proof]."

**Verbatim demand-trigger condition (≤15 words from line 903):**
> «متى تشرح سواك اذا كان اي احد من اللاعبين الاخرين معه نفس الشكل»

**English:** "*When* do you prove your SWA? If any of the other players has the same suit [as one of yours]…"

**Mechanic:** Proof = laying cards down in the *demanded order* (lay all-trump first, then all-of-suit-X next, then suit-Y, etc.) to demonstrate that no opp can win a card by sneak-ordering. Demand can be triggered by *either* opposing player ("اي احد من اللاعبين الاخرين"), not only the team-leader.
**Confidence:** Very high.

---

### Q14 — Bidder-team SWA vs defender-team SWA — different rules?

**Search performed:** grep for «المنفذ», «المدافع», «الفريق المنفذ», «الفريق المدافع», «هاوش», «على المنفذ» across full SRT.
**Result:** **No occurrences** of any explicit bidder-team-vs-defender-team SWA distinction. The speaker uses generic «الفريق الخصم» (opposing team), «الفريق الثاني» (the second team), «الخصم» (the opp). The same SWA rules apply regardless of which team called the contract.

**Implicit hint at line 264:** «يكون على يدك ممكن يكون على يد الخصم» — "[the lead] might be on your side, might be on the opp's side". The speaker does treat "lead position" as a relevant variable for SWA validity (lead-on-bidder = stronger SWA case; lead-on-opp = weaker, possibly invalid). But this is a card-position rule, not a team-role rule.

**Verdict:** Video #35 has **NO** rule splitting bidder-team SWA from defender-team SWA. Anything `Rules.lua` currently does to differentiate them is not authority-grounded in #35. (May be grounded in another video — would need cross-check.)
**Confidence:** High that #35 is silent on the distinction.

---

### Q15 — Two-hand cooperative SWA in Hokm — verbatim authority for trust-partner reading

**SRT location:** subtitles #233 → #295 (00:05:08,919 → 00:06:37,350) + the trust-partner sentences in Q4 (subtitles #561 → #571).

**Verbatim conditions enumerated (subtitles #243–#247, ≤15 words from line 1213):**
> «انت عندك الديمد واكبر ورقه في الديمد مع خويك تمام»

**English:** "You have diamonds, and the *biggest card in diamonds is with your partner*, OK."

**Verbatim "must be sure" condition (≤15 words from line 1213):**
> «طبعا لازم تكون متاكد انه الورقه مع خويك اللي هي الاكا»

**English:** "Of course you have to be **sure** the card with your partner is the A."

**Verbatim "second-largest" rule (≤15 words from line 1353):**
> «من شروط سوا يدين انه يكون عندك ثاني اكبر ورقه بعد خويك»

**English:** "Among the conditions of two-hand SWA: you have the **second-largest** card after your partner."

**Verbatim Hokm-specific partner conditions (≤15 words from line 1494):**
> «لازم تشرح سواك طبعا وغالبا خويك لازم يكون معه حكم ولازم يكون معاه مقطوع»

**English:** "You must prove your SWA, and usually your partner *must have trump and must have a void* (مقطوع = void in some suit so partner can ruff)."

**Verbatim trust-completely (≤15 words):**
> «ثق تماما انه خويك راح يجي دائما ثق تماما»  *(line 2824, see Q4)*

**Synthesised authority for D-RT-31:**
The Saudi-authoritative two-hand cooperative SWA in Hokm has **objective conditions**:
1. Bidder holds the suit being claimed for two-hand sweep (e.g. diamonds).
2. The biggest card in that suit (A) is with **partner** — bidder must KNOW this (from bidding signals, AKA, prior plays).
3. Bidder holds the **second-largest** card in that suit.
4. Partner has **trump** AND a **void** (in Hokm specifically) so partner can ruff the third card.
5. Trust the partner will come through cooperatively (Q4 trust-completely sentence).

If `R.IsValidSWA`'s partner-adversarial branch checks all five objective conditions and they pass, it MUST return valid — modelling the partner's hand as worst-case adversarial would over-reject because it assumes partner plays *against* the SWA when objectivity says partner plays *with* it.

**The arbitration:** `R.IsValidSWA` should treat partner's hand as **conditional-cooperative**: partner will play cooperatively *if and only if* the objective conditions are met from the bidder's information set. If even one objective condition is uncertain (bidder doesn't have signal that partner holds the A), the SWA is invalid — but not because partner is adversarial, rather because the *condition itself* is unproven.
**Confidence:** Very high for the conditions; High for the application to the partner-adversarial branch.

---

## Cross-cutting findings

### Sun (صن) vs Hokm (حكم) — two-hand SWA scope

Subtitle #229 (line 1144): «ساوي يدين في الحكم مش في الصن لكن بعطيكم مثال في الصن وبعدين في الحكم» — "Two-hand SWA is in **Hokm, not Sun**, but I'll give you an example in Sun, then in Hokm." So **two-hand SWA only applies in Hokm contracts** — never in Sun. (Sun has no trump, so there's no ruff to clear partner's third card.)

If `Rules.lua` allows two-hand SWA in Sun, that's a bug.

### مقطوع (partner-must-have-void) — Hokm-specific

Subtitle #299 (line 1494) confirms partner must have a void as well as trump. The video does not specify *which* suit partner must be void in; from context it's the suit being SWA'd (so partner can ruff once the bidder plays the second-largest card and opp covers).

### Lead-position dependency

Subtitle #555 (line 2774): «لو هذا لعب مثلا دي كان على يده اللعب ولعب دائما وانت ما عندك دائما هنا لسه مو سوا» — "If [opp] played e.g. led with diamonds when lead was on him, and you don't have diamonds, here it's still NOT SWA." Lead position matters for SWA validity in some cases.

---

## Summary for D-RT-13 / D-RT-31

| Code claim | Authority | Verdict |
|---|---|---|
| 5+ cards = mandatory permission | line 2414 «مستحيل يمشونها» | **Confirmed** |
| Auto-approve timer = Saudi rule | (search returned 0 hits) | **Refuted** — UX construct only |
| 4-card permission = strict | line 2184 «في جلسات ما يسمح» | **Sitting-dependent** — not strict |
| ≤3 cards = instant claim | subtitles #21–#43 | **Confirmed** |
| Two-hand Hokm SWA = adversarial-partner | line 2824 «ثق تماما» | **Refuted** — cooperative-trust + objective conditions |
| Partner-must-have-trump-and-void | line 1494 «حكم ومقطوع» | **Confirmed** |
| Bidder holds second-largest after partner | line 1354 «ثاني اكبر ورقه بعد خويك» | **Confirmed** |
| مثلوث (3-suit-with-K) breaks SWA | line 3034 «سو خاط» | **Confirmed** |
| شرح proof on demand | line 2734 «اشرح سواك» | **Confirmed** |
| نسمح verbal-grant | line 2214 «قالوا لك نسمح» | **Confirmed** |
| خلينا نلعب verbal-decline | line 2594 «خلينا نلعب» | **Confirmed** |
| Bidder-team vs defender-team different rules | (no hits) | **Silent in #35** — no authority either way |
| Two-hand SWA in Sun | line 1144 «مش في الصن» | **Refuted** — Hokm only |

---

## Notes on transcript quality

- The SRT uses double-cue subtitles (each phrase appears twice with 10ms offset between cues — typical YT auto-caption artefact). Line numbers above point to the *visible* duplicate; the .ar-orig-ness preserves the colloquial Hejazi/Najdi phrasing.
- Several colloquialisms are used throughout: «تستالن» = «تستأذن» (ask permission), «خويك» = «أخوك» (your partner — literally "your brother"), «دائما» = «الديمنت» (diamonds — Arabicised English), «شايب» = K (literally "old-man"), «الولد» = J (literally "the boy"), «بنت» = Q (literally "girl"). Glossary cross-references in `docs/strategy/glossary.md` should already cover these.
- No timing words anywhere — strongest possible refutation of the auto-approve-timer-is-Saudi-rule claim.
