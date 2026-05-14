# T-2 sweep-pursuit-early Kaboot lead — design / inventory pass

**Status:** design pass only. No runtime edits, no test edits, no
branch, no tag, no release. Uncommitted on `main`.

**Provenance:**

- Builds on `.swarm_findings/v3_2_4_high_pickplay_coverage_design.md`
  and `.swarm_findings/v3_2_5_high_pickplay_batch_b_design.md`,
  both of which deferred T-2 pending a dedicated design pass on
  prior-tricks-history fixture approach.
- Current state: `main = origin/main = 8fea79e`. Harness baseline
  `1273 / 0` after the BJ T-10 merge.
- Latest shipped tag: `v3.2.3` (no v3.2.4/v3.2.5 release tag).
- This doc inventories T-2 — the **sweep-pursuit-early Kaboot
  lead** branch in `pickLead` — and recommends whether to ship
  test-only coverage, a runtime fix, or a deferral.

**Hard constraints (this pass):**

- Design only. **No edits to `Bot.lua`**, tests, `.toc`,
  `.pkgmeta`, `.github/`, packaging, or CHANGELOG.
- No branch, no tag, no release.
- Preserve `sprint-a-experimental` and `v0.5.1-experimental`.
- Leave `.swarm_findings/v3_2_0_botlua_comment_audit.md` untouched
  and untracked.
- This document stays **uncommitted** until Codex review approves.

---

## 1. Current Source Walkthrough

All line numbers verified against current `main` HEAD `8fea79e`.

### 1.1 sweep-pursuit-early gate (`Bot.lua:1073-1137`)

```lua
local trickNum = #(S.s.tricks or {}) + 1
local sweepPursuitEarly = false
-- v1.0.3 (Cluster 4 defender sweep-pursuit): pre-fix the gate
-- required `isBidderTeam`. But defenders sweeping every prior
-- trick is the canonical Reverse Al-Kaboot setup ...
if trickNum >= 3 and trickNum <= 7 then
    local mySwept = 0
    for _, t in ipairs(S.s.tricks or {}) do
        if R.TeamOf(t.winner) == myTeam then
            mySwept = mySwept + 1
        end
    end
    sweepPursuitEarly = (mySwept == trickNum - 1)
    -- v1.0.3 (U-7) Kaboot-feasibility hand-shape gate ...
    if sweepPursuitEarly and Bot.IsM3lm() and S.HighestUnplayedRank
       and contract.trump then
        local remainingNeeded = 8 - trickNum + 1
        local feasibleWinners = 0
        for _, c in ipairs(legal) do
            local r = C.Rank(c)
            local su = C.Suit(c)
            if su == contract.trump then
                if r == "J" or r == "9" or r == "A" then
                    feasibleWinners = feasibleWinners + 1
                elseif S.HighestUnplayedRank(contract.trump) == r then
                    feasibleWinners = feasibleWinners + 1
                end
            else
                if S.HighestUnplayedRank(su) == r then
                    feasibleWinners = feasibleWinners + 1
                end
            end
        end
        if feasibleWinners < remainingNeeded then
            sweepPursuitEarly = false
        end
    end
end
```

### 1.2 Sweep-pursuit fire site (`Bot.lua:1138-1190`)

```lua
if trickNum == 8 or sweepPursuitEarly then
    ...
    if S.HighestUnplayedRank then
        local trumpExhausted = (contract.type == K.BID_HOKM
                                and contract.trump
                                and S.HighestUnplayedRank(contract.trump) == nil)
        local safeBosses = {}
        for _, c in ipairs(legal) do
            local r = C.Rank(c)
            local su = C.Suit(c)
            local isBoss = S.HighestUnplayedRank(su) == r
            local isSafe = (contract.type ~= K.BID_HOKM)
                            or C.IsTrump(c, contract)
                            or trumpExhausted
            if isBoss and isSafe then safeBosses[#safeBosses + 1] = c end
        end
        if #safeBosses > 0 then
            return highestByFaceValue(safeBosses, contract)
        end
    end
    -- Else: just lead our highest-rank or highest-face-value ...
    if sweepPursuit then
        return highestByRank(legal, contract)
    end
    return highestByFaceValue(legal, contract)
end
```

