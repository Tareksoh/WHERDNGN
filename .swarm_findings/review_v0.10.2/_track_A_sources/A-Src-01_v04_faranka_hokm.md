# A-Src-01 — Video 04 (Faranka in Hokm) re-extraction for v0.10.2 / D-RT-03 S-1

**Source:** `C:\CLAUDE\WHEREDNGN\docs\strategy\_transcripts\h1eEwSezzic_04_faranka_in_hokm.ar-orig.srt`
**Scope:** Video #04 only (`h1eEwSezzic_04`). Video 06 is **out of scope** for this re-read; the previous review's `source_C_faranka.md` merged 04+06, and several questions (F-14, anti-rule 7) cite content that is *not present in video 04* — flagged below.
**Reviewer agent:** Track-A source re-extractor.
**Re-extraction trigger:** D-RT-03 S-1 (BUG) requires source arbitration on F-16 universality vs. F-30b interaction. v0.10.2 carry-forward audit demands tighter quotes for the bidder-team predicate.

**Total runtime of video 04 transcript:** 6:29 (final cue ends @ 00:06:29,600).

**Reading method:** SRT cue-by-cue. Arabic quotes given verbatim ≤15 words, English literal translation (not paraphrase), timestamp from cue start of the *first* cue containing the quote, source-confidence per Saudi-tutorial standard (Definite / Common / Sometimes).

---

## TL;DR (answers to the prompt's six questions, all from video 04 alone)

| # | Question | Answer |
|---|----------|--------|
| Q-D-RT-03 | Is F-16 (K-of-trump cover) **universal** in video 04? | **No, video 04 never states F-16.** F-16 is a *Sun-Faranka* anti-rule from **video 06**, which v0.10.0 X3 **lifted into the Hokm code path**. Video 04 makes no K-of-trump claim either way. **Source-side, F-16 has no Hokm-Faranka mandate.** D-RT-03 S-1 is correct that F-16 over-fires when the K-cover threat model is extinct (opps trump-void); the source provides no counter-argument. |
| 1 | Anti-rule F-14 ("must Faranka") slip — verify | **Not in video 04.** F-14 originates from video 06. Out of scope. |
| 2 | F-16 — universal or context-dependent? | **Not in video 04.** Video 04 has no F-16 statement. v0.10.0's import of F-16 into Hokm is an inference *from* video 06's Sun anti-rule; video 04 does not endorse it. |
| 3 | F-29 (J-dead) — "after J played" or "J counted as gone"? | Speaker's exact words at 03:19: "اذا الولد لعب من اول". Literal: "**if the J was played at the start**" (i.e., **a prior trick has already happened in which J fell**). Source language is *strictly past-tense / completed-trick* — **not** "J counted as gone in this trick". |
| 4 | F-30 / Exception #4 — bidder-team OR bidder-only? | F-30's *example* at 05:00 is **bidder-only** ("وده انت كنت مشتري حكم"). But the speaker **generalises immediately at 05:28**: "سواء انت مشتري او خويك او حتى لو الخصم" — "**whether you are the buyer or your partner or even if the opponent [bought]**". F-30's *favourability framing* is bidder-only; the broader meta-rule (worst-case planning) is universal. **Code's `contract.bidder == seat` is over-tight** — should be `R.TeamOf(contract.bidder) == R.TeamOf(seat)` (bidder team). |
| 5 | F-27 / Exception #2 — 2-trump-count gate verbatim | Verbatim: "ممكن تتفرنك اذا كان عندك حكمين فقط". Literal: "you may Faranka **only if you have two trumps only**". Strict-equality reading; speaker says "حكمين فقط" = "two trumps, that's all". Hand-shape example given is "you bought Hokm and got no second trump" — **bidder example, but rule is hand-shape (=2 trumps), not seat**. |
| 6 | Anti-rule rule 7 (opp Q-led + J+8 rebut) | **Not in video 04.** No rule mentions "Q-led trump rebut" anywhere in the 6:29 of video 04. This appears to be either (a) an extrapolation from video 06's Sun-Faranka factor weighting, or (b) an addon-internal heuristic with no source basis. Flagged as **single-track-A unsupported**. |

---

## Verbatim extracts (video 04 only, in transcript order)

### Setup / framing (00:00–01:20)

#### V04-Q1 — DEFAULT NO Hokm-Faranka

