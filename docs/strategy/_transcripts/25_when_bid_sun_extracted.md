# 25_when_bid_sun — extracted rules

**Source:** https://www.youtube.com/watch?v=myxSSlNGZIk
**Title (Arabic):** متى تشتري صن في البلوت للمبتدئين
**Topic:** When to bid Sun (صن) in Baloot — beginner-level hand-strength heuristics

---

## 1. Decision rules

| # | WHEN | RULE | WHY | MAPS-TO |
|---|---|---|---|---|
| R1 | Deciding whether to bid Sun | Buy only if you hold the strongest cards in Sun (i.e. **at least one إكة (A)**, ideally **A + T (mardoofa) of same suit**, AKA إكة مردوفة) | Sun ranks A=11 ابناء, T=10, K(شايب)=4, Q(بنت)=3, J(ولد)=2; you must have the top-2 ranks of a suit to capture | `Bot.PickBid` Bot.lua:725; threshold `K.BOT_SUN_TH` |
| R2 | First 5 cards: 0 إكة, 0 عشرة, no صورة, no مشروع | **PASS — never bid Sun.** | "أنت عندك أصغر الورق… ما عندك ولا صورة ولا مشروع" — pure low cards lose every trick | `Bot.PickBid` Bot.lua:725 — strength=0 fallback |
| R3 | Hand has 1 شايب (K) but no A and no T | Do NOT bid Sun | Without A or T you cannot win opening tricks; K is rank-3 and gets eaten | `Bot.PickBid` Bot.lua:725 |
| R4 | Hand has 1 ولد (J) and 0 A, 0 T | Do NOT bid Sun | J is rank-5 in Sun (worth 2 ابناء only) — useless as a winner | `Bot.PickBid` Bot.lua:725 |
| R5 | Hand has 1 بنت (Q) only — no A, no T, no مشروع | Do NOT bid Sun (regardless of position or game-stage) — "أبدا تتبه" | Q rank-4 worth 3 ابناء; cannot win | `Bot.PickBid` Bot.lua:725 |
| R6 | First 5 cards contain **مشروع من أول يد** (a meld already made on initial 5 cards: 50, 100, etc.) | **MAY bid Sun even without an A** — exception R1 | Meld points (50/100) compensate for weak trick-taking; "عندك مشروع من أول يد… تشتري صن" | `Bot.PickBid` Bot.lua:725 — meld-detect path |
| R7 | First 5 cards contain a ولد + the bid-up card would **complete a 100-meld** (e.g. you hold J/T/9/8 and adding one more makes 100) | Take the bid as Sun (also OK as Hokm; if early game prefer Sun) | The meld guarantees 100 even if trick-points fail | `Bot.PickBid` Bot.lua:725 — Ashkal/meld detect |
| R8 | First 5 cards contain a 50-meld but no A or T | May still bid Sun, especially if the buy-card adds to it (e.g. ولد of أشري next to your J-meld becomes إكة) | "ممكن تأخذها صن… خصوصا لو كان ولد الشري بداله إكة" | `Bot.PickBid` Bot.lua:725 |
| R9 | You hold 1 إكة (single A, not mardoofa) + low side cards (السبيت/سرة only) | Generally PASS — too weak | "ولا في إكة ولا شي… لا ما ينفع، ما نصحك تشتري" | `Bot.PickBid` Bot.lua:725 |
| R10 | You hold إكة مردوفة (A+T same suit) + 1 other side card | **Bid Sun (مجازف — risky-but-acceptable)** | A+T of same suit guarantees 21 ابناء + last-trick pull; "تعتبر مجازف لكن إذا قدت أصل ونجحت معاك أحلى" | `Bot.PickBid` Bot.lua:725 — strength threshold |
| R11 | You hold إكة مردوفة + عشرة مردوفة (two A+T pairs in different suits) | **Definitely bid Sun.** "أشتري صن خلاص" | Two top-2 pairs = guaranteed control; "الورق قاعد يكبر معانا… ونت طالع تشتري" | `Bot.PickBid` Bot.lua:725 |
| R12 | You hold 3 إكة (three Aces) + 1 of any 10 + side card | **Bid Sun. "ما يبقى لها كلام."** | Three A's = guaranteed 33 ابناء + control of three suits | `Bot.PickBid` Bot.lua:725 |
| R13 | You hold 3 إكة + التسعة-replacement (e.g. 4 high cards) | **Bid Sun.** Even stronger | Hand-pattern dominance | `Bot.PickBid` Bot.lua:725 |
| R14 | You hold the FOUR ACES (الأربع مئة meld) | **Bid Sun, never Ashkal.** "مستحيل تخسر عليك… سلم على الشهداء" | 400 meld guaranteed; Sun multiplier ×2 stacks; impossible to fail | `Bot.PickBid` Bot.lua:725 — `K.MELD_CARRE_A_SUN`=200 path |
| R15 | You hold any **عشرة (T) of any suit** alongside the four-A pattern | Prefer Sun over Ashkal | A 10 in your own hand strengthens the sweep | `Bot.PickBid` Bot.lua:725 |
| R16 | You hold four A's BUT also hold the **عشرة الديمت** specifically (T of Diamonds, lone) | **Ashkal acceptable** here | Risk that the bid-up card is a doubleton without partner; Ashkal hands the contract to partner | `Bot.PickBid` Bot.lua:725 — Ashkal branch (`K.BOT_ASHKAL_TH`=65) |
| R17 | Late game: you 140, opp 140 (close-to-finish, near match-target 152) | **Do NOT take Sun on weak/medium hands** — play conservatively, prefer Hokm or pass | "ممكن في هذه الحالة ما تأخذ حصن… راح تكون حريص وتلعب على المضمون أكثر" | `Bot.PickBid` Bot.lua:725 + `scoreUrgency` Bot.lua:588 |
| R18 | You 100+, opp <30 (you well ahead, opp far behind) | **Sun OK on above-medium hand even if opp doubles** | Even if Bel'd to 52, opp still well below match-end | `Bot.PickBid` Bot.lua:725 |
| R19 | You 120, opp 90 (you ahead but opp catching up) | **AVOID Sun unless very strong** — risk of opp Bel + sweep escalation | Bel-then-50/100 from opp can flip the score | `Bot.PickBid` Bot.lua:725 + Bel-fear path |
| R20 | First-round bidding: you have weak/medium Sun hand, undecided | **Pass on first lap (أول لفة)** — wait for second lap | Partner may take Hokm/Sun first; opp may take Hokm forcing your hand; "لا تستعجل… مشيها" | `Bot.PickBid` Bot.lua:725 — first-pass lap policy |
| R21 | First-round: opp took **Hokm** before you | You may **take Sun on a moderate hand** — partly forced | Opp's Hokm usually denies you a chance; Sun is the override | `Bot.PickBid` Bot.lua:725 |
| R22 | First-round: opp took **Sun** before you | **Better to LET THEM HAVE IT.** Do NOT counter-bid Sun unless your hand is overwhelmingly strong | "ممكن الخصم معهم صن… ممكن تخسر عليهم" — opps may have stronger Sun than you | `Bot.PickBid` Bot.lua:725 |
| R23 | First-round: partner took Hokm | You may convert to Sun via **Ashkal** if your hand is Sun-strong | Standard Ashkal use | `Bot.PickAshkal`; `K.BOT_ASHKAL_TH`=65 |
| R24 | Sun decision: between Sun and Hokm with similar strength | **Default to Hokm** — "الحكم أرحم… الحكم خسارته 16، الصن خسارته 26" | Failed Sun = 26 raw to opp, failed Hokm = 16 raw; Hokm safer | `Bot.PickBid` Bot.lua:725 — bid-type selector |
| R25 | Sun decision in **endgame** (close to 152) with similar Sun/Hokm strength | **Strongly prefer Hokm** | Hokm "غالبا ينجح" with 4 trumps + cover; Sun is variance-heavy late | `Bot.PickBid` Bot.lua:725 + `matchPointUrgency` Bot.lua:619 |
| R26 | You are bidder team; opp ahead 140; opp took Sun | **Bel anyway**, even on bad cards | "ما أنت خسرانه… ممكن يجيك مشروع" — bidder is locked in to lose round; Bel doesn't add expected loss | `Bot.PickDouble` Bot.lua:1787 — score-desperation path |
| R27 | You opp; opp took Sun; you hold a **مشروع 100** in hand + Ace | **Bel** — almost guaranteed positive EV | Meld-100 + A guarantees you win the round even if opp competent | `Bot.PickDouble` Bot.lua:1787 |
| R28 | You hold an A + a 10 of same suit (mardoofa) + nothing else; opp took Sun | **Bel** — high chance partner has cover or a 10 lands you 100-meld | "ممكن تجيك 10 رابعة وتكمل لك 100" | `Bot.PickDouble` Bot.lua:1787 |

