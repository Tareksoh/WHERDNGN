# Audit 51: human SWA at 5+ cards (asymmetric vs bot cap) — v0.9.0

## Verdict
CONFIRMED. Human SWA path has no upper hand-count cap. A human at 5/6/7/8 cards can route through `N.LocalSWA` and reach `R.IsValidSWA` host resolution. Bots are capped at `#hand <= 4`. Per video #35 the 5+ regime is "mandatory permission" — but in code the existing permission flow is the SAME as 4-card flow, so the asymmetry is only "bot can't try"; the determinism check still gates correctness. Result: not a scoring exploit, but a Saudi-convention violation (5+ should not even be offered) and a bot-fairness asymmetry.

## Evidence

### 1. `N.LocalSWA` — no hand-count check
`Net.lua:2452-2565`. Pre-conditions checked: pause, phase, localSeat, contract, allowSWA, in-flight `swaRequest` matching same caller. Line 2465 reads `handCount = #(S.s.hand or {})` but only stores it; never compared to any cap. Pre-v0.5.17 had `if needPerm and handCount >= 4` — collapsed to unconditional `if needPerm` at line 2481 (comment 2478-2480 confirms intentional removal so banner displays cards "in every scenario"). 6/7/8-card calls accepted identically to 3-card calls.

### 2. UI button — no gate
`UI.lua:2011`: shown whenever `swaEnabled and not swaPending`. No `#hand` check. Round-start (8 cards) human sees the SWA button identically to 3-card endgame.

### 3. Permission flow at 5+ — IDENTICAL to 4
Single code path: `MSG_SWA_REQ` broadcast → `K.SWA_TIMEOUT_SEC=5` window → bot-opponent auto-accept (line 2510) → `HostResolveSWA`. No "5+ category" exists in `Constants.lua` / `State.lua`. `WHEREDNGNDB.swaRequiresPermission` is a binary toggle (any count or none). No per-count regime — video #35's "≤3 instant / 4 جلسة-conditional / 5+ mandatory" tri-regime collapses to binary "perm required / skipped".

### 4. Round-start (8-card) SWA — does NOT reject; relies on `R.IsValidSWA`
At 8 cards remaining (round start, no tricks played), `HostResolveSWA` (Net.lua:2890) builds `trickPlays={}, leader=S.s.turn or callerSeat` and calls `R.IsValidSWA`. The minimax (Rules.lua:349-467) recurses over the full ~8-card×4-seat tree. With Saudi-strict-strict (every-partner-play branch), an 8-card claim almost always fails determinism → Qaid penalty to opp. Sound from a scoring standpoint, but the player still pays the full hand-total Qaid for a click that should have been blocked at the UI.

### 5. Cross-team Takweesh on 5+ SWA — fires correctly
`HostResolveTakweesh` (Net.lua:2120) clears `swaRequest` (line 2137) and runs the illegal-play scan independent of hand count. Counter on a 5+ SWA works the same as on a 4-card SWA. No bug.

## Issue summary
- Bot vs human asymmetry: bots gated at `#hand <= 4` (Bot.lua:3525); humans are not.
- 5+ mandatory permission is collapsed into "same flow as 4" — auto-accept timer fires identically.
- Recommendation: add `if handCount > 4 then return end` (or warn) at top of `N.LocalSWA`, OR distinguish 5+ banner with no auto-accept (true mandatory). Current behavior is Saudi-rule incorrect but is rescued by the determinism check from being a scoring exploit.
