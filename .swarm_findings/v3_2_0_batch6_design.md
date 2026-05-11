# v3.2.0 Cleanup Batch 6 — Design / Inventory Pass

Status: design pass only. No runtime code changed. No tests changed.
Working tree limited to this doc.

Base: `main` at `256dd97` (post-cleanup checkpoint amend).
Cleanup batches 1-5C merged + bel-quality shim + H7 comment polish +
checkpoint doc + amend. v3.1.14 remains the last shipped CurseForge
tag. Full harness baseline: **1150 / 1150**.

Goal: pick 3-6 source-pin → behavioral conversions that reduce the
friction blocking a future `Bot/Bidding.lua` or `Bot/Escalation.lua`
extraction.

---

## 1. Source-Pin Inventory

Pins in `tests/test_state_bot.lua` that anchor on Bot.lua source
inside the bidding / escalation surfaces. Line numbers are 1-based.

### 1A. Bidding-area pins (block `Bot/Bidding.lua`)

| Pin ID | Line | Anchors | Protects | Convertibility |
|---|---|---|---|---|
| R.2a | 2684 | `local function btrace` inside Bot.PickBid | diagnostic helper exists | HIGH (debug-only; not behavior) |
| R.2b | 2686 | `WHEREDNGNDB.debugBidcalc` | trace short-circuits when off | HIGH (debug-only) |
| R.2c | 2689 | `"R1 direct Sun"` | trace covers R1 Sun decision | HIGH (string literal) |
| R.2d | 2691 | `"R2 Sun fires"` | trace covers R2 Sun decision | HIGH (string literal) |
| R.2e | 2693 | `btrace("hand=` | trace logs hand+thresholds | HIGH (debug-only) |
| T.2b | 2730 | `math.min(penalty, K.BOT_SUN_VOID_PENALTY_CAP)` in sunStrength | void-penalty cap = 8 | MEDIUM (`sunStrength` is local; reach via PickBid + massive-void hand) |
| T.2c | 2732 | `math.min(penalty, 18)` ABSENT | old 18-cap removed | MEDIUM (absence assertion) |
| T.3a | 2751 | `hasTrumpA, hasTrumpNine` in hokmMinShape | flag declaration | HIGH (variable name) |
| T.3b | 2753 | `hasTrumpNine or hasTrumpA` | count==2 gate | MEDIUM (reachable via PickBid R2) |
| W.1 | 3075 | `aceCount == 2 ... K.BOT_SUN_2ACE_BONUS` in PickBid | 2-Ace Sun bonus | LOW (behavioral W.2 already exists for this hand) |
| X.1c | 3177 | `K.BOT_OVERCALL_VOID_TRUMP_BONUS` in PickOvercall | overcall void bonus | MEDIUM (reachable via PickOvercall fixture) |
| X.1d | 3179 | `trumpCount == 0` in PickOvercall | void check | MEDIUM (same) |
| X.2 | 3197 | `count >= 3 and hasTrumpNine` in hokmMinShape | self-sufficient mardoofa path | MEDIUM (reachable via PickBid Hokm R2) |
| X.2b | 3204 | (ordering: new path before L07 gate) | branch order | HIGH (ordering assertion) |
| X.3a | 3222 | `local hypHand = withBidcard(hand, S.s.bidCard)` in PickBid | R1 Hokm-on-flipped uses bidcard | LOW (behavioral X.4 already exists) |
| X.3b | 3224 | `hokmMinShape(hypHand, bidCardSuit)` | hypHand passed to shape eval | LOW (behavioral X.4 already exists) |
| **Y.1** | **3270** | **`local function withBidcard(hand, bidcard)`** | **helper at file scope** | **LOW (behavioral AE.1 + AE.1c already exercise withBidcard end-to-end)** |
| **Y.2** | **3282** | **`hasKsuit and hasQsuit and count >= 2`** in hokmMinShape | **Belote K+Q escape clause** | **MEDIUM (reachable via PickBid R2 with K+Q+1 trump no J)** |
| Y.2b | 3288 | (ordering: Belote escape before J-floor) | branch order | HIGH (ordering assertion) |
| Y.3a-d | 3303-3318 | `withBidcard` calls in PickBid/PickPreempt/PickOvercall | bidcard included before shape eval | MEDIUM (4 pins; behavioral coverage via AE.1, X.4, plus would need new PickPreempt/PickOvercall behavioral) |
| Z.1 | 3386 | `belote = beloteSuit(withBidcard(hand, S.s.bidCard))` | belote computed post-bidcard | LOW (behavioral via existing Belote tests) |
| Z.2 | 3399 | (ordering: hypHand precedes trumpCount loop) | ordering inside PickOvercall | HIGH (ordering assertion) |
| Z.3 | 3408 | `aceCountAndMardoofa(sunHand)` | mardoofa recomputed post-bidcard | LOW (behavioral W.2 covers it) |
| Z.5 | 3424 | `hypHand[#hypHand + 1] = S.s.bidCard` ABSENT | inline build replaced | HIGH (absence assertion of refactor) |
| AA.4 | 3480 | `local function bidderHoldsBidcard(seat, card)` | helper exists | MEDIUM (helper is local; behavioral test would route through PickPlay/PickAKA) |
| AB.3 | 3532 | `S.s.phase ~= K.PHASE_PLAY` in bidderHoldsBidcard | phase gate | MEDIUM (helper is local; behavioral via PickAKA at PHASE_DEAL2BID) |