- **Timestamp:** 00:00:09,120 → 00:00:16,440
- **Arabic verbatim (≤15 words):** "اغلب لاعبين البلوت راح يقول لك لا تدفنك في الحكم"
- **English literal:** "Most baloot players will tell you do not Faranka in Hokm."
- **Speaker's stance:** "ولو تجي تسالني نفس الكلام بشكل عام الافضل لا تترن في الحكم لكن فيها تفصيل"
  - Literal: "And if you ask me, same answer; in general it's better not to Faranka in Hokm, **but there is detail**."
- **Source-confidence:** **Definite**.
- **Maps-to:** F-23 (default-NO).

---

### Exception #1 — Type-3 cabotage to lose trick to opps (01:20–01:37)

#### V04-Q2 — First exception: Type 3 only

- **Timestamp:** 00:01:20,040 → 00:01:37,560
- **Arabic verbatim (≤15 words):** "تخسرها على الخصم ممكن في هذه الحاله لك افضليه في الفرنكه"
- **English literal:** "[If you want to] lose it to the opponent, possibly in this case you have an advantage in Faranka."
- **Restriction phrase:** "في النوع الثالث فقط لانه تقريبا نفس الصمت"
  - Literal: "**in Type 3 only, because [it is] almost the same as Sun**".
- **Closing condition:** "اما غير كذا ما انصحك ابدا"
  - Literal: "**Other than that, I never advise it**."
- **Source-confidence:** **Definite**.
- **Maps-to:** F-24 (Type-3-only cabotage), F-25 (hard-stop on Types 1/2).
- **No contradiction** with v0.10.0 source_C extraction.

---

### Exception #2 — Type 1 trump-only with J/Walad pre-condition (01:37–02:18)

#### V04-Q3 — Worked example: bidder, partner cuts, opp plays J

- **Timestamp:** 00:01:37,560 → 00:02:00,420
- **Arabic verbatim (≤15 words):** "افترض المربع هذا طبعا ما راح يلعب التسعه راح يلعب البنت"
- **English literal:** "Assume this 'cutter' [partner] won't play the 9, [they] will play the J [bint = Q here actually]." — see correction.
- **Translation note:** The speaker says "البنت" = literally "the girl" = **Queen**. The wider context ("ما راح يلعب التسعه راح يلعب البنت") is the worked example where **partner cuts (with a low trump)**, and the speaker contrasts the 9 vs the Q as the trump-rank-7-vs-rank-3 question. **This is a Q (البنت), not a J (الولد)** — the v0.10.0 extraction labelled the seat-before-you's card as "J" which is incorrect for this passage; it's "Q".
- **Continuation:** "اجباري انك تكبر فلا تلعب عشره يا تلعب ولد" (00:01:49)
  - Literal: "Compulsory that you cover, so [you] either play 10 or play J [walad]." — confirms **J=walad** distinct from **Q=bint**.
- **Critical seat predicate (V04-Q3b):**
  - **Timestamp:** 00:02:04,140 → 00:02:09,360
  - **Arabic verbatim (≤15 words):** "والتسعه لازم تكون للاعب اللي قبلك"
  - **English literal:** "**And the 9 must be with the player who is before you**" (i.e., right-opp in CCW Saudi seating).
- **Anti-condition (V04-Q3c):**
  - **Arabic:** "فلو كانت عند خويك ما راح تنفع الفرنك" (00:02:06)
  - **Literal:** "If [the 9] is with your partner, Faranka won't help."
  - **Arabic:** "او لو كانت عند الخصم اللي بعدك هذي مشكله راح يلعبها وراح ياكل الحله" (00:02:09)
  - **Literal:** "Or if it's with the opp **after** you, this is a problem — they'll play it and eat the trick."
- **Source-confidence:** **Definite** (worked example, repeated three times).
- **Maps-to:** F-26.
- **Bidder-team note (V04-Q3d):**
  - **Arabic:** "ناخذ هذا المثال لو انت اشتريت حكم وخويك ... قطع" (00:01:37)
  - **Literal:** "Take this example: if **you bought Hokm** and your partner ... cut [with low trump]."
  - **Source-confidence:** Bidder-side example only; rule-statement does not generalise. **Code's bidder-team gating is faithful to the example, but the source does not state the rule fails for non-bidder seats.** Single-source ambiguity preserved.

---

### Exception #3 — Weak Hokm holding (only 2 trumps) (02:18–02:38)

#### V04-Q4 — F-27 verbatim 2-trump gate

