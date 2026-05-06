# F-Test-01 — Test Coverage Gap Audit (v0.10.3 fixes)

**Agent:** F-Test-01
**Scope:** Cross-reference v0.10.3 fixes (REVIEW_v0.10.2.md sections 2 + 4) against the live test suite executed by `tests/run.py`.
**Method:** Read-only inspection of:
- `tests/run.py` (manifest)
- `tests/test_rules.lua` (1169 lines — Constants/Cards/Rules)
- `tests/test_state_bot.lua` (1836 lines — State/Bot)
- ancillary `tests/test_*.lua` files NOT in the manifest (catalogued for context)
- production source files at fix sites for invariant cross-check
- `Constants.lua:181/229`, `Bot.lua:484-507`, `Bot.lua:1640-1683`, `Bot.lua:1703-1715`, `Bot.lua:2128-2143`, `Bot.lua:2940-3010`, `BotMaster.lua:820-841`, `Rules.lua:810-940`, `State.lua:1167-1188`, `Net.lua:543`+`620`

---

## 0. Executive ledger

| Fix / Defer | Severity | Verdict | Notes |
|---|---|---|---|
| **#1 Wire-tag collision** (Constants.lua:229) | CRIT | **UNPINNED** | Zero tests touch `K.MSG_*` constants; harness never loads `Net.lua` |
| **#2 F-16 oppsVoidPath skip** (Bot.lua:2943-2992) | HIGH | **UNPINNED** | No Faranka-Exception-#4 fixture exists |
| **#3 bidderTeam undefined fix** (Bot.lua:2128) | HIGH | **UNPINNED** | M3lm conservative-opp branch never exercised |
| **#4 isBidderTeam Hokm-only typo** (Bot.lua:1705) | HIGH | **UNPINNED** | No Sun sweep-pursuit-early test fixture |
| **#5 BotMaster akaCalled propagation** (BotMaster.lua:830) | HIGH | **UNPINNED** | `BotMaster.lua` is never loaded by the runner (`run.py` manifest excludes it) |
| Deferred — Reverse Al-Kaboot scoring | HIGH | **UNPINNED** | Type-blind sweep awards never asserted with `reverseAlKaboot=true` |
| Deferred — Gahwa match-win type-blind | HIGH | PARTIALLY-PINNED | `test_rules.lua:L` exercises Hokm-Gahwa make/fail; no Sun-Gahwa pin |
| Deferred — ApplyMeld Hokm Carré-A drop | HIGH | PARTIALLY-PINNED | `R.DetectMelds` Hokm-Carré-A is pinned (test_rules.lua:E ~L370-380) but `S.ApplyMeld` apply-path has zero coverage |
| Deferred — Touching-honors WRITE missing partner-still-winning gate | HIGH | **UNPINNED** | `style.topTouchSignal` writes are never asserted |
| Deferred — Bargiya inner-discriminator axis | HIGH | PARTIALLY-PINNED | M7 single-A `lenAtAce` proxy is pinned (J.4); the deeper hand-shape vs event-count axis flip is not |

**Zero of the five v0.10.3 applied fixes have a regression test in the live suite.**

---

## 1. Test runner manifest reality check

`tests/run.py` only executes:

```
HARNESSES = [
    ("rules",     "test_rules.lua",     "Rules.lua / Cards.lua / Constants.lua"),
    ("state_bot", "test_state_bot.lua", "State.lua / Bot.lua"),
]
```

Files present in `tests/` but **NOT in the manifest** (not contributing to the 362-test count):
- `test_H1_pin_J9_trump.lua` — patches BotMaster sampler; loads it from a patched in-memory string
- `test_H7_sun_shortest_lead.lua`
- `test_asymmetric_metrics.lua`, `test_baseline_metrics.lua`, `test_bel_decision_quality.lua`, `test_multiseed_metrics.lua`, `test_numworlds_scaling.lua`, `test_v0.5_traced_game.lua`
- `probe_defender_strength.lua`
- `run_*.py` orchestrators (asymmetric, baseline, bel_decision_quality, multiseed_tournament, traced_game)

Implication: **`Net.lua` and `BotMaster.lua` are never loaded by the live test suite.** Wire-tag collisions and ISMCTS-driver bugs cannot be caught by the existing 362-test pass.

---

## 2. Per-fix verdicts (v0.10.3 applied fixes)

### Fix #1 — Wire-tag collision (Constants.lua:229) — **UNPINNED** [CRIT]

