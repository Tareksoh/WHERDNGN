# B-State-05: `R.ScoreRound` deep audit (v0.10.2)

## Scope

- `Rules.lua:661-952` — `R.ScoreRound` full body
- `Rules.lua:67-73` — `R.TrickPoints`
- `Rules.lua:343-353` — `R.CompareMelds` (calls `bestMeld` / `meldRank` at `Rules.lua:301-341`)
- `Rules.lua:503-507` — `R.SumMeldValue`
- `Rules.lua:220-290` — `R.DetectMelds` (Carré-A branch at 273-287)
- `Constants.lua:53-115` — `K.LAST_TRICK_BONUS`, `K.HAND_TOTAL_*`, `K.MULT_*`, `K.MELD_*`, `K.AL_KABOOT_*`, `K.CARRE_RANKS`
- `State.lua:1149-1189` — `S.ApplyMeld` (corroborates D-RT-06 finding that `meldsByTeam` ≠ `R.DetectMelds` output)

## Verdict

The math pipeline (trick aggregation → outcome dispatch → multiplier → belote add → div10) is canonically correct. The function correctly applies v0.10.0 R2 (Sun-multiplier collapse), v0.10.0 R5 (Carré-A in Sun = 400 raw direct), v0.9.0 M5 (team-level belote cancellation), and v0.10.0 R2 (Sun tied-target inversion ignores stale Triple/Four/Gahwa).

Defects cluster at the edges:

- **F-01 (HIGH)** Reverse Al-Kaboot (+88) is unwired — D-RT-04 F12 / Source G corroboration is unactioned in code.
- **F-02 (HIGH)** Match-win Gahwa branch (line 928) is type-blind — a stale `gahwa=true` on a Sun contract still triggers `gahwaWonGame=true` despite the multiplier path correctly collapsing it.
- **F-03 (MEDIUM)** Belote sweep override + cancellation order can resurrect a previously-cancelled belote on the sweeping team.
- **F-04 (MEDIUM)** `meldsByTeam` is built by `S.ApplyMeld` (which DROPS Hokm 4-Aces because no value is set — D-RT-06), not by `R.DetectMelds`. So the v0.10.0 X5 fix at `Rules.lua:273-287` does NOT propagate into `R.ScoreRound`'s `meldA` / `meldB` / `meldVerdict` / `effMeld*`. Carré-A in Hokm scores 0 in scoring but counts in some inferred bot logic — divergence.
- **F-05 (MEDIUM)** `R.TeamOf(nil)` returns "B" at `Rules.lua:25-28` — `contract.bidder = nil` mis-attributes silently. No defensive guard at line 677.
- **F-06 (LOW)** Sweep-then-cancellation comment (lines 716-722) routes belote to sweeper but the loser-team's 100-meld is the canonical cancellation predicate — comment has the right idea but cancellation logic uses post-override team.
- **F-07 (LOW)** Failed-Gahwa raw-scoring path: when `outcome_kind == "fail"` and `contract.gahwa == true`, the code awards `handTotal × MULT_FOUR` to defenders THEN sets `gahwaWonGame=true` with `gahwaWinner=oppTeam`. Both consumers of the result (per-round delta + match-win flag) fire, doubling the impact. Whether this is intended (match-win short-circuits anyway) is unclear from the inline comment.
- **F-08 (LOW)** Trick-1-leader inference for Reverse Al-Kaboot would require `tricks[1].plays[1].seat`; the function does not currently snapshot this.
- **F-09 (LOW)** `multiplier` field of return struct is post-collapse (Sun-Triple collapsed → ×2) but `result.bidderMade` doesn't expose `outcome_kind` — callers can't distinguish "make" from "doubled-tie inversion (take)" without the `multiplier`/`raw` cross-check.

---

## Findings

### F-01 — Reverse Al-Kaboot (+88) UNWIRED (HIGH severity)

**File:** `Rules.lua:711-723, 817-822`.

**Issue:** Per D-RT-04 F12 / Source G corroborated, when defenders sweep all 8 tricks AND the bidder led trick 1, defenders should earn the Reverse Al-Kaboot bonus (raw +88, distinct from regular Al-Kaboot 250/220). The current sweep branch at `Rules.lua:817-822`:

```lua
if sweepTeam then
    local bonus = (contract.type == K.BID_HOKM) and K.AL_KABOOT_HOKM or K.AL_KABOOT_SUN
    cardA = (sweepTeam == "A") and bonus or 0
    cardB = (sweepTeam == "B") and bonus or 0
    meldPoints.A = (sweepTeam == "A") and meldA or 0
    meldPoints.B = (sweepTeam == "B") and meldB or 0
```

