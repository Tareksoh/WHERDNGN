# Wave 8 C1 — Dynamic Adaptation (cont) + Partner Coordination Batch A

---

## B-70 — Saudi Baloot Bel-saturation: social Bel degrades style ledger

| Field | Detail |
|---|---|
| SIGNAL/MISTAKE | MISSING FEATURE — no saturation guard on `bels` counter |
| FREQUENCY | Every multi-round game against a human who Bels as social custom (common in casual Saudi play), occurring from round 3 onward once `m.bels > 3` |
| BOT-EXPLOITS-IT | NO — the ledger is maintained but `styleBelTendency` is never called anywhere (confirmed by wave7_C5/B-71 finding and re-verified here). The `bels` counter in `Bot._partnerStyle[seat]` (Bot.lua:142, accumulated by `Bot.OnEscalation` Bot.lua:162–172) saturates correctly at high values, but because `styleBelTendency` (Bot.lua:181–187) has no caller in the codebase, a saturated bels counter has zero effect on bot decisions. The primary concern raised in B-70 is therefore moot in a pure bot-exploitation sense. However, a secondary concern is valid: `partnerEscalatedBonus` (Bot.lua:496–534), which IS wired into `PickDouble`/`PickTriple`/`PickFour`/`PickGahwa`, reads `contract.doubled` (the current-round Bel flag), not the lifetime `bels` counter. So a habitual-Beler's escalations do not artificially inflate the partner bonus — those paths are correctly isolated. The saturation guard proposed in the prompt (suppress `partnerStyle` usage for the seat when `bels > 3`) would logically apply to `styleBelTendency`, but since that function is already dead code, implementing the guard before wiring the function provides no benefit. |
| file:line | Bot.lua:181–187 (`styleBelTendency` — dead code), Bot.lua:142 (`bels` counter), Bot.lua:162–172 (`OnEscalation`) |
| fix | Wire `styleBelTendency` into `Bot.PickTriple` first (as proposed in wave7_C5/B-71). Only after that, add the saturation guard: before calling `styleBelTendency`, check `if m.bels > 3 then return nil end` so a habitual-Beler's pattern is treated as uninformative noise rather than a strong signal. This two-step ordering prevents implementing a guard on a function that produces no output. |

---

## B-74 — Human over-ruffing (ruffing partner's winning trick)

| Field | Detail |
|---|---|
| SIGNAL/MISTAKE | MISSING FEATURE — partner-ruff by opponents is not recorded in `Bot._memory` |
| FREQUENCY | Occasional (1–2 instances per game, mostly from weaker human players) |
| BOT-EXPLOITS-IT | NO — no tracking mechanism exists. `Bot.OnPlayObserved` (Bot.lua:200–270) records: (a) played cards, (b) void inferences, (c) firstDiscard (Fzloky signal), (d) trump tempo via `Bot._partnerStyle`. It does NOT record whether a seat ruffed into a trick where their own partner was the current winner. The check would require: after each ruffing play (off-suit trump in Hokm, i.e. `cardSuit == contract.trump` and `leadSuit ~= contract.trump`), determine if the play's seat's partner was `curWinner` before the ruff. The data is available: `R.CurrentTrickWinner` and `R.Partner` are both accessible in `OnPlayObserved`, and `Bot._memory[seat]` is already the right accumulation point. However, no counter exists (compare `emptyMemory()` at Bot.lua:98–116: fields are `void`, `played`, `firstDiscard`, `akaSent` — no `partnerRuffs`). The claimed exploitation path (create more trump-lead situations to bait the error-prone seat into ruffing their partner) has no execution hook. Note: the `partnerWinning` flag IS computed in `pickFollow` (Bot.lua:917) and `BotMaster.lua:373`, but only to decide whether the BOT should conserve cards — it is not used to diagnose human opponents. |
| file:line | Bot.lua:98–116 (`emptyMemory` — missing `partnerRuffs` field), Bot.lua:200–270 (`OnPlayObserved` — missing ruff check), Bot.lua:917 (`pickFollow` `partnerWinning`) |
| fix | Add `partnerRuffs = 0` to `emptyMemory()`. In `OnPlayObserved`, after void inference: if `leadSuit` is not nil, `C.IsTrump(card, S.s.contract)` is true (the off-suit play is trump), and `R.CurrentTrickWinner({leadSuit=leadSuit, plays=S.s.trick.plays}, S.s.contract) == R.Partner(seat)`, then increment `Bot._memory[seat].partnerRuffs`. Then in `pickLead` (M3lm gate), if an opponent's `partnerRuffs >= 2`, increase the frequency of leading trump in that suit earlier (tricks 3–5) to create ruffable positions where the error-prone opponent may ruff in over their partner. |

