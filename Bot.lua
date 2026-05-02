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
--   - Bel/Triple/Four/Gahwa escalation is gated on strength thresholds.
--   - Triple-on-Ace pre-emption (الثالث) handled via Bot.PickPreempt.

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
-- pass on most deals. Then lowered too far so bots with marginal
-- hands committed too often (looked like they were bidding on bad
-- cards). Raised again to a sensible middle: bot needs J+kicker, or
-- 9+Ace, or A+T+K with length. Round-2 stricter so bots stop
-- bidding mediocre 3-card suits in the second window.
local TH_HOKM_R1_BASE = 42
local TH_HOKM_R2_BASE = 36
local TH_SUN_BASE     = 50
local BID_JITTER      = 6   -- ±6 swing per call

-- Advanced-bots feature flag. Off by default; toggle via
-- /baloot advanced or the lobby checkbox. When ON, the bots layer
-- in human-style heuristics: partner-bid awareness, score-position
-- modifiers, AKA self-call on lead, position-aware following,
-- J-of-trump step-function, side-suit-ace bonus, distribution-aware
-- Sun bidding, bidder/partner lead asymmetry, and opponent-bid
-- play hints. Each is gated individually so we can A/B compare in
-- play and partial fall-throughs are safe.
function Bot.IsAdvanced()
    -- All higher tiers strictly extend Advanced.
    return WHEREDNGNDB
       and (WHEREDNGNDB.advancedBots == true
            or WHEREDNGNDB.m3lmBots == true
            or WHEREDNGNDB.fzlokyBots == true
            or WHEREDNGNDB.saudiMasterBots == true)
end

-- M3lm (معلم — "master"). Pro-level heuristics layered on top of
-- Advanced: partner / opponent play-style ledger, match-point
-- urgency, and coordinated escalation. Strictly extends Advanced.
function Bot.IsM3lm()
    return WHEREDNGNDB
       and (WHEREDNGNDB.m3lmBots == true
            or WHEREDNGNDB.fzlokyBots == true
            or WHEREDNGNDB.saudiMasterBots == true)
end

-- Fzloky (فظلوكي). Signal-aware tier on top of M3lm. Reads partner's
-- first-discard (the rank thrown when first failing to follow lead)
-- as a high/low suit-preference signal and biases the bot's leading
-- choice toward / away from that suit accordingly.
function Bot.IsFzloky()
    return WHEREDNGNDB
       and (WHEREDNGNDB.fzlokyBots == true
            or WHEREDNGNDB.saudiMasterBots == true)
end

function Bot.IsSaudiMaster()
    return WHEREDNGNDB and WHEREDNGNDB.saudiMasterBots == true
end

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
            -- Fzloky: rank+suit of the FIRST card this seat threw
            -- when they failed to follow lead suit. High = "lead this",
            -- low = "don't lead this". Reset per round with the rest
            -- of memory.
            firstDiscard = nil,  -- {suit, rank}
            -- Per-suit AKA-already-signaled flag. Once a bot has
            -- announced "I hold the boss of X" by AKA, the partner
            -- knows. Re-announcing on subsequent leads of the same
            -- suit is noise. Reset per round.
            akaSent = { S = false, H = false, D = false, C = false },
        }
    end
    return m
end

function Bot.ResetMemory()
    Bot._memory = emptyMemory()
end

-- ---------------------------------------------------------------------
-- M3lm: partner play-style model
-- ---------------------------------------------------------------------
-- Per-seat aggregate counters, accumulated ACROSS the entire GAME
-- (not reset per round). Stable patterns let the bot calibrate to
-- known partner / opponent behaviour. Reset on Reset() / new game.
--
-- Counters:
--   bels       — how often this seat has Beled
--   trumpEarly — trump LEAD before trick 5 (aggressive tempo)
--   trumpLate  — trump LEAD from trick 5 onwards (saver style)
Bot._partnerStyle = nil

local function emptyStyle()
    local m = {}
    for s = 1, 4 do
        m[s] = {
            bels = 0,
            trumpEarly = 0, trumpLate = 0,
        }
    end
    return m
end

function Bot.ResetStyle()
    Bot._partnerStyle = emptyStyle()
end

-- Hook into Net.lua at contract finalization so the seat that Beled
-- this round adds to their lifetime counter. Net.lua calls this from
-- _OnDouble / _OnTriple / _OnFour / _OnGahwa.
function Bot.OnEscalation(seat)
    if not Bot._partnerStyle then Bot._partnerStyle = emptyStyle() end
    local m = Bot._partnerStyle[seat]
    if not m then return end
    m.bels = m.bels + 1
end

-- Convenience derived metrics. All return nil if we haven't seen
-- enough actions to be meaningful — caller should fall back to a
-- neutral default in that case. Currently unused by the picker
-- code; reserved for future M3lm-Plus heuristics that gate on
-- per-seat play style (e.g., bias trump-counting against a partner
-- known to leak trump early). Keep them around as the ledger is
-- already maintained by OnPlayObserved / OnEscalation.
local function styleBelTendency(seat)
    if not Bot._partnerStyle then return nil end
    local m = Bot._partnerStyle[seat]
    if not m or m.bels < 1 then return nil end
    if m.bels >= 2 then return 1 end
    return 0