unconditionally awards 250/220 to whichever team swept. There's no:
- Bidder-vs-defender distinction on the sweepTeam.
- Trick-1-leader check.
- `K.AL_KABOOT_REVERSE` constant.

**Repro:**
1. Hokm-S, bidder is seat 1 (team A). Seat 1 leads trick 1.
2. Defenders (team B) win all 8 tricks.
3. Current: `sweepTeam = "B"`, `bonus = 250`, `cardB = 250`, `mult = 1` (Hokm undoubled).
4. `rawB = (250 + 0) × 1 + 0 (belote A) = 250`. Final B = 25 gp.
5. Expected per D-RT-04 F12: `rawB = 88` (or 88 + something, depending on which Reverse-Kaboot interpretation: video #16 disputes this internally — "88" vs "treat as regular Kaboot").

**Code quote:**
```lua
-- Al-kaboot: one team won all 8 tricks. Replaces normal scoring.
local sweepTeam
if trickCount.A == 8 then sweepTeam = "A"
elseif trickCount.B == 8 then sweepTeam = "B" end
```
(Rules.lua:712-714) — no defender-vs-bidder check here.

**Severity:** HIGH. The current code over-pays defender-sweep by ~162 raw vs. the 88-interpretation, or over-pays by 0 vs. the equivalent-to-regular interpretation. Either way, it doesn't even attempt the differentiation and silently picks one branch.

**Recommendation:** Either wire it (add `K.AL_KABOOT_REVERSE = 88`, predicate on `sweepTeam ~= bidderTeam and tricks[1].plays[1].seat == contract.bidder`) OR add an explicit comment near `sweepTeam` block noting the unwired status. Track-A noted single-source dispute; the v0.10.2 reaudit should escalate to "wire-with-test-coverage" or "explicitly-decline-with-comment".

---

### F-02 — Gahwa match-win branch is type-blind (HIGH severity)

**File:** `Rules.lua:920-937`.

**Issue:** v0.10.0 R2 added defensive Sun-flag collapse at the multiplier site (lines 884-887: "intentionally ignore tripled/foured/gahwa on Sun"). But the Gahwa match-win branch at lines 920-937 does not collapse `contract.gahwa` against `contract.type == K.BID_SUN`. A stale `gahwa = true` on a Sun contract triggers `gahwaWonGame = true`, signaling the network layer (`Net.lua` HostStepAfterTrick per docstring at line 924) to award a match-win on a contract that should not even support Gahwa.

**Code quote:**
```lua
local gahwaWonGame = false
local gahwaWinner
if contract.gahwa then
    -- Caller's team = bidder team. They "win" if bidderMade
    -- (made or doubled-tie inversion), "lose" otherwise.
    if bidderMade then
        gahwaWinner = bidderTeam
    else
        gahwaWinner = oppTeam
    end
    gahwaWonGame = true
end
```
(Rules.lua:926-937)

Compare to the multiplier path (Rules.lua:884-893):
```lua
local mult = K.MULT_BASE
if contract.type == K.BID_SUN then
    mult = mult * K.MULT_SUN
    if contract.doubled then mult = mult * K.MULT_BEL end
    -- intentionally ignore tripled/foured/gahwa on Sun
else
    if     contract.gahwa   then mult = mult * K.MULT_FOUR  -- ×4 baseline
    elseif contract.foured  then mult = mult * K.MULT_FOUR
    elseif contract.tripled then mult = mult * K.MULT_TRIPLE
    elseif contract.doubled then mult = mult * K.MULT_BEL end
end
```

The asymmetry: multiplier-side collapses `tripled/foured/gahwa` for Sun; match-win-side does not. A Sun-with-stale-gahwa contract is silently treated as a match-deciding round.

**Repro:**
1. Hand-edit `s.contract = { type=K.BID_SUN, doubled=true, gahwa=true, bidder=1, ... }` (e.g., from a stale resync where Gahwa was set during a Hokm contract that got re-bid as Sun via takweesh).
2. Score round: `mult = 1 × 2 (Sun) × 2 (Bel) = 4` — correctly ignores `gahwa`.
3. But `gahwaWonGame = true` and `gahwaWinner = bidderTeam` (or oppTeam).
4. Net.lua treats the round as match-deciding → entire game ends.

**Severity:** HIGH. Defensive normalization that's correctly applied in one place but not its mirror. Same source-of-bug class as the v0.10.0 R2 audit-fix that was already shipped.

**Recommendation:** Mirror the multiplier-path collapse:
```lua
if contract.gahwa and contract.type ~= K.BID_SUN then
    ...
    gahwaWonGame = true
end
```

Add Section L test that pins Sun-stale-gahwa: `gahwaWonGame == false`, `multiplier == 4`.

---

### F-03 — Sweep override + Belote cancellation order resurrects cancelled Belote (MEDIUM severity)

**File:** `Rules.lua:721-746`.

**Issue:** Sequence:

```lua
-- step 1: detect K+Q same hand → belote = R.TeamOf(kWho)
...
-- step 2: sweep override
if sweepTeam and belote and belote ~= sweepTeam then
    belote = sweepTeam
end
...
-- step 3: cancellation against post-override team's melds
if belote and kWho then
    local list = (meldsByTeam and meldsByTeam[belote]) or {}
    for _, m in ipairs(list) do
        if (m.value or 0) >= 100 then
            belote = nil
            break
        end
    end
end
```
(Rules.lua:721-746)

The cancellation walks `meldsByTeam[belote]` AFTER `belote` was reassigned to the sweep winner. If the original K+Q holder (cancelled-by-100-meld) was on the loser side, but the sweep override moved `belote` to the winner side, cancellation now checks the winner's melds (not the holder's). Saudi convention per `B-Rules-02_scoreRound.md` F-01 (PDF 02 line 140 "ويلغى اذا كان معه مشروع المئة فقط") — Belote is cancelled because of a property of the original declaration (holder + 100-meld), not contingent on which team eventually receives the +20.

