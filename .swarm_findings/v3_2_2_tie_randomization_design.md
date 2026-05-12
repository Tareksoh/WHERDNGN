# v3.2.2 tie-randomization design pass

**Repo:** `C:\CLAUDE\WHEREDNGN`
**Main / origin-main:** `17a0e95` (v3.2.1 ship)
**Latest tags:** `v3.2.1`, `v3.2.0`, `v3.1.14`
**Scope:** read-only design. No runtime / test / TOC / `.pkgmeta` edits.

---

## §0 Executive recommendation

**PROCEED with a VERY SMALL v3.2.2 batch: 1 runtime site converted,
4 sites deferred.**

> **v0.2 amendment (post-Codex review):** F5 site 3 (pos-3 Sun
> partner-certain Takbeer donate at `Bot.lua:4464-4491`) was
> originally approved in v0.1 of this doc. Codex review correctly
> identified that the site's gate `partnerWinning and #winners == 0`
> sits below an enclosing `if partnerWinning then ... return
> lowestByRank(legal, contract) end` block (the partnerWinning block
> at `Bot.lua:3362-3887` ends with an unconditional return at L3886).
> Therefore `partnerWinning == false` is guaranteed at the site, and
> the inner `partnerWinning and #winners == 0` predicate is
> unsatisfiable. This is **the same reachability shape as the v3.2.1
> F2 «تخليه يمسك» hold-back branch** — a second F2-class dead
> branch that the v3.2.1 audit missed. The proposed BE.3 fixture
> (in v0.1) set partnerWinning=true, which means it would not have
> reached the intended donate loop; the test would have failed for
> the wrong reason pre-fix. F5 site 3 is **reclassified to DEFER**
> until the broader pos-3 Sun branch relocation is designed (the
> same future-audit that owns F2 reactivation).

Reading the actual code against the audit's enumeration shows that
only **1 of the 5 audit-listed sites** (F5 site 1) has a real
tie-randomization gap that is both reachable and observable. The
other four — F5 site 2 (Sun establishing boss-lead, single suit
filter), F5 site 3 (pos-3 Takbeer donate, **unreachable**), F5 site
4 (hold-back in the F2-flagged dead branch), and F6 (BotMaster
forced-ruff override, trump-only filter) — either have no ties
possible in their filtered input sets OR sit below an earlier
partnerWinning return.

**Approved sites:** F5 site 1 (`Bot.lua:2033-2040`, Hokm side-Ace
exhaustion fallback).

**Deferred sites:** F5 site 2, F5 site 3 (newly), F5 site 4, F6.

Tests are deterministic (single `math.random` stub) — no
statistical assertions, no probability gates, no flakiness risk.
Tests are designed using the established `origRandom save/restore`
pattern already proven in the harness (AJ.12 / AS.* / etc.).

---

## §1 Repo state (verified)

| Item | Value |
|---|---|
| Current branch | `main` |
| `main` HEAD | `17a0e95fa226d194eca053cb61043aeb92911ab0` |
| `origin/main` | `17a0e95fa226d194eca053cb61043aeb92911ab0` (in sync) |
| Latest tags | `v3.2.1`, `v3.2.0`, `v3.1.14`, `v3.1.12`, `v3.1.11` |
| Working tree | clean except untracked `.swarm_findings/v3_2_0_botlua_comment_audit.md` (left untouched per prompt) |

`WHEREDNGN.toc` load order confirms `Bot/PlayPrimitives.lua` (line
22) loads BEFORE `BotMaster.lua` (line 26), so
`B.Bot.Primitives.lowestByRank` IS available at BotMaster's chunk-
load time. F6's load-order concern is resolved cleanly **if it were
to be done**, but per §0 it is not approved for v3.2.2 anyway.

---

## §2 Site inventory

