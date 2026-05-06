# H1 Verification — Overcall Resolve Race (v0.8.6)

**Verdict: FIXED**

## Original finding (audit_v0.7.1/31)
`_OnOvercallResolve` re-derived the contract from a remote's *local*
`s.overcall.decisions` table. Dropped/reordered `MSG_OVERCALL_DECISION`
frames → remote derived a different contract than the host. The
`taken=true` branch was masked by the host's follow-up `MSG_CONTRACT`,
but the `taken=false` branch had no self-correction → desync persisted.

## v0.8.6 commit 0d0b4d0 — `Net.lua` diff
The `S.FinalizeOvercall()` call inside `_OnOvercallResolve` was deleted.
Replaced with a 2-line pure clear:
```lua
S.s.overcall = nil
S.s.phase = K.PHASE_DOUBLE
```
The wire payload (takenStr/by/otype) is unused; the function signature
is preserved for forward-compat / debug only.

## Current Net.lua state (HEAD = v0.9.0+)
- `_OnOvercallResolve` (1116-1144): does **NOT** call `S.FinalizeOvercall`. Confirmed.
- Clears `S.s.overcall = nil` (1141). Confirmed.
- Sets `S.s.phase = K.PHASE_DOUBLE` (1142). Confirmed.

## Host side (server-of-truth)
`_HostResolveOvercall` (Net.lua 1227-1258):
1. Snapshots prev contract values.
2. Calls `S.FinalizeOvercall()` (host's local copy of decisions IS authoritative).
3. `N.SendOvercallResolve(taken, by, type)`.
4. **If `result.taken`**: `N.SendContract(...)` re-broadcasts canonical contract → remote applies via `_OnContract` / `S.ApplyContract`. ✓
5. **If `taken=false`**: no `MSG_CONTRACT` sent. Host's `S.FinalizeOvercall` falls through the `if result.taken then` block (State.lua 979-1004) — contract is **untouched**, only `s.overcall=nil; s.phase=PHASE_DOUBLE`. Remote does the same → both stay on Hokm. ✓

## Adversarial scenario
Remote received bad/missing `MSG_OVERCALL_DECISION` frames →
`s.overcall.decisions` is stale. Then `MSG_OVERCALL_RESOLVE` arrives:
- Pre-fix: `S.FinalizeOvercall()` would call `R.ResolveOvercall` against the
  bad table → wrong contract on `taken=true`/false alike.
- Post-fix: `s.overcall.decisions` is **never read** by the remote. The
  whole table is nilled out via `s.overcall = nil`. On `taken=true`,
  the follow-up `MSG_CONTRACT` overwrites contract authoritatively. On
  `taken=false`, contract is left untouched (stays Hokm). No path from
  stale decisions to mutated contract on the remote. **Race closed.**

## Caveat
If `MSG_CONTRACT` is itself dropped on `taken=true`, remote stays on the
old (pre-overcall) contract — but that's a generic single-frame-drop
problem solvable by resync, not the H1 race. v0.9.x resync code path
(N._OnResyncRequest) would need to be checked separately if relevant.
