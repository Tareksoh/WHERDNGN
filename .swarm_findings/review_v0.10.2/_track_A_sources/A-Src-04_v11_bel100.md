# A-Src-04: Video #11 — Bel-100 (Sun Double) Legality Rule

**Source transcript:** `docs/strategy/_transcripts/21fN1IEm5Xk_11_bel_beginners.ar-orig.srt`
**Video:** `21fN1IEm5Xk` — "الدبل في البلوت للمبتدئين" (Doubling in Baloot for Beginners)
**Audit context:** v0.10.0 R1 score-split fix re-verification + D-RT-22 (Net._OnDouble defender-seat gate) finding under audit.
**Re-extracted:** 2026-05-05

---

## Reference frame established by v0.10.0 R1

The R1 reaudit fixed the predicate to:

```
caller.cum ≤ 100  AND  opposite.cum ≥ 101
```

— score-split, **role-irrelevant** (no bidder/defender distinction), evaluated at the moment the Bel call is made.

D-RT-22 flagged that while `R.CanBel` admits this rule correctly, `Net._OnDouble` (and the UI gate that feeds it) only fires for **defender-seat** players. So the **bidder-trailing** case (bidder team at ≤100, defender team at ≥101) is **legal per `R.CanBel` but unreachable in flight** — the bidder team never gets a Bel button. This creates a 60s AFK regression when the rare bidder-trailing-Sun comes up.

The question for this re-extract: **does the source video support role-irrelevance, or does the speaker actually frame Bel-in-Sun as defender-only?**

---

## Q1. Verbatim Arabic @ 00:07:25–00:07:31 (Bel-100 rule, score-split)

**Timestamp range covered by SRT lines 240–247.**

### Verbatim Arabic (≤15 words, segmented to fit budget)

> "في الصن لازم يكون فريق 100 نقطه او اعلى والفريق الثاني يكون اقل من 100"

**Source lines 240–245** @ 00:07:21,900 → 00:07:31,730.

### English translation

> "In Sun, one team must be at 100 points or above, and the other team must be below 100."

### Confirmation

CONFIRMED verbatim. Quote matches the SRT character-for-character.

### Confidence

**HIGH.** This is the canonical statement of the rule, delivered cleanly with no qualification or hedging. The speaker uses the abstract framing "فريق ... والفريق الثاني" ("a team ... and the other team") — not "the bidder" / "the defender."

---

## Q2. Verbatim Arabic @ 00:07:38–00:07:43 (which team can Bel)

**Timestamp range covered by SRT lines 249–253.**

### Verbatim Arabic (≤15 words)

> "الفريق اللي اقل من 100 لوحه حقيقيه يدبل لكن الفريق اللي فوق الميه ما يدبل"

**Source lines 249–253** @ 00:07:34,979 → 00:07:43,550.

### English translation

> "The team that is below 100 — it has a genuine board (right) to Bel; but the team above 100, [it] does not Bel."

(Note: "لوحه حقيقيه" — literally "true board" — is colloquial for "genuine right / legitimate ground.")

### Continuation @ 00:07:43,550 → 00:07:47,210 (line 253–255)

> "في الصن اتكلم ماله حقا انه يدبل بعكس الحكم"

**English:** "In Sun specifically, [the >100 team] does not have the right to Bel — opposite of Hokm."

### Confirmation

CONFIRMED verbatim.

### Confidence

**HIGH.** The two clauses bracket the rule symmetrically: <100 team CAN Bel; >100 team CANNOT. Same framing as Q1 — purely score-based, no role qualifier.

---

## Q3. Role-irrelevance — speaker's framing

### Verdict

**Role-irrelevant per the speaker's own words.** The speaker NEVER mentions "bidder" (المشتري) or "defender" (الخصم) when stating the Sun-Bel rule.

### Supporting evidence

**Q1 verbatim:** "فريق 100 نقطه او اعلى والفريق الثاني يكون اقل من 100" — abstract "team A / team B" language.

**Q2 verbatim:** "الفريق اللي اقل من 100 ... الفريق اللي فوق الميه" — pure score predicate.

**Lines 256–259** @ 00:07:47,210 → 00:07:52,490 (Hokm-comparison, where the speaker EXPLICITLY mentions roles):

> "الحكم مفتوح في الدبل سواء كنت اعلى من 100 او اقل او كنت اعلم الفريق الاخر او اقل منه"

