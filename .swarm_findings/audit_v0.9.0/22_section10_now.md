# Section 10 (Hokm Faranka) — re-audit at HEAD v0.9.0

HEAD = `9c32c50` (v0.9.0). Evidence from `git show 10f05a5` (v0.8.4) and
`git show 4a51d93` (v0.8.5) plus current `Bot.lua` / `State.lua`.

## Code: WIRED at v0.9.0

All landed inside the `pickFollow` Hokm-trump block (Bot.lua ~2601-2700),
M3lm-gated, only fires when `contract.type == K.BID_HOKM` + `#winners > 0`.

- **Exception #2** (only 2 trumps total): wired v0.8.4. Counts trumps in
  hand; `myTrumpCount == 2` sets `farankaTriggered = true`
  (Bot.lua:2628-2635).
- **Exception #4** (bidder + opp trump exhausted): wired v0.8.4. Walks
  opp seats checking `Bot._memory[s].void[contract.trump]`; both must be
  void (Bot.lua:2658-2670).
- **Exception #3** (J dead, 9 is new top): wired v0.8.5. Predicate is
  `S.HighestUnplayedRank(contract.trump) == "9"` AND we hold trump-9
  (Bot.lua:2647-2656). Depends on the v0.8.5 State fix below.
- **Anti-rule (J+8 rebuttal)**: wired v0.8.4. After triggering, if
  trick.lead is opp bidder + lead.rank == "Q" + we hold both trump-J
  and trump-8 → `farankaTriggered = false` (Bot.lua:2674-2691).
- **Behavior on trigger**: prefers non-trump non-winners, falls back to
  any non-winner; uses `lowestByRank` (Bot.lua:2694-2703).

## State.HighestUnplayedRank trump-rank fix (v0.8.5)

State.lua:1294-1322. Was walking plain `AKA_ORDER`
(`A>T>K>Q>J>9>8>7`) for every suit. Now declares
`TRUMP_HOKM_ORDER = { "J","9","A","T","K","Q","8","7" }` and inside
`S.HighestUnplayedRank` switches order when
`s.contract.type == K.BID_HOKM and s.contract.trump == suit`. Auto-detect
is correct; no caller change needed.

Caller usage in current HEAD (line numbers shifted from v0.8.5 commit
note's 1503/1832):
- **Sweep-pursuit boss detection**: now Bot.lua:1581-1589 (was 1503).
- **Trump-pull-skip guard**: now Bot.lua:1925-1926 — gates `Bot.IsAdvanced()
  and S.HighestUnplayedRank(contract.trump) ~= "J"` (was 1832). Correct
  semantic intent ("J still live"); fix unblocks it from misreporting "A".

## Code: NOT WIRED at v0.9.0 (confirmed deferred)

- **Exception #1** (pursuing Al-Kaboot): no Kaboot-aware Faranka branch.
- **Exception #5** (partner shown extra trump): no `partnerExtraTrump`
  ledger key; sampler/style-ledger absent.
- **Anti-rule pos-4 take-with-9 only**: no specific branch — generic
  "play winner" default covers it incidentally but not by name.

## Doc drift (HIGH)

`docs/strategy/decision-trees.md` Section 10 still tags exceptions
**#2, #3, #4 AND the J+8 anti-rule** as `(not yet wired)` at v0.9.0
(lines 248-252). The v0.9.0 commit updated several other rows (Section 9
N-1/N-2/N-3, Section 11 pigeonhole/Sun-bidder/baitedSuit) but missed
Section 10. MAPS-TO citations still point at the placeholder
`Bot.lua:1457` rather than the real ~2601 block.

## Tests

Neither v0.8.4 nor v0.8.5 added tests/ files (319→319→319 unchanged).
No `test_*faranka*` exists. Branches are wired but unverified by the
suite — every trigger and the J+8 rebuttal is regression-bare.
