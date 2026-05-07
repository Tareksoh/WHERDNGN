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

-- v1.0.10 (audit pass-2 B LOW-3): defensive nil-seat guard. Pre-fix
-- a nil seat fell through to the bare `return "B"` — silently
-- attributing nil ownership to team B. Not exploitable in production
-- (all current callers pass a validated seat), but the silent default
-- could mask a future bug where a misrouted call passes nil. Now nil
-- (or any non-1/2/3/4 input) returns nil so callers can branch on it.
function R.TeamOf(seat)
    if seat == 1 or seat == 3 then return "A" end
    if seat == 2 or seat == 4 then return "B" end
    return nil
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
function R.IsLegalPlay(card, hand, trick, contract, seat, akaCalled)
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

    -- v0.10.2 M4 — AKA-receiver relief (J-066/J-067 part 2,
    -- review_v0.10.0 xref_X2_aka.md B1+B5). When partner has called
    -- AKA on the led suit (banner: `s.akaCalled = {seat, suit}`),
    -- the receiver is exempt from must-trump-ruff: partner's lead
    -- card is the boss of the suit, so partner's team is winning
    -- the trick by default. The 10-substitutes-for-Ace semantic
    -- (J-067 part 1) collapses to the same rule — whichever AKA
    -- card is in play, partner's team treats the trick as locked.
    -- Caller passes `akaCalled` from S.s.akaCalled at live-play
    -- time; simulators pass nil and get the AKA-blind semantics.
    -- This relief applies BEFORE must-follow / must-trump checks
    -- so a void+trump receiver may discard freely.
    --
    -- v0.10.3 M4-extension — implicit-AKA relief (S6-6, video #18).
    -- Saudi convention: partner leading the bare A of a non-trump
    -- suit in Hokm IS the implicit AKA call ("ace + lead = I have
    -- the boss"). No MSG_AKA banner fires (Bot.PickAKA's r=="A"
    -- early-return at line ~3214). pickFollow detects this at
    -- Bot.lua:2475-2492 but the discards filter was still empty
    -- in the canonical void+trump case because legality didn't
    -- honor the implicit signal — same dead-code shape as the
    -- pre-v0.10.2 explicit-AKA bug. Detect from the lead card
    -- itself: partner-led + non-trump + Ace = same relief as
    -- explicit AKA. Symmetric closure to BotMaster.lua:830 fix.
    -- v0.10.4 E1 companion guard (review_v0.10.2 D-RedTeam-01:29-60,
    -- B-Net-05 F8a, HIGH): defense-in-depth — even if a malformed
    -- `s.akaCalled.suit == contract.trump` slipped past the wire-
    -- entry guard at Net.lua:3122, the relief gate refuses trump-
    -- suit AKA. AKA's semantic is "I have the boss of a non-trump
    -- suit"; trump-suit AKA is meaningless and must not grant
    -- ruff-suppression relief.
    local akaRelief = false
    if akaCalled and akaCalled.seat and akaCalled.suit
       and seat and R.Partner(seat) == akaCalled.seat
       and akaCalled.suit == leadSuit
       and contract and contract.type == K.BID_HOKM
       and akaCalled.suit ~= contract.trump then
        akaRelief = true
    end
    if not akaRelief and seat
       and contract and contract.type == K.BID_HOKM and contract.trump
       and leadSuit and leadSuit ~= contract.trump
       and trick.plays[1] then
        local lead = trick.plays[1]
        if lead.seat and R.Partner(seat) == lead.seat
           and C.Rank(lead.card) == "A"
           and C.Suit(lead.card) == leadSuit then
            akaRelief = true
        end
    end

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

    -- v0.10.2 M4 — AKA-receiver relief: when partner called AKA on
    -- the led suit, an opp may have over-trumped and now leads, but
    -- the receiver is still exempt from must-ruff per J-066/J-067.
    -- Discard freely.
    if akaRelief then return true end

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
    --   A in Hokm   -> 100 raw (One Hundred — treated like T/K/Q/J carré)
    --   A in Sun    -> 200 raw (post-v0.11.10 revert; the user-cited
    --                  Arabic name "الأربع مئة" / "Four Hundred"
    --                  refers to the post-multiplier value 200×Sun×2
    --                  = 400 effective, not the stored constant. Pipeline
    --                  yields 200 × Sun×2 / 10 = 40 nq).
    --   9, 8, 7     -> don't score (omitted from K.CARRE_RANKS for 9)
    --
    -- v0.10.0 X5 fix (review_v0.10.0/xref_X5_*.md): pre-v0.10.0 the
    -- Hokm-A branch had no `else` — `value` stayed nil and the meld
    -- was silently dropped. Per videos #32 line 245 + #38 line 61,
    -- four-Aces in Hokm scores 100 like the other carrés. The drop
    -- cascaded into bidder strict-majority threshold checks,
    -- R.CompareMelds winner-takes-all, AND the Belote-cancellation
    -- v0.9.0 M5 path (the holder's missing 100-meld left Belote
    -- uncancelled → silent +20 over-scoring).
    local byRank = {}
    for _, c in ipairs(hand) do
        local r = C.Rank(c)
        byRank[r] = (byRank[r] or 0) + 1
    end
    for rank, count in pairs(byRank) do
        if count == 4 and K.CARRE_RANKS[rank] then
            local value
            if rank == "A" then
                value = isSun and K.MELD_CARRE_A_SUN or K.MELD_CARRE_OTHER
            else
                value = K.MELD_CARRE_OTHER
            end
            local cards = {}
            for _, s in ipairs(K.SUITS) do cards[#cards + 1] = rank .. s end
            out[#out + 1] = {
                kind = "carre", value = value, top = rank, cards = cards, len = 4,
            }
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

-- v1.0.9 C#2: expose meld-rank computation for Bot.PickMelds Qaid
-- protection (skip declaring melds that lose to already-declared opp
-- melds). The internal `meldRank` orders melds the same way
-- `R.CompareMelds` does (carrés > sequences; sequences ordered by
-- length then top card; tie-breakers as documented).
--
-- v1.0.10 (audit pass-2 A MED-3): IMPORTANT — `R.MeldRank` returns
-- a strict ORDINAL value only. It does NOT apply the PDF Rule 2
-- dealer-right priority for tied-rank melds; equal-rank melds will
-- compare equal here. Callers that need to resolve a tied-rank
-- winner MUST call `R.CompareMelds(meldsA, meldsB, contract,
-- dealerSeat)` instead — that function knows the tiebreak rules.
-- `Bot.PickMelds` is fine using `R.MeldRank` directly because it
-- only needs strict-greater comparison (ride or skip), not winner
-- determination.
function R.MeldRank(m, contract)
    return meldRank(m, contract)
end

-- v1.0.9 (PDF Rule 2): tied-meld dealer-right priority. PDF text:
-- «في حال تساوى مشروعان متشابهان في القيمة فأفضلية النزول لمن على
-- يمين الموزع» — "If two equal-value melds tie, declaration priority
-- goes to the player on the dealer's right." Pre-v1.0.9 ties returned
-- "tie" → both teams scored 0 melds. Now: walk seats starting at
-- NextSeat(dealer) and the first seat with a declared meld of the
-- tied rank takes the win. Optional `dealerSeat` param preserves
-- back-compat for callers that don't have dealer context (they get
-- the original "tie" behavior).
function R.CompareMelds(meldsA, meldsB, contract, dealerSeat)
    local bA = bestMeld(meldsA or {}, contract)
    local bB = bestMeld(meldsB or {}, contract)
    if not bA and not bB then return "tie" end
    if not bA then return "B" end
    if not bB then return "A" end
    local rA, rB = meldRank(bA, contract), meldRank(bB, contract)
    if rA > rB then return "A"
    elseif rB > rA then return "B"
    else
        -- Tied rank — apply PDF dealer-right tiebreaker if dealer
        -- known. Walk seats starting from right-of-dealer; first
        -- seat declaring a top-rank meld wins for its team.
        if dealerSeat then
            local seat = (dealerSeat % 4) + 1  -- right of dealer
            for _ = 1, 4 do
                local team = R.TeamOf(seat)
                local lookList = (team == "A") and meldsA or meldsB
                for _, m in ipairs(lookList or {}) do
                    if m.declaredBy == seat
                       and meldRank(m, contract) == rA then
                        return team
                    end
                end
                seat = (seat % 4) + 1
            end
        end
        return "tie"
    end
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
-- v1.0.3 (L2): defensive recursion budget. Natural max depth is
-- bounded by total cards remaining (~32 = 8 tricks × 4 plays). A
-- corrupted hands table or contract.trump combo could in theory
-- create a non-terminating loop; the budget caps unchecked depth.
-- Failure mode: return false (deny SWA) — better to falsely-deny
-- than to hang the host on a malformed input. 200 is comfortably
-- above the natural max with margin for "every legal exists"
-- branching factor.
local SWA_RECURSION_BUDGET = 200

function R.IsValidSWA(callerSeat, hands, contract, trickState, _depth)
    if not callerSeat or not hands or not contract then return false end
    if not trickState then trickState = { plays = {}, leader = callerSeat } end
    -- v1.0.3 (L2): budget guard. _depth is internal recursion counter
    -- — defaults to 0 on first call, increments on each recursive
    -- call. Public callers don't need to pass it.
    _depth = (_depth or 0) + 1
    if _depth > SWA_RECURSION_BUDGET then return false end

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
        }, _depth)
    end

    -- Done: caller emptied their hand BETWEEN tricks (i.e. trick just
    -- closed in their favour and no cards remain). Claim succeeded.
    --
    -- v0.5.17 BUG fix: gate this on `#plays == 0` (between tricks).
    -- Pre-fix, this fired whenever caller's hand was empty regardless
    -- of trick state — which incorrectly returned `true` mid-trick
    -- when the caller plays their LAST card as the 1st/2nd/3rd play
    -- of the trick. Subsequent opponent ruffs (or partner over-takes)
    -- were never seen by the validator. The V14 audit fix earlier
    -- only addressed the 4th-play case (added `#plays == 4` branch
    -- ABOVE this); the 1st/2nd/3rd-play case was still broken.
    -- Discovered via Section O test failures O.2 + O.3.
    if #plays == 0 and (#(hands[callerSeat] or {})) == 0 then
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

    -- v0.5.17: Saudi-strict-strict SWA. The caller's claim must hold
    -- REGARDLESS of which legal card any other seat (partner OR
    -- opponent) plays. No "back-and-forth" cooperation with partner
    -- — partner is treated adversarially in the recursion. Combined
    -- with the per-trick `winner == callerSeat` check at line 366,
    -- this enforces: the caller alone wins every remaining trick
    -- under ANY legal play sequence. Partner may not over-take with
    -- a higher card; if partner CAN over-take in any legal play,
    -- the SWA fails.
    --
    -- v0.11.18 audit B6/M5 fix: existential branch when nextSeat IS
    -- the caller. Pre-fix the universal recursion required EVERY
    -- legal caller-card to preserve the SWA — but the caller will
    -- pick optimally on their own turn, not adversarially. This was
    -- an over-strict rejection: e.g., caller has 2 cards [J of trump,
    -- 7 of side] in Hokm, J wins the next trick, 7 doesn't — but the
    -- universal check rejected because 7 fails. Saudi convention:
    -- caller plays optimally; the claim must hold under SOME caller
    -- play (existential), AND under EVERY partner/opponent play
    -- (universal). Self-adversarial recursion was the bug.
    --
    -- Other-seat branches retain universal: partner may try to
    -- legally over-take, opponents may try every legal lead/follow.
    if nextSeat == callerSeat then
        for _, card in ipairs(legal) do
            local nh, ns = applyMove(card)
            if R.IsValidSWA(callerSeat, nh, contract, ns, _depth) then
                return true
            end
        end
        return false
    else
        for _, card in ipairs(legal) do
            local nh, ns = applyMove(card)
            if not R.IsValidSWA(callerSeat, nh, contract, ns, _depth) then
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