### 1a. Sun-Mughataa (الصن المغطى — covered/blind Sun)

| # | WHEN | RULE | WHY | MAPS-TO |
|---|---|---|---|---|
| R29 | You declare Sun BEFORE seeing your 5 initial cards (blind) | **Mechanically identical** to normal Sun — no point/score difference | "ما في أبدا أي فرق" | `Bot.PickBid` Bot.lua:725 — no separate code path needed |
| R30 | Sun-Mughataa motivation #1 (compassion/تعاطف): you 140, opp 20 | OK to declare blind Sun — even if you fail, opp still far behind | Pure mercy/sportsmanship; risk-bounded | Player-tier flavor; not a bot rule |
| R31 | Sun-Mughataa motivation #2 (هياط/طقطق — bragging/taunting) | OK BUT **expect opponent Bel** | Provocation invites Bel; if opp Bels then makes 52 raw, score flips | `Bot.PickDouble` Bot.lua:1787 — opp may Bel a covered-Sun bidder |

---

## 2. New terms (proposed for glossary)

| Arabic | Translation | Definition | Source |
|---|---|---|---|
| إكة مردوفة | "doubled Ace" (mardoofa) | A+T of the same suit held in your hand together — the canonical Sun-strength signature | 25 |
| عشرة مردوفة | "doubled Ten" | T held with another high card of same suit (typically T+K or two T's not possible — context is T accompanied by another rank) | 25 |
| مشروع من أول يد | "meld from the first hand" — a meld already realized in initial 5 cards | 50 / 100 / 200 already made on the deal, before the bid-up card; a key Sun-bidding override | 25 |
| الصن المغطى | "covered Sun" / Sun-Mughataa | Bidding Sun blind, before seeing your 5 cards. Same scoring as ordinary Sun. | 25 |
| ابناء | "sons / point-children" — i.e. card-point values within a contract (A=11, T=10, K=4, Q=3, J=2 in Sun) | Saudi term for "ranking points" of cards | 25 |
| مرة فوق / مرة تحت | "way up / way down" — score-state shorthand for cumulative-point lead/deficit | Used in escalation gating ("أنت 140 والخصم 20 مرة تحت") | 25 |
| الهياط والتقطق | "bragging and taunting" | Social motive for Sun-Mughataa; opp likely to Bel as retaliation | 25 |
| نشرة / مكامة | "scorecard / book of points" — the running ledger of cumulative scores | Speaker uses نشرة for what code calls `S.s.cumulative` | 25 |
| مجازف | "risk-taker / gambler" — descriptive for buying Sun on medium-strength hands | Hand-strength tier label | 25 |

---

## 3. Contradictions

None within this transcript. **Cross-video alignment:**
- R10 (إكة مردوفة minimum threshold) **corroborates** Section 1's existing Sun-bid heuristic in `decision-trees.md` (was previously only "strong cards" — now has a concrete pattern).
- R24 (Hokm-default rule of thumb) **agrees with** existing strategy that Hokm is "always safer" — speaker quantifies it as 16 raw vs 26 raw failure cost.
- R20-R22 (first-lap pass discipline) **adds** a previously unstated bidding-tempo convention to Section 1.

---

## 4. Non-rule observations — Sun-bid trigger summary

### Sun-bid trigger conditions — what HAND PATTERNS justify bidding Sun?

The speaker organizes Sun-buy strength in roughly five tiers:

1. **Mandatory bid (overwhelmingly strong):** four A's (الأربع مئة), or 3 A's + 1 T, or 3 A's + extras. Sun is mandatory; Ashkal would waste the meld.
2. **Confident bid:** A+T mardoofa in two different suits (إكة مردوفة + عشرة مردوفة) → guaranteed control of two suits.
3. **Acceptable bid (مجازف — risky):** A+T mardoofa in **one** suit with one side card. Speaker says "تعتبر مجازف لكن إذا قدت أصل ونجحت معاك أحلى وأحلى."
4. **Conditional bid (meld-driven):** mشروع من أول يد (50 or 100 made on deal) — Sun OK even **without an Ace**, since meld points compensate. The 400-meld (4 A's) is the extreme case.
5. **Forced bid:** opp took Hokm before you and you have moderate Sun hand → take Sun as the only override.

Implicit rank-ordering across the 5: ابناء preference is A > T > K(شايب) > Q(بنت) > J(ولد) > 9 > 8 > 7. The "buying" question reduces to: *can I capture 5 of 8 tricks AND/OR meld my way past a defender's 100?*

### Sun-bid anti-triggers — when should you NOT bid Sun even with strong cards?

- **Single-suit dominance only** (no mardoofa, e.g. 1 A + 1 T in different suits) without a meld — too easily cut.
- **Endgame (you 140+, opp 140+)** — Sun's variance is too high; switch to Hokm or pass even with strong cards.
- **Opp at 90-120 while you're at 100-130** — fear of Bel; opp's 52-raw Bel windfall closes the gap.
- **Opp already took Sun in this round** — opp's Sun usually means opp has a stronger Sun pattern; competing is statistically losing.
- **Single A only + low cards** — speaker explicit: even with one A, if the rest is سرة (junk), pass.
- **K (شايب) replacing your 8 in an otherwise weak hand** — does NOT upgrade the hand; K alone is rank-3 in Sun and gets eaten.
- **Q (بنت) replacing your low** — never qualifying.
- **J (ولد) alone with 0 A and 0 T** — never qualifying.

### Comparison vs Hokm — when to prefer Sun over Hokm given similar hand strength?

Speaker's heuristic is **default to Hokm; bid Sun only when explicit advantages override**:

| Situation | Choice |
|---|---|
| Similar strength, early/mid game | **Hokm** — failure costs 16 raw vs 26 raw |
| Hand has multi-suit Aces (i.e. control of multiple suits, no single trump anchor) | **Sun** — Hokm wastes multi-suit strength |
| Hand has 4-card trump-suit + ولد/تسعة + cover | **Hokm** — trump-strong hands favor Hokm |
| Hand has مشروع 100 + A | **Sun** — meld + A is Sun's sweet spot (×2 multiplier) |
| Endgame (close to 152) | **Hokm** — variance penalty too high in Sun |
| Opp took Hokm before you | **Sun** (Ashkal-style override) — only path forward |
| Hand has 4-A meld | **Sun** mandatory — 200-meld × 2 multiplier = 400 effective |

The speaker explicitly says: "في الأغلب الناس يشترون حكم… الحكم مضمون دائما نجاحه."

### Specific Ace-count thresholds — does the speaker say "X Aces is the minimum"?

**Speaker's explicit minimum:** "أقل شيء لازم يكون عندك إكة وحدة، والأفضل تكون مردوفة." → **Minimum = 1 Ace, preferably mardoofa (A+T same suit).**

Exceptions to the 1-A minimum:
- **0 A + مشروع من أول يد** (50 or 100 meld already made) — overrides the 1-A minimum.
- All other 0-A hands → PASS.

The speaker does NOT name a hard "X Aces" threshold. The framework is:
- **0 A**: bid only with مشروع
- **1 A (single, no T-mardoofa)**: pass unless مشروع
- **1 A (mardoofa with T)**: bid (مجازف tier)
- **2 A**: bid (confident tier — implied; the speaker's "two mardoofa" example is 2 A's)
- **3 A**: bid (mandatory)
- **4 A (الأربع مئة)**: bid Sun, never Ashkal

### Side-suit length — how does suit-length distribution affect the choice?

The speaker does NOT use the term "side-suit length" explicitly, but reasons by **mardoofa pairing**:

- **Two mardoofa (4-card commitment across 2 suits)** → optimal Sun shape; the remaining 1 card is a side filler.
- **One mardoofa + 3 side cards in other suits** → marginal/مجازف; whether to bid depends on score-state.
- **No mardoofa, 5 distributed cards** → does NOT support Sun unless مشروع compensates.
- **Concentrated single-suit (e.g. 5 cards in one suit, A+T+J+9+8)** → speaker does not address directly, but implicit rule: prefer **Hokm** for trump-concentrated hands. Sun rewards control across suits, Hokm rewards depth in one.

The speaker's worked examples consistently show **2-3-card-per-suit distributions** as the Sun-bid baseline. Long single-suit holdings are NOT the Sun shape.

### Other useful non-rule observations

- **Five inputs to bidding (speaker's framework):** (1) cards in hand, (2) personal risk tolerance / "are you a مجازف?", (3) النشرة (cumulative score), (4) what's already been bid before you (Hokm? Sun?), (5) seat position relative to dealer.
- **Cards-in-hand vs cards-on-ground (الأرض):** the bid-up card matters; speaker explicitly considers "if the buy-card were a J of Spades, this hand becomes makeable."
- **Score-state Bel reasoning:** with 100-meld + you behind 140-vs-yours-110, Bel is recommended even if opp took Sun ("لا تخاف، معاك مشروع 100").
- **First-lap pass discipline (R20):** "لا تستعجل، عدي أول لفة" — wait for the second lap to take a marginal Sun; partner or opp may resolve the bid for you.

---

## 5. Quality notes

- **Whisper transcription quality:** good. Most Arabic terms preserved; minor ASR drift on a few words (يديق/يدبر etc.) but core terms (إكة, مردوفة, مشروع, شايب/بنت/ولد, أبناء, نشرة, الصن المغطى) all clear.
- **Speaker discipline:** medium-low. Lots of conversational hedging and tier-blurring ("ممكن… على حسب… يعتمد عليك"). Hard rules are interspersed with player-style notes.
- **Worked examples:** the speaker walks through ~10 specific hand patterns; this is the strongest part of the video (extracted as R2-R16). The bid-or-pass decision for each is clearly stated.
- **Numerical specificity:** modest. Speaker references concrete failure costs (26 raw Sun, 16 raw Hokm), score thresholds (140/152, 100/120/130 framing), and meld values (50, 100, 400). No percentages or expected-value formulas; pure heuristic reasoning.
- **Confidence calibration:** treat R1-R16 as **Definite/Common** within this single source. Cross-video corroboration with videos 03/06/07 (which discuss Sun in passing) would upgrade them. R20-R22 (first-lap pass) is single-source — flag as **Sometimes** until corroborated.
- **Caption-error risk:** The speaker says "أبناء" (point-values) consistently; no homophone confusion noticed. Authoritative card-name mapping (شايب=K, بنت=Q, ولد=J) used throughout — no anti-trio mistakes.
- **Single-source caveats:** Sun-Mughataa (R29-R31) is mentioned; needs cross-reference. The Bel-fear matrix (R26-R28) draws on a follow-up video reference ("شرحت في مقطع حساب البلوت") not in this transcript.
- **Code-mapping notes:** all rules map to `Bot.PickBid` Bot.lua:725 with assist from `K.BOT_SUN_TH`, `K.BOT_ASHKAL_TH`=65, `K.BOT_BEL_TH`=60, `scoreUrgency` Bot.lua:588, and `matchPointUrgency` Bot.lua:619. The "first-lap pass discipline" (R20) currently has no encoded analog — would require a new turn-counter gating predicate in `Bot.PickBid`.
