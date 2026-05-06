# Source B — Bargiya + Discover-via-Tahreeb (videos 14, 19)

## Coverage map

| Video | Title slug | Primary topics covered | Touched (secondary) topics |
|---|---|---|---|
| 14 | bargiya_ace_tahreeb | Bargiya/Tahreeb-Aka (sacrifice an Ace), partner-discover via Bargiya, when receiver should dash to partner immediately vs eat first, end-of-game vs early-game asymmetry, hand-shape-as-trigger | SWA inference (`عنده سوا`), opening leads (high card from sequence), AKA (`الاكا`) signaling, Sun-side Bargiya situations, Kaboot setup, partner-misread risk |
| 19 | discover_via_tahreeb | Tanfeer (`تنفير` — opponent throwaway) vs Tahreeb (`تهريب` — partner sacrifice) distinction, the 6 Tanfeer-inference factors (game progress, card rank, two-cards-same-suit, both-opponents-same-suit, suit-switch, who-bought-the-bid), the "always assume worst" inversion principle | Bargiya bullet definition, opening-lead inference, Sun/Hokm bidder card-strength assumption, "Akah" treated as exception (Tanfeer of Ace = stranded) |

**Note on scope:** Video 14 frames itself as a Bargiya tutorial but spends >50% of runtime on receiver-side decision logic (when to dash to partner vs eat extra tricks first), which has direct SWA timing and bot-decision implications. Video 19 frames itself as Tanfeer (opponent-discard reading) but the final third develops a generalized "assume the worst → favor Tahreeb interpretation" decision principle that overrides Tanfeer when Tahreeb interpretation is also live.

## Rules extracted

### Rule 1: Bargiya is the strongest convention in Baloot
- **Source:** video 14 @ 00:00:02 – 00:00:13
- **Arabic phrase (verbatim, ≤15 words):** "اقوى تهريب في البلوت الا وهو تهريب الاكه او البرقيه"
- **Rule (English):** Bargiya (Tahreeb of the Ace, also called "Tabreek") is the single highest-confidence partner signal in Saudi Baloot. The speaker labels it the "strongest Tahreeb" with the highest success rate of all conventions.
- **Confidence (per source):** Definite
- **Hand-shape preconditions:** n/a (definitional)
- **Phase scope:** signaling
- **Numerical thresholds:** n/a

### Rule 2: Bargiya success rate ~90%
- **Source:** video 14 @ 00:01:43 – 00:01:46
- **Arabic phrase (verbatim, ≤15 words):** "نسبه نجاحه وتسعين في المئه"
- **Rule (English):** When partner sends a Bargiya (sacrifices the Ace under your win), the inference "partner wants this suit returned" succeeds approximately 90% of the time. Speaker repeats elsewhere "اقوى تعريف البلوت" — strongest convention in Baloot. **[FOCUS]** This is a calibration number for any bot that weights signal confidence; v0.10.0 should not treat Bargiya as merely "probable" — it should be near-certain.
- **Confidence (per source):** Definite
- **Hand-shape preconditions:** n/a
- **Phase scope:** signaling
- **Numerical thresholds:** ~90% success rate

### Rule 3: The two exceptions to "Bargiya means return the suit"
- **Source:** video 14 @ 00:01:48 – 00:02:54
- **Arabic phrase (verbatim, ≤15 words):** "السفنقات جدا بسيطه ونادره وغالبا تكون في اخر الجيم"
- **Rule (English):** There are exactly TWO situations where partner's Bargiya does NOT request the same suit back. Both are end-game. (a) Stranded-Ace defensive Bargiya: partner discards Ace because they fear opponent will outrun them at end of hand and want to bank the points themselves; typical when opponent holds 2-3 cards in hand. (b) Forced choice: partner had to choose between Ace and another card and chose to play Ace (e.g., Ace + 10 of diamonds remaining and partner picks one). The exceptions are "very simple, rare, and usually at end of game."
- **Confidence (per source):** Definite (named exceptions)
- **Hand-shape preconditions:** End-of-game (each player ≤4 cards); opponent showing strong-suit collection
- **Phase scope:** endgame / signaling
- **Numerical thresholds:** Opponent has 2 or 3 cards remaining

### Rule 4: Definition of "early game" vs "end game" by card-count
- **Source:** video 14 @ 00:05:09 – 00:05:21
- **Arabic phrase (verbatim, ≤15 words):** "بدايه اللعب اذا كان عند كل لاعب خمسه اوراق فاكثر"
- **Rule (English):** Early game = each player holds 5+ cards. End game = each player holds 4 or fewer cards. This boundary determines whether the receiver of a Bargiya should dash to partner immediately or eat extra tricks first. **[FOCUS]** This is an explicit threshold the bot should use for the SWA-attempt timing decision; "trick 4" or "cards-in-hand ≤4" is the Saudi-source-canonical boundary.
- **Confidence (per source):** Definite
- **Hand-shape preconditions:** n/a
- **Phase scope:** mid-game / endgame
- **Numerical thresholds:** ≥5 cards = early; ≤4 cards = end

### Rule 5: Bargiya receiver with no spare tricks → dash to partner immediately (always)
- **Source:** video 14 @ 00:03:42 – 00:03:50, 00:04:48 – 00:05:01
- **Arabic phrase (verbatim, ≤15 words):** "في هذه الحاله بدون اي نقاش روح لخويك على طول"
- **Rule (English):** If you receive a Bargiya and you cannot win any trick on your own ("you have no extra eats"), then unconditionally play to partner immediately, regardless of game phase. There is no debate on this case. This applies whether or not you hold the requested suit — if you have it, lead it; if you don't, follow Tahreeb-conventions to deliver tempo to partner.
- **Confidence (per source):** Definite
- **Hand-shape preconditions:** No tricks-of-your-own anywhere in your hand
- **Phase scope:** mid-game / endgame
- **Numerical thresholds:** n/a

