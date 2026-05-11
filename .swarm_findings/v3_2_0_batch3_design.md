# v3.2.0 Cleanup Batch 3 — Source-Pin Conversion (Design / Inventory Pass)

**Status**: design only, no code changes. Output for Codex review
before implementation.

**Branch baseline**: `main` at `c2e0a99` (post-Batch 2). Working tree
clean. Tests at 1082/1082 pass.

**Goal**: convert 5 low-risk source-pin tests into behavioral tests.
Picks prioritized for: (1) easy fixture, (2) existing nearby
behavioral scaffolding that can be reused, (3) low risk of
introducing flakiness or coverage gaps.

## Inventory summary

- Source-pin assertions in `tests/test_state_bot.lua`:
  **~244 `:find()` calls** across helpers, function-body
  inspections, and structural invariants.
- Existing behavioral sections: AE / AJ / AK / AL / AM / AN /
  AP / AZ. Several are explicit "behavioral counterpart" pairings
  for older source pins.
- Source pins targeted for conversion in this batch: 5 (out of
  many candidates). Conservative scope so each conversion can be
  reviewed individually.

## Selection criteria applied

1. **Pure-logic decision functions** preferred (`Pick*` returns,
   state-machinery side effects) over UI-side or log-format pins.
2. **Existing nearby scaffolding** — at least one behavioral test
   in the same or adjacent section using similar state setup
   (`freshState`, `snapshotS`, `Bot._partnerStyle`, manual
   `S.s.hostHands` injection).
3. **Deterministic** — avoid pins that test randomized sampler
   weights (AI.3) or non-deterministic ISMCTS scoring.
4. **Boundary-testable** — pins on threshold conditions are ideal
   because the boundary fixture is small and unambiguous.

## The 5 picks (ranked lowest risk first)

---

### Pick 1: AD.4a — BotMaster single-card-shortcut diagnostic tag

**Current pin** (`tests/test_state_bot.lua:3668`):
```lua
local bmSrc = io.open(WHEREDNGN_TESTS_ROOT .. "/BotMaster.lua"):read("*a")
assertTrue(bmSrc:find('BM%._lastShortCircuit = "single%-card"') ~= nil,
           "AD.4a (BM-03): BotMaster tags single-card-shortcut path")
```

**Behavior it claims to protect**: when `BotMaster.PickPlay` is
called with a seat that has exactly 1 legal card, the function
short-circuits without running ISMCTS rollouts and tags
`BM._lastShortCircuit = "single-card"` for diagnostic visibility
(used by `/baloot ismctsdiag`).

**Proposed behavioral replacement**:
```lua
-- AD.4a (BM-03) BEHAVIORAL: single-card-shortcut sets diagnostic.
do
    WHEREDNGNDB = { saudiMasterBots = true }   -- enable BotMaster
    freshState()
    S.s.isHost = true
    S.s.contract = { type = K.BID_HOKM, trump = "S", bidder = 1 }
    S.s.phase = K.PHASE_PLAY
    S.s.turn = 2
    S.s.turnKind = "play"
    -- Single legal card: bot holds only 9S, must-follow trump after
    -- a trump-led trick from seat 1.
    S.s.hostHands = { [1] = {}, [2] = { "9S" }, [3] = {}, [4] = {} }
    S.s.trick = { leadSuit = "S",
                  plays = { { seat = 1, card = "AS" } } }
    S.s.tricks = {}
    BM._lastShortCircuit = nil
    local pick = WHEREDNGN.BotMaster.PickPlay(2)
    assertEq(pick, "9S",
        "AD.4a-b1 (BM-03 behavioral): single-card hand returns that card")
    assertEq(BM._lastShortCircuit, "single-card",
        "AD.4a-b2 (BM-03 behavioral): diagnostic tag set to 'single-card'")
end
```

**Fixture setup**:
- Reuses `freshState()` (already used across section A/B/C/D)
- Single-card `hostHands[seat]` injection (used in many existing tests)
- BotMaster enabled via `WHEREDNGNDB.saudiMasterBots = true`

**Nearby scaffolding**: `tests/test_state_bot.lua:633-823` Section
D (Headless tournament) configures BotMaster similarly. The
`botmaster` test suite at `tests/test_botmaster.lua` has direct
BotMaster.PickPlay setup patterns this can mirror.

**Risk**: **LOWEST**. Pure state observation, no scoring math, no
randomness, single function call.

---

### Pick 2: AC.6 — PickFour unconditional +5 partner-open-Bel bonus

