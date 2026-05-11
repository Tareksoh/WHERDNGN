# v3.2.0 Cleanup Batch 4 — Skip/Preempt Retry + Adjacent Raw Paths (Design / Inventory Pass)

**Status**: design only, no code changes. Output for Codex review
before implementation.

**Branch baseline**: `main` at `eb66339` (post-Batch 3). Working tree
clean. Tests at 1084/1084 pass.

**Goal**: inventory all remaining one-shot/raw wire broadcasts around
skip, preempt, and adjacent SWA/Takweesh outcome paths, then
recommend the smallest safe implementation slice. Per the audit
plan, this is the "skip/preempt retry coverage decision."

## Inventory summary

**Total raw / one-shot send sites discovered**: 18 across 4 areas
(senders themselves, not their interior call sites — `LocalPreempt`,
`MaybeRunBot` bot paths, etc. that already route through helpers
are NOT counted as separate raw sites).

- **Area A** (skip helpers): 4 helpers, all currently one-shot by
  intentional design from Batch 1.
- **Area B** (preempt): 4 sites — `N.SendPreempt` helper (one-shot)
  + `N.SendPreemptPass` helper (one-shot) + 1 RAW AFK broadcast
  bypassing `SendPreemptPass` + 1 special "window open" raw frame
  with multi-payload shape.
- **Area C** (SWA): 3 sites — `N.SendSWA` helper (one-shot) + 1
  raw `MSG_SWA_REQ` broadcast inside `MaybeRunBot` that bypasses
  the retrying `SendSWAReq` helper + 1 raw `MSG_SWA` fallback when
  `C_Timer` is unavailable (also inside `MaybeRunBot`).
- **Area D** (outcome/review): 7 senders/sites that are outcome or
  review broadcasts — `SendSWAOut`, `SendTrick`, `SendRound`,
  `SendGameEnd`, MSG_DEAL redeal, `MSG_TAKWEESH_REVIEW`,
  `MSG_TAKWEESH_OUT`. Generally **defer** — receiver-side
  authority makes outcome retry semantically risky.

## Required inventory table

### Area A — Skip helpers (4 sites)

| Message / helper | Call sites | State mutation order | Receiver idempotence | Existing guard / candidate retry guard | Dropped-frame impact | Stale-retry risk | Recommendation | Recommended tests | Risk |
|---|---|---|---|---|---|---|---|---|---|
| `N.SendSkipDouble` (`Net.lua:443`) | 6 sites: `_OnDouble` Race-A recovery (1588), `LocalSkip` Double branch (3076), `_HostBelTimeout` double (5408), `MaybeRunBot` bot Bel-decision botSkips loop (5688), `_OnDouble` reject + LocalSkip — send-then-mutate | `LocalSkip`: send → mutate `belPending` locally → `HostFinishDeal()` or `MaybeRunBot()`. `_HostBelTimeout`: send → mutate `belPending` → finish/redispatch. Bot path: send-then-mutate | `_OnSkipDouble` (Net.lua:2176-2206) phase-gates on `PHASE_DOUBLE`, idempotent on `pendingContains(belPending, seat) == false` (already-removed defender) | Pre-apply phase guard `PHASE_DOUBLE` + post-apply `not pendingContains(belPending, seat)` for receiver-side idempotence proof | AFK 60s fallback exists (`_HostBelTimeout` re-fires the skip), but the user-perceived stall is the gap. Single-frame drop = up to 60s pause for that defender | **MEDIUM** — phase advances to PLAY when `belPending` empties. If both defenders skip near-simultaneously, retry firing post-phase-advance is harmless (receiver phase-guard rejects). But if mid-window phase already moved to TRIPLE, retry could collide | **Add retry** with post-apply guard: `S.s.phase == PHASE_DOUBLE and not pendingContains(belPending, seat)`. The "not in pending" predicate confirms our skip has been recorded locally; retry only fires if state hasn't advanced past PHASE_DOUBLE | AZ.33a: initial broadcast; AZ.33b: retry fires when still in PHASE_DOUBLE with seat not in belPending; AZ.33c: retry suppressed when phase moves to TRIPLE/PLAY | LOW-MED |
| `N.SendSkipTriple` (`Net.lua:447`) | 4 sites: `LocalSkip` Triple branch (3095), `_HostBelTimeout` triple (5423), `MaybeRunBot` bot Triple skip (5738) + recovery (5757) | All: send-then-`HostFinishDeal()` (advances to PLAY immediately). No defender state to mutate — single-bidder decision | `_OnSkipTriple` (Net.lua:2208-2216) phase-gates on `PHASE_TRIPLE`; calls `HostFinishDeal` (idempotent via `if S.s.isHost` + phase progression) | Pre-apply phase guard `PHASE_TRIPLE` is the only meaningful gate. By 0.25s post-send the phase is already PLAY | **HIGH** — phase always advances to PLAY before the 0.25s retry can fire. Retry guard `phase == TRIPLE` would always fail. Same dead-code shape as v3.1.13 pre-Codex-fix escalation retries | The pre-apply-guard dead-code risk is exactly what Codex caught in v3.1.13. There's no post-apply identity (no per-rung flag tracks "we skipped Triple"). The host's `HostFinishDeal` is the only side-effect. **HIGH stale-retry risk if mis-guarded** | **Defer.** No clean post-apply guard exists. The pre-apply phase guard fails immediately. Adding retry here without a state token would either always-fire (no guard) or never-fire (current pattern). The AFK 60s timer is the only fallback. Recommend addressing in a future batch with a new "skip-recorded" state field, OR leave as-is (the round still progresses via AFK) | None for this batch | HIGH if forced |
| `N.SendSkipFour` (`Net.lua:451`) | 4 sites: `LocalSkip` Four branch (3100), `_HostBelTimeout` four (5427), `MaybeRunBot` bot Four skip (5792) + recovery (5811) | Same as Triple: send-then-`HostFinishDeal()` (advances to PLAY) | `_OnSkipFour` (2218-2228) phase-gates on `PHASE_FOUR`, identity on `doublerSeat == seat` | Pre-apply guard `PHASE_FOUR` — same dead-code shape as Triple | **HIGH** — same as Triple | **Defer.** Same reasoning as Triple | None | HIGH if forced |
| `N.SendSkipGahwa` (`Net.lua:455`) | 4 sites: `LocalSkip` Gahwa branch (3105), `_HostBelTimeout` gahwa (5431), `MaybeRunBot` bot Gahwa skip (5844) + recovery (5857) | Same shape: send-then-`HostFinishDeal()` | `_OnSkipGahwa` (2230-2238) phase-gates on `PHASE_GAHWA`, identity on `seat == contract.bidder` | Pre-apply guard `PHASE_GAHWA` — dead-code shape | **HIGH** — same | **Defer.** Same reasoning | None | HIGH if forced |