**Repro:**
1. Hokm-H. Seat 2 (team B) holds KH+QH+seq5-hearts (seq5 = 100 raw).
2. Per Saudi: B's belote is cancelled at meld declaration. +20 doesn't exist for the round.
3. Team A sweeps all 8 tricks. `meldsByTeam.A = {}` (no melds), `meldsByTeam.B = [{seq5, value=100}]`.
4. Code path: belote = "B" (step 1) → sweep override → belote = "A" (step 2) → cancellation checks `meldsByTeam.A` → empty → belote stands → A gets sweep + 20 raw.
5. Expected: belote was cancelled at declaration, A gets sweep + 0 raw.

**Severity:** MEDIUM. Score off by 2 gp per hit. Rare configuration but determinate over-payment.

**Recommendation:** Either move cancellation BEFORE sweep override, or cache `originalBeloteTeam = R.TeamOf(kWho)` at step 1 and use that for the cancellation walk. The comment at `Rules.lua:725-737` defends current order with "sweeper discards loser's melds" — but the Belote +20 is documented at `Rules.lua:898-912` as multiplier-immune AND independent of meld winner-takes-all. The comment's logic conflates two unrelated rules.

---

### F-04 — `meldsByTeam` source mismatch with X5 fix (MEDIUM severity)

**File:** `Rules.lua:680-682, 760-762, 821-822, 839-840, 852-853`.

**Issue:** `R.ScoreRound` consumes `meldsByTeam` from its caller. The actual production source is `s.meldsByTeam` populated by `S.ApplyMeld` (`State.lua:1149-1189`), NOT by `R.DetectMelds`. `S.ApplyMeld` drops Hokm 4-Aces:

```lua
if kind == "carre" then
    if K.CARRE_RANKS[top] then
        if top == "A" then
            if s.contract and s.contract.type == K.BID_SUN then
                value = K.MELD_CARRE_A_SUN     -- "Four Hundred", Sun only
            end
            -- Hokm 4-Aces: doesn't score (per Pagat-strict)
        else
            value = K.MELD_CARRE_OTHER          -- T, K, Q, J → 100 raw
        end
    end
    -- 9 carrés (and 8/7) drop through with value=nil → not scored
end
if not value then return end
```
(State.lua:1171-1184)

The Hokm-A branch has NO else — `value` stays nil → `S.ApplyMeld` returns early WITHOUT inserting into `meldsByTeam`. So whatever `R.DetectMelds` produces for Hokm-A (now correctly 100 raw per X5 at `Rules.lua:276-280`), the wire path silently drops it.

`R.ScoreRound` consumes `meldsByTeam`:

```lua
local meldA = R.SumMeldValue(meldsByTeam.A)
local meldB = R.SumMeldValue(meldsByTeam.B)
```
(Rules.lua:680-681)

