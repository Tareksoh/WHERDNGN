# Escalation chain — Bel / Bel x2 / Four / Gahwa

> **v1.4.1 status update**: this file is **partially populated**.
> Threshold values are now empirically calibrated (v1.3.2 + v1.3.4
> walkbacks anchored to corrected multiseed harness measurements).
> The CALIBRATION-OPEN items below are **BLOCKED on video research**
> per user direction — Saudi-pro Bel-mandatory hand patterns and
> "aggressive Bel x2" patterns require dedicated strategy-video
> transcripts that don't exist in `docs/strategy/_transcripts/` yet.
> When such transcripts arrive, items in this file should be updated
> with video-cited frequency/pattern data.

> **Stub status**: header had previously read "populate from YouTube
> transcripts" implying everything was unwired. Most prose IS now
> populated (see `R.CanBel` Bel-100 Sun gate, escalation thresholds
> calibrated v1.3.2-v1.3.4, Bel-fear ramp v0.6.0+, etc.). The
> remaining gaps are explicitly tagged "BLOCKED on video" below.

> **Naming convention (final):**
> - بل (Bel) — ×2, defender opens
> - بل×2 (Bel x2) — ×3, bidder counters
> - فور (Four — English loan-word) — ×4, defender re-counters
> - قهوة (Gahwa / Coffee) — match-win, bidder terminal
>
> Code identifiers (`K.MSG_TRIPLE`, `Bot.PickTriple`, etc.) are
> English shortcuts and stay as-is for backward compat — strategy
> notes use the Saudi names. See `glossary.md` for the full mapping.

## What this file informs

When modifying escalation-decision bot logic, this is the reference:

- `Bot.PickDouble` — defender Bel decision (Bot.lua)
- `Bot.PickTriple` — bidder Bel x2 counter-decision (×3)
- `Bot.PickFour` — defender ×4 counter-decision
- `Bot.PickGahwa` — bidder Gahwa (Coffee) terminal decision
- `K.BOT_BEL_TH=62`, `K.BOT_TRIPLE_TH=82`, `K.BOT_FOUR_TH=80`,
  `K.BOT_GAHWA_TH=95` — threshold values (current as of v1.4.x;
  re-anchored to corrected multiseed harness in v1.3.2-v1.3.4).

**Updated context (v1.3.x cycle):** the original v0.5 "0% chain
fire" was caused by a multiseed harness state-prep bug (fixed in
v1.3.0) — escalation pickers read empty `S.s.hostHands` arrays
and always returned false. Once the harness was fixed, the
corrected probe showed `BOT_BEL_TH=35` fired Bel at ~92% (the
v0.11.20 calibration was tuned against a bug-zeroed null).
Thresholds were re-anchored in v1.3.2 against measured
distributions and walked back in v1.3.4 to align with `escalation.md`
prose-ordering (Triple-worthy hand requires more strength than
Bel-worthy hand).

---

## Bel (×2) — defender's open

The defender Bels when they believe **the bidder will fail**. Saudi
strategy literature emphasizes:

- Side-suit Aces are the strongest signal (sustained trick power).
- Voids (especially in trump) enable ruff-capture of the bidder's
  trump leads.
- Long off-suit cards (7-9 in non-trump) are dead weight; they
  dilute strength score.

### v1.4.2 video-mining update — Bel-mandatory patterns

44 video transcripts in `_transcripts/` were systematically scanned
for Bel-mandatory hand-shape patterns. **Result: shape-based
"3+ side Aces = always Bel" or "multi-void = always Bel" rules
have ZERO transcript support.** The closest evidence is EV-based
reasoning that converges on Bel under specific conditions:

| Pattern | Source | Confidence | Code mapping |
|---|---|---|---|
| **Score-desperation Bel** — defender team severely behind, opp took Sun. Speaker «ما أنت خسرانه — ممكن يجيك مشروع» (you can't lose more than you're already losing). Round already conceded; Bel cannot meaningfully worsen cumulative position. Bel REGARDLESS of hand. | `25_when_bid_sun` R26 | Common (single source, explicit reasoning) | `Bot.PickDouble` Bot.lua:6045 — score-urgency path. NOT yet wired as a hand-bypass; current `scoreUrgency` only adjusts threshold magnitudes, not bypasses. **Recommendation**: when `cumulative[myTeam] < cumulative[oppTeam] - 80` (or similar large gap), bypass strength check entirely. **DEFERRED** — magnitude needs play-test validation. |
| **100-meld + Ace defender Bel** — defender holds مشروع 100 (a 100-point meld) plus an Ace. "Almost guaranteed positive EV." | `25_when_bid_sun` R27 | Common (single source) | `Bot.PickDouble` — conditional on `meldPoints[myTeam] >= 100 + has_ace`. Currently melds aren't read in `PickDouble`. **Recommendation**: implement conditional-Bel for 100-meld+Ace shape. **DEFERRED**. |
| **A+T mardoofa Bel** — defender holds Ace + Ten of same suit. «ممكن تجيك عشرة رابعة وتكمل لك 100» (10 may complete a 100-meld). Probabilistic positive EV. | `25_when_bid_sun` R28 | Sometimes (single source, "ممكن" / probabilistic) | `Bot.PickDouble` — strength-formula already gives mardoofa shapes a bonus via `aceCountAndMardoofa` (Bot.lua:1138-1155). Likely already captured by current threshold tuning. |
| **Bel-fear bidder side** — bidder anticipates opp Bel when bidder has weak hand near match-point. Restraint at bid time, not at Bel time. | `25_when_bid_sun` R19, `26_when_bid_hokm` R18 | Common | `Bot.PickBid` — already wired via Bel-fear ramp (v0.6.0 → v1.2.1 jitter). |

