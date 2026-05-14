-- WHEREDNGN Bot/PlayPrimitives.lua
--
-- Play-primitive helpers extracted from Bot.lua in v3.2.0 cleanup
-- batch 5C. Ten pure(-ish) helpers that pickLead / pickFollow /
-- PickAKA / PickPlay / escalation deciders close over to evaluate
-- card legality, ranking, and partner Tahreeb signals:
--
--   * pickRandomTied           — randomized tie-break (audit HIGH-1)
--   * lowestByRank             — trick-rank min (with tie-break)
--   * highestByRank            — trick-rank max (with tie-break)
--   * highestByFaceValue       — face-value max (with tie-break)
--   * holdsBeloteThusFar       — K+Q-of-trump check (Belote pair)
--   * highestTrump             — top trump in a card list
--   * legalPlaysFor            — legality filter (passes live AKA)
--   * wouldWin                 — simulate a play and ask R who wins
--   * tahreebClassify          — partner-signal classifier (Saudi
--                                "want"/"dontwant"/"bargiya"/etc.)
--   * applyClosedTrumpLeadGate — Bel/Four closed-trump filter
--
-- They are exported via the B.Bot.Primitives table so Bot.lua's
-- re-binding header (file-local `lowestByRank = Primitives.lowestByRank`,
-- etc.) keeps every existing call site resolving unchanged. Inter-
-- primitive calls (lowest/highest/highestByFaceValue → pickRandomTied)
-- stay as file-local closures inside this module — no need to route
-- through Primitives.foo internally.
--
-- The .toc loads this file after Bot/Tiers.lua and before Bot.lua, so
-- B.Bot.Primitives exists when Bot.lua's re-binding header runs.

WHEREDNGN = WHEREDNGN or {}
local B = WHEREDNGN
B.Bot = B.Bot or {}
local Bot = B.Bot
local K, C, R, S = B.K, B.Cards, B.Rules, B.State

local Primitives = Bot.Primitives or {}
Bot.Primitives = Primitives

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
            -- Replace with filtered view; preserve lenAtAce and
            -- lenAtFirstDiscard only if the first non-forced event
            -- matches the original first. Both fields describe the
            -- sender's pre-discard suit-size at the very first signal
            -- event; if forced filtering changes which event is "first",
            -- the size no longer applies to the new first event.
            filtered.lenAtAce = (filtered[1] == signals[1])
                                 and signals.lenAtAce or nil
            filtered.lenAtFirstDiscard = (filtered[1] == signals[1])
                                 and signals.lenAtFirstDiscard or nil
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
    -- v3.0.2 (user-reported by expert friend: "when I play a different-
    -- suit big card it means do not come back to me with that"). Verified
    -- against docs/strategy/signals.md video #1 form #1: "Same-suit top-
    -- down — high then lower in same suit = 'I do NOT want this suit'".
    -- The TWO-card pattern was already handled below ("descending →
    -- dontwant"); the SINGLE big-card case was lost to the catch-all
    -- "hint" return — even though the underlying signal-direction is
    -- already there in the first event. Promote single discards of T or
    -- K (the two highest non-Ace plain ranks) to "dontwant". A is
    -- already special-cased above (bargiya). J / Q / 9 / 8 / 7 stay
    -- "hint" — those are mid-or-low ranks where direction is genuinely
    -- ambiguous from a single event. The forced filter above already
    -- strips no-choice discards, so reaching this point implies a
    -- voluntary high-card dump.
    if #signals == 1 then
        local plain = K.RANK_PLAIN
        local r = plain[signals[1]] or 0
        local rK = plain["K"] or 0
        local r9 = plain["9"] or 0
        if r >= rK then
            -- T or K (in plain rank, T is highest non-Ace at index 7,
            -- K at index 6). A would have routed to bargiya above.
            return "dontwant"
        end
        -- v3.0.3 GAP-01 (audit doc-vs-code differential, mirror of
        -- v3.0.2 single-big-card fix). Per signals.md video #1 form 5
        -- + decision-trees.md:222: "Bottom-up same-suit — low first,
        -- higher next = 'I want this suit (and don't have its Ace)'".
        -- Single-low (7/8/9) has the SAME informational content as the
        -- FIRST event of the canonical low-then-higher sequence — the
        -- partner just hasn't had a second chance to confirm. Demoting
        -- to "want_hint" (lower confidence than confirmed "want") with
        -- weight 1 (parity with bargiya_hint) preserves the directional
        -- read while letting confirmed multi-event "want" (weight 2)
        -- and confirmed "bargiya" (weight 3) dominate when present.
        -- J/Q remain "hint" because mid-rank singles are genuinely
        -- ambiguous (no top-down vs bottom-up disambiguation possible
        -- without context tracking).
        --
        -- v3.0.6 SENDER-INTENT alignment: gate "want_hint" on the
        -- sender's pre-discard suit-size. Bot SENDERS emit low cards
        -- via TWO paths:
        --   (a) bottom-up "want" arm (Tahreeb "want" sender in
        --       pickFollow, Sun-only) discards lowest from a 3+
        --       no-A no-T suit. Intent: "want this suit"
        --       → single-low correctly reads as "want_hint".
        --   (b) T-4 dump-larger arm (Tahreeb T-4 sender in
        --       pickFollow) discards LARGER first from a 2-card
        --       no-honor doubleton. Intent:
        --       "descending = dontwant" (full pattern needs 2 events).
        --       Single 9 from 9+7 doubleton — or single 8 from 8+7 —
        --       would mis-read as "want_hint" without this gate.
        -- The recorder host-side stashes `lenAtFirstDiscard` (Bot.lua
        -- ~755-770) so the classifier can require ≥3 cards held in
        -- the suit at discard time before promoting to "want_hint".
        -- When `lenAtFirstDiscard` is missing (non-host clients,
        -- pre-v3.0.6 fixtures, human discards we can't observe),
        -- fall back to "hint" — the conservative read.
        if r <= r9 then
            local lenAtFirst = signals.lenAtFirstDiscard or 0
            if lenAtFirst >= 3 then
                return "want_hint"
            end
            -- Sender held only 1-2 cards (T-4 dump territory) or
            -- size unknown → ambiguous single event, default to
            -- "hint" until a 2nd event disambiguates direction.
            return "hint"
        end
        return "hint"
    end
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

-- Export the file-local helpers. Bot.lua's re-binding header
-- re-imports each as a file-local so existing call sites resolve
-- unchanged.
Primitives.pickRandomTied           = pickRandomTied
Primitives.lowestByRank             = lowestByRank
Primitives.highestByRank            = highestByRank
Primitives.highestByFaceValue       = highestByFaceValue
Primitives.holdsBeloteThusFar       = holdsBeloteThusFar
Primitives.highestTrump             = highestTrump
Primitives.legalPlaysFor            = legalPlaysFor
Primitives.wouldWin                 = wouldWin
Primitives.tahreebClassify          = tahreebClassify
Primitives.applyClosedTrumpLeadGate = applyClosedTrumpLeadGate
