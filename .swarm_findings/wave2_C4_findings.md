# Wave 2 — Cluster C4: Sun-Strength Evaluation Across Tiers
## Auditor: C4 code-review agent | Date: 2026-05-03 | Codebase: v0.4.4

---

### A-30 — PickDouble trump-strength blend: sunStrength + trumpStr * 0.5

**VERDICT: WARNING**

**File:line:** `C:/CLAUDE/WHEREDNGN/Bot.lua:1158-1163`

**Evidence:**
`Bot.PickDouble` computes the defender's effective strength as `sunStrength(hand) + trumpStr * 0.5`, where `trumpStr` is the full return value of `suitStrengthAsTrump`. The 0.5 blend is applied in `PickDouble` exclusively; by contrast, `escalationStrength` (used by PickTriple/PickFour/PickGahwa at Bot.lua:1191-1201) adds the full `suitStrengthAsTrump` result without any scaling:

```lua
-- PickDouble (line 1161-1162):
local trumpStr = suitStrengthAsTrump(hand, contract.trump)
strength = strength + trumpStr * 0.5

-- escalationStrength (line 1194):
strength = strength + suitStrengthAsTrump(hand, contract.trump)
```

This asymmetry means the Bel decision (the first escalation rung, where the stakes are lowest) sees only 50% of trump value while every subsequent rung (Triple/Four/Gahwa, far higher stakes) sees 100%. The rationale comment ("trump cards are an extra defensive resource") does not explain the 50% discount. A hand with J+9 of trump scores 34 trump card-points, but only gets +17 added to sunStrength for the Bel decision. This can suppress Bel calls on genuinely strong defensive hands while allowing the same hand to proceed freely through Triple and Four. The asymmetry is internally inconsistent across the escalation chain.

**Recommended adjustment:** Either justify and document the 50% discount (e.g., "at Bel the declarer hasn't yet used trump; later rungs have more information"), or align `PickDouble` with `escalationStrength` by using a full blend (coefficient 1.0). If the intent is conservatism at Bel, prefer an explicit threshold raise (`K.BOT_BEL_TH + delta`) rather than a hidden strength haircut that silently propagates into wantOpen logic.

---

### A-31 — Sun penalty: honors vs. distribution (OR condition)

**VERDICT: INFO**

**File:line:** `C:/CLAUDE/WHEREDNGN/Bot.lua:391-396`

**Evidence:**
The Advanced-tier distribution penalty in `sunStrength` reads:

```lua
if count[su] < 2 or not honors[su] then penalty = penalty + 10 end
```

The OR means a suit is penalized if it has fewer than 2 cards OR if it has no A/T/K. This correctly penalizes voids/singletons (count < 2) and suits with only low cards (7-8 doubleton). However it also penalizes a doubleton Q-J (count=2, honors=false since honors requires A/T/K only per line 367: `if r == "A" or r == "T" or r == "K" then honors[su] = true end`). A QJ doubleton in Sun is a genuine half-stopper (second-round control), not a clear liability. The question raised in the prompt — "should Q-J doubleton also be penalized?" — is valid: the hand HAS honors (Q and J) but `honors[su]` remains false because Q/J don't set the flag.

That said, the penalty cap of 18 (line 396: `math.min(penalty, 18)`) softens the impact, and a QJ doubleton in Sun is legitimately risky (opponents can lead the suit twice and take the third round). The practical scoring impact of a single 10-point penalty absorbed into an 18-point cap is small. The more significant structural concern is that `honors` only tracks A/T/K, making `not honors[su]` true for suits containing only Q and J — these are called out as "no honors" despite clearly having face-card material.

**Recommended adjustment:** Expand the honors flag to include Q: `if r == "A" or r == "T" or r == "K" or r == "Q" then honors[su] = true end`. This correctly exempts QJ or Qxx combinations from the "no honors" branch while still penalizing pure low-card suits (7-8, 7-9, 8-9). The count < 2 branch (void/singleton) remains correct as-is.

---

### A-32 — sunStrength in PickBid round 1: evaluated BEFORE suitStrengthAsTrump

**VERDICT: WARNING**

**File:line:** `C:/CLAUDE/WHEREDNGN/Bot.lua:554-636`

**Evidence:**
`Bot.PickBid` evaluates `sun = sunStrength(hand)` at line 554, then at line 583 immediately returns `K.BID_SUN` if `sun >= thSun` — before the Hokm suit-strength loop is ever reached. The Ashkal path (lines 585-626) also runs before Hokm evaluation, and the Hokm-on-flipped path (lines 629-635) only fires if both Sun and Ashkal paths fell through. This ordering is intentional per the comment at line 579 ("Sun overcalls Hokm"), but the threshold for Sun is `jitter(TH_SUN_BASE - urgency, BID_JITTER)` = approximately 44-56 (jitter ±6 around TH_SUN_BASE=50), while a competitive Hokm hand might score 60-80 on suitStrengthAsTrump.

The practical consequence: a hand with `sun=52` (just above threshold) and one suit scoring 70 on suitStrengthAsTrump will always bid Sun, never Hokm. Sun is a ×2 contract and harder to make — the declarer needs distributed high-card strength with no weak suits, while Hokm with a J+9+length suit is often the superior contract. The bot has no mechanism to say "my Sun score barely passes but my Hokm score is much stronger; I should prefer Hokm." In Round 2, line 649 (`if sun >= thSun and sun > bestScore`) adds the `sun > bestScore` guard, which partially addresses this — but Round 1 has no such guard.

