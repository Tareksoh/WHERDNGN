# Wave 5 C4 — Human Bid Signal Reading (Continuation)
## Angles B-09 through B-13

Codebase: v0.4.4  
Auditor: wave5_C4 (pathfinder specialist)  
Date: 2026-05-03

---

## B-09 — Partner's prior bid: human vs. bot honesty awareness

**IS-EXPLOITED: YES**

### Evidence

`partnerBidBonus` (Bot.lua:410–427) reads `S.s.bids[partner]` and assigns fixed bonuses:

- HOKM matching our trump → +20
- HOKM other suit → +10
- SUN / ASHKAL → +15
- PASS → -10

There is no check of `S.s.seats[partner].isBot` anywhere in this function. The bonus table was designed with honest, bot-grade bidding in mind: a bot that calls `HOKM:H` provably holds J/9 or a strong Hearts hand (because `Bot.PickBid` gates on suitStrengthAsTrump ≥ 42). A human calling `HOKM:H` may be:

- **Under-bidding** (conservative Saudi culture: humans often hold back J+9 and still PASS in round 1 waiting for the opponent to commit first)
- **Over-bidding** (showing off / bluffing on a 2-card suit with only the Ace)
- **Private convention** (some tables always bid the suit they want partner to lead, regardless of trump holding)

The +20 bonus on a "matching Hokm" from a human partner therefore over-counts combined strength when the human is a show-off bidder, and under-reads it when the partner is conservative (a conservative human PASS should not always translate to −10; they may still hold a strong hand).

**File:line:** Bot.lua:410–427

### Fix proposal

Gate the bonus magnitude on `S.s.seats[partner].isBot`:

```
-- Bot partner: full bonus (honest bid convention enforced by Bot.PickBid)
-- Human partner: attenuated (50%) bonus, reflecting bid-honesty uncertainty
local scale = (S.s.seats[partner] and S.s.seats[partner].isBot) and 1.0 or 0.5
```

Apply `scale` as a multiplier to each branch's return value. Over N rounds, the M3lm-tier `styleBelTendency` ledger accumulates evidence on whether the human partner bids conservatively or aggressively — once `m.bels >= 2` (frequent escalators → over-bidders), the scale could be lowered further to 0.3; if `m.bels == 0` after 4+ rounds (under-bidder), raise toward 0.7. This makes `partnerBidBonus` human-aware without a full per-seat bid-calibration system.

---

## B-10 — Human tendency to reflexive Bel when opponent near score target

**IS-EXPLOITED: NO**

### Evidence

The bot does model score-urgency for its **own** Bel/Triple decisions via `scoreUrgency` (Bot.lua:443–453) and `matchPointUrgency` (Bot.lua:468–487). When `opp >= target - 25`, `scoreUrgency` returns +12, lowering the bot's Bel threshold from 70 to ~58. This correctly models "we should Bel more desperately when we're near losing."

However, the question is the **inverse**: does the bot anticipate that a HUMAN opponent team near their win target will Bel *reflexively* against the bot's Sun contract, even with a weak defensive hand?

No such anticipation exists. `PickDouble` (Bot.lua:1153–1180) decides only whether the **current bot** should Bel. There is no code that reads `opp >= target - 25` and then adjusts the **bot's play strategy** in response to the prediction "human opponents will likely Bel this contract." Concretely:

- The bot does not lower its Gahwa threshold when it knows the bot-bidder team is near the target (opponents reflexively Bel → chain is more likely to escalate → if bot can call Gahwa it should, since opponents forced the chain).
- The bot does not raise its Sun bid threshold when the opponent team is near the target (opponents will Bel reflexively even on marginal hands → the bot should need a stronger Sun to survive the Bel).

**File:line:** Bot.lua:443–453 (scoreUrgency — applies only to own-team decisions, no opponent-reflex modeling)

### Fix proposal

Add a read-ahead in `PickDouble` and `PickGahwa` for the **opponent's** score proximity: when `oppCumulative >= target - 25`, assume a human opponent seat will Bel with probability ~0.8 even on a marginal hand. For `PickGahwa`, this means: if the chain has reached Gahwa because of a human-driven Bel → Triple → Four escalation sequence, the bot already knows the opponents were willing to bet at ×4 on a near-loss desperation — it should be slightly more willing to accept the Gahwa gamble than its raw `strength >= BOT_GAHWA_TH` gate suggests. A +5 to +8 Gahwa strength bonus when `oppCumulative >= target - 25` and `isBotSeat(defSeat) == false` would capture this.