**Code post-fix:**
- `K.MSG_RESYNC_REQ = "?"` (Constants.lua:181)
- `K.MSG_OVERCALL_RESOLVE = "!"` (Constants.lua:229)
- Net.lua dispatch order: OVERCALL_RESOLVE elseif at L543, RESYNC_REQ elseif at L620

**Search result:** Grep across all of `tests/` for `MSG_RESYNC|MSG_OVERCALL_RESOLVE|wire.tag|tag.collision|byte.collision` — zero matches. No test inspects `K.MSG_*` values.

**Why nothing catches it:** `test_rules.lua` and `test_state_bot.lua` never load `Net.lua`. Even if they did, no test enumerates the `K.MSG_*` value-set for byte-distinctness.

**Risk:** A future commit that re-uses any single-byte glyph (e.g. someone defines a new `K.MSG_FOO = "!"`) will silently misroute again, with no test failing.

**Suggested fixture (sketch — to add in test_rules.lua, ideally a new section "R. Wire-tag distinctness"):**
```lua
-- R. Wire-tag distinctness (v0.10.3 CRIT-1 regression pin)
section("R. Wire-tag distinctness (CRIT-1)")
do
    -- Enumerate every K.MSG_* constant; assert all values are unique.
    -- Net.lua's if/elseif dispatch puts the FIRST matching branch wins,
    -- so any byte-collision silently misroutes traffic.
    local seen = {}
    local dups = {}
    for name, val in pairs(K) do
        if type(name) == "string"
           and name:sub(1, 4) == "MSG_"
           and type(val) == "string" then
            if seen[val] then
                dups[#dups + 1] = name .. "<->" .. seen[val] .. " (='" .. val .. "')"
            else
                seen[val] = name
            end
        end
    end
    assertEq(#dups, 0,
             ("Wire-tag distinctness: no byte collisions among K.MSG_*; got: %s"):format(
                table.concat(dups, ", ")))
    -- Strict pin for the historical clash:
    assertTrue(K.MSG_RESYNC_REQ ~= K.MSG_OVERCALL_RESOLVE,
               "v0.10.3 CRIT-1: MSG_RESYNC_REQ and MSG_OVERCALL_RESOLVE must be distinct")
    assertEq(K.MSG_RESYNC_REQ,        "?", "MSG_RESYNC_REQ pinned to '?'")
    assertEq(K.MSG_OVERCALL_RESOLVE,  "!", "MSG_OVERCALL_RESOLVE pinned to '!'")
end
```

---

### Fix #2 — F-16 over-fire skip on `oppsVoidPath` (Bot.lua:2943-2992) — **UNPINNED** [HIGH]

**Code post-fix:** `oppsVoidPath` boolean tracks Exception-#4 trigger (both opps observed-void in trump). When `oppsVoidPath = true`, the F-16 K-cover veto is skipped, allowing legitimate F-30b risk-free Farankas on K-less hands.

**Search result:** Grep across `tests/` for `oppsVoidPath|F-16|Faranka|Exception #4|F_16` — zero matches.

**Why nothing catches it:** No test puts the bot in a withhold-trump-K-less scenario with both opponents marked as observed-void in trump (`Bot._memory[oppSeat].void[trump] = true`).

**Risk:** A future refactor of the Faranka block could silently re-introduce the gate without any failing test. Particularly fragile: the gate is a single-line check (`if farankaTriggered and not oppsVoidPath then`).