**Recommended adjustment:** In Round 1, add a comparative guard analogous to Round 2: evaluate the flipped-suit Hokm strength before committing to Sun, and only bid Sun when `sun >= thSun AND sun > hokmCandidateScore`. This requires computing `suitStrengthAsTrump(hand, bidCardSuit)` before the Sun early-return. Alternatively, raise TH_SUN_BASE for Round 1 to require a clearly Sun-dominant hand (e.g., +8 to base).

---

### A-33 — Ashkal Sun strength requirement (BOT_ASHKAL_TH = 65 vs. TH_SUN_BASE = 50)

**VERDICT: INFO**

**File:line:** `C:/CLAUDE/WHEREDNGN/Bot.lua:623` and `C:/CLAUDE/WHEREDNGN/Constants.lua:256`

**Evidence:**
`K.BOT_ASHKAL_TH` is 65 (Constants.lua:256). The direct Sun threshold `TH_SUN_BASE` is 50 (Bot.lua:37). Both are jittered by `BID_JITTER=6`, giving effective ranges of 59-71 for Ashkal and 44-56 for direct Sun. Ashkal is 15 points stricter at base, which is directionally correct: Ashkal hands the contract to the partner, so the caller needs more confidence than a self-bid. The concern raised in the prompt — that the thresholds might be inconsistent — is not borne out by the code. The 15-point gap between `BOT_ASHKAL_TH` (65) and `TH_SUN_BASE` (50) is larger than the jitter amplitude (±6), so Ashkal is always harder to trigger than direct Sun.

However, an edge case exists: under extreme urgency (`scoreUrgency + matchPointUrgency` can return up to +18 combined per lines 449-452 and 475-479), the direct Sun threshold drops to `jitter(50 - 18, 6)` = approximately 26-38, while Ashkal uses the fixed `K.BOT_ASHKAL_TH` without an urgency modifier (line 623: `local thAshkal = jitter(K.BOT_ASHKAL_TH or 65, BID_JITTER)` — no urgency subtracted). Under maximum desperation, a bot could pass Sun (score 40, below the urgent thSun≈32... actually no, 40 > 32 so it would bid Sun directly). The more subtle issue: in near-loss situations, Ashkal becomes relatively harder than direct Sun because urgency lowers direct Sun's threshold but not Ashkal's. The relative strictness of Ashkal increases under desperation, which may be the wrong behavior (a desperate team should arguably be more willing to force partner into Sun, not less).

**Recommended adjustment:** Apply urgency to the Ashkal threshold consistently: `local thAshkal = jitter((K.BOT_ASHKAL_TH or 65) - urgency, BID_JITTER)`. This aligns the urgency handling with all other threshold calculations in the function.

---

### A-34 — sunStrength for Preempt decisions vs. PREEMPT threshold 75

**VERDICT: WARNING**

**File:line:** `C:/CLAUDE/WHEREDNGN/Bot.lua:1261-1291`

**Evidence:**
`Bot.PickPreempt` computes `strength = sunStrength(hand)` then adds: +12 if the bot holds the Ace of the bid suit (line 1273-1274), ±6/+8/+5 for partner bid context (lines 1283-1287), and `scoreUrgency + matchPointUrgency` (lines 1288-1289). The threshold is `jitter(K.BOT_PREEMPT_TH or 75, BEL_JITTER)` = 65-85 (BEL_JITTER=10).

The prompt asks whether the +12 Ace bonus is the "prime preempt trigger" and whether the function fires in practice. Analysis: `sunStrength` for a round-1 5-card hand with no Ace of bid suit is unlikely to exceed 63 (realistic max: 3 Aces in other suits = 33, plus T/K/Q = 17, total ~50, plus at most 2 face cards in remaining suits). With the +12 Ace-of-bid-suit bonus, that becomes ~62. The threshold lower bound is 65 (75-10). So the function with Ace bonus and no partner boost barely fails to fire even in strong hands. Adding partner-bid bonuses (+8 for partner Sun, +5 for partner Hokm) pushes it to 70-75, which clears the lower bound of the jitter range.

The conclusion is that `PickPreempt` is very unlikely to fire unless the bot holds the Ace of the bid suit AND the partner has already bid. This makes the function nearly dormant in the most common preempt scenario (partner passed, bot holds Ace-strong hand). The -6 partner-pass penalty at line 1283 further suppresses preemption when the partner is weak — yet preemption is most tactically valuable when the bidder's team is otherwise weak (steal the contract with the Ace to deny opponents a soft Sun). The combination of a high jittered threshold (65-85), a strong penalty for the common partner-passed case (-6), and the narrow bonus range means the preempt path will rarely activate even with the Ace trigger.

**Recommended adjustment:** Either lower `K.BOT_PREEMPT_TH` to 68 (giving a jitter range of 58-78), or remove the -6 partner-pass penalty (partner passing is not a reason to avoid preemption — it means the bot's team needs the contract more, not less). The partner-pass penalty likely inverts the correct game logic.

---

## Summary Table

| Angle | Severity | Location | Issue |
|-------|----------|----------|-------|
| A-30  | WARNING  | Bot.lua:1161-1162 | PickDouble uses 0.5x trump blend; escalationStrength uses 1.0x — inconsistent across rung chain |
| A-31  | INFO     | Bot.lua:391-396   | honors flag excludes Q/J; QJ doubleton incorrectly classified as "no honors" |
| A-32  | WARNING  | Bot.lua:554-583   | Round 1 Sun early-return fires before Hokm strength is evaluated; no comparative guard |
| A-33  | INFO     | Bot.lua:623 / Constants.lua:256 | Ashkal threshold lacks urgency modifier; becomes relatively stricter under desperation |
| A-34  | WARNING  | Bot.lua:1261-1291 | Preempt nearly dormant; partner-pass penalty inverts game logic; threshold too high |
