# Wave 2 Cluster C2 — Sun Bid Threshold Calibration
**Auditor:** C2 code-review agent  
**Version audited:** v0.4.4  
**Scope file:** wave2_C2_sun_bid_thresholds_prompt.md  
**Date:** 2026-05-03

---

## A-03 — TH_SUN_BASE = 50 vs. actual Sun win probability

**VERDICT: WARNING**

**File:line:** `Bot.lua:37` (TH_SUN_BASE), `Constants.lua:55` (K.HAND_TOTAL_SUN = 130)

**Evidence:**

The Sun declarer must capture strictly more than 50% of trick-points to make the contract (65+ of 130 pre-multiplier; the ×2 MULT_SUN fires regardless of outcome). The `sunStrength()` function scores only the *bidder's* 5-card deal1 hand (cards drawn from a point-max of 120 raw across all four suits, plus an 8-card final deal). After deal1 the bot holds exactly 5 cards.

A maximally-scored 5-card deal1 hand in Sun would be A+T of one suit (21) + A+T of another (21) + A of a third (11) = 53 raw. That hand easily crosses TH_SUN_BASE=50 and is in fact a reliable Sun hand: three Aces plus two Tens gives solid coverage of 3/4 suits and represents ~31 of the 120 card points. However, a hand of A+T+K+Q+J (11+10+4+3+2=30) also crosses 50 and is a realistic deal1 combination. That hand has all points concentrated in one suit, is void in three suits, and is a structurally dangerous Sun bid even after the Advanced distribution penalty (which caps at 18 raw off: 30 - 18 = 12, still below 50 — actually this combination *would not* cross 50 after penalties in Advanced mode).

The structural concern is the *basic-mode* path (Advanced off): the distribution penalty is skipped entirely. In basic mode a player with A+T+K in one suit plus J+Q in another (11+10+4+3+2=30, below 50) does not bid Sun — fine. But a hand with A+T in two suits plus a King elsewhere (11+10+11+10+4=46, below 50) also passes. The floor is reasonable. The real risk is jitter: TH_SUN_BASE - urgency - jitter can pull the effective threshold as low as 50 - 12 (desperate urgency) - 6 (BID_JITTER) = 32. At 32 virtually any hand with two Aces crosses the bar. The desperation path is the calibration hazard, not the base value itself.

**Tuning recommendation:** TH_SUN_BASE = 50 is appropriate for basic-mode mid-game play. The urgency modifier (+12 desperate, +6 far-behind) combined with BID_JITTER=6 can compress the effective floor to ~32 in worst-case, which is too low. Cap the urgency contribution to Sun bidding at +8 (vs. +12+6 for Hokm escalation, where the ×2 multiplier is not in play). Alternatively, add a Sun-specific floor: `thSun = math.max(thSun, TH_SUN_BASE - 10)`. No change to TH_SUN_BASE itself. **Recommendation: ±0 on TH_SUN_BASE; add floor of TH_SUN_BASE - 10 to the computed thSun.**

---

## A-06 — sideSuitAceBonus cap at 3 aces × 8 = 24 points

**VERDICT: WARNING**

**File:line:** `Bot.lua:337-345`

**Evidence:**

```lua
local function sideSuitAceBonus(hand, trumpSuit)
    if not Bot.IsAdvanced() then return 0 end
    local n = 0
    for _, card in ipairs(hand) do
        if C.Rank(card) == "A" and C.Suit(card) ~= trumpSuit then
            n = n + 1
        end
    end
    return math.min(n, 3) * 8
end
```

The function is documented as a *Hokm* heuristic: "outside-trump aces are tricks the bidder can typically capture before being trumped out." The 4th Ace is implicitly the trump Ace and is already counted by `suitStrengthAsTrump` (A=+11 in that function). The cap at 3 therefore prevents double-counting the trump Ace. This logic is sound for Hokm.

