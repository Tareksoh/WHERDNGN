# Wave 2 — Cluster C5: Escalation Chain Threshold Calibration
## Auditor: C5 swarm agent | v0.4.4 | 2026-05-03

---

### A-50 — Bel threshold K.BOT_BEL_TH = 70 and gap to Triple TH = 90

**VERDICT: WARNING**

**File:line:** `C:/CLAUDE/WHEREDNGN/Constants.lua:252-253`, `C:/CLAUDE/WHEREDNGN/Bot.lua:1171-1179`, `C:/CLAUDE/WHEREDNGN/Bot.lua:1206-1213`

**Evidence:**

The Bel threshold is applied in `PickDouble` (Bot.lua:1171) as `th = K.BOT_BEL_TH - (scoreUrgency + matchPointUrgency)`, and the open/close decision uses `wantOpen = strength >= jth + 20` (Bot.lua:1178). The prompt correctly identifies the logic: a defender needs `strength >= jitter(70 - urgency, 10) + 20` to open — roughly `strength >= 90` in the zero-urgency case, which exactly equals the Triple threshold. This is internally consistent by design, but it creates a subtle asymmetry:

The `escalationStrength` used in `PickTriple` includes the full `suitStrengthAsTrump` contribution (Bot.lua:1193: `strength = strength + suitStrengthAsTrump(hand, contract.trump)` — no 0.5 weight). By contrast, `PickDouble` uses the 0.5-weighted trump contribution (Bot.lua:1160-1161: `strength = strength + trumpStr * 0.5`). This means a defender who opens Bel (strength >= 90 in `PickDouble`'s metric) can legitimately have a different raw value than the bidder evaluating their Triple threshold (BOT_TRIPLE_TH = 90 in `escalationStrength`'s metric). The "defender opens at exactly Triple TH" coincidence only holds numerically if both parties are evaluated on the same strength formula — they are not.

Specifically: a defender with 5-trump strong hand may score `sunStrength=35 + trumpStr*0.5=30 = 65` in PickDouble (below Bel threshold), but a bidder on the same conceptual hand scores `sunStrength=35 + trumpStr=60 = 95` in escalationStrength (well above Triple threshold). The formula asymmetry means the "gap is 20" invariant holds at the formula level in PickDouble, but does not map to a symmetric rung-to-rung ladder across the two different evaluation contexts.

**Recommended adjustment:**

Either (a) unify the trump weight in PickDouble to use the full `suitStrengthAsTrump` contribution (no 0.5 multiplier) to match the `escalationStrength` formula used for Triple/Four, which would mean raising BOT_BEL_TH from 70 to approximately 100 to preserve equivalent selectivity; or (b) document explicitly that BOT_BEL_TH and BOT_TRIPLE_TH operate on different strength scales and raise BOT_BEL_TH to ~85 to compensate for the undercount, narrowing the de-facto gap. The current 20-point numeric gap is misleading because it straddles two different scoring contexts. Low severity in practice (Bel fires roughly as often as designed), but it means the "defender opens only if they can survive a Triple" invariant is not actually enforced.

---

### A-51 — Four threshold K.BOT_FOUR_TH = 110 and Gahwa TH = 135

**VERDICT: WARNING**

**File:line:** `C:/CLAUDE/WHEREDNGN/Constants.lua:254-255`, `C:/CLAUDE/WHEREDNGN/Bot.lua:1191-1202`, `C:/CLAUDE/WHEREDNGN/Bot.lua:1239-1255`

**Evidence:**

All escalation decisions (PickDouble through PickGahwa) fire during PHASE_DOUBLE/TRIPLE/FOUR/GAHWA, which precedes `HostFinishDeal` and the distribution of the final 3 cards (State.lua:1313-1332). Therefore, all `escalationStrength` evaluations run on 5-card hands. With a 5-card hand, computing the realistic ceiling for `escalationStrength`:

