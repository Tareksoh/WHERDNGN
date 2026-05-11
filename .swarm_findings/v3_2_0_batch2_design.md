# v3.2.0 Cleanup Batch 2 — Retry Abstraction (Design / Inventory Pass)

**Status**: design only, no code changes. Output for Codex review
before implementation.

**Branch baseline**: `main` at `fde6aea` (post-Batch 1).
**Net.lua size**: 6101 lines.
**Target**: extract the repeated 250ms re-broadcast pattern into one
`broadcastWithRetry` helper local to `Net.lua`.

## 1. Inventory — all 18 retry sites in Net.lua

Grep `C_Timer\.After\(0\.25` → 18 matches.

| # | Function | Line | Tag | Guard shape |
|---|---|---|---|---|
| 1 | `N.SendBidCard` | 249 | MSG_BIDCARD | phase ∈ {DEAL1, DEAL2BID} |
| 2 | `N.SendTurn` | 280 | MSG_TURN | isHost + turn == seat + turnKind == kind |
| 3 | `N.SendBid` | 298 | MSG_BID | phase ∈ {DEAL1, DEAL2BID} |
| 4 | `N.SendContract` | 322 | MSG_CONTRACT | contract.bidder == X + type == X + trump == X |
| 5 | `N.SendDouble` | 360 | MSG_DOUBLE | contract == contractAtSend + doubled + doublerSeat == seat |
| 6 | `N.SendTriple` | 380 | MSG_TRIPLE | contract == contractAtSend + tripled |
| 7 | `N.SendFour` | 398 | MSG_FOUR | contract == contractAtSend + foured |
| 8 | `N.SendGahwa` | 415 | MSG_GAHWA | contract == contractAtSend + gahwa |
| 9 | `N.SendBelote` | 463 | MSG_BELOTE | phase == PLAY + beloteAnnounced[seat] |
| 10 | `N.SendMeld` | 562 | MSG_MELD | phase ∈ {PLAY, DEAL3} |
| 11 | `N.SendAKA` | 589 | MSG_AKA | phase == PLAY + akaCalled match |
| 12 | `N.SendSWAReq` | 642 | MSG_SWA_REQ | phase == PLAY + swaRequest.caller == seat |
| 13 | `N.SendSWAResp` | 667 | MSG_SWA_RESP | phase == PLAY + swaRequest.caller == caller |
| 14 | `N.SendTakweesh` | 693 | MSG_TAKWEESH | phase ∈ {PLAY, TAKWEESH_REVIEW} |
| 15 | `N.SendKawesh` | 709 | MSG_KAWESH | phase == DEAL1 |
| 16 | `N.SendPlay` | 743 | MSG_PLAY | phase == PLAY |
| 17 | `N.SendOvercallDecision` | 1826 | MSG_OVERCALL_DECISION | phase == OVERCALL |
| 18 | `N._OnContract` (inline) | 2113 | MSG_CONTRACT | s.contract truthy (calls `N.SendContract` recursively) |

## 2. Guard pattern categorization

### Pattern A — Phase-only
Simple `S.s.phase == X (or Y)`. **7 sites**: BidCard, Bid, Meld,
Takweesh, Kawesh, Play, OvercallDecision.

### Pattern B — Phase + state identity
Phase check + check on a state field. **5 sites**: Turn (no explicit
phase; turn-kind IS the phase-equivalent), Belote, AKA, SWAReq, SWAResp.

### Pattern C — Contract-table identity + post-apply flag
The v3.1.14 fix. Captures `contractAtSend = S.s.contract` before the
Apply* call advances state. **4 sites**: Double, Triple, Four, Gahwa.

### Pattern D — Contract-by-value identity
SendContract — compares bidder + type + trump fields. **1 site**.

### Pattern E — Redundant second-layer retry
`_OnContract` host-post-apply (line 2113) re-broadcasts MSG_CONTRACT
via `N.SendContract(...)` — which itself now has a retry (v3.1.13).
**1 site, redundant**. Cleanup opportunity.

## 3. Proposed helper API

```lua
-- Module-local helper near `broadcast` (Net.lua:37).
-- Wraps a guarded re-broadcast 250ms after the initial send. The
-- guard closure decides whether the retry is still relevant — same
-- shape as the existing per-site inline guards, just consolidated.
local function broadcastWithRetry(frame, guardFn, delay)
    broadcast(frame)
    if not (C_Timer and C_Timer.After) then return end
    C_Timer.After(delay or 0.25, function()
        if guardFn() then broadcast(frame) end
    end)
end
```

