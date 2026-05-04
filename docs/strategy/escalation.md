# Escalation chain — Bel / Bel x2 / Four / Gahwa

> **Stub — populate from YouTube transcripts.** This is the most
> Saudi-specific aspect of the game; transcripts will add the most
> value here.

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
- `K.BOT_BEL_TH=60`, `K.BOT_TRIPLE_TH=90`, `K.BOT_FOUR_TH=110`,
  `K.BOT_GAHWA_TH=135` — threshold values

**Critical context:** as of v0.5, the escalation chain fires at
**0% in symmetric pure-bot play**. The thresholds are calibrated
for asymmetric human hand distributions. See
`.swarm_findings/v0.5_FINAL_REPORT.md` section 4 for the gap.
**Real-game telemetry (or asymmetric playtest data from
transcripts) is the unblocking input here.**

---

## Bel (×2) — defender's open

The defender Bels when they believe **the bidder will fail**. Saudi
strategy literature emphasizes:

- Side-suit Aces are the strongest signal (sustained trick power).
- Voids (especially in trump) enable ruff-capture of the bidder's
  trump leads.
- Long off-suit cards (7-9 in non-trump) are dead weight; they
  dilute strength score.

> **TODO from videos:**
> - Specific "Bel-mandatory" hand patterns Saudi pros recognize.
> - When to Bel "for show" (closed Bel, signaling weakness without
>   inviting Bel x2).
> - Bel timing — does the defender always Bel immediately, or
>   delay-Bel after seeing partner's response?

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

> **TODO from videos:** Saudi tournaments often see Bel x2 in
> situations bot would consider weak. What hand patterns justify
> "aggressive Bel x2"?

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