-- v0.5.9 Section 2 patch E-1: Sun Bel-100 legality gate
-- (decision-trees.md Section 2, "Bel is FORBIDDEN" row).
--
-- Saudi rule: in a Sun contract, only the team currently at <100
-- cumulative score may call Bel. Hokm has no such gate (الحكم مفتوح
-- في الدبل — "Hokm is open in the doubling"). Authoritative
-- predicate so Bot.PickDouble + Net._OnDouble + Net.LocalDouble all
-- gate on the same answer.
--
-- Returns true iff `team` may legally call Bel against `contract`,
-- given the current `cumulative` table (`{ A = N, B = N }`).
--
-- Sources: decision-trees.md Section 2 (Definite, video 11);
-- glossary.md "Bel (×2) legality gate".
function R.CanBel(team, contract, cumulative)
    if not contract or not team then return false end
    if contract.type ~= K.BID_SUN then
        return true                         -- Hokm: always allowed
    end
    -- Sun: SCORE-SPLIT, ROLE-IRRELEVANT.
    --
    -- v0.10.0 R1 fix (review_v0.10.0/reaudit_R1_bel100.md): three
    -- sources unanimous on the rule once parsed verbatim:
    --   • Video #11: "في الصن لازم يكون فريق 100 نقطه او اعلى والفريق
    --     الثاني يكون اقل من 100" + "الفريق اللي اقل من 100 لوحه حقيقيه
    --     يدبل لكن الفريق اللي فوق الميه ما يدبل"
    --   • PDF 02: "ولايحق للاعب ان يدبل خصمة الا بعد ان يتجاوز المئة اي
    --     101" — `يدبل خصمة` is verb + DIRECT OBJECT; opponent is the
    --     team being Bel'd, NOT the caller.
    --   • PDF 07: "ويكون الدبل للمتأخر فقط وهو الذي لم يتجاوز عدده 100"
    --     — Bel belongs to the trailing one only.
    --
    -- All three reduce to: caller.cum ≤ GATE AND opposite.cum > GATE.
    -- Bidder/defender role does not enter — only score position.
    --
    -- Pre-v0.9.2 was MISSING the dual-team check (only `mine < 100`).
    -- v0.9.2 #45 added the dual-team check but anchored on bidder/
    -- defender role, breaking the edge case where the bidder team is
    -- TRAILING (e.g., A=130, B=60, B bids Sun: B is the trailing side
    -- and per Saudi rule may Bel; v0.9.2 wrongly forbade this).
    --
    -- The three-predicate consistency story still holds: R.CanBel,
    -- Net._SunBelAllowed, and Bot.PickDouble must all use the same
    -- score-split predicate. `contract.bidder` is no longer consulted
    -- here (kept in the contract table for log-readability and other
    -- consumers, but harmless to omit).
    local mine     = (cumulative and cumulative[team]) or 0
    local otherTeam = (team == "A") and "B" or "A"
    local otherCum  = (cumulative and cumulative[otherTeam]) or 0
    if mine     >  K.SUN_BEL_CUMULATIVE_GATE then return false end
    if otherCum <= K.SUN_BEL_CUMULATIVE_GATE then return false end
    return true
