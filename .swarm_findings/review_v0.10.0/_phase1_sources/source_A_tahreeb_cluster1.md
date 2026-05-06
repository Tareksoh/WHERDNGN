# Source A — Tahreeb cluster pt 1 (videos 01, 02, 03, 09, 10)

**Note on transliteration:** The speakers consistently use Arabic
suit names: شريه (sharia/sharee = Hearts), سبيت (spit/spade = Spades),
دايمن/ديمه (dayman = Diamonds), هاص/هاوس (haas/hous = Clubs).
Card ranks: السبعه (7), الثمانيه (8), التسعه (9), البنت (Q), الولد/الشايب
(J), العشره (10), الاكه (A). "خويك" = your partner. "صن" = Sun contract.
"اكه" / "اككه" = Ace; **"اكا" (AKA)** = the named partner-direction signal
(speaker often uses بَرقيه/barqia interchangeably for the Ace-lead variant).
"كاله" = Clubs (synonym in speech). The transcripts blur ك/ق at times;
سحب is spelled هاص/هاوس inconsistently — I treat them as Clubs throughout.

## Coverage map

| Video | Title slug | Primary topics covered | Touched (secondary) topics |
|---|---|---|---|
| 01 | `tahreeb_beginners` | Foundational tahreeb concept; the 5 forms (نفس اللون عكس الشكل / عكس اللون / two-card same-color discard / البرقيه AKA-lead / من تحت لفوق); high-to-low vs low-to-high direction encoding; partner-trick precondition; reading opponent vs partner; reasons partner may "miss" the signal | 70/30 success-prior framing; opponent "tafarnak" (تفرنك) reaction to forced 10; Ahkam-vs-Sun bidding context; throwing Q for points; "side-by-side card pair" (مردوفه) caveat; protecting 10 by leading neighbor; remembering all played cards |
| 02 | `partner_after_tahreeb` | Receiver-side response after partner's tahreeb-of-A; when to lead 10 vs cover (شراء/buy back); when 10 is "alone" vs "doubled" (مردوفه); avoiding capture-with-J trick when 10 lonely; **سرد** (3-of-suit-mirror) reasoning; protecting 10 in 3-card holdings; مثلوث (triple-non-runner) shape; not playing the 8 next to a doubled 10 in front-position | Reading buyer's hand (Sun buyer = no Diamond run); not leading the 8-next-to-10 if you'd waste your 10 sit; partner returning Diamond after winning vs trump return; trick economics: 1 vs 2 captures based on card-count |
| 03 | `tahreeb_vs_tanfeer` | The boundary case where you don't know whether YOU or OPP wins the future trick; degenerate prob-50/50 or 45/45/10 weighting; **default to tahreeb-rule (opposite of taneer)** when uncertain; classifying hand strength as **Weak / Medium / Strong** for shape choice | Taneer (التنفيذ) reverse rule (partner wins → you cut means tahreeb; opp wins → you cut means tanfeer); "hold the strong card; signal-discard with the medium one"; "tahreeb is a message to your partner — every card you discard means something" |
| 09 | `most_essential_tahreeb` | **Key prior probabilities 70/25/5** for tahreeb-of-single-card; the "second tahreeb confirms" rule; how absence of an expected second tahreeb in trick-2 means partner is cut in suit; the "I want this colour" small-to-big rescue when partner has no preferred suit | "Direction (low→high or high→low) is the only language for two-tahreeb pairs"; signaling Diamond vs Clubs preference using A vs Q rather than 9; example-based pedagogy disclaimer |
| 10 | `tahreeb_small_to_big` | The من تحت لفوق rule — **strongest tahreeb in Baloot, 100% confidence when occurring 2x or more**; small-to-big = want the suit; big-to-small = don't want; ordered-pair language: 7-then-8 ≠ 8-then-7 even though "no points"; how to use sub-7-8-9 ranks to send the message; opponent's small-to-big also means "wants the suit" — and impacts your **don't-lead-that-suit** decision | "If partner has 10, partner should tahreeb-with-the-10 (top-down)"; partner-without-10 forced into bottom-up, that's why bottom-up implies "no 10 in partner's hand"; risk of the 7→J→9 mixed-direction sequence confusing partner |

---

## Rules extracted

### Rule 1: Tahreeb is defined by partner-wins-the-trick precondition
- **Source:** video 01 @ 00:00:31–00:00:54; video 03 @ 00:00:07–00:00:17
- **Arabic phrase:** "اذا كان اللعب لعب عند خويك" / "لازم خويك يكون ماكل حل مئه في الميه"
- **Rule (English):** A discard is classified as "tahreeb" only when the trick is currently being won by your partner with **100% certainty** before your turn arrives. If opponent is winning, your discard is classified as "tanfeer" (التنفيذ) instead — the opposite signaling axis.
- **Confidence (per source):** Definite (stated as definitional in 01, 03)
- **Hand-shape preconditions:** n/a — this is a phase classifier, not a hand condition
- **Phase scope:** mid-game / signaling
- **Numerical thresholds:** Partner's win-probability for this trick = 100%
- **[FOCUS]** Bot decision-making depends on this binary classifier; if code uses a probabilistic threshold or treats partner-tied as tahreeb, it diverges from the source.

### Rule 2: The "tanfeer" axis is the EXACT inverse of tahreeb
- **Source:** video 03 @ 00:00:25–00:00:39; @ 00:01:48–00:02:00
- **Arabic phrase:** "بالنسبه للتنفيذ عكس التهريب تماما"
- **Rule (English):** Tanfeer rules are the exact opposite of tahreeb. If you tahreeb-discard a card, it means you do NOT want that suit. If you tanfeer-discard a card, it means you DO want that suit (or you have the Ace of that suit).
- **Confidence:** Definite
- **Hand-shape preconditions:** n/a
- **Phase scope:** signaling
- **Numerical thresholds:** none

### Rule 3: Boundary case — "between tahreeb and tanfeer" (uncertain trick winner)
- **Source:** video 03 @ 00:00:43–00:01:33
- **Arabic phrase:** "اذا ما انت متاكد مين راح ياكل حله سواء خويك او احد خصمينك"
- **Rule (English):** When you cannot tell who will win the trick, treat the situation probabilistically. The speaker frames it as either **50/50** (partner-vs-opp), or in a finer-grained variant **45% partner / 45% one-opp / 10% other-opp**. **In this uncertain case, default to the tahreeb interpretation** because "the tahreeb rule is stronger than the tanfeer rule" and partner is more likely to "follow with you".
- **Confidence:** Common (single source explicitly, but phrased as a known proverb)
- **Phase scope:** signaling / mid-game
- **Numerical thresholds:** **50/50** baseline; **45/45/10** finer alt; tie-break **always tahreeb**.
- **[FOCUS]** If `Bot.PickPlay`/`PickAKA` codes a hard threshold (e.g. partner-win > 0.6 → tahreeb; else tanfeer) it should match this default-to-tahreeb behaviour, not 50/50 random.

### Rule 4: Tahreeb success rate is roughly 70%, never 100%
- **Source:** video 01 @ 00:06:01–00:06:09
- **Arabic phrase:** "التهريب مش مضمون 100% خلينا نقول 70%"
- **Rule (English):** A tahreeb signal is "about 70%" reliable — it can fail because (a) partner is a beginner and doesn't read it, (b) partner wasn't paying attention, (c) partner is cut in the suit you want, (d) partner has the suit but a weaker form. Don't expect 100% return.
- **Confidence:** Common (one source quantifies; others imply)
- **Phase scope:** signaling / mid-game
- **Numerical thresholds:** **~70%**
- **[FOCUS]** This is a **Bot decision** input — when bot models opponent-pair tahreeb signals, the prior on "partner of tahreeb-er has the suit" should be ~0.7, not 1.0.

