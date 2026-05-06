# B-Rules-10 — Nil-safety / boundary defensives in `Rules.lua`

**Version**: v0.10.2
**Track**: B (code, no modifications)
**Scope**: pure code-quality scan of `C:/CLAUDE/WHEREDNGN/Rules.lua` (953 lines)
**Date**: 2026-05-05
**Verdict**: 1 high (latent crash), 5 medium (silent corruption / wrong-answer), 6 low (cosmetic / tightening). No exploitable scoring bug found. The two real defensive holes are (a) `R.ScoreRound` with no top-level nil-guards on its inputs (every other R.* function has them) and (b) `R.IsValidSWA` recursion has no depth cap and one accept-and-degrade path on a malformed `trickState.plays = nil`.

---

## Reference map

| Symbol | Lines | Notes |
|---|---|---|
| `R.Partner`            | `Rules.lua:16-21`     | total function on `seat ∈ {1,2,3,4}`; falls off the end on bad input |
| `R.NextSeat`           | `Rules.lua:23`        | one-liner; uses `%` |
| `R.TeamOf`             | `Rules.lua:25-28`     | total function on `seat ∈ {1,2,3,4}`; defaults to "B" on bad input |
| `R.CurrentTrickWinner` | `Rules.lua:34-59`     | early-out on empty trick; assumes `contract` non-nil |
| `R.TrickWinner`        | `Rules.lua:62-64`     | thin alias |
| `R.TrickPoints`        | `Rules.lua:67-73`     | assumes `trick.plays` is iterable |
| `R.IsLegalPlay`        | `Rules.lua:89-210`    | 6-arg, 5th-arg `seat` mostly unguarded; trump pre-scan tolerates nil contract.trump |
| `R.DetectMelds`        | `Rules.lua:220-290`   | safe on empty `hand`; tolerates nil contract |
| `meldRank` / `bestMeld`| `Rules.lua:301-341`   | local; uses `B.Cards.TrickRank` re-binding for safety |
| `R.CompareMelds`       | `Rules.lua:343-353`   | uses `(meldsA or {})` defensively |
| `R.IsValidSWA`         | `Rules.lua:383-501`   | top-level guards; recursion bounded by card count, not stack frames |
| `R.SumMeldValue`       | `Rules.lua:503-507`   | tolerates nil list |
| `R.CanBel`             | `Rules.lua:523-561`   | full nil-guards on team/contract/cumulative |
| `R.CanOvercall`        | `Rules.lua:573-586`   | full nil-guards on seat/contract |
| `R.ResolveOvercall`    | `Rules.lua:611-643`   | top-level nil-guards; `d:sub(...)` without type check |
| `R.ScoreRound`         | `Rules.lua:661-953`   | NO top-level guards; trusts `contract`, `meldsByTeam`, `tricks` |

| Cross-call dependency | Reads |
|---|---|
| `C.Suit`, `C.Rank` (Cards.lua:87-93) | both return `card and card:sub(...)` — nil-safe |
| `C.IsValid` (Cards.lua:95-98) | type+length check then index |
| `C.IsTrump` (Cards.lua:125-128) | nil-safe via early-return |
| `C.TrickRank`, `C.PointValue` (Cards.lua:107-123) | both `or 0` defaults on lookup miss |
| `K.RANK_INDEX` | strict-keyed table, missing rank → nil |

