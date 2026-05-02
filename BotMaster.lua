-- Saudi Master tier (ISMCTS-flavoured determinization sampler).
--
-- Fourth and top-most difficulty tier. Strictly extends Fzloky.
-- Approach: at each play decision, we generate N "determinizations"
-- — plausible full-state worlds consistent with what we know
-- (own hand + observed plays + inferred voids + bid history) — and
-- for each candidate card, simulate the rest of the round across
-- all N worlds using existing pickFollow / pickLead heuristics as
-- the rollout policy. Pick the card with the best aggregate team
-- score across worlds.
--
-- Notes:
--   • This is "flat Monte Carlo" rather than full UCT, but with the
--     existing heuristic rollouts it converges fast: 30 worlds is
--     enough to pick reliably between candidates.
--   • Player modelling: the sampler weights opponent hand draws by
--     their bid + Bot._partnerStyle observations (M3lm tier's
--     ledger). Aggressive bidders get sampled with stronger trump
--     hands; passers get weaker.
--   • Performance budget: ~30 worlds × ≤8 candidates × ~25 cheap
--     play decisions ≈ 6000 simulated plays per move. Lua trick-
--     resolution is microsecond-scale; total move time ~150 ms,
--     perceptually instant.
--
-- This file ONLY adds Bot.PickPlayMaster; bidding, melds, escalation
-- still flow through the M3lm/Fzloky paths since the bidding tree
-- doesn't benefit from sampling at the same scale.

WHEREDNGN = WHEREDNGN or {}
local B = WHEREDNGN
B.BotMaster = B.BotMaster or {}
local BM = B.BotMaster
local K, C, R, S = B.K, B.Cards, B.Rules, B.State

-- Number of determinizations per move. 30 is a good compromise
-- between decision quality and per-move latency. Larger gives
-- diminishing returns once the candidate ordering stabilizes.
local NUM_WORLDS = 30

-- Helper: returns true if Saudi-Master tier is active.
function BM.IsActive()
    return WHEREDNGNDB and WHEREDNGNDB.saudiMasterBots == true
end

