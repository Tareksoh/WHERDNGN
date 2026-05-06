# WHEREDNGN v0.4.4 — Swarm Audit Master Report
## 200-Agent Campaign | 8 Waves | 40 Clusters | 2026-05-03

---

## 1. Executive Summary

The 200-agent audit of WHEREDNGN v0.4.4 (Saudi Baloot WoW addon) produced **5 confirmed critical bugs**, **~15 high-priority calibration/logic errors**, and **~25 missing-feature gaps** in the human-pattern recognition layer. The most impactful single finding (A-81/A-84): `Bot.OnPlayObserved` is never called for bot plays, AFK plays, or bot error-recovery plays — the void-inference, firstDiscard/Fzloky, and AKA deduplication subsystems are entirely inert for roughly half of all card plays. Two style-metric functions (`styleBelTendency`, `styleTrumpTempo`) are defined and fed data but never called by any picker — confirmed by 8+ independent clusters. The Ashkal bid path is structurally unreachable (Sun-return fires at Bot.lua:583 first). PickDouble applies a 0.5x trump-weight that blocks Hokm defenders from ever Beling. The cross-cutting architectural gap — no `Bot.IsBotSeat()` helper in Bot.lua — causes all human-signal paths to remain unguarded. Recommended fix order: OnPlayObserved dispatch first, then dead-code wiring, then isBot guards, then calibration.

---

## 2. Critical Bugs — Fix Immediately

These are confirmed code defects that produce incorrect behavior on every affected code path.

### C-1 — OnPlayObserved never called for bot plays (A-81, A-84)
| Field | Value |
|---|---|
| Files | Net.lua:~3360 (MaybeRunBot dispatch), Net.lua:~2775 (AFK timeout), Net.lua:~3394 (bot error-recovery) |
| Severity | CRITICAL — entire memory subsystem inert for ~50% of plays |
| Impact | Void inference, firstDiscard/Fzloky signals, AKA deduplication, trump tempo counters, and style ledger counters (`trumpEarly`, `trumpLate`) are never populated from bot card plays. `Bot._memory[seat].played` misses every bot-played card. Downstream: `suitCardsOutstanding` is wrong, `HighestUnplayedRank` is wrong, `opponentsVoidInAll` produces false positives. |
| Fix | After each bot card play is dispatched and applied, call `Bot.OnPlayObserved(seat, card, leadSuit, trickPlays, trickNum)` in each of the three dispatch sites listed above. Bot plays satisfy the same observation contract as human plays. |

### C-2 — Trump-ruff rollback leaves spurious void (A-75)
| Field | Value |
|---|---|
| Files | Bot.lua:217-218, Bot.lua:262-269 |
| Severity | CRITICAL — incorrect void flag persists for the round |
| Impact | When a play is rolled back after an illegal ruff detection, `rollbackPlay` correctly nils `firstDiscard` but does NOT clear the `mem.void[leadSuit] = true` that was set during the forward-play observation. The spurious void persists, causing incorrect free-trick inferences and wrong `suitCardsOutstanding` counts for the remainder of the round. |
| Fix | In `Bot.rollbackPlay` (Bot.lua:262-269), after clearing `firstDiscard`, also clear `Bot._memory[seat].void[leadSuit]` for any leadSuit that was set during the rolled-back play. |

### C-3 — A/T sure-stopper not gated to Sun contract (A-37)
| Field | Value |
|---|---|
| Files | Bot.lua:1003-1012 |
| Severity | CRITICAL — fires in Hokm where non-trump Aces can be trumped |
| Impact | The pos-2 "sure stopper" shortcut at Bot.lua:1003-1012 plays the highest non-trump Ace/Ten when the lead is in a suit the bot controls. This logic is not gated on `contract.type == "SUN"`. In a Hokm contract, a non-trump Ace is NOT a sure stopper — an opponent void in that suit can over-ruff it. The bot sacrifices its Ace when it should duck. |
| Fix | Wrap the sure-stopper block at Bot.lua:1003-1012 with `if contract.type == K.BID_SUN then ... end` or equivalently add `and not isTrumpContract` to the existing guard. |

