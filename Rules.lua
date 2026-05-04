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

-- SWA (سوا) claim validation. The caller asserts they personally
-- will win EVERY remaining trick. Returns true if the claim is
-- guaranteed against any opponent strategy.
--
-- Implementation: full minimax over remaining plays. Caller's team
-- (caller + partner) is cooperative — partner picks plays to support
-- caller; opponents pick plays to break the claim. The claim is
-- valid iff there's a strategy for caller's team that wins every
-- remaining trick regardless of what opponents do.
--
-- "Caller wins" means literally: trick winner is the caller seat.
-- Partner taking a trick doesn't count — that's a stricter reading
-- consistent with the Saudi "I claim the rest" gesture (caller plays
-- their cards out and each one wins). It also rejects the easy
-- abuse of partner "saving" the claim.
--
-- Bounded search: the remaining game tree has at most ~5 cards per
-- seat × 4 seats with branching factor ≤ 4 (legal-play filter
-- shrinks it further). Worst case ~ thousands of nodes — fine for
-- a one-time host-side check at SWA call time.
--
-- Args:
--   callerSeat   — 1..4
--   hands        — { [1..4] = array of cards } current REMAINING
--   contract     — { type, trump, ... }
--   trickState   — { leadSuit, leader, plays } current trick state
--                  (leader is the seat that started this trick;
--                  plays may be empty or partial mid-trick)
function R.IsValidSWA(callerSeat, hands, contract, trickState)
    if not callerSeat or not hands or not contract then return false end
    if not trickState then trickState = { plays = {}, leader = callerSeat } end

    local plays = trickState.plays or {}
    local leadSuit = trickState.leadSuit
    local leader   = trickState.leader

    -- Re-audit fix V14: resolve a COMPLETE trick BEFORE the
    -- caller-empty short-circuit. Otherwise: if caller plays their
    -- last card as the 4th play of a trick they would actually LOSE
    -- (e.g. opponent already trumped in), `#hands[caller]==0` would
    -- trigger before `#plays==4` and the recursion would return true
    -- without ever calling CurrentTrickWinner — false-positive SWA.
    if #plays == 4 then
        local winner = R.CurrentTrickWinner(
            { leadSuit = leadSuit, plays = plays }, contract)
        if winner ~= callerSeat then return false end
        return R.IsValidSWA(callerSeat, hands, contract, {
            leader = callerSeat, leadSuit = nil, plays = {}
        })
    end

    -- Done: caller emptied their hand BETWEEN tricks (i.e. trick just
    -- closed in their favour and no cards remain). Claim succeeded.
    if (#(hands[callerSeat] or {})) == 0 then
        return true
    end

    -- Determine next seat to play.
    local nextSeat
    if #plays == 0 then
        nextSeat = leader
    else
        nextSeat = (plays[#plays].seat % 4) + 1
    end

    -- Build legal-play set for this seat.
    local trickProbe = { leadSuit = leadSuit, plays = plays }
    local legal = {}
    local hand = hands[nextSeat] or {}
    for _, c in ipairs(hand) do
        local ok = R.IsLegalPlay(c, hand, trickProbe, contract, nextSeat)
        if ok then legal[#legal + 1] = c end
    end
    if #legal == 0 then return false end  -- shouldn't happen

    local function applyMove(card)
        -- Build new state with `card` removed from nextSeat's hand
        -- and appended to plays. Shallow copies — recursion only
        -- inspects, doesn't mutate further.
        local newHands = {}
        for s = 1, 4 do
            local src = hands[s] or {}
            if s == nextSeat then
                local out = {}
                local removed = false
                for _, c in ipairs(src) do
                    if not removed and c == card then
                        removed = true
                    else
                        out[#out + 1] = c
                    end
                end
                newHands[s] = out
            else
                newHands[s] = src
            end
        end
        local newPlays = {}
        for _, p in ipairs(plays) do newPlays[#newPlays + 1] = p end
        newPlays[#newPlays + 1] = { seat = nextSeat, card = card }
        local newLead = leadSuit or C.Suit(card)
        return newHands, {
            leadSuit = newLead, leader = leader, plays = newPlays,
        }
    end

    local cooperative = (R.TeamOf(nextSeat) == R.TeamOf(callerSeat))
    if cooperative then
        -- Caller's team: claim is valid if SOME play leads to a win.
        for _, card in ipairs(legal) do
            local nh, ns = applyMove(card)
            if R.IsValidSWA(callerSeat, nh, contract, ns) then
                return true
            end
        end
        return false
    else
        -- Opponent: claim is valid only if EVERY play leads to a win.
        for _, card in ipairs(legal) do
            local nh, ns = applyMove(card)
            if not R.IsValidSWA(callerSeat, nh, contract, ns) then
                return false
            end
        end
        return true
    end
end

function R.SumMeldValue(list)
    local s = 0
    for _, m in ipairs(list or {}) do s = s + (m.value or 0) end
    return s
end

-- Round scoring -------------------------------------------------------

-- Inputs:
--   tricks: array of { plays, leadSuit, winner } - 8 entries
--   contract: { type, trump, bidder, doubled, tripled, foured, gahwa }
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
    --
    -- Saudi rule (per "ماهو البلوت في لعبة البلوت"): the +20 belote bonus
    -- is CANCELLED when the same holder also declared a meld of value
    -- ≥ 100 (sequence-of-5 or carré of T/K/Q/J/A). The 100-meld
    -- subsumes the belote — no double-counting. Sequences of 3/4 (≤50)
    -- and the bare belote stand on their own.
    local belote = nil
    local kWho  -- expose to outer scope for cancellation below
    if contract.type == K.BID_HOKM and contract.trump then
        local qWho
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
        else
            kWho = nil
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

    -- Belote cancellation (Gemini #8 audit fix): the 100-meld "subsumes"
    -- the belote ONLY when the meld and the belote both score for the
    -- same team. After the sweep override above moves belote to the
    -- sweeping team, the holder's 100-meld may no longer be relevant
    -- (sweeper discards loser's melds). Apply cancellation AFTER sweep
    -- so the +20 follows the sweep winner correctly. Cancel only if
    -- the team currently holding belote ALSO has a ≥100 meld declared
    -- by kWho (i.e., the K+Q holder is on the side scoring the belote).
    if belote and kWho and R.TeamOf(kWho) == belote then
        local list = (meldsByTeam and meldsByTeam[belote]) or {}
        for _, m in ipairs(list) do
            if m.declaredBy == kWho and (m.value or 0) >= 100 then
                belote = nil
                break
            end
        end
    end

    -- Saudi rule 4-2/4-3: bidder must STRICTLY beat defender's total.
    -- Equal totals = tie; tie default goes to defenders. Bidder's total
    -- includes tricks + (only the meld-winner team's) melds + their
    -- belote. ONLY THE MELD COMPARISON WINNER counts — the loser's
    -- declared melds drop to 0 even for the threshold check (matches
    -- the actual scoring branch below). Adding both teams' melds to
    -- both totals would be a wash for equal-meld cases, but when
    -- meld values are unequal (e.g. seq3=20 vs seq4=50, or trump
    -- tie-break favors one), summing them on both sides flips the
    -- threshold incorrectly.
    local beloteA = (belote == "A") and K.MELD_BELOTE or 0
    local beloteB = (belote == "B") and K.MELD_BELOTE or 0
    local meldVerdict = R.CompareMelds(meldsByTeam.A, meldsByTeam.B, contract)
    local effMeldA = (meldVerdict == "A") and meldA or 0
    local effMeldB = (meldVerdict == "B") and meldB or 0
    local bidderTotal = teamPoints[bidderTeam] +
        (bidderTeam == "A" and (effMeldA + beloteA) or (effMeldB + beloteB))
    local oppTotal = teamPoints[oppTeam] +
        (oppTeam == "A" and (effMeldA + beloteA) or (effMeldB + beloteB))

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
        -- v0.2.0+ chain (Bel-Re removed):
        --   no escalation     → bidder is buyer    → fail (def takes)
        --   doubled (Bel)     → defender is buyer  → take (bidder takes)
        --   tripled (Triple)  → bidder is buyer    → fail
        --   foured  (Four)    → defender is buyer  → take
        --   gahwa             → bidder is buyer    → fail
        --     (gahwa is normally short-circuit to match-win, so this
        --      tie path is only reached when ScoreRound is called from
        --      an SWA / takweesh penalty path that doesn't trigger
        --      the match-win branch.)
        local highest
        if     contract.gahwa   then highest = "gahwa"
        elseif contract.foured  then highest = "four"
        elseif contract.tripled then highest = "triple"
        elseif contract.doubled then highest = "double"
        else                         highest = "none" end
        if highest == "double" or highest == "four" then
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
        -- Failed contract: defender team takes the handTotal qaid
        -- penalty. Per Saudi rule "مشروعي لي ومشروعك لك" each team
        -- KEEPS their own declared melds (the same rule we already
        -- apply to qaid/takweesh and invalid-SWA per v0.4.3). The
        -- penalty is the handTotal × multiplier awarded to the
        -- winner; the loser's melds are NOT confiscated.
        --
        -- User-reported bug RCA: with Hokm Bel'd (×2) and the bidder
        -- team failing, the bidder team showed final = 0 even when
        -- they had declared a quarte (50 raw × 2 = 100 raw = 10 gp).
        -- Aligns this branch with the qaid path in Net.lua's
        -- HostResolveTakweesh / HostResolveSWA-invalid which already
        -- preserves each team's own melds.
        cardA = (oppTeam == "A") and handTotal or 0
        cardB = (oppTeam == "B") and handTotal or 0
        meldPoints.A = meldA
        meldPoints.B = meldB
    elseif outcome_kind == "take" then
        -- Doubled tie: rule 4-10 inversion. Bidder takes the entire
        -- handTotal — the doubler/buyer failed their commitment. Same
        -- meld-attribution rule as the fail branch above: each team
        -- keeps their own declared melds; only the handTotal qaid
        -- penalty flows to the winner. Without this, a defender that
        -- Bel'd and tied (rule 4-10 says they failed) lost ALL their
        -- declared melds — the user-reported "loser team gets 0
        -- should be 10" pattern.
        cardA = (bidderTeam == "A") and handTotal or 0
        cardB = (bidderTeam == "B") and handTotal or 0
        meldPoints.A = meldA
        meldPoints.B = meldB
    else
        -- Made: each team gets their card points. Meld winner-takes-all
        -- by best-meld comparison (now contract-aware so trump-suit
        -- sequences beat non-trump on equal length+top).
        cardA, cardB = teamPoints.A, teamPoints.B
        local outcome = R.CompareMelds(meldsByTeam.A, meldsByTeam.B, contract)
        if outcome == "A" then meldPoints.A = meldA
        elseif outcome == "B" then meldPoints.B = meldB end
    end

    -- Multipliers (v0.2.0+ canonical 4-rung): Sun stacks with the
    -- highest active escalation. Only one escalation multiplier
    -- applies — they replace each other rather than compound.
    --   Bel    ×2
    --   Triple ×3
    --   Four   ×4
    --   Gahwa  → match-win (special-cased below; mult kept at ×4 for
    --           any per-round computation, but the match-win branch
    --           overrides cumulative totals).
    local mult = K.MULT_BASE
    if contract.type == K.BID_SUN then mult = mult * K.MULT_SUN end
    if     contract.gahwa   then mult = mult * K.MULT_FOUR  -- ×4 baseline
    elseif contract.foured  then mult = mult * K.MULT_FOUR
    elseif contract.tripled then mult = mult * K.MULT_TRIPLE
    elseif contract.doubled then mult = mult * K.MULT_BEL end

    local rawA = (cardA + meldPoints.A) * mult
    local rawB = (cardB + meldPoints.B) * mult

    -- Belote: independent +20 raw, applied AFTER the multiplier.
    -- Pagat: "Baloot always 2 points unaffected" — Bel/Triple/Four/Sun multipliers
    -- do NOT scale the Belote bonus. Always +2 game points to that team.
    --
    -- Audit fix: do NOT mutate meldPoints with the belote bonus.
    -- meldPoints is exported in the result struct; if any caller
    -- recomputes a per-team total from (cardPts + meldPoints) * mult,
    -- a mutated meldPoints would double-apply the belote AND scale it
    -- by the multiplier, contradicting the "unaffected" rule above.
    -- The belote winner is exposed separately as result.belote.
    if belote == "A" then
        rawA = rawA + K.MELD_BELOTE
    elseif belote == "B" then
        rawB = rawB + K.MELD_BELOTE
    end

    -- Saudi convention: round to nearest 10, **"5 rounds UP"**,
    -- then /10. Per video #43 "حساب النقاط في البلوت للمبتدئين":
    -- 65 raw → 70, 67 raw → 70, 64 raw → 60. Earlier code rounded
    -- 5 DOWN (`(x + 4) / 10`); the corrected formula is `(x + 5) / 10`.
    local function div10(x) return math.floor((x + 5) / 10) end

    -- Gahwa MATCH-WIN branch (v0.2.0+, per "نظام الدبل في لعبة البلوت"):
    -- a successful Gahwa wins the entire match for the caller's team
    -- regardless of point delta. A failed Gahwa hands the match to
    -- defenders. Override the per-round delta to push cumulative-to-
    -- target by signaling a "match-win" flag the caller (Net.lua's
    -- HostStepAfterTrick) can read off the result struct.
    local gahwaWonGame = false
    local gahwaWinner
    if contract.gahwa then
        -- Caller's team = bidder team. They "win" if bidderMade
        -- (made or doubled-tie inversion), "lose" otherwise.
        if bidderMade then
            gahwaWinner = bidderTeam
        else
            gahwaWinner = oppTeam
        end
        gahwaWonGame = true
    end

    return {
        teamPoints    = teamPoints,
        meldPoints    = meldPoints,
        lastTrickTeam = lastTrickTeam,
        bidderTeam    = bidderTeam,
        bidderMade    = bidderMade,
        sweep         = sweepTeam,
        belote        = belote,
        multiplier    = mult,
        gahwaWonGame  = gahwaWonGame,
        gahwaWinner   = gahwaWinner,
        raw           = { A = rawA, B = rawB },
        final         = { A = div10(rawA), B = div10(rawB) },
    }
end
