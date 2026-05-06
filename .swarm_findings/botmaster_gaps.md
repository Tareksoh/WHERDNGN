# BotMaster.lua Gap Analysis — Saudi Master ISMCTS Sampler
**Scope:** v0.4.7 codebase (BotMaster.lua 596 lines, plus supporting Bot.lua / Rules.lua / Constants.lua / Cards.lua)
**Date:** 2026-05-03
**Prior audits cross-referenced:** MASTER_REPORT.md (200-agent v0.4.4), v0.4.6_AUDIT_REPORT.md, v0.4.7_AUDIT_REPORT.md

---

## 1. Component Audits

### 1.1 sampleConsistentDeal (lines 124–320)

#### Constraints honored
- Own hand pinned (line 199): self-seat always receives `S.s.hostHands[seat]`. Correct.
- Bid card pinned to bidder (lines 138–146, 205): `S.s.bidCard` found in `unseen` is pinned to the bidder seat. The bid card is inserted into `hostHands[bidder]` at `State.lua:1359`, so by `PHASE_PLAY` it is already in the bidder's known hand and therefore NOT in `unseen` (buildUnseen marks all own-hand cards seen at lines 68–70 but only for the calling bot's own seat). For non-calling-bot seats the bidder's hand is opaque; the bidCard does remain in `unseen` and the pin fires correctly. Redundancy is zero because `buildUnseen` only exempts the calling bot's own hand.
- Void inference (lines 202–203): per-seat `Bot._memory[s].void` flags respected in Phase 1 and Phase 2 fill. Correct.
- Meld pins (lines 162–178 primary; lines 292–315 fallback): declared meld cards pinned to their declarer in both paths since v0.4.7. Correct — H-6 was verified fixed.
- likelyKawesh opponent-gating (lines 235–238): desire map cleared only for opponent seats (`sIsOpponent` guard added in v0.4.6 B-99 fix). Correct.
- A-hoarder pickProb degradation (lines 239–243): `aceLate >= 2` reduces strong-bias from 0.70 to 0.50. Correct.

#### Constraints NOT honored / new gaps

**GAP-S1 — No Hokm trump threshold pinning for bidder (J and 9 of trump)**
The sampler pins the bid card to the bidder (line 142) but the Hokm bid threshold in Bot.lua implies the bidder holds J and/or 9 of the declared trump suit (suitStrengthAsTrump awards ~20 points for J, ~14 for 9; the bid threshold is 42). In practice the bidder almost always has at least one of J/9 of trump. The sampler never biases these two cards toward the bidder beyond the general `strong` map. The `strong` map (getStrongCards, lines 43–44) includes `"J"..t = 50` and `"9"..t = 40`, so they ARE in the desire map for the bidder — but at 70% probability only. When the J or 9 is not selected for the bidder in a given world, it may land on a defender, corrupting the world's trump landscape. **Assessment: existing `strong` desire map partially addresses this, but no hard pin exists.** For maximum accuracy, J and 9 of the declared trump suit should be hard-pinned to the bidder (or given desire weight of 100% rather than 70%) when the contract is Hokm. This is a new finding not previously flagged.

**GAP-S2 — Defender desire map is empty (lines 213–214)**
The `desire` map is populated only for the bidder (`s == bidder and strong`) and the partner (pSignalSuit). Both defender seats receive `desire = {}`. Defenders in Hokm are known to hold the remaining trump cards and high side-suit cards. In a Hokm game where bidder+partner account for ~5–6 trump, defenders hold ~2–3 trump. The sampler distributes these proportionally by random fill, which is correct on average but ignores the known void constraints. More importantly, defenders' high-point cards (side-suit A, T) are not biased toward the richer defender. This is the "desire map only weights bidder/partner/pSignalSuit" concern. **Verdict: confirmed present.** A modest improvement would be to give each defender seat a weak non-trump-Ace desire bias (~weight 10) so that side-suit Aces land on defenders at a higher-than-random rate — matching the real-game distribution where defenders often hoard side Aces defensively.

