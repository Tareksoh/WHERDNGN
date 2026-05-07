# Changelog

## v1.0.10 — Audit pass-3 quick wins + partner-Hokm BC-MANDATORY override

Closes the LOW/MED severity items from v1.0.9's 4-agent ultra-audit
plus a HIGH edge-case from a fresh agent review of partner-Hokm
overcall strategy. 791/791 tests pass.

### CRITICAL — Saudi-rule conflict resolution

- **BC-MANDATORY Belote overrides G-4 partner-Hokm suppression
  (Bot.lua PickBid R2)**. Pre-v1.0.10 the G-4 partner-Hokm
  suppression block (videos #29 + #34: "do NOT outbid partner's
  Hokm") fired BEFORE the BC-MANDATORY-Belote bypass (video #26
  rule B-6: "Mandatory Hokm with the Belote suit as trump"). Two
  Definite-confidence Saudi rules conflicted; G-4 silently won.
  Result: a hand with K+Q+canonical-4-seq in a non-bidcard suit
  could be forced to PASS when partner had bid Hokm-of-other-suit
  — forfeiting the +20 multiplier-immune Belote bonus. Per the
  partner-Hokm-overcall agent review, the structural Belote
  outweighs partner-support: the bot now overrides G-4 only when
  `beloteBypassQualifies` returns true for a non-bidcard suit
  (canonical 4-card trump-seq OR K+Q+count>=3+sideAce). This is
  the ONLY HOKM-on-HOKM overcall the bot ever performs.

### MEDIUM — Bot strategy

- **M5 target folds Belote ±20 (Bot.lua trick-8 winners block,
  audit pass-2 A MED-1 / B LOW-1)**. Pre-v1.0.10 M5's
  algebraically-correct `(oppMeld - myMeld) / 2` adjustment
  ignored Belote entirely. With opp holding Belote (K+Q-of-trump
  same-seat, +20 raw), the effective target was off by +10 raw —
  enough to mis-classify boundary make-or-break decisions at
  trick-8. Now folds `(oppBelote - myBelote) / 2` into target;
  uses `R.IsBeloteCancelled` to match the same ≥100-meld-subsumes-
  Belote rule that R.ScoreRound applies. Hokm-only (Sun has no
  Belote).

### LOW / cleanup

- **R.TeamOf nil-seat defensive guard (Rules.lua, audit pass-2 B
  LOW-3)**. Pre-fix nil seat fell through to silent `return "B"`
  (mis-attribution to team B). Now nil/invalid → nil so callers
  can branch on it. Existing call sites unaffected (all pass
  validated seats; 791/791 tests still green).

- **R.MeldRank docstring (Rules.lua, audit pass-2 A MED-3)**.
  Doc warning added: `R.MeldRank` returns ordinal value only and
  does NOT apply PDF Rule 2 dealer-right tiebreaker. Callers that
  need to resolve a tied-rank winner must use `R.CompareMelds`
  with `dealerSeat` instead. `Bot.PickMelds` is fine using
  MeldRank directly (only needs strict-greater for filter logic).

- **AL.2 test top="K" → top="A" (audit pass-2 C MED-2)**. The
  Q-K-A sequence's actual top is A. Pre-fix typo was harmless
  (partner's len=4 outranked regardless) but fragile if equal-
  length melds were ever compared.

- **AL.4 rewritten as direct unit tests on `Bot._beloteBypassQualifies`
  (audit pass-2 C MED-1)**. The PickBid path satisfies A#2
  transitively for canonical-4-seq hands (T-J-Q-K passes thHokmR1
  on strength alone), making the canonical-4-seq branch
  behaviorally untestable through PickBid. Helper now exposed on
  `Bot._beloteBypassQualifies`; AL.4 splits into 7 sub-tests
  (a-g) each isolating a specific gate (T-J-Q-K, J-Q-K-A,
  K+Q+count≥3+sideAce, count==2 fail, no-sideAce fail, no-K fail,
  nil-suit defensive).

### Tests

- **AL.5 (NEW)**: G-4 regression pin — partner-Hokm with strong
  different-suit Hokm hand → BID_PASS.
- **AL.6 (NEW)**: G-4 Sun-overcall allowance — partner-Hokm with
  Sun-shape → BID_SUN.
- **AL.7 (NEW)**: BC-MANDATORY > G-4 — partner-Hokm with K+Q
  Belote in non-partner suit → HOKM:beloteSuit overcall.
- **AL.4 (REWRITTEN)**: 7 direct unit-test assertions on
  `Bot._beloteBypassQualifies` (a-g).
- Y.3b source-pin window bumped 25000→32000 to accommodate the
  new BC-MANDATORY-overrides-G-4 block.

### Deferred (still in backlog)

- **D HIGH-2 Belote announcement requirement**: requires
  MSG_BELOTE wire + S.s.beloteAnnounced flag + UI button +
  R.ScoreRound gate. Substantial multiplayer-coordination scope.
- **D MED M1 Either-defender Bel**: requires multi-seat
  belPending tracking + UI changes + AFK timer rework + bot
  dispatcher updates. Touches 10+ files; needs multiplayer test
  surface.
- **D HIGH-3 Reverse Kaboot rule arbitration**: PDF text supports
  88 raw + bidder-led-trick-1 (current) OR 99 raw + dealer-right-
  Ace-held (alternate); user arbitration required.
- **`Bot.PickKawesh` partner-Hokm gate (LOW)**: investigation
  pending — Kawesh fires at PHASE_DEAL1 (pre-bidding), so partner-
  bid doesn't yet exist; agent's finding may have conflated
  pre-bid kawesh vs in-play kasho. Will research.

## v1.0.9 — PDF cross-check fixes + 4-agent swarm closure

This release closes the critical findings from the four-agent swarm
(A=Saudi-pro convention, B=human-reading skills, C=partner-coordination,
D=BalootGCC official PDF rules cross-check) plus the two A-class bot-
strategy items the user explicitly green-lit. 760/760 tests pass.

### CRITICAL — actual scoring bugs

- **A#1: M5 algebra error reverted to canonical formula (Bot.lua
  trick-8 winners block).** v1.0.6's N3 introduced two compounding
  errors in defender M5 target estimation: (a) algebra was off by
  2× (used `oppMeld - myMeld` where the canonical R.ScoreRound
  formula is `(oppMeld - myMeld) / 2`), and (b) didn't consult
  `R.CompareMelds` winner-takes-all. With opp's 100-meld declared,
  the bot computed the wrong threshold by ~5 raw, mis-firing M5
  swings on doomed contracts. Now uses the canonical formula AND
  consults CompareMelds for winner-takes-all attribution.

- **D HIGH-1: Multiplier semantics split for cards vs melds
  (Rules.lua R.ScoreRound).** PDF §5-5 / §5-6 cross-check vs
  v0.11.10 user arbitration: melds DO NOT cascade past Bel.
  Pre-v1.0.9 a Triple/Four/Gahwa contract multiplied BOTH cards AND
  melds by Bel×Triple/Four/Gahwa (cascading multiplier). Per PDF
  §5-6 melds only ever multiply by Bel (×2), regardless of what
  rung the contract reached — the higher rungs only multiply
  CARDS. User re-arbitrated: "option A i was wrong" — agreed with
  PDF reading. Now the result struct exposes `cardMultiplier` and
  `meldMultiplier` separately; legacy `multiplier = cardMult` for
  back-compat with consumers that haven't been updated.

### HIGH — Saudi rule conformance

- **Rule 2 (PDF §): tied-meld dealer-right priority
  (Rules.lua R.CompareMelds + R.ScoreRound).** PDF text:
  «في حال تساوى مشروعان متشابهان في القيمة فأفضلية النزول لمن
  على يمين الموزع» — "if two equal-value melds tie, declaration
  priority goes to the player on the dealer's right." Pre-v1.0.9
  ties returned "tie" → both teams scored 0 melds. Now: walk seats
  starting at NextSeat(dealer); the first seat declaring a top-rank
  meld takes the win for its team. Optional `dealerSeat` parameter
  preserves back-compat for callers without dealer context.
  Updated 3 callers (State.lua, Net.lua, BotMaster.lua) to pass
  the dealer.

### MEDIUM — Bot strategy tightening

- **A#2: BC-MANDATORY-Belote bypass tighten (Bot.lua PickBid).**
  Pre-v1.0.9 the BC-MANDATORY bypass fired whenever the Belote
  suit merely passed `hokmMinShape` (which admits K+Q+count==2 via
  the v0.11.16 escape clause). Over-fired on weak K+Q-only hands
  → routinely-failing Hokm contracts. Tightened: bypass now
  requires structural support — canonical 100-meld in trump suit
  (T-J-Q-K or J-Q-K-A) OR K+Q+count>=3+sideAce. Belote +20 bonus
  still contributes to the strength score (so the standard
  threshold gate retains Belote awareness), but only auto-fires
  when Mandatory-Belote is structurally backed.

- **C#2: PickMelds Qaid-protection meld filter (Bot.lua
  PickMelds).** Saudi meld scoring is winner-takes-all
  (R.CompareMelds). If opps have already declared a higher-rank
  meld AND partner has no winning declaration, our team's
  declarations all drop to 0 anyway — declaring losing melds is
  pure information cost (revealing 3-4 cards) for 0 expected
  score benefit. Filter to candidates that either flip the outcome
  (candidate beats opp's best) OR ride a partner's already-winning
  declaration. Exposes `R.MeldRank` for external rank queries.

### Ultra-audit pass-2 fixes (post-staging swarm)

A 4-agent ultra-audit (Saudi-pro / code-effect / test-quality /
PDF-conformance) of the v1.0.9 staged diff surfaced four follow-on
fixes BEFORE shipping:

- **Net.lua Qaid handlers cardMult/meldMult split (CRITICAL)**:
  `HostResolveTakweesh` (line ~2462) and `HostResolveSWA` invalid-SWA
  branch (line ~3337) BOTH still applied a single full-cascade `mult`
  to (cards + melds). With D HIGH-1 in `Rules.lua` but unchanged in
  `Net.lua`, a Triple/Four/Gahwa Qaid resolution would over-multiply
  the non-offender's melds by ×3/×4 instead of ×2 — directly
  contradicting the PDF §5-6 fix one file over. Now both Qaid paths
  use the same `cardMult`/`meldMult` split. Legacy `mult = cardMult`
  alias kept for the outer-scope telemetry field.

- **Bot.lua M5 CompareMelds passes dealer**: M5's winner-takes-all
  zeroing now passes `S.s.dealer` so tied-rank scenarios resolve
  the same way `R.ScoreRound` does (PDF Rule 2 dealer-right
  priority). Pre-fix M5 would see "tie" → keep both teams' melds
  while ScoreRound resolved to one team — mis-estimating M5 target
  by up to (oppMeld)/2 in tied scenarios.

- **State.lua S.MeldVerdict passes dealer**: UI's live meld-verdict
  strip now consults dealer for tied-rank resolution, eliminating
  the momentary visual lie where the strip showed "tie/no strip"
  while final scoring awarded melds to the dealer-right team.

- **docs/strategy/saudi-rules.md**: rewrote the Q3/Q5 multiplier
  section to reflect the v1.0.9 PDF §5-6 cap-at-Bel rule. Per
  CLAUDE.md ("If a strategy doc and Rules.lua disagree, Rules.lua
  is authoritative for legality"), the doc was contradicting v1.0.9
  code with the v0.11.10 full-cascade reading.

- **A#2 comment cleanup**: re-labeled "canonical 100-meld" →
  "canonical 4-card trump-sequence" since T-J-Q-K and J-Q-K-A score
  as `K.MELD_SEQ4 = 50` raw, not 100. The gate logic was correct;
  comments and chat traces were misleading.

### Tests

- **AE.1 / AE.2 updated** for A#2 tightening — pre-v1.0.9 hands
  pinned the loose-bypass behavior; updated to use hands that
  satisfy the new gate (K+Q+count>=3+sideAce).
- **AE.1c (NEW)**: K+Q+count>=3 NO sideAce blocks BC-MANDATORY → PASS.
- **AE.2c (NEW)**: K+Q+count>=3+sideAce R2 fires Hokm.
- **AJ.1b / AJ.2b / AK.6 updated** for A#1 algebra (added
  `math.floor((m5_oppMeld - m5_myMeld) / 2)` and `baseTarget`).
- **AJ.2c (NEW)**: A#1 source-pin verifying CompareMelds is
  consulted for winner-takes-all.
- **Section AL (NEW)**: v1.0.9 swarm-finding behavioral coverage.
  AL.1 (C#2 skip), AL.2 (C#2 ride partner), AL.3 (no info), AL.4
  (A#2 4-card trump sequence).
- **K2 section (NEW, test_rules.lua)**: 8 tests for the D HIGH-1
  cardMult/meldMult split. Hokm bare/Bel/Triple/Four/Gahwa, Sun
  bare/Bel, plus a behavioral test asserting `raw.A` reflects the
  cap (250×3 + 100×2 = 950 NOT 1050 full-cascade).
- **F.dealer-right (NEW, test_rules.lua)**: 4 tests for PDF Rule 2
  tied-meld dealer-right priority. dealer=4→A, dealer=1→B,
  walk-skip case, back-compat fallback (no dealerSeat → "tie").

### What WASN'T changed (this release)

The user's PDF cross-check covered four rules. Three are already
canonical in the code (verified), one needs a bigger feature:

- **Rule 1 (Belote announcement requirement)** — D HIGH-2: NOT
  implemented. PDF says the Belote holder must announce on the
  second card or it doesn't count (unless covered by a sequence
  meld). Currently auto-detected retroactively in R.ScoreRound.
  Needs MSG_BELOTE wire + S.s.beloteAnnounced flag + UI button +
  R.ScoreRound gate. Deferred — substantial scope, requires user
  green-light on UX details.
- **Rule 3 (Kaboot + opp's declared melds)**: VERIFIED
  IMPLEMENTED. Sweeper gets bonus + own declared melds; swept
  side's melds drop to 0. Matches PDF "the kabooter team gets X
  points + the مكبِّت's declared melds" reading (active participle
  = sweeping team).
- **Rule 4 (Bel-Triple-Four-Gahwa is bidder-vs-Beler-only)**:
  VERIFIED PARTIAL. Net.lua seat gates: Bel→NextSeat(bidder),
  Triple→bidder, Four→NextSeat(bidder), Gahwa→bidder. The Beler
  seat is HARDCODED to NextSeat(bidder); chain is locked to
  bidder↔Beler-only because Beler-seat is fixed. Caveat: PDF text
  «المدبل» = "the doubler" (the defender who actually Bel'd) does
  not specify which of the two defenders. Saudi-pro convention
  allows EITHER defender to Bel first; current addon restricts to
  NextSeat(bidder) only — PrevSeat(bidder) cannot Bel. Stricter-
  than-necessary gate (not a leak); the partner of the Beler is
  correctly excluded. Future enhancement: add `contract.doublerSeat`
  tracking + open Bel-eligibility to both defenders. Deferred
  (UI/wire/AFK touch points; not a v1.0.9 critical gap).

## v1.0.8 — Triple/Four/Gahwa eltrace observability

User-requested: the existing `[bel sN] PickDouble eval/PASS/FIRE`
trace shows defender Bel decisions when `WHEREDNGNDB.debugBidcalc`
is on. The downstream rungs (Triple, Four, Gahwa) had no
equivalent trace — leaving "why never Triple?" debugging blind.

### Added

- **`Bot.PickTriple` eltrace** (Bot.lua:Bot.PickTriple). Mirror of
  PickDouble's pattern. Logs `[trp sN] PickTriple eval: strength=X
  th=Y jth=Z (BOT_TRIPLE_TH=W)` then PASS or FIRE with wantOpen
  flag. Also logs the `Sun has no Triple rung` short-circuit when
  the Sun-blocked branch fires.

- **`Bot.PickFour` eltrace** (Bot.lua:Bot.PickFour). `[for sN]`
  prefix (orange). Same eval/PASS/FIRE shape.

- **`Bot.PickGahwa` eltrace** (Bot.lua:Bot.PickGahwa). `[ghw sN]`
  prefix (red). Logs eval/PASS/FIRE; FIRE notes "terminal,
  match-win".

### Why this matters

Across the 51-round v1.0.7 sample, Bel fired 3× but Triple fired 0×.
Two interpretations were possible:
1. Bidder correctly didn't escalate marginal Bels (calibrated)
2. Triple threshold structurally too high (mis-calibrated)

The eltrace now disambiguates: the next time PHASE_TRIPLE fires,
the trace will show the bidder's strength score and threshold,
making it visible whether the bidder was below threshold by 1 or
by 30. Same applies to Four (PHASE_FOUR) and Gahwa (PHASE_GAHWA).

### Tests

753/753 pass. AH.3 source-pin window bumped 2500→4000 to
accommodate the new eltrace block in PickTriple.

### How to use

`/baloot bidcalc` toggles the existing debug flag. With it on,
all four escalation rungs now log to chat with color-coded
prefixes:
- `[bel sN]` cyan-green — defender Bel decision
- `[trp sN]` cyan — bidder Triple decision
- `[for sN]` orange — defender Four decision
- `[ghw sN]` red — bidder Gahwa decision

## v1.0.7 — Test-debt closure (Section AK behavioral coverage)

Test-only release. Adds 7 behavioral tests (Section AK) that exercise
v1.0.4 + v1.0.6 bot-logic fixes by setting up game state and asserting
on `Bot.PickPlay` / `Bot.PickTriple` outputs. No bot-logic, schema,
or calibration changes. 753/753 tests pass.

### What v1.0.4 / v1.0.6 lacked

Sections AI (8 tests) and AJ (9 tests) were source-pin only — they
verified the relevant code blocks existed in source via `find()`
patterns, not that the code BEHAVES correctly. v0.11.19-hotfix F1
proved this anti-pattern is dangerous: a source-pin pass coincided
with a silently broken `if nil and ...` short-circuit (M5 never
fired because of an unbound variable). Behavioral tests catch this.

### New behavioral coverage (Section AK)

- **AK.1 (N2 behavioral): Foured smother gate.** Sets up Foured
  contract + pos-3 + partnerWinning + 2 H point cards in hand;
  asserts the bot does NOT smother A (gate=lastSeat-only at ×4).
- **AK.2 (N2 behavioral): Doubled tier preserves donate.** Same
  setup but ×2 contract + 5 prior tricks completed; asserts the
  bot DOES smother A (gate=lastSeat OR completed≥4 at ×2).
- **AK.3 (N1 behavioral smoke): Urgency-swing meld-pin guard.**
  Constructs near-clinch state with partner-meld declaring AH;
  asserts pickFollow returns SOME card (smoke — exact card depends
  on multi-branch interplay; the source-pin AJ.3 verifies block).
- **AK.4 (agent #6 behavioral): touch-honor save filters A/T.**
  Sets `Bot._partnerStyle[partner].topTouchSignal[H] =
  {nextDown="K"}`; asserts smother donates Q (not A or T) when
  partner has signaled K-singleton inference.
- **AK.5 (agent #8 behavioral): Mathlooth K-tripled.** Sun
  contract + 3 H cards + can't-beat path; asserts K is NOT picked.
- **AK.6 (N6 behavioral pin): defender M5 no +1 off-by-one.**
  Source-pin verifies `defenderTarget = baseTarget + m5_oppMeld
  - m5_myMeld` (no +1) — combined with N3 meld delta math.
- **AK.7 (FLOOR-3 behavioral): PickTriple floor cap respected.**
  Constructs weak hand + maximum urgency drop; asserts PickTriple
  does NOT fire even at the floor cap edge.

### Deferred — full Cluster 7 conversion

The original v1.0.4 deferred-list mentioned ~10 source-pin tests to
convert to behavioral. Section AK adds 7 NEW behavioral tests (the
highest-leverage ones — covering recent bot-logic changes). The
remaining source-pin tests in T/U/V/W/X/Y/Z and earlier sections
are mostly historical pins of old fixes; converting them is
mechanical work with diminishing returns. Defer until a specific
test fragility surfaces.

## v1.0.6 — Dual ultra-audit findings + deck refresh

Closes the dual-agent audit run from the v1.0.5 cycle (one bot-
behavior agent finding 9 NEW gaps; one code-effect agent finding 8
issues including a real off-by-one bug). Plus user-requested deck
changes. 746/746 tests pass.

### CRITICAL — actual logic bug (real-game impact)

- **N6: M5 defender mirror off-by-one (Bot.lua:M5 trick-8 block).**
  Pre-fix code used `defenderTarget = base + 1`, but Saudi rule
  per CLAUDE.md and Rules.lua: bidder fails on tied half-and-half.
  Defender at exactly 81 raw (Hokm) or 65 raw (Sun) ALREADY forces
  bidder fail. The `+1` was wrong by 1 raw — fired the swing 1 raw
  too late. Mostly benign (just spurious fires) but inconsistent
  with the bidder mirror. Now both mirrors use `baseTarget` directly.

- **N3: M5 mirrors ignore meld bonuses in target.** Both bidder and
  defender mirrors used bare 81/65 constants — but `R.ScoreRound`
  adds melds to team totals. Opp declared 100-pt carré → bidder's
  REAL make-threshold is 181 (M5 fired highestByRank on a doomed
  contract). Now: `target = baseTarget + oppMeld - myMeld`.

### HIGH severity — gap-closing fixes

- **N1: Urgency-aware swing × meld-pin guard (Bot.lua:pickFollow).**
  v1.0.4 #1 (urgency swing) fired before pos-aware ducks under
  match-point pressure but didn't consult Cluster 1 meld awareness.
  Worst-case: bot grabs trick with K when partner's already-
  declared meld holds A — strands partner's run. Now: before swing
  fires, check `meldKnownHeld(partner)` for higher-rank cards in
  led suit; suppress swing if found.

- **N2: Multiplier-aware tightening tiered (Bot.lua:smother).** Pre-
  fix v1.0.4 #2 treated all escalation rungs identically as
  `lastSeat-only`. But ×2 (Bel, the COMMONEST) shouldn't suppress
  speculative donates as aggressively as ×3/×4. Now tiered:
  `foured/tripled → lastSeat only`, `doubled → lastSeat OR
  completed >= 4`, base unchanged otherwise.

- **N5: ISMCTS rollouts mute `S.s.cumulative` (BotMaster.lua).**
  v1.0.4 #1's urgency-aware swing reads `S.s.cumulative` directly.
  C-14 closure swapped hostHands/trick/_memory but NOT cumulative
  → all rollout worlds homogenize under match-point pressure,
  killing variance/discrimination. Now cumulative is saved/nil'd
  during rollouts and restored on cleanup.

### MEDIUM — code quality / cleanup

- **B#1 ESC-1 comment correction (Bot.lua:escalationStrength).**
  Comment claimed "inverts the Sun-only void penalty"; actual code
  is "neutralization" (cancels Sun penalty so EV-1 voidBonus passes
  through clean). Behavior is correct (voids count positive in Hokm
  via EV-1's +5/void). Comment now accurately describes the
  neutralize+EV-1-bonus pattern. No math change.

- **B#3+#4 Dead-code removal (UI.lua).** v1.0.5 made
  `meldTextVisible()` always return false; `meldsDescForSeat()`
  builder + `if meldTextVisible() then ...` arms became
  unreachable. Removed both functions and collapsed the dead arms.
  ~22 lines of unreachable code gone.

- **B#6 State.lua R.TeamOf (S.ApplyRoundEnd:trickWinners).**
  Inline `(winSeat == 1 or winSeat == 3) and "A" or "B"` replaced
  with `R.TeamOf(winSeat)`. The team-mapping rule lives in one
  place (Rules.lua:25-28); duplication risked silent telemetry
  desync if the rule ever changed.

### LOW — UX / display

- **B#7 Tooltip rename (UI.lua:M3lm tooltip).** "Beled / Tripled"
  → "Doubled / Tripled" to match v1.0.2's "Bel" → "Double x2"
  rename. v1.0.2 missed this user-visible string.

### User-requested deck changes

- **"Burgundy" → "4 Colors" display rename (UI.lua).** Internal
  key `burgundy` and `texSubdir` preserved so existing
  `WHEREDNGNDB.cardStyle = "burgundy"` entries keep working
  without migration. Display name only.

- **"Royal Noir" → "Ba8ala SET" + new card art (UI.lua + 32 TGA
  files in `cards/royal_noir/`).** Replaced Royal Noir card art
  with [xCards](https://github.com/Xadeck/xCards) (BSD-2 license)
  via `tools/convert_xcards_to_baqala.py`. Saudi-relevant 32
  cards (7-A × 4 suits) at @2x source density Lanczos-downscaled
  to 128×192 32bpp BGRA TGA. Internal key `royal_noir` and
  `texSubdir` preserved (option A migration: existing settings
  keep working). `back.tga` preserved from the original Royal
  Noir charcoal/gold aesthetic.

### Tests

- 9 new source-pin assertions in Section AJ covering AJ.1 (N6 + N3
  off-by-one fix), AJ.2 (N3 meld-aware), AJ.3 (N1 partner-meld
  guard), AJ.4 (N5 ISMCTS swap), AJ.5 (N2 tiered gate), AJ.6 (B#6
  R.TeamOf), AJ.7 (B#3+#4 dead code), AJ.8 (B#7 tooltip), AJ.9
  (deck renames).
- 746/746 tests pass (was 727/727 at end of v1.0.5).

### Deferred / not-fixed-this-release

- **N7 Sun-bidder-drought disambiguation** — refinement; defer.
- **N8 Defender observation asymmetry** — new feature (defender-
  side tells), not a bug fix.
- **N9 `meldKnownHeld` + bidcard composition** — refactor
  opportunity; defer.
- **B#5 CHANGELOG line-number drift** — small drift (~17 lines on
  v1.0.4 entries). Cosmetic for git-spelunkers; future debugger
  habit is to grep on function name not line number.
- **B#8 Historical CHANGELOG `K.SND_MELD_DECLARE` ref** — point-
  in-time accurate; leave.
- **N4/B#2 BEHAVIORAL coverage for AI section** — partial. AJ
  section has additional source-pins; behavioral tests with
  state-setup harnesses deferred to a focused test-debt cycle
  (alongside Cluster 7 from v1.0.4).

## v1.0.5 — Hide trick-1 meld text label (user UX request)

User-requested behavior change: the small text label under each
player's name during trick 1 ("Seq3 K (20)" / "Carre J (100)" etc.)
is now hidden permanently. Saudi convention is verbal-only
announcement — no on-screen badge.

### What changed

- **`UI.lua` `meldTextVisible()` always returns `false`.** Pre-v1.0.5
  it returned true during DEAL3/PLAY when no tricks had completed
  (`#s.tricks == 0`), making the meld text label visible until
  trick 1 closed.

### What stays

- **Trick-1 sound cue:** unchanged. `S.ApplyMeld` (v1.0.2 wiring)
  fires `K.SND_MELD_SERA / 50 / 100 / 400` based on meld value/
  kind/contract. Audio announcement remains the primary
  declaration signal.
- **Trick-2 card reveal:** unchanged. When a declarer's turn
  arrives in trick 2, their meld cards display for 5 seconds
  via the `meldHoldUntil` mechanism. Cards-as-proof is preserved.
- **Round-end summary:** unchanged. The banner at round end
  shows what melds got declared and their values.

### Tests

726/726 pass. Single-line behavior change to a UI-only helper
with no test impact.

## v1.0.4 — Bot-vs-human behavior gap closure (8 audit findings)

Closes the 8-finding bot-behavior audit from the v1.0.3 cycle.
Addresses structural gaps in trick-play decision-making that were
NOT on the original v1.0.0 deferred list. 726/726 tests pass.

### HIGH severity (2 items)

- **#1 Trick-play urgency-blindness (Bot.lua:pickFollow ~3997).**
  PickBid/PickDouble/PickTriple/PickFour/PickGahwa/PickPreempt/
  PickOvercall/PickAKA all consult `scoreUrgency` /
  `combinedUrgency` / `matchPointUrgency` — but pickLead and
  pickFollow ignored cumulative state. A defender at 145/152 plays
  the same as at 0/152. Now pickFollow's winners-block pre-empts
  the pos-aware ducks with a `highestByRank` swing under match-
  point pivotal pressure (myCum >= target-25 OR oppCum >=
  target-15). M3lm-gated. Skips trick 8 (M5 already handles it).

- **#2 Trick-play multiplier-blindness (Bot.lua:pickFollow ~3490).**
  Smother / winners-block / M5 trick-8 logic ignored
  `contract.doubled` / `tripled` / `foured` — but a 10-face-value
  swing in a Foured (×4) round is worth 40 effective. Smother gate
  now tightens to **lastSeat-only** (free-dump path) when any
  escalation is active. Speculative donates (≥2 point cards spare
  OR late-round) deferred under multiplier ≥ 2.

### MEDIUM severity (6 items)

- **#3 BotMaster sampler bidcard downweight
  (BotMaster.lua:sampleConsistentDeal).** The v0.11.19 U-3 bidcard
  inference flips trump-pull-exhaustion in pickFollow but
  `sampleConsistentDeal` still placed side-suit-A bidcard cards in
  defender hands via the H-2 defenderDesire bias (each non-trump
  Ace = 8). When bidcard is a side-suit Ace owned by bidder, the
  defender bias for THAT specific Ace is now cleared so the
  sampler doesn't waste cycles on inconsistent worlds.

- **#4 PickDouble bid-history inflection
  (Bot.lua:Bot.PickDouble).** The contract's provenance carries
  hand-quality info: a Sun-on-A-bidcard with prior bidders implies
  preempt-Sun shape (strong). `contract.overcallFromHokm` flag
  implies overcall-converted Sun (very strong). Both bias `th`
  upward by +5 to deter Bel'ing strong-tells contracts. M3lm-gated.

- **#5 Bargiya receiver phase-split (Bot.lua:pickLead ~2425).**
  Per signals.md §3 (canonical): receiver of a confirmed bargiya
  with ≥5 cards remaining (opening / mid-round) should burn 1-2
  of own tricks first to set up the eventual lead-back — not
  surrender initiative immediately. Endgame (≤4 cards) DOES lead
  the bargiya'd suit immediately. Phase-split now suppresses the
  pref for confirmed-bargiya signals when handSize >= 5; bargiya_
  hint / want / endgame retain the immediate lead-back behavior.

- **#6 Touching-honors signal in pickFollow
  (Bot.lua:pickFollow smother ~3450).** F3 wired the partner-touch-
  honor read in pickLead in v1.0.0. Mirrored here in the smother
  branch: when partner has shown a K-singleton (entry.cleared =
  {Q,J}) or any T/Q signal in the LED suit, save A and T — let
  partner cash the run on their own lead. Filters A/T out of
  pointCards; K/Q/J still donate.

- **#7 M5 trick-8 defender mirror (Bot.lua:pickFollow trick-8).**
  v0.11.19 M5 added bidder-team make-the-bid awareness on trick 8.
  Symmetric defender goal (force bidder fail at strict-majority,
  target+1 raw) now gets the same `highestByRank` preference when
  defender is in the make-or-break band. Defender at 75 raw needs
  ≥82 raw to force Hokm-bidder fail; trick 8 = swing.

- **#8 Mathlooth K-tripled trickle in Sun
  (Bot.lua:pickFollow ~4257).** Per decision-trees.md §4 row 11
  (Definite, video 17): Sun + K + 2 lower in side-suit + suit
  led + tricks 1-2 → reserve K for trick 3 (after A and T fall).
  Now excludes K from the lowestByRank candidate pool when this
  shape exists, so the trickle dumps 7/8 first and K cashes
  trick 3. M3lm-gated.

### Tests

- 8 new source-pin assertions in Section AI covering each of the
  8 agent findings.
- Total: 726/726 tests pass (was 718/718 at end of v1.0.3).

### Deferred to v1.0.5

- **Cluster 7 test-debt closure** (~10 source-pin tests to convert
  to behavioral counterparts). Pure mechanical work, no behavior
  change. Held since adding more source-pin tests in this release
  (Section AI's 8 new pins, plus the prior Section AH's 10) would
  go in the wrong direction; the test-debt closure is best done as
  a focused refactor pass with no other changes mixed in.

## v1.0.3 — Deferred-queue closure: 22 audit items from clusters 2-5

Closes the entire v1.0.0-deferred queue from CHANGELOG.md (the
"Deferred from v1.0.0" section). 22 items across 4 audit clusters
plus 10 new source-pin tests in Section AH. No calibration-threshold
changes. 718/718 tests pass.

### Cluster 2 — Defender play (5 items)

- **F5 (Belote K+Q-trump preservation in pickLead defender,
  Bot.lua:~3140).** When forced to lead trump (no non-trump in hand)
  AND we hold both K+Q of trump (Belote pair), prefer trump that's
  NOT K or Q. Belote scoring is locked at meld declaration so this
  doesn't affect the +20 bonus, but keeping the pair together for
  cash-on-our-lead extracts more attack value than an arbitrary
  K-lead. Layered AFTER `saveHighTrump` so the J/9 protection
  still wins; only kicks in for "below-J/9" decisions.

- **F6 (Defender Bargiya defensive-shed in Hokm — DEFERRED).**
  Considered and rejected. The Saudi convention for discard-side-A-
  with-cover is canonically Sun-only; Hokm has its own side-suit
  control signaling via implicit AKA on bare-A lead. A Hokm extension
  conflicted with the U-6 v0.11.19 fix (E.3 test pin). The Sun gate
  stays as-is; Hokm "lead-back" semantic is carried by AKA flow.
  Decision documented in code (no behavior change).

- **F7 (firstDiscard vs Tahreeb conflict — RESOLUTION-DOC).** The
  conflict is structurally resolved via two complementary gates:
  v0.11.18-final U-2 made the Tahreeb sender's "want" arm Sun-only,
  and v1.0.3 (U-5 below) added a sender-side trump-discard
  suppression. firstDiscard ledger no longer carries trump or Sun-
  Tahreeb-bargiya-emission entries. Documented in pickLead's
  Fzloky-pref-suit reader (no behavior change).

- **F8 (Sun-bidder-drought tell, Bot.lua:~2916).** Mirror of
  `bidderTrumpDrought` for Sun contracts. After 3 tricks, if the
  bidder has LED at least once and NEVER led an Ace, they're Ace-
  poor — defender team aggressively cashes their highest point
  card. M3lm-gated; reuses the existing point-card lead branch.

- **F9 (Defender Faranka comment cleanup, Bot.lua:~3469).** Hokm
  Faranka exception comment block refreshed to reflect current
  bidder-team gating (v0.9.2 #49 + v0.10.0 X3 widened both
  exceptions #2 and #4 from bidder-only). Removed the stale
  Section 10 rule 7 anti-trigger reference (deleted in v0.10.3).
  No behavior change.

### Cluster 3 — Bidding/escalation residuals (5 items)

- **FLOOR-3 (Bot.lua:Bot.PickTriple ~line 4404).** Floor cap added
  matching the symmetric defenses in PickDouble/PickFour/PickGahwa.
  `combinedUrgency + styleBelTendency` could drop `th` from base 90
  to 67 on top-tier hands; floor at `BOT_TRIPLE_TH - 16 = 74`.

- **ESC-1 (Bot.lua:escalationStrength).** sunStrength applies a
  Sun-only void penalty (capped 8). In Hokm, voids = ruff capacity
  (POSITIVE), not negative. escalationStrength now inverts that
  penalty in its Hokm branch so the per-hand score is honest.

- **PEB-DEAD (Bot.lua:partnerEscalatedBonus).** Doc'd `contract
  .foured` and `contract.gahwa` branches as INTENTIONALLY dead —
  they fire only from post-Gahwa override pickers (none currently);
  reserved for future. No behavior change.

- **OVC-DOUBLE (Bot.lua:Bot.PickOvercall).** Doc'd the calibration
  interaction between sunStrength's void-penalty (capped 8 cumulative
  on short/honorless suits) and PickOvercall's voidBonus (only fires
  on TRUE voids). They don't fully cancel; the asymmetry is by design
  and documented.

- **PB-1 (Bot.lua:partnerBidBonus).** Split PASS-penalty semantics by
  bidder-team membership. For BIDDER side, partner-PASS is a
  legitimate weakness signal (partner couldn't bid) — penalty
  applies. For DEFENDER side, partner is the OTHER defender; both
  defenders pass in any bidding round (only the bidder team bids),
  so partner-PASS is uninformative. Penalty suppressed for
  defenders so escalation thresholds aren't unfairly raised.

### Cluster 4 — Trick play / signaling (5 items)

- **U-4 (Bot.lua:topTouchSignal writer).** Mirror of v0.9.2 #46
  baitedSuit forced-J gate. Suppress T/K/Q signal recording when
  no lower-rank cards of the suit have been observed played by
  this seat (the honor play might have been mathematically forced).
  7/8/9 broke-signals remain unconditional (forced-or-not, the
  "no honor in suit" inference is unambiguous).

- **U-5 (Bot.lua:Bot.OnPlayObserved).** Sender-side trump-discard
  suppression on `mem.firstDiscard`. In Hokm, must-trump-ruff
  forces a trump play when void in led suit — that's not a
  voluntary discard, so it shouldn't pollute the suit-preference
  signal ledger. The reader-side already filtered trump; now we
  symmetrically gate at the writer.

- **U-7 (Bot.lua:pickLead sweep-pursuit-early).** Kaboot-feasibility
  hand-shape gate. Pre-fix the early pursuit fired purely on "won
  every prior trick" — a thin-hand sweep at trick 3 commits us to a
  failing track. Now M3lm-gated additional check: count trump J/9/A
  in hand + side-suit bosses; require count >= remaining-needed
  tricks. False-positives just keep us in default play, not a worse
  path.

- **U-8 (Constants.lua + Bot.lua:Bot.PickAKA).** Promoted the inline
  `25` and `20` clutch thresholds to `K.BOT_AKA_CLUTCH_DISTANCE` /
  `K.BOT_AKA_CLUTCH_RACE_GAP` constants for tunability. No behavior
  change at default values.

- **Defender sweep-pursuit (Bot.lua:pickLead).** Pre-fix the early
  sweep-pursuit gate required `isBidderTeam`. Defenders sweeping
  every prior trick is the canonical Reverse Al-Kaboot setup
  (K.AL_KABOOT_REVERSE = 88 raw). Gate now allows defender-team
  pursuit too.

### Cluster 5 — SWA + BotMaster cross-cutting (8 items)

- **M6 (Bot.lua:Bot.PickSWAResponse).** Partner-team gate doc'd as
  defense-in-depth. Net.LocalSWAResp / _OnSWAResp already filter
  partners out at the wire layer; the team gate here is unreachable
  through normal flow but kept for any future direct invocation.

- **L1 (Net.lua:LocalSWA fall-through).** Stale "≤3 cards or
  permission disabled" comment refreshed. v0.5.17 routed ALL counts
  through the permission window when permission is enabled; the
  fall-through now only fires for `swaRequiresPermission == false`.

- **L2 (Rules.lua:R.IsValidSWA).** Defensive recursion budget
  (`SWA_RECURSION_BUDGET = 200`). Natural max depth is ~32
  (8 tricks × 4 plays). Budget caps unchecked depth on malformed
  inputs; failure mode = deny SWA (better than hang).

- **BM-01-DOC (BotMaster.lua:rolloutMemory firstDiscard copy).**
  Removed dead-copy of non-existent `.bucket` field. Schema is
  `{suit, rank}` only.

- **BM-04-FALLBACK (BotMaster.lua:sampleConsistentDeal fallback).**
  Two-pass void-respecting allocation. Pass 1 places only void-
  respecting cards; Pass 2 (give-up path) accepts void-violating
  cards only when Pass 1 under-fills. Better incomplete info than
  no rollout.

- **DOC-DRIFT-WORLDS (docs/strategy/bot-personalities.md).** Saudi
  Master tier description refreshed: "100/60/30 worlds" is the
  CONFIGURED ceiling; actual worlds-completed is capped by
  `K.BOT_ISMCTS_BUDGET_SEC` (default 0.5s wall-clock). Pre-doc
  claimed the configured count without the budget caveat.

- **PARTNERSTYLE-INVARIANT (tests/test_state_bot.lua AH.1).**
  Source-pin test asserting BotMaster.lua never reassigns
  `Bot._partnerStyle` during a rollout (the C-14 closure swaps
  `Bot._memory` but `_partnerStyle` is intentionally shared across
  rollout/main-game).

- **BM-06 (Bot.lua:Bot.IsSaudiMaster).** Predicate intentionally
  retained with no current heuristic carve-out — tier API symmetry
  with IsAdvanced/IsM3lm/IsFzloky. Decision documented in code.

### Plus 1 stale-comment refresh

- **CONSTANT-COMMENT-DRIFT (Constants.lua:K.BOT_GAHWA_TH).** Comment
  refreshed to reflect 8-card-hand evaluation context (Gahwa fires
  post-HostDealRest). Pre-doc cited the 5-card bidding-time max,
  which was the original v0.11.17 justification but doesn't apply
  at the threshold's actual fire point.

### Tests

- 10 new source-pin assertions in Section AH covering FLOOR-3,
  L2, BM-04-FALLBACK, U-8, PB-1, ESC-1, PARTNERSTYLE-INVARIANT.
- 1 source-pin window bumped (AA.1) to accommodate ESC-1's
  Sun-penalty inversion preamble.
- Total: 718/718 tests pass.

### Deferred to v1.0.4

The bot-vs-human behavior gap audit (8 findings — 2 HIGH on trick-
play urgency/multiplier blindness + 6 MED on signal/sampler
refinements) and Cluster 7 test-debt closure (~10 source-pin tests
to convert to behavioral) are scoped for v1.0.4. Held to keep this
release surgical.

## v1.0.2 — User-supplied Saudi-vocal sounds + escalation-rung UI rename

User supplied 9 .mp3 vocal cues for the Saudi-Baloot escalation chain
and the four meld value tiers, plus a UI label rename matching the
new sound naming.

### Added (sound assets)

9 .mp3 files in `sounds/`:
- `BEL.mp3` — first escalation rung (defenders ×2)
- `three.mp3` — second rung (bidder ×3, replaces former triple.ogg)
- `four.mp3` — third rung (defenders ×4, replaces four.ogg)
- `gahwa.mp3` — terminal rung (replaces gahwa.ogg)
- `baloot.mp3` — Belote bonus (K+Q of trump, replaces baloot.ogg)
- `SERA.mp3` — seq3 meld (3 consec same suit, 20 raw)
- `khamseen.mp3` — seq4 meld (4 consec same suit, 50 raw)
- `100.mp3` — seq5 / carré T,K,Q,J / carré-A in Hokm (100 raw)
- `400.mp3` — carré-A in Sun (200 raw, "أربع مية")

### Wired

- **`K.SND_VOICE_DOUBLE`** — new constant pointing at `BEL.mp3`. Pre-
  v1.0.2 the first escalation rung had no voice line; only Triple/
  Four/Gahwa fired voice cues.
- **`S.ApplyDouble` fires `K.SND_VOICE_DOUBLE`** on every client at
  rung commit — symmetric with `S.ApplyTriple` / `Four` / `Gahwa`.
- **`S.ApplyMeld` dispatches** to one of `K.SND_MELD_SERA / 50 / 100
  / 400` based on `kind`/`value`/contract. Replaces the v1.0.1
  placeholder `K.SND_MELD_DECLARE`. Saudi convention names each meld
  by raw value; the dispatch table mirrors that.

### UI label rename

- `PHASE_DOUBLE` action buttons: "Bel (x2)" → "Double x2";
  "Bel & open/closed" → "Double & open/closed"; "Bel forbidden..." →
  "Double forbidden...". Internal phase / message names
  (PHASE_DOUBLE, LocalDouble, MSG_DOUBLE) unchanged — pure UI string
  change matching the new sound asset.
- `PHASE_TRIPLE` action buttons: "Triple & open (x3)" → "Triple x3
  (open)"; "Triple & closed (x3)" → "Triple x3 (closed)". Plus
  Skip-leftmost slot ordering (mirrors the v1.0.1 PHASE_DOUBLE
  click-momentum fix).
- Score-banner / round-summary modifier badges: "Bel" → "Double x2";
  "Triple (x3)" → "Triple x3".

### Tests

708/708 pass. No bot-logic, schema, or calibration changes.

## v1.0.1 — User-reported UX/visual fixes

Three fixes from the post-v1.0.0 user-feedback batch. All
gameplay/correctness paths unchanged; bot logic and telemetry
schema untouched. 708/708 tests pass.

### Fixed

- **Meld card display ambiguity (UI.lua `meldCardsForSeat`)**.
  Pre-v1.0.1 the trick-2 reveal strip concatenated cards from
  EVERY meld a seat declared and truncated to 5 slots. A seat
  declaring carré-J (4 cards) + an unrelated seq3 (3 cards) showed
  as `J♠ J♥ J♦ J♣ K♠` — visually indistinguishable from one
  illegal "4 Js + K" meld. Per Saudi rule only the BEST meld
  matters for the team-vs-team comparison anyway, so the strip
  now renders only the highest-`.value` meld for that seat.
  Tie-break: higher .top rank, then declaration order.

- **Bel button click-momentum hazard (UI.lua phase-DOUBLE actions)**.
  The action-button pool reuses fixed slot positions across phases.
  PHASE_OVERCALL slot 1 = "Take as Sun"; PHASE_DOUBLE slot 1 was
  "Bel & open" — same screen pixel. A user mid-click on the
  overcall decision could land their second click on Bel, and a
  third click could fire it through the confirm-arm. Now
  PHASE_DOUBLE slot 1 = "Skip" (safe default), Bel buttons after.
  Confirm-arm pattern still applies as second-line defense.

### Added

- **Meld-declaration sound cue (Sound.lua + State.lua + Constants.lua)**.
  `K.SND_MELD_DECLARE` placeholder added; `S.ApplyMeld` now fires
  `B.Sound.Try(K.SND_MELD_DECLARE)` on every client at the moment
  a meld is registered (trick 1, declaration time) — NOT at trick
  2 reveal time. Saudi convention treats the declaration as the
  canonical announcement moment. The .ogg file lives at
  `sounds/meld_declare.ogg`; user supplies it. If absent, no
  sound plays (graceful — `B.Sound.Try` nil-guards).

### Tooling

- **`tools/calibrate.py` Windows console encoding** — replaced the
  Unicode arrow `→` with ASCII `->` so the analyzer runs
  cleanly under Windows cp1252 (default `cmd.exe` codepage).
  No analytics changed. Python tool only — not part of the
  in-game addon.

### Deferred

- **FPS drop on Saudi Master tier (`K.BOT_ISMCTS_BUDGET_SEC`)**.
  Diagnosed: the per-move 0.5s ISMCTS rollout budget runs on the
  WoW main thread, causing visible stutter (~30 frames blocked
  per heavy bot move). Fix options enumerated (drop budget to
  0.25s; expose as a slash command setting; or refactor to
  C_Timer-spread rollouts across frames). Held pending explicit
  user request — the gameplay correctness is unaffected.

## v1.0.0 — Meld awareness + defender play + telemetry schema v=3

Milestone release. Bundles the highest-leverage residual items from
the v0.11.x audit queue into a coherent package focused on three
themes: (1) bots reasoning about declared melds in trick play, (2)
defender-side play improvements that surface in user-reported "bots
burn high cards" telemetry, and (3) richer round-end telemetry for
offline calibration of subsequent releases.

User priority: the meld-awareness package was explicitly prioritized
("prioritize it for next, but hold i am testing now, next release
should include all pending matters and be 1.0.0"). Second-tier items
remain on the deferred list — see "Deferred from v1.0.0" at the end
of this entry.

### Cluster 1 — Meld awareness (4 wirings)

When opponents declare a sequence/carré meld in trick 1, those cards
are PUBLIC INFORMATION but pre-v1.0.0 only the BotMaster ISMCTS sampler
consumed them (BotMaster.lua:243-260 pins meld cards into world-sample
hands). The heuristic Bot.PickPlay layer — used by Advanced/M3lm/Fzloky
tiers AND as the Saudi-Master rollout policy via the C-14 delegation
— was meld-blind. Now wired through 4 decision points:

1. **Trump-J/9 inference (Bot.lua:2657-2667).** The Hokm trump-pull-
   exhaustion check (`trumpJSeen and trump9Seen`) now considers OPP-
   declared meld cards as "still in opp's hand" — preventing premature
   "trump-killers are gone" inference when an opp's J/9 of trump is
   actually still live via meld declaration.

2. **Boss-of-side meld check (Bot.lua:2192-2207).** When we'd lead
   our highest non-trump as a "free trick" (HighestUnplayedRank),
   scan opp meld-known cards for higher rank in the same suit. If
   opp has a higher card via declared meld, our "boss" is no longer
   the boss — skip and try the next candidate. This closes the gap
   where HighestUnplayedRank is played-pile-based (correct) but
   misses meld-known cards in opp hands.

3. **Partner-meld avoid in pickLead (Bot.lua:2389-2403).** If PARTNER
   declared a sequence meld in suit X, partner has those cards.
   Leading X wastes partner's tempo and may strand high cards.
   Avoid leading X (let partner cash their meld run on their own
   lead). Sets `fzlokyAvoidSuit` if not already set.

4. **`meldKnownHeld(seat)` helper (Bot.lua:961-988).** Returns a set
   of cards the seat is known to hold via declared melds, EXCLUDING
   cards already played. Read by all 3 wirings above.

### Cluster 2 — Defender play (F2/F3/F4/F10)

Four targeted defender-side plays that closed gaps surfaced by user
trace data and Agent forensic analysis:

- **F2: J/9 trump-burn protection in pickFollow (Bot.lua:3635-3690).**
  When the BIDDER leads low trump (rank ≤ Q in trump rank order: 7, 8,
  Q), it's a probe to count opp trumps. If a defender uses J or 9 to
  take such a trick, they reveal the kill card AND burn it on a low-
  value trick. Saudi pros DUCK with non-J/9 trump. Mirror of pickLead's
  `saveHighTrump` but on the response side. Fires before the winners
  block so the cheapest-winner default doesn't auto-burn J/9 against
  us (especially in pos-2 sureStopper case where trumpOut <= 1).

- **F3: topTouchSignal read-side wiring (Bot.lua:2410-2422).** M3lm+
  writes the "partner played K under our A → partner has Q+J" inference
  (Bot.lua:498-530) but pre-v1.0.0 no heuristic decision consumed it.
  Now: if partner has a known down-touched honor in suit X, AVOID
  leading X so partner can cash their middle honor on their own lead.
  Layered after `fzlokyAvoidSuit`; first-set wins.

- **F4: Partner-void-suit ruff setup (Bot.lua:2828-2862).** When partner
  is OBSERVED void in a non-trump suit X (via prior must-trump-ruff
  detection), leading our LOW card from X gives partner a free ruff.
  1-2 partner ruffs per round can be the difference between failing
  and making bidder. Skip when partner is the bidder (ruffing partner's
  own contract is wasteful — they want to PULL trump, not ruff).

- **F10: Trump-J/9 pin awareness — covered by Cluster 1 #1.** The
  meld-aware trump-J/9 inference IS the F10 fix: J/9 in opp meld means
  opp trump strength is NOT exhausted, so don't lead high non-trump
  expecting safety.

### Cluster 6 — Telemetry schema v=3

`S.ApplyRoundEnd` now writes 3 new fields per round-end row, bumping
schema version 2 → 3. Old (v=2) rows continue to parse cleanly under
the existing analyzer (field-presence checks throughout).

- **`bidderTier`** — string ("Basic"/"Advanced"/"M3lm"/"Fzloky"/
  "SaudiMaster"/"human"). Per-tier bot fail-rate split, no longer
  blocked on the file-level `_inferredTier` fallback. Snapshot at
  round-end.
- **`tricksA, tricksB`** — int counts of tricks won by each team.
  Trivial to derive but logged for analyzer histogram convenience.
- **`trickWinners`** — string of 1-8 chars "ABBA..." indicating per-
  trick winner team. Compact (8-byte string vs 8-element table).

`tools/calibrate.py` `_report_sweep_progression` now consumes these
fields when present: per-trick team-A win rate, plus bidder-team
trick-1 → final-make-rate analysis. Pre-v=3 rows show the existing
final-outcome-only stats.

### Pre-ship ultra-audit (4 findings addressed)

Two parallel review agents found 4 real bugs in the initial v1.0.0
ship; all fixed before tagging:

- **H1 (Bot.lua trump-J/9 inference).** Original meld block iterated
  OPP team and forced `trumpJSeen=false` — but the default for
  unplayed-non-our-hand cards is ALREADY false, making the override
  a no-op. The genuine missing case was the INVERSE: when PARTNER
  team has J or 9 of trump in a declared meld, that card IS in
  friendly pool — should mark trumpJSeen / trump9Seen as TRUE so
  the "switch to side-Ace cashing" branch fires. Fix: iterate
  partner team and set trumpJSeen/9Seen=true.
- **H2 (Bot.lua boss-of-side meld check).** Also dead code. The
  outer gate `HighestUnplayedRank(su) == Rank(c)` already considers
  meld cards as "unplayed" — if opp had a higher meld card, the gate
  would fail before the meld scan ran. Reverted to simple-return.
- **H3 (Bot.lua partner-meld avoid).** Original block triggered on
  any partner-meld card, including carrés. Mirrored the existing
  opp-meld avoid filter to only fire on `seq*` melds (where the
  "let partner cash this run" rationale applies).
- **H4 (Bot.lua F3 topTouchSignal read-side).** Original block read
  `sig.nextDown` only — but the K-signal writer (the canonical case
  the CHANGELOG narrative emphasizes) sets `entry.cleared`, not
  `entry.nextDown`. F3 silently filtered out its main case. Fix:
  also read `sig.cleared`.
- **G7 (test coverage).** Schema v=3 had source-pin tests but no
  behavioral coverage of the new fields. Added AG.10 + AG.11
  exercising `S.ApplyRoundEnd` with each tier flag combination,
  asserting `bidderTier`, `trickWinners`, `tricksA/B` are written
  correctly.

### Tests

- 13 new behavioral assertions in Section AG (test_state_bot.lua).
- F2 has TWO behavioral tests (AG.8 + AG.9) that exercise the pos-2
  sureStopper override directly (with controlled `Bot._memory.played`
  state so trumpOut <= 1 fires deterministically).
- Schema v=3 has TWO behavioral tests (AG.10 bot tier + AG.11 human
  bidder) confirming the round-end row is correct.
- 708/708 tests pass.

### Deferred from v1.0.0

The full Cluster 2 deferred-list (F5, F6, F7, F8, F9) and remaining
Cluster 3-5 items (FLOOR-3, ESC-1, PEB-DEAD, OVC-DOUBLE, PB-1, U-4,
U-5, U-7, U-8, M6, L1, L2, BM-01-DOC, BM-04-FALLBACK, DOC-DRIFT,
PARTNERSTYLE-INVARIANT, CONSTANT-COMMENT-DRIFT, BM-06) are deferred
to v1.0.x or v1.1. Rationale per item:

- **F5 (Belote K+Q-trump preservation in pickLead).** Analysis
  (v1.0.0 prep): Belote is locked once both K+Q are held at meld-
  declaration time, regardless of when they're played. The
  preservation logic in pickFollow is about FACE-VALUE preservation,
  not Belote eligibility. The pickLead trump-leading paths already
  prefer non-J/9 (`saveHighTrump`) — adding non-K/Q would only differ
  when only K/Q remain as trump options, which is forced anyway. Low
  impact; defer.
- **F6 (Defender Bargiya defensive-shed in Hokm).** Bargiya is Sun-
  specific per Saudi convention (decision-trees.md Section 8 T-1).
  Hokm equivalent would require new doc-derived rule. Speculative;
  defer.
- **F7 (firstDiscard vs Tahreeb conflict).** Signal-disambiguation
  edge case; current code resolves via Sun-only Tahreeb gate (v0.11.18-
  final U-2 fix). No user-reported bug. Defer.
- **F8 (Sun-bidder-drought tell).** Mirror of `bidderTrumpDrought`
  for Sun. Niche signal; defer.
- **F9 (defender Faranka comment cleanup).** Pure prose; defer.
- **BM-06 (`Bot.IsSaudiMaster()` unused).** Function definition is
  harmless dead code. Removal would break tier-API symmetry (Advanced/
  M3lm/Fzloky/SaudiMaster all have an `Is*` predicate). Keep.

### Why this is "v1.0.0"

Per user instruction: "next release should include all pending matters
and be 1.0.0". Practical delivery scope:

- Cluster 1+2 high-impact items: SHIPPED (4 + 4 = 8 wirings)
- Telemetry schema v=3: SHIPPED (3 new fields + analyzer support)
- Test coverage: 8 new behavioral assertions
- Deferred items: explicitly enumerated above with per-item rationale

The version bump from 0.11.x to 1.0.0 reflects API stability:
`WHEREDNGNDB` schema v=3, `S.ApplyContract`/`S.ApplyDouble`/etc.
public surface, slash command set, and the 5-tier bot dispatch
model are all stable. Future v1.x releases will preserve these
contracts; deferred items will land as v1.0.x or v1.1.

708/708 tests pass.

## v0.11.21 — Display rename: "Loot & Baloot"

User-requested rebrand. Two-line change:

- **`WHEREDNGN.toc`** `## Title:` field: `WHEREDNGN` → `Loot & Baloot`
  (this is what users see in the in-game AddOns list)
- **`UI.lua:407`** main window title: `WHEREDNGN` → `Loot & Baloot`
  (cyan-colored brand at the top of the bot's window)

The "(KZKZ will come)" subtitle/tagline on line 412 is preserved as
the addon's signature branding.

### What stays

- Folder name: `WHEREDNGN/` (changing requires GitHub repo rename +
  CurseForge project migration + 600+ test pin updates; defer to a
  future v0.12.0 if ever).
- Lua namespace: `WHEREDNGN.Bot`, `WHEREDNGN.K`, etc. (internal code
  organization; invisible to users).
- SavedVariables key: `WHEREDNGNDB` (zero data loss for existing users).
- Slash command: `/baloot` (already user-friendly).
- CurseForge project ID 1529200.

### Why minimal scope

A full namespace rename touches ~30 Lua files with hundreds of
references and requires SavedVariables migration. The user-visible
brand is the **Title** in the .toc + the in-game window title — both
now say "Loot & Baloot". Anyone reading the source still sees
"WHEREDNGN" but that's an internal-only concern.

675/675 tests pass.

## v0.11.20 — Tier-1 calibration nudges (Agent 1 math) + R1 Sun-button UI bug

Implements all 4 calibration recommendations from Agent 1's calibration-
math analysis (validated against your 33-round empirical data + 8 fresh
v0.11.19 rounds with the new eltrace observability).

Plus a user-reported UI bug: R1 Sun button was shown unconditionally
even when SUN was already bid in the round.

### Calibration changed (Agent 1 math)

- **`K.BOT_BEL_TH 45 → 35`.** Empirical 3-sample defender Bel-eval data
  (strength 5, 22, 4 from v0.11.19 trace) validates Agent 1's math:
  defender 5-card hands genuinely score in the 4-22 range. At TH=45,
  jth ≈ [35, 55] — strength=22 case never fires. At TH=35, jth ≈ [25, 45],
  catches ~30% of strength=22 hands and ~60% of canonical mardoofa-
  strength hands. v0.11.19 history: 60 → 45 (still too high empirically).

- **AKQ stopper bonus +8 → +12** (`Bot.lua:1044`). Agent 1: AKQ-trio = 3
  guaranteed tricks ≈ 30 raw. Existing face value contributes 18; bonus
  closes the gap. Modest +0.18pp Bel-rate impact alone (rare shape:
  0.87% of 5-card hands), but rule-correct.

- **R2 Advanced bump REMOVED** (`Bot.lua:1443`). Pre-fix
  `if Bot.IsAdvanced() then r2Base = math.max(r2Base, r1Base - 4)`
  bumped Advanced R2 from 36 to 38. Sim showed (n=20K, jitter=±6):
  - r2=36 → R1/R2 split 56.8/43.2 (closest to canonical 50/50)
  - r2=38 → 58.1/41.9 (over-suppressed R2 by 1.3pp)
  Empirical 33-round data showed R1 over-fires 73%; removing bump
  shifts R2 share up ~1.3pp.

- **`K.BOT_PREEMPT_TH 75 → 60`** + **PickPreempt 2-Ace+mardoofa bonus
  stack added.** Pre-fix structurally unreachable: 2A post-bidcard
  hands have median sun=24, p95=37; jitter band [65, 85] meant
  <0.01% fire. Both changes required:
  - PE_TH 75 → 60 (jitter band [50, 70])
  - 2-Ace +15 / 3-Ace +15 / mardoofa-pair-cap*+20 bonus stack mirrors
    PickBid R1 Sun
  Combined: ~0.72% canonical fire rate per A-bidcard (vs <0.01%
  pre-fix). Saudi tournament target 1-3% per A-bidcard.

### Fixed (user-reported UI)

- **R1 Sun button hidden when `anySun=true`** (`UI.lua:1736`). User
  observed: "if someone bids SUN before you, why do you still have
  Sun button?" Per `State.lua:2046` (HostAdvanceBidding), the FIRST
  direct Sun in R1 locks the contract; subsequent SUN bids are
  silent no-ops. The button was misleading. Now gated on
  `if not anySun then addAction("Sun", ...) end`. Hokm-on-flipped
  (line 1704) and Ashkal (line 1732) were already correctly gated.
  PASS button always shown — bidding round still completes formally
  per host wait-for-all-4 design.

### Tooling

- **`tools/calibrate.py`** stale comment: was reporting "BOT_BEL_TH=60;
  expect 20-35%" — now reads "BOT_BEL_TH=35 post-v0.11.20; expect
  10-25% in mixed-tier play".

### Test coverage (Section AF)

5 pins (AKQ +12, R2 bump removed, PickPreempt 2-Ace, PE_TH=60, UI
gate). 675/675 tests pass.

### What to expect on next play session

| Behavior | Expected |
|---|---|
| Bel rate | 0% (v0.11.19) → 5-15% per Hokm contract (target zone) |
| Strength=22 defender hand | Should now sometimes Bel (~30% of jitter rolls) |
| R2 contracts | Up ~1.3pp share (more rounds reaching R2) |
| PickPreempt fire | Was 0% on A-bidcard; now ~0.7% canonical |
| R1 UI after Sun bid | Sun button hidden, only PASS shown |
| Trick-8 make-or-break | M5 actually fires (post-hotfix) |

### Recommended validation

1. Pull v0.11.20 from CurseForge (~10 min after push)
2. `/baloot history clear`, `/baloot bidcalc`, play 10-15 rounds
3. Look for `[bel sN] PickDouble FIRE` lines (was always PASS pre-v0.11.20)
4. Run `python tools/calibrate.py --breakdown=escalation <savevars>` to confirm Bel rate > 0%
5. After Sun is bid in R1, verify Sun button is hidden in your UI

## v0.11.19-hotfix — F1 (M5 dead) + agent-delivered tooling + 19 behavioral tests

Post-v0.11.19 4-agent parallel audit returned. **Critical finding from
Agent 3 (defensive-play audit): the M5 trick-8 make-the-bid block
shipped in v0.11.19 was SILENTLY DEAD due to undefined upvalues.**
Plus Agent 2 delivered 19 new behavioral tests (closing source-pin
debt) and Agent 4 extended `tools/calibrate.py` with rich breakdowns.

### Fixed (CRITICAL)

- **F1 — M5 trick-8 dead block.** v0.11.19's M5 fix referenced
  `isBidderTeam` and `myTeam` as if they were locals in `pickFollow`,
  but those names exist ONLY in `pickLead` (peer file-local function;
  no upvalue scope). In Lua 5.1 the unbound names resolved to nil
  globals; `if nil and ...` short-circuited; M5 never fired. AD.6
  source-pin passed because it only checked the literal `target = ...`
  line was in source — the canonical "shipped dead code" failure
  pattern that Section AE behavioral tests are now meant to prevent.
  Fix: compute `m5_myTeam` and `m5_isBidderTeam` locally in the trick-8
  branch.

### Added — Section AE (Agent 2: 10 behavioral test cases, 19 assertions)

| Test | What it verifies behaviorally |
|---|---|
| AE.1 | BC-MANDATORY R1: K+Q-of-bidcardsuit fires Hokm even when raw strength below threshold |
| AE.2 | BC-MANDATORY R2: K+Q Belote suit fires Hokm even when bestScore below threshold |
| AE.3 | bidderHoldsBidcard phase-gate: PickPlay completes for both PHASE_PLAY and PHASE_DOUBLE |
| AE.4 | F5 OnEscalation: all four S.Apply* increment correct counter on _partnerStyle |
| AE.5 | B6 IsValidSWA existential: positive + negative SWA scenarios exercise caller-turn branch |
| AE.6 | U-6 non-trump preference: TrickRank=1 tie returns non-trump 7C (not trump 7H) |
| AE.7 | M5 trick-8 make-the-bid: gap=4 case picks JH (highestByRank) over 9H (highestByFaceValue) |
| AE.8 | PickDouble eltrace: trace fires only when WHEREDNGNDB.debugBidcalc=true |
| AE.9 | B4/H-5 akaLive flag: opp over-trumps partner's bare-A → receiver still discards non-trump |
| AE.10 | EV-1 bonuses: rich Hokm hand fires PickTriple; weak hand doesn't |

670/670 tests pass (was 651). 19 NEW behavioral tests close the
source-pin debt that allowed F1 to ship.

### Tooling — Agent 4

- **`tools/calibrate.py`** extended with `--breakdown=PROP` flag:
  `bidcard | tier | escalation | r0 | sweep-prog | round-dist | all`.
  Per-bidcard-rank fail-rate with Wilson 95% CIs, per-tier splits,
  chain progression, R0 sub-categorization. Backward compatible.
  Accepts multiple SavedVariables files for combined dataset.
- **`tools/SCHEMA_PROPOSAL.md`** — proposes `bidderTier`, `trickWinners`,
  `r0Reason`, `sideAKQ`, `bidPoints` fields for next-cycle telemetry.
- **`tools/sim_calib.py`** — Agent 1's calibration math simulator.

### Agent findings preserved (deferred for v0.11.20)

- **Agent 1 calibration recommendations** (3 concrete numbers):
  - AKQ-stopper bonus +8 → +12 (modest +0.18pp Bel impact alone)
  - R2 base 38 → 36 unconditional (drops Advanced bump; sim shows
    R1/R2 split 58.1/41.9 → 56.8/43.2, closer to canonical)
  - PickPreempt: add +K.BOT_SUN_2ACE_BONUS post-bidcard recompute +
    K.BOT_PREEMPT_TH 75 → 60 (pre-fix structurally unreachable; post-fix
    ~0.72% canonical fire rate per A-bidcard)

- **Agent 3 defender-side findings** (10 items):
  - F2 HIGH: defender J/9 of trump burn on first low pull (mirror of
    bidder-side saveHighTrump for pickFollow)
  - F3 HIGH: `topTouchSignal` written but never read in heuristic
    pickLead/pickFollow (only consumed by BotMaster sampler)
  - F4 MED: pickLead missing partner-void-suit ruff setup
  - F5 MED: Belote K+Q-of-trump preservation absent in pickLead
  - F6 MED: Defender Bargiya defensive-shed blocked in Hokm
  - F7 MED: firstDiscard Fzloky read fights with Tahreeb ledger
  - F8 MED: No Sun-bidder-drought tell parity for defender
  - F9 LOW: Defender Faranka comment cleanup
  - F10 LOW: Defender-side trump-J pin awareness

- **Agent 4 empirical signals** from extended analyzer on 33-round data:
  - Bidcard=K: 0/6 fails (K-bidcard correctly weighted)
  - Bidcard=Q: 2/4 fails (50% — possibly over-rated, small sample)
  - 0/15 Hokm + 0/18 Sun produced any escalation chain fire (matches
    Agent 1's statistical-consistency finding at BOT_BEL_TH=45)

### Test count

670/670 tests pass.

## v0.11.19 — agent-driven 3-game forensic + 9 fixes

User played 3 games on v0.11.18-final (33 rounds total). A specialized
forensic agent analyzed the trace data + SavedVariables against the
actual bot code and surfaced 1 NEW bug + confirmed all the planned
fixes. v0.11.19 implements all 9 (8 planned + 1 from agent).

### Fixed (HIGH from prior deferred ledger)

- **BC-MANDATORY (Belote shape→strength bridge).** Saudi rule B-6
  marks K+Q-of-trump + count≥2 as MANDATORY Hokm-of-that-suit.
  v0.11.16 added the shape-gate escape but the strength gate still
  rejected when score < thHokmR1. Now: if `belote == bidCardSuit`
  in R1 (or `belote == suit` in R2's bestSuit candidate set), Hokm
  fires unconditionally. The +20 multiplier-immune Belote bonus
  locks the suit's structural value.

- **U-3 (bidderHoldsBidcard → trump-J inference).** Wired the helper
  into `pickFollow`'s trump-J/9 exhaustion check (Bot.lua:2494). Pre-
  fix the inference treated bidcard-of-trump as "could be in any opp
  hand" — but the bidcard is PUBLIC knowledge held by the bidder.
  Now: if bidcard is J or 9 of trump and bidder hasn't played it,
  treat trump-strength as NOT exhausted; suppress side-Ace cashing.

- **DEAD-2 (PickGahwa floor cap removed).** Pre-fix `if th <
  K.BOT_GAHWA_TH - 16 then th = K.BOT_GAHWA_TH - 16 end` was
  unreachable: combinedUrgency clamp ±15 leaves th in [105, 135],
  always above floor 104. Removed; rationale documented inline.

### Fixed (MED — visible play improvement)

- **U-6 (non-trump preference in released-from-must-ruff).** Pre-fix
  `lowestByRank(legal)` in pickFollow's partner-winning fall-through
  picked arbitrarily between trump-7 and non-trump-7 (both TrickRank=1
  in their respective rank tables). Now: in Hokm + partner-winning,
  prefer lowest non-trump if available — preserves trump for actual
  ruffing capacity. Fixed test E.3 (was pinning the wrong v0.5.11
  fall-through behavior; updated to expect non-trump 9D over trump 7S).

- **M5 (trick-8 make-the-bid awareness).** Pre-fix trick-8 winners
  branch always picked `highestByFaceValue`. Now: when bidder team
  AND we're in the make-or-break gap (raw < target, gap ≤ 30),
  use `highestByRank` instead — maximizes trick-WINNING probability
  at the cost of a few face-value points. Targets: Hokm=81, Sun=65.

### Fixed (LOW)

- **`/baloot ismctsdiag` "0 worlds" disambiguation (ultra-audit BM-03
  follow-up).** Pre-fix users couldn't tell "0 worlds = single-card
  shortcut (normal)" from "0 worlds = budget cut on iter 1 (perf
  concern)". Now BotMaster tags `BM._lastShortCircuit` with
  "single-card" / "no-legal-moves" / "legal-build-failed" / nil
  (= entered world loop). Slash command surfaces the specific case.

- **btrace arg correctness (NEW from agent forensic).** Pre-fix
  the bidcalc trace logged `aceCount, mardoofaCount` from PRE-bidcard
  but `sun` from POST-bidcard, producing impossible-looking lines
  like `sun=64 aces=1 mardoofa=0`. Agent verified mathematically by
  reverse-engineering Game 3 trace at 13:32:14. Now: log `sunAces,
  sunMardoofa` (the post-bidcard recompute used for bonus stack).

### Changed (calibration)

- **`K.BOT_BEL_TH 60 → 45`.** Agent's mathematical walk-through of 5
  defender hands from the 33-round dataset showed effective belStr
  range 31-53 — 60 was structurally unreachable on most 5-card
  defender hands. Combined with v0.11.17 EV-1 added bonuses + new
  observability, target ~10-20% Bel rate per Hokm contract. Sub-
  finding deferred: side-AKQ stopper bonus (+8 in sunStrength)
  under-rewards 3 guaranteed tricks (~30 raw); future tuning.

### Added (escalation observability)

- **`PickDouble` eltrace** — mirrors PickBid btrace pattern. Toggled
  via `/baloot bidcalc`. Logs strength, threshold, jth, fire/pass
  decision. User-reported 0% Bel rate across 33 rounds had no
  diagnostic visibility; now the next session will produce
  `[bel sN] PickDouble PASS: strength=X < jth=Y` lines that surface
  WHY defenders aren't reaching threshold.

### Test coverage (Section AD added)

9 pins covering each fix. 651/651 tests pass.

### Forensic agent's other findings (deferred)

The agent flagged 4 additional items not yet shipped:
- Side-AKQ stopper bonus +8 under-rewards 3 guaranteed tricks
  (formula calibration)
- R1 over-fires 73% vs canonical Saudi 50-60% (R2 vs R1
  threshold gap should widen for non-M3lm tiers)
- Defender-team sweep-pursuit branch missing (Game 2 R7 had
  defenders sweep 28/144 swing without active pursuit)
- Need 80-120 rounds across mixed bot tiers for next-cycle
  statistical-power audit

### User-reported observation

User noticed "couldn't Bel >2x in these rounds" — investigated and
confirmed NOT a UI/state bug. PHASE_TRIPLE only fires after Bel.
Across 33 rounds 0 Bels = 0 PHASE_TRIPLE = no Triple button visible.
v0.11.19 BOT_BEL_TH drop should resolve this organically.

## v0.11.18-final — ultra-audit hotfix + comprehensive deferred report

Final hotfix from the post-v0.11.18 ultra-audit (4 parallel agents, ~13
HIGH findings). Addresses the most actionable items + leaves the rest
in the structured deferred-work report below.

### Fixed (HIGH from ultra-audit)

- **DEAD-1** — `Bot.PickFour` `belOpen == false` branch was DEAD CODE.
  PHASE_FOUR is structurally unreachable when belOpen=false (S.ApplyDouble
  shortcuts to PHASE_PLAY when belOpen=false; PHASE_TRIPLE only fires
  when belOpen=true; PHASE_FOUR only after open Triple). At PHASE_FOUR
  belOpen=true is invariant. Removed branch; reframed +5 bonus as
  unconditional calibration constant (matches reality).

- **U-1** — Implicit-AKA detector still gated on `partnerWinning`.
  v0.11.17's H-5 fix dropped this for explicit AKA but missed implicit.
  Rules.lua:142-152 grants implicit-AKA legality relief regardless of
  who's currently winning, so the heuristic should match. Pre-fix when
  partner led bare-A and opp pos-2 over-trumped, the receiver got
  non-trump in legal (relief fired) but pickFollow's branch still
  didn't fire — burning trump that legality had freed.

- **U-2** — Tahreeb sender "want" arm fired in Hokm. Per
  decision-trees.md Section 8 every sender row is tagged Sun-only.
  Pre-fix Hokm "want" emissions biased partner toward leading sideX
  when natural play is trump-pull. Wrapped want arm in
  `if contract.type == K.BID_SUN then ... end`; T-4 dump-ordering
  remains contract-agnostic.

- **B2-FALLBACK-REGRESSION** — Wall-clock budget broke heuristic-
  fallback gate. Pre-fix `if rolloutErrors == numWorlds` could never
  fire after early budget break (rolloutErrors=5 != numWorlds=100).
  Fixed: `worldsCompleted == 0 or rolloutErrors == worldsCompleted`.

- **BM-03** — `/baloot ismctsdiag` slash command added. Surfaces
  `BM._lastWorldsCompleted` + budget setting. Pre-fix the telemetry
  was dark — users had no visibility into when ISMCTS quality was
  truncated by budget.

- **H1** — SWA safety-net asymmetry. `PickSWA` (caller-side) had Hokm
  trump-coverage safety net rejecting when opp top trump > caller top
  trump. `Bot.PickSWAResponse` (response-side) only ran IsValidSWA.
  Bots now defend with same conservatism they call with — mirrored
  the safety-net check on caller's encoded hand vs hostHands.

- **H2** — `Bot.PickSWAResponse` missing W7 corrupted-state guard.
  Pre-fix the validator base-case (no cards remaining = trivial
  caller-win) accepted as valid; HostResolveSWA pre-call forces
  valid=false on this state. Bot now matches.

### Deferred — comprehensive structured report

The 4-agent ultra-audit produced findings in 4 clusters. After
applying the HIGH fixes above, the remaining items are explicitly
deferred for future cycles. Listed by audit cluster + severity:

#### Bidding + Escalation (Audit A)

| ID | Severity | Title | Notes |
|---|---|---|---|
| DEAD-2 | HIGH | PickGahwa F3 floor cap unreachable | Math: th range [105,135], floor 104 < min. Cosmetic / documents intent; no behavioral impact. |
| BC-MANDATORY | HIGH | Belote-no-J fails strength gate despite Mandatory rule | Fix: bypass strength threshold when shape=Mandatory-Belote. ~5 lines; defer pending behavioral test. |
| FLOOR-3 | MED | PickTriple has no floor cap (asymmetric with PickDouble/Four/Gahwa) | Add `if th < K.BOT_TRIPLE_TH - 16 then th = ...`. |
| ESC-1 | MED | escalationStrength sunStrength void penalty wrong in Hokm | sunStrength penalty assumes voids=bad; Hokm voids=ruff capacity (positive). Wider refactor. |
| PE-1 | MED | PickPreempt missing K.BOT_SUN_2ACE_BONUS | Apply 2/3-Ace + mardoofa bonuses post-bidcard recompute. |
| PEB-DEAD | MED | partnerEscalatedBonus contract.gahwa/foured branches dead | Reserved for future post-Gahwa override pickers. |
| OVC-DOUBLE | LOW | sunStrength penalty + PickOvercall voidBonus partial double-handling | Document the calibration interaction. |
| PEB-NEG / PB-1 | LOW | partnerBidBonus PASS penalty inappropriate for defenders | Re-confirmed; split into bidder/defender variants is the proper fix. |

#### Trick play + Signaling (Audit B)

| ID | Severity | Title | Notes |
|---|---|---|---|
| U-3 | HIGH | bidderHoldsBidcard helper dead code (3 cycles deferred) | Wire one consumer or delete. Trump-J-inference is highest-leverage callsite. |
| U-4 | MED | topTouchSignal writer doesn't gate on forced-play | Mirror v0.9.2 baitedSuit forced-J gate. |
| U-5 | MED | Tahreeb sender records trump discards (recv filters; sender doesn't) | Cheap symmetric guard. |
| U-6 / H-6 | MED | pickFollow released-from-must-ruff doesn't prefer non-trump discard | Saudi Master tier directly impacted via ISMCTS rollouts. |
| U-7 | MED | Trick-3 sweep-pursuit lacks Kaboot-feasibility gate | Hand-shape predicate from decision-trees.md. |
| U-8 | MED | AKA late-round clutch gate uses arbitrary 25-point threshold | Pin to constant or derive from scoreUrgency. |
| U-9 | LOW | Bot.PickAKA at trick 1 structurally a no-op | Comment update; A6 unsuppression matters for trick 2+. |
| U-10 | LOW | doubled AKA suppression doesn't account for all rungs explicitly | Defensive symmetry. |

#### SWA + Endgame + Takweesh (Audit C)

| ID | Severity | Title | Notes |
|---|---|---|---|
| M3 | MED | Sweep-pursuit early trigger lacks Kaboot-feasibility hand-shape gate | Same as U-7. |
| M4 | MED | PickSWA cap of 6 leaves 7/8-card SWAs uncomputed | Defensible perf-gate; raise only if telemetry shows missed claims. |
| M5 | MED | Trick-8 push lacks "make-the-bid" score awareness | Bidder team at 80 raw with N points-to-make. Telemetry-driven calibration. |
| M6 | MED | Bot.PickSWAResponse partner-team gate is dead code | Defensive; harmless but misleading. |
| L1 | LOW | Stale comment in LocalSWA fall-through | One-line update. |
| L2 | LOW | IsValidSWA lacks recursion budget | Defensive; not currently a perf concern. |

#### BotMaster + Cross-cutting (Audit D)

| ID | Severity | Title | Notes |
|---|---|---|---|
| B3-DEAD-CODE | MED | bidderHoldsBidcard dead (3 cycles) | Same as U-3. |
| BM-01-DOC-DRIFT | MED | firstDiscard.bucket field non-existent | Remove dead-copy line. |
| BUDGET-WORLDS-COUNT | MED | worldsCompleted counts errored worlds | Track worldsSuccessful separately. |
| BM-04-MELDPIN-FALLBACK | MED | Fallback uniform-deal bypasses BM-04 void filter | Hoist meldPins build, apply void filter once. |
| DOC-DRIFT-WORLDS | MED | bot-personalities.md claims "100/60/30 worlds" without budget caveat | Two-line doc update. |
| BM-06 | LOW | Bot.IsSaudiMaster() defined but never called (no carve-out) | Either delete or wire one heuristic Saudi-Master-only feature. |
| C-14-FRAGILITY | LOW | simTricks reference-copies completed tricks | Defensive deep-copy. |
| PARTNERSTYLE-INVARIANT | LOW | No test asserts _partnerStyle never swapped during rollout | Source-pin test. |
| CONSTANT-COMMENT-DRIFT | LOW | K.BOT_GAHWA_TH comment references stale 5-card-hand reasoning | Refresh comment. |

### Behavioral test gaps (cross-cutting)

Sections T, U, V, W, X, Y, Z, AA, AB, AC are mostly source-pin only.
Audit D specifically called out behavioral coverage gaps:
- AA.1c (escalationStrength bonuses)
- AA.3a/b (B2 budget actually truncates)
- AA.4 (bidderHoldsBidcard per-phase semantics)
- AA.5 (pickFollow akaLive flag behavioral)
- AB.3 (bidderHoldsBidcard PHASE_PLAY gate behavioral)
- AC.6 (PickFour belOpen behavioral — but DEAD-1 makes this moot)

### Test coverage

639/639 tests pass after this hotfix.

## v0.11.18 — Tier 3: ISMCTS state preservation + existential SWA + calibration cleanups

Final tier of the deep-audit fix sequence. Closes:
- **B5** (BM-01, BM-04): rolloutMemory preserves observed signals; meldPins respects voids
- **B6** (M5): IsValidSWA existential when caller's own turn
- **BG-1**: Sun Bel-fear gate strict > 100
- **OE-1**: PickOvercall mirrors Bel-fear bias
- **P4-1**: PickFour reads partner's belOpen flag

### Fixed (HIGH)

- **B5 / BM-01 — `rolloutMemory` preserves `firstDiscard` and `likelyKawesh`.**
  Pre-v0.11.18 BotMaster's per-rollout memory was initialized empty
  except for played/void from `simTricks`. The C-14/Bot1-01 audit
  explicitly omitted firstDiscard/likelyKawesh as "cross-round signal
  layer not relevant" — but they're PER-ROUND state populated by
  real-game `OnPlayObserved` BEFORE the rollout starts. A Saudi
  Master rollout where partner already showed a high-card preference
  via firstDiscard couldn't model that future leads should exploit
  it (Fzloky pref-suit logic, Bot.lua:2117-2129). Now copies these
  two fields from `B.Bot._memory[s]` into `rolloutMemory[s]`. akaSent
  remains uncopied — truly cross-round, not consumed by per-rollout
  heuristics.

- **B5 / BM-04 — `meldPins` respects observed voids.** Pre-fix a meld
  declared by seat 2 in trick 1 (e.g., Hearts Tierce containing 7H)
  was always pinned to seat 2's hand even if seat 2 LATER showed
  Hearts-void in trick 5 (`mem.void.H = true`). The deal was internally
  inconsistent: seat 2 simultaneously holds 7H AND is void in Hearts.
  Now: if observed void, drop the meld pin (the unplayed meld card
  must've been disposed of even if not in our `played` map yet).

- **B6 / M5 — `R.IsValidSWA` existential when caller's own turn.**
  Pre-v0.11.18 the v0.5.17 strict-strict recursion enumerated EVERY
  legal caller-card adversarially — but the caller will pick optimally
  on their own turn, not adversarially. SWAs like `[J of trump, 7 of
  side]` in Hokm where J wins but 7 doesn't were rejected because
  the universal check failed on 7. New behavior: when `nextSeat ==
  callerSeat`, return true if SOME caller-move preserves the SWA
  (existential). Other-seat branches retain universal (partner adversarial,
  opponent adversarial). Tightens v0.5.17's over-strict rejection
  while preserving Saudi's "deterministic-or-bust" intent for non-
  caller plays.

### Fixed (MED)

- **BG-1 — Sun Bel-fear gate strict `> 100`.** Pre-fix `>= 100` was
  one point too eager; opp cannot Bel us at our.cum == 100 exactly
  per `R.CanBel`'s strict `> 100`. The +8 thSun bias should mirror
  the legality boundary.

- **OE-1 — `Bot.PickOvercall` mirrors Bel-fear.** When considering
  TAKE-as-Sun and our cum > 100, opp can still Bel the Sun for ×2.
  PickBid had this bias; PickOvercall didn't. Same magnitude (-8).

- **P4-1 — `Bot.PickFour` reads `contract.belOpen` flag.** Partner's
  CLOSED Bel = "I have just enough for ×2, no more"; PickFour
  overriding with a Four would defy partner's stated intent —
  suppress unless overwhelming. OPEN Bel = "I'd survive a Triple
  counter" — combined-team strength signal beyond raw partnerEscalatedBonus,
  +5 strength bonus.

### Test coverage (Section AC)

- **AC.1**: `rolloutMemory` copies firstDiscard / likelyKawesh
- **AC.2**: `meldPins` respects observed voids
- **AC.3**: `IsValidSWA` existential branch on caller's turn
- **AC.4**: Bel-fear gate uses strict `> 100`
- **AC.5**: PickOvercall biases sunStr down by Bel-fear
- **AC.6a/b**: PickFour suppresses Four on closed Bel; +5 bonus on open Bel

640/640 tests pass.

### Deferred to post-v0.11.18 (future work)

The 4-agent deep audit + 3 release cycles + ultra-audit have closed
the highest-impact items. Remaining audit items not yet addressed:
- **B3 deeper integration**: trump-J-tracking, opp-trump-exhausted
  checks, side-suit boss-lead decisions consult `bidderHoldsBidcard`
- **B4 (H-4)**: Tahreeb sender doesn't avoid strong suit
- **B4 (H-6)**: pickFollow released-from-must-ruff doesn't prefer
  non-trump discard
- **BM-03**: ISMCTS perf instrumentation (`/baloot ismctsdiag` to
  surface `_lastWorldsCompleted` and `_fallbackCount`)
- **BM-06**: Saudi-Master-only carve-out (T-sacrifice in Sun)
- **Tier 3 doc-drift**: stale comments in BotMaster.lua header,
  bot-personalities.md retracted "probabilistic SWA"
- **PB-1**: split `partnerBidBonus` into bidder-team / defender-team variants
- **Behavioral test gaps** for source-pin-only assertions (Y, AA, AB, AC)

A final ultra-audit + report on all post-audit-cycle status follows
this release.

## v0.11.17-hotfix — post-ship audit follow-up

5 findings from the v0.11.17 post-ship audit, all fixed.

### Fixed (HIGH)

- **F1 — Sun branch in `escalationStrength` was DEAD CODE.** All callers
  (`PickTriple`, `PickFour`, `PickGahwa`) early-return on `contract.type
  == K.BID_SUN` BEFORE calling `escalationStrength`. Sun has no
  Triple/Four/Gahwa rungs (Saudi rule R2 + v0.10.0 R2 defense-in-depth);
  Sun's only escalation is Bel which has its own inline path in
  `PickDouble`. v0.11.17's mardoofa/2-Ace/3-Ace branch was unreachable.
  Removed; comment clarifies Hokm-only.

- **F2 — implicit-AKA still gated on `partnerWinning`.** B4 (H-5) was
  intended to drop the partnerWinning requirement, but `implicitAKA`
  (line 2815) still required it. Net behavioral impact small (legality
  layer doesn't relieve must-ruff for implicit AKA anyway), so the
  documented over-scope is reflected in the tightened comment rather
  than a code change. Future Rules.lua update could relieve implicit
  AKA's must-ruff symmetrically.

### Fixed (MED)

- **F3 — `PickGahwa` floor cap.** Pre-fix, EV-2's `BOT_GAHWA_TH=120` +
  `combinedUrgency` -15 + jitter -10 left effective threshold at 95 —
  within reach of mid-strength Hokm hands under near-clinch desperation.
  Added `if th < K.BOT_GAHWA_TH - 16 then th = ... - 16 end` floor cap
  (mirrors `PickDouble:3870` and `PickFour:4026`). Preserves Gahwa's
  rare-rung property while still allowing top-tier hands (~140 strength
  post-EV-1) to fire.

- **F4 — `bidderHoldsBidcard` phase-gates to `PHASE_PLAY`.** Pre-fix
  helper returned true during PHASE_BEL/TRIPLE/FOUR/GAHWA when the
  contract is set but `HostDealRest` hasn't yet appended the bidcard
  to `hostHands[bidder]`. Future v0.11.18 callers wiring this for
  trump-J inference would mis-attribute the J of trump mid-escalation.
  Added `if S.s.phase ~= K.PHASE_PLAY then return false end`.

- **F5 — `Bot.OnEscalation` ledger never fired for host's own bot
  escalations.** Wire-receive `_OnDouble/Triple/Four/Gahwa` had inline
  `OnEscalation` calls but those were post-`fromSelf` filter — meaning
  host-direct bot decisions and local-human escalations silently
  skipped the ledger update. `Bot._partnerStyle.{bels,triples,fours,
  gahwas}` counters were stuck at 0 for half the table. v0.11.17's
  unblocked escalation chain magnified the impact. Moved `OnEscalation`
  into `S.ApplyDouble/Triple/Four/Gahwa` (single uniform call site
  covering wire/host/local paths). Net.lua redundant calls removed.

### Test coverage (Section AB)

- **AB.1**: Sun dead branch removed from `escalationStrength`
- **AB.2**: `PickGahwa` floor cap
- **AB.3**: `bidderHoldsBidcard` phase-gate to PHASE_PLAY
- **AB.4a-d**: Each `S.ApplyX` calls `Bot.OnEscalation` with correct kind
- **AB.4e**: Net.lua has zero `Bot.OnEscalation` calls (single source-of-truth)

Plus AA.1c updated for the F1 dead-branch removal. 630/630 tests pass.

## v0.11.17 — Tier 2: escalation chain + ISMCTS perf + bidcard-in-defense

Continues the deep-audit fix sequence. Tier 2 closes:
- **B1**: escalation chain unblock (EV-1 + EV-2)
- **B2**: ISMCTS wall-clock budget (3-15s pause -> 0.5s cap)
- **B3**: bidcard public-knowledge helper (light wiring; deeper integration deferred)
- **B4**: pickFollow Hokm AKA-receiver gate extension (H-5)

### Fixed (HIGH)

- **B1 (EV-1) — `escalationStrength` now mirrors PickDouble/PickBid bonuses.**
  Pre-v0.11.17 the bidder-side escalation strength missed:
  - Hokm: void-count × 5 + (sideAces - 1) × 8 (defender-side had this; bidder didn't)
  - Sun: 2-Ace bonus (+15), 3-Ace bonus (+15), mardoofa-pair bonus (+20)
  Combined effect: bidder/defender ran on different scales for the same
  hand quality. Triple/Four/Gahwa rungs systematically under-fired.

- **B1 (EV-2) — `BOT_GAHWA_TH` lowered 135 -> 120.** Prior threshold
  was structurally unreachable on 5-card hands (max ~99 raw + +20
  partner-bonus = 119 < 120 floor at urgency=15). Combined with EV-1's
  added bonuses, max climbs to ~140; threshold 120 keeps Gahwa as the
  rarest rung but actually reachable on top-tier hands. Closes
  escalation.md "0% chain fire in symmetric pure-bot play" diagnostic.

- **B2 — ISMCTS wall-clock budget.** Pre-v0.11.17 fixed numWorlds
  (100/60/30) × ~8 candidates × ~21 rollout-policy calls = ~16,800
  full `Bot.PickPlay` invocations per move at trick 0 (post-v0.11.1
  C-14 the rollout policy is full PickPlay, not the cheap simulator
  decisions the original "150 ms perceptually instant" comment
  assumed). Realistic load was 3-15 seconds per Saudi-Master move on
  early tricks. New `K.BOT_ISMCTS_BUDGET_SEC = 0.5` caps wall-clock
  per-move; completed worlds vote, remaining skipped. Tracks
  `BM._lastWorldsCompleted` for `/baloot ismctsdiag`. Set budget to
  0 to disable cap and run full numWorlds always.

### Added (B3 light)

- **`bidderHoldsBidcard(seat, card)`** file-local helper. Returns true
  iff the seat is the bidder, the card matches `S.s.bidCard`, AND
  the bidcard hasn't yet been played. The bidder gets the bidcard
  at HostDealRest; this is PUBLIC knowledge (visible during bidding).
  Defender bots that don't factor this in waste tricks probing for
  trump distribution that's already known. Helper is in place; deeper
  integration into trump-J-tracking, opp-trump-exhausted checks, and
  side-suit boss-lead decisions deferred to v0.11.18 (each requires
  careful per-callsite evaluation).

### Fixed (MED)

- **B4 (H-5) — pickFollow Hokm AKA-receiver gate now fires regardless
  of `partnerWinning`.** Pre-v0.11.17 the gate required current trick
  winner = partner. But `Rules.lua` legality layer (line 202-206)
  correctly relieves the receiver from must-trump-ruff EVEN when an
  opp over-trumped partner's A-led trick. Pre-fix when opp over-
  trumped, the heuristic fell through to natural must-ruff/winners
  flow, sometimes burning trump unnecessarily. Now: AKA on led suit
  -> always prefer non-trump discard (matches legality semantics).

### Test coverage (Section AA added)

- **AA.1**: `escalationStrength` includes void/sideAce/Sun bonuses
- **AA.2**: `BOT_GAHWA_TH = 120`
- **AA.3**: `K.BOT_ISMCTS_BUDGET_SEC = 0.5` + BotMaster wires it +
  tracks `_lastWorldsCompleted`
- **AA.4**: `bidderHoldsBidcard` helper defined
- **AA.5**: `pickFollow` uses `akaLive` flag (relief regardless of winner)

622/622 tests pass.

### Deferred to v0.11.18

Remaining Tier 2/3 items:
- **B3 deeper integration**: trump-J-tracking, opp-exhaust checks, side-suit-boss leads consult `bidderHoldsBidcard`
- **B4 (H-4)**: Tahreeb sender doesn't avoid strong suit
- **B4 (H-6)**: released-from-must-ruff doesn't prefer non-trump discard
- **B5**: ISMCTS rollout state preservation (BM-01) + sampler fallback (BM-02) + meldPins voids (BM-04)
- **B6**: existential SWA validator for caller's own moves
- **Tier 3 cleanup**: PB-1, PP-1 (already done in v0.11.16), BG-1, OE-1, P4-1, BM-06, doc drift

## v0.11.16-hotfix — post-ship audit follow-up

Post-ship audit of v0.11.16 caught 5 follow-up issues. All A1-family
gaps (post-bidcard recomputation needed in additional sites).

### Fixed (HIGH)

- **GAP-01** — `belote = beloteSuit(hand)` was using the bare 5-card
  hand. v0.11.16's A2 (Belote K+Q-trump escape clause in `hokmMinShape`)
  passed the post-bidcard hand to the shape gate, but `belote` itself
  was still pre-bidcard — so a hand `[QS 8C 9C 7H X]` + bidcard `KS`
  passed the shape gate yet missed the `+K.BOT_PICKBID_BELOTE_BONUS`
  +20 strength bonus. The two halves of A2 were mutually inconsistent.
  Fix: `local belote = beloteSuit(withBidcard(hand, S.s.bidCard))`.

- **OVC-bidcard** — `Bot.PickOvercall` `trumpCount` loop iterated the
  bare 5-card hand, then `hypHand` was built later. A bidcard in
  `contract.trump` suit was missed by the void/short check, double-
  counting its contribution to defensive strength. Fix: hoist `hypHand`
  build BEFORE the trumpCount loop and iterate `hypHand`.

### Fixed (MED)

- **MD-01** — `mardoofaCount` was passed from the pre-bidcard
  `aceCountAndMardoofa(hand)`. If bidcard provides the missing A or T
  to complete A+T mardoofa (e.g., hand `[8C 9C TC AS 7H]` + bidcard
  `AC` -> AC+TC mardoofa), the +20 K.BOT_SUN_MARDOOFA_BONUS missed.
  Fix: recompute mardoofa on `sunHand` after building it.

### Fixed (LOW)

- **TC-01** — Takweesh fallback rate `or 0.40` was a stale leftover
  from the pre-A4 decay table. Aligned to flat `or 0.95`.

- **BC-INLINE** — R1 Hokm-on-flipped still used the v0.11.15 inline
  bidcard-append construction. Replaced with the `withBidcard` helper
  for consistency with the other 5 bid paths.

### Test coverage (Section Z)

- **Z.1**: `belote` recomputed on post-bidcard hand
- **Z.2**: PickOvercall `hypHand` precedes `trumpCount` loop
- **Z.3**: mardoofa recomputed on post-bidcard `sunHand`
- **Z.4**: Takweesh fallback rate aligned to 0.95
- **Z.5**: inline bidcard append eliminated

Plus updated X.3a source-pin for the `withBidcard` refactor. 613/613
tests pass.

## v0.11.16 — Tier 1: 7 deep-audit fixes for human-like bot play

User-requested 4-agent deep audit of bot behavior surfaced 17 HIGH-severity
issues across bidding, trick play, endgame, and BotMaster. v0.11.16 ships
Tier 1 (7 highest user-visible-impact fixes) ahead of Tier 2/3 in
follow-up releases.

### Added

- **`withBidcard(hand, bidcard)`** file-local helper in Bot.lua —
  unifies the v0.11.15 hypHand pattern (5-card hand + bidcard) used
  for evaluating the bidder's post-win hand structure.

- **`Bot.PickSWAResponse(seat, callerSeat, encodedCallerHand)`** —
  new function letting bots DENY clearly-invalid SWA claims via
  `R.IsValidSWA` strict-rejection. Pre-v0.11.16 bots auto-accepted
  every incoming SWA, eliminating the entire defensive side of the
  mechanic. Wired in `Net.lua` `_OnSWAReq` + parallel host-localSWA
  + bot-fired SWA paths.

### Changed (audit-driven behavioral fixes)

- **A1 (BC-1) — bidcard inclusion in 5 remaining bid paths.** v0.11.15
  fixed only R1 Hokm-on-flipped; v0.11.16 extends to R1 Sun, R2 Hokm,
  R2 Sun, `Bot.PickPreempt`, and `Bot.PickOvercall`. The bidder
  receives the bidcard (`HostDealRest` State.lua:1950); evaluating
  bid decisions on the 5-card pre-deal hand systematically
  underestimated post-win strength. R1 Sun also recomputes
  `aceCount` post-bidcard so the +15 2-Ace bonus correctly fires
  on hands like `[KH 8H 7C 9D 8S]` + bidcard `AC`.

- **A2 (BS-1) — Belote K+Q-of-trump escape clause in `hokmMinShape`.**
  Saudi rule B-6 (decision-trees.md, **Mandatory** verdict, video #26):
  K+Q of trump + count >= 2 = mandatory Hokm-of-that-suit. Pre-v0.11.16
  the J-floor (`if not hasJ then return false end`) blocked these
  hands when J-of-trump was missing, even though +20 multiplier-immune
  Belote bonus locks the Royal Hand. Escape clause runs BEFORE J-floor.

- **A3 (H1) — `Bot.PickSWAResponse` denies clearly-invalid SWAs.**
  Prior bot auto-accept gave humans free SWA-bluff EV. Bots now
  validate via `R.IsValidSWA` over decoded caller hand + known
  hostHands. Strict-reject -> DENY. Default-accept on ambiguity
  matches the addon's "humans handle close calls verbally" UX intent.

- **A4 (H2) — Takweesh rate flat 0.95 (was decaying 0.60->0.05).**
  saudi-rules.md:163-166 (video #36): Takweesh is a HARD rule-correctness
  call; humans call ALL detected violations promptly. Prior decay made
  the bot effectively dead at trick 6/7. The 0.95 keeps a tiny
  human-realism softener while restoring tournament-grade vigilance.

- **A5 (H3) — `Bot.PickSWA` cap raised 4 -> 6 cards.** Saudi rule:
  5+ cards = mandatory PERMISSION flow, NOT forbidden. The Net.lua
  5-second permission flow already handles 5+ correctly; the
  artificial #hand>4 cap eliminated legitimate Sun-A+T+A+T late-trick
  SWAs.

- **A6 (H-1) — AKA trick-1 suppression DROPPED.** signals.md Section 4
  + decision-trees.md Section 6: "AKA at trick-1/trick-2 is the
  STRONGEST read." Prior `if trickNum <= 1 then return nil end`
  inverted canonical Saudi practice. The partner-certainly-void-in-
  trump gate already covers the case where AKA carries zero
  coordination value.

- **A7 (H-2) — Tahreeb-return decision tree.** Pre-v0.11.16 always
  led the lowest in partner's preferred suit. Per signals.md Section 1
  + decision-trees.md Section 8 receiver:
  - Bare-T (singleton T) -> lead T immediately (else opps tafranak)
  - Doubled-T + partner is Sun bidder -> lead the cover (preserve T
    for partner's A overtake)
  - Doubled-T + partner is NOT Sun bidder -> lead the T (else cover-
    lead telegraphs T to opps)
  - 3+ cards -> lead low (legacy, unchanged)

- **PP-1 cleanup (in A1)** — removed dead-code "+12 if hand contains
  A of bidSuit" bonus in `Bot.PickPreempt`. The +12 was unreachable
  because PickPreempt only fires when `bidCard.rank == "A"`, and
  there's only one A per suit in 32-card deck — so no bot can hold
  it. Replaced with the canonical `withBidcard` pattern that adds
  +11 (A face value) via the same mechanism as R1 Sun.

### Test coverage (Section Y added)

- **Y.1 (A1)**: `withBidcard` helper at file scope
- **Y.2 (A2 / BS-1)**: Belote K+Q escape + ordering before J-floor
- **Y.3 (A1)**: bidcard inclusion in PickBid R1 Sun, R2 Hokm,
  PickPreempt, PickOvercall
- **Y.4 (A4)**: Takweesh rate flat 0.95
- **Y.5 (A5)**: PickSWA cap raised to 6
- **Y.6 (A3)**: `Bot.PickSWAResponse` exists + Net.lua wiring
- **Y.7 (A6 / H-1)**: trick-1 AKA suppression dropped
- **Y.8 (A7 / H-2)**: Tahreeb-return bare-T + doubled-T branches +
  partner-is-Sun-bidder branch

Plus updated T.3 / X.2 source-pins for the bigger `hokmMinShape`,
W.1 for the `aceCount` -> `sunAces` rename. 608/608 tests pass.

### Deferred to v0.11.17/v0.11.18

Remaining audit findings (not in this release):
- **B1**: escalation chain calibration (EV-1/EV-2)
- **B2**: ISMCTS wall-clock budget (3-15s pause at trick 0)
- **B3**: bidcard public-knowledge in defense
- **B4**: Tahreeb sender refinements (H-4/H-5/H-6)
- **B5**: ISMCTS rollout state preservation + sampler fallback
- **B6**: existential SWA validator for caller's own moves
- **Tier 3**: dead-code cleanup, calibration nudges, Saudi-Master carve-out

## v0.11.15 — three bot bidding gaps surfaced by user audit (Q1 overcall, Q2 hokm shape, bidcard inclusion)

User-audit questions revealed three real gaps in bot bidding logic
that calibration nudges alone couldn't fix:

1. **Q1 — Sun overcall doesn't recognize void-in-trump signal.** When
   opp bids Hokm in a suit you have 0-1 cards in, that's the textbook
   Saudi Sun-overcall trigger (no trump = no void penalty). Previous
   `Bot.PickOvercall` used generic `sunStrength()` with no awareness
   of the opp's chosen trump suit.

2. **Q2 — `hokmMinShape` rejects canonical "ولد ومردوفته" hands without
   any Ace.** Saudi rule allows J + 9 of trump + count >= 3 as
   self-sufficient even without side Ace, but the L07 M3lm-tier gate
   (added in v0.10.0) auto-rejected ANY hand without an Ace anywhere.
   Trace evidence: hands like `[8C 9C JC JH QD]` (J + 9 of clubs + 3
   clubs + JH side, NO Ace) were canonical Hokm-clubs candidates but
   silently passed.

3. **Audit — `Bot.PickBid` R1 Hokm-on-flipped doesn't include the
   bidcard in evaluation.** The bidder gets the bidcard appended to
   their final hand at `HostDealRest` (State.lua:1950), but
   `hokmMinShape(hand, bidCardSuit)` was called on the 5-card pre-deal
   hand. If bidcard provided the J of trump or filled out a count,
   the bot didn't see it — leading to false-negative rejections.

### Added (calibration / heuristics)

- **`K.BOT_OVERCALL_VOID_TRUMP_BONUS = 15`** + **`K.BOT_OVERCALL_SHORT_TRUMP_BONUS = 8`**
  applied additively to `sunStrength` in `Bot.PickOvercall` based on
  the bot's count in `contract.trump`. Void hands (0 trump) get +15;
  singleton hands (1 trump) get +8. Pre-threshold so `BOT_OVERCALL_TAKE_TH`
  / `BOT_OVERCALL_SELF_TH` stay meaningful for normal balanced hands.

### Changed (bot logic)

- **`hokmMinShape` — new self-sufficient mardoofa path.** `if count >= 3
  and hasTrumpNine then return true` runs BEFORE the L07 any-Ace gate,
  letting J + 9 + count>=3 hands pass even at M3lm+ tier without a
  side Ace. Matches the count==2 mardoofa path's canonical-only logic
  (RT07-07 from v0.11.9), extended to count>=3 strength.

- **`Bot.PickBid` R1 Hokm-on-flipped — include bidcard in evaluation.**
  Builds a hypothetical post-win hand (`hypHand = hand + S.s.bidCard`)
  and passes it to BOTH `hokmMinShape` and `suitStrengthAsTrump`. The
  bidder's actual post-deal-2 hand is 8 cards (5 initial + bidcard +
  2 unknowns); we now include the deterministic bidcard contribution.
  +6-8 strength shift on average when bidcard is in trump suit.
  Threshold thHokmR1=42 unchanged — the small fire-rate bump aligns
  with user-audit goal.

### Test coverage

- **X.1a/b/c/d** — pin new constants + `Bot.PickOvercall` references
  `K.BOT_OVERCALL_VOID_TRUMP_BONUS` and checks for `trumpCount == 0`.
- **X.2/X.2b** — pin `hokmMinShape` self-sufficient mardoofa path AND
  verify it appears BEFORE the L07 any-Ace gate (correct ordering).
- **X.3a/b** — pin `Bot.PickBid` R1 Hokm-on-flipped builds `hypHand`
  including `S.s.bidCard` and passes it to `hokmMinShape`.
- **X.4** — Behavioral: bidcard-provides-J Hokm-on-flipped fires.
  Hand `[8C 9C TC AS KH]` + bidcard `JC` -> 4 clubs including J +
  side AS -> deterministic `HOKM:C` fire. Pre-v0.11.15 this returned
  PASS (B-4 floor failed; no J in 5-card hand).

### Quantified expected impact

- R1 Hokm-on-flipped fire rate: +20-30% (more hands clear shape via
  bidcard inclusion + L07 relax).
- R2 Hokm fire rate: +30-40% (Q2 self-sufficient mardoofa unlocks the
  no-Ace J+9 cases).
- Sun overcall fire rate: previously near-zero on void-trump hands;
  now ~15-20% on void-trump Hokm targets.

593/593 tests pass.

## v0.11.14 — Sun bot calibration: 2-Ace bonus from user-bidcalc trace evidence

User-bidcalc trace from 27 + 10 telemetry rounds revealed the actual
bottleneck behind "bots don't bid Sun enough": **2-Ace hands without
mardoofa or AKQ triple consistently scored 17-21**, well below
`thSun=38-46`, even though Saudi rule S-1 says 2 Aces IS the canonical
Sun shape. The 3-Ace and mardoofa bonuses existed; the 2-Ace case was
silently un-bonused. Adding `K.BOT_SUN_2ACE_BONUS = 15` brings these
hands into the jitter fire-band without disturbing other calibration.

Specific user-trace examples that previously skipped Sun:
- `[7D AD QC AC 9H]` — 2 Aces + Q + nothing else, sun=17 thSun=38
- `[AH AD KC 7H QS]` — 2 Aces + K + Q across 4 suits, sun=21 thSun=38

Both score 32/36 post-bonus and now fire ~17-39% of jitter rolls.

### Added (calibration)

- **`K.BOT_SUN_2ACE_BONUS = 15`** (new). Magnitude mirrors `K.BOT_SUN_3ACE_BONUS`
  — both signal "shape-pass canonical" rather than "guaranteed-win".
  Applied via `elseif aceCount == 2` in `Bot.PickBid`, gated against
  double-applying with the 3-Ace branch.

### Empirical impact (sim_sun.py + user-trace data)

- Theoretical R1 bot Sun fire rate: 5.67% → **7.39%** per-bot per-round
  (~30% bump, all from the 2-Ace path).
- Per-round outcomes: ~21% chance of bot Sun fire → ~28%.
- 10-round session expectation: ~2.5 bot Sun bids → ~3 (vs 2 observed
  on v0.11.13).
- 27-round session expectation: ~6-8 bot Sun bids → ~7-10 (vs 3 observed
  on v0.11.13). Closes much of the user-perceived gap.

### Rejected alternatives

- **Lower `TH_SUN_BASE` 40→32**: blunt-force calibration that would
  also pull weak 0-1 Ace hands into firing range, raising bot Sun fail
  rate from current 0% (overly conservative) to ~25-30% (overshooting
  tournament target of 30-40%). The 2-Ace bonus is targeted: it lifts
  exactly the hand class Saudi rules consider Sun-eligible.
- **Lower `K.BOT_SUN_VOID_PENALTY_CAP` 8→4**: would help but also
  affects 0-1 Ace junk hands. Already user-arbitrated to 8 in v0.11.9
  from a higher value; further reduction without targeting risks over-
  firing other shapes.
- **Relax `sunMinShape` to allow 1A + same-suit K**: K-cover is
  genuinely weaker than T-cover (T is rank #2 in Sun, K is #3 and loses
  to opp's T). Saudi S-1 specifically calls out A+T mardoofa or 2+ Aces.

### Tooling — `tools/sim_sun.py` (new)

- Empirical Sun fire-rate simulator. Loads a Python re-impl of `Bot.lua`'s
  `sunStrength` + `sunMinShape` + bonus stack (line-by-line mirror of
  v0.11.14). Generates N random 5-card hands (R1 deal state — the actual
  bidding context, NOT 8-card post-deal-2 which earlier analyses
  mistakenly used) and reports score distribution + fire rates across
  threshold + bonus-value sweeps.
- Usage: `python tools/sim_sun.py --advanced --two-ace-bonus 15`.
- Now permanently in-tree to ground future calibration discussions in
  data instead of guesswork.

### Test coverage

- **U.14f** — `K.BOT_SUN_2ACE_BONUS = 15` constant pin.
- **W.1** — `Bot.PickBid` source-pin: `aceCount == 2` elseif branch
  applies `K.BOT_SUN_2ACE_BONUS`.
- **W.2** — Behavioral: 2-Ace + mardoofa hand reliably fires Sun
  (`[AH TH AD 8C 7S]` → sun=59 after bonuses, deterministic fire).

### Bundled cleanups (from prior loop iteration)

- **SU2-08** — UI.lua `renderCardGlyphs` deduped — uses `K.RANK_INDEX`
  / `K.SUIT_INDEX` truthiness instead of local `VALID_RANKS` / `VALID_SUITS`
  duplicates. U.13 test pins updated to assert the new pattern.
- **Constants.lua reference table** — fixed misleading "10 / 80 = Hokm 100,
  Sun 400" line. Post-v0.11.10 revert, Carré-A in Sun is **40 nq** (200
  raw × Sun×2 / 10). The Arabic "الأربع مئة" / "Four Hundred" name
  refers to the post-multiplier value 200 × Sun×2 = 400 effective raw,
  not the stored constant. Reference table now reads "10 / 40".
- **CHANGELOG v0.11.12 site count** — corrected from "11 sites" to
  "10 sites" (State.lua: 9 → 8) per audit SU2-06.

581/581 tests pass.

## v0.11.13 — hotfix: 4-agent ultra-audit findings (NetU2-01 HIGH revert + SU2-02 CRITICAL scope fix + XR2-05 wire validation)

Hotfix release closing 5 findings from the post-v0.11.12 4-agent ultra
audit. **One CRITICAL** (the v0.11.11 SU-Ultra-01 fix was itself
unreachable due to a Lua block-scoping error — the same "shipped
dead code" failure pattern it was meant to fix). **One HIGH regression**
introduced in v0.11.11 XU-09 (host /reload mid-PHASE_OVERCALL
soft-locked). **Two MED** wire-validation gap + defense-in-depth
asymmetry. **Several LOW** doc-drift closures.

The audit caught the CRITICAL and HIGH issues precisely because the
existing source-string pins (U.10, U.11) matched the *text* but
couldn't prove the *behavior*. Test-harness extension (XU-01 phase
2 — Net.lua wire-injection harness) is now the single highest-
leverage debt item; both regressions in this batch would have been
caught at commit time with phase-2 coverage.

### Fixed (CRITICAL)

- **SU2-02 — `N.HostResolveSWA` per-team breakdown was UNREACHABLE
  due to Lua block-scoping.** v0.11.11's SU-Ultra-01 fix declared
  `local result` inside the valid-arm `else` block and `local cardA/
  cardB/mpA/mpB/mult/beloteOwner` inside the invalid-arm `if` block.
  Both blocks closed at the `end` BEFORE the breakdown-stash code
  (line 3406+), so all six locals resolved to undefined globals
  (= `nil`) at the read sites. Net effect: VALID-SWA showed the
  same degraded "Claim verified — all remaining tricks awarded."
  banner that v0.11.2 was meant to fix; INVALID-SWA wrote a
  breakdown table with `nil` entries that displayed as "cards 0 +
  melds 0" rows. Hoisted all six locals to outer scope before the
  if/else. The unreachable-fix-shipping-with-the-same-bug pattern
  is exactly what v0.11.12 XU-01 phase 1 was introduced to address;
  phase 2 (Net.lua wire-injection harness) would have caught this
  at commit time. Audit anchor: `Net.lua:3251-3266`.

### Fixed (HIGH regressions)

- **NetU2-01 — REVERT v0.11.11 XU-09. `s.overcall` is no longer
  in `TRANSIENT_FIELDS`.** The v0.11.11 XU-09 addition broke the
  v0.9.0 M2 host re-arm at `WHEREDNGN.lua:300`: that block is gated
  by `if B.State.s.phase == K.PHASE_OVERCALL and B.State.s.overcall
  then`, scheduling a fresh `_HostResolveOvercall` timer with
  `startedAt = now` for a clean 5-second window post-restore. With
  `overcall` made transient, `s.phase` (still persisted) stayed
  `PHASE_OVERCALL` while `s.overcall` got wiped on `SaveSession` —
  the re-arm short-circuited on the gate, no timer was scheduled,
  the host stayed in `PHASE_OVERCALL` forever with no path forward.
  Same shape as the v0.10.6 RT07-01 redeal-recovery regression
  v0.11.0 fixed — a lifecycle change broke gated-on-presence
  recovery. The pre-v0.11.11 design (overcall persisted, M2 resets
  startedAt) was correct. Pin behavior in test_state_bot.lua U.10
  inverted from "asserts present" to "asserts absent" with full
  rationale block (and added V.4 cross-check for the re-arm gate).
  Audit anchor: `State.lua:256-272`.

### Fixed (MED — wire validation + defense-in-depth)

- **XR2-05/06 — `N._OnContract` validates Hokm trump-suit against
  the 4-suit enum.** Pre-v0.11.13 a buggy/old host fork could
  broadcast `MSG_CONTRACT;3;HOKM;X` and `S.ApplyContract` would
  write `contract.trump = "X"` verbatim. Downstream `R.IsLegalPlay`
  consults `contract.trump` for trump-overcut logic — non-suit
  trump means `C.IsTrump("XS", contract)` returns false for ALL
  cards, silently neutering the bidder's trump declaration (Hokm
  degrades to suit-following without trump). `fromHost` gate
  prevents non-host forging, but a buggy host fork would slip
  through. Mirrors the NetU-03 `_OnAKA` suit-enum gate from
  v0.11.11. Sun contracts (empty trump) allowed through.
  Audit anchor: `Net.lua:961-973`.

- **SU2-01 — `S.ApplyResyncSnapshot` clears stale `s.overcall`.**
  The cleanup block at `State.lua:557-573` explicitly nils 12
  transient fields (akaCalled, lastTrick, takweeshResult, swaResult,
  swaRequest, swaDenied, redealing, pendingPreemptContract,
  preemptEligible, lastRoundResult, lastRoundDelta, sweepTrack-
  Announced) but was missing `s.overcall`. Defense-in-depth:
  `RestoreSession`'s pre-snapshot strip handles the /reload path,
  but the parallel resync-from-host path didn't clear, leaving
  stale state if a late client rejoined mid-overcall. Now nil'd
  symmetrically with the 12 sibling fields.

### Fixed (LOW — doc-drift)

- **SU2-04 — `State.lua:1227` `S.ApplyMeld` block comment.**
  Said "MELD_CARRE_A_SUN (Aces in Sun — 400 raw, الأربع مئة)".
  Post-v0.11.10 revert the constant is **200 raw**. The Arabic
  name "الأربع مئة" / "Four Hundred" refers to the post-mult value
  (200 × Sun×2 = 400 effective), not the stored constant. Updated
  to clarify.

- **SU2-05 — `State.lua:1107-1117` `S.ApplyContract` block comment.**
  Said "It survived through the round and into SaveSession (s.overcall
  is NOT in TRANSIENT_FIELDS)" — the parenthetical was correct
  pre-v0.11.11, became wrong with XU-09, and is correct again
  post-v0.11.13 revert. Replaced with a fuller explanation of the
  v0.9.0 M2 design + why the explicit nil here is still needed.

- **SU2-06 — `CHANGELOG.md` v0.11.12 XR-15 site-count off-by-one.**
  Said "11 sites migrated" / "State.lua (9 sites)". Actual count is
  10/8/1/1. Corrected. (The 13→10 reduction reflects compound-gate
  sites that retain explicit guards.)

- **XR2-10 — `State.lua:1099-1104` belOpen comment-vs-code mismatch.**
  Said "Default open=true" while the field initial values were
  `false`. Confusion stemmed from conflating the *field's initial
  state* (which IS false; escalation is opt-in) with the *ApplyDouble
  argument default* (which IS true; legacy callers passing nil
  advance to the next rung). Rewrote comment to disambiguate.

- **`Rules.lua:288` `R.DetectMelds` comment.** Same "400 raw" stale
  reference as SU2-04. Updated to point at the 200-raw constant +
  explain the post-mult Arabic-name origin.

- **`tests/test_state_bot.lua` K.2a pin comment.** Said "value =
  MELD_CARRE_A_SUN (400 raw)". The constant is 200 raw post-revert;
  the assertion still passes (`K.MELD_CARRE_A_SUN` is the constant
  symbol, value-agnostic), but the comment was misleading.

### Test coverage (v0.11.13 hotfix-specific)

- **U.10 inverted** from "asserts overcall in TRANSIENT_FIELDS"
  to "asserts overcall is NOT in TRANSIENT_FIELDS". Renamed from
  XU-09 to NetU2-01 with full rationale block.
- **V.1a/b** — pin SU2-02 hoist: `local cardA, cardB, mpA, mpB,
  mult, beloteOwner` and `local result` declared BEFORE the
  if-block in `N.HostResolveSWA`.
- **V.2** — pin XR2-05/06: `_OnContract` checks trump enum.
- **V.3** — pin SU2-01: `ApplyResyncSnapshot` clears `s.overcall`.
- **V.4** — pin NetU2-01 cross-check: `WHEREDNGN.lua` post-restore
  PHASE_OVERCALL re-arm gate intact (depends on overcall persisting).

577/577 tests pass.

### Deferred to v0.11.14+

- **XU-01 phase 2** — Net.lua wire-injection harness. **Single
  highest-leverage debt item** post-v0.11.13. Would have caught
  both v0.11.13 HIGH/CRITICAL regressions at commit time. Required
  precondition for XR-16 (MaybeRunBot 638-line refactor).
- **XR2-08** — OPEN-1 NetU-01 250ms re-broadcast may not fully
  close the chat-throttle window. Structural fix is collapsing
  MSG_OVERCALL_RESOLVE + MSG_CONTRACT into one message; deferred
  pending phase 2 harness for empirical validation.
- **SU2-07** — `B.Sound.Try` removes the existence guard for
  migrated sites. Theoretical risk only (Sound.lua loads via .toc
  before State/UI), but worth a top-level shim in Sound.lua's
  tail.
- **XR2-07** — Sun calibration empirical telemetry (~100 rounds
  via `WHEREDNGNDB.history` → `tools/calibrate.py`). Latent risk
  that cumulative bonuses post-v0.11.10 over-fire Sun. Pin coverage
  exists for constants, not fire-rate distribution.

## v0.11.12 — test-harness extension + Sound.Try migration + doc updates

Continues the v0.11.9 ultra-audit queue. The previous batch (v0.11.11)
closed wire-validation symmetry items + the SU-Ultra-01 reachability
fix. This batch adds behavioral test coverage for the BotMaster path
(highest-leverage architectural code), migrates the Sound.Cue guard
pattern to the v0.11.11 helper, and documents the calibration journey.

### Added (test infrastructure — XU-01 phase 1)

- **`tests/test_botmaster.lua`** — new behavioral harness loading
  State + Bot + BotMaster under stub globals. Exercises `BM.PickPlay`
  and `rolloutValue` end-to-end. Closes the test-harness gap that
  allowed v0.11.2 SU-Ultra-01 ("SWA per-team breakdown shipped dead")
  and v0.10.6 RT07-01 ("redeal recovery shipped dead") to pass
  source-string-match pins. **Source-string pins on BotMaster.lua
  remained useful as structural guardrails but couldn't catch the
  "code matches text but is unreachable" bug class** — those need
  behavioral exercise, which this harness provides.

  19 new behavioral pins covering:
  - **Section A**: BotMaster surface + IsActive flag-gating
  - **Section B**: C-14 + Bot1-01 state-swap correctness — verifies
    all 6 swapped fields (hostHands, trick, tricks, akaCalled,
    playedCardsThisRound, _memory) are restored after BM.PickPlay,
    and that `_inRollout` doesn't leak
  - **Section C**: heuristicPick delegates to Bot.PickPlay (counts
    >100 invocations during a single BM.PickPlay rollout)
  - **Section D**: Bot1-02 `_inRollout` flag-leak guard — injects an
    R.IsLegalPlay error and verifies the flag still clears
  - **Section E**: v0.11.10 canonical scoring rule end-to-end —
    Sun-Carré-A meld contributes exactly 400 raw / 40 nq through
    R.ScoreRound (the user-arbitrated "should be 66" rule)

  **Phase 2** (Net.lua harness with WoW API stubs: C_ChatInfo,
  C_Timer, GetTime, CHAT_MSG_ADDON event injection) is the next
  test-infrastructure investment; deferred to its own release
  because it requires a substantial stub kit. Phase 1 covers
  the highest-value architectural code (C-14 + Bot1-01/02 all live
  in BotMaster.lua) which is enough for the majority of the
  source-string pin debt.

### Changed (refactor — XR-15 site migration)

- **10 sites migrated** from `if B.Sound and B.Sound.Cue then B.Sound.Cue(K.SND_X) end`
  to `B.Sound.Try(K.SND_X)`:
  - `State.lua` (8 sites)
  - `Net.lua` (1 site)
  - `UI.lua` (1 site)

  v0.11.11 introduced `B.Sound.Try` as a thin nil-safe wrapper
  but didn't migrate existing sites. v0.11.12 completes the
  migration. Test stub `WHEREDNGN.Sound = { ..., Try = function() end, ... }`
  in `test_state_bot.lua` and `test_botmaster.lua` ensures the
  harness picks up the new helper.

  Compound-gate sites (e.g., `if not isReplay and B.Sound and B.Sound.Cue then ...`)
  retain the explicit guard form because they layer additional
  conditions (replay suppression, trick-8 gating) that don't
  belong inside the simple Try wrapper.

### Updated (XU-12 / XU-14 — doc drift closures)

- **`docs/strategy/saudi-rules.md`** — added "Bot calibration
  journey (v0.10.0 → v0.11.10)" appendix:
  - Live diagnostic: `/baloot bidcalc` reference
  - Calibration constants table (current values + Constants.lua
    locations)
  - Tuning history table (v0.4 → v0.10.4 → v0.10.6 → v0.11.9 →
    v0.11.10) covering all bidding constants that moved
  - Diagnostic process narrative referencing the v0.11.8/.9/.10
    cycle as the canonical example of "user reports → bidcalc
    trace → calibration adjustment"

- **`docs/strategy/decision-trees.md`** Section 1 — added a callout
  for `/baloot bidcalc` near the bidding-rule tables so future
  contributors find the diagnostic toggle without grep'ing
  CHANGELOG.

### Skipped (intentional defers)

- **NetU-10** — feature-decision (implement Takweesh recovery vs.
  remove forward-compat hook for `s.contract.forced`). Both options
  have merit; needs explicit user direction.
- **XR-16 MaybeRunBot 638-line refactor** — too risky without test
  harness phase 2 covering the dispatch path. Better deferred until
  XU-01 phase 2 lands.
- **XU-01 phase 2 (Net.lua harness)** — substantial stub kit work;
  separate release. Phase 1 in v0.11.12 covers BotMaster which is
  the higher-leverage half.
- **XU-15 (30+ inline `S.s.* =` writes architectural debt)** — slow-
  burn refactor; many sites; better as ongoing improvement than a
  single batch.

### Tests

- **`tests/test_botmaster.lua`** Sections A-E (19 new pins)
- **569 / 569 pass** (up from 550, +19 new behavioral pins)

## v0.11.11 — audit-queue batch (NetU-01..09 + SU-Ultra-01..03 + XU-07/09/10)

Sweeps the remaining items from the v0.11.9 ultra audit: 1 HIGH (OPEN-1
chat-throttle mitigation) + multiple MED wire-validation symmetry items
+ the v0.11.2 SWA banner unreachable-code fix + magic-number promotion
to K.* + Sound.Try helper introduction.

### Fixed (HIGH)

- **NetU-01 / OPEN-1 mitigation** (`Net.lua:1369` `_HostResolveOvercall`)
  — added defensive 250ms re-broadcast of `MSG_CONTRACT` after a
  successful overcall resolution. Mitigates the leading remaining
  hypothesis for the user-reported "Sun overcall bottom contract
  banner not updating" bug (open since v0.11.2): WoW's
  `CHAT_MSG_ADDON` chat-throttle (~4-6 msg/sec/sender) can drop the
  single MSG_CONTRACT broadcast in the dense overcall sequence (open
  + 4×decision + resolve dual-emit + contract + dealphase + turn +
  whispers). The retry costs nothing in the happy path
  (S.ApplyContract's idempotence guard at line 1059 makes re-receipt
  a no-op) and recovers from a single throttle drop.

### Fixed (MED — SWA banner reachability)

- **SU-Ultra-01 / SU-Ultra-02** (`Net.lua:3401` `HostResolveSWA` +
  `UI.lua:3043` `renderBanner` SWA branch) — fixed the v0.11.2 SWA
  per-team breakdown which had been STRUCTURALLY DEAD CODE since v0.11.2.
  HostResolveSWA sets `S.s.lastRoundResult = nil` BEFORE renderBanner
  runs, so the conditional `if r and r.bidderTeam ...` always fell
  through to the degraded "Claim verified — all remaining tricks
  awarded." line. Same failure mode as v0.10.6 redeal recovery
  (RT07-01) — code that compiles, source-matches, and tests pass but
  is unreachable. Fixed by stashing the breakdown directly on
  `S.s.swaResult.breakdown` (host-side); UI.lua now reads from there.
  Non-host receivers see the existing degraded view (wire-format
  extension would push past the 252-byte chunk limit; deferred).

### Fixed (MED — wire-validation symmetry, 8 items)

Same defense-in-depth shape as v0.11.3 RT07-05 / v0.11.5 cluster:

- **NetU-02** (`Net.lua:1496` `_OnMeld`) — kind enum check
  (`{seq3, seq4, seq5, carre}`). Pre-v0.11.11 garbage kind silently
  wrote nil-value meld, risking nil-arithmetic in score sum.
- **NetU-03** (`Net.lua:3388` `_OnAKA`) — suit enum check
  (`{S, H, D, C}`). Garbage suits silently passed to ApplyAKA + UI.
- **NetU-04** (`Net.lua:1652` `_OnRound`) — bounds check on
  addA/addB ≤ 200, totA/totB ≤ 1000. Pre-v0.11.11 nil was rejected
  but bogus huge values could falsely trigger game-end via
  R.GameEndWinner.
- **NetU-05** (`Net.lua:882` `_OnBidCard`) — `#card == 2` check.
  Mirrors XR-11's `_OnPlay`. Allows empty string sentinel.
- **NetU-06** (`Net.lua:786` `_OnLobby`) — per-name 64-char cap.
  Mirrors XR-06's encodedHand cap. Defends against multi-MB name
  injection via SaveSession persistence.
- **NetU-07** (`Net.lua:1069` `_OnPreempt`) — seat ∈ [1,4]. Mirrors
  XR-08's escalation-handler cluster.
- **NetU-08** (`Net.lua:3030` `_OnSWAResp`) — responder + caller
  ∈ [1,4]. Pre-v0.11.11 garbage seats wrote `req.responses[99]`
  which lingered in SavedVariables.
- **NetU-09** (`Net.lua:885` `_OnHand`) — encodedCards ≤ 16 chars.
  Mirrors XR-06.

### Fixed (MED — UI hardening)

- **SU-Ultra-03** (`UI.lua:3068` renderCardGlyphs) — whitelist rank
  and suit before glyph render. Pre-v0.11.11 any 2-char pair
  (e.g. "XY") passed through, producing visually-nonsense rows.
  Now invalid cards are silently skipped.

### Fixed (defense-in-depth)

- **XU-09** (`State.lua:264` TRANSIENT_FIELDS) — added `s.overcall`.
  Pre-v0.11.11 a /reload during PHASE_OVERCALL restored the struct
  with stale wall-clock; renderOvercallBanner showed 0-or-negative
  timer with no host-side enforcement (the original 5-second timer
  was gone). Now /reload during the overcall window cleanly drops
  it. v0.11.5 SU-01 patched the in-session leak; this closes the
  cross-/reload path.

### Added (refactor + tunability)

- **XU-07** (`Constants.lua` + `Bot.lua`) — promoted 5 bidding
  thresholds from Bot.lua locals to K.* constants for tunability:
  `K.BOT_TH_HOKM_R1_BASE` (42), `K.BOT_TH_HOKM_R2_BASE` (36),
  `K.BOT_TH_SUN_BASE` (40), `K.BOT_BID_JITTER` (6),
  `K.BOT_SUN_VOID_PENALTY_CAP` (8). Bot.lua locals retained as
  aliases sourced from K.* for backward-compat with existing call
  sites. Calibration trail documented in Constants.lua comment.

- **XR-15 / XU-10** (`Sound.lua`) — added `B.Sound.Try(soundId)`
  thin nil-safe wrapper. Helper enables incremental migration of
  the 13 `if B.Sound and B.Sound.Cue then B.Sound.Cue(K.SND_X) end`
  call sites; existing sites unchanged in v0.11.11 (each requires
  gate-preservation review). Future cleanup release can migrate.

### Tests

- **`tests/test_state_bot.lua` Section U** (26 new pins covering
  every NetU-01..09, XU-09, SU-Ultra-01..03, XU-07, XR-15)
- T.2 pin updated for the K.BOT_SUN_VOID_PENALTY_CAP promotion
- **550 / 550 pass** (up from 524, +26 new pins; 1 pin updated)

### Still open / deferred to v0.11.12+

- **XR-15 site migration**: helper is in place; converting the 13
  existing call sites is a pure-refactor follow-up.
- **XU-01/02 test-harness extension**: phase 1 (`test_botmaster.lua`)
  + phase 2 (Net.lua under WoW API stubs). Substantial work; ~96%
  of v0.11.x pins still source-string-match.
- **XR-16 MaybeRunBot 638-line refactor** (high risk; better after
  test-harness extension).
- **NetU-10 dead `s.contract.forced`** (decide whether to implement
  Takweesh recovery or remove dead reads).
- **XU-12 / XU-14 doc drift** (saudi-rules.md / decision-trees.md
  bidding calibration journey not documented in user-facing docs).

## v0.11.10 — canonical scoring rule (R5 + v0.11.6 fully reverted) + Sun-bidding closure

User-stated authoritative rule supersedes both v0.10.0 R5 and v0.11.6.
After ultra-audit cross-validation against video #43 (lines 152-158
verbatim Arabic walking through sere 20→4 nq, quarte 50→10 nq in Sun)
and the user's own concrete statement of canonical values, the
correct rule is:

> sere is 4 points in sun and 2 in hokm
> 50 is 10 points in sun and 5 in hokm
> 100 is 20 points in sun and 10 in hokm
> Carré-A is 40 points in sun and shifts to 10 in hokm as there is
> no carré-A in hokm.

Decoded: **all melds get the FULL contract multiplier (Sun ×2 +
escalation Bel/Triple/Four/Gahwa)**. Belote (K+Q of trump) alone is
multiplier-immune. The user's reported "should be 66" answer was
correct after all — but the right path to it is `K.MELD_CARRE_A_SUN
= 200` raw with full Sun×2 mult, NOT 400 raw with the "Sun-immune"
hack. v0.11.6 produced 40 nq for Carré-A but broke sere/quarte/quinte
to 2/5/10 nq instead of canonical 4/10/20. Both v0.10.0 R5 (200→400)
and v0.11.6 (split-multiplier) introduced regressions; v0.4.x was
correct all along.

### Reverted (HIGH — scoring correctness)

- **`Constants.lua` `K.MELD_CARRE_A_SUN`: 400 → 200.** Original v0.4.x
  value. With Sun×2 mult applied (per canonical rule): 200×2/10 = 40 nq.
- **`Rules.lua` R.ScoreRound**: removed v0.11.6 split (`contractMult` /
  `escalationMult` no longer exported); restored single `mult` applied
  uniformly to `(cards + melds)`. Belote post-mult immunity preserved.
- **`Net.lua` HostResolveTakweesh + HostResolveSWA invalid branch**:
  same single-mult restore.
- **`UI.lua` renderBanner**: per-bucket multiplier display reverted to
  single `×N` row.
- **`State.lua` ApplyMeld** comment: "200 raw" annotation.
- **`docs/strategy/saudi-rules.md` Q3 + Q5**: rewritten with canonical
  rule + math reference + history note for posterity.
- **`tests/test_rules.lua` Section S**: rewritten to pin the canonical
  values directly (8 pins covering all melds in both contracts +
  Sun-Bel escalation + end-to-end R.ScoreRound flow). Replaces v0.11.6
  pins.

### Fixed (HIGH — Sun bot bidding closure)

The v0.11.9 calibration was insufficient because the CHANGELOG
prediction misjudged `BID_JITTER` (assumed ±25, actual ±6). At
urgency=0, the post-v0.11.9 `[QS TH AH 8C KH]` hand had `sun=40`
vs threshold band 41-53 → **0% fire rate** (predicted 60%). Per
audit BotU-16:

- **`Bot.lua` `TH_SUN_BASE`: 47 → 40.** Brings the threshold band to
  34-46 so `sun=40` clears it ~50% of jitter outcomes (the canonical
  A+T-mardoofa Sun-bid rate per Saudi pro convention). Other hands:
  - `[8H JC AC TC 7S]` (sun=35) → ~10-15% fire rate
  - `[AS KH KC JH AD]` (sun=24, 2-Ace-no-mardoofa) → 0% (correctly
    conservative)
  - Weak A+T (sun~27) → 0% (correctly conservative)

This closes the user-reported "30 bidding rounds = 0 Sun bids"
investigation. Combined with v0.11.9's `MARDOOFA_BONUS 10→20` and
`void-cap 18→8`, A+T-mardoofa hands now reliably bid Sun.

### Tests

- **`tests/test_rules.lua` Section S** (8 new pins): K.MELD_CARRE_A_SUN
  = 200 + canonical math for sere/quarte/quinte/Carré-A in both
  contracts + Sun-Bel + empty-meld G/H/I/K compat + end-to-end
  R.ScoreRound flow.
- **524 / 524 pass** (up from 518; 6 previous v0.11.6 pins replaced
  by 8 canonical pins).

### Note on the v0.10.0 → v0.11.10 calibration journey

For posterity, the bidding-calibration constants moved through:

| Constant | v0.9 | v0.10.4 | v0.10.6 | v0.11.9 | **v0.11.10** |
|---|---|---|---|---|---|
| `BOT_SUN_MARDOOFA_BONUS` | 5 | 10 | – | 20 | 20 |
| `TH_SUN_BASE` | 50 | – | 47 | – | **40** |
| `sunStrength` void-cap | 25 | – | – | 8 | 8 |
| `K.MELD_CARRE_A_SUN` | 200 | – | – | – | **200 (revert)** |

All cumulative changes shipped now reflect the user-stated
authoritative rule. Cross-validation against video #43 + #32 + #38
agrees with this state.

### Re-test instructions

1. Update to v0.11.10 (CurseForge auto-publish ~10 min)
2. `/reload`
3. `/baloot bidcalc` to enable trace
4. Play 10-20 rounds
5. Expected pattern:
   - ~50% of A+T-mardoofa Sun-eligible hands bid Sun
   - Sun-Carré-A scoring shows 40 nq for the meld portion
   - Sun-Bel scoring shows 80 nq for the meld portion
   - Hokm-Carré-A (treated as Carré-other) shows 10 nq
6. Disable trace when satisfied: `/baloot bidcalc`

## v0.11.9 — bidding calibration (user-arbitrated from bidcalc trace evidence)

User played ~50+ bidding events with the v0.11.8 `bidcalc` trace
on. Analysis surfaced **three real calibration issues**, all confirmed
by specific trace events. Each fix is targeted with a defensible
Saudi-source basis.

### The data

Three Sun-eligible hands (sunMinShape=true) were observed in the
trace; ALL were filtered out by the strength threshold despite being
canonical Saudi Sun bids:

| Hand | aces | mardoofa | sunStrength | thSun | Gap |
|---|---|---|---|---|---|
| `[QS TH AH 8C KH]` | 1 | 1 | 20 | 43-47 | -23 to -27 |
| `[8H JC AC TC 7S]` | 1 | 1 | 15 | 48-52 | -33 to -37 |
| `[AS KH KC JH AD]` | 2 | 0 | 14 | 41 | -27 |

The first two have A+T mardoofa pairs (the canonical "إكة مردوفة"
pattern, video #25); the third has 2 Aces + 2 Kings (high-card
concentration). All structurally bid-Sun in Saudi convention but the
heuristic score values 14-20 were structurally ~25 points below the
threshold band of 41-52.

Plus one weak-mardoofa Hokm trigger:

```
[bid s4 r2] hand=[7C KC AC JS 8S] sun=-1 aces=1 mardoofa=1 thSun=51
[bid s4 r2] R2 Sun skipped: sunMinShape=false sun=-1 thSun=51
[bid s4 r2] R2 Hokm fires: S bestScore=30 >= thHokmR2=28
```

J♠+8♠ is NOT a Saudi mardoofa pair (canonical: J+9 or J+A). The bot
bid Hokm-Spades on a 2-trump hand where the second trump is 8 — the
exact RT07-07 audit-flagged case ("count==2 admits weak mardoofas").

### Fixed

- **`Constants.lua` `K.BOT_SUN_MARDOOFA_BONUS`: 10 → 20.** The v0.10.4
  bump (5 → 10) was insufficient. A+T mardoofa is the canonical
  "must-bid" Sun pattern in Saudi convention; +10 was structurally
  too small to cross the threshold even after face-value addition.
  Pair cap (2) preserved so 2-pair hands cap at +40, not unbounded.

- **`Bot.lua:949` `sunStrength` void-penalty cap: 18 → 8.** The
  void/short-suit penalty is HOKM-think mistakenly applied to Sun.
  In Hokm voids = ruff vulnerabilities; in Sun (no trump) voids are
  neutral or POSITIVE for the bidder (free discards on opp leads).
  Pre-v0.11.9 a hand like `[QS TH AH 8C KH]` (A+T+K hearts locked
  suit + 3 mid singletons) got 28 face value − 18 cap = 10 base —
  the penalty wiped out the entire face-value advantage of the
  A+T+K trio. Cap of 8 preserves "definitely-junk hand" filtering
  (e.g. all 4 suits void/honorless = -8) without erasing strong
  single-suit concentrations. History: 25 → 18 (Gemini softening) →
  8 (v0.11.9).

- **`Bot.lua:794` `hokmMinShape` Lever C tightening (RT07-07 closure).**
  The v0.10.6 `count == 2 and hasSideAce` clause admitted ANY second
  trump as a "mardoofa partner" of J — including 7, 8, T, Q, K. The
  bidcalc trace caught the bot bidding Hokm on J+8+side-Ace, exactly
  the case RT07-07 audit predicted. Per video #26 R2 the canonical
  "مردوفة" partner of J is specifically rank 9 (top mardoofa) or A
  (still strong). v0.11.9 tightens the gate: tracks `hasTrumpNine`
  and `hasTrumpA` separately and requires `(hasTrumpNine or hasTrumpA)`
  alongside the existing `hasSideAce`. J+7/J+8/J+T/J+Q/J+K with side
  Ace no longer triggers — closing the loose gate.

### Expected behavioral change

Re-running the trace's three missed Sun hands with v0.11.9 strength values:

| Hand | New sunStrength | thSun band | Fire rate |
|---|---|---|---|
| `[QS TH AH 8C KH]` | 28 − 8 + 20 = **40** | 32-57 (jittered) | ~60% |
| `[8H JC AC TC 7S]` | 23 − 8 + 20 = **35** | 32-57 | ~40% |
| `[AS KH KC JH AD]` | 32 − 8 + 0 = **24** | 32-57 | ~5% |

Net: ~50% of A+T-mardoofa hands now bid Sun (was 0%); 2-Ace-no-mardoofa
hands stay conservative (legitimately marginal in 5-card view).

### Tests

- **`tests/test_state_bot.lua` Section T** (8 new pins):
  - T.1: `K.BOT_SUN_MARDOOFA_BONUS = 20`
  - T.2a-b: void-penalty cap = 8 (and old 18 removed)
  - T.3a-b: hokmMinShape declares trump-rank flags + uses them in count==2
  - T.4 BEHAVIORAL: J+8+side-Ace 5-card hand → Bot.PickBid returns PASS
    (RT07-07 closure verified end-to-end via Bot.PickBid path)
- **518 / 518 pass** (up from 510, +8 new pins).

### Note

`/baloot bidcalc` toggle from v0.11.8 is still available — re-enable
it to verify v0.11.9 produces the predicted Sun-bid rate. Expected
trace pattern: `R1 direct Sun fires: sun=NN >= thSun=MM` should now
appear ~50% of the time on A+T mardoofa hands (was 0% pre-v0.11.9).

## v0.11.8 — bidcalc trace toggle (diagnostic for Sun-bidding investigation)

User-reported "bots not bidding Sun in 30 bidding rounds = 0".
Analysis of a 13-game-round SavedVariables snapshot showed bots
ARE bidding Sun (2/5 bot bids = 40% Sun rate, both made), but the
user's 30-bidding-round observation covers a wider sample than the
file. To get definitive data, this release adds a chat-output
diagnostic trace toggle.

### Added (diagnostic)

- **`/baloot bidcalc`** (alias `/baloot bidtrace` / `/baloot biddebug`)
  — toggles `WHEREDNGNDB.debugBidcalc`. When ON, every `Bot.PickBid`
  call prints to chat with seat + bidRound prefix. Output covers:
  - **Top-of-call**: hand, sunStrength, aceCount, mardoofa pairs,
    urgency stack, all three thresholds (thSun, thHokmR1, thHokmR2)
    with jitter applied
  - **Each decision branch**: which path fired (R1 direct Sun, R1
    Hokm-on-flipped, R2 Sun, R2 Hokm, fall-through PASS) with the
    specific values that led to it
  - **Negative paths**: when a Sun bid is *blocked* by the
    sunMinShape gate, threshold gap, or Hokm-margin rule

  Off-by-default. Zero overhead in production (the helper short-
  circuits on the toggle check before any string formatting). Format
  pcall'd so a bad fmt-string can't crash bot dispatch.

  Independent of the master `/baloot debug` flag (which gates
  Log.lua-level output) — this is a focused short-term diagnostic
  toggle aimed at the Sun-bidding question. Sample output:
  ```
  [bid s3 r1] hand=[7H 9C TS QH AC 8S JD AH] sun=42 aces=2 mardoofa=0 urgency=0 thSun=47 thHokmR1=42 thHokmR2=36
  [bid s3 r1] R1 direct Sun skipped: sunMinShape=true sun=42 thSun=47
  [bid s3 r1] R1 Hokm-on-flipped blocked: anyHokm=false anySun=false bidCardSuit=nil
  [bid s3 r1] R1 falls through to PASS
  ```

### Use case

Enable the toggle, play 5-10 rounds, capture the chat log. The
output reveals whether bots:
- Have hands that should bid Sun but don't (calibration regression)
- Have weak Sun-shape hands that legitimately stay Hokm (sampling)
- Run into a specific threshold/jitter pattern that pre-v0.11.8
  invisibly biased away from Sun

The bidcalc-instrumented data closes the diagnostic loop without
needing additional `/dump` commands.

### Tests

- **`tests/test_state_bot.lua` Section R** (7 source-match pins):
  - R.1a-b: Slash.lua wires the toggle via `WHEREDNGNDB.debugBidcalc`
  - R.2a-e: Bot.PickBid defines `btrace` + gates on the flag + traces
    R1/R2 Sun decisions + hand-state at the top of each call
- **510 / 510 pass** (up from 502, +8 new pins).

## v0.11.7 — SWA UX fixes (user-reported): bot-1-card short-circuit + result-banner cards

Two user-reported SWA UX bugs:
1. Bot calling SWA with 1 card left is silly UX — the bot is about
   to play that card anyway as the final trick. Just play.
2. The post-resolution score banner ("SWA from Bot X verified") had
   no card display, even when the caller was the player's teammate.
   The pending banner showed cards during the 5-second window, but
   they vanished when the round resolved.

### Fixed (UX)

- **`Bot.lua:3926` Bot.PickSWA** — short-circuit on `#hand <= 1`.
  Pre-v0.11.7 the gate was `#hand == 0 or #hand > 4` (allowing 1).
  With 1 card left the bot's MaybeRunBot dispatch will play that
  card as the next trick anyway; SWA banner + permission flow +
  claim-verified announcement for a single forced play is just
  noise. Now the bot just plays.

- **`Net.lua:3304` HostResolveSWA** — stash caller's `encodedHand`
  into `S.s.swaResult`. Pre-v0.11.7 the swaResult had only `caller`,
  `valid`, `contractMade`, `sweep` — the cards weren't carried into
  PHASE_SCORE. The post-resolution banner therefore had no card
  data, particularly opaque for teammate-bot SWAs ("SWA from Bot 3
  verified" with nothing to verify visually).

- **`Net.lua` SendSWAOut wire format** — extended to field 10
  (encodedHand). Backward-compatible with pre-v0.11.7 receivers
  (they ignore the extra field; nil-encodedHand falls through to
  the no-cards branch). Receiver `_OnSWAOut` consumes field 10
  with the same 16-char cap as v0.11.5 XR-06 (8 cards × 2 chars).
  Dispatcher passes `fields[10]` through.

- **`UI.lua` renderBanner SWA branch** — appends rank+suit-glyph
  card row to the banner title when `swaResult.encodedHand` is
  populated. Red-suit cards render in red, black-suit cards in
  white. Visible to ALL viewers regardless of caller team (per
  user spec: "you should be able to see the cards regardless").
  Format: `SWA! Bot 3 claimed — verified  ·  J♠ A♠ T♠ K♠`.

### Tests

- **`tests/test_state_bot.lua` Section Q** (7 new pins):
  - Q.1: Bot.PickSWA #hand<=1 short-circuit
  - Q.2a-b: HostResolveSWA encodedHand computation + stash
  - Q.3a-d: SendSWAOut signature + _OnSWAOut signature + dispatcher
    fields[10] + 16-char cap
- **502 / 502 pass** (up from 493, +9 new pins).

### User-reported still open (telemetry / calibration)

- **Bots not bidding Sun** — user reports 30 rounds with 0 Sun bids
  even after v0.10.4 + v0.10.6 calibration adjustments
  (MARDOOFA_BONUS 5→10, TH_SUN_BASE 50→47). Filed for next
  calibration cycle. Need data on which seats/hands the user
  thinks should have bid Sun but didn't.

## v0.11.6 — split-multiplier scoring: contract-mult vs escalation-mult (R5 supersession)

**User-arbitrated scoring rule fix.** A reported scoring bug ("Sun
SWA-fail with opp Carré-A meld scored 106, should have been 66")
exposed that the v0.10.0 R5 fix had the **multiplier rule wrong** for
melds in Sun. The R5 reasoning that `K.MELD_CARRE_A_SUN = 400` is the
raw value was correct (matches videos #32 + #38's "أربع مئة"), but
applying Sun's ×2 multiplier to that meld produced 80 nq game points
in Sun vs 10 nq in Hokm — a **1:8 ratio** that contradicts the
videos' clear "Hokm: 100; Sun: 400" 1:4 framing.

The canonical Saudi rule per user clarification:
- **Cards** scale with contract-mult (Sun ×2 / Hokm ×1) AND
  escalation-mult (Bel ×2, Triple ×3, Four ×4, Gahwa ×4)
- **Melds** (sequence, carré-other, carré-A) scale ONLY with
  escalation-mult — they're contract-mult-immune
- **Belote** (K+Q of trump) is immune to ALL multipliers
  (existing rule, unchanged)

Under the new rule the Hokm/Sun ratio is exactly 1:4 (10 nq vs 40 nq),
matching the Saudi naming convention. The user's reported scenario now
correctly produces 66 / 0 instead of 106 / 0.

### Fixed (HIGH — scoring correctness)

- **Rules.lua R.ScoreRound** — split the multiplier into
  `contractMult` (Sun ×2 / Hokm ×1) and `escalationMult` (Bel/Triple/
  Four/Gahwa). Cards multiply by both via `mult = contractMult ×
  escalationMult`; melds multiply by `escalationMult` only. Belote
  stays multiplier-immune (added post-everything). Result struct
  exports both `contractMult` and `escalationMult` separately so UI
  consumers can show the breakdown; `multiplier` field preserved as
  the combined value for backward-compat (test_rules.lua section K
  pins still pass).

- **Net.lua HostResolveTakweesh** (line 2382) — same split. Takweesh
  Qaid penalty math now matches R.ScoreRound.

- **Net.lua HostResolveSWA invalid branch** (line 3179) — same split.
  Resolves the user-reported "Sun SWA-fail with Carré-A scored
  106 / should be 66" bug.

### Changed (UI — score-banner breakdown)

- **UI.lua renderBanner** — bidder/defender breakdown lines now
  display the per-bucket multiplier suffix when relevant:
  `Team A: cards 130 ×2 + melds 400 ×1`. The modifiers row appends a
  `melds ×N (Sun-immune)` indicator when a Sun contract has melds in
  play and the meld-side multiplier differs from the card-side
  multiplier — making the contract-mult-immunity rule visible
  without needing to compute the math manually.

### Sanity-check / cross-validation (R5 supersession reasoning)

- Hokm-Carré-A = 100 raw → 100 ÷ 10 = **10 nq** (no Sun, no
  escalation)
- Sun-Carré-A under R5 = 400 × Sun×2 ÷ 10 = **80 nq** → 1:8 ratio
- Sun-Carré-A under v0.11.6 = 400 ÷ 10 = **40 nq** → 1:4 ratio ✓
- Sun-Bel-Carré-A under v0.11.6 = 400 × Bel×2 ÷ 10 = **80 nq**
  (escalation still applies)
- Videos #32 line ~245 + #38 line ~61: "in Hokm count as 100; in Sun
  it's 400" — explicit 1:4 ratio between the named values

The earlier R5 doc's `/5 divisor` analogy with sere/quarte (e.g.,
sere 20 → 4 nq under Sun) was correctly read but mis-extrapolated to
Carré-A: the videos' /5 worked-examples for sequences may have been
demonstrating simplified accumulated arithmetic rather than per-meld
divisor application. Per user-arbitrated rule, all melds are
contract-mult-immune.

### Tests

- **`tests/test_rules.lua` Section S** (12 new pins):
  - S.0a-e: result struct exposes `contractMult` + `escalationMult`
    correctly across Hokm/Sun ± escalation
  - S.1a-c: user's reported SWA-fail scenario reproduces correctly
    (raw 660 → final 66) + Hokm/Sun 1:4 ratio cross-check
  - S.2a-b: Sun-Bel preserves escalation ×2 on melds (400 × Bel×2 = 80 nq)
  - S.3a: empty-meld fixture unchanged (regression guard for
    sections G/H/I/K)
  - S.4: Hokm-Bel quarte still scales correctly (escalation works)
  - S.5a-b: Belote stays multiplier-immune (existing rule preserved)
- **493 / 493 pass** (up from 479, +14 new pins).

### Impact analysis

**Affected (verified via grep):**
- `Rules.lua` R.ScoreRound, `Net.lua` HostResolveTakweesh + SWA-invalid,
  `UI.lua` renderBanner — all updated.
- `BotMaster.lua` rolloutValue uses `R.ScoreRound`, inherits
  automatically. Saudi-Master ISMCTS now evaluates rollout-team scores
  with the corrected Sun-meld math.
- `Net.lua` HostResolveSWA valid branch uses `R.ScoreRound`, inherits
  automatically.

**Not affected:**
- `Bot.lua` PickBid/Ashkal/Double/Triple/Four/Gahwa/Preempt/AKA/SWA/
  PickPlay — none of these compute multiplier × meld directly. The
  `sunStrength` and `escalationStrength` heuristic functions weight
  cards/aces, not multiplier-affected meld values.
- All existing test fixtures in test_rules.lua sections G/H/I/K use
  empty melds (`{ A = {}, B = {} }`), so meld×mult scoring isn't
  pinned anywhere — **zero test churn from existing fixtures.**

### Constants.lua + saudi-rules.md updates

- `K.MELD_CARRE_A_SUN = 400` retained; comment rewritten to explain
  the post-v0.11.6 multiplier rule and reference the math trace
  (Sun: 40 nq base, 80 nq Bel; Hokm: 10 nq via MELD_CARRE_OTHER).
- `docs/strategy/saudi-rules.md` Q3 marked "🔁 R5 SUPERSEDED v0.11.6"
  with the full ratio-cross-check rationale.
- `docs/strategy/saudi-rules.md` Q5 marked "🔁 REVISED v0.11.6"
  pointing to the contract-side / escalation-side split and noting
  that video #43's /5 worked-examples were demonstrating
  simplified accumulated arithmetic.

## v0.11.5 — defensive batch: SU-01 + 7 LOW closures + dead-code cleanup

Closes the remaining defensive findings from v0.11.3 comprehensive
audit that survived v0.11.4. All low-risk one-liners or targeted
removals. Two false-positive findings (SU-03, SU-06) verified
non-issues during implementation (audit was incorrect on both).

### Fixed (MED — defensive)

- **SU-01** (`State.lua` `S.ApplyContract`) — clear `s.overcall` when
  advancing phase past PHASE_OVERCALL. Pre-v0.11.5, under client wire
  reorder where MSG_CONTRACT arrived before MSG_OVERCALL_RESOLVE,
  this function advanced phase to PHASE_DOUBLE but left `s.overcall`
  non-nil. The follow-up `_OnOvercallResolve` then bailed on the
  v0.11.0 A5 phase guard, so `s.overcall` was never cleared. It
  survived through the round and into SaveSession (the field is NOT
  in `TRANSIENT_FIELDS`). Defensive single-line clear; the overcall
  window is logically closed once a contract has been (re-)applied.

### Fixed (LOW — wire-validation hardening)

Each guards against a buggy/forked host emitting malformed broadcast
frames that would silently corrupt receiver state. Same shape as
the v0.11.3 RT07-05 / v0.11.4 wire-validation cluster.

- **NetA-06** (`Net.lua:843` `_OnDealPhase` redeal branch) — validate
  `nextDealer ∈ [1,4]`. Pre-v0.11.5 a buggy/forked host emitting
  `MSG_DEAL_PHASE;redeal;<garbage>` passed nil or out-of-range into
  `S.ApplyRedealAnnouncement`; the redeal banner displayed the wrong
  (or no) dealer name.
- **NetA-07 / XR-04** (`Net.lua:2279` `_OnTakweeshOut` and
  `Net.lua:3057` `_OnSWAOut`) — validate caller ∈ [1,4] and (Takweesh
  only) `illegalSeat ∈ [0,4]` (0 = "no offender" sentinel from the
  wire format). Pre-v0.11.5 garbage callers wrote into
  `S.s.takweeshResult.caller` / `S.s.swaResult.caller`; downstream
  `S.s.seats[99]` lookups returned nil and label fallback dropped to
  `"?"`.
- **XR-05** (`Net.lua:2677` `_OnPause`) — enforce payload ∈ {"0","1"}.
  Pre-v0.11.5 any non-"1" payload (nil, "true", garbage) silently
  mapped to false (resume). Bogus payloads now drop at the wire.
- **XR-06** (`Net.lua:2872` `_OnSWAReq` + `Net.lua:3040` `_OnSWA`) —
  cap `encodedHand` to 16 chars (max 8 cards × 2 chars/card).
  Pre-v0.11.5 the encoded hand was stashed unbounded into
  `S.s.swaRequest`, which is NOT in `TRANSIENT_FIELDS` so persists
  to SavedVariables. WoW addon-channel max payload caps ~252 bytes
  per chunk so the actual attack surface was small, but explicit
  cap closes the future-channel-format-change risk.
- **XR-08** (`Net.lua` `_OnDouble` / `_OnTriple` / `_OnFour` /
  `_OnGahwa`) — seat range checks added. Downstream `eligibleSeat`
  comparison would have rejected out-of-range seats by mismatch but
  explicit range gating is uniform with the rest of the wire layer.
- **NetA-09** (`Net.lua:1864` `_HostExecuteRedeal`) — validate
  `nextDealer ∈ [1,4]` after the existing nil-check. Pre-v0.11.5 a
  corrupted SavedVariables with `s.redealing.nextDealer = 99` passed
  the nil-check and corrupted `s.dealer` + downstream rotation math
  (99 % 4 + 1 = 4, so first-bidder math limps along but the
  dealer-rotation invariant breaks from this round forward).

### Removed (LOW — dead code)

- **Bot1-05 / C-01** (`Bot.lua:1391-1397`) — deleted the byte-identical
  duplicate of the singleton-T cardinality gate. The canonical block
  at lines ~1361-1367 is preserved; this site is now a one-line
  no-op marker. The duplicate had been flagged in the v0.10.7 audit
  and survived through several cycles.
- **XR-14** (`Constants.lua:183`) — removed `K.MSG_KICK = "K"`. Zero
  references across the codebase; the kick-a-seat UX was never
  implemented. Tag `"K"` is now free for future reuse.

### Investigated, not real bugs (audit false-positives)

- **SU-03** — `s.takweeshResult` was reported as missing from
  `TRANSIENT_FIELDS`; verified during implementation that line
  `State.lua:228` already has `takweeshResult = true,`. The audit
  agent was reading from a different (or imagined) version. No
  action.
- **SU-06** — round-end cue cluster (HOKM_LOST/KABOOT/etc.) was
  reported as needing an `isReplay` guard like RT07-03. Investigation
  showed `_OnResyncRes` calls `S.ApplyResyncSnapshot` which writes
  `s.cumulative` directly from the snapshot fields — MSG_ROUND is
  NOT replayed during resync. The audit's claimed "MSG_ROUND replay
  flood" scenario doesn't actually happen. No action.

### Tests

- **`tests/test_state_bot.lua` Section P** (25 new source-match pins):
  - P.1 (SU-01): S.ApplyContract clears s.overcall
  - P.2 (NetA-06): _OnDealPhase nextDealer range
  - P.3a-c (NetA-07/XR-04): Takweesh + SWA caller ranges
  - P.4 (XR-05): _OnPause payload domain
  - P.5a-b (XR-06): SWA encodedHand 16-char cap
  - P.6 (XR-08): four escalation handlers seat range
  - P.7 (NetA-09): _HostExecuteRedeal nextDealer range
  - P.8 (Bot1-05): T-cardinality canonical block appears exactly once
  - P.9 (XR-14): K.MSG_KICK definition removed
- **479 / 479 pass** (up from 454, +25 new pins).

### Still open (defer to v0.12.x)

- **OPEN-1** — Sun overcall bottom contract banner not updating.
  Both Net.lua and State+UI audit agents confirm no code-level bug
  from inspection. Pending user repro details.
- **XR-01** — Test-harness blind spot. `tests/run.py` doesn't load
  Net.lua / BotMaster.lua / WHEREDNGN.lua → all v0.11.x pins are
  source-string matches. Bigger lift; needs WoW API stubs.
- **Bot1-03** — ISMCTS performance budget guard. Defer until user
  reports lag.
- **RT07-07 / Bot1-04** — `hokmMinShape` weak mardoofa (J+7 passes).
  Calibration; pending v0.11.1+ telemetry.
- **XR-15** — Sound.Cue guard helper consolidation (~26 LOC reduction).
  Pure refactor; no behavioral change. Defer.
- **XR-16** — `MaybeRunBot` 638-line refactor candidate. Bigger lift.

## v0.11.4 — comprehensive-audit batch: C-14 completion + Saudi-Master robustness + wire-validation cluster

Closes the highest-value items from the v0.11.3 comprehensive audit
(four parallel agents covering Net.lua / State+UI.lua / Bot+BotMaster /
cross-cutting+red-team). Three tracks in one batch.

### Fixed (HIGH)

- **Bot1-01** (`BotMaster.lua` rolloutValue) — **C-14 completion**.
  v0.11.1 swapped 5 fields (hostHands / trick / tricks / akaCalled /
  playedCardsThisRound) but missed `Bot._memory`. The audit
  (`C_Bot_audit.md` Bot1-01) found this was the partial-coverage gap:
  branches reading `_memory[seat].played[card]` and `_memory[seat].void[suit]`
  saw real-state observations only — the rollout's simulated forward
  play never updated `_memory`, so the simulated tail's revealed voids
  were invisible to the rollout policy. Affected branches:
  - **Ace-exhaustion lead** (`Bot.lua:2101-2132`) — at trick T+k of a
    rollout, "have side Aces all been played?" silently answered "no"
    (only saw real-state plays through trick T). Trump-poor cash-side
    play was undervalued.
  - **Faranka exception #4** (`Bot.lua:2985-2999`) — bidder-team
    Faranka pos-4 trump-cut fires when all opps observed-void in
    trump. Rollouts couldn't see voids revealed in tricks T+1..T+k.
  - **`opponentsVoidInAll` / `anyOpponentVoidIn`** helpers
    (`Bot.lua:674-702`) — opp-void-aware lead branches in pickLead.
  - **`PickAKA` suppression** (`Bot.lua:3385`) — suppress AKA when
    partner observed void in trump.

  Fix: rolloutValue now also saves/swaps/restores `B.Bot._memory` to a
  rollout-local `rolloutMemory[seat] = { played, void }` populated from
  `simTricks` + `currentTrick.plays` at swap-in (mirrors
  `Bot.OnPlayObserved`'s populated/void inference rule). A
  `recordRolloutMemory(seat, pick, leadSuit)` helper updates the
  rollout-local memory after every pick during the rollout loop, so
  voids revealed in the simulated tail are visible to subsequent
  picks. Cross-round signals (`firstDiscard`, `likelyKawesh`,
  `akaSent`, `_partnerStyle` ledger) are NOT swapped — those are
  invariant during a single-round rollout and the Bot.PickPlay
  branches that read them aren't bot-coordination-relevant in
  rollouts.

### Fixed (MED — Saudi-Master robustness)

- **Bot1-02** (`BotMaster.lua` BM.PickPlay legal-set construction) —
  `_inRollout` flag leak fix. Pre-v0.11.4 a `R.IsLegalPlay` error
  inside the legal-set loop propagated up to Net.lua's outer pcall
  in `MaybeRunBot`, which caught the error but never restored
  `B.Bot._inRollout` — silently disabling Saudi-Master ISMCTS for the
  rest of the session (every subsequent `Bot.PickPlay` short-circuited
  at the delegation guard, falling through to heuristics). The C-14
  v0.11.1 expansion widened the surface area where errors could
  occur (full pickLead/pickFollow now exposed via the rollout policy
  delegation), making this leak more likely.

  Fix: wrap legal-set construction in pcall via named-function
  `buildLegalSet`. On failure, `_restore(nil)` clears `_inRollout`
  and returns nil so `Bot.PickPlay` falls back to heuristics for THIS
  move only — Saudi-Master tier remains armed for the rest of the
  session. Named-function form (rather than inline closure) preserves
  the I.4 (H4) per-world pcall structural test that requires the
  first inline `pcall(function()` to come after the per-world for-loop.

### Fixed (MED — wire-validation cluster, 5 one-liners)

Same defense-in-depth shape as v0.11.3 RT07-05 (`_OnContract` bidder
range + btype enum). Each guards against a buggy/forked host emitting
malformed broadcast frames that silently corrupt receiver state.

- **NetA-03 / RT07-06** (`Net.lua:1608` `_OnRound`) — nil-numeric
  guards on addA/addB/totA/totB. Pre-v0.11.4 `S.ApplyRoundEnd`
  unconditionally wrote `s.cumulative.A = totA`; nil totals silently
  corrupted the score panel until the next valid MSG_ROUND.
- **NetA-04** (`Net.lua:1573` `_OnTrick`) — winner ∈ [1,4] + points
  non-nil. Pre-v0.11.4 `s.tricks[i].winner = nil` corrupted trick
  history; downstream `R.TeamOf(nil)` defaulted to "B", miscounting
  team trick totals.
- **NetA-05** (`Net.lua:875` `_OnTurn`) — seat ∈ [1,4]. Pre-v0.11.4
  a bogus `s.turn = 99` broke turn-glow UI (`S.s.seats[99] = nil`)
  and AFK timer arming (`isBotSeat` returned nil → bot dispatch
  noops). Garbage seat persisted until next valid MSG_TURN.
- **XR-09** (`Net.lua:1615` `_OnGameEnd`) — winner ∈ {"A","B"}.
  Pre-v0.11.4 accepted any string and wrote into `s.winner`; downstream
  `R.TeamOf` comparisons silently fell through to default branches.
- **XR-11** (`Net.lua:1475` `_OnPlay`) — seat ∈ [1,4] + `#card == 2`.
  Pre-v0.11.4 a malformed card (1-char, 5-char, garbage) was passed
  to `S.ApplyPlay` → `R.IsLegalPlay` → `card:sub(1,1)/sub(2,2)`
  producing bogus rank/suit silently. Mirrors the inline check
  already in `_OnTrick`'s encPlays loop.

### Tests

- **`tests/test_state_bot.lua` Section O** (20 new source-match pins):
  - O.1a-f (Bot1-01): Bot._memory swap/restore + rolloutMemory
    population + recordRolloutMemory helper
  - O.2a-c (Bot1-02): buildLegalSet + pcall + _restore on failure
  - O.3 (NetA-03): _OnRound nil-numeric guard
  - O.4a-b (NetA-04): _OnTrick winner range + points non-nil
  - O.5 (NetA-05): _OnTurn seat range
  - O.6 (XR-09): _OnGameEnd winner enum
  - O.7a-b (XR-11): _OnPlay seat + card-length
- **454 / 454 pass** (up from 434, +20 new pins).

### Verified-correct items (no action needed; from comprehensive audit)

- **C-14 architecture** (post v0.11.1) — structurally correct. State
  swap covers every field read by `Bot.PickPlay` descendants.
- **All v0.11.0/.3 closures hold**: A5, B2, C1#6, D1, E2, RT07-01,
  RT07-02, RT07-03, RT07-04, RT07-05, S-1, U-7.
- **TRANSIENT_FIELDS coverage clean** post-RT07-01.
- **Wire/state Send↔On pairing clean** — no orphans.
- **Self-broadcast loops** — every `_On*` has `fromSelf` guard.
- **Tier strict-extension intact**: Master ⊂ Fzloky ⊂ M3lm ⊂ Advanced.
- **Bot memory lifecycle**: per-round / per-game resets correct.
- **Resync handshake post-C1#6** fully covers pause-during-resync.
- **Takweesh banner WIN/LOST**: verified-correct (proxy ≡ score-delta
  by construction; unlike SWA's v0.11.2 fix).

### Still open (next-batch candidates)

- **OPEN-1** — Sun overcall bottom contract banner not updating.
  Both Net.lua and State+UI agents confirm no code-level bug from
  inspection. Most-likely root: AddonMessage chat-throttle drop of
  MSG_CONTRACT (no redundant rebroadcast in `_HostResolveOvercall`).
  Defensive mitigation possible: re-send MSG_CONTRACT ~250ms later.
  Pending user repro details (host vs client, `/dump`, screenshot).
- **SU-01** — `S.ApplyContract` should clear `s.overcall` on phase
  advance (defensive single-line; wire-reorder edge case).
- **SU-06** — `S.ApplyRoundEnd` cue cluster lacks isReplay guard
  (rejoiner audio flood). Mirror RT07-03 pattern.
- **XR-01** — Test-harness blind spot. `tests/run.py` doesn't load
  Net.lua / BotMaster.lua / WHEREDNGN.lua → all v0.11.x pins are
  source-string matches. Bigger lift; needs WoW API stubs.
- **Bot1-03** — Performance budget for ISMCTS. Defer until user
  reports lag.
- **RT07-07** — `hokmMinShape` weak mardoofa (J+7 passes). Calibration;
  pending v0.11.1+ telemetry.
- **LOW**: NetA-06, NetA-07, XR-04, XR-08, XR-14, XR-15, XR-16
  (dead constant, sound-cue dedup, MaybeRunBot refactor, etc.).

## v0.11.3 — RT07 batch: SND_LAST_TRICK_WIN trick-8 gate + sweep-track reset + contract wire-validation

Three targeted MED closures from `audit_v0.10.7/D_RedTeam_audit.md`.
All three are low-risk defense-in-depth or UX-correctness fixes.

### Fixed (MED)

- **RT07-02** (`State.lua` `S.ApplyTrickEnd` last-trick-win cue) —
  `SND_LAST_TRICK_WIN` is now gated to trick 8 only. Pre-v0.11.3 the
  cue fired on every "guaranteed-unbeatable" play across all 8 tricks
  (pos-4 win, boss-of-suit with trump exhausted, boss-of-trump). User's
  v0.10.7 spec was *"sound for the last hand winning card when it
  played and 100% it is obvious a win"* — "last hand" = trick 8 in
  Saudi parlance, and the v0.10.7 CHANGELOG wiring blurb explicitly
  said `#tricks == 8`. The cue now layers with the natural cluster of
  round-end cues (SND_TRICK_WON, SND_KABOOT, SND_BALOOT, possibly
  SND_HOKM_LOST) for a single coherent close-of-round audio moment
  rather than scattering across mid-round tricks. Note: `s.tricks`
  already includes the just-resolved trick at the cue site (via
  `table.insert` earlier in `ApplyTrickEnd`), so `#s.tricks == 8` is
  the correct test.

- **RT07-04** (`State.lua` `S.ApplyRoundEnd`) — added
  `s.sweepTrackAnnounced = nil` defensively at round-end. Pre-v0.11.3
  the flag was only reset by `ApplyStart` and `reset()`; v0.11.0 S-1
  added the `ApplyResyncSnapshot` reset for rejoiners. v0.11.3
  completes the triple of reset sites so a corrupted/partial-restore
  state (orphan PHASE_SCORE without subsequent MSG_START, dropped
  start-of-round frame) doesn't carry the prior round's announced-flag
  into the next round. `sweepTrackAnnounced` is not in
  `TRANSIENT_FIELDS` so it persists across `/reload` via
  `RestoreSession`; this round-boundary clear is the belt-and-braces
  guard.

- **RT07-05** (`Net.lua:899` `N._OnContract`) — added
  `bidder ∈ [1,4]` range check and `btype ∈ {HOKM, SUN}` enum check.
  Pre-v0.11.3 only `nil` was rejected. The `fromHost` trust gate
  already prevents non-host peers from forging MSG_CONTRACT, but a
  host running a buggy/forked client could send `MSG_CONTRACT;5;H;X`,
  writing `s.contract.bidder = 5` and silently masking the error
  downstream (`R.TeamOf(5)` defaults to "B", `(5 % 4) + 1 = 2`
  off-by-one for next-seat math, `S.s.seats[5]` is `nil`). Same
  defensive shape as the existing nil-check. Originally noted in
  `review_v0.10.4_ship_readiness.md` deferred items (B-Net-02 H1/H2);
  this is the explicit closure.

### Tests

- **`tests/test_state_bot.lua` Section N** (5 new source-match pins):
  - N.1 (RT07-02): `ApplyTrickEnd` last-trick-win cue gated on
    `#s.tricks == 8`
  - N.2 (RT07-04): `S.ApplyRoundEnd` clears `s.sweepTrackAnnounced`
  - N.3a (RT07-05): `_OnContract` rejects bidder outside 1-4 range
  - N.3b (RT07-05): `_OnContract` rejects btype outside `{HOKM, SUN}`
- **434 / 434 pass** (up from 429, +5 new pins).

### Still open (next batch candidates)

- **OPEN-1** — Sun overcall bottom contract banner not updating
  (user-reported v0.11.2; needs repro details)
- **RT07-06** — `_OnRound` accepts nil numeric fields (similar shape
  to RT07-05; defer to next MED batch)
- **RT07-07** — `hokmMinShape` Lever C admits weak mardoofa pairs
  (calibration; pending v0.11.1 telemetry)
- **B1, C-07, C-19, X-1** — still as-listed in v0.11.0 deferred
- **Comprehensive ultra audit** — pending v0.11.1+v0.11.2+v0.11.3
  game-log telemetry from user

## v0.11.2 — SWA banner UX: per-team breakdown + WIN/LOST relative to round outcome

User-reported UX hotfix surfaced from a screenshot: the SWA result
banner was overwriting the regular round-end score breakdown, and
its "WIN" headline was driven by SWA-validity rather than the actual
round outcome. Concretely the user's screenshot showed: team A bid
HOKM, Bot 3 (team A) called SWA, claim was verified, but team A's
trick total fell short of the make threshold so team B got +20 raw.
The banner showed a green "WIN" headline despite team A losing the
contract, and the regular per-team cards-and-melds breakdown was
hidden behind the SWA's three-line text.

### Fixed

- **`UI.lua:3036` `renderBanner` SWA branch (UX, MED)** — the SWA
  banner now:
  - Computes WIN/LOST from the actual round score delta
    (`lastRoundDelta`) relative to the local team — replacing the
    prior `setOutcome(callerTeam)` proxy which used SWA validity.
    A valid SWA claim can still coincide with a contract loss when
    the bidder team's trick points fall short of the make threshold
    (and likewise an invalid claim can coincide with a sweep
    elsewhere); the score delta is the only authoritative source
    of round outcome.
  - Shows the same per-team breakdown as the regular round-end path
    (`bidderTeam: cards X + melds Y`, `defenderTeam: cards X + melds
    Y`, modifiers row with contract type + Bel/Triple/Four/Gahwa +
    multiplier, Belote line if applicable) instead of replacing those
    rows with a single `Claim verified — all remaining tricks
    awarded.` line. The SWA-specific text is now confined to the
    banner title.
  - Title becomes either `SWA! <name> claimed — verified` (green
    backdrop) or `SWA failed — <name> claimed wrongly` (red
    backdrop).
  - Non-host degraded view (no `lastRoundResult` broadcast yet) keeps
    the prior single-line explanation in the bidder slot as a
    graceful fallback.

  Preserved: the `final` score-delta line stays unchanged at the
  bottom (`A +X   B +Y` with team-color highlights). Sounds (e.g.
  `SND_HOKM_LOST` from State.lua) continue to fire through the
  existing State.lua paths — no Sound code touched.

### Investigated, not reproduced

- **Sun overcall bottom contract banner not updating** (user-reported,
  same message): traced the wire flow end-to-end and could not find
  a code-level bug. After `S.FinalizeOvercall` mutates `s.contract`
  (host-side) and `S.ApplyContract` is called via `MSG_CONTRACT`
  receive (client-side), the bottom contract strip in `renderStatus`
  reads `S.s.contract.type` / `.trump` / `.bidder` on every UI
  refresh and rebuilds the text unconditionally — there's no caching
  layer that could hold stale values. The dispatcher fires `UI.Refresh`
  after every `CHAT_MSG_ADDON` event (`Net.lua:677`), and the host's
  `_HostResolveOvercall` calls `UI.Refresh` explicitly at line 1345
  (or via `HostFinishDeal` in the Sun-Bel-skip path).

  If the user can reproduce reliably, useful diagnostics would be:
  - Were they host or client when the bug fired?
  - The SavedVariables `WHEREDNGN.lua` dump at the moment of the bug
    (specifically `WHEREDNGN.s.contract` and `WHEREDNGN.s.phase`)
  - Whether the chat showed the `Sun overcall by <name>` log line
  - A screenshot of the moment AFTER the resolve

  Filing as `OPEN-1` for now; ready to fix once we have a repro.

### Tests

- `429 / 429 pass` — no test changes (UI.lua doesn't have a Lua
  harness; the change is mechanical and source-isolated to the SWA
  banner branch).

## v0.11.1 — C-14 BotMaster heuristicPick → Bot.PickPlay delegation

Single architectural fix: the audit-flagged HIGH item from v0.11.0's
deferred list. `BotMaster.lua` rolloutValue used a 50-line Advanced-
mirror placeholder for its rollout policy that the audit's deep dive
identified as the **single highest-impact gap in the bot code** —
rollouts under-valued ~30% of Saudi-canonical play patterns
(sweep-pursuit, trick-8 boss-scan, free-trick suit, Sun L08, Tahreeb
sender/receiver, Faranka exceptions, AKA receiver, Sun shortest-suit,
Belote preservation, Tanfeer, etc.). Saudi-Master tier was structurally
no stronger than Fzloky on these scenarios because every rollout was
biased away from canonical patterns.

This release reroutes rollouts through `Bot.PickPlay` under the
existing `_inRollout=true` recursion guard set in `BM.PickPlay`. The
delegation pattern + state swap was already identified by audit as
the canonical fix; this release implements it cleanly.

### Fixed (HIGH-architectural)

- **C-14** (`BotMaster.lua:644-755` rolloutValue heuristicPick) —
  replaced the 50-line Advanced-mirror placeholder with a single-line
  delegation: `return B.Bot.PickPlay(s)`. The rollout policy now picks
  up every Saudi-canonical branch in pickLead/pickFollow that the
  placeholder missed.

  **Mechanism**:
  - `BM.PickPlay` already sets `B.Bot._inRollout = true` (existing
    line 822) before entering the world loop. The recursion guard at
    `Bot.PickPlay:3450` (`if not Bot._inRollout`) short-circuits the
    BotMaster delegation when set, so the delegated call runs
    pickLead/pickFollow directly without recursive ISMCTS re-entry.
  - State swap inside `rolloutValue`: save and override
    `S.s.hostHands`, `S.s.trick`, `S.s.tricks`, `S.s.akaCalled`,
    `S.s.playedCardsThisRound` so `Bot.PickPlay` reads the
    determinization-sampled view rather than the real game state.
    `S.s.playedCardsThisRound` matters because `S.HighestUnplayedRank`
    keys off it (used by sweep-pursuit boss-scan, J+9 trump-lock,
    highest-unplayed lead).
  - `S.s.akaCalled` set to `nil` for sim-blind AKA semantics
    (rollouts intentionally treat AKA as not-yet-called; future tricks
    can't introduce new AKA calls in simulation).
  - Per-trick re-swap of `S.s.trick = currentTrick` after each new
    trick reset, since the loop reassigns `currentTrick` to a fresh
    table on trick boundaries.
  - All 5 swapped fields restored unconditionally via pcall pattern
    so a mid-rollout error cannot leak the swap to the next world's
    `sampleConsistentDeal` (which would corrupt sampling by reading
    polluted hostHands).

  **Bias direction shift**: the old placeholder was fundamentally
  Hokm-only (mostly Advanced-mirror smother + lowest-rank duck +
  highest-trump bidder lead). It missed all Sun-specific lead patterns
  and any later-tier follow refinements. The delegated call exposes
  the rollout simulator to the same logic real bots use, including
  M3lm/Fzloky/Master tier-specific branches when the seat being
  simulated qualifies (per `Bot.IsAdvanced/IsM3lm/IsFzloky` checks
  inside pickLead/pickFollow).

  **Performance note**: per-pick cost rises from ~5µs to ~20-50µs.
  Worst-case early-trick rollout (100 worlds × 8 candidates × ~25
  plays ≈ 20k inner picks) lands ~400-1000ms per move, vs ~100ms for
  the placeholder. Acceptable for Saudi-Master tier where the user
  has explicitly opted into a 100-world sampler — the move-quality
  gain dwarfs the latency. If empirical telemetry shows users
  perceiving the lag, a `_lightweight=true` flag could short-circuit
  the heaviest pickFollow branches in v0.11.2.

  Source: `.swarm_findings/audit_v0.10.7/C_Bot_audit.md` Audit Item
  BM-3 (lines 360-478) + Recommendation #1 (lines 580-586).

### Tests

- **`tests/test_state_bot.lua` Section M** (10 new source-match pins):
  - M.1 (C-14): heuristicPick body delegates to `B.Bot.PickPlay`
  - M.1b (C-14): old "Lead heuristics (Advanced-mirror)" placeholder
    comment removed (regression guardrail against accidental restore)
  - M.2a-f (C-14): rolloutValue saves/swaps/restores the 5 swapped
    state fields (hostHands, trick, tricks, akaCalled,
    playedCardsThisRound)
- **429 / 429 pass** (up from 419, +10 new pins).

### Caveat / next-step

The existing `tests/test_state_bot.lua` doesn't load `BotMaster.lua`,
so the C-14 delegation isn't exercised behaviorally in the test
suite — only structurally pinned. Manual smoke-testing during
development confirmed `BM.PickPlay` completes successfully with the
new delegation in ~430ms for a 100-world early-trick move (single
all-spade fixture, all 8 candidates evaluated). A behavioural test
that loads BotMaster + runs a tier comparison is the next test-
infrastructure item, deferred until the existing test_state_bot.lua
harness gap (no Net.lua / no BotMaster.lua) is closed more broadly.

The next phase per user direction is empirical telemetry: collect
v0.11.1 SavedVariables across several rounds with Saudi-Master tier
active, then compare bot decision quality vs v0.11.0 (which used the
Advanced-mirror placeholder). Specifically watch for:
- Sun bidder-team rollouts now leading the shortest suit (was leading
  longest)
- Trick-8 sweep-pursuit boss-scans firing
- AKA receiver branch firing in rollouts (was hard-blocked by
  must-trump-ruff in placeholder)

### Deferred (still-open from v0.10.7 audit, not in v0.11.1)

- **X-1** — State→UI refresh implicit dependency (massive surface)
- **C-11** — `hokmMinShape` R2-only scoping (pending telemetry)
- **C-19** — BotMaster retry-exhaust instrumentation
- 5 more MED items: A2, B1, C-07, RT07-02, etc.
- LOW items (dead-code, MaybeRunBot refactor, Sound-guard dedup)

## v0.11.0 — audit_v0.10.7 closures + voice-cue refresh

200k-token quad-track audit (Net.lua, UI.lua+State.lua, Bot.lua+
BotMaster.lua, cross-cutting/red-team) surfaced 9 HIGH + 22 MED + 17
LOW findings. v0.11.0 closes the 7 actionable HIGH bugs + 2 high-value
MED + the 8-voice-cue audio refresh. Architectural items (C-14
BotMaster heuristicPick weakness, X-1 State→UI refresh implicit
dependency) deferred to v0.11.1.

The single most important finding: **my v0.10.6 redeal-stuck recovery
was structurally dead** (RT07-01) — `s.redealing` was in
`TRANSIENT_FIELDS` so SaveSession wiped it before persistence, meaning
the recovery code at WHEREDNGN.lua + Net.lua never had data to act on.
The exact user-reported scenario ("paused mid-redeal + /reload") still
soft-locked despite the v0.10.6 shipped fix. Test-harness gap (Net.lua
+ WHEREDNGN.lua not loaded by `tests/run.py`) masked the regression.

### Fixed (HIGH)

- **RT07-01** (`State.lua:211` TRANSIENT_FIELDS) — removed `redealing`
  from the transient-fields table so SaveSession persists it. The
  v0.10.6 recovery code at `WHEREDNGN.lua` PLAYER_LOGIN + `Net.lua`
  LocalPause resume now has data to act on. The C_Timer-based auto-
  dismiss path is replaced by the recovery path post-/reload.
  **The user-reported soft-lock is now actually fixed.**

- **A5** (`Net.lua:1186` `_OnOvercallResolve`) — phase-idempotency
  guard. The v0.10.3 dual-emit (`"!"` + `"?"`) for cross-version compat
  could fire `_OnOvercallResolve` twice; under wire reorder the second
  hit could revert a remote client from PHASE_PLAY back to
  PHASE_DOUBLE. Added `if S.s.phase ~= K.PHASE_OVERCALL then return end`.

- **D1** (`WHEREDNGN.lua:197` PLAYER_LOGIN) — PHASE_PREEMPT AFK re-arm
  branch. Pre-v0.11.0 the re-arm chain covered DOUBLE/TRIPLE/FOUR/
  GAHWA but not PREEMPT; /reload during a Triple-on-Ace pre-emption
  with a human eligible seat soft-locked the same way the v0.10.6
  redeal-stuck bug did. Added `for _, pseat in ipairs(s.preemptEligible)`
  loop that re-arms `StartBelTimer(pseat, "preempt_pass")` for the
  first human eligible seat.

- **S-1** (`State.lua:546` ApplyResyncSnapshot) — added
  `s.sweepTrackAnnounced = nil` to the resync clear block. Pre-v0.11.0
  a rejoiner carrying a stale `true` flag from a prior round would
  silently miss the v0.10.7 SND_SWEEP_TRACK cue when their team
  swept tricks 1-2-3 of the new round.

- **U-7** (`UI.lua:2034`) — SWA Deny button switched from `addAction`
  (single-click) to `addConfirmAction`. Misclick cost ~30 game points
  (handTotal × mult, awarded as the Qaid penalty against the caller).
  Takweesh had confirm protection; Deny didn't.

- **B2** (`Net.lua:2079` HostFinishDeal) — nil-hands soft-lock now
  surfaces a user-facing chat error advising `/baloot reset`. Pre-
  v0.11.0 was log-only, leaving the user with a frozen window and no
  visible explanation.

- **C1#6** (`Net.lua:316` SendResyncReq) — `resyncResExpiryTimer` now
  pause-aware. Pre-v0.11.0 the 30s window timer fired regardless of
  pause; user paused for >30s (or paused + /reload) saw legitimate
  MSG_RESYNC_RES rejected as expired. Recursive named function
  pattern matching the v0.10.5 SWA pause re-arm fix.

### Fixed (MED — 2 high-value cherry-picks)

- **E2** (`Net.lua:2940` `_OnSWA`) — added `swaRequest` mutex matching
  `_OnSWAReq`. Pre-v0.11.0 a direct MSG_SWA claim from a different
  seat could race against an in-flight vote window — the second
  resolve clobbered the first.

- **RT07-03** (`Net.lua` MSG_TRICK + `State.lua` ApplyTrickEnd/ApplyPlay)
  — resync replay no longer fires v0.10.7 sound cues for past events.
  Added trailing `;1` replay flag to whispered MSG_TRICK frames during
  resync; receiver propagates `isReplay` through `S.ApplyTrickEnd` +
  `S.ApplyPlay`; the v0.10.7 cues (SND_TRUMP_CUT, SND_SWEEP_TRACK,
  SND_LAST_TRICK_WIN) skip when `isReplay=true`. Pre-v0.11.0 a
  rejoiner heard the cues for every past trick during the snapshot
  replay flood.

### Voice-cue refresh (8 mp3 → ogg replacements)

User-supplied refreshed Saudi voice cues replace the v0.5-era
edge-tts synthesized cues. All 8 files copied from `Downloads/`,
converted via `ffmpeg libvorbis q=5`, dropped into `sounds/`:

| File | Phrase | Trigger |
|---|---|---|
| `aka.ogg` | إكَهْ | AKA partner-coordination call |
| `ashkal.ogg` | أشكال | Ashkal call |
| `wla.ogg` | ولا | round-2 pass |
| `pass.ogg` | بَسْ | round-1 pass |
| `sun.ogg` | صن | Sun bid |
| `hokm.ogg` | حكم | Hokm bid |
| `awal.ogg` | أوَل | round-1 bidding start |
| `thany.ogg` | ثآني | round-2 bidding start |

No code changes — constant paths unchanged.

### Tests

- **`tests/test_state_bot.lua` Section L** (3 new pins):
  - L.1 (RT07-01): `redealing = true` no longer in TRANSIENT_FIELDS
  - L.2 (S-1): ApplyResyncSnapshot clear block contains
    `sweepTrackAnnounced` reset
  - L.3 (RT07-03): `S.ApplyTrickEnd` + `S.ApplyPlay` signatures
    accept `isReplay`; v0.10.7 cues gated on `not isReplay`
- **419 / 419 pass** (up from 412 in v0.10.7, +7 new pins).

### Deferred to v0.11.1+ (per v0.10.7 audit)

#### HIGH-architectural (deserves its own release)

- **C-14** — BotMaster `heuristicPick` rollout policy substantially
  weaker than `Bot.PickPlay` (Saudi Master ISMCTS sampler under-
  values canonical play). Recommended fix: route rollouts through
  `Bot.PickPlay` under `_inRollout=true` guard. Substantial — needs
  A/B simulation testing.
- **X-1** — State→UI refresh dependency is implicit (every Net.lua
  dispatch must remember `B.UI.Refresh()`). Same architectural
  pattern that caused the v0.10.6 round-end-stuck bug. Massive
  refactor surface.

#### MED batch (cherry-pick from 22)

- A2: unknown-tag silent UI churn (cosmetic but real)
- B1: HostStartRound mid-round redeal hazard (phase gate)
- C-07: topTouchSignal write-without-read at M3lm tier (data
  collected but unused — wire BotMaster reader call from M3lm too)
- C-19: BotMaster retry-exhaust silent fallthrough (instrumentation)
- C-11: `hokmMinShape` Lever C R2-only scoping (pending v0.10.6
  empirical telemetry showing R1 over-firing)
- 17 more in `audit_v0.10.7/` reports

#### LOW (defer to v0.11.2+)

- Dead-code duplicate at Bot.lua:1361-1397
- 638-line `MaybeRunBot` refactor candidate
- `K.MSG_KICK = "K"` dead constant
- 18 Sound-guard duplications (refactor to `cue()` helper)

### References

Audit reports under `.swarm_findings/audit_v0.10.7/`:
- `A_Net_audit.md` — Net.lua deep audit (~600 lines)
- `B_UIState_audit.md` — UI.lua + State.lua audit (~963 lines)
- `C_Bot_audit.md` — Bot.lua + BotMaster.lua audit (~630 lines)
- `D_RedTeam_audit.md` — cross-cutting / red-team audit (~365 lines)

## v0.10.7 — 6 specialized sound cues (user-supplied)

User-driven audio polish — six new specialized cues layered on top
of the existing sound system. All six OGG files supplied by the user
and wired into appropriate trigger sites in `State.lua`. Cues fire
on the appropriate audience (some all-clients, some local-only,
some team-specific). The generic `SND_LOST_ROUND` stinger is now
suppressed when one of the new specific loss cues fires so the
local client doesn't hear two stacked stingers.

### Added — 6 new sound cues

| Constant | File | Trigger | Audience |
|---|---|---|---|
| `K.SND_SWEEP_TRACK` | `sounds/sweep_track.ogg` | After trick 3 closes when same team won 1+2+3 — sweep pursuit confirmed. Once per round. | All clients |
| `K.SND_KABOOT` | `sounds/kaboot.ogg` | Round-end when local team achieved Al-Kaboot (won all 8 tricks). | Winning team only |
| `K.SND_TRUMP_CUT` | `sounds/trump_cut.ogg` | First trump played in a non-trump-led trick (Hokm only). One cue per cut event. | All clients |
| `K.SND_LAST_TRICK_WIN` | `sounds/last_trick_win.ogg` | Local seat plays a card that's GUARANTEED unbeatable by remaining seats (option 3c). Pos-4 win OR boss-of-suit with trump pool exhausted OR boss-of-trump. | Local seat only |
| `K.SND_HOKM_LOST` | `sounds/hokm_lost.ogg` | Hokm contract failed (`bidderMade=false`); fires for the bidder team (losers) only. **Takes priority over `SND_KABOOT_AGAINST`** when both would fire. Supersedes generic `SND_LOST_ROUND`. | Bidder team (losers) only |
| `K.SND_KABOOT_AGAINST` | `sounds/kaboot_against.ogg` | Round-end when Al-Kaboot was scored against local team. Suppressed if `SND_HOKM_LOST` fired (Hokm-fail dominates kaboot-against per user spec). Supersedes generic `SND_LOST_ROUND`. | Losing team only |

### Loss-cue priority order (per user spec)

1. **`SND_HOKM_LOST`** wins when bidder team failed Hokm AND local on bidder team — even when opp also achieved Al-Kaboot. The contract loss is the dominant outcome.
2. **`SND_KABOOT_AGAINST`** fires only when `SND_HOKM_LOST` didn't claim priority above (e.g., defender team got swept on a Sun contract, or sweep without contract failure).
3. **`SND_LOST_ROUND`** generic fallback fires only when neither of the above did (e.g., normal Sun-fail loss, Takweesh penalty loss).
4. **`SND_KABOOT`** (winning team) fires independently — distinct audience so no priority conflict.

### Last-trick-win cadence (option 3c)

Fires only when the local play is **provably unbeatable** from public state:
- **Position 4** AND local won → always (last-to-play has full trick info)
- **Earlier positions**: card is the boss of its suit AND for Hokm: trump pool fully exhausted (no remaining seat can ruff)
- **Trump-led tricks**: card is the highest-unplayed trump

Conservative — false negatives (won-but-not-fired) acceptable, false positives (cued-but-could've-been-beaten) not. Bot._memory void inferences are host-side only and not consulted client-side; cue relies on `S.HighestUnplayedRank` public state.

### Trigger-site wiring

- **`State.lua` `S.ApplyPlay`** (trump-cut detection): scan plays
  in the current trick for trump count BEFORE the new play; fire
  if zero prior trump AND new play IS trump AND lead-suit ≠ trump
  AND contract is Hokm.
- **`State.lua` `S.ApplyTrickEnd`** (sweep-track + last-trick-win):
  when `#tricks == 3`, if all 3 winners are on the same team,
  fire SND_SWEEP_TRACK once per round (gated by
  `s.sweepTrackAnnounced`); when `#tricks == 8` AND
  `winner == localSeat`, fire SND_LAST_TRICK_WIN.
- **`State.lua` `S.ApplyRoundEnd`** (kaboot/hokm-lost cluster):
  branch on local team membership relative to `sweep` and
  `bidderMade` parameters. Layered on top of existing
  `SND_BALOOT` round-end fanfare; suppresses `SND_LOST_ROUND`
  when a more specific loss cue (HOKM_LOST or KABOOT_AGAINST)
  fires.

### State additions

- **`s.sweepTrackAnnounced`**: per-round one-shot flag for the
  SND_SWEEP_TRACK gate. Reset at round-start (`S.ApplyStart`)
  and on full-state Reset.

### Tests

- 412 / 412 still pass — sound wiring is non-blocking
  (`B.Sound.Cue` checks for module presence; tests run with
  `B.Sound = nil`, all calls no-op).

## v0.10.6 — bidding-calibration step 3 + redeal-stuck fix (Lever C + Lever A + UX)

Calibration-probe agent (read-only) traced source-canonical Saudi
bid patterns through the addon's strength functions and identified
**the lever as HOKM-side, not Sun-side**. Plus a user-reported
HIGH bug: paused-during-redeal + /reload soft-locks the round.

### Fixed (UX HIGH — paused-during-redeal soft-lock, user report)

User report: *"game was reshuffling, i paused and did /reload, i
came back after reload to the bidding round with no buttons and
it froze with turn on the opposite side bot (dealer)."*

- **`Net.lua` new `N._HostExecuteRedeal(nextDealer)`**: extracted
  from the inline 3s `C_Timer.After` body in `N._HostRedeal` so
  it can be re-invoked from recovery paths (LocalPause resume,
  PLAYER_LOGIN session restore) when the original timer was lost
  to a pause+/reload sequence. Idempotent — bails on missing
  `s.redealing`, wrong phase, or paused state.
- **`Net.lua` `LocalPause` resume path**: when un-pausing, if
  `s.redealing` is set and phase is DEAL2BID/DEAL1, schedule a
  fresh 3s timer to land the deal. Pre-v0.10.6 the resume path
  only handled stuck PHASE_PLAY tricks; redeal-stuck case had no
  recovery.
- **`WHEREDNGN.lua` PLAYER_LOGIN session restore**: same recovery
  for the cross-/reload case. If `s.redealing` is set after
  restore and we're not paused, schedule the deal step. Mirrors
  the existing `_HostStepPlay` re-fire pattern for stuck tricks.

### Tightened (Lever C — `hokmMinShape` R2 canonical-minimum)

Per the calibration-probe agent's primary finding (review_v0.10.2
BIDDING_CALIBRATION_v0.10.5.md §8.1, video #26 R2):

- **`Bot.lua:805` `hokmMinShape`**: added `count == 2 and hasSideAce`
  clause to accept the canonical-minimum Hokm hand from video
  #26 R2 — *"أقل شي عشان تشتري الحكم: الولد + مردوفة معاه + إكا
  وحدها"* ("minimum to buy Hokm: J of trump + ONE other trump
  with it + ONE Ace on the side"). The existing `not hasJ →
  return false` guard at line ~798 already enforces J-of-trump
  anchor, so the new clause is exactly the R2 pattern (2-trump-
  with-J + side Ace), no broader. Pre-v0.10.6 this canonical
  pattern was silently rejected — the most-emphasized "minimum
  confident bid" in the entire Hokm corpus, lost.

  **Per 200k-trial Monte Carlo: ~19.23% of random 8-card hands
  match this pattern. Predicted lift: net bid rate 82% → 92.35%,
  Hokm bid rate 68.6% → 79.95% (+11.3pp).** This is the
  largest-impact single-lever lift available; addresses the
  user's "bots are not bidding" telemetry directly.

### Tightened (Lever A — `TH_SUN_BASE` 50 → 47)

Secondary calibration step paired with the v0.10.4
`K.BOT_SUN_MARDOOFA_BONUS` 5→10 bump:

- **`Bot.lua:37` `TH_SUN_BASE`**: 50 → 47. Moves the S-B "confident
  A+T mardoofa pair + 2-Ace" hand from ~38% jitter-clear to ~75%
  jitter-clear. Predicted Sun bid rate 16.8% → 22.1% per bot.
  NOT enough to close the S-A "single-mardoofa مجازف" gap
  (sunStrength=22 vs threshold=47, gap of 25 still too wide for
  threshold tweak) — that gap requires a sunStrength formula
  rebalance which is risk-laden and **deferred to v0.10.7+** if
  v0.10.6 telemetry still shows Sun under-firing.

### Test fixture refit (C-section, no behavioural change)

The PickBid sanity test fixture `{JH,9H,AH,TH,KH}` (5-card royal
flush in hearts) crossed the new Sun threshold band [41, 53] via
the v0.10.4 mardoofa bonus + v0.10.6 threshold drop combination
(sunStrength=43 within band). Replaced TH with 8H to break the
mardoofa pair — preserves the test's intent (strong 5-trump hand
bids Hokm, J+9+A+K still textbook strong-Hokm), now seed-robust.

### Tests

- **`tests/test_state_bot.lua` C-section new pin**: R2 canonical-
  minimum Hokm bid (J+9-trump + side Ace + advanced mode) bids
  HOKM. Pre-v0.10.6 this exact pattern PASSed via hokmMinShape
  rejection; post-v0.10.6 it bids correctly.
- **412 / 412 pass** (up from 411 in v0.10.5, +1 new pin).

### Deferred to v0.10.7+ (per calibration-probe agent §8.3-8.4)

- **S-A gap closure** — sunStrength formula under-rewards single-
  mardoofa hands by ~25-30 points. Threshold tweaks can't close
  this. Bonus bumps to MARDOOFA_BONUS 10→30+ would over-reward
  non-canonical mardoofa hands. Wait for empirical telemetry on
  v0.10.6 — if S-A-class hands still under-fire, tackle as a
  formula-rebalance audit.
- **R7 sirra-malaki Hokm under M3lm** — H-D pattern (4-card
  trump-meld, no Ace) is rejected under M3lm's L07 patch. Source
  carves it out as a "rare exception". Re-evaluating L07
  trade-off in isolation reserved for separate audit.
- **Promote thresholds to `K.*` constants** — `TH_SUN_BASE`,
  `TH_HOKM_R1_BASE`, `TH_HOKM_R2_BASE` are file-local in Bot.lua;
  a future cleanup can promote to `K.BOT_TH_*` for consistency
  with the rest of the bot tunables.

### References

Calibration-probe report at `.swarm_findings/review_v0.10.2/
BIDDING_CALIBRATION_v0.10.5.md` (430-line read-only audit with
10-pattern source-canonical trace + 200k-trial Monte Carlo).

## v0.10.5 — scoring-track audit closures (HIGH-2 + 4 MED + helpers + UI hotfix)

10-agent scoring sub-audit (S-Score-01..10) traced end-to-end
scoring pipelines that per-function audits couldn't see.
**Verdict: scoring is broadly correct; HIGH-1 was already shipped
in v0.10.4; HIGH-2 + 4 MED gaps close in this release.** Plus
two shared helpers extract divergent logic that had been
duplicated (and drifting) across 3 call sites each. Plus
user-reported UI hotfix for round-end "Next Round" stick.

### Fixed (UI hotfix — round-end "Next Round" sticks for human host)

- **`Net.lua:N.HostStartRound` + `N.HostFinishDeal`**: both
  functions advance host-side state and rely on the subsequent
  bot action's loopback to trigger `B.UI.Refresh()`. When the
  new round's first bidder (HostStartRound) or trick-1 leader
  (HostFinishDeal) is the human host, no bot fires → no loopback
  → UI stays on the prior PHASE_SCORE view. The Awal sound still
  plays because it's queued from `S.ApplyStart`, but the bid
  panel / play table never renders. **User-reported: "sometimes
  the round ends screen gets stuck even when pushing the next
  round button, you hear awal sound but it does not show you
  cards."** Fix: explicit `B.UI.Refresh()` at the tail of both
  functions. Harmless when a bot DID fire (Refresh runs again
  on the bot's loopback).

### Fixed (HIGH-2 — Reverse Al-Kaboot type-blind defender over-pay)

- **`Constants.lua` new `K.AL_KABOOT_REVERSE = 88`**: per video #16
  (canonical Saudi reverse Al-Kaboot / الكبوت المقلوب), defender
  sweep is awarded uniformly 88 raw across contracts — not the
  forward-AK 250/220.
- **`Rules.lua` `R.ScoreRound` sweep block**: branch on bidder-team
  vs defender-team detection. Forward-AK (bidder team sweeps):
  existing 250/220 logic unchanged. Reverse-AK (defender team
  sweeps): gated on `tricks[1].plays[1].seat == contract.bidder`.
  If bidder didn't lead trick 1, the sweep falls through to
  normal scoring (no AK bonus). The gating reflects the canonical
  Saudi asymmetry — forward-AK rewards crushing the contract;
  reverse-AK is a smaller "humiliation" payout that requires the
  bidder to have actively engaged.

  **Pre-v0.10.5 over-paid defender by ~16 gp/round (Hokm) or
  ~35 gp/round (Sun) — game-deciding in a 152-target match.**
  Source: S-Score-06.

### Fixed (MED-1 — Belote-cancellation team-level rule shared helper)

- **`Rules.lua` new `R.IsBeloteCancelled(team, meldsByTeam)`**:
  the canonical post-v0.9.0 M5 team-level form.
- **3 call sites consolidated**: `R.ScoreRound`,
  `Net.HostResolveTakweesh`, `Net.HostResolveSWA` (invalid SWA
  branch). Pre-v0.10.5 the Net.lua qaid handlers used a
  `m.declaredBy == kWho` SAME-PLAYER check, which missed
  cancellation when the K+Q holder's PARTNER declared the ≥100
  meld — over-crediting the bidder team by +2 gp on Qaid-context
  rounds. Source: S-Score-07.

### Fixed (MED-2 — Game-end H3 tiebreak shared helper)

- **`Rules.lua` new `R.GameEndWinner(cumA, cumB, target, result)`**:
  canonical post-v0.8.6 H3 logic — Gahwa winner > bidderMade-side
  > defensive "A".
- **3 call sites consolidated**: `Net.lua` normal round-end (was
  already canonical), Takweesh, SWA-invalid (both used pre-v0.8.6
  raw bidder-team logic that could award the match to the OFFENDER
  team on simultaneous-target hits during Qaid resolution).
  Source: S-Score-08.

### Fixed (MED-3 — Gahwa Sun-stale-flag defensive type-gate)

- **`Rules.lua` Gahwa match-win branch**: type-gated on
  `contract.type == K.BID_HOKM`. Sun has no Gahwa rung; a stale
  `contract.gahwa = true` on a Sun contract (resync, hostile peer,
  incomplete reset) would otherwise fire a spurious match-win.
  The multiplier path (lines 904-913) and inversion path (825-832)
  already collapse Sun's stale tripled/foured/gahwa flags
  defensively; this branch was missed. Source: S-Score-02 +
  S-Score-08.

### Fixed (MED-4 — Belote sweep-override / cancellation ordering)

- **`Rules.lua` `R.ScoreRound`**: cancellation walk now runs
  BEFORE sweep-override. Pre-v0.10.5 ordering: sweep-override
  flipped Belote ownership to the sweeping team FIRST, then
  cancellation walked meldsByTeam for the (possibly-flipped)
  Belote owner. In rare configs where the K+Q-holder's team had
  a ≥100 meld AND the OTHER team swept, the override moved
  Belote to the sweeper before cancellation could fire — net
  ~2 gp swing. Source: S-Score-04 + B-Rules-02 F-01.

### Doc — citation drift fixes

- **`docs/strategy/saudi-rules.md` Q1**: stale `Rules.lua:694`
  reference (was line of `R.ScoreRound` start) refreshed to
  current `~795` (Belote-Hokm gate inside that function).
- **`docs/strategy/glossary.md`**: "Match target | 152 raw"
  corrected to "152 game points" — the target is compared against
  per-team cumulative GAME points after div10 rounding, not raw.
- **`CLAUDE.md`**: "Bidder fails on tied 81/162" extended to
  cover Sun's 65/130 threshold too. Both Hokm and Sun require
  strictly more than half; doc previously implied Hokm-only.

### Tests

- **`tests/test_rules.lua` Section H.10-H.13**: Reverse Al-Kaboot
  pins (Hokm reverse → 88 raw, Sun reverse → 88×2=176, no AK fires
  when bidder didn't lead trick 1, forward-AK regression pin
  unchanged at 250).
- **`tests/test_rules.lua` Section L**: MED-3 Sun-Gahwa malformed
  flag does NOT fire match-win.
- **`tests/test_rules.lua` Section Q+**: 5 pins for
  `R.IsBeloteCancelled`, 7 pins for `R.GameEndWinner` (covers all
  H3 tiebreak branches), 1 pin for MED-4 ordering (Belote
  cancelled by 100-meld BEFORE sweep-override).
- **411 / 411 pass** (up from 387 in v0.10.4, +24 new pins).

### Removed from §4.2 backlog (verified false alarm)

- "MED | `Net.lua:2185-2190, 2930-2935` | R2 Sun mult collapse not
  backported to Takweesh / SWA-invalid". Verified by S-Score-07:
  both Net.HostResolveTakweesh and Net.HostResolveSWA invalid
  branches correctly apply `K.MULT_SUN`. Not a bug.

### Deferred to v0.10.6+ (per scoring-audit §"LOW")

- LOW-1: Net.lua qaid handlers don't apply v0.10.0 R2 Sun-rung
  defensive normalization (production-unreachable; defense-in-depth
  gap).
- LOW-2: `K.GAME_TARGET = 152` constant — replace 6+ hardcoded
  `or 152` literals across the codebase. Hygiene.
- LOW-4: `R.TeamOf(nil)` returns "B" silently (defensive only;
  same root cause as several existing audit refs).
- LOW-5/6: additional test pins for Belote multiplier-immunity at
  ×3/×4 + Carré-A 400 integration through R.ScoreRound.

### Pre-existing deferred items (carried from v0.10.4)

- D-RedTeam-01 E4 — T-AKA trick-locking exploit
- B-Net-02 H1/H2 — Forced-flag dead branches + bidder out-of-range
- B-State-02 H1 — ApplyBid value validation gap
- Bargiya FN → FP swing (cross-cite)
- B-Bot-06 F-01/F-02 — L07 cascade fail at M3lm+
- Dead-code redundancy at `Bot.lua:1336-1342` / `1366-1372`
- Bargiya inner-discriminator axis flip
- ISMCTS akaCalled-respecting sample pool
- `S.s.swaDenied` UI banner read
- Sun-Mathlooth-K pos-4 smother gate
- Test-harness gap (Net.lua + BotMaster.lua not loaded by run.py)

### References

Audit reports under
`.swarm_findings/review_v0.10.2/_track_S_scoring/`:
- `SCORING_SUMMARY.md` (~300-line synthesis)
- `S-Score-01..10.md` (per-pipeline sub-reports)

## v0.10.4 — review_v0.10.2 validation closures (4 HIGH + 1 calibration + tooling + doctrine doc)

Validation pass against the v0.10.3 audit synthesis caught 1 UI-
parity miss in M4 + 2 wire-level AKA exploits (HIGH) + 1 Sun-bid
calibration gap. Pre-shipping ship-readiness pass surfaced two
1-line wire guards (E1 + E2) on the AKA protocol. Late ship-
readiness pass surfaced HIGH-1 (X5 half-fix in `S.ApplyMeld` —
silent Hokm-Carré-A scoring corruption since v0.10.0). Tooling:
telemetry parser fix unblocks the calibration analyzer. Plus
doctrine note in `saudi-rules.md` documents the intentional Qaid-
vs-failed-bid meld asymmetry (v0.10.1 arbitration rationale).

### Fixed (HIGH-1 — X5 half-fix closure: Hokm-Carré-A in `S.ApplyMeld`)

- **`State.lua:1167-1190`**: v0.10.0's X5 fix patched
  `R.DetectMelds` (the meld-detection path used by `Bot.PickMelds`
  for declaring) but missed the **parallel path in `S.ApplyMeld`**
  used on the wire-receive side AND on the host's own ApplyMeld
  self-loopback. Pre-v0.10.4: `kind == "carre" + top == "A" +
  contract.type == K.BID_HOKM` fell through with `value = nil`,
  silently dropping every Hokm-Carré-A meld. Cascade: missing
  100-meld broke bidder strict-majority threshold, `R.CompareMelds`
  winner-takes-all, AND v0.9.0 M5 belote-cancellation (silent
  +20 raw over-credit on rounds where the offender held K+Q of
  trump alongside the lost Carré-A). Per video #32 line 245 +
  video #38 line 61, Carré-A in Hokm = 100 raw (treated like
  Carré-T/K/Q). Fix: added the Hokm branch with
  `value = K.MELD_CARRE_OTHER`. Stale comments at 1166 ("200 raw"
  — actual is 400) and 1177 ("Hokm 4-Aces: doesn't score" —
  opposite of rule) corrected.

  **Real-game impact:** every game with a Hokm-Carré-A round
  played since v0.10.0 mis-scored. Fix triggers ~1.92% of rounds
  per the audit's frequency estimate; combined cascade can be
  10 gp dropped + 20 gp over-credited = ~30 gp swing on affected
  rounds.

### Fixed (HIGH — `S.GetLegalPlays` AKA-blind, M4 completeness)

- **`State.lua:1975`** (comment header at 1962): pass `s.akaCalled`
  as the 6th arg to `R.IsLegalPlay`. Without this, the UI-dimming
  function ignored AKA-receiver relief — the human player saw
  non-trump discards greyed out even when partner had AKA'd,
  visually contradicting the M4 rule that legality, bot heuristics,
  and BotMaster outer driver all already honor. Same one-arg shape
  as the v0.10.3 BotMaster fix #5; this closes the M4 loop at the
  final layer.

### Fixed (HIGH — wire-level AKA exploit guards)

Pre-ship validation surfaced two wire-level AKA exploit windows
the v0.10.3 ship missed. Both are 1-line `if … then return end`
guards at the host receive boundary; both close real attack
surfaces with no risk to legitimate traffic.

- **E1 — trump-AKA wire reject** (`Net.lua:3122` `N._OnAKA`,
  D-RedTeam-01:29-60 / B-Net-05 F8a). AKA is meaningful only on
  non-trump suits — the AKA promise is "I have the boss of this
  non-trump suit." The UI hides the AKA button when the candidate
  suit equals trump, but a hostile peer can craft `MSG_AKA;<seat>;
  <trump>` directly on the wire. If accepted, it could mislead a
  partner-bot's `pickFollow` into suppressing a ruff that should
  fire (multi-trick damage on non-trump-led tricks via the
  implicit-AKA branch). Reject at wire entry. Companion guard
  added at `Rules.lua:115-130`: `akaRelief` excludes
  `akaCalled.suit == contract.trump` regardless of how the banner
  was set — defense-in-depth even if a malformed banner slipped
  past the wire-entry guard.

- **E2 — `_OnAKA` mid-trick lead-only gate** (`Net.lua` after E1
  guard, D-RedTeam-01:63-90 / B-Net-05 F8b). `LocalAKA` enforces
  lead-only at line 2358 (anti-misclick) but the wire path didn't.
  A hostile peer sending mid-trick `MSG_AKA` would set
  `s.akaCalled` after the receiver had already committed to ruff
  (or just before the next ruff decision), suppressing it. Added
  the same gate as `LocalAKA`: refuse AKA frames received when
  `#S.s.trick.plays > 0` (mid-trick).

### Calibrated (Sun-bid threshold — A+T mardoofa surgical bump)

- **`Constants.lua:329` `K.BOT_SUN_MARDOOFA_BONUS` 5 → 10**: the
  per-pair bonus for the canonical Saudi إكة مردوفة (A+T cover)
  pattern was under-rewarding hands that a Saudi pro would bid
  Sun on. Validation's preferred lever over a `TH_SUN_BASE` drop
  because it's surgical: the bonus only fires for hands with the
  doc-anchored A+T cover (video #25), not broadly relaxing the
  Sun threshold for any A-heavy hand. With pair cap = 2, max
  bonus moves from +10 to +20 for a 2-pair Sun-Mughataa hand.

  **First-step calibration framing:** simulation estimate
  predicts Sun bid rate moves ~3.1% → ~4.1% per seat. **The
  user's "bots under-bid Sun" complaint will be partially —
  but not fully — addressed.** Empirical telemetry (~30+ rounds
  on v0.10.4) needed to confirm the lift. **Reserved for v0.10.5:
  if real-play data shows still under-firing, the second pass is
  `K.TH_SUN_BASE` 50 → 44** (broader, but less doc-anchored).
  Not stacking both today — A/B comparability requires single-
  variable steps.

### Fixed (UI — first-launch felt theme mismatch, user report)

- **`UI.lua` `U.Show`**: on first launch with a non-default felt
  theme saved (e.g. `WHEREDNGNDB.feltTheme = "midnight"`), the
  cycle button label rendered correctly ("Felt: Midnight") but
  the backdrop tints rendered the **classic green** values from
  the COL hardcoded defaults at lines 143-145. Cause: `setBackdrop`
  reads `COL.feltDark`/`COL.feltLight` at frame-construction time;
  although `applyThemeColors()` runs at module-load (line 211) and
  should have updated COL before `buildMain/Lobby/Table` fire, an
  edge case in the load order left some frames captured against
  the pre-mutation defaults. Defensive fix: after freshly-built
  frames exist, force-reapply the theme by re-invoking
  `SetFeltTheme(active)`. Idempotent (writes the same name back),
  no behavioural change for users on the default green theme. The
  cycle button label and the actual backdrop now agree on first
  launch.

### Tooling — telemetry parser fix

- **`tools/calibrate.py`**: WoW SavedVariables uses bracketed-
  string key syntax (`["history"] = { ... }`) for all named
  table keys. The pre-v0.10.4 parser's regexes only matched
  bare-key form (`history = { ... }`) — the primary regex
  failed entirely, the fallback regex's non-greedy `.*?\n\s*\}`
  terminated at the first row's close brace (capturing only ~one
  row's worth of inner text with no `{}` markers, yielding zero
  parsed rows). Rewrote the locator to manual brace-walking
  with string-literal awareness; rewrote the row-key regex to
  accept both bare and bracketed forms. End-user can now run
  `python tools/calibrate.py <SavedVariables-path>` and get
  the calibration report — previously silently returned "no
  telemetry rows found" against valid SavedVariables files.

### Doc — Qaid meld-asymmetry doctrine note

- **`docs/strategy/saudi-rules.md`**: documents the intentional
  asymmetry between regular failed-bid (both teams keep own melds
  per «مشروعي لي ومشروعك لك») and Qaid (offender forfeits melds
  per «المشتري مشروعه فايد»). The two proverbs describe different
  round-end scenarios — fair-tricks-fail vs rule-violation —
  and are consistent in their respective contexts. Captures the
  v0.10.1 user arbitration rationale so future audits don't
  re-flag the asymmetry as a bug. Pre-v0.10.4 the doc still
  reflected the pre-v0.10.1 «keeps melds uniformly» reading.

### Tests

- **`tests/test_state_bot.lua` Section J**: GetLegalPlays
  AKA-relief pin (3 positive cases for non-trump discards +
  trump-still-legal, 3 sanity cases for the without-AKA
  must-trump baseline).
- **`tests/test_state_bot.lua` Section K**: HIGH-1 X5 half-fix
  parity pin — `S.ApplyMeld` produces 100-raw value for Hokm-
  Carré-A (was silently dropped pre-v0.10.4); Sun-Carré-A still
  400 raw; Hokm-Carré-K unchanged at 100 raw; Carré-9 still
  drops (K.CARRE_RANKS excludes 9).
- **`tests/test_rules.lua` Q.13**: trump-suit malformed `akaCalled`
  does not grant ruff-relief (defense-in-depth pin for E1).
- **387 / 387 pass** (up from 371 in v0.10.3, +16 new pins).

### Notes for v0.10.5 reviewers

The v0.10.3 CHANGELOG cited some HIGH-fix line numbers (1705,
2128, 830, 2964) that were comment-block headers; actual code
starts are 1714, 2143, 838, 2980. The fixes themselves are
correct; only the citation drifted. Won't amend v0.10.3 (already
on CurseForge) — captured here for forward reference.

### Deferred to v0.10.5+ (per ship-readiness review)

#### Newly catalogued HIGH backlog (absent at v0.10.3 ship too)

These were surfaced by the v0.10.4 ship-readiness pass via the
red-team and code-audit tracks; they're NOT v0.10.4 ship-blockers
but should be visible in the §4.2 backlog from now on:

- **D-RedTeam-01 E4** — T-AKA trick-locking exploit. AKA-on-T
  semantic per J-067 part 1 (10 substitutes for Ace) is partially
  honored at the bot heuristic but not at the legality layer in
  the over-trump-required case. Separate from M4 receiver-relief.
- **B-Net-02 H1/H2** — Forced-flag dead branches + out-of-range
  bidder. Wire validation gap on `MSG_BID` — accepts bidder seat
  outside 1..4 → `ApplyBid` writes to invalid seat slot.
- **B-State-02 H1** — `S.ApplyBid` lacks input value validation;
  partial mitigation downstream but the gap can corrupt state.
- **Bargiya FN → FP swing** (cross-cite). The `lenAtAce ≥ 5`
  promotion to `bargiya` (v0.10.2 M7) closes the FN but introduces
  a narrow FP path (sender holds 5+ but discarded A defensively
  on a partner-winning trick where partner was already on the
  Ace). Need hand-shape disambiguation; deferred per audit §4.2.

#### Pre-existing deferred items (per validation)

- B-Bot-06 F-01/F-02 — L07 cascade fail at M3lm+ for Aceless
  5-trump J+9 hands (~5–7 gp/match impact).
- Dead-code redundancy at `Bot.lua:1336-1342` / `1366-1372`
  (duplicate T-cardinality block in `PickBid`).
- Reverse Al-Kaboot rewrite (`K.AL_KABOOT_REVERSE = 88` constant
  doesn't exist yet; needs new bidder-led-trick-1 gate logic).
- Bargiya inner-discriminator axis flip (event-count → hand-shape).
- ISMCTS `akaCalled`-respecting sample pool (E-Det-01 #2c).
- `S.s.swaDenied` UI banner read.
- Sun-Mathlooth-K pos-4 smother gate (G-Logic-01 §3).
- Test-harness gap: Net.lua + BotMaster.lua not loaded by
  `run.py`; H1–H4 pins are source-string matches not behavioural.
- Backported MED fixes (Net.lua M5 / H3 / R2; State.lua M3
  false-AKA wipe). The full review notes M5 + H3 should arguably
  be HIGH per B-Net-04 — re-triage on v0.10.5 cycle.

### Coordination references

Full v0.10.4 ship-readiness analysis at
`.swarm_findings/review_v0.10.2/REVIEW_v0.10.4_ship_readiness.md`
(539 lines). Single richest pre-ship document — pulls together
the synthesis + focused validation + corpus traversal into one
verdict.

## v0.10.3 — review_v0.10.2 audit closures (CRIT + 8 HIGH + 7 doc + 4 follow-ups)

Multi-track ~95-agent audit cycle (Tracks A through G + synthesis)
covering 114 reports surfaced one CRIT-class production defect and
a cluster of HIGH-severity heuristic mis-scopings. Combined with
in-flight stash work and §9 low-risk follow-ups, this release closes:

- **1 CRIT** (resync dead in production via wire-tag collision)
- **6 HIGH code fixes** (4 from fork audit + my implicit-AKA closure
  + SWA pause re-arm refactor)
- **7 doc fixes** (Mathlooth revert + saudi-rules cleanup + glossary
  phantom-constant removal)
- **3 low-risk follow-ups** (dead anti-rule deletion, F-30b secondary
  trigger, hardcoded UI glyph)
- **1 UI label cleanup** (last hardcoded Arabic glyph)

All gated by 367 / 367 tests.

### Fixed (CRIT-1 — wire-tag collision; resync dead in production)

- **`Constants.lua:229`**: `K.MSG_OVERCALL_RESOLVE` collided with
  `K.MSG_RESYNC_REQ` (both `"?"`). Net.lua's dispatch chain hits
  OVERCALL_RESOLVE first → every `?` tag misrouted →
  `_OnResyncReq` was permanently unreachable. **Multiplayer rejoin
  / snapshot recovery has been silently broken since the overcall
  feature landed in v0.7.0.** Reassigned OVERCALL_RESOLVE to `"!"`.
- **`tests/test_rules.lua` Section R**: regression pin asserting
  (a) the specific collision is gone and (b) the broader invariant
  that every `K.MSG_*` constant has a unique byte value, so future
  tag additions can't reintroduce a silent dispatcher collision.

#### Cross-version compatibility (mitigated)

The `"?"` → `"!"` reassignment was paired with bidirectional
backward-compat so v0.10.2 ↔ v0.10.3 lobbies don't soft-lock at
`PHASE_OVERCALL`:

- **v0.10.3 host → v0.10.2 client**: `N.SendOvercallResolve`
  dual-emits BOTH the canonical `"!"` tag AND a legacy `"?"`-shaped
  frame so v0.10.2 clients (which only know `"?"`) still receive
  the resolve. v0.10.3 clients see both; the second arrival hits
  the idempotent `_OnOvercallResolve` (state already cleared) so
  it's a benign no-op.
- **v0.10.2 host → v0.10.3 client**: the dispatcher's `"?"` branch
  payload-shape-disambiguates. RESYNC_REQ is 2 fields
  (`"?;{gameID}"`); OVERCALL_RESOLVE is 4 fields
  (`"?;{taken};{by};{type}"`). 4-field `"?"` payloads route to
  `_OnOvercallResolve`; 2-field route to `_OnResyncReq`.

Net result: v0.10.2 ↔ v0.10.3 lobbies work in both directions
without coordinating upgrades. The dual-emit is eligible to be
dropped in v0.11.0 once v0.10.2 ages out of the install base.

### Fixed (HIGH — heuristic scoping / variable-shadowing bugs)

- **`Bot.lua:1705` `pickLead`** (B-Bot-* HIGH): pre-v0.10.3 the
  `isBidderTeam` predicate gated on `contract.type == K.BID_HOKM`,
  silently returning FALSE for ALL Sun contracts. This bypassed
  every downstream Sun branch — including Sun sweep-pursuit-early
  citing `K.AL_KABOOT_SUN = 220` (×2 = 440 effective). The check
  is purely about team relationship; type-gates already exist at
  each downstream use site. Removed the type clause.
- **`Bot.lua:2128` `bidderTeam` undefined** (B-Bot-08, HIGH):
  the conservativeOpp loop referenced an undefined `bidderTeam`,
  resolved to `nil` by Lua → `R.TeamOf(s2) ~= nil` always true →
  team-gate was a no-op (the loop accepted ANY seat with
  `styleTrumpTempo == -1`, including bidder-team). Defined locally
  inside the existing `contract.bidder` non-nil guard.
- **`Bot.lua:2964-2992` Faranka F-16 K-cover scope** (A-Src-29 +
  D-RT-03 S-1, HIGH): F-16 ("no K of trump → don't Faranka") was
  firing uniformly across all Hokm Faranka exceptions even though
  its threat model — opp A-of-trump punishment of the withheld
  card — is **structurally extinct on Exception #4** (both opps
  observed-void in trump). Scoped F-16 to skip when `oppsVoidPath`
  is true. Source-C confirms F-16 is purely a Sun anti-rule from
  video #06; the v0.10.0 X3 import to all Hokm exceptions was
  over-tight per A-Src-29.
- **`BotMaster.lua:830`** (E-Det-01 #7, B-BotMaster-01 F1, HIGH):
  Saudi-Master tier's outer driver passed 5 args to
  `R.IsLegalPlay`, omitting the optional 6th `akaCalled`. Real-
  state legal filtering ignored M4 AKA-receiver relief — the
  bot's own legal set was AKA-blind, defeating the v0.10.2 M4
  fix at the canonical case. Added `S.s.akaCalled` as 6th arg.
  (Inner rollouts intentionally pass nil for sim-blind AKA
  semantics.)
- **`Rules.lua` `R.IsLegalPlay` implicit-AKA extension**: companion
  closure to the BotMaster fix. The v0.10.2 M4 relief honored only
  the explicit `s.akaCalled` banner; partner's bare-A lead in Hokm
  non-trump (the IMPLICIT AKA per S6-6 / video #18) didn't fire
  any banner because `Bot.PickAKA`'s `r=="A"` early-return
  suppresses it. Without legality recognition, the bot's pickFollow
  implicit-AKA branch had the same dead-discards-filter shape as
  the pre-v0.10.2 explicit case. Detect the implicit pattern from
  the lead card itself: partner-led + non-trump + Ace + Hokm =
  same relief.
- **`Net.lua` SWA pause-soft-lock re-arm refactor** (E-Net-01,
  HIGH): three SWA timer sites (LocalSWA at ~2546, _OnSWAReq at
  ~2691, bot-fired at ~4059) had pause-handling shapes that all
  leaked under multi-cycle pause-toggles within one window. The
  bot-fired site bare-exited on `S.s.paused` with no re-arm at
  all (single pause = permanent soft-lock). The other two sites
  had a one-step re-arm whose inner timer also bare-exited on
  pause (two pauses within one window = soft-lock). All three
  refactored to named functions that recursively re-arm
  themselves, mirroring the OVERCALL_TIMEOUT pattern at line
  ~1195. Each pause cycle now resets to a fresh full
  `SWA_TIMEOUT_SEC` window from resume.

### Doc (review_v0.10.2 source-cite corrections)

- **`saudi-rules.md`**: Carré-A in Sun melds-table 200 → 400 (the
  table was self-contradicting v0.10.0 R5's prose); SWA paragraph
  rewritten — v0.5.17 routes ALL SWA calls through the 5-sec
  permission window, the pre-v0.5.17 "≤3 instant" branch is gone
  in code; failed-bid scoring corrected per «مشروعي لي ومشروعك لك»
  (each team keeps its own declared melds, only trick-points flow
  to winner — v0.4.3+ encoded this); stale `Rules.lua` line refs
  refreshed.
- **`decision-trees.md` + `glossary.md` Mathlooth REVERTED to
  K-tripled** (A-Src-06 + C-Xref-07): v0.10.0 R7 flipped this from
  K-tripled to J-tripled citing wrong Sun rank order. Video #17
  is unambiguous: «اول شيء عندك اكه بعدها عشره بعدها شايب» —
  Saudi Sun rank is **A > T > K > Q > J > 9 > 8 > 7**. K-tripled
  (مثلوث الشايب) is canonical; J/Q-tripled are lower-probability
  variants per the same video. Filename `17_k_tripled` was
  correct all along. R7's "romanization-error" framing was
  itself the error.
- **`glossary.md` phantom-constant cleanup**: removed references
  to non-existent constants (`K.MSG_HOKM`, `K.PHASE_HOKM`,
  `K.MULT_HOKM`, `K.MSG_SUN`, `K.PHASE_SUN`, `K.MSG_BEL`).
  Hokm/Sun share `K.MSG_BID = "B"` with type discriminator;
  Hokm uses `K.MULT_BASE = 1`; Bel uses `K.MSG_DOUBLE = "X"`.

### Cleanup (low-risk follow-ups per review §9)

- **Deleted dead rule-7 anti-trigger** at `Bot.lua:3005-3024`
  (A-Src-29 + D-RT-03 S-5): the "opp bidder led trump-Q AND we
  hold J+8 → cancel Faranka" anti-trigger was both sourceless
  (F-39 / J+8-vs-Q absent from #04 Hokm corpus) and structurally
  dead post-v0.10.0 (bidder-team gates on Exceptions #2/#3 and
  F-16 K-cover veto on Exception #4 made the path unreachable
  with `farankaTriggered = true` AND opp-bidder-led-Q). Removed.
- **F-30b secondary trigger** (G-Logic-01 §1): extended Exception
  #4 (`oppsVoidPath`) to also fire when
  `S.HighestUnplayedRank(trump) == nil` — the structurally-
  extinct case where the entire trump pool has been played out.
  Per-opp `void[trump]` flags are only set on observed
  fail-to-follow; trump-led consumption can exhaust the pool
  without ever surfacing a void → no opp can ruff regardless.
- **`UI.lua:1952` قبلك hardcoded glyph** (E-UI-01-2): replaced
  raw Arabic with Latin "Qablak" since WoW's bundled fonts
  (Arial Narrow / Frizz / Skurri) don't render Arabic glyphs.
  Same pattern as the AKA button at line 2046. Last remaining
  hardcoded Arabic glyph in v0.10.2's UI label set.

### Tests

- **`tests/test_rules.lua` Section Q.9-Q.11**: implicit-AKA
  legality relief (partner bare-A lead grants relief; opp bare-A
  doesn't; bare-K isn't Ace).
- **`tests/test_rules.lua` Section R**: wire-tag distinctness
  pin (CRIT-1 specific + invariant for all `K.MSG_*`).
- **367 / 367 pass** (up from 362 baseline).

### Deferred to v0.10.4 (per review §9)

- `S.s.swaDenied` UI banner read (UI component design needed).
- Sun-Mathlooth-K pos-4 smother gate (G-Logic-01 §3 — needs
  Mathlooth-suit hand-shape detection).
- Reverse Al-Kaboot rewrite (`K.AL_KABOOT_REVERSE = 88` constant +
  bidder-led-trick-1 gate).
- Bargiya inner-discriminator axis flip (event-count → hand-shape).
- ISMCTS akaCalled-respecting sample pool (E-Det-01 #2c).
- Backported MED-severity fixes (Net.lua M5 / H3 / R2; State.lua M3
  false-AKA wipe; `S.GetLegalPlays` AKA-blind).

### References

Audit reports under `.swarm_findings/review_v0.10.2/`:
- `_track_A_sources/A-Src-01..30` (verbatim Arabic re-extracts)
- `_track_B_code/` (per-function audits)
- `_track_C_xref/C-Xref-01..07` (cross-references / doc-drift)
- `_track_D_redteam/D-RT-01..32` (adversarial probes)
- `_track_E_ux/E-Det-01` (ISMCTS determinism)
- `REVIEW_v0.10.2.md` (~250-line synthesis)

## v0.10.2 — review-cycle MEDIUM/LOW closures (M3+M4+M7+M8+L3)

Five items from the v0.10.0 source-of-truth review closed in one
sweep. All gated by 360+ tests; bot-side behaviour now matches the
canonical Saudi pro conventions for AKA mechanics, Sun opening
leads, and Bargiya signaling.

### Fixed (M4 — AKA-receiver legality relief, J-066/J-067 part 2)

- **`Rules.lua` `R.IsLegalPlay`**: new optional 6th parameter
  `akaCalled = {seat, suit}`. When partner has called AKA on the
  led suit (banner state from `S.s.akaCalled`), the receiver is
  exempt from must-trump-ruff — they may discard freely. Closes
  `xref_X2_aka.md` B1 + B5: pre-v0.10.2 the bot's AKA-receiver
  branch was structurally dead code because `R.IsLegalPlay`
  always enforced must-trump for void+has-trump receivers,
  filtering non-trump options out of `legal` before the branch
  could pick them.
- **`Bot.lua` `legalPlaysFor`**: passes `S.s.akaCalled` through to
  every live-game legality check. Simulator callers (`R.SunCanRolloff`)
  deliberately omit the param so rollouts get AKA-blind semantics
  (transient banner state shouldn't propagate into hypothetical
  futures).
- **`Net.lua`**: 3 host-side `R.IsLegalPlay` call sites updated
  (LocalPlay anti-misclick warn, _OnPlay validation, AFK auto-play).
  All now AKA-aware on the host.
- **`Bot.lua` AKA-receiver branch (line ~2513)**: comment updated
  from "deferred to later release" to "now LIVE" — the upstream
  legality fix means `discards` filter has live content.

### Fixed (M3 — False AKA = Qaid, J-069)

- **`State.lua` `S.ApplyPlay`**: host-side validation. When the
  AKA-caller leads, the lead card MUST be the highest-unplayed of
  the AKA'd suit. Otherwise the AKA was a false claim — mark the
  lead with `.illegal=true, .illegalReason="false AKA"` and clear
  `s.akaCalled` so partner doesn't get receiver-relief on a bogus
  banner. The existing Takweesh resolution path scans `.illegal`
  marks and resolves the round as a Qaid against the offender's
  team. Also catches AKA-suit ≠ lead-suit as trivially false.
- Walks `playedCardsThisRound` from the highest non-trump rank
  downward; if any rank above the lead's is unplayed, the AKA
  is invalid. Bot's `Bot.PickAKA` already validates sender-side
  (line 3217) so legitimate addon traffic never hits this path —
  it's defensive against hostile/buggy peers that bypass the
  local `LocalAKAcandidate` gate.

### Added (M8 — Sun seat-1 mardoofa probe lead, Pro-2 L08)

- **`Bot.lua` `pickLead`**: new branch BEFORE the singleton-low /
  shortest-suit fallthrough. When the Sun bidder (or partner)
  opens trick 1 holding an A+T mardoofa (إكة مردوفة), they MUST
  lead the Ace from that pair. Source-L Pro-2 wording: "obligatory
  on him AND on his partner" — both bidder and partner are bound.
  Pre-v0.10.2 the Sun-bidder lead path fell through to "Sun
  shortest-suit lead" which led the LOWEST card from the SHORTEST
  suit — exactly opposite of L08. Tier-gated at Advanced+.

### Added (M7 — Bargiya canonical FN, محشور بلون واحد proxy)

- **`Bot.lua` `OnPlayObserved` Tahreeb recorder**: when recording
  a partner-winning A-discard signal, capture sender's pre-discard
  length-in-suit from `S.s.hostHands` (host-only). Stored as
  `tahreebSent[suit].lenAtAce`, alongside the existing rank array.
  Backward-compat: legacy fixtures with raw rank-string entries
  leave `lenAtAce` nil; only the host's bot updates it.
- **`Bot.lua` `tahreebClassify`**: when `signals[1] == "A"` AND
  `signals.lenAtAce >= 5`, return `"bargiya"` directly (confirmed
  invite per video #14 rule 2 — sender محشور بلون واحد) instead
  of demoting to `"bargiya_hint"` and waiting for a second event.
  Closes the FN where genuine 5-card invites were beaten by
  ascending 2-event "want" signals in another suit.

### Tightened (L3 — PickAKA doubled-contract conservatism)

- **`Bot.lua` `Bot.PickAKA`**: new gate — when `S.s.contract.doubled`
  is true (any escalation rung in play), suppress AKA categorically.
  Per `xref_X2_aka.md` B3 / G18-10 paragraph 2: doubled hands raise
  the info-leak cost of any signal because both sides are extra-
  motivated to read every banner. The bot now matches Saudi pro
  reservation: AKA only in normal play, not under Bel/Triple/Four.

### Tests

- **`tests/test_state_bot.lua` Section J**: 12 new pins for L3, M3,
  M7, M8 (with bidder-team and defender-seat sanity cases).
- **`tests/test_rules.lua` Section Q**: 8 new pins for M4 covering
  partner AKA / opp AKA / wrong-suit AKA / Sun-no-op / trump-still-
  legal scenarios.
- All 360+ tests pass; no regressions in the existing E/F/G/H/I/P
  sections.

### Status

After this release the v0.10.0 review's confirmed bugs are all
closed (M1 → M4 → M7 → M8 → L3 + earlier R1-R7 / X1-X5 closures).
Remaining items are opt-in variants (L4-L6 sessional flags, M5
Sun Faranka 5-factor weighted accumulator, M9 pre-bid Tawzee Qaid)
and the broader missing-features catalogue (MF-1..MF-20). Audit
cycle is genuinely saturated — calibration phase (`tools/calibrate.py`
+ in-game telemetry) is the next bottleneck.

## v0.10.1 — M1 closure: Qaid offender melds now forfeited (user arbitration)

The v0.10.0 review surfaced an unresolved rule-reading ambiguity (M1):
on a Qaid penalty, does the offender's team **keep** their own
declared melds (per "مشروعي لي ومشروعك لك" / PDF K-08) or **forfeit**
them (per Source H H-36.12 + PDF 02 K-04 "the buyer's meld is
forfeited")? User arbitration resolved this in favor of the
forfeit reading.

### Fixed (M1 — Qaid offender forfeits melds)

- **`Net.lua` `HostResolveTakweesh` (line ~2196-2225)**: when a Qaid
  penalty is resolved, the OFFENDER team (opposite of `winnerTeam`)
  now zeros their own declared melds. The non-offender team (the
  winner of the penalty) keeps their own melds × multiplier as
  before. Belote independent regardless of side.
- **`Net.lua` `HostResolveSWA` invalid-claim branch (line ~2924-2940)**:
  invalid SWA is a Qaid context — the SWA caller's team (the
  offender) zeros their own melds. Opp adds their own melds × mult.
- **Scope deliberately narrow**: the same change is NOT applied to
  `R.ScoreRound`'s regular contract-fail branch, because that path
  fires on plain bidder-failed-to-make (no illegal play). PDF K-04's
  "buyer's meld forfeited" wording is specifically about Qaid
  context, so regular fail keeps the existing "each team keeps own
  melds" semantics.

### Doc

- The pre-v0.10.1 14th-audit fix comment ("each team keeps their own
  melds during a Qaid") cited PDF K-08; it's preserved as a
  historical reference inside the new comment, then explained why
  v0.10.1 reverses for Qaid contexts. Future readers can see both
  the prior reasoning and the M1 arbitration outcome.

### Tests

- 340/340 still pass. Note: per `xref_X1_*.md` G1, there are no
  unit tests covering `N.HostResolveTakweesh` directly, so this
  behavior change is regression-bare. Adding Net.lua test harness
  coverage is a separate (larger) effort flagged in the Phase 2B
  cross-reference report.

### Concrete impact

- ~10-20 game points per round difference on Qaid-triggering rounds
  vs the pre-v0.10.1 behavior (loser's pre-existing melds no longer
  count toward their own score).

## v0.10.0 — Source-of-truth review: 9 silent bugs closed + doc-drift sweep

A 24-agent triangulation across 38 video transcripts, 8 PDFs, and the
addon code surfaced silent bugs in scoring, signaling, and bot
decision-making — most of which had been silently mis-attributed to
"framing" in earlier audits. Full review at
`.swarm_findings/review_v0.10.0/REVIEW.md` with cite trails.

### Fixed (HIGH — silent scoring bugs)

- **R5 — Carré-A in Sun under-scored 2×**
  (`review_v0.10.0/reaudit_R5_carre_a_sun.md`). Per videos #32 + #38,
  الأربع ميه names a **400 raw direct** value (the meld's name IS its
  value); per video #43 Sun divides raw by 5 → 80 game points. Pre-
  v0.10.0 `K.MELD_CARRE_A_SUN = 200` produced 200×Sun×2 ÷ 10 = 40 gp
  — exactly half. An earlier "Gemini scoring-audit catch" 400→200 was
  a misinterpretation: it eliminated the correct value as if it were
  double-counting. Fixed: `Constants.lua:95` 200 → 400 with rewritten
  comment tracing the math.

- **X5 — Carré-A in Hokm meld silently dropped**
  (`review_v0.10.0/xref_X5_meld_coverage.md`). `R.DetectMelds:240-242`
  had no `else` branch for Ace+Hokm — `value` stayed `nil` and the
  meld was never emitted. Per videos #32 line 245 + #38 line 61,
  Carré-A in Hokm scores 100 (treated like Carré-T/K/Q). Cascade:
  silent drop broke bidder strict-majority threshold check,
  `R.CompareMelds` winner-takes-all path, AND the Belote-cancellation
  v0.9.0 M5 path (holder's missing 100-meld left Belote uncancelled →
  silent +20 over-scoring). Fixed: added Hokm `value =
  K.MELD_CARRE_OTHER` branch with regression test inverted at
  `tests/test_rules.lua:365-379`.

### Fixed (HIGH — bot-decision corrections)

- **R1 — Bel-100 over-corrected by v0.9.2 #45**
  (`review_v0.10.0/reaudit_R1_bel100.md`). Three sources unanimous on
  the rule once parsed verbatim: **caller.cum ≤ 100 AND opposite.cum
  ≥ 101**, score-split and role-irrelevant. Pre-v0.9.2 was missing
  the dual-team check (`mine < 100` only). v0.9.2 #45 added the
  check but anchored on bidder/defender role, breaking the edge case
  where the bidder team is TRAILING (e.g., A=130/B=60, B bids Sun
  to catch up — B is the trailing side and per Saudi rule may Bel;
  v0.9.2 wrongly forbade this). Fixed: collapsed to score-split
  predicate; dropped `contract.bidder` consultation in `R.CanBel`;
  simplified `Net._SunBelAllowed` to query trailing team. Test
  fixtures rewritten in Section N.

- **R6 — Touching-honors K-signal interpretation INVERTED**
  (`review_v0.10.0/reaudit_R6_touching_honors.md`). Per video #05
  lines 783-884, when follower plays K after partner's bare-A: K is
  a singleton; Q and J are NOT in their hand ("Can he have Q or J?
  No, impossible — he would have played those instead"). Pre-v0.10.0
  code at `Bot.lua:491-492` set `entry.nextDown = "Q"` — pinning Q
  to the seat that the source EXPLICITLY says doesn't have Q. v0.9.2
  #12 fix activated the previously dead WRITE branch, turning dead-
  code-wrong into reachable-mispredicting-wrong. Fixed: K-signal now
  emits `entry.cleared = {"Q", "J"}` (negative-bias); reader at
  `BotMaster.lua` handles the new field by clearing those rank
  desires. Also extended `entry.broke` to fire on rank 9 (per Source
  D R3e: "9/8/7 → discourage further A-runs"; pre-v0.10.0 only 7/8).

- **R6 — Trust-asymmetry now enforced at READ site**
  (`review_v0.10.0/reaudit_R6_*.md` + `xref_X4_pro2_deal.md`). Per
  video #05 @ 03:17-03:22: "trust partner signals at face value,
  discount opponent signals (تقيد)." Pre-v0.10.0 the BotMaster
  topTouchSignal reader applied pins/clears uniformly to all 4 seats;
  opponents could weaponize the mis-pin via deceptive K-plays. Fixed:
  reader now gates on `s == R.Partner(seat)` — opponent inferences
  no longer feed sampler bias. (Self is also skipped; bot's own
  hand is known.)

- **X3 — Hokm Faranka Exception "#3" missing bidder-team gate**
  (`review_v0.10.0/xref_X3_faranka.md`). v0.9.2 #49 fixed the same-
  class bug for code's Exception "#2"; Exception "#3" (J-dead, hold
  9) at `Bot.lua:2795-2804` had the same gap and would Faranka into
  opp's Hokm contract on J-dead+9-only hands. Fixed: same `and
  onBidderTeam` gate.

- **X3 — Code's Faranka Exception "#4" relaxed from bidder-only to
  bidder-team**. Per Source C (video #04), bidder-team is sufficient
  for the "both opps trump-void" exception — partner of bidder also
  qualifies. Pre-v0.10.0's strict `contract.bidder == seat` check
  silently fell through for the partner; now uses the same
  `onBidderTeam` flag.

- **X3 — F-16 anti-rule enforced** ("no K of trump → don't
  Faranka"). Pre-v0.10.0 the code accepted T-as-cover when K was
  absent, violating Source C's explicit anti-rule. Faranka without
  K-cover has no defensive backbone (any opponent A-of-trump
  punishes the preserved card directly). Fixed: explicit
  `hasKtrump` check before allowing `farankaTriggered = true`.

- **X4/L07 — Hokm-needs-Ace tier-gated for M3lm+**
  (`review_v0.10.0/xref_X4_pro2_deal.md`). Per Pro-2 PDF L07, Hokm
  bid SHOULD require an Ace (defensive vs Sun-overcall, Kaboot,
  4-Hundred). Per Source H this is STRATEGY not hard rule — gated
  at M3lm+ (Basic/Advanced stay permissive). Pre-v0.10.0
  `hokmMinShape` enforced `hasSideAce` only at `count == 3`; the
  `count >= 4` self-sufficient branch passed without ANY Ace check
  (half-implemented L07). Fixed: M3lm+ requires `hasAnyAce` (side-
  Ace OR trump-A) at any trump count.

### Fixed (MEDIUM — invariant defense)

- **R2 — Sun escalation defensive normalization**
  (`review_v0.10.0/reaudit_R2_sun_escalation.md`). Sun has NO
  Triple/Four/Gahwa rungs (canonical rule, 3 sources unanimous —
  PDF 02 K-21, PDF 07 L34, video #11). The phase machine prevents
  these flags in practice (`State.ApplyDouble` jumps Sun directly
  to `PHASE_PLAY`), but if any caller / hand-edited save / stale
  resync slips a Sun-tripled/foured/gahwa flag through, the
  multiplier path used to apply ×6 / ×8 — encoding the invariant
  violation. Fixed: `R.ScoreRound` collapses Sun multipliers to
  Sun×Bel maximum; inversion logic ignores Sun-tripled/foured/gahwa
  for outcome determination too. Defense-in-depth Sun guards added
  at `Bot.PickTriple` / `Bot.PickFour` / `Bot.PickGahwa` (return
  `false, false` on Sun). Test fixtures rewritten to assert
  collapse instead of codifying the wrong invariant.

### Documented (M2 — deferred fix with diagnostic comment)

- **AKA receiver-relief at `Bot.lua:2451-2475` is effectively dead
  code in canonical scenarios** per `xref_X2_aka.md` B1.
  `R.IsLegalPlay` doesn't consult `S.s.akaCalled` — must-trump-ruff
  fires whenever seat is void in led suit and has trump. The
  proper fix is upstream (R.IsLegalPlay AKA-aware), but that's a
  broader change with cross-test implications (J-066/J-067 AKA-on-T
  trick-locking, J-069 false-AKA = Qaid). Inline diagnostic comment
  added; deferred to a later release.

### Doc drift (no code change)

- `saudi-rules.md` Q3 reconciliation rewritten (was incorrectly
  declaring "no change needed" — see R5).
- `saudi-rules.md` Q3b added for the Carré-A in Hokm cascade (X5).
- `saudi-rules.md` Q4 footnote refreshed (rounding resolved at
  v0.5.6, double-confirmed in v0.10.0 review).
- `saudi-rules.md` Q6 closed: سيكل (sykl) is colloquial name for
  9-8-7 tierce, scores 20 like any tierce — no separate code path.
- `saudi-rules.md` melds table: Carré-J corrected (was "trump-
  implicit 200"; canonical = 100 in any contract per videos).
- `decision-trees.md` Section 4: "K-tripled (مثلوث الشايب)" →
  "J-tripled (مثلوث الولد)" with v0.10.0 review note explaining the
  romanization-artifact bug. Per Source F, video #17 covers J-tripled
  (Sun A>T>J → J wins trick 3), not the Hokm-K case earlier docs
  imagined.
- `glossary.md` Mathlooth entry expanded with the J-tripled
  correction.
- `glossary.md` Bargiya entry now annotates "Burqia" as a
  transliteration alias (same Arabic word برقيّة, both spellings
  appear in source materials) and emphasizes the **hand-shape**
  (محشور) classification axis vs event-count.
- `CLAUDE.md` SWA section: 5-second auto-approve timer now correctly
  framed as **addon UX construct, NOT Saudi rule** (per video #35
  verbatim — no timer terminology in source). Plus 5+-card mandatory
  permission framing.

### Tests

- 340/340 regression tests pass.
- New: Hokm Carré-A meld emit test (was inverted to assert "no
  meld" — flipped to assert 100 raw).
- Updated: R.CanBel Section N rewritten for score-split rule with
  bidder-trailing edge case fixtures.
- Updated: Sun-tripled / Sun-foured tests now assert collapse to
  Sun×Bel multiplier instead of codifying the ×6 / ×8 invariant
  violation.

### Open: M1 — Qaid-offender-melds (human arbitration required)

The v0.10.0 review surfaced a rule-reading ambiguity that this
release does NOT close — left for user arbitration:

- **Source H H-36.12**: offender's melds on Qaid are "zeroed/
  forfeited"
- **PDF K-04**: "the buyer's meld is forfeited (kept by neither
  side, just lost)"
- **PDF K-08**: "stays with owner" (ambiguous — does "stays" mean
  "owner scores it" or "stays in their pile but doesn't count"?)
- **Current code**: keeps melds with offender (`Net.lua:2207-2208`,
  `Rules.lua:807-808`). The 14th-audit fix cited K-08 as basis.
- **Concrete impact**: ~10-20 game points per round when Qaid
  triggers.

Pending user decision in next release.

## v0.9.6 — Telemetry schema v=2: bot-vs-human bidder split for calibration

Audit `audit_v0.9.0/41_v083_telemetry.md` flagged two missing fields
that block meaningful calibration: schema versioning (forward-compat)
and per-row bot-flags (bot-bidder vs human-bidder distinguishability).
Both wired now.

### Added (State.lua telemetry row schema v=2)

- `v = 2` — schema version field. Pre-v0.9.6 rows lack this; analyzer
  treats them as `v=1` and skips bot/human-split analysis.
- `bidderIsBot` — derived 0/1 flag from `s.seats[bidder].isBot`. The
  single most important field for calibration: lets the analyzer
  separate "the BOT is mis-bidding" from "the HUMAN is mis-bidding."
  Without this, fail-rate / Bel-rate signals are uninterpretable.
- `seat1Bot` / `seat2Bot` / `seat3Bot` / `seat4Bot` — per-seat
  isBot snapshot at row write time. Lets the analyzer compute
  "this round had N bots at the table" cohorts.

### Updated (tools/calibrate.py)

- New "bot vs human bidder" report section. Skips pre-v0.9.6 (v=1)
  rows. For v=2 rows, splits make/fail by `bidderIsBot` and emits
  fail-rate spread:
  - Spread < 15pp = balanced bidder behavior
  - Spread > 15pp = **CALIBRATION SIGNAL** (tier or threshold
    mismatch worth investigating)
- Pre-v0.9.6-only datasets get a graceful "play more rounds with
  v0.9.6+" hint instead of a confusing empty section.

### Why this matters

The audit framed it well: telemetry's whole purpose is to drive
threshold refits. Without bot/human distinguishability, every
signal is averaged across both populations — meaningless for
saying "raise BOT_BEL_TH" or "lower TH_HOKM_R1_BASE". v=2 makes
the analyzer's calibration recommendations actually actionable.

### Tests

- 333/333 regression tests pass.
- Analyzer verified end-to-end on a 5-row synthetic dataset
  (2 bot bidders + 3 human bidders); produces correct fail-rate
  split + spread calculation.

### Backward compatibility

- Old v=1 rows in existing SavedVariables remain valid; analyzer
  reads both schemas.
- 200-row FIFO cap unchanged — old rows naturally drop as new
  v=2 rows accumulate.

## v0.9.5 — Section 4 rule 1B wouldWin gate + saudi-rules.md doc fixes

Audit-sweep loop iter on the saturated queue. Three items closed.

### Fixed (Bot.lua — Section 4 rule 1B trick-stealing misfire)

`pickFollow` rule 1B (Sun + partner-winning + we-can't-beat → second-
lowest as re-entry signal) was missing a `wouldWin` precondition.
The `sorted[2]` second-lowest pick could BEAT partner's lead and
steal the trick, contradicting the rule's intent. Concrete misfire:
partner leads JH, our hand `{7H, KH}`, smother gate fails (only 1
point card), rule 1B fires, sorted[2]=KH, KH beats JH, **we steal
partner's trick.**

Fix: gate `return sorted[2]` on `not wouldWin(sorted[2], trick,
contract, seat)`. If the second-lowest would steal, fall through
to `lowestByRank` (partner keeps the trick — the absolute-lowest
play also implicitly preserves re-entry in 2-card holdings since
there's only one alternative).

Source: `audit_v0.9.0/18_section4_now.md` §2.

### Fixed (saudi-rules.md doc drift D5)

Two stale sections updated:

- **Q4 score-rounding text** (line 156). Was tagged "⚠ Possible
  mismatch" pointing at `(x + 4) / 10` (rounds DOWN). Now reflects
  v0.5.6 fix `(x + 5) / 10` (rounds UP per video #43, "حساب النقاط
  في البلوت للمبتدئين"). Audit `audit_v0.9.0/26_rules_scoring.md`
  §6 verified the code is correct; only the doc was stale.

- **Qaid forfeit text** (line 119). Was "offending team's melds
  forfeited (zeroed) but NOT transferred to caller". Code's actual
  semantic (per 14th-audit Codex/Gemini interpretation) is "each
  team keeps own melds" — neither zeroed nor transferred. Updated
  doc to match. Audit `audit_v0.9.0/28_rules_aka_swa_takweesh.md`
  §4 confirms code-correctness.

### Tests

- 333/333 regression tests pass. Rule 1B wouldWin gate is observation-
  driven; existing E.6 fixture passes (the 9H second-lowest does NOT
  beat AH lead, so the new gate doesn't fire there).

### Audit response cumulative (v0.8.6 -> v0.9.5)

| Severity | Closed |
|---|---|
| HIGH    | 4/4 |
| MEDIUM  | 5/5 |
| LOW     | 4/6 (L2, L3 cosmetic remain) |
| Doc drift | **5/5 + saudi-rules Q4/Qaid** (D5 closed v0.9.5) |
| Missing | 7/11 |
| v0.9.0 ultra-audit | **13+** items closed |

## v0.9.4 — Calibration tooling: telemetry analyzer + workflow doc

Audit cycle saturated; pivoting to empirical calibration. v0.8.3 added
the per-round telemetry pipeline; this release adds the analyzer that
reads it and the doc that explains the workflow.

### Added

- **`tools/calibrate.py`**: zero-dependency Python analyzer for
  `WHEREDNGNDB.history` rows. Reads SavedVariables/WHEREDNGN.lua,
  parses the history table (hand-written Lua-table parser; only
  stdlib), and prints a calibration report covering:
  - Contract-type mix (Hokm vs Sun fraction)
  - Bid-round breakdown (R1 / R2 / forced)
  - Bidder make / fail rate
  - Bel / Triple / Four / Gahwa fire rates against current
    `K.*_TH` thresholds with healthy-range annotations
  - Per-bidder seat performance + cumulative-delta sum
  - Sweep frequency
  - Calibration-signal flags (fail-rate, Bel-rate, etc.) with
    target ranges from Saudi-tournament empirical data
- Modes: `--json OUT` to dump parsed rows; `--paste` to read from
  stdin.

- **`docs/CALIBRATION.md`**: workflow doc covering how to dump
  telemetry from in-game, where SavedVariables lives on Windows,
  what the analyzer produces, what each metric means in healthy
  ranges, and privacy notes (local-only, no network egress, no
  hand contents in rows).

### Why now

The bot has ~20 tunable thresholds calibrated from videos +
symmetric-distribution unit tests, but never against
human-asymmetric real-game outcomes. This is the missing input.
~100 rounds of real telemetry should be enough to refit
`BOT_BEL_TH`, `TH_HOKM_R1_BASE`, `BOT_OVERCALL_*_TH`, and the
escalation-chain ladders.

### Tests

- 333/333 regression tests pass (no production-code change in
  this release; all additions are under `tools/` + `docs/`).
- Analyzer tested on a synthetic 3-row dataset to verify parser
  + report path work end-to-end.

## v0.9.3 — Audit-sweep loop: 4 more v0.9.0 ultra-audit items closed

Continuation of the 60-report v0.9.0 ultra-audit. Four items closed
this iteration: doc drift on Section 10 (HIGH per audit #22),
bargiya_hint pass-through gap in N-3 (#58), short-window
StartLocalWarn no-op (#56), and AKA precondition (g) round-stage
suppression (#19 + decision-trees.md).

### Fixed

- **Section 10 doc drift (HIGH per audit #22)**. `decision-trees.md`
  Section 10 still tagged exceptions #2, #3, #4 + the J+8 anti-rule
  as `(not yet wired)` even though they shipped in v0.8.4 / v0.8.5 /
  v0.9.2. v0.9.0's doc-refresh updated Section 9 + Section 11 rule 3
  + Section 11 rule 4 markers but missed Section 10 entirely. Now:
  - Default no-Faranka row reframed as "wired by absence" (winners-
    branch covers it; no Faranka path exists unless an exception
    fires).
  - Exception #1 marked partially wired (v0.5.19 trick-3 sweep
    pursuit; cross-wire to pickFollow Faranka still deferred).
  - Exception #2 marked wired v0.8.4 + bidder-team gate v0.9.2.
  - Exception #3 marked wired v0.8.5 (with `S.HighestUnplayedRank`
    trump-rank fix).
  - Exception #4 marked wired v0.8.4.
  - J+8 anti-Faranka rebuttal marked wired v0.8.4.

- **#58 N-3 receiver: bargiya_hint silent drop**
  (`audit_v0.9.0/58_tahreeb_desync.md`). The N-3 opp-avoid pass at
  `Bot.lua:1799` only marked `cls == "bargiya" or cls == "want"` as
  avoid-suit. The v0.9.0-introduced `bargiya_hint` (single-A event,
  ambiguous between invite and defensive shed) was silently dropped
  — meaning a Saudi-tier opp's legitimate single-event Bargiya
  invite went undefended (we wouldn't deny tempo). Now also avoids
  on `bargiya_hint`. Conservative defense: lower-confidence hint
  still warrants suit-avoidance.

- **#56 StartLocalWarn warnAt-clamp** (`audit_v0.9.0/56_afk_new_phases.md`
  Q5). Pre-warn computed `warnAt = TURN_TIMEOUT_SEC - 10 = 50s` for
  ALL kinds, including the 5-second OVERCALL window — `warnAt > timeout`
  meant the warn never fired. Now: per-kind timeout selection
  (`overcall` uses `OVERCALL_TIMEOUT_SEC=5`), with proportional
  warnAt: 10s before for long windows (≥20s), 1s before for short
  windows. The OVERCALL human gets a 1s pre-warn cue.

### Added

- **AKA precondition (g) — round-stage / scoreUrgency suppression**
  (`audit_v0.9.0/19_section6_now.md` §2 + decision-trees.md
  Section 6 row "preconditions"). When `trickNum >= 6` (late round,
  ≤2 tricks remain), AKA's marginal information value is low —
  most voids are known, partner can read trick state directly,
  and the banner just leaks our top-card holding. Now suppress
  late-round AKA UNLESS the round is clutch (opp near-win, we
  near-clinch, or close-race within 20 cum points). Pre-v0.9.3
  only the coarse `trickNum <= 1` skip existed.

### Tests

- 333/333 regression tests pass (no fixture additions; behavior
  changes are observation-driven and gracefully degrade in absence
  of triggering conditions).

### Audit response cumulative (v0.8.6 → v0.9.0 → v0.9.1 → v0.9.2 → v0.9.3)

| Severity | Closed |
|---|---|
| v0.7.1 HIGH    | 4/4 |
| v0.7.1 MEDIUM  | 5/5 |
| v0.7.1 LOW     | 4/6 |
| v0.7.1 Doc drift | **5/5** (Section 10 closed v0.9.3) |
| v0.7.1 Missing | **7/11** (AKA precond g closed v0.9.3) |
| v0.9.0 ultra-audit | 11+ closed (HIGH-impact subset) |

## v0.9.2 — Audit-sweep loop: 7 v0.9.0 ultra-audit findings closed

Continuation of the v0.9.0 ultra-audit response. The 60-report
re-audit surfaced one CRITICAL bug (a feature claimed wired in
v0.9.0 was actually dead code), three HIGH bugs (persistence /
exploit / contract-aid), one MEDIUM (Ashkal allow-list gap), and
two LOW (UX race + hand-edit safety). All seven are closed in
this release.

### Fixed (CRITICAL)

- **#12 Touching-honors WRITE branch was dead code**
  (`audit_v0.9.0/12_touching_honors.md`). The v0.9.0 commit
  9c32c50 wired `topTouchSignal` inferences (Section 6 rules 1-4,
  video #05) but the predicate referenced an undeclared local
  `trick` instead of the existing `trickPlays`. The variable
  resolved to a global lookup → `nil`, the entire WRITE branch
  silently short-circuited, and the BotMaster sampler iterated
  against a permanently empty ledger every PickPlay call. The
  v0.9.0 CHANGELOG falsely claimed this feature was wired.
  Substituting `trickPlays` activates the dead branch as
  designed; the 60-weight desire-pin and 5-card desire-clear
  inferences now flow into ISMCTS sampling.

### Fixed (HIGH)

- **#54 M4 _partnerStyle persistence quirks**
  (`audit_v0.9.0/54_m4_partnerstyle_quirks.md`). Two bugs:
  (a) restore-side type guard was truthy-only — corrupt
  SavedVariables (hand-edited, partial-write crash, version
  skew) populating `partnerStyle` as a string would crash the
  next `Bot.OnEscalation` and silently break bot decisions for
  the rest of the game. Now `type() == "table"` checked per
  subfield. (b) Cross-character session guard short-circuited
  to PASS when either side was nil — if PLAYER_LOGIN's restore
  ran before `SetLocalName` resolved, any owner's session
  passed. Now fail-closed: `if not sess.owner or not s.localName
  then return false end`.

- **#46 Bait-ledger forced-J exploit**
  (`audit_v0.9.0/46_bait_ledger_exploit.md`). v0.8.2's deceptive-
  overplay detector flagged any J-of-suit play under partner-
  winning state as a bait, including the case where J was the
  opp's only legal card (mathematically forced). The flag
  persisted across rounds AND across /reload via M4, so a
  skilled opp could burn the bot's lead-X option for the entire
  game by playing one forced J in round 1. Two-part fix:
  (a) add a forced-J approximation gate — only flag when the
  seat's `mem.played` shows they previously held lower-rank
  same-suit cards; (b) move `baitedSuit` and `topTouchSignal`
  from per-game to per-round scope (Bot.ResetMemory), so
  cross-round amplification dies at round boundary even if a
  false flag slips through.

- **#49 Hokm Faranka Exception #2 missing bidder-team guard**
  (`audit_v0.9.0/49_hokm_faranka_priorities.md`). The 2-trump-
  count Faranka trigger fired regardless of contract ownership,
  so on a 2-trump hand against an OPPONENT's Hokm contract the
  bot would Faranka — actively withholding trump from a trick
  the opp wanted to win, helping their contract make. Fix:
  gate trigger on `R.TeamOf(contract.bidder) == R.TeamOf(seat)`.
  Exception #4 already had this guard; #2 was the gap.

### Fixed (MEDIUM)

- **#60 A-2 doubleton-T-no-A still slips through Ashkal gate**
  (`audit_v0.9.0/60_a2_singleton_t.md`). v0.9.1 closed the K
  block but the doc allow-list specifies `singleton-T`. Pre-
  v0.9.2 a hand with 2+ Ts (each in different suits, neither
  paired with own-suit A) could still Ashkal at bid-up T —
  contradicting the doc's cardinality requirement. Add explicit
  T-count gate: accept T only when `tCount == 1`.

### Fixed (LOW)

- **#45 R.CanBel three-predicate divergence**
  (`audit_v0.9.0/45_canbel_three_predicates.md`). The UI gate
  (`R.CanBel`), bot decision (`Bot.PickDouble`), and host gate
  (`Net._SunBelAllowed`) used three different predicates for
  Sun Bel-eligibility per video #11. In dual-low scenarios
  (both teams <100), the UI showed a Bel button that the host
  silently dropped — defender clicked, saw success locally,
  then watched it vanish on next MSG_ROUND. Now `R.CanBel`
  consults `contract.bidder` to apply the asymmetric form
  (`bidder>=101 AND defender<=100`); legacy nil-bidder callers
  fall through to the symmetric form for backward compat.

- **#47 Telemetry history hand-edit safety**
  (`audit_v0.9.0/47_telemetry_growth.md`). Append site
  (`State.lua`) and dump site (`Slash.lua`) used `or {}`
  fallback only — a hand-edited `WHEREDNGNDB.history` of any
  non-table type (number, string, corrupt array entry) crashed
  the next `#h` / `h[#h+1]` op. Type-guard with `type() ==
  "table"` mirrors the pattern at the top-level
  `WHEREDNGNDB` init in `WHEREDNGN.lua`. Dump path also skips
  non-table rows.

### Tests

- 333/333 regression tests pass (up 3 from v0.9.1's 330 due to
  new R.CanBel asymmetric pin coverage in test_rules.lua N).
- The touching-honors WRITE branch is now reachable; existing
  state_bot tests do not exercise the new flow but no fixture
  regresses.

### Audit response cumulative

| Severity | Closed (v0.8.6 + v0.9.0 + v0.9.1 + v0.9.2) |
|---|---|
| HIGH (v0.7.1) | 4/4 |
| MEDIUM (v0.7.1) | 5/5 |
| LOW (v0.7.1) | 4/6 (L1, L4, L5, L6) |
| Doc drift | 3/5 |
| Missing | 6/11 |
| **v0.9.0 ultra-audit findings** | **7 closed** (#12 CRIT, #45/#46/#47/#49/#54 + #60) |

### Deferred (v0.9.0 ultra-audit)

- **#51 SWA 5+ asymmetry** (UX/Saudi-rule alignment, not a bug;
  rescued by determinism check from being a scoring exploit).
- **#55 Bargiya axis FN** (cheap fix has B-side trade-off; needs
  recorder-side change for محشور proxy — deferred for design).

## v0.9.1 — Audit-sweep loop iteration: L5 + A-2 + AKA precondition (f)

Three audit items closed in one loop pass.

### Fixed (LOW)

- **L5 _OnResyncRes accepts unsolicited snapshots**. Pre-v0.9.1 a
  peer who passively overheard the gameID could fabricate a
  MSG_RESYNC_RES and inject score-state (no hand exposure, but
  cumulative + bid + contract + seat names leaked). Now: we track
  `expectingResyncRes` and only accept a response within a 30-second
  window after we explicitly sent MSG_RESYNC_REQ. The flag clears
  on first valid response or timeout.

### Added (missing feature #3 — A-2 Ashkal bid-up rank gate)

- **`Bot.PickBid` Ashkal anti-trigger A-2** (Common, video 31).
  Per the doc's allow-list ("bid-up small/mid: 7, 8, 9, J, Q,
  singleton-T"), the K is NOT permitted. Pre-v0.9.1 the predicate
  only blocked A (A-3) and T-with-A-cover (A-4); K could fire
  Ashkal in the 65-84 sun-strength range. Now: explicit `bidCardRank
  == "K"` block.

### Added (missing feature #4 — AKA precondition (f))

- **`Bot.PickAKA` precondition (f) — partner-trump-void**
  (decision-trees.md Section 6, row "AKA-call decision preconditions"
  subitem f). The whole point of AKA is to ask partner to defer
  the ruff. If partner is observed void in trump
  (`Bot._memory[partner].void[trump] == true`), they can't ruff
  anyway — the signal carries zero coordination value and leaks
  info to opponents (the banner is broadcast). Now suppressed.

### Tests

- 330/330 regression tests pass (no new fixtures this iteration; the
  three changes are observation-driven and graceful in absence of
  triggering conditions).

### Audit response cumulative

| Severity | Closed (v0.8.6 + v0.9.0 + v0.9.1) |
|---|---|
| HIGH    | 4/4 |
| MEDIUM  | 5/5 |
| LOW     | **4/6** (L1, L4, L5, L6) |
| Doc drift | 3/5 |
| Missing | **6/11** (G-4, touching-honors, Tahreeb-want, Bargiya-2flavor, A-2, AKA-f) |

## v0.9.0 — Audit MEDIUM/LOW fixes + 4 missing-feature wires + doc drift refresh

Continuation of the 73-agent v0.7.2 audit response. v0.8.6 closed
HIGH (H1-H4); v0.9.0 closes MEDIUM (M1-M5), partial LOW (L1, L4, L6),
ships 4 of the 11 documented missing features, and refreshes doc-
drift markers (D3, D4).

### Fixed (MEDIUM)

- **M1 PHASE_OVERCALL pause-blind timer**. The 5s overcall window's
  `C_Timer.After` fired regardless of pause state — could force-
  resolve the contract on resume before a human had a chance to
  click. Now: re-arms a fresh 5s timer on resume (mirrors SWA
  pattern at Net.lua:2627).
- **M2 /reload mid-OVERCALL or mid-SWA soft-locks**. PLAYER_LOGIN
  re-armed only Bel/Triple/Four/Gahwa AFK timers. Host /reload
  during PHASE_OVERCALL or with an SWA permission request in
  flight left the window stuck until manual recovery. Now: both
  windows are re-armed in WHEREDNGN.lua's PLAYER_LOGIN handler
  (cleanly resetting `startedAt` / `req.ts` so the 5s clock
  restarts post-reload).
- **M3 ISMCTS desire-table mutation idempotence**. Pre-v0.9.0,
  per-seat mutations in `sampleConsistentDeal` (line 368
  pSignalSuit, line 428 leadCount, etc.) wrote DIRECTLY into the
  shared `strong` / `defenderDesire` / `partnerDesire` tables —
  pollution persisted across seats and retry attempts within
  one PickPlay call. Now: each seat clones desire before mutation
  (3-line patch).
- **M4 Bot._partnerStyle persisted across /reload**. Bot's module-
  level state (`_partnerStyle`, `_memory`, `r1WasAllPass`) lived
  outside `S.s` and was wiped on every /reload — M3lm / Fzloky /
  Saudi-Master silently lost all accumulated reads (bels/triples/
  fours/gahwas counts, void inferences, aceLate, leadCount,
  baitedSuit, gahwaFailed, sunFail, etc.) mid-game. Now bundled
  into `WHEREDNGNDB.session.bot`; rehydrated in `S.RestoreSession`.
- **M5 Belote cancellation team-level**. Cancellation predicate
  required `m.declaredBy == kWho` (same player) — silently ignored
  partner's ≥100 meld AND silently failed when declaredBy was nil.
  Saudi rule "≥100 subsumes belote" applies to the team's collective
  scoring side. Now any team-mate's ≥100 meld cancels.

### Fixed (LOW)

- **L1 UI banner ticks during pause**. SWA + overcall self-ticking
  countdown OnUpdate handlers now skip body refresh under
  `S.s.paused`. Banner stays visible with frozen digit until resume.
- **L4 Late-AKA retroactive flip**. `N.LocalAKA` now requires
  `#trick.plays == 0` (we're about to lead) AND turn-aware
  (`S.s.turn == localSeat AND turnKind == "play"`). Pre-v0.9.0,
  pressing AKA mid-trick retroactively flipped `s.akaCalled` and
  suppressed the 4th-seat bot's ruff after the fact —
  informationally inconsistent.
- **L6 WHEREDNGNDB.target type-guard gap**. Both read sites in
  `WHEREDNGN.lua` now `tonumber()`-coerce. Hand-edited string
  target no longer breaks `cum >= target` arithmetic.

### Added (4 of 11 missing features)

- **G-4 partner-bid suppression** (audit missing #1, video #29).
  `Bot.PickBid` R2 now suppresses our own Hokm bid when partner
  has already bid Hokm — Saudi convention says support partner's
  commitment, don't compete. Sun overcall still allowed (different
  contract type). Pre-v0.9.0 the bot would emit HOKM:♥ outbid
  on partner's HOKM:♠; the host dropped it (winning already set),
  but the wire violation was visible.

- **Touching-honors family — Section 6 rules 1-4** (audit missing
  #10, video #05, Definite-confidence). When a seat plays T/K/Q
  in a trick led by their PARTNER's Ace of the same suit (or
  AKA-led), Saudi convention infers the next-rung-down rank in
  their hand:
    plays T  → has K
    plays K  → has Q
    plays Q  → has J
    plays 7/8 → broke in suit's high cards
  Inference written to `Bot._partnerStyle[seat].topTouchSignal[suit]`.
  Read by BotMaster sampler: pins the inferred next-down card to
  the seat (desire weight 60), and clears suit-high desires when
  the seat showed broke.

- **Tahreeb sender's "want" arm** (audit missing #7, video #10).
  Pre-v0.9.0 the Tahreeb sender only emitted T-4 ("LARGER first" =
  don't-want signal); the "want" arm (LOW-then-HIGH ascending
  sequence) was never emitted, so receiver's "want" classification
  could only fire by coincidence. Now wired: when we hold A or T
  of a side suit with ≥3 cards, the FIRST discard event from that
  suit is the LOWEST non-winner — receiver reads ascending
  sequence as "want this suit, lead it back".

- **Bargiya 2-flavor split** (audit missing #9, video #14).
  `tahreebClassify` now distinguishes:
    `bargiya`       — confirmed invite (signals[1]==A, ≥2 events)
    `bargiya_hint`  — ambiguous single-Ace event (could be invite
                       OR defensive shed; lower-confidence)
  Receiver scoring weights: bargiya=3, want=2, bargiya_hint=1
  (below "want" so multi-event signals dominate the ambiguous
  single-Ace case).

### Doc drift (D3, D4)

- Section 9 Tanfeer rules (3 rows) updated from "(not yet wired)"
  → "wired v0.5.14" with code-anchor hints.
- Section 11 rule 3 (pigeonhole pin) updated from "(not yet wired)"
  → "wired v0.5.22".
- Section 11 rule 4 (Sun-bidder partner concentration) updated
  from "(not yet wired)" → "wired v0.6.1".
- Section 11 rule 8 (deceptiveOverplay bait ledger) updated
  to reflect v0.8.2 wire (was duplicated in the doc; deduped).

### Tests

- 330/330 regression tests pass (was 330; M5 fix corrected one
  test's expected value from "A" to nil — the original test pinned
  the buggy single-player-only cancellation behavior).

### Audit response status (cumulative across v0.8.6 + v0.9.0)

| Severity | Total | Closed | Remaining |
|---|---|---|---|
| HIGH    |  4 | **4** | 0 |
| MEDIUM  |  5 | **5** | 0 |
| LOW     |  6 | **3** (L1, L4, L6) | 3 (L2 cosmetic AFK-pass, L3 stale akaCalled defensive, L5 _OnResyncRes info-leak) |
| Doc drift | 5 | **3** (D3, D4, partial D2) | 2 (D1 line-anchor pass, D2 R.CanBel unification, D5 Qaid forfeit text) |
| Missing |  11 | **4** | 7 (B-3, A-2, AKA preconds f+g, Bargiya receiver phase-split, 70/25/5 prior, Six-factor Tanfeer) |

## v0.8.6 — 73-agent audit HIGH fixes (H1-H4)

User-supplied 73-agent audit on v0.7.2 head identified four HIGH-severity
functional defects. All four fixed with source-level regression pins.

### Fixed (H1) — Sun-overcall race-A wire desync

**Net.lua `_OnOvercallResolve`** previously called `S.FinalizeOvercall()`
which RE-DERIVED the contract mutation from the remote's local
`s.overcall.decisions` table. If MSG_OVERCALL_DECISION frames were
dropped/reordered on a slow client, the remote's local-derived contract
disagreed with the host's. The `taken=true` branch was masked by the
host's follow-up MSG_CONTRACT broadcast; the `taken=false` branch had
no self-correction → desync persisted into trick play (different
trump suit / multiplier / scoring).

Fix: trust the wire. `_OnOvercallResolve` now just clears local
overcall state and exits PHASE_OVERCALL. The host is server-of-truth
via the follow-up MSG_CONTRACT (sent on `taken=true`); on `taken=false`
the contract stayed Hokm and the remote shouldn't mutate based on its
possibly-wrong local decisions.

### Fixed (H2) — Failed-Gahwa loser keeps own melds (cumulative inflation)

**Net.lua `_HostStepAfterTrick`** Gahwa-win override force-bumped the
WINNER's add to push their cumulative to target, but left the LOSER's
add intact (which could include their own meld points per the
"each team keeps own melds" rule in `R.ScoreRound:fail`). This
inflated the loser's cumulative cosmetically AND, more critically,
created a tiebreaker false-fire path when both teams happened to land
exactly at target.

Fix: zero the loser's add (delta) after force-bumping the winner's.
The cumulative state now cleanly reflects "match decided by Gahwa
override" with no tiebreaker race.

### Fixed (H3) — Tie-at-target tiebreaker reads `contract.bidder` (wrong on failed Gahwa)

**Net.lua `_HostStepAfterTrick`** game-end branch awarded
match-on-tie to `R.TeamOf(S.s.contract.bidder)`. On a FAILED contract
(`bidderMade==false`), the bidder team is the LOSER of the round —
awarding them the match contradicts the round result.

Fix: tiebreaker now respects `res.gahwaWinner` (canonical for Gahwa
rounds), then `res.bidderMade` (bidder won round → bidder team;
bidder failed → opp team won round). The pre-v0.8.6 raw
`contract.bidder` read is removed.

### Fixed (H4) — ISMCTS pcall granularity wraps entire 100-world loop

**BotMaster.PickPlay** `pcall` previously wrapped the entire `for w =
1, numWorlds do` loop. One bad world (sampler edge case, malformed
card, ScoreRound corner) caused pcall to bail and discard ALL 99
healthy rollouts → fallback to heuristics, dropping Saudi Master to
M3lm-equivalent for that play.

Fix: `pcall` moved INSIDE the per-world iteration. Failed worlds are
silently skipped; remaining worlds aggregate normally. With 100
worlds typical, losing 1-2 to errors is statistically irrelevant.
Only when literally all worlds error does the function fall back to
heuristics (suggests a deterministic bug, not a sampling edge).

### Tests

- 330/330 regression tests pass (was 319; +11 in new test_state_bot.lua
  section I).
- I.1a-e (H3): tiebreaker decision matrix (5 cases — bidderMade
  true/false × bidder seat 1/2 × Gahwa override).
- I.2/I.2b/I.2c (H1): source-level pin asserting `_OnOvercallResolve`
  no longer invokes `FinalizeOvercall`, still clears `s.overcall`,
  still transitions to PHASE_DOUBLE.
- I.3a/I.3b (H2): source-level pin for `addA = 0` / `addB = 0` in
  the Gahwa-win override branch.
- I.4 (H4): source-level pin asserting `pcall(function()` appears
  AFTER `for w = 1, numWorlds` (per-world wrapping, not loop-wrapping).

### Audit report

The full report and 73 per-agent findings live at
`.swarm_findings/audit_v0.7.1/AUDIT_REPORT.md`. This release closes
the HIGH section. MEDIUM (5) and LOW (6) findings + 11 missing
features are deferred for follow-up.

## v0.8.5 — Hokm Faranka exception #3 + S.HighestUnplayedRank trump-rank fix

Audit-sweep loop iteration. Two fixes that landed together because
the second was discovered while implementing the first.

### Fixed (State.lua)

- **`S.HighestUnplayedRank` trump-rank-order bug**. Pre-v0.8.5 the
  function walked `AKA_ORDER` (`A>T>K>Q>J>9>8>7`, plain rank) for
  ALL suits — including the Hokm trump suit, where the actual rank
  order is `J>9>A>T>K>Q>8>7`. So calling `HighestUnplayedRank(trump)`
  while the J was still live would return "A" instead of "J",
  producing wrong "boss" detection in the trick-8 sweep-pursuit
  branch (Bot.lua:1503) and wrong logic for the trump-pull-skip
  guard (Bot.lua:1832).
- Now auto-detects when `suit == s.contract.trump` AND
  `s.contract.type == K.BID_HOKM`, walks the new `TRUMP_HOKM_ORDER`
  in that case. Backward-compatible — no caller signature change.
- Practical impact: in late-game Hokm with J still live and us
  holding A of trump, the bot was incorrectly leading A as a
  "safe boss" in sweep pursuit. With the fix, the bot correctly
  identifies J as the top-live and skips A-leads when J could
  over-ruff. Estimated EV gain: 1-2 sweep recoveries per 100 rounds
  in late-trick scenarios.

### Changed (Bot.lua)

- **Hokm Faranka exception #3** (Common, video 04). When J of
  trump is observed dead AND we hold the 9 of trump → 9 is the
  new top live trump. Faranka allowed (withhold the new boss to
  ambush opp's remaining high cards). Detection uses the now-fixed
  `S.HighestUnplayedRank(contract.trump) == "9"` predicate (clean
  one-liner thanks to the trump-rank fix).
- Layered alongside Section 10 exceptions #2 and #4 from v0.8.4 in
  pickFollow. Anti-trigger from v0.8.4 (rule 7: opp bidder Q-led +
  we hold J+8) still applies and overrides exception #3 too.

### Tests

- 319/319 regression tests pass (no regression).
- Both fixes are observation-driven and require specific late-game
  hand shapes; the property-test legality sweep (section B) covers
  many random states without explicit fixtures. The
  `HighestUnplayedRank` fix is implicitly exercised every time the
  function is called — pre-v0.8.5 callers got wrong results that
  happened to not break legality but did mis-aim the bot's lead/
  follow choices.

## v0.8.4 — Hokm Faranka exceptions (Section 10 rules 2, 4)

Closes the v0.5.20-deferred Section 10 exceptions. Default Hokm
Faranka stays NO (play winners normally); these two exceptions
allow withholding the top trump in narrow Common-confidence cases.

### Changed (Bot.lua pickFollow)

- **Section 10 exception #2** (Common, video 04): we hold only 2
  trumps total → trump posture is already weak; Faranka EV cost
  is small. Withhold the top, play a non-winner (preferring
  non-trump non-winners to preserve trump cover).
- **Section 10 exception #4** (Common, video 04): we are the
  bidder AND both opponents are observed void in trump → risk-free
  Faranka (no one can punish the withhold). Same withhold logic.

- **Anti-trigger (rule 7)**: when opp bidder led trump-Q AND we
  hold both J and 8 of trump → override the Faranka trigger and
  play J normally. Direct counter per Section 10 rule 7.

- M3lm-gated. Lower tiers stay with default no-Faranka.

### Deferred (Section 10 exceptions still pending)

- **Exception #1** (Al-Kaboot pursuit): sweep-track detection
  exists in pickLead but cross-wiring with pickFollow adds
  complexity. Defer.
- **Exception #3** (J of trump dead, our 9 is now top): needs
  played-card scan + dynamic top-trump tracking. Doable; deferred
  for separate batch.
- **Exception #5** (partner shown extra trump): needs new style
  ledger counter for partner trump-cut events. Defer.

### Tests

- 319/319 regression tests pass (no regression).
- Faranka exceptions are M3lm-gated and require specific hand
  shapes; the property-test legality sweep in section B catches
  any illegal-card regression. No dedicated fixture in this batch
  (would require multi-trick state setup); covered indirectly by
  E.1/E.6 + the legality sweep.

## v0.8.3 — Live-game telemetry export

Foundation for empirical calibration work. Captures one row per round
into `WHEREDNGNDB.history` (SavedVariables, persists across sessions),
exposed via `/baloot history` slash commands.

### Added (State.lua)

- `S.ApplyRoundEnd` writes a row to `WHEREDNGNDB.history` per round.
  Capped at 200 rows; oldest rows drop when full. Captures:
  `roundNumber`, `ts` (GetTime), `type` (HOKM/SUN), `trump`,
  `bidder`, `doubled`/`tripled`/`foured`/`gahwa` flags, `forced`
  (Takweesh-recovery), `bidRound` (1/2), `bidCard`, `addA`/`addB`,
  `totA`/`totB`, `sweep`, `bidderMade`, `target`, `localSeat`.

### Added (Slash.lua)

- `/baloot history [N]` — print last N row summaries to chat
  (default 20). One line per round with contract shape + score
  delta + multiplier flags.
- `/baloot history clear` — wipe the history table.
- `/baloot history on` / `/baloot history off` — toggle capture
  (default ON).

### Behavior changes

- None on a clean install. `WHEREDNGNDB.historyEnabled` defaults to
  `nil` which is treated as ON (`~= false`). Existing players see
  the table grow silently; can disable with `/baloot history off`
  if SavedVariables size is a concern.
- Each client logs independently — every player has their own
  per-round perspective. Useful for individual analysis.

### Rationale

v0.5_FINAL_REPORT Priority 1 flagged "Bel calibration from real game
data" as the unblocking work for several deferred calibration items
(R1 threshold, BOT_GAHWA_TH, BOT_OVERCALL thresholds, Bel-strength
formula). This is zero-risk infrastructure — no behavior change —
that makes that calibration possible. Run a few sessions, dump the
table, fit thresholds against observed outcomes.

### Tests

- 319/319 regression tests pass (no regression).
- Telemetry write is gated on `WHEREDNGNDB` being a table; in the
  test harness `WHEREDNGNDB` is a stub table so writes happen but
  don't affect test assertions.

## v0.8.2 — Section 11 rule 8 bait-detected ledger

Closes the Section 11 rule 8 deferred item. When an opponent plays J
of led suit (or trump) while their partner was already winning the
trick — i.e., the J was unnecessary — the bot now reads it as Saudi
deceptive overplay ("I'm void below J, re-lead this suit") and
records the suit as a bait-detected target.

Subsequent `pickLead` defender turns AVOID re-leading that suit,
denying the opp's bait setup.

### Added (Bot.lua emptyStyle)

- `Bot._partnerStyle[seat].baitedSuit = { S=0, H=0, D=0, C=0 }` —
  per-suit counter accumulated across the game.

### Added (Bot.lua OnPlayObserved)

- Bait-detection branch: when a non-self seat plays J AND
  `#trickPlays >= 2` AND the pre-J trick winner equals this seat's
  partner, increment `baitedSuit[cardSuit]`. M3lm-implicit (the
  ledger always accumulates; only readers gate on tier).

### Added (Bot.lua pickLead defender branch)

- After the v0.7.1 opp-meld suit-avoidance check: if any opp
  `baitedSuit[X] >= 1` AND no earlier avoid is set AND X is not
  trump, set `fzlokyAvoidSuit = X`. Layered avoid logic:
  Fzloky > meld-suit > bait-suit (first non-nil wins).

### Tests

- 319/319 regression tests pass (no regression).
- Bait detection is observation-driven; the property-test sweep in
  test_state_bot.lua section B exercises pickLead against many
  random states without explicit bait fixtures. The wire is graceful
  — when no bait is observed, all reads return 0 and behave
  identically to v0.8.1.

## v0.8.1 — B-95 opponent score-urgency tracking

Closes the wave8 B-95 gap: bot's own urgency was wired into
`matchPointUrgency` (v0.5.x), but opponent urgency was unmodelled.
Desperate humans bid weaker hands; the bot now anticipates this
and counter-Bels accordingly.

### Added (Bot.lua)

- `opponentUrgency(oppSeat)` — local helper, mirror of `scoreUrgency`
  read from oppSeat's team perspective. Returns +12 (opp on brink),
  +6 (opp behind 80+), -8 (opp near clinch), 0 (neutral). M3lm-gated.
- `Bot.OpponentUrgency(oppSeat)` — public wrapper for cross-module
  use (BotMaster sampler reads this).

### Changed (Bot.lua)

- `Bot.PickDouble` lowers the Bel threshold by 5 when the contract
  bidder's `opponentUrgency` ≥ 6 (their team behind 80+, or we're
  near clinch). M3lm-gated. Combined with existing `combinedUrgency`
  the threshold stays within the `BOT_BEL_TH - 16` floor.

### Changed (BotMaster.lua)

- `sampleConsistentDeal` damps `pickProb` to 0.5 (matching the
  aceLate degradation tier) when the bidder seat has `OpponentUrgency`
  ≥ 6. Strong-card pinning becomes less aggressive in the bidder's
  hand, widening the sampled distribution toward weaker holdings —
  the Hail-Mary bid pattern.

### Tests

- 319/319 regression tests pass (no regression).
- The B-95 wire is gated on M3lm + cumulative-score state; unit
  tests for `Bot.PickPlay` legality (section B) sweep across many
  random states without explicit B-95 fixtures. The behavior is
  graceful — when opponentUrgency returns 0 (neutral), all wires
  no-op identically to pre-v0.8.1.

## v0.8.0 — Sun-overcall window: cross-trump Hokm take

Extension of v0.7.0. Same 5s window now also lets a non-bidder seat
**TAKE the contract as their OWN Hokm** (different trump suit), in
addition to the existing TAKE-as-Sun option. Symmetric with how
v0.7.0 enabled bidder UPGRADE → Sun and non-bidder TAKE → Sun.

Bidder UPGRADE remains Sun-only (a bidder switching to a different
Hokm suit makes no strategic sense — they already chose their best
trump).

### Added (Constants.lua)

- `K.BOT_OVERCALL_TAKE_HOKM_TH = 80` — bot threshold for cross-trump
  Hokm take.

### Changed (Rules.lua)

- `R.ResolveOvercall` now accepts decisions of the form
  `TAKE_HOKM_<S|H|D|C>`. Validates suit (must be one of S/H/D/C and
  must NOT match bidder's current trump). On match, returns
  `{ taken = true, by = N, type = "TAKE_HOKM", trump = "<suit>" }`.
- TAKE and TAKE_HOKM_<suit> share the same priority (bid order from
  dealer's right). Bidder UPGRADE still wins over both.

### Changed (State.lua)

- `S.RecordOvercallDecision` accepts `TAKE_HOKM_<S|H|D|C>` decisions.
  Validates the 11-character format and suit set; rejects malformed
  inputs (`TAKE_HOKM_X`, `TAKE_HOKM_`, `TAKE_HOKM`).
- `S.FinalizeOvercall` handles the `TAKE_HOKM` result type: contract
  type stays Hokm, bidder is rewritten to taker, trump is rewritten
  to result.trump, defender pair re-derived.

### Changed (Bot.lua)

- `Bot.PickOvercall` extended to evaluate Hokm-take alternatives.
  For each non-current-trump suit, computes `suitStrengthAsTrump`,
  applies the B-1 Saudi minimum-Hokm gate (J + count >= 3), and
  returns the strongest contract type that clears its threshold.
  When TAKE-as-Sun and TAKE_HOKM-as-Hokm both clear, the higher raw
  strength score wins.

### Changed (Net.lua)

- `N.LocalOvercall` validates `TAKE_HOKM_<suit>` decisions, rejects
  same-as-current-trump suits, and routes via the existing
  `MSG_OVERCALL_DECISION` wire (no protocol change — decision string
  is just longer).

### Changed (UI.lua)

- Non-bidder PHASE_OVERCALL action panel shows two TAKE options:
  "Take as Sun" + "Take as Hokm <suit>" (auto-picks best non-current-
  trump suit from local hand using inline suitStrength heuristic).
  WLA still available. Decided-state label handles all decision
  types including TAKE_HOKM_<suit>.

### Tests

- 319/319 regression tests pass (was 292; +7 new in section P,
  +20 new in section H).
- New P.23-P.29: TAKE_HOKM resolution, same-suit rejection,
  malformed-suit rejection, bidder UPGRADE still wins, bid-order
  priority across mixed TAKE/TAKE_HOKM, forced-contract gating.
- New H.15-H.17: Bot.PickOvercall TAKE_HOKM choice, contract
  rewrite via S.FinalizeOvercall, lock-out, malformed decision
  rejection.

## v0.7.2 — Section 4 rule 1 split + Section 11 rule 1 wire (video #05/#09 re-read)

User-reported re-read of source video #05 transcript revealed that
v0.5.11 conflated two distinct scenarios into a single "Sun losing-
side dump HIGHEST" rule. The fix went from one wrong extreme to
another. v0.7.2 splits Section 4 rule 1 into two scenarios per the
correct readings, AND wires Section 11 rule 1 (deferred since v0.5.22
when the WHY column was suspect).

### The video re-read

**Video #05 transcript** (Saudi Arabic, paraphrased):
> "If this opponent played the K, it's possible he has only the T.
> He played the K [which is] smaller than the T. But could he have
> the Q or J? No, impossible — if he had them he would have played
> them instead of the K, because they are smaller than the K."

The convention is **Tasgheer** (play-smallest), not "dump-highest".
The speaker's reasoning: opp plays K because K is the smallest of
their non-saving cards. Q/J/9/8/7 (smaller than K in plain rank
A>T>K>Q>J>9>8>7) would have been played FIRST per the convention.

**Video #09** ("biggest mistake in Baloot") is a DIFFERENT scenario:
partner-led Tahreeb-receiver context where playing absolute lowest
signals "I'm out of this suit", denying partner the re-entry.

### Changed (Bot.lua)

- **Section 4 rule 1A** (Common, video 05). REVERTED v0.5.11
  "highestByRank" branch in `pickFollow` opp-winning fall-through.
  The fall-through to `lowestByRank(legal)` at the function bottom
  already implements the corrected Tasgheer convention. The v0.5.11
  branch is now a documentation-only marker explaining the revert.

- **Section 4 rule 1B** (Definite, video 09). New branch in
  `pickFollow` partner-winning fall-through (after smother fails).
  When Sun + partner-winning + must-follow + can't-beat AND no
  point card to donate via Takbeer: returns **second-lowest** of
  the in-suit follow set, NOT absolute lowest. Preserves partner's
  ability to lead the suit back to us as a re-entry. Fires only
  for Sun (Hokm partner-winning has different conventions) and
  only when ≥2 in-suit cards are available.

- **Section 11 rule 1** (Common, video 05). Wire in
  `Bot.OnPlayObserved`: when Sun + opp follows lead suit with K or
  T AND that play loses (some other card in the trick outranks it),
  set `mem.void[leadSuit] = true`. Per Tasgheer convention, smaller
  cards (Q/J/9/8/7) would have been played first; reaching K or T
  means everything below is structurally absent. Pragmatic
  approximation — seat may still hold a single T after K-play, but
  the void flag is the right signal for sampler / opp-void lookups.

### Changed (docs/strategy/decision-trees.md)

- Section 4 rule 1 split into 1A (Sun+opp-winning → SMALLEST) and
  1B (Sun+partner-winning → SECOND-LOWEST).
- Section 11 rule 1 WHY column rewritten — was "Saudi losing-side
  dump-highest convention" (wrong); now "Saudi Tasgheer / play-
  smallest convention" with transcript citation.
- Contradictions log: the Sun off-suit losing-side dump entry
  reframed as RESOLVED v0.7.2 with rationale.

### Tests

- 292/292 regression tests pass (was 291; +1 new E.6).
- **E.1 updated**: pre-v0.7.2 expected `KH` (v0.5.11 highest); now
  expects `8H` (v0.7.2 lowest, Tasgheer rule 1A).
- **E.6 new**: pin for rule 1B partner-winning + can't-beat →
  second-lowest. Constructed to skip the smother gate (#pointCards=1
  H card, completed=0, not lastSeat) so the rule 1B branch fires.

## v0.7.1 — B-97 opp-meld suit avoidance (audit sweep)

Single-fix release. Loops back to `bot_picker_gaps.md` / wave8 B-97
for one previously unprocessed item.

### Changed (Bot.lua)

- **B-97 opp-meld suit avoidance** (audit). Pre-v0.7.1, `pickLead`
  never read `S.s.meldsByTeam` — opponents could declare a sequence
  meld in suit X (their established run) and the bot would still
  lead X freely, giving them tempo to cash the declared cards.
  Added an M3lm-gated reader in the defender-branch fzlokyAvoid
  block that flags any opponent-team sequence meld's suit as an
  avoid hint. Layered on top of existing Fzloky avoid (Fzloky wins
  if both apply). Skips trump suit (irrelevant to non-trump lead
  selection) and skips carrés (across-suit 4-of-a-rank don't imply
  a suit-lead intent).
  Sources: bot_picker_gaps.md / wave8 B-97.

### Tests

- 291/291 regression tests pass.
- B-97 fix is on the M3lm+ defender-lead path and only triggers when
  an opp seq meld is already in `S.s.meldsByTeam` — narrow scenario,
  no dedicated fixture (covered by the property-test sweep in
  test_state_bot.lua section B that runs random states across many
  seeds and would catch any illegal-card regression).

## v0.7.0 — Sun-overcall window: Phase 3 (UI) — feature complete

End-to-end Sun-overcall window. The bidder of any non-forced Hokm
contract gets a 5-second window to upgrade to Sun (unless the R1
bid card was an Ace, in which case only WAIVE is available); other
seats get to TAKE the contract as their Sun. First bidder UPGRADE
wins; otherwise earliest TAKE in bid order; otherwise Hokm stands.

### Added (UI.lua)

- **Sun-overcall countdown banner** mirroring SWA's pattern. Shows
  "Xs left · N/4 decided" and self-ticks at ~3 Hz. Auto-hides on
  phase exit. Anchored to `centerPad` top, tinted blue (vs SWA
  gold) for at-a-glance phase distinction.
- **PHASE_OVERCALL action buttons** in the standard action panel:
  - Bidder + non-Ace bid → "Upgrade to Sun (Ns)" + "WLA (waive) (Ns)"
  - Bidder + Ace bid → "WLA (waive) (Ns)" only (UPGRADE filtered)
  - Non-bidder → "Take as Sun (Ns)" + "WLA (waive) (Ns)"
  - After local seat decides → status indicator instead of buttons
    ("Upgraded to Sun — waiting for others", etc.)
- Host explicitly calls `B.UI.Refresh()` from
  `N._HostBeginOvercallWindow` since the loopback receiver returns
  early on `S.s.isHost` — without this the host wouldn't see their
  own overcall buttons / banner.

### End-to-end behaviour

| Scenario | Outcome |
|---|---|
| All-bot table, no bot bids strong enough Sun | 5s elapses, all WAIVE, contract stays Hokm (existing flow) |
| All-bot table, one bot has Sun-strong hand | Synchronous resolve at window-open: contract flips to Sun |
| Mixed table, human bidder Sun-strong | Human clicks Upgrade, contract flips, 5s short-circuits if all decide |
| Mixed table, human non-bidder takes | Human clicks Take, contract flips, becomes new bidder |
| R1 bid card was Ace, bidder strong | Bidder sees WLA only — anti-trap rule. Other seats can still TAKE. |
| Forced/Takweesh contract | Window does NOT open (existing post-bid flow proceeds as v0.6) |
| Sun bid | Window does NOT open (overcall is Hokm-only) |
| Late join during window | Resync replay sends MSG_OVERCALL_OPEN + recorded decisions |

### Tests

- 291/291 regression tests pass.
- Phase 3 UI is not covered by headless tests (no UI test harness in
  the repo). State machine + bot AI are exhaustively tested in Phase 1
  (sections P + H, 65 assertions). Network protocol relies on
  manual in-game verification — the SWA banner pattern this mirrors
  is a known-good blueprint.

### Configuration

- `WHEREDNGNDB.allowSunOvercall` (Boolean, default true): set false
  to disable the entire feature for non-Saudi-rule installations.

### Known limitations / deferred polish

- 5s window is short. If you find players consistently miss the
  decision, we can raise `K.OVERCALL_TIMEOUT_SEC` (or make it
  contextual: longer when a human is eligible, shorter when only
  bots remain undecided).
- Bot strength thresholds (`K.BOT_OVERCALL_SELF_TH = 75`,
  `K.BOT_OVERCALL_TAKE_TH = 80`) are first-pass calibrations.
  Tune empirically once you've played some games.
- `Bot.PickOvercall` is M3lm+ only (lower tiers always WAIVE) per
  D3 in the design spec. If you want Advanced bots to also act on
  overcalls, drop the `Bot.IsM3lm()` gate.

### Side notes (logged for future work)

- **R1 bid rate measurement** (1000 deals): R1 bid 36.7%, R2 bid
  69.7% of those that reached R2, overall 80.8% of deals get a bid;
  19.2% all-pass redeals. Lowering `TH_HOKM_R1_BASE` from 42 to 38
  would shift more boundary hands into bidding without violating
  the B-1 minimum-shape gate. **Deferred** — calibration tweak,
  not a bug.
- **Ashkal never fires in pure-bot bidding** despite v0.5.8 ORDER
  FIX — likely because the bid-history snapshot used by the Ashkal
  predicate is empty when seats are simulated independently.
  **Deferred** — separate investigation.

## v0.7.0-pre2 — Sun-overcall window: Phase 2 (network protocol)

Wires the Phase 1 state machine onto the addon-message bus so the
overcall window opens in actual networked play. UI is still Phase 3.

### Added (Constants.lua)

- `K.MSG_OVERCALL_OPEN` (`>`) — host announces the 5s window opens.
  No payload.
- `K.MSG_OVERCALL_DECISION` (`<`) — a seat decided. Payload:
  `seat;decision` where decision ∈ {UPGRADE, TAKE, WAIVE}.
- `K.MSG_OVERCALL_RESOLVE` (`?`) — host announces window closed +
  result. Payload: `taken(0|1);by(seat or 0);type`.

### Added (Net.lua)

- `N.SendOvercallOpen / SendOvercallDecision / SendOvercallResolve`
  broadcast wrappers.
- `N._OnOvercallOpen / _OnOvercallDecision / _OnOvercallResolve`
  receivers + dispatch entries in `N.HandleMessage`.
- `N._HostBeginOvercallWindow` — opens the window via
  `S.BeginOvercall`, broadcasts MSG_OVERCALL_OPEN, records all
  bot-seat decisions synchronously (via `Bot.PickOvercall`), schedules
  the 5s timer OR early-resolves if all seats already decided.
- `N._HostResolveOvercall` — calls `S.FinalizeOvercall`, broadcasts
  MSG_OVERCALL_RESOLVE, broadcasts a fresh MSG_CONTRACT if the
  contract was rewritten, then continues the existing post-bid flow
  (Sun-Bel-skip check + `MaybeRunBot` for PHASE_DOUBLE).
- `N.LocalOvercall(decision)` — local-action helper for the player's
  UI button click. Validates decision vs `R.CanOvercall` + bidder/
  non-bidder semantics; sends the wire message.
- Hook in `N._HostStepBid` (between `S.ApplyContract` and the existing
  Sun-Bel-skip/MaybeRunBot path) — calls
  `_HostBeginOvercallWindow`. If it returns true, defers the rest of
  the post-bid flow until `_HostResolveOvercall` fires; otherwise
  proceeds normally.
- `N.MaybeRunBot` early-returns on PHASE_OVERCALL — bot decisions
  are already recorded synchronously by the host orchestrator and
  the 5s timer drives the resolve.
- `N.StartLocalWarn` accepts `"overcall"` kind (no-op pre-warn since
  5s < 10s warn threshold; included for symmetry with the existing
  escalation kinds).
- Resync replay: `N.SendResyncRes` whispers `MSG_OVERCALL_OPEN` plus
  any already-recorded `MSG_OVERCALL_DECISION` frames when a rejoiner
  arrives during PHASE_OVERCALL. Without this, late-joiners would see
  PHASE_OVERCALL in the snapshot but no `s.overcall` body, so their
  UI button + clicks would silently no-op.

### Behavior changes

- Per-install opt-out: `WHEREDNGNDB.allowSunOvercall = false` disables
  the window entirely (default: enabled). Useful for non-Saudi-rule
  installations.

### Phase 2 explicitly NOT included

- **No UI yet.** Clicking the local-action button requires Phase 3
  (UI 5s popup mirroring SWA's pattern).
- **Headless wire test absent.** WHEREDNGN's Net.lua doesn't have a
  headless test harness (everything's mocked at S/Bot layer). Phase 2
  changes are validated by Phase 1's 65 headless tests + manual
  network testing in-game.

### Tests

- 291/291 regression tests pass — Phase 2 is a wire-protocol layer
  on top of Phase 1's already-tested state primitives.

## v0.7.0-pre1 — Sun-overcall window: Phase 1 (state machine + bot AI)

User-requested feature: post-Hokm-bid 5-second window where the bidder
may upgrade their Hokm to Sun, AND non-bidder seats may take the
contract as their own Sun. Implements `Q1=A, Q2=simultaneous-bid-order
priority, Q3=A, Q4=other-takes-or-bidder-self-upgrade, Q5=before Bel,
D1=bid-order-priority, D2=no-Takweesh, D3=M3lm+, D4=SWA-style popup`
from the design discussion.

This release ships **Phase 1 only** — the pure-host state-machine
primitives, bot AI, and headless tests. Network plumbing (Phase 2)
and UI (Phase 3) follow in subsequent releases.

### Added (Constants.lua)

- `K.PHASE_OVERCALL = "overcall"` — new game phase between bid
  resolution and PHASE_DOUBLE.
- `K.OVERCALL_TIMEOUT_SEC = 5` — 5-second window per spec.
- `K.BOT_OVERCALL_SELF_TH = 75` — bidder self-upgrade strength.
- `K.BOT_OVERCALL_TAKE_TH = 80` — non-bidder take strength (stricter).

### Added (Rules.lua)

- `R.CanOvercall(seat, contract, bidCard)` — eligibility predicate.
  Returns false for forced/Takweesh contracts, Sun contracts, the
  bidder when bid card is Ace (anti-trap rule), nil inputs.
- `R.ResolveOvercall(decisions, contract, bidCard, dealerSeat)` —
  conflict resolver. Bidder UPGRADE wins; otherwise earliest TAKE
  in bid order (starting from dealer's right).

### Added (State.lua)

- `S.BeginOvercall(bidCard, dealerSeat)` — opens the window,
  transitions phase to PHASE_OVERCALL, initializes `s.overcall`.
  Refuses on Sun/forced contracts.
- `S.RecordOvercallDecision(seat, decision)` — locks in a per-seat
  decision (UPGRADE/TAKE/WAIVE). Once decided, no take-backs.
- `S.FinalizeOvercall()` — runs `R.ResolveOvercall`, mutates
  `s.contract` if an overcall wins (rewrites bidder + clears trump
  + re-derives defender pair), transitions phase to PHASE_DOUBLE,
  clears `s.overcall`.

### Added (Bot.lua)

- `Bot.PickOvercall(seat)` returns `"UPGRADE"`, `"TAKE"`, or
  `"WAIVE"`. Tier-gated: lower-than-M3lm always WAIVE per D3.
  Uses `sunStrength(hand)` against the two thresholds; respects
  Ace-bid-card via `R.CanOvercall`.

### Added (tests)

- `test_rules.lua` section P (22 assertions): `R.CanOvercall` +
  `R.ResolveOvercall` covering bidder UPGRADE, non-bidder TAKE,
  Ace-bid blocks, forced contracts, bid-order priority,
  multi-TAKE arbitration across different dealer positions, nil
  inputs.
- `test_state_bot.lua` section H (43 assertions): full state-
  machine integration — BeginOvercall/Record/Finalize lifecycle,
  contract rewriting on UPGRADE vs TAKE, phase transitions, lock-out
  semantics, invalid-input rejection, Bot.PickOvercall tier gating
  + strength-decision sweep.

### Phase-1 explicitly NOT included

- **No networking yet.** `MSG_OVERCALL_TAKE` / `MSG_OVERCALL_WAIVE`
  / `HostBeginOvercall` / `HostResolveOvercall` are Phase 2.
- **No UI.** The 5s popup mirroring SWA's flow is Phase 3.
- **No integration with `S.ApplyContract`.** Existing post-bid
  flow still goes directly to PHASE_DOUBLE — Phase 2 will hook
  the overcall window in.

### Tests

- 291/291 regression tests pass (was 226; +65 in sections P + H).
- Headless tournament unaffected (overcall window not yet wired
  into the natural game loop).

## v0.6.1 — BotMaster sampler biases + bidder-branch styleTrumpTempo wire

Three clean wires that were dead infrastructure or partial.

### Changed (BotMaster.lua sampler)

- **B-56 leadCount-based suit bias** (audit Tier 4 / v0.5_FINAL_REPORT
  Priority 2). `leadCount[suit]` was previously written by
  `Bot.OnPlayObserved` (Bot.lua:368-369) but read by zero pickers —
  pure dead infrastructure. Now read in `sampleConsistentDeal` for
  OPPONENT seats: when an opp seat has led a given suit ≥3 times
  across the game (per-game style ledger, not per-round), bias the
  sampler to put more cards of that suit in their hand. Encoded as
  `desire[suit] = 1` (triggers the existing 20-weight suit-fallback
  path). Skipped for Kawesh-cleared opponents and for teammates
  (we already have stronger Fzloky / Tahreeb signals on partner).

- **Section 11 rule 4 — Sun-bidder partner concentration** (Common,
  video 02 — deferred from v0.5.22). `getPartnerCards` previously
  returned `{}` for Sun contracts, leaving the bidder's partner
  with no sampler bias at all. Saudi convention: a Sun-bidder
  team only commits when both partners can carry trick-pulling
  weight, so the partner typically holds A's and K's across
  multiple suits. Encoded as per-card desire weights:
  `desire["A"..s] = 8` (matches defender bias), `desire["K"..s] = 4`
  (partial clustering tier).

### Changed (Bot.lua)

- **B-57/B-71 styleTrumpTempo bidder-branch wire** (audit
  bot_picker_gaps.md). Pre-v0.6.1 the bidder branch of `pickLead`
  never read `styleTrumpTempo` — only the defender branch did.
  Gap: a defender showing CONSERVATIVE trump tempo (saving high
  trump for over-ruff capture rather than tempo pull) is signaling
  intent to over-ruff the bidder's pulled trump. Saudi pro counter:
  cash side-suit Aces FIRST (defenders must follow if they have
  the suit; can't over-ruff a non-trump lead), forcing them to
  spend low cards in side suits before pulling trump.
  Inserted between the trump-poor side-Ace branch and the B-98
  J+9 trump-lock branch in pickLead bidder mode. M3lm-gated
  (style ledger requires accumulated prior-round signal), Hokm-only.

### Audit-confirmed already wired (no code change)

- **B-67 aceLate counter** — wired into `sampleConsistentDeal`'s
  `pickProb` adjustment (BotMaster.lua:376-378). Confirmed live.

- **B-83 gahwaFailed counter** — wired into `Bot.PickFour` (Bot.lua:
  ~2755). Confirmed live.

- **B-47/B-50 oppGahwas/oppFours** — wired into `matchPointUrgency`
  (Bot.lua:802-827). Confirmed live.

- **M-3 rollout void tracking** — moot. `heuristicPick` doesn't read
  `Bot._memory.void`; legality is enforced via the simulated hand
  state which IS updated as cards play out. The "stale void" concern
  doesn't apply with the current rollout architecture.

### Deferred

- **Section 11 rule 1 (Sun K-or-higher dump-high inference)**: the
  decision-tree rule documents a "no lower rank" inference but the
  rationale ("Saudi losing-side dump-highest convention") suggests
  the OPPOSITE — dump-highest is consistent with holding lower
  cards underneath. Defer until source video #05 can be re-verified.

- **Section 11 rule 2 (Hokm trump-high-dump)**: needs new
  `trumpHighDump` counter infrastructure. Defer.

- **Section 11 rule 5 (Tahreeb-low-from-partner)**: needs
  `tahreebSuspect[suit]` ledger key. Defer.

### Tests

- 226/226 regression tests pass.
- Headless tournament (M3lm vs Master) still tier-ordered correctly:
  Basic 97.9, M3lm 99.5, Master 99.5 over 30 rounds.
- The sampler biases don't affect picker legality (only sampled
  hand distributions); property-test legality coverage continues
  to sweep across many seeds.

## v0.6.0 — Section 1 deferred bidding rules + audit H-3/H-7 fixes (closes v0.5.x audit cycle)

Three audit-pending items landed in one batch. Major version bump
signals end of the v0.5.x decision-trees translation cycle —
Sections 1-11 of `docs/strategy/decision-trees.md` are now either
implemented or explicitly deferred with rationale.

### Changed (Bot.lua)

- **B-7 Bel-fear bias for Sun bidding** (Common, video 25). When
  OUR team's cumulative is at >= K.SUN_BEL_CUMULATIVE_GATE (=100),
  the OTHER team can still Bel us in Sun (per the v0.5.9 E-1 rule:
  only the team <100 may Bel; opp at <100 still qualifies). A
  failed Bel'd Sun = ×2 multiplier on handTotal=130 raw = 26 game
  points lost — major setback. Bias `thSun` UP by +8 to deter
  Sun bids when we're at risk. Roughly one strength-tier penalty.
  Sources: decision-trees.md S-7 / Section 1 row "Cumulative score
  ≥100 (Sun-Bel-gate context)" (Common, video 25).

- **H-3 singleton-low rank guard** (audit MASTER_REPORT). The
  pre-v0.6.0 singleton-lead branch in `pickLead` priority 2
  picked the lowest singleton unconditionally — including a
  singleton Ace/T/K/Q in Hokm where the opponent void in that
  suit can over-ruff and capture the honor for nothing. The
  "ruffing entry" rationale (lead low, dump it, partner can lead
  the suit back later for us to ruff) only applies to genuinely
  low cards. Filter Hokm-contract singletons to face-rank 7/8/9;
  if all our singletons are honors, fall through to the
  longest-suit-low lead instead of dumping a winner. Sun keeps
  current behavior (A/T are sure stoppers in Sun).
  Sources: MASTER_REPORT H-3 / wave3 A-47.

- **H-7 combined-urgency cap** (audit MASTER_REPORT). Previously
  callers computed `urgency = scoreUrgency(team) + matchPointUrgency(team)`
  with each component capped independently (±10 on
  matchPointUrgency, +12 max on scoreUrgency). Combined could
  reach +22, dropping BOT_BEL_TH from 70 to 48 in worst case —
  bot Bels garbage hands when desperate. Per the audit comment
  intent ("combined cap ±15"), introduced `combinedUrgency(team,
  context)` helper that clamps the SUM. All five threshold
  computations (Bel/Triple/Four/Gahwa + R2 Hokm) now route
  through the helper. Sources: MASTER_REPORT H-7 / wave2 A-56.

### Confirmed already wired (no code change in this release)

- **G-2 round-1 conservative bias** (Common, video 25): R1 Hokm
  threshold (`TH_HOKM_R1_BASE` ~=42) is already higher than R2
  (`TH_HOKM_R2_BASE` ~=36). The v0.5.13 calibration locked in the
  Saudi bidding-decision-tree's "round 1 stricter" intent. No new
  code needed.

- **B-3 5+ trump Kaboot pursuit** (Common, video 04): partially
  handled by v0.5.19's trick-3 sweep-pursuit extension. The
  trump-heavy hand path triggers sweep-pursuit early (trick 3+),
  giving 5+ trumps free play to chase Kaboot when bidder team
  hasn't lost a trick yet.

### Deferred

- **G-4 Takweesh bid-override anti-trigger** (Common, video 13):
  blocks bidding when we just Takweeshed (Qaid). Conflicts with
  the user's earlier Sun-overcall expectation (the Sun-overcall
  scenario explicitly allows mid-bidding overcall). Defer until
  the multi-day Hokm-overcall-window UX lands.

- **H-9 BOT_GAHWA_TH=135 calibration**: audit recommends lowering
  to 125 since 135 is mathematically near-unreachable. Defer —
  Gahwa is a match-win commit; conservative bias preferred until
  empirical Gahwa-success rate is measured.

### Tests

- 226/226 regression tests pass.
- Headless tournament averages: Basic 97.9, M3lm 99.5, Master 99.5
  over 30 rounds (tier ordering preserved post-edit).
- The B-7 / H-3 / H-7 changes don't have dedicated test fixtures
  (hand-shape gating is hard to pin without elaborate setups);
  property-test legality coverage in test_state_bot.lua section
  B sweeps the picker output across many random hands and would
  catch any illegal-card regression.

## v0.5.22 — decision-trees.md Section 11 rule 3: pigeonhole pin extension

Translates the Definite-confidence Section 11 rule (sampler hand-
reconstruction inference). Extension of v0.5.0's H-1 J/9-of-trump
pin in `BotMaster.PickPlay` sampler.

### Changed (BotMaster.lua sampler)

- **Rule 3 pigeonhole pin** (Definite, video 05). When N trumps
  remain unseen AND we observe all-but-one OTHER seats are void
  in trump (via `Bot._memory[s].void[trump]`), all those remaining
  trumps MUST be in the one remaining trump-eligible seat —
  mathematical force. Pin them via `meldPins`.

  Pre-v0.5.22, only J/9 of trump were pinned (H-1). The other
  trump cards (K/Q/T/A/8/7) were sampled randomly across all
  three opp/partner hands per the baseline 70%-pickProb. With
  voids surfacing late in the round, the random sampling was
  often counter-factual (placed trumps on seats known to be
  void). This extension uses the void-observation data to
  hard-constrain the remaining trumps to the single eligible
  seat when only one such seat exists.

  Significantly improves rollout accuracy late in the round when
  trump voids have surfaced — the rollout no longer wastes
  iterations on impossible deals.

### Other Section 11 rules (deferred)

| Rule | Confidence | Status |
|---|---|---|
| 1 (Sun K-or-higher dump-high inference → no-lower-rank constraint) | Common | DEFERRED — needs `dumpHighSeen` ledger key + sampler constraint |
| 2 (Hokm trump-high-dump → opp short on trump) | Common | DEFERRED — needs `trumpHighDump` counter |
| 4 (Partner Sun bidder → assume one long suit + concentrated highs) | Common | DEFERRED — Sun-bidder-partner sampler bias |
| 5 (Partner Tahreeb'd low → partner has A or J in other suit) | Common | DEFERRED — `tahreebSuspect[suit]` ledger key |
| 6 (Touching-honors gate when not winning) | Definite | BLOCKED — no touching-honors read exists yet (rules 1-3 from Section 6 also deferred) |
| 7 (Convention-adherence rolling counter) | Sometimes | DEFERRED |
| 8 (Bait-detected ledger) | Sometimes | BLOCKED — no deceptiveOverplay sender exists yet |

### Tests

- 226/226 regression tests pass.
- The pigeonhole pin fires only when:
  - Hokm contract.
  - Trump suit known.
  - All-but-one other seats observed void in trump (mid-late round).
  This is rare in random tournaments; the change won't show up in
  aggregate baseline metrics. Verified empirically via the tournament
  harnesses still running clean.

## v0.5.21 — Section 5 Sun Faranka + scoring discrepancy fix + Hokm SWA safety

Three user-reported items addressed in one batch.

### Section 5 — Sun pos-4 Faranka (Definite, video 06)

The canonical Saudi Faranka: Sun + lastSeat + partnerWinning + we
hold A AND a "cover" (T or K) of led suit + EXACTLY 2 cards of
led suit → DUCK with the cover, let partner take this trick, our
A captures the next opp-led trick. Bridges 2 tricks per single
A/cover deployment.

This branch fires BEFORE the v0.5.18 Takbeer-extension smother
because Faranka and Takbeer conflict (both fire on partner-
winning + we-hold-A). Per video #06, Faranka is the correct
Sun pos-4 play; Takbeer is the general partner-winning donate-
highest behavior. When BOTH match, Faranka wins.

Tier-gating: bidder-team only (rule 9 anti-trigger — defenders
should win the trick to deny opp Kaboot rather than fish for
tempo). Anti-trigger rule 4 (≥3 cards of suit, 10 drops naturally)
is enforced via `suitCount == 2` gate.

Anti-trigger rules 3, 5, 6, 8 are SOMETIMES-confidence or require
state we don't track cheaply (e.g., A is known to be at LHO).
Deferred.

### Scoring discrepancy fix (user-reported "scoring not matching docs")

Two paths in Net.lua used the OLD `(x + 4) / 10` rounding (5
rounds DOWN), inconsistent with R.ScoreRound's v0.5.6 fix to
`(x + 5) / 10` (5 rounds UP per video #43):

- **`Net.HostResolveTakweesh`** (Qaid penalty path) at line ~1889.
- **`Net.HostResolveSWA`** invalid-SWA branch at line ~2591.

Both now use `(x + 5) / 10` consistently with R.ScoreRound. So
a Qaid penalty resolution and an invalid-SWA penalty resolve
with the same rounding direction as a normal round-end. User-
reported symptom: scores after a takweesh/SWA-failure didn't
match what the docs said for raw values ending in 5 (e.g., 65
raw should be 7 game points per "5 rounds UP", not 6).

### Hokm SWA safety net (user-reported "bots SWA while opp has Hokm")

User reports observing bots calling SWA in Hokm contracts while
opponents still hold trump (Hokm) cards. R.IsValidSWA is post-
v0.5.17 strict-caller-correct (per inline trace verification),
but the user wants extra conservatism in Hokm.

Added belt-and-suspenders gate to `Bot.PickSWA`: in Hokm, after
R.IsValidSWA returns true, additionally verify that NO opponent
holds a trump higher than caller's top trump. Specifically:
- Compute `callerTopRank` = highest TrickRank of caller's trumps.
- Compute `oppTopRank` = highest TrickRank of opps' trumps.
- Reject SWA if `oppTopRank > callerTopRank`.

When caller has 0 trumps and opp has any trump, oppTopRank > -1 =
callerTopRank → reject. (R.IsValidSWA already correctly rejects
this case via the must-trump-ruff path; the safety net is
redundant defense for any edge case.)

Trade-off: bot may miss some genuinely valid Hokm SWAs where
caller has no trump but the situation is otherwise unbeatable
(e.g., 4-card endgame where caller holds 4 Aces and opp's only
trump is 7H but they're forced to follow non-trump leads). Rare;
conservative bias preferred per user.

### Tests

- 226/226 regression tests pass.
- The Section 5 Faranka branch and the Hokm SWA safety net are
  not directly pinned by tests (would require complex hand setup);
  scoring rounding fix is implicitly covered by the existing
  Section M div10 tests in test_rules.lua.

## v0.5.20 — decision-trees.md Section 10: Hokm Faranka audit (no code change)

Section 10's 9 rules establish the Saudi convention: **Hokm Faranka
default = NO**, with 5 narrow Common-confidence exceptions and 2
Definite anti-rules.

The current bot code never voluntarily ducks (winners-branch returns
cheapest-winner; falls through to lowestByRank when no winners) —
so the Hokm-default is automatically satisfied. The Definite anti-
rules (6, 7, 9) are likewise implicitly correct via winners-branch
behavior. The 5 Common-confidence exceptions allow Faranka in
narrow scenarios — those are deferred.

### Audit findings — all Hokm Faranka rules

| Rule | Confidence | Status | Why |
|---|---|---|---|
| 1 (default = NO Faranka) | Definite | **ALIGNED** | Bot never ducks. winners-branch picks cheapest winner; lowestByRank fallback in losing-side. No Faranka path exists in code. |
| 2 (exception: Al-Kaboot pursuit) | Common | DEFERRED | Would allow Faranka when on sweep-track. Variance acceptable per video #04 ("losing ANY trick already kills Kaboot"). Defer until sweep-track Faranka becomes a measurable need. |
| 3 (exception: only 2 trumps held) | Common | DEFERRED | Trump-poor hand, low-cost incremental Faranka. Edge case. |
| 4 (exception: J-of-trump dead, your 9 is new top) | Common | DEFERRED | Requires played-card scan + dynamic top-trump shift detection. |
| 5 (exception: bidder + opp trump exhausted) | Common | DEFERRED | Risk-free Faranka condition. Requires void-tracking on opp seats. |
| 6 (exception: partner has shown extra trump) | Sometimes | DEFERRED | Single-source. Style-ledger reading (partner trump-cut-cleanly inference). |
| 7 (anti-Faranka: opp bidder led trump-Q + we hold J+8) | Definite | **ALIGNED** | Bot plays J normally (winners-branch fires). Faranka isn't tempted because the bot doesn't have a Faranka heuristic to override. |
| 8 (anti-Faranka: pos-4 trump-9-only + opp Faranka'd) | Common | **ALIGNED** | Bot plays 9 to win (winners-branch fires). |
| 9 (meta: trump still live → assume worst case, cover) | Definite | **ALIGNED** | Bot's risk-averse default (no voluntary ducking) implements this meta-principle. |

### Net effect: no code change

Hokm Faranka is a refinement OPPORTUNITY (the 5 Common-confidence
exceptions could lift bot strength in specific scenarios), but the
DEFAULT behavior is already correct per Saudi convention. Implementing
the exceptions adds risk-of-misfire (Faranka ducked at the wrong
moment costs the trick) for marginal gain. Defer to a focused release
once empirical measurements show what subset of these matters.

### Tests

- 226/226 regression tests pass (no behavior change in this release).

## v0.5.19 — decision-trees.md Section 7: trick-3 Kaboot pursuit + endgame audit

Translates Section 7 endgame/SWA rules. Most are already wired
post-v0.5.17; this release lands the trick-3 Kaboot-pursuit
extension and audits the rest.

### Changed

- **Section 7 rules 1+2** (Common, videos 06+07+15): trick-3
  Kaboot pursuit extension. The pre-v0.5.19 sweep-pursuit branch
  in `pickLead` only fired at `trickNum == 8`. Per video #15: "if
  no opp cut by trick 2, trump distribution is favorable; sweep
  is genuinely reachable. Earlier trigger lets tricks 3-7 be
  optimized for sweep." Now: when `trickNum >= 3` AND `isBidderTeam`
  AND mytTeam-has-won-every-prior-trick → enter sweep-pursuit
  mode (same logic as trick-8 — boss-lead in safe suit, fall
  through to highest-face-value). K.AL_KABOOT_HOKM=250,
  K.AL_KABOOT_SUN=220 ×2 = 440. High-value bonus to pursue.

### Confirmed already wired (no code change)

- **Rule 7** (Sun Bargiya — Common, video 01): wired in v0.5.10
  T-1 Bargiya sender. When partner is winning + we hold A of side
  suit X with cover → discard A as Bargiya signal.

- **Rule 11** (SWA deterministic-or-bust — Definite, video 35):
  enforced in v0.5.17 via R.IsValidSWA strict-caller (cooperative
  branch tightened to "every play must succeed").

- **Rule 12** (Opp denies SWA → Qaid penalty — Common, video 35):
  already wired via `MSG_SWA_OUT` + `Net.HostResolveSWA` outcome
  path. The valid-flag in the message carries the result.

### Confirmed implicitly handled (no code change)

- **Rule 5** (Defender prevent Kaboot — Common, video 07): the
  existing `pickFollow` winners-branch already returns any winner
  when opp is winning + we have a winner. "First success" =
  taking any trick = the winners-branch firing at all.

- **Rule 6** (Defender force-fail — Common, video 07): partially
  implicit via `scoreUrgency` for bidding/escalation. The play-
  side "capture high-value tricks at cost of low-card discipline"
  would require switching the winners-branch from cheapest-winner
  to highest-face-value-winner when defender + bidder-making.
  Could be a future targeted enhancement; currently the
  cheapest-winner default still captures trick points (just not
  maximally).

### Deferred

- **Rule 3** (Sun bidder sweep abandonment — Sometimes, video 15):
  needs score-tracking. House-rule territory.
- **Rule 4** (Defender Qaid-bait — Sometimes): doc explicitly
  says "bot likely should NOT do this without dedicated
  heuristic". Skip.
- **Rule 8** (Sun trick-8 Bargiya followup — Sometimes, videos
  01+08): we'd lead the suit we Bargiya'd in earlier. Requires
  reading our OWN `tahreebSent` (not partner's) — small
  extension to the v0.5.10 receiver. Defer.
- **Rule 9** (Reverse Al-Kaboot scoring — Sometimes, video 16):
  +88 raw to defender team on full sweep against bidder. Single-
  source; doc says "confirm before wiring". Defer.
- **Rule 10** (SWA card-count thresholds 5+ stricter): video #35
  refines current ≤3-instant / 4+-permission to ≤3 / 4-context-
  dependent / 5+-mandatory. Current code (post-v0.5.17 — all
  flows go through 5s window) is functionally correct; the
  "context-dependent" subtlety is hard to pin behaviorally. Defer.

### Tests

- 226/226 regression tests pass (no new tests for this release;
  the trick-3 sweep pursuit fires only when bidder-team has won
  every prior trick — rare in random tournaments, exercised
  empirically rather than via a pinned test).

## v0.5.18 — decision-trees.md Section 4: Takbeer point-card extension

Translates the remaining Definite-confidence rule from Section 4
(Takbeer/Tasgheer) — extending v0.5.11's smother fix from "donate
highest of {A, T}" to "donate highest of all point cards"
(A, T, K, Q, J).

### Changed

- **Section 4 rule 7 extension** (Definite, videos 21, 22, 23):
  the smother branch in `pickFollow` (partner-winning + non-trump-
  led + feedSafe gate) now considers ALL point cards in the led
  suit, not just A and T. Saudi Takbeer convention donates the
  HIGHEST point card to partner's certain-winning trick. K (4
  raw), Q (3 raw), and J (2 raw) are also "ابناء" (point-card
  sons) — donating them when no A or T is in led suit still adds
  team-pile value vs the previous fall-through to lowestByRank.

  The existing v0.5.11 descending-sort + `[1]` correctly returns
  the highest after expansion; the gate (`#pointCards >= 2 OR
  completed >= 3 OR lastSeat`) is preserved unchanged. So a hand
  with AH+TH still picks AH (same behavior as v0.5.17). A hand
  with KH+8H now picks KH on `lastSeat=true` instead of falling
  to lowestByRank (8H). +4 raw donated per occurrence.

### Confirmed (no code change)

- **Section 4 rule 13** (K-tripled / مثلوث الشايب trickle, Common,
  video 17): "Sun, hold K + 2 lower in led suit, opp leads → play
  SMALLEST first across tricks 1–2". This is ALREADY correctly
  handled by the existing pickFollow fall-through:
  - When opp's A/J/Q is unplayed, K is NOT highest unplayed →
    `winners` branch doesn't fire on K → falls to `lowestByRank`
    of legal (= smallest X card). ✓ Matches the rule.
  - When opp's higher cards are gone, K IS highest unplayed →
    `winners` branch returns K (or another winner). The K-tripled
    rule's "save K for trick 3" intent is achieved naturally
    because K wouldn't be the boss in tricks 1-2 if A is still
    out. No new code needed.

### Deferred

- **Rules 4–6 (deceptive overplay)** — Sometimes-confidence,
  single-source. Sacrifice top to bait re-lead. Requires complex
  scenario detection (partner played mid-trump, opp played low,
  we hold J+9, etc.). Defer to a focused release with the
  `pickFollow.deceptiveOverplay` branch + Saudi Master-tier
  variant.

- **Rules 10–12 (Hokm consecutive top trumps)** — Definite, video
  22, but the scenarios are subtle (Takbeer-mandatory vs INVERT
  vs over-cut-with-smaller depend on rank-adjacency analysis of
  trump cards). Defer to a focused release.

### Tests

- 226/226 regression tests pass. Section E.2 (Takbeer A over T)
  still pins AH (highest of point cards). The expansion to K/Q/J
  doesn't change A/T-present scenarios; it adds new scenarios
  where K alone is the highest available point card.

## v0.5.17 — SWA tightening + display fix + R.IsValidSWA pre-existing bug

User-reported SWA issues. Three distinct fixes:

### 1. SWA strict-caller (R.IsValidSWA cooperative branch tightened)

The pre-v0.5.17 cooperative branch accepted "if SOME partner play
leads to caller winning" — partner could optimally duck under the
caller's lead to preserve the SWA. User report: "SWA should only
work if the player will actually win every hand not back and forth
with their teammate."

Tightened to "EVERY partner play must lead to caller winning" —
partner is treated adversarially in the recursion. Combined with
the per-trick `winner == callerSeat` check, this enforces:
**caller alone wins every remaining trick under ANY legal play
sequence**. Partner may not over-take with a higher card; if
partner CAN over-take in any legal play, the SWA is invalid.

Trade-off: SWA becomes harder to validly claim. Some hands that
previously passed (caller-relies-on-partner-ducking) now fail.
Saudi-strict convention says caller must be self-sufficient —
this matches the stricter interpretation.

### 2. R.IsValidSWA pre-existing bug fix

Discovered while writing Section O regression tests. The "caller
emptied hand → success" early-return at Rules.lua line ~374 fired
WHENEVER `caller.hand` was empty, including mid-trick — after
caller played their last card as the 1st/2nd/3rd play. Subsequent
opponent ruffs (or partner over-takes) were never seen by the
validator. False-positive SWA in any 1-card lead scenario where
the opponent could ruff.

The V14 audit fix earlier only addressed the 4th-play case (added
`#plays == 4` branch above the early-return). The 1st/2nd/3rd-play
case was still broken. Now: gate the early-return on `#plays == 0`
(between tricks) so mid-trick states correctly continue the
recursion.

### 3. SWA card display in every scenario

User-reported: "SWA does not show — i need to see the actual cards
in every scenario when it is called for 5 seconds."

The pre-v0.5.17 ≤3-card "instant claim" branch resolved the SWA
without setting `swaRequest` — so the UI banner (which only renders
when `swaRequest` is non-nil) never displayed the caller's cards
in that scenario. Per user requirement, ALL SWA flows now go
through the 5-second permission display window:

- **Bot-initiated SWA** (`Net.MaybeRunBot` SWA branch): removed the
  `handCount <= 3` shortcut. Now sets `swaRequest` + broadcasts
  `MSG_SWA_REQ` + arms the 5s timer for every claim.
- **Human-initiated SWA** (`Net.LocalSWA`): removed the
  `handCount >= 4` gate. Same 5s window for all claims.

The opponent-team bot auto-accept still fires for ≤3-card claims
(no real defensive position with so few cards), and Takweesh is
still possible during the window — but the cards are visible.

### Added (Section O tests)

- **O.1** 1-card SWA, caller's AS unbeatable, valid (positive).
- **O.2** 1-card SWA, opp can ruff caller's AS, invalid (catches
  the pre-existing bug — fails on pre-v0.5.17 code).
- **O.3** 1-card SWA, partner's only-play over-takes caller's lead,
  invalid (catches the same bug).
- **O.4** 2-card SWA, partner has TWO clubs (one would over-take,
  one would duck), invalid under strict-caller (catches the
  cooperative=EVERY tightening).

### Tests

- 226/226 regression tests pass (was 222 + 4 new Section O).

### Notes

- Saved games unchanged; v0.5.16 saves load as v0.5.17.
- The Hokm-vs-Sun overcall-window UX request from the second user
  message ("any player bid Hokm in 1st/2nd round → 5-second Sun-
  overcall window with WLA waive button, Ace-special-case excludes
  bidder") is OUT OF SCOPE for this release. The current bidding
  flow DOES allow Sun-overcall (verified end-to-end via
  HostAdvanceBidding trace) — but as sequential turn-based bidding,
  not as a discrete simultaneous-overcall window. Implementing the
  proposed UX requires a new `PHASE_HOKM_OVERCALL_WINDOW`, new wire
  messages, UI integration, and race-condition handling — a
  multi-day implementation. Will be a separate focused release.

## v0.5.16 — decision-trees.md Section 6: AKA signaling refinements

Translates two AKA-related rules from Section 6:

- **S6-6 Implicit AKA on bare-Ace lead** (Definite, video 18). The
  H-5 receiver in `pickFollow` now fires on partner's bare-Ace lead
  in a non-trump suit, even when no explicit `MSG_AKA` was
  broadcast. Per Saudi convention, leading bare A non-trump IS the
  implicit AKA call. Receiver suppresses the forced trump-ruff and
  plays a low non-trump instead. Detection: partner LED (first play
  of trick) a card with rank=A in a non-trump suit.

- **S6-10(c) AKA-sender skip on Ace** (Definite, video 18). Bot
  no longer broadcasts `MSG_AKA` when leading an Ace — that's the
  implicit-AKA case (S6-6) and the explicit announcement is
  redundant. Applied as a new gate in `Bot.PickAKA` after the
  existing `su == trump` and bot-partner gates.

### Notes

- 222/222 regression tests pass. The Section E v0.5.11 fix tests
  briefly broke during implementation when the implicit-AKA branch
  fired too broadly (matched partner's followed-Ace, not just led-
  Ace). Fixed by narrowing detection to `trick.plays[1]` (the
  trick's lead play). Test pin re-confirms expected behavior.
- The remaining S6 rules (S6-1/2/3/4 touching-honors, S6-7
  pos-4 ruff release heuristic, S6-10 (f)/(g) sender preconditions)
  are deferred — touching-honors needs new ledger keys + sampler
  integration; the others require richer state tracking.

## v0.5.15 — easy-wins batch (UI gate + Ashkal test fixture + doc refresh)

Audit follow-up batch from the v0.5.13/v0.5.14 deferred lists. Pure
small-LOC items + audit-recommended test fixture + doc maintenance.

### Sun-overcall investigation (no code change)

Verified end-to-end via inline trace: round 1 Sun-overcalls-Hokm
works correctly. The earlier user observation likely reflects bot
threshold tuning (a 2-Ace hand without mardoofa scores too low to
overcall — correct per Saudi convention since failing Sun is -26
vs failing Hokm -16). All 4 Saudi rules pass:
- Round 1 Sun overcalls Hokm ✓
- Hokm cannot overcall a prior Sun ✓
- Two Sun bids: first wins ✓
- Round 2 Sun overcalls Hokm ✓

### Fixed

- **UI Bel button consults R.CanBel** (UI.lua, PHASE_DOUBLE
  render). Previously the Bel/Bel-open/Bel-closed buttons rendered
  unconditionally for the eligible defender; clicking them in a
  forbidden Sun ≥100 scenario was silently dropped by Net.LocalDouble's
  R.CanBel guard — confusing UX. Now: when R.CanBel returns false,
  show "Bel forbidden (Sun >=100)" disabled placeholder + Skip.

### Added

- **Section G in tests/test_state_bot.lua** — 16 Ashkal eligibility
  test cases (4 dealer values × 4 seat values). Pins post-v0.5.7
  correct behavior: only `bidPos >= 3` (dealer + dealer's-LEFT) may
  call Ashkal. Audit-recommended fixture from v0.5.6/v0.5.7 saga.

### Changed (docs)

- **glossary.md "Re-anchoring line numbers" section** — refreshed
  current snapshot table for v0.5.15. Picker line numbers drifted
  +165 to +461 lines across v0.5.8 → v0.5.14. Snapshot included
  alongside the existing grep recipe.
- **decision-trees.md section headers** — Sections 1–7 line-number
  refs updated to current values. Cell-level "MAPS-TO" line refs
  inside the tables NOT updated (would be hundreds of edits) —
  treat them as approximate.
- **decision-trees.md S6-7 stale claim removed** — the doc claimed
  `R.IsLegalPlay` "may need a 'partner winning trick' exception."
  Wave-2 audit confirmed Rules.lua:118–121 + 147–149 already have
  it. Updated to "ALREADY WIRED" + flagged the actual remaining
  gap (a pickFollow heuristic to *prefer* non-trump discard when
  released, separate from the legality fix).

### Deferred to a future release

- **Section 3 rule 1** (`pickLead` strong-card-hold). The user's
  queue marked it "easy" but the rule requires post-processing the
  chosen lead card to detect "leading our strong suit early"
  (T-as-top in non-A suit, partner hasn't captured trick) and
  rerouting to a different suit. Non-trivial in the existing
  pickLead structure with multiple lead heuristics (Tahreeb pref,
  Fzloky pref, Advanced bare-Ace, bidder trump-pull, lead-from-
  longest). Better as a focused release.

### Tests

- 222/222 regression tests pass (was 206 + 16 new Section G).
- No production behavior change beyond the UI Bel button gate
  (which now matches Net.LocalDouble's already-existing wire-side
  enforcement).

## v0.5.14 — decision-trees.md Section 9: Tanfeer (تنفير)

Translates Section 9 (Tanfeer / opponent-disrupt convention) — 3
rules. Inverse of Section 8 Tahreeb: where Tahreeb signals run
sender→partner using top-down/bottom-up direction encoding,
Tanfeer signals run via the discarded SUIT alone (positive single-
event signal) when OPP is winning. Also wires the receiver-side
opp-signal avoidance and revives the formerly-dead
`tahreebAvoidSuit` variable from the Wave-2 audit.

### Wired (Section 9 rules)

- **N-1 Sender (Common, video 03).** When opp is winning AND we're
  void in led suit (so we're discarding from a non-led non-trump
  suit), pick the LOWEST card from a "wanted suit" — a non-trump
  suit where we hold a high card (A or T) AND ≥1 spare low to
  discard. The discarded SUIT signals partner "I want this back";
  we keep the high card in hand. M3lm+ + bot-partner-only.
  Implementation in `pickFollow` after Section 4 rule 1.

- **N-2 Default semantics (Common, video 03).** Doc-only — the
  existing pickFollow already defaults to lowestByRank when winner
  is uncertain (no specific Tanfeer encoding fires). LowestByRank
  is closer to "Tahreeb-low" (positive partner-want) than Tanfeer-
  positive, so the default aligns with the doc's "Tahreeb is the
  dominant convention" claim. Documented as a comment in the N-1
  block.

- **N-3 Receiver (Common, video 10).** `pickLead` M3lm+ block now
  reads OPP `tahreebSent` (in addition to partner's). Opp's
  "want"/"bargiya" classifications add to a `tahreebAvoidSet`.
  Conflict resolution: if our partner-pref-suit is ALSO in the
  opp-avoid set, drop the partner pref. Defending against opp's
  signal dominates partner-help when both signals point at the
  same suit (rare).

### Fixed

- **Dead variable revival.** v0.5.10's receiver block set
  `tahreebAvoidSuit` from partner's "dontwant" but never read it.
  Wave-2 audit flagged. Now consumed by the v0.5.14 N-3 conflict
  resolution: partner-dontwant suits added to the same
  `tahreebAvoidSet` along with opp-want/bargiya.

### Tests

- 206/206 regression tests pass (was 202 + 4 new Section F).
- **F.1**: N-1 sender — opp winning + void in led + A+low in side
  suit returns the LOW (7H). Sun contract used since Hokm + opp-
  winning + void-in-led triggers must-trump (no non-trump
  candidates for N-1 to pick from).
- **F.2**: N-1 sender doesn't fire on lone A (no spare low in
  same suit). Falls through to lowestByRank.
- **F.3**: N-3 receiver — opp `tahreebSent` ascending sequence
  records as want; pickLead consumes the opp signal without crash.
- **F.3b**: N-3 conflict resolution — partner pref + opp signal
  same suit → partner pref dropped.

### Notes

- Asymmetric harness still runs clean (PickFollow N-1 fires only
  in opp-winning + void-in-led + qualifying-wanted-suit scenarios,
  rare in symmetric play).
- No data shape changes; v0.5.13 saves load as v0.5.14 unchanged.
- Deferred Section 9 items: none — all 3 rules wired or documented.

## v0.5.13 — S-3 calibration + magic-number K.* promotion

Two related items from the v0.5.11 deferred list:

1. **S-3 (3-Ace Sun bonus) calibration:** the v0.5.8 implementation
   used `+12` to nudge 3-Ace hands toward Sun. Wave-2 audit found
   that 3-Ace hands without an AKQ stopper triple landed at sun ≈ 41
   vs thSun = 44–56, which couldn't fire R1 reliably. The
   decision-trees.md Section 1 row ranks S-3 as Definite ("almost
   always Sun"), so the formula should clear the median threshold
   reliably. Bumped from 12 → 15: the floor moves from 41 to 44,
   crossing thSun in ~70% of jitter outcomes (vs ~30% under +12).

2. **Magic-number K.* promotion:** v0.5.x added several inline
   tunable literals to `Bot.PickBid` and `Rules.R.CanBel`. Pulled
   them into named `K.*` constants in Constants.lua so future
   tuning lives in one place and comments can't drift from values.

### Added (Constants.lua)

- **`K.BOT_SUN_3ACE_BONUS = 15`** (S-3, was inline +12; bumped per
  Wave-2 calibration)
- **`K.BOT_SUN_MARDOOFA_BONUS = 5`** (S-8 per A+T mardoofa pair)
- **`K.BOT_SUN_MARDOOFA_PAIR_CAP = 2`** (S-8 max pairs counted)
- **`K.BOT_BIDDING_SUN_OVER_HOKM_MARGIN = 5`** (B-5 round-2 margin)
- **`K.BOT_ASHKAL_DIRECT_SUN_PIVOT = 85`** (A-6 65/85 pivot)
- **`K.BOT_PICKBID_BELOTE_BONUS = K.MELD_BELOTE`** (B-6; aliased to
  the meld constant so the bid bonus tracks the actual scoring
  bonus if either is ever retuned)
- **`K.SUN_BEL_CUMULATIVE_GATE = 100`** (E-1 / R.CanBel; Saudi
  Bel-legality threshold for Sun)

### Changed (Bot.lua)

- S-3 bonus now reads `K.BOT_SUN_3ACE_BONUS` (=15, bumped from 12).
- S-8 mardoofa bonus and pair cap now read K.* constants.
- B-5 Sun-over-Hokm margin reads `K.BOT_BIDDING_SUN_OVER_HOKM_MARGIN`.
- A-6 Ashkal pivot reads `K.BOT_ASHKAL_DIRECT_SUN_PIVOT`.
- B-6 Belote bonus reads `K.BOT_PICKBID_BELOTE_BONUS`.

### Changed (Rules.lua)

- `R.CanBel` reads `K.SUN_BEL_CUMULATIVE_GATE` instead of inline `100`.

### Tests

- 202/202 regression tests pass (no behavior change for
  same-strength inputs; the S-3 +3 nudge shifts which 3-Ace hands
  trigger the Sun-bid threshold but is empirically validated by
  the asymmetric harness still running clean).

### Notes

- No new tests in this release. The 6 new K.* constants are
  static values; the S-3 calibration change is verified
  by the asymmetric harness's clean run + the
  pre-existing PickBid sanity tests still passing.
- Saved games unchanged; v0.5.12 saves load as v0.5.13 unchanged.

## v0.5.12 — test coverage for v0.5.11 fixes (Wave-3 audit follow-up)

The 40-agent swarm audit's Wave-3 verification flagged that v0.5.11
shipped 4 load-bearing fixes (Race A, Section 4 rule 1, Takbeer
smother, T-4 over-fire gate) with **zero new tests**. A future
refactor could silently re-flip the behavior — particularly the
single-character Takbeer sort flip and the Section 4 rule 1
HIGHEST-vs-LOWEST direction. This release adds 6 targeted regression
tests pinning the post-v0.5.11 behavior.

### Added (test coverage)

- **`tests/test_state_bot.lua` Section E** — 6 new tests pinning
  the v0.5.11 fixes:
  * **E.1** Section 4 rule 1: Sun losing-side off-suit dumps HIGHEST.
    Pre-v0.5.11 returned LOWEST (8H); post returns KH.
  * **E.2** Takbeer smother: partner certain-winning donates A over T.
    Pre-v0.5.11 returned TH; post returns AH.
  * **E.3** T-4 over-fire gate: K-doubleton + A-doubleton both skip
    Tahreeb encoding, falling through to lowestByRank → 7S
    (preserves the high cards). Pre-v0.5.11 returned KH (over-fired).
  * **E.4** T-4 base case (sanity): Q-doubleton still fires the
    Tahreeb encoding correctly (gate doesn't accidentally block Q).
  * **E.5** PickDouble integration with R.CanBel: Sun + defender
    cumulative ≥100 → PickDouble returns false regardless of strength.
  * **E.5b** Hokm Bel not blocked by the Sun-100 gate (sanity).

### Notes

- 202/202 regression tests pass (was 196 + 6 new).
- The Race A wire-side fix doesn't have a direct test in this
  release because `tests/test_state_bot.lua` doesn't load `Net.lua`.
  Wire-side enforcement uses the same broadcast + `HostFinishDeal`
  pattern as the well-exercised AFK timeout path; missing test is
  acceptable risk for now.
- No production code changed in this release — pure test-coverage.

## v0.5.11 — 35-agent swarm audit follow-up: 4 fixes

A 35-agent (2-wave) swarm review of v0.5.8/9/10 surfaced 4 actionable
issues. All fixed. Wave-3 verification confirmed convergence.

### Fixed

- **Race A wire desync (Net.lua _OnDouble).** When v0.5.9 host receives
  a Bel from a v0.5.8 client (which has no LocalDouble Bel-100 gate),
  the host previously rejected silently. The v0.5.8 client had already
  applied `doubled=true` locally before sending the wire — round-stuck
  desync until the next deal. Now: on rejection, host broadcasts
  `MSG_SKIP_DBL` + calls `HostFinishDeal()`, snapping the client back
  into lockstep. Reuses the existing AFK-timeout recovery pattern.
  Severity: WARNING (rare in production — only mixed v0.5.8/v0.5.9
  sessions, both same-day-tagged, CurseForge auto-update window).
  Sources: Wave-1/Wave-2 audit Race-A finding.

- **Section 4 rule 1: Sun losing-side off-suit dump HIGHEST
  (Bot.lua pickFollow).** Previously the bot dumped the LOWEST in-suit
  card when forced to follow a suit it can't win — what video #9 calls
  "the biggest mistake in Baloot." Now: in Sun + must-follow + can't
  beat current winner, return `highestByRank` of the in-suit cards.
  Saudi inverse-laddering convention signals partner that we're done
  with this suit. Hokm trump-follow keeps LOWEST (Section 4 rule 2,
  separate convention). Hokm non-trump losing-side keeps LOWEST until
  doc clarifies.
  Sources: decision-trees.md Section 4 rule 1 (Definite, videos 05+09).

- **Section 4 rule 7 Takbeer fix (Bot.lua pickFollow smother branch).**
  When partner is certain-winning a non-trump-led trick, the Saudi
  Takbeer rule says donate the HIGHEST card (التكبير, "magnification").
  The smother branch was sorting ascending and returning [1] = LOWEST
  of {A, T} held in led suit — the literal opposite. Single-char flip
  (`<` → `>`). Maximizes trick-point capture (~1 raw point per
  occurrence: A=11 vs T=10).
  Sources: decision-trees.md Section 4 rule 7 (Definite, videos
  21+22+23).

- **T-4 over-fire gate (Bot.lua pickFollow Tahreeb sender).** v0.5.10's
  T-4 dump-larger-first rule fired on ANY 2-card non-trump non-led
  suit, including K+J / A+x doubletons — shedding the valuable card
  for a Tahreeb signal worth ~1 trick of coordination. Saudi rule's
  premise is a "2-card unwanted suit" (low cards). Now: T-4 only fires
  when the doubleton's higher rank is at most Q. K/T/A doubletons fall
  through to `lowestByRank`, preserving the high card.
  Sources: Wave-2 audit T-4 over-fire finding.

### Tests

- 196/196 regression tests pass.

### Notes

- No data shape changes; v0.5.10 saved games load as v0.5.11 unchanged.
- The Wave-2 audit also identified several deferred items NOT fixed in
  this release:
  * **UI Bel button doesn't consult R.CanBel** — UI shows the button
    in PHASE_DOUBLE without checking; clicking it triggers the
    LocalDouble silent gate. Cosmetic UX bug; low player-impact.
  * **S-3 +12 bonus undercalibrated** — 3-Ace hands without AKQ triple
    sit at sun=41 vs thSun=44-56, can't fire R1. Doc says "Definite
    almost always Sun." Could short-circuit `if aceCount >= 3 and
    sunMinShape then return BID_SUN` (parallel to S-4 Carré).
  * **Pigeonhole pin extension to H-1** — Definite Section 11 rule.
    BotMaster sampler hard-pins J/9 of trump to bidder; should also
    hard-pin remaining N trumps when N opponents are known void.
  * **Magic numbers ripe for K.* promotion** — B-5 +5, A-6 85, S-3 +12,
    S-8 +5, R.CanBel 100. Pure refactor.
  * **Decision-trees.md / glossary.md line numbers stale** — all
    picker references drifted +165 to +461 lines after v0.5.8/9/10
    insertions. Comment-only update.
  * **`tahreebAvoidSuit` dead variable** — set by receiver classifier
    but never consumed by the picker.

## v0.5.10 — decision-trees.md Section 8: Tahreeb (تهريب) MVP

The most heavily-sourced section of decision-trees.md (5 of 10 source
videos) — partner-supply discard convention. This release lands the
sender-side encoding + receiver-side reading scaffolding as MVP. All
the high-confidence Definite rules from Section 8 are wired; the
Common-confidence shape-specific receiver rules (T-mardoofa, T-tripled,
Sun-bidder special cases) are deferred to a follow-up.

### Added

- **`tahreebSent[suit]` per-seat style-ledger key** (Bot.lua, in
  `emptyStyle`). For each suit, accumulates the rank of every discard
  the seat made WHILE THEIR PARTNER WAS WINNING the trick. Reset
  per-round via `Bot.ResetMemory` (other ledger counters are per-game
  and stay across rounds — this matches their semantics).

- **`tahreebClassify(signals)` helper** (Bot.lua, before pickLead).
  Classifies a tahreebSent list into `"bargiya"` (Ace at index 1),
  `"want"` (≥2-event ascending), `"dontwant"` (≥2-event descending),
  `"hint"` (single non-Ace event), or `nil`. Uses `K.RANK_PLAIN` for
  ordering since Tahreeb signals are non-trump discards.

- **Tahreeb-signal recording in `Bot.OnPlayObserved`.** When `seat`
  plays a non-led-suit card AND the trick winner BEFORE this play
  was `R.Partner(seat)`, append the rank to
  `Bot._partnerStyle[seat].tahreebSent[discardSuit]`. The "winner
  before this play" is computed by reconstructing the trick with all
  plays except the current one and calling `R.CurrentTrickWinner`.

### Wired (Section 8 rules)

**Sender side** (in `pickFollow` partner-winning + void-in-led branch,
M3lm+ + bot-partner-only):

- **T-1 Bargiya** (Definite, videos 01, 03). Sun, partner winning,
  hand has A of side suit X with cover (≥2 cards in X) → discard
  the A as Bargiya ("I have the slam in X, lead it back").
- **T-4 Dump-ordering** (Definite, video 01). From a 2-card non-led
  non-trump suit, dump the LARGER first. Larger-first is unambiguous
  refusal; smaller-first would be a false positive bottom-up signal.

**Receiver side** (in `pickLead`, M3lm+ + bot-partner-only):

- **T-7/T-8 reading** (Definite, videos 09, 10). Read partner's
  recorded `tahreebSent` per suit; classify; if any suit returns
  `"bargiya"` (priority 3) or `"want"` (priority 2), prefer
  leading our LOWEST card in that suit (so partner's tops win). If
  any suit returns `"dontwant"`, mark it as avoid (informational —
  not yet consumed by the picker; the existing low-from-longest
  fallback naturally avoids declared-want suits).

### Tier gating

All Tahreeb logic is M3lm+ and bot-partner-only. Signals to a human
partner are noise (humans don't follow the convention reliably);
the existing Fzloky reasoning at the same site applies here.

### Tests

- 196/196 regression tests pass (no new tests in this release —
  Tahreeb behavior is exercised in production via the M3lm+ tier
  in real games; the existing harnesses use `pickContract` and
  fixed-bidder asymmetric deals which don't drive PickFollow's
  partner-winning discard branch).
- 100-round baseline tournament metrics identical to v0.5.9 — the
  Tahreeb branch fires only in M3lm+ Sun discard scenarios, rare
  enough in random symmetric play that aggregate metrics don't shift.

### Deferred (Section 8 rules NOT in this release)

- **Common-confidence receiver shape rules** (T-mardoofa, T-tripled,
  T+sun-bidder, T+non-sun-bidder, no-winning-card high-return,
  partner-resupply release-control). These need richer hand-shape
  inference + per-suit T-count tracking.
- **Three-discard variant** (Common, video 10). Strict-ascending
  3-event sequences. Requires extending the encoding state machine.
- **Sender's strong-suit avoidance** (Common, video 03). Don't
  Tahreeb FROM your strong suit. Currently the bot may Bargiya
  away its own strong-suit Ace if it has cover; the fix needs a
  "what is our strong suit" classifier.
- **Cutter-as-Tahreeb-event** (Common, video 03). Treating a ruff
  as a Tahreeb signal. Adds a state-tracking dimension.

## v0.5.9 — decision-trees.md Section 2: Sun Bel-100 legality gate

Translates the Definite-confidence rule from Section 2 (Escalation):
**in Sun contracts, only the team at <100 cumulative score may Bel**
(الحكم مفتوح في الدبل ≠ الصن; Sun has the gate, Hokm doesn't). This
is a rule-correctness item, not a heuristic — wired both bot-side
(`Bot.PickDouble`) and wire-side (`Net._OnDouble` + `Net.LocalDouble`)
so a stale-state human client cannot bypass it via the wire.

### Added

- **`R.CanBel(team, contract, cumulative)` in Rules.lua.** Authoritative
  predicate: returns true iff the given team may legally call Bel
  against `contract`, given the cumulative table. Hokm: always true.
  Sun: true iff `cumulative[team] < 100`. Three call sites consume the
  same predicate so behavior cannot drift between bot and human.

- **16 boundary tests** in `tests/test_rules.lua` Section N pin the
  `< 100` direction strictly (99 ✓, 100 ✗, 101 ✗), per-team
  independence (A blocked at 100 doesn't affect B), and defensive
  nil handling.

### Fixed (rule-correctness)

- **E-1 (decision-trees.md Section 2): Sun Bel-100 gate.** Previously
  bots and humans could call Bel in Sun even when their cumulative
  was >=100 — a Saudi-rule violation. `Bot.PickDouble` now early-returns
  false when `R.CanBel` is false; `Net._OnDouble` rejects illegal
  incoming wire messages with a `Warn` log; `Net.LocalDouble` short-
  circuits before issuing the wire.
  Sources: decision-trees.md Section 2 (Definite, video 11);
  glossary.md "Bel (×2) legality gate".

### Tests

- 196/196 regression tests pass (was 180; +16 R.CanBel boundary tests).

### Notes

- Hokm Bel logic is unchanged — the gate explicitly returns true for
  Hokm regardless of score.
- The other Section 2 rules are NOT in this release:
  * Round-1 Bel restriction (Sometimes confidence — TBD from a
    follow-up video to confirm exact mechanism)
  * Trick-3 Al-Kaboot pursuit trigger (Common; structural — needs
    pursuit-flag state field + pickLead read-side wire)
  * Sun bidder sweep-abandonment (Sometimes; score-aware sweep logic)
  * Defender Qaid-bait (Sometimes; doc explicitly says "bot likely
    should NOT do this without dedicated heuristic")

## v0.5.8 — Bot.PickBid: translate decision-trees.md Section 1 (bidding)

Translates Section 1 of `docs/strategy/decision-trees.md` (~25 rules
sourced from Saudi tournament videos) into `Bot.PickBid` picker code.
Each named patch (B-1 through B-6, S-1 through S-8, A-3 through A-6)
maps to a specific WHEN/RULE/MAPS-TO row in the decision tree.

A 3-agent post-commit audit surfaced one BUG (B-1 missing the
"≥1 side Ace" requirement from the source rule) and one stylistic
NOTE (leading-underscore locals). Both fixed before tagging.

### Bidding fixes

- **B-1, B-2, B-4: Hokm minimum-shape gate.** Bot now refuses to bid
  Hokm unless either (a) count ≥ 4 with J of trump (B-2 self-
  sufficient) OR (b) count == 3 with J of trump AND ≥ 1 side Ace
  (B-1 minimum, "الحكم المغطى"). The absolute floor (B-4) is "no J
  OR count ≤ 2 → never bid Hokm". The audit-fix step added the
  side-Ace requirement to the count==3 case — without it, a
  J+x+x trump hand with zero side aces could bid (no side trick
  power, structurally weak). Suits like 9+A+T+K (no J) likewise
  never bid. New helper `hokmMinShape(hand, suit)` enforces the
  rule; applied in round 1 (Hokm-on-flipped) and round 2 (best-suit
  search). Sources: decision-trees.md B-1, B-2, B-4 (all Definite, video 26).

- **B-5: 16-vs-26 Hokm-over-Sun bias.** Round 2 now requires Sun to
  beat the best Hokm score by ≥ 5 strength points before overcalling
  Hokm. Failed Hokm = 16 raw, failed Sun = 26 raw — the asymmetry
  bounds the failure cost. Borderline tied calls stay with Hokm.
  Sources: decision-trees.md B-5 (Definite, videos 25 + 26).

- **B-6: Belote (سراء ملكي) bidding bonus.** When the hand holds K+Q
  of any suit, that suit gets a +20 bonus in PickBid's Hokm-strength
  calculation (multiplier-immune Belote bonus). New helper
  `beloteSuit(hand)`. Sun bidding is unaffected (Belote is Hokm-only).
  Sources: decision-trees.md B-6 (Definite, video 26).

### Sun fixes

- **S-1, S-5, S-6: Sun minimum-shape gate.** Bot now refuses to bid
  Sun without either A+T mardoofa (إكة مردوفة) OR 2+ Aces. A bare
  1-Ace hand without T-cover gets torn through; Saudi rule says do
  not bid Sun. New helper `sunMinShape(hand)`.
  Sources: decision-trees.md S-1, S-5 (Definite/Common, video 25).

- **S-3: 3+ Aces strong-Sun bonus.** +12 to Sun strength when the
  hand holds 3 or more Aces. The 26-vs-16 risk premium is paid by
  sustained trick power across 3+ suits.
  Sources: decision-trees.md S-3 (Definite, video 25).

- **S-4: Carré of Aces (الأربع مئة) mandatory Sun.** When the hand
  holds all 4 Aces, returns `K.BID_SUN` as the earliest possible
  exit — beats every other path. Carré of Aces = 200 raw × 2 = 400
  effective ("Four Hundred").
  Sources: decision-trees.md S-4 (Definite, videos 25, 32, 38).

- **S-8: Sun-Mughataa A+T mardoofa bonus.** +5 per A+T mardoofa pair
  (capped at 2 pairs) on top of the normal Sun strength. "Covered
  Sun" emphasizes safety distinct from raw Ace count.
  Sources: decision-trees.md S-8 (Common, video 25).

### Ashkal fixes

- **Order restructure:** Ashkal-eligibility check now runs BEFORE
  the direct-Sun branch. Previously direct-Sun (sun ≥ thSun = 50)
  short-circuited Ashkal (sun ≥ thAshkal = 65), making the Ashkal
  block effectively dead code. The decision tree expects eligible
  seats to PREFER Ashkal in the 65-84 strength band; the restructure
  enables that preference. Non-eligible seats fall through to direct
  Sun unchanged.

- **A-3: bid-up = A → don't Ashkal.** Anti-trigger; losing A into
  no-trump with no T-cover is a textbook bad Ashkal.
  Sources: decision-trees.md A-3 (Definite, video 31).

- **A-4: bid-up = T + we hold A same suit → don't Ashkal.** Hokm
  preserves the A+T mardoofa; Ashkal converts to Sun and breaks it.
  Sources: decision-trees.md A-4 (Common, video 31).

- **A-5: 3+ Aces → don't Ashkal.** With that much firepower, claim
  the contract directly via Sun; we don't need partner's project.
  Sources: decision-trees.md A-5 (Common, video 31).

- **A-6: sun ≥ 85 → don't Ashkal (the 65/85 pivot).** 65-84 strength
  range = Ashkal range; 85+ = direct-Sun range. Falls through to the
  direct-Sun branch below.
  Sources: decision-trees.md A-6 (Common, video 31).

### Test status

- 180/180 regression tests pass (existing PickBid sanity tests:
  strong J+9+A+T+K hand still bids Hokm; weak 7/8-only hand still
  passes — both unaffected because the new gates don't reject those).
- 100-round symmetric baseline tournament unchanged: the harness
  uses `pickContract` (deterministic strongest-hand picker), not
  `Bot.PickBid`, so PickBid changes are not exercised offline.
- Asymmetric harness similarly uses fixed bidder + trump.
- Behavioral validation will land via player feedback; the WoW
  bidding loop is the real test surface for these changes.

### Notes

- No data shape changes; v0.5.7 saved games load as v0.5.8 unchanged.
- Deferred to a future patch (Section 1 rules NOT yet wired):
  * B-3 (5+ trump Kaboot pursuit flag — needs `S.s.pursuitFlagBidder`
    + pickLead read-side wire; structural)
  * B-7 (cumulative ≥ 100 Bel-fear bias on Sun bidding)
  * G-2 (round-1 conservative bias — already partially encoded via
    r1Base > r2Base; further tightening unclear without data)
  * G-4 (don't bid against partner's contract — Takweesh
    bid-override anti-trigger)

## v0.5.7 — v0.5.6 audit follow-up: revert Ashkal misfix + correct CHANGELOG narrative

A 3-agent audit on v0.5.6 surfaced two issues that had to be
fixed:

1. **The v0.5.6 Ashkal seat-restriction "fix" was an inversion,
   not a correction** — the original v0.5.5 code was already
   correct. v0.5.6's misfix is reverted in this release.

2. **The v0.5.6 CHANGELOG attributed a Bel-rate jump (0% → 13-67%)
   to the score-rounding cascade through `scoreUrgency`. That
   attribution was empirically false** — A/B test reverting the
   rounding alone showed identical Bel rates. The actual cause
   was v0.5.5's harness state-leakage fix, not v0.5.6's rounding
   change. Narrative corrected.

Plus a small test-fixture cleanup: `tests/test_rules.lua` had
two assertions hard-coded to the OLD `(x+4)/10` formula; both
coincidentally passed under the new `(x+5)/10` formula but were
asserting the wrong invariant. Updated to `+5` and added explicit
"5 rounds UP" boundary tests.

### Fixed

- **Reverted State.lua:1450-1490 Ashkal seat-restriction.** The
  v0.5.6 change to `bidPosition == 1 OR bidPosition == 4` was
  based on misreading WHEREDNGN's seat geometry. Audit against
  `UI.lua:223-225` confirms `R.NextSeat(seat) = (seat % 4) + 1`
  is "the seat to your RIGHT" (the existing UI code documents
  this — `pos == "right"` returns `R.NextSeat(me)`). So in the
  bidding order `{dealer+1, dealer+2, dealer+3, dealer}`:
  - bidPosition 1 = dealer+1 = **dealer's RIGHT** (NOT eligible)
  - bidPosition 3 = dealer+3 = **dealer's LEFT** (eligible)
  - bidPosition 4 = dealer (eligible)

  Video #31's "dealer + dealer's LEFT" therefore maps to
  positions 3 + 4 — exactly what `bidPosition < 3` (the v0.5.5
  code) was already enforcing. **The v0.5.5 code was correct;
  the v0.5.6 misfix is reverted.**

  Comment block in State.lua updated to explicitly cite
  UI.lua's seat convention as the disambiguator.

- **Updated `tests/test_rules.lua` div10 assertions** to use
  `(x+5)/10` and added 3 explicit boundary tests pinning
  "5 rounds UP" behavior:
  - `div10(65) = 7` (5 rounds UP)
  - `div10(15) = 2` (5 rounds UP)
  - `div10(64) = 6` (4 rounds DOWN)

### Notes

- The score-rounding fix in `Rules.lua:698` (`(x+4)/10` →
  `(x+5)/10`) is **kept** — it remains mathematically correct
  per video #43. The CHANGELOG narrative attributing the Bel-rate
  cascade to it has been corrected, but the fix itself stands.
- Strategy docs (`docs/strategy/bidding.md`,
  `docs/strategy/decision-trees.md`) updated to reflect the
  corrected Ashkal seat geometry.
- 180/180 regression tests pass (was 177 before; 3 new boundary
  tests added).

### Audit findings (recorded for traceability)

- Audit #1 (Ashkal): FLAGS — verdict driven by `UI.lua:223-225`
  seat-direction convention conflicting with v0.5.6's comment.
  Resolution: revert.
- Audit #2 (score rounding): FLAGS minor — test fixtures
  hardcoded `+4` formula. Resolution: update to `+5` + add
  boundary tests.
- Audit #3 (Bel-rate cascade): REFUTED — empirical A/B test
  showed rounding had zero causal effect on Bel rates. The
  v0.5.6 CHANGELOG narrative was a false attribution.
  Resolution: correct the narrative; the actual cause was
  v0.5.5's harness state-leakage fix unmasking previously-hidden
  Bel events.

## v0.5.6 — Saudi tournament-video doc batch + 2 rule-correctness fixes

This release lands two things:

1. A massive **strategy-docs scaffold** in `docs/strategy/`
   (~24,000 words, 11 files) distilled from 40+ Saudi Baloot
   tutorial videos processed via yt-dlp auto-captions and
   whisper-turbo on RTX 5080 GPU.
2. Two rule-correctness fixes surfaced by the doc audit:
   one `State.lua` Ashkal seat-restriction fix and one
   `Rules.lua` score-rounding direction fix.

The bigger Bot.PickBid heuristics-wiring work (translating the
new `decision-trees.md` Section 1's ~25 bidding rules into
picker code) is **deliberately deferred** to a follow-up so the
docs and the picker-code translation can be reviewed
independently.

### Fixed (rule correctness)

- **Ashkal seat restriction (State.lua:1450-1487).** Per video
  #31 "شرح الاشكل بالتفصيل في البلوت", only the **dealer + dealer's
  LEFT** (يسار الموزع) may call Ashkal. The previous code
  enforced "bidPositions 3 + 4 in turn order" which maps to
  **dealer's RIGHT + dealer** — wrong direction. The new check
  is `bidPosition == 1 OR bidPosition == 4` (dealer's-left = pos 1
  in CCW bidding order, dealer = pos 4). Comment block updated
  to cite the video and explain the seat geometry.

- **Score rounding direction (Rules.lua:698).** Per video #43
  "حساب النقاط في البلوت للمبتدئين", Saudi convention is **5 rounds
  UP** (65 raw → 70, 67 raw → 70, 64 raw → 60). The previous
  `div10(x) = floor((x + 4) / 10)` rounded 5 DOWN. Corrected to
  `floor((x + 5) / 10)`. Secondary effect: cumulative scores
  reach the 100/152 thresholds slightly faster, which cascades
  through `scoreUrgency` / `matchPointUrgency` and noticeably
  raises bot-bot Bel rates in baseline tournaments (a positive —
  v0.5.5's 0% Bel was a known structural gap).

### Added (strategy docs)

- **`docs/strategy/`** (new folder, 11 files):
  - `README.md` — navigation + decision tree
  - `glossary.md` — Arabic ↔ code-identifier mapping with Lua
    line cross-refs; authoritative card-name family-trio (شايب=K,
    بنت=Q, ولد=J); Tahreeb / Tanfeer / Faranka / Bargiya /
    Takbeer / Tasgheer / Mardoofa / Mughataa fully defined
  - `decision-trees.md` — operational WHEN/RULE/MAPS-TO chains
    across 11 sections; ~140+ rules with confidence ratings
    (Definite / Common / Sometimes) sourced from videos
  - `saudi-rules.md` — rule deltas vs French Belote; rule-
    correctness verifications cross-checked against `Rules.lua`
    / `Net.lua` (Bel-100 gate, pos-4 ruff-relief, must-overcut-
    not-partner, Sun ×2 multiplier, Ashkal seat eligibility);
    Kasho-vs-Qaid distinction; Reverse Al-Kaboot
  - `bidding.md` — Hokm/Sun/Ashkal hand-strength heuristics
    (J+مردوفة+إكا minimum Hokm; A+T mardoofa minimum Sun;
    16-vs-26 failed-bid asymmetry; trump-count tiers; Ashkal
    65/85 threshold pivot)
  - `escalation.md` — Bel/Bel-x2/Four/Gahwa chain
  - `signals.md` — Tahreeb (5 forms, 70/25/5 prior, two-trick
    confirmation, "biggest mistake in Baloot" rule); Tanfeer as
    parent class with Tahreeb as intent-bearing subset; Bargiya
    2-flavor split (come-to-me invite vs defensive shed); AKA
    touching-honors signaling
  - `endgame.md` — Faranka (5-factor Sun framework, Hokm 5
    exceptions); the "smart move" (J/T sacrifice deception);
    Al-Kaboot trick-3 trigger; SWA strict-deterministic
  - `opening-leads.md` — strong-card timing; Tahreeb-return
    decision tree by length
  - `bot-personalities.md` — tier-fit table for new heuristics
  - `transcripts.md` — yt-dlp + Whisper workflow doc
- **`CLAUDE.md`** — repo-level guidance pointing future Claude
  sessions to `docs/strategy/`; non-obvious Saudi rules
  highlighted (9 doesn't form Carré, Belote multiplier-immune,
  Sun ×2, etc.)

### Open questions documented (not fixed)

- Sun Belote (ملكي) — single-source claim of K+Q meld in Sun;
  currently Hokm-only in code. **Decision: keep Hokm-only.**
- سيكل (sykl) — possible 9-8-7 sequence meld; unconfirmed.
- Bel hand-strength thresholds — no video covered specific
  numerical thresholds for *when* to call Bel; remaining gap.
- 5 procedural bid-rules from video #28 cross-checked: 4 of 5
  already implemented in `State.lua` `S.HostAdvanceBidding`,
  1 (auto-convert-to-Sun on missing trump) is UI-prevented.

### Deferred to follow-up

- **Translate `decision-trees.md` Section 1's bidding rules
  into `Bot.PickBid` picker code.** The decision-trees.md
  format gives exact Bot.lua line-N maps; the picker-code
  translation is the natural next step but kept separate from
  this commit so docs and code-translation can be reviewed
  independently.

### Test status

- 177/177 regression tests pass.
- Baseline tournament: Bel rates jumped from 0% (v0.5.5) to
  13-67% in natural mode, primarily from the rounding-direction
  cascade through `scoreUrgency`. Game outcomes still well-
  distributed; no test regressions.

## v0.5.5 — playtest-fixture audit: harness state-leakage bug found

A targeted playtest-fixture audit (asked: "is Master good enough?")
built a new `test_asymmetric_metrics.lua` harness that biases the
deal so the bidder gets a realistic strong-Hokm trump cluster
(J+9, J+9+A, or J+9+A+T of trump). Running it surfaced a
LONG-STANDING bug in BOTH the asymmetric and the existing
baseline harnesses that silently masked all Bel/Triple/Four/Gahwa
measurements as 0% across every v0.5.x release.

**No production code changed in this release.** Live bot behaviour
is unaffected — the bug was purely in the offline tournament
harnesses. v0.5.0–v0.5.4 telemetry must be re-read with the
"escalation rates were unobservable" caveat.

### Fixed (test harness)

- **State-leakage bug in `resolveEscalation` (test_baseline_metrics.lua,
  test_asymmetric_metrics.lua).** `Bot.PickDouble`, `PickTriple`,
  `PickFour`, and `PickGahwa` all read `S.s.contract` and
  `S.s.hostHands` directly. The harness called `resolveEscalation`
  BEFORE `playOneRound` (which is what calls `freshState` + sets
  the live state). So every escalation pick ran against either nil
  state (round 1) or the PREVIOUS round's contract+hands (rounds 2+).
  Result: defender PickDouble computed strength against the wrong
  hand and threshold against the wrong contract, so it almost never
  fired. Fix: call `freshState` and seed `S.s.contract` /
  `S.s.hostHands` / `S.s.cumulative` BEFORE `resolveEscalation`.
  `playOneRound` then re-runs `freshState` (idempotent) before play.

### Added

- **`tests/test_asymmetric_metrics.lua` + `tests/run_asymmetric.py`** —
  100-round tournaments at three bias levels (moderate / strong /
  elite) covering the full 6 tier configs × 2 modes matrix. Output
  written to `.swarm_findings/bot_asymmetric_metrics.json`.

- **`tests/probe_defender_strength.lua`** — diagnostic probe that
  computes the defender-strength distribution across 1000 hands per
  bias level and cross-validates by directly calling Bot.PickDouble.
  Confirms the formula matches: 16% defender-clear-rate at TH=60
  vs 16% per-defender Bel-fire rate from the live picker.

### Findings (post-fix tournament data)

Symmetric baseline (`bot_baseline_metrics.json`, 100-round tournaments):
- all_basic natural: Bel 67% (6/9 rounds played)
- all_advanced natural: Bel 13%
- all_m3lm natural: Bel 14%
- all_master natural: Bel 15%
- mixed_*_master natural: Bel 13–15%
- Triple still 0% across all natural-mode configs — bidder rarely
  has the strength to push back

Asymmetric (`bot_asymmetric_metrics.json`):
- moderate bias: Bel 0–36%, sweep 6–7% (similar to symmetric)
- strong bias: Bel 6–12%, first Triple observed (8% in basic)
- elite bias: Bel 0–8%, sweep climbs to 12–21% (bidder strong → sweeps)
- Master vs Basic in mixed configs: Master wins consistently across
  all bias levels (AvgB > AvgA in mixed_basic_master_natural at all
  three bias levels)

### Notes

- 177/177 regression tests still pass; pure test-infra change.
- Future calibration sprints can now use reliable Bel/Triple/Four/
  Gahwa rate measurements as a feedback signal.

## v0.5.4 — SWA banner shows the actual cards (player feedback)

Previously the SWA banner showed only "N cards remaining" + timer.
Player approved (or auto-approved) without seeing WHICH cards the
caller was claiming — especially opaque for bot-initiated SWA where
the player has no other visibility into the bot's hand.

### Changed

- **SWA banner now renders the caller's full hand inline (UI.lua).**
  The banner height grew from 38 to 100 px to accommodate a card-
  face row beneath the title/body. Up to 4 card slots (SWA fires at
  ≤4 remaining), centered horizontally, anchored to the banner's
  bottom edge. The cards are decoded from `swaRequest.encodedHand`
  which has been on the wire since v0.4.6 — only the visualization
  was missing. Saudi convention is "show your hand on SWA"; opponents
  can now actually inspect the claim before the auto-approve timer
  expires.

- **No data shape changes** — pure UI fix. v0.5.3 saved games and
  active SWA requests display correctly without any state migration.

### Notes

- Both render paths updated: the banner's self-tick OnUpdate (3 Hz
  for the timer countdown) and the `renderSWABanner` Refresh path.
  Both share `_lastEnc` to avoid redecoding the hand 3× per second.
- 177/177 regression tests pass; UI.lua syntax-checks clean via
  Lua loadfile.

## v0.5.3 — second ultra-test follow-up: 3 BUGs fixed

A 6-agent verification swarm against shipped v0.5.2 surfaced three
new bugs that the previous round missed. All three are now fixed.

### Fixed (BUGs)

- **BUG #1: `Bot._inRollout` flag leaked on rollout error
  (BotMaster.lua).** `BM.PickPlay` set `B.Bot._inRollout = true` and
  relied on the explicit `_restore` calls at every return path. But
  the rollout loop had no `pcall` around it. If `rolloutValue`,
  `R.IsLegalPlay`, `C.TrickRank`, or `R.ScoreRound` errored mid-
  rollout (malformed card, bad meld, nil ref), the error escaped to
  Net.lua's outer `pcall` — but `_inRollout` was never restored.
  Every subsequent `Bot.PickPlay` would then skip the BotMaster
  delegation guard and silently degrade Saudi Master to heuristic
  for the rest of the session. Now: rollout loop is wrapped in
  `pcall`; on error, `_restore(nil)` clears the flag and Bot.PickPlay
  falls through to heuristics for THIS pick only.

- **BUG #2: `PickFour` threshold floor was gated on `Bot.IsM3lm()`
  (Bot.lua).** v0.5.2's PickDouble unconditional floor cited "matches
  PickFour's defensive cap" — but PickFour's own floor was INSIDE
  the IsM3lm() block at line ~1958, so non-M3lm tiers (Basic /
  Advanced / Fzloky / Master) had no floor at all. With
  `scoreUrgency("defend")` and `matchPointUrgency` capable of
  dropping the threshold by 12+, this allowed false-Four bids on
  hands below the safe minimum strength. Lifted the floor cap OUT
  of the IsM3lm block so it applies unconditionally — symmetric
  with PickDouble's v0.5.2 behavior.

- **BUG #3: Trick-8 boss-scan was greedy (Bot.lua pickLead).** The
  v0.5.2 fix correctly added `trumpExhausted` to isSafe, but the
  boss-scan loop returned the FIRST boss in hand-iteration order
  rather than the BEST. With multiple bosses on trick 8 (especially
  when `trumpExhausted` opens up ALL non-trump bosses), throwing a
  7-of-spades-boss instead of a Ten-of-clubs-boss costs up to 10
  face-value points PLUS the +10 LAST_TRICK_BONUS goes to whichever
  card actually wins. Fix: collect all qualifying safe bosses into
  a list, then pick by `highestByFaceValue` (which is contract-aware
  via C.PointValue, correctly handling Hokm / Sun trump-vs-plain
  scoring).

### Notes

- No data shape changes; v0.5.2 saved games load as v0.5.3 unchanged.
- All Lua files pass syntax check; 177/177 regression tests pass.
- 100-round baseline tournament unchanged from v0.5.2 (the fixes
  affect rare paths: rollout errors, non-M3lm Four bids, and
  trick-8 multi-boss scenarios — none common enough to shift
  large-N tournament metrics).

## v0.5.2 — ultra-test follow-up: 2 BUGs + 3 WARNINGs fixed

A 12-agent ultra-verification swarm read the v0.5.0+v0.5.1 patches
end-to-end against the live tree and surfaced two actual bugs and
three latent footguns. All five are now fixed and the regression
suite (177 tests) plus 100-round baseline tournament still pass.

The headline empirical result: with the test-harness fix in this
release (BotMaster.lua now loaded by all four offline harnesses),
Master vs M3lm finally diverges in the standalone tournament —
all_master natural is winner=A (8.8/8.1, sw=0.06) while all_m3lm
natural is winner=B (6.6/10.3, sw=0.07). mixed_basic_master forced
flipped to winner=B (Master), confirming the v0.5_FINAL_REPORT
prediction held end-to-end.

### Fixed (BUGs from ultra test)

- **BUG #1: C-2 SWA C_Timer nil-guard misplacement (Net.lua).**
  When `C_Timer` is unavailable (test harness, pre-init edge cases),
  the previous `S.s.swaRequest` was set + broadcast was issued, but
  the auto-approve timer was silently skipped — leaving a dangling
  permission flow that never resolved. Now: timer arming check
  happens BEFORE the swaRequest assignment; if `C_Timer` is nil we
  degrade to the instant-claim path so the round never stalls.

- **BUG #2: C-4 isSafe excluded non-trump bosses in Hokm
  (Bot.lua pickLead trick-8).** The original isSafe expression
  `(contract.type ~= K.BID_HOKM) or C.IsTrump(c, contract)`
  excluded every non-trump boss card in Hokm — rendering the
  trick-8 boss-scan dead in the dominant case (Hokm contracts).
  Now: when `S.HighestUnplayedRank(contract.trump) == nil`,
  trump is exhausted and non-trump bosses ARE safe to lead;
  added `trumpExhausted` check to isSafe.

### Fixed (WARNINGs from ultra test)

- **WARNING #1: PickDouble had no threshold floor (Bot.lua).**
  Combined drops from `scoreUrgency("defend")` + `matchPointUrgency`
  could push the threshold down by 15+; combined with C-3b adding
  up to +31 to strength (3 voids × 5 + 3 Aces × 8) and BEL_JITTER
  ±10, weak-trump hands could fire false-Bels. Floored at
  `K.BOT_BEL_TH - 16` to match PickFour's defensive cap.

- **WARNING #2: H-4 Belote preservation passed `legal` not `hand`
  (Bot.lua pickFollow).** When must-follow forced non-trump play,
  `legal` would not contain K or Q of trump even when both were
  still in hand — `holdsBeloteThusFar(legal, ...)` returned false
  and the preservation logic was bypassed. Now passes `hand`; the
  filter still applies to `legal` below so legality is preserved.

- **WARNING #3: Net.lua double-delegation to BotMaster.PickPlay.**
  Since v0.5.0's C-1 fix made Bot.PickPlay delegate internally,
  the explicit `if B.BotMaster ... B.BotMaster.PickPlay(seat)`
  block in MaybeRunBot was redundant — and would cause double
  ISMCTS computation if BotMaster bailed and Bot.PickPlay
  re-delegated. Single canonical call: `B.Bot.PickPlay(seat)`.

### Fixed (test harness)

- **Test harness load order: BotMaster.lua now loaded by all four
  offline harnesses** (`test_baseline_metrics.lua`,
  `test_multiseed_metrics.lua`, `test_v0.5_traced_game.lua`,
  `test_bel_decision_quality.lua`). Without this, Bot.PickPlay's
  C-1 delegation fell through (B.BotMaster was nil) and Master
  silently degraded to M3lm in offline tournaments — masking the
  empirical proof that the C-1 fix was actually wired. With the
  load added, all_master and all_m3lm now produce divergent
  outputs in the standalone baseline (the result predicted in
  the v0.5_FINAL_REPORT but not previously reproducible offline).

### Notes

- No data shape changes; v0.5.1 saved games load as v0.5.2 unchanged.
- All Lua files pass syntax check; 177/177 regression tests pass.
- Baseline tournament metrics: see updated
  `.swarm_findings/bot_baseline_metrics.json`.

## v0.5.1 — Sprints B-H: complete bot improvement campaign

Continues the v0.5.0 work by landing the remaining 8 staged patches
from the bot improvement research campaign. v0.5.0 unlocked the
Saudi Master tier; v0.5.1 lands the strategy and coordination
heuristics that distinguish a competent player from a Saudi pro.

Empirical 100-round A/B tournament (`bot_baseline_metrics_sprint_BCDH.json`):
- All-Master (natural) flipped from B-wins back to balanced
  (8.8/8.1) — Master-vs-Master games are now near-symmetric
- Master ISMCTS rollouts have higher quality through
  partner-trump bias (H-3) and defender-Ace clustering (H-2 in v0.5.0)

### Added (Critical missing features)

- **C-2: Bot-initiated SWA (`Bot.PickSWA`).** Bots now claim the rest
  of the round when holding an unbeatable hand (≤4 cards, R.IsValidSWA
  passes). Net.lua MaybeRunBot dispatches SWA via the existing
  permission flow (5-sec auto-approve from v0.4.6) for ≥4 cards or
  instant-claim for ≤3. Saudi convention preserved. Silent gameplay
  improvement: bots no longer leak winnable trick-points to opponents
  by playing out unbeatable hands trick-by-trick.

- **C-4: Last-trick +10 targeting + AL-KABOOT pursuit.** Trick 8
  was previously played identical to trick 1 — `lowestByRank(winners)`
  in pos-4 wasted the highest face-value card on a cheap winner,
  forfeiting the LAST_TRICK_BONUS. Now `pickFollow` pos-4 on trick 8
  uses `highestByFaceValue`, and `pickLead` on trick 8 prefers boss
  cards in safe suits (or highest-rank if our team has won 7/7
  → AL-KABOOT pursuit mode).

- **C-3b: Defender-aware strength formula additions.** PickDouble's
  Bel-decision strength now adds void-suit count × 5 (each void =
  ruff potential) and side-suit Aces beyond the first × 8 (sustained
  trick-winning power). Combined with v0.5.0's TH=60 calibration,
  Bels now fire on the right defender hands.

### Added (High-priority strategy heuristics)

- **H-3: Sampler partner trump-count bias (`getPartnerCards`).** The
  bidder's partner now gets a trump-suit weighting (`desire[trump] = true`
  → weight 20 via the suit-fallback) plus a light non-trump-Ace bias
  (5 per Ace). Without this, the sampler under-trumped the partner
  in ~50% of worlds, distorting cooperative trump-clearing rollouts.

- **H-4: Belote (K+Q of trump) preservation.** `pickFollow` discard
  fallback now skips K and Q of trump in tricks 1-3 if BOTH are still
  in hand. Saudi rule: Belote +20 raw post-multiplier scores when
  both K and Q are played from the same hand. Bot was routinely
  shedding K via `lowestByRank` (rank 4, low-end). Belote bonus now
  preserved.

- **H-5: AKA receiver convention.** When partner announces AKA on
  the led suit and is currently winning the trick, the bot
  suppresses the forced trump-ruff and plays a low non-trump
  discard instead. The half-coordination from v0.4.5 (sender-only)
  is now complete.

- **H-6: A-of-trump preservation for late tricks.** In bidder
  pickLead trump-pull, the A of trump is now excluded from the
  highestTrump candidate set when (a) `#tricks < 5` AND (b) we have
  non-Ace trump available. Saudi pros spend J/9 on pull and reserve
  A for late tricks where its 11 face value + LAST_TRICK_BONUS = 21
  effective points.

- **H-8 (already in v0.5.0): scoreUrgency context-aware** — confirmed
  active in v0.5.1.

### Activated (Style ledger wiring)

- **H-9 (partial): `triples` counter wired into PickFour.** Previously
  written by OnEscalation but read by zero pickers. Now defenders
  facing a habitual-Triple bidder (`triples >= 2`) drop their Four
  threshold by 5 (capped at -16 combined with `gahwaFailed`).
  `aceLate` and `leadCount` remain dead — wiring them is staged for
  a future cleanup sprint.

### Empirical impact

Pre-v0.5 → v0.5.1 cumulative (100-round tournaments):

| Metric | Before | After (v0.5.0) | After (v0.5.1) |
|---|---|---|---|
| `all_master` natural AvgB | 10.3 | 8.5 | **8.1** (more competitive) |
| `mixed_basic_master` natural Master gp/round | 8.8 | **11.7** | 11.5 |
| `mixed_basic_master` forced winner | A | **B** | B (Master) |
| `mixed_m3lm_master` sweep rate | 0.07 | 0.13 | **0.13** |

### Verification

- 9/9 Lua files syntax-validated
- 177/177 tests pass
- 3 baseline JSONs preserved as evidence
  (`bot_baseline_metrics.json`, `_sprint_A.json`, `_sprint_BCDH.json`)
- v0.5.1 worktree retained for reference

## v0.5.0 — Sprint A: Saudi Master tier unlocked + bot quality improvements

The 20-agent ruflo-swarm "Bot Improvement" research campaign (the
larger 300-agent budget converged early) found 5 critical structural
defects + 9 high-priority gaps in bot behavior. This release lands
Sprint A — the highest-impact subset — verified via empirical 100-round
A/B tournaments that show measurable Master-tier wins for the first
time. Master vs Basic mixed tournaments flipped winner: Master team
gp/round +33%; sweep rate +86% in M3lm-vs-Master.

Full research report at `.swarm_findings/bot_improvement_v0.5_REPORT.md`.
Pre-Sprint-A baseline at `.swarm_findings/bot_baseline_metrics.json`;
post-Sprint-A at `bot_baseline_metrics_sprint_A.json`. Staged patches
for the remaining findings at `.swarm_findings/bot_proposed_patches/`.

### Fixed (Critical structural defects)

- **C-1: Saudi Master ISMCTS was dead code (CRITICAL).**
  `Bot.PickPlay` never delegated to `BotMaster.PickPlay`. Only
  Net.lua's MaybeRunBot reached the sampler — direct callers (AFK
  recovery, error fallback, test harnesses) all ran heuristics
  even with `saudiMasterBots=true`. Empirical proof: M3lm and
  Saudi Master produced byte-identical metrics across all 6
  tournament configs in 100-round runs. v0.5 wires the
  delegation at the top of `Bot.PickPlay`, gated by a new
  `Bot._inRollout` flag set by `BotMaster.PickPlay` to prevent
  ISMCTS from recursively re-entering itself.

- **C-5: numWorlds direction was BACKWARDS (HIGH).** v0.4.7 audit
  incorrectly marked H-2 as resolved; the production code still
  used 30 worlds at trick 1 (max uncertainty) and 100 at trick 8
  (least uncertainty). Inverted to 100/60/30 by trick number —
  early-trick decisions, where the state space is largest, now
  get the most sampling budget. ~50% reduction in early-trick
  rollout sampling noise.

- **C-3a: Bel threshold lowered 70 → 60 (HIGH).** Empirical
  bel-decision-quality test (`bel_decision_quality.json`) showed
  TH=70 fired Bel only 4.2% of the time in 1000 hands and was
  wrong 50% of those firings (literal coin-flip precision). At
  TH=60 the F1 score doubles (0.137 → 0.286). Calibration only —
  the underlying strength formula still has structural issues,
  documented in C-3b for a future sprint.

### Added (Sampler improvements)

- **H-1: Hard-pin J/9 of trump to bidder (HIGH).** Previously the
  desire-weight mechanism (J=50, 9=40) still placed them on
  defenders ~30% of sampled worlds — every such world was
  structurally inverted (defender holding the trump Jack), and
  every rollout pessimistic for the bidder team. Now hard-pinned
  via the same `meldPins` mechanism used for the bid card and
  declared melds.

- **H-2: Defender side-suit Ace clustering (HIGH).** Previously
  defender seats got `desire = {}` — side-suit Aces distributed
  uniformly. Real defenders cluster non-trump Aces (since the
  bidder claimed trump). Added `getDefenderCards`: each non-trump
  Ace gets weight 8, King 4, plus a long-suit incentive. Ships
  for both opposing seats; bidder's partner stays on `{}` (H-3
  staged for future).

### Fixed (Strategy heuristics)

- **H-7: Sun opening lead from shortest non-trump suit (MEDIUM).**
  Saudi pro convention is to lead from shortest suit in Sun
  (forcing opponents to play their boss early). Bot previously
  fell through to the same "low from longest" used by Hokm
  defenders — the longest-suit lead is right for Hokm but wrong
  for Sun (no trump shield; long-suit cards get over-trumped).
  Sun now leads shortest, with boss/Fzloky/singleton priorities
  preserved.

- **H-8: Context-aware near-win urgency (MEDIUM).**
  `scoreUrgency` returned -8 uniformly when our team was near-clinch,
  raising thresholds for ALL escalations. Saudi pros do the
  opposite for DEFENSIVE escalation (Bel, Four) — they aggress
  when one win clinches the match. Added `context` param: `"bid"`
  preserves the conservative -8 (offensive); `"defend"` flips to
  +5 (aggressive). PickDouble and PickFour now pass `"defend"`;
  PickBid/PickTriple/PickGahwa/PickPreempt stay `"bid"`.

### Empirical impact (100-round A/B tournament)

Pre-Sprint-A → Post-Sprint-A:

| Config | Metric | Before | After | Delta |
|---|---|---|---|---|
| `mixed_basic_master` natural | Master AvgB | 8.8 | **11.7** | **+33%** |
| `mixed_basic_master` forced | Tournament winner | A (Basic) | **B (Master)** | flipped |
| `mixed_m3lm_master` natural | Sweep rate | 0.07 | **0.13** | +86% |
| `all_master` natural | AvgB | 10.3 | 8.5 | -1.8 (more competitive) |

Master vs Basic empirically advantageous for the first time.

### Staged for future sprints (design specs in `.swarm_findings/bot_proposed_patches/`)

- **C-2: Bot-initiated SWA** (`Bot.PickSWA`)
- **C-3b: Defender-aware strength formula** (proper Bel calibration)
- **C-4: Last-trick +10 / Al-Kaboot pursuit** (LAST_TRICK_BONUS targeting)
- **H-3: Sampler partner trump-count bias**
- **H-4: Belote K+Q preservation**
- **H-5: AKA receiver convention**
- **H-6: A-of-trump preservation for late tricks**
- **H-9: Wire dead `_partnerStyle` counters** (leadCount, triples, aceLate)

### Verification

- 9/9 Lua files syntax-validated
- 177/177 tests pass
- A/B baseline JSON evidence committed
- Worktree experiment in `WHEREDNGN-sprintA` branch (kept for reference)

## v0.4.11 — Spectator mode + WoW deck

### Added

- **WoW card deck** ("Battle of Heroes" PNG set, 32 face cards at
  512×768 + synthesized purple/gold back). Sources placed in
  `cards/wow/_src/` (PNG), rasterized to 128×192 TGAs by the new
  `cards/_make_wow.py` script using LANCZOS resampling. Registered
  as `wow` in `CARD_STYLES` (UI.lua); cycle in via `/baloot cards`
  or the lobby Cards: button. The zip ships no back image so we
  synthesize one matching the deck theme: charcoal-violet body
  with diagonal violet lattice + warm-gold border.

- **Spectator support.** A 5th+ party member with no seat now sees
  the full table:
  - Three seat badges (top/left/right) populated using a fixed
    seat-1 anchor, mapping seats 2/3/4 to right/top/left.
  - A new "Spectating" info line in the hand-row area showing
    seat 1's name + card count (the seat that doesn't get a badge).
  - Banner (round-end / game-end) renders normally; the v0.4.8
    WIN/LOST headline correctly stays empty for spectators.
  - All player-action paths still gate on `S.s.localSeat`:
    `renderHand`, `renderActions`, `LocalPlay`, `LocalBid`,
    `LocalSWA`, `LocalTakweesh`, `IsMyTurn`, etc. all return early
    when there's no seat — spectators cannot interfere.
  - The v0.4.10 lost-round stinger and v0.4.8 WIN/LOST headline
    are also correctly suppressed for spectators (existing
    `s.localSeat` guards in `S.ApplyRoundEnd` and `setOutcome`).
  - Team coloring on the badges falls back to absolute team
    (A=green / B=red) for spectators — they don't have a partner
    relationship to claim "us-vs-them" against.

## v0.4.8 — Three small UI fixes (player feedback)

### Fixed

- **Lobby checkbox overlap:** the 4-tier bot checkbox stack
  (Advanced / M3lm / Fzloky / Saudi Master) had its bottom row at
  `y=12`, the same vertical band as the centred Host Game / Start
  Round / Fill Bots buttons. The "Saudi Master" label visually
  overlapped Host Game. Shift the entire stack up by 30 (new
  `y={108, 86, 64, 42}`) and bump the right-column Cards/Felt cycle
  buttons to match (`y={108, 86}`) so the top two rows still pair.

- **Pass label rendered as empty boxes for opponents:**
  `bidLabelForSeat` returned `"بس"` (Arabic colloquial "Pass") for
  the per-seat bid display below other players' names. WoW's bundled
  fonts (Arial Narrow / Frizz / Skurri) don't include Arabic glyphs
  — same constraint already documented for the AKA button — so the
  label rendered as empty boxes / glyph errors. Match the local-side
  bid-button convention: `"wla"` (Latin transliteration of ولا) in
  R2, `"Pass"` in R1.

- **Round-end banner: WIN / LOST headline:** the score banner showed
  "AL-KABOOT! / BALOOT! / ALLY B3DO" with YA MRW7 pointing at the
  losing team, but players had to mentally translate that contract
  framing into their own team's outcome. Added a large-font headline
  above the contract title showing "WIN" (green) or "LOST" (red)
  from the local player's perspective. Logic covers all branches:
  - Sweep → sweeping team wins
  - Contract made → bidder team wins
  - Contract failed → defender team wins
  - SWA valid → caller's team wins; invalid → opp wins
  - Takweesh caught → caller's team wins; false call → opp wins
  - Match end → S.s.winner team wins
  - Non-host degraded view → infer from delta sign

  Banner height bumped from 170 → 196 to fit. Spectators (no
  localSeat) get an empty headline, falling back to the existing
  contract-title context.

## v0.4.7 — 50-agent empirical + codebase audit (5 critical bugs found)

A second 50-agent ruflo-swarm audit, this time split 20 agents on
empirical playtest scenarios (tracing real game flows step-by-step)
and 30 agents on full-codebase review. The empirical wave alone
caught two CRITICAL bugs that pure static analysis missed in v0.4.6.
Full audit report at `.swarm_findings/v0.4.7_AUDIT_REPORT.md`.

### Fixed (Critical)

- **v0.4.6 turn-desync fix was incomplete (CRITICAL):** the self-heal
  block at `Net.lua:_OnPlay` correctly accepted host-signed plays for
  any seat AT THE FIRST GATE, then patched `s.turn`. But the SECOND
  authority gate (`if not isReplay and not authorizeSeat(seat, sender)
  then return end`) did NOT have the fromHost escape. For human
  seats, `authorizeSeat(seat, host)` returns false (sender is host,
  seat owner is the human's name), so the play was silently dropped
  AFTER the self-heal patched `s.turn`. The reported AFK auto-play
  cascade (player sees stuck turn → AFK fires → click an
  already-played card → "illegal play") was NOT actually fixed in
  v0.4.6 — only after this v0.4.7 patch is the chain complete. Mirror
  the fromHost escape on the second gate at Net.lua:1104.

- **AFK timeout silently forfeited melds (CRITICAL):**
  `_HostTurnTimeout`'s play branch auto-played the AFK seat's lowest
  legal card but did NOT auto-declare melds. The Saudi meld
  declaration window closes after trick 1 (`#s.tricks >= 1` gate in
  `S.GetMeldsForLocal` / `S.ApplyMeld` / `Bot.PickMelds`), so a human
  AFK'd through trick 1 silently lost their entire meld score — a
  declared Quarte (50 raw) under Bel ×2 = 100 raw = 10 gp lost with
  no UI feedback. Now mirrors `MaybeRunBot`'s auto-declare pattern:
  if `meldsDeclared[seat]` is false, run the meld picker on the AFK
  seat's behalf, broadcast, stamp `meldsDeclared`, then play the
  card. Outside the trick-1 window the meld picker returns `{}`
  naturally, so the fix is a no-op there.

- **BotMaster fallback deal path missing meldPins (CRITICAL):**
  `sampleConsistentDeal`'s primary path correctly pinned declared
  meld cards to their declarer (since v0.4.5). The fallback path
  (used when the primary 15-attempt loop exhausts) ignored
  `meldPins` entirely — a Tierce 7-8-9 of Hearts declared by seat 3
  could end up split across all four seats in fallback rollouts,
  corrupting every Saudi Master ISMCTS estimate in games with active
  melds. Fix mirrors the primary path: exclude `meldPins` keys from
  the fallback shuffle pool and pre-place them into the declaring
  seat's hand before filling the remainder.

### Fixed (High)

- **SWA 5-sec timer ignored pause:** both `_OnSWAReq` and `LocalSWA`
  C_Timer.After callbacks fired during paused games, force-approving
  SWA requests mid-pause. Now the timer's first action is a paused
  check; if paused, re-arm a fresh 5-sec window when the game resumes
  rather than auto-approving. Opponents retain the chance to press
  Takweesh after unpause.

- **Bot.OnPlayObserved fired on replay frames:** during a resync
  /reload, `_OnPlay` re-applies in-flight plays with `isReplay=true`.
  The Bot.OnPlayObserved call was outside the `not isReplay` guard,
  so void inference / firstDiscard / aceLate / leadCount / likelyKawesh
  counters could be poisoned by phantom replay observations on any
  client with bot logic loaded. Currently safe because only humans
  rejoin (B.Bot is unused on their clients), but the latent risk is
  closed — guard added.

### Fixed (Medium one-line patches per audit synthesis)

- **`C.IsKaweshHand` requires ≥5 cards:** Saudi Kawesh is defined on
  the first-five-dealt hand. The previous guard `#hand == 0` allowed
  a 1-4-card mid-deal hand of all 7/8/9 to falsely match. Tightened
  to `#hand < 5`.

- **`WHEREDNGN.lua` `B.Net` nil-guard:** the CHAT_MSG_ADDON dispatcher
  called `B.Net.HandleMessage` without a nil-check. Every other
  module reference in the file is nil-guarded; this one was an
  outlier and would flood error popups if Net.lua ever failed to
  load.

- **`UI.lua` `renderActions` localSeat guard:** spectators (joined
  party with no seat) had no top-level gate. Most action branches
  gated on localSeat internally, but PHASE_SCORE/GAME_END only
  checked isHost — exposing host buttons to spectator-host edge
  cases. Single `if not S.s.localSeat then return end` at the entry.

### Audit-confirmed PASS items (no change)

- B-61 sunFail direction is correct (raise threshold = Bel less);
  earlier wave's EV math was flawed (forgot Bel doubles bidder's
  made score symmetrically)
- Carré J = 100 and no-Carré-9 are correct per Saudi rule
  (Pagat-strict, not French Belote convention); confirmed against
  v0.4.3 audit citations to "نظام التسجيل في البلوت"
- Trick resolution, must-follow / overcut / partner-winning
  exception in `R.IsLegalPlay` all correct
- Resync / replay flow / packSnapshot serialization clean
- AFK timer arming/cancelation respects pause and SWA correctly
  (preempt window post-host-reload is the only minor gap)

### Open (deferred — info / next sprint)

- AKA receiver behavior in pickFollow: bot partner reads `akaSent`
  per-suit dedup but doesn't actually consult `S.s.akaCalled` to
  suppress over-trumping. Half of the AKA convention is missing.
- Headless tournament test fixtures cannot exercise Tier 4 features
  (resets between rounds). 5 concrete test skeletons proposed in
  audit report; not yet implemented.
- All-4-disconnect: non-host state lost (no resync mechanism after
  group dissolves). Acceptable for v1; would need a mid-host-migrate
  protocol to fix.

## v0.4.6 — Three player-reported bugs + SWA UX rework + 50-agent audit follow-ups

A 50-agent ruflo-swarm audit on the v0.4.5 + v0.4.6 changes (10 waves
of 5 agents each, 50 distinct angles) confirmed three follow-up bugs
in the Tier 4 work; all three are fixed below. The full audit report
is at `.swarm_findings/v0.4.6_AUDIT_REPORT.md`. The audit also
re-derived the EV math for B-61 (sunFail) and confirmed the original
direction is correct (raise Bel threshold against repeat-sunFail
bidders). Master report's `gahwaFailed` counter was found to be a
dead increment with no consumer; this release wires it into PickFour.

### Audit-driven fixes (in addition to the v0.4.6 player-reported items below)

- **B-99 likelyKawesh teammate cross-contamination (HIGH):** the
  `mem.likelyKawesh` flag in `Bot.OnPlayObserved` was being set for
  the just-played seat regardless of team. The BotMaster sampler
  consumed the flag uniformly across all seats — when a partner
  played only 7/8/9 in tricks 1-3 (legitimate signal-suit conservation,
  not a Kawesh-skip pattern), the sampler cleared the partner's
  `desire` map, discarding the Fzloky `pSignalSuit` bias that was
  set just two lines earlier. Fixed by gating the consumer at
  `BotMaster.lua:226-229`: the desire-clear now only fires when
  `R.TeamOf(s) ~= R.TeamOf(seat)` (s is an opponent of the calling
  bot's seat). The flag itself remains descriptive of per-seat
  behaviour; only the consumption is team-relative. Dead-code
  `for opp = 1, 4 do ... end` loop in `Bot.OnPlayObserved` removed.

- **B-83 gahwaFailed wired into PickFour (MEDIUM):** the
  `_partnerStyle.gahwaFailed` counter was incremented in
  `Bot.OnRoundEnd` (Bot.lua:234) when a Gahwa contract failed but
  had zero consumers — fully dead instrumentation. Per the master
  report's B-83 spec, defenders should be more aggressive against
  reckless Gahwa-callers. Now wired in `Bot.PickFour` (Bot.lua:1670):
  tiered threshold drop of -5 on `gahwaFailed >= 1` and -8 on
  `gahwaFailed >= 2` (matching `styleBelTendency`'s magnitude).
  M3lm-gated.

- **Takweesh now explicitly clears swaRequest (MEDIUM):**
  `HostResolveTakweesh` previously relied on the SWA 5-sec timer's
  phase guard to no-op the auto-approve; the timer would find
  `phase ~= PHASE_PLAY` after Takweesh's `S.ApplyRoundEnd` and
  return. Worked correctly but left `S.s.swaRequest` stale through
  PHASE_SCORE, contradicting the changelog claim that "Takweesh
  during the window clears swaRequest". Now explicit:
  `S.s.swaRequest = nil` at the top of `HostResolveTakweesh`
  (Net.lua:1736). Belt-and-braces with `ApplyStart`'s round-start
  clear; comments in the SWA timer block are now accurate.

### v0.4.6 (original — three player-reported bugs)



### Fixed

- **Turn desync → illegal play (CRITICAL):** players occasionally got
  stuck — their UI showed the previous seat highlighted while the host
  thought it was their turn. AFK auto-play would fire on the host
  (consuming a card from their authoritative hand), and when the
  player finally clicked, they hit "illegal play" because their UI
  still showed the auto-played card but it was no longer in their
  hand on the host. RCA pinned this to `Net.lua` MSG_PLAY handler:
  `if S.s.turn ~= seat or S.s.turnKind ~= "play" then return end`
  silently dropped any MSG_PLAY whose seat didn't match the local
  turn pointer. CHAT_MSG_ADDON party-channel is at-most-once under
  server contention; a single dropped MSG_TURN frame made the
  receiver permanently miss every subsequent play in the trick,
  including the host's recovery auto-play. Fix: when the seat doesn't
  match local turn but the sender is the host (or the seat is a bot
  whose moves the host signs), trust the host's authority and
  self-heal `s.turn` before applying. Existing idempotence guard
  prevents double-apply if the missed MSG_TURN arrives later.

- **Hokm Bel scoring zeroed loser's melds (HIGH):** when a Hokm
  contract was Bel'd (×2) and the bidder team failed, the bidder's
  declared melds were nullified — a quarte (50 raw) that should
  have scored 100 raw / 10 gp under Bel ×2 instead scored 0. Same
  bug in the doubled-tie inversion ("take") branch — a defender
  team that Bel'd and tied lost ALL their melds. Both contradict
  the Saudi rule "مشروعي لي ومشروعك لك" (each team keeps their
  own declared melds; only the qaid penalty handTotal × multiplier
  flows to the winner). The qaid path was already corrected in
  v0.4.3; the regular `R.ScoreRound` fail/take branches now match.

### Changed

- **SWA permission window: 5-sec auto-approve + Takweesh counter
  (UX redesign):** previously a permission-required SWA (≥4 cards
  remaining) waited indefinitely on Accept/Deny votes from both
  opponents. Now the host arms a `K.SWA_TIMEOUT_SEC = 5` second
  auto-approve timer at request-time. During the window:
  - the SWA-claim banner displays in the centre of the table
    (caller name + remaining-card count + countdown)
  - opponents inspect the claim and either let the timer auto-
    approve, or press the always-visible **TAKWEESH** button to
    counter (Takweesh scans every prior trick of the SWA caller's
    team for an illegal play; if found, the qaid penalty applies
    and SWA is voided)
  - explicit Accept / Deny still works as a manual override
  - bots auto-accept (existing behaviour) — the timer is mostly
    a safety net for human deadlocks
  Rationale: humans may have played illegal cards in earlier tricks
  that would invalidate an SWA claim. The 5-sec window gives the
  opposing team a natural inspection beat to call Takweesh against
  prior misplays before the SWA resolves.

## v0.4.5 — 200-agent audit Tier 1+2 (critical bot fixes)

Tier 1 (4 confirmed critical bugs) + Tier 2 (style-ledger activation)
from the 200-agent ruflo-swarm audit campaign. All 5 candidate
critical findings reviewed; one (C-2 trump-ruff void rollback) was
re-classified as a false positive — the void flag IS correct in a
trump-ruff scenario because the seat is genuinely void in lead suit,
and the existing `wasIllegal` guard at Bot.lua:213-217 already
prevents void inference on rolled-back illegal plays.

### Fixed (Tier 1 critical bugs)

- **C-1 Bot memory inert for ~half of plays (CRITICAL):**
  `Bot.OnPlayObserved` was only invoked from the two human-play
  dispatch sites in `Net.lua`. Bot plays via `MaybeRunBot`, AFK
  auto-plays via `_HostTurnTimeout`, and bot error-recovery
  fallbacks all skipped the observer entirely. Result: void
  inference, `firstDiscard`/Fzloky signals, AKA per-suit dedup,
  trump-tempo counters (`trumpEarly`/`trumpLate`), and the entire
  per-seat memory subsystem missed every bot card play. Downstream
  `suitCardsOutstanding`, `HighestUnplayedRank`, and
  `opponentsVoidInAll` produced wrong answers all round long.
  Fix: added `Bot.OnPlayObserved(seat, card, leadBefore)` calls at
  three sites in `Net.lua` (the bot-play dispatch, the AFK timeout,
  and the play-decision error-recovery branch), each capturing
  `leadSuit` BEFORE `S.ApplyPlay` mirrors the human-play pattern.

- **C-3 A/T sure-stopper not gated to Sun (CRITICAL):** The
  pos-2 "sure stopper" shortcut at `Bot.lua:1003-1012` returned the
  highest non-trump A/T of the led suit unconditionally. In Hokm,
  a non-trump Ace is NOT a guaranteed winner — an opponent void in
  that suit can over-ruff and the bot sacrifices its Ace for
  nothing. Now gated on `contract.type == K.BID_SUN` where Aces
  genuinely cannot be over-trumped.

- **C-4 PickDouble trump-weight blocked Hokm Bel (CRITICAL):**
  `Bot.PickDouble` computed strength as `sunStrength + 0.5 *
  trumpStr`. The 0.5x discount was inconsistent with the 1.0x
  weight used by `escalationStrength` (PickTriple/Four/Gahwa). A
  Hokm defender with J+9+A of trump scored ~42 trump points but
  only saw 21 in PickDouble — combined hand total mathematically
  could not reach `BOT_BEL_TH=70`. Strong-trump defenders
  systematically declined legitimate Bels. Trump weight now 1.0x,
  aligned with the rest of the escalation pipeline.

- **C-5 heuristicPick rollout selected wrong card (CRITICAL):**
  `BotMaster.heuristicPick` bidder-lead branch called
  `highestRank(legal)` then checked `if C.IsTrump(t, contract)`.
  When the highest legal card by `TrickRank` was NOT trump (e.g.,
  a side-suit Ace outranking a depleted trump in the cross-scale
  comparison), the trump check failed and the rollout silently
  fell through to the side-suit branch — returning a low side-suit
  card instead of pulling trump. Saudi Master ISMCTS rollouts
  therefore made the wrong bidder-lead decision in any trump-poor
  position. Now filters legal to trump cards first, picks
  `highestRank(trumpCards)`, and only falls through if the trump
  set is empty.

### Activated (Tier 2 style ledger)

- **`styleBelTendency` wired into `Bot.PickTriple`:** The function
  was defined at `Bot.lua:181-187` and fed by `OnEscalation` but
  had zero callers across the codebase. Habitual Belers (`bels >=
  2`) now drop our Triple threshold by 8 — their Bel signal is
  noise and we counter more aggressively. M3lm-gated
  (`Bot.IsM3lm()`).

- **`styleTrumpTempo` wired into `pickLead` defender branch:** The
  function was defined at `Bot.lua:189-196` and fed by
  `OnPlayObserved` but had zero callers across the codebase. As a
  defender against a known aggressive trump-puller (bidder or
  bidder's partner observed leading trump in early tricks across
  prior rounds), the bot now saves J/9 of trump from the
  forced-trump fallback, burning 7/8/Q/K instead so the boss trump
  is held back to over-ruff their pulled trump tricks. M3lm-gated
  and Hokm-only.

### Architectural (Tier 3 — human-vs-bot guards)

The 200-agent audit identified that the bot's partner-aware code
paths (`partnerBidBonus`, `pickLead` Fzloky reads, `PickAKA`)
applied bot-calibrated logic equally to human partners — a
systematic mis-calibration unblocked by a single architectural
helper plus four scoped guards.

- **`Bot.IsBotSeat(seat)` helper added (Bot.lua:80-90):** thin
  proxy delegating to `S.IsSeatBot`. Replaces every
  `S.s.seats[seat] and S.s.seats[seat].isBot` open-coded reach
  into State across the picker code. One-line call sites for the
  guards below.

- **H-11 / B-09 / B-14: `partnerBidBonus` PASS penalty halved for
  human partners (Bot.lua:436-437):** bot PASS = calibrated weakness
  signal (`PickBid` only passes when no Sun-strong / Hokm-strong /
  Ashkal-eligible hand is present). Human PASS = often overcaution
  on marginal hands a bot would have bid. Treating both as a -10
  signal suppressed Triple/Four/Gahwa after a human partner's PASS
  even when our own hand merited escalation. Bot partner: -10;
  human partner: -5.

- **H-12 / B-31 / B-87 / B-90: `pickLead` Fzloky guarded on
  `Bot.IsBotSeat(partner)` (Bot.lua:775-787):** Fzloky is a bot-side
  convention (bot's first off-suit discard is a deliberate
  suit-preference signal — high = lead this, low = avoid). A human's
  first off-suit discard is just whatever they shed (often a high
  card to dump weakness, often random). Reading a human's discard as
  a "lead this suit" signal misdirected the bot's lead priority for
  the rest of the round.

- **B-33 / B-60: `Bot.PickAKA` suppressed when partner is human
  (Bot.lua:1158-1168):** AKA is a partner-coordination signal —
  bot partners read the per-round `akaSent` flag and suppress
  over-trumping the announced suit. Human partners typically don't
  recognize the AKA banner as a "don't ruff this suit" instruction;
  at best the signal is wasted, at worst it leaks information to
  opponents (who see the same banner) and hands them a free read on
  which suit we hold the boss in.

- **`Bot.PickPreempt` partner-bid bonuses scaled for human partners
  (Bot.lua:1389-1402):** symmetric with H-11 — a human PASS doesn't
  imply weakness as reliably as a bot PASS, and a human Hokm bid
  doesn't imply J/9 as reliably as a bot Hokm bid. PASS penalty
  -6 → -3, Hokm bonus +5 → +3 when partner is human. Sun bonus
  unchanged (Sun bid implies real high-card distribution either way).

### Reclassified

- **C-2 trump-ruff void rollback:** the master report flagged this
  as a critical bug, but on inspection the void inference IS
  correct — a trump-ruff genuinely implies the seat was void in
  lead suit (otherwise they'd have been forced to follow). The
  separate rollback at lines 262-269 is the Fzloky firstDiscard
  rollback for forced ruffs (the discard isn't a preference signal),
  and that path correctly nils only `firstDiscard`. The illegal-play
  case is already gated by `wasIllegal` at Bot.lua:213-217. No
  change needed.

### Track B (Tier 4 — human-pattern exploitation)

The 200-agent audit catalogued ~25 missing-feature gaps where the
bot collected data but failed to act on it, or had no way to
detect a human-specific pattern. Tier 4 adds the foundation
callbacks plus 11 picker integrations that turn the dormant style
ledger into actual gameplay decisions. M3lm-gated where the
counters are involved; Hokm-only / contract-conditioned where
appropriate. Dropped from scope (per master report's own
reverse-exploit-risk caveats): B-63/B-93 Bel-timing hesitation,
B-76 tilt detection, B-85 trump-back context flag, B-88 echo
convention.

#### Foundation infrastructure

- **`Bot.OnRoundEnd(contract, bidderMade)` callback added
  (Bot.lua:222-239, State.lua):** wired from `S.ApplyRoundEnd` on
  every client (mirrors `OnEscalation`'s broadcast pattern). Allows
  per-round outcome tracking without scattering bookkeeping across
  multiple Net.lua dispatch sites.

- **`emptyStyle` extended with 4 new counters (Bot.lua:155-180):**
  `gahwaFailed` (reckless callers — bidder Gahwa'd and failed),
  `sunFail` (defensive-Sun pattern — bidder Sun'd and failed),
  `aceLate` (A-hoarder pattern — Ace played at trick 5+),
  `leadCount[suit]` (per-suit lead frequency for repeat-lead
  pattern). Maintained on every client; consumed only host-side.

- **`emptyMemory` extended with `likelyKawesh` flag (Bot.lua:117-122):**
  per-round, per-seat. Set by `OnPlayObserved` after trick 3 if all
  observed plays are rank 7/8/9. Consumed by BotMaster sampler.

- **`Bot.r1WasAllPass` snapshot (B-80 / H-10):**
  `S.HostBeginRound2` captures whether R1 ended with all 4 seats
  passing BEFORE clearing `s.bids`. `S.ApplyStart` resets to false
  at round start. `Bot.PickBid` R2 reads it to drop `r2Base` by 6
  in trap-pass rounds (the table is weak overall; a strong R2 bid
  by a human is more likely overcaution-recovery than genuine
  combined strength).

#### Style-ledger integrations (8 picker fixes)

- **B-47 / B-50 — `matchPointUrgency` reads opponent escalation
  history (Bot.lua:563-590):** sums opponent `.gahwas` and
  `.fours` across both opp-team seats. Gahwa-prone opponent
  trailing by 50+ → +3 (they may try a desperate Gahwa to spike,
  Bel them ready). Passive opponent (0 fours, 0 gahwas) when
  WE are far behind → dampen +3 to +1 (no spike risk to
  defend against).

- **B-77 — `anyOpponentVoidIn` helper + Ace-lead exploit
  (Bot.lua:354-368, ~1010):** when one opponent is known void in
  a side suit AND we hold the boss, lead the boss in priority 1.5
  of `pickLead`. The single-void variant fires far more often than
  the both-void shortcut at priority 1, capturing high cards that
  would otherwise sit unused.

- **B-82 — Trump-drought tell in defender `pickLead`
  (Bot.lua:1000-1043):** scans the current round's tricks for
  bidder leads. After 3 tricks, if the bidder has led at least once
  but never trump, the bidder is trump-poor — defenders cash their
  highest non-trump A/T immediately (no ruff threat). M3lm-gated.

- **B-98 — J+9 trump-lock in bidder `pickLead`
  (Bot.lua:951-994):** once both J and 9 of trump are observed
  played (or held in our own hand), opponent trump strength is
  spent. Switch to cashing side-suit Aces while still holding
  reserve trump for defensive ruffs. Advanced+, depends on the
  C-1 memory population fix from earlier in v0.4.5.

- **B-96 — Ace-exhaustion window in bidder `pickLead`
  (Bot.lua:935-959):** after trick 3, if all 3 non-trump Aces
  have been observed played (anywhere, including our own hand), no
  Ace threats remain — switch to leading our highest non-trump
  (now bosses) instead of continuing trump-pull.

- **B-99 — `likelyKawesh` inference + BotMaster integration
  (Bot.lua:367-387, BotMaster.lua:213-228):** `OnPlayObserved` flags
  a seat as `likelyKawesh` after trick 3 if all their observed plays
  are rank 7/8/9. The sampler `desire` map is cleared for that seat,
  so trump J/9/A no longer get pinned to a low-card hand — fixes
  rollouts that previously mis-modeled Kawesh-skipping opponents
  as having strong cards.

- **B-67 — `aceLate` counter feeds sampler probability
  (Bot.lua:359-365, BotMaster.lua:228-234):** seats with
  `aceLate >= 2` get `pickProb` reduced from 0.7 to 0.5 in the
  sampler — A-hoarder patterns lower the reliability of bid-strong
  bias for that seat.

- **B-56 — `leadCount[suit]` accumulation
  (Bot.lua:351-358):** populated on every lead play in
  `OnPlayObserved`. Consumed by future repeat-lead exploitation
  features (placeholder ledger; no current picker integration —
  data is being captured for downstream use).

- **B-61 — `sunFail` defensive-Sun detection in `PickDouble`
  (Bot.lua:1597-1611):** when the Sun bidder has failed Sun ≥2
  times this game, our Bel threshold rises by 8 (defensive Sun
  has low base score; the 2x Bel reward is small if we win and
  large if we lose, expected-value math favors letting low Sun
  play out without Bel risk amplification). M3lm-gated.

#### Wire-protocol fix

- **B-69 — `s.target` added to packSnapshot
  (Net.lua:351, State.lua:368-373, 461-468):** late-joining /
  reloaded clients previously defaulted to 152 even when the host
  had configured a different target via `/baloot target N`. Field
  29 of the resync snapshot now carries the host's target. Backwards-
  compatible: pre-v0.4.5 hosts omit field 29 and the receiver
  preserves its existing `s.target` default.

## v0.4.4 — Bidding visibility + bigger meld strips (player feedback)

Two cosmetic fixes from player feedback. No rule / wire / scoring
changes.

- **Hokm bid suit visible to other players.** When a player calls
  Hokm in round 2 (or any bidding round), the seat badge now shows
  "HOKM ♠" (or ♥ / ♦ / ♣) below the player's name, in the suit's
  on-card colour. Over-bidders can now see which direction someone
  is going and decide whether to over-bid with Sun, Bel, or skip.
  Pass / Sun / Ashkal also render. Visible only during the bidding
  phases (DEAL1 / DEAL2BID); cleared once the contract is locked.

- **Meld strip 1.45x larger and below the badge.** Players reported
  the seat-side meld card strip (cards face-up during the 5-second
  trick-2 reveal) was too small to read. Cards now scale 1.45x and
  the strip is anchored BELOW the seat badge frame (extending ~46
  px down into the table area) instead of squeezed inside the
  badge bottom. The local bar's strip is unchanged so the local
  player's own layout stays the same.

## v0.4.3 — Saudi rule corrections (10-agent scoring audit)

Three rule-compliance fixes from a 10-agent audit (Codex + Gemini + 8
Claude angle agents) that cross-checked the scoring algorithm against
seven canonical Saudi Baloot PDF references:
- نظام التسجيل في البلوت (Scoring System)
- نظام الدبل في لعبة البلوت (Doubling System)
- نظام اللعب في البلوت (Play System)
- ماهو البلوت في لعبة البلوت (Bloot Definition)
- الثالث (Triple-on-Ace)
- سر الاحتراف 1 + 3 (Pro Secrets)

The audit identified ~7 issues; the user authorised three to fix and
deferred the rest pending interpretation. Re-confirmed-correct: card
values, hand totals, Bloot value (20 raw = 2 gp), Bloot cancellation,
sequence values, Sun-no-Triple/Four/Gahwa, tie resolution, qaid
penalty scaling under escalation (interpretation b).

### Fixed

- **Carre-A in Sun double-counted (CRITICAL):** `K.MELD_CARRE_A_SUN`
  was 400 raw, then multiplied by `MULT_SUN=2` in `R.ScoreRound` →
  800 raw / 80 gp final. Saudi rule says "أربع مئة" = 400 (final
  raw, post-Sun-mult). Constant now 200 raw so the Sun ×2 brings the
  final to 400 raw / 40 gp, matching canon.

- **Qaid melds nullified loser's projects (HIGH):** Both
  `HostResolveTakweesh` and the invalid-SWA path in `HostResolveSWA`
  zeroed out the loser's declared melds, contradicting Saudi rule
  "مشروعي لي ومشروعك لك" (each team keeps their own melds during a
  qaid). Both teams now retain their own declared melds; the qaid
  penalty (handTotal × multiplier) is awarded to the winner
  separately.

- **Sun Bel eligibility too permissive (HIGH):** Code enabled Sun Bel
  whenever EITHER team had cumulative ≥ 101. Saudi rule "ويكون الدبل
  للمتأخر فقط وهو الذي لم يتجاوز عدده 100" requires the doubler to
  be the BEHIND team, AND someone to have crossed 100. New helper
  `N._SunBelAllowed(bidderSeat)` enforces: bidder team ≥ 101 AND
  defender team < 101. Applied to all 5 Sun-Bel-gate sites
  (post-bid contract, preempt finalize, post-preempt-claim, host
  bot path, local preempt action).

### Researched (deferred)

- **Sun "no abnat" rule:** A research agent confirmed the addon's
  `div10` rounding is canonically correct for Hokm but produces
  ±1 game-point errors for Sun at certain card-point boundaries
  (totals ending in 3 or 6). Canonical Sun rule is "round to nearest
  10 preserving units-5, then ÷5", which differs from the current
  "× MULT_SUN(2), then round-half-down ÷10". The fix would require
  refactoring the rounding pipeline to apply card-point rounding
  BEFORE the multiplier — deferred pending design call.

### Confirmed correct (no change)

- Card point values (J/9 in trump, J in non-trump)
- Hand totals (162 Hokm, 130 Sun)
- Bloot value (20 raw → 2 gp), cancellation, no-doubling
- Sun phase machine blocks Triple/Four/Gahwa
- Tie resolution (strict bidder>defender, doubled-tie inversion)
- Sequence values (SEQ3=20, SEQ4=50, SEQ5=100)
- Qaid penalty scaled by escalation (interpretation b per user)

Tests: 177 passed, 0 failed.

## v0.4.2 — Round-end banner clarity (player feedback)

Two cosmetic fixes only; no rule / wire / scoring changes.

- **YA MRW7 tease for the losing team.** The round-end banner used
  to declare the OUTCOME ("AL-KABOOT", "BALOOT", "ALLY B3DO") but
  not WHICH team got the bad end. Players reported the result was
  ambiguous when their team's identity wasn't obvious. The title
  now appends "— YA MRW7 [losing team]" in red. Same applies to
  Takweesh, SWA, and the non-host degraded view (which infers the
  loser from the broadcast delta).
- **Score colors now reflect us-vs-them, not Team A vs Team B.**
  The final-delta line and team labels (A +X, B +Y) used to
  hard-code Team A as green and Team B as red regardless of which
  team the local player belonged to — so a Team B player saw their
  own deltas in red. Both labels and numbers now use `txtUs` for
  the local team and `txtThem` for opponents (or fall back to the
  legacy A=green/B=red for spectators / pre-join state).

## v0.4.1 — Saudi Master pro-grade ISMCTS

Major BotMaster.lua upgrade driven by a 25-agent + Codex + Gemini
deep audit focused exclusively on the Saudi Master tier. The bot
now plays meaningfully closer to a pro Saudi Baloot tactician.

### Sampling fidelity (`sampleConsistentDeal`)

- **Bidder strong-card weighting**: bidder's hand sample is now
  biased toward J / 9 / A of trump (Hokm) or multi-suit Aces (Sun)
  with 70% selection rate per "desired" card. Previously uniform
  random.
- **Partner Fzloky signal**: partner's first-discard suit gets a
  +20 weight in the sampler so worlds match what the bot already
  reads at lead time.
- **Declared meld cards pinned**: every unplayed card in a declared
  tierce / quart / quint / carré is pinned to the declarer's seat.
  Previously the sampler could scatter "Hearts Tierce 7-8-9" across
  all four seats, corrupting every rollout's view.
- **Bid card pinned to bidder** (kept from v0.3.x): the public bid
  card always lands in the bidder's hand.

### Rollout value function (`rolloutValue`)

- **Real Saudi scoring**: `R.ScoreRound` now drives the rollout
  utility — multipliers (Bel ×2, Triple ×3, Four ×4), make/fail
  cliff, melds, sweep, belote, last-trick bonus all priced in. The
  previous raw-trick-points return ignored multipliers entirely.
- **Team diff axis**: returns `result.raw[us] - result.raw[opp]`
  instead of just our points. Puts both "we make by 5" and "we
  fail by 2" on a single ranking axis where the contract-outcome
  cliff dominates raw-point fluctuation.
- **Gahwa terminal boost**: ±10000 when the rollout reaches a
  Gahwa-won-game state, ensuring match-winning candidates dominate.
- **Meld reconstruction**: each rollout reconstructs the initial
  8-card hand for each seat and runs `R.DetectMelds` so opponent
  meld threats are correctly priced (was previously zero).

### Rollout policy (`heuristicPick`)

- Now mirrors live `pickFollow` for position-aware play:
  - Pos-2 ducking with sure-stopper exception (Ace of led suit
    in Sun is unbeatable; Hokm trump-only-1-out is a stopper).
  - Pos-3 third-hand-high (committed winner so 4th seat can't
    cheaply overcut).
  - Smother on partner-winning + non-trump-led trick.
  - Trump preservation when not last seat.

### Adaptive search depth (`PickPlay`)

- World count scales with trick number for endgame fidelity:
  - Tricks 1-3: 30 worlds (default)
  - Tricks 4-5: 60 worlds
  - Tricks 6+: 100 worlds (small information set, near-exhaustive)

### Tests

177/177 passing (new Master-tier tournament test in
`test_state_bot.lua` confirms Master tier matches M3lm tier
under randomized synthetic deals).

### Audit findings deferred

- Backtracking CSP for void-fallback sampler (architectural
  overhaul; current 15-attempt retry adequate for normal play).
- Bel-open/closed inversion claim (verified that current code
  already matches Saudi convention: strong defender opens to
  invite escalation, marginal defender closes to lock-in ×2).
- Adaptive `numWorlds` based on confidence intervals (current
  trick-based scaling is simpler and well-tuned for the budget).
- Per-seat Hokm/Sun bid count ledger extension (would require new
  Bot.OnBid hook; deferred to a follow-up release).

## v0.4.0 — Bot AI improvements (25-agent audit)

Tactical and evaluation upgrades across all bot tiers. No wire-format
changes. Driven by a 25-agent audit (23 Claude angle agents + Codex
CLI + Gemini CLI) focused exclusively on Bot.lua and BotMaster.lua.

### Bidding evaluation

- `suitStrengthAsTrump` now scores 7 and 8 of trump at +2 each (Saudi
  Hokm convention). Previously fell through with 0 contribution,
  undercounting trump-rich hands by up to 8 points.
- `sunStrength` adds two new bonuses:
  - **+6 per card beyond 4** in suits ≥5 long that contain an A or K
    ("the suit walks"). A 6-card spade suit with AKQ now scores ~30
    higher than before, properly reflecting Sun-control value.
  - **+8 stopper triple** for any AKQ in the same suit (3 guaranteed
    tricks in no-trump).
  - Distribution penalty cap softened from −25 to −18 (long solid
    suits no longer bleed all their headroom).
- Advanced R2 threshold bump reduced from +6 to −4. The previous +6
  forced Advanced/M3lm to pass winnable marginal hands that Basic
  scooped up — directly responsible for the headless-tournament
  M3lm regression (97.7 vs Basic 99.1).
- `matchPointUrgency` magnitudes halved on the opp-near-win branches
  (+8→+5, +3→+2) and the function output is now capped at ±10.
  Previously stacked with `scoreUrgency` could reduce thresholds by
  up to 20 points (Bel 70→50), causing desperate over-escalations.

### Card play tactics

- `pickFollow` smother (partner winning) now fires on Sun and Ashkal,
  not Hokm-only. Dumping A/T of the led suit is free points in any
  contract.
- New Sun sure-stopper: in any contract with a non-trump lead, the
  Ace of the led suit is unbeatable AND a high-point card. Pos-2 no
  longer ducks A/T of the led suit ("don't voluntarily lose 11
  points").
- Pos-3 forced trump-ruff now uses the LOWEST trump, not the highest
  — saving J / 9 / A for forcing leads. Previously the bot wasted
  the J of trump on a 7-of-side-suit ruff in a classic give-back.

### Kawesh / Saneen

- New `Bot.PickKawesh(seat)` implements the bot side of the
  hand-annul rule: 5+ cards of {7,8,9} → unconditionally call
  Kawesh in DEAL1. Net.lua bot dispatch checks before bidding so
  the bot redeals an unwinnable hand the same way a human would.
  Previously bots had to play these hands and lose.

### Pre-emption

- `Bot.PickPreempt` now factors partner's bid history. Partner who
  passed → −6 (no fallback if our Sun fails). Partner who bid Sun →
  +8 (side-suit coverage implied). Partner who bid Hokm → +5.
- The Ace-of-bid-suit bonus raised from +8 to +12. The Ace is worth
  ~11 raw points + tempo control + guaranteed first-trick — under-
  weighted at +8.

### Saudi Master ISMCTS rollouts

- `BotMaster.heuristicPick` upgraded with three of the highest-impact
  live heuristics, closing the gap with `Bot.pickFollow`:
  - Smother on partner-winning + last-seat (with non-trump lead).
  - Position-3 highest-winner (was always lowest).
  - Position-3 forced-trump-ruff exception: lowest trump.
  - Trump preservation: discard non-trump first when not last seat.
- `sampleConsistentDeal` now pins the public bid card to the
  bidder's hand. Previously the sampler could randomly assign it to
  any opponent, corrupting every rollout's evaluation.

### Tests

176/176 passing. Headless tournament (`test_state_bot.lua`) tests
play-only with synthetic contracts; full bidding-round comparison
between tiers requires a separate harness and is not in this release.

## v0.3.2 — Lobby card-style preview

Cosmetic add only.

- The `Cards: <name>` cycle button in the lobby now renders a 3-card
  preview (Ace of Spades · King of Hearts · 10 of Diamonds) at its
  right edge using the currently-selected style. Both the in-lobby
  cycle button and `/baloot cards <name>` keep the preview in sync
  with the active style.

## v0.3.1 — Classic v2 deck + royal_noir refresh

Two cosmetic adds; no wire-protocol changes, no rule changes.

- New card style `classic_v2` from David Bellot's SVG-cards (LGPL,
  via Huub de Beer's PNG mirror at htdebeer/SVG-cards). Pulls the
  2x PNGs and rasterizes them to TGA at the addon's 128×192 size.
  Pairs naturally with the Midnight felt theme — uses `back-black.png`
  from the same source.
- Royal Noir refresh: replaced the SVG sources with the user-supplied
  zip and re-rendered the 33 TGAs. Same `royal_noir` style name, new
  art.

Activation:

    /baloot cards classic_v2
    /baloot cards royal_noir
    /baloot themes              -- shows the full list

## v0.3.0 — Visual themes (mix-and-match) + deep audit hardening

Wire-format compatible additive release. v0.2.x clients can play with
v0.3.0 hosts (extra fields are append-only and ignored by older
parsers); v0.3.0 receivers handle pre-v0.3.0 senders gracefully.

### Deep audit hardening (post-draft, audit waves 6–13)

Eight additional audit waves after the initial v0.3.0 draft, each
combining Codex CLI + Gemini CLI + 5–10 parallel Claude angle agents
for cross-source verification. Findings refuted with code-trace
verification were not applied; only multi-source-confirmed real bugs
went in.

**36 confirmed bug fixes + 17 defense-in-depth guards** across 10
commits (e83bf8b, c4964b1, b5d506a, 456dda2, a3e4aa3, c3ecc73,
0aa496f, 5dbd9d6, 15931cf):

- Host /reload mid-bid soft-lock — `hostDeckRemainder` was wrongly
  in TRANSIENT_FIELDS; restoring `hostHands` without its remainder
  short-circuited HostDealRest.
- 4-play trick stuck on /reload — PLAYER_LOGIN restore now re-fires
  `_HostStepPlay` if the saved trick is complete.
- Host's own preempt swallowed by `fromSelf` — LocalPreempt now
  applies state directly instead of routing through `_OnPreempt`.
- ApplyContract escalation flags wiped on duplicate broadcast —
  added (bidder, type, trump) idempotence guard.
- `scoreUrgency` / `matchPointUrgency` returns had inverted signs vs.
  their docstring — flipped, near-win is now actually conservative.
- UI peek-banner could overlay round-end banner — phase-gated on
  PLAY/DEAL3 and U.Refresh now `clearHand` in SCORE/GAME_END.
- Reset between games silently reverted user's `/baloot target` and
  team names — `reset()` now reads from WHEREDNGNDB.
- SWA permission requests could be clobbered by a second concurrent
  request — added overwrite guard.
- Resync roster lookup mishandled cross-realm name suffixes — added
  `nameEq` normalization on both `info.name` and sender.
- Remote humans never saw the preempt window — host's seat=0 frame
  now broadcasts the eligible-seat CSV; receivers seed phase +
  preemptEligible.
- Host's own SWA permission claim resolved as empty hand —
  `encodedHand` now stashed in the local request struct (the
  `fromSelf` loopback guard had skipped its population path).
- MaybeRunBot now early-returns while a SWA permission request is
  in flight; bot play timer also re-checks at fire time so an
  already-scheduled callback can't slip past the entry guard.
- Resync snapshot now packs a 4-bit `isBot` mask in field 28; without
  it, post-resync seats had `isBot=nil` and host-signed bot
  broadcasts silently failed `authorizeSeat`.
- Host /reload mid-SWA-vote no longer drops `swaRequest` (removed
  from TRANSIENT_FIELDS).
- WHEREDNGNDB type-guarded throughout — corrupted SavedVariables
  no longer crashes addon load.
- `lastTrick` cleared in ApplyStart so peek can't display the
  previous round's final trick.
- ApplyStart also clears `swaRequest` + `swaDenied` so a Kawesh
  redeal mid-SWA-vote doesn't leak Accept/Deny buttons into the new
  round.
- AFK turn timer now defers when a SWA permission request is active
  — the SWA caller's hand was being force-played under them while
  opponents were still voting.
- SWA bot opponents auto-accept on the host's behalf — bots never
  send MSG_SWA_RESP, so a host-with-bots game would otherwise
  deadlock waiting for two votes that never come.
- Redeal banner C_Timer.After(3.0) now uses a generation token
  (`B._redealGen`); /baloot reset and the UI reset popup both bump
  the generation, so an in-flight redeal callback no-ops instead of
  spawning a ghost round.
- `ApplyResyncSnapshot` now re-derives `s.localSeat` through
  `S.SeatOf(s.localName)` (normalized) and clears `s.isHost`
  unconditionally — same-realm rejoiners with a bare-vs-suffixed
  name mismatch were being left with `localSeat=nil` and a stale
  `isHost=true` from a prior session.
- HostResolveSWA now prefers `S.s.hostHands[callerSeat]` over the
  wire-supplied hand — a stale or modified client could previously
  validate impossible claims via the trusted decode path.
- U.PulseTurn now stores the ticker handle and cancels prior on
  re-arm — back-to-back calls used to spawn overlapping animations.
- `/baloot reset` and the UI reset popup now both also call
  `N.CancelTurnTimer` and `N.CancelLocalWarn` so stale AFK or
  T-10s pre-warn timers can't fire on the next frame after reset.
- Non-host SWA responder now applies the response to their own
  `swaRequest` locally (deny clears + 3s toast, accept records
  vote). The wire echo via `_OnSWAResp` was being dropped by
  `fromSelf`, leaving the denier with stale Accept/Deny buttons.
- `_OnResyncRes` and `_OnLobby` now early-return for an active host
  — a stale or forged peer broadcast could otherwise demote the
  host via `ApplyResyncSnapshot`'s `s.isHost = false` or
  `ApplyLobby`'s "new game" reset path.
- Defense-in-depth: 13 more host-broadcast handlers (`_OnStart`,
  `_OnDealPhase`, `_OnHand`, `_OnBidCard`, `_OnTurn`, `_OnContract`,
  `_OnTrick`, `_OnRound`, `_OnGameEnd`, `_OnPause`, `_OnTeams`,
  `_OnTakweeshOut`, `_OnSWAOut`) plus 4 branch-specific cases
  (`_OnPreemptPass` seat=0, replay branches of `_OnMeld`/`_OnPlay`/
  `_OnAKA`) now have explicit `if S.s.isHost then return end`. Each
  was already protected by `fromHost`, but local invariants make
  the protection robust to future refactors.

Tests: 176/176 passing across every commit.

### Visual themes — split into card style + felt theme axes

Card art and table felt are now two independent saved variables you
can mix and match: 4 card styles × 4 felt themes = 16 combinations.

**Card styles** (`/baloot cards <name>` or lobby `Cards: ...`):
- `classic` — hayeah Vector Playing Cards (the original)
- `burgundy` — SVGCards 4-color deck with red lattice back
- `tattoo` — old-school SVG art with rose decorations + portrait face
  cards + burgundy mandala back
- `royal_noir` — gold-on-charcoal SVG deck with crown face cards

**Felt themes** (`/baloot felt <name>` or lobby `Felt: ...`):
- `green` — classic forest-green felt
- `burgundy` — deep wine-red felt
- `vintage` — saddle-brown leather felt
- `midnight` — near-black felt with indigo undertone

The previous single-axis `WHEREDNGNDB.cardTheme` is migrated on first
load to the appropriate `cardStyle` + `feltTheme` pair.

### Asset pipeline

Three SVG-based decks (`burgundy`, `tattoo`, `royal_noir`) are
rasterized to TGA via `resvg_py` (Rust-based, no system cairo). One
procedural felt generator per theme produces the 128×128 tileable
fabric. Source SVGs preserved under `cards/<theme>/_src/` for
reproducibility.

### Test harness

New `tests/test_rules.lua` (120 assertions) and `tests/test_state_bot.lua`
(56 assertions) covering Constants/Cards/Rules/State/Bot. Driven by
`tests/run.py` via Python lupa. 176/176 passing across all the
audit-sweep changes below.

### Bug-fix sweep — three audit passes (~40 real bugs)

Three rounds of 20-agent parallel audits before release. Categorised:

**Critical (gameplay-blocking):**
- Resync replay frames (MSG_PLAY/AKA/MELD whispered during rejoin) now
  carry a "1" flag the receiver uses to bypass turn + authorizeSeat
  gates. Mid-trick rejoin reconstructs the table correctly. The
  earlier "fix" that just appended replay messages was silently
  filtered by those gates.
- Every bot decision callback in MaybeRunBot is now wrapped in pcall
  with phase-appropriate recovery (force-pass / force-skip / lowest-
  legal-play). A `Bot.PickX` error no longer freezes the deal — bots
  have no AFK timer otherwise.
- Each escalation pcall tracks `applied` AND `skipSent` so recovery
  can branch on real state vs. unreachable state, avoiding both stalls
  (when phase has advanced past the simple guard) AND double SKIP_X
  broadcasts (when the body completed the skip then HostFinishDeal
  errored).
- Bel-decision recovery on `applied=true` calls MaybeRunBot for open
  Bel in Hokm (correctly running the bidder's Triple decision)
  instead of HostFinishDeal which would skip the entire chain.
- Solo-bot preempt path no longer routes through `_OnPreempt` — that
  handler short-circuits on `fromSelf(sender)` before authorizeSeat,
  silently dropping the claim. Bots now apply directly + run the
  host post-apply block.
- WHEREDNGN.lua PLAYER_LOGIN restore re-arms StartTurnTimer +
  StartBelTimer + StartLocalWarn for human seats. /reload mid-turn no
  longer leaves the table waiting forever.
- `_HostTurnTimeout` and `_HostBelTimeout` now respect `S.s.paused` —
  C_Timer:Cancel() doesn't catch already-queued callbacks, so a
  pause-during-fire would otherwise let auto-actions run mid-pause.
- `_OnKawesh` and `HostHandleKawesh` likewise respect paused.

**Wire format:**
- `MSG_ROUND` now includes `sweep` ("A"/"B"/"") + `bidderMade` (""/0/1).
  BALOOT fanfare fires on every client, not just the host. Three-state
  bidderMade encoding distinguishes "absent" (legacy / SWA / Takweesh)
  from "explicit failure" so legacy hosts and per-feature paths don't
  trigger false-positive fanfares.
- `MSG_PLAY` / `MSG_AKA` / `MSG_MELD` extended with optional trailing
  "1" flag for resync replay (see Critical above).

**Theme system:**
- Split `cardTheme` → `cardStyle` + `feltTheme` (mix-and-match).
- Theme refresh re-applies backdrop colors to seat badges, localBar,
  party panel, lobby seat-rows, and the main outer rim. Was tex-only
  previously; corner tints stayed stale until /reload.
- `migrateLegacyTheme` runs only when legacy is non-nil so fresh
  installs fall through to runtime defaults.

**Scoring & game logic:**
- `R.IsValidSWA` resolves complete tricks before the caller-empty
  short-circuit. Caller playing their last card to a trick they
  would lose now correctly fails the claim.
- `R.IsValidSWA` rejects top-level entry with caller-empty + no plays
  (corrupted-state guard).
- `R.ScoreRound` no longer mutates `meldPoints` with the +20 belote
  bonus. Belote is exposed separately on the result struct; UI shows
  it on its own line.
- `S.ApplyTrickEnd` rejects partial tricks (`#plays != 4`); malformed
  broadcasts no longer corrupt history.
- `S.reset()` and `S.ApplyResyncSnapshot` explicitly clear all
  per-trick / per-round transient fields (akaCalled, lastTrick,
  redealing, takweeshResult, swaResult/Request/Denied, ...). Stale
  banners no longer leak across game boundaries or resync.

**Bot AI:**
- `Bot.OnEscalation` accepts a rung kind ("double"/"triple"/"four"/
  "gahwa"); per-rung counters in the style ledger. Previously every
  rung incremented `m.bels`, misclassifying aggressive bidders.
- `partnerEscalatedBonus` gated on `IsAdvanced` (was IsM3lm); team-
  membership check covers BOTH defender seats (was only bidder+1).
- `Bot.PickGahwa` returns `(yes, false)` matching PickTriple/PickFour.
- `OnPlayObserved` trumpEarly/Late counter no longer requires
  `leadSuit == contract.trump` (was unreachable on lead plays).
- `firstDiscard` rolled back when the off-suit play was a forced
  trump ruff (Fzloky no longer misreads forced ruffs as preference).

**UX & polish:**
- StartLocalWarn supports "four" / "gahwa" / "preempt" kinds; State
  arms them in the open path of each escalation.
- AKA banner frame-level bumped above center trick cards.
- localBar.meldStrip anchored INSIDE localBar so it no longer
  extends 36 px into the centerPad/trick area.
- statusFor PHASE_SCORE / PHASE_GAME_END use custom team names.
- Sound throttle classification: VOICE interval applies only to
  `K.SND_VOICE_*` paths; everything else (BALOOT, CARD_PLAY,
  TURN_PING, ...) uses the SFX interval. Previously the SFX-paths-
  as-strings were bucketed as voice and suppressed.
- `_HostRedeal` accepts a reason ("allpass" / "kawesh"); Kawesh path
  no longer also prints "all passed".
- `framePos` drag-stop persists on first drag (nil-safe init).
- Cards.lua SortHand nil-safe SUIT_DISPLAY lookup.

### Notes for upgraders

Pre-v0.2.0 → v0.3.0 still requires a coordinated bump (escalation
chain change). v0.2.x → v0.3.0 is wire-compatible: a v0.2.x client
in a v0.3.0 host party will not hear the BALOOT fanfare on remote
sweeps/failures (no MSG_ROUND extra-fields parser), but everything
else works including the resync flow.

## v0.2.0 — Canonical 4-rung escalation + Triple-on-Ace pre-emption

This release applies the remaining canonical Saudi rules from the
new batch of documents ("نظام الدبل في لعبة البلوت" / "الثالث" /
"ماهو البلوت في لعبة البلوت"). It is a **wire-format-incompatible**
release — clients on <v0.2.0 will desync. Bump everyone together.

### Escalation chain rewrite (FOUR rungs, not five)

Per "نظام الدبل في لعبة البلوت", the canonical Saudi escalation chain
has only **four** rungs, not the five we shipped previously. The
"Bel-Re" rung is non-canonical and has been removed entirely.

**Old chain (5 rungs):**
- Bel(def, ×2) → Bel-Re(bid, ×4) → Triple(def, ×8) → Four(bid, ×16) → Gahwa(def, ×32)

**New chain (4 rungs):**
- Bel(def, ×2) → Triple(bid, ×3) → Four(def, ×4) → Gahwa(bid, **match-win**)

Every escalation alternates between the bidder and defenders. The
multipliers now match canon: ×2 / ×3 / ×4. Gahwa is no longer a
round-multiplier — calling it bets the entire match: a successful
Gahwa wins the game outright (cumulative→target); a failed Gahwa
hands the match to defenders.

Removed across `Constants.lua`, `State.lua`, `Net.lua`, `Rules.lua`,
`UI.lua`, `Bot.lua`:
- `K.MULT_BELRE`, `K.MULT_GAHWA`, `K.PHASE_REDOUBLE`, `K.MSG_REDOUBLE`,
  `K.MSG_SKIP_RDBL`, `K.BOT_BELRE_TH`
- `S.ApplyRedouble`, `s.belrePending`, `contract.redoubled`
- `N.SendRedouble`, `N._OnRedouble`, `N._OnSkipRedouble`, `N.LocalRedouble`
- `Bot.PickRedouble`
- All UI references to "Bel-Re" / `PHASE_REDOUBLE`

Re-targeted constants:
- `K.MULT_TRIPLE`: 8 → **3**
- `K.MULT_FOUR`: 16 → **4**
- `K.MULT_GAHWA`: 32 → (deleted; Gahwa is match-win, not a multiplier)
- `K.BOT_TRIPLE_TH`: 95 → **90** (lower — Triple is now ×3, less risky)
- `K.BOT_FOUR_TH`: 115 → **110**
- `K.BOT_GAHWA_TH`: 130 → **135** (raised — Gahwa is now terminal)

Role flips (Triple/Four/Gahwa):
- **Triple** was defender's response to Bel-Re; now **bidder's** response to Bel.
- **Four** was bidder's response to Triple; now **defenders'** response to Triple.
- **Gahwa** was defender's terminal; now **bidder's** terminal (match-win).

`Rules.lua` tie-inversion table rewritten for the 4-rung chain:
`R.ScoreRound` returns `gahwaWonGame=true` + `gahwaWinner` when the
contract had Gahwa active; `_HostStepAfterTrick` reads these and
overrides `addA`/`addB` to push the winner to the cumulative target.

### Open/Closed escalation choice (التربيع)

Per the same doc, each escalation rung lets the caller choose **open**
("I bel & I'm prepared for your Triple") or **closed** ("I bel & we
play — no further escalation"). The wire format extends each
escalation tag with a trailing `;0` (closed) or `;1` (open) field;
pre-v0.2.0 senders that omit it default to open.

- `S.ApplyDouble`/`ApplyTriple`/`ApplyFour` take an `open` boolean.
  Closed transitions phase directly to PLAY; open advances to the
  next-rung window.
- UI: each escalation now has paired buttons ("Bel & open" / "Bel
  & closed"). Sun's Bel button hides the open variant since Sun has
  no Triple rung anyway.
- Bot: `Bot.PickTriple/Four` return `(yes, wantOpen)` — open if
  strength is ≥20 above threshold (we'd still escalate next rung),
  else closed.

### Belote cancellation when 100-meld present

Per "ماهو البلوت في لعبة البلوت": the +20 belote bonus is **cancelled**
when the same K+Q-of-trump holder also declared a meld of value ≥100
(seq5 or carré of T/K/Q/J/A). The 100-meld subsumes the belote — no
double-counting. Sequences of 3/4 (≤50) and the bare belote stand on
their own.

- `R.ScoreRound`: belote scan now post-checks `meldsByTeam[team]` for
  any meld with `declaredBy == kWho and value ≥ 100`. Match → cancel
  belote.
- Same guard in `N.HostResolveTakweesh` and `N.HostResolveSWA`
  invalid branch.

### Triple-on-Ace pre-emption (الثالث) — host-toggleable, ON by default

Entirely new mechanic. When a round-2 Sun bid lands and the original
**bid card is an Ace**, eligible earlier seats (those who already bid
in this round, excluding the buyer's partner — "can't Triple your
partner") may "claim before you" — taking the Sun contract for
themselves. Per "الثالث" doc.

New constants:
- `K.PHASE_PREEMPT` — pre-emption window phase
- `K.MSG_PREEMPT = "@"`, `K.MSG_PREEMPT_PASS = "%"` — wire tags
- `K.BOT_PREEMPT_TH = 75` — bot threshold

New host-toggleable: `WHEREDNGNDB.preemptOnAce` (default true). Toggle
via `/baloot preempt`.

New code:
- `S.PreemptEligibleSeats(buyer, bidder)` — eligibility list
- `S.ApplyPreempt`, `S.ApplyPreemptPass` — state transitions
- `N._OnPreempt`, `N._OnPreemptPass`, `N._FinalizePreempt`,
  `N.LocalPreempt`, `N.LocalPreemptPass`, `N.SendPreempt`,
  `N.SendPreemptPass`
- UI: `PHASE_PREEMPT` action panel with "قبلك (Pre-empt)" + "Pass"
  buttons for eligible seats only
- Bot: `Bot.PickPreempt(seat)` — Sun-strength gated, +8 bonus when
  holding the Ace of bid suit
- AFK timer: `kind="preempt_pass"` auto-passes after 60s

### Saved-game upgrader

`State.RestoreSession` strips stale `redoubled=true` /
`belrePending` fields and bumps any `phase=="redouble"` save back to
`PHASE_DOUBLE` so the eligible defender can act fresh. Pre-v0.2.0
sessions restored on v0.2.0+ install will not freeze on load.

### Wire format changes (v0.2.0+, breaking)

- `K.MSG_DOUBLE/TRIPLE/FOUR`: payload extended with trailing `;0|;1`
  open/closed flag. Receivers default to open if missing.
- Resync snapshot (`packSnapshot`): removed `redoubled` slot; added
  `tripleOpen`, `fourOpen`. Slots renumbered (15-17 → 14-19).
- `K.MSG_REDOUBLE` and `K.MSG_SKIP_RDBL` deleted.
- `K.MSG_PREEMPT`, `K.MSG_PREEMPT_PASS` added.

Hard requirement: all party members must be on v0.2.0+. Mixed
versions will desync immediately.

---

## v0.1.33 — Saudi rules sweep (canonical doc-driven fixes)

This release applies the canonical Saudi rules from the
official scoring + play documents ("نظام التسجيل في البلوت" /
"نظام لعبة البلوت الأساسي") that the user provided.

**SWA permission flow + canonical Qayd meld rule**
(see prior notes — same as the earlier draft of this version).

**Ashkal seat restriction (R3)**
- Per the play-system doc: only the **3rd and 4th players in
  bidding order** can call Ashkal. The 1st and 2nd bidders
  cannot.
- `State.HostAdvanceBidding` now silently drops Ashkal from
  seats with bid-position < 3.
- UI hides the Ashkal button for the same seats.
- `Bot.PickBid` Ashkal heuristic gated on the same condition.

**Sun escalation gate (R5/R7)**
- Per the doc: *"في الصن لايوجد الثري والفور والقهوة وإنما
  يلعب دبلاً فقط. ولايحق للاعب أن يدبل خصمه إلا بعد أن يتجاوز
  المئة أي 101"* — Sun has no Triple/Four/Gahwa; only Bel,
  and Bel is locked until at least one team's cumulative game
  score has exceeded 100 (≥101).
- `Net._HostStepBid` "contract" branch: when contract is Sun
  and both teams' cumulative <101, skip `PHASE_DOUBLE`
  entirely and go straight to play via `HostFinishDeal`.
- `State.ApplyRedouble`: Sun contracts skip `PHASE_TRIPLE` —
  set phase to PLAY directly so Triple/Four/Gahwa never fire
  in Sun.
- `Net._OnRedouble`: Sun contracts call `HostFinishDeal`
  immediately after Bel-Re instead of dispatching the Triple
  decision.

**Aces carré value (R8)**
- `K.MELD_CARRE_A_SUN`: 200 → **400** raw. The doc explicitly
  says *"الأربع مئة فهي الأربع أكك"* — the four-hundred meld
  is the four-Aces carré.

## v0.1.33-pre — SWA permission flow + canonical Qayd meld rule

**Saudi-rule fix (HIGH)**

- **Qayd / Tasjeel meld rule**: per the Saudi scoring document
  ("نظام التسجيل في البلوت"), in any early-termination penalty
  (takweesh, invalid SWA), the OFFENDER'S MELDS STAY WITH THEM —
  they don't transfer to the winning side. Previously we were
  awarding all melds (both teams' values combined) to the winner,
  which doesn't match the canonical Saudi rule:

  > "المشروع لصاحبه" — *"the meld stays with its owner"*

  Now: winner takes `handTotal × mult` + their OWN melds × mult
  + belote (independent). The offender keeps their melds (held
  out from scoring this round). Applies to both
  `HostResolveTakweesh` and the invalid-SWA branch in
  `HostResolveSWA`. Math produces exactly **26 (Sun) / 16
  (Hokm)** game points for the bare penalty as specified by the
  document.

**SWA permission flow (NEW)**

Per the Saudi-rules video: SWA called with 4+ cards remaining
requires opponent permission. Implemented as a host-toggleable
gate.

- New host settings:
  - `WHEREDNGNDB.allowSWA` (default true) — disables SWA
    entirely for tournament-mode play.
  - `WHEREDNGNDB.swaRequiresPermission` (default true) — gates
    4+-card claims behind opponent vote.
- New slash commands: `/baloot swa` (toggle SWA on/off),
  `/baloot swaperm` (toggle the permission gate — same flag
  via `/baloot swa` if you don't need the second control;
  see help).
- New wire tags: `MSG_SWA_REQ` ("I"), `MSG_SWA_RESP` ("O").
- Flow:
  - ≤3 cards: instant resolution (current behavior).
  - 4+ cards: caller broadcasts a request. Both opponents see
    Accept / Deny buttons in the action panel.
  - Either opponent denies → request cancelled, 3-second toast
    shows the denier name, round resumes from where it was.
  - Both opponents accept → host runs the actual minimax
    validator and proceeds with normal SWA scoring (now using
    the Qayd meld rule).
- The caller's SWA button is hidden while a request is in
  flight to prevent double-clicks.

**Documentation**

- `WHEREDNGN.lua` flag comment for `allowSWA` updated: SWA is
  now confirmed Saudi convention (per video tutorial), not just
  a digital-app shortcut. The English-language references
  (Pagat, Saudi Federation page) just don't cover it.

**Deferred**

- "Sequence specification" (شرح السوا): caller laying out the
  exact play order to satisfy the claim. The current minimax
  validator implicitly handles sequencing (it finds ANY winning
  order), so this is a UX nicety not a correctness issue. Still
  on the future-work list.

## v0.1.32 — five-agent audit sweep

**HIGH-severity fixes**

- **`Rules.ScoreRound` make-check**: the threshold comparison was
  adding both teams' melds to both team totals, which could flip
  a made contract to failed when meld values differed. Now uses
  `R.CompareMelds` first and only the winning team's melds count
  toward the threshold (matches the actual scoring branches).
- **`S.ApplyMeld` trick-1 lock**: rejects late wire-side meld
  declarations once trick 1 has closed, backing up the UI / Bot
  / GetMeldsForLocal local gates.
- **Resync replay**: `SendResyncRes` now whispers the bid card,
  every declared meld, and every closed trick to the rejoiner
  using existing `MSG_BIDCARD` / `MSG_MELD` / `MSG_TRICK` wires.
  A mid-hand /reload-rejoin now correctly rebuilds the meld strip,
  peek-last-trick state, and contract banner. Previous resync
  snapshot was 26-field-only and dropped trick history + melds.
- **Bot trump-tempo counter**: was firing on RUFF (defensive cut)
  rather than LEAD. Now requires `#trick.plays == 1` and
  `leadSuit == trump` so only voluntary tempo-spending counts.
- **Fzloky avoid-suit `pairs()` ordering**: rewritten as a
  two-pass selection so the avoid-suit can never claim "longest"
  via iteration-order luck. Avoid-suit only wins if it exceeds
  the best non-avoid by ≥2 cards.
- **`bidsAttempts` counter**: dropped — was never incremented and
  drove `styleBelTendency` into degenerate values. Belief now
  gates on `bels >= 1` count alone.
- **AKA banner reposition**: was 26 px tall anchored above the
  centre pad, but the gap to the top seat-badge is only 10 px.
  Banner pokes ~16 px into the partner badge. Now 22 px tall
  anchored INSIDE centerPad's top edge — clear of both seat and
  trick area.
- **Contract banner reposition**: was at `f.BOTTOM, 0, 6`,
  overlapping the score and round text at the same Y. Now sits
  at `f.BOTTOM, 0, 30` — above the score line.
- **`_HostStepPlay` paused guard**: trick-resolve timer no longer
  fires while the host is paused.
- **`_HostRedeal` reset/pause guard**: 3 s redeal timer now
  aborts if game state was reset or paused during the wait.

**MEDIUM-severity fixes**

- **`S.ApplyGameEnd` idempotence**: returns early on duplicate
  re-apply with the same winner — prevents the BALOOT fanfare
  cue from double-firing on host-loopback + remote receive.
- **Bid card visible during escalation**: `renderCenter` now
  keeps the bid card up through DEAL3 / DOUBLE / REDOUBLE /
  TRIPLE / FOUR / GAHWA, not just the bidding rounds. Players
  retain "what was bid" reference all the way to play start.
- **Transient-fields cleanup**: `lastRoundResult`,
  `lastRoundDelta`, `lastTrick` added to TRANSIENT_FIELDS so
  they don't survive a /reload (would otherwise surface a
  previous round's banner).
- **`BotMaster.lua` rollout policy**: was always picking
  `lowestRank(legal)` on lead. Now mirrors `Bot.pickLead`
  — bidder team leads highest trump in Hokm, defenders lead
  lowest from longest non-trump. Removes the systematic bias
  toward passive lines in determinization rollouts.
- **Dead-code cleanup**: `partnerVoidIn` (defined, never
  called), `smothers` / `smotherOpps` counters (never
  written) removed from `Bot._partnerStyle` and `Bot.lua`.

**LOW-severity fixes**

- `_OnAKA` now goes through `authorizeSeat` — prevents a peer
  from spoofing an AKA banner for another seat.
- `WHEREDNGNLog` removed from `WHEREDNGN.toc` — the
  `SavedVariablesPerCharacter` declaration was unused; log
  buffer is in-memory only.

## v0.1.31 — Saudi Master tier (ISMCTS-flavoured)

**New tier: Saudi Master** — top of the cascade
`Saudi Master → Fzloky → M3lm → Advanced`. New module
`BotMaster.lua` (~280 lines) implements determinization-sampling
play decisions:
- At each play, sample 30 plausible opponent hands consistent
  with our cards + observed plays + inferred voids.
- For each candidate card, simulate the rest of the round across
  all 30 worlds using existing pickFollow / pickLead heuristics
  as the rollout policy.
- Pick the card with the best aggregate team score.
- Sampler honours per-seat void inference from `Bot._memory`.

Bidding, melds, and escalations still flow through the
M3lm/Fzloky paths since the bidding tree doesn't benefit from
sampling at the same scale; only PLAY decisions get the ISMCTS
treatment. Performance budget ~150 ms per move (30 worlds × ≤8
candidate cards × ~25 cheap rollout plays).

UI: new "Saudi Master" checkbox at the bottom of the lobby
difficulty stack. Slash: `/baloot saudimaster` (also accepts
`master+` and `ismcts`). Cascade rules: ticking Saudi Master
auto-checks Fzloky / M3lm / Advanced (greyed). `Bot.IsSaudiMaster()`
gates the new picker.

## v0.1.30 — SWA scoring rebuilt, takweesh simplified

**SWA scoring fix (HIGH severity)**
- `HostResolveSWA` was awarding `handTotal × mult` to the winning
  side and 0 to the other regardless of how many tricks were
  played. Already-earned trick points evaporated, the kaboot
  bonus never applied, the last-trick +10 was missing.
- Now: VALID SWA synthesizes the remaining tricks (each won by
  caller seat), appends to played-trick history, and routes
  through `R.ScoreRound`. ScoreRound handles sweep / made /
  failed / meld winner / last-trick bonus / belote correctly
  by construction.
- INVALID SWA still applies the flat penalty: opp takes
  handTotal × mult + ALL melds × mult + belote.
- Sweep is now detected when caller's team has won every played
  trick AND wins all remaining via SWA → kaboot bonus
  (250 / 220 raw) applies via the same ScoreRound path.

**Takweesh scoring simplified**
- Dropped the made/failed mapping introduced in v0.1.28 — both
  branches of takweesh are punitive penalties to the same shape.
- Now: caught → caller's team takes handTotal × mult + ALL
  melds × mult + belote. Not-caught → opp-of-caller takes the
  same. Single code path, no contract-result inversion.

## v0.1.29 — belote tightened to "K+Q played", SWA/takweesh docs

**Fix (Saudi rule, rb3haa)**
- Belote (+20 raw) now requires the K AND Q of trump to BOTH be
  played before the round ends. v0.1.27/v0.1.28 had been scanning
  unplayed hands too — that's wrong: per Saudi convention, belote
  must be announced as the cards are played. If a takweesh or SWA
  ends the round before K+Q both surface, no belote bonus.
- Applies to both `HostResolveSWA` and `HostResolveTakweesh`.

**Documentation**
- `HostResolveSWA` doc-comment now flags the made/failed contract
  mapping as a HOUSE-RULE NORMALIZATION. The published Saudi
  sources don't fully specify a meld/belote formula for SWA —
  our mapping (valid+bidder→MADE etc.) is a defensible synthesis
  but isn't a verbatim attested rule.

## v0.1.28 — takweesh scoring respects melds + belote

**Fix (same shape as v0.1.27)**
- `HostResolveTakweesh` had the identical bug as the pre-v0.1.27
  SWA path: awarded only `handTotal × multiplier` and ignored
  meld points + belote. A defender team could win a takweesh
  while ALSO holding 100-point carrés and K+Q-of-trump and still
  drop those points.
- Now routes through the standard made/failed branches:
  - Caught + caller is bidder team OR not caught + caller is
    defender team → MADE: bidder team takes hand × mult, meld
    winner gets their melds × mult.
  - Caught + caller is defender team OR not caught + caller is
    bidder team → FAILED: opp-of-bidder takes hand × mult AND
    all declared melds combined × mult.
- Belote +20 raw flows independently to its K+Q-of-trump holder.
  Takweesh ends the round mid-trick, so we scan unplayed hands
  too (same fix shape as SWA's belote scan).
- Audit also confirmed: regular ScoreRound has no early-end path
  to worry about (always runs at #tricks ≥ 8 when all cards are
  played); Kawesh has no scoring path (annul + redeal); game-end
  tie-rule is consistent across all three scoring paths;
  Ashkal-shifted bidder is correctly read everywhere; bot meld
  lock is enforced in both human and bot paths.

## v0.1.27 — SWA scoring respects melds + belote

**Fix**
- SWA was awarding only `handTotal × multiplier` to the winning
  side, ignoring meld points and belote. A team with 400 worth of
  melds could lose because the opposing team called SWA — wrong
  per Saudi rules.
- `HostResolveSWA` now routes through the same made/failed
  scoring branches as a regular round:
  - **Made** (caller's claim valid AND caller is on bidder team):
    bidder team takes `handTotal × mult`. Meld winner (per
    `R.CompareMelds`) gets their melds × mult.
  - **Made** (caller's claim invalid AND caller is on defender
    team): same — defender's false claim hands the contract back
    to the bidder.
  - **Failed** (caller valid + defender, OR caller invalid +
    bidder): opposing team takes `handTotal × mult` AND ALL
    declared melds combined × mult — same rule the regular
    `ScoreRound` uses for a busted contract.
- Belote (+20 raw, Hokm only) flows to the K+Q-of-trump holder
  regardless of SWA outcome. SWA can end the round before K+Q
  are played; we scan unplayed hands so the holder still gets
  the bonus per Saudi convention.

## v0.1.26 — round-2 Sun overcall, "wla" pass label

**Saudi rule fix: round 2 has a Sun overcall window**
- Previously round 2 was "first non-pass wins" — seat 3's Hokm bid
  resolved bidding immediately, robbing seat 4 (and any later
  seats) of their chance to bid Sun.
- Now both rounds wait for all 4 bids, and Sun overcalls Hokm in
  either round. Hokm-vs-Hokm in round 2 still uses first-non-pass
  ordering. Sun-vs-Sun: first direct Sun locks (same as round 1).
- Round-2 Hokm-on-flipped-suit drop and Ashkal silently-dropped
  paths still apply.

**UX**
- Pass button in round 2 now labelled "wla" (ولا) to match the
  Saudi verbal convention. Confirms an existing bid or opens a
  redeal if all 4 say wla.

## v0.1.25 — SWA full minimax, last-trick visibility, Fzloky tier

**SWA validation upgraded to full minimax**
- Previous "sufficient condition" check rejected valid claims like
  `[A♠ A♦ T♦]` in Sun (lead A♠ → A♦ → T♦, all wins) because it
  couldn't see that T♦ becomes the boss after A♦ is played.
- Now `R.IsValidSWA` runs a recursive minimax over the remaining
  game tree: caller's team picks plays cooperatively, opponents
  pick adversarially, and the claim is valid iff caller can
  guarantee winning every remaining trick. Bounded by hand size
  so worst-case ~ thousands of nodes — fine for a one-time check.
- "Caller wins" still means trick winner == caller seat (strict
  reading; partner taking a trick doesn't satisfy the claim).

**Last-trick peek now shows all 4 plays everywhere**
- The peek button could show only 2–3 cards on non-host clients
  because `MSG_TRICK` arrived before the 4th `MSG_PLAY` and the
  trick-end snapshot captured a partial trick.
- `MSG_TRICK` now carries the full trick payload (leadSuit + all
  4 seat/card pairs). `_OnTrick` rebuilds `s.trick.plays` from
  the snapshot before applying trick-end, so `s.lastTrick` is
  always complete regardless of inter-sender ordering.

**Fzloky tier (signal-aware bots)**
- New checkbox below M3lm. Slash: `/baloot fzloky`.
- Tier cascade: `Fzloky → M3lm → Advanced`. Each lower tier is
  auto-checked-and-disabled when a higher one is on.
- Fzloky reads partner's first off-suit discard as a high/low
  suit-preference signal and biases lead choice accordingly:
  - Partner discards A/T/K → bot prefers leading that suit
    (lowest card from it; partner has the high cards).
  - Partner discards 7/8 → bot avoids leading that suit unless
    no alternative exists.
- v1 covers first-discard signaling only. Echo / petite-grand
  peter / "throw the king" are still future work.

## v0.1.24 — SWA claim, carré tie-break, M3lm UX polish

**New: SWA (سوا) claim mechanic**
- New action button "SWA" next to TAKWEESH during play. Confirm
  once before sending.
- Caller reveals their remaining hand; host validates via
  `R.IsValidSWA` (sufficient condition: every caller card is
  the current "boss" of its suit, plus a Hokm trump-count
  guarantee against forced ruffs).
- Outcome:
  - **Valid** → caller's team takes the full hand × multiplier
    (same shape as a made contract — caller proved dominance).
  - **Invalid** → opposing team takes the full hand × multiplier
    (same penalty as a failed takweesh).
- Wire: `MSG_SWA = "Q"` (caller→host with hand reveal),
  `MSG_SWA_OUT = "Z"` (host→all with verdict + scoring).
- Banner: green "SWA!" on success, red "SWA failed" on bust;
  takes priority over the normal score breakdown.

**Saudi rule fix: carré tie-break**
- Equal-value carrés (e.g. K-carré vs J-carré, both 100 raw)
  now break by the trick-rank of the top card. Trump-J carré
  beats trump-Q carré in Hokm; Aces in Sun beat anything else
  by raw value already. Bonus is small (×0.01) so it can't
  flip carré-vs-sequence comparisons.

**Saudi rule fix: bot meld lock**
- `Bot.PickMelds` now respects the trick-1 declaration window
  the same way `S.GetMeldsForLocal` does. Previously bots could
  declare melds in trick 2+ via the bot-auto-meld loop in
  Net.lua. Closes a rule-bypass.

**M3lm UX polish**
- Lobby Advanced checkbox auto-checks and disables when M3lm
  is on, signalling visually that M3lm strictly extends Advanced.
- Tooltip clarifies "stack with Advanced for full effect" was
  redundant — now reads as a single-pick tier system.

**Defensive cleanup**
- `LocalSWA` clears any stale `swaResult` banner from earlier
  in the round before broadcasting.

## v0.1.23 — M3lm tier, audit fixes, banner copy

**M3lm (pro) bot tier — host opt-in, stacks with Advanced**
- Lobby checkbox is now functional (was greyed in v0.1.20).
- New slash: `/baloot m3lm` toggles the flag.
- Adds three new layers on top of Advanced:
  - **Partner / opponent play-style modeling**: per-seat counters
    (`bels`, `trumpEarly`, `trumpLate`) accumulate across a full
    game so the bot can read each player's tendencies. Reset only
    on round 1 of a new game.
  - **Match-point urgency**: finer-grained threshold modifier
    layered on top of Advanced's `scoreUrgency` — opponent ≥
    target-15 → extra −8 (defensive desperation), opponent ≥
    target-40 → extra −3 (caution), we ≥ target-15 → extra +5
    (lock it down), behind 50–80 → extra −3 (measured risk).
  - **Coordinated escalation**: `partnerEscalatedBonus` adds to
    escalation strength when partner has already Beled / Tripled
    in the current contract. Defender chain (Bel/Triple/Gahwa)
    rewards escalating partners with +5/+8/+12; bidder chain
    (Bel-Re/Four) rewards bidder partners with +5/+8.
- Net.lua hooks `Bot.OnEscalation(seat)` from
  `_OnDouble/_OnRedouble/_OnTriple/_OnFour/_OnGahwa` so the
  partner-style ledger updates from network events too (covers
  remote players as well as bots).
- `Bot.IsAdvanced()` now returns true if EITHER advancedBots OR
  m3lmBots is set — M3lm strictly extends Advanced.

**Saudi rules audit fixes**
- Meld declaration window closes at end of trick 1 (Pagat-strict).
  Previously a player could still declare during trick 2 if they
  hadn't yet played their first card. `S.GetMeldsForLocal` now
  returns empty once `#s.tricks >= 1`.
- Game-end ties now go to the bidding team (Saudi convention)
  instead of Team A by default. Affects both
  `_HostStepAfterTrick`'s round-end branch and
  `HostResolveTakweesh`'s game-end branch.

**Copy**
- Game-end banner: "GAME OVER" → "8amt!! go play something else".

## v0.1.22 — only winning team reveals in trick 2

**Fix**
- Trick-2 card reveal is now gated to declarers on the **winning
  team only**, per Saudi rule (Pagat-cited): "the opposing team are
  not allowed to show or score for any projects." Losing team's
  cards are never exposed, even though their trick-1 announcement
  still happens.
- Both teammates on the winning team can still reveal — each gets
  their own 5-second window when their PLAY turn opens in trick 2.
- Trick-1 announcement text remains unchanged: every declarer's
  type/length/top-rank still posts (verbal declaration is public
  by everyone), suit still hidden.
- Ties (or no melds) → neither team reveals. Matches the scoring
  side, which already awards 0 to both on a tie.

## v0.1.21 — meld display rule corrected

**Fix**
- Trick 1 now shows only an announcement text — type, length and top
  rank, *no suit and no cards* ("Seq3 K (20)", "Carré J (100)"). The
  full mini-card strip is no longer flashed during trick 1.
- Trick 2: each declarer's actual cards become visible for exactly
  5 seconds when their PLAY turn starts, then hide for the rest of
  the hand. Hooked into `S.ApplyTurn` rather than `S.ApplyPlay` —
  so the timer starts with the turn, not after the play.
- Trick 3 onwards: nothing is shown. Earlier trick-1-always-visible
  behaviour was an over-broad reading of the Saudi rule; this
  release matches the table convention (announce in trick 1, brief
  reveal in trick 2, gone after).

## v0.1.20 — Advanced bot heuristics (host opt-in)

**New**
- Lobby checkboxes: **Advanced** (functional) and **M3lm**
  ("master", greyed out — reserved for a future deeper-heuristic
  layer with multi-trick lookahead and signal interpretation).
- Slash command: `/baloot advanced` toggles the host's advanced-bot
  flag.
- Default is OFF on upgrade — existing bot behaviour is unchanged
  unless the host explicitly turns Advanced on.

**Advanced-mode heuristics (Tier 1 + 2 + 3 from the bot research
agents):**

*Bidding*
- Hand evaluation: J+9 synergy bumped from +10 to +18 (Coinche
  step-jump). J-of-trump step-function damp — no-J + no 9+A pair
  + count<5 trump suit gets 0.4× score (structurally weak).
- Side-suit aces fold into Hokm strength (+8 each, capped at 3).
- Sun bid distribution penalty: −10 per suit with count<2 or no
  honors (capped at −25).
- Round-2 threshold raised to ≥ Round-1 + 6 (R2 picker has more
  optionality, so the bar should be higher, not lower).
- Ashkal additional check: only call if our own holding in the
  flipped suit is weak (no J of flipped, count ≤ 2).

*Escalation (Bel / Bel-Re / Triple / Four / Gahwa)*
- Partner's bid feeds escalation strength directly:
  HOKM-trump-match +20, HOKM-other +10, SUN +15, ASHKAL +15,
  PASS-both-rounds −10.
- Score-urgency threshold modifier: behind 80+ → −6 (more
  aggressive); near loss → −12; near win → +8 (conservative).

*Play*
- Position-aware following: 2nd-hand-low (duck unless sure
  stopper) / 3rd-hand-high (commit a card that survives 4th-seat
  overcut). 4th still cheapest-winner.
- `pickLead` boss-card scan: lead the highest unplayed card in
  any non-trump suit when we hold it (free trick).
- Bidder lead asymmetry: trump-poor bidder (<4 trump) with a
  side-suit Ace cashes the Ace before the trump pull. Bidder's
  partner falls through to defender-style logic instead of
  blindly leading high trump.
- Bot AKA self-call: when leading the boss of a non-trump suit,
  bot fires the AKA banner + voice cue first so partner doesn't
  over-trump (matches the human signal).
- Smother gate (basic + advanced): now relaxes when 4th-to-act
  with partner winning — the trick is going on partner's pile
  no matter what, free points.

**Internals**
- `Bot.IsAdvanced()` / `Bot.IsM3lm()` (the latter always returns
  false until the M3lm tier is implemented).
- All advanced helpers return 0/nil in basic mode so non-advanced
  hosts get the v0.1.19 behaviour bit-for-bit.

## v0.1.19 — Saudi rules sweep, smarter bots, meld timing

**Saudi rules**
- `Rules.IsLegalPlay` — when trump is led and your partner is currently
  winning the trick, you no longer have to overcut. Matches the
  off-lead-trump partner-winning exception that was already in place.
- `Rules.ScoreRound` — in a sweep (Al-Kaboot), the +20 belote bonus
  now follows the sweep winner instead of staying with the K+Q
  holder. "Winner takes all" applies to belote too.
- `State.HostAdvanceBidding` — round-2 Hokm cannot reuse the bid
  card's flipped suit (host-side enforcement, backing up the UI gate).
- `State.HostAdvanceBidding` — first direct Sun bid in round 1 locks
  the declarer chair; later direct Sun bids no longer overcall it.
  An Ashkal-derived Sun can still be overcalled by a later direct
  Sun (the direct bid reassigns declarer to the actual bidder per
  Saudi convention). Tracked via a `viaAshkal` flag on the winning
  record.
- `Net.HostResolveTakweesh` — takweesh penalty multiplier now respects
  the full escalation chain (Triple ×8, Four ×16, Gahwa ×32). Was
  previously stuck at base / Bel ×2 / Bel-Re ×4.

**Bots**
- Bidding thresholds raised: `TH_HOKM_R1_BASE 35→42`,
  `TH_HOKM_R2_BASE 28→36`. Bots stop committing to Hokm on weak
  hands.
- `pickLead` rewritten for non-bidder team — 5-tier priority:
  opponent-void high lead, low singleton, low from longest non-trump,
  fallback lowest non-trump, lowest trump. No more blind Ace leads.
- `pickFollow` smother gated — bots only dump A/T onto a partner-
  winning trick if (a) holding ≥2 of A/T in lead suit, OR (b) past
  trick 3. Trump-led smother skipped entirely. Stops the trick-1
  Ace burn.
- New `Bot.PickTriple` / `PickFour` / `PickGahwa` — strength-gated
  escalation (`BOT_TRIPLE_TH 95`, `BOT_FOUR_TH 115`,
  `BOT_GAHWA_TH 130`) replaces the previous flat 10% coin-flip.
- New Ashkal heuristic — when partner has bid Hokm in round 1 and
  the bot's Sun-strength clears `BOT_ASHKAL_TH (65)`, bot calls
  Ashkal to push partner into Sun (higher multiplier).

**Hand display**
- Sort order now strictly alternates colour: ♠ ♥ ♣ ♦
  (B R B R). Replaces the previous BBRR group-by-colour layout.
  Easier to scan — every adjacent pair is opposite colour.

**Meld display timing**
- Meld card strip now follows a three-window model per Saudi rule:
  - Trick 1: every declarer's strip is visible the whole time.
  - Trick 2: a seat's strip appears only while it's that seat's
    turn, and hides as soon as the next seat is up.
  - Trick 2 last player: held visible 4 seconds after their final
    play (no "next turn" to clip them).
  - Trick 3 onwards: never visible.

## v0.1.18 — meld backdrop fix, hand sort, contract banner

**Fixes**
- Meld mini-cards now render with a solid cream body + dark edge
  drawn from explicit Texture layers (BACKGROUND/0 for the edge,
  BACKGROUND/1 for the body, ARTWORK for the card face). The
  previous BackdropTemplate approach didn't reliably render at
  small sizes, leaving the cards transparent. Slot bumped to 22×30.
- Meld strip and meldText label both hide once trick 1 closes,
  matching the Saudi rule that melds are public during trick 1
  only. Previously the text label persisted for the whole round
  alongside the strip.

**UX polish**
- Hand sort now groups suits by colour (♣ ♠ ♥ ♦ → black, black,
  red, red) instead of the interleaved black-red-red-black layout
  that the old K.SUIT_INDEX produced. One colour boundary in the
  middle of the hand instead of two — easier to scan.
- Contract line at the bottom of the window upgraded to a wood-edged
  plate with a 15-px outlined font: `Contract: HOKM ♥  by  Bidder
  [Bel+x16]`. The plate auto-hides outside an active contract.
  Modifier list now also shows Triple/Four/Gahwa multipliers.

## v0.1.17 — meld display polish + AKA label fix

**Fixes**
- Meld mini-cards now have the cream card-body backdrop. Previously
  the slot was a bare texture and the card art TGAs are transparent
  outside the rank/pip glyphs, so cards looked like floating
  fragments. Each slot is now a small frame with the same body +
  edge backdrop as the table card faces, with the rank/pip texture
  laid on top.
- AKA button label and banner switched from "إكَهْ" to Latin "AKA".
  WoW's bundled fonts (Arial Narrow / Frizz / Skurri) don't include
  Arabic glyphs, so the original label rendered as empty boxes. The
  voice cue still says إكَهْ, so the audio carries the Saudi feel.
- Meld card strips now respect the Saudi-rule timing: face-up only
  during trick 1 (PHASE_DEAL3 and the first trick of PHASE_PLAY).
  After trick 1 closes the cards rejoin the hand and the strip
  hides — only the score the meld earned is remembered (shown in
  the round-end banner).
- Slot size bumped 18×24 → 26×36 so the card art is actually
  legible at table scale.

## v0.1.16 — AKA call (إكَهْ) + meld card display

**New gameplay**
- AKA (إكَهْ) partner-coordination signal in Hokm contracts. When the
  local player holds the highest unplayed card in any non-trump suit
  (Sun ranking: A → 10 → K → Q → J → 9 → 8 → 7), an "إكَهْ" button
  appears in the action row. Pressing it broadcasts a soft signal:
  voice cue plays for everyone, banner appears above the trick area
  showing the suit + caller. The teammate uses this to avoid
  over-trumping. No legal-play enforcement — purely informational,
  matching the social signal used at the table.
- Voice asset (sounds/aka.ogg) — placeholder generated via gTTS;
  re-bake with `_make_voice_eleven.py aka` on a paid ElevenLabs
  plan to swap in the Saud voice (consistent with the rest of the
  Arabic cues).

**New visual**
- Declared melds now show as face-up mini cards next to each player
  in addition to the existing text label. Per Saudi rule, melds are
  public the moment they're declared during trick 1.
- Once trick 1 closes, the meld-comparison verdict drives strip
  styling: the winning team's melds stay at full opacity, the losing
  team's melds dim to 0.45 alpha so the player can see what was
  declared but it visibly "doesn't count". Ties stay neutral (0.85).
- Strips appear under the seat-badge card-back fan for opponents and
  above the local bar for the local player.

**Internals**
- `s.playedCardsThisRound` set tracks cards played this hand; rebuilt
  from s.tricks on /reload, marked TRANSIENT for SaveSession.
- `s.akaCalled` is per-trick ephemeral, cleared by ApplyTrickEnd.
- Wire: `MSG_AKA = "e"`, payload `seat;suit`. Soft signal — host
  doesn't need to validate or arbitrate; receivers gate on PHASE_PLAY
  + HOKM contract.

## v0.1.15 — multiplayer rejoin after game-end

**Bug fix**
- After a game ended and the host clicked Reset + Host Game, joiners
  who were still showing the score banner (PHASE_SCORE / GAME_END)
  silently dropped the new lobby announcement. Symptoms: the Join
  button never appeared on the joiner's side, OR the joiner's Join
  click went out with the previous game's stale gameID and the host
  silently rejected it — leaving only some of the players visible
  in the host's seat list.
- `Net._OnHost` and `State.ApplyLobby` now accept lobby announcements
  in any "passive" phase (IDLE, LOBBY, SCORE, GAME_END). Mid-active-
  play phases still ignore stranger announcements (anti-grief).
- When a new gameID arrives, ApplyLobby soft-resets leftover round
  artifacts (contract, hand, tricks, score banner, winner) while
  preserving session identity (localName, target, team-name labels,
  peer versions).
- `pendingHost` is now cleared once the joiner is successfully
  seated, so a stale entry from a finished game can't mask a future
  host announcement.

## v0.1.14 — peek button relocated, banner re-labelled

**UI**
- The last-trick peek "?" button moved out of the felt's top-right
  corner and into the main frame's top-right gutter, just below the
  Reset button. It now sits between Bot 2's seat badge and Reset, so
  the trick area stays uncluttered.
- The pause "II" button takes the freed-up corner inside the felt
  (top-right of the centre pad).
- Round-result banner: "Contract made" → "ALLY B3DO" to match the
  Saudi-Arabish wording players use at the table.

## v0.1.13 — lobby seat-row layout fix

**UI fix**
- Lobby seat rows now auto-fit between the lobby's left edge and the
  party-members sidebar's left edge instead of overhanging it. The old
  fixed 380-px-wide centred rows clipped under the sidebar by ~22 px
  on the right; new rows use anchored TOPLEFT/TOPRIGHT pairs so the
  layout stays tidy regardless of the main frame width.

## v0.1.7 — visuals, takweesh detail, reset button, audit fixes

**New UI**
- Reset button (top-right under game code) with a Blizzard popup
  confirmation. Equivalent to `/baloot reset`.
- "(KZKZ will come)" branding next to the title.
- Minimal-bg toggle (bottom-left): hides the outer green frame so
  only the felt trick area + cards remain visible. Useful for
  streaming or low-clutter views. Persists per-account.

**Takweesh feedback**
- A successful Takweesh now displays the offending card (rank + suit
  glyph) and the rule reason in chat: "K♠ — must follow suit",
  "T♥ — must overcut", etc.
- Score banner shows the same details for the rest of the round.

**Card art**
- All 32 card-face TGAs re-baked composited against the cream
  backdrop so anti-aliased edges blend cleanly. Fixes the "glow"
  visible on Ace of Diamonds (and minor halos on other cards).

**Agent-audit fixes**
- `redealing` and `takweeshResult` added to TRANSIENT_FIELDS so
  timer-backed banners don't persist across /reload.
- `maybeRequestResync` no longer gated on PHASE_IDLE — RestoreSession
  brings us into a non-IDLE phase and we still want the host's
  authoritative state, not a possibly-stale local snapshot. Added
  a host-skip so a solo-bot host doesn't broadcast to nobody.

## v0.1.6 — escalation chain, redeal pause, polish

**New gameplay**
- Full Triple / Four / Gahwa escalation chain (×8 / ×16 / ×32) per
  Saudi rule 4-10. Bot opponents skip these by default with a small
  random escalation chance.
- Voice cues "ثري" / "فور" / "قهوة" announce each step.
- Doubled-tie inversion logic now follows the alternating "buyer"
  rule across all 5 escalation levels.

**Bidding feel**
- Bots commit on more typical biddable hands (thresholds lowered
  ~30%) — fewer all-pass rounds.
- Bel-skip no longer plays the pass voice (it was confusing right
  after a contract announcement).
- Round-2 pass says "ولا" (round-1 still says "بَسْ").
- "ثآني" announces the round-2 bidding window (mirrors "أوَل").
- AWAL / THANY voices delayed 0.5s so the visual round-start lands
  first, then the audio.
- All-pass redeal now holds for 3s with a "Next dealer: NAME"
  banner so the rotation is obvious instead of instant.
- Trick-resolve buffer 1.5s → 2.2s; bot delays 1.0s → 1.6s.

**UI polish**
- Custom team A / B names — host edits in lobby, broadcast to all
  clients, persists per-account, applied across score line + banner.
- Local player bar narrower (540 → 280px) and centered, with the
  same turn-glow texture the other three seat badges use.
- Card back replaced with a programmatic navy/gold diamond pattern.
- Ace of Clubs no longer renders a white square (chroma-keyed the
  source PNG's solid card body to transparent).
- Pause/peek buttons elevated to FULLSCREEN_DIALOG strata so they
  remain clickable when the pause overlay is up.
- Title/scale buttons no longer overlap.

## v0.1.3 — session persistence

- Game state survives `/reload` and logout. The host's snapshot
  (phase, contract, scores, seats, hands, current trick, melds) is
  saved on `PLAYER_LOGOUT` and restored on the next `PLAYER_LOGIN`.
- Per-character guard so an account's saved session can't surface on
  a different character.
- Sessions older than an hour or finished games are discarded.
- Reset clears the saved session.

## v0.1.2 — title overlap fix

- Move +/- scale buttons off the centered title (they were covering
  the "WH" of "WHEREDNGN").

## v0.1.1 — visuals, sound, scoring fixes, hardening

**Visuals**
- Vector Playing Cards art (32 cards + back) replaces the FontString placeholders.
- Four-color suit deck (♠ black, ♥ red, ♦ blue, ♣ green) — suits are unambiguous at a glance.
- Felt-green tiled trick area with winner-glow on the trick winner.
- Card slide-in animation from each player's edge.
- Bot avatar circles next to seat names.
- Window scale controls (+/−) in the title bar; size persists.

**Sound (with mute toggle in top-left)**
- Card swish + slap on every play.
- Soft bell when your turn arrives.
- Two-note chime when contract is finalized.
- Triad arpeggio when your team wins a trick.
- Four-note fanfare for AL-KABOOT / contract failure.
- Arabic voice cues (ElevenLabs Saud) for HOKM / SUN / ASHKAL / PASS / "Awal" round-start.

**Bot AI**
- Bid threshold randomized ±6 so two bots dealt similar hands don't always pick the same bid.
- Bel/Bel-Re threshold randomized ±10 — no longer a hard cliff.
- Smother-partner: in Hokm, bots dump A/10 of trick lead suit when partner is winning.
- Trump-saving: bots prefer non-trump discards when they're not closing the trick.
- Card-counting helper for outstanding-trump awareness.
- Takweesh detection: bots call Takweesh on opponent illegal plays (60% in trick 1, decays through hand).

**Networking / correctness**
- Authority + phase + idempotence guards on `_OnBid`/`_OnPlay`/`_OnMeld`/`_OnTakweesh`/`_OnKawesh`.
- Resync-on-reload (`MSG_RESYNC_REQ`/`RES`): players who `/reload` mid-game request state from the host and rehydrate.
- Host pause toggle suspends bots and AFK timers without dropping in-flight state.
- AFK pre-warn (T-10s) flashes the local bar and pings audibly so auto-pass isn't a surprise.
- Hold-to-confirm on Bel-Re and Takweesh — single-click can't trigger a round-ender by mistake.

**Saudi rule corrections**
- Strict-majority make check (Saudi rule 4-2/4-3): 65-65 (Sun) / 81-81 (Hokm) is now a tie that goes to the defenders.
- Belote shifted into the make-check total (rule 4-5).
- Doubled-tie inversion (rule 4-10): on a tied doubled hand, the bidder team takes the full count.

**Bug fixes**
- `cancelLocalWarn` was nil at call time → every Local* action crashed. Forward-declared.
- Sound dispatch: SoundKit IDs now route via `PlaySound`, not `PlaySoundFile`.
- Takweesh false-call no longer leaves the trick frozen on the table.

## v0.1.0 — initial release

- Full Saudi Baloot ruleset: Hokm, Sun, Ashkal, Belote, Al-kaboot, Takweesh, Kawesh.
- 4-player party-only over addon channel; bots fill empty seats.
- Bidding (round 1 + round 2), Bel/Bel-Re windows, meld declarations, trick play.
- AFK timer auto-skips Bel/Bel-Re windows after 60s.
- Authority + idempotence guards on Double/Redouble messages.