The problem: the function is also called in round-2 Sun bidding (`Bot.lua:645`, `s = s + sideSuitAceBonus(hand, suit)` where `suit` is the best non-flipped Hokm candidate). In the Sun evaluation path, no suit is trump; outside aces in Sun are not "before being trumped out" — every Ace is a winner in Sun unless the opponents hold all smaller cards and trump falls first. The function's assumptions break down in this dual-use. A player holding A+A+A in three suits in a Sun bid would get +24 bonus in `sunStrength()` *plus* the 3×11=33 from the direct A-scoring in `sunStrength`, for a combined 57 from three Aces alone — that is fine, but the ace bonus also fires in the Hokm round-2 path when a Sun-alternative is compared against a Hokm suit. The comparison `sun > bestScore` at `Bot.lua:649` is comparing a sun-strength value computed without ace bonus against a Hokm bestScore computed with it, potentially underweighting Sun vs. Hokm in round 2.

Regarding the 4th ace for Hokm: the cap at 3 is correct (the 4th non-trump ace would imply a void in trump, already handled by Advanced distribution logic). The partial-bonus question for Sun context is the real issue.

**Tuning recommendation:** +0 on the cap value (3 aces × 8 = 24 is correct for Hokm). Address the cross-context contamination: the `sideSuitAceBonus` call in round-2 Sun path (line ~645) should be removed or gated `if sun < thSun` to avoid distorting the Hokm vs. Sun comparison. The function itself is correctly scoped for Hokm only.

---

## A-08 — BOT_ASHKAL_TH = 65 vs. TH_SUN_BASE = 50 gap

**VERDICT: WARNING**

**File:line:** `Constants.lua:256` (BOT_ASHKAL_TH = 65), `Bot.lua:37` (TH_SUN_BASE = 50), `Bot.lua:604-625` (Ashkal path)

**Evidence:**

The Ashkal path fires when ALL of these hold:
1. bidPos >= 3 (3rd or 4th position)
2. partner bid Hokm in this round
3. no prior Sun bid
4. Advanced gate passes (no J of flipped suit, sCnt <= 2)
5. `sun >= thAshkal` where `thAshkal = jitter(K.BOT_ASHKAL_TH or 65, BID_JITTER)`

The Sun direct-bid path fires earlier (line 583): `if sun >= thSun then return K.BID_SUN end`. Since TH_SUN_BASE=50 and BOT_ASHKAL_TH=65, a bot with sun in [50, 64] reaches the Ashkal check only after *failing* the direct-Sun check. With jitter both thresholds move ±6, so the effective overlap zone where a bot would Sun-direct but not Ashkal is roughly sun in [44, 71] (jittered ranges). A bot with sun=62 might pass thSun=56 (jittered down) and bid Sun direct, or pass thSun=64 (jittered up) and fall through to the Ashkal gate at thAshkal=59 (jittered down) and bid Ashkal instead — a different contract from the same hand on different random draws.

The more dangerous case: when partner bid Hokm, the Ashkal path precedes the direct-Sun return in the code order... actually no. Looking at the code flow:

```
line 583: if sun >= thSun then return K.BID_SUN end
...
line 623: if sun >= thAshkal then return K.BID_ASHKAL end
```

Direct Sun is checked first. So a sun=62 bot with thSun=58 (jittered down) bids Sun directly and never reaches the Ashkal gate — even if partner bid Hokm. This means the Ashkal path is only reachable when `sun < thSun`, i.e., the bot did NOT qualify for direct Sun. With TH_SUN_BASE=50 and BOT_ASHKAL_TH=65, the Ashkal gate (65) is *above* the Sun gate (50), so Ashkal is unreachable: no hand that fails `sun >= thSun` (threshold ~50) will pass `sun >= thAshkal` (threshold ~65). After jitter, there exists a narrow window: if thSun is jittered up to 56 and thAshkal is jittered down to 59, a hand with sun=57 would fail direct Sun (57 < 59? No: thSun=56 so 57 >= 56 → bid Sun direct). The window where Ashkal fires but Sun does not requires thSun > sun >= thAshkal, which requires thSun > thAshkal. With base 50 vs. 65 this is impossible because BOT_ASHKAL_TH > TH_SUN_BASE; the jitter range of ±6 means the maximum thSun is 56 and the minimum thAshkal is 59. They do not cross. **Ashkal is structurally unreachable in the current code for any bot that evaluates bidding in round 1 with Sun strength in the normal range.** The direct-Sun check always fires first and returns before the Ashkal branch.

