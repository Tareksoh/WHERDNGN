# Bot personalities — what distinguishes each tier

> **Stub — populate from YouTube transcripts and pro-vs-amateur
> contrasts.**

## What this file informs

- `Bot.IsAdvanced()` / `Bot.IsM3lm()` / `Bot.IsFzloky()` /
  `Bot.IsSaudiMaster()` — tier-gated branches throughout Bot.lua
- `BotMaster.PickPlay` — Saudi Master ISMCTS sampler
- `WHEREDNGNDB.advancedBots` / `m3lmBots` / `fzlokyBots` /
  `saudiMasterBots` — tier-flag config

---

## The 5 tiers (ordered weakest → strongest)

### Tier 1 — Basic
- **Behavior:** random legal play.
- **Bidding:** simple strength-threshold, no style reads.
- **Escalation:** never escalates; will accept bids passively.
- **Personality fit:** "complete beginner" / pickup-game opponent.

### Tier 2 — Advanced
- **Behavior:** heuristic picker with boss tracking and basic
  memory (which cards have been played).
- **Bidding:** Hokm/Sun thresholds, simple Ashkal logic.
- **Escalation:** baseline Bel/Bel-x2 thresholds; no style ledger.
- **Personality fit:** "casual player who knows the rules but
  doesn't read partner".

### Tier 3 — M3lm (معلم)
- **Behavior:** Advanced + style-ledger inference. Reads partner
  history (`triples`, `gahwaFailed`, `sunFail`).
- **Bidding:** adjusts Bel/Four thresholds based on opponent
  history.
- **Escalation:** detects bluff patterns; adjusts thresholds.
- **Personality fit:** "club regular who remembers your tells".

### Tier 4 — Fzloky (فضولكي)
- **Behavior:** M3lm + extended bid-reading and conservative
  rollouts.
- **Bidding:** stronger Sun-bid discrimination, finer Ashkal.
- **Escalation:** sub-Bel reads (e.g., closed-Bel vs open-Bel).
- **Personality fit:** "studious player; knows the playbook but
  isn't a tactical master".

### Tier 5 — Saudi Master
- **Behavior:** Fzloky + ISMCTS determinization sampling
  (`BotMaster.PickPlay`). 100/60/30 worlds per trick (early/mid/
  late).
- **Bidding:** still uses Bot.PickBid heuristic (ISMCTS not in
  bid phase).
- **Escalation:** highest-quality Bel/Bel-x2/Four reads via style
  ledger + sampler.
- **Play:** evaluates 100 randomized opponent-hand worlds and
  picks the play with the highest aggregate rollout score.
- **Personality fit:** "pro player; reads partner perfectly,
  rarely makes a mistake".

---

## What we want each tier to *feel* like

> **TODO from videos:** capture how Saudi commentators describe
> different player skill levels. The terms aren't just "better"
> and "worse" — they have specific personality flavors:

- **The aggressive/reckless** — bids on weak hands, Bels often,
  Bel-x2-happy. *Which tier should this be?*
- **The patient/conservative** — passes on borderline hands,
  rarely Bels, never Fours. *Tier 2 perhaps?*
- **The tactical/calculator** — long pauses, computes precise
  reads, low variance. *Tier 5.*
- **The intuitive/feel-player** — quick decisions, occasional
  brilliant unconventional plays, occasional disasters.
  *No current tier maps to this; could be a future "Wild" tier.*

---

## Differentiating play signatures

When watching the same game state, each tier should make
*different choices*. Capture from videos:

- **Bidding aggressiveness curves** — at what hand strength does
  each tier first START bidding?
- **Escalation appetite** — Bel rate per tier, Bel-x2 rate
  conditional on Bel, Four rate.
- **Trump-pull patterns** — when does the tier lead trump vs.
  off-suit?
- **Belote-preservation discipline** — how strict is each tier
  about keeping K+Q together?
- **Last-trick targeting** — does the tier "see" the trick-8
  bonus?

> **Empirical baseline (v0.5.4):** see
> `.swarm_findings/bot_baseline_metrics.json` for current
> per-tier escalation rates. Bel/Bel-x2/Four/Gahwa are 0% in
> natural symmetric play across all tiers — calibration is
> currently against synthetic data, not real games.

---

## "Saudi Master" — what the top tier should look like

The Saudi Master tier is the calibration target. From real
tournament videos:

> **TODO from videos:** capture moves that ONLY a Saudi Master
> would make. These are the "tells of mastery":
> - Specific signaling-aware leads.
> - Sub-optimal plays that set up future-trick wins (sacrificial
>   discards).
> - "Reading" through escalation chains.
> - Match-point clinches.
>
> If a video has a "look how he played that!" moment, it's a
> Saudi Master move. Document the pattern.

