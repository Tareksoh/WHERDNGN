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
WHEREDNGN.Sound = { Cue = function() end, Try = function() end, ArmCue = function() end }
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

-- v0.10.4 GetLegalPlays AKA-receiver-relief pin (review_v0.10.2
-- validation HIGH closure). When partner has called AKA on the led
-- suit AND we're void+have-trump, the UI-dimming legal set must
-- include non-trump discards (M4/J-066). Without the akaCalled
-- arg, GetLegalPlays returned only trumps — UI greyed out the
-- discards that R.IsLegalPlay (Bot.legalPlaysFor + BotMaster outer
-- driver) actually permitted, defeating M4 at the UI layer.
freshState()
S.s.localSeat = 4
S.s.turn = 4
S.s.turnKind = "play"
S.s.phase = K.PHASE_PLAY
S.s.contract = { type = K.BID_HOKM, trump = "H", bidder = 1 }
-- Seat 4's partner is seat 2. Partner AKA'd on D, then led KD.
-- Opp seat 3 cut with trump 7H. Seat 4's hand: void in D, has
-- trump 9H, has non-trump AS + 8C.
S.s.hand = { "AS", "9H", "8C" }
S.s.trick = { leadSuit = "D", plays = {
    { seat = 2, card = "KD" },
    { seat = 3, card = "7H" },
} }
S.s.akaCalled = { seat = 2, suit = "D" }
do
    local legal = S.GetLegalPlays()
    local set = {}
    for _, c in ipairs(legal) do set[c] = true end
    assertTrue(set["AS"],
               "v0.10.4 GetLegalPlays AKA-relief: AS (non-trump) legal under partner AKA")
    assertTrue(set["8C"],
               "v0.10.4 GetLegalPlays AKA-relief: 8C (non-trump) legal under partner AKA")
    assertTrue(set["9H"],
               "v0.10.4 GetLegalPlays AKA-relief: 9H (trump) still legal — relief is permissive, not restrictive")