**Area A summary**: only **SendSkipDouble** has a meaningfully-
checkable post-apply guard (the multi-defender `belPending` array
that gradually shrinks). The single-decision skip rungs (Triple,
Four, Gahwa) all advance phase immediately and have no
intermediate identity to test, so retry would be pre-apply
dead-code (same shape as Codex caught in v3.1.13).

### Area B — Preempt senders (4 sites)

| Message / helper | Call sites | State mutation order | Receiver idempotence | Existing guard / candidate retry guard | Dropped-frame impact | Stale-retry risk | Recommendation | Recommended tests | Risk |
|---|---|---|---|---|---|---|---|---|---|
| `N.SendPreempt` (`Net.lua:541`) | 2 sites: `N.LocalPreempt` (3023), `MaybeRunBot` bot preempt-claim path (5899) | **Two orderings exist**: (a) `LocalPreempt` calls `S.ApplyPreempt(localSeat)` BEFORE `N.SendPreempt(localSeat)` — but on NON-HOST clients the local state lands in `PHASE_DEAL2BID` with `contract == nil` (no host echo yet). (b) `MaybeRunBot` bot path sends BEFORE host applies; the retry timer fires after the callback that does `S.ApplyContract` runs. So **the retry guard must handle both pre-contract-echo and post-contract-echo states** | `_OnPreempt` (Net.lua:1687-1717) phase-gates on `PHASE_PREEMPT` + `seat ∈ preemptEligible`. After `ApplyPreempt(seat)`, the seat is removed from `preemptEligible` | **Two-branch post-send guard required** (per Codex review): `(phase == PHASE_DEAL2BID and contract == nil) or (contract and contract.bidder == seat and contract.type == K.BID_SUN)`. First branch covers non-host claimant waiting for echo; second branch covers host/bot after `ApplyContract` | Drop = the claim never reaches the host/other clients. Host doesn't transition to claimant's contract. Other clients see the preempt window expire on 5s timer. **Real desync risk**: claimant locally thinks they got SUN; other clients think the original buyer kept the bid | **MEDIUM** — by 0.25s post-send, host MAY have already `ApplyContract`'d. The retry's guard handles both states. Single-branch contract-only guard would dead-code the non-host-claimant case (Codex caught this) | **Add retry** with the two-branch guard | AZ.34a/b/c/d: initial + retry-fires-non-host-pre-echo + retry-fires-post-contract + retry-suppress-when-neither-branch-holds | MEDIUM |
| `N.SendPreemptPass` (`Net.lua:545`) | 3 sites: `N.LocalPreemptPass` (3046), `MaybeRunBot` bot pass + recovery (5922, 5980) | Send-then-`ApplyPreemptPass`-then-finalize-or-redispatch. Order: pre-apply on `LocalPreemptPass`, post-apply on host bot path | `_OnPreemptPass` (1719-1759) phase-gates on `PHASE_PREEMPT` + `seat ∈ preemptEligible`. Handles seat=0 special "window open" case separately | Post-apply: `S.s.phase == PHASE_PREEMPT and seat NOT in S.s.preemptEligible` (we waived, our seat is now removed). Pre-apply guard `PHASE_PREEMPT` alone would dead-code if `_FinalizePreempt` clears `preemptEligible` and advances phase | Drop = host doesn't see this seat waive. Window stays open until 60s AFK or until another seat decides. Lower impact than missed preempt claim (no contract change) | **LOW-MEDIUM** — if all eligible seats waive concurrently, by 0.25s the window may already be finalized. Retry guard with "seat not in preemptEligible AND still in PHASE_PREEMPT" handles this | **Add retry** with post-apply guard. Similar shape to SendPreempt | AZ.35a/b/c | LOW-MED |
| **RAW** `broadcast(MSG_PREEMPT_PASS, seat)` in `_HostBelTimeout` (Net.lua:5438, AFK path) | 1 site — host's AFK auto-pass for an eligible preempt seat | Send-then-`ApplyPreemptPass(seat)`-then-finalize-or-redispatch. AFK timer fires here. Bypasses `N.SendPreemptPass` helper | Same receiver (`_OnPreemptPass`) | This is the missing-helper-routing case Codex flagged. Today it's raw broadcast. **Migrate to `N.SendPreemptPass(seat)`** so retry (if added) covers AFK path too | Drop = same as `SendPreemptPass` drop. Currently affects AFK chain advancement | LOW (raw → helper migration is mechanical) | **Migrate to helper** (and retry inherits) | Existing `_HostBelTimeout` behavior remains identical; AZ.35 covers AFK timeout if helper migrated | LOW |
| **RAW** `broadcast(MSG_PREEMPT_PASS, 0, eligCsv)` "window open" frame (Net.lua:2545) | 1 site — host's `_HostBeginPreemptWindow` (or similar) on phase entry | Pre-apply (host transitions itself to PHASE_PREEMPT first, then sends) | `_OnPreemptPass` (1719-1745) has a special-case branch for `seat == 0` that seeds `preemptEligible` from the CSV payload | **Do not migrate to `SendPreemptPass`** — the helper signature is `(seat)` and this payload is `(0, eligCsv)`. Different wire format | Drop = remote clients never see the preempt window open. Their phase stays at PHASE_DOUBLE (or wherever). High-impact desync | **MEDIUM-HIGH** if retried — opening the window twice could re-seed `preemptEligible` after seats have already waived, re-arming the entire window | **Defer.** Adding retry here needs a new helper `SendPreemptWindowOpen(eligCsv)` with guard `phase == PHASE_PREEMPT and preemptEligible == eligCsv-decoded`. Justifiable but increases scope. Recommend leaving raw for Batch 4; revisit in a separate decision if user reports preempt-window-stuck | None for this batch | LOW (if deferred) |

