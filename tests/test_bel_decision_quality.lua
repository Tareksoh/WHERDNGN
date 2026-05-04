-- tests/test_bel_decision_quality.lua
--
-- Empirical calibration test for Bot.PickDouble (Bel decision).
--
-- For each of N random deals:
--   1. Build a valid Hokm deal: bidder (seat 1) holds J+9 of trump
--      plus 6 random cards; the three defender seats are random.
--   2. Run Bot.PickDouble with BOT_BEL_TH swept at 60, 70, 80.
--   3. Simulate the 8-trick round with heuristic play (Bot.PickPlay).
--   4. Check whether the defending team (seats 2+4, TeamB, against
--      bidder at seat 1) actually won the round (made more trick
--      points than half of HAND_TOTAL_HOKM, i.e. defenders win if
--      bidder fails to make).
--
-- Metrics collected per threshold:
--   fire_rate    = fraction of hands where Bel fires
--   false_bel    = fire AND defender team loses round  (Bel was wrong)
--   missed_bel   = no-fire AND defender team wins round (Bel was missed)
--   correct_bel  = fire AND defender team wins round
--   correct_pass = no-fire AND defender team loses round
--
-- NOTE: jitter inside PickDouble is pinned to 0 during the sweep by
-- patching math.random temporarily, so threshold comparisons are
-- clean. Individual-threshold isolation is achieved by re-running
-- PickDouble under each K.BOT_BEL_TH value.
--
-- Results are written to BEL_QUALITY_RESULTS (global table).

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

-- -- WoW globals stubs --------------------------------------------------
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

-- -- Load addon files ---------------------------------------------------
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

-- Deterministic seed.
math.randomseed(20260503)

-- -- Helpers -------------------------------------------------------------

local function freshState()
    local s = S.s
    s.phase = K.PHASE_IDLE
    s.isHost = true
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