### Rule 6: Bargiya receiver in END-game with extra tricks → still dash to partner
- **Source:** video 14 @ 00:04:01 – 00:04:09, 00:05:43 – 00:05:48
- **Arabic phrase (verbatim, ≤15 words):** "روح لخويك على طول لانه غالبا عنده سوا"
- **Rule (English):** If end-game (each player ≤4 cards) and partner Bargiya'd, dash to partner immediately even if you hold extra winning tricks. Reason: at end-game partner almost certainly has SWA. **[FOCUS]** This is the strong SWA-inference signal — if a player receives Bargiya in end-game, the bot should sharply elevate its prior on partner-has-SWA. Eating an extra trick first risks letting opponent break the SWA.
- **Confidence (per source):** Definite
- **Hand-shape preconditions:** Receiver has ≥1 winning trick of their own; ≤4 cards in each hand
- **Phase scope:** endgame
- **Numerical thresholds:** Each player ≤4 cards

### Rule 7: Bargiya receiver in EARLY-game with extra tricks → eat 1-2 first, THEN go to partner
- **Source:** video 14 @ 00:04:09 – 00:04:18, 00:13:11 – 00:13:16
- **Arabic phrase (verbatim, ≤15 words):** "بدايه اللعب الافضل انك ما تروح لخويك مباشره"
- **Rule (English):** If early-game (each player ≥5 cards) and you receive Bargiya AND you have extra tricks of your own, the optimal play is NOT to dash to partner immediately. Instead, cash 1 or 2 of your own winners first, then transition to partner. The reasoning developed across multiple examples is: in early-game partner does NOT necessarily have SWA — they may have sent Bargiya because they hold a single long suit and want to clarify the request before opponents disrupt. **[FOCUS]** This is the inverse of end-game behavior and contradicts the "common-player belief" that Bargiya always means SWA. The bot's SWA-prior elevation on Bargiya should be CONDITIONAL on the early/late-game cards-remaining axis, not unconditional.
- **Confidence (per source):** Definite (developed across multiple worked examples)
- **Hand-shape preconditions:** Receiver has ≥1 of own winning tricks; each player ≥5 cards
- **Phase scope:** mid-game
- **Numerical thresholds:** Eat 1-2 tricks max — limits given by partner's hand size (see Rule 19)

### Rule 8: Bargiya is sometimes voluntary (preempt-clarity), not always SWA-driven
- **Source:** video 14 @ 00:04:18 – 00:04:44
- **Arabic phrase (verbatim, ≤15 words):** "خويك ما يبرق لك الا اذا عنده سوا هل هذا شرط او دائما لا"
- **Rule (English):** It is NOT a hard rule that "Bargiya implies SWA." In end-game, yes — partner usually has SWA. But in early-game, partner may Bargiya because they hold a single suit (5+ cards) and want to communicate the request early before they may get squeezed. They may also lack the "color" / shape needed to use a non-Ace Tahreeb to convey the same message clearly. **[FOCUS]** Bot decision logic should NOT short-circuit Bargiya → partner-has-SWA at all phases.
- **Confidence (per source):** Definite (explicit Q-and-A in the source)
- **Hand-shape preconditions:** Early-game version applies when partner shape is single-suit (5+) or color-deficient
- **Phase scope:** signaling / mid-game
- **Numerical thresholds:** Single-suit length ≥5 cards triggers early voluntary Bargiya

### Rule 9: Bargiya-flavor distinguishing axis — HAND-SHAPE based, not event-count based
- **Source:** video 14 @ 00:11:48 – 00:12:32 (the worked-example walkthrough)
- **Arabic phrase (verbatim, ≤15 words):** "محشور بلون واحد او بلونين ومنه مثلا مردوفه بشيء صغير"
- **Rule (English):** **[FOCUS]** The two flavors of Bargiya (invitation/SWA-inviting vs defensive shed) are distinguished by partner's hand-shape revealed by what the receiver can infer, NOT by counting how many Bargiya events have happened. Specifically: a Bargiya from partner who is "محشور بلون واحد" (stuck/cornered into one suit) — i.e. holds only 1 or 2 suits and has a small follower (مردوفه بشيء صغير) or is alone (تك) or hooked (علق) — is the early-Bargiya invitation case (preempt-clarity). The other flavor is the end-game stranded-Ace defensive shed described in Rule 3. The user-flagged hunch is correct: the Saudi-source axis is **hand-shape (محشور بلون واحد)**, not "event-count ≥2 events." This is the single most important conflict-flag for the WHEREDNGN code-side audit. The implementer should re-read this rule directly before touching `Bot.PickBargiya` / Bargiya classification.
- **Confidence (per source):** Definite
- **Hand-shape preconditions:** Single-suit (1 color) or two-suit (2 colors) holdings; mardoofa with small card; alone/hooked configurations
- **Phase scope:** signaling
- **Numerical thresholds:** "5 cards or more in one suit" exemplified

### Rule 10: Bargiya transmits "highest card sacrificed → I have the next-strongest in suit" implication
- **Source:** video 14 @ 00:00:39 – 00:01:00
- **Arabic phrase (verbatim, ≤15 words):** "هربت اكبر ورقه عندك"
- **Rule (English):** When partner Bargiya's (sacrifices the Ace), they are explicitly communicating "I sacrificed the BIGGEST card in this suit; therefore I hold the cards just below it (10, J, Q etc.) or the longest run." Examples given: holds 10+J+Q after Ace; holds 10+J+9 after Ace; etc. The strength of the inference comes from the magnitude of the sacrifice.
- **Confidence (per source):** Definite
- **Hand-shape preconditions:** Sacrificer must hold next-strongest card OR substantial-length run in suit
- **Phase scope:** signaling
- **Numerical thresholds:** n/a

### Rule 11: Bargiya request prioritized over other Tahreeb if both available
- **Source:** video 14 @ 00:01:30 – 00:01:37
- **Arabic phrase (verbatim, ≤15 words):** "ولو خيو بين تهريب البرقيه وتهريب اخر امشي على تهريب البرقيه"
- **Rule (English):** If a player can choose between sending a Bargiya (Ace-Tahreeb) and a different non-Ace Tahreeb (e.g. K-Tahreeb), the speaker recommends ALWAYS choosing Bargiya. Reasoning: it has the highest success rate as a signal.
- **Confidence (per source):** Definite (explicit recommendation)
- **Hand-shape preconditions:** Must hold Ace + sufficient backing in same suit
- **Phase scope:** signaling
- **Numerical thresholds:** n/a

