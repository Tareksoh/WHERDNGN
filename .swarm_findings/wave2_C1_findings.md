# Wave 2 — Cluster C1: Hokm Bidding Threshold Calibration

Reviewer: swarm-C1 (code-review agent)
Codebase: WHEREDNGN v0.4.4
Files examined: Bot.lua (1354 lines), Constants.lua (258 lines)
Key loci:
  - Bot.lua:35-38  — TH_HOKM_R1_BASE, TH_HOKM_R2_BASE, TH_SUN_BASE, BID_JITTER
  - Bot.lua:296-332 — suitStrengthAsTrump (J-step penalty at line 329)
  - Bot.lua:443-487 — scoreUrgency, matchPointUrgency
  - Bot.lua:540-656 — Bot.PickBid (threshold computation and application)
  - Bot.lua:570-575 — r2Base clamp: `math.max(r2Base, r1Base - 4)`

---

## A-01 — Hokm R1 threshold sensitivity (TH_HOKM_R1_BASE = 42)

**VERDICT: WARNING**

**File:Line:** Bot.lua:35 / Bot.lua:296-332

**Evidence:**
The strength formula in `suitStrengthAsTrump` allocates: J=20, 9=14, A=11, T=10, K=4, Q=3, 8=2, 7=2, plus length bonus +5 per card beyond 2, plus Advanced J+9 synergy +18 (or +10 basic). The bid threshold is `jitter(42 - urgency, 6)`, meaning the effective window is [36, 48] before urgency.

Enumeration of the 38-46 zone (Basic mode, no urgency):

- J alone (20): 20 — well below threshold, correctly passes.
- J + 9 (20+14+10 synergy = 44 with Basic, 48 with Advanced): precisely straddles the basic threshold cliff at 42. A J+9 two-card suit in Basic lands at 44 — bids about 75% of the time (threshold window 36-48, 44 is above midpoint). This is correct human behavior: J+9 alone in 5-card round is a biddable hand.
- J + A (20+11 = 31): below threshold, correctly passes.
- J + K (20+4 = 24): below threshold.
- 9 + A (14+11 = 25): below threshold, correct.
- 9 + A + T (14+11+10 = 35): just below the jitter floor (36), passes ~50% — this is the main calibration concern. A hand with 9+A+T in a 5-card round is a solid playable trump in Saudi expert play, but the bot passes it roughly half the time.
- J + 3 small (20+2+2+5 = 29, length bonus +5 for 4 cards): still below. Correct — J alone in 4-card suit is marginal.
- J + Q (20+3 = 23): passes. Correct.
- J + 9 + K (20+14+4+10 synergy = 48 Basic): bids nearly always. Strong hand, correct.

**Key finding:** The 9+A+T combination (raw strength 35) falls just below the jitter floor, meaning it passes roughly 50% of the time in Basic mode. Saudi tournament play treats 9+A+T with reasonable length as a biddable suit. A 2-point downward nudge to TH_HOKM_R1_BASE=40 would admit 9+A+T-length hands reliably while still blocking the 9+A-only (25) and J-alone (20) marginal hands. The upper boundary is safe: J+9 at 44 Basic / 52 Advanced already bids confidently.

**Recommendation:** -2 (lower TH_HOKM_R1_BASE from 42 to 40). The 9+A+T borderline hand is currently under-bid in Basic mode, affecting round-1 action frequency. Low impact on the strong end.

---

## A-02 — Hokm R2 threshold gap vs. R1 (r2Base = 38 in Advanced)

**VERDICT: WARNING**

**File:Line:** Bot.lua:571-572 (`if Bot.IsAdvanced() then r2Base = math.max(r2Base, r1Base - 4) end`)

**Evidence:**
The local constants are TH_HOKM_R1_BASE=42 and TH_HOKM_R2_BASE=36. In Advanced mode, `r2Base = math.max(36, 42-4) = math.max(36, 38) = 38`. So Advanced R2 base is 38, Basic R2 base is 36. Both are below R1 base of 42.

The comment at line 560-569 acknowledges this is a known semantic inconsistency: "R2 allows suit-choice which should raise the bar, not lower it" but then explains the regression rationale for keeping it below R1. In Round 2 the bot can pick ANY non-flipped suit, so it evaluates `bestScore` across all three candidate suits — effectively using the maximum strength across four hands rather than committing to the bid-card suit. This changes the interpretation: a R2 bid at score X is structurally stronger than a R1 bid at the same X because the best suit was selected.