`sweepPursuit` (the local at L1149) is only true when `mySwept ==
7` (trick 8 with full prior sweep). For trickNum 3-7 with
`sweepPursuitEarly` firing, `sweepPursuit` is false, so the
"highest-rank legal" branch at L1187 is dead for T-2; we reach
either `safeBosses` (L1180) or `highestByFaceValue(legal)`
(L1189).

### 1.3 Markers in the T-2 region

- **L1063:** `v0.5.19 Section 7 rules 1+2 (Common, videos
  06+07+15)` — anchors the v0.5.19 origin of the early-pursuit
  extension.
- **L1074:** `v1.0.3 (Cluster 4 defender sweep-pursuit)` —
  anchors the v1.0.3 defender-team relaxation.
- **L1089:** `v1.0.3 (U-7) Kaboot-feasibility hand-shape gate`
  — anchors the v1.0.3 feasibility gate (the most specific
  marker for T-2's behavioural surface).
- **L1095:** `Kaboot pursuit feasibility check` (cross-reference
  to `decision-trees.md` Section 7).

All four are single-line and survive the line-wrap pitfall that
hit BJ.3/BJ.4 in round 1.

---

## 2. Preconditions to Reach T-2

To enter the T-2 (sweep-pursuit-early fire) path through `pickLead`:

| Predicate | Requirement |
|---|---|
| `applyClosedTrumpLeadGate(legal, contract)` | Does not strip our hand to empty (no `S.s.closedTrump` set). |
| `trickNum` | `#(S.s.tricks) + 1`, so `S.s.tricks` must have 2-6 entries to land in `[3, 7]`. |
| `myTeam` | `R.TeamOf(seat)`; bot's own team. |
| `mySwept` | Every prior trick's `winner` ∈ `myTeam`. |
| Tier | `Bot.IsM3lm()` (only required for the feasibility gate to RUN; without M3lm the gate is skipped, but the rest of sweep-pursuit-early still fires when conditions 1-4 hold). |
| Contract | `contract.trump` set. Both Hokm and Sun work; the feasibility gate uses `S.HighestUnplayedRank(contract.trump)` which returns nil for `contract.trump = nil` (Sun), forcing the M3lm feasibility check to skip entirely. |
| `legal` | Contains enough "winners" so `feasibleWinners >= 8 - trickNum + 1`. Trump J/9/A always count; lower trump count if `HUR(trump) == r`; side-suit cards count if `HUR(suit) == r`. |
| Upstream shadows | None — `sweepPursuitEarly` is among the very first branches in `pickLead` (L1073), before mardoofa probes, Tahreeb reads, Fzloky, etc. |

The branch chooses a card via:

1. `safeBosses` scan: in-suit boss + safe-in-contract. In Hokm:
   trump cards are always safe; non-trump cards are safe only if
   `trumpExhausted == true` (every trump played). If any boss is
   safe, returns `highestByFaceValue(safeBosses, contract)`.
2. Fallback for trickNum 3-7 (not full-sweep): returns
   `highestByFaceValue(legal, contract)`.

---

## 3. Prior-Trick History Staging

### 3.1 What `S.s.tricks` entries need

The sweep-pursuit gate at L1083 only reads `t.winner` for each
entry. **No other field is consulted by this branch.** Existing
test precedent at `test_state_bot.lua:354/1877/1938/1986/5994/
6950/7195` already stages `S.s.tricks = { { winner = N, plays =
{...} } }` with arbitrary `plays` content (often empty `{}`).

Minimal entry for T-2's gate: `{ winner = N }` (no `plays`
required for the gate; `plays = {}` for cosmetic consistency
with existing tests is fine).