**Current pin** (`tests/test_state_bot.lua:3617-3626`):
```lua
local botSrc = io.open(WHEREDNGN_TESTS_ROOT .. "/Bot.lua"):read("*a")
local fnStart = botSrc:find("function Bot%.PickFour")
if fnStart then
    local body = botSrc:sub(fnStart, fnStart + 2500)
    assertTrue(body:find("strength = strength %+ 5") ~= nil,
               "AC.6 (P4-1 / DEAD-1): PickFour applies unconditional +5 partner-open-Bel bonus")
end
```

**Behavior it claims to protect**: `Bot.PickFour` adds +5 to the
defender's strength score before comparing against the fire
threshold. This compensates for the implicit "partner already
believed enough to Bel open" signal — without it, defenders
under-fire Four.

**Proposed behavioral replacement**:
```lua
-- AC.6 BEHAVIORAL: PickFour +5 bonus shifts the fire threshold.
do
    WHEREDNGNDB = { advancedBots = true }
    freshState()
    S.s.isHost = true
    S.s.contract = {
        type = K.BID_HOKM, trump = "S", bidder = 1,
        doubled = true, doublerSeat = 2, belOpen = true,
        tripled = true, tripleOpen = true,
    }
    S.s.phase = K.PHASE_FOUR
    -- Construct a hand near the Four threshold. If +5 bonus is
    -- applied, the bot Fours; if removed, it skips. The exact
    -- hand-shape can be calibrated by running once and observing
    -- where the boundary lies.
    --
    -- Working assumption: a defender hand with 1 trump A + 1
    -- side A is just-below threshold without the bonus, just-above
    -- with it. Two-direction assertion:
    --   * With bonus (current code): PickFour returns yes=true
    --   * Without bonus (hypothetical): would return false
    -- Test asserts only the positive direction; the boundary
    -- calibration ensures the +5 is load-bearing.
    S.s.hostHands = { [1] = {}, [2] = {
        "AS",   -- trump Ace (high)
        "KH", "QH", "JH",   -- side suit support
        "9D", "8D", "7D", "AC",
    }, [3] = {}, [4] = {} }
    S.s.cumulative = { A = 0, B = 0 }
    local yes, _ = Bot.PickFour(2)
    assertTrue(yes,
        "AC.6 behavioral: PickFour fires at threshold (incl. +5 partner-open bonus)")
end
```

**Fixture setup**:
- Standard `freshState()` + `S.s.contract` escalated to PHASE_FOUR
- Single-seat `hostHands[2]` for the defender being evaluated
- No randomness; deterministic threshold comparison

**Nearby scaffolding**: `AK.7 (cluster 7 FLOOR-3 behavioral, line
5675+)` already tests `Bot.PickTriple` with a calibrated boundary
hand — this is the closest pattern.

**Risk**: **LOW**. The +5 is a fixed integer offset; finding a
single hand at the boundary requires a one-time calibration but
the resulting test is deterministic.

---

### Pick 3: AI.6 — saveForPartnerTouch in pickFollow smother

**Current pin** (`tests/test_state_bot.lua:5094-5098`):
```lua
local botSrc = io.open(WHEREDNGN_TESTS_ROOT .. "/Bot.lua"):read("*a")
assertTrue(botSrc:find("saveForPartnerTouch") ~= nil,
           "AI.6 (agent #6): pickFollow smother reads partner topTouchSignal")
```

**Behavior it claims to protect**: the pickFollow smother branch
reads `Bot._partnerStyle[partner].topTouchSignal[leadSuit]` and
sets `saveForPartnerTouch = true` when the partner has shown a
touching-honor signal, filtering A/T out of the donate candidate
set.

**Proposed approach** — **DOWNGRADE TO REFERENCE COMMENT**:

`AK.4 (line 5442+)` is already the full behavioral counterpart of
AI.6 — it sets up `Bot._partnerStyle[1].topTouchSignal.H.nextDown
= "K"`, calls `Bot.PickPlay(3)`, and asserts the returned card is
`QH` (highest non-A/T point card). The AI.6 source pin is purely
redundant with AK.4's coverage.

**Proposed behavioral replacement** (replace AI.6 entirely):
```lua
-- AI.6 (agent #6): pickFollow smother reads partner topTouchSignal.
-- Source-pin retired in v3.2.0 batch 3 — the behavior is exhaustively
-- exercised by AK.4 (touching-honors save → donate Q instead of A/T).
-- If AK.4 regresses, this branch's wiring is the most likely cause.
-- Cross-reference only; no separate assertion.
```

