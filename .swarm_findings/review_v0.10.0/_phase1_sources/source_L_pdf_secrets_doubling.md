# Source L — PDF Secrets-of-Pro Series + What-Is-Baloot + Doubling System

Cluster: pymupdf-extracted Arabic PDFs (plus one Google-Doc-pasted clean text) covering advanced strategy, the conceptual basis of Baloot scoring, and the canonical doubling/escalation chain.

Files covered:
1. `03_secrets_pro_1.txt` — سر الاحتراف في لعبة البلوت ١ (Secrets of Pro 1)
2. `03b_secrets_pro_2.txt` — سر الاحتراف في لعبة البلوت ٢ (Secrets of Pro 2, Google-Doc-pasted clean)
3. `04_secrets_pro_3.txt` — سر الاحتراف في لعبة البلوت ٣ (Secrets of Pro 3)
4. `05_what_is_baloot.txt` — ماهو البلوت في لعبة البلوت (What is Baloot)
5. `07_doubling_system.txt` — نظام الدبل في لعبة البلوت (Doubling/Bel system)

Notation: pages cited as `(file:page)` e.g. `(03:1)`, `(03b:1)`, `(04:1)`, `(05:1)`, `(07:1)`.

OCR/extraction caveats: pymupdf reverses Arabic-Indic digits in many places (e.g. "٢٦١" should be 162; "٠٠١" = 100; "٠٩" = 90; "٢٥١" = 152; "٦١" = 16; "٢٣" = 32; "٨٤" = 48; "٤٦" = 64; "٢٥" = 52; "٠١" = 10). Ditto for many word-internal digit pairs ("٢١ ورقة" = 12 cards). I've reconstructed the intended numerals where context makes them unambiguous; flagged where it doesn't.

---

## A. Secrets of Pro 1 — Card-counting fundamentals

### L01. Card-counting is the foundational pro skill **[FOCUS]**
- Source: 03_secrets_pro_1
- Arabic ≤15: «متابعة مايسقط من الوراق و عدها ومعرفة ماتبقى منها»
- English: Track every card that falls, count them, and know what remains. The deck has 4 suits, each running from King down to 7 — a player who ignores card-counting "will not become a pro at this game."
- Confidence: HIGH
- Page: 03:1
- Phase: ALL (every trick during play)
- Thresholds: 32-card deck = 4 suits × 8 ranks (K, T, J, A, 10, 9, 8, 7 in Hokm rank-order).

### L02. Count your own *strengths* falling from opponents and partner **[FOCUS]**
- Source: 03_secrets_pro_1
- Arabic ≤15: «أن ينتبه ويعد أوراق قوته التي تسقط من الخصم ومن زميله»
- English: A player must specifically count *his own strong cards* that fall from opponent and partner hands, and know how many remain. (Tracking high cards in the suits you hold is more important than tracking everything.)
- Confidence: HIGH
- Page: 03:1
- Phase: ALL
- Thresholds: per-suit count of remaining strength cards.

### L03. Watch what partner *escapes* (تهريب) to read his shape and read opponent strength
- Source: 03_secrets_pro_1
- Arabic ≤15: «ينتبه لالوراق التي هربها زميله»
- English: Pay attention to cards your partner discards / "escapes" away from. From this you learn (a) what partner wants you to play and what he needs you to hold, and (b) the opponents' strength.
- Confidence: HIGH
- Page: 03:1
- Phase: PLAY (mid-trick reads)
- Thresholds: —
- Note: this is the closest the cluster gets to a generic "discard signal" doctrine. AKA is *not* mentioned here — this is informational reading from partner's voluntary slough cards.

### L04. Know your accumulated points before round end so you can decide what to escape **[FOCUS]**
- Source: 03_secrets_pro_1
- Arabic ≤15: «يعرف العدد الذي حصل عليه من أوراق اللعبة قبل نهايتها»
- English: A player must know the points he has accumulated from the round's cards before it ends, so he can determine the *deficit* by which he might still succeed or his opponent might win, in order to escape (slough) the largest cards he has to his partner and finish the round cleanly.
- Confidence: HIGH
- Page: 03:1
- Phase: PLAY (especially late tricks)
- Thresholds: example — "if the deficit to losing is 10 points, he sloughs the King to his partner instead of holding it."
- Note: precondition stated explicitly: «بشرط أن يكون الخصم احل اللعب» — only valid when the opponent is *the bidder* (i.e. you are defending). The example assumes the partner is on lead next or otherwise can win the trick.

### L05. When partner reveals his need, send him your biggest card
- Source: 03_secrets_pro_1
- Arabic ≤15: «ياتيه باكبر ما لديه من ورقة»
- English: If, after observing partner's escapes, you can deduce what partner needs or where his strength is, lead/play him your highest card in that suit.
- Confidence: HIGH
- Page: 03:1
- Phase: PLAY
- Thresholds: —

