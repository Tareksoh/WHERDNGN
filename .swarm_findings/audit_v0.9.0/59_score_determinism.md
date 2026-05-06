# 59 — Score Broadcast Determinism (v0.9.0)

## Verdict
**Determinism is preserved by the wire-format itself.** Host computes deltas + absolute totals locally, ships ALL FOUR (`addA, addB, totA, totB`) over `MSG_ROUND`, and clients commit `totA/totB` directly into `S.s.cumulative` with no local recomputation. Rounding direction (`(x+5)/10`) is therefore a host-only concern at all canonical sites.

## Trace

### 1. Host computation
- `R.ScoreRound` (Rules.lua:598, div10 at line 833) — normal contract path.
- `N._HostResolveTakweesh` (Net.lua:2238-2241) — Qaid penalty path; computes `addX` then `totX = S.s.cumulative.X + addX`.
- `N._HostResolveSWA` (Net.lua:2956-2957) — SWA fail path; same div10.
- `S.HostScoreRoundResult` (State.lua:1832) wraps these for the host's own banner.

All three host paths use the SAME formula `(x+5)/10` post-v0.5.21 alignment.

### 2. Wire payload (MSG_ROUND)
Net.lua:281-282:
```lua
broadcast(("%s;%d;%d;%d;%d;%s;%s"):format(
    K.MSG_ROUND, addA, addB, totA, totB, sweepStr, madeStr))
```
**Absolute totals are on the wire.** Clients never need to add a delta.

### 3. Client commit (no recomputation)
- `N._OnRound` (Net.lua:1496-1501) — gates on `fromHost`, calls `S.ApplyRoundEnd(addA, addB, totA, totB, sweep, bidderMade)`.
- `S.ApplyRoundEnd` (State.lua:1405-1407): `s.cumulative.A = totA; s.cumulative.B = totB`. Direct assignment. No `+=`.

### 4. Bot.OnRoundEnd
Bot.lua:273 — only takes `(contract, bidderMade)`. Never reads `s.cumulative`. Inputs come from `R.ScoreRound` result (host) or wire flags (clients). No determinism gap.

### 5. UI score panel
UI.lua:32 declares `scoreText`; reads `S.s.cumulative` (the post-`ApplyRoundEnd` authoritative value). No local div10 in UI.

## Edge cases

### MSG_ROUND drop / network loss
Clients do NOT reconstruct cumulative from MSG_TRICK history. `_OnTrick` only applies `points` to the current round's trick state via `S.ApplyTrickEnd(winner, points)`; cumulative advances only on `ApplyRoundEnd`. **A dropped MSG_ROUND leaves the client's `s.cumulative` stale.** Recovery is via `MSG_RESYNC_REQ/RES` (Net.lua:299, packed snapshot fields 16-17 carry `cumulative.A/B` directly — same wire-trust model).

### Cross-version (v0.5.x client vs v0.9.0 host)
Pre-v0.5.6 clients used `(x+4)/10`. **Not a desync risk under the current wire** — old `_OnRound` handlers ALSO consume `totA/totB` directly (the field positions are unchanged across all versions inspected; the format extended only by appending `sweepStr/madeStr`). Old clients ignore unknown trailing fields. Only the host's div10 matters.

### Qaid/SWA paths
Both call `S.ApplyRoundEnd` then `SendRound` — same broadcast → same client commit. Aligned post-v0.5.21.

## Risks (non-blocking)
- **No retry / no sequence number** on MSG_ROUND. A single dropped packet desyncs cumulative until the next resync. Consider attaching a round counter to MSG_ROUND so clients can detect skipped round-ends.
- `S.HostScoreRoundResult` runs AFTER `ApplyRoundResult` stash but the host also calls `S.ApplyRoundEnd` directly (loopback), so host and clients converge on the same `totA/totB` derived from the host's single computation.

## Conclusion
No active determinism gap from rounding. The single live concern is MSG_ROUND drop tolerance.