### 3.2 Can prior tricks be staged cleanly?

**Yes.** A trickNum=7 fixture needs 6 prior-trick entries —
trivial to write. No upstream gate consults the contents of
prior tricks for the sweep-pursuit-early branch specifically.

### 3.3 Risk: prior-tricks side effects on other branches

If we later expand the fixture to test a fallback path (e.g.
trick-1 mardoofa probe, Sun pos-3 Takbeer), those branches
might read `S.s.tricks[*]` for `winner` / `plays`. But for **T-2
itself**, the gate is self-contained.

---

## 4. HUR / `playedCardsThisRound` Stubbing

### 4.1 Source of truth

`S.HighestUnplayedRank(suit)` at `State.lua:1762-1776` computes
from `s.playedCardsThisRound` directly:

```lua
function S.HighestUnplayedRank(suit)
    if not suit or suit == "" then return nil end
    s.playedCardsThisRound = s.playedCardsThisRound or {}
    local order = AKA_ORDER  -- non-trump: A > T > K > Q > J > 9 > 8 > 7
    if s.contract and s.contract.type == K.BID_HOKM
       and s.contract.trump == suit then
        order = TRUMP_HOKM_ORDER  -- trump: J > 9 > A > T > K > Q > 8 > 7
    end
    for _, r in ipairs(order) do
        if not s.playedCardsThisRound[r .. suit] then
            return r
        end
    end
    return nil
end
```

So there is **no separate HUR stub** — seeding
`S.s.playedCardsThisRound` is the way to control HUR.

### 4.2 Required seeding for the proposed fixture (§5)

For the proposed fixture with hand `{JS, 9S}` at trickNum=7:

- `feasibleWinners` check at L1108-1132: trump J and 9 auto-count
  (`r == "J" or r == "9" or r == "A"`); no HUR query needed for
  the auto-count path.
- `safeBosses` scan at L1170-1178: `isBoss = (HUR(su) == r)`.
  - For `JS`: `HUR("S") == "J"` → since `JS` is in our hand
    (unplayed) AND we don't seed any other trump-S cards as
    played, HUR walks TRUMP_HOKM_ORDER `{J, 9, A, T, K, Q, 8,
    7}` and returns the first not-in-played: `"J"`. ✓
  - For `9S`: `HUR("S") == "9"` → returns `"J"` (same logic),
    not `"9"`. Skipped. ✓

**No `playedCardsThisRound` seeding is strictly required for
the positive case.** The default empty table works because the
two trump cards we're inspecting are auto-counted (feasibility)
and HUR returns the correct boss naturally.

For the **negative case** (one opp prior win → `sweepPursuitEarly
== false`), the bot falls through to the rest of `pickLead`,
which eventually reaches the no-non-trump fallback at
`Bot.lua:2892-2937` returning `lowestByRank(legal, contract)` =
`9S` (trump-rank 7 < J trump-rank 8). Again no
`playedCardsThisRound` seeding required.

### 4.3 Optional fixture polish

To be cosmetically realistic (24 cards played across 6 prior
tricks), one could seed `playedCardsThisRound` with the 24
non-{JS, 9S} cards from those tricks. This is NOT needed for
the test to assert correctly, just for "looks like a real game"
hygiene. Recommend skipping the cosmetic seeding to keep the
fixture minimal.

---

## 5. Positive Fixture Proposal

### 5.1 BK.1 — sweep-pursuit-early fires + boss-lead

**Fixture setup:**

- Hokm contract, trump `S`, bidder seat 1.
- Bot at seat 3, partner = seat 1 (same team A).
- `WHEREDNGNDB.m3lmBots = true` (M3lm enabled so the
  feasibility gate runs).
- All seats marked `isBot = true` (consistency with BH/BI/BJ
  prologue; no functional requirement here since T-2 doesn't
  consult `Bot.IsBotSeat`).