| # | Source | Lines (current) | Description | Filter scope | **Ties possible?** | Reachable? | Test approach | Decision |
|---|---|---|---|---|---|---|---|---|
| F5-1 | `Bot.lua` | 2033-2040 | Hokm side-Ace exhaustion fallback — highest non-trump card after all 3 non-trump Aces played | non-trump (multi-suit) | **YES** — same rank across different non-trump suits | YES (Hokm + Advanced + tricks≥3 + sideAcesLeft==0) | Stub `math.random` + tied K♠/K♥ pair | **CHANGE** |
| F5-2 | `Bot.lua` | 2669-2679 | Sun establishing boss-lead — highest TrickRank in a specific suit | single suit (filtered by `C.Suit(c) == suit`) | **NO** — within a single suit, all 8 ranks are unique | YES | No tie behaviour to test | **DEFER** (single-suit, no ties) |
| F5-3 | `Bot.lua` | 4464-4491 | pos-3 Sun partner-certain Takbeer donate — highest non-A/T | non-A non-T (multi-suit) | YES in principle — same non-A/T rank across different suits | **NO** — gate requires `partnerWinning == true` but execution path guarantees `partnerWinning == false` here (enclosing `if partnerWinning then ... return lowestByRank(legal, contract) end` at `Bot.lua:3362-3887` returns at L3886) | Site cannot be reached; tie question belongs to a future pos-3 partner-certain branch relocation audit (same family as v3.2.1 F2) | **DEFER** (currently unreachable due to earlier `partnerWinning` return) |
| F5-4 | `Bot.lua` | 4561-4574 | pos-3 «تخليه يمسك» hold-back — highest of 7/8/9 in lead suit | single suit + rank ∈ {7,8,9} | **NO** — within a single suit, 7/8/9 are distinct | DEAD (per v3.2.1 F2 unreachability flag) | Dead code; no behaviour to test | **DEFER** (unreachable + single-suit) |
| F6 | `BotMaster.lua` | 1191-1203 | Forced-ruff override — lowest TrickRank trump in legal | trump suit only | **NO** — within trump suit, all 8 trump-ranks (`K.RANK_TRUMP_HOKM`: J=8, 9=7, A=6, T=5, K=4, Q=3, 8=2, 7=1) are unique | YES | No tie behaviour to test | **DEFER** (trump-only, no ties) |

### §2.1 Why sites 2, 4, F6 have no ties

`C.TrickRank(card, contract)` is determined by (rank, suit, trump).
For two cards to have the same TrickRank:
- Both are non-trump → both use `K.RANK_PLAIN` (`AKA_ORDER`-derived) → same rank string ⇒ same TrickRank.
- Both are trump → both use `K.RANK_TRUMP_HOKM` → same rank string ⇒ same TrickRank.

Within a deck, each (rank, suit) pair is unique. So **ties at the
same TrickRank require two cards in the same hand of the same rank
but different suits, both within the filter's accepted suit set**.

- Site F5-2 filters `C.Suit(c) == suit` — single suit. Two cards
  of same rank in the same suit is impossible (unique cards). No
  ties.
- Site F5-4 filters `C.Suit(c) == lead and r ∈ {7,8,9}` — single
  suit. Same impossibility.
- Site F6 filters `C.IsTrump(c, S.s.contract)` — trump is one suit
  (in Hokm). Same impossibility.

Sites F5-1 (non-trump, multi-suit) and F5-3 (non-A/T, multi-suit)
DO admit ties — e.g., a hand holding K♠ and K♥ in Hokm with trump
= D will see both at `RANK_PLAIN["K"]` → same TrickRank.

### §2.2 The original audit's mis-grouping

The audit's D-1 finding ("4 inline highestByRank-shaped loops
bypass tie randomization") enumerated four sites uniformly, but the
"tie randomization bypass" claim only applies to **one** of them
(F5-1). Two of the remaining three (F5-2, F5-4) have identical
strict-`>` loop shapes but operate on provably tie-free filtered
inputs. The fourth (F5-3) admits ties in principle, but sits below
an earlier `partnerWinning` return — exactly the same reachability
shape as the v3.2.1 F2 «تخليه يمسك» hold-back branch. Both F5-3
and F5-4 are members of the same "pos-3 partner-certain branch
that the partnerWinning return preempts" family.

