# Wave 6 C2 — Human Play Mistake Taxonomy (Batch B): Findings

Audited angles: B-24 (meld over-declaration), B-25 (takweesh under-use), B-26 (SWA overconfidence), B-27 (10-of-trump undervaluation), B-28 (bid-round timing tells).

---

## B-24 — Human meld over-declaration: declaring weak sequences to intimidate

**MISTAKE:** Casual players declare every detected sequence meld regardless of strategic value. Declaring even a seq3 (20 raw) tells the table the exact range of cards held (e.g., declaring 7-8-9 of spades reveals all three cards). Informed opponents know the declarant lacks the high honors in that suit and can lead into it aggressively.

**FREQUENCY:** Common. Nearly universal in casual games; experienced players withhold weak (seq3/seq4) melds when the information cost outweighs the raw point gain, especially against a team that has already declared a higher meld (which wins all meld points anyway per Saudi winner-takes-all).

**BOT EXPLOITS IT:** Partially, but not specifically. `Bot.PickMelds` at `Bot.lua:1130-1139` declares ALL detected melds unconditionally via `R.DetectMelds(hand, S.s.contract)`. The bot's `Bot._memory` void-inference system (lines 215-226) already tracks which suits opponents have played in, but there is no mechanism that reads OPPONENT meld declarations to infer suit composition (e.g., "opponent declared seq3 of H ⇒ opponent holds 7-8-9-H, lacks A/K/Q/J/T of hearts"). The bot's meld behavior exactly mirrors the human mistake — unconditional declaration — meaning informed humans get the same card-count signal from the bot that they would from a novice human. The bot cannot differentiate "weak seq3 not worth declaring" from "seq4+ worth declaring," nor does it use opponent meld declarations to feed into `Bot._memory[seat].void`.

**file:line:** `Bot.lua:1130-1139` (`Bot.PickMelds`), `Rules.lua:194-255` (`R.DetectMelds`)

**FIX:** In `Bot.PickMelds`, gate seq3 declarations (value == `K.MELD_SEQ3 = 20`) on whether the team can actually WIN the meld comparison; skip declaring if the opponent team has already declared a higher-rank meld or if the bot is on the losing team in the comparison. Independently, add a reader in `Bot.OnPlayObserved` or a new `Bot.OnMeldObserved` hook that, on seeing an opponent's declared meld (kind + suit + top card), derives the exact card subset and marks those cards as "seen" in `Bot._memory[seat].played` and the absent ranks as negative-knowledge (helping void inference on subsequent tricks).

---

## B-25 — Human takweesh under-use: humans miss illegal plays

**MISTAKE:** Casual human players frequently fail to call Takweesh (revoke challenges) because they are focused on their own hand. The rate of detection is meaningfully lower in human games than in a bot game where the engine has perfect card-memory.

**FREQUENCY:** Common in casual play; detection rates estimated at 20-30% on trick 1 for human players, dropping near zero by trick 4+. Expert players maintain higher rates but still miss calls in time pressure.

**BOT EXPLOITS IT:** The current `TAKWEESH_RATE_BY_TRICK` table in `Bot.lua:1324-1327` is:

```
[0]=0.60, [1]=0.55, [2]=0.45, [3]=0.40, [4]=0.30, [5]=0.20, [6]=0.10, [7]=0.05
```

The trick-0 rate of 60% represents the bot's probability of catching a revoke on the first completed trick. However, this rate is applied uniformly regardless of whether the opponent is a human or a bot. The question the angle asks: should the HUMAN detection rate (when a human can also call Takweesh) be modeled differently? The answer is yes — but the current code has no separate detection-rate for human callers. The 60% figure models BOT detection, which benefits from perfect card memory. A human caller would realistically be at 20-30% on trick 1. In a mixed human+bot game, both human and bot seats share the same code path; the distinction matters if the design ever needs to simulate "would a human have called this?" for purposes like AI training or difficulty scaling. Currently there is no distinction.

**file:line:** `Bot.lua:1324-1333` (`TAKWEESH_RATE_BY_TRICK`, `Bot.PickTakweesh`)

**FIX:** Add a separate rate table `TAKWEESH_RATE_HUMAN_BY_TRICK` (e.g., `[0]=0.25, [1]=0.20, [2]=0.12, [3]=0.08, [4]=0.04, [5]=0.02, [6]=0.01, [7]=0.00`) and gate on whether `seat` is human vs. bot when simulating human detection scenarios. For the current use-case (bot-only callers), the 60% figure is appropriate — but the lack of a human-rate constant means the game cannot model the human-miss pattern for future difficulty settings or tutorials.

---

## B-26 — Human endgame SWA: overconfident claims with 2–3 risky tricks remaining

**MISTAKE:** Human players frequently claim SWA (سوا) prematurely: with 2-3 cards left, they declare "I win all remaining tricks" before trump is fully exhausted. The most common scenario is holding a trump J or A but missing coverage for one side suit that an opponent can over-trump with a higher trump or lead a void to force an under-ruff.

**FREQUENCY:** Common. In casual Saudi play, SWA claims with 3+ remaining tricks are routine and often invalid. The validator at `Rules.lua:349-447` (`R.IsValidSWA`) performs a full minimax and correctly rejects invalid claims. The human error is in the decision to call, not in the system's validation.

**BOT EXPLOITS IT:** No mechanism exists. `Bot.PickPlay` (`Bot.lua:1110-1124`) has no branch that detects a pending or announced human SWA claim and adjusts play to try to win a trick before the SWA resolves. The SWA flow is entirely human-initiated; bots auto-accept SWA permission requests (`_OnSWAReq`, `Net.lua:2122-2136`) and have no strategic model of "try to spoil a SWA by grabbing one trick." The closest analog is that bots already play to beat opponents (`pickFollow`, `Bot.lua:962-1069`), but this is general trick-winning logic, not SWA-specific sub-optimal play designed to steal one trick against a SWA claimant. There is also no `Bot.PickSWAResp` function — bots unconditionally accept all SWA requests regardless of whether the claim looks beatable.

