# BotMaster.rolloutValue audit (v0.7.2)

File: `C:/CLAUDE/WHEREDNGN/BotMaster.lua` lines 510-725 (rollout),
730-807 (PickPlay caller).

## 1. Recursion guard (v0.5.0 C-1) — INTACT

`rolloutValue` does NOT call `pickFollow`/`pickLead` from `Bot.lua`.
It uses an inlined local `heuristicPick` closure (lines 563-673)
that re-implements the Advanced-mirror heuristics directly. So the
recursion concern is theoretical only — `heuristicPick` does not
call `Bot.PickPlay`. Defence-in-depth is still provided by the
`B.Bot._inRollout = true` flag at line 740. `Bot.PickPlay`
(`Bot.lua:2664`) checks `if not Bot._inRollout` before delegating
to `BM.PickPlay`, so any future refactor that routes the rollout
back through `Bot.PickPlay` still cannot recursively re-enter
ISMCTS. Save/restore (`prevRollout`) at line 739/741 protects
nested host calls.

## 2. v0.5.3 pcall fix — INTACT

`pcall` wraps the entire rollout loop (lines 782-792). On error
the `not ok` branch at 793 calls `_restore(nil)` which restores
`B.Bot._inRollout = prevRollout`. Without this, a sampler/scorer
exception would silently disable Saudi Master ISMCTS for the rest
of the session by leaving `_inRollout = true` (Net.lua's outer
pcall catches the error but doesn't restore the flag). Comment
block at 774-781 documents the fix correctly. Verified intact.

## 3. End-of-round detection — CORRECT

Loop terminates `while #simTricks < 8` (line 676). Each completed
4-play trick is scored via `R.CurrentTrickWinner`, appended, and
the next trick is led by the winner (line 684). After 8 tricks,
`R.ScoreRound(simTricks, contract, meldsByTeam)` is called at
line 711 with the full trick history. This is the same final
scorer used by the live game.

## 4. Multiplier path inside rollout — CORRECT

`R.ScoreRound` (Rules.lua:598) applies all four multipliers
internally based on `contract.{doubled,tripled,foured,gahwa}`
(Rules.lua:800-803). The rollout passes the LIVE `S.s.contract`
through unchanged (line 510 → 711), so Bel/Triple/Four/Gahwa
multipliers are honoured automatically. Belote-immunity is
preserved by `R.ScoreRound`'s internal scan. Gahwa terminal cliff
is also handled: lines 720-723 add ±10000 when `result.gahwaWonGame`
indicates a match-decisive Gahwa, putting the contract-outcome
cliff above raw-point fluctuation.

## 5. Determinism — NOT deterministic per-rollout

`heuristicPick` itself is deterministic (no `math.random` calls in
the closure). But each call to `BM.PickPlay` runs N rollouts
(60-100) over distinct sampled worlds via `sampleConsistentDeal`,
which uses `math.random` (lines 191, 426). Pinning the RNG seed
BEFORE `BM.PickPlay` produces a deterministic aggregate score.
Inside a SINGLE rollout (fixed `world`) the playout is
deterministic.

## Caveats

- Initial-hand reconstruction (lines 514-529) for meld detection
  combines the sampled world with already-played cards from
  `S.s.tricks` and `S.s.trick`. Correct.
- Score returned is team-DIFF (us-them), not raw (line 719). This
  is the v0.7.x ranking-axis fix, intentional.
- Partner cooperates non-adversarially. Documented (lines 507-509).
