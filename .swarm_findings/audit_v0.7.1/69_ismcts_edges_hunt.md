# ISMCTS Rollout Edge-Case Hunt — BotMaster.lua v0.7.2

**Verdict:** Two real bugs, one regression risk, four cleared.

## Findings

### B-1 (HIGH): per-loop pcall poisons all 100 worlds on single error
`BM.PickPlay` lines 795–813 wrap the ENTIRE world-loop in one pcall.
If world 47/100 errors (sampler edge case, malformed card,
`R.ScoreRound` boundary), the pcall catches and `_restore(nil)`
returns nil — discarding worlds 1–46's already-accumulated `scores`
plus worlds 48–100's would-be contributions. Bot.PickPlay then
falls through to heuristics for THIS move, masking a recoverable
single-world failure as a tier-degradation. The v0.5.3 comment
(line 787-794) notes pcall protects `_inRollout` leak — correct,
but pcall granularity should be per-world (move pcall inside
`for w = 1, numWorlds do`) so 99 healthy worlds still vote.

### B-2 (MED): desire-table mutation across attempts/seats
Lines 363-368: `desire = strong | defenderDesire | partnerDesire`
assigns the SHARED per-call helper table by reference, then line
368 (`desire[pSignalSuit] = 1`), line 391 (`desire = {}` Kawesh
clobber — only rebinds local), and line 428 (`desire[suit] = 1`
leadCount) mutate it. Within the 15-attempt outer loop AND across
seats in the same attempt, mutations leak: e.g. seat-2's
`partnerDesire[pSignalSuit]=1` mutation persists when seat-4 later
re-binds `desire = partnerDesire` (if `bidderPartner==4`). Earlier
audit "idempotent now" claim is FALSE — only the local rebind on
line 391 is safe; lines 368 and 428 still mutate shared state.
Fix: shallow-copy on assignment or build all desire tables fresh
inside the seat loop.

### B-3 (LOW): maxAttempts=15 fallback returns under-sized hands
Lines 469-507 fallback ignores `voids` (intentional) but doesn't
guard `idx <= #pool` exhaustion against `#hand < n`. If meld pins
+ pool < required size, returns truncated hand silently; rollout
`heuristicPick` returns nil mid-trick, breaks loop, `ScoreRound`
runs on <8 tricks producing skewed `result.raw` diff that still
votes in `scores[card]`. Add `if #hand < n then return nil end`
and let PickPlay's `if world then` guard skip the bad sample.

## Cleared
- (1) Sampler always returns a deal table; never nil.
- (2) `used[]` table + meld pre-pin prevents double-deal.
- (5) `_inRollout` guard reliable; `_restore` runs on all post-flag returns.
- (6) End-of-round `#simTricks >= 8` correctly fires `R.ScoreRound`.

---
- B-1 single-pcall masks all 100 rollouts on one bad world
- B-2 desire-table mutation still shared across attempts/seats
- B-3 fallback can return short hands without nil-signal