- **Timestamp:** 00:02:24,660 → 00:02:30,959
- **Arabic verbatim (≤15 words):** "ممكن تتفرنك اذا كان عندك حكمين فقط"
- **English literal:** "**You may Faranka [only] if you have two trumps only.**"
- **Worked-example continuation (V04-Q4b):**
  - **Arabic:** "يعني لو مثلا اشتريت حكم ما جاك اي حكم ثاني فهذه الحاله انت احكامك ضعيفه"
  - **Literal:** "I mean if e.g. you bought Hokm and no second trump came, then in this case **your trumps are weak**."
  - **Hand example:** "عندك الولد مثلا جنبها العشره او جنبها اي ورقه" (00:02:30)
    - Literal: "You have the J e.g. with the 10 next to it, or with any [other] card next to it."
- **Reasoning:** "ممكن في هذه الحالات يتفرنك املا انه مثلا ما تخسر عليك" (00:02:33)
  - Literal: "Possibly in these cases [you] Faranka, hoping that you don't lose [more]."
- **Source-confidence:** **Definite** wording, **Common** as a guideline.
- **Bidder-team scope:**
  - Speaker's example phrases this as bidder ("اشتريت"), but the rule predicate is **hand-shape** (=2 trumps + J-adjacent). The rule is not stated as "bidder-only" — it is a hand-shape rule whose example happened to be the bidder. **Strict reading: code's `contract.bidder == seat` gate over-restricts.** Looser reading: any seat with 2-trump weak-J holding may apply.
- **Numeric strictness:** "حكمين فقط" = literal "two trumps **only**". Strict-equality reading is safest; the v0.10.0 doc flagged this as ambiguous (≤2 vs =2). Re-read confirms strict =2 wording — but pragmatically the rule is "you have very few trumps, you accept the risk", so a `≤2` predicate is defensible from intent, **not** from literal Arabic.

---

### Exception #4 — Type 1, holding 9 with redundant trump (02:38–03:19)

#### V04-Q5 — F-28 (9 mardoofa)

- **Timestamp:** 00:02:38,809 → 00:02:44,449
- **Arabic verbatim (≤15 words):** "افترض انه عندي التسعه والتسعه مردوفه معايا"
- **English literal:** "Assume I have the 9 and the 9 is mardoofa with me" (mardoofa = adjacent / paired with another trump).
- **Decision pivot (V04-Q5b):**
  - **Timestamp:** 00:02:47,449 → 00:02:52,369
  - **Arabic verbatim (≤15 words):** "اجباري في الحكم انك تلعب التسعه لو لعبت العشره"
  - **English literal:** "**Compulsory in Hokm that [you] play the 9 [no Faranka], if [you] played the 10 instead** [the rule shifts]."
- **Conditional Faranka of the 9 (V04-Q5c):**
  - **Timestamp:** 00:02:58,200 → 00:03:04,500
  - **Arabic:** "شوف لاحظ هذا لعب البنت وخويك لعب الشايب وهذا تفرنك ولعب العشره"
  - **Literal:** "Watch — this [opp] played Q, your partner played K, **this [other opp] Faranka'd and played 10**, the trick came to you."
  - **Decision:** "تقدر تاكل بالتسعه ... هل تتفرلك وتاكل لا طبعا تاكل بالتسعه" (00:03:04 → 00:03:10)
    - Literal: "You can take with 9 ... do you Faranka and take? **No, of course take with 9**, because possibly the 9 will be lost on you."
- **Source-confidence:** **Sometimes** (speaker hedges throughout: "ممكن", "ولا يشيل التسعه").
- **Maps-to:** F-28.

---

### Exception #5 — F-29 J-dead "from a prior trick" (03:19–03:50)

#### V04-Q6 — F-29 verbatim, prior-trick semantics

- **Timestamp:** 00:03:19,200 → 00:03:24,420
- **Arabic verbatim (≤15 words):** "متى تتفرلك بالتسعه اذا الولد لعب من اول"
- **English literal:** "**When do you Faranka with the 9? If the J was played at the start.**"
- **Critical phrase:** "**من اول**" = literal "from the start" / "from before" / "at the beginning". This is **past-tense, prior-trick** semantics — *not* "the J counted as gone in the current trick".
- **Continuation (V04-Q6b):**
  - **Timestamp:** 00:03:24,420 → 00:03:28,369
  - **Arabic:** "خلاص المهم انت باقي لك التسعه هي اكبر ورقه موجوده في الحكم"
  - **Literal:** "Done — what matters is **you have the 9 left, it is the biggest card present in trump**."
- **Decision example (V04-Q6c):**
  - **Timestamp:** 00:03:28,369 → 00:03:34,560
  - **Arabic:** "تدق بالشايب يعني تتفرنك وما تلعب التسع"
  - **Literal:** "You hit [are knocked] by the K, meaning you Faranka and don't play the 9."
