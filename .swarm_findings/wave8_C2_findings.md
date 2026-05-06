# Wave 8 C2 — Partner Coordination Batch A Findings

Auditor: Pathfinder (C2)
Codebase: WHEREDNGN v0.4.4
Scope: Bot.lua, BotMaster.lua, Constants.lua, Cards.lua, Rules.lua, State.lua, Net.lua

---

## B-78 — Human Kawesh-eligible hand detection by bot: pre-redeal strategy

**SIGNAL/MISTAKE:** MISTAKE — partial gap.

**Analysis:**
`Bot.PickKawesh` (Bot.lua:1302–1308) calls `C.IsKaweshHand(hand)` which returns true when all 5 initial cards are 7/8/9 (Cards.lua:164–170). The bot unconditionally calls Kawesh if eligible. The bot does NOT, however, use this same logic offensively against human opponents. `Bot._memory` tracks `void` flags and played cards per seat, but there is no counter tracking how many low-rank (7/8/9) cards an opponent has played, and no inference path that concludes "opponent held a Kawesh-eligible hand but did not call it — therefore they have no honor cards."

The closest mechanism is `suitStrengthAsTrump` (Bot.lua:298–332): it awards 0 for 8 and 7 of trump (fixed in 13th audit), and the BotMaster tier samples opponent hands biased toward "strong" cards based on `getStrongCards` (BotMaster.lua:39–55). But neither path queries whether an opponent's entire initial hand was low-card.

**Frequency:** Low. Kawesh-eligible hands are statistically rare (~1 in several hundred deals depending on exact rules). However, when it happens and the human declines to call Kawesh (trap or oversight), the bot cannot exploit it.

**Bot-exploits-it:** No — the bot does not detect or exploit a declined Kawesh.

**File:line:** Bot.lua:1302 (`PickKawesh`); BotMaster.lua:39 (`getStrongCards`); Bot.lua:95–116 (`emptyMemory` — no low-card counter).

