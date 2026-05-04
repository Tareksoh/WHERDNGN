-- tests/test_multiseed_metrics.lua
--
-- Multi-seed variant of test_baseline_metrics.lua.
-- Runs 5 seeds × 100 rounds × 6 configs × 2 modes = 60 tournaments.
-- Seeds: 1, 12345, 999, 7, 42  (passed as MULTI_SEED_VALUE global by runner)
--
-- Deal seeds are varied per tournament: round deal-seed = seed_offset + i*7919 + 1234
-- where seed_offset = MULTI_SEED_VALUE * 99991 (a large prime shift so seeds don't
-- collide with one another's round sequences).
--
-- Exposes MULTISEED_RESULTS in globals for the Python runner.
-- Do NOT modify production files.

unpack = unpack or table.unpack

-- -- Locate addon root -------------------------------------------------------
local function addonRoot()
    if WHEREDNGN_TESTS_ROOT then return WHEREDNGN_TESTS_ROOT end
    local src = debug.getinfo(1, "S").source
    if src:sub(1, 1) ~= "@" then
        error("set WHEREDNGN_TESTS_ROOT before running")
    end
    return (src:sub(2):gsub("[/\\]tests[/\\][^/\\]+$", ""))
end
local ROOT = addonRoot()

-- -- WoW globals stubs -------------------------------------------------------
local fakeNow = 2000000.0
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

WHEREDNGN = WHEREDNGN or {}
WHEREDNGN.Sound = { Cue = function() end, ArmCue = function() end }
WHEREDNGN.Log   = {
    Debug = function() end, Info = function() end, Warn = function() end,
    Error = function() end, Clear = function() end, Dump = function() end,
}
WHEREDNGN.UI = {
    Refresh = function() end, Show = function() end, Hide = function() end,
    Toggle  = function() end,
}

-- -- Load addon files --------------------------------------------------------
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
load("Bot.lua")
load("BotMaster.lua")

local K   = WHEREDNGN.K
local C   = WHEREDNGN.Cards
local R   = WHEREDNGN.Rules
local S   = WHEREDNGN.State
local Bot = WHEREDNGN.Bot

-- Seed from runner (default fallback so file can be sourced standalone).
local SEED_VALUE = MULTI_SEED_VALUE or 1

-- -- Helpers -----------------------------------------------------------------

local function freshState()
    local s = S.s
    s.phase = K.PHASE_IDLE
    s.isHost = false
    s.gameID = nil
    s.dealer = 1
    s.roundNumber = 0
    s.bidCard = nil
    s.bidRound = 1
    s.bids = {}
    s.contract = nil
    s.hand = {}
    s.hostHands = nil
    s.hostDeckRemainder = nil
    s.turn = nil
    s.turnKind = nil
    s.trick = nil
    s.tricks = {}
    s.meldsByTeam = { A = {}, B = {} }
    s.meldsDeclared = {}
    s.belPending = nil
    s.preemptEligible = nil
    s.target = 152
    s.teamNames = { A = "Team A", B = "Team B" }
    s.peerVersions = {}
    s.paused = false
    s.lastTrick = nil
    s.akaCalled = nil
    s.playedCardsThisRound = {}
    s.localSeat = nil
    s.seats = { [1]=nil, [2]=nil, [3]=nil, [4]=nil }
end

local function setTier(tier)
    WHEREDNGNDB.advancedBots    = false
    WHEREDNGNDB.m3lmBots        = false
    WHEREDNGNDB.fzlokyBots      = false
    WHEREDNGNDB.saudiMasterBots = false
    if tier == "advanced" then WHEREDNGNDB.advancedBots = true
    elseif tier == "m3lm"   then WHEREDNGNDB.m3lmBots = true
    elseif tier == "fzloky" then WHEREDNGNDB.fzlokyBots = true
    elseif tier == "master" then WHEREDNGNDB.saudiMasterBots = true end
end

local function tierFlagsFor(tier)
    return {
        advancedBots    = (tier == "advanced" or tier == "m3lm" or tier == "fzloky" or tier == "master"),
        m3lmBots        = (tier == "m3lm"   or tier == "fzloky" or tier == "master"),
        fzlokyBots      = (tier == "fzloky" or tier == "master"),
        saudiMasterBots = (tier == "master"),
    }
end

local function applyTierFlags(flags)
    WHEREDNGNDB.advancedBots    = flags.advancedBots
    WHEREDNGNDB.m3lmBots        = flags.m3lmBots
    WHEREDNGNDB.fzlokyBots      = flags.fzlokyBots
    WHEREDNGNDB.saudiMasterBots = flags.saudiMasterBots
end

-- -- Deal / contract helpers -------------------------------------------------

local function dealRandom(seed)
    local deck = {}
    for _, suit in ipairs(K.SUITS) do
        for _, rank in ipairs(K.RANKS) do
            deck[#deck + 1] = rank .. suit
        end
    end
    C.Shuffle(deck, seed)
    local hands = { {}, {}, {}, {} }
    local idx = 1
    for seat = 1, 4 do
        for _ = 1, 8 do
            hands[seat][#hands[seat] + 1] = deck[idx]
            idx = idx + 1
        end
    end
    return hands
end

local function pickContract(hands)
    local bestSeat, bestSuit, bestScore = 1, "S", -1
    for seat = 1, 4 do
        local bySuit = { S=0, H=0, D=0, C=0 }
        local bySuitPts = { S=0, H=0, D=0, C=0 }
        for _, c in ipairs(hands[seat]) do
            local suit = C.Suit(c)
            bySuit[suit] = bySuit[suit] + 1
            bySuitPts[suit] = bySuitPts[suit] +
                (K.POINTS_TRUMP_HOKM[C.Rank(c)] or 0)
        end
        for suit, count in pairs(bySuit) do
            local score = count * 100 + bySuitPts[suit]
            if score > bestScore then
                bestSeat, bestSuit, bestScore = seat, suit, score
            end
        end
    end
    return { type = K.BID_HOKM, trump = bestSuit, bidder = bestSeat }
end

-- -- Escalation simulation ---------------------------------------------------

local function resolveEscalation(contract, hands, mode)
    local bidderTeam = R.TeamOf(contract.bidder)
    local belFired = false
    if mode == "forced" then
        contract.doubled = true
        belFired = true
    else
        for seat = 1, 4 do
            if R.TeamOf(seat) ~= bidderTeam then
                local yes, wantOpen = Bot.PickDouble(seat)
                if yes then
                    contract.doubled = true
                    belFired = true
                    if not wantOpen then return end
                    break
                end
            end
        end
    end
    if not belFired then return end

    local tripleFired = false
    if mode == "forced" then
        contract.tripled = true
        tripleFired = true
    else
        for seat = 1, 4 do
            if R.TeamOf(seat) == bidderTeam then
                local yes, wantOpen = Bot.PickTriple(seat)
                if yes then
                    contract.tripled = true
                    tripleFired = true
                    if not wantOpen then return end
                    break
                end
            end
        end
    end
    if not tripleFired then return end

    local fourFired = false
    for seat = 1, 4 do
        if R.TeamOf(seat) ~= bidderTeam then
            local yes, wantOpen = Bot.PickFour(seat)
            if yes then
                contract.foured = true
                fourFired = true
                if not wantOpen then return end
                break
            end
        end
    end
    if not fourFired then return end

    for seat = 1, 4 do
        if R.TeamOf(seat) == bidderTeam then
            local yes = Bot.PickGahwa(seat)
            if yes then
                contract.gahwa = true
                return
            end
        end
    end
end

-- -- Play one 8-trick round --------------------------------------------------

local function playOneRound(hands, contract, leaderSeat, seatTierFlags)
    freshState()
    S.s.isHost = true
    S.s.contract = contract
    local h = {}
    for seat = 1, 4 do
        h[seat] = {}
        for _, c in ipairs(hands[seat]) do h[seat][#h[seat] + 1] = c end
    end
    S.s.hostHands = h
    S.s.tricks = {}
    S.s.playedCardsThisRound = {}
    S.s.akaCalled = nil
    if Bot.ResetMemory then Bot.ResetMemory() end

    local nextLeader = leaderSeat
    for trickN = 1, 8 do
        S.s.trick = { leadSuit = nil, plays = {} }
        local seat = nextLeader
        for _ = 1, 4 do
            if seatTierFlags then
                applyTierFlags(seatTierFlags[seat])
            end
            local card = Bot.PickPlay(seat)
            if not card then
                error(("trick %d: bot seat %d returned nil"):format(trickN, seat))
            end
            local ok = R.IsLegalPlay(card, h[seat], S.s.trick, contract, seat)
            if not ok then
                error(("trick %d: bot seat %d picked illegal %s"):format(trickN, seat, card))
            end
            for i, c in ipairs(h[seat]) do
                if c == card then table.remove(h[seat], i); break end
            end
            S.s.trick.plays[#S.s.trick.plays + 1] = { seat = seat, card = card }
            if #S.s.trick.plays == 1 then S.s.trick.leadSuit = C.Suit(card) end
            if Bot.OnPlayObserved then
                local ls = (#S.s.trick.plays > 1) and S.s.trick.leadSuit or nil
                Bot.OnPlayObserved(seat, card, ls)
            end
            seat = (seat % 4) + 1
        end
        local winner = R.TrickWinner(S.s.trick, contract)
        local pts    = R.TrickPoints(S.s.trick, contract)
        S.ApplyTrickEnd(winner, pts)
        nextLeader = winner
    end

    local teamPoints = { A = 0, B = 0 }
    local trickCount = { A = 0, B = 0 }
    for _, t in ipairs(S.s.tricks) do
        local team = R.TeamOf(t.winner)
        teamPoints[team] = teamPoints[team] + (t.points or 0)
        trickCount[team] = trickCount[team] + 1
    end
    local sweep
    if trickCount.A == 8 then sweep = "A"
    elseif trickCount.B == 8 then sweep = "B" end
    return { teamPoints = teamPoints, trickCount = trickCount, sweep = sweep }
end

-- -- Run one 100-round tournament --------------------------------------------
-- seedOffset: large per-seed shift so deal sequences don't overlap.
-- tierA/tierB: tier strings. escalationMode: "natural" or "forced".

local NUM_ROUNDS = 100

local function runTournament(tierA, tierB, escalationMode, seedOffset)
    Bot.ResetStyle()
    Bot.ResetMemory()

    local cumA, cumB = 0, 0
    local esc   = { bel = 0, triple = 0, four = 0, gahwa = 0 }
    local belA, belB  = 0, 0
    local sweeps      = 0
    local sweepA, sweepB = 0, 0
    local deltaSumA, deltaSumB = 0, 0
    local winRoundsA, winRoundsB = 0, 0
    local gahwaWinsA, gahwaWinsB = 0, 0
    local gameOver = false
    local gameWinner = nil

    local seatTierFlags = nil
    if tierA ~= tierB then
        seatTierFlags = {
            [1] = tierFlagsFor(tierA),
            [2] = tierFlagsFor(tierB),
            [3] = tierFlagsFor(tierA),
            [4] = tierFlagsFor(tierB),
        }
    else
        setTier(tierA)
    end

    local roundsPlayed = 0

    for i = 1, NUM_ROUNDS do
        if gameOver then break end

        -- Key change vs baseline: seedOffset shifts the deal sequence per seed.
        local dealSeed = seedOffset + i * 7919 + 1234
        local hands    = dealRandom(dealSeed)
        local contract = pickContract(hands)
        local leader   = contract.bidder

        if seatTierFlags then applyTierFlags(seatTierFlags[leader]) end
        resolveEscalation(contract, hands, escalationMode)

        if contract.doubled  then esc.bel    = esc.bel    + 1 end
        if contract.tripled  then esc.triple = esc.triple + 1 end
        if contract.foured   then esc.four   = esc.four   + 1 end
        if contract.gahwa    then esc.gahwa  = esc.gahwa  + 1 end

        if contract.doubled then
            local bidderTeam = R.TeamOf(contract.bidder)
            if bidderTeam == "A" then belB = belB + 1
            else                      belA = belA + 1 end
        end

        if seatTierFlags then applyTierFlags(seatTierFlags[leader]) end

        local result = playOneRound(hands, contract, leader, seatTierFlags)

        local scored = R.ScoreRound(S.s.tricks, contract, { A = {}, B = {} })
        local gpA = scored.final.A
        local gpB = scored.final.B

        if contract.gahwa and scored.gahwaWinner then
            if scored.gahwaWinner == "A" then
                gahwaWinsA = gahwaWinsA + 1
                gameOver   = true
                gameWinner = "A"
                cumA = cumA + (S.s.target or 152)
            else
                gahwaWinsB = gahwaWinsB + 1
                gameOver   = true
                gameWinner = "B"
                cumB = cumB + (S.s.target or 152)
            end
        else
            cumA = cumA + gpA
            cumB = cumB + gpB
            deltaSumA = deltaSumA + gpA
            deltaSumB = deltaSumB + gpB
            if gpA > 0 then winRoundsA = winRoundsA + 1 end
            if gpB > 0 then winRoundsB = winRoundsB + 1 end

            local target = S.s.target or 152
            if cumA >= target or cumB >= target then
                gameOver = true
                if cumA >= target and cumB >= target then
                    gameWinner = (cumA >= cumB) and "A" or "B"
                elseif cumA >= target then
                    gameWinner = "A"
                else
                    gameWinner = "B"
                end
            end
        end

        if result.sweep then
            sweeps = sweeps + 1
            if result.sweep == "A" then sweepA = sweepA + 1
            else                        sweepB = sweepB + 1 end
        end

        S.s.cumulative = { A = cumA, B = cumB }
        roundsPlayed = roundsPlayed + 1
    end

    if not gameWinner then
        if   cumA > cumB then gameWinner = "A"
        elseif cumB > cumA then gameWinner = "B"
        else                   gameWinner = "tie" end
    end

    local bel_rate    = (roundsPlayed > 0) and esc.bel    / roundsPlayed or 0
    local triple_rate = (roundsPlayed > 0) and esc.triple / roundsPlayed or 0
    local four_rate   = (roundsPlayed > 0) and esc.four   / roundsPlayed or 0
    local gahwa_rate  = (roundsPlayed > 0) and esc.gahwa  / roundsPlayed or 0
    local sweep_rate  = (roundsPlayed > 0) and sweeps     / roundsPlayed or 0
    local bel_rate_A  = (roundsPlayed > 0) and belA / roundsPlayed or 0
    local bel_rate_B  = (roundsPlayed > 0) and belB / roundsPlayed or 0
    local avg_delta_A = (roundsPlayed > 0) and deltaSumA / roundsPlayed or 0
    local avg_delta_B = (roundsPlayed > 0) and deltaSumB / roundsPlayed or 0

    return {
        rounds_played   = roundsPlayed,
        escalations     = esc,
        bel_rate        = bel_rate,
        bel_rate_A      = bel_rate_A,
        bel_rate_B      = bel_rate_B,
        triple_rate     = triple_rate,
        four_rate       = four_rate,
        gahwa_rate      = gahwa_rate,
        sweep_rate      = sweep_rate,
        sweep_A         = sweepA,
        sweep_B         = sweepB,
        avg_gp_delta_A  = avg_delta_A,
        avg_gp_delta_B  = avg_delta_B,
        win_rounds_A    = winRoundsA,
        win_rounds_B    = winRoundsB,
        gahwa_wins_A    = gahwaWinsA,
        gahwa_wins_B    = gahwaWinsB,
        game_winner     = gameWinner,
        final_gp        = { A = cumA, B = cumB },
    }
end

-- -- Run all 6 × 2 configurations for this seed ----------------------------

local configs = {
    { name = "all_basic",           tierA = "basic",    tierB = "basic"  },
    { name = "all_advanced",        tierA = "advanced", tierB = "advanced" },
    { name = "all_m3lm",            tierA = "m3lm",     tierB = "m3lm"   },
    { name = "all_master",          tierA = "master",   tierB = "master" },
    { name = "mixed_basic_master",  tierA = "basic",    tierB = "master" },
    { name = "mixed_m3lm_master",   tierA = "m3lm",     tierB = "master" },
}

-- Large prime shift per seed so round sequences don't overlap across seeds.
local SEED_PRIME = 99991
local seedOffset = SEED_VALUE * SEED_PRIME

print(("== seed=%d  offset=%d =="):format(SEED_VALUE, seedOffset))

local results = {}
for _, cfg in ipairs(configs) do
    for _, mode in ipairs({ "natural", "forced" }) do
        local key = cfg.name .. "__" .. mode
        io.write(("  [seed=%d] %-36s ..."):format(SEED_VALUE, key))
        io.flush()
        local r = runTournament(cfg.tierA, cfg.tierB, mode, seedOffset)
        r.config         = cfg.name
        r.tier_A         = cfg.tierA
        r.tier_B         = cfg.tierB
        r.escalation_mode = mode
        r.seed           = SEED_VALUE
        results[key]     = r
        print((" bel=%.2f tri=%.2f sw=%.2f winner=%s rounds=%d")
              :format(r.bel_rate, r.triple_rate, r.sweep_rate,
                      r.game_winner, r.rounds_played))
    end
end

MULTISEED_RESULTS = results
print("")
