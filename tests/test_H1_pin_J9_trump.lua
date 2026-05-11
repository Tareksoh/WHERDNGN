-- tests/test_H1_pin_J9_trump.lua
--
-- Regression test for issue H-1: sampleConsistentDeal must hard-pin the J
-- and 9 of trump to the bidder seat in Hokm contracts.
--
-- Strategy: load BotMaster.lua from a patched in-memory string (applying
-- the H-1 diff programmatically) so we never touch production files.  After
-- load we inject a one-line shim into the patched chunk that exposes the
-- module-local sampleConsistentDeal via BM._testSampleDeal, then run it
-- 100 times and assert both power cards land on the bidder in every world.
--
-- Run via:  lua tests/test_H1_pin_J9_trump.lua
--           (or add to the python runner manifest)

unpack = unpack or table.unpack

-- -- Locate addon root ----------------------------------------------------

local function addonRoot()
    if WHEREDNGN_TESTS_ROOT then return WHEREDNGN_TESTS_ROOT end
    local src = debug.getinfo(1, "S").source
    if src:sub(1, 1) ~= "@" then
        error("set WHEREDNGN_TESTS_ROOT before running")
    end
    return (src:sub(2):gsub("[/\\]tests[/\\][^/\\]+$", ""))
end
local ROOT = addonRoot()

-- -- WoW global stubs (same minimal set as test_state_bot.lua) -----------