### C-4 — PickDouble 0.5x trump-weight blocks Bel for strong defenders (A-97)
| Field | Value |
|---|---|
| Files | Bot.lua:1161 vs Bot.lua:1193 |
| Severity | CRITICAL — legitimate Bels blocked systematically |
| Impact | `PickDouble` computes hand strength at Bot.lua:1161 using `0.5 * trumpStr + sideStr`, applying a 50% discount to trump. `escalationStrength` (called from PickTriple/PickGahwa) uses the full trump value. A Hokm defender with J+9+A of trump scores ~42 trump points but only sees 21 in PickDouble — the combined score cannot reach `BOT_BEL_TH = 70`. The bot never Bels strong Hokm contracts when its entire hand strength is concentrated in trump. |
| Fix | Change the trump weight in PickDouble from 0.5 to 1.0 (or at minimum 0.75) to align with the scale used by escalationStrength. Alternatively derive PickDouble from the same `escalationStrength` function with a context flag. |

### C-5 — heuristicPick rollout uses highestRank(all legal), not filtered trump (A-99)
| Field | Value |
|---|---|
| Files | BotMaster.lua:426-436 |
| Severity | CRITICAL — rollout policy selects wrong card in bidder-lead scenarios |
| Impact | The `heuristicPick` bidder-lead branch at BotMaster.lua:427-429 calls `highestRank(legal)` on the full legal-cards list, then checks `if C.IsTrump(card, contract)`. When the highest-ranked legal card is NOT trump (e.g., the Ace of side suit outranks J of a depleted trump in the combined rank table), the trump check fails and `heuristicPick` silently falls through to the next branch, returning a random fallback card. The bidder-lead rollout policy is therefore wrong whenever the highest legal card is a non-trump card. |
| Fix | Replace `highestRank(legal)` with `highestRank(trumpCards)` where `trumpCards = C.FilterTrump(legal, contract)`. Add a fallback only when `trumpCards` is empty. |

---

## 3. High-Priority Warnings

### H-1 — BOT_ASHKAL_TH=65 makes Ashkal bid structurally unreachable (A-08)
| Field | Value |
|---|---|
| Files | Bot.lua:583, Bot.lua:623, Constants.lua:256 |
| Severity | HIGH — dead bid path; entire Ashkal strategy never fires |
| Impact | At Bot.lua:583, `if sunStr >= thSun then return BID_SUN end` fires before the Ashkal check at Bot.lua:623. Since `thSun (50) < BOT_ASHKAL_TH (65)`, any hand that reaches Ashkal eligibility has already been caught by the Sun return. Ashkal can never be selected. |
| Fix | Reorder: evaluate Ashkal eligibility before the Sun-strength return. Move the Ashkal check above the `return BID_SUN` at line 583. Also verify the `sideSuitAceBonus` comparison at Bot.lua:612-620 for correctness in the reordered context. |

### H-2 — numWorlds scaling inverted (A-60, B-53)
| Field | Value |
|---|---|
| Files | BotMaster.lua:514-517 |
| Severity | HIGH — ISMCTS weakest when it matters most (early tricks) |
| Impact | `BASE_NUM_WORLDS = 30` is used in early tricks and `MAX_NUM_WORLDS = 100` in late tricks. This is backwards: early-trick decisions require more worlds because uncertainty is highest. Late-trick decisions have fewer unknown cards and need fewer samples. Confirmed independently by wave 4 (A-60) and wave 7 (B-53). |
| Fix | Invert the scaling: start at 100 worlds for tricks 1-3, scale down to 30 for tricks 7-8. Or use `numWorlds = max(30, 100 - trickNum * 10)`. |

### H-3 — Singleton lead fires on high-rank cards (A-47)
| Field | Value |
|---|---|
| Files | Bot.lua:840-847 |
| Severity | HIGH — leads singleton Ace/K/Q, wasting honor cards |
| Impact | No rank filter on the singleton-lead shortcut. Singletons should only be led when low-rank (7/8/9) to gain ruffing entries, not when holding the boss. |
| Fix | Guard: `if C.RankOf(card) <= K.NINE then ... end` before firing the singleton shortcut. |

