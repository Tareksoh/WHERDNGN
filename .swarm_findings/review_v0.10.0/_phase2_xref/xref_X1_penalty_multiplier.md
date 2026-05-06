# X1: Penalty + multiplier scope

Cross-reference of Phase-1 audit claims (Source H = videos #29/30/34/36;
Source J = videos #37/39/40/41/42/44; Source K = PDFs 01, 02) against
the WHEREDNGN code at `C:\CLAUDE\WHEREDNGN\` (Constants.lua, Rules.lua,
Net.lua, tests/test_rules.lua).

**Key terminology disambiguation (carried throughout this report):**

| Term used in sources | Code's term | Code's representation |
|---|---|---|
| Qaid Sun = "26 raw" | "Sun handTotal" | `K.HAND_TOTAL_SUN = 130` |
| Qaid Hokm = "16 raw" | "Hokm handTotal" | `K.HAND_TOTAL_HOKM = 162` |

The Saudi rule book (Sources H + J + K) speaks of Qaid penalty values
in **post-rounding "game points"** (26 / 16). The code instead speaks
in **pre-rounding raw points** (130 / 162) and arrives at the correct
26 / 16 game points after `(× Sun-mult ÷ 10) round-up` — see trace
below. This is the source of confusion: the constants in
`Constants.lua` look "wrong" against the source claims at first read
but are arithmetically correct.

---

## Qaid base values (code vs source)

| Item | Source claim (game points) | Code constant | Trace to game points | Match |
|---|---|---|---|---|
| Sun Qaid base | **26** (H-30.3, H-36.8, J-025, K-02) | `K.HAND_TOTAL_SUN = 130` (Constants.lua:55) | 130 raw × `K.MULT_SUN`=2 = 260; `(260+5)/10`=26 | YES (after pipeline) |
| Hokm Qaid base | **16** (H-30.4, H-36.9, J-025, K-02) | `K.HAND_TOTAL_HOKM = 162` (Constants.lua:54) | 162 raw × 1 = 162; `(162+5)/10`=16 | YES (after pipeline) |
| Pre-bid (Tawzee) Qaid | **16** (H-30.6, H-36.10, J-033) | **MISSING** — no `K.QAID_PRE_BID` constant; pre-bid penalty path is not implemented (see "Bugs found" #B1) | n/a | **NO — not modeled** |
| `K.QAID_RAW_SUN` constant | (not asked by source) | **DOES NOT EXIST** in `Constants.lua` | — | — |
| `K.QAID_RAW_HOKM` constant | (not asked by source) | **DOES NOT EXIST** in `Constants.lua` | — | — |

A grep for `K.QAID*` against `Constants.lua` returns ZERO hits. The
question's premise of "verify K.QAID_RAW_SUN, K.QAID_RAW_HOKM,
K.QAID_PRE_BID" is itself slightly miscalibrated — those constants
were never created. The code uses `K.HAND_TOTAL_*` directly. There
is, however, one stale doc reference to non-existent
`K.QAID_HOKM = 16` / `K.QAID_SUN = 26` at
`docs\strategy\_transcripts\40_cut_deal_rules_extracted.md:187-188`
— the docs assert constants the code does not have. (See "Bugs
found" #B2.)

---

## R.ScoreRound Qaid path trace

There are TWO Qaid resolution paths in the code, both in `Net.lua`:

1. **Takweesh** — `N.HostResolveTakweesh` at `Net.lua:2131-2305`
   (caller catches an illegal play; phase = PLAY).
2. **Invalid SWA** — `N.HostResolveSWA` at `Net.lua:2852+` (caller's
   SWA claim fails the minimax validator).

**Crucially, `R.ScoreRound` itself does NOT have a "Qaid path"** —
the function is the regular round-end scorer that handles
made / failed / sweep / tie. The Qaid penalty is a parallel scoring
function in `Net.lua` that reuses the same multiplier ladder + meld
constants but bypasses ScoreRound entirely. The `outcome_kind=="fail"`
branch in `R.ScoreRound` (Rules.lua:791-808) coincidentally produces
the same 16/26 number for a defender-takes-handTotal ordinary failed
contract because that is the SAME numeric quantity.

### Step-by-step trace of `N.HostResolveTakweesh` after a found-illegal

`Net.lua:2131-2305` (post-bid Qaid path):

```
1. Phase guard: phase must be K.PHASE_PLAY (Net.lua:2133).
   → Pre-bid Qaid is NOT reachable.

2. Cancel turn timer + clear S.s.swaRequest (Net.lua:2138-2148).

3. Determine teams: callerTeam = R.TeamOf(callerSeat).
   oppTeam = the other one.

4. Scan all played tricks + the in-flight trick for any p.illegal
   marked play by an OPPOSING-team seat (Net.lua:2153-2166).

5. Set winnerTeam:
   - foundIllegal     → winnerTeam = callerTeam (Qaid succeeds)
   - none found       → winnerTeam = oppTeam   (Qaid fails / reverses
                                                 — H-36.3 conformance)
   (Net.lua:2179)

6. handTotal = (Sun) ? K.HAND_TOTAL_SUN : K.HAND_TOTAL_HOKM
   = 130 or 162.            (Net.lua:2181)

7. Multiplier ladder (Net.lua:2189-2194):
       mult = K.MULT_BASE = 1
       if Sun:    mult *= K.MULT_SUN    = 2
       if gahwa:  mult *= K.MULT_FOUR   = ×4
       elif foured:  mult *= K.MULT_FOUR  = ×4
       elif tripled: mult *= K.MULT_TRIPLE = ×3
       elif doubled: mult *= K.MULT_BEL  = ×2
   (only ONE escalation rung applies — replacement, not stacking)

8. meldA = R.SumMeldValue(S.s.meldsByTeam.A)   ← OWN melds for both teams
   meldB = R.SumMeldValue(S.s.meldsByTeam.B)
   cardA = (winnerTeam == "A") ? handTotal : 0
   cardB = (winnerTeam == "B") ? handTotal : 0
   mpA = meldA   ← KEY: BOTH teams keep their OWN melds, including
   mpB = meldB         the loser. (Net.lua:2200-2208 with comment
                       citing the 14th-audit fix.)

9. Belote scan (Hokm only): find K-of-trump and Q-of-trump from
   played cards. If same seat played both → belote = R.TeamOf(seat).
   Cancel belote if K+Q holder also declared a ≥100 meld
   (Net.lua:2213-2236).

10. rawA = (cardA + mpA) * mult              ← own melds get multiplied
    rawB = (cardB + mpB) * mult
    if belote == "A": rawA += K.MELD_BELOTE  ← Belote +20 NOT multiplied
    elif belote == "B": rawB += K.MELD_BELOTE  (Net.lua:2238-2241)

11. addA = math.floor((rawA + 5) / 10)       ← div10 with 5-rounds-UP
    addB = math.floor((rawB + 5) / 10)        (video #43 conformance)

12. Apply to cumulative + broadcast SendRound. (Net.lua:2251-2281)
```

**Worked numerical examples** (each cross-checks one Source-H claim):

| Scenario | Formula | rawA (winner) | game points |
|---|---|---|---|
| Hokm Qaid, no escalation, no melds | (162 + 0) × 1 | 162 | **16** ✓ H-36.9 |
| Sun Qaid, no escalation, no melds | (130 + 0) × 2 | 260 | **26** ✓ H-36.8 |
| Sun Qaid × Bel(×2), no melds | (130 + 0) × 4 | 520 | **52** ✓ H-36.13 |
| Hokm Qaid × Bel(×2), no melds | (162 + 0) × 2 | 324 | **32** ✓ H-36.13 |
| Sun Qaid × Bel(×2) + own sera (20) | (130 + 20) × 4 | 600 | **60** ✓ H-36.13 |
| Sun Qaid × Four(×4), no melds | (130 + 0) × 8 | 1040 | **104** ✓ H-36.13 |

All Source-H H-36.13 numerical examples reproduce exactly under the
code's pipeline. Multiplier scope IS as Source H claims (Qaid base ×
mult AND own melds × mult).

---

## Multiplier scope verdict

| Element | Multiplier-applied (code) | Source says | Match |
|---|---|---|---|
| Trick points (made contract) | YES — `rawA = (cardA + meldPoints.A) * mult` (Rules.lua:848) | YES (implicit; standard scoring) | YES |
| Qaid base (handTotal) | YES — `(cardA + mpA) * mult` (Net.lua:2238) | YES (H-36.13 explicit) | YES |
| Own melds in Qaid | YES — same formula | YES (H-36.13 explicit, "MELDS ALSO MULTIPLY under Qaid") | YES |
| Opp melds in Qaid | N/A — opp's melds are kept WITH the offender (mpA = meldA, mpB = meldB), so they multiply on the offender's side too. **Both teams' own melds multiply, but the LOSER's melds are NOT transferred to the winner's pile** | "Caller keeps OWN melds; offender's melds are zeroed but NOT transferred" (H-36.12 + K-08 + K-09). Source actually says **zeroed**, not "kept" | **PARTIAL MISMATCH — see Bugs #B3** |
| Belote (K+Q trump) +20 | NO — added AFTER mult (Rules.lua:861-865; Net.lua:2240-2241) | Sources H/J don't address this directly under Qaid; CLAUDE.md says "multiplier-immune"; PDF K-27 says "Belote does not get the Double multiplier" | YES (consistent with K-27 + CLAUDE.md) |
| Carré other (T/K/Q/J) | YES — value=100 stored as a meld → flows through `(cardA + meldPoints.A) * mult` | Not explicitly addressed in cluster; K-23 implies Hokm full-escalation applies; H-36.13 lists "MELDS ALSO MULTIPLY" generically | YES (consistent) |
| Carré A in Sun (200 raw) | YES — value=200 stored as a meld → multiplied | covered separately by R5 audit | (covered by R5) |

### Discussion: H-36.13 vs CLAUDE.md "Belote multiplier-immune"

Source H H-36.13 explicitly says **"MELDS ALSO MULTIPLY under Qaid"**
and gives `Sun-Qaid + sera under Bel-double = 8 + 52 = 60` (i.e.
sera adds 8 game points pre-Bel, becomes 8 → multiplied to 60-52=8?
No — re-reading: 130 raw × ×4 = 520 = 52gp PLUS sera 20 raw × ×4 = 80
→ 8gp = TOTAL 60gp). So sera (a 20-raw seq3) multiplies. The video
does NOT list **Belote** in its multiplier-applied examples — H-36.13
only mentions sera, fifty, and hundred. The code applies Belote AFTER
the multiplier (immune), which agrees with PDF K-27 "البلوت لايدبل"
("Belote does not get doubled") and CLAUDE.md.

**Verdict on the user's flagged divergence:** H-36.13 does NOT
explicitly contradict the Belote-immune rule. It addresses the
multiplication of Qaid base + sera/fifty/hundred melds, all of which
the code does correctly multiply. The Belote immune rule survives.
H-36.13 and CLAUDE.md are compatible — the Source-H phrase
"Multiplier INCLUDES Qaid base AND own-meld bonuses" should be read
as "Qaid base + ordinary melds (sera, fifty, hundred, carré); Belote
remains separate per its Pagat-strict +20 fixed-rule".

### Source-J J-034: "Wronged side's projects ADD to Qaid total"

J-034 says "When taking Qaid, if the wronged side has a project
(Sera, Carré, etc.), it adds to their Qaid total." The code
implements this exactly: `mpA = meldA; mpB = meldB; rawA = (cardA +
mpA) * mult` adds the WINNER's own meld total to the Qaid base. ✓

### Source-H H-36.12: "Offender's melds are zeroed but NOT transferred"

This is the divergence. Code keeps offender's melds with the offender
(both teams keep their OWN), where Source H says they should be
**zeroed**. See Bugs #B3.

---

## Bugs found

### B1 — Pre-bid (Tawzee) Qaid not modeled (gap, not bug)
**Sources:** H-30.6, H-36.10, J-033, J-Code-watchpoint J-025
**Code:** `N.LocalTakweesh` (Net.lua:2077) and `N.HostResolveTakweesh`
(Net.lua:2133) both gate on `S.s.phase ~= K.PHASE_PLAY → return`.
**Effect:** No path scores a 16-raw Tawzee Qaid for misdeal /
deal-error / pre-bid cheating. Sources H + J + K all describe this
as an active rule.
**Severity:** Low (pre-bid Qaid is procedural / dispute-resolution
that rarely triggers in casual play; glossary explicitly says "Kasho
[and pre-bid Qaid]: Currently not modeled in code; player-only edge
case"). Not a regression — design choice.
**Reference:** `.swarm_findings\audit_v0.7.1\45_takweesh_flow.md:31`
already documented this scope decision.

### B2 — Stale doc reference to non-existent constants
**Source:** doc-only, single line each
**Code:**
`docs\strategy\_transcripts\40_cut_deal_rules_extracted.md:187-188`
references `K.QAID_HOKM = 16` and `K.QAID_SUN = 26`. Neither exists
in `Constants.lua`.
**Effect:** Incorrect breadcrumb. Anyone following the doc to the
constant will not find it.
**Severity:** Low (docs only; no runtime impact).
**Fix:** either rename the doc references to `K.HAND_TOTAL_HOKM` /
`K.HAND_TOTAL_SUN` (with a note that the divisor-by-10 brings them
to 16/26 game points) OR introduce semantic aliases
`K.QAID_RAW_HOKM = K.HAND_TOTAL_HOKM` and `K.QAID_RAW_SUN =
K.HAND_TOTAL_SUN` to align constant names with the source-rule names.

### B3 — Offender's melds: code KEEPS them with offender; Source H says ZEROED
**Sources:** H-36.12 ("Offender's melds are NOT transferred to you —
they are simply zeroed/forfeited"), H-30.5 ("opponent treatment is
sessional"), K-03 ("My meld is mine, your meld is yours"), K-04
("buyer's meld is forfeited (kept by neither side, just lost)"),
K-08, K-09 ("buyer scores only the round (16 or 26) and does NOT
take the defender's meld, because the meld is fundamentally yours"),
K-14 (same rule under Double).

**Code:** `Net.lua:2207-2208` sets `mpA = meldA; mpB = meldB`, with
the comment at 2200-2206 explicitly citing PDF K's
"مشروعي لي ومشروعك لك" rule and the 14th-audit fix that **changed
this from "loser meld zeroed" to "loser meld kept"**.

**Effect:** Sources DISAGREE. PDF K-04 / K-08 / K-09 (the strongest
"meld stays with owner" claim) is the source of truth the code
follows. Source H H-36.12 says "zeroed/forfeited" — the offender
"loses" them in the sense that they don't add to the offender's
score, but in the code they DO add to their own pile via `mpA = meldA`
even when team A is the loser.

**Decoding:** look at the actual numerical effect. If the offender's
meld is added to their `mp_offender`, then:
   raw_offender = (0 + meld_offender) * mult > 0

Compared to Source-H's "zeroed":
   raw_offender = (0 + 0) * mult = 0

So the LOSER (offender) gets some non-zero score from their own
melds in the code. **This is wrong if H-36.12 / K-04 are taken
strictly** — both say the meld is "forfeited" / "kept by neither
side, just lost". K-04 is unambiguous: "the buyer's meld is
forfeited (kept by neither side, just lost). The opponent does not
gain the buyer's meld."

K-08 is the clearest principle: "in the foul/registration case, play
stops here, meaning there is no contest — therefore neither side wins
the meld off the other. The meld stays with whoever owned it; only
the round-penalty (16/26) transfers." This says the meld doesn't
TRANSFER but does NOT specify whether the offender SCORES their own
meld. The 14th-audit fix interpreted "stays with owner" as "the
owner scores it." This may be a misinterpretation: "stays with
owner" might mean "is not added to the opponent" while still
zeroing for scoring purposes.

**Severity assessment:** ambiguous. The code's current behavior is
internally consistent with one reading of K-08. Source H H-36.12 +
K-04 favor the stricter "loser scores 0 from melds." If the latter
is correct, this is a real scoring bug — the offender is being given
free points. **Recommend re-asking the user** which interpretation
applies. The user-flagged framing in the prompt ("Offender's melds
zeroed but NOT transferred") aligns with the strict H-36.12 + K-04
reading, NOT with the current code.

**Concrete impact:** in a Hokm-Bel scenario where the offender's team
declared a 50-meld + the bidder team Qaids them: code currently
gives offender team `(0 + 50) × 2 = 100 raw = 10 gp`. Strict H/K
reading: offender gets 0 gp. **Up to ~10-20 gp per round** can be
miscredited. Net.lua:2199-2208 has an explicit comment block citing
the 14th-audit fix as the reason for the current behavior, so a
reversal would need a deliberate decision.

### B4 — `R.ScoreRound`'s `outcome_kind=="fail"` branch ALSO keeps loser's melds
**Source:** same as B3 (H-36.12, K-04, K-08, K-09)
**Code:** `Rules.lua:791-808` — fail branch:
```
cardA = (oppTeam == "A") and handTotal or 0
cardB = (oppTeam == "B") and handTotal or 0
meldPoints.A = meldA      ← loser keeps their melds
meldPoints.B = meldB
```
Comment block 2790-2808 cites the same v0.4.3 alignment with the
qaid path. So the bug (if B3 is a bug) extends to ordinary failed
contracts. The fail-vs-Qaid distinction matters mainly for whether
projects are "in play" at the time of the cut (J-033 gives the
Tawzee = 16 rationale). **Same severity ambiguity as B3.**

### B5 — `bidder` field absent from contract → `R.CanBel` fallback
(Out of scope for X1 but caught while searching.) `Rules.lua:534` is
a backwards-compat fallback for contracts missing `contract.bidder`.
Not a Qaid bug; flagging for separate audit.

---

## Tests gaps / wrong fixtures

### G1 — No dedicated test for `N.HostResolveTakweesh`
**Where to look:** `tests/` directory contains 11 `.lua` files; grep
for `HostResolveTakweesh` returns ZERO matches.
**Effect:** the entire Qaid penalty code path (Net.lua:2131-2305) —
including the 14th-audit fix B3 (loser keeps own melds), the v0.5.21
div10 alignment, the ≥100-meld Belote cancellation — is unverified
by any unit test.
**Recommendation:** add `tests/test_takweesh.lua` covering:
1. Basic Hokm Qaid → 16 gp to caller
2. Basic Sun Qaid → 26 gp to caller
3. Sun + Bel + own sera → 60 gp to caller
4. Hokm + Belote(K+Q held by caller) → +2 gp on top
5. Carré-suppressed Belote
6. False Qaid (no illegal play found) → 16/26 to OFFENDER
7. The B3 contention: confirm offender's own meld scores or doesn't
   under your chosen interpretation.

### G2 — Existing fail-path test does NOT exercise meld preservation
**Where to look:** `tests/test_rules.lua:434-437` — the fail-branch
test uses `meldsByTeam = { A = {}, B = {} }` (no melds at all).
**Effect:** B4's behavior (loser keeps own melds in failed-contract
path) is NEVER tested. The Bel test at lines 555-559 also uses
empty melds.
**Recommendation:** add test where bidder team declares a 50-meld
AND fails. Verify the bidder team's `final.A > 0` (current code) vs
== 0 (strict source reading), and pin down which is correct.

### G3 — Multiplier scope under Qaid is also untested
**Effect:** H-36.13 explicit examples (52, 32, 60, 104) are not
asserted anywhere in `tests/test_rules.lua`. They appear correct
when traced manually (above), but no test catches a regression.

---

## Confidence

- **Qaid base value translation 130/162→26/16 game points:** HIGH
  confidence the code is correct. Tests at `test_rules.lua:434-436`
  and 487-488 explicitly assert the post-pipeline values.
- **Multiplier × Qaid-base × own-melds:** HIGH confidence the code
  matches Source H H-36.13's numerical examples. Manually traced
  6/6 examples matched.
- **Belote +20 multiplier-immunity:** HIGH confidence code-correct
  AND Saudi-correct (PDF K-27 + CLAUDE.md confirm; Source H does not
  contradict).
- **Carré multiplier scope (other / A in Sun):** HIGH confidence
  Carré flows through the meld pipeline and is multiplied. (Carré-A
  in Sun has its own R5 issue regarding the 200-vs-400 raw value and
  the Sun ×2 stack — covered separately.)
- **Pre-bid Tawzee Qaid (16):** HIGH confidence NOT MODELED.
  Documented design choice per glossary + audit_v0.7.1 / 45_takweesh.
- **B3 / B4 (offender's melds: keep vs zero):** **MEDIUM-LOW
  confidence in code's current "keep" interpretation.** The
  14th-audit fix block has clear comments justifying it from K-08;
  Source H H-36.12 + PDF K-04 favor the stricter "zero" reading. The
  word "forfeited" (K-04: "kept by neither side, just lost") is the
  hinge. RECOMMEND HUMAN ARBITRATION — this is a non-obvious rule
  reading where the code may be ~10-20 gp off per round in
  loser-has-meld scenarios.
- **Source-H H-36.13 vs CLAUDE.md (multiplier scope claim):**
  HIGH confidence they are COMPATIBLE, not divergent. The user's
  prompt framing "DIVERGES from CLAUDE.md's Belote +20
  multiplier-immune rule" is incorrect — H-36.13 lists sera / fifty
  / hundred / carré in its multiplier examples, NOT Belote. The
  rules cohabit.

---

## Files referenced

- `C:\CLAUDE\WHEREDNGN\Constants.lua` — lines 54-55 (handTotal),
  68-77 (multipliers), 91-103 (melds), 110-111 (Al-Kaboot)
- `C:\CLAUDE\WHEREDNGN\Rules.lua` — lines 636-906 (`R.ScoreRound`),
  791-808 (fail branch), 841-846 (multiplier ladder), 861-865
  (Belote post-mult)
- `C:\CLAUDE\WHEREDNGN\Net.lua` — lines 2075-2092
  (`N.LocalTakweesh` / `_OnTakweesh`), 2131-2305
  (`HostResolveTakweesh`), 2852+ (`HostResolveSWA` invalid path)
- `C:\CLAUDE\WHEREDNGN\tests\test_rules.lua` — lines 420-462 (fail /
  make tests), 469-489 (sweeps), 543-578 (tie-inversion), 668-699
  (multipliers)
- `C:\CLAUDE\WHEREDNGN\.swarm_findings\review_v0.10.0\_phase1_sources\source_H_bidding_penalty.md` —
  H-30.3-12, H-36.8-13, X-1, X-2
- `C:\CLAUDE\WHEREDNGN\.swarm_findings\review_v0.10.0\_phase1_sources\source_J_cut_deal_play.md` —
  J-024, J-025, J-033, J-034
- `C:\CLAUDE\WHEREDNGN\.swarm_findings\review_v0.10.0\_phase1_sources\source_K_pdf_basic_rules.md` —
  K-02, K-03, K-04, K-08, K-09, K-12, K-14, K-27
- `C:\CLAUDE\WHEREDNGN\docs\strategy\_transcripts\40_cut_deal_rules_extracted.md` —
  lines 187-188 (stale doc reference, B2)
- `C:\CLAUDE\WHEREDNGN\.swarm_findings\audit_v0.7.1\45_takweesh_flow.md` —
  prior audit confirming pre-bid Qaid is intentionally unimplemented