### 1B. Escalation-area pins (block `Bot/Escalation.lua`)

| Pin ID | Line | Anchors | Protects | Convertibility |
|---|---|---|---|---|
| AA.1a | 3443 | `voidCount * 5` in escalationStrength | void bonus | MEDIUM (reachable but escalationStrength is local) |
| AA.1b | 3445 | `sideAces - 1` in escalationStrength | side-Ace bonus | MEDIUM (same) |
| **AA.1c** | **3451** | **`"Sun has no Triple/Four/Gahwa rungs"`** | **Sun-no-rungs documentation** | **LOW (comment only; can retire if behavioral AB.1 / Sun-Pick* tests already cover the early return)** |
| **AB.1** | **3506** | **`elseif contract.type == K.BID_SUN then` ABSENT** | **Sun dead branch removed** | **LOW (behavioral: PickDouble/Triple/Four/Gahwa under Sun contract returns false; covered by Sun-no-rungs invariant)** |
| AB.2 | 3519 | `DEAD-2` comment in PickGahwa | floor-cap removal rationale | HIGH (comment-only) |
| AD.3 | 3739 | same as AB.2 | floor-cap removal rationale | HIGH (comment-only; duplicate) |
| AD.7a | 3783 | `local function eltrace` in PickDouble | diagnostic helper exists | HIGH (debug-only) |
| AD.7b | 3785 | `"PickDouble eval: strength="` | diagnostic format | HIGH (debug-only) |
| AH.3 | 5083 | `th < K.BOT_TRIPLE_TH - 16 then th = ...` in PickTriple | floor cap | MEDIUM-HIGH (requires inflection state setup) |
| AH.6 | 5111 | `seatIsBidder` in partnerBidBonus | bidder vs defender split | MEDIUM (local helper) |
| AH.7 | 5122 | `"neutralize Sun-only penalty"` comment | escalationStrength rationale | HIGH (comment-only) |
| AI.1 | 5133 | `v1.0.4 (agent #1): urgency-aware swing` | comment marker | HIGH (comment-only) |
| AI.2a/b | 5143-5145 | tiered smother gate branches | escalation-aware smother | MEDIUM (deep behavioral fixture; pickFollow only) |
| AI.4 | 5161 | `v1.0.4 (agent #4)` comment | bid-history inflection | HIGH (comment-only) |
| AI.5 | 5169 | `"Bargiya receiver phase-split"` | comment marker | HIGH (comment-only) |

### 1C. PickSWA / PickSWAResponse pins

| Pin ID | Line | Anchors | Protects | Convertibility |
|---|---|---|---|---|
| **Q.1** | **2615** | **`if #hand <= 1 then return false end`** | **PickSWA short-circuit** | **LOW (trivial boundary test)** |
| **Y.5** | **3337** | **`if not hand or #hand == 0 or #hand > 6 then return false end`** | **PickSWA outer guard (cap = 6)** | **LOW (boundary tests at 0 / 7)** |
| Y.6a | 3344 | `function Bot.PickSWAResponse` | function defined | LOW (presence test) |
| Y.6b | 3348 | `B.Bot.PickSWAResponse` in Net.lua | wired into _OnSWAReq | MEDIUM (behavioral test would need full SWA-vote flow) |

