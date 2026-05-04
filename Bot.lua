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

-- Audit Tier 3 helper: is `seat` controlled by a bot? Thin proxy
-- to S.IsSeatBot (State.lua:624-626) so picker code can write
-- `if Bot.IsBotSeat(p)` without reaching into State for every
-- human-vs-bot branch. Used by Fzloky guards (H-12), partner-bid
-- bonus (H-11), and the human-pattern-exploitation Track-B work.
-- Returns false if the seats table is missing (defensive).
function Bot.IsBotSeat(seat)
    if not S or not S.IsSeatBot then return false end
    return S.IsSeatBot(seat) == true
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
            -- Audit Tier 4 (B-99): hand-annul (Kawesh) inference.
            -- After trick 3, if all opponent plays are rank 7/8/9, the
            -- opponent likely has a Kawesh hand they declined to call.
            -- BotMaster sampler de-weights trump strong-card pinning
            -- in the opponent slot when this is true.
            likelyKawesh = false,
        }
    end
    -- Audit Tier 4 (B-80 / H-10): trap-pass round detection. Captured
    -- before s.bids is cleared in HostBeginRound2 so bots can check
    -- whether everyone passed in round 1 — a trap-pass round signals
    -- weak overall, but a human bidding strong in R2 after a trap-pass
    -- R1 is often overcaution-recovery rather than genuine strength.
    m.r1WasAllPass = false
    return m
end

function Bot.ResetMemory()
    Bot._memory = emptyMemory()
    -- v0.5.10 Section 8: clear per-round Tahreeb signals on round-start.
    -- Bot.ResetMemory is called once per round; the other _partnerStyle
    -- counters (bels/triples/fours/gahwas/etc.) are intentionally
    -- per-game and stay across rounds.
    if Bot._partnerStyle then
        for s = 1, 4 do
            local style = Bot._partnerStyle[s]
            if style and style.tahreebSent then
                style.tahreebSent = { S = {}, H = {}, D = {}, C = {} }
            end
        end
    end
end

-- ---------------------------------------------------------------------
-- M3lm: partner play-style model
-- ---------------------------------------------------------------------
-- Per-seat aggregate counters, accumulated ACROSS the entire GAME
-- (not reset per round). Stable patterns let the bot calibrate to
-- known partner / opponent behaviour. Reset on Reset() / new game.
--
-- Counters:
--   bels       — how often this seat has Beled  (defender, ×2)
--   triples    — how often this seat has Tripled (bidder,   ×3)
--   fours      — how often this seat has Foured  (defender, ×4)
--   gahwas     — how often this seat has Gahwa'd (bidder,   match-win)
--   trumpEarly — trump LEAD before trick 5 (aggressive tempo)
--   trumpLate  — trump LEAD from trick 5 onwards (saver style)
Bot._partnerStyle = nil

local function emptyStyle()
    local m = {}
    for s = 1, 4 do
        m[s] = {
            bels = 0, triples = 0, fours = 0, gahwas = 0,
            trumpEarly = 0, trumpLate = 0,
            -- Audit Tier 4 counters (B-83, B-61, B-67, B-56):
            -- gahwaFailed: how often this seat called Gahwa and failed
            --   the contract. Reckless callers raise the bot's
            --   PickFour aggression against them.
            -- sunFail: how often this seat's Sun bid failed. Marker
            --   for defensive-Sun players (bidding Sun to block
            --   opponent Hokm rather than for genuine score). Raises
            --   PickDouble Bel threshold against repeat sunFailers.
            -- aceLate: late-trick (trick 5+) Ace plays. A-hoarder
            --   pattern — humans hold Aces to "save" them, often
            --   never spending. Sampler can de-prioritize A-pinning
            --   for high-aceLate seats.
            -- leadCount[suit]: how often this seat led the suit
            --   across the game. Repeat-lead suit is a partner
            --   convention signal; opponents can be over-trumped on
            --   their habitual lead suit.
            gahwaFailed = 0,
            sunFail     = 0,
            aceLate     = 0,
            leadCount   = { S = 0, H = 0, D = 0, C = 0 },
            -- v0.5.10 Section 8 Tahreeb (تهريب) signal log.
            --   tahreebSent[suit] = list of ranks recorded as discards
            --   while this seat's PARTNER was winning the trick. The
            --   sender's intent is encoded by the order of the list:
            --   ascending = "want this suit", descending = "don't want",
            --   single Ace at index 1 = Bargiya (برقية, "telegram" —
            --   strongest "lead this back" signal). Reset per round
            --   in Bot.OnRoundEnd (per-round, not per-game) so signals
            --   from a previous round don't leak into receiver
            --   inference.
            -- Sources: decision-trees.md Section 8 (Definite, videos
            -- 01, 02, 03, 09, 10).
            tahreebSent = { S = {}, H = {}, D = {}, C = {} },
        }
    end
    return m
end

function Bot.ResetStyle()
    Bot._partnerStyle = emptyStyle()
end

-- Hook into Net.lua at contract finalization so the seat that
-- escalated this round adds to their per-rung lifetime counter.
-- Net.lua calls this from _OnDouble / _OnTriple / _OnFour / _OnGahwa
-- with the rung kind ∈ {"double","triple","four","gahwa"}.
--
-- Audit fix: previous version always incremented `m.bels` regardless
-- of rung — a seat that Tripled or Gahwa'd inflated the bel counter
-- and styleBelTendency misclassified aggressive bidders as Bel-prone
-- defenders. Each rung now has its own counter.
function Bot.OnEscalation(seat, kind)
    if not Bot._partnerStyle then Bot._partnerStyle = emptyStyle() end
    local m = Bot._partnerStyle[seat]
    if not m then return end
    if     kind == "double" then m.bels    = m.bels    + 1
    elseif kind == "triple" then m.triples = m.triples + 1
    elseif kind == "four"   then m.fours   = m.fours   + 1
    elseif kind == "gahwa"  then m.gahwas  = m.gahwas  + 1
    else                         m.bels    = m.bels    + 1   -- legacy
    end
end

