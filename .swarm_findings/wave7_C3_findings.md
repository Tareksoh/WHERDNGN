# Wave 7 C3 Findings — Memory + Pattern Recognition Exploitation (Batch A)

Angles: B-56, B-57, B-59, B-60, B-61

---

## B-56 — Human repeat-lead pattern: humans who always return to the same suit

SIGNAL / ONCE PER GAME (no counter exists) / NOT EXPLOITED / Bot.lua:136-143

`_partnerStyle` tracks six per-seat counters across the game: `bels`, `triples`, `fours`, `gahwas`, `trumpEarly`, `trumpLate`. There is no counter for "how many times did seat X lead suit Y." The `firstDiscard` in `_memory` (Bot.lua:107) records only the first off-suit discard of the current round, not a recurring opening lead preference. The `trumpEarly`/`trumpLate` split in `_partnerStyle` records trump-lead tempo but only for trump leads under Hokm (Bot.lua:246-254), and nothing equivalent exists for non-trump suits. A human who habitually returns to their opening lead suit throughout a game — a common Saudi Baloot pattern called "تكرار البداية" — leaves no footprint that the bot could read. The fix is a lightweight per-seat, per-suit counter such as `leadCount = {S=0,H=0,D=0,C=0}` accumulated in `OnPlayObserved` when `#trickPlays == 1` (a lead), then exposed in a derived `styleLeadSuitPreference(seat)` function parallel to `styleTrumpTempo`. Threshold: 2+ leads of the same suit in a game should be considered a signal.

---

## B-57 — Human anti-bot exploitation: humans who deliberately play unpredictably

SIGNAL (partial) / MODERATE / PARTIALLY EXPLOITED at SaudiMaster only / BotMaster.lua:1-30, Bot.lua:81-84

The `jitter()` function (Bot.lua:81-84) introduces ±6 randomness in bidding thresholds and ±10 in escalation thresholds. The SaudiMaster tier samples 30–100 determinized worlds per play decision (BotMaster.lua:515-517), which inherently produces play variety because candidate-card scores are aggregates over random hand distributions. However, jitter only affects threshold gating at bid/escalation time — actual play selection in `pickLead` and `pickFollow` is deterministic given legal cards and memory state. An experienced human who knows "bots always lead high trump when bidder" can hold the K of trump specifically to overcut the bot's forced J lead, and at all tiers below SaudiMaster the bot's lead will be perfectly predictable (Bot.lua:785-800: `if isBidderTeam and isBidder … return highestTrump`). There is no counter for opponent play variance or any detection of deliberate unpredictability. The `_partnerStyle` ledger does track opponents (all seats 1-4), but `styleTrumpTempo` is defined as a `local function` (Bot.lua:189) and is never called anywhere in the codebase — confirmed by grep: it appears only at its definition site and in a comment. The fix: `styleTrumpTempo` should be wired into `pickLead` for M3lm+ to modulate whether the bot leads high trump early against an opponent known to be tempo-aggressive, matching their style rather than being predictably countered.

---

## B-59 — Bot exploiting human "always Bel against Sun" reflex

MISTAKE / UNIMPLEMENTED / NOT EXPLOITED / Bot.lua:1153-1179, Constants.lua:252-255

`PickDouble` (Bot.lua:1153) is the defender's Bel decision. The function evaluates the bot's own hand strength plus `partnerBidBonus` and `partnerEscalatedBonus` and `scoreUrgency`, then gates against `K.BOT_BEL_TH = 70`. There is zero opponent-awareness in this function: the bot never reads the `_partnerStyle.bels` counter of the opposing team to decide whether to raise or lower its own Gahwa/Triple threshold. Specifically, if a human opponent is known to reflexively Bel every Sun contract, the bidder-bot's `PickTriple` (Bot.lua:1215) and `PickGahwa` (Bot.lua:1239) thresholds do not adjust. Both functions call `escalationStrength` → `escalateDecision` (Bot.lua:1191-1213), which is purely hand-strength + partner-info based and ignores `_partnerStyle[opponentSeat].bels`. The `bels` counter IS correctly incremented via `OnEscalation` (Bot.lua:162-172) — the infrastructure exists — but `styleBelTendency(seat)` (Bot.lua:181-187), the function that reads it, is never called anywhere in the codebase (confirmed by grep: definition only). The fix is to call `styleBelTendency` on each opponent seat in `PickTriple`/`PickGahwa`: if `styleBelTendency(opponentSeat) == 1` (opponent Bels habitually), lower the Triple threshold by ~8 and the Gahwa threshold by ~12 since the Bel was not a true strength signal.

