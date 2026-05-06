# Wave 7 C1 — Score-Position Exploitation, Batch A
## B-46 through B-50

---

### B-46 — Near-win pressure: bot under-bids when disruption is needed

**SIGNAL/MISTAKE:** MISTAKE — the near-win branch in `scoreUrgency` returns `-8` (raises threshold → more conservative) for the bot's OWN team when `me >= target - 25`. This applies uniformly whether the bot is on the near-win team OR the near-losing team facing a near-win opponent. When the HUMAN team is near-win, the bot's team is the near-loser, so it should receive the `+12` desperate branch — and it does, correctly. The structural mistake is that the near-win conservatism (`-8`) applies to ANY bid/escalation function (Bel, Triple, Four, Gahwa, preempt) for the leading bot team, including defensive disruption (Bel). A near-win bot should be MORE willing to Bel (to pile on and close the match), not less. The single modifier is used for both offensive bidding and defensive escalation contexts without distinguishing them.

**FREQUENCY:** Every round in which the bot's team is within 25 points of target — roughly the final 1–2 rounds of most games.

**BOT EXPLOITS IT:** Yes. When a human team holds a 127/152 lead, the bot (near-win team) drops its Bel threshold by `−8` (raising it), making it less likely to Bel a human bidder's contract even when that Bel+win combination would clinch the match. The human can bid marginal contracts unchallenged in precisely the window where it hurts most.

**File:line:** `C:/CLAUDE/WHEREDNGN/Bot.lua:449` (`scoreUrgency`, near-win return branch); `Bot.lua:1171` (PickDouble consumes it without context discrimination).

**Fix:** Introduce a `context` parameter (e.g., `"bid"` vs `"escalate"`) to `scoreUrgency` so near-win conservatism only suppresses offensive bidding, not defensive Bel/Four. Alternatively, expose a separate `defenseUrgency()` that returns `+8` (lower Bel threshold) when the team is near-win — match-clinching Bels are more valuable there, not less.

---

### B-47 — Near-loss desperation: bot does not lower Gahwa/Four thresholds to exploit reckless human escalation

**SIGNAL/MISTAKE:** SIGNAL (partial) — `scoreUrgency` already returns `+12` when the opponent is within 25 of target (near-loss for the bot), which lowers Bel/Triple/Four/Gahwa thresholds by 12. However, this is a flat, context-blind modifier. The specific exploit — detecting that a human trailing by 80+ is statistically likely to over-escalate with Gahwa on a sub-optimal hand — is not modeled. The bot does lower its own escalation thresholds when behind, but it does not raise its defensive counter-escalation eagerness in anticipation of a human's reckless Gahwa.

**FREQUENCY:** Occurs in every game where one team falls 80+ behind — common in lopsided early rounds.

**BOT EXPLOITS IT:** Partially. The `+12` desperation and `+6` far-behind branches do create asymmetric aggression, but the bot has no specific model for opponent escalation likelihood. When a human's team is at 72/152 and the bot's team is at 0, the human faces high Gahwa temptation; the bot's Gahwa threshold only drops by 6 (far-behind branch) rather than also factoring in the opponent's proximity to desperation-escalation. `_partnerStyle.gahwas` counter is accumulated (Bot.lua:169) but never read in any urgency calculation.

**File:line:** `C:/CLAUDE/WHEREDNGN/Bot.lua:451` (far-behind branch `+6`); `Bot.lua:125-147` (`_partnerStyle` definition with `gahwas` counter); `Bot.lua:169` (OnEscalation stores gahwa count, never consumed by urgency).

**Fix:** In `matchPointUrgency` (M3lm tier), read `Bot._partnerStyle[oppSeat1].gahwas` and `[oppSeat2].gahwas`. If the opponent team has Gahwa'd before AND they are currently trailing by 50+, add +3 to the modifier to pre-emptively lower bot's Four threshold (intercept the Gahwa chain before it starts by Belling more readily).

---

### B-48 — Human score-blind bidding: bot's position-aware asymmetry is the real exploit

**SIGNAL/MISTAKE:** SIGNAL — this is a correct exploit by the bot. `scoreUrgency` and `matchPointUrgency` fire only on Advanced/M3lm tier (Bot.lua:444, Bot.lua:469), giving the bot a genuine strategic edge over any human who bids purely on hand strength without position awareness. The asymmetry is intentional and real: a human at 140/152 who bids a marginal Hokm because "the hand looks good" faces a bot that is conservatively passing similar hands (near-win `-8`). Conversely, a human at 50/152 facing a 130/152 bot is met with a bot in full desperation mode (`+12`), so the bot aggressively bids hands the human might expect it to fold.

