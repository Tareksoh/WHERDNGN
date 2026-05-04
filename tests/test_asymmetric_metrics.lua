-- tests/test_asymmetric_metrics.lua
--
-- Asymmetric-deal playtest fixture for WHEREDNGN.
--
-- The default `test_baseline_metrics.lua` deals symmetrically (32-card
-- random shuffle, 8 cards per seat). In symmetric play, no defender
-- hand ever clears K.BOT_BEL_TH (=60 since v0.5.0) because Saudi Bel
-- is calibrated for the asymmetric clustering humans actually see —
-- a human bidder typically has J+9-of-trump (or stronger), which
-- means the OTHER team has weak trump and can have side-suit Ace
-- clusters that justify a Bel.
--
-- This harness biases the deal so the bidder gets a known
-- "strong-Hokm" trump pattern. The opposing team's hands are still
-- random over the remaining cards. We then:
--   1. Run the FULL bid + escalation + play cycle for 100 rounds
--   2. Across the 6 tier configs × 2 modes (12 tournaments each level)
--   3. At three bias levels: J+9, J+9+A, J+9+A+T-of-trump
--   4. Capture all the same metrics as the baseline harness
--
-- The hypothesis: as the bidder gets stronger, defenders' relative
-- side-suit Ace clusters become more pronounced (because more of
-- the trump cards are accounted for in the bidder's hand). At
-- sufficient asymmetry, Bel/Triple/Four/Gahwa SHOULD start firing
-- in natural mode if the v0.5 calibration is roughly correct.
--
-- Driven from: python tests/run_asymmetric.py
-- Output: .swarm_findings/bot_asymmetric_metrics.json
-- Globals: ASYMMETRIC_RESULTS

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

-- -- WoW globals stubs ----------------------------------------------------
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

-- -- Load addon files -----------------------------------------------------
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

math.randomseed(20260504)

-- -- State helpers --------------------------------------------------------

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
    s.cumulative = { A = 0, B = 0 }
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

-- -- Tier flag helpers (mirrors test_baseline_metrics.lua) ---------------

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
    if not flags then return end
    WHEREDNGNDB.advancedBots    = flags.advancedBots
    WHEREDNGNDB.m3lmBots        = flags.m3lmBots
    WHEREDNGNDB.fzlokyBots      = flags.fzlokyBots
    WHEREDNGNDB.saudiMasterBots = flags.saudiMasterBots
end

-- -- Asymmetric deal -------------------------------------------------------
--
-- Bias levels:
--   "moderate" -- bidder has J+9 of trump (canonical strong-Hokm pattern)
--   "strong"   -- bidder has J+9+A of trump
--   "elite"    -- bidder has J+9+A+T of trump
-- The remaining bidder cards (8 - bias size) and all 24 defender cards
-- are dealt randomly from the post-bias remainder of the deck.
--
-- Trump and bidder seat are deterministic functions of the seed so the
-- same seed across tier configs produces the same hands (matches the
-- pattern used by test_baseline_metrics.lua).

local BIAS_PATTERNS = {
    moderate = { "J", "9" },
    strong   = { "J", "9", "A" },
    elite    = { "J", "9", "A", "T" },
}

local function dealAsymmetric(seed, biasLevel)
    -- Deterministic per-seed trump + bidder.
    math.randomseed(seed)
    local trumpSuit = K.SUITS[math.random(1, 4)]
    local bidderSeat = math.random(1, 4)
    local pattern = BIAS_PATTERNS[biasLevel]
        or error("unknown bias level: " .. tostring(biasLevel))

    -- Build deck minus the fixed-bidder cards.
    local fixed = {}
    local fixedSet = {}
    for _, rank in ipairs(pattern) do
        local card = rank .. trumpSuit
        fixed[#fixed + 1] = card
        fixedSet[card] = true
    end
    local pool = {}
    for _, suit in ipairs(K.SUITS) do
        for _, rank in ipairs(K.RANKS) do
            local card = rank .. suit
            if not fixedSet[card] then pool[#pool + 1] = card end
        end
    end
    -- Shuffle the pool with the same seed (Cards.Shuffle is deterministic).
    C.Shuffle(pool, seed)

    local hands = { {}, {}, {}, {} }
    -- Bidder gets fixed cards first.
    for _, card in ipairs(fixed) do
        hands[bidderSeat][#hands[bidderSeat] + 1] = card
    end
    -- Fill bidder up to 8 with random cards from the pool.
    local idx = 1
    while #hands[bidderSeat] < 8 do
        hands[bidderSeat][#hands[bidderSeat] + 1] = pool[idx]
        idx = idx + 1
    end
    -- Defenders get 8 random cards each.
    for seat = 1, 4 do
        if seat ~= bidderSeat then
            for _ = 1, 8 do
                hands[seat][#hands[seat] + 1] = pool[idx]
                idx = idx + 1
            end
        end
    end

    -- Sanity: 32 cards total dealt.
    local total = 0
    for s = 1, 4 do total = total + #hands[s] end
    if total ~= 32 then
        error(("dealAsymmetric: total=%d (expected 32)"):format(total))
    end

    return hands, bidderSeat, trumpSuit
end

-- pickContract is REPLACED in this harness — the bidder + trump are
-- fixed by the asymmetric deal. We just need to construct the contract
-- record with type=HOKM, the chosen trump, and the chosen bidder seat.
local function fixedContract(bidderSeat, trumpSuit)
    return { type = K.BID_HOKM, trump = trumpSuit, bidder = bidderSeat }
end

-- -- Escalation simulation (identical to baseline) ------------------------

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

-- -- Play one 8-trick round (identical to baseline) ----------------------

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

-- -- Run one 100-round tournament -----------------------------------------

local NUM_ROUNDS = 100

local function runTournament(tierA, tierB, escalationMode, biasLevel)
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

        local seed    = i * 7919 + 1234
        local hands, bidderSeat, trumpSuit = dealAsymmetric(seed, biasLevel)
        local contract = fixedContract(bidderSeat, trumpSuit)
        local leader  = contract.bidder

        if seatTierFlags then
            applyTierFlags(seatTierFlags[leader])
        end
        -- v0.5.5 harness BUG fix: Bot.PickDouble (and friends) read
        -- S.s.contract and S.s.hostHands directly. Without freshState
        -- here, the escalation decisions in resolveEscalation use
        -- whichever state was left over from the previous round (or
        -- nil for round 1). This silently masked Bel/Triple/Four/Gahwa
        -- rates as 0% across BOTH the asymmetric and baseline harnesses.
        -- Set the state to the CURRENT round's hands+contract before
        -- the escalation window. playOneRound below calls freshState
        -- again, which is fine — it's idempotent.
        freshState()
        S.s.isHost = true
        S.s.contract = contract
        local hForEsc = {}
        for seat = 1, 4 do
            hForEsc[seat] = {}
            for _, c in ipairs(hands[seat]) do
                hForEsc[seat][#hForEsc[seat] + 1] = c
            end
        end
        S.s.hostHands = hForEsc
        S.s.cumulative = { A = cumA, B = cumB }
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

        if seatTierFlags then
            applyTierFlags(seatTierFlags[leader])
        end

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
                gameOver   = true
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

    local bel_rate     = (roundsPlayed > 0) and esc.bel    / roundsPlayed or 0
    local triple_rate  = (roundsPlayed > 0) and esc.triple / roundsPlayed or 0
    local four_rate    = (roundsPlayed > 0) and esc.four   / roundsPlayed or 0
    local gahwa_rate   = (roundsPlayed > 0) and esc.gahwa  / roundsPlayed or 0
    local sweep_rate   = (roundsPlayed > 0) and sweeps     / roundsPlayed or 0
    local bel_rate_A   = (roundsPlayed > 0) and belA / roundsPlayed or 0
    local bel_rate_B   = (roundsPlayed > 0) and belB / roundsPlayed or 0
    local avg_delta_A  = (roundsPlayed > 0) and deltaSumA / roundsPlayed or 0
    local avg_delta_B  = (roundsPlayed > 0) and deltaSumB / roundsPlayed or 0

    return {
        rounds_played   = roundsPlayed,
        bias_level      = biasLevel,
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

-- -- Run all bias × config × mode permutations ---------------------------

print("")
print("== WHEREDNGN Asymmetric Playtest Metrics (100-round tournaments) ==")

local configs = {
    { name = "all_basic",           tierA = "basic",    tierB = "basic"  },
    { name = "all_advanced",        tierA = "advanced", tierB = "advanced" },
    { name = "all_m3lm",            tierA = "m3lm",     tierB = "m3lm"   },
    { name = "all_master",          tierA = "master",   tierB = "master" },
    { name = "mixed_basic_master",  tierA = "basic",    tierB = "master" },
    { name = "mixed_m3lm_master",   tierA = "m3lm",     tierB = "master" },
}

local biasLevels = { "moderate", "strong", "elite" }
local modes      = { "natural", "forced" }

local results = {}
for _, bias in ipairs(biasLevels) do
    print(("\n-- Bias: %s --"):format(bias))
    for _, cfg in ipairs(configs) do
        for _, mode in ipairs(modes) do
            local key = bias .. "/" .. cfg.name .. "__" .. mode
            io.write(("  running %-48s ..."):format(key))
            io.flush()
            local r = runTournament(cfg.tierA, cfg.tierB, mode, bias)
            r.config = cfg.name
            r.tier_A = cfg.tierA
            r.tier_B = cfg.tierB
            r.escalation_mode = mode
            results[key] = r
            print((" bel=%.2f tri=%.2f 4=%.2f ghw=%.2f sw=%.2f winner=%s")
                  :format(r.bel_rate, r.triple_rate, r.four_rate, r.gahwa_rate,
                          r.sweep_rate, r.game_winner))
        end
    end
end

ASYMMETRIC_RESULTS = results
print("")
print("== Done ==")