**GAP-S3 — Trump distribution not calibrated to bidder-team allocation**
Saudi Baloot deals 8 cards per seat, 32 total. Each suit has 8 cards. In a Hokm game the bidder normally holds 3–5 trump (5-card deal typically has 1–2; after the 3-card deal they hold bid card + 2 more, so roughly 2–4 trump total depending on the deal). The opponent team (2 seats × 8 cards) holds the remaining trump. The sampler performs no explicit trump-count constraint to ensure the bidder team gets the expected ~5–6 trump total. The `strong` desire map biases more trump to the bidder, but not to the bidder's partner, leaving the partner under-trumped and both defenders over-trumped in many worlds. No fix currently exists. The correct approach is to sample trump distribution first (bidder team target: 5–6 trump of 8), then fill side suits. This is a new angle not previously addressed.

**GAP-S4 — Belote (K+Q of trump) not biased to bidder**
K and Q of the declared trump suit receive weights 10 and 10 in `getStrongCards`. These moderate weights mean Belote is not reliably co-located on the bidder in sampled worlds. Saudi Master play data indicates the bidder holds Belote more often than chance because (a) the bid threshold implies long trump, and (b) K+Q are mid-tier trump (ranks 4 and 3 in RANK_TRUMP_HOKM) — a bidder with J+9+A has likely collected the whole trump suit. No co-location bias currently exists in the sampler. Worlds where Belote is split across bidder+defender create incorrect Belote scoring in `rolloutValue` (Rules.lua ScoreRound detects Belote by playing history, so split-Belote worlds undercount the +20 bonus for the bidder team). This is the new Belote angle from the audit request. **Verdict: confirmed gap, low-medium severity.**

**GAP-S5 — Carre partial-completion not modeled**
If 3 of 4 cards of a Carre (four-of-a-kind) have been observed played, the 4th is somewhere in the unseen pool. The sampler does not reason about this: the 4th card is distributed uniformly at random across the three non-self seats. In practice, if the Carre declarer has not been identified (no declared meld), the 4th card could plausibly be anywhere. But if a player declared a Carre meld and has already played 3 of its cards, the 4th is almost certainly still in their hand (they are the only declarer). The meld-pin system handles this if the meld was declared. The gap is for UNDECLARED potential Carres (the 4th card exists in the pool but no meld was announced). This is a subtle gap with very low frequency; flagged for completeness.

---

### 1.2 getStrongCards (lines 39–55)

#### Hokm path (lines 41–47)
Weights: J=50, 9=40, A=30, T=20, K=10, Q=10 for trump; A=15 for each side suit.
- J and 9 of trump are the two jacks (Bauer equivalent in Saudi Belote): J=20 points, 9=14 points. Their dominance in trick resolution (ranks 8 and 7 in RANK_TRUMP_HOKM) justifies the top weights. Correct.
- A of trump at weight 30 is placed below J and 9. Correct for trick-resolution rank (A is rank 6, below 9's rank 7 and J's rank 8). Correct.
- T at 20, K at 10, Q at 10 reflect their trick-resolution order (T=5, K=4, Q=3). Correct.
- Side-suit A at 15: consistent with the bidding bonus in Bot.lua (`sideSuitAceBonus` adds 5 per side Ace). Appropriate.

**Minor gap:** 8 and 7 of trump are not included at all (they score 0 points and have the lowest trick ranks). This is correct — they are undesirable to assign to the bidder. No issue here.

**Key gap (relates to GAP-S1):** No hard-pin mechanism exists. Weights are probabilistic (70%), not guarantees. The J of trump, the card most diagnostic of whether the bidder will make their contract, can still end up on a defender in 30% of worlds. For a card with weight 50 the actual "goes to bidder" probability with sequential biased allocation is approximately 70% × (pool availability) ≈ 65–70% per world. This is the highest-impact modelling deficiency in the sampler.

