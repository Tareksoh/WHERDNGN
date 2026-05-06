# Audit 37 — Trick-Resolve 2.2s Race Conditions (Net.lua `_HostStepPlay`)

HEAD = v0.7.2. Lines reference `Net.lua` unless noted.

The 2.2s `C_Timer.After` at line 1564 holds the trick view; the closure at 1565-1581 has guards on `isHost`, `paused`, `phase==PLAY`, `contract`, and `trick.plays>=4`.

## 1) Pause during the 2.2s hold — SAFE
- Pause flips `S.s.paused` (line 1569 guard bails the closure).
- Resume path (`LocalPause`, lines 2294-2297, "Codex #4 audit catch") explicitly detects `phase==PLAY && #plays>=4` and re-fires `_HostStepPlay()`, which re-arms a fresh 2.2s timer.
- **Side effect**: the timer DOES restart from zero on resume. Players see the trick for an extra full 2.2s after unpausing — minor UX but not a bug.
- Note: `_OnPause` on remote clients (line 2330) only mirrors `S.ApplyPause` — there's no remote re-fire. Only the host re-schedules, which is correct (only host runs `_HostStepPlay`).

## 2) Takweesh during the 2.2s hold — SAFE
- `HostResolveTakweesh` (line 2035) requires `phase==PLAY`, then sets phase=SCORE inside `ApplyTakweeshScore`. When the 2.2s timer fires, the `phase ~= PLAY` guard at line 1572 bails cleanly.
- The original (pre-takweesh) trick state remains on the table; no double-resolve, no double SendTrick.
- `S.s.swaRequest = nil` at line 2050 also prevents stale SWA paths from firing inside SCORE.

## 3) /reload during the 2.2s hold — SAFE
- C_Timer state does NOT survive /reload. WHEREDNGN.lua:198-209 (PLAYER_LOGIN restore) detects `phase==PLAY && #plays>=4` and schedules a 0.5s delayed `_HostStepPlay()` re-entry. This re-arms the full 2.2s hold and resolves correctly.
- Guarded against host-mismatch, paused, phase change, and `<4 plays` at fire time.

## 4) Bot pos-4 race — SAFE but tight
- Bot path: `Bot.PickPlay` → `LocalPlay` (line 1932) → `S.ApplyPlay` → `SendPlay` → `_HostStepPlay()` (line 1963). All synchronous.
- If the human pauses BEFORE the bot's `LocalPlay` completes, `LocalPlay` checks `S.s.paused` at line 1933 and aborts — the bot's play is dropped, not partial. `MaybeRunBot` re-dispatches on resume (line 2299).
- No torn write: `ApplyPlay` is the atomic step. Either the play is fully applied (and 2.2s timer arms), or it isn't.

## 5) 8th-trick / round-end branch — SAFE
- After 2.2s, `ApplyTrickEnd` + `_HostStepAfterTrick` runs. `_HostStepAfterTrick` checks `#S.s.tricks >= 8` (line 1585) and routes to round scoring. The 8th trick is fully resolved with normal animation timing.

## 6) Phase-change guard at line 1572 — VERIFIED CORRECT
- Order is right: `paused` (1569) → `phase==PLAY` (1572) → `contract` (1573) → `trick && plays>=4` (1574). Each guard prevents the resolve in its specific scenario.

## Findings: no bugs. Three latent risks worth noting:
- **Risk A (cosmetic)**: Resume re-arms a fresh 2.2s — players who paused mid-hold wait the full 2.2s again. Acceptable.
- **Risk B (latent)**: Multiple stacked timers — if `_HostStepPlay` is called twice while `#plays>=4` (e.g. resume races with another trigger), TWO closures fire 2.2s later. Both pass guards; second one finds `#plays<4` after `ApplyTrickEnd` clears `S.s.trick.plays` (State.lua:1217 reset to empty), so it bails at line 1574. Idempotent by accident, but a generation token would be cleaner.
- **Risk C**: No generation token covers the /reload re-fire path either; if PLAYER_LOGIN fires twice (unusual but possible during quick reconnects), two pending timers exist. Same idempotence-by-empty-plays saves it.

Recommendation: add `B._stepPlayGen` token (mirroring `B._redealGen` pattern at line 1656) to make idempotence explicit and audit-provable.