- `S.s.tricks` = 6 entries, all `winner` ∈ team A (seats 1 and
  3 alternating). Each entry uses `plays = {}` for cosmetic
  consistency with existing tests; the gate only reads
  `t.winner`.
- `S.s.trick = { leadSuit = nil, plays = {} }` (we are
  leading).
- `S.s.playedCardsThisRound = {}` (no seeding needed — HUR
  computes from empty as documented in §4.2).
- Hand at seat 3: `{ "JS", "9S" }`.

**Trace:**

- `trickNum = 7`, `mySwept = 6`, `sweepPursuitEarly = (6 == 6)`
  = true.
- M3lm + `S.HighestUnplayedRank` defined + `contract.trump =
  "S"` → feasibility gate runs.
- `remainingNeeded = 8 - 7 + 1 = 2`.
- `feasibleWinners` count:
  - `JS`: trump suit `S`, rank `"J"` → auto-count `+1`.
  - `9S`: trump suit `S`, rank `"9"` → auto-count `+1`.
  - Total = 2 ≥ 2. Gate passes; `sweepPursuitEarly` stays true.
- Branch fires at L1138.
- `safeBosses` scan:
  - `JS`: `HUR("S") == "J"` → true. `isSafe` = `C.IsTrump(JS,
    contract)` → true. Added to `safeBosses`.
  - `9S`: `HUR("S") == "9"` → false (HUR returns "J"). Skipped.
- `safeBosses = {JS}`. `highestByFaceValue({JS})` = `JS`.

**Expected assertion:** `card == "JS"` (strict).

**Counterfactual:** if sweep-pursuit-early doesn't fire (or the
boss-scan finds nothing), execution falls through to the rest of
`pickLead`. Trace of the all-trump 2-card no-non-trump path:

- Reaches L2892 ("no non-trump — lowest trump"). `saveHighTrump`
  is false (bot is on bidder team — see L2307 gate `not
  isBidderTeam`).
- L2937 `return lowestByRank(legal, contract)`. In Hokm trump
  context, `9S` (trump-rank 7) < `JS` (trump-rank 8), so
  `lowestByRank({JS, 9S})` returns `9S`.

The `JS` vs `9S` wire discriminator is the positive/negative
proof.

---

## 6. Negative Fixture Proposal

### 6.1 BK.2 — sweep-pursuit-early gate fails (one opp prior win)

**Fixture setup:** identical to BK.1 except one prior trick's
`winner` is changed to an opp seat:

- `S.s.tricks` = 6 entries, but `tricks[2].winner = 2` (opp
  team B); the other 5 still won by team A.

**Trace:**

- `trickNum = 7`, `mySwept = 5`, `sweepPursuitEarly = (5 == 6)`
  = false.
- The feasibility gate inner `if sweepPursuitEarly and ...` is
  skipped (already false).
- `if trickNum == 8 or sweepPursuitEarly` at L1138 is false →
  sweep-pursuit branch skipped entirely.
- Falls through to the rest of `pickLead`.
- `legal = {JS, 9S}` (all trump). Various downstream branches
  are gated on non-trump-presence or trick-N-specific predicates;
  none fire for this 2-card all-trump hand at trick 7 (Hokm,
  bidder-team).
- Reaches L2892. `saveHighTrump` false. L2937 returns
  `lowestByRank({JS, 9S})` = `9S`.

**Expected assertion:** `card == "9S"` (strict).

**Wire role:** locks the `mySwept == trickNum - 1` gate. If a
regression weakens this gate (e.g. allows fire when only some
prior tricks are won), BK.2 would return `JS` instead of `9S`
and the assertion catches it.

---

## 7. Source Pin Proposal

### 7.1 BK.3 — single source pin on the U-7 feasibility marker

```lua
assertTrue(botSrc:find("v1%.0%.3 %(U%-7%) Kaboot%-feasibility hand%-shape gate") ~= nil,
    "BK.3 (v3.2.5 T-2): v1.0.3 U-7 Kaboot-feasibility marker present")
```