**Suggested fixture (sketch — add to test_state_bot.lua section E or new section P):**
```lua
-- v0.10.3 — F-16 oppsVoidPath skip (HIGH).
do
    WHEREDNGNDB.advancedBots = true
    WHEREDNGNDB.m3lmBots = true
    freshState()
    S.s.isHost = true
    -- Hokm contract, trump=H, bidder=1. Seat 3 (bidder's partner)
    -- is on the bidder team. Both opps (seats 2, 4) marked observed
    -- void in trump (Bot._memory[2/4].void.H = true). Hand has a
    -- low trump but NO K of trump (the F-16 cover absent).
    S.s.contract = { type = K.BID_HOKM, trump = "H", bidder = 1 }
    S.s.tricks = {}                   -- early enough that Faranka can fire
    S.s.trick = { leadSuit = nil, plays = {} }
    -- Seat 3's hand: low trump 8H + the cards we'd preserve under F-30b.
    -- Plus a non-trump A we want to lead. Goal: assert pickLead chooses
    -- non-trump A (Faranka withhold), NOT 8H.
    S.s.hostHands = {
        [1] = {}, [2] = {}, [3] = { "AS","KS","8H","9D","JD","8D","JC","7C" }, [4] = {},
    }
    S.s.seats = {
        [1] = { isBot = true }, [2] = { isBot = true },
        [3] = { isBot = true }, [4] = { isBot = true },
    }
    Bot._memory = nil
    -- Manually prime void records on opp seats:
    Bot._partnerStyle = nil  -- ensure clean slate
    -- Use OnPlayObserved to synthesise voids: opp seat 2 plays a non-trump
    -- when trump is led (signals trump-void); opp seat 4 likewise. The
    -- exact prime-mechanism depends on what Bot.OnPlayObserved sets; if
    -- Bot._memory is the sink, set Bot._memory[2].void.H=true directly.
    Bot._memory = Bot._memory or { [1]={void={}}, [2]={void={}},
                                    [3]={void={}}, [4]={void={}} }
    Bot._memory[2].void.H = true
    Bot._memory[4].void.H = true
    -- Pre-v0.10.3: F-16 fires (no K of H in seat 3's hand). Suppresses
    -- the withhold; falls through to natural lead, possibly bleeding 8H.
    -- Post-v0.10.3: oppsVoidPath=true, F-16 skipped. Withhold 8H,
    -- lead AS to cash side-suit boss.
    local card = Bot.PickPlay(3)
    assertTrue(card ~= "8H",
               "v0.10.3 #2: F-16 skipped when both opps trump-void → 8H NOT bled")
    -- Stronger: the chosen lead should be a non-trump high (AS).
    assertEq(card, "AS",
             "v0.10.3 #2: F-30b risk-free Faranka leads non-trump boss")
    WHEREDNGNDB.m3lmBots = false
    WHEREDNGNDB.advancedBots = false
end
```

Note: the exact card chosen depends on full pickLead resolution; the **invariant** worth pinning is "8H not bled" plus the existence of `oppsVoidPath` semantics. A direct white-box fixture could reach the picker on a stripped-down hand and assert that with `Bot._memory[2].void[trump]=Bot._memory[4].void[trump]=true`, F-16's veto path is not entered. If Bot.lua exposes a helper for unit-testing this gate, that would be tighter.

---

### Fix #3 — `bidderTeam` undefined fix (Bot.lua:2128) — **UNPINNED** [HIGH]

**Code post-fix:** `local bidderTeam = R.TeamOf(contract.bidder)` is now defined inside the M3lm + Hokm + contract.bidder-non-nil guard, before the conservativeOpp loop test `R.TeamOf(s2) ~= bidderTeam`.

**Search result:** Grep across `tests/` for `bidderTeam|conservativeOpp|conservative.opp|M3lm.*conservative` — `bidderTeam` matches are all in metric-helper code (computing bidder-team scores in tournament fixtures) and in section I.1 (H3 tiebreaker), not the conservativeOpp branch.

**Why nothing catches it:** The conservativeOpp branch requires `Bot._partnerStyle[s2].styleTrumpTempo == -1` for at least one seat to enter the side-suit-Aces-first reorder. No test seeds the partner-style ledger with that value AND constructs the right Hokm fixture.

**Risk:** A future tweak to the bidderTeam declaration could silently re-introduce the no-op bug — both teams' seats would once again be accepted as "conservative opp", causing the bot to cash side-suit Aces in scenarios where its OWN partner has the conservative trump-tempo style (wrong target).