### Rule 12: When sending Bargiya in the "kaboot setup" pattern (early Bargiya)
- **Source:** video 14 @ 00:08:13 – 00:09:25
- **Arabic phrase (verbatim, ≤15 words):** "في البدايه بالذات اذا يبغى كبوت"
- **Rule (English):** Sender should send Bargiya early specifically when seeking Kaboot. This typically applies when sender has only 2 suits OR a single suit with a long run. The early Bargiya is sent before the receiver could mistakenly play a wrong suit and lose the trick to the opponent's Ace. The rationale: an early Bargiya gives partner a clear instruction before they have to guess between two non-trump suits.
- **Confidence (per source):** Common (specific worked-example with multiple variants)
- **Hand-shape preconditions:** Sender has 2 suits or 1 long suit (5+); seeks Kaboot
- **Phase scope:** opening-lead / mid-game
- **Numerical thresholds:** Run length 5+ in single suit; or exactly 2 suits

### Rule 13: Sender's Bargiya communicates "your guess between my two non-trump suits would be wrong"
- **Source:** video 14 @ 00:09:42 – 00:10:08
- **Arabic phrase (verbatim, ≤15 words):** "برق لك عشان لا تروح شيريه بالغلط"
- **Rule (English):** A specific motivation for early Bargiya: the sender wants to prevent the receiver from leading the WRONG suit (e.g. Hearts when Spades is correct). Without Bargiya, the receiver might guess wrong, the opponent (holder of the Ace in that suit) wins the trick, and the Kaboot is broken. Bargiya removes the guesswork.
- **Confidence (per source):** Definite
- **Hand-shape preconditions:** Sender has clear-cut single suit they want returned; receiver has 2+ candidate suits to play
- **Phase scope:** signaling
- **Numerical thresholds:** n/a

### Rule 14: Bargiya is a 2-way contract requiring both partners to "speak the convention"
- **Source:** video 14 @ 00:10:01 – 00:10:11
- **Arabic phrase (verbatim, ≤15 words):** "لازم الاثنين يكون عندكم هذا التفكير"
- **Rule (English):** The Bargiya convention only works if BOTH partners share the convention's interpretation. If one partner reads "Bargiya means dash immediately" and the other plays the early-Bargiya = preempt-clarify variant, miscommunication occurs. The speaker stresses this is a precondition. **[FOCUS]** For bot-pairing logic: bots should assume their human/AI partner shares the convention only when partner-tier matches.
- **Confidence (per source):** Definite
- **Hand-shape preconditions:** n/a (meta-rule)
- **Phase scope:** signaling
- **Numerical thresholds:** n/a

### Rule 15: Avoid sending a "fake" Bargiya / mistaking opponent's discard
- **Source:** video 14 @ 00:13:51 – 00:14:11
- **Arabic phrase (verbatim, ≤15 words):** "ممكن تنثر لخصمك واخر شبكه تفهمه"
- **Rule (English):** There is exactly ONE situation where the *opponent* may sacrifice an Ace to you: when they have stranded between Ace and 10 in a suit and you, the opponent, hold a card between them. They sacrifice to clear the path for the 10 to win. This is "the only case" where opponent gives you an Ace. Receiver must not mis-interpret this opponent-Bargiya as a partner-Bargiya. **[FOCUS]** Bot must distinguish "Ace played by partner" vs "Ace played by opponent" — the inference rule is direction-of-player-sensitive.
- **Confidence (per source):** Definite (single case)
- **Hand-shape preconditions:** Opponent holds Ace + 10 + nothing between; you hold a middling card in suit
- **Phase scope:** mid-game / endgame
- **Numerical thresholds:** n/a

### Rule 16: Default rule — DO NOT Bargiya unless you have SWA
- **Source:** video 14 @ 00:14:14 – 00:14:29
- **Arabic phrase (verbatim, ≤15 words):** "الافضل لا تبرق الا اذا عندك سوا"
- **Rule (English):** The general/default rule for the SENDER: do NOT send Bargiya unless you have SWA (or the closely-related single-suit early-game configuration). The exception is the early-game single-suit case described in Rules 8 and 12. Speaker explicitly says "in general it's best you don't Bargiya unless you have SWA, and per the cases mentioned." **[FOCUS]** Bot SWA-detection should be a primary trigger for bot Bargiya-emission; secondary trigger is the single-suit / 5+-cards configuration.
- **Confidence (per source):** Definite
- **Hand-shape preconditions:** SWA OR (single suit length 5+ AND early-game)
- **Phase scope:** signaling / SWA
- **Numerical thresholds:** Hand-size at Bargiya-decision time: end-game (4 cards) → SWA required; early-game (6-8 cards) → single-suit-5+ optional

### Rule 17: How many tricks the receiver may eat before going to partner — sized by partner's expected hand
- **Source:** video 14 @ 00:11:58 – 00:12:10
- **Arabic phrase (verbatim, ≤15 words):** "مثلا سبعه اوراق تاكل اكلاتين ثلاثه اكلات بالكثير"
- **Rule (English):** **[FOCUS]** Concrete thresholds for "eat-first-then-partner" Bargiya receiver behavior, sized by partner's hand size at time of Bargiya: (a) Partner had 7 cards → eat at most 2 or 3 tricks. (b) Partner had 6 cards → eat at most 1 or 2 tricks. (c) Partner had 5 cards → eat at most 1 trick — DO NOT exceed even if you have more winners. Reason: every extra eat increases partner's doubt that you understood the Bargiya, and may force partner to switch tactics (e.g. discard the 10 of suit defensively). This is a directly-implementable bot heuristic for SWA-attempt timing.
- **Confidence (per source):** Definite (numeric thresholds explicit)
- **Hand-shape preconditions:** Receiver has multiple winning tricks of own
- **Phase scope:** mid-game / endgame / SWA
- **Numerical thresholds:** 7-card partner → eat ≤2-3; 6-card → eat ≤1-2; 5-card → eat ≤1