```lua
local meldVerdict = R.CompareMelds(meldsByTeam.A, meldsByTeam.B, contract)
```
(Rules.lua:760)

If a player held 4 Aces in Hokm and declared the carré, `meldsByTeam[holderTeam]` does not contain the meld → `meldA/meldB` excludes 100, `R.CompareMelds` doesn't see it, strict-majority threshold check at lines 763-766 doesn't include 100, scoring branch at lines 821-822 / 839-840 / 852-853 awards 0 instead of 100 raw, AND the v0.9.0 M5 belote-cancellation path at lines 738-746 doesn't see the ≥100 meld so belote stays uncancelled (silent +20 over-scoring).

**Code quotes (the X5 site is correct, the wire path drops it):**

X5 in `R.DetectMelds` (correct):
```lua
if rank == "A" then
    value = isSun and K.MELD_CARRE_A_SUN or K.MELD_CARRE_OTHER
else
    value = K.MELD_CARRE_OTHER
end
```
(Rules.lua:276-280)

`S.ApplyMeld` (wire path, drops Hokm-A):
```lua
if top == "A" then
    if s.contract and s.contract.type == K.BID_SUN then
        value = K.MELD_CARRE_A_SUN
    end
    -- Hokm 4-Aces: doesn't score (per Pagat-strict)
else
    value = K.MELD_CARRE_OTHER
end
```
(State.lua:1173-1180)

The "(per Pagat-strict)" comment in `S.ApplyMeld` directly contradicts the v0.10.0 X5 fix comment in `R.DetectMelds` ("Per videos #32 line 245 + #38 line 61, four-Aces in Hokm scores 100 like the other carrés"). One is wrong.

**Severity:** MEDIUM. Bidder-strict-majority can flip on a 100-raw delta. Belote cancellation can flip. Score off by 10 gp per Hokm-A-carré hit + possibly 2 gp belote-cancellation flip.

**Recommendation:** Either (a) `S.ApplyMeld` should mirror `R.DetectMelds` and set `value = K.MELD_CARRE_OTHER` for Hokm-A, OR (b) the audit team needs to decide whether X5 was correct or `S.ApplyMeld`'s "Pagat-strict" comment was correct, and align both. Cross-reference `feedback_wow_spellid_sources.md`-style triangulation: D-RT-06 found this; D-RT-30 F2 corroborates the asymmetry.

---

### F-05 — `R.TeamOf(nil)` returns "B" silently (MEDIUM severity)

**File:** `Rules.lua:677, 25-28`.

**Issue:** `R.TeamOf` doesn't validate input:

```lua
function R.TeamOf(seat)
    if seat == 1 or seat == 3 then return "A" end
    return "B"
end
```
(Rules.lua:25-28)

`R.ScoreRound` line 677:
```lua
local bidderTeam  = R.TeamOf(contract.bidder)
```

If `contract.bidder == nil` (e.g., stale resync where contract was reset, hand-edited save), `bidderTeam` silently becomes "B". The entire scoring branch then assumes B is bidder. This is a silent failure mode — no warning, no log.

**Repro:**
1. `contract = { type=K.BID_HOKM, trump="H", bidder=nil, ... }`.
2. `R.ScoreRound` proceeds, `bidderTeam = "B"`, `oppTeam = "A"`.
3. If A took 100 trick points and B took 62, code reads "bidder B failed" (62 < 100) → defenders (A) get handTotal=162. Plausible but the scenario is corrupt input.

**Severity:** MEDIUM. Boundary defensive. Won't fire in normal play, but corruption / wire-edge / test-fixture-typo silently passes.

**Recommendation:** Either:
- Add early guard at `R.ScoreRound` start: `if not contract or not contract.bidder then return nil, "no bidder" end`.
- Make `R.TeamOf` strict: return nil on invalid seat, propagate.

---

### F-06 — Belote sweep-override comment misaligned with code intent (LOW severity)

**File:** `Rules.lua:716-723, 725-737`.

**Issue:** Comment at lines 716-723:

```
-- Saudi sweep convention: the sweeping team takes EVERYTHING,
-- including the +20 belote bonus. Pagat-strict would keep belote
-- with the K+Q holder regardless, but the Saudi "winner takes all"
-- reading covers belote too. Override here so the belote-add-to-raw
-- below routes the bonus to the sweep winner.
```