---

## NEW (from videos — tier-fit assignments)

### Saudi-Master tier signature moves

From video #8 (the "smart move"):

- **J-sacrifice in Sun** (sacrifice the J when you'd win with 9
  anyway, to bait opp into re-leading) — **M3lm+ tier** should find.
- **J-trump-sacrifice in Hokm** (same shape, goal inverts to
  *suppress* opp's trump re-pull) — **Fzloky+ tier** should find.
- **T-sacrifice in Sun** (sacrifice the 10 itself) — **Saudi
  Master ONLY**. Speaker explicit: "ما يسويها الا واحد محترف في
  البلد" (only a real pro plays this). ISMCTS rollouts may surface
  it; hand-coded heuristic risks misfiring at lower tiers.

From video #6 (Faranka in Sun):

- **5-factor Faranka scoring** — M3lm should evaluate the 5 factors
  for Sun pos-4 Faranka decisions; Saudi Master via ISMCTS rollouts
  should converge to similar choices.

### Tier-distinguishing observable behaviors

The bot needs play-signature differences. Per video extraction:

| Behavior | Basic | Advanced | M3lm | Fzloky | Master |
|---|---|---|---|---|---|
| Pos-4 in Sun: Faranka with J+A | No | No | Yes | Yes | Yes |
| Sun: J-sacrifice for re-lead deception | No | No | Yes | Yes | Yes |
| Hokm: J-trump-sacrifice to suppress re-pull | No | No | No | Yes | Yes |
| Sun: T-sacrifice (Saudi-Master move) | No | No | No | No | Yes |
| Honors Tahreeb signals from partner | No | No | Yes | Yes | Yes |
| Sends well-disciplined Tahreeb (5 forms) | No | No | Partial | Yes | Yes |
| Reads touching-honors signaling | No | No | Yes | Yes | Yes |
| Pigeonhole trump-pin (full extension of H-1) | No | No | No | Yes | Yes |
| Per-partner conventionAdherence calibration | No | No | No | Yes | Yes |
| Probabilistic SWA (sub-100% certain) | No | No | No | No | Yes (via ISMCTS) |

This table is the **operational tier-distinguishing spec**. When
implementing a new heuristic, gate it by tier consistent with this
table.

---

## Source video log

| Source | Title | Date processed | Tier(s) informed |
|---|---|---|---|
| `06_faranka_in_sun` | كيف تتفرنك في الصن | 2026-05-04 | M3lm+ (Faranka 5-factor framework); Master (T-sacrifice variant) |
| `08_smart_move` | حركه ذكيه في البلوت | 2026-05-04 | M3lm (Sun J-sacrifice); Fzloky (Hokm variant); Master (T-sacrifice) |
| `09_most_essential_tahreeb` | اكثر تهريب تحتاجه في البلوت | 2026-05-04 | M3lm+ (Tahreeb signaling discipline) |
| `05_baloot_predictions_general` | التوقعات في البلوت بشكل عام | 2026-05-04 | Fzloky (touching-honors reads, pigeonhole-pin extension); Master (per-partner conventionAdherence) |
| `13_predict_trick` | توقع الحلَّة | 2026-05-04 | Fzloky+ (trick-prediction primitive feeding Tahreeb/Tanfeer/Faranka); Master (~90% confidence cap in Hokm) |
| `14_bargiya_ace_tahreeb` | تهريب الاكة — البرقية | 2026-05-04 | M3lm+ (Bargiya 2-flavor); Fzloky (receiver phase-split heuristic) |
| `15_kaboot_detailed` | الكبوت في البلوت | 2026-05-04 | M3lm+ (early-trigger Kaboot at trick 3); Fzloky (Bel-vs-Kaboot multiplier choice) |
| `17_k_tripled` | المثلوث K | 2026-05-04 | M3lm+ (K-tripled trickle pattern); Fzloky (exploiting opp مثلوث) |
| `19_discover_via_tahreeb` | اكتشف اوراق خصمك | 2026-05-04 | Fzloky+ (six-factor opp-Tanfeer reading); Master (per-opp ledger keys: tanfeerSeen, tanfeerAbsent, tanfeerSwitchedTo) |
| `20_control_game` | كيف تسيطر على اللعب | 2026-05-04 | M3lm+ (game-control / مسك اللعب tempo management) |
| `21_magnify_sun` / `22_magnify_hokm` / `23_miniaturize` | Takbeer/Tasgheer series | 2026-05-04 | All tiers (basic certainty-conditioned dump); Fzloky+ for Hokm trump non-consecutive inversion |
| `35_swa_term_detailed` | شرح مصطلح سوا | 2026-05-04 | All tiers (deterministic-only SWA — RETRACTS earlier "probabilistic SWA Master-tier" suggestion) |
