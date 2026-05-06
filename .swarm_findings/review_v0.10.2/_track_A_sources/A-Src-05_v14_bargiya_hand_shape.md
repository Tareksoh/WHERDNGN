# A-Src-05 — Video #14 Bargiya hand-shape re-extraction

Source SRT: `C:\CLAUDE\WHEREDNGN\docs\strategy\_transcripts\n1FBrNNVUAA_14_bargiya_ace_tahreeb.ar-orig.srt`
Title: "تهريب الإكا أو البرقية" (Bargiya = Ace-Telegram)
Total length: 14:34, 637 cue indices.
Re-extraction date: 2026-05-05 (against v0.10.0 R4 audit + v0.10.2 M7 cover-gate fix at Bot.lua:1652-1683).

This re-extraction is to confirm whether code's two-flavor split (`bargiya` vs `bargiya_hint`) at the AKA-classifier uses the **correct distinguishing axis** that the speaker actually defines, and to gather verbatim Arabic for the receiver phase-split rules used in `pickLead` Branch 4.

----

## Q1 — Verbatim Arabic at @ 00:11:48–00:11:54 (subtitles 509–515)

**Confirmed.** The subtitle-by-subtitle scrolling-caption layout means the line is split across 509/511/513/515. The continuous sentence is:

> **"اذا خويك اعطاك برقيه من اول مره انه محشور بلون واحد او بلونين مردوفه بشيء صغير او انت تكون تك او علق"**

Verbatim, broken to ≤15 word quotes per copyright limit:

| Cue | Time | Arabic ≤15 words | English |
|---|---|---|---|
| 509 | 00:11:45,120 → 00:11:48,350 | "تفهم اذا خويك اعطاك برقيه من اول مره انه" | "understand: if your partner gave you a Bargiya from the first time, it means he's…" |
| 511 | 00:11:48,360 → 00:11:51,410 | "محشور بلون واحد او بلونين ومنه مثلا" | "stuck/jammed in one suit or two — for example…" |
| 513 | 00:11:51,420 → 00:11:54,230 | "مردوفه بشيء صغير او انت تكون تك او علق" | "doubled up by a small one, or you're the singleton/holdup" |

**Confidence: HIGH (verbatim match against SRT cues 509/511/513).**

The speaker's stated *cause* of an early Bargiya is **partner's hand shape** — partner is "stuck in one or two suits." That is the specific causal chain (early Bargiya ⇐ partner is محشور). It is NOT defined by event-count.

----

## Q2 — Bargiya-as-invite vs Bargiya-as-defensive-shed: distinguishing axis

The video opens (00:00:06–00:00:13) by establishing the canonical Bargiya as **a partner-invite signal**:

> Cue 5–9: **"اقوى تهريب في البلوت … الا وهو تهريب الاكه او البرقيه او التبريك … من اسم البرقيه واضح انه رساله"**
> "The strongest sacrifice/discard in Baloot … is the Ace-discard / Bargiya / Tabriik … the name itself shows it's a message."

Cue 17–19 spells out the message:
> **"تعال سبيت فاذا اكلت الحله هذي مثلا العفس بيت وروح لخويك"** — "Come to spades; if you take this trick (e.g. with the Jack of clubs), come to your partner."

But cues 71–121 (00:01:46–00:02:59) explicitly carve out **two exceptions** where the Ace-discard is *not* an invite — these are the "defensive shed" cases:

> Cue 75: **"الاستثناءات بشيئين"** — "the exceptions are two things."

**Exception A — Ace-shed-and-run (forced from a singleton):**
> Cue 77–93: **"اذا خويك هرب بالاكه يعني عرب لك اكه وشرد بيها … ما عنده الا السبيت ما عنده الا شكل واحد"** — "if partner discarded the Ace and ran with it … he has only spades, only one suit." Partner is forced to dump the Ace before opponent can ruff/over-take it.