However the clamp relationship is still technically inverted from first principles: R2 threshold (38) < R1 threshold (42). The code comment justification — "R2 should be ≥ R1 doesn't apply since suit-choice compensates" — is valid but undocumented as a deliberate design decision. The risk is future editors raising r2Base without understanding the suit-choice compensation argument.

**Urgency stacking check:**
- Max Basic urgency stack (scoreUrgency only): +12 (near-loss case).
- Max Advanced urgency stack (scoreUrgency + matchPointUrgency, both capped): +12+10=22, but matchPointUrgency is internally capped at ±10, and the dominant near-loss scenario gives scoreUrgency=12 + matchPointUrgency=5 = 17.
- At urgency=17: thHokmR1 = jitter(42-17,6) = jitter(25,6) = [19,31]; thHokmR2 = jitter(38-17,6) = jitter(21,6) = [15,27].
- The clamp `math.max(r2Base, r1Base-4)` applies to base values BEFORE urgency subtraction, so it guarantees r2Base ≥ r1Base-4 only at the base level. After urgency subtraction, r2 and r1 thresholds can converge or cross because both receive the same urgency deduction. At urgency=17, r2Base(38)-urgency(17)=21 and r1Base(42)-urgency(17)=25, so R2 effective midpoint (21) is still 4 below R1 midpoint (25). The gap is preserved through urgency arithmetic. No invariant break found here.

**Recommendation:** 0 (no change). The clamp is correctly applied and the gap survives urgency stacking. Document the design intent more explicitly: "R2 < R1 is intentional because R2 uses best-of-3-suits selection." The code comment at line 562-569 partially explains this but buries the key "compensated by best-suit selection" rationale.

---

## A-04 — BID_JITTER = 6 effect on threshold cliff sharpness

**VERDICT: WARNING**

**File:Line:** Bot.lua:38 (`local BID_JITTER = 6`)

**Evidence:**
The effective bidding window is ±6 (12-point range) on top of each threshold. For TH_HOKM_R1_BASE=42 with no urgency: a bot bids when strength ≥ rand_in[36,48]. For a hand at strength exactly 42 (on-the-cliff), the bot bids ~50% of the time.

The primary concern: strong hands near the ceiling of the cliff can occasionally pass.
- J+9 Basic (strength 44): threshold window [36,48]. Passes when jitter draws 45-48 (4 of 13 values ≈ 30%). This is surprisingly frequent for a clearly biddable J+9 hand.
- J+9+length (strength 49+): comfortably above even the high end (48), bids always. Safe.
- J+9 Advanced (strength 52 with +18 synergy): far above window, always bids.

The "two bots always match bids on similar hands" concern: with ±6 jitter each bot draws independently from a 13-value uniform distribution. Two bots with the same strength-42 hand have a (4/13)^2 ≈ 9.5% chance of both drawing the same threshold value, but since bids are resolved sequentially (and the second bid is blocked by the first Hokm), the jitter effectively desynchronizes them. No systematic synchronization issue observed.

Edge case where jitter flips a clear bid into a pass:
- J+9 Basic (44) has a 30.8% pass rate as computed above. This is the main cliff problem. An expert player would bid J+9 nearly always in Round 1.
- Root cause: BID_JITTER=6 is 14% of the base threshold (42), which is too wide relative to the "clear bid" zone just above the threshold.

**Recommendation:** -2 (reduce BID_JITTER from 6 to 4). A ±4 window still provides sufficient desynchronization (9-point range vs. 13-point) but narrows the zone where a J+9 hand (strength 44) risks a pass. At BID_JITTER=4, J+9 Basic passes only when jitter draws 45-46 (2 of 9 values ≈ 22%), and combined with a -2 on TH_HOKM_R1_BASE (A-01), J+9 Basic at 44 vs threshold window [34,42] would bid nearly always.

---

## A-05 — J-step-function 0.4 dampener for no-J hands in Advanced

**VERDICT: WARNING**

**File:Line:** Bot.lua:324-330

```lua
if Bot.IsAdvanced()
   and not hasJ and count < 5 and not (has9 and hasA) then
    strength = math.floor(strength * 0.4)
end
```

**Evidence:**
The dampener applies when ALL of: (a) Advanced mode, (b) no J, (c) fewer than 5 cards in suit, (d) NOT (has9 AND hasA).

Checking A-05's specific concern — 4-card A+T+K hand:
- Raw strength: 11+10+4 = 25, plus length bonus (4-2)*5 = 10 → total 35.
- Conditions: no J (true), count=4 < 5 (true), has9=false, hasA=true — condition (d) is `not (false AND true)` = `not false` = true. So the dampener DOES apply.
- Post-dampener: floor(35 * 0.4) = floor(14) = 14.

