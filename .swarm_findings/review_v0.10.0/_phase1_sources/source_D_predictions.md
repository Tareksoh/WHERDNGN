# Source D — Predictions (vkY55gg-39k #05 + zCubr1YEJBE #13)

**Sources**
- `vkY55gg-39k_05_baloot_predictions_general.ar-orig.srt` — "predictions in Baloot" (Sun explained first, then Hokm). Auto-captioned Arabic; transcript noisy in places (token خويه vs خويك, OCR-style typos like "كل هاوس" for "كاتل"/"كتلة", "الحكومه" for "الحكم"). Treated as canonical Section-6 video per existing `signals.md` notes.
- `zCubr1YEJBE_13_predict_trick.ar-orig.srt` — "who will eat the trick" (predicting the trick winner Pos-by-Pos, then leveraging that to over- or under-trump).

**Domain**: prediction of (a) where the missing big cards live, and (b) who will win the current trick — both in Sun and Hokm. Arabic shape names: السبيت/السميد = spades-equivalent / suit being illustrated, الحكم = trump, الصن = Sun (no-trump). Card names: الاكه=A, العشره=10, الشايب=K, البنت=Q, الولد=J (in Hokm, J=highest), التسعه=9, الثمانيه=8, السبعه=7.

---

## Coverage map

| Topic | Video #05 | Video #13 |
|---|---|---|
| 8 cards per suit, deck arithmetic | covered | covered |
| Sun rank order (A>10>K>Q>J>9>8>7) | covered (implicit through "after 10s, K, Q, J…") | explicit ("اكا… ثم العشره… ك ب 11 بنطلع عشره ب10 قريبه من بعض… شايب اربع بنات… البنت ثلاثه… الولد") |
| Hokm rank order (J>9>A>10>K>Q>8>7) | covered (rank by trump from J down to 7) | covered |
| AKA-receiver signals (touching honors) | **canonical Section 6 source — covered in detail** | mentioned, less detailed |
| Confidence buckets (95% / 90% / 99% / 50/50 / 10%) | numeric tiers stated | numeric tiers stated |
| Pos-1 / Pos-2 / Pos-3 / Pos-4 dependencies | implicit | **explicit** ("الحله رايحه فين بنسبه 100%" only at Pos-4 with all 3 cards down) |
| Touching-cards inference (متتاليه) | covered | covered |
| Cut/قطع inference about void in suit | covered | covered |
| Trump-count arithmetic (8 trumps, who has remainder) | covered (extensive worked examples) | covered |
| Lead-from-bottom trick (تحت) trickery | mentioned ("عشان يطيح عليك") | covered ("بعضهم يلعب الشاي في البدايه عشان يطيح عليك") |
| "Smallest-card-played → most cards in suit" prior | covered ("اللاعب اللي يلعب اصغر ورقه تفترض عنده اوراق اكثر") | indirect |
| "Always assign consecutive cards to partner" rule | covered ("دائما اعطي خويك الورقه المتتاليه") | covered |
| 50/50 split of unknowns when no signal | covered ("نص بالنص") | implied via balance/توازن advice |
| Balance / توازن (play the median card) | covered briefly | **covered in depth** (median-of-three heuristic) |
| 70/25/5 receiver priors | NOT stated | NOT stated |

---

## Rules extracted

> Numeric-tier convention used below (taken verbatim from the transcripts): **near-100% (99–100%)**, **~95%**, **~90%**, **~50/50**, **~10%**.

### R1. Deck arithmetic baseline
- **Source**: #05 ~00:19–00:43
- **Arabic ≤15**: "اربع اشكال كل شكل منه ثمانيه اوراق"
- **English**: 4 suits × 8 cards = 32 deck. After your hand + the 3 cards on the table, count what is missing among the other two opponents.
- **Confidence**: certain (rule of arithmetic).
- **Hand-shape**: any.
- **Phase**: any trick.
- **Thresholds**: card_count_remaining = 8 − seen_in_trick − seen_in_hand − seen_in_history.

