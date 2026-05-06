# 36 — Score-broadcasting wire flow audit (Net.lua, v0.7.2)

Targets: `N.SendRound`/`_OnRound` (264/1438), `N.SendSWAOut`/`_OnSWAOut`
(212/2707), `N.SendTrick`/`_OnTrick` (243/1409), `N.SendContract`/
`_OnContract` (155/825). Also: `HostResolveSWA` (2740), `HostStepAfterTrick`
(1584).

## 1. `_OnRound` idempotence on replay  — SAFE BY DESIGN
Wire format carries **absolute totals** `(addA, addB, totA, totB)`, not just
deltas. `S.ApplyRoundEnd` (State.lua:1359) does `s.cumulative.A = totA;
s.cumulative.B = totB` — overwrite, not increment. A duplicate `MSG_ROUND`
re-sets cumulative to the same value; no double-count.
SIDE EFFECT RISK on replay: `S.ApplyRoundEnd` re-fires `K.SND_BALOOT`,
`K.SND_LOST_ROUND`, and `B.Bot.OnRoundEnd` (1378-1404). No idempotence
guard like `S.ApplyGameEnd`'s phase+winner short-circuit (1422). A
resync-replay during `PHASE_SCORE` will re-stinger and double-bump the bot
ledger. Minor, but worth a `s.phase == K.PHASE_SCORE && s.lastRoundDelta`
guard.

## 2. Trick-points host vs client — CONSISTENT
Host computes via `R.TrickPoints` (Rules.lua:67) at Net.lua:1576, broadcasts
the integer in `MSG_TRICK`. Clients consume the wire `points` directly via
`S.ApplyTrickEnd(winner, points)` at 1434 — no client-side recomputation,
so no divergence possible. The encPlays snapshot (1417-1432) only rebuilds
`s.trick.plays` for the lastTrick peek view; it does NOT recompute points.

## 3. `(x+5)/10` rounding — UNIFORM
Every active div10 site uses `math.floor((x + 5) / 10)`:
- `Rules.lua:828` (`R.ScoreRound`)
- `Net.lua:2151-2152` (`HostResolveTakweesh`)
- `Net.lua:2855-2856` (`HostResolveSWA` invalid path)
Valid-SWA path goes through `R.ScoreRound` (2908), inheriting div10. No
`(x+4)/10` remains in active code (only historical comments at
Rules.lua:827, Net.lua:2147).

## 4. Belote +20 wire format — POST-MULTIPLIER, BAKED IN
`SendRound` ships `addA/addB` as the FINAL post-rounded delta. The +20 is
applied in `R.ScoreRound` AFTER multiplier (`raw = teamPts*mult + meld*mult`,
then `+ K.MELD_BELOTE`, then `div10`) at Rules.lua:819-821. Same in
`HostResolveTakweesh` (2142-2143) and `HostResolveSWA` invalid path
(2851-2852). Multiplier-immunity preserved on the wire by construction —
the wire never carries belote separately, so clients can't desync.

## 5. Gahwa match-win override — HOST-ONLY
The cumulative-jump-to-target logic lives in `HostStepAfterTrick`
(1593-1600), AFTER `S.HostScoreRoundResult` returns. The inflated `addA/addB`
are then broadcast via `SendRound` — clients receive the already-overridden
totals and apply them via `S.ApplyRoundEnd`. **One-sided computation, but
clients see consistent totals.** The override does NOT fire in
`HostResolveSWA` (2796-2913) or `HostResolveTakweesh` paths — if a Gahwa
contract terminates via SWA or Takweesh, the match-win semantic is dropped.
Likely intentional (per Rules.lua:838 comment "fully-played-out round"),
but worth confirming against Saudi rules.

## 6. SWA sync invariants — HOLDS
Host: `HostResolveSWA` computes addA/addB, calls `S.ApplyRoundEnd` locally
(2928), then `SendSWAOut` (2929). Clients: `_OnSWAOut` (2707) calls
`S.ApplyRoundEnd(addA, addB, totA, totB, sweep, bidderMade)` at 2723. Same
absolute-total semantics as MSG_ROUND, so cumulative is synced. The
9th-audit fix (2756) trusts host's `hostHands` over wire — security
correct. Replay risk: same fanfare-double-fire as section 1.
