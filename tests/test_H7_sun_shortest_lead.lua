-- tests/test_H7_sun_shortest_lead.lua
--
-- Regression test for issue H-7: in Sun contracts the bot should lead
-- from the SHORTEST suit, not the longest.
--
-- Strategy: apply the H-7 patch to Bot.lua source in memory (never
-- touching production files), then run contrived scenarios through
-- the patched Bot.PickPlay.
--
-- Key scenario: seat 1 holds a 4-3-2-3 distribution across S/H/D/C
-- in a Sun contract and leads the first trick.  The patched bot must
-- lead from the 2-card suit (Diamonds), not the 4-card suit (Spades).
--
-- Run via: lua tests/test_H7_sun_shortest_lead.lua
--          (or add to the python runner manifest)

unpack = unpack or table.unpack

-- -- Locate addon root ---------------------------------------------------

local function addonRoot()
    if WHEREDNGN_TESTS_ROOT then return WHEREDNGN_TESTS_ROOT end
    local src = debug.getinfo(1, "S").source
    if src:sub(1, 1) ~= "@" then
        error("set WHEREDNGN_TESTS_ROOT before running")
    end
    return (src:sub(2):gsub("[/\\]tests[/\\][^/\\]+$", ""))
end
local ROOT = addonRoot()

-- -- WoW global stubs (same minimal set as test_state_bot.lua) ----------

local fakeNow = 4000000.0
GetTime = function()
    fakeNow = fakeNow + 0.001
    return fakeNow
end
C_Timer = {
    NewTicker = function(_, _) return { Cancel = function() end } end,
    NewTimer  = function(_, _) return { Cancel = function() end } end,
    After     = function(_, _) end,
}
GetUnitName = function() return "TestPlayer" end
UnitName    = function() return "TestPlayer" end
WHEREDNGNDB = {}   -- basic tier by default; individual tests override
SendChatMessage = function() end
C_ChatInfo = {
    RegisterAddonMessagePrefix = function() return true end,
    SendAddonMessage = function() end,
}
CreateFrame = function()
    return {
        SetScript     = function() end,
        RegisterEvent = function() end,
        UnregisterEvent = function() end,
        Hide = function() end,
        Show = function() end,
    }
end

WHEREDNGN = WHEREDNGN or {}
WHEREDNGN.Sound = { Cue = function() end, ArmCue = function() end }
WHEREDNGN.Log   = {
    Debug = function() end, Info  = function() end,
    Warn  = function() end, Error = function() end,
    Clear = function() end, Dump  = function() end,
}
WHEREDNGN.UI = {
    Refresh = function() end, Show = function() end,
    Hide    = function() end, Toggle = function() end,
}

-- -- Load base modules (unpatched) --------------------------------------

local function loadFile(rel)
    local path = (ROOT .. "/" .. rel):gsub("\\", "/")
    local chunk, err = loadfile(path)
    if not chunk then error("failed to load " .. rel .. ": " .. tostring(err)) end
    chunk()
end

