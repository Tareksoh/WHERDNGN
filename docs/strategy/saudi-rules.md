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
  tricks against the bidder team. Bonus: **+88 raw**. Qualifies
  only when bidder was the trick-1 leader. **Single-source rule
  (video #16); confirm before wiring.** New constant proposal:
  `K.AL_KABOOT_REVERSE = 88`.

### Penalty system — Kasho vs Qaid

**These are TWO DISTINCT penalties** (per videos #30, #36). Earlier
docs conflated them under "Takweesh"; that conflation was wrong.

| Penalty | Phase | Trigger | Outcome |
|---|---|---|---|
| **Kasho (كاشو)** | **Pre-bid** | Procedural error during deal (mis-cut, dropped card, mis-deal) | **Redeal**, no points awarded |
| **Qaid (قيد)** | **Post-bid** | Illegal play during round (failed must-follow, failed must-ruff, undeclared meld, observed cheat, **verbal slip about held cards** (تَوْضِيح لَعِب)) | Non-offending team scores **26 raw (Sun) / 16 raw (Hokm)** + their **own** melds; offending team **keeps** their own melds (per "مشروعي لي ولك مشروعك" — corrected v0.4.3+ per Codex/Gemini 14th-audit); ×multiplier applies on Bel/Bel-x2. Audit `audit_v0.9.0/28_rules_aka_swa_takweesh.md` §4 verified. |

**Takweesh (تكويش)** is the *verb form* of calling Kasho. Calling
"Takweesh" during pre-bid invokes Kasho mechanics. Post-bid illegal
plays are accused via Takweesh and *resolved* via Qaid. Existing
`K.MSG_TAKWEESH` + `K.MSG_TAKWEESH_OUT` cover the call/outcome
flow; the score side currently lacks the 26/16 split.

**Trigger discipline (video #36):** bot-side Takweesh calls should
be restricted to **explicit triggers only** — failed-follow-suit,
failed-Hokm-ruff, failed-over-cut, undeclared meld, observed cheat.
Ambiguous breaches resolve via house rules (الجلسات), not formal
qaid.

### Rule-correctness questions from videos 32-43 — resolved

Cross-checked against `R.IsLegalPlay`, `R.ScoreRound`, and
`Constants.lua`. Status:

**Q1: Belote (K+Q of trump) in Sun?** ✗ **NOT in code.**
`R.ScoreRound` line 694 gates Belote scoring on
`contract.type == K.BID_HOKM`. Single-source from video #41 says
"ملكي" K+Q meld scores in Sun. Could be regional house variant
or genuine convention. **Open question** — verify with another
Saudi source before extending code.

**Q2: Pos-4 partner-winning ruff-relief?** ✓ **Already in code.**
`R.IsLegalPlay` lines 137-141 (over-trump-partner relief) and
165-169 (general partner-winning relief on void). Video #42's
rule is fully enforced.

**Q3: Four-Aces Sun meld value (200 raw vs 400)?** ✅ **RESOLVED v0.10.0
(R5).** `K.MELD_CARRE_A_SUN` was previously stored as **200**
with the rationale that `R.ScoreRound`'s `K.MULT_SUN = 2` would
bring it to "400 effective". That reasoning was wrong: code's
`× mult / div10` pipeline produced **40 game points** (200×2÷10)
NOT 80 — exactly half the canonical value. Per the v0.10.0
review's verbatim Arabic from videos #32 + #38, الأربع ميه ("Four
Hundred") names a **400 raw direct** value; per video #43 Sun
divides raw by 5 (400 ÷ 5 = 80 game points). Fixed:
`K.MELD_CARRE_A_SUN = 400` and the comment now traces the math
correctly. The earlier "Gemini scoring-audit catch" that changed
400→200 was a misinterpretation. Source: `review_v0.10.0/
reaudit_R5_carre_a_sun.md`.

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

**Q5: Sun ×2 multiplier phrasing.** Code applies the ×2 in the
multiplier path, then `div10` at the end. Magnitude matches
video #43's "÷5 vs ÷10" framing for trick points and standard
melds. Note: now that Q3 (`K.MELD_CARRE_A_SUN = 400`) is fixed,
the math goes 400 × Sun×2 ÷ 10 = 80 game points, matching the
video's 400÷5 = 80 framing. The two formulations are
equivalent; existing code is correct.

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
