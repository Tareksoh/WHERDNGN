# Reaudit R4: Bargiya/Tahreeb classification axis

This is the deferred audit_v0.9.0/55 close. Three Phase-1 reports
(A, B, F) made claims about the SAME signal that LOOK like they
contradict on the classification axis (event-count vs hand-shape
vs direction). Reading the Arabic transcripts directly resolves
the conflict: they describe a multi-axis classification — there
is **no contradiction**, but the current code collapses two of the
axes into one, and that conflation is the bug.

---

## Quoted Arabic from key passages

### Video #14 @ 00:11:42 – 00:12:32 (the disputed Bargiya passage)

Lead-in (subtitles 491–509, 00:11:20 → 00:11:48):

> الطريقه الثانيه انه يعطيك اكه من اول مره ما يلعبها يعطيك
> برقيه يصير كذا وضح لك من بدري انه يبغى السبيد ايضا حيتوقع
> انه انت اصلا ما عندك لانه باقي من السبيل قطعتين فقط ممكن
> تكون عنده الخصم فبالتالي اعطاك احسن منه ياخذها وممكن ما
> يرجعوا له ايضا لو انت عندك سبيد وعندك اكل زياده كانه يقول
> لك يا خويي كل اكل لك وبعدين تعال

Translation (essential): "The second method is that he gives you
the Ace from the very first time, doesn't play it, he gives you a
'Bargiya'. So it's clear early to you that he wants Spades. He'll
also expect that you don't have it [the Ace], because only two
pieces of Spades remain — possibly the opponent has them — so he
gave it to you better than the opponent taking it. They might
also not return [the suit] to him. And if you have Spades AND you
have extra eats, it's as if he's saying to you: 'my partner, eat
your eats first then come [to me]'."

The KEY sentence (subtitles 509–515, 00:11:45 → 00:11:54):

> فانت لازم تفهم اذا خويك اعطاك برقيه من اول مره انه
> **محشور بلون واحد او بلونين ومنه مثلا مردوفه بشيء صغير
> او انت تكون تك او علق**

Translation: "So you must understand — if your partner gave you a
Bargiya from the first round, it [means] he is **محشور
(cornered/stuck) in one color or two colors, with for example a
مردوفه (paired/backed) by a small card, OR you [the receiver] are
تك (alone/empty in suit) or علق (hooked)**."

Then the immediate follow-on (subtitles 515–531, 00:11:54 →
00:12:15) gives the receiver-side numeric thresholds:

> الان لو اعطاك من البدايه طبعا انت ما تعرف بالضبط ايش اوراقه
> فالسؤال المهم كم اكله تاكل بعدين تروح لخويك اذا كان عنده
> **مثلا سبعه اوراق تاكل اكلاتين ثلاثه اكلات بالكثير واذا كان
> عنده سته اوراق ممكن اكلتين بالكثير او اكله واذا كان خمس
> اوراق اكله ولا تزود عليها** حتى لو عنده اكل زياده ليش لا
> تزود اكل كثير لانه كل ما تزود اكل كل ما خويك يشك انه انت ما
> عندك الشكل اللي بره بالذات اذا عنده لون واحد فخويه كذا ممكن
> يضطر انه يهرب بالعشره

Translation: "Now if he gave you it from the start, of course you
don't know exactly what his cards are. The important question is:
how many eats do you take before going to your partner? If he has
e.g. 7 cards, take 2 eats, 3 eats at most. If he has 6 cards,
maybe 2 at most or 1. If he has 5 cards, ONE eat — don't add to
it, even if you have extra eats. Why don't you add more eats?
Because every extra eat makes your partner doubt that you have
the suit out there — especially if he has one color [single-suit],
his partner [you] might force him to throw away with the 10 [as a
defensive action]."

### Video #09 @ 00:00:49 – 00:01:09 (single-event tahreeb classification)