### Rule 5: 70/25/5 prior for "what the partner wants" after a single tahreeb
- **Source:** video 09 @ 00:01:22–00:01:34
- **Arabic phrase:** "بنسبه 70% هل ممكن يبغى السبيت ... بنسبه 25% ... وهل ممكن يبغى دائما ... خمسه في المئه"
- **Rule (English):** When partner tahreebs ONE Diamond (دايمن) early, infer partner's wanted suit as: **~70% Clubs (هاص), ~25% Spades (سبيت), ~5% wants Diamonds (دائما/diamond)**. The 5% "wants the suit they discarded" case exists because the partner could be empty in the wanted suit and discarding Diamond is forced.
- **Confidence:** Single-source (quantified) but reflects a general distribution principle
- **Hand-shape preconditions:** First-trick discard, single-card tahreeb, partner has not tahreebed twice yet
- **Phase scope:** signaling / mid-game
- **Numerical thresholds:** **70 / 25 / 5** (suit-preference, alt-suit, paradox-want-discarded-suit)
- **[FOCUS]** This is the **exact prior** that should be in `Bot.PickAKA` / `Bot.PickPlay`'s opponent-tahreeb-reader. If the code uses 100/0/0, it overcommits to the wrong suit when partner is cut in the wanted suit.

### Rule 6: Two-time tahreeb (trick 1 + trick 2) raises confidence to 90%
- **Source:** video 09 @ 00:03:09–00:03:14
- **Arabic phrase:** "حتفترض بنسبه 90% انه يبغى خاص"
- **Rule (English):** After partner tahreebs a second time (in trick 2), the prior shifts to **~90% partner wants the second-tahreeb-implied suit**, with ~10% remainder spread over alternatives.
- **Confidence:** Single-source (quantified)
- **Phase scope:** signaling / mid-game
- **Numerical thresholds:** **~90%** after 2nd-tahreeb
- **[FOCUS]** Bot inference confidence should escalate from ~70% to ~90% when a confirming second tahreeb appears. Single-shot estimate is wrong.

### Rule 7: Two-time small-to-big tahreeb has 100% confidence, "not up for debate"
- **Source:** video 10 @ 00:00:17–00:00:23, @ 00:01:11–00:01:14, @ 00:05:05–00:05:10
- **Arabic phrase:** "اقوى تهريب في البلوت اذا كان التهريب من مرتين او اكثر" / "100% ما يبغى لها نقاش"
- **Rule (English):** When partner discards two cards of the same suit in **ascending order** (e.g. 7 then 8, or 7 then 9) across two consecutive tricks, this is the **strongest tahreeb signal** and has **100% confidence** that partner wants that suit. Speaker is emphatic: "this is a fixed rule, no debate". Same applies to 7→J or 8→J or 9→10 etc. as long as direction is small→big.
- **Confidence:** Definite
- **Hand-shape preconditions:** Partner must have at least 2 throwaway cards in the suit
- **Phase scope:** signaling
- **Numerical thresholds:** **100%** confidence after 2x small-to-big tahreeb
- **[FOCUS]** **Bot decision:** when this signal occurs, the bot should treat it as deterministic — return that suit when leading after partner takes a trick. If code applies the 70% prior here, it's underconfident.

### Rule 8: Direction encoding — small-to-big means WANT, big-to-small means DON'T-WANT
- **Source:** video 10 @ 00:00:55–00:01:06; video 01 @ 00:12:51–00:13:23 (mirror); @ 00:14:01 ("anti-burqia"); video 09 @ 00:02:58–00:03:02
- **Arabic phrase:** "من كبير لصغير معناته ما يبغى" / "من تحت لفوق ... يبغى نفس الشكل"
- **Rule (English):** **Direction is the encoding axis** for two-card tahreeb pairs. Two cards in **ascending** rank order across consecutive tricks = "I want this suit". Two cards in **descending** rank order = "I do NOT want this suit." This applies even to point-zero ranks (7-8-9) where the rank choice has no scoring effect — the **message** is the entire purpose.
- **Confidence:** Definite (multiple sources)
- **Hand-shape preconditions:** Partner has freedom to choose order (i.e. multiple discardable cards in suit)
- **Phase scope:** signaling
- **Numerical thresholds:** none — direction is binary
- **[FOCUS]** This is the **encoding axis** that the user mentions in the prompt. Code should distinguish the two directions, not collapse them to a single "tahreeb-with-suit-X" symbol.

### Rule 9: 7-then-8 ≠ 8-then-7 (direction is meaningful even with no points)
- **Source:** video 10 @ 00:04:46–00:05:00 (and the cold-open clip at 00:00:00–00:00:11)
- **Arabic phrase:** "ما تهرب ثمانيه بعدين سبعه ... هدفك الرساله ... عكس تماما"
- **Rule (English):** Even though 7-7-7 of side suits and 7/8/9 carry zero card-points, the ORDER you play them encodes the direction. Many casual players don't notice; expert pairs always sequence the cards to send the correct message.
- **Confidence:** Definite (stated twice, framed as a "language" rule)
- **Phase scope:** signaling
- **Numerical thresholds:** none

### Rule 10: When partner has the 10, partner should tahreeb WITH the 10 (top-down)
- **Source:** video 10 @ 00:01:34–00:01:46
- **Arabic phrase:** "اذا ما عندك العشره ... لو خويك عنده العشره المفروض يهرب لك العشره"
- **Rule (English):** Bottom-up tahreeb implicitly **denies** that you hold the 10 in the suit you want. If you DO have the 10, the correct play is to lead/discard the 10 itself (top-down) — that simultaneously says "I want this suit AND I have its 10" (~big-card "burqia" semantics, see Rule 21).
- **Confidence:** Definite
- **Hand-shape preconditions:** Has 10 of suit, wants suit returned
- **Phase scope:** signaling
- **Numerical thresholds:** none

### Rule 11: Bottom-up tahreeb requires forcing — it usually means "no other shape left"
- **Source:** video 10 @ 00:01:37–00:01:44
- **Arabic phrase:** "غالبا الناس يهربون هذا التهريب اذا ما كان عندهم مثلا الا هذا الشكل"
- **Rule (English):** Players often default to bottom-up tahreeb in the wanted suit when they have no choice (only that suit left to discard). The signal is therefore a **discoverable consequence** of partner being cut in the other side suits as well as wanting this one.
- **Confidence:** Common
- **Hand-shape preconditions:** Cut in alt-suits / forced
- **Phase scope:** signaling

### Rule 12: After a single tahreeb, if partner has not played a second tahreeb, that itself is a signal
- **Source:** video 09 @ 00:03:17–00:03:30
- **Arabic phrase:** "خويك ما راح يهرب لك تسعه في هذه المره راح يهربها عشان يفهمك"
- **Rule (English):** If partner had the option to confirm with a second tahreeb in trick 2 but did NOT (instead played a different suit / different signal), infer partner is cut in the second suit (e.g. partner is cut in Spades). Useful for narrowing the partner's hand.
- **Confidence:** Common
- **Phase scope:** signaling

