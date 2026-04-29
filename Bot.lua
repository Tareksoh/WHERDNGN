-- Basic-heuristic WHEREDNGN AI.
--
-- All decisions are pure functions of the host's view of state plus
-- the seat's hand (read from s.hostHands[seat]). Driven from Net.lua's
-- MaybeRunBot when it's a bot's turn.
--
-- Design level: "basic" — bids on real strength, plays sensibly:
--   - Bid Hokm if strong J/9/A/length in a suit; Sun if hand has many
--     aces/tens; pass otherwise.
--   - Lead trump (high) if you're the bidder team in Hokm; else lead
--     a high non-trump.
--   - Following: try to beat the current winner, save high cards when
--     partner is winning, trump in if Hokm and lead suit isn't yours.
--   - Always declare detected melds.
--   - Never call Bel/Bel-Re (conservative).

WHEREDNGN = WHEREDNGN or {}
local B = WHEREDNGN
B.Bot = B.Bot or {}
local Bot = B.Bot
local K, C, R, S = B.K, B.Cards, B.Rules, B.State

-- Tuning thresholds. Higher = more conservative bidding.
local TH_HOKM_R1 = 50
local TH_HOKM_R2 = 38
local TH_SUN     = 60

-- ---------------------------------------------------------------------
-- Card memory + partner inference
-- ---------------------------------------------------------------------
-- Tracks every play observed (host-side, since bots run only on host)
-- so that the AI can:
--   - infer voids when a seat fails to follow suit
--   - count trumps remaining across all hands
--   - read partner's signals (low lead/discard ⇒ short or weak)
-- Reset on every new round via Bot.ResetMemory.

Bot._memory = nil

local function emptyMemory()
    local m = {}
    for s = 1, 4 do
        m[s] = {
            void   = { S = false, H = false, D = false, C = false },
            played = {},   -- [card] = true
        }
    end
    return m
end

function Bot.ResetMemory()
    Bot._memory = emptyMemory()
end

-- Called from Net.lua AFTER each ApplyPlay (host-only). leadSuit may be
-- nil if the play opens a new trick.
function Bot.OnPlayObserved(seat, card, leadSuit)
    if not Bot._memory then Bot.ResetMemory() end
    local mem = Bot._memory[seat]
    if not mem then return end
    mem.played[card] = true
    -- Void inference: a seat that didn't follow lead suit is void in it.
    local cardSuit = C.Suit(card)
    if leadSuit and cardSuit ~= leadSuit then
        mem.void[leadSuit] = true
    end
end

local function partnerVoidIn(seat, suit)
    if not Bot._memory then return false end
    local p = R.Partner(seat)
    return Bot._memory[p] and Bot._memory[p].void[suit] or false
end

local function opponentsVoidInAll(seat, suit)
    if not Bot._memory then return false end
    for opp = 1, 4 do
        if R.TeamOf(opp) ~= R.TeamOf(seat) then
            if not (Bot._memory[opp] and Bot._memory[opp].void[suit]) then
                return false
            end
        end
    end
    return true
end

-- ---------------------------------------------------------------------
-- Hand evaluation
-- ---------------------------------------------------------------------

-- Score how strong `suit` would be if it were trump.
-- Includes length bonus and the J+9 synergy.
local function suitStrengthAsTrump(hand, suit)
    local strength = 0
    local count = 0
    local hasJ, has9 = false, false
    for _, card in ipairs(hand) do
        if C.Suit(card) == suit then
            count = count + 1
            local r = C.Rank(card)
            if     r == "J" then hasJ = true; strength = strength + 20
            elseif r == "9" then has9 = true; strength = strength + 14
            elseif r == "A" then strength = strength + 11
            elseif r == "T" then strength = strength + 10
            elseif r == "K" then strength = strength + 4
            elseif r == "Q" then strength = strength + 3
            end
        end
    end
    strength = strength + math.max(0, count - 2) * 5
    if hasJ and has9 then strength = strength + 10 end
    return strength, count
end