This is a correctness defect: Ashkal was presumably designed to let a bot with a Sun-strong hand *give* a Sun contract to a partner who bid Hokm (upgrading from Hokm to Sun). But the direct-Sun return preempts it. The gap of 15 points (65 - 50) is too large; the Ashkal threshold should be at most equal to TH_SUN_BASE to be reachable. In Saudi tournament practice Ashkal is most useful precisely when the calling bot has a marginal-to-good Sun hand and partner has already committed to Hokm — the Ashkal caller is saying "I'm Sun-strong enough to hand this off."

**Tuning recommendation:** Lower BOT_ASHKAL_TH by approximately 15 points (to 50), OR reorder the bid check so Ashkal is evaluated before direct Sun when partner bid Hokm. The cleaner fix is to move the Ashkal block ahead of the `if sun >= thSun then return K.BID_SUN` line in round-1 handling, and leave BOT_ASHKAL_TH at 65 as a meaningful bar (only Ashkal when genuinely Sun-strong). **Recommendation: -15 on BOT_ASHKAL_TH (to ~50) to match TH_SUN_BASE, OR reorder the checks (no numeric change). One of these two changes is required for Ashkal to be reachable.**

---

## A-09 — Ashkal J-of-flipped-suit gate (hasJflip or sCnt > 2)

**VERDICT: WARNING**

**File:line:** `Bot.lua:613-620`

**Evidence:**

```lua
local sStr, sCnt = suitStrengthAsTrump(hand, bidCardSuit)
local hasJflip = false
for _, c in ipairs(hand) do
    if C.Rank(c) == "J" and C.Suit(c) == bidCardSuit then
        hasJflip = true; break
    end
end
if hasJflip or sCnt > 2 then ok = false end
```

The `hasJflip` veto is well-reasoned: if the Ashkal caller holds the J of the flipped suit, partner's Hokm bid on that suit may be J-less (or marginal), making the Sun contract riskier. This is correct and aligns with Saudi tournament wisdom.

The `sCnt > 2` veto (3+ cards of the flipped suit) is more questionable. The stated rationale (code comment): "we're weak in the flipped suit so partner's J of that suit is doing the work." Holding 3 cards of the flipped suit with no J does NOT necessarily mean partner's bid is bluff. A 3-card holding of 9-8-7 in the flipped suit is structurally weak for trump but is neutral for Sun purposes — those cards have zero Sun-point value (9=0, 8=0, 7=0 in `K.POINTS_PLAIN`). The bot is vetoing Ashkal based on card count alone without checking the quality of those cards.

Specifically: holding Q-8-7 of the flipped suit (sCnt=3, no J) triggers the veto. But Q=3 in Sun, and 8/7=0, so the holding barely affects Sun prospects. The veto is over-broad. A player with sCnt=3 and no J, all low cards, should still be eligible for Ashkal.

The correct gate should be: veto Ashkal if `hasJflip` (agreed, correct) OR if sCnt >= 3 AND the cards in the flipped suit have meaningful trump-strength (i.e., `sStr > some_threshold` such as 10, which would require a 9/A/T in that suit). The raw count sCnt > 2 is too blunt.

Separately, note that due to A-08's finding (Ashkal is structurally unreachable because TH_SUN_BASE=50 precedes BOT_ASHKAL_TH=65), this gate never executes in practice. Fix A-08 first, then this veto becomes relevant.

**Tuning recommendation:** Change `sCnt > 2` to `(sCnt > 2 and sStr > 10)`. This preserves the intent (don't Ashkal when the bot has meaningful flipped-suit strength that validates partner's bid) while correctly allowing Ashkal when the 3 flipped-suit cards are all low (0-point trash). **Recommendation: no threshold numeric change; refine the sCnt condition as described.**

---

## A-10 — partnerBidBonus: +20 matching trump, +10 other Hokm, +15 Sun

**VERDICT: WARNING**

**File:line:** `Bot.lua:401-427`

**Evidence:**

```lua
local function partnerBidBonus(seat, contract)
    if not Bot.IsAdvanced() then return 0 end
    ...
    if b == K.BID_SUN then return 15 end
    if b == K.BID_ASHKAL then return 15 end
    if b == K.BID_PASS then return -10 end
    if b:sub(1, #K.BID_HOKM) == K.BID_HOKM then
        local bidTrump = b:sub(#K.BID_HOKM + 2, #K.BID_HOKM + 2)
        if contract and contract.trump and bidTrump == contract.trump then
            return 20
        end
        return 10
    end
    return 0
end
```