**Exception B — Ace-vs-T discard (chosen between two cards in same suit, late-game):**
> Cue 101–121: **"يهرب ابكا لكن ما يقصد فيها انه يبغى نفس الشكل هو انحد عليها او خير بينها وبين ورقه عنده اخرى"** — "discards the Ace but doesn't mean he wants the same suit; he was forced into it or chose between it and another card he had."
> Cue 117–121: **"ما يقصد انه هي اخر ورقه عنده فبالتالي هذه الحاله الثانيه اللي ما يقصد فيها تعال زي ما قلنا تكون في اخر الجيم"** — "he doesn't mean it's his last card; this second case where it doesn't mean 'come' is at the end of the game."

**The DISTINGUISHING AXIS is: WHO HOLDS THE 10/T (the second-rank card in the suit) — NOT how many events landed on the suit.**

- If partner discards an A and the T (or another high card in that suit) is **demonstrably elsewhere** (opponent or already played), the Ace-discard was forced/chosen — it's a defensive shed, NOT an invite.
- If partner discards an A and the T-or-other-cover is **plausibly with partner** (i.e. partner is holding ≥2 in the suit, "محشور بلون واحد"), it IS the invite — partner is stuck and asking for a return.

**Confidence: HIGH.** The two-exception structure is explicit, and the speaker's framing (cues 73–75 "السفنقات جدا بسيطه ونادره وغالبا تكون في اخر الجيم" — "the exceptions are very simple and rare and usually at the end of the game") directly maps "endgame + alternate-card available" to "defensive," and "early-game + stuck shape" to "invite."

This **DIRECTLY CONFLICTS** with code's current axis at Bot.lua:1640-1683:
- Code's axis is *event count* — single Ace event = `bargiya_hint` (hint), Ace + want event = `bargiya` (confirmed). The v0.10.2 M7 cover-grade gate at Bot.lua:1668-1683 is a partial fix but still uses event-count as the gate (escalating only when a second event meets a rank threshold).
- Speaker's axis is *cover topology* — "is the T plausibly with partner (محشور)" or "demonstrably not (انحد)". Single-event is sufficient on the speaker's axis when محشور is established.

----

## Q3 — Receiver phase-split rules 8–10 (verbatim)

The phase-split rules (immediate-lead vs delay-by-1-or-2-tricks) appear in cues 165–231 (00:03:55–00:05:28). Phase definition is at cues 219–227:

> Cue 221–225: **"بدايه اللعب اذا كان عند كل لاعب خمسه اوراق فاكثر ونهايه اللعب اذا كان عند كل لاعب اربع اوراق في اقل"** — "opening: every player has 5 cards or more. Endgame: every player has 4 cards or fewer."

**Confidence: HIGH (cue 221–225, exact numeric thresholds).**

### Rule 9 — Endgame (≤4 cards): lead immediately

> Cue 169–175: **"اذا كان نهايه اللعب روح لخويك على طول لانه غالبا عنده سوا"** — "if it's endgame, go to your partner immediately, because he probably has SWA."

> Cue 245–249: **"بالافضل روح لخويك حتى لو عندك اكله زياده ليش لانه نهايه اللعب وغالبا … عنده سوا"** — "better to go to partner even if you have a spare winner, because endgame he probably has SWA."

**Confidence: HIGH.**

### Rule 10 — Opening (≥5 cards): burn 1–2 own captures first

> Cue 173–179: **"اذا كان بدايه اللعب الافضل انك ما تروح لخويك مباشره فتاكل اكله واكلتين بعدين تروح لخويك"** — "if it's opening, better not go to partner immediately; eat one or two captures, then go to partner."

> Cue 437–449 (worked-example confirmation): **"على النظام انك تروح على طول حتروح بدون ما تاكل بالشاية صح راح تروح سبيت خويك غالبا ما عنده سوا لانه هنا في سبعه لسه. طيب لو سويت هذه الحركه اكلت اكله واحده قويه كذا هرب لك سبعه ثم رحت سبيت لانه هرب لك برقيه من اول"** — at hand-size 7, eat one strong capture (your J) FIRST, then return to spades; partner will Bargiya you with the 7 in the meantime, confirming.