> اذا خويك هرب لك ورقه معناته تقريبا الاكه البرقيه وتهريب من
> تحت لفوق لكن تهريب يحتاج تهريب مره ثانيه

Translation: "If your partner threw you a card, it means
approximately the 'Aka of Bargiya' and 'tahreeb from below to
above', BUT a tahreeb needs a second tahreeb to confirm."

Then 00:00:58 → 00:01:03:

> مبدئيا عندي من اول مره خويه الرمله دائما ايش افترض هنا
> حفترض بنسبه كبيره خويي يبغى خاص

Translation: "Initially from the first time, what do I assume?
I'd assume with a big probability my partner wants [Spades/the
suit]."

### Video #10 (small-to-big direction encoding)

The cluster Source-A Rule 7/8 quotes hold up in the SRT:

> اقوى تهريب في البلوت اذا كان التهريب من مرتين او اكثر
> (00:00:17–00:00:23)
>
> من كبير لصغير معناته ما يبغى ... من تحت لفوق ... يبغى نفس
> الشكل (00:00:55–00:01:06)
>
> ما تهرب ثمانيه بعدين سبعه ... هدفك الرساله ... عكس تماما
> (00:04:46–00:05:00)

Translation summary: "The strongest tahreeb in Baloot is when the
tahreeb is from two times or more. From big to small means he
doesn't want; from below to above means he wants the same suit.
Don't tahreeb 8 then 7 — your goal is the message; that's
completely backwards."

### Video #12 (Tanfeer/Tahreeb taxonomy — the parent-class ruling)

Source F Rule F2.02 is verbatim from the SRT (00:01:38–00:02:03):

> كل تهريب تنفيذ لكن ليس كل تنفيذ تهريب

Translation: "Every Tahreeb is a Tanfeer/Tanfeedh, but not every
Tanfeer is a Tahreeb."

And Rule F2.06 (00:03:38–00:03:50) on the Bargiya inversion:

> اللي اذا اعطاك برقيه معناته يبغى نفس الشكل

Translation: "If he gives you a Bargiya, it means he wants the
same suit."

---

## Are Phase1-A and Phase1-B in conflict, or describing different things?

**Not a conflict. They describe different things, both correct.**

The conflation lies in the words "Bargiya" and "Tahreeb" being
used at different levels of the taxonomy:

- **Phase1-A** (videos 01/02/03/09/10) is mostly talking about
  **multi-event small-to-big sequences** of *side-suit* tahreeb
  (Form 5 of the five tahreeb forms, ranks 7/8/9/J discarded
  across consecutive partner-won tricks). For THAT class, the
  axis IS event-count + direction:
  - 1 event = "hint" (~70% confidence)
  - 2 events ascending = "want" (~100%)
  - 2 events descending = "dontwant"

- **Phase1-B** (video 14) is talking about **the Bargiya
  specifically** (Form 4 — Ace-as-tahreeb, the named
  "البرقيه"/"telegram"). Bargiya is a **single-event** Form-4
  signal that does NOT need a second event to be high-confidence.
  The receiver-side question is "should I dash to partner now or
  eat first?", and the answer depends on **partner's hand-shape
  at signal time**:
  - **محشور بلون واحد/بلونين** (cornered into 1 or 2 colors) +
    early-game = invitation Bargiya, dash to partner
  - **End-game stranded Ace** = defensive shed, NOT an invitation
    (the two exceptions in Source-B Rule 3)

- **Phase1-F** (video 12) is the *taxonomy* layer: Tanfeer ⊃
  Tahreeb ⊃ {Bargiya, small-to-big, etc.}. Bargiya is the
  high-card-discard *inversion* of the default Tahreeb code.

The phrase "tahreeb classification axis" therefore needs
sub-typing:

