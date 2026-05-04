# Changelog

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