The function returns a *strength bonus* that is added to the bot's own evaluated strength score before comparing against an escalation threshold. The concern raised in the prompt is double-counting: the bot's own trump strength is already in its `escalationStrength()`, and adding +20 for partner confirmation overcounts synergy.

Analysis of usage sites:

1. `PickDouble` (line 1169): `strength = strength + partnerBidBonus(seat, contract) + partnerEscalatedBonus(seat, contract)`. The `strength` here is computed as `sunStrength(hand) + trumpStr * 0.5` — this IS the bot's own hand only. Adding +20 for "partner also bid our trump" is a synthetic boost representing combined-team confidence, not a double-count of trump cards (partner's J and 9 are not in our hand).

2. `escalationStrength` (line 1198): same pattern — `sunStrength(hand) + suitStrengthAsTrump(hand, contract.trump)`. These are own-hand evaluations. Partner's Hokm bid does imply partner holds a trump-strong hand; the +20 bonus is the bot's estimate of partner's trump contribution to the combined-team strength.

The prompt's concern is architectural: the bonus is applied to the *threshold adjustment* rather than the hand score. In fact the code applies it to `strength` (the score side), then compares `strength >= threshold`. This is equivalent to adjusting the threshold downward by 20, which is the documented intent. The framing is consistent.

The magnitude concern: +20 for "partner bid same trump" is approximately equal to the value of a trump Jack (J=20 in `suitStrengthAsTrump`). This is calibrated to "partner likely has J of trump" — a reasonable approximation for Saudi Baloot where the J is the dominant trump card. +15 for partner Sun (lots of A/T) is 1.5 Aces, also reasonable as a "partner brings side-suit coverage" signal.

The real calibration risk is that `partnerBidBonus` is also used in `PickDouble` (Bel decision) for *defenders*. Defenders are the opposing team; their partner is also a defender. The contract's trump belongs to the *bidder*, not the defender. A defender who receives +20 "partner bid our trump" bonus is in a case where partner bid the *same suit as the current contract trump* — meaning both defenders bid the same suit as the bidder. This scenario is rare (the bidder would already hold the trump), but when it occurs, the +20 defender bonus is computed against a defender trump strength that includes defending a suit, not their own attacking trump. This is a mild semantic mismatch. The bonus is not zero (knowledge of partner's trump strength is still valuable for Bel defense calibration) but 20 is likely 5-8 points too high in the defender context.

**Tuning recommendation:** The +15 Sun and +10 other-Hokm values are well-calibrated. The +20 same-trump bonus is correct for the *bidder team* escalation path but approximately 5-8 points too high when applied in the *defender* Bel (`PickDouble`) path where partner confirming trump suit means something different. Consider splitting the function into bidder-team and defender-team variants, or guard the +20 with `R.TeamOf(seat) == R.TeamOf(contract.bidder)` and return +12 in the defender case. **Recommendation: +20 → +12 in the defender-team branch, no change for bidder-team.** No change to the +15 Sun bonus or -10 pass penalty.

---

## Summary Table

| Angle | Severity  | Tuning Rec |
|-------|-----------|------------|
| A-03: TH_SUN_BASE = 50 | WARNING | Add computed floor `math.max(thSun, TH_SUN_BASE - 10)`; no change to base value |
| A-06: sideSuitAceBonus cap | WARNING | Remove sideSuitAceBonus from round-2 Sun-vs-Hokm comparison path; cap itself (3×8) is correct |
| A-08: BOT_ASHKAL_TH = 65 unreachable | WARNING (correctness defect) | Lower BOT_ASHKAL_TH to ~50 OR reorder Ashkal check before direct-Sun check |
| A-09: sCnt > 2 veto | WARNING | Change condition to `(sCnt > 2 and sStr > 10)` |
| A-10: partnerBidBonus +20 | WARNING | +20 → +12 in defender-team context only |

**Critical note:** A-08 is the highest-priority finding — Ashkal is structurally unreachable in the current code, meaning the BOT_ASHKAL_TH constant and the J-of-flipped-suit gate (A-09) are dead code for any hand evaluated with the current check ordering.