### 1D. PickAKA / PickPreempt / PickOvercall body pins

| Pin ID | Line | Anchors | Protects | Convertibility |
|---|---|---|---|---|
| X.1c+d | 3177-3179 | (see 1A bidding) | PickOvercall void bonus | MEDIUM |
| **Y.7** | **3360** | **`if trickNum <= 1 then return nil end` ABSENT** | **PickAKA trick-1 suppression dropped** | **LOW-MEDIUM (behavioral: trickNum=1 partner-led-A scenario expects non-nil AKA)** |
| Y.8a-c | 3369-3373 | `hasT and count == 1`, `hasT and count == 2`, `partnerIsSunBidder` | Tahreeb-return decision tree branches | MEDIUM (Tahreeb-return is reachable via PickAKA + S.s.swaTahreeb setup) |
| AC/AD areas | various | PickGahwa / PickPreempt internals | many | MIXED |

---

## 2. Behavioral Convertibility Summary

### High-value LOW-risk conversions (immediate candidates)

| Pin | Replacement | Rationale |
|---|---|---|
| **Q.1 + Y.5** | New AJ.10: PickSWA hand-size boundary tests at 0/1/7 cards | Both pins protect the same guard cluster; one new test block retires two pins. Pure boundary; no random override. |
| **Y.7** | New AJ.11: PickAKA fires at trickNum=1 | Behavioral counterpart for the dropped suppression. Advanced tier + partner-A-lead fixture. |
| **Y.2** | New AJ.12: hokmMinShape Belote K+Q escape via PickBid R2 | K+Q+1 trump + no J + R2 → Hokm fires (was PASS pre-fix). Determinism via strong-hand selection. |
| **AA.1c + AB.1** | Single combined retirement: cite existing Sun-contract escalation invariant from AE-section behavioral tests; behavioral AJ.13 confirms Bot.PickDouble/Triple/Four/Gahwa all return false under Sun | The "Sun has no rungs" comment pin and the absence-of-Sun-branch pin both protect the same invariant. Behavioral test exercises all 4 deciders under Sun. |
| **Y.1** | RETIRED with citation to AE.1 / AE.1c | `withBidcard` is exercised end-to-end every time AE.1 succeeds: the K+Q+side-Ace fixture is sub-threshold WITHOUT bidcard inclusion, so AE.1 returning HOKM:S only passes if withBidcard correctly folded `7S` into hypHand. No new test needed. |

### Existing behavioral fixtures available for reuse

- `snapshotS(...)` helper in test_state_bot.lua line 3829 — already pattern for the AE-section.
- `WHEREDNGNDB.advancedBots` flag flip — used by AE.X, AK.X tests.
- `S.s.hostHands` setup with `S.s.bidRound`, `S.s.bidCard`, `S.s.dealer`, `S.s.cumulative`, `S.s.bids` snapshot — standard PickBid fixture from W.2, X.4, AE.1.
- For escalation: `S.s.contract = { type = K.BID_HOKM, trump = "H", bidder = 1, doubled = true }` pattern — used by PickTriple/Four/Gahwa tests in AC/AD sections.

### Pins that should remain source-only for now

- All "agent #N" comment markers (AI.1 / AI.4 / AI.5) — they pin discoverability, not behavior.
- Diagnostic helpers (R.2a-e btrace, AD.7a/b eltrace) — debug-mode wiring; converting to behavioral would require capturing print output, out of scope.
- Ordering assertions (Y.2b, X.2b, Z.2) — these test source-position relationships; behavioral equivalents would be complex and add little value beyond the pin.
- Absence assertions of refactored-away code (T.2c old 18-cap, Z.5 inline bidcard) — protect against regression to old form; structural and cheap.

### Pins that block extraction but are tricky to convert

- T.3a/b (hokmMinShape internal flags) — would require fully exercising mardoofa cases through PickBid R2.
- AA.4 / AB.3 (bidderHoldsBidcard) — helper is local; behavioral path is PickAKA → bidderHoldsBidcard → result observation. Workable but multi-step.
- AH.3 (PickTriple floor cap) — requires constructing the inflection state that knocks `th` very low.
- AI.2a/b (tiered smother gate) — deep pickFollow fixture; high complexity.