-- Build a full 32-card deck minus the two cards already fixed.
local function deckWithout(excluded)
    local ex = {}
    for _, c in ipairs(excluded) do ex[c] = true end
    local deck = {}
    for _, suit in ipairs(K.SUITS) do
        for _, rank in ipairs(K.RANKS) do
            local card = rank .. suit
            if not ex[card] then deck[#deck + 1] = card end
        end
    end
    return deck
end

-- Deep-copy a set of 4 hands.
local function copyHands(src)
    local h = {}
    for s = 1, 4 do
        h[s] = {}
        for _, c in ipairs(src[s]) do h[s][#h[s] + 1] = c end
    end
    return h
end

-- Play a single 8-trick round; returns {teamPoints, bidderMade, sweep}
-- where bidderMade = true iff the bidder team accumulated >= half the
-- hand total (strict majority = > handTotal/2 = > 81, so >= 82 for Hokm).
local function playRound(hands, contract)
    freshState()
    S.s.isHost = true
    S.s.contract = contract
    S.s.hostHands = copyHands(hands)
    S.s.tricks = {}
    S.s.playedCardsThisRound = {}
    S.s.akaCalled = nil
    if Bot.ResetMemory then Bot.ResetMemory() end
    if Bot.ResetStyle  then Bot.ResetStyle()  end

    -- Use basic tier only so play doesn't depend on M3lm style state.
    WHEREDNGNDB.advancedBots    = false
    WHEREDNGNDB.m3lmBots        = false
    WHEREDNGNDB.fzlokyBots      = false
    WHEREDNGNDB.saudiMasterBots = false

    local h = S.s.hostHands
    local nextLeader = contract.bidder
    for _ = 1, 8 do
        S.s.trick = { leadSuit = nil, plays = {} }
        local seat = nextLeader
        for play = 1, 4 do
            local card = Bot.PickPlay(seat)
            if not card then
                -- Fallback: first legal card.
                local legal = R.GetLegalPlays(h[seat], S.s.trick, contract, seat)
                card = legal and legal[1]
                if not card then
                    -- Last resort: whatever's left.
                    card = h[seat][1]
                end
            end
            -- Remove from hand.
            for i, c in ipairs(h[seat]) do
                if c == card then table.remove(h[seat], i); break end
            end
            S.s.trick.plays[#S.s.trick.plays + 1] = { seat = seat, card = card }
            if play == 1 then S.s.trick.leadSuit = C.Suit(card) end
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
    -- Add last-trick bonus.
    if #S.s.tricks > 0 then
        local lastWinTeam = R.TeamOf(S.s.tricks[#S.s.tricks].winner)
        teamPoints[lastWinTeam] = teamPoints[lastWinTeam] + K.LAST_TRICK_BONUS
    end

    local bidderTeam = R.TeamOf(contract.bidder)
    local oppTeam    = bidderTeam == "A" and "B" or "A"
    -- Bidder FAILS if they get strictly LESS than half the hand total.
    -- HAND_TOTAL_HOKM = 162; half = 81; so bidder fails if < 82.
    local bidderMade = teamPoints[bidderTeam] >= 82
    local sweep = nil
    if trickCount[bidderTeam] == 8 then sweep = bidderTeam
    elseif trickCount[oppTeam] == 8 then sweep = oppTeam end

    return {
        teamPoints  = teamPoints,
        bidderMade  = bidderMade,
        bidderTeam  = bidderTeam,
        oppTeam     = oppTeam,
        sweep       = sweep,
    }
end

-- Build one random deal where bidder (seat 1) is guaranteed J+9 of trump.
-- Trump is fixed as "H".  Returns { hands, contract }.
local function buildBelScenario(seed)
    math.randomseed(seed)
    local TRUMP = K.SUITS[math.random(1, 4)]
    local bidderSeat = 1   -- bidder is always seat 1 in this test
    local defSeat    = 2   -- primary defender (seat 2, TeamB) calls Bel

    -- Bidder must hold J+9 of trump as a "strong Hokm" contract.
    local fixed = { "J"..TRUMP, "9"..TRUMP }
    local pool  = deckWithout(fixed)
    C.Shuffle(pool, seed)

    -- Deal: bidder gets fixed 2 + 6 random; each defender gets 8 random.
    -- Total used: 2 + 6 + 8*3 = 32. Good.
    local hands = { {}, {}, {}, {} }
    -- Bidder: fixed trump pair + 6 from pool.
    hands[bidderSeat][1] = fixed[1]
    hands[bidderSeat][2] = fixed[2]
    local idx = 1
    for _ = 3, 8 do
        hands[bidderSeat][#hands[bidderSeat] + 1] = pool[idx]
        idx = idx + 1
    end
    -- Defenders.
    for seat = 1, 4 do
        if seat ~= bidderSeat then
            for _ = 1, 8 do
                hands[seat][#hands[seat] + 1] = pool[idx]
                idx = idx + 1
            end
        end
    end

    local contract = { type = K.BID_HOKM, trump = TRUMP, bidder = bidderSeat }
    return hands, contract, defSeat, TRUMP
end

-- Run Bot.PickDouble for the defender seat with a specific BOT_BEL_TH,
-- using jitter=0 so the threshold is applied cleanly.
local origRandom = math.random
local function pickDoubleAtTH(hands, contract, defSeat, th)
    -- Temporarily override K.BOT_BEL_TH and pin jitter to 0.
    local savedTH = K.BOT_BEL_TH
    K.BOT_BEL_TH = th

    -- Freeze jitter: math.random(-10,10) must return 0.
    math.random = function(a, b)
        if a == -10 and b == 10 then return 0 end
        return origRandom(a, b)
    end

    freshState()
    S.s.isHost = true
    S.s.contract = contract
    S.s.hostHands = copyHands(hands)
    S.s.bids = {}   -- no bids history, so partnerBidBonus/urgency = 0
    S.s.cumulative = { A = 0, B = 0 }
    S.s.target = 152
    WHEREDNGNDB.advancedBots    = false
    WHEREDNGNDB.m3lmBots        = false
    WHEREDNGNDB.fzlokyBots      = false
    WHEREDNGNDB.saudiMasterBots = false
    if Bot.ResetStyle then Bot.ResetStyle() end

    local yes, _ = Bot.PickDouble(defSeat)

    -- Restore.
    K.BOT_BEL_TH = savedTH
    math.random = origRandom

    return yes
end

-- -- Main sweep ----------------------------------------------------------

local N_HANDS  = 1000
local THRESHOLDS = { 60, 70, 80 }

-- Accumulators keyed by threshold.
local stats = {}
for _, th in ipairs(THRESHOLDS) do
    stats[th] = {
        fire        = 0,
        false_bel   = 0,  -- fired but def-team lost
        missed_bel  = 0,  -- not fired but def-team won
        correct_bel = 0,  -- fired and def-team won
        correct_pass= 0,  -- not fired and def-team lost
        total       = 0,
    }
end

-- We need to know the "outcome" only once per deal (it doesn't change
-- with threshold). Cache it.
local outcomes = {}  -- [i] = { defWon = bool }

print("Building " .. N_HANDS .. " random Hokm scenarios …")

local BASE_SEED = 77777
for i = 1, N_HANDS do
    local seed = BASE_SEED + i
    local hands, contract, defSeat, _ = buildBelScenario(seed)

    -- Simulate outcome: does the defender team win?
    local result = playRound(copyHands(hands), contract)
    local defTeam = R.TeamOf(defSeat)     -- always "B"
    local defWon  = not result.bidderMade  -- bidder failed = defender wins
    outcomes[i] = { defWon = defWon, hands = hands,
                    contract = contract, defSeat = defSeat }
end

print("Outcome simulation done. Running PickDouble sweep …")

for _, th in ipairs(THRESHOLDS) do
    local st = stats[th]
    for i = 1, N_HANDS do
        local o = outcomes[i]
        local fired = pickDoubleAtTH(o.hands, o.contract, o.defSeat, th)
        st.total = st.total + 1
        if fired then
            st.fire = st.fire + 1
            if o.defWon then
                st.correct_bel = st.correct_bel + 1
            else
                st.false_bel = st.false_bel + 1
            end
        else
            if o.defWon then
                st.missed_bel = st.missed_bel + 1
            else
                st.correct_pass = st.correct_pass + 1
            end
        end
    end
end

-- -- Compile results for Python -----------------------------------------

local function pct(num, denom)
    if denom == 0 then return 0 end
    return num / denom
end

local results = {}
for _, th in ipairs(THRESHOLDS) do
    local st = stats[th]
    local fired  = st.fire
    local nfired = N_HANDS - fired
    results[th] = {
        threshold       = th,
        n_hands         = N_HANDS,
        fire_rate       = pct(fired, N_HANDS),
        false_bel_rate  = pct(st.false_bel,  math.max(fired, 1)),
        missed_bel_rate = pct(st.missed_bel, math.max(nfired, 1)),
        correct_bel_rate= pct(st.correct_bel, math.max(fired, 1)),
        precision       = pct(st.correct_bel, math.max(fired, 1)),
        recall          = pct(st.correct_bel,
                              math.max(st.correct_bel + st.missed_bel, 1)),
        raw = {
            fired        = fired,
            false_bel    = st.false_bel,
            missed_bel   = st.missed_bel,
            correct_bel  = st.correct_bel,
            correct_pass = st.correct_pass,
        },
    }
    print(string.format(
        "TH=%d  fire=%.1f%%  false_bel=%.1f%%  missed_bel=%.1f%%  precision=%.1f%%  recall=%.1f%%",
        th,
        pct(fired, N_HANDS) * 100,
        pct(st.false_bel, math.max(fired, 1)) * 100,
        pct(st.missed_bel, math.max(nfired, 1)) * 100,
        pct(st.correct_bel, math.max(fired, 1)) * 100,
        pct(st.correct_bel,
            math.max(st.correct_bel + st.missed_bel, 1)) * 100
    ))
end

BEL_QUALITY_RESULTS = results
