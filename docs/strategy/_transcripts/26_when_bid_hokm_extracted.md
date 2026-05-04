# 26_when_bid_hokm — extracted rules

**Source:** https://www.youtube.com/watch?v=zPLFYuLPnIA
**Title (Arabic):** متى تشتري حكم في البلوت للمبتدئين
**Topic:** When to bid Hokm (حكم) in Baloot — beginner-level hand-strength heuristics; companion to video #25 (Sun-bid).

---

## 1. Decision rules

| # | WHEN | RULE | WHY | MAPS-TO |
|---|---|---|---|---|
| R1 | Deciding whether to bid Hokm at all | Buy only if you have **the strongest cards in the would-be trump suit**, ordered: ولد (J=20 ابناء), تسعة (9=14), إكة (A=11), عشرة (T=10), شايب (K=4), بنت (Q=3), 8/7=0 | "أكبر شي عندنا الولد ثم التسعة" — the J + 9 of trump are uniquely the structural anchors of any Hokm hand | `Bot.PickBid` Bot.lua:725 — strength threshold via `K.BOT_HOKM_TH` |
| R2 | **Minimum Hokm-bid hand:** ولد (J of trump) + ONE other trump (مردوفة) + ONE إكة on the side | Bid Hokm. "أقل شي عشان تشتري الحكم يكون عندك الولد، وقطعة مثلا مردوفة معاه، ومعاك إكا وحدها" | J=20 ابناء plus a partner trump for follow + one off-suit Ace to capture an early non-trump trick | `Bot.PickBid` Bot.lua:725 — minimum threshold |
| R3 | First 5 cards: only 7 + 8 of would-be trump (الأصغر قطعتين), no Sun (no إكة, no عشرة) | **PASS — never bid Hokm.** "كيف حتمسك اللعب كيف حتاكل" | The 8 and 7 of trump are 0 ابناء and rank-1/2 (lowest); no path to taking any trick | `Bot.PickBid` Bot.lua:725 — strength=0 fallback |
| R4 | Trump-suit holding = 9 + 8 only, plus a small side filler (سرة) | Do NOT bid Hokm. "تسعة وثمانية ما تكفي… حتى ما عندك الولد" | Without J, your top trump is rank-7 (=14) but vulnerable to opp J; and your 8 is dead. Need the J anchor | `Bot.PickBid` Bot.lua:725 |
| R5 | Trump-suit = 9 + 7, plus 2 إكة on the side | **MAY bid Hokm.** "ممكن تشتري حكم… لأنه عندك أنت ذراك يقطع حكم معه مشروع وعندك برضو إكتين" | Trump-9 + 2 side Aces is borderline; the 9 alone is the cut, dual Aces give two side captures | `Bot.PickBid` Bot.lua:725 — augmented-strength path |
| R6 | Trump-suit = J + 8 + 7 (ولد + small fillers), no other trump, no side Sun | **MAY bid Hokm in early/mid game** but not strong | The J alone is enough to count; "أقل شيء يكون عندك الولد ومعه قطعة مردوفة" — having 3 trumps is the qualifying minimum here | `Bot.PickBid` Bot.lua:725 |
| R7 | You hold a **مشروع شريَة** (royal-sequence meld in the would-be trump suit, e.g. K-Q-J-T = 100 سراء ملكي) but NO J and NO 9 of trump | Bid Hokm anyway — **rare exception** to the J/9 requirement. "إذا كان عندك مشروع، والمشروع يكون في الحكم… بعض الناس يشتري حكم شرية" | The 100-meld + Belote (K+Q of trump = 20) + Sequence dominate even without J anchor; meld safety net | `Bot.PickBid` Bot.lua:725 — meld-detect path; `K.MELD_SEQ4`/`K.MELD_SEQ5` + `K.MELD_BELOTE` |
| R8 | Sequence/meld is in trump and you have **4+ trump cards** | **Strongly bid Hokm.** "لو عندك أربع قطع أحلى وأحلى. ولو كانت خمسة قطع أفضل" | Meld + trump-depth = high success probability | `Bot.PickBid` Bot.lua:725 |
| R9 | You hold ولد + تسعة (J + 9 of trump) together | **Definitely bid Hokm.** "جوا مع بعض يا سلام" | The two top trumps together are the canonical Hokm signature; "أكبر قطعتين" | `Bot.PickBid` Bot.lua:725 |
| R10 | You hold J + 9 of trump + 8 of trump + 2 Sun cards (إكة الشري + عشرة الشري) | **Definitely bid Hokm — حكم ثاني (non-mandatory trump).** Strong hand | 3 trump pieces with J/9 + 2 side Aces = guaranteed control | `Bot.PickBid` Bot.lua:725 |
| R11 | You hold J + 9 of trump + 8 of trump + Q of trump | **Bid Hokm — 4 trumps.** "ممكن يجيك سياق أحكام برضو، ممكن يجيك صن، أفضل وأفضل" | 4 trumps + meld potential from incoming partner-supply | `Bot.PickBid` Bot.lua:725 |
| R12 | You hold J + 9 of trump + 8 + side إكة (replacing what would be the Q) | Bid Hokm; **also fine as Sun** but speaker recommends Hokm | "جداً حكم قوي، ممكن تجيب كبوت على الخصم" — Al-Kaboot path is open | `Bot.PickBid` Bot.lua:725; pursuit logic in `pickLead` Bot.lua:953 |
| R13 | Trump = T + 9 + side Aces only, NO J in hand | **Borderline / contextual.** Speaker hesitant: "خصوصاً إذا كان بداية اللعب… ممكن تشتري" | T-9 + side strength can hold, but missing J makes opp J devastating; depends on score-state | `Bot.PickBid` Bot.lua:725 |
| R14 | Trump-anchor in your hand is **the إكة of trump** (not J or 9) — i.e. you'd have to bid Hokm "على إكة" | **The table will usually NOT let you take it.** Opp will likely bid Sun to override. "في ناس عندها عيب أنك تحكم على إكة لأنه إكة أكبر شيء في الصن" | The Ace is "الأرض" — the bid-up card; calling Hokm on the Ace is socially disfavored. Opps treat it as a bait/conversion signal | `Bot.PickBid` Bot.lua:725 — social-convention gate |
| R15 | You hold a Sun-strong hand AND want opps to take Sun (so you can crush them) | **Open with a Hokm bid as a feint** ("شبه تجبره أنه ياخذها صن"). If table goes silent, you'll fall into Hokm; if anyone bids Sun, you win double | "كثير يسوي هذه الحركة… عشان يشوف هل في أحد من اللاعبين راح ياخذها صن" | Bid-misdirection move; advanced player technique | `Bot.PickBid` Bot.lua:725 — feint mode (advanced tier only) |
| R16 | Doubling regime: opponent will likely call Bel (لعب مكفول vs مفتوح) | **Hokm strategy depends on doubling state.** Open game (مفتوح): need top trumps to ربع (lead trump). Closed game (مكفول): top-trumps less essential | "لو كان عندك أقوى أوراق في الحكم، اللعب دائماً المفتوح لصالحك" | Bel/double affects whether trump-leading remains the right play | `Bot.PickBid` Bot.lua:725 + `Bot.PickDouble` Bot.lua:1787 |
| R17 | Endgame: you 145, opp 145 (both close to 152 match-target); medium-strength Hokm hand | **Take Hokm.** "غالبا مبروك لك حتى لو الخصم عنده مشروع" | Hokm safer than Sun in endgame; failed Hokm = 16 raw vs failed Sun = 26 raw | `Bot.PickBid` Bot.lua:725 + `matchPointUrgency` Bot.lua:619 |
| R18 | Endgame with weak/medium Hokm hand AND opp is "تحت مرة" (well below match-target) | **Be CAUTIOUS.** Opp likely Bels — "فالخصم غالباً حيدبل، ما لولا الدبل" | Score-state Bel-fear: opp at <100 has every reason to Bel; weak-Hokm + Bel = guaranteed loss | `Bot.PickBid` Bot.lua:725 — Bel-fear path |
| R19 | Mid-game; bidder team strong; some hands let opp Bel pass without escalation | Some players "ما يخلونها قهوة" — let it stop at Bel × 2 (Bel-x2/ثري) so the round doesn't end the match | Pacing: avoid hand-closing escalation just to extend the session | Player-tier flavor |
| R20 | Hokm-Mughataa (covered/blind Hokm) is offered — you bid Hokm without seeing your 5 | Mechanically same as Sun-Mughataa from #25; if opp does this, **let them — it favors you**. "أكيد بيقول له خذ حكم مغطة يا رجال" | Blind bid is statistically losing; passively accept opp's hubris | Player-tier flavor; not a bot rule |
| R21 | Trump count: opp who has trumps sitting **AFTER you** in turn order | **Worse for you** than if they sit before you. "إذا كان بعدك… يجننك طبعا" | Position-disadvantage: opp following you can capture your trump leads with their J/9 | `Bot.PickBid` Bot.lua:725 — seat-relative Hokm-fear path |
| R22 | First 5 cards: 1 Q (بنت) of trump + 4 small side cards | Generally do NOT bid Hokm | Q rank-3 in trump (=3 ابناء); needs cover. Single Q ≠ minimum | `Bot.PickBid` Bot.lua:725 |
| R23 | First 5 cards: J + 8 + 7 of trump + 2 side cards (no Q, no K, no Aces) | **MAY bid Hokm in early game.** "إذا كان بداية اللعب أو وسط اللعب، ممكن تشتري فيها حكم عادي. إذا اشتريت إن شاء الله الورق يكبر معاك" | The 3 trumps with J meet the minimum; partner-supply (`سياق`) may complete | `Bot.PickBid` Bot.lua:725 |
| R24 | First 5 cards: 4 of one suit (e.g. 4 spades) including the J + 9 + side filler — heavy single-suit concentration | **Both Hokm and Sun are defensible.** Speaker presents both views. Choice depends on score-state and Bel risk | "هذه وجهة نظر… واللي يأخذها صن يقول لك أنا عندي إكتين، لكن عندي أربع قطع من الشكل هذا" | `Bot.PickBid` Bot.lua:725 — disambiguation by `scoreUrgency` |
| R25 | First 5: 50-meld in hand + ولد (J) of trump + would-be trump 9 of side card | **Bid Hokm.** Choice between Hokm vs Sun goes to Hokm "خصوصا لو نهاية اللعب" | Hokm + meld + endgame = highest safety | `Bot.PickBid` Bot.lua:725 |
| R26 | Hokm vs Sun: similar strength, hand has 50-meld in trump (i.e. 4 sequence pieces of trump including K-Q) | **Strongly prefer Hokm.** "في الصن صعب تجيب كبوت بهذا الورق. فالحكم في هذه الحالة أفضل" | Trump-concentrated hands are Hokm shape; Sun rewards multi-suit Aces, Hokm rewards trump depth | `Bot.PickBid` Bot.lua:725 |
| R27 | Hokm vs Sun, similar hand strength, score 145/145 endgame | **Hokm — explicit.** "لو كانت تسكى مثلا 145 لك والخصم 145 وخدت الحكم غالبا مبروك لك… لكن لو خدت صن يعتبر تهور" | Failed-bid penalty is explicit: Hokm 16 raw vs Sun 26 raw; "16 vs 26" is the speaker's recap | `Bot.PickBid` Bot.lua:725 + `matchPointUrgency` Bot.lua:619 |
| R28 | General "default" frequency: which contract does Saudi Baloot bid most? | **Most hands → Hokm.** "أغلب الناس يشتري حكم وليس صن" | Reasoning: (1) Hokm only requires J or 9 of trump + side cover; Sun requires Ace; trump-strong hands are statistically more common; (2) failure cost 16 raw vs 26 raw makes Hokm safer default | `Bot.PickBid` Bot.lua:725 — default-bias path |