#### Sun path (lines 49–53)
Weights: A=40, T=30, K=10 for all four suits.
- Sun contracts have no trump; trick resolution is by led suit only (RANK_PLAIN). A=8, T=7, K=6 in plain rank. Weights match the scoring hierarchy. Aces (11 pts) and Tens (10 pts) are the bulk of the 130 total points. Correct.
- Q and J are omitted (K=10 is the minimum). Q=3, J=2 — low point/trick-rank. Omitting them is acceptable; they are negligible strength signals.
- The strong map gets applied only to the bidder in Sun (line 213). In Sun contracts there is no "partner-Fzloky" guarantee of strong suit preference because Sun is unidirectional strength. The pSignalSuit line (214) can add a suit bias to the bot's partner — that is correct, as partner may have signaled a strong suit even in Sun.

**Verdict: getStrongCards is correct for Sun. The Hokm path is correct in weighting order but lacks hard-pin guarantees for J/9 (GAP-S1).**

---

### 1.3 rolloutValue (lines 335–550)

#### Reward signal correctness
The function returns `diff = result.raw[myTeam] - result.raw[oppTeam]` (lines 543–544), the raw point differential using `R.ScoreRound` (line 536). This is correct: it places make/fail outcomes on the same ranking axis because the contract-outcome cliff (bidder fails → opp takes 162 raw at baseline, swinging the diff by ~324) dominates card-point fluctuation (±20 typical swing). The comment at lines 538–541 correctly explains this.

The Gahwa match-win bonus (lines 545–548: diff ± 10000) correctly dominates all other outcomes, ensuring the sampler prioritizes game-winning paths.

`R.ScoreRound` is called with reconstructed `initialHands` and freshly detected melds (lines 526–534). This is correct but has a subtle model gap: meld detection at lines 528–529 runs `R.DetectMelds(initialHands[s], contract)` on the initial hand (all 8 cards including played tricks). Since melds are declared in trick 1 only, running meld detection on the full initial hand is correct for measuring what WOULD have been declared. However, the sampled `initialHands` are not the real initial hands — they include the sampled cards, not necessarily the real distribution. In worlds where the sampled hand contains an accidental Carre (e.g., 4 Kings land on one seat by coincidence), a phantom Carre scoring event occurs. This is a low-frequency artifact of the sampling process.

**Verdict: rolloutValue reward signal is correct. One minor phantom-meld artifact exists but is low-frequency.**

---

### 1.4 heuristicPick (lines 388–498)

#### Lead heuristic (lines 479–497)
The C-5 fix from MASTER_REPORT is verified present at lines 482–491: `trumpCards` is filtered first, then `highestRank(trumpCards)` is returned for bidder-team in Hokm. The prior bug (using `highestRank(legal)` with possible non-trump result) is fixed. Correct.

Non-trump fallback (lines 493–497): returns lowest non-trump if available, else lowest legal. This mimics a safe-lead policy (discard cheapest side card). Reasonable for a rollout policy.

#### Following heuristic (lines 416–468)
- Partner winning: tries smother (A or T of led suit, non-trump) then falls back to lowest legal. This matches the smother-then-discard pattern in Bot.lua. Correct.
- Not partner winning, second hand (pos==2): duck unless holding unbeatable Ace in Sun; play lowest non-winner otherwise. Third hand high (pos==3). Fourth hand: lowest winner if any, else lowest legal. These match standard Belote/Baloot following heuristics.

**One remaining gap (new, not in prior audits):**

**GAP-H1 — heuristicPick has no void-update in rollout simulation**
During the simulated play-out (lines 501–522), `heuristicPick` calls `R.IsLegalPlay(c, hand, trick, contract, s)` to build the legal set. IsLegalPlay uses the current `hand` and `trick` state correctly. However, the rollout loop does NOT update `Bot._memory` during simulation — voids are not inferred from in-simulation plays. This means mid-rollout trick-play for seat 2 does not update seat 3's void inference for later rollout tricks. This is by design (it would be expensive and would mutate live memory), but it means the heuristic policy ignores void information that would be observable mid-rollout. The practical impact is modest: the legal-play filter already enforces must-follow and must-trump rules, so the heuristic doesn't need void inference to be legal-play-correct. The main gap is in lead heuristics: a simulated seat may lead into a known void when a real player would not.

