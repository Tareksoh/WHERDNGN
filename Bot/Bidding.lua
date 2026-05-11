-- WHEREDNGN Bot/Bidding.lua
--
-- Bidding-window deciders + their helpers, extracted from Bot.lua in
-- v3.2.0 cleanup batch 8. This module owns:
--
--   * Bot.PickBid       (R1/R2 bidding decision; the giant ~590-line decider)
--   * Bot.PickPreempt   (triple-on-Ace pre-emption for non-bidders)
--   * Bot.PickOvercall  (Sun overcall window after a Hokm bid)
--   * Bot.OpponentUrgency (public — read by BotMaster.lua)
--   * Bot._beloteBypassQualifies (test-internal export at test_state_bot.lua:6230)
--
-- All 14 bidding helpers (sideSuitAceBonus, hokmMinShape, sunMinShape,
-- beloteSuit, beloteBypassQualifies, aceCountAndMardoofa, withBidcard,
-- sunStrength, partnerBidBonus, scoreUrgency, opponentUrgency,
-- matchPointUrgency, combinedUrgency, partnerEscalatedBonus) are
-- declared `local function` inside this file. Five of them
-- (sunStrength, partnerBidBonus, partnerEscalatedBonus,
-- combinedUrgency, opponentUrgency) are also re-exported via the
-- `Bot.Bidding.*` sub-table so Bot.lua's escalation deciders can
-- re-bind them as file-locals.
--
-- `bidderHoldsBidcard` STAYS in Bot.lua (its only caller is pickLead/
-- pickFollow's trump-J inference). The bidding cluster is therefore
-- split into two ranges: lines 1034-1289 (sideSuitAceBonus through
-- aceCountAndMardoofa) and lines 1319-2273 (withBidcard through end of
-- Bot.PickBid) in the pre-extraction Bot.lua.
--
-- The .toc loads Bot/Bidding.lua after Bot/PlayPrimitives.lua and
-- before Bot.lua so the Bidding sub-table exists when Bot.lua's
-- re-binding header runs.

WHEREDNGN = WHEREDNGN or {}
local B = WHEREDNGN
B.Bot = B.Bot or {}
local Bot = B.Bot
local K, C, R, S = B.K, B.Cards, B.Rules, B.State

local Bidding = Bot.Bidding or {}
Bot.Bidding = Bidding

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

-- BEL_JITTER for PickPreempt's `jitter(th, BEL_JITTER)` call. Mirrors
-- the same `local BEL_JITTER = 10` that stays in Bot.lua for
-- escalationStrength + the escalation deciders. Two independent
-- file-locals, same value.
local BEL_JITTER      = 10


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


-- ---------------------------------------------------------------------
-- Bidding sub-table exports
-- ---------------------------------------------------------------------
-- Narrow surface: only helpers still consumed by Bot.lua post-extraction
-- (escalation deciders + escalationStrength) are exposed via the
-- sub-table for Bot.lua's re-binding header. scoreUrgency and
-- matchPointUrgency stay file-local — Bot.lua has zero remaining
-- call sites for them after the move.

Bidding.suitStrengthAsTrump     = suitStrengthAsTrump
Bidding.sunStrength             = sunStrength
Bidding.partnerBidBonus         = partnerBidBonus
Bidding.partnerEscalatedBonus   = partnerEscalatedBonus
Bidding.combinedUrgency         = combinedUrgency
Bidding.opponentUrgency         = opponentUrgency