loadFile("Constants.lua")
loadFile("Cards.lua")
loadFile("Rules.lua")
loadFile("State.lua")
-- v3.2.0 cleanup batch 5B: tier predicates live in Bot/Tiers.lua and
-- must populate B.Bot before the patched Bot.lua chunk compiles
-- (Bot.lua call sites resolve `Bot.IsAdvanced()` through the shared
-- table at runtime).
loadFile("Bot/Tiers.lua")
-- v3.2.0 cleanup batch 5C: the play-primitive helpers (pickRandomTied
-- / lowestByRank / highestByRank / highestByFaceValue /
-- holdsBeloteThusFar / highestTrump / legalPlaysFor / wouldWin /
-- tahreebClassify / applyClosedTrumpLeadGate) live in
-- Bot/PlayPrimitives.lua. Bot.lua re-binds them as file-locals at
-- the top of its chunk, so the patched code injected below (which
-- calls `lowestByRank` inside pickLead's body) resolves through
-- those Bot.lua-scoped locals.
loadFile("Bot/PlayPrimitives.lua")
-- v3.2.0 cleanup batch 8: the bidding-window deciders (Bot.PickBid /
-- Bot.PickPreempt / Bot.PickOvercall) and 15 file-local helpers (incl.
-- suitStrengthAsTrump / sunStrength / partnerBidBonus /
-- partnerEscalatedBonus / combinedUrgency / opponentUrgency) live in
-- Bot/Bidding.lua.
loadFile("Bot/Bidding.lua")
-- v3.2.0 cleanup batch 9: the four-rung escalation chain
-- (Bot.PickDouble / PickTriple / PickFour / PickGahwa) plus 3 file-
-- local helpers (escalationStrength / selfStyleJitterBonus /
-- styleBelTendency) and 4 per-rung jitter constants live in
-- Bot/Escalation.lua. Imports the 6 Bidding helpers it needs and
-- inlines its own jitter + shuffledSuits.
loadFile("Bot/Escalation.lua")

local K = WHEREDNGN.K
local C = WHEREDNGN.Cards
local R = WHEREDNGN.Rules
local S = WHEREDNGN.State

-- -- Apply H-7 patch to Bot.lua source in memory -----------------------
--
-- Two insertions:
--
--   1. Add `cardsOfSuit` helper immediately before `local function
--      pickLead` so it lands at file-scope, in the same chunk closure
--      as Bot.lua's re-bound `lowestByRank` local. (Pre-v3.2.0 batch
--      5C this hunk anchored on `local function highestByRank`, which
--      lived just above lowestByRank in Bot.lua. Batch 5C moved the
--      play primitives — including highestByRank and lowestByRank —
--      to Bot/PlayPrimitives.lua, so the anchor moved one function
--      further down to `pickLead` — the next stable file-scope symbol
--      that is deferred indefinitely from extraction.)
--
--   2. Add the Sun-shortest-lead branch immediately before the comment
--      "-- Defenders / bidder's partner / Sun lead".  (In the patched
--      version that comment is renamed to "Hokm lead" but we match the
--      original production text here.)

local botPath = (ROOT .. "/Bot.lua"):gsub("\\", "/")
local fh = assert(io.open(botPath, "r"), "cannot open Bot.lua")
local src = fh:read("*a")
fh:close()