-- Score for a Sun bid: high cards across all suits, length is irrelevant.
local function sunStrength(hand)
    local s = 0
    for _, card in ipairs(hand) do
        local r = C.Rank(card)
        if     r == "A" then s = s + 11
        elseif r == "T" then s = s + 10
        elseif r == "K" then s = s + 4
        elseif r == "Q" then s = s + 3
        elseif r == "J" then s = s + 2
        end
    end
    return s
end

-- ---------------------------------------------------------------------
-- Bidding
-- ---------------------------------------------------------------------

function Bot.PickBid(seat)
    local hand = S.s.hostHands and S.s.hostHands[seat]
    if not hand then return K.BID_PASS end
    local round = S.s.bidRound
    local bidCardSuit = S.s.bidCard and C.Suit(S.s.bidCard) or nil

    -- Inspect prior bids to know what's still available to us.
    local anyHokm, anySun = false, false
    for s2 = 1, 4 do
        local b = S.s.bids[s2]
        if b == K.BID_SUN then anySun = true
        elseif b and b:sub(1, 4) == K.BID_HOKM then anyHokm = true end
    end

    local sun = sunStrength(hand)

    if round == 1 then
        -- Sun is always an overcall option (overcalls Hokm or prior Sun).
        if sun >= TH_SUN then return K.BID_SUN end
        -- Hokm-on-flipped only available if no prior Hokm/Sun.
        if not anyHokm and not anySun and bidCardSuit then
            local strength = suitStrengthAsTrump(hand, bidCardSuit)
            if strength >= TH_HOKM_R1 then
                return K.BID_HOKM .. ":" .. bidCardSuit
            end
        end
        return K.BID_PASS
    end

    -- Round 2: pass / Hokm-non-flipped / Sun. First non-pass wins.
    local bestSuit, bestScore = nil, 0
    for _, suit in ipairs(K.SUITS) do
        if suit ~= bidCardSuit then
            local s = suitStrengthAsTrump(hand, suit)
            if s > bestScore then bestSuit, bestScore = suit, s end
        end
    end
    if sun >= TH_SUN and sun > bestScore then
        return K.BID_SUN
    end
    if bestSuit and bestScore >= TH_HOKM_R2 then
        return K.BID_HOKM .. ":" .. bestSuit
    end
    return K.BID_PASS
end

-- ---------------------------------------------------------------------
-- Play
-- ---------------------------------------------------------------------

local function lowestByRank(cards, contract)
    local best, bestR = cards[1], math.huge
    for _, c in ipairs(cards) do
        local r = C.TrickRank(c, contract)
        if r < bestR then best, bestR = c, r end
    end
    return best
end

local function highestByRank(cards, contract)
    local best, bestR = cards[1], -1
    for _, c in ipairs(cards) do
        local r = C.TrickRank(c, contract)
        if r > bestR then best, bestR = c, r end
    end
    return best
end

local function highestNonTrump(cards, contract)
    local best, bestR = nil, -1
    for _, c in ipairs(cards) do
        if not C.IsTrump(c, contract) then
            local r = C.TrickRank(c, contract)
            if r > bestR then best, bestR = c, r end
        end
    end
    return best
end

local function highestTrump(cards, contract)
    local best, bestR = nil, -1
    for _, c in ipairs(cards) do
        if C.IsTrump(c, contract) then
            local r = C.TrickRank(c, contract)
            if r > bestR then best, bestR = c, r end
        end
    end
    return best
end

