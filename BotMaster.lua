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

-- Default number of determinizations. Scaled up in PickPlay for end-game.
local BASE_NUM_WORLDS = 30

-- Helper: identify cards a seat is likely to hold based on the contract.
local function getStrongCards(contract)
    local strong = {}
    if contract.type == K.BID_HOKM and contract.trump then
        local t = contract.trump
        strong["J"..t] = 50; strong["9"..t] = 40; strong["A"..t] = 30
        strong["T"..t] = 20; strong["K"..t] = 10; strong["Q"..t] = 10
        -- Side Aces
        for _, s in ipairs(K.SUITS) do
            if s ~= t then strong["A"..s] = 15 end
        end
    elseif contract.type == K.BID_SUN then
        for _, s in ipairs(K.SUITS) do
            strong["A"..s] = 40; strong["T"..s] = 30; strong["K"..s] = 10
        end
    end
    return strong
end

-- v0.5 H-2 helper: desire map for defender seats in a Hokm contract.
-- Defenders cluster non-trump Aces and Kings because the bidder
-- committed to trump strength — side-suit power cards tend to live
-- in non-bidder hands. Returns {} for SUN (no trump asymmetry).
--
-- Three bias tiers:
--   desire["A"..s] = 8     non-trump Ace (strong clustering)
--   desire["K"..s] = 4     non-trump King (secondary bias)
--   desire[s]      = true  activates `desire[suit] and 20` fallback for
--                          remaining cards in that suit, biasing 4+
--                          length onto defenders. Card-level A/K take
--                          precedence (checked first in pool loop).
local function getDefenderCards(contract)
    local desire = {}
    if not contract or contract.type ~= K.BID_HOKM or not contract.trump then
        return desire
    end
    local t = contract.trump
    for _, s in ipairs(K.SUITS) do
        if s ~= t then
            desire["A"..s] = 8
            desire["K"..s] = 4
            desire[s]      = true
        end
    end
    return desire
end

-- v0.5.1 H-3 helper: desire map for the BIDDER'S PARTNER seat in a
-- Hokm contract. Bidder's partner usually holds 2-3 trump cards
-- (the rest of the team's allotment after the bidder claimed J/9/A
-- via the bid). Without this bias, the sampler under-trumped the
-- partner ~50% of worlds and over-trumped defenders, distorting
-- cooperative trump-clearing rollouts. Returns {} for SUN.
--
--   desire[trump] = true   long-suit incentive: any remaining trump
--                          card weight 20 via the existing fallback
--   desire["A"..s] = 5     light non-trump-Ace bias (lighter than
--                          defender's 8 to avoid double-clustering
--                          all 3 side Aces away from defenders)
local function getPartnerCards(contract)
    local desire = {}
    if not contract or contract.type ~= K.BID_HOKM or not contract.trump then
        return desire
    end
    local t = contract.trump
    desire[t] = true
    for _, s in ipairs(K.SUITS) do
        if s ~= t then
            desire["A"..s] = 5
        end
    end
    return desire
