# Wave 2 Cluster C3 — Trump Strength Eval Continuation
## Swarm audit findings — REPORT ONLY, no code changes

Reviewer: C3 code-review agent
File under review: `C:/CLAUDE/WHEREDNGN/Bot.lua`
Scope prompt: `wave2_C3_trump_eval_cont_prompt.md`

---

### A-14 — Preempt threshold BOT_PREEMPT_TH = 75 calibration

**VERDICT: WARNING**

**File:line:** `Bot.lua:1290` (`local th = K.BOT_PREEMPT_TH or 75`), `Constants.lua:257` (`K.BOT_PREEMPT_TH = 75`)

**Evidence:** `PickPreempt` evaluates `sunStrength(hand)` with three additive bonuses: +12 for holding the bid-suit Ace (line 1274), +8/-6/+5 for partner bid state (lines 1283-1287), and `scoreUrgency + matchPointUrgency` (line 1288). The final threshold is `jitter(75, BEL_JITTER)` where BEL_JITTER=10, producing an effective range of [65, 85]. The base sunStrength ceiling on a 5-card hand at deal2 is approximately 65-70 (A+T+K in one suit = 25, stopper-triple +8, A+T in another = 21, A in a third = 11 → 65 before bonuses). That means preempt only fires when the bot also holds the bid-suit Ace (+12) or has a matching partner bid (+8), narrowing eligibility to roughly 8-12% of hands dealt into the preempt phase. The jitter's low end (effective threshold 65) matches BOT_ASHKAL_TH exactly, creating threshold-equivalence between two structurally different decisions: Ashkal (partner already bid Hokm, relatively safe) and preempt (hostile takeover of an opponent's Sun, high variance). At the BEL_JITTER high end (85) the threshold exceeds what most 8-card Sun hands can achieve without both Ace bonus and partner-support bonus simultaneously — effectively prohibiting unilateral preempts. This asymmetry is not ideal: a player in position 1 with A+T+K / A+T / A in three suits (sunStrength ~65) would legitimately want to preempt in Saudi expert play even without the bid-suit Ace.

**Recommended adjustment:** Reduce BOT_PREEMPT_TH from 75 to 68, or hold the threshold at 75 but switch from BEL_JITTER=10 to BID_JITTER=6, bringing the effective range to [69, 81] and eliminating the Ashkal-equivalence at the low end.

---

### A-15 — Bid position ordering in Ashkal gate (lines ~594-603)

**VERDICT: INFO** (formula is correct but contains a latent readability risk)

**File:line:** `Bot.lua:594-603`

**Evidence:** The `order` table is constructed as:
```
order = { (d%4)+1, ((d+1)%4)+1, ((d+2)%4)+1, d }
```
Traced against all four dealer values:
- d=1: order = {2, 3, 4, 1} — seats bid in order 2→3→4→1, dealer last. Correct.
- d=2: order = {3, 4, 1, 2} — seats bid 3→4→1→2. Correct.
- d=3: order = {4, 1, 2, 3}. Correct.
- d=4: order = {1, 2, 3, 4}. Correct.

The formula is arithmetically correct for all four dealer values. The Ashkal gate then checks `bidPos >= 3`, meaning the 3rd or 4th seats in turn order. Per Saudi Baloot convention, these are the seats with the most bidding information (they saw two prior bids), so the restriction is correctly placed. However, there is a latent issue: if `S.s.dealer` is ever nil or 0 (e.g., a state desync during reconnect), `bidPos` stays 0 and the Ashkal branch never fires silently. The nil guard at line 594 (`if S.s.dealer then`) protects against nil but not against 0. A dealer value of 0 is invalid but not impossible given network desync scenarios.

**Recommended adjustment:** Add an explicit validity check: `if S.s.dealer and S.s.dealer >= 1 and S.s.dealer <= 4 then`. This is a defensive-programming info item, not a correctness bug under normal operation.

---

### A-17 — Length bonus: (count-2) * 5 calibration

**VERDICT: WARNING**

**File:line:** `Bot.lua:320`

**Evidence:** The length bonus is `math.max(0, count - 2) * 5`. For a 5-card trump suit the bonus is +15; for a 7-card suit +25. Consider the hand 7-8-9-Q-K of trump (count=5): card-point values are 2+2+14+3+4 = 25 raw, plus length +15 = 40 total. For comparison, J-alone (count=1) scores 20 with no length bonus. The 5-card mediocre suit outscores J-alone by +20, yet J-alone is categorically stronger as trump (it is the highest trump card and wins every trick it leads). In Advanced mode the J+9 synergy bonus partially corrects this by rewarding quality, but in basic mode there is no such correction. The (count-2)*5 formula was designed for suits containing J or 9 (where length genuinely extends trick-taking capacity), but it applies equally to suits where all length cards are below-9 rank, over-lifting pure-length junk hands. A 7-8-9-Q-K five-card suit has zero first-round trick control and would lose all five tricks to a single J of trump.

