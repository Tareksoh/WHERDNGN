# Audit 61 — Contract-Type Confusion Hunt (v0.7.2)

## Verdict
**CLEAN.** No active cross-contamination between Hokm/Sun logic
paths. Every Hokm-only branch surveyed gates correctly on
`contract.type == K.BID_HOKM`, and every Sun-only branch on
`K.BID_SUN`. Defensive `(contract.trump or "")` patterns in
`pickLead` make the trump-suit `~=` comparisons robust when
`contract.trump == nil`. `Cards.IsTrump`, `Cards.TrickRank`,
`Cards.PointValue` all short-circuit correctly in Sun (return
`RANK_PLAIN` / `false`).

## File / line audit (v0.7.2 HEAD)

| Concern | Location | Result |
|---|---|---|
| `R.CurrentTrickWinner` trump pre-scan | `Rules.lua:40` | Hokm-gated — trumpPlayed stays false in Sun, eligibility falls back to `s == leadSuit`. |
| `R.IsLegalPlay` overcut on trump-led | `Rules.lua:117` | Gated on `K.BID_HOKM and leadSuit == contract.trump`. Sun never enters. |
| `R.IsLegalPlay` "Sun: anything" early-out | `Rules.lua:143` | Correct — short-circuits before any Hokm trump-must-trump branch. |
| `R.DetectMelds` Carré-of-Aces (200) | `Rules.lua:196,241` | Sun-only via `isSun` flag. |
| `meldRank` trump-bonus tie-break | `Rules.lua:280,292` | Both gated on `BID_HOKM`. In Sun the carré probeSuit defaults to `"S"` (harmless: just a probe suit for `RANK_PLAIN` lookup; trump ordering inactive). |
| `R.CanBel` Sun gate | `Rules.lua:491` | Correct — Hokm always returns true. |
| `R.CanOvercall` Hokm-only window | `Rules.lua:512` | Correct — any non-Hokm contract returns false. |
| `R.ScoreRound` handTotal | `Rules.lua:613` | Correct ternary on `BID_SUN`. |
| `R.ScoreRound` Belote (K+Q trump) | `Rules.lua:631` | Hokm-only. Sun never opens this block — `kWho` stays nil, belote stays nil. |
| `R.ScoreRound` Al-Kaboot value | `Rules.lua:743` | `AL_KABOOT_HOKM` vs `AL_KABOOT_SUN` ternary correct. |
| `R.ScoreRound` Sun ×2 multiplier | `Rules.lua:799` | Applied only when `BID_SUN`; cannot accidentally fire in Hokm. |
| `BotMaster.getStrongCards` | `BotMaster.lua:39` | Two distinct branches, both correctly gated. |
| `BotMaster.getDefenderCards` | `BotMaster.lua:71` | Returns `{}` early for Sun — no trump access. |
| `BotMaster.getPartnerCards` | `BotMaster.lua:101,121` | Two distinct branches, properly gated. |
| `BotMaster.sampleConsistentDeal` H-1 J/9 pin | `BotMaster.lua:271` | `BID_HOKM and contract.trump` — correct. |
| `BotMaster` pigeonhole pin | `BotMaster.lua:293` | `BID_HOKM and contract.trump` — correct. |
| `BotMaster` rollout smother feedSafe | `BotMaster.lua:610` | `contract.type ~= BID_HOKM or leadSuit ~= trump` — fires safely in Sun. |
| `BotMaster` ducking unbeatable check | `BotMaster.lua:635` | Correct — Sun-only Ace-as-stopper detection. |
| `BotMaster` lead trump-pull | `BotMaster.lua:669` | `BID_HOKM and bidderTeam` — correct. |
| `Bot.PickAKA` | `Bot.lua:2811` | Hokm-only convention — correct. |
| `pickLead` H-7 Sun shortest-suit | `Bot.lua:2059` | `BID_SUN` gate — correct. |
| `pickLead` trump-pull (`isBidderTeam and isBidder`) | `Bot.lua:1437,1734` | `isBidderTeam` itself folds in `K.BID_HOKM` — Sun bidder cannot enter the trump-pull branch. |
| `pickFollow` Tahreeb / AKA receiver | `Bot.lua:2201,2213` | Both gated on `BID_HOKM and contract.trump`. |
| `pickFollow` Sun pos-4 Faranka | `Bot.lua:2251` | `BID_SUN` gate — correct. |
| `pickFollow` Hokm Faranka exceptions (M3lm) | `Bot.lua:2494` | `BID_HOKM and contract.trump` — correct. |
| `pickFollow` Sun re-entry second-lowest | `Bot.lua:2444` | `BID_SUN` — correct. |
| `pickFollow` Tanfeer skipTrump | `Bot.lua:2772` | `BID_HOKM and su == trump` — Sun never excludes a "trump suit". |
| `Bot.PickBid` Sun direct gates | `Bot.lua:1223,1280` | Correct — uses `sunStrength` (no trump bonuses). |
| `Bot.PickDouble` Sun bias | `Bot.lua:2997` | Correct: trump bonus only applied inside `BID_HOKM` block (line 2960); Sun adds flat +10. |
| `Bot.PickOvercall` `suit ~= contract.trump` | `Bot.lua:3282` | Reachable only when `contract.type == BID_HOKM` (per `R.CanOvercall`). Safe. |
| `Bot.PickSWA` Hokm safety net | `Bot.lua:3410` | Hokm-gated — correct. |

## Targeted answers

1. **Unguarded `contract.trump` access in Sun?** None reachable.
   The ones that look unguarded (`(contract.trump or "")` at
   `Bot.lua:1670, 1699`) are deliberate — they coerce nil to ""
   so the `~=` comparison still excludes nothing in Sun (no suit
   equals ""), letting the meld-suit/bait-suit avoidance fire
   on any suit in Sun. Behaviorally correct.

2. **Sun trick resolution applying trump rank ordering?** No.
   `R.CurrentTrickWinner` only enters its trump pre-scan when
   `BID_HOKM`; in Sun, `trumpPlayed` stays false, eligibility
   reduces to lead-suit follow, and `C.TrickRank` returns
   `RANK_PLAIN` (Sun never indexes `RANK_TRUMP_HOKM`).

3. **Hokm score applying Sun ×2?** No. `mult = mult * MULT_SUN`
   is gated on `BID_SUN` at `Rules.lua:799`. Hokm path never
   touches it.

4. **PickBid Sun strength awarding trump bonuses?** No.
   `sunStrength` (Bot.lua:725) computes purely from rank-based
   honours (A=11, T=10, K=4, Q=3, J=2) and AKQ stoppers.
   No reference to `contract.trump` (no contract argument at
   all). The Hokm-trump bonus in `PickDouble` (line 2968) is
   inside a `contract.type == K.BID_HOKM` block.

## 3 bullets
- All `contract.type == BID_HOKM` and `BID_SUN` gates surveyed
  match their intended scope; no inverted polarities found.
- `Cards.lua` low-level rank/value/IsTrump primitives short-
  circuit cleanly to plain ranks in Sun, so even if a higher
  layer forgot to gate, trump-rank ordering cannot leak.
- The only mildly fragile pattern is the `(contract.trump or "")`
  guard idiom — works because no real suit equals "", but a
  future programmer adding a "" suit constant would silently
  break it. Worth a code-review note, not a bug.