### 1a. Hokm-Mughataa (الحكم المغطى — covered/blind Hokm)

| # | WHEN | RULE | WHY | MAPS-TO |
|---|---|---|---|---|
| R29 | You declare Hokm BEFORE seeing your 5 cards | **Mechanically identical to ordinary Hokm.** No separate scoring. Speaker says it's used like Sun-Mughataa from #25 — for هياط (taunting) when the round outcome doesn't matter | "نفس الصن من باب التقطقة" | `Bot.PickBid` Bot.lua:725 — no separate code path |
| R30 | Opp offers Hokm-Mughataa | **Let them.** "أكيد بيقول له خذ حكم مغطة يا رجال، اخترع أي شي بحياتك" | Blind bid is EV-negative for the bidder; pure positive for you | Player-tier flavor |

---

## 2. New terms (proposed for glossary)

| Arabic | Translation | Definition | Source |
|---|---|---|---|
| الحكم المغطى | "covered Hokm" / Hokm-Mughataa | Bidding Hokm blind, before seeing your 5 cards. Same scoring as ordinary Hokm. Used for هياط only | 26 |
| سراء ملكي | "royal sequence" — meld 100 in the trump suit (T-J-Q-K or J-Q-K-A in rank-card order) | Refers to Belote-strong sequence-of-4 in the would-be trump; the rare exception to the J/9-of-trump minimum | 26 |
| اللعب المفتوح / اللعب المكفول | "open game / closed game" — game state with vs without an active Bel | Bel-state shorthand. Open: no Bel; trump-leading is the natural play. Closed: Bel called; lower-power play favored | 26 |
| الورق يكبر معاك | "the cards grow with you" — i.e. partner-supply (سياق) and bid-up improve your hand mid-round | Common idiom for the post-bid hand consolidation | 26 |
| ربع / يربع (in Hokm context) | "to lead trump" (lead from your trump pieces) | Verb-form for the act of pulling trump from a strong-trump hand | 26 (also 04, 08) |
| سياق | "the partner-supply card" — the 3rd card dealt after the 5 + bid-up that completes a player's 8 | Saudi-specific term for the second-deal cards. Not currently in code | 26 |
| تك / تك له | "T (Ten) for him" — context idiom for "if his T was the high there, you could capture it" | Used to describe pos-after-you opp's likely strong cards | 26 |
| النشرة | "scorecard / running ledger" | Cumulative-score tracker; same as `S.s.cumulative`. Already noted in #25 | 26 corroborates |
| مردوفة (in Hokm context) | "doubled" — second card of the same trump suit accompanying the J or 9 | Already noted in #25 for Sun (إكة مردوفة); here it generalizes to "any second-of-suit cover" | 26 corroborates |