---

## 3. Recommended Batch 6 Implementation Scope

**5 picks: 1 retirement + 4 new behavioral tests, replacing 7 source pins.**

| Action | Replaces | Risk | Tests Δ |
|---|---|---|---|
| Retire Y.1 (cite AE.1 / AE.1c) | Y.1 (1 pin) | LOW | -1 |
| Add AJ.10 (PickSWA boundaries) | Q.1 + Y.5 (2 pins) | LOW | +3 −2 = +1 net |
| Add AJ.11 (PickAKA trick-1) | Y.7 (1 pin) | LOW-MEDIUM | +1 −1 = 0 net |
| Add AJ.12 (Belote K+Q escape) | Y.2 (1 pin) | MEDIUM | +1 −1 = 0 net |
| Add AJ.13 (Sun-no-rungs invariant) | AA.1c + AB.1 (2 pins) | LOW | +4 −2 = +2 net |
| | | **Total** | **+2 net** |

Test count delta breakdown: **+9 behavioral asserts** (3 in AJ.10 + 1 in AJ.11 + 1 in AJ.12 + 4 in AJ.13), **−7 source-pin asserts retired** (Y.1, Q.1, Y.5, Y.7, Y.2, AA.1c, AB.1). Net: **+2**. Final count if implemented: 1150 + 2 = **1152**.

### Why this scope, not more?

- The four conversions all target Bot/Bidding.lua + Bot/Escalation.lua surfaces — exactly the extractions the checkpoint flagged next.
- Five picks fit comfortably in a single batch for Codex review (Batch 3 was 4 pins, Batch 4A was multi-area; 5 here is mid-range).
- Only AJ.12 requires a `math.random` jitter freeze (arity-aware shim — same shape as commit `08473ce`). AJ.10 (PickSWA boundary guards), AJ.11 (PickAKA lead-only trick-1 fixture), AJ.13 (Sun-no-rungs invariant) all complete without any random override because they exit on guards before jitter is sampled.
- None require exposing internal helpers as new exports.
- Avoids high-risk conversions (sampler / UI / network).

### Why not retire more pins?

The pins I'm leaving in (T.2b/c, T.3a/b, AA.1a/b, X.1c/d, X.2, AA.4, AB.3) are all reachable behaviorally but each conversion is multi-step or requires deeper fixtures. A second prep batch (Batch 7) can pick those up after Batch 6 lands and proves the pattern at lower risk. The checkpoint document's recommendation was specifically "3-6 pins"; landing 5 conversions of low/medium risk is the right scope.

---

## 4. Per-Pin Implementation Sketches

### 4A. Retire Y.1 (`withBidcard` helper exists)

**Current pin (lines 3268-3272):**
```lua
do
    local botSrc = io.open(WHEREDNGN_TESTS_ROOT .. "/Bot.lua"):read("*a")
    assertTrue(botSrc:find("local function withBidcard%(hand, bidcard%)") ~= nil,
               "Y.1 (A1): withBidcard helper defined at file scope")
end
```

**Replacement:**
```lua
-- Y.1 (v3.2.0 cleanup batch 6): source pin RETIRED. AE.1 + AE.1c
-- both exercise withBidcard end-to-end — they build K+Q+side-Ace
-- hands that are sub-threshold WITHOUT the bidcard's spades joining
-- hypHand, then call Bot.PickBid and assert HOKM:S (AE.1) / PASS
-- (AE.1c). If withBidcard regresses (e.g. stops folding the
-- bidcard into hypHand), AE.1 stops firing HOKM:S — the test
-- fails loud. No incremental coverage added by a structural pin.
```

**Why the protected logic would fail if regressed:** if `withBidcard` were inlined wrong (e.g. mutated `hand` instead of returning a copy, or omitted the bidcard), AE.1's `KS QS 7H 8C AD` hand would not see spades count=3 after adding bidcard `7S`, BC-MANDATORY would not bypass, raw strength would be 14 (sub-threshold), result would be PASS — AE.1 fails loud.

**Test count delta: -1.**