**Suggested fixture (sketch — test_state_bot.lua section E):**
```lua
-- v0.10.3 — bidderTeam scope fix (HIGH, B-Bot-08).
do
    WHEREDNGNDB.advancedBots = true
    WHEREDNGNDB.m3lmBots     = true
    freshState()
    S.s.isHost = true
    S.s.contract = { type = K.BID_HOKM, trump = "H", bidder = 1 }
    S.s.tricks = {}
    S.s.trick = { leadSuit = nil, plays = {} }
    -- Seat 1 leading. Bidder's PARTNER is seat 3; seats 2,4 are opps.
    -- Pre-v0.10.3 BUG: with bidderTeam=nil, R.TeamOf(s2) ~= nil is
    --   always true, so seat 3 (partner!) qualifies as conservativeOpp
    --   if their styleTrumpTempo == -1. Wrong: that should only target
    --   OPPS (seats 2/4).
    -- Build a hand where the choice differs: seat 1 has trump-pull
    --   candidate JH AND a side-suit A (AS). With conservativeOpp wrongly
    --   triggered by partner, code reorders to lead AS first. With the
    --   fix, partner triggering is a no-op → falls through to JH (or
    --   whatever the natural pickLead chooses).
    S.s.hostHands = {
        [1] = { "JH","9H","AS","KS","9D","8D","JC","9C" },
        [2] = {}, [3] = {}, [4] = {},
    }
    S.s.seats = { [1]={isBot=true}, [2]={isBot=true},
                  [3]={isBot=true}, [4]={isBot=true} }
    -- Prime PARTNER (seat 3, same team as bidder) styleTrumpTempo = -1.
    -- With pre-fix bug: seat 3 wrongly counted as conservativeOpp.
    -- With post-fix: seat 3 is on bidder team, ignored by gate.
    Bot._partnerStyle = {
        [1] = { tahreebSent={S={},H={},D={},C={}} },
        [2] = { tahreebSent={S={},H={},D={},C={}}, styleTrumpTempo = 0  },
        [3] = { tahreebSent={S={},H={},D={},C={}}, styleTrumpTempo = -1 },  -- partner
        [4] = { tahreebSent={S={},H={},D={},C={}}, styleTrumpTempo = 0  },
    }
    Bot._memory = nil
    -- Expected post-fix: pickLead does NOT reorder for side-suit-Aces-first
    --   (no opp has -1 styleTrumpTempo). Assertable:
    --     card != "AS" (the cash-Ace branch was suppressed correctly)
    -- The exact card depends on rest of pickLead; the negative invariant
    -- is the safe pin.
    local card = Bot.PickPlay(1)
    assertTrue(card ~= "AS",
               "v0.10.3 #3: partner-only -1 tempo does NOT trigger cash-Aces-first (bidderTeam scope honoured)")
    WHEREDNGNDB.m3lmBots = false
    WHEREDNGNDB.advancedBots = false
end
```

---

### Fix #4 — `isBidderTeam` Hokm-only typo (Bot.lua:1705) — **UNPINNED** [HIGH]

**Code post-fix:** `local isBidderTeam = (myTeam == R.TeamOf(contract.bidder))` (type-clause removed; was previously gated `and contract.type == K.BID_HOKM`, killing all Sun branches).

**Search result:** Grep for `isBidderTeam|sweep.pursuit|pickLead.*Sun` — zero matches.

**Why nothing catches it:** No test exercises pickLead in Sun on a sweep-pursuit-early scenario (trick 3-7 with the bidder team having won every trick so far). Section J.2 (M8) uses Sun + trick 1, which doesn't reach the sweep-pursuit branch.

**Risk:** A regression that re-introduces the type-gate would silently break Sun-Kaboot pursuit (220×2=440 raw at stake) AND defender-style reads at lines 1984/2248. None of these are pinned.

**Suggested fixture (sketch):**
```lua
-- v0.10.3 — isBidderTeam Sun re-enable (HIGH).
do
    WHEREDNGNDB.advancedBots = true
    freshState()
    S.s.isHost = true
    S.s.contract = { type = K.BID_SUN, trump = nil, bidder = 1 }
    -- Bidder team has won 4 prior tricks (clean sweep so far),
    -- now leading trick 5. sweepPursuitEarly should fire (trickNum=5,
    -- 3 ≤ 5 ≤ 7). Pre-v0.10.3: isBidderTeam=false in Sun → branch
    -- bypassed → leads natural choice. Post-v0.10.3: branch fires.
    -- Construct so the branch's lead is DIFFERENT from natural fallthrough.
    --
    -- Concrete: hand has K-led-suit guarantee + a non-K side ace.
    -- sweep-pursuit-early in Sun pushes the highest face-value winner
    -- (AL_KABOOT_SUN=220) — leads the GUARANTEED boss in long suit.
    -- Natural Sun pickLead would pick shortest-suit-low (different).
    S.s.tricks = {
        { winner = 1, plays = {{seat=1,card="AS"}}, leadSuit="S" },
        { winner = 3, plays = {{seat=3,card="AC"}}, leadSuit="C" },
        { winner = 1, plays = {{seat=1,card="AD"}}, leadSuit="D" },
        { winner = 3, plays = {{seat=3,card="AH"}}, leadSuit="H" },
    }
    S.s.trick = { leadSuit = nil, plays = {} }
    S.s.hostHands = {
        [1] = { "TS","KS","QS","JS","TD","KD","JD","9D" },  -- TS guaranteed boss (AS played)
        [2] = {}, [3] = {}, [4] = {},
    }
    -- Without the Sun gate, sweep-pursuit-early kicks in →
    -- highest-face-value boss = TS (10 points, top of S after AS). Without
    -- the fix, the Sun shortest-suit-low fallback would pick 9D or similar.
    local card = Bot.PickPlay(1)
    assertEq(card, "TS",
             "v0.10.3 #4: Sun sweep-pursuit-early fires (was skipped pre-fix due to type-clause)")
    WHEREDNGNDB.advancedBots = false
end
```