### H-4 — pos-4 cheapest winner uses cross-scale TrickRank (A-39)
| Field | Value |
|---|---|
| Files | Bot.lua:1048-1049 |
| Severity | HIGH — selects trump-7 (rank 1) over side-suit Ace (rank 8) |
| Impact | TrickRank comparison crosses trump and plain scales. Trump 7 = rank 1; non-trump Ace = rank 8 in plain scale; scales are incomparable. Bot picks a low trump over a side-suit winner. |
| Fix | Filter candidates to all-trump or all-plain before selecting minimum-rank within the filtered set. |

### H-5 — J double-counted in escalationStrength (A-49)
| Field | Value |
|---|---|
| Files | Bot.lua:1191-1200 |
| Severity | HIGH — inflates escalation score by ~2, over-triggers escalation |
| Impact | J of trump is included in the general trump-point sum and again in the J-bonus branch. Double-count makes the bot escalate more readily than its hand justifies. |
| Fix | Exclude J from the base trump-point loop when the J-bonus branch handles it separately. |

### H-6 — Fallback deal ignores meldPins and void constraints (A-63, A-65)
| Field | Value |
|---|---|
| Files | BotMaster.lua:251-274 |
| Severity | HIGH — sampled hands violate known meld and void constraints |
| Impact | Fallback card-distribution at BotMaster.lua:251-274 ignores `meldPins` and per-seat void flags. Meld cards can appear in wrong seats; cards can be placed in suits a seat is known void in. |
| Fix | Extract constraint checking into `dealPassesConstraints(deal)` and call it in both primary and fallback paths. |

### H-7 — Combined urgency uncapped at ±22 (A-56)
| Field | Value |
|---|---|
| Files | Bot.lua:443-487 |
| Severity | HIGH — can drop BOT_BEL_TH to ~48, causing garbage Bels |
| Impact | `scoreUrgency` (+12 max) + `matchPointUrgency` (+10 max) = +22 combined. Intended cap was ±15 (per comment). BOT_BEL_TH=70 drops to 48; bot Bels garbage hands when desperate. |
| Fix | `urgency = math.min(15, math.max(-15, scoreUrgency + matchPointUrgency))` before threshold application. |

### H-8 — Near-win conservatism suppresses defensive Bel (B-46)
| Field | Value |
|---|---|
| Files | Bot.lua:449, Bot.lua:1171 |
| Severity | HIGH — bot less likely to Bel when a Bel clinches the match |
| Impact | `scoreUrgency` returns -8 near-win for ALL escalations, including defensive Bel. A near-win bot that should Bel a marginal opponent contract instead passes. |
| Fix | Add `context` parameter to `scoreUrgency`: "bid" applies -8 conservatism; "defend" applies +4. |

### H-9 — BOT_GAHWA_TH=135 exceeds realistic ceiling (A-51)
| Field | Value |
|---|---|
| Files | Constants.lua:255 |
| Severity | MEDIUM-HIGH — Gahwa effectively never bid by bot |
| Impact | A 5-card hand with J+9+A+T+K of trump scores a maximum of approximately 132 points in the `escalationStrength` function. With `BOT_GAHWA_TH = 135`, the bot can mathematically never reach the threshold on a pure trump hand, making Gahwa a dead bid for the bot. |
| Fix | Lower `BOT_GAHWA_TH` to 125 or recalibrate to empirically achievable scores using the actual `escalationStrength` formula. |

### H-10 — R1 bid history cleared before R2 threshold computed (B-80)
| Field | Value |
|---|---|
| Files | Bot.lua:556-574, State.lua:1503-1504, Net.lua:731 |
| Severity | HIGH — bot cannot detect trap-pass rounds |
| Impact | `S.s.bids` is reset in `HostBeginRound2` before the bot calls `PickBid` R2, erasing all R1 bid data. Trap-passers who passed R1 then bid strong in R2 face a bot that did not lower its threshold. |
| Fix | Snapshot `s.r1WasAllPass` (boolean) before clearing `s.bids`. In `PickBid` R2, subtract 5-8 from `thHokmR2` when true. |