**Fixture setup**: NONE. The behavior is already covered.

**Nearby scaffolding**: AK.4 IS the scaffolding.

**Risk**: **LOWEST** (this is a deletion-with-reference, not a
behavioral rewrite). Zero risk of coverage loss because AK.4
already enforces the same invariant end-to-end.

---

### Pick 4: AC.4 — Sun Bel-fear gate uses strict > 100

**Current pin** (`tests/test_state_bot.lua:3593-3598`):
```lua
local botSrc = io.open(WHEREDNGN_TESTS_ROOT .. "/Bot.lua"):read("*a")
assertTrue(botSrc:find("myTotal > K%.SUN_BEL_CUMULATIVE_GATE then") ~= nil,
           "AC.4 (BG-1): Sun Bel-fear gate uses strict > 100 (matches R.CanBel)")
```

**Behavior it claims to protect**: in Sun contracts, the Bel-fear
suppression (which dampens defender Bel decisions when the
defender team is "ahead" cumulative) uses **strict greater-than**
comparison `myTotal > 100` — not `>=`. This matches Saudi rule
("bidder fails on tied half-and-half") so a defender at exactly
100 is still ahead and should NOT be suppressed.

**Proposed behavioral replacement**:
```lua
-- AC.4 BEHAVIORAL: Sun Bel-fear strict>100 boundary.
do
    WHEREDNGNDB = { advancedBots = true }
    freshState()
    S.s.isHost = true
    S.s.contract = { type = K.BID_SUN, trump = nil, bidder = 1 }
    S.s.phase = K.PHASE_DOUBLE
    -- Defender (seat 2, team B) hand calibrated to FIRE Bel without
    -- the cumulative penalty. Cumulative.B = 100 (boundary).
    S.s.hostHands = { [1] = {}, [2] = {
        "AH", "KH", "QH", "JH", "9H", "AS", "AD", "AC",
    }, [3] = {}, [4] = {} }
    S.s.cumulative = { A = 0, B = 100 }
    S.s.belPending = { 2, 4 }
    local yes, _ = Bot.PickDouble(2)
    assertTrue(yes,
        "AC.4 behavioral: Bel still fires at exactly 100 (strict > gate, not >=)")
    -- Counter-direction: at 101, suppression kicks in. Same hand
    -- but cumulative bumped above strict gate.
    S.s.cumulative = { A = 0, B = 101 }
    local yesAt101, _ = Bot.PickDouble(2)
    -- Asserting a specific outcome at 101 is bolder; safer to
    -- assert that the strength delta drops below threshold. For
    -- now: just check the boundary in the YES direction. Codex can
    -- decide whether to require both directions during review.
end
```

**Fixture setup**:
- Standard `freshState()` + Sun contract + PHASE_DOUBLE
- `S.s.cumulative.B = 100` (the boundary value)
- A strong defender hand (calibrated to fire Bel at the boundary)
- `S.s.belPending` set to include seat 2

**Nearby scaffolding**: `AK.7 (cluster 7 FLOOR-3 behavioral)` is
the closest pattern for "threshold-boundary PickDouble/PickTriple"
testing. `AJ.1` and `AJ.6` also exercise `S.s.cumulative`-driven
decisions.

**Risk**: **LOW-MEDIUM**. The hand calibration is the only soft
point — picking a hand that demonstrably fires at exactly 100 is
straightforward, but verifying the precise boundary requires a
small one-time calibration pass. Single-direction assertion (YES
at 100) is safer; counter-direction (NO at 101) is bolder.

---

### Pick 5: AH.4 — BM-04-FALLBACK void-respecting two-pass

**Current pin** (`tests/test_state_bot.lua:5007-5014`):
```lua
local botMasterSrc = io.open(WHEREDNGN_TESTS_ROOT .. "/BotMaster.lua"):read("*a")
assertTrue(botMasterSrc:find("Pass 1: void%-respecting allocation") ~= nil,
           "AH.4a (BM-04-FALLBACK): fallback has void-respecting Pass 1")
assertTrue(botMasterSrc:find("Pass 2:.*give%-up") ~= nil,
           "AH.4b (BM-04-FALLBACK): fallback has give-up Pass 2 only when Pass 1 under-fills")
```