### Rule 13: Partner-side response — when receiving a tahreeb-of-Ace, lead-back rule
- **Source:** video 02 @ 00:00:21–00:00:33; @ 00:00:46–00:00:51
- **Arabic phrase:** "اذا كان عندك العشره تك لحالها زي كذا فقط على طول روح بالعشره"
- **Rule (English):** When partner has tahreebed an A in your wanted suit, and you have a "lonely" 10 (no other cards beside it in that suit), **lead the 10 back immediately**. Reasoning: any opponent who plays will surely cut/raise it and steal the 10, so you must cash it before that happens.
- **Confidence:** Definite
- **Hand-shape preconditions:** "10 alone" (10 with no neighbor in suit)
- **Phase scope:** opening-lead / mid-game
- **Numerical thresholds:** none

### Rule 14: Partner-side — when 10 is "doubled" (مردوفه) with a neighbor card, hold/cover instead
- **Source:** video 02 @ 00:01:01–00:01:07; @ 00:05:12–00:05:18
- **Arabic phrase:** "لو العشره مردوفه زي كذا هنا حيختلف الوضع شويه" / "اذا كان عندك العشره معاها ورقتين او اكثر الافضل انك ما تروح بالعشره ... تروح بالثمانيه"
- **Rule (English):** If your 10 has at least one accompanying card in the same suit (a "ridfa" / مردوفه = doubled or supported 10), do NOT lead the 10. Instead lead a smaller neighbor (the 8 typically). Reason: the supporting card prevents an opponent from instantly stealing the 10. With 3 cards in suit (10 + 2 others), the rule strengthens — definitely lead a small one.
- **Confidence:** Definite
- **Hand-shape preconditions:** **2+ in suit including 10** (ridfa/doubled), or **3+ in suit including 10** (sard/سرد)
- **Phase scope:** opening-lead / mid-game
- **Numerical thresholds:** suit-length **2** vs **3+**

### Rule 15: When holding (10, 8) with no 9 ("8-next-to-10"), do NOT play the 8 in front position
- **Source:** video 02 @ 00:04:14–00:04:22
- **Arabic phrase:** "في شيء اسمه قليل الاذرع ... شيلها حتى لو خويك طلعت عنده لك"
- **Rule (English):** A 10 with the 8 next to it (and no 9) is "قليل الاذرع" (short of arms). Do not lead the 8 from front position; the 8 itself is unattractive and exposes the 10. Choose a different suit/option instead.
- **Confidence:** Single-source
- **Hand-shape preconditions:** Holding 10+8 with no 9
- **Phase scope:** opening-lead

### Rule 16: After buyer hint — if partner is the Sun-buyer, the Diamond-side response is more nuanced
- **Source:** video 02 @ 00:04:22–00:04:43
- **Arabic phrase:** "اذا خويه كان يشتري صن الافضل تروح شريحه"
- **Rule (English):** If partner bought Sun, partner cannot have an unbroken run in any single suit (Sun-buyers don't have a 5+ unbroken suit). So although partner's tahreeb suggests they want a particular suit "always", you can sometimes lead Hearts (شريحه) rather than the implied Diamond — partner may be holding a Heart group instead.
- **Confidence:** Single-source / Sometimes
- **Hand-shape preconditions:** Partner is Sun-buyer; you have your own constraint
- **Phase scope:** bidding-aware mid-game

### Rule 17: Reverse — if partner did NOT buy Sun, follow the basic tahreeb rule strictly
- **Source:** video 02 @ 00:04:37–00:04:43
- **Arabic phrase:** "لكن لو خويك ما كان مشتري ... تروح الافضل دائما تمام تمشي اكثر على التهريب"
- **Rule (English):** When partner is NOT the Sun buyer (i.e. one of the opponents bought, or YOU bought), the standard tahreeb-direction rule applies more strictly. Stay on the canonical tahreeb axis.
- **Confidence:** Single-source / Common
- **Phase scope:** bidding-aware mid-game

### Rule 18: مثلوث (mathlooth = three non-consecutive cards in a suit) — must lead the suit, can't hold
- **Source:** video 02 @ 00:05:43–00:06:50
- **Arabic phrase:** "مثلوث ما هو نفس المردوف بالتالي حتلعب الشريحه"
- **Rule (English):** A 3-card holding in the suit you want, where they are NOT a connected sequence (i.e. مثلوث "tripled but not stacked"), is weaker than a مردوفه (stacked pair). Partner playing 8 then 7 in that suit is fine; the 3-card non-stack means **you must lead the suit you want now and cannot hold it for later**.
- **Confidence:** Single-source
- **Hand-shape preconditions:** 3 non-consecutive cards in target suit
- **Phase scope:** opening-lead / mid-game

### Rule 19: When you tahreeb-of-A (the "burqia"), it carries an implicit "I have the SWA" meaning
- **Source:** video 01 @ 00:11:45–00:11:50; @ 00:03:42–00:03:50; video 02 (echoed)
- **Arabic phrase:** "البرقيه تكون اكه وتكون نفس الشكل اللي تبغاه ... معك سوا"
- **Rule (English):** Discarding the Ace as a tahreeb (called **بَرقيه / burqia**) means "I want this suit AND I have the SWA in it" (where SWA in this context means the cover-card / connected support). Speaker emphasizes the burqia must be **the Ace of the wanted suit**, not the Ace of an unrelated suit (which would be "wrong" / غلط).
- **Confidence:** Definite
- **Hand-shape preconditions:** Holding A of the wanted suit; ideally also support
- **Phase scope:** signaling
- **Numerical thresholds:** none
- **[FOCUS]** SWA semantics from this source: SWA = supporting cards, not necessarily a single card type. **Code-side SWA timing should NOT auto-fire on a burqia signal alone — the partner sends the burqia, the receiver responds with its 10/cover.** Verify how `Bot.PickSWA` interprets a partner-AKA-of-Ace.

### Rule 20: Burqia ≠ A-of-wrong-suit
- **Source:** video 01 @ 00:12:01–00:12:05
- **Arabic phrase:** "لو لعبت اكه الديمن غلط لانه ما عندك دي دائما"
- **Rule (English):** If you discard the A of Diamonds while wanting Clubs, you have NOT made a burqia — that's an error. The burqia is "Ace of the wanted suit". Wrong-suit-Ace is read by partner as "I want Diamonds always" (the literal first-tahreeb interpretation).
- **Confidence:** Definite
- **Phase scope:** signaling

### Rule 21: When partner plays burqia (A-tahreeb), receiver should respond IMMEDIATELY with that suit
- **Source:** video 01 @ 00:12:18–00:12:25
- **Arabic phrase:** "الاكه معناتها تعال على طول لا تاكل اكله ثانيه"
- **Rule (English):** Burqia means "come at once, don't grab a second trick first". Partner expects an immediate same-suit lead from the receiver, not an additional capture in another suit before responding.
- **Confidence:** Definite
- **Phase scope:** signaling / opening-lead
- **Numerical thresholds:** **first response trick** (immediacy)

### Rule 22: Partner can fail to follow a tahreeb for legitimate reasons (cut-in-suit etc.)
- **Source:** video 01 @ 00:05:39–00:06:09
- **Arabic phrase:** "اما انه خويك ما يعرف يلعب لسه مبتدئ ... او مثلا خويك ما عنده ... ما عنده التسعه"
- **Rule (English):** Partner may not return your tahreeb-suit if: (a) they're a beginner and don't read signals, (b) they weren't focused, (c) they're cut in the suit you wanted. The 70% number reflects this empirical failure rate.
- **Confidence:** Definite
- **Phase scope:** signaling / mid-game

### Rule 23: Form 1 — "same color, opposite shape" (نفس اللون عكس الشكل)
- **Source:** video 01 @ 00:07:34–00:07:38; example @ 00:07:46–00:09:09
- **Arabic phrase:** "نفس اللون وعكس الشكل"
- **Rule (English):** First named form: discard a card of the SAME color but OPPOSITE shape (Heart vs Diamond, both red). Encodes "I don't want this Hearts; I want Diamonds (the same-color other shape)". For a same-color pair of suits, large-to-small ordering preserves the "don't want" meaning.
- **Confidence:** Definite
- **Phase scope:** signaling

### Rule 24: Form 2 — "opposite color" (عكس اللون)
- **Source:** video 01 @ 00:09:12–00:09:20
- **Arabic phrase:** "عكس اللون يعني اهرب ورقه وانا ابغى عكس اللون"
- **Rule (English):** Second named form: discard a card of OPPOSITE color, indicating "I want one of the two suits in the OTHER color". Partner narrows further (see Rule 27).
- **Confidence:** Definite
- **Phase scope:** signaling

### Rule 25: Form 3 — two cards same-color (back-to-back) eliminates one color entirely
- **Source:** video 01 @ 00:10:12–00:10:18; example @ 00:10:24–00:11:11
- **Arabic phrase:** "اذا هربت لك ورقتين نفس اللون ابغى عكسه"
- **Rule (English):** Third form: when you discard two cards of the same color back-to-back across two tricks, you eliminate that entire color from your wanted set. Partner narrows to the other color and uses prior signals to pick the specific suit.
- **Confidence:** Definite
- **Phase scope:** signaling
- **Numerical thresholds:** **2 same-color discards** triggers full-color elimination

### Rule 26: Form 4 — burqia (A-on-trick-1 of wanted suit) — "I want THIS suit, come fast"
- **Source:** video 01 @ 00:11:13–00:12:25
- **Arabic phrase:** "البرقيه ... معك سوا"
- **Rule (English):** (See Rules 19–21.) A-as-tahreeb is its own named form.
- **Confidence:** Definite
- **Phase scope:** signaling

### Rule 27: Form 5 — small-to-big "I want SAME shape" (من تحت لفوق)
- **Source:** video 01 @ 00:12:32–00:13:23; entire video 10
- **Arabic phrase:** "تجي من نفس الشكل ... تحت لفوق"
- **Rule (English):** Fifth form: when you can't use the burqia (e.g. you don't have the A), you signal "want this suit" by discarding two side-suit cards in **small-to-big** order across two tricks. Direction matters intensely — see Rules 7–9.
- **Confidence:** Definite
- **Phase scope:** signaling