---

## 3. Contradictions

None within this transcript.

**Cross-video alignment:**
- R28 (Hokm-default frequency) **corroborates** #25's R24 ("الحكم أرحم… 16 vs 26") and elevates it from a hedge to an authoritative default. Already in `decision-trees.md` Section 1 — this video upgrades confidence to **Common** (now 2 sources: #25, #26).
- R2 (canonical minimum: ولد + مردوفة + إكة) is a **NEW pattern** parallel to #25's "A+T mardoofa" minimum for Sun. Belongs as a new row in `decision-trees.md` Section 1.
- R7 (سراء ملكي override) is a **NEW exception** — the only sub-case where Hokm bidder may lack J/9 of trump.
- R28 also reaffirms #25's R24 explicit failure-penalty difference: "الحكم 16 نقطة والصن 26."

---

## 4. Non-rule observations — Hokm-bid trigger summary

### Hokm-bid trigger conditions — what hand patterns justify Hokm?

The speaker's framework runs in three concentric tiers:

1. **Mandatory bid (very strong):** ولد (J of trump) + تسعة (9 of trump) together, plus 1+ side إكة or extra trump. Hokm "definitely" — possible Al-Kaboot path. (R9, R10, R11, R12)
2. **Confident bid:** ولد + 1 other trump piece (مردوفة) + 1 إكة on the side. **This is the canonical minimum hand.** (R2)
3. **Borderline / context-dependent:** 9 + 7 of trump + 2 side Aces → bid only if score-state and turn-order favor you (R5); 3 trumps with J but no Aces → bid in early/mid game only (R23).

