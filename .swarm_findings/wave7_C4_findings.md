# Wave 7 C4 — Memory + Pattern Recognition Exploitation, Batch B

## B-62: Human bid pattern by hand count — length-over-quality bias in Hokm

**SIGNAL** / ONCE PER CODEBASE / NO

`suitStrengthAsTrump` in `Bot.lua:298-332` applies a length bonus of `(count-2)*5` for every card beyond 2 in the trump suit. For a human who bids Hokm on a 5-card suit with modest honor strength (e.g., 5-card suit with K/Q/T but no J/9), their suit scores: 3+4+10 + (5-2)*5 = 32, which clears the round-1 base threshold of 42 only with jitter, but clears round-2 (36) comfortably. This is the observed over-bidding vector.

`getStrongCards` in `BotMaster.lua:39-55` biases the ISMCTS sampler to assign J/9/A of trump to the human bidder's seat with weights 50/40/30. A human who bid Hokm on a 5-card suit WITHOUT J or 9 (length-over-quality pattern) will be sampled with inflated trump holdings — the bot models them as stronger than they are. The sampler has no per-bidder length-qualifier. No skepticism penalty is applied when the bidder lacks J or 9.

**Fix**: In `getStrongCards`, when the observed bidder has NOT escalated and the contract is round-1 (bid in `PHASE_DEAL1`, detectable via `S.s.bidRound == 1`), reduce the J/9 weights and raise T/K to model a length-bidder pattern. Alternatively, add a `skepticismFactor` parameter to `sampleConsistentDeal` that scales down `strong[]` weights based on the bidder's `trumpEarly` history (a bidder who trumps early often holds J/9; one who doesn't, may have bid on length).

**File:line**: `BotMaster.lua:39-55`, `Bot.lua:298-332`

---

## B-63: Human escalation hesitation as information — Bel latency signal

**SIGNAL** / NEVER PRESENT / NO

The PHASE_DOUBLE window is entered at `State.lua:901` (`s.phase = K.PHASE_DOUBLE`) and terminated by either `N._OnDouble` (explicit Bel) or `N.HostFinishDeal()` called from `N._OnSkipDouble`. There is no timestamp recorded at phase entry. The `K.TURN_TIMEOUT_SEC = 60` timer in `Net.lua:2794` counts down to auto-skip, but no elapsed-time record is exposed to the bot's inference engine. `S.s` has no `phaseEnteredAt` or `belDecisionMs` field. `Bot._memory` and `Bot._partnerStyle` contain no latency fields.

The bot cannot distinguish a human who Bel-ed or skipped in 2 seconds from one who waited 55 seconds before declining. A near-threshold decliner (weak-ish hand that almost passed the Bel check) is informationally invisible.

**Fix**: Record `s.phaseEnteredAt = GetTime()` in `State.ApplyContractFinalized` (or wherever `PHASE_DOUBLE` is entered, `State.lua:901`). When the human human-skips, store `belResponseSec = GetTime() - s.phaseEnteredAt` in `Bot._partnerStyle[seat].belResponseSec`. The ISMCTS sampler can then weight a slow-decliner's hand marginally weaker when reconstructing future worlds.

**File:line**: `State.lua:901`, `Net.lua:2794`, `Bot.lua:136-196`

---

## B-64: Human last-trick concession — does rollout capture LAST_TRICK_BONUS?

**MISTAKE** / ONCE PER ROLLOUT / YES (SUBTLE)

`R.ScoreRound` in `Rules.lua:471-716` correctly adds `K.LAST_TRICK_BONUS = 10` at `Rules.lua:480-482`: `if i == #tricks then teamPoints[team] = teamPoints[team] + K.LAST_TRICK_BONUS end`. This is inside the per-trick loop and fires when `i == #tricks`.

`rolloutValue` in `BotMaster.lua:289-489` calls `R.ScoreRound(simTricks, contract, meldsByTeam)` at line 475. The `simTricks` array is built by the loop at `BotMaster.lua:440-488`, which runs `while #simTricks < 8`. After trick 8 is appended (`simTricks[#simTricks+1] = currentTrick` at line 445), the loop `break`s at line 446 (`if #simTricks == 8 then break end`). This means `simTricks` passed to `ScoreRound` has exactly 8 entries, so `i == #tricks` fires on the 8th trick and the bonus is included.