vs. lines 898-912 (post-multiplier belote add):
```
-- Belote: independent +20 raw, applied AFTER the multiplier.
-- Pagat: "Baloot always 2 points unaffected" — Bel/Triple/Four/Sun multipliers
-- do NOT scale the Belote bonus. Always +2 game points to that team.
```

The two comments contradict on whether Belote follows winner-takes-all. The first says "Saudi sweep takes belote too" (winner-takes-all-extends-to-belote). The second says "Belote always 2 points unaffected" (Pagat-style independent bonus).

The actual code (Rules.lua:721) implements the first rule (sweep moves belote). Whether this is "Saudi sweep convention" or a specific interpretation is undocumented at the source level. Track-A had no transcript covering sweep+belote interaction.

**Severity:** LOW. Code is internally consistent (the sweep override happens before the belote add). Comment-level inconsistency only.

**Recommendation:** Either delete the sweep override (per most-natural-reading-of-Pagat-belote-rule) or add a transcript citation defending it. Currently it's an undefended interpretation.

---

### F-07 — Failed-Gahwa raw-scoring path coexists with match-win flag (LOW severity)

**File:** `Rules.lua:823-840, 920-937`.

**Issue:** When `outcome_kind == "fail"` and `contract.gahwa == true`:

1. `cardA/cardB` set to `handTotal × MULT_FOUR` for defender team (lines 837-840).
2. `meldPoints.A/B` set to each team's own melds (Rules.lua:839-840).
3. Multiplier path: `mult = K.MULT_FOUR = 4` (Rules.lua:889).
4. `rawA/rawB` = `(card + meld) × 4` per team.
5. Belote +20 added unscaled.
6. **Then** Gahwa match-win branch at line 928:
```lua
if contract.gahwa then
    if bidderMade then
        gahwaWinner = bidderTeam
    else
        gahwaWinner = oppTeam
    end
    gahwaWonGame = true
end
```

So the result struct contains BOTH:
- `final.A/B` reflecting the per-round (×4 raw) computation.
- `gahwaWonGame = true`, `gahwaWinner = oppTeam`.

The comment at `Rules.lua:920-925` says:
```
-- Gahwa MATCH-WIN branch (v0.2.0+, per "نظام الدبل في لعبة البلوت"):
-- a successful Gahwa wins the entire match for the caller's team
-- regardless of point delta. A failed Gahwa hands the match to
-- defenders. Override the per-round delta to push cumulative-to-
-- target by signaling a "match-win" flag the caller (Net.lua's
-- HostStepAfterTrick) can read off the result struct.
```

So the per-round delta is supposed to be overridden. But the function does NOT zero `final.A/B`. It returns BOTH the ×4 per-round delta AND the match-win flag. Net.lua is responsible for choosing which to apply (per "the caller can read off the result struct").

This is a contract-with-the-caller. If Net.lua applies BOTH (adds the per-round delta then triggers match-win), it double-counts. If it only triggers match-win, the per-round delta is wasted. Inline comment doesn't resolve the contract.

**Severity:** LOW (assuming Net.lua handles correctly). But it IS a soft contract that could break with refactoring. No assertion / test pins this interaction.

**Recommendation:** Either zero `final.A/B` when `gahwaWonGame == true`, OR add an explicit comment "caller MUST short-circuit on `gahwaWonGame == true` and ignore `final`/`raw`". Currently the convention is implicit.

Compare to `Rules.lua:789-793`:
```
-- (gahwa is normally short-circuit to match-win, so this
--  tie path is only reached when ScoreRound is called from
--  an SWA / takweesh penalty path that doesn't trigger
--  the match-win branch.)
```

This comment acknowledges the multi-caller complexity but is buried in the tied-target inversion path, not at the result-struct return.

---

### F-08 — Trick-1-leader inference for Reverse-Kaboot would require new tracking (LOW severity)

**File:** `Rules.lua:665-674`.

**Issue:** The trick aggregation loop:
```lua
for i, t in ipairs(tricks) do
    local team = R.TeamOf(t.winner)
    local pts = R.TrickPoints(t, contract)
    teamPoints[team] = teamPoints[team] + pts
    trickCount[team] = trickCount[team] + 1
    if i == #tricks then
        lastTrickTeam = team
        teamPoints[team] = teamPoints[team] + K.LAST_TRICK_BONUS
    end
end
```

This loop doesn't snapshot trick-1's lead seat. To wire Reverse-Kaboot (F-01), the function would need to read `tricks[1].plays[1].seat` (the first play of the first trick) and compare against `contract.bidder`. Trick-1-leader is recoverable from the input but not currently extracted.

