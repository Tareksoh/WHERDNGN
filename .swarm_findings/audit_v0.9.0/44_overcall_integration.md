# Sun-overcall integration audit (v0.7.0+v0.8.0 at HEAD v0.9.0)

Files audited: `State.lua` (191-360, 915-1008, 1592-1729), `Net.lua`
(60-76, 405-430, 1115-1258, 1514-1605, 3503-3530), `Bot.lua` (3392-3453),
`WHEREDNGN.lua` (125-270), `Constants.lua` (293-343).

## 1. Sun-overcall + Bel-100 gate — CORRECT

`_HostResolveOvercall` (Net.lua 1250-1255) re-runs `_SunBelAllowed` after
contract mutation. UPGRADE→Sun and TAKE→Sun both go through this gate;
if neither team is past 100 (or bidder team isn't behind), `belPending`
is cleared and `HostFinishDeal()` is called immediately, skipping
PHASE_DOUBLE. TAKE_HOKM keeps type=Hokm so the gate correctly does not
fire (`R.CanBel` returns true for non-Sun). After TAKE/TAKE_HOKM the
`belPending` pair is re-derived from the new bidder seat in
`S.FinalizeOvercall` (State.lua 991, 1002). No defect.

## 2. Sun-overcall + Pre-emption — MUTUALLY EXCLUSIVE

`PHASE_PREEMPT` opens only on R2 + `payload.type==BID_SUN` +
`bidRank=="A"` (Net.lua 1528-1531). `_HostBeginOvercallWindow` opens
only on `contract.type==BID_HOKM` + non-forced (Net.lua 1153-1154).
The two branches are gated on contract type and execute in an
if/elseif within `_HostStepBid action=="contract"` — pre-emption first,
overcall second. Same round cannot trigger both. No sequencing defect.

## 3. Sun-overcall + Ashkal — MUTUALLY EXCLUSIVE

Ashkal converts a Hokm bid to a Sun-with-`viaAshkal=true` contract
during R1 within `S.HostAdvanceBidding` (State.lua 1637-1685). The
Ashkal-derived contract has `type==BID_SUN`, so when the bid sequence
exits with `action="contract"`, `_HostBeginOvercallWindow` rejects on
`type ~= BID_HOKM` (line 1153) and falls through. Direct Sun in R1 can
still overcall an Ashkal-Sun via the bid mechanism (State 1623-1627), but
that is the ordinary bid path, not PHASE_OVERCALL. R2 phasing identical.
No defect.

## 4. AFK timeout during PHASE_OVERCALL — VERIFIED

`MaybeRunBot` early-returns on `phase==PHASE_OVERCALL` (Net.lua 3529).
Bots decide synchronously at window-open (1166-1175). Humans have the
5s timer; on fire, `_HostResolveOvercall` runs against decisions table
where missing seats default to nil (treated as WAIVE in
`R.ResolveOvercall`). Pause-aware re-arm at lines 1191-1202 prevents
auto-WAIVE during host pause. Behavior matches spec: human times out
→ host synthesizes WAIVE via the nil-decision path.

## 5. Bot tier dispatch — APPROPRIATE STRENGTH

`Bot.PickOvercall` (Bot.lua 3398-3453) is M3lm-gated (lower tiers always
WAIVE). Thresholds: SELF=75 (UPGRADE), TAKE=80 (TAKE-as-Sun),
TAKE_HOKM=80 with shape gate (J + count>=3). Cross-trump comparison via
`suitStrengthAsTrump` correctly excludes the bidder's current trump
(line 3432). Threshold ordering and shape gate align with C2/C4 Sun-bid
research. No regression.

## 6. Save/Restore mid-window — FIXED (M2)

`s.overcall` is NOT in `TRANSIENT_FIELDS` (State.lua 191-248) — persists
across /reload. Host re-arm at WHEREDNGN.lua 256-269 resets
`overcall.startedAt` and arms a fresh `OVERCALL_TIMEOUT_SEC` timer that
calls `_HostResolveOvercall`. Local pre-warn re-arm at 243-247.
Verified: M2 fix ships.

## Residual concerns

**(LOW)** No headless test coverage for the integrated paths:
overcall→Sun-Bel-skip, overcall→TAKE_HOKM→new-defender Bel, /reload
mid-PHASE_OVERCALL re-arm. `tests/test_state_bot.lua` has 94
overcall hits but all on the state primitives. The wire+restore
integrations are exercised only manually.

**(LOW)** `_HostResolveOvercall` (1250-1254) calls
`_SunBelAllowed(S.s.contract.bidder)` — correct post-mutation. But
the parallel call site at `_HostStepBid` (1586-1592) uses
`payload.bidder` not the post-`ApplyContract` bidder. Both happen to
be identical in the non-overcall path; flagging as a future-proofing
concern only.

## Verdict

All six integration questions resolve cleanly. v0.9.0 M2 closes the
last identified soft-lock. No blockers for ship.