### H-11 — partnerBidBonus PASS penalty not discounted for human overcaution (B-92)
| Field | Value |
|---|---|
| Files | Bot.lua:418 |
| Severity | HIGH — bot under-escalates after human partner passes |
| Impact | -10 penalty for BID_PASS applied unconditionally. Bot pass = calibrated weakness; human pass = may be overcaution. Suppresses Triple/Four/Gahwa after human partner passes. |
| Fix | `return S.IsSeatBot(partner) and -10 or -5` at Bot.lua:418. |

### H-12 — Fzloky reads human partner discard as convention signal (B-87, B-90)
| Field | Value |
|---|---|
| Files | Bot.lua:747-758, Bot.lua:848-869 |
| Severity | HIGH — incorrect lead priority all round from one human discard |
| Impact | `pickLead` interprets `firstDiscard` as a Fzloky suit-preference signal with no `isBot` check. A human discarding a high card to shed weakness misdirects the bot's lead priority for the remainder of the round. Confirmed in waves 6, 7, and 8. |
| Fix | Guard both Fzloky blocks with `if S.IsSeatBot(R.Partner(seat)) then`. |

---

## 4. Unexploited Human Tells — Track B

These are missing features where the bot collects data but fails to act on it, or does not collect data at all. Organized by impact tier.

### Tier 1 — Dead Code (data collected, function defined, function never called)

| ID | Function | File:line | Signal Missed |
|---|---|---|---|
| B-57/B-71/B-82 | `styleTrumpTempo` | Bot.lua:189-196 | Trump lead tempo — aggressive vs conservative bidder; trump-drought tell after trick 3 |
| B-59/B-71 | `styleBelTendency` | Bot.lua:181-187 | Habitual Beler discount in PickTriple/PickGahwa |
| B-66 | `styleTrumpTempo` in pickLead | Bot.lua:847-892 | Partner aggression never modifies lead strategy |

Fix for all: Wire `styleTrumpTempo` into `pickLead` (M3lm gate) to modulate trump-pull timing against aggressive opponents. Wire `styleBelTendency` into `Bot.PickTriple` to discount habitual-Beler threshold by ~8. Both require a one-line call addition in the respective pickers.

### Tier 2 — Counter Accumulated, No Derived Metric

| ID | Counter | File:line | What Is Missed |
|---|---|---|---|
| B-47 | `_partnerStyle.gahwas` | Bot.lua:169 | Opponent prior Gahwa count never used in scoreUrgency |
| B-50 | `_partnerStyle.fours`, `.gahwas` | Bot.lua:125-147 | Bot over-escalates when human plays conservative despite deficit |
| B-83 | `_partnerStyle.gahwas` (fail case) | Bot.lua:127-171 | No `gahwaFailed` counter — can't detect reckless callers |
| B-67 | No aceLate counter | Bot.lua:136-196 | A-hoarder pattern invisible to ISMCTS sampler |
| B-73 | No bid coherence | Bot.lua:126-151 | Bid-vs-play mismatch for human anchor bidders undetectable |

Fix B-47/B-50: In M3lm `matchPointUrgency`, read opponent `.gahwas`; if >= 2 and opponent trailing by 50+, add +3 to modifier. Read opponent `.fours + .gahwas`; if both == 0, dampen +6 far-behind boost to +2.
Fix B-83: Add `gahwaFailed` to `emptyStyle`; wire a `Bot.OnRoundEnd(bidderMade)` callback from `S.ApplyRoundEnd`.

### Tier 3 — No Infrastructure, Signal Requires New Tracking