- `sunStrength` maximum on 5 cards: A+A+A+A+T with stopper bonus = 11+11+11+11+10 + 8 (one AKQ stopper) ~ 62. The Advanced lopsidedness penalty (up to -18) can reduce this, but with 4 aces it won't fire. Practical sun-heavy ceiling: ~62.
- `suitStrengthAsTrump` on 5-card suit: J(20)+9(14)+A(11)+T(10)+K(4) + length bonus (5-2)*5=15 + J+9 synergy Advanced(18) = 92.
- `partnerBidBonus`: max +20 (partner bid Hokm matching our trump).
- `partnerEscalatedBonus`: for a Gahwa decision, partner has already tripled, so `contract.tripled` is set → +5. But Gahwa is the bidder's terminal, so pIsBidderTeam is true — bonus = +5 (tripled). Max from this path: +5 at Gahwa rung.

Realistic escalationStrength ceiling for a 5-card Hokm hand at Gahwa decision time:
- Strong trump scenario: sunStrength~30 (2 off-suit honors) + trumpStr~77 (J+9+A+T+K, 5-card, with Advanced synergy) + partnerBid+20 + partnerEscalated+5 = ~132.
- Sun-heavy scenario: sunStrength~62 + trumpStr=0 (Sun contract, no trump) + partnerBid+15 (partner bid Sun) + partnerEscalated (contract.tripled) ~+5 = ~82.

BOT_GAHWA_TH = 135 sits above the realistic Hokm ceiling of ~132 and far above the Sun ceiling of ~82. Gahwa therefore essentially never fires for bot-vs-bot games. For the Hokm case, the threshold is reachable only with a 2-point jitter tail (jitter amplitude BEL_JITTER=10 at Bot.lua:1147 subtracts from TH, so effective fire threshold is `135 - jitter(0, 10)` = as low as 125), making it fire very rarely (~low single-digit percentage of eligible deals). This is borderline consistent with the intent ("near-certain hand") but may produce excessively passive bots at tournament level.

BOT_FOUR_TH = 110 is achievable: sunStrength~40 + trumpStr~60 + partnerBid+10 = 110. This fires on realistically strong defender hands and appears correctly calibrated.

**Recommended adjustment:**

Lower BOT_GAHWA_TH from 135 to 120 to allow Gahwa to fire on genuinely strong Hokm hands without the bidder needing a statistically improbable five-trump perfect hand. At 120, the `jitter(120, 10)` window (110-120) captures typical maximum-strength hands. Alternatively, if the 5-card pre-deal3 evaluation is intentional (bet on incomplete information), add a comment documenting that the threshold was set assuming full 8-card hands and is consequently too high — then either lower it or defer the decision to post-deal3. The Four threshold appears correctly placed.

---

### A-55 — Escalation during play vs. pre-play phase gating

**VERDICT: INFO**

**File:line:** `C:/CLAUDE/WHEREDNGN/Net.lua:2897`, `2970`, `3021`, `3072`; `C:/CLAUDE/WHEREDNGN/Bot.lua:1153`, `1215`, `1227`, `1239`

**Evidence:**

The picker functions `PickDouble`, `PickTriple`, `PickFour`, and `PickGahwa` contain no internal phase guard. Each function reads `S.s.hostHands[seat]` and `S.s.contract` and returns a decision purely based on hand strength — there is no `if S.s.phase ~= K.PHASE_DOUBLE then return false end` guard inside the pickers themselves.

The phase enforcement falls entirely on `MaybeRunBot` in Net.lua, which uses explicit phase checks before scheduling each picker:
- Line 2897: `if S.s.phase == K.PHASE_DOUBLE and S.s.contract then`
- Line 2970: `if S.s.phase == K.PHASE_TRIPLE and S.s.contract then`
- Line 3021: `if S.s.phase == K.PHASE_FOUR and S.s.contract then`
- Line 3072: `if S.s.phase == K.PHASE_GAHWA and S.s.contract then`

Additionally, each timer callback re-checks the phase before calling the picker (e.g., Net.lua:2909 `if S.s.phase ~= K.PHASE_DOUBLE then return end`). So the two-level guard (MaybeRunBot outer + callback inner) prevents out-of-phase execution in all normal paths.

If `PickDouble` were called directly during PHASE_PLAY (e.g., from a hypothetical future caller or test harness), it would evaluate the hand strength and return a result — it would NOT error or no-op. The function is stateless with respect to phase. This is a design choice (pure function), not a bug, but it is a latent risk: any future caller that bypasses the Net.lua dispatcher will silently produce an escalation decision for the wrong phase with no internal protection.

**Recommended adjustment:**

