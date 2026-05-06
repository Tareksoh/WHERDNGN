# Wave 1 — Cluster A4 Findings
## Memory Integration / Edge Cases
Auditor: A4 agent | Date: 2026-05-03 | Codebase: WHEREDNGN v0.4.4

---

### A-87 — Trump tempo counter fires only on trick.plays count == 1 (leads only)

**VERDICT: BUG-CONFIRMED (benign by design — but the comment is misleading and the count-point is post-ApplyPlay, not pre)**

**File:line:** `Bot.lua:244-254`

**Evidence:**
`OnPlayObserved` is called from `Net.lua:1065-1066` AFTER `S.ApplyPlay(seat, card)` has already executed. `ApplyPlay` appends the play to `s.trick.plays` before returning (`State.lua:1071`). Therefore when `OnPlayObserved` reads `#trickPlays` at `Bot.lua:245`, the just-played card is already in `s.trick.plays`. A lead play (first card of the trick) will yield `#trickPlays == 1` — exactly the guard at line 248 — so the condition correctly identifies leads. This is the documented intent in the comment at line 239-243 ("Audit fix: … `#trickPlays == 1` after ApplyPlay already identifies a lead"). The logic is therefore correct AS IMPLEMENTED. However, the comment saying "after ApplyPlay already identifies a lead" is only true because ApplyPlay appends before returning; a reader who does not trace `ApplyPlay` would assume count=0 for the lead. There is no latent off-by-one bug here, but the code is fragile: if `ApplyPlay` ever stops mutating `trick.plays` synchronously before calling the observer, the condition would silently break. The original concern ("if ApplyPlay hasn't pushed yet, count=0 for a lead") is factually resolved — `ApplyPlay` always pushes first (`State.lua:1071`). The `leadSuit` in the loopback path (`Net.lua:1063`) is captured BEFORE `ApplyPlay`, confirming the call ordering is intentional.

**Minimal-diff fix recommendation:**
No functional change required. Add a clarifying comment at `Bot.lua:245` noting that `trickPlays` is read AFTER `ApplyPlay` appends the card, so `#trickPlays == 1` means "this IS the lead play". This removes the fragility risk for future readers.

---

### A-88 — wasIllegal check: lastPlay match by seat AND card

**VERDICT: NOT-CONFIRMED (race condition is not present; rapid-succession case is handled)**

**File:line:** `Bot.lua:211-214`

**Evidence:**
The `wasIllegal` detection reads `S.s.trick.plays[#S.s.trick.plays]` — the LAST play in the current trick array — then checks `lastPlay.seat == seat AND lastPlay.card == card`. This is called from `OnPlayObserved(seat, card, leadSuit)` which is invoked from `Net.lua:1065-1066` IMMEDIATELY after `S.ApplyPlay(seat, card)`. Because `ApplyPlay` has a one-play-per-seat-per-trick guard (`State.lua:1050-1052`) that returns early if the seat already has a play in the trick, and because `ApplyPlay` appends synchronously before control returns to `Net.lua`, the last entry in `trick.plays` is guaranteed to be the play that was just applied for `seat`. The `seat AND card` dual-check is therefore always satisfied when the play was illegal. The concern about "two bots playing in rapid succession" does not apply: bot actions are always dispatched by the host via `C_Timer.After`, and each timer callback calls `S.ApplyPlay` and `OnPlayObserved` for exactly one play before returning. WoW addon Lua is single-threaded (no preemptive concurrency); timers cannot interleave within a callback. There is no race condition path. A theoretical multi-play scenario (e.g., desync replay) would require `isReplay=1` flag and bypasses the `OnPlayObserved` call anyway (`Net.lua:1068`).

**Minimal-diff fix recommendation:**
None required. The dual-check is correct and the race concern does not apply in WoW's single-threaded Lua timer model.

---

### A-91 — PickBid R1/R2 phase gate: Bot doesn't check S.s.phase