**Severity:** LOW (precondition for F-01 wiring, not a bug on its own).

**Recommendation:** When wiring F-01, compute `local firstLeader = tricks[1] and tricks[1].plays[1] and tricks[1].plays[1].seat` early in `R.ScoreRound` (alongside `lastTrickTeam`).

---

### F-09 — Tied-target inversion sequence: Sun-foured / Sun-tripled paths unreachable but defensively wired (LOW severity)

**File:** `Rules.lua:794-811`.

**Issue:** v0.10.0 R2 collapse of Sun-Triple/Four/Gahwa to Sun-Bel-max happens here:

```lua
local highest
if contract.type == K.BID_SUN then
    highest = contract.doubled and "double" or "none"
elseif contract.gahwa   then highest = "gahwa"
elseif contract.foured  then highest = "four"
elseif contract.tripled then highest = "triple"
elseif contract.doubled then highest = "double"
else                         highest = "none" end
```
(Rules.lua:799-806)

Sun branch correctly drops `tripled/foured/gahwa` flags. The `if contract.type == K.BID_SUN then` early-out is structured well: it handles Sun first and returns without falling through to the `gahwa/foured/tripled` chain.

```lua
if highest == "double" or highest == "four" then
    outcome_kind = "take"   -- defender escalated last; tie → bidder takes
else
    outcome_kind = "fail"
end
```
(Rules.lua:807-811)

Logic: `double` and `four` rungs were last-escalated by defenders → tie means defender (the "buyer") failed → bidder takes (`outcome_kind = "take"`). `triple`, `gahwa`, `none` are bidder-escalated (or no-escalation, where bidder is the implicit "buyer") → tie → bidder fails (`outcome_kind = "fail"`). This matches v0.8.6 H3 logic.

**Severity:** LOW. The path is correct. The minor quibble: comment block at lines 784-789 explicitly enumerates "no escalation → bidder buyer", "doubled (Bel) → defender buyer", "tripled → bidder buyer", etc. — but the code uses `"double"` and `"four"` as the defender-buyer set (not "double" + "four" as written in the comment). Cross-check: at v0.2.0+ chain "doubled (Bel) → defender", "tripled → bidder", "foured → defender", "gahwa → bidder". `four` is in the defender-buyer set ✓. `double` ✓. So `outcome_kind == "take"` for `double | four` is correct.

The `none → fail` path also fires in the no-escalation case (e.g., `contract = { type=BID_HOKM, bidder=1 }` with no doubled/tripled flags). This is the canonical "tie defaults to defenders" rule. ✓.

**No issue. Documenting for completeness.**

---

### F-10 — Sun-mult collapse correctly handles all stale flags (PASS)

**File:** `Rules.lua:884-893`.

**Issue:** None. Collapse logic:

```lua
local mult = K.MULT_BASE
if contract.type == K.BID_SUN then
    mult = mult * K.MULT_SUN
    if contract.doubled then mult = mult * K.MULT_BEL end
    -- intentionally ignore tripled/foured/gahwa on Sun
else
    if     contract.gahwa   then mult = mult * K.MULT_FOUR  -- ×4 baseline
    elseif contract.foured  then mult = mult * K.MULT_FOUR
    elseif contract.tripled then mult = mult * K.MULT_TRIPLE
    elseif contract.doubled then mult = mult * K.MULT_BEL end
end
```

- Sun no-double: `mult = 1 × 2 = 2` ✓
- Sun-Bel: `mult = 1 × 2 × 2 = 4` ✓
- Sun-stale-tripled: `mult = 1 × 2 = 2` ✓ (stale flag ignored)
- Hokm no-double: `mult = 1` ✓
- Hokm-Bel: `mult = 2` ✓
- Hokm-Triple: `mult = 3` ✓
- Hokm-Four: `mult = 4` ✓
- Hokm-Gahwa: `mult = 4` ✓ (per comment "×4 baseline")

Per `Constants.lua:68-72`. PASS.

---

### F-11 — Belote independence correctly applied AFTER mult (PASS)

**File:** `Rules.lua:895-912`.

**Issue:** None. Code:

```lua
local rawA = (cardA + meldPoints.A) * mult
local rawB = (cardB + meldPoints.B) * mult

-- Belote: independent +20 raw, applied AFTER the multiplier.
if belote == "A" then
    rawA = rawA + K.MELD_BELOTE
elseif belote == "B" then
    rawB = rawB + K.MELD_BELOTE
end
```

