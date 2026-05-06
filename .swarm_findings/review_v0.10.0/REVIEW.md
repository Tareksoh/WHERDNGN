# REVIEW v0.10.0 — Source-of-Truth Audit

**Scope:** Triangulate Saudi Baloot rules across three sources — 38 YouTube
video transcripts, 8 PDFs (7 from Downloads + 1 pasted Google Doc), and the
WHEREDNGN code/docs as of `cc8a775` (v0.9.2). Identify
misunderstandings, misimplementations, missing features, and
doc drift before further rule wiring.

**Methodology:** 24 agents in 3 waves —
- **Wave 1 (12 agents)** extracted rules per natural source-scope into
  `_phase1_sources/source_{A..L}_*.md`.
- **Wave 2A (7 reaudits)** resolved cross-cluster conflicts into
  `_phase2_xref/reaudit_R{1..7}_*.md`.
- **Wave 2B (5 xrefs)** cross-checked code areas not directly conflict-
  driven into `_phase2_xref/xref_X{1..5}_*.md`.

User-flagged focus areas (SWA, scoring, bot decisions) get **[FOCUS]** tags
throughout.

---

## TL;DR

Three sources mostly agree on Saudi rules; three real **scoring bugs**
were silently mis-attributed to "framing" or never caught. The biggest
findings:

1. **🚨 Carré-A in Hokm is silently dropped entirely** — `R.DetectMelds`
   has no `else` branch for Ace+Hokm. Cascades into bidder-majority
   threshold, meld-comparison, and Belote-cancellation paths.
2. **🚨 Carré-A in Sun is under-scored exactly 2×** (40 nq vs 80 nq) — a
   prior "Gemini scoring audit catch" 400→200 was wrong.
3. **🚨 Touching-honors K-signal is INVERTED in code** — speaker says
   "K-played → only K, Q/J elsewhere"; code pins Q to that seat. v0.9.2
   #12 made this dead-code-wrong into reachable-mispredicting-wrong.
4. **🚨 Bel-100 v0.9.2 #45 over-corrected** — three sources unanimous on
   score-split (caller≤100 AND opposite≥101); code now anchors on
   bidder/defender role, breaks the bidder-trailing edge case.
5. **Touching-honors trust-asymmetry not enforced** on writer or reader —
   bot weights opponents' inferred-pin signals identically to its own.
6. **SWA mechanism is structurally correct but the 5-second auto-approve
   timer is invented** — not a Saudi rule. `CLAUDE.md` line 41 mis-cites.

The user's hunch on **scoring being structurally wrong is fully
confirmed** (R5, X5). The user's hunch on **SWA being wrong** is
PARTIALLY confirmed — naming is correct, mechanism mostly correct, but
the auto-approve timer authenticity claim is wrong and partner-
adversarial validation may over-reject Hokm two-hand SWA.

The user's hunch on **bot decisions being wrong** is confirmed in
multiple specific spots: Bel-100 (R1), Faranka exception "#3" missing
bidder gate (X3), F-16 violated (X3), Bargiya FN persists (R4), AKA
receiver-relief possibly dead code (X2/B1), Hokm-needs-Ace half-
implemented (X4/L07), Sun seat-1 must-lead A+T not implemented
(X4/L08).

---

## Triage table