The audit was not wrong to flag the loop **pattern** (it's still
ugly inline copy-paste that could call `Primitives.highestByRank`),
but the audit was wrong to claim **all four sites have the same
gameplay-impact gap**. Only 1/4 do. The other three plus F6 are
either cosmetic-refactor candidates with no observable behaviour
change (F5-2, F6), or members of the F2 unreachable-branch family
that need their own follow-up audit before any code changes
(F5-3, F5-4).

**Note for future audit work:** F5-3 (`Bot.lua:4464-4491`) is a
second F2-class dead branch and probably deserves the same kind of
in-source "UNREACHABLE in production" comment marker that v3.2.1
F2 applied to the «تخليه يمسك» branch. This is **out of scope for
v3.2.2** (per the prompt's hard rule against editing Bot.lua), but
should be flagged in whichever future-audit owns F2 reactivation
so both sites are addressed together.

---

## §3 Proposed code changes (NOT applied)

### §3.1 Site F5-1 — Hokm side-Ace exhaustion (Bot.lua:2033-2040)

**Before:**

```lua
if sideAcesLeft == 0 then
    -- Lead our highest non-trump (unblocked tricks).
    local bestSide, bestSideR = nil, -1
    for _, c in ipairs(legal) do
        if not C.IsTrump(c, contract) then
            local r = C.TrickRank(c, contract)
            if r > bestSideR then bestSide, bestSideR = c, r end
        end
    end
    if bestSide then return bestSide end
end
```

**After (proposed, ~7 lines including v3.2.2 marker):**

```lua
if sideAcesLeft == 0 then
    -- v3.2.2 F5 site 1 (audit D-1): build the non-trump pool and
    -- route through Primitives.highestByRank so ties at same
    -- TrickRank (e.g., two Kings in different non-trump suits)
    -- are picked at random rather than by hand-iteration order.
    -- Closes a v1.1.0-class predictability tell.
    local nonTrumps = {}
    for _, c in ipairs(legal) do
        if not C.IsTrump(c, contract) then
            nonTrumps[#nonTrumps + 1] = c
        end
    end
    if #nonTrumps > 0 then return highestByRank(nonTrumps, contract) end
end
```

Semantics:
- **Non-tie inputs:** identical card returned (highestByRank picks
  the unique max, same as the inline strict-`>`).
- **Tie inputs:** previously deterministic-first-iteration; now
  randomized via `pickRandomTied`.

### §3.2 Why the other 4 sites get no code change

- **F5-2 (Sun establishing boss-lead, L2669-2679):** filtered to a
  single suit; no ties possible. A refactor would change `for c in
  legal: if Suit(c)==suit and cr > bestRank ...` to `build pool;
  highestByRank(pool)` — semantically identical but adds an
  allocation for zero observable benefit. Hygiene argument is real
  but no behaviour-test could distinguish before/after. Skip.
- **F5-3 (pos-3 partner-certain Takbeer donate, L4464-4491):**
  **unreachable** under the current `pickFollow` structure (the
  enclosing `if partnerWinning then ... return ... end` block at
  `Bot.lua:3362-3887` returns at L3886 before this site's
  `partnerWinning and #winners == 0` gate is ever evaluated). The
  tie-randomization question is genuine in principle, but until the
  pos-3 partner-certain branch is relocated above the
  partnerWinning return, there is no execution path that reaches
  the donate loop. This is a member of the same F2 unreachable-
  branch family as F5-4. Skip until the F2 follow-up audit is
  designed.
- **F5-4 (pos-3 hold-back lowCard, L4561-4574):** branch is
  unreachable per v3.2.1 F2's source-pinned marker. Modifying dead
  code adds review surface and risks subtly altering the dead
  branch's reactivation behaviour when the F2 follow-up audit
  decides whether to relocate it. Skip until F2 is addressed.
- **F6 (BotMaster forced-ruff override, L1191-1203):** filtered to
  trump suit; no ties possible. Same as F5-2 — pure hygiene with no
  observable behaviour change. Skip.

The hygiene-only refactors of F5-2 and F6 could be bundled into a
future "Bot.lua loop-pattern consolidation" pass, but should NOT
ride alongside the real bug-fix in v3.2.2 (different purpose,
different review surface). F5-3 and F5-4 are owned by the future
F2 follow-up audit (pos-3 partner-certain branch relocation) and
should be addressed there.

---

## §4 Proposed tests (NOT applied)

### §4.1 Test architecture

All tests use the **deterministic `math.random` stub** pattern
already proven in the harness (search hits: `tests/test_state_bot.lua`
L3631, L5716, L5787):

```lua
local origRandom = math.random
math.random = function(a, b)
    -- per-test custom return
end
-- ... PickPlay call ...
math.random = origRandom
```

`pickRandomTied(tied)` (PlayPrimitives.lua:45-48) calls
`math.random(#tied)` to return an integer in `[1, #tied]`. Stubbing
that to return `1` forces "first tied", `2` forces "second tied",
etc. Combined with controlled fixture pools, every assertion is
fully deterministic — no statistical thresholds, no flakiness.

### §4.2 BE section (NEW) — F5 site 1 behavioural tests

Proposed location: append after CD section (currently the last
defined section in `tests/test_state_bot.lua`). Test IDs are BE.1
through BE.3.

> **v0.2 amendment:** BE.3/BE.4 from v0.1 of this doc (which would
> have exercised F5 site 3 pos-3 Takbeer donate) are **removed
> from the approved implementation plan**. They are recorded in
> §4.3 below as "deferred future test ideas" — to be revisited
> after the pos-3 partner-certain branch is relocated above the
> `partnerWinning` early-return as part of the future F2 audit.
> The renumbered BE.3 in this revision is the F5 site 1 source-pin
> test (was BE.5 in v0.1).

#### BE.1 — F5 site 1, tie randomization wired

**Fixture:** Hokm contract, Advanced bidder-self at lead position
post-trick-3 with all 3 non-trump Aces observed-played (mardoofa
exhaustion). Hand contains exactly two tied non-trump bosses (e.g.,
K♠ and K♥ — both `RANK_PLAIN["K"]=6`).

```lua
-- BE.1: F5 site 1 tie-randomization wired
do
    WHEREDNGNDB.advancedBots = true
    freshState()
    S.s.isHost = true
    S.s.contract = { type = K.BID_HOKM, trump = "D", bidder = 3 }
    Bot._memory = nil; Bot.ResetMemory()
    -- All 3 non-trump Aces marked played by opps so sideAcesLeft=0.
    Bot._memory[1].played = { AS = true, AH = true, AC = true }
    -- 3+ prior tricks present (required by L1997 gate)
    S.s.tricks = {
        { winner = 1, leadSuit = "S",
          plays = {{seat=1,card="AS"},{seat=2,card="7S"},{seat=3,card="8S"},{seat=4,card="9S"}} },
        { winner = 1, leadSuit = "H",
          plays = {{seat=1,card="AH"},{seat=2,card="7H"},{seat=3,card="8H"},{seat=4,card="9H"}} },
        { winner = 1, leadSuit = "C",
          plays = {{seat=1,card="AC"},{seat=2,card="7C"},{seat=3,card="8C"},{seat=4,card="9C"}} },
    }
    S.s.trick = { leadSuit = nil, plays = {} }
    -- Bot seat 3 (bidder), hand has K♠ + K♥ (tied non-trump K),
    -- plus 7D (single trump). legal = full hand at lead.
    S.s.hostHands = { [1]={}, [2]={}, [3]={"KS","KH","7D"}, [4]={} }
    S.s.seats = { [1]={isBot=true},[2]={isBot=true},[3]={isBot=true},[4]={isBot=true} }
    S.s.cumulative = { A=0, B=0 }; S.s.target = 152
    S.s.meldsByTeam = { A={}, B={} }
    -- Force pickRandomTied to pick SECOND tied card.
    local origRandom = math.random
    math.random = function(a, b)
        if a == 2 and b == nil then return 2 end       -- pickRandomTied
        if a == nil then return origRandom() end
        if b == nil then return origRandom(a) end
        return origRandom(a, b)
    end
    local card = Bot.PickPlay(3)
    math.random = origRandom
    -- Pool order is K♠ then K♥ (iteration order from hand). stub→2
    -- ⇒ pickRandomTied returns K♥. Pre-fix would return K♠ (first
    -- iteration), so this assertion would FAIL pre-fix and PASS
    -- post-fix — the behavioral proof.
    assertEq(card, "KH",
        ("BE.1 (F5/D-1 site 1): tied non-trump bosses randomize " ..
         "(stub→2 picks KH; got %s)"):format(tostring(card)))
    WHEREDNGNDB.advancedBots = nil
end
```

Pre-fix behaviour: returns `"KS"` (first iteration of strict-`>`
loop). Test fails.
Post-fix behaviour: returns `"KH"` (stub forces pickRandomTied to
return tied[2]). Test passes.

#### BE.2 — F5 site 1, non-tie behaviour unchanged

**Fixture:** identical to BE.1 except hand is `{"KS","QH","7D"}` —
K♠ (rank 6) > Q♥ (rank 5), unique max. No ties. Whatever the stub
returns, `pickRandomTied` only sees one card.

```lua
-- BE.2: F5 site 1 non-tie behaviour unchanged
do
    -- ... same setup as BE.1 except:
    S.s.hostHands = { [1]={}, [2]={}, [3]={"KS","QH","7D"}, [4]={} }
    -- Stub return any value; only K♠ should ever be returned.
    local origRandom = math.random
    math.random = function(a, b) if a == 2 then return 2 end
                                 if a == nil then return origRandom() end
                                 if b == nil then return origRandom(a) end
                                 return origRandom(a, b) end
    local card = Bot.PickPlay(3)
    math.random = origRandom
    assertEq(card, "KS",
        "BE.2 (F5/D-1 site 1): unique max K♠ returned regardless of stub")
end
```

#### BE.3 — Source-pin

```lua
-- BE.3: source-pin coverage for F5 v3.2.2 site 1 marker
do
    local botSrc = io.open(WHEREDNGN_TESTS_ROOT .. "/Bot.lua"):read("*a")
    assertTrue(botSrc:find("v3%.2%.2 F5 site 1") ~= nil,
        "BE.3a: F5 site 1 marker present in Bot.lua")
    assertTrue(botSrc:find("audit D%-1") ~= nil,
        "BE.3b: audit reference 'D-1' anchored in Bot.lua")
end
```

### §4.3 Test count summary

| Test | Type | Purpose |
|---|---|---|
| BE.1 | behavioural | F5 site 1 — tie randomization wired |
| BE.2 | behavioural | F5 site 1 — non-tie unchanged |
| BE.3 | source-pin (block) | F5 site 1 marker + audit D-1 reference |
| ↳ BE.3a | source-pin | `v3.2.2 F5 site 1` marker present in Bot.lua |
| ↳ BE.3b | source-pin | `audit D-1` reference anchored in Bot.lua |

Total: **4 new checks**. Expected harness delta: `1241 → 1245`.

> **v0.3 amendment (post-Codex implementation review):** BE.3 was
> originally specified as a single source-pin entry. In the actual
> implementation (commit `697cb4d`), BE.3 was split into two
> separate `assertTrue` calls — BE.3a for the version-marker pin
> and BE.3b for the audit-reference pin — so a future regression
> can distinguish "marker was deleted" from "audit reference was
> deleted" without re-running the suite manually. BE.3 is still
> one conceptual test block (one `do ... end`), but it produces
> two harness checks. Net new check count is 4 (not 3); harness
> delta is `1241 → 1245` (not `→ 1244`).

#### Deferred future test ideas (NOT in v3.2.2)

The following two test ideas are recorded here for the future F2
follow-up audit that decides whether to relocate the pos-3
partner-certain branch above the `partnerWinning` early-return at
`Bot.lua:3886`. Once that relocation is designed, these tests
become the wire-proof for F5 site 3's tie-randomization fix.

- **(Deferred) F5 site 3 tie randomization wired** — Sun pos-3
  fixture that genuinely reaches the donate loop (which today is
  impossible). The v0.1 BE.3 fixture set `partnerWinning=true`
  via partner's T♦ lead at pos-1 winning; that fixture would
  short-circuit at the L3886 partnerWinning return instead of
  reaching the L4477 donate loop, so the test would fail for the
  wrong reason. A correct fixture awaits the future relocation
  design.
- **(Deferred) F5 site 3 non-tie behaviour unchanged** — partner
  setup as above with a unique-max donation candidate. Same
  reachability problem until relocation.

### §4.4 Why not statistical tests

Statistical tie-randomization tests (run pickPlay N times, assert
both tied cards appear at least M times each) are tempting for
"belt-and-braces" coverage, but the prompt explicitly biases
against them:

> If a site cannot be tested without brittle statistical
> assertions, recommend deferring that site.

With the `math.random` stub approach, deterministic single-shot
assertions cover both directions cleanly:

- **Tie wired:** stub→2 returns tied[2], which differs from the
  pre-fix's tied[1]. Single assertion proves the new randomization
  path is actually engaged.
- **Non-tie preserved:** stub→2 returns the unique max anyway
  (because `pickRandomTied([one_card]) = one_card`, no random call
  made on a 1-element tied set per L46 `if #tiedSet == 1 then
  return tiedSet[1] end`). Single assertion proves non-tie
  semantics are unchanged.

So 2 deterministic behavioural tests + 1 source-pin block (which
fires 2 distinct assertions, BE.3a + BE.3b — see §4.3 v0.3
amendment) = full coverage of the one approved site with zero
flakiness.

---

## §5 Risk register

| Risk | Likelihood | Severity | Mitigation |
|---|---|---|---|
| Tied bosses where `KH` was previously preferred by hand-iteration order now becomes randomized, producing different per-round outcomes from the same starting state | CERTAIN (this is the intended effect) | LOW — the whole point of v1.1.0 was to make this unpredictable | None needed; this is the fix. Document in CHANGELOG so observer-mode users aren't confused. |
| F5 site 1 fixture (BE.1) sets `Bot._memory[1].played = {AS,AH,AC}` directly — could fail if the in-loop check (L2024-2027) reads memory via a different path | LOW | MED — would cause `sideAcesLeft != 0` and the loop wouldn't enter | Verified during design: L2024 reads `Bot._memory[s2].played[aceCard]` for s2 in 1..4. Setting `Bot._memory[1].played` satisfies the check on seat 1. Test would be debugged early during implementation if the gate doesn't enter. |
| ~~F5 site 3 fixture reachability~~ | N/A | N/A | **Resolved by v0.2 amendment:** F5 site 3 is unreachable under the current pickFollow structure (gate requires `partnerWinning==true` but enclosing partnerWinning block returns first). Reclassified to DEFER. The BE.3/BE.4 tests from v0.1 are removed from the implementation plan. |
| math.random stub leaks to subsequent tests if test crashes mid-stub | LOW | LOW | `math.randomseed(20260503)` is called at L4528 of test_state_bot.lua at section AT boundary, and the existing AS/AT pattern wraps stub assignment in a `local origRandom`. Same pattern used here. |
| Future cleanup batch removes the v3.2.2 F5 source-pin marker | MED | LOW | BE.3 source-pin catches deletion. The behavioural test BE.1 would also fail if the runtime fix is reverted (`stub→2` would no longer change the return). Defense in depth. |
| Conflict with other in-flight branches | LOW (no in-flight branches) | LOW | Branch off current `17a0e95`. |

---

## §6 Recommended branch name

`pickplay-tie-randomization-v3.2.2`

Created off `main` (currently `17a0e95`).

---

## §7 Expected harness delta

Pre-implementation: 1,241 / 0.
Post-implementation: **1,245 / 0** (+4 new BE.* checks: BE.1,
BE.2, BE.3a, BE.3b — see §4.3 v0.3 amendment for the BE.3 split
rationale).

Behavioural test BE.1 **MUST fail pre-fix and pass post-fix** — it
is the wire-proof for F5 site 1's tie-randomization fix. Non-tie
test BE.2 **MUST pass in both pre-fix and post-fix** states — it
pins the behaviour-preserving invariant. Source-pin BE.3a + BE.3b
both **fail pre-fix and pass post-fix** because the v3.2.2 F5
marker and `audit D-1` reference are added by the runtime edit;
writing tests first, both BE.3 assertions fail until the runtime
fix lands.

A 4-check delta is very small relative to the v3.2.1 batch's +22
(BA/BB/CC/CD). Reviewable in a single Codex pass.

---

## §8 Stop conditions for implementation

The implementation branch must STOP and re-design (not silently
proceed) if any of:

1. **BE.1 passes pre-fix.** This would mean the "behavioural
   proof" is testing something else — the assertion structure is
   broken and needs re-thinking before the fix is landed.
2. **BE.2 fails pre-fix.** The non-tie regression-guard should
   always pass; if it fails, the test fixture has a bug (likely a
   misunderstanding of which branch the bot enters) and the
   implementation should not proceed until the fixture is correct.
3. **Harness count regresses below 1,241** at any point during
   implementation. The fix must be purely additive in test
   coverage; any pre-existing test that breaks is a sign the fix
   has unintended scope.
4. **The fix touches anything outside `Bot.lua` and
   `tests/test_state_bot.lua`.** Per the established v3.2.1A scope
   discipline, runtime edits are limited to `Bot.lua` and behavioural
   tests are limited to `tests/test_state_bot.lua`. No `.toc`,
   `.pkgmeta`, workflow, or BotMaster.lua edits (since F6 is
   deferred).
5. **A new tie source is discovered** in F5 site 1 that the
   design pass missed (e.g., cards entering the pool from a third
   suit changing the tied-set size assumptions). The implementation
   must verify the `pickRandomTied([two-card pool])` call site
   matches what the test fixture sets up before claiming green.
6. **F5 site 3 is found to be reachable** under some path the
   v0.2 amendment missed. If a fixture demonstrably reaches the
   donate loop without going through the partnerWinning return,
   stop, re-classify F5 site 3 back to APPROVED, and re-run this
   design pass with the corrected reachability claim. Do not
   silently re-add F5 site 3 to the implementation plan without
   re-review.

If any stop condition fires, the design doc must be updated
(noting the deviation), Codex reviews the updated design, and only
then can implementation resume.

---

## §9 Implementation order (when approved)

1. (Optional) Commit this design doc on `main` first:
   `docs: add v3.2.2 tie-randomization design pass`. This is
   independent of the implementation branch and only useful for
   pinning the doc into git history alongside the v3.2.1 audit.
2. Branch `pickplay-tie-randomization-v3.2.2` off `main`
   (currently `17a0e95`).
3. Write tests BE.1-BE.3 FIRST (BE.3 is one source-pin `do` block
   containing two assertions, BE.3a + BE.3b — see §4.3 v0.3
   amendment). Run harness. Confirm BE.1 FAILS (the behavioural
   proof), BE.2 PASSES (the non-tie regression guard), and both
   BE.3a + BE.3b FAIL until the v3.2.2 F5 marker is added by the
   runtime edit.
4. Apply the runtime edit for F5 site 1 (`Bot.lua:2033-2040`).
   The edit builds a `nonTrumps` filtered pool and routes through
   the existing `highestByRank(nonTrumps, contract)` re-binding.
5. Run harness. Confirm BE.1, BE.2, BE.3a, and BE.3b all PASS.
   Full harness at **1,245 / 0**.
6. Commit: `fix(Bot.lua): F5 site 1 — tie-randomize Hokm side-Ace
   exhaustion (audit D-1)`.
7. Stop. Open for Codex review.

Standalone smokes (H1 + H7) should remain 11/0 and 9/0 throughout
— neither smoke exercises this branch.

---

## §10 Final report mapping

This doc satisfies the prompt's "Output doc" requirements:

| Requirement | Section |
|---|---|
| Executive recommendation: proceed/defer/reject | §0 |
| Inventory table for all 5 sites | §2 |
| Exact proposed code changes | §3 |
| Exact proposed tests | §4 |
| Risk register | §5 |
| Recommended branch name | §6 |
| Expected harness delta | §7 |
| Stop conditions | §8 |
