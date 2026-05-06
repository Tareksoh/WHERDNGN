# L1 — SWA + Overcall banner OnUpdate pause-skip (v0.9.0)

**Verdict:** PASS, with one minor unrendered side-effect on resume (cosmetic only).

## Diff (UI.lua, commit 9c32c50)
Both self-ticking banner OnUpdate handlers now early-return on `S.s.paused`:
- **Overcall banner** (UI.lua:1350): inserted AFTER the phase-exit hide check (1341-1343) and BEFORE the body-refresh block.
- **SWA banner** (UI.lua:1458): inserted AFTER the tick-accum gate (1453-1455) and BEFORE the phase/req hide check (1460-1462).

## Edge analysis

**(3) Freeze vs blank under pause — PASS.**
Both handlers `return` before mutating `body:SetText(...)`. The frame stays `:Show()`'d and the FontString retains its last-set text. `_lastRemain` / `_lastEnc` are also not reset. Digit visually freezes at last value. Confirmed by absence of any clearing call on the early-return path.

**(4) Unpause snap-to-actual — PASS for overcall, PARTIAL for SWA.**
Overcall recomputes `remain = ceil(windowSec - (now - startedAt))` from absolute time on every tick. After resume, the next tick (within 0.33s) renders the *true* elapsed remain — there's no "stuck" carry-forward. Note: `startedAt` is NOT bumped on resume (Net.lua:2389+), so the overcall window effectively continues counting wall-clock through the pause. This is consistent with the M1 fix's `_HostResolveOvercall` resolution path. SWA is identical (`req.ts` is the wall anchor); same behavior.

**(5) Phase-exit hide while paused — PASS for overcall, NO-OP-RISK for SWA.**
Overcall's phase-check at 1341-1343 runs BEFORE the pause check at 1350, so a phase change during pause still hides the frame. SWA's phase-check at 1460-1462 runs AFTER the pause check at 1458 — under pause, the hide path won't execute. However, host-side `swaRequest` clears (Net.lua:2137, 2552, etc.) are themselves gated by non-paused execution; in practice phase doesn't transition out of `PHASE_PLAY` mid-pause, so the SWA banner should not be left orphaned. Minor latent risk if `swaRequest` is cleared during pause via /reload restore — banner would remain visible until 1st post-resume tick re-evaluates and hides.

**(6) UX visibility under pause overlay — CAVEAT.**
`pauseOverlay` is `DIALOG` strata at `0.55` alpha black (UI.lua:1271-1272). Both banners parent to `centerPad`/default strata = `MEDIUM`. Pause overlay sits ABOVE both banners, dimming them. Frozen digits visible but legibility is reduced. Pause button (FULLSCREEN_DIALOG) is bumped above overlay; banners are NOT. Acceptable for the use case (player isn't supposed to act during pause), but worth a follow-up to bump banner strata or hide them entirely under pause for clarity.

## Bottom line
Fix lands as advertised. Frozen-digit, snap-on-resume, and phase-exit-hide all behave correctly for the realistic state-machine paths. The SWA hide-after-pause-check ordering and dim-overlay legibility are noted as low-priority follow-ups, not regressions.