**Confidence: HIGH.**

The speaker's phrasing **"اكله واكلتين"** ("one or two captures") is fuzzy — Rule 10 is "delay 1–2 tricks," NOT "always delay exactly 1." The exact count is governed by Rule 17 (numeric SWA-attempt thresholds, see Q6).

----

## Q4 — B-Bot-08 F5: pickLead Branch 4 leads Bargiya'd suit immediately for ALL hand sizes

**Confirmed bug.** Speaker says delay 1–2 own-capture tricks at hand size ≥5. Quote (already given in Q3 above):

> Cue 173–179: **"اذا كان بدايه اللعب الافضل انك ما تروح لخويك مباشره فتاكل اكله واكلتين بعدين تروح لخويك"** — "in opening, better not go to partner immediately; eat 1–2 captures first, then go to partner."

The speaker spends 18 seconds (cues 145–163) arguing **AGAINST** the common-but-wrong heuristic of "if partner Bargiya'd, lead it immediately regardless of hand size":

> Cue 141–149: **"تقولي اذا خويك بالرجلك اكه وروح على طول نفس الشكل حتى لو عندك اكل زياده من وجهه نظري الكلام هذا صحيح في اغلبه لكن في حالات فيها تفصيل والافضل انك ما تروح لخويك على طول"** — "people say: if partner gave you a Bargiya, go immediately with the same suit even if you have spare winners. From my view this is mostly right but there are detailed cases and the better rule is NOT to go to partner immediately."

The qualifying condition for delay is "you hold spare winners" (`اكل زياده`):

> Cue 245–249: **"حتى لو عندك اكله زياده ليش"** — "even if you have a spare capture, why [delay]?"
> Cue 437–449 (worked example): partner with 7-card hand, 1 spare J of a side-suit, you eat the J first, partner Bargiyas the 7, THEN you lead spades.

**This is exactly the rule pickLead Branch 4 violates** if it leads the Bargiya'd suit immediately when (hand_size ≥ 5 AND we hold a spare own-capture). Rule 9 is for endgame (≤4) only.

**Confidence: HIGH.** Cue 173–179 + cue 437–449 worked example are unambiguous.

----

## Q5 — SWA prior on Bargiya: phase-conditional?

**Yes — explicitly phase-conditional.** Cues 183–199 (00:04:18–00:04:44):

> Cue 183–189: **"خويك ما يبرق لك الا اذا عنده سوا هل هذا شرط او دائما لا هو غالبا اذا كان في نهايه اللعب سوا لكن اذا كان بدايه اللعب مش دائما سوا"** — "Does your partner ONLY Bargiya when he has SWA? No — usually if it's endgame YES SWA, but if it's opening NOT ALWAYS SWA."

> Cue 191–199: **"ليش مو دايما سوا لانه ممكن في حاله يكون خويك عنده شكل واحد فقط منه مثلا خمسه اوراق او اكثر بالتالي خويك يبرق لك من بدري من البدايه خايف انك ما تفهمه او مثلا ما عنده لون كفايه يقدر يهرب يخليك تفهم ايش يبغى بالضبط"** — "WHY not always SWA: because partner could have only one suit (e.g. 5 cards or more in it), so partner Bargiyas early — afraid you won't understand him, or he doesn't have enough other-color cards to throw to make you understand."

This is the *causal* model:
- **Endgame Bargiya → strong SWA prior.** Partner has cleared their hand and now needs the trick to claim — Bargiya sender is plausibly running SWA.
- **Early Bargiya (≥5 cards) → weak SWA prior; instead "stuck shape" (محشور) prior.** Partner is signaling because of their *shape*, not their winning-claim status. They might NOT have SWA at all.

> Cue 211–215 reinforces: **"خويه غالبا عنده سوا الا اذا ما عندك سبيت مثلا تروح بشيء ثاني سواء كان بدايه اللعب او نهايه اللعب"** — "partner usually has SWA EXCEPT when [other shape conditions apply]."