- `rawX = (cardX + meldX) × mult + (belote == X and 20 or 0)` ✓
- Belote NOT scaled by mult ✓
- Per CLAUDE.md "Belote (K+Q of trump, +20) is multiplier-immune. A ×4 round doesn't ×4 the Belote bonus." ✓
- Comment at line 902-907 explicitly notes that `meldPoints` is NOT mutated with belote (avoids double-apply if a caller recomputes from `(cardPts + meldPoints) * mult`). PASS.

---

### F-12 — Carré-A in Sun = 400 raw direct (PASS at the `R.DetectMelds` site, BUT see F-04)

**File:** `Rules.lua:273-287`, cross-checked at `Constants.lua:95`.

**Issue:** `R.DetectMelds` correctly produces a meld `{kind="carre", value=400, top="A", ...}` in Sun. `S.ApplyMeld` (`State.lua:1173-1175`) ALSO correctly sets `value = K.MELD_CARRE_A_SUN = 400` for Sun-A. So in the wire path, Sun-A is 400 raw. Pipeline `400 × 2 (Sun mult) / 10 = 80 gp`. PASS for Sun.

(For Hokm-A, F-04 applies — `S.ApplyMeld` drops Hokm-A.)

---

### F-13 — Bidder strict-majority `>` (not `>=`) — both Hokm and Sun (PASS)

**File:** `Rules.lua:775-778`.

**Issue:** None. Code:

```lua
if bidderTotal > oppTotal then
    outcome_kind = "make"
elseif bidderTotal < oppTotal then
    outcome_kind = "fail"
else
    -- tie path
```

Strict `>` → equal totals fall through to tie path → tie defaults to defenders for `none/triple/gahwa` (line 810). Per CLAUDE.md "Bidder fails on tied 81/162 — strict majority required."

For Hokm: bidder needs `> 81` (i.e., ≥ 82) of the 162 raw. ✓
For Sun: bidder needs `> 65` (i.e., ≥ 66) of the 130 raw. ✓ (canonically: tied at 65 = bidder fails, 65+1 needed)

PASS.

---

### F-14 — `effMeldA/B` logic: only winner-team's melds count for threshold check (PASS, with caveat)

**File:** `Rules.lua:758-766`.

**Issue:** None. Code:

```lua
local beloteA = (belote == "A") and K.MELD_BELOTE or 0
local beloteB = (belote == "B") and K.MELD_BELOTE or 0
local meldVerdict = R.CompareMelds(meldsByTeam.A, meldsByTeam.B, contract)
local effMeldA = (meldVerdict == "A") and meldA or 0
local effMeldB = (meldVerdict == "B") and meldB or 0
local bidderTotal = teamPoints[bidderTeam] +
    (bidderTeam == "A" and (effMeldA + beloteA) or (effMeldB + beloteB))
local oppTotal = teamPoints[oppTeam] +
    (oppTeam == "A" and (effMeldA + beloteA) or (effMeldB + beloteB))
```

Threshold check correctly uses `effMeld*` (winner-takes-all), matching the actual scoring branch at lines 858-861 (which also uses `R.CompareMelds`). Comment at lines 748-757 defends this against the alternative "add both melds to both totals" interpretation.

**Caveat:** This depends on `R.CompareMelds` being deterministic at this call site AND at line 859. Currently both call with the same `(meldsByTeam.A, meldsByTeam.B, contract)` so they agree. PASS.

If a future change made `R.CompareMelds` non-deterministic (e.g., random tiebreak), the two call sites could disagree. Defensive recommendation: cache `meldVerdict` and reuse at line 859. (Minor.)

---

### F-15 — `meldVerdict == "tie"` correctly results in `effMeldA = effMeldB = 0` and meldPoints = 0/0 (PASS)

**File:** `Rules.lua:759-862`.

**Issue:** None. When `R.CompareMelds` returns "tie":
- `effMeldA = 0`, `effMeldB = 0` (line 761-762).
- Bidder/opp totals exclude meld.
- Made branch (line 858-861): `meldPoints` stays at 0/0 because `outcome` is "tie", neither A nor B clause fires.
- Fail branch (line 837-840): `meldPoints.A = meldA`, `meldPoints.B = meldB` (each team keeps own melds — explicitly per "مشروعي لي ومشروعك لك" rule, comment line 825-829). Note: this DIFFERS from the made branch's winner-takes-all. Intentional asymmetry.
- Take branch (line 850-853): same as fail — each team keeps own melds.
- Sweep branch (line 821-822): sweep team takes `meldA` or `meldB`, loser team gets 0. Sweep is "winner takes all".