| ID | Signal | Fix Summary |
|---|---|---|
| B-56 | Repeat-lead suit preference | Add `leadCount = {S=0,H=0,D=0,C=0}` to `emptyStyle`; populate in `OnPlayObserved` when `#trickPlays == 1` |
| B-61 | Defensive Sun detection | Add `sunFail` counter; increment in `OnRoundEnd` when Sun contract fails; raise PickDouble threshold by 8 when `sunFail >= 2` |
| B-62 | Length-over-quality Hokm bid | In `getStrongCards`, reduce J/9 weights for round-1 bidder without escalation history; add skepticismFactor |
| B-69 | s.target not in packSnapshot | Add `s.target` to `packSnapshot` at Net.lua:306-351 as field 30; also send in MSG_LOBBY |
| B-75 | High-vs-low opening lead | Add `leadsHigh/leadsLow` to `emptyStyle`; derive `styleLeadsHigh`; use in BotMaster biasing |
| B-77 | Single-opponent void unexploited | Add `anyOpponentVoidIn(seat, suit)` helper; use it in `pickLead` priority 1.5 for Ace-lead when void + we hold boss |
| B-80 | Trap-pass round detection | See H-10 above — snapshot `r1WasAllPass` before `s.bids` reset |
| B-82 | Trump-drought tell | After trick 3, if bidder `trumpEarly == 0`, classify as trump-poor; defend with high-point side-suit leads |
| B-95 | Opponent score-urgency in sampler | Add `opponentUrgency(oppSeat)` helper; use in BotMaster `getStrongCards` to widen sampled trump when opponent desperate |
| B-96 | Ace-exhaustion window | In `pickLead` bidder branch, after trick 3 if all side-suit Aces observed played, skip high-trump pull; lead side-suit winners instead |
| B-97 | Meld-intent lead signal | In `pickFollow` pos-2 and `pickLead`, read `S.s.meldsByTeam` opponent entries; flag declared-sequence suit as likely-next-lead |
| B-98 | A-of-trump lock after J+9 exhausted | In `pickLead` bidder branch, detect J+9 gone from pool; stop trump pull; in rollout replace `highestRank(legal)` placeholder |
| B-99 | Missed-Kawesh inference | In `OnPlayObserved`, after trick 3 if all opponent plays are rank 7/8/9, set `mem.likelyKawesh = true`; zero strong-card desire in sampler |

### Tier 4 — Signals with Implementation Complexity / Reverse-Exploit Risk

| ID | Signal | Note |
|---|---|---|
| B-63/B-93 | Bel timing hesitation | Requires `phaseEnteredAt = GetTime()` at PHASE_DOUBLE entry; reverse-exploit possible if not guarded by saturation check |
| B-76 | Human tilt after 4+ consecutive losses | `recentOppTrickStreak(seat)` from `S.s.tricks`; medium complexity, medium reliability |
| B-85 | Naive trump-back vs informed tempo | Distinguish partner `trumpEarly` from bidder `trumpEarly`; requires context flag on the counter |
| B-88 | Echo convention detection | Requires `suitPlays = {rank, trickNum}` list per seat; most valuable at SaudiMaster tier |

---

## 5. Dead Code and Infrastructure Gaps

| Item | File:line | Notes |
|---|---|---|
| `styleBelTendency` — defined, never called | Bot.lua:181-187 | Data fed via OnEscalation; 0 callers across full codebase |
| `styleTrumpTempo` — defined, never called | Bot.lua:189-196 | Data fed via OnPlayObserved; 0 callers across full codebase |
| `BOT_ASHKAL_TH` check — unreachable | Bot.lua:623, Constants.lua:256 | Sun-return at Bot.lua:583 fires first; Ashkal structurally dead |
| `contract.viaAshkal` — set but never read | State.lua:1448 | Set when Ashkal contract awarded; no caller in Bot.lua or BotMaster.lua |
| No `Bot.IsBotSeat(seat)` helper | Bot.lua (absent) | `S.IsSeatBot` exists at State.lua:624-626 but is not proxied in Bot.lua; every human-aware branch must reach into State |
| No `Bot.ResetMemory` / `Bot.Reset` umbrella | Bot.lua | Per-round reset scattered across multiple sites; B-100 (wave 5) confirmed no single reset function |
| `partnerEscalatedBonus` defender-foured branch unreachable | Bot.lua (A-52) | Branch condition never satisfied in practice |
| `contract.viaAshkal` unused in ISMCTS | BotMaster.lua | Sampler cannot bias for Ashkal-context deals |
| `.bids` R1 data cleared before R2 threshold | State.lua:1503-1504 | See H-10 — no R1 snapshot taken before clear |

