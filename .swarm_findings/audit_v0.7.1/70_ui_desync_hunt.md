# Audit 70: UI desync hunt (UI.lua, v0.7.2 HEAD)

Verdict: 4 real desyncs, 1 cosmetic. Worst is the pause-blind banner
self-tick (#1) — pre-flagged in audit 39 but unfixed.

## 1. Pause-blind countdowns (CONFIRMED, REGRESSION-EXEMPT)

`UI.lua:1337-1364` (overcall) and `UI.lua:1445-1473` (SWA) OnUpdate
self-ticks decrement `remain` from wall-clock `GetTime()` every 0.33s.
Neither consults `S.s.paused`. Pause overlay (`UI.lua:1269-1280`) is
shown but the countdown digit keeps ticking under it. Bug since v0.7.0;
prior audit 39 §5 flagged it; not fixed in v0.7.2. Recommended one-line
fix: early-return on `S.s.paused` in both OnUpdate handlers (use
`startedAt`/`req.ts` snapshots so pause-resume preserves elapsed).

## 2. Belote announcement banner — ABSENT (BY DESIGN, NOT A BUG)

User question 8 asked when the K+Q banner fires. It doesn't exist.
`Rules.lua:621-690` only computes `result.belote` at scoring; UI shows
"Belote (K+Q ♥): TEAM +20 raw" only inside the round-end banner
(`UI.lua:3140-3142`). No mid-trick banner / sound on K+Q play. This
matches Saudi convention (Belote is silent until score) but worth
documenting if "show on play" was ever intended.

## 3. BALOOT fanfare on /reload — DOES NOT REFIRE (CORRECT)

`State.lua:237` flags `lastRoundResult` and `lastRoundDelta` as
TRANSIENT, dropped on save. Cue fires inside `S.ApplyRoundEnd`
(`State.lua:1393-1396`), driven by MSG_ROUND receipt — not by
PHASE_SCORE persistence. After /reload the phase persists but
`ApplyRoundEnd` does not re-run, so no double-fanfare. Confirmed safe.

## 4. Card-back vs card-face flip timing — CORRECT

`renderCenter` (`UI.lua:2554-2629`) uses `prevTrickPlayCount` so only
NEW plays animate via `animateLand`. `S.ApplyPlay` removes the played
card from `s.hand` (`State.lua:1199-1203`) BEFORE the next Refresh, so
the local hand always reflects post-play state. Bid card hides on
PHASE_PLAY entry (`UI.lua:2582-2595` — phase guard correctly excludes
PHASE_PLAY). Redeal restores cleanly: `ApplyStart` resets `bidCard=nil`
(`State.lua:44, 713`).

## 5. Trick-card clearing & last-trick peek — CORRECT-WITH-CAVEAT

`renderCenter` at `UI.lua:2555-2560` blanks every centerCard slot at
top, so prior trick clears between tricks. `centerOverride` (peek) gates
on PHASE_PLAY/DEAL3 only (`UI.lua:2646-2648`) — phase changes mid-peek
correctly leave the C_Timer to NIL out the override 3s later, but the
override won't refresh until the timer fires. Minor: a Refresh during
peek-window phase change won't re-hide cards immediately. Cosmetic.

## 6. Score display — CORRECT

`renderStatus:3293-3295` reads `S.s.cumulative` directly. Cumulative is
mutated only inside `S.ApplyRoundEnd` (`State.lua:1375-1376`), itself
driven by MSG_ROUND. No local recomputation. Spectators see same
host-broadcast totals.

## 7. Forbidden Bel button — clickable no-op (cosmetic, audit 39 §1)

`UI.lua:1761-1767` colors the label grey but doesn't `SetEnabled(false)`.
No state damage (handler is `function() end`); cosmetic-only.

## 8. Hand removal of remote MY-card — IMPOSSIBLE BY PROTOCOL

`S.ApplyPlay:1199-1203` only mutates `s.hand` when `seat==localSeat`.
A spoofed MSG_PLAY for `seat==localSeat` would be rejected by
`Net.lua:authorizeSeat:634-651` (sender-seat ownership check). Safe.

## Net new findings vs audit 39

- §2-§5 expand audit 39's narrow scope (which only checked banners)
  with score-path / hand-removal / fanfare verification.
- §1 reconfirms audit 39 §5 — bug still present in v0.7.2.
- §2 (Belote banner absence) and §7 (forbidden-Bel cosmetic) are new.
