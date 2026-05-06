# Section 10 audit — Hokm Faranka (v0.7.1, HEAD = v0.7.2)

## Scope

Section 10 has 9 rules in the Hokm-Faranka block (Bot.lua:2063-2597 `pickFollow`):
- 1 default rule (NO Faranka unless exception)
- 5 narrow exceptions (#1–#5, all `Common`/`Sometimes`)
- 2 explicit anti-Faranka counter-rules (#7, #8 in the table — Definite/Common)
- 1 meta-rule (worst-case assumption)

Note: the 3 Sun-Faranka rows above the Hokm subhead are scoped to Section 5 (one is wired at Bot.lua:2126-2179, v0.5.21). All 3 Sun rows reference Section 5 for full rules, so this audit treats them as Section 5 territory.

## Results

| # | Rule | Status |
|---|---|---|
| Sun 1 | A+cover pos-4 Faranka | **WIRED-CORRECT** (Bot.lua:2150-2179) |
| Sun 2 | Al-Kaboot pos-4 Faranka | NOT-WIRED |
| Sun 3 | Score-flip Faranka | NOT-WIRED |
| Hokm default | NO Faranka | **WIRED-CORRECT** (no Faranka heuristic exists; winners-branch Bot.lua:2369-2467 picks cheapest winner; loser-branch falls through to lowestByRank Bot.lua:2596) |
| Hokm exc #1 | Al-Kaboot pursuit | NOT-WIRED |
| Hokm exc #2 | Only 2 trumps | NOT-WIRED |
| Hokm exc #3 | J dead, 9 is top | NOT-WIRED |
| Hokm exc #4 | Bidder + opp trump exhausted | NOT-WIRED |
| Hokm exc #5 | Partner shown extra trump | NOT-WIRED |
| Anti #7 | Opp bidder led trump-Q + J+8 → take | **WIRED-CORRECT** (winners-branch fires; J wins) |
| Anti #8 | Pos-4 9-only + opp Faranka'd → take with 9 | **WIRED-CORRECT** (winners-branch; 9 is the only winner) |
| Meta #9 | Trump live → assume worst, cover | **WIRED-CORRECT** (no voluntary duck path exists) |

## v0.5.20 verification

The v0.5.20 changelog claim — "all rules ALIGNED via the absence of any Faranka path" — **holds**. The audit's reasoning is structurally correct:

1. The default (no Faranka) is satisfied **by omission**: Bot.lua:2369-2467 always picks a winner if one exists; Bot.lua:2475-2596 falls through to `lowestByRank`. There is no `if shouldDuckTrump then` branch anywhere in `pickFollow`.
2. Anti-rules #7 and #8 are satisfied by the same omission — the bot can't be tempted to Faranka because the heuristic doesn't exist.
3. The 5 exceptions are genuinely deferred (`(not yet wired)` in the doc matches the code). Wiring them risks misfire for marginal Common-confidence gain.

**Conclusion:** v0.5.20's "no code change" was correct. Nothing was missed. The split is clean: 4 WIRED-CORRECT-by-omission, 5 NOT-WIRED-by-design, 1 WIRED-CORRECT-explicitly (Sun pos-4 Faranka, separate Section 5 row landed v0.5.21 the next release).

## Recommendation

No action. Section 10 status remains "audit complete, exceptions deferred."