The asymmetry is documented at lines 824-836 (fail) and 841-849 (take): the bidder-fail / doubled-tie-inversion paths preserve loser's melds (per the bug fix narrative — "with Hokm Bel'd (×2) and the bidder team failing, the bidder team showed final = 0 even when they had declared a quarte").

PASS.

---

### F-16 — `div10` rounding 5-up direction (PASS)

**File:** `Rules.lua:914-918`.

**Issue:** None. Code:
```lua
local function div10(x) return math.floor((x + 5) / 10) end
```

Per video #43 transcript (cited at lines 914-917): "65 raw → 70, 67 raw → 70, 64 raw → 60." Formula `(x + 5) / 10` floor:
- 65 → (65+5)/10 = 7 → 70 ✓
- 67 → (67+5)/10 = 7.2 → floor 7 → 70 ✓
- 64 → (64+5)/10 = 6.9 → floor 6 → 60 ✓
- 70 → (70+5)/10 = 7.5 → floor 7 → 70 ✓

PASS.

---

### F-17 — Last-trick +10 awarded to last-trick-winner team, not bidder (PASS)

**File:** `Rules.lua:670-673`.

**Issue:** None. Code:
```lua
if i == #tricks then
    lastTrickTeam = team
    teamPoints[team] = teamPoints[team] + K.LAST_TRICK_BONUS
end
```

`team = R.TeamOf(t.winner)` where `t.winner` is the trick-8 winner. Bonus 10 goes to whoever won trick 8, regardless of bidder/defender role. ✓ Matches Saudi rule "+10 to the team that takes trick 8" (CLAUDE.md "Last trick = +10 raw — bonus to whoever wins trick 8").

PASS.

---

## Cross-references

- D-RT-04 F12 (Reverse-Kaboot single-source dispute) → F-01
- D-RT-06 (`S.ApplyMeld` drops Hokm-A) → F-04
- D-RT-20 (v0.9.0 M5 belote-cancel team-level clean) → confirmed in F-03 + F-15
- D-RT-30 F2 (Gahwa branch lacks Sun gate at line 928) → F-02
- v0.10.0 R2 (Sun-mult collapse) → F-10 PASS
- v0.10.0 R5 (Carré-A in Sun = 400) → F-12 PASS
- v0.10.0 X5 (Carré-A in Hokm = 100 in `R.DetectMelds`) → contradicted by `S.ApplyMeld` (F-04)
- v0.8.6 H3 (tied-target inversion) → F-09 PASS
- B-Rules-02 (existing `R.ScoreRound` review) → corroborates F-01 (their F-02), F-02 (their F-03), F-03 (their F-01), F-05 (their F-04). This audit adds F-04 (S.ApplyMeld asymmetry), F-07 (failed-Gahwa raw + match-win double-fire), F-08 (trick-1-leader missing), and explicit PASS findings F-09 through F-17.

## Test gaps (recommended additions)

- Section J: sweep-resurrects-cancelled-belote (F-03 scenario): Hokm-H, seat 1 (A) holds KH+QH+seq5-hearts, B sweeps. Expect `final.A` = 25 gp (250/10) NOT 27 (250+20)/10.
- Section L: Sun-stale-gahwa: `contract = { type=Sun, gahwa=true, bidder=1 }`. Expect `gahwaWonGame == false`, `multiplier == 2`.
- Section J: Hokm 4-Aces declared via `S.ApplyMeld` then scored via `R.ScoreRound`. Expect `meldA = 100` in `R.ScoreRound`. Currently FAILS due to F-04.
- Section H: defender-sweep with bidder-led-trick-1 (Reverse-Kaboot setup). Expected behavior depends on F-01 resolution (wire +88 or explicit no-op).
- Section G: Hokm 81-81 tied trick-points (no melds, no doubles). Expect `outcome_kind = "fail"`, `final.opp = 16`, `final.bid = 0`.
- Section L: failed-Gahwa interaction (F-07): `contract = { type=Hokm, gahwa=true, bidder=1 }`, defender takes 90 of 162. Expect `gahwaWonGame = true`, `gahwaWinner = oppTeam`, AND validate caller's contract on what to do with `final.*` — currently ambiguous.
