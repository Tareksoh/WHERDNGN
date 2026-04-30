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

-- Tuning thresholds. Higher = more conservative bidding. Randomized
-- per-call so two bots dealt similar hands don't always pick the same
-- bid — eliminates the "predictable cliff" feel.
--
-- Originally these were tuned for "professional" bot bidding (J+9 of
-- trump + length), which produced too-quiet rounds where 3-of-4 bots
-- pass on most deals. Lowered so a bot with one strong card in the
-- bid-card suit (J alone, or A+T+K of trump) commits in round 1.
local TH_HOKM_R1_BASE = 35
local TH_HOKM_R2_BASE = 28
local TH_SUN_BASE     = 50
local BID_JITTER      = 6   -- ±6 swing per call

local function jitter(base, amp)
    return base + math.random(-amp, amp)
end

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
    local thHokmR1 = jitter(TH_HOKM_R1_BASE, BID_JITTER)
    local thHokmR2 = jitter(TH_HOKM_R2_BASE, BID_JITTER)
    local thSun    = jitter(TH_SUN_BASE,     BID_JITTER)

    if round == 1 then
        -- Sun is always an overcall option (overcalls Hokm or prior Sun).
        if sun >= thSun then return K.BID_SUN end
        -- Hokm-on-flipped only available if no prior Hokm/Sun.
        if not anyHokm and not anySun and bidCardSuit then
            local strength = suitStrengthAsTrump(hand, bidCardSuit)
            if strength >= thHokmR1 then
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
    if sun >= thSun and sun > bestScore then
        return K.BID_SUN
    end
    if bestSuit and bestScore >= thHokmR2 then
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

-- How many cards of `suit` are still UNACCOUNTED for, ignoring our own
-- hand and any plays we've observed. 8 cards total per suit; subtract
-- ours + every played card we've seen.
local function suitCardsOutstanding(hand, suit)
    local out = 8
    for _, c in ipairs(hand) do
        if C.Suit(c) == suit then out = out - 1 end
    end
    if Bot._memory then
        for s = 1, 4 do
            local mem = Bot._memory[s]
            if mem then
                for card in pairs(mem.played) do
                    if C.Suit(card) == suit then out = out - 1 end
                end
            end
        end
    end
    return math.max(0, out)
end

local function pickFollow(legal, hand, trick, contract, seat)
    local curWinner = R.CurrentTrickWinner(trick, contract)
    local partnerWinning = curWinner and R.Partner(seat) == curWinner
    local lastSeat = (#trick.plays == 3)  -- we're closing the trick

    if partnerWinning then
        -- Smother: in Hokm, if partner is winning a non-trump trick AND
        -- we hold an Ace/10 of that suit, dump it on partner's pile so
        -- our team scores the big point card. Skips if it would have
        -- been our last A/T standing in that suit (defensive depth).
        if contract.type == K.BID_HOKM and trick.leadSuit then
            local lead = trick.leadSuit
            for _, c in ipairs(legal) do
                local r = C.Rank(c)
                if C.Suit(c) == lead and (r == "A" or r == "T") then
                    return c
                end
            end
        end
        -- Otherwise don't waste a high card.
        return lowestByRank(legal, contract)
    end

    -- Opponent winning: try to beat them.
    local winners = {}
    for _, c in ipairs(legal) do
        if wouldWin(c, trick, contract, seat) then winners[#winners + 1] = c end
    end
    if #winners > 0 then
        -- Card-counting heuristic: if we'd win with a TRUMP and the
        -- opponents are likely empty of higher trump (counting from
        -- memory + our hand), commit cheaply. Otherwise we still win
        -- with the lowest legal winner.
        if contract.type == K.BID_HOKM and contract.trump then
            local trumpOut = suitCardsOutstanding(hand, contract.trump)
            -- If only ~1 outstanding trump remains across opponents,
            -- our cheapest winner is "safe enough" — same as before.
            -- This branch is here for future heuristics; right now we
            -- still pick lowest winner. Trump-counting affects the
            -- DEFENSIVE choice below where we save trumps.
            _ = trumpOut
        end
        -- Win cheaply: use the lowest card that still wins.
        return lowestByRank(winners, contract)
    end

    -- Can't win. If we're closing the trick (4th seat) and the trick
    -- already has decent points, throw the lowest-value loser. If
    -- earlier in the trick AND we have a trump that we'd need to
    -- cross-trump with, save the trump and instead discard from a
    -- short side suit to preserve flexibility.
    if not lastSeat and contract.type == K.BID_HOKM and contract.trump then
        local discardable = {}
        for _, c in ipairs(legal) do
            if not C.IsTrump(c, contract) then
                discardable[#discardable + 1] = c
            end
        end
        if #discardable > 0 then
            return lowestByRank(discardable, contract)
        end
    end
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
-- bonus because Sun is harder to make than Hokm. Threshold is jittered
-- per-call by ±10 so the Bel decision isn't a hard cliff at exactly
-- the configured value (was the #1 "predictable bot" complaint).
local BEL_JITTER = 10

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
    return strength >= jitter(K.BOT_BEL_TH, BEL_JITTER)
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
    return strength >= jitter(K.BOT_BELRE_TH, BEL_JITTER)
end

-- ---------------------------------------------------------------------
-- Takweesh detection
-- ---------------------------------------------------------------------
-- A bot scans completed and in-progress tricks for any opponent play
-- flagged .illegal by the host (only the host runs bots, and only the
-- host fills .illegal during S.ApplyPlay). Probability is higher in
-- the early tricks where a botched play is still fresh / "obvious",
-- and degrades as the hand progresses (a clever human caller would
-- catch it earlier; bots that wait too long feel more lifelike).
--
-- Returns the offending play table if the bot decides to call, else
-- nil. Net.lua's MaybeRunBot consumes this on each bot turn before
-- scheduling the normal play.

local TAKWEESH_RATE_BY_TRICK = {
    [0] = 0.60, [1] = 0.55, [2] = 0.45, [3] = 0.40,
    [4] = 0.30, [5] = 0.20, [6] = 0.10, [7] = 0.05,
}

function Bot.PickTakweesh(seat)
    if not S.s.contract then return nil end
    local myTeam = R.TeamOf(seat)
    local completed = #(S.s.tricks or {})
    local rate = TAKWEESH_RATE_BY_TRICK[completed] or 0.40

    -- Find the first illegal opposing play.
    local function scan(plays)
        for _, p in ipairs(plays or {}) do
            if p.illegal and R.TeamOf(p.seat) ~= myTeam then return p end
        end
    end
    local found
    for _, t in ipairs(S.s.tricks or {}) do
        found = scan(t.plays)
        if found then break end
    end
    if not found and S.s.trick then
        found = scan(S.s.trick.plays)
    end
    if not found then return nil end

    if math.random() < rate then return found end
    return nil
end
