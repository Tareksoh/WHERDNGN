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
-- v0.11.11 XU-07: thresholds promoted to K.* (Constants.lua); these
-- locals are now aliases for backward-compat with the existing call
-- sites. Single source of truth: K.BOT_TH_HOKM_R1_BASE / K.BOT_TH_HOKM_R2_BASE
-- / K.BOT_TH_SUN_BASE / K.BOT_BID_JITTER / K.BOT_SUN_VOID_PENALTY_CAP.
local TH_HOKM_R1_BASE = K.BOT_TH_HOKM_R1_BASE
local TH_HOKM_R2_BASE = K.BOT_TH_HOKM_R2_BASE
-- v0.10.6 Lever A: 50 → 47 (secondary calibration step for Sun
-- confidence, paired with v0.10.4 mardoofa bonus bump).
-- v0.11.9: paired with K.BOT_SUN_MARDOOFA_BONUS 10 → 20 + void-cap
-- 18 → 8. Predicted ~50% A+T-mardoofa Sun bid rate.
-- v0.11.10 user-arbitrated bidcalc trace evidence + audit BotU-16:
-- the v0.11.9 prediction was wrong because BID_JITTER is ±6 (not
-- ±25 as the v0.11.9 CHANGELOG assumed). At urgency=0:
--   Hand [QS TH AH 8C KH] sunStrength = 40, threshold band 41-53
--   → 0% fire rate (predicted 60%).
-- Drop to 40 to bring the threshold band to 34-46, restoring the
-- predicted Sun-bid rate on canonical A+T mardoofa hands. Math:
--   Hand [QS TH AH 8C KH] (sun=40) vs band 34-46 → fires when
--     jitter ≤ 0 (about 50% of jitter outcomes).
--   Hand [8H JC AC TC 7S] (sun=35) vs band 34-46 → fires when
--     jitter ≤ -5 (about 10-15%).
--   Hand [AS KH KC JH AD] (sun=24, 2-Ace-no-mardoofa) → 0%
--     (correctly conservative).
--   Weak A+T (sun~27) → 0% (correctly conservative).
local TH_SUN_BASE     = K.BOT_TH_SUN_BASE
local BID_JITTER      = K.BOT_BID_JITTER

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

-- v1.0.2 (BM-06 keep-decision): predicate intentionally retained
-- with no current heuristic carve-out. Tier API symmetry —
-- IsAdvanced / IsM3lm / IsFzloky all expose Is* predicates; future
-- Saudi-Master-only heuristics (e.g. T-sacrifice in Sun, opp-
-- seat-tracking-aware leads) will use this. Removing it now would
-- break the symmetric tier-detection idiom across the codebase.
-- Bot.PickPlay's BM.IsActive() delegation gates the ISMCTS-vs-
-- heuristic split; Bot.IsSaudiMaster() is for tier-specific code
-- inside the heuristic layer.
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

