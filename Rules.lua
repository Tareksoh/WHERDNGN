-- Pure game logic: legal-play validation, trick resolution,
-- meld detection / comparison, round scoring.
--
-- Stateless. Operates on snapshots passed by State.lua.

WHEREDNGN = WHEREDNGN or {}
local B = WHEREDNGN
B.Rules = B.Rules or {}
local R = B.Rules
local K = B.K
local C = B.Cards

-- Seat helpers ---------------------------------------------------------

-- 1->3, 2->4, 3->1, 4->2
function R.Partner(seat)
    if seat == 1 then return 3
    elseif seat == 2 then return 4
    elseif seat == 3 then return 1
    elseif seat == 4 then return 2 end
end

function R.NextSeat(seat) return (seat % 4) + 1 end

function R.TeamOf(seat)
    if seat == 1 or seat == 3 then return "A" end
    return "B"
end

-- Trick resolution -----------------------------------------------------

-- trick = { leadSuit = "H", plays = { {seat=1, card="JH"}, ... } }
-- Returns the seat currently winning, or nil if trick is empty.
function R.CurrentTrickWinner(trick, contract)
    if not trick or not trick.plays or #trick.plays == 0 then return nil end
    local plays = trick.plays
    local leadSuit = trick.leadSuit
    local bestSeat, bestRank = nil, -1
    local trumpPlayed = false
    if contract.type == K.BID_HOKM then
        for _, p in ipairs(plays) do
            if C.IsTrump(p.card, contract) then trumpPlayed = true; break end
        end
    end
    for _, p in ipairs(plays) do
        local s = C.Suit(p.card)
        local eligible
        if trumpPlayed then
            eligible = C.IsTrump(p.card, contract)
        else
            eligible = (s == leadSuit)
        end
        if eligible then
            local rk = C.TrickRank(p.card, contract)
            if rk > bestRank then bestRank, bestSeat = rk, p.seat end
        end
    end
    return bestSeat
end

-- Final winner once all 4 plays are in.
function R.TrickWinner(trick, contract)
    return R.CurrentTrickWinner(trick, contract)
end

-- Sum point value of all cards in a trick, given contract.
function R.TrickPoints(trick, contract)
    local total = 0
    for _, p in ipairs(trick.plays) do
        total = total + (C.PointValue(p.card, contract) or 0)
    end
    return total
end

-- Legal play ----------------------------------------------------------