---

## B-60 — Human partner-signal blindness: not reading bot AKA or Fzloky signals

SIGNAL / EVERY ROUND WITH HUMAN PARTNER / NOT SUPPRESSED / Bot.lua:1071-1108, Bot.lua:741-773

`Bot.PickAKA` (Bot.lua:1078) fires unconditionally for any Advanced+ bot lead of the highest unplayed non-trump card, and broadcasts the signal via `N.SendAKA` / `MSG_AKA` regardless of whether the partner is a human or a bot. There is no check of `S.s.seats[R.Partner(seat)].isBot` before deciding to AKA. The signal has real cost: it reveals information to all four seats (including opponents), and the bot deduces partner's suit preference from firstDiscard (`pickLead`, Bot.lua:748-773) only when Fzloky is active. If the human partner does not understand AKA convention, the bot is giving opponents free information about the boss card in a suit while receiving no behavioral benefit from the human side. The `firstDiscard` signal path in `pickLead` correctly reads `Bot._memory[partner].firstDiscard`, but that only works when the partner is a bot whose discard was itself strategic; a human's first discard may be random. The fix: in `Bot.PickAKA`, add a guard `if S.s.seats and S.s.seats[R.Partner(seat)] and not S.s.seats[R.Partner(seat)].isBot then return nil end` to suppress AKA when partner is human. Similarly, in `pickLead`, suppress the `fzlokyPrefSuit` branch when `not S.s.seats[partner].isBot`, since human discards are not reliable Fzloky signals.

---

## B-61 — Human "defensive" Sun: using Sun to block opponent Hokm

SIGNAL / UNDETECTABLE WITH CURRENT COUNTERS / NOT EXPLOITED / Bot.lua:354-399, Bot.lua:1153-1179

`sunStrength` (Bot.lua:354) evaluates the bot's own hand for a Sun bid. `PickDouble` (Bot.lua:1153) uses the defender's `sunStrength` to decide whether to Bel a Sun contract. Neither function accounts for the possibility that the Sun bidder is a human playing a marginal defensive Sun (score 50–55) to block an opponent Hokm. The `_partnerStyle` ledger has no "Sun bid quality" counter — there is no way to distinguish a genuine high-score Sun from a blocking Sun after the fact. The `thSun` threshold in `PickBid` (Bot.lua:575) is `jitter(50, 6)` at base, meaning the bot itself bids Sun at 44–56+, so it cannot infer that an opponent Sun at a similar score is defensive rather than genuine. The fix requires tracking opponent Sun bid outcomes across rounds: a new `sunFail` counter in `_partnerStyle` incremented when the opponent Sun contract fails (i.e., `R.ScoreRound` returns `bidderMade = false` for a Sun bidder), then used to raise the bot's `PickDouble` Bel threshold by ~8 when `_partnerStyle[oppSeat].sunFail >= 2`, signaling that opponent's Sun bids tend to be weak/defensive. This is the only reliable post-hoc signal available, as bid-time Sun score is not transmitted over the wire.

---

## Summary of dead-code issue affecting multiple findings

`styleBelTendency` (Bot.lua:181) and `styleTrumpTempo` (Bot.lua:189) are defined as `local function` but never called anywhere. `_partnerStyle` is populated correctly by `OnEscalation` and `OnPlayObserved`, but the derived-metric layer sits entirely inert. This is the common root cause for B-57, B-59, and partially B-61: the infrastructure is built, the counters are maintained, but the consumption layer was never wired to the decision functions.