**Special exception:** سراء ملكي (a 100-meld in the would-be trump suit — T-J-Q-K) lets you bid Hokm with NEITHER J NOR 9 of trump. This is the only sub-case (R7).

**Mid-Hokm-bid escalation factors:** trump-count is the single most important property. **3 trumps = minimum**, 4+ trumps = strong, 5+ = guaranteed Al-Kaboot pursuit (R8, R11, R12). Side-suit Aces add capture power but do NOT replace trump depth.

### Hokm-bid anti-triggers — when NOT to bid Hokm?

- **Trump-suit = 7 + 8 only** (the two lowest trumps), no Sun → never (R3).
- **Trump-suit = 9 + 8 only** (no J, no Aces) → never (R4).
- **Single Q of trump only**, no other trump pieces, no Aces → never (R22).
- **Bid-up card (الأرض) is the إكة** AND you have only 1-2 trumps → opps will override to Sun, "ما يخلونك تحكم" (R14).
- **Endgame with weak Hokm hand AND opp far behind** → opp will Bel for survival; your weak Hokm + Bel = guaranteed loss (R18, R21).
- **Opp at trump-position AFTER you in turn order** holding 4+ trumps → "يجننك"; Hokm becomes structurally hard (R21).
- **Hand has multi-suit Aces (no trump anchor)** → wrong shape; this is the Sun pattern, not Hokm.