**GAP-H2 — pos-4 smother logic missing (new finding)**
`heuristicPick` at position 4 (all three opponents have already played) falls through to `lowestRank(winners)` if the seat can win, else `lowestRank(legal)`. There is no smother logic at position 4 even though position 4 is the strongest position to spend an A/T "smother" card — the trick winner is already determined and a cheap winner suffices. The practical impact is small because `lowestRank(winners)` will already pick the cheapest winning card. **Verdict: minor, existing behavior is safe.**

**GAP-H3 — Trump-pull policy too aggressive in Sun rollouts**
The lead branch at lines 481–491 is gated on `contract.type == K.BID_HOKM and R.TeamOf(s) == bidderTeam`. In Sun contracts this branch is skipped and the fallback `lowestRank(nonTrumps)` fires (line 496). This is correct because Sun has no trump. **No issue here.**

---

### 1.5 PickPlay — top-level dispatch (lines 555–595)

#### Structure
- BM.IsActive() gate (line 556): correct.
- Legal play enumeration (lines 563–567): uses `R.IsLegalPlay` with the real hand and trick. Correct.
- Single legal play short-circuit (line 568): correct.
- Score accumulation without averaging (lines 583–587): raw sum is used, not mean. Since all candidates are evaluated against the same N worlds, argmax(sum) == argmax(mean). Correct.
- Fallback world handling: if `sampleConsistentDeal` returns nil (impossible per current code — it always returns a deal), the `if world then` guard at line 582 skips that world. This means if the primary path exhausts 15 attempts AND falls back, the deal still returns (fallback never returns nil). The nil-guard is a safe defensive check. Correct.
- Best-card selection (lines 590–594): `>` comparison, so ties resolve in favor of the first evaluated card (iteration order of `legal`). This is a minor tie-breaking non-determinism but does not bias toward incorrect play.

**No bugs found in PickPlay dispatch.**

---

### 1.6 numWorlds scaling (lines 575–578)

#### Current code
```lua
local numWorlds = BASE_NUM_WORLDS  -- 30
if numTricks >= 6 then numWorlds = 100
elseif numTricks >= 4 then numWorlds = 60 end
```

#### H-2 status: STILL INVERTED (confirmed present in v0.4.7)

The MASTER_REPORT (H-2) and waves 4 and 7 all flagged this as HIGH severity. The v0.4.6 audit (H-2 renaming to the "OnPlayObserved replay" issue) did NOT fix the numWorlds direction — that item was renamed in the v0.4.7 report (the v0.4.7 H-2 is the replay-guard issue, different from MASTER H-2). Checking BotMaster.lua lines 575–578 directly: **the inverted scaling is still present in v0.4.7**.

**Why it is inverted:**
- Tricks 1–3 (numTricks 0–3): `numWorlds = 30`. Here, all 3 other seats hold ~5–7 unknown cards each. The number of consistent deals is enormous. The sampler uses only 30 worlds — minimum precision at maximum uncertainty.
- Tricks 7–8 (numTricks >= 6): `numWorlds = 100`. Here, each seat holds ~1–2 unknown cards. The total number of distinct consistent deals is small (often < 30). Using 100 worlds over-samples a small solution space; many worlds are duplicates or near-duplicates.

**Correct scaling:** more worlds early (high variance), fewer worlds late (low variance). The recommendation from MASTER_REPORT:
```lua
local numWorlds
if numTricks <= 3 then numWorlds = 100
elseif numTricks <= 5 then numWorlds = 60
else numWorlds = BASE_NUM_WORLDS end  -- 30
```