end

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
-- with their inferred voids and likely hand strength (from bids).
local function sampleConsistentDeal(seat, unseen)
    local contract = S.s.contract
    local bidder = contract and contract.bidder
    local strong = getStrongCards(contract)
    -- v0.5 H-2: pre-compute defender desire once (shared by both
    -- defender seats). Defender = on opposing team AND not bidder.
    local defenderDesire = getDefenderCards(contract)
    -- v0.5.1 H-3: partner desire (trump-count bias). Distinct from
    -- the calling sampler's `partner` (R.Partner(seat)) — we want
    -- the BIDDER's partner regardless of who's calling.
    local partnerDesire = getPartnerCards(contract)
    local bidderPartner = bidder and R.Partner(bidder) or nil
    local partner = R.Partner(seat)
    local pMem = B.Bot._memory and B.Bot._memory[partner]
    local pSignalSuit = pMem and pMem.firstDiscard and pMem.firstDiscard.suit

    local sizes = {}
    for s = 1, 4 do
        if s ~= seat then sizes[s] = seatHandSize(s) end
    end

    local pinSeat, pinCard = nil, nil
    if contract and bidder and bidder ~= seat and S.s.bidCard then
        for _, c in ipairs(unseen) do
            if c == S.s.bidCard then
                pinSeat = bidder
                pinCard = S.s.bidCard
                break
            end
        end
    end

    -- 26th-audit fix (Codex Saudi Master finding #5): pin every
    -- unplayed card from a DECLARED MELD to its declarer. Melds
    -- expose exact cards (m.cards + m.declaredBy) — without pinning,
    -- the sampler can scatter "Hearts Tierce 7-8-9" cards across all
    -- four seats instead of keeping them in the declarer's hand,
    -- corrupting every rollout's view of who holds what.
    --
    -- Build a map: card -> declaring seat. Skip cards already played
    -- (they're in `seen` already and excluded from `unseen`). Skip
    -- the calling bot's own meld cards (they're in our hand, not
    -- unseen). The pinned-card list is consulted alongside pinCard
    -- (bid card) below.
    local meldPins = {}
    if S.s.meldsByTeam then
        for _, team in ipairs({ "A", "B" }) do
            for _, m in ipairs(S.s.meldsByTeam[team] or {}) do
                if m.declaredBy and m.declaredBy ~= seat
                   and m.cards then
                    for _, c in ipairs(m.cards) do
                        -- Only pin if still in unseen pool (not played).
                        for _, u in ipairs(unseen) do
                            if u == c then
                                meldPins[c] = m.declaredBy
                                break
                            end
                        end
                    end
                end
            end
        end
    end

    -- v0.5 H-1 fix: for Hokm contracts, hard-pin the J and 9 of trump to
    -- the bidder seat. They are structurally bidder-held (the bidder
    -- bought Hokm precisely because they hold these power cards). The
    -- baseline 70%-pickProb desire weighting still placed them on
    -- defenders ~30% of sampled worlds, inverting every rollout's value
    -- estimate for the bidder team. Three skip conditions all reduce to
    -- "is the card still in unseen?": already played → buildUnseen
    -- excludes; already in our hand → buildUnseen excludes; already
    -- covered by pinCard (the bid card IS the J or 9) → guarded below.
    if contract and contract.type == K.BID_HOKM and contract.trump and bidder then
        local trump = contract.trump
        for _, powerCard in ipairs({ "J" .. trump, "9" .. trump }) do
            if powerCard ~= pinCard and not meldPins[powerCard] then
                for _, u in ipairs(unseen) do
                    if u == powerCard then
                        meldPins[powerCard] = bidder
                        break
                    end
                end
            end
        end
    end

    local maxAttempts = 15
    for attempt = 1, maxAttempts do
        local pool = {}
        for _, c in ipairs(unseen) do
            if c ~= pinCard and not meldPins[c] then
                pool[#pool + 1] = c
            end
        end
        shuffle(pool)

        local deal = {}
        local ok = true
        local used = {}
        if pinCard then used[pinCard] = true end
        for c, _ in pairs(meldPins) do used[c] = true end

        -- Sequential deal with seat-specific biasing.
        for s = 1, 4 do
            if s == seat then
                deal[s] = (S.s.hostHands and S.s.hostHands[s]) or {}
            else
                local n = sizes[s]
                local voids = (B.Bot._memory and B.Bot._memory[s]
                               and B.Bot._memory[s].void) or {}
                local hand = {}
                if s == pinSeat and pinCard then hand[#hand + 1] = pinCard end
                -- Pre-place this seat's declared meld cards.
                for c, declarerSeat in pairs(meldPins) do
                    if declarerSeat == s then hand[#hand + 1] = c end
                end

                -- Phase 1: Biased pick from pool.
                -- Bidder gets strong cards; partner gets signaled suit.
                -- v0.5 H-2: defender seats now share defenderDesire
                -- (non-trump A/K clustering). Role determined by
                -- absolute team comparison so both defender seats get
                -- the same bias regardless of which seat is the
                -- sampler's caller.
                local isDefender = bidder ~= nil
                                   and R.TeamOf(s) ~= R.TeamOf(bidder)
                                   and s ~= bidder
                -- v0.5.1 H-3: bidder's partner gets trump-count bias.
                local isBidderPartner = bidderPartner ~= nil and s == bidderPartner
                local desire
                if     s == bidder        then desire = strong
                elseif isDefender         then desire = defenderDesire
                elseif isBidderPartner    then desire = partnerDesire
                else                           desire = {} end
                if s == partner and pSignalSuit then desire[pSignalSuit] = 1 end

                -- Audit Tier 4 (B-99): if this seat is `likelyKawesh`
                -- (all observed plays were rank 7/8/9), they probably
                -- DON'T hold strong cards — clear the desire map so
                -- the sampler doesn't pin J/9/A to a low-card hand.
                -- Audit Tier 4 (B-67): high aceLate count means the
                -- seat is an A-hoarder; sampling ALL Aces to them is
                -- still plausible (they hoard them), but we down-weight
                -- the trump-J/9 pinning since they prefer side-suit
                -- hoarding. Keep desire intact but reduce desire weight
                -- by half via a flag below.
                --
                -- 50-agent audit fix (Wave 5/7/10 critical): only apply
                -- the desire-clear for OPPONENT seats. A teammate playing
                -- only 7/8/9 in tricks 1-3 is likely conserving cards
                -- (Fzloky low-discard signal), not signalling Kawesh —
                -- and clearing desire for the partner discards the
                -- Fzloky signal-suit bias (line 214 above) that the
                -- sampler depends on for partner-bias rollouts.
                local mem = B.Bot._memory and B.Bot._memory[s]
                local sIsOpponent = R.TeamOf(s) ~= R.TeamOf(seat)
                if mem and mem.likelyKawesh and sIsOpponent then
                    desire = {}
                end
                local style = B.Bot._partnerStyle and B.Bot._partnerStyle[s]
                local pickProb = 0.7
                if style and style.aceLate and style.aceLate >= 2 then
                    pickProb = 0.5  -- A-hoarder: less reliable strong-bias
                end

                local remainingInPool = {}
                for _, c in ipairs(pool) do
                    if #hand < n and not used[c] and not voids[C.Suit(c)] then
                        local weight = desire[c] or (desire[C.Suit(c)] and 20) or 0
                        -- 70% chance to take a "desired" card if weight exists
                        -- (50% if seat is A-hoarder).
                        if weight > 0 and math.random() < pickProb then
                            hand[#hand + 1] = c
                            used[c] = true
                        else
                            remainingInPool[#remainingInPool + 1] = c
                        end
                    else
                        remainingInPool[#remainingInPool + 1] = c
                    end
                end
                pool = remainingInPool

                -- Phase 2: Fill remaining slots for this seat.
                local leftovers = {}
                for _, c in ipairs(pool) do
                    if #hand < n and not used[c] and not voids[C.Suit(c)] then
                        hand[#hand + 1] = c
                        used[c] = true
                    else
                        leftovers[#leftovers + 1] = c
                    end
                end
                if #hand < n then ok = false; break end
                deal[s] = hand
                pool = leftovers
            end
        end
        if ok then return deal end
    end

    -- Fallback: uniform random deal ignoring voids.
    --
    -- 50-agent codebase audit fix (H-6 regression): the prior fallback
    -- ignored both meldPins AND voids. Voids are intentionally ignored
    -- here (it's the "give up trying to satisfy constraints" path), but
    -- meldPins MUST be respected — declared meld cards are exact known
    -- positions, not soft constraints. Without this, a Tierce 7-8-9 of
    -- Hearts declared by seat 3 could end up split across all four
    -- seats in the rollout deal, corrupting every rollout's view of who
    -- holds what. The primary path (above) handled meldPins correctly;
    -- the fallback was missing the same logic.
    local pool = {}
    for _, c in ipairs(unseen) do
        if c ~= pinCard and not meldPins[c] then
            pool[#pool + 1] = c
        end
    end
    shuffle(pool)
    local deal = {}
    local idx = 1
    for s = 1, 4 do
        if s == seat then
            deal[s] = (S.s.hostHands and S.s.hostHands[s]) or {}
        else
            local n = seatHandSize(s)
            local hand = {}
            if s == pinSeat and pinCard then hand[#hand + 1] = pinCard end
            -- Pre-place this seat's declared meld cards.
            for c, declarerSeat in pairs(meldPins) do
                if declarerSeat == s then hand[#hand + 1] = c end
            end
            while #hand < n and idx <= #pool do
                hand[#hand + 1] = pool[idx]
                idx = idx + 1
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
    -- Capture initial hands for meld detection. Reconstruct by combining
    -- sampled remaining cards with already-played cards for each seat.
    local initialHands = {}
    for s = 1, 4 do
        local h = {}
        for _, c in ipairs(world[s] or {}) do h[#h + 1] = c end
        for _, t in ipairs(S.s.tricks or {}) do
            for _, p in ipairs(t.plays or {}) do
                if p.seat == s then h[#h + 1] = p.card end
            end
        end
        if S.s.trick and S.s.trick.plays then
            for _, p in ipairs(S.s.trick.plays) do
                if p.seat == s then h[#h + 1] = p.card end
            end
        end
        initialHands[s] = h
    end

    local hands = {}
    for s = 1, 4 do
        local out = {}
        for _, c in ipairs(world[s] or {}) do out[#out + 1] = c end
        hands[s] = out
    end

    local simTricks = {}
    -- Load already completed tricks.
    for _, t in ipairs(S.s.tricks or {}) do simTricks[#simTricks + 1] = t end

    local currentTrick = {
        leadSuit = (S.s.trick and S.s.trick.leadSuit) or nil,
        plays = {},
    }
    if S.s.trick and S.s.trick.plays then
        for _, p in ipairs(S.s.trick.plays) do
            currentTrick.plays[#currentTrick.plays + 1] = { seat = p.seat, card = p.card }
        end
    end

    -- Apply our candidate card.
    local function removeCard(arr, c)
        for i, x in ipairs(arr) do
            if x == c then table.remove(arr, i); return end
        end
    end
    removeCard(hands[seat], card)
    if #currentTrick.plays == 0 then currentTrick.leadSuit = C.Suit(card) end
    currentTrick.plays[#currentTrick.plays + 1] = { seat = seat, card = card }

    -- Helper: pick a card using pro-level heuristics (Advanced-mirror).
    local function heuristicPick(s, trick)
        local hand = hands[s]
        local legal = {}
        for _, c in ipairs(hand) do
            if R.IsLegalPlay(c, hand, trick, contract, s) then
                legal[#legal + 1] = c
            end
        end
        if #legal == 0 then return nil end
        if #legal == 1 then return legal[1] end

        local function lowestRank(cards)
            local b, br = cards[1], math.huge
            for _, c in ipairs(cards) do
                local r = C.TrickRank(c, contract)
                if r < br then b, br = c, r end
            end
            return b
        end
        local function highestRank(cards)
            local b, br = cards[1], -1
            for _, c in ipairs(cards) do
                local r = C.TrickRank(c, contract)
                if r > br then b, br = c, r end
            end
            return b
        end

        local pos = #trick.plays + 1
        if pos > 1 then
            local curWinner = R.CurrentTrickWinner(trick, contract)
            local partnerWinning = curWinner and R.Partner(s) == curWinner
            if partnerWinning then
                -- Smother logic (from Bot.lua).
                if trick.leadSuit and (contract.type ~= K.BID_HOKM or trick.leadSuit ~= contract.trump) then
                    for _, c in ipairs(legal) do
                        local r = C.Rank(c)
                        if C.Suit(c) == trick.leadSuit and (r == "A" or r == "T") then
                            return c
                        end
                    end
                end
                return lowestRank(legal)
            end

            local winners = {}
            for _, c in ipairs(legal) do
                local tp = { leadSuit = trick.leadSuit, plays = {} }
                for _, p in ipairs(trick.plays) do tp.plays[#tp.plays + 1] = p end
                tp.plays[#tp.plays + 1] = { seat = s, card = c }
                if R.CurrentTrickWinner(tp, contract) == s then
                    winners[#winners + 1] = c
                end
            end

            if #winners > 0 then
                if pos == 2 then
                    -- Ducking logic: second hand low if not unbeatable.
                    local unbeatable = false
                    if contract.type == K.BID_SUN then
                        for _, c in ipairs(winners) do
                            if C.Rank(c) == "A" and C.Suit(c) == trick.leadSuit then
                                unbeatable = true; break
                            end
                        end
                    end
                    if unbeatable then return highestRank(winners) end
                    local nonWinners = {}
                    for _, c in ipairs(legal) do
                        local win = false
                        for _, w in ipairs(winners) do if w == c then win = true; break end end
                        if not win then nonWinners[#nonWinners + 1] = c end
                    end
                    if #nonWinners > 0 then return lowestRank(nonWinners) end
                elseif pos == 3 then
                    -- Third hand high (commit).
                    return highestRank(winners)
                end
                return lowestRank(winners)
            end
            return lowestRank(legal)
        end

        -- Lead heuristics (Advanced-mirror).
        --
        -- Audit C-5 fix: bidder-lead branch must select the highest TRUMP,
        -- not the highest legal card. `highestRank(legal)` returns whatever
        -- card has the highest TrickRank — and a non-trump Ace can outrank
        -- a depleted trump in the cross-scale comparison. The downstream
        -- `if C.IsTrump(t, contract)` check then fails silently and the
        -- rollout falls through to the side-suit branch, returning a
        -- random low side-suit card instead of pulling trump.
        local bidderTeam = R.TeamOf(contract.bidder)
        if contract.type == K.BID_HOKM and R.TeamOf(s) == bidderTeam then
            local trumpCards = {}
            for _, c in ipairs(legal) do
                if C.IsTrump(c, contract) then
                    trumpCards[#trumpCards + 1] = c
                end
            end
            if #trumpCards > 0 then
                return highestRank(trumpCards)
            end
        end
        local nonTrumps = {}
        for _, c in ipairs(legal) do
            if not C.IsTrump(c, contract) then nonTrumps[#nonTrumps + 1] = c end
        end
        if #nonTrumps > 0 then return lowestRank(nonTrumps) end
        return lowestRank(legal)
    end

    -- Play out the rest of the hand.
    while #simTricks < 8 do
        if #currentTrick.plays == 4 then
            local winner = R.CurrentTrickWinner(currentTrick, contract)
            if not winner then break end
            currentTrick.winner = winner
            simTricks[#simTricks + 1] = currentTrick
            if #simTricks == 8 then break end
            currentTrick = { leadSuit = nil, plays = {} }
            local nextSeat = winner
            local pick = heuristicPick(nextSeat, currentTrick)
            if not pick then break end
            removeCard(hands[nextSeat], pick)
            currentTrick.leadSuit = C.Suit(pick)
            currentTrick.plays[1] = { seat = nextSeat, card = pick }
        else
            local prev = currentTrick.plays[#currentTrick.plays]
            local nextSeat = (prev.seat % 4) + 1
            local pick = heuristicPick(nextSeat, currentTrick)
            if not pick then break end
            removeCard(hands[nextSeat], pick)
            currentTrick.plays[#currentTrick.plays + 1] = { seat = nextSeat, card = pick }
        end
    end

    -- Accurate round scoring including melds and make/fail cliffs.
    local meldsByTeam = { A = {}, B = {} }
    for s = 1, 4 do
        local team = R.TeamOf(s)
        local m = R.DetectMelds(initialHands[s], contract)
        for _, meld in ipairs(m) do
            meld.declaredBy = s
            table.insert(meldsByTeam[team], meld)
        end
    end

    local result = R.ScoreRound(simTricks, contract, meldsByTeam)
    -- 26th-audit fix (Codex Saudi Master critical #1 variant):
    -- return TEAM DIFF (us - them) rather than just our raw points.
    -- This puts both candidate-A "we make by 5" (+162) and candidate-
    -- B "we fail by 2" (-162) onto a single ranking axis where the
    -- contract-outcome cliff dominates raw-point fluctuation.
    -- Gahwa terminal: huge boost when our team wins the match.
    local oppTeam = (myTeam == "A") and "B" or "A"
    local diff = (result.raw[myTeam] or 0) - (result.raw[oppTeam] or 0)
    if result.gahwaWonGame and result.gahwaWinner then
        if result.gahwaWinner == myTeam then diff = diff + 10000
        else diff = diff - 10000 end
    end
    return diff
end

-- Public entry point: pick the best play using ISMCTS-flavoured
-- determinization sampling. Returns nil if not enough info, in
-- which case callers fall back to the lower-tier picker.
function BM.PickPlay(seat)
    if not BM.IsActive() then return nil end
    if not S.s.contract then return nil end
    -- v0.5 C-1 recursion guard: Bot.PickPlay now delegates to us when
    -- Saudi Master is active. heuristicPick is currently a local
    -- closure and doesn't call Bot.PickPlay, but we set the flag
    -- defensively so any future refactor that routes rollout play
    -- selection through Bot.PickPlay won't recursively re-enter ISMCTS.
    -- Save/restore (not just clear) in case nested host calls ever happen.
    local prevRollout = B.Bot._inRollout
    B.Bot._inRollout = true
    local function _restore(v) B.Bot._inRollout = prevRollout; return v end
    local hand = S.s.hostHands and S.s.hostHands[seat]
    if not hand or #hand == 0 then return _restore(nil) end
    -- Build legal-plays list.
    local trick = S.s.trick or { leadSuit = nil, plays = {} }
    local legal = {}
    for _, c in ipairs(hand) do
        local ok = R.IsLegalPlay(c, hand, trick, S.s.contract, seat)
        if ok then legal[#legal + 1] = c end
    end
    if #legal == 0 then return _restore(nil) end
    if #legal == 1 then return _restore(legal[1]) end

    local unseen = buildUnseen(seat)
    local scores = {}
    for _, c in ipairs(legal) do scores[c] = 0 end

    -- Dynamic world count: scale UP for early tricks (maximum uncertainty),
    -- scale DOWN as the round progresses toward a near-deterministic state.
    --
    -- Rationale: at trick 0-2 up to 8 cards are unknown across opponent
    -- hands; the state space is vast and more samples are needed to converge
    -- on a reliable card choice.  By trick 6+ only 2-4 total cards remain
    -- unseen; a single determinization nearly captures the true state, so
    -- BASE_NUM_WORLDS (30) is more than sufficient.  The previous code was
    -- inverted: it burned 100 worlds when the game was nearly decided and
    -- used only 30 when uncertainty was highest.
    local numTricks = #(S.s.tricks or {})
    local numWorlds
    if numTricks <= 2 then numWorlds = 100
    elseif numTricks <= 5 then numWorlds = 60
    else numWorlds = BASE_NUM_WORLDS end

    for w = 1, numWorlds do
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
    return _restore(best)
end
