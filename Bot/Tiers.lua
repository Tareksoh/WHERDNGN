-- WHEREDNGN Bot/Tiers.lua
--
-- Tier-detection predicates extracted from Bot.lua in v3.2.0 cleanup
-- batch 5B. These five functions classify the bot strength tier from
-- the saved-variable feature flags (and one State helper for the
-- bot-vs-human seat check). They are public on `B.Bot.*` so every
-- existing call site (Bot.IsAdvanced(), Bot.IsM3lm(), etc.) inside
-- Bot.lua continues to resolve through the shared B.Bot table — no
-- re-binding header is needed in Bot.lua.
--
-- The .toc loads this file after State.lua (we depend on
-- S.IsSeatBot for Bot.IsBotSeat) and before Bot.lua (so the
-- predicates exist by the time Bot.lua's chunk runs and Bot.PickPlay
-- et al. close over them via the shared local Bot reference).

WHEREDNGN = WHEREDNGN or {}
local B = WHEREDNGN
B.Bot = B.Bot or {}
local Bot = B.Bot
local S = B.State

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