**Area B summary**: **SendPreempt** and **SendPreemptPass** are the
clean retry candidates with reasonable post-apply guards. The
AFK raw broadcast at line 5438 should route through
`SendPreemptPass` so it benefits from any retry added. The special
`(seat=0, eligCsv)` window-open frame is a different shape and is
deferred.

### Area C — Adjacent raw SWA paths (3 sites)

| Message / helper | Call sites | State mutation order | Receiver idempotence | Existing guard / candidate retry guard | Dropped-frame impact | Stale-retry risk | Recommendation | Recommended tests | Risk |
|---|---|---|---|---|---|---|---|---|---|
| `N.SendSWA` (`Net.lua:602`, helper) | 1 site: `N.LocalSWA` direct-claim fallthrough when `swaRequiresPermission == false` (4215). Helper-routed | Send-then-`HostResolveSWA` (host directly resolves without permission window) | `_OnSWA` handler resolves SWA on host. `HostResolveSWA` is idempotent only if called with consistent hand state | None defined. Pre-apply phase `PHASE_PLAY`; post-apply round may have already resolved | **MEDIUM-HIGH** — `HostResolveSWA` mutates round state. Calling twice could double-apply scores. Receiver-side idempotence not well-characterized | Direct-claim is the rare fallback path (only when `swaRequiresPermission = false`). Real-world dominated by `SendSWAReq` (already retrying). Drop low, stale-retry high | **Defer.** Without a clear post-resolve idempotence story, retry could double-apply scoring | None | HIGH if forced |
| **RAW** `broadcast(MSG_SWA_REQ, seat, enc)` inside `MaybeRunBot` (Net.lua:6147) — bypasses `SendSWAReq` helper | 1 site — bot-initiated SWA request, post-`swaRequest` mutation | Send is followed by setting `S.s.swaRequest` locally on host | Same `_OnSWAReq` receiver as the helper path | The retrying `N.SendSWAReq` helper exists (`Net.lua:628`) with phase + caller guard. Migrating to helper auto-inherits retry | Drop = bot's SWA never reaches non-host clients. Host's local `swaRequest` is set so host UI updates, but remote opponents don't see the banner or get to vote | **LOW** (helper exists with proven guard from v3.1.12/v3.1.14) | **Migrate to `N.SendSWAReq(seat, enc)`** — pure helper-routing, no new retry added | AZ.36: bot-initiated SWA path produces 2 broadcasts via helper | LOW |
| **RAW** `broadcast(MSG_SWA, seat, enc)` `C_Timer`-unavailable fallback inside `MaybeRunBot` (Net.lua:6203) | 1 site — degraded "instant claim" path when `C_Timer.After` not present (test harness, ancient client) | Send-then-`HostResolveSWA(seat, hand)` | Same `_OnSWA` receiver as the helper path. Receiver-side double-apply risk identical to `SendSWA` helper above | None | This is a degraded test-harness fallback; in production WoW `C_Timer` is always present so the path is effectively dead-code | **N/A in production** | **Defer.** Path is effectively dead in production. Could optionally route through `N.SendSWA` for code-shape consistency but adds no reliability | None | N/A |