### Migration shape per pattern

**Pattern A (phase-only)** — current:

```lua
function N.SendBidCard(card)
    broadcast(("%s;%s"):format(K.MSG_BIDCARD, card or ""))
    if C_Timer and C_Timer.After then
        C_Timer.After(0.25, function()
            if S.s.phase == K.PHASE_DEAL1
               or S.s.phase == K.PHASE_DEAL2BID then
                broadcast(("%s;%s"):format(K.MSG_BIDCARD, card or ""))
            end
        end)
    end
end
```

After:

```lua
function N.SendBidCard(card)
    broadcastWithRetry(
        ("%s;%s"):format(K.MSG_BIDCARD, card or ""),
        function()
            return S.s.phase == K.PHASE_DEAL1
                or S.s.phase == K.PHASE_DEAL2BID
        end
    )
end
```

**Pattern C (post-apply identity)** — current:

```lua
function N.SendDouble(seat, open)
    local frame = ("%s;%d;%s"):format(K.MSG_DOUBLE, seat,
        (open == false) and "0" or "1")
    broadcast(frame)
    local contractAtSend = S.s.contract
    if C_Timer and C_Timer.After then
        C_Timer.After(0.25, function()
            if S.s.contract == contractAtSend
               and S.s.contract
               and S.s.contract.doubled
               and S.s.contract.doublerSeat == seat then
                broadcast(frame)
            end
        end)
    end
end
```

After:

```lua
function N.SendDouble(seat, open)
    local frame = ("%s;%d;%s"):format(K.MSG_DOUBLE, seat,
        (open == false) and "0" or "1")
    local contractAtSend = S.s.contract
    broadcastWithRetry(frame, function()
        return S.s.contract == contractAtSend
           and S.s.contract
           and S.s.contract.doubled
           and S.s.contract.doublerSeat == seat
    end)
end
```

Pattern C closures correctly capture `contractAtSend` and `seat` via
upvalue capture — same semantics as the current inline closure.

## 4. Migration risks

### R1 — Source-pin tests that look at function bodies

3 known pins look for `C_Timer.After(0.25` *inside* a specific
function body:

| Pin | File line | Function inspected | Action needed |
|---|---|---|---|
| U.1 (NetU-01) | tests:2807 | `N._HostResolveOvercall` | Update or remove |
| AX.3 (v3.1.10) | tests:7785 | `N.SendPlay` | Update to look for `broadcastWithRetry(` |
| AX.6 (v3.1.10) | tests:7797 | `N.SendOvercallDecision` | Update to look for `broadcastWithRetry(` |

The AZ behavioral tests (AZ.1-29 across SWA/Takweesh/Kawesh/Belote/
Meld/AKA/Bid/Contract/BidCard/Double/Triple/Four/Gahwa/Play/Overcall
/Skip) keep working without modification because they exercise
the actual code path and count broadcasts via the captured
`C_ChatInfo.SendAddonMessage`. The retry is still triggered through
`C_Timer.After`, just from inside the helper.

Recommendation: convert the 3 source pins to look for
`broadcastWithRetry(` within the function body. This preserves the
guardrail intent (retry is wired) without enforcing a specific
implementation detail.

### R2 — Comment loss

Each current retry site has detailed per-site comments documenting
why the retry exists, what idempotence guarantees the receiver has,
and what edge cases the guard handles. These would relocate but
shouldn't be lost — the comment moves with the function body to
describe the call to `broadcastWithRetry`.

### R3 — Pattern C closure capture

The 4 Pattern C sites use `local contractAtSend = S.s.contract` to
freeze the contract table reference for the post-apply identity check.
Lua closures capture upvalues correctly across function boundaries,
so the migration preserves semantics. Behavioral tests AZ.23-25 with
the contract-replaced suppress assertions will continue to pass.

### R4 — `_OnContract` recursive retry (site #18)

This site is *outside* a Send* helper. It calls `N.SendContract(...)`
from `_OnContract`'s host-post-apply branch, and `N.SendContract`
itself now retries (since v3.1.13). The second-layer retry produces
3 total MSG_CONTRACT broadcasts within ~0.25s of the contract event.

Two clean options:

**Option a** (recommended): remove site #18 entirely. `N.SendContract`
already retries — the recursive layer is now redundant. This is a
behavior change in the sense that there's one fewer broadcast in
the happy path, but the receiver-side idempotence (ApplyContract
match-check) makes the third frame a no-op anyway.

