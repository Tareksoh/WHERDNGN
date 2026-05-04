-- tests/probe_defender_strength.lua
--
-- Diagnostic probe: for each bias level, measure the defender hand
-- strength distribution as seen by Bot.PickDouble. Helps answer
-- "why doesn't Bel fire even at elite bias?" — is it because the
-- threshold is too high, or because defender strengths are below
-- expectation for some other reason?

unpack = unpack or table.unpack

local function addonRoot()
    if WHEREDNGN_TESTS_ROOT then return WHEREDNGN_TESTS_ROOT end
    local src = debug.getinfo(1, "S").source
    if src:sub(1, 1) ~= "@" then
        error("set WHEREDNGN_TESTS_ROOT before running")
    end
    return (src:sub(2):gsub("[/\\]tests[/\\][^/\\]+$", ""))
end
local ROOT = addonRoot()

GetTime = function() return 0 end
C_Timer = { After = function(_,_) end }
GetUnitName = function() return "X" end
UnitName    = function() return "X" end
WHEREDNGNDB = {}
SendChatMessage = function() end
C_ChatInfo = { RegisterAddonMessagePrefix = function() return true end,
               SendAddonMessage = function() end }
CreateFrame = function() return {
    SetScript=function() end, RegisterEvent=function() end,
    UnregisterEvent=function() end, Hide=function() end, Show=function() end,
} end

WHEREDNGN = WHEREDNGN or {}
WHEREDNGN.Sound = { Cue = function() end, ArmCue = function() end }
WHEREDNGN.Log   = { Debug=function() end, Info=function() end,
                    Warn=function() end, Error=function() end,
                    Clear=function() end, Dump=function() end }
WHEREDNGN.UI    = { Refresh=function() end }

local function load(rel)
    local path = (ROOT .. "/" .. rel):gsub("\\", "/")
    local chunk, err = loadfile(path)
    if not chunk then error(err) end
    chunk()
end
load("Constants.lua")
load("Cards.lua")
load("Rules.lua")
load("State.lua")
load("Bot.lua")
load("BotMaster.lua")

local K = WHEREDNGN.K
local C = WHEREDNGN.Cards
local R = WHEREDNGN.Rules
local S = WHEREDNGN.State
local Bot = WHEREDNGN.Bot

-- Mirror the harness's deal logic.
local BIAS = {
    moderate = { "J", "9" },
    strong   = { "J", "9", "A" },
    elite    = { "J", "9", "A", "T" },
}

