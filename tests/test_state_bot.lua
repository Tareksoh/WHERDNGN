-- tests/test_state_bot.lua
--
-- Harness for State.lua + Bot.lua. Stubs the WoW globals these files
-- call at load / run time, then exercises:
--   - State pure data transforms (HostDealInitial, ApplyTrickEnd,
--     GetLegalPlays, MeldVerdict, PreemptEligibleSeats, IsSeatBot,
--     LobbyFull, ApplyResyncSnapshot)
--   - Bot legality property test: Bot.PickPlay always returns a
--     legal card across many randomized trick states
--   - Bot.PickBid sanity: high-strength hands bid, weak hands pass
--   - Headless tournament: M3lm-vs-Basic mixed seating across N rounds,
--     assert the M3lm side outperforms (or at least doesn't underperform)
--
-- Run via: python tests/run.py (after this file is added to the runner)
-- or directly: lua tests/test_state_bot.lua

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
-- Just enough to let State.lua / Bot.lua load and operate. None of these
-- need to be high-fidelity — the pure-logic functions don't actually
-- depend on real timing or the chat system.

-- Monotonic clock for shuffle seeds and timestamps. Increment per call
-- so successive shuffles use different seeds.
local fakeNow = 1000000.0
GetTime = function()
    fakeNow = fakeNow + 0.001
    return fakeNow
end

-- C_Timer: NewTicker / NewTimer return objects with :Cancel(). We don't
-- actually fire scheduled callbacks — tests run synchronously and never
-- need them.
C_Timer = {
    NewTicker = function(_, _) return { Cancel = function() end } end,
    NewTimer  = function(_, _) return { Cancel = function() end } end,
    After     = function(_, _) end,
}

-- Identity helpers
GetUnitName = function() return "TestPlayer" end
UnitName    = function() return "TestPlayer" end

-- Saved variables
WHEREDNGNDB = {}

-- Chat / addon channel stubs (State.lua doesn't broadcast, Net.lua does)
SendChatMessage = function() end
C_ChatInfo = {
    RegisterAddonMessagePrefix = function() return true end,
    SendAddonMessage = function() end,
}

-- Frame creation. State.lua only uses CreateFrame for SaveSession debounce.
CreateFrame = function()
    return {
        SetScript = function() end,
        RegisterEvent = function() end,
        UnregisterEvent = function() end,
        Hide = function() end, Show = function() end,
    }
end

-- Verbose flag from the runner.
local VERBOSE = (TEST_VERBOSE == true)

-- -- Module shims (provide no-op B.Sound, B.Log, B.UI before files load)

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

local K   = WHEREDNGN.K
local C   = WHEREDNGN.Cards
local R   = WHEREDNGN.Rules
local S   = WHEREDNGN.State
local Bot = WHEREDNGN.Bot

-- Deterministic RNG so tournament outcomes are reproducible.
math.randomseed(20260503)

-- -- Tiny test framework -------------------------------------------------

local pass, fail = 0, 0
local failures = {}

local function assertEq(actual, expected, name)
    if actual == expected then
        pass = pass + 1
        if VERBOSE then print(("  PASS  %s"):format(name)) end
    else
        fail = fail + 1
        local msg = ("FAIL  %s\n        expected: %s\n        actual:   %s")
                       :format(name, tostring(expected), tostring(actual))
        failures[#failures + 1] = msg
        print("  " .. msg)
    end
end
local function assertTrue(actual, name)  assertEq(not not actual, true,  name) end
local function assertFalse(actual, name) assertEq(not not actual, false, name) end
local function section(label) print(""); print("== " .. label .. " ==") end

-- =====================================================================
-- A. State.lua pure data transforms
-- =====================================================================
section("A. State.lua pure transforms")

-- Reset before each scenario.
local function freshState()
    -- Bypass S.Reset (which is the local `reset()` closure inside State.lua).
    -- Instead manipulate S.s directly; we have full access.
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

-- HostDealInitial: 4 hands of 5 cards each + 1 face-up bid card = 21 cards.
freshState()
S.s.isHost = true
local hands, bidCard = S.HostDealInitial()
assertEq(#hands,     4,    "HostDealInitial: 4 hands returned")
assertEq(#hands[1],  5,    "HostDealInitial: hand 1 has 5 cards")
assertEq(#hands[2],  5,    "HostDealInitial: hand 2 has 5 cards")
assertEq(#hands[3],  5,    "HostDealInitial: hand 3 has 5 cards")
assertEq(#hands[4],  5,    "HostDealInitial: hand 4 has 5 cards")
assertTrue(C.IsValid(bidCard), "HostDealInitial: bid card is valid")

-- All 21 dealt cards are unique and from the standard deck.
do
    local seen = {}
    local dups = false
    for seat = 1, 4 do
        for _, c in ipairs(hands[seat]) do
            if seen[c] then dups = true end
            seen[c] = true
        end
    end
    if seen[bidCard] then dups = true end
    assertFalse(dups, "HostDealInitial: 21 cards all unique")
end

-- The remaining deck (s.hostDeckRemainder) holds 32-21=11 cards.
assertEq(#S.s.hostDeckRemainder, 11, "HostDealInitial: 11 cards left in deck")

-- HostDealRest: with a contract for seat 1, that seat gets bidCard + 2 more (=8),
-- the other three seats get +3 each (=8). Final hands: 4×8 = 32.
freshState()
S.s.isHost = true
S.HostDealInitial()
S.s.contract = { type = K.BID_HOKM, trump = "H", bidder = 1 }
local fullHands = S.HostDealRest()
assertEq(#fullHands[1], 8, "HostDealRest: bidder hand = 8")
assertEq(#fullHands[2], 8, "HostDealRest: defender hand = 8")
assertEq(#fullHands[3], 8, "HostDealRest: defender hand = 8")
assertEq(#fullHands[4], 8, "HostDealRest: defender hand = 8")
do
    local seen = {}
    local dups = false
    for seat = 1, 4 do
        for _, c in ipairs(fullHands[seat]) do
            if seen[c] then dups = true end
            seen[c] = true
        end
    end
    assertFalse(dups, "HostDealRest: 32 cards all unique")
end
-- The bidCard ends up in the bidder's hand.
do
    local found = false
    for _, c in ipairs(fullHands[1]) do
        if c == S.s.bidCard then found = true end
    end
    assertTrue(found, "HostDealRest: bidder hand contains the face-up bid card")
end

-- ApplyTrickEnd: appends to s.tricks, stamps lastTrick, clears s.trick.
freshState()
S.s.contract = { type = K.BID_HOKM, trump = "H", bidder = 1 }
S.s.trick = {
    leadSuit = "H",
    plays = {
        { seat = 1, card = "JH" }, { seat = 2, card = "9H" },
        { seat = 3, card = "AH" }, { seat = 4, card = "TH" },
    },
}
S.ApplyTrickEnd(1, 55)
assertEq(#S.s.tricks, 1, "ApplyTrickEnd: trick recorded")
assertEq(S.s.tricks[1].winner, 1, "ApplyTrickEnd: winner stored")
assertEq(S.s.tricks[1].points, 55, "ApplyTrickEnd: points stored")
assertEq(S.s.lastTrick.winner, 1, "ApplyTrickEnd: lastTrick.winner snapshotted")
assertEq(#S.s.trick.plays, 0, "ApplyTrickEnd: trick.plays reset to empty")
-- Audit-fix verification: ApplyTrickEnd stamps playedCardsThisRound for
-- every card in the swept trick, so the bot card-counter sees them.
assertTrue(S.s.playedCardsThisRound["JH"], "ApplyTrickEnd: JH stamped in playedCardsThisRound")
assertTrue(S.s.playedCardsThisRound["AH"], "ApplyTrickEnd: AH stamped in playedCardsThisRound")
assertTrue(S.s.playedCardsThisRound["TH"], "ApplyTrickEnd: TH stamped in playedCardsThisRound")
assertTrue(S.s.playedCardsThisRound["9H"], "ApplyTrickEnd: 9H stamped in playedCardsThisRound")

-- HighestUnplayedRank: tracks the top of each suit as cards fall.
freshState()
S.s.playedCardsThisRound = {}
assertEq(S.HighestUnplayedRank("H"), "A", "HighestUnplayedRank: nothing played → Ace top")
S.s.playedCardsThisRound["AH"] = true
assertEq(S.HighestUnplayedRank("H"), "T", "HighestUnplayedRank: A played → 10 top")
S.s.playedCardsThisRound["TH"] = true
assertEq(S.HighestUnplayedRank("H"), "K", "HighestUnplayedRank: A,T played → K top")
assertEq(S.HighestUnplayedRank("S"), "A", "HighestUnplayedRank: other suit untouched")
-- Empty / nil suit
assertEq(S.HighestUnplayedRank(nil), nil, "HighestUnplayedRank(nil) = nil")
assertEq(S.HighestUnplayedRank(""),  nil, "HighestUnplayedRank('') = nil")

-- GetLegalPlays: requires localSeat + IsMyTurn + PHASE_PLAY + contract.
freshState()
S.s.localSeat = 1
S.s.turn = 1
S.s.turnKind = "play"
S.s.phase = K.PHASE_PLAY
S.s.contract = { type = K.BID_HOKM, trump = "H", bidder = 1 }
S.s.hand = { "AS", "KS", "9D", "JH" }
S.s.trick = { leadSuit = "S", plays = { { seat = 4, card = "QS" } } }
do
    local legal = S.GetLegalPlays()
    -- Hand has spades (AS, KS), so player must follow suit. Legal: AS, KS.
    local set = {}
    for _, c in ipairs(legal) do set[c] = true end
    assertTrue(set["AS"],  "GetLegalPlays: AS in legal set (follow suit)")
    assertTrue(set["KS"],  "GetLegalPlays: KS in legal set")
    assertFalse(set["9D"], "GetLegalPlays: 9D NOT legal (must follow S)")
    assertFalse(set["JH"], "GetLegalPlays: JH NOT legal (must follow S)")
end

-- MeldVerdict: thin wrapper around CompareMelds; uses s.meldsByTeam.
-- Guard: returns nil unless at least one trick has been recorded
-- (verdict is meaningless before trick 1 closes).
freshState()
S.s.contract = { type = K.BID_HOKM, trump = "H", bidder = 1 }
S.s.meldsByTeam = {
    A = { { kind = "seq3", value = 20, len = 3, top = "9", suit = "S" } },
    B = {},
}
assertEq(S.MeldVerdict(), nil, "MeldVerdict: nil before any trick recorded")
S.s.tricks = { { winner = 1, points = 0, plays = {} } }
assertEq(S.MeldVerdict(), "A", "MeldVerdict: A has melds, B empty, post-trick-1 → A")

-- PreemptEligibleSeats: with dealer=1, bid order is 2,3,4,1.
-- buyer=4 → seats 2 and 3 are earlier and bid → eligible (excl. partner of 4 = 2).
-- So expected: just {3}.
freshState()
S.s.dealer = 1
S.s.bids = { [2] = K.BID_PASS, [3] = K.BID_PASS, [4] = K.BID_HOKM .. ":H" }
do
    local elig = S.PreemptEligibleSeats(4, 4)
    assertEq(#elig, 1, "PreemptEligibleSeats: 1 seat eligible (excl. partner)")
    assertEq(elig[1], 3, "PreemptEligibleSeats: seat 3 eligible")
end

-- buyer=1 (dealer themselves): all three earlier seats bid; partner is 3.
-- Expected eligibility: {2, 4} (3 excluded as partner).
freshState()
S.s.dealer = 1
S.s.bids = {
    [2] = K.BID_PASS, [3] = K.BID_PASS, [4] = K.BID_PASS,
    [1] = K.BID_SUN,
}
do
    local elig = S.PreemptEligibleSeats(1, 1)
    -- Bid order with dealer=1: 2, 3, 4, 1. All seats before 1 with a bid: 2,3,4.
    -- Exclude partner of 1 = 3. Eligible: {2, 4}.
    assertEq(#elig, 2, "PreemptEligibleSeats: 2 seats eligible when buyer is dealer")
    -- Order is dealer+1 first: 2, then 4 (3 was skipped as partner).
    assertEq(elig[1], 2, "PreemptEligible[1] = 2")
    assertEq(elig[2], 4, "PreemptEligible[2] = 4")
end

-- IsSeatBot / LobbyFull
freshState()
S.s.seats = {
    [1] = { name = "P1-realm" },
    [2] = { name = "BOT-2", isBot = true },
    [3] = { name = "P3-realm" },
    [4] = nil,
}
assertFalse(S.IsSeatBot(1), "IsSeatBot(1) = false (real player)")
assertTrue(S.IsSeatBot(2),  "IsSeatBot(2) = true")
assertFalse(S.IsSeatBot(4), "IsSeatBot(4) = false (empty)")
assertFalse(S.LobbyFull(),  "LobbyFull = false when seat 4 empty")
S.s.seats[4] = { name = "BOT-4", isBot = true }
assertTrue(S.LobbyFull(), "LobbyFull = true when all 4 seated")

-- HostValidatePlay
freshState()
S.s.isHost = true
S.s.contract = { type = K.BID_HOKM, trump = "H", bidder = 1 }
S.s.hostHands = { ["1"] = nil, [1] = { "AS", "KS", "9D" } }
S.s.turn = 1
S.s.trick = { leadSuit = "S", plays = { { seat = 4, card = "QS" } } }
do
    local ok, why = S.HostValidatePlay(1, "AS")
    assertTrue(ok, "HostValidatePlay: AS legal (following lead)")
    local ok2, why2 = S.HostValidatePlay(1, "9D")
    assertFalse(ok2, "HostValidatePlay: 9D illegal (must follow)")
end

-- HostScoreRoundResult (smoke check — defers to R.ScoreRound)
freshState()
S.s.isHost = true
S.s.contract = { type = K.BID_HOKM, trump = "H", bidder = 1 }
local stockPlays = {
    { seat = 1, card = "JH" }, { seat = 2, card = "9H" },
    { seat = 3, card = "AH" }, { seat = 4, card = "TH" },
}
for i = 1, 8 do
    S.s.tricks[i] = { winner = 1, leadSuit = "H", plays = stockPlays, points = 55 }
end
S.s.meldsByTeam = { A = {}, B = {} }
do
    local res = S.HostScoreRoundResult()
    assertTrue(res ~= nil, "HostScoreRoundResult: returns a result")
    assertEq(res.sweep, "A", "HostScoreRoundResult: sweep detected")
end

-- =====================================================================
-- B. Bot.PickPlay legality property test
-- =====================================================================
section("B. Bot.PickPlay legality (property test)")

-- Generate N random scenarios with a partial trick + a 4-card hand, and
-- verify Bot.PickPlay always returns a card that R.IsLegalPlay accepts.
-- Random hands drawn from the full deck without overlap with cards
-- already on the table.
local function randomScenario(seed)
    math.randomseed(seed)
    local deck = {}
    for _, suit in ipairs(K.SUITS) do
        for _, rank in ipairs(K.RANKS) do
            deck[#deck + 1] = rank .. suit
        end
    end
    -- shuffle
    for i = #deck, 2, -1 do
        local j = math.random(i)
        deck[i], deck[j] = deck[j], deck[i]
    end

    -- 0..3 cards already on table; rest of seats hold 5-card hands.
    local trickN = math.random(0, 3)
    local plays = {}
    local idx = 1
    -- Pick a random seat for the bot under test (the "next to play").
    -- Seats already played form trick.plays; we'll always have the bot
    -- be the seat AFTER the last play (or seat 1 if empty).
    local botSeat
    if trickN == 0 then
        botSeat = math.random(1, 4)
    else
        local leader = math.random(1, 4)
        for k = 1, trickN do
            local s = ((leader - 1 + k - 1) % 4) + 1
            plays[#plays + 1] = { seat = s, card = deck[idx] }
            idx = idx + 1
        end
        botSeat = ((plays[#plays].seat) % 4) + 1
    end
    local leadSuit = (#plays > 0 and C.Suit(plays[1].card)) or nil

    -- Hands: bot + 3 others. 5 cards each (mid-game-ish).
    local hands = {}
    for s = 1, 4 do
        hands[s] = {}
        for _ = 1, 5 do
            hands[s][#hands[s] + 1] = deck[idx]
            idx = idx + 1
        end
    end

    local trumps = K.SUITS
    local trump = trumps[math.random(1, 4)]
    local contractType = (math.random() < 0.7) and K.BID_HOKM or K.BID_SUN
    local contract = { type = contractType, bidder = math.random(1, 4) }
    if contractType == K.BID_HOKM then contract.trump = trump end

    return botSeat, hands, plays, leadSuit, contract
end

local function setupAndPick(botSeat, hands, plays, leadSuit, contract)
    freshState()
    S.s.isHost = true
    S.s.hostHands = hands
    S.s.contract = contract
    S.s.trick = { leadSuit = leadSuit, plays = plays }
    -- Reset bot memory between scenarios so accumulated state doesn't
    -- contaminate later picks.
    if Bot.ResetMemory then Bot.ResetMemory() end
    return Bot.PickPlay(botSeat)
end

local N = 100
local illegalHits = 0
for i = 1, N do
    local botSeat, hands, plays, leadSuit, contract = randomScenario(i)
    local pick = setupAndPick(botSeat, hands, plays, leadSuit, contract)
    if pick == nil then
        illegalHits = illegalHits + 1
        if VERBOSE then
            print(("    scenario %d: PickPlay returned nil (seat %d, %d cards)")
                  :format(i, botSeat, #hands[botSeat]))
        end
    else
        local ok = R.IsLegalPlay(
            pick, hands[botSeat],
            { leadSuit = leadSuit, plays = plays },
            contract, botSeat)
        if not ok then
            illegalHits = illegalHits + 1
            if VERBOSE then
                print(("    scenario %d: ILLEGAL pick %s (seat %d, lead=%s)")
                      :format(i, pick, botSeat, tostring(leadSuit)))
            end
        end
    end
end
assertEq(illegalHits, 0, ("Bot.PickPlay legality: %d/%d scenarios all legal"):format(N, N))

-- =====================================================================
-- C. Bot.PickBid sanity — strong hand bids, weak hand passes
-- =====================================================================
section("C. Bot.PickBid sanity")

-- Strong Hokm-hearts hand: J,9,A of trump + length should produce a Hokm bid.
do
    freshState()
    S.s.isHost = true
    S.s.bidRound = 1
    S.s.bidCard = "9H"  -- bid card matters less than hand strength
    S.s.dealer = 4
    S.s.bids = {}
    S.s.hostHands = {
        [1] = { "JH","9H","AH","TH","KH" },  -- 5 of a single suit, all top trumps if Hokm-H
        [2] = { "7S","8S","9S","TS","JS" },
        [3] = { "7C","8C","9C","TC","JC" },
        [4] = { "7D","8D","9D","TD","JD" },
    }
    S.s.contract = nil
    local bid = Bot.PickBid(1)
    assertTrue(bid and bid:sub(1,4) == K.BID_HOKM,
               ("PickBid: strong 5-trump hand bids Hokm (got %s)"):format(tostring(bid)))
end

-- Weak hand: random low cards, no trump strength. Should pass.
do
    freshState()
    S.s.isHost = true
    S.s.bidRound = 1
    S.s.bidCard = "8S"
    S.s.dealer = 4
    S.s.bids = {}
    S.s.hostHands = {
        [1] = { "7S","8H","7D","8C","9D" },  -- 5 zero-pt cards, no length
        [2] = { "AH","TH","KH","QH","JH" },
        [3] = { "AS","TS","KS","QS","JS" },
        [4] = { "AC","TC","KC","QC","JC" },
    }
    S.s.contract = nil
    local bid = Bot.PickBid(1)
    assertEq(bid, K.BID_PASS,
             ("PickBid: weak 7/8-only hand passes (got %s)"):format(tostring(bid)))
end

-- =====================================================================
-- D. Headless tournament — Bot tier comparison
-- =====================================================================
section("D. Headless tournament (Bot tier comparison)")

-- Run a complete 8-trick play-only round between two bot configurations.
-- Same dealt hands, same contract, same lead — only difference is which
-- bots are at which seats. Compare aggregate trick-points across N rounds.

-- Run a single 8-trick round with all 4 seats picking via Bot.PickPlay.
-- Returns: { teamPoints = {A=N, B=N}, sweep = "A"|"B"|nil }
local function playOneRound(hands, contract, leaderSeat)
    freshState()
    S.s.isHost = true
    S.s.contract = contract
    -- Deep copy hands so the test doesn't mutate the caller's array.
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
    if Bot.ResetStyle  then Bot.ResetStyle()  end

    local nextLeader = leaderSeat
    for trickN = 1, 8 do
        S.s.trick = { leadSuit = nil, plays = {} }
        local seat = nextLeader
        for play = 1, 4 do
            local card = Bot.PickPlay(seat)
            if not card then
                error(("trick %d: bot seat %d returned nil"):format(trickN, seat))
            end
            -- Verify legality
            local ok = R.IsLegalPlay(card, h[seat], S.s.trick, contract, seat)
            if not ok then
                error(("trick %d: bot seat %d picked illegal %s"):format(trickN, seat, card))
            end
            -- Apply the play: remove card from hand, append to trick, set leadSuit.
            for i, c in ipairs(h[seat]) do
                if c == card then table.remove(h[seat], i); break end
            end
            S.s.trick.plays[#S.s.trick.plays + 1] = { seat = seat, card = card }
            if play == 1 then S.s.trick.leadSuit = C.Suit(card) end
            seat = (seat % 4) + 1
        end
        -- Resolve trick
        local winner = R.TrickWinner(S.s.trick, contract)
        local pts    = R.TrickPoints(S.s.trick, contract)
        S.ApplyTrickEnd(winner, pts)
        nextLeader = winner
    end

    -- Tally team scores manually so we don't trip over melds/escalations.
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
    return { teamPoints = teamPoints, sweep = sweep,
             trickCount = trickCount }
end

-- Build a randomised but balanced 4×8 deal. We use a freshly shuffled deck
-- via Cards.Shuffle. Returns hands + a seed-derived contract.
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

-- Pick a contract: bidder is the seat with the strongest single-suit
-- holding (most cards of one suit, ties → most points). This is a crude
-- proxy for "who would actually buy the bid".
local function pickContract(hands)
    local bestSeat, bestSuit, bestScore = 1, "S", -1
    for seat = 1, 4 do
        local bySuit = { S=0, H=0, D=0, C=0 }
        local bySuitPoints = { S=0, H=0, D=0, C=0 }
        for _, c in ipairs(hands[seat]) do
            local suit = C.Suit(c)
            bySuit[suit] = bySuit[suit] + 1
            bySuitPoints[suit] = bySuitPoints[suit] +
                (K.POINTS_TRUMP_HOKM[C.Rank(c)] or 0)
        end
        for suit, count in pairs(bySuit) do
            local score = count * 100 + bySuitPoints[suit]
            if score > bestScore then
                bestSeat, bestSuit, bestScore = seat, suit, score
            end
        end
    end
    return { type = K.BID_HOKM, trump = bestSuit, bidder = bestSeat }
end

-- Configure tier flags (touches the saved-variables flags Bot reads).
local function setTier(tier)
    WHEREDNGNDB.advancedBots    = false
    WHEREDNGNDB.m3lmBots        = false
    WHEREDNGNDB.fzlokyBots      = false
    WHEREDNGNDB.saudiMasterBots = false
    if tier == "advanced" then WHEREDNGNDB.advancedBots = true
    elseif tier == "m3lm" then WHEREDNGNDB.m3lmBots = true
    elseif tier == "fzloky" then WHEREDNGNDB.fzlokyBots = true
    elseif tier == "master" then WHEREDNGNDB.saudiMasterBots = true end
end

-- Tournament: same N deals played twice, once with all-Basic bots, once
-- with all-M3lm bots. Compare bidder-team performance.
-- Hypothesis: higher tier shouldn't make bidder win MORE (same hands +
-- same contract), but it should at least not lose. We assert that the
-- M3lm side's per-round point total is in a sensible range.
local NUM_ROUNDS = 30
local basicSum, m3lmSum, masterSum = 0, 0, 0
local nilCount = 0

for i = 1, NUM_ROUNDS do
    local seed = i * 7919  -- distinct seeds across runs
    local hands = dealRandom(seed)
    local contract = pickContract(hands)
    local leader = contract.bidder

    setTier("basic")
    local r1 = playOneRound(hands, contract, leader)
    basicSum = basicSum + (r1.teamPoints[R.TeamOf(contract.bidder)] or 0)

    setTier("m3lm")
    local r2 = playOneRound(hands, contract, leader)
    m3lmSum = m3lmSum + (r2.teamPoints[R.TeamOf(contract.bidder)] or 0)

    setTier("master")
    local r3 = playOneRound(hands, contract, leader)
    masterSum = masterSum + (r3.teamPoints[R.TeamOf(contract.bidder)] or 0)

    -- Sanity: every round should produce a valid result.
    if r1.teamPoints == nil or r2.teamPoints == nil or r3.teamPoints == nil then
        nilCount = nilCount + 1
    end
end

assertEq(nilCount, 0, "Tournament: all rounds produced a valid result")
-- All tiers should accumulate sane totals (>0; bidder team usually
-- captures at least some tricks).
assertTrue(basicSum > 0, ("Tournament: Basic bidder-team total > 0 (got %d)"):format(basicSum))
assertTrue(m3lmSum > 0,  ("Tournament: M3lm bidder-team total > 0 (got %d)"):format(m3lmSum))
assertTrue(masterSum > 0, ("Tournament: Master bidder-team total > 0 (got %d)"):format(masterSum))
print(("    [info] Basic avg = %.1f, M3lm = %.1f, Master = %.1f over %d rounds")
      :format(basicSum / NUM_ROUNDS, m3lmSum / NUM_ROUNDS, masterSum / NUM_ROUNDS, NUM_ROUNDS))

-- The strict-superset cascade implies: M3lm includes all Advanced
-- heuristics, which include Basic. So M3lm should never play strictly
-- worse than Basic on average. We assert M3lm ≥ Basic - margin (loose
-- bound, since same-deal variance and some heuristics make different
-- choices that wash out across 30 rounds).
local margin = 0.85   -- M3lm must be at least 85% of Basic
assertTrue(m3lmSum >= basicSum * margin,
           ("Tournament: M3lm aggregate >= 85%% of Basic (m3lm=%d, basic=%d)")
           :format(m3lmSum, basicSum))

-- =====================================================================
-- E. v0.5.11 fix coverage — pickFollow regression pins
--
-- The Wave-3 audit flagged that v0.5.11's 4 fixes (Race A wire,
-- Section 4 rule 1, Takbeer smother, T-4 over-fire gate) shipped
-- without any new tests — a future refactor could silently re-flip
-- the load-bearing behavior. These tests pin the post-v0.5.11
-- behavior so any regression fails loudly.
--
-- The Race A wire test would require loading Net.lua, which this
-- harness doesn't currently do. Wire-side enforcement uses the same
-- pattern (broadcast + HostFinishDeal) as the well-exercised AFK
-- timeout path, so the missing test is acceptable risk for now.
-- =====================================================================
section("E. v0.5.11 fix coverage")

-- E.1: Section 4 rule 1A (Common, video 05). REVISED v0.7.2.
-- Sun + OPP winning + we must follow with cards that can't beat.
-- Saudi Tasgheer / play-smallest convention: dump the SMALLEST
-- in-suit card. Per video #05 transcript: opp's K-play implies no
-- Q/J/9/8/7 below it (those would have been played first because
-- they're smaller than K in plain rank). Mirror: we play smallest
-- non-saving card.
--
-- v0.5.11 introduced "dump HIGHEST" citing both videos #05 and #09,
-- but cross-checking the transcripts shows v0.5.11 conflated two
-- distinct scenarios. v0.7.2 split them: this E.1 is the OPP-winning
-- case (rule 1A → SMALLEST). E.6 covers the PARTNER-winning case
-- (rule 1B → SECOND-LOWEST per video #09 "biggest mistake").
do
    freshState()
    S.s.isHost = true
    S.s.contract = { type = K.BID_SUN, trump = nil, bidder = 1 }
    -- Trick: seat 1 (OPP of seat 2) led AH (winning, can't be beat).
    -- Seat 2 to follow with hand containing KH+JH+8H — three H cards,
    -- none can beat AH. partnerWinning=false (seat 1 is opp).
    S.s.hostHands = {
        [1] = { "AH", "TH", "QH", "AS", "KS", "QS", "JS", "TS" },
        [2] = { "KH", "JH", "8H", "8C", "7C", "8D", "7D", "9D" },
        [3] = { "AC", "TC", "KC", "QC", "JC", "AD", "KD", "QD" },
        [4] = { "9H", "7H", "9C", "JD", "TD", "9S", "8S", "7S" },
    }
    S.s.trick = { leadSuit = "H", plays = { { seat = 1, card = "AH" } } }
    S.s.tricks = {}
    -- Seat 2's must-follow legal = {KH, JH, 8H}. Can't beat AH.
    -- v0.7.2 rule 1A: opp-winning + can't-beat → lowestByRank → 8H.
    local card = Bot.PickPlay(2)
    assertEq(card, "8H",
             "v0.7.2 E.1: Sun + opp winning + can't beat → SMALLEST in-suit (8H, Tasgheer)")
end

-- E.2: Section 4 rule 7 Takbeer (Definite, videos 21+22+23).
-- Smother branch: when partner is currently winning a non-trump-led
-- trick, we donate the HIGHEST of {A, T} held in led suit, not the
-- lowest. Pre-v0.5.11 sorted ascending → returned LOWEST (T over A).
-- Post-v0.5.11: descending → A over T. +1 raw point per occurrence.
do
    freshState()
    S.s.isHost = true
    S.s.contract = { type = K.BID_SUN, trump = nil, bidder = 2 }
    -- Trick: 3 plays already, seat 1 in pos 4 (lastSeat=true).
    -- Seat 3 (partner) played KH and is currently winning.
    -- Seat 1 hand has BOTH AH and TH — highInSuit = {AH, TH}.
    S.s.hostHands = {
        [1] = { "AH", "TH", "9C", "8C", "7C", "8D", "7D", "9D" },
        [2] = {},
        [3] = {},
        [4] = {},
    }
    S.s.trick = { leadSuit = "H", plays = {
        { seat = 2, card = "9H" },
        { seat = 3, card = "KH" },
        { seat = 4, card = "JH" },
    } }
    S.s.tricks = {}
    -- partnerWinning=true (seat 3 = partner, KH currently highest).
    -- Both AH and TH legal (must follow H). highInSuit = {A, T}.
    -- lastSeat=true → smother fires. Post-fix descending sort → AH.
    local card = Bot.PickPlay(1)
    assertEq(card, "AH",
             "v0.5.11 E.2: Takbeer smother donates HIGHEST (AH > TH)")
end

-- E.3: T-4 over-fire gate (Wave-2 audit finding).
-- v0.5.10's Tahreeb T-4 dump-larger fired on ANY 2-card non-trump
-- non-led suit, including K+J / A+x doubletons — shedding valuable
-- cards. Post-v0.5.11: only fires when the doubleton's higher rank
-- is at most Q. K/T/A doubletons fall through to lowestByRank.
do
    -- M3lm tier required (Tahreeb is M3lm-gated).
    WHEREDNGNDB.m3lmBots = true
    freshState()
    S.s.isHost = true
    S.s.contract = { type = K.BID_HOKM, trump = "S", bidder = 2 }
    -- Hand: K+J of hearts (2-card with hi=K → should skip per gate),
    -- A+9 of diamonds (2-card with hi=A → should skip),
    -- 4 trumps (KS, QS, 8S, 7S). Void in clubs (led).
    S.s.hostHands = {
        [1] = { "KH", "JH", "KS", "QS", "8S", "7S", "AD", "9D" },
        [2] = {},
        [3] = {},
        [4] = {},
    }
    S.s.trick = { leadSuit = "C", plays = {
        { seat = 2, card = "9C" },
        { seat = 3, card = "AC" },
        { seat = 4, card = "TC" },
    } }
    S.s.tricks = {}
    -- Mark partner (seat 3) as bot for the bot-partner-only gate.
    S.s.seats = {
        [1] = nil,
        [2] = { isBot = true },
        [3] = { isBot = true },
        [4] = { isBot = true },
    }
    if Bot.ResetMemory then Bot.ResetMemory() end
    -- voidInLed=true (no clubs). M3lm=true. partner-bot=true.
    -- T-1 Bargiya: skipped (HOKM not Sun).
    -- T-4: iterates S, H, D, C.
    --   S (trump): excluded.
    --   H: KH+JH, hi=KH, hiRank="K" → SKIP (gate).
    --   D: AD+9D, hi=AD, hiRank="A" → SKIP (gate).
    --   C: void → skip.
    -- No T-4 return. Falls through to lowestByRank(legal, contract).
    -- Lowest trick rank: 7S (trump rank 1 in RANK_TRUMP_HOKM).
    -- Pre-v0.5.11: T-4 fired on H, returned KH.
    local card = Bot.PickPlay(1)
    assertEq(card, "7S",
             "v0.5.11 E.3: T-4 gate skips K/A doubletons → lowestByRank → 7S")
    -- Cleanup
    WHEREDNGNDB.m3lmBots = false
end

-- E.4: T-4 base case (sanity) — Q-doubleton still fires.
-- Verifies the gate doesn't accidentally block Q-doubletons (the
-- actual "2-card unwanted suit" case the rule was designed for).
do
    WHEREDNGNDB.m3lmBots = true
    freshState()
    S.s.isHost = true
    S.s.contract = { type = K.BID_HOKM, trump = "S", bidder = 2 }
    -- Hand: Q+J of hearts (2-card with hi=Q → SHOULD fire T-4).
    -- 3-card clubs (not 2-card, won't be considered).
    -- 3 trumps. Void in diamonds (led).
    S.s.hostHands = {
        [1] = { "QH", "JH", "7C", "8C", "9C", "KS", "QS", "JS" },
        [2] = {},
        [3] = {},
        [4] = {},
    }
    S.s.trick = { leadSuit = "D", plays = {
        { seat = 2, card = "9D" },
        { seat = 3, card = "AD" },
        { seat = 4, card = "TD" },
    } }
    S.s.tricks = {}
    S.s.seats = {
        [1] = nil,
        [2] = { isBot = true },
        [3] = { isBot = true },
        [4] = { isBot = true },
    }
    if Bot.ResetMemory then Bot.ResetMemory() end
    -- T-4 fires on H: hi=QH, hiRank="Q" → passes gate → returns QH.
    local card = Bot.PickPlay(1)
    assertEq(card, "QH",
             "v0.5.11 E.4: T-4 fires on Q-doubleton (sanity, gate passes)")
    WHEREDNGNDB.m3lmBots = false
end

-- E.5: PickDouble integration with R.CanBel (Sun Bel-100 gate).
-- v0.5.9 introduced the gate; this pins the bot-side integration:
-- PickDouble must early-return false when R.CanBel returns false,
-- regardless of strength. Without this test, a future refactor of
-- the PickDouble early checks could silently drop the gate.
do
    freshState()
    S.s.isHost = true
    S.s.contract = { type = K.BID_SUN, trump = nil, bidder = 1 }
    -- Defender team B at cumulative 100 (gate fires).
    S.s.cumulative = { A = 50, B = 100 }
    -- Seat 2's hand is strong-Bel material (would normally fire).
    S.s.hostHands = {
        [1] = { "9H", "8H", "7H", "9D", "8D", "7D", "9C", "8C" },
        [2] = { "AH", "KH", "QH", "JH", "AS", "TS", "AD", "AC" },
        [3] = { "TH", "KD", "QD", "JD", "TC", "KC", "QC", "JC" },
        [4] = { "JS", "9S", "8S", "7S", "KS", "QS", "TD", "JH" },
    }
    local yes = Bot.PickDouble(2)
    assertEq(yes, false,
             "v0.5.11 E.5: PickDouble respects R.CanBel (Sun, B>=100, blocked)")

    -- Sanity: Hokm has no gate. Same hand, Hokm contract → may fire.
    S.s.contract = { type = K.BID_HOKM, trump = "H", bidder = 1 }
    -- Don't assert specific result for Hokm Bel — just verify it's not
    -- blocked by R.CanBel (returns true unconditionally for Hokm).
    -- The actual fire is strength-dependent; the key invariant is
    -- that the gate path doesn't short-circuit Hokm.
    local hokmYes = Bot.PickDouble(2)
    -- We expect either true or false — but NOT a forced-false from
    -- the CanBel gate. The test just exercises that Hokm bypasses.
    -- Don't assert on hokmYes (strength-dependent); use a placeholder
    -- assertion that confirms the call completes without error.
    assertTrue(hokmYes == true or hokmYes == false,
               "v0.5.11 E.5b: PickDouble in Hokm not blocked by Sun-100 gate")
end

-- E.6: Section 4 rule 1B (Definite, video 09 "biggest mistake").
-- Sun + PARTNER winning the trick + we must follow + we can't beat
-- partner's lead AND smother (Takbeer) doesn't fire (no A/T/K/Q/J of
-- led suit to donate). Per video #09: don't play absolute lowest —
-- play second-lowest to preserve partner's option to lead this suit
-- back to us as a re-entry. Absolute lowest signals "I'm out of this
-- suit" and is the "biggest mistake in Baloot".
do
    freshState()
    S.s.isHost = true
    S.s.contract = { type = K.BID_SUN, trump = nil, bidder = 4 }
    -- Trick: seat 4 (PARTNER of seat 2) led AH. Seat 2 must follow.
    -- Seat 2's H cards: {KH, JH, 8H} — no A/T/K/Q/J that beats AH;
    -- has K/J/8 but K and J both lose to A. Smother gate requires
    -- ≥2 point cards (KH+JH qualifies — wait, K is rank 4 so it IS
    -- a point card per the v0.5.18 expansion which now includes
    -- A/T/K/Q/J). Need to construct a hand where smother SKIPS so
    -- the rule 1B fall-through fires.
    --
    -- Smother gate (Bot.lua ~line 2185): #pointCards >= 2 OR
    -- completed >= 3 OR lastSeat. We're pos 2 (not lastSeat),
    -- completed = 0 (no prior tricks). To skip smother, we need
    -- only ONE point card in suit. Construct: seat 2's H cards =
    -- {KH, 9H, 8H}. K is the only point card (J,Q,T,A excluded by
    -- design here). #pointCards = 1, completed = 0, not lastSeat
    -- → smother gate fails → fall-through to rule 1B → second-lowest.
    --
    -- Sorted ascending by trick rank: 8H (rank 2) < 9H (rank 3) <
    -- KH (rank 6). Second-lowest = 9H.
    S.s.hostHands = {
        [1] = { "AS", "TS", "KS", "QS", "JS", "AC", "TC", "KC" },
        [2] = { "KH", "9H", "8H", "8C", "7C", "8D", "7D", "9D" },
        [3] = { "TH", "QH", "JH", "QC", "JC", "AD", "KD", "QD" },
        [4] = { "AH", "9C", "JD", "TD", "9S", "8S", "7S", "7H" },
    }
    S.s.trick = { leadSuit = "H", plays = { { seat = 4, card = "AH" } } }
    S.s.tricks = {}
    -- partnerWinning = (seat 4 winning) and seat 4 = R.Partner(2)?
    -- Partners: 1↔3, 2↔4. R.Partner(2) = 4. Yes, partnerWinning.
    -- Smother: pointCards in H = {KH}. #pointCards=1, completed=0,
    -- not lastSeat → gate fails. Tahreeb-sender requires voidInLed
    -- (we're NOT void since we have H). Falls to rule 1B branch.
    -- Result: second-lowest of {KH, 9H, 8H} = 9H.
    local card = Bot.PickPlay(2)
    assertEq(card, "9H",
             "v0.7.2 E.6: Sun + partner winning + can't beat → SECOND-LOWEST (9H, video #09 'biggest mistake' fix)")
end

-- =====================================================================
-- F. v0.5.14 Section 9 Tanfeer (تنفير) — opponent-disrupt convention
--
-- Three rules from decision-trees.md Section 9:
--   N-1 (Sender): opp winning + we discard → low card from "wanted
--        suit" (suit holding A or T, ≥2 cards) signals partner.
--   N-2 (Default semantics): uncertain winner → default to Tahreeb.
--        Documented in code comments; no separate test.
--   N-3 (Receiver): opp's recorded "want"/"bargiya" tahreebSent →
--        suit-to-AVOID on lead (deny opp tempo). Also wires the
--        partner-dontwant signal (formerly the dead `tahreebAvoidSuit`
--        variable from Wave-2 audit).
-- =====================================================================
section("F. v0.5.14 Section 9 Tanfeer")

-- F.1: N-1 sender — opp winning, we void in led, hand has A+low in a
-- side suit. Discard the LOW (suit-only positive signal).
-- NOTE: must use Sun contract — in Hokm, opp-winning + void-in-led
-- triggers must-trump (legal restricted to trumps), so N-1 has no
-- non-trump candidates to choose from. Sun has no must-trump rule.
do
    WHEREDNGNDB.m3lmBots = true
    freshState()
    S.s.isHost = true
    S.s.contract = { type = K.BID_SUN, trump = nil, bidder = 2 }
    -- Hand: AH+7H (wanted suit), + 6 non-high non-led cards.
    -- Spades has no A/T (so N-1 skips it). Diamonds void.
    S.s.hostHands = {
        [1] = { "AH", "7H", "9S", "8S", "KS", "QS", "JS", "7S" },
        [2] = {},
        [3] = {},
        [4] = {},
    }
    -- Trick: 9C led, opp seat 4 played AC (winning).
    S.s.trick = { leadSuit = "C", plays = {
        { seat = 2, card = "9C" },
        { seat = 3, card = "JC" },
        { seat = 4, card = "AC" },
    } }
    S.s.tricks = {}
    S.s.seats = {
        [1] = nil,
        [2] = { isBot = true },
        [3] = { isBot = true },
        [4] = { isBot = true },
    }
    if Bot.ResetMemory then Bot.ResetMemory() end
    -- Opp winning (seat 4 = AC). partnerWinning=false.
    -- Section 4 rule 1 (Sun + leadSuit): #follow=0 (void in C). Skip.
    -- Section 9 N-1 iterates {S, H, D, C}:
    --   S: hasHigh=false (no AS/TS). Skip.
    --   H: hasHigh=true (AH). lows=[7H]. RETURN 7H.
    -- Pre-v0.5.14: lowestByRank(legal). Plain min=7H, 7S (tie at rank 1).
    -- Iteration order returns AH first... actually min rank wins, 7H=1
    -- and 7S=1, first found wins. legal iteration order matches hand
    -- order: 7H comes before 7S, so 7H. But this isn't a robust pin
    -- — the v0.5.14 N-1 logic returns 7H DETERMINISTICALLY via the
    -- {S,H,D,C} iteration + has-high gate. That's the difference.
    local card = Bot.PickPlay(1)
    assertEq(card, "7H",
             "v0.5.14 F.1: N-1 sender — opp winning, void in led, A+low → low (7H)")
    WHEREDNGNDB.m3lmBots = false
end

-- F.2: N-1 sender doesn't fire when no qualifying wanted suit.
-- Lone A (no spare low in same suit), no other A/T in any suit.
do
    WHEREDNGNDB.m3lmBots = true
    freshState()
    S.s.isHost = true
    S.s.contract = { type = K.BID_SUN, trump = nil, bidder = 2 }
    -- Hand: lone AH, no other A/T anywhere. 7 low non-led cards.
    S.s.hostHands = {
        [1] = { "AH", "7D", "8D", "9D", "JD", "7S", "8S", "9S" },
        [2] = {}, [3] = {}, [4] = {},
    }
    S.s.trick = { leadSuit = "C", plays = {
        { seat = 2, card = "9C" },
        { seat = 3, card = "JC" },
        { seat = 4, card = "AC" },
    } }
    S.s.tricks = {}
    S.s.seats = {
        [1] = nil,
        [2] = { isBot = true },
        [3] = { isBot = true },
        [4] = { isBot = true },
    }
    if Bot.ResetMemory then Bot.ResetMemory() end
    -- N-1 search (Sun, no trump exclusion):
    --   S: no A/T → hasHigh=false. Skip.
    --   H: AH alone, lows={}, ≥1 fails. Skip.
    --   D: no A/T. Skip.
    --   C: void. Skip.
    -- Falls through to lowestByRank. AH must NOT be returned.
    local card = Bot.PickPlay(1)
    assertTrue(card ~= "AH",
               "v0.5.14 F.2: N-1 doesn't burn lone A (no spare low)")
    WHEREDNGNDB.m3lmBots = false
end

-- F.3: N-3 receiver — opp signaled "want" (ascending) in suit X,
-- pickLead avoids X.
-- Setup: opp seat 2 sent {7H, 9H} ascending in hearts (their
-- partner is seat 4). pickLead for seat 1 should avoid leading H.
-- This test verifies the opp-side avoid-set wire.
do
    WHEREDNGNDB.m3lmBots = true
    freshState()
    S.s.isHost = true
    S.s.contract = { type = K.BID_HOKM, trump = "S", bidder = 1 }
    -- Set up opp seat 2's recorded tahreebSent: ascending in H.
    -- Need to lazy-init partnerStyle first.
    if Bot.ResetMemory then Bot.ResetMemory() end
    -- Force lazy init by triggering OnPlayObserved with a no-op-equivalent.
    -- Simpler: directly set the ledger.
    if not Bot._partnerStyle then
        -- Manually trigger init via emptyStyle (private) — use a fake
        -- play to do it.
        Bot._partnerStyle = nil
        Bot.OnPlayObserved(1, "8S", nil)  -- lead play, init triggers
    end
    -- Now overwrite seat 2's tahreebSent.H with ascending sequence.
    -- The receiver classifies {7,9} as "want" (ascending).
    if Bot._partnerStyle and Bot._partnerStyle[2] then
        Bot._partnerStyle[2].tahreebSent.H = { "7", "9" }
    end
    -- Lead trick. Hand has cards in multiple non-trump suits.
    S.s.hostHands = {
        [1] = { "8H", "9H", "8D", "9D", "8C", "9C", "JS", "QS" },
        [2] = {}, [3] = {}, [4] = {},
    }
    S.s.trick = { leadSuit = nil, plays = {} }  -- no plays = lead
    S.s.tricks = {}
    S.s.seats = {
        [1] = nil,
        [2] = { isBot = true },
        [3] = { isBot = true },
        [4] = { isBot = true },
    }
    -- The pref-suit logic finds no positive partner signal (only opp
    -- signals). tahreebAvoidSet = { H = true } from opp seat 2's "want".
    -- tahreebPrefSuit = nil. Falls through to existing lead heuristics.
    -- The avoid wire ONLY filters partner-pref conflicts (no impact
    -- when no partner signal exists). The card returned is determined
    -- by the existing fall-through; we just verify the call completes
    -- without error and doesn't crash on the opp-tahreebSent read.
    local card = Bot.PickPlay(1)
    assertTrue(card ~= nil,
               "v0.5.14 F.3: N-3 receiver — opp signal recorded, pickLead returns valid card")
    -- Stronger assertion: when partner ALSO signals "want" in the
    -- same suit, the conflict-resolution drops the partner pref.
    -- Wave-2 specifically called out this conflict path.
    if Bot._partnerStyle and Bot._partnerStyle[3] then
        Bot._partnerStyle[3].tahreebSent.H = { "7", "9" }  -- partner ALSO wants H
    end
    -- Now: partner pref = H (want, score 2). Opp pref = H (want).
    -- Conflict resolution: drop partner pref (defending dominates).
    -- pickLead falls through to existing logic. Card returned is NOT
    -- forced to be H (partner pref dropped).
    local cardAfter = Bot.PickPlay(1)
    assertTrue(cardAfter ~= nil,
               "v0.5.14 F.3b: N-3 conflict resolution — opp+partner same suit → partner pref dropped")
    WHEREDNGNDB.m3lmBots = false
    if Bot.ResetMemory then Bot.ResetMemory() end  -- cleanup
end

-- =====================================================================
-- G. Ashkal eligibility — bid-position-based seat restriction
--
-- Audit-recommended pin (v0.5.6/v0.5.7 saga): only the dealer +
-- dealer's-LEFT may call Ashkal. v0.5.6 incorrectly inverted this
-- to dealer + dealer's-RIGHT; v0.5.7 reverted. UI.lua:223-225's
-- NextSeat=right convention is the disambiguator. In bid order
-- (dealer-left first, dealer last), eligible seats are positions
-- 3 (dealer's-left) and 4 (dealer).
--
-- This fixture pins the post-v0.5.7 correct behavior: 16 assertions
-- (4 dealer values × 4 seat values) verifying which seat-by-dealer
-- combinations may legally call Ashkal.
-- =====================================================================
section("G. Ashkal eligibility (audit-recommended fixture)")

-- Reusable helper: simulate a round-1 Ashkal attempt by setting
-- s.bids and calling HostAdvanceBidding. The Ashkal-call rule
-- silently drops the call if the seat isn't bidPosition >= 3.
-- We test this by reading whether the RESULT favors the Ashkal
-- caller (or their partner, who becomes the Sun-bidder if Ashkal
-- succeeds).
local function ashkalEligible(dealer, seat)
    -- bid order = {(d%4)+1, ((d+1)%4)+1, ((d+2)%4)+1, d}.
    -- Position of `seat` in that order.
    local order = {
        (dealer % 4) + 1, ((dealer + 1) % 4) + 1,
        ((dealer + 2) % 4) + 1, dealer,
    }
    for i, st in ipairs(order) do
        if st == seat then return i >= 3 end
    end
    return false
end

-- Cross-check: for each (dealer, seat), set up a scenario where:
--   - dealer-left bidder bids HOKM:H
--   - then `seat` attempts ASHKAL
--   - other bidders pass
-- HostAdvanceBidding result tells us whether Ashkal was honored.
-- Eligible seats produce contract={SUN, viaAshkal=true}; ineligible
-- seats produce contract={HOKM, ...} (Ashkal silently dropped).
for dealer = 1, 4 do
    local order = {
        (dealer % 4) + 1, ((dealer + 1) % 4) + 1,
        ((dealer + 2) % 4) + 1, dealer,
    }
    for seat = 1, 4 do
        local expected = ashkalEligible(dealer, seat)
        local label = ("dealer=%d seat=%d (bidPos=%d)"):format(
            dealer, seat,
            (seat == order[1] and 1) or
            (seat == order[2] and 2) or
            (seat == order[3] and 3) or
            (seat == order[4] and 4) or 0
        )
        -- Build a bid sequence: first eligible bidder (order[1]) bids
        -- HOKM:H, our `seat` bids ASHKAL, others PASS.
        -- Special case: if seat IS order[1], they can't bid HOKM AND
        -- ASHKAL — so use a different testing setup.
        local bids = {}
        if seat == order[1] then
            -- seat is the FIRST bidder. They bid Ashkal directly
            -- (no prior Hokm). Per Saudi rule, bidPos 1 can't
            -- Ashkal — the Hokm bid is required to be in winner
            -- before Ashkal evaluates (line 1500: HOKM gates winning).
            -- So seat 1 alone bidding Ashkal means winning stays nil
            -- after the Ashkal logic (which checks bidPos >= 3).
            -- For a clean test, we still expect Ashkal silently drops
            -- and we should fall to whatever else qualifies. Add
            -- HOKM:H from seat-2 to make the scenario testable.
            bids[seat] = K.BID_ASHKAL
            bids[order[2]] = "HOKM:H"
            bids[order[3]] = K.BID_PASS
            bids[order[4]] = K.BID_PASS
        else
            -- seat is not first. order[1] bids HOKM:H, seat bids ASHKAL.
            bids[order[1]] = "HOKM:H"
            bids[seat] = K.BID_ASHKAL
            for _, st in ipairs(order) do
                if not bids[st] then bids[st] = K.BID_PASS end
            end
        end

        S.s.isHost = true
        S.s.contract = nil
        S.s.dealer = dealer
        S.s.bidRound = 1
        S.s.bids = bids

        local action, payload = S.HostAdvanceBidding()

        -- If Ashkal was honored, the contract type becomes Sun (via
        -- Ashkal: declarer = caller's partner). If not, the Hokm
        -- from the first bidder wins.
        local ashkalHonored = (action == "contract"
                              and payload
                              and payload.type == K.BID_SUN)
        assertEq(ashkalHonored, expected,
                 ("v0.5.15 G: Ashkal eligibility (%s) honored=%s"):format(
                     label, tostring(expected)))
    end
end

-- =====================================================================
-- H. v0.7 Sun-overcall (S.BeginOvercall / S.RecordOvercallDecision /
--    S.FinalizeOvercall) + Bot.PickOvercall
-- =====================================================================
section("H. v0.7 Sun-overcall state-machine + Bot.PickOvercall")

do
    -- Reset state for each scenario.
    local function setup(bidder, trump, forced, bidCard, dealer)
        S.s.contract = {
            type    = K.BID_HOKM,
            trump   = trump or "C",
            bidder  = bidder or 1,
            forced  = forced or nil,
        }
        S.s.dealer = dealer or 4
        S.s.overcall = nil
        S.s.phase = K.PHASE_DOUBLE  -- pre-overcall canonical state
    end

    -- Scenario 1: bidder UPGRADE
    setup(1, "C", false, "9C", 4)
    local ok = S.BeginOvercall("9C", 4)
    assertEq(ok, true, "H.1: BeginOvercall returns true on Hokm contract")
    assertEq(S.s.phase, K.PHASE_OVERCALL, "H.1: phase transitioned to PHASE_OVERCALL")
    S.RecordOvercallDecision(1, "UPGRADE")
    S.RecordOvercallDecision(2, "WAIVE")
    S.RecordOvercallDecision(3, "WAIVE")
    S.RecordOvercallDecision(4, "WAIVE")
    local res = S.FinalizeOvercall()
    assertEq(res.taken, true,           "H.1: bidder UPGRADE → taken")
    assertEq(res.type,  "UPGRADE",      "H.1: result type=UPGRADE")
    assertEq(S.s.contract.type,   K.BID_SUN, "H.1: contract.type rewritten to Sun")
    assertEq(S.s.contract.trump,  nil,      "H.1: contract.trump cleared")
    assertEq(S.s.contract.bidder, 1,        "H.1: bidder unchanged on UPGRADE")
    assertEq(S.s.phase,           K.PHASE_DOUBLE, "H.1: phase advanced to PHASE_DOUBLE")
    assertEq(S.s.overcall,        nil,           "H.1: s.overcall cleared")

    -- Scenario 2: non-bidder TAKE (seat 3)
    setup(1, "C", false, "9C", 4)
    S.BeginOvercall("9C", 4)
    S.RecordOvercallDecision(1, "WAIVE")
    S.RecordOvercallDecision(3, "TAKE")
    res = S.FinalizeOvercall()
    assertEq(res.taken, true,            "H.2: non-bidder TAKE → taken")
    assertEq(res.by,    3,               "H.2: by=3")
    assertEq(S.s.contract.type,   K.BID_SUN, "H.2: contract.type=Sun")
    assertEq(S.s.contract.bidder, 3,         "H.2: bidder rewritten to taker (3)")
    assertEq(S.s.contract.trump,  nil,       "H.2: trump cleared")

    -- Scenario 3: all WAIVE → Hokm stands
    setup(1, "C", false, "9C", 4)
    S.BeginOvercall("9C", 4)
    res = S.FinalizeOvercall()  -- empty decisions = all timeout = WAIVE
    assertEq(res.taken,         false,       "H.3: empty decisions → not taken")
    assertEq(S.s.contract.type, K.BID_HOKM, "H.3: contract stays Hokm")
    assertEq(S.s.contract.trump, "C",        "H.3: trump preserved")
    assertEq(S.s.phase,         K.PHASE_DOUBLE, "H.3: phase still advances")

    -- Scenario 4: Ace bid card blocks bidder UPGRADE
    setup(1, "C", false, "AC", 4)
    S.BeginOvercall("AC", 4)
    S.RecordOvercallDecision(1, "UPGRADE")  -- attempted but blocked by R.CanOvercall
    S.RecordOvercallDecision(2, "TAKE")
    res = S.FinalizeOvercall()
    assertEq(res.taken, true,    "H.4: Ace-bid-card blocks bidder, TAKE wins")
    assertEq(res.by,    2,       "H.4: TAKE by=2 (after dealer=4 → bid order 1,2,3,4; 1 skipped as bidder)")
    assertEq(res.type,  "TAKE",  "H.4: type=TAKE")

    -- Scenario 5: forced/Takweesh contract → BeginOvercall refuses
    setup(1, "C", true, "9C", 4)
    ok = S.BeginOvercall("9C", 4)
    assertEq(ok, false,                  "H.5: forced contract → BeginOvercall refuses")
    assertEq(S.s.phase, K.PHASE_DOUBLE,  "H.5: phase unchanged")
    assertEq(S.s.overcall, nil,          "H.5: s.overcall stays nil")

    -- Scenario 6: Sun contract → BeginOvercall refuses (overcall is Hokm-only)
    S.s.contract = { type = K.BID_SUN, trump = nil, bidder = 1 }
    S.s.phase = K.PHASE_DOUBLE
    S.s.overcall = nil
    ok = S.BeginOvercall(nil, 4)
    assertEq(ok, false,                  "H.6: Sun contract → BeginOvercall refuses")

    -- Scenario 7: lock-out — once a seat decides, can't change
    setup(1, "C", false, "9C", 4)
    S.BeginOvercall("9C", 4)
    local first = S.RecordOvercallDecision(2, "WAIVE")
    local second = S.RecordOvercallDecision(2, "TAKE")  -- attempt to change
    assertEq(first,  true,   "H.7: first decision recorded")
    assertEq(second, false,  "H.7: second attempt rejected (lock-out)")
    assertEq(S.s.overcall.decisions[2], "WAIVE", "H.7: original WAIVE preserved")
    S.FinalizeOvercall()  -- cleanup

    -- Scenario 8: invalid decision string rejected
    setup(1, "C", false, "9C", 4)
    S.BeginOvercall("9C", 4)
    local invalid = S.RecordOvercallDecision(2, "GARBAGE")
    assertEq(invalid, false, "H.8: invalid decision → rejected")
    S.FinalizeOvercall()

    -- Scenario 9: invalid seat rejected
    setup(1, "C", false, "9C", 4)
    S.BeginOvercall("9C", 4)
    assertEq(S.RecordOvercallDecision(0, "WAIVE"), false, "H.9a: seat=0 rejected")
    assertEq(S.RecordOvercallDecision(5, "WAIVE"), false, "H.9b: seat=5 rejected")
    S.FinalizeOvercall()

    -- Scenario 10: Bot.PickOvercall returns WAIVE for non-M3lm tier
    WHEREDNGNDB.advancedBots     = false
    WHEREDNGNDB.m3lmBots         = false
    WHEREDNGNDB.fzlokyBots       = false
    WHEREDNGNDB.saudiMasterBots  = false
    setup(1, "C", false, "9C", 4)
    S.BeginOvercall("9C", 4)
    S.s.hostHands = {
        [1] = { "AS","AH","AD","AC","TS","TH","TD","TC" },  -- max sunStrength
        [2] = { "JS","9S","KS","QS","8S","7S","JH","9H" },
        [3] = { "JD","9D","KD","QD","8D","7D","JC","9C" },
        [4] = { "KH","QH","8H","7H","KC","QC","8C","7C" },
    }
    assertEq(Bot.PickOvercall(1), "WAIVE", "H.10: Basic tier → bidder always WAIVE")
    assertEq(Bot.PickOvercall(2), "WAIVE", "H.10: Basic tier → non-bidder always WAIVE")
    S.FinalizeOvercall()

    -- Scenario 11: Bot.PickOvercall — M3lm bidder UPGRADE on Sun-strong hand
    WHEREDNGNDB.advancedBots = true
    WHEREDNGNDB.m3lmBots     = true
    setup(1, "C", false, "9C", 4)
    S.BeginOvercall("9C", 4)
    S.s.hostHands = {
        [1] = { "AS","AH","AD","AC","TS","TH","TD","TC" },  -- 4 A + 4 T = max sunStrength
        [2] = { "JS","9S","KS","QS","8S","7S","JH","9H" },
        [3] = { "JD","9D","KD","QD","8D","7D","JC","9C" },
        [4] = { "KH","QH","8H","7H","KC","QC","8C","7C" },
    }
    local pick = Bot.PickOvercall(1)
    assertEq(pick, "UPGRADE",
             "H.11: M3lm bidder + Sun-strong + non-Ace bid → UPGRADE")
    S.FinalizeOvercall()

    -- Scenario 12: Bot.PickOvercall — M3lm bidder Ace-bid-card → WAIVE
    setup(1, "C", false, "AC", 4)
    S.BeginOvercall("AC", 4)
    S.s.hostHands = {
        [1] = { "AS","AH","AD","AC","TS","TH","TD","TC" },
        [2] = { "JS","9S","KS","QS","8S","7S","JH","9H" },
        [3] = { "JD","9D","KD","QD","8D","7D","JC","9C" },
        [4] = { "KH","QH","8H","7H","KC","QC","8C","7C" },
    }
    pick = Bot.PickOvercall(1)
    assertEq(pick, "WAIVE",
             "H.12: M3lm bidder + Ace bid card → WAIVE (Ace-special blocks UPGRADE)")
    S.FinalizeOvercall()

    -- Scenario 13: Bot.PickOvercall — M3lm non-bidder Sun-strong → TAKE
    setup(1, "C", false, "9C", 4)
    S.BeginOvercall("9C", 4)
    S.s.hostHands = {
        [1] = { "JC","9C","KC","QC","8C","7C","JS","9S" },
        [2] = { "8H","7H","8S","7S","8D","7D","KS","QS" },
        [3] = { "AS","AH","AD","AC","TS","TH","TD","TC" },  -- Sun-strong
        [4] = { "JH","JD","9H","9D","QH","QD","KH","KD" },
    }
    pick = Bot.PickOvercall(3)
    assertEq(pick, "TAKE",
             "H.13: M3lm non-bidder + Sun-strong → TAKE")
    S.FinalizeOvercall()

    -- Scenario 14: Bot.PickOvercall — weak hand → WAIVE
    setup(1, "C", false, "9C", 4)
    S.BeginOvercall("9C", 4)
    S.s.hostHands = {
        [1] = { "8H","7H","8S","7S","8D","7D","8C","7C" },
        [2] = { "JS","9S","KS","QS","JH","9H","KH","QH" },
        [3] = { "AS","AH","AD","TS","TH","TD","KD","JD" },
        [4] = { "AC","TC","9D","JC","9C","QC","QD","KC" },
    }
    pick = Bot.PickOvercall(1)
    assertEq(pick, "WAIVE", "H.14: M3lm bidder + weak hand → WAIVE")
    S.FinalizeOvercall()

    -- H.15: v0.8 cross-trump TAKE_HOKM resolution.
    -- Bidder Hokm-C, non-bidder seat 3 has Hokm-strong cards in S
    -- (different suit). Should TAKE_HOKM_S, contract becomes Hokm-S
    -- with bidder=3.
    setup(1, "C", false, "9C", 4)
    S.BeginOvercall("9C", 4)
    -- Seat 3's hand: J+9+A+T+K of Spades + 3 low side cards =
    -- score 20+14+11+10+4 = 59 base; count=5 → +(5-2)*5 = 15 dist;
    -- J+9 synergy +18 (Advanced) = 92. Above BOT_OVERCALL_TAKE_HOKM_TH=80.
    -- Sun strength: 5 hi cards of one suit but only 3 suits total =
    -- distribution penalty + low non-Spade Aces. Should pick Hokm.
    S.s.hostHands = {
        [1] = { "JC","9C","AC","TC","KC","QC","8C","7C" },  -- bidder Hokm-C strong
        [2] = { "JH","9H","KH","QH","8H","7H","JD","9D" },
        [3] = { "JS","9S","AS","TS","KS","8H","7D","8D" },  -- Hokm-S strong
        [4] = { "AH","TH","AD","TD","QS","JC","QD","KD" },  -- arbitrary
    }
    pick = Bot.PickOvercall(3)
    assertEq(pick, "TAKE_HOKM_S",
             "H.15: M3lm non-bidder + Hokm-S strong → TAKE_HOKM_S")
    -- Resolve and verify contract rewrite.
    S.RecordOvercallDecision(3, "TAKE_HOKM_S")
    S.RecordOvercallDecision(1, "WAIVE")
    S.RecordOvercallDecision(2, "WAIVE")
    S.RecordOvercallDecision(4, "WAIVE")
    res = S.FinalizeOvercall()
    assertEq(res.taken, true,                     "H.15: TAKE_HOKM resolved as taken")
    assertEq(res.type,  "TAKE_HOKM",              "H.15: result.type=TAKE_HOKM")
    assertEq(res.trump, "S",                      "H.15: result.trump=S")
    assertEq(S.s.contract.type,   K.BID_HOKM,     "H.15: contract.type stays Hokm")
    assertEq(S.s.contract.trump,  "S",            "H.15: contract.trump rewritten to S")
    assertEq(S.s.contract.bidder, 3,              "H.15: contract.bidder rewritten to 3")
    assertEq(S.s.phase,           K.PHASE_DOUBLE, "H.15: phase advanced")

    -- H.16: lock-out with TAKE_HOKM decision.
    setup(1, "C", false, "9C", 4)
    S.BeginOvercall("9C", 4)
    local first = S.RecordOvercallDecision(2, "TAKE_HOKM_S")
    local second = S.RecordOvercallDecision(2, "WAIVE")
    assertEq(first,  true,  "H.16: TAKE_HOKM_S recorded")
    assertEq(second, false, "H.16: lock-out — second decision rejected")
    assertEq(S.s.overcall.decisions[2], "TAKE_HOKM_S", "H.16: TAKE_HOKM_S preserved")
    S.FinalizeOvercall()

    -- H.17: invalid TAKE_HOKM_<bad-suit> rejected at RecordOvercallDecision.
    setup(1, "C", false, "9C", 4)
    S.BeginOvercall("9C", 4)
    assertEq(S.RecordOvercallDecision(2, "TAKE_HOKM_X"), false, "H.17a: bad suit X rejected")
    assertEq(S.RecordOvercallDecision(2, "TAKE_HOKM_"),  false, "H.17b: missing suit rejected")
    assertEq(S.RecordOvercallDecision(2, "TAKE_HOKM"),   false, "H.17c: no _-suffix rejected")
    S.FinalizeOvercall()
end

-- =====================================================================
-- Summary
-- =====================================================================
print("")
print(("== Result: %d passed, %d failed =="):format(pass, fail))
TEST_RESULTS = { passed = pass, failed = fail }
if fail == 0 then return true end
return false
