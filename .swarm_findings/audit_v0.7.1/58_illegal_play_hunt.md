# 58 — Adversarial illegal-play hunt (v0.7.2 / HEAD)

**Verdict: CLEAN.** I could not construct a scenario in which `Bot.PickPlay` (or any picker) returns a card that `R.IsLegalPlay` would reject.

## Audit summary

`Bot.PickPlay` (Bot.lua:2885) builds `legal = legalPlaysFor(hand, trick, contract, seat)` (Bot.lua:1376) which calls `R.IsLegalPlay` once per card and only retains `ok=true`. It then dispatches to either `pickLead(legal, ...)` or `pickFollow(legal, ...)`. Every `return` statement in both pickers (and in the Saudi Master `BM.PickPlay` / `heuristicPick` mirror at BotMaster.lua:743/576) terminates with a value derived from the `legal` array, never from `hand` directly.

I enumerated all 25+ early returns in `pickFollow` and all 14+ early returns in `pickLead` and traced each candidate set:

- Every `pointCards[]`, `winners[]`, `nonWinners[]`, `discardable[]`, `withoutBelote[]`, `discards[]`, `safeBosses[]`, `nonTrumps[]`, `singletons[]`, `lowSingletons[]`, `fromShortest[]`, `fromLongest[]`, `fromPref[]`, `lowTrump[]`, `trumpWinners[]`, `trumpCandidates[]`, `bySuit[su]` is built by iterating `legal` (or for the AKA-receiver / sweep / bidder-trump branches, by filtering `legal`).
- The Bargiya / T-4 Tahreeb sender (Bot.lua:2378-2425) returns `c` and `hi` from `bySuit` which is built from `legal`.
- The Faranka exception (Bot.lua:2543-2569) returns from `pool` ⊂ `nonWinners` ⊂ `legal`.
- The Sun pos-4 Faranka cover (Bot.lua:2277) sets `cover` only from `legal`.
- The Sun rule-1B second-lowest re-entry (Bot.lua:2444-2458) iterates `legal`.
- The Tanfeer sender (Bot.lua:2758-2796) returns `lowestByRank(lows)` where `lows` ⊂ `legal`.

## Scenarios checked

1. **Hokm trump-led must-overcut** — `R.IsLegalPlay` (Rules.lua:117-138) excludes lower trumps from `legal`. AKA-receiver block (Bot.lua:2213) gates on `partnerWinning`; in trump-led + has-trump, IsLegalPlay forces `legal=trump-only` even when partner is winning (the partner-winning shortcut at Rules.lua:119 only relaxes overcut, not must-follow). `discards = non-trump ∩ legal = empty`, branch no-ops. **Clean.**
2. **Sun void** — Rules.lua:143 returns `true` for any card; `legal = hand`. Picker freely chooses. **Clean.**
3. **Partner-winning shortcut** — `pickFollow`'s partnerWinning branches (smother / Tahreeb sender / lowestByRank) all post-date legalPlaysFor and read from `legal`. The shortcut is pre-applied inside IsLegalPlay so legal is correctly broad. **Clean.**
4. **Tahreeb / Bargiya / smother** — all candidate sets filtered from `legal`. Smother feedSafe gate excludes Hokm-trump-led (which is the only case the v0.5.18 K/Q/J expansion could conflict with overcut, and IsLegalPlay already pruned). **Clean.**
5. **`legalPlaysFor` bypass** — `pickLead` and `pickFollow` are file-local. Only `Bot.PickPlay` calls them, always with the `legalPlaysFor`-built `legal`. `BM.PickPlay` independently rebuilds legal from `R.IsLegalPlay`. `Bot.PickSWA` returns boolean only. **No bypass found.**

## Three takeaways

- `legalPlaysFor` is the single funnel; both heuristic and ISMCTS paths re-derive `legal` from `R.IsLegalPlay`, and Saudi Master ISMCTS at BotMaster.lua:761 mirrors the contract identically.
- Every `pickFollow`/`pickLead` early return I traced sources its candidate from `legal` — no `hand`-direct returns, no `wouldWin`-only returns escape the filter.
- One previously-flagged risk (A-46 double `legalPlaysFor` for Saudi Master) is a perf concern, not a legality concern — both calls produce the same set.