### Trump-count threshold — minimum trumps; J of trump? 9 of trump? Aces?

**Minimum trump count: 3 trumps** with at least one being the J. Speaker explicit: "أقل شي عشان تشتري الحكم يكون عندك الولد ومعه قطعة مردوفة." (R2)

| Trump count | Status |
|---|---|
| 0–1 trumps | PASS unless Sun bid |
| 2 trumps including J | Below minimum; PASS |
| 2 trumps NO J | PASS |
| 3 trumps + J included | **MIN (canonical Hokm-bid)** |
| 3 trumps NO J, NO 9 | PASS unless سراء ملكي meld (R7) |
| 4+ trumps with J or 9 | Confident bid |
| 5+ trumps | Al-Kaboot pursuit shape |

**J of trump priority:** the J (ولد) is **strongly preferred** as the trump anchor. Speaker repeats "الأفضل يكون عندك الولد تسعة" but treats J alone (without 9) as already-qualifying with cover.

**9 of trump priority:** the 9 alone WITHOUT J is **borderline** — the J is the dominant rank. R5 (9 + 7 + 2 Aces) is "ممكن" — possible but contextual. R4 (9 + 8 alone with side filler, no Aces) is anti-trigger.

**Side-suit Aces:** each off-suit إكة is a trick-capture but does NOT substitute for trump depth. The "magic" Hokm bid is **trump pieces + side Aces**, not "Aces alone." (R5, R10, R11, R12)

### Comparison vs Sun — when is Hokm safer than Sun on a borderline hand?

The speaker's heuristic: **default to Hokm; bid Sun only on trump-poor multi-Ace hands.**