| Prior audits referenced |
|---|
| `audit_v0.7.1/30_islegal_edges.md` (R.IsLegalPlay edges; #6 contract.trump fragility) |
| `audit_v0.7.1/61_contract_confusion_hunt.md` (Hokm/Sun gates clean) |
| `audit_v0.7.1/71_nil_hand_hunt.md` (no crash paths in pickers; sparse-array bug) |
| `audit_v0.7.1/29_canbel_divergence.md` (CanBel pre-fix; v0.10.0 R1 unified rule) |
| `review_v0.10.2/_track_B_code/B-Rules-04_isValidSWA.md` (recursion bound F3 confirmed) |

---

## Findings

### F1 — `R.ScoreRound` has zero top-level nil-guards (HIGH)

**Severity: HIGH** — easiest crash path in the file. Every other R.* function defensively gates its inputs (`R.CanBel:524`, `R.CanOvercall:574`, `R.IsValidSWA:384`, `R.ResolveOvercall:612`). `R.ScoreRound` does not.

**Lines**: `Rules.lua:683` opens the function; first index of `contract` happens at `Rules.lua:694` (`(contract.type == K.BID_SUN) and ...`). First index of `meldsByTeam` happens at `Rules.lua:680` (`R.SumMeldValue(meldsByTeam.A)`).

**Crash modes**:
- `contract == nil` → `Rules.lua:694` `contract.type` indexes nil → "attempt to index a nil value" runtime error.
- `meldsByTeam == nil` → `Rules.lua:680` indexes nil at `.A` → same error. `R.SumMeldValue` itself is safe (`Rules.lua:503-507` uses `(list or {})`), but the caller code at L680/681 does `meldsByTeam.A` BEFORE the SumMeldValue call.
- `tricks == nil` → `Rules.lua:685` `for i, t in ipairs(tricks) do` would error on a non-table (Lua 5.1 `ipairs` raises if `tricks` is nil; under Lua 5.5 with an `__ipairs` metamethod absent it silently iterates 0 times).
- A `tricks[i]` element with `t.winner == nil` → `R.TeamOf(nil)` returns "B" silently (the seat-helper fallthrough at `Rules.lua:25-28` defaults to "B" if seat is not 1/3) → **silently miscredits the trick to team B**.
- A `tricks[i].plays == nil` → `R.TrickPoints` at `Rules.lua:69` does `for _, p in ipairs(t.plays)` → ipairs on nil → crash.

**Caller protection**: `State.lua:1922-1924` does check `s.contract` non-nil before invoking, and `BotMaster.lua:793` runs inside the rollout pcall. The host live path (`Net.lua:3038`) has no upstream contract-nil guard at the call site itself. Bot rollouts shield the caller via the outer pcall at `BotMaster.lua` (per `audit_v0.7.1/71_nil_hand_hunt.md` cross-cutting note 1), so the practical exposure is the live `Net.lua:3038` path during a phase-corruption resync.

**Recommended hardening pattern** (to mirror the file's other functions):
```lua
function R.ScoreRound(tricks, contract, meldsByTeam)
    if not tricks or not contract or not meldsByTeam then return nil end
    -- … existing body …
end
```

This brings `R.ScoreRound` in line with the file's prevailing defensive discipline.

---

### F2 — `R.TeamOf(nil)` silently returns `"B"` (MEDIUM)

**Severity: MEDIUM** — silent miscredit, no crash. Combined with F1's missing `t.winner` guard, an empty/corrupt winner field becomes 8 phantom team-B trick wins.

**Lines**: `Rules.lua:25-28`:
```lua
function R.TeamOf(seat)
    if seat == 1 or seat == 3 then return "A" end
    return "B"
end
```

For `seat == nil`, `seat == 2`, `seat == 4`, `seat == "potato"`, `seat == 0`, `seat == 5` — all return `"B"`. The function lacks a "guard against bad input" branch.

This is exploitable as a silent corruption vector (per `audit_v0.7.1/71_nil_hand_hunt.md` cross-cut #6: hand-edited SavedVariables protection). A SavedVariables corruption setting `s.tricks[i].winner = nil` would attribute every such trick to team B during the next score reconciliation. No crash, no log line. **Look at the file again on a /reload after a CLEU-blocked phase**: every trick whose winner field didn't survive the round-trip becomes a B-credit.

**Recommended**: tighten to
```lua
function R.TeamOf(seat)
    if seat == 1 or seat == 3 then return "A"
    elseif seat == 2 or seat == 4 then return "B"
    else return nil end
end
```
and have `R.ScoreRound` propagate the nil to a `result.malformed = true` flag rather than silently scoring.

---

### F3 — `R.Partner` falls off the end on bad input (MEDIUM)

**Severity: MEDIUM** — silent nil propagation.

**Lines**: `Rules.lua:16-21`:
```lua
function R.Partner(seat)
    if seat == 1 then return 3
    elseif seat == 2 then return 4
    elseif seat == 3 then return 1
    elseif seat == 4 then return 2 end
end
```

No final `else`; for `seat == nil` or any other input, the function returns `nil`. Most callers tolerate this (they compare `R.Partner(seat) == curWinner`, which is just false on nil). But three sites use the result as a table key:

- `Rules.lua:139` `if curWinner and seat and R.Partner(seat) == curWinner then return true` — nil propagation handled by the upstream `seat and` guard.
- `Rules.lua:117` `seat and R.Partner(seat) == akaCalled.seat` — same, guarded.
- `Bot.lua` partner-coordination paths use `R.Partner(seat)` to index `S.s.hands[partner]` — these paths assume non-nil and would crash on bad input.

The `Rules.lua` callers are guarded; the Bot.lua / BotMaster.lua callers (out of scope here) inherit the foot-gun. Mark as MEDIUM because the function ought to be total or explicitly partial.

**Recommended**: append `return nil` after the final branch to make the partial nature explicit (currently it's implicit Lua "no return = nil" semantics — readers may miss it).

---

### F4 — `R.IsValidSWA` recursion has no stack-depth cap (MEDIUM)

**Severity: MEDIUM** — Lua 5.1 default stack is 200 frames; the validator tail-recurses through the trick-resolution boundary at `Rules.lua:401` and the recursive descent at `Rules.lua:496`.

**Lines**: `Rules.lua:401-404` (post-trick recursion) + `Rules.lua:494-499` (per-legal-play recursion).

**Worst-case depth**: a round-1 SWA at trick-1 has 8 cards × 4 seats = 32 plays = 8 trick-resolution recursions × 4 per-trick recursions = ~32 frames, each with a per-legal-play recursion that itself goes down to the next play. Total recursive depth ≈ 32 + branching at each. Stack frames per recursive call ≈ 1; with `applyMove` non-tail (it returns multiple values that get bound to local names at L495), the compiler can't tail-call optimize.

**Reality check**: The B-Rules-04 audit at F3 says "all paths terminate" and the prior `audit_v0.7.1/50_v0.5.17_swa.md` agrees. The branching factor is bounded (≤8 per node, typically ≤4-5 after legal-play filter). **Adversarial worst case**: if a hand-edited save passes a 32-card all-legal-everywhere state, ~8! ≈ 40K nodes × 32 frames = manageable on 200 frames? No — node count doesn't equal stack depth. **The recursive descent depth is bounded by the number of plays remaining**, which is ≤32. So 32 frames + a small constant for the helpers. Lua 5.1's 200-frame limit is comfortable.

**But** there's no explicit guard. If a future change widens the recursion (e.g. adding a "what-if-partner-cooperates" branch reintroduces the v0.5.16 cooperative path) the bound could be subtly broken. Mark MEDIUM only because it's a latent risk — under the v0.10.2 codebase the depth is fine.

**Recommended**: Add an explicit `local function rec(seat, hands, ts, depth) if depth > 64 then return false end ...` shape so any future nesting is bounded by construction.

---

### F5 — `R.ResolveOvercall`'s `d:sub(...)` will crash on non-string decisions (MEDIUM)

**Severity: MEDIUM** — type-coercion hole.

**Lines**: `Rules.lua:629-630`:
```lua
elseif d and d:sub(1, 10) == "TAKE_HOKM_" then
    local suit = d:sub(11, 11)
```

The `d and d:sub(...)` pattern is a string-method call. `d` is read from `decisions[s]` which is unsanitized. If a malformed hand-edited save (per `audit_v0.7.1/71_nil_hand_hunt.md` cross-cut: SavedVariables protection) injects `decisions = { [3] = 42 }`, then `d = 42`, `d` truthy, then `d:sub(1, 10)` calls `string.sub` on a number — **Lua 5.1: error "attempt to index a number value"; Lua 5.5: same** (numbers do not auto-coerce to strings for the colon-method syntax in 5.1 — the metatable lookup fails).

Under WoW's Lua 5.1 runtime this is a hard crash inside the host overcall resolver. The fact that all live callers (`Net.lua` overcall path) only ever assign strings to the decisions table means the crash is unreachable in practice — but a hand-edited `WHEREDNGNDB.swaRequest.decisions` survival entry, or any future code path that passes a number/boolean, would trip it.

**Recommended**: Add `type(d) == "string"` to the branch:
```lua
elseif type(d) == "string" and d:sub(1, 10) == "TAKE_HOKM_" then
```

**Side note**: line 627 (`if d == "TAKE" then`) is type-safe — `==` doesn't crash on a number.

---

### F6 — `R.IsLegalPlay` doesn't validate `seat` is in 1..4 (MEDIUM)

**Severity: MEDIUM** — interacts with F2/F3.

**Lines**: `Rules.lua:89` (signature) + `Rules.lua:117, 139, 167` (uses `seat`).

The function reads `seat` only to compute `R.Partner(seat) == curWinner`. If `seat` is nil, the upstream `and seat and` guards short-circuit (lines 117, 139). If `seat` is a non-1..4 number, `R.Partner(seat)` returns nil (per F3) and the comparisons are false → the partner-winning shortcut never fires → the must-trump / overcut / follow-suit logic still runs correctly. So the function is NOT crashable on bad seat, but it silently ignores partner-ish corruption.

The asymmetry with `R.IsValidSWA` (which tightly checks `if not callerSeat then return false`) is jarring. If a malformed live state has `S.s.turn` corrupted to a non-1..4 value, `R.IsLegalPlay` will give the wrong answer (no partner-winning relief) without any indication.

**Recommended**: add an early-out
```lua
if seat ~= 1 and seat ~= 2 and seat ~= 3 and seat ~= 4 then
    return false, "bad seat"
end
```
or document that callers must pre-validate.

---

### F7 — Saudi card-rank string-symbol comparison: `C.Rank(c)` may return nil → silent miscompare (MEDIUM)

**Severity: MEDIUM** — depends on `C.IsValid` having been called upstream.

**Lines**: `Rules.lua:228` `local idx = K.RANK_INDEX[C.Rank(c)]` + `Rules.lua:269-271` (byRank tally) + `Rules.lua:699-700` (Belote scan).

The pattern: `C.Rank(c)` returns nil if `c` is nil (`Cards.lua:87-89`: `card and card:sub(1, 1) or nil`). For `c = ""`, `C.Rank("")` returns `""` (empty string, not nil — `"":sub(1, 1) == ""`). For `c = "A"` (length 1), `C.Rank("A")` returns `"A"`. For `c = 42`, `C.Rank(42)` errors at `card:sub(...)` because numbers can't be indexed (no metatable).

**In `R.DetectMelds:228`**: the `if s and idx then` guard at L229 catches nil-rank silently — the malformed card is dropped without a warning. This is the "sparse hand" silent-corruption category from `audit_v0.7.1/71_nil_hand_hunt.md` cross-cut.

**In `R.ScoreRound:699-700`** (Belote scan):
```lua
if C.Suit(p.card) == contract.trump then
    if C.Rank(p.card) == "K" then kWho = p.seat end
    if C.Rank(p.card) == "Q" then qWho = p.seat end
end
```
If `p.card == nil`, `C.Suit(nil)` returns nil, `nil == contract.trump` is false → block skipped. Safe.
If `p.card == "K"` (length 1), `C.Suit("K")` returns `""` (length-0 suffix), `"" == contract.trump` is false → block skipped. Safe.
If `p.card == "Kh"` (lowercase suit), `C.Suit("Kh")` returns `"h"`, comparison with `"H"` fails → silent miscredit (Belote not detected).

The code is robust against most corruption modes. **Lowercase-suit silent failure** is the only real risk and it's exotic (no caller produces lowercase). LOW-MEDIUM.

**In `R.IsLegalPlay`'s `C.Rank == "A"` check at L580 (overcall ace-blocking)**: same pattern — if `bidCard` is nil-or-malformed, the comparison silently misfires. The function is documented to handle nil bidCard (`bidCard and ...` at L579), so it's safe.

---

### F8 — `or 0` defaults assume 0 is a valid trick rank, but `K.RANK_*` tables start at 1 (LOW)

**Severity: LOW** — cosmetic, but a precondition violation that masks bugs.

**Lines**: `Cards.lua:111-122` — `return K.RANK_TRUMP_HOKM[r] or 0` and `K.RANK_PLAIN[r] or 0`. Plus `Rules.lua:55, 146, 191, 207` — `local highest = -1` initialization for trick ranks.

The trick-rank table values start at 1 (`K.RANK_PLAIN["7"] = 1`, `K.RANK_TRUMP_HOKM["7"] = 1`). A nil-key fallback to 0 means a malformed card gets a TrickRank of 0, which is *strictly less than* any real card's rank.

**In `R.CurrentTrickWinner:55`**: `if rk > bestRank then bestRank, bestSeat = rk, p.seat end`. With `bestRank = -1` initially, a card with rk = 0 would still update bestSeat. **But** the initial bestRank starts at `-1`, so the first eligible card sets bestRank to its actual rank or 0. If the first card is malformed (rank 0), bestSeat still gets set to that seat. Subsequent eligible cards with rk > 0 will overwrite. **Result**: a trick where every play is malformed (rank 0) would be won by the FIRST malformed seat. Inconsequential because (a) `C.IsValid` should've blocked the play, (b) the trick winner of an all-malformed trick is meaningless anyway.

**In `R.IsLegalPlay:146-147` and L188-191**: `local highest = -1` then `if rk > highest then highest = rk end`. A malformed-but-trump card would set highest = 0; subsequent overcut comparison `C.TrickRank(c, contract) > highest` is `>= 1 > 0` → true → overcut considered satisfiable. **Slightly wrong** but only triggered by an upstream invariant violation (a card was admitted as "trump" but yields rank 0).

**Verdict**: 0 is a sane fallback because the comparison logic uses `> highest` strictly. Not a bug; mark for code-readability. The `-1` init matches a "no card seen yet" sentinel; if it were 0 the must-overcut logic would behave subtly differently when no trump was played (it does anyway thanks to L194 `if highestTrumpRank < 0 then return true`).

---

### F9 — `meldRank` synthesizes a probe card from `m.top .. probeSuit` without validating either field (LOW)

**Severity: LOW** — works, but easy to break in a future edit.

**Lines**: `Rules.lua:301-321`:
```lua
local probeSuit = (contract.type == K.BID_HOKM
                   and contract.trump) or "S"
local rk = (B.Cards and B.Cards.TrickRank
           and B.Cards.TrickRank(m.top .. probeSuit, contract))
           or (K.RANK_INDEX[m.top] or 0)
```

If `m.top == nil`, then `m.top .. probeSuit` raises "attempt to concatenate a nil value". The `B.Cards and B.Cards.TrickRank and ...` guard does NOT save you — it's evaluated at the call site, but the concatenation runs as an argument to TrickRank before the function returns. **Crash risk if `m.top == nil`.**

In practice, every meld emitted by `R.DetectMelds` sets `m.top` (lines 247, 284). So under normal flow, this code is unreachable in a crashable state. But the function is a prime candidate for a hand-edited save trip-wire (per cross-cut #6).

**The fallback `(K.RANK_INDEX[m.top] or 0)` is also nil-unsafe**: `K.RANK_INDEX[nil]` raises in Lua 5.1 ("table index is nil"). The chain is: try concatenation (crash on nil top), try table lookup (crash on nil top). Both fail-stops on the same condition.

**Recommended**: gate the function with `if not m.top then return 1000 + (m.value or 0) end` (skip the rank-bonus when top is missing).

---

### F10 — `R.CanBel` uses `(cumulative and cumulative[team]) or 0` — works only when 0 is a sane absent-team default (LOW)

**Severity: LOW** — actually correct, but worth pinning the assumption.

**Lines**: `Rules.lua:555-559`:
```lua
local mine     = (cumulative and cumulative[team]) or 0
local otherTeam = (team == "A") and "B" or "A"
local otherCum  = (cumulative and cumulative[otherTeam]) or 0
if mine     >  K.SUN_BEL_CUMULATIVE_GATE then return false end
if otherCum <= K.SUN_BEL_CUMULATIVE_GATE then return false end
```

The `or 0` default fires when `cumulative` is nil OR `cumulative[team]` is nil. The `if otherCum <= 100 then return false` clause means **if no team has crossed**, return false (no Bel allowed yet). For mine = 0 (caller hasn't crossed), the first check passes (0 ≤ 100). For otherCum = 0 (other side also at 0), the second check fires → return false. So `cumulative = nil` correctly forbids Bel.

**The subtlety**: if `cumulative = { A = 50 }` (B missing entirely), then for `team = "A"`, mine = 50, otherCum = 0 → no opposite cross → return false. For `team = "B"`, mine = 0, otherCum = 50 → no opposite cross (50 ≤ 100) → return false. Both safe.

**The hidden assumption**: NEGATIVE cumulative scores. If the cumulative table contains negatives (penalty went underflow somewhere), `(cumulative[team]) or 0` returns the negative. Then `mine > 100` is false (negative is less). Then `otherCum <= 100` returns false → no Bel. So negatives are still safe.

**Verdict**: the `or 0` default is the right call here. Mark as a documented invariant: "negative cumulative is treated as 'team hasn't crossed gate'." LOW.

---

### F11 — `R.IsValidSWA` accepts `trickState.plays = nil` and silently degrades to `plays = {}` (LOW)

**Severity: LOW** — already documented in `B-Rules-04_isValidSWA.md` F4; restated for completeness.

**Lines**: `Rules.lua:387` `local plays = trickState.plays or {}`.

If a top-level caller passes `{ leadSuit = "H", leader = 2 }` (no `plays` field), the validator synthesizes `plays = {}` and treats this as the START of the next trick — even if the leadSuit/leader fields would normally indicate a mid-trick state. This is silent acceptance of a malformed input rather than a rejection.

In practice, `Net.lua:2902-2904` and `Bot.lua:3882-3884` always provide `plays` (per B-Rules-04 F4). Tests at `tests/test_rules.lua:875` pass `{ plays = {}, leader = 1 }` explicitly.

**Recommended**: add a "either both present or both absent" check:
```lua
if trickState.leadSuit and not trickState.plays then return false end
```
or, even simpler, document the synthesis rule explicitly (already done at L385 comment).

---

### F12 — `R.CompareMelds` returns "tie" on `(nil, nil, contract)` rather than nil/error (LOW)

**Severity: LOW** — by design, kept for completeness.

**Lines**: `Rules.lua:344-353`:
```lua
local bA = bestMeld(meldsA or {}, contract)
local bB = bestMeld(meldsB or {}, contract)
if not bA and not bB then return "tie" end
```

The `(meldsA or {})` makes nil melds equivalent to empty. The "tie" return is consumed by `R.ScoreRound:760` (the fail/take meld-attribution computation). For both teams empty, both get 0 effective melds → no flip on the threshold check → bidder fails. This is correct behavior and matches the v0.10.0 R5 fix lineage.

**Cosmetic note**: this is the only function in the file that returns string literals `"A"`, `"B"`, `"tie"` rather than booleans. Code-readability LOW only.

---

### F13 — Lua 5.1 `math.floor` on negative numbers + `(x + 5) / 10` (LOW)

**Severity: LOW** — confirmed not a concern.

**Lines**: `Rules.lua:918` `local function div10(x) return math.floor((x + 5) / 10) end`.

`R.ScoreRound`'s raw scores are always `>= 0` because `cardA`, `cardB`, `meldPoints.A`, `meldPoints.B` start at 0 and only get added to. The multiplier `mult` is always ≥ 1. The Belote +20 is only added, never subtracted. So `rawA, rawB >= 0` always.

`math.floor((x + 5) / 10)` for x ≥ 0 always rounds the half toward positive (5 rounds UP per video #43). Lua 5.1 vs 5.5 floor semantics agree for positive arguments. The "5 rounds UP" comment block at L915 documents the Saudi convention (changed from `(x+4)/10` in pre-v0.5.6).

**No cross-platform issue**. The `Rules.lua:236-237` sequence sort uses `<` strict — also no float concerns (idx values are integers from K.RANK_INDEX).

---

## Tests / coverage observations

The test file `tests/test_rules.lua` covers most positive paths and the v0.10.0 R1/R2 fixes. Defensive coverage gaps:

- **No test for `R.ScoreRound(nil, nil, nil)` or any subset thereof**. F1 above is uncovered.
- **No test for `R.TeamOf(nil)`**. F2 silent-miscredit is uncovered.
- **No test for `R.ResolveOvercall` with non-string decision values**. F5 crash is uncovered.
- **No test for `R.IsLegalPlay` with `seat = nil` or `seat = 5`**. F6 silent-degradation uncovered.
- Test N at L842-846 has the right idea (`R.CanBel(nil, ...)`, `R.CanBel("A", nil, ...)`) — extending this pattern to ScoreRound/IsLegalPlay would close most of the F1-F6 gaps.

The Section O SWA tests (4 cases) don't exercise stack-depth or recursion-bound concerns (F4); B-Rules-04 F11 already flagged this independently.

---

## Summary table

| # | Severity | Function | Issue | Crashable | Silent-corrupt |
|---|---|---|---|---|---|
| F1 | HIGH | `R.ScoreRound` | No top-level nil-guards on tricks/contract/meldsByTeam | YES | YES |
| F2 | MED | `R.TeamOf` | Returns "B" for any non-{1,3} input including nil | NO | YES |
| F3 | MED | `R.Partner` | Returns nil for non-{1,2,3,4} input; implicit fallthrough | NO | YES (consumers) |
| F4 | MED | `R.IsValidSWA` | No explicit recursion-depth cap (currently bounded by 32 plays, but coupling to data shape, not stack) | NO (in practice) | NO |
| F5 | MED | `R.ResolveOvercall` | `d:sub(...)` crashes on numeric/boolean decision values | YES | NO |
| F6 | MED | `R.IsLegalPlay` | Doesn't validate `seat` ∈ {1,2,3,4}; partner-relief silently fails on bad seat | NO | YES |
| F7 | MED-LOW | `R.DetectMelds` / `R.ScoreRound` | `C.Rank(c)` nil/empty returns get silently dropped from byRank/Belote scan | NO | YES (sparse hands) |
| F8 | LOW | `Cards.TrickRank` `or 0` | Fallback rank of 0 < real ranks (1..8); used in highest-rank loops | NO | NO (just unintuitive) |
| F9 | LOW | `meldRank` | `m.top .. probeSuit` crashes if `m.top == nil`; `K.RANK_INDEX[nil]` also crashes | YES (only on hand-edited save) | NO |
| F10 | LOW | `R.CanBel` | `or 0` default works for negative-cumulative edge case; assumption worth pinning | NO | NO |
| F11 | LOW | `R.IsValidSWA` | Silent acceptance of `trickState.plays = nil` | NO | LOW |
| F12 | LOW | `R.CompareMelds` | Returns string literals; "tie" on (nil,nil,contract) is by-design | NO | NO |
| F13 | LOW | `div10` | Confirmed math.floor on positive raw scores is cross-platform safe | NO | NO |

---

## Top-3 actionables (ranked by user-impact)

1. **Add the 3-line nil-guard to `R.ScoreRound`** (F1). Highest return-on-effort: aligns the function with the rest of the file and removes the only "live-callable, top-level, unguarded" entry point in `Rules.lua`. Net.lua:3038 is the host live invocation point and currently has no upstream contract-nil cross-check.

2. **Tighten `R.TeamOf` and `R.Partner` to be either total or explicitly partial** (F2, F3). Currently both fall off the end on bad input; F2's silent "B" default is the worst because it produces wrong-but-plausible results. A 1-line `else return nil` adds intent.

3. **Add `type(d) == "string"` to `R.ResolveOvercall`'s TAKE_HOKM_ branch** (F5). This is the only "live data could realistically be malformed" path that produces a hard crash rather than a silent fallback. Single-line fix.

---

## Confidence

- **HIGH** on F1 (direct read of L683 vs the rest of the file's defensive patterns; `Net.lua:3038` call-site verified).
- **HIGH** on F2, F3 (explicit code reads).
- **HIGH** on F4 (depth analysis cross-checked with B-Rules-04 F3).
- **HIGH** on F5 (Lua 5.1 string-method semantics).
- **MEDIUM** on F6 — the silent-degrade path is reachable in theory but no live caller is known to corrupt seat.
- **HIGH** on F7-F13 (direct reads, plus prior audits 30/61/71 corroborate).

No execution / harness was run; all conclusions are static reads of `Rules.lua`, `Cards.lua`, `Constants.lua`, plus call-site checks in `State.lua`, `Net.lua`, `BotMaster.lua`, `tests/test_rules.lua`, and the prior audit reports listed above. None of the F1-F13 findings produce a *scoring exploit* (no observed path that wrongly credits points to a team — the silent-corruption findings F2, F6, F7 produce wrong-but-symmetric drops, not asymmetric over-payment). The only true crash hazards are F1, F5, and F9, and only F1 is reachable from a normal live phase-corruption resync.