---

## 6. Confirmed Correct

These items were investigated and found to be correct implementations, not bugs.

| ID | Description | Confirmed At |
|---|---|---|
| A-75 (fwd path) | Void inference forward path sets correct void flag on ruff | Bot.lua:218 — correct; only the rollback is wrong (C-2) |
| A-85 | Void inference rollback asymmetry — clearing one direction is correct | wave1_A3 |
| A-86 | seatHandSize hardcoded 8 is correct (8-card Baloot hand) | wave1_A2 |
| A-78, A-82, A-83, A-90 | Various clean angles (rolloutValue masking, nil fallback, etc.) | wave4_C5 |
| B-43 | Human void inference is working correctly (bot correctly tracks human voids) | wave1_B1 |
| B-64 | LAST_TRICK_BONUS correctly scored in rollout (simTricks has 8 entries, i==#tricks fires) | wave7_C4, Rules.lua:480-482 |
| B-68 | Bot card memory advantage (perfect recall vs human forgetting) — correct by design | wave7_C5 |
| B-18 | pos-4 cheapest winner selection correct (undocumented but valid) | wave5_C5 |
| A-40 | Smother gate at completed>=3 correct (not over-smothering) | wave3_C5 |
| B-94 | Bot does not exploit partner voids against partner — correct (opponentsVoidInAll filters to opponents only) | wave8_C4 |

---

## 7. Recommended Fix Order

Priority is based on: (1) frequency of execution, (2) severity of incorrect output, (3) blast radius across dependent features.

### Sprint 1 — Fix Memory System (unblocks everything downstream)
1. **C-1**: Add `Bot.OnPlayObserved(...)` call to the three missing dispatch sites in Net.lua. Without this, all memory/void/Fzloky/AKA fixes are testing against a broken baseline.
2. **C-2**: Fix rollback — clear the spurious `mem.void[leadSuit]` on rolled-back plays.
3. Add `Bot.IsBotSeat(seat)` proxy in Bot.lua (delegates to `S.IsSeatBot`). This single line unblocks H-12, B-09, B-14, B-31, B-33, B-60, B-87, B-90.

### Sprint 2 — Fix Critical Incorrect Decisions
4. **C-3**: Gate A/T sure-stopper to Sun contract only.
5. **C-4**: Fix PickDouble trump-weight to 1.0x.
6. **C-5**: Fix heuristicPick rollout to use `highestRank(trumpCards)`.
7. **H-4**: Fix pos-4 cross-scale cheapest-winner rank comparison.
8. **H-3**: Add rank guard (ranks 1-3 only) to singleton-lead shortcut.

### Sprint 3 — Unblock Dead Code (style signals)
9. Wire `styleBelTendency` into `Bot.PickTriple` (subtract ~8 from th when opponent `bels >= 2`).
10. Wire `styleTrumpTempo` into `pickLead` defender branch (save high trump against early-trump opponents).
11. Fix Ashkal reachability: move Ashkal check above Sun-return at Bot.lua:583.

### Sprint 4 — Calibration Fixes
12. **H-2**: Invert numWorlds scaling (100 early, 30 late).
13. **H-7**: Cap combined urgency at ±15.
14. **H-8**: Add context parameter to scoreUrgency (bid vs defend).
15. **H-9**: Lower BOT_GAHWA_TH to 125.
16. **H-5**: Fix J double-count in escalationStrength.
17. **H-6**: Apply meldPins and void constraints to fallback deal path.

### Sprint 5 — Human-Awareness Guards
18. **H-12**: Gate Fzloky signal reads on `S.IsSeatBot(partner)`.
19. **H-11**: Halve PASS penalty for human partners at Bot.lua:418.
20. **H-10**: Snapshot `r1WasAllPass` before `s.bids` reset.
21. **B-69**: Add `s.target` to packSnapshot (Net.lua:306-351, field 30).

### Sprint 6 — Style Counter Wiring (new features, lower risk)
22. Add `gahwaFailed` counter + `Bot.OnRoundEnd` callback.
23. Wire `_partnerStyle.gahwas` into matchPointUrgency (B-47, B-50).
24. Add `anyOpponentVoidIn` helper for single-void exploitation (B-77).
25. Implement B-62 skepticismFactor for length-bidder detection in getStrongCards.

---

## 8. Architectural Recommendations

### A-1 — Add Bot.IsBotSeat(seat) helper to Bot.lua
At least 12 separate findings (B-09, B-14, B-15, B-31, B-33, B-60, B-87, B-90, B-92, B-94, and others) require a human-vs-bot seat guard inside Bot.lua. Every fix currently reaches into State.lua via `S.IsSeatBot`. Add a one-line proxy in Bot.lua delegating to the existing `S.IsSeatBot` at State.lua:624-626.

### A-2 — Add Bot.OnRoundEnd(contract, bidderMade) callback
Multiple findings (B-83: gahwaFailed, B-61: sunFail, B-50: deficit response patterns) need per-round outcome data. A single `Bot.OnRoundEnd` callback wired from `S.ApplyRoundEnd` or `N._OnRound` provides a clean hook for all round-result style updates without scattering them across Net.lua dispatch sites.

### A-3 — Add Bot.Reset() umbrella function
Round-state and memory should be reset through a single function rather than at scattered call sites. `emptyMemory()` and `emptyStyle()` exist as constructors but are called directly in multiple places. An umbrella `Bot.ResetMemory(seat)` and `Bot.ResetAll()` would make the per-round reset auditable and ensure new memory fields (gahwaFailed, likelyKawesh, partnerRuffs, etc.) are automatically cleared without requiring edits at each reset site.

### A-4 — Separate defensive urgency from offensive urgency
`scoreUrgency` returns a single modifier used for both offensive bid thresholds and defensive Bel thresholds. Near-win conservatism (-8) should suppress offensive bids but not defensive Bels. Architecturally, maintain two separate urgency values: `bidUrgency` and `defenseUrgency`, which can have opposite signs in near-win scenarios (Sprint 4, item 14).

### A-5 — Separate human-partner and bot-partner code paths in escalation
`partnerBidBonus` (Bot.lua:410-427) applies bot-calibrated bonuses equally to human and bot partners. Flagged in B-01, B-02, B-09, B-14, B-92. Rather than guards at each return site, refactor into `botPartnerBidBonus` and `humanPartnerBidBonus` with different scale factors, dispatched from a single facade via `Bot.IsBotSeat(partner)`. Makes human-trust discounts explicit and auditable.

### A-6 — Document numWorlds policy
numWorlds direction was identified as inverted by two independent waves (A-60, B-53). Once fixed, add a comment at BotMaster.lua:514 stating "high worlds at trick 1 (max uncertainty), low at trick 8" to prevent regression.

### A-7 — Add s.target to packSnapshot and MSG_LOBBY
`s.target` is configurable via `/baloot target N` but absent from `packSnapshot` (Net.lua:306-351) and MSG_LOBBY. Late-joining or reloaded human clients default to 152 regardless of the actual target. The bot on the host always reads the correct value. Fix: add `s.target` as field 30 in `packSnapshot` and decode in `ApplyResyncSnapshot`; also append to MSG_LOBBY. Backwards-compatible with a field-existence check on decode.

---

*End of Master Report. 40 clusters, ~85 distinct findings, 5 critical bugs, ~15 high-priority items, ~25 Track-B gaps. Total investigated: waves 1-8, C1-C5.*