| Hand shape | Recommendation |
|---|---|
| 2 إكة + 1 إكة + 0 trumps | Sun |
| إكة مردوفة (A+T same suit) + 1 إكة elsewhere | Sun |
| ولد + 1 trump cover + 1 إكة | Hokm (canonical minimum, R2) |
| ولد + تسعة + 1 إكة | Hokm (R9, R10) |
| 4 trumps + 0 Aces | Hokm |
| 3 trumps + 2 Aces | **Either** — depends on score-state. Sun if you fear Bel; Hokm if endgame |
| 50-meld in trump suit + ولد | Hokm; "خصوصا لو نهاية اللعب" |
| 100-meld in trump (سراء ملكي) without J/9 | Hokm — exception path (R7) |
| Endgame (145/145) borderline | Hokm — explicit (R27) |
| 4 إكة (الأربع مئة) | **Sun mandatory** (per #25 R14) |

The speaker explicitly: "أغلب الناس يشتري حكم وليس صن" — Hokm is the dominant default because (1) trump-strong hand patterns are more common than 2-Ace patterns, and (2) the failure cost is lower.

### Specific failed-bid penalty: 16 raw (vs Sun's 26) — discussed in Hokm context?

**YES — explicitly discussed.** Near the close of the video (transcript line ~787), the speaker recaps:

> "الحكم 16 نقطة والصن 26، فلو أخدت حكم وخسرت عليك أهول من أنك تأخذها صن، خاصة لو في مشاريع."

Translation: "Hokm fails at 16 points, Sun at 26. So if you take Hokm and lose, it's lighter than taking Sun — especially when there are melds [you've revealed]."

This 16/26 split is the speaker's **most concrete numerical justification** for the "default to Hokm" rule. It's the same Qaid-style penalty structure as in `saudi-rules.md` (Qaid post-bid: 26 Sun / 16 Hokm) but here applied to the **failed-bid** outcome — not the Qaid penalty case. Same magnitude.

Speaker uses this in two places: (1) early discussion of why bidder caution matters in endgame, (2) closing recap of "why Hokm is the bot's preferred default."

### Other useful non-rule observations

- **Bel-state changes the play, not the bid threshold:** an open game (لعب مفتوح, no Bel) rewards trump-leading (ربع), so top trumps matter more; a closed game (مكفول, Bel called) reduces the value of the J+9 anchor because lead-pulls are penalized. Bel-state is post-bid context but informs the bid decision via Bel-fear (R16, R18).
- **First-lap pass discipline (carryover from #25):** the same first-lap pass policy applies to Hokm — wait for second lap on borderline hands. Speaker references #25 explicitly.
- **Position-relative trump fear:** opp seated AFTER you with 4+ trumps is the worst case ("يجننك"). Speaker recommends factoring seat order into the bid — same as #25's "5 inputs" framework, point 5.
- **Partner-supply optimism (سياق):** the speaker repeatedly says "ممكن يجيك سياق" — partner-supply may complete weak Hokm hands. Speaker treats this as a real EV factor in bidding borderline hands (R5, R23).
- **"Hokm على إكة" social taboo (R14):** if the bid-up card is the إكة, calling Hokm to "use it as trump" is socially disfavored — opps usually bid Sun to override. This is a real interaction effect on the bid, not just a flavor observation.
- **Feint-bid technique (R15):** opening with a Hokm bid when you actually want Sun, hoping someone else takes the Sun bait. Player-tier maneuver; advanced bots only.

---

## 5. Quality notes

- **Whisper transcription quality:** acceptable but lower than #25. ~10 lines of spurious "ثلاثة" repetition (probably Whisper hallucinating on a silence interval, lines 575–602); ignore. Card terms (ولد, تسعة, إكة, شايب, بنت, مردوفة, مشروع, السراء, القهوة) are clean.
- **Speaker discipline:** medium. The hand-pattern walk-through is the strongest section; conversational hedging on margin cases is heavy ("ممكن… على حسب… يعتمد عليك"). Numerical thresholds are stated explicitly only for the 16-vs-26 failure cost.
- **Worked examples:** ~12 hand patterns walked through (R3–R13, R22–R25). Speaker is consistent across them; the "minimum bid" pattern (R2) is mentioned ~3 times for emphasis.
- **Numerical specificity:** modest. Concrete: 16/26 failure penalty (recap), 145/152 endgame thresholds (R17, R27), trump-card values 20/14/11/10/4/3 (recap). No percentages or EV computations — pure heuristic reasoning, same as #25.
- **Confidence calibration:** treat R2, R3, R7, R9, R28 as **Definite** within this single source — speaker is unambiguous. R5, R6, R13 (borderline cases) are **Sometimes**. R7 (سراء ملكي exception) is **Definite** per speaker but **Common** because some Saudi sources treat sequence-only Hokm as house-rule territory; cross-corroborate before code change.
- **Caption-error risk:** "ربع" (rabbaʕ — to lead) is correctly captured; no homophone confusion. "سراء" (sequence) is captured though one Whisper drift to "شراء" (buying) in line 187 — context disambiguates. Card-name family-trio (شايب=K, بنت=Q, ولد=J) used consistently throughout.
- **Single-source caveats:** R7 (سراء ملكي override) and R15 (feint-bid technique) are single-source and need cross-reference. R29-R30 (Hokm-Mughataa) is single-source and corroborates #25's Sun-Mughataa structure.
- **Code-mapping notes:** all rules map to `Bot.PickBid` Bot.lua:725 with assist from `K.BOT_HOKM_TH` (currently the implicit threshold), `K.BOT_BEL_TH`=60 (Bel-fear path R18), `scoreUrgency` Bot.lua:588, `matchPointUrgency` Bot.lua:619, and `K.MELD_SEQ4`/`K.MELD_BELOTE` for the meld-exception path R7.
- **Highest-priority rules for `decision-trees.md` Section 1 update:** R2 (canonical minimum hand pattern), R7 (سراء ملكي meld exception), R14 (Hokm-on-Ace social gate), R28 (Hokm-default-bias quantified at 16 vs 26 raw). These four are the load-bearing additions from this video.
