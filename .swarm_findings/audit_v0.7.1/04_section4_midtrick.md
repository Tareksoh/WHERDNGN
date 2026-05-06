# Section 4 — Mid-trick play (`pickFollow` pos 2-3) — audit v0.7.2

**HEAD:** v0.7.2 (commit 93b1e9d)
**Source doc:** `docs/strategy/decision-trees.md` Section 4
**Implementation:** `Bot.lua` `pickFollow` (Bot.lua:2063-2597)

## Rule-by-rule status

| # | Rule | Status | Site |
|---|---|---|---|
| 1A | Sun + OPP-winning + can't beat → SMALLEST in-suit (Tasgheer) | WIRED-CORRECT | Bot.lua:2512-2529 (doc marker) → falls through to `lowestByRank(legal)` at Bot.lua:2596 |
| 1B | Sun + PARTNER-winning + can't beat (smother failed) → SECOND-LOWEST | WIRED-CORRECT | Bot.lua:2327-2358 (new v0.7.2 branch) |
| 2 | Hokm losing-side trump follow → LOWEST trump (inverse) | NOT-WIRED | doc says `(not yet wired)` for read-side; default `lowestByRank` covers numerically but no explicit branch |
| 3 | Sun partner-winning + void in led → Tahreeb-encoded discard | WIRED-CORRECT | Bot.lua:2231-2325 (T-1 Bargiya, T-4 dump-larger with v0.5.11 K/T/A gate) |
| 4 | Sun deceptiveOverplay (sacrifice J / T) | NOT-WIRED | matches `(not yet wired)` in doc |
| 5 | Hokm deceptiveOverplay (sacrifice J of trump) | NOT-WIRED | matches doc |
| 6 | Hokm A+3-trump → no deceptive overplay | NOT-WIRED | gate-off condition not yet present |

## Takbeer / Tasgheer (Section 4 sub-table)

| Rule | Status | Site |
|---|---|---|
| Partner-CERTAIN-winning → Takbeer (HIGHEST) | WIRED-CORRECT (proxy) | Bot.lua:2200-2228 smother branch (donates highest of A/T/K/Q/J via descending sort) |
| Opp-CERTAIN-winning → Tasgheer (LOWEST) | WIRED-CORRECT | covered by 1A fall-through |
| Hokm trump rank-CONSECUTIVE Takbeer | NOT-WIRED | matches doc |
| Hokm trump non-consecutive INVERT | NOT-WIRED | matches doc |
| Hokm over-cut consecutive → smaller | NOT-WIRED | matches doc |

## K-tripled (مثلوث الشايب)

| Rule | Status |
|---|---|
| Sun + K + 2 lower, suit led → trickle smallest, K trick 3 | NOT-WIRED |
| Sun + lead إكَه withhold T to bait opp's K-tripled | NOT-WIRED |

Doc accurately marks both `(not yet wired)`.

## v0.7.2 verification

1. **Tasgheer (rule 1A) for Sun + opp-winning** — VERIFIED. v0.5.11's `highestByRank` branch at the function bottom is reverted to a documentation-only marker (Bot.lua:2512-2529); the function now falls through to `lowestByRank(legal, contract)` at Bot.lua:2596. CHANGELOG entry matches code.
2. **Rule 1B SECOND-LOWEST for Sun + partner-winning + Tahreeb-receiver context** — VERIFIED. Bot.lua:2343-2358 sorts in-suit follow ascending by `TrickRank` and returns `sorted[2]`. Gated to Sun + `#follow >= 2` + post-smother fall-through. Matches video #09 "biggest mistake" and Section 4 rule 1B.
3. **Test E.1 update** — VERIFIED. `tests/test_state_bot.lua:727-760` now expects `8H` (Tasgheer SMALLEST) with explicit v0.7.2 documentation header; new E.6 at line 919-965 pins rule 1B at `9H` (second-lowest of `{KH,9H,8H}`). CHANGELOG claims 292/292 pass with the +1 new test.

Section 11 rule 1 wire (`OnPlayObserved` Bot.lua:319-333) also confirmed in place per the v0.7.2 changelog claim, though that's outside Section 4 proper.
