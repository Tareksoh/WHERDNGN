# 19 — Section 6 (AKA / signaling) re-audit at v0.9.0 (9c32c50)

**Verdict:** **CONFIRM-bug.** Re-audit reproduces every finding in 12_touching_honors.md, plus surveys the rest of Section 6.

## 1. Touching-honors WRITE site, Bot.lua:442-472

```lua
if not wasIllegal and contract and trick and trick.plays
   and #trick.plays >= 2 and style.topTouchSignal then
    local lead = trick.plays[1]
    ...
```

`Bot.OnPlayObserved` is `function ... at line 313`, ends at line 572. Inside that scope:

- Only relevant local at `Bot.lua:396`: `local trickPlays = (S.s.trick and S.s.trick.plays) or {}`. There is **no `local trick`** anywhere in 313-572.
- Grep across Bot.lua: only `local trick = ...` is at line 3053 (`pickFollow`, different function).

So `trick` at line 442 is a **global lookup → `nil`**. The `and`-chain short-circuits at `... and trick and ...` BEFORE `trick.plays` is dereferenced. **Silent no-op**, not a crash. `style.topTouchSignal` ledger remains `{}` per suit forever.

`BotMaster.lua:445` reader is structurally correct but operates on the empty ledger → unconditional no-op. Confirms 12_touching_honors finding.

## 2. Other Section 6 rules

- **Implicit-AKA on bare-Ace lead** (S6-6): WIRED at `Bot.lua:2289-2305` (`pickFollow`). `lead.seat == R.Partner(seat)`, `Rank=A`, `Suit=trick.leadSuit`, `partnerWinning`, `not explicitAKA`. Correct.
- **AKA-verbal-required**: `Bot.PickAKA` at 2960 only fires from `LocalAKA`/wire; receiver only honors `S.s.akaCalled` (explicit) OR bare-Ace lead (implicit). Silent high-card play does NOT confer relief. Correct.
- **PickAKA preconditions**: (a) HOKM 2962, (b) suit≠trump 2981, (c) rank≠"A" 2988, (d) highest unplayed 2991, (e) lead+0 plays 2963 — all wired. **(f) partner-void-trump check: NOT WIRED** at v0.9.0 (added later in v0.9.1 commit 83717be). **(g) round-stage / scoreUrgency / confidence: NOT WIRED**, only a coarse `trickNum<=1` skip at 3003. Confirms doc claim.
- **AKA receiver in pickFollow**: explicit (`S.s.akaCalled.seat==Partner`, suit match) AND implicit (bare-Ace lead + partnerWinning) at 2306-2318. Both cases functional.
- **Late-AKA L4 fix**: `Net.lua:2316-2322` early-returns when trick has plays OR turn≠localSeat OR turnKind≠"play". Turn-aware + lead-only gate intact. (See 10_l4_l6_fixes.md.)

## 3. Section 6 health

5 of 7 rule families wired; rules 1-4 (touching-honors) **DEAD** via NameError; precondition (f)+(g) gaps documented. No regression test for `topTouchSignal` so 330/330 pass is uninformative for this code path.