### L06. Hold opponent's strength suit; do NOT escape your own strength prematurely **[FOCUS]**
- Source: 03_secrets_pro_1
- Arabic ≤15: «يحتفظ بها وال يهربها حتى لو اضطر لتهريب قوته»
- English: A player must know the opponents' strength suit and try to *retain* (not escape) those cards — even if it means sloughing some of his own strength — in order to avoid losing 4-4 (failing). Only escape your strength after you've counted what has fallen and what remains with the opponent.
- Confidence: MEDIUM (the "44 وال يهرب" string is corrupted; "44" is most likely "ال 44" referring to the 4-4 / Failing penalty threshold or simply "loss").
- Page: 03:1
- Phase: PLAY (slough decisions)
- Thresholds: precondition — count what has fallen of opp's strength suit before sloughing your strength.

---

## B. Secrets of Pro 2 — Three numbered bidding/lead rules **[FOCUS]**

### L07. Hokm bid REQUIRES holding an Ace **[FOCUS]**
- Source: 03b_secrets_pro_2
- Arabic ≤15: «اذا اراد ان يحكم اللاعب فلابد من وجود اكه لديه»
- English: To declare Hokm, the player MUST hold an Ace. Two reasons:
  1. (defensive) fear of the opponent forcing Sun, Kaboot, or 4-Hundred against you;
  2. (informational) if you bid Hokm without an Ace, your *partner* will assume you have one and will, on that basis, form (شكل) or buy (شترى) Sun.
