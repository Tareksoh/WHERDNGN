# 71 — Nil/Empty Hand Crash Hunt (HEAD = v0.7.2)

Verdict: NO crash paths found. Defenses are uniform. One latent silent-corruption category (sparse hands) exists but does not crash.

## Per-question findings

### 1. `pickLead`/`pickFollow` called with empty hand — Bot.lua:1435, 2164
SAFE. The only caller is `Bot.PickPlay` at Bot.lua:2902–2914, which gates on
`if #legal == 0 then return nil end` before invoking either picker. With an
empty hand `legalPlaysFor` (Bot.lua:1376) returns `{}`, the `#legal==0`
branch fires, neither picker is reached. Internally both helpers also use
`#fromX > 0` guards on every sub-list before falling through to the
`lowestByRank(legal,…)` final return.

### 2. `Bot.PickSWA` with `#hand == 0` (post-final-play) — Bot.lua:3375
SAFE. v0.5.17 added explicit guard:
`if not hand or #hand == 0 or #hand > 4 then return false end` (Bot.lua:3375).
Verified against CHANGELOG v0.5.17 entry. Also guards on `phase != PHASE_PLAY`
and missing contract upstream.

### 3. `R.IsValidSWA` with empty hand — Rules.lua:349
SAFE BUT SUBTLE. Returns `true` only when `#plays == 0 AND #hand == 0`
(line 384), i.e. between tricks. Mid-trick empty-hand short-circuits to
`#legal == 0 → return false` (line 404, comment "shouldn't happen").
The line-363 `#plays == 4` branch resolves the trick first to avoid a
v0.5.17-pre false-positive when caller plays last card as 4th play of a
losing trick. Iteration uses `hands[s] or {}` defensively.

### 4. `BotMaster.PickPlay` empty hand — BotMaster.lua:743
SAFE. Line 756: `if not hand or #hand == 0 then return _restore(nil) end`.
The `_restore` wrapper guarantees `Bot._inRollout` is reset even on the empty
path. Outer `pcall` (line 795) catches downstream rollout errors.

### 5. `Bot.PickBid` with corrupt hand (nil entries) — Bot.lua:1018
DEFENSIVE for nil hand (line 1020 `→ BID_PASS`). For sparse-array nil holes
(`{c1, nil, c3}`) Lua's `ipairs` stops at first nil — silent under-counting,
no crash. `aceCountAndMardoofa`, `sunStrength`, `beloteSuit` all use
`for _, c in ipairs(hand)` so a corrupt sparse hand silently scores low and
the bot passes. No crash, but a sparse-hand bug elsewhere would be invisible.

### 6. `R.DetectMelds` with empty hand — Rules.lua:194
SAFE. Empty hand → `bySuit` all empty lists → no sequences → `byRank` empty
→ no carrés → returns `{}`. No nil deref. `Bot.PickMelds` (Bot.lua:2921)
also returns `{}` early on `not hand`.

## Cross-cutting observations

- `Net.lua:3389` `MaybeRunBot` PHASE_PLAY branch wraps the bot body in
  `pcall` (Net.lua:3830) — any picker crash recovers without freezing the
  table; failure path falls through to the `_HostTurnTimeout` lowest-legal
  recovery noted in the comment.
- AFK pre-deal (`hostHands` not yet populated): every entry point uses
  `S.s.hostHands and S.s.hostHands[seat]` then `if not hand` → safe nil-chain.
- Sparse-array silent-corruption is the only remaining category. Not a
  crash, but `ipairs` early-termination on `{c, nil, c}` would let a
  malformed deal pass through every picker scoring near-zero. A defensive
  `#hand` audit assertion at hand-creation sites would catch this; the
  pickers themselves cannot detect it.