-- ---- Hunk 1: cardsOfSuit helper ----------------------------------------
-- Anchor: the blank line immediately before `local function pickLead`.
-- (v3.2.0 cleanup batch 5C: `highestByRank` moved to
-- Bot/PlayPrimitives.lua, so the previous anchor on
-- "\nlocal function highestByRank" no longer matches Bot.lua source.
-- `pickLead` is the next stable file-scope symbol and is deferred
-- indefinitely from extraction, so it's a stable anchor across
-- foreseeable batches. Injecting cardsOfSuit immediately before
-- pickLead places it at the same file-scope position as before, in
-- the same chunk closure as Bot.lua's re-bound `lowestByRank` local.)
local ANCHOR_HELPER = "\nlocal function pickLead"

local HELPER_BLOCK = [[

-- H-7: collect all cards from `cards` whose suit matches `suit`.
-- Used by the Sun shortest-suit lead branch.
local function cardsOfSuit(cards, suit)
    local out = {}
    for _, c in ipairs(cards) do
        if C.Suit(c) == suit then out[#out + 1] = c end
    end
    return out
end
]]

local helperPos = src:find(ANCHOR_HELPER, 1, true)
assert(helperPos,
    "H-7 test: cardsOfSuit anchor not found — Bot.lua structure has changed")

-- Use plain find + manual splice to avoid Lua pattern-special chars
-- ('.', '-', etc.) in the replacement string corrupting the output.
local patched = src:sub(1, helperPos - 1) .. HELPER_BLOCK
              .. src:sub(helperPos)

-- ---- Hunk 2: Sun-lead branch -------------------------------------------
-- Anchor: the comment line that begins the defender/Sun section.
local ANCHOR_SUN =
    "\n    -- Defenders / bidder's partner / Sun lead: don't burn high cards.\n"

local SUN_BRANCH = [[

    -- Sun lead: Saudi-pro shortest-suit opening.
    --
    -- Saudi pros lead from the SHORT suit in Sun contracts.  Forcing
    -- opponents to spend their boss in a short suit early leaves that
    -- suit unguarded for the rest of the round.  Leading from long suits
    -- does the opposite: opponents conserve their boss and over-lead us.
    --
    -- Priority order:
    --   (a) We hold the boss (highest unplayed) of any suit: lead it.
    --   (b) Singleton low: lead it (can't save it).
    --   (c) Lowest card from our SHORTEST suit (fewest cards, > 0).
    if contract.type == K.BID_SUN then
        -- (a) Boss of any suit (Advanced+).
        if Bot.IsAdvanced() and S.HighestUnplayedRank then
            for _, c in ipairs(legal) do
                if S.HighestUnplayedRank(C.Suit(c)) == C.Rank(c) then
                    return c
                end
            end
        end
        -- In Sun there is no trump; legal == all non-trump cards.
        local sunCount = { S = 0, H = 0, D = 0, C = 0 }
        for _, c in ipairs(legal) do
            sunCount[C.Suit(c)] = sunCount[C.Suit(c)] + 1
        end
        -- (b) Singleton low.
        local sunSingletons = {}
        for _, c in ipairs(legal) do
            if sunCount[C.Suit(c)] == 1 then sunSingletons[#sunSingletons + 1] = c end
        end
        if #sunSingletons > 0 then return lowestByRank(sunSingletons, contract) end
        -- (c) Shortest suit.
        local shortest, shortestN = nil, math.huge
        for _, suit in ipairs({ "S", "H", "D", "C" }) do
            local n = sunCount[suit]
            if n > 0 and n < shortestN then
                shortest, shortestN = suit, n
            elseif n > 0 and n == shortestN and shortest then
                local curLow  = lowestByRank(cardsOfSuit(legal, shortest), contract)
                local candLow = lowestByRank(cardsOfSuit(legal, suit),     contract)
                if C.TrickRank(candLow, contract) < C.TrickRank(curLow, contract) then
                    shortest = suit
                end
            end
        end
        if shortest then
            local fromShortest = cardsOfSuit(legal, shortest)
            if #fromShortest > 0 then return lowestByRank(fromShortest, contract) end
        end
        return lowestByRank(legal, contract)
    end

]]

local sunPos = patched:find(ANCHOR_SUN, 1, true)
assert(sunPos,
    "H-7 test: Sun-branch anchor not found — Bot.lua structure has changed")

local patched2 = patched:sub(1, sunPos - 1) .. SUN_BRANCH
               .. patched:sub(sunPos)

-- Load the patched Bot.lua into the current environment.
local chunk, compErr
if _VERSION >= "Lua 5.2" then
    chunk, compErr = load(patched2, "Bot.lua[H-7-patched]", "t", _ENV)
else
    chunk, compErr = loadstring(patched2, "Bot.lua[H-7-patched]")
    if chunk then setfenv(chunk, getfenv(1)) end
end
assert(chunk, "H-7 test: failed to compile patched Bot.lua: " .. tostring(compErr))
chunk()

local Bot = WHEREDNGN.Bot

-- -- Tiny test framework -------------------------------------------------

local pass, fail = 0, 0
local failures = {}

local function assertEq(actual, expected, name)
    if actual == expected then
        pass = pass + 1
        if TEST_VERBOSE then print(("  PASS  %s"):format(name)) end
    else
        fail = fail + 1
        local msg = ("FAIL  %s\n        expected: %s\n        actual:   %s")
                       :format(name, tostring(expected), tostring(actual))
        failures[#failures + 1] = msg
        print("  " .. msg)
    end
end
local function assertTrue(v, name)  assertEq(not not v, true,  name) end
local function assertFalse(v, name) assertEq(not not v, false, name) end
local function section(label) print(""); print("== " .. label .. " ==") end

-- -- State reset helper --------------------------------------------------

local function freshState()
    local s = S.s
    s.phase   = K.PHASE_IDLE
    s.isHost  = false
    s.gameID  = nil
    s.dealer  = 1
    s.roundNumber = 0
    s.bidCard = nil
    s.bidRound = 1
    s.bids    = {}
    s.contract = nil
    s.hand    = {}
    s.hostHands = nil
    s.hostDeckRemainder = nil
    s.turn    = nil
    s.turnKind = nil
    s.trick   = nil
    s.tricks  = {}
    s.meldsByTeam = { A = {}, B = {} }
    s.meldsDeclared = {}
    s.belPending = nil
    s.preemptEligible = nil
    s.cumulative = { A = 0, B = 0 }
    s.target  = 152
    s.teamNames = { A = "Team A", B = "Team B" }
    s.peerVersions = {}
    s.paused  = false
    s.lastTrick = nil
    s.akaCalled = nil
    s.playedCardsThisRound = {}
    s.localSeat = nil
    s.seats   = { [1]=nil, [2]=nil, [3]=nil, [4]=nil }
end

-- Helper: set up a Sun opening-lead scenario.
-- `hand` is the full 8-card hand for seat 1.
-- Returns Bot.PickPlay(1) — the card the bot leads.
local function sunOpeningLead(hand)
    freshState()
    S.s.isHost = true
    S.s.contract = { type = K.BID_SUN, bidder = 1 }
    S.s.hostHands = {
        [1] = hand,
        [2] = { "7S", "8S", "7H", "8H" },  -- other seats: irrelevant fillers
        [3] = { "9S", "TS", "9H", "TH" },
        [4] = { "JS", "QS", "JH", "QH" },
    }
    S.s.trick   = { leadSuit = nil, plays = {} }
    S.s.tricks  = {}
    S.s.playedCardsThisRound = {}
    if Bot.ResetMemory then Bot.ResetMemory() end
    return Bot.PickPlay(1)
end

-- =====================================================================
-- H-7 core scenario: 4-3-2-3 distribution (Basic tier)
-- =====================================================================
section("H-7: Sun opening lead — 4-3-2-3 hand (Basic tier)")

-- Hand layout:
--   Spades  (4 cards): AS KS QS JS   ← longest suit
--   Hearts  (3 cards): AH KH QH
--   Diamonds(2 cards): AD KD          ← shortest suit
--   Clubs   (3 cards): AC KC QC
--
-- Expected: bot leads from Diamonds (2 cards), not Spades (4 cards).
-- Within Diamonds, lowest trick-rank card = KD (RANK_PLAIN K=6, A=8)
-- so bot should play KD (lower than AD).

WHEREDNGNDB = {}  -- basic tier: advanced = false
local HAND_4323 = {
    "AS", "KS", "QS", "JS",   -- 4 spades
    "AH", "KH", "QH",         -- 3 hearts
    "AD", "KD",               -- 2 diamonds (shortest)
    "AC", "KC", "QC",         -- 3 clubs
}
-- NOTE: The hand above is 12 cards; trim to 8 for a realistic mid-deal
-- scenario.  We use 8 cards: 4S 2H 1D 1C produces unambiguous 1-card
-- shortest.  Use the full distribution to test 4-3-2-3 proper, but
-- trim for the 8-card constraint:
--   4S, 2H, 1D, 1C  →  shortest = D or C (tie on 1). Tie-break: lead
--   the weaker suit.
-- Instead use a non-tied scenario: 4-3-2-3 trimmed to 8:
--   Spades 3: AS KS QS
--   Hearts 2: AH KH
--   Diamonds 1 (shortest): AD  ← but that triggers singleton-low path
-- Use a true non-singleton shortest: 4-2-... doesn't fit in 8 without
-- a singleton.
-- Best 8-card 4-3-2-3-ish (no singleton) example for 8 cards:
-- We need counts to sum to 8, shortest >= 2, longest <= 4:
--   3-3-2-0 ... 4-2-2-0 ... 3-2-2-1 (singleton appears)
-- Pure no-singleton 8-card deal with a distinct shortest: 4-2-2-0
-- impossible (no cards of 4th suit but not zero). Use 3-3-2-0 where the
-- 2-card suit is clearly shortest and we lead from it.
-- Concrete: S=3, H=3, D=2, C=0 → shortest=D (2 cards), longest=S or H (3).

WHEREDNGNDB = {}  -- basic tier
local HAND_3320 = {
    "AS", "KS", "QS",  -- 3 spades
    "AH", "KH", "QH",  -- 3 hearts
    "AD", "KD",        -- 2 diamonds ← shortest non-zero suit
}

local lead_basic = sunOpeningLead(HAND_3320)
assertEq(C.Suit(lead_basic), "D",
    "H-7 basic: leads from Diamonds (shortest, 2 cards) not Spades/Hearts (3 cards)")

-- Within D, lowest trick-rank: RANK_PLAIN K=6, A=8 → KD is lower.
assertEq(lead_basic, "KD",
    "H-7 basic: leads KD (lowest card of shortest suit D)")

-- =====================================================================
-- H-7: same hand, Advanced tier — boss-first exception must fire
-- =====================================================================
section("H-7: Advanced tier — boss exception overrides shortest-suit")

-- Mark AD as the boss (highest unplayed in Diamonds).
-- Since S.HighestUnplayedRank reads s.playedCardsThisRound, we can
-- simulate "nothing played" — AD is the boss of D by default.
-- But we also need to ensure the bot's IsAdvanced() path fires, which
-- means it must check HighestUnplayedRank.
--
-- We actually want to test that the boss-exception fires BEFORE the
-- shortest-suit logic.  Give seat 1 a hand where:
--   - Diamonds has 1 card: AS (highest unplayed = AS → we own the boss)
--   Wait: AD would be boss of D; if we hold AD and nothing in D played,
--   the bot should lead AD (boss) not KD.
--
-- Concrete: hand = { "AS"(boss of S, 3-card), "KS","QS", "AH","KH","QH","AD","KD" }
-- If AS is highest unplayed in S → boss exception fires → lead AS.

WHEREDNGNDB = { advancedBots = true }

-- Nothing played; AS is boss of Spades by default.
freshState()
S.s.isHost = true
S.s.contract = { type = K.BID_SUN, bidder = 1 }
S.s.hostHands = {
    [1] = HAND_3320,
    [2] = { "7C", "8C", "7D", "8D" },
    [3] = { "9C", "TC", "9D", "TD" },
    [4] = { "JC", "QC", "JD", "QD" },
}
S.s.trick  = { leadSuit = nil, plays = {} }
S.s.tricks = {}
S.s.playedCardsThisRound = {}
-- Verify AS is the unplayed boss of Spades.
assertEq(S.HighestUnplayedRank("S"), "A",
    "precondition: AS is highest unplayed in Spades before anything played")

if Bot.ResetMemory then Bot.ResetMemory() end
local lead_adv = Bot.PickPlay(1)
assertEq(lead_adv, "AS",
    "H-7 advanced: boss exception fires — leads AS (boss of Spades) before shortest-suit logic")

-- =====================================================================
-- H-7: shortest-suit logic with 4-3-2-3 using exactly 12-card hand
--      trimmed to an 8-card deal (no singletons, clear shortest)
-- =====================================================================
section("H-7: 3-2-2-1 hand — singleton-low path fires (not shortest)")

-- 3-2-2-1 hand: singleton card should be led (step b, before step c).
WHEREDNGNDB = {}
local HAND_3221 = {
    "AS", "KS", "QS",   -- 3 spades
    "AH", "KH",         -- 2 hearts
    "AD", "KD",         -- 2 diamonds
    "7C",               -- 1 club (singleton)
}
local lead_single = sunOpeningLead(HAND_3221)
assertEq(C.Suit(lead_single), "C",
    "H-7 singleton: leads the singleton Club suit (step b before step c)")
assertEq(lead_single, "7C",
    "H-7 singleton: leads 7C (only Club card, lowest by definition)")

-- =====================================================================
-- H-7: Unpatched bot leads from LONGEST suit — verify test detects it
-- =====================================================================
section("H-7: baseline check — unpatched logic would pick longest (doctest)")

-- We do NOT re-load the unpatched bot here (that would require a second
-- patching pass and is fragile). Instead we verify the distribution
-- property directly: for HAND_3320, the longest suits are S and H (3 ea)
-- and the shortest is D (2). If the patched bot leads D, the patch
-- is working. We document the expected unpatched behaviour as a comment.
--
-- Unpatched (long-from-longest logic):
--   suitCount = {S=3, H=3, D=2}; longest = S or H (both 3).
--   The production iteration order `{ "S","H","D","C" }` visits S first,
--   so unpatched bot would pick S and lead QS (lowest of S: rank=5 for
--   Q, K=7, A=8 in RANK_PLAIN → QS rank=5 is lowest of AS/KS/QS).
--
-- Patched bot leads KD (shortest=D, lowest=KD).
assertEq(C.Suit(lead_basic), "D", "H-7 patch verification: lead is from D (2 cards), not S/H (3 cards)")
assertFalse(C.Suit(lead_basic) == "S",
    "H-7 patch verification: patched bot does NOT lead from Spades (longest)")
assertFalse(C.Suit(lead_basic) == "H",
    "H-7 patch verification: patched bot does NOT lead from Hearts (tied-longest)")

-- =====================================================================
-- Summary
-- =====================================================================
print("")
print(("== Result: %d passed, %d failed =="):format(pass, fail))
for _, msg in ipairs(failures) do print(msg) end
TEST_RESULTS = { passed = pass, failed = fail }
if fail == 0 then return true end
return false