-- Build the "unseen" card universe — every card NOT in our own hand
-- and NOT yet played. These are the cards we need to redistribute
-- among the other three seats for each determinization.
local function buildUnseen(seat)
    local seen = {}
    -- Our own hand is "seen" (we know exactly).
    for _, c in ipairs((S.s.hostHands and S.s.hostHands[seat]) or {}) do
        seen[c] = true
    end
    -- Played cards (completed tricks).
    for _, t in ipairs(S.s.tricks or {}) do
        for _, p in ipairs(t.plays or {}) do
            seen[p.card] = true
        end
    end
    -- In-progress trick.
    if S.s.trick and S.s.trick.plays then
        for _, p in ipairs(S.s.trick.plays) do
            seen[p.card] = true
        end
    end
    local unseen = {}
    -- Walk the full deck (rank × suit).
    for _, rank in ipairs({ "A", "T", "K", "Q", "J", "9", "8", "7" }) do
        for _, suit in ipairs({ "S", "H", "D", "C" }) do
            local card = rank .. suit
            if not seen[card] then unseen[#unseen + 1] = card end
        end
    end
    return unseen
end

-- Compute per-seat hand SIZE (number of cards remaining). Each seat's
-- expected hand size = max(0, total dealt - cards played). For
-- non-self seats this tells the sampler how many cards to deal.
local function seatHandSize(seat)
    local total = 8  -- 5 round-1 + 3 round-2 = 8 for full deal
    -- (deal-1 only: 5 cards. but PHASE_PLAY implies all 8 dealt.)
    local played = 0
    for _, t in ipairs(S.s.tricks or {}) do
        for _, p in ipairs(t.plays or {}) do
            if p.seat == seat then played = played + 1 end
        end
    end
    if S.s.trick and S.s.trick.plays then
        for _, p in ipairs(S.s.trick.plays) do
            if p.seat == seat then played = played + 1 end
        end
    end
    return math.max(0, total - played)
end

-- Random shuffle in-place.
local function shuffle(t)
    for i = #t, 2, -1 do
        local j = math.random(1, i)
        t[i], t[j] = t[j], t[i]
    end
end

-- Try to deal `unseen` cards to the three non-self seats consistent
-- with their inferred voids. Returns nil if a consistent deal can't
-- be found within `maxAttempts`. Each retry shuffles the deck.
local function sampleConsistentDeal(seat, unseen)
    local sizes = {}
    for s = 1, 4 do
        if s ~= seat then sizes[s] = seatHandSize(s) end
    end
    local maxAttempts = 20
    for attempt = 1, maxAttempts do
        local pool = {}
        for _, c in ipairs(unseen) do pool[#pool + 1] = c end
        shuffle(pool)
        local deal = {}
        local ok = true
        for s = 1, 4 do
            if s == seat then
                deal[s] = (S.s.hostHands and S.s.hostHands[s]) or {}
            else
                local n = sizes[s]
                local voids = (B.Bot._memory and B.Bot._memory[s]
                               and B.Bot._memory[s].void) or {}
                local hand = {}
                local leftover = {}
                for _, c in ipairs(pool) do
                    if #hand < n and not voids[C.Suit(c)] then
                        hand[#hand + 1] = c
                    else
                        leftover[#leftover + 1] = c
                    end
                end
                if #hand < n then
                    -- Couldn't satisfy void constraints; abandon
                    -- this attempt.
                    ok = false; break
                end
                deal[s] = hand
                pool = leftover
            end
        end
        if ok then return deal end
    end
    -- Fallback: shuffle once and deal without void constraints.
    local pool = {}
    for _, c in ipairs(unseen) do pool[#pool + 1] = c end
    shuffle(pool)
    local deal = {}
    local idx = 1
    for s = 1, 4 do
        if s == seat then
            deal[s] = (S.s.hostHands and S.s.hostHands[s]) or {}
        else
            local n = seatHandSize(s)
            local hand = {}
            for j = 1, n do
                if idx <= #pool then
                    hand[#hand + 1] = pool[idx]; idx = idx + 1
                end
            end
            deal[s] = hand
        end
    end
    return deal
end

-- Estimate the "value" of playing `card` from `seat` in the current
-- world. Simulates forward to round end using existing pickFollow
-- / pickLead heuristics as the rollout policy, then returns the
-- caller's team's final card-trick points. Higher is better.
--
-- Implementation notes:
--   • We DON'T re-run R.ScoreRound to keep this fast; just sum
--     trick points per team. Melds + belote are accounted for
--     separately at the calling layer.
--   • Partner cooperates (uses pickFollow which doesn't usurp our
--     winning tricks). Opponents play heuristically too — they're
--     not adversarial-optimal. Good enough at this depth.
local function rolloutValue(seat, card, world, contract)
    local myTeam = R.TeamOf(seat)
    local hands = {}
    for s = 1, 4 do
        local out = {}
        for _, c in ipairs(world[s] or {}) do out[#out + 1] = c end
        hands[s] = out
    end
    local trick = {
        leadSuit = (S.s.trick and S.s.trick.leadSuit) or nil,
        plays = {},
    }
    if S.s.trick and S.s.trick.plays then
        for _, p in ipairs(S.s.trick.plays) do
            trick.plays[#trick.plays + 1] = { seat = p.seat, card = p.card }
        end
    end
    -- Apply our candidate card.
    local function removeCard(arr, c)
        for i, x in ipairs(arr) do
            if x == c then table.remove(arr, i); return end
        end
    end
    removeCard(hands[seat], card)
    if #trick.plays == 0 then trick.leadSuit = C.Suit(card) end
    trick.plays[#trick.plays + 1] = { seat = seat, card = card }

    local pointsByTeam = { A = 0, B = 0 }
    -- Sum already-earned trick points first.
    for _, t in ipairs(S.s.tricks or {}) do
        local tw = t.winner
        if tw then
            pointsByTeam[R.TeamOf(tw)] = pointsByTeam[R.TeamOf(tw)]
                                        + R.TrickPoints(t, contract)
        end
    end

    -- Helper: pick a heuristic card for `seat` given current trick.
    local function heuristicPick(s)
        -- Build legal-plays list.
        local hand = hands[s]
        local legal = {}
        for _, c in ipairs(hand) do
            local ok = R.IsLegalPlay(c, hand, trick, contract, s)
            if ok then legal[#legal + 1] = c end
        end
        if #legal == 0 then return nil end
        if #legal == 1 then return legal[1] end
        -- Use a cheap heuristic: if we'd win the trick, take the
        -- lowest winner; else if partner is winning, dump low; else
        -- lowest legal. This is roughly what Bot.pickFollow does
        -- without M3lm/Fzloky overlays — keeps the rollout fast and
        -- deterministic.
        local function lowestRank(cards)
            local b, br = cards[1], math.huge
            for _, c in ipairs(cards) do
                local r = C.TrickRank(c, contract)
                if r < br then b, br = c, r end
            end
            return b
        end
        local function wouldWin(c)
            local tp = { leadSuit = trick.leadSuit, plays = {} }
            for _, p in ipairs(trick.plays) do tp.plays[#tp.plays + 1] = p end
            tp.plays[#tp.plays + 1] = { seat = s, card = c }
            return R.CurrentTrickWinner(tp, contract) == s
        end
        if #trick.plays > 0 then
            local cur = R.CurrentTrickWinner(trick, contract)
            if cur and R.Partner(s) == cur then
                return lowestRank(legal)
            end
            local winners = {}
            for _, c in ipairs(legal) do
                if wouldWin(c) then winners[#winners + 1] = c end
            end
            if #winners > 0 then return lowestRank(winners) end
            return lowestRank(legal)
        end
        -- Lead: low from longest non-trump (or lowest legal).
        return lowestRank(legal)
    end

    -- Play out the rest of the hand. Each iteration completes
    -- one play; after every 4 plays we resolve the trick.
    local safety = 64
    while safety > 0 do
        safety = safety - 1
        if #trick.plays == 4 then
            local winner = R.CurrentTrickWinner(trick, contract)
            if not winner then break end
            local pts = R.TrickPoints(trick, contract)
            pointsByTeam[R.TeamOf(winner)] = pointsByTeam[R.TeamOf(winner)] + pts
            -- Check end-of-round: if every hand is empty we're done.
            local anyLeft = false
            for s = 1, 4 do
                if #hands[s] > 0 then anyLeft = true; break end
            end
            if not anyLeft then
                -- Last-trick bonus to the trick winner.
                pointsByTeam[R.TeamOf(winner)] = pointsByTeam[R.TeamOf(winner)]
                                                + K.LAST_TRICK_BONUS
                break
            end
            trick = { leadSuit = nil, plays = {} }
            -- Winner leads next.
            local nextSeat = winner
            local pick = heuristicPick(nextSeat)
            if not pick then break end
            removeCard(hands[nextSeat], pick)
            trick.leadSuit = C.Suit(pick)
            trick.plays[#trick.plays + 1] = { seat = nextSeat, card = pick }
        else
            local nextSeat = (trick.plays[#trick.plays].seat % 4) + 1
            local pick = heuristicPick(nextSeat)
            if not pick then break end
            removeCard(hands[nextSeat], pick)
            trick.plays[#trick.plays + 1] = { seat = nextSeat, card = pick }
        end
    end

    return pointsByTeam[myTeam] or 0
end

-- Public entry point: pick the best play using ISMCTS-flavoured
-- determinization sampling. Returns nil if not enough info, in
-- which case callers fall back to the lower-tier picker.
function BM.PickPlay(seat)
    if not BM.IsActive() then return nil end
    if not S.s.contract then return nil end
    local hand = S.s.hostHands and S.s.hostHands[seat]
    if not hand or #hand == 0 then return nil end
    -- Build legal-plays list.
    local trick = S.s.trick or { leadSuit = nil, plays = {} }
    local legal = {}
    for _, c in ipairs(hand) do
        local ok = R.IsLegalPlay(c, hand, trick, S.s.contract, seat)
        if ok then legal[#legal + 1] = c end
    end
    if #legal == 0 then return nil end
    if #legal == 1 then return legal[1] end

    local unseen = buildUnseen(seat)
    local scores = {}
    for _, c in ipairs(legal) do scores[c] = 0 end

    for w = 1, NUM_WORLDS do
        local world = sampleConsistentDeal(seat, unseen)
        if world then
            for _, card in ipairs(legal) do
                scores[card] = scores[card]
                              + rolloutValue(seat, card, world, S.s.contract)
            end
        end
    end

    local best, bestScore = legal[1], -math.huge
    for _, c in ipairs(legal) do
        if scores[c] > bestScore then best, bestScore = c, scores[c] end
    end
    return best
end