end

local function styleTrumpTempo(seat)
    if not Bot._partnerStyle then return nil end
    local m = Bot._partnerStyle[seat]
    if not m or (m.trumpEarly + m.trumpLate) < 2 then return nil end
    if m.trumpEarly > m.trumpLate * 1.5 then return 1   end -- aggressive
    if m.trumpLate  > m.trumpEarly * 1.5 then return -1 end -- conservative
    return 0
end

-- Called from Net.lua AFTER each ApplyPlay (host-only). leadSuit may be
-- nil if the play opens a new trick.
function Bot.OnPlayObserved(seat, card, leadSuit)
    if not Bot._memory then Bot.ResetMemory() end
    local mem = Bot._memory[seat]
    if not mem then return end
    mem.played[card] = true
    -- Gemini #5 audit catch: if the play was ILLEGAL (host marked it
    -- p.illegal=true in S.ApplyPlay), the seat actually DID hold a
    -- card of leadSuit but chose not to play it. Inferring void from
    -- this poisons memory for the rest of the round. Skip void/discard
    -- inference for illegal plays — the void inference only applies
    -- when the off-suit play was legal (the seat truly was void).
    local lastPlay = S.s.trick and S.s.trick.plays
                     and S.s.trick.plays[#S.s.trick.plays]
    local wasIllegal = lastPlay and lastPlay.seat == seat
                       and lastPlay.card == card and lastPlay.illegal
    -- Void inference: a seat that didn't follow lead suit is void in it.
    local cardSuit = C.Suit(card)
    if not wasIllegal and leadSuit and cardSuit ~= leadSuit then
        mem.void[leadSuit] = true
        -- Fzloky: stash the FIRST off-suit discard. It's the
        -- moment a seat reveals what they care about — their
        -- suit-preference signal.
        if not mem.firstDiscard then
            mem.firstDiscard = { suit = cardSuit, rank = C.Rank(card) }
        end
    end

    -- M3lm: accumulate per-seat play-style stats across the full game.
    -- Cheap counters; we only USE them in M3lm-gated branches.
    if not Bot._partnerStyle then Bot._partnerStyle = emptyStyle() end
    local style = Bot._partnerStyle[seat]
    if not style then return end
    -- Trump tempo: did this seat LEAD trump (i.e., voluntarily
    -- spent it to draw out opponents' trump)? Lead = first play of
    -- a trick. A trump-RUFF in response to a non-trump lead by
    -- another seat is defensive, not tempo-spending — must NOT
    -- be counted here.
    local contract = S.s and S.s.contract
    local trickPlays = (S.s.trick and S.s.trick.plays) or {}
    if contract and contract.type == K.BID_HOKM and contract.trump
       and cardSuit == contract.trump
       and (#trickPlays == 1)  -- this is the LEAD (we're the only play in)
       and leadSuit == contract.trump then
        local trickNum = #(S.s.tricks or {}) + 1
        if trickNum <= 4 then
            style.trumpEarly = style.trumpEarly + 1
        else
            style.trumpLate = style.trumpLate + 1
        end
    end
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
--
-- Advanced (host opt-in) layers two more heuristics on top:
--   • J of trump is a step-function. A trump-bid hand with no J,
--     no 9+A pair, and fewer than 5 cards in the suit gets its
--     score multiplied by 0.4 — it's structurally un-biddable
--     even if the raw point sum looks OK.
--   • J+9 synergy bonus bumped from +10 to +18. Coinche convention
--     treats J+9 as a step jump, not a linear continuation.
local function suitStrengthAsTrump(hand, suit)
    local strength = 0
    local count = 0
    local hasJ, has9, hasA = false, false, false
    for _, card in ipairs(hand) do
        if C.Suit(card) == suit then
            count = count + 1
            local r = C.Rank(card)
            if     r == "J" then hasJ = true; strength = strength + 20
            elseif r == "9" then has9 = true; strength = strength + 14
            elseif r == "A" then hasA = true; strength = strength + 11
            elseif r == "T" then strength = strength + 10
            elseif r == "K" then strength = strength + 4
            elseif r == "Q" then strength = strength + 3
            end
        end
    end
    strength = strength + math.max(0, count - 2) * 5
    if hasJ and has9 then
        strength = strength + (Bot.IsAdvanced() and 18 or 10)
    end
    if Bot.IsAdvanced()
       and not hasJ and count < 5 and not (has9 and hasA) then
        -- No J, no 9+A pair, and short — structurally weak as trump.
        -- Damp rather than zero so a J-led overcall by a bid-card
        -- coincidence still falls through naturally.
        strength = math.floor(strength * 0.4)
    end
    return strength, count
end

-- Outside-trump aces are tricks the bidder can typically capture
-- before being trumped out. Returns the bonus to add when advanced
-- mode is on; 0 otherwise. Cap at 3 aces (the 4th would be in trump).
local function sideSuitAceBonus(hand, trumpSuit)
    if not Bot.IsAdvanced() then return 0 end
    local n = 0
    for _, card in ipairs(hand) do
        if C.Rank(card) == "A" and C.Suit(card) ~= trumpSuit then
            n = n + 1
        end
    end
    return math.min(n, 3) * 8
end

-- Score for a Sun bid: high cards across all suits, length is irrelevant.
--
-- Advanced layer: penalize lopsided distributions. A Sun hand with a
-- void or singleton (or no honors) in any suit is dangerous — opponents
-- lead the weak suit and you bleed. -10 per offending suit, capped at
-- the +25 range so a very lopsided hand still has *some* score floor.
local function sunStrength(hand)
    local s = 0
    local count = { S = 0, H = 0, D = 0, C = 0 }
    local honors = { S = false, H = false, D = false, C = false }
    for _, card in ipairs(hand) do
        local r = C.Rank(card)
        local su = C.Suit(card)
        count[su] = count[su] + 1
        if r == "A" or r == "T" or r == "K" then honors[su] = true end
        if     r == "A" then s = s + 11
        elseif r == "T" then s = s + 10
        elseif r == "K" then s = s + 4
        elseif r == "Q" then s = s + 3
        elseif r == "J" then s = s + 2
        end
    end
    if Bot.IsAdvanced() then
        local penalty = 0
        for _, su in ipairs({ "S", "H", "D", "C" }) do
            if count[su] < 2 or not honors[su] then penalty = penalty + 10 end
        end
        s = s - math.min(penalty, 25)
    end
    return s
end

-- Read partner's bid as info for escalation decisions. Returns a
-- numeric bonus to add to the bot's own evaluated strength. Off
-- (returns 0) when advanced is disabled. Convention:
--   • partner HOKM matching our trump → +20 (J/9 in trump)
--   • partner HOKM other suit         → +10 (general strong hand)
--   • partner SUN                     → +15 (lots of A/T)
--   • partner ASHKAL (forced Sun)     → +15 (similar to SUN above)
--   • partner PASS both rounds        → -10 (weak)
--   • no info / unknown               →  0
local function partnerBidBonus(seat, contract)
    if not Bot.IsAdvanced() then return 0 end
    if not S.s.bids then return 0 end
    local partner = R.Partner(seat)
    local b = S.s.bids[partner]
    if not b then return 0 end
    if b == K.BID_SUN then return 15 end
    if b == K.BID_ASHKAL then return 15 end
    if b == K.BID_PASS then return -10 end
    if b:sub(1, #K.BID_HOKM) == K.BID_HOKM then
        local bidTrump = b:sub(#K.BID_HOKM + 2, #K.BID_HOKM + 2)
        if contract and contract.trump and bidTrump == contract.trump then
            return 20
        end
        return 10
    end
    return 0
end

-- Score-position urgency. Returns a threshold MODIFIER (subtract
-- from threshold to lower it / be more aggressive). Off (returns 0)
-- when advanced is disabled.
--   • near win (cumulative >= target-25): +8 (more conservative)
--   • near loss (opp cumulative >= target-25): -12 (desperate)
--   • behind by 80+: -6 (take risks)
--   • else: 0
local function scoreUrgency(myTeam)
    if not Bot.IsAdvanced() then return 0 end
    if not S.s.cumulative or not myTeam then return 0 end
    local me  = S.s.cumulative[myTeam] or 0
    local opp = S.s.cumulative[(myTeam == "A") and "B" or "A"] or 0
    local target = (S.s.target or 152)
    if me  >= target - 25 then return  8  end
    if opp >= target - 25 then return -12 end
    if opp - me > 80      then return -6  end
    return 0
end

-- M3lm-only: smoother match-point urgency. Layers on top of
-- scoreUrgency with a finer-grained curve based on distance-to-win.
-- Returns ADDITIONAL modifier to subtract from threshold.
--   • opponent  ≥ target-15  : extra -8  (defensive desperation)
--   • opponent  ≥ target-40  : extra -3  (caution)
--   • we        ≥ target-15  : extra +5  (lock it down)
--   • behind by 50..80       : extra -3  (take measured risk)
local function matchPointUrgency(myTeam)
    if not Bot.IsM3lm() then return 0 end
    if not S.s.cumulative or not myTeam then return 0 end
    local me  = S.s.cumulative[myTeam] or 0
    local opp = S.s.cumulative[(myTeam == "A") and "B" or "A"] or 0
    local target = (S.s.target or 152)
    local mod = 0
    if opp >= target - 15 then mod = mod - 8
    elseif opp >= target - 40 then mod = mod - 3 end
    if me  >= target - 15 then mod = mod + 5 end
    local diff = opp - me
    if diff > 50 and diff <= 80 then mod = mod - 3 end
    return mod
end

-- M3lm-only: did our partner already escalate in this contract? If
-- yes, bot should be MORE willing to escalate further (combined-team
-- strength signal). If partner DECLINED an escalation opportunity
-- (their seat is the one that should have just acted), that's a
-- weakness signal — bot should be MORE cautious.
--
-- Returns a strength bonus to add (positive = more aggressive).
local function partnerEscalatedBonus(seat, contract)
    if not Bot.IsM3lm() then return 0 end
    if not contract then return 0 end
    local p = R.Partner(seat)
    -- v0.2.0: contract escalation roles have flipped from the 5-rung
    -- chain. Mapping:
    --   contract.doubled — set by the defender (Bel)
    --   contract.tripled — set by the bidder (Triple)
    --   contract.foured  — set by the defender (Four)
    --   contract.gahwa   — set by the bidder (Gahwa, match-win)
    local bidder = contract.bidder
    local defender = bidder and ((bidder % 4) + 1) or nil
    local bonus = 0
    -- If partner is the DEFENDER and they Beled or Foured, that's a
    -- positive signal for us (the defender team) — escalation chain
    -- says we're confident in breaking the contract. Bidder team
    -- shouldn't read this as a positive for them.
    if p == defender then
        if contract.doubled then bonus = bonus + 5  end
        if contract.foured  then bonus = bonus + 8  end
    end
    -- If partner is the BIDDER and they Tripled, that's a positive
    -- signal for us (the bidder team) — they're confident in making.
    if p == bidder then
        if contract.tripled then bonus = bonus + 5  end
        if contract.gahwa   then bonus = bonus + 12 end
    end
    return bonus
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
    local urgency = (scoreUrgency(R.TeamOf(seat)) + matchPointUrgency(R.TeamOf(seat)))
    -- Round-2 threshold ought to be ≥ round-1: in R2 the bidder picks
    -- the suit, so fewer hands are forced to commit. Advanced layer
    -- enforces this; basic mode keeps the existing R2<R1 split.
    local r1Base = TH_HOKM_R1_BASE
    local r2Base = TH_HOKM_R2_BASE
    if Bot.IsAdvanced() then r2Base = math.max(r2Base, r1Base + 6) end
    local thHokmR1 = jitter(r1Base    - urgency, BID_JITTER)
    local thHokmR2 = jitter(r2Base    - urgency, BID_JITTER)
    local thSun    = jitter(TH_SUN_BASE - urgency, BID_JITTER)

    if round == 1 then
        -- Sun overcalls Hokm. Note: a LATER direct Sun does NOT
        -- overcall an earlier direct Sun — host's HostAdvanceBidding
        -- locks on the first direct Sun. Bot bids Sun whenever its
        -- threshold passes; if another seat already won the Sun chair
        -- earlier, the host silently treats this as a no-op.
        if sun >= thSun then return K.BID_SUN end

        -- Ashkal: if our PARTNER bid Hokm earlier in this round and
        -- we hold a Sun-strong hand, call Ashkal so partner is forced
        -- into Sun (higher multiplier). RESTRICTIONS per Saudi rule:
        --   • Only the 3rd and 4th seats in turn order can Ashkal.
        --     1st and 2nd bidders never get the option.
        --   • A prior direct Sun bid blocks Ashkal.
        local partner = R.Partner(seat)
        local partnerBid = S.s.bids and S.s.bids[partner]
        local bidPos = 0
        if S.s.dealer then
            local d = S.s.dealer
            local order = {
                (d % 4) + 1, ((d + 1) % 4) + 1,
                ((d + 2) % 4) + 1, d,
            }
            for i, st in ipairs(order) do
                if st == seat then bidPos = i; break end
            end
        end
        if bidPos >= 3
           and partnerBid and partnerBid:sub(1, #K.BID_HOKM) == K.BID_HOKM
           and not anySun then
            -- Advanced: only Ashkal if WE'RE weak in the flipped suit
            -- (so partner's J of that suit is doing the work, not ours).
            -- If we hold the J of the flipped suit, partner's bid is
            -- bluff/marginal and Ashkal is risky — skip.
            local ok = true
            if Bot.IsAdvanced() and bidCardSuit then
                local sStr, sCnt = suitStrengthAsTrump(hand, bidCardSuit)
                local hasJflip = false
                for _, c in ipairs(hand) do
                    if C.Rank(c) == "J" and C.Suit(c) == bidCardSuit then
                        hasJflip = true; break
                    end
                end
                if hasJflip or sCnt > 2 then ok = false end
            end
            if ok then
                local thAshkal = jitter(K.BOT_ASHKAL_TH or 65, BID_JITTER)
                if sun >= thAshkal then return K.BID_ASHKAL end
            end
        end

        -- Hokm-on-flipped only available if no prior Hokm/Sun.
        if not anyHokm and not anySun and bidCardSuit then
            local strength = suitStrengthAsTrump(hand, bidCardSuit)
            strength = strength + sideSuitAceBonus(hand, bidCardSuit)
            if strength >= thHokmR1 then
                return K.BID_HOKM .. ":" .. bidCardSuit
            end
        end
        return K.BID_PASS
    end

    -- Round 2: pass / Hokm-non-flipped / Sun. Both rounds now wait
    -- for all 4 bids and Sun overcalls Hokm in either round.
    local bestSuit, bestScore = nil, 0
    for _, suit in ipairs(K.SUITS) do
        if suit ~= bidCardSuit then
            local s = suitStrengthAsTrump(hand, suit)
            s = s + sideSuitAceBonus(hand, suit)
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
    local isBidderTeam = (contract.type == K.BID_HOKM
                          and myTeam == R.TeamOf(contract.bidder))
    local isBidder = (seat == contract.bidder)

    -- Advanced (Tier 3 #11): if we hold a card that's currently the
    -- HIGHEST UNPLAYED in its non-trump suit, leading that card is
    -- a guaranteed trick. Reuses State.HighestUnplayedRank, which is
    -- maintained by ApplyPlay across all clients.
    if Bot.IsAdvanced() and contract.type == K.BID_HOKM
       and S.HighestUnplayedRank then
        for _, c in ipairs(legal) do
            local r = C.Rank(c)
            local su = C.Suit(c)
            if su ~= contract.trump and S.HighestUnplayedRank(su) == r then
                return c
            end
        end
    end

    -- Fzloky (signal-aware): if our partner has shown a "lead this
    -- suit" signal via a HIGH first-discard (A/T/K), prefer leading
    -- that suit. If their first-discard was LOW (7/8), avoid that
    -- suit. Operates on top of the Advanced lead heuristics: we
    -- pick a suit, then fall through to the existing low-from-
    -- longest logic to choose the actual card.
    local fzlokyPrefSuit, fzlokyAvoidSuit = nil, nil
    if Bot.IsFzloky() and Bot._memory then
        local p = R.Partner(seat)
        local sig = Bot._memory[p] and Bot._memory[p].firstDiscard
        if sig and sig.suit then
            local r = sig.rank
            if r == "A" or r == "T" or r == "K" then
                fzlokyPrefSuit = sig.suit
            elseif r == "7" or r == "8" then
                fzlokyAvoidSuit = sig.suit
            end
        end
    end
    if fzlokyPrefSuit then
        -- Lead our LOWEST card in the preferred suit (partner has
        -- the high cards there; we lead low for them to win).
        local fromPref = {}
        for _, c in ipairs(legal) do
            if C.Suit(c) == fzlokyPrefSuit
               and not C.IsTrump(c, contract) then
                fromPref[#fromPref + 1] = c
            end
        end
        if #fromPref > 0 then
            return lowestByRank(fromPref, contract)
        end
    end

    -- Bidder team in Hokm: typical play is "draw trump" (lead high
    -- trump). But not always:
    --   • If we ARE the bidder: stick with high-trump lead (clears
    --     opponent trumps so our side suits run).
    --   • If we are bidder's PARTNER: leading trump WITH the bidder's
    --     own hand still concentrated in trump is wasteful — we cash
    --     side winners through, then partner ruffs. Fall through to
    --     the defender-style logic.
    --   • Trump-poor bidder hand (<4 trump) with a side-suit boss
    --     (we already covered that above via HighestUnplayedRank).
    if isBidderTeam and isBidder then
        -- Count own trump.
        local trumpCount = 0
        for _, c in ipairs(legal) do
            if C.IsTrump(c, contract) then trumpCount = trumpCount + 1 end
        end
        -- Advanced: trump-poor (<4) AND we have a non-trump A → cash
        -- the Ace first; trump-pull on the next round.
        if Bot.IsAdvanced() and trumpCount < 4 then
            for _, c in ipairs(legal) do
                if C.Rank(c) == "A" and not C.IsTrump(c, contract) then
                    return c
                end
            end
        end
        local t = highestTrump(legal, contract)
        if t then return t end
    end

    -- Defenders / bidder's partner / Sun lead: don't burn high cards.
    -- Heuristics, in priority order:
    --   1. If opponents are known void in some non-trump suit, lead
    --      our HIGHEST card of that suit (free trick — they can't
    --      stop it).
    --   2. Lead a singleton low non-trump (we can't lead it later).
    --   3. Lead LOW from our LONGEST non-trump suit (preserve high
    --      cards for capture, give partner room to win).
    --   4. Otherwise: lowest non-trump.
    --   5. No non-trump option: lowest legal trump.
    local nonTrumps = {}
    local suitCount = { S = 0, H = 0, D = 0, C = 0 }
    for _, c in ipairs(legal) do
        if not C.IsTrump(c, contract) then
            nonTrumps[#nonTrumps + 1] = c
            suitCount[C.Suit(c)] = suitCount[C.Suit(c)] + 1
        end
    end

    -- 1: any free-trick suit?
    for _, c in ipairs(nonTrumps) do
        if opponentsVoidInAll(seat, C.Suit(c)) then
            -- Take the HIGHEST card we have in that suit — opponents
            -- can't trump (can't follow either), and partner won't
            -- be able to take from us.
            local best, bestR = c, C.TrickRank(c, contract)
            for _, c2 in ipairs(nonTrumps) do
                if C.Suit(c2) == C.Suit(c) then
                    local r = C.TrickRank(c2, contract)
                    if r > bestR then best, bestR = c2, r end
                end
            end
            return best
        end
    end

    -- 2: singleton low? Pick the lowest singleton if we have any.
    local singletons = {}
    for _, c in ipairs(nonTrumps) do
        if suitCount[C.Suit(c)] == 1 then singletons[#singletons + 1] = c end
    end
    if #singletons > 0 then
        return lowestByRank(singletons, contract)
    end

    -- 3: lead low from longest non-trump suit. If Fzloky has flagged
    -- a partner-avoid suit (their LOW first-discard), exclude that
    -- suit from the longest-pick when an alternative exists.
    if #nonTrumps > 0 then
        -- Two-pass selection avoids the iteration-order bug where
        -- pairs(suitCount) might visit the avoid-suit first and let
        -- it claim `longest` before any alternative is considered.
        -- Pass 1: longest NON-avoid suit. Pass 2: any longest if pass
        -- 1 found nothing. The Fzloky "≥2 more cards" tolerance is
        -- now applied as a tie-break — avoid-suit only wins if it
        -- exceeds the best non-avoid by ≥2.
        local longest, longestN = nil, 0
        for _, suit in ipairs({ "S", "H", "D", "C" }) do
            local n = suitCount[suit] or 0
            if suit ~= fzlokyAvoidSuit and n > longestN then
                longest, longestN = suit, n
            end
        end
        if fzlokyAvoidSuit then
            local avoidN = suitCount[fzlokyAvoidSuit] or 0
            if avoidN >= longestN + 2 then
                longest, longestN = fzlokyAvoidSuit, avoidN
            end
        end
        if not longest then
            -- Avoid-suit was our only non-trump. Use it.
            for _, suit in ipairs({ "S", "H", "D", "C" }) do
                local n = suitCount[suit] or 0
                if n > longestN then longest, longestN = suit, n end
            end
        end
        local fromLongest = {}
        for _, c in ipairs(nonTrumps) do
            if C.Suit(c) == longest then fromLongest[#fromLongest + 1] = c end
        end
        if #fromLongest > 0 then
            return lowestByRank(fromLongest, contract)
        end
        return lowestByRank(nonTrumps, contract)
    end

    -- 5: no non-trump — lowest trump.
    return lowestByRank(legal, contract)
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
    -- Position in this trick (1 = first/lead, 4 = last/closing).
    -- Used by advanced position-aware play; kept consistent with the
    -- existing `lastSeat` flag.
    local pos = #trick.plays + 1
    local lastSeat = (pos == 4)

    if partnerWinning then
        -- Smother: in Hokm, dumping our Ace/10 of lead suit onto partner's
        -- trick-pile feeds points to our team. Gate:
        --   (a) we have a SECOND A or T in that suit (so we keep one
        --       for defensive depth), OR
        --   (b) we're past the first 3 tricks, OR
        --   (c) [ANY MODE] we're 4th to act — the trick is going on
        --       partner's pile no matter what, free points.
        -- Trump-led: smother is skipped (trump tricks don't reward
        -- feeding A/T).
        if contract.type == K.BID_HOKM and trick.leadSuit
           and trick.leadSuit ~= contract.trump then
            local lead = trick.leadSuit
            local highInSuit = {}  -- list of A/T legal cards in lead suit
            for _, c in ipairs(legal) do
                local r = C.Rank(c)
                if C.Suit(c) == lead and (r == "A" or r == "T") then
                    highInSuit[#highInSuit + 1] = c
                end
            end
            local completed = #(S.s.tricks or {})
            if #highInSuit >= 2 or completed >= 3 or lastSeat then
                table.sort(highInSuit, function(a, b)
                    return C.TrickRank(a, contract) < C.TrickRank(b, contract)
                end)
                if highInSuit[1] then return highInSuit[1] end
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
        -- Position-aware (advanced):
        --   pos 2: "second hand low" — partner hasn't played yet.
        --     Don't commit our highest unless the card we'd win with
        --     is unbeatable (sure stopper). Otherwise duck and let
        --     partner cover. We approximate "sure stopper" as
        --     trump-when-only-one-trump-outstanding.
        --   pos 3: "third hand high" — partner already played, lost.
        --     Commit a card that survives the 4th seat's likely
        --     overcut (highest winner, not lowest).
        --   pos 4: cheapest winner (current behavior).
        if Bot.IsAdvanced() then
            if pos == 2 then
                local sureStopper = nil
                if contract.type == K.BID_HOKM and contract.trump then
                    local trumpOut = suitCardsOutstanding(hand, contract.trump)
                    if trumpOut <= 1 then
                        -- Use the highest trump winner as "sure".
                        for _, c in ipairs(winners) do
                            if C.IsTrump(c, contract)
                               and (not sureStopper
                                    or C.TrickRank(c, contract)
                                       > C.TrickRank(sureStopper, contract)) then
                                sureStopper = c
                            end
                        end
                    end
                end
                if sureStopper then return sureStopper end
                -- Duck: throw the lowest legal that ISN'T a winner.
                local nonWinners = {}
                for _, c in ipairs(legal) do
                    local isWin = false
                    for _, w in ipairs(winners) do
                        if w == c then isWin = true; break end
                    end
                    if not isWin then nonWinners[#nonWinners + 1] = c end
                end
                if #nonWinners > 0 then
                    return lowestByRank(nonWinners, contract)
                end
                -- All legal cards are winners — fall through.
            elseif pos == 3 then
                -- Highest winner so the 4th seat can't easily overcut.
                return highestByRank(winners, contract)
            end
        end
        -- Default / pos 4 / no advanced: cheapest winner.
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

-- Bot AKA (إكَهْ) self-call. Advanced-only. Returns the non-trump suit
-- of `leadCard` if it's the AKA (highest unplayed card) of that suit
-- AND meaningful to signal; nil otherwise. Net.MaybeRunBot calls this
-- with the chosen lead card so the bot only announces AKA on the
-- card it's actually leading — not on some unrelated suit it happens
-- to hold the boss of. Per-suit dedup prevents re-announcing the
-- same suit on later leads in the same round.
function Bot.PickAKA(seat, leadCard)
    if not Bot.IsAdvanced() then return nil end
    if not S.s.contract or S.s.contract.type ~= K.BID_HOKM then return nil end
    if not S.s.trick or #S.s.trick.plays > 0 then return nil end  -- lead only
    if not leadCard then return nil end
    if not S.HighestUnplayedRank then return nil end
    local trump = S.s.contract.trump
    if not trump then return nil end
    local r = C.Rank(leadCard)
    local su = C.Suit(leadCard)
    -- AKA is non-trump only.
    if su == trump then return nil end
    -- The lead card must be the highest UNPLAYED rank of its suit.
    -- Otherwise the signal is false (we don't actually hold the boss).
    if S.HighestUnplayedRank(su) ~= r then return nil end
    -- Per-round, per-suit dedup. Once announced, partner knows we
    -- hold the boss until it falls. Re-announcing on the same suit
    -- is noise — the spam complaint.
    Bot._memory = Bot._memory or emptyMemory()
    local mem = Bot._memory[seat]
    if mem and mem.akaSent and mem.akaSent[su] then return nil end
    -- Skip on the very first trick lead: at that point no opponent has
    -- shown a void yet, so the signal isn't actionable for partner —
    -- they have no reason to over-trump a fresh suit yet anyway.
    -- AKA is most useful in the mid/late hand once voids are showing.
    local trickNum = #(S.s.tricks or {}) + 1
    if trickNum <= 1 then return nil end
    -- Mark sent and return.
    if mem and mem.akaSent then mem.akaSent[su] = true end
    return su
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
    -- Saudi rule: melds must be declared during trick 1 only. Once
    -- trick 1 has closed (any completed trick), the declaration
    -- window is shut even for bots that haven't yet committed their
    -- first card of trick 2. Mirrors the gate in S.GetMeldsForLocal
    -- so bots can't bypass it via the bot-auto-meld loop in Net.lua.
    if (#(S.s.tricks or {})) >= 1 then return {} end
    return R.DetectMelds(hand, S.s.contract)
end

-- Smarter Bel — gated by hand strength so a weak defender doesn't bel
-- into stronger opposition. Sun contracts get a small bonus because
-- Sun is harder to make than Hokm. Threshold is jittered per-call by
-- ±10 so the Bel decision isn't a hard cliff at exactly the configured
-- value (was the #1 "predictable bot" complaint).
local BEL_JITTER = 10

-- v0.2.0: returns (yes, wantOpen) like the other escalation pickers.
-- wantOpen: open the chain to a bidder Triple counter only if our hand
-- is comfortably above threshold (we'd survive the next rung's stakes).
-- Sun forces wantOpen=false since Sun has no Triple rung anyway.
function Bot.PickDouble(seat)
    local hand = S.s.hostHands and S.s.hostHands[seat]
    local contract = S.s.contract
    if not hand or not contract then return false, false end

    local strength = sunStrength(hand)
    if contract.type == K.BID_HOKM and contract.trump then
        -- Trump cards are an extra defensive resource.
        local trumpStr = suitStrengthAsTrump(hand, contract.trump)
        strength = strength + trumpStr * 0.5
    end
    if contract.type == K.BID_SUN then
        strength = strength + 10   -- bias: Sun is harder for the bidder
    end
    -- Advanced: partner's bid is a strong signal of combined-team
    -- strength; score urgency adjusts threshold for desperation/safety.
    strength = strength + partnerBidBonus(seat, contract)
                       + partnerEscalatedBonus(seat, contract)
    local th = K.BOT_BEL_TH - (scoreUrgency(R.TeamOf(seat)) + matchPointUrgency(R.TeamOf(seat)))
    local jth = jitter(th, BEL_JITTER)
    if strength < jth then return false, false end
    -- Sun: open is moot (no Triple rung).
    if contract.type == K.BID_SUN then return true, false end
    -- Open if we have a comfortable buffer (would survive a Triple
    -- counter); else close to lock in the ×2.
    local wantOpen = strength >= jth + 20
    return true, wantOpen
end

-- ---------------------------------------------------------------------
-- Triple / Four / Gahwa escalation (v0.2.0+ canonical 4-rung chain)
-- ---------------------------------------------------------------------
-- Bel(def, ×2) → Triple(bidder, ×3) → Four(def, ×4) → Gahwa(bidder, match-win).
-- Each rung is a counter to the previous rung's caller. Bots return
-- (yes, wantOpen) — wantOpen=true allows the next rung; false closes
-- the chain. Closed-with-strong-hand is the safer play when the
-- partner's escalation tendency is uncertain.

local function escalationStrength(seat, hand, contract)
    local strength = sunStrength(hand)
    if contract.type == K.BID_HOKM and contract.trump then
        strength = strength + suitStrengthAsTrump(hand, contract.trump)
    end
    -- Advanced: factor in partner's bid as combined-team strength
    -- info. PASS both rounds → -10; HOKM matching trump → +20; etc.
    strength = strength + partnerBidBonus(seat, contract)
                       + partnerEscalatedBonus(seat, contract)
    return strength
end

-- Returns (yes, wantOpen). wantOpen heuristic: open if our strength
-- has a comfortable buffer over the threshold (we'd be willing to
-- escalate again next rung if challenged).
local function escalateDecision(strength, th)
    local jth = jitter(th, BEL_JITTER)
    if strength < jth then return false, false end
    -- Strong-enough → open if we're well past threshold (we'd
    -- still escalate the next rung); else close.
    local wantOpen = strength >= jth + 20
    return true, wantOpen
end

function Bot.PickTriple(seat)
    -- v0.2.0: Triple is the BIDDER's response to a defender's Bel.
    -- A confident bidder triples (×3 multiplier) and may stay open if
    -- they think they can absorb a defender's Four counter.
    local hand = S.s.hostHands and S.s.hostHands[seat]
    local contract = S.s.contract
    if not hand or not contract then return false, false end
    local strength = escalationStrength(seat, hand, contract)
    local th = K.BOT_TRIPLE_TH - (scoreUrgency(R.TeamOf(seat)) + matchPointUrgency(R.TeamOf(seat)))
    return escalateDecision(strength, th)
end

function Bot.PickFour(seat)
    -- v0.2.0: Four is the DEFENDER's response to bidder's Triple.
    -- A failed ×4 round is a hand-killer — defender needs to be
    -- highly confident the contract will fail.
    local hand = S.s.hostHands and S.s.hostHands[seat]
    local contract = S.s.contract
    if not hand or not contract then return false, false end
    local strength = escalationStrength(seat, hand, contract)
    local th = K.BOT_FOUR_TH - (scoreUrgency(R.TeamOf(seat)) + matchPointUrgency(R.TeamOf(seat)))
    return escalateDecision(strength, th)
end

function Bot.PickGahwa(seat)
    -- v0.2.0: Gahwa is the BIDDER's terminal — match-win or match-loss.
    -- Bot only fires this on a near-certain hand: the entire match
    -- hangs on the next 8 tricks.
    local hand = S.s.hostHands and S.s.hostHands[seat]
    local contract = S.s.contract
    if not hand or not contract then return false end
    local strength = escalationStrength(seat, hand, contract)
    local th = K.BOT_GAHWA_TH - (scoreUrgency(R.TeamOf(seat)) + matchPointUrgency(R.TeamOf(seat)))
    return strength >= jitter(th, BEL_JITTER)
end

-- Triple-on-Ace pre-emption (الثالث) — bot decision for an earlier
-- seat eligible to claim a Sun bid when the bid card is an Ace.
-- Heuristic: claim only if our own Sun strength is strong enough that
-- we'd have wanted to bid Sun ourselves (subject to BOT_PREEMPT_TH).
function Bot.PickPreempt(seat)
    local hand = S.s.hostHands and S.s.hostHands[seat]
    if not hand then return false end
    local strength = sunStrength(hand)
    -- Slight bonus when we hold the Ace of the bid suit ourselves
    -- (it would have been our trick-winner anyway).
    local bidSuit = S.s.bidCard and C.Suit(S.s.bidCard)
    if bidSuit then
        for _, c in ipairs(hand) do
            if C.Rank(c) == "A" and C.Suit(c) == bidSuit then
                strength = strength + 8; break
            end
        end
    end
    strength = strength + scoreUrgency(R.TeamOf(seat))
                       + matchPointUrgency(R.TeamOf(seat))
    local th = K.BOT_PREEMPT_TH or 75
    return strength >= jitter(th, BEL_JITTER)
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