Verified single-line presence at `Bot.lua:1089`:

```
1089:        -- v1.0.3 (U-7) Kaboot-feasibility hand-shape gate. Pre-fix
```

Locks the v1.0.3 U-7 feasibility gate's anchor — the exact
marker for the runtime guard that BK.1 exercises (and BK.1's
hand satisfies `feasibleWinners >= remainingNeeded` for).

### 7.2 Recommendation: skip second pin

A second pin on L1074 (`v1.0.3 (Cluster 4 defender
sweep-pursuit)`) or L1063 (`v0.5.19 Section 7 rules 1+2`) is
**not** recommended — the single L1089 anchor is sufficient and
keeps the slice minimal.

---

## 8. Expected Harness Delta

| Item | Checks |
|---|---|
| BK.1 (positive sweep-pursuit-early → JS) | 1 behavioural |
| BK.2 (negative one-opp-won → 9S) | 1 behavioural |
| BK.3 (source pin v1.0.3 U-7 Kaboot-feasibility) | 1 source-pin |
| **Subtotal** | **3** |

New harness total: `1273 + 3 = 1276 / 0`.

---

## 9. Stop Conditions

Stop and report (do NOT silently work around) if any of these
happen during implementation:

1. **BK.1 returns `"9S"` instead of `"JS"`.** Indicates
   sweep-pursuit-early didn't fire (gate failed: `mySwept !=
   trickNum-1`? feasibility miscount?) OR safeBosses scan
   returned empty (HUR misreporting `"S"`'s top). Re-audit the
   prior-tricks `winner` seeding and `playedCardsThisRound`
   state.
2. **BK.1 returns any non-trump card.** Indicates the legal set
   somehow contains non-trump cards or a different branch
   shadowed sweep-pursuit-early. Re-audit fixture setup.
3. **BK.2 returns `"JS"` instead of `"9S"`.** Indicates
   sweep-pursuit-early fired despite the one-opp-won gate —
   either the gate `(mySwept == trickNum - 1)` is regressed, or
   the prior-tricks `winner` seeding for opp seat is wrong.
4. **BK.2 returns any non-trump card.** Same as condition 2.
5. **Existing trick-history-based tests regress** (e.g. AK.3
   at `test_state_bot.lua:5994`+, AB.4 / J.4 / v3.0.2-3 at
   1877/1938/1986). Any pre-existing harness check breaks ⇒
   stop and report.
6. **Source-pin substring missing.** If BK.3's substring
   doesn't match current `Bot.lua`, the marker may have been
   reworded — verify before adjusting; do NOT silently weaken
   the pin.
7. **Runtime change becomes necessary.** Test-only batch. If a
   runtime edit appears required, stop and report — the design
   recommendation is option A (test-only); do NOT switch to
   option B without a fresh Codex round.

---

## 10. Recommendation

### 10.1 Classification

**A. Already correct; needs regression coverage only.**

Rationale:
- The T-2 branch at L1081-1136 is well-structured with explicit
  gates and an audit-documented feasibility check.
- No anomalies observed in the source walkthrough.
- The branch's gating is conservative (M3lm-only feasibility
  check, M3lm-only fire after the v1.0.3 U-7 fix) — false-
  positives degrade to the v0.5.19 default, not a worse path.
- No HUR / `playedCardsThisRound` stub semantic mismatch
  identified.

### 10.2 Implementation recommendation

**Proceed with smallest-batch test-only implementation: BK.**

Scope:
- New BK section in `tests/test_state_bot.lua` (after BJ).
- 3 checks: BK.1 (positive), BK.2 (negative), BK.3 (single
  source pin).
- Expected harness delta: `1273 / 0 → 1276 / 0`.
- No runtime change. No CHANGELOG. No tag.

### 10.3 Fixture complexity disclosure

BK is **slightly heavier** than BH/BI/BJ:

- Requires staging 6 prior-trick entries (vs single-trick
  fixtures in BH/BI/BJ).
- Each entry's `winner` field must be carefully set to either
  team A (for BK.1) or one team B (for BK.2).

But it is still much lighter than the originally-feared T-2
fixture surface:

- **No** `S.HighestUnplayedRank` stub override needed (the
  default empty-`playedCardsThisRound` semantic produces the
  right HUR values for our hand).
- **No** large `playedCardsThisRound` seeding (24-card
  consistency is not required for the test to assert correctly).
- **No** multi-suit boss construction (the `{JS, 9S}` all-trump
  2-card hand sidesteps non-trump boss-scan complexity entirely).

Risk classification: **LOW-MED.** The medium component is the
prior-tricks-history setup (more lines of fixture code), but
nothing technically novel — precedent exists in AK.3 / AB.4 /
J.4 / v3.0.2-3.

### 10.4 Deferrals tracked

- **Sun variant of T-2.** The proposed fixture uses Hokm. A Sun
  variant would also be testable but requires non-trump boss
  staging and a different feasibility-gate path (Sun skips the
  M3lm feasibility check since `contract.trump = nil`). Defer
  unless Codex specifically requests a Sun pair.
- **Defender-team sweep-pursuit (v1.0.3 Cluster 4 relaxation).**
  The proposed BK.1 puts bot on bidder team. A defender-team
  fixture would also exercise the v1.0.3 relaxation explicitly.
  Defer unless Codex specifically requests a defender pair.

---

## 11. Open Questions for Codex Review

1. **Section naming.** BJ is the v3.2.5 T-10 section. BK is the
   natural next letter. Recommend BK.

2. **Source-pin choice.** I propose a single pin on `v1.0.3
   (U-7) Kaboot-feasibility hand-shape gate` (L1089). Codex may
   prefer pinning the broader v0.5.19 origin marker at L1063
   instead, or pinning both. My recommendation: single pin at
   L1089 (most specific to T-2's behavioural surface; minimises
   over-pinning).

3. **Bidder-team vs defender-team fixture orientation.** BK.1
   uses bot on bidder team (seat 3, bidder seat 1, same team
   A). The v1.0.3 Cluster 4 fix specifically extended
   sweep-pursuit to **defenders** (Reverse Al-Kaboot setup).
   Codex may prefer the BK.1 fixture be defender-team to
   directly exercise the v1.0.3 relaxation. My recommendation:
   bidder-team for the simpler test; flag defender-team as a
   future BL slice.

4. **Cosmetic playedCardsThisRound seeding.** §4.3 notes the
   test asserts correctly without seeding `playedCardsThisRound`
   to reflect the 24 cards played across 6 prior tricks. Codex
   may prefer the fixture include a more realistic
   `playedCardsThisRound` for "looks like a real game"
   readability. My recommendation: skip the cosmetic seeding to
   keep the fixture minimal and the assertion robust.

5. **All-trump 2-card hand artificiality.** A {JS, 9S} hand at
   trick 7 implies the bot never played a non-trump card across
   6 tricks — possible but rare. Codex may prefer a
   mixed-suit hand at trickNum=5 (4-card hand). I evaluated
   that and it requires non-trivial `playedCardsThisRound`
   seeding to make non-trump bosses HUR-recognised. The
   simpler all-trump fixture sidesteps this entirely. My
   recommendation: ship the all-trump fixture as-is; if
   "synthetic-looking" is a real Codex concern, switch to the
   mixed-suit at trickNum=5 (and accept the seeding overhead).

---

## 12. Confirmation

- No tracked files changed by this design pass.
- This document is created uncommitted; Codex review precedes
  any commit.
- No edits to `Bot.lua`, runtime files, `tests/`, `.toc`,
  `.pkgmeta`, `.github/`, CHANGELOG.
- No branch created, no tag created, no release initiated.
- `sprint-a-experimental` and `v0.5.1-experimental` preserved.
- `.swarm_findings/v3_2_0_botlua_comment_audit.md` untouched
  and untracked.
