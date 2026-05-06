# 12 — Touching-Honors Family (Section 6 rules 1-4)

**Commit:** 9c32c50 (v0.9.0)
**Files:** `Bot.lua` (WRITE site), `BotMaster.lua` (READ site)
**Verdict:** **PARTIAL-WIRED — NameError bug; ledger always empty**

## 1. Ledger declaration

`Bot.lua:217-219` — `emptyStyle().topTouchSignal = { S = {}, H = {}, D = {}, C = {} }`. Per-suit subtable holds `{nextDown="K|Q|J"}` or `{broke=true}`. Persisted via M4 fix.

## 2. WRITE site (Bot.OnPlayObserved, lines 442-472)

```
if not wasIllegal and contract and trick and trick.plays
   and #trick.plays >= 2 and style.topTouchSignal then
    local lead = trick.plays[1]
    ...
```

**CRITICAL BUG:** the variable `trick` is **never declared** in `Bot.OnPlayObserved`. The function declares `local trickPlays = (S.s.trick and S.s.trick.plays) or {}` at line 396 but no `local trick`. Grep confirms only `local trick = S.s.trick` at line 3053 (different function, `pickFollow`). Thus `trick` resolves to a global lookup → `nil`, the entire `if` predicate short-circuits to false, and **the WRITE branch never executes**. `topTouchSignal` ledger remains permanently empty `{}` per suit.

Inside the dead branch the predicate logic itself is sound:
- `lead.seat == R.Partner(seat)` — partner-of-follower led
- `C.Suit(lead.card)==cardSuit and C.Rank(lead.card)=="A"` — lead was Ace of follower's suit
- AKA equivalence via `S.s.akaCalled.seat == R.Partner(seat)`
- Rank dispatch: T→K, K→Q, Q→J, 7|8→broke

## 3. READ site (BotMaster.lua:445-472)

```
if style and style.topTouchSignal then
    for suit, entry in pairs(style.topTouchSignal) do
        if entry.nextDown then
            local card = entry.nextDown .. suit
            desire[card] = math.max(desire[card] or 0, 60)
        end
        if entry.broke then
            for _, hi in ipairs({"A","T","K","Q","J"}) do
                desire[hi..suit] = nil
            end
        end
    end
end
```

Reader is structurally correct: weight 60 dominates standard bias values, broke clears all 5 high-card desires. Reader runs against the empty ledger so it's a no-op.

## 4. Multi-high-card edge

If lead=Ace, 2nd=T (partner-of-leader), 3rd=K (opp-of-leader, partner-of-2nd-seat-actually-no — partner of leader): Section 6 only signals when `lead.seat == R.Partner(seat)`. Seat 2 is partner of seat 4 (leader's partner), NOT partner of seat 1 (leader). So only the leader's partner — typically seat 3 — fires the WRITE. Subsequent followers would only fire if they too are partner of leader, which is impossible (one partner per seat). **WRITE fires at most ONCE per trick** (correct). Were the bug fixed.

## 5. INVERSE (broke) edge

7/8 → `entry.broke = true`. Reader's loop clears `A/T/K/Q/J` desires of that suit for the seat. Note: rule 4 doesn't clear `nextDown` if previously set; if seat played T (→nextDown=K) earlier in round, then later played 7 in same suit, both flags coexist and reader pins K AND clears K (nil) — order-dependent in the for-loop. Minor inconsistency masked by the larger NameError bug.

## 6. Regression test

**NONE.** `git show 9c32c50 -- tests/test_rules.lua` only touches the M5 belote-cancellation test. No test file added for `topTouchSignal`. The 330/330 claim does not exercise this code path — explains why the NameError went unnoticed.