### Rule 28: When discarding "I don't want this", play the LARGEST first then smaller
- **Source:** video 01 @ 00:07:46–00:08:07; @ 00:09:32–00:10:09
- **Arabic phrase:** "تهريبك من فوق لتحت ... ترمي اول شيء اكبر ورقه من اللي ما تبغاه بعدين ترمي ثاني اصغر ورقه"
- **Rule (English):** When signaling "don't want", lead with the LARGEST disposable card in the unwanted suit and follow with a smaller one. Reverse direction (small first then big) sends the OPPOSITE message.
- **Confidence:** Definite
- **Phase scope:** signaling

### Rule 29: Special case — discard the Q rather than 9 to "give partner points"
- **Source:** video 01 @ 00:08:25–00:08:30
- **Arabic phrase:** "البنت فيها ثلاثه ابناط فانت تزود لنفسك ولخويك ابناط"
- **Rule (English):** When you have a choice between Q (3 points) and 9 (0 points) as the "first big card down", prefer the Q. Reasons: partner captures with their A or 10 and gets +3 points, plus the Q is unambiguously a "middle" rank card so the message is preserved.
- **Confidence:** Common
- **Hand-shape preconditions:** Holds Q + 9 in unwanted side suit
- **Phase scope:** signaling / scoring
- **Numerical thresholds:** Q = 3 pts vs 9 = 0 pts
- **[FOCUS]** **Scoring decision** that affects raw point distribution. If the bot scoring code only assigns points by trick winner, this rule simply reinforces "throw the Q" as the right card to **discard**, not change scoring math. But if a `Bot.PickPlay` / `pickFollow` heuristic counts "discard cost = card_points" and avoids the Q, it loses 3 pts to bad heuristic.

### Rule 30: When holding (10, J, Q) or similar valuable tail, DON'T discard the 10
- **Source:** video 01 @ 00:09:32–00:09:46
- **Arabic phrase:** "تلعب العشره لانه فيها 10 ابنات زياده الشايب اربع ناط فقط"
- **Rule (English):** Speaker rephrases the same scoring point: 10 is worth 10 raw points, J only 4. When forced to discard, prefer the card with FEWER points to your unwanted suit signal — keep the 10 OFF the discard pile.
- **Confidence:** Common
- **Hand-shape preconditions:** 10 in an unwanted suit context
- **Phase scope:** scoring / signaling
- **Numerical thresholds:** **10 pts** vs **4 pts**
- **[FOCUS]** **Score calculation:** these are non-trump rank values stated explicitly. Verify `R.ScoreRound` constants for non-trump (10=10, J=4 in Ahkam non-trump? — depends on contract). The speaker's "10 ابنات / 4 ابنات" should be cross-checked against the Saudi point table.

### Rule 31: On any first-trick lead, opponents assume you LEAD YOUR STRENGTH
- **Source:** video 02 @ 00:02:31–00:02:43
- **Arabic phrase:** "في البدايه هيلعب قوته ... الاغلب هيفترضوا انه عندك العشره"
- **Rule (English):** Standard convention: a player leading a suit at trick 1 is assumed to be holding the suit's strength (most likely the 10 of that suit). Opponents may "tafarnak" (تفرنك = trump-cut early to steal) based on this inference.
- **Confidence:** Definite
- **Phase scope:** opening-lead / opponent-modelling
- **Numerical thresholds:** none

### Rule 32: Partner reading — every card you play must have a reason
- **Source:** video 01 @ 00:00:18–00:00:28
- **Arabic phrase:** "اي ورقه راح تلعبها لازم يكون لها معنى او لازم يكون لها سبب"
- **Rule (English):** Universal rule: there is no "neutral" card in Baloot — every play sends information. This frames why mis-direction in tahreeb is so costly.
- **Confidence:** Definite (axiom)
- **Phase scope:** all

### Rule 33: Tahreeb is ALSO a memory game — must track played cards
- **Source:** video 01 @ 00:01:43–00:02:08
- **Arabic phrase:** "لازم تكون عارف الورق اللي نزل واللي ما نزل ... كله هذا لازم تعرفه"
- **Rule (English):** A competent tahreeb-reader has tracked which cards have been played in earlier tricks. The speaker calls this "the difference between professional and casual players".
- **Confidence:** Definite
- **Phase scope:** signaling / mid-game

### Rule 34: With 3 cards left and partner just won, immediately discard your largest non-want
- **Source:** video 01 @ 00:00:43–00:00:54; example carries the entire video
- **Arabic phrase:** "كل واحد متبقي في يده اخر ثلاث اوراق"
- **Rule (English):** A common late-trick scenario: 3 cards in hand, partner just took a trick. The discard you make is read by the entire table as a tahreeb signal. Speaker spends the bulk of video 01 walking through this exact 3-card / partner-leads-next configuration.
- **Confidence:** Definite (the foundational scenario)
- **Hand-shape preconditions:** **exactly 3 cards in hand** (i.e. trick-6 onward in 8-trick game)
- **Phase scope:** mid-game / endgame