| Axis | Applies to | Source |
|---|---|---|
| **Event-count + direction** | side-suit (non-A) Tahreeb pairs (Form 5) | Source A Rules 7, 8, 9, 27, 40, 50, 53 |
| **Hand-shape (محشور)** | Bargiya (Form 4) flavor: invite vs defensive-shed | Source B Rule 9; Video 14 @ 00:11:48–00:11:54 |
| **Direction (small→big vs big→small)** | side-suit Tahreeb pairs only | Source A Rule 8 |
| **Player-relationship (partner vs opp)** | choosing Tahreeb-read vs Tanfeer-read | Source F Rules F2.07, F2.08 |

**Source A Rule 58/59 is partially wrong** when it says "the axis
is event-count, NOT hand-shape". The correct statement is:
event-count + direction is the axis for FORMS 1, 2, 3, 5 (the
non-A forms); hand-shape (محشور) is the axis for FORM 4 (Bargiya
invite-vs-shed). Source A's Rule 58 over-generalized from its
own corpus, which doesn't include video 14.

---

## True classification model

```
Tanfeer (any "I'm getting rid of this" discard while void in
   led suit)
└── Tahreeb (intentional partner-targeted version: precondition =
       partner currently winning the trick at 100%; sub-precondition =
       sender is قاطع/cutter)
    ├── Form 4: Bargiya (single Ace-discard)
    │   ├── INVITATION flavor
    │   │   • Trigger: sender محشور (cornered) in 1-2 colors
    │   │     with مردوفه backed by small, OR receiver is تك/علق
    │   │   • Phase: any (especially early-game, single-suit ≥5)
    │   │   • Receiver action depends on game-phase + own extras
    │   │     (eat 0/1/2/3 by partner-hand-size 5/6/7)
    │   │
    │   └── DEFENSIVE-SHED flavor
    │       • Trigger: end-game (each player ≤4 cards), opponent
    │         has 2-3 cards in hand showing strong-suit collection,
    │         OR sender forced (only A + one other in suit)
    │       • Receiver action: do NOT lead the suit back blindly
    │
    └── Forms 1, 2, 3, 5: side-suit Tahreeb (non-A discards)
        • Axis = event-count × direction
        • 1 event  = "hint" (70/25/5 prior on opposite-color)
        • 2 ascending  = "want"     (100% confidence)
        • 2 descending = "dontwant" (signal partner away)
        • mixed direction = unreadable, treat as "hint"
```

The taxonomy is internally consistent across A/B/F. The
key disambiguator: **the signal's first event is `A`** routes
through the hand-shape axis; **the first event is `7/8/9/J/Q/K`**
routes through the event-count + direction axis.

---

## Code verdict

### Current `tahreebClassify` (Bot.lua:1582-1630, v0.9.2)

**Axis used for Bargiya:** `signals[1] == "A"` AND `#signals >= 2`
AND `r2 >= rT` (rank Ten-or-better) → `"bargiya"` (confirmed
invite). Single Ace event OR 2nd event below rank-T → `"bargiya_hint"`.

This is an **event-count + 2nd-rank-cover-grade hybrid** that
attempts to approximate the hand-shape axis without ever seeing
the sender's hand shape. The v0.9.2 cover-grade gate (the `>= rT`
check) was added precisely to mitigate the Bargiya FP (Example B
in audit 55: A then forced-courtesy-8 falsely escalating).

**Axis used for non-A Tahreeb:** event-count (1 = `"hint"`, 2+
ascending = `"want"`, 2+ descending = `"dontwant"`, mixed = `"hint"`).
**This part is correct vs source.**

### Correct axis per source

| Signal type | Correct axis | Current code | Status |
|---|---|---|---|
| Side-suit pair (Forms 1/2/3/5) | event-count + direction | event-count + direction | **CORRECT** |
| Bargiya invite vs defensive-shed (Form 4) | hand-shape (محشور at signal time) + game-phase | event-count of A-events + 2nd-event rank-cover | **APPROXIMATION (lossy)** |

**Bug confirmed: PARTIAL Y.**

- **Side-suit tahreeb classification** (Source A Rules 7/8/9): no
  bug. Event-count + direction is the right axis for those forms,
  and the code implements it correctly.