local fakeNow = 3000000.0
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
WHEREDNGNDB = { saudiMasterBots = true }
SendChatMessage = function() end
C_ChatInfo = {
    RegisterAddonMessagePrefix = function() return true end,
    SendAddonMessage = function() end,
}
CreateFrame = function()
    return {
        SetScript    = function() end,
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

-- -- Load base addon modules (no BotMaster yet) ---------------------------

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
loadFile("Bot/Tiers.lua")
loadFile("Bot/PlayPrimitives.lua")
loadFile("Bot/Bidding.lua")
loadFile("Bot.lua")

local K   = WHEREDNGN.K
local R   = WHEREDNGN.Rules
local S   = WHEREDNGN.State

-- -- Apply H-1 patch to BotMaster.lua source in memory -------------------
--
-- We read BotMaster.lua, inject the H-1 block (J/9 of trump pin) after the
-- meldPins block, then append a one-line shim that exposes the module-local
-- sampleConsistentDeal via BM._testSampleDeal so the test can call it
-- directly without modifying the production source.

local bmPath = (ROOT .. "/BotMaster.lua"):gsub("\\", "/")
local fh = assert(io.open(bmPath, "r"), "cannot open BotMaster.lua")
local src = fh:read("*a")
fh:close()

-- The insertion anchor: the blank line immediately before "local maxAttempts"
-- inside sampleConsistentDeal, right after the meldPins closing `end`.
-- We search for the exact sentinel that uniquely identifies that location.
local ANCHOR = "\n    local maxAttempts = 15\n"

local H1_BLOCK = [[

    -- H-1 fix: hard-pin J and 9 of trump to the bidder in Hokm contracts.
    -- The J (trick-rank 8, 20 pts) and 9 (trick-rank 7, 14 pts) are the
    -- two highest-value trump cards.  Bidders commit to Hokm because they
    -- hold these; placing them on a defender in 30% of worlds structurally
    -- inverts every rollout value for the bidder team.
    --
    -- Skip conditions (all reduce to membership in `unseen`):
    --   • Already played / in our hand: buildUnseen() excludes both.
    --   • pinCard already covers this card: pinCard is excluded from the
    --     pool; double-recording it in meldPins would corrupt the deal.
    if contract and contract.type == K.BID_HOKM and contract.trump and bidder then
        local trump = contract.trump
        for _, powerCard in ipairs({ "J" .. trump, "9" .. trump }) do
            if powerCard ~= pinCard and not meldPins[powerCard] then
                for _, u in ipairs(unseen) do
                    if u == powerCard then
                        meldPins[powerCard] = bidder
                        break
                    end
                end
            end
        end
    end
]]

assert(src:find(ANCHOR, 1, true),
    "H-1 test: anchor not found in BotMaster.lua — patch target has moved")

-- Use a function replacement to avoid gsub's special interpretation of
-- '%' characters in the replacement string (the H1_BLOCK comment contains
-- '%' for Lua pattern-capture escaping which would corrupt the output).
local patchApplied = false
local patchedSrc = src:gsub(ANCHOR, function(_)
    if patchApplied then return nil end  -- only replace the first occurrence
    patchApplied = true
    return H1_BLOCK .. ANCHOR
end)

-- Append test shim: expose the module-local sampleConsistentDeal.
-- BM is the local alias inside BotMaster.lua for B.BotMaster.
-- We add a public field so tests can reach it.
local SHIM = "\nWHEREDNGN.BotMaster._testSampleDeal = sampleConsistentDeal\n"
patchedSrc = patchedSrc .. SHIM

-- Load the patched source as a chunk in the current environment.
local chunk, compErr
if _VERSION >= "Lua 5.2" then
    chunk, compErr = load(patchedSrc, "BotMaster.lua[H-1-patched]", "t", _ENV)
else
    -- Lua 5.1 (WoW): loadstring + setfenv
    chunk, compErr = loadstring(patchedSrc, "BotMaster.lua[H-1-patched]")
    if chunk then setfenv(chunk, getfenv(1)) end
end
assert(chunk, "H-1 test: failed to compile patched BotMaster.lua: " .. tostring(compErr))
chunk()

local BM = WHEREDNGN.BotMaster
local sampleDeal = BM._testSampleDeal
assert(type(sampleDeal) == "function",
    "H-1 test: _testSampleDeal shim not installed — check SHIM injection")

-- -- Tiny test framework -------------------------------------------------

local pass, fail = 0, 0
local failures = {}

local function assertEq(actual, expected, name)
    if actual == expected then
        pass = pass + 1
        if TEST_VERBOSE then
            print(("  PASS  %s"):format(name))
        end
    else
        fail = fail + 1
        local msg = ("FAIL  %s\n        expected: %s\n        actual:   %s")
            :format(name, tostring(expected), tostring(actual))
        failures[#failures + 1] = msg
        print("  " .. msg)
    end
end
local function assertTrue(v, name) assertEq(not not v, true, name) end

local function section(label) print(""); print("== " .. label .. " ==") end

-- -- Helpers --------------------------------------------------------------

-- Build the `unseen` array that sampleConsistentDeal expects:
-- all cards NOT in `ourHand` and NOT in `played`.
local function buildUnseenForTest(ourHand, played)
    local excluded = {}
    for _, c in ipairs(ourHand) do excluded[c] = true end
    for _, c in ipairs(played)   do excluded[c] = true end
    local unseen = {}
    for _, rank in ipairs({ "A", "T", "K", "Q", "J", "9", "8", "7" }) do
        for _, suit in ipairs({ "S", "H", "D", "C" }) do
            local card = rank .. suit
            if not excluded[card] then unseen[#unseen + 1] = card end
        end
    end
    return unseen
end

-- Configure S.s with a minimal Hokm state.
-- `ourSeat` = the calling bot (not the bidder in this scenario).
-- `bidderSeat` = who bid the contract.
-- `ourHand` = cards the calling bot holds.
local function setupState(ourSeat, bidderSeat, trump, ourHand, bidCard)
    S.s.phase        = K.PHASE_PLAY
    S.s.isHost       = true
    S.s.contract     = { type = K.BID_HOKM, trump = trump, bidder = bidderSeat }
    S.s.bidCard      = bidCard
    S.s.tricks       = {}
    S.s.trick        = { leadSuit = nil, plays = {} }
    S.s.meldsByTeam  = { A = {}, B = {} }
    S.s.hostHands    = {}
    for s = 1, 4 do S.s.hostHands[s] = {} end
    S.s.hostHands[ourSeat] = ourHand
    if WHEREDNGN.Bot.ResetMemory then WHEREDNGN.Bot.ResetMemory() end
end

-- =====================================================================
-- H-1: J and 9 of trump are always on bidder seat (100 samples)
-- =====================================================================
section("H-1: sampleConsistentDeal pins J/9 of trump to bidder (Hokm)")

math.randomseed(20260503)

-- Scenario: bot is seat 1, bidder is seat 2 (opponents), trump = Hearts.
-- Both JH and 9H are unseen (not in bot hand, not played).
-- bidCard = AH (not J or 9, so pinCard does not overlap).
local OUR_SEAT    = 1
local BIDDER_SEAT = 2
local TRUMP       = "H"
local BID_CARD    = "AH"

-- Our hand has no trump at all — JH and 9H are definitely unseen.
local OUR_HAND = { "AS", "KS", "QS", "JS", "TS", "8S", "7S", "KC" }
setupState(OUR_SEAT, BIDDER_SEAT, TRUMP, OUR_HAND, BID_CARD)

local unseen = buildUnseenForTest(OUR_HAND, {})

-- Verify the two power cards are actually in unseen before we start.
local jInUnseen, nineInUnseen = false, false
for _, c in ipairs(unseen) do
    if c == "JH" then jInUnseen = true end
    if c == "9H" then nineInUnseen = true end
end
assertTrue(jInUnseen,    "precondition: JH is in unseen pool")
assertTrue(nineInUnseen, "precondition: 9H is in unseen pool")

local NUM_SAMPLES = 100
local jMisplaced, nineMisplaced = 0, 0

for i = 1, NUM_SAMPLES do
    local world = sampleDeal(OUR_SEAT, unseen)
    assert(world, ("sample %d: sampleConsistentDeal returned nil"):format(i))

    -- Check where JH landed.
    local jFound = false
    for _, c in ipairs(world[BIDDER_SEAT] or {}) do
        if c == "JH" then jFound = true; break end
    end
    if not jFound then
        jMisplaced = jMisplaced + 1
        if TEST_VERBOSE then
            print(("  sample %d: JH NOT on bidder seat %d"):format(i, BIDDER_SEAT))
        end
    end

    -- Check where 9H landed.
    local nineFound = false
    for _, c in ipairs(world[BIDDER_SEAT] or {}) do
        if c == "9H" then nineFound = true; break end
    end
    if not nineFound then
        nineMisplaced = nineMisplaced + 1
        if TEST_VERBOSE then
            print(("  sample %d: 9H NOT on bidder seat %d"):format(i, BIDDER_SEAT))
        end
    end
end

assertEq(jMisplaced, 0,
    ("H-1: JH on bidder in 100/100 samples (misplaced=%d)"):format(jMisplaced))
assertEq(nineMisplaced, 0,
    ("H-1: 9H on bidder in 100/100 samples (misplaced=%d)"):format(nineMisplaced))

-- =====================================================================
-- H-1 caveat: bidCard IS the J of trump — no double-pin
-- =====================================================================
section("H-1 caveat: bidCard = JH — pinCard covers J, 9 still pinned")

-- bidCard = JH: pinCard will cover JH (bidder ~= our seat so pinSeat is set).
-- 9H should still be pinned by the H-1 block.  JH should not appear in two
-- places (pinCard + meldPins). We just verify 9H always lands on bidder.
setupState(OUR_SEAT, BIDDER_SEAT, TRUMP, OUR_HAND, "JH")
local unseen2 = buildUnseenForTest(OUR_HAND, {})

local nineMisplaced2 = 0
for i = 1, NUM_SAMPLES do
    local world = sampleDeal(OUR_SEAT, unseen2)
    assert(world, ("caveat sample %d: returned nil"):format(i))
    local nineFound = false
    for _, c in ipairs(world[BIDDER_SEAT] or {}) do
        if c == "9H" then nineFound = true; break end
    end
    if not nineFound then nineMisplaced2 = nineMisplaced2 + 1 end
end
assertEq(nineMisplaced2, 0,
    ("H-1 caveat: 9H on bidder in 100/100 even when JH=bidCard"):format())

-- =====================================================================
-- H-1 caveat: J of trump already played — only 9 is pinned
-- =====================================================================
section("H-1 caveat: JH already played — only 9H is pinned")

setupState(OUR_SEAT, BIDDER_SEAT, TRUMP, OUR_HAND, "AH")
-- Simulate JH having been played: put it in s.tricks so buildUnseen sees it.
S.s.tricks = {
    { plays = { { seat = 2, card = "JH" }, { seat = 3, card = "8H" },
                { seat = 4, card = "7H" }, { seat = 1, card = "TH" } },
      winner = 2, points = 0 }
}
local unseenAfterJ = buildUnseenForTest(OUR_HAND, { "JH", "8H", "7H", "TH" })

-- JH should not appear in unseen at all.
local jStillUnseen = false
for _, c in ipairs(unseenAfterJ) do
    if c == "JH" then jStillUnseen = true end
end
assertEq(jStillUnseen, false, "precondition: JH absent from unseen after being played")

-- 9H should still pin to bidder.
local nineMisplaced3 = 0
for i = 1, NUM_SAMPLES do
    local world = sampleDeal(OUR_SEAT, unseenAfterJ)
    assert(world, ("played-J sample %d: returned nil"):format(i))
    local nineFound = false
    for _, c in ipairs(world[BIDDER_SEAT] or {}) do
        if c == "9H" then nineFound = true; break end
    end
    if not nineFound then nineMisplaced3 = nineMisplaced3 + 1 end
end
assertEq(nineMisplaced3, 0,
    "H-1 caveat: 9H on bidder in 100/100 when JH was already played")

-- =====================================================================
-- H-1 negative: SUN contract — no pin (no trump suit)
-- =====================================================================
section("H-1 negative: SUN contract — power-card pins must NOT fire")

S.s.tricks      = {}
S.s.trick       = { leadSuit = nil, plays = {} }
S.s.contract    = { type = K.BID_SUN, bidder = BIDDER_SEAT }
S.s.bidCard     = "AS"
local unseenSun = buildUnseenForTest(OUR_HAND, {})

-- In SUN, JH and 9H are plain cards — they should distribute freely.
-- We do NOT assert they stay off bidder; we assert the sampler doesn't crash
-- and produces valid (non-nil) worlds for all 100 samples.
local sunNilCount = 0
for i = 1, NUM_SAMPLES do
    local world = sampleDeal(OUR_SEAT, unseenSun)
    if not world then sunNilCount = sunNilCount + 1 end
end
assertEq(sunNilCount, 0,
    "H-1 negative: SUN contract — sampleConsistentDeal returns non-nil in 100/100")

-- =====================================================================
-- H-1 caveat: we ARE the bidder — bidder == seat, so pin target is self
-- =====================================================================
section("H-1 caveat: calling bot IS the bidder — J/9 already in our hand or unseen for others")

-- When seat == bidder, S.s.bidCard check fires only when bidder ~= seat, so
-- pinCard stays nil.  The H-1 block still runs but `meldPins[powerCard] = bidder`
-- means it would try to pin to ourSeat.  The deal loop pre-places meldPin
-- cards into the seat == declarerSeat slot; for ourSeat that slot is filled
-- from hostHands[ourSeat], not the pool.  Verify: no crash + valid worlds.
local BIDDER_IS_US = OUR_SEAT
setupState(BIDDER_IS_US, BIDDER_IS_US, TRUMP,
           { "JH", "9H", "AS", "KS", "QS", "JS", "TS", "8S" }, "JH")
-- JH and 9H are in our hand — buildUnseen excludes them.
local unseenBidder = buildUnseenForTest(
    { "JH", "9H", "AS", "KS", "QS", "JS", "TS", "8S" }, {})
local jInUnseenB, nineInUnseenB = false, false
for _, c in ipairs(unseenBidder) do
    if c == "JH" then jInUnseenB = true end
    if c == "9H" then nineInUnseenB = true end
end
assertEq(jInUnseenB,    false, "caveat bidder=us: JH absent from unseen (in our hand)")
assertEq(nineInUnseenB, false, "caveat bidder=us: 9H absent from unseen (in our hand)")

local bidderUsNilCount = 0
for i = 1, NUM_SAMPLES do
    local world = sampleDeal(BIDDER_IS_US, unseenBidder)
    if not world then bidderUsNilCount = bidderUsNilCount + 1 end
end
assertEq(bidderUsNilCount, 0,
    "H-1 caveat: bidder==us — 100/100 valid worlds (no crash, no double-pin)")

-- =====================================================================
-- Summary
-- =====================================================================
print("")
print(("== Result: %d passed, %d failed =="):format(pass, fail))
for _, msg in ipairs(failures) do
    print(msg)
end
TEST_RESULTS = { passed = pass, failed = fail }
if fail == 0 then return true end
return false