However, the human last-trick concession pattern (throw-in on an already-lost round) is NOT modeled in the `heuristicPick` rollout policy. At position 4 (`lastSeat` = true) when no winners exist, `pickFollow` returns `lowestByRank(legal, contract)` at `Bot.lua:1068`. The rollout policy mirrors this — `heuristicPick` in `BotMaster.lua:353-437` also falls through to `lowestRank(legal)` at line 435. A human who concedes the last trick throws a throwaway low card; the bot in rollout does the same. The LAST_TRICK_BONUS therefore accrues to whichever team wins trick 8 in the simulation. The bonus IS scored. But since the rollout doesn't model the human opting out of contesting the last trick, the bot cannot specifically target the 10 pts when the human would concede. This is an unexploited opportunity, not a scoring omission.

**Fix**: In the rollout's `heuristicPick`, when position==4 and `#winners == 0` and the round is already decided (team diff > handTotal/2), model the opponent as throwing their lowest card (already the default). No fix needed for scoring correctness. To exploit the human concession, bot play on trick 7 could specifically preserve a winning card for trick 8 when it detects that the human is losing badly. This is not currently done.

**File:line**: `BotMaster.lua:440-488`, `Rules.lua:480-482`

---

## B-66: Human over-dependent on bot partner — reckless early leads absorbed by bot?

**SIGNAL** / ONCE PER CODEBASE / PARTIALLY

The bot `pickFollow` (`Bot.lua:915-1069`) is already defensive: when partner is winning, it feeds A/T points (smother) or plays lowest non-trump. When the opponent wins, it plays cheapest winner (pos 4) or ducks at pos 2 (Advanced mode). The bidder bot leads high trump only when it IS the bidder (`isBidder` flag, `Bot.lua:785`); the partner falls through to defender-style.

The key gap: `pickLead` at `Bot.lua:720-892` has no mode that says "my human partner just burned a high card recklessly so I should be extra conservative." The bot leads as if human is playing optimally. If the human partner leads into a strong suit early and bleeds points, the bot's leads on subsequent tricks are unaffected. `Bot._partnerStyle[seat].trumpEarly` counter IS accumulated by `Bot.OnPlayObserved` at `Bot.lua:246-254`, and `styleTrumpTempo` at `Bot.lua:189-196` can return 1 for aggressive, -1 for conservative. However, `styleTrumpTempo` is marked "currently unused" at `Bot.lua:177-180` and is NEVER called from `pickLead` or `pickFollow`. The collected data is dead code.

**Fix**: In `pickLead` (Advanced tier), check `styleTrumpTempo` of the human partner. If `trumpEarly > trumpLate * 1.5` (aggressive partner), switch the bot partner lead from "low from longest" to "highest non-trump first" — cash our own high cards before the human can lead into the suit. Link: `Bot.lua:847-892` (the lead heuristics section after free-trick and singleton checks).

**File:line**: `Bot.lua:177-196` (dead `styleTrumpTempo`), `Bot.lua:847-892` (lead heuristics ignoring partner aggression)

---

## B-67: Tracking per-seat A/T retention — A-hoarding pattern

**SIGNAL** / ONCE PER CODEBASE / NO

`Bot._partnerStyle[seat]` stores `trumpEarly` and `trumpLate` (trump leads by trick number) but stores NO per-suit or per-rank retention data. There is no counter tracking how late in the hand a seat typically plays their Aces. `Bot._memory[seat].played` (`Bot.lua:102`) maps card string to `true` once observed — this can be queried post-hoc but no derived statistic is accumulated.

The ISMCTS sampler in `sampleConsistentDeal` (`BotMaster.lua:124-274`) applies a blanket `strong[]` bias toward trump honors for the bidder, but does NOT bias Aces specifically toward late-game positions for a human opponent. If a human opponent is an A-hoarder (plays A in trick 6-8 rather than trick 1-3), the sampler distributes their A as uniformly as any other card across all worlds. The bot therefore leads Aces-out-attempting plays too early when it shouldn't, wasting the forcing move when the opponent doesn't yet have trump depleted.

`styleTrumpTempo` (early trump lead ratio) is the closest proxy for aggression but captures leads, not Ace retention specifically, and is never read at play time.

**Fix**: Add per-seat `aceLate` counter to `Bot._partnerStyle`: increment when a seat plays their Ace of any non-trump suit in tricks 6-8 (detectable in `Bot.OnPlayObserved` at `Bot.lua:200`). In `sampleConsistentDeal`, when sampling an opponent with `aceLate >= 2`, add an ordering bias in Phase 1 that keeps Aces toward the tail of the sampled hand (i.e., delay their appearance in rollout simulations by assigning them last when sizing up). This forces bot rollouts to model the A as unavailable early, making the bot lead forcing non-Ace suits to bleed trump first.

**File:line**: `Bot.lua:136-196` (style ledger), `Bot.lua:200-270` (OnPlayObserved), `BotMaster.lua:211-231` (Phase 1 biased sampling)