**VERDICT: NOT-CONFIRMED (phase gating exists in MaybeRunBot's bidding dispatch)**

**File:line:** `Bot.lua:540-543`, `Net.lua:3249-3259`

**Evidence:**
`Bot.PickBid` itself (`Bot.lua:540`) does not check `S.s.phase` — it reads only `S.s.bidRound` and the hand. However, `Bot.PickBid` is called exclusively from one place: the bidding timer callback inside `N.MaybeRunBot` (`Net.lua:3278`). That callback is wrapped in a double-gated `C_Timer.After` closure. The dispatch condition entering the timer (`Net.lua:3249-3250`) requires `S.s.phase == K.PHASE_DEAL1 OR K.PHASE_DEAL2BID`. Inside the timer callback body, the same phase check is repeated at `Net.lua:3258`: `if S.s.phase ~= K.PHASE_DEAL1 and S.s.phase ~= K.PHASE_DEAL2BID then return end`. A phase=PHASE_PLAY scenario where `MaybeRunBot` is called with a stale "bid" turn pointer cannot reach `PickBid` because the play-dispatch branch (`Net.lua:3300`) would match first (it checks `phase == K.PHASE_PLAY`) and return before reaching the bidding block. Additionally, the bidding dispatch itself checks `turnKind == "bid"` which would be "play" in PHASE_PLAY. The cascading phase guards make erroneously calling `PickBid` during PHASE_PLAY structurally impossible through the normal dispatch path.

**Minimal-diff fix recommendation:**
No functional change required. As a defensive hardening, adding a `if S.s.phase ~= K.PHASE_DEAL1 and S.s.phase ~= K.PHASE_DEAL2BID then return K.BID_PASS end` guard at the top of `Bot.PickBid` would make the function self-defending against future callers. Currently the guard lives only in `MaybeRunBot`.

---

### A-92 — PickPlay dispatching: Saudi Master → Fzloky → M3lm → Advanced → Basic fallback chain

**VERDICT: VARIANT-FOUND — tier dispatch is a two-level cascade (Saudi Master / Bot.PickPlay), not a four-level chain; multiple tiers CAN be active simultaneously but do NOT double-evaluate**

**File:line:** `Net.lua:3343-3348`, `Bot.lua:48-79`, `Bot.lua:1110-1124`, `BotMaster.lua:494-534`

**Evidence:**
The actual dispatch in `Net.lua:3343-3348` is a two-step cascade: (1) if `IsSaudiMaster()` is true, call `B.BotMaster.PickPlay(seat)`; (2) if that returns `nil`, fall back to `B.Bot.PickPlay(seat)`. There is no separate Fzloky → M3lm → Advanced → Basic chain at the dispatch site. Those tiers are not separate pickers; they are feature flags that gate BRANCHES WITHIN `Bot.PickPlay` (`pickLead`, `pickFollow`) and within `Bot.PickBid`. Specifically: `Bot.IsM3lm()` returns true when `m3lmBots`, `fzlokyBots`, OR `saudiMasterBots` is true (`Bot.lua:60-64`); `Bot.IsFzloky()` returns true when `fzlokyBots` OR `saudiMasterBots` is true (`Bot.lua:71-74`); `Bot.IsAdvanced()` returns true for any of the four flags (`Bot.lua:50-54`). This means when `saudiMasterBots` is set, ALL tier predicates return true simultaneously. There is no double-evaluation: `BotMaster.PickPlay` runs the ISMCTS sampler (which internally calls `heuristicPick`, a self-contained copy of Advanced heuristics, NOT `Bot.pickLead`/`Bot.pickFollow`), and `Bot.PickPlay` is only called as a fallback when `BotMaster.PickPlay` returns nil. The concern about double-evaluation is not present. However, the tier hierarchy being expressed as cumulative DB flags (not an enum or explicit tier level) creates a maintenance hazard: adding a new tier requires updating all four `IsX()` functions. This is a style/architecture finding, not a logic bug.

**Minimal-diff fix recommendation:**
No functional bug to fix. For clarity, replace the four overlapping `IsX()` boolean flags with a single `BotTier()` function that returns an enum-like integer (0=Basic, 1=Advanced, 2=M3lm, 3=Fzloky, 4=SaudiMaster), and replace all `IsX()` calls with `BotTier() >= N` comparisons. This eliminates the O(N) maintenance overhead when a new tier is added.

---

### A-99 — BotMaster heuristicPick: "bidder team leads high trump" uses placeholder comment

**VERDICT: BUG-CONFIRMED (placeholder is incomplete — always picks highest-ranked legal card as trump lead, ignores whether trump are cleared)**

**File:line:** `BotMaster.lua:426-436`

**Evidence:**
In `rolloutValue`'s `heuristicPick` function, the lead branch at `BotMaster.lua:426-429` reads:
```lua
if contract.type == K.BID_HOKM and R.TeamOf(s) == bidderTeam then
    local t = highestRank(legal)  -- placeholder: lead high trump
    if C.IsTrump(t, contract) then return t end
end
```
`highestRank(legal)` is called over ALL legal cards (not filtered to trump first), and then `C.IsTrump(t, contract)` checks if the result happens to be trump. If the highest-ranked legal card is not trump (e.g., bidder has drawn trump and leads a high non-trump), the condition `C.IsTrump(t, contract)` fails silently and falls through to the defender-style `lowestRank(nonTrumps)` logic — making the bidder-team rollout play as if they're defenders on that simulated lead. More critically, the placeholder never checks whether trump have already been cleared (all 8 trump played). When trump are exhausted, leading high trump is nonsensical, but the placeholder would still try (and fail the `IsTrump` check, accidentally falling through). Contrast with `Bot.pickLead` in `Bot.lua:785-801`, which correctly checks `trumpCount`, applies the "trump-poor → cash Ace first" heuristic, and calls `highestTrump(legal, contract)` which is pre-filtered to trump-only cards. The BotMaster rollout thus underestimates bidder-team performance in endgame positions where trump are exhausted or the bidder has a side-suit Ace to cash first. The comment "placeholder: lead high trump" (`BotMaster.lua:428`) explicitly acknowledges the incompleteness.

**Minimal-diff fix recommendation:**
Replace the `highestRank(legal)` / `C.IsTrump` test in `heuristicPick` with a properly filtered trump-first pick:
1. Collect `trumpCards` from `legal` filtered by `C.IsTrump(c, contract)`.
2. If `#trumpCards > 0`, check whether bidder has fewer than 4 trump (i.e., "trump-poor" threshold mirroring `Bot.pickLead:793`); if trump-poor and a non-trump Ace exists in `legal`, return it; otherwise return `highestRank(trumpCards)`.
3. Fall through to non-trump lead logic only if `#trumpCards == 0`.
This mirrors the existing `Bot.pickLead` behavior and eliminates the silent fall-through when the overall-highest card is not trump. No external interface changes needed — `heuristicPick` is a local closure inside `rolloutValue`.
