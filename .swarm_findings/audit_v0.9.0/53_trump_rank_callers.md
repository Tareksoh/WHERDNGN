# 53 — v0.8.5 S.HighestUnplayedRank trump-rank fix: caller audit

## Verdict: CLEAN

The v0.8.5 fix is COMPLETE. No leftover callers; no parallel
AKA_ORDER walks for trump exist outside the fixed function.
Re-audit at v0.9.0 HEAD confirms all caller sites resolve via
the now-trump-aware `S.HighestUnplayedRank` in State.lua:1309.

## All callers of `S.HighestUnplayedRank` (production code)

| # | File:Line | Suit arg | Hokm-trump invokable? | J-as-boss correct? |
|---|---|---|---|---|
| 1 | State.lua:1337 (`S.LocalAKAcandidate`) | `su` (filtered: `su ~= trump`) | NO — explicit non-trump filter | N/A |
| 2 | Bot.lua:1595 (`pickLead` trumpExhausted probe) | `contract.trump` | YES — predicate `== nil` | OK (trump-aware order) |
| 3 | Bot.lua:1600 (`pickLead` boss-scan, sweep-pursuit) | `su` of any held card (incl. trump) | YES — iter walks legal hand | OK — returns "J" when J live |
| 4 | Bot.lua:1628 (`pickLead` non-trump boss) | `su` (filtered: `su ~= contract.trump`) | NO — explicit non-trump filter | N/A |
| 5 | Bot.lua:1937 (J+9 trump-lock detect) | `contract.trump` | YES — predicate `~= "J"` | OK — fires only when J fallen |
| 6 | Bot.lua:2112 (single-opp void exploit) | `su` (filtered: `su ~= contract.trump`) | NO — explicit non-trump filter | N/A |
| 7 | Bot.lua:2659 (Faranka exception #3) | `contract.trump` | YES — predicate `== "9"` | OK — fires iff J fallen + 9 live |
| 8 | Bot.lua:3002 (`Bot.PickAKA`) | `su` of `leadCard` (gated: `su == trump → return nil` at 2992) | NO — pre-filtered earlier | N/A |
| -- | C-4 last-trick patch (`bot_proposed_patches/`, NOT shipped) | — | — | — |

5 trump-invokable sites (#2, #3, #5, #7 explicitly with `contract.trump`; #3 with iterated `su` that may equal trump). All 5 produce correct trump ordering after v0.8.5.

## Specific check items from prompt

1. **BotMaster.lua sampler AKA_ORDER walk for trump?** NO. Zero
   `S.HighestUnplayedRank` callers in BotMaster.lua. Sampler walks
   the unseen-deck via fixed `{A,T,K,Q,J,9,8,7}` literal
   (BotMaster.lua:159) for *card pool*, not boss detection. Pin
   logic for J/9 of trump uses raw `J<trump>`/`9<trump>` string
   lookups (lines 273, 467) — no rank-ordering involved.

2. **Bot.lua `pickLead` trump-pull-skip (line ~1937)?** Correct.
   Reads `S.HighestUnplayedRank(contract.trump) ~= "J"` to gate
   J+9 trump-lock detection. Now correctly identifies J as boss.

3. **Bot.lua `pickFollow` over-trump computation?** Uses
   `C.TrickRank` (Cards.lua:107), NOT `HighestUnplayedRank`.
   `TrickRank` is contract-aware via `K.RANK_TRUMP_HOKM` /
   `K.RANK_PLAIN` lookup tables — independent of the AKA_ORDER
   walk. CLEAN.

4. **Rules.lua `R.TrickWinner` / `R.TrickPoints`?** Zero callers
   of `S.HighestUnplayedRank` in Rules.lua. Winner determination
   uses `C.TrickRank` via `R.CurrentTrickWinner` (Rules.lua:34-58).
   Same contract-aware path. CLEAN.

## Parallel AKA_ORDER replication?

`AKA_ORDER` literal is local to State.lua:1294. No file outside
State.lua re-implements the trump rank walk. The unrelated
unseen-deck literal in BotMaster.lua:159 uses the same character
set with no rank-ordering semantics.

## Test coverage gap (informational, not a bug)

`tests/test_state_bot.lua:263-271` only exercises non-trump suits.
A targeted `assertEq(S.HighestUnplayedRank(trump), "J")` pin (with
`s.contract = {type=BID_HOKM, trump="H"}`) would be cheap insurance
against future regression of the trump-aware branch.