(The exact "expected card" needs verification against the actual code; the **invariant** is that some reachable distinguishable choice be made, vs. a fallthrough that ignores the bidder-team status.)

---

### Fix #5 — BotMaster `akaCalled` propagation (BotMaster.lua:830) — **UNPINNED** [HIGH]

**Code post-fix:** Outer driver passes `S.s.akaCalled` as the 6th arg to `R.IsLegalPlay` so the bot's own legal set respects M4 AKA-receiver relief.

**Search result:** Grep matches I.4 in test_state_bot.lua, which is only a SOURCE-LEVEL string match for the pcall pattern (verifying `for w` precedes `pcall(function()`). It does NOT actually invoke `BotMaster.PickPlay`.

**Why nothing catches it:** `test_state_bot.lua` never calls `load("BotMaster.lua")`. The tournament block sets `WHEREDNGNDB.saudiMasterBots = true`, but `Bot.PickPlay`'s delegation reads `WHEREDNGN.BotMaster` which is **nil** in the test environment. The "master" tier path in the tournament therefore silently falls through to the heuristic Bot.PickPlay — the entire BotMaster module is invisible to the test suite.

This is a serious test-coverage architectural gap, not just for fix #5: ALL of BotMaster.lua's logic (ISMCTS, sampler, akaCalled propagation, numWorlds scaling, hand-sample uniformity, voids respect, pcall granularity for H4) is unverified by the live runner. The H4 source-level pin (I.4 in test_state_bot.lua) would only catch a pattern reorder, not a behavioural regression.

**Risk:** Regression to AKA-blind real-state legal filtering would re-break M4 in Saudi-Master tier with zero test failures.

**Suggested fixture (sketch — deserves a new harness `test_botmaster.lua` added to run.py manifest):**
```lua
-- v0.10.3 — BotMaster outer driver akaCalled propagation (HIGH, E-Det-01 #7).
do
    -- Setup: load BotMaster (currently NOT in run.py manifest — add it).
    load("BotMaster.lua")
    local BM = WHEREDNGN.BotMaster

    -- Force Saudi-Master tier active.
    WHEREDNGNDB.saudiMasterBots = true
    freshState()
    S.s.isHost = true
    -- Hokm trump H. Partner (seat 2) AKA'd on D and led KD. Opp (seat 3)
    -- cut with 7H. Seat 4 to play, void in D, has trump 9H, has non-trump
    -- AS+8C. Without akaCalled passed, R.IsLegalPlay returns ONLY {9H}.
    -- With akaCalled passed, returns {AS, 9H, 8C}.
    S.s.contract = { type = K.BID_HOKM, trump = "H", bidder = 2 }
    S.s.akaCalled = { seat = 2, suit = "D" }
    S.s.hostHands = {
        [1] = {},
        [2] = {},
        [3] = {},
        [4] = { "AS", "9H", "8C" },
    }
    S.s.trick = { leadSuit = "D", plays = {
        { seat = 2, card = "KD" },
        { seat = 3, card = "7H" },
    } }
    S.s.tricks = {}

    -- Drive a single ISMCTS pick. Full ISMCTS sampling is non-deterministic;
    -- the assertion is "the chosen card is in the AKA-relieved legal set
    -- {AS, 9H, 8C}", which Bot ISMCTS legality-filters from. Pre-fix, the
    -- legal set would be {9H}, forcing 9H. Post-fix, AS or 8C are reachable.
    -- A statistical pin (run 30 ISMCTS picks, assert at least one non-9H) is
    -- robust against per-call randomness.
    local nonTrumpReached = false
    for trial = 1, 30 do
        local card = BM.PickPlay(4)
        if card == "AS" or card == "8C" then nonTrumpReached = true; break end
    end
    assertTrue(nonTrumpReached,
               "v0.10.3 #5: BotMaster outer driver respects akaCalled — non-trump discard reachable")
    -- Negative pin: clear akaCalled, must-trump fires, only 9H reachable.
    S.s.akaCalled = nil
    for trial = 1, 30 do
        local card = BM.PickPlay(4)
        assertEq(card, "9H",
                 "v0.10.3 #5 sanity: no akaCalled → must-trump enforced, only 9H legal")
    end
    WHEREDNGNDB.saudiMasterBots = false
end
```