**EV impact:** At trick 1, the sampler is making its most consequential decisions (first play sets the tempo for the whole round) on only 30 worlds. A J-of-trump lead vs a side-suit Ace lead is often separated by < 20 raw points per world. With 30 worlds the standard error is ~±3.6 (σ/√n for σ≈20). With 100 worlds it would be ±2.0. The sampler can make wrong decisions at trick 1 simply from sampling noise that would be eliminated by the fix.

---

## 2. Known Issues — Verification Status

| Issue ID | Description | Status in v0.4.7 |
|---|---|---|
| H-2 (MASTER) | numWorlds scaling inverted | STILL PRESENT (lines 575–578) |
| B-99 likelyKawesh teammate contamination | desire cleared for teammates | FIXED (line 236 `sIsOpponent` guard) |
| H-6 fallback meldPins | fallback path missing meldPins | FIXED (lines 292–315) |
| desire map defender modeling | defenders get empty desire | STILL PRESENT (GAP-S2) |
| sampleConsistentDeal rank-distribution bias | no within-void rank distribution model | NEW ANALYSIS (GAP-S3, GAP-S4) |

---

## 3. New Angles — Investigation Results

### 3.1 Bid-card pinning: should J/9 of trump be hard-pinned?

**Finding (GAP-S1 above):** The sampler does not hard-pin J and 9 of the declared trump suit to the bidder. They receive desire weights 50 and 40 respectively, which at pickProb=0.70 gives roughly 65–70% placement probability per world. In ~30–35% of worlds, one or both of J/9 of trump lands on a defender. A world where a defender holds JH in a Hearts Hokm contract is a structurally corrupt world: the bidder cannot reliably pull trump, and all rollout scores for that world are pessimistic for the bidder team. Since the bidder is our partner in half of all seat configurations (when we are the partner), these corrupt worlds systematically underestimate the value of aggressive trump-pull plays, causing the sampler to prefer defensive plays even when aggressive trump pull is correct.

**Recommended fix:** Promote J and 9 of the declared trump suit to hard-pinned cards when the contract is Hokm, similar to how `pinCard` (the bid card) is handled. Add them to a `bidderPins` set and pre-place them into the bidder's hand before the Phase 1 biased draw. This is a small extension of the existing pin mechanism (5–8 lines of code).

### 3.2 Future meld possibilities: 4th card of a Carre

