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
    if not contract then return desire end
    -- Hokm-bidder partner: trump-count bias + outside-Ace clustering.
    if contract.type == K.BID_HOKM and contract.trump then
        local t = contract.trump
        desire[t] = true
        for _, s in ipairs(K.SUITS) do
            if s ~= t then
                desire["A"..s] = 5
            end
        end
        return desire
    end
    -- v0.6.1 Section 11 rule 4 (Common, video 05): Sun-bidder partner
    -- → assume concentrated highs. Saudi convention: a Sun-bidder team
    -- only commits when both partners can carry trick-pulling weight,
    -- so the partner typically holds A's and K's across multiple suits
    -- (the "one long suit" inference is harder to localize without
    -- knowing WHICH suit; we encode the highs-concentration here and
    -- let length emerge from the random fill). Weight 8 on Aces is
    -- distinctly above the suit-fallback 20-weight floor so the
    -- sampler reliably places them in the partner's hand. K weight 4
    -- mirrors the partial-clustering tier.
    if contract.type == K.BID_SUN then
        for _, s in ipairs(K.SUITS) do
            desire["A"..s] = 8
            desire["K"..s] = 4
        end
        return desire
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

    -- v1.0.4 (agent #3): bidcard-defender-desire downweight. The
    -- bidcard is publicly held by the bidder (post-HostDealRest pin).
    -- defenderDesire's per-side-Ace bias (8) was set up under the
    -- pre-bidcard assumption that ALL non-trump Aces could be in
    -- defender hands. With the bidcard-pin live, when bidcard is a
    -- side-suit Ace owned by the bidder, the defenders cannot hold
    -- it. Drop that specific Ace's desire to 0 so the sampler doesn't
    -- waste rollouts placing it in a defender hand (where the
    -- pinSeat=bidder constraint would just reject the world).
    if pinCard and pinSeat == bidder and contract.type == K.BID_HOKM
       and contract.trump then
        local pinSuit = C.Suit(pinCard)
        local pinRank = C.Rank(pinCard)
        if pinRank == "A" and pinSuit ~= contract.trump then
            -- Mutate a clone — defenderDesire is shared. Use the
            -- v0.9.0 M3 clone-on-mutation pattern.
            local clone = {}
            for k, v in pairs(defenderDesire) do clone[k] = v end
            clone[pinCard] = nil  -- remove the explicit Ace bias
            defenderDesire = clone
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
                        -- v0.11.18 audit BM-04 fix: respect observed
                        -- voids when pinning meld cards. Pre-fix a meld
                        -- declared trick-1 by seat 2 (e.g., Hearts Tierce
                        -- including 7H) was always pinned to seat 2,
                        -- even if seat 2 LATER showed Hearts-void in
                        -- trick 5 (mem.void.H = true). The deal would
                        -- be internally inconsistent (seat 2 has 7H
                        -- AND is void in Hearts). Right resolution:
                        -- if void observed, drop the pin — the meld
                        -- card must've been played even if not yet
                        -- in our `played` map (could be hostHands-
                        -- only data depending on game state).
                        local declarerVoid = false
                        local mem = B.Bot and B.Bot._memory and B.Bot._memory[m.declaredBy]
                        if mem and mem.void and mem.void[C.Suit(c)] then
                            declarerVoid = true
                        end
                        if not declarerVoid then
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

    -- v0.5.22 Section 11 rule 3 (Definite, video 05): pigeonhole pin
    -- extension of H-1. When N trumps remain unseen AND we observe
    -- that all-but-one OTHER seats are void in trump (via
    -- B.Bot._memory[s].void[trump]), all those remaining trumps MUST
    -- be in the one remaining trump-eligible seat. Mathematical
    -- force; pin them. This is a HARD constraint that significantly
    -- improves rollout accuracy late in the round when voids surface.
    -- Sources: decision-trees.md Section 11 rule 3 (Definite, video 05).
    if contract and contract.type == K.BID_HOKM and contract.trump then
        local trump = contract.trump
        -- Collect non-self seats that have NOT been observed void in trump.
        local trumpEligible = {}
        for s = 1, 4 do
            if s ~= seat then
                local voids = (B.Bot._memory and B.Bot._memory[s]
                               and B.Bot._memory[s].void) or {}
                if not voids[trump] then
                    trumpEligible[#trumpEligible + 1] = s
                end
            end
        end
        -- If exactly one other seat can hold trump, pin all unseen
        -- trumps to that seat. (Existing H-1 J/9 pin already covers
        -- those two specifically — this catches K/Q/T/A/8/7 of trump
        -- in the same scenario.)
        if #trumpEligible == 1 then
            local pinSeat = trumpEligible[1]
            for _, u in ipairs(unseen) do
                if C.Suit(u) == trump and u ~= pinCard and not meldPins[u] then
                    meldPins[u] = pinSeat
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
                -- v0.9.0 M3 fix (audit AUDIT_REPORT_v0.7.1.md): clone
                -- desire before any per-seat mutation. Pre-v0.9.0, the
                -- per-seat mutations below (pSignalSuit assignment at
                -- this site, leadCount/baitedSuit additions further
                -- down) wrote DIRECTLY into the shared `strong`/
                -- `defenderDesire`/`partnerDesire` tables, polluting
                -- them across seats and retry attempts within one
                -- sampleConsistentDeal call. Now each seat gets a
                -- fresh copy and mutations are seat-local.
                local desireOrig = desire
                desire = {}
                for k, v in pairs(desireOrig) do desire[k] = v end
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
                -- v0.8.1 B-95: desperate-bidder pickProb damping. When
                -- this seat is the contract bidder AND on a team far
                -- behind us (opponentUrgency >= 6), they may have bid
                -- a weaker hand than thresholds suggest — Hail-Mary
                -- bidding pattern. Damp pickProb so the strong-card
                -- pinning is less aggressive in this seat's hand,
                -- widening the sampled distribution toward weaker
                -- holdings. M3lm-gated via OpponentUrgency.
                -- Sources: bot_picker_gaps.md / wave8 B-95.
                if s == bidder and B.Bot.OpponentUrgency
                   and B.Bot.OpponentUrgency(bidder) >= 6 then
                    pickProb = math.min(pickProb, 0.5)
                end
                -- v0.6.1 B-56: leadCount-based suit bias. A seat with
                -- repeated lead-suit X (across the GAME, not the round —
                -- _partnerStyle is per-game) has historically been dealt
                -- long in X. Bias the sampler to put more X-suit cards
                -- in their hand: set desire[suit] = 1 to enable the
                -- suit-fallback path (weight 20 per card). Threshold of
                -- >=3 leads avoids noise (a single lead is round-luck;
                -- 3+ is a hand-shape pattern). Skip if Kawesh-cleared
                -- the desire map already, OR if the suit-flag is already
                -- set by another mechanism (Fzloky signal-suit). The
                -- additive bias only fires for OPPONENT seats — we don't
                -- need to second-guess teammate hand shape (we already
                -- have stronger signals via firstDiscard / Tahreeb).
                if style and style.leadCount and sIsOpponent
                   and not (mem and mem.likelyKawesh) then
                    for suit, count in pairs(style.leadCount) do
                        if count >= 3 and not desire[suit] then
                            desire[suit] = 1
                        end
                    end
                end

                -- v0.9.0 Section 6 rules 1-4: touching-honors-down
                -- desire bumps. When this seat showed touching-honors
                -- in suit X (played T → has K, etc.), HARD-PIN the
                -- inferred next-down card. Definite-confidence per
                -- video #05.
                --
                -- v0.10.0 R6 fix (review_v0.10.0/reaudit_R6_touching_honors.md):
                --   * Trust-asymmetry per video #05 @ 03:17-03:22:
                --     "trust partner signals at face value, discount
                --     opponent signals." Only apply pins/clears for
                --     this seat's PARTNER (sIsOpponent == false AND
                --     s ~= seat). Pre-v0.10.0 the reader applied
                --     uniformly — opponents could weaponize the
                --     mis-pin via deceptive K-plays. Skip applying
                --     for self (s == seat — bot's own hand is known)
                --     and for opp seats.
                --   * Handle `entry.cleared` (new field): K-signal
                --     means the seat does NOT hold the listed ranks.
                --     Sets desire[rank+suit] = nil to negative-bias
                --     the sampler away from putting those ranks in
                --     this seat's hand. Pre-v0.10.0 the K-signal
                --     wrongly set entry.nextDown="Q", which PINNED
                --     Q to the seat that explicitly does NOT hold Q.
                --   * `entry.broke` now also fires for 9 (extended
                --     from 7/8 only).
                --
                -- Sources: decision-trees.md Section 6 rules 1-4;
                --   review_v0.10.0/reaudit_R6_touching_honors.md.
                local sIsPartner = (s == R.Partner(seat))
                if sIsPartner and style and style.topTouchSignal then
                    for suit, entry in pairs(style.topTouchSignal) do
                        if entry.nextDown then
                            local card = entry.nextDown .. suit
                            -- High desire weight to nudge sampler. Not
                            -- a hard meld-pin (declared melds get those);
                            -- this is a soft inference. Use a desire
                            -- weight strictly above the existing strong-
                            -- card weights so it dominates random fills.
                            desire[card] = math.max(desire[card] or 0, 60)
                        end
                        if entry.cleared then
                            -- v0.10.0 R6: explicit-NOT-holding inference
                            -- (K-singleton signal: seat doesn't have Q/J).
                            for _, rk in ipairs(entry.cleared) do
                                desire[rk .. suit] = nil
                            end
                        end
                        if entry.broke then
                            -- Clear high-card desires for this suit;
                            -- seat is observed broke in highs.
                            for _, hi in ipairs({ "A", "T", "K", "Q", "J" }) do
                                desire[hi .. suit] = nil
                            end
                        end
                    end
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

    -- Fallback: uniform random deal — best-effort void respecting.
    --
    -- 50-agent codebase audit fix (H-6 regression): meldPins MUST be
    -- respected — declared meld cards are exact known positions, not
    -- soft constraints. Without this, a Tierce 7-8-9 of Hearts
    -- declared by seat 3 could end up split across all four seats.
    --
    -- v1.0.3 (BM-04-FALLBACK): pre-fix the fallback uniformly ignored
    -- voids. The primary path's BM-04 void filter was bypassed
    -- whenever the 15-attempt loop couldn't satisfy constraints,
    -- producing rollout worlds with seats holding cards in suits
    -- they're observed-void in. Now the fallback first tries to
    -- allocate respecting voids; cards that would violate are
    -- pushed to a "void-violating" pool used only when the void-
    -- respecting pool can't fill the seat. Best-effort, not strict —
    -- the fallback's contract is "produce SOME deal" not "produce a
    -- consistent deal", so if voids can't be satisfied we still
    -- ship a deal (better partial info than no rollout at all).
    local pool = {}
    for _, c in ipairs(unseen) do
        if c ~= pinCard and not meldPins[c] then
            pool[#pool + 1] = c
        end
    end
    shuffle(pool)
    local deal = {}
    local consumed = {}  -- cards already placed (across seats)
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
            local voids = (B.Bot._memory and B.Bot._memory[s]
                           and B.Bot._memory[s].void) or {}
            -- Pass 1: void-respecting allocation.
            for _, c in ipairs(pool) do
                if #hand >= n then break end
                if not consumed[c] and not voids[C.Suit(c)] then
                    hand[#hand + 1] = c
                    consumed[c] = true
                end
            end
            -- Pass 2: if still under-filled (impossible to satisfy
            -- voids given remaining pool), accept void-violating
            -- cards. This is the give-up path — better incomplete
            -- info than no rollout at all.
            if #hand < n then
                for _, c in ipairs(pool) do
                    if #hand >= n then break end
                    if not consumed[c] then
                        hand[#hand + 1] = c
                        consumed[c] = true
                    end
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

    -- v0.11.1 C-14: Build a rollout-local playedCardsThisRound from the
    -- real-state played cards plus the candidate card we just simulated.
    -- This is the table consulted by S.HighestUnplayedRank, which several
    -- Bot.PickPlay branches read (sweep-pursuit boss-scan, J+9 trump-lock,
    -- highest-unplayed lead). Without this swap, those branches would
    -- fire against the REAL game's unplayed-set instead of the rollout's
    -- determinization-sampled state.
    local rolloutPlayed = {}
    for _, t in ipairs(S.s.tricks or {}) do
        for _, p in ipairs(t.plays or {}) do rolloutPlayed[p.card] = true end
    end
    if S.s.trick and S.s.trick.plays then
        for _, p in ipairs(S.s.trick.plays) do rolloutPlayed[p.card] = true end
    end
    rolloutPlayed[card] = true

    -- v0.11.4 Bot1-01 (HIGH from comprehensive audit): also build a
    -- rollout-local Bot._memory[seat] so pickLead/pickFollow branches
    -- that read _memory[seat].played[card] and _memory[seat].void[suit]
    -- see the determinization-sampled view rather than real-state
    -- observations. Without this, branches like:
    --   • Ace-exhaustion lead (Bot.lua:2101-2132) — checks if anyone
    --     has played the side Ace; key for trump-poor cash-side play
    --   • Faranka exception #4 (Bot.lua:2985-2999) — fires when all
    --     opps observed-void in trump; key bidder-team Faranka
    --     pos-4 trump-cut
    --   • opponentsVoidInAll / anyOpponentVoidIn helpers (Bot.lua:674,692)
    --   • PickAKA suppression (Bot.lua:3385) — suppress AKA when
    --     partner is observed void in trump
    -- ...all read _memory in real-state at trick T, missing the void
    -- info revealed in the rollout's simulated tail (tricks T+1..T+k).
    -- v0.11.1 C-14 swapped 5 fields but missed _memory; the audit
    -- (Bot1-01) called this the partial-coverage gap.
    --
    -- Population mirrors Bot.OnPlayObserved (Bot.lua:343-368): for each
    -- play, set played[card]=true, and if leadSuit existed and the
    -- card's suit didn't match leadSuit, set void[leadSuit]=true.
    -- The Sun K/T-loses inference (Bot.lua:385-406) is omitted in the
    -- rollout — it's a real-observation rule and the rollout's
    -- simulated picks aren't observed signal events.
    --
    -- v0.11.18 audit BM-01 fix: COPY firstDiscard / likelyKawesh from
    -- prevMemory into rolloutMemory. Pre-fix these were dropped, so
    -- a Saudi Master rollout couldn't model that future leads should
    -- exploit partner's already-shown signal-suit (Fzloky firstDiscard
    -- → leadSuit preference, Bot.lua:2117-2129) or that we believe a
    -- specific seat may be Kaweshing (Bot.lua:402-404 desire-clear).
    -- akaSent is NOT copied — it's a cross-round signal layer that
    -- the per-rollout heuristics don't consume directly.
    local rolloutMemory = {}
    local prevForCopy = B.Bot and B.Bot._memory or {}
    for s = 1, 4 do
        rolloutMemory[s] = { played = {}, void = {} }
        local pm = prevForCopy[s]
        if pm then
            -- Deep-copy firstDiscard (table or nil) so rollout
            -- mutations don't bleed back into real Bot._memory.
            -- v1.0.2 (BM-01-DOC-DRIFT): the schema is `{suit, rank}`
            -- only — Bot.lua:140/375-376 confirms the writer never
            -- sets a `.bucket` field. Pre-fix copied a non-existent
            -- field as nil → harmless but misleading. Removed.
            if pm.firstDiscard then
                rolloutMemory[s].firstDiscard = {
                    suit = pm.firstDiscard.suit,
                    rank = pm.firstDiscard.rank,
                }
            end
            -- likelyKawesh is a boolean
            rolloutMemory[s].likelyKawesh = pm.likelyKawesh
        end
    end
    for _, t in ipairs(simTricks) do
        for _, p in ipairs(t.plays or {}) do
            if p.seat and p.card then
                rolloutMemory[p.seat].played[p.card] = true
                if t.leadSuit and C.Suit(p.card) ~= t.leadSuit then
                    rolloutMemory[p.seat].void[t.leadSuit] = true
                end
            end
        end
    end
    -- currentTrick has the candidate card already appended above; walk
    -- ALL its plays (real + candidate) so the seed reflects state at
    -- the moment heuristicPick is first called for the next seat.
    for _, p in ipairs(currentTrick.plays) do
        if p.seat and p.card then
            rolloutMemory[p.seat].played[p.card] = true
            if currentTrick.leadSuit and C.Suit(p.card) ~= currentTrick.leadSuit then
                rolloutMemory[p.seat].void[currentTrick.leadSuit] = true
            end
        end
    end

    -- v0.11.1 C-14 (HIGH from C_Bot_audit.md): heuristicPick now delegates
    -- to the full Bot.PickPlay path under the existing _inRollout=true
    -- guard set in BM.PickPlay. The previous Advanced-mirror placeholder
    -- (50 lines of pos/winner heuristics) substantially below Bot.PickPlay's
    -- coverage — missing sweep-pursuit, trick-8 boss-scan, free-trick
    -- suit, Sun L08, Tahreeb sender/receiver, Faranka exceptions, AKA
    -- receiver, Sun shortest-suit, Belote preservation, Tanfeer, etc.
    -- Audit measured this as the single highest-impact gap in the bot
    -- code: rollouts under-valued ~30% of Saudi-canonical play patterns.
    --
    -- Mechanism: BM.PickPlay sets B.Bot._inRollout = true (line 822) before
    -- entering the world loop. When this delegated heuristicPick calls
    -- Bot.PickPlay, that function's own delegation gate (Bot.lua:3450
    -- "if not Bot._inRollout") short-circuits the BotMaster re-entry,
    -- so we run pickLead/pickFollow directly without recursive ISMCTS.
    --
    -- State swap: Bot.PickPlay reads S.s.hostHands[seat], S.s.trick,
    -- S.s.tricks, S.s.akaCalled, S.s.playedCardsThisRound, and (v0.11.4)
    -- B.Bot._memory. We swap these to point at rollout-local views
    -- (hands, currentTrick, simTricks, nil for sim-blind AKA,
    -- rolloutPlayed, rolloutMemory) so the delegated picker sees the
    -- determinization-sampled state. Restored unconditionally below
    -- via pcall pattern so a mid-rollout error cannot leak the swap to
    -- subsequent worlds (which would corrupt the next sampleConsistentDeal
    -- call by reading polluted hostHands).
    local prevHostHands = S.s.hostHands
    local prevTrick = S.s.trick
    local prevTricks = S.s.tricks
    local prevAkaCalled = S.s.akaCalled
    local prevPlayed = S.s.playedCardsThisRound
    local prevMemory = B.Bot and B.Bot._memory or nil

    S.s.hostHands = hands
    S.s.trick = currentTrick
    S.s.tricks = simTricks
    S.s.akaCalled = nil   -- sim-blind: rollouts treat AKA as not-yet-called
    S.s.playedCardsThisRound = rolloutPlayed
    if B.Bot then B.Bot._memory = rolloutMemory end

    local function heuristicPick(s, _trick)
        -- _trick param kept for callsite compatibility but unused: the
        -- swap above means S.s.trick == currentTrick at all delegation
        -- points (we re-swap S.s.trick after each trick reset below).
        return B.Bot and B.Bot.PickPlay and B.Bot.PickPlay(s) or nil
    end

    -- v0.11.4 Bot1-01: helper to update rollout-local memory after a
    -- pick. Mirrors Bot.OnPlayObserved's played + void inference. Called
    -- after each `removeCard` + `rolloutPlayed[pick] = true` below.
    local function recordRolloutMemory(seat, pick, leadSuitAtPlay)
        local mem = rolloutMemory[seat]
        if not mem then return end
        mem.played[pick] = true
        if leadSuitAtPlay and C.Suit(pick) ~= leadSuitAtPlay then
            mem.void[leadSuitAtPlay] = true
        end
    end

    -- Play out the rest of the hand. Wrapped in pcall so a mid-rollout
    -- error (sampler edge case, malformed legal-set, etc.) doesn't leak
    -- the state swap to subsequent worlds in the outer BM.PickPlay loop.
    local result
    local ok = pcall(function()
        while #simTricks < 8 do
            if #currentTrick.plays == 4 then
                local winner = R.CurrentTrickWinner(currentTrick, contract)
                if not winner then break end
                currentTrick.winner = winner
                simTricks[#simTricks + 1] = currentTrick
                if #simTricks == 8 then break end
                currentTrick = { leadSuit = nil, plays = {} }
                S.s.trick = currentTrick   -- re-swap to the new trick
                local nextSeat = winner
                local pick = heuristicPick(nextSeat, currentTrick)
                if not pick then break end
                removeCard(hands[nextSeat], pick)
                rolloutPlayed[pick] = true
                -- Lead pick: leadSuit was nil at moment of pick; no void
                -- info to record. (Leader can't be void in their own lead.)
                recordRolloutMemory(nextSeat, pick, nil)
                currentTrick.leadSuit = C.Suit(pick)
                currentTrick.plays[1] = { seat = nextSeat, card = pick }
            else
                local prev = currentTrick.plays[#currentTrick.plays]
                local nextSeat = (prev.seat % 4) + 1
                local pick = heuristicPick(nextSeat, currentTrick)
                if not pick then break end
                removeCard(hands[nextSeat], pick)
                rolloutPlayed[pick] = true
                -- Follower: leadSuit is set; void inferred if pick's
                -- suit differs from leadSuit (didn't follow).
                recordRolloutMemory(nextSeat, pick, currentTrick.leadSuit)
                currentTrick.plays[#currentTrick.plays + 1] = { seat = nextSeat, card = pick }
            end
        end

        -- Accurate round scoring including melds and make/fail cliffs.
        -- R.ScoreRound + R.DetectMelds are pure (no S.s reads), so it's
        -- safe to compute under the swapped state.
        local meldsByTeam = { A = {}, B = {} }
        for s = 1, 4 do
            local team = R.TeamOf(s)
            local m = R.DetectMelds(initialHands[s], contract)
            for _, meld in ipairs(m) do
                meld.declaredBy = s
                table.insert(meldsByTeam[team], meld)
            end
        end
        result = R.ScoreRound(simTricks, contract, meldsByTeam)
    end)

    -- ALWAYS restore state, even on rollout error.
    S.s.hostHands = prevHostHands
    S.s.trick = prevTrick
    S.s.tricks = prevTricks
    S.s.akaCalled = prevAkaCalled
    S.s.playedCardsThisRound = prevPlayed
    if B.Bot then B.Bot._memory = prevMemory end

    if not ok or not result then return 0 end

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
    -- v0.10.3 audit (E-Det-01 #7, B-BotMaster-01 F1, D-RT-18 S1, HIGH):
    -- the outer driver was passing 5 args to R.IsLegalPlay, omitting
    -- the optional 6th `akaCalled`. Real-state legal filtering must
    -- respect Saudi-Master M4 AKA-receiver relief; without it, the
    -- bot's own legal set incorrectly excluded discards permitted by
    -- partner's AKA call (must-trump-ruff was enforced where Rules.lua
    -- M4 explicitly grants relief). Inner rollouts intentionally pass
    -- nil (sim-blind AKA semantics); the outer driver must NOT.
    local trick = S.s.trick or { leadSuit = nil, plays = {} }
    local legal = {}
    -- v0.11.4 Bot1-02 fix: wrap the legal-set construction in pcall so
    -- a R.IsLegalPlay error (corrupt card, malformed contract,
    -- AKA-relief edge case) cannot leak `_inRollout = true`. Pre-v0.11.4
    -- a single legality error inside this loop propagated up to Net.lua's
    -- outer pcall in MaybeRunBot, which caught the error but never
    -- restored the flag — silently disabling Saudi-Master ISMCTS for
    -- the rest of the session (every subsequent Bot.PickPlay would
    -- short-circuit at the delegation guard, falling through to
    -- heuristics). The C-14 v0.11.1 expansion widened the surface area
    -- where errors can occur (full pickLead/pickFollow now exposed via
    -- the rollout policy delegation), making this leak more likely. On
    -- failure we _restore(nil) to fall back cleanly to heuristics for
    -- THIS move only — Saudi-Master tier remains armed for the rest
    -- of the session. The named-function call form is used (rather
    -- than an inline closure) so I.4 (H4)'s structural test, which
    -- enforces per-world rollout granularity, still locates the
    -- correct rollout-loop entry as the first match.
    local function buildLegalSet()
        for _, c in ipairs(hand) do
            local lok = R.IsLegalPlay(c, hand, trick, S.s.contract, seat, S.s.akaCalled)
            if lok then legal[#legal + 1] = c end
        end
    end
    local legalOk = pcall(buildLegalSet)
    if not legalOk then
        BM._lastShortCircuit = "legal-build-failed"
        return _restore(nil)
    end
    if #legal == 0 then
        BM._lastShortCircuit = "no-legal-moves"
        return _restore(nil)
    end
    if #legal == 1 then
        -- v0.11.19 (ultra-audit BM-03 follow-up): tag single-card-
        -- shortcut path so /baloot ismctsdiag distinguishes
        -- "0 worlds because no rollout needed" from "0 worlds because
        -- budget cut on iter 1". Pre-fix users couldn't tell which.
        BM._lastShortCircuit = "single-card"
        BM._lastWorldsCompleted = 0
        return _restore(legal[1])
    end
    BM._lastShortCircuit = nil  -- enters world loop normally

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

    -- v0.5.3 BUG fix: wrap the rollout in pcall so a mid-rollout
    -- error (sampler nil-deref, malformed card, ScoreRound edge case)
    -- cannot escape with B.Bot._inRollout left = true. Without this,
    -- a single rollout error would silently disable Saudi Master ISMCTS
    -- for the rest of the session — every subsequent Bot.PickPlay
    -- would skip the BotMaster delegation guard at Bot.lua and fall
    -- through to heuristics. The outer pcall in Net.lua's MaybeRunBot
    -- catches the error but never restores _inRollout, hence this fix.
    --
    -- v0.8.6 H4 fix (audit AUDIT_REPORT_v0.7.1.md): pcall granularity
    -- moved to PER-WORLD. Pre-v0.8.6 the pcall wrapped the entire
    -- world loop, so ONE bad world (e.g., a sampler edge case in
    -- world 7 of 100) aborted ALL rollouts and dropped to heuristics
    -- — discarding the 99 healthy world evaluations. Now each world
    -- is wrapped independently; a failed world is silently skipped
    -- and the remaining worlds aggregate normally. With 100 worlds
    -- typical, losing 1-2 to errors is statistically irrelevant;
    -- losing all 100 to one bad world was the prior pathology.
    local rolloutErrors = 0
    -- v0.11.17 audit B2: wall-clock budget. Pre-v0.11.17 fixed numWorlds
    -- (100/60/30) × ~8 candidates × ~21 rollout-policy calls per world
    -- = ~16,800 full Bot.PickPlay invocations per move at trick 0.
    -- With each call traversing M3lm partner-style + memory + multiple
    -- HighestUnplayedRank scans, realistic load is 3-15 seconds per
    -- early-trick move — UI-perceptible stutter. Budget caps per-move
    -- at K.BOT_ISMCTS_BUDGET_SEC (default 0.5s); already-completed
    -- worlds vote, remaining worlds skipped. Saudi Master move
    -- responsiveness > marginal accuracy gained from world 80-100.
    local startedAt = (GetTime and GetTime()) or 0
    local budgetSec = (K and K.BOT_ISMCTS_BUDGET_SEC) or 0.5
    local worldsCompleted = 0
    for w = 1, numWorlds do
        if budgetSec > 0 and (GetTime and GetTime() or 0) - startedAt > budgetSec then
            break
        end
        local ok, err = pcall(function()
            local world = sampleConsistentDeal(seat, unseen)
            if world then
                for _, card in ipairs(legal) do
                    scores[card] = scores[card]
                                  + rolloutValue(seat, card, world, S.s.contract)
                end
            end
        end)
        if not ok then rolloutErrors = rolloutErrors + 1 end
        worldsCompleted = w
    end
    -- Track for ismctsdiag: actual worlds completed (vs configured numWorlds).
    BM._lastWorldsCompleted = worldsCompleted
    -- v0.11.18-final B2-FALLBACK-REGRESSION (ultra audit): compare
    -- against worldsCompleted, not numWorlds. With B2 budget, the
    -- loop can break early (worldsCompleted < numWorlds). Pre-fix
    -- the gate `rolloutErrors == numWorlds` could never fire after
    -- an early break — even if every completed world errored, we'd
    -- fall through to scoring with rolloutErrors == 5 != numWorlds == 100,
    -- picking legal[1] blindly with zero-data scores. Now the gate
    -- correctly triggers heuristic fallback when all completed
    -- worlds erred. Also handle worldsCompleted == 0 (budget=0.0 +
    -- GetTime overshot first iteration; defensive).
    if worldsCompleted == 0 or rolloutErrors == worldsCompleted then
        return _restore(nil)
    end

    local best, bestScore = legal[1], -math.huge
    for _, c in ipairs(legal) do
        if scores[c] > bestScore then best, bestScore = c, scores[c] end
    end
    return _restore(best)
end