---

## B-75 — Human tendency to lead highest card (vs bot's lead-lowest)

| Field | Detail |
|---|---|
| SIGNAL/MISTAKE | MISSING FEATURE — no opening-lead pattern detector for human opponents |
| FREQUENCY | Every game where a human defender opens a new suit; potentially readable within 2–3 leads |
| BOT-EXPLOITS-IT | PARTIALLY — the bot's lead heuristic is the opposite of the human pattern but this asymmetry is unused for inference. The bot leads the LOWEST card from its longest non-trump suit (Bot.lua:880–888, `lowestByRank(fromLongest, contract)`), a standard Belote/Coinche convention. Human Saudi players typically lead the HIGHEST card to "test" whether it gets beaten. However, the bot does not track opening-lead ranks per opponent seat. `Bot._partnerStyle` has `trumpEarly`/`trumpLate` (Bot.lua:143) but no `leadsHigh`/`leadsLow` counter for non-trump suit opens. The Fzloky `firstDiscard` mechanism (Bot.lua:222–226) captures the first OFF-SUIT discard (fail-to-follow), but not a LEAD when following suit — these are structurally different observations. An opponent who leads AH (highest heart) reveals they hold the Ace and are testing, whereas the bot leading 7H reveals shortness. The bot reads its own opponent's first discard as a suit-preference signal but misses the entirely separate inference available from the rank of a suit-lead. This inference is most valuable for BotMaster's determinization (BotMaster.lua:122–274): if an opponent led high in a suit in trick 2, the sampler should weight their hand as holding the remaining high cards in that suit. |
| file:line | Bot.lua:143 (`emptyStyle` — missing `leadsHigh`/`leadsLow` counters), Bot.lua:880–888 (`pickLead` low-from-longest), BotMaster.lua:209–231 (`sampleConsistentDeal` biasing) |
| fix | Add `leadsHigh = 0, leadsLow = 0` to `emptyStyle()`. In `OnPlayObserved`, when `leadSuit` is nil (opening a new trick), record whether the card's rank is "high" (A, T, K — ranks 7–8 of the 8-rank order) vs "low" (7, 8, 9 — ranks 1–3) into `Bot._partnerStyle[seat]`. Expose a derived `styleLeadsHigh(seat)` function analogous to `styleTrumpTempo`. In BotMaster's `sampleConsistentDeal`, when an opponent has `styleLeadsHigh(opp) == 1`, bias their sampled hand to include high-rank cards in the suits they have already led (opposite of the current `desire` weighting which biases the bidder toward trump). |

---

## B-76 — Human "tilt" after losing 4+ consecutive tricks