-- Returns true if `card` is a legal play given `hand` (full hand including
-- the card), `trick` (current trick state), `contract`, and `seat`.
--
-- Saudi WHEREDNGN rules:
--  1. If trick is empty: any card.
--  2. If you have a card matching leadSuit: must follow suit.
--  3. Hokm only: if you can't follow lead and your partner is NOT
--     currently winning, you must trump. If you must trump and someone
--     already trumped above you, you must overcut if you can; otherwise
--     play any trump (under-trump) — but only if no overcut option exists.
--  4. Hokm: if you can't follow and partner IS winning, any card.
--  5. Sun: if you can't follow, any card.
function R.IsLegalPlay(card, hand, trick, contract, seat)
    if not C.IsValid(card) then return false, "invalid card" end
    -- card must be in hand
    local has = false
    for _, c in ipairs(hand) do if c == card then has = true; break end end
    if not has then return false, "not in hand" end

    if not trick or not trick.plays or #trick.plays == 0 then
        return true
    end

    local leadSuit = trick.leadSuit
    local cardSuit = C.Suit(card)

    -- Do we have any card of leadSuit?
    local hasLead = false
    for _, c in ipairs(hand) do
        if C.Suit(c) == leadSuit then hasLead = true; break end
    end
    if hasLead then
        if cardSuit ~= leadSuit then return false, "must follow suit" end
        -- Strict Saudi/Belote: when trump is led, you must overcut if
        -- you have a higher trump than what's been played so far —
        -- UNLESS your partner is the one currently winning the trick.
        -- Saudi rule: you never have to over-trump your own partner.
        -- This matches the analogous off-lead-trump case below
        -- (partner-winning shortcut) and is what players expect at the
        -- table.
        if contract.type == K.BID_HOKM and leadSuit == contract.trump then
            local curWinner = R.CurrentTrickWinner(trick, contract)
            if curWinner and seat and R.Partner(seat) == curWinner then
                return true
            end
            local highest = -1
            for _, p in ipairs(trick.plays) do
                if C.IsTrump(p.card, contract) then
                    local rk = C.TrickRank(p.card, contract)
                    if rk > highest then highest = rk end
                end
            end
            local canOvercut = false
            for _, c in ipairs(hand) do
                if C.IsTrump(c, contract) and C.TrickRank(c, contract) > highest then
                    canOvercut = true; break
                end
            end
            if canOvercut and C.TrickRank(card, contract) <= highest then
                return false, "must overcut"
            end
        end
        return true
    end

    -- Can't follow suit.
    if contract.type == K.BID_SUN then return true end  -- Sun: anything

    -- Hokm: check partner-winning shortcut.
    local curWinner = R.CurrentTrickWinner(trick, contract)
    if curWinner and R.Partner(seat) == curWinner then
        return true
    end

    -- Must trump if we have any trump.
    local hasTrump = false
    for _, c in ipairs(hand) do
        if C.IsTrump(c, contract) then hasTrump = true; break end
    end
    if not hasTrump then return true end  -- no trump, any card

    if not C.IsTrump(card, contract) then return false, "must trump" end

    -- Overcut requirement: find the highest trump already played.
    local highestTrumpRank = -1
    for _, p in ipairs(trick.plays) do
        if C.IsTrump(p.card, contract) then
            local rk = C.TrickRank(p.card, contract)
            if rk > highestTrumpRank then highestTrumpRank = rk end
        end
    end
    if highestTrumpRank < 0 then
        return true  -- no trump played yet, any trump OK
    end

    -- Can we overcut?
    local canOvercut = false
    for _, c in ipairs(hand) do
        if C.IsTrump(c, contract) and C.TrickRank(c, contract) > highestTrumpRank then
            canOvercut = true; break
        end
    end
    if canOvercut then
        if C.TrickRank(card, contract) > highestTrumpRank then return true end
        return false, "must overcut"
    end
    return true  -- can't overcut, any trump
end

-- Meld detection ------------------------------------------------------