- Confidence: HIGH (clean Google-Doc text; explicitly numbered rule #1)
- Page: 03b:1
- Phase: BID (`Bot.PickBid` precondition for `K.BID_HOKM`)
- Thresholds: Ace count ≥ 1 (suit not specified — any ace).

### L08. Sun bidder at seat 1 MUST lead the Ace+T (backed pair) on trick 1 if he holds one **[FOCUS]**
- Source: 03b_secrets_pro_2
- Arabic ≤15: «الاكه المردوفة بعشرة إن وجدت»
- English: If a player buys Sun and is on lead (seat 1, "رأس اللعب"), he MUST play *the Ace backed by the Ten* (i.e. an Ace whose holder also has the matching Ten in the same suit — اكه مردوفة بعشرة) if he has one. Purpose: discover whether *projects/melds* (مشاريع) exist in opponents' or partner's hands. This lead is *obligatory* on him AND on his partner.
- Confidence: HIGH (clean text; explicitly numbered rule #2)
- Page: 03b:1
- Phase: PLAY → opening lead (`pickLead` for Sun bidder at seat 1)
- Thresholds: holding A + 10 of same side; contract = SUN; bidder seat = 1.
- Note: the "اجبارية عليه وعلى زميله" wording suggests the *partner*, when ON LEAD himself, is also bound by the same convention if he has the backed Ace.

### L09. Seat 1/2 with bid-card-supported strength: delay the buy, give partner first chance **[FOCUS]**
- Source: 03b_secrets_pro_2
- Arabic ≤15: «اجلها للثاني... لإعطاء زميلك الفرصة بالمشترى الاول»
- English: If you are seat 1 or seat 2 (head-of-play or second), and the *up-card* (الورقة المكشوفة) supports your strength, do NOT buy it on the first round of bidding. Defer to the second round so partner gets first chance to buy. Why:
  - The card may form an *even stronger* combination for partner — either the 50-meld project or the 100-meld project.
  - The card may reveal that *partner has Sun strength*, so partner forms or takes Sun himself.
  - Caveat 1: this applies *only* when you intend to bid Sun AND the up-card does not specifically form your 100-meld (المية).
  - Caveat 2: when bidding Hokm, partner has the right to over-call you with either Ashkal or Sun anyway.
- Confidence: HIGH (clean text; explicitly numbered rule #3)
- Page: 03b:1
- Phase: BID (`Bot.PickBid` for seats 1–2, dealer-card-supported hands)
- Thresholds: seat ∈ {1, 2}; up-card "supports your strength"; intent = SUN; up-card does NOT complete 100-meld.

---

## C. Secrets of Pro 3 — Project-elimination logic from the 12 visible cards

### L10. The "12 visible cards" inference base **[FOCUS]**
- Source: 04_secrets_pro_3
- Arabic ≤15: «اول 12 ورقة التي تسقط في بداية اللعبة»
- English: A player can deduce his partner's or opponent's *project* (meld) by combining the 12 visible cards seen at the start of play:
  - the up-card (الورقة المكشوفة) at the start = 1 card
  - PLUS the first 3 cards each opponent and partner play = 3 cards
  - PLUS the 8 cards in your own hand
  - = 12 known cards
- Confidence: HIGH
- Page: 04:1
- Phase: PLAY (early — first one or two tricks)
- Thresholds: 12 cards total; reduces to 11 if you are the bidder, OR if the up-card was discarded on the first trick.

### L11. 100-meld (المية) negation by ONE card from a 5-card "two-section" project **[FOCUS]**
- Source: 04_secrets_pro_3
- Arabic ≤15: «الميه من ٥ أوراق ذات قسمين... الولد او العشرة احدهما ينفي المشروع»
- English: A 100-meld (5 consecutive cards in one suit) can be eliminated/refuted by sighting *one* key card. Specifically: if either the Jack (الولد) OR the Ten (العشرة) of a suit is among the 12 visible cards, the 100-meld in that suit is excluded.
- Confidence: HIGH
- Page: 04:1
- Phase: PLAY (early-trick deduction by partner / defenders)
- Thresholds: J or 10 visible in any suit ⇒ 100-meld in that suit ruled out.
- Example given: partner declared 100-meld; he played J of hearts (الهاص). You hold 10 of hearts. → Eliminate hearts as the 100-meld suit.

### L12. 100-meld negation by TWO cards (combinations)
- Source: 04_secrets_pro_3
- Arabic ≤15: «الكه مع... التسعه او العشرة او الولد ينفيان المشروع»
- English: Pairs visible that *together* eliminate a 100-meld in a suit:
  - Ace + (9 OR 10 OR J) — eliminates 100 in that suit
  - "الباشا" King + (8 OR 9 OR 10 OR J) — eliminates 100 in that suit (range goes one rank lower, 8 also counts here)
  - "البنت" Queen + any card *below* her (i.e. 7/8/9/10/J)
- Confidence: MEDIUM (the bullet about the Queen reads "with one of the cards beneath her", which I've interpreted as the standard descending range; exact ranks not enumerated for the Queen line)
- Page: 04:1
- Phase: PLAY (early)
- Thresholds: see card-pair list above.
- Note: the pasta on Saudi rank-order: A > 10 > K > Q > J > 9 > 8 > 7 in Sun; with Hokm the trump suit reorders J > 9 > A > 10 > K > Q > 8 > 7. The "100-meld" here means a 5-consecutive sequence regardless of trump status.

### L13. Worked example — eliminate 100-meld and play around partner's project **[FOCUS]**
- Source: 04_secrets_pro_3
- Arabic ≤15: «بالتأكيد سيصبح المشروع من جهة السبيت»
- English: Worked example. Partner bought Sun on up-card "ولد الشريا" (J of hearts? — actually الشريا is one of the four suits, transliterated). Partner is seat 2. Seat 1 (opponent) plays K-hearts. Partner declares 100-meld and plays J-hearts. Seat 3 plays 8-hearts. You are seat 4 holding A-hearts, 10-hearts, Q-diamonds, 7-diamonds out of your 8 cards. **Pro play:** since hearts are now eliminated as the meld suit (J-hearts visible), the meld must be in spades (السبيت). Therefore play A-hearts (collect the trick), then play a *spade* — to either help partner complete his spade meld or avoid leading hearts back.
- Confidence: HIGH
- Page: 04:1
- Phase: PLAY (lead choice on trick 2 after early visibility)
- Thresholds: —
- Note: this is a *concrete pickLead pattern* — once meld-suit is deduced, lead INTO that suit (or avoid the negated suit), not the suit just played.

### L14. 100-meld of "4 cards" variant — needs ONE-of-each-rank to refute
- Source: 04_secrets_pro_3
- Arabic ≤15: «من 4 اوراق هو ورقة من كل نوع»
- English: A 4-card 100-meld variant (carré-100? or 4-card sequence?) is refuted by sighting one card of each rank in the run, "from Ace down to 10" — but specifically *under Hokm*. **Under Sun**, you instead need one card from "King or Queen down to 10" (the rank "below an A" because Sun rank-order differs).
- Confidence: MEDIUM (text is terse and contract-conditional — the رتب/ranks listed are slightly garbled by extraction)
- Page: 04:1–2
- Phase: PLAY
- Thresholds: contract-conditional (HOKM vs SUN refutation set differs).

### L15. 4-Jacks / 4-Tens projects don't need to be refuted
- Source: 04_secrets_pro_3
- Arabic ≤15: «الربع بشوات او الربع عشرات... ال يحتاج بأن يحل»
- English: If a Jack and a Queen are both among the 12 visible cards, the project must be the 4-Jacks (الربع بشوات) or 4-Tens (الربع عشرات) carré. **These projects don't matter to refute** — partner doesn't need them dismantled because they self-resolve.
- Confidence: MEDIUM (Arabic text is terse; "وهذا المشروع اليهمنا معرفته ألنه ال يحتاج بأن يحل" — interpretation: carrés don't need disrupting because they're already locked in / resolution = self-evident)
- Page: 04:2
- Phase: PLAY (deduction)
- Thresholds: J + Q both visible ⇒ project is a carré, not a sequence.

### L16. 50-meld (الخمسين) negation table **[FOCUS]**
- Source: 04_secrets_pro_3
- Arabic ≤15: «الولد والعشرة معا ينفيان المشروع تماما»
- English: A 50-meld (4 consecutive in one suit) is eliminated by sighting any of these *pairs* among the 12 visible cards:
  - Jack + 10 — eliminates 50 completely
  - Ace + 10 — eliminates 50 completely
  - King + (10 OR 9) — eliminates 50
  - Queen + (10 OR 9 OR 8) — eliminates 50
  - Jack + any card *below it* (i.e. 9, 8, 7) — eliminates 50
- Confidence: HIGH
- Page: 04:2
- Phase: PLAY (early-deduction)
- Thresholds: see pairs above. Stated rule of thumb: "Jack with anything below it, OR 10 with anything above it, and so on."

### L17. 20-meld / Sira (سرى) negation table
- Source: 04_secrets_pro_3
- Arabic ≤15: «الورقتان التي تنفيان السرى هما البنت والتسعة»
- English: A 20-meld (3-card "Sira") is eliminated by sighting *Q + 9 together*. More specifically by anchor card:
  - Sira anchored on Ace-of-diamonds (سرى اكه الديمن) — eliminated by visible King OR Queen (الباشا أو البنت)
  - Sira anchored on King (سرى الباش) — eliminated by visible Queen OR Jack
  - Continue downward — Sira anchored on the 9 — eliminated by visible 8 OR 7
- Confidence: HIGH
- Page: 04:2
- Phase: PLAY (early-deduction)
- Thresholds: anchor-card-conditional — see list.

### L18. "These are not all the secrets — we cannot enumerate the rest"
- Source: 04_secrets_pro_3
- Arabic ≤15: «أبرز الحترافيات في لعبة البلوت وليس كلها»
- English: Closing disclaimer — these are the *most prominent* pro tricks but not the complete set; the rest are uncountable. (Treat the rules in this PDF as canonical-but-non-exhaustive.)
- Confidence: HIGH
- Page: 04:2
- Phase: META
- Thresholds: —

---

## D. What is Baloot — conceptual basis of scoring

### L19. Total card-points in a round = 162 **[FOCUS]**
- Source: 05_what_is_baloot
- Arabic ≤15: «مجموع اللعب ٢٦١» (= 162 — Indic-digit reversal)
- English: When the Hokm side of the game was created, the total point value of one round was calibrated to 162: 152 from the cards + 10 for last trick.
- Confidence: HIGH
- Page: 05:1
- Phase: SCORE
- Thresholds: round total = 162 = 152 cards + 10 last-trick-bonus.
- Note: confirms `K.LAST_TRICK_BONUS = 10` and round normalization.

### L20. Hokm raw card values per suit = 62 (before Belote bonus)
- Source: 05_what_is_baloot
- Arabic ≤15: «عدد الحكم ٢٦» (= 62)
- English: In a trump suit under Hokm, the card-points in that suit alone sum to 62: A=11 + K=4 + Q=3 + J=20 + 10=10 + 9=14 = 62.
- Confidence: HIGH
- Page: 05:1
- Phase: SCORE
- Thresholds: trump suit point breakdown:
  - Ace = 11
  - King = 4
  - Queen = 3
  - Jack = 20
  - Ten = 10
  - Nine = 14

### L21. Sun raw card values per suit = 90/3 = 30 each (90 total across 3 non-trump suits in Hokm)
- Source: 05_what_is_baloot
- Arabic ≤15: «الصن ٠٩ ل ٣ جهات» (= 90 across 3 sides)
- English: Under Hokm, the three non-trump suits together yield 90 points (= 30 per suit by Sun ranks). Plus 10 for last trick. So Hokm round = trump 62 + non-trump 90 + last-trick 10 = 162.
- Confidence: HIGH
- Page: 05:1
- Phase: SCORE
- Thresholds: non-trump suit values = standard Sun ranks; one-suit total = 30.

### L22. The "Baloot" bonus = +20 fixed on K+Q of trump (the conceptual origin) **[FOCUS]**
- Source: 05_what_is_baloot
- Arabic ≤15: «أعطوا البلوت القيمة ٢ ... بنت وشايب الحكم معا» (Baloot value 2; Q+K of trump together)
- English: To re-balance Hokm vs Sun (since Sun's 9 per suit × 10 = 90 and Hokm's 8 per suit × 10 = 80 originally), the rule-makers gave Hokm a fixed bonus of 20 (text writes "value 2" per card × 10? — see notes), placed on the Q + K of trump *together*. This is the Baloot (i.e. Belote in the WoW addon — `K.MULT_BEL`).
- Confidence: HIGH (logic explicit; the Indic-digit reversal makes "2" vs "20" ambiguous on its face but mathematically the bonus is 20)
- Page: 05:1
- Phase: SCORE / DECLARE
- Thresholds: bonus = 20; cards = K + Q of trump suit.

### L23. Baloot is multiplier-immune AND project-immune **[FOCUS]**
- Source: 05_what_is_baloot
- Arabic ≤15: «والينفيه السرى او الخمسين او المئة واليدبل»
- English: The Baloot bonus:
  - is NOT cancelled by Sira (20-meld), 50-meld, or 100-meld;
  - is NOT doubled by Bel/Bel-x2/Four/Gahwa multipliers («واليدبل»);
  - has a *fixed*, unchanging value;
  - belongs to *one of the players* (whoever holds K+Q of trump).
- Confidence: HIGH (this is the *authoritative* statement of Baloot immunity)
- Page: 05:1
- Phase: SCORE
- Thresholds: BEL bonus excluded from multiplier scope.
- Note: matches CLAUDE.md statement "Belote (K+Q of trump, +20) is multiplier-immune."

### L24. Baloot is CANCELLED on the side that declared a 100-meld **[FOCUS]**
- Source: 05_what_is_baloot
- Arabic ≤15: «فيلغى البلوت على صاحب مشروع المئة»
- English: Mathematical reasoning: with Baloot, total = 182, splittable 91/91. With 100-meld added, total = 262, splittable 131/131. If you ALSO add Baloot, total = 282, which is not divisible by 2 (because Baloot doesn't split). Therefore Baloot is *cancelled on the side that holds the 100-meld* so the parity stays at 131/131. **Conclusion: Baloot is auxiliary, not core; added for balance, removed for balance.**
- Confidence: HIGH
- Page: 05:2
- Phase: SCORE (interaction between BEL bonus and 100-meld)
- Thresholds: if a side has 100-meld → that side does NOT collect the +20 Baloot bonus.

---

## E. Doubling System (escalation chain) **[FOCUS]**

### L25. Hokm: doubling open from trick 1 **[FOCUS]**
- Source: 07_doubling_system
- Arabic ≤15: «بالحكم : يكون الدبل مفتوح من اول لعبه»
- English: Under Hokm, doubling is open from the first trick / first card. (Either side may invoke the multiplier chain immediately.)
- Confidence: HIGH
- Page: 07:1
- Phase: PRE-PLAY / PLAY
- Thresholds: Hokm contract → Bel/Triple/Four/Gahwa available from card 1.

### L26. Sun: no doubling allowed until score exceeds 100 **[FOCUS]**
- Source: 07_doubling_system
- Arabic ≤15: «بالصن : اليفتح الدبل ال بعد العدد ٠٠١» (= 100)
- English: Under Sun, doubling **does not open** until after the score reaches 100. Specifically: only the *trailing side* (the one whose score has not yet exceeded 100) may double, and only after the leading side has crossed that threshold.
- Confidence: HIGH
- Page: 07:1
- Phase: PRE-PLAY / mid-round
- Thresholds: Sun contract → Bel only available after score > 100; available *only to the trailing side*.

### L27. Hokm escalation chain: 4 rungs (Bel → Triple → Four → Gahwa) **[FOCUS]**
- Source: 07_doubling_system
- Arabic ≤15: «( دبل - ثري - فور - قهوة )»
- English: The Hokm doubling chain has exactly 4 rungs in this Saudi nomenclature:
  - **Dabl / Bel** (دبل) = ×2
  - **Three / Triple** (ثري) = ×3
  - **Four** (فور) = ×4
  - **Gahwa** (قهوة) = "the whole game taken" (see L31)
- Confidence: HIGH
- Page: 07:1
- Phase: PLAY (escalation)
- Thresholds: 4 distinct rungs in Hokm.

### L28. Bel (×2) arithmetic: 16 × 2 = 32 (per-suit-trick base)
- Source: 07_doubling_system
- Arabic ≤15: «يعني ٦١ * ٢ = ٢٣» (16 × 2 = 32)
- English: "Bel" means the Hokm trick-points sum is multiplied by 2: 16 × 2 = 32. **All projects/melds also double EXCEPT the Baloot — because Baloot is a fixed compulsory complementary value, not subject to doubling.**
- Confidence: HIGH
- Page: 07:1
- Phase: SCORE
- Thresholds: ×2 multiplier on (trick-points + projects/melds); BEL bonus excluded.
- Note: the "16" is the base trick-points per suit; here likely refers to the Hokm trick-point engine. The example arithmetic is canonical.

### L29. Triple (×3) arithmetic: 16 × 3 = 48
- Source: 07_doubling_system
- Arabic ≤15: «يعني ٦١ * ٣ = ٨٤» (16 × 3 = 48)
- English: "Triple" / Three means ×3: 16 × 3 = 48. Same scope: all projects double-and-trebble, EXCEPT Baloot. Formula: `(16 + project) × 3`.
- Confidence: HIGH
- Page: 07:1
- Phase: SCORE
- Thresholds: ×3 multiplier; BEL bonus excluded.

### L30. Four (×4) arithmetic: 16 × 4 = 64
- Source: 07_doubling_system
- Arabic ≤15: «يعني ٦١ * ٤ = ٤٦» (16 × 4 = 64)
- English: "Four" means ×4: 16 × 4 = 64. Formula: `(16 + project) × 4`. BEL still excluded.
- Confidence: HIGH
- Page: 07:1
- Phase: SCORE
- Thresholds: ×4 multiplier.

### L31. Gahwa = "whole-game taken" = 152 **[FOCUS]**
- Source: 07_doubling_system
- Arabic ≤15: «القهوة : تؤخذ اللعبة كاملة يعني ٢٥١» (= 152)
- English: "Gahwa" means **the entire round is taken**: value = 152 (= the full deck card-points before last-trick-bonus). At Gahwa rung, the 4× quadrupling (التربيع) is **always open** (forced/mandatory open).
- Confidence: HIGH
- Page: 07:1
- Phase: SCORE (apex multiplier)
- Thresholds: Gahwa = 152; quadrupling forced open.

### L32. Bel/Triple/Four are caller's choice: open vs closed **[FOCUS]**
- Source: 07_doubling_system
- Arabic ≤15: «من يطلب الدبل يختار مفتوح او مغلق»
- English: Whoever calls Bel chooses whether the quadrupling (التربيع) is *open* or *closed*. Same for the player who calls Triple or Four. **EXCEPTION:** at Gahwa, the quadrupling is always open (mandatory).
- Confidence: HIGH
- Page: 07:1
- Phase: PLAY (escalation declaration)
- Thresholds: caller-elects open/closed at Bel/Triple/Four rungs; forced-open at Gahwa.
- Note: "open" vs "closed" likely refers to whether the next escalation rung is available or locked-out for the rest of the round. (Terminology not further defined in this PDF.)

### L33. Hokm always plays with "Bnaat" regardless of doubling status **[FOCUS]**
- Source: 07_doubling_system
- Arabic ≤15: «الحكم يلعب ب البناط سواء كان اللعب دبل او بدون دبل»
- English: Hokm always plays with بناط (Bnaat / "points" — the trick-point multiplier system mentioned at L28–L30), whether the round is doubled or not. (Bnaat is intrinsic to Hokm scoring.)
- Confidence: HIGH
- Page: 07:1
- Phase: SCORE
- Thresholds: Hokm contract always uses Bnaat scoring engine.

### L34. Sun: ONLY Bel rung exists (no Triple, no Four, no Gahwa) **[FOCUS]**
- Source: 07_doubling_system
- Arabic ≤15: «نظام الدبل بالصن ( دبل فقط)»
- English: Under Sun the only doubling rung available is **Bel**. There is no Triple, no Four, no Gahwa under Sun. Reasoning: doubling only opens after score > 100, and the bidder doesn't *need* Triple because reaching 52 raw is enough to win — no further escalation is required. **And Sun has no Bnaat (no point-system multiplier).**
- Confidence: HIGH
- Page: 07:1
- Phase: ESCALATION (Sun-specific gate)
- Thresholds:
  - Sun chain length = 1 rung (Bel only).
  - Sun has no Bnaat scoring.
  - Bidder needs only 52 raw to win in Sun.

### L35. Sun-Bel arithmetic: 26 × 2 = 52 **[FOCUS]**
- Source: 07_doubling_system
- Arabic ≤15: «ويكون الدبل ٦٢ * ٢ = ٢٥» (= 26 × 2 = 52)
- English: Sun-Bel doubles **all projects** (26 base × 2 = 52). All meld projects ARE doubled (note: this contrasts with Hokm where the only exclusion is Baloot — Sun *has no Baloot* because the K+Q of trump bonus has no analogue in trumpless Sun).
- Confidence: HIGH
- Page: 07:1
- Phase: SCORE
- Thresholds: Sun-Bel multiplier ×2; full project scope.

### L36. Sun-Bel callable ONLY by the trailing side (لا تدبل الا من المتأخر) **[FOCUS]**
- Source: 07_doubling_system
- Arabic ≤15: «ويكون الدبل للمتأخر فقط وهو الذي لم يتجاوز عدده ٠٠١» (= ... whose score has not exceeded 100)
- English: Sun-Bel can only be invoked by *the trailing side* — defined as the side whose score has NOT yet exceeded 100. (The leader cannot double; only the catch-up side can.)
- Confidence: HIGH
- Page: 07:1
- Phase: PLAY (Sun escalation, mid-round)
- Thresholds: caller's score ≤ 100 (note: text says "not exceeded 100"); other side's score > 100 (implied trigger).
- Note: this is a tight legality gate — the bot must check both sides' scores, not just its own.

---

## F. Cross-cluster derived rules and notes

### L37. Belote/Baloot CANNOT be invoked under Sun (no trump → no K+Q-of-trump bonus) **[FOCUS]**
- Source: 05_what_is_baloot, 07_doubling_system (interaction)
- Arabic ≤15: derived from L22 + L26 absence
- English: Since Baloot is defined as the +20 bonus on K+Q of trump (L22), and Sun has no trump suit, Baloot does NOT exist as a player-claimable bonus in Sun contracts. (None of the Sun-doubling discussion in PDF 07 mentions Baloot — only "all projects double".)
- Confidence: MEDIUM (logically derived; not stated as a single negative rule, but consistent with the texts)
- Page: derived from 05:1, 07:1
- Phase: DECLARE (Sun contract precondition for Bel claim)
- Thresholds: contract = SUN ⇒ Baloot bonus = 0.

### L38. Trump rank-order in Hokm follows the suit-points table at L20
- Source: 05_what_is_baloot (point breakdown)
- Arabic ≤15: derived from L20 ranks
- English: The Hokm-suit point assignments (J=20, 9=14, A=11, 10=10, K=4, Q=3, 8=7=0) confirm the Hokm trump rank-order: J > 9 > A > 10 > K > Q > 8 > 7. Note that 9 *of trump* is rank 7 (second-highest), but does NOT count as a Carré — confirmed external (CLAUDE.md `K.CARRE_RANKS` excludes "9").
- Confidence: HIGH
- Page: 05:1
- Phase: ALL
- Thresholds: see L20 point breakdown.

### L39. Sun rank-order is descending A > 10 > K > Q > J > 9 > 8 > 7
- Source: 05_what_is_baloot (point arithmetic for non-trump 30/suit)
- Arabic ≤15: derived from L21 (90 points across 3 suits = 30 per suit)
- English: Under Sun, no trump. Sun rank-order (and hence trick-winning order) follows standard high-card-wins descending: A > 10 > K > Q > J > 9 > 8 > 7. Per-suit total of 30 points matches the Sun table (A=11 + 10=10 + K=4 + Q=3 + J=2 = 30; the 9/8/7 are 0).
- Confidence: HIGH
- Page: 05:1
- Phase: PLAY (trick-winning, Sun)
- Thresholds: see derivation.

### L40. Round normalization total = 162 with last-trick = 10 **[FOCUS]**
- Source: 05_what_is_baloot
- Arabic ≤15: «مجموع اللعب ٢٦١» (= 162)
- English: Confirmed: the round point total is 162 = 152 from cards + 10 from last-trick bonus. This is the score-normalization basis. Bidder must achieve **strict majority** (i.e. > 81) to make contract — fails on tied 81/162 (per CLAUDE.md).
- Confidence: HIGH
- Page: 05:1
- Phase: SCORE
- Thresholds: round total = 162; bidder threshold > 81 (strict majority); last trick = +10 raw.

---

## G. Open uncertainties / extraction caveats

### L41. UNCERTAIN — exact ranks for Queen-100 and Queen-50 negation lines
- Source: 04_secrets_pro_3
- Arabic ≤15: «البنت مع إحدى األوراق التي تحتها»
- English: The Queen lines for both 100-meld and 50-meld negation say "Queen with one of the cards beneath her" without listing them explicitly. Best-guess interpretation per L12, L16: Q + (any of 7/8/9/10/J), but the J might or might not count.
- Confidence: LOW
- Page: 04:1, 04:2
- Phase: PLAY (deduction)
- Thresholds: ambiguous.

### L42. UNCERTAIN — "44" in L06 source text **[FOCUS]**
- Source: 03_secrets_pro_1
- Arabic ≤15: «يتفادى ال 44 وال يهرب»
- English: The text reads "to avoid the 44, do not slough...". The literal "44" is anomalous. Best interpretation: a typo / extraction artifact for "ال" (a particle) reduplicated, possibly meant "ال 4-4" referring to the *Failing 4-4* result (a tied trick count?). May also encode an Indic numeral "٤٤" (= 44) that doesn't have an obvious referent. Could relate to "the" (الـ) followed by something. **Audit team should verify against original PDF.**
- Confidence: LOW
- Page: 03:1
- Phase: PLAY
- Thresholds: unknown.

### L43. UNCERTAIN — meaning of "open vs closed" التربيع at Bel/Triple/Four (L32)
- Source: 07_doubling_system
- Arabic ≤15: «يختار مفتوح او مغلق»
- English: PDF 07 states that the caller of Bel/Triple/Four picks "open or closed" for the التربيع (quadrupling). Two plausible interpretations:
  - (a) "open" = next escalation rung remains available; "closed" = locked at this rung (can't go higher).
  - (b) "open" = visible/declared to opponents; "closed" = hidden/sealed.
  Given Gahwa is *forced open* (L31), interpretation (a) is more natural (Gahwa is the apex, so "open" is moot — perhaps "closed" = no further escalation by anyone, "open" = others may re-double upward). **Audit team should reconcile against `Bot.PickDouble`/`PickTriple`/`PickFour`/`PickGahwa` semantics.**
- Confidence: LOW
- Page: 07:1
- Phase: ESCALATION
- Thresholds: unknown.

### L44. UNCERTAIN — the "16" base in L28–L30 arithmetic
- Source: 07_doubling_system
- Arabic ≤15: «٦١ * ٢ = ٢٣»
- English: The arithmetic 16×2=32, 16×3=48, 16×4=64 references a base value of 16 with no direct definition in the PDF. Possibilities: 16 = trump card-points minus Belote bonus (62 − 20 = 42... no); = trick-point Bnaat per suit-trick (per L33 reference to Bnaat); = constant in the Bnaat formula. **The audit team should map this to whatever `R.ScoreRound` does at multiplier rungs.** Note that the *practical* multiplier formula given is `(16 + project) × multiplier`, with project = the meld value.
- Confidence: LOW (the "16" is left undefined in this PDF; audit-only)
- Page: 07:1
- Phase: SCORE
- Thresholds: unknown base.

### L45. UNCERTAIN — exact "supported by up-card" meaning in L09
- Source: 03b_secrets_pro_2
- Arabic ≤15: «الورقة المكشوفة تدعم قوتك»
- English: PDF 03b says "if the up-card supports your strength" but doesn't formally define "supports." Heuristic interpretation: up-card is in your already-strong suit (3+ cards including high cards), making bidding the up-card's suit defensive vs offensive. **Audit team should map to `Bot.PickBid`'s strength-evaluation function.**
- Confidence: MEDIUM
- Page: 03b:1
- Phase: BID
- Thresholds: unknown definition of "support".

---

## H. Summary count

| Section | Rules | Of which **[FOCUS]** |
|---|---|---|
| A. Card-counting fundamentals (PDF 03) | L01–L06 (6) | L01, L02, L04, L06 (4) |
| B. Numbered bidding/lead rules (PDF 03b) | L07–L09 (3) | L07, L08, L09 (3) |
| C. Project-elimination logic (PDF 04) | L10–L18 (9) | L10, L11, L13, L16 (4) |
| D. Conceptual scoring basis (PDF 05) | L19–L24 (6) | L19, L22, L23, L24 (4) |
| E. Doubling system (PDF 07) | L25–L36 (12) | L25, L26, L27, L31, L32, L33, L34, L35, L36 (9) |
| F. Cross-cluster derived | L37–L40 (4) | L37, L40 (2) |
| G. Open uncertainties | L41–L45 (5) | L42 (1) |
| **TOTAL** | **45** | **27** |

---

## I. Key audit hooks for the v0.10.0 review

Quick-reference list of the highest-leverage **[FOCUS]** rules vs. likely code touchpoints:

| Rule | Code touchpoint to verify |
|---|---|
| L07 — Hokm requires Ace | `Bot.PickBid` HOKM precondition; reject HOKM if no Ace |
| L08 — Sun bidder seat 1 must lead backed Ace+T | `pickLead` for `K.BID_SUN`, seat 1, holding A+10 same suit |
| L09 — Seats 1/2 delay buy | `Bot.PickBid` defer-to-second-round logic |
| L11–L17 — Project negation tables | `Bot.PickPlay` opponent-meld inference (does code do this?) |
| L19–L21 — Round=162 + per-suit point tables | `Rules.lua` / `R.ScoreRound` constants |
| L22–L24 — Belote/Baloot semantics | `K.MULT_BEL` immunity + 100-meld interaction in scoring |
| L25–L27, L31–L33 — Hokm escalation chain | `Bot.PickDouble`/`PickTriple`/`PickFour`/`PickGahwa` legality |
| L26, L34–L36 — Sun-only-Bel + score-100 gate + trailing-side rule | Sun escalation legality gate; verify all three checks present |
| L40 — Strict-majority threshold | `R.ScoreRound` bidder-success check (must be > 81, not ≥) |

This concludes the source-L extraction.
