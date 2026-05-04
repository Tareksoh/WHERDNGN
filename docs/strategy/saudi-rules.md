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
| Carré J | 200 | **disallowed** unless trump (Saudi: J carré only counts trump-implicit, see below) |
| Carré 9 | 150 | **disallowed** — `K.CARRE_RANKS` excludes "9" |
| Carré A,T,K,Q | 100 | 100 — `K.MELD_CARRE_OTHER` |
| Carré A in Sun | n/a | **200 (الأربع مئة, "Four Hundred")** — `K.MELD_CARRE_A_SUN` |
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
  - ≤3 cards remaining: instant claim.
  - 4: caller asks opponents for permission (5-sec auto-approve).
  - 5+: caller MUST تستاذن (request permission) — mandatory.
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
| **Qaid (قيد)** | **Post-bid** | Illegal play during round (failed must-follow, failed must-ruff, undeclared meld, observed cheat, **verbal slip about held cards** (تَوْضِيح لَعِب)) | Non-offending team scores **26 raw (Sun) / 16 raw (Hokm)** + their **own** melds; offending team's melds **forfeited (zeroed) but NOT transferred** to caller; ×multiplier applies on Bel/Bel-x2 |

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
`R.ScoreRound` line 504 gates Belote scoring on
`contract.type == K.BID_HOKM`. Single-source from video #41 says
"ملكي" K+Q meld scores in Sun. Could be regional house variant
or genuine convention. **Open question** — verify with another
Saudi source before extending code.

**Q2: Pos-4 partner-winning ruff-relief?** ✓ **Already in code.**
`R.IsLegalPlay` lines 117-121 (over-trump-partner relief) and
145-149 (general partner-winning relief on void). Video #42's
rule is fully enforced.

**Q3: Four-Aces Sun meld value (200 raw vs 400)?** ✓ **Reconciles
correctly.** `K.MELD_CARRE_A_SUN = 200` (raw); `R.ScoreRound`
line 672 applies `K.MULT_SUN = 2` to the round multiplier; line
678 multiplies meld points. So 200 raw × 2 Sun = 400 effective —
exactly what video #38 says. **No change needed.**

**Q4: Score-rounding ("5 rounds down")?** ⚠ **Possible mismatch.**
`R.ScoreRound` line 698: `div10(x) = math.floor((x + 4) / 10)` —
this rounds 65 → 6 (DOWN to 60). Video #43 extraction said
65 → 70 (UP). The in-code comment cites "5 rounds down" as the
rule. Verify the video extraction (it may have mis-quoted) or the
Saudi convention's actual rounding direction.

**Q5: Sun ×2 multiplier phrasing.** Code applies the ×2 in the
multiplier path (line 672), then `div10` at the end. Magnitude
matches video #43's "÷5 vs ÷10" framing (200/5 = 40 game points
vs 200/10 = 20 game points = ×2 effective). The two formulations
are equivalent; existing code is correct.

**Q6: سيكل (sykl) — 9-8-7 sequence?** Single-source, scoring
unconfirmed. Cross-check future videos before adding.

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
- **Failed bid (defenders win the round):** opponents capture all
  trick points; bidder team gets 0.
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