**No transcript evidence found for**: shape-based Bel-mandatory
patterns ("3+ Aces", "trump-void enabling ruff"), "open Bel vs
closed Bel" discrimination heuristics, "delay-Bel after partner
response" timing rules. These remain **BLOCKED** — the corpus
either doesn't contain dedicated videos on these or they're
addressed implicitly (see `K.BOT_BEL_TH` calibration history).

> **TODO from videos** (still open after 44-transcript scan):
> - "Open Bel vs Closed Bel" discrimination — `wantOpen` second
>   return value in `Bot.PickDouble` has no video basis. **BLOCKED**.
> - Bel timing (delay vs immediate) — not addressed. **BLOCKED**.
> - Mid-chain reads ("after Bel x2, partner of bidder should
>   expect X") — not addressed. **BLOCKED**.

### Open Bel vs Closed Bel

- **Open Bel** — invites Bel x2. "I'm strong, are you stronger?"
- **Closed Bel** — declines further escalation. "Just stop here."

The bot currently has a `wantOpen` second return value but the
discrimination is heuristic; videos should clarify when humans
prefer open vs closed.

---

## Bel x2 (بل×2 — ×3) — bidder's counter

Bel x2 is the bidder's response to a Bel. Logic: "you say I'll
fail, I say I'll make so hard you'll regret doubling." Code calls
this `Bot.PickTriple`; commentators say "بل×2".

Bel-x2-mandatory patterns:
- Bidder has J+9+A of trump (≥45 raw of the 62 trump points pre-
  trick).
- Bidder has Belote (K+Q of trump, +20 multiplier-immune).
- Bidder has 5+ trumps total.

### v1.4.2 video-mining update — Bel-x2 thresholds

44-transcript scan for Bel-x2 "aggressive" hand-shape patterns.
**Result: BLOCKED.** The only transcript covering Bel-x2 mechanics
is `11_bel_beginners_extracted.md`, which treats Bel-x2 as a
binary structural option (defender Bel'd, bidder either counters
or accepts). Speaker quotes:

> «اللي راح يفوز في هذه السكه راح يفوز في الجيم كامل»
> (whoever wins this round wins the entire game)

This emphasizes the stakes but provides ZERO hand-strength criteria.
The transcript's own "Non-rule observations" section explicitly
flags: "No discussion of Bel x2 / Four / Gahwa strength thresholds
beyond restating 'doubles the prior multiplier'."

**No other video** (videos 12-44, including `26_when_bid_hokm` R19
that mentions "ما يخلونها قهوة" — "they don't let it reach Coffee")
provides Bel-x2 hand-shape triggers. The "اglsavg" pacing/restraint
observation isn't about *when* to call Bel-x2; it's about session-
level conservatism.

`K.BOT_TRIPLE_TH=82` (v1.3.4) remains a calibration-empirical value
without video grounding. Any future tuning should be empirical.

> **TODO from videos** (still BLOCKED after exhaustive scan):
> - Saudi-pro Bel-x2 hand-shape triggers — no transcript exists.
> - "Aggressive Bel-x2 on weak hands" pattern — no source.
> - "Bel-x2 on J+9+meld" or similar quantified patterns — no source.

---

## Four (فور — ×4) — defender's counter

Four (the English word, written in Arabic as فور) is rare but
devastating. Defender escalates to ×4 when they believe the Bel x2
was a bluff. Four hand patterns:

- Defender has 3+ side-suit Aces (sustained trick power even if
  bidder has strong trump).
- Defender team has multiple voids → ruff capacity for bidder's
  trump leads.
- Bidder team is at high cumulative score (matchPointUrgency
  reduces threshold — bot encodes this).

> **TODO from videos:** Saudi pros say "فور على القهوة" — "Four
> aimed at the Coffee" — meaning Four called specifically to bait
> Gahwa. Capture this dynamic.

---

## Gahwa (Coffee — match-win) — bidder's terminal

Gahwa is the "I'll win the match on this round" call. A successful
Gahwa wins outright. A failed Gahwa is a hand-killer (the failing
team loses the match, or per-house-rule loses the equivalent of
the match target).

Gahwa-mandatory patterns:
- Near-certain rolloff: bidder has J+9+A+T of trump + side-suit Aces.
- Very rare in casual play; most common in clinches when bidder
  team is at 130+ of 152.

> **TODO from videos:** Saudi pros have memorable "Gahwa stories"
> — situations where Gahwa was right despite looking thin. Capture
> patterns. Also: when is the *reckless* Gahwa correct (matchpoint
> desperation vs likely-fail)?

---

## v1.4.2 video-mining update — Round-1 Bel restriction

44-transcript scan for the round-1 anti-grief rule referenced in
`decision-trees.md:91`. **Result: Common-tier evidence, single
source, session-variant.**

Source: `11_bel_beginners` decision rules row 6. Speaker:

> «بعض الجلسات تمنع هذا الشيء»
> (some sessions forbid this)

Context: calling Bel (or Gahwa) on the very first round of a
fresh match (score 0–0) is banned in some Saudi-table rule sets
to prevent a sore-loser one-shot-killing the match via Gahwa on
the opening bid. Speaker frames it as «تخرب اللعب» (spoiling the
game) — anti-grief for fresh matches.

**Variant**: NOT a universal rule. Speaker explicitly says some
sessions enforce it, others don't.

**Recommendation for bot default**: round-1 Bel/Gahwa restraint
as the BEGINNER-FRIENDLY default. M3lm+ tier could allow override
on extreme-strength hands. **DEFERRED** — implementation decision
pending user direction:
- Hard rule (always restrict round-1 Bel)?
- Soft tier-gated (basic/advanced restrict; M3lm+ allow)?
- Configurable WHEREDNGNDB.allowR1Bel toggle?

The exact wording of the rule (whether "round 1 of the entire
match" or "first sakkah") is not specified beyond "score 0–0 on
fresh match." Cross-referenced in `40_cut_deal_rules` non-rule
observations as an open question — confirms `11_bel_beginners`
as the sole source.

---

## Escalation timing — chain-flow expectations

Reading the chain is a meta-game:

- Bel → No Bel x2 = bidder is afraid; defenders should expect ≥45
  trick points without further escalation.
- Bel → Bel x2 → No Four = defenders folded; bidder probably has it.
- Bel → Bel x2 → Four → Gahwa = "showdown"; sub-1% probability of
  occurring naturally; almost always a clinch decision.

> **TODO from videos:** capture the *mid-chain* read commentators
> use. "After Bel x2, partner of bidder should expect X" type rules.

---

## NEW (from videos — see `decision-trees.md` Section 2)

### Bel (×2) legality gate (video #11)

**Saudi naming variations:** the ×2 rung is also called **الدبل
(al-Dabl)** — loan-word from English "double." The ×3 rung is also
called **ثري (Theri)** — loan-word from "three." Earlier docs
incorrectly claimed Saudi players don't say ثري; that was wrong.

**Sun-only legality rule:** Team at **≥100 cumulative score** is
**FORBIDDEN** from calling Bel in Sun. Only the team <100 may Bel.
This is a HARD rule, not a heuristic. Hokm has no such gate.

```
Sun: if S.s.cumulative[myTeam] >= 100, Bot.PickDouble must return false
Hokm: no score gate
```

This is enforcement-grade and should be implemented in
`Rules.lua` as `R.CanBel(team, contract)`, not just gated in
`Bot.PickDouble`.

### Other Bel constraints from video #11

- **Cards-revealed lockout** (مقفول): once any card is shown in a
  trick, the Bel window closes.
- **Round-1 anti-grief restriction:** speaker references
  round-1 Bel limit; exact rule TBD from follow-up.
- **Threshold heuristic NOT provided:** video #11 is a rules-of-
  the-game explainer. It does NOT supply hand-strength thresholds
  for *when* to call Bel. The current `K.BOT_BEL_TH=60` calibration
  remains best-guess; a strategy-level Bel-decision video would be
  the next unblock.

### Kaboot interaction (video #15)

- When `K.MULT_BEL × hand_total > K.AL_KABOOT_*`, the multiplier
  path scores higher than the sweep. Bidder may **sabotage own
  sweep** (تخريب الكبوت) to land at multiplier instead.
- Earlier-trigger Kaboot pursuit (trick 3) — see endgame.md
  Section 5.

---

## Source video log

| Source | Title | Date processed | Sections informed |
|---|---|---|---|
| `11_bel_beginners` | شرح الدبل في البلوت للمبتدئين | 2026-05-04 | Bel legality gate (Sun ≥100 forbidden); cards-revealed lockout; ثري naming |
| `15_kaboot_detailed` | الكبوت في البلوت | 2026-05-04 | Bel-vs-Kaboot multiplier interaction (تخريب الكبوت) |