### Rule 18: When receiver has no same-suit (sbeit) — apply standard Tahreeb-direction rules
- **Source:** video 14 @ 00:13:23 – 00:13:46
- **Arabic phrase (verbatim, ≤15 words):** "امشي على قواعد التهريب على نظام التهريب عكس الشكل"
- **Rule (English):** If the receiver gets Bargiya but does NOT have the requested suit (sbeit) in hand, apply the general Tahreeb conventions to find the right substitute card to deliver: (a) red-on-red Tahreeb → partner wants black; choose between the two black suits using shape clues; (b) if partner did not Tahreeb but answered the trick, fall back to Tanfeer (opponent-discard reading) interpretation; (c) if you were eating tricks, also use Tanfeer-of-opponent inference. The "Tahreeb opposite shape" routing is the canonical fallback.
- **Confidence (per source):** Definite
- **Hand-shape preconditions:** Receiver lacks Bargiya'd suit
- **Phase scope:** mid-game
- **Numerical thresholds:** n/a

### Rule 19: Tahreeb sender should send EARLIER if hand has only 1 long suit
- **Source:** video 14 @ 00:09:30 – 00:09:48
- **Arabic phrase (verbatim, ≤15 words):** "خويك يلعب لك من بدري عشان يرتاح وعشان يفهمك من بدري"
- **Rule (English):** If the sender has a single long suit (5+ cards), they should send the Bargiya/Tahreeb signal AS EARLY AS POSSIBLE — even on the very first trick they get to. This: (a) lets sender "rest" — they no longer need to manage the message; (b) clarifies the request before receiver gets squeezed; (c) prevents receiver from playing the wrong non-trump (Sheryeh vs Sbeit guess error).
- **Confidence (per source):** Definite
- **Hand-shape preconditions:** Sender has ≥5 cards in one suit
- **Phase scope:** opening-lead / mid-game / signaling
- **Numerical thresholds:** ≥5 cards single-suit triggers early-Bargiya

### Rule 20: Sender SHOULD NOT cash extra eats before sending Bargiya in early-game-single-suit case
- **Source:** video 14 @ 00:13:01 – 00:13:11
- **Arabic phrase (verbatim, ≤15 words):** "المفروض ما يلعبها خلاص يروح سبيت مباشره"
- **Rule (English):** When sender has the early-Bargiya configuration and an extra trick of their own, sender should NOT cash that extra trick — they should immediately Bargiya / lead-suit-back. Holding back the extra eat is wasteful in this case because the message about the long suit is more valuable than one extra point.
- **Confidence (per source):** Sometimes (single-source, presented as "the right way" against common practice)
- **Hand-shape preconditions:** Sender has long suit + small extra trick
- **Phase scope:** signaling / SWA
- **Numerical thresholds:** n/a

### Rule 21: Tanfeer (opponent discard) is fundamentally different from Tahreeb (partner Tahreeb)
- **Source:** video 19 @ 00:00:49 – 00:01:13
- **Arabic phrase (verbatim, ≤15 words):** "اكيد في فرق ولا ما كان سويت مقطع"
- **Rule (English):** Tahreeb = partner's signal sacrificed UNDER your won trick (or for your benefit). Tanfeer = opponent throwing away a card that they no longer need (or losing it under partner). The two are syntactically similar (both are visible card-plays from a non-leader) but semantically opposite. The same card visible in different contexts (partner-win vs opponent-win) means OPPOSITE things.
- **Confidence (per source):** Definite (foundational distinction)
- **Hand-shape preconditions:** n/a
- **Phase scope:** signaling
- **Numerical thresholds:** n/a

### Rule 22: Same card cannot be both a Tahreeb and a Tanfeer — direction matters
- **Source:** video 19 @ 00:01:59 – 00:02:08
- **Arabic phrase (verbatim, ≤15 words):** "تهريب الخويي راح اهرب له بنت الهاشمي تهريب الخصمي ما راح اهرب له بنت"
- **Rule (English):** Worked example: same physical card (Jack of clubs) — if I play it intending Tahreeb to partner I lead the BIG card; if I'm opponent dropping it as Tanfeer I drop a SMALL card (e.g. 7) instead. Therefore the receiver/partner can use card-magnitude to disambiguate: if the dropped card is HIGH, it's Tahreeb; if LOW, it's likely Tanfeer.
- **Confidence (per source):** Definite (worked example)
- **Hand-shape preconditions:** n/a
- **Phase scope:** signaling
- **Numerical thresholds:** Card rank — high (10/J/Q/K) leans Tahreeb; low (7/8) leans Tanfeer

