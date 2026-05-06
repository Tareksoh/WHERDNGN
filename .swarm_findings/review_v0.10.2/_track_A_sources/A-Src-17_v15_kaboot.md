# A-Src-17 — Video #15 "Al-Kaboot (detailed)"

**Source:** `docs/strategy/_transcripts/PPW4uSWTirA_15_kaboot_detailed.ar-orig.srt`
**Title in playlist:** Al-Kaboot — detailed
**Total runtime:** ~14:17
**Extraction scope:** Phase-1 reconciliation of bonus values, Strategic break-Kaboot-to-Double, Trick-3 early Kaboot recognition, Defender sandbag-Qaid vs bidder delay-Qaid timing, Trick-1 leader requirement, Pre-conditions to claim Kaboot, Reverse Kaboot Sun-only, Reverse Kaboot Ace-lead requirement.

---

## Q1 — Kaboot bonus values (Hokm 25, Sun 44 *raw / game points*)

**Verbatim AR (Sun, ≤15 words):**
> «تاخذ في الصن 44 نقطه الحين نقاط الصن كامله 26 بدون مشاريع»

**Verbatim AR (Hokm, ≤15 words):**
> «وفي الحكم اذا جبت كبوت راح تاخذ 25 نقطه»

**English:**
> "In Sun you take 44 points — and Sun's full hand is 26 without projects"
> "And in Hokm if you bring a Kaboot you take 25 points"

**Timestamp:** 02:43–02:54 (subtitles 109–117)
**Confidence:** **HIGH** — speaker states the numbers explicitly twice and contextualizes against the no-Kaboot baseline (Sun 26, Hokm 16) at the *raw / game-point* layer.

**Reconciliation note for Phase 1:**
The user's swarm-finding "250/220 raw" does **NOT** match this video. Speaker's raw values are **44 (Sun)** and **25 (Hokm)** in the same units he calls "Sun=26, Hokm=16 without projects" — i.e. these are the post-divide game-points, NOT raw card points. The 250/220 figures from a prior reconcile attempt appear to multiply through Sun's ×2 and apply something else; this video is unambiguous that Kaboot = 44 / 25 in **the same point-units used to track the running game score**.

Supplementary verbatim (2nd pass at 02:51, ≤15 words):
> «نقاط الحكم 16 لكن الكبوت راح تاخذ 25 اعلى»
> "Hokm's points are 16 but for Kaboot you'll take 25 higher"

---

## Q2 — Strategic break-Kaboot-to-Double (Sun double 52 > Sun Kaboot 44)

**Verbatim AR (≤15 words):**
> «دبل الصن ب 52 نقطه ... واذا جبت كبوت راح تاخذ 44 نقطه»

**English:**
> "Doubled Sun is 52 points… and if you bring a Kaboot you'd take 44 points"

**Timestamp:** 04:06–04:14 (subtitles 167–171)
**Confidence:** **HIGH**

**Tactical recommendation verbatim (≤15 words):**
> «راح تعطي الخصم حله او حلتين بس عشان يكسرون كبوت»

**English:**
> "You'll give the opponent one trick or two just so they break the Kaboot"

**Timestamp:** 04:46–04:48 (subtitles 197–199)

**Doctrine-statement verbatim (≤15 words):**
> «فعشان كذا في ناس تدبل الكبوت»

**English:**
> "And that's why some people 'double' the Kaboot [intentionally break their own]"

**Timestamp:** 05:01–05:03 (subtitle 211)

**Hokm parallel verbatim (≤15 words):**
> «دبل الحكم ب 32 اكثر من الكبوت الكبوت ب 25»

**English:**
> "Doubled Hokm is 32, more than the Kaboot at 25"

**Timestamp:** 05:06–05:09 (subtitles 213–215)
**Confidence:** **HIGH** — speaker explicitly endorses the trade for Sun-doubled (52>44) AND Hokm-doubled (32>25); "and even more for triple/quadruple/Gahwa-level multipliers."

**Note on triples+:** speaker continues "اذا كان 3 اللعب او اذا كان ف اكثر واكثر" — "if it's 3× or even more and more" — so the break-Kaboot-to-keep-multiplier doctrine scales with the multiplier, not just doubles. Tactic applies whenever multiplier × baseline > 44 (Sun) / 25 (Hokm).

---

## Q3 — Trick-3 / early Kaboot recognition (bot currently triggers at trick 8)

**Verbatim AR (≤15 words):**
> «وخصوصا لو كانت بدايه اللعب يعني لسه ثاني اكله مثلا وانت شايف ورقك»

**English:**
> "And especially if it's the start of the round — say still only the second trick — and you can see your cards"