### Rule 35: Order matters — in two-card opposite-shape, large-then-small encodes "don't want"
- **Source:** video 01 @ 00:08:01–00:08:25
- **Arabic phrase:** "تلعب التسعه غلط اذا عندك التسعه لحالها ... تلعب اكبر شيء عندك البنت"
- **Rule (English):** Within Form 1 (same color, opposite shape), if you have BOTH Q and 9 of the unwanted suit, play Q first (the bigger). Playing 9 first is wrong because order encodes meaning.
- **Confidence:** Definite
- **Phase scope:** signaling
- **Numerical thresholds:** Q (3) > 9 (0) — direction by card-value not just rank-index

### Rule 36: Single non-Ace tahreeb of (e.g.) Diamond → 70% Clubs preference (= "wants the same color's other shape")
- **Source:** video 09 @ 00:01:20–00:01:34
- **Arabic phrase:** "حفترض خويه يبغى هاس مثلا بنسبه 70%"
- **Rule (English):** Restating Rule 5 with the suit-mapping: if partner discards a Diamond, partner most likely (70%) wants Clubs. Speaker explicitly mentions Clubs (هاس) here — implying the convention is **opposite-color partner-preference is the dominant interpretation** when only one tahreeb is seen.
- **Confidence:** Single-source / quantified
- **Phase scope:** signaling

### Rule 37: AKA (الاكا) is signal in form 4 — note "the AKA" terminology
- **Source:** video 01 @ 00:01:46–00:01:48 (incidental); throughout videos
- **Arabic phrase:** "زي الاكا العشره هذه تكون عارفها"
- **Rule (English):** Speaker uses "الاكا" both as a card name (the Ace) and as a signal. **Burqia (the form 4 named tahreeb) is essentially "the AKA call"** — Ace-of-wanted-suit, "come immediately". This connects the strategy term AKA directly to the burqia.
- **Confidence:** Definite (terminology)
- **Phase scope:** signaling / glossary
- **[FOCUS]** Maps to code: `K.AKA*` and `Bot.PickAKA`. Verify the code's AKA semantics match this — the AKA call is **a burqia of the wanted suit**, and the receiver's correct response is to lead the wanted suit ASAP.

### Rule 38: When opponent plays small-to-big tahreeb, treat as "they want suit X — DON'T lead it"
- **Source:** video 10 @ 00:05:21–00:05:42
- **Arabic phrase:** "لو الخصم هرب من تحت لفوق لازم تفهم انه يبغى نفس الشكل"
- **Rule (English):** Same direction-encoding rule applies symmetrically: if an OPPONENT shows a small-to-big tahreeb, infer they want that suit. Therefore **do not lead that suit** unless you've seen partner's tahreeb saying they want it.
- **Confidence:** Definite
- **Phase scope:** signaling / opponent-modelling / opening-lead
- **[FOCUS]** **Bot decision-making** — bot should refuse to lead a suit an opponent has just small-to-big-tahreebed.

### Rule 39: A "lonely" 10 in the suit-of-tahreeb can still be lost if partner doesn't have the supporting card
- **Source:** video 02 @ 00:03:55–00:04:01
- **Arabic phrase:** "ما عندك سوا فحيجيك سبيد وحتاكل حله واحده بس"
- **Rule (English):** If you tahreeb-of-A but don't have the SWA / supporting card in suit, partner returns and you only capture one trick. You don't get the burqia's full value.
- **Confidence:** Single-source
- **Hand-shape preconditions:** A only (no 10 or other support) in burqia suit
- **Phase scope:** signaling / mid-game
- **[FOCUS]** Reinforces SWA semantics in the source: SWA refers to supporting/connected cards, NOT the named "SWA permission flow" mentioned in CLAUDE.md. **Same Arabic word, different referent in code vs source.** Phase 2 should disambiguate.

### Rule 40: Reverse-direction tahreeb (J then 8) = explicit "I do NOT want this suit"
- **Source:** video 10 @ 00:00:55–00:01:06; video 09 @ 00:02:58–00:03:02
- **Arabic phrase:** "لو هرب في البدايه الولد وبعدين هرب الثمانيه ... من كبير لصغير معناته ما يبغى بالشكل هذا"
- **Rule (English):** Partner playing J in trick 1 then 8 in trick 2 is the inverted form of Rule 7. Confirmation: partner does NOT want this suit. Both trick-1 and trick-2 cards must be read TOGETHER — single trick-1 J alone is ambiguous.
- **Confidence:** Definite
- **Phase scope:** signaling

### Rule 41: Ascending direction across same-suit pair → 100% confidence; mixed direction → confused/unreadable
- **Source:** video 10 @ 00:04:18–00:04:22
- **Arabic phrase:** "هنا حيتلخبط او ما حيفهم"
- **Rule (English):** If a player plays e.g. 7 (small-to-big start), then later 9 (looks like big-to-small), partner gets confused. Speaker advises a clean ordered pair only — never mix.
- **Confidence:** Single-source
- **Phase scope:** signaling

### Rule 42: Last trick (الاخيري) is +10 raw points
- **Source:** video 01 @ 00:03:01–00:03:03; video 02 (echoed)
- **Arabic phrase:** "الاخيري قلنا في 10 ابناط زياده"
- **Rule (English):** Whoever wins the last trick scores +10 bonus raw points. This is referenced multiple times as a standard fact.
- **Confidence:** Definite
- **Phase scope:** scoring / endgame
- **Numerical thresholds:** **+10**
- **[FOCUS]** **Scoring** — matches CLAUDE.md "Last trick = +10 raw". Cross-check `R.ScoreRound` for the +10 last-trick bonus.

### Rule 43: With (10, A, J) in your strong suit, tahreeb-of-A is wrong; lead the suit instead
- **Source:** video 02 @ 00:00:21–00:00:51
- **Arabic phrase:** "اذا كان عندك العشره تك لحالها زي كذا فقط على طول روح بالعشره"
- **Rule (English):** A 3-card holding of (A, K(=J?), Q…) where you'd normally tahreeb the A — but if you also hold the 10 LONELY, just lead the 10. The burqia would over-signal.
- **Confidence:** Single-source
- **Phase scope:** opening-lead

### Rule 44: Holding the strong card while partner is winning → don't "تمسك" (don't hold-back); release for partner
- **Source:** video 02 @ 00:03:18–00:03:24
- **Arabic phrase:** "ما تبغى تمسك لعب انت خلاص اكلت اللي عليك هنا تمام تبغى تروح لخويك"
- **Rule (English):** When partner is winning the current trick, do NOT clutch/hold a high-value card; play it out so partner can return / continue. Holding ("masak") is wasted protection.
- **Confidence:** Common
- **Phase scope:** mid-game

### Rule 45: When you can't decide between buying-back (شراء) and tahreeb, default to tahreeb rules
- **Source:** video 02 @ 00:01:55–00:02:03
- **Arabic phrase:** "انت ما مشيت على اصول التهريب او على قواعد التهريب"
- **Rule (English):** If you choose "buy" (covering / pre-empting opponent capture) over correct tahreeb-direction, you violate the tahreeb canon. Speaker frames this as a player error.
- **Confidence:** Single-source
- **Phase scope:** mid-game

### Rule 46: 100% partner-wins precondition — if uncertain, you're in tanfeer territory
- **Source:** video 03 @ 00:00:07–00:00:24
- **Arabic phrase:** "لازم خويك يكون ماكل حل مئه في الميه ... 100%"
- **Rule (English):** Re-emphasises Rule 1 — only when partner's win is **mathematically guaranteed** (100%) is the discard a "tahreeb". Anything less, even highly likely, falls into the boundary case (Rule 3).
- **Confidence:** Definite
- **Phase scope:** signaling
- **Numerical thresholds:** **100%** strict