| Sev | ID | Issue | Cite |
|---|---|---|---|
| 🚨 H | R5  | Carré-A in Sun 200→400 raw (under-scored 2×) | `_phase2_xref/reaudit_R5_*.md` |
| 🚨 H | X5  | Carré-A in Hokm meld DROPPED ENTIRELY (cascades to belote-cancel + majority) | `xref_X5_*.md` Bug 1 |
| 🚨 H | R6  | Touching-honors K → only-K (code says K → has Q — INVERTED, now reachable) | `reaudit_R6_*.md` |
| 🚨 H | R6+X4 | Trust-asymmetry NOT enforced (writer Bot.lua:471-487 + reader BotMaster.lua:453-472) | `reaudit_R6_*.md`, `xref_X4_*.md` |
| 🚨 H | R1  | Bel-100 over-corrected v0.9.2 #45; needs `caller≤100 AND opposite≥101` | `reaudit_R1_*.md` |
| H    | X3  | Hokm Faranka Exception "#3" no bidder-team gate (same class as v0.9.2 #49) | `xref_X3_*.md` |
| H    | X3  | F-16 violated: code accepts T-as-cover when K absent | `xref_X3_*.md` |
| H    | X4  | L07 Hokm-needs-Ace half-implemented (only count==3 branch) | `xref_X4_*.md` |
| H    | R2  | Sun escalation tests `test_rules.lua:562-577` codify wrong invariants (×6, ×8) | `reaudit_R2_*.md` |
| M    | X1  | **HUMAN ARBITRATION**: offender melds on Qaid — zeroed/forfeited vs keep-with-owner | `xref_X1_*.md` B3+B4 |
| M    | X2  | AKA receiver-relief at Bot.lua:2427-2438 may be dead code (R.IsLegalPlay ignores akaCalled) | `xref_X2_*.md` B1 |
| M    | X2  | False AKA = Qaid (J-069) NOT implemented | `xref_X2_*.md` B2 |
| M    | X2  | AKA-on-10 trick-locking NOT implemented | `xref_X2_*.md` B5 |
| M    | X3  | Sun Faranka 5-factor — code is AND-gated trigger, not weighted accumulator | `xref_X3_*.md` |
| M    | X3  | Code Faranka Exception "#4" over-tight (`bidder==seat`; should be bidder-team) | `xref_X3_*.md` |
| M    | R4  | Bargiya canonical FN: محشور first-trick A-only → bargiya_hint instead of bargiya | `reaudit_R4_*.md` |
| M    | X4  | Sun seat-1 must-lead A+T NOT implemented (Pro-2 L08) | `xref_X4_*.md` |
| M    | R2  | Defense-in-depth: Bot.PickTriple/Four/Gahwa lack explicit Sun guards | `reaudit_R2_*.md` |
| M    | X1  | Pre-bid Tawzee Qaid (= 16) NOT modeled (gap, by design) | `xref_X1_*.md` B1 |
| L    | R3  | SWA 5-sec auto-approve timer is NOT a Saudi rule (CLAUDE.md doc fix) | `reaudit_R3_*.md` |
| L    | R3  | SWA partner-adversarial validation may over-reject Hokm two-hand SWA | `reaudit_R3_*.md` |
| L    | X2  | Doubled-contract conservatism missing in Bot.PickAKA | `xref_X2_*.md` B3 |
| L    | X4  | Sessional 7-8-9 same-suit Kasho NOT implemented | `xref_X4_*.md` |
| L    | X4  | Self-trigger override (kasho-hand + J/T/A → Hokm) NOT implemented | `xref_X4_*.md` |
| L    | X4  | Pro-2 L09 seat-1/2 Sun deferral NOT implemented | `xref_X4_*.md` |
| L    | R7  | Decision-trees.md: Mathlooth "K-tripled" → "J-tripled" doc fix | `reaudit_R7_*.md` |
| L    | R7  | glossary.md transliteration aliases (Burqia/Bargiya, etc.) | `reaudit_R7_*.md` |
| —    | doc | saudi-rules.md Q3 reconciliation incorrect (about Carré-A in Sun) | R5 |
| —    | doc | saudi-rules.md Q4 still says "possible mismatch" (resolved at v0.5.6+) | rounding |
| —    | doc | CLAUDE.md "Carré-J trump-implicit" remark — code is correct, docs need cleanup | X5 |

---

## CRITICAL/HIGH bugs — recommended fix order

### 1. R5 + X5: Scoring bugs (Carré-A in both contracts) **[FOCUS]**

**R5 — Carré-A in Sun under-scored 2×**
- `Constants.lua:95` `K.MELD_CARRE_A_SUN = 200` → should be **400**.
- Math: video #43's "Sun ÷5" framing means 400/5=80 game points. Code's
  `200 × Sun×2 mult / div10` yields 40. Off by 2×.
- A prior fix changed 400→200 thinking it was double-counting; the
  original 400 was correct, the "fix" was a bug.
- `saudi-rules.md` Q3 reconciliation needs rewriting.

**X5 — Carré-A in Hokm silently dropped**
- `Rules.lua:240-242` has no `else` branch. When `rank=="A" AND
  isSun==false`, `value` stays `nil` and the meld is never emitted.
- Per video #32 line 245 + #38 line 61, Carré-A in Hokm = 100
  (treated like Carré-T/K/Q).
- Cascading impact:
  - Missing 100-meld value
  - Bidder strict-majority threshold check sees wrong total
  - `R.CompareMelds` winner-takes-all path gets wrong winner
  - **Belote-cancellation logic leaves Belote uncancelled** when the
    holder's missing 100-meld would have triggered the v0.9.0 M5 rule
    → silent **+20 over-scoring** in those rounds

**Fix scope:** ~3 lines in `Rules.lua` (add the Hokm Carré-A branch),
~1 line in `Constants.lua` (200→400), regression tests for both.

### 2. R6: Touching-honors K-signal inversion **[FOCUS]**

- `Bot.lua:491-492`: when follower plays K after partner's bare-A,
  code sets `entry.nextDown = "Q"` (interpretation: "they have Q").
- Source #05 (lines 783-884): K-played means **K is singleton — Q and
  J are NOT in their hand** ("Can he have Q or J? No, impossible —
  he would have played those instead").
- Reader at `BotMaster.lua:455-462` then bumps `desire["Q"+suit]=60`
  for that seat — pinning Q to the seat that explicitly does NOT have
  Q.
- Pre-v0.9.2 #12, this was dead code so the inversion was harmless.
  Post-fix, it's reachable and **actively mispredicting**.
- **Trust-asymmetry**: writer + reader apply uniformly to all seats.
  Source #05 explicit: partner signals trustworthy, opp signals can be
  deceptive. Mis-pin gets weaponized by opponents.

**Fix scope:**
- Bot.lua:491-492 — replace `entry.nextDown = "Q"` with
  `entry.singleton = "K"` (or equivalent semantics) and rework reader
  to clear Q/J desires.
- Add team-gate at writer (`Bot.lua:471-487`) AND reader
  (`BotMaster.lua:453-472`) — only apply pins for partner-team seats;
  skip for opponents (trust-asymmetry).
- Extend `9 → broke` (currently only 7/8).

### 3. R1: Bel-100 over-correction (revert v0.9.2 #45)

- v0.9.2 changed `R.CanBel` from `mine < 100` (incomplete — missing
  the dual-team check) to `bidder ≥ 101 AND defender ≤ 100`
  (over-corrected — anchored on role).
- Three sources unanimous on **score-split, role-irrelevant** rule:
  `caller.cum ≤ 100 AND opposite.cum ≥ 101`.
- Edge case the v0.9.2 fix breaks: bidder team is trailing (Sun bid
  by behind team to catch up).
- **Fix scope:**
  - `Rules.lua:489+` collapse to score-split predicate; drop
    `contract.bidder` consultation
  - `Net.lua:68+` simplify `_SunBelAllowed` to query trailing team
  - `tests/test_rules.lua` Section N — flip 1 expected value, add 2
    new fixtures for bidder-trailing case
  - Grep `Bot.PickDouble` for role-based form

### 4. X3: Hokm Faranka Exception "#3" missing bidder-team gate

- v0.9.2 #49 fixed Exception "#2" with `onBidderTeam` gate.
- Code's Exception "#3" (J-dead, hold 9, `Bot.lua:2795-2804`) has the
  **same class of bug** — fires regardless of contract ownership →
  bot Faranka's into opp's Hokm contract on J-dead+9-only hands.
- Same fix pattern: add `and onBidderTeam` to the trigger.
- Code's Exception "#4" is **over-tight** (`contract.bidder == seat`
  strict; Source C says **bidder-team is sufficient** — partner of
  bidder also qualifies).

### 5. X3: F-16 violated (no K → don't Faranka)

- `Bot.lua` Hokm Faranka logic accepts T-as-cover when K absent.
- Source C F-16: explicit anti-rule "don't Faranka if you don't hold
  the K".
- Quick fix: gate Faranka triggers on holding K-of-trump.

### 6. X4/L07: Hokm-needs-Ace half-implemented

- `Bot.lua:740-757` `hokmMinShape` enforces `hasSideAce` only when
  `count == 3`; the `count >= 4` branch passes without any Ace check.
- Source L (Pro-2 L07) + Source H both say Hokm bid should require
  an Ace (defense rule against Sun-overcall / Kaboot / 4-Hundred).
- **Note**: Source H clarifies this is STRATEGY, not a hard rule.
  Treatment: gate at Saudi-Master/Fzloky tiers; permissive at Basic/
  Advanced.

### 7. R2: Sun escalation tests codify wrong invariant

- `tests/test_rules.lua:562-577` and `:696` actively exercise
  `Sun×Triple=×6` and `Sun×Four=×8`.
- These multipliers are forbidden by canonical rule (Sun = Bel-only
  chain, all 3 sources agree).
- **No live bug** — phase machine prevents it in practice — but tests
  ASSERT the invariant violation.
- Fix: replace with assertions that multiplier collapses to ×Bel
  regardless of stale `tripled/foured` flags.
- Consider adding defensive `if contract.type == K.BID_SUN` guards
  at `Bot.PickTriple/Four/Gahwa` for defense-in-depth.

---

## MEDIUM bugs

| # | Location | Issue | Source |
|---|---|---|---|
| M1 | `xref_X1_*.md` B3+B4 | Offender melds on Qaid: code keeps with offender, sources say zeroed/forfeited | **Human arbitration** |
| M2 | `xref_X2_*.md` B1 | AKA receiver-relief at Bot.lua:2427-2438 may be dead code (R.IsLegalPlay doesn't consult akaCalled) | Trace-verify, then fix or remove |
| M3 | `xref_X2_*.md` B2 | False AKA = Qaid (J-069) NOT implemented (`N._OnAKA:2458` explicit "soft signal" comment) | J-069 / Phase1-J |
| M4 | `xref_X2_*.md` B5 | AKA-on-10 trick-locking NOT implemented (R.CurrentTrickWinner is purely highest-rank) | J-066/J-067 |
| M5 | `xref_X3_*.md` | Sun Faranka 5-factor: code is single AND-gated trigger, not weighted accumulator | Source C |
| M6 | `xref_X3_*.md` | Code Faranka Exception "#4" over-tight; should be bidder-team not bidder-only | Source C |
| M7 | `reaudit_R4_*.md` | Bargiya canonical FN: محشور-sender first-trick A-only → bargiya_hint (score 1), loses to incidental want (score 2) | Video #14 @ 00:11:48 |
| M8 | `xref_X4_*.md` | Sun seat-1 must-lead A+T NOT implemented (`pickLead` falls through to "Sun shortest-suit lead" — opposite of L08 mandate) | Pro-2 L08 |
| M9 | `xref_X1_*.md` B1 | Pre-bid Tawzee Qaid (= 16) NOT modeled — by-design gap (N.LocalTakweesh / N.HostResolveTakweesh gate on PHASE_PLAY) | H-30.6/J-033 |
| M10 | `reaudit_R2_*.md` | Bot.PickTriple/Four/Gahwa lack explicit `if contract.type == K.BID_SUN then return false end` | Defense-in-depth |

---

## LOW / minor

| # | Location | Fix |
|---|---|---|
| L1 | `reaudit_R3_*.md` | CLAUDE.md line 41 — clarify that 5-sec SWA auto-approve is addon UX, not Saudi rule |
| L2 | `reaudit_R3_*.md` | R.IsValidSWA partner-adversarial may over-reject Hokm two-hand SWA — separate audit recommended |
| L3 | `xref_X2_*.md` B3 | Bot.PickAKA add doubled-contract conservatism (inspect `S.s.contract.mult`) |
| L4 | `xref_X4_*.md` | Sessional 7-8-9 same-suit Kasho — opt-in flag |
| L5 | `xref_X4_*.md` | Self-trigger override (kasho-hand + ground J/T/A → Hokm forced) |
| L6 | `xref_X4_*.md` | Pro-2 L09 seat-1/2 Sun deferral when bid-card supports without 100-meld |

---

## Doc drift (no code change needed)

| File | Issue | Source |
|---|---|---|
| `saudi-rules.md` Q3 | Reconciliation reasoning incorrect — assumes 200×2=400 effective, but code yields 40 game points (off by 2×) | R5 |
| `saudi-rules.md` Q4 | "Possible mismatch" on rounding — resolved at v0.5.6 with `(x+5)/10` | Verified live |
| `saudi-rules.md` reverse-Kaboot | Single-source flag can be downgraded — corroborated by both #15 + #16 | Source G |
| `saudi-rules.md` reverse-Kaboot | Add: most rule-sets require lead-card = Ace (not just bidder-team) | Source G |
| `decision-trees.md` Section 6 | Mathlooth "K-tripled" → "J-tripled" (شايب=J top under Sun A>T>J) | R7 |
| `CLAUDE.md` line 41 | SWA 5-sec timer wording — currently presents as Saudi rule, is addon UX | R3 |
| `CLAUDE.md` Carré-J | "Trump-implicit" remark contradicts videos; code correct (Carré-J = 100 always) | X5 |
| `glossary.md` | Add Burqia↔Bargiya transliteration alias note (same word برقيّة) | R7 |
| `glossary.md` | Mathlooth (مثلوث) entry expansion + J-tripled clarification | R7 |
| (analyst) | Source A's `التنفيذ` listing was inheriting YouTube ASR error; correct root is ن-ف-ر (تنفير) | R7 |

---

## Missing features (catalogued, not yet wired)

Each of these is referenced in at least one source but has no code
implementation. Listed in rough leverage order.

| MF | Description | Source(s) |
|---|---|---|
| MF-1 | 12-card project-elimination tables (highest leverage for ISMCTS) | PDF 04 / Source L L10-L18 |
| MF-2 | 6-factor opp-Tanfeer framework with bidder-asymmetric weighting | Source B (#19) |
| MF-3 | 70/25/5 receiver prior + 90% confirmation + 100% small-to-big | Sources A, B (videos #09, #10) |
| MF-4 | 5-tier confidence buckets {100/95/90/50-50/10} (not 3-tier) | Source D (#13) |
| MF-5 | Sun Faranka 5-factor weighted accumulator | Source C (#06) |
| MF-6 | Sun seat-1 mandatory backed-A+T probe lead | Pro-2 L08 |
| MF-7 | False AKA = Qaid against caller | J-069 |
| MF-8 | AKA-on-10 trick-locking + must-trump-ruff exemption | J-066/J-067 |
| MF-9 | Hokm Faranka exceptions F-24 (Type-3 cabotage), F-26 (J-preserve), F-28 (9-mardoofa while J live) | Source C |
| MF-10 | Magnify (Takbeer) + Tasgheer signal-reading (play-direction signals) | Source E (#21, #22, #23) |
| MF-11 | Saudi-Master signature moves: J/T sacrifice for deception, Hokm Q-deception | Source E (#08, #20) |
| MF-12 | Strategy/tactic 2-layer model architecture | Source E (#07) |
| MF-13 | Defender single-trick = Kaboot break recognition | Sources E, G |
| MF-14 | Pre-bid Tawzee Qaid (= 16) — phase=PHASE_DEAL etc. | H-30.6/J-033 |
| MF-15 | Pro-2 L09 seat-1/2 Sun deferral when bid-card supports w/o 100-meld | Pro-2 L09 |
| MF-16 | Sessional 7-8-9 same-suit Kasho variant | Source J |
| MF-17 | Self-trigger override: kasho-hand + ground J/T/A → buy Hokm | Source H/J |
| MF-18 | Reverse-Kaboot Ace-lead requirement (most rule-sets require A) | Source G |
| MF-19 | Defender sandbag-Qaid vs bidder delay-Qaid endgame timing | Source G |
| MF-20 | Strategic break-Kaboot-to-Double tactic (Sun-double 52 > Sun-Kaboot 44) | Source G |

---

## Confirmed correct (positive verifications)

These were checked and the code is consistent with sources. Listed for
completeness so future audits don't re-verify them.

- ✅ Score rounding `(x+5)/10` applied at `Rules.lua:870-871` matches
  video #43's "5 rounds UP" worked examples (65→70, 66→70, 67→70,
  64→60, 62→60, 55→60, 51→50, 74→70). v0.5.6 fix verified live.
- ✅ Multiplier scope on Qaid + own-melds matches Source H H-36.13's
  six worked examples exactly (Net.lua:2238).
- ✅ Belote +20 multiplier-immune (Rules.lua:861-865, applied AFTER
  mult).
- ✅ Sun escalation truncated to Bel-only via phase machine
  (State.lua:1085-1087, Net.lua:902-915, Bot.PickDouble:3372).
- ✅ Hokm-only AKA gate (UI/sender/receiver/state defence-in-depth).
- ✅ Implicit AKA via bare-A lead receiver-side at Bot.lua:2396-2426.
- ✅ AKA preconditions (non-trump, largest-remaining, lead-only,
  non-Ace) gated in Bot.PickAKA.
- ✅ AKA late-game conservatism wired (half of G18-10).
- ✅ Bidder strict-majority enforced at Rules.lua:750.
- ✅ Belote team-level cancellation (v0.9.0 M5) at Rules.lua:713-721.
- ✅ Sun Belote (ملكي) correctly OMITTED — sources I, L unanimous.
- ✅ Carré-J = 100 always (CLAUDE.md remark is what's wrong).
- ✅ Quinte K.MELD_SEQ5=100 used at Rules.lua:218.
- ✅ سيكل (9-8-7) detected as plain SEQ3=20 via K.RANK_INDEX.
- ✅ F-14 transcription slip — code reads CORRECTED intent (last-seat
  + opp-winning falls through to winners-selection, does NOT Faranka).
- ✅ F-17 (≥3 cards anti-Faranka): match.
- ✅ F-18 (Hokm Faranka default-NO): match.
- ✅ Reverse-Kaboot +88 raw — corroborated across both #15 and #16
  (single-source flag can be downgraded).
- ✅ Reverse-Kaboot Sun-only — confirmed (does NOT exist in Hokm).
- ✅ Code's SWA naming is correct (verdict A from R3) — `K.MSG_SWA`
  etc. attached to the right end-game-claim referent.
- ✅ Code naming for escalation (MULT_TRIPLE, PickTriple) doesn't
  collide with the play-signal Takbeer (which is the videos' usage).
- ✅ Code's `bargiya` standardization is canonical; Source A's "burqia"
  is just a different romanization of the same word برقيّة.

---

## Human arbitration required

Only one item needs the user to choose between two reasonable rule
readings:

### M1: Offender's melds on Qaid

- **Current code**: offender keeps their own melds (`Net.lua:2207-2208`,
  `Rules.lua:807-808` fail branch).
- **Source H H-36.12**: "zeroed/forfeited"
- **PDF K-04**: "the buyer's meld is forfeited (kept by neither side,
  just lost)"
- **PDF K-08** (which the 14th-audit fix cited as basis for current
  behavior): "stays with owner" — ambiguous interpretation (does
  "stays" mean "owner scores it" or "stays in their pile but doesn't
  count")?
- **Concrete impact**: ~10-20 game points / round when it triggers.
- **Recommendation**: pick a reading; document the choice in
  `saudi-rules.md`; add fixture coverage either way.

---

## Recommended fix priority

If you want a single-sprint fix list:

**Sprint 1 — silent scoring bugs (critical):**
1. R5: Carré-A in Sun 200→400 in Constants.lua + saudi-rules.md Q3
2. X5: Carré-A in Hokm — add `else` branch in R.DetectMelds:240-242
3. M1: Resolve Qaid-offender-melds question; align code or doc

**Sprint 2 — bot-decision corrections:**
4. R1: Bel-100 score-split form (revert v0.9.2 #45 to new symmetric
   form `mine ≤ 100 AND otherCum ≥ 101`)
5. R6: Touching-honors K-signal inversion + trust-asymmetry team-gate
   (writer + reader)
6. X3: Faranka Exception "#3" bidder-gate; F-16 K-required gate;
   Exception "#4" relax to bidder-team
7. X4/L07: Hokm-needs-Ace `count >= 4` branch

**Sprint 3 — invariant defense + tests:**
8. R2: Replace test_rules.lua:562-577 + :696 Sun-Triple/Four
   assertions with collapse-to-Bel assertions
9. R2: Defensive Sun-guards in Bot.PickTriple/Four/Gahwa
10. M2: Trace-verify or remove dead AKA receiver-relief branch

**Sprint 4 — missing features (prioritize after backlog discussion):**
- MF-1 (project-elimination tables, highest sampling leverage)
- MF-3 (Tahreeb 70/25/5 prior, easy win)
- MF-7/MF-8 (false-AKA-Qaid + AKA-on-10 — completeness)

**Doc drift sweep**: can be done independently in any sprint.

---

## Cite trail map

```
.swarm_findings/review_v0.10.0/
├── REVIEW.md                              ← this file
├── _phase1_sources/                       (12 source extracts, ~510 KB total)
│   ├── source_A_tahreeb_cluster1.md       videos 01,02,03,09,10
│   ├── source_B_bargiya_discover.md       videos 14, 19
│   ├── source_C_faranka.md                videos 04, 06
│   ├── source_D_predictions.md            videos 05, 13
│   ├── source_E_strategy_magnify.md       videos 07,08,20,21,22,23
│   ├── source_F_bel_tanfeer.md            videos 11, 12, 17
│   ├── source_G_kaboot_aka.md             videos 15, 16, 18
│   ├── source_H_bidding_penalty.md        videos 27,28,29,30,34,36
│   ├── source_I_melds_swa_scoring.md      videos 32, 35, 38, 43
│   ├── source_J_cut_deal_play.md          videos 37,39,40,41,42,44
│   ├── source_K_pdf_basic_rules.md        PDFs 01, 02, 06
│   └── source_L_pdf_secrets_doubling.md   PDFs 03, 03b, 04, 05, 07
└── _phase2_xref/                          (12 cross-reference reports)
    ├── reaudit_R1_bel100.md               score-split rule resolution
    ├── reaudit_R2_sun_escalation.md       chain truncation verdict
    ├── reaudit_R3_swa.md                  naming + timer authenticity
    ├── reaudit_R4_bargiya_tahreeb.md      multi-axis taxonomy resolved
    ├── reaudit_R5_carre_a_sun.md          200→400 scoring bug
    ├── reaudit_R6_touching_honors.md      K-signal inversion bug
    ├── reaudit_R7_glossary.md             Takbeer/Bargiya/Mathlooth/Tanfeer
    ├── xref_X1_penalty_multiplier.md      Qaid + multiplier scope
    ├── xref_X2_aka.md                     AKA mechanism completeness
    ├── xref_X3_faranka.md                 Hokm + Sun Faranka rules
    ├── xref_X4_pro2_deal.md               Pro-2 leads + cut/deal
    └── xref_X5_meld_coverage.md           Carré-A in Hokm + meld completeness
```

---

## Methodology notes

**Source-of-truth precedence** used during conflict resolution:
1. **PDFs** (authoritative, edited rule docs) > YouTube videos
2. **Multi-source agreement** (3+ corroborating) > single-source
3. **Verbatim Arabic** (with tight ≤15-word quotes) > paraphrase
4. **Worked examples** (numerical) > abstract framing
5. **Code behavior** trumps docs when checking implementation
   correctness (but code can still be wrong vs source)

**Audit anti-patterns observed in this pass:**
- **Frame-projection bias**: Phase 1 audit prose imposed
  bidder/defender frame on a score-frame rule (caused R1 v0.9.2 #45
  error). Mitigation: always quote the verbatim Arabic before drawing
  inferences.
- **Math-equivalence false-positive**: `saudi-rules.md` Q3
  reconciliation declared "no change needed" because 200×2=400 looks
  right; missed that the code's pipeline yields 40 game points not 80
  (R5 spinoff X5 cascade). Mitigation: trace numerical examples
  through to game-points outputs, not just intermediate raws.
- **Reachable-but-wrong** vs **dead-code-wrong**: v0.9.2 #12
  legitimately fixed a NameError that activated the topTouchSignal
  WRITE branch. But the activated branch's K-signal interpretation
  was wrong all along — the bug shifted from latent to active. Future
  fixes that activate dead code should re-verify the activated
  semantics.

---

*Audit complete. 24 reports, 12 sources triangulated, ~50 distinct
findings. Ready for fix-prioritization discussion.*