**file:line:** `Net.lua:2122-2136` (bot auto-accept SWA), `Bot.lua:1110-1124` (`Bot.PickPlay` — no SWA-awareness), `Rules.lua:349-447` (`R.IsValidSWA` minimax)

**FIX:** Add `Bot.PickSWAResp(seat, callerSeat, callerHand)` that runs a lightweight version of `R.IsValidSWA` from the bot's perspective (using known card memory) to decide whether to accept or deny the SWA request. If the minimax indicates at least one winning line for the bot's team, the bot should DENY, not auto-accept. Additionally, add a flag in `MaybeRunBot`'s play path: if an opponent SWA is pending validation, the bot (if it has priority in the current trick) should prefer its highest-value trick-winning card rather than its cheapest winner.

---

## B-27 — Human point-counting errors: undervaluing 10-of-trump in Hokm

**MISTAKE:** Saudi players commonly forget that the 10-of-trump (T-trump) scores only 10 points in Hokm — equal to a non-trump 10 — not as the dominant card its trick-rank (5th, above K) might imply. Players trade away T-trump cheaply for a side-suit ace because they over-rate its trick strength and under-rate its point value relative to the J (20), 9 (14), and A (11). The T-trump costs 10 points to lose but wins fewer tricks than the J or 9 in the endgame.

**FREQUENCY:** Common, particularly in informal games. Experienced players know T-trump's exact scoring but its anomalous position in the trick-rank table (`K.RANK_TRUMP_HOKM: T=5, above K=4 but below A=6, 9=7, J=8`) regularly confuses intermediate players.

**BOT EXPLOITS IT:** Indirectly. The bot's `suitStrengthAsTrump` function (`Bot.lua:298-332`) correctly weights T-trump at +10 and J at +20, 9 at +14. The `pickFollow` smother logic (`Bot.lua:936-959`) dumps A and T of the led suit onto partner's winning tricks to score those points — but this is suit-agnostic (it works the same whether the card is T-trump or T-side-suit). There is no explicit heuristic that says "apply pressure on the side suits to force a human to discard T-trump." The bot's `pickLead` function leads highest from free-trick suits (`Bot.lua:823-839`) and lowest from longest non-trump, which does not specifically target the scenario "lead a non-trump suit to drain human's side-suit holdings and force them to ruff with T-trump instead of a more valuable trump." The bot does not track opponent T-trump as a high-value card to flush.

**file:line:** `Constants.lua:42-51` (scoring tables `K.POINTS_TRUMP_HOKM`, `K.RANK_TRUMP_HOKM`), `Bot.lua:298-332` (`suitStrengthAsTrump`), `Bot.lua:820-892` (`pickLead`)

**FIX:** In M3lm or SaudiMaster tier, add a "T-trump flush" heuristic in `pickLead`: when the bot is on the bidder team and trump is NOT yet exhausted, if Bot._memory shows an opponent likely holds T-trump (i.e., T-trump not yet in `Bot._memory[opp].played` and not in bot's own hand), prefer leading a non-trump long suit to force that opponent to either follow (and not ruff with T-trump) or ruff with something. This is a narrow but real exploit of humans who over-ruff with T-trump when they should discard.

---

## B-28 — Human bid-round timing tells: slow human = marginal hand

**MISTAKE:** In human play, a seat that takes 40+ seconds to bid is typically on a borderline hand — they are counting cards and estimating suit strength, which takes time only when the hand is unclear. A fast bid (under 10 seconds) signals either a clear pass or a strong trump suit.

**FREQUENCY:** Very common behavioral tell in informal games. Experienced players exploit it in face-to-face settings; the mechanic is unknown to most casual players.

**BOT EXPLOITS IT:** No. The turn timer is `K.TURN_TIMEOUT_SEC = 60` (`Constants.lua:243`), armed via `N.StartTurnTimer` (`Net.lua:2729-2738`), but the elapsed time is stored only in the underlying `C_Timer.NewTimer` and is never exposed to the bot. There is no `s.turnStart`, no elapsed-time field in game state, and `Bot.PickBid` (`Bot.lua:540-656`) has no parameter for human elapsed time. The bot's bid strategy has zero awareness of how long a human took to bid. The `Bot._partnerStyle` ledger (`Bot.lua:136-197`) accumulates escalation and trump-tempo counters across the full game but does not record bid timing.

**file:line:** `Constants.lua:243` (`K.TURN_TIMEOUT_SEC`), `Net.lua:2729-2738` (`N.StartTurnTimer`), `Bot.lua:540-656` (`Bot.PickBid`), `Bot.lua:136-197` (`Bot._partnerStyle`)

**FIX:** In `N.StartTurnTimer`, record `s.turnStartTime = (GetTime and GetTime()) or 0` when arming a human bid timer. When the human bid arrives in `N._OnBid`, compute `elapsed = GetTime() - s.turnStartTime` and pass it (or a derived confidence bucket: "fast"/<10s, "normal"/10-30s, "slow"/>30s) into `Bot.OnBidObserved(seat, bid, elapsed)`. In `Bot.OnBidObserved`, update a new `_partnerStyle[seat].bidTempo` counter. In `Bot.PickDouble` / `Bot.PickTriple` (M3lm tier), consult `bidTempo` for the bidder: a slow bidder is more likely on a marginal Hokm hand, which is mildly exploitable by a defender deciding to Bel (lower threshold by 5-8 if bidder was slow and their team is not already ahead).