### 4B. AJ.10 (NEW) — PickSWA hand-size boundaries (replaces Q.1 + Y.5)

**Current pins (lines 2609-2618 and 3335-3339):**
```lua
-- Q.1
local fnStart = botSrc:find("function Bot%.PickSWA")
local body = botSrc:sub(fnStart, fnStart + 1500)
assertTrue(body:find("if #hand <= 1 then return false end") ~= nil, ...)

-- Y.5
assertTrue(botSrc:find("if not hand or #hand == 0 or #hand > 6 then return false end") ~= nil, ...)
```

**Replacement (single block, 3 asserts):**
```lua
-- AJ.10 (v3.2.0 cleanup batch 6, replaces Q.1 + Y.5 source pins):
-- behavioral counterpart for Bot.PickSWA's hand-size guards. The
-- guards short-circuit on:
--   * #hand == 0 (no cards to claim)
--   * #hand == 1 (just play the card; no SWA needed)
--   * #hand > 6 (cap raised from 4 → 6 in v0.11.16 A5; above the
--     cap, the bot will not initiate SWA)
-- All three return paths yield `false`.
do
    local restore = snapshotS({
        "phase", "contract", "hostHands", "localSeat", "isHost",
    })
    S.s.phase     = K.PHASE_PLAY
    S.s.contract  = { type = K.BID_HOKM, trump = "H", bidder = 1 }
    S.s.isHost    = true
    S.s.hostHands = {}
    -- Empty hand → false.
    S.s.hostHands[1] = {}
    assertEq(Bot.PickSWA(1), false,
             "AJ.10a (PickSWA guard): empty hand returns false")
    -- 1-card hand → false.
    S.s.hostHands[1] = { "AS" }
    assertEq(Bot.PickSWA(1), false,
             "AJ.10b (PickSWA guard): 1-card hand returns false")
    -- 7-card hand → false (>6).
    S.s.hostHands[1] = { "AS", "KS", "QS", "JS", "TS", "9S", "8S" }
    assertEq(Bot.PickSWA(1), false,
             "AJ.10c (PickSWA guard): 7-card hand exceeds cap, returns false")
    restore()
end
```

**Why it would fail if regressed:** if either guard is removed, Bot.PickSWA would enter the substantive SWA-evaluation path with #hand outside the supported range. The empty-hand case would index `hand[1]` which is nil — likely error or false anyway; the 1-card case would attempt an SWA claim with no out-card to commit; the 7-card case would over-fire SWAs at hand sizes the bot is not calibrated for. The behavioral test catches all three deviations.

**Test count delta: +3 new asserts, -2 source pins (Q.1, Y.5) = +1 net.**

### 4C. AJ.11 (NEW) — PickAKA fires at trickNum=1 (replaces Y.7)

**Current pin (lines 3352-3363):**
```lua
local fnStart = botSrc:find("function Bot%.PickAKA")
local body = botSrc:sub(fnStart, fnStart + 5000)
assertTrue(body:find("if trickNum <= 1 then return nil end") == nil,
           "Y.7 (A6 / H-1): trick-1 AKA suppression dropped")
```

**Replacement:**

`Bot.PickAKA` is a **lead-only** decider — it runs when the seat is the leader (no plays yet in the trick) and refuses to announce on the Ace itself (an AKA announces "I hold the boss of suit X" so that partners can route plays through; announcing your own Ace would surrender hand-info). The earlier fixture sketch in this doc had partner already played `7S` and seat-1 holding `AS`, which Bot.PickAKA correctly rejects (not a lead position, and Ace is the would-be announcement). The corrected fixture is lead-only, the would-be AKA suit's boss is `K` (held by the seat), and `S.HighestUnplayedRank` is stubbed (J.1 pattern) so the boss check resolves deterministically.

