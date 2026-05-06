# 65 — Tier Dispatch Hunt (v0.7.2)

**Verdict: CLEAN** — tier-dispatch is consistent. No mis-fires found; one
non-bug observation worth flagging.

---

## 1. Tier ordering (Saudi ⊂ Fzloky ⊂ M3lm ⊂ Advanced)

`Bot.IsAdvanced/IsM3lm/IsFzloky/IsSaudiMaster` (Bot.lua:48-79) all
OR-chain the higher flags into the lower predicate. Setting
`saudiMasterBots=true` makes all four predicates true. Setting
`m3lmBots=true` makes IsAdvanced+IsM3lm true and leaves Fzloky/Saudi
false. This is correct ⊂ semantics.

Direct flag-reads outside helpers:
- `BM.IsActive()` (BotMaster.lua:132-134) — reads only `saudiMasterBots`.
  Identical to `Bot.IsSaudiMaster()`. OK.
- `UI.lua:2696-2699` — display-only (checkbox cascade).
- `Slash.lua:143-173` — toggles single flag at a time. **Note**: slash
  toggles do NOT auto-set lower flags, but every read site uses the
  cumulative helpers, so behaviour is correct. Verified: no consumer
  reads the raw flag and expects "Advanced behaviour ON" from
  `advancedBots == true` (it always also accepts higher tiers).

## 2. v0.5.0 C-1 delegation bypass

`Bot.PickPlay` (Bot.lua:2885-2900) delegates to `BM.PickPlay` when
`BM.IsActive()`, gated by `Bot._inRollout` (recursion guard).
`BM.PickPlay` save/restores `_inRollout` (BotMaster.lua:752-754) so
the rollout `heuristicPick` closure can call into Bot internals
without re-entering ISMCTS. Net.lua:3928 is the sole external
callsite for play decisions. **No bypass found.**

`StartTurnTimer` (Net.lua:3219) skips bot seats, so AFK auto-play
(Net.lua:3244-3290, lowest-trick-rank fallback) cannot fire on a bot.
The pcall recovery path at Net.lua:3969-3994 only fires when
`Bot.PickPlay`/`BM.PickPlay`/`PickMelds` raised — it's a degraded
last-resort and is acceptable.

## 3. Mid-game flag flip

Style-ledger writers in `Bot.OnPlayObserved` (Bot.lua:368-446) run
unconditionally at every tier — they only WRITE `_partnerStyle`.
Readers are M3lm-gated (`if Bot.IsM3lm() and Bot._partnerStyle then`,
Bot.lua:1557, 1692, 1806, 1919, 1934, 3032, 3108, 3141). Therefore a
mid-game flip M3lm OFF→ON gives the reader a complete style ledger
from round 1 onward — correct. ResetStyle fires only at round 1
(Net.lua:1710-1712); ResetMemory fires every round.

## 4. Tier-mixed seats

`State.lua:423` stores only `s.seats[seat].isBot` per-seat. **No
per-seat tier field exists.** The mixed-config tests in
test_baseline_metrics.lua / test_asymmetric_metrics.lua mutate the
GLOBAL `WHEREDNGNDB.*` flags between sub-tests, never per-seat.
Consequence: **Q4 is unanswerable as designed** — bots cannot have
heterogeneous tiers in one game; the harness flips the global between
seats only by re-running the dispatch with a different global.
Documenting as a design constraint, not a bug.

## 5. M3lm-gated reads at lower tiers

Every `_partnerStyle` read I traced is wrapped in `Bot.IsM3lm()` or
calls `styleBelTendency`/`styleTrumpTempo` which themselves do not
gate (the wrapper does). `defensiveSun` (sunFail counter) read at
Bot.lua:3032 is M3lm-gated. Fzloky `firstDiscard` read at
Bot.lua:1640 uses `Bot.IsFzloky()`. **No tier-leak found.**

## 6. Per-seat vs global

Global wins; no per-seat override exists.

---

## Three issues / observations

- **Slash toggles independent**: `/baloot saudimaster` toggles only
  the saudiMaster flag. Lower flags don't visibly change. Behaviour
  is still correct (helpers OR-chain), but a user inspecting
  `WHEREDNGNDB` directly might think Advanced is off. UI checkbox
  cascade hides this; CLI-only users may be confused. **Cosmetic.**
- **pcall recovery degrades to Basic**: when `BM.PickPlay` rollout
  raises and is caught (BotMaster.lua:795-813), `Bot.PickPlay`
  re-enters and runs heuristics; if heuristics ALSO raise (the outer
  pcall in Net.lua:3830), recovery uses lowest-trick-rank — even for
  Saudi Master. Documented at BotMaster.lua:787-794. **Acceptable.**
- **No per-seat tier**: heterogeneous-tier games are impossible by
  design. If Q4's premise reflects a desired feature, it requires a
  new schema (`s.seats[seat].tier`) and dispatch refactor.
