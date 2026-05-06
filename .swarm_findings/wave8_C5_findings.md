# Wave 8 C5 — Final Cluster: Human Cultural & Situational Patterns

## B-95 — Human score-position signaling via bid aggressiveness

| Field | Detail |
|---|---|
| SIGNAL/MISTAKE | MISSING FEATURE — `scoreUrgency` reads only the bot's own team's cumulative score; it never reads OPPONENT cumulative to predict how urgently an opponent bidder will commit |
| FREQUENCY | Detectable across every round where the opponent team is behind by 60+ points (common in middle and late game) |
| BOT-EXPLOITS-IT | Not currently exploitable — the gap is real and directional. `scoreUrgency(myTeam)` at Bot.lua:443–453 reads `S.s.cumulative[myTeam]` and `S.s.cumulative[oppTeam]`, but it is only ever called with the bot's own team (`R.TeamOf(seat)`) as the argument — see Bot.lua:555, 1171, 1223, 1235, 1252, 1288. The result modulates the bot's OWN thresholds; it is never applied to model how aggressively an opponent is likely to bid. In `sampleConsistentDeal` (BotMaster.lua:124–274), opponent hand strength is biased only by bid type (Hokm vs Sun) via `getStrongCards(contract)` (BotMaster.lua:39–55); opponent score position is never used to tighten or widen the sampled trump distribution. A human bidder 60+ behind will commit to marginal Hokm and Sun bids at lower strength thresholds — the bot's world-sampler should reflect this by widening the trump-strength distribution for opponents in deficit, and the bot's own counter-play should adjust (e.g., more aggressive Bel because the opponent's contract is likely marginally made). |
| file:line | Bot.lua:443–453 (`scoreUrgency`, self-team only), BotMaster.lua:39–55 (`getStrongCards`, no score-urgency component), BotMaster.lua:213 (desire = bidder strong only) |
| fix | Add an `opponentUrgency(oppSeat)` helper in Bot.lua mirroring `scoreUrgency` but reading from the opponent's perspective. In `sampleConsistentDeal`, when computing `desire` for an opponent bidder seat, if `opponentUrgency` returns positive (opponent is desperate), extend the strong-card spread to include borderline trump cards (K/Q of trump at lower weights). Surface this urgency value in `Bot.PickDouble` to lower `BOT_BEL_TH` when the opponent contract is likely marginal due to their desperation bid. |

---

## B-96 — Human "show the Ace" culture: Aces played early

| Field | Detail |
|---|---|
| SIGNAL/MISTAKE | MISSING FEATURE — no Ace-exhaustion inference per opponent; `pickLead` does not model the window after which A-of-side-suits are cleared |
| FREQUENCY | Relevant from trick 4 onward in every game where at least one opponent played an Ace in tricks 1–3 |
| BOT-EXPLOITS-IT | Partially — but not by design. `Bot._memory[seat].played` (Bot.lua:204) tracks every observed card per seat, including Aces. `HighestUnplayedRank` (referenced in pickLead at Bot.lua:731–738) tracks the highest remaining rank per suit across all seats. If a human plays their side-suit Ace early, the bot will eventually register it via `Bot.OnPlayObserved` and `HighestUnplayedRank` will update. However there is no explicit "Ace exhaustion window" heuristic: the bot does not check "all side-suit Aces have been played by tricks 1–3" as a positive trigger to start aggressively pulling trump (knowing opponent ruff threats are reduced). `pickLead`'s bidder branch (Bot.lua:785–802) leads high trump unconditionally when `trumpCount >= 4`, regardless of whether opponent Ace threats have already been cashed. The cultural pattern produces an exploitable tell — opponents who played their off-suit Aces in tricks 1–3 have no high-point follow-up; the bot should capitalise by leading low in those suits to draw out weak cards, conserving trump instead of pulling it early. |
| file:line | Bot.lua:731–738 (`pickLead` HighestUnplayedRank gate), Bot.lua:785–802 (bidder trump-pull branch, no Ace-exhaustion gate), Bot.lua:200–204 (`OnPlayObserved`, played hash) |
| fix | In `pickLead`, after the `HighestUnplayedRank` boss-lead check, add an M3lm-gated "Ace-exhausted" check: iterate the four non-trump suits; for each suit where `Bot._memory` shows no opponent seat still holding an Ace (i.e., the Ace was observed played in a completed trick), mark that suit as "safe-to-lead low". In the bidder team branch, if all non-trump Aces have been cleared by trick 3, skip the high-trump pull in favour of cashing side-suit winners — the opponent ruff threat is gone. |

---

## B-97 — Human post-meld play pattern: declared sequences lead from that suit

| Field | Detail |
|---|---|
| SIGNAL/MISTAKE | MISSING FEATURE — declared meld cards are pinned correctly in the ISMCTS sampler (BotMaster.lua:160–177) but neither `pickLead` nor `pickFollow` reads an opponent's declared meld as a lead-intention signal |
| FREQUENCY | Every hand where an opponent declares a 3- or 4-sequence meld (seq3/seq4) and leads in tricks 2–4 |
| BOT-EXPLOITS-IT | Not exploitable — the meld-pin fix at BotMaster.lua:148–177 only prevents those meld cards from being redistributed across wrong seats during world-sampling; it does not read the meld as a LEAD-INTENTION signal. After meld declarations, `pickFollow` (Bot.lua:915–1068) makes no reference to `S.s.meldsByTeam`. If an opponent declared a Hearts sequence (7-8-9) in trick 1 and leads Hearts in trick 2, the bot will simply react on that trick as normal — it has no pre-emptive "expect Hearts lead" branch that causes it to void-prep (e.g., lead another suit to gain a void before the opponent's sequence runs). Similarly, `pickLead` has no "cover the declared meld suit" or "duck through the meld suit" branch. The bot cannot read the opponent's meld as foreshadowing of their trick-taking strategy, which a Saudi Master-level player explicitly would. |
| file:line | BotMaster.lua:160–177 (meld pinning, no lead-intent), Bot.lua:720–892 (`pickLead`, no meld-suit gate), Bot.lua:915–1068 (`pickFollow`, no meld-signal gate), `S.s.meldsByTeam` populated by State.lua:54 |
| fix | In `pickLead` (and in the defensive branch of `pickFollow` pos-2), add an Advanced-gated meld-intent reader: iterate `S.s.meldsByTeam` for the opponent team's entries; for any declared seq3/seq4/seq5 where the declarer has not yet exhausted that suit (checked via `Bot._memory[s].played` — if the sequence cards are not all in `played`, the run is still live), flag that suit as "likely opponent next lead". Use this to plan a void-before-sequence: if the bot has cards in that suit and can afford to discard them on earlier tricks, prefer doing so to prevent being end-played by the run. |

---

## B-98 — Human A-of-trump retention: last-trick guarantee

| Field | Detail |
|---|---|
| SIGNAL/MISTAKE | MISSING FEATURE — the ISMCTS rollout policy in BotMaster.lua contains a placeholder (`-- placeholder: lead high trump`) at BotMaster.lua:428 that does not model the endgame A-of-trump retention scenario |
| FREQUENCY | Deterministic scenario in every Hokm endgame where the bot team has spent J+9 and the opponent holds A-of-trump; affects approximately 20–30% of Hokm rounds that reach 6+ tricks |
| BOT-EXPLOITS-IT | Not exploitable — opponent A-of-trump retention after J+9 exhaustion is not modelled in either the heuristic or ISMCTS paths. In Hokm, the trick-rank order is J(8) > 9(7) > A(6) > T(5) > K(4) > Q(3) > 8(2) > 7(1) (Constants.lua:50: `K.RANK_TRUMP_HOKM`). Once J and 9 are gone, A-of-trump becomes the highest remaining trump and will win every trump trick. `pickFollow` at Bot.lua:978–990 checks `suitCardsOutstanding(hand, contract.trump)` to detect a "sure stopper" only when the bot HOLDS the trump card and `trumpOut <= 1`. There is no parallel check from the defender's perspective: "if opponent holds A-of-trump and J+9 are exhausted, they WILL win the last trump trick — do not try to draw trump; concede the last trick and focus on the `K.LAST_TRICK_BONUS = 10`." In the ISMCTS rollout, the heuristic at BotMaster.lua:428 (`highestRank(legal)` placeholder) does not weight the A-of-trump's post-J+9 lock differently. The rollout can simulate the bot leading into a guaranteed opponent A-of-trump loss without penalty adjustment, undervaluing the risk. |
| file:line | BotMaster.lua:426–432 (rollout lead heuristic, placeholder comment), Bot.lua:978–990 (`pickFollow` pos-2 sure-stopper, bot-held only), Constants.lua:50 (`K.RANK_TRUMP_HOKM` — A rank 6, below J=8 and 9=7), Rules.lua:34–59 (`CurrentTrickWinner`) |
| fix | In `pickLead` (bidder branch), add a post-J+9 Ace-of-trump detection gate: count remaining unplayed trump cards via `suitCardsOutstanding`; if J and 9 are both gone (confirmed via `Bot._memory`) and any opponent seat has not been confirmed void in trump, treat the situation as "opponent likely holds A-of-trump — stop trump pulls, redirect to cashing non-trump winners". In the ISMCTS rollout at BotMaster.lua:424–436, replace the `highestRank(legal)` placeholder with a check: if the highest remaining trump is the A (J and 9 absent from the unseen pool), deprioritise leading trump in the rollout simulation to prevent over-attributing last-trick bonus to trump leads. |

---

## B-99 — Human hesitation on Kawesh call: missed Kawesh inference

| Field | Detail |
|---|---|
| SIGNAL/MISTAKE | MISSING FEATURE — after tricks 1–3 complete with no Ace won by an opponent, the bot cannot infer "opponent may have had a Kawesh-eligible hand and didn't call it", which would indicate the opponent has no Aces in their 8-card hand |
| FREQUENCY | Rare but decisive: a missed-Kawesh opponent hand has zero Aces and no Trump-rank honors; the bot's world-sampler currently cannot account for this class of hand |
| BOT-EXPLOITS-IT | Not exploitable in current code. `Bot.PickKawesh(seat)` at Bot.lua:1302–1308 correctly calls Kawesh for bot seats with an all-7/8/9 five-card hand. `C.IsKaweshHand(hand)` at Cards.lua:164–170 checks that all cards are rank 7, 8, or 9. However, there is no inference path in `Bot._memory` or `BotMaster.sampleConsistentDeal` that models the case where an opponent plays their first three tricks with cards that are consistent with a Kawesh-eligible first hand (all 7/8/9 in 5 cards) but never called it. Concretely: if after tricks 1–3 an opponent seat has zero Ace wins, zero 10-point card wins, and three 7/8/9 cards observed in `Bot._memory[s].played`, the bot can infer with moderate confidence that the opponent's first five cards were all 7/8/9 (Kawesh-eligible but uncalled). This means the opponent's remaining 3 cards (dealt in round 2) may be similarly low-ranked. The world-sampler at BotMaster.lua:196–248 never adjusts the `desire` or void-constraint map for this class of opponent, so it continues sampling as if any card could be in their hand. |
| file:line | Bot.lua:1302–1308 (`PickKawesh`, own-seat only), Cards.lua:164–170 (`IsKaweshHand`), BotMaster.lua:196–248 (`sampleConsistentDeal`, no Kawesh-inference branch), Bot.lua:95–116 (`emptyMemory`, no Kawesh-inference field) |
| fix | In `Bot.OnPlayObserved`, after updating `mem.played`, add an M3lm-gated check for seats that are not the bot's team: if `#(tricks completed) <= 3` and all cards observed from that seat so far are rank 7, 8, or 9, set a new `mem.likelyKawesh = true` flag. In `sampleConsistentDeal`, when building the `desire` map for a seat with `likelyKawesh = true`, zero out strong-card weights (Aces, Tens, face cards) for that seat's desire pool and add low-rank soft constraints — reducing the probability of sampling high-honor cards into that hand. This would not change the validity check for an actual Kawesh call, only the ISMCTS hand distribution inference. |