```lua
-- AJ.11 (v3.2.0 cleanup batch 6, replaces Y.7 source pin):
-- behavioral counterpart for the v0.11.16 A6 fix that dropped the
-- trick-1 AKA suppression. Pre-fix, Bot.PickAKA short-circuited to
-- nil on trick 1; post-fix the bot can declare AKA on the opening
-- trick. Setup (lead-only, J.1 pattern): seat 2 is leader on trick
-- 1 of a Hokm-S round, hand contains KH (boss of H), all seats are
-- bots so AKA-receiver doesn't matter, S.HighestUnplayedRank is
-- stubbed so suit H returns "K" (boss = KH).
-- Expected: PickAKA returns "H" (the AKA suit).
do
    local restore = snapshotS({
        "phase", "contract", "hostHands", "trick", "tricks",
        "playedCardsThisRound", "seats", "cumulative",
        "localSeat", "akaCalled",
    })
    local prevAdvanced = WHEREDNGNDB.advancedBots
    WHEREDNGNDB.advancedBots = true

    S.s.phase = K.PHASE_PLAY
    S.s.contract = { type = K.BID_HOKM, trump = "S", bidder = 1 }
    S.s.hostHands = { [2] = { "KH", "9C", "8D", "7H", "QS" } }
    S.s.tricks = {}                         -- trickNum = 1
    S.s.trick = { leadSuit = nil, plays = {} } -- lead-only, no one has played
    S.s.playedCardsThisRound = {}
    S.s.cumulative = { A = 0, B = 0 }
    S.s.seats = {
        [1] = { isBot = true }, [2] = { isBot = true },
        [3] = { isBot = true }, [4] = { isBot = true },
    }
    if Bot.ResetMemory then Bot.ResetMemory() end

    local origHUR = S.HighestUnplayedRank
    S.HighestUnplayedRank = function(suit)
        if suit == "H" then return "K" end
        if suit == "S" then return "J" end
        return origHUR and origHUR(suit) or nil
    end

    local aka = Bot.PickAKA(2, "KH")

    S.HighestUnplayedRank = origHUR
    WHEREDNGNDB.advancedBots = prevAdvanced
    restore()

    assertEq(aka, "H",
             "AJ.11 (A6 / H-1): PickAKA fires on trick 1 (suppression dropped)")
end
```

**Why it would fail if regressed:** if the `if trickNum <= 1 then return nil end` short-circuit re-appeared, `Bot.PickAKA(2, "KH")` returns `nil` on this exact lead-only trick-1 fixture, and the assert fails.

**Test count delta: +1 new assert, -1 source pin = 0 net.**

### 4D. AJ.12 (NEW) — hokmMinShape Belote K+Q escape (replaces Y.2)

**Current pin (lines 3274-3292):**
```lua
local fnStart = botSrc:find("local function hokmMinShape")
local body = botSrc:sub(fnStart)
local nextFn = body:find("\nlocal function ", 2, true)
if nextFn then body = body:sub(1, nextFn) end
assertTrue(body:find("hasKsuit and hasQsuit and count >= 2") ~= nil, ...)
-- + Y.2b ordering assertion (kept separately; ordering pin stays)
```

**Replacement:** keep Y.2b (ordering) as source pin; convert only Y.2 (the substantive Belote-escape branch existence) to behavioral. The fixture below pins the K+Q-of-trump Belote escape using an arity-aware `math.random` jitter freeze so the bid threshold is exact (no probabilistic dependence on jitter rolls):

```lua
-- AJ.12 (v3.2.0 cleanup batch 6, replaces Y.2 source pin):
-- behavioral counterpart for the v0.11.16 A2 Belote K+Q-of-trump
-- escape clause in hokmMinShape. Pre-fix the J-floor short-
-- circuited the function on hands without J-of-trump regardless
-- of other shape. Post-fix, hands with K+Q-of-trump and count≥2
-- in the trump suit pass shape even without J — Belote (+20)
-- compensates for the missing J.
--
-- Determinism: jitter is frozen at 0 via the arity-aware shim shape
-- (same pattern as commit 08473ce) so the bid threshold comparison
-- is exact. Without the freeze the hand sits inside the jitter band
-- and the assert would only hold ~5/13 of the time.
--
-- Hand: KH QH 7H AS KD. Trump=H, K+Q+7 of H (count 3, no J).
-- Pre-fix: J-floor returns false → PickBid PASSes.
-- Post-fix: Belote escape returns true → suit strength + Belote
-- +20 + sidecar honors clears thHokmR2 → fires HOKM:H.
do
    local restore = snapshotS({
        "bidRound", "bidCard", "dealer", "hostHands", "cumulative", "bids",
    })
    local origRandom = math.random
    math.random = function(a, b)
        if a == -K.BOT_BID_JITTER and b == K.BOT_BID_JITTER then return 0 end
        if a == nil then return origRandom() end
        if b == nil then return origRandom(a) end
        return origRandom(a, b)
    end

    S.s.bidRound = 2
    S.s.bidCard = "JC"
    S.s.dealer = 4
    S.s.cumulative = { A = 0, B = 0 }
    S.s.bids = { K.BID_PASS, K.BID_PASS, K.BID_PASS, K.BID_PASS }
    S.s.hostHands = { [1] = { "KH", "QH", "7H", "AS", "KD" } }

    local result = Bot.PickBid(1)

    math.random = origRandom
    restore()

    assertEq(result, K.BID_HOKM .. ":H",
             "AJ.12 (A2 / BS-1): K+Q+other trump no J fires Hokm-H via Belote escape")
end
```

