# 31_ashkal_detailed — extracted rules

**Source:** https://www.youtube.com/watch?v=QTDH9TVa_1Q
**Title (Arabic):** شرح الاشكل بالتفصيل في البلوت
**Topic:** Ashkal (أشكال) — the 3rd/4th-position bid that converts the Hokm-bidder's contract to Sun, played by partner. Includes seat restriction, signal semantics ("ما أبغى الشكل"), order semantics (أول vs ثاني / أكثر فالأكثر), and hand-strength criteria for Ashkal vs Sun vs Hokm vs Pass.

---

## 1. Decision rules

| # | WHEN | RULE | WHY | MAPS-TO |
|---|---|---|---|---|
| R1 | Bid phase; you are deciding whether to call Ashkal | Ashkal is **mechanically Sun** — same scoring, same multiplier, same Bel/escalation. **Only difference:** the bid-up card (ورقة الأرض) goes to **partner**, not to you. | "الأشكل هو نفس الصن… لكن الورقة اللي في الأرض ما رح تأخذها، اللي رح يأخذها خويك" | `Bot.PickAshkal`; converts contract to `K.BID_SUN` with partner-as-recipient of the bid-up card |
| R2 | You are **not** the dealer (الموزع) and **not** the dealer's left (يسار الموزع) | **Ashkal FORBIDDEN** — only seats `dealer` and `dealer+1 (left of dealer)` may call Ashkal. Other two seats (dealer's right, opposite-of-dealer) may NOT. | Saudi rule: "اللي يقدر يقول أشكل: الموزع ويسار الموزع. أما اللعبين الآخرين، اللي يمين الموزع واللعب اللي أمام الموزع، ممنوع يقول أشكل" | **State.lua:1450-1487 seat restriction — VERIFY against video framing.** See section 4 below. |
| R3 | Ineligible seat illegally calls Ashkal AND it is **caught before any card revealed** | Reverse the call — contract reverts to **Sun** (forced); penalty: ineligible caller is **forced into Sun** (ينجبر يأخذها صن). No Takweesh. | "ينجبر يأخذها صن. فلو قال هذا أشكل وانتوا اكتشفتوا أنه ما له أشكل، تعطونا الورقة وينجبر اللعب صن" | New `R.CheckAshkalEligibility` in Rules.lua + revert-to-Sun branch in `Bot.PickAshkal` `(not yet wired)` |
| R4 | Ineligible seat illegally calls Ashkal AND **a card has been revealed** before catch | **Cannot reverse** — Ashkal stands, partner takes the bid-up card. مشت عليكم. | "لكن لو قال أشكل ومثلا انت نسيت… مشت عليكم… ما ينفع تقيد عليه" | Same module; cards-revealed lockout same as Bel window | 31 |
| R5 | Ineligible seat **deliberately** calls illegal Ashkal AND opposing team **does not catch** in time | Ashkal stands silently — informal "passive Sun" by intentional mis-call. Player-tier maneuver. | "ممكن تمشي عليكم… ما عنده مشكلة عادي أخذ الصن لكن قال ممكن تمشي" | Player flavor; bot should NEVER do this (rule-violation) | 31 |
| R6 | Hand has 0 إكة, 0 عشرة, no صورة, no مشروع (i.e. 7s, 8s, low cards only) | **DO NOT Ashkal** — pass. Pure low cards never qualify. | "ما هو صن أبدا… ما في لا إكا ولا عشرة، ما يملك تمسك اللعب أبدا" | `Bot.PickAshkal` reject; strength ≪ `K.BOT_ASHKAL_TH=65` | 31 |
| R7 | Hand has only 1 إكة (single Ace), no T-mardoofa, no مشروع | **DO NOT Ashkal** — too weak | "إكا واحدة ما معاها لا عشرة" — single A insufficient even with side cards | `Bot.PickAshkal` reject | 31 |
| R8 | Hand has إكتين (2 Aces), with one mardoofa (A+T same suit) | **Ashkal/Sun candidate.** Speaker walks worked example: "عندك إكتين، وإكا هذه مردوفة معاها ثمانية، وعندك عشرة مردوفة" — bid-strong | `Bot.PickAshkal`/`PickBid` accept | 31 |
| R9 | Bid-up card (ورقة الأرض) is a **9, 8, or 7** (i.e. small) AND your hand has any 1+ Ace | **PREFER Ashkal over Sun** when bid-up card is small. The 3-card extra you'd get from Sun would include this small useless card; Ashkal hands the small card to partner and you get 3 cards from الستياق (potentially including A or T) | "كلما يكون الرقم صغير ومعاك إكة أو عشرة، الأفضل أن تشكل فيه" | `Bot.PickAshkal` — bid-up rank check; favor Ashkal when `bidUp.rank in {7,8,9}` | 31 |
| R10 | Bid-up card is a **ولد (J)** AND no جرية/مشروع available without it | **PREFER Ashkal** — J alone doesn't carry the hand; better to send to partner and draw 3 from stack | "هذه احتمال كبير إنك تشكل فيها" | `Bot.PickAshkal` — J handling | 31 |
| R11 | Bid-up card is a **بنت (Q)** | **PREFER Ashkal** (~75% of cases per speaker's later distributional comment) — Q alone is mid-rank, weak control | Speaker's heuristic: "كان بنت بربو خمسة وسبعين" likelihood that Ashkal-caller doesn't want Q's suit | `Bot.PickAshkal` — Q handling | 31 |
| R12 | Bid-up card is a **شايب (K)** | **MIXED** — speaker estimates ~80% Ashkal-prefer, but check completion of meld/جرية first | "كان شايب والله ثمانين في المئة" | `Bot.PickAshkal` — K handling with meld-completion check | 31 |
| R13 | Bid-up card is a **عشرة (T)** | **CHECK FIRST: do you hold the إكة of that suit?** If YES → take Sun (you'll capture; A+T = guaranteed جرية). If NO → Ashkal | "لو تأخذها صن أفضل، يكون عندك ضامن جرية، إكا بعدين عشرة ضامن. لكن لو كانت عشرة ما عندك إكتها زي كذا، خاصة لو كانت تك… تشكل" | `Bot.PickAshkal` — must read `holds(A_of_bidUpSuit)` | 31 |
| R14 | Bid-up card is a **T (مثلاً عشرة الديمن) and you do NOT hold ديمن in hand** | **PREFER Ashkal** — T would be **تك** (singleton) for you; vulnerable to opp's A. Partner getting T is safer (3 cards distributed) | "ما عندك ديمن هنا في يدك من أول يد، ما انت ضامن ديمن. تشكل فيها" | `Bot.PickAshkal` — singleton-T check | 31 |
| R15 | Bid-up card is an **إكة (A)** | **GENERALLY DO NOT Ashkal — take Sun.** A is the strongest card; surrendering it to partner is "غشيم" (rookie). | "إذا واحد تشكل على إكاة معناته غشيم… كلنا نتفك على هذا الشي" | `Bot.PickAshkal` — A-discrimination penalty in scoring | 31 |
| R16 | **Ashkal-on-A exception:** hand has 3 شياب of one suit + scattered side, AND bid-up A could complete a 4-Aces / 100-meld via the 3-card draw | **Ashkal allowed even on A** — meld-completion path | "احتمال تجيك العشر الرابع تصير 100" + "ممكن تجيك إكاة، ممكن تجيك إكتين، ممكن إكاة وعشرة" | `Bot.PickAshkal` — meld-via-stack-draw evaluator | 31 |
| R17 | Hand has 50-meld already + bid-up card would NOT extend the meld | **DO NOT Ashkal — take Sun** to preserve guaranteed meld | "أنت ضامن مشروع خلاص خلي عندك" | `Bot.PickAshkal` reject when `existingMeldValue > 0 && bidUp.completes == nil` | 31 |
| R18 | Hand has شايب of bid-up suit + ولد of same suit + bid-up card extends to جرية (5-card sequence) | **DO NOT Ashkal — take Sun** to lock the جرية | Worked example: "عندك إكا، عشرة، شايب، بنت، ولد… عندك خمسة قطع عشرية تجري فيها" | `Bot.PickAshkal` reject when `wouldFormSequence5(hand + bidUp)` | 31 |
| R19 | Bid-up card is K of opposite-color suit (e.g. شايب الديمن when you hold ولد الشري) | **Ashkal preferred** — no جرية path; partner's draw better | "لو كان شايب مثلا ديما زي كذا، الحالة ما تأخذها الصن لا تشكل الأفضل" | `Bot.PickAshkal` — color/suit alignment check | 31 |
| R20 | Hand has 2 T's that are both **تك** (singletons in different suits) | **Ashkal preferred over Sun** — singletons need cover; partner's 3-card draw more likely to deliver mardoof than your 2-card draw | "أنا أحتاج يجيني مردوف للعشرتين هالي… عندك هنا 6 ورق وتحتاج ورقتين، احتمال ضئيل" | `Bot.PickAshkal` — singleton-cover analysis; favors Ashkal when `count(singletonT) >= 2` | 31 |
| R21 | You called Ashkal **first round (في الأول)** — partner had not yet bid | **Signal semantics:** "I want **opposite-shape (عكس الشكل)** — same color, opposite suit." E.g. Ashkal-on-spades = "lead Hearts." | "في الأول معناته نفس اللون لكن عكس الشكل" | `Bot.PickAshkal` signal-emission + receiver in `pickLead` `(not yet wired)` | 31 |
| R22 | You called Ashkal **second round (في الثاني / أكثر فالأكثر)** — partner already passed once and you Ashkal'd on opp's bid-up | **Signal semantics:** "I want **opposite-color (عكس اللون)**." Spades-Ashkal = "lead a Red suit (Hearts/Diamonds)." | "الأشكال في الثاني معناته أبغى عكس اللون" | Same; receiver branch reads `S.s.bidLap == 2` | 31 |
| R23 | Partner took **Hokm in first lap** AND you Ashkal in first lap | **Signal semantics override:** "I had to Ashkal because partner took Hokm — direction does NOT carry the standard عكس-الشكل meaning. It just means 'I want Sun, not Hokm.'" | "خويك عشان أخذ حكم في الأول أجبرني إن أقول أشكل… ما أقدر أنتظر الثاني" | `Bot.PickAshkal` — signal-suppression flag when partner-took-Hokm-prior `(not yet wired)` | 31 |
| R24 | You Ashkal'd on suit X; partner's turn to lead trick 1 | **Partner SHOULD avoid leading X** — Ashkal is a "I don't want this شكل" signal. Partner leads strongest non-X. | "خلاص ما تبقى السبيت، كنسل السبيت. أجي له في الثلاثة الأشكال الأخرى" | `pickLead` Ashkal-receiver branch `(not yet wired)`; new ledger key `Bot._partnerStyle[partner].ashkalSuit` | 31 |
| R25 | You Ashkal'd on suit X; **opponent** is on lead in trick 1 (not partner) | **Opponent should LEAD X** (the suit you Ashkal'd) — they correctly read it as your weak suit. Bot defender: lead the Ashkal-suit if you have any strength there. | "الخصم لازم يفهم هذا الشي… يلعب الشي اللي انت شكلت عليه، لانه غالبا انت شكلت على شي ما تبغى" | `pickLead` opp-vs-Ashkal-bidder branch `(not yet wired)` | 31 |
| R26 | Ashkal-suit-direction reliability ladder | Reliability of "Ashkal = ما أبغى" depends on bid-up rank: T = ~95%, K = ~80%, Q = ~75%, J = ~60%, 9/8/7 = "not necessarily" (small ranks may be Ashkal'd for any reason) | "كان عشرة احتمال كبير تسعة و سعين في المئة إني ما أبغى الشكل. كان شايب والله ثمانين. كان بنت بربو خمسة وسبعين. كان ولد ينزل ستين. كان تسعة ثمانية سبعة لا والله مو شرط" | Signal-confidence value used by sampler/picker `(not yet wired)` | 31 |
| R27 | Bid order: you are 4th to bid; first 3 all said "بس" (pass); seat 4 wants to Ashkal | **LEGAL** — seat 4 = dealer's left (yasaar al-muwazzi) is one of the two eligible seats. Speaker's worked example. | "وانت قلت أشكل… أول لاعب قال بس، وهذا قال بس، وهذا قال بس، وجيت أنت قلت أشكل" | Confirms seat-4-as-dealer-left eligibility | 31 |
| R28 | Bid order: dealer (seat 4) is the one bidding | **LEGAL** — dealer is the OTHER eligible seat. (Seats 1-2-3 = NOT eligible by the video.) | "أنت الموزع الآن، صح؟ يعني أنت من حقك تقول أشكل" | Confirms dealer eligibility | 31 |
| R29 | Bid-up card is a **side card** (e.g. K of off-color) AND your hand has 2 T's mardoofa + 1 A | **DO NOT Ashkal — take Sun.** Strong-Sun hand makes the bid-up card irrelevant. | "إكتين وعشرتين مردوفتين شكلت وحلو، ليش ما تأخذها صن؟" | `Bot.PickAshkal` reject when `strength > 80` (well above `K.BOT_ASHKAL_TH=65`) | 31 |
| R30 | Hand has 3 إكة (three Aces) | **DO NOT Ashkal — take Sun.** "ثلاث إكتك ما يبقى لها كلام" | Too strong; Ashkal wastes the dominance | `Bot.PickAshkal` hard-reject at three-A | 31 |

---

## 2. New terms (proposed for glossary)

| Arabic | Translation | Definition | Source |
|---|---|---|---|
| ورقة الأرض / ورقة السياق | "the ground card / draw-stack card" | The bid-up card visible during bidding; in normal Sun/Hokm goes to bidder, in Ashkal goes to partner | 31 |
| الموزع | "the dealer" | Seat that dealt the cards. In Ashkal, dealer is one of two eligible callers. | 31 |
| يسار الموزع | "left of dealer" | Seat dealer+1. The other eligible Ashkal seat. | 31 |
| يمين الموزع | "right of dealer" | Seat dealer-1 (opposite direction). NOT eligible to Ashkal. | 31 |
| أمام الموزع | "across from dealer" | Seat dealer+2 (across the table). NOT eligible to Ashkal. | 31 |
| أول / في الأول | "first / in the first (lap)" | First bidding round. Ashkal-in-first encodes "عكس الشكل" (opposite suit, same color). | 31 |
| ثاني / في الثاني / أكثر فالأكثر | "second / in the second / more-and-more" | Second bidding round. Ashkal-in-second encodes "عكس اللون" (opposite color). | 31 |
| كنسل (kansl) | "cancel" — colloquial English loan | "I cancel that suit"; partner-side reading after Ashkal | 31 |
| غشيم | "rookie / clueless" | Pejorative: a player who Ashkal's on an Ace is غشيم | 31 |
| تك (tikk) | "stuck / vulnerable singleton" | A T or A held alone in a suit, vulnerable to opp's higher card. "تك على عليك" = "stuck on you" | 31 |
| مردوف / مردوفة | "doubled / paired with another in suit" | Already in glossary (videos 25, 02). Reinforced here. | 31 |
| نخفف على بعض / تأخذها صن (verb form: تشكل) | "to Ashkal (verb)" | "تشكل عليه" = "to Ashkal on it (the bid-up card)" | 31 |

---

## 3. Contradictions

**Within-source:** None. Speaker is internally consistent.

**Cross-video alignment:**
- **R8-R20 hand-strength criteria** corroborate video #25 (Sun-bid heuristics) — both videos converge on **A+T mardoofa + meld/control across suits** as the bid-strong signature. Video #25 R10 ("A+T mardoofa = مجازف tier") is the same threshold.
- **R15 (Ashkal-on-A is غشيم)** **CORROBORATES** video #25 R14: "with 4 A's, bid Sun, never Ashkal." Both videos treat A-discrimination as a hard rule.
- **R16 (Ashkal-on-A exception)** **REFINES** video #25 R16 (4-A's + lone T-of-Diamonds → Ashkal acceptable). Speaker here adds the meld-completion-via-stack-draw justification.
- **R21-R22 signal semantics (في الأول vs في الثاني)** **CORROBORATES** the existing Tahreeb/glossary entry "عكس اللون / عكس الشكل" (videos 01, 03). Ashkal is a 6th form of Tahreeb-family signal, applied at bid time rather than play time.

**Potential contradiction with State.lua:1450-1487 — see section 4.**

---

## 4. Non-rule observations

### Ashkal trigger conditions — what hand pattern justifies Ashkal?

**The canonical trigger:** *partner just took (or you have a chance to convert) Hokm/the bid-up card, and YOUR hand is Sun-strong (≥1 إكة, preferably mardoofa, OR a مشروع)* AND **the bid-up card is a small-to-mid rank** (9/8/7 strongly favor Ashkal; J/Q lean Ashkal; K is mixed; T depends on whether you hold A of that suit; A almost never Ashkal).

The decision tree is two-axis:
1. **Hand axis** — is hand Sun-bid-eligible at all? (Use video #25 criteria: ≥1 A, mardoofa preferred, or a 50/100 meld already.) If NO → pass. If YES → continue.
2. **Bid-up axis** — would the bid-up card add MORE value to your hand than to partner's 3-card draw?
   - If YES (A, K-with-جرية, T-with-A-in-hand, completes-meld) → **Sun** (take it yourself).
   - If NO (small rank, singleton-T, no جرية/meld extension) → **Ashkal** (give to partner).

### Hand-strength threshold — does the speaker give a numeric threshold?

The speaker does **NOT give a numeric threshold**. The criterion is structural:

- **0 إكة + 0 مشروع** → never Ashkal.
- **1 إكة (single, no mardoofa)** → never Ashkal unless مشروع compensates.
- **1 إكة (mardoofa with T)** + 1 side card → Ashkal/Sun candidate (مجازف tier from #25).
- **2 إكة + at least 1 mardoofa** → Ashkal/Sun candidate (confident).
- **3 إكة or 4 إكة (الأربع مئة)** → never Ashkal — take Sun directly (R30).
- **مشروع 100 already in hand** → take Sun directly (preserves locked meld), don't Ashkal (R17).

Mapped to `K.BOT_ASHKAL_TH=65`: the **65 threshold roughly corresponds to "1 mardoofa + side card"** in the existing Bot scoring (mardoofa A+T ≈ 11+10+stability ≈ 25-35 strength points; combined with bid-up card considerations and seat-eligibility). The threshold is a **strength FLOOR** — below 65 → pass; at/above 65 → consider; well above (~85+) → take Sun directly instead of Ashkal.

**Implication for code:** `Bot.PickAshkal` should evaluate two branches:
- (a) `strength < K.BOT_ASHKAL_TH` → pass.
- (b) `strength >= K.BOT_ASHKAL_TH` AND bid-up rank ∈ {7,8,9,J,Q} → Ashkal preferred.
- (c) `strength >= K.BOT_ASHKAL_TH` AND bid-up rank ∈ {A, T-with-A, K-completes-جرية, مشروع-extender} → Sun preferred (don't Ashkal).
- (d) `strength >= ~85` (very strong) → Sun directly regardless of bid-up rank.

### Ashkal vs partner's Hokm — when do you "let partner have it" vs Ashkal-convert?

The video addresses this explicitly (R23):

- **Partner took Hokm in first lap and your hand is Sun-strong** → Ashkal anyway. The signal "ما أبغى الشكل" is **suppressed** — partner reads it as "I just want Sun, no directional content."
- **Partner took Hokm in first lap and your hand is mediocre Sun (1-mardoofa marginal)** → **let partner play Hokm.** Ashkal-converting a mediocre Sun is a worse outcome than partner's Hokm.
- **Partner took Hokm in first lap and your hand is purely Hokm-shape** (4-card trump with cover) → never Ashkal. Hokm wins.

The decision criterion is: **does your Sun-strength STRICTLY EXCEED what partner's Hokm would deliver?** If marginal → let partner have it.

Speaker's framing (R23): "خويك عشان أخذ حكم أجبرني إن أقول أشكل" — "partner taking Hokm forced me to Ashkal." Implying: *only force Ashkal when your Sun-strength dominates*; if you're indifferent, accept partner's Hokm.

### Anti-triggers — when do you have an Ashkal-eligible hand but should NOT call?

The video gives explicit anti-triggers:

1. **Bid-up card = إكة (A)** with no special meld-completion path → take Sun, never Ashkal. R15. Considered غشيم if violated.
2. **Bid-up card = T AND you hold A of that suit** → take Sun (A+T مردوفة guaranteed). R13.
3. **Bid-up card completes جرية (5-card sequence) you already have** → take Sun. R18.
4. **Hand has 50/100 meld already and bid-up card doesn't extend it** → take Sun. R17.
5. **Hand has 3 إكة or الأربع مئة (4 إكة)** → take Sun directly. R30 + #25 R14.
6. **You are not in seat dealer or dealer's left** → forbidden (rule, not heuristic). R2.
7. **A card has been revealed in the bidding window** → window closed; same as Bel cards-revealed lockout. R4.

### Rule-correctness verification — seat restriction

**Per video:** "اللي يقدر يقول أشكل: **الموزع ويسار الموزع**." → only **seat dealer** and **seat dealer+1** may Ashkal. Seat dealer-1 (يمين الموزع) and seat dealer+2 (أمام الموزع) are FORBIDDEN.

**State.lua:1450-1487 currently enforces:** "only seats 3-4 can call" (per the topic hint). 

**Verification status:** **CONDITIONAL CORRECTNESS — depends on seat-ID convention.**

- If `seat 4 = dealer` and `seat 3 = dealer-1 (right of dealer)`, then "seats 3-4" allows the dealer (4) but ALSO allows the right-of-dealer (3) — **WRONG per video**, since seat 3 (يمين الموزع) is explicitly FORBIDDEN.
- If `seat 4 = dealer` and `seat 3 = dealer+1 (left of dealer)`, then "seats 3-4" allows dealer (4) and left-of-dealer (3) — **CORRECT per video**.
- If `seat 1 = dealer` (alternative convention) and seats are numbered counterclockwise from dealer, the mapping again depends on numbering direction.

**Action item:** verify the seat-ID convention in `State.lua:1450-1487`. The video unambiguously names the **dealer + dealer's LEFT** as the only two eligible seats. The current code's "seats 3-4" must map to **{dealer, dealer+1 (counterclockwise/leftward)}**, NOT {dealer, dealer-1}.

If the State.lua convention has `dealer = seat 4` and `seat 3 = dealer's left (seat in counterclockwise direction)`, then existing logic is **CORRECT**. If `seat 3 = dealer's right`, then it's **INVERTED** — fix needed: change to `{seat 4, seat 1}` (where seat 1 = dealer+1 wrapping).

**Recommendation:** add an inline comment to `State.lua:1450-1487` clarifying the dealer-left mapping:
```lua
-- Ashkal eligibility (per video #31): dealer + dealer's left (يسار الموزع).
-- Seats 3-4 here assume seat 4 = dealer, seat 3 = dealer+1 (CCW).
-- If seat numbering convention changes, update this list.
```

Also add a `R.IsAshkalEligible(seat)` predicate in `Rules.lua` that derives from `S.s.dealer` rather than hard-coding seat numbers — robust to convention changes.

### Other useful non-rule observations

- **Five inputs to Ashkal decision** (speaker's framework, mirroring video #25's bidding framework): (1) cards in hand, (2) personal risk tolerance, (3) النشرة (cumulative score), (4) what's been bid before you (Hokm/Sun/pass sequence), (5) seat position relative to dealer.
- **Ashkal as a Tahreeb-family signal:** speaker explicitly frames Ashkal as "ساجس شكل من أشكال التهريب" ("the 6th form of Tahreeb"). The "ما أبغى الشكل" semantics directly mirrors Tahreeb's "I refuse this suit" mechanic, but applied at bid time, before any card is played.
- **Distributional probabilities for Ashkal-as-refusal signal:** speaker explicitly enumerates a confidence ladder by bid-up rank (T 95%, K 80%, Q 75%, J 60%, low 9/8/7 = uncertain). This is a usable signal-strength weighting for the partner-receiver in `pickLead`.
- **3-vs-2 cards from stack:** key informational reason for Ashkal — Ashkal-caller draws **3** cards from الستياق, regular Sun-caller draws **2**. Extra card improves expected hand quality (more chances at A, T, or meld-extender). Speaker uses this as the central economic argument for Ashkal: *when bid-up card is small, the 3-card draw beats keeping it + 2-card draw.*
- **"Ashkal in second" meaning** is contested — speaker notes "في ناس تسمها بالثاني، في جلسات كثيرة تسمح بالثاني، في ناس ما تسمحها." The convention is **session-dependent (جلسة-dependent)**. Bot should default to "أول" semantics unless a session/group preference is configured.

---

## 5. Quality notes

- **Whisper transcription quality:** good. Major Saudi terms (أشكل, الموزع, يسار/يمين, تهريب, الورقة, مشروع, إكة, شايب, بنت, ولد, مردوفة, تك, جرية, غشيم, السبيت, الديمن, الشريع, الهاص) all preserved with minor ASR drift. A few tokens are mis-rendered (e.g. "نيرجي رح يففيكم" line 2-3 is unintelligible noise; "البزراج" line 649 is likely "البلوت"; "بمثابة الاكتراك" line 363 is malformed but context-clear). Core argumentative chain intact.
- **Speaker discipline:** medium. Heavy on worked examples (~6-8 hand patterns walked through), with explicit numerical confidence claims (T=95%, K=80%, etc.) — unusually concrete for a Baloot tutorial. Some conversational hedging ("ممكن… على حسب…") but rules emerge clearly.
- **Worked examples:** 6+ specific bid-up-card scenarios (small numbers, T-with-vs-without-A, K, Q, J, 4-A's edge case, meld preservation). Each has a clear bid-or-Ashkal-or-Sun verdict.
- **Numerical specificity:** moderate. Reliability percentages (95/80/75/60), card-counts (3 vs 2 from stack), score-state framing implicit. No expected-value formulas.
- **Confidence calibration:** R1-R30 should be **Definite/Common** within this single source. Cross-corroboration with video #25 (Sun-bid heuristics) is strong; with #01-03 (Tahreeb signal direction) confirms R21-R22.
- **Caption-error risk:** The speaker says "أشكل" (Ashkal) consistently; no homophone confusion with تنفير/تنفيذ noticed. Authoritative card-name mapping (شايب=K, بنت=Q, ولد=J) used throughout — no anti-trio mistakes.
- **Single-source caveats:** R3-R4 (illegal-Ashkal-revert mechanics with cards-revealed lockout) is single-source from this video; consistent with Bel cards-revealed convention from #11 but should be cross-checked. R26 (reliability percentages by bid-up rank) is single-source but explicitly numerical.
- **Code-mapping notes:** all rules map to `Bot.PickAshkal`/`Bot.PickBid` with assist from `K.BOT_ASHKAL_TH=65`, `K.BOT_SUN_TH`, `R.IsAshkalEligible(seat)` (proposed new), and `S.s.dealer`. The seat-restriction question (R2 vs State.lua:1450-1487) is the one rule-correctness item flagged for verification — see section 4 above.