| Field | Detail |
|---|---|
| SIGNAL/MISTAKE | MISSING FEATURE — no cumulative-loss indicator in the style ledger |
| FREQUENCY | Detectable in ~20–30% of Hokm rounds where one team falls 4+ tricks behind early (tricks 1–5) |
| BOT-EXPLOITS-IT | NO — not tracked. The style ledger (`Bot._partnerStyle`) tracks lifetime aggregates across rounds but has no within-round state for "consecutive tricks lost." The round-local `Bot._memory` (Bot.lua:98–116) stores per-trick play observations but no streak counter. The `S.s.tricks` array (State.lua:52) contains the full completed-trick list with `.winner` on each entry; a streak is trivially computable from it. Specifically: to determine whether opponents have lost N consecutive tricks, count the most recent tricks where `R.TeamOf(t.winner)` equals the bot's team. But no function in Bot.lua or BotMaster.lua computes or queries this. The proposed exploitation path (human tilt → reckless leads, come-back Gahwa attempts) would manifest as a pattern in `s.bids` history (snap Gahwa when already losing) and as more aggressive leads detectable through `firstDiscard` or `leadsHigh` signals. The `scoreUrgency` / `matchPointUrgency` functions (Bot.lua:443–487) only use cumulative game scores, not within-round trick-streak data. |
| file:line | Bot.lua:443–487 (`scoreUrgency`, `matchPointUrgency` — no within-round streak input), Bot.lua:98–116 (`emptyMemory` — no streak field), State.lua:52 (`s.tricks` — data source) |
| fix | Add a helper `recentOppTrickStreak(seat)` that reads `S.s.tricks` backwards and counts consecutive tricks won by the bot's team (opponents of `seat` are losing those). Gate on `Bot.IsM3lm()`. If streak >= 4 and we're within the first 6 tricks, increase play aggression: in `pickLead`, prefer leading high-point non-trump suits (to prevent come-back ruffing opportunities) rather than leading low. Optionally add a `tiltStreak = 0` integer to `emptyMemory()` and increment it in `OnPlayObserved` for post-round cross-analysis. |

---

## B-77 — Exploiting human over-commitment to one suit

| Field | Detail |
|---|---|
| SIGNAL/MISTAKE | PARTIALLY EXPLOITED — void memory correctly detects the void, but the exploitation logic requires `opponentsVoidInAll` (both opponents void simultaneously) |
| FREQUENCY | Common — 1–2 such situations per Hokm round once a human becomes void in one suit via repeated leading |
| BOT-EXPLOITS-IT | PARTIALLY — the free-trick exploit fires only if BOTH opponents are void; the more common case of ONE opponent void is missed. The bot has correct void tracking: `mem.void[leadSuit] = true` is set in `OnPlayObserved` (Bot.lua:218) on any legal off-suit play. `opponentsVoidInAll(seat, suit)` (Bot.lua:272–281) checks `R.TeamOf(opp) ~= R.TeamOf(seat)` for both opponent seats. In `pickLead` priority 1 (Bot.lua:823–838), the bot leads its HIGHEST card in a suit only when `opponentsVoidInAll` returns true — requiring both opponent seats to be known void. However the human over-commitment pattern (B-77) typically makes ONE opponent void first (the one who keeps leading), with the second opponent potentially still holding cards. The single-void case is more common and already actionable: if ONE opponent is void and we can lead a suit where we hold the boss (Ace), we should cash it, since only one ruffing threat remains (not the partner-ruff scenario B-74, but an opponent ruff). The current code misses this by requiring the stricter `opponentsVoidInAll` condition. Additionally, the `suitCount` aggregation in `pickLead` (Bot.lua:815–820) does not inspect the `void` map of individual opponents when selecting the longest suit to lead from — a suit where one opponent is void and we hold A/K should be prioritized even if it's not our longest suit. |
| file:line | Bot.lua:272–281 (`opponentsVoidInAll` — requires both void), Bot.lua:823–838 (priority-1 free-trick path — `opponentsVoidInAll` only), Bot.lua:815–820 (`suitCount` for longest-suit selection — ignores per-opponent voids) |
| fix | Add a second helper `anyOpponentVoidIn(seat, suit)` that returns true if at least ONE opponent is void in `suit`. In `pickLead` priority 1 (Bot.lua:823), retain the `opponentsVoidInAll` check for guaranteed free tricks, but add a priority-1.5 path: if `anyOpponentVoidIn(seat, suit)` and we hold the Ace of that suit (unbeatable regardless of the non-void opponent following), lead it. The unbeatable-Ace condition prevents losing to the non-void opponent. Additionally, in `pickLead`'s longest-suit selection (step 3), when `Bot.IsM3lm()`, apply a bonus to suits where at least one opponent is known void — bias toward those suits even if they are not our longest. |

---