**FREQUENCY:** Any game with Advanced/M3lm bots where score diverges beyond 25 points from target, or where one team leads by 80+. Dominant in late-game rounds.

**BOT EXPLOITS IT:** Yes, correctly and by design. No code bug. The asymmetry is documented in the comment at Bot.lua:429-442.

**File:line:** `C:/CLAUDE/WHEREDNGN/Bot.lua:443-453` (scoreUrgency); `Bot.lua:468-487` (matchPointUrgency); `Bot.lua:555` (urgency applied at bid call site).

**Fix:** No bug fix needed. Document in the difficulty-level UI that Advanced/M3lm bots use match position in bidding decisions, so players who don't can be informed this asymmetry exists. This is a feature, not a defect.

---

### B-49 — Human target-score awareness: configurable target creates confusion, bot does not compensate

**SIGNAL/MISTAKE:** MISTAKE — `s.target` is fully configurable via `/baloot target <N>` (Slash.lua:210-225) and defaults to 152, but the UI score line (UI.lua:2793-2795) renders it as a bare integer at the right edge of the score string (`"  /  152"`). There is no label like "Target:" or visual emphasis. A human player joining a game with a custom target (e.g., 100 or 200) sees only a small number appended after scores with no explanation that this IS the win target. The bot correctly reads `S.s.target` everywhere (Bot.lua:448, Bot.lua:473) and adapts all urgency thresholds. The human has no such adaptation. If the human plays as though the target is 152 when it is 100, they enter near-win conservative behavior at entirely the wrong moment — the bot's urgency thresholds will have tightened (near-win at `target-25 = 75`) while the human is still bidding freely.

**FREQUENCY:** Any game with a non-default target, which is a user-controllable config option.

**BOT EXPLOITS IT:** Indirectly. The bot does not need to do anything special — it just correctly reads the target, while humans may not notice the configured value. The bot's urgency thresholds silently shift to match the new target; a confused human's behavior does not, creating a widening strategic gap.

**File:line:** `C:/CLAUDE/WHEREDNGN/UI.lua:2793-2795` (score display); `C:/CLAUDE/WHEREDNGN/Slash.lua:210-225` (target setting); `C:/CLAUDE/WHEREDNGN/Bot.lua:448` and `473` (target reads in urgency functions).

**Fix:** Change the score display string to prefix the target with a label, e.g., `"Goal: %d"` or color it distinctly when a non-default target is in use. Optionally, flash a notification when the game starts with a non-152 target.

---

### B-50 — Human comeback mechanic: deficit model covers only one direction, not the "careful loser" pattern

**SIGNAL/MISTAKE:** MISTAKE — `scoreUrgency` models two losing-team responses: `+12` when the opponent is near-win (desperation), and `+6` when behind by 80+ (take risks). Both drive aggression. But the comment in B-50's premise identifies that some human teams respond to a large deficit by playing MORE carefully rather than panicking. The bot's urgency model has no mechanism to detect or adapt to this pattern. The `_partnerStyle` table tracks `trumpEarly`/`trumpLate` tempo and escalation counts across the game, but there is no per-opponent deficit-response signal. If the human team is playing carefully (passing marginal hands, declining Bels) while 80 behind, the bot's aggressive `+6` modifier causes it to commit to escalations the humans will not match, sometimes resulting in the bot over-escalating into a Four on a contract the calm human defenders will beat.

**FREQUENCY:** Applies in every game where the deficit exceeds 80 at M3lm tier; the mismatch between "bot expects panic" and "human plays tight" occurs whenever the human plays the careful-loser style.

**BOT EXPLOITS IT:** No — this is a gap where the bot is exploitable by the human who knows to stay calm. A human that refuses to Gahwa or over-escalate while 80 behind will find the bot matching their position with `+6` aggression, potentially triggering Four rounds the human's calm team will win. The `_partnerStyle.gahwas` and `.fours` counters (Bot.lua:125-147) exist and are populated (Bot.lua:162-172) but are never consulted in `scoreUrgency` or `matchPointUrgency` to dampen the bot's urgency when opponent escalation history suggests restraint.

**File:line:** `C:/CLAUDE/WHEREDNGN/Bot.lua:451` (far-behind `+6` branch, no style gating); `Bot.lua:125-147` (`_partnerStyle` counters unused in urgency); `Bot.lua:468-487` (matchPointUrgency, no per-opponent escalation history lookup).

**Fix:** In M3lm tier, before applying the `+6` far-behind urgency boost, check the opponent team's per-seat `fours` and `gahwas` history. If both opponent seats show zero escalations over the last N rounds, dampen the `+6` to `+2` — the opponent is playing conservatively, and the bot should not gift them a Four win by over-escalating on the assumption of desperation.
