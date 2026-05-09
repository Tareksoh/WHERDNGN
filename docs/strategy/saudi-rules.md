# Saudi Baloot rule deltas vs French Belote

WHEREDNGN implements the **Saudi/Khaleeji** Baloot variant. If you
search for "Belote rules" online you'll mostly find the French
parent game — many rules are different. This file documents the
deltas so strategy notes can assume Saudi rules without re-arguing
basics.

> **Source-of-truth precedence:** if a YouTube video contradicts
> this file, **fix this file** before changing the bot logic. This
> file aims to mirror the rules `Rules.lua` actually enforces.

---

## Deck and deal

- **Deck:** 32 cards (7 through Ace in 4 suits). Same as French.
- **Deal:** 8 cards per player. Same as French.
- **Players:** Exactly 4, in 2 partnerships. Same as French.

## Bidding (different)

- **Saudi bids:** `HOKM` (trump-named), `SUN` (no-trump), `ASHKAL`
  (3rd/4th-position bid that hands a SUN to partner), `PASS`.
  *No "all trumps" or "no trumps" auctions*; no points bidding.
- **Bid resolution:** First non-pass wins the contract; subsequent
  players can `PASS`, accept silently, or call `ASHKAL` if they're
  the partner of the Hokm-bidder and prefer to play it as Sun.
- **No "preneur":** the bidder doesn't gain or lose specifically by
  declaring; they take the contract and the round resolves under
  contract-typed scoring.

## Card values (mostly same as French, with one crucial twist)

- **Hokm (trump suit):** J=20, 9=14, A=11, T=10, K=4, Q=3, 8/7=0.
  Same order as French (J highest, 9 second). Sum = 62 raw.
- **Off-trump and Sun:** A=11, T=10, K=4, Q=3, J=2, 9/8/7=0.
  Sum = 30 raw per suit. Same as French.
- **Hand totals:** 152 trick points + 10 last-trick bonus.
  - Hokm round total = 162 (matches French Belote).
  - Sun round total = 130 (120 base + 10 last-trick) **then ×2
    multiplier applied** = 260 effective. *This ×2 is Saudi-specific;
    French "tout sans atout" multipliers vary.*

## Melds (significant differences)

| Meld | French Belote | Saudi Baloot (`Rules.lua`) |
|---|---|---|
| Tierce (3-seq) | 20 | 20 — `K.MELD_SEQ3` |
| Quarte (4-seq) | 50 | 50 — `K.MELD_SEQ4` |
| Quinte (5-seq) | 100 | 100 — `K.MELD_SEQ5` |
| Carré J | 200 | 100 — `K.MELD_CARRE_OTHER` (Saudi: J carré scores like T/K/Q at any contract, NOT 200; "trump-implicit" wording in earlier docs was incorrect — code is right). |
| Carré 9 | 150 | **disallowed** — `K.CARRE_RANKS` excludes "9" |
| Carré A,T,K,Q | 100 | 100 — `K.MELD_CARRE_OTHER` |
| Carré A in Sun | n/a | **400 (الأربع مئة, "Four Hundred")** — `K.MELD_CARRE_A_SUN` (v0.10.0 R5; see Q3 below) |
| Belote (K+Q trump) | 20 | 20 — `K.MELD_BELOTE`, **scored independently of multiplier** |

- **No "running announcement" rule** in Saudi; melds simply declared
  in trick 1.
- **Belote is multiplier-immune.** Even if the round goes ×4, the
  +20 K+Q-of-trump bonus stays at +20. (See `R.ScoreRound`.)
- **9 of trump is ranked but not a meld.** The 9 is the second-
  highest trump (rank-wise), but four 9s never form a Carré in Saudi.

## Escalation chain (Saudi-specific — does not exist in French)

This is the biggest rule difference. After bidding, before play
starts, there's a four-rung doubling chain:

1. **Bel (بل — ×2)** — defenders' window. Any defender can call.
2. **Bel x2 (بل×2 — ×3)** — bidder team's window. Counter to Bel.
   *Code identifier: `K.MSG_TRIPLE` / `Bot.PickTriple`.*
3. **Four (فور — ×4)** — defenders' window. Counter to Bel x2.
   *Saudi loan-word from English; written فور in Arabic.*