**English:** "Hokm is open for Bel — whether you're above 100 or below, whether you're [scored] above the other team or below them."

The speaker's foil here is illustrative: when he wants to say role/score doesn't matter (Hokm case), he uses "كنت" (you-were) — second person, score-comparing. He does NOT say "whether you bid or defended." So even in the *contrast* case, he frames everything as score-based, not role-based.

**Critical: there is NO sentence in the entire transcript where the speaker conditions Sun-Bel on bidder vs defender role.** The rule is *purely* a score predicate.

### Confidence

**VERY HIGH.** The speaker had multiple opportunities to add a role qualifier and never did. The earlier Hokm section (lines 87–105 @ 00:02:04–00:02:31) does discuss bidder/defender flow ("الخصم واحد منهم قال دبل" — "one of the defenders said Bel"), so the speaker is *capable* of framing things in role terms when he wants to. He chose not to for the Sun-Bel rule.

---

## Q4. Bidder-trailing case (THE D-RT-22 question)

**Question:** When the bidder team is at <100 and the defender team is at ≥101, can the bidder team Bel its own contract?

### Verdict

**NOT EXPLICITLY ADDRESSED — but the speaker's own example uses second-person addressed-to-the-bidder framing, which strongly implies YES.**

### The example @ 00:07:31,730 → 00:07:34,969 (lines 245–248)

> "مثلا لو انت نقاطك 60 ونقاط الفريق الاخر فوق الميه يعني كانت 130 او 140 او 100"

**English:** "For example, if YOUR points are 60, and the other team's points are above 100 — say 130 or 140 or 100..."

### Critical context

This example sits in the **Sun contract** section (transitioned at line 209 @ 00:06:42 — "بالنسبه للصين الصين جدا بسيط"). The speaker's pedagogical pattern throughout the video is to address the listener as the prospective bidder/buyer:

- Line 51 @ 00:01:14: "لو افترضنا انه انت الحين الموزع" ("suppose you are now the dealer")
- Line 91 @ 00:02:13: "فلو هذا اشترى حكم" ("if [your partner] bought Hokm")
- Line 225 @ 00:06:58: "لو مثلا انت جيت اشتريت هذه صن" ("for example, if you came and bought this as Sun")

So the natural reading of "لو انت نقاطك 60" in context is: **"if YOU (the player thinking about whether to call Bel) are at 60, and the opposing team is above 100, you have the right to Bel."** The speaker does NOT distinguish whether "you" are the buyer or a defender — and given that the immediately preceding example (line 225) explicitly cast "you" as the Sun buyer, the same "you" continuing into the Bel-rule example would include the bidder-trailing case.

### Verbatim that comes closest to bidder-trailing endorsement

> "لو انت نقاطك 60 ونقاط الفريق الاخر فوق الميه ... يدبل"

(Lines 245–251 @ 00:07:31,730 → 00:07:41,210, stitched.)

**English:** "If your points are 60 and the other team's points are above 100 ... [your team] Bels."

**The speaker imposes no role condition on "you."** The bidder-trailing case (you bought Sun, then your team is at 60 and theirs is at 130) falls inside this rule by direct application.

### What the speaker does NOT say

- He does NOT say "only the defender team can Bel in Sun."
- He does NOT say "the buyer cannot Bel his own contract."
- He does NOT say "Bel is only by the team that did not buy."

If the rule were genuinely defender-only, this is the moment a teaching video for beginners would say so — and he doesn't.

### D-RT-22 implication

**The source supports `R.CanBel`'s current predicate (role-irrelevant). It does NOT support `Net._OnDouble`'s defender-seat gate.** The defender-seat gate is an implementation artifact, not a Saudi-rules requirement. D-RT-22's regression (60s AFK on bidder-trailing-Sun) is a real bug per the source video.

### Confidence

**MEDIUM-HIGH on the inference, HIGH on what's not said.** The speaker doesn't *explicitly* walk through "buyer at 60, defender at 130, buyer Bels" — that specific scenario is never narrated. But:
- the rule statement is purely score-based,
- the example pronoun "you" was the Sun-buyer two sentences earlier,
- the speaker explicitly contrasts with Hokm using score-comparison language ("whether you're above 100 or below"),
- nowhere does the speaker introduce a role qualifier.

A defender-only reading would require reading a constraint INTO the source that isn't there.

---

## Q5. Round-1 anti-grief rule

### Verbatim Arabic (≤15 words)