**Confidence: HIGH.** This directly maps to Q2 — endgame Bargiya = SWA-confirmed = invite-by-mathematical-claim; early Bargiya = محشور-driven = invite-by-shape-pressure. Both are invites, but only the endgame one carries the SWA prior reliably.

----

## Q6 — Concrete numeric SWA-attempt thresholds (Source B Rule 17)

Verbatim numeric thresholds at cues 519–527 (00:11:58–00:12:10):

> Cue 519–521: **"فالسؤال المهم كم اكله تاكل بعدين تروح لخويك اذا كان عنده مثلا سبعه اوراق تاكل اكلاتين ثلاثه اكلات بالكثير"** — "the important question is: how many captures do you eat before going to partner? If he has 7 cards, eat 2-3 captures at most."

> Cue 523–525: **"واذا كان عنده سته اوراق ممكن اكلتين بالكثير او اكله"** — "and if he has 6 cards, maybe 2 captures at most, or 1."

> Cue 525–527: **"واذا كان خمس اوراق اكله ولا تزود عليها"** — "and if he has 5 cards, [eat] 1 capture and DON'T add to it."

The speaker then gives the explicit reason at cues 529–537:

> Cue 529–533: **"حتى لو عنده اكل زياده ليش لا تزود اكل كثير لانه كل ما تزود اكل كل ما خويك يشك انه انت ما عندك الشكل اللي بره"** — "even if you have spare captures, why not eat too many: the more you eat, the more your partner suspects you don't have the suit he asked for."

Numeric table (verbatim):

| Partner hand size | Captures before going to partner | Cue |
|---|---|---|
| 7 | 2–3 max | 519–521 |
| 6 | 1–2 max | 523–525 |
| 5 | exactly 1, no more | 525–527 |

**Confidence: HIGH.**

This directly contradicts naive "always lead Bargiya'd suit immediately" and ALSO contradicts naive "always burn 2 first" — the count is a function of partner's apparent hand size.

----

## Q7 — Worked examples: A-only-discard vs A+T-discard (verbatim)

### Example 1 — Partner has 6 cards in single suit (محشور بلون واحد), Bargiya-as-invite via the 8 (cues 455–501, 00:10:32–00:11:36)

> Cue 455–461: **"الفكره في هذا المثال خويك عنده شكل واحد يصير هذه في البلوت عنده مثلا او سبعه وثمانيه خلينا نقول ثمانيه وسبعه نادره يعني لكن سته خمسه ممكن طيب هنا عنده سته اوراق"** — "the idea: partner has one suit, e.g. 6 cards in spades, the 8 and 7 are rare but 6/5 plausible. He has 6 cards."

> Cue 467–479: **"خويك عنده طريقتين هنا اول طريقه اذا انت لعبت راح يعطيك تسعه وبعدين اذا لعبت عشره … الطريقه الثانيه انه يعطيك اكه من اول مره ما يلعبها يعطيك برقيه يصير كذا وضح لك من بدري انه يبغى السبيد"** — "partner has TWO methods: method 1 — if you lead [later], he gives 9 then 10 [stepwise descending = 'want']. Method 2 — first time, instead of playing it, he gives the Ace, becomes a Bargiya, clarifies early he wants spades."

This is the **EARLY single-event Bargiya = INVITE** case: A is single, partner is محشور in a 6-card suit, no T-confirmation event needed because the *shape* makes the message unambiguous.

**Confidence: HIGH.**

### Example 2 — Partner forced to A-shed because of A+T pair late-game (cues 95–121, 00:02:14–00:02:59)

> Cue 105–115: **"خويك والله مسك الاكه هذه معاه عشره الدايمن في الاخير فانت اكلت مثلا بشايب وباقي لك ورقه في يدك وخويك توقع انه ما عندك سبيت واعطاك سبيت وانت هنا عندك سبيت او مثلا ما عندك من حد بين الاكا وبين العشره وخير بينها"** — "partner held the Ace of diamonds with the 10 at the end; you took with the J, you have one card left, partner *thought* you had no spades and gave you spades, but actually you have spades — partner is being forced/choosing between Ace and 10."