- **Source-confidence:** **Definite** wording; **Common** strategic confidence.
- **Maps-to:** F-29.
- **Implication for D-RT-03 S-2 / S-3:** Source language is **prior-trick** ("من اول"). Code's `S.HighestUnplayedRank("S")` returning "9" because JS is in `playedCardsThisRound` is *technically correct* if J was completed in a prior trick, but **does not correctly represent F-29 when JS was just played in the current in-flight trick**. Source supports a "completed-trick required" interpretation. D-RT-03 S-2's "DEFER" verdict is debatable; from source, the proper guard is `#(s.tricks or {}) > 0`.

---

### Type 2 / Side+Trump example (03:50–05:00)

#### V04-Q7 — Type-2 second-mover example (the speaker's main "no Faranka" case)

- **Timestamp:** 00:03:50,040 → 00:04:11,750
- **Arabic verbatim:** "اذا الخصوم كان مشتري حكم ... عندك ثمانيه عندك"
- **Literal:** "If **the opponents bought Hokm** ... you have 8, you have [...]" (worked example: opp leads 7 of side, partner shows nothing, you have 8 of side and another).
- **Decision (V04-Q7b):**
  - **Timestamp:** 00:04:11,760 → 00:04:16,500
  - **Arabic verbatim:** "**ما انصحك تتفرلك ابدا بالذات اذا الخصم مشتري حكم**"
  - **Literal:** "**I do not advise you to Faranka, ever, especially if the opponent bought Hokm.**"
- **Source-confidence:** **Definite**.
- **Maps-to:** F-32 (opp-bidder = strong NO Faranka).
- **Reasoning (V04-Q7c):**
  - **Arabic:** "اغلب احتماليه واحد من الخصم يدق احتماليه اكبر" (00:04:50)
  - **Literal:** "Most likely one of the opps will [come] hit [ruff] — bigger probability."

---

### Exception #6 — Bidder + A+K of side (Type 2) (05:00–05:25)

#### V04-Q8 — F-30 verbatim, bidder-only framing

- **Timestamp:** 00:05:00,479 → 00:05:09,290
- **Arabic verbatim (≤15 words):** "وده انت كنت مشتري حكم وعندك ريكا وعندك الشايب"
- **English literal:** "**And [if] you were the buyer of Hokm and [you] have Reka [the A] and [you] have the K**"
- **Glossary note:** "ريكا" / "الايكا" / "العكه" = the A (Ace). All variants appear in the corpus.
- **Favourability statement (V04-Q8b):**
  - **Arabic:** "حزيد نسبه التفمك اذا طمعت في كبوت او اذا خلصت الاحكام من ايادي اللاعبين"
  - **Literal:** "**The Faranka ratio rises if [you] covet Kabout, or if trumps are exhausted from the players' hands.**"
- **Source-confidence:** **Definite** wording; **Common** strategic confidence.
- **Bidder-team scope:** Phrasing is **bidder-only** ("**انت كنت مشتري**"). No partner-of-bidder generalisation in this passage.

---

### V04-Q9 — Generalisation passage (CRITICAL for Q4 of the prompt)

- **Timestamp:** 00:05:23,580 → 00:05:33,000
- **Arabic verbatim (≤15 words):** "**سواء انت مشتري او خويك او حتى لو الخصم**"
- **English literal:** "**Whether you are the buyer, or your partner, or even if the opponent [bought]**"
- **Wider quote (15+ words for context, NOT a verbatim extract):**
  - "لكن بصفه عامه في الحكم لا في الاستثناءات اللي قلناها فانت لازم تحسبها ولازم توازن ايش اقصد في كلامي هذا اقصد اذا باقي حكم هاس في يد خويك مثلا سواء انت مشتري او خويك او حتى لو الخصم والخصم هذا لعب ثمانيه ..."
  - English summary (≤30 words, displacive): General Hokm worst-case-planning advice; the bidder-team distinction is **dropped here** — the speaker explicitly says rule applies "**whether you are the buyer or your partner or even the opponent**".