**Finding (GAP-S5 above):** The sampler does not reason about partial Carre completions when no meld was declared. This is extremely low frequency (requires exactly 3 cards of a rank to be observed played without a Carre declaration, which means the 4th went to another seat who also didn't declare it — rare). The meld-pin system handles declared melds correctly. **No action recommended** for this sprint; flag for completeness only.

### 3.3 Trump-distribution bias

**Finding (GAP-S3 above):** The sampler does not enforce a trump-count constraint at the team level. Bidder-team (2 seats) is expected to hold 5–6 of 8 trump in a Hokm contract. The current sampler biases trump toward the bidder seat via `strong` desire map but not toward the bidder's partner. The partner desire map only receives `pSignalSuit` (a non-trump suit preference). In worlds where the partner holds 0–1 trump and each defender holds 3–4, the rollout overestimates opponent trump control and causes the sampler to play defensively when active trump-pull is correct.

**Recommended fix:** After building the `strong` desire map for the bidder, add a moderate trump desire for the partner seat as well (weight ~15 for all remaining trump after the bidder's allocation). This could be expressed as: if the contract is Hokm and `s == partner`, add `desire[trump_suit_as_suit_key] = 15` (using the suit-match branch: `desire[C.Suit(c)] and 20` at line 248 will pick it up). This is a 1-line addition.

### 3.4 Belote bias

**Finding (GAP-S4 above):** K and Q of trump receive weights 10 and 10 in `getStrongCards`. Co-location probability (both K and Q landing on the same seat) is not explicitly enforced. With 70% pick probability and the pool depletion dynamics, the actual co-location rate in sampled worlds is roughly (0.70 × 0.70) + overlap effects ≈ ~55-60% when both are available. Given that the real game has the bidder holding Belote at significantly higher than random rates, sampled worlds underestimate this. This is low-severity because the rollout scoring correctly handles the case (ScoreRound detects Belote from final trick plays), but it is a modelling gap.

**No action required** unless deeper calibration is wanted; the effect on win-rate is second-order.

---

## 4. Summary Table — All Gaps by Severity

| ID | Component | Description | Severity | Status |
|---|---|---|---|---|
| H-2 (MASTER) | PickPlay numWorlds | Scaling inverted: 30 worlds early, 100 late — should be reversed | HIGH | OPEN, confirmed present v0.4.7 |
| GAP-S1 | sampleConsistentDeal | J and 9 of trump not hard-pinned to bidder in Hokm | MEDIUM-HIGH | NEW |
| GAP-S2 | sampleConsistentDeal | Defender desire map empty; side Aces not biased to defenders | MEDIUM | KNOWN (confirmed still present) |
| GAP-S3 | sampleConsistentDeal | Trump count not constrained at team level; partner under-trumped in worlds | MEDIUM | NEW |
| GAP-S4 | sampleConsistentDeal | Belote K+Q co-location not forced to bidder | LOW-MEDIUM | NEW |
| GAP-H1 | heuristicPick | Void inference not updated during rollout simulation | LOW | NEW |
| GAP-H2 | heuristicPick | Position-4 smother logic absent (minor; lowestWinner is safe) | LOW | NEW |
| GAP-S5 | sampleConsistentDeal | Partial Carre (3 played, 1 unknown) not modeled | LOW (rare) | NEW |

---

## 5. Fix Priority Order

1. **H-2 numWorlds inversion** — highest EV gain, 2-line fix, no risk. Fix is: `if numTricks <= 3 then numWorlds = 100 elseif numTricks <= 5 then numWorlds = 60 else numWorlds = 30 end`.

2. **GAP-S1 J/9 trump hard-pin** — eliminates ~30% of structurally corrupt Hokm worlds where J/9 lands on defender. ~8–10 lines, low risk.

3. **GAP-S3 partner trump desire** — 1-line fix. Add `desire[contract.trump_suit] = 15` for the partner seat when contract is Hokm. Reduces under-trumped-partner worlds.

4. **GAP-S2 defender side-Ace desire** — 1-2 lines. Add `desire["A"..sidesuit] = 8` for each non-trump side suit in the defender's `desire` map. Requires identifying which seats are defenders.

5. **GAP-S4 Belote co-location** — Low severity, deferred. Optional: raise K and Q weights from 10 to 20 for the bidder.

---

## 6. Appendix — Code Locations

| Finding | File | Lines |
|---|---|---|
| numWorlds scaling | `BotMaster.lua` | 575–578 |
| getStrongCards | `BotMaster.lua` | 39–55 |
| sampleConsistentDeal desire map | `BotMaster.lua` | 213–214 |
| sampleConsistentDeal bid-card pin | `BotMaster.lua` | 138–146, 205 |
| sampleConsistentDeal meld pins | `BotMaster.lua` | 162–178 (primary), 292–315 (fallback) |
| likelyKawesh opponent gate | `BotMaster.lua` | 235–238 |
| heuristicPick trump-filter fix (C-5) | `BotMaster.lua` | 482–491 |
| rolloutValue reward signal | `BotMaster.lua` | 535–549 |
| PickPlay dispatch + numWorlds | `BotMaster.lua` | 555–595 |
| Trump rank constants | `Constants.lua` | 50 |
| ScoreRound (Belote, meld scoring) | `Rules.lua` | 471–733 |
| likelyKawesh inference | `Bot.lua` | 358–381 |
| OnPlayObserved aceLate counter | `Bot.lua` | 350–356 |