**Area C summary**: one clean migration target (raw MSG_SWA_REQ →
`N.SendSWAReq` helper). The direct-claim `SendSWA` path and the
fallback `MSG_SWA` are both deferred — direct-claim due to
double-apply risk on retry, fallback because it's effectively
dead-code in production.

### Area D — Outcome / review broadcasts (7 sites)

| Message / helper | Call sites | State mutation order | Receiver idempotence | Existing guard / candidate retry guard | Dropped-frame impact | Stale-retry risk | Recommendation | Recommended tests | Risk |
|---|---|---|---|---|---|---|---|---|---|
| `N.SendSWAOut` (`Net.lua:606`) | Outcome of SWA resolution | Round-end mutation already happened on host. This is a result broadcast to remotes | `_OnSWAOut` applies round-end state. Re-applying same outcome should be idempotent via round-number / phase checks — but not currently verified | None defined | Drop = remote clients miss the SWA outcome. Round-end summary may be wrong. **Real impact** — score totals on remote UI off until next round | **MEDIUM** — outcome broadcasts shouldn't fire twice. Receiver-side idempotence needs explicit verification before retry | **Defer.** Re-applying ApplyRoundEnd may double-apply scores if not idempotent. Verify receiver first, then revisit | None | DEFER |
| `N.SendTrick` (`Net.lua:741`) | End-of-trick broadcast | Post-apply on host: `ApplyTrickEnd` ran locally before send | Receiver-side `_OnTrick` applies trick end. Pre-trick guard via `s.tricks` length | None | Drop = remote misses trick winner + score. **High impact** | **MEDIUM** — `ApplyTrickEnd` mutates `tricks` array, `cumulative`, last-trick. Double-apply risk if not guarded | **Defer.** Tricks already have a workaround (host re-broadcasts via resync flow if drift detected). Verify receiver idempotence first | None | DEFER |
| `N.SendRound` (`Net.lua:762`) | End-of-round broadcast | Post-apply | `ApplyRoundEnd` writes `cumulative.A`, `cumulative.B`, etc. — should be idempotent via round-number, but verify | None | Drop = remote misses round-end score totals | **MEDIUM** | **Defer.** Same as SendSWAOut | None | DEFER |
| `broadcast(MSG_GAMEEND, winner)` (`Net.lua:784` inside `N.SendGameEnd`) | Game-end notification | Post-apply on host | Receiver applies game-end state. Idempotent via single bool flag | None | Drop = remote doesn't see "GAME OVER" banner. Round won't restart correctly | **LOW** — receiver idempotent on `phase == GAME_END` | **Defer.** Low impact since recovery is via /reload or new game start | None | DEFER |
| `broadcast(MSG_DEAL, "redeal", nextDealer)` (`Net.lua:2751`) | All-pass redeal announcement | Pre-apply: `S.ApplyRedealAnnouncement(nextDealer)` happens BEFORE broadcast | Receiver `_OnDealPhase` with "redeal" payload triggers `S.ApplyRedealAnnouncement` and a UI banner | None | Drop = remote misses redeal banner. The actual redeal still happens on the host's clock; the banner is cosmetic | **LOW** — banner-only impact | **Defer.** Cosmetic + UI banner; not gameplay-affecting | None | DEFER |
| `broadcast(MSG_TAKWEESH_REVIEW, ...)` (`Net.lua:3301`) | Takweesh review window opens | Host transitions to `PHASE_TAKWEESH_REVIEW` first, then broadcasts | `_OnTakweeshReview` advances remote phase + displays banner | None | Drop = remote stuck in PHASE_PLAY while host is in REVIEW. **Real desync** | **MEDIUM-HIGH** — retry guard would need `phase == PHASE_TAKWEESH_REVIEW and takweeshReview.callerSeat == X`. Achievable but new state field | **Defer.** Same shape as the `(seat=0, eligCsv)` preempt window-open frame — multi-payload, defer to a separate decision | None | DEFER |
| `broadcast(MSG_TAKWEESH_OUT, ...)` (`Net.lua:3697`) | Takweesh resolution outcome | Post-apply | Receiver applies round-end (if caught) or no-op (if false call) | None | Drop = same as SendSWAOut — remote miscounts | **MEDIUM** | **Defer.** Same reasoning | None | DEFER |