-- Audit Tier 4 (B-83 / B-61): per-round outcome callback. Invoked
-- from S.ApplyRoundEnd on every client (host bot decisions are the
-- only consumers, but maintaining the counters everywhere matches
-- how OnEscalation is wired). bidderMade may be true / false / nil
-- (nil when the round ended via Takweesh/SWA cancellation — no
-- contract outcome to record).
--
-- Updates:
--   gahwaFailed[bidder]: bidder called Gahwa AND failed → reckless
--   sunFail[bidder]:     Sun bidder failed → defensive-Sun marker
function Bot.OnRoundEnd(contract, bidderMade)
    if not Bot._partnerStyle then Bot._partnerStyle = emptyStyle() end
    if not contract or not contract.bidder then return end
    if bidderMade ~= false then return end  -- only count actual fails
    local m = Bot._partnerStyle[contract.bidder]
    if not m then return end
    if contract.gahwa then
        m.gahwaFailed = (m.gahwaFailed or 0) + 1
    end
    if contract.type == K.BID_SUN then
        m.sunFail = (m.sunFail or 0) + 1
    end
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
    --
    -- Audit fix: drop `leadSuit == contract.trump` from the conditions.
    -- On a LEAD play, leadSuit is nil (the seat opens a fresh trick),
    -- so the check was unreachable and the counters never moved.
    -- `#trickPlays == 1` after ApplyPlay already identifies a lead;
    -- combined with `cardSuit == contract.trump` we know it's a
    -- trump-LED trick.
    local contract = S.s and S.s.contract
    local trickPlays = (S.s.trick and S.s.trick.plays) or {}
    if contract and contract.type == K.BID_HOKM and contract.trump
       and cardSuit == contract.trump
       and (#trickPlays == 1) then
        local trickNum = #(S.s.tricks or {}) + 1
        if trickNum <= 4 then
            style.trumpEarly = style.trumpEarly + 1
        else
            style.trumpLate = style.trumpLate + 1
        end
    end

    -- Audit fix #22: when the off-suit play was a TRUMP RUFF in a
    -- Hokm contract (forced or chosen), it's not a "preference signal"
    -- — the seat had no choice. Don't poison the Fzloky firstDiscard
    -- ladder with this. Roll back the firstDiscard if it was set above
    -- AND the played card is trump.
    if not wasIllegal and leadSuit and cardSuit ~= leadSuit
       and contract and contract.type == K.BID_HOKM
       and contract.trump and cardSuit == contract.trump
       and mem.firstDiscard
       and mem.firstDiscard.suit == cardSuit
       and mem.firstDiscard.rank == C.Rank(card) then
        mem.firstDiscard = nil
    end

    -- Audit Tier 4 (B-56): per-suit lead counter. Accumulated on every
    -- LEAD play (trickPlays count was 1 after ApplyPlay since this is
    -- the first card of the trick). Used for repeat-lead pattern
    -- detection — a seat that habitually leads suit X is exploitable
    -- by opponents who hoard high cards in X waiting to over-trump.
    if (#trickPlays == 1) and style.leadCount then
        style.leadCount[cardSuit] = (style.leadCount[cardSuit] or 0) + 1
    end

    -- v0.5.10 Section 8 Tahreeb recording. When `seat` plays a non-led
    -- suit (discard) AND their partner was winning the trick BEFORE
    -- this play, the discard is a Tahreeb signal directed at the
    -- partner. Record (suit, rank) in `Bot._partnerStyle[seat].
    -- tahreebSent[suit]` so the partner-of-`seat` (us, when we read
    -- partner's signals later) can classify direction:
    --   • single Ace at index 1 → Bargiya (برقية, "lead this back")
    --   • ascending sequence (rank order rises) → "want this suit"
    --   • descending sequence → "do NOT want this suit"
    -- Two events are needed for high-confidence direction; a single
    -- discard is a hint (per video #09: "تهريب يحتاج تهريب ثاني عشان
    -- يأكد"). The picker (pickLead M3lm+) decides what to act on.
    -- Sources: decision-trees.md Section 8 (Definite, videos 01, 02,
    -- 03, 09, 10).
    if not wasIllegal and leadSuit and cardSuit ~= leadSuit
       and contract and style.tahreebSent then
        -- Was partner-of-`seat` winning the trick BEFORE this play?
        -- Construct a "prior plays" trick (everything except the play
        -- we just observed, which is the most recent entry) and check
        -- the trick winner.
        local plays = trickPlays
        if plays and #plays >= 2 then
            local prior = {}
            for i = 1, #plays - 1 do prior[i] = plays[i] end
            local priorTrick = { plays = prior, leadSuit = leadSuit }
            local prevWinner = R.CurrentTrickWinner(priorTrick, contract)
            if prevWinner and R.Partner(seat) == prevWinner then
                -- Discard while partner is winning = Tahreeb signal.
                local list = style.tahreebSent[cardSuit]
                if list then
                    list[#list + 1] = C.Rank(card)
                end
            end
        end
    end

    -- Audit Tier 4 (B-67): late-trick Ace counter. Aces played at
    -- trick 5 or later are A-hoarder pattern — humans tend to "save"
    -- Aces and never spend them, ending up forced to dump them late.
    -- Sampler de-prioritizes Ace pinning for high-aceLate seats.
    if C.Rank(card) == "A" then
        local trickNum = #(S.s.tricks or {}) + 1
        if trickNum >= 5 and style.aceLate ~= nil then
            style.aceLate = style.aceLate + 1
        end
    end

    -- Audit Tier 4 (B-99): missed-Kawesh inference. After trick 3+, if
    -- ALL of this seat's plays so far have been rank 7/8/9, they
    -- likely held a Kawesh hand (5+ low cards) but declined to call
    -- hand-annul — playing the round out with low cards expecting
    -- cheap captures. The flag is descriptive (per-seat behavior
    -- pattern); the team-relative gating (only consult flag for
    -- opponents, not partners) lives at the BotMaster sampler
    -- consumer site to avoid losing partner Fzloky-signal bias.
    if not wasIllegal then
        local trickNum = #(S.s.tricks or {}) + 1
        if trickNum >= 3 then
            local allLow = true
            local anyPlay = false
            for c2 in pairs(mem.played) do
                anyPlay = true
                local r = C.Rank(c2)
                if r ~= "7" and r ~= "8" and r ~= "9" then
                    allLow = false
                    break
                end
            end
            mem.likelyKawesh = anyPlay and allLow
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

-- Audit Tier 4 (B-77): is ANY opponent (not all) known void in `suit`?
-- Used by pickLead's Ace-lead opportunist branch — if one opponent is
-- void, our high card faces only one possible defender, dramatically
-- reducing over-trump risk in Hokm. (Without this helper the bot was
-- only willing to lead a high non-trump when BOTH opponents were void
-- — a much rarer condition.)
local function anyOpponentVoidIn(seat, suit)
    if not Bot._memory then return false end
    for opp = 1, 4 do
        if R.TeamOf(opp) ~= R.TeamOf(seat) then
            if Bot._memory[opp] and Bot._memory[opp].void[suit] then
                return true
            end
        end
    end
    return false
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
            -- 13th-bot-audit fix: 8 and 7 of trump are worth 2 each
            -- per Saudi Hokm point convention. Previously fell through
            -- with 0 contribution, undercounting trump-rich hands.
            elseif r == "8" then strength = strength + 2
            elseif r == "7" then strength = strength + 2
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

-- v0.5.8 patch B-1/B-4 (decision-trees.md Section 1, Hokm bidding):
-- the Saudi minimum-Hokm shape is "الحكم المغطى" — J of trump + ≥1
-- cover trump (مردوفة, so count >= 2) + ≥1 side Ace (B-1).
-- The B-2 escape clause: 4+ trumps including J is enough on its own,
-- side-Ace not required (trump-heavy hand is self-sufficient). The
-- absolute floor (B-4) is "no J OR count <= 2 → never bid Hokm".
-- Audit fix (post-v0.5.8 commit, before tag): the original gate
-- enforced only J + count >= 3 and missed the side-Ace requirement
-- of B-1 — a J + 2 trumps + 0 side-Ace hand passed the gate even
-- though it has no side trick power. Now correctly implements:
--   (count >= 4 AND hasJ)  ← B-2 self-sufficient
--   OR
--   (count == 3 AND hasJ AND hasSideAce)  ← B-1 minimum
-- Returns true if the minimum shape is met.
--
-- Sources: decision-trees.md Section 1 rules B-1, B-2, B-4 (all
-- Definite, video 26).
local function hokmMinShape(hand, suit)
    if not suit then return false end
    local hasJ, count = false, 0
    local hasSideAce = false
    for _, c in ipairs(hand) do
        local r, su = C.Rank(c), C.Suit(c)
        if su == suit then
            count = count + 1
            if r == "J" then hasJ = true end
        elseif r == "A" then
            hasSideAce = true
        end
    end
    if not hasJ then return false end          -- B-4 absolute floor
    if count >= 4 then return true end         -- B-2 self-sufficient
    if count == 3 and hasSideAce then return true end  -- B-1 minimum
    return false
end

-- v0.5.8 patch S-1/S-5 (decision-trees.md Section 1, Sun bidding):
-- the Saudi minimum-Sun shape is either A+T mardoofa (إكة مردوفة) OR
-- 2+ Aces. A bare 1-Ace hand without T-cover is the canonical "do
-- NOT bid Sun" anti-trigger — the lone Ace gets torn through.
-- Returns true if the minimum shape is met.
--
-- Sources: decision-trees.md Section 1 rules S-1, S-5 (Definite/Common,
-- video 25).
local function sunMinShape(hand)
    local aceCount = 0
    local hasA = { S = false, H = false, D = false, C = false }
    local hasT = { S = false, H = false, D = false, C = false }
    for _, c in ipairs(hand) do
        local r, su = C.Rank(c), C.Suit(c)
        if r == "A" then hasA[su] = true; aceCount = aceCount + 1
        elseif r == "T" then hasT[su] = true end
    end
    if aceCount >= 2 then return true end
    if aceCount == 1 then
        for _, su in ipairs({ "S", "H", "D", "C" }) do
            if hasA[su] and hasT[su] then return true end  -- mardoofa
        end
    end
    return false
end

-- v0.5.8 patch B-6 (decision-trees.md Section 1, Hokm bidding):
-- detect Belote pair (K+Q of same suit, "سراء ملكي"). The +20 Belote
-- bonus is multiplier-immune so locking it in by bidding the suit
-- as trump is a Saudi MUST. Returns the suit (string) holding K+Q
-- if any, else nil.
--
-- Sources: decision-trees.md Section 1 rule B-6 (Definite, video 26).
local function beloteSuit(hand)
    local hasK = { S = false, H = false, D = false, C = false }
    local hasQ = { S = false, H = false, D = false, C = false }
    for _, c in ipairs(hand) do
        local r, su = C.Rank(c), C.Suit(c)
        if r == "K" then hasK[su] = true
        elseif r == "Q" then hasQ[su] = true end
    end
    for _, su in ipairs({ "S", "H", "D", "C" }) do
        if hasK[su] and hasQ[su] then return su end
    end
    return nil
end

-- v0.5.8 patches S-3/S-4/S-8 helper: count Aces and detect mardoofa
-- (A+T pair in same suit). Returns aceCount, mardoofaCount.
--
-- Sources: decision-trees.md Section 1 rules S-3 (3+ Aces strong),
-- S-4 (Carré of Aces mandatory Sun), S-8 (Sun-Mughataa).
local function aceCountAndMardoofa(hand)
    local aceCount = 0
    local hasA = { S = false, H = false, D = false, C = false }
    local hasT = { S = false, H = false, D = false, C = false }
    for _, c in ipairs(hand) do
        local r, su = C.Rank(c), C.Suit(c)
        if r == "A" then hasA[su] = true; aceCount = aceCount + 1
        elseif r == "T" then hasT[su] = true end
    end
    local mardoofaCount = 0
    for _, su in ipairs({ "S", "H", "D", "C" }) do
        if hasA[su] and hasT[su] then mardoofaCount = mardoofaCount + 1 end
    end
    return aceCount, mardoofaCount
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
    -- 13th-bot-audit fix: also track per-suit Aces / Kings / Queens
    -- so we can detect AKQ "stopper" patterns and length walks.
    local hasA   = { S = false, H = false, D = false, C = false }
    local hasK   = { S = false, H = false, D = false, C = false }
    local hasQ   = { S = false, H = false, D = false, C = false }
    for _, card in ipairs(hand) do
        local r = C.Rank(card)
        local su = C.Suit(card)
        count[su] = count[su] + 1
        if r == "A" or r == "T" or r == "K" then honors[su] = true end
        if r == "A" then hasA[su] = true
        elseif r == "K" then hasK[su] = true
        elseif r == "Q" then hasQ[su] = true end
        if     r == "A" then s = s + 11
        elseif r == "T" then s = s + 10
        elseif r == "K" then s = s + 4
        elseif r == "Q" then s = s + 3
        elseif r == "J" then s = s + 2
        end
    end
    -- 13th-bot-audit fix (Codex+sunStrength agent): long suits with
    -- a top card (A or K) "walk" in Sun once opponents are out — bonus
    -- +6 per card beyond 4 in such suits. Without this, a 6-card suit
    -- AKQxxx scored barely above 18; should be ~30+.
    for _, su in ipairs({ "S", "H", "D", "C" }) do
        if count[su] >= 5 and (hasA[su] or hasK[su]) then
            s = s + (count[su] - 4) * 6
        end
        -- Stopper triple: AKQ in same suit means 3 guaranteed tricks.
        if hasA[su] and hasK[su] and hasQ[su] then s = s + 8 end
    end
    if Bot.IsAdvanced() then
        local penalty = 0
        for _, su in ipairs({ "S", "H", "D", "C" }) do
            if count[su] < 2 or not honors[su] then penalty = penalty + 10 end
        end
        -- Cap softened from 25 to 18 (Gemini): lopsided hands with a
        -- solid long suit shouldn't bleed all of their headroom.
        s = s - math.min(penalty, 18)
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
--   • partner PASS (bot)              → -10 (calibrated weakness)
--   • partner PASS (human)            →  -5 (may be overcaution)
--   • no info / unknown               →  0
--
-- Audit Tier 3 (H-11): bot PASS = calibrated bot-side weakness signal.
-- Human PASS = often overcaution: humans pass marginal hands a bot
-- would have bid. Treating them identically suppresses Triple/Four/
-- Gahwa after a human partner's PASS even when our own hand merits
-- escalation. Halve the penalty for human partners.
local function partnerBidBonus(seat, contract)
    if not Bot.IsAdvanced() then return 0 end
    if not S.s.bids then return 0 end
    local partner = R.Partner(seat)
    local b = S.s.bids[partner]
    if not b then return 0 end
    if b == K.BID_SUN then return 15 end
    if b == K.BID_ASHKAL then return 15 end
    if b == K.BID_PASS then
        return Bot.IsBotSeat(partner) and -10 or -5
    end
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
--   • near win (cumulative >= target-25): -8 (more conservative)
--   • near loss (opp cumulative >= target-25): +12 (desperate)
--   • behind by 80+: +6 (take risks)
--   • else: 0
--
-- 6th-audit fix: signs were previously inverted vs. the comments.
-- Callers do `th = base - urgency`, so a POSITIVE return lowers
-- threshold (more aggressive); a NEGATIVE return raises it (more
-- conservative). Near-win = conservative ⇒ negative; near-loss =
-- desperate ⇒ positive; far-behind = take risks ⇒ positive. The
-- old returns gave the opposite of the documented intent.
-- v0.5 H-8: context-aware near-win modifier. The "we're nearly won"
-- branch was uniformly -8 (conservative offensive bid), but in
-- DEFENSIVE escalations (Bel, Four) Saudi pros do the opposite —
-- they aggress when one win clinches the match. context="defend"
-- flips that branch to +5 (more aggressive defensive escalation);
-- "bid" preserves the original -8 for offensive bid evaluation.
local function scoreUrgency(myTeam, context)
    if not Bot.IsAdvanced() then return 0 end
    if not S.s.cumulative or not myTeam then return 0 end
    local me  = S.s.cumulative[myTeam] or 0
    local opp = S.s.cumulative[(myTeam == "A") and "B" or "A"] or 0
    local target = (S.s.target or 152)
    if me  >= target - 25 then
        -- Defender Bel/Four near clinch: aggress (+5). Bidder bid: stay
        -- conservative (-8). Default to "bid" for backward compat with
        -- callers that haven't been updated.
        if context == "defend" then return  5 end
        return -8
    end
    if opp >= target - 25 then return  12 end   -- desperate when nearly lost
    if opp - me > 80      then return  6  end   -- take risks when far behind
    return 0
end

-- M3lm-only: smoother match-point urgency. Layers on top of
-- scoreUrgency with a finer-grained curve based on distance-to-win.
-- Returns ADDITIONAL modifier to subtract from threshold (so positive
-- = more aggressive, negative = more conservative — same convention
-- as scoreUrgency).
--   • opponent  ≥ target-15  : extra +8  (defensive desperation)
--   • opponent  ≥ target-40  : extra +3  (caution → guard the lead)
--   • we        ≥ target-15  : extra -5  (lock it down)
--   • behind by 50..80       : extra +3  (take measured risk)
--
-- 6th-audit fix: signs flipped to match the documented threshold
-- convention. The previous code returned negative-when-aggressive,
-- which the caller's subtraction inverted into the wrong direction.
local function matchPointUrgency(myTeam)
    if not Bot.IsM3lm() then return 0 end
    if not S.s.cumulative or not myTeam then return 0 end
    local me  = S.s.cumulative[myTeam] or 0
    local opp = S.s.cumulative[(myTeam == "A") and "B" or "A"] or 0
    local target = (S.s.target or 152)
    local mod = 0
    if opp >= target - 15 then mod = mod + 5    -- was +8
    elseif opp >= target - 40 then mod = mod + 2 end  -- was +3
    if me  >= target - 15 then mod = mod - 5 end
    local diff = opp - me
    if diff > 50 and diff <= 80 then mod = mod + 3 end

    -- Audit Tier 4 (B-47, B-50): factor opponent escalation history
    -- into the score-urgency modifier. The data is per-seat, so we
    -- aggregate across both opponent seats on the opp team.
    if Bot._partnerStyle then
        local oppTeam = (myTeam == "A") and "B" or "A"
        local oppGahwas, oppFours = 0, 0
        for s2 = 1, 4 do
            if R.TeamOf(s2) == oppTeam then
                local m = Bot._partnerStyle[s2]
                if m then
                    oppGahwas = oppGahwas + (m.gahwas or 0)
                    oppFours  = oppFours  + (m.fours  or 0)
                end
            end
        end
        -- B-47: gahwa-prone opponent who is now trailing by 50+ may
        -- attempt a desperate Gahwa to spike. Add +3 so our defensive
        -- Bel threshold drops; we're ready to counter-escalate.
        -- Note `diff = opp - me` so diff < -50 means OPP is trailing.
        if oppGahwas >= 2 and diff <= -50 then
            mod = mod + 3
        end
        -- B-50: opponent has never escalated (no Fours, no Gahwas).
        -- Passive players don't spike points via hand-killers, so the
        -- "we're far behind, take risks" branch should be dampened —
        -- we won't lose to a desperate opponent escalation that won't
        -- come. Replace +3 with +1 in the diff > 50 branch when both
        -- are zero.
        if oppFours == 0 and oppGahwas == 0 and diff > 50 and diff <= 80 then
            mod = mod - 2  -- net effect: +3 → +1
        end
    end

    -- 13th-bot-audit fix (Codex catch): cap output so stacking with
    -- scoreUrgency doesn't drop thresholds past 50% (Bel 70→50 etc).
    -- Saudi tournament play uses target-15 as the canonical "near"
    -- boundary; magnitudes were also halved on the opp-near branches.
    if mod >  10 then mod =  10 end
    if mod < -10 then mod = -10 end
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
    -- Audit fix #8: gate on IsAdvanced rather than IsM3lm. Reading
    -- the contract escalation flags is structural state inspection,
    -- not a tier-3 partner-style model — Advanced bots should benefit
    -- too. (M3lm-specific style modeling lives in styleBelTendency etc.)
    if not Bot.IsAdvanced() then return 0 end
    if not contract then return 0 end
    local p = R.Partner(seat)
    if not p or not contract.bidder then return 0 end
    -- v0.2.0: contract escalation roles have flipped from the 5-rung
    -- chain. Mapping:
    --   contract.doubled — set by the defender (Bel)
    --   contract.tripled — set by the bidder (Triple)
    --   contract.foured  — set by the defender (Four)
    --   contract.gahwa   — set by the bidder (Gahwa, match-win)
    --
    -- Audit fix #24: previous code did `p == defender` where
    -- `defender = bidder+1`. Since defenders are at bidder+1 AND
    -- bidder+3, the check missed the case where p == bidder+3, so
    -- only one of the two defender seats received the bonus. Use
    -- team membership: p is on defender team iff R.TeamOf(p) differs
    -- from R.TeamOf(bidder).
    local pTeam       = R.TeamOf(p)
    local bidderTeam  = R.TeamOf(contract.bidder)
    local pIsDefender = pTeam and bidderTeam and pTeam ~= bidderTeam
    local pIsBidderTeam = pTeam and bidderTeam and pTeam == bidderTeam
    local bonus = 0
    -- Defender-team partner: their team has been escalating (Bel/Four).
    if pIsDefender then
        if contract.doubled then bonus = bonus + 5  end
        if contract.foured  then bonus = bonus + 8  end
    end
    -- Bidder-team partner: their team has been escalating (Triple/Gahwa).
    if pIsBidderTeam then
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
    local bidCardRank = S.s.bidCard and C.Rank(S.s.bidCard) or nil

    -- v0.5.8 patch S-4 (decision-trees.md Section 1, Sun bidding):
    -- Carré of Aces (الأربع مئة, "Four Hundred") = 200 raw × 2 (Sun
    -- multiplier) = 400 effective. Saudi rule: ALWAYS Sun, regardless
    -- of any other consideration. Earliest possible return — beat
    -- every other bid path.
    -- Sources: decision-trees.md S-4 (Definite, videos 25, 32, 38).
    local aceCount, mardoofaCount = aceCountAndMardoofa(hand)
    if aceCount >= 4 then return K.BID_SUN end

    -- Inspect prior bids to know what's still available to us.
    local anyHokm, anySun = false, false
    for s2 = 1, 4 do
        local b = S.s.bids[s2]
        if b == K.BID_SUN then anySun = true
        elseif b and b:sub(1, 4) == K.BID_HOKM then anyHokm = true end
    end

    -- v0.5.8 patches S-3, S-8 (decision-trees.md Section 1, Sun bidding):
    -- bonus to sunStrength for 3+ Aces (S-3) and per-mardoofa pair (S-8).
    -- S-3: nudge to clear thSun without being over-determinative.
    -- S-8: each A+T mardoofa pair is "Sun-Mughataa" (covered Sun) —
    -- distinctly safer than 2 separate Aces. Capped at 2 pairs to
    -- avoid double-rewarding when 3+ Aces already nudged via S-3.
    --
    -- v0.5.13 calibration: bonus values and pair cap promoted to K.*
    -- constants. The S-3 bonus was bumped from 12 → 15 per the Wave-2
    -- audit finding that 3-Ace hands without AKQ triple landed at
    -- sun≈41 vs thSun=44–56 (couldn't fire R1) — doc ranks S-3
    -- "Definite, almost always Sun" so the formula should clear the
    -- median threshold reliably. +15 puts the floor at sun≈44, which
    -- crosses thSun in ~70% of jitter outcomes vs ~30% under +12.
    -- Sources: decision-trees.md S-3 (Definite, video 25), S-8
    -- (Common, video 25); Wave-2 audit calibration analysis.
    local sun = sunStrength(hand)
    if aceCount >= 3 then sun = sun + K.BOT_SUN_3ACE_BONUS end
    sun = sun + math.min(mardoofaCount, K.BOT_SUN_MARDOOFA_PAIR_CAP)
              * K.BOT_SUN_MARDOOFA_BONUS

    -- v0.5.8 patch B-6 (decision-trees.md Section 1, Hokm bidding):
    -- detect Belote (سراء ملكي = K+Q of trump). The +20 Belote bonus
    -- is multiplier-immune so locking it in by bidding the suit as
    -- trump is a Saudi MUST. Computed once, applied in both round 1
    -- (Hokm-on-flipped) and round 2 (best-suit search).
    -- Sources: decision-trees.md B-6 (Definite, video 26).
    local belote = beloteSuit(hand)

    local urgency = (scoreUrgency(R.TeamOf(seat)) + matchPointUrgency(R.TeamOf(seat)))
    -- Round-2 threshold ought to be ≥ round-1: in R2 the bidder picks
    -- the suit, so fewer hands are forced to commit. Advanced layer
    -- enforces this; basic mode keeps the existing R2<R1 split.
    --
    -- 13th-bot-audit fix (Codex+Gemini consensus): the Advanced bump
    -- was previously +6 (r2Base=48), making M3lm pass winnable
    -- marginal hands that Basic scooped up — directly responsible for
    -- the headless-tournament regression where M3lm bidder-team-avg
    -- (97.7) under-performed Basic (99.1). Reduce to +2 so Advanced
    -- R2 (38) is only mildly stricter than Basic R2 (36) — still
    -- consistent with "R2 should be ≥ R1" intent (since R1=42 base,
    -- R2=38 with the fix is still below R1, matching basic-mode
    -- semantics; the bump just prevents R2 from being _easier_ in
    -- Advanced after urgency stacks).
    local r1Base = TH_HOKM_R1_BASE
    local r2Base = TH_HOKM_R2_BASE
    if Bot.IsAdvanced() then r2Base = math.max(r2Base, r1Base - 4) end
    -- Audit Tier 4 (B-80 / H-10): trap-pass detection. When R1 was
    -- all-pass (every seat declined the flipped suit), the table is
    -- weak overall — R2 thresholds should drop slightly so we don't
    -- under-bid back into a redeal. M3lm-gated since the data only
    -- becomes meaningful when partner-style differentiation is on.
    if round == 2 and Bot.IsM3lm() and Bot.r1WasAllPass then
        r2Base = r2Base - 6
    end
    local thHokmR1 = jitter(r1Base    - urgency, BID_JITTER)
    local thHokmR2 = jitter(r2Base    - urgency, BID_JITTER)
    local thSun    = jitter(TH_SUN_BASE - urgency, BID_JITTER)

    if round == 1 then
        -- v0.5.8 ORDER FIX: Ashkal-eligibility check moved BEFORE direct Sun.
        -- Previously the direct-Sun branch fired at sun >= thSun (50) and
        -- short-circuited the Ashkal block (which needed sun >= thAshkal=65)
        -- — Ashkal was effectively dead code unless urgency stacks made
        -- thSun > thAshkal (rare extreme). The decision-tree expects an
        -- eligible Ashkal seat in the 65-84 strength band to PREFER Ashkal
        -- over direct Sun (the 65-84 vs 85+ pivot, A-6). Restructuring
        -- here makes the patch set A-3/A-4/A-5/A-6 actually have effect.
        -- Sources: decision-trees.md A-2 through A-6 (videos 27, 31).

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
            local ok = true

            -- v0.5.8 patch A-3 (decision-trees.md): bid-up card is A
            -- → don't Ashkal. Losing the A into a no-trump contract
            -- with no T-cover is a textbook bad Ashkal — the Ace gets
            -- torn through immediately by opponents.
            -- Sources: decision-trees.md A-3 (Definite, video 31).
            if bidCardRank == "A" then ok = false end

            -- v0.5.8 patch A-4 (decision-trees.md): bid-up is T AND
            -- we hold A of the same suit → don't Ashkal. The A+T
            -- mardoofa pair is preserved by the Hokm contract; an
            -- Ashkal converts to Sun and breaks the cover.
            -- Sources: decision-trees.md A-4 (Common, video 31).
            if ok and bidCardRank == "T" and bidCardSuit then
                for _, c in ipairs(hand) do
                    if C.Rank(c) == "A" and C.Suit(c) == bidCardSuit then
                        ok = false; break
                    end
                end
            end

            -- v0.5.8 patch A-5 (decision-trees.md): 3+ Aces in hand
            -- → bid direct Sun, not Ashkal. With that much firepower
            -- we don't need partner's project — claim the contract
            -- ourselves so partner-supply isn't a precondition.
            -- Sources: decision-trees.md A-5 (Common, video 31).
            if ok and aceCount >= 3 then ok = false end

            -- v0.5.8 patch A-6 (decision-trees.md): the 65/85 pivot.
            -- 65-84 strength = Ashkal range (need partner's project);
            -- 85+ strength = direct Sun range (claim it ourselves).
            -- The fall-through here lets sun >= cutoff hands proceed
            -- to the direct-Sun branch below.
            -- v0.5.13: 85 promoted to K.BOT_ASHKAL_DIRECT_SUN_PIVOT.
            -- Sources: decision-trees.md A-6 (Common, video 31).
            if ok and sun >= K.BOT_ASHKAL_DIRECT_SUN_PIVOT then
                ok = false
            end

            -- Existing Advanced check: only Ashkal if WE'RE weak in
            -- the flipped suit (so partner's J of that suit is doing
            -- the work, not ours). If we hold the J of the flipped
            -- suit, partner's bid is bluff/marginal and Ashkal is risky.
            if ok and Bot.IsAdvanced() and bidCardSuit then
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

        -- v0.5.8 patch S-1 (decision-trees.md): direct Sun requires
        -- minimum shape — A+T mardoofa OR 2+ Aces. A bare 1-Ace hand
        -- without T-cover gets torn through; do not bid Sun on it.
        -- Sources: decision-trees.md S-1 (Definite, video 25), S-5
        -- (Common, video 25), S-6 (Common, video 25).
        --
        -- Sun overcalls Hokm. Note: a LATER direct Sun does NOT
        -- overcall an earlier direct Sun — host's HostAdvanceBidding
        -- locks on the first direct Sun. Bot bids Sun whenever its
        -- threshold passes; if another seat already won the Sun chair
        -- earlier, the host silently treats this as a no-op.
        if sunMinShape(hand) and sun >= thSun then return K.BID_SUN end

        -- Hokm-on-flipped only available if no prior Hokm/Sun.
        -- v0.5.8 patches B-1, B-4, B-6: gate on hokmMinShape (J of
        -- trump + count >= 3) — Saudi 3-card minimum, "no J = pass".
        -- Belote (K+Q of trump same suit) adds a +20 multiplier-immune
        -- bonus when the bid-up suit IS the Belote suit.
        -- Sources: decision-trees.md B-1 (Definite, 26), B-4 (Definite, 26), B-6 (Definite, 26).
        if not anyHokm and not anySun and bidCardSuit then
            if hokmMinShape(hand, bidCardSuit) then
                local strength = suitStrengthAsTrump(hand, bidCardSuit)
                strength = strength + sideSuitAceBonus(hand, bidCardSuit)
                -- v0.5.13: B-6 +20 promoted to K.BOT_PICKBID_BELOTE_BONUS
                -- (which mirrors K.MELD_BELOTE so the bid bonus tracks
                -- the actual scoring bonus if either is ever retuned).
                if belote == bidCardSuit then
                    strength = strength + K.BOT_PICKBID_BELOTE_BONUS
                end
                if strength >= thHokmR1 then
                    return K.BID_HOKM .. ":" .. bidCardSuit
                end
            end
        end
        return K.BID_PASS
    end

    -- Round 2: pass / Hokm-non-flipped / Sun. Both rounds now wait
    -- for all 4 bids and Sun overcalls Hokm in either round.
    --
    -- v0.5.8 patches B-1/B-4/B-6: only consider suits where the
    -- minimum-Hokm shape is met (J + count >= 3). Suits with no J,
    -- or fewer than 3 trumps, are skipped — Saudi rule, not heuristic.
    -- Belote suit (K+Q same suit) gets the +20 multiplier-immune bonus.
    -- Sources: decision-trees.md B-1, B-4 (Definite, video 26), B-6 (Definite, video 26).
    local bestSuit, bestScore = nil, 0
    for _, suit in ipairs(K.SUITS) do
        if suit ~= bidCardSuit and hokmMinShape(hand, suit) then
            local s = suitStrengthAsTrump(hand, suit)
            s = s + sideSuitAceBonus(hand, suit)
            -- v0.5.13: +20 → K.BOT_PICKBID_BELOTE_BONUS (mirrors K.MELD_BELOTE).
            if belote == suit then s = s + K.BOT_PICKBID_BELOTE_BONUS end
            if s > bestScore then bestSuit, bestScore = suit, s end
        end
    end
    -- v0.5.8 patch B-5: 16-vs-26 failed-bid asymmetry. When BOTH Hokm
    -- and Sun are viable, prefer Hokm UNLESS Sun beats it by ≥ 5
    -- strength points. Failed Hokm = 16 raw, failed Sun = 26 raw —
    -- so the conservative default is Hokm. Sun must clearly justify
    -- the +10 raw downside swing.
    -- Sources: decision-trees.md B-5 (Definite, videos 25 + 26).
    -- Patch S-1 also gates Sun on minimum shape (mardoofa or 2+ Aces).
    if sunMinShape(hand) and sun >= thSun then
        local hokmViable = (bestSuit and bestScore >= thHokmR2)
        if not hokmViable then
            return K.BID_SUN
        end
        -- v0.5.13: B-5 +5 margin → K.BOT_BIDDING_SUN_OVER_HOKM_MARGIN.
        if sun >= bestScore + K.BOT_BIDDING_SUN_OVER_HOKM_MARGIN then
            return K.BID_SUN
        end
        -- Otherwise: both viable, Sun's margin too thin → stay Hokm
        -- (falls through to Hokm return below).
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

-- v0.5.1 C-4 helper: pick the highest-FACE-VALUE card from a list,
-- tie-broken by trick rank. Used for last-trick targeting where the
-- LAST_TRICK_BONUS (+10) plus the card's face value matters more
-- than its trick-rank (winning the last trick with a Ten = 10 face
-- + 10 bonus = 20 effective vs winning with a 7 = 0+10 = 10).
local function highestByFaceValue(cards, contract)
    local best, bestPts, bestRank = cards[1], -1, -1
    for _, c in ipairs(cards) do
        local pts = C.PointValue(c, contract) or 0
        if pts > bestPts then
            best, bestPts, bestRank = c, pts, C.TrickRank(c, contract)
        elseif pts == bestPts then
            local r = C.TrickRank(c, contract)
            if r > bestRank then best, bestRank = c, r end
        end
    end
    return best
end

-- v0.5.1 H-4 helper: do we currently hold BOTH K and Q of trump
-- (the Belote pair)? Belote scores +20 raw post-multiplier when
-- both cards are played from the same hand within a single round —
-- so we want to preserve them through the early discards.
-- Hokm-only; Sun has no trump so Belote doesn't apply.
local function holdsBeloteThusFar(hand, contract)
    if not contract or contract.type ~= K.BID_HOKM or not contract.trump then
        return false
    end
    local trump = contract.trump
    local hasK, hasQ = false, false
    for _, c in ipairs(hand) do
        if C.Suit(c) == trump then
            local r = C.Rank(c)
            if     r == "K" then hasK = true
            elseif r == "Q" then hasQ = true end
        end
    end
    return hasK and hasQ
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

-- v0.5.10 Section 8: classify a partner's recorded Tahreeb signal in
-- a single suit. `signals` is a list of ranks (e.g. {"7","9"} =
-- ascending = "want this suit"; {"J","9"} = descending = "do NOT want
-- this suit"; {"A"} at index 1 = Bargiya).
--
-- Returns one of:
--   "bargiya"  — partner discarded the Ace; lead-this-back signal.
--   "want"     — ascending sequence of ≥2 events; partner wants this.
--   "dontwant" — descending sequence of ≥2 events; partner refuses.
--   "hint"     — exactly 1 event (≠ Ace); ambiguous, wait for second.
--   nil        — no signal.
--
-- Sources: decision-trees.md Section 8 (Definite, videos 01, 09, 10).
local function tahreebClassify(signals)
    if not signals or #signals == 0 then return nil end
    -- Bargiya = the very first observed discard in this suit was the Ace.
    -- Per video #14 there are two semantic flavors of Bargiya (invite vs
    -- defensive shed), but for receiver-side action we treat both as
    -- "lead-this-back" — the worst case is leading partner's strong
    -- suit, which is still a reasonable play. Defer the
    -- invite-vs-shed disambiguation to a future patch with better
    -- hand-shape inference.
    if signals[1] == "A" then return "bargiya" end
    if #signals == 1 then return "hint" end
    -- Compare rank-order indices using K.RANK_PLAIN (the non-trump
    -- ordering: 7<8<9<J<Q<K<T<A). Tahreeb signals are in non-trump
    -- discards, so plain ranking applies. A 2+-event sequence that's
    -- monotonically increasing → "want"; monotonically decreasing →
    -- "dontwant"; mixed → ambiguous → fall back to "hint".
    local plain = K.RANK_PLAIN
    local ascending, descending = true, true
    for i = 2, #signals do
        local prev, cur = plain[signals[i - 1]] or 0, plain[signals[i]] or 0
        if cur <= prev then ascending = false end
        if cur >= prev then descending = false end
    end
    if ascending  then return "want" end
    if descending then return "dontwant" end
    return "hint"
end

local function pickLead(legal, contract, seat)
    local myTeam = R.TeamOf(seat)
    local isBidderTeam = (contract.type == K.BID_HOKM
                          and myTeam == R.TeamOf(contract.bidder))
    local isBidder = (seat == contract.bidder)

    -- v0.5.1 C-4: last-trick targeting at lead. On trick 8 there's no
    -- future trick to set up — lead our HIGHEST face-value winner if
    -- we hold a guaranteed boss (HighestUnplayedRank check) in any
    -- safe suit, OR fall through to highest-face-value otherwise.
    -- Sweep pursuit: if my team has won 7/7 tricks so far, also push
    -- aggressively (already-leading suggests we're going for AL_KABOOT).
    local trickNum = #(S.s.tricks or {}) + 1
    if trickNum == 8 then
        -- Sweep pursuit: our team won every prior trick → maximise
        -- our chance of winning this final trick by leading our
        -- highest-rank card (boss most likely; even if not, brute-force
        -- it).
        local myTeamSweepCount = 0
        for _, t in ipairs(S.s.tricks or {}) do
            if R.TeamOf(t.winner) == myTeam then
                myTeamSweepCount = myTeamSweepCount + 1
            end
        end
        local sweepPursuit = (myTeamSweepCount == 7)
        -- First try a boss-lead in a safe suit. v0.5.2 BUG fix:
        -- previously `isSafe = (Sun OR trump)` excluded non-trump
        -- bosses in Hokm — making the boss-scan dead code in the
        -- dominant case. A non-trump boss IS safe in Hokm when
        -- opponents have no trump left to ruff with — verifiable
        -- via S.HighestUnplayedRank(contract.trump) == nil.
        -- v0.5.3 BUG fix: boss-scan was greedy — returned the FIRST
        -- boss in hand-iteration order, not the best. With multiple
        -- bosses on trick 8 (especially when trumpExhausted opens up
        -- ALL non-trump bosses), throwing a 7-of-spades-boss instead
        -- of a Ten-of-clubs-boss costs up to 10 face-value points
        -- PLUS the +10 LAST_TRICK_BONUS goes to whichever card wins
        -- the trick. Collect all qualifying safe bosses, then pick
        -- the best by face value (highestByFaceValue is contract-
        -- aware via C.PointValue).
        if S.HighestUnplayedRank then
            local trumpExhausted = (contract.type == K.BID_HOKM
                                    and contract.trump
                                    and S.HighestUnplayedRank(contract.trump) == nil)
            local safeBosses = {}
            for _, c in ipairs(legal) do
                local r = C.Rank(c)
                local su = C.Suit(c)
                local isBoss = S.HighestUnplayedRank(su) == r
                local isSafe = (contract.type ~= K.BID_HOKM)
                                or C.IsTrump(c, contract)
                                or trumpExhausted
                if isBoss and isSafe then safeBosses[#safeBosses + 1] = c end
            end
            if #safeBosses > 0 then
                return highestByFaceValue(safeBosses, contract)
            end
        end
        -- Else: just lead our highest-rank or highest-face-value
        -- (sweep pursuit ranks tie-break to highest-rank for max
        -- over-trump resistance).
        if sweepPursuit then
            return highestByRank(legal, contract)
        end
        return highestByFaceValue(legal, contract)
    end

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

    -- v0.5.10 Section 8 Tahreeb receiver + v0.5.14 Section 9 N-3
    -- receiver. M3lm+ tier reads BOTH partner's and opponents'
    -- recorded Tahreeb signals:
    --   • Partner positive (want/bargiya) → prefer leading that suit.
    --   • Partner negative (dontwant)     → avoid leading that suit.
    --   • Opp positive    (want/bargiya) → avoid (deny opp tempo).
    --   • Opp negative    (dontwant)     → ignored (low value).
    -- Bargiya (Ace-discard) = strongest single-event invite; "want" =
    -- 2-event ascending. Conflict resolution: if partner-pref-suit is
    -- ALSO in opp-avoid set, drop the partner pref (defending against
    -- opp's signal dominates partner-help). Only honor when the
    -- relevant seat is a bot (signals from humans are noise per the
    -- Fzloky reasoning below).
    -- Sources: decision-trees.md Section 8 (Definite, videos 01,
    -- 02, 09, 10) + Section 9 N-3 (Common, video 10).
    local tahreebPrefSuit = nil
    local tahreebAvoidSet = {}  -- v0.5.14: revives former dead
                                -- `tahreebAvoidSuit` — set is now
                                -- consumed by the conflict-resolution
                                -- step below.
    if Bot.IsM3lm() and Bot._partnerStyle then
        -- Partner-side signals: positive = pref, negative = avoid.
        local p = R.Partner(seat)
        if Bot.IsBotSeat(p) then
            local pStyle = Bot._partnerStyle[p]
            local signals = pStyle and pStyle.tahreebSent
            if signals then
                local best, bestScore = nil, 0
                for _, su in ipairs({ "S", "H", "D", "C" }) do
                    -- Don't bias toward trump (leading trump has its
                    -- own dedicated logic below).
                    if su ~= contract.trump then
                        local cls = tahreebClassify(signals[su])
                        local score = (cls == "bargiya" and 3)
                                   or (cls == "want"    and 2)
                                   or 0
                        if score > bestScore then
                            best, bestScore = su, score
                        end
                        if cls == "dontwant" then
                            tahreebAvoidSet[su] = true
                        end
                    end
                end
                if best then tahreebPrefSuit = best end
            end
        end
        -- v0.5.14 Section 9 N-3 receiver: opp positive signals → avoid.
        -- Opp's "want"/"bargiya" indicates they want their partner to
        -- lead that suit; we deny them tempo by not leading it.
        for s = 1, 4 do
            if R.TeamOf(s) ~= R.TeamOf(seat) and Bot.IsBotSeat(s) then
                local oStyle = Bot._partnerStyle[s]
                local osignals = oStyle and oStyle.tahreebSent
                if osignals then
                    for _, su in ipairs({ "S", "H", "D", "C" }) do
                        if su ~= contract.trump then
                            local cls = tahreebClassify(osignals[su])
                            if cls == "bargiya" or cls == "want" then
                                tahreebAvoidSet[su] = true
                            end
                        end
                    end
                end
            end
        end
        -- Conflict resolution: if partner pref-suit is in opp-avoid
        -- set, drop the pref. Denying opp dominates helping partner
        -- when both signals point at the same suit (rare).
        if tahreebPrefSuit and tahreebAvoidSet[tahreebPrefSuit] then
            tahreebPrefSuit = nil
        end
    end
    if tahreebPrefSuit then
        -- Lead our LOWEST card in the partner-preferred suit. Partner
        -- has the high cards there (or wants to receive the suit);
        -- we lead low so partner's tops win the trick.
        local fromPref = {}
        for _, c in ipairs(legal) do
            if C.Suit(c) == tahreebPrefSuit
               and not C.IsTrump(c, contract) then
                fromPref[#fromPref + 1] = c
            end
        end
        if #fromPref > 0 then
            return lowestByRank(fromPref, contract)
        end
    end

    -- Fzloky (signal-aware): if our partner has shown a "lead this
    -- suit" signal via a HIGH first-discard (A/T/K), prefer leading
    -- that suit. If their first-discard was LOW (7/8), avoid that
    -- suit. Operates on top of the Advanced lead heuristics: we
    -- pick a suit, then fall through to the existing low-from-
    -- longest logic to choose the actual card.
    local fzlokyPrefSuit, fzlokyAvoidSuit = nil, nil
    -- Audit Tier 3 (H-12): Fzloky is a BOT-vs-BOT convention signal.
    -- A bot's first off-suit discard is a deliberate suit-preference
    -- communication; a HUMAN's first off-suit discard is just whatever
    -- card they shed (often a high card to dump weakness, often random).
    -- Reading a human's discard as a "lead this suit" signal misdirects
    -- the bot's lead priority for the rest of the round. Only honour
    -- the signal when the partner is also a bot.
    if Bot.IsFzloky() and Bot._memory then
        local p = R.Partner(seat)
        if Bot.IsBotSeat(p) then
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
        -- Audit Tier 4 (B-96): Ace-exhaustion window. After trick 3,
        -- if all 3 NON-trump Aces have been observed played (anyone's
        -- played pile contains the Ace, OR the Ace is in our own
        -- legal cards still), opponents have no Ace threats left.
        -- Continued trump-pull only spends our trump for 7/8/Q
        -- captures — wasteful. Switch to cashing side-suit length
        -- (we hold mid-cards K/Q/J in non-trump that are now bosses).
        -- Advanced+, requires C-1 memory population.
        if Bot.IsAdvanced() and S.s.tricks and #S.s.tricks >= 3
           and contract.trump and Bot._memory then
            local sideAcesLeft = 0
            for _, su in ipairs({ "S", "H", "D", "C" }) do
                if su ~= contract.trump then
                    -- Check if Ace of this suit has been played OR is in our hand.
                    local aceCard = "A" .. su
                    local seen = false
                    for s2 = 1, 4 do
                        local m = Bot._memory[s2]
                        if m and m.played[aceCard] then seen = true; break end
                    end
                    if not seen then
                        for _, c in ipairs(legal) do
                            if c == aceCard then seen = true; break end
                        end
                    end
                    if not seen then sideAcesLeft = sideAcesLeft + 1 end
                end
            end
            if sideAcesLeft == 0 then
                -- Lead our highest non-trump (unblocked tricks).
                local bestSide, bestSideR = nil, -1
                for _, c in ipairs(legal) do
                    if not C.IsTrump(c, contract) then
                        local r = C.TrickRank(c, contract)
                        if r > bestSideR then bestSide, bestSideR = c, r end
                    end
                end
                if bestSide then return bestSide end
            end
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
        -- Audit Tier 4 (B-98): J+9 trump-lock detection. Once BOTH
        -- the Jack and 9 of trump have been observed played (or are
        -- in our own hand still), opponent trump strength is nearly
        -- spent — pulling more trump only burns our high trump for
        -- 7/8 captures. Switch to cashing side-suit Aces while we
        -- still have trump in reserve to ruff returns. Advanced+ since
        -- it relies on Bot._memory.played tracking which is itself
        -- conditioned on memory population (post-Tier-1 C-1 fix).
        if Bot.IsAdvanced() and S.HighestUnplayedRank
           and S.HighestUnplayedRank(contract.trump) ~= "J" then
            local trumpJSeen, trump9Seen = false, false
            -- Build the union of "played" and "in our hand" — both
            -- count as out-of-pool for opponent trump strength.
            local out = {}
            if Bot._memory then
                for s2 = 1, 4 do
                    local m = Bot._memory[s2]
                    if m then
                        for card in pairs(m.played) do out[card] = true end
                    end
                end
            end
            for _, c in ipairs(legal) do out[c] = true end
            for card in pairs(out) do
                if C.Suit(card) == contract.trump then
                    if C.Rank(card) == "J" then trumpJSeen = true
                    elseif C.Rank(card) == "9" then trump9Seen = true end
                end
            end
            if trumpJSeen and trump9Seen then
                -- Both gone from pool. Cash a side-suit Ace if we
                -- have one; otherwise fall through to highestTrump.
                for _, c in ipairs(legal) do
                    if C.Rank(c) == "A" and not C.IsTrump(c, contract) then
                        return c
                    end
                end
            end
        end
        -- v0.5.1 H-6: preserve A-of-trump for late tricks. Saudi pros
        -- spend J/9 of trump on trump-pull and reserve A-of-trump for
        -- the LAST few tricks where its 11 face value + LAST_TRICK_BONUS
        -- becomes 21 effective points. Without this guard, after J+9
        -- are out, the bot's `highestTrump` returns A-of-trump and
        -- spends it on routine pull. Filter out A-of-trump from the
        -- candidate set when (a) we're in early tricks (#tricks < 5)
        -- AND (b) we have non-Ace trump available. Falls through to
        -- raw highestTrump if A is our only trump or trick 5+.
        local trumpCandidates = {}
        local hasNonAceTrump = false
        for _, c in ipairs(legal) do
            if C.IsTrump(c, contract) and C.Rank(c) ~= "A" then
                hasNonAceTrump = true
                break
            end
        end
        local earlyTricks = (#(S.s.tricks or {}) < 5)
        for _, c in ipairs(legal) do
            if C.IsTrump(c, contract) then
                if not (earlyTricks and C.Rank(c) == "A" and hasNonAceTrump) then
                    trumpCandidates[#trumpCandidates + 1] = c
                end
            end
        end
        local t
        if #trumpCandidates > 0 then
            t = highestByRank(trumpCandidates, contract)
        else
            t = highestTrump(legal, contract)
        end
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
    --
    -- Audit Tier 2: M3lm-gated tempo read. When the BIDDER has been
    -- observed leading trump aggressively in early tricks across
    -- prior rounds (styleTrumpTempo == 1), they will likely pull
    -- trump fast in this round too. As a defender we must NOT spend
    -- our high trump in a casual cross-ruff — save it to over-ruff
    -- their trump leads. We flag this for the trump fallback at
    -- step 5 (lowest legal trump) and bias side-suit length leads
    -- away from suits where we hold a singleton high card that the
    -- aggressive bidder would happily capture with their pulled
    -- trump on trick 2-3.
    local saveHighTrump = false
    if Bot.IsM3lm() and contract.type == K.BID_HOKM
       and not isBidderTeam then
        local bidderTempo = styleTrumpTempo(contract.bidder)
        local partnerTempo = styleTrumpTempo(R.Partner(contract.bidder))
        if bidderTempo == 1 or partnerTempo == 1 then
            saveHighTrump = true
        end
    end

    -- Audit Tier 4 (B-82): trump-drought tell. After 3 tricks, if the
    -- bidder has LED at least once and NEVER led trump, the bidder is
    -- trump-poor (they're out of trump or never had it). As a defender
    -- we should aggressively cash high-point side-suit cards before
    -- the bidder finds something to ruff with. M3lm-gated and Hokm-only.
    local bidderTrumpDrought = false
    if Bot.IsM3lm() and contract.type == K.BID_HOKM and not isBidderTeam
       and S.s.tricks and #S.s.tricks >= 3 and contract.bidder
       and contract.trump then
        local bidderLeadCount, bidderTrumpLeadCount = 0, 0
        for _, t in ipairs(S.s.tricks) do
            if t.plays and t.plays[1] and t.plays[1].seat == contract.bidder then
                bidderLeadCount = bidderLeadCount + 1
                if C.Suit(t.plays[1].card) == contract.trump then
                    bidderTrumpLeadCount = bidderTrumpLeadCount + 1
                end
            end
        end
        if bidderLeadCount >= 1 and bidderTrumpLeadCount == 0 then
            bidderTrumpDrought = true
        end
    end

    local nonTrumps = {}
    local suitCount = { S = 0, H = 0, D = 0, C = 0 }
    for _, c in ipairs(legal) do
        if not C.IsTrump(c, contract) then
            nonTrumps[#nonTrumps + 1] = c
            suitCount[C.Suit(c)] = suitCount[C.Suit(c)] + 1
        end
    end

    -- Audit Tier 4 (B-82): on trump-drought, lead our HIGHEST point
    -- non-trump (T or A) — bidder can't ruff so the points fall to
    -- our team or partner. Beats the standard "low from longest"
    -- defender priority. Skip if no point-card non-trump available.
    if bidderTrumpDrought then
        local pointCard = nil
        local pointVal  = -1
        for _, c in ipairs(nonTrumps) do
            local r = C.Rank(c)
            local v = (r == "A" and 11) or (r == "T" and 10) or 0
            if v > pointVal then pointCard, pointVal = c, v end
        end
        if pointCard and pointVal >= 10 then
            return pointCard
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

    -- Audit Tier 4 (B-77): single-opponent void exploit. If we hold
    -- the BOSS (highest unplayed) of a non-trump suit AND exactly one
    -- opponent is void in it, the opponent's defense is reduced to
    -- one possible over-trumper. In Hokm-only this is enough leverage
    -- to lead the high card — partner sits between the void opp and
    -- the other opp in seat order roughly half the time, the boss
    -- wins outright the other half. Sun is already covered by the
    -- general Sun-led-Ace heuristic. Advanced+ since it relies on
    -- HighestUnplayedRank tracking.
    if Bot.IsAdvanced() and contract.type == K.BID_HOKM
       and S.HighestUnplayedRank then
        for _, c in ipairs(nonTrumps) do
            local su = C.Suit(c)
            if su ~= contract.trump
               and S.HighestUnplayedRank(su) == C.Rank(c)
               and anyOpponentVoidIn(seat, su)
               and not opponentsVoidInAll(seat, su) then
                return c
            end
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

    -- v0.5 H-7: Sun shortest-suit lead. Saudi pro convention is to
    -- lead from the shortest non-trump suit in Sun (forcing opponents
    -- to play their boss in that suit early; once spent, our lower
    -- cards in that suit become winners). Bot previously fell through
    -- to "low from longest" for both Hokm defenders AND Sun bidders —
    -- the longest-suit lead is right for Hokm defenders (preserve
    -- high cards for capture, give partner room) but wrong for Sun
    -- (Sun has no trump shield; long-suit cards get over-trumped).
    if contract.type == K.BID_SUN then
        local count = { S = 0, H = 0, D = 0, C = 0 }
        for _, c in ipairs(legal) do
            count[C.Suit(c)] = count[C.Suit(c)] + 1
        end
        local shortestSuit, shortestN = nil, 99
        for _, suit in ipairs({ "S", "H", "D", "C" }) do
            local n = count[suit] or 0
            if n > 0 and n < shortestN then shortestSuit, shortestN = suit, n end
        end
        if shortestSuit then
            local fromShortest = {}
            for _, c in ipairs(legal) do
                if C.Suit(c) == shortestSuit then
                    fromShortest[#fromShortest + 1] = c
                end
            end
            if #fromShortest > 0 then
                return lowestByRank(fromShortest, contract)
            end
        end
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

    -- 5: no non-trump — lowest trump. When saveHighTrump is set
    -- (M3lm: aggressive opposing bidder), prefer the LOWEST trump
    -- that isn't J/9 — we want to burn 7/8/Q/K first and hold the
    -- top trump for over-ruff capture later. If only J/9 are legal,
    -- fall through to the regular lowest pick.
    if saveHighTrump then
        local lowTrump = {}
        for _, c in ipairs(legal) do
            local r = C.Rank(c)
            if r ~= "J" and r ~= "9" then
                lowTrump[#lowTrump + 1] = c
            end
        end
        if #lowTrump > 0 then
            return lowestByRank(lowTrump, contract)
        end
    end
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

    -- v0.5.1 H-5: AKA receiver convention. When our partner just
    -- announced AKA (إكَهْ) on the led suit AND is currently winning the
    -- trick, they're saying "I hold the boss of this suit, partner —
    -- don't over-trump it." Without this gate the bot's forced-trump
    -- logic in Hokm would still ruff partner's lead. Suppress the ruff
    -- by returning a low non-trump discard if any non-trump is legal.
    -- Falls through to normal logic when no non-trump exists (legality
    -- preserved) or when AKA isn't applicable.
    --
    -- v0.5.16 S6-6 extension (Definite, video 18): IMPLICIT AKA. When
    -- partner leads a bare Ace of a non-trump suit AND no explicit
    -- MSG_AKA was broadcast (S.s.akaCalled is nil), the receiver
    -- still applies AKA-receiver semantics. Saudi convention: leading
    -- bare A in non-trump = implicit AKA call. The Ace is the highest
    -- unplayed rank in its suit at trick 1 (no prior plays in that
    -- suit), so partner is trivially "winning" the trick. Detection:
    -- partner's most-recent play in this trick is rank=A, suit !=
    -- trump, partner is currently winning, AKA wasn't explicitly
    -- broadcast. Same suppress-ruff outcome as explicit AKA.
    local explicitAKA = S.s.akaCalled
                        and S.s.akaCalled.seat == R.Partner(seat)
                        and S.s.akaCalled.suit == trick.leadSuit
    local implicitAKA = false
    -- v0.5.16 S6-6: implicit AKA fires when partner LED the bare Ace
    -- (not when partner FOLLOWED with an Ace). Per the doc, "leading
    -- bare A in non-trump = implicit AKA". A trick's lead is the
    -- FIRST play (trick.plays[1]). Partner-followed-Ace is just a
    -- normal must-follow play, not an AKA signal.
    if not explicitAKA and contract.type == K.BID_HOKM
       and contract.trump and trick.leadSuit
       and trick.leadSuit ~= contract.trump
       and partnerWinning
       and trick.plays and trick.plays[1] then
        local lead = trick.plays[1]
        if lead.seat == R.Partner(seat)
           and C.Rank(lead.card) == "A"
           and C.Suit(lead.card) == trick.leadSuit then
            implicitAKA = true
        end
    end
    if Bot.IsAdvanced() and contract.type == K.BID_HOKM and contract.trump
       and trick.leadSuit and partnerWinning
       and (explicitAKA or implicitAKA) then
        local discards = {}
        for _, c in ipairs(legal) do
            if not C.IsTrump(c, contract) then
                discards[#discards + 1] = c
            end
        end
        if #discards > 0 then
            return lowestByRank(discards, contract)
        end
    end

    if partnerWinning then
        -- Smother: dumping our Ace/10 of lead suit onto partner's
        -- trick-pile feeds points to our team. Gate:
        --   (a) we have a SECOND A or T in that suit (so we keep one
        --       for defensive depth), OR
        --   (b) we're past the first 3 tricks, OR
        --   (c) [ANY MODE] we're 4th to act — the trick is going on
        --       partner's pile no matter what, free points.
        -- 13th-bot-audit fix (Codex+pickFollow agent): smother now
        -- fires on Sun + Ashkal too. The original Hokm-only gate
        -- missed the case where partner sweeps in Sun — A/T are
        -- worth 11/10 points there too. Trump-led smother stays
        -- skipped under Hokm only (trump tricks don't reward feed).
        local feedSafe = trick.leadSuit and (
            contract.type ~= K.BID_HOKM
            or trick.leadSuit ~= contract.trump
        )
        if feedSafe then
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
                -- v0.5.11 Section 4 rule 7 Takbeer fix (Definite, videos
                -- 21+22+23): when partner is certain-winning, donate the
                -- HIGHEST card (Takbeer / التكبير), not the lowest. Was
                -- ascending sort + [1] = LOWEST — the literal opposite of
                -- the Saudi rule. Single-char flip: < → >. Maximizes
                -- trick-point capture when partner takes the trick (A=11
                -- vs T=10 raw differential per occurrence).
                table.sort(highInSuit, function(a, b)
                    return C.TrickRank(a, contract) > C.TrickRank(b, contract)
                end)
                if highInSuit[1] then return highInSuit[1] end
            end
        end

        -- v0.5.10 Section 8 Tahreeb sender. We're discarding (or about
        -- to) while partner is winning — this discard IS a Tahreeb
        -- signal whether we mean it to be or not. If we're VOID in
        -- the led suit (so we have free choice of which suit to
        -- discard from) AND M3lm+ (the convention is bot-vs-bot
        -- coordination), encode an intentional signal:
        --
        --   T-1 Bargiya (Definite, videos 01,03): if we hold A of a
        --     side suit X with at least 1 cover (≥2 cards in X), and
        --     it's Sun, discard the A as Bargiya — "I have the slam
        --     in X, lead it back".
        --   T-4 Dump-ordering (Definite, video 01): from a 2-card
        --     non-led non-trump suit, dump the LARGER first. Larger-
        --     first reads as unambiguous refusal; smaller-first
        --     would be a false bottom-up positive signal that
        --     misleads partner.
        --
        -- Both rules only fire when:
        --   • partner is a bot (signals to humans = noise);
        --   • we're void in led suit (legal must contain non-led
        --     cards — we have a free choice of suit);
        --   • we're not 4th to act on the led suit (the smother
        --     branch above already handled the high-feed case).
        --
        -- When neither rule fires, fall through to lowestByRank.
        -- Sources: decision-trees.md Section 8 (Definite, videos 01, 03).
        local voidInLed = trick.leadSuit and (function()
            for _, c in ipairs(legal) do
                if C.Suit(c) == trick.leadSuit then return false end
            end
            return true
        end)()
        if Bot.IsM3lm() and voidInLed
           and Bot.IsBotSeat(R.Partner(seat)) then
            -- Group legal cards by suit (excluding trump in Hokm —
            -- trump discards have their own value as ruff fodder).
            local bySuit = { S = {}, H = {}, D = {}, C = {} }
            for _, c in ipairs(legal) do
                local su = C.Suit(c)
                if not (contract.type == K.BID_HOKM
                        and su == contract.trump) then
                    bySuit[su][#bySuit[su] + 1] = c
                end
            end

            -- T-1 Bargiya (Sun only): A-of-side-suit with cover.
            if contract.type == K.BID_SUN then
                for _, su in ipairs({ "S", "H", "D", "C" }) do
                    local cards = bySuit[su]
                    -- Need ≥2 of the suit (Ace + cover) AND Ace present.
                    if #cards >= 2 then
                        for _, c in ipairs(cards) do
                            if C.Rank(c) == "A" then
                                return c   -- Bargiya
                            end
                        end
                    end
                end
            end

            -- T-4 Dump-ordering: from a 2-card suit, dump LARGER first.
            -- The encoding only "works" when partner can observe BOTH
            -- discards in this suit — but we still emit the larger
            -- first unconditionally because (a) larger-first = clear
            -- "don't want" signal even if partner sees only one event,
            -- and (b) it never falsely signals "want".
            --
            -- v0.5.11 T-4 over-fire gate (Wave-2 audit finding): the
            -- Saudi rule's premise is "a 2-card suit you don't WANT" —
            -- low-rank doubletons (J+9, 8+7, Q+J style). Without a rank
            -- floor, T-4 was firing on K+J / A+x doubletons too,
            -- shedding valuable cards in service of a Tahreeb signal
            -- that's only worth ~1 trick of partner-coord. Cap the
            -- larger card at Q — if the doubleton's higher card is K,
            -- T, or A, fall through to lowestByRank (preserves the
            -- valuable card; partner still gets a discard signal,
            -- just not the over-eager Tahreeb encoding).
            for _, su in ipairs({ "S", "H", "D", "C" }) do
                local cards = bySuit[su]
                if #cards == 2 then
                    -- Find the larger by trick rank (in non-trump,
                    -- TrickRank uses RANK_PLAIN: 7<8<9<J<Q<K<T<A).
                    local lo, hi = cards[1], cards[2]
                    if C.TrickRank(lo, contract) > C.TrickRank(hi, contract) then
                        lo, hi = hi, lo
                    end
                    local hiRank = C.Rank(hi)
                    if hiRank ~= "K" and hiRank ~= "T" and hiRank ~= "A" then
                        return hi
                    end
                    -- High-value doubleton: skip Tahreeb encoding,
                    -- preserve the card. Continue searching other suits.
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
                -- 13th-bot-audit fix (Codex+Gemini+pickFollow agent):
                -- in Sun, an Ace of the led suit is unbeatable AND a
                -- point card (11). Don't duck it. Same for the T (10)
                -- of led suit. (Position-2-low only makes sense when
                -- the card we'd take with is a low-point K/Q/J —
                -- saving it for partner doesn't apply to A/T.)
                --
                -- Audit C-3: this shortcut MUST be Sun-only. In Hokm,
                -- a non-trump Ace is NOT a sure stopper — an opponent
                -- void in that suit can over-ruff it, sacrificing the
                -- Ace for nothing. Restricting to Sun also makes
                -- "leadSuit == cardSuit" universally true (Sun has no
                -- trump to ruff with), so a side-suit Ace is genuinely
                -- unbeatable in that contract.
                if not sureStopper and trick.leadSuit
                   and contract.type == K.BID_SUN then
                    for _, c in ipairs(winners) do
                        local r = C.Rank(c)
                        if C.Suit(c) == trick.leadSuit
                           and (r == "A" or r == "T") then
                            sureStopper = c
                            break
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
                -- 13th-bot-audit fix: EXCEPT when the only winners are
                -- trump (forced ruff) — then ruff with the LOWEST trump
                -- to save the J / 9 / A for forcing leads. Wasting the
                -- J of trump on a 7-of-side-suit ruff is a classic
                -- give-back; bot must conserve high trump.
                if contract.type == K.BID_HOKM and contract.trump then
                    local trumpWinners = {}
                    for _, c in ipairs(winners) do
                        if C.IsTrump(c, contract) then
                            trumpWinners[#trumpWinners + 1] = c
                        end
                    end
                    if #trumpWinners > 0 and #trumpWinners == #winners then
                        return lowestByRank(trumpWinners, contract)
                    end
                end
                return highestByRank(winners, contract)
            end
        end
        -- v0.5.1 C-4: last-trick targeting. On trick 8 the cheapest
        -- winner is wrong — there's no future trick to save the
        -- higher card for, and LAST_TRICK_BONUS (+10) plus face-value
        -- captures more total points. Default / pos 4 / no advanced
        -- behavior elsewhere remains "cheapest winner".
        local trickNum = #(S.s.tricks or {}) + 1
        if trickNum == 8 then
            return highestByFaceValue(winners, contract)
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
    -- v0.5.1 H-4: Belote (K+Q of trump) preservation. If we still hold
    -- BOTH K and Q of trump and we're in early tricks (#tricks < 4),
    -- avoid discarding either — they pair for +20 raw post-multiplier
    -- when played from the same hand. Filter the discard candidates;
    -- if filtering would leave us with no legal cards (only K and Q
    -- of trump are legal), fall through to lowestByRank — legality
    -- always wins.
    -- v0.5.2 WARNING fix: pass `hand` not `legal` to detect Belote
    -- across the FULL hand, not just the currently-legal subset. K
    -- and Q of trump may not be in `legal` when must-follow forces
    -- non-trump play, but they're still in our hand. Filter still
    -- applies to `legal` below — legality preserved.
    local completed = #(S.s.tricks or {})
    if completed < 4 and holdsBeloteThusFar(hand, contract) then
        local trump = contract.trump
        local withoutBelote = {}
        for _, c in ipairs(legal) do
            local r = C.Rank(c)
            if not (C.Suit(c) == trump and (r == "K" or r == "Q")) then
                withoutBelote[#withoutBelote + 1] = c
            end
        end
        if #withoutBelote > 0 then
            return lowestByRank(withoutBelote, contract)
        end
    end
    -- v0.5.11 Section 4 rule 1 (Definite, videos 05+09): Sun
    -- losing-side off-suit follow → dump HIGHEST. Saudi
    -- inverse-laddering signals partner "we're done in this suit".
    -- Without this, the bot dumps absolute lowest in-suit when
    -- forced to follow a suit it can't win — what the source
    -- video calls "the biggest mistake in Baloot" (per glossary.md
    -- Tahreeb section, video #09 source). Hokm trump-follow stays
    -- LOWEST per Section 4 rule 2 (separate convention). Hokm
    -- non-trump losing-side stays LOWEST until doc clarifies.
    -- Sources: decision-trees.md Section 4 rule 1 (Definite, 05+09).
    if contract.type == K.BID_SUN and trick.leadSuit then
        local follow = {}
        for _, c in ipairs(legal) do
            if C.Suit(c) == trick.leadSuit then
                follow[#follow + 1] = c
            end
        end
        if #follow > 0 then
            return highestByRank(follow, contract)
        end
    end

    -- v0.5.14 Section 9 N-1 sender (Tanfeer / تنفير).
    -- When opp is winning AND we're VOID in led (so we're discarding
    -- from a non-led suit), the discarded SUIT itself signals to
    -- partner "I want this returned." Inverse of Tahreeb (which uses
    -- direction-encoding while partner wins); Tanfeer uses suit-
    -- only positive signaling while opp wins. Pick the LOWEST card
    -- of a "wanted suit" — a non-trump suit where we hold a high
    -- card (A or T) and at least one low to spare (so we don't burn
    -- the high card on a losing trick).
    --
    -- N-2 default semantics (decision-trees.md Section 9 N-2):
    -- "uncertain winner → default to Tahreeb." The pickFollow code
    -- branches on `partnerWinning` (computed via R.CurrentTrickWinner)
    -- — it's a best-estimate determination, not certainty.
    -- The Tahreeb sender block above is the partnerWinning path; the
    -- Tanfeer sender here is the opp-winning path. Ambiguous-winner
    -- cases naturally fall to lowestByRank (no encoding) — closer
    -- to "Tahreeb default" since lowest = positive Tahreeb signal.
    -- Sufficient for the current rule set; revisit if a future video
    -- demands explicit uncertain-handling.
    --
    -- Tier-gated to M3lm+ (partner-coordination convention) and
    -- bot-partner-only (signals to humans = noise per Fzloky logic).
    -- Sources: decision-trees.md Section 9 N-1, N-2 (Common, video 03).
    if Bot.IsM3lm() and Bot.IsBotSeat(R.Partner(seat))
       and trick.leadSuit then
        local voidInLed = true
        for _, c in ipairs(legal) do
            if C.Suit(c) == trick.leadSuit then
                voidInLed = false
                break
            end
        end
        if voidInLed then
            -- Find a wanted suit + a low card in it. Prefer the first
            -- non-trump suit where we have BOTH a high card (A or T)
            -- AND at least one low (non-A non-T) to spare.
            for _, su in ipairs({ "S", "H", "D", "C" }) do
                local skipTrump = (contract.type == K.BID_HOKM
                                   and su == contract.trump)
                if not skipTrump then
                    local hasHigh = false
                    local lows = {}
                    for _, c in ipairs(legal) do
                        if C.Suit(c) == su then
                            local r = C.Rank(c)
                            if r == "A" or r == "T" then
                                hasHigh = true
                            else
                                lows[#lows + 1] = c
                            end
                        end
                    end
                    if hasHigh and #lows >= 1 then
                        -- Discard lowest non-A non-T → suit signal
                        -- without burning the high card.
                        return lowestByRank(lows, contract)
                    end
                end
            end
            -- No wanted-suit-with-spare-low matched. Fall through to
            -- lowestByRank.
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
    -- Audit Tier 3 (B-33 / B-60): AKA is a bot-side coordination
    -- convention. The signal coordinates with bot partners who read
    -- the per-round `akaSent` flag and suppress over-trumping the
    -- announced suit. Human partners typically don't recognize the
    -- AKA banner as a "don't ruff this suit" instruction — at best
    -- the signal is wasted, at worst it leaks information to
    -- opponents (who see the banner too) and gives them a free read
    -- on which suit we hold the boss in. Suppress AKA when the
    -- partner is human.
    if not Bot.IsBotSeat(R.Partner(seat)) then return nil end
    local r = C.Rank(leadCard)
    local su = C.Suit(leadCard)
    -- AKA is non-trump only.
    if su == trump then return nil end
    -- v0.5.16 S6-10(c) (Definite, video 18): AKA-sender-side
    -- precondition (c) — `card.rank != "A"`. Leading a bare Ace of a
    -- non-trump suit is the IMPLICIT AKA case (S6-6); explicitly
    -- announcing AKA on an Ace is redundant. Receivers detect
    -- bare-Ace lead via the H-5 implicit-AKA branch (extended this
    -- release) — no MSG_AKA needed.
    if r == "A" then return nil end
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
    -- v0.5 C-1: Saudi Master ISMCTS delegation. Previously Bot.PickPlay
    -- bypassed BotMaster.PickPlay entirely — only Net.lua's MaybeRunBot
    -- explicit branch reached the sampler. Direct callers (AFK timeout
    -- recovery, test harnesses, error paths) all ran heuristics even
    -- with saudiMasterBots=true. Empirical: M3lm and Saudi Master
    -- produced byte-identical metrics in 100-round tests. This delegation
    -- routes every call through ISMCTS when active, gated by Bot._inRollout
    -- so internal rolloutValue doesn't recursively re-enter ISMCTS.
    if not Bot._inRollout then
        local BM = WHEREDNGN and WHEREDNGN.BotMaster
        if BM and BM.IsActive and BM.IsActive() and BM.PickPlay then
            local masterCard = BM.PickPlay(seat)
            if masterCard then return masterCard end
        end
    end

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

    -- v0.5.9 Section 2 patch E-1: Sun Bel-100 legality gate.
    -- Saudi rule: in Sun contracts, only the team at <100 cumulative
    -- score may Bel. Hokm has no such gate. R.CanBel is the
    -- authoritative predicate (also enforced wire-side in Net.lua,
    -- so a human player can't bypass via the wire).
    -- Sources: decision-trees.md Section 2 (Definite, video 11).
    if R.CanBel and not R.CanBel(R.TeamOf(seat), contract, S.s.cumulative) then
        return false, false
    end

    local strength = sunStrength(hand)
    if contract.type == K.BID_HOKM and contract.trump then
        -- Trump cards are an extra defensive resource. Audit C-4 fix:
        -- previous 0.5x discount was inconsistent with the 1.0x weight
        -- used by escalationStrength (PickTriple/Four/Gahwa). A Hokm
        -- defender with J+9+A of trump (~42 trump points) was scored
        -- at 21 here, never reaching BOT_BEL_TH=70 — legitimate Bels
        -- structurally blocked. Aligned to the same scale escalation
        -- already uses.
        local trumpStr = suitStrengthAsTrump(hand, contract.trump)
        strength = strength + trumpStr

        -- v0.5.1 C-3b: defender-aware strength additions. The 200-agent
        -- audit identified missed Bels when defender had ruff potential
        -- (void suits) or multiple side-suit Aces. Empirical: at TH=60
        -- the Bel formula precision was still 45% — these additions
        -- improve discriminator power.
        --   • Void in non-trump suit: +5 (ruff capacity each round)
        --   • Each side-suit Ace beyond the first: +8 (sustained
        --     trick-winning power outside the trump axis)
        local voidCount, sideAces = 0, 0
        local suitCount = { S = 0, H = 0, D = 0, C = 0 }
        for _, c in ipairs(hand) do
            suitCount[C.Suit(c)] = suitCount[C.Suit(c)] + 1
            if C.Rank(c) == "A" and C.Suit(c) ~= contract.trump then
                sideAces = sideAces + 1
            end
        end
        for _, suit in ipairs({ "S", "H", "D", "C" }) do
            if suit ~= contract.trump and suitCount[suit] == 0 then
                voidCount = voidCount + 1
            end
        end
        strength = strength + voidCount * 5
        if sideAces >= 2 then
            strength = strength + (sideAces - 1) * 8
        end
    end
    if contract.type == K.BID_SUN then
        strength = strength + 10   -- bias: Sun is harder for the bidder
    end
    -- Advanced: partner's bid is a strong signal of combined-team
    -- strength; score urgency adjusts threshold for desperation/safety.
    strength = strength + partnerBidBonus(seat, contract)
                       + partnerEscalatedBonus(seat, contract)
    -- v0.5 H-8: defender Bel uses context="defend" so the near-clinch
    -- branch flips to aggressive (+5) instead of conservative (-8).
    local th = K.BOT_BEL_TH - (scoreUrgency(R.TeamOf(seat), "defend") + matchPointUrgency(R.TeamOf(seat)))

    -- Audit Tier 4 (B-61): defensive-Sun detection. If the Sun bidder
    -- has failed Sun >=2 times this game, they're a known defensive-Sun
    -- caller (bidding marginal Sun to block opponent Hokm rather than
    -- for genuine score). Raise our Bel threshold by 8 — defensive Sun
    -- has low base score, so the 2x Bel reward is small if we win the
    -- Bel and large if we lose. The expected-value math favors letting
    -- a low Sun play out and capturing the small score directly without
    -- the Bel risk amplification. M3lm-gated.
    if Bot.IsM3lm() and contract.type == K.BID_SUN and contract.bidder
       and Bot._partnerStyle then
        local m = Bot._partnerStyle[contract.bidder]
        if m and (m.sunFail or 0) >= 2 then
            th = th + 8
        end
    end

    -- v0.5.2 WARNING fix: cap the threshold floor like PickFour does.
    -- Combined drops from scoreUrgency("defend") + matchPointUrgency
    -- can push th down by 15+; with C-3b adding up to +31 to strength
    -- (3 voids × 5 + 3 Aces × 8) and BEL_JITTER ±10, weak-trump hands
    -- could fire false-Bels. Floor at BOT_BEL_TH - 16 to match
    -- PickFour's defensive cap.
    if th < K.BOT_BEL_TH - 16 then th = K.BOT_BEL_TH - 16 end

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
    -- Audit Tier 2: M3lm-gated style read. A defender that has Beled
    -- ≥2 times this game is a habitual Beler — their current Bel is
    -- less informative about hand strength, and our Triple response
    -- can be more aggressive. Drop the Triple threshold by 8 against
    -- a known habitual Beler. Style metric returns nil with <2 Bels
    -- in the ledger; threshold change only fires when there's enough
    -- data to be meaningful.
    if Bot.IsM3lm() then
        local myTeam = R.TeamOf(seat)
        for opp = 1, 4 do
            if R.TeamOf(opp) ~= myTeam then
                if styleBelTendency(opp) == 1 then
                    th = th - 8
                    break
                end
            end
        end
    end
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
    -- v0.5 H-8: defender Four uses context="defend" — same logic as Bel.
    local th = K.BOT_FOUR_TH - (scoreUrgency(R.TeamOf(seat), "defend") + matchPointUrgency(R.TeamOf(seat)))
    -- 50-agent audit fix (B-83 wiring): the gahwaFailed counter on
    -- the bidder's _partnerStyle was incremented by Bot.OnRoundEnd
    -- but never read by any picker — a dead-counter feature gap. A
    -- bidder who has called Gahwa and failed is a reckless caller;
    -- defenders should be more willing to Four against them. Tiered
    -- threshold drop: -5 on first fail (one data point, modest), -8
    -- on 2+ fails (matches PickTriple's styleBelTendency magnitude).
    -- M3lm-gated since the counter is a style-ledger derivative.
    if Bot.IsM3lm() and contract.bidder and Bot._partnerStyle then
        local m = Bot._partnerStyle[contract.bidder]
        local fails = m and (m.gahwaFailed or 0) or 0
        if fails >= 2 then
            th = th - 8
        elseif fails >= 1 then
            th = th - 5
        end
        -- v0.5.1 H-9: wire `triples` counter (was dead). Habitual
        -- Triple-bidder = aggressive caller; defenders should be
        -- slightly more willing to Four against them. Cap combined
        -- threshold drop with the gahwaFailed branch above so we
        -- don't collapse the threshold below 50% of base.
        local triples = m and (m.triples or 0) or 0
        if triples >= 2 then th = th - 5 end
    end
    -- v0.5.3 BUG fix: lift the floor cap OUT of the IsM3lm() block.
    -- Even non-M3lm tiers (Basic/Advanced/Fzloky/Master) can drop
    -- `th` below safe levels via scoreUrgency("defend") and
    -- matchPointUrgency above. The floor is a defensive cap on the
    -- combined drop; it should apply unconditionally (matching
    -- PickDouble's v0.5.2 unconditional floor at line ~1850).
    if th < K.BOT_FOUR_TH - 16 then th = K.BOT_FOUR_TH - 16 end
    return escalateDecision(strength, th)
end

function Bot.PickGahwa(seat)
    -- v0.2.0: Gahwa is the BIDDER's terminal — match-win or match-loss.
    -- Bot only fires this on a near-certain hand: the entire match
    -- hangs on the next 8 tricks.
    --
    -- Audit fix #9: align return arity with PickTriple/PickFour, which
    -- both return (yes, wantOpen). Gahwa is terminal so wantOpen is
    -- moot, but matching the signature avoids any caller pattern-match
    -- destructure dropping a nil into the "wantOpen" slot.
    local hand = S.s.hostHands and S.s.hostHands[seat]
    local contract = S.s.contract
    if not hand or not contract then return false, false end
    local strength = escalationStrength(seat, hand, contract)
    local th = K.BOT_GAHWA_TH - (scoreUrgency(R.TeamOf(seat)) + matchPointUrgency(R.TeamOf(seat)))
    local yes = strength >= jitter(th, BEL_JITTER)
    return yes, false
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
    -- (it would have been our trick-winner anyway). 13th-bot-audit
    -- raised this from +8 to +12 (Codex+Claude consensus): the Ace
    -- is worth ~11 points + tempo control + guaranteed first-trick,
    -- under-weighted at +8.
    local bidSuit = S.s.bidCard and C.Suit(S.s.bidCard)
    if bidSuit then
        for _, c in ipairs(hand) do
            if C.Rank(c) == "A" and C.Suit(c) == bidSuit then
                strength = strength + 12; break
            end
        end
    end
    -- 13th-bot-audit fix (Codex): factor partner's bid history.
    -- Partner who already passed (Sun option declined) → preempt is
    -- riskier (no fallback if our Sun fails). Partner who bid Sun or
    -- Hokm → side-suit coverage already implied → safer to preempt.
    --
    -- Audit Tier 3: a human PASS may be overcaution (humans pass
    -- marginal hands a bot would have bid). Halving the penalty
    -- prevents over-suppression of preempt after a human pass.
    -- Hokm bonus also halved for human partners since human Hokm bids
    -- have wider variance than bot bids (no J/9 guarantee).
    local partner = R.Partner(seat)
    local pBid = S.s.bids and S.s.bids[partner]
    local pIsBot = Bot.IsBotSeat(partner)
    if pBid == K.BID_PASS then
        strength = strength + (pIsBot and -6 or -3)
    elseif pBid == K.BID_SUN then
        strength = strength + 8
    elseif pBid and pBid:sub(1, #K.BID_HOKM) == K.BID_HOKM then
        strength = strength + (pIsBot and 5 or 3)
    end
    strength = strength + scoreUrgency(R.TeamOf(seat))
                       + matchPointUrgency(R.TeamOf(seat))
    local th = K.BOT_PREEMPT_TH or 75
    return strength >= jitter(th, BEL_JITTER)
end

-- ---------------------------------------------------------------------
-- Kawesh / Saneen detection
-- ---------------------------------------------------------------------
-- Bot decision to call hand-annul when holding 5+ cards of 7/8/9.
-- 13th-bot-audit: Kawesh was missing for bots — humans got the redeal
-- option but bots had to play unwinnable hands. Decision is
-- unconditional: if eligible, call. The hand has no honors, no length,
-- no scoring potential — redeal is strictly better than playing it.
function Bot.PickKawesh(seat)
    local hand = S.s.hostHands and S.s.hostHands[seat]
    if not hand then return false end
    if S.s.phase ~= K.PHASE_DEAL1 then return false end
    if C.IsKaweshHand and C.IsKaweshHand(hand) then return true end
    return false
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

-- v0.5.1 C-2: Bot.PickSWA — bot SWA initiation. Returns true when the
-- bot holds an unbeatable position; the caller (Net.lua MaybeRunBot)
-- then dispatches the SWA via the existing host SWA flow. Saudi
-- convention: SWA is the ≤4-card "I claim the rest" call. Validity is
-- delegated to R.IsValidSWA which runs the recursive minimax against
-- the host's authoritative hand state.
--
-- Gates:
--   • Bot.IsAdvanced() — Basic bots never call SWA
--   • Phase == PLAY
--   • S.s.hostHands[seat] exists and has ≤4 cards
--   • R.IsValidSWA returns true on the reconstructed trick state
function Bot.PickSWA(seat)
    if not Bot.IsAdvanced() then return false end
    if S.s.phase ~= K.PHASE_PLAY then return false end
    if not S.s.contract then return false end
    local hand = S.s.hostHands and S.s.hostHands[seat]
    if not hand or #hand == 0 or #hand > 4 then return false end

    -- Reconstruct trick state for the validator.
    local trickPlays = (S.s.trick and S.s.trick.plays) or {}
    local trickLead = S.s.trick and S.s.trick.leadSuit
    local trickLeader
    if #trickPlays > 0 then
        trickLeader = trickPlays[1].seat
    else
        trickLeader = S.s.turn or seat
    end
    local trickState = {
        leadSuit = trickLead, leader = trickLeader, plays = trickPlays,
    }
    -- Build all four hands for the validator.
    local hands = {}
    for s2 = 1, 4 do
        hands[s2] = (S.s.hostHands and S.s.hostHands[s2]) or {}
    end
    -- Delegate to R.IsValidSWA — single source of truth for SWA legality.
    return R.IsValidSWA(seat, hands, S.s.contract, trickState) == true
end