end

-- v0.7 Sun-overcall predicate. Returns true iff `seat` is currently
-- eligible to act in the post-Hokm overcall window. Two action types:
--   • UPGRADE — only the bidder, only when the contract is Hokm AND
--     the R1 bid card (if any) was NOT an Ace. R2 contracts have no
--     bid card and the Ace-special rule does not apply.
--   • TAKE — any non-bidder seat may take the contract as their Sun.
-- Forced/Takweesh-recovery contracts (`contract.forced == true`) do
-- NOT trigger the overcall window; the predicate returns false for
-- every seat in that case.
-- Sun contracts also return false (overcall is Hokm→Sun only).
function R.CanOvercall(seat, contract, bidCard)
    if not seat or not contract then return false end
    if contract.type ~= K.BID_HOKM then return false end
    if contract.forced then return false end
    if seat == contract.bidder then
        -- Bidder UPGRADE option. Blocked when bid card was an Ace.
        if bidCard and C.Rank and C.Rank(bidCard) == "A" then
            return false
        end
        return true
    end
    -- Non-bidder TAKE option — always available.
    return true
end

-- v0.7 Sun-overcall resolution. Inputs:
--   decisions  : {[seat] = decision | nil}
--                Decision strings:
--                  "UPGRADE"          — bidder upgrades own Hokm to Sun
--                  "TAKE"             — non-bidder takes as Sun (legacy alias)
--                  "TAKE_HOKM_<suit>" — non-bidder takes as Hokm with trump
--                                       suit (v0.8). Suit ∈ {S,H,D,C} and
--                                       must NOT match bidder's current trump.
--                  "WAIVE"            — decline (also nil = WAIVE on timeout)
--   contract   : current contract table (Hokm).
--   bidCard    : the R1 bid card, or nil for R2.
--   dealerSeat : the dealer seat (1-4) — used to compute bid order.
-- Returns one of:
--   { taken = false }                                                   — Hokm stands.
--   { taken = true, by = N, type = "UPGRADE" }                          — bidder upgrade.
--   { taken = true, by = N, type = "TAKE" }                             — N takes as Sun.
--   { taken = true, by = N, type = "TAKE_HOKM", trump = "<suit>" }      — N takes as Hokm.
-- Priority: bidder UPGRADE wins if eligible & decided; otherwise
-- earliest-in-bid-order taking-decision among non-bidder seats wins
-- (TAKE and TAKE_HOKM_<suit> share priority; bid order is the
-- discriminator regardless of contract type chosen). Bid order starts
-- at the seat to dealer's right (Saudi anticlockwise convention) and
-- proceeds through 4 seats.
function R.ResolveOvercall(decisions, contract, bidCard, dealerSeat)
    if not contract or not decisions or not dealerSeat then
        return { taken = false }
    end
    local bidder = contract.bidder
    -- Bidder UPGRADE has top priority — provided the bidder is allowed
    -- to upgrade (Ace-special blocks them; CanOvercall encodes this).
    if bidder and decisions[bidder] == "UPGRADE"
       and R.CanOvercall(bidder, contract, bidCard) then
        return { taken = true, by = bidder, type = "UPGRADE" }
    end
    -- Non-bidder TAKE / TAKE_HOKM_<suit> in bid order.
    local s = R.NextSeat(dealerSeat)
    for _ = 1, 4 do
        if s ~= bidder and R.CanOvercall(s, contract, bidCard) then
            local d = decisions[s]
            if d == "TAKE" then
                return { taken = true, by = s, type = "TAKE" }
            elseif d and d:sub(1, 10) == "TAKE_HOKM_" then
                local suit = d:sub(11, 11)
                -- Validate suit and reject same-as-current-trump (no
                -- point taking the same Hokm). Invalid → treat as WAIVE.
                if (suit == "S" or suit == "H" or suit == "D" or suit == "C")
                   and suit ~= contract.trump then
                    return { taken = true, by = s, type = "TAKE_HOKM",
                             trump = suit }
                end
            end
        end
        s = R.NextSeat(s)
    end
    return { taken = false }
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