**Area D summary**: **all 5 outcome/review sites deferred**.
Receiver-side idempotence isn't well-characterized; double-apply
risk is non-trivial. The takweesh-review window-open frame has
a multi-payload shape like the preempt window-open frame and
needs its own helper design.

## Ranked recommendations for Batch 4 implementation

### Batch 4A — RECOMMENDED (lowest-risk, highest-value)

1. **Migrate AFK raw `MSG_PREEMPT_PASS` to `N.SendPreemptPass(seat)`** (Net.lua:5438).
   - Mechanical helper-routing, no new retry semantics added.
   - Inherits any future retry added to `SendPreemptPass`.
   - Risk: **LOW**. AZ test: AFK timeout path produces single broadcast through helper.

2. **Migrate bot-initiated raw `MSG_SWA_REQ` to `N.SendSWAReq(seat, enc)`** (Net.lua:6147).
   - Mechanical helper-routing.
   - Inherits the existing v3.1.12 retry (helper already retries).
   - Risk: **LOW**. AZ test: bot SWA path emits 2 broadcasts (initial + retry).

3. **Add retry to `N.SendSkipDouble`** with post-apply guard:
   `S.s.phase == PHASE_DOUBLE and not pendingContains(belPending, seat)`.
   - Multi-defender state allows a meaningful post-apply identity.
   - Risk: **LOW-MED**. AZ test: initial + retry-fires + retry-suppress-on-phase-advance.

4. **Add retry to `N.SendPreempt` and `N.SendPreemptPass`** with
   post-apply guards.
   - `SendPreempt`: guard on `S.s.contract.bidder == seat and S.s.contract.type == K.BID_SUN`.
   - `SendPreemptPass`: guard on `S.s.phase == PHASE_PREEMPT and seat NOT in preemptEligible`.
   - Risk: **MEDIUM**. AZ tests: 6-8 new pins for initial + retry + suppress across both helpers.

**Estimated Batch 4A scope**:
- ~4-6 code changes in `Net.lua` (2 raw→helper migrations + 3 helper retry additions).
- ~10-15 new behavioral tests (AZ.33-36 series).
- Test count: 1084 → ~1095-1099.

### Items deferred to a future batch

1. **`SendSkipTriple` / `SendSkipFour` / `SendSkipGahwa`** — no
   clean post-apply guard exists (phase advances immediately,
   no per-rung "we skipped" state). Adding retry here without a
   new state field would be the same pre-apply dead-code shape
   Codex caught in v3.1.13. Either invest in a new "skip-recorded"
   state field, OR leave as-is (AFK 60s timer already handles it).
   **Recommend leaving as-is** unless user reports surface.