> Cue 117–121: **"ما يقصد انه هي اخر ورقه عنده فبالتالي هذه الحاله الثانيه اللي ما يقصد فيها تعال زي ما قلنا تكون في اخر الجيم"** — "doesn't mean it's his last card; this second case where it doesn't mean 'come' is at the end of the game."

This is the **LATE A+T-discard = NOT INVITE** case: partner held both A and T, chose to drop the A as a defensive shed because the T was a viable alternative. NOT a Bargiya invite.

**Confidence: HIGH.**

### Example 3 — Ace-shed-and-run from singleton suit (cues 77–99, 00:01:53–00:02:24)

> Cue 77–93 (already quoted above in Q2): **"اذا خويك هرب بالاكه يعني عرب لك اكه وشرد بيها … ما عنده الا السبيت ما عنده الا شكل واحد"** — partner has only one suit, dumps the Ace before opponent over-takes.

This is the **defensive forced shed**, NOT an invite. Note: this case is *also* محشور (partner has only one suit) — but the SHED is from a different suit than what partner is stuck in. The discriminator here is direction: partner discards an Ace-of-X to clear it before opponent ruffs, not because they want X led back.

**Confidence: HIGH** for the verbatim quote, **MEDIUM** for code-mappability (this case is hard to distinguish from Example 1 at recorder-time without tracking which suit partner has been keeping — currently we infer "suit shape" only by what partner has *played*, which is exactly the recorder's blind spot).

----

## Q8 — Cross-confirmation against v0.10.0 R4 / v0.10.2 M7

**Code state at Bot.lua:1640-1683 (read 2026-05-05):**

The current axis at line 1654-1665 is partial-correct:
```
-- v0.10.2 M7 — Bargiya canonical FN
-- محشور بلون واحد proxy: when sender held 5+ in this suit
... (when proxy says 5+, escalate single A to "bargiya")
```

The proxy at line 1654 (`5+ in this suit`) is **the right axis but wrong direction.** The speaker's "محشور بلون واحد" means **partner is stuck in a single-suit hand-shape** (i.e. the 5+ cards are spread across only 1-2 *other* suits and partner has nothing to throw away comfortably). It does NOT mean "partner held 5+ in *this* suit."

The clearest read of cue 191–199 ("ممكن في حاله يكون خويك عنده شكل واحد فقط منه مثلا خمسه اوراق او اكثر") is:

- Partner has only ONE suit, with 5+ cards in *that one suit*.
- That one suit is what partner WANTS led (the Bargiya'd suit).
- So actually — the v0.10.2 M7 proxy is **correct in direction** if we interpret "this suit" as "the suit where the Ace was discarded" — partner held 5+ in the suit they Bargiya'd. Wait, that's not محشور-from-shape, that's **a long suit they want pumped**.

**Cross-checking cues 153–179 makes this clearer.** The speaker distinguishes:
1. **محشور shape** — partner has 1-2 suits total (so they discard from a side suit; they want the *long* suit led back).
2. **Defensive shed** — partner has many suits but the suit they shed contained A+T, and they chose A.

**The recorder-side question is:** at the moment partner discards an Ace, what does the recorder know?
- Recorder knows: which suit partner discarded into (the side-suit), how many tricks partner has played in each suit so far.
- Recorder does NOT know: partner's full hand shape.

**Therefore the right proxy is NOT "did partner hold 5+ in the discard suit" — that's the WRONG suit.** The Bargiya'd suit (the suit partner wants led back) is **a different suit** from the suit the Ace was discarded INTO. The speaker's wording in cues 13-44 makes this clear: "if you played spades and partner discarded the Ace of clubs (=Bargiya'd), partner wants spades back" — the Ace's suit is clubs, the wanted suit is spades.

**So the correct محشور proxy at recorder-time is:**
- "Has partner shown ANY card outside the suit-led-by-you in the trick where partner discarded?" — if NO (partner only has long-suit + dump-shape), partner is محشور.
- More tractable proxy: count how many distinct suits partner has touched across all tricks so far. Few suits = محشور-likely.

**The cheap "2nd-rank ≥ T" fix (v0.9.2 #55 cover-grade gate at Bot.lua:1668-1683)** is on the wrong axis. It fires only when a SECOND event arrives — but the speaker's own examples (Example 1 in Q7) explicitly confirm a single-event Bargiya is sufficient when shape is established, and (Example 2) confirms even multi-event isn't sufficient when the A+T cover is broken late-game.

**Verdict:** The cheap "2nd-rank ≥ T" fix is **NOT sufficient.** A recorder-time محشور-detection signal is needed — proxied by partner's shown-suits-count-so-far, plus the relative position of the discard within the trick.

**Confidence: HIGH** that the axis is wrong; **MEDIUM** that suits-touched-count is the best practical proxy (further test cases in `audit_v0.9.0/55_bargiya_axis_impact.md` would help calibrate).

----

## Cross-cutting verbatim quotes (≤15 words each, for code comments / future docs)

| Topic | Cue | Arabic ≤15 words |
|---|---|---|
| Phase definition | 221–225 | "بدايه اللعب اذا كان عند كل لاعب خمسه اوراق فاكثر ونهايه اللعب اربع اوراق" |
| Endgame rule | 169–171 | "اذا كان نهايه اللعب روح لخويك على طول لانه غالبا عنده سوا" |
| Opening rule | 173–179 | "اذا كان بدايه اللعب الافضل انك ما تروح لخويك مباشره فتاكل اكله واكلتين" |
| محشور cause | 511 | "محشور بلون واحد او بلونين ومنه مثلا" |
| SWA phase-split | 187–189 | "غالبا اذا كان في نهايه اللعب سوا لكن اذا كان بدايه اللعب مش دائما سوا" |
| 7-cards threshold | 521 | "اذا كان عنده مثلا سبعه اوراق تاكل اكلاتين ثلاثه اكلات بالكثير" |
| 6-cards threshold | 523 | "واذا كان عنده سته اوراق ممكن اكلتين بالكثير او اكله" |
| 5-cards threshold | 525–527 | "واذا كان خمس اوراق اكله ولا تزود عليها" |
| Why not over-eat | 531–533 | "كل ما تزود اكل كل ما خويك يشك انه انت ما عندك الشكل اللي بره" |
| Defensive-shed exception | 117–121 | "ما يقصد انه هي اخر ورقه عنده فبالتالي تكون في اخر الجيم" |

----

## Summary recommendations (informational only — no code changes per instructions)

1. **Q1 verbatim:** Confirmed exactly. Single sentence split across cues 509/511/513/515.
2. **Q2 axis:** The distinguishing axis is **cover topology / hand-shape (محشور vs A+T-broken)**, NOT event-count. Code's current event-count axis at Bot.lua:1640-1683 is wrong.
3. **Q3 phase-split:** Endgame (≤4) = lead immediate; Opening (≥5) = burn 1–2 first. Verbatim at cues 169–179.
4. **Q4 B-Bot-08 F5:** Confirmed bug. Rule 9 (delay 1–2 in opening) is in the speaker's verbatim at cue 173–179.
5. **Q5 SWA prior:** Phase-conditional. Endgame Bargiya = SWA-strong; opening Bargiya = shape-driven, SWA-weak. Verbatim at cue 183–199.
6. **Q6 numeric thresholds:** Partner hand 7→2-3, 6→1-2, 5→1. Verbatim at cues 519–527.
7. **Q7 worked examples:** Both Example 1 (محشور invite) and Example 2 (A+T defensive) confirmed verbatim with cue references.
8. **Q8 cross-confirm:** v0.10.2 M7 cover-grade gate is on the wrong axis. The cheap "2nd-rank ≥ T" fix is **NOT sufficient.** A recorder-time محشور-detection signal (proxied by partner's distinct-suits-touched count) is needed.