-- Returns array of detected melds in `hand`, each shaped:
--   { kind="seq3"|"seq4"|"seq5"|"carre", value=N, top="A"|..., suit="H"|nil, cards={...} }
-- Sequences are by rank order 7,8,9,T,J,Q,K,A.
--
-- contract is required for Carré-of-Aces ("Four Hundred"): scores only
-- in Sun. Pass nil/empty contract to suppress conditional Aces.
function R.DetectMelds(hand, contract)
    local out = {}
    local isSun = contract and contract.type == K.BID_SUN

    -- Sequences per suit
    local bySuit = { S = {}, H = {}, D = {}, C = {} }
    for _, c in ipairs(hand) do
        local s = C.Suit(c)
        local idx = K.RANK_INDEX[C.Rank(c)]
        if s and idx then bySuit[s][#bySuit[s] + 1] = { idx = idx, card = c } end
    end
    for suit, list in pairs(bySuit) do
        table.sort(list, function(a, b) return a.idx < b.idx end)
        local i = 1
        while i <= #list do
            local j = i
            while j < #list and list[j + 1].idx == list[j].idx + 1 do j = j + 1 end
            local runLen = j - i + 1
            if runLen >= 3 then
                local cards = {}
                for k = i, j do cards[#cards + 1] = list[k].card end
                local kind, value
                if runLen == 3 then kind, value = "seq3", K.MELD_SEQ3
                elseif runLen == 4 then kind, value = "seq4", K.MELD_SEQ4
                else kind, value = "seq5", K.MELD_SEQ5 end
                out[#out + 1] = {
                    kind = kind, value = value, suit = suit,
                    top = K.RANKS[list[j].idx], len = runLen, cards = cards,
                }
            end
            i = j + 1
        end
    end

    -- Carré (Pagat-strict):
    --   T, K, Q, J  -> 100 raw (One Hundred)
    --   A           -> 200 raw, but ONLY in Sun (Four Hundred)
    --   9, 8, 7     -> don't score (omitted from K.CARRE_RANKS for 9)
    local byRank = {}
    for _, c in ipairs(hand) do
        local r = C.Rank(c)
        byRank[r] = (byRank[r] or 0) + 1
    end
    for rank, count in pairs(byRank) do
        if count == 4 and K.CARRE_RANKS[rank] then
            local value = nil
            if rank == "A" then
                if isSun then value = K.MELD_CARRE_A_SUN end
            else
                value = K.MELD_CARRE_OTHER
            end
            if value then
                local cards = {}
                for _, s in ipairs(K.SUITS) do cards[#cards + 1] = rank .. s end
                out[#out + 1] = {
                    kind = "carre", value = value, top = rank, cards = cards, len = 4,
                }
            end
        end
    end

    return out
end

-- Compare two meld lists. Returns "A", "B", or "tie".
-- Best-meld hierarchy (Pagat-strict Saudi):
--   1. Carré beats sequence at any value (carrés sort first).
--   2. Among carrés: by value (J > 9 > others — though only J/Q/K/T
--      score in Hokm and J is just 100 like the others; in Sun the
--      Aces carré is the highest at 200 raw).
--   3. Among sequences: longer wins, then higher top card.
--   4. TIE-BREAKER: trump-suit sequence beats non-trump (Hokm only).
--      Implemented as a small fractional bonus on meldRank.
local function meldRank(m, contract)
    if m.kind == "carre" then
        -- Carré tie-break by trick rank of the top card: when two
        -- carrés have equal raw value (e.g. K-carré vs J-carré, both
        -- 100), the carré with the higher trick-rank top wins. Uses
        -- the contract-aware TrickRank so a trump-J carré sits above
        -- a non-trump-J carré in Hokm. Bonus is small enough not to
        -- flip carré-vs-sequence comparisons.
        local rankBonus = 0
        if m.top and contract then
            -- Synthesize a probe card: any suit works for plain rank;
            -- when carré-of-trump is theoretically possible (4-of-suit)
            -- we use the trump suit so trump ordering kicks in.
            local probeSuit = (contract.type == K.BID_HOKM
                               and contract.trump) or "S"
            local rk = (B.Cards and B.Cards.TrickRank
                       and B.Cards.TrickRank(m.top .. probeSuit, contract))
                       or (K.RANK_INDEX[m.top] or 0)
            rankBonus = rk * 0.01
        end
        return 1000 + (m.value or 0) + rankBonus
    end
    local lenScore = (m.len or 3) * 10
    local topIdx = K.RANK_INDEX[m.top] or 0
    local trumpBonus = 0
    if contract and contract.type == K.BID_HOKM
       and m.suit and m.suit == contract.trump then
        trumpBonus = 0.5
    end
    return lenScore + topIdx + trumpBonus
end

local function bestMeld(list, contract)
    local best
    for _, m in ipairs(list) do
        if not best or meldRank(m, contract) > meldRank(best, contract) then
            best = m
        end
    end
    return best
end

function R.CompareMelds(meldsA, meldsB, contract)
    local bA = bestMeld(meldsA or {}, contract)
    local bB = bestMeld(meldsB or {}, contract)
    if not bA and not bB then return "tie" end
    if not bA then return "B" end
    if not bB then return "A" end
    local rA, rB = meldRank(bA, contract), meldRank(bB, contract)
    if rA > rB then return "A"
    elseif rB > rA then return "B"
    else return "tie" end
end

-- SWA (سوا) claim validation. The caller asserts they can win every
-- remaining trick. Returns true if the claim is supportable, false if
-- the host can immediately rule it false.
--
-- Sufficient (not necessary) condition we check:
--   • For each card in the caller's hand, that card is currently the
--     HIGHEST unplayed card of its suit in the global frontier.
--   • In Hokm: the caller's trump count is ≥ the highest opponent's
--     trump count, so the caller can over-cut any forced rough.
-- This rejects obviously-false claims (e.g. caller has the 7 of a
-- suit nobody else has played) without trying to do a full minimax.
-- Edge cases that "pass" but aren't truly winning are rare and the
-- caller bears the responsibility — same as a Saudi-table SWA.
--
-- callerHand: array of card strings (caller's REMAINING hand)
-- otherHands: { [seat] = array } for the three other seats (also
--             remaining cards only)
-- contract:   {type, trump, ...}
-- highestUnplayed: function(suit) → rank string of highest unplayed
--             card across all hands (caller's hand counted)
function R.IsValidSWA(callerHand, otherHands, contract, highestUnplayed)
    if not callerHand or #callerHand == 0 then return false end
    -- (a) Every caller card must currently be the highest unplayed
    -- of its suit. We use the supplied frontier function (built by
    -- the host using S.HighestUnplayedRank or equivalent).
    if highestUnplayed then
        for _, c in ipairs(callerHand) do
            local r = c:sub(1, 1)
            local su = c:sub(2, 2)
            if highestUnplayed(su) ~= r then return false end
        end
    end
    -- (b) Hokm trump check: caller must have at least as much trump
    -- as the heaviest opponent in trump, so they can over-cut a
    -- forced trump-in.
    if contract and contract.type == K.BID_HOKM and contract.trump then
        local trump = contract.trump
        local mine = 0
        for _, c in ipairs(callerHand) do
            if c:sub(2, 2) == trump then mine = mine + 1 end
        end
        local maxOpp = 0
        for _, hand in pairs(otherHands or {}) do
            local n = 0
            for _, c in ipairs(hand or {}) do
                if c:sub(2, 2) == trump then n = n + 1 end
            end
            if n > maxOpp then maxOpp = n end
        end
        if mine < maxOpp then return false end
    end
    return true
end

function R.SumMeldValue(list)
    local s = 0
    for _, m in ipairs(list or {}) do s = s + (m.value or 0) end
    return s
end

-- Round scoring -------------------------------------------------------

-- Inputs:
--   tricks: array of { plays, leadSuit, winner } - 8 entries
--   contract: { type, trump, bidder, doubled, redoubled }
--   meldsByTeam: { A = {...}, B = {...} } - declared melds (only)
--
-- Returns: {
--   teamPoints = { A = N, B = N },        -- card-trick points per team
--   meldPoints = { A = N, B = N },        -- declared melds awarded to winners
--   lastTrickTeam = "A"|"B",
--   bidderTeam = "A"|"B",
--   bidderMade = bool,
--   multiplier = N,
--   final = { A = N, B = N },              -- after multipliers + contract pen
-- }
function R.ScoreRound(tricks, contract, meldsByTeam)
    local teamPoints = { A = 0, B = 0 }
    local trickCount = { A = 0, B = 0 }
    local lastTrickTeam
    for i, t in ipairs(tricks) do
        local team = R.TeamOf(t.winner)
        local pts = R.TrickPoints(t, contract)
        teamPoints[team] = teamPoints[team] + pts
        trickCount[team] = trickCount[team] + 1
        if i == #tricks then
            lastTrickTeam = team
            teamPoints[team] = teamPoints[team] + K.LAST_TRICK_BONUS
        end
    end

    local handTotal   = (contract.type == K.BID_SUN) and K.HAND_TOTAL_SUN or K.HAND_TOTAL_HOKM
    local bidderTeam  = R.TeamOf(contract.bidder)
    local oppTeam     = bidderTeam == "A" and "B" or "A"

    local meldA = R.SumMeldValue(meldsByTeam.A)
    local meldB = R.SumMeldValue(meldsByTeam.B)
    local meldPoints = { A = 0, B = 0 }

    -- Belote (K+Q of trump in same hand) — Hokm only, scored independently
    -- of the contract result. Detect by scanning who played which card.
    local belote = nil
    if contract.type == K.BID_HOKM and contract.trump then
        local kWho, qWho
        for _, t in ipairs(tricks) do
            for _, p in ipairs(t.plays) do
                if C.Suit(p.card) == contract.trump then
                    if C.Rank(p.card) == "K" then kWho = p.seat end
                    if C.Rank(p.card) == "Q" then qWho = p.seat end
                end
            end
        end
        if kWho and qWho and kWho == qWho then
            belote = R.TeamOf(kWho)
        end
    end

    -- Al-kaboot: one team won all 8 tricks. Replaces normal scoring.
    local sweepTeam
    if trickCount.A == 8 then sweepTeam = "A"
    elseif trickCount.B == 8 then sweepTeam = "B" end

    -- Saudi sweep convention: the sweeping team takes EVERYTHING,
    -- including the +20 belote bonus. Pagat-strict would keep belote
    -- with the K+Q holder regardless, but the Saudi "winner takes all"
    -- reading covers belote too. Override here so the belote-add-to-raw
    -- below routes the bonus to the sweep winner.
    if sweepTeam and belote and belote ~= sweepTeam then
        belote = sweepTeam
    end

    -- Saudi rule 4-2/4-3: bidder must STRICTLY beat defender's total.
    -- Equal totals = tie; tie default goes to defenders. Bidder's total
    -- includes tricks + melds + belote (rule 4-5 explicitly carves out
    -- the "without belote" case, implying belote shifts the threshold).
    local beloteA = (belote == "A") and K.MELD_BELOTE or 0
    local beloteB = (belote == "B") and K.MELD_BELOTE or 0
    local bidderTotal = teamPoints[bidderTeam] +
        (bidderTeam == "A" and (meldA + beloteA) or (meldB + beloteB))
    local oppTotal = teamPoints[oppTeam] +
        (oppTeam == "A" and (meldA + beloteA) or (meldB + beloteB))

    -- Outcome resolution. Three branches:
    --   "make"  bidder strictly beat opp → normal scoring
    --   "fail"  defenders take handTotal + all melds (×mult)
    --   "take"  rule 4-10 doubled-tie inversion: bidder takes the full
    --           count because the doubler (now the "buyer") tied and
    --           thus failed
    local outcome_kind
    if bidderTotal > oppTotal then
        outcome_kind = "make"
    elseif bidderTotal < oppTotal then
        outcome_kind = "fail"
    else
        -- Tie. Saudi rule 4-10: count goes to non-buyer. The "buyer"
        -- alternates with each escalation level — whoever made the
        -- LAST decision is the current "buyer". Tie means that buyer
        -- failed, so the OTHER side takes the count.
        --   no escalation         → bidder is buyer       → fail (def takes)
        --   doubled               → defender is buyer     → take (bidder takes)
        --   redoubled             → bidder is buyer again → fail
        --   tripled (×8)          → defender is buyer     → take
        --   foured (×16)          → bidder is buyer       → fail
        --   gahwa (×32)           → defender is buyer     → take
        local highest
        if contract.gahwa     then highest = "gahwa"
        elseif contract.foured  then highest = "four"
        elseif contract.tripled then highest = "triple"
        elseif contract.redoubled then highest = "redouble"
        elseif contract.doubled   then highest = "double"
        else                            highest = "none" end
        if highest == "double" or highest == "triple" or highest == "gahwa" then
            outcome_kind = "take"   -- defender escalated last; tie → bidder takes
        else
            outcome_kind = "fail"
        end
    end

    local bidderMade = (outcome_kind == "make" or outcome_kind == "take")

    local cardA, cardB
    if sweepTeam then
        local bonus = (contract.type == K.BID_HOKM) and K.AL_KABOOT_HOKM or K.AL_KABOOT_SUN
        cardA = (sweepTeam == "A") and bonus or 0
        cardB = (sweepTeam == "B") and bonus or 0
        meldPoints.A = (sweepTeam == "A") and meldA or 0
        meldPoints.B = (sweepTeam == "B") and meldB or 0
    elseif outcome_kind == "fail" then
        -- "WHEREDNGN" / failed contract: defenders take all card points AND
        -- ALL melds (regardless of who declared). Bidder team scores 0.
        cardA = (oppTeam == "A") and handTotal or 0
        cardB = (oppTeam == "B") and handTotal or 0
        meldPoints[oppTeam]   = meldA + meldB
        meldPoints[bidderTeam] = 0
    elseif outcome_kind == "take" then
        -- Doubled tie: rule 4-10 inversion. Bidder takes the entire
        -- handTotal + all melds × mult.
        cardA = (bidderTeam == "A") and handTotal or 0
        cardB = (bidderTeam == "B") and handTotal or 0
        meldPoints[bidderTeam] = meldA + meldB
        meldPoints[oppTeam]    = 0
    else
        -- Made: each team gets their card points. Meld winner-takes-all
        -- by best-meld comparison (now contract-aware so trump-suit
        -- sequences beat non-trump on equal length+top).
        cardA, cardB = teamPoints.A, teamPoints.B
        local outcome = R.CompareMelds(meldsByTeam.A, meldsByTeam.B, contract)
        if outcome == "A" then meldPoints.A = meldA
        elseif outcome == "B" then meldPoints.B = meldB end
    end

    -- Multipliers: Sun stacks with the highest active escalation level
    -- (Bel ×2, Bel-Re ×4, Triple ×8, Four ×16, Gahwa ×32). Only one
    -- escalation multiplier applies — they replace each other rather
    -- than compound.
    local mult = K.MULT_BASE
    if contract.type == K.BID_SUN then mult = mult * K.MULT_SUN end
    if     contract.gahwa     then mult = mult * K.MULT_GAHWA
    elseif contract.foured    then mult = mult * K.MULT_FOUR
    elseif contract.tripled   then mult = mult * K.MULT_TRIPLE
    elseif contract.redoubled then mult = mult * K.MULT_BELRE
    elseif contract.doubled   then mult = mult * K.MULT_BEL end

    local rawA = (cardA + meldPoints.A) * mult
    local rawB = (cardB + meldPoints.B) * mult

    -- Belote: independent +20 raw, applied AFTER the multiplier.
    -- Pagat: "Baloot always 2 points unaffected" — Bel/Bel-Re/Sun multipliers
    -- do NOT scale the Belote bonus. Always +2 game points to that team.
    if belote == "A" then
        rawA = rawA + K.MELD_BELOTE
        meldPoints.A = meldPoints.A + K.MELD_BELOTE  -- diagnostic only
    elseif belote == "B" then
        rawB = rawB + K.MELD_BELOTE
        meldPoints.B = meldPoints.B + K.MELD_BELOTE
    end

    -- Saudi convention: round to nearest 10, "5 rounds down", then /10.
    local function div10(x) return math.floor((x + 4) / 10) end

    return {
        teamPoints    = teamPoints,
        meldPoints    = meldPoints,
        lastTrickTeam = lastTrickTeam,
        bidderTeam    = bidderTeam,
        bidderMade    = bidderMade,
        sweep         = sweepTeam,
        belote        = belote,
        multiplier    = mult,
        raw           = { A = rawA, B = rawB },
        final         = { A = div10(rawA), B = div10(rawB) },
    }
end