### Rule 47: Hand-strength classification: Weak / Medium / Strong determines tahreeb form selection
- **Source:** video 03 @ 00:02:18–00:03:13
- **Arabic phrase:** "ثلاثه فئات ... الورقه الضعيفه ... ورق متوسط ... من الفئه القويه"
- **Rule (English):** When deciding which card to discard:
  - **Weak hand** (no A, no key 10) → it's impossible to discard "for points" so you discard whatever you can; this defaults to the standard tahreeb-rule.
  - **Medium hand** (≥1 A, no run) → discard your "least useful" non-A card following tahreeb canon to message direction.
  - **Strong hand** (you bought / have run) → you may DELIBERATELY play `tahreeb` (Spades-of-Hearts) to signal a particular suit, even at the cost of holding it back, because you don't NEED partner's return.
- **Confidence:** Single-source
- **Phase scope:** signaling / decision tree

### Rule 48: When partner is cut in the wanted suit, partner returns the OPPOSITE-color suit
- **Source:** video 10 @ 00:02:43–00:02:50
- **Arabic phrase:** "خويك قاطع في الدائمه يعني ما عنده دائما واعطاك شريه يعني ما يبغى شريه"
- **Rule (English):** If partner is cut in suit X (proven by partner discarding in suit X earlier), and partner now discards a card of suit Y, infer partner doesn't want Y either — then partner wants the third option (one of the two remaining suits). Cross-elimination.
- **Confidence:** Single-source
- **Phase scope:** signaling