### R2. "If opponent answered (followed) without taking, he holds nothing higher in that suit"
- **Source**: #05 ~03:27–03:36
- **Arabic ≤15**: "اذا الخصم لعب ورق وانت ماكل حله معناته ما عنده اسهر منها"
- **English**: When an opponent **follows suit but plays small** (didn't try to win), they have **no higher card of that suit remaining** — no 10, no K, no Q above what they discarded.
- **Confidence**: high (≈95% per video).
- **Hand-shape**: any; receiver of an under-played follower.
- **Phase**: mid-trick (after Pos-2/Pos-3/Pos-4 plays under).
- **Thresholds**: deterministic — used to mark cards "definitely not at player X".

### R3. Touching-honors signal — when partner leads bare A, follower's choice signals
This is the **Section-6 canonical content**. Encoded as one rule per follower-card. All assume Sun unless tagged as Hokm.

#### R3a. Partner plays A, you respond with **10** → strongest "I have the K" partner signal
- **Source**: #05 ~03:48–04:03
- **Arabic ≤15**: "في اصول البلوت اذا خويك لعب عشره يعني… مع الشايب"
- **English**: When your partner leads and you (or a player on your side) plays the **10 second-highest**, by Baloot conventions you **also hold the K** (شايب) — i.e. the next-touching card down. "بشكل عام اذا واحد لعب اي شيء غير الايكه بنسبه كبيره جدا ما عنده الاك" (he probably doesn't have the A, hence partner has it).
- **Confidence**: high (~99% in #13's rephrasing: "اذا لعب العشره بنسبه 99.99").
- **Hand-shape**: signaller has K (and possibly Q below).
- **Phase**: Pos-2 / Pos-3 receiver after partner's lead, Sun.
- **Thresholds**: — "as a rule, not always" (#05).
- **[FOCUS]** — directly affects `Bot.PickAKA` / signal interpretation.

#### R3b. Partner plays A, you respond with **K (شايب)** when 10 is gone
- **Source**: #05 ~04:48–05:13
- **Arabic ≤15**: "اذا هذا الخصم لعب الشايب احتمال يكون عنده عشره فقط"
- **English**: If a player plays the K, possibilities are: (a) it was the smallest he had (no 10, no Q, no J — impossible to play below it), so he has only the K and the 10 is at one of the **other** two opponents; OR (b) he plays K with 10 covered, meaning his side now claims the lead. Reading: 10 is **not** at partner if K and A are both visible elsewhere.
- **Confidence**: ~85–90% (deduced via elimination).
- **Hand-shape**: any.
- **Phase**: any after K is played.
- **Thresholds**: stated in #05 as an elimination chain.
- **[FOCUS]**

#### R3c. Partner plays A, you respond with **Q (بنت)** → "I hold J (ولد)" signal
- **Source**: #05 ~05:13–05:18
- **Arabic ≤15**: "ولو هذا لعب بنت السبيت خويك مع الولد"
- **English**: A player who plays Q in Sun signals he also holds the J — same touching-down chain as 10→K. Use this in symmetrical fashion when reading mid-rank honors.
- **Confidence**: high (~90%).
- **Hand-shape**: signaller has J.
- **Phase**: Pos-2/3/4 honor signal, Sun.
- **Thresholds**: — convention.
- **[FOCUS]**

#### R3d. Partner plays A, you respond with **J (ولد)** → bottom-of-honors, no nearby honor
- **Source**: #05 ~05:16–05:22 (combined with R3c)
- **Arabic ≤15**: "هذا لعب اصغر شيء عندي اللي هو الشايب وهذا لعب اصغر شيء عنده اللي هو البنت"
- **English**: When the player plays the **smallest of the honor block he holds**, you should infer he has nothing useful beyond what's just been discarded — opponents on the next trick will likely cut/over-trump. (Implication for AKA receiver: J is a "no I have nothing" reply; do NOT continue leading bare honors.)
- **Confidence**: medium (~50/50 per #13 framing).
- **Hand-shape**: signaller weak.
- **Phase**: Pos-2/3/4 reply, Sun.
- **Thresholds**: — used as "they will cut next trick" warning.
- **[FOCUS]**

#### R3e. Partner plays A, you respond with **9 / 8 / 7 (تسعه/ثمانيه/سبعه)** → discouraging
- **Source**: #13 ~01:03–01:10 (under "play smallest with zero-bnaq" rule); #05 ~04:08–04:50 (small-cards-played-under)
- **Arabic ≤15**: "تلعب اصغر الورق… التسعه 8 7 في الصن يعني بصفر ابناغ"
- **English**: Small cards (9/8/7) in Sun carry **0 points (ابناء)**, so playing one **discourages further A-runs**: it says "I have nothing in this suit, do not lead it again." Encoded as: 9 ≈ "no honor + I have at most one small left," 7 ≈ "longest in this suit, please switch."
- **Confidence**: high (deterministic: small cards have 0 ابناء in Sun).
- **Hand-shape**: signaller suit-weak (low cards only).
- **Phase**: AKA/lead reply.
- **Thresholds**: — categorical ("zero abna3").
- **[FOCUS]**

#### R3f. Asymmetry of side: own-partner **cannot** under-cut you, opponents **can**
- **Source**: #05 ~03:17–03:22
- **Arabic ≤15**: "انت ما تقيد على خويك لكن هذا خصم ممكن يقيد عليه"
- **English**: A signal sent **by your partner** is reliable — they will not deliberately mislead. Signals **by opponents** can be deliberate "تقيد" (deception); discount accordingly.
- **Confidence**: framing rule (always-true asymmetry).
- **Hand-shape**: any.
- **Phase**: any.
- **Thresholds**: — discount opponent signals; trust partner signals at face value.
- **[FOCUS]**

### R4. Confidence-tier values (the three buckets)
- **Source**: #05 ~04:36–04:48 ("95% ما عندي اصغر من عشره… هذا 90% فرق بسيط بينهم"); #13 ~02:23 ("100% ما فيها كلام"), #13 ~05:54–06:02 ("اذا لعب العشره بنسبه 99.99"), #13 ~07:13–07:18 ("بنسبه 50% او خويك بنسبه 50%"), #13 ~06:14–06:18 ("نسبه 10% مالك")
- **Arabic ≤15** (representative): "العشرتك… 95%… 90%… 50% او خويك بنسبه 50%"
- **English**: The transcripts use exactly three discrete confidence buckets when stating priors:
  - **near-100%** ("100%", "99.99%") — used for "trick winner is 100% known when all 3 cards are down" (R10) and for the "he played 10 → no smaller of that suit" inference.
  - **~85–95%** ("95%", "90%") — used for the canonical "he led 10 from a player on your right" → "it's yours" (95%) vs "he led 10 from far position" → 90% — explicitly contrasted as "فرق بسيط بينهم".
  - **~50/50** — for unknowns split between the two unknown-card positions when no signal disambiguates.
  - **~10%** — used as the residual "he is bluffing / leading a 10 from doubleton" exception.
- **Confidence**: rule-of-thumb.
- **Hand-shape**: any.
- **Phase**: any prediction.
- **Thresholds**: discrete tiers `{100, 95, 90, 50, 10}`. **Note**: The buckets `{near-100, ~85–90, ~50/50}` from the watchpoint are present but **with an extra 95 and 10 tier**; not strictly 3 buckets.
- **[FOCUS]** — affects scoring weights anywhere the bot encodes "P(card at player X)".

### R5. "70/25/5 receiver priors"
- **Source**: NOT STATED in either transcript.
- **Arabic ≤15**: n/a.
- **English**: Neither video explicitly states a 70/25/5 split for AKA-receiver positional priors. The closest analog is R4 (95/90/50/10). The 70/25/5 numbers are **not derivable** from these two sources.
- **Confidence**: absence-of-evidence.
- **[FOCUS]** — flag as **MISSING / ABSENT** in cross-reference.

### R6. Pos-1 (leader) prediction
- **Source**: #13 ~02:08–02:23
- **Arabic ≤15**: "اذا البدايه يعني هذا اللاعب تقدر تتوقع الحله رايحه فين بنسبه 100%"
- **English**: Wait — careful translation: "If you (the player) lead, you can predict where the trick will go with 100% confidence" — meaning **you control where it goes**, since you choose the lead and know your own hand. As soon as Pos-2 (partner) plays, the certainty is reduced.
- **Confidence**: deterministic (tautology).
- **Hand-shape**: any leader.
- **Phase**: Pos-1 lead.
- **Thresholds**: 100% before any other card is shown.
- **[FOCUS]** — prior at Pos-1 = full control, not a probability distribution.

### R7. Pos-2 prediction (after partner has played)
- **Source**: #13 ~02:39–02:43
- **Arabic ≤15**: "بعد الخويه اذا خويك لعب راح تقل النسبه"
- **English**: Once your partner has played, your prediction confidence **drops** below 100% (transcript actually says "100%" here, but is contrasting with the next case — interpretation: marginally less than full certainty).
- **Confidence**: marginal — use ~95–99%.
- **Hand-shape**: any.
- **Phase**: between Pos-1 lead and Pos-3 reveal.
- **Thresholds**: implicit; interpret as "still very high but admit one unknown opponent".
- **[FOCUS]**

### R8. Pos-3 prediction (after partner + one opponent have played)
- **Source**: #13 ~02:47–03:01
- **Arabic ≤15**: "اي لاعب من هذول الثلاثه اللاعبين يلعب اكا… مين راح ياكل"
- **English**: With two cards on the table, you can name who is currently winning; you do not yet know what the **last** opponent will overtrump with, but if you have already played (i.e. you are sitting after them), you can finalise.
- **Confidence**: high (~90%).
- **Hand-shape**: any.
- **Phase**: Pos-3 turn or analysing trick from Pos-3's perspective.
- **Thresholds**: — depends on whether the missing player is you or opponent.
- **[FOCUS]**

### R9. Pos-4 prediction (everyone has played)
- **Source**: #13 ~02:23–02:32
- **Arabic ≤15**: "هذا لعب وهذا لعب وهذا لعب… اكبر ورقه موجوده هنا"
- **English**: With all three other cards down, it's deterministic: largest card on the table wins (subject to trump-cut rules). Pos-4 prediction is **100%**.
- **Confidence**: deterministic.
- **Hand-shape**: any.
- **Phase**: Pos-4 — Bot is deciding its own card.
- **Thresholds**: 100%.
- **[FOCUS]** — when bot is at Pos-4, prediction reduces to "look at table, apply trump rules."

### R10. Highest free card → trick winner (Sun)
- **Source**: #13 ~02:51–02:58
- **Arabic ≤15**: "اول شيء اكبر ورقه في الصن عندنا ايش الاكه"
- **English**: In Sun, the trick winner = whoever played the highest still-live rank, where the rank order is A>10>K>Q>J>9>8>7. Track which honors have been played in earlier tricks; if A is dead, then 10 is "free"; if both dead, K is free, etc. Then anyone holding the **next free card** is the predicted winner.
- **Confidence**: deterministic.
- **Hand-shape**: any.
- **Phase**: any.
- **Thresholds**: — categorical.
- **[FOCUS]**

### R11. Highest free card → trick winner (Hokm)
- **Source**: #05 ~09:50–10:05 (Hokm rules section); confirmed throughout
- **Arabic ≤15**: "ولد الى السبعه" — J highest down to 7
- **English**: In Hokm (trump), rank order is **J > 9 > A > 10 > K > Q > 8 > 7** (Saudi convention; matches `CLAUDE.md` "9 of trump is rank 7 (second-highest)"). Same "next-free-card" logic as R10 with this order.
- **Confidence**: deterministic.
- **Hand-shape**: any.
- **Phase**: any.
- **Thresholds**: categorical.

### R12. "Cut by another suit ⇒ player is void in led suit"
- **Source**: #13 ~03:55–04:03
- **Arabic ≤15**: "اي واحد يقطع غير شكل الارض ما راح يفرق معنا"
- **English**: If a player ruffs (قطع) using a non-trump that isn't the led suit, they are confirmed void in the led suit. (Trivially mandatory: must follow suit if able. Not new but noted as basis for void-tracking.)
- **Confidence**: deterministic (rules-enforced).
- **Hand-shape**: any.
- **Phase**: any.
- **Thresholds**: — used to mark `void[player][suit] = true`.

### R13. Pre-emptive lead of 10 → "I am void of A in this suit"
- **Source**: #13 ~04:05–04:35; #05 mentions same
- **Arabic ≤15**: "واحد لعب 10 في البدايه تتوقع بنسبه كبير انه ما عندي لك"
- **English**: A player who **leads** the 10 of a suit almost certainly does not hold the A of that suit (else they would have led the A first to "make the trick safe"). Stated explicitly at "**99.99%**" in #13.
- **Confidence**: ~99.99% per #13.
- **Hand-shape**: lead strategy.
- **Phase**: Pos-1 lead at any trick.
- **Thresholds**: — but with a residual ~10% counter-trick: "ممكن يفكر يصير العشره" (he plays 10 from a doubleton expecting partner to win the A back — see R20).
- **[FOCUS]** — affects bot's read of opponent leads.

### R14. Pre-emptive lead of K → very likely no A
- **Source**: #13 ~05:42–05:47
- **Arabic ≤15**: "اذا لعب الشايب… ممكن يكون عند العشره لك غالب"
- **English**: A player who leads the K of a suit very likely holds the 10 too (covered) but does NOT hold the A. Probability bucket: ~90%.
- **Confidence**: ~90%.
- **Hand-shape**: lead.
- **Phase**: Pos-1.
- **Thresholds**: 90%.

### R15. Lead-from-bottom (تحت / "make-it-fall on you") tactic
- **Source**: #13 ~04:08–04:12, ~06:02–06:09
- **Arabic ≤15**: "بعضهم يلعب الشاي في البدايه عشان يطيح عليك"
- **English**: Skilled opponents sometimes lead a small card (e.g. 7) to make YOU spend the A — i.e. they have the K behind it, hoping you waste your A on a small trick so they can later lead theirs. Rule: don't reflexively eat a small lead with your A unless trick value justifies it.
- **Confidence**: heuristic.
- **Hand-shape**: AKQ-block holder.
- **Phase**: any lead-response by Pos-2/3/4.
- **Thresholds**: — judgmental.

### R16. "Smallest card played → has the most cards in that suit"
- **Source**: #05 ~07:21–07:34
- **Arabic ≤15**: "اللاعب اللي يلعب اصغر ورقه تفترض عنده اوراق اكثر"
- **English**: When two opponents both follow with small cards in the same trick, the one who played the **smaller** card is presumed to have the **longer** holding in that suit. Used to bias remaining-card distribution: assign extra unknowns to the smaller-card player.
- **Confidence**: heuristic prior.
- **Hand-shape**: distribution inference.
- **Phase**: post-trick analysis.
- **Thresholds**: directional bias, no fixed %.
- **[FOCUS]** — directly affects suit-length priors used in card-allocation heuristics.

### R17. Default split of unknowns: 1-1 (نص بالنص)
- **Source**: #13 ~07:23–07:27 ("نص بالنص"); #05 ~06:00–06:05 ("الافضل قسم لكل واحد ورقها")
- **Arabic ≤15**: "كل واحد ورقه نص بالنص"
- **English**: When `N` unknown cards remain split between two unknown opponents and no signal applies, assign **as evenly as possible** ("each one a card; half-and-half"). Used as the prior before applying R16/R3-block adjustments.
- **Confidence**: prior.
- **Hand-shape**: any.
- **Phase**: any.
- **Thresholds**: even split, then adjust by R2/R16/R3.
- **[FOCUS]**

### R18. Always assign consecutive cards to partner (متتاليه)
- **Source**: #05 ~06:32–06:38
- **Arabic ≤15**: "دائما اعطي خويك الورقه المتتاليه"
- **English**: When a card on the table is one of a touching pair (e.g. K-Q-J in sequence), assume the **next-touching card** is at your partner. Used to refine the R17 prior.
- **Confidence**: high prior.
- **Hand-shape**: any.
- **Phase**: any.
- **Thresholds**: directional prior favoring partner.
- **[FOCUS]**

### R19. "If partner had the bigger card, he'd have played it" — receiver inference
- **Source**: #05 ~04:51–05:01
- **Arabic ≤15**: "هل ممكن يكون عنده البنت ولا الولد لا مستحيل لو عنده كان لعبها بدال الشايب"
- **English**: When a partner plays a card under the led trick, you can rule out him holding any **smaller-rank** card of that same suit (he would have played the smallest). Symmetric to R2 but applied to partner.
- **Confidence**: deterministic (assumes correct play).
- **Hand-shape**: post-partner-play.
- **Phase**: after Pos-2 partner plays.
- **Thresholds**: categorical.
- **[FOCUS]**

### R20. Project / مشروع inference (no 3-honor block)
- **Source**: #05 ~06:09–06:23
- **Arabic ≤15**: "لو عنده كان عنده مشروع خمسين"
- **English**: If a player did **not** announce a 50-point project (مشروع — three consecutive cards in same suit), it is impossible that they hold (e.g.) 10-9-8 of one suit together. Use this to rule out impossible hand-shapes.
- **Confidence**: deterministic given declarations are honest.
- **Hand-shape**: rules out "three-touching" combos at non-declarers.
- **Phase**: after declaration phase.
- **Thresholds**: hard exclusion.
- **[FOCUS]** — affects card-distribution priors in MCTS sampling.

### R21. Trump count: 8 trumps total, deduce remainder mechanically
- **Source**: #05 ~10:11–10:21, ~11:13–11:18, ~13:21–13:30
- **Arabic ≤15**: "ثمانيه اوراق عندنا في الهاس والحكم… اذا انت عندك اربع اوراق وهنا اتلعبت ورقتين معناته اخويك عنده ورقتين"
- **English**: 8 trumps in Hokm. After you've played all your trumps and seen the others play, the remaining trump count is fully determined: `8 − your_trumps − played_trumps = remaining at unknown players`. Cross-reference cuts/قطع to assign side.
- **Confidence**: deterministic.
- **Hand-shape**: trump-count tracking.
- **Phase**: any (Hokm only).
- **Thresholds**: arithmetic.
- **[FOCUS]**

### R22. 9 of trump (التسعه) is the second-highest after J
- **Source**: #05 ~11:18–11:31, ~12:21–12:35
- **Arabic ≤15**: "وين التسعه موجوده او تسعه الحكومه"
- **English**: In Hokm, after J the 9 is the most powerful trump remaining. Tracking the 9 is critical: "بنات التسعه عنده تك" (whoever didn't play 9 when he could have small-trumped, has the 9 still). Matches `CLAUDE.md` rule "9 of trump is rank 7 (second-highest)".
- **Confidence**: deterministic rank rule.
- **Hand-shape**: any in Hokm.
- **Phase**: any.
- **Thresholds**: — rank fact.
- **[FOCUS]**

### R23. Higher-than-played impossibility (partner)
- **Source**: #05 ~09:52–09:58
- **Arabic ≤15**: "اذا خويك لعب ورقه مستحيل يكون عنده اصغر منها"
- **English**: When your partner plays a card following suit, he cannot have a smaller card of the same suit (corollary to "play smallest first"). Mirror of R19, but on the under-cut/follow side rather than the take side.
- **Confidence**: deterministic (assumes correct partner).
- **Hand-shape**: any.
- **Phase**: post-partner-follow.
- **Thresholds**: categorical.
- **[FOCUS]**

### R24. Cut-from-trump implies fewer trumps remain at that side
- **Source**: #05 ~10:31–10:38
- **Arabic ≤15**: "لو هذي قطع بالثمانيه… بتسعه تشترية"
- **English**: If a player ruffs (قطع) with the smallest trump (8) and is later overruffed by 9, you can mark the smaller-trump player as having "exhausted his cheap trumps" — bias remaining trump distribution to the other unknown player.
- **Confidence**: heuristic.
- **Hand-shape**: trump tracking.
- **Phase**: mid-game Hokm.
- **Thresholds**: directional.

### R25. "Buyer-of-trump (مشتري) usually holds the J"
- **Source**: #13 ~10:27–10:32
- **Arabic ≤15**: "هو مشتري حكومه غالبا مع الولد وفي الحكم مجبر تعتلي"
- **English**: The player who **bought / declared trump** (the contractor) almost certainly holds the J of trump — they would not have called Hokm without it. Use to localise the J before it has been seen.
- **Confidence**: high (~95% per Saudi convention).
- **Hand-shape**: contractor.
- **Phase**: pre-J reveal.
- **Thresholds**: — strong prior on contractor side.
- **[FOCUS]**

### R26. Median-card heuristic / توازن (balance)
- **Source**: #13 ~07:18–07:31, ~07:36–07:53
- **Arabic ≤15**: "تلعب الورقه المتوسط من ناحيه عدده"
- **English**: When trick-winner prediction is **uncertain (≈50/50)**, play the **median-rank card** from your hand for that suit. Rationale: if opponent eats it you don't regret losing a high card; if partner eats it you didn't waste a small. The video gives the explicit rank-by-points partition: A=11, 10=10, K=4, Q=3, J=2, 9/8/7=0 — and identifies the "balance card" as **K, Q, or J**, depending on what you hold.
- **Confidence**: heuristic.
- **Hand-shape**: 3-card subset where one is high (A/10), one is mid (K/Q/J), one is low (9/8/7).
- **Phase**: any uncertain trick.
- **Thresholds**: — choose middle card by Sun-points value, **not** by rank order.
- **[FOCUS]** — directly applies to bot follow-card selection in 50/50 zones.

### R27. Cards have ابناء (Sun-points) values driving "throw small" rule
- **Source**: #13 ~01:03–01:08, ~07:01–07:05
- **Arabic ≤15**: "التسعه 8 7 في الصن يعني بصفر ابناغ"
- **English**: Sun point values: 9=0, 8=0, 7=0; J=2; Q=3; K=4; 10=10; A=11. The "play smallest" rule is operationalised as "play any **0-points** card first" — saves your scoring cards for when partner is winning.
- **Confidence**: rule.
- **Hand-shape**: any.
- **Phase**: opponent winning the trick.
- **Thresholds**: — point values.
- **[FOCUS]** — affects SWA loss minimisation.

### R28. "Hokm has only 1-rank gap between J and 9, so any trump beats virtually anything"
- **Source**: #13 ~05:02–05:13
- **Arabic ≤15**: "العشره بعشره هناك تعتبر الصن… بينه وبين الكهف واحد فقط"
- **English**: Stated as a wider point about Hokm vs Sun: in Hokm the gap between J (top trump) and 9 (next) is only one rank, but in Sun the A-10 spread already includes the 11/10 point gap. Implication: cutting opportunities in Hokm leave less room for inference because both J and 9 are typically held tightly.
- **Confidence**: rule-of-thumb.
- **Hand-shape**: any.
- **Phase**: Hokm only.
- **Thresholds**: structural.

### R29. Don't lead 10 of a suit unless certain partner has A behind
- **Source**: #13 ~04:36–04:50
- **Arabic ≤15**: "غلط كبير انك تلعب عشره لان انت عندك… خليني انا اشك"
- **English**: Leading the 10 in Sun is a "big mistake" if you don't know the A's location — opponents will read it as R13 ("you have no A") and adjust. Implication for bot: do **not** lead 10 when A is at unknown opponent (it leaks information AND likely loses the trick).
- **Confidence**: rule.
- **Hand-shape**: 10-without-A.
- **Phase**: lead.
- **Thresholds**: avoid unless A is at partner with high confidence.
- **[FOCUS]** — affects `pickLead`.

### R30. Tracked information sources: A, 10, K of each suit (pruning order)
- **Source**: #13 ~03:46–03:55
- **Arabic ≤15**: "لازم تتابع الورق التابع الاكه والعشره والشايب اتلعب ولا"
- **English**: The three honors to track per suit are: **A, 10, K** (ايكه, عشره, شايب). Once these are accounted for, prediction collapses to a small set of cases.
- **Confidence**: rule of thumb.
- **Hand-shape**: any.
- **Phase**: any.
- **Thresholds**: — at minimum track these 3 ranks per suit per opponent.
- **[FOCUS]** — affects bot's memory model: minimum state to keep is {A, 10, K} location per suit per player.

### R31. Practice / partner-quality dependency note
- **Source**: #13 ~13:56–14:03 (closing notes)
- **Arabic ≤15**: "خويك برضو يكون فاهم في البلوت يكون لعيب"
- **English**: All these inferences assume **your partner plays correctly**. If partner is a beginner, signals lose validity. (Not a code rule but a flag for bot-tier dispatch: a "Saudi Master" partner can be assumed to follow R3/R18/R19/R23; lower tiers cannot.)
- **Confidence**: meta-rule.
- **[FOCUS]** — affects how Saudi-Master ISMCTS samples partner hands when partner is a non-Master.

---

## Cross-source conflicts

| Conflict | Source A | Source B | Notes |
|---|---|---|---|
| **Pos-2 confidence** = "100%" vs "تقل النسبه" | #13 ~02:39 says ~100% | #13 ~02:43 immediately says "تقل النسبه" | Self-contradiction within #13. Best read: ≈99% (very high but with one unknown). |
| **Bucket scale** {100/95/90/50/10} vs the watchpoint's {near-100, ~85–90, ~50/50} | #05 + #13 | watchpoint description | The transcripts use **5 tiers**, not 3. Cross-referencer should check whether existing `signals.md` already collapsed them to 3. |
| **Lead-10 prior** 99.99% (#13) vs 95% / 90% (#05) | #13 ~05:54 | #05 ~04:36 | Different contexts: #13's 99.99% applies when you're sitting AS the leader (i.e. you control the read); #05's 95/90 applies when an opponent leads 10 from the right vs from across. Not a true conflict but easy to mis-collapse. |
| **Discard-of-K (شايب) interpretation** (R3b) | #05 says "احتمال يكون عنده عشره فقط" | — | Single-source; implication "10 is at one of the **other two**" follows by elimination. Confirm with cross-source if available. |
| **70/25/5 receiver priors** | NEITHER source | — | Not stated; if existing addon/docs use this triple, the source is elsewhere (different video?). Mark for cross-referencer. |

---

## Open ambiguities

1. **Pos-2 numeric prior**: #13 says "100%" then "less than 100%" in adjacent sentences. Is the canonical value 95%, 99%, or "near-100%"? Ambiguous — needs an explicit number from another source.

2. **Q (بنت)-as-signal direction**: R3c reads "Q signals J behind it" by analogy to R3a (10 signals K). #05 phrases this briefly ("هذا لعب بنت السبيت خويك مع الولد") but does not clarify whether this is the same level of confidence as the 10→K signal, or weaker because Q is mid-rank rather than top.

3. **J-as-signal interpretation** (R3d): The Arabic phrasing "هذا لعب اصغر شيء عندي" is ambiguous between (a) "he played his smallest" (signal: weak holding) and (b) "he played the smallest of his honor block" (signal: he has nothing higher). Cross-referencer should disambiguate against actual gameplay.

4. **R20 (project / مشروع) interaction with bot's MCTS sampling**: Does the existing addon already exclude project-shapes from the prior at non-declarers? If yes, R20 is already satisfied. If no, R20 is a missing constraint.

5. **R26 (median heuristic)**: The video's "median by points" rule (K=4, Q=3, J=2 → median is Q) does **not** match a "median by rank" rule (10>K>Q>J → median is K). Code ambiguity — which axis is "median"?

6. **R30 (3-honor tracking)**: Does the bot currently track A/10/K location per suit per player, or does it track full hand-state? If the latter, R30 is already covered as a strict subset.

7. **Lead-from-bottom threshold (R15)**: When does "small lead" trigger the "don't waste your A" caution? Not given numerically.

8. **R24 (cheap-trump exhaustion)**: No numeric threshold; Cross-referencer should check whether the addon biases trump priors after a small ruff.

---

## Notes for cross-referencer

1. **Section-6 canonical signals (R3a–R3f)**: These are the highest-priority items for `Bot.PickAKA` and the AKA-receiver code path. Confirm against `docs/strategy/signals.md` and the picker function in `Bot.lua`. Quote chain: 10→K, K→has-only-K, Q→J, J→nothing, 9/8/7→discourage, partner-trustworthy, opponent-deceptive.

2. **The 70/25/5 receiver priors are NOT stated in either video**. If they exist in the addon code, they came from a different source (possibly extrapolated from R4 buckets, or from another video the audit hasn't covered yet). Flag explicitly.

3. **Pos-1/2/3/4 dependencies (R6–R9)**: Maps cleanly to the `pickFollow` / `BotMaster.PickPlay` code paths. Pos-1 = leader-decides (no prediction needed); Pos-4 = deterministic (just look at table); Pos-2 and Pos-3 are the "interesting" cases where the receiver-prior code lives. The "near-100/95/90/50/10" tiers map to those positions roughly as: Pos-1 = 100; Pos-2 = 99; Pos-3 = 95 or 90 depending on side; Pos-4 = 100. The "10%" tier is a residual / bluff allowance.

4. **Bucket convention**: The transcripts give **five** numeric tiers `{100, 95, 90, 50, 10}`, not three. If the addon uses three buckets `{near-100, ~85–90, ~50/50}`, the 95/90 distinction has been collapsed and the 10% bluff residual has been dropped. Worth checking if those simplifications cost accuracy.

5. **R26 (median by points, not by rank)**: This is subtle and easy to get wrong in code. The video explicitly partitions cards into "scoring" (A=11, 10=10), "honor mid" (K=4, Q=3, J=2), and "zero" (9/8/7=0). The "balance card" sits in the **honor-mid** band, and choosing among K/Q/J depends on what's left. Verify the addon's median-card logic uses points, not raw rank.

6. **R27 ابناء values**: The video confirms the standard Sun point table but specifically notes that 9/8/7 are zero — used to operationalise "play under" as "play any 0-point card first". Cross-check this against `Constants.lua` / `Rules.lua` value tables.

7. **R30 (track A/10/K per suit per player)**: This is the minimum tracking state the videos demand. Bot can use richer state, but at least these 3 ranks per suit per player must be queryable for prediction logic to run.

8. **R22 (9-of-trump centrality)**: Maps directly to `K.CARRE_RANKS` exclusion ("9 of trump is rank 7 second-highest, but four 9s do NOT form a Carré" per CLAUDE.md). The video confirms 9 is the most-tracked card after the J in Hokm.

9. **R31 partner-quality**: When the bot's partner is a lower tier (e.g. Saudi-Master partnered with Basic), the signal-trust rules R3, R18, R19, R23 should be **discounted**, since lower-tier bots will not respect them. This is a tier-dispatch concern.

10. **Both transcripts are auto-captioned and noisy**. Spelling drift includes خويه↔خويك (your partner ≈ partner-of-yours), الحكومه vs الحكم (Hokm), كل هاوس vs كاتل (likely "حقه" / "اعتلى"). Quoted Arabic snippets above retain transcript spellings; corrections in the English glosses use canonical Saudi-Baloot vocabulary.

11. **Watchpoint resolution table**:
    - Touching-honors rules: **R3a–R3f** ✓ (extensive coverage in #05)
    - Bucketed confidence tiers: **R4** — tiers `{100, 95, 90, 50, 10}`, not strictly the watchpoint's three
    - 70/25/5 receiver priors: **NOT STATED** in either video — flag as missing
    - Pos-1/2/3/4 dependencies: **R6–R9** ✓ (explicit in #13)