local function legalPlaysFor(hand, trick, contract, seat)
    local out = {}
    for _, c in ipairs(hand) do
        local ok = R.IsLegalPlay(c, hand, trick, contract, seat)
        if ok then out[#out + 1] = c end
    end
    return out
end

-- Would playing `card` make `seat` win this trick?
local function wouldWin(card, trick, contract, seat)
    local plays = {}
    for _, p in ipairs(trick.plays) do plays[#plays + 1] = p end
    plays[#plays + 1] = { seat = seat, card = card }
    local sim = { leadSuit = trick.leadSuit, plays = plays }
    return R.CurrentTrickWinner(sim, contract) == seat
end

local function pickLead(legal, contract, seat)
    local myTeam = R.TeamOf(seat)
    -- Bidder team in Hokm: lead high trump to draw out opponents' trumps.
    if contract.type == K.BID_HOKM and myTeam == R.TeamOf(contract.bidder) then
        local t = highestTrump(legal, contract)
        if t then return t end
    end
    -- Otherwise prefer leading non-trump from a suit where opponents are
    -- known void (free Ace) or partner is NOT void (more chance partner
    -- can win it). Skip suits the partner is known void in.
    local nonTrumps = {}
    for _, c in ipairs(legal) do
        if not C.IsTrump(c, contract) then nonTrumps[#nonTrumps + 1] = c end
    end
    -- Sort by (opp-all-void boost, partner-not-void preferred, then trick rank desc)
    local function leadScore(c)
        local s = C.Suit(c)
        local r = C.TrickRank(c, contract)
        local oppAllVoid = opponentsVoidInAll(seat, s) and 100 or 0
        local partnerVoid = partnerVoidIn(seat, s) and -50 or 0
        return r + oppAllVoid + partnerVoid
    end
    if #nonTrumps > 0 then
        local best, bestS = nonTrumps[1], leadScore(nonTrumps[1])
        for _, c in ipairs(nonTrumps) do
            local s = leadScore(c)
            if s > bestS then best, bestS = c, s end
        end
        return best
    end
    return highestByRank(legal, contract)
end

local function pickFollow(legal, hand, trick, contract, seat)
    local curWinner = R.CurrentTrickWinner(trick, contract)
    local partnerWinning = curWinner and R.Partner(seat) == curWinner

    if partnerWinning then
        -- Don't waste a high card. Discard the lowest legal play.
        return lowestByRank(legal, contract)
    end

    -- Opponent winning: try to beat them.
    local winners = {}
    for _, c in ipairs(legal) do
        if wouldWin(c, trick, contract, seat) then winners[#winners + 1] = c end
    end
    if #winners > 0 then
        -- Win cheaply: use the lowest card that still wins.
        return lowestByRank(winners, contract)
    end

    -- Can't win. Throw the lowest-value loser.
    return lowestByRank(legal, contract)
end

function Bot.PickPlay(seat)
    local hand = S.s.hostHands and S.s.hostHands[seat]
    local trick = S.s.trick
    local contract = S.s.contract
    if not hand or not contract then return nil end

    local legal = legalPlaysFor(hand, trick, contract, seat)
    if #legal == 0 then return nil end
    if #legal == 1 then return legal[1] end

    if not trick or not trick.plays or #trick.plays == 0 then
        return pickLead(legal, contract, seat)
    end
    return pickFollow(legal, hand, trick, contract, seat)
end

-- ---------------------------------------------------------------------
-- Melds and double decisions
-- ---------------------------------------------------------------------

function Bot.PickMelds(seat)
    local hand = S.s.hostHands and S.s.hostHands[seat]
    if not hand then return {} end
    return R.DetectMelds(hand, S.s.contract)
end

-- Smarter Bel/Bel-Re — gated by hand strength so a weak defender
-- doesn't bel into stronger opposition. Sun contracts get a small
-- bonus because Sun is harder to make than Hokm.
function Bot.PickDouble(seat)
    local hand = S.s.hostHands and S.s.hostHands[seat]
    local contract = S.s.contract
    if not hand or not contract then return false end

    local strength = sunStrength(hand)
    if contract.type == K.BID_HOKM and contract.trump then
        -- Trump cards are an extra defensive resource.
        local trumpStr = suitStrengthAsTrump(hand, contract.trump)
        strength = strength + trumpStr * 0.5
    end
    if contract.type == K.BID_SUN then
        strength = strength + 10   -- bias: Sun is harder for the bidder
    end
    return strength >= K.BOT_BEL_TH
end

function Bot.PickRedouble(seat)
    local hand = S.s.hostHands and S.s.hostHands[seat]
    local contract = S.s.contract
    if not hand or not contract then return false end

    -- Bidder Bel-Res only with a clearly above-average hand.
    local strength = sunStrength(hand)
    if contract.type == K.BID_HOKM and contract.trump then
        strength = strength + suitStrengthAsTrump(hand, contract.trump)
    end
    return strength >= K.BOT_BELRE_TH
end