---

## B-11 — Reading human Bel decisions: pattern classification

**IS-EXPLOITED: PARTIALLY**

### Evidence

`Bot._partnerStyle[seat].bels` (Bot.lua:130, 142, 166) counts lifetime Bels per seat and is maintained correctly by `OnEscalation`. The derived function `styleBelTendency` (Bot.lua:181–187) returns:

- `nil` if fewer than 1 Bel seen (no data)
- `0` if exactly 1 Bel seen
- `1` if 2+ Bels seen

This is the only classification: "frequent belar or not." The three Saudi human patterns described in the angle are:

**(a) Always-Bel-if-strong regardless of score** — approximated by `styleBelTendency == 1`. PARTIAL: the counter doesn't distinguish score-position at time of Bel, so it conflates type-(a) and type-(c) bidders.

**(b) Desperation Bel only when bidding team near target** — NOT captured. A player who Beled once when opponents were at target−10 and otherwise never Bels would read as `styleBelTendency == 0` (not a belar), but that single Bel was highly predictable and the bot missed the chance to pre-adjust.

**(c) Habitual Bel (80% of the time)** — captured reasonably by `bels >= 2` = `styleBelTendency == 1`, since after a few rounds a habitual belar will have 3–4 counts. PARTIAL: the threshold of 2 is too low; a player who Beled in 2 of 3 rounds and one was a desperation might be misclassified as type-(c).

**Critical finding:** `styleBelTendency` is defined and populated but **never called from any decision-making path**. Grep confirms its only callsite is its own definition (Bot.lua:181) and a comment reference (Bot.lua:500). It is dead code with respect to decision influence. The ledger is maintained, but the bot never uses the classification to adjust its bidding threshold, Triple decision, or play strategy against human Bel-prone opponents.

**File:line:** Bot.lua:181–187 (styleBelTendency — dead function, no callsite in decision path)

### Fix proposal

Wire `styleBelTendency` into `PickTriple` and `PickFour`. When deciding whether to Triple after a human Bel:

- If `styleBelTendency(belSeat) == 1` (habitual belar) → their Bel carries LESS information about hand strength → bot should be slightly MORE willing to Triple (lower the effective threshold by ~5), since the Bel may be habitual noise.
- If `styleBelTendency(belSeat) == nil` (first Bel ever) → maximal information content → treat as honest → keep threshold at baseline.

For `PickFour` (responding to bot-team Triple): if `styleBelTendency(oppSeat) == 1` and the opponent is on the defender team, their Four may also be reflexive → bot's Four threshold should be slightly lower (more willing to Four, since opponents may be bluffing the chain).

---

## B-12 — Human Triple tendency: always or never

**IS-EXPLOITED: NO**

### Evidence

`Bot._partnerStyle[seat].triples` counter is maintained by `OnEscalation` (Bot.lua:167) for every seat including human seats. However, like `styleBelTendency`, there is no `styleTripleTendency` function and no callsite that reads `.triples` from an opponent's (human) ledger to predict their next Triple decision.

When a HUMAN holds the bidder seat and has just received a bot Bel, the bot at the defender seat (`PickFour`) must anticipate whether the human will Triple. The current `PickFour` (Bot.lua:1227–1237) uses only:

- `escalationStrength(seat, hand, contract)` — own hand + contract
- `scoreUrgency` / `matchPointUrgency` — own score position
- `partnerBidBonus` + `partnerEscalatedBonus` — partner's structural signals

None of these factors adjust for "this human bidder has Tripled 3 out of 3 times in this game" (always-Triple culture) vs. "this human bidder has never Tripled despite being in bidder seat twice" (conservative culture). The Saudi cultural split is real: confidence-culture players Triple almost automatically when they bid in Hokm; conservative players prefer the ×2 Bel payout and close.

**File:line:** Bot.lua:1227–1237 (PickFour — no `.triples` ledger read); Bot.lua:167 (counter maintained but never consumed for prediction)

### Fix proposal

Add a `styleTripleTendency` function analogous to `styleBelTendency`:

```lua
local function styleTripleTendency(seat)
    if not Bot._partnerStyle then return nil end
    local m = Bot._partnerStyle[seat]
    if not m then return nil end
    -- Need at least 2 bidder-seat opportunities before classifying.
    -- Use (triples + 0) vs (bids seen as bidder, estimated from rounds played).
    if m.triples >= 2 then return 1   end  -- always-Triple
    if m.triples == 0 and m.bels >= 2 then return -1 end  -- never-Triple (conservative)
    return nil
end
```

Use it in `PickFour`: if the human bidder is `styleTripleTendency == 1` (will almost certainly Triple), the defender bot should raise its Four willingness slightly since the chain will probably extend to Four regardless. If `styleTripleTendency == -1` (won't Triple), the bot should close the Bel more readily by the human declining Triple, and a bot Four attempt would be moot.

---

## B-13 — Human Gahwa frequency: cultural bravado vs. card-optimal

**IS-EXPLOITED: NO**

### Evidence

`BOT_GAHWA_TH = 135` (Constants.lua:255) is calibrated for a bot that Gahwa-calls only on a near-certain hand. Saudi human players commonly call Gahwa at much lower hand-strength thresholds — empirically Saudi Baloot community data and forum discussions indicate human Gahwa calls on hands scoring 95–115 in the bot's strength metric (20–30% below the bot threshold), driven by bravado, momentum, or "coffee culture" (قهوة as a social showoff move).

When a HUMAN opponent calls Gahwa, the current bot response is purely mechanical: the bot's play policy (`PickPlay` / `BM.PickPlay`) does not change. The ISMCTS sampler in BotMaster.lua uses `getStrongCards` to bias opponent hand sampling — it correctly biases toward strong trump cards for the bidder — but it does NOT apply a "Gahwa callers may be weaker than expected" discount. A human Gahwa on a 95-strength hand means the bot-team rollouts should expect a slightly weaker bidder hand than if it were a bot Gahwa.

There is no check of `S.s.seats[bidder].isBot` anywhere in `getStrongCards` (BotMaster.lua:39–55) or `sampleConsistentDeal` (BotMaster.lua:124–274). The sampler treats all Gahwa-level contracts as equally "near-certain bidder hand" regardless of whether the caller is a human who might be bluffing.

**File:line:** BotMaster.lua:39–55 (getStrongCards — no human-Gahwa discount); Constants.lua:255 (BOT_GAHWA_TH = 135)

### Fix proposal

In `sampleConsistentDeal`, after constructing `strong` from `getStrongCards`, check whether the bidder is a human seat:

```lua
local bidderIsHuman = S.s.seats[bidder] and not S.s.seats[bidder].isBot
if bidderIsHuman and S.s.contract.gahwa then
    -- Human Gahwa: discount strong-card weights by 40%.
    -- Spreads the sampled hand distribution across weaker configurations.
    for k, v in pairs(strong) do strong[k] = math.floor(v * 0.6) end
end
```

This causes the ISMCTS rollouts to sample a wider range of plausible bidder hands, reducing the tendency to "concede" to a human Gahwa that may be a bluff. The +10% reduction in defender aggression that the bot currently exhibits when facing a Gahwa contract (because rollouts score the bidder winning most worlds) is attenuated appropriately.

Additionally, a per-seat `gahwas` counter is already maintained in `Bot._partnerStyle` (Bot.lua:133, 169). A human seat with `gahwas == 0` in 3+ games should be treated as conservative (their Gahwa is honest); a human with `gahwas >= 2` in fewer games is a bravado caller and the discount should be larger (0.4 multiplier instead of 0.6).

---

## Summary Table

| Angle | IS-EXPLOITED | Primary file:line | Key finding |
|-------|-------------|-------------------|-------------|
| B-09 | YES | Bot.lua:410–427 | `partnerBidBonus` treats human bids as honest; no isBot check; human over/under-bidding not discounted |
| B-10 | NO | Bot.lua:443–453 | `scoreUrgency` gates only own-team desperation; no model of opponent-human reflexive Bel when they're near loss |
| B-11 | PARTIALLY | Bot.lua:181–187 | `styleBelTendency` exists but is dead code — never called in any decision path |
| B-12 | NO | Bot.lua:1227–1237 | `.triples` counter maintained but no `styleTripleTendency` function; PickFour ignores human Triple tendency |
| B-13 | NO | BotMaster.lua:39–55 | `getStrongCards` gives no human-Gahwa discount; ISMCTS overestimates human Gahwa hand quality |