**Behavior it claims to protect**: in the BotMaster ISMCTS
`sampleConsistentDeal` fallback path (when the constraint solver
can't produce a fully consistent deal), there are TWO passes:
- Pass 1: respect every observed void (`rolloutMemory[opp].void[suit]`)
- Pass 2: only fires if Pass 1 under-fills hands; ignores void
  constraints as a last resort

**Proposed behavioral replacement**:
```lua
-- AH.4 BEHAVIORAL: void-respecting fallback Pass 1.
do
    -- Setup: simulate a rollout state where opp seat 3 is known
    -- VOID in suit S (observed by Bot.OnPlayObserved). Force the
    -- fallback path by setting up a determinization with a
    -- minimal/contradictory unseen pool. Then call the sampler
    -- and assert that seat 3's hand contains zero S cards.
    --
    -- The exact mechanism: BotMaster has a sampleConsistentDeal
    -- helper that handles assignment. The test inspects the
    -- post-sample state and verifies void respect.
    --
    -- ALTERNATIVE: if the sampler is fully private, a behavioral
    -- test may not be feasible without exporting an internal
    -- helper. In that case, this pin stays as source-only —
    -- replace with a more targeted source pin (e.g., on the
    -- specific void-check predicate inside Pass 1) OR retain
    -- as-is.
end
```

**Fixture setup**: Possibly REQUIRES exporting an internal helper
for inspection. The BotMaster sampler is normally invoked
indirectly via `BotMaster.PickPlay`. Verifying Pass 1's
void-respect end-to-end means running many rollout worlds and
sampling the resulting `S.s.hostHands` snapshots — flaky.

**Nearby scaffolding**: `tests/test_botmaster.lua` has BotMaster
internal-state assertions (sections B/C/D). Could be extended.

**Risk**: **MEDIUM**. Convertibility is uncertain without an
exported test hook. RECOMMENDATION: defer if Codex agrees the
sampler is too internal; instead retire AH.4a/b in favor of an
existing behavioral assertion that the fallback produces
valid (non-crashing) plays on heavily-voided opp memories. If
that doesn't exist, RETAIN AH.4 as source-only.

**Alternative Pick 5** if AH.4 proves too risky: **AC.5 (PickOvercall
mirrors Bel-fear bias)**. Section H has an existing Sun-overcall
state-machine test scaffolding (lines 1345-1572). Convert by
setting up `S.s.cumulative.A > 100` and calling `Bot.PickOvercall`,
asserting the returned strength estimate is reduced.

## Migration plan (if Codex approves any subset)

For each approved pick:
1. Add the behavioral replacement to the appropriate section
   (likely AE / AJ / AK / AZ).
2. Either DELETE the source pin entirely (Picks 1, 3 — strongest
   case) or RETAIN it as a thin pointer comment marker (Picks 2,
   4 — defense-in-depth).
3. Run `python tests/run.py` — expect prior test count + new
   behavioral pins added (1082 → ~1090 depending on subset).
4. Codex reviews diff.
5. Merge.

## Risks not in individual pick assessments

- **Calibration drift**: Picks 2 and 4 require a hand-shape just
  past a threshold. If `BOT_BEL_TH` or related constants change in
  a future calibration pass, the behavioral test could fail
  spuriously. Mitigation: write the assertion in terms of "fires"
  vs "doesn't fire" at a single boundary value, not absolute
  strength numbers.

- **AH.4 sampler internals**: as noted, AH.4 may not be safely
  convertible without exposing an internal helper. Better to drop
  AH.4 from this batch than to force a brittle test.

- **AK.4 covers AI.6**: confirmed via reading both tests. Picking
  AI.6 for retirement is safe IF AK.4 itself isn't fragile —
  reviewing AK.4 separately is recommended before retiring AI.6.

## Recommendation

**Approve Picks 1, 2, 3, 4** for Batch 3 implementation.
**Defer Pick 5 (AH.4)** unless Codex sees a clean conversion
path. If deferred, substitute **AC.5 (PickOvercall Bel-fear)** as
the 5th pick.

Expected delta:
- Picks 1+2+4 add ~6-10 new behavioral assertions
- Pick 3 retires 1 redundant source pin
- Net test-count change: roughly **+5 to +8 pins**

## Files this batch will touch

If approved as-is:
- `tests/test_state_bot.lua` (additions in AE/AK/AZ sections,
  modification at AI.6, AC.4, AC.6, AD.4a)
- No source code changes in `Bot.lua` / `BotMaster.lua` / `Net.lua`

## Out of scope for Batch 3

- Don't touch retry/network code (covered by Batches 1-2)
- Don't refactor unrelated source pins
- Don't introduce new fixture utilities (reuse existing
  `freshState`, `snapshotS`)
- Don't change shipped behavior — this batch is test-coverage
  refactor only