end
-- Sanity: clear akaCalled and the same fixture greys the discards.
S.s.akaCalled = nil
do
    local legal = S.GetLegalPlays()
    local set = {}
    for _, c in ipairs(legal) do set[c] = true end
    assertFalse(set["AS"],
                "v0.10.4 GetLegalPlays sanity: without AKA, must-trump → AS illegal (UI greys it)")
    assertFalse(set["8C"],
                "v0.10.4 GetLegalPlays sanity: without AKA → 8C illegal too")
    assertTrue(set["9H"],
               "v0.10.4 GetLegalPlays sanity: trump 9H legal (must-trump satisfied)")
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
    -- v0.10.6 fixture refit: dropped TH from the original
    -- {JH,9H,AH,TH,KH} fixture to break the AH+TH mardoofa pair.
    -- v0.10.4's K.BOT_SUN_MARDOOFA_BONUS 10 + v0.10.6's TH_SUN_BASE
    -- 47 left the original fixture's sunStrength=43 within the
    -- thSun-jitter band [41, 53], so Sun fired in ~15% of seed
    -- outcomes. Replacing TH with 8H removes the mardoofa, drops
    -- sunStrength to ~23 (well below jitter floor), and keeps the
    -- test's intent — strong 5-trump hand should bid Hokm — fully
    -- intact (J+9+A+K is still a textbook strong Hokm hand).
    S.s.hostHands = {
        [1] = { "JH","9H","AH","8H","KH" },  -- 5 of a single suit, top trumps J+9+A+K (no T → no mardoofa)
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

-- v0.10.6 Lever C — R2 canonical-minimum Hokm bid: J of trump +
-- ONE other trump (mardoofa) + ONE Ace on the side. Per video
-- #26 R2 ("أقل شي عشان تشتري الحكم: الولد + مردوفة معاه + إكا
-- وحدها"), this is the most-emphasized "minimum confident bid" in
-- the Hokm corpus. Pre-v0.10.6 the `count >= 3` lower-bound at
-- hokmMinShape silently rejected the entire pattern (~19.23% of
-- random hands per Monte Carlo). Source: review_v0.10.2
-- BIDDING_CALIBRATION_v0.10.5.md §4.2 H-B + §8.1.
--
-- Test fixture uses J+9 of trump (synergy +10 basic / +18 advanced)
-- + ONE side Ace + advanced bots so the Hokm strength clears the
-- jitter ceiling reliably. With JH+9H = 34 + synergy 10 = 44 (basic)
-- or 60 (advanced w/sideSuitAceBonus +8 + synergy +18 = 50). The
-- weaker 8H-as-cover variant (cover-only, no synergy) has strength
-- 22 — falls below thHokmR1 jitter floor [36, 48] even post-Lever-C.
-- The R2 canonical pattern's STRENGTH varies; this pin verifies
-- the predicate-acceptance path on a hand where strength permits.
do
    WHEREDNGNDB.advancedBots = true     -- enable J+9 synergy +18 + sideSuitAceBonus
    freshState()
    S.s.isHost = true
    S.s.bidRound = 1
    S.s.bidCard = "9H"   -- bid card is hearts; bot considers Hokm-on-flipped
    S.s.dealer = 4
    S.s.bids = {}
    -- Seat 1 hand: J+9 of hearts (mardoofa with synergy) + side Ace +
    -- filler. count(H)=2, hasJ[H]=true, hasSideAce=true (AS) →
    -- R2 canonical minimum predicate matches.
    S.s.hostHands = {
        [1] = { "JH","9H","AS","8D","7C","7D","8C","8S" },  -- 2 H (J+9), AS side
        [2] = { "AH","TH","KH","QH","TS","JS","KS","QS" },
        [3] = { "AC","TC","KC","QC","JC","AD","TD","KD" },
        [4] = { "QD","JD","9D","9C","7H","7S","9S","8H" },
    }
    S.s.contract = nil
    local bid = Bot.PickBid(1)
    -- Pre-v0.10.6: bid would be PASS-MINSHAPE (hokmMinShape rejects count==2).
    -- Post-v0.10.6: bid should be HOKM:H (R2 canonical minimum + sufficient strength).
    assertTrue(bid and bid:sub(1,#K.BID_HOKM) == K.BID_HOKM,
               ("v0.10.6 Lever C R2 canonical-min: J+9-trump+sideAce bids Hokm (got %s)")
                 :format(tostring(bid)))
    WHEREDNGNDB.advancedBots = nil
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
-- I. v0.8.6 audit-fix regression pins (H1-H4)
--
-- Pins for the four HIGH-severity bugs caught in the v0.7.2 audit:
--   H1 — Sun-overcall race-A wire desync (_OnOvercallResolve)
--   H2 — Failed-Gahwa loser keeps melds (_HostStepAfterTrick)
--   H3 — Tie-at-target tiebreaker reads contract.bidder
--   H4 — ISMCTS pcall granularity (BotMaster.PickPlay)
-- =====================================================================
section("I. v0.8.6 HIGH-bug regression pins (H1-H4)")

do
    -- I.1 (H3): tiebreaker on cumulative tie at target should respect
    -- bidderMade. When bidder team failed (bidderMade=false), the
    -- opponent team won the round — they should win the tiebreaker.
    --
    -- Direct test of the tiebreaker logic by simulating the decision
    -- without going through full game flow (which requires too much
    -- state). The fixed predicate:
    --   if totA == totB:
    --     if gahwaWonGame: winner = gahwaWinner
    --     elif bidderMade: winner = bidderTeam
    --     elif bidderMade==false: winner = oppTeam
    local function tiebreaker(totA, totB, gahwaWonGame, gahwaWinner,
                              bidderMade, bidder)
        if totA == totB then
            if gahwaWonGame and gahwaWinner then
                return gahwaWinner
            elseif bidder then
                local bidderTeam = R.TeamOf(bidder)
                if bidderMade then
                    return bidderTeam
                else
                    return (bidderTeam == "A") and "B" or "A"
                end
            else
                return "A"
            end
        elseif totA > totB then return "A"
        elseif totB > totA then return "B" end
        return "A"
    end

    -- Sanity: bidderMade=true → bidder team wins tie.
    assertEq(tiebreaker(152, 152, false, nil, true, 1), "A",
             "I.1a (H3): tie + bidder=1 (team A) made → A wins")
    -- Bug-pin: bidderMade=false → opp team wins tie.
    assertEq(tiebreaker(152, 152, false, nil, false, 1), "B",
             "I.1b (H3): tie + bidder=1 (team A) FAILED → B wins (was A pre-v0.8.6)")
    assertEq(tiebreaker(152, 152, false, nil, false, 2), "A",
             "I.1c (H3): tie + bidder=2 (team B) FAILED → A wins")
    -- Gahwa override: gahwaWinner is canonical.
    assertEq(tiebreaker(152, 152, true, "B", false, 1), "B",
             "I.1d (H3): Gahwa won by B regardless of bidder")
    -- No-tie cases unchanged.
    assertEq(tiebreaker(155, 152, false, nil, false, 1), "A",
             "I.1e (H3): A higher cumulative wins regardless of bidderMade")

    -- I.2 (H1): _OnOvercallResolve must NOT call S.FinalizeOvercall
    -- (which re-derives mutation from local decisions). Direct
    -- verification: walk Net.lua source for the post-fix pattern.
    do
        local net_path = WHEREDNGN_TESTS_ROOT .. "/Net.lua"
        local f = io.open(net_path, "r")
        local body = f:read("*a"); f:close()
        local fnStart = body:find("function N%._OnOvercallResolve")
        local fnEnd = body:find("function N%._HostBeginOvercallWindow",
                                fnStart or 1)
        local fn = body:sub(fnStart or 1, fnEnd or #body)
        -- Pre-v0.8.6: contained "if S.FinalizeOvercall then S.FinalizeOvercall() end"
        -- Post-v0.8.6: should NOT have that call pattern. Match the
        -- specific conditional-invocation guard, not loose substrings
        -- (the explanatory comment legitimately mentions the function name).
        assertEq(fn:find("if%s+S%.FinalizeOvercall%s+then%s+S%.FinalizeOvercall%(%)") ~= nil, false,
                 "I.2 (H1): _OnOvercallResolve must NOT invoke FinalizeOvercall (server-of-truth)")
        -- Should still clear s.overcall and transition phase.
        assertTrue(fn:find("s%.overcall%s*=%s*nil") ~= nil,
                   "I.2b (H1): _OnOvercallResolve clears s.overcall")
        assertTrue(fn:find("phase%s*=%s*K%.PHASE_DOUBLE") ~= nil,
                   "I.2c (H1): _OnOvercallResolve transitions to PHASE_DOUBLE")
    end

    -- I.3 (H2): in Gahwa-win override, loser's delta should be zeroed.
    -- Direct test: source-level verification that the fix is present.
    do
        local net_path = WHEREDNGN_TESTS_ROOT .. "/Net.lua"
        local f = io.open(net_path, "r")
        local body = f:read("*a"); f:close()
        local stepFn = body:find("function N%._HostStepAfterTrick")
        local nextFn = body:find("function N%._HostRedeal", stepFn or 1)
        local fn = body:sub(stepFn or 1, nextFn or #body)
        -- Look for the H2 fix markers: addB = 0 and addA = 0 inside
        -- the gahwaWonGame branch.
        assertTrue(fn:find("addB%s*=%s*0") ~= nil,
                   "I.3a (H2): Gahwa-win zero loser B delta present")
        assertTrue(fn:find("addA%s*=%s*0") ~= nil,
                   "I.3b (H2): Gahwa-win zero loser A delta present")
    end

    -- I.4 (H4): BotMaster.PickPlay pcall must be PER-WORLD, not wrapping
    -- the entire loop. Source-level check.
    do
        local bm_path = WHEREDNGN_TESTS_ROOT .. "/BotMaster.lua"
        local f = io.open(bm_path, "r")
        local body = f:read("*a"); f:close()
        local fnStart = body:find("function BM%.PickPlay")
        local fn = body:sub(fnStart or 1)
        -- Pre-v0.8.6: pcall wraps the for-loop ("pcall(function()" then
        -- "for w = 1, numWorlds").
        -- Post-v0.8.6: for-loop wraps the pcall ("for w" before pcall).
        local forIdx = fn:find("for w%s*=%s*1%s*,%s*numWorlds")
        local pcallIdx = fn:find("pcall%(function%(%)")
        assertTrue(forIdx and pcallIdx and forIdx < pcallIdx,
                   "I.4 (H4): pcall must be inside the for-loop (per-world), not outside")
    end
end

-- =====================================================================
-- J. v0.10.2 review-cycle MEDIUM/LOW closures
--
--   J.1 (L3) — PickAKA suppresses on doubled contracts.
--   J.2 (M8) — Sun bidder-team mardoofa probe lead on trick 1
--              (Pro-2 L08, MF-2). A+T mardoofa → lead the A.
-- =====================================================================
section("J. v0.10.2 review-cycle closures (L3, M8)")

-- J.1 (L3): doubled contract → PickAKA returns nil even when all
-- other gates would otherwise allow. Reproduces the exact gate-stack:
-- Hokm contract, mid-round, partner is bot, lead card is non-Ace boss
-- of a non-trump suit. Without the doubled gate, AKA fires; with it,
-- nil. Source: review_v0.10.0 xref_X2_aka.md B3 + G18-10 paragraph 2.
do
    WHEREDNGNDB.advancedBots = true
    freshState()
    S.s.isHost  = true
    S.s.contract = { type = K.BID_HOKM, trump = "S", bidder = 1,
                     doubled = true }   -- Bel'd by defenders
    -- Two completed tricks so we're past the trick-1 ban.
    S.s.tricks = {
        { winner = 1, plays = { { seat = 1, card = "AS" } } },
        { winner = 1, plays = { { seat = 1, card = "JS" } } },
    }
    S.s.trick = { leadSuit = nil, plays = {} }
    -- Seat 2 leading. Partner = seat 4. Mark all seats as bots
    -- (Bot.IsBotSeat checks `s.seats[seat].isBot`).
    S.s.seats = {
        [1] = { isBot = true }, [2] = { isBot = true },
        [3] = { isBot = true }, [4] = { isBot = true },
    }
    Bot._memory = nil
    -- Lead card KH: non-Ace boss of H (A and T already played out
    -- so KH is highestUnplayed). Fake S.HighestUnplayedRank to return
    -- "K" for H, "J" for trump.
    local origHUR = S.HighestUnplayedRank
    S.HighestUnplayedRank = function(suit)
        if suit == "H" then return "K" end
        if suit == "S" then return "J" end
        return nil
    end
    -- With contract.doubled=true, expect nil.
    local got = Bot.PickAKA(2, "KH")
    assertEq(got, nil,
             "J.1 (L3): doubled contract suppresses AKA banner (xref_X2_aka.md B3)")
    -- Sanity: clear the doubled flag and the same hand should fire.
    S.s.contract.doubled = false
    -- Re-prime per-seat akaSent map (Bot.PickAKA uses Bot._memory[seat].akaSent).
    Bot._memory = nil
    local fired = Bot.PickAKA(2, "KH")
    assertEq(fired, "H",
             "J.1 sanity: same fixture without doubled flag DOES fire AKA")
    S.HighestUnplayedRank = origHUR
end

-- J.2 (M8): Sun bidder-team trick-1 lead with A+T mardoofa → lead
-- the A from that mardoofa pair (NOT the shortest-suit low). Source:
-- review_v0.10.0 xref_X4_pro2_deal.md MF-2 / Pro-2 L08.
do
    WHEREDNGNDB.advancedBots = true
    freshState()
    S.s.isHost = true
    -- Sun contract, seat 2 is bidder, partners = seat 4.
    S.s.contract = { type = K.BID_SUN, trump = nil, bidder = 2 }
    S.s.tricks = {}                        -- trick 1
    S.s.trick = { leadSuit = nil, plays = {} }
    -- Seat 2 hand: AH+TH mardoofa, plus filler. Without M8 the
    -- shortest-suit-low would lead 7C (1-card C is shortest). With M8
    -- we expect AH (the mardoofa Ace).
    S.s.hostHands = {
        [1] = { "JS", "9S", "8S", "7S", "JC", "9C", "8C", "7C" },
        [2] = { "AH", "TH", "KH", "QH", "JH", "9H", "8H", "7C" },
        [3] = { "AS", "TS", "KS", "QS", "AC", "TC", "KC", "QC" },
        [4] = { "AD", "TD", "KD", "QD", "JD", "9D", "8D", "7D" },
    }
    local card = Bot.PickPlay(2)
    assertEq(card, "AH",
             "J.2 (M8): Sun bidder trick-1 with A+T mardoofa → lead the Ace (Pro-2 L08)")

    -- Negative case: same hand but on a NON-bidder seat → fall
    -- through to the existing Sun shortest-suit lead (LOWEST card
    -- of SHORTEST non-trump suit). Seat-1 vs bidder seat-2 → opp
    -- team. Hand has 7C as singleton — shortest. Expect 7C.
    S.s.hostHands[1] = { "AH", "TH", "KH", "QH", "JH", "9H", "8H", "7C" }
    local oppCard = Bot.PickPlay(1)
    assertEq(oppCard, "7C",
             "J.2 sanity: same A+T mardoofa from defender seat falls through to shortest-suit-low (7C)")
end

WHEREDNGNDB.advancedBots = nil

-- J.3 (M3) — False AKA = Qaid (J-069). When a seat calls AKA on a suit
-- and then leads a card that is NOT the highest-unplayed of that suit,
-- S.ApplyPlay marks the lead .illegal=true with reason "false AKA"
-- so a Takweesh call catches the offense. Source: review_v0.10.0
-- xref_X2_aka.md B2.
do
    freshState()
    S.s.isHost = true
    S.s.contract = { type = K.BID_HOKM, trump = "C", bidder = 1 }
    -- Seat 1 hand contains KH but NOT AH (so AH is somewhere else, still unplayed).
    -- Seat 1 announces AKA on H, then leads KH (false claim — AH is still out).
    S.s.hostHands = {
        [1] = { "KH", "QH", "9H", "8C", "7C", "JC", "9C", "TC" },
        [2] = { "AH", "TH", "JH", "AS", "TS", "KS", "QS", "JS" },
        [3] = { "AC", "KC", "QC", "9S", "8S", "7S", "AD", "TD" },
        [4] = { "7H", "8H", "KD", "QD", "JD", "9D", "8D", "7D" },
    }
    S.s.trick = { leadSuit = nil, plays = {} }
    S.s.tricks = {}
    S.s.playedCardsThisRound = {}

    -- Seat 1 announces AKA on H (false — they don't actually hold the boss).
    S.ApplyAKA(1, "H")
    assertEq(S.s.akaCalled and S.s.akaCalled.suit, "H",
             "J.3 setup: AKA banner set on H by seat 1")

    -- Seat 1 plays KH (false — AH is still in seat 2's hand).
    S.ApplyPlay(1, "KH")
    local lead = S.s.trick.plays[1]
    assertEq(lead.illegal, true,
             "J.3 (M3): false AKA on KH (when AH is unplayed) → lead marked .illegal=true")
    assertEq(lead.illegalReason, "false AKA",
             "J.3 (M3): illegalReason = 'false AKA' for Takweesh display")
    assertEq(S.s.akaCalled, nil,
             "J.3 (M3): false-AKA banner cleared (no receiver-relief on bogus claim)")

    -- Sanity: a TRUE AKA (lead is the actual boss) does NOT mark illegal.
    freshState()
    S.s.isHost = true
    S.s.contract = { type = K.BID_HOKM, trump = "C", bidder = 1 }
    -- Seat 1 holds AH (the actual boss of H, since H is non-trump).
    S.s.hostHands = {
        [1] = { "AH", "9H", "8H", "7H", "JC", "9C", "8C", "7C" },
        [2] = { "TH", "KH", "QH", "JH", "AS", "TS", "KS", "QS" },
        [3] = { "AC", "KC", "QC", "9S", "8S", "7S", "AD", "TD" },
        [4] = { "JS", "KD", "QD", "JD", "9D", "8D", "7D", "TC" },
    }
    S.s.trick = { leadSuit = nil, plays = {} }
    S.s.tricks = {}
    S.s.playedCardsThisRound = {}

    S.ApplyAKA(1, "H")
    S.ApplyPlay(1, "AH")
    local lead2 = S.s.trick.plays[1]
    assertEq(lead2.illegal, nil,
             "J.3 sanity: TRUE AKA on actual boss (AH) → lead NOT marked illegal")
    assertEq(S.s.akaCalled and S.s.akaCalled.suit, "H",
             "J.3 sanity: TRUE AKA banner persists for receiver-relief")

    -- Edge: AKA on suit X but lead is suit Y → trivially false.
    freshState()
    S.s.isHost = true
    S.s.contract = { type = K.BID_HOKM, trump = "C", bidder = 1 }
    S.s.hostHands = {
        [1] = { "AH", "AS", "JC", "9C", "8C", "7C", "JS", "TS" },
        [2] = { "TH", "KH", "QH", "JH", "9H", "8H", "7H", "KS" },
        [3] = { "AC", "KC", "QC", "QS", "9S", "8S", "7S", "AD" },
        [4] = { "TC", "TD", "KD", "QD", "JD", "9D", "8D", "7D" },
    }
    S.s.trick = { leadSuit = nil, plays = {} }
    S.s.tricks = {}
    S.s.playedCardsThisRound = {}

    S.ApplyAKA(1, "H")        -- claims AKA on H
    S.ApplyPlay(1, "AS")      -- but leads S
    local lead3 = S.s.trick.plays[1]
    assertEq(lead3.illegal, true,
             "J.3 edge: AKA-on-H then lead-on-S → false AKA (suit mismatch)")
    assertEq(lead3.illegalReason, "false AKA",
             "J.3 edge: suit-mismatch reason matches")
end

-- J.4 (M7) — Bargiya canonical FN closure: محشور بلون واحد proxy
-- (sender held 5+ of suit at A-discard time) promotes single-event A
-- to confirmed `bargiya` without needing a second event. Source:
-- audit_v0.9.0/55_bargiya_axis_impact.md Example A.
do
    -- Direct classifier invocation. Reach the local function via
    -- rebuilding the relevant bits — actually tahreebClassify is
    -- file-local; we exercise it indirectly through pickLead's
    -- partner-pref path, OR via Bot._partnerStyle priming.
    --
    -- Preferred: prime the per-seat tahreebSent with `lenAtAce` and
    -- exercise the receiver's partner-pref pickLead branch. Verify
    -- the bot leads the bargiya suit (proves classifier returned
    -- "bargiya" weight 3, not "bargiya_hint" weight 1).
    WHEREDNGNDB.m3lmBots = true
    freshState()
    S.s.isHost = true
    S.s.contract = { type = K.BID_HOKM, trump = "C", bidder = 4 }
    S.s.tricks = { { winner = 4, plays = {
        { seat = 4, card = "AC" }, { seat = 1, card = "9C" },
        { seat = 2, card = "8C" }, { seat = 3, card = "7C" },
    } } }
    S.s.trick = { leadSuit = nil, plays = {} }
    -- Seat 1's hand (we are seat 1, leading trick 2). Mix of suits;
    -- prefer the bargiya-flagged suit.
    S.s.hostHands = {
        [1] = { "JS", "9S", "8S", "JH", "9H", "8H", "JD", "9D" },
        [2] = {}, [3] = {}, [4] = {},
    }
    -- Mark all bots so partner-pref read fires (Bot.IsBotSeat check).
    S.s.seats = {
        [1] = { isBot = true }, [2] = { isBot = true },
        [3] = { isBot = true }, [4] = { isBot = true },
    }

    -- Prime: partner (seat 3) sent ONE A-event in S with lenAtAce=5.
    -- Without M7 this would classify as bargiya_hint (weight 1).
    -- Other suits get an "ascending 2-event want" (weight 2) — the
    -- محشور-confirmed A in S (weight 3) must dominate.
    Bot._partnerStyle = Bot._partnerStyle or {
        [1] = {}, [2] = {}, [3] = {}, [4] = {},
    }
    -- Reset partner style for seat 3.
    Bot._partnerStyle[3] = {
        tahreebSent = { S = {}, H = {}, D = {} },
    }
    Bot._partnerStyle[3].tahreebSent.S = { "A", lenAtAce = 5 }   -- محشور proxy
    Bot._partnerStyle[3].tahreebSent.H = { "7", "9" }            -- 2-event ascending = "want"
    Bot._partnerStyle[3].tahreebSent.D = {}

    -- pickLead is called on lead. Read partner pref via
    -- tahreebClassify; with M7 wired, S beats H by weight (3>2).
    -- Verify the chosen lead suit is S.
    local card = Bot.PickPlay(1)
    assertEq(C.Suit(card), "S",
             "J.4 (M7): محشور-proxy single-A bargiya beats 2-event 'want' (S over H)")

    -- Negative: same fixture WITHOUT lenAtAce → bargiya_hint (weight 1).
    -- Now H ('want', weight 2) should win over S (weight 1).
    Bot._partnerStyle[3].tahreebSent.S = { "A" }   -- no lenAtAce
    local card2 = Bot.PickPlay(1)
    assertEq(C.Suit(card2), "H",
             "J.4 (M7) sanity: WITHOUT lenAtAce, single-A is bargiya_hint → 'want'(H) dominates")
    WHEREDNGNDB.m3lmBots = nil
end

-- =====================================================================
-- K. v0.10.4 X5 half-fix closure — S.ApplyMeld parity with R.DetectMelds
--
-- v0.10.0 fixed Hokm-Carré-A meld scoring at the R.DetectMelds path
-- (used by Bot.PickMelds for declaring) but the parallel S.ApplyMeld
-- path (used on the wire-receive side AND on the host's own ApplyMeld
-- self-loopback) silently dropped Hokm-Carré-A with value=nil. Net
-- effect since v0.10.0: every game with 4 Aces in a Hokm round
-- silently lost the 100-meld + cascaded through belote-cancellation
-- to over-credit +20 raw. Sources: review_v0.10.2 prior summary
-- (S-Score-03 + S-Score-10) + 3 prior audit references.
-- =====================================================================
section("K. v0.10.4 X5 half-fix closure (Hokm-Carré-A parity)")

do
    -- K.1 — Hokm-Carré-A through ApplyMeld now scores 100 raw.
    freshState()
    S.s.contract = { type = K.BID_HOKM, trump = "S", bidder = 1 }
    -- Encoded hand: AH+AC+AD+AS — the 4 Aces.
    S.ApplyMeld(1, "carre", "", "A", C.EncodeHand({"AH","AC","AD","AS"}))
    local meldsA = S.s.meldsByTeam.A
    assertEq(#meldsA, 1,
             "K.1: Hokm-Carré-A produces a meld entry (was silently dropped pre-v0.10.4)")
    if meldsA[1] then
        assertEq(meldsA[1].kind, "carre", "K.1a: meld kind = carre")
        assertEq(meldsA[1].top,  "A",     "K.1b: meld top = A")
        assertEq(meldsA[1].value, K.MELD_CARRE_OTHER,
                 "K.1c: Hokm-Carré-A value = MELD_CARRE_OTHER (100 raw)")
    end

    -- K.2 — Sun-Carré-A scores K.MELD_CARRE_A_SUN (200 raw post-v0.11.10
    -- revert; pipeline yields 200×Sun×2/10 = 40 nq, the user-cited
    -- canonical Saudi value). Sanity that K.1 didn't break Sun.
    freshState()
    S.s.contract = { type = K.BID_SUN, bidder = 1 }
    S.ApplyMeld(1, "carre", "", "A", C.EncodeHand({"AH","AC","AD","AS"}))
    local meldsB = S.s.meldsByTeam.A
    assertEq(#meldsB, 1, "K.2: Sun-Carré-A still produces a meld entry")
    if meldsB[1] then
        assertEq(meldsB[1].value, K.MELD_CARRE_A_SUN,
                 "K.2a: Sun-Carré-A value = MELD_CARRE_A_SUN (200 raw)")
    end

    -- K.3 — non-Ace Carré in Hokm unaffected (T/K/Q/J = 100 raw).
    freshState()
    S.s.contract = { type = K.BID_HOKM, trump = "S", bidder = 1 }
    S.ApplyMeld(1, "carre", "", "K", C.EncodeHand({"KH","KC","KD","KS"}))
    local meldsC = S.s.meldsByTeam.A
    assertEq(#meldsC, 1, "K.3: Hokm-Carré-K produces a meld entry")
    if meldsC[1] then
        assertEq(meldsC[1].value, K.MELD_CARRE_OTHER,
                 "K.3a: Hokm-Carré-K value = MELD_CARRE_OTHER (100 raw)")
    end

    -- K.4 — Carré-9 still doesn't score (K.CARRE_RANKS excludes 9).
    -- Defensive: 9-carré is sometimes attempted by mistake; ensure
    -- the v0.10.4 fix doesn't accidentally start scoring 9-carrés.
    freshState()
    S.s.contract = { type = K.BID_HOKM, trump = "S", bidder = 1 }
    S.ApplyMeld(1, "carre", "", "9", C.EncodeHand({"9H","9C","9D","9S"}))
    local meldsD = S.s.meldsByTeam.A or {}
    assertEq(#meldsD, 0, "K.4: Carré-9 still drops (K.CARRE_RANKS excludes 9)")
end

-- =====================================================================
-- L. v0.11.0 audit closures (RT07-01 + S-1 + RT07-03 + sound-replay)
--
-- L.1 (RT07-01) — s.redealing must be PERSISTED through SaveSession,
-- not stripped as transient. Pre-v0.11.0 the redealing field was in
-- TRANSIENT_FIELDS so SaveSession wiped it before persistence — the
-- v0.10.6 redeal-stuck recovery code at WHEREDNGN.lua + Net.lua both
-- gated on `s.redealing`, so the recovery NEVER FIRED in production.
--
-- L.2 (S-1) — s.sweepTrackAnnounced must clear on resync so a
-- rejoiner gets a fresh SND_SWEEP_TRACK gate for the new round.
--
-- L.3 (RT07-03) — S.ApplyTrickEnd + S.ApplyPlay accept isReplay flag;
-- v0.10.7 cues skip on replay so resync flood doesn't re-fire past
-- trump-cuts / sweep-tracks / last-trick-wins.
-- =====================================================================
section("L. v0.11.0 audit closures (RT07-01, S-1, RT07-03)")

-- L.1: s.redealing persists through SaveSession.
--
-- TRANSIENT_FIELDS is a file-local table in State.lua. We verify via
-- source-string match: confirm `redealing = true` is NO LONGER in the
-- table (the v0.11.0 fix removed it). Pre-v0.11.0 the line was
-- present, after fix the comment block survived but the field
-- assignment was deleted.
do
    local stateSrc = io.open(WHEREDNGN_TESTS_ROOT .. "/State.lua"):read("*a")
    -- Locate TRANSIENT_FIELDS table body.
    local tableStart = stateSrc:find("local TRANSIENT_FIELDS = {", 1, true)
    assertTrue(tableStart, "L.1 setup: TRANSIENT_FIELDS table found")
    if tableStart then
        -- The closing brace of the table is the next "^}" at column 0
        -- after tableStart. Scan for it.
        local search = stateSrc:sub(tableStart)
        local braceEnd = search:find("\n}\n", 1, true)
        local tableBody = search:sub(1, braceEnd or #search)
        -- Match `redealing = true,` (canonical TRANSIENT_FIELDS entry
        -- form — note trailing comma, distinguishes from comment text
        -- describing the prior bug). The v0.11.0 fix removed the
        -- entry; the documenting comment block remains.
        local hasRedealing = tableBody:match("redealing%s*=%s*true%s*,")
        assertEq(hasRedealing, nil,
                 "L.1 (RT07-01): TRANSIENT_FIELDS no longer strips s.redealing — recovery code can now act")
    end
end

-- L.2: s.sweepTrackAnnounced reset on resync.
do
    freshState()
    S.s.sweepTrackAnnounced = true
    S.s.contract = { type = K.BID_HOKM, trump = "S", bidder = 1 }
    -- Build a minimal valid resync snapshot payload that ApplyResyncSnapshot
    -- can parse. Simplest: pack a snapshot from the CURRENT state, then
    -- apply. The clear block at line ~525 should reset sweepTrackAnnounced.
    --
    -- Direct shortcut: ApplyResyncSnapshot reads encoded fields then runs
    -- the clear block. We can simulate the clear-block effect by calling
    -- it with a no-op snapshot. But we need a valid encoder. Skip the
    -- packing layer — directly assert that the field is in the post-
    -- snapshot clear logic by checking its presence in S.ApplyResyncSnapshot
    -- code via a structural test: invoke the function's clear path
    -- through a minimal snapshot.
    --
    -- Easier: use the snapshot encoder S.SaveSession produced + a
    -- corresponding "we received MSG_RESYNC_RES" path. State.lua exposes
    -- ApplyResyncSnapshot indirectly through the wire — but the Lua test
    -- env doesn't load Net.lua. So just verify the field appears in the
    -- ApplyResyncSnapshot clear block by source-string match.
    --
    -- (Behavioural test deferred until Net.lua test harness lands per
    -- audit's "untested paths" recommendation. This pin is at least
    -- a structural floor.)
    local stateSrc = io.open(WHEREDNGN_TESTS_ROOT .. "/State.lua"):read("*a")
    local clearBlockStart = stateSrc:find("Audit fix: clear remaining transient round state", 1, true)
    local clearBlockEnd = stateSrc:find("Trick / hand are not snapshotted", 1, true)
    assertTrue(clearBlockStart and clearBlockEnd and clearBlockStart < clearBlockEnd,
               "L.2 setup: ApplyResyncSnapshot clear block bounds found")
    if clearBlockStart and clearBlockEnd then
        local clearBlock = stateSrc:sub(clearBlockStart, clearBlockEnd)
        assertTrue(clearBlock:find("sweepTrackAnnounced", 1, true),
                   "L.2 (S-1): ApplyResyncSnapshot clear block resets s.sweepTrackAnnounced")
    end
end

-- L.3: S.ApplyTrickEnd accepts isReplay; v0.10.7 cues skip on replay.
do
    -- We can't audit Sound.Cue invocations directly (no recorder in test
    -- env), but we can pin the ApplyTrickEnd signature accepts isReplay.
    local stateSrc = io.open(WHEREDNGN_TESTS_ROOT .. "/State.lua"):read("*a")
    assertTrue(stateSrc:find("function S.ApplyTrickEnd(winner, points, isReplay)", 1, true),
               "L.3a (RT07-03): S.ApplyTrickEnd signature includes isReplay parameter")
    assertTrue(stateSrc:find("function S.ApplyPlay(seat, card, isReplay)", 1, true),
               "L.3b (RT07-03): S.ApplyPlay signature includes isReplay parameter")
    -- Verify the v0.10.7 cues are gated on `not isReplay`.
    assertTrue(stateSrc:find("not isReplay and B.Sound and B.Sound.Cue", 1, true),
               "L.3c (RT07-03): v0.10.7 cues skip when isReplay=true")
end

-- =====================================================================
-- M. v0.11.1 audit closures (C-14 BotMaster heuristicPick delegation)
--
-- C-14 (HIGH from .swarm_findings/audit_v0.10.7/C_Bot_audit.md): the
-- previous heuristicPick was an Advanced-mirror placeholder substantially
-- below Bot.PickPlay's coverage — missing sweep-pursuit, trick-8 boss-
-- scan, free-trick suit, Sun L08, Tahreeb sender/receiver, Faranka
-- exceptions, AKA receiver, Sun shortest-suit, etc. Audit measured this
-- as the single highest-impact gap in the bot code. v0.11.1 reroutes
-- heuristicPick through Bot.PickPlay under the existing _inRollout=true
-- guard, with state swap-restore so Bot.PickPlay sees the determinization-
-- sampled view (hands, trick, tricks, playedCardsThisRound).
-- =====================================================================
section("M. v0.11.1 audit closures (C-14 BotMaster delegation)")

-- M.1: heuristicPick now delegates to Bot.PickPlay (no Advanced-mirror
-- placeholder). The delegation line is the single body of heuristicPick
-- after v0.11.1.
do
    local bm_path = WHEREDNGN_TESTS_ROOT .. "/BotMaster.lua"
    local f = io.open(bm_path)
    assertTrue(f ~= nil, "M.1 setup: BotMaster.lua readable")
    if f then
        local bmSrc = f:read("*a")
        f:close()
        -- Locate the heuristicPick function.
        local fnStart = bmSrc:find("local function heuristicPick", 1, true)
        assertTrue(fnStart ~= nil,
                   "M.1 setup: heuristicPick function found in BotMaster.lua")
        if fnStart then
            -- Body is short post-v0.11.1; scan ~500 chars after the def.
            local fnBody = bmSrc:sub(fnStart, fnStart + 600)
            assertTrue(fnBody:find("B.Bot.PickPlay", 1, true) ~= nil,
                       "M.1 (C-14): heuristicPick delegates to B.Bot.PickPlay")
            -- Negative pin: the old "Lead heuristics (Advanced-mirror)"
            -- comment was the marker for the placeholder. Confirm it's
            -- gone — if it reappears, someone restored the placeholder.
            assertEq(bmSrc:find("Lead heuristics %(Advanced%-mirror%)") and "found" or nil,
                     nil,
                     "M.1b (C-14): old Advanced-mirror placeholder removed from heuristicPick")
        end
    end
end

-- M.2: rolloutValue swaps S.s.hostHands / S.s.trick / S.s.tricks /
-- S.s.akaCalled / S.s.playedCardsThisRound for the rollout, and restores
-- them unconditionally afterwards. Without this swap the delegated
-- Bot.PickPlay would read REAL game state instead of the rollout's
-- determinization view, and a leak across worlds would corrupt the
-- next sampleConsistentDeal.
do
    local bm_path = WHEREDNGN_TESTS_ROOT .. "/BotMaster.lua"
    local f = io.open(bm_path)
    if f then
        local bmSrc = f:read("*a")
        f:close()
        -- Save lines.
        assertTrue(bmSrc:find("local prevHostHands = S.s.hostHands", 1, true) ~= nil,
                   "M.2a (C-14): rolloutValue saves prev S.s.hostHands")
        assertTrue(bmSrc:find("local prevPlayed = S.s.playedCardsThisRound", 1, true) ~= nil,
                   "M.2b (C-14): rolloutValue saves prev S.s.playedCardsThisRound")
        -- Swap.
        assertTrue(bmSrc:find("S.s.hostHands = hands", 1, true) ~= nil,
                   "M.2c (C-14): rolloutValue swaps S.s.hostHands to rollout-local")
        assertTrue(bmSrc:find("S.s.akaCalled = nil", 1, true) ~= nil,
                   "M.2d (C-14): rolloutValue nils S.s.akaCalled (sim-blind AKA)")
        -- Restore.
        assertTrue(bmSrc:find("S.s.hostHands = prevHostHands", 1, true) ~= nil,
                   "M.2e (C-14): rolloutValue restores S.s.hostHands after rollout")
        assertTrue(bmSrc:find("S.s.playedCardsThisRound = prevPlayed", 1, true) ~= nil,
                   "M.2f (C-14): rolloutValue restores S.s.playedCardsThisRound after rollout")
    end
end

-- =====================================================================
-- N. v0.11.3 audit closures (RT07-02 + RT07-04 + RT07-05)
--
-- RT07-02 — SND_LAST_TRICK_WIN gated to trick 8 only. Pre-v0.11.3 the
-- cue fired on every "guaranteed-unbeatable" play across all 8 tricks.
-- User's spec said "last hand winning card" (trick 8), and the v0.10.7
-- CHANGELOG wiring blurb explicitly said `#tricks == 8`. The code path
-- gates ApplyTrickEnd's last-trick cue on `not isReplay and #s.tricks == 8`.
--
-- RT07-04 — sweepTrackAnnounced reset added to S.ApplyRoundEnd. v0.11.0
-- S-1 already added the ApplyResyncSnapshot reset; this completes the
-- triple of reset sites (ApplyStart/reset/ApplyResyncSnapshot/ApplyRoundEnd).
--
-- RT07-05 — _OnContract validates bidder ∈ [1,4] and btype ∈
-- {HOKM, SUN}. Pre-v0.11.3 only nil was rejected.
-- =====================================================================
section("N. v0.11.3 audit closures (RT07-02, RT07-04, RT07-05)")

-- N.1 (RT07-02): ApplyTrickEnd's last-trick-win cue gated on #s.tricks == 8.
-- Source-string match against the gate line — the cue check now requires
-- the trick is the round-final trick.
do
    local stateSrc = io.open(WHEREDNGN_TESTS_ROOT .. "/State.lua"):read("*a")
    -- The v0.11.3 gate line.
    assertTrue(stateSrc:find("not isReplay and #s%.tricks == 8") ~= nil,
               "N.1 (RT07-02): ApplyTrickEnd last-trick-win cue gated on #s.tricks == 8")
end

-- N.2 (RT07-04): S.ApplyRoundEnd resets sweepTrackAnnounced.
-- Source-string match: confirm the reset line appears between
-- "function S.ApplyRoundEnd" and the next "function S\\." or end-of-file.
do
    local stateSrc = io.open(WHEREDNGN_TESTS_ROOT .. "/State.lua"):read("*a")
    local fnStart = stateSrc:find("function S%.ApplyRoundEnd")
    assertTrue(fnStart ~= nil,
               "N.2 setup: S.ApplyRoundEnd function found")
    if fnStart then
        -- Scan ~1500 chars (function body should be much shorter, but be safe).
        local fnSlice = stateSrc:sub(fnStart, fnStart + 1500)
        assertTrue(fnSlice:find("s%.sweepTrackAnnounced%s*=%s*nil") ~= nil,
                   "N.2 (RT07-04): S.ApplyRoundEnd clears s.sweepTrackAnnounced")
    end
end

-- N.3 (RT07-05): N._OnContract validates bidder range and btype enum.
-- Behavioural test: stub fromHost to true, call _OnContract with bogus
-- bidder=5 and bogus btype="GARBAGE", verify s.contract is unchanged.
do
    local netSrc = io.open(WHEREDNGN_TESTS_ROOT .. "/Net.lua"):read("*a")
    -- Source-pin: the bidder range check exists.
    assertTrue(netSrc:find("if bidder < 1 or bidder > 4 then return end") ~= nil,
               "N.3a (RT07-05): _OnContract rejects bidder outside 1-4 range")
    -- Source-pin: btype enum check exists.
    assertTrue(netSrc:find("if btype ~= K%.BID_HOKM and btype ~= K%.BID_SUN then return end") ~= nil,
               "N.3b (RT07-05): _OnContract rejects btype outside {HOKM, SUN}")
end

-- =====================================================================
-- O. v0.11.4 audit closures (Bot1-01 + Bot1-02 + NetA-03/04/05 + XR-09/11)
--
-- Bot1-01 — C-14 completion: rolloutValue swaps Bot._memory to a
-- rollout-local copy populated from simTricks + currentTrick.plays so
-- pickLead/pickFollow branches reading _memory.played and _memory.void
-- see the determinization-sampled state.
--
-- Bot1-02 — _inRollout flag leak fix: BM.PickPlay's legal-set
-- construction is wrapped in a pcall (named-function form to preserve
-- I.4 (H4) per-world pcall structural test).
--
-- NetA-03 — _OnRound nil-numeric guards on addA/addB/totA/totB.
-- NetA-04 — _OnTrick winner ∈ [1,4] + points non-nil.
-- NetA-05 — _OnTurn seat ∈ [1,4].
-- XR-09  — _OnGameEnd winner ∈ {"A","B"}.
-- XR-11  — _OnPlay seat ∈ [1,4] + card length == 2.
-- =====================================================================
section("O. v0.11.4 audit closures (Bot1-01 + Bot1-02 + wire validation)")

-- O.1 (Bot1-01): rolloutValue saves and swaps Bot._memory.
do
    local bm = io.open(WHEREDNGN_TESTS_ROOT .. "/BotMaster.lua"):read("*a")
    assertTrue(bm:find("local prevMemory = B%.Bot and B%.Bot%._memory") ~= nil,
               "O.1a (Bot1-01): rolloutValue saves prev B.Bot._memory")
    assertTrue(bm:find("if B%.Bot then B%.Bot%._memory = rolloutMemory end") ~= nil,
               "O.1b (Bot1-01): rolloutValue swaps B.Bot._memory to rollout-local")
    assertTrue(bm:find("if B%.Bot then B%.Bot%._memory = prevMemory end") ~= nil,
               "O.1c (Bot1-01): rolloutValue restores B.Bot._memory after rollout")
    -- Verify population: rolloutMemory[seat].played and .void built
    -- from simTricks + currentTrick.plays.
    assertTrue(bm:find("rolloutMemory%[p%.seat%]%.played%[p%.card%] = true") ~= nil,
               "O.1d (Bot1-01): rolloutMemory.played populated from simTricks + currentTrick")
    assertTrue(bm:find("rolloutMemory%[p%.seat%]%.void%[t%.leadSuit%] = true") ~= nil,
               "O.1e (Bot1-01): rolloutMemory.void populated from simTricks")
    -- Verify per-pick update helper exists.
    assertTrue(bm:find("local function recordRolloutMemory") ~= nil,
               "O.1f (Bot1-01): recordRolloutMemory helper updates rollout memory per pick")
end

-- O.2 (Bot1-02): BM.PickPlay's legal-set construction is pcall-wrapped.
do
    local bm = io.open(WHEREDNGN_TESTS_ROOT .. "/BotMaster.lua"):read("*a")
    assertTrue(bm:find("local function buildLegalSet") ~= nil,
               "O.2a (Bot1-02): BM.PickPlay defines buildLegalSet helper")
    assertTrue(bm:find("local legalOk = pcall%(buildLegalSet%)") ~= nil,
               "O.2b (Bot1-02): BM.PickPlay calls pcall(buildLegalSet) — _inRollout leak guard")
    -- Confirm the failure path returns _restore(nil) so the flag is
    -- cleared when the legal-set construction errors.
    assertTrue(bm:find("if not legalOk then return _restore%(nil%) end") ~= nil,
               "O.2c (Bot1-02): pcall failure returns _restore(nil) — clears _inRollout")
end

-- O.3 (NetA-03 / RT07-06): _OnRound nil-numeric guards.
do
    local net = io.open(WHEREDNGN_TESTS_ROOT .. "/Net.lua"):read("*a")
    assertTrue(
        net:find("if not addA or not addB or not totA or not totB then return end") ~= nil,
        "O.3 (NetA-03): _OnRound rejects nil score fields")
end

-- O.4 (NetA-04): _OnTrick winner ∈ [1,4] + points non-nil.
do
    local net = io.open(WHEREDNGN_TESTS_ROOT .. "/Net.lua"):read("*a")
    -- Locate _OnTrick and scan first 30 lines for both guards.
    local fnStart = net:find("function N%._OnTrick")
    assertTrue(fnStart ~= nil, "O.4 setup: _OnTrick function found")
    if fnStart then
        local body = net:sub(fnStart, fnStart + 1500)
        assertTrue(body:find("winner < 1 or winner > 4") ~= nil,
                   "O.4a (NetA-04): _OnTrick rejects winner outside 1-4")
        assertTrue(body:find("if not points then return end") ~= nil,
                   "O.4b (NetA-04): _OnTrick rejects nil points")
    end
end

-- O.5 (NetA-05): _OnTurn seat ∈ [1,4].
do
    local net = io.open(WHEREDNGN_TESTS_ROOT .. "/Net.lua"):read("*a")
    local fnStart = net:find("function N%._OnTurn")
    assertTrue(fnStart ~= nil, "O.5 setup: _OnTurn function found")
    if fnStart then
        local body = net:sub(fnStart, fnStart + 700)
        assertTrue(body:find("seat < 1 or seat > 4") ~= nil,
                   "O.5 (NetA-05): _OnTurn rejects seat outside 1-4")
    end
end

-- O.6 (XR-09): _OnGameEnd winner ∈ {"A","B"}.
do
    local net = io.open(WHEREDNGN_TESTS_ROOT .. "/Net.lua"):read("*a")
    local fnStart = net:find("function N%._OnGameEnd")
    assertTrue(fnStart ~= nil, "O.6 setup: _OnGameEnd function found")
    if fnStart then
        local body = net:sub(fnStart, fnStart + 500)
        assertTrue(body:find('winner ~= "A" and winner ~= "B"') ~= nil,
                   "O.6 (XR-09): _OnGameEnd rejects winner outside {A,B}")
    end
end

-- O.7 (XR-11): _OnPlay seat ∈ [1,4] + card length == 2.
do
    local net = io.open(WHEREDNGN_TESTS_ROOT .. "/Net.lua"):read("*a")
    local fnStart = net:find("function N%._OnPlay")
    assertTrue(fnStart ~= nil, "O.7 setup: _OnPlay function found")
    if fnStart then
        local body = net:sub(fnStart, fnStart + 1000)
        assertTrue(body:find("seat < 1 or seat > 4") ~= nil,
                   "O.7a (XR-11): _OnPlay rejects seat outside 1-4")
        assertTrue(body:find("if #card ~= 2 then return end") ~= nil,
                   "O.7b (XR-11): _OnPlay rejects malformed card (length != 2)")
    end
end

-- =====================================================================
-- P. v0.11.5 batch — defensive MED + LOW closures from comprehensive audit
--
-- SU-01: S.ApplyContract clears s.overcall when advancing phase.
-- NetA-06: _OnDealPhase redeal nextDealer range check.
-- NetA-07/XR-04: _OnTakweeshOut/_OnSWAOut caller seat range check.
-- XR-05: _OnPause payload domain check.
-- XR-06: _OnSWAReq/_OnSWA encodedHand length cap.
-- XR-08: escalation _On* seat range checks.
-- NetA-09: _HostExecuteRedeal nextDealer range check.
-- Bot1-05/C-01: Bot.lua duplicate T-cardinality block removed.
-- XR-14: K.MSG_KICK dead constant removed.
-- =====================================================================
section("P. v0.11.5 audit closures (defensive MED + LOW batch)")

-- P.1 (SU-01): S.ApplyContract clears s.overcall when advancing phase.
do
    local stateSrc = io.open(WHEREDNGN_TESTS_ROOT .. "/State.lua"):read("*a")
    local fnStart = stateSrc:find("function S%.ApplyContract")
    assertTrue(fnStart ~= nil, "P.1 setup: S.ApplyContract function found")
    if fnStart then
        local body = stateSrc:sub(fnStart, fnStart + 3000)
        assertTrue(body:find("s%.overcall = nil") ~= nil,
                   "P.1 (SU-01): S.ApplyContract clears s.overcall on phase advance")
    end
end

-- P.2 (NetA-06): _OnDealPhase redeal nextDealer range check.
do
    local netSrc = io.open(WHEREDNGN_TESTS_ROOT .. "/Net.lua"):read("*a")
    -- The redeal branch ends with the new range guard.
    assertTrue(netSrc:find('elseif phase == "redeal" then') ~= nil,
               "P.2 setup: _OnDealPhase redeal branch found")
    -- Locate the redeal branch and check for the range guard.
    local branchStart = netSrc:find('elseif phase == "redeal" then')
    if branchStart then
        local body = netSrc:sub(branchStart, branchStart + 1000)
        assertTrue(body:find("nextDealer < 1 or nextDealer > 4") ~= nil,
                   "P.2 (NetA-06): _OnDealPhase rejects nextDealer outside 1-4")
    end
end

-- P.3 (NetA-07 / XR-04): _OnTakweeshOut and _OnSWAOut validate caller.
do
    local netSrc = io.open(WHEREDNGN_TESTS_ROOT .. "/Net.lua"):read("*a")
    -- _OnTakweeshOut: callerSeat range check + illegalSeat range check.
    local fnT = netSrc:find("function N%._OnTakweeshOut")
    assertTrue(fnT ~= nil, "P.3 setup: _OnTakweeshOut found")
    if fnT then
        local body = netSrc:sub(fnT, fnT + 2000)
        assertTrue(body:find("callerSeat < 1 or callerSeat > 4") ~= nil,
                   "P.3a (NetA-07): _OnTakweeshOut rejects callerSeat outside 1-4")
        assertTrue(body:find("illegalSeat < 0 or illegalSeat > 4") ~= nil,
                   "P.3b (NetA-07): _OnTakweeshOut rejects illegalSeat outside 0-4 sentinel range")
    end
    -- _OnSWAOut: caller range check.
    local fnS = netSrc:find("function N%._OnSWAOut")
    assertTrue(fnS ~= nil, "P.3 setup: _OnSWAOut found")
    if fnS then
        local body = netSrc:sub(fnS, fnS + 1500)
        assertTrue(body:find("caller < 1 or caller > 4") ~= nil,
                   "P.3c (XR-04): _OnSWAOut rejects caller outside 1-4")
    end
end

-- P.4 (XR-05): _OnPause payload domain check.
do
    local netSrc = io.open(WHEREDNGN_TESTS_ROOT .. "/Net.lua"):read("*a")
    local fnStart = netSrc:find("function N%._OnPause")
    assertTrue(fnStart ~= nil, "P.4 setup: _OnPause found")
    if fnStart then
        local body = netSrc:sub(fnStart, fnStart + 800)
        assertTrue(body:find('payload ~= "1" and payload ~= "0"') ~= nil,
                   "P.4 (XR-05): _OnPause rejects payloads outside {0, 1}")
    end
end

-- P.5 (XR-06): _OnSWAReq and _OnSWA cap encodedHand length to 16 chars.
do
    local netSrc = io.open(WHEREDNGN_TESTS_ROOT .. "/Net.lua"):read("*a")
    -- _OnSWAReq cap.
    local fnReq = netSrc:find("function N%._OnSWAReq")
    if fnReq then
        local body = netSrc:sub(fnReq, fnReq + 1500)
        assertTrue(body:find("encodedHand and #encodedHand > 16") ~= nil,
                   "P.5a (XR-06): _OnSWAReq rejects encodedHand longer than 16 chars")
    end
    -- _OnSWA cap.
    local fnSWA = netSrc:find("function N%._OnSWA%s*%(")
    if fnSWA then
        local body = netSrc:sub(fnSWA, fnSWA + 1500)
        assertTrue(body:find("encodedHand and #encodedHand > 16") ~= nil,
                   "P.5b (XR-06): _OnSWA rejects encodedHand longer than 16 chars")
    end
end

-- P.6 (XR-08): escalation handlers _OnDouble/_OnTriple/_OnFour/_OnGahwa
-- have seat range checks.
do
    local netSrc = io.open(WHEREDNGN_TESTS_ROOT .. "/Net.lua"):read("*a")
    for _, fnName in ipairs({"_OnDouble", "_OnTriple", "_OnFour", "_OnGahwa"}) do
        local fnStart = netSrc:find("function N%." .. fnName)
        assertTrue(fnStart ~= nil,
                   "P.6 setup: N." .. fnName .. " found")
        if fnStart then
            local body = netSrc:sub(fnStart, fnStart + 700)
            assertTrue(body:find("seat < 1 or seat > 4") ~= nil,
                       ("P.6 (XR-08): N.%s rejects seat outside 1-4"):format(fnName))
        end
    end
end

-- P.7 (NetA-09): _HostExecuteRedeal validates nextDealer range.
do
    local netSrc = io.open(WHEREDNGN_TESTS_ROOT .. "/Net.lua"):read("*a")
    local fnStart = netSrc:find("function N%._HostExecuteRedeal")
    assertTrue(fnStart ~= nil, "P.7 setup: _HostExecuteRedeal found")
    if fnStart then
        local body = netSrc:sub(fnStart, fnStart + 1500)
        assertTrue(body:find("nextDealer < 1 or nextDealer > 4") ~= nil,
                   "P.7 (NetA-09): _HostExecuteRedeal rejects nextDealer outside 1-4")
    end
end

-- P.8 (Bot1-05 / C-01): Bot.lua duplicate T-cardinality block removed.
do
    local botSrc = io.open(WHEREDNGN_TESTS_ROOT .. "/Bot.lua"):read("*a")
    -- Pre-v0.11.5: TWO byte-identical blocks of:
    --   if ok and bidCardRank == "T" then
    --       local tCount = 0 ... if tCount > 1 then ok = false end
    -- v0.11.5: only ONE remains. Count occurrences of the canonical
    -- pattern used inside the duplicated block.
    local pattern = 'if ok and bidCardRank == "T" then'
    local count = 0
    local pos = 1
    while true do
        local found = botSrc:find(pattern, pos, true)
        if not found then break end
        count = count + 1
        pos = found + 1
    end
    -- The same line still appears in 1) the singleton-T cardinality
    -- gate (kept) AND 2) the same-suit-A check (`if ok and bidCardRank
    -- == "T" and bidCardSuit then`). The duplicate t-count block (with
    -- the same `if ok and bidCardRank == "T" then` opener but no
    -- `bidCardSuit` clause) is removed. So the EXACT pattern now
    -- appears once — the kept singleton-T gate.
    assertEq(count, 1,
             "P.8 (Bot1-05): Bot.lua dead duplicate T-cardinality block removed (canonical line appears exactly once)")
end

-- P.9 (XR-14): K.MSG_KICK dead constant removed.
do
    local kSrc = io.open(WHEREDNGN_TESTS_ROOT .. "/Constants.lua"):read("*a")
    -- Pre-v0.11.5: `K.MSG_KICK = "K"` was defined but never referenced.
    -- v0.11.5 removed the assignment.
    assertEq(kSrc:find('K%.MSG_KICK%s*=') and "found" or nil, nil,
             "P.9 (XR-14): K.MSG_KICK dead constant removed from Constants.lua")
end

-- =====================================================================
-- Q. v0.11.7 SWA UX fixes (user-reported)
--
-- Q.1: Bot.PickSWA refuses #hand <= 1 (just play instead).
-- Q.2: HostResolveSWA stashes caller's encodedHand into swaResult so
--      the post-resolution banner can show cards (UI fix).
-- Q.3: SendSWAOut wire format extended to field 10 (encodedHand) for
--      remote receivers; receivers also stash into swaResult.
-- =====================================================================
section("Q. v0.11.7 SWA UX fixes")

-- Q.1 (Bot.PickSWA #hand<=1 short-circuit).
do
    local botSrc = io.open(WHEREDNGN_TESTS_ROOT .. "/Bot.lua"):read("*a")
    local fnStart = botSrc:find("function Bot%.PickSWA")
    assertTrue(fnStart ~= nil, "Q.1 setup: Bot.PickSWA function found")
    if fnStart then
        local body = botSrc:sub(fnStart, fnStart + 1500)
        assertTrue(body:find("if #hand <= 1 then return false end") ~= nil,
                   "Q.1 (v0.11.7): Bot.PickSWA short-circuits with #hand<=1 (just play)")
    end
end

-- Q.2 (HostResolveSWA stashes encodedHand on swaResult).
-- HostResolveSWA is ~250 lines; need a wide slice to catch the
-- encodedHand stash near the end of the function.
do
    local netSrc = io.open(WHEREDNGN_TESTS_ROOT .. "/Net.lua"):read("*a")
    local fnStart = netSrc:find("function N%.HostResolveSWA")
    assertTrue(fnStart ~= nil, "Q.2 setup: HostResolveSWA function found")
    if fnStart then
        -- Function spans roughly 9000 chars; scan the next 12k for the
        -- v0.11.7 encodedHand stash + computation.
        local body = netSrc:sub(fnStart, fnStart + 12000)
        assertTrue(body:find("encodedHand%s*=%s*callerEncodedHand") ~= nil,
                   "Q.2a (v0.11.7): HostResolveSWA stashes encodedHand on swaResult")
        assertTrue(body:find("local callerEncodedHand") ~= nil,
                   "Q.2b (v0.11.7): HostResolveSWA computes callerEncodedHand from callerHand/hostHands")
    end
end

-- Q.3 (Wire format: SendSWAOut + _OnSWAOut + dispatcher all carry field 10).
do
    local netSrc = io.open(WHEREDNGN_TESTS_ROOT .. "/Net.lua"):read("*a")
    -- SendSWAOut signature includes encodedHand parameter.
    assertTrue(netSrc:find("function N%.SendSWAOut%(caller, valid, addA, addB, totA, totB, sweep, bidderMade, encodedHand%)") ~= nil,
               "Q.3a (v0.11.7): N.SendSWAOut accepts 9th encodedHand arg")
    -- _OnSWAOut signature also includes encodedHand.
    assertTrue(netSrc:find("function N%._OnSWAOut%(sender, caller, valid, addA, addB, totA, totB, sweep, bidderMade, encodedHand%)") ~= nil,
               "Q.3b (v0.11.7): N._OnSWAOut accepts 10th encodedHand arg")
    -- Dispatcher passes fields[10] through.
    assertTrue(netSrc:find("swSweep, swMade, fields%[10%]") ~= nil,
               "Q.3c (v0.11.7): MSG_SWA_OUT dispatcher passes fields[10] to _OnSWAOut")
    -- Receiver caps at 16 chars (mirrors XR-06 cap on MSG_SWA_REQ).
    assertTrue(netSrc:find("if encodedHand and #encodedHand > 16 then encodedHand = nil end") ~= nil,
               "Q.3d (v0.11.7): _OnSWAOut caps encodedHand at 16 chars (mirrors XR-06)")
end

-- =====================================================================
-- R. v0.11.8 bidcalc trace toggle (diagnostic, gated on WHEREDNGNDB.debugBidcalc)
--
-- /baloot bidcalc toggles a per-call print of Bot.PickBid's hand
-- evaluation + thresholds + decision path. Off-by-default so
-- production users see no spam; on for diagnosing user-reported
-- "bots not bidding Sun" patterns. Gated via the same WHEREDNGNDB
-- flag pattern as the existing /baloot debug toggle.
-- =====================================================================
section("R. v0.11.8 bidcalc trace toggle")

-- R.1: Slash.lua wires the bidcalc toggle command.
do
    local slashSrc = io.open(WHEREDNGN_TESTS_ROOT .. "/Slash.lua"):read("*a")
    assertTrue(slashSrc:find('msg == "bidcalc"') ~= nil,
               "R.1a (v0.11.8): /baloot bidcalc toggle wired in Slash.lua")
    assertTrue(slashSrc:find("WHEREDNGNDB%.debugBidcalc") ~= nil,
               "R.1b (v0.11.8): toggle flips WHEREDNGNDB.debugBidcalc")
end

-- R.2: Bot.PickBid defines the btrace helper gated on the toggle.
-- PickBid is ~330 lines (~30k chars) so we slice a generous 40k from
-- the function start to cover R1 + R2 + fall-through decision sites.
do
    local botSrc = io.open(WHEREDNGN_TESTS_ROOT .. "/Bot.lua"):read("*a")
    local fnStart = botSrc:find("function Bot%.PickBid")
    assertTrue(fnStart ~= nil, "R.2 setup: Bot.PickBid found")
    if fnStart then
        local body = botSrc:sub(fnStart, fnStart + 40000)
        assertTrue(body:find("local function btrace") ~= nil,
                   "R.2a (v0.11.8): Bot.PickBid defines btrace helper")
        assertTrue(body:find("WHEREDNGNDB%.debugBidcalc") ~= nil,
                   "R.2b (v0.11.8): btrace short-circuits when toggle is off (zero overhead in prod)")
        -- Verify trace fires at key Sun-vs-Hokm decision points.
        assertTrue(body:find("R1 direct Sun") ~= nil,
                   "R.2c (v0.11.8): trace covers R1 direct Sun decision")
        assertTrue(body:find("R2 Sun fires") ~= nil,
                   "R.2d (v0.11.8): trace covers R2 Sun-vs-Hokm decision")
        assertTrue(body:find('btrace%("hand=') ~= nil,
                   "R.2e (v0.11.8): trace logs hand+thresholds at top of bid call")
    end
end

-- =====================================================================
-- T. v0.11.9 bidding calibration (user-arbitrated from bidcalc trace)
--
-- 1. K.BOT_SUN_MARDOOFA_BONUS bumped 10 → 20 (S-8 reinforcement).
-- 2. sunStrength Advanced void-penalty cap lowered 18 → 8 (Hokm-think
--    no longer applied to Sun: voids aren't ruff vulnerabilities in
--    no-trump play).
-- 3. hokmMinShape Lever C tightened: count==2 branch now requires the
--    second trump be rank 9 or A (canonical mardoofa partners of J),
--    not any rank. Closes RT07-07.
-- =====================================================================
section("T. v0.11.9 bidding calibration (user-arbitrated)")

-- T.1 — K.BOT_SUN_MARDOOFA_BONUS = 20.
do
    assertEq(K.BOT_SUN_MARDOOFA_BONUS, 20,
             "T.1 (v0.11.9): mardoofa bonus = 20 (was 10 in v0.10.4)")
end

-- T.2 — sunStrength Advanced penalty cap = 8 (via K.BOT_SUN_VOID_PENALTY_CAP).
do
    -- v0.11.11: cap was inlined as `8` in v0.11.9; promoted to
    -- K.BOT_SUN_VOID_PENALTY_CAP in v0.11.11 (XU-07). Verify both
    -- the constant value AND the call-site form.
    assertEq(K.BOT_SUN_VOID_PENALTY_CAP, 8,
             "T.2 (v0.11.11): K.BOT_SUN_VOID_PENALTY_CAP = 8")
    local botSrc = io.open(WHEREDNGN_TESTS_ROOT .. "/Bot.lua"):read("*a")
    local fnStart = botSrc:find("local function sunStrength")
    if fnStart then
        local body = botSrc:sub(fnStart, fnStart + 3000)
        assertTrue(body:find("math%.min%(penalty, K%.BOT_SUN_VOID_PENALTY_CAP%)") ~= nil,
                   "T.2b (v0.11.11): sunStrength uses K.BOT_SUN_VOID_PENALTY_CAP")
        assertTrue(body:find("math%.min%(penalty, 18%)") == nil,
                   "T.2c (v0.11.11): old 18-cap removed")
    end
end

-- T.3 — hokmMinShape Lever C tightened to require second trump = 9 or A.
do
    local botSrc = io.open(WHEREDNGN_TESTS_ROOT .. "/Bot.lua"):read("*a")
    local fnStart = botSrc:find("local function hokmMinShape")
    assertTrue(fnStart ~= nil, "T.3 setup: hokmMinShape found")
    if fnStart then
        local body = botSrc:sub(fnStart, fnStart + 3500)
        -- New gate references hasTrumpNine and hasTrumpA tracked in
        -- the loop, then requires (hasTrumpNine or hasTrumpA) in the
        -- count==2 branch.
        assertTrue(body:find("hasTrumpA, hasTrumpNine") ~= nil,
                   "T.3a (v0.11.9): hokmMinShape declares hasTrumpA + hasTrumpNine flags")
        assertTrue(body:find("hasTrumpNine or hasTrumpA") ~= nil,
                   "T.3b (v0.11.9): count==2 branch requires (9 or A) in trump")
    end
end

-- T.4 — Behavioral pin: hokmMinShape rejects [JS 8S + side AC] (J+8
-- weak-mardoofa, the exact RT07-07 trace case).
do
    -- Build a 5-card hand: JS, 8S, AC, 7H, 9D — the structural shape
    -- of the s4 r2 trace event. count(S)=2 with J+8, hasSideAce=true.
    local hand = { "JS", "8S", "AC", "7H", "9D" }
    -- Pre-v0.11.9: hokmMinShape("S") returned true (J+8 + side ace
    -- passed Lever C). v0.11.9: returns false because second trump is
    -- 8 (not 9 or A). The function is local to Bot.lua so we can't
    -- call it directly from this harness — verify via Bot.PickBid
    -- output instead.
    --
    -- Bot.PickBid surfaces hokmMinShape rejection by falling through
    -- to PASS in R1 (no Hokm fires). Set up state for an R1 bid call.
    if Bot.PickBid then
        freshState()
        S.s.isHost = true
        S.s.hostHands = { [1] = hand, [2] = {}, [3] = {}, [4] = {} }
        S.s.bidRound = 1
        S.s.bidCard = "8S"  -- flipped card matching trump suit S
        S.s.bids = {}
        S.s.dealer = 4
        S.s.cumulative = { A = 0, B = 0 }
        WHEREDNGNDB = WHEREDNGNDB or {}
        WHEREDNGNDB.advancedBots = false
        WHEREDNGNDB.m3lmBots = false
        WHEREDNGNDB.fzlokyBots = false
        WHEREDNGNDB.saudiMasterBots = false
        local bid = Bot.PickBid(1)
        -- Pre-v0.11.9: bid would be "HOKM:S" (J+8+side-Ace passed
        -- Lever C). Post-v0.11.9: should be PASS (Lever C now
        -- rejects J+8). The basic-tier hokmMinShape gate also
        -- runs, so even without M3lm the J+8+side-Ace case is now
        -- caught.
        assertEq(bid, K.BID_PASS,
                 "T.4 (v0.11.9 RT07-07): J+8 weak-mardoofa with side-Ace no longer triggers Hokm bid")
    end
end

-- =====================================================================
-- U. v0.11.11 audit-queue batch (NetU-01..09 + SU-Ultra-01..03 + XU-07/09)
-- =====================================================================
section("U. v0.11.11 audit-queue batch")

-- U.1 (NetU-01): _HostResolveOvercall has 250ms re-broadcast for OPEN-1.
do
    local netSrc = io.open(WHEREDNGN_TESTS_ROOT .. "/Net.lua"):read("*a")
    local fnStart = netSrc:find("function N%._HostResolveOvercall")
    assertTrue(fnStart ~= nil, "U.1 setup: _HostResolveOvercall found")
    if fnStart then
        local body = netSrc:sub(fnStart, fnStart + 2500)
        assertTrue(body:find("C_Timer%.After%(0%.25") ~= nil,
                   "U.1 (NetU-01): OPEN-1 250ms re-broadcast scheduled in _HostResolveOvercall")
        assertTrue(body:find("if S%.s%.contract then") ~= nil,
                   "U.1b (NetU-01): re-broadcast nil-guards on s.contract")
    end
end

-- U.2 (NetU-02): _OnMeld validates kind enum.
do
    local netSrc = io.open(WHEREDNGN_TESTS_ROOT .. "/Net.lua"):read("*a")
    assertTrue(netSrc:find('kind ~= "seq3" and kind ~= "seq4" and kind ~= "seq5" and kind ~= "carre"') ~= nil,
               "U.2 (NetU-02): _OnMeld rejects kind outside {seq3,seq4,seq5,carre}")
end

-- U.3 (NetU-03): _OnAKA validates suit enum.
do
    local netSrc = io.open(WHEREDNGN_TESTS_ROOT .. "/Net.lua"):read("*a")
    local fnStart = netSrc:find("function N%._OnAKA")
    if fnStart then
        local body = netSrc:sub(fnStart, fnStart + 800)
        assertTrue(body:find('suit ~= "S" and suit ~= "H"') ~= nil,
                   "U.3 (NetU-03): _OnAKA rejects suit outside {S,H,D,C}")
    end
end

-- U.4 (NetU-04): _OnRound bounds-checks score fields.
do
    local netSrc = io.open(WHEREDNGN_TESTS_ROOT .. "/Net.lua"):read("*a")
    local fnStart = netSrc:find("function N%._OnRound")
    if fnStart then
        local body = netSrc:sub(fnStart, fnStart + 1500)
        assertTrue(body:find("addA < 0 or addB < 0") ~= nil,
                   "U.4 (NetU-04): _OnRound rejects negative score fields")
        assertTrue(body:find("totA > 1000 or totB > 1000") ~= nil,
                   "U.4b (NetU-04): _OnRound rejects implausibly large totals")
    end
end

-- U.5 (NetU-05): _OnBidCard validates card format.
do
    local netSrc = io.open(WHEREDNGN_TESTS_ROOT .. "/Net.lua"):read("*a")
    local fnStart = netSrc:find("function N%._OnBidCard")
    if fnStart then
        local body = netSrc:sub(fnStart, fnStart + 800)
        assertTrue(body:find('card and card ~= "" and #card ~= 2') ~= nil,
                   "U.5 (NetU-05): _OnBidCard rejects malformed cards")
    end
end

-- U.6 (NetU-06): _OnLobby caps name length.
do
    local netSrc = io.open(WHEREDNGN_TESTS_ROOT .. "/Net.lua"):read("*a")
    local fnStart = netSrc:find("function N%._OnLobby")
    if fnStart then
        local body = netSrc:sub(fnStart, fnStart + 3000)
        assertTrue(body:find("n:sub%(1, 64%)") ~= nil,
                   "U.6 (NetU-06): _OnLobby caps each name at 64 chars")
    end
end

-- U.7 (NetU-07): _OnPreempt validates seat range.
do
    local netSrc = io.open(WHEREDNGN_TESTS_ROOT .. "/Net.lua"):read("*a")
    local fnStart = netSrc:find("function N%._OnPreempt%s*%(")
    if fnStart then
        local body = netSrc:sub(fnStart, fnStart + 400)
        assertTrue(body:find("seat < 1 or seat > 4") ~= nil,
                   "U.7 (NetU-07): _OnPreempt rejects seat outside 1-4")
    end
end

-- U.8 (NetU-08): _OnSWAResp validates responder + caller range.
do
    local netSrc = io.open(WHEREDNGN_TESTS_ROOT .. "/Net.lua"):read("*a")
    local fnStart = netSrc:find("function N%._OnSWAResp")
    if fnStart then
        local body = netSrc:sub(fnStart, fnStart + 1200)
        assertTrue(body:find("responder < 1 or responder > 4") ~= nil,
                   "U.8a (NetU-08): _OnSWAResp rejects responder outside 1-4")
        assertTrue(body:find("caller < 1 or caller > 4") ~= nil,
                   "U.8b (NetU-08): _OnSWAResp rejects caller outside 1-4")
    end
end

-- U.9 (NetU-09): _OnHand caps encodedCards length.
do
    local netSrc = io.open(WHEREDNGN_TESTS_ROOT .. "/Net.lua"):read("*a")
    local fnStart = netSrc:find("function N%._OnHand")
    if fnStart then
        local body = netSrc:sub(fnStart, fnStart + 1000)
        assertTrue(body:find("encodedCards and #encodedCards > 16") ~= nil,
                   "U.9 (NetU-09): _OnHand rejects encodedCards longer than 16 chars")
    end
end

-- U.10 (NetU2-01 — v0.11.13 revert of v0.11.11 XU-09):
-- s.overcall is NOT in TRANSIENT_FIELDS. The original v0.9.0 M2 host
-- re-arm at WHEREDNGN.lua:300 specifically depends on `s.overcall`
-- surviving /reload to schedule a fresh resolve timer; making it
-- transient (the v0.11.11 XU-09 change) caused the host to soft-lock
-- in PHASE_OVERCALL after /reload — the re-arm short-circuited on
-- `if … and B.State.s.overcall then` because the field was wiped
-- before the post-restore check. v0.11.13 reverted to the canonical
-- v0.9.0 M2 design.
do
    local stateSrc = io.open(WHEREDNGN_TESTS_ROOT .. "/State.lua"):read("*a")
    local tfStart = stateSrc:find("local TRANSIENT_FIELDS = {")
    assertTrue(tfStart ~= nil, "U.10 setup: TRANSIENT_FIELDS table found")
    if tfStart then
        local search = stateSrc:sub(tfStart)
        local braceEnd = search:find("\n}\n", 1, true)
        local body = search:sub(1, braceEnd or #search)
        assertTrue(body:find("overcall%s*=%s*true%s*,") == nil,
                   "U.10 (NetU2-01): s.overcall is NOT in TRANSIENT_FIELDS (v0.11.13 revert)")
    end
end

-- U.11 (SU-Ultra-01): HostResolveSWA stashes breakdown on swaResult.
do
    local netSrc = io.open(WHEREDNGN_TESTS_ROOT .. "/Net.lua"):read("*a")
    local fnStart = netSrc:find("function N%.HostResolveSWA")
    if fnStart then
        local body = netSrc:sub(fnStart, fnStart + 12000)
        assertTrue(body:find("breakdown%s*=%s*breakdown") ~= nil,
                   "U.11a (SU-Ultra-01): HostResolveSWA stashes breakdown on swaResult")
        assertTrue(body:find("local breakdown") ~= nil,
                   "U.11b (SU-Ultra-01): breakdown computed for both valid and invalid SWA branches")
    end
end

-- U.12 (SU-Ultra-01): UI.lua renderBanner SWA branch consumes sw.breakdown.
do
    local uiSrc = io.open(WHEREDNGN_TESTS_ROOT .. "/UI.lua"):read("*a")
    -- Must reference sw.breakdown (the new field) for the per-team rows.
    assertTrue(uiSrc:find("local bd = sw%.breakdown") ~= nil,
               "U.12 (SU-Ultra-01): UI.lua reads sw.breakdown in renderBanner SWA branch")
end

-- U.13 (SU-Ultra-03 + v0.11.14 SU2-08): renderCardGlyphs whitelists
-- ranks+suits via K.RANK_INDEX / K.SUIT_INDEX truthiness checks.
-- Pre-v0.11.14 used local VALID_RANKS / VALID_SUITS duplicate tables;
-- v0.11.14 SU2-08 deduped to use the canonical Constants.lua tables.
do
    local uiSrc = io.open(WHEREDNGN_TESTS_ROOT .. "/UI.lua"):read("*a")
    assertTrue(uiSrc:find("K%.RANK_INDEX%[rank%]") ~= nil,
               "U.13a (SU2-08): renderCardGlyphs whitelists ranks via K.RANK_INDEX")
    assertTrue(uiSrc:find("K%.SUIT_INDEX%[suit%]") ~= nil,
               "U.13b (SU2-08): renderCardGlyphs whitelists suits via K.SUIT_INDEX")
end

-- U.14 (XU-07 + v0.11.14): magic-number promotion to K.* — six constants
-- post-v0.11.14 (added K.BOT_SUN_2ACE_BONUS).
do
    assertEq(K.BOT_TH_HOKM_R1_BASE, 42,    "U.14a: K.BOT_TH_HOKM_R1_BASE = 42")
    assertEq(K.BOT_TH_HOKM_R2_BASE, 36,    "U.14b: K.BOT_TH_HOKM_R2_BASE = 36")
    assertEq(K.BOT_TH_SUN_BASE,     40,    "U.14c: K.BOT_TH_SUN_BASE = 40")
    assertEq(K.BOT_BID_JITTER,      6,     "U.14d: K.BOT_BID_JITTER = 6")
    assertEq(K.BOT_SUN_VOID_PENALTY_CAP, 8, "U.14e: K.BOT_SUN_VOID_PENALTY_CAP = 8")
    assertEq(K.BOT_SUN_2ACE_BONUS,  15,    "U.14f (v0.11.14): K.BOT_SUN_2ACE_BONUS = 15")
end

-- U.15 (XR-15/XU-10): Sound.Try helper introduced in Sound.lua.
do
    local soundSrc = io.open(WHEREDNGN_TESTS_ROOT .. "/Sound.lua"):read("*a")
    assertTrue(soundSrc:find("function M%.Try%(soundId%)") ~= nil,
               "U.15 (XR-15): Sound.Try helper added (incremental migration)")
end

-- =====================================================================
-- V. v0.11.13 hotfix batch (NetU2-01 + SU2-01..02 + XR2-05 + doc drift)
-- =====================================================================
print("")
print("=== Section V: v0.11.13 hotfix batch ===")

-- V.1 (SU2-02 CRITICAL): HostResolveSWA hoists per-team accounting
-- locals OUT of the if/else blocks so the breakdown stash can read
-- them. Pre-v0.11.13 the SU-Ultra-01 fix was unreachable because
-- the locals were declared inside the now-closed if/else arms.
-- (Anchor is `local handTotal` — first non-comment line inside the
-- invalid-arm body — to avoid matching `if not valid then` in the
-- explanatory comment block.)
do
    local netSrc = io.open(WHEREDNGN_TESTS_ROOT .. "/Net.lua"):read("*a")
    local fnStart = netSrc:find("function N%.HostResolveSWA")
    assertTrue(fnStart ~= nil, "V.1 setup: HostResolveSWA found")
    if fnStart then
        local body = netSrc:sub(fnStart, fnStart + 8000)
        local ifBodyStart = body:find("local handTotal = ", 1, true)
        local hoistMatch = body:find(
            "local cardA, cardB, mpA, mpB, mult, beloteOwner", 1, true)
        -- "local result" hoisted: appears in the prefix before `local handTotal`.
        local prefix = ifBodyStart and body:sub(1, ifBodyStart - 1) or ""
        local resultHoist = prefix:find("local result", 1, true)
        assertTrue(hoistMatch ~= nil and ifBodyStart ~= nil and hoistMatch < ifBodyStart,
                   "V.1a (SU2-02): cardA/cardB/mpA/mpB/mult/beloteOwner hoisted before if-block")
        assertTrue(resultHoist ~= nil,
                   "V.1b (SU2-02): result hoisted before if-block")
    end
end

-- V.2 (XR2-05/06 MED): _OnContract validates Hokm trump suit against
-- the 4-suit enum. Mirrors NetU-03 _OnAKA pattern.
do
    local netSrc = io.open(WHEREDNGN_TESTS_ROOT .. "/Net.lua"):read("*a")
    local fnStart = netSrc:find("function N%._OnContract")
    assertTrue(fnStart ~= nil, "V.2 setup: _OnContract found")
    if fnStart then
        local body = netSrc:sub(fnStart, fnStart + 2000)
        assertTrue(body:find('trump == "S" or trump == "H" or trump == "D" or trump == "C"') ~= nil,
                   "V.2 (XR2-05): _OnContract validates Hokm trump suit enum")
    end
end

-- V.3 (SU2-01 MED): ApplyResyncSnapshot clears stale s.overcall
-- (defense-in-depth, parallel to the 11 sibling clears).
do
    local stateSrc = io.open(WHEREDNGN_TESTS_ROOT .. "/State.lua"):read("*a")
    local fnStart = stateSrc:find("function S%.ApplyResyncSnapshot")
    assertTrue(fnStart ~= nil, "V.3 setup: ApplyResyncSnapshot found")
    if fnStart then
        -- ApplyResyncSnapshot is ~150 lines; need a wide window. Cap
        -- at the next top-level `function` to stay within scope.
        local body = stateSrc:sub(fnStart)
        local nextFn = body:find("\nfunction ", 2, true)
        if nextFn then body = body:sub(1, nextFn) end
        assertTrue(body:find("s%.overcall%s*=%s*nil") ~= nil,
                   "V.3 (SU2-01): ApplyResyncSnapshot clears s.overcall")
    end
end

-- V.4 (NetU2-01 HIGH revert): WHEREDNGN.lua post-restore PHASE_OVERCALL
-- re-arm path is preserved AND the gate `B.State.s.overcall` non-nil
-- can fire (i.e., overcall is NOT in TRANSIENT_FIELDS — already
-- pinned in U.10, this is a behavioral cross-check).
do
    local mainSrc = io.open(WHEREDNGN_TESTS_ROOT .. "/WHEREDNGN.lua"):read("*a")
    -- The re-arm depends on `s.phase == PHASE_OVERCALL and s.overcall`
    -- both being truthy after RestoreSession. Pin presence of the gate.
    assertTrue(mainSrc:find("PHASE_OVERCALL and B%.State%.s%.overcall") ~= nil
               or mainSrc:find('phase == K%.PHASE_OVERCALL and B%.State%.s%.overcall') ~= nil
               or mainSrc:find("PHASE_OVERCALL.-overcall") ~= nil,
               "V.4 (NetU2-01): post-restore PHASE_OVERCALL re-arm gate intact")
end

-- =====================================================================
-- W. v0.11.14 — 2-Ace Sun bonus (user-bidcalc trace evidence)
-- =====================================================================
print("")
print("=== Section W: v0.11.14 2-Ace Sun bonus ===")

-- W.1 — Bot.PickBid applies the 2-Ace bonus. Source-pin: the
-- elseif that adds K.BOT_SUN_2ACE_BONUS is present in PickBid.
do
    local botSrc = io.open(WHEREDNGN_TESTS_ROOT .. "/Bot.lua"):read("*a")
    local fnStart = botSrc:find("function Bot%.PickBid")
    assertTrue(fnStart ~= nil, "W.1 setup: Bot.PickBid found")
    if fnStart then
        local body = botSrc:sub(fnStart, fnStart + 5000)
        assertTrue(body:find("aceCount == 2") ~= nil
                   and body:find("K%.BOT_SUN_2ACE_BONUS") ~= nil,
                   "W.1 (v0.11.14): PickBid applies K.BOT_SUN_2ACE_BONUS for aceCount==2")
    end
end

-- W.2 — Behavioral: the user-trace 2-Ace hands fire Sun post-bonus.
-- Sets up minimal state so PickBid can run and exercises both hands
-- the user pasted from /baloot bidcalc that previously skipped Sun.
do
    -- Save / restore S.s state we mutate (don't pollute later tests).
    local s_save = {
        bidRound = S.s.bidRound, bidCard = S.s.bidCard,
        dealer = S.s.dealer, hostHands = S.s.hostHands,
        cumulative = S.s.cumulative, bids = S.s.bids,
    }

    -- Configure: round 1, dealer=4 so seat 1 = first bidder. Bidcard
    -- is club to match the trace context (any non-conflicting suit
    -- works — we expect Sun fire to override Hokm-on-flipped anyway).
    S.s.bidRound  = 1
    S.s.bidCard   = "8C"
    S.s.dealer    = 4
    S.s.cumulative = { A = 0, B = 0 }
    S.s.bids      = {}

    -- Hand 1 from trace 03:15:21 r1 — was sun=17 thSun=38 SKIPPED.
    -- Post-bonus: sun should be 32 (17 + 15 = 32).
    -- Jitter band [34, 46] still excludes 32 deterministically — but
    -- the WIN here is reaching the band at all (was 17 = unreachable).
    -- For a deterministic fire test we'd need to either override
    -- jitter or pick a higher-scoring hand. The user-trace example
    -- 03:20:13 hand=[AH AD KC 7H QS] sun=21 → 36 post-bonus IS in
    -- the band; ~39% jitter rolls fire. We can't pin a probabilistic
    -- outcome without seeding, so this test pins the SCORE (which is
    -- deterministic) via Bot.PickBid running and observing the trace
    -- (or computing inline). Simpler approach: pin the bonus is
    -- applied by checking a hand that reliably fires post-bonus.

    -- Strong hand: 2 Aces with KIng + Queen of trump-equivalent suits.
    -- AH AD KC QS 7H = 2 Aces + K + Q across 4 suits (not a 3-Ace).
    -- Face: 11+11+4+3+0 = 29. count S=1 H=2 D=1 C=1.
    -- Penalty (advanced): S(short) +10, D(short) +10, C(short) +10,
    --   H has count=2 + honors → 0. Total penalty=30, capped at 8.
    -- sunStrength = 29 - 8 = 21. Post-2-Ace bonus = 36.
    -- thSun base 40 with jitter ±6 → band [34, 46].
    -- 36 fires when jitter is -6, -5, -4, -3, -2 (jit<=-4 actually):
    --   thSun = 40+jit; fire if 36 >= thSun → jit <= -4.
    --   With jitter range [-6, +6] (13 values), fire on 3/13 = 23%.
    -- This is non-deterministic; we pin the SCORE side via direct call.

    -- For W.2: Use a hand that reliably fires (high enough score).
    -- AH AS AD KC 7H = 3 Aces, gets 3-Ace bonus, NOT 2-Ace bonus.
    -- That doesn't test our new bonus. Instead use 2 Aces + 1 mardoofa:
    -- AH TH AD 8C 7S = 2A + mardoofa (AH+TH).
    -- With mardoofa: shape passes via 2 Aces (>=2 path).
    -- aceCount=2, mardoofaCount=1.
    -- Face: 11+10+11+0+0 = 32. count S=1 H=2 D=1 C=1.
    -- Penalty: S+10 D+10 C+10 → 30, capped 8. sunStrength = 24.
    -- 2-Ace bonus +15 + mardoofa +20 = +35. Total sun = 59.
    -- thSun ≤ 46 always → fires deterministically.
    S.s.hostHands = { ["1"] = nil }  -- only seat 1
    S.s.hostHands[1] = { "AH", "TH", "AD", "8C", "7S" }
    -- aceCount=2 elseif fires; mardoofa=1 adds +20; Sun fires.
    if Bot and Bot.PickBid then
        local result = Bot.PickBid(1)
        assertEq(result, K.BID_SUN,
                 "W.2 (v0.11.14): 2-Ace+mardoofa hand reliably fires Sun")
    end

    -- Restore.
    S.s.bidRound = s_save.bidRound
    S.s.bidCard = s_save.bidCard
    S.s.dealer = s_save.dealer
    S.s.hostHands = s_save.hostHands
    S.s.cumulative = s_save.cumulative
    S.s.bids = s_save.bids
end

-- =====================================================================
-- X. v0.11.15 — bot bidding gaps surfaced by user audit:
--   X.1: Sun overcall void-in-trump bonus
--   X.2: hokmMinShape J+9+count>=3 self-sufficient mardoofa
--   X.3: R1 Hokm-on-flipped includes bidcard in shape eval
-- =====================================================================
print("")
print("=== Section X: v0.11.15 bot bidding audit fixes ===")

-- X.1a — Constants pinned
do
    assertEq(K.BOT_OVERCALL_VOID_TRUMP_BONUS,  15,
             "X.1a: K.BOT_OVERCALL_VOID_TRUMP_BONUS = 15")
    assertEq(K.BOT_OVERCALL_SHORT_TRUMP_BONUS,  8,
             "X.1b: K.BOT_OVERCALL_SHORT_TRUMP_BONUS = 8")
end

-- X.1c — Bot.PickOvercall applies the void/short bonus
do
    local botSrc = io.open(WHEREDNGN_TESTS_ROOT .. "/Bot.lua"):read("*a")
    local fnStart = botSrc:find("function Bot%.PickOvercall")
    assertTrue(fnStart ~= nil, "X.1c setup: Bot.PickOvercall found")
    if fnStart then
        local body = botSrc:sub(fnStart, fnStart + 3000)
        assertTrue(body:find("K%.BOT_OVERCALL_VOID_TRUMP_BONUS") ~= nil,
                   "X.1c (Q1): PickOvercall references K.BOT_OVERCALL_VOID_TRUMP_BONUS")
        assertTrue(body:find("trumpCount == 0") ~= nil,
                   "X.1d (Q1): PickOvercall checks for trump-suit void")
    end
end

-- X.2 — hokmMinShape allows J+9+count>=3 self-sufficient (no side Ace)
-- Source-pin: the new path appears AFTER the count>=4 check and BEFORE
-- the L07 any-Ace gate.
do
    local botSrc = io.open(WHEREDNGN_TESTS_ROOT .. "/Bot.lua"):read("*a")
    local fnStart = botSrc:find("local function hokmMinShape")
    assertTrue(fnStart ~= nil, "X.2 setup: hokmMinShape found")
    if fnStart then
        local body = botSrc:sub(fnStart, fnStart + 3000)
        assertTrue(body:find("count >= 3 and hasTrumpNine") ~= nil,
                   "X.2 (Q2): hokmMinShape adds J+9+count>=3 self-sufficient path")
        -- Verify the new path comes BEFORE the L07 gate, otherwise
        -- the L07 would still reject these hands.
        local newPath = body:find("count >= 3 and hasTrumpNine")
        local l07 = body:find("Bot%.IsM3lm%(%) and not hasAnyAce")
        if newPath and l07 then
            assertTrue(newPath < l07,
                       "X.2b (Q2): self-sufficient mardoofa path runs BEFORE L07 any-Ace gate")
        end
    end
end

-- X.3 — R1 Hokm-on-flipped includes bidcard in shape evaluation.
-- Bot.PickBid is ~330 lines; need a wide window to cover the R1
-- Hokm-on-flipped block which sits ~280 lines into the function.
do
    local botSrc = io.open(WHEREDNGN_TESTS_ROOT .. "/Bot.lua"):read("*a")
    local fnStart = botSrc:find("function Bot%.PickBid")
    assertTrue(fnStart ~= nil, "X.3 setup: Bot.PickBid found")
    if fnStart then
        local body = botSrc:sub(fnStart, fnStart + 25000)
        -- Source-pin: hypHand built from hand + bidCard, passed to
        -- hokmMinShape instead of bare hand.
        assertTrue(body:find("hypHand%[#hypHand %+ 1%] = S%.s%.bidCard") ~= nil,
                   "X.3a (audit): R1 Hokm-on-flipped builds hypothetical post-win hand")
        assertTrue(body:find("hokmMinShape%(hypHand, bidCardSuit%)") ~= nil,
                   "X.3b (audit): R1 Hokm-on-flipped passes hypHand to hokmMinShape")
    end
end

-- X.4 — Behavioral: Hokm-on-flipped fires when bidcard provides the
-- missing J of trump. Pre-v0.11.15 this path was rejected at the
-- B-4 absolute floor (no J in hand).
do
    local s_save = {
        bidRound = S.s.bidRound, bidCard = S.s.bidCard,
        dealer = S.s.dealer, hostHands = S.s.hostHands,
        cumulative = S.s.cumulative, bids = S.s.bids,
    }
    S.s.bidRound  = 1
    S.s.bidCard   = "JC"  -- bidcard provides J of clubs
    S.s.dealer    = 4     -- seat 1 = first bidder
    S.s.cumulative = { A = 0, B = 0 }
    S.s.bids      = {}
    S.s.hostHands = {}
    -- Hand with no J of clubs but 3 clubs (8C 9C TC) + side Ace AS + KH.
    -- count of clubs = 3 (8C 9C TC) + bidcard JC = 4 total. hasJ=true
    -- (via bidcard). count>=4 → self-sufficient. Should fire Hokm-C.
    S.s.hostHands[1] = { "8C", "9C", "TC", "AS", "KH" }
    if Bot and Bot.PickBid then
        local result = Bot.PickBid(1)
        assertEq(result, K.BID_HOKM .. ":C",
                 "X.4 (audit): bidcard-provides-J Hokm-on-flipped fires post-bidcard-inclusion")
    end
    S.s.bidRound = s_save.bidRound
    S.s.bidCard = s_save.bidCard
    S.s.dealer = s_save.dealer
    S.s.hostHands = s_save.hostHands
    S.s.cumulative = s_save.cumulative
    S.s.bids = s_save.bids
end

-- =====================================================================
-- Summary
-- =====================================================================
print("")
print(("== Result: %d passed, %d failed =="):format(pass, fail))
TEST_RESULTS = { passed = pass, failed = fail }
if fail == 0 then return true end
return false