2. **`SendSWA` direct-claim path** — receiver-side idempotence
   for `HostResolveSWA` not characterized. Double-apply risk
   for round-end scoring. Defer until receiver-side verified.

3. **`MSG_PREEMPT_PASS` "window open" frame `(seat=0, eligCsv)`**
   — needs its own helper (`SendPreemptWindowOpen(eligCsv)`) with
   a state-identity guard. Defer to a separate decision.

4. **All Area D outcome/review broadcasts** (SendSWAOut, SendTrick,
   SendRound, SendGameEnd, MSG_DEAL redeal, MSG_TAKWEESH_REVIEW,
   MSG_TAKWEESH_OUT) — receiver-side idempotence verification
   required before retry can be safely added. Likely a separate
   audit batch focused on "outcome message reliability."

### Items requiring Codex decision before implementation

1. **Pick 3 (SendSkipDouble retry)**: am I correct that
   `not pendingContains(belPending, seat)` is the right post-apply
   identity? Alternative: gate on phase only (`PHASE_DOUBLE`) and
   accept that retry won't fire if both defenders skip
   concurrently → no harm, just no retry coverage in that subcase.
   **Question**: which guard does Codex prefer?

2. **Pick 4a (SendPreempt retry)**: the post-apply guard
   `S.s.contract.bidder == seat and type == K.BID_SUN` could have
   a false-positive if a different seat ALSO took Sun via
   overcall in the same window. Probability is low (preempt is
   bidding-phase only, overcall is post-bidding) but worth
   confirming. **Question**: is the bidding-phase isolation
   guarantee strong enough to use this guard?

3. **Batch split A/B**: should Batch 4A be just the 2 raw→helper
   migrations (Picks 1-2, very low risk), with the 3 retry
   additions (Picks 3-4) deferred to Batch 4B? Splitting reduces
   review surface per batch. **Question**: prefer split or
   combined?

## Testing plan

For Batch 4A (combined), the AZ section adds:

- **AZ.33** — SendSkipDouble retry:
  - 33a: initial broadcast emitted
  - 33b: retry fires when still in PHASE_DOUBLE AND seat is no longer in belPending (we already removed ourselves locally)
  - 33c: retry suppresses when phase advances to PHASE_TRIPLE/PLAY
  - 33d: retry suppresses when seat re-appears in belPending (corruption case)

- **AZ.34** — SendPreempt retry:
  - 34a: initial broadcast
  - 34b: retry fires when contract.bidder still matches and type is SUN
  - 34c: retry suppresses when contract has been replaced (overcall flipped it)

- **AZ.35** — SendPreemptPass retry:
  - 35a: initial broadcast
  - 35b: retry fires when still in PHASE_PREEMPT and seat not in preemptEligible
  - 35c: retry suppresses when phase advanced past PREEMPT
  - 35d: AFK-timeout path emits exactly 2 broadcasts through helper migration

- **AZ.36** — bot SWA helper migration:
  - 36a: bot SWA from MaybeRunBot path emits 2 broadcasts (initial + retry)
  - 36b: retry uses the existing SendSWAReq guard (phase + swaRequest.caller)

All tests follow the AZ section's existing scaffolding:
- Load Net.lua via the AZ block's loader
- Capture broadcasts via stubbed `C_ChatInfo.SendAddonMessage`
- Capture and manually fire `C_Timer.After` callbacks
- Restore stubs at end

## Out of scope

- UI changes
- Bot logic changes
- Rule engine changes
- Source-pin retirement (handled in Batch 3)
- Test scaffolding refactor

## Summary numbers

- **Inventoried**: 18 raw/one-shot send sites across 4 areas (4 + 4 + 3 + 7)
- **Recommended Batch 4A**: 5 picks (2 migrations + 3 helper retry additions: SendSkipDouble, SendPreempt, SendPreemptPass)
- **Deferred**: 13 sites (3 skip-rung retries + 7 outcome/review + 1 preempt window-open + 2 deferred SWA paths)
- **Codex review status**: design APPROVED with corrections; SendPreempt guard requires two-branch post-send shape (not contract-only)
- **Expected test count delta**: +10 to +15 behavioral pins
- **Estimated implementation size**: ~80-120 lines changed in `Net.lua`, ~150-200 lines added in `tests/test_state_bot.lua`