> "ممكن بعض الجلسات ما تسمح في بدايه اللعب ... ممكن يمنعون الدبل"

**Source lines 259–263** @ 00:07:52,490 → 00:07:57,529.

### Full passage

> "الا ممكن بعض الجلسات ما تسمح في بدايه اللعب يعني لو كانت الصكه لسه توهكم بادئين ممكن يمنعون الدبر [الدبل]"

(Note: SRT line 263 reads "الدبر" — almost certainly a transcription typo for "الدبل" given context. SRT line 261 reads "الصقر" which should be "الصكه" — the round/hand. Both appear to be ASR artifacts.)

### English translation

> "Except — some sessions don't allow [Bel] at the very start of play, meaning if the round (al-sakka) just barely started, they may forbid Bel."

### Confirmation

CONFIRMED — speaker frames this as a **session-house-rule**, NOT a universal Saudi rule. "ممكن بعض الجلسات" = "some sessions might [forbid it]."

### Confidence

**HIGH.** Wording is unambiguous about it being optional/session-dependent.

---

## Q6. Cards-revealed lockout (kashf al-waraq)

### Verbatim Arabic (≤15 words)

> "اذا كشفت الورق خلاص وما قلت دبل ممنوع تدبل"

**Source lines 71–73** @ 00:01:41,109 → 00:01:44,939.

### Full immediate context (lines 67–83 @ 00:01:35–00:01:58)

The lockout window is described in two parts:

**Part 1 — primary statement (lines 71–75 @ 00:01:41–00:01:50):**
> "اذا كشفت الورق خلاص وما قلت دبل ممنوع تدبل لكن اذا ما كشفت الورق حتى لو وزعلك ما كشفت الورق السياق هذا واللي راح يسوقك راح يكون عندك فرصه دبل"

**English:** "If you've revealed [your] cards, that's it — and you didn't say Bel — you're forbidden to Bel. But if you haven't revealed your cards, even if [the dealer] dealt to you and you haven't revealed [yet], in this context and the one driving you [next], you'll have a chance to Bel."

**Part 2 — alternate house-rule (lines 77–83 @ 00:01:52–00:02:01):**
> "وفي ناس يقولوا لا لو اي لاعب من هذول اللاعبين كشف ورق السياق هنا ممنوع انك تدبل في النهايه على حسب الجلسه"

**English:** "And there are people who say no — if ANY player from these players has revealed cards-of-context [the kicker pile], here it's forbidden for you to Bel at the end. So it depends on the session."

### Confirmation

CONFIRMED. The lockout is **per-session-configurable** at the boundary: strict-house = any player's reveal locks the table; lenient-house = only your own reveal locks you.

### Confidence

**HIGH.** Both variants are explicit.

---

## Q7. "Maqfūl" under even-multiplier Hokm

### Verbatim Arabic (≤15 words)

> "اللعب هنا راح يكون مقفول ... يعني ما تربيعي بحكم"

**Source lines 129–131** @ 00:04:06,720 → 00:04:14,159.

### Full passage (lines 123–149)

The speaker explains:
1. Hokm + Bel (×2) or Hokm + Four (×4) — "اللعب هنا راح يكون مقفول" — the play is "closed" / "locked." [Lines 123–129 @ 00:04:01–00:04:09]
2. "مقفول يعني ما تربيعي بحكم" — "Maqfūl means you don't square-with-trump." [Line 131 @ 00:04:11]
3. Mechanic: at the start, deal the remaining cards and reveal hands normally; the trump-leader does not get to "ribba'" (square / cut) using trump. [Lines 133–149 @ 00:04:14–00:05:22]
4. Operationally: "ما يلعب اول ورقه في الارض حكم اي لاعب باختصار يلعب اي شيء غير الحكم الا اذا باقي له حكم فقط في يده" — "He must NOT play trump as the first card to the floor; any player, in short, plays anything but trump — UNLESS only trump remains in his hand." [Lines 145–149 @ 00:05:14–00:05:22]

### Verbatim Arabic (≤15 words, the operational rule)

> "ما يلعب اول ورقه في الارض حكم"

**Source line 145** @ 00:05:14,880 → 00:05:17,030.

### English translation

> "He doesn't play [the] first card to the floor [as a] trump."

### Confirmation

CONFIRMED. Maqfūl is the lead restriction (no opening with trump) under Hokm + even-multiplier (Bel/Four).

### Critical note on parity