**Recommended adjustment:** Gate the per-card length increment on at least one high trump (J, 9, or A) being present, or reduce the coefficient from 5 to 3 for hands lacking J or 9. This ensures length only adds value when there is a controlling card to back it up.

---

### A-18 — J+9 synergy bonus: +10 basic vs. +18 advanced

**VERDICT: WARNING** (double-counting present but justified by design; calibration of +18 is questionable)

**File:line:** `Bot.lua:321-323`

**Evidence:** J scores +20 and 9 scores +14 individually (lines 306-307). When both are present, an additional synergy bonus of +18 (Advanced) or +10 (Basic) is added (line 322). The J+9 pair together accounts for 34 of the 62 total trump-suit card points, which is 54.8% of all trump-point value in two cards. The +18 synergy is meant to reflect that J+9 together form an impenetrable 1-2 combination — the holder controls the top two trump ranks and is nearly certain to capture both top trump tricks. However, J+20 and 9+14 are already fully scored individually before the synergy lands. With +18 on top, J+9 together contribute 52 strength points (20+14+18) from a maximum possible trump-suit total that rarely exceeds 70-75 for a full strong hand. That means J+9 alone (without A or T or any length) can reach 52, which exceeds TH_HOKM_R1_BASE=42 on its own — the bot would bid Hokm on J+9 bare regardless of suit length. This seems intended behavior (J+9 bare is a legitimate Hokm bid in Saudi play), but the +18 synergy makes Advanced mode meaningfully more aggressive than Basic (+10) in a way that is hard to justify by reference to card mathematics: the 34-point pair value is already captured in the individual scores; the synergy should represent only the coordination value, not re-value the cards. A +10 basic synergy appears better calibrated to that definition; +18 is likely 4-6 points too high in Advanced mode.

**Recommended adjustment:** Reduce the Advanced J+9 synergy from +18 to +12 or +14 to reflect coordination value only, without implicitly re-pricing already-scored individual cards.

---

### A-19 — No-J penalty: multiplier 0.4 vs. disqualification

**VERDICT: WARNING**

**File:line:** `Bot.lua:324-330`

**Evidence:** The Advanced no-J penalty is `strength * 0.4` applied when: `not hasJ and count < 5 and not (has9 and hasA)`. The escape hatches are: (a) count >= 5 (long suit bypasses penalty entirely), (b) holding both 9 and A together. For a hand with A+T+9+K in trump (count=4, has9=true, hasA=true), the penalty does NOT fire because of escape hatch (b) — this is correct Saudi expert behavior: A+9 is a controlling pair. For a hand with A+T+K+Q in trump (count=4, has9=false, hasJ=false), the penalty fires: raw = 11+10+4+3 = 28, after 0.4x = 11.2, below every threshold. In Saudi expert play, A+T alone of a 4-card suit is considered a borderline-acceptable Hokm bid in specific positional circumstances (late position round 2, no Hokm yet bid, partner likely has support). The 0.4x multiplier at count=4 makes this impossible regardless of position. However, the multiplier does not apply at count >= 5 — so A+T+K+Q+7 (five cards) avoids the penalty entirely, which is arguably inconsistent (five weak cards is not significantly better controlled than four with A+T). The 0.4x coefficient appears slightly too aggressive for the 3-4 card case, but calling it a full disqualification (0.0x) would be worse. The primary concern is the count<5 boundary: a 4-card A+T+K+Q hand is overcapped at ~11 while a 5-card 7+8+9+Q+K hand (no J, no A) avoids the penalty entirely and scores 2+2+14+3+4+length(15) = 40, which exceeds TH_HOKM_R1_BASE. This inversion — weak 5-card suits bidding while strong 4-card suits pass — is a calibration gap.

**Recommended adjustment:** Change the escape hatch from `count < 5` to `count < 6`, so 5-card no-J suits still receive a softened penalty (perhaps 0.6x rather than 0.4x), or alternatively apply the penalty as a flat subtraction (e.g., -20) rather than a multiplier to avoid the score-floor inversion between 4-card and 5-card no-J hands.

---

## Summary table

| Angle | Severity  | Location         | Short finding                                      |
|-------|-----------|------------------|----------------------------------------------------|
| A-14  | warning   | Bot.lua:1290     | BOT_PREEMPT_TH=75 + BEL_JITTER=10 too restrictive; fires ~8-12% of hands; threshold-equivalence with Ashkal at low end |
| A-15  | info      | Bot.lua:594-603  | bidPos formula arithmetically correct; latent null-unsafe on dealer=0 desync |
| A-17  | warning   | Bot.lua:320      | (count-2)*5 awards +15 to mediocre length suits regardless of high-card quality; over-lifts J-less 5-card suits above J-alone |
| A-18  | warning   | Bot.lua:322      | +18 Advanced J+9 synergy double-counts individually-scored J+20 and 9+14; +12-14 is more calibrated |
| A-19  | warning   | Bot.lua:324-330  | 0.4x no-J penalty at count<5 creates score inversion: weak 5-card suits (no J) escape penalty and bid while strong 4-card A+T+K+Q are capped at ~11 |