A simpler fixture would directly invoke a hypothetical `BM._buildLegal(seat)` if exposed; the surface above uses statistical coverage.

---

## 3. Deferred-HIGH coverage

### Reverse Al-Kaboot scoring (Rules.lua:817-822 type-blind) — **UNPINNED**

**Status:** Ifx not yet applied (deferred to v0.10.4). Currently sweepTeam awards `K.AL_KABOOT_HOKM=250` or `K.AL_KABOOT_SUN=220` regardless of who's sweeping (bidder team or defender team). Per A-Src-18 + B-State-05 F-01, defender-sweep should award +88 raw with a bidder-led-trick-1 gate.

**Test coverage today:** Section H in test_rules.lua exercises Hokm + Sun sweeps with `winnerSeat` of either team — but only asserts the existing (allegedly-wrong) values. The test does NOT distinguish defender-sweep vs bidder-sweep semantics.

**For the v0.10.3 release (fix not applied):** the existing tests act as **negative regression pins** that will need updating when the fix lands. Worth adding a TODO comment.

**For v0.10.4 design call:** Recommend a fixture that constructs a defender-sweep with `bidderLedTrick1` true vs false, and asserts:
- `bidderLedTrick1=true` + defender sweep → +88 raw (reverse path)
- `bidderLedTrick1=false` + defender sweep → standard 250/220 (or whatever the synthesised constant is)
Plus a constant-existence pin: `assertTrue(K.AL_KABOOT_REVERSE)` once added.

---

### Gahwa match-win type-blind (Rules.lua:928) — PARTIALLY-PINNED