### Rule 49: Smaller cards (7, 8, 9) raise probability that partner will tahreeb low-to-high
- **Source:** video 10 @ 00:03:18–00:03:22
- **Arabic phrase:** "السبعه الثمانيه التسعه كل ما يصغر الورق كل ما تفترض انه ممكن يهرب لك من تحت لفوق"
- **Rule (English):** The smaller the card partner discarded, the more likely the discard is the START of a small-to-big sequence (since they're keeping the bigger cards for the next trick). For ranks like J or 10 in trick 1, this assumption doesn't apply.
- **Confidence:** Single-source
- **Phase scope:** signaling / opponent-modelling

### Rule 50: Optimal small-to-big sequence — discard the SMALLEST two cards in suit
- **Source:** video 10 @ 00:04:25–00:04:31
- **Arabic phrase:** "العب سبعه وبعدين تسعه يعني العب اصغر ورقتين ورا بعض"
- **Rule (English):** When sending a small-to-big tahreeb, use the two SMALLEST throwaway cards in the suit (e.g. 7 then 9 if you don't have the 8). This maximises the unambiguity and cleanly preserves higher-rank cards for future captures.
- **Confidence:** Single-source
- **Phase scope:** signaling

### Rule 51: 7-then-J vs 7-then-9 — both work, 100% in either ordering
- **Source:** video 10 @ 00:05:05–00:05:10
- **Arabic phrase:** "نسبه نجاحه 100% سواء سبعه بعدها ثمانيه او سبعه بعدها تسعه"
- **Rule (English):** Direction (small-to-big) carries the meaning, not the specific size of the gap. 7-then-8 = 7-then-9 = same encoding, both 100% confidence.
- **Confidence:** Definite
- **Phase scope:** signaling

### Rule 52: 3rd-tahreeb scenario — if partner can tahreeb a third time, you should bottom-up correctly even if it costs the J
- **Source:** video 10 @ 00:04:05–00:04:13
- **Arabic phrase:** "تضطر تهرب اما الشايب او السبعه وقلنا الشايب تمسك فيه"
- **Rule (English):** When partner needs to send a 3rd tahreeb and only J + small are left, discard the small (preserve the J) — opponent could pick up the J otherwise. Holds J for capture potential.
- **Confidence:** Single-source
- **Phase scope:** signaling / endgame

### Rule 53: Order signals matter even with identical card values
- **Source:** video 10 @ 00:04:46–00:05:00 (cold-open repeat)
- **Arabic phrase:** "ما تهرب ثمانيه بعدين سبعه ... هدفك الرساله"
- **Rule (English):** When 7 and 8 both score zero and you have a free choice of order, choose the order that conveys the right direction. Trick economics are 0 either way; signaling economics differ enormously.
- **Confidence:** Definite
- **Phase scope:** signaling

### Rule 54: After ≥3 tahreebs without confirming partner-return, accept the message is lost
- **Source:** video 09 @ 00:04:11–00:04:43
- **Arabic phrase:** "خويك لو مثلا ما هرب لك السبع هنا هرب لك عشره السبيل هنا واضح انه ما يبغى"
- **Rule (English):** A third-trick discard from partner can flip the interpretation if partner uses the 10 as discard (signaling new direction). The pattern (7 → 9 → 10 of a different suit) explicitly cancels prior signals about the first suit.
- **Confidence:** Single-source
- **Phase scope:** signaling

### Rule 55: First tahreeb is "primary message", second is "confirm or revise"
- **Source:** video 09 @ 00:02:00–00:02:09
- **Arabic phrase:** "كل ما تهرب اكثر من مره كل ما يزيد او كل ما تتاكد"
- **Rule (English):** Confidence in the inferred wanted-suit accumulates with each successive tahreeb from partner. Single tahreeb = "guess"; double tahreeb = "confirmed".
- **Confidence:** Definite
- **Phase scope:** signaling

### Rule 56: When forced to lead and partner's signal is ambiguous, lead the largest disposable card you have
- **Source:** video 09 @ 00:02:15–00:02:25
- **Arabic phrase:** "هذا فن تروح بالورقه الكبيره"
- **Rule (English):** Speaker calls it an "art": when partner's signal isn't clear AND you must initiate the next trick, lead with your largest non-trump throwaway (signals "I have power here" — alternative interpretation by partner).
- **Confidence:** Common
- **Phase scope:** opening-lead

### Rule 57: Tahreeb works on the assumption opponents follow the same rules — exploitability
- **Source:** video 03 (implicit throughout); video 02 @ 00:02:55–00:03:15
- **Arabic phrase:** "حيفترض انه انت معاك العشره بالتالي حيروح شكل اخر"
- **Rule (English):** Expert opponents read your signals too. They will "tafarnak" (cut your big card) preemptively, switch suits, or set up traps based on your tahreeb. Rule isn't unidirectional.
- **Confidence:** Common
- **Phase scope:** signaling / opponent-modelling

### Rule 58: Bargiya/burqia = tahreeb-of-single-Ace; "full Tahreeb" = tahreeb of 2+ events
- **Source:** video 01 @ 00:11:42–00:12:25 (form-4 named "burqia"); video 09 @ 00:00:43–00:00:53 (forms enumerated)
- **Arabic phrase:** "الاكه البرقيه" / "تهريب يحتاج تهريب مره ثانيه"
- **Rule (English):** Speakers do NOT use the word "Bargiya" explicitly in this cluster, but the form-4 = burqia and is the SINGLE-Ace-event signal. Forms 1, 2, 3, 5 require **2+ events** (a same-color pair, a same-suit pair, or two opposite-color discards). The classification axis is therefore **EVENT-COUNT** (single A = burqia/AKA; multi-card = directional tahreeb), NOT hand-shape (محشور).
- **Confidence:** Definite (cross-source consistent)
- **Phase scope:** signaling / classification
- **[FOCUS]** **Code-side classification**: if `WHEREDNGN` distinguishes Bargiya vs full-Tahreeb by hand-shape (e.g. "5+ in suit"), the source disagrees — the axis is event-count.

### Rule 59: Not a single-source 5-card-suit precondition for ANY tahreeb form
- **Source:** none — *absence* across videos 01, 02, 03, 09, 10
- **Rule (English):** The speakers never state "5+ cards in the suit" as a precondition for tahreeb. The hand-shape factor that DOES appear is the local 2-card or 3-card structure (مردوفه, سرد, مثلوث) of the suit being discarded.
- **Confidence:** Negative observation across all 5 sources
- **Phase scope:** classification
- **[FOCUS]** **Bot decision** — if the code requires "5+ in suit AND has-A" before treating a discard as a Bargiya/burqia, that's stricter than the source. Source classification is event-count + cards-discarded, not hand-shape.

### Rule 60: Partner-side response — if 10 is in a 3-card holding (sard/سرد), still lead the small one (8) first
- **Source:** video 02 @ 00:05:43–00:06:50
- **Arabic phrase:** "اذا كان سرد حيكون ثلاثه اوراق نفس اللي عندك ولو رجعنا"
- **Rule (English):** Sard = 3-card holding in suit. Same logic as ridfa: lead the smallest of the 3, return to partner via that suit; you won't lose the 10 because your 2 supporting cards block opponent from cutting.
- **Confidence:** Single-source
- **Hand-shape preconditions:** 3-card suit holding
- **Phase scope:** opening-lead

### Rule 61: Sun-buyer-implied rules: Sun buyer cannot have a "sard" (run) in a single suit
- **Source:** video 02 @ 00:01:18–00:01:30
- **Arabic phrase:** "خويك مشتري صن معقول يشتري على لون واحد فقط ... دائما ولا عنده العشره"
- **Rule (English):** Sun buyers must have wide distribution. The speaker uses "Sun buyer cannot have a long run in one suit" to deduce partner doesn't have a 5+ Diamond run when partner bought Sun. Useful for narrowing partner's holdings.
- **Confidence:** Single-source
- **Hand-shape preconditions:** Partner = Sun buyer
- **Phase scope:** bidding-aware reading
- **[FOCUS]** **Bot decision** — when reading partner-as-Sun-buyer, opponent-model should rule out 5+ unbroken suits.

### Rule 62: Beware the 10-cap — opponents will play J or Q to "catch" your lonely 10 if you protect-lead
- **Source:** video 02 @ 00:03:24–00:03:31
- **Arabic phrase:** "يكون عنده شايب الدي او بنت الدايمن ويقدر ياكل فيها فانت لو مسكت بالعشره هتخرب عليه"
- **Rule (English):** If you "hold" your 10 (don't lead it after a tahreeb call), opponent may play J or Q from a different group, capturing your 10 once you're forced to discard it. Better to release the 10 to partner immediately.
- **Confidence:** Single-source
- **Phase scope:** mid-game / endgame

### Rule 63: When partner has tahreebed two cards same-suit and you can lead, ALWAYS lead with the 10
- **Source:** video 10 @ 00:01:53–00:01:58
- **Arabic phrase:** "تروح له بالورقه الكبيره اللي عندك واذا كانت 10 جدا كويس روح له بالعشره"
- **Rule (English):** When responding to two-time small-to-big, lead with your highest card in the wanted suit. If that's the 10, even better — it cashes the 10 immediately and confirms the message back.
- **Confidence:** Definite
- **Phase scope:** opening-lead

### Rule 64: Two-time small-to-big tahreeb can also be inferred from a single discard if hand pattern fits
- **Source:** video 10 @ 00:01:58–00:03:30
- **Arabic phrase:** "هل ممكن تتوقع هذا التهريب من مره واحده"
- **Rule (English):** When partner has only one trick to discard before you must lead, a SINGLE discard can be classified as "small-to-big intent" if it's a low rank (7, 8, 9). Speaker says: "smaller card → assume bottom-up direction" with corresponding probability.
- **Confidence:** Single-source
- **Phase scope:** signaling / opening-lead
- **Numerical thresholds:** card rank ≤9 raises bottom-up prior

### Rule 65: When you have small-to-big partner tahreeb but NO suit yourself, lead a "Hearts" placeholder
- **Source:** video 10 @ 00:02:37–00:02:49
- **Arabic phrase:** "ورقك مثلا كان هنا دائما صغير ... فانت بالتالي هذا التهريب لغيته اللي هو عكس الشكل ما عندك ... ممكن تلعب شريه"
- **Rule (English):** If you cannot follow partner's wanted-suit (cut yourself), the "opposite shape" (Form 1) interpretation is also dead. Lead the suit partner already SHOWED (e.g. Hearts) since at minimum partner is cut there too — opponents may be cut as well, allowing a free trick.
- **Confidence:** Single-source
- **Phase scope:** opening-lead

### Rule 66: When in doubt, lead the AKA/burqia of your strongest suit to clarify
- **Source:** video 09 @ 00:00:50–00:01:00; video 01 @ 00:11:42 (forms)
- **Arabic phrase:** "اذا خويك هرب لك ورقه ... معناته تقريبا الاكه البرقيه وتهريب من تحت لفوق"
- **Rule (English):** "Burqia" and "small-to-big from-below" are the strongest, most-clarifying signals available. When you must initiate ambiguously, prefer one of these forms.
- **Confidence:** Common
- **Phase scope:** signaling

### Rule 67: 10-of-Diamond as discard messages "I want Clubs" with very high confidence
- **Source:** video 09 @ 00:06:24–00:06:33
- **Arabic phrase:** "العشره لمن تهربها غير لما تهرب البنت ... ابغى هاوس بنسبه كبيره"
- **Rule (English):** Discarding the 10 (rather than Q) of Diamonds is itself a stronger message. The 10 is a 10-point sacrifice, so the signal carries premium weight — partner reads it as "I want Clubs (هاوس) with very high confidence".
- **Confidence:** Single-source
- **Phase scope:** signaling
- **Numerical thresholds:** rank-of-discard correlates with signal-strength

### Rule 68: Throw-the-7 first when the 7 is "lonely" (no neighbors in suit) is the biggest mistake
- **Source:** video 09 @ 00:06:08–00:06:16
- **Arabic phrase:** "هذا اكبر غلط في البلد يعني تكون مردوفه تلعب مثلا الورقه اللي جنبها"
- **Rule (English):** The 7 sitting alone (no 8 next to it, no other support) should NOT be the first card you lead — opponent will simply cut it. Lead the supporting card instead (or a different suit entirely).
- **Confidence:** Single-source
- **Phase scope:** opening-lead

### Rule 69: Tahreeb is not restricted to endgame — can occur from trick 1
- **Source:** video 01 @ 00:06:47–00:06:53
- **Arabic phrase:** "التهريب مش شرط يكون اخر الجيم ممكن يكون في بدايه الجيم عادي"
- **Rule (English):** Tahreeb signaling can begin in trick 1 and continues all game. The "must be late game" intuition is wrong.
- **Confidence:** Definite
- **Phase scope:** all phases
- **[FOCUS]** **Bot decision** — if the bot only checks for tahreeb in late-trick states (e.g. trick > 4), it misses early-game signals.

### Rule 70: Partner must currently be winning the trick — not just "likely to win it"
- **Source:** video 03 @ 00:00:10–00:00:17
- **Arabic phrase:** "لازم خويك يكون ماكل حل مئه في الميه"
- **Rule (English):** "Will-take-this-trick = 100%" is the strict precondition. Even high-probability ≠ 100% places you in the boundary case (Rule 3) requiring tahreeb-default behaviour. This eliminates the gray middle.
- **Confidence:** Definite
- **Phase scope:** signaling

---

## Cross-source conflicts within this batch

1. **70/25/5 vs 90/10 prior shift after 2nd tahreeb** — Video 09 @ 00:01:22 says "70%/25%/5%" for ONE tahreeb of Diamond. Video 09 @ 00:03:09 then says "90%" after a SECOND tahreeb of the same suit. These don't conflict but DO need to be applied conditionally on tahreeb-count.

2. **100% confidence vs ~70% confidence** — Video 09 @ 00:01:22 frames any tahreeb as 70% reliable. Video 10 @ 00:01:11 says two-time small-to-big is 100% "no debate". These are NOT in conflict — they apply at different signal-counts (1 vs 2). Code should handle the count-dependent ramp-up.

3. **"Lead with biggest" vs "lead with smallest"** — Video 01 @ 00:09:32 says "play biggest first when discarding what you don't want". Video 10 @ 00:04:25 says "play smallest two when sending small-to-big want signal". These are opposite **purposes** (don't-want vs want) → no conflict, but a naive single-rule implementation would clash.

4. **"Burqia is form 4" vs "burqia is the burqia"** — Video 01 enumerates burqia as the 4th form (form 4: A-as-tahreeb). Video 09 calls it the first thing you should infer. Both consistent — burqia just gets prioritised at trick 1 because the A "trumps" all other reads.

5. **Sun-buyer no-run vs general no-restriction** — Video 02 @ 00:01:18 says Sun buyers can't have a 5+ run. No other source contradicts; this is an inference-only rule that requires cross-checking the saudi-rules.md file.

---

## Open ambiguities

1. **What exactly is "SWA" in source-speak vs code-speak?** — Source uses "سوا" (literally "together"/"alongside") to mean **a supporting card with the A** (i.e. a 10 or other connected card). The CLAUDE.md definition of SWA refers to a permission-flow protocol (≤3 cards = instant claim, 4+ = 5-second auto-approve). Different referent. **Phase 2 must clarify which the code's `Bot.PickSWA` is enforcing.**

2. **"Bargiya" word never appears in transcripts** — Speakers use **burqia** (بَرقيه, spelled برقيه) for the form-4 signal. The user's prompt asks if Bargiya ≠ burqia or are synonyms. From this cluster, NO instance of "Bargiya" — only burqia.

3. **"AKA" terminology** — Speakers occasionally use "الاكا" but it's ambiguous whether they mean (a) the Ace-the-card, (b) the partner-direction signal, or (c) both. Glossary cross-check needed against `K.AKA*` in Constants.lua.

4. **"محشور" hand-shape NOT mentioned** — User asked about hand-shape (محشور) vs event-count axis. Hand-shape word does not appear in any of these 5 transcripts. Sources frame everything via event-count. This may be addressed in other clusters / sources.

5. **What counts as "tafarnak" (تفرنك)** — Speakers use it for "opponent cuts to steal", but the exact precondition (does it require trump? does it require seeing your 10? etc.) is not formally defined.

6. **Last-trick +10 timing** — Source confirms the +10 bonus exists; doesn't specify whether it's applied before or after Belote bonuses, multipliers etc. (Critical for code cross-ref.)

7. **Whether tahreeb-form 2 ("opposite color") REQUIRES a confirming second discard** — Speaker says it can be inferred from one discard but isn't explicit about confidence — speaker is ambiguous between "single tahreeb hint" and "needs 2nd to confirm".

8. **Q-vs-9 discard preference under tanfeer** — Speakers cover the "tahreeb" direction extensively; tanfeer's discard-rank choice is not detailed in this cluster.

9. **Whether "memorize all played cards" is a soft or hard rule** — Speaker calls it "the difference between professional and casual" — implying it's not strict but advisable. No bot-implementation guidance.

---

## Notes for cross-referencer (Phase 2)

### High-priority cross-references to verify in code

- **`Bot.PickAKA` / `Bot.PickPlay` priors:** Should incorporate the **70/25/5 split** for one-time tahreeb (Rule 5/36) and **~90% / 100%** ramp-up after 2 tahreebs (Rule 6/7). If a single static probability is used, this is wrong.

- **`Bot.PickSWA`:** Source's "SWA" = supporting card with the A in burqia context. Code's "SWA" = ≤3 vs ≥4 card permission flow. **Same Arabic root, two different semantic referents.** Verify the Saudi-correct semantics of `Bot.PickSWA` aren't conflating the two.

- **Direction encoding (Rule 8):** Code MUST distinguish small-to-big from big-to-small in tahreeb-pair detection. Collapsing them to "tahreeb-suit-X" loses 100% of the information — Rules 7, 8, 9 hinge on direction.

- **Trick-1 vs late-trick tahreeb (Rule 69):** If `Bot.PickPlay` only enables tahreeb logic past a trick threshold, it misses early-game signals.

- **Burqia → AKA mapping:** The form-4 burqia is the AKA call. Verify `Bot.PickAKA` triggers on partner's first-trick A-discard → receiver-side immediate same-suit lead (Rule 21).

- **Last-trick +10 (Rule 42):** Cross-check `R.ScoreRound` for the bonus calculation order vs Belote multipliers (CLAUDE.md says Belote is multiplier-immune; +10 last-trick interaction not specified by source).

- **Card values in side suits (Rule 30):** 10 = 10 pts, J = 4 pts in non-trump per source. Verify `Constants.lua` non-trump rank-value table.

### Medium-priority cross-references

- **Sun-buyer no-run inference (Rule 61):** If `Bot.PickPlay` opponent-model includes "partner-bid-Sun → no 5+ unbroken suit", confirm. If absent, this is a missed inference.

- **Hand-shape vs event-count classification of Bargiya/burqia (Rule 58, 59):** The axis is event-count. If code uses hand-shape (e.g. "5+ in suit AND A → Bargiya"), this is stricter than source.

- **Partner-cut inference (Rule 12, 48):** Cross-elimination logic — useful for `BotMaster.PickPlay` ISMCTS opponent-model.

- **"Don't lead opp's tahreebed suit" (Rule 38):** Should be in `pickLead` heuristics.

### Definitions to add to `glossary.md` from this cluster

- **بَرقيه (burqia)** — form-4 tahreeb: A-of-wanted-suit, "come immediately"; equivalent to AKA call.
- **مردوفه (ridfa / madroofa)** — a doubled 10 (10 + neighbor in same suit); changes lead-back rule.
- **سرد (sard)** — 3-card holding in a suit, all-stacked.
- **مثلوث (mathlooth)** — 3-card holding in a suit, NOT consecutive.
- **تفرنك (tafarnak)** — opponent cuts/trumps preemptively to steal expected high.
- **شراء (sharaa)** — "buying back" / covering = pre-emptively releasing a high card to prevent opponent capture.
- **التنفيذ (tanfeer/tanfeedh)** — opposite-of-tahreeb signal axis (opponent-wins-trick context).
- **قليل الاذرع (qalil al-adraa)** — "short of arms" — describes the 10+8-no-9 pattern, weak.
- **انيرجي / انرجي (energy)** — speaker is "Energy"; channel-naming, not a rule.

### Calibration confidence

- 5 transcripts, all from the same speaker ("Energy"). **Same-source consistency is high** but cross-speaker calibration cannot be done within this cluster.
- Rule confidences labeled "Definite" appear in 2+ transcripts OR are framed as axiomatic by the speaker.
- "Single-source" rules need confirmation from other clusters before being treated as canon.

### Counts

- Total rules extracted: **70** (+ 9 glossary terms).
- Conflicts noted: 5 (all reconcilable on closer reading).
- Open ambiguities flagged for Phase 2: 9.
- **[FOCUS]** tags applied: 14 (the user's stated focus areas — SWA semantics, scoring math, bot decision priors).
