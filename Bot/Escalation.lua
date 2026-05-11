-- WHEREDNGN Bot/Escalation.lua
--
-- Escalation-window deciders + their helpers, extracted from Bot.lua
-- in v3.2.0 cleanup batch 9. This module owns the four-rung escalation
-- chain (Bel ×2 -> Triple ×3 -> Four ×4 -> Gahwa match-win):
--
--   * Bot.PickDouble    (defender's Bel response)
--   * Bot.PickTriple    (bidder's Triple counter)
--   * Bot.PickFour      (defender's Four counter)
--   * Bot.PickGahwa     (bidder's terminal Gahwa)
--
-- Plus the 3 file-local helpers consumed only by these pickers:
--
--   * escalationStrength    -- shared bid-strength calc for the
--                              three bidder-side pickers (Triple,
--                              Four, Gahwa)
--   * selfStyleJitterBonus  -- Fzloky+ jitter-widening based on
--                              the seat's lifetime escalation count
--   * styleBelTendency      -- partner-style tendency read consumed
--                              by Bot.PickTriple
--
-- And the 4 per-rung jitter constants (BEL_JITTER, TRIPLE_JITTER,
-- FOUR_JITTER, GAHWA_JITTER).
--
-- DOES NOT include Bot.OnEscalation / Bot.OnRoundEnd / emptyStyle /
-- styleTrumpTempo / Bot._partnerStyle / Bot._memory -- those are
-- style-ledger maintenance code consumed by State.lua and the play
-- pickers (pickLead / pickFollow), and they stay in Bot.lua.
--
-- The .toc loads this file AFTER Bot/Bidding.lua (whose 6 helpers
-- are re-imported below) and BEFORE Bot.lua (so the public
-- Bot.PickDouble / PickTriple / PickFour / PickGahwa are set on the
-- shared B.Bot table by the time Net.lua's MaybeRunBot reads them
-- at runtime).

WHEREDNGN = WHEREDNGN or {}
local B = WHEREDNGN
B.Bot = B.Bot or {}
local Bot = B.Bot
local K, C, R, S = B.K, B.Cards, B.Rules, B.State

-- Bidding helpers consumed by the escalation deciders live in
-- Bot/Bidding.lua (Batch 8 extraction). Re-bind as file-locals so
-- escalationStrength + the 4 pickers close over the same names that
-- the pre-Batch-9 source used inside Bot.lua.
local Bidding                 = Bot.Bidding
local suitStrengthAsTrump     = Bidding.suitStrengthAsTrump
local sunStrength             = Bidding.sunStrength
local partnerBidBonus         = Bidding.partnerBidBonus
local partnerEscalatedBonus   = Bidding.partnerEscalatedBonus
local combinedUrgency         = Bidding.combinedUrgency
local opponentUrgency         = Bidding.opponentUrgency

-- Inline copies of the two universal helpers used by every picker
-- across the codebase. Bot.lua keeps the canonical originals (still
-- used by jitter/shuffledSuits call sites in pickLead/pickFollow);
-- this duplicate keeps Bot/Escalation.lua self-contained. Same
-- pattern as Bot/Bidding.lua's inline copies (Batch 8).
local function jitter(base, amp)
    return base + math.random(-amp, amp)
end

local function shuffledSuits()
    local s = { "S", "H", "D", "C" }
    -- Fisher-Yates in-place shuffle.
    for i = 4, 2, -1 do
        local j = math.random(i)
        s[i], s[j] = s[j], s[i]
    end
    return s
end

-- Partner-style tendency read consumed only by Bot.PickTriple to
-- penalize habitual-Beler defenders. Returns 1 if the partner has
-- Bel'ed 2+ times this game (loose Bel pattern), 0 on a single Bel,
-- and nil if the ledger has no data yet. Companion `styleTrumpTempo`
-- helper stays in Bot.lua because it's consumed by pickLead/pickFollow
-- play decisions.
local function styleBelTendency(seat)
    if not Bot._partnerStyle then return nil end
    local m = Bot._partnerStyle[seat]
    if not m or m.bels < 1 then return nil end
    if m.bels >= 2 then return 1 end
    return 0
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