The speaker is precise that Maqfūl applies to **even multipliers only** (Bel ×2, Four ×4). Three (×3) and Gahwa-coffee are explicitly **مفتوح / open** — see lines 153–165 @ 00:05:25–00:05:46:
> "برضو اللعب مقفول لكن في بعض الجلسات يلعبون الدبل والفور لعب مفتوح ... لو مثلا ما كان في دبل كان لعب طبيعي او كان ثري اللي هو عدد فردي تضرب في ثلاثه او كان قهوه هذا لعب مفتوح"

**English (≤15-word quote):** "لو ... كان ثري اللي هو عدد فردي ... هذا لعب مفتوح" — "if [the multiplier] is Three, which is an odd number ... this is open play."

So: **odd multiplier = open; even multiplier under Hokm = maqfūl** — but some sessions also play Bel/Four as open, so this too is partially session-dependent.

### Confidence

**HIGH** on the rule, **MEDIUM-HIGH** on the session-dependence (speaker says "في بعض الجلسات يلعبون الدبل والفور لعب مفتوح" — "in some sessions they play Bel/Four as open").

---

## Q8. Hand-shape requirements / explicit threshold for Bel call

### Verdict

**No hand-shape threshold. No explicit minimum-strength requirement.**

### Evidence

The speaker treats Bel as a **bidding-phase declaration** with two gates only:
1. **Timing gate** — before cards are revealed (Q6).
2. **Score gate (Sun only)** — caller-team < 100 AND opposite-team ≥ 101 (Q1, Q2).

There is NO mention in the transcript of:
- "Bel only with X trump cards"
- "Bel only with hand-strength ≥ N"
- "Bel only with Belote/sequences" (the hand-decoration sense of "بلوت" is a different concept)
- Any quantitative shape requirement

The only passage describing what justifies a Bel is the abstract reasoning at lines 209–229 @ 00:06:40–00:07:09, where the speaker simply says "[the player] said Bel — that's it, the play is multiplied by two." No hand-shape gate.

### Implicit threshold (NOT verbatim — inferred)

The speaker's framing throughout (e.g., line 64 @ 00:01:33: "متى تقول" — "when do you say [Bel]") treats it as a **judgment call**, not a rule-gated action. The closest the speaker comes to a "threshold" is the cards-revealed lockout (timing) and the Sun score-split (score) — both already captured above.

### Confidence

**HIGH on absence.** A teaching video for beginners that omits a hand-shape requirement, while explicitly listing all the OTHER requirements (timing, score, session variants), is strong evidence that no canonical hand-shape threshold exists in this rule-tradition. Hand-shape is bot-strategy / heuristic territory, not rule-legality.

---

## Summary — D-RT-22 verdict from the source

| Question | Source verdict |
|---|---|
| Is the Sun-Bel rule score-split (caller-team <100 vs opposite ≥100)? | **YES — verbatim @ 00:07:25–00:07:31** |
| Is the rule role-irrelevant (no bidder/defender distinction)? | **YES — speaker never invokes role; uses pure-score language throughout** |
| Can the bidder team Bel its own Sun contract when bidder-team is at ≤100 and defender-team is at ≥101? | **YES by direct application of the verbatim rule. The speaker uses second-person "you" pronouns continuous with an earlier "you bought Sun" example, and never adds a buyer-exclusion clause.** |
| Does `R.CanBel` (role-irrelevant predicate) match the source? | **YES — `R.CanBel` is correctly aligned with the speaker's stated rule.** |
| Does `Net._OnDouble` defender-seat gate match the source? | **NO — the defender-seat gate has no basis in the speaker's rule statement and is the cause of the D-RT-22 60s AFK regression on bidder-trailing-Sun.** |

**Recommended (no code change in this audit per instructions, but for the audit log):** the defender-seat gate in `Net._OnDouble` and any UI feed should be widened to allow the bidder team's seat to surface a Bel button when the score-split predicate is satisfied. This brings the network/UI layer into agreement with `R.CanBel` and with the source video's rule.

---

## Provenance

- **Transcript file:** `C:\CLAUDE\WHEREDNGN\docs\strategy\_transcripts\21fN1IEm5Xk_11_bel_beginners.ar-orig.srt`
- **Re-extract date:** 2026-05-05
- **Reaudit context:** v0.10.2 Track A — re-verifying v0.10.0 R1 score-split fix in light of D-RT-22 (Net._OnDouble defender-seat gate) finding
- **No code modified per audit instructions.**