**Test coverage today:** Section L in test_rules.lua pins Hokm-Gahwa make + fail. No Sun-Gahwa test exists, but per state-machine, Sun cannot reach Gahwa (it's structurally unreachable; ApplyDouble jumps to PHASE_PLAY).

**Verdict:** the existing pins are correct for Hokm. Sun-Gahwa is structurally dead per R2 normalisation in test_rules.lua section K (Sun×stale-Four collapses to Sun×Bel). A defensive **pin** that asserts Sun-Gahwa input is silently normalized (e.g. `mult = K.MULT_SUN * K.MULT_BEL`, gahwaWonGame stays false) would close B-State-05 F-02.

**Suggested fixture:**
```lua
-- Sun + stale gahwa flag → normalised, no match-win triggered.
do
    local c = sun(1, { doubled=true, tripled=true, foured=true, gahwa=true })
    local res = R.ScoreRound(sweptTricks(1), c, { A = {}, B = {} })
    assertEq(res.gahwaWonGame, nil, "Sun + stale gahwa: gahwaWonGame NOT set (Sun has no Gahwa rung)")
    assertEq(res.multiplier, K.MULT_SUN * K.MULT_BEL,
             "Sun + stale gahwa: mult collapses to Sun×Bel")
end
```

---

### ApplyMeld Hokm Carré-A drop (State.lua:1167-1184) — PARTIALLY-PINNED

**Test coverage today:** test_rules.lua section E (lines 365-380) pins R.DetectMelds Hokm-Carré-A → `value = K.MELD_CARRE_OTHER (100)`. This is the **detect** path.

**Gap:** S.ApplyMeld (the **apply** path triggered when a player explicitly declares the meld) has NO test. Reading State.lua:1167-1184: when `top == "A"` and `s.contract.type ~= K.BID_SUN`, the inner `if/end` falls through with `value = nil`, and the outer `if not value then return end` silently drops the meld.

**Why this matters:** even with the v0.10.0 X5 fix at the detect path, a player who declares 4-Aces in Hokm via the explicit-declaration UI path would have ApplyMeld silently drop it.

**Suggested fixture (test_state_bot.lua):**
```lua
-- ApplyMeld Hokm Carré-A apply-path (X5 follow-through).
do
    freshState()
    S.s.contract = { type = K.BID_HOKM, trump = "H", bidder = 1 }
    -- Encoded form for ApplyMeld depends on the encoding used by C.EncodeHand.
    -- The ApplyMeld signature: ApplyMeld(seat, kind, top, suit, encodedCards, ...?)
    S.ApplyMeld(1, "carre", "A", nil, C.EncodeHand({"AS","AH","AD","AC"}))
    local team = R.TeamOf(1)
    local found
    for _, m in ipairs(S.s.meldsByTeam[team]) do
        if m.kind == "carre" and m.top == "A" then found = m end
    end
    assertTrue(found, "ApplyMeld Hokm Carré-A: meld stored (was dropped pre-fix)")
    if found then
        assertEq(found.value, K.MELD_CARRE_OTHER, "Hokm Carré-A apply value = 100")
    end
    -- Sanity: Sun Carré-A still routes to MELD_CARRE_A_SUN (200/400).
    freshState()
    S.s.contract = { type = K.BID_SUN, bidder = 1 }
    S.ApplyMeld(1, "carre", "A", nil, C.EncodeHand({"AS","AH","AD","AC"}))
    local team = R.TeamOf(1)
    found = nil
    for _, m in ipairs(S.s.meldsByTeam[team]) do
        if m.kind == "carre" and m.top == "A" then found = m end
    end
    assertEq(found.value, K.MELD_CARRE_A_SUN, "Sun Carré-A apply value = 400")
end
```

---

### Touching-honors WRITE missing partner-still-winning gate (Bot.lua:484-507) — **UNPINNED**

**Code reality at site:** `Bot.OnPlayObserved` writes `style.topTouchSignal[cardSuit]` based on the played card's rank (T→nextDown=K, K→cleared={Q,J}, Q→nextDown=J, 7/8/9→broke). The READ side in pickLead/pickFollow uses these to guess partner's hand shape.

**The deferred concern:** the WRITE fires on touching-honors signals from ANY observation matching the partner-A-led / partner-AKA pattern, **without checking if partner is still winning the trick at the moment of the observed card.** If an opponent has cut between partner's lead and the current card (e.g. trumped in mid-trick), the touch signal is corrupted because the play wasn't actually in the partner-context any more.

**Test coverage today:** zero. No test inspects `Bot._partnerStyle[seat].topTouchSignal` after constructed fixtures.

**Suggested fixture (test_state_bot.lua):**
```lua
-- Touching-honors WRITE partner-still-winning gate (deferred HIGH).
do
    freshState()
    S.s.contract = { type = K.BID_HOKM, trump = "C", bidder = 1 }
    Bot._partnerStyle = nil
    -- Partner (seat 1) leads AS. Opp (seat 2) cuts with 7C (trump).
    -- Seat 3 (partner of seat 1) plays TS. Pre-fix: TS write fires
    -- (T→nextDown=K). Post-fix-ideal: gate suppresses the write because
    -- partner (seat 1) is no longer winning at the moment of TS observation.
    Bot.OnPlayObserved(1, "AS", { leadSuit="S", plays={{seat=1,card="AS"}} })
    Bot.OnPlayObserved(2, "7C", { leadSuit="S", plays={
        {seat=1,card="AS"}, {seat=2,card="7C"} } })
    Bot.OnPlayObserved(3, "TS", { leadSuit="S", plays={
        {seat=1,card="AS"}, {seat=2,card="7C"}, {seat=3,card="TS"} } })
    -- After fix: seat 3's topTouchSignal[S] should be nil/empty.
    -- Pre-fix: nextDown="K".
    local sig = Bot._partnerStyle and Bot._partnerStyle[3]
              and Bot._partnerStyle[3].topTouchSignal
              and Bot._partnerStyle[3].topTouchSignal.S
    assertTrue(sig == nil or not sig.nextDown,
               "Touching-honors WRITE: gate suppresses signal when partner not winning")
end
```

The actual fix may be either at WRITE time (gate before the if-chain at line 493) or at READ time (filter before consuming). The test pins the externally-observable invariant.

---

### Bargiya inner-discriminator axis (Bot.lua:1640-1683) — PARTIALLY-PINNED

**Test coverage today:** Section J.4 in test_state_bot.lua pins the M7 محشور-proxy via `lenAtAce >= 5` returning "bargiya" (weight 3) and outranking 2-event "want" (weight 2). Plus the negative case where `lenAtAce` is absent → "bargiya_hint" (weight 1) loses to "want" (weight 2).

**Gap:** the deferred audit item is about the deeper axis: the function classifies on (event-count, cover-grade-of-second-event), but per A-Src-30 + #14 + P1B R9 the canonical axis is **hand-shape** (محشور / suits-touched-count proxy). The current 2-event cover-grade gate only partially captures hand-shape via the secondary check. A future axis-flip would change classifier outputs in the (≥2 events, second-rank<T) region, which J.4 does not exercise distinguishingly.

**No new test required for v0.10.3** — the J.4 pins protect the M7 specific FN closure. The deeper axis flip is design-call backlog.

---

## 4. Priority ordering for v0.10.3 release confidence

Ranked highest-leverage gaps first (most CRIT/HIGH risk × ease-of-pinning):

1. **Wire-tag distinctness pin (#1)** — CRIT, single-section addition to test_rules.lua, no new harness needed, ~10 lines. **Ship-blocker if you want any regression protection on the CRIT-1 fix.**
2. **ApplyMeld Hokm Carré-A pin** — closes the X5 follow-through (the detect path is already pinned, leaving the apply path as a hidden inverse-regression risk). Trivial fixture in test_state_bot.lua.
3. **isBidderTeam Sun re-enable (#4)** — pickLead Sun coverage is conspicuously absent. Sun-Kaboot pursuit (440 raw at stake) is high-impact.
4. **bidderTeam scope (#3)** — invariant is easy to negative-pin (partner styleTrumpTempo=-1 should NOT trigger cash-aces-first).
5. **F-16 oppsVoidPath (#2)** — slightly fragile fixture (depends on Bot._memory void-prime mechanism), but the negative invariant ("8H not bled") is robust.
6. **BotMaster akaCalled propagation (#5)** — requires loading BotMaster.lua AND a new harness file. **Lower on list because it requires architectural test-suite work** (adding test_botmaster.lua to run.py manifest), but the underlying coverage gap is broader than just fix #5: ALL of BotMaster.lua is currently uncovered by the live suite.

For v0.10.4 backlog:
7. Sun-Gahwa normalization pin (B-State-05 F-02 closure)
8. Touching-honors WRITE gate pin
9. Reverse Al-Kaboot fixture (paired with the constant + gate addition)

---

## 5. Architectural observation

The most material finding from this audit is that **`Net.lua` and `BotMaster.lua` are entirely outside the live test envelope.** The 362 tests exercise Constants/Cards/Rules/State/Bot.lua only. Of the v0.10.3 fixes:
- 1 lives in Constants.lua (#1 — wire tag)
- 3 live in Bot.lua (#2, #3, #4)
- 1 lives in BotMaster.lua (#5)

The four Bot.lua / Constants.lua fixes are pinnable today with section additions to existing files. The BotMaster.lua fix (#5) and any future Net.lua-domain fixes need **manifest-level work**: extending `tests/run.py` to load a new `test_botmaster.lua` and `test_net.lua` harness. This is a one-time investment that would unlock regression coverage for the entire E-Det-01 ISMCTS determinism table and the wire-tag dispatch class.

The H1/H7/numworlds .lua files in `tests/` already prove the test-from-Lua-string-with-stubs pattern works for BotMaster — they're just not wired to `run.py`.

---

## 6. Cross-references

- Constants.lua:181 — `K.MSG_RESYNC_REQ = "?"`
- Constants.lua:229 — `K.MSG_OVERCALL_RESOLVE = "!"` (post-fix)
- Net.lua:543 — OVERCALL_RESOLVE elseif (first-match-wins)
- Net.lua:620 — RESYNC_REQ elseif (would-be unreachable pre-fix)
- Bot.lua:484-507 — Touching-honors WRITE site (deferred)
- Bot.lua:1640-1683 — Bargiya classifier (M7 pinned, axis flip deferred)
- Bot.lua:1703-1715 — pickLead `isBidderTeam` (fix #4)
- Bot.lua:2128-2143 — M3lm conservativeOpp (fix #3)
- Bot.lua:2940-3010 — Faranka oppsVoidPath + F-16 gate (fix #2)
- BotMaster.lua:830-841 — outer driver akaCalled (fix #5)
- Rules.lua:817-822 — sweep type-blind (Reverse Al-Kaboot deferred)
- Rules.lua:928 — Gahwa branch (partially pinned)
- State.lua:1167-1184 — ApplyMeld Carré-A drop (deferred)
- tests/run.py — 2-harness manifest
- tests/test_rules.lua — 1169 lines, sections A-Q
- tests/test_state_bot.lua — 1836 lines, sections A-J

---

*End of F-Test-01 coverage gap audit.*