- **Source-confidence:** **Definite** wording.
- **Implication for D-RT-03 S-1 and Q4 of prompt:**
  - **F-30's favourable triggers (V04-Q8) are bidder-only.**
  - **F-32 / Worst-case planning (V04-Q7, V04-Q9) is universal across seat-types.**
  - **Code's `contract.bidder == seat` predicate** for the F-30b path matches V04-Q8's literal wording (bidder-only). But:
    - V04-Q9 explicitly extends the *worst-case meta-rule* to "even if opp is buyer". This is the *anti-Faranka* direction (consistent with code's design).
    - Strictly **on the pro-Faranka side (F-30b), source supports bidder OR bidder-team**: the speaker's example at 05:33 onwards uses "خويك" (your partner) parallel to "you" — i.e., **bidder-team membership** is the natural unit, not strictly "you = bidder".
    - **Recommendation:** code's `contract.bidder == seat` is **over-tight by one seat** (excludes bidder's partner). Should be `R.TeamOf(contract.bidder) == R.TeamOf(seat)`. The transcript supports the team-level reading because the *strategic frame* of F-30b (extend Kabout via A+K of side) is a **team plan**, not a one-seat plan.
  - **D-RT-03 S-1 verdict supported by source.** F-16's "K of trump" cover requirement is *not stated in video 04*; v0.10.0 imported it from video 06's Sun anti-rule, where the threat model (opp A-of-suit punishes preserved K) is clear. In Hokm with both opps observed-void in trump (the F-30b precondition), that threat model is extinct. **Source-side, the F-16 veto has no Hokm mandate at all — the v0.10.2 carry-forward is over-restrictive.**

---

### Closing reasoning (05:33–end)

#### V04-Q10 — Worst-case planning meta-rule (F-33)

- **Timestamp:** 00:05:43,500 → 00:05:55,759
- **Arabic verbatim (≤15 words):** "حط اسوا الاحتمالات دائما"
- **English literal:** "**Always put [in mind] the worst possibilities**."
- **Repeated:** "دائما اسوء الاحتمالات" (00:05:55) — "always worst possibilities".
- **Source-confidence:** **Definite**.
- **Maps-to:** F-33.

#### V04-Q11 — Two-trick guarantee on take vs. 100% loss on Faranka (F-34, F-35)

- **Timestamp:** 00:05:59,160 → 00:06:25,610
- **Arabic verbatim:** "بعكس لو متفرغت راح الحلين هذه 100%"
- **Literal:** "**On the contrary, if [you] Faranka'd, both tricks go [are lost] 100%**."
- **Counterpart (V04-Q11b):**
  - **Arabic:** "تضمن حلتين بعكس لوكت ممكن تروح عليك"
  - **Literal:** "**[Take and you] guarantee two tricks; otherwise possibly [they all] go on you.**"
- **Source-confidence:** **Definite**.
- **Maps-to:** F-34, F-35.

#### V04-Q12 — Partner-with-trump fallback (F-36)

- **Timestamp:** 00:06:08,160 → 00:06:23,330
- **Arabic verbatim (≤15 words):** "حتى لو اخوي تجاوب راح تاكل وحلتين لانه معاه حكم"
- **English literal:** "Even if my brother [partner] doesn't respond, [you] still eat two tricks because he has trump."
- **Source-confidence:** **Common**.
- **Maps-to:** F-36.

#### V04-Q13 — Final reiteration

- **Timestamp:** 00:06:25,620 → 00:06:29,600
- **Arabic verbatim (≤15 words):** "دائما في الحكم حاول قدر المستطاع لا تتفر"
- **English literal:** "**Always in Hokm, try as much as possible not to Faranka.**"
- **Source-confidence:** **Definite**.
- **Maps-to:** F-23 reiteration; closes the video.

---

## Per-question detailed answers

### Q-D-RT-03 (D-RT-03 S-1: F-16 over-fires on Exception #4 when opps observed trump-void)

**Source verdict: D-RT-03 S-1 is correct. F-16 has no Hokm-Faranka mandate in video 04.**

- Video 04 contains **zero** mentions of "K of trump as cover card" or any equivalent.
- Video 04's exceptions (F-24 through F-30) are all hand-shape / seat-position predicates, **none of which require K of trump**:
  - F-24 / Type-3 cabotage: hand-shape = side-suit-only.
  - F-26 / Type-1 J-preservation: hand-shape = J of trump + side card; seat = right-opp holds 9.
  - F-27 / weak holding: hand-shape = =2 trumps.
  - F-28 / 9-mardoofa: hand-shape = 9 of trump + redundant trump.
  - F-29 / J-dead: hand-shape = 9 of trump + smaller trump; phase = J already played in prior trick.
  - F-30 / A+K of side: hand-shape = A+K of side suit; seat = bidder.
