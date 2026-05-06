# Wave 5 C3 — Human Bid Signal Reading Findings
**Auditor:** C3 (human bid signal reading)
**Version:** v0.4.4
**Files reviewed:** Bot.lua, BotMaster.lua, Net.lua, Constants.lua, Rules.lua
**Angles:** B-04 through B-08

---

## Summary Table

| Angle | IS-EXPLOITED | Severity | Primary File:Line |
|-------|-------------|----------|------------------|
| B-04: Dealer (seat 4) position bias on Hokm bid | NO | Medium | Bot.lua:540–636 |
| B-05: Human R2 over-bidding on marginal hands | NO | Medium | Bot.lua:540–636 |
| B-06: Human double-pass as weakness signal | PARTIALLY | Low | Bot.lua:410–427 |
| B-07: Partner Ashkal as combined-strength indicator | PARTIALLY | Low | Bot.lua:410–427 |
| B-08: Preempt declination as weakness signal | NO | Medium | Bot.lua:1261–1292 |

---

## B-04 — Human Bidding Seat-4 Position Bias

### IS-EXPLOITED: NO

### Evidence

`Bot.PickBid` (Bot.lua:540–656) computes bidding thresholds from `suitStrengthAsTrump`, `sunStrength`, `scoreUrgency`, and `matchPointUrgency`. None of these functions accepts a seat-position argument. The only place seat position is consulted during bidding is the Ashkal-eligibility check (Bot.lua:593–603):

```lua
local bidPos = 0
if S.s.dealer then
    local d = S.s.dealer
    local order = {
        (d % 4) + 1, ((d + 1) % 4) + 1,
        ((d + 2) % 4) + 1, d,
    }
    for i, st in ipairs(order) do
        if st == seat then bidPos = i; break end
    end
end
if bidPos >= 3 ...  -- Ashkal eligibility gate only
```

This `bidPos` is checked only to gate Ashkal access (positions 3 and 4 in bid order). It is never used to calibrate the bot's READ of a human opponent's Hokm bid. When reading a human's bid in `partnerBidBonus` (Bot.lua:410–427), no position information is consulted — partner's bid is classified purely as HOKM/SUN/ASHKAL/PASS with no weight for which bid-order position the human occupied.

### Saudi Baloot Literature Context

In tournament Saudi Baloot, the dealer bids last (seat 4 in bid order) and has maximum information: all three prior bids are visible before committing. A seat-4 Hokm bid therefore has an asymmetrically lower information threshold than a seat-1 Hokm bid. Human players in seat 4 routinely bid Hokm on strength that a seat-1 player would pass, because seat 4 knows the flipped suit is still available and can commit without risk of being overcalled. Conversely, a seat-1 Hokm bid from a human is a strong commitment made with zero positional information — it signals a structurally sound hand.

The bot treats both identically in `partnerBidBonus`: any partner HOKM bid returns +10 (other suit) or +20 (matching trump), regardless of whether it came from an information-rich dealer position or an information-blind seat-1 opener. The ISMCTS sampler in `BotMaster.lua` also ignores this: `sampleConsistentDeal` (BotMaster.lua:124–274) assigns the `strong` weight table to the `bidder` seat uniformly without scaling by bid-order position.

### Fix Proposal

Add a `bidPositionFactor(bidderSeat)` helper that returns 1.0 for seat-1 bids (full commitment), 0.85 for seat-2, 0.75 for seat-3, and 0.65 for seat-4 (information-rich, lower bar). Multiply the `partnerBidBonus` return by this factor when the partner is the contract bidder. In `BotMaster.sampleConsistentDeal`, scale the `strong` card-weight for the bidder seat by the same factor so determinizations give seat-4 bidders a wider range of plausible trump holdings. Gate the entire adjustment on `Bot.IsAdvanced()`.

---

## B-05 — Human R2 Over-bidding on Marginal Hands (Avoiding Ashkal)

### IS-EXPLOITED: NO

### Evidence

