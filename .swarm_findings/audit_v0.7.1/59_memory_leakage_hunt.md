# 59 — Memory / round-state leakage hunt (v0.7.2)

Verdict: **MOSTLY CLEAN — 2 latent issues, 1 doc bug.**

The reset wiring is solid in the happy path; the holes are all on
non-standard round-end paths and one subtle persistence vector.

## Per-bullet findings

### 1. `Bot.OnRoundEnd` — per-round state clearing
**CLEAN, with caveats.** `OnRoundEnd` (Bot.lua:263–275) is *not* a
round-state clearer — its only job is to bump `gahwaFailed` /
`sunFail` style counters. The actual per-round clear of `_memory` /
per-suit `tahreebSent` lives in `Bot.ResetMemory` (Bot.lua:141–155),
called at next-round start by Net.lua:1670 (redeal) and Net.lua:1706
(`HostStartRound`).

**Doc bug (cosmetic):** comment at Bot.lua:217 says `tahreebSent`
is reset "in `Bot.OnRoundEnd`", but it's actually reset in
`Bot.ResetMemory` (line 151). Same effective lifetime, wrong file
pointer.

### 2. `Bot.ResetStyle` granularity
**CLEAN.** Called from exactly one site: Net.lua:1710–1712, gated
`if roundNum == 1`. `ResetMemory` does *not* touch `_partnerStyle`.
`gahwaFailed` / `sunFail` / triples / fours / gahwas / leadCount
all persist game-long as designed.

### 3. `Bot._inRollout` rollout guard
**CLEAN.** BotMaster.lua:752–754 saves `prevRollout`, sets the flag,
and the v0.5.3 `pcall` wrapper (line 795) plus `_restore` closure
(line 754) guarantee restoration on every exit (including error,
nil-legal, and single-legal early returns). No leak vector found.

### 4. `S.HostStartRound` / `S.ApplyStart` per-round clears
**MOSTLY CLEAN.** `ApplyStart` (State.lua:706–777) clears
`bids`, `contract`, `tricks`, `meldsByTeam`, `playedCardsThisRound`,
`akaCalled`, `swaRequest`, `swaDenied`, `lastTrick`,
`takweeshResult`, `r1WasAllPass`. **GAP:** `belPending`,
`preemptEligible`, `pendingPreemptContract` are NOT cleared here.
They're cleared at their own success paths, but if a round ends
abnormally with one of these still set (e.g. host crash mid-Bel
window, then forced round restart), the next round inherits stale
state. ApplyResyncSnapshot at State.lua:478–486 *does* clear them,
which masks the issue on rejoin only.

### 5. `Bot._memory` vs `S.s.playedCardsThisRound`
**CLEAN.** Both reset at round start (ResetMemory at Net.lua:1670/
1706; `playedCardsThisRound={}` at State.lua:745). Resync rebuild
at State.lua:317–326 keeps them in sync.

### 6. AKA / SWA / Bel state lifetime
**LATENT BUG (SWA).** `SaveSession` marks `swaRequest` as
**non-transient** (State.lua:225, by *omission* from
`TRANSIENT_FIELDS`). If host /reloads while a round is in
PHASE_SCORE *and* an unresolved swaRequest somehow lingered,
`RestoreSession` carries it into the next round. `ApplyStart`
nils it (State.lua:767), so the leak only manifests if the next
session restore happens *before* `ApplyStart` runs — narrow but
real for crash-mid-flow.

`akaCalled` clears per-trick (State.lua:1238) and per-round.
`belPending` clears at every escalation outcome but has the same
HostStartRound gap as #4.

## Suggested fixes
- Bot.lua:217 comment → "Reset per round in `Bot.ResetMemory`".
- State.lua:706 `ApplyStart` → also nil `belPending`,
  `preemptEligible`, `pendingPreemptContract` defensively.
