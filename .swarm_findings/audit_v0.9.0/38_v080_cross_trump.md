# 38 — v0.8.0 cross-trump Hokm take audit (commit a48fe34)

## What "cross-trump Hokm take" means

Within the same 5s post-Hokm overcall window introduced in v0.7.0, a
non-bidder seat may now also TAKE the contract as **their own Hokm**
on a *different* trump suit. v0.7.0 only allowed TAKE → Sun; v0.8.0
adds the symmetric Hokm-with-different-trump option. Bidder UPGRADE
remains Sun-only (a bidder switching their own Hokm trump makes no
strategic sense — they already chose).

## Verification by question

### 1. Net.lua MSG_OVERCALL_DECISION wire — new action types

`N.LocalOvercall` (Net.lua:1262–1295) accepts `TAKE_HOKM_<S|H|D|C>`
strings: 11-char length, `TAKE_HOKM_` prefix, single-char suit ∈
`{S,H,D,C}`. Routes via the **same** `K.MSG_OVERCALL_DECISION` frame
(line 1300). **No new tag** — only the decision payload string got
longer. CHANGELOG line 524 explicitly notes "no protocol change."

### 2. State.lua S.FinalizeOvercall — contract trump mutation

State.lua:961–1005 handles `result.type == "TAKE_HOKM"` correctly:
- `s.contract.type` ← `K.BID_HOKM` (stays Hokm, no Sun multiplier)
- `s.contract.trump` ← `result.trump` (rewritten to taker's suit)
- `s.contract.bidder` ← `result.by`
- `s.belPending` re-derived for the new defender pair (mirrors
  the `TAKE`-as-Sun branch). Solid.

### 3. Bot AI for cross-trump take

`Bot.PickOvercall` (Bot.lua:3009–3060) iterates the 3 non-current-
trump suits, computes `suitStrengthAsTrump`, applies the **B-1
Saudi minimum-Hokm shape gate** (J of trump + count ≥ 3), and
compares raw scores against `K.BOT_OVERCALL_TAKE_HOKM_TH = 80`. When
Sun-take and Hokm-take both clear, **higher raw score wins**. This
is well-grounded in the existing escalation-formula scale.

### 4. Wire-protocol back-compat

**v0.7.0 host receives a v0.8.0 `TAKE_HOKM_S` frame:** rejected by
the legacy validator (`decision ~= "UPGRADE" and ~= "TAKE" and ~=
"WAIVE"` → false). Frame silently dropped, treated as no-decision /
WAIVE on timeout. Safe, but the v0.8.0 client thinks it succeeded.
**v0.8.0 host receives v0.7.0 frames:** fully accepted (TAKE,
UPGRADE, WAIVE all still valid). Clean asymmetric back-compat —
**only safe if all clients run the same version**. No version
gating present; mixed-version groups will mis-resolve.

### 5. Pause/resume edge

Net.lua:414–428 (rejoin replay): if rejoiner arrives during
`PHASE_OVERCALL`, host re-emits `MSG_OVERCALL_OPEN` plus per-seat
`MSG_OVERCALL_DECISION` for each already-recorded `decisions[seat]`.
Since `TAKE_HOKM_<suit>` is just stored as a string in
`s.overcall.decisions[seat]`, replay carries it verbatim. Host-side
state correctly preserves it across the `S.ApplyPause` freeze
(`s.paused` flag doesn't touch `s.overcall`). Solid.

### 6. Tests added

**P-section (Rules):** P.23–P.29 (7 tests) — TAKE_HOKM resolution,
same-suit rejection, malformed-suit rejection, UPGRADE precedence,
bid-order priority across mixed TAKE/TAKE_HOKM, forced-contract
gating. **H-section (State+Bot):** H.15–H.17 (3 named, ~20 asserts)
— Bot.PickOvercall TAKE_HOKM_S choice with constructed strong
Spades hand, contract rewrite via FinalizeOvercall, lock-out, three
malformed-decision rejections (`TAKE_HOKM_X`, `TAKE_HOKM_`,
`TAKE_HOKM`). 319/319 total pass (was 292; +27 new — matches commit
claim). Coverage is thorough.

## Concerns

- **No mixed-version protection.** v0.7.0↔v0.8.0 will silently
  mis-resolve if seats run different versions. Consider an addon-
  version gate or feature-detect ping.
