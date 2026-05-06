# M3 — sampleConsistentDeal desire-table clone

**Verdict: SHIPPED, CORRECT.**

## Original finding
> sampleConsistentDeal lines 368 + 428 mutate shared desire/strong
> tables across attempts and seats. Distorts sample under retry.

## Patch location (current `BotMaster.lua`)

Lines **377-379**, immediately after the alias-selection block at
364-367 (`if s == bidder then desire = strong elseif ... end`):

```lua
local desireOrig = desire
desire = {}
for k, v in pairs(desireOrig) do desire[k] = v end
```

This is the canonical Lua 5.1 shallow-copy idiom (no
`vim.tbl_extend` available; that's Neovim).

## Mutation sites — all post-clone

| Line | Mutation | Pre-fix risk | Now |
|------|----------|--------------|------|
| 380  | `desire[pSignalSuit] = 1` | Wrote into shared `partnerDesire` | Local |
| 403  | `desire = {}` (Kawesh clear) | Replaced local var only — already safe | Still local |
| 440  | `desire[suit] = 1` (leadCount) | Wrote into shared `defenderDesire`/`strong` | Local |
| 462  | `desire[card] = math.max(...)` (touching-honors) | Would have leaked into shared tables | Local |
| 468  | `desire[hi .. suit] = nil` (broke clear) | Would have wiped shared K/Q/J entries! | Local |

The 462/468 mutations are **new in v0.9.0** (touching-honors wire,
also part of the same commit). Without the clone they would have
been worse than the original bug — `desire[card] = nil` mutation on
the shared `strong` table would have permanently zeroed strong-card
weights for subsequent seats and attempts.

## Q4 — does `strong` get cloned?

Yes, indirectly. `strong` is one of three source tables aliased into
`desire` at line 364 (bidder branch). The clone runs unconditionally
on whichever table `desire` points to, so `strong`, `defenderDesire`,
and `partnerDesire` are all protected. The empty-table branch
(`else desire = {}`) clones an empty table — wasted work but
harmless.

## Q5 — retry idempotence

Verified by inspection: the clone is inside the `for s = 1, 4` seat
loop, which is itself inside the `for attempt = 1, maxAttempts` loop
(line 321). So every `(attempt, seat)` pair gets a fresh clone.
Attempt-2 sees the original unmutated `strong`/`defenderDesire`/
`partnerDesire` from the outer scope. No trace needed — the
structural nesting guarantees it.

## Q6 — performance cost

3 non-self seats × 15 attempts × 1 clone = **45 clones max** per
`sampleConsistentDeal` call (worst case; usually ok'd in 1-2
attempts).

Each desire table holds ≤32 keys (full deck size), and bidder/
defender desires typically have 4-8 entries (A/K of side suits,
J/9 of trump). pairs-iter copy of <10 entries is negligible —
~50ns each in LuaJIT, single-digit µs total per PickPlay call.

`PickPlay` runs once per bot decision (not per rollout — rollouts
get the *result* of one sample). Cost is invisible.

## Files
- `C:\CLAUDE\WHEREDNGN\BotMaster.lua` lines 198, 320, 364-379
- Commit `9c32c50` (v0.9.0)