- The K of trump is **never** named as a cover requirement.
- F-16's source (video 06) is in **Sun-Faranka factor weighting** — the threat model is "opp holds A of led suit and punishes Faranka" (a side-suit / Sun threat). v0.10.0's X3 carried F-16 into Hokm as a generalised "K of trump backs up the withhold" rule — that's a code-side inference, not a source statement.
- When F-30b's predicate fires (`oppTrumpExhausted == true`, both opps observed trump-void via `Bot._memory[seat].void["S"]`), the *threat model that motivates F-16 is impossible by construction*. The opps cannot ruff with trump A because they have no trump.
- **Recommendation to D-RT-03's fix-Author:** Option (A) — scope F-16 to Triggers #2/#3 (where opp may still attack trump), skip on Trigger #4 (F-30b) — is **source-aligned**. Options (B)/(C) work but are less clean.

**Confidence:** **HIGH** that the F-16 veto is not source-mandated for the F-30b path.

---

### Q1 — F-14 transcription slip ("must Faranka" vs "must NOT Faranka")

**Not in video 04.**

- F-14 ("last-player anti-rule") is a video 06 rule. The transcription slip in question — "اذا كنت اخر لاعب انت لازم تتفرنك" vs the worked example showing taking — is a video 06 issue.
- Video 04 has **no occurrence** of "اخر لاعب" (last player). Verified via grep.
- This question is **out of scope** for an A-Src-01 video-04-only re-read.
- **Recommendation:** Defer to a separate A-Src-02 v06 re-extraction.

---

### Q2 — F-16 universality

**Video 04 makes no claim about F-16, either way.**

- F-16 ("if no K of trump, don't Faranka") originates from video 06 Sun-Faranka anti-rules.
- v0.10.0 X3 lifted this anti-rule into the Hokm code path on the rationale that "K of trump is the cover for a Hokm Faranka withhold". That rationale is a code-side inference, not a video 04 statement.
- **Source-side answer:** F-16 is **context-dependent (Sun anti-rule)** in its native source (video 06). Its universal application in Hokm at `Bot.lua:2964-2972` is **unsupported by video 04**.
- **D-RT-03 S-1's recommendation to scope F-16 narrowly is supported by source.**

---

### Q3 — F-29 (J-dead) "after J played" or "J counted as gone"

**Source language is unambiguously "after J played in a prior trick" (past-tense, completed).**

- Verbatim at 00:03:19,200: "متى تتفرلك بالتسعه يتفرج بالتسعه اذا الولد لعب من اول"
  - Literal: "When do you Faranka with the 9? With the 9 if the J **was played at the start** [from the beginning]."
- The phrase "**من اول**" (literally "from the start" / "from before") is **past-tense, prior-trick** semantics. It does **not** mean "is now gone" or "is currently being discarded".
- Continuation at 00:03:24: "خلاص المهم انت باقي لك التسعه" — "Done — what matters is you still have the 9". The word "خلاص" ("done / over") reinforces the "J already fell, it's over" reading.
- **Code's `S.HighestUnplayedRank("S")` returning "9" because `playedCardsThisRound["JS"] = true`** is technically true regardless of whether J fell in the current or a prior trick — but **source language requires a prior trick**.
- D-RT-03 S-2's "DEFER" verdict on same-trick J-fall is **defensible on frequency** but the source language **does favour a "completed-trick required" guard** (e.g., `#(s.tricks or {}) > 0`).
- **Confidence:** **HIGH** for prior-trick reading.

---

### Q4 — F-30 / Exception #4 — bidder-team OR bidder-only?

**Mixed:**

- **F-30's favourability statement (V04-Q8) is bidder-only**: "وده انت كنت مشتري حكم" = "and [if] you were the buyer of Hokm". The speaker does not extend this to "or your partner is the buyer" in this specific passage.
- **However**, V04-Q9 (00:05:23–05:33) gives the **generalised meta-frame** for *all Hokm Faranka decisions*: "سواء انت مشتري او خويك او حتى لو الخصم" = "**whether you are the buyer, or your partner, or even if the opponent [bought]**". This generalises the *worst-case planning* rule across all seats.
- F-30b's *strategic intent* — extending Kabout via A+K of side suit when trumps are out — is a **team-level plan**, not a single-seat plan. The bidder's partner can equally pursue Kabout extension.
- **Code's `contract.bidder == seat` is over-tight by one seat (excludes bidder's partner).**
- **Source-supported predicate:** `R.TeamOf(contract.bidder) == R.TeamOf(seat)`.
- **Confidence:** **MEDIUM-HIGH** — V04-Q8 is *literally* bidder-only, but V04-Q9 explicitly opens the door to bidder-team or wider; the strategic frame is team-level.