**Timestamp:** 13:27–13:33 (subtitles 599–602)
**Confidence:** **HIGH** — speaker's explicit framing for "the start" (بدايه اللعب) with a concrete example of *trick 2*, not trick 3.

**Surrounding context verbatim (≤15 words):**
> «وقام واحد منهم قطع سواء متعمد او غير متعمد حاول قدر مستطاع ما تقيد لين اخر حله»

**English:**
> "And one of them ruffed [cut/trump], deliberate or not — try as much as you can not to take the trick until the last hand"

**Timestamp:** 13:33–13:40 (subtitles 603–608)

**Operational rule verbatim (≤15 words):**
> «حد القيد عندك لين ما تبدا تحسب»

**English:**
> "Your right to refuse-the-Qaid lasts until you start to count [the running score]"

**Timestamp:** 13:42–13:45 (subtitles 609–611)

**Implication for `Bot.PickSWA` / Al-Kaboot pursuit:**
The bot's current trick-8-only trigger is **far too late** per this video. Speaker says recognition can/should occur as early as **trick 2** when:
1. you can see your hand is sweep-capable, AND
2. an opponent has cut a side suit (signaling they suspect Kaboot).

The "until you start to count" phrasing implies the entire pre-counting window (when the no-Kaboot game-point delta hasn't crystallized) is open for switching from "take Qaid" to "request Kaboot" — practically tricks 1–7. The bot should evaluate Kaboot pursuit / Qaid refusal each trick from trick-2 onward.

---

## Q4 — Defender sandbag-Qaid vs bidder delay-Qaid endgame timing

### Defender sandbag-Qaid (sabotage Kaboot by deliberately ruffing wrong)

**Verbatim AR (≤15 words):**
> «خليني اقيد على اي شيء وانا عارف انه الجيد حقي غلط»

**English:**
> "Let me 'qaid' on anything — I know my Qaid is wrong [deliberately]"

**Timestamp:** 07:51–07:54 (subtitles 341–343)
**Confidence:** **HIGH**

**Mechanism verbatim (≤15 words):**
> «يتقيد علي وينقلب علي القيد وياخذون 26 بدل ما ياخذون 44»

**English:**
> "[Bidder] qaids on me and the qaid flips on me, they take 26 instead of 44"

**Timestamp:** 07:54–08:00 (subtitles 345–347)
**Confidence:** **HIGH** — *explicit numerical comparison* 26 vs 44 (Sun no-Kaboot vs Sun Kaboot, raw game-points).

**Hokm parallel verbatim (≤15 words):**
> «الحكم ياخذون 16 بدال ما ياخذون 25»

**English:**
> "[In] Hokm they take 16 instead of 25"

**Timestamp:** 08:00–08:03 (subtitles 347–349)

### Bidder delay-Qaid response (refuse the bait)

**Verbatim AR (≤15 words):**
> «في هذه الحاله ما تقيد عليه الافضل تطلب كبوت»

**English:**
> "In this case don't qaid on him — best to claim Kaboot"

**Timestamp:** 13:14–13:17 (subtitles 587–589)
**Confidence:** **HIGH**

**Counter-defense verbatim (≤15 words):**
> «هو يبغاك تقيد عليه ... سو الحركه دي عشان تقيد عليه وتاخذ 26 بدل ما تاخذ 44»

**English:**
> "He wants you to qaid on him… he made this move so you'd qaid and take 26 instead of 44"

**Timestamp:** 13:17–13:23 (subtitles 590–593)

**Endgame-window summary verbatim (≤15 words):**
> «حاول لا تقيد لين ما يخرب الكبوت»

**English:**
> "Try not to qaid until the Kaboot breaks [or proves itself]"

**Timestamp:** 13:55–13:58 (subtitles 621–622)

**TL;DR recommendation verbatim (≤15 words):**
> «اذا رايح كبوت خلاص خذ الكبوت احسن لك من القد»

**English:**
> "If it's heading for Kaboot, take the Kaboot — better than the Qaid for you"

**Timestamp:** 14:07–14:10 (subtitles 629–631)

**Mapping to G15-14 → G15-19:**
The video supports a *single-window* doctrine: from the moment a defender's suspicious ruff (دفاع متعمد) appears, the bidder MUST defer Qaid-claim until either (a) the last trick crystallizes the Kaboot or (b) the defender's sandbag is exposed and you can request Kaboot directly. **There is no separate "early-Qaid" timing for the bidder** — the bidder's only correct timings are: claim Kaboot when sweep is provable, OR fall back to normal scoring. The defender's *sandbag-Qaid* IS an early move (often trick 2-3), but the bidder's *delay-Qaid* is a hold-for-the-whole-round response.

**Confidence on G-numbering:** **MEDIUM** — without seeing G15-14..G15-19 doc IDs, I can only assert the *substantive content* aligns; mapping which sub-claim each G-bullet corresponds to is for the consumer to do.

---

## Q5 — Trick-1 leader = bidder team required for Kaboot? Or any team can sweep?

**Verbatim AR (≤15 words):**
> «الكبوت اما يكون من يد او من يدين يعني اما يكون على يد لاعب واحد»

**English:**
> "The Kaboot is either from one hand or from two — either by a single player or [shared between partners]"

**Timestamp:** 00:40–00:45 (subtitles 27–31)
**Confidence:** **HIGH**

**Continuation verbatim (≤15 words):**
> «يكون على يدين ما حيفرق لكن اللهم متعه اللعب لما يكون على يدين»

**English:**
> "It's on both [partners' hands], doesn't matter — except the enjoyment is greater when it's on both"

**Timestamp:** 00:50–00:54 (subtitles 35–37)

**Verdict:** **NO trick-1 leader requirement for normal Kaboot.** The video is explicit: a Kaboot is *any* sweep where the **team** wins all 8 tricks. The lead can pass back and forth between partners ("رحت لخوي... رجع لي بعدين رحت له"). The only constraint is that **NO** opponent ever wins a trick.

**Note re Reverse Kaboot:** The trick-1 / lead requirement appears in **Reverse Kaboot** (Q7-Q8 below), not standard Kaboot.

---

## Q6 — Pre-conditions to claim Kaboot

Direct pre-conditions extracted from the video (verbatim ≤15 words each):

**(a) Team sweeps all 8 tricks:**
> «انك راح تاكل جميع الاكلات او جميع الحلات في اللعب»
"You will eat every trick or every trick in the round" — 00:11–00:17 (subtitles 9–11)

**(b) Opponents win zero tricks:**
> «والخصم ماله ولا حله»
"And the opponent has not even one trick" — 00:33–00:36 (subtitle 25)

**(c) For *claiming* the Kaboot before all 8 are played, you must be able to demonstrate the sweep:**
> «من حقك تطلب كبوت تقول ما ابغى قد اللعب كبوت طبعا لازم تشرح»
"You have the right to request Kaboot [and refuse the Qaid] — but you must demonstrate [your hand]" — 08:50–08:55 (subtitles 388–391)
**Timestamp:** 08:50–08:55
**Confidence:** **HIGH**

**(d) Demonstration must be valid (no missed cuts that opponent has):**
The video at 09:02–09:14 (subtitles 397–407) gives the corner case — if the sweep depends on the *partner* having a specific card and the partner doesn't, the Kaboot claim *fails* and Qaid is reversed onto the claimant ("سوا خاطئ" — invalid SWA). This is the cross-link to video #35 (SWA permission flow).

**(e) Bonus stacks with multipliers via REPLACEMENT, not multiplication:**
> «اذا جا كبوت واللعب دبل ... راح تاخذ نقاط الكبوت ما راح تاخذ الدبل»
"If Kaboot comes and play is doubled… you take Kaboot points, not the double" — 04:01–04:06 (subtitles 161–166)
**Timestamp:** 04:01–04:06
**Confidence:** **HIGH**

**(f) Opponent's projects (Sirah/Bel/100) transfer to claimant if opponent was bidder:**
> «لو الخصم مشتري وجبت عليه كبوت راح تاخذ مشاريعه»
"If the opponent is bidder and you Kaboot him, you take his projects"
**Timestamp:** 03:46–03:51 (subtitles 152–155)
**Confidence:** **HIGH**

---

## Q7 — Reverse Kaboot is Sun-only

**Verbatim AR (≤15 words):**
> «الكبوت المقلوب في الصن وليس في الحكم»

**English:**
> "Reverse Kaboot is in Sun and NOT in Hokm"

**Timestamp:** 05:32–05:34 (subtitles 233–234)
**Confidence:** **HIGH** — single, unambiguous, declarative.

**Bonus value verbatim (≤15 words):**
> «الكبوت المقلوب نقاطه 88 يعني دبل الكبوت العادي»

**English:**
> "Reverse Kaboot's points are 88 — i.e. double the normal Kaboot"

**Timestamp:** 05:36–05:42 (subtitles 237–239)

**Variant-acknowledgement verbatim (≤15 words):**
> «بعض الناس يعتبر الكبوت المقلوب كانه الكبوت العادي يعني ب 44»

**English:**
> "Some people treat Reverse Kaboot as if it were normal Kaboot — i.e. 44"

**Timestamp:** 05:42–05:48 (subtitles 240–243)

**Recommendation:** code should default to **88** (the canonical value) but allow a session-config override for tables that play it as 44.

---

## Q8 — Reverse Kaboot: Ace-lead requirement (must be Aka)

**Verbatim AR (≤15 words):**
> «اغلب الناس تقول لازم الارض تكون اكا يعني المشترى يكون اكا»

**English:**
> "Most people say the lead [first card played] must be Aka — i.e. the bid-on suit must be Aka"

**Timestamp:** 06:24–06:30 (subtitles 273–277)
**Confidence:** **HIGH** for the *majority-rule* version.

**Mechanism verbatim (≤15 words):**
> «الخصم اللي راح يشتري الاكه طبعا ما راح يلعبها»

**English:**
> "The opponent [bidder] who would 'buy' [win] the Aka of course won't play it"

**Timestamp:** 06:30–06:34 (subtitles 279–281)

**Variant verbatim (≤15 words):**
> «في ناس يقول لا مش شرط الورقه تكون اكا»

**English:**
> "Some people say no — it's not a condition that the card be Aka"

**Timestamp:** 06:50–06:53 (subtitles 295–296)

**Speaker's normative stance verbatim (≤15 words):**
> «ما قد شفت ناس يلعبونه زي كذا»

**English:**
> "I've never seen people play it that way [the variant]"

**Timestamp:** 07:18–07:20 (subtitles 315–316)
**Confidence:** **HIGH** — speaker's lived-experience endorsement of the Aka-required version.

**Pre-conditions for Reverse Kaboot (composite, all from this video):**
1. Contract is **Sun** (not Hokm). [05:32]
2. **Bidder is the opposing team** — your team did NOT bid. [05:53–05:58 sub 250]
3. The lead is on the bidder's side — i.e. the bidder or his partner plays first. [06:01–06:15 sub 255–265]
4. The first card led is the **Aka of the bid suit** (majority rule; minority rule = any card). [06:24–07:00]
5. Your team then sweeps all 8 tricks.

**Cross-confirmation with #16:** flagged for the consumer; this extraction does NOT include #16.

---

## Cross-reference summary table

| # | Topic | AR-source line range | Timestamp | Confidence |
|---|---|---|---|---|
| 1 | Sun Kaboot = 44 | sub 109 | 02:43 | HIGH |
| 1 | Hokm Kaboot = 25 | sub 115 | 02:54 | HIGH |
| 2 | Sun double = 52 > Kaboot 44 | sub 167–171 | 04:09 | HIGH |
| 2 | Hokm double = 32 > Kaboot 25 | sub 213–215 | 05:06 | HIGH |
| 2 | Doctrine: break own Kaboot to keep multiplier | sub 211 | 05:01 | HIGH |
| 3 | Early recognition = trick 2 | sub 599–602 | 13:27 | HIGH |
| 3 | "until last trick" hold-Qaid rule | sub 605–611 | 13:38 | HIGH |
| 4 | Defender sandbag-Qaid mechanism | sub 341–349 | 07:51 | HIGH |
| 4 | Bidder delay-Qaid response | sub 587–593 | 13:14 | HIGH |
| 5 | NO trick-1-leader requirement (any team can sweep) | sub 27–37 | 00:40 | HIGH |
| 6 | Pre-conditions list | (multiple) | (multiple) | HIGH |
| 7 | Reverse Kaboot = Sun only | sub 233–234 | 05:32 | HIGH |
| 7 | Reverse Kaboot = 88 (canon) | sub 237–239 | 05:36 | HIGH |
| 8 | Ace-lead required (majority rule) | sub 273–277 | 06:24 | HIGH |
| 8 | Speaker endorses Ace-lead variant | sub 315–316 | 07:18 | HIGH |

---

## Reconciliation flags for v0.10.2 review

1. **Phase-1 250/220 figure is NOT in this video.** Speaker uses 44 (Sun) / 25 (Hokm) consistently, in the same units used for the running game score. Whoever reconciled to 250/220 likely confused raw card-points (×30 or ×Sun-multiplier) with game-points. **Recommend re-checking against video #41 (Sun basics).**

2. **Bot trick-8-only trigger contradicts video.** Speaker explicitly says trick-2 awareness, hold-Qaid through "last trick." Bot should at minimum start evaluating Kaboot pursuit at trick 2, with the canonical "claim only when provable" guard.

3. **Reverse Kaboot Ace-lead is a *table convention*** with a documented variant. Code should expose this as a config flag (e.g. `K.REVERSE_KABOOT_ACE_REQUIRED`, default `true`).

4. **Reverse Kaboot bonus 88 is canonical** but 44-variant exists. Same config-flag treatment recommended (`K.REVERSE_KABOOT_BONUS`, default `88`).
