# 48 — v0.8.0 cross-trump take × Bel-100 gate race

Verdict: **PASS with one MEDIUM concern** (remote MSG_DOUBLE pre-MSG_CONTRACT race window).

## Scenario walked

1. Bidder=S1 bids `HOKM:♠`. `_HostStepBid` calls `_HostBeginOvercallWindow` (Net.lua:1150) — opens 5s window, `s.phase=PHASE_OVERCALL`.
2. Bot/human at S2 sends `SELF_OVERCALL_SUN` (the bidder's own UPGRADE→Sun) OR a `TAKE` from a non-bidder.
3. `_HostResolveOvercall` (Net.lua:1227) calls `S.FinalizeOvercall` (State.lua:971) which mutates `s.contract.{type,trump,bidder}` AND recomputes `s.belPending = oppA and {2,4} or {1,3}` from the **new** bidder (State.lua:991, 1002).
4. Host re-broadcasts `MSG_OVERCALL_RESOLVE` then `MSG_CONTRACT` (Net.lua:1239, 1245).
5. Host re-checks `_SunBelAllowed(S.s.contract.bidder)` against the **new** bidder team (Net.lua:1250-1255). Cumulative scores haven't changed; only `bidderTeam` flipped. So a defender that was "behind" pre-overcall may now be the bidder team, or vice versa.

## Findings (in audit order)

1. **belPending recompute after cross-trump take: CORRECT.**
   `S.FinalizeOvercall` re-derives `belPending` for both `TAKE` (line 991) and `TAKE_HOKM` (line 1002) using `result.by`. The old defender pair is overwritten — no stale `belPending` from the original bidder.

2. **`_SunBelAllowed` post-overcall: CORRECT.**
   Reads `S.s.contract.bidder` after `FinalizeOvercall` mutated it. `bidderTeam = R.TeamOf(seat)` correctly resolves to the new bidder's team. Path verified: Net.lua:1250-1254 fires `belPending=nil` + `HostFinishDeal()` when gate fails, skipping PHASE_DOUBLE entirely. (Note: cross-trump-take→Hokm path skips this branch entirely since `contract.type==BID_HOKM` — Hokm has no Bel-100 gate. Correct per Saudi rules.)

3. **MSG_OVERCALL_RESOLVE → MSG_CONTRACT → MSG_DOUBLE ordering: MEDIUM RISK.**
   On remote client, `_OnOvercallResolve` (Net.lua:1116) clears `s.overcall` and sets `s.phase=PHASE_DOUBLE` **before** `MSG_CONTRACT` arrives. If a defender bot/human on a separate client now reacts to PHASE_DOUBLE on the **stale** contract (still `HOKM:♠`, original bidder) and sends `MSG_DOUBLE` before its `_OnContract` fires, the host's `_OnDouble` (Net.lua:853) gates on `R.CanBel(R.TeamOf(seat), S.s.contract, ...)` against the **new** contract — which on host is already mutated. This means: a pre-overcall defender's stale Bel intent gets validated against the post-overcall contract. The wire authorizeSeat check at Net.lua:861 (`eligibleSeat = (S.s.contract.bidder % 4) + 1`) protects against the wrong-seat case (rejects if the old defender is no longer NextSeat of the new bidder). But for `SELF_OVERCALL_SUN` (UPGRADE — bidder unchanged), the same defender remains eligible, and a Bel sent against pre-mutation contract will land. Bel-100 gate evaluates against the **new** Sun cumulative — generally desired but driver-dependent: the human clicked Bel believing Hokm (no gate), now lands as Sun (gate may reject silently — silently, if R.CanBel fails, host broadcasts MSG_SKIP_DBL and finishes deal). **No corruption, but UX cliff: human's Bel click silently disappears.** Documented mitigation precedent at Net.lua:880-887.

4. **/reload mid-overcall + Bel: CORRECT.**
   `s.overcall` is persisted (not in TRANSIENT_FIELDS). PLAYER_LOGIN handler at WHEREDNGN.lua:255-269 (M2 fix) re-arms a fresh 5s timer with `paused`-guard. Restored `s.contract` is the pre-overcall Hokm contract; `_HostResolveOvercall` will fire fresh and run the same gate path. `belPending` is regenerated on overcall finalize, not at restore — safe.

5. **Bot.PickDouble post-overcall: CORRECT.**
   Reads `S.s.contract` directly (Bot.lua:3096). Dispatch path: `_HostResolveOvercall` → `MaybeRunBot` (Net.lua:1256) → PHASE_DOUBLE branch (Net.lua:3532). Bot reads the live mutated contract.type/trump/bidder. `R.CanBel` gate at Bot.lua:3105 fires against the new (Sun, possibly post-100) state. No stale capture.

## Reproducer for #3

Two-client, host=S1 bidder, S3=remote defender. Host fires SELF_OVERCALL_SUN (UPGRADE). On a slow-network frame where MSG_OVERCALL_RESOLVE arrives at S3 before MSG_CONTRACT and S3's auto-AFK/human reacts to phase=PHASE_DOUBLE within ~1 frame, S3's MSG_DOUBLE wire reaches host evaluated against new contract.

## Suggested patch (optional)

In `_OnOvercallResolve` (Net.lua:1141), defer `s.phase = PHASE_DOUBLE` until `_OnContract` fires (or queue a "pending phase" gate). Alternatively widen `_OnDouble` reject window: drop any MSG_DOUBLE arriving within 250ms of last MSG_OVERCALL_RESOLVE on host side.

(Word count: ~445)