**D-RT-03's claim that the code's `contract.bidder == seat` is over-tight is supported by source.**

---

### Q5 — F-27 / Exception #2 — 2-trump-count gate verbatim

- **Verbatim at 00:02:24,660:** "**ممكن تتفرنك اذا كان عندك حكمين فقط**"
- **Literal:** "**You may Faranka if you have two trumps only.**"
- **Strictness:** "**حكمين فقط**" = "**two trumps only**" — strict-equality wording. The word "فقط" ("only / nothing else") is emphatic.
- **However**, the surrounding context is "**احكامك ضعيفه**" = "your trumps are weak" — which the speaker uses to *justify* the rule. The semantic core is "weak trumps justify the risk", and a hand-shape with 1 trump is even weaker than 2 trumps. So a **`≤2` predicate is defensible from intent**, but a **`=2` predicate is faithful to literal Arabic**.
- **Bidder-team scope:** Speaker's example uses "اشتريت حكم" (bidder), but the rule predicate is *hand-shape*, not seat. Source does not state "bidder-only".
- **Code's current predicate** at `Bot.lua` for F-27 should be reviewed: if `myTrumpCount == 2` the rule fires, **and** if `contract.bidder == seat`. The seat-gate is supported by example but **not the rule statement**. The transcript permits a non-bidder weak-trump seat to apply the rule.

---

### Q6 — Anti-rule rule 7 (opp Q-led trump + we hold J+8 rebut)

**Not in video 04.**

- Video 04 contains no rule mentioning "opp leads Q of trump" combined with "we have J+8" rebut.
- Video 04's only Q-of-trump mention is in the F-26 worked example where **the opp plays the Q in response to partner's cut** — the opposite seat-structure from "rule 7".
- Searched the v04 transcript exhaustively; the J+8 rebut pattern does not appear.
- This rule appears to be **either (a) extrapolated from video 06 Sun-Faranka factor weighting, or (b) addon-internal heuristic with no source basis, or (c) cited in another v04+ video out of scope here**.
- **Source-side verdict:** rule 7 is **single-track-A unsupported** for video 04. Its presence in the code at `Bot.lua:2974-2993` may be a v0.10.0 X3 inference, an artifact, or a reference to a different source.
- D-RT-03 S-5's verdict ("rule-7 is structurally dead code post-v0.10.0, harmless belt-and-suspenders") is **consistent with there being no v04 source mandate**. Without a source mandate, the dead-code can be safely removed; with one, it should be kept as a safety net.
- **Recommendation:** if rule 7 has a v06 or other-video source, label it. If not, remove or deprecate.

---

## Contradictions with v0.10.0 review's source_C_faranka.md

| # | Issue | v0.10.0 source_C says | This re-read says | Contradiction? |
|---|-------|-----------------------|-------------------|----------------|
| 1 | F-30 bidder-team scope | "**Explicitly bidder-only** (انت كنت مشتري حكم)" — line 298 | Bidder-only at the *favourable-trigger* sentence, but **V04-Q9 generalises across seats**, supporting bidder-team for the team-level Kabout intent. | **Partial.** Source_C correctly quotes V04-Q8, but **misses V04-Q9's generalisation** and the team-level strategic frame. Net: source_C's "bidder-only" is *quote-correct* but *strategy-incomplete*. |
| 2 | F-27 2-trump bidder-team scope | "Speaker example is bidder ('اشتريت حكم'), but the rule (weak trump holding) seems applicable to any seat" — line 272 | Same observation; agreed. | No. |
| 3 | F-29 prior-trick semantics | Quotes "اذا الولد لعب من اول" but doesn't emphasise prior-trick vs same-trick distinction | Same quote; **explicit prior-trick reading required**. | **Implicit.** Source_C's wording was loose enough to admit same-trick; this re-read pins it down. |
| 4 | F-26 worked example: "opp plays J" vs "opp plays Q" | "you bought Hokm, partner cuts with 7-of-trump → opp likely will play J not 9" — line 256 | Speaker says "**ما راح يلعب التسعه راح يلعب البنت**" = "won't play the 9, will play the **Q**" (البنت = Queen, not Jack). | **YES — small but real.** Source_C labels the seat-before-you's card as "J" but the speaker says "البنت" = Q. F-26's worked example is opp-plays-Q, not opp-plays-J. The rule's *predicate* ("9 must be with right-opp") is unaffected; only the worked-example labelling. |
| 5 | F-16 universal Hokm application | Source_C lists F-16 in the "Sun-Faranka anti-rules" section (correct) and does **not** advocate Hokm application — line 174 | Confirmed. v0.10.0 X3's import of F-16 into Hokm code (`Bot.lua:2964-2972`) **is not supported by source_C** either; it's a code-side inference. | **No contradiction with source_C, but source_C does not endorse Hokm-F-16. v0.10.2 code's universality is unsupported.** |