-- v1.1.0 (audit unpredictability HIGH-3 / MED-8): randomized suit
-- iteration. Pre-v1.1.0 the codebase had 21 separate
-- `for _, su in ipairs({ "S", "H", "D", "C" })` loops that selected
-- the FIRST matching suit — meaning Sun mardoofa probe always
-- opened with A♠, Bargiya/want-arm/T-4 dump always preferred ♠,
-- Tanfeer suit always picked ♠. Spades-first iteration was a
-- broadcast tell (a careful human reads "if bot's Tahreeb landed
-- on hearts, then their spades is too short or they would have
-- picked spades"). This helper returns a shuffled copy of the
-- 4-suit set so first-match selection no longer encodes alphabet
-- order. Per video #21: «التسعه ثمانيه سبعه ثاني نفس الشيء... لا
-- تفرق» — substitutable choices should look substitutable.
local function shuffledSuits()
    local s = { "S", "H", "D", "C" }
    -- Fisher-Yates in-place shuffle.
    for i = 4, 2, -1 do
        local j = math.random(i)
        s[i], s[j] = s[j], s[i]
    end
    return s
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
            -- v1.1.0 (audit partner-coord H3): receiver-side memory of
            -- partner's AKA emissions. When partner AKA's suit X,
            -- receiver records here so subsequent pickLead can treat
            -- X as a "want" suit (lead it back once partner's boss
            -- falls) and pickFollow can preserve high cards in X for
            -- partner's eventual lead-back. Per video #18 the AKA
            -- holder typically holds touching honors (boss + next-
            -- down rank) so receiver should keep the next-down to
            -- support a clean partner-runner.
            partnerAkaSuit = { S = false, H = false, D = false, C = false },
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
    --
    -- v0.9.2 #46 fix (audit_v0.9.0/46_bait_ledger_exploit.md): move
    -- baitedSuit and topTouchSignal from per-game to per-round scope.
    -- Pre-v0.9.2 these accumulated across the entire game (and even
    -- survived /reload via M4 persistence), so a deliberate or forced
    -- single-J play in round 1 silently locked the bot out of leading
    -- that suit for ALL remaining rounds. Round-scoping eliminates
    -- ~80% of the strategic damage at zero behavior change inside a
    -- single round. The signals are inherently round-local — touching-
    -- honors and deceptive-overplay both apply to current-trick state.
    if Bot._partnerStyle then
        for s = 1, 4 do
            local style = Bot._partnerStyle[s]
            if style then
                if style.tahreebSent then
                    style.tahreebSent = { S = {}, H = {}, D = {}, C = {} }
                end
                if style.baitedSuit then
                    style.baitedSuit = { S = 0, H = 0, D = 0, C = 0 }
                end
                if style.topTouchSignal then
                    style.topTouchSignal = { S = {}, H = {}, D = {}, C = {} }
                end
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
            -- v0.8.2 Section 11 rule 8: bait-detected ledger. When this
            -- seat plays J (highest of led suit / trump) AND their
            -- partner was already winning the pre-J trick state, the
            -- J was unnecessary — they're "wasting" it as a Saudi
            -- deceptive-overplay signal ("I'm void below J, re-lead
            -- this suit"). Per-suit count. Used by pickLead defender
            -- branch as an avoid-suit hint (don't re-lead the suit
            -- they baited; they have leverage there).
            -- Sources: decision-trees.md Section 11 rule 8 (Sometimes,
            -- video 08); Section 4 rules 4-5 (deceptiveOverplay).
            baitedSuit  = { S = 0, H = 0, D = 0, C = 0 },
            -- v0.9.0 Section 6 rules 1-4 (Definite, video 05):
            -- touching-honors-down ledger. When this seat plays
            -- T/K/Q in a trick led by their partner's Ace (or
            -- AKA-led), Saudi convention says they hold the
            -- next-rung-DOWN rank. When they play LOW (7/8) instead,
            -- they're broke in the suit's high cards.
            -- Per-suit nextDown ∈ {"K","Q","J"} or broke=true.
            -- Read by BotMaster sampler to bias hand distribution.
            -- Sources: decision-trees.md Section 6 rules 1-4 (Definite, 05).
            topTouchSignal = { S = {}, H = {}, D = {}, C = {} },
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
            -- v1.2.0 (Tier 5 control-the-game per video #20 «تمسك
            -- لون»): hand-strength signal counter. Each follow event
            -- where this seat played a low card (rank ≤ 9 in plain
            -- order, i.e. 7/8/9) under a partner-winning trick
            -- accumulates here as evidence of weak hand. Counterpart
            -- highCardPlays counts A/T/K plays; the ratio gives the
            -- bot a coarse "weak vs strong hand" read on partner.
            -- Used by pickFollow's pos-4 branch: if partner is
            -- showing weak hand, INVERT Faranka-duck behavior — TAKE
            -- the trick to keep tempo away from the weak partner.
            weakHandSignal  = 0,
            highCardPlays   = 0,
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
        --
        -- v1.0.3 (U-5) sender symmetry: in Hokm, when a seat is void
        -- in leadSuit AND has trump, must-trump-ruff forces them to
        -- play trump — that's not a discard, it's a forced ruff. The
        -- "suit-preference" signal interpretation only applies to
        -- truly free non-trump discards. The READER side at
        -- pickLead's firstDiscard branch already filters trump (see
        -- e.g. Bot.lua:~2474 in baitedSuit reader, similar pattern
        -- in firstDiscard consumer); we now mirror at the WRITER
        -- side so the ledger doesn't carry polluted entries.
        local s_contract = S.s and S.s.contract
        local isTrumpDiscard = s_contract and s_contract.type == K.BID_HOKM
                               and s_contract.trump
                               and cardSuit == s_contract.trump
        if not mem.firstDiscard and not isTrumpDiscard then
            mem.firstDiscard = { suit = cardSuit, rank = C.Rank(card) }
        end
    end

    -- v0.7.2 Section 11 rule 1 (Common, video 05): Sun + opp follows
    -- lead suit with K or higher AND loses → infer they have no
    -- card LOWER than what they played in that suit. Per the Saudi
    -- Tasgheer (play-smallest) convention, smaller cards would have
    -- been played first; reaching K or T means everything below it
    -- (Q/J/9/8/7) is structurally absent. Set void as a pragmatic
    -- approximation — the seat may still hold a single T (only rank
    -- larger than K in plain) but for sampler / opponentsVoidInAll
    -- purposes the void flag is the right signal.
    --
    -- A is excluded because A can't lose in Sun (highest plain rank).
    -- Q is excluded because the rule's confidence drops at Q; the
    -- speaker's explicit ~95%/90% bracket only covers K and Q-ish.
    -- Wiring K and T captures the strong end of the rule.
    -- Sources: decision-trees.md Section 11 rule 1 (Common, video 05).
    do
        local s_contract = S.s and S.s.contract
        local s_trick    = S.s and S.s.trick
        if not wasIllegal and leadSuit and cardSuit == leadSuit
           and s_contract and s_contract.type == K.BID_SUN
           and s_trick and s_trick.plays then
            local theirRank = C.Rank(card)
            if theirRank == "K" or theirRank == "T" then
                local theirTR = C.TrickRank(card, s_contract)
                local lost = false
                for _, p in ipairs(s_trick.plays) do
                    if p.seat ~= seat
                       and C.TrickRank(p.card, s_contract) > theirTR then
                        lost = true; break
                    end
                end
                if lost then
                    mem.void[leadSuit] = true
                end
            end
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

    -- Touching-honors-down inferences (Definite, video #05).
    -- When seat plays in a trick led by their PARTNER's Ace (or
    -- AKA-led), Saudi convention reads:
    --   plays T → has the K              (entry.nextDown = "K")
    --   plays K → K-singleton, no Q or J (entry.cleared = {"Q","J"})
    --   plays Q → has the J              (entry.nextDown = "J")
    --   plays 7/8/9 → broke in the suit  (entry.broke = true)
    -- v0.10.0 R6 fixed inverted K interpretation (was pinning Q to
    -- the seat that EXPLICITLY doesn't hold Q). Writer is symmetric;
    -- reader (BotMaster.lua) applies team-gate so opp inferences
    -- don't weaponize against the bot.
    if not wasIllegal and contract and trickPlays
       and #trickPlays >= 2 and style.topTouchSignal then
        local lead = trickPlays[1]
        local theirRank = C.Rank(card)
        -- Touching-honors context: lead was the Ace of cardSuit AND
        -- the lead seat is THIS seat's partner. (AKA-led equivalence
        -- captured via S.s.akaCalled with seat == partner of `seat`,
        -- suit == cardSuit.)
        local touchContext = false
        if lead.seat == R.Partner(seat)
           and C.Suit(lead.card) == cardSuit
           and C.Rank(lead.card) == "A" then
            touchContext = true
        elseif S.s.akaCalled and S.s.akaCalled.seat == R.Partner(seat)
               and S.s.akaCalled.suit == cardSuit then
            touchContext = true
        end
        if touchContext then
            -- v1.0.3 (U-4) forced-play gate. Mirror v0.9.2's #46
            -- baitedSuit forced-J gate (line ~562-590 below). The
            -- T/K/Q-under-partner-A signal is only meaningful if the
            -- seat had a CHOICE — i.e., they could have followed with
            -- a lower card and chose the honor. If we've observed no
            -- lower-rank cards from this seat in this suit yet, the
            -- honor play might have been mathematically forced (only
            -- card of suit in hand). Approximation: if any lower of
            -- this suit has been observed-played by THIS seat (mem
            -- .played accounts for prior plays this round + this one),
            -- record the signal. Otherwise suppress to avoid noise.
            -- Exception: 7/8/9 plays (rule 4 "broke") are SUPPRESSORS
            -- ("partner doesn't have any high left"), so they should
            -- always be recorded — a seat following with 7-9 is
            -- unambiguous "no honor in this suit". Forced-7/8/9 is
            -- the same signal regardless of choice.
            local recordOk = true
            if theirRank == "T" or theirRank == "K" or theirRank == "Q" then
                local lowerSeen = false
                if mem and mem.played then
                    for _, low in ipairs({ "7", "8", "9" }) do
                        if mem.played[low .. cardSuit] then
                            lowerSeen = true; break
                        end
                    end
                end
                if not lowerSeen then recordOk = false end
            end
            if recordOk then
                local entry = style.topTouchSignal[cardSuit] or {}
                if theirRank == "T" then
                    entry.nextDown = "K"                       -- rule 1
                elseif theirRank == "K" then
                    -- v0.10.0 R6 fix: K-signal = K-singleton, not has-Q.
                    entry.cleared = { "Q", "J" }               -- rule 2
                elseif theirRank == "Q" then
                    entry.nextDown = "J"                       -- rule 3
                elseif theirRank == "7" or theirRank == "8"
                    or theirRank == "9" then
                    entry.broke = true                         -- rule 4
                end
                style.topTouchSignal[cardSuit] = entry
            end
        end
    end

    -- v0.8.2 Section 11 rule 8: bait-detected ledger. Detect when
    -- `seat` plays J of led suit (or trump) when their partner was
    -- already winning the pre-J trick state. The J was unnecessary
    -- for trick-taking — Saudi convention reads this as deceptive
    -- overplay ("I'm void below J, re-lead this suit").
    -- Detection requires:
    --   • #trickPlays >= 2 (we have prior plays to evaluate)
    --   • The played card is J
    --   • Pre-J trick winner == seat's partner
    -- The increment fires per-suit per-occurrence; pickLead reads
    -- it as a suit-avoid hint via the Fzloky avoid pipeline.
    -- Sources: decision-trees.md Section 11 rule 8 (Sometimes, 08);
    -- Section 4 rules 4-5 (deceptiveOverplay sender, deferred).
    if not wasIllegal and contract and #trickPlays >= 2
       and C.Rank(card) == "J" and style.baitedSuit then
        local prePlays = {}
        for i = 1, #trickPlays - 1 do prePlays[i] = trickPlays[i] end
        if #prePlays >= 1 then
            local prevTrick = { plays = prePlays, leadSuit = leadSuit }
            local prevWinner = R.CurrentTrickWinner(prevTrick, contract)
            if prevWinner == R.Partner(seat) then
                -- v0.9.2 #46 forced-J gate (audit
                -- audit_v0.9.0/46_bait_ledger_exploit.md): the previous
                -- predicate flagged ANY J-play under partner-winning as
                -- a bait, including the case where J was opp's only
                -- remaining card in suit (mathematically forced — no
                -- choice). To approximate "lower legal alternative
                -- existed", check whether ANY lower-rank card of this
                -- suit has been observed played already this round
                -- (in completed tricks or current-trick prior plays).
                -- If no lower has appeared anywhere, the J might still
                -- be in someone's hand — but if a lower was previously
                -- played by THIS seat, then they HELD lowers and chose
                -- to play J anyway → genuine bait. We approximate: if
                -- this seat's `mem.played` doesn't yet contain any
                -- lower-than-J of this suit, suppress (likely forced).
                local lowerSeen = false
                local plain = K.RANK_PLAIN
                local jr = plain["J"] or 0
                if mem and mem.played then
                    for _, low in ipairs({ "7", "8", "9" }) do
                        if mem.played[low .. cardSuit] then
                            lowerSeen = true; break
                        end
                    end
                end
                if lowerSeen then
                    style.baitedSuit[cardSuit] =
                        (style.baitedSuit[cardSuit] or 0) + 1
                end
            end
        end
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
                -- v1.2.0 (Tier 5 control-the-game per video #20):
                -- accumulate hand-strength signal. When this seat
                -- plays under partner-winning trick they have a
                -- CHOICE of high vs low. A low-card play (7/8/9)
                -- under partner-winning is a "weak hand" tell;
                -- A/T/K plays are "strong hand" tells (Takbeer/
                -- magnify donation). Per the video: «اذا انت عندك
                -- قوه ... تحاول تمسك اللعب» — strong hand holds
                -- tempo; weak hand defers to strong partner.
                if style.weakHandSignal ~= nil then
                    local r = C.Rank(card)
                    if r == "7" or r == "8" or r == "9" then
                        style.weakHandSignal = style.weakHandSignal + 1
                    elseif r == "A" or r == "T" or r == "K" then
                        style.highCardPlays = style.highCardPlays + 1
                    end
                end
                -- v1.1.1 (M2 audit): forced-vs-intentional flag.
                -- Pre-fix the bot recorded its discard as a Tahreeb
                -- signal even when it was FORCED to discard from its
                -- only-non-led-non-trump suit. Per video #03 + #09
                -- the Saudi convention is "Tahreeb AWAY from your
                -- real holding"; forced dumps from a strong suit
                -- corrupt the partner-side read. Detect: if the
                -- player's POST-play hand has 0 other non-led
                -- (non-trump in Hokm) suits, the discard was forced.
                -- Marked as `list.forced[i] = true`; tahreebClassify
                -- filters forced events out of the signal sequence.
                local trumpSuit = (contract.type == K.BID_HOKM)
                                   and contract.trump or nil
                local postHand = (S.s.isHost and S.s.hostHands
                                   and S.s.hostHands[seat]) or {}
                local distinct = {}
                for _, c in ipairs(postHand) do
                    local su = C.Suit(c)
                    if su ~= leadSuit and su ~= trumpSuit then
                        distinct[su] = true
                    end
                end
                local n = 0
                for _ in pairs(distinct) do n = n + 1 end
                -- Pre-play also had `cardSuit`; if post-play count
                -- was 0 (no other non-led non-trump option) then the
                -- discard was forced — bot had only this one suit.
                local isForced = (n == 0)
                local list = style.tahreebSent[cardSuit]
                if list then
                    -- v0.10.2 M7 — Bargiya canonical FN: محشور بلون
                    -- واحد (cornered in one suit, video #14 rule 2)
                    -- promotes a single-event A discard from
                    -- bargiya_hint to confirmed bargiya WITHOUT a
                    -- second event. The classifier needs the sender's
                    -- pre-discard length-in-suit for that suit; capture
                    -- it host-side from S.s.hostHands (host has all
                    -- hands; non-host clients can't observe sender
                    -- shape). Stored as `list.lenAtAce` to keep the
                    -- numeric array of ranks backward-compatible.
                    -- Computed BEFORE the rank append so #list reads
                    -- the pre-record count for the Ace-first guard.
                    if C.Rank(card) == "A" and #list == 0
                       and S.s.isHost and S.s.hostHands and S.s.hostHands[seat] then
                        local preLen = 0
                        for _, c in ipairs(S.s.hostHands[seat]) do
                            if C.Suit(c) == cardSuit then
                                preLen = preLen + 1
                            end
                        end
                        -- ApplyPlay already removed the discarded card,
                        -- so add 1 back to recover sender's pre-discard
                        -- length-in-suit (the discard was on cardSuit).
                        list.lenAtAce = preLen + 1
                    end
                    -- v1.5.0 (audit follow-up — Tanfeer factor 5,
                    -- video #19 §2.5): record FIRST-trick-N per suit
                    -- so factor-5 cancellation logic can detect when
                    -- an opp has SWITCHED signaled suits across
                    -- tricks. Per video: "opp discards X first, then
                    -- later discards Y → CANCEL the X-read; top now
                    -- attributed to Y." Stored as `list.firstTrickN`
                    -- alongside the rank array; only set on first
                    -- event for the suit (don't overwrite).
                    if not list.firstTrickN then
                        list.firstTrickN = #(S.s.tricks or {}) + 1
                    end
                    list[#list + 1] = C.Rank(card)
                    -- v1.1.1 (M2): parallel forced-flag list, indexed
                    -- the same as the rank list. tahreebClassify
                    -- filters forced events before classification.
                    list.forced = list.forced or {}
                    list.forced[#list] = isForced
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

-- Hokm minimum shape «الحكم المغطى» (Definite, video #26).
-- Returns true when:
--   (count >= 4 AND hasJ)                    ← B-2 self-sufficient
--   OR (count == 3 AND hasJ AND hasSideAce)  ← B-1 minimum
-- Floor (B-4): no J or count <= 2 → never bid Hokm.
-- M3lm+ also requires ≥1 Ace anywhere (Pro-2 PDF L07 defensive
-- rule against Sun-overcall / Kaboot / Carré-A by opp; tier-gated
-- as STRATEGY per Phase 1 Source H, not a hard rule).
local function hokmMinShape(hand, suit)
    if not suit then return false end
    local hasJ, count = false, 0
    local hasSideAce = false
    local hasAnyAce  = false
    -- v0.11.9 RT07-07 fix: track whether the second trump card is a
    -- canonical mardoofa partner (9 or A). In Saudi Hokm trump order
    -- J=1st, 9=2nd, A=3rd; J+9 is the top mardoofa pair, J+A is also
    -- strong. J+7, J+8, J+T, J+Q, J+K are NOT real mardoofa per the
    -- video #26 R2 canonical rule "الولد + مردوفة معاه" (J + its
    -- mardoofa partner). Used by the count==2 branch below.
    local hasTrumpA, hasTrumpNine = false, false
    for _, c in ipairs(hand) do
        local r, su = C.Rank(c), C.Suit(c)
        if su == suit then
            count = count + 1
            if r == "J" then hasJ = true end
            if r == "A" then hasAnyAce = true; hasTrumpA = true end
            if r == "9" then hasTrumpNine = true end
        elseif r == "A" then
            hasSideAce = true
            hasAnyAce  = true
        end
    end
    -- v0.11.16 BS-1 fix (audit A2): Belote K+Q-of-trump escape clause.
    -- Saudi rule B-6 (Mandatory, video #26): "K+Q of trump (سراء ملكي)
    -- + count >= 2 -> Mandatory Hokm with that suit as trump." The +20
    -- multiplier-immune Belote bonus is structural — failing to bid
    -- the Belote suit forfeits the canonical Saudi-tournament-mandatory
    -- bid. Pre-v0.11.16 the J-floor at line below blocked this when
    -- the hand had K+Q of suit X but no JX; e.g. [KS QS 8C 9C 7H]
    -- (K+Q spades + 2 trumps) was rejected. Saudi convention says J
    -- is irrelevant when K+Q-Belote locks the contract. Runs BEFORE
    -- the J-floor so this single canonical pattern bypasses all other
    -- shape gates.
    do
        local hasKsuit, hasQsuit = false, false
        for _, c in ipairs(hand) do
            if C.Suit(c) == suit then
                if C.Rank(c) == "K" then hasKsuit = true
                elseif C.Rank(c) == "Q" then hasQsuit = true end
            end
        end
        if hasKsuit and hasQsuit and count >= 2 then return true end
    end
    if not hasJ then return false end          -- B-4 absolute floor
    if count >= 4 then return true end         -- B-2 self-sufficient
    -- v0.11.15 Q2 user-audit: self-sufficient mardoofa relax.
    -- Pre-v0.11.15 the v0.10.0 L07 M3lm gate (`hasAnyAce` required)
    -- fired BEFORE the count checks below, rejecting hands like
    -- [JC 9C 8C JS QH] (J + 9 of trump + count=3, NO Aces anywhere)
    -- — which is the canonical Saudi "ولد ومردوفته" (J + mardoofa
    -- partner) self-sufficient pattern. The v0.11.9 RT07-07 fix
    -- correctly identified J+9 (or J+A) as canonical mardoofa per
    -- video #26, but only used it in the count==2 path. This
    -- count>=3 extension recognizes that J+9 plus ANY third trump is
    -- structurally self-sufficient — the J takes top trick, the 9
    -- takes any second-rank trick, and the third trump locks the
    -- suit. No side Ace needed. Matches video #26 R2 canonical-min
    -- worked example. Trace evidence: bot s2 r2 [JC 9C 8C JS QH]
    -- failed L07 even though it's a respectable Hokm-clubs hand.
    if count >= 3 and hasTrumpNine then return true end
    -- v0.10.0 L07 tier-gated requirement: M3lm requires any Ace
    -- from here on (for the count==3+sideAce / count==2 paths).
    if Bot.IsM3lm and Bot.IsM3lm() and not hasAnyAce then
        return false
    end
    if count == 3 and hasSideAce then return true end  -- B-1 minimum
    -- v0.10.6 Lever C — R2 canonical minimum (review_v0.10.2
    -- BIDDING_CALIBRATION_v0.10.5.md §8.1, video #26 R2):
    -- "أقل شي عشان تشتري الحكم: الولد + مردوفة معاه + إكا واحدة"
    -- — "minimum to buy Hokm: J of trump + ONE other trump (mardoofa
    -- with the J) + ONE Ace on the side."
    --
    -- v0.11.9 RT07-07 closure: the v0.10.6 implementation was too
    -- loose — `count == 2 and hasSideAce` admitted ANY second trump
    -- (including J+7, J+8, J+T, etc.) as a "mardoofa". Live bidcalc
    -- trace evidence: bot s4 r2 bid Hokm-S on [JS 8S + AC side],
    -- which is exactly the "weak mardoofa" RT07-07 audit predicted.
    -- Per video #26 the "مردوفة" (mardoofa partner of J) is
    -- specifically 9 or A — the 2nd and 3rd ranks in Saudi Hokm
    -- trump order. v0.11.9 tightens the count==2 branch to require
    -- the second trump be 9 or A — closing the loose gate.
    if count == 2 and hasSideAce and (hasTrumpNine or hasTrumpA) then
        return true   -- R2 canonical min: J + (9 or A trump) + side Ace
    end
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
        for _, su in ipairs(shuffledSuits()) do
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
    for _, su in ipairs(shuffledSuits()) do
        if hasK[su] and hasQ[su] then return su end
    end
    return nil
end

-- v1.0.9 A#2 (swarm finding): BC-MANDATORY-Belote bypass tightening.
-- Pre-v1.0.9 the BC-MANDATORY bypass fired whenever the Belote suit
-- merely passed `hokmMinShape` (which admits K+Q+count==2 via the
-- v0.11.16 escape clause). That over-counted weak K+Q-only hands as
-- "Mandatory Belote" — yielding sub-threshold Hokm bids that
-- routinely failed in real games. Saudi convention treats Belote as
-- "Mandatory" only when the hand has STRUCTURAL backing beyond the
-- bare K+Q pair: either a canonical 4-card trump sequence containing
-- the K+Q (T-J-Q-K or J-Q-K-A — both score as 50 raw per
-- K.MELD_SEQ4, plus the +20 Belote bonus), OR K+Q + count>=3 + a
-- side Ace (so the side Ace stables the hand even without a 4th
-- trump). Below those thresholds the bypass falls through to the
-- standard strength gate, preserving the +20 Belote bonus
-- contribution to the strength score (no loss of Belote awareness,
-- just gating it correctly).
--
-- Returns true if `suit` (with `hand` evaluated as the post-bidcard
-- hypothesis hand) qualifies for the BC-MANDATORY bypass.
local function beloteBypassQualifies(hand, suit)
    if not suit then return false end
    local has = { ["T"] = false, ["J"] = false, ["Q"] = false,
                  ["K"] = false, ["A"] = false }
    local count = 0
    local hasSideAce = false
    for _, c in ipairs(hand) do
        local r, su = C.Rank(c), C.Suit(c)
        if su == suit then
            count = count + 1
            if has[r] ~= nil then has[r] = true end
        elseif r == "A" then
            hasSideAce = true
        end
    end
    -- Canonical 4-card trump sequence T-J-Q-K (top anchored at K).
    if has["T"] and has["J"] and has["Q"] and has["K"] then return true end
    -- Canonical 4-card trump sequence J-Q-K-A (top anchored at A).
    if has["J"] and has["Q"] and has["K"] and has["A"] then return true end
    -- K+Q + count>=3 + side Ace stabilization.
    if has["K"] and has["Q"] and count >= 3 and hasSideAce then return true end
    return false
end

-- v1.0.10 (audit pass-2 C MED-1): expose the helper on Bot for
-- direct unit testing. The PickBid path can satisfy A#2 transitively
-- through threshold passes, making it impossible to behaviorally
-- isolate the canonical-4-seq vs K+Q+count>=3+sideAce branches via
-- PickBid alone (T-J-Q-K hands always clear thHokmR1 on strength
-- alone). Direct unit tests on this helper let us pin EACH branch
-- independently. Underscore prefix marks it as test-internal.
Bot._beloteBypassQualifies = beloteBypassQualifies

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
    for _, su in ipairs(shuffledSuits()) do
        if hasA[su] and hasT[su] then mardoofaCount = mardoofaCount + 1 end
    end
    return aceCount, mardoofaCount
end

-- v1.0.0 Cluster 1 (meld awareness): cards we KNOW seat holds via
-- declared melds. Melds are public information (declared in trick 1);
-- subsequent trick play should factor known-card distributions. The
-- BotMaster ISMCTS sampler already pins meld cards for world-sample
-- generation (BotMaster.lua:243-260); this helper extends the same
-- knowledge to the heuristic Bot.PickPlay layer (used by Advanced/
-- M3lm/Fzloky tiers AND as the Saudi-Master rollout policy per C-14).
--
-- Returns a set: { ["AS"]=true, ["KH"]=true, ... } of cards we know
-- `seat` holds, EXCLUDING cards already played (those are no longer
-- in hand; consult Bot._memory[seat].played for that).
local function meldKnownHeld(seat)
    local out = {}
    if not S.s or not S.s.meldsByTeam then return out end
    -- A meld is declared by ONE seat (declaredBy). The meld team
    -- bracket holds it. Iterate both teams and pick declarers matching.
    local mem = Bot._memory and Bot._memory[seat]
    local played = (mem and mem.played) or {}
    for _, team in ipairs({ "A", "B" }) do
        for _, m in ipairs(S.s.meldsByTeam[team] or {}) do
            if m.declaredBy == seat and m.cards then
                for _, c in ipairs(m.cards) do
                    if not played[c] then out[c] = true end
                end
            end
        end
    end
    return out
end

-- v0.11.17 audit B3: known-cards-held-by-bidder helper. After
-- HostDealRest the bidder owns the bidcard; this is PUBLIC knowledge
-- (the bidcard was face-up during bidding). Defender bots that don't
-- factor this in waste a trick or two probing for trump distribution
-- that was already known. Returns true iff the seat is the bidder
-- AND the card is the bidcard AND the bidcard hasn't yet been played.
local function bidderHoldsBidcard(seat, card)
    if not S.s or not S.s.contract or not S.s.bidCard then return false end
    if seat ~= S.s.contract.bidder then return false end
    if card ~= S.s.bidCard then return false end
    -- v0.11.17-hotfix F4 (post-ship audit): phase-gate to PHASE_PLAY
    -- only. Pre-fix the helper returned true during the escalation
    -- phases (PHASE_BEL through PHASE_GAHWA), where the contract is
    -- set and bidcard is set but HostDealRest hasn't yet appended
    -- the bidcard to hostHands[bidder]. A planned v0.11.18 caller
    -- using this for trump-J inference would mis-attribute the J of
    -- trump to the bidder's hand mid-escalation, breaking trump-pull
    -- coordination logic. Defenders should know "bidder will hold
    -- bidcard once HostDealRest fires" — which is true only at and
    -- beyond PHASE_PLAY.
    if S.s.phase ~= K.PHASE_PLAY then return false end
    -- If the bidcard's already been played, the bidder no longer
    -- holds it. Bot._memory tracks played-by-seat.
    local mem = Bot._memory and Bot._memory[seat]
    if mem and mem.played and mem.played[card] then return false end
    return true
end

-- v0.11.16 audit BC-1: hypothetical post-win hand helper. The bidder
-- gets the bidcard appended to their final hand at HostDealRest
-- (State.lua:1950). Pre-v0.11.16, only the R1 Hokm-on-flipped path
-- (v0.11.15) included the bidcard in evaluation; R1 Sun, R2 Hokm,
-- R2 Sun, PickPreempt, and PickOvercall didn't. This helper unifies
-- the pattern across all bid pickers. Returns `hand` unchanged when
-- there's no bidcard (defensive — should always be present in
-- bidding phases).
local function withBidcard(hand, bidcard)
    if not bidcard then return hand end
    local out = {}
    for _, c in ipairs(hand) do out[#out + 1] = c end
    out[#out + 1] = bidcard
    return out
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
    for _, su in ipairs(shuffledSuits()) do
        if count[su] >= 5 and (hasA[su] or hasK[su]) then
            s = s + (count[su] - 4) * 6
        end
        -- Stopper triple: AKQ in same suit means 3 guaranteed tricks.
        -- v0.11.20 (Agent 1 calibration math): +12 (was +8). AKQ-trio
        -- = 3 guaranteed tricks ≈ 30 raw points. Existing face value
        -- of A+K+Q = 11+4+3 = 18 already contributes ~60% of trick
        -- value; the +12 bonus closes the structural gap to 30.
        -- Modest +0.18pp Bel-rate impact alone (rare shape: 0.87% of
        -- 5-card hands have AKQ in any suit), but rule-correct.
        if hasA[su] and hasK[su] and hasQ[su] then s = s + 12 end
    end
    if Bot.IsAdvanced() then
        local penalty = 0
        for _, su in ipairs(shuffledSuits()) do
            if count[su] < 2 or not honors[su] then penalty = penalty + 10 end
        end
        -- v0.11.9 user-arbitrated (bidcalc trace): cap reduced 18 → 8.
        -- v0.11.11: promoted to K.BOT_SUN_VOID_PENALTY_CAP for tunability.
        -- The void/short-suit penalty is HOKM-think mistakenly applied
        -- to Sun. In Hokm, voids = ruff vulnerabilities (opponents trump
        -- from your void). In Sun there's no trump, so voids are
        -- neutral or even POSITIVE for the bidder (you discard freely
        -- on opp leads). Pre-v0.11.9 a hand like [QS TH AH 8C KH] —
        -- A+T+K of hearts (locked suit) plus 3 mid singletons — got
        -- 28 face value − 18 penalty = 10 base. The penalty wiped out
        -- the entire face-value advantage of the A+T+K trio. Cap of 8
        -- preserves "definitely-junk hand" filtering (e.g. all 4
        -- suits void/honorless = -8 still) without erasing strong
        -- single-suit concentrations. v0.10.0 history: pre-Gemini
        -- 25 → softened 18 → v0.11.9 8.
        s = s - math.min(penalty, K.BOT_SUN_VOID_PENALTY_CAP)
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
        -- v1.0.3 (PB-1): split bidder vs defender semantics for PASS.
        -- For the BIDDER side (seat == contract.bidder, partner = bidder's
        -- teammate), partner's PASS is legitimate weakness signal — they
        -- couldn't bid this contract type, suggesting partner's hand
        -- doesn't reinforce ours. Penalty applies.
        --
        -- For DEFENDERS, partner is the OTHER defender; both defenders
        -- pass in any bidding round (only the bidder team's seat bids).
        -- Defender-partner PASS is uninformative noise — escalating
        -- (Bel/Four) is a hand-quality decision unrelated to whether
        -- our partner-defender passed earlier. Suppress the penalty for
        -- defenders so the threshold isn't unfairly raised on their
        -- escalation paths.
        local seatIsBidder = (contract and contract.bidder
                              and R.TeamOf(seat) == R.TeamOf(contract.bidder))
        if not seatIsBidder then
            return 0
        end
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

-- v0.8.1 B-95: opponent score-urgency reader. Mirrors `scoreUrgency`
-- but reads from `oppSeat`'s team perspective. Used to model how
-- desperate the opp is — desperate opponents bid marginally and
-- commit weak Hokm/Sun contracts more readily, which our defensive
-- counter-play should anticipate.
--
-- Returns:
--   +12 — opp's team is on the brink (their opp-from-them ≥ target-25,
--         which is OUR team near-clinch from opp's view) → opp likely
--         to commit Hail-Mary bids and escalations.
--    +6 — opp behind 80+ relative to us → opp risk-tolerant bidder.
--    -8 — opp near clinch themselves (their cumulative ≥ target-25)
--         → conservative bidder, less likely to overbid.
--     0 — neutral.
--
-- M3lm-gated (style-modeling tier; lower tiers stay simple).
-- Sources: bot_picker_gaps.md / wave8 B-95 — "human score-position
-- signaling via bid aggressiveness".
local function opponentUrgency(oppSeat)
    if not Bot.IsM3lm() then return 0 end
    if not S.s.cumulative or not oppSeat then return 0 end
    local oppTeam = R.TeamOf(oppSeat)
    if not oppTeam then return 0 end
    local opp_cum = S.s.cumulative[oppTeam] or 0
    local our_cum = S.s.cumulative[(oppTeam == "A") and "B" or "A"] or 0
    local target = (S.s.target or 152)
    -- Mirror of scoreUrgency from opp's POV:
    if opp_cum >= target - 25 then return -8 end       -- opp near clinch
    if our_cum >= target - 25 then return  12 end      -- opp desperate (we near win)
    if our_cum - opp_cum > 80  then return  6  end     -- opp far behind us
    return 0
end

-- Public wrapper for cross-module use (BotMaster sampler reads this).
function Bot.OpponentUrgency(oppSeat)
    return opponentUrgency(oppSeat)
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

-- v0.6.0 H-7 fix: cap COMBINED urgency at ±15. The per-call cap on
-- matchPointUrgency (±10) plus scoreUrgency's max of +12 still allowed
-- combined urgency to reach +22, dropping BOT_BEL_TH from 70 to 48
-- in worst case — bot Bels garbage hands when desperate. Per the
-- audit comment intent ("combined cap ±15"), clamp the SUM here so
-- callers can compute `urgency = combinedUrgency(team, context)` once
-- without reasoning about per-component bounds.
local function combinedUrgency(myTeam, context)
    local raw = scoreUrgency(myTeam, context) + matchPointUrgency(myTeam)
    if raw >  15 then return  15 end
    if raw < -15 then return -15 end
    return raw
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
        -- v1.0.3 (PEB-DEAD): the `contract.foured` branch is currently
        -- DEAD CODE — partnerEscalatedBonus is consulted from
        -- escalationStrength via PickTriple/PickFour/PickGahwa, and
        -- contract.foured is only set AFTER PickFour returns true.
        -- PickFour runs at PHASE_FOUR with foured=false (it's the
        -- defender's CURRENT decision); subsequent rungs (PickGahwa)
        -- run on the bidder side, where the partner's team is the
        -- BIDDER team — pIsDefender=false. Reserved for any future
        -- "post-Gahwa override" decision points where a defender-side
        -- partner with a Foured contract might re-evaluate. Kept
        -- intentionally so the bonus is one edit away when needed.
        if contract.foured  then bonus = bonus + 8  end
    end
    -- Bidder-team partner: their team has been escalating (Triple/Gahwa).
    if pIsBidderTeam then
        if contract.tripled then bonus = bonus + 5  end
        -- v1.0.3 (PEB-DEAD): the `contract.gahwa` branch mirrors the
        -- foured-dead-code rationale above. PickGahwa runs at
        -- PHASE_GAHWA with gahwa=false (the bidder's CURRENT decision).
        -- gahwa=true is only seen by post-Gahwa override pickers
        -- (none currently). Same reserved-for-future stance.
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

    -- v0.11.8 — bidcalc trace helper. Toggled via /baloot bidcalc.
    -- Used for diagnosing user-reported "bots not bidding Sun" patterns.
    -- Each call prints to chat with `[bid sN rR]` prefix so the user
    -- can correlate against the visible bid sequence. Returns silently
    -- when the toggle is off (zero overhead in production). Format
    -- pcall'd so a bad fmt-string can't crash bot dispatch.
    local function btrace(fmt, ...)
        if not (WHEREDNGNDB and WHEREDNGNDB.debugBidcalc) then return end
        local ok, msg = pcall(string.format, fmt, ...)
        if not ok then return end
        print(("|cff66ddff[bid s%d r%s]|r %s"):format(
            seat or 0, tostring(round or "?"), msg))
    end

    -- v0.5.8 patch S-4 (decision-trees.md Section 1, Sun bidding):
    -- Carré of Aces (الأربع مئة, "Four Hundred") = 200 raw × 2 (Sun
    -- multiplier) = 400 effective. Saudi rule: ALWAYS Sun, regardless
    -- of any other consideration. Earliest possible return — beat
    -- every other bid path.
    -- Sources: decision-trees.md S-4 (Definite, videos 25, 32, 38).
    local aceCount, mardoofaCount = aceCountAndMardoofa(hand)
    if aceCount >= 4 then
        btrace("S-4 auto-Sun: 4 Aces in hand → BID_SUN")
        return K.BID_SUN
    end

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
    -- v0.11.16 audit BC-1: include bidcard in Sun evaluation. The
    -- bidder will receive the bidcard added to their final hand —
    -- its face value contributes directly to sunStrength (no trump
    -- in Sun, so suit doesn't matter; only rank face value). E.g.,
    -- bidcard AC adds +11 to sunStrength of any seat that wins the
    -- bid. Pre-v0.11.16 this was undercounted in R1 Sun, R2 Sun,
    -- PickPreempt, and PickOvercall paths.
    local sunHand = withBidcard(hand, S.s.bidCard)
    local sun = sunStrength(sunHand)
    -- Recompute aceCount on the post-bidcard hand for bonus eligibility.
    local sunAces = aceCount
    if S.s.bidCard and C.Rank(S.s.bidCard) == "A" then
        sunAces = sunAces + 1
    end
    if sunAces >= 3 then sun = sun + K.BOT_SUN_3ACE_BONUS
    -- v0.11.14 user-bidcalc trace: 2-Ace hands without mardoofa or AKQ
    -- triple were consistently rejected (sun=17-21 vs thSun=38-46).
    -- Per Saudi rule S-1, 2 Aces IS the canonical Sun shape — these
    -- hands SHOULD bid. Adding the bonus brings score into the jitter
    -- fire-band. elseif gates against double-applying with 3-Ace.
    elseif sunAces == 2 then sun = sun + K.BOT_SUN_2ACE_BONUS end
    -- v0.11.16-hotfix MD-01 (post-ship audit): recompute mardoofa
    -- count on the post-bidcard sunHand. Pre-hotfix the bidcard
    -- providing the missing A or T to complete an A+T mardoofa pair
    -- (e.g., hand [8C 9C TC AS 7H] + bidcard AC -> AC+TC mardoofa)
    -- was missed; the +20 K.BOT_SUN_MARDOOFA_BONUS per pair didn't
    -- fire because mardoofaCount was from the 5-card hand.
    local _, sunMardoofa = aceCountAndMardoofa(sunHand)
    sun = sun + math.min(sunMardoofa, K.BOT_SUN_MARDOOFA_PAIR_CAP)
              * K.BOT_SUN_MARDOOFA_BONUS

    -- v0.5.8 patch B-6 (decision-trees.md Section 1, Hokm bidding):
    -- detect Belote (سراء ملكي = K+Q of trump). The +20 Belote bonus
    -- is multiplier-immune so locking it in by bidding the suit as
    -- trump is a Saudi MUST. Computed once, applied in both round 1
    -- (Hokm-on-flipped) and round 2 (best-suit search).
    -- Sources: decision-trees.md B-6 (Definite, video 26).
    -- v0.11.16-hotfix GAP-01 (post-ship audit): Belote detected on the
    -- post-bidcard hand. Pre-fix `belote` was computed on the bare
    -- 5-card hand, so a hand `[QS 8C 9C 7H X]` + bidcard `KS` passed
    -- the v0.11.16 K+Q-of-trump shape gate (A2/BS-1) BUT missed the
    -- +20 strength bonus, leaving strength below thHokmR1. The two
    -- halves of A2 were mutually inconsistent — shape-pass without
    -- the strength-pass that justifies it. Recompute on hand+bidcard.
    local belote = beloteSuit(withBidcard(hand, S.s.bidCard))

    -- v0.6.0 H-7: capped at ±15 to prevent garbage Bels under desperation.
    local urgency = combinedUrgency(R.TeamOf(seat))
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
    -- v0.11.20 (Agent 1 calibration math): Advanced R2 bump REMOVED.
    -- Pre-fix `if Bot.IsAdvanced() then r2Base = math.max(r2Base, r1Base - 4) end`
    -- bumped Advanced R2 from 36 to 38. Sim showed (n=20K, jitter=±6):
    --   r2=36 -> R1/R2 split 56.8/43.2 (closest to canonical 50/50)
    --   r2=38 -> 58.1/41.9 (over-suppresses R2 by 1.3pp)
    -- Empirical 33-round data showed R1 over-fires 73% (well above
    -- canonical 50-60%). Removing the bump shifts R2 share up ~1.3pp
    -- and tightens toward the canonical Saudi distribution. The
    -- 13th-bot-audit comment claimed the bump prevented R2 < R1
    -- leakage, but real data shows the opposite — R2 was already
    -- over-suppressed. Net: r2Base = 36 unconditionally for all
    -- tiers via the K constant.
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

    -- v0.11.8 bidcalc: log thresholds + base strength once per call.
    -- v0.11.19 audit (post-3-game forensic): use POST-bidcard sunAces
    -- and sunMardoofa to match the `sun` value reported. Pre-fix the
    -- log displayed PRE-bidcard counts but POST-bidcard sun, producing
    -- impossible-looking trace lines like `sun=64 aces=1 mardoofa=0`
    -- (where the 64 actually came from a 3-Ace + 1-mardoofa bonus
    -- stack on the post-bidcard hand). The discrepancy made trace
    -- lines unreliable for empirical calibration analysis.
    btrace("hand=[%s] sun=%d sunAces=%d sunMardoofa=%d urgency=%d thSun=%d thHokmR1=%d thHokmR2=%d",
           table.concat(hand, " "), sun, sunAces, sunMardoofa,
           urgency, thSun, thHokmR1, thHokmR2)

    -- v0.6.0 B-7: Bel-fear bias for Sun bidding (Common, video 25).
    -- When OUR team's cumulative is at >= K.SUN_BEL_CUMULATIVE_GATE
    -- (=100), the OTHER team can still Bel us in Sun (per the E-1
    -- Saudi rule: only the team <100 may Bel; opp at <100 still
    -- qualifies). Failing a Bel'd Sun = ×2 multiplier on
    -- handTotal=130 raw = 26 game points lost — major setback.
    -- Bias the Sun threshold UP to deter Sun bids when we're at risk.
    -- The +8 nudge is roughly one strength-tier penalty.
    -- Sources: decision-trees.md S-7 / Section 1 row "Cumulative score
    -- ≥100 (Sun-Bel-gate context)" (Common, video 25).
    if S.s.cumulative then
        local myTotal = S.s.cumulative[R.TeamOf(seat)] or 0
        -- v1.1.0 (audit unpredictability MED-9): Bel-fear piecewise
        -- ramp instead of single +8 cliff. Pre-fix at cumulative=100
        -- normal Sun bid; at 101 threshold +8 — a hard cliff that a
        -- careful human could read.
        --
        -- v1.2.1 (audit A5): jitter the knees per-call so the same
        -- `myTotal` produces different bias across rounds. Pre-v1.2.1
        -- knees at 90/105/130 were sharp inflection points; opp
        -- could observe "bot bid Sun at cum=104 but not at cum=131"
        -- and infer the ramp structure. ±3 jitter at each knee
        -- preserves the underlying shape (still piecewise) while
        -- breaking the precise-ledge tell.
        local k1 = 90 + math.random(-3, 3)
        local k2 = 105 + math.random(-3, 3)
        local k3 = 130 + math.random(-3, 3)
        if myTotal < k1 then
            -- no bias
        elseif myTotal <= k2 then
            thSun = thSun + math.floor(8 * (myTotal - k1) / math.max(1, k2 - k1))
        elseif myTotal <= k3 then
            thSun = thSun + 8
        else
            local span = math.max(0, math.min(22, myTotal - k3))
            thSun = thSun + 8 - math.floor(5 * span / 22)
        end
    end

    -- v1.1.0 (audit unpredictability MED-10): round-1 position-aware
    -- conservatism. Pre-fix R1 first-lap-pass discipline (per video
    -- #25 «اول دور... اذا كنت تشك خلاص امرر») wasn't wired — bidPos
    -- 1 (info-poor) bid identical hands the same way as bidPos 4
    -- (info-rich). Now: position-bias adds to thHokmR1/thSun.
    --
    -- v1.2.2 user-reported tuning: pre-v1.2.2 bias was +5/+3 which
    -- COMPOUNDED with the existing Bel-fear ramp (0–8) and BID_JITTER
    -- (±6) to push thSun unreachable for moderate hands. User trace
    -- showed sun=20 vs thSun=47 at bidPos 1 — passing on hands that
    -- should be considered. Reduced to +2/+1 — still adds the "wait
    -- and see" texture but stays within reachable range.
    if round == 1 and S.s.dealer then
        local d = S.s.dealer
        local order = { (d % 4) + 1, ((d + 1) % 4) + 1,
                        ((d + 2) % 4) + 1, d }
        local bidPos = 0
        for i, st in ipairs(order) do
            if st == seat then bidPos = i; break end
        end
        if bidPos == 1 then
            thHokmR1 = thHokmR1 + 2
            thSun = thSun + 2
        elseif bidPos == 2 then
            thHokmR1 = thHokmR1 + 1
            thSun = thSun + 1
        end
    end

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

            -- v0.9.1 patch A-2 (audit AUDIT_REPORT_v0.7.1.md missing
            -- item #3 / decision-trees.md A-2). Ashkal allow-list per
            -- video #31: bid-up card must be small/mid (7, 8, 9, J,
            -- Q, or singleton-T). K is NOT on the allow list — blocks
            -- Ashkal at this rank. Pre-v0.9.1 the predicate only
            -- explicitly blocked A and T-with-A-cover; K could fire
            -- Ashkal when sun was in the 65-84 range, contradicting
            -- the doc's allow-list semantics.
            -- Sources: decision-trees.md A-2 (Common, video 31).
            if ok and bidCardRank == "K" then ok = false end

            -- v0.9.2 patch A-2 cardinality refinement (audit_v0.9.0/
            -- 60_a2_singleton_t.md). The doc allow-list says
            -- "singleton-T-without-A". v0.9.1 added the K-block but
            -- the T cardinality wasn't enforced: doubleton/tripleton-T
            -- (no own-A) slipped through. Reject if we hold a SECOND T
            -- anywhere — combined with A-4's own-A check below, this
            -- enforces "T accepted only when singleton AND no own-A".
            if ok and bidCardRank == "T" then
                local tCount = 0
                for _, c in ipairs(hand) do
                    if C.Rank(c) == "T" then tCount = tCount + 1 end
                end
                if tCount > 1 then ok = false end
            end

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

            -- v0.9.2 #60 reference: see the T-cardinality gate above
            -- (lines ~1361-1367). v0.11.5 Bot1-05/C-01 removed the
            -- byte-identical duplicate of that block that previously
            -- lived here; the single canonical block above enforces
            -- "singleton-T only" via the same `tCount > 1 → ok=false`
            -- check, so this site is now a no-op marker.
            -- Sources: decision-trees.md A-2 (Common, video 31).

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
        if sunMinShape(sunHand) and sun >= thSun then
            btrace("R1 direct Sun fires: sun=%d >= thSun=%d (sunMinShape=true)", sun, thSun)
            return K.BID_SUN
        end
        btrace("R1 direct Sun skipped: sunMinShape=%s sun=%d thSun=%d",
               tostring(sunMinShape(sunHand)), sun, thSun)

        -- Hokm-on-flipped only available if no prior Hokm/Sun.
        -- v0.5.8 patches B-1, B-4, B-6: gate on hokmMinShape (J of
        -- trump + count >= 3) — Saudi 3-card minimum, "no J = pass".
        -- Belote (K+Q of trump same suit) adds a +20 multiplier-immune
        -- bonus when the bid-up suit IS the Belote suit.
        -- Sources: decision-trees.md B-1 (Definite, 26), B-4 (Definite, 26), B-6 (Definite, 26).
        if not anyHokm and not anySun and bidCardSuit then
            -- v0.11.15 user-audit: include the bidcard in BOTH shape
            -- and strength evaluation for R1 Hokm-on-flipped. The
            -- bidder GETS the bidcard added to their final hand
            -- (HostDealRest in State.lua appends bidcard + 2 more
            -- deck cards to the bidder's hand, line ~1950). Pre-v0.11.15
            -- the bot evaluated only the 5-card pre-deal-2 hand,
            -- under-counting structurally guaranteed contributions:
            -- if bidcard is J of trump (the highest Hokm card), bidder
            -- post-win has the J automatically. Pre-fix, hokmMinShape
            -- on the 5-card hand without the J said "no J -> reject"
            -- (B-4 floor). Trace evidence from user-bidcalc:
            --   [9D 8H KC TC TH] bidcard would have made some Hokm
            --   shapes viable; [JC 7C TC JS 9H] hand had its own J
            --   but the threshold left margin for bidcard contribution.
            -- Including bidcard in strength shifts fire rates up
            -- slightly (avg bidcard contributes +6-8 strength when
            -- it's the trump suit). Threshold thHokmR1=42 unchanged
            -- — the small upshift aligns with user-audit goal of
            -- "more bot Hokm bidding". Tune empirically post-ship.
            -- v0.11.16-hotfix BC-INLINE: use the file-local withBidcard
            -- helper (same semantics as v0.11.15's inline construction;
            -- factored out so all bid pickers share one path).
            local hypHand = withBidcard(hand, S.s.bidCard)
            if hokmMinShape(hypHand, bidCardSuit) then
                local strength = suitStrengthAsTrump(hypHand, bidCardSuit)
                strength = strength + sideSuitAceBonus(hand, bidCardSuit)
                -- v0.5.13: B-6 +20 promoted to K.BOT_PICKBID_BELOTE_BONUS
                -- (which mirrors K.MELD_BELOTE so the bid bonus tracks
                -- the actual scoring bonus if either is ever retuned).
                if belote == bidCardSuit then
                    strength = strength + K.BOT_PICKBID_BELOTE_BONUS
                end
                btrace("R1 Hokm-on-flipped consider: suit=%s strength=%d thHokmR1=%d belote=%s",
                       bidCardSuit, strength, thHokmR1, tostring(belote == bidCardSuit))
                -- v0.11.19 BC-MANDATORY (post-v0.11.18 ultra-audit): if
                -- the trump suit holds a Belote pair (K+Q in same hand),
                -- decision-trees.md B-6 says "Mandatory Hokm with that
                -- suit as trump" — the +20 multiplier-immune Belote bonus
                -- is structural and shape-only. Bypass strength threshold
                -- when shape is Mandatory-Belote.
                --
                -- v1.0.9 A#2 tightening (swarm): bypass now requires
                -- structural support beyond the bare K+Q (canonical
                -- 100-meld OR K+Q+count>=3+sideAce). See
                -- `beloteBypassQualifies` for the exact gate. Pre-v1.0.9
                -- the bypass over-fired on K+Q+count==2 hands which
                -- routinely failed contracts; the +20 Belote bonus still
                -- contributes to `strength` so the standard threshold
                -- gate retains Belote awareness.
                if belote == bidCardSuit
                   and beloteBypassQualifies(hypHand, bidCardSuit) then
                    btrace("R1 Hokm fires (BC-MANDATORY Belote): %s strength=%d (Mandatory-Belote bypass)",
                           bidCardSuit, strength)
                    return K.BID_HOKM .. ":" .. bidCardSuit
                elseif belote == bidCardSuit then
                    btrace("R1 BC-MANDATORY Belote skipped: %s shape lacks 4-card trump-seq or K+Q+count>=3+sideAce",
                           bidCardSuit)
                end
                if strength >= thHokmR1 then
                    btrace("R1 Hokm fires: %s strength=%d >= thHokmR1=%d",
                           bidCardSuit, strength, thHokmR1)
                    return K.BID_HOKM .. ":" .. bidCardSuit
                end
            else
                btrace("R1 Hokm-on-flipped skipped: hokmMinShape(%s)=false",
                       tostring(bidCardSuit))
            end
        else
            btrace("R1 Hokm-on-flipped blocked: anyHokm=%s anySun=%s bidCardSuit=%s",
                   tostring(anyHokm), tostring(anySun), tostring(bidCardSuit))
        end
        btrace("R1 falls through to PASS")
        return K.BID_PASS
    end

    -- Round 2: pass / Hokm-non-flipped / Sun. Both rounds now wait
    -- for all 4 bids and Sun overcalls Hokm in either round.
    --
    -- v0.9.0 G-4 fix (audit AUDIT_REPORT_v0.7.1.md / video #29):
    -- partner-bid suppression. If partner has already bid Hokm this
    -- round, the bot must NOT outbid them with our own different-suit
    -- Hokm — Saudi convention says support partner's commitment, not
    -- compete with it. Sun overcall is still allowed (higher contract
    -- type, not partner-bid competition). Otherwise pass.
    -- Pre-v0.9.0 the bot would happily emit HOKM:<other-suit> outbid
    -- on partner's HOKM:<their-suit>; the host dropped it (winning
    -- already set), but the wire violation was visible.
    do
        local g4_partner = R.Partner(seat)
        local g4_partnerBid = S.s.bids and S.s.bids[g4_partner]
        local g4_partnerBidHokm = g4_partnerBid
            and g4_partnerBid:sub(1, #K.BID_HOKM) == K.BID_HOKM
        if g4_partnerBidHokm then
            -- Partner committed Hokm. Allow Sun overcall (different
            -- contract type, not a "competing Hokm" violation).
            if sunMinShape(sunHand) and sun >= thSun then
                return K.BID_SUN
            end
            -- v1.0.10 (audit pass-3 / partner-Hokm review HIGH):
            -- BC-MANDATORY Belote overrides G-4 partner-Hokm
            -- suppression. Two Definite-confidence Saudi rules
            -- conflict here: G-4 says "support partner's Hokm"
            -- (videos #29 + #34) and B-6 says "Mandatory Hokm with
            -- the Belote suit as trump" (video #26). The +20
            -- multiplier-immune Belote bonus + structural shape
            -- (canonical 4-card trump-seq OR K+Q+count>=3+sideAce)
            -- is too valuable to forfeit on partner-Hokm support
            -- — and the bidcard-suit Hokm we'd be overcalling is
            -- distinct from our Belote suit anyway. This is the
            -- ONLY HOKM-on-HOKM overcall the bot ever performs.
            -- Use the same beloteBypassQualifies gate as the R2
            -- BC-MANDATORY block below (line ~1980).
            do
                local hokmHand_g4 = withBidcard(hand, S.s.bidCard)
                local belote_g4 = beloteSuit(hokmHand_g4)
                if belote_g4
                   and belote_g4 ~= bidCardSuit
                   and hokmMinShape(hokmHand_g4, belote_g4)
                   and beloteBypassQualifies(hokmHand_g4, belote_g4) then
                    btrace("R2 BC-MANDATORY overrides G-4 partner-Hokm: HOKM:%s",
                           belote_g4)
                    return K.BID_HOKM .. ":" .. belote_g4
                end
            end
            return K.BID_PASS
        end
    end

    -- v0.5.8 patches B-1/B-4/B-6: only consider suits where the
    -- minimum-Hokm shape is met (J + count >= 3). Suits with no J,
    -- or fewer than 3 trumps, are skipped — Saudi rule, not heuristic.
    -- Belote suit (K+Q same suit) gets the +20 multiplier-immune bonus.
    -- Sources: decision-trees.md B-1, B-4 (Definite, video 26), B-6 (Definite, video 26).
    -- v0.11.16 audit BC-1: include bidcard in R2 Hokm evaluation. R2
    -- skips bidcard's suit as a candidate trump (line below: `suit ~=
    -- bidCardSuit`), so the bidcard becomes a non-trump card in the
    -- bidder's post-win hand. It contributes via sideSuitAceBonus
    -- (if it's an Ace) and via face value implicitly through the
    -- standard suitStrengthAsTrump pipeline. Pre-v0.11.16 missing.
    local hokmHand = withBidcard(hand, S.s.bidCard)
    local bestSuit, bestScore = nil, 0
    -- v0.11.19 BC-MANDATORY: track if Belote suit was found in any
    -- bestSuit candidate; bypass strength gate later if so (Saudi
    -- "Mandatory" rule per B-6).
    local beloteCandidate = nil
    for _, suit in ipairs(K.SUITS) do
        if suit ~= bidCardSuit and hokmMinShape(hokmHand, suit) then
            local s = suitStrengthAsTrump(hokmHand, suit)
            s = s + sideSuitAceBonus(hokmHand, suit)
            -- v0.5.13: +20 → K.BOT_PICKBID_BELOTE_BONUS (mirrors K.MELD_BELOTE).
            if belote == suit then s = s + K.BOT_PICKBID_BELOTE_BONUS end
            if s > bestScore then bestSuit, bestScore = suit, s end
            if belote == suit then beloteCandidate = suit end
        end
    end
    -- v0.5.8 patch B-5: 16-vs-26 failed-bid asymmetry. When BOTH Hokm
    -- and Sun are viable, prefer Hokm UNLESS Sun beats it by ≥ 5
    -- strength points. Failed Hokm = 16 raw, failed Sun = 26 raw —
    -- so the conservative default is Hokm. Sun must clearly justify
    -- the +10 raw downside swing.
    -- Sources: decision-trees.md B-5 (Definite, videos 25 + 26).
    -- Patch S-1 also gates Sun on minimum shape (mardoofa or 2+ Aces).
    if sunMinShape(sunHand) and sun >= thSun then
        local hokmViable = (bestSuit and bestScore >= thHokmR2)
        if not hokmViable then
            btrace("R2 Sun fires (Hokm not viable): sun=%d thSun=%d bestSuit=%s bestScore=%d",
                   sun, thSun, tostring(bestSuit), bestScore or 0)
            return K.BID_SUN
        end
        -- v0.5.13: B-5 +5 margin → K.BOT_BIDDING_SUN_OVER_HOKM_MARGIN.
        if sun >= bestScore + K.BOT_BIDDING_SUN_OVER_HOKM_MARGIN then
            btrace("R2 Sun fires (margin clears): sun=%d >= bestScore=%d + margin=%d",
                   sun, bestScore, K.BOT_BIDDING_SUN_OVER_HOKM_MARGIN)
            return K.BID_SUN
        end
        btrace("R2 Sun considered but blocked: sun=%d hokm-bestScore=%d margin-needed=%d (sun must >= %d)",
               sun, bestScore, K.BOT_BIDDING_SUN_OVER_HOKM_MARGIN,
               bestScore + K.BOT_BIDDING_SUN_OVER_HOKM_MARGIN)
        -- Otherwise: both viable, Sun's margin too thin → stay Hokm
        -- (falls through to Hokm return below).
    else
        btrace("R2 Sun skipped: sunMinShape=%s sun=%d thSun=%d",
               tostring(sunMinShape(sunHand)), sun, thSun)
    end
    -- v0.11.19 BC-MANDATORY: Mandatory-Belote bypass for R2 Hokm.
    -- If our Belote suit reached the bestSuit candidate set (passed
    -- shape gate) AND has structural support per `beloteBypassQualifies`
    -- (canonical 100-meld OR K+Q+count>=3+sideAce), fire Hokm-of-that-
    -- suit unconditionally — Saudi B-6 "Mandatory".
    --
    -- v1.0.9 A#2 tightening (swarm): pre-v1.0.9 fired on bare K+Q
    -- regardless of supporting shape; over-fired and routinely failed
    -- weak K+Q-only contracts. Tightening preserves Belote bonus in
    -- the strength score (so threshold gate still favors Belote
    -- candidates) but only auto-fires when truly Mandatory.
    if beloteCandidate
       and beloteBypassQualifies(hokmHand, beloteCandidate) then
        btrace("R2 Hokm fires (BC-MANDATORY Belote): %s bestScore=%d (Mandatory-Belote bypass)",
               beloteCandidate, bestScore)
        return K.BID_HOKM .. ":" .. beloteCandidate
    elseif beloteCandidate then
        btrace("R2 BC-MANDATORY Belote skipped: %s shape lacks 4-card trump-seq or K+Q+count>=3+sideAce",
               beloteCandidate)
    end
    if bestSuit and bestScore >= thHokmR2 then
        btrace("R2 Hokm fires: %s bestScore=%d >= thHokmR2=%d", bestSuit, bestScore, thHokmR2)
        return K.BID_HOKM .. ":" .. bestSuit
    end
    btrace("R2 falls through to PASS: bestSuit=%s bestScore=%d thHokmR2=%d",
           tostring(bestSuit), bestScore or 0, thHokmR2)
    return K.BID_PASS
end

-- ---------------------------------------------------------------------
-- Play
-- ---------------------------------------------------------------------

-- v1.1.0 (audit unpredictability HIGH-1): tie-break randomization.
-- Pre-v1.1.0 every "lowest/highest" pick used strict `<` / `>` so a
-- tie defaulted to hand-iteration order — a careful human reads
-- "if bot played 7♠ instead of 7♥ to discard, the 7♥ must be later
-- in their dealt hand" → the bot's choice broadcasts hand-order.
-- This helper picks RANDOMLY among cards tied for the chosen score.
local function pickRandomTied(tiedSet)
    if #tiedSet == 1 then return tiedSet[1] end
    return tiedSet[math.random(#tiedSet)]
end

local function lowestByRank(cards, contract)
    local bestR = math.huge
    for _, c in ipairs(cards) do
        local r = C.TrickRank(c, contract)
        if r < bestR then bestR = r end
    end
    local tied = {}
    for _, c in ipairs(cards) do
        if C.TrickRank(c, contract) == bestR then tied[#tied + 1] = c end
    end
    return pickRandomTied(tied)
end

local function highestByRank(cards, contract)
    local bestR = -1
    for _, c in ipairs(cards) do
        local r = C.TrickRank(c, contract)
        if r > bestR then bestR = r end
    end
    local tied = {}
    for _, c in ipairs(cards) do
        if C.TrickRank(c, contract) == bestR then tied[#tied + 1] = c end
    end
    return pickRandomTied(tied)
end

-- v0.5.1 C-4 helper: pick the highest-FACE-VALUE card from a list,
-- tie-broken by trick rank. Used for last-trick targeting where the
-- LAST_TRICK_BONUS (+10) plus the card's face value matters more
-- than its trick-rank (winning the last trick with a Ten = 10 face
-- + 10 bonus = 20 effective vs winning with a 7 = 0+10 = 10).
-- v1.1.0: randomize among final ties (rank+face both equal).
local function highestByFaceValue(cards, contract)
    local bestPts, bestRank = -1, -1
    for _, c in ipairs(cards) do
        local pts = C.PointValue(c, contract) or 0
        if pts > bestPts then
            bestPts, bestRank = pts, C.TrickRank(c, contract)
        elseif pts == bestPts then
            local r = C.TrickRank(c, contract)
            if r > bestRank then bestRank = r end
        end
    end
    local tied = {}
    for _, c in ipairs(cards) do
        local pts = C.PointValue(c, contract) or 0
        if pts == bestPts and C.TrickRank(c, contract) == bestRank then
            tied[#tied + 1] = c
        end
    end
    return pickRandomTied(tied)
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
    -- v0.10.2 M4: pass live `s.akaCalled` to R.IsLegalPlay so the
    -- AKA-receiver relief (J-066/J-067) is honored at the legality
    -- layer. Without this, must-trump-ruff fires even when partner
    -- has AKA'd, defeating AKA's primary purpose. Simulator callers
    -- (R.SunCanRolloff line 409) deliberately omit the param so
    -- rollouts get AKA-blind semantics.
    local aka = S and S.s and S.s.akaCalled or nil
    local out = {}
    for _, c in ipairs(hand) do
        local ok = R.IsLegalPlay(c, hand, trick, contract, seat, aka)
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
    -- v1.1.1 (M2 audit): filter out FORCED discards before
    -- classification. Per video #03 + #09 «do NOT Tahreeb the
    -- strong suit» — when bot was forced (only-non-led-non-trump
    -- suit available) the discard isn't a real signal and shouldn't
    -- corrupt the partner-side read. Build a virtual signals table
    -- from non-forced events. If the entire sequence was forced,
    -- treat as no-signal (return nil).
    if signals.forced then
        local filtered = {}
        for i, r in ipairs(signals) do
            if not signals.forced[i] then
                filtered[#filtered + 1] = r
            end
        end
        if #filtered == 0 then return nil end
        if #filtered ~= #signals then
            -- Replace with filtered view; preserve lenAtAce only if
            -- the first non-forced event matches the original first.
            filtered.lenAtAce = (filtered[1] == signals[1])
                                 and signals.lenAtAce or nil
            signals = filtered
        end
    end
    -- v0.9.0 Bargiya 2-flavor split (audit AUDIT_REPORT_v0.7.1.md
    -- missing item #9, Sources: video #14):
    --   • CONFIRMED invite: signals[1]=="A" AND ≥2 events with the
    --     second being lower-rank than A. Partner explicitly extended
    --     the discard pattern → strong "lead this back, I have cover".
    --   • AMBIGUOUS bargiya_hint: signals[1]=="A" AND #signals==1.
    --     Could be invite (cover-held) OR defensive-shed (singleton A,
    --     dumping for safety). Without follow-up, lower-confidence —
    --     callers may treat as "hint" rather than full lead-back.
    -- Pre-v0.9.0 conflated both as "bargiya", potentially wasting
    -- leads on defensive-shed cases.
    if signals[1] == "A" then
        -- v0.10.2 M7 — Bargiya canonical FN (review_v0.10.0
        -- xref X-prep / audit_v0.9.0/55_bargiya_axis_impact.md).
        -- محشور بلون واحد proxy: when sender held 5+ in this suit
        -- AT THE MOMENT of the Ace discard, video #14 rule 2 fires
        -- the early-Bargiya invite — no second event required. The
        -- recorder captures `lenAtAce` host-side from hostHands; if
        -- it's >= 5, the single-A signal is a confirmed invite. This
        -- closes the FN where genuine 5-card invites were demoted
        -- to bargiya_hint and beaten by ascending 2-event "want" in
        -- another suit. Falls back to the existing 2-event cover-
        -- grade gate when lenAtAce is missing (non-host clients,
        -- legacy fixtures with raw rank-string entries).
        if (signals.lenAtAce or 0) >= 5 then
            return "bargiya"        -- confirmed invite (محشور proxy)
        end
        if #signals >= 2 then
            -- v0.9.2 #55 cover-grade gate (audit_v0.9.0/55_bargiya_axis_impact.md).
            -- Require event #2 to be a COVER-GRADE rank (T or higher
            -- in the suit). The original "any second event" classifier
            -- escalated to confirmed-bargiya on courtesy/forced low
            -- discards (e.g., A then 8 of same suit when 8 was their
            -- last card). Cover-grade requires at least T because that
            -- proves real cover behind the A → invite is genuine.
            -- Lower second-event ranks fall back to bargiya_hint.
            local plain = K.RANK_PLAIN
            local r2 = plain[signals[2]] or 0
            local rT = plain["T"] or 0
            if r2 >= rT then
                return "bargiya"    -- confirmed invite (cover proven)
            end
        end
        return "bargiya_hint"       -- ambiguous (possible defensive shed)
    end
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

-- v1.2.0 (audit transcript H2): closed-trump under Bel/Four. Per
-- video #11 «الاعداد الزوجيه الدبل تضرب في اثنين والفور في اربعه
-- ... اللعب راح يكون مقفول». Under EVEN-multiplier Hokm rounds —
-- Bel-only (×2) or Four-only (×4) — trump-leading is FORBIDDEN
-- unless the player has only trump in hand. Triple (×3) and
-- Gahwa rounds play "open" with normal trump rules.
--
-- This is bot-only (we don't change Rules.lua legality so human
-- players retain their full freedom). When this gate matches, we
-- filter `legal` to non-trump cards before any pickLead heuristic
-- runs — none of the downstream branches will then choose trump.
-- If the only legal cards are trump, the gate is a no-op.
local function applyClosedTrumpLeadGate(legal, contract)
    if not contract or contract.type ~= K.BID_HOKM
       or not contract.trump then
        return legal
    end
    -- Closed-trump cases:
    --   1. Bel called, no Triple (×2 closed)
    --   2. Four called, no Gahwa (×4 closed)
    -- Triple-without-Four is OPEN play; Four-without-Gahwa is closed
    -- play; Gahwa is its own match-win regime.
    local isClosed = false
    if contract.doubled and not contract.tripled then
        isClosed = true
    elseif contract.foured and not contract.gahwa then
        isClosed = true
    end
    if not isClosed then return legal end
    local nonTrump = {}
    for _, c in ipairs(legal) do
        if not C.IsTrump(c, contract) then
            nonTrump[#nonTrump + 1] = c
        end
    end
    if #nonTrump == 0 then return legal end  -- only-trump → must lead trump
    return nonTrump
end

local function pickLead(legal, contract, seat)
    -- v1.2.0 (Tier 5 / transcript H2): closed-trump filter before
    -- any pickLead heuristic runs. Saudi rule per video #11.
    legal = applyClosedTrumpLeadGate(legal, contract)
    local myTeam = R.TeamOf(seat)
    -- v0.10.3 audit (B-Bot-* HIGH): pre-v0.10.3 this predicate
    -- gated on `contract.type == K.BID_HOKM`, making isBidderTeam
    -- always FALSE in Sun. Downstream branches that test
    -- `isBidderTeam` (sweep-pursuit-early at 1727, defender style
    -- reads at 1984/2248) silently bypassed all Sun contracts —
    -- including the explicit Sun-Kaboot pursuit branch citing
    -- K.AL_KABOOT_SUN=220 (×2=440) at lines 1723-1724. The check
    -- is purely about team relationship; type-gates are applied
    -- separately at each downstream use site (e.g. 1764, 2262).
    local isBidderTeam = (myTeam == R.TeamOf(contract.bidder))
    local isBidder = (seat == contract.bidder)

    -- v0.5.1 C-4: last-trick targeting at lead. On trick 8 there's no
    -- future trick to set up — lead our HIGHEST face-value winner if
    -- we hold a guaranteed boss (HighestUnplayedRank check) in any
    -- safe suit, OR fall through to highest-face-value otherwise.
    -- Sweep pursuit: if my team has won 7/7 tricks so far, also push
    -- aggressively (already-leading suggests we're going for AL_KABOOT).
    --
    -- v0.5.19 Section 7 rules 1+2 (Common, videos 06+07+15): extend
    -- the sweep-pursuit branch to fire from trick 3 onwards when:
    --   • Bidder's team has won EVERY prior trick (clean sweep so far).
    --   • We're the BIDDER team (defenders pursuing sweep is rarer).
    --   • trickNum is 3-7 (trick 8 already handled by the block below).
    -- Per video 15: "if no opp cut by trick 2, trump distribution is
    -- favorable; sweep is genuinely reachable. Earlier trigger lets
    -- tricks 3-7 be optimized for sweep." K.AL_KABOOT_HOKM=250,
    -- K.AL_KABOOT_SUN=220 (×2=440). Worth pursuing aggressively.
    local trickNum = #(S.s.tricks or {}) + 1
    local sweepPursuitEarly = false
    -- v1.0.3 (Cluster 4 defender sweep-pursuit): pre-fix the gate
    -- required `isBidderTeam`. But defenders sweeping every prior
    -- trick is the canonical Reverse Al-Kaboot setup (K.AL_KABOOT_
    -- REVERSE = 88 raw per Rules.lua:826-844 + video #16). When the
    -- bidder team is collapsing and our defender team has won every
    -- prior trick, pursuing the sweep is correct symmetric play.
    -- Saudi convention treats this as rarer but valid.
    if trickNum >= 3 and trickNum <= 7 then
        local mySwept = 0
        for _, t in ipairs(S.s.tricks or {}) do
            if R.TeamOf(t.winner) == myTeam then
                mySwept = mySwept + 1
            end
        end
        sweepPursuitEarly = (mySwept == trickNum - 1)
        -- v1.0.3 (U-7) Kaboot-feasibility hand-shape gate. Pre-fix
        -- the early-pursuit fired purely on "won every prior trick"
        -- — but a clean trick-3 sweep with a thin remaining hand
        -- (no high trump, no boss in hand) commits us to a sweep
        -- track that fails at trick 4-5, costing the high cards we
        -- spent + the missed Faranka/Kaboot risk premium. Per
        -- decision-trees.md Section 7 row "Kaboot pursuit feasibility
        -- check" (Definite, video 15): only pursue when we hold
        -- enough remaining-trick winners. Count: trump J/9/A in hand
        -- (each ≈1 guaranteed trick when trump pool isn't exhausted)
        -- + side-suit bosses (each ≈1 trick when opps trump-exhausted
        -- or void in suit). Need count >= (8 - trickNum + 1) to be
        -- feasible. M3lm-gated since the hand-shape introspection is
        -- a tournament-strategy nuance; lower tiers rely on the simple
        -- "won everything so far" trigger only.
        if sweepPursuitEarly and Bot.IsM3lm() and S.HighestUnplayedRank
           and contract.trump then
            local remainingNeeded = 8 - trickNum + 1
            local feasibleWinners = 0
            for _, c in ipairs(legal) do
                local r = C.Rank(c)
                local su = C.Suit(c)
                if su == contract.trump then
                    -- Trump J/9/A always count; lower trump counts
                    -- only if remaining trump pool indicates we
                    -- dominate (HighestUnplayedRank == this rank).
                    if r == "J" or r == "9" or r == "A" then
                        feasibleWinners = feasibleWinners + 1
                    elseif S.HighestUnplayedRank(contract.trump) == r then
                        feasibleWinners = feasibleWinners + 1
                    end
                else
                    -- Non-trump: count if it's the boss of its suit
                    -- (reflects "opp can't beat with same suit"; for
                    -- Hokm we additionally need opp trump-exhausted
                    -- which the existing trumpExhausted check covers
                    -- before fire — keep this estimate slightly
                    -- generous since false-positives just keep us in
                    -- the v0.5.19 default, not a worse path).
                    if S.HighestUnplayedRank(su) == r then
                        feasibleWinners = feasibleWinners + 1
                    end
                end
            end
            if feasibleWinners < remainingNeeded then
                sweepPursuitEarly = false
            end
        end
    end
    if trickNum == 8 or sweepPursuitEarly then
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

    -- v0.10.2 Pro-2 L08 — Sun bidder-team mardoofa probe lead on
    -- trick 1 (review_v0.10.0 xref_X4_pro2_deal.md MF-2 + REVIEW.md
    -- M8). Saudi pro mandate: when the Sun bidder (or partner) opens
    -- on trick 1 and holds an A+T mardoofa (إكة مردوفة), they MUST
    -- lead the Ace from that pair. Rationale: probe — "I have the
    -- backed slam in this suit; let's see who else has length."
    -- The T cover protects the A from being torn through later. This
    -- supersedes ALL downstream Sun fallthroughs (singleton-low,
    -- shortest-suit-low) — those were leading LOW cards which is
    -- exactly opposite of L08's HIGH probe. Pro-2 wording: "obligatory
    -- on him AND on his partner", so partner-when-on-lead is also
    -- bound. Tier-gate at Advanced+ (mardoofa is a structural strength
    -- concept already used in PickBid sunStrength bonus). Placed
    -- BEFORE the singleton/free-trick/free-low fallthroughs so it
    -- supersedes them — those branches were leading low cards which
    -- contradicts L08's HIGH-probe intent.
    if Bot.IsAdvanced() and contract.type == K.BID_SUN
       and trickNum == 1
       and contract.bidder
       and myTeam == R.TeamOf(contract.bidder) then
        local hasA = { S = false, H = false, D = false, C = false }
        local hasT = { S = false, H = false, D = false, C = false }
        local aceCard = { S = nil, H = nil, D = nil, C = nil }
        for _, c in ipairs(legal) do
            local r, su = C.Rank(c), C.Suit(c)
            if r == "A" then hasA[su] = true; aceCard[su] = c
            elseif r == "T" then hasT[su] = true end
        end
        for _, su in ipairs(shuffledSuits()) do
            if hasA[su] and hasT[su] and aceCard[su] then
                return aceCard[su]
            end
        end
    end

    -- Advanced (Tier 3 #11): if we hold a card that's currently the
    -- HIGHEST UNPLAYED in its non-trump suit, leading that card is
    -- a guaranteed trick. Reuses State.HighestUnplayedRank, which is
    -- maintained by ApplyPlay across all clients.
    -- v1.0.0 ultra-audit H2 follow-up: the original v1.0.0 boss-meld
    -- check was dead code. `S.HighestUnplayedRank` consults
    -- `playedCardsThisRound` only (State.lua:1640-1651) — meld cards are
    -- "unplayed" so any meld card higher than `c` already prevents
    -- HighestUnplayedRank == Rank(c) at the outer gate. The redundant
    -- meld-overbid scan never had a reachable input. Reverted to the
    -- pre-v1.0.0 simple-return form. The genuine meld-aware leverage
    -- lives in the trump-J/9 inference block below.
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
    local tahreebPrefFlavor = nil  -- v1.0.4 (agent #5): track flavor
    local tahreebPrefMahshour = false  -- v1.2.1 (J.4 fix): track
                                   -- of the chosen pref suit to gate
                                   -- the receiver phase-split below.
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
                local best, bestScore, bestFlavor = nil, 0, nil
                for _, su in ipairs(shuffledSuits()) do
                    -- Don't bias toward trump (leading trump has its
                    -- own dedicated logic below).
                    if su ~= contract.trump then
                        local cls = tahreebClassify(signals[su])
                        -- v0.9.0 Bargiya 2-flavor weights:
                        --   bargiya       (confirmed invite): 3
                        --   want                            : 2
                        --   bargiya_hint  (ambiguous, single A): 1
                        --     — lower than "want" so multi-event signals
                        --     dominate the single-Ace ambiguous case.
                        local score = (cls == "bargiya"      and 3)
                                   or (cls == "want"         and 2)
                                   or (cls == "bargiya_hint" and 1)
                                   or 0
                        if score > bestScore then
                            best, bestScore, bestFlavor = su, score, cls
                        end
                        if cls == "dontwant" then
                            tahreebAvoidSet[su] = true
                        end
                    end
                end
                if best then
                    tahreebPrefSuit = best
                    tahreebPrefFlavor = bestFlavor
                    -- v1.2.1 (J.4 fix): preserve مؤشور-proxy marker
                    -- on the chosen pref so the phase-split below
                    -- can skip "burn-tricks-first" advice when
                    -- sender was cornered (lenAtAce >= 5).
                    local chosenList = signals[best]
                    tahreebPrefMahshour = chosenList
                                          and (chosenList.lenAtAce or 0) >= 5
                end
            end
        end
        -- v0.5.14 Section 9 N-3 receiver: opp positive signals → avoid.
        -- Opp's "want"/"bargiya" indicates they want their partner to
        -- lead that suit; we deny them tempo by not leading it.
        --
        -- v0.9.3 #58 fix (audit_v0.9.0/58_tahreeb_desync.md): also
        -- include `bargiya_hint` (single-A event, ambiguous between
        -- invite and defensive shed). Pre-v0.9.3 the silent drop of
        -- bargiya_hint here meant a Saudi-tier opp's legitimate
        -- single-event Bargiya invite went undefended — partner-of-opp
        -- could lead-back without our deny-tempo response. Even though
        -- bargiya_hint is lower-confidence than full bargiya, marking
        -- it as avoid is the correct conservative defense.
        -- v1.1.1 (L2 audit): track opp-Bargiya suits in receiver
        -- memory so the must-ruff branch in pickFollow can prefer a
        -- HIGH ruff (boss-grade trump) to absolutely defeat opp's
        -- runner-back. Per video #19: opp Bargiya = suit-to-avoid
        -- (already wired below) PLUS ruff-X-if-possible trigger
        -- (NEW). Stored on `Bot._memory[seat].opponentBargiyaSuit`.
        if Bot._memory and Bot._memory[seat] then
            Bot._memory[seat].opponentBargiyaSuit =
                Bot._memory[seat].opponentBargiyaSuit
                or { S = false, H = false, D = false, C = false }
        end
        -- v1.2.0 (Tier 5 / video #19 6-factor confidence scoring):
        -- pre-v1.2.0 ALL opp signals (bargiya/want/bargiya_hint) were
        -- treated as binary avoid-suit. Per video #19 «عوامل مؤثره»
        -- there are 6 factors that scale confidence:
        --   1. Lateness in the round (later trick = stronger signal)
        --   2. Rank of discarded card (higher = stronger)
        --   3. Same-suit repetition (multi-event = stronger)
        --   4. Cross-opp redundancy (both opps signal same suit)
        --   5. Suit-switch cancellation (signal on suit X then Y
        --      partially cancels X — confidence drops)
        --   6. Bidder identity (sender-is-bidder = stronger weight)
        -- v1.2.0 implements 1-4 + 6; 5 (cancellation) requires
        -- per-event temporal ordering and is deferred. Confidence
        -- threshold = 4: at or above, the suit becomes avoidSet.
        -- Bargiya ALWAYS gets the special opponentBargiyaSuit flag
        -- (per L2 — Bargiya is a NAMED rule, not generic tanfeer).
        local oppSuitConfidence = { S = 0, H = 0, D = 0, C = 0 }
        for s = 1, 4 do
            if R.TeamOf(s) ~= R.TeamOf(seat) and Bot.IsBotSeat(s) then
                local oStyle = Bot._partnerStyle[s]
                local osignals = oStyle and oStyle.tahreebSent
                if osignals then
                    -- v1.5.0 (Tanfeer factor 5 — switch detection):
                    -- find the LATEST-signaled suit for this opp
                    -- (max firstTrickN). Opp's later-signaled suit
                    -- gets full weight; earlier suits get half weight
                    -- per video #19 §2.5 cancellation rule.
                    local opp_latestSuit, opp_latestTrickN = nil, -1
                    for _, su in ipairs({ "S", "H", "D", "C" }) do
                        local sig = osignals[su]
                        if sig and sig.firstTrickN
                           and sig.firstTrickN > opp_latestTrickN then
                            opp_latestSuit = su
                            opp_latestTrickN = sig.firstTrickN
                        end
                    end
                    for _, su in ipairs(shuffledSuits()) do
                        if su ~= contract.trump then
                            local cls = tahreebClassify(osignals[su])
                            local sigList = osignals[su]
                            if cls == "bargiya" or cls == "want"
                               or cls == "bargiya_hint" then
                                -- Base classify weight (factor 3 +
                                -- bargiya quality):
                                local w = (cls == "bargiya"      and 3)
                                       or (cls == "want"         and 2)
                                       or (cls == "bargiya_hint" and 1)
                                       or 0
                                -- Factor 2: rank of highest event
                                -- (A=3, T/K=2, others=1).
                                if sigList and #sigList > 0 then
                                    local plain = K.RANK_PLAIN or {}
                                    local maxR = 0
                                    for _, r in ipairs(sigList) do
                                        local rv = plain[r] or 0
                                        if rv > maxR then maxR = rv end
                                    end
                                    if maxR >= (plain["A"] or 8) then
                                        w = w + 2
                                    elseif maxR >= (plain["T"] or 7) then
                                        w = w + 1
                                    end
                                end
                                -- Factor 1: lateness (more cards
                                -- played = later in round = stronger).
                                local trickN = #(S.s.tricks or {})
                                if trickN >= 5 then w = w + 2
                                elseif trickN >= 3 then w = w + 1 end
                                -- Factor 6: bidder identity (sender
                                -- IS the bidder → stronger).
                                if contract.bidder == s then
                                    w = w + 1
                                end
                                -- v1.5.0 (Tanfeer factor 5 — switch
                                -- detection): if opp has signaled a
                                -- LATER suit (max firstTrickN > this
                                -- suit's firstTrickN), downgrade by
                                -- 50%. Per video #19 §2.5: "the newer
                                -- signal supersedes; opp's strength
                                -- has shifted to Y." Cancel-flag is
                                -- soft (multiply, not zero) since the
                                -- old suit may still hold mid-rank
                                -- value even if not the strongest.
                                if opp_latestSuit and opp_latestSuit ~= su
                                   and sigList and sigList.firstTrickN
                                   and opp_latestTrickN > sigList.firstTrickN then
                                    w = math.floor(w * 0.5)
                                end
                                oppSuitConfidence[su] =
                                    oppSuitConfidence[su] + w
                                -- L2 Bargiya special-case override
                                -- preserved (still flag the memory
                                -- regardless of confidence score).
                                if cls == "bargiya"
                                   and Bot._memory[seat]
                                   and Bot._memory[seat].opponentBargiyaSuit then
                                    Bot._memory[seat].opponentBargiyaSuit[su] = true
                                end
                            end
                        end
                    end
                end
            end
        end
        -- Factor 4: cross-opp redundancy already accumulates (both
        -- opps' weights sum into oppSuitConfidence[su]).
        -- Apply confidence threshold: only mark avoid when summed
        -- weight ≥ 4. Bargiya base (3) + 1 lateness or 1 bidder hits
        -- the threshold; bargiya_hint (1) needs stacking from rank
        -- + lateness + cross-opp to reach 4 — appropriately stricter.
        for su, w in pairs(oppSuitConfidence) do
            if w >= 4 then
                tahreebAvoidSet[su] = true
            end
        end
        -- v1.2.1 (G5 audit): export to Bot._memory[seat].oppHighInferred
        -- so downstream consumers (A1's deceptiveOverplay, BotMaster
        -- sampler) can bias on the inferred opp-holds-high reading.
        -- Per video #19 «اي شكل خصمك ينفر تفترض انه عنده» — opp
        -- Tanfeer is "infer opp holds the high cards in suit". Setting
        -- the per-suit memory flag at confidence ≥ 4 (same threshold
        -- as the avoid-set) gives consumers a uniform read.
        if Bot._memory and Bot._memory[seat] then
            Bot._memory[seat].oppHighInferred =
                Bot._memory[seat].oppHighInferred
                or { S = false, H = false, D = false, C = false }
            for su, w in pairs(oppSuitConfidence) do
                if w >= 4 then
                    Bot._memory[seat].oppHighInferred[su] = true
                end
            end
        end
        -- Conflict resolution: if partner pref-suit is in opp-avoid
        -- set, drop the pref. Denying opp dominates helping partner
        -- when both signals point at the same suit (rare).
        if tahreebPrefSuit and tahreebAvoidSet[tahreebPrefSuit] then
            tahreebPrefSuit = nil
        end
        -- v1.0.4 (agent #5): Bargiya receiver phase-split. Per
        -- signals.md §3 (canonical): receiver of a confirmed bargiya
        -- with ≥5 cards remaining (opening / mid-round) should burn
        -- 1-2 of own tricks first to set up the eventual lead-back —
        -- not surrender initiative immediately. Endgame (≤4 cards)
        -- DOES lead the bargiya'd suit immediately. Phase split:
        --   * confirmed bargiya + #hand >= 5 → downgrade to "consider,
        --     not mandate". We drop the pref so the standard low-from-
        --     longest path runs; bargiya may still win on the next
        --     trick when fewer cards remain.
        --   * bargiya_hint / want / endgame → keep the pref (low-conf
        --     hint AND endgame both want the immediate lead-back).
        if tahreebPrefSuit and tahreebPrefFlavor == "bargiya" then
            local handSize = #legal  -- pickLead's `legal` is the full
                                     -- hand (no must-follow constraint)
            -- v1.2.1 (J.4 audit fix): محشور-proxy bargiya skips the
            -- phase-split. Sender held 5+ cards in the suit at A-
            -- discard time → they cornered themselves and burned the
            -- A immediately. The "burn 1-2 tricks first" advice is
            -- for ambiguous 2-event bargiya, NOT for cornered-A
            -- single-event sends. Receiver should lead-back NOW.
            if handSize >= 5 and not tahreebPrefMahshour then
                tahreebPrefSuit = nil
            end
        end
        -- v1.1.0 (audit partner-coord H3): if no Tahreeb pref but
        -- partner AKA'd a non-trump suit earlier, treat that suit
        -- as a "want" lead-back signal. Partner held the boss in
        -- that suit + canonically the next-down rank (touching
        -- honors); leading it back lets partner cash both. Only
        -- fires when partner's AKA boss is no longer the highest
        -- unplayed (i.e., it has fallen) — otherwise let partner
        -- run their own boss first.
        if not tahreebPrefSuit and Bot._memory then
            local mem = Bot._memory[seat]
            local pas = mem and mem.partnerAkaSuit
            if pas then
                -- v1.2.2 (P1-4 audit fix): hoist the 0.85 roll OUT of
                -- the suit loop. Pre-v1.2.2 each matching suit got
                -- its own roll → variable RNG consumption per
                -- pickLead (1-4 rolls) shifting downstream seed
                -- state. Single roll per pickLead invocation: either
                -- we lead-back this turn OR we delay; uniform RNG
                -- consumption across calls.
                local leadBackRoll = math.random()
                for _, su in ipairs(shuffledSuits()) do
                    if pas[su] and su ~= contract.trump then
                        -- Only lead-back once partner's boss has
                        -- fallen. HighestUnplayedRank tracks unplayed
                        -- rank per suit; if it's < A AND we don't
                        -- hold the boss ourselves, partner's boss
                        -- has been played.
                        local hi = S.HighestUnplayedRank
                                    and S.HighestUnplayedRank(su)
                        if hi and hi ~= "A" then
                            -- v1.2.1 (A4 audit): probabilistic
                            -- lead-back. ~85% probability — opp
                            -- who saw partner AKA + boss falling
                            -- can no longer bank "bot opens AKA
                            -- suit at trick N+1" with certainty.
                            if leadBackRoll < 0.85 then
                                tahreebPrefSuit = su
                                tahreebPrefFlavor = "want"
                                break
                            end
                        end
                    end
                end
            end
        end
    end
    if tahreebPrefSuit then
        -- v0.11.16 audit H-2: Tahreeb-return decision tree.
        -- Pre-v0.11.16 we always led the LOWEST card in the partner-
        -- preferred suit. Per signals.md Section 1 + decision-trees.md
        -- Section 8 receiver-side, that's correct ONLY for the
        -- "T+2+ tripled" and "3+ no-T" cases. The two T-priority cases
        -- demand a different lead:
        --   * Bare-T (singleton T in the pref suit) -> lead T
        --     immediately. Otherwise opps "tafranak" (duck) to capture
        --     our T later when we're forced to lead small.
        --   * Doubled-T (T + 1 cover, partner is NOT Sun bidder) ->
        --     lead the T. Leading the cover telegraphs the T to opps
        --     who duck low and capture later.
        --   * Doubled-T (T + 1 cover, partner IS Sun bidder) -> lead
        --     the cover. Sun-bidder partner has the A; we keep the T
        --     to follow partner's A and avoid forcing partner to
        --     overtake.
        --   * 3+ cards (with or without T) -> lead LOW (legacy).
        local fromPref = {}
        local hasT, tCard = false, nil
        local nonTpref = {}
        for _, c in ipairs(legal) do
            if C.Suit(c) == tahreebPrefSuit
               and not C.IsTrump(c, contract) then
                fromPref[#fromPref + 1] = c
                if C.Rank(c) == "T" then
                    hasT = true; tCard = c
                else
                    nonTpref[#nonTpref + 1] = c
                end
            end
        end
        if #fromPref > 0 then
            local count = #fromPref
            if hasT and count == 1 then
                -- Bare-T: lead immediately.
                return tCard
            elseif hasT and count == 2 then
                -- Doubled-T: branch on partner-is-Sun-bidder.
                local partner = R.Partner(seat)
                local partnerIsSunBidder = (contract and contract.bidder == partner
                                            and contract.type == K.BID_SUN)
                if partnerIsSunBidder then
                    -- Lead cover; keep T for partner's A.
                    return lowestByRank(nonTpref, contract)
                else
                    -- Lead T; otherwise opp tafranaks to capture later.
                    return tCard
                end
            elseif hasT and tahreebPrefFlavor == "want" then
                -- v1.1.0 (audit partner-coord H1): Tahreeb-receiver
                -- T-supply for count >= 3. Pre-fix this branch fell
                -- through to `lowestByRank` whenever count >= 3, even
                -- when partner emitted a CONFIRMED `want` (small→big)
                -- Tahreeb signal — which video #10 calls "100%
                -- reliable" («نسبه نجاحه كبيره اللي هي 100%»). The
                -- small-to-big sender is signalling no-T; receiver
                -- with T MUST lead it back to partner regardless of
                -- the count of cover. Restricted to "want" flavor
                -- (the canonical small→big confirmed signal); other
                -- Tahreeb flavors keep the legacy low-lead behavior.
                return tCard
            else
                -- 3+ cards OR no T (or count >= 3 without "want"
                -- flavor): lead low (legacy).
                return lowestByRank(fromPref, contract)
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
    -- Audit Tier 3 (H-12): Fzloky is a BOT-vs-BOT convention signal.
    -- A bot's first off-suit discard is a deliberate suit-preference
    -- communication; a HUMAN's first off-suit discard is just whatever
    -- card they shed (often a high card to dump weakness, often random).
    -- Reading a human's discard as a "lead this suit" signal misdirects
    -- the bot's lead priority for the rest of the round. Only honour
    -- the signal when the partner is also a bot.
    -- v1.0.3 (F7): firstDiscard vs Tahreeb conflict resolution.
    -- Both signals can fire on the same partner discard event: the
    -- Tahreeb sender records intentional suit signaling (Section 8
    -- T-1 Bargiya / want / refuse) while firstDiscard is a more
    -- general "first off-suit reveal". v0.11.18-final U-2 wrapped
    -- the Tahreeb sender's "want" arm in a Sun-only gate
    -- (decision-trees.md Section 8 is canonically Sun); in Hokm,
    -- only the firstDiscard signal fires and the Tahreeb sender
    -- doesn't pollute the ledger with bargiya/want emissions.
    -- Plus v1.0.3 (U-5) wrote the "trump-discard suppression" at
    -- the WRITER side so trump-ruff plays no longer become first
    -- Discard records. The conflict is therefore structurally
    -- resolved via two complementary gates — not behavior change
    -- here, just documenting the resolution path.
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

    -- v1.0.0 Cluster 1 (meld awareness): if PARTNER declared a sequence
    -- meld in suit X, partner has those cards — leading X wastes
    -- partner's tempo and may strand high cards. Avoid leading X
    -- (let partner cash their meld run). Sets fzlokyAvoidSuit if
    -- not already set.
    -- v1.0.0 ultra-audit H3 follow-up: filter to SEQUENCE melds only.
    -- The original v1.0.0 ship looped over all partner-meld cards
    -- including carrés, but a carré is "4 of a same RANK across
    -- suits" — the suit of any one carré card carries no "let
    -- partner cash this run" signal. Mirror the existing opp-meld
    -- avoid filter at line ~2434 (`m.kind:sub(1,3) == "seq"`).
    if Bot.IsAdvanced() and S.s.meldsByTeam then
        local partner = R.Partner(seat)
        local partnerTeam = R.TeamOf(partner)
        local meldsList = S.s.meldsByTeam[partnerTeam] or {}
        for _, m in ipairs(meldsList) do
            if m.declaredBy == partner and m.kind
               and m.kind:sub(1, 3) == "seq" and m.suit
               and m.suit ~= (contract.trump or "")
               and not fzlokyAvoidSuit then
                fzlokyAvoidSuit = m.suit
                break
            end
        end
    end

    -- v1.0.0 Cluster 2 F3 (defender play): topTouchSignal READ-side.
    -- M3lm+ writes the "partner played K under our A → partner has Q+J"
    -- inference (Bot.lua:498-530) but no heuristic decision consumed
    -- it pre-v1.0.0. Now: if partner has a known down-touched honor
    -- in suit X (T-signal → has K, Q-signal → has J, K-signal → has
    -- Q+J), AVOID leading X so partner can cash their middle honor
    -- on their own lead. Layered after fzlokyAvoidSuit; first-set wins.
    --
    -- v1.0.0 ultra-audit H4 follow-up: also read `sig.cleared` (the
    -- K-signal payload — see writer rule 2 at line ~521). Original
    -- v1.0.0 ship only read `sig.nextDown`, which silently filtered
    -- out the K-signal case the CHANGELOG narrative emphasizes.
    if Bot.IsM3lm() and Bot._partnerStyle and not fzlokyAvoidSuit then
        local partner = R.Partner(seat)
        local pStyle = Bot._partnerStyle[partner]
        if pStyle and pStyle.topTouchSignal then
            for _, suit in ipairs(shuffledSuits()) do
                local sig = pStyle.topTouchSignal[suit]
                -- v1.2.1 (G3 audit fix): drop `sig.cleared` from the
                -- avoid-lead gate. Per video #05 «هل ممكن يكون عنده
                -- البنت ولا الولد لا مستحيل لو عنده كان لعبها بدال
                -- الشايب»: K-singleton (cleared = {Q,J}) means partner
                -- CANNOT continue the run — they have no middle honor
                -- left to lead back. So `cleared` is the OPPOSITE of
                -- a continue-signal; only `nextDown` (T-played → has K,
                -- Q-played → has J) actually marks "partner will lead
                -- this back." Treating `cleared` as a continue-signal
                -- was an inverted reading. Symmetric with the smother
                -- gate fix at line ~3941 in pickFollow.
                local hasSignal = sig and not sig.broke and sig.nextDown
                if hasSignal and suit ~= (contract.trump or "") then
                    fzlokyAvoidSuit = suit
                    break
                end
            end
        end
    end

    -- v0.7.1 B-97: opp-meld suit avoidance. When an opponent has
    -- declared a sequence meld (seq3/seq4/seq5) in suit X, that suit
    -- is THEIR run — leading X gives them tempo to cash their
    -- declared cards. AVOID leading X when an alternative exists.
    -- M3lm-gated since it relies on accumulated meld observations.
    -- Only fires for non-bidder defender leads (we're picking lead
    -- here = we won the prior trick = we're temporarily controlling
    -- the table; meld-suit avoidance is most useful in that context).
    -- Sources: bot_picker_gaps.md / wave8 B-97.
    if Bot.IsM3lm() and not isBidderTeam and S.s.meldsByTeam then
        local oppTeam = (R.TeamOf(seat) == "A") and "B" or "A"
        for _, m in ipairs(S.s.meldsByTeam[oppTeam] or {}) do
            -- Only sequence melds (seq3/seq4/seq5); carrés are
            -- 4-of-a-rank across suits and don't imply a suit-lead.
            if m.kind and m.kind:sub(1, 3) == "seq" and m.suit
               and m.suit ~= (contract.trump or "") then
                -- Only avoid if there's a non-meld-suit alternative;
                -- if all our non-trump cards are in the meld suit,
                -- we'd no-op the avoid anyway via the longest-suit
                -- fallback. The avoid is layered on top of any
                -- existing fzlokyAvoidSuit; if both apply (Fzloky
                -- and meld-suit collide), Fzloky wins (existing).
                if not fzlokyAvoidSuit then
                    fzlokyAvoidSuit = m.suit
                end
                break  -- only need one avoid hint
            end
        end
    end

    -- v0.8.2 Section 11 rule 8: bait-detected suit avoidance.
    -- An opp who played J in suit X with their partner already
    -- winning was performing Saudi deceptive overplay — they're
    -- baiting us to re-lead X assuming they're void below J. AVOID
    -- leading X. Layered on top of fzlokyAvoid / meld-suit avoid;
    -- earlier-set avoid wins (we don't override). M3lm-gated.
    -- Sources: decision-trees.md Section 11 rule 8 (Sometimes, 08).
    if Bot.IsM3lm() and Bot._partnerStyle then
        for s2 = 1, 4 do
            if R.TeamOf(s2) ~= R.TeamOf(seat) then
                local m = Bot._partnerStyle[s2]
                if m and m.baitedSuit then
                    for suit, count in pairs(m.baitedSuit) do
                        if count >= 1 and not fzlokyAvoidSuit
                           and suit ~= (contract.trump or "") then
                            fzlokyAvoidSuit = suit
                            break
                        end
                    end
                    if fzlokyAvoidSuit then break end
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
            for _, su in ipairs(shuffledSuits()) do
                if su ~= contract.trump then
                    -- Check if Ace of this suit has been played.
                    --
                    -- v1.3.3 (Suspect A audit fix — natural-mode
                    -- Advanced<Basic root cause): pre-fix this loop
                    -- ALSO checked whether the Ace was in our own
                    -- `legal` cards and marked it `seen` if so. That
                    -- made sideAcesLeft = 0 fire whenever we held the
                    -- only remaining Ace ourselves — a FALSE PREMISE
                    -- that the heuristic's intent ("all opponent Aces
                    -- are out, our K/Q/J are bosses") clearly didn't
                    -- support. The early-return then bypassed later
                    -- pickLead heuristics (partner-void ruff,
                    -- Belote-K+Q preservation, singleton-low,
                    -- Sun-shortest-suit). Empirical probe showed this
                    -- cost Advanced ~21-26 GP/game in natural mode
                    -- head-to-head against Basic, the bulk of the
                    -- pre-v1.3.3 Advanced<Basic anomaly. Now: only
                    -- PLAYED Aces count toward exhaustion. Our own
                    -- Ace is still in play and the inference must
                    -- not assume it's "out".
                    local aceCard = "A" .. su
                    local seen = false
                    for s2 = 1, 4 do
                        local m = Bot._memory[s2]
                        if m and m.played[aceCard] then seen = true; break end
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

        -- v0.6.1+ B-57/B-71: bidder-branch styleTrumpTempo read. When
        -- a DEFENDER on the opposing team has shown conservative trump
        -- tempo across prior rounds (styleTrumpTempo == -1: they hold
        -- high trump for over-ruff capture, NOT for early-tempo pull),
        -- straight trump-pull on this round is dangerous — they're
        -- waiting to over-ruff our pulled trump card. Saudi pro
        -- counter: cash side-suit Aces FIRST (defenders must follow if
        -- they have the suit, can't over-ruff a non-trump lead),
        -- forcing them to spend low cards in side suits. Then pull
        -- trump on a later trick when their non-trump holdings are
        -- depleted. M3lm-gated (style ledger requires accumulated
        -- prior-round signal), Hokm-only, Advanced trump-counting
        -- already established above.
        --
        -- Sources: bot_picker_gaps.md "styleTrumpTempo of opposing
        -- defender team" gap, MASTER_REPORT.md B-57/B-71.
        if Bot.IsM3lm() and contract.type == K.BID_HOKM
           and contract.trump and contract.bidder then
            -- v0.10.3 audit (B-Bot-08, HIGH): pre-v0.10.3 the loop body
            -- referenced an undefined `bidderTeam`, which Lua resolved
            -- to nil. `R.TeamOf(s2) ~= nil` is always true for valid
            -- seats, so the team-gate was a no-op — the conservativeOpp
            -- check accepted ANY seat (including bidder-team) with
            -- styleTrumpTempo == -1. Define bidderTeam locally; the
            -- outer `contract.bidder` non-nil gate makes R.TeamOf safe.
            local bidderTeam = R.TeamOf(contract.bidder)
            local conservativeOpp = false
            for s2 = 1, 4 do
                if R.TeamOf(s2) ~= bidderTeam
                   and styleTrumpTempo(s2) == -1 then
                    conservativeOpp = true
                    break
                end
            end
            if conservativeOpp then
                for _, c in ipairs(legal) do
                    if C.Rank(c) == "A" and not C.IsTrump(c, contract) then
                        return c
                    end
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
            -- v0.11.19 audit U-3: bidcard public-knowledge inference.
            -- The bidder receives the bidcard at HostDealRest; if the
            -- bidcard is the J or 9 of trump and bidder is observed to
            -- still hold it, treat that as "bidder has it" — so it's
            -- NOT consumed from the opp's collective trump pool from
            -- defenders' POV. For US (the seat reasoning), if WE are
            -- the defender, the bidder still having J/9 trump means
            -- opp trump strength is NOT exhausted; suppress the
            -- "switch to side-Ace cashing" branch. Pre-fix the trump-
            -- J/9 inference treated "card not played, not in our hand"
            -- as "could be in any opp hand" — but the bidcard is
            -- KNOWN to be in bidder's hand specifically.
            if contract.bidder and contract.bidder ~= seat
               and S.s.bidCard and bidderHoldsBidcard(contract.bidder, S.s.bidCard)
               and C.Suit(S.s.bidCard) == contract.trump then
                local bidcardRank = C.Rank(S.s.bidCard)
                if bidcardRank == "J" then
                    -- J of trump KNOWN to be in bidder's hand. Don't
                    -- treat trump-J as exhausted; bidder will play it.
                    trumpJSeen = false
                elseif bidcardRank == "9" then
                    trump9Seen = false
                end
            end
            -- v1.0.0 Cluster 1 (meld awareness) + ultra-audit H1 fix:
            -- factor declared meld cards. The original v1.0.0 ship had
            -- this block iterate OPP team and force trumpJSeen=false —
            -- but the default for unplayed-non-our-hand cards is ALREADY
            -- false (only `played` and `legal` populate `out`), so the
            -- override was a no-op. The genuinely missing case is the
            -- INVERSE: PARTNER team has J or 9 of trump in a declared
            -- meld → that card IS friendly-pool (NOT in opp pool) → mark
            -- as `out` so trumpJSeen / trump9Seen flips to true. Pre-
            -- v1.0.0 this was missed: even though we knew partner held
            -- the killer, the inference treated it as "could be in opp
            -- hand" and didn't switch to side-Ace cashing.
            for s2 = 1, 4 do
                if R.TeamOf(s2) == R.TeamOf(seat) and s2 ~= seat then
                    local known = meldKnownHeld(s2)
                    for card in pairs(known) do
                        if C.Suit(card) == contract.trump then
                            if C.Rank(card) == "J" then trumpJSeen = true
                            elseif C.Rank(card) == "9" then trump9Seen = true end
                        end
                    end
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

    -- v1.0.3 (F8): Sun-bidder-drought tell — mirror of bidderTrump
    -- Drought for Sun contracts. Sun has no trump, but bidders
    -- typically lead Aces when they hold them (tempo). After 3
    -- tricks, if the bidder has LED at least once and NEVER led
    -- an Ace, they're Ace-poor (didn't have the canonical
    -- 2-Ace+ Sun shape, or have spent them already off-lead). As
    -- defenders we should aggressively cash our own high-point
    -- side-suit cards. M3lm-gated; Sun-only mirror.
    local bidderSunDrought = false
    if Bot.IsM3lm() and contract.type == K.BID_SUN and not isBidderTeam
       and S.s.tricks and #S.s.tricks >= 3 and contract.bidder then
        local bidderLeadCount, bidderAceLeadCount = 0, 0
        for _, t in ipairs(S.s.tricks) do
            if t.plays and t.plays[1] and t.plays[1].seat == contract.bidder then
                bidderLeadCount = bidderLeadCount + 1
                if C.Rank(t.plays[1].card) == "A" then
                    bidderAceLeadCount = bidderAceLeadCount + 1
                end
            end
        end
        if bidderLeadCount >= 1 and bidderAceLeadCount == 0 then
            bidderSunDrought = true
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
    -- v1.0.3 (F8): same path also fires on Sun-bidder-drought.
    -- Sun has no trump so the "bidder can't ruff" logic applies
    -- trivially; Ace-led tells us bidder is Ace-poor specifically,
    -- which is the Sun-equivalent of the trump-poor signal. The
    -- action is the same — cash our highest point card before
    -- bidder finds something to capture with their remaining honors.
    if bidderTrumpDrought or bidderSunDrought then
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

    -- v1.0.0 Cluster 2 F4 (defender play): partner-void-suit ruff
    -- setup. When partner is OBSERVED void in a non-trump suit X,
    -- leading our LOW card from X gives partner a free ruff (they
    -- can't follow → trump). 1-2 partner ruffs per round can be
    -- the difference between failing or making bidder. Helper:
    -- partner-void check from Bot._memory.void.
    -- Skip if we hold the boss (covered by single-opp-void branch
    -- above) or if partner is the bidder (partner ruffing partner's
    -- own contract is wasteful — they want to PULL trump, not ruff).
    if Bot.IsAdvanced() and contract.type == K.BID_HOKM
       and Bot._memory then
        local partner = R.Partner(seat)
        local pmem = Bot._memory[partner]
        local partnerIsBidder = (contract.bidder == partner)
        if pmem and pmem.void and not partnerIsBidder then
            for _, c in ipairs(nonTrumps) do
                local su = C.Suit(c)
                if su ~= contract.trump and pmem.void[su] then
                    -- Lead our LOWEST card in the partner-void suit
                    -- to preserve our higher cards; partner ruffs.
                    local lows = {}
                    for _, c2 in ipairs(nonTrumps) do
                        if C.Suit(c2) == su then
                            lows[#lows + 1] = c2
                        end
                    end
                    if #lows > 0 then
                        return lowestByRank(lows, contract)
                    end
                end
            end
        end
    end

    -- 2: singleton low? Pick the lowest singleton if we have any.
    --
    -- v0.6.0 H-3 fix: rank-guard the singleton-lead branch. The
    -- audit's concern: leading a singleton Ace/T/K/Q in Hokm wastes
    -- the honor — opponents void in that suit can over-ruff (no
    -- protection from our hand). The "ruffing entry" rationale
    -- (lead low, dump it, partner can lead the suit back later for
    -- us to ruff) only applies to genuinely low cards. In Sun,
    -- A/T are sure stoppers (no trump exists) so the rank-guard
    -- only fires in Hokm. Filter singletons to face-rank 7/8/9
    -- in Hokm; if all our singletons are honors, fall through to
    -- the longest-suit-low lead instead of dumping a winner.
    local singletons = {}
    for _, c in ipairs(nonTrumps) do
        if suitCount[C.Suit(c)] == 1 then singletons[#singletons + 1] = c end
    end
    if #singletons > 0 then
        local ledger = singletons
        if contract.type == K.BID_HOKM then
            local lowSingletons = {}
            for _, c in ipairs(singletons) do
                local r = C.Rank(c)
                if r == "7" or r == "8" or r == "9" then
                    lowSingletons[#lowSingletons + 1] = c
                end
            end
            ledger = lowSingletons
        end
        if #ledger > 0 then
            return lowestByRank(ledger, contract)
        end
        -- Fall through: all singletons are honors in Hokm — preserve
        -- them and lead from longest non-trump suit instead.
    end

    -- v1.2.1 (G1 audit): weakHandSignal-aware lead bias. Per video
    -- #20 «اذا انت عندك قوه ... تحاول تمسك اللعب ضعيف ممكن تخلي
    -- قويه يمسك اللعب» — strong hand grabs tempo, weak hand defers.
    -- The complementary read on PARTNER's tempo: when partner has
    -- shown a WEAK hand pattern (more low-card plays under partner-
    -- winning observation than high-card plays, ≥3 events), we
    -- should lead from OUR strongest suit (take initiative away
    -- from the weak partner) rather than defer to partner's run.
    -- Sets `forceOwnInitiative` flag consumed by Sun shortest-suit
    -- (skip) and by longest-suit logic (prefer suits where we hold
    -- A or T). M3lm-gated.
    local forceOwnInitiative = false
    if Bot.IsM3lm and Bot.IsM3lm() and Bot._partnerStyle then
        local pStyle = Bot._partnerStyle[R.Partner(seat)]
        if pStyle and pStyle.weakHandSignal and pStyle.highCardPlays then
            local total = pStyle.weakHandSignal + pStyle.highCardPlays
            if total >= 3
               and pStyle.weakHandSignal > pStyle.highCardPlays * 2 then
                forceOwnInitiative = true
            end
        end
    end

    -- v1.4.3: Sun establishing «مسك اللون» + round-end T deferral.
    -- Sources: video #20 (control_game), video #6 (faranka_in_sun),
    -- video #9 (most_essential_tahreeb).
    --
    -- Establishing rule: when holding the top live card (A or T)
    -- of a non-trump suit AND ≥3 cards in that suit, LEAD that
    -- suit. Opponents' mid-cards fall naturally on follow-ups;
    -- K/J become bosses after 1-2 cycles. Wins over Sun shortest-
    -- suit (H-7 default) when bot has true boss-and-long shape.
    -- Composes with v1.3.1 forceOwnInitiative (which prefers A/T
    -- suits when partner shows weak) — fires only when
    -- forceOwnInitiative didn't already decide.
    --
    -- Round-end T deferral (video #9 «احتفظ فيها وخليها للأخير»):
    -- skip establishing on T-boss suit when partner has 0 tricks
    -- AND trick ≤ 5. T is worth more at round-end (last-trick
    -- bonus + face-value compounds). A-boss not deferred (no
    -- last-trick bonus value to preserve).
    --
    -- M3lm+ gated.
    if contract.type == K.BID_SUN and not forceOwnInitiative
       and Bot.IsM3lm and Bot.IsM3lm() then
        local count = { S = 0, H = 0, D = 0, C = 0 }
        for _, c in ipairs(legal) do
            count[C.Suit(c)] = count[C.Suit(c)] + 1
        end
        -- Compute round-end-deferral predicate once (used per-suit).
        --
        -- v1.4.8 (audit HIGH-2 fix): pre-fix this fired on
        -- (partner has 0 captures) AND (trick ≤ 5) — too broad.
        -- User reported: "bots saving big cards for last trick,
        -- losing control over rounds, scoring less or losing
        -- contract." Video #9 «احتفظ فيها وخليها للأخير» («save
        -- it for the end») applies to a DEFENDED team comfortable
        -- with their lead — not a struggling bidder. Two changes:
        --   1. Tightened trick gate: was ≤ 5, now ≤ 3. After
        --      trick 3 the landscape is clear enough to establish.
        --   2. Added underContractPressure bypass: if bot is on
        --      bidder team and current raw is < target - 30, skip
        --      the deferral entirely. Take the T-boss now —
        --      contract failure is the bigger risk than burning
        --      the round-end T.
        local partner = R.Partner(seat)
        local partnerWonAny = false
        local trickCount = #(S.s.tricks or {})
        for _, t in ipairs(S.s.tricks or {}) do
            if t.winner == partner then partnerWonAny = true; break end
        end
        local underContractPressure = false
        if contract.bidder and S.s.tricks and trickCount >= 4 then
            local myTeam = R.TeamOf(seat)
            local isBidderTeam = (R.TeamOf(contract.bidder) == myTeam)
            if isBidderTeam then
                local raw = 0
                for _, t in ipairs(S.s.tricks) do
                    if R.TeamOf(t.winner) == myTeam then
                        for _, p in ipairs(t.plays or {}) do
                            raw = raw + (C.PointValue(p.card, contract) or 0)
                        end
                    end
                end
                local baseTarget = (contract.type == K.BID_SUN) and 65 or 81
                underContractPressure = (raw < baseTarget - 30)
            end
        end
        local roundEndDeferActive = (not partnerWonAny)
                                     and trickCount <= 3
                                     and not underContractPressure
        -- Find a suit where: (a) we have ≥3 cards, (b) we hold the
        -- highest LIVE card (top unplayed), and (c) that highest is
        -- A or T (a real "boss" — leading K alone is too weak).
        local plainOrder = { "A", "T", "K", "Q", "J", "9", "8", "7" }
        for _, suit in ipairs(shuffledSuits()) do
            if count[suit] >= 3 then
                -- Walk plain order: first unplayed rank IS the live boss
                local liveBoss = nil
                if S.s.playedCardsThisRound then
                    for _, r in ipairs(plainOrder) do
                        if not S.s.playedCardsThisRound[r .. suit] then
                            liveBoss = r; break
                        end
                    end
                end
                -- Check we hold the live boss
                local weHoldBoss = false
                if liveBoss == "A" or liveBoss == "T" then
                    for _, c in ipairs(legal) do
                        if C.Suit(c) == suit and C.Rank(c) == liveBoss then
                            weHoldBoss = true; break
                        end
                    end
                end
                -- Round-end deferral: skip establishing on a T-boss
                -- suit when partner hasn't won yet + early/mid round.
                -- Establishing on A-boss is fine (A doesn't carry the
                -- 10-point round-end value that justifies preservation).
                local deferThisSuit = (roundEndDeferActive
                                       and liveBoss == "T")
                if weHoldBoss and not deferThisSuit then
                    -- Lead the boss (highest rank we hold in this suit
                    -- by trick rank). For Sun's plain ordering, A > T.
                    local lead = nil
                    local bestRank = -1
                    for _, c in ipairs(legal) do
                        if C.Suit(c) == suit then
                            local cr = C.TrickRank(c, contract)
                            if cr > bestRank then
                                lead = c; bestRank = cr
                            end
                        end
                    end
                    if lead then return lead end
                end
            end
        end
    end

    -- v1.4.3 (audit follow-up — adjacent-to-T anti-rule, video #2).
    -- «خطأ أنك تروح بالورقة اللي جنب العشرة لو كانت العشرة مردوفة»
    -- (it's wrong to lead the card adjacent to T when T is doubled).
    -- Leading 9 from a T+9 doubleton telegraphs to opps that we hold
    -- T (the conventional inference: bots/pros don't lead the LOW of
    -- a doubleton without specific reason, so leading 9 implies the
    -- suit-mate is higher). Detect this shape and avoid it in
    -- subsequent suit-selection (shortest-suit, longest-low). M3lm+
    -- gated (sophisticated read).
    local tPlusNineDoubletonSuit = nil
    if Bot.IsM3lm and Bot.IsM3lm() then
        local suitCountForT9 = { S = 0, H = 0, D = 0, C = 0 }
        local hasT9 = { S = { t = false, n = false },
                        H = { t = false, n = false },
                        D = { t = false, n = false },
                        C = { t = false, n = false } }
        for _, c in ipairs(legal) do
            if not C.IsTrump(c, contract) then
                local r, s = C.Rank(c), C.Suit(c)
                suitCountForT9[s] = suitCountForT9[s] + 1
                if r == "T" then hasT9[s].t = true end
                if r == "9" then hasT9[s].n = true end
            end
        end
        for _, suit in ipairs({ "S", "H", "D", "C" }) do
            if suitCountForT9[suit] == 2
               and hasT9[suit].t and hasT9[suit].n then
                tPlusNineDoubletonSuit = suit
                break
            end
        end
    end

    -- v0.5 H-7: Sun shortest-suit lead. Saudi pro convention is to
    -- lead from the shortest non-trump suit in Sun (forcing opponents
    -- to play their boss in that suit early; once spent, our lower
    -- cards in that suit become winners). Bot previously fell through
    -- to "low from longest" for both Hokm defenders AND Sun bidders —
    -- the longest-suit lead is right for Hokm defenders (preserve
    -- high cards for capture, give partner room) but wrong for Sun
    -- (Sun has no trump shield; long-suit cards get over-trumped).
    if contract.type == K.BID_SUN and not forceOwnInitiative then
        -- v1.2.0 (Tier 5 Sun-partner-support): video #02 «خويك مشتري
        -- صن» distinguishes Sun-bidder-self vs Sun-bidder-partner.
        -- Sun-bidder partner should preferentially lead from suits
        -- where they have a SPARE LOW (not the high-card suit) —
        -- clearing those suits lets partner's Aces dominate later.
        -- Specifically: avoid leading from a suit where we hold a
        -- bare A or A+T (those are partner's runner suits — our
        -- A could collide with partner's A; better to lead from
        -- "no-A short suit" first to clear it for partner's run).
        local partnerIsSunBidder = (contract.bidder
                                     and contract.bidder == R.Partner(seat))
        local count = { S = 0, H = 0, D = 0, C = 0 }
        local hasA = { S = false, H = false, D = false, C = false }
        for _, c in ipairs(legal) do
            count[C.Suit(c)] = count[C.Suit(c)] + 1
            if C.Rank(c) == "A" then hasA[C.Suit(c)] = true end
        end
        -- v1.4.3 anti-T+9-doubleton: skip the T+9 doubleton suit
        -- in shortest-suit selection if alternatives exist (avoids
        -- the "lead 9 from T+9 telegraphs T" leak). Falls through
        -- gracefully — if T+9 IS the only valid shortest, the
        -- selection re-runs without the exclusion.
        local shortestSuit, shortestN = nil, 99
        local shortestNonAceSuit, shortestNonAceN = nil, 99
        for _, suit in ipairs(shuffledSuits()) do
            local n = count[suit] or 0
            if n > 0 and n < shortestN
               and suit ~= tPlusNineDoubletonSuit then
                shortestSuit, shortestN = suit, n
            end
            if n > 0 and not hasA[suit] and n < shortestNonAceN
               and suit ~= tPlusNineDoubletonSuit then
                shortestNonAceSuit, shortestNonAceN = suit, n
            end
        end
        -- Fallback: if anti-T+9 exclusion left no candidate (T+9
        -- was the only suit), re-run without exclusion.
        if not shortestSuit then
            for _, suit in ipairs(shuffledSuits()) do
                local n = count[suit] or 0
                if n > 0 and n < shortestN then
                    shortestSuit, shortestN = suit, n
                end
                if n > 0 and not hasA[suit] and n < shortestNonAceN then
                    shortestNonAceSuit, shortestNonAceN = suit, n
                end
            end
        end
        -- Sun-bidder-partner: prefer the shortest non-Ace-holding
        -- suit (keeps our Aces concentrated for partner's later
        -- run-back support). Falls back to plain shortest if every
        -- suit holds an Ace (rare).
        local pickSuit = (partnerIsSunBidder and shortestNonAceSuit)
                          or shortestSuit
        if pickSuit then
            local fromShortest = {}
            for _, c in ipairs(legal) do
                if C.Suit(c) == pickSuit then
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
    --
    -- v1.3.1 (deadSignal-1 audit fix): forceOwnInitiative second
    -- consumer. The v1.2.1 G1 write-site comment at Bot.lua:3632-3634
    -- promised the flag is consumed «by Sun shortest-suit (skip) AND
    -- by longest-suit logic (prefer suits where we hold A or T)».
    -- The Sun-skip half lands at line 3655, but the longest-suit A/T
    -- preference was never wired — `longest` was picked purely by
    -- `suitCount`. Now: when forceOwnInitiative is set (partner shows
    -- weak hand), score suits as `count*10 + has_A*5 + has_T*3` so a
    -- 4-card-with-A beats a 5-card-no-honors. Same Fzloky avoid-suit
    -- gating; mardoofa-aware via the additive A+T bonus.
    if #nonTrumps > 0 then
        local hasA, hasT = {}, {}
        for _, c in ipairs(nonTrumps) do
            local r, s = C.Rank(c), C.Suit(c)
            if r == "A" then hasA[s] = true end
            if r == "T" then hasT[s] = true end
        end
        local function suitScore(suit)
            local n = suitCount[suit] or 0
            if n == 0 then return 0 end
            if forceOwnInitiative then
                local bonus = (hasA[suit] and 5 or 0) + (hasT[suit] and 3 or 0)
                return n * 10 + bonus
            end
            return n * 10
        end
        -- Two-pass selection avoids the iteration-order bug where
        -- pairs(suitCount) might visit the avoid-suit first and let
        -- it claim `longest` before any alternative is considered.
        -- Pass 1: best NON-avoid suit. Pass 2: any best if pass
        -- 1 found nothing. The Fzloky "≥2 more cards" tolerance is
        -- now applied as a tie-break — avoid-suit only wins if it
        -- exceeds the best non-avoid by ≥2 in raw count (independent
        -- of A/T bonus to preserve the original Fzloky semantics).
        local longest, longestN, longestScore = nil, 0, 0
        for _, suit in ipairs(shuffledSuits()) do
            local n = suitCount[suit] or 0
            local score = suitScore(suit)
            if suit ~= fzlokyAvoidSuit and score > longestScore then
                longest, longestN, longestScore = suit, n, score
            end
        end
        if fzlokyAvoidSuit then
            local avoidN = suitCount[fzlokyAvoidSuit] or 0
            if avoidN >= longestN + 2 then
                longest = fzlokyAvoidSuit
                longestN = avoidN
                longestScore = suitScore(fzlokyAvoidSuit)
            end
        end
        if not longest then
            -- Avoid-suit was our only non-trump. Use it.
            for _, suit in ipairs(shuffledSuits()) do
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
    --
    -- v1.0.3 (F5): Belote-K+Q-of-trump preservation for defender
    -- pickLead. When forced to lead trump (no non-trump), and we
    -- still hold BOTH K and Q of trump (Belote pair), prefer trump
    -- that is NOT K or Q so the K-Q pair cashes together later.
    -- Belote scoring is locked at meld declaration, but the +20
    -- bonus is collected at the SAME PHYSICAL TRICK only if K and
    -- Q go down together (Saudi convention). Splitting the pair
    -- via a forced K-lead, only to land Q in a different trick,
    -- collects the bonus but loses the "pair-cashes-on-our-lead"
    -- attack pattern. Layered AFTER saveHighTrump so the J/9 save
    -- still wins; only kicks in for "below-J/9" decisions.
    if saveHighTrump then
        local lowTrump = {}
        for _, c in ipairs(legal) do
            local r = C.Rank(c)
            if r ~= "J" and r ~= "9" then
                lowTrump[#lowTrump + 1] = c
            end
        end
        if #lowTrump > 0 then
            -- F5 sub-filter: among non-J/9 trump, prefer non-K/Q
            -- when we hold the Belote pair. holdsBeloteThusFar checks
            -- the FULL hand (already pre-bidcard-merged in pickLead's
            -- caller path, see Bot.lua:1453 belote detection).
            if holdsBeloteThusFar and holdsBeloteThusFar(legal, contract) then
                local notKQ = {}
                for _, c in ipairs(lowTrump) do
                    local r = C.Rank(c)
                    if r ~= "K" and r ~= "Q" then
                        notKQ[#notKQ + 1] = c
                    end
                end
                if #notKQ > 0 then
                    return lowestByRank(notKQ, contract)
                end
            end
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

-- v1.5.0 (audit follow-up — predictTrickWinner helper).
-- Sources: videos #21/22/23 (Takbeer/Tasgheer certainty triage).
-- The Takbeer/Tasgheer rules require knowing WHO will take this
-- trick before deciding to magnify (for partner) or miniaturize
-- (for opp). Existing pickFollow branches embed certainty logic
-- inline (v1.4.1 pos-3 partner-Takbeer reads pos-4 void; v1.4.8
-- HIGH-3 pos-3 hold-back checks pos4CannotBeat). This helper
-- centralizes the certainty computation.
--
-- Returns: (winnerSeat, confidence) where confidence is one of:
--   "certain"    — given known voids + remaining unplayed cards,
--                  the predicted winner is mathematically locked
--   "likely"     — high probability based on memory but not locked
--   "uncertain"  — too many unknowns; default behaviors apply
--
-- v1.5.0 scope: ADDITIVE only — defined as a building block for
-- future Takbeer/Tasgheer expansions. Existing branches keep their
-- inline logic untouched (per user direction "keep and replace in
-- later release"). Called by NEW branches in v1.5.x+ as needed.
local function predictTrickWinner(trick, contract, seat, knownVoids)
    if not trick or not trick.plays or #trick.plays == 0 then
        return nil, "uncertain"
    end
    local curWinner = R.CurrentTrickWinner(trick, contract)
    local pos = #trick.plays + 1
    -- Pos-4 (lastSeat): current winner is locked once we play.
    -- Caller's own play is added afterward; for prediction purposes
    -- here, the winner is whichever of {curWinner, our card} wins.
    -- For "certain partner / certain opp" classification at pos-4,
    -- check curWinner's team vs our team.
    if pos == 4 then
        return curWinner, "certain"
    end
    -- Pos-3 (we're third to play): can be certain when pos-4
    -- demonstrably cannot beat the current winner.
    if pos == 3 and trick.leadSuit and knownVoids then
        local pos4Seat = (seat % 4) + 1
        local pos4Voids = knownVoids[pos4Seat]
        if pos4Voids and pos4Voids[trick.leadSuit] then
            -- Pos-4 cannot follow led suit. In Sun this means they
            -- can't beat (no trump). In Hokm with trump available
            -- they could ruff — only "certain" if pos-4 also void
            -- in trump or trump fully exhausted.
            if contract.type == K.BID_SUN then
                return curWinner, "certain"
            elseif contract.type == K.BID_HOKM and contract.trump
                   and pos4Voids[contract.trump] then
                return curWinner, "certain"
            else
                return curWinner, "likely"
            end
        end
    end
    -- Pos-1, pos-2: rarely certain at this stage; leave to inline
    -- heuristics. Future expansion could add specific certainty
    -- predicates if they prove valuable.
    return curWinner, "uncertain"
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
    -- v0.11.18-final U-1 (ultra audit): drop `partnerWinning` from
    -- the implicit-AKA detector. v0.11.17 H-5 fixed the same gate
    -- on the EXPLICIT AKA branch but left implicit gated on
    -- partnerWinning; Rules.lua:142-152 grants implicit-AKA legality
    -- relief regardless. Pre-fix when partner led bare-A and opp
    -- pos-2 over-trumped, the receiver still got non-trump in legal
    -- (relief fired) but pickFollow's implicitAKA=false skipped the
    -- AKA-receiver branch, falling into wouldWin and potentially
    -- burning trump that the legality layer had freed.
    if not explicitAKA and contract.type == K.BID_HOKM
       and contract.trump and trick.leadSuit
       and trick.leadSuit ~= contract.trump
       and trick.plays and trick.plays[1] then
        local lead = trick.plays[1]
        if lead.seat == R.Partner(seat)
           and C.Rank(lead.card) == "A"
           and C.Suit(lead.card) == trick.leadSuit then
            implicitAKA = true
        end
    end
    -- v0.10.2 M4 — receiver-relief branch is now LIVE. Upstream
    -- R.IsLegalPlay was patched (Rules.lua, akaCalled param) to
    -- exempt AKA-receivers from must-trump-ruff (J-066/J-067 part 2).
    -- With the legality layer relaxed, `legal` for a void+trump
    -- seat under AKA includes non-trump cards, so the `discards`
    -- filter below has live content and the branch picks the
    -- lowest non-trump discard (preserves trump for later, lets
    -- partner take the trick with their boss). Implicit-AKA case
    -- (bare-Ace lead) doesn't reach the legality layer because the
    -- relief there hinges on `S.s.akaCalled` (only set on explicit
    -- MSG_AKA). The implicit branch here still fires only when the
    -- seat has lead-suit cards (partner-winning shortcut keeps
    -- legality permissive) — see review_v0.10.0/xref_X2_aka.md B1.
    -- v0.11.17 audit H-5: AKA-receiver relief fires regardless of
    -- partnerWinning. Pre-v0.11.17 the gate required `partnerWinning`
    -- (current trick winner = partner). But the legality layer (Rules.lua
    -- :202-206) correctly relieves the receiver from must-ruff even
    -- when an opp over-trumped partner's A-led trick — the receiver
    -- is still exempt from must-trump-ruff per J-066/J-067. Pre-fix
    -- when opp over-trumps, this branch fell through to the natural
    -- must-ruff/winners flow, sometimes burning trump unnecessarily.
    -- Now fires whenever AKA was called on the led suit, regardless
    -- of who's currently winning.
    local akaLive = explicitAKA or implicitAKA
    -- v1.1.0 (audit partner-coord H3): record partner's AKA suit in
    -- receiver memory so pickLead can prefer leading it back later
    -- (touching-honors continuation) and pickFollow can preserve
    -- high cards in that suit for partner's lead-back.
    if akaLive and trick.leadSuit and Bot._memory then
        local mem = Bot._memory[seat]
        if mem and mem.partnerAkaSuit then
            mem.partnerAkaSuit[trick.leadSuit] = true
        end
    end
    if Bot.IsAdvanced() and contract.type == K.BID_HOKM and contract.trump
       and trick.leadSuit and akaLive then
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

    -- v0.5.21 Section 5 Sun pos-4 Faranka (Definite, video 06).
    -- Saudi-pro Faranka: Sun + lastSeat + partnerWinning + we hold A
    -- AND a "cover" (T or K) of led suit + EXACTLY 2 cards of led
    -- suit (anti-trigger rule 4: ≥3 means 10 drops naturally).
    -- Duck with the COVER (T or K), let partner take this trick;
    -- our A captures the next opp-led trick. Bridges 2 tricks per
    -- single A/cover deployment.
    --
    -- Tier-gating: bidder-team only (rule 9 — defenders should win
    -- the trick to deny opp Kaboot rather than fish for tempo).
    -- Anti-trigger rule 3 (we hold two highest UNPLAYED) is hard
    -- to detect cheaply; the suitCount==2 + has-A + has-T-or-K
    -- gate is a reasonable proxy for the canonical "A+T mardoofa"
    -- Faranka shape (which IS the typical case where the rule
    -- fires per video #06).
    --
    -- This branch fires BEFORE smother (Section 4 rule 7 Takbeer)
    -- because Faranka and Takbeer conflict — both fire on
    -- partner-winning + we-hold-A scenarios. Per video #06,
    -- Faranka is the correct Sun pos-4 play; Takbeer is the
    -- general partner-winning donate-highest behavior. When BOTH
    -- conditions match (Sun + lastSeat + bidder-team + A+cover +
    -- 2-card suit), Faranka takes precedence.
    -- Sources: decision-trees.md Section 5 (Definite, video 06).
    if contract.type == K.BID_SUN and lastSeat and partnerWinning
       and trick.leadSuit
       and R.TeamOf(seat) == R.TeamOf(contract.bidder) then
        local lead = trick.leadSuit
        local hasA = false
        local cover = nil
        local coverRank = -1
        local suitCount = 0
        for _, c in ipairs(legal) do
            if C.Suit(c) == lead then
                suitCount = suitCount + 1
                local r = C.Rank(c)
                if r == "A" then hasA = true
                elseif r == "T" or r == "K" then
                    local cr = C.TrickRank(c, contract)
                    if cr > coverRank then
                        cover = c
                        coverRank = cr
                    end
                end
            end
        end
        -- v1.4.0 (Concern 5 audit fix — Faranka anti-trigger row 167):
        -- if we hold the TWO HIGHEST UNPLAYED of led suit, "ducking"
        -- with cover wouldn't actually duck — cover would beat the
        -- highest already-played card (since nothing in opp's hand is
        -- higher than our cover by definition). Faranka becomes
        -- meaningless: we'd take the trick from partner and have
        -- no follow-up advantage. Fall through to smother (next
        -- branch) which correctly donates A to partner-winning
        -- trick. Per decision-trees.md row 167 (video #06).
        local holdsTopTwoUnplayed = false
        if hasA and cover and S.s.playedCardsThisRound then
            local plainOrder = { "A", "T", "K", "Q", "J", "9", "8", "7" }
            local firstUnplayed, secondUnplayed = nil, nil
            for _, r in ipairs(plainOrder) do
                if not S.s.playedCardsThisRound[r .. lead] then
                    if not firstUnplayed then
                        firstUnplayed = r
                    else
                        secondUnplayed = r; break
                    end
                end
            end
            if secondUnplayed and C.Rank(cover) == secondUnplayed then
                holdsTopTwoUnplayed = true
            end
        end
        -- Faranka fires when:
        --   • We have A + a cover (T or K) of led suit.
        --   • Exactly 2 cards in led suit (rule 4 anti-trigger).
        --   • Bidder-team only (rule 9 anti-trigger).
        --   • Anti-trigger row 167 (v1.4.0): NOT holding top 2 unplayed.
        if hasA and cover and suitCount == 2 and not holdsTopTwoUnplayed then
            -- v1.5.0 (audit follow-up — Faranka 5-factor framework).
            -- Sources: video #06 (faranka_in_sun) — explicit 5-factor
            -- framework + video #20 (control) — weak-partner inversion.
            --
            -- Pre-v1.5.0: flat 30% capture / 70% Faranka, with a
            -- v1.3.0 weak-partner inversion to 70% capture. The flat
            -- rate didn't reflect video #06's stated 5-factor
            -- gradient («راح اعطيك خمس عوامل رئيسيه» — "I'll give you
            -- five main factors"). Pros don't Faranka uniformly —
            -- they evaluate factors and adjust.
            --
            -- v1.5.0 5-factor framework — each factor that favors
            -- Faranka decreases capture rate (more duck) by 0.10:
            --   F1: Cover is J (highest possible cover, video factor 1)
            --   F2: Partner-takes (already required by partnerWinning)
            --   F3: Al-Kaboot pursuit active (sweepPursuit true)
            --   F4: Faranka would flip game-loss to opp (score-aware)
            --   F5: LHO is bidder + trick == 1 (proxy for LHO holds T)
            --   Plus weakHandSignal inversion (video #20): boost
            --   capture by +0.40 (strong-hand-grabs-tempo)
            --   Anti-trigger: opp-bidder + Kaboot threat → capture=1
            --   (always take, deny their Kaboot)
            -- Score base = 0.50 (uncertain default). Range clamped
            -- to [0.05, 0.95] so neither extreme is deterministic
            -- (preserves unpredictability per v1.2.1 A7 audit).
            -- M3lm-gated.
            local captureRate = 0.50
            -- F1: cover is J (best — J+A doubleton)
            if cover and C.Rank(cover) == "J" then
                captureRate = captureRate - 0.10
            end
            -- F2: partner-takes is implicit (partnerWinning required
            -- by outer gate). No additional score.
            -- F3: Al-Kaboot pursuit active for our team
            local sweepActive = false
            if S.s.tricks and #S.s.tricks >= 2 then
                local myTeam = R.TeamOf(seat)
                local allMine = true
                for _, t in ipairs(S.s.tricks) do
                    if R.TeamOf(t.winner) ~= myTeam then
                        allMine = false; break
                    end
                end
                sweepActive = allMine
            end
            if sweepActive then
                captureRate = captureRate - 0.10
            end
            -- F4: Faranka-success would flip game-loss to opp.
            -- Heuristic: opp's cumulative is within target-26 (clinch
            -- pressure on opp side) AND we're behind in this round →
            -- securing this Faranka denies them the points.
            if S.s.cumulative and S.s.target then
                local myTeam = R.TeamOf(seat)
                local oppTeam = (myTeam == "A") and "B" or "A"
                local oppCum = S.s.cumulative[oppTeam] or 0
                local target = S.s.target
                if oppCum >= target - 26 then
                    captureRate = captureRate - 0.10
                end
            end
            -- F5: LHO (next-trick leader) is the bidder AND we're at
            -- trick 1 (fresh hand) — proxy for "LHO probably has T".
            -- We're at pos-4, so LHO is the next-clockwise seat.
            local lhoSeat = (seat % 4) + 1
            local trickN = #(S.s.tricks or {}) + 1
            if contract.bidder == lhoSeat and trickN == 1 then
                captureRate = captureRate - 0.10
            end
            -- Weak-partner inversion (video #20): if partner has shown
            -- weak hand pattern, INVERT — strong hand grabs tempo.
            if Bot._partnerStyle then
                local pStyle = Bot._partnerStyle[R.Partner(seat)]
                if pStyle and pStyle.weakHandSignal and pStyle.highCardPlays then
                    local total = pStyle.weakHandSignal + pStyle.highCardPlays
                    if total >= 3
                       and pStyle.weakHandSignal > pStyle.highCardPlays * 2 then
                        captureRate = captureRate + 0.40
                    end
                end
            end
            -- Anti-trigger: opp-bidders + Kaboot threat (defender
            -- must break Kaboot, can't gamble Faranka). Per video
            -- #06: "if opp is bidder and threatening Al-Kaboot,
            -- DON'T Faranka — defend, don't experiment."
            if contract.bidder
               and R.TeamOf(contract.bidder) ~= R.TeamOf(seat)
               and S.s.tricks and #S.s.tricks >= 3 then
                local oppTeam = R.TeamOf(contract.bidder)
                local oppSweep = true
                for _, t in ipairs(S.s.tricks) do
                    if R.TeamOf(t.winner) ~= oppTeam then
                        oppSweep = false; break
                    end
                end
                if oppSweep then
                    captureRate = 1.0  -- always take, break Kaboot
                end
            end
            -- v1.6.0 CS-01 (audit v1.5.3 swarm — predictability fix):
            -- borderline-state breaker. When the factor-additive
            -- captureRate lands in the genuinely-uncertain band
            -- [0.40, 0.60] — i.e. neither the cover, sweep, game-flip,
            -- nor LHO factors push it strongly either way — add a
            -- ±0.10 random kick before the clamp. This shifts the
            -- actual roll across the Faranka/capture flip threshold
            -- on ~20% of borderline rolls that were previously fully
            -- predictable to humans memorizing the 5-factor framework.
            -- M3lm+-gated; partner-bot doesn't predict outcomes in
            -- advance, only observes the result, so the wobble stays
            -- inside the noise budget partner already absorbs from
            -- the 0.50 base.
            if Bot.IsM3lm and Bot.IsM3lm()
               and captureRate >= 0.40 and captureRate <= 0.60 then
                captureRate = captureRate + (math.random() * 0.20 - 0.10)
            end
            -- Clamp [0.05, 0.95]
            if captureRate < 0.05 then captureRate = 0.05 end
            if captureRate > 0.95 then captureRate = 0.95 end
            if Bot.IsM3lm and Bot.IsM3lm() and math.random() < captureRate then
                -- Capture-not-Faranka: take with A. Sun off-trump A
                -- is the highest in suit; cover stays for next
                -- trick.
                for _, c in ipairs(legal) do
                    if C.Suit(c) == lead and C.Rank(c) == "A" then
                        return c
                    end
                end
            end
            return cover
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
            -- v0.5.18 Section 4 rule 7 extension (Definite, videos 21+22+23):
            -- Takbeer / التكبير = donate HIGHEST point card to partner's
            -- certain-winning trick. Pre-v0.5.18 only A and T were
            -- candidates ("highInSuit"); the Saudi convention also
            -- includes K (4 raw), Q (3 raw), and J (2 raw) — all the
            -- "ابناء" (point-card sons). Higher = more donated; the
            -- existing v0.5.11 descending-sort + [1] correctly returns
            -- the highest. Expanding the candidate set ensures we
            -- donate K when no A or T is in led suit, etc.
            -- Sources: decision-trees.md Section 4 rule 7 (Definite,
            -- videos 21, 22, 23).
            local pointCards = {}
            for _, c in ipairs(legal) do
                local r = C.Rank(c)
                if C.Suit(c) == lead and (r == "A" or r == "T"
                                          or r == "K" or r == "Q" or r == "J") then
                    pointCards[#pointCards + 1] = c
                end
            end
            local completed = #(S.s.tricks or {})
            -- v1.0.4 (agent #6): touching-honors signal in pickFollow.
            -- F3 wired the partner-touch-honor READ in pickLead. Mirror
            -- the read here in the smother branch: if partner has
            -- shown a touching T or Q signal in the LED suit
            -- (sig.nextDown), partner intends to lead this suit again
            -- with their middle honor. Donating our A or T now wastes
            -- our future cash — partner's run on their own lead is
            -- the bigger play. Suppress the donate of A/T.
            --
            -- v1.2.1 (G3 audit fix): drop `sig.cleared` from this gate.
            -- Per video #05 «هل ممكن يكون عنده البنت ولا الولد لا
            -- مستحيل لو عنده كان لعبها بدال الشايب»: K-singleton
            -- (cleared = {Q,J}) means partner CAN'T continue the run —
            -- their only middle-honor card was the K and they already
            -- played it. There is NO "partner leads this back later"
            -- in the K-singleton case. Treating `cleared` as a save-
            -- signal was inverted. Now `cleared` falls through to
            -- normal donate (no save), and a NEW force-donate branch
            -- below biases A/T donation when cleared is set (partner
            -- can't take, so we should cash NOW). Symmetric with the
            -- pickLead reader fix at line ~3037.
            local saveForPartnerTouch = false
            local forceDonateCleared = false
            if Bot.IsM3lm() and Bot._partnerStyle and lead then
                local partnerStyle = Bot._partnerStyle[R.Partner(seat)]
                local sig = partnerStyle and partnerStyle.topTouchSignal
                            and partnerStyle.topTouchSignal[lead]
                if sig and not sig.broke then
                    if sig.nextDown then
                        saveForPartnerTouch = true
                    elseif sig.cleared then
                        -- Partner is broke in middle honors → cash now.
                        forceDonateCleared = true
                    end
                end
            end
            if saveForPartnerTouch then
                -- Filter A and T out of pointCards; let K/Q/J donate.
                local filtered = {}
                for _, c in ipairs(pointCards) do
                    local r = C.Rank(c)
                    if r ~= "A" and r ~= "T" then
                        filtered[#filtered + 1] = c
                    end
                end
                pointCards = filtered
            elseif forceDonateCleared then
                -- v1.2.2 (HIGH-2 audit fix): consume the
                -- forceDonateCleared flag the v1.2.1 G3 fix set but
                -- never read. Per video #05 «هل ممكن يكون عنده البنت
                -- ولا الولد لا مستحيل»: K-singleton means partner
                -- CAN'T continue the run — donate A/T NOW (before
                -- they get stranded). Filter pointCards to ONLY A/T
                -- so the descending-sort below picks A first; if
                -- neither A nor T is present, fall through to the
                -- normal pointCards (no-op). Symmetric inversion
                -- of the saveForPartnerTouch branch.
                local highCash = {}
                for _, c in ipairs(pointCards) do
                    local r = C.Rank(c)
                    if r == "A" or r == "T" then
                        highCash[#highCash + 1] = c
                    end
                end
                if #highCash > 0 then pointCards = highCash end
            end
            -- Gate: ≥2 point cards spare, OR late round, OR pos 4.
            -- v0.5.18 keeps the same gate logic but applies to the
            -- expanded candidate set.
            -- v1.0.4 (agent #2): multiplier-aware tightening.
            -- v1.0.6 (N2): tiered gate — pre-fix treated all
            -- escalation rungs identically as `lastSeat-only`. But
            -- ×2 (Bel) is the COMMONEST escalation in tournament
            -- play; suppressing speculative donates on every Bel'd
            -- round throws away a tested heuristic. ×3/×4 are where
            -- regret math diverges (40-effective swing). Now:
            --   foured / tripled : lastSeat only (strictest)
            --   doubled (×2)     : lastSeat OR completed >= 4
            --   none             : original (≥2 spare OR completed
            --                      >= 3 OR lastSeat)
            local gateOk
            if contract.foured or contract.tripled then
                gateOk = lastSeat  -- only the safest donate fires
            elseif contract.doubled then
                gateOk = (lastSeat or completed >= 4)
            else
                gateOk = (#pointCards >= 2 or completed >= 3 or lastSeat)
            end
            if gateOk then
                table.sort(pointCards, function(a, b)
                    return C.TrickRank(a, contract) > C.TrickRank(b, contract)
                end)
                -- v1.2.1 (G8 audit): conditional consecutive/non-
                -- consecutive Takbeer override per video #21 lines
                -- 142-149: «الاصل والافضل تلعب اكبر» (default is
                -- highest) BUT «الا اذا تبغى كلاب طبعا عشان تمسك لعب
                -- لازم يكون عندك قوه يعني معك اوراق صنع» (exception:
                -- if you want to hold the game AND have own cover,
                -- play the lower of the non-consecutive pair to
                -- signal "boss above is missing").
                -- Conditions: contract = Sun; non-consecutive pair
                -- (gap of ≥1 rank between top two pointCards); we
                -- hold a cover Ace in another suit (own strength
                -- justifying tempo-hold). Falls back to default
                -- (highest) when conditions unmet.
                if contract.type == K.BID_SUN and #pointCards >= 2 then
                    local plain = K.RANK_PLAIN or {}
                    local r1 = plain[C.Rank(pointCards[1])] or 0
                    local r2 = plain[C.Rank(pointCards[2])] or 0
                    local nonConsecutive = (r1 - r2) >= 2
                    local hasCoverAce = false
                    for _, c in ipairs(legal) do
                        if C.Rank(c) == "A"
                           and C.Suit(c) ~= C.Suit(pointCards[1]) then
                            hasCoverAce = true; break
                        end
                    end
                    if nonConsecutive and hasCoverAce
                       and Bot.IsM3lm and Bot.IsM3lm() then
                        -- Play the LOWER of the pair to signal "boss
                        -- above is missing" → partner reads "no top
                        -- card here" and continues.
                        return pointCards[2]
                    end
                end
                if pointCards[1] then return pointCards[1] end
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
        -- v1.4.5 (multi-perspective audit, Codex finding): removed
        -- the bot-partner-only gate. Pre-fix: `Bot.IsBotSeat(R.Partner
        -- (seat))` constrained Tahreeb sender to fire only when partner
        -- was a bot, treating human partners as "noise". Per Codex
        -- audit:
        --
        -- > "Strong human players do read Saudi signals. Ignoring
        -- > human-readable signaling leaves EV on table."
        --
        -- Saudi convention is a partnership language; competent human
        -- partners (the kind who know to expect Tahreeb signaling)
        -- understand and parse the convention. Sending the signal
        -- helps them whether they're bot or human. M3lm+ tier gating
        -- preserved (basic/advanced bots don't emit; the convention
        -- is sophisticated). Receiver-side reads of human signals are
        -- still appropriately discounted (humans may not strictly
        -- follow the convention) — that asymmetry is correct per
        -- audit guidance.
        if Bot.IsM3lm() and voidInLed then
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
            -- v1.0.3 (F6 deferred-decision-doc): Hokm extension
            -- considered and rejected. The Saudi convention for
            -- discard-side-A-with-cover is canonically Sun-only per
            -- decision-trees.md Section 8 — Hokm has its own
            -- side-suit-control signaling (implicit AKA on bare-A
            -- lead, AKA explicit announcement). Adding a Hokm
            -- Bargiya would conflict with the U-6 v0.11.19 fix
            -- ("when partnerWinning + Hokm + void in led suit,
            -- prefer non-trump discard") which currently picks the
            -- LOWEST non-trump in this exact branch path (E.3 test
            -- pin). The Sun gate stays as-is; the Hokm "lead-back"
            -- semantic is carried by the AKA announce flow instead.
            if contract.type == K.BID_SUN then
                -- v1.2.1 (G7 audit): conditional A+cover requirement.
                -- Per video #14 lines 311-317: «اذا بتبرق لخويه يكون
                -- عندك سوا بالذات اذا كان في يدك اربع اوراق لكن اذا
                -- سبعه سته اوراق ثمانيه اوراق من بدري مو لازم يكون
                -- عندك سوا بالذات اذا عندك لون واحد فقط». Translation:
                -- "if you Bargiya, ideally have SWA — ESPECIALLY late-
                -- game (4-card hand). Early game (7-8 cards), need not
                -- have SWA, especially if you only hold one suit
                -- (cornered)." So:
                --   * Late-game (#hand <= 4): require A + cover (≥2)
                --   * Early-game (#hand >= 5): allow A-only IF the
                --     bot has only ONE non-trump suit (cornered)
                local handSize = (S.s.isHost and S.s.hostHands
                                  and S.s.hostHands[seat]
                                  and #S.s.hostHands[seat]) or 0
                local lateGame = (handSize > 0 and handSize <= 4)
                for _, su in ipairs(shuffledSuits()) do
                    local cards = bySuit[su]
                    local minLen = lateGame and 2 or 1
                    if #cards >= minLen then
                        -- Early-game cornered exception: only allow
                        -- A-only when this is our only non-trump suit
                        -- with cards.
                        local cornered = true
                        if not lateGame and #cards == 1 then
                            for _, su2 in ipairs({"S","H","D","C"}) do
                                if su2 ~= su and #(bySuit[su2] or {}) > 0 then
                                    cornered = false; break
                                end
                            end
                            if not cornered then
                                -- skip — early-game A-only without
                                -- cornered suit is the ambiguous case.
                            else
                                for _, c in ipairs(cards) do
                                    if C.Rank(c) == "A" then
                                        return c   -- Bargiya cornered
                                    end
                                end
                            end
                        else
                            for _, c in ipairs(cards) do
                                if C.Rank(c) == "A" then
                                    return c   -- Bargiya (cover proven)
                                end
                            end
                        end
                    end
                end
            end

            -- Tahreeb "want" sender arm (Sun-only).
            -- Source: video #1 form 5 «بدال البرقيه» (bottom-up =
            -- "want this suit, NO Ace"). Receiver decodes the
            -- ascending sequence as "lead suit back, partner has
            -- cards but no A/T". Bargiya (above) handles the A+cover
            -- case; this arm covers want-without-Ace.
            --
            -- v1.4.4 reversed v0.9.0 wiring per multi-perspective
            -- audit: pre-fix this fired from suits WITH A or T (a
            -- STRONG suit per video #3 — should NOT be Tahreeb'd).
            -- Now requires no A AND no T for canonical "want without
            -- Ace" semantics. Sun-only gate (v0.11.18-final U-2):
            -- Hokm partnerships use trump-pull, not side-suit
            -- want-back. Receiver decoder at Bot.lua:2322+
            -- (tahreebClassify) treats ascending sequence as "want".
            if contract.type == K.BID_SUN then
            for _, su in ipairs(shuffledSuits()) do
                local cards = bySuit[su]
                if #cards >= 3 then
                    local hasA, hasT = false, false
                    for _, c in ipairs(cards) do
                        local r = C.Rank(c)
                        if r == "A" then hasA = true
                        elseif r == "T" then hasT = true end
                    end
                    if not hasA and not hasT then
                        -- "Want, no Ace" canonical bottom-up: pick the
                        -- lowest card from this no-honors suit. Receiver
                        -- decodes as "lead suit X back, partner has
                        -- some cards but no A/T" — the correct semantic.
                        local lows = {}
                        for _, c in ipairs(cards) do
                            lows[#lows + 1] = c
                        end
                        if #lows > 0 then
                            return lowestByRank(lows, contract)
                        end
                    end
                end
            end
            end  -- end of v0.11.18-final U-2 Sun-only gate

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
            for _, su in ipairs(shuffledSuits()) do
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

        -- v0.7.2 Section 4 rule 1B (Definite, video 09 "biggest
        -- mistake"): partner-winning + we must follow + we can't
        -- beat their lead AND smother above didn't fire (no
        -- A/T/K/Q/J of led suit to donate). Default lowestByRank
        -- would return absolute lowest — but per video #09 that's
        -- the single biggest mistake in Baloot: it signals "I'm
        -- out of this suit, partner can't lead it back to me",
        -- denying the re-entry. Play SECOND-LOWEST instead — keeps
        -- partner's option to lead this suit back to us, knowing
        -- we may have a higher card to take.
        --
        -- v1.1.0 (audit partner-coord H4): EXTENDED to Hokm. Pre-fix
        -- this branch was Sun-only ("Hokm partner-winning has
        -- different conventions") but video #09 explicitly does NOT
        -- condition on contract type for the absolute-lowest mistake
        -- — the re-entry signal corruption is contract-agnostic.
        -- Hokm carve-out: don't fire when partner led trump (the
        -- "low signals out" semantic doesn't apply to trump-pull)
        -- or when we're forced to ruff (must-trump situation).
        local rule1bApplies = false
        if trick.leadSuit then
            if contract.type == K.BID_SUN then
                rule1bApplies = true
            elseif contract.type == K.BID_HOKM
                   and trick.leadSuit ~= contract.trump then
                rule1bApplies = true
            end
        end
        if rule1bApplies then
            local follow = {}
            for _, c in ipairs(legal) do
                if C.Suit(c) == trick.leadSuit then
                    follow[#follow + 1] = c
                end
            end
            if #follow >= 2 then
                local sorted = {}
                for _, c in ipairs(follow) do sorted[#sorted + 1] = c end
                table.sort(sorted, function(a, b)
                    return C.TrickRank(a, contract) < C.TrickRank(b, contract)
                end)
                -- v0.9.5 wouldWin gate (audit_v0.9.0/18_section4_now.md
                -- §2): rule 1B's "second-lowest" can be a card that
                -- BEATS partner's lead — stealing the trick instead
                -- of letting partner take it. Example: partner leads
                -- JH, we hold {7H, KH}. sorted[2] = KH beats JH and
                -- steals partner's trick. Defend: only return the
                -- second-lowest if it does NOT win the trick (i.e.,
                -- partner would still be the trick winner after our
                -- play). If second-lowest would steal, fall through
                -- to lowestByRank — partner keeps the trick we're
                -- preserving the re-entry signal indirectly via the
                -- absolute-lowest play (the "biggest mistake" rule's
                -- mitigation is moot if our lowest IS the absolute
                -- lowest of a 2-card holding anyway).
                if not wouldWin(sorted[2], trick, contract, seat) then
                    return sorted[2]   -- second-lowest = re-entry signal
                end
            end
        end

        -- v0.11.19 audit U-6: prefer non-trump discard when partner
        -- is winning in Hokm and we're released from must-ruff. Per
        -- decision-trees.md Section 6, when pos-4-partner-winning-
        -- void-in-led-suit in Hokm, legality permits both trump and
        -- non-trump. lowestByRank ties at TrickRank=1 between trump-7
        -- and non-trump-7 — iteration order arbitrarily picks one,
        -- wasting trump 50% of the time. Non-trump preference
        -- preserves trump for actual ruffing capacity later.
        -- Belote-K/Q-of-trump preservation already handled above.
        if contract.type == K.BID_HOKM and contract.trump then
            local nonTrumpLegal = {}
            for _, c in ipairs(legal) do
                if not C.IsTrump(c, contract) then
                    nonTrumpLegal[#nonTrumpLegal + 1] = c
                end
            end
            if #nonTrumpLegal > 0 then
                return lowestByRank(nonTrumpLegal, contract)
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

    -- Hokm Faranka exceptions (M3lm-gated, video #04). Default
    -- Hokm = no Faranka. Three exceptions allow withholding top
    -- trump (bidder-team only):
    --   #2: bidder-team + only 2 trumps total (weak posture, low EV cost)
    --   #3: bidder-team + J dead + we hold 9 (9 is new top live trump)
    --   #4: bidder-team + both opps observed void in trump (risk-free)
    -- F-16 K-cover veto applies to #2 and #3 (no K → don't Faranka).
    -- Exceptions #1 (sweep-track) and #5 (partner-trump-extra)
    -- remain deferred — see CHANGELOG history.
    if Bot.IsM3lm() and contract.type == K.BID_HOKM and contract.trump
       and trick.leadSuit and #winners > 0 then
        local farankaTriggered = false

        -- Count our trumps for Exception #2.
        -- v0.9.2 #49 fix (audit_v0.9.0/49_hokm_faranka_priorities.md):
        -- gate Exception #2 on bidder-team membership. Pre-v0.9.2 the
        -- 2-trump trigger fired regardless of contract ownership, so
        -- the bot would Faranka into the OPPONENT's Hokm contract on
        -- 2-trump hands — actively helping opp's contract make. The
        -- doc's intent was "low-risk withhold for our team's own
        -- contract"; we make that explicit by checking team membership.
        local myTrumpCount = 0
        for _, c in ipairs(hand) do
            if C.IsTrump(c, contract) then
                myTrumpCount = myTrumpCount + 1
            end
        end
        local onBidderTeam = (contract.bidder
                              and R.TeamOf(contract.bidder) == R.TeamOf(seat))
        if myTrumpCount == 2 and onBidderTeam then
            farankaTriggered = true
        end

        -- v0.8.5 Exception #3 (Common, video 04): J of trump is dead
        -- AND we hold the 9 of trump → 9 is the new top live trump
        -- (Hokm trump rank: J=8 > 9=7 > A=6 > ...). Faranka allowed
        -- because withholding the new boss to ambush opp's other
        -- high cards has clear EV.
        --
        -- v0.10.0 X3 fix (review_v0.10.0/xref_X3_*.md): bidder-team
        -- gate added (parallel with v0.9.2 #49's Exception "#2" fix).
        -- Pre-v0.10.0 Exception "#3" fired regardless of contract
        -- ownership — the bot would Faranka into opp's Hokm contract
        -- on J-dead+9-only hands, withholding trump from a trick
        -- the opp wanted to win and helping their contract make.
        -- Source C: pro-Faranka triggers must be bidder-team-only.
        --
        -- Detection uses S.HighestUnplayedRank(trump) which is
        -- trump-aware as of v0.8.5 (was buggy plain-rank-order
        -- pre-v0.8.5). When it returns "9", J has been played AND 9
        -- is still live — which exactly matches the rule's WHEN.
        if not farankaTriggered and onBidderTeam
           and S.HighestUnplayedRank
           and S.HighestUnplayedRank(contract.trump) == "9" then
            local hold9 = false
            for _, c in ipairs(hand) do
                if C.Suit(c) == contract.trump and C.Rank(c) == "9" then
                    hold9 = true; break
                end
            end
            if hold9 then farankaTriggered = true end
        end

        -- Exception #4: bidder-team + both opps void in trump.
        --
        -- v0.10.0 X3 fix (review_v0.10.0/xref_X3_*.md): relaxed
        -- `contract.bidder == seat` (over-tight, only the bidder
        -- themselves) to bidder-team membership. Source C: Saudi
        -- convention says ANY member of the bidder-team can take
        -- the risk-free Faranka when both opps are void — partner
        -- of the bidder also qualifies. Pre-v0.10.0 the partner
        -- silently fell through to natural play, missing the EV.
        local oppsVoidPath = false  -- v0.10.3 audit: tracks Exc-#4 trigger
        if not farankaTriggered and onBidderTeam then
            local oppTrumpExhausted = true
            for s2 = 1, 4 do
                if R.TeamOf(s2) ~= R.TeamOf(seat) then
                    local m = Bot._memory and Bot._memory[s2]
                    if not (m and m.void and m.void[contract.trump]) then
                        oppTrumpExhausted = false
                        break
                    end
                end
            end
            if oppTrumpExhausted then
                farankaTriggered = true
                oppsVoidPath = true
            end
            -- v0.10.3 F-30b secondary trigger (review_v0.10.2 G-Logic-01 §1).
            -- The per-opp `void[trump]` flag misses the structurally-
            -- extinct case where the entire trump pool has been played
            -- out (S.HighestUnplayedRank(trump) == nil). Per-opp voids
            -- are only set after we OBSERVE that opp fail-to-follow on
            -- a trump-led trick; if trump are exhausted via trump-led
            -- consumption (we played J+9+K+Q etc.), opps may have
            -- followed every trump-led trick without ever revealing
            -- a trump void, leaving Bot._memory[opp].void[trump] false
            -- even though no opp can punish us. HighestUnplayedRank
            -- consults playedCardsThisRound and is deterministic — a
            -- canonical "no opp can ruff" check that doesn't depend
            -- on opp-void observation.
            if not farankaTriggered and onBidderTeam
               and S.HighestUnplayedRank
               and S.HighestUnplayedRank(contract.trump) == nil then
                farankaTriggered = true
                oppsVoidPath = true
            end
        end

        -- v0.10.0 X3 anti-rule F-16 (review_v0.10.0/xref_X3_*.md):
        -- "no K of trump → don't Faranka". Source C F-16 is an
        -- explicit anti-rule: the K is the canonical "cover" card
        -- for a Faranka — without it, the withhold has no
        -- defensive backbone (any opponent A-of-trump punishes the
        -- preserved card directly). Pre-v0.10.0 the code accepted
        -- T-as-cover when K was absent — F-16 violated.
        --
        -- v0.10.3 audit (A-Src-29 + D-RT-03 S-1, HIGH): scope F-16
        -- to threat-model-live cases. F-16's premise — "opp can
        -- still punish the withheld trump" — is structurally
        -- extinct on Exception #4 (`oppsVoidPath`): when both opps
        -- are observed-void in trump, no opp holds a punishing
        -- card regardless of whether we hold K. Pre-v0.10.3 this
        -- gate fired uniformly across exceptions, vetoing
        -- legitimate F-30b risk-free Farankas on K-less hands.
        -- Sources: D-RT-03 S-1 Option A (per-exception scoping);
        -- A-Src-29 confirms F-16 is absent from #04 Hokm corpus.
        if farankaTriggered and not oppsVoidPath then
            local hasKtrump = false
            for _, c in ipairs(hand) do
                if C.IsTrump(c, contract) and C.Rank(c) == "K" then
                    hasKtrump = true; break
                end
            end
            if not hasKtrump then farankaTriggered = false end
        end

        -- v0.10.3 deletion (review_v0.10.2 §9 follow-up #3, A-Src-29
        -- + D-RT-03 S-5): the former rule-7 anti-trigger here ("opp
        -- bidder led trump-Q AND we hold J+8 → cancel Faranka") was
        -- removed for two reasons: (a) sourceless — F-39 / J+8-vs-Q
        -- doesn't appear in the #04 Hokm corpus per A-Src-29; (b)
        -- structurally dead post-v0.10.0 — the bidder-team gates
        -- on Exceptions #2/#3 (v0.9.2 #49 + v0.10.0 X3) and the
        -- F-16 K-cover veto on Exception #4 mean the only path
        -- where farankaTriggered is true with opp-bidder-led-Q is
        -- already vetoed upstream. The bidder-team gate forbids
        -- our team from triggering when the lead was an opp's, so
        -- the predicate `R.TeamOf(lead.seat) ~= R.TeamOf(seat)`
        -- under `farankaTriggered=true` was unreachable. Removing
        -- closes a sourceless dead branch.

        if farankaTriggered then
            -- Find a non-winner to play. Prefer non-trump non-winner
            -- (preserve trump cover); fall through to lowest non-winner
            -- of any suit.
            local nonWinners = {}
            for _, c in ipairs(legal) do
                local isWin = false
                for _, w in ipairs(winners) do
                    if w == c then isWin = true; break end
                end
                if not isWin then
                    nonWinners[#nonWinners + 1] = c
                end
            end
            if #nonWinners > 0 then
                -- Prefer non-trump non-winner to keep trump in reserve.
                local nonTrumpLosers = {}
                for _, c in ipairs(nonWinners) do
                    if not C.IsTrump(c, contract) then
                        nonTrumpLosers[#nonTrumpLosers + 1] = c
                    end
                end
                local pool = (#nonTrumpLosers > 0) and nonTrumpLosers or nonWinners
                return lowestByRank(pool, contract)
            end
            -- All legal are winners; fall through to natural play.
        end
    end

    -- Defender J/9 trump-burn protection on bidder's low-trump probe.
    -- v1.0.0 Cluster 2 F2. Saudi convention: when bidder leads low
    -- trump (7/8/Q) to count opp trumps, defender DUCKS with non-J/9
    -- trump to keep killers hidden for the real pull (where J can
    -- kill bidder's A). Mirrors pickLead's saveHighTrump on the
    -- response side. Gate: Hokm + trump-led + lead seat = bidder +
    -- lead-rank ∈ {7, 8, Q} + defender team + legal contains J or 9
    -- of trump + has non-J/9 trump alternative. Action: return
    -- lowest non-J/9 trump (may be a winner — that's fine).
    if Bot.IsAdvanced() and contract.type == K.BID_HOKM
       and contract.trump and trick.leadSuit == contract.trump
       and trick.plays and trick.plays[1]
       and trick.plays[1].seat == contract.bidder
       and R.TeamOf(seat) ~= R.TeamOf(contract.bidder) then
        local leadCard = trick.plays[1].card
        local leadRank = C.Rank(leadCard)
        local lowProbe = (leadRank == "7" or leadRank == "8" or leadRank == "Q")
        if lowProbe then
            local hasKillerInLegal = false
            local nonKillerTrump = {}
            for _, c in ipairs(legal) do
                if C.IsTrump(c, contract) then
                    local r = C.Rank(c)
                    if r == "J" or r == "9" then
                        hasKillerInLegal = true
                    else
                        nonKillerTrump[#nonKillerTrump + 1] = c
                    end
                end
            end
            -- Only fire if we have a killer to protect AND a duck
            -- option. If legal is all-killers (J+9 only), fall
            -- through — the natural pos-N logic picks the lower
            -- killer (preserves the higher one).
            if hasKillerInLegal and #nonKillerTrump > 0 then
                return lowestByRank(nonKillerTrump, contract)
            end
        end
    end

    -- v1.1.0 (audit transcript-cross-check H1): Hokm 9-of-trump
    -- consecutive/non-consecutive Takbeer rule (video #22 R3/R4 —
    -- the most valuable unwired Hokm-trump-follow rule).
    -- When following trump and we hold 9 of trump alongside a
    -- non-rank-adjacent lower trump, prefer the lower trump. Hokm
    -- trump rank order: J(8) > 9(7) > A(6) > T(5) > K(4) > Q(3) >
    -- 8(2) > 7(1). Adjacent-below-9 = A only. So with 9 + (T/K/Q/8/7)
    -- the lower is non-adjacent → play the lower to fish opp's J/A,
    -- save the 9 for next trick.
    -- Verbatim: «لو عندك تسعه + ثمانيه ... ما تلعب التسعه ... لان
    -- ما عندك حافه فوقها» = "if you have 9+8, don't play the 9 —
    -- you have no edge (rank-adjacent partner) above it."
    -- Skipped at pos-4 (trick is closing — 9 can win immediately
    -- with no fishing benefit) and when must-ruff legality forces
    -- the only-trump path.
    if Bot.IsAdvanced() and contract.type == K.BID_HOKM
       and contract.trump and trick.leadSuit == contract.trump
       and not lastSeat then
        local nineOfTrump
        local nonAdjacentLowers = {}
        for _, c in ipairs(legal) do
            if C.Suit(c) == contract.trump then
                local r = C.Rank(c)
                if r == "9" then
                    nineOfTrump = c
                elseif r == "T" or r == "K" or r == "Q"
                       or r == "8" or r == "7" then
                    nonAdjacentLowers[#nonAdjacentLowers + 1] = c
                end
            end
        end
        if nineOfTrump and #nonAdjacentLowers > 0 then
            return lowestByRank(nonAdjacentLowers, contract)
        end
    end

    if #winners > 0 then
        -- v1.0.4 (agent #1): urgency-aware swing. Pre-fix the trick-
        -- play winner picker uniformly preferred low-cost winners
        -- (cheapest-winner pos-4 default, position-2 ducks). But when
        -- we're in cumulative match-point pressure (near clinch on
        -- our side OR near loss to opp), winning THIS trick reliably
        -- matters more than saving a card for a future trick that
        -- may never happen. Mirror M5's "make-or-break" trick-8
        -- highestByRank preference, but extend it to mid-round
        -- tricks where score-position is decisive.
        --
        -- Gate: M3lm-tier (urgency-reading is M3lm); team is
        -- defender-side near-clinch (forcing bidder fail = match
        -- swing) OR bidder-side near-clinch (making bid = match
        -- swing). Skip on trick 8 (M5 already handles it).
        if Bot.IsM3lm() and S.s.cumulative then
            local trickNumPF = #(S.s.tricks or {}) + 1
            if trickNumPF < 8 then
                local myTeam = R.TeamOf(seat)
                local myCum = S.s.cumulative[myTeam] or 0
                local oppCum = S.s.cumulative[(myTeam == "A") and "B" or "A"] or 0
                local target = S.s.target or 152
                -- Either side of clinch: we're at target-25+ OR opp
                -- is at target-15+ (opp clinching faster is also a
                -- decisive moment).
                local pivotalSwing = (myCum >= target - 25)
                                     or (oppCum >= target - 15)
                if pivotalSwing then
                    -- v1.0.6 (N1): partner-meld-pin guard. Cluster 1's
                    -- meldKnownHeld helper tracks cards partner has
                    -- declared via melds (still in their hand). If
                    -- partner has a HIGHER-rank card in led suit via
                    -- a declared meld, taking the trick with our
                    -- card now strands partner's meld run — partner
                    -- would have caught it cleanly. Suppress the
                    -- swing override and let partner's known boss
                    -- take the trick naturally.
                    local skipForPartnerMeld = false
                    if trick.leadSuit and meldKnownHeld then
                        local partner = R.Partner(seat)
                        local known = meldKnownHeld(partner)
                        for kc in pairs(known) do
                            if C.Suit(kc) == trick.leadSuit then
                                -- Find our highest card we'd win with;
                                -- compare to partner's meld card.
                                for _, c in ipairs(winners) do
                                    if C.Suit(c) == trick.leadSuit
                                       and C.TrickRank(kc, contract)
                                          > C.TrickRank(c, contract) then
                                        skipForPartnerMeld = true
                                        break
                                    end
                                end
                            end
                            if skipForPartnerMeld then break end
                        end
                    end
                    if not skipForPartnerMeld then
                        -- Win this trick at maximum reliability —
                        -- over-trump-resistant card. Skip the pos-
                        -- aware ducks which would save cards we may
                        -- never get to use.
                        return highestByRank(winners, contract)
                    end
                end
            end
        end
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
                -- v1.5.0 (Sun K-is-boss parallel — mirrors v1.4.8
                -- HIGH-1 fix into Sun): in Sun there's no trump → no
                -- ruff threat ever. Once A of led suit is played,
                -- K becomes the live boss with nothing above. Same
                -- saving-K-too-long bug existed here as in Hokm.
                -- Promote K to sureStopper when A is gone.
                if not sureStopper and trick.leadSuit
                   and contract.type == K.BID_SUN
                   and S.s.playedCardsThisRound then
                    local aceKey = "A" .. trick.leadSuit
                    if S.s.playedCardsThisRound[aceKey] then
                        for _, c in ipairs(winners) do
                            if C.Suit(c) == trick.leadSuit
                               and C.Rank(c) == "K" then
                                sureStopper = c; break
                            end
                        end
                    end
                end
                -- v1.4.8 (audit HIGH-1 fix — Hokm K-is-boss):
                -- when A of led suit has already been played this
                -- round, our K becomes the live boss of the suit. The
                -- pre-fix code only promoted trump-winners as
                -- sureStopper and side-suit A/T in Sun — but in Hokm
                -- after A is dead, K has no card above it, and (since
                -- we only get here past the trump-out check) we don't
                -- need to fear ruff in the same way as a live A. Bot
                -- was systematically ducking K with low while opps
                -- took with Q/J — the user-reported "saves big cards
                -- for last trick, loses control" pattern matches this
                -- exactly. Per video #5 second-hand-low convention:
                -- the rule applies when the K is NOT the live boss;
                -- once A is dead, K should be played to win the
                -- trick now.
                if not sureStopper and trick.leadSuit
                   and contract.type == K.BID_HOKM
                   and trick.leadSuit ~= contract.trump
                   and S.s.playedCardsThisRound then
                    local aceKey = "A" .. trick.leadSuit
                    if S.s.playedCardsThisRound[aceKey] then
                        for _, c in ipairs(winners) do
                            if C.Suit(c) == trick.leadSuit
                               and C.Rank(c) == "K" then
                                sureStopper = c; break
                            end
                        end
                    end
                end
                -- v1.6.0 (audit v1.5.3 swarm — pos-2 deception re-intro):
                -- v1.4.6 fully removed the probabilistic pos-2 breaker
                -- on the basis that v1.4.5's pure-probability deviation
                -- read as «غلط» (beginner mistake) to a Saudi observer.
                -- The v1.5.3 audit (variance gap, agent 4) found that
                -- removal went too far for HUMAN-target play: pos-2 is
                -- the most-read position in Saudi Baloot, and a fully
                -- deterministic pos-2 makes the bot strictly readable.
                -- Per video #22 R3, pros DO deviate at pos-2 — but on
                -- HAND-SHAPE TRIGGERS, not pure probability.
                --
                -- v1.6.0 re-introduces pos-2 deception as a hand-shape-
                -- conditioned, Saudi-Master-only branch. Trigger: Hokm
                -- contract, sureStopper has been picked (we WERE going
                -- to take with the boss), and we hold a same-suit "next
                -- card down" that still wins the trick. With 8% chance,
                -- swap down: play the lower winner instead. Opp sees
                -- the lower card, infers we don't have the higher one,
                -- and sets up a counter-attack against the (now-fake)
                -- absent higher card. We use the higher card next round
                -- to surprise.
                --
                -- Carve-outs (forbidden):
                --  • Trump suit (signal-critical for partner reads)
                --  • Sun contract (no ruff threat — deception value lower)
                --  • Pos-3/pos-4 has known void in led suit (would over-
                --    cut our lower winner; deception fails)
                --  • The "lower winner" is also rank A or J (signal carriers)
                if sureStopper and Bot.IsSaudiMaster and Bot.IsSaudiMaster()
                   and contract.type == K.BID_HOKM
                   and trick.leadSuit and trick.leadSuit ~= contract.trump
                   and math.random() < 0.08 then
                    local sureRank = C.Rank(sureStopper)
                    -- Find a strictly lower-ranked legal that is also a
                    -- winner (so the trick is still ours).
                    local rankIdx = {}
                    do
                        local i = 1
                        for _, r in ipairs(K.RANK_PLAIN or { "7","8","9","J","Q","K","T","A" }) do
                            rankIdx[r] = i; i = i + 1
                        end
                    end
                    local sureIdx = rankIdx[sureRank] or 0
                    local altWinner = nil
                    for _, c in ipairs(legal) do
                        local cIdx = rankIdx[C.Rank(c)] or 0
                        if c ~= sureStopper
                           and C.Suit(c) == trick.leadSuit
                           and C.Rank(c) ~= "A" and C.Rank(c) ~= "J"
                           and cIdx > 0 and cIdx < sureIdx then
                            -- Verify it's still a winner (in `winners`).
                            for _, w in ipairs(winners) do
                                if w == c then altWinner = c; break end
                            end
                            if altWinner then break end
                        end
                    end
                    -- Last gate: pos-3 (partner) and pos-4 (opp) not
                    -- KNOWN void in led suit — deception requires they
                    -- can't ruff our lower winner.
                    if altWinner then
                        local partnerSeat = R.Partner(seat)
                        -- v1.6.0-hotfix (meta-audit): seat-math here is
                        -- correct but original variable was misnamed
                        -- `opp4`. At pos-2, partner is pos-4 (across
                        -- the table) and the OPP between us and partner
                        -- is pos-3 (next seat in trick rotation). The
                        -- defensive fallback handles the rare seat-3
                        -- vs partner edge.
                        local pos3Opp = (seat % 4) + 1     -- pos-3 in trick order = opp
                        if pos3Opp == partnerSeat then pos3Opp = (partnerSeat % 4) + 1 end
                        local pVoid = Bot._memory and Bot._memory[partnerSeat]
                                      and Bot._memory[partnerSeat].void
                                      and Bot._memory[partnerSeat].void[trick.leadSuit]
                        local oVoid = Bot._memory and Bot._memory[pos3Opp]
                                      and Bot._memory[pos3Opp].void
                                      and Bot._memory[pos3Opp].void[trick.leadSuit]
                        if not pVoid and not oVoid then
                            return altWinner   -- deception fires
                        end
                    end
                end
                if sureStopper then return sureStopper end
                -- v1.4.6 NOTE preserved: pure-probability pos-2 deviation
                -- (the v1.4.5 18%/25% breaker on non-take cases) remains
                -- removed. The v1.6.0 hand-shape breaker above is opt-in
                -- on the TAKE side only — when we're already winning the
                -- trick, just with a different card. Random "duck when
                -- you should take" is still excluded as «غلط».
                --
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
                -- v1.4.1 (Concern 4 — Takbeer/Tasgheer certainty
                -- gate, decision-trees.md rows 123-128, videos 21/22/23):
                -- M3lm+ pos-3 partner-certain Takbeer extension.
                -- Existing pos-3 logic (below) already does
                -- "highestByRank(winners)" — implicit Takbeer when WE
                -- have a winner. The certainty gate adds: when
                -- PARTNER is certain winner (pos-4 known void in led
                -- suit, Sun contract) AND we have NO winners
                -- ourselves, play highest LOSER from led suit (or
                -- highest non-trump if void). This donates points to
                -- partner's winning pile that the default
                -- low-loser fallback would discard.
                --
                -- Caveats per videos:
                --   * Sun-only (Hokm trump-led has different conventions)
                --   * Pos-4 void verified via Bot._memory[pos4].void
                --   * Skip if we're a STRONG suit holder ourselves
                --     (don't burn our own future winners). Heuristic:
                --     skip the donate if our highest card is A or T.
                --
                -- "Behavior is not off" gate: this fires ONLY when the
                -- existing winners-based Takbeer can't (no winners),
                -- so it's a pure addition to previously-default-low
                -- behavior. Doesn't override the existing logic.
                if Bot.IsM3lm and Bot.IsM3lm()
                   and contract.type == K.BID_SUN
                   and partnerWinning and #winners == 0
                   and trick.leadSuit and Bot._memory then
                    local pos4Seat = (seat % 4) + 1
                    local pos4Mem = Bot._memory[pos4Seat]
                    local pos4Void = pos4Mem and pos4Mem.void
                                     and pos4Mem.void[trick.leadSuit]
                    if pos4Void then
                        -- Partner-certain: pos-4 cannot follow led
                        -- suit, can't beat partner. Donate highest.
                        -- Filter: don't play A or T (preserve own
                        -- strong-suit winners for future tricks).
                        local donate = nil
                        local donateRank = -1
                        for _, c in ipairs(legal) do
                            local r = C.Rank(c)
                            if r ~= "A" and r ~= "T" then
                                local cr = C.TrickRank(c, contract)
                                if cr > donateRank then
                                    donate = c
                                    donateRank = cr
                                end
                            end
                        end
                        if donate then return donate end
                    end
                end
                -- v1.4.4 (pos-3 hold-back — psychological bait, video #20).
                -- «تخليه يمسك» — let opp think they're holding the suit;
                -- you ambush next round. Saudi-pro convention; the Sun
                -- variant of "hold the شايب in reserve."
                --
                -- This is a CONTAINED-RISK heuristic:
                -- * Math: roughly breakeven on point-count vs default
                --   take-with-K. Worst case ~-1 trick if pos-4 over-tops
                --   our partner's mid lead with Q/J unexpectedly.
                -- * Real value: "INFORMATION WARFARE" — opp observing the
                --   bot duck with low after partner's mid lead reads
                --   "bot has nothing in this suit", corrupting their
                --   hand-distribution model for the rest of the round.
                --   Against humans, this also creates re-lead bait
                --   (~55% probability opp re-leads suit they "won").
                -- * Containment: 9 conditions ensure the rule fires
                --   only when risk is bounded — non-clutch score, mid-
                --   round, alternative strength elsewhere, pos-4 not
                --   known to hold A.
                -- * Tier-graded fire: 30% M3lm, 40% Saudi Master.
                --   Master is more aggressive on psychological reads
                --   per bot-personalities.md tier spec.
                if Bot.IsM3lm and Bot.IsM3lm()
                   and contract.type == K.BID_SUN
                   and trick.leadSuit and trick.plays and #trick.plays >= 2
                   and #winners > 0 then
                    -- C1 gating block: collect preconditions.
                    local lead = trick.leadSuit
                    local partner = R.Partner(seat)
                    local pos1 = trick.plays[1]
                    local pos2 = trick.plays[2]
                    -- C3: partner led mid card (rank 8/9/J/Q).
                    -- v1.4.4 (multi-perspective audit fix per ruflo):
                    -- expanded from "9 or J only" to "8/9/J/Q". Both
                    -- 8 (low-mid) and Q (just-below-K) preserve the
                    -- "partner currently winning + bot K beats partner"
                    -- structure. The narrower 9/J-only gate created
                    -- a recognizable pattern gap that an M3lm-tier opp
                    -- could exploit by probing partner-led-8 tricks.
                    local partnerLed = (pos1 and pos1.seat == partner)
                    local pos1Rank = pos1 and C.Rank(pos1.card) or nil
                    local partnerLedMid = (pos1Rank == "8" or pos1Rank == "9"
                                           or pos1Rank == "J" or pos1Rank == "Q")
                    -- C4: opp pos-2 played LOWER than partner's lead
                    -- (partner currently winning)
                    local pos2Lower = false
                    if pos2 and pos1 and partnerLed then
                        local p1tr = C.TrickRank(pos1.card, contract)
                        local p2tr = C.TrickRank(pos2.card, contract)
                        local pos2InLead = (C.Suit(pos2.card) == lead)
                        pos2Lower = (not pos2InLead) or (p2tr < p1tr)
                    end
                    -- C5: bot holds K of led + ≥1 low (7/8/9) of led
                    local hasK, lowCard = false, nil
                    local lowRank = -1
                    for _, c in ipairs(legal) do
                        if C.Suit(c) == lead then
                            local r = C.Rank(c)
                            if r == "K" then hasK = true
                            elseif r == "7" or r == "8" or r == "9" then
                                local cr = C.TrickRank(c, contract)
                                if cr > lowRank then
                                    lowCard = c; lowRank = cr
                                end
                            end
                        end
                    end
                    -- C6: independent strength elsewhere — at least one
                    -- A in another suit, OR a 3+-card non-trump suit
                    -- elsewhere (we're not betting the round on this K)
                    local hasIndependentStrength = false
                    if hasK and lowCard then
                        local sCount = { S = 0, H = 0, D = 0, C = 0 }
                        for _, c in ipairs(legal) do
                            local r, su = C.Rank(c), C.Suit(c)
                            if su ~= lead then
                                sCount[su] = sCount[su] + 1
                                if r == "A" then
                                    hasIndependentStrength = true
                                end
                            end
                        end
                        if not hasIndependentStrength then
                            for _, su in ipairs({ "S", "H", "D", "C" }) do
                                if sCount[su] >= 3 then
                                    hasIndependentStrength = true; break
                                end
                            end
                        end
                    end
                    -- C7: trick number 2-5 (mid-round window)
                    local trickN = #(S.s.tricks or {}) + 1
                    local midRound = (trickN >= 2 and trickN <= 5)
                    -- C8: score non-clutch (both teams below target-26)
                    local nonClutch = true
                    if S.s.cumulative and S.s.target then
                        local target = S.s.target
                        if (S.s.cumulative.A or 0) >= target - 26
                           or (S.s.cumulative.B or 0) >= target - 26 then
                            nonClutch = false
                        end
                    end
                    -- C9 (v1.4.8 audit HIGH-3 fix): pos-4 confirmed
                    -- UNABLE to beat partner's lead. Pre-fix this used
                    -- a weak `pos4HasA = false` predicate that treated
                    -- unknown as "no A," making the rule MORE likely
                    -- to fire when memory was sparse — exact opposite
                    -- of safe. Real Saudi-pro hold-back is:
                    -- "let opp think they hold the suit" — only
                    -- meaningful when partner DEFINITELY wins this
                    -- trick. If pos-4 can over-take partner's mid
                    -- lead with their A/Q/J, the saved K bought
                    -- nothing and the trick is just lost.
                    --
                    -- Strict gate: pos-4 must be CONFIRMED VOID in
                    -- led suit (Bot._memory[pos4].void[lead] = true)
                    -- to fire the hold-back. In Sun, void means pos-4
                    -- can't follow → can't beat partner. (In Hokm
                    -- void = ruff threat, but this whole block is
                    -- contract.type == K.BID_SUN gated above.)
                    local pos4Seat = (seat % 4) + 1
                    local pos4CannotBeat = false
                    if Bot._memory and Bot._memory[pos4Seat]
                       and Bot._memory[pos4Seat].void
                       and Bot._memory[pos4Seat].void[lead] then
                        pos4CannotBeat = true
                    end
                    -- All conditions satisfied → probabilistic fire
                    local fireRate = 0.30
                    if Bot.IsSaudiMaster and Bot.IsSaudiMaster() then
                        fireRate = 0.40
                    end
                    if partnerLed and partnerLedMid and pos2Lower
                       and hasK and lowCard
                       and hasIndependentStrength
                       and midRound and nonClutch
                       and pos4CannotBeat
                       and math.random() < fireRate then
                        -- Hold-back FIRES: duck with the low, save K
                        -- for "next round" psychological play.
                        return lowCard
                    end
                end
                -- Highest winner so the 4th seat can't easily overcut.
                -- 13th-bot-audit fix: EXCEPT when the only winners are
                -- trump (forced ruff) — then ruff with the LOWEST trump
                -- to save the J / 9 / A for forcing leads. Wasting the
                -- J of trump on a 7-of-side-suit ruff is a classic
                -- give-back; bot must conserve high trump.
                if #winners == 0 then
                    -- No winner; fall through to default loser pick.
                else
                    if contract.type == K.BID_HOKM and contract.trump then
                        local trumpWinners = {}
                        for _, c in ipairs(winners) do
                            if C.IsTrump(c, contract) then
                                trumpWinners[#trumpWinners + 1] = c
                            end
                        end
                        if #trumpWinners > 0 and #trumpWinners == #winners then
                            -- v1.5.0 (audit follow-up — Hokm trump
                            -- adjacency, video #22 R1+R3+R8):
                            -- consecutive trump winners → play HIGHEST
                            -- (R1: top-down for partner read). Non-
                            -- consecutive → play LOWEST (R3: preserve
                            -- top trump as re-entry, opp will burn
                            -- shape mid-trumps to capture).
                            -- Trump rank order is non-natural
                            -- (J>9>A>T>K>Q>8>7); use K.RANK_TRUMP_HOKM.
                            if #trumpWinners == 2 then
                                local r1 = K.RANK_TRUMP_HOKM[C.Rank(trumpWinners[1])] or 0
                                local r2 = K.RANK_TRUMP_HOKM[C.Rank(trumpWinners[2])] or 0
                                if math.abs(r1 - r2) == 1 then
                                    -- Consecutive: play highest (R1)
                                    return highestByRank(trumpWinners, contract)
                                end
                            end
                            -- 1 winner OR 3+ winners OR non-consecutive
                            -- pair: play lowest (R3 — conserve top trump).
                            return lowestByRank(trumpWinners, contract)
                        end
                    end
                    return highestByRank(winners, contract)
                end
            end
        end
        -- v0.5.1 C-4: last-trick targeting. On trick 8 the cheapest
        -- winner is wrong — there's no future trick to save the
        -- higher card for, and LAST_TRICK_BONUS (+10) plus face-value
        -- captures more total points. Default / pos 4 / no advanced
        -- behavior elsewhere remains "cheapest winner".
        local trickNum = #(S.s.tricks or {}) + 1
        if trickNum == 8 then
            -- v0.11.19 audit M5: bidder-team make-the-bid awareness
            -- on trick 8. Pre-fix highestByFaceValue picked maximum
            -- per-trick face value, but if our team is the BIDDER and
            -- the current trick win is BORDERLINE (we need this trick
            -- + last-trick bonus to reach the make-threshold), maximize
            -- trick-WINNING probability over face-value. highestByRank
            -- picks the highest TrickRank — most over-trump-resistant
            -- — even if it sacrifices a few face-value points.
            -- Specifically: bidder team at 60-80 raw points without
            -- this trick = trick 8 is a make-or-break swing.
            -- v0.11.19-hotfix F1 (post-ship audit Agent 3): the v0.11.19
            -- M5 ship referenced `isBidderTeam` and `myTeam` as if they
            -- were locals in pickFollow, but those names exist only in
            -- pickLead. In Lua 5.1 the unbound names resolved to nil
            -- globals; `if nil and ...` short-circuited; M5 never
            -- fired. AD.6 source-pin passed because it only checked
            -- the literal `target = ...` line was in source. Now
            -- compute these locally inside pickFollow.
            local m5_myTeam = R.TeamOf(seat)
            local m5_oppTeam = (m5_myTeam == "A") and "B" or "A"
            local m5_isBidderTeam = (contract.bidder
                and m5_myTeam == R.TeamOf(contract.bidder)) or false
            -- v1.0.6 (N3): M5 meld-aware target.
            -- v1.0.9 (A#1 hotfix): two corrections to v1.0.6 N3:
            --   (a) ALGEBRA: the bidder-makes inequality is
            --       `(myMeld + ourTrickRaw) > (oppMeld + oppTrickRaw)`.
            --       With ourTrickRaw + oppTrickRaw = handTotal (constant),
            --       this solves to `ourTrickRaw > baseTarget +
            --       (oppMeld - myMeld) / 2`. v1.0.6 used the full
            --       (oppMeld - myMeld) without dividing by 2 — off
            --       by 2x.
            --   (b) WINNER-TAKES-ALL: R.CompareMelds (Rules.lua) gives
            --       ALL meld points to the comparison-WINNER. We must
            --       consult CompareMelds to know which team actually
            --       gets the meld bonus before computing the threshold
            --       delta. Pre-fix code assumed both teams kept their
            --       own melds — wrong.
            -- Belote (+20 K+Q-of-trump same-seat) is awarded
            -- INDEPENDENTLY of the meld comparison (Rules.lua:824-839),
            -- so it doesn't go through CompareMelds. We treat Belote
            -- separately: include it in whichever team holds it.
            local m5_meldA_raw = (R.SumMeldValue and S.s.meldsByTeam
                                   and R.SumMeldValue(S.s.meldsByTeam.A)) or 0
            local m5_meldB_raw = (R.SumMeldValue and S.s.meldsByTeam
                                   and R.SumMeldValue(S.s.meldsByTeam.B)) or 0
            -- Apply CompareMelds: only the winning team gets meld
            -- points (the loser's are zeroed). If CompareMelds returns
            -- nil/0/no-winner, both teams keep their declared values
            -- (defensive — shouldn't happen with well-formed input).
            -- v1.0.9 audit MED-2: pass S.s.dealer so the tied-rank
            -- branch resolves via PDF Rule 2 (dealer-right priority)
            -- the same way R.ScoreRound does at round-end. Pre-fix
            -- M5 saw "tie" → kept both teams' melds while ScoreRound
            -- resolved to one team — mis-estimating the M5 target by
            -- up to (oppMeld)/2 in tied scenarios.
            local meldWinner = (R.CompareMelds and S.s.meldsByTeam
                                and R.CompareMelds(
                                    S.s.meldsByTeam.A or {},
                                    S.s.meldsByTeam.B or {},
                                    contract or {},
                                    S.s.dealer))
                               or nil
            local m5_meldA = m5_meldA_raw
            local m5_meldB = m5_meldB_raw
            if meldWinner == "A" then
                m5_meldB = 0
            elseif meldWinner == "B" then
                m5_meldA = 0
            end
            local m5_myMeld  = (m5_myTeam == "A") and m5_meldA or m5_meldB
            local m5_oppMeld = (m5_oppTeam == "A") and m5_meldA or m5_meldB
            -- v1.0.10 (audit pass-2 A MED-1 / B LOW-1): fold Belote into
            -- the M5 target. Belote (+20 raw to K+Q-of-trump-same-seat
            -- holder) is awarded INDEPENDENTLY of CompareMelds — added
            -- post-mult to whichever team has the holder. Pre-v1.0.10
            -- M5 ignored Belote entirely; with opp holding Belote the
            -- effective target was off by +10 raw (Belote/2 in the
            -- algebraic mirror, see derivation at line ~4255). Cancellation
            -- by ≥100 meld matches Rules.lua's R.IsBeloteCancelled — if
            -- the K+Q holder's TEAM has a ≥100 meld, Belote is subsumed.
            -- Mirrors Rules.lua:864-879 scan logic. Hokm-only.
            local m5_beloteTeam
            if contract.type == K.BID_HOKM and contract.trump and S.s.tricks then
                local m5_kWho, m5_qWho
                for _, t in ipairs(S.s.tricks) do
                    for _, p in ipairs(t.plays or {}) do
                        if C.Suit(p.card) == contract.trump then
                            if C.Rank(p.card) == "K" then m5_kWho = p.seat end
                            if C.Rank(p.card) == "Q" then m5_qWho = p.seat end
                        end
                    end
                end
                if m5_kWho and m5_qWho and m5_kWho == m5_qWho then
                    m5_beloteTeam = R.TeamOf(m5_kWho)
                    if R.IsBeloteCancelled and S.s.meldsByTeam
                       and R.IsBeloteCancelled(m5_beloteTeam, S.s.meldsByTeam) then
                        m5_beloteTeam = nil
                    end
                end
            end
            local m5_myBelote  = (m5_beloteTeam == m5_myTeam)  and (K.MELD_BELOTE or 20) or 0
            local m5_oppBelote = (m5_beloteTeam == m5_oppTeam) and (K.MELD_BELOTE or 20) or 0
            if m5_isBidderTeam and S.s.tricks then
                local raw = 0
                for _, t in ipairs(S.s.tricks) do
                    if R.TeamOf(t.winner) == m5_myTeam then
                        for _, p in ipairs(t.plays or {}) do
                            raw = raw + (C.PointValue(p.card, contract) or 0)
                        end
                    end
                end
                local baseTarget = (contract.type == K.BID_SUN) and 65 or 81
                -- v1.0.9 (A#1) algebra fix: divide meld delta by 2.
                -- The full inequality solves to ourTrickRaw > baseTarget
                -- + (oppMeld - myMeld) / 2. Floor-divide for integer
                -- target since the LHS is integer trick-raw.
                -- v1.0.10 (audit pass-2): also fold Belote into target —
                -- same algebraic mirror, +20 raw to the holder's team.
                local target = baseTarget
                                + math.floor((m5_oppMeld - m5_myMeld) / 2)
                                + math.floor((m5_oppBelote - m5_myBelote) / 2)
                -- Make-or-break: 0 < (target - raw) <= ~30 (current
                -- trick can swing make-fail boundary). Favor trick-rank
                -- over face-value to lock the last trick.
                local gap = target - raw
                if gap > 0 and gap <= 30 then
                    return highestByRank(winners, contract)
                end
            end
            -- v1.0.4 (agent #7): M5 defender mirror. Defender team's
            -- primary goal #2 (decision-trees.md Section 7) is to FORCE
            -- BIDDER FAIL.
            -- v1.0.6 (N6): off-by-one fix. Saudi rule per CLAUDE.md
            -- and Rules.lua: bidder fails on tied half-and-half.
            -- Defender at exactly 81 raw (Hokm) or 65 raw (Sun)
            -- ALREADY forces bidder fail (bidder ties → bidder
            -- fails). Pre-v1.0.6 the code used target+1 thinking
            -- defender needed strict-majority +1; that was wrong
            -- by Saudi rule (defender wins on tie too). Drop the
            -- `+1` so the band aligns with the bidder mirror.
            -- Plus N3 meld-aware target: defender's effective target
            -- is baseTarget - oppMeld + myMeld (defender NEEDS that
            -- much raw to overcome opp-meld + base-target threshold).
            if not m5_isBidderTeam and contract.bidder and S.s.tricks then
                local raw = 0
                for _, t in ipairs(S.s.tricks) do
                    if R.TeamOf(t.winner) == m5_myTeam then
                        for _, p in ipairs(t.plays or {}) do
                            raw = raw + (C.PointValue(p.card, contract) or 0)
                        end
                    end
                end
                local baseTarget = (contract.type == K.BID_SUN) and 65 or 81
                -- v1.0.9 (A#1): divide meld delta by 2; CompareMelds
                -- winner-takes-all already applied above. Defender
                -- needs raw >= baseTarget + (oppMeld - myMeld)/2 to
                -- overcome bidder's meld+base advantage.
                -- (mirror of bidder formula; we're the "defender" team
                -- so opp is the bidder team — meld accounting flips
                -- accordingly via m5_oppMeld and m5_myMeld).
                -- v1.0.10 (audit pass-2): Belote folded the same way.
                local defenderTarget = baseTarget
                                       + math.floor((m5_oppMeld - m5_myMeld) / 2)
                                       + math.floor((m5_oppBelote - m5_myBelote) / 2)
                local gap = defenderTarget - raw
                if gap > 0 and gap <= 30 then
                    return highestByRank(winners, contract)
                end
            end
            return highestByFaceValue(winners, contract)
        end
        -- v1.1.0 (audit unpredictability HIGH-2): deceptiveOverplay
        -- (video #08 "smart move"). When pos-4 in Sun with multiple
        -- winners in the led suit, sometimes play a HIGHER winner
        -- instead of the cheapest — to confuse opp's read on our
        -- remaining holdings. Pros use this sparingly to corrupt
        -- opp's prior on our suit strength: video #08 verbatim
        -- «راح تلعب اكبر ورقه موجوده عندك فبالتالي راح تلعب الشايب
        --  ... ليش لعبت الشايب ايش الهدف من هذه الحركه ... ما
        --  يسويها الا واحد محترف في البلد» — "the move only a
        -- country pro does." Anti-triggers: tahreeb signal active
        -- (preserve hand integrity for partner coordination); not
        -- the absolute-pinned cards (K+Q of trump are Belote).
        -- M3lm-gated. ~40% probabilistic so opp can't read the
        -- counter-tell either.
        -- v1.2.1 (A1 audit): extend deceptiveOverplay to Hokm with
        -- explicit J/9-of-trump anti-trigger. Per video #08 lines
        -- 168-198 the deceptive-overplay rule applies to Hokm too —
        -- BUT in Hokm, J and 9 of trump are «تقريبا نفس الاكه»
        -- (≈ AKA-equivalent / the canonical kill cards). Sacrificing
        -- them as a "smart move" is anti-pro; the Hokm sacrifice
        -- card must be «ما تحت التسعه والولد» (below 9 and J).
        -- Sun fires at ~40% (existing), Hokm at ~25% (lower since
        -- the burn cost is real), with explicit J/9 trump exclusion.
        -- v1.2.1 (G5+A1 wiring): also suppresses when opp inferred
        -- to hold cover in led suit (oppHighInferred).
        if Bot.IsM3lm and Bot.IsM3lm() and #winners >= 2 then
            local isSun = (contract.type == K.BID_SUN)
            local isHokm = (contract.type == K.BID_HOKM)
            if isSun or isHokm then
                local lowWin = lowestByRank(winners, contract)
                local lowSuit = C.Suit(lowWin)
                local lowRank = C.TrickRank(lowWin, contract)
                local higher = {}
                for _, c in ipairs(winners) do
                    if c ~= lowWin and C.Suit(c) == lowSuit
                       and C.TrickRank(c, contract) > lowRank then
                        -- v1.2.1 A1 anti-trigger: in Hokm, NEVER
                        -- sacrifice J or 9 of trump (video #08
                        -- explicit — they are the canonical kill
                        -- cards, AKA-equivalent in trump).
                        if isHokm and C.Suit(c) == contract.trump
                           and (C.Rank(c) == "J" or C.Rank(c) == "9") then
                            -- skip — never burn a trump killer
                        else
                            higher[#higher + 1] = c
                        end
                    end
                end
                if #higher > 0 then
                    local partner = R.Partner(seat)
                    local pStyle = Bot._partnerStyle
                                    and Bot._partnerStyle[partner]
                    -- v1.3.1 (deadSignal-3 audit fix): pre-fix this
                    -- iterated `pairs(pStyle.tahreebSent)` and tested
                    -- `evt.flavor` — but tahreebSent[suit] is a raw
                    -- rank-list array (e.g. {"7","9"}), NOT a flavor
                    -- object. `.flavor` was always nil, `tahreebActive`
                    -- was permanently false, deceptive-overplay
                    -- suppression NEVER fired. The other 3 callers
                    -- (Bot.lua:2696, 2775, 5317, 5358) correctly use
                    -- `tahreebClassify(tahreebSent[su])` per-suit;
                    -- mirror that pattern here.
                    local tahreebActive = false
                    if pStyle and pStyle.tahreebSent then
                        for _, su in ipairs({ "S", "H", "D", "C" }) do
                            local cls = tahreebClassify(pStyle.tahreebSent[su])
                            if cls == "want" or cls == "bargiya" then
                                tahreebActive = true; break
                            end
                        end
                    end
                    -- v1.2.1 (G5+A1): suppress when opp inferred to
                    -- hold cover in this suit (their tanfeer signaled
                    -- high cards held). Burning a non-low here would
                    -- collide with the opp's outs.
                    local oppHigh = false
                    local mem = Bot._memory and Bot._memory[seat]
                    if mem and mem.oppHighInferred
                       and mem.oppHighInferred[lowSuit] then
                        oppHigh = true
                    end
                    -- Probabilistic fire: 40% Sun, 25% Hokm.
                    local fireProbability = isSun and 0.40 or 0.25
                    if not tahreebActive and not oppHigh
                       and math.random() < fireProbability then
                        -- Pick the deceptive overplay card. Prefer
                        -- the "Shayb" (J of non-trump suit, since
                        -- trump-J is excluded above) per video #08.
                        --
                        -- v1.4.0 (T-sacrifice tier-gate audit fix):
                        -- pre-fix, if no J was in `higher` the fallback
                        -- picked a random card from `higher` — which
                        -- could be the T (10) of the led suit. Per
                        -- bot-personalities.md:161, T-sacrifice is
                        -- "Saudi Master ONLY" ("only a real pro plays
                        -- this"). At M3lm and Fzloky tiers, the
                        -- T-sacrifice fallback violated the tier-spec.
                        -- Now: if no J found, only Saudi Master tier
                        -- proceeds with the higher[] random fallback;
                        -- lower tiers fall through to the canonical
                        -- non-deceptive play below.
                        for _, c in ipairs(higher) do
                            if C.Rank(c) == "J" then return c end
                        end
                        if Bot.IsSaudiMaster and Bot.IsSaudiMaster() then
                            return higher[math.random(#higher)]
                        end
                        -- Lower tiers: skip T-sacrifice fallback,
                        -- fall through to canonical play.
                    end
                end
            end
        end
        -- v1.1.1 (L2 audit): opp-Bargiya ruff override. When opp
        -- Bargiya'd suit X (signaled their partner to lead X back),
        -- and now opp's partner HAS led X, and we're must-ruffing
        -- (legal is trump-only because we're void in X), pick a
        -- HIGH trump (boss-grade) instead of cheapest winner. Per
        -- video #19: opp Bargiya = ruff-X-if-possible trigger;
        -- using a low trump risks opp's K/A-of-X getting through
        -- a partner overtrump — high ruff guarantees the kill.
        -- Hokm-only (Sun has no trump).
        if Bot.IsAdvanced() and contract.type == K.BID_HOKM
           and contract.trump and trick.leadSuit
           and trick.leadSuit ~= contract.trump
           and Bot._memory and Bot._memory[seat]
           and Bot._memory[seat].opponentBargiyaSuit
           and Bot._memory[seat].opponentBargiyaSuit[trick.leadSuit] then
            -- Are we void in led-suit (must-ruffing)?
            local hasLead = false
            for _, c in ipairs(legal) do
                if C.Suit(c) == trick.leadSuit then hasLead = true; break end
            end
            if not hasLead then
                -- Pick the HIGHEST winner (high ruff) — burns trump
                -- but defeats opp's intended runner-back decisively.
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
            -- v1.1.0 (audit partner-coord H6): preserve secondary
            -- winners in partner's declared sequence-meld suit. If
            -- partner declared a 50/100 meld in suit Y, partner has
            -- the meld cards (T-J-Q-K or J-Q-K-A range); our high
            -- cards in Y are SECONDARY winners that pair with
            -- partner's eventual lead-back. Don't dump them as
            -- Tahreeb-fodder. Filter discardable to non-meld-suit
            -- cards if we have any.
            local meldSuit
            if S.s.meldsByTeam then
                local partner = R.Partner(seat)
                local pTeam = R.TeamOf(partner)
                for _, m in ipairs(S.s.meldsByTeam[pTeam] or {}) do
                    if m.declaredBy == partner and m.kind
                       and m.kind:sub(1, 3) == "seq" and m.suit
                       and m.suit ~= contract.trump then
                        meldSuit = m.suit
                        break
                    end
                end
            end
            if meldSuit then
                local nonMeldDiscards = {}
                for _, c in ipairs(discardable) do
                    -- Keep only non-meld-suit OR low-value meld-suit
                    -- cards (Q+ in meld suit is "secondary winner",
                    -- preserve; 7/8/9/T below partner's meld floor
                    -- safe to dump).
                    local r = C.Rank(c)
                    local isHighInMeld = (C.Suit(c) == meldSuit)
                                          and (r == "A" or r == "K" or r == "Q")
                    if not isHighInMeld then
                        nonMeldDiscards[#nonMeldDiscards + 1] = c
                    end
                end
                if #nonMeldDiscards > 0 then
                    return lowestByRank(nonMeldDiscards, contract)
                end
            end
            -- v1.2.1 (G2 audit): receiver-side T/A preservation in
            -- partner's tahreeb-want/bargiya suit. Per video #02
            -- «اذا كانت العشره معاها ورقتين ... الافضل انك ما تروح
            -- بالعشره وتتهور لا تروح بالثمانيه»: receiver who saw
            -- partner Tahreeb suit X must HOLD the cover-grade card
            -- in X for the lead-back; dumping the T or A of X on a
            -- non-X discard destroys partner's plan. Filter
            -- discardable to exclude T/A in any non-trump suit
            -- where partner emitted want/bargiya.
            local tahreebSuit
            if Bot.IsM3lm and Bot.IsM3lm() and Bot._partnerStyle then
                local partner = R.Partner(seat)
                local pStyle = Bot._partnerStyle[partner]
                if pStyle and pStyle.tahreebSent
                   and Bot.IsBotSeat(partner) then
                    for _, su in ipairs(shuffledSuits()) do
                        if su ~= contract.trump then
                            local cls = tahreebClassify(pStyle.tahreebSent[su])
                            if cls == "bargiya" or cls == "want" then
                                tahreebSuit = su; break
                            end
                        end
                    end
                end
            end
            if tahreebSuit then
                local nonTahreebDiscards = {}
                for _, c in ipairs(discardable) do
                    local r = C.Rank(c)
                    local isHighInTahreeb = (C.Suit(c) == tahreebSuit)
                                            and (r == "A" or r == "T")
                    if not isHighInTahreeb then
                        nonTahreebDiscards[#nonTahreebDiscards + 1] = c
                    end
                end
                if #nonTahreebDiscards > 0 then
                    return lowestByRank(nonTahreebDiscards, contract)
                end
            end
            -- v1.2.1 (G4 audit): preserve T/K of partner's AKA suit
            -- when partner ALSO emitted Bargiya/want in same suit.
            -- Per video #14 (Bargiya, lines 144-160) the lead-back
            -- holder keeps the next-down rank for partner's
            -- continuation. The "AKA-with-Bargiya" overlap means
            -- partner explicitly signaled they hold cover behind
            -- the AKA-claimed boss; dumping our T/K of that suit
            -- collides with their cover.
            local akaSuit
            if Bot._memory and Bot._memory[seat]
               and Bot._memory[seat].partnerAkaSuit then
                local pas = Bot._memory[seat].partnerAkaSuit
                local partner = R.Partner(seat)
                local pStyle = Bot._partnerStyle
                                and Bot._partnerStyle[partner]
                for _, su in ipairs(shuffledSuits()) do
                    if pas[su] and su ~= contract.trump then
                        -- Only preserve if Bargiya/want overlap.
                        if pStyle and pStyle.tahreebSent then
                            local cls = tahreebClassify(pStyle.tahreebSent[su])
                            if cls == "bargiya" or cls == "want" then
                                akaSuit = su; break
                            end
                        end
                    end
                end
            end
            if akaSuit then
                local nonAkaDiscards = {}
                for _, c in ipairs(discardable) do
                    local r = C.Rank(c)
                    local isHighInAka = (C.Suit(c) == akaSuit)
                                        and (r == "T" or r == "K")
                    if not isHighInAka then
                        nonAkaDiscards[#nonAkaDiscards + 1] = c
                    end
                end
                if #nonAkaDiscards > 0 then
                    return lowestByRank(nonAkaDiscards, contract)
                end
            end
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
    -- Mathlooth K-tripled (Sun, video #17 + video #20). M3lm-gated.
    -- When holding K + ≥2 lowers in led suit AND in tricks 1-3,
    -- exclude K from low-pick candidates — preserve K for trick 3+
    -- cash after A and T fall naturally. Plus pos-3 K-doubled bait
    -- (v1.1.1 «تمسك لون»): at pos-3 with K + 1 low when opp led
    -- LOW, decline to win; let opp take cheap, ambush with K
    -- later.
    --
    -- Note: v0.7.2 reverted an earlier v0.5.11 "dump HIGHEST under
    -- opp-winning" branch — the canonical Sun convention is
    -- Tasgheer (play smallest), handled by lowestByRank(legal) at
    -- the function's bottom. No Sun-specific branch needed at the
    -- general opp-winning fall-through.
    if Bot.IsM3lm() and contract.type == K.BID_SUN
       and trick.leadSuit and (#(S.s.tricks or {}) <= 2) then
        local lead = trick.leadSuit
        local suitCards = {}
        local hasK, kCard = false, nil
        for _, c in ipairs(legal) do
            if C.Suit(c) == lead then
                suitCards[#suitCards + 1] = c
                if C.Rank(c) == "K" then hasK = true; kCard = c end
            end
        end
        -- ≥3 same-suit AND we have K → K-tripled shape. Exclude K
        -- from the candidate pool so lowestByRank picks 7/8/9/J/Q.
        if hasK and #suitCards >= 3 then
            local nonK = {}
            for _, c in ipairs(legal) do
                if c ~= kCard then nonK[#nonK + 1] = c end
            end
            if #nonK > 0 then
                return lowestByRank(nonK, contract)
            end
        end
        -- v1.1.1 (L3 NEW): pos-3 K-doubled bait. We're 3rd-to-play
        -- in Sun; we hold K + 1 cover; opp led LOW (rank 9 or below
        -- in plain card order — i.e., 7/8/9). Don't burn K to win
        -- the cheap trick: duck low, save K for the trick where A
        -- and T have fallen and our K becomes top-live.
        local pos = (trick.plays and #trick.plays + 1) or 1
        if hasK and #suitCards == 2 and pos == 3 and trick.plays
           and trick.plays[1] then
            local leadCard = trick.plays[1].card
            local leadRank = C.Rank(leadCard)
            -- "Low" lead = rank 9 or below in plain order
            -- (Sun K=6, J=4, 9=3, 8=2, 7=1; "low" = 7/8/9).
            if leadRank == "7" or leadRank == "8" or leadRank == "9" then
                local nonK = {}
                for _, c in ipairs(legal) do
                    if c ~= kCard then nonK[#nonK + 1] = c end
                end
                if #nonK > 0 then
                    return lowestByRank(nonK, contract)
                end
            end
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
            for _, su in ipairs(shuffledSuits()) do
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

    -- v1.1.0 (audit unpredictability HIGH-5): tasgheer near-lowest
    -- variance. Pre-fix the bot's losing-side dump was always the
    -- absolute lowest — a careful human reads "K-play implies no
    -- Q/J/9/8/7 below it" with 100% confidence (video #05 verbatim
    -- «بنسبه كبيره جدا ما عنده الاكه بنسبه ٩٠%»). Pros occasionally
    -- mis-tasgheer to corrupt opp's reads.
    --
    -- v1.2.1 (A8 audit): desync clutch constants from AKA-withhold
    -- (which uses 22/18) and tasgheer (now 26/22) so the
    -- synchronized-silence-as-tell pattern breaks. Plus shrink-not-
    -- zero variance in clutch — keep ~3% (was 0%) so the late-
    -- round-locked tell becomes noisy. M3lm+ gating preserved.
    if Bot.IsM3lm and Bot.IsM3lm() and #legal >= 2
       and S.s.cumulative then
        local myTeam = R.TeamOf(seat)
        local meCum = S.s.cumulative[myTeam] or 0
        local oppCum = S.s.cumulative[(myTeam == "A") and "B" or "A"] or 0
        local target = S.s.target or 152
        -- v1.2.2 (P1-3 audit fix): A8 race-gap pair was promised in
        -- v1.2.1 ("26/22") but only `clutchDist=26` was wired; the
        -- raceGap term was missing. Now: distinct from AKA-withhold's
        -- (22/18) — tasgheer uses (26/22) so the synchronized-silence
        -- pattern fully breaks across both branches.
        local clutch = (oppCum >= target - 26) or (meCum >= target - 26)
                       or (math.abs(oppCum - meCum) <= 22)
        local prob = clutch and 0.03 or 0.07
        if math.random() < prob then
            local sorted = {}
            for _, c in ipairs(legal) do sorted[#sorted + 1] = c end
            table.sort(sorted, function(a, b)
                return C.TrickRank(a, contract) < C.TrickRank(b, contract)
            end)
            -- Don't fire if 2nd-lowest is dramatically higher
            -- (it's a real winner, not a near-lowest substitute).
            local lowR = C.TrickRank(sorted[1], contract)
            local secondR = C.TrickRank(sorted[2], contract)
            if secondR - lowR <= 3 then
                return sorted[2]
            end
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
    -- v1.1.0 (audit partner-coord H2): REMOVED the IsBotSeat(partner)
    -- gate. Pre-fix the bot suppressed AKA whenever its teammate was
    -- human, citing "humans don't recognize the AKA banner". But video
    -- 18's 4 hard preconditions don't list partner-tier; AKA is a
    -- canonical Saudi VOCAL signal («اذا انت متاكد انه فعلا هذه
    -- العشره فعلا اكبر ورقه موجوده... لازم تقول اكه») that even a
    -- human teammate can read once they see the banner. Suppression
    -- on tier was a UX over-conservatism — a "Saudi-flavor bot" that
    -- never AKA's because partner is human is the OPPOSITE of Saudi
    -- flavor. The existing precondition (f) at line below (partner-
    -- void-in-trump check) already handles the case where AKA is
    -- coordinationally meaningless.
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
    -- v0.11.16 audit H-1: trick-1 AKA suppression DROPPED. Per
    -- signals.md Section 4 ("AKA at trick-1 or trick-2 is the
    -- strongest read") and decision-trees.md Section 6 (canonical
    -- Saudi convention recognizes trick-1/2 AKAs as the most
    -- meaningful window), the prior heuristic was inverted: trick-1
    -- AKA on K/Q/J of side suits IS the highest-EV announcement. The
    -- prior comment "no opponent has shown a void yet" misframed the
    -- mechanism — partner's must-ruff obligation kicks in regardless
    -- of opp voids; the AKA is what cancels it. The partner-certainly-
    -- void-in-trump gate below already covers the case where AKA
    -- carries zero coordination value. Pre-v0.11.16 bots played
    -- "without AKA" half the time it would matter. The trickNum is
    -- still computed for the trick-6+ clutch-only gate at line ~3590.
    local trickNum = #(S.s.tricks or {}) + 1
    -- v0.9.1 AKA precondition (f) (audit AUDIT_REPORT_v0.7.1.md
    -- missing item #5, decision-trees.md Section 6 row "preconditions"
    -- subitem (f)): NOT (partner certainly void in trump). The whole
    -- point of AKA is to ask partner to defer the ruff (let our boss
    -- take the trick). If partner is OBSERVED void in trump, they
    -- can't ruff anyway — the signal carries zero coordination value
    -- and just leaks info to opponents who can read the banner.
    -- Suppress.
    do
        local partner = R.Partner(seat)
        local pmem = Bot._memory and Bot._memory[partner]
        if pmem and pmem.void and pmem.void[trump] then
            return nil
        end
    end

    -- v0.10.2 AKA doubled-contract conservatism (review_v0.10.0
    -- xref_X2_aka.md B3 / G18-10 paragraph 2). G18-10 explicitly
    -- distinguishes regular vs doubled hands: "اللعب طبيعي مش
    -- دبل" = early permissiveness applies in NORMAL play, not
    -- doubled. The inverse — "doubled ⇒ tighten AKA" — is the
    -- Saudi pro convention. With Bel/Triple/Four in play, both
    -- sides are extra-motivated to read every signal and exploit
    -- info-leaks; the AKA banner's coordination value drops while
    -- its leakage cost rises.
    --
    -- v1.2.0 (audit transcript H3): nuanced uncertainty gate.
    -- Pre-v1.2.0 ALL doubled rounds blanket-suppressed AKA. Per
    -- video #18 «اذا انت متاكد انه فعلا هذه العشره فعلا اكبر
    -- ورقه موجوده... لازم تقول اكه» — AKA fires when CERTAIN.
    -- The certainty grows as cards are played. Now: suppress on
    -- doubled rounds ONLY when uncertainty is high (tricks
    -- completed < 3 → early round, opp could still hold the
    -- cards above our claimed boss). Mid/late doubled rounds
    -- (tricks >= 3) allow AKA when other gates pass — the played-
    -- card history makes the highest-unplayed determination sound.
    if S.s.contract and S.s.contract.doubled then
        if (#(S.s.tricks or {})) < 3 then
            return nil
        end
        -- Mid-round doubled: extra confidence check — our claimed
        -- boss (K/Q/J) is sound only if all higher cards in suit
        -- have been played. HighestUnplayedRank already reflects
        -- this; the existing `~= r` gate at line ~4985 enforces it.
        -- No additional suppression needed past trick 3.
    end

    -- v0.9.3 AKA precondition (g) (audit_v0.9.0/19_section6_now.md
    -- §2 + decision-trees.md Section 6 row "preconditions" subitem g).
    -- Round-stage / scoreUrgency: AKA is most valuable mid-round
    -- when voids have surfaced. In LATE-round tricks (trickNum >= 6)
    -- the signal carries marginal additional information — most
    -- voids are already known, partner can read the trick state
    -- directly, and broadcasting a banner just leaks our top-card
    -- holding to opponents for low return. Suppress when:
    --   • trickNum >= 6 (late round, ≤2 tricks remain) AND
    --   • cumulative differential is large (we're not in a
    --     clutch-trick scenario where the AKA's coordination
    --     genuinely matters) → use scoreUrgency==0 as a proxy for
    --     "not desperate, not near-clinch"
    -- The first condition is sufficient on its own per the doc;
    -- the second tightens it so we still send AKA late-round when
    -- the round is decisive.
    if trickNum >= 6 then
        -- Allow the late-round AKA when score-state is meaningful
        -- (close race, opp near-win, we near-clinch). Suppress when
        -- it's just a normal late-round info reveal.
        -- v1.0.3 (U-8): magic numbers 25 / 20 promoted to
        -- K.BOT_AKA_CLUTCH_DISTANCE / K.BOT_AKA_CLUTCH_RACE_GAP for
        -- tunability. Original 25 was a hand-set heuristic; pinning
        -- it to a constant makes future calibration a single edit.
        if S.s.cumulative then
            local myTeam = R.TeamOf(seat)
            local meCum = S.s.cumulative[myTeam] or 0
            local oppCum = S.s.cumulative[(myTeam == "A") and "B" or "A"] or 0
            local target = S.s.target or 152
            local clutchDist = K.BOT_AKA_CLUTCH_DISTANCE or 25
            local raceGap = K.BOT_AKA_CLUTCH_RACE_GAP or 20
            local clutch = (oppCum >= target - clutchDist)  -- opp near-win
                           or (meCum >= target - clutchDist)  -- we near-clinch
                           or (math.abs(oppCum - meCum) <= raceGap)  -- close race
            if not clutch then return nil end
        else
            return nil
        end
    end
    -- v1.1.0 (audit unpredictability HIGH-6) + v1.2.1 (A2 audit):
    -- Saudi-Master tier probabilistic withhold. Pre-fix `Bot.PickAKA`
    -- ALWAYS returned the suit when conditions matched — silence-
    -- as-signal: opp learns "if bot didn't AKA, bot doesn't hold the
    -- boss". Per video #19 «دائما خصم يحتفظ قوته في الاخر».
    --
    -- v1.2.1 A2: extend window from `trickNum <= 4` → `trickNum <= 6`.
    -- Per video #19's lateness factor (factor 1), pros withhold MORE
    -- in mid/late tricks, not less — the 4-trick cap was too early.
    -- v1.2.1 A8: keep clutch suppression but with a SHRUNK (not zero)
    -- variance — even in clutch the bot withholds at ~4% so the
    -- silence-vs-noise-in-clutch is itself not a tell. Distinct
    -- thresholds: clutchDist 22 (was 25 in tasgheer), raceGap 18
    -- (was 20) — desync from tasgheer to break synchronized silence.
    if Bot.IsSaudiMaster and Bot.IsSaudiMaster()
       and S.s.cumulative and trickNum <= 6 then
        local myTeam = R.TeamOf(seat)
        local meCum = S.s.cumulative[myTeam] or 0
        local oppCum = S.s.cumulative[(myTeam == "A") and "B" or "A"] or 0
        local target = S.s.target or 152
        local clutch = (oppCum >= target - 22)
                       or (meCum >= target - 22)
                       or (math.abs(oppCum - meCum) <= 18)
        local withholdProb = clutch and 0.04 or 0.10
        if math.random() < withholdProb then
            return nil
        end
    end
    -- v1.2.1 (A2 audit): noise-AKA emission. Pre-v1.2.1 if bot held
    -- the boss, the AKA fired with ~100% reliability; opp could trust
    -- "AKA on suit X" = "bot holds X-boss". Saudi-Master tier ~3%
    -- emits a NOISE AKA on the second-highest unplayed of a suit
    -- where bot has cover but NOT the actual boss. Opp's reliability
    -- on the AKA banner drops; they have to weigh whether each AKA
    -- might be noise. Only fires AFTER all the boss-claim gates have
    -- already passed-or-rejected — runs as a separate emission path.
    -- Mark akaSent so the dedup honors the noise emission too.
    -- Mark sent and return (boss-claim path).
    if mem and mem.akaSent then mem.akaSent[su] = true end
    return su
end

-- v1.2.1 (A2): noise-AKA emission helper. Called from Net's
-- pickPlay-with-AKA path AFTER `Bot.PickAKA` returns nil for the
-- regular boss-claim path. Saudi-Master only, low probability. The
-- "noise" suit is a non-trump suit where the bot holds K (or Q if
-- the K has been played) but the A is still unaccounted for — a
-- plausible-but-wrong AKA claim that corrupts opp's prior.
function Bot.PickAKANoise(seat, leadCard)
    if not Bot.IsSaudiMaster or not Bot.IsSaudiMaster() then return nil end
    if not leadCard then return nil end
    if not S.s.contract or S.s.contract.type ~= K.BID_HOKM then return nil end
    if not S.s.trick or #S.s.trick.plays > 0 then return nil end
    local trump = S.s.contract.trump
    if not trump then return nil end
    -- v1.6.0 (audit v1.5.3 swarm — signal leakage agent 3): noise rate
    -- bumped from 0.03 to 0.08. Audit found AKA was the single highest-
    -- leak signal (CRITICAL severity at sub-Saudi-Master tiers because
    -- the call-banner pinpoints the live boss). The 3% noise rate at
    -- Saudi Master was too low to meaningfully degrade opp's prior on
    -- AKA contents — opp could safely treat 97% of AKA calls as honest
    -- and ignore the noise floor. 8% (~3x increase) shifts the
    -- expectation enough that opp must seriously hedge against the
    -- bluff arm. Still well below convention-breaking levels (no opp
    -- would dismiss an AKA as 92% trustworthy).
    if math.random() >= 0.08 then return nil end
    -- Avoid trump suit + dedup with already-sent AKA suits.
    Bot._memory = Bot._memory or emptyMemory()
    local mem = Bot._memory[seat]
    local su = C.Suit(leadCard)
    local r = C.Rank(leadCard)
    if su == trump then return nil end
    if mem and mem.akaSent and mem.akaSent[su] then return nil end
    -- The card we're "AKA"ing on must be K or Q (a plausible second-
    -- highest cover that opp might believe is our boss).
    if r ~= "K" and r ~= "Q" then return nil end
    -- The actual boss (A in plain rank) must NOT be in our hand —
    -- otherwise this is just delayed boss-claim, not noise.
    local hand = S.s.hostHands and S.s.hostHands[seat]
    if hand then
        for _, c in ipairs(hand) do
            if C.Suit(c) == su and C.Rank(c) == "A" then
                return nil   -- we DO have the A; not a noise opportunity
            end
        end
    end
    -- Mark sent + return so the dedup gates honor it.
    if mem and mem.akaSent then mem.akaSent[su] = true end
    return su
end

-- Forward declaration for v1.6.0 CS-03 lead-suit perturbation. The
-- assignment `function perturbLeadSuit(...)` below this point writes
-- to this local (Lua 5.1 idiom), so PickPlay's call site at line 6470
-- resolves to the local rather than creating a global.
local perturbLeadSuit

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
        return perturbLeadSuit(pickLead(legal, contract, seat),
                               legal, contract)
    end
    return pickFollow(legal, hand, trick, contract, seat)
end

-- v1.6.0 CS-03 (audit v1.5.3 swarm — predictability fix): lead-suit
-- perturbation. pickLead resolves through a long deterministic
-- branch-priority chain (closed-trump filter → trick-8 targeting →
-- sweep-pursuit → tahreeb-pref → AKA continuation → defender-style →
-- lowestByRank fallback). When 2+ branches would fire on the same
-- hand state, the FIRST listed branch always wins. A perfect-memory
-- opp pre-computes this.
--
-- Fix: at Fzloky+ tier only, with 6% probability after pickLead
-- resolves, swap the chosen card with a same-rank-class alternative
-- in a DIFFERENT, NON-TRUMP suit. Same rank-class preserves the
-- lead's strategic value (boss/mid/low quality unchanged); the suit
-- swap degrades opp's lead-suit prediction from ~85% to ~60% on
-- flat-top states without breaking any signal.
--
-- Carve-outs that we DO NOT perturb (signal-critical):
--   • Trump leads — partner reads trump-led-vs-side-led for read on
--     bidder-team strength
--   • A/J leads — boss-claim and AKA-hint signals
--   • Singletons — no alternative anyway
--
-- Partner impact: minimal. Partner reads the suit led; the
-- post-perturb suit is one of pickLead's own candidate set (legal +
-- same rank class), all Saudi-canonical. Partner's read-side logic
-- treats lead-suit as input, not predicted-in-advance.
--
-- Defined as a forward-decl-style local function so PickPlay can
-- reference it on the line above. Must come AFTER PickPlay since
-- Lua 5.1 needs the upvalue captured before the call site, but
-- since perturbLeadSuit is itself local, declaring it ABOVE PickPlay
-- (with a forward-decl pattern) is the cleanest fix.
function perturbLeadSuit(card, legal, contract)
    if not card then return card end
    if not Bot.IsFzloky or not Bot.IsFzloky() then return card end
    if not legal or #legal < 2 then return card end
    if math.random() >= 0.06 then return card end
    local rank = C.Rank(card)
    local suit = C.Suit(card)
    local trump = contract and contract.trump
    if trump and suit == trump then return card end
    if rank == "A" or rank == "J" then return card end
    -- Find same-rank legal alternatives in a DIFFERENT, non-trump suit.
    local pool = {}
    for _, c in ipairs(legal) do
        if c ~= card
           and C.Suit(c) ~= suit
           and C.Rank(c) == rank
           and (not trump or C.Suit(c) ~= trump) then
            pool[#pool + 1] = c
        end
    end
    if #pool > 0 then return pool[math.random(#pool)] end
    return card
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
    local contract = S.s.contract
    local all = R.DetectMelds(hand, contract)

    -- v1.0.9 C#2 (swarm finding): Qaid-protection meld filter. Saudi
    -- meld scoring is winner-takes-all per `R.CompareMelds` — only
    -- the team with the higher-ranked best meld scores; the loser
    -- team's declared melds drop to 0. If opps have already declared
    -- (we're not the first player in trick 1) and their best meld
    -- already beats our team's current best AND would beat each of
    -- our candidates, declaring our melds reveals 3-4 cards for 0
    -- expected score benefit. Filter to candidates that either
    --   (a) flip the outcome (candidate beats opp's best), OR
    --   (b) ride a partner's already-winning declaration (so our
    --       meld adds to the SUM that scores when our team wins).
    -- If R.MeldRank isn't available (very old back-port), fall
    -- through to the unfiltered candidate set.
    if R.MeldRank and S.s.meldsByTeam then
        local team = R.TeamOf(seat)
        local oppTeam = (team == "A") and "B" or "A"
        local oppMelds = S.s.meldsByTeam[oppTeam] or {}
        local teamMelds = S.s.meldsByTeam[team] or {}
        if #oppMelds > 0 then
            local oppBestRank = -math.huge
            for _, m in ipairs(oppMelds) do
                local r = R.MeldRank(m, contract)
                if r > oppBestRank then oppBestRank = r end
            end
            local teamBestRank = -math.huge
            for _, m in ipairs(teamMelds) do
                local r = R.MeldRank(m, contract)
                if r > teamBestRank then teamBestRank = r end
            end
            -- If partner already has a winning meld, every candidate
            -- adds to our team's SUM (no filter needed).
            if teamBestRank > oppBestRank then
                return all
            end
            -- Otherwise keep only candidates that would beat opp.
            local kept = {}
            for _, m in ipairs(all) do
                if R.MeldRank(m, contract) > oppBestRank then
                    kept[#kept + 1] = m
                end
            end
            return kept
        end
    end
    return all
end

-- Smarter Bel — gated by hand strength so a weak defender doesn't bel
-- into stronger opposition. Sun contracts get a small bonus because
-- Sun is harder to make than Hokm. Threshold is jittered per-call by
-- ±10 so the Bel decision isn't a hard cliff at exactly the configured
-- value (was the #1 "predictable bot" complaint).
local BEL_JITTER = 10
-- v1.1.0 (audit unpredictability MED-7): per-rung jitter magnitude.
-- Pre-fix all four escalation rungs used the same ±10 — making the
-- chain Bel→Triple→Four→Gahwa effectively deterministic given the
-- starting hand. Per video #11 the rungs are explicitly framed as
-- separate strategic acts («الفور على القهوه» etc.), so escalation
-- variance should grow with risk: Bel ±8, Triple ±12, Four ±15,
-- Gahwa ±18. Higher rungs = larger jitter = less correlated decisions.
local TRIPLE_JITTER = 12
local FOUR_JITTER   = 15
local GAHWA_JITTER  = 18

-- v1.6.0 CS-02 (audit v1.5.3 swarm — predictability fix): self-style
-- jitter widening for Fzloky+. Pre-fix, every Fzloky bot's Bel/Triple/
-- Four/Gahwa decision was driven by the same per-rung jitter band — so
-- once a human read one bot's escalation pattern, every bot at that
-- table escalated from the same implied strength range. Hand-strength-
-- from-Bel was readable to ~22 points resolution.
--
-- Fix: thread the seat's lifetime escalation count (Bot._partnerStyle
-- [seat].bels / .triples / .fours / .gahwas) into an extra jitter delta.
-- Seats that have escalated often get wider effective jitter ("loose"
-- caller — could Bel from anywhere); seats that haven't get tighter
-- ("tight" caller — Bel implies serious strength). Net: opp can't bank
-- "all bots Bel from the same band". The same Bel from a loose-bel
-- seat conveys less strength info than the same Bel from a tight-bel
-- seat.
--
-- Partner impact: minimal. Partner observes contract.cardMult after
-- the Bel fires (read-side); the wider WHICH-hands-Bel band doesn't
-- change the meaning of the Bel itself — partner's Triple-eval ladder
-- runs on the standard threshold scale.
local function selfStyleJitterBonus(seat, kind)
    if not Bot.IsFzloky or not Bot.IsFzloky() then return 0 end
    if not Bot._partnerStyle then return 0 end
    local m = Bot._partnerStyle[seat]
    if not m then return 0 end
    local count = (kind == "bels"    and m.bels)
               or (kind == "triples" and m.triples)
               or (kind == "fours"   and m.fours)
               or (kind == "gahwas"  and m.gahwas)
               or 0
    -- Seat with 0-1 calls of this kind → tight reputation, mild
    -- contract: -2 jitter (band tighter). Seat with 2+ → loose
    -- reputation, expand: +(count-1), capped at +5. Higher rungs
    -- cap at higher max since they're rarer (more variance budget).
    local maxBonus = (kind == "bels" and 4)
                  or (kind == "triples" and 5)
                  or (kind == "fours" and 5)
                  or (kind == "gahwas" and 6)
                  or 4
    local extra = math.min(maxBonus, math.max(-2, count - 1))
    if extra == 0 then return 0 end
    return math.random(-math.abs(extra), math.abs(extra))
end

-- v0.2.0: returns (yes, wantOpen) like the other escalation pickers.
-- wantOpen: open the chain to a bidder Triple counter only if our hand
-- is comfortably above threshold (we'd survive the next rung's stakes).
-- Sun forces wantOpen=false since Sun has no Triple rung anyway.
function Bot.PickDouble(seat)
    local hand = S.s.hostHands and S.s.hostHands[seat]
    local contract = S.s.contract
    if not hand or not contract then return false, false end

    -- v0.11.19 audit (escalation observability): mirror PickBid's btrace
    -- pattern. Pre-fix the user reported 0% Bel rate across 33 rounds
    -- with no diagnostic visibility — couldn't tell whether bots reached
    -- threshold and were jitter-rejected, or strength was way off.
    -- Reuses /baloot bidcalc toggle (WHEREDNGNDB.debugBidcalc).
    local function eltrace(fmt, ...)
        if not (WHEREDNGNDB and WHEREDNGNDB.debugBidcalc) then return end
        local ok, msg = pcall(string.format, fmt, ...)
        if not ok then return end
        print(("|cff66ff77[bel s%d]|r %s"):format(seat or 0, msg))
    end

    -- v0.5.9 Section 2 patch E-1: Sun Bel-100 legality gate.
    -- Saudi rule: in Sun contracts, only the team at <100 cumulative
    -- score may Bel. Hokm has no such gate. R.CanBel is the
    -- authoritative predicate (also enforced wire-side in Net.lua,
    -- so a human player can't bypass via the wire).
    -- Sources: decision-trees.md Section 2 (Definite, video 11).
    if R.CanBel and not R.CanBel(R.TeamOf(seat), contract, S.s.cumulative) then
        eltrace("PickDouble blocked: Sun Bel-100 gate (R.CanBel=false)")
        return false, false
    end

    -- v1.4.3 (audit follow-up — score-desperation Bel hand-bypass).
    -- Source: video #25 (when_bid_sun) R26.
    -- Saudi pro reasoning: «ما أنت خسرانه — ممكن يجيك مشروع»
    -- (you can't lose more than you're already losing — and you might
    -- land a meld). When our team is severely behind AND opp is
    -- within one round of winning, the round is essentially conceded;
    -- a Bel cannot meaningfully worsen our cumulative position
    -- (failing the Bel'd round vs failing un-Bel'd is the same
    -- match outcome). Bel REGARDLESS of hand strength — the ×2
    -- multiplier preserves the small upside (any pulled trick or
    -- meld is doubled in our pile). Closed Bel (wantOpen=false)
    -- prevents this from cascading into Triple/Four/Gahwa where
    -- strength threshold checks should remain in force.
    -- M3lm-gated: this is a strategic read, not a basic-tier rule.
    if Bot.IsM3lm and Bot.IsM3lm() and S.s.cumulative then
        local myTeam = R.TeamOf(seat)
        local oppTeam = (myTeam == "A") and "B" or "A"
        local myCum = S.s.cumulative[myTeam] or 0
        local oppCum = S.s.cumulative[oppTeam] or 0
        local target = S.s.target or 152
        if oppCum >= target - 26 and myCum <= oppCum - 50 then
            eltrace("PickDouble FIRE: score-desperation (myCum=%d oppCum=%d target=%d)",
                    myCum, oppCum, target)
            return true, false  -- Bel, closed
        end
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
        for _, suit in ipairs(shuffledSuits()) do
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
    -- v0.6.0 H-7: capped at ±15 (combined urgency).
    local th = K.BOT_BEL_TH - combinedUrgency(R.TeamOf(seat), "defend")

    -- v0.8.1 B-95: opp-bidder desperation. If the bidder is on a team
    -- that's far behind us (or we're near clinch), their contract is
    -- more likely a Hail-Mary marginal bid. Lower our Bel threshold
    -- to defensively counter the likely-failing bid. M3lm-gated since
    -- it relies on opponentUrgency which itself is M3lm+. Magnitude
    -- (-5) is conservative — combined with the existing combinedUrgency
    -- it stays within the BOT_BEL_TH - 16 floor enforced below.
    -- Sources: bot_picker_gaps.md / wave8 B-95.
    if contract.bidder and Bot.IsM3lm() then
        local bidUrg = opponentUrgency(contract.bidder)
        if bidUrg >= 6 then
            th = th - 5
        end
    end

    -- v1.4.3 (audit follow-up — 100-meld + Ace defender Bel modifier).
    -- Source: video #25 (when_bid_sun) R27.
    -- Saudi pro: defender holding a 100-meld (مشروع 100) + an Ace has
    -- "almost guaranteed positive EV" on Bel. The 100-meld already
    -- locks in 100 raw points for our team independent of trick play;
    -- the Ace ensures we capture at least one trick of trick-points;
    -- Bel doubles both. Lower effective BOT_BEL_TH by 15 when this
    -- shape is present — meaningful nudge without forcing Bel on
    -- hopeless hands. Threshold floor (BOT_BEL_TH - 16) still
    -- applies below. M3lm-gated: requires meld-state read +
    -- positional Bel reasoning.
    if Bot.IsM3lm() and S.s.meldsByTeam and R.SumMeldValue then
        local myTeam = R.TeamOf(seat)
        local myMelds = S.s.meldsByTeam[myTeam]
        local meldTotal = (myMelds and R.SumMeldValue(myMelds)) or 0
        if meldTotal >= 100 then
            local hasAce = false
            for _, c in ipairs(hand) do
                if C.Rank(c) == "A" then hasAce = true; break end
            end
            if hasAce then
                th = th - 15
                eltrace("PickDouble: 100-meld + Ace modifier applied (-15)")
            end
        end
    end

    -- v1.0.4 (agent #4): bid-history inflection read. The contract's
    -- provenance carries information about hand quality:
    --   • PREEMPT path (someone Sun-preempted a prior Hokm bid on
    --     A-bidcard): bidder's hand exceeded the preempt threshold
    --     under bidcard. Strong-hand tell.
    --   • OVERCALL conversion (Hokm→Sun via Sun overcall): bidder's
    --     hand exceeded BOTH the original Hokm threshold AND the
    --     Sun-overcall threshold. Even stronger tell.
    -- In both cases the bidder is more likely to MAKE their contract
    -- → Bel'ing it is a worse bet. Bias `th` upward by +5 to deter.
    -- Detection is heuristic — we read S.s.bids array for bid-history
    -- shape. Not perfect but cheap and the magnitude is conservative.
    -- M3lm-gated since cross-bid-history reading is a tier-3 nuance.
    if Bot.IsM3lm() and S.s.bids and contract.bidder and S.s.bidCard then
        local bidcardRank = C.Rank(S.s.bidCard)
        local bidderBid = S.s.bids[contract.bidder]
        -- Detect "Sun on A-bidcard with at least one prior bidder":
        -- iterate bids, count non-pass non-bidder bids that came BEFORE
        -- the bidder. If >= 1 and bidder bid SUN on A-bidcard, that's
        -- a preempt-Sun shape.
        if bidcardRank == "A" and bidderBid == K.BID_SUN then
            local priorBids = 0
            for _, b in pairs(S.s.bids) do
                if b and b ~= K.BID_PASS and b ~= bidderBid then
                    priorBids = priorBids + 1
                end
            end
            if priorBids >= 1 then
                th = th + 5
            end
        end
        -- Detect overcall conversion: contract.type=Sun but contract
        -- has an `overcall` history flag (set by S.ApplyOvercall paths).
        -- If present, bidder converted Hokm→Sun = strong-hand tell.
        if contract.type == K.BID_SUN and contract.overcallFromHokm then
            th = th + 5
        end
    end

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
    -- v1.6.0 CS-02: self-style jitter widening (Fzloky+).
    jth = jth + selfStyleJitterBonus(seat, "bels")
    eltrace("PickDouble eval: strength=%d th=%d jth=%d (BOT_BEL_TH=%d)",
            strength, th, jth, K.BOT_BEL_TH)
    if strength < jth then
        eltrace("PickDouble PASS: strength=%d < jth=%d", strength, jth)
        return false, false
    end
    -- Sun: open is moot (no Triple rung).
    if contract.type == K.BID_SUN then
        eltrace("PickDouble FIRE (Sun, no open): strength=%d >= jth=%d", strength, jth)
        return true, false
    end
    -- Open if we have a comfortable buffer (would survive a Triple
    -- counter); else close to lock in the ×2.
    local wantOpen = strength >= jth + 20
    eltrace("PickDouble FIRE (Hokm): strength=%d >= jth=%d wantOpen=%s",
            strength, jth, tostring(wantOpen))
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
        -- v1.0.3 (ESC-1): sunStrength applies a Sun-only void-penalty
        -- (capped K.BOT_SUN_VOID_PENALTY_CAP=8) intended for Sun
        -- where short suits can't be ruffed (no trump). In Hokm,
        -- voids = ruff capacity. The block below NEUTRALIZES the
        -- Sun-only penalty (adds back the same magnitude that
        -- sunStrength subtracted) so the EV-1 voidBonus immediately
        -- below — `voidCount * 5 + sideAces * 8` — is the SOLE
        -- Hokm void/Ace contribution. Net effect for Hokm: voids
        -- earn +5 each (positive, ruff-capacity); side-Aces beyond
        -- the first earn +8 each. Without this neutralization, the
        -- Sun penalty would partially cancel the EV-1 bonus.
        --
        -- v1.0.6 (B#1) comment fix: clarified "neutralization" vs
        -- the prior misleading "inversion" claim. Behavior unchanged.
        if Bot.IsAdvanced() then
            local count = { S = 0, H = 0, D = 0, C = 0 }
            local honors = { S = false, H = false, D = false, C = false }
            for _, card in ipairs(hand) do
                local r = C.Rank(card)
                local su = C.Suit(card)
                count[su] = count[su] + 1
                if r == "A" or r == "T" or r == "K" then
                    honors[su] = true
                end
            end
            local penalty = 0
            for _, su in ipairs(shuffledSuits()) do
                if count[su] < 2 or not honors[su] then
                    penalty = penalty + 10
                end
            end
            local applied = math.min(penalty, K.BOT_SUN_VOID_PENALTY_CAP)
            strength = strength + applied  -- neutralize Sun-only penalty
        end
        strength = strength + suitStrengthAsTrump(hand, contract.trump)
        -- v0.11.17 EV-1 (audit): mirror PickDouble's defender bonuses
        -- on the BIDDER side. Pre-v0.11.17 escalationStrength missed
        -- void/side-Ace bonuses while PickDouble (defender) added
        -- them, putting bidder/defender on different scales for the
        -- same hand quality. Combined with EV-2 (BOT_GAHWA_TH=135 on
        -- 5-card hand), this is the root cause of escalation.md's
        -- "0% chain fire in symmetric pure-bot play" diagnostic.
        local voidCount, sideAces = 0, 0
        local sideSuits = { S = 0, H = 0, D = 0, C = 0 }
        for _, c in ipairs(hand) do
            local r, su = C.Rank(c), C.Suit(c)
            if su ~= contract.trump then
                sideSuits[su] = sideSuits[su] + 1
                if r == "A" then sideAces = sideAces + 1 end
            end
        end
        for _, su in ipairs(shuffledSuits()) do
            if su ~= contract.trump and sideSuits[su] == 0 then
                voidCount = voidCount + 1
            end
        end
        strength = strength + voidCount * 5 + math.max(sideAces - 1, 0) * 8
    end
    -- NOTE: Sun has no Triple/Four/Gahwa rungs (Saudi rule R2 +
    -- v0.10.0 R2 defense-in-depth; PickTriple/Four/Gahwa explicitly
    -- early-return false on `contract.type == K.BID_SUN`). Sun's
    -- only escalation path is Bel via PickDouble, which has its own
    -- inline scoring (line ~3812+) and doesn't call this function.
    -- v0.11.17-hotfix F1 (post-ship audit): the v0.11.17 Sun branch
    -- here was dead code — never reachable from any caller — so
    -- removed. AA.1c source-pin retained but converted to a Sun-
    -- bidder-bonus-applied test on the PickBid path, not on
    -- escalationStrength.
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
    -- v1.0.8 (user-requested observability): eltrace mirror of
    -- PickDouble's `[bel sN]` pattern. When debugBidcalc toggle is on,
    -- log `[trp sN] PickTriple eval/PASS/FIRE` so users debugging
    -- "why never Triple?" can see strength + threshold. Was missing
    -- pre-v1.0.8; only PickDouble had observability.
    local function eltrace(fmt, ...)
        if not (WHEREDNGNDB and WHEREDNGNDB.debugBidcalc) then return end
        local ok, msg = pcall(string.format, fmt, ...)
        if not ok then return end
        print(("|cff66ddff[trp s%d]|r %s"):format(seat or 0, msg))
    end
    -- v0.10.0 R2 defense-in-depth: Sun has no Triple rung. The phase
    -- machine prevents PHASE_TRIPLE on Sun in practice, but a stale
    -- caller path (test or future refactor) reaching here on a Sun
    -- contract should still no-op. Source: review_v0.10.0/reaudit_R2.
    if contract.type == K.BID_SUN then
        eltrace("PickTriple blocked: Sun has no Triple rung")
        return false, false
    end
    local strength = escalationStrength(seat, hand, contract)
    -- v0.6.0 H-7: capped at ±15 (combined urgency).
    local th = K.BOT_TRIPLE_TH - combinedUrgency(R.TeamOf(seat))
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
    -- v1.0.2 (FLOOR-3): floor cap matches the symmetric defenses in
    -- PickDouble (v0.5.2), PickFour (v0.5.3), and PickGahwa. The
    -- combined urgency + style-bel-tendency path can drop `th` from
    -- 90 base to 75 (-15 urgency cap) → 67 (-8 bel-tendency) on top-
    -- tier hands. Without this cap the 16-pt drop opens a gap below
    -- the well-calibrated threshold range. Floor at -16 mirrors
    -- PickFour's K.BOT_FOUR_TH - 16 = 94; here that's 74.
    if th < K.BOT_TRIPLE_TH - 16 then th = K.BOT_TRIPLE_TH - 16 end
    -- v1.1.0 (audit unpredictability MED-7): Triple uses ±12 jitter
    -- (vs Bel ±10) — higher rung = larger variance.
    local jth = jitter(th, TRIPLE_JITTER)
    -- v1.6.0 CS-02: self-style jitter widening (Fzloky+).
    jth = jth + selfStyleJitterBonus(seat, "triples")
    eltrace("PickTriple eval: strength=%d th=%d jth=%d (BOT_TRIPLE_TH=%d)",
            strength, th, jth, K.BOT_TRIPLE_TH)
    if strength < jth then
        eltrace("PickTriple PASS: strength=%d < jth=%d", strength, jth)
        return false, false
    end
    local wantOpen = strength >= jth + 20
    eltrace("PickTriple FIRE: strength=%d >= jth=%d wantOpen=%s",
            strength, jth, tostring(wantOpen))
    return true, wantOpen
end

function Bot.PickFour(seat)
    -- v0.2.0: Four is the DEFENDER's response to bidder's Triple.
    -- A failed ×4 round is a hand-killer — defender needs to be
    -- highly confident the contract will fail.
    local hand = S.s.hostHands and S.s.hostHands[seat]
    local contract = S.s.contract
    if not hand or not contract then return false, false end
    -- v1.0.8: eltrace observability (mirror of PickDouble pattern).
    local function eltrace(fmt, ...)
        if not (WHEREDNGNDB and WHEREDNGNDB.debugBidcalc) then return end
        local ok, msg = pcall(string.format, fmt, ...)
        if not ok then return end
        print(("|cffff8855[for s%d]|r %s"):format(seat or 0, msg))
    end
    -- v0.10.0 R2 defense-in-depth: Sun has no Four rung.
    if contract.type == K.BID_SUN then
        eltrace("PickFour blocked: Sun has no Four rung")
        return false, false
    end
    -- v0.11.18 audit P4-1: read partner's Bel `belOpen` flag.
    -- v0.11.18-final DEAD-1 (ultra audit): the `belOpen == false`
    -- branch was DEAD CODE. PHASE_FOUR is structurally unreachable
    -- when belOpen=false (S.ApplyDouble shortcuts to PHASE_PLAY when
    -- belOpen=false; PHASE_TRIPLE only fires when belOpen=true; PHASE_FOUR
    -- only after open Triple). At PHASE_FOUR, belOpen=true is invariant.
    -- The +5 bonus therefore ALWAYS fires — reframed as honest
    -- calibration constant rather than conditional signal.
    local strength = escalationStrength(seat, hand, contract)
    -- v0.11.18 P4-1: +5 bonus reflects "partner kept the chain open,
    -- combined-team strength signal beyond raw partnerEscalatedBonus".
    -- Per DEAD-1 audit, this is unconditional at PHASE_FOUR.
    strength = strength + 5
    -- v0.5 H-8: defender Four uses context="defend" — same logic as Bel.
    -- v0.6.0 H-7: capped at ±15 (combined urgency).
    local th = K.BOT_FOUR_TH - combinedUrgency(R.TeamOf(seat), "defend")
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
    -- v1.0.8: eltrace eval/PASS/FIRE.
    -- v1.1.0 (audit MED-7): Four uses ±15 jitter — higher rung,
    -- larger decision variance.
    local jth = jitter(th, FOUR_JITTER)
    -- v1.6.0 CS-02: self-style jitter widening (Fzloky+).
    jth = jth + selfStyleJitterBonus(seat, "fours")
    eltrace("PickFour eval: strength=%d th=%d jth=%d (BOT_FOUR_TH=%d)",
            strength, th, jth, K.BOT_FOUR_TH)
    if strength < jth then
        eltrace("PickFour PASS: strength=%d < jth=%d", strength, jth)
        return false, false
    end
    local wantOpen = strength >= jth + 20
    eltrace("PickFour FIRE: strength=%d >= jth=%d wantOpen=%s",
            strength, jth, tostring(wantOpen))
    return true, wantOpen
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
    -- v1.0.8: eltrace observability.
    local function eltrace(fmt, ...)
        if not (WHEREDNGNDB and WHEREDNGNDB.debugBidcalc) then return end
        local ok, msg = pcall(string.format, fmt, ...)
        if not ok then return end
        print(("|cffff5555[ghw s%d]|r %s"):format(seat or 0, msg))
    end
    -- v0.10.0 R2 defense-in-depth: Sun has no Gahwa rung.
    if contract.type == K.BID_SUN then
        eltrace("PickGahwa blocked: Sun has no Gahwa rung")
        return false, false
    end
    local strength = escalationStrength(seat, hand, contract)
    -- v0.6.0 H-7: capped at ±15 (combined urgency).
    local th = K.BOT_GAHWA_TH - combinedUrgency(R.TeamOf(seat))
    -- v0.11.19 DEAD-2 (ultra-audit): floor cap removed. With combinedUrgency
    -- already clamped at ±15 by line 1198, `th` range is [105, 135]. The
    -- prior floor at K.BOT_GAHWA_TH-16=104 was unreachable (105 > 104
    -- always). The PickDouble/PickFour floors fire because their pickers
    -- have ADDITIONAL M3lm style adjustments (gahwaFailed/triples) that
    -- can drop th past the urgency-cap floor; PickGahwa has no such
    -- style adjustments, so the cap is the only constraint. Documenting
    -- intent: minimum effective threshold = 105 - 10 jitter = 95.
    -- Acceptable because Gahwa is bidder-side (we have all the info),
    -- and combined-urgency >= 15 only fires when our team is near-loss
    -- desperation (terminal swing OK).
    -- v1.1.0 (audit MED-7): Gahwa uses ±18 jitter — terminal rung,
    -- highest variance to break "pure deterministic from hand shape"
    -- escalation chain pattern.
    local jth = jitter(th, GAHWA_JITTER)
    -- v1.6.0 CS-02: self-style jitter widening (Fzloky+).
    jth = jth + selfStyleJitterBonus(seat, "gahwas")
    eltrace("PickGahwa eval: strength=%d th=%d jth=%d (BOT_GAHWA_TH=%d)",
            strength, th, jth, K.BOT_GAHWA_TH)
    local yes = strength >= jth
    if yes then
        eltrace("PickGahwa FIRE: strength=%d >= jth=%d (terminal, match-win)",
                strength, jth)
    else
        eltrace("PickGahwa PASS: strength=%d < jth=%d", strength, jth)
    end
    return yes, false
end

-- Triple-on-Ace pre-emption (الثالث) — bot decision for an earlier
-- seat eligible to claim a Sun bid when the bid card is an Ace.
-- Heuristic: claim only if our own Sun strength is strong enough that
-- we'd have wanted to bid Sun ourselves (subject to BOT_PREEMPT_TH).
function Bot.PickPreempt(seat)
    local hand = S.s.hostHands and S.s.hostHands[seat]
    if not hand then return false end
    -- v0.11.16 audit BC-1 + PP-1 fix: include bidcard in sunStrength.
    -- PickPreempt fires only when bidCard.rank == "A" (gated by
    -- Net.lua _OnPreempt phase). The pre-emption winner becomes the
    -- new bidder and gets the bidcard appended to their hand. Pre-
    -- v0.11.16 the dead-code "+12 if hand contains A of bidSuit"
    -- bonus was unreachable: the A of bidSuit IS the bidcard, so no
    -- non-host seat can hold it. Replacing with the canonical
    -- bidcard-inclusion via withBidcard correctly adds +11 (A face
    -- value) to sunStrength via the same mechanism as R1 Sun.
    local sunHand = withBidcard(hand, S.s.bidCard)
    local strength = sunStrength(sunHand)
    -- v0.11.20 PE-1 (Agent 1 calibration math): mirror PickBid R1 Sun's
    -- ace-count + mardoofa bonus stack. PickPreempt only fires when
    -- bidCard.rank == "A", so post-bidcard sunHand has at least 1 Ace.
    -- If bot's hand also holds an Ace, post-bidcard hand has 2 Aces —
    -- canonical Saudi S-1 Sun shape. Pre-fix sunStrength alone gave
    -- median sun=24 / p95=37, structurally below BOT_PREEMPT_TH=75.
    -- Combined with TH 75 -> 60 (Constants.lua), gives ~0.72%
    -- canonical fire rate per A-bidcard (vs <0.01% pre-fix).
    local preemptAces = 0
    for _, c in ipairs(sunHand) do
        if C.Rank(c) == "A" then preemptAces = preemptAces + 1 end
    end
    if preemptAces >= 3 then
        strength = strength + K.BOT_SUN_3ACE_BONUS
    elseif preemptAces == 2 then
        strength = strength + K.BOT_SUN_2ACE_BONUS
    end
    local _, preemptMardoofa = aceCountAndMardoofa(sunHand)
    strength = strength + math.min(preemptMardoofa, K.BOT_SUN_MARDOOFA_PAIR_CAP)
                        * K.BOT_SUN_MARDOOFA_BONUS
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
-- ---------------------------------------------------------------------
-- Sun-overcall (Hokm → Sun) decision
-- ---------------------------------------------------------------------
-- Returns one of: "UPGRADE", "TAKE", "WAIVE".
-- Tier-gated: M3lm+ only. Lower tiers always WAIVE — overcall is a
-- tournament-strategy nuance and should not surprise basic-bot games.
-- Sources: bot_picker_gaps.md (Sun-overcall feature), user spec.
function Bot.PickOvercall(seat)
    if not Bot.IsM3lm() then return "WAIVE" end
    if not S.s or not S.s.contract or not S.s.overcall then return "WAIVE" end
    local hand = S.s.hostHands and S.s.hostHands[seat]
    if not hand or #hand == 0 then return "WAIVE" end
    local contract = S.s.contract
    local bidCard  = S.s.overcall.bidCard
    if not R.CanOvercall(seat, contract, bidCard) then return "WAIVE" end

    -- v0.11.16 audit BC-1: include the R1 bidcard (carried in
    -- S.s.overcall.bidCard) in overcall evaluation. Whoever wins the
    -- overcall becomes the new bidder and gets the bidcard appended
    -- to their hand at HostDealRest. For non-bidder TAKE/TAKE_HOKM
    -- the +11 (A bidcard) or smaller face value contribution can
    -- flip threshold-borderline overcall decisions.
    --
    -- v0.11.16-hotfix OVC-bidcard (post-ship audit): hypHand build
    -- moved BEFORE the void/short trumpCount loop. Pre-hotfix the
    -- count operated on the bare 5-card hand, so a bidcard in
    -- contract.trump suit was missed — a seat with 0 trump in their
    -- hand but bidcard-of-trump (1 effective trump post-win) still
    -- got the +15 void bonus, double-counting the bidcard's
    -- contribution to defensive strength.
    local hypHand = withBidcard(hand, bidCard)

    -- v0.11.15 Q1 user-audit: void-in-trump signal for Sun overcall.
    -- When the bidder's Hokm trump is a suit we have ZERO (or one)
    -- cards in, that's the canonical Saudi Sun-overcall trigger —
    -- in Sun there's no trump, so our void/short suit doesn't bleed.
    -- Without this bonus, the bot used generic sunStrength which has
    -- no awareness of the opp's trump choice; void hands looked the
    -- same as balanced ones.
    local trumpCount = 0
    if contract.trump then
        for _, c in ipairs(hypHand) do
            if C.Suit(c) == contract.trump then trumpCount = trumpCount + 1 end
        end
    end
    local voidBonus = 0
    if trumpCount == 0 then
        voidBonus = K.BOT_OVERCALL_VOID_TRUMP_BONUS
    elseif trumpCount == 1 then
        voidBonus = K.BOT_OVERCALL_SHORT_TRUMP_BONUS
    end

    -- v0.11.18 audit OE-1: Sun Bel-fear bias for overcall. Mirror
    -- PickBid's check (line 1465-1473): if our cumulative > 100 and
    -- we're considering taking as Sun, the OTHER team can still Bel
    -- us in Sun (per R.CanBel — only the team <100 may Bel; opp at
    -- ≤100 still qualifies). A failed Bel'd Sun is 26 game points
    -- against us. Bias overcall threshold UP by +8 to deter, mirroring
    -- the same magnitude as the bid-side gate.
    local overcallBelFear = 0
    if S.s.cumulative then
        local myTotal = S.s.cumulative[R.TeamOf(seat)] or 0
        if myTotal > K.SUN_BEL_CUMULATIVE_GATE then
            overcallBelFear = 8
        end
    end
    -- v1.0.3 (OVC-DOUBLE) calibration interaction note:
    -- sunStrength(hypHand) returns the base score WITH the Sun
    -- void-penalty applied (capped K.BOT_SUN_VOID_PENALTY_CAP = 8).
    -- voidBonus is then ADDED on top — but they don't fully cancel:
    --   • sunStrength's penalty hits suits short OR honorless;
    --   • voidBonus only credits true voids (count==0).
    -- So a 1-card honorless suit gets penalised but earns no
    -- voidBonus; a true void earns voidBonus but the penalty was
    -- already applied with cap 8. The end-to-end calibration
    -- assumes this asymmetry — keeps shorter "cover-but-not-stop"
    -- suits as a penalty (they're vulnerable in Sun) while still
    -- crediting full-void cushion bonus. Documented per audit
    -- OVC-DOUBLE; no behavioral change.
    local sunStr = sunStrength(hypHand) + voidBonus - overcallBelFear
    if seat == contract.bidder then
        -- UPGRADE option (non-Ace-bid only — CanOvercall already
        -- filters Ace case). Threshold is BOT_OVERCALL_SELF_TH.
        if sunStr >= K.BOT_OVERCALL_SELF_TH then
            return "UPGRADE"
        end
        return "WAIVE"
    end

    -- Non-bidder: TAKE (as Sun) or WAIVE.
    --
    -- v1.5.3 (user-reported, saudi-rules.md:26-28): TAKE_HOKM_<suit>
    -- evaluation removed. Cross-trump non-bidder take is non-canonical
    -- — the canonical Saudi response to a Hokm bid is PASS, ACCEPT, or
    -- ASHKAL (partner-only). Sun-overcall (TAKE) remains, since
    -- "Sun overcalls Hokm" is documented at saudi-rules.md:256.
    if sunStr >= K.BOT_OVERCALL_TAKE_TH then
        return "TAKE"
    end
    return "WAIVE"
end

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
-- host fills .illegal during S.ApplyPlay).
--
-- v0.11.16 audit H2: rate-table inverted+over-soft to flat ~0.95.
-- Pre-v0.11.16 the rate decayed 0.60 -> 0.05 across tricks, framing
-- Takweesh as a "looks more obvious early" tactical option. Per
-- saudi-rules.md:163-166 (video #36) Takweesh is a HARD rule-correctness
-- call — humans call ALL detected violations promptly regardless of
-- trick number. The decay was leaving ~95% of trick-6/7 illegal plays
-- silently uncalled. Flat 0.95 keeps a tiny "human realism" softener
-- (not all humans catch every violation) while restoring tournament-
-- grade vigilance. Returns the offending play table if the bot
-- decides to call, else nil. Net.lua's MaybeRunBot consumes this
-- on each bot turn before scheduling the normal play.

local TAKWEESH_RATE_BY_TRICK = {
    [0] = 0.95, [1] = 0.95, [2] = 0.95, [3] = 0.95,
    [4] = 0.95, [5] = 0.95, [6] = 0.95, [7] = 0.95,
}

function Bot.PickTakweesh(seat)
    if not S.s.contract then return nil end
    local myTeam = R.TeamOf(seat)
    local completed = #(S.s.tricks or {})
    -- v0.11.16-hotfix TC-01: fallback rate aligned with A4's flat 0.95.
    -- Unreachable in normal play (8 tricks per round indexed 0..7) but
    -- kept consistent.
    local rate = TAKWEESH_RATE_BY_TRICK[completed] or 0.95

    -- v1.5.1 (audit fix — Takweesh realism): pre-fix scanned for
    -- p.illegal flag (host-side full-info) and fired Takweesh
    -- whenever an opp's illegal play was found, even if the bot
    -- couldn't realistically OBSERVE the violation. User-reported:
    -- "bots seem to use Takweesh before realistically knowing if it
    -- is valid (it is valid but they did not see the violation)."
    -- Real Takweesh requires the caller to have OBSERVED the
    -- violation through publicly-visible play. The proof is when
    -- the violator later plays a card of the led suit in a
    -- subsequent trick, revealing they had it during the original
    -- off-suit play.
    --
    -- Realistic-observation predicate: for an opp's off-suit play
    -- at trick N, observation is confirmed if the same opp seat
    -- played a card of trick N's led suit at any later trick
    -- (or in the current in-progress trick). Card-counting via
    -- Bot._memory[seat].played gives the human-equivalent
    -- detection — what a vigilant Saudi-table player would track.
    local function laterPlayedLeadSuit(violatorSeat, originalLeadSuit, fromTrickIdx)
        if not violatorSeat or not originalLeadSuit
           or not S.s.tricks then return false end
        for tIdx2 = fromTrickIdx + 1, #S.s.tricks do
            local laterTrick = S.s.tricks[tIdx2]
            for _, p2 in ipairs(laterTrick.plays or {}) do
                if p2.seat == violatorSeat and p2.card
                   and C.Suit(p2.card) == originalLeadSuit then
                    return true
                end
            end
        end
        -- Also check current in-progress trick
        if S.s.trick and S.s.trick.plays then
            for _, p2 in ipairs(S.s.trick.plays) do
                if p2.seat == violatorSeat and p2.card
                   and C.Suit(p2.card) == originalLeadSuit then
                    return true
                end
            end
        end
        return false
    end

    -- Find the first realistically-observable illegal opposing play.
    local found
    for tIdx, t in ipairs(S.s.tricks or {}) do
        for _, p in ipairs(t.plays or {}) do
            if p.illegal and R.TeamOf(p.seat) ~= myTeam then
                -- Realism gate: was the violation later revealed
                -- by the violator playing the led-suit in a
                -- subsequent trick? If yes → bot can call
                -- Takweesh from publicly-visible info. If no →
                -- skip (the violation, while real, isn't yet
                -- publicly proven).
                if t.leadSuit and laterPlayedLeadSuit(p.seat, t.leadSuit, tIdx) then
                    found = p; break
                end
            end
        end
        if found then break end
    end
    -- v1.5.1: do NOT scan in-progress trick — a violation in the
    -- current trick has zero opportunity for "later reveal," so
    -- the realism gate would always fail. Skip entirely.
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
--   • S.s.hostHands[seat] exists and has ≤6 cards (v0.11.16 audit H3:
--     was ≤4; raised to allow legitimate 5/6-card SWAs per Saudi rule
--     "5+ cards is mandatory PERMISSION", NOT forbidden — endgame.md
--     191-198, decision-trees.md:207, CLAUDE.md:64-76. The Net.lua
--     5-second permission flow handles 5+ correctly; the artificial
--     #hand>4 cap was eliminating legitimate SWAs especially in Sun
--     where holding A+T+A+T at trick 4 is a guaranteed claim.)
--   • R.IsValidSWA returns true on the reconstructed trick state
function Bot.PickSWA(seat)
    if not Bot.IsAdvanced() then return false end
    if S.s.phase ~= K.PHASE_PLAY then return false end
    if not S.s.contract then return false end
    local hand = S.s.hostHands and S.s.hostHands[seat]
    if not hand or #hand == 0 or #hand > 6 then return false end
    -- v0.11.7 user feedback: don't bother SWA-claiming with only 1
    -- card left — the bot is about to play that card as the final
    -- trick anyway. An SWA banner + permission flow + claim-verified
    -- announcement for a single forced play is just UI noise. Just
    -- play. (Real-game flow: the bot's MaybeRunBot dispatch will
    -- play the card on the next turn after this PickSWA returns
    -- false; nothing else needs to change.)
    if #hand <= 1 then return false end

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
    if not R.IsValidSWA(seat, hands, S.s.contract, trickState) then
        return false
    end

    -- v0.5.21 user-reported safety net: in Hokm, additionally require
    -- that caller holds the HIGHEST unplayed trump OR no opponent has
    -- any trump remaining. R.IsValidSWA is strict-caller-correct
    -- (post-v0.5.17), but the user reports observing SWA-while-opp-
    -- has-trump scenarios that "feel wrong" — possibly false-positives
    -- from edge cases in the recursive validator, possibly UI-banner
    -- misinterpretation. This belt-and-suspenders gate makes the
    -- bot strictly conservative in Hokm: SWA only fires when the
    -- top-trump position is unambiguous.
    -- Sources: user-direct on v0.5.20 → v0.5.21 transition.
    if S.s.contract.type == K.BID_HOKM and S.s.contract.trump then
        local trump = S.s.contract.trump
        -- Find caller's highest trump (if any).
        local callerTopRank = -1
        for _, c in ipairs(hand) do
            if C.Suit(c) == trump then
                local r = C.TrickRank(c, S.s.contract)
                if r > callerTopRank then callerTopRank = r end
            end
        end
        -- Find opponents' highest trump (if any).
        local oppTopRank = -1
        for s2 = 1, 4 do
            if R.TeamOf(s2) ~= R.TeamOf(seat) then
                for _, c in ipairs(hands[s2]) do
                    if C.Suit(c) == trump then
                        local r = C.TrickRank(c, S.s.contract)
                        if r > oppTopRank then oppTopRank = r end
                    end
                end
            end
        end
        -- Reject if any opp trump is higher than caller's top trump.
        -- (oppTopRank == -1 means no opp trump → safe.
        --  callerTopRank == -1 + oppTopRank > -1 means opp has trump and
        --  we don't → reject. Caller would lose any trick to opp's ruff.)
        if oppTopRank > callerTopRank then
            return false
        end
    end

    return true
end

-- ---------------------------------------------------------------------
-- SWA-response: deny clearly-invalid claims (v0.11.16 audit H1)
-- ---------------------------------------------------------------------
-- When an opponent calls SWA, the host runs bot response on cross-team
-- seats. Returns true (ACCEPT) for any plausible SWA, false (DENY) only
-- when R.IsValidSWA strictly rejects (bots have host-side full info via
-- S.s.hostHands). Defaults toward ACCEPT to match addon UX (5-second
-- auto-approve is human-deadlock prevention); DENY reserved for
-- clearly-invalid claims. Saudi rule: endgame.md:185-187 +
-- decision-trees.md:209 — Takweesh denial demands شرح (proof).
function Bot.PickSWAResponse(seat, callerSeat, encodedCallerHand)
    if not S.s.isHost then return true end  -- only host runs bots
    if not S.s.contract then return true end
    if not callerSeat or callerSeat < 1 or callerSeat > 4 then
        return true
    end
    if seat == callerSeat then return true end  -- can't deny own SWA
    -- v1.0.2 (M6): defense-in-depth — Net.LocalSWAResp / _OnSWAResp
    -- already gate partners out (Net.lua:2922), so PickSWAResponse
    -- in normal flow is only ever called with an opp-team `seat`.
    -- This branch is unreachable through the wire path. Kept as a
    -- safety net for any future direct invocation (test harness,
    -- replay path). Documented per audit M6 finding rather than
    -- removed — symmetric SWA branches all keep their team gates.
    if R.TeamOf(seat) == R.TeamOf(callerSeat) then
        return true  -- partner always accepts (defense-in-depth)
    end

    -- Reconstruct trick state for the validator (mirrors Bot.PickSWA
    -- and N.HostResolveSWA logic).
    local trickPlays = (S.s.trick and S.s.trick.plays) or {}
    local trickLead = S.s.trick and S.s.trick.leadSuit
    local trickLeader
    if #trickPlays > 0 then
        trickLeader = trickPlays[1].seat
    else
        trickLeader = S.s.turn or callerSeat
    end
    local trickState = {
        leadSuit = trickLead, leader = trickLeader, plays = trickPlays,
    }

    -- Hands: caller's via the wire (encoded); others via host's
    -- authoritative hostHands. If encoded is missing, accept (we
    -- can't validate without it; default to safe ACCEPT).
    local hands = {}
    for s2 = 1, 4 do
        if s2 == callerSeat and encodedCallerHand and #encodedCallerHand > 0 then
            hands[s2] = (C and C.DecodeHand) and C.DecodeHand(encodedCallerHand) or
                        (S.s.hostHands and S.s.hostHands[s2]) or {}
        else
            hands[s2] = (S.s.hostHands and S.s.hostHands[s2]) or {}
        end
    end

    -- v0.11.18-final H2 (ultra audit): mirror HostResolveSWA's W7
    -- corrupted-state guard. Pre-fix the validator's base-case
    -- short-circuit (no remaining cards = trivial caller-win) was
    -- accepted as a valid SWA; HostResolveSWA explicitly forces
    -- valid=false on this state pre-call. Bot now matches.
    if (#(hands[callerSeat] or {})) == 0 and #trickPlays == 0 then
        return false
    end

    -- Defensive pcall — never crash a bot on validator edge cases;
    -- accept by default. Strict-deny only on a definitively-false
    -- validator return.
    local ok, valid = pcall(R.IsValidSWA, callerSeat, hands, S.s.contract, trickState)
    if not ok then return true end  -- pcall fail → accept
    if valid == false then return false end  -- deny clearly-invalid

    -- v0.11.18-final H1 (ultra audit): mirror PickSWA's Hokm safety
    -- net for symmetry. PickSWA (caller-side) rejects when opp's
    -- top trump > caller's top trump (line ~4389-4418 below). Pre-
    -- fix PickSWAResponse only ran IsValidSWA, so a human caller
    -- could fire a validator-passing SWA where PickSWA's safety net
    -- would have blocked it (e.g., 6-card Hokm where caller-top-trump
    -- = T but opp-top-trump = A in validator-passing edge cases).
    -- Bots now defend with the same conservatism they call with.
    if S.s.contract and S.s.contract.type == K.BID_HOKM and S.s.contract.trump then
        local trump = S.s.contract.trump
        local TRUMP_RANK = K.RANK_TRUMP_HOKM or {}
        local callerTopRank = -1
        local oppTopRank = -1
        for s2 = 1, 4 do
            for _, c in ipairs(hands[s2] or {}) do
                if C.Suit(c) == trump then
                    local trickRank = TRUMP_RANK[C.Rank(c)] or 0
                    if s2 == callerSeat then
                        if trickRank > callerTopRank then
                            callerTopRank = trickRank
                        end
                    elseif R.TeamOf(s2) ~= R.TeamOf(callerSeat) then
                        if trickRank > oppTopRank then
                            oppTopRank = trickRank
                        end
                    end
                end
            end
        end
        if oppTopRank > callerTopRank then return false end
    end

    return true
end