**Option b**: leave site #18 alone. Migrating sites 1-17 doesn't
require touching #18. The redundancy is documented but defensive.

Codex's call on which option lands in Batch 2 or a follow-up.

### R5 — No `_HostResolveOvercall` migration in this batch

Site U.1 mentions a retry inside `_HostResolveOvercall` (line ~2113
context). That's actually the same as site #18 — the v0.11.11 NetU-01
fix that lives inside `_OnContract`. There's no separate Pattern at
`_HostResolveOvercall` itself. The U.1 source pin verifies the wider
context. **U.1's fate depends on R4 decision**.

### R6 — Helper placement

Two reasonable placements for the local helper:
- **Near `broadcast`** (Net.lua:37) — groups all low-level send
  primitives together. Preferred for module structure clarity.
- **Just before the first Send* function that uses it** (around
  Net.lua:235) — closer to first use. Lua scoping allows either.

Recommendation: place near `broadcast`. The retry IS a thin wrapper
on `broadcast` and reads naturally as part of the "send primitives"
section.

## 5. Tests required for Batch 2

Per audit plan: "Add one test proving the helper does not call guard
after state changes incorrectly."

Proposed AZ.30 series (additions, not replacements):

- **AZ.30a** — `broadcastWithRetry(frame, alwaysTrue)` emits 1
  initial + 1 retry (2 broadcasts)
- **AZ.30b** — `broadcastWithRetry(frame, alwaysFalse)` emits 1
  initial only (guard rejects retry)
- **AZ.30c** — guard closure captures locals at call time (Lua
  upvalue capture verified end-to-end)
- **AZ.30d** — `delay` parameter optional (defaults to 0.25)
- **AZ.30e** — no retry queued when `C_Timer.After` is nil (degrade
  cleanly in test harnesses that strip C_Timer)

These complement, not replace, the existing AZ behavioral tests for
the 17 Send* sites that now route through the helper.

## 6. Recommended migration sequence

If Codex prefers staged review:

- **Phase 2a**: add `broadcastWithRetry` helper near `broadcast`,
  migrate Pattern A sites (7 sites: BidCard, Bid, Meld, Takweesh,
  Kawesh, Play, OvercallDecision). Update U.1, AX.3, AX.6 source
  pins. Add AZ.30a-e.
- **Phase 2b**: migrate Pattern B sites (5: Turn, Belote, AKA,
  SWAReq, SWAResp).
- **Phase 2c**: migrate Pattern C sites (4: Double, Triple, Four,
  Gahwa) — most subtle due to closure capture of `contractAtSend`.
- **Phase 2d**: migrate Pattern D (1: Contract).
- **Phase 2e**: address `_OnContract` recursive retry (R4 decision).

If Codex prefers one batch: do all phases in a single commit. The
mechanical refactor is uniform shape; staging only helps if
intermediate review surfaces unexpected issues.

Recommendation: **single batch** based on the mechanical uniformity,
with the option to split if review-cost becomes a concern.

## 7. Out of scope (per audit plan)

- No retry added to skip messages (deferred to Batch 4 per plan)
- No retry added to MSG_PREEMPT/MSG_PREEMPT_PASS (Batch 4)
- No phase guard added to Batch 1's `N.SendSkip*` helpers
- No retry-delay tuning (0.25s stays everywhere)
- No retry-count change (still single retry)

## 8. Summary numbers

- **18 retry sites** in Net.lua
- **17 migrate** to `broadcastWithRetry`
- **1 redundant** (`_OnContract` recursive — R4 decision)
- **3 source-pin tests** need updates (U.1, AX.3, AX.6)
- **0 behavioral tests** need changes (AZ tests stay green)
- **~250 lines** of inline retry blocks removed
- **~10 lines** of helper added
- **No gameplay behavior change** (every guard semantic preserved)

## 9. Ready-to-implement checklist

If Codex approves the design:
- [ ] Branch off main: `v3.2.0-cleanup-batch2`
- [ ] Add `broadcastWithRetry` near `broadcast` (Net.lua:~37)
- [ ] Migrate all 17 retry sites (or staged per §6)
- [ ] Handle site #18 per §R4 decision
- [ ] Update 3 source-pin tests (U.1, AX.3, AX.6)
- [ ] Add AZ.30a-e behavioral coverage for the helper itself
- [ ] Run `python tests/run.py` — expect 1065 + 5 new = 1070 pass
- [ ] Codex review of diff before merge