local function dealAsymmetric(seed, bias)
    math.randomseed(seed)
    local trump = K.SUITS[math.random(1, 4)]
    local bidder = math.random(1, 4)
    local fixed, fixedSet = {}, {}
    for _, r in ipairs(BIAS[bias]) do
        local card = r .. trump
        fixed[#fixed+1] = card; fixedSet[card] = true
    end
    local pool = {}
    for _, su in ipairs(K.SUITS) do
        for _, ra in ipairs(K.RANKS) do
            local card = ra .. su
            if not fixedSet[card] then pool[#pool+1] = card end
        end
    end
    C.Shuffle(pool, seed)
    local hands = {{}, {}, {}, {}}
    for _, card in ipairs(fixed) do
        hands[bidder][#hands[bidder]+1] = card
    end
    local idx = 1
    while #hands[bidder] < 8 do
        hands[bidder][#hands[bidder]+1] = pool[idx]; idx = idx+1
    end
    for s = 1, 4 do
        if s ~= bidder then
            for _ = 1, 8 do
                hands[s][#hands[s]+1] = pool[idx]; idx = idx+1
            end
        end
    end
    return hands, bidder, trump
end

-- For each defender of the deal, run Bot.PickDouble and capture both
-- whether it fires AND the underlying strength value (we need to do
-- a tiny bit of code-internal poking via a lightweight wrapper).

local function freshState(hands, contract)
    local s = S.s
    s.phase = K.PHASE_PLAY
    s.isHost = true
    s.contract = contract
    s.hostHands = hands
    s.bids = {}
    s.tricks = {}
    s.cumulative = { A = 0, B = 0 }
    s.target = 152
    s.seats = { [1]=nil, [2]=nil, [3]=nil, [4]=nil }
    s.meldsByTeam = { A = {}, B = {} }
    s.meldsDeclared = {}
    s.akaCalled = nil
    if Bot.ResetStyle then Bot.ResetStyle() end
    if Bot.ResetMemory then Bot.ResetMemory() end
end

WHEREDNGNDB.advancedBots = false
WHEREDNGNDB.m3lmBots = false
WHEREDNGNDB.fzlokyBots = false
WHEREDNGNDB.saudiMasterBots = false

-- We can't directly call the local sunStrength or suitStrengthAsTrump,
-- but we can replicate the formula here for diagnostic comparison.
local function suitStrengthAsTrump(hand, suit)
    local s, count, hasJ, has9 = 0, 0, false, false
    for _, c in ipairs(hand) do
        if C.Suit(c) == suit then
            count = count + 1
            local r = C.Rank(c)
            if     r == "J" then hasJ = true; s = s + 20
            elseif r == "9" then has9 = true; s = s + 14
            elseif r == "A" then s = s + 11
            elseif r == "T" then s = s + 10
            elseif r == "K" then s = s + 4
            elseif r == "Q" then s = s + 3
            elseif r == "8" then s = s + 2
            elseif r == "7" then s = s + 2
            end
        end
    end
    s = s + math.max(0, count - 2) * 5
    if hasJ and has9 then s = s + 10 end
    return s
end

local function sunStrength(hand)
    local s = 0
    for _, c in ipairs(hand) do
        local r = C.Rank(c)
        if     r == "A" then s = s + 11
        elseif r == "T" then s = s + 10
        elseif r == "K" then s = s + 4
        elseif r == "Q" then s = s + 3
        elseif r == "J" then s = s + 2
        end
    end
    return s
end

local function defenderStrength(hand, trump)
    local s = sunStrength(hand) + suitStrengthAsTrump(hand, trump)
    -- C-3b additions
    local voidCount, sideAces = 0, 0
    local suitCount = { S = 0, H = 0, D = 0, C = 0 }
    for _, c in ipairs(hand) do
        suitCount[C.Suit(c)] = suitCount[C.Suit(c)] + 1
        if C.Rank(c) == "A" and C.Suit(c) ~= trump then
            sideAces = sideAces + 1
        end
    end
    for _, su in ipairs({ "S", "H", "D", "C" }) do
        if su ~= trump and suitCount[su] == 0 then
            voidCount = voidCount + 1
        end
    end
    s = s + voidCount * 5
    if sideAces >= 2 then s = s + (sideAces - 1) * 8 end
    return s, sideAces, voidCount
end

local biases = { "moderate", "strong", "elite" }
local N = 1000
local TH = K.BOT_BEL_TH

-- ALSO probe: directly call Bot.PickDouble on each defender hand to
-- see what the live picker returns (caught discrepancy: probe says
-- 16% should clear at moderate, but tournament harness says 0% Bel
-- rate). The picker is the source of truth.
print(("Direct Bot.PickDouble fire-rate per bias (TH=%d)"):format(TH))
print(("%-10s | %-12s %-12s %-12s"):format(
    "bias", "fired_any", "fired_perDef", "rounds_tested"))
print(string.rep("-", 60))

for _, bias in ipairs(biases) do
    local rounds = 200
    local firedAnyRounds = 0
    local totalDefs, firedDefs = 0, 0
    for i = 1, rounds do
        local hands, bidder, trump = dealAsymmetric(i * 7919 + 1234, bias)
        local contract = { type = K.BID_HOKM, trump = trump, bidder = bidder }
        freshState(hands, contract)
        local bidderTeam = R.TeamOf(bidder)
        local anyFired = false
        for s = 1, 4 do
            if R.TeamOf(s) ~= bidderTeam then
                totalDefs = totalDefs + 1
                local yes = Bot.PickDouble(s)
                if yes then
                    firedDefs = firedDefs + 1
                    anyFired = true
                end
            end
        end
        if anyFired then firedAnyRounds = firedAnyRounds + 1 end
    end
    print(("%-10s | %-12.3f %-12.3f %d"):format(
        bias,
        firedAnyRounds / rounds,
        firedDefs / totalDefs,
        rounds))
end

print("")
print(("Defender-strength distribution (TH=%d)"):format(TH))
print(("%-10s | %-8s %-8s %-8s %-8s %-8s %-8s | %-10s"):format(
    "bias", "min", "med", "p75", "p90", "max", "mean", "frac>=TH"))
print(string.rep("-", 85))

for _, bias in ipairs(biases) do
    local strengths = {}
    local sumAces, sumVoids = 0, 0
    for i = 1, N do
        local hands, bidder, trump = dealAsymmetric(i * 7919 + 1234, bias)
        local bidderTeam = R.TeamOf(bidder)
        for s = 1, 4 do
            if R.TeamOf(s) ~= bidderTeam then
                local str, ac, vd = defenderStrength(hands[s], trump)
                strengths[#strengths+1] = str
                sumAces = sumAces + ac
                sumVoids = sumVoids + vd
            end
        end
    end
    table.sort(strengths)
    local n = #strengths
    local mean = 0
    for _, v in ipairs(strengths) do mean = mean + v end
    mean = mean / n
    local atOrAbove = 0
    for _, v in ipairs(strengths) do
        if v >= TH then atOrAbove = atOrAbove + 1 end
    end
    local function pct(p)
        return strengths[math.max(1, math.ceil(n * p / 100))]
    end
    print(("%-10s | %-8d %-8d %-8d %-8d %-8d %-8.1f | %-10.3f"):format(
        bias,
        strengths[1], pct(50), pct(75), pct(90), strengths[n], mean,
        atOrAbove / n))
    print(("           avg side-Aces=%.2f  avg voids=%.2f"):format(
        sumAces / n, sumVoids / n))
end