Note the assert lands **after** `math.random` is restored. This avoids a stuck shim if the assert itself ever raises (defensive — the harness shouldn't long-jump, but cleanup ordering matters for human readability of the test body).

**Why it would fail if regressed:** without the K+Q escape in `hokmMinShape`, the no-J trump shape fails the J-floor; `Bot.PickBid` skips Hokm-H consideration; result is `BID_PASS`. With jitter frozen at 0 the assert is unambiguous.

**Test count delta: +1 new assert, -1 source pin = 0 net.**

### 4E. AJ.13 (NEW) — Sun-no-rungs escalation invariant (replaces AA.1c + AB.1)

**Current pins:**
- AA.1c (line 3451): `botSrc:find("Sun has no Triple/Four/Gahwa rungs")` — comment pin
- AB.1 (line 3506): `botSrc:find('elseif contract%.type == K%.BID_SUN then') == nil` — absence pin

**Replacement:**
```lua
-- AJ.13 (v3.2.0 cleanup batch 6, replaces AA.1c + AB.1 source pins):
-- behavioral counterpart for the invariant that Sun contracts have
-- NO Triple/Four/Gahwa escalation rungs. The escalationStrength
-- helper used to have an `elseif contract.type == K.BID_SUN then`
-- branch (v0.11.17-hotfix F1 removed it as dead code — every
-- escalation caller early-returns on Sun before reaching the
-- strength calc). Behavioral assertion: under a Sun contract,
-- Bot.PickDouble / Bot.PickTriple / Bot.PickFour / Bot.PickGahwa
-- ALL return false / not-fire regardless of hand strength.
do
    local restore = snapshotS({
        "phase", "contract", "hostHands", "cumulative", "tricks", "trick",
    })
    S.s.phase     = K.PHASE_PLAY
    S.s.contract  = { type = K.BID_SUN, bidder = 1 }
    S.s.cumulative = { A = 0, B = 0 }
    S.s.tricks   = {}
    S.s.trick    = nil
    S.s.hostHands = {}
    -- Strong Sun hand — would absolutely qualify for any rung under
    -- Hokm. If escalationStrength's Sun branch were re-introduced
    -- (or if any of the four deciders forgot the Sun early-return),
    -- some non-false return would slip through.
    S.s.hostHands[1] = { "AS", "AH", "AD", "AC", "KS" }
    assertEq(Bot.PickDouble(1), false,
             "AJ.13a (F1): PickDouble returns false on Sun contract")
    assertEq(Bot.PickTriple(1), false,
             "AJ.13b (F1): PickTriple returns false on Sun contract")
    assertEq(Bot.PickFour(1), false,
             "AJ.13c (F1): PickFour returns false on Sun contract")
    assertEq(Bot.PickGahwa(1), false,
             "AJ.13d (F1): PickGahwa returns false on Sun contract")
    restore()
end
```

**Why it would fail if regressed:** if any escalation decider lost its Sun early-return (or escalationStrength's Sun branch was re-added and a caller stopped early-returning), one of these `assertEq` calls would catch a non-`false` return.

**Test count delta: +4 new asserts, -2 source pins (AA.1c, AB.1) = +2 net.**

---

## 5. Explicit Deferrals

| Pin | Reason for defer |
|---|---|
| R.2a-e (btrace) | Diagnostic helper; structural pin protects observability not behavior |
| AD.7a-b (eltrace) | Same as R.2 — debug-mode wiring |
| AB.2 / AD.3 (DEAD-2 rationale) | Comment-only pin; safer to leave |
| Y.2b / X.2b / Z.2 (ordering) | Source-position ordering; behavioral equivalents would add little |
| T.3a/b (hokmMinShape internal flag names) | Requires multi-state PickBid R2 fixtures across mardoofa scenarios |
| AH.3 (PickTriple floor cap) | Requires constructing inflection state that knocks `th` very low |
| AH.6 (partnerBidBonus seatIsBidder) | Helper is local; behavioral test would need full PickBid bidder-vs-defender split coverage |
| AI.1 / AI.4 / AI.5 (agent comment markers) | Comment-discoverability pins; converting wouldn't reduce extraction friction |
| AI.2a/b (tiered smother gate) | Deep pickFollow fixture; out of scope for this prep batch |
| AA.4 / AB.3 (bidderHoldsBidcard) | Helper is local; behavioral path through PickAKA at PHASE_PLAY vs PHASE_DEAL2BID is two-step |
| Y.3a-d (withBidcard call sites in PickBid/PickPreempt/PickOvercall) | Partially covered by AE.1 / X.4 already; full retirement would need new PickPreempt + PickOvercall behavioral tests — defer to Batch 7 |
| W.1 (2-Ace Sun bonus K constant ref) | W.2 behavioral exists; could retire by citation, but the K-constant ref pin is cheap to keep |
| Z.1 / Z.3 (belote / mardoofa recompute post-bidcard) | Implicitly covered by AE.1 + W.2; retire candidates for Batch 7 |

---

## 6. Implementation Guardrails For Later

When implementing Batch 6:

- No runtime Lua changes — pure test_state_bot.lua edits.
- Use the existing `snapshotS(fields)` helper for state restoration.
- For AJ.12 (Belote escape) freeze `math.random` via arity-aware shim (mirrors the bel-quality fix in commit `08473ce`):
  ```lua
  local origRandom = math.random
  math.random = function(a, b)
      if a == -K.BOT_BID_JITTER and b == K.BOT_BID_JITTER then return 0 end
      if a == nil then return origRandom() end
      if b == nil then return origRandom(a) end
      return origRandom(a, b)
  end
  ```
  Restore `math.random = origRandom` before the assert returns.
- For pin DELETIONS (Y.1, Q.1, Y.5, Y.7, Y.2, AA.1c, AB.1) leave a one-line comment at the old position citing the new AJ.NN behavioral assert (mirrors batch-3 pattern at AD.4a, AI.6).
- Run full harness AND test_H7 / test_H1 standalone smokes after the batch (to confirm no Bot.lua structural side-effects).
- Stop on a feature branch `v3.2.0-cleanup-batch6` and push for Codex review before merge.
- Expected harness count after merge: **1152** (+2 net).
- No release tag.

---

## 7. Summary

**Recommended Batch 6 scope (5 picks, 1 retirement + 4 behavioral conversions):**

1. RETIRE `Y.1` (`withBidcard` helper exists) — cite AE.1 / AE.1c.
2. NEW `AJ.10` — PickSWA hand-size guards (3 boundary asserts), replaces Q.1 + Y.5.
3. NEW `AJ.11` — PickAKA fires at trick 1 (Advanced tier, partner-led-A fixture), replaces Y.7.
4. NEW `AJ.12` — hokmMinShape Belote K+Q escape via PickBid R2 (jitter-frozen fixture), replaces Y.2.
5. NEW `AJ.13` — Sun-no-rungs escalation invariant (4 asserts: PickDouble/Triple/Four/Gahwa all false under Sun), replaces AA.1c + AB.1.

**Net source-pin reduction: 7 pins retired / behaviorally replaced.**
**Net test count delta: +2** (1150 → 1152).
**Risk class:** LOW for AJ.10 + AJ.13 + retire Y.1; LOW-MEDIUM for AJ.11; MEDIUM for AJ.12.

Working tree status: clean except for this design doc (untracked at
`.swarm_findings/v3_2_0_batch6_design.md`).

Awaiting Codex review of this design doc before implementation.
Stopping per the prompt's hard rule. No runtime/test code changed.