**Net:** No major source contradictions. One small worked-example labelling fix (J → Q in F-26). Several places where source_C was *quote-correct* but *strategy-incomplete* — flagged.

---

## Summary table for cross-reference

| Rule | v04 timestamp | Verbatim Arabic key phrase | Bidder-team scope | Source-confidence |
|------|---------------|----------------------------|-------------------|-------------------|
| F-23 default-NO | 00:00:09 | "بشكل عام الافضل لا تترن في الحكم" | universal | Definite |
| F-24 Type-3 cabotage | 00:01:20 | "تخسرها على الخصم ... في النوع الثالث فقط" | implicit bidder-team (Kabout extension) | Definite |
| F-25 hard-stop on Type 1/2 | 00:01:30 | "اما غير كذا ما انصحك ابدا" | universal | Definite |
| F-26 J-preservation | 00:02:04 | "والتسعه لازم تكون للاعب اللي قبلك" | example=bidder, rule=hand-shape | Definite |
| F-27 weak 2-trump | 00:02:24 | "**ممكن تتفرنك اذا كان عندك حكمين فقط**" | example=bidder, rule=hand-shape | Definite |
| F-28 9-mardoofa | 00:02:38 | "افترض انه عندي التسعه والتسعه مردوفه معايا" | universal | Sometimes |
| F-29 J-dead | 00:03:19 | "**اذا الولد لعب من اول**" (prior trick) | universal | Definite |
| F-30 A+K of side, bidder | 00:05:00 | "**وده انت كنت مشتري حكم وعندك ريكا وعندك الشايب**" | bidder-only literal, bidder-team strategic | Definite |
| F-32 opp-bidder NO | 00:04:11 | "**ما انصحك تتفرلك ابدا بالذات اذا الخصم مشتري حكم**" | opp-bidder = NO | Definite |
| F-33 worst-case meta | 00:05:43 | "**حط اسوا الاحتمالات دائما**" | universal | Definite |
| F-34 100% loss | 00:05:59 | "بعكس لو متفرغت راح الحلين هذه 100%" | universal | Definite |
| F-35 take = guarantee 2 | 00:06:08 | "تضمن حلتين بعكس لوكت ممكن تروح عليك" | universal | Definite |
| F-36 partner-trump fallback | 00:06:08 | "حتى لو اخوي تجاوب راح تاكل وحلتين لانه معاه حكم" | universal | Common |
| F-23 reiteration | 00:06:25 | "دائما في الحكم حاول قدر المستطاع لا تتفر" | universal | Definite |
| **F-14 (Q1)** | **NOT IN V04** | — | — | — |
| **F-16 (Q2)** | **NOT IN V04** | — | (v06-only Sun anti-rule) | — |
| **rule 7 (Q6)** | **NOT IN V04** | — | — | — |

---

## Recommendations to subsequent tracks

1. **Track-B / code fixes (`Bot.lua:2964-2972`)** — accept D-RT-03 S-1's Option (A): scope F-16 to Triggers #2/#3 only; skip on F-30b. Source-aligned per Q2 + Q-D-RT-03 above.
2. **Track-B / code fixes (`Bot.lua` F-30 predicate)** — relax `contract.bidder == seat` to `R.TeamOf(contract.bidder) == R.TeamOf(seat)` per Q4. Source supports bidder-team for the team-level Kabout intent.
3. **Track-B / code fixes (`Bot.lua` F-27 predicate)** — review whether bidder-only seat-gate is necessary; source permits hand-shape-only predicate (=2 trumps + J-adjacent + side card).
4. **Track-B / code fixes (`Bot.lua` F-29)** — consider adding `#(s.tricks or {}) > 0` guard to enforce prior-trick semantics per Q3.
5. **Track-A follow-up** — re-extract video 06 (A-Src-02) to re-verify F-14 transcription slip and F-16 Sun-Faranka native form, since neither is in v04.
6. **Track-A follow-up** — locate "rule 7" (Q-led + J+8) source. If no source exists, deprecate `Bot.lua:2974-2993` per D-RT-03 S-5's NIT verdict.
7. **Track-C / xref** — update v0.10.0 source_C_faranka.md F-26 worked example: opp plays Q (البنت), not J (الولد). Small fix; the rule predicate is unchanged.
