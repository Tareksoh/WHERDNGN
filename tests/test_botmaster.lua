-- tests/test_botmaster.lua
--
-- v0.11.12 XU-01 phase 1: behavioral test harness for BotMaster.lua.
-- Loads State + Bot + BotMaster under stub globals and exercises
-- BM.PickPlay / rolloutValue end-to-end. Closes the test-harness
-- gap that allowed v0.11.2 SU-Ultra-01 ("SWA per-team breakdown
-- shipped dead") and v0.10.6 RT07-01 ("redeal recovery shipped
-- dead") to pass source-string-match pins. Source-string pins on
-- BotMaster.lua are still useful as structural guardrails but
-- don't catch the "code compiles + matches text but is unreachable"
-- bug class — those need behavioral exercise.
--
-- Phase 2 (XU-01 phase 2 — deferred): Net.lua harness with WoW API
-- stubs (C_ChatInfo, C_Timer, GetTime, CHAT_MSG_ADDON event injection).
-- Phase 1 covers BotMaster — the highest-value architecturally
-- significant code path (C-14 + Bot1-01 + Bot1-02 all live here).

unpack = unpack or table.unpack
C_AddOns = nil
GetAddOnMetadata = nil

local function addonRoot()
    if WHEREDNGN_TESTS_ROOT then return WHEREDNGN_TESTS_ROOT end
    local src = debug.getinfo(1, "S").source
    if src:sub(1, 1) ~= "@" then
        error("cannot locate addon root: not running from a file. " ..
              "Set WHEREDNGN_TESTS_ROOT before running.")
    end
    src = src:sub(2)
    return (src:gsub("[/\\]tests[/\\][^/\\]+$", ""))
end

local ROOT = addonRoot()

-- -- Globals shim --------------------------------------------------------
GetUnitName = function() return "TestPlayer" end
UnitName    = function() return "TestPlayer" end
WHEREDNGNDB = {}
SendChatMessage = function() end
C_ChatInfo = {
    RegisterAddonMessagePrefix = function() return true end,
    SendAddonMessage = function() end,
}
CreateFrame = function()
    return {
        SetScript = function() end,
        RegisterEvent = function() end,
        UnregisterEvent = function() end,
        Hide = function() end, Show = function() end,
    }
end

local VERBOSE = (TEST_VERBOSE == true)

-- Module shims (Sound + Log + UI) — same pattern as test_state_bot.lua.
WHEREDNGN = WHEREDNGN or {}
WHEREDNGN.Sound = { Cue = function() end, Try = function() end, ArmCue = function() end }
WHEREDNGN.Log   = {
    Debug = function() end, Info = function() end, Warn = function() end,
    Error = function() end, Clear = function() end, Dump = function() end,
}
WHEREDNGN.UI = {
    Refresh = function() end, Show = function() end, Hide = function() end,
    Toggle  = function() end,
}

-- -- Load addon files ----------------------------------------------------
local function load(rel)
    local path = (ROOT .. "/" .. rel):gsub("\\", "/")
    local chunk, err = loadfile(path)
    if not chunk then error("failed to load " .. rel .. ": " .. tostring(err)) end
    chunk()
end

load("Constants.lua")
load("Cards.lua")
load("Rules.lua")
load("State.lua")
load("Bot/Tiers.lua")
load("Bot/PlayPrimitives.lua")
load("Bot/Bidding.lua")
load("Bot/Escalation.lua")
load("Bot.lua")
load("BotMaster.lua")

local K   = WHEREDNGN.K
local C   = WHEREDNGN.Cards
local R   = WHEREDNGN.Rules
local S   = WHEREDNGN.State
local Bot = WHEREDNGN.Bot
local BM  = WHEREDNGN.BotMaster

math.randomseed(20260506)

-- -- Tiny test framework -------------------------------------------------
local pass, fail = 0, 0
local failures = {}

local function assertEq(actual, expected, name)
    if actual == expected then
        pass = pass + 1
        if VERBOSE then print(("  PASS  %s"):format(name)) end
    else
        fail = fail + 1
        local msg = ("  FAIL  %s\n        expected: %s\n        actual:   %s"):format(
            name, tostring(expected), tostring(actual))
        failures[#failures + 1] = msg
        print(msg)
    end
end

local function assertTrue(actual, name)
    assertEq(actual and true or false, true, name)
end

local function assertFalse(actual, name)
    assertEq(actual and true or false, false, name)
end

local function section(label)
    print(("\n== %s =="):format(label))
end

-- -- Helpers ------------------------------------------------------------

-- Reset state between tests.
local function freshState()
    S.s = {
        phase = K.PHASE_IDLE,
        seats = { [1] = {}, [2] = {}, [3] = {}, [4] = {} },
        cumulative = { A = 0, B = 0 },
        meldsByTeam = { A = {}, B = {} },
        bids = {},
        target = 152,
        peerVersions = {},
    }
end

-- =====================================================================
-- A. BotMaster basic surface
-- =====================================================================
section("A. BotMaster basic surface")

assertTrue(BM ~= nil, "A.1: BotMaster module loaded")
assertTrue(BM.PickPlay ~= nil, "A.2: BM.PickPlay exists")
assertTrue(BM.IsActive ~= nil, "A.3: BM.IsActive exists")

-- IsActive gates on saudiMasterBots flag.
WHEREDNGNDB.saudiMasterBots = false
assertFalse(BM.IsActive(), "A.4: IsActive false when flag off")
WHEREDNGNDB.saudiMasterBots = true
assertTrue(BM.IsActive(), "A.5: IsActive true when flag on")

-- =====================================================================
-- B. C-14 + Bot1-01 state-swap behavioral validation
-- =====================================================================
section("B. C-14 state swap correctness (Bot1-01 closure)")

-- Set up a plausible game state for BM.PickPlay to act on.
do
    freshState()
    S.s.isHost = true
    S.s.contract = { type = K.BID_HOKM, trump = "S", bidder = 1 }
    -- Hand fixture: seat 1 has 8 distinct spades (the bot's own pinned
    -- hand). buildUnseen will distribute the rest of the deck across
    -- seats 2-4 in samples.
    S.s.hostHands = {
        [1] = { "JS", "9S", "AS", "TS", "KS", "QS", "8S", "7S" },
        [2] = { "AH", "TH", "KH", "QH", "JH", "9H", "8H", "7H" },
        [3] = { "AD", "TD", "KD", "QD", "JD", "9D", "8D", "7D" },
        [4] = { "AC", "TC", "KC", "QC", "JC", "9C", "8C", "7C" },
    }
    S.s.tricks = {}
    S.s.trick = { leadSuit = nil, plays = {} }
    S.s.playedCardsThisRound = {}
    S.s.akaCalled = nil

    -- Snapshot pre-call state for restoration check.
    local preHostHands = S.s.hostHands
    local preTrick = S.s.trick
    local preTricks = S.s.tricks
    local preAkaCalled = S.s.akaCalled
    local prePlayed = S.s.playedCardsThisRound
    local preMemory = Bot._memory
    local preInRollout = Bot._inRollout

    -- Call BM.PickPlay (the entry point under audit).
    local card = BM.PickPlay(1)

    -- Behavioral assertions that source-match pins can't catch:
    assertTrue(card ~= nil,
               "B.1 (C-14): BM.PickPlay returned a card")

    -- All swapped fields restored to their original values.
    assertEq(S.s.hostHands, preHostHands,
             "B.2a (Bot1-01): S.s.hostHands restored after rollout")
    assertEq(S.s.trick, preTrick,
             "B.2b (Bot1-01): S.s.trick restored")
    assertEq(S.s.tricks, preTricks,
             "B.2c (Bot1-01): S.s.tricks restored")
    assertEq(S.s.akaCalled, preAkaCalled,
             "B.2d (Bot1-01): S.s.akaCalled restored")
    assertEq(S.s.playedCardsThisRound, prePlayed,
             "B.2e (Bot1-01): S.s.playedCardsThisRound restored")
    assertEq(Bot._memory, preMemory,
             "B.2f (Bot1-01): Bot._memory restored after rollout")

    -- The recursion guard is correctly cleared post-call.
    assertEq(Bot._inRollout, preInRollout,
             "B.3 (Bot1-02): Bot._inRollout restored to pre-call value (no leak)")
end

-- =====================================================================
-- C. C-14 delegation: heuristicPick uses Bot.PickPlay
-- =====================================================================
section("C. heuristicPick delegates to Bot.PickPlay (v0.11.1 C-14)")

do
    -- Spy approach: count Bot.PickPlay invocations during a rollout.
    -- After v0.11.1 every rollout pick goes through Bot.PickPlay
    -- (instead of the old Advanced-mirror placeholder). With 100
    -- worlds × 8 candidates × ~25 picks per rollout, we expect
    -- well over 1000 Bot.PickPlay calls per BM.PickPlay invocation.
    local pickPlayCount = 0
    local origPickPlay = Bot.PickPlay
    Bot.PickPlay = function(seat)
        pickPlayCount = pickPlayCount + 1
        return origPickPlay(seat)
    end

    freshState()
    S.s.isHost = true
    S.s.contract = { type = K.BID_HOKM, trump = "S", bidder = 1 }
    S.s.hostHands = {
        [1] = { "JS", "9S", "AS", "TS", "KS", "QS", "8S", "7S" },
        [2] = { "AH", "TH", "KH", "QH", "JH", "9H", "8H", "7H" },
        [3] = { "AD", "TD", "KD", "QD", "JD", "9D", "8D", "7D" },
        [4] = { "AC", "TC", "KC", "QC", "JC", "9C", "8C", "7C" },
    }
    S.s.tricks = {}
    S.s.trick = { leadSuit = nil, plays = {} }
    S.s.playedCardsThisRound = {}
    S.s.akaCalled = nil
    WHEREDNGNDB.saudiMasterBots = true

    BM.PickPlay(1)

    -- Restore the spy.
    Bot.PickPlay = origPickPlay

    -- 100 worlds × 8 candidates × ~25 inner picks ≈ 20000.
    -- Lower bound check: at least 100 picks fired (sanity that the
    -- delegation path actually exercised the rollout policy).
    assertTrue(pickPlayCount > 100,
               ("C.1 (C-14): Bot.PickPlay invoked >100 times during rollout (got %d)"):format(pickPlayCount))
end

-- =====================================================================
-- D. Bot1-02 _inRollout flag leak guard
-- =====================================================================
section("D. _inRollout flag leak guard (Bot1-02)")

do
    -- Inject an error into R.IsLegalPlay to verify the v0.11.4 Bot1-02
    -- buildLegalSet pcall correctly catches it AND restores _inRollout.
    -- Pre-v0.11.4 a R.IsLegalPlay error in the legal-set construction
    -- propagated up to Net.lua's outer pcall but never restored
    -- _inRollout — silently disabling Saudi-Master tier for the rest
    -- of the session.
    local origIsLegalPlay = R.IsLegalPlay
    R.IsLegalPlay = function() error("test injection") end

    freshState()
    S.s.isHost = true
    S.s.contract = { type = K.BID_HOKM, trump = "S", bidder = 1 }
    S.s.hostHands = {
        [1] = { "JS", "9S", "AS", "TS", "KS", "QS", "8S", "7S" },
        [2] = {}, [3] = {}, [4] = {},
    }
    S.s.tricks = {}
    S.s.trick = { leadSuit = nil, plays = {} }
    S.s.playedCardsThisRound = {}
    Bot._inRollout = false
    WHEREDNGNDB.saudiMasterBots = true

    -- Call BM.PickPlay; it should fail gracefully (return nil) and
    -- restore _inRollout to false.
    local card = BM.PickPlay(1)
    assertEq(Bot._inRollout, false,
             "D.1 (Bot1-02): _inRollout cleared even when R.IsLegalPlay errors")

    -- Restore.
    R.IsLegalPlay = origIsLegalPlay
end

-- =====================================================================
-- E. v0.11.10 canonical scoring rule end-to-end via BotMaster rollout
-- =====================================================================
section("E. v0.11.10 canonical scoring drives BotMaster decisions correctly")

do
    -- Confirm K.MELD_CARRE_A_SUN is at the canonical 200 raw value,
    -- so BotMaster.rolloutValue's R.ScoreRound calls produce the
    -- correct EV diff for Sun-Carré-A meld scenarios.
    assertEq(K.MELD_CARRE_A_SUN, 200,
             "E.1 (v0.11.10): K.MELD_CARRE_A_SUN = 200 (canonical raw)")

    -- Direct R.ScoreRound check: Sun + Carré-A meld credited to bidder
    -- (post-make), no escalation. Expected meld nq = 200×Sun×2/10 = 40.
    -- Build a fixture where bidder team A makes the contract.
    freshState()
    S.s.contract = { type = K.BID_SUN, bidder = 1 }
    -- Build 8 simple tricks: A wins 7, B wins 1.
    local tricks = {}
    local cards = {}
    for _, suit in ipairs(K.SUITS) do
        for _, rank in ipairs(K.RANKS) do
            cards[#cards + 1] = rank .. suit
        end
    end
    local idx = 1
    for i = 1, 8 do
        local plays = {}
        for s = 1, 4 do
            plays[#plays + 1] = { seat = s, card = cards[idx] }
            idx = idx + 1
        end
        tricks[#tricks + 1] = {
            winner = (i == 4) and 2 or 1,  -- B wins trick 4; A wins others
            leadSuit = C.Suit(plays[1].card),
            plays = plays,
        }
    end
    local melds = {
        A = { { kind = "carre", value = K.MELD_CARRE_A_SUN, top = "A", len = 4, declaredBy = 1 } },
        B = {},
    }
    local res = R.ScoreRound(tricks, S.s.contract, melds)
    assertEq(res.bidderTeam, "A", "E.2a: bidderTeam = A")
    -- Bidder takes (made the contract OR was bidder). Either way the
    -- meld is credited to A's pile.
    -- raw.A includes (cardA + meldA) × Sun×2 = (cards + 200) × 2.
    -- Whatever cards A took, the meld portion = 400. Net delta from
    -- pre-meld (set melds = {}) should be exactly 400 raw.
    local resNoMeld = R.ScoreRound(tricks, S.s.contract, { A = {}, B = {} })
    local meldDelta = res.raw.A - resNoMeld.raw.A
    assertEq(meldDelta, 400,
             "E.2b (v0.11.10): Sun-Carré-A meld contributes 400 raw (200×Sun×2) — canonical")
    -- Final delta = 40 nq.
    assertEq(res.final.A - resNoMeld.final.A, 40,
             "E.2c (v0.11.10): Sun-Carré-A meld contributes 40 nq game points — canonical")
end

-- =====================================================================
-- F. v3.2.0 batch 3 — AD.4a single-card-shortcut diagnostic (behavioral)
-- =====================================================================
section("F. v3.2.0 batch 3 AD.4a single-card-shortcut")

-- AD.4a (BM-03) BEHAVIORAL — converted from source pin
-- `tests/test_state_bot.lua:3668` that scanned BotMaster.lua for the
-- literal `BM._lastShortCircuit = "single-card"` assignment. Pre-fix
-- the assertion only verified the line existed; this version proves
-- the diagnostic actually gets set on the single-card code path AND
-- that the returned card is the lone legal card.
do
    freshState()
    WHEREDNGNDB.saudiMasterBots = true
    S.s.isHost = true
    S.s.contract = { type = K.BID_HOKM, trump = "S", bidder = 1 }
    S.s.phase = K.PHASE_PLAY
    S.s.turn = 2
    S.s.turnKind = "play"
    -- Seat 2's hand has exactly 1 card. The trick already has a lead
    -- (any suit); the must-follow legality logic doesn't matter for
    -- this test because the only-1-card hand means there's only 1
    -- possible play regardless. The single-card shortcut at
    -- BotMaster.lua:1048 fires on `#legal == 1`.
    S.s.hostHands = {
        [1] = { "JS", "9S", "AS", "TS", "KS", "QS", "8S", "7S" },
        [2] = { "9C" },
        [3] = { "AD", "TD", "KD", "QD", "JD", "9D", "8D", "7D" },
        [4] = { "AC", "TC", "KC", "QC", "JC", "AH", "8C", "7C" },
    }
    S.s.tricks = {}
    S.s.trick = { leadSuit = "C",
                  plays = { { seat = 1, card = "AC" } } }
    S.s.playedCardsThisRound = {}
    S.s.akaCalled = nil

    BM._lastShortCircuit = nil
    BM._lastWorldsCompleted = nil
    local preInRollout = Bot._inRollout
    local pick = BM.PickPlay(2)

    -- The single legal card is returned.
    assertEq(pick, "9C",
        "F.1a (AD.4a behavioral): single-card hand returns that card from BM.PickPlay")
    -- The diagnostic tag is set so /baloot ismctsdiag distinguishes
    -- this fast path from "0 worlds because budget cut on iter 1".
    assertEq(BM._lastShortCircuit, "single-card",
        "F.1b (AD.4a behavioral): _lastShortCircuit tagged 'single-card'")
    assertEq(BM._lastWorldsCompleted, 0,
        "F.1c (AD.4a behavioral): _lastWorldsCompleted = 0 (no rollouts ran)")
    -- The _inRollout flag is restored (no leak even on the fast path).
    assertEq(Bot._inRollout, preInRollout,
        "F.1d (AD.4a behavioral): Bot._inRollout restored after single-card shortcut")
end

-- =====================================================================
-- G. v3.2.18 ISMCTS runtime memory guard + 3-bot world-count cap
-- =====================================================================
-- HIGH stability incident: WoW client freeze / high-memory crash
-- around trick ~3 in 1-human + 3-bot games. Root cause: the v0.11.17
-- wall-clock budget bounds ISMCTS *latency* but not *allocation* —
-- on a fast client the determinization / rollout loop can allocate
-- megabytes of transient tables well within 0.12s, and with 3
-- Saudi-Master bots sampling back-to-back per trick the Lua heap
-- spikes faster than the incremental GC reclaims it. v3.2.18 adds:
--   (1) a runtime memory emergency brake in the world loop,
--   (2) per-move memory telemetry surfaced via /baloot ismctsdiag,
--   (3) a more conservative world-count cap on 3+-bot tables,
--   (4) a single post-move incremental GC step (never a full
--       collect, never inside the tight loops).
-- Heuristic fallback when zero worlds complete is unchanged and is
-- re-validated here.

local function bmSrc()
    local f = io.open((ROOT .. "/BotMaster.lua"):gsub("\\", "/"), "r")
    local s = f:read("*a"); f:close(); return s
end
local function constSrc()
    local f = io.open((ROOT .. "/Constants.lua"):gsub("\\", "/"), "r")
    local s = f:read("*a"); f:close(); return s
end
local function slashSrc()
    local f = io.open((ROOT .. "/Slash.lua"):gsub("\\", "/"), "r")
    local s = f:read("*a"); f:close(); return s
end

section("G. v3.2.18 ISMCTS memory guard + 3-bot world cap")

-- G.1 BEHAVIORAL: a real multi-legal Saudi-Master move on a 3-bot
-- table enters the world loop, populates ALL new memory-telemetry
-- fields, AND has its world count reduced by the 3-bot cap (trick 0:
-- base 100 → min(100,50) = 50). One test covers Goal 1 (telemetry
-- fields exist + populated) and Goal 3 (3-bot reduction) behaviorally.
do
    freshState()
    WHEREDNGNDB.saudiMasterBots = true
    S.s.isHost = true
    S.s.phase = K.PHASE_PLAY
    S.s.contract = { type = K.BID_HOKM, trump = "S", bidder = 3 }
    -- 3 bot seats + 1 human → botSeatCount == 3 → reduction active.
    S.s.seats = {
        [1] = { isBot = true },
        [2] = { isBot = false, name = "Human" },
        [3] = { isBot = true },
        [4] = { isBot = true },
    }
    -- In-progress FIRST trick (no completed tricks → numTricks 0):
    -- seat 4 led 8H; seat 1 (bot caller) must follow Hearts → exactly
    -- 2 legal cards, so we enter the world loop (no single-card
    -- short-circuit) with a small, fast rollout set.
    S.s.tricks = {}
    S.s.trick = { leadSuit = "H", plays = { { seat = 4, card = "8H" } } }
    S.s.hostHands = {
        [1] = { "9H", "KH", "AS", "TS", "QD", "JD", "8C", "7C" },
        [2] = { "AH", "TH", "JH", "QH", "AD", "KD", "9D", "7D" },
        [3] = { "AC", "TC", "KC", "QC", "JC", "9C", "JS", "9S" },
        [4] = { "KS", "QS", "8S", "7S", "AD", "8D", "TD", "8H" },
    }
    S.s.playedCardsThisRound = { ["8H"] = true }
    S.s.akaCalled = nil

    local preInRollout = Bot._inRollout
    local pick = BM.PickPlay(1)

    assertTrue(pick ~= nil,
        "G.1a (v3.2.18): multi-legal Saudi-Master move returns a card (entered world loop)")
    assertTrue(pick == "9H" or pick == "KH",
        "G.1b (v3.2.18): returned card is one of the 2 follow-suit legal cards")
    -- Goal 3: 3-bot table caps trick-0 world count at 50 (was 100).
    assertEq(BM._lastNumWorlds, 50,
        "G.1c (v3.2.18): 3-bot table caps trick-0 numWorlds at 50 (base 100 reduced)")
    -- Goal 1: telemetry fields exist and are populated correctly.
    assertEq(BM._lastLegalCount, 2,
        "G.1d (v3.2.18): _lastLegalCount records the 2-card legal set")
    assertEq(BM._lastTrickCount, 0,
        "G.1e (v3.2.18): _lastTrickCount records trick index 0")
    assertEq(type(BM._lastMemKB), "number",
        "G.1f (v3.2.18): _lastMemKB is a number (memory delta telemetry present)")
    assertTrue(BM._lastMemKB >= 0,
        "G.1g (v3.2.18): _lastMemKB is non-negative (clamped delta)")
    assertEq(type(BM._lastMemCapped), "boolean",
        "G.1h (v3.2.18): _lastMemCapped is a boolean")
    assertFalse(BM._lastMemCapped,
        "G.1i (v3.2.18): memory brake did NOT trip on a tiny 50-world test (16MB cap)")
    assertTrue((BM._lastWorldsCompleted or 0) >= 1,
        "G.1j (v3.2.18): at least one world completed (loop actually ran)")
    assertEq(Bot._inRollout, preInRollout,
        "G.1k (v3.2.18): Bot._inRollout restored after a memory-guarded move")
end

-- G.2 BEHAVIORAL: heuristic fallback remains intact when ZERO worlds
-- complete. We force a 0-world outcome via a monotonic GetTime stub
-- so the wall-clock brake trips before world 1; BM.PickPlay must
-- return nil, and Bot.PickPlay must then fall through to the
-- heuristic picker and still return a legal card. (Goal 2 "fall back
-- to normal heuristic when the guard trips before any useful
-- rollout"; Goal 4 "heuristic fallback remains when zero worlds
-- complete".) The mem brake shares this exact 0-worlds → _restore(nil)
-- gate, so validating the time path validates the shared fallback.
do
    freshState()
    WHEREDNGNDB.saudiMasterBots = true
    S.s.isHost = true
    S.s.phase = K.PHASE_PLAY
    S.s.contract = { type = K.BID_HOKM, trump = "S", bidder = 3 }
    S.s.seats = {
        [1] = { isBot = true }, [2] = { isBot = true },
        [3] = { isBot = true }, [4] = { isBot = true },
    }
    S.s.tricks = {}
    S.s.trick = { leadSuit = "H", plays = { { seat = 4, card = "8H" } } }
    S.s.hostHands = {
        [1] = { "9H", "KH", "AS", "TS", "QD", "JD", "8C", "7C" },
        [2] = { "AH", "TH", "JH", "QH", "AD", "KD", "9D", "7D" },
        [3] = { "AC", "TC", "KC", "QC", "JC", "9C", "JS", "9S" },
        [4] = { "KS", "QS", "8S", "7S", "AD", "8D", "TD", "8H" },
    }
    S.s.playedCardsThisRound = { ["8H"] = true }
    S.s.akaCalled = nil

    -- Monotonic GetTime: every call advances 1000s, so the first
    -- in-loop overBudget() check (now - startedAt ≥ 1000 > 0.12s)
    -- trips before any world runs → worldsCompleted stays 0.
    local origGetTime = GetTime
    local _t = 0
    GetTime = function() _t = _t + 1000; return _t end

    local preInRollout = Bot._inRollout
    local mc = BM.PickPlay(1)
    assertTrue(mc == nil,
        "G.2a (v3.2.18): BM.PickPlay returns nil when 0 worlds complete (budget brake)")
    assertEq(BM._lastWorldsCompleted, 0,
        "G.2b (v3.2.18): _lastWorldsCompleted == 0 recorded")
    -- Bot.PickPlay must fall through to the heuristic picker.
    local hp = Bot.PickPlay(1)
    GetTime = origGetTime
    assertTrue(hp ~= nil,
        "G.2c (v3.2.18): Bot.PickPlay falls back to heuristic (non-nil card) when ISMCTS yields 0 worlds")
    assertTrue(hp == "9H" or hp == "KH",
        "G.2d (v3.2.18): heuristic fallback returned a legal follow-suit card")
    assertEq(Bot._inRollout, preInRollout,
        "G.2e (v3.2.18): Bot._inRollout restored after 0-world fallback (no leak)")
end

-- G.3 SOURCE PINS — BotMaster.lua: telemetry assignments + memory
-- guard structure + post-move incremental GC step, and the
-- "never a full collect" guarantee.
do
    local src = bmSrc()
    assertTrue(src:find("BM._lastNumWorlds = numWorlds", 1, true) ~= nil,
        "G.3a (v3.2.18): _lastNumWorlds telemetry assignment present")
    assertTrue(src:find("BM._lastLegalCount = #legal", 1, true) ~= nil,
        "G.3b (v3.2.18): _lastLegalCount telemetry assignment present")
    assertTrue(src:find("BM._lastTrickCount = numTricks", 1, true) ~= nil,
        "G.3c (v3.2.18): _lastTrickCount telemetry assignment present")
    assertTrue(src:find("BM._lastMemKB = math.max(0, math.floor((memNowKB() - startMemKB) + 0.5))", 1, true) ~= nil,
        "G.3d (v3.2.18): _lastMemKB net-delta telemetry assignment present")
    assertTrue(src:find("BM._lastMemCapped = memCapped", 1, true) ~= nil,
        "G.3e (v3.2.18): _lastMemCapped telemetry assignment present")
    assertTrue(src:find("local gcAvail = type(collectgarbage) == \"function\"", 1, true) ~= nil,
        "G.3f (v3.2.18): collectgarbage availability is guarded (graceful when absent)")
    assertTrue(src:find("local function overMemBudget()", 1, true) ~= nil,
        "G.3g (v3.2.18): overMemBudget() guard helper exists")
    assertTrue(src:find("(memNowKB() - startMemKB) > memBudgetKB", 1, true) ~= nil,
        "G.3h (v3.2.18): memory guard compares net heap growth to the budget")
    assertTrue(src:find("if overBudget() or overMemBudget() then break end", 1, true) ~= nil,
        "G.3i (v3.2.18): world loop breaks on time OR memory budget")
    -- v3.2.18 Codex polish #1: the post-move step must HONOR the
    -- documented "K.BOT_ISMCTS_GC_STEP_KB = 0 disables" contract.
    -- Pin the resolve + explicit `> 0` gate + the gated call so a
    -- regression back to a bare `if gcAvail then step(0)` is caught.
    assertTrue(src:find("local gcStepKB = (K and K.BOT_ISMCTS_GC_STEP_KB) or 256", 1, true) ~= nil,
        "G.3j (v3.2.18): GC step size resolved into gcStepKB before use")
    assertTrue(src:find("if gcAvail and gcStepKB > 0 then", 1, true) ~= nil,
        "G.3j2 (v3.2.18 Codex#1): post-move GC step gated on gcStepKB > 0 (0 disables)")
    assertTrue(src:find('collectgarbage("step", gcStepKB)', 1, true) ~= nil,
        "G.3j3 (v3.2.18): the gated post-move incremental GC step call is present")
    assertTrue(src:find('collectgarbage("step", (K and K.BOT_ISMCTS_GC_STEP_KB) or 256)', 1, true) == nil,
        "G.3j4 (v3.2.18 Codex#1): old un-gated step(0)-capable form is gone")
    assertTrue(src:find('collectgarbage("collect")', 1, true) == nil,
        "G.3k (v3.2.18): NO full collectgarbage(\"collect\") anywhere in BotMaster (never full-collect)")
    assertTrue(src:find("if worldsCompleted == 0 or rolloutErrors == worldsCompleted then", 1, true) ~= nil,
        "G.3l (v3.2.18): zero-worlds heuristic-fallback gate preserved")
    -- v3.2.18 Codex polish #2: _lastWorldsCompleted is reset in the
    -- per-move telemetry block (before the short-circuit exits), so
    -- the no-legal / legal-build-failed paths cannot surface a prior
    -- heavy move's completed-world count via /baloot ismctsdiag.
    do
        local resetStart = src:find("reset per-move telemetry", 1, true)
        local legalOkPos = src:find("local legalOk = pcall(buildLegalSet)", 1, true)
        assertTrue(resetStart ~= nil and legalOkPos ~= nil
            and src:find("BM._lastWorldsCompleted = 0", resetStart, true) ~= nil
            and src:find("BM._lastWorldsCompleted = 0", resetStart, true) < legalOkPos,
            "G.3m (v3.2.18 Codex#2): _lastWorldsCompleted = 0 reset before the short-circuit exits")
    end
end

-- G.4 SOURCE PINS — Constants.lua: the two new tunables exist with
-- the documented emergency-only defaults.
do
    local src = constSrc()
    assertTrue(src:find("K.BOT_ISMCTS_MEM_BUDGET_KB = 16384", 1, true) ~= nil,
        "G.4a (v3.2.18): K.BOT_ISMCTS_MEM_BUDGET_KB default 16384 present")
    assertTrue(src:find("K.BOT_ISMCTS_GC_STEP_KB = 256", 1, true) ~= nil,
        "G.4b (v3.2.18): K.BOT_ISMCTS_GC_STEP_KB default 256 present")
end

-- G.5 SOURCE PINS — Slash.lua: /baloot ismctsdiag surfaces the
-- memory delta + mem-capped tag.
do
    local src = slashSrc()
    assertTrue(src:find("local memKB = bm._lastMemKB or 0", 1, true) ~= nil,
        "G.5a (v3.2.18): ismctsdiag reads _lastMemKB")
    assertTrue(src:find("local memTag = bm._lastMemCapped", 1, true) ~= nil,
        "G.5b (v3.2.18): ismctsdiag reads _lastMemCapped")
    assertTrue(src:find("Δmem %dKB", 1, true) ~= nil,
        "G.5c (v3.2.18): ismctsdiag output includes the memory-delta field")
    assertTrue(src:find("[MEM-CAPPED]", 1, true) ~= nil,
        "G.5d (v3.2.18): ismctsdiag flags a memory-capped move")
end

-- G.6 SOURCE PIN — BotMaster.lua: the 3-bot world-count reduction
-- ladder (Goal 3), behaviorally proven by G.1c, pinned here so a
-- refactor can't silently drop the early/mid caps.
do
    local src = bmSrc()
    assertTrue(src:find("if botSeatCount >= 3 then", 1, true) ~= nil,
        "G.6a (v3.2.18): 3+-bot-seat branch present")
    assertTrue(src:find("numWorlds = math.min(numWorlds, 50)", 1, true) ~= nil,
        "G.6b (v3.2.18): trick≤2 3-bot cap = 50")
    assertTrue(src:find("numWorlds = math.min(numWorlds, 30)", 1, true) ~= nil,
        "G.6c (v3.2.18): trick≤5 3-bot cap = 30")
    assertTrue(src:find("numWorlds = math.min(numWorlds, 20)", 1, true) ~= nil,
        "G.6d (v3.2.18): late-trick 3-bot cap = 20")
end

-- G.7 BEHAVIORAL (v3.2.18 Codex polish #2): a short-circuit exit that
-- has NO _lastWorldsCompleted assignment of its own must still NOT
-- surface a prior heavy move's completed-world count. We seed a stale
-- value, then force the `no-legal-moves` exit by stubbing
-- R.IsLegalPlay → false for every card (a non-empty hand still reaches
-- the per-move telemetry reset + buildLegalSet, but #legal == 0). Only
-- the reset block can zero _lastWorldsCompleted on that path, so this
-- isolates the fix end-to-end (the single-card path's own reset is
-- separately covered by F.1c).
do
    freshState()
    WHEREDNGNDB.saudiMasterBots = true
    S.s.isHost = true
    S.s.phase = K.PHASE_PLAY
    S.s.contract = { type = K.BID_HOKM, trump = "S", bidder = 3 }
    S.s.seats = {
        [1] = { isBot = true }, [2] = { isBot = true },
        [3] = { isBot = true }, [4] = { isBot = true },
    }
    S.s.tricks = {}
    S.s.trick = { leadSuit = "H", plays = { { seat = 4, card = "8H" } } }
    S.s.hostHands = {
        [1] = { "9H", "KH", "AS", "TS", "QD", "JD", "8C", "7C" },
        [2] = { "AH", "TH", "JH", "QH", "AD", "KD", "9D", "7D" },
        [3] = { "AC", "TC", "KC", "QC", "JC", "9C", "JS", "9S" },
        [4] = { "KS", "QS", "8S", "7S", "AD", "8D", "TD", "8H" },
    }
    S.s.playedCardsThisRound = { ["8H"] = true }
    S.s.akaCalled = nil

    -- Simulate a prior heavy move having left a non-zero count.
    BM._lastWorldsCompleted = 999
    BM._lastShortCircuit = nil

    local origIsLegal = R.IsLegalPlay
    R.IsLegalPlay = function() return false end
    local preInRollout = Bot._inRollout
    local pick = BM.PickPlay(1)
    R.IsLegalPlay = origIsLegal

    assertTrue(pick == nil,
        "G.7a (v3.2.18 Codex#2): forced no-legal short-circuit returns nil")
    assertEq(BM._lastShortCircuit, "no-legal-moves",
        "G.7b (v3.2.18 Codex#2): took the no-legal-moves exit (no own _lastWorldsCompleted write)")
    assertEq(BM._lastWorldsCompleted, 0,
        "G.7c (v3.2.18 Codex#2): stale _lastWorldsCompleted (999) cleared to 0 by the reset block")
    assertEq(Bot._inRollout, preInRollout,
        "G.7d (v3.2.18 Codex#2): Bot._inRollout restored after the no-legal short-circuit")
end

-- =====================================================================
-- Summary
-- =====================================================================
print("")
print(("== Result: %d passed, %d failed =="):format(pass, fail))
TEST_RESULTS = { passed = pass, failed = fail }
if fail == 0 then return true end
return false