Low priority. Document the phase-guard responsibility in each picker's docblock (currently only a general comment at the top of the Bel/Triple/Four/Gahwa section at Bot.lua:1185-1188 covers this). Consider adding a single-line assert or early-return guard inside `PickDouble` at minimum as a defensive layer, since Bel is the most likely entry point for future callers. No correctness issue exists in the current dispatcher architecture.

---

### A-56 — Score urgency stacking cap: scoreUrgency + matchPointUrgency limit

**VERDICT: WARNING**

**File:line:** `C:/CLAUDE/WHEREDNGN/Bot.lua:443-487`, `1171`, `1223`, `1235`, `1252`

**Evidence:**

`scoreUrgency` returns at most +12 (Bot.lua:449: `return 12` when `opp >= target - 25`) and at most -8 at the conservative end. `matchPointUrgency` is capped at ±10 (Bot.lua:484-485). The combined maximum positive urgency is therefore 12 + 10 = 22. Applied to BOT_BEL_TH = 70: `th = 70 - 22 = 48`. With `jitter(48, 10)` the effective Bel threshold can drop to 38.

At threshold 38 on a 5-card hand, `escalationStrength` (or PickDouble's `strength`) can easily exceed this. Consider: a defender with just J of trump (strength 20) + one off-suit ace (strength from sunStrength ~11) = sunStrength ~11 + trumpStr*0.5 ~10 = 21, still below 38. But adding `partnerBidBonus` (+10 for a generic Hokm partner bid) + `partnerEscalatedBonus` (+5 for partner having Beled) pushes to ~36, almost at the threshold. Realistically, any defender dealt 2-3 honors will fire Bel in desperate mode.

The cap placement is technically correct (each function has its own internal cap), but the stacking interaction is not independently bounded. The combined output of 22 produces a scenario where BOT_BEL_TH effectively becomes ~48 — not "any hand qualifies" (as the prompt asks), but it is low enough that weak 5-card hands with a couple of honors will Bel in late-game desperation. This may be the intended behavior, but it lacks documentation.

More critically: BOT_GAHWA_TH = 135 with the same max urgency = `th = 113`. Given the realistic ceiling of ~132 computed in A-51, desperation urgency can push Gahwa to fire on ordinarily-below-threshold hands. The interaction between urgency stacking and the already-borderline Gahwa threshold compresses the gap between normal and desperate behavior entirely for terminal escalation.

The cap in `matchPointUrgency` (Bot.lua:484) is correctly placed — it prevents the individual function from returning more than ±10. However, no cap exists on the SUM of the two functions. The callers always combine them with `scoreUrgency + matchPointUrgency` (e.g., Bot.lua:1171, 1223) with no clamping of the aggregate.

**Recommended adjustment:**

Add a combined-urgency cap at the call sites or in a wrapper function. A combined ceiling of +15 (not 22) is recommended: this preserves meaningful desperation behavior (15-point threshold reduction) while preventing degenerate corner cases where both functions simultaneously max out. The Gahwa threshold in particular needs protection — consider applying combined urgency to Gahwa at half-weight or capping combined urgency for terminal-rung decisions. Example at Bot.lua:1252: `local th = K.BOT_GAHWA_TH - math.min(scoreUrgency(R.TeamOf(seat)) + matchPointUrgency(R.TeamOf(seat)), 12)` instead of uncapped 22.

---

## Summary Table

| Angle | Verdict  | Primary File:Line | Core Issue |
|-------|----------|-------------------|------------|
| A-50  | WARNING  | Bot.lua:1159-1179 | Bel and Triple thresholds use different strength formulas; "20-point gap" invariant is not symmetric across evaluation contexts |
| A-51  | WARNING  | Bot.lua:1191-1255 + Constants.lua:254-255 | BOT_GAHWA_TH=135 exceeds realistic 5-card hand ceiling (~132); Gahwa fires near-never in normal play |
| A-55  | INFO     | Net.lua:2897-3113 + Bot.lua:1153-1255 | Pickers have no internal phase guard; responsibility falls entirely on Net.lua dispatcher; no current bug but latent risk |
| A-56  | WARNING  | Bot.lua:443-487, 1171-1252 | Combined urgency cap missing (max 22 uncapped); effectively drops BOT_BEL_TH to ~38 and compresses Gahwa's already-thin margin |
