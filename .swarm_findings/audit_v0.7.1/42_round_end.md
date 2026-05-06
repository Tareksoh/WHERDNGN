# 42 — Round-end transition (PHASE_PLAY → SCORE → BID)

Targets: `N._HostStepAfterTrick` (Net.lua:1584), `S.HostScoreRoundResult`
(State.lua:1741), `S.ApplyRoundResult` (State.lua:1411), `S.ApplyRoundEnd`
(State.lua:1359), `MSG_ROUND` flow (Net.lua:264/540/1438), `Bot.OnRoundEnd`
(Bot.lua:252).

## 1. Gahwa match-win override — HOST-ONLY, NOT ON WIRE

`R.ScoreRound` (Rules.lua:836-846) flags `gahwaWonGame`/`gahwaWinner` on
the result struct. `_HostStepAfterTrick` (Net.lua:1593-1600) inflates
`addA`/`addB` to `target - cumulative` BEFORE calling `S.ApplyRoundEnd`
and `N.SendRound`. Therefore the inflated deltas land on the wire as
normal `MSG_ROUND` totals; non-host clients see correct cumulative
totals but never see the `gahwaWonGame` flag itself. **Issue:** non-hosts
can't distinguish a match-win Gahwa from a regular round that happened
to push past target. UI surfaces (`UI.lua:2998` / `:3294`) only consult
`s.cumulative` so the game-end banner still fires correctly, but
`s.lastRoundResult` (set in `S.ApplyRoundResult`, Net.lua:1588) is
**host-only** — non-host summary panels show no Gahwa annotation.

## 2. Style-ledger order — CORRECT BUT FRAGILE

`S.ApplyRoundEnd` (State.lua:1402) calls `B.Bot.OnRoundEnd(s.contract, ...)`
**before** `s.contract` is cleared (the comment at 1399 explicitly notes
this). Order: cumulative updated → phase=SCORE → fanfare → `OnRoundEnd`.
`OnEscalation` increments fire earlier (during DOUBLE/TRIPLE/FOUR/GAHWA
phases via `_OnDouble`/`_OnTriple`/etc.), so `triples`/`fours`/`gahwas`
are already counted before round-end; only `gahwaFailed`/`sunFail` post-
round increments. Order is correct. **Fragility:** if any future code
clears `s.contract` before line 1403 (e.g., during `ApplyStart` of next
round arriving racy on non-host), `OnRoundEnd` early-returns at line 254.

## 3. Broadcast vs bot ledger — NO STALE-READ on host

The host runs `ApplyRoundEnd` synchronously (Net.lua:1603) BEFORE
`SendRound` (line 1604). `Bot.OnRoundEnd` updates the ledger before
`HostStartRound` is ever invoked for the next round (which is user-
initiated via UI/Slash). No race — bot bid decisions next round read
the freshly-incremented `gahwaFailed`/`sunFail`.

## 4. Dealer rotation — NOT BROADCAST AT ROUND-END

At round-end, `_HostStepAfterTrick` does NOT advance `s.dealer`. Dealer
advances inside `N.HostStartRound` (Net.lua:1701: `(S.s.dealer % 4) + 1`)
and is then synced via `N.SendStart` (line 1715) → `MSG_START` →
`S.ApplyStart(round, dealer)` (State.lua:712) on receivers. The wire
field `dealer` in MSG_START is the canonical sync — non-hosts never
compute it locally. Correct.

## 5. /reload mid-transition — SAFE

`SaveSession` (State.lua:252) skips persistence in `PHASE_GAME_END` and
`PHASE_IDLE`/`LOBBY`, but **persists `PHASE_SCORE`**. A /reload between
`ApplyRoundEnd` (phase=SCORE) and the next `HostStartRound` restores
correctly: `s.cumulative`, `s.lastRoundDelta`, and `s.dealer` survive;
the user re-presses "Next Round" and rotation works off restored
`s.dealer`. The 1-hour TTL guard (line 274) is fine for normal play.

## 6. Game-end session clear — CORRECT

`ApplyGameEnd` sets `phase=PHASE_GAME_END` (State.lua:1425). The next
`SaveSession` call (PLAYER_LOGOUT/reload) hits the GAME_END branch at
State.lua:253-255 and writes `WHEREDNGNDB.session = nil`. **Caveat:**
clear only happens on next save/reset, not immediately. If the user
inspects `WHEREDNGNDB.session` between `ApplyGameEnd` and a /reload
they'll see stale data.

## Recommendations

- Broadcast `gahwaWonGame`/`gahwaWinner` as extension fields on
  `MSG_ROUND` so non-host summary panels can render the match-win
  annotation.
- Add comment-pin near State.lua:1402 that `s.contract` clearing
  must remain post-`OnRoundEnd`.