This is overly aggressive. A 4-card A+T+K suit in Saudi Hokm is a strong holding: the A wins the first trick, the T is the second-highest point card, and K takes the fourth highest. Three of four tricks from this suit are point-rich. Collapsing this to 14 raw means it never bids in any mode — it falls well below the [36,48] jitter window.

Now checking the cliff concern — 4-card A+9 vs. 3-card J hand:
- 4-card A+9 (Advanced, no dampener since has9 AND hasA): 11+14+10(length) = 35. No dampener. Strength = 35.
- 3-card J hand (Advanced): 20 + 0(length) = 20. Dampener: floor(20 * 0.4) = 8.
- No cliff inversion here — the dampener correctly penalizes J-alone-short. The A+9 hand (35) is properly above J-short (8).

But the 4-card A+T+K cliff is real: without the dampener this hand is 35 (marginal, passes often), with it the hand becomes 14 (never bids). The exemption condition should also include `hasA and hasT` (A+T is a guaranteed first two tricks).

**Recommendation:** +1 (add `not (hasA and hasT)` to the dampener exemption condition). The updated guard:
```lua
if Bot.IsAdvanced()
   and not hasJ and count < 5
   and not (has9 and hasA)
   and not (hasA and hasT) then
    strength = math.floor(strength * 0.4)
end
```
This preserves the dampener for genuinely weak no-J hands (Q-K-small, K-small-small) while exempting A+T anchor hands that are structurally playable even without the J.

---

## A-07 — Advanced R2 threshold stricter-than-R1 invariant under extreme urgency

**VERDICT: INFO**

**File:Line:** Bot.lua:555-575

**Evidence:**
The theoretical max urgency stack for M3lm (which is the only tier reaching matchPointUrgency):
- scoreUrgency max positive: +12 (opp >= target-25)
- matchPointUrgency max positive: +10 (internal cap at line 484)
- Combined max: +22 (theoretical), but real-world max is ~17 because the +12 scoreUrgency (opp near win) and +5 matchPointUrgency (opp >= target-15, halved from +8 in the 13th audit fix) are the dominant scenario. The +10 cap in matchPointUrgency blocks the old +8 case from stacking with scoreUrgency's +12 for a total of +20.

Checking the A-07 concern (urgency = 17):
- r1Base = 42, r2Base = 38 (Advanced after clamp).
- thHokmR1 midpoint = 42 - 17 = 25, jitter window [19, 31].
- thHokmR2 midpoint = 38 - 17 = 21, jitter window [15, 27].
- R2 midpoint (21) remains 4 below R1 midpoint (25). Gap = r1Base - r2Base = 42-38 = 4. The urgency subtraction applies equally to both, so the gap is preserved arithmetically.

Worst case at urgency = 22 (theoretical max):
- thHokmR1 midpoint = 42 - 22 = 20, window [14, 26].
- thHokmR2 midpoint = 38 - 22 = 16, window [10, 22].
- Still r2 < r1 by 4 points at midpoint.

The `math.max(r2Base, r1Base - 4)` clamp is applied BEFORE urgency (on the base constants), so it correctly locks in the 4-point gap at the base level. The urgency subtraction then translates both thresholds downward by the same amount, preserving the gap at all urgency levels. **No invariant break under any urgency scenario.**

One minor concern: at urgency = 22 (theoretical max), R2 jitter floor drops to 10. A 10-point threshold means almost any non-void suit bids in Round 2 (a 2-card 7-8 suit scores 4 and fails, but a 2-card A-T suit scores 21 and passes). This is intentional desperate behavior, consistent with the "near-loss" semantics.

**Recommendation:** 0 (no change). The clamp correctly preserves the gap. Consider adding an urgency floor clamp to prevent the R2 threshold from falling below ~20 in extreme urgency scenarios (e.g., `thHokmR2 = math.max(thHokmR2, 20)`), but this is a cosmetic robustness improvement, not a correctness issue.

---

## Summary Table

| Angle | Verdict  | File:Line        | Recommended Change                          |
|-------|----------|------------------|---------------------------------------------|
| A-01  | WARNING  | Bot.lua:35       | TH_HOKM_R1_BASE: 42 → 40 (-2)              |
| A-02  | WARNING  | Bot.lua:571-572  | No constant change; document design intent  |
| A-04  | WARNING  | Bot.lua:38       | BID_JITTER: 6 → 4 (-2)                     |
| A-05  | WARNING  | Bot.lua:324-330  | Add `not (hasA and hasT)` exemption to guard|
| A-07  | INFO     | Bot.lua:555-575  | No change; invariant holds under all urgency|