### Rule 23: Initial assumption — opponent who Tanfeers has the Ace of that suit
- **Source:** video 19 @ 00:02:29 – 00:03:24
- **Arabic phrase (verbatim, ≤15 words):** "اي ورقه يهربها خصمك افترض مبدئيا انه عنده او عشرتها"
- **Rule (English):** **[FOCUS]** Foundational Tanfeer-inference rule (the "worst-case assumption"): when an opponent throws away (Tanfeer's) any card in a suit, the *initial assumption* is that they hold the Ace (or the 10) in that suit. The flip is also a rule: if opponent does NOT Tanfeer a particular card, assume they don't have its strongest counterpart. The reasoning: this is the WORST-CASE for you, and Saudi-Baloot strategy demands worst-case assumptions for opponent strength. The principle: in Tahreeb, "he wants this suit and the other 3"; in Tanfeer, "he keeps the strong cards in this suit and discards the rest." This reverses the Tahreeb-of-partner reading. Bot decision logic that builds opponent-hand priors must default to "opponent holds top of any suit they Tanfeer." Speaker explicitly calls this "the worst-case principle" or "الافتراض الاسوء."
- **Confidence (per source):** Definite (founding principle of the source's framework)
- **Hand-shape preconditions:** n/a (always-on prior)
- **Phase scope:** signaling / mid-game / bot-decision
- **Numerical thresholds:** Confidence floor 1%, ceiling 99% (see Rule 24)

### Rule 24: Tanfeer rule confidence floats from 1% to 99% based on factors
- **Source:** video 19 @ 00:03:46 – 00:04:24
- **Arabic phrase (verbatim, ≤15 words):** "قاعده تنفيذ ترى نسبه نجاحها من 1% الى تسعه وتسعين نسبه مفتوحه"
- **Rule (English):** **[FOCUS]** The Tanfeer-implies-strong-card rule has a wildly variable confidence range — anywhere from 1% to 99% depending on context. At trick 1 with 8 cards in opponent's hand, the rule applies but confidence is LOW because opponent is just clearing junk. As game progresses and hand-size shrinks, opponent starts to be FORCED to discard real strength, so the rule's confidence climbs. **[FOCUS]** This is critical for any bot probability model — the Tanfeer signal is NOT a fixed-weight feature; weighting must scale with cards-remaining-in-hand. A naive bot using a constant Tanfeer prior will over-trust early Tanfeers and under-trust late ones.
- **Confidence (per source):** Definite
- **Hand-shape preconditions:** Confidence depends on remaining hand size of Tanfeer'er
- **Phase scope:** signaling / bot-decision
- **Numerical thresholds:** 1% (early game, junk discard) → 99% (late game, forced strong discard)

### Rule 25: Tahreeb interpretation overrides Tanfeer interpretation when both possible
- **Source:** video 19 @ 00:04:24 – 00:04:54, 00:11:00 – 00:11:34
- **Arabic phrase (verbatim, ≤15 words):** "اذا خيو بينهم دائما رجح التهريب"
- **Rule (English):** **[FOCUS]** When the same observed play could be interpreted as either Tahreeb or Tanfeer, ALWAYS choose the Tahreeb interpretation. Reason: Tahreeb's success rate (~90%) is much higher than Tanfeer's variable success rate. Concretely: "If the opponent's Jack of trump is played, you must CANCEL the Tanfeer interpretation, REVERSE the assumption, and READ it as Tahreeb." This produces an automatic prior-flip: the moment Tahreeb is even plausible, prior on Tanfeer collapses. **[FOCUS]** A bot's Bayesian inference must NOT independently combine Tahreeb and Tanfeer probabilities — it must apply Tahreeb-priority gating.
- **Confidence (per source):** Definite (named principle: "أفضليه" / preference)
- **Hand-shape preconditions:** Both interpretations must be syntactically possible
- **Phase scope:** signaling / bot-decision
- **Numerical thresholds:** n/a

### Rule 26: Tanfeer factor 1 — game-progress / hand-size
- **Source:** video 19 @ 00:04:24 – 00:06:21
- **Arabic phrase (verbatim, ≤15 words):** "كل ما يقدم القيم"
- **Rule (English):** First Tanfeer-confidence amplifier: as the game progresses (cards-in-hand decreases), Tanfeer-rule confidence rises. Specifically: 8-card-in-hand discard = junk-drop-low confidence; 6-7 cards = mid; 4-5 cards = high; ≤3 cards = forced strength discard, very high confidence.
- **Confidence (per source):** Definite (named factor 1)
- **Hand-shape preconditions:** n/a
- **Phase scope:** signaling
- **Numerical thresholds:** ≥7 cards → low; 5-6 → mid; ≤4 → high

### Rule 27: Tanfeer factor 2 — discarded card's rank (the bigger, the more confident)
- **Source:** video 19 @ 00:06:21 – 00:07:31
- **Arabic phrase (verbatim, ≤15 words):** "كل ما يزيد معك ترتيب الورق كل ما تزيد صحه هذه القاعده"
- **Rule (English):** Second Tanfeer factor: confidence in the rule scales with the rank of the discarded card. Order of confidence-strength of Tanfeer: Ace > 10 > K > Q > J > 9 > 8 > 7. The higher the discarded card, the more strongly the rule applies (because high-card discard is a stronger admission of forced loss). Special exception: discarded ACE means the opponent is "hugging" the suit (انحد عليها) with 10 + nothing between — this is the rare opponent-Bargiya from Rule 15. Discard of low card (7-8) at game start often just means "this is junk" (تك), not a strength reveal.
- **Confidence (per source):** Definite (named factor 2 with explicit rank-ordering)
- **Hand-shape preconditions:** n/a
- **Phase scope:** signaling
- **Numerical thresholds:** Rank-order: 7 < 8 < 9 < J < Q < K < 10 < A

### Rule 28: Tanfeer factor 3 — same opponent Tanfeer's same suit twice (consecutive vs non-consecutive)
- **Source:** video 19 @ 00:07:31 – 00:08:13
- **Arabic phrase (verbatim, ≤15 words):** "اذا خصمك نفر ورقتين من نفس الشكل"
- **Rule (English):** Third Tanfeer factor: when the same opponent Tanfeer's two cards from the SAME suit, confidence in the strong-residual hypothesis rises. Two sub-cases: (a) consecutive (trick N and N+1) — high confidence amplifier; (b) non-consecutive (trick N and N+2 with different suit between) — moderate amplifier. Mid-to-late-game double-Tanfeer is especially strong evidence opponent retains the suit's tops.
- **Confidence (per source):** Definite (named factor 3)
- **Hand-shape preconditions:** Same opponent must Tanfeer same suit ≥2 times
- **Phase scope:** signaling
- **Numerical thresholds:** Consecutive > non-consecutive

### Rule 29: Tanfeer factor 4 — both opponents Tanfeer same suit
- **Source:** video 19 @ 00:08:13 – 00:09:06
- **Arabic phrase (verbatim, ≤15 words):** "اذا خصمينك نفروا نفس الشكل"
- **Rule (English):** Fourth Tanfeer factor: if BOTH opponents Tanfeer the same suit, you assume strong cards are concentrated in ONE of them — and the one whose Tanfeer'd card was BIGGER is the stronger candidate. If discards are in different tricks, the LATER discard (closer to end-game) is more revealing of held strength.
- **Confidence (per source):** Definite (named factor 4)
- **Hand-shape preconditions:** Both opponents must Tanfeer same suit
- **Phase scope:** signaling
- **Numerical thresholds:** Bigger discarded card → higher prior on holding cards above it

### Rule 30: Tanfeer factor 5 — opponent Tanfeer's a DIFFERENT suit on later trick
- **Source:** video 19 @ 00:10:00 – 00:10:45
- **Arabic phrase (verbatim, ≤15 words):** "راح تلغي قاعده تنفيذ في الشكل الاول وتفترضها في الشكل الثاني"
- **Rule (English):** Fifth Tanfeer factor: if the same opponent Tanfeer's suit X first, then suit Y on a later trick, CANCEL the Tanfeer-strong-card rule on suit X and APPLY it to suit Y. Reasoning: opponents preserve their strength for later — so the SECOND Tanfeer is more revealing than the first. The first Tanfeer in a hand always has reduced confidence. **[FOCUS]** Concretely: for bot opponent-hand inference, the Tanfeer-prior should be applied incrementally per-suit per-Tanfeer event, with later events outweighing earlier ones in the same hand.
- **Confidence (per source):** Definite (named factor 5)
- **Hand-shape preconditions:** Same opponent Tanfeer's two different suits at different tricks
- **Phase scope:** signaling
- **Numerical thresholds:** First Tanfeer prior < later-trick Tanfeer prior

### Rule 31: Tanfeer factor 6 — bidder identity (who-bought-the-bid)
- **Source:** video 19 @ 00:10:00 – 00:11:00
- **Arabic phrase (verbatim, ≤15 words):** "لو خويك اللي اشترى صن او انت اشتريت صن هنا نسبه التنفير ما راح تكون نسبه كبيره"
- **Rule (English):** **[FOCUS]** Sixth Tanfeer factor — bidder identity matters: (a) If YOU or your PARTNER won the bid (Sun or Hokm), opponent Tanfeer-confidence is LOW because opponents already revealed weakness by passing — they may simply be discarding garbage with no real strength. (b) If an OPPONENT won the bid (especially Sun), Tanfeer-confidence is HIGH because the bidder already proved they have strong cards, and the OTHER opponent is likely also holding strong supporting cards. (c) Hokm-buyer also gets boosted assumed-strength. **[FOCUS]** Bot scoring/estimation must be bid-side-asymmetric for opponent-hand priors. This is a direct consequence for `Bot.PickAshkal`-related logic.
- **Confidence (per source):** Definite (named factor 6, explicit examples)
- **Hand-shape preconditions:** Sun or Hokm contract; identity of bid-winner
- **Phase scope:** signaling / scoring / bot-decision
- **Numerical thresholds:** n/a (qualitative)

### Rule 32: "Always assume the worst" — meta-principle for opponent-hand inference
- **Source:** video 19 @ 00:10:45 – 00:10:55
- **Arabic phrase (verbatim, ≤15 words):** "كلاعب بلوت دائما تفترض الاسوا"
- **Rule (English):** Meta-principle: as a Baloot player you always assume the WORST case for opponent's hand strength. This is the philosophical justification for Rule 23. Even when factors might lower the Tanfeer prior, you maintain the worst-case as the safety net — you only relax the assumption when evidence positively contradicts it.
- **Confidence (per source):** Definite (explicit meta-rule)
- **Hand-shape preconditions:** n/a (meta-rule)
- **Phase scope:** bot-decision
- **Numerical thresholds:** n/a

### Rule 33: Receiver should re-image themselves as the discarder ("put yourself in opponent's seat")
- **Source:** video 19 @ 00:11:42 – 00:11:55
- **Arabic phrase (verbatim, ≤15 words):** "حط نفسك مكان الخصم"
- **Rule (English):** A practical inference heuristic: when reading opponent's Tanfeer, ALWAYS imagine yourself in the opponent's seat with the same visible game state — what would YOU Tanfeer? Your own behavior closely mirrors theirs. This is the meta-skill underlying all 6 factors. Implication for the bot: the same evaluator function should drive both "what should I Tanfeer?" and "what does opponent's Tanfeer mean?" — they are inverses of each other.
- **Confidence (per source):** Definite (recommended practice)
- **Hand-shape preconditions:** n/a
- **Phase scope:** bot-decision
- **Numerical thresholds:** n/a

### Rule 34: Partner (خوي) "appraisal" / partner-tahreeb is always preferred over opponent-tanfeer
- **Source:** video 19 @ 00:11:32 – 00:11:42
- **Arabic phrase (verbatim, ≤15 words):** "دائما قدر خويك تهريب وهو اللي يمشي على الخصم"
- **Rule (English):** Restatement of Rule 25 with a more specific framing: the principle "appraise your partner's signal as Tahreeb" (تقدير الخوي) is the master rule. Partner-Tahreeb interpretation drives the strategic choice; Tanfeer-of-opponent only kicks in when no partner-Tahreeb interpretation is available. Speaker uses the term "تقدير الخوي" / "estimation of partner" to name this principle.
- **Confidence (per source):** Definite (named principle)
- **Hand-shape preconditions:** n/a
- **Phase scope:** bot-decision
- **Numerical thresholds:** n/a

### Rule 35: Partner can act either as Tahreeb-er to YOU or as Tanfeer-er to opponent — same physical card means OPPOSITE
- **Source:** video 19 @ 00:11:55 – 00:12:24
- **Arabic phrase (verbatim, ≤15 words):** "خويك ما هرب لك لكن نفر للخصم"
- **Rule (English):** Critical case for partner-reading: partner may play a card that is NOT Tahreeb to you (because trick is being won by opponent, not you) but is a TANFEER to opponent. In this case, BOTH inferences trigger: opponent reads it as Tanfeer (low signal); you read it as Tahreeb (you mentally substitute yourself as the receiver and apply Tahreeb logic). This means partner's same physical play sends DIFFERENT messages to the two sides of the table simultaneously.
- **Confidence (per source):** Definite
- **Hand-shape preconditions:** Partner discards on opponent-won trick
- **Phase scope:** signaling
- **Numerical thresholds:** n/a

### Rule 36: Inference is dynamic — must be re-computed per-trick, per-player
- **Source:** video 19 @ 00:12:15 – 00:12:34, 00:04:36 – 00:04:51
- **Arabic phrase (verbatim, ≤15 words):** "تتغير فرضياتك في كل مره لكل لاعب ولكل حله"
- **Rule (English):** Inference about opponent / partner hands must be RECOMPUTED at every trick for every player, NOT cached as a static prior at game-start. Hypotheses that were true at trick 1 may flip at trick 3. **[FOCUS]** For a bot, this means opponent-hand probability state must be a per-trick-updated structure, not a precomputed table. Naive caching of "opponent X has hearts strong cards" risks holding a stale prior into a phase where evidence has flipped it.
- **Confidence (per source):** Definite
- **Hand-shape preconditions:** n/a
- **Phase scope:** bot-decision
- **Numerical thresholds:** n/a

### Rule 37: Sun-buyer (or Hokm-buyer) presumption: bidder has strong cards
- **Source:** video 19 @ 00:10:21 – 00:10:32
- **Arabic phrase (verbatim, ≤15 words):** "اللي يشتري صن غالبا عنده ورق قوي واقل شيء عنده كذا"
- **Rule (English):** **[FOCUS]** When evaluating any opponent or partner who BOUGHT the bid (especially Sun, but also Hokm), assume by default that they hold strong cards. Use this as a base-rate prior for the bot's opponent-hand-strength estimate. Concrete consequence: in Sun contracts, opponent Tanfeer's confidence is HIGH (because both opponents may already be at the ceiling of their cards' ranges).
- **Confidence (per source):** Definite
- **Hand-shape preconditions:** Sun or Hokm bidder identified
- **Phase scope:** scoring / bot-decision
- **Numerical thresholds:** n/a (qualitative)

### Rule 38: Opening-Tanfeer of an Ace = exception (suit-trapped, not strength-revealing)
- **Source:** video 19 @ 00:06:59 – 00:07:13
- **Arabic phrase (verbatim, ≤15 words):** "اذا هرب لك عكا اعرف انه انحد عليها في الغالب"
- **Rule (English):** Special case nullifying Rule 23 for Ace specifically: if opponent leads/Tanfeer's their Ace, do NOT assume they hold the 10 below. Instead assume they were "stuck" — they had Ace+10 with nothing else in suit and were forced to lead the Ace (typically end-of-game when they're about to be cut off). This is essentially the opponent-side analog of Rule 3's stranded-Ace defensive Bargiya.
- **Confidence (per source):** Definite (named exception)
- **Hand-shape preconditions:** Opponent holds Ace + 10 + (nothing else in suit); end-game pressure
- **Phase scope:** endgame / signaling
- **Numerical thresholds:** n/a

### Rule 39: Beginning-of-game low-card Tanfeer often means "junk discard" not strength
- **Source:** video 19 @ 00:07:13 – 00:07:31
- **Arabic phrase (verbatim, ≤15 words):** "بدايه الجيم حتفترض غالبا انها تك يعني ما عنده شكل"
- **Rule (English):** Negative case: if opponent Tanfeer's a LOW card (8 or below) at the START of the game, assume opponent simply has no cards in that suit (تك = "alone"/"empty") and is just clearing low filler. Do NOT apply Rule 23 strongly. Confidence: low. This is the floor of the 1-99% range from Rule 24.
- **Confidence (per source):** Definite
- **Hand-shape preconditions:** Opponent has 8 cards (start of game) and Tanfeer's a low card
- **Phase scope:** opening-lead / signaling
- **Numerical thresholds:** Low card = 7, 8 (sometimes 9)

### Rule 40: Tahreeb is the "language" of Baloot
- **Source:** video 19 @ 00:00:34 – 00:00:46
- **Arabic phrase (verbatim, ≤15 words):** "التهريب يعتبر مثل اللغه في البلوت"
- **Rule (English):** Conceptual framing: Tahreeb is treated as the LANGUAGE of Baloot. The conventions are fixed and must be MEMORIZED and INTERNALIZED ("لازم تحفظها ولازم تفهمها"). Players who do not learn the conventions cannot communicate with their partners — they "speak a different language." **[FOCUS]** For pairing-bot logic, this implies that bots configured with different convention-tiers are incompatible partners; mixing tiers degrades signal-passing.
- **Confidence (per source):** Definite
- **Hand-shape preconditions:** n/a (meta-rule)
- **Phase scope:** signaling
- **Numerical thresholds:** n/a

### Rule 41: Tanfeer of a "strong card" requires special handling (e.g. opponent throws a J/Q)
- **Source:** video 19 @ 00:04:24 – 00:04:42
- **Arabic phrase (verbatim, ≤15 words):** "خويك هرب شايب السبيت ايش راح تفهم هنا راح تفهم انه خويك يبغى شريه"
- **Rule (English):** When partner discards a STRONG card (e.g. K of spades) on an opponent trick, the receiver should immediately switch from default Tanfeer interpretation to a Tahreeb-of-cross-color interpretation: e.g. "partner discarded K of spades → partner wants other-color suit (sheryeh)." This is the trigger pattern for Rule 25's flip.
- **Confidence (per source):** Definite (worked example)
- **Hand-shape preconditions:** Partner plays high card on opponent-won trick
- **Phase scope:** signaling
- **Numerical thresholds:** "Strong" = J or higher

### Rule 42: Partner discard with Bargiya-like pattern → flip prior on partner's hand
- **Source:** video 19 @ 00:04:36 – 00:04:54
- **Arabic phrase (verbatim, ≤15 words):** "افترضنا انه القاعده اتكنسلت او نكست"
- **Rule (English):** Once you flip from Tanfeer to Tahreeb interpretation on partner's discard, the prior on partner's hand also flips: instead of "partner does NOT have X," update to "partner DOES have X." Concrete walkthrough: prior flips from "partner doesn't have 10 of sheryeh" to "partner has 10 of sheryeh and wants the lead returned." **[FOCUS]** Bot probability tables must support paired flip-and-update operations on Tahreeb/Tanfeer reclassification — not just additive Bayesian updates.
- **Confidence (per source):** Definite
- **Hand-shape preconditions:** n/a
- **Phase scope:** bot-decision
- **Numerical thresholds:** n/a

### Rule 43: Final summary — go practice the rules
- **Source:** video 19 @ 00:12:45 – 00:12:56
- **Arabic phrase (verbatim, ≤15 words):** "روح العب كم صكه وامشي على القاعده اللي قلتها"
- **Rule (English):** Speaker's closing: take these rules and PRACTICE them in real games to verify which match your style. Acknowledges that the rules are heuristics with success rates, not absolutes.
- **Confidence (per source):** Definite (closing remark)
- **Hand-shape preconditions:** n/a
- **Phase scope:** n/a
- **Numerical thresholds:** n/a

## Cross-source conflicts within this batch

### Conflict 1: When does Bargiya imply SWA?
- Video 14 (Rules 6, 7, 8, 16): explicitly **conditional** — Bargiya implies SWA at end-game, but in early-game it may indicate single-suit instead.
- Video 19 does NOT directly contradict, but implicitly assumes Bargiya/Tahreeb signals always indicate concrete hand contents. The framework in Video 19 is general-purpose discard-reading, not specifically Bargiya-as-SWA-marker.
- **Resolution:** Video 14 is more precise on Bargiya semantics; Video 19's framework should be subordinated to Video 14's more specific rules when reasoning about Bargiya.

### Conflict 2: How fast to react to partner's signal?
- Video 14 (Rule 7): in early-game, EAT 1-2 first before going to partner.
- Video 19 (Rules 25, 34): Tahreeb-priority principle says "always trust partner's signal" — could be read as "go to partner immediately."
- **Resolution:** Not actually a conflict — Video 19's Tahreeb-priority is about INTERPRETATION (read it as Tahreeb), not TIMING (act on it instantly). Video 14's eat-first-in-early-game rule operates on top of correct interpretation.

### Conflict 3: Single-source vs corroborated rules
- Rule 9 (hand-shape axis for Bargiya flavors) appears ONLY in video 14 — not corroborated by video 19. Video 19's framework would not naturally distinguish the two flavors (it lumps all opponent-Tanfeers together, then varies confidence by factor). This single-source status is a flag for the audit: if WHEREDNGN code uses event-count, the hand-shape axis from video 14 is the ONLY video evidence here. A cross-referencer needs to confirm against other source videos before rewriting.

## Open ambiguities

1. **What constitutes a "shape" (شكل) vs a "color" (لون)?** — Both terms are used. Sometimes "color" maps to red/black pair (Hearts+Diamonds = red; Clubs+Spades = black). Sometimes "shape" is single-suit. The Bargiya rules use "هرب احمر على احمر" (red on red) suggesting partner wants the OPPOSITE color. Bot code should clarify whether color-pairs or per-suit semantics are used.

2. **The "stranded between Ace and 10" opponent-Bargiya (Rule 15)** — speaker says "you have a card between them." What card-rank counts as "between"? The example uses J/Q/K but is not formalized.

3. **Voluntary Bargiya from "color-deficient" partner (Rule 8)** — speaker says "ما عنده لون كفايه يقدر يهرب يخليك تفهم ايش يبغى بالضبط" (lacks enough color to Tahreeb cleanly). The threshold for "lacks enough" is not given.

4. **Tanfeer-rule confidence numbers (Rules 24, 26, 27, 28, 29, 30, 31)** — all qualitative ("high," "low," "increases"); only one explicit number is given (10% in worked example). Bot translation requires assigning numeric weights to each factor; the source does NOT provide the weighting scheme.

5. **Bidder identity asymmetry (Rule 31, 37)** — Rule 31 says opponent-bid → high Tanfeer-confidence; partner-bid → low. But what if NEITHER side bid (i.e., dealer-default)? The source does not address this.

6. **Tahreeb vs Tanfeer cross-direction reading (Rule 35)** — when partner plays a card on opponent-won trick, the rule says BOTH interpretations apply. But which dominates in your decision-making? Tahreeb-priority (Rule 25) suggests Tahreeb wins, but the trick is opponent-won — does that affect priority?

7. **Length thresholds for "single suit" / "long suit"** — Rule 8 says "5+ cards." Rule 12 says "long run." Rule 19 also says 5+. But Rule 17 distinguishes by partner's hand-size (5/6/7), not by single-suit length. Are these the same threshold or different ones?

## Notes for cross-referencer

- **Most important Audit-flags for the WHEREDNGN code-side review:**
  1. **Rule 9 hand-shape vs event-count axis:** verify whether `Bot.PickBargiya` (or wherever Bargiya classification lives) uses cards-in-suit or event-count. The user's hunch about event-count being wrong is strongly corroborated here.
  2. **Rule 24 confidence-floats-with-hand-size:** check whether Tanfeer probability code uses a constant or scales with cards-remaining.
  3. **Rule 25 Tahreeb-priority gating:** check whether Bayesian inference order applies Tahreeb interpretation before Tanfeer.
  4. **Rule 31 bidder-asymmetric Tanfeer prior:** check whether opponent-hand priors are bidder-conditional in the code.
  5. **Rule 17 numeric thresholds for SWA-attempt timing:** these are concrete numbers (eat 1, 2, 2-3 by partner-hand-size) that should be in `Bot.PickSWA` or `Bot.PickPlay` SWA-related logic. **[FOCUS]**
  6. **Rule 4 early/end game boundary:** explicit threshold (5+ cards = early; ≤4 = end). Should be a single named constant in `Constants.lua`, used consistently across SWA, Bargiya, Kaboot decisions. **[FOCUS]**

- **Cross-validation needed against other source videos:**
  - Hand-shape Bargiya axis (Rule 9) — single-source, needs second video confirmation
  - Sun-buyer Tanfeer-confidence boost (Rule 31) — only this source mentions it; should appear in other Sun-strategy videos
  - Voluntary-early-Bargiya without SWA (Rule 8) — partial corroboration only

- **Terminology mapping reminders for cross-referencer:**
  - **Bargiya / Tahreeb-Aka / البرقيه / تهريب الاكه / التبريك** — all the SAME convention (sacrifice an Ace under partner's win or for partner's benefit)
  - **Tahreeb (تهريب)** — partner-direction sacrifice signal (general)
  - **Tanfeer (تنفير) / Tanfeez (تنفيذ)** — opponent-direction discard (the SAME word — both spellings used interchangeably in the source)
  - **SWA (سوا)** — claimable winning sequence
  - **Sbeit / السبيت** — the suit specifically being requested back via Bargiya (often spades, but term refers to "the requested suit," not literally spades)
  - **Sheryeh / الشريحه / الشريه** — the OTHER non-trump suit choice (often hearts but really "the alternative non-trump")
  - **Hass / الهاس** — Hearts
  - **Daimen / الدايمن / الديمن** — Diamonds
  - **Hokm (حكم)** — trump
  - **Sun (صن) / Sa3oodi-Sun** — no-trump
  - **Tek (تك)** — alone, empty in a suit
  - **Mahshoor (محشور)** — cornered/stuck (in a single color)
  - **Mardoofa (مردوفه)** — backed-up by a smaller card
  - **Kaboot (كبوت)** — sweep/shutout objective
  - **Saa3 (شايب) / Saheb (الشايب)** — King
  - **Bint (بنت)** — Queen
  - **Walad (الولد)** — Jack
  - **Sba3 (سبعه)** — 7 (note: 7 of trump becomes the lowest, but in non-trump it remains rank-7)