-- Belote-cancellation predicate (Saudi rule «100 يلتهم البلوت» / "100
-- subsumes belote"). Returns true iff `team` declared at least one
-- meld with value >= 100 — implying the +20 belote bonus is absorbed
-- into the 100-meld and should not be added.
--
-- v0.10.5 MED-1 fix (review_v0.10.2 SCORING_SUMMARY MED-1, S-Score-07):
-- pre-v0.10.5 the cancellation check diverged across 3 call sites:
--   • R.ScoreRound:769-777 used TEAM-level (the canonical post-v0.9.0
--     M5 form — partner's 100-meld also cancels)
--   • Net.HostResolveTakweesh:2278 used SAME-PLAYER-only check
--     (`m.declaredBy == kWho`)
--   • Net.HostResolveSWA:3001 used SAME-PLAYER-only check
-- Per «المشروع للفريق» the rule is team-level, not per-player. The
-- divergence over-credited the bidder team by +2 gp on Qaid-context
-- rounds where the bidder held K+Q-trump and the bidder's PARTNER
-- declared a quarte. Single helper consumed by all 3 sites.
function R.IsBeloteCancelled(team, meldsByTeam)
    if not team or not meldsByTeam then return false end
    local list = meldsByTeam[team]
    if not list then return false end
    for _, m in ipairs(list) do
        if (m.value or 0) >= 100 then
            return true
        end
    end
    return false
end

-- Game-end winner with H3 tiebreak (post-v0.8.6 canonical). Returns
-- "A" or "B" if either cumulative crossed `target`, else nil. When
-- both teams hit target simultaneously, applies the H3 tiebreak:
--   1. Gahwa winner (if `result.gahwaWinner` is set)
--   2. bidderMade side (bidder team if true, opp team if false)
--   3. Defensive fallback "A"
--
-- v0.10.5 MED-2 fix (review_v0.10.2 SCORING_SUMMARY MED-2, S-Score-08):
-- pre-v0.10.5 the tiebreak diverged across 3 call sites:
--   • Net.lua:1721-1750 (normal round-end) — canonical H3 tiebreak ✓
--   • Net.lua:2362-2372 (Takweesh) — pre-v0.8.6 raw bidder-team logic
--   • Net.lua:3091-3100 (SWA) — pre-v0.8.6 raw bidder-team logic
-- Both stale paths could award the match to the OFFENDER team on
-- Takweesh / invalid-SWA simultaneous-target hits. Shared helper.
--
-- `result` shape (subset used here):
--   { gahwaWinner = "A"|"B"|nil, bidderTeam = "A"|"B",
--     bidderMade = bool|nil }
function R.GameEndWinner(cumA, cumB, target, result)
    if not target then return nil end
    cumA = cumA or 0
    cumB = cumB or 0
    if cumA < target and cumB < target then return nil end
    if cumA >= target and cumB >= target then
        -- H3 tiebreak.
        if result and result.gahwaWinner then
            return result.gahwaWinner
        end
        if result and result.bidderTeam then
            if result.bidderMade then
                return result.bidderTeam
            else
                return (result.bidderTeam == "A") and "B" or "A"
            end
        end
        return "A"  -- defensive fallback
    end
    if cumA >= target then return "A" end
    return "B"
end

-- v1.0.9 (PDF Rule 2): added optional `dealerSeat` for tied-meld
-- dealer-right tiebreaker. Back-compat: nil dealer means CompareMelds
-- falls back to "tie" → both teams 0 melds (legacy behavior).
-- v1.0.11 (D HIGH-2): helper — does any sequence meld in trump suit
-- declared by `team` cover both K and Q of trump? Used by the Belote
-- announcement gate (PDF exception: «إذا كان البلوت مكشوف مع مشروع
-- متسلسل فيحسب حتى لو لم يُذكر»). Returns true if any team meld is a
-- sequence in trumpSuit whose card list contains K-of-trump AND
-- Q-of-trump.
local function teamSequenceCoversBelote(team, meldsByTeam, trumpSuit)
    if not team or not meldsByTeam or not trumpSuit then return false end
    local list = meldsByTeam[team]
    if not list then return false end
    for _, m in ipairs(list) do
        if (m.kind == "sequence" or m.kind == "seq3" or m.kind == "seq4"
            or m.kind == "seq5") and m.suit == trumpSuit then
            local hasK, hasQ = false, false
            for _, card in ipairs(m.cards or {}) do
                if C.Suit(card) == trumpSuit then
                    if     C.Rank(card) == "K" then hasK = true
                    elseif C.Rank(card) == "Q" then hasQ = true end
                end
            end
            if hasK and hasQ then return true end
        end
    end
    return false
end

-- v1.0.11 (D HIGH-2): expose helper for Net.lua's Qaid handlers
-- (HostResolveTakweesh + HostResolveSWA) which run their own Belote
-- detection and need the same PDF exception check.
R.TeamSequenceCoversBelote = teamSequenceCoversBelote

-- v1.0.11 (D HIGH-2 Belote announcement): added `beloteAnnounced`
-- as a 5th optional parameter — a `[seat] = true` table, the value
-- of `S.s.beloteAnnounced` at scoring time. When provided AND the
-- holder is NOT in the table, Belote counts only if the holder's
-- team has a sequence meld in trump suit that covers K+Q (PDF
-- exception). Legacy callers (no parameter) get the pre-v1.0.11
-- behavior — Belote always counts when detected.
function R.ScoreRound(tricks, contract, meldsByTeam, dealerSeat,
                      beloteAnnounced)
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

    -- v1.0.11 (D HIGH-2 Belote announcement gate). PDF rule:
    -- «يجب على اللاعب الذي لديه البلوت ذكره أثناء لعب الورقة الثانية
    --  وقبل نزولها على الأرض، أما إذا كان البلوت مكشوف مع مشروع
    --  متسلسل (سرا، خمسين، مائة) فيحسب حتى لو لم يُذكر»
    -- = "The Belote holder must announce on the second card of K/Q-of-
    --   trump play. EXCEPTION: if Belote is laid open with a sequence
    --   meld (Sera/50/100), it counts even without announcement."
    --
    -- Implementation: when `beloteAnnounced` is provided AND the K+Q
    -- holder is NOT in the announce-set, drop the bonus UNLESS the
    -- holder's team has a sequence meld in trump suit covering K+Q.
    -- Legacy callers (no `beloteAnnounced` arg) skip the gate
    -- entirely — pre-v1.0.11 behavior preserved.
    if belote and beloteAnnounced and kWho
       and not beloteAnnounced[kWho] then
        if not teamSequenceCoversBelote(belote, meldsByTeam,
                                         contract.trump) then
            belote = nil
            kWho = nil
        end
    end

    -- Al-kaboot: one team won all 8 tricks. Replaces normal scoring.
    --
    -- v0.10.5 HIGH-2 fix (review_v0.10.2 SCORING_SUMMARY HIGH-2,
    -- S-Score-06): two distinct cases by sweep direction —
    --
    --   FORWARD Al-Kaboot (bidder team sweeps): full bonus per
    --     `K.AL_KABOOT_HOKM`=250 / `K.AL_KABOOT_SUN`=220.
    --   REVERSE Al-Kaboot (defender team sweeps, الكبوت المقلوب):
    --     uniform `K.AL_KABOOT_REVERSE = 88` raw — gated on the
    --     bidder having led trick 1. If bidder didn't lead trick 1,
    --     fall through to normal scoring (no AK bonus). Per video
    --     #16 the asymmetry is canonical Saudi: forward-AK rewards
    --     the bidder for crushing; reverse-AK is a smaller payout
    --     that requires the bidder to have actively engaged.
    --
    -- Pre-v0.10.5 awarded 250/220 to ANY 8-trick sweeper regardless
    -- of bidder/defender, over-paying defender by ~16 gp/round
    -- (Hokm) or ~35 gp/round (Sun) — game-deciding in a 152-target
    -- match.
    local sweepTeam
    if trickCount.A == 8 then sweepTeam = "A"
    elseif trickCount.B == 8 then sweepTeam = "B" end

    local sweepIsBidderTeam = sweepTeam and (sweepTeam == bidderTeam) or false
    local sweepIsReverseAK = false
    if sweepTeam and not sweepIsBidderTeam then
        -- v1.0.12 (D HIGH-3 user-canonical): reverse Al-Kaboot rule.
        -- All four conditions must hold (per Saudi PDF text):
        --   1. Defender team swept (already verified — sweepTeam set
        --      and not bidder team)
        --   2. Bid is SUN (not Hokm)
        --   3. Bidder is on dealer's right (seat == NextSeat(dealer))
        --   4. Bidder has/had an Ace at any point during the round
        --      (played in any trick — the round is over, so all of
        --      bidder's 8 cards are in the trick history)
        --
        -- If any condition fails, the defender sweep falls through to
        -- normal scoring (regular contract-fail path: defender wins
        -- handTotal × cardMult). Pre-v1.0.12 this used a different
        -- single-source rule (bidder led trick 1, 88 raw). User
        -- supplied the canonical PDF text replacing that hypothesis.
        local sunBid       = (contract.type == K.BID_SUN)
        local dealerRight  = dealerSeat
                              and contract.bidder == ((dealerSeat % 4) + 1)
        local bidderHadAce = false
        if sunBid and dealerRight then
            for _, t in ipairs(tricks) do
                for _, p in ipairs(t.plays or {}) do
                    if p.seat == contract.bidder
                       and C.Rank(p.card) == "A" then
                        bidderHadAce = true
                        break
                    end
                end
                if bidderHadAce then break end
            end
        end
        if sunBid and dealerRight and bidderHadAce then
            sweepIsReverseAK = true
        else
            -- Conditions not met. Suppress sweepTeam so the cardA/cardB
            -- block below skips its sweep branch — defender sweep then
            -- falls through to the regular fail path.
            sweepTeam = nil
        end
    end

    -- v0.10.5 MED-4 fix (review_v0.10.2 SCORING_SUMMARY MED-4,
    -- S-Score-04 + B-Rules-02 F-01): apply Belote cancellation
    -- BEFORE the sweep-override. Pre-v0.10.5 ordering had the
    -- override flip Belote ownership to the sweeping team FIRST,
    -- then the cancellation walk read meldsByTeam for the
    -- (possibly-flipped) Belote owner. In rare configs where the
    -- K+Q-holder's team has a ≥100 meld AND the OTHER team
    -- sweeps, the override moved Belote to the sweeper before
    -- cancellation could fire on the original holder's team —
    -- net ~2 gp swing. The canonical order is:
    --   1. Detect Belote (K+Q same-seat in trump)
    --   2. Cancel if holder's TEAM has ≥100 meld (v0.9.0 M5)
    --   3. Apply sweep-override only if the cancellation didn't
    --      already null Belote
    -- This preserves the «100 subsumes belote» rule even when
    -- the holder's team is on the losing side of an Al-Kaboot.

    -- Belote cancellation (Gemini #8 audit fix, v0.9.0 M5 team-level
    -- promotion, v0.10.5 MED-1 shared helper): the 100-meld
    -- "subsumes" the belote when the holder's team declared a ≥100
    -- meld. Walk meldsByTeam of the BELOTE-HOLDER's team (pre-sweep-
    -- override), not the post-override owner. Helper extracted so
    -- Net.lua's Qaid handlers (Takweesh + SWA-invalid) use the same
    -- TEAM-level rule (pre-v0.10.5 they used same-player-only check).
    if belote and kWho and R.IsBeloteCancelled(belote, meldsByTeam) then
        belote = nil
    end

    -- Saudi sweep convention: the sweeping team takes EVERYTHING,
    -- including the +20 belote bonus. Pagat-strict would keep belote
    -- with the K+Q holder regardless, but the Saudi "winner takes all"
    -- reading covers belote too. Override here so the belote-add-to-raw
    -- below routes the bonus to the sweep winner. Only fires when an
    -- AK actually fires (sweepTeam still set after the reverse-AK
    -- gate above) AND Belote wasn't already cancelled by a ≥100 meld
    -- on the holder's team (per the reordered M5 above).
    if sweepTeam and belote and belote ~= sweepTeam then
        belote = sweepTeam
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
    local meldVerdict = R.CompareMelds(meldsByTeam.A, meldsByTeam.B,
                                        contract, dealerSeat)
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
        -- v0.10.0 R2 normalization: Sun has no Triple/Four/Gahwa rungs
        -- (canonical rule, all 3 sources). If any of those flags are
        -- set on a Sun contract (stale resync, hand-edited save, etc.),
        -- ignore them for inversion purposes too — Sun's only rung is
        -- doubled/Bel.
        local highest
        if contract.type == K.BID_SUN then
            highest = contract.doubled and "double" or "none"
        elseif contract.gahwa   then highest = "gahwa"
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
        -- v0.10.5 HIGH-2: branch on direction. Forward-AK pays the
        -- contract-specific bonus; reverse-AK pays the uniform 88.
        local bonus
        if sweepIsReverseAK then
            bonus = K.AL_KABOOT_REVERSE
        else
            bonus = (contract.type == K.BID_HOKM) and K.AL_KABOOT_HOKM
                                                  or  K.AL_KABOOT_SUN
        end
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
        local outcome = R.CompareMelds(meldsByTeam.A, meldsByTeam.B,
                                        contract, dealerSeat)
        if outcome == "A" then meldPoints.A = meldA
        elseif outcome == "B" then meldPoints.B = meldB end
    end

    -- v0.11.10 user-arbitrated authoritative rule (CHANGELOG v0.11.10):
    --   "sere is 4 points in sun and 2 in hokm, 50 is 10 points in
    --    sun and 5 in hokm, 100 is 20 points in sun and 10 in hokm,
    --    Carre-A is 40 points in sun and shifts to 10 in hokm as
    --    there is no carre-A in hokm."
    --
    -- Decoded: ALL melds (sequence, carré-other, carré-A) get the
    -- contract multiplier (Sun ×2) AND any active escalation mult
    -- (Bel ×2, Triple ×3, Four ×4, Gahwa ×4). Cards and melds are
    -- treated identically by the multiplier. ONLY Belote (K+Q of
    -- trump) is multiplier-immune (added post-mult below).
    --
    -- Math sanity: K.MELD_CARRE_A_SUN=200 raw × Sun×2 / 10 = 40 nq ✓
    --              K.MELD_SEQ3=20 raw × Sun×2 / 10 = 4 nq ✓
    --              K.MELD_SEQ4=50 raw × Sun×2 / 10 = 10 nq ✓
    --              K.MELD_SEQ5=100 raw × Sun×2 / 10 = 20 nq ✓
    --              K.MELD_CARRE_OTHER=100 raw × Hokm×1 / 10 = 10 nq ✓
    --
    -- v0.11.6 history (now superseded): briefly attempted "melds
    -- Sun-immune"; produced sere=2 / quarte=5 / quinte=10 / Carré-A=40
    -- — broke sequence values vs canonical. The video #43 worked
    -- examples (sere 20→4, quarte 50→10, quinte 100→20) and the
    -- user's authoritative rule statement are the canonical reference.
    -- v0.10.0 R5 history (now superseded): bumped K.MELD_CARRE_A_SUN
    -- 200→400; produced 80 nq for Carré-A (2× canonical). Both
    -- previous "fixes" were wrong; the original v0.4.x state (200 raw,
    -- full Sun×2 application) was correct all along.
    --
    -- v0.10.0 R2 defensive normalization preserved: Sun has NO
    -- Triple/Four/Gahwa rungs; stale flags on Sun collapse to Sun-Bel.
    -- v1.0.9 (D HIGH-1) PDF §5-6 fix: melds DO NOT cascade past Bel.
    -- PDF: «لا تضاعف المشاريع في حالة الثري والفور في الحكم» —
    -- "Melds DO NOT multiply in Triple (×3) or Four (×4) in Hokm."
    -- PDF §5-5 confirms melds DO multiply at Bel level: «تتضاعف
    -- نتيجة المشاريع في حال الدبل بالصن والحكم». So the cap is at
    -- the Bel multiplier; Triple/Four/Gahwa keep cards cascading
    -- but melds frozen at Bel level.
    --
    -- Pre-v1.0.9 (user-arbitrated v0.11.10): cards and melds both
    -- got the full cascade multiplier — contradicted PDF §5-6.
    -- v1.0.9 user re-arbitrated to follow PDF after seeing the
    -- official text.
    --
    -- cardMult = full cascade per the existing code path
    -- meldMult = capped at Bel level (×2 in Hokm, Sun×2 in Sun-no-bel,
    --            Sun×2×2 = ×4 in Sun-Bel)
    -- Belote (+20 K+Q-of-trump): independent post-everything,
    --                             multiplier-immune as before.
    local cardMult = K.MULT_BASE
    local meldMult = K.MULT_BASE
    if contract.type == K.BID_SUN then
        cardMult = cardMult * K.MULT_SUN
        meldMult = meldMult * K.MULT_SUN
        if contract.doubled then
            cardMult = cardMult * K.MULT_BEL
            meldMult = meldMult * K.MULT_BEL
        end
        -- intentionally ignore tripled/foured/gahwa on Sun (R2)
    else
        -- Hokm: cards cascade through all rungs.
        if     contract.gahwa   then cardMult = cardMult * K.MULT_FOUR
        elseif contract.foured  then cardMult = cardMult * K.MULT_FOUR
        elseif contract.tripled then cardMult = cardMult * K.MULT_TRIPLE
        elseif contract.doubled then cardMult = cardMult * K.MULT_BEL end
        -- Hokm melds: ×1 base, ×2 ONCE escalation reaches Bel; stays
        -- at ×2 for Triple/Four/Gahwa (PDF §5-6 cap).
        if contract.doubled or contract.tripled
           or contract.foured or contract.gahwa then
            meldMult = meldMult * K.MULT_BEL
        end
    end

    -- Cards get full cascade; melds get the Bel-capped multiplier.
    -- Belote: post-everything, fully immune (only meld type that's
    -- multiplier-immune).
    --
    -- v1.0.12 (D HIGH-3): reverse Al-Kaboot bonus is also multiplier-
    -- immune — the canonical PDF rule says "88 banta" flat regardless
    -- of Sun-bare or Sun-Bel'd contract state. K.AL_KABOOT_REVERSE
    -- (now 880) is the post-multiplier raw value. Defender melds still
    -- get meldMult (Sun×2 or Sun×2×Bel×2, capped per D HIGH-1).
    local cardMultEffective = sweepIsReverseAK and K.MULT_BASE or cardMult
    local rawA = (cardA * cardMultEffective) + ((meldPoints.A or 0) * meldMult)
    local rawB = (cardB * cardMultEffective) + ((meldPoints.B or 0) * meldMult)

    -- Belote: independent +20 raw, applied AFTER the multiplier.
    -- Pagat: "Baloot always 2 points unaffected" — Bel/Triple/Four/Sun multipliers
    -- do NOT scale the Belote bonus. Always +2 game points to that team.
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
    --
    -- v0.10.5 MED-3 fix (review_v0.10.2 SCORING_SUMMARY MED-3,
    -- S-Score-02 + S-Score-08): type-gate the Gahwa branch on
    -- HOKM. Sun has no Gahwa rung per "في الصن لايوجد الثري والفور
    -- والقهوة" (PDF 02 K-21 + L34 + video #11). The multiplier path
    -- (lines 904-913) and inversion path (825-832) BOTH defensively
    -- collapse Sun's stale tripled/foured/gahwa flags; this branch
    -- was missed. A stale `contract.gahwa = true` on a Sun contract
    -- — possible via incomplete state reset, resync, or hostile
    -- peer — would otherwise fire a spurious match-win for the
    -- bidder. Phase machine guards prevent normal state from
    -- setting gahwa=true on Sun, but state-corruption paths exist.
    local gahwaWonGame = false
    local gahwaWinner
    if contract.gahwa and contract.type == K.BID_HOKM then
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
        -- v1.0.9 (D HIGH-1): split into cardMult / meldMult per PDF
        -- §5-6. Legacy `multiplier` field aliases cardMult (consumer
        -- tests assert this is the contract multiplier for cards).
        multiplier    = cardMult,
        cardMultiplier = cardMult,
        meldMultiplier = meldMult,
        gahwaWonGame  = gahwaWonGame,
        gahwaWinner   = gahwaWinner,
        raw           = { A = rawA, B = rawB },
        final         = { A = div10(rawA), B = div10(rawB) },
    }
end