- **Bargiya classification** (Source B Rule 9, video 14
  @ 00:11:48–00:11:54): **YES, axis-mismatch bug**. The
  source-canonical axis for distinguishing invitation-Bargiya from
  defensive-shed-Bargiya is **sender's hand-shape at signal time**
  (محشور in 1-2 colors, مردوفه with small, or receiver تك/علق),
  conditioned on game-phase (each-player cards ≥5 = early ⇒
  invite tilt; ≤4 = end ⇒ shed tilt). The current cover-grade
  proxy (require A then ≥T) is a 2nd-event heuristic that approximates
  the hand-shape axis but is structurally different and misses
  the dominant FN case: the **first-trick Ace-only Bargiya from a
  محشور sender**, where there's no 2nd event yet to reach
  cover-grade. That is *exactly* the canonical worked example in
  video 14 @ 00:11:42-00:11:54 ("اعطاك برقيه من اول مره ... محشور
  بلون واحد") — and the current code routes it to `"bargiya_hint"`
  (score 1), which the receiver weights *below* a 2-event
  side-suit `"want"` (score 2).

### Cross-check: receiver scoring (Bot.lua:1660-1710 region,
actual span 1749-1822)

Score table:
- `bargiya`       = 3
- `want`          = 2
- `bargiya_hint`  = 1

Per Source-B Rule 1/2 ("Bargiya ~90%, اقوى تعريف البلوت / strongest
convention in Baloot") and Source-A Rule 7 (small-to-big 2-event =
100%), the score ordering is plausible WHEN bargiya_hint truly is
the lower-confidence flavor. The bug is upstream — events that
SHOULD be `"bargiya"` (محشور invitation) are being classified as
`"bargiya_hint"` and thereby losing to incidental side-suit "want"
signals.

The opp-avoid set (Bot.lua:1800-1816) was correctly broadened in
v0.9.3 #58 to include `bargiya_hint`, so the receiver-side
defense against opp signals is fine. The bug is partner-side
under-weighting only.

### Cross-check: recorder (Bot.lua:560-590)

The recorder appends `(suit, rank)` only — it does NOT capture
**sender length-in-suit at signal time** or **game-phase / each-
player card count at signal time**. Both are required for the
hand-shape axis. So the classifier physically cannot apply the
correct axis without a recorder-side change.

---

## Recommended code action

The audit_v0.9.0/55 finding listed two fixes; pick the **strong
fix** to actually close the issue, not the cheap fix that was
shipped in v0.9.2 (which only narrows the FP). The cheap fix
addresses the FP (Example B in audit 55) but does NOT address the
FN (Example A — true invite from محشور sender on first trick).

**Recommended change set (no code modification done in this
audit per instructions):**

1. **Recorder (Bot.lua:582-588):** instead of
   `list[#list+1] = C.Rank(card)`, store
   `list[#list+1] = { rank = C.Rank(card), lenAtPlay = N, trickNum = T }`
   where `N` = count of cards the sender holds in `cardSuit`
   *immediately after* this play (i.e. the sender's residual
   length in suit, which is the post-signal محشور proxy), and
   `T` = trick index when the signal fired (proxy for
   game-phase).

2. **Classifier (Bot.lua:1595-1613):** for Ace-led signal sequences,
   promote to `"bargiya"` immediately when:
   - `signals[1].lenAtPlay >= 4` (sender محشور in this color
     at signal time — they retained 4+ side cards in the suit
     after dropping their Ace), **OR**
   - `signals[1].trickNum <= 3 AND sender has only 1-2 distinct
     suits visible in their plays so far` (early-game محشور
     proxy). The trick-3 boundary aligns with Source-B Rule 4's
     ≥5 cards = early-game definition.

   Keep the existing 2-event cover-grade path as a secondary
   confirm: `signals[1].rank == "A" AND #signals >= 2 AND
   signals[2].rank ∈ {T,J,Q,K}` ⇒ `"bargiya"`.

   Single Ace event with NEITHER condition met ⇒ `"bargiya_hint"`
   (the genuine ambiguous case — defensive shed at end-game with
   no 2nd event).

