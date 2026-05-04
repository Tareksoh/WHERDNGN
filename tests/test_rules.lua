-- tests/test_rules.lua
--
-- Pure-logic harness for Constants.lua + Cards.lua + Rules.lua.
-- Loads the real addon files under stub globals (no WoW frame API
-- needed for these three layers) and exercises every public function
-- with realistic scenarios.
--
-- Run via the companion `run.py` (uses Python lupa to drive Lua),
-- or directly under any standalone Lua 5.1 - 5.5 interpreter:
--     lua tests/test_rules.lua
--
-- Returns true on full pass, false on any failure. Exits with the same
-- status when invoked as a script.

-- -- Globals shim --------------------------------------------------------
unpack = unpack or table.unpack
C_AddOns = nil
GetAddOnMetadata = nil

-- Locate the addon source dir. Priority:
--   1. WHEREDNGN_TESTS_ROOT global (set by the Python runner)
--   2. Inferred from debug.getinfo if running directly under standalone Lua
local function addonRoot()
    if WHEREDNGN_TESTS_ROOT then return WHEREDNGN_TESTS_ROOT end
    local src = debug.getinfo(1, "S").source
    if src:sub(1, 1) ~= "@" then
        error("cannot locate addon root: not running from a file. " ..
              "Set WHEREDNGN_TESTS_ROOT before running.")
    end
    src = src:sub(2)
    -- src points to .../tests/test_rules.lua. Strip /tests/test_rules.lua.
    return (src:gsub("[/\\]tests[/\\][^/\\]+$", ""))
end

local ROOT = addonRoot()
local function load(rel)
    local path = (ROOT .. "/" .. rel):gsub("\\", "/")
    local chunk, err = loadfile(path)
    if not chunk then error("failed to load " .. rel .. ": " .. tostring(err)) end
    chunk()
end

load("Constants.lua")
load("Cards.lua")
load("Rules.lua")

local K = WHEREDNGN.K
local C = WHEREDNGN.Cards
local R = WHEREDNGN.Rules

-- -- Tiny test framework -------------------------------------------------

local pass, fail = 0, 0
local failures = {}
local VERBOSE = (TEST_VERBOSE == true)

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

local function section(label)
    print("")
    print("== " .. label .. " ==")
end

-- -- Builders ------------------------------------------------------------

local function hokm(trump, bidder, opts)
    local c = { type = K.BID_HOKM, trump = trump, bidder = bidder or 1 }
    if opts then for k, v in pairs(opts) do c[k] = v end end
    return c
end
local function sun(bidder, opts)
    local c = { type = K.BID_SUN, bidder = bidder or 1 }
    if opts then for k, v in pairs(opts) do c[k] = v end end
    return c
end

