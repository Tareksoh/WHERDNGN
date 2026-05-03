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
-- Summary
-- =====================================================================
print("")
print(("== Result: %d passed, %d failed =="):format(pass, fail))
TEST_RESULTS = { passed = pass, failed = fail }
if fail == 0 then return true end
return false