**Fix:** Add a per-seat `lowCardCount` counter to `_memory` (incremented in `OnPlayObserved` when rank is 7/8/9). After trick 3, if an opponent's `lowCardCount >= 3` and `void` shows no suit with honors played, set an inferred flag `probableKawesh = true` for that seat. In `pickLead` and BotMaster's `sampleConsistentDeal`, use this flag to sample that opponent with honor-free hands and play more aggressively (lead side-suit bosses without fear of losing to that opponent's high cards).

---

## B-79 — Human bid-card reading: humans react to the visible bid card

**SIGNAL/MISTAKE:** MISTAKE — absent heuristic.

**Analysis:**
The bid card (face-up flipped card) is available as `S.s.bidCard` throughout `PickBid` (Bot.lua:540–656). The bot uses `bidCardSuit` only for two purposes: (1) gating round-1 Hokm-on-flipped (`Bot.lua:629–634`), and (2) the Ashkal eligibility / J-of-flipped check (`Bot.lua:612–620`). There is no code that models how a human player over-weights the bid card's suit when evaluating their own hand.

Concretely: if the bid card is "AH" (Ace of Hearts), a human player will mentally inflate their Hearts suit. The bot has no heuristic to predict that a human is more likely to bid Hokm:H or evaluate their hand relative to Hearts. The `partnerBidBonus` function (Bot.lua:410–427) reads partner's actual bid after it is placed — it does not predict what a human is likely to bid based on the face-up card. `sampleConsistentDeal` in BotMaster.lua (line 124–274) biases the bidder's hand toward `getStrongCards(contract)` which is derived from the contract type and trump already decided — not from the bid card suit as a pre-bid signal.

**Frequency:** Every deal. Every human at the table sees the bid card and is cognitively biased by it.

**Bot-exploits-it:** No — the bot treats all non-flipped suits equally in round-2 bidding (Bot.lua:641–647 iterates `K.SUITS` excluding `bidCardSuit` with no suit-attractiveness weighting).

**File:line:** Bot.lua:544 (`bidCardSuit` declaration); Bot.lua:641–647 (round-2 suit selection loop); BotMaster.lua:39–55 (`getStrongCards`).

**Fix:** In `PickBid` round-2 and in `sampleConsistentDeal`, add a bid-card-suit attractiveness weight: if the bid card is an Ace or face card (A/K/Q), add a +10–15 prior to the probability that human opponents bid or hold strength in that suit. In BotMaster's opponent hand sampling, increase the `desire` weight for the bid-card suit when sampling a non-bidder human (this is the suit they were most likely evaluating pre-bid). This lets the bot anticipate opponent bids and play more accurately in the resulting contract.

---

## B-80 — Human bluff-pass: passing a strong hand to see if opponents commit

**SIGNAL/MISTAKE:** MISTAKE — R2 threshold is flat; no R1-all-pass adjustment.

**Analysis:**
`Bot.PickBid` computes `thHokmR2 = jitter(r2Base - urgency, BID_JITTER)` (Bot.lua:574) where `r2Base` is `TH_HOKM_R2_BASE = 36` (or 38 in Advanced, Bot.lua:572). This threshold is computed identically whether R1 was all-pass or whether someone bid in R1. There is no code anywhere in `PickBid` or `HostAdvanceBidding` that flags "R1 was all-pass" as a signal relevant to bot bidding decisions.

The `S.s.bids` table is reset to `{}` when entering round 2 (`Net.lua:731`, `State.lua:1503–1504`). This means by the time a bot calls `PickBid` in round 2, all R1 bid information is gone. Even if the bot wanted to detect "everyone passed R1 → trap hands possible," the data is not available in `S.s.bids` at that point.

The result: a bot that would normally pass a 40-strength hand in R2 (just below `thHokmR2 ≈ 38`) will always do so, regardless of whether R1 was 4×PASS (indicating most players have 40–50 strength hands that they trapped). Human trap-passers then bid strongly in R2 against a bot that did not adjust for the elevated field strength.

**Frequency:** Common. Experienced human players trap-pass routinely in R1.

**Bot-exploits-it:** No — and the bot is also vulnerable: it cannot defend against an opponent who trap-passed, because it does not infer from all-pass-R1 that the opener's R2 bid is likely from a strong hand.

**File:line:** Bot.lua:556–574 (threshold computation, no R1-context branch); State.lua:1503–1504 (`HostBeginRound2` clears `s.bids`); Net.lua:731 (client-side bids clear).

**Fix (two-part):** (1) Before clearing R1 bids in `HostBeginRound2` and `_OnDealPhase`, snapshot a boolean `s.r1WasAllPass = true` when all four bids were K.BID_PASS. (2) In `Bot.PickBid` round-2 path, if `S.s.r1WasAllPass` is true, subtract 5–8 from `thHokmR2` (lower threshold = more willing to bid) to model the elevated field. This prevents the bot from being exploited by R1 trap-passers who open R2 with a strong hand the bot should have matched.

---

## B-81 — Human post-Takweesh play change: caught humans play more carefully afterward

**SIGNAL/MISTAKE:** SIGNAL present (TAKWEESH_RATE_BY_TRICK decay), but MISTAKE in that it does not account for "already called this round."

**Analysis:**
`TAKWEESH_RATE_BY_TRICK` (Bot.lua:1324–1327) decays the call probability from 0.60 at trick 0 down to 0.05 at trick 7 — correctly modeling that a bot calling Takweesh late looks less lifelike. The angle's observation is correct: this rate should ALSO decrease if Takweesh has already been called in this round, because the human opponent will now play more carefully and is unlikely to make another illegal play.

There is no variable in `Bot._memory` or anywhere in the state tracking whether Takweesh was already called in the current round. `S.s.takweeshResult` (State.lua:115) stores the most recent Takweesh outcome for UI display but is not consulted by `PickTakweesh`. The scan in `PickTakweesh` (Bot.lua:1336–1349) finds the first `p.illegal` play in all completed tricks and the current trick — if the same play was already called and resolved (marked caught), a second scan of the same play would re-detect it unless Net.lua/State clears the `.illegal` flag post-resolution.

**Frequency:** Low per-round (Takweesh is rare), but the exploit window is real: if Takweesh is called and the human continues to make illegal plays, the bot applies the same random rate rather than a near-zero "they are now hyper-careful" rate.

**Bot-exploits-it:** Not correctly. The rate does not differentiate "fresh illegal play by a not-yet-caught human" from "same illegal play after a Takweesh warning."

**File:line:** Bot.lua:1324–1327 (`TAKWEESH_RATE_BY_TRICK`); Bot.lua:1329–1353 (`PickTakweesh`, no already-called guard); State.lua:115 (`s.takweeshResult`, not queried).

**Fix:** Add a `Bot._memory[seat].takweeshCalledThisRound` flag (or a round-level `Bot._takweeshCalledSeats` set). In `PickTakweesh`, after a Takweesh is successfully called on a seat, mark that seat. On subsequent calls, halve the rate for that seat (e.g., `rate = rate * 0.3`) to reflect the human now playing more carefully. Reset with `Bot.ResetMemory` at round start.

---

## B-82 — Human Hokm bidder "trump drought" tell: delayed first trump lead

**SIGNAL/MISTAKE:** SIGNAL partially captured, but MISTAKE — the inference is not wired to aggressive ruffing decisions.

**Analysis:**
`Bot._partnerStyle[seat].trumpEarly` (Bot.lua:134–143) counts trump leads before trick 5. The counter is incremented in `OnPlayObserved` (Bot.lua:246–254) when `#trickPlays == 1` (a lead) and the card is trump. The bidder's `trumpEarly` counter will remain at 0 through tricks 1–4 if they have not led trump — this is exactly the "delayed trump lead" tell.

However, `styleTrumpTempo` (Bot.lua:189–196) — the function that reads this counter — is explicitly marked "currently unused by the picker code; reserved for future M3lm-Plus heuristics" (Bot.lua:176–179). Neither `pickLead`, `pickFollow`, nor any escalation picker calls `styleTrumpTempo`. The data is collected but never acted upon.

The specific exploit path described in B-82 — "infer human bidder is trump-poor, ruff more freely" — would require: (a) detecting that `trumpEarly == 0` after trick 3 for the Hokm bidder seat, and (b) biasing the defender's lead choice toward non-trump suits (forcing the bidder to either ruff with scarce trump or lose point tricks). Currently `pickLead` for defenders (Bot.lua:804–888) uses void inference, Fzloky signals, and longest-suit logic, but no "opponent bidder is trump-poor so lead a juicy side suit" branch.

**Frequency:** Common. Trump-poor Hokm bidders (fewer than 4 trump) frequently delay trump lead, which is visible in the M3lm tier's trumpEarly counter.

**Bot-exploits-it:** No — `styleTrumpTempo` is dead code relative to play decisions. The counter accumulates but the inference never feeds back into `pickLead` or ruffing aggressiveness.

**File:line:** Bot.lua:134–143 (`trumpEarly`/`trumpLate` counters); Bot.lua:174–196 (`styleTrumpTempo` — unused); Bot.lua:785–800 (bidder trump-pull path, does not check opponent's trump-drought); Bot.lua:804–888 (`pickLead` defender path, no trump-drought branch).

**Fix:** In `pickLead` (defender path, M3lm or Advanced gate), after trick 3, check `Bot._partnerStyle[contract.bidder].trumpEarly`. If `trumpEarly == 0` and at least 3 tricks have been played, classify the bidder as likely trump-poor. Then bias toward leading high-point side-suit cards (Aces and Tens of non-trump suits) rather than singletons or long-suit lows, forcing the bidder to choose between giving up point tricks or spending scarce trump prematurely. This wires the already-collected `trumpEarly` signal to an actionable play decision.

---

## Summary

All five angles reveal genuine gaps. B-78: `Bot._memory` has no low-rank card counter, so a declined Kawesh hand is invisible to the bot. B-79: the bid card's suit exerts no attractiveness weight on opponent hand sampling or round-2 suit selection, leaving a systematic human cognitive bias unexploited. B-80: R1 bid history is wiped before round-2 thresholds are computed, so the bot cannot lower its R2 bar when a trap-pass round occurred. B-81: `TAKWEESH_RATE_BY_TRICK` decays by trick count alone; a post-call "now they're careful" decay is absent, meaning the bot may attempt to re-detect the same opponent's illegal play at the same rate even after a warning. B-82: `trumpEarly` is meticulously collected in `Bot._partnerStyle` but `styleTrumpTempo` is explicitly flagged as unused dead code — the trump-drought tell never feeds into defender lead choices, leaving the most common trump-poor tell unexploited.