The bot does not apply any expanded uncertainty band to R2 Hokm bids from human opponents. `partnerBidBonus` (Bot.lua:410–427) returns the same flat bonuses for HOKM bids regardless of whether the bid occurred in round 1 or round 2. The bid round is recorded in `S.s.bidRound` and is available at call time, but is never consulted by `partnerBidBonus` or by `BotMaster.sampleConsistentDeal`.

The round-2 path in `Bot.PickBid` (Bot.lua:639–656) does apply a stricter threshold for the bot's OWN bids:

```lua
if Bot.IsAdvanced() then r2Base = math.max(r2Base, r1Base - 4) end
local thHokmR2 = jitter(r2Base - urgency, BID_JITTER)
```

This logic correctly models that the bot should not over-bid marginally in R2 — but it is only applied to the bot's own bidding decision. The corresponding READ of a human R2 bid carries no equivalent uncertainty expansion.

### Saudi Baloot Literature Context

In competitive Saudi Baloot, R2 Hokm is commonly used as an escape valve against Ashkal exposure. A human holding a suit of marginal strength (composite score 30–38 in the codebase's formula) will frequently commit Hokm in R2 on that suit rather than pass and risk an opponent calling Ashkal on their partner, which would force a Sun contract at higher multiplier. The practical effect is that human R2 Hokm bids cover a wider hand-quality range than R1 Hokm bids. The bot's ISMCTS sampler (BotMaster.lua:213) weights the bidder's sampled hand uniformly toward `strong` cards regardless of round, overestimating the human bidder's trump quality when the bid was a defensive R2 commitment on a 30–38-strength suit.

### Fix Proposal

In `partnerBidBonus`, detect whether the partner's bid was made in round 1 or round 2 by checking `S.s.bidRound` at the time the bid was stored (store bid round alongside bid in state), or by post-processing `S.s.bids` against a round-tracker. Reduce the HOKM partner bonus by 30% when the bid was R2 (e.g., return 14 instead of 20 for matching-trump R2 HOKM). In `BotMaster.sampleConsistentDeal`, reduce the `strong` weight table's trump probabilities by 25% for R2 Hokm bidders. Gate on `Bot.IsM3lm()` since this requires per-round bid tracking.

---

## B-06 — Human Double-Pass as Weakness Signal

### IS-EXPLOITED: PARTIALLY

### Evidence

`partnerBidBonus` (Bot.lua:410–427) does detect a partner PASS and penalizes it:

```lua
if b == K.BID_PASS then return -10 end
```

However, `S.s.bids[partner]` stores only one bid per seat — the last resolved bid. Because both rounds write to the same `s.bids[seat]` slot (State.lua:838: `s.bids[seat] = bid`), by the time escalation decisions are made, a double-passer (pass R1 + pass R2) and a single-passer (pass R1 only; no R2 chance because contract was decided in R1) both appear as `BID_PASS` in the table. The bot correctly applies -10 in both cases.

The partial exploit gap is this: the bot reads PARTNER's pass but has no mechanism to read OPPONENT seats' pass patterns. `partnerBidBonus` is called as `partnerBidBonus(seat, contract)` and internally uses `R.Partner(seat)` — it only reads the bidding partner's bid, never the opponents' bids. If both opponents double-passed, that is a structural signal that neither opponent held a bidable hand, which should make the bot's own Sun or Hokm contract more likely to succeed (reduced trump threat from opponents). This inference is unused.

The trap-pass concern (a human deliberately passing a strong hand to force opponents into bad contracts) is architecturally unresolvable from observed bids alone — it requires behavioral modeling beyond what `partnerBidBonus` or `_partnerStyle` currently capture.

### Saudi Baloot Literature Context

A human double-pass is a strong weakness signal in Saudi tournament play. Because R2 allows suit choice, a competent player will almost always find a biddable suit in R2 if they hold J+9 or 9+A or 3+ side aces. A double-pass indicates none of these combinations are present. In practical terms, a double-passer from the opponent team means the bot's bidder faces a weaker defense than average. The bot should bid slightly more aggressively and favor Bel/Triple escalation when both opposing seats double-passed.

### Fix Proposal

Extend `partnerBidBonus` (or create a separate `opponentBidContext(seat)` function gated on `Bot.IsM3lm()`) that also inspects the two opponent seats' bids. If both opponents have `BID_PASS`, return a positive strength bonus (+5 to +8) representing reduced defensive threat. This does not require round-tracking — any PASS from an opponent implies at minimum a sub-threshold hand. Apply this modifier in `escalationStrength` (Bot.lua:1191–1200) so it influences Bel/Triple/Four decisions, not just initial bidding.

---

## B-07 — Partner Ashkal as Combined Strength Indicator

### IS-EXPLOITED: PARTIALLY

### Evidence

`partnerBidBonus` (Bot.lua:416–417) does treat partner Ashkal identically to partner Sun:

```lua
if b == K.BID_SUN then return 15 end
if b == K.BID_ASHKAL then return 15 end
```

The +15 is applied in escalation decisions (`escalationStrength`, Bot.lua:1198) and in Bel/Triple/Four/Gahwa pickers via `PickDouble` (Bot.lua:1169), `PickTriple/Four/Gahwa` (Bot.lua:1223, 1235, 1252). So the basic "partner is Ashkal-strong" signal is correctly exploited for escalation.

The gap is in PLAY behavior after the contract begins. The prompt asks whether the bot plays more aggressively — "leading trumped suits earlier, taking tempo risks" — when partner confirmed side-suit solidity via Ashkal. The bot's play logic in `pickLead` (Bot.lua:720–892) and `pickFollow` (Bot.lua:915–1069) does not consult `S.s.bids` at all. The Ashkal partner signal is only used for bidding/escalation strength computation; it is never transmitted into the play decision layer.

Concretely: when a partner bid Ashkal (meaning they hold Sun-level strength, Sun >= 65 per `BOT_ASHKAL_TH`), the bot should know partner is holding multiple side-suit Aces/Tens and can be trusted to cover non-trump leads. This should push the bot toward more aggressive trump tempo (lead trump earlier to draw opponents' trump, then partner cashes side-suit winners). Currently `pickLead` treats a game with an Ashkal-bidding partner identically to one with an unknown partner.

Additionally, `BotMaster.sampleConsistentDeal` (BotMaster.lua:213–214) gives partner a signal-suit weight from `pSignalSuit` (firstDiscard) but does NOT give partner a boosted probability of holding high cards (A/T across suits) when partner bid Ashkal. The sampler's partner model is entirely play-signal-based, missing the stronger pre-game bid signal.

### Saudi Baloot Literature Context

In Saudi Master-tier Baloot, an Ashkal bid is a high-bar commitment (Sun >= 65 in this codebase's formula, equivalent to holding 3+ Aces or Ace-Ten pairs across 3+ suits). This is strong enough that partner can confidently lead trump early in Hokm without fear of stranding partner in a losing side-suit position — partner will cover with their Aces/Tens. Tournament play specifically exploits this: bidder of Hokm leads trump aggressively when Ashkal was called, because partner's Ashkal confirms sufficient side-suit depth to survive the early trump extraction.

### Fix Proposal

In `pickLead` (Bot.lua:720, gated on `Bot.IsM3lm()`): check `S.s.bids[R.Partner(seat)]` and if equal to `K.BID_ASHKAL`, boost trump-lead priority. Specifically, reduce the trump-poor threshold for early trump draw from 4 cards to 3 cards (Bot.lua:793: `if Bot.IsAdvanced() and trumpCount < 4` becomes `< 3` when partner Ashkaled). In `BotMaster.sampleConsistentDeal`, when `partner` seat has `S.s.bids[partner] == K.BID_ASHKAL`, add side-suit Ace and Ten cards to the partner's `desire` table (weight ~25 each, similar to how bidder gets trump strong cards) so the sampler correctly models Ashkal-partner's hand distribution.

---

## B-08 — Preempt Declination as Weakness Signal

### IS-EXPLOITED: NO

### Evidence

`Bot.PickPreempt` (Bot.lua:1261–1292) decides whether a bot seat claims the preempt window. The function evaluates own `sunStrength` plus partner-bid bonuses and score-urgency modifiers. The result (claim or pass) is broadcast via `N.SendPreempt` / `N.SendPreemptPass`, and `S.ApplyPreemptPass` removes the seat from `s.preemptEligible` (State.lua:1567–1572).

Once the preempt window closes (all eligible seats passed), `S.s.preemptEligible` is set to nil (State.lua:1571–1572). There is no recording of WHICH seats declined and no flag persisted to indicate "seat X was eligible and declined." The play layer — `pickLead`, `pickFollow`, `Bot.PickDouble/Triple` — has no mechanism to query whether a human seat declined a preempt opportunity during the bidding phase.

The ISMCTS sampler in `BotMaster.sampleConsistentDeal` likewise does not consult preempt history. The `seatHandSize`, `buildUnseen`, and `sampleConsistentDeal` functions operate on `S.s.tricks`, `S.s.hostHands`, and `S.s.bids` — none of which capture preempt pass decisions.

The theoretical exploit: per `Bot.PickPreempt`'s own threshold (BOT_PREEMPT_TH = 75), a bot passes the preempt only when its Sun strength is below 75. A human seat that declined preempt on an Ace bid-card therefore signals Sun < 75 for that seat, which is actionable: the bot facing that seat in play knows their trump-and-side-suit depth is limited, making the opponent a weaker Bel threat and a weaker defender in Sun contracts.

### Saudi Baloot Literature Context

In Saudi tournament play, the preempt (الثالث) is a significant commitment — an earlier seat claiming the Sun contract on an Ace bid-card is asserting Sun strength >= threshold against a known bidder. A pass in the preempt window is therefore a bounded weakness signal: the passing seat either lacked sufficient Sun strength or strategically deferred. Since the preempt threshold is well-known among experienced players, a declination can be treated as confirming the passing seat's hand is below that Sun threshold. This is a useful calibration signal for subsequent escalation decisions.

### Fix Proposal

In `Bot.OnPlayObserved` or a new `Bot.OnPreemptObserved(seat, claimed)` hook called from `N._OnPreemptPass` / `N.LocalPreemptPass`, record per-seat preempt decisions into `Bot._memory[seat]` as a new `preemptPassed = true` flag (set when seat declined while eligible). Gate on `Bot.IsM3lm()`. Consume this flag in `escalationStrength` (Bot.lua:1191–1200): when evaluating whether to Bel against opponents who both declined preempt, add +5 to the bot's effective strength (their Sun floor is constrained). In `BotMaster.sampleConsistentDeal`, exclude high-Sun-value cards (multiple Aces across suits) from the `desire` weight for seats flagged `preemptPassed` — those seats statistically hold fewer side-suit Aces.

---

## Cross-Cutting Observations

**Bid round not stored alongside bid value:** The most impactful single fix enabling B-04, B-05, and B-08 is persisting the round number when a bid is recorded. Currently `s.bids[seat] = bid` (State.lua:838) stores only the bid string. Adding a parallel `s.bidRounds[seat] = bidRound` would enable B-05's R2 uncertainty expansion and partially enable B-04's position-weight calculation. This is a one-line State.lua addition with no breaking changes.

**partnerBidBonus only reads partner, never opponents:** Angles B-06 and B-07 both suffer from the fact that `partnerBidBonus` is defined to read only `R.Partner(seat)`. A small refactor to an `allBidContext(seat)` function that returns both a partner-inferred bonus and an opponent-inferred modifier would enable B-06's double-pass exploitation and could be reused in B-08's preempt-pass flag consumption.

**ISMCTS sampler (BotMaster) is the highest-leverage improvement target for B-04, B-05, B-07:** All three angles involve the sampler assigning unrealistically uniform strong-card probability to the bidder (B-04), overestimating trump quality for R2 bids (B-05), and missing Ashkal-partner side-suit depth (B-07). These are all adjustments to the `desire` table in `sampleConsistentDeal` — a concentrated fix area with high payoff for Saudi Master tier.

---

## Sources

- [Baloot — card game rules (Pagat)](https://www.pagat.com/jass/baloot.html)
- [Baloot — Wikipedia](https://en.wikipedia.org/wiki/Baloot)
- [Baloot Rules — Jawaker](https://www.jawaker.com/en/rules/baloot)