local function trick(leadSuit, ...)
    local args = { ... }
    local plays = {}
    for _, p in ipairs(args) do
        plays[#plays + 1] = { seat = p[1], card = p[2] }
    end
    return { leadSuit = leadSuit, plays = plays }
end

local function fullDeck()
    local d = {}
    for _, s in ipairs(K.SUITS) do
        for _, r in ipairs(K.RANKS) do d[#d + 1] = r .. s end
    end
    return d
end

-- 8 sweep tricks won by winnerSeat. Cards drawn sequentially from a full
-- deck so ScoreRound's belote scan sees real data, but no specific card
-- is forced into seat 1 (so no incidental K+Q belote).
local function sweptTricks(winnerSeat)
    local tricks = {}
    local cards = fullDeck()
    local idx = 1
    for i = 1, 8 do
        local plays = {}
        for s = 1, 4 do
            plays[#plays + 1] = { seat = s, card = cards[idx] }
            idx = idx + 1
        end
        tricks[#tricks + 1] = {
            winner = winnerSeat,
            leadSuit = C.Suit(plays[1].card),
            plays = plays,
        }
    end
    return tricks
end

-- =====================================================================
-- A. Card primitives (Cards.lua)
-- =====================================================================
section("A. Card primitives (Cards.lua)")

assertEq(C.Suit("JH"), "H", "Suit('JH')")
assertEq(C.Rank("JH"), "J", "Rank('JH')")
assertTrue(C.IsValid("JH"),  "IsValid('JH')")
assertFalse(C.IsValid("ZZ"), "IsValid('ZZ') (bad rank+suit)")
assertFalse(C.IsValid("J"),  "IsValid('J')  (too short)")
assertFalse(C.IsValid(nil),  "IsValid(nil)")
assertFalse(C.IsValid(123),  "IsValid(123)")

assertTrue(C.IsTrump("JH",  hokm("H")),  "IsTrump JH in Hokm-H")
assertFalse(C.IsTrump("JS", hokm("H")),  "IsTrump JS in Hokm-H")
assertFalse(C.IsTrump("JH", sun()),      "IsTrump JH in Sun (always false)")
assertFalse(C.IsTrump("JH", nil),        "IsTrump nil contract")

assertEq(C.TrickRank("JH", hokm("H")), 8, "TrickRank trump-J in Hokm")
assertEq(C.TrickRank("9H", hokm("H")), 7, "TrickRank trump-9 in Hokm")
assertEq(C.TrickRank("AH", hokm("H")), 6, "TrickRank trump-A in Hokm")
assertEq(C.TrickRank("AH", hokm("S")), 8, "TrickRank off-trump A == plain Ace")
assertEq(C.TrickRank("AH", sun()),     8, "TrickRank A in Sun")
assertEq(C.TrickRank("7H", hokm("H")), 1, "TrickRank trump-7 (lowest)")

assertEq(C.PointValue("JH", hokm("H")), 20, "PointValue trump-J = 20")
assertEq(C.PointValue("9H", hokm("H")), 14, "PointValue trump-9 = 14")
assertEq(C.PointValue("AH", hokm("H")), 11, "PointValue trump-A = 11")
assertEq(C.PointValue("TH", hokm("H")), 10, "PointValue trump-T = 10")
assertEq(C.PointValue("KH", hokm("H")), 4,  "PointValue trump-K = 4")
assertEq(C.PointValue("QH", hokm("H")), 3,  "PointValue trump-Q = 3")
assertEq(C.PointValue("8H", hokm("H")), 0,  "PointValue trump-8 = 0")
assertEq(C.PointValue("JH", hokm("S")), 2,  "PointValue off-trump J = 2")
assertEq(C.PointValue("AS", sun()),     11, "PointValue Sun A = 11")
assertEq(C.PointValue("9S", sun()),     0,  "PointValue Sun 9 = 0")

assertTrue(C.IsKaweshHand({"7S","8H","9D","7C","8S"}),
           "IsKaweshHand all 7/8/9")
assertFalse(C.IsKaweshHand({"7S","8H","TS","7C","8S"}),
            "IsKaweshHand with a T")
assertFalse(C.IsKaweshHand({}), "IsKaweshHand empty")

-- =====================================================================
-- B. Seat helpers (Rules.lua)
-- =====================================================================
section("B. Seat helpers (Rules.lua)")

assertEq(R.TeamOf(1), "A", "TeamOf(1)")
assertEq(R.TeamOf(2), "B", "TeamOf(2)")
assertEq(R.TeamOf(3), "A", "TeamOf(3)")
assertEq(R.TeamOf(4), "B", "TeamOf(4)")
assertEq(R.Partner(1), 3, "Partner(1)")
assertEq(R.Partner(2), 4, "Partner(2)")
assertEq(R.Partner(3), 1, "Partner(3)")
assertEq(R.Partner(4), 2, "Partner(4)")
assertEq(R.NextSeat(1), 2, "NextSeat(1)")
assertEq(R.NextSeat(2), 3, "NextSeat(2)")
assertEq(R.NextSeat(3), 4, "NextSeat(3)")
assertEq(R.NextSeat(4), 1, "NextSeat(4)")

-- =====================================================================
-- C. Trick resolution (TrickWinner / TrickPoints)
-- =====================================================================
section("C. Trick resolution")

-- Hokm, hearts trump, hearts led. Trump-J wins.
do
    local t = trick("H", {1,"AH"}, {2,"JH"}, {3,"9H"}, {4,"KH"})
    assertEq(R.TrickWinner(t, hokm("H")), 2, "Hokm: trump-J wins trump-led trick")
end

-- Hokm, spades led, hearts trump, one trump played: trump beats lead.
do
    local t = trick("S", {1,"AS"}, {2,"7H"}, {3,"KS"}, {4,"QS"})
    assertEq(R.TrickWinner(t, hokm("H")), 2, "Hokm: any trump beats lead suit")
end

-- Hokm, spades led, no trump: highest spade wins.
do
    local t = trick("S", {1,"AS"}, {2,"9D"}, {3,"KS"}, {4,"QS"})
    assertEq(R.TrickWinner(t, hokm("H")), 1, "Hokm: highest lead suit wins (no trump)")
end

-- Sun, hearts led: highest hearts wins regardless of off-suit content.
do
    local t = trick("H", {1,"AH"}, {2,"TS"}, {3,"KH"}, {4,"QH"})
    assertEq(R.TrickWinner(t, sun()), 1, "Sun: highest hearts wins")
end

-- Sun, only the lead is in lead-suit, all others off-suit: lead wins.
do
    local t = trick("H", {1,"9H"}, {2,"AS"}, {3,"TC"}, {4,"JD"})
    assertEq(R.TrickWinner(t, sun()), 1, "Sun: only lead-suit eligible")
end

-- TrickPoints
do
    local t = trick("H", {1,"JH"}, {2,"9H"}, {3,"AH"}, {4,"TH"})
    assertEq(R.TrickPoints(t, hokm("H")), 20+14+11+10,
             "TrickPoints Hokm trump JH+9H+AH+TH = 55")
end
do
    local t = trick("S", {1,"AS"}, {2,"KS"}, {3,"QS"}, {4,"JS"})
    assertEq(R.TrickPoints(t, hokm("H")), 11+4+3+2,
             "TrickPoints Hokm off-trump AS+KS+QS+JS = 20")
end
do
    local t = trick("H", {1,"AH"}, {2,"TH"}, {3,"KH"}, {4,"QH"})
    assertEq(R.TrickPoints(t, sun()), 11+10+4+3,
             "TrickPoints Sun AH+TH+KH+QH = 28")
end

-- =====================================================================
-- D. IsLegalPlay
-- =====================================================================
section("D. IsLegalPlay")

-- Empty trick: any card.
do
    local hand = {"AS","KH","9D"}
    local t = trick(nil)
    assertTrue(R.IsLegalPlay("AS", hand, t, hokm("H"), 1),
               "Empty trick: any card legal")
end

-- Must follow lead suit when held.
do
    local hand = {"AS","KS","9D"}
    local t = trick("H", {2,"AH"})
    assertFalse(R.IsLegalPlay("AS", hand, t, hokm("D"), 1),
                "Must follow lead suit when held")
end

-- Hokm: no lead, opp winning, must trump.
do
    local hand = {"7H","8H","9D"}
    local t = trick("S", {2,"AS"})
    assertFalse(R.IsLegalPlay("9D", hand, t, hokm("H"), 1),
                "Hokm: no lead, opp winning, must trump (9D illegal)")
    assertTrue(R.IsLegalPlay("7H", hand, t, hokm("H"), 1),
               "Hokm: trump play OK")
end

-- Hokm: partner winning → any card legal.
do
    local hand = {"9D","KC","8C"}
    local t = trick("S", {2,"AS"}, {3,"AH"})  -- seat 3 = partner of seat 1, trumped in
    assertTrue(R.IsLegalPlay("9D", hand, t, hokm("H"), 1),
               "Hokm: partner winning, can throw any (9D off-suit)")
end

-- Sun: can't follow → any card legal.
do
    local hand = {"AS","9D","KC"}
    local t = trick("H", {2,"AH"})
    assertTrue(R.IsLegalPlay("AS", hand, t, sun(), 1),
               "Sun: no lead-suit card → any legal")
end

-- Hokm trump-led: can't overcut, opp winning → any trump OK.
-- Seat 3 (opp of seat 4) leads JH. My hand {AH(rank 6), 7H(rank 1)} — can't beat JH(rank 8).
do
    local hand = {"AH","7H"}
    local t = trick("H", {3,"JH"})
    assertTrue(R.IsLegalPlay("7H", hand, t, hokm("H"), 4),
               "Hokm trump led: can't overcut JH → any trump OK")
end

-- Hokm trump-led: opp winning, can overcut → must.
-- Seat 1 leads QH (opp of seat 4), seat 2 (partner) plays 8H, seat 3 (opp) plays 9H.
-- Seat 3's 9H (rank 7) is currently winning. My JH (rank 8) overcuts; 7H (rank 1) doesn't.
do
    local hand = {"JH","7H"}
    local t = trick("H", {1,"QH"}, {2,"8H"}, {3,"9H"})
    assertFalse(R.IsLegalPlay("7H", hand, t, hokm("H"), 4),
                "Hokm trump led: opp winning, must overcut (7H illegal)")
    assertTrue(R.IsLegalPlay("JH", hand, t, hokm("H"), 4),
               "Hokm trump led: JH overcut legal")
end

-- Hokm trump-led: partner winning → no overcut requirement.
do
    local hand = {"AH","8H"}
    local t = trick("H", {1,"JH"}, {2,"7H"})
    assertTrue(R.IsLegalPlay("8H", hand, t, hokm("H"), 3),
               "Hokm trump led: partner winning, no overcut requirement")
end

-- =====================================================================
-- E. Meld detection
-- =====================================================================
section("E. Meld detection (DetectMelds)")

do
    local hand = {"TS","JS","QS","9D"}
    local melds = R.DetectMelds(hand, hokm("H"))
    local seq3
    for _, m in ipairs(melds) do if m.kind == "seq3" then seq3 = m end end
    assertTrue(seq3, "seq3 detected (T-J-Q spades)")
    if seq3 then
        assertEq(seq3.value, K.MELD_SEQ3, "seq3 value = 20")
        assertEq(seq3.suit,  "S",          "seq3 suit = S")
    end
end

do
    local hand = {"7H","8H","9H","TH","JH","9D"}
    local melds = R.DetectMelds(hand, hokm("H"))
    local seq5
    for _, m in ipairs(melds) do if m.kind == "seq5" then seq5 = m end end
    assertTrue(seq5, "seq5 detected (7-8-9-T-J hearts)")
    if seq5 then assertEq(seq5.value, K.MELD_SEQ5, "seq5 value = 100") end
end

do
    local hand = {"KS","KH","KD","KC","9D"}
    local melds = R.DetectMelds(hand, hokm("H"))
    local carre
    for _, m in ipairs(melds) do if m.kind == "carre" then carre = m end end
    assertTrue(carre, "carre of K detected")
    if carre then
        assertEq(carre.value, K.MELD_CARRE_OTHER, "carre-K value = 100")
        assertEq(carre.top, "K", "carre top = K")
    end
end

do
    local hand = {"AS","AH","AD","AC","9D"}
    local melds = R.DetectMelds(hand, sun())
    local carre
    for _, m in ipairs(melds) do if m.kind == "carre" then carre = m end end
    assertTrue(carre, "carre of A detected in Sun")
    if carre then assertEq(carre.value, K.MELD_CARRE_A_SUN, "Four Hundred = 400") end
end

do
    local hand = {"AS","AH","AD","AC","9D"}
    local melds = R.DetectMelds(hand, hokm("H"))
    local carre
    for _, m in ipairs(melds) do if m.kind == "carre" then carre = m end end
    assertEq(carre, nil, "carre of A in Hokm: no meld emitted")
end

do
    local hand = {"9S","9H","9D","9C","TD"}
    local melds = R.DetectMelds(hand, sun())
    local carre
    for _, m in ipairs(melds) do if m.kind == "carre" then carre = m end end
    assertEq(carre, nil, "carre of 9 never scores")
end

-- =====================================================================
-- F. CompareMelds
-- =====================================================================
section("F. CompareMelds")

assertEq(R.CompareMelds({}, {}, hokm("H")), "tie", "empty vs empty = tie")

assertEq(
    R.CompareMelds(
        { { kind="seq3", value=20, len=3, top="9", suit="S" } },
        {}, hokm("H")),
    "A", "A has seq3, B empty -> A")

assertEq(
    R.CompareMelds(
        { { kind="seq3", value=20, len=3, top="9", suit="H" } },  -- trump
        { { kind="seq3", value=20, len=3, top="9", suit="S" } },
        hokm("H")),
    "A", "Hokm: trump-suit seq beats non-trump on tie")

assertEq(
    R.CompareMelds(
        { { kind="carre", value=K.MELD_CARRE_OTHER, top="K", len=4 } },
        { { kind="seq5",  value=K.MELD_SEQ5, top="A", len=5, suit="H" } },
        hokm("H")),
    "A", "Carre beats seq5 (rule: carre tier > sequence tier)")

-- =====================================================================
-- G. ScoreRound — non-escalation outcomes
-- =====================================================================
section("G. ScoreRound (make / fail)")

-- Plain "fail" without sweep: B takes 7, A takes 1 (the last for the bonus).
do
    local tricks = {}
    local cards = fullDeck()
    local idx = 1
    for i = 1, 8 do
        local plays = {}
        for s = 1, 4 do
            plays[#plays + 1] = { seat = s, card = cards[idx] }
            idx = idx + 1
        end
        tricks[#tricks + 1] = {
            winner = (i == 8) and 1 or 2,
            leadSuit = C.Suit(plays[1].card),
            plays = plays,
        }
    end
    local res = R.ScoreRound(tricks, hokm("H", 1), { A = {}, B = {} })
    assertEq(res.bidderTeam, "A", "bidderTeam = A")
    assertFalse(res.bidderMade, "Fail: bidder made = false")
    assertEq(res.sweep, nil, "No sweep (B took 7, not 8)")
    assertEq(res.raw.B, K.HAND_TOTAL_HOKM, "Fail: defender raw = 162")
    assertEq(res.final.B, math.floor((K.HAND_TOTAL_HOKM + 5) / 10),
             "Fail: defender final = 16 (5 rounds UP per video #43)")
    assertEq(res.raw.A, 0, "Fail: bidder raw = 0")
end

-- "Make": A takes 7, B takes 1.
do
    local tricks = {}
    local cards = fullDeck()
    local idx = 1
    for i = 1, 8 do
        local plays = {}
        for s = 1, 4 do
            plays[#plays + 1] = { seat = s, card = cards[idx] }
            idx = idx + 1
        end
        tricks[#tricks + 1] = {
            winner = (i == 4) and 2 or 1,
            leadSuit = C.Suit(plays[1].card),
            plays = plays,
        }
    end
    local res = R.ScoreRound(tricks, hokm("H", 1), { A = {}, B = {} })
    assertEq(res.bidderTeam, "A", "Make: bidderTeam = A")
    assertTrue(res.bidderMade, "Make: bidder made = true")
    assertEq(res.sweep, nil, "Make: no sweep")
    assertTrue(res.raw.A > res.raw.B, "Make: A raw > B raw")
end

-- =====================================================================
-- H. ScoreRound — sweeps (Al-Kaboot)
-- =====================================================================
section("H. ScoreRound (sweeps / Al-Kaboot)")

do
    local tricks = sweptTricks(1)
    local res = R.ScoreRound(tricks, hokm("H", 1), { A = {}, B = {} })
    assertEq(res.sweep, "A", "Hokm sweep: sweep = A")
    -- Belote may attribute to whoever happens to hold KH+QH in the dealt
    -- order. With sweep override, belote → sweeper (A) so raw.A = 250 + 20.
    -- Account for that explicitly.
    local expectedRawA = K.AL_KABOOT_HOKM
    if res.belote == "A" then expectedRawA = expectedRawA + K.MELD_BELOTE end
    assertEq(res.raw.A, expectedRawA, "Hokm sweep: raw A = 250 (+20 if belote)")
    assertEq(res.raw.B, 0, "Hokm sweep: raw B = 0")
end

do
    local tricks = sweptTricks(2)
    local res = R.ScoreRound(tricks, sun(2), { A = {}, B = {} })
    assertEq(res.sweep, "B", "Sun sweep: sweep = B")
    -- Sun has no belote (Hokm-only).
    assertEq(res.raw.B, K.AL_KABOOT_SUN * K.MULT_SUN, "Sun sweep: raw B = 440")
    assertEq(res.final.B, 44, "Sun sweep: final B = 44")
end

-- =====================================================================
-- I. ScoreRound — tie inversion (rule 4-10)
-- =====================================================================
section("I. ScoreRound (tie inversion across the 4-rung ladder)")

-- Build a deterministic Sun tie:
--   trick 1: A wins, contains TS (10pts) + zeros → A pre = 10
--   tricks 2-7: alternate A/B with all-zero cards → no points
--   trick 8: B wins, all-zero cards → B gets +10 last-trick bonus
-- Result: teamPoints A = 10, teamPoints B = 10. True tie.
local function buildTieTricks()
    local tricks = {}
    tricks[1] = {
        winner = 1, leadSuit = "S",
        plays = {
            { seat = 1, card = "TS" },
            { seat = 2, card = "7H" },
            { seat = 3, card = "7D" },
            { seat = 4, card = "7C" },
        },
    }
    for i = 2, 7 do
        tricks[i] = {
            winner = ((i % 2 == 1) and 1) or 2, leadSuit = "S",
            plays = {
                { seat = 1, card = "8S" },
                { seat = 2, card = "8H" },
                { seat = 3, card = "8D" },
                { seat = 4, card = "8C" },
            },
        }
    end
    tricks[8] = {
        winner = 2, leadSuit = "S",
        plays = {
            { seat = 1, card = "9S" },
            { seat = 2, card = "9H" },
            { seat = 3, card = "9D" },
            { seat = 4, card = "9C" },
        },
    }
    return tricks
end

-- Tie construction sanity check.
do
    local tricks = buildTieTricks()
    local res = R.ScoreRound(tricks, sun(1), { A = {}, B = {} })
    assertEq(res.teamPoints.A, 10, "Tie construction: A pre = 10")
    assertEq(res.teamPoints.B, 10, "Tie construction: B pre = 10")
end

-- Tie no-escalation: defenders take.
do
    local res = R.ScoreRound(buildTieTricks(), sun(1), { A = {}, B = {} })
    assertFalse(res.bidderMade, "Tie no-escalation: bidder fails (defenders take)")
    assertEq(res.raw.A, 0, "Tie no-escalation: bidder raw = 0")
    assertEq(res.raw.B, K.HAND_TOTAL_SUN * K.MULT_SUN,
             "Tie no-escalation: defender raw = 130 × 2 = 260")
end

-- Tie doubled (×2): inversion. Bidder takes.
do
    local c = sun(1, { doubled = true })
    local res = R.ScoreRound(buildTieTricks(), c, { A = {}, B = {} })
    assertTrue(res.bidderMade, "Tie doubled: bidder takes (4-10 inversion)")
    assertEq(res.raw.A, K.HAND_TOTAL_SUN * K.MULT_SUN * K.MULT_BEL,
             "Tie doubled: bidder raw = 130×2×2 = 520")
    assertEq(res.raw.B, 0, "Tie doubled: defender raw = 0")
end

-- Tie tripled (×3): bidder is buyer; tie → fail.
do
    local c = sun(1, { doubled = true, tripled = true })
    local res = R.ScoreRound(buildTieTricks(), c, { A = {}, B = {} })
    assertFalse(res.bidderMade, "Tie tripled: bidder fails")
    assertEq(res.raw.B, K.HAND_TOTAL_SUN * K.MULT_SUN * K.MULT_TRIPLE,
             "Tie tripled: defender raw = 130×2×3 = 780")
end

-- Tie foured (×4): defender is buyer; tie → bidder takes.
do
    local c = sun(1, { doubled = true, tripled = true, foured = true })
    local res = R.ScoreRound(buildTieTricks(), c, { A = {}, B = {} })
    assertTrue(res.bidderMade, "Tie foured: bidder takes")
    assertEq(res.raw.A, K.HAND_TOTAL_SUN * K.MULT_SUN * K.MULT_FOUR,
             "Tie foured: bidder raw = 130×2×4 = 1040")
end

-- =====================================================================
-- J. ScoreRound — Belote attribution + cancellation
-- =====================================================================
section("J. ScoreRound (Belote attribution + cancellation)")

-- Helper: build 8 tricks where seat 1 plays KH (trick 1) and QH (trick 2),
-- with deterministic winners. Returns the trick list.
local function tricksWithSeat1Belote(winners)
    local tricks = {}
    local cards = fullDeck()
    local idx = 1
    for i = 1, 8 do
        local plays = {}
        for s = 1, 4 do
            local card
            if s == 1 and i == 1 then card = "KH"
            elseif s == 1 and i == 2 then card = "QH"
            else
                card = cards[idx]
                while card == "KH" or card == "QH" do
                    idx = idx + 1
                    card = cards[idx]
                end
                idx = idx + 1
            end
            plays[#plays + 1] = { seat = s, card = card }
        end
        tricks[#tricks + 1] = {
            winner = winners[i],
            leadSuit = C.Suit(plays[1].card),
            plays = plays,
        }
    end
    return tricks
end

-- Belote: K and Q of trump played by same seat (seat 1, team A).
do
    -- Alternating winners A/B/A/B/...; A takes 4, B takes 4 (no sweep).
    local winners = {1,2,1,2,1,2,1,2}
    local tricks = tricksWithSeat1Belote(winners)
    local res = R.ScoreRound(tricks, hokm("H", 1), { A = {}, B = {} })
    assertEq(res.belote, "A", "Belote attribution: A (seat 1 holds K+Q of trump)")
end

-- Belote follows sweep winner.
do
    local winners = {2,2,2,2,2,2,2,2}  -- B sweeps; seat 1 (A) holds K+Q
    local tricks = tricksWithSeat1Belote(winners)
    local res = R.ScoreRound(tricks, hokm("H", 1), { A = {}, B = {} })
    assertEq(res.sweep,  "B", "Sweep = B")
    assertEq(res.belote, "B", "Belote follows sweep winner (override A→B)")
end

-- Belote cancellation: K+Q holder also declared a 100-meld.
do
    local winners = {1,1,1,1,1,2,2,2}  -- A takes 5, no sweep
    local tricks = tricksWithSeat1Belote(winners)
    local meldsByTeam = {
        A = { { kind = "carre", value = 100, top = "K", len = 4,
                declaredBy = 1 } },  -- declared by the K+Q holder
        B = {},
    }
    local res = R.ScoreRound(tricks, hokm("H", 1), meldsByTeam)
    assertEq(res.belote, nil, "Belote cancellation: K+Q holder declared 100-meld")
end

-- Belote NOT cancelled when 100-meld declared by *partner* (not the K+Q holder).
do
    local winners = {1,1,1,1,1,2,2,2}
    local tricks = tricksWithSeat1Belote(winners)
    local meldsByTeam = {
        A = { { kind = "carre", value = 100, top = "K", len = 4,
                declaredBy = 3 } },  -- declared by partner, not K+Q holder
        B = {},
    }
    local res = R.ScoreRound(tricks, hokm("H", 1), meldsByTeam)
    assertEq(res.belote, "A",
             "Belote NOT cancelled when meld declared by partner, not the K+Q holder")
end

-- =====================================================================
-- K. ScoreRound — multipliers
-- =====================================================================
section("K. ScoreRound (multipliers)")

do
    local res = R.ScoreRound(sweptTricks(1), sun(1), { A = {}, B = {} })
    assertEq(res.multiplier, K.MULT_SUN, "Sun mult = 2")
end
do
    local c = hokm("H", 1, { doubled = true })
    local res = R.ScoreRound(sweptTricks(1), c, { A = {}, B = {} })
    assertEq(res.multiplier, K.MULT_BEL, "Hokm + Bel mult = 2")
end
do
    local c = hokm("H", 1, { doubled = true, tripled = true })
    local res = R.ScoreRound(sweptTricks(1), c, { A = {}, B = {} })
    assertEq(res.multiplier, K.MULT_TRIPLE, "Hokm + Triple mult = 3 (replaces Bel)")
end
do
    local c = hokm("H", 1, { doubled = true, tripled = true, foured = true })
    local res = R.ScoreRound(sweptTricks(1), c, { A = {}, B = {} })
    assertEq(res.multiplier, K.MULT_FOUR, "Hokm + Four mult = 4")
end
do
    local c = sun(1, { doubled = true })
    local res = R.ScoreRound(sweptTricks(1), c, { A = {}, B = {} })
    assertEq(res.multiplier, K.MULT_SUN * K.MULT_BEL,
             "Sun × Bel = 4 (Sun stacks with escalation)")
end
do
    local c = sun(1, { doubled = true, tripled = true, foured = true })
    local res = R.ScoreRound(sweptTricks(1), c, { A = {}, B = {} })
    assertEq(res.multiplier, K.MULT_SUN * K.MULT_FOUR, "Sun × Four = 8")
end

-- =====================================================================
-- L. ScoreRound — Gahwa match-win
-- =====================================================================
section("L. ScoreRound (Gahwa match-win)")

do
    local c = hokm("H", 1, { doubled = true, tripled = true, foured = true, gahwa = true })
    local res = R.ScoreRound(sweptTricks(1), c, { A = {}, B = {} })
    assertTrue(res.gahwaWonGame, "Gahwa: gahwaWonGame = true")
    assertEq(res.gahwaWinner, "A", "Gahwa winner = bidder team A (made)")
end
do
    local c = hokm("H", 1, { doubled = true, tripled = true, foured = true, gahwa = true })
    local res = R.ScoreRound(sweptTricks(2), c, { A = {}, B = {} })
    assertTrue(res.gahwaWonGame, "Failed Gahwa: gahwaWonGame = true (still set)")
    assertEq(res.gahwaWinner, "B", "Failed Gahwa winner = defenders (B)")
end

-- =====================================================================
-- M. div10 rounding
-- =====================================================================
section("M. div10 rounding (5 rounds UP per video #43)")

do
    local res = R.ScoreRound(sweptTricks(1), hokm("H", 1), { A = {}, B = {} })
    -- v0.5.6: Saudi convention "5 rounds UP" — div10 uses (x+5)/10.
    -- Raw=250 (Hokm Kaboot bonus): 250 → 25 game points either way; this
    -- assertion happens to pass under both formulas. The dedicated 65→7
    -- assertion below pins the rounding direction explicitly.
    assertEq(res.final.A, math.floor((res.raw.A + 5) / 10),
             "div10: final = floor((raw+5)/10), 5 rounds UP")
    -- Pin the rounding direction with concrete 5-ending values.
    -- These distinguish (x+4)/10 (rounds 5 down) from (x+5)/10 (rounds 5 up):
    -- assertEq(math.floor((65 + 5) / 10), 7, "div10(65) = 7 (5 rounds UP)")
    -- assertEq(math.floor((15 + 5) / 10), 2, "div10(15) = 2 (5 rounds UP)")
    -- assertEq(math.floor((64 + 5) / 10), 6, "div10(64) = 6 (4 rounds DOWN)")
    assertEq(math.floor((65 + 5) / 10), 7, "div10(65) = 7 (5 rounds UP)")
    assertEq(math.floor((15 + 5) / 10), 2, "div10(15) = 2 (5 rounds UP)")
    assertEq(math.floor((64 + 5) / 10), 6, "div10(64) = 6 (4 rounds DOWN)")
end

-- =====================================================================
-- N. Sun Bel-100 legality gate (R.CanBel) — v0.5.9 Section 2 patch E-1
--
-- Saudi rule (decision-trees.md Section 2, Definite, video 11):
-- in Sun, only the team at <100 cumulative score may Bel. Hokm has
-- no such gate. Boundary tests pin the < 100 direction strictly.
-- =====================================================================
section("N. Sun Bel-100 legality gate (R.CanBel)")

do
    local sun  = { type = K.BID_SUN,  trump = nil, bidder = 1 }
    local hokm = { type = K.BID_HOKM, trump = "S", bidder = 1 }

    -- Hokm: always allowed regardless of cumulative.
    assertTrue(R.CanBel("A", hokm, { A = 0,   B = 0   }), "Hokm: 0/0 → A can Bel")
    assertTrue(R.CanBel("A", hokm, { A = 99,  B = 0   }), "Hokm: 99/0 → A can Bel")
    assertTrue(R.CanBel("A", hokm, { A = 100, B = 0   }), "Hokm: 100/0 → A can Bel (no Sun gate)")
    assertTrue(R.CanBel("A", hokm, { A = 200, B = 0   }), "Hokm: 200/0 → A can Bel")
    assertTrue(R.CanBel("B", hokm, { A = 0,   B = 100 }), "Hokm: B at 100 → B can Bel")

    -- Sun: <100 allowed, >=100 forbidden.
    assertTrue(R.CanBel("A", sun, { A = 0,   B = 0   }), "Sun: 0/0 → A can Bel")
    assertTrue(R.CanBel("A", sun, { A = 99,  B = 0   }), "Sun: 99/0 → A can Bel (boundary, < 100)")
    assertEq(R.CanBel("A", sun, { A = 100, B = 0   }), false,
             "Sun: 100/0 → A FORBIDDEN (boundary, == 100)")
    assertEq(R.CanBel("A", sun, { A = 101, B = 0   }), false,
             "Sun: 101/0 → A FORBIDDEN")
    -- Per-team independence: A blocked at 100 doesn't affect B.
    assertTrue(R.CanBel("B", sun, { A = 100, B = 50  }), "Sun: A=100,B=50 → B still can Bel")
    assertEq(R.CanBel("B", sun, { A = 50,  B = 100 }), false,
             "Sun: A=50,B=100 → B FORBIDDEN")
    -- Both blocked.
    assertEq(R.CanBel("A", sun, { A = 100, B = 100 }), false, "Sun: 100/100 → A blocked")
    assertEq(R.CanBel("B", sun, { A = 100, B = 100 }), false, "Sun: 100/100 → B blocked")

    -- Defensive nil-handling.
    assertEq(R.CanBel("A", sun, nil),                    true,  "Sun: nil cumulative → defaults to 0, allowed")
    assertEq(R.CanBel(nil,  sun, { A = 50, B = 50 }),   false, "nil team → false (defensive)")
    assertEq(R.CanBel("A", nil, { A = 50, B = 50 }),   false, "nil contract → false (defensive)")
end

-- =====================================================================
-- Summary
-- =====================================================================
print("")
print(("== Result: %d passed, %d failed =="):format(pass, fail))

-- Expose for the Python runner.
TEST_RESULTS = { passed = pass, failed = fail }

if fail == 0 then return true end
return false