4. **Gahwa (قهوة — Coffee — match-win)** — bidder team's terminal.
   *A successful Gahwa wins the match outright; a failed Gahwa is
   a hand-killer.*

Each rung is voluntary. Skipping a rung closes the chain (e.g., if
nobody calls Bel x2 after Bel, the round plays at ×2). The chain
strictly alternates teams; you cannot Bel your own bid or Bel-x2
your opponent's.

## Special plays (Saudi-specific)

- **AKA (إكَهْ)** — partner-coordination signal in Hokm. The caller
  announces "I hold the highest unplayed in suit X". Reciprocal
  partner expectations apply.
  - **Implicit AKA** (per video #18): leading the **bare Ace of a
    non-trump suit** as your first lead is treated as an AKA call
    by the partner-side convention, even without an explicit
    `K.MSG_AKA` broadcast. Receiver applies the H-5 receiver
    convention in either case.
- **SWA (سوا)** — slam-with-ace. The caller asserts they will win
  every remaining trick.
  - **Code (since v0.5.17):** ALL SWA calls — regardless of card
    count — route through the 5-sec permission window so the
    caller's hand is visible to all players. The pre-v0.5.17
    "≤3 instant" branch was removed per user requirement
    (see `Net.lua:2473-2502`).
  - **Saudi rule:**
    - ≤3 cards remaining: convention is instant claim, but the
      addon still gates on the permission window (UX-only).
    - 4 cards: caller asks opponents for permission.
    - 5+ cards: caller MUST تستاذن (request permission) —
      mandatory per video #35 ("ما تساوي بدون ما تستاذن").
  - Saudi-strict: SWA is **deterministic-or-bust**; sub-100%-certain
    SWA claims are not the convention (per video #35).
  - Opponents can deny via Takweesh OR demand شرح (proof) — failed
    proof inverts to a Qaid against the caller.
- **Al-Kaboot (كبوت)** — bidder team sweeps all 8 tricks. Bonus:
  250 raw in Hokm, 220 in Sun (pre-multiplier).
- **Reverse Al-Kaboot (الكبوت المقلوب)** — *defenders* sweep all 8
  tricks against the bidder team. **v1.0.12 user-canonical PDF
  rule** (replacing the v0.10.5 video-#16 single-source hypothesis):
  «اللاعب الذي على يمين الموزع بشراء صن و(كبتت) عليه ولديه إكه
   سواء أخذها من الميدان أو كانت في يده. تسجل للفريق المقابل كبوت
   مقلوب بـ(88) بنط بالمشاريع». All four conditions must hold:
    1. Defender team sweeps all 8 tricks
    2. Bid is **SUN** (not Hokm)
    3. Bidder is on **dealer's right** (`seat == NextSeat(dealer)`)
    4. Bidder has/had an **Ace** at any point during the round
       (played in any trick, or — in the rare bidcard-takes-Ace
       case — would have played it after taking the bidcard)
  Reward: **88 banta FLAT** (= 880 raw post-multiplier; cardMult-
  immune so the same 88 banta holds in Sun-bare and Sun-Bel'd) +
  defender's declared melds × meldMult (the «بالمشاريع» clause).
  Constant: `K.AL_KABOOT_REVERSE = 880` (post-multiplier raw value).
  When any condition fails, the defender sweep falls through to
  the regular contract-fail path (defender takes `handTotal × cardMult`).

### Penalty system — Kasho vs Qaid

**These are TWO DISTINCT penalties** (per videos #30, #36). Earlier
docs conflated them under "Takweesh"; that conflation was wrong.

| Penalty | Phase | Trigger | Outcome |
|---|---|---|---|
| **Kasho (كاشو)** | **Pre-bid** | Procedural error during deal (mis-cut, dropped card, mis-deal) | **Redeal**, no points awarded |
| **Qaid (قيد)** | **Post-bid** | Illegal play during round (failed must-follow, failed must-ruff, undeclared meld, observed cheat, **verbal slip about held cards** (تَوْضِيح لَعِب), false AKA per J-069) | Non-offending team scores **26 gp (Sun) / 16 gp (Hokm)** + their **own** melds; **offending team FORFEITS their own melds** (per Source H H-36.12 + PDF 02 K-04 «المشتري مشروعه فايد» — "the buyer's meld is forfeited"); ×multiplier applies on Bel/Bel-x2. The 26/16 figures are *game points* after div10: Sun handTotal 130 × Sun mult 2 = 260 raw → 26 gp; Hokm handTotal 162 × 1 = 162 raw → 16 gp. The code in `Net.HostResolveTakweesh` awards `handTotal × cardMult` raw and the standard `(x+5)/10` div10 produces 26/16 gp exactly. v0.10.1 user arbitration; see asymmetry doctrine note below. |

#### Doctrine note — meld asymmetry between regular fail and Qaid

**This is intentional**, not an inconsistency. The two scenarios
fire under different proverbs and must be treated separately:

| Scenario | Path | Melds outcome | Saudi proverb |
|---|---|---|---|
| Bidder team plays out tricks but fails to make | `R.ScoreRound` fail branch (v0.4.3+) | Both teams **keep** own declared melds; only the trick-point side flows to defenders | «مشروعي لي ومشروعك لك» — "my meld for me, your meld for you" — the contract resolved fairly via tricks |
| Round terminates on rule violation (Takweesh / invalid SWA / false AKA) | `Net.lua` Qaid handlers (v0.10.1+) | Offender **forfeits** own melds; non-offender keeps theirs × mult | «المشتري مشروعه فايد» — "the buyer's meld is forfeited" — rule violation revokes the offender's standing to score |

The two readings are CONSISTENT in their respective contexts —
they describe different terminations of a round. Regular fail is
a contract-level outcome (try-and-fail); Qaid is a rule-violation
outcome (illegal play). Saudi convention treats them differently
on melds because they're different KINDS of round-end.

**Code locations:**
- Regular fail: `Rules.lua` `R.ScoreRound` line ~854 (`outcome_kind == "fail"` branch)
- Qaid Takweesh: `Net.lua` `HostResolveTakweesh` line ~2196-2218
- Qaid invalid SWA: `Net.lua` `HostResolveSWA` line ~2940-2950

The pre-v0.10.1 code applied the «مشروعي لي ولك مشروعك» reading
uniformly to BOTH paths (Codex/Gemini 14th-audit). v0.10.1's user
arbitration corrected the Qaid path to «المشتري مشروعه فايد»
based on Source H H-36.12 + PDF K-04 (the explicit-forfeit
reading). Historical CHANGELOG entry: v0.10.1 M1.

**Takweesh (تكويش)** is the *verb form* of calling Kasho. Calling
"Takweesh" during pre-bid invokes Kasho mechanics. Post-bid illegal
plays are accused via Takweesh and *resolved* via Qaid. Existing
`K.MSG_TAKWEESH` + `K.MSG_TAKWEESH_OUT` cover the call/outcome
flow; the score side correctly produces the 26/16 gp split via
`handTotal × cardMult ÷ 10` (verified v3.0.3 GAP-06 audit closure).

**Trigger discipline (video #36):** bot-side Takweesh calls should
be restricted to **explicit triggers only** — failed-follow-suit,
failed-Hokm-ruff, failed-over-cut, undeclared meld, observed cheat.
Ambiguous breaches resolve via house rules (الجلسات), not formal
qaid.

### Rule-correctness questions from videos 32-43 — resolved

Cross-checked against `R.IsLegalPlay`, `R.ScoreRound`, and
`Constants.lua`. Status:

**Q1: Belote (K+Q of trump) in Sun?** ✗ **NOT in code.**
`R.ScoreRound` line ~795 gates Belote scoring on
`contract.type == K.BID_HOKM`. Single-source from video #41 says
"ملكي" K+Q meld scores in Sun. Could be regional house variant
or genuine convention. **Open question** — verify with another
Saudi source before extending code.

**Q2: Pos-4 partner-winning ruff-relief?** ✓ **Already in code.**
`R.IsLegalPlay` lines 137-141 (over-trump-partner relief) and
165-169 (general partner-winning relief on void). Video #42's
rule is fully enforced.

**Q3: Four-Aces Sun meld value (200 raw vs 400)?** ✅ **RESOLVED v0.11.10
(authoritative rule: 200 raw, full Sun×2 mult applied).** Both
v0.10.0 R5 (200→400) and v0.11.6 (split-multiplier "melds Sun-immune")
were superseded by user-stated authoritative rule v0.11.10:

> sere is 4 points in sun and 2 in hokm
> 50 is 10 points in sun and 5 in hokm
> 100 is 20 points in sun and 10 in hokm
> Carré-A is 40 points in sun and shifts to 10 in hokm as there is
> no carré-A in hokm.

Decoded as raw values (with /10 final divisor and Sun×2 mult applied):
- sere = 20 raw → Hokm 20×1/10 = 2 nq, Sun 20×2/10 = 4 nq ✓
- quarte = 50 raw → Hokm 5 nq, Sun 10 nq ✓
- quinte / Carré-other = 100 raw → Hokm 10 nq, Sun 20 nq ✓
- Carré-A = **200 raw** → Sun 200×2/10 = 40 nq ✓
- Carré-A in Hokm: emits as `K.MELD_CARRE_OTHER` (100 raw) → 10 nq
  via X5 path

**Multiplier rule (canonical, v1.0.9 PDF §5-6 cap-at-Bel):**
- **Cards** scale with the FULL contract cascade (Sun ×2 +
  Bel/Triple/Four/Gahwa, all stacking).
- **Melds** (sequence, carré-other, carré-A) scale with Sun ×2 + Bel
  ×2 ONLY — Triple/Four/Gahwa do NOT cascade onto melds. PDF §5-6:
  «لا تضاعف المشاريع في حالة الثري والفور» — "melds do not multiply
  in the case of Triple and Four". Belote (K+Q of trump) is fully
  multiplier-immune (added post-mult; +20 raw → +2 nq always).
- **Sun + Bel**: cards ×4, melds ×4 (Sun×2 × Bel×2 stacks for both).
- **Hokm + Triple**: cards ×3, melds ×2 (cap).
- **Hokm + Four / Gahwa**: cards ×4, melds ×2 (cap).

The split is exposed on `R.ScoreRound`'s result struct as
`cardMultiplier` and `meldMultiplier`. Legacy `multiplier` field
aliases `cardMultiplier` for back-compat.

Cross-confirmed against video #43 explicit walkthrough at lines
152-158: "بالنسبه للمشاريع في السن برضو راح تحولها لنقاط تقسم على
خمسه" — "regarding melds in Sun, you also convert them by dividing
by 5" — which is mathematically equivalent to "× Sun×2 ÷ 10". The
Sun×2 absolutely does apply to melds; the v1.0.9 PDF cross-check
clarified that the ESCALATION rungs (Triple/Four/Gahwa) are the
ones that cap on melds, not the contract-type multiplier.

Implementation: `Rules.lua` R.ScoreRound + `Net.lua`
HostResolveTakweesh + HostResolveSWA all use the cardMult/meldMult
split per v1.0.9 D HIGH-1.

Implementation history (for posterity):
- v0.4.x: 200 raw + Sun×2 (correct, but undocumented as canonical)
- v0.10.0 R5: 200→400 (wrong; produced 80 nq in Sun)
- v0.11.6: 400 + melds Sun-immune (wrong; produced 40 nq for Carré-A
  but broke sere/quarte/quinte to 2/5/10 instead of 4/10/20)
- v0.11.10: full revert to v0.4.x state (200 raw, full Sun×2 mult).
  Cards AND melds × full cascade including Triple/Four/Gahwa.
- v1.0.9 (PDF cross-check): full-cascade kept for cards but melds
  cap at Bel per PDF §5-6. v0.11.10's Triple/Four/Gahwa cascade on
  melds was over-multiplying — corrected. User arbitration: "option
  A i was wrong" — agreed with PDF reading. See CHANGELOG v1.0.9.
  User-stated authoritative rule.

**Q3b: Carré-A in Hokm.** ✅ **RESOLVED v0.10.0 (X5).** Pre-v0.10.0
`R.DetectMelds` had no `else` branch for the Hokm-A path — the
meld was silently DROPPED. Per videos #32 line 245 + #38 line 61,
Carré-A in Hokm scores 100 (treated like the other carrés).
Cascade: missing meld broke bidder-strict-majority threshold,
`R.CompareMelds` winner-takes-all, AND v0.9.0 M5 belote-
cancellation (silent +20 over-scoring). Fixed in
`Rules.lua:273-287` + regression test inverted at
`tests/test_rules.lua:365-379`. Source: `review_v0.10.0/
xref_X5_meld_coverage.md`.

**Q4: Score-rounding ("5 rounds UP" per video #43).** ✅ **RESOLVED v0.5.6.**
`R.ScoreRound` div10 is now `math.floor((x + 5) / 10)` —
rounds 65 → 70 (UP), 64 → 60. Per video #43 ("حساب النقاط
في البلوت للمبتدئين"). Earlier `(x + 4) / 10` formulation was
wrong; v0.5.6 fixed all div10 sites to align (R.ScoreRound,
HostResolveTakweesh, HostResolveSWA-invalid). v0.10.0 review
Phase1-I double-confirmed against verbatim source examples:
65→70, 66→70, 67→70, 64→60, 62→60, 55→60, 51→50, 74→70.

**Q5: Sun ×2 multiplier phrasing.** ✅ **RESOLVED v0.11.10.** Code applies
the Sun ×2 (contract mult) and any active escalation (Bel ×2, Triple
×3, Four ×4, Gahwa ×4) UNIFORMLY to both card-trick points and
declared melds. The post-mult sum gets `/10` (with "5 rounds UP"
rounding per video #43). Belote (K+Q of trump) is the lone
multiplier-immune exception (+20 raw added post-mult).

This matches video #43's "÷5 in Sun" worked-examples directly: the
speaker walks through sere (20→4 in Sun), quarte (50→10), and
quinte (100→20) using the /5 divisor — which is mathematically
equivalent to `× Sun×2 ÷ 10`. The earlier (v0.11.6) interpretation
that the worked examples were "simplified accumulated arithmetic"
was incorrect; they are direct per-meld value statements.

History note: v0.11.6 briefly experimented with "melds Sun-immune"
(only Carré-A would have produced the canonical 40 nq under that
rule, but it broke sere/quarte/quinte to 2/5/10 nq). The v0.11.10
revert restores the canonical rule. See Q3 for full math reference.

**Q6: سيكل (sykl) — 9-8-7 sequence?** ✅ **RESOLVED v0.10.0 (review).**
Per Phase 1 Source I extraction: سيكل is the colloquial name
for any 9-8-7 tierce; it scores **20 raw**, identical to any
other tierce (`K.MELD_SEQ3`). NOT a separate meld — just a
name. `R.DetectMelds` already detects it correctly via
`K.RANK_INDEX` ordering. No code change needed; this Q can be
closed.

**Q7: Bid takweesh (override partner's bid).** Video #29
introduces a SECOND meaning of "takweesh" — competing with
partner's bid. This is **bid-decision logic** (`Bot.PickBid`
should not bid against partner's strong contract), distinct from
the existing `K.MSG_TAKWEESH` penalty-call. Glossary updated to
disambiguate.

### Bel (×2) legality gate (per video #11)

**Sun contracts only:** the team currently at **≥100 cumulative
score** is **forbidden** from calling Bel. Only the team at <100
may Bel. This is a HARD rule, not a heuristic — `Rules.lua` should
enforce it via `R.CanBel(team)` predicate.

**Hokm contracts:** no such gate. "الحكم مفتوح في الدبل" — Hokm is
open to Bel from either team regardless of score.

**Round-1 anti-grief:** speaker says round-1 Bel is restricted —
need to verify exact rule from a follow-up video.

Other Bel constraints (per video #11):
- Cards-revealed lockout — once any card is shown, Bel window
  closes.
- "مقفول" (closed) under even-multiplier Hokm — speaker references
  but does not fully define; flag for follow-up.

## Scoring quirks

- **Half-and-half tiebreak:** if bidder team gets exactly 81 of 162,
  bidder **fails** (need strictly more than half). `R.ScoreRound`
  encodes this.
- **Failed bid (defenders win the round):** defenders capture the
  full `handTotal` (×multiplier) as a qaid penalty against the
  bidder team. Per the Saudi rule «مشروعي لي ومشروعك لك» ("my
  meld for me, your meld for you"), each team **KEEPS its own
  declared melds** — only the trick-point side flows to the
  winner. v0.4.3+ encoded this at `Rules.lua:823-840`; pre-v0.4.3
  the bidder-team's own melds were silently confiscated when the
  bid failed (e.g. a quarte=50×2=100 raw was lost to the qaid).
- **Multiplier scope:** ×2/×3/×4 applies to the trick-point side
  of the score. Belote +20 is multiplier-immune. Gahwa is binary
  (match-win/loss) — multiplier moot.

## Trick-play rules

- **Must follow suit** if able. (Same as French.)
- **Must over-trump** if leading suit is trump and you can over-cut.
  Saudi-strict; some French variants allow under-trumping.
- **Must trump-ruff** if void in led suit and your team is not
  currently winning the trick. *AKA receiver convention overrides
  this in some cases* — see `signals.md`.

---

## Where this lives in code

- `Rules.lua` — `R.ScoreRound`, `R.IsLegalPlay`, `R.TrickWinner`,
  `R.TrickPoints`. Authoritative for rules enforcement.
- `Constants.lua` — `K.POINTS_TRUMP_HOKM`, `K.RANK_TRUMP_HOKM`,
  meld scores, escalation thresholds.
- `Net.lua` — multiplier application in score broadcasts.

If a strategy note in this folder cites a rule, **link to the line
in `Rules.lua` that enforces it**. Keeps the docs honest.

---

## Bot calibration journey (v0.10.0 → v0.11.10)

This section is a calibration changelog for bot bidding/scoring tuning.
The rules above don't change; what's documented here is how the bot's
*decision* logic was tuned over 12 release cycles to match real-game
Saudi-pro patterns.

### Live diagnostic toggle

Use `/baloot bidcalc` (added v0.11.8) to enable a per-call trace of
`Bot.PickBid`'s Sun-vs-Hokm decisions. Output goes to chat with
`[bid sN rR]` prefix showing hand, sun strength, all thresholds, and
which decision branch fired (or was skipped). Off-by-default; zero
overhead in production. Toggle off when done: `/baloot bidcalc` again.

### Calibration constants — current values

| Constant | Current | Where |
|---|---|---|
| `K.BOT_TH_HOKM_R1_BASE` | 42 | Constants.lua, Bot.PickBid R1 Hokm |
| `K.BOT_TH_HOKM_R2_BASE` | 36 | R2 Hokm threshold |
| `K.BOT_TH_SUN_BASE` | 40 | R1+R2 Sun threshold |
| `K.BOT_BID_JITTER` | 6 | ±6 swing per call |
| `K.BOT_SUN_VOID_PENALTY_CAP` | 8 | sunStrength void/short-suit penalty cap |
| `K.BOT_SUN_MARDOOFA_BONUS` | 20 | per A+T mardoofa pair |
| `K.BOT_SUN_3ACE_BONUS` | 15 | extra +bonus for 3+ Aces |
| `K.MELD_CARRE_A_SUN` | 200 raw | Carré-A in Sun (canonical) |

### Tuning history

| Constant | v0.4 | v0.10.4 | v0.10.6 | v0.11.9 | v0.11.10 |
|---|---|---|---|---|---|
| `BOT_SUN_MARDOOFA_BONUS` | 5 | 10 | – | 20 | – |
| `TH_SUN_BASE` | 50 | – | 47 | – | **40** |
| `sunStrength` void-cap | 25 | – | – | 8 | – |
| `K.MELD_CARRE_A_SUN` | 200 | 400(R5) | – | – | **200(revert)** |
| `hokmMinShape` count==2 | strict | – | LOOSER (Lever C) | TIGHTER (req 9 or A) | – |

The v0.10.0 R5 + v0.11.6 split-multiplier experiments both introduced
regressions; v0.11.10 reverted to the canonical v0.4.x state. See Q3
above and CHANGELOG v0.11.10 for full rationale.

### Diagnostic process

Per the v0.11.8/v0.11.9/v0.11.10 cycle: the user reported a
"bots not bidding Sun" pattern, captured a chat log via the
`/baloot bidcalc` toggle, and the trace data revealed:

1. Hands legitimately failing `sunMinShape` (correct — most hands
   structurally don't qualify for Sun)
2. Hands passing `sunMinShape` but failing the strength threshold
   by 20-30 points (calibration gap)

The bidcalc trace exposes both the structural-eligibility check
and the strength threshold gate, so future calibration questions
can be answered against real-game data without instrumenting on
the fly.