3. **Receiver weights (Bot.lua:1773-1776):** unchanged — the
   `bargiya=3 / want=2 / bargiya_hint=1` ordering is correct;
   the routing change in (2) puts the right events into
   `bargiya` (3) instead of `bargiya_hint` (1).

4. **Defensive-shed detection (out of scope for this issue but
   worth flagging):** Source B Rule 3's two named exceptions are
   end-game-only (each player ≤4 cards). A future receiver-side
   refinement should consult game-phase before acting on
   `"bargiya"` from late-trick Ace signals — but only after the
   recorder change above lands. Without sender hand-shape info,
   end-game Bargiyas are inherently ambiguous and the current
   `"bargiya_hint"` fallback is the safe path.

5. **Tests:** the test pin from audit 55 is still missing per
   that finding's note. Add to `tests/test_bot_signals.lua`:

   | signals.S | post-strong-fix |
   |---|---|
   | `{}` | nil |
   | `{rank="7", lenAtPlay=3, trickNum=4}` | hint |
   | `{rank="A", lenAtPlay=5, trickNum=2}` | **bargiya** (was bargiya_hint pre-fix — FN closed) |
   | `{rank="A", lenAtPlay=2, trickNum=7}` | bargiya_hint (genuine ambiguous late-game) |
   | `{rank="A",...},{rank="8",...}` | bargiya_hint (forced courtesy 8, current cover-grade gate already correct) |
   | `{rank="A",...},{rank="T",...}` | bargiya |

   These pin the new axis without breaking the existing
   v0.9.2 cover-grade behavior on 2-event sequences.

---

## Confidence

**HIGH** on the conflict resolution and source reading.

- Phase1-A and Phase1-B are NOT contradictory; A's Rule 58 is
  over-generalized from its corpus (videos 01/02/03/09/10 don't
  cover Bargiya invite-vs-shed sub-classification, only Forms
  1/2/3/4-burqia-as-AKA/5).
- Video #14 @ 00:11:42-00:11:54 says exactly what Phase1-B Rule 9
  reports: hand-shape (محشور بلون واحد او بلونين) is the axis for
  the early-Bargiya invite case. Verified verbatim against the
  source SRT.
- Phase1-F's Rule F2.02 (`كل تهريب تنفيذ لكن ليس كل تنفيذ تهريب`)
  cleanly resolves the taxonomic level — Bargiya, small-to-big,
  and opposite-color signals are all subtypes within the Tahreeb
  parent class.

**MEDIUM** on the ranking of fix priority. The v0.9.2 cover-grade
gate already kills the Example-B FP (false invite from forced
courtesy 8), so the remaining bug is the Example-A FN (true invite
on first-trick Ace from محشور sender being downgraded to
`bargiya_hint`). Whether this FN is worth a recorder-schema change
depends on game-frequency data not collected here. The fix is
mechanically straightforward (~1 hash per discard) but it's a
recorder-schema change, which has compatibility implications for
saved style ledgers. A simpler interim could be: keep the
recorder schema but classify on a **receiver-side computed proxy**
(e.g., when a single A signal arrives at trick ≤3 with sender's
already-seen plays showing only 1-2 distinct suits, escalate to
`bargiya` despite no 2nd event).

**Definitive close on the audit_v0.9.0/55 axis question:** the
hand-shape axis IS canonical for Bargiya per video #14. The code's
event-count + cover-grade approximation is structurally weaker and
DOES under-fire on the canonical worked example. The cheap fix
shipped in v0.9.2 narrowed the FP but did not address the FN,
which is the larger error per the source's own framing of Bargiya
as "اقوى تعريف البلوت" (strongest convention in Baloot, ~90%
success).
