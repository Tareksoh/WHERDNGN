-- Addon-channel networking.
--
-- Wire format: "<TAG>;<f1>;<f2>;..." top-level fields separated by ;.
-- Lists inside a field use comma. See K.MSG_* in Constants.lua for
-- the tag table; each handler below documents its payload.
--
-- All public broadcasts go to PARTY (party only — RAID/GUILD intentionally
-- excluded for v1). Private hand deals go via WHISPER to the seat owner.
--
-- Throttling: we send <1 msg/sec on average per client. No
-- ChatThrottleLib needed; we don't even come close to the 10/s budget.
--
-- Loopback: SendAddonMessage delivers to the sender too, so the host's
-- own broadcasts feed back through the same handler tree.

WHEREDNGN = WHEREDNGN or {}
local B = WHEREDNGN
B.Net = B.Net or {}
local N = B.Net
local K, C, R, S = B.K, B.Cards, B.Rules, B.State
local L = B.Log

local function log(level, ...) L[level]("net", ...) end

-- Forward declarations. The Local* action functions below reference
-- `cancelLocalWarn` in their closures, but the AFK pre-warn helpers
-- aren't defined until later in the file (next to the host-side turn
-- timer). Without these, the closures would bind to a global of the
-- same name and crash when the action fires (`attempt to call a nil
-- value (global 'cancelLocalWarn')`). With the local declared here,
-- the closures bind to this upvalue and resolve correctly at runtime
-- once the assignments below populate it.
local cancelLocalWarn

-- -- Send -----------------------------------------------------------

local function broadcast(msg)
    if not msg or #msg == 0 then return end
    if not IsInGroup() then return end
    if IsInRaid() then
        log("Warn", "in raid, party-only protocol skipping send: %s", msg)
        return
    end
    local ok, err = pcall(C_ChatInfo.SendAddonMessage, K.PREFIX, msg, "PARTY")
    if not ok then log("Warn", "send failed: %s", tostring(err)) end
end

local function whisper(target, msg)
    if not target or not msg or #msg == 0 then return end
    local ok, err = pcall(C_ChatInfo.SendAddonMessage, K.PREFIX, msg, "WHISPER", target)
    if not ok then log("Warn", "whisper failed: %s", tostring(err)) end
end

N.Broadcast = broadcast
N.Whisper   = whisper

-- 14th-audit helper (scoring-vs-rules audit). Saudi rule for Sun Bel
-- (per "نظام الدبل في لعبة البلوت"):
--   "ولايحق للاعب ان يدبل خصمة الا بعد ان يتجاوز المئة اي 101"
--   "ويكون الدبل للمتأخر فقط وهو الذي لم يتجاوز عدده 100"
-- ⇒ Sun Bel is allowed only when:
--   (a) the BIDDER team's cumulative has crossed 100 (>= 101), AND
--   (b) the DEFENDER team's cumulative is still BELOW 101 (the
--       "behind" team that gets to double).
-- If both teams are below 101 (no one crossed yet) OR both are
-- above 100 (no one is "behind"), Sun Bel is silently skipped.
-- Hokm has no such gate (Bel/Triple/Four open from any score).
function N._SunBelAllowed(bidderSeat)
    if not bidderSeat then return false end
    -- v0.10.0 R1 fix (review_v0.10.0/reaudit_R1_bel100.md): Sun-Bel
    -- is score-split, role-irrelevant. Either team is eligible iff
    -- that team is at ≤100 AND the other is at ≥101. The two teams
    -- are mutually exclusive on this gate (only one team can be the
    -- trailer on a strict-split), so we just ask whichever team is
    -- currently trailing. Passing `bidder = bidderSeat` no longer
    -- affects R.CanBel's output but documents intent.
    local cumA = (S.s.cumulative and S.s.cumulative.A) or 0
    local cumB = (S.s.cumulative and S.s.cumulative.B) or 0
    local trailingTeam = (cumA <= cumB) and "A" or "B"
    return R.CanBel(trailingTeam,
                    { type = K.BID_SUN, bidder = bidderSeat },
                    S.s.cumulative)
end

-- High-level senders. These are called by State / UI; they format and
-- broadcast or whisper. Most are host-only invocations.

function N.SendHostAnnounce(gameID)
    -- Trailing field is the host's addon version so peers can flag
    -- mismatches before joining. Old clients just ignore the extra
    -- field — backward compatible.
    broadcast(("%s;%s;%s"):format(K.MSG_HOST, gameID, K.GetAddonVersion()))
end

function N.SendJoin(gameID)
    broadcast(("%s;%s;%s"):format(K.MSG_JOIN, gameID, K.GetAddonVersion()))
end

function N.SendLobby(seats, gameID)
    -- Wire format: L;<gameID>;<n1>;<n2>;<n3>;<n4>;<botMask4>;<hostVersion>
    -- The bot mask lets non-hosts tell bots from humans (otherwise
    -- authorizeSeat rejects host-signed bot bids). Trailing version
    -- field surfaces on peers as the host's addon version.
    local names, bots = {}, {}
    for i = 1, 4 do
        local s = seats[i]
        names[i] = (s and s.name) or ""
        bots[i] = (s and s.isBot) and "1" or "0"
    end
    broadcast(("%s;%s;%s;%s;%s"):format(K.MSG_LOBBY, gameID,
        table.concat(names, ";"), table.concat(bots, ""),
        K.GetAddonVersion()))
end

function N.SendStart(roundNumber, dealer)
    broadcast(("%s;%d;%d"):format(K.MSG_START, roundNumber, dealer))
end

function N.SendDealPhase(phase)
    broadcast(("%s;%s"):format(K.MSG_DEAL, tostring(phase)))
end

function N.SendHand(target, cards)
    -- Tag the hand with the current round number so a late ApplyStart
    -- for the same round won't wipe it on the recipient.
    local rn = (S.s.roundNumber or 0)
    whisper(target, ("%s;%d;%s"):format(K.MSG_HAND, rn, C.EncodeHand(cards)))
end

-- Whisper the hand to every non-bot, non-self seat. Bots live only on
-- the host (their "hand" is in s.hostHands), so there's no peer to
-- whisper. The host's own hand is set directly via S.ApplyHand.
local function dealHandsToHumans(hands)
    for seat = 1, 4 do
        local info = S.s.seats[seat]
        if info and not info.isBot and seat ~= S.s.localSeat then
            N.SendHand(info.name, hands[seat])
        end
    end
end

function N.SendBidCard(card)
    -- Audit Cl22 fix: when card is nil, "%s" stringifies it to "nil",
    -- producing the wire frame "b;nil". Receivers store the literal
    -- string "nil" in s.bidCard, which UI's truthy check treats as a
    -- real card and tries to render. Coalesce to empty string so the
    -- field round-trips as a clear no-card sentinel.
    broadcast(("%s;%s"):format(K.MSG_BIDCARD, card or ""))
end

function N.SendTurn(seat, kind)
    broadcast(("%s;%d;%s"):format(K.MSG_TURN, seat, kind))
    -- Host arms the AFK auto-action timer for human seats. Bots
    -- self-act via MaybeRunBot and aren't subject to the timeout.
    if S.s.isHost then N.StartTurnTimer(seat, kind) end
end

function N.SendBid(seat, bid)
    broadcast(("%s;%d;%s"):format(K.MSG_BID, seat, bid))
end

function N.SendContract(bidder, btype, trump)
    broadcast(("%s;%d;%s;%s"):format(K.MSG_CONTRACT, bidder, btype, trump or ""))
end

-- Escalation broadcasts. v0.2.0+ wire format adds an Open/Closed flag:
-- "<TAG>;<seat>;<open>" where <open> is "1" (open — chain may continue)
-- or "0" (closed — chain stops here, no next rung). Clients on
-- pre-v0.2.0 wire that lack the flag are treated as Open (default).
-- Gahwa is terminal so no flag is meaningful there.
function N.SendDouble(seat, open)
    broadcast(("%s;%d;%s"):format(K.MSG_DOUBLE, seat,
        (open == false) and "0" or "1"))
end

function N.SendTriple(seat, open)
    broadcast(("%s;%d;%s"):format(K.MSG_TRIPLE, seat,
        (open == false) and "0" or "1"))
end

function N.SendFour(seat, open)
    broadcast(("%s;%d;%s"):format(K.MSG_FOUR, seat,
        (open == false) and "0" or "1"))
end

function N.SendGahwa(seat)
    broadcast(("%s;%d"):format(K.MSG_GAHWA, seat))
end

-- v1.0.11 (D HIGH-2): Baloot/Belote announcement broadcast.
function N.SendBelote(seat)
    broadcast(("%s;%d"):format(K.MSG_BELOTE, seat))
end

-- v1.0.11 (D HIGH-2): host-side auto-announce on bot K/Q-of-trump play.
-- After a bot's play of K-or-Q-of-trump, if the same seat has now
-- played BOTH K and Q of trump (this play closing the pair), announce
-- the +20 Belote bonus on their behalf. Bots always announce in real
-- Saudi play; humans must click the BALOOT! UI button.
--
-- Called only from the host's bot-play paths in MaybeRunBot.
-- Safe to call for non-bot plays too (the seat-bot check is a no-op
-- if the seat isn't a bot in our table — currently the helper trusts
-- the caller to gate; double-check via S.s.seats).
function N._HostMaybeAutoBelote(seat, card)
    if not S.s.isHost then return end
    if not S.s.contract or not S.s.contract.trump then return end
    if S.s.contract.type ~= K.BID_HOKM then return end
    if not seat or not card then return end
    if S.s.beloteAnnounced and S.s.beloteAnnounced[seat] then return end
    -- Only auto-announce for bot seats (humans must click the button).
    local seats = S.s.seats or {}
    if not seats[seat] or not seats[seat].isBot then return end
    -- Was this play K-or-Q of trump?
    if C.Suit(card) ~= S.s.contract.trump then return end
    local r = C.Rank(card)
    if r ~= "K" and r ~= "Q" then return end
    -- Has the same seat played the OTHER (K or Q) of trump in any
    -- prior trick (or earlier in the current trick)?
    local kPlayed, qPlayed = false, false
    local function scan(plays)
        for _, p in ipairs(plays or {}) do
            if p.seat == seat and C.Suit(p.card) == S.s.contract.trump then
                if     C.Rank(p.card) == "K" then kPlayed = true
                elseif C.Rank(p.card) == "Q" then qPlayed = true end
            end
        end
    end
    for _, t in ipairs(S.s.tricks or {}) do scan(t.plays) end
    if S.s.trick then scan(S.s.trick.plays) end
    if kPlayed and qPlayed then
        S.ApplyBeloteAnnounce(seat)
        N.SendBelote(seat)
    end
end

function N.SendPreempt(seat)
    broadcast(("%s;%d"):format(K.MSG_PREEMPT, seat))
end

function N.SendPreemptPass(seat)
    broadcast(("%s;%d"):format(K.MSG_PREEMPT_PASS, seat))
end

function N.SendMeld(seat, meld)
    broadcast(("%s;%d;%s;%s;%s;%s"):format(
        K.MSG_MELD, seat, meld.kind, meld.suit or "", meld.top or "",
        C.EncodeHand(meld.cards or {})))
end

-- AKA (إكَهْ) signal. The caller's seat tells everyone they hold the
-- highest unplayed card in `suit`; teammate is supposed to NOT
-- over-trump. Soft signal — no rule enforcement, just a banner +
-- voice cue.
function N.SendAKA(seat, suit)
    broadcast(("%s;%d;%s"):format(K.MSG_AKA, seat, suit or ""))
end

-- SWA broadcast: caller declares they'll win all remaining tricks
-- and reveals their remaining hand for verification. The host
-- responds with an MSG_SWA_OUT result (valid + point delta).
function N.SendSWA(seat, encodedHand)
    broadcast(("%s;%d;%s"):format(K.MSG_SWA, seat, encodedHand or ""))
end

function N.SendSWAOut(caller, valid, addA, addB, totA, totB, sweep, bidderMade, encodedHand)
    -- 4th-audit X4 fix: append sweep + bidderMade flags so receivers
    -- can fire the BALOOT fanfare on SWA-resolved sweeps / failed
    -- contracts (host's direct ApplyRoundEnd call already covers
    -- the host side; this closes the gap for remote clients).
    -- Three-state encoding ("" | "0" | "1") matches MSG_ROUND.
    -- v0.11.7 user feedback: append the caller's encoded hand as
    -- field 10 so the post-resolution banner can show the cards
    -- (especially for teammate-bot SWAs which the player previously
    -- only saw as "verified" with no visible hand). Append-only so
    -- pre-v0.11.7 clients reading the old 9-field form work
    -- unchanged.
    local sweepStr = (sweep == "A" or sweep == "B") and sweep or ""
    local madeStr
    if bidderMade == true       then madeStr = "1"
    elseif bidderMade == false  then madeStr = "0"
    else                              madeStr = "" end
    broadcast(("%s;%d;%s;%d;%d;%d;%d;%s;%s;%s"):format(
        K.MSG_SWA_OUT, caller, valid and "1" or "0",
        addA, addB, totA, totB, sweepStr, madeStr, encodedHand or ""))
end

function N.SendSWAReq(seat, encodedHand)
    broadcast(("%s;%d;%s"):format(K.MSG_SWA_REQ, seat, encodedHand or ""))
end

function N.SendSWAResp(responder, accept, caller)
    broadcast(("%s;%d;%s;%d"):format(
        K.MSG_SWA_RESP, responder, accept and "1" or "0", caller))
end

function N.SendPlay(seat, card)
    broadcast(("%s;%d;%s"):format(K.MSG_PLAY, seat, card))
end

function N.SendTrick(winner, points)
    -- Snapshot the full trick into the message so non-host clients
    -- always have the complete play set when ApplyTrickEnd fires —
    -- network ordering between MSG_PLAY and MSG_TRICK across DIFFERENT
    -- senders isn't guaranteed, so a non-host could otherwise apply
    -- trick-end with only 2-3 plays, leaving s.lastTrick incomplete
    -- and the peek button showing fewer cards than expected.
    --
    -- Wire format: leadSuit is one char; each play is 3 chars
    -- (card[2] + seat[1]), 4 plays = 12 chars.
    local enc = ""
    if S.s.trick and S.s.trick.plays then
        for _, p in ipairs(S.s.trick.plays) do
            enc = enc .. (p.card or "??") .. tostring(p.seat or 0)
        end
    end
    local leadSuit = (S.s.trick and S.s.trick.leadSuit) or ""
    broadcast(("%s;%d;%d;%s;%s"):format(
        K.MSG_TRICK, winner, points, leadSuit, enc))
end

function N.SendRound(addA, addB, totA, totB, sweep, bidderMade)
    -- Audit fix: include sweep + bidderMade flags so non-host clients
    -- can fire the BALOOT fanfare on AL-KABOOT or failed-contract.
    -- Previously only the host (via ApplyRoundResult on the
    -- HostScoreRoundResult struct) heard the fanfare.
    --
    -- Three-state encoding for bidderMade ("" | "0" | "1") so the
    -- receiver can distinguish "host didn't supply" (legacy / SWA /
    -- Takweesh paths) from explicit "bidder failed". Without this,
    -- pre-v0.3.0 hosts and Takweesh/SWA call sites that omit the
    -- flag would all decode as bidderMade=false, firing a spurious
    -- fanfare on every round-end. (Re-audit V16/V10/V9 finding.)
    local sweepStr = (sweep == "A" or sweep == "B") and sweep or ""
    local madeStr
    if bidderMade == true       then madeStr = "1"
    elseif bidderMade == false  then madeStr = "0"
    else                              madeStr = "" end
    broadcast(("%s;%d;%d;%d;%d;%s;%s"):format(
        K.MSG_ROUND, addA, addB, totA, totB, sweepStr, madeStr))
end

function N.SendGameEnd(winner)
    broadcast(("%s;%s"):format(K.MSG_GAMEEND, winner))
end

function N.SendPause(paused)
    broadcast(("%s;%s"):format(K.MSG_PAUSE, paused and "1" or "0"))
end

function N.SendTeams(teamA, teamB)
    broadcast(("%s;%s;%s"):format(K.MSG_TEAMS, teamA or "", teamB or ""))
end

-- Resync senders. Request is a broadcast (we don't know the host's
-- name until they reply); response is a private whisper.
-- v0.9.1 L5 fix (audit AUDIT_REPORT_v0.7.1.md): track whether we've
-- explicitly requested a resync. Pre-v0.9.1, a peer who overheard
-- the gameID could fabricate a MSG_RESYNC_RES and inject score-
-- state into our session (no hand exposure, but cumulative + bid +
-- contract leak). Now: only accept MSG_RESYNC_RES within a 30-second
-- window after we sent MSG_RESYNC_REQ. The flag clears on first
-- valid response OR on timeout.
local expectingResyncRes = false
local resyncResExpiryTimer = nil

function N.SendResyncReq(gameID)
    broadcast(("%s;%s"):format(K.MSG_RESYNC_REQ, gameID or ""))
    expectingResyncRes = true
    if resyncResExpiryTimer and resyncResExpiryTimer.Cancel then
        resyncResExpiryTimer:Cancel()
    end
    -- v0.11.0 C1#6 fix (audit_v0.10.7 A_Net_audit.md HIGH): pause-
    -- aware re-arm. Pre-v0.11.0 the 30-second window timer fired
    -- regardless of pause state; if the user paused for >30 seconds
    -- (or paused + /reload), the timer expired and a legitimate
    -- MSG_RESYNC_RES arriving after resume was rejected by the
    -- `if not expectingResyncRes` early-return at the receive site.
    -- Mirrors the SWA pause-aware re-arm pattern at LocalSWA / etc.
    -- Named function so it can recursively re-arm itself.
    local function expiryTick()
        if S.s.paused then
            -- Defer expiry until resume; re-arm a fresh 30s window
            -- so a long pause doesn't compound. The window is anchored
            -- to RESUME-TIME, not original-request-time.
            if C_Timer and C_Timer.NewTimer then
                resyncResExpiryTimer = C_Timer.NewTimer(30, expiryTick)
            end
            return
        end
        expectingResyncRes = false
        resyncResExpiryTimer = nil
    end
    if C_Timer and C_Timer.NewTimer then
        resyncResExpiryTimer = C_Timer.NewTimer(30, expiryTick)
    end
end

-- Pack a compact snapshot of the host's gameplay state and whisper it
-- back to the requester. ApplyResyncSnapshot on the receiver side
-- decodes the same wire format.
local function packSnapshot()
    local s = S.s
    local function nz(x) return x or "" end
    local c = s.contract or {}
    local seats = {}
    for i = 1, 4 do
        local info = s.seats[i]
        seats[i] = (info and info.name) or ""
    end
    local bids = {}
    for i = 1, 4 do bids[i] = nz(s.bids and s.bids[i]) end
    -- 7th-audit fix: pack a 4-bit isBot mask into a single field.
    -- Without it, ApplyResyncSnapshot rebuilds seats with isBot=nil,
    -- so subsequent host-signed bot broadcasts fail the rejoiner's
    -- authorizeSeat check (the rejoiner thinks the seat is human and
    -- expects the message to be signed by that name, not the host).
    local botMask = 0
    for i = 1, 4 do
        local info = s.seats[i]
        if info and info.isBot then botMask = botMask + (2 ^ (i - 1)) end
    end
    return table.concat({
        nz(s.gameID),
        nz(s.phase),
        tostring(s.dealer or 0),
        tostring(s.roundNumber or 0),
        tostring(s.turn or 0),
        nz(s.turnKind),
        nz(c.type),                              -- HOKM | SUN | ""
        nz(c.trump),
        tostring(c.bidder or 0),
        c.doubled and "1" or "0",                -- Bel (×2)
        c.tripled and "1" or "0",                -- Triple (×3)
        c.foured  and "1" or "0",                -- Four (×4)
        c.gahwa   and "1" or "0",                -- Gahwa (match-win)
        c.tripleOpen and "1" or "0",             -- bidder allowed Four counter?
        c.fourOpen   and "1" or "0",             -- defenders allowed Gahwa counter?
        tostring(s.cumulative and s.cumulative.A or 0),
        tostring(s.cumulative and s.cumulative.B or 0),
        s.paused and "1" or "0",
        tostring(s.bidRound or 1),               -- 1 / 2
        seats[1], seats[2], seats[3], seats[4],
        bids[1], bids[2], bids[3], bids[4],
        tostring(botMask),                       -- 4-bit isBot mask
        -- Audit Tier 4 (B-69): match target gp. Configured via /baloot
        -- target N on the host; previously absent from the snapshot, so
        -- late joiners and reloads defaulted to 152 even when the host
        -- ran a different target. Field 29 (1-indexed). Backwards-
        -- compatible: pre-v0.4.5 receivers stop reading at field 28.
        tostring(s.target or 152),
    }, "|")
end

function N.SendResyncRes(target, gameID)
    if not target then return end
    local payload = packSnapshot()
    whisper(target, ("%s;%s;%s"):format(K.MSG_RESYNC_RES, gameID or "", payload))
    -- Replay rebuild for fields not in the packed snapshot (tricks
    -- history, declared melds, bid card). Whispered to the target
    -- only — they reuse the same handlers (MSG_MELD / MSG_TRICK /
    -- MSG_BIDCARD), so no new wire format. This restores the meld
    -- strip / peek-last-trick / contract-banner state on a mid-hand
    -- /reload-rejoiner.
    if S.s.bidCard then
        whisper(target, ("%s;%s"):format(K.MSG_BIDCARD, S.s.bidCard))
    end
    -- Replay declared melds (winning team's strip + losing team's
    -- meld score eligibility both rely on s.meldsByTeam). Flag "1"
    -- in the trailing field tells the receiver to bypass authorizeSeat
    -- (sender is host, not the original declarer).
    for _, team in ipairs({ "A", "B" }) do
        for _, m in ipairs((S.s.meldsByTeam and S.s.meldsByTeam[team]) or {}) do
            local enc = (m.cards and C.EncodeHand(m.cards)) or ""
            whisper(target, ("%s;%d;%s;%s;%s;%s;1"):format(
                K.MSG_MELD, m.declaredBy or 0,
                m.kind or "", m.suit or "", m.top or "", enc))
        end
    end
    -- Replay pre-emption window state when a rejoiner lands during
    -- PHASE_PREEMPT. 7th-audit fix: include the LIVE eligible-seat
    -- CSV in the seat=0 frame so the rejoiner can fully rebuild
    -- preemptEligible (previously this was admitted-broken — the
    -- rejoiner was left with a nil list and the UI hid their button).
    if S.s.phase == K.PHASE_PREEMPT and S.s.preemptEligible
       and #S.s.preemptEligible > 0 then
        local eligCsv = table.concat(S.s.preemptEligible, ",")
        whisper(target, ("%s;0;%s"):format(K.MSG_PREEMPT_PASS, eligCsv))
    end
    -- v0.7 Sun-overcall: replay the open-window state. Without this,
    -- a rejoiner during the 5s overcall would see PHASE_OVERCALL
    -- (from the snapshot) but no s.overcall body, so their UI button
    -- and any local click would no-op silently. Also replay any
    -- already-recorded decisions so per-seat UI rendering matches.
    if S.s.phase == K.PHASE_OVERCALL and S.s.overcall then
        whisper(target, K.MSG_OVERCALL_OPEN)
        for seat = 1, 4 do
            local d = S.s.overcall.decisions and S.s.overcall.decisions[seat]
            if d then
                whisper(target, ("%s;%d;%s"):format(
                    K.MSG_OVERCALL_DECISION, seat, d))
            end
        end
    end
    -- Replay closed-trick history (fed via MSG_TRICK so the receiver
    -- runs the same ApplyTrickEnd path; we provide the fully-encoded
    -- plays so they don't depend on MSG_PLAY arrival order).
    --
    -- v0.11.0 RT07-03 fix (audit_v0.10.7 D_RedTeam_audit.md MED):
    -- trailing ";1" replay flag so the receiver's _OnTrick can
    -- propagate isReplay to ApplyTrickEnd, suppressing the v0.10.7
    -- SND_SWEEP_TRACK + SND_LAST_TRICK_WIN cues. Pre-v0.11.0 a
    -- rejoiner heard those cues for every past trick during the
    -- resync replay flood. The MSG_TRICK wire format is now 6
    -- fields including the trailing flag (was 5).
    for _, t in ipairs(S.s.tricks or {}) do
        local enc = ""
        for _, p in ipairs(t.plays or {}) do
            enc = enc .. (p.card or "??") .. tostring(p.seat or 0)
        end
        whisper(target, ("%s;%d;%d;%s;%s;1"):format(
            K.MSG_TRICK, t.winner or 0, t.points or 0,
            t.leadSuit or "", enc))
    end
    -- Replay in-flight trick plays (so the rejoiner sees the cards
    -- currently on the table). Trailing "1" flags the frame as a
    -- resync replay so _OnPlay bypasses turn + authority checks
    -- (the rejoiner's snapshot has s.turn pointing at the LAST seat,
    -- which would otherwise make every replay except the last drop).
    if S.s.trick and S.s.trick.plays then
        for _, p in ipairs(S.s.trick.plays) do
            whisper(target, ("%s;%d;%s;1"):format(
                K.MSG_PLAY, p.seat or 0, p.card or "??"))
        end
    end
    -- Replay AKA banner if active this trick. Trailing "1" tells
    -- _OnAKA to bypass authorizeSeat (sender is host, not seat owner).
    if S.s.akaCalled then
        whisper(target, ("%s;%d;%s;1"):format(
            K.MSG_AKA, S.s.akaCalled.seat or 0, S.s.akaCalled.suit or ""))
    end
end

-- -- Receive -----------------------------------------------------

-- Split helper: lua's gmatch is fine but empty-trailing fields lose.
-- Use a manual splitter so empty fields preserve.
local function split(s, sep)
    local out = {}
    if not s then return out end
    sep = sep or ";"
    local start = 1
    while true do
        local i = s:find(sep, start, true)
        if not i then out[#out + 1] = s:sub(start); break end
        out[#out + 1] = s:sub(start, i - 1)
        start = i + 1
    end
    return out
end

-- Public so UI can also fire actions when the user clicks.
function N.HandleMessage(prefix, message, channel, sender)
    if prefix ~= K.PREFIX then return end
    if not message or #message == 0 then return end
    local fields = split(message, ";")
    local tag = fields[1]
    log("Debug", "<- [%s] from %s: %s", channel, tostring(sender), message)

    if tag == K.MSG_HOST then
        N._OnHost(sender, fields[2], fields[3])
    elseif tag == K.MSG_JOIN then
        N._OnJoin(sender, fields[2], fields[3])
    elseif tag == K.MSG_LOBBY then
        N._OnLobby(sender, fields[2],
            { fields[3] or "", fields[4] or "", fields[5] or "", fields[6] or "" },
            fields[7], fields[8])
    elseif tag == K.MSG_START then
        N._OnStart(sender, tonumber(fields[2]), tonumber(fields[3]))
    elseif tag == K.MSG_DEAL then
        N._OnDealPhase(sender, fields[2], fields[3])
    elseif tag == K.MSG_HAND then
        -- Wire format: "h;<roundNum>;<encoded>".  Older single-field
        -- form ("h;<encoded>") is tolerated for back-compat.
        if fields[3] then
            N._OnHand(sender, fields[3], tonumber(fields[2]))
        else
            N._OnHand(sender, fields[2], nil)
        end
    elseif tag == K.MSG_BIDCARD then
        N._OnBidCard(sender, fields[2])
    elseif tag == K.MSG_TURN then
        N._OnTurn(sender, tonumber(fields[2]), fields[3])
    elseif tag == K.MSG_BID then
        N._OnBid(sender, tonumber(fields[2]), fields[3])
    elseif tag == K.MSG_CONTRACT then
        N._OnContract(sender, tonumber(fields[2]), fields[3], fields[4])
    elseif tag == K.MSG_DOUBLE then
        N._OnDouble(sender, tonumber(fields[2]), fields[3])
    elseif tag == K.MSG_TRIPLE then
        N._OnTriple(sender, tonumber(fields[2]), fields[3])
    elseif tag == K.MSG_FOUR then
        N._OnFour(sender, tonumber(fields[2]), fields[3])
    elseif tag == K.MSG_GAHWA then
        N._OnGahwa(sender, tonumber(fields[2]))
    elseif tag == K.MSG_BELOTE then
        -- v1.0.11 (D HIGH-2): Baloot/Belote announcement.
        N._OnBelote(sender, tonumber(fields[2]))
    elseif tag == K.MSG_PREEMPT then
        N._OnPreempt(sender, tonumber(fields[2]))
    elseif tag == K.MSG_PREEMPT_PASS then
        -- 7th-audit fix: forward the optional eligible CSV (fields[3])
        -- so the seat=0 "window open" frame can seed phase + eligible
        -- list on remote clients. Pre-7th senders won't include it;
        -- _OnPreemptPass treats nil as "no CSV provided".
        N._OnPreemptPass(sender, tonumber(fields[2]), fields[3])
    elseif tag == K.MSG_OVERCALL_OPEN then
        -- v0.7 Sun-overcall: host opens the 5s window. No payload.
        N._OnOvercallOpen(sender)
    elseif tag == K.MSG_OVERCALL_DECISION then
        -- v0.7 Sun-overcall: a seat decided. Payload: seat;decision.
        N._OnOvercallDecision(sender, tonumber(fields[2]), fields[3])
    elseif tag == K.MSG_OVERCALL_RESOLVE then
        -- v0.7 Sun-overcall: window closed; result follows.
        -- Payload: taken(0|1);by(seat or 0);type.
        N._OnOvercallResolve(sender, fields[2], tonumber(fields[3]),
                             fields[4])
    elseif tag == K.MSG_SKIP_DBL then
        N._OnSkipDouble(sender, tonumber(fields[2]))
    elseif tag == K.MSG_SKIP_TRP then
        N._OnSkipTriple(sender, tonumber(fields[2]))
    elseif tag == K.MSG_SKIP_FOR then
        N._OnSkipFour(sender, tonumber(fields[2]))
    elseif tag == K.MSG_SKIP_GHW then
        N._OnSkipGahwa(sender, tonumber(fields[2]))
    elseif tag == K.MSG_MELD then
        -- fields[7] is the optional replay flag ("1" iff this MSG_MELD
        -- was whispered as part of a resync replay; bypass authorizeSeat).
        N._OnMeld(sender, tonumber(fields[2]), fields[3], fields[4],
                  fields[5], fields[6], fields[7])
    elseif tag == K.MSG_PLAY then
        -- fields[4] is the optional replay flag (see _OnPlay).
        N._OnPlay(sender, tonumber(fields[2]), fields[3], fields[4])
    elseif tag == K.MSG_TRICK then
        -- v0.11.0 RT07-03: fields[6] is the optional replay flag
        -- ("1" iff this MSG_TRICK was whispered during a resync
        -- replay; tells _OnTrick to suppress v0.10.7 sound cues).
        N._OnTrick(sender, tonumber(fields[2]), tonumber(fields[3]),
                   fields[4], fields[5], fields[6])
    elseif tag == K.MSG_ROUND then
        local sweep = fields[6]
        if sweep == "" or sweep == nil then sweep = nil end
        -- Three-state decode for bidderMade (see N.SendRound). Empty
        -- or absent → nil (don't fire fanfare); "1" → true; "0" → false.
        local madeRaw = fields[7]
        local bidderMade
        if     madeRaw == "1" then bidderMade = true
        elseif madeRaw == "0" then bidderMade = false
        else                       bidderMade = nil end
        N._OnRound(sender, tonumber(fields[2]), tonumber(fields[3]),
                   tonumber(fields[4]), tonumber(fields[5]),
                   sweep, bidderMade)
    elseif tag == K.MSG_GAMEEND then
        N._OnGameEnd(sender, fields[2])
    elseif tag == K.MSG_TAKWEESH then
        N._OnTakweesh(sender, tonumber(fields[2]))
    elseif tag == K.MSG_TAKWEESH_OUT then
        N._OnTakweeshOut(sender, tonumber(fields[2]),
                         fields[3] == "1", tonumber(fields[4]),
                         fields[5], fields[6])
    elseif tag == K.MSG_KAWESH then
        N._OnKawesh(sender, tonumber(fields[2]))
    elseif tag == K.MSG_PAUSE then
        N._OnPause(sender, fields[2])
    elseif tag == K.MSG_TEAMS then
        N._OnTeams(sender, fields[2], fields[3])
    elseif tag == K.MSG_AKA then
        -- fields[4] is the optional replay flag (see _OnAKA).
        N._OnAKA(sender, tonumber(fields[2]), fields[3], fields[4])
    elseif tag == K.MSG_SWA then
        N._OnSWA(sender, tonumber(fields[2]), fields[3])
    elseif tag == K.MSG_SWA_OUT then
        -- fields[8] = sweep ("" | "A" | "B"); fields[9] = bidderMade
        -- ("" | "0" | "1"). Both optional / ignored on legacy (7-arg)
        -- senders; receivers fall through to nil and skip fanfare.
        local swSweep = fields[8]
        if swSweep == "" or swSweep == nil then swSweep = nil end
        local swMadeRaw = fields[9]
        local swMade
        if     swMadeRaw == "1" then swMade = true
        elseif swMadeRaw == "0" then swMade = false
        else                         swMade = nil end
        -- v0.11.7: fields[10] is the optional caller's encoded hand
        -- so the post-resolution banner can show the cards. Optional;
        -- pre-v0.11.7 senders omit it and receivers fall through to
        -- nil-encodedHand (banner shows no cards as before).
        N._OnSWAOut(sender, tonumber(fields[2]),
                    fields[3] == "1",
                    tonumber(fields[4]), tonumber(fields[5]),
                    tonumber(fields[6]), tonumber(fields[7]),
                    swSweep, swMade, fields[10])
    elseif tag == K.MSG_SWA_REQ then
        N._OnSWAReq(sender, tonumber(fields[2]), fields[3])
    elseif tag == K.MSG_SWA_RESP then
        N._OnSWAResp(sender, tonumber(fields[2]),
                     fields[3] == "1", tonumber(fields[4]))
    elseif tag == K.MSG_RESYNC_REQ then
        -- v0.10.3 cross-version compat (review_v0.10.2 §4.2 follow-up):
        -- v0.10.2 hosts emit OVERCALL_RESOLVE under the legacy "?"
        -- tag (which collided with RESYNC_REQ pre-v0.10.3). A v0.10.3
        -- client talking to a v0.10.2 host needs to disambiguate "?"
        -- by payload shape:
        --   • RESYNC_REQ payload  : "?;{gameID}"        → 2 fields
        --   • OVERCALL_RESOLVE    : "?;{taken};{by};{type}" → 4 fields
        -- Route 4-field "?" frames to _OnOvercallResolve so v0.10.2
        -- hosts can complete the overcall window with v0.10.3 clients.
        -- 2-field "?" frames are real resyncs (canonical post-v0.10.3).
        -- v0.10.3 hosts also dual-emit "?" alongside "!" (see
        -- N.SendOvercallResolve); the second hit is benign since
        -- _OnOvercallResolve is idempotent (clears state, exits phase).
        if #fields >= 4 then
            N._OnOvercallResolve(sender, fields[2], tonumber(fields[3]),
                                 fields[4])
        else
            N._OnResyncReq(sender, fields[2])
        end
    elseif tag == K.MSG_RESYNC_RES then
        -- The packed snapshot uses '|' for inner field separation so
        -- top-level ';' doesn't get chewed up. Reassemble fields[3..].
        local rest = {}
        for i = 3, #fields do rest[#rest + 1] = fields[i] end
        N._OnResyncRes(sender, fields[2], table.concat(rest, ";"))
    end

    if B.UI and B.UI.Refresh then B.UI.Refresh() end
end

-- -- Handlers ---------------------------------------------------

-- Gemini #5 audit catch: WoW's CHAT_MSG_ADDON sender format isn't
-- guaranteed to match the locally-stored "Name-Realm" form. Same-realm
-- senders may arrive as just "Name". Normalize the sender via
-- S.NormalizeName before any equality comparison so the host's own
-- self-loopbacks AND same-realm peer messages match the stored names.
local function normSender(sender)
    if not sender then return sender end
    return (S.NormalizeName and S.NormalizeName(sender)) or sender
end

local function fromHost(sender)
    if not S.s.hostName then return false end
    return normSender(sender) == S.s.hostName
end

local function fromSelf(sender)
    if not S.s.localName then return false end
    return normSender(sender) == S.s.localName
end

-- Authority helper: a per-seat action message is valid if
-- (a) the seat is a human and `sender` matches that seat's owner, OR
-- (b) the seat is a bot, in which case only the host signs on its behalf.
-- Used by every _On* handler that accepts a `seat` field — without it,
-- a malformed or replayed addon message could apply state for an
-- arbitrary seat as long as the phase/dispatch layer let it through.
local function authorizeSeat(seat, sender)
    local info = S.s.seats[seat]
    if not info then return false end
    local nsender = normSender(sender)
    if info.isBot then
        return S.s.hostName ~= nil and nsender == S.s.hostName
    end
    if info.name == nil then return false end
    -- 8th-audit fix: normalize info.name as well. Previous code
    -- normalized only `sender`; if the roster was populated from a
    -- restored saved-session or a non-suffixed source, raw equality
    -- against the suffixed live sender failed and the seat owner's
    -- own messages were rejected. Fast path first (avoid normalization
    -- on the common exact-match case).
    if info.name == nsender then return true end
    local nname = (S.NormalizeName and S.NormalizeName(info.name)) or info.name
    return nname == nsender
end

-- Loopback policy: SendAddonMessage delivers a copy back to the sender
-- via CHAT_MSG_ADDON. Local actions (Local* / Host*) already apply state
-- directly, so handlers SKIP self-loopbacks to avoid double-apply.

function N._OnHost(sender, gameID, version)
    if fromSelf(sender) then return end
    -- Track the host's addon version so the lobby can flag mismatches.
    -- 4th-audit X9-4 fix: normalize the key so same-realm senders merge
    -- into the same entry the UI looks up (see _OnLobby).
    if version and version ~= "" then
        local skey = (S.NormalizeName and S.NormalizeName(sender)) or sender
        S.s.peerVersions[skey] = version
    end
    if S.s.isHost then return end
    -- Accept host announcements during any "passive" phase: IDLE, LOBBY,
    -- SCORE (round-end banner) and GAME_END. Crucially this includes
    -- GAME_END so a peer who finished the previous game with us can
    -- pick up the next lobby instead of being stuck on the score
    -- screen with no Join button. Mid-active-play (DEAL/BID/PLAY/etc.)
    -- still ignores stranger announcements to avoid griefing.
    local p = S.s.phase
    if p ~= K.PHASE_IDLE and p ~= K.PHASE_LOBBY
       and p ~= K.PHASE_SCORE and p ~= K.PHASE_GAME_END then
        return
    end
    S.s.pendingHost = { name = sender, gameID = gameID }
    log("Info", "host announce from %s gameID=%s ver=%s",
        sender, tostring(gameID), tostring(version))
end

function N._OnJoin(sender, gameID, version)
    if fromSelf(sender) then return end
    if version and version ~= "" then
        local skey = (S.NormalizeName and S.NormalizeName(sender)) or sender
        S.s.peerVersions[skey] = version
    end
    if not S.s.isHost or S.s.phase ~= K.PHASE_LOBBY then return end
    if gameID ~= S.s.gameID then return end
    local seat = S.HostHandleJoin(sender)
    if seat then
        N.SendLobby(S.s.seats, S.s.gameID)
        -- Re-broadcast custom team labels so the late joiner doesn't
        -- see the default "Team A"/"Team B" — SendLobby's payload
        -- doesn't carry team names (kept compact), and the lobby
        -- ticker only re-broadcasts SendHostAnnounce.
        if S.s.teamNames and N.SendTeams then
            N.SendTeams(S.s.teamNames.A or "", S.s.teamNames.B or "")
        end
    end
end

function N._OnLobby(sender, gameID, names, botMask, hostVersion)
    if fromSelf(sender) then return end
    -- 12th-audit fix (Codex): active host must NEVER apply another
    -- peer's MSG_LOBBY — we ARE the host. Without this guard, a
    -- stale or forged MSG_LOBBY with a different gameID would route
    -- through S.ApplyLobby's "new game" branch, run S.Reset(), and
    -- demote the host into IDLE. Same defensive class as the
    -- _OnResyncRes guard added in 0aa496f.
    if S.s.isHost then return end
    -- 4th-audit X9-3 fix: tighten host adoption. Previously any peer
    -- who broadcast MSG_LOBBY first could claim hostName when our
    -- pendingHost was unset (e.g., post-/reload before we got a
    -- MSG_HOST). Now require either:
    --   (a) sender already known as host (idempotent re-bind), or
    --   (b) we have a pendingHost record matching this gameID, or
    --   (c) the gameID matches the one we previously joined
    --       (WHEREDNGNDB.lastGameID surviving /reload).
    -- Otherwise leave hostName alone — better to mis-render a lobby
    -- than to grant host authority to an arbitrary peer.
    if not fromHost(sender) and not S.s.pendingHost then
        local trustGameID = (WHEREDNGNDB and WHEREDNGNDB.lastGameID == gameID)
        if trustGameID then
            S.s.hostName = sender
        end
    elseif S.s.pendingHost and S.s.pendingHost.gameID == gameID then
        S.s.hostName = sender
    end
    -- 4th-audit X9-4 fix: peerVersions is keyed by raw sender on the
    -- write side but read by Name-Realm in UI. Normalize the key so
    -- same-realm senders (sometimes "Name", sometimes "Name-Realm"
    -- depending on WoW client) merge into one entry the UI can find.
    local skey = (S.NormalizeName and S.NormalizeName(sender)) or sender
    if hostVersion and hostVersion ~= "" then
        S.s.peerVersions[skey] = hostVersion
    end
    -- v0.11.11 NetU-06 fix: cap each name at 64 chars before persisting.
    -- Pre-v0.11.11 a buggy/forked host could send arbitrarily long
    -- names, persisted into s.seats[i].name and SaveSession-stored.
    -- WoW addon-channel max payload caps ~252 bytes per chunk so the
    -- exploit ceiling is small, but explicit cap closes the future-
    -- channel-format-change risk. Mirrors XR-06's encodedHand cap.
    if names then
        for i, n in ipairs(names) do
            if type(n) == "string" and #n > 64 then
                names[i] = n:sub(1, 64)
            end
        end
    end
    S.ApplyLobby(gameID, names, botMask)
end

function N._OnStart(sender, roundNumber, dealer)
    if fromSelf(sender) then return end
    if not fromHost(sender) then return end
    -- 13th-audit defense-in-depth: hosts are authoritative; never
    -- apply host-broadcast frames from other peers. Already gated by
    -- fromHost for an active host, but explicit isHost makes the
    -- invariant local. Same pattern applied to every host-broadcast
    -- handler in this wave (_OnDealPhase, _OnHand, _OnBidCard,
    -- _OnTurn, _OnContract, _OnTrick, _OnRound, _OnGameEnd, _OnPause,
    -- _OnTeams, _OnTakweeshOut, _OnSWAOut).
    if S.s.isHost then return end
    S.ApplyStart(roundNumber, dealer)
end

function N._OnDealPhase(sender, phase, extra)
    if fromSelf(sender) then return end
    if not fromHost(sender) then return end
    if S.s.isHost then return end
    if phase == "1" then S.s.phase = K.PHASE_DEAL1
    elseif phase == "2" then
        S.s.phase = K.PHASE_DEAL2BID
        S.s.bids = {}                -- clear round-1 bids on receivers too
        S.s.bidRound = 2
        -- Round-2 announcement. 0.5s delay so the round-2 bid panel
        -- has rendered before the voice plays. (Mirrors the same
        -- delay in S.HostBeginRound2 / S.ApplyStart.)
        if B.Sound and B.Sound.Cue then
            C_Timer.After(0.5, function()
                B.Sound.Cue(K.SND_VOICE_THANY)
            end)
        end
    elseif phase == "3" then S.s.phase = K.PHASE_DEAL3
    elseif phase == "play" then S.ApplyPlayPhase()
    elseif phase == "redeal" then
        -- Host broadcasts this when all four players passed both rounds
        -- and the deal is rotating. The trailing field is the next
        -- dealer's seat number; mirror it to a state flag the UI reads.
        local nextDealer = tonumber(extra)
        -- v0.11.5 NetA-06 fix: validate nextDealer ∈ [1,4]. Pre-v0.11.5
        -- a buggy/forked host emitting MSG_DEAL_PHASE;redeal;<garbage>
        -- passed nil or out-of-range into ApplyRedealAnnouncement; the
        -- redeal banner displayed wrong/no dealer name. Cosmetic but
        -- mirrors the broader wire-validation hardening.
        if not nextDealer or nextDealer < 1 or nextDealer > 4 then return end
        S.ApplyRedealAnnouncement(nextDealer)
    end
end

function N._OnHand(sender, encodedCards, forRound)
    -- Host whispers each player their hand. Whispers don't loopback to
    -- self in the same way; host applies its own hand directly in
    -- HostStartRound / HostFinishDeal. So we still skip-self defensively.
    if fromSelf(sender) then return end
    if not fromHost(sender) then return end
    if S.s.isHost then return end
    -- v0.11.11 NetU-09 fix: cap encodedCards to 16 chars (max 8 cards
    -- × 2 chars). Pre-v0.11.11 unbounded; a buggy host could send 1KB+
    -- encodedHand which persists in s.hand until next ApplyHand.
    -- Mirrors XR-06 SWA cap.
    if encodedCards and #encodedCards > 16 then return end
    S.ApplyHand(C.DecodeHand(encodedCards), forRound)
end

function N._OnBidCard(sender, card)
    if fromSelf(sender) then return end
    if not fromHost(sender) then return end
    if S.s.isHost then return end
    -- v0.11.11 NetU-05 fix: validate card format. Pre-v0.11.11 a
    -- malformed bid card was passed through to S.ApplyBidCard;
    -- downstream UI :sub(1,1)/:sub(2,2) produced bogus rank/suit.
    -- Allow empty string (no-bidcard sentinel from SendBidCard);
    -- otherwise must be 2 chars (rank+suit). Mirrors XR-11's _OnPlay.
    if card and card ~= "" and #card ~= 2 then return end
    S.ApplyBidCard(card)
end

function N._OnTurn(sender, seat, kind)
    if fromSelf(sender) then return end
    if not fromHost(sender) then return end
    if S.s.isHost then return end
    if not seat then return end
    -- v0.11.4 NetA-05 fix: validate seat ∈ [1,4]. Pre-v0.11.4 a
    -- buggy/forked host emitting MSG_TURN;99;play wrote s.turn=99,
    -- breaking turn-glow UI (S.s.seats[99] is nil) and AFK timer
    -- arming (isBotSeat returns nil → bot dispatch noops).
    if seat < 1 or seat > 4 then return end
    S.ApplyTurn(seat, kind)
end

function N._OnBid(sender, seat, bid)
    if fromSelf(sender) then return end
    if not seat or not bid then return end
    -- Phase: bidding only.
    if S.s.phase ~= K.PHASE_DEAL1 and S.s.phase ~= K.PHASE_DEAL2BID then return end
    -- Turn: only the seat whose turn it is may bid.
    if S.s.turn ~= seat or S.s.turnKind ~= "bid" then return end
    -- Idempotence: each seat bids at most once per round.
    if S.s.bids and S.s.bids[seat] ~= nil then return end
    -- Authority: sender must be the seat owner (or host for bots).
    if not authorizeSeat(seat, sender) then return end
    S.ApplyBid(seat, bid)
    N.CancelTurnTimer()
    if S.s.isHost then N._HostStepBid() end
end

function N._OnContract(sender, bidder, btype, trump)
    if fromSelf(sender) then return end
    if not fromHost(sender) then return end
    if S.s.isHost then return end
    if not bidder or not btype then return end
    -- v0.11.3 RT07-05 fix (defense-in-depth): bidder range check.
    -- The fromHost trust gate already prevents non-host peers from
    -- forging MSG_CONTRACT, but a host running a buggy/old fork could
    -- send MSG_CONTRACT;5;H;X. Pre-v0.11.3 this writes
    -- s.contract.bidder = 5; downstream R.TeamOf(5) defaults to "B"
    -- and (5 % 4) + 1 = 2 silently masks the error, leaving a
    -- corrupted contract that misbills team scores. Reject any
    -- bidder outside the 1-4 seat range. Same defensive shape as the
    -- existing nil-check above. Also validate btype against the two
    -- canonical contract types — the wire protocol only emits
    -- "HOKM" and "SUN", any other value is corruption (or a
    -- forward-compat hint we don't support yet — either way reject).
    if bidder < 1 or bidder > 4 then return end
    if btype ~= K.BID_HOKM and btype ~= K.BID_SUN then return end
    -- v0.11.13 XR2-05/06 fix: validate Hokm trump suit against the
    -- 4-suit enum. Pre-v0.11.13 a buggy/old host fork could broadcast
    -- MSG_CONTRACT;3;HOKM;X (non-suit trump). S.ApplyContract writes
    -- contract.trump = "X" verbatim, then R.IsLegalPlay's Hokm cases
    -- silently neuter — C.IsTrump("XS", contract) returns false for
    -- ALL cards, so trump-overcut logic disappears, Hokm degrades to
    -- pure suit-following, and the bidder's team is silently
    -- disadvantaged. Mirrors the NetU-03 _OnAKA suit-enum gate
    -- (v0.11.11). Sun contracts have empty trump; allow that case.
    if btype == K.BID_HOKM and trump ~= nil and trump ~= "" then
        if not (trump == "S" or trump == "H" or trump == "D" or trump == "C") then
            return
        end
    end
    S.ApplyContract(bidder, btype, trump)
end

function N._OnDouble(sender, seat, openField)
    if fromSelf(sender) then return end
    if not seat then return end
    -- v0.11.5 XR-08 fix: seat range check (defense-in-depth). The
    -- downstream eligibleSeat comparison would already reject out-of-
    -- range seats by mismatch, but explicit range gating mirrors the
    -- _OnContract / _OnTurn / _OnTrick pattern.
    if seat < 1 or seat > 4 then return end
    -- Idempotence: ignore if no contract or already doubled.
    if not S.s.contract or S.s.contract.doubled then return end
    if S.s.phase ~= K.PHASE_DOUBLE then return end
    -- v1.0.11 (D MED M1 either-defender Bel): accept Bel from EITHER
    -- defender on the bidder's opposite team. Pre-v1.0.11 the wire
    -- gate hardcoded `seat == NextSeat(bidder)`, blocking the partner-
    -- defender (PrevSeat(bidder)) from ever Bel'ing — stricter than
    -- Saudi convention. PDF text «المدبل» (the doubler) does not
    -- specify which defender; whoever calls Bel first becomes the
    -- doubler. `S.s.belPending` already lists both defenders (set in
    -- S.ApplyContract); we accept any seat in that list.
    local function pendingContains(t, s)
        if not t then return false end
        for _, v in ipairs(t) do if v == s then return true end end
        return false
    end
    if not pendingContains(S.s.belPending, seat) then return end
    if not authorizeSeat(seat, sender) then return end
    -- v0.5.9 Section 2 patch E-1: Sun Bel-100 legality gate.
    -- Reject illegal Bel attempts at the wire — a human player whose
    -- team is at >=100 in a Sun contract cannot Bel. Bot.PickDouble
    -- has the same gate; this is the wire-side enforcement so even
    -- a bypass-attempt or stale-state client gets stopped.
    -- Sources: decision-trees.md Section 2 (Definite, video 11).
    --
    -- v0.5.11 Race-A fix: a v0.5.8 client (no LocalDouble gate) calls
    -- S.ApplyDouble locally THEN sends the wire (Net.lua LocalDouble
    -- order). If the host rejects silently, the client's local state
    -- has doubled=true while host stays at doubled=nil — round-stuck
    -- desync until next deal. Recovery: when host rejects, broadcast
    -- MSG_SKIP_DBL + finish the deal at the un-doubled state. The
    -- offending client sees MSG_SKIP_DBL and HostFinishDeal's MSG_ROUND,
    -- snapping it back into lockstep. Same pattern as the AFK timeout
    -- recovery at _HostBelTimeout (Net.lua line ~3020).
    if R and R.CanBel
       and not R.CanBel(R.TeamOf(seat), S.s.contract, S.s.cumulative) then
        log("Warn", "rejected illegal Bel from seat %d (Sun >=100 gate)", seat)
        if S.s.isHost then
            broadcast(("%s;%d"):format(K.MSG_SKIP_DBL, seat))
            N.HostFinishDeal()
        end
        return
    end
    -- Open/Closed flag (v0.2.0+ wire). Pre-v0.2.0 senders won't include
    -- it; default to OPEN (current behavior).
    local open = (openField == nil) or (openField ~= "0")
    local wasSun = S.s.contract.type == K.BID_SUN
    S.ApplyDouble(seat, open)
    -- v0.11.17-hotfix F5: OnEscalation moved INTO S.ApplyDouble so all
    -- paths (wire-receive, host-direct, local-human) update the ledger
    -- uniformly. Pre-fix only fired here, missing host-direct and
    -- local paths. Inline call removed to avoid double-counting.
    -- Sun: ApplyDouble already set phase=PLAY (Sun has no Triple).
    -- Closed Bel: ApplyDouble set phase=PLAY too.
    -- Open Bel in Hokm: phase=TRIPLE, defer to bot dispatcher.
    if S.s.isHost then
        if wasSun or not open then
            N.HostFinishDeal()
        else
            N.MaybeRunBot()
        end
    end
end

function N._OnTriple(sender, seat, openField)
    if fromSelf(sender) then return end
    if not seat then return end
    if seat < 1 or seat > 4 then return end                  -- v0.11.5 XR-08
    if not S.s.contract or S.s.contract.tripled then return end
    if S.s.phase ~= K.PHASE_TRIPLE then return end
    -- Triple is the BIDDER's response to Bel.
    if seat ~= S.s.contract.bidder then return end
    if not authorizeSeat(seat, sender) then return end
    local open = (openField == nil) or (openField ~= "0")
    S.ApplyTriple(seat, open)
    -- v0.11.17-hotfix F5: OnEscalation moved into S.ApplyTriple.
    if S.s.isHost then
        if open then N.MaybeRunBot() else N.HostFinishDeal() end
    end
end

function N._OnFour(sender, seat, openField)
    if fromSelf(sender) then return end
    if not seat then return end
    if seat < 1 or seat > 4 then return end                  -- v0.11.5 XR-08
    if not S.s.contract or S.s.contract.foured then return end
    if S.s.phase ~= K.PHASE_FOUR then return end
    -- v1.0.11 (D MED M1): Four is the SPECIFIC defender who Bel'd
    -- (now tracked as contract.doublerSeat). PDF Rule 4: escalation
    -- chain is bidder ↔ doubler only. Pre-v1.0.11 hardcoded
    -- NextSeat(bidder); now uses the actual doubler seat (back-compat
    -- fallback to NextSeat(bidder) if doublerSeat missing on stale
    -- pre-v1.0.11 saved state).
    local eligibleSeat = S.s.contract.doublerSeat
                          or ((S.s.contract.bidder % 4) + 1)
    if seat ~= eligibleSeat then return end
    if not authorizeSeat(seat, sender) then return end
    local open = (openField == nil) or (openField ~= "0")
    S.ApplyFour(seat, open)
    -- v0.11.17-hotfix F5: OnEscalation moved into S.ApplyFour.
    if S.s.isHost then
        if open then N.MaybeRunBot() else N.HostFinishDeal() end
    end
end

function N._OnGahwa(sender, seat)
    if fromSelf(sender) then return end
    if not seat then return end
    if seat < 1 or seat > 4 then return end                  -- v0.11.5 XR-08
    if not S.s.contract or S.s.contract.gahwa then return end
    if S.s.phase ~= K.PHASE_GAHWA then return end
    -- Gahwa is the BIDDER's terminal (match-win) escalation.
    if seat ~= S.s.contract.bidder then return end
    if not authorizeSeat(seat, sender) then return end
    S.ApplyGahwa(seat)
    -- v0.11.17-hotfix F5: OnEscalation moved into S.ApplyGahwa.
    -- Terminal: no further window. Move into PLAY.
    if S.s.isHost then N.HostFinishDeal() end
end

-- v1.0.11 (D HIGH-2 Belote announcement): handler for incoming
-- MSG_BELOTE. Verifies the seat actually holds K+Q-of-trump (defensive
-- — prevents a hostile peer from claiming Belote without the cards),
-- gates on PHASE_PLAY (announcement window is during play, not bidding),
-- gates on contract.type == HOKM (Sun has no Belote), then mutates
-- S.s.beloteAnnounced via S.ApplyBeloteAnnounce on every client.
function N._OnBelote(sender, seat)
    if fromSelf(sender) then return end
    if not seat or seat < 1 or seat > 4 then return end
    if not S.s.contract or not S.s.contract.trump then return end
    if S.s.contract.type ~= K.BID_HOKM then return end   -- Sun has no Belote
    if S.s.phase ~= K.PHASE_PLAY then return end
    if not authorizeSeat(seat, sender) then return end
    S.ApplyBeloteAnnounce(seat)
    if B.UI and B.UI.Refresh then B.UI.Refresh() end
end

function N._OnPreempt(sender, seat)
    if fromSelf(sender) then return end
    if not seat then return end
    if seat < 1 or seat > 4 then return end          -- v0.11.11 NetU-07
    if S.s.phase ~= K.PHASE_PREEMPT then return end
    if not S.s.preemptEligible then return end
    local eligible = false
    for _, s2 in ipairs(S.s.preemptEligible) do
        if s2 == seat then eligible = true; break end
    end
    if not eligible then return end
    if not authorizeSeat(seat, sender) then return end
    S.ApplyPreempt(seat)
    -- Pre-emption claim: the seat takes the contract as their own SUN.
    if S.s.isHost then
        S.s.pendingPreemptContract = nil
        S.ApplyContract(seat, K.BID_SUN, nil)
        N.SendContract(seat, K.BID_SUN, "")
        -- 14th-audit fix (scoring vs rules): Sun Bel is restricted to
        -- the BEHIND team (defender side still < 101) AND requires the
        -- bidder team to have crossed 100. Was previously enabled if
        -- EITHER team was past 100, which let a leading defender (who
        -- shouldn't be doubling) call Bel.
        if not N._SunBelAllowed(seat) then
            S.s.belPending = nil
            N.HostFinishDeal()
            return
        end
        N.MaybeRunBot()
    end
end

function N._OnPreemptPass(sender, seat, eligCsv)
    if fromSelf(sender) then return end
    if not seat then return end
    -- 7th-audit fix: seat=0 is the host's "preempt window open" frame.
    -- The host serializes the eligible-seat list as a CSV in eligCsv;
    -- receivers seed phase + preemptEligible so the local UI can
    -- render the claim button. Without this, remote human clients
    -- never saw their own preempt window — the host's local state
    -- changed but only the seat=0 ping went over the wire, which
    -- earlier code dropped as "not in PHASE_PREEMPT yet".
    if seat == 0 then
        if not fromHost(sender) then return end
        if S.s.isHost then return end  -- defense in depth
        if not eligCsv or eligCsv == "" then return end
        local elig = {}
        for n in eligCsv:gmatch("(%d+)") do
            local v = tonumber(n)
            if v and v >= 1 and v <= 4 then elig[#elig + 1] = v end
        end
        if #elig == 0 then return end
        S.s.phase = K.PHASE_PREEMPT
        S.s.preemptEligible = elig
        if N.StartLocalWarn then N.StartLocalWarn("preempt") end
        if B.UI and B.UI.Refresh then B.UI.Refresh() end
        return
    end
    if S.s.phase ~= K.PHASE_PREEMPT then return end
    if not S.s.preemptEligible then return end
    if not authorizeSeat(seat, sender) then return end
    S.ApplyPreemptPass(seat)
    if S.s.isHost then
        if not S.s.preemptEligible then
            -- All eligible seats waived → finalize original buyer.
            N._FinalizePreempt()
        else
            -- Non-final pass: dispatch the next eligible seat. Without
            -- this, the chain stalls until 60s AFK fires (Codex #2).
            N.MaybeRunBot()
        end
    end
end

-- Finalize the original buyer's contract once all eligible pre-empters
-- waived. The host queued the contract struct as s.pendingPreemptContract
-- when PHASE_PREEMPT opened.
function N._FinalizePreempt()
    if not S.s.isHost then return end
    if not S.s.pendingPreemptContract then return end
    local pc = S.s.pendingPreemptContract
    S.s.pendingPreemptContract = nil
    S.s.preemptEligible = nil
    S.ApplyContract(pc.bidder, pc.type, pc.trump)
    N.SendContract(pc.bidder, pc.type, pc.trump or "")
    -- 14th-audit fix: Sun Bel only enabled for the behind defender.
    if pc.type == K.BID_SUN and not N._SunBelAllowed(pc.bidder) then
        S.s.belPending = nil
        N.HostFinishDeal()
        return
    end
    N.MaybeRunBot()
end

-- v0.7 Sun-overcall (post-Hokm 5s upgrade-or-take window).
-- See Constants.lua K.MSG_OVERCALL_* for wire-format docs and
-- Rules.lua / State.lua for the underlying state primitives.

function N.SendOvercallOpen()
    broadcast(K.MSG_OVERCALL_OPEN)
end

function N.SendOvercallDecision(seat, decision)
    broadcast(("%s;%d;%s"):format(K.MSG_OVERCALL_DECISION, seat, decision))
end

function N.SendOvercallResolve(taken, by, otype)
    -- v0.10.3 cross-version dual-emit (review_v0.10.2 §4.2 follow-up):
    -- v0.10.3 reassigned K.MSG_OVERCALL_RESOLVE to "!" to free "?"
    -- for its rightful owner K.MSG_RESYNC_REQ (CRIT-1 fix). v0.10.2
    -- clients only know "?" for OVERCALL_RESOLVE, so a v0.10.3 host
    -- talking to v0.10.2 clients would see them ignore "!" and
    -- soft-lock at PHASE_OVERCALL on `taken=false`. Mitigation: emit
    -- BOTH the canonical new tag AND a legacy "?"-shaped frame so
    -- v0.10.2 clients receive the resolve. v0.10.3 clients see both;
    -- the second arrival hits the idempotent _OnOvercallResolve
    -- (state already cleared) so it's a benign no-op. The
    -- payload-shape disambiguator at the dispatcher's "?" branch
    -- (Net.lua ~line 620) routes 4-field "?" payloads to
    -- _OnOvercallResolve and 2-field "?" payloads to _OnResyncReq.
    --
    -- Eligible to be dropped in v0.11.0 once v0.10.2 clients have
    -- aged out of the install base (CurseForge auto-updates most
    -- users within 1-2 weeks of release).
    local takenStr = taken and "1" or "0"
    local byNum    = by or 0
    local typeStr  = otype or ""
    broadcast(("%s;%s;%d;%s"):format(
        K.MSG_OVERCALL_RESOLVE, takenStr, byNum, typeStr))
    -- Legacy "?" emit for v0.10.2 clients. Payload shape matches
    -- v0.10.2's _OnOvercallResolve expectations (taken;by;type).
    broadcast(("?;%s;%d;%s"):format(takenStr, byNum, typeStr))
end

function N._OnOvercallOpen(sender)
    if fromSelf(sender) then return end
    if not fromHost(sender) then return end
    if S.s.isHost then return end                  -- defense in depth
    if not S.s.contract then return end
    -- Trust the host: open the local overcall window via the state
    -- primitive. The bidCard / dealer are already in s from the prior
    -- bid-card and lobby messages.
    if S.BeginOvercall then
        S.BeginOvercall(S.s.bidCard, S.s.dealer)
    end
    if N.StartLocalWarn then N.StartLocalWarn("overcall") end
    if B.UI and B.UI.Refresh then B.UI.Refresh() end
end

function N._OnOvercallDecision(sender, seat, decision)
    if not seat or not decision then return end
    if S.s.phase ~= K.PHASE_OVERCALL then return end
    if S.s.isHost then
        -- Host validates and re-broadcasts. Self-loopback ignored
        -- because the host writes the decision via N.LocalOvercall
        -- before broadcasting, and the loopback hits this handler
        -- with the host's own sender.
        if fromSelf(sender) then return end
        if not authorizeSeat(seat, sender) then return end
        if S.RecordOvercallDecision and S.RecordOvercallDecision(seat, decision) then
            N.SendOvercallDecision(seat, decision)
            -- Early-resolve check: if every eligible seat has decided,
            -- we don't need to wait the full 5s. Eligibility is per
            -- R.CanOvercall (forced/Sun contracts already returned
            -- false in _HostBeginOvercallWindow, so all 4 seats are
            -- eligible — except in the Ace-bid case where the bidder
            -- is blocked from UPGRADE but can still WAIVE, so even
            -- there all 4 seats are decision-capable).
            if N._OvercallAllDecided() then
                N._HostResolveOvercall()
            end
        end
    else
        if not fromHost(sender) then return end
        -- Echo: update local UI state.
        if S.RecordOvercallDecision then
            S.RecordOvercallDecision(seat, decision)
        end
        if B.UI and B.UI.Refresh then B.UI.Refresh() end
    end
end

function N._OnOvercallResolve(sender, takenStr, by, otype)
    if fromSelf(sender) then return end
    if not fromHost(sender) then return end
    if S.s.isHost then return end
    -- v0.8.6 H1 fix (audit AUDIT_REPORT_v0.7.1.md): pre-v0.8.6 this
    -- handler called S.FinalizeOvercall() which RE-DERIVED the contract
    -- mutation from the remote's LOCAL `s.overcall.decisions` table.
    -- If MSG_OVERCALL_DECISION frames were dropped or reordered on a
    -- slow client, the remote's decisions disagreed with the host's
    -- → different contract type/bidder/trump than the host. The
    -- `taken=true` branch was masked by the host's follow-up
    -- MSG_CONTRACT broadcast, but the `taken=false` branch had no
    -- self-correction → desync persisted into trick play.
    --
    -- Now: trust the wire. Just clear local overcall state and exit
    -- PHASE_OVERCALL. If the contract changed (taken=true), the host's
    -- follow-up MSG_CONTRACT (sent immediately after MSG_OVERCALL_RESOLVE)
    -- canonically sets the new contract via _OnContract / S.ApplyContract.
    -- If not changed (taken=false), the contract stays Hokm and the
    -- remote shouldn't mutate based on its (possibly wrong) decisions.
    --
    -- The wire payload (takenStr/by/otype) is informational — kept in
    -- the function signature for forward-compat / debug logging — but
    -- not consulted for state mutation. The host is server-of-truth
    -- via MSG_CONTRACT.
    --
    -- v0.11.0 A5 fix (audit_v0.10.7 A_Net_audit.md HIGH): phase-
    -- idempotency guard. The v0.10.3 dual-emit (`"!"` + `"?"`) for
    -- cross-version compat means this handler can fire TWICE per
    -- resolve event: once for each tag. The second hit was assumed
    -- benign (same state mutation), but under wire reorder the
    -- second hit can arrive AFTER subsequent MSG_CONTRACT +
    -- MSG_DEAL "play" → reverting a remote client from PHASE_PLAY
    -- back to PHASE_DOUBLE. Bail if we're not currently in
    -- PHASE_OVERCALL — phase has already advanced past the
    -- overcall window, the resolve is stale and would corrupt
    -- state. The first-arrival path still works correctly because
    -- it fires WITHIN PHASE_OVERCALL.
    if S.s.phase ~= K.PHASE_OVERCALL then return end
    S.s.overcall = nil
    S.s.phase = K.PHASE_DOUBLE
    if B.UI and B.UI.Refresh then B.UI.Refresh() end
end

-- v0.7 Sun-overcall: open the 5s window. Called from _HostStepBid
-- after MSG_CONTRACT broadcasts but before PHASE_DOUBLE flow.
-- Returns true if the window opened (caller defers further flow);
-- false if not eligible (caller continues normally to PHASE_DOUBLE).
function N._HostBeginOvercallWindow()
    if not S.s.isHost then return false end
    if not S.s.contract then return false end
    if S.s.contract.type ~= K.BID_HOKM then return false end
    if S.s.contract.forced then return false end
    -- Honour a per-install opt-out so non-Saudi-rule installations can
    -- disable the window via /baloot config. Default: enabled.
    if WHEREDNGNDB ~= nil and WHEREDNGNDB.allowSunOvercall == false then
        return false
    end
    if not S.BeginOvercall then return false end
    if not S.BeginOvercall(S.s.bidCard, S.s.dealer) then return false end
    N.SendOvercallOpen()
    -- Bots act immediately (their Bot.PickOvercall is deterministic
    -- given hand + thresholds; no need to wait 5s for them). Humans
    -- get the full 5s.
    for seat = 1, 4 do
        if S.IsSeatBot and S.IsSeatBot(seat)
           and B.Bot and B.Bot.PickOvercall then
            local d = B.Bot.PickOvercall(seat)
            if d and S.RecordOvercallDecision
               and S.RecordOvercallDecision(seat, d) then
                N.SendOvercallDecision(seat, d)
            end
        end
    end
    -- Did all 4 already decide? (All-bots table.)
    if N._OvercallAllDecided() then
        N._HostResolveOvercall()
        return true
    end
    -- Otherwise schedule the 5s timeout.
    -- v0.9.0 M1 fix (audit AUDIT_REPORT_v0.7.1.md): pause-aware timer.
    -- If the host pauses mid-window, the original C_Timer.After kept
    -- counting and force-resolved the contract on resume — possibly
    -- before a human had a chance to click. Now: on timer fire, if
    -- paused, re-arm a fresh timer and skip resolve. Mirrors the
    -- existing SWA timer pattern at Net.lua ~2627.
    local function overcallTimerFn()
        if not S.s.isHost then return end
        if S.s.phase ~= K.PHASE_OVERCALL then return end
        if S.s.paused then
            -- Re-arm a fresh window when the host pauses through a
            -- timeout fire. The 5s resets — humans get a fresh shot
            -- after resume rather than auto-WLA on the resume tick.
            if S.s.overcall then
                S.s.overcall.startedAt = (GetTime and GetTime()) or 0
            end
            if C_Timer and C_Timer.After then
                C_Timer.After(K.OVERCALL_TIMEOUT_SEC, overcallTimerFn)
            end
            return
        end
        N._HostResolveOvercall()
    end
    C_Timer.After(K.OVERCALL_TIMEOUT_SEC, overcallTimerFn)
    -- Host UI: kick the local refresh since the receiver _OnOvercallOpen
    -- skips host-loopback. Without this the host doesn't render the
    -- countdown banner / their own overcall buttons.
    if N.StartLocalWarn then N.StartLocalWarn("overcall") end
    if B.UI and B.UI.Refresh then B.UI.Refresh() end
    return true
end

-- Returns true iff every seat has recorded a decision OR is structurally
-- ineligible (e.g., bidder under Ace-special would normally be blocked
-- from UPGRADE — but they can still WAIVE, so they ARE eligible to
-- decide; this is a future hook if we ever introduce a fully-blocked
-- seat).
function N._OvercallAllDecided()
    if not S.s.overcall or not S.s.overcall.decisions then return false end
    for seat = 1, 4 do
        if not S.s.overcall.decisions[seat] then return false end
    end
    return true
end

function N._HostResolveOvercall()
    if not S.s.isHost then return end
    if not S.s.overcall then return end
    if not S.FinalizeOvercall then return end
    -- Snapshot the contract values BEFORE FinalizeOvercall so we can
    -- detect whether the contract changed (and broadcast a new
    -- MSG_CONTRACT if so).
    local prevType   = S.s.contract.type
    local prevTrump  = S.s.contract.trump
    local prevBidder = S.s.contract.bidder
    local result = S.FinalizeOvercall()
    if not result then return end
    N.SendOvercallResolve(result.taken, result.by, result.type)
    if result.taken then
        -- Contract was mutated. Re-broadcast so all clients see the new
        -- bidder/type/trump combination canonically (overcall RESOLVE
        -- is the human-readable announcement; CONTRACT is the
        -- authoritative state.)
        N.SendContract(S.s.contract.bidder, S.s.contract.type,
                       S.s.contract.trump or "")
        -- v0.11.11 NetU-01 (OPEN-1 mitigation): defensive 250ms re-broadcast
        -- of MSG_CONTRACT to recover from WoW chat-throttle drops. The
        -- overcall sequence is dense (open + 4×decision + resolve dual-
        -- emit + contract + dealphase + turn + whispers) and can flirt
        -- with the ~4-6 msg/sec/sender CHAT_MSG_ADDON throttle. If the
        -- single MSG_CONTRACT broadcast is dropped, clients keep
        -- s.contract.type == HOKM while host advances to SUN — this is
        -- the leading remaining hypothesis for the user-reported
        -- "Sun overcall bottom contract banner not updating" bug
        -- (OPEN-1 since v0.11.2). The retry costs nothing in the happy
        -- path (idempotent on the receiver via S.ApplyContract's match
        -- check at line 1059) and recovers from a single throttle drop.
        if C_Timer and C_Timer.After then
            C_Timer.After(0.25, function()
                if S.s.contract then
                    N.SendContract(S.s.contract.bidder, S.s.contract.type,
                                   S.s.contract.trump or "")
                end
            end)
        end
    end
    -- Continue post-bid flow (mirrors the post-MSG_CONTRACT logic in
    -- _HostStepBid). If the contract is now Sun, re-check Sun-Bel-skip.
    if S.s.contract.type == K.BID_SUN
       and N._SunBelAllowed and not N._SunBelAllowed(S.s.contract.bidder) then
        S.s.belPending = nil
        N.HostFinishDeal()
        return
    end
    N.MaybeRunBot()
    if B.UI and B.UI.Refresh then B.UI.Refresh() end
end

-- Local action (player clicks Take/Upgrade/Waive on their UI).
function N.LocalOvercall(decision)
    if not S.s.overcall then return false end
    if not S.s.localSeat then return false end
    if S.s.phase ~= K.PHASE_OVERCALL then return false end
    if not R.CanOvercall(S.s.localSeat, S.s.contract,
                         S.s.overcall.bidCard) then
        return false
    end
    -- Validate decision string (mirrors S.RecordOvercallDecision).
    -- v1.5.3: TAKE_HOKM_<suit> removed (non-canonical Saudi rule —
    -- saudi-rules.md:26-28). Stale clients may still emit it; we
    -- silently reject at the wire so the host never accepts it either.
    local validDec = decision == "UPGRADE"
                     or decision == "TAKE"
                     or decision == "WAIVE"
    if not validDec then return false end
    -- Bidder + Ace-bid forces UPGRADE → WAIVE silently (R.CanOvercall
    -- returns false for that combo, so we already returned above).
    if S.s.localSeat == S.s.contract.bidder and decision == "TAKE" then
        return false                                 -- bidder can't TAKE own bid
    end
    if S.s.localSeat ~= S.s.contract.bidder and decision == "UPGRADE" then
        return false                                 -- non-bidder can't UPGRADE
    end
    -- Send to host. On host, dispatch directly; on remote, broadcast
    -- the MSG_OVERCALL_DECISION and let _OnOvercallDecision route it.
    if S.s.isHost then
        if S.RecordOvercallDecision(S.s.localSeat, decision) then
            N.SendOvercallDecision(S.s.localSeat, decision)
            if N._OvercallAllDecided() then N._HostResolveOvercall() end
        end
    else
        broadcast(("%s;%d;%s"):format(K.MSG_OVERCALL_DECISION,
                                       S.s.localSeat, decision))
    end
    return true
end

function N._OnSkipDouble(sender, seat)
    if fromSelf(sender) then return end
    if S.s.phase ~= K.PHASE_DOUBLE then return end
    if not seat or not S.s.contract then return end
    -- v1.0.11 (D MED M1): either-defender Bel — skip removes ONE
    -- defender from belPending. Window stays open until ALL defenders
    -- have decided. State mutation runs on every client (not just
    -- host) so non-host UIs reflect the partial-skip immediately.
    local function pendingContains(t, sa)
        if not t then return false end
        for _, v in ipairs(t) do if v == sa then return true end end
        return false
    end
    if not pendingContains(S.s.belPending, seat) then return end
    if not authorizeSeat(seat, sender) then return end
    -- Remove seat from belPending on all clients.
    local newPending = {}
    for _, v in ipairs(S.s.belPending) do
        if v ~= seat then newPending[#newPending + 1] = v end
    end
    S.s.belPending = newPending
    if S.s.isHost then
        if #newPending == 0 then
            N.HostFinishDeal()
        else
            -- Other defender(s) still have a window — re-dispatch.
            N.MaybeRunBot()
        end
    end
    if B.UI and B.UI.Refresh then B.UI.Refresh() end
end

function N._OnSkipTriple(sender, seat)
    if fromSelf(sender) then return end
    if S.s.phase ~= K.PHASE_TRIPLE then return end
    if not seat or not S.s.contract then return end
    -- Bidder skips their Triple window.
    if seat ~= S.s.contract.bidder then return end
    if not authorizeSeat(seat, sender) then return end
    if S.s.isHost then N.HostFinishDeal() end
end

function N._OnSkipFour(sender, seat)
    if fromSelf(sender) then return end
    if S.s.phase ~= K.PHASE_FOUR then return end
    if not seat or not S.s.contract then return end
    -- v1.0.11 (D MED M1): Four-skip from the SPECIFIC doubler.
    local eligibleSeat = S.s.contract.doublerSeat
                          or ((S.s.contract.bidder % 4) + 1)
    if seat ~= eligibleSeat then return end
    if not authorizeSeat(seat, sender) then return end
    if S.s.isHost then N.HostFinishDeal() end
end

function N._OnSkipGahwa(sender, seat)
    if fromSelf(sender) then return end
    if S.s.phase ~= K.PHASE_GAHWA then return end
    if not seat or not S.s.contract then return end
    -- Bidder skips their Gahwa window.
    if seat ~= S.s.contract.bidder then return end
    if not authorizeSeat(seat, sender) then return end
    if S.s.isHost then N.HostFinishDeal() end
end

function N._OnMeld(sender, seat, kind, suit, top, encodedCards, replayFlag)
    if fromSelf(sender) then return end
    if not seat or not kind then return end
    -- v0.11.11 NetU-02 fix: enum-validate kind. Pre-v0.11.11 a buggy/
    -- forked host emitting MSG_MELD;<seat>;garbageKind;... reached
    -- S.ApplyMeld which only handles seq3/seq4/seq5/carre — unknown
    -- kinds yielded value=nil written into s.meldsByTeam, leading to
    -- nil-arithmetic risk in score sum and garbage in meld-strip UI.
    -- Same defense-in-depth shape as v0.11.3 RT07-05 / v0.11.5 cluster.
    if kind ~= "seq3" and kind ~= "seq4" and kind ~= "seq5" and kind ~= "carre" then
        return
    end
    if seat < 1 or seat > 4 then return end
    -- Audit fix: replay-frame bypass. Resync whispers a marker "1" in
    -- the trailing field; with fromHost(sender) verified we trust the
    -- frame and skip the per-seat authorizeSeat (which would reject
    -- because sender is the HOST, not the seat owner).
    local isReplay = (replayFlag == "1") and fromHost(sender)
    -- 13th-audit defense: hosts must never be the target of a replay
    -- frame (resync replay only goes to rejoiners). Skip the host's
    -- replay-branch path entirely.
    if isReplay and S.s.isHost then return end
    -- Phase: melds are declarable in DEAL3 / PLAY only. ApplyMeld already
    -- dedupes by (seat, kind, top, suit), but we still gate phase + author
    -- here so a stale message from a previous round can't poison the
    -- meldsByTeam table.
    if S.s.phase ~= K.PHASE_PLAY and S.s.phase ~= K.PHASE_DEAL3 then return end
    if not isReplay and not authorizeSeat(seat, sender) then return end
    S.ApplyMeld(seat, kind, suit, top, encodedCards)
end

function N._OnPlay(sender, seat, card, replayFlag)
    if fromSelf(sender) then return end
    if not seat or not card then return end
    -- v0.11.4 XR-11 fix: validate seat ∈ [1,4] and card format
    -- (2-char rank+suit). Pre-v0.11.4 a malformed card (1-char,
    -- 5-char, garbage) was passed to S.ApplyPlay → R.IsLegalPlay →
    -- card:sub(1,1)/sub(2,2) producing bogus rank/suit silently.
    -- Mirrors the inline check already in _OnTrick's encPlays loop
    -- (Net.lua:1592).
    if seat < 1 or seat > 4 then return end
    if #card ~= 2 then return end
    -- Phase: plays only land during PLAY.
    if S.s.phase ~= K.PHASE_PLAY then return end
    -- Audit fix: replay-frame bypass. During a resync replay the host
    -- whispers each in-flight play in turn-order; the rejoiner's
    -- snapshot has s.turn set to the seat about to act NEXT (the last
    -- in the trick), so the standard turn-check rejects every replay
    -- except the very last one. With fromHost(sender) verified, we
    -- trust the frame and skip turn + authority checks. Idempotence
    -- still applies — never double-add a seat to the same trick.
    local isReplay = (replayFlag == "1") and fromHost(sender)
    -- 13th-audit defense: hosts are never the target of a replay
    -- frame; resync replay only goes to rejoiners.
    if isReplay and S.s.isHost then return end
    if not isReplay then
        -- Turn: only the seat whose turn it is may play.
        --
        -- Audit fix (turn-desync RCA): the strict turn-equality gate
        -- below silently dropped any MSG_PLAY whose seat didn't match
        -- our local turn pointer. Combined with the absence of any
        -- per-message sequence number AND the fact that S.ApplyPlay
        -- does NOT advance s.turn, a single dropped MSG_TURN frame
        -- (CHAT_MSG_ADDON party-channel is at-most-once under server
        -- contention) made the receiver permanently miss every
        -- subsequent play in the trick — including the host's AFK
        -- auto-play that should have recovered the stuck seat.
        --
        -- Reported user symptom: "game stuck — player sees previous
        -- seat highlighted, host shows it's their turn, AFK fires,
        -- when player finally plays they get illegal-card because
        -- the auto-played card is no longer in their authoritative
        -- hand on the host."
        --
        -- Self-healing fix: when the seat doesn't match local turn
        -- BUT the sender is the host AND the seat is properly
        -- authorized for that sender, trust the host's authority
        -- and patch our local turn pointer before applying. The
        -- existing idempotence guard below still prevents double-
        -- apply if the matching MSG_TURN arrives later.
        if S.s.turnKind ~= "play" then
            -- Outside the play turn-kind window, drop as before
            -- (covers stale frames between phases).
            return
        end
        if S.s.turn ~= seat then
            -- Self-heal: only accept when the host vouches for the
            -- seat. authorizeSeat already accepts (sender == host)
            -- for any seat as long as that seat is human and host-
            -- delegated, OR the seat is a bot. Same gate as below.
            if not fromHost(sender) and not authorizeSeat(seat, sender) then
                return
            end
            S.s.turn     = seat
            S.s.turnKind = "play"
        end
    end
    -- Idempotence: that seat must not have already played this trick.
    if S.s.trick and S.s.trick.plays then
        for _, p in ipairs(S.s.trick.plays) do
            if p.seat == seat then return end
        end
    end
    -- Authority: sender must own the seat (or host if it's a bot,
    -- OR if the host is auto-acting on behalf of a human via AFK
    -- timeout / error-recovery — host-signed plays for human seats
    -- are legitimate authoritative actions). 50-agent playtest
    -- audit caught this as the missing half of the v0.4.6 turn-
    -- desync fix: the self-heal block above (line 1090) correctly
    -- accepts host-signed plays for any seat, but this gate
    -- previously rejected them for human seats — silently dropping
    -- the very AFK auto-play that the self-heal was designed to
    -- accept. Mirroring the fromHost escape closes the loop.
    if not isReplay and not fromHost(sender)
       and not authorizeSeat(seat, sender) then return end
    -- Capture lead suit BEFORE ApplyPlay so the bot memory observer
    -- knows whether `card` followed suit or was off-suit (a void tell).
    local leadBefore = S.s.trick and S.s.trick.leadSuit or nil
    -- v0.11.0 RT07-03 fix (audit_v0.10.7 D_RedTeam_audit.md MED): pass
    -- isReplay through to ApplyPlay so the v0.10.7 SND_TRUMP_CUT cue
    -- doesn't fire on resync-replay frames (those are reconstructive,
    -- not new — the cue would announce a long-past trump-cut event).
    S.ApplyPlay(seat, card, isReplay)
    -- 50-agent playtest audit fix: do not feed Bot.OnPlayObserved on
    -- replay frames during a resync. The plays are reconstructive,
    -- not new — observing them would corrupt void / firstDiscard /
    -- aceLate / leadCount counters with phantom data on any client
    -- that has Bot loaded. Currently safe because rejoiners are
    -- always human (B.Bot is nil-or-unused there), but the guard
    -- closes the latent risk if bot seats ever exist on non-host.
    if not isReplay and B.Bot and B.Bot.OnPlayObserved then
        B.Bot.OnPlayObserved(seat, card, leadBefore)
    end
    -- Don't advance host's turn machinery on a replay frame — those
    -- are reconstructive, not new plays. (Host shouldn't be the
    -- replay TARGET anyway; this is belt-and-braces.)
    if not isReplay then
        N.CancelTurnTimer()
        if S.s.isHost then N._HostStepPlay() end
    end
end

function N._OnTrick(sender, winner, points, leadSuit, encPlays, replayFlag)
    if fromSelf(sender) then return end
    if not fromHost(sender) then return end
    if S.s.isHost then return end
    -- v0.11.4 NetA-04 fix (audit_v0.11.3 cross-cutting MED): validate
    -- winner ∈ [1,4] and points non-nil before passing to ApplyTrickEnd.
    -- Pre-v0.11.4 a buggy/forked host sending MSG_TRICK with garbage
    -- numerics (tonumber returning nil, or seat=99) silently corrupted
    -- s.tricks[i].winner = nil and downstream R.TeamOf(nil) defaulted
    -- to "B", miscounting team trick totals. Mirrors RT07-05 wire
    -- validation shape.
    if not winner or winner < 1 or winner > 4 then return end
    if not points then return end
    -- Authoritative trick snapshot from host. We rebuild s.trick from
    -- the encoded plays so ApplyTrickEnd's lastTrick stash is complete
    -- regardless of MSG_PLAY arrival order. Older hosts (pre-v0.1.25)
    -- send empty leadSuit/encPlays — fall back to the local view.
    --
    -- v0.11.0 RT07-03 fix (audit_v0.10.7 D_RedTeam_audit.md MED):
    -- accept and propagate isReplay so ApplyTrickEnd suppresses
    -- v0.10.7 cues (SND_SWEEP_TRACK + SND_LAST_TRICK_WIN) on
    -- replayed past tricks during a resync flood.
    local isReplay = (replayFlag == "1") and fromHost(sender)
    if encPlays and #encPlays >= 3 then
        local plays = {}
        for i = 1, #encPlays, 3 do
            local card = encPlays:sub(i, i + 1)
            local seat = tonumber(encPlays:sub(i + 2, i + 2))
            if card and #card == 2 and seat and seat >= 1 and seat <= 4 then
                plays[#plays + 1] = { seat = seat, card = card }
            end
        end
        if #plays > 0 then
            S.s.trick = S.s.trick or { plays = {} }
            S.s.trick.plays = plays
            if leadSuit and leadSuit ~= "" then
                S.s.trick.leadSuit = leadSuit
            end
        end
    end
    S.ApplyTrickEnd(winner, points, isReplay)
    if S.s.isHost then N._HostStepAfterTrick() end
end

function N._OnRound(sender, addA, addB, totA, totB, sweep, bidderMade)
    if fromSelf(sender) then return end
    if not fromHost(sender) then return end
    if S.s.isHost then return end
    -- v0.11.4 NetA-03 / RT07-06 fix: nil-numeric guard on the four
    -- score fields. Pre-v0.11.4 a buggy/forked host emitting
    -- MSG_ROUND;<garbage>;... with non-numeric fields → tonumber()
    -- returns nil → S.ApplyRoundEnd writes s.cumulative.A/B = nil,
    -- corrupting the score panel until the next valid MSG_ROUND.
    -- Mirrors RT07-05 wire-validation shape.
    if not addA or not addB or not totA or not totB then return end
    -- v0.11.11 NetU-04 fix: bound-check on score fields. Pre-v0.11.11
    -- a buggy host emitting MSG_ROUND with garbage numerics
    -- (negative, or 9999999) passed the nil-check but corrupted
    -- s.cumulative downstream — could falsely trigger game-end via
    -- R.GameEndWinner(totA, totB, target) where target=152. Reasonable
    -- bound: 0 <= addX <= 200 (per-round delta), 0 <= totX <= 1000
    -- (cumulative; max realistic = ~3 game targets).
    if addA < 0 or addB < 0 or addA > 200 or addB > 200 then return end
    if totA < 0 or totB < 0 or totA > 1000 or totB > 1000 then return end
    S.ApplyRoundEnd(addA, addB, totA, totB, sweep, bidderMade)
end

function N._OnGameEnd(sender, winner)
    if fromSelf(sender) then return end
    if not fromHost(sender) then return end
    if S.s.isHost then return end
    -- v0.11.4 XR-09 fix: validate winner ∈ {"A","B"}. Pre-v0.11.4
    -- accepted any string and wrote it into s.winner; downstream
    -- R.TeamOf comparisons silently fall through to default branches.
    if winner ~= "A" and winner ~= "B" then return end
    S.ApplyGameEnd(winner)
end

-- -- Host stepping ----------------------------------------------
-- All Host* functions apply state locally first, then broadcast.
-- Loopback handlers skip self, so this is the canonical path on host.

function N._HostStepBid()
    local action, payload = S.HostAdvanceBidding()
    if action == "next" then
        S.ApplyTurn(payload.seat, "bid")
        N.SendTurn(payload.seat, "bid")
        N.MaybeRunBot()
    elseif action == "contract" then
        -- Triple-on-Ace pre-emption (الثالث): a round-2 SUN bid where
        -- the bid card is an Ace AND there are eligible earlier seats
        -- triggers a pre-emption window. Toggleable via
        -- WHEREDNGNDB.preemptOnAce (default ON in v0.2.0+).
        local enablePreempt = (WHEREDNGNDB == nil)
                           or (WHEREDNGNDB.preemptOnAce ~= false)
        local bidRank = S.s.bidCard and C.Rank(S.s.bidCard) or nil
        if enablePreempt
           and S.s.bidRound == 2
           and payload.type == K.BID_SUN
           and bidRank == "A" then
            local elig = S.PreemptEligibleSeats(payload.bidder, payload.bidder)
            if elig and #elig > 0 then
                -- Open a pre-emption window. Stash the original buyer's
                -- contract; finalize either when a seat claims (claimer
                -- becomes declarer) or when all eligible seats waive.
                S.s.preemptEligible = elig
                S.s.pendingPreemptContract = {
                    bidder = payload.bidder,
                    type   = payload.type,
                    trump  = payload.trump,
                }
                S.s.phase = K.PHASE_PREEMPT
                -- Broadcast: re-use MSG_PREEMPT_PASS as a "window open"
                -- ping with seat=0; clients render UI based on
                -- s.preemptEligible. 7th-audit fix: include the
                -- eligible-seat CSV. Without it, remote clients only
                -- received the "0" seat (which their _OnPreemptPass
                -- dropped — phase was still DEAL2BID), so their phase
                -- never advanced and their UI never showed the claim
                -- button. The receiver special-cases seat=0 to bring
                -- itself into PHASE_PREEMPT and seed preemptEligible.
                local eligCsv = table.concat(elig, ",")
                broadcast(("%s;0;%s"):format(K.MSG_PREEMPT_PASS, eligCsv))
                -- 4th-audit X7 fix: arm the local T-10s pre-warn for
                -- any human eligible seat. The other escalation
                -- windows (Bel/Triple/Four/Gahwa) arm their pre-warn
                -- on phase entry from State.lua; PHASE_PREEMPT is
                -- the lone outlier because the eligibility list is
                -- host-side. StartLocalWarn self-gates on whether
                -- localSeat is in S.s.preemptEligible.
                if N.StartLocalWarn then N.StartLocalWarn("preempt") end
                -- Bots dispatch via MaybeRunBot's preempt branch.
                N.MaybeRunBot()
                if B.UI and B.UI.Refresh then B.UI.Refresh() end
                return
            end
        end
        S.ApplyContract(payload.bidder, payload.type, payload.trump)
        N.SendContract(payload.bidder, payload.type, payload.trump or "")
        -- v0.7 Sun-overcall: post-Hokm 5-second window where the
        -- bidder may upgrade Hokm→Sun (non-Ace bid card only) and
        -- non-bidder seats may take the contract as their Sun.
        -- Returns true if a window opened (deferring the rest of the
        -- post-bid flow until N._HostResolveOvercall fires); false if
        -- the contract isn't Hokm or is forced/Takweesh, in which case
        -- we continue straight to PHASE_DOUBLE below.
        if N._HostBeginOvercallWindow and N._HostBeginOvercallWindow() then
            return
        end
        -- Saudi Sun rule: contract Sun can be Beled only after one
        -- team's cumulative game score has exceeded 100 (i.e. ≥101).
        -- If Sun and neither team is past 100, skip the DOUBLE phase
        -- entirely and go straight to play. Triple/Four/Gahwa never
        -- exist for Sun.
        if payload.type == K.BID_SUN then
            -- 14th-audit fix: Sun Bel restricted to behind defender.
            if not N._SunBelAllowed(payload.bidder) then
                S.s.belPending = nil
                N.HostFinishDeal()
                return
            end
        end
        N.MaybeRunBot()
    elseif action == "round2" then
        S.HostBeginRound2()
        N.SendDealPhase("2")
        local first = (S.s.dealer % 4) + 1
        S.ApplyTurn(first, "bid")
        N.SendTurn(first, "bid")
        N.MaybeRunBot()
    elseif action == "redeal" then
        N._HostRedeal("allpass")
    end
end

function N._HostStepPlay()
    if not S.s.trick then return end
    if #S.s.trick.plays < 4 then
        local last = S.s.trick.plays[#S.s.trick.plays].seat
        local nxt = (last % 4) + 1
        S.ApplyTurn(nxt, "play")
        N.SendTurn(nxt, "play")
        N.MaybeRunBot()
        return
    end
    -- Hold the full 4-card view long enough for the player to read it,
    -- including the case where THEY were the 4th to play (in which case
    -- the trick resolves on the same turn they clicked and 1.5s felt
    -- abrupt). 2.2s gives the slide-in animation (~0.22s) + plenty of
    -- "see the trick" time + the winner-glow read.
    C_Timer.After(2.2, function()
        if not S.s.isHost then return end
        -- Pause-state guard: if the host paused during the 2.2s
        -- window, don't resolve the trick into a paused state — wait
        -- for resume to fire the next StepPlay.
        if S.s.paused then return end
        -- A Takweesh during the wait window can move phase to SCORE.
        -- Don't resolve the trick if we're no longer in PLAY.
        if S.s.phase ~= K.PHASE_PLAY then return end
        if not S.s.contract then return end
        if not S.s.trick or #S.s.trick.plays < 4 then return end
        local winner = R.TrickWinner(S.s.trick, S.s.contract)
        local points = R.TrickPoints(S.s.trick, S.s.contract)
        N.SendTrick(winner, points)
        S.ApplyTrickEnd(winner, points)
        N._HostStepAfterTrick()
        if B.UI then B.UI.Refresh() end
    end)
end

function N._HostStepAfterTrick()
    if #S.s.tricks >= 8 then
        local res = S.HostScoreRoundResult()
        if not res then return end
        S.ApplyRoundResult(res)               -- host-only stash for summary panel
        local addA, addB = res.final.A, res.final.B
        -- Gahwa match-win override: a successful (or failed) Gahwa
        -- hands the entire match to a single team. Force their
        -- cumulative to the target so the game-end branch fires.
        --
        -- v0.8.6 H2 fix (audit AUDIT_REPORT_v0.7.1.md): also zero the
        -- LOSER's delta. Pre-v0.8.6, the loser's add could include
        -- their own meld points (per the "each team keeps own melds"
        -- branch in R.ScoreRound:fail). With Gahwa overriding the
        -- match outcome, leaving the loser's add non-zero inflated
        -- their cumulative for cosmetic display AND — more critically
        -- — could trigger a tiebreaker false-fire when both teams
        -- happened to land at exactly target. Zeroing the loser's
        -- delta makes the cumulative state cleanly reflect "match
        -- decided by Gahwa override" and removes the tiebreaker race.
        if res.gahwaWonGame and res.gahwaWinner then
            local target = S.s.target or 152
            if res.gahwaWinner == "A" then
                addA = math.max(addA, target - (S.s.cumulative.A or 0))
                addB = 0  -- v0.8.6 H2: zero loser's delta
            else
                addB = math.max(addB, target - (S.s.cumulative.B or 0))
                addA = 0  -- v0.8.6 H2: zero loser's delta
            end
        end
        local totA = S.s.cumulative.A + addA
        local totB = S.s.cumulative.B + addB
        S.ApplyRoundEnd(addA, addB, totA, totB, res.sweep, res.bidderMade)
        N.SendRound(addA, addB, totA, totB, res.sweep, res.bidderMade)
        -- v0.10.5 MED-2: game-end + H3 tiebreak via shared
        -- R.GameEndWinner helper. Same canonical post-v0.8.6 logic
        -- (Gahwa winner > bidderMade-side > defensive "A"); now also
        -- used by Takweesh + SWA-invalid Qaid paths.
        local winner = R.GameEndWinner(totA, totB, S.s.target, {
            gahwaWinner = res.gahwaWonGame and res.gahwaWinner or nil,
            bidderTeam  = S.s.contract and S.s.contract.bidder
                            and R.TeamOf(S.s.contract.bidder) or nil,
            bidderMade  = res.bidderMade,
        })
        if winner then
            S.ApplyGameEnd(winner)
            N.SendGameEnd(winner)
        end
        return
    end
    local lastWinner = S.s.tricks[#S.s.tricks].winner
    S.ApplyTurn(lastWinner, "play")
    N.SendTurn(lastWinner, "play")
    N.MaybeRunBot()
end

-- v0.10.6 user-reported bug fix: extracted from the inline 3s
-- C_Timer body in N._HostRedeal so it can be re-invoked from
-- recovery paths (LocalPause resume, PLAYER_LOGIN session restore)
-- when the original timer was lost to a pause+/reload sequence.
-- Idempotent — bails on missing s.redealing, wrong phase, or
-- paused state. Uses `nextDealer` from arg (3s-timer caller) or
-- fallback to s.redealing.nextDealer (recovery callers).
function N._HostExecuteRedeal(nextDealer)
    if not S.s.isHost then return end
    if S.s.paused then return end
    -- Reset / pause guards: if the user reset or paused during
    -- the 3s redeal banner, abort the deal — otherwise we'd
    -- write fresh round state into a wiped or paused game.
    if S.s.phase ~= K.PHASE_DEAL2BID and S.s.phase ~= K.PHASE_DEAL1
       and not S.s.redealing then
        return
    end
    -- Recover nextDealer from state if caller didn't pass it
    -- (recovery paths from session restore).
    nextDealer = nextDealer or (S.s.redealing and S.s.redealing.nextDealer)
    if not nextDealer then return end
    -- v0.11.5 NetA-09 fix: range check nextDealer. Pre-v0.11.5 a
    -- corrupted SavedVariables with s.redealing.nextDealer = 99 passed
    -- the nil-check and corrupted s.dealer + downstream rotation math.
    -- (99 % 4) + 1 = 4, so first-bidder math limps along but the
    -- dealer-rotation invariant is broken from this round forward.
    if nextDealer < 1 or nextDealer > 4 then return end

    S.s.dealer = nextDealer
    if B.Bot and B.Bot.ResetMemory then B.Bot.ResetMemory() end
    S.ApplyStart(S.s.roundNumber, nextDealer)
    N.SendStart(S.s.roundNumber, nextDealer)

    local hands, bidCard = S.HostDealInitial()
    dealHandsToHumans(hands)
    S.ApplyHand(hands[S.s.localSeat])
    S.ApplyBidCard(bidCard)
    N.SendBidCard(bidCard)
    S.s.phase = K.PHASE_DEAL1
    N.SendDealPhase("1")
    local first = (nextDealer % 4) + 1
    S.ApplyTurn(first, "bid")
    N.SendTurn(first, "bid")
    N.MaybeRunBot()
    if B.UI and B.UI.Refresh then B.UI.Refresh() end
end

function N._HostRedeal(reason)
    -- All-pass / Kawesh redeal: per Saudi rule, the deal moves to the
    -- next dealer (no team scored, but the seat rotates). Round number
    -- stays the same since no real round was played.
    --
    -- Audit fix: caller passes a reason ("allpass" | "kawesh") so the
    -- print accurately reflects which path triggered the redeal.
    -- Previously always printed "all passed", contradicting the
    -- already-printed "X called Kawesh" line on the host's chat.
    local nextDealer = (S.s.dealer % 4) + 1
    -- Surface a "redeal" banner with the next-dealer name on every
    -- client for 3 seconds before the actual deal lands. The host
    -- broadcasts a synthetic MSG_DEAL phase "redeal" so non-hosts can
    -- show the same banner; everyone counts down off their own clock.
    S.ApplyRedealAnnouncement(nextDealer)
    broadcast(("%s;redeal;%d"):format(K.MSG_DEAL, nextDealer))
    if reason == "kawesh" then
        -- Caller (LocalKawesh / _OnKawesh / HostHandleKawesh) already
        -- printed the seat-attributed announcement; stay silent here.
    else
        print("|cffaaaaaaWHEREDNGN|r all passed — redealing with next dealer.")
    end
    if B.UI and B.UI.Refresh then B.UI.Refresh() end

    -- v0.10.6 user-reported bug fix: the redeal-deal-step body is
    -- now extracted into N._HostExecuteRedeal so it can be re-invoked
    -- from LocalPause resume and PLAYER_LOGIN restore when the
    -- in-flight 3s C_Timer is gone. Pre-v0.10.6 the timer body bare-
    -- exited on `S.s.paused` (and the timer itself died on /reload),
    -- so a pause-during-redeal-banner soft-locked the round: state
    -- restored with s.redealing set but no recovery path → user
    -- comes back to a bidding-phase view with no buttons and turn
    -- pinned to a non-acting bot.
    --
    -- 9th-audit fix: capture a generation token so /baloot reset can
    -- invalidate this in-flight 3s callback. Without this, a reset
    -- during the redeal countdown would let the timer fire afterward
    -- and spawn a ghost round into the IDLE state. State.Reset bumps
    -- _redealGen to invalidate any pending callbacks.
    B._redealGen = (B._redealGen or 0) + 1
    local thisGen = B._redealGen
    C_Timer.After(3.0, function()
        if thisGen ~= B._redealGen then return end
        N._HostExecuteRedeal(nextDealer)
    end)
end

-- -- Driving host actions from UI ----------------------------------

function N.HostStartRound()
    if not S.s.isHost then return end
    -- Rotate dealer from the CURRENT s.dealer (not from roundNumber).
    -- This correctly handles redeals which may have advanced s.dealer
    -- mid-round without bumping roundNumber. At game start, roundNumber
    -- is 0 and we anchor dealer at the host (seat 1).
    local dealer
    if S.s.roundNumber == 0 then
        -- v1.3.5 (random first dealer): pre-fix dealer was hardcoded
        -- to seat 1 at game start. This created persistent "team A
        -- starts" bias — seat 1 led the round-1 trick (since bidder-
        -- after-dealer is seat 2 only when dealer is 1, and bidder
        -- usually leads round 1 in this code path), which cascades
        -- into trick-winner-leads tempo control. Random first dealer
        -- (1-4 uniform) eliminates the structural bias and matches
        -- Saudi-table convention where the first dealer is decided
        -- by card-cut, dice roll, or verbal agreement. UI fires a
        -- ~3.5s "DICE ROLL" banner via S.ApplyStart's transition
        -- detection (s.dealerRollAt) so all seats see the random
        -- pick before deal phase visuals kick in.
        dealer = math.random(1, 4)
    else
        dealer = (S.s.dealer % 4) + 1
    end
    local roundNum = S.s.roundNumber + 1

    -- Fresh bot card memory each round.
    if B.Bot and B.Bot.ResetMemory then B.Bot.ResetMemory() end
    -- Partner-style stats reset only at NEW GAME (round 1). Across
    -- rounds within a game we keep accumulating so the M3lm tier has
    -- stable patterns to read.
    if roundNum == 1 and B.Bot and B.Bot.ResetStyle then
        B.Bot.ResetStyle()
    end

    S.ApplyStart(roundNum, dealer)
    N.SendStart(roundNum, dealer)

    local hands, bidCard = S.HostDealInitial()
    dealHandsToHumans(hands)
    S.ApplyHand(hands[S.s.localSeat])
    S.ApplyBidCard(bidCard)
    N.SendBidCard(bidCard)

    S.s.phase = K.PHASE_DEAL1
    N.SendDealPhase("1")

    local first = (dealer % 4) + 1
    S.ApplyTurn(first, "bid")
    N.SendTurn(first, "bid")
    N.MaybeRunBot()
    -- v0.10.5 user-reported bug fix: round-end screen sticks on
    -- "Next Round" when the new round's first bidder is the human
    -- host (no bot fires → no loopback Refresh → UI stays on prior
    -- PHASE_SCORE view). The Awal sound still plays because it's
    -- queued from S.ApplyStart, but the bid panel doesn't render.
    -- Force a Refresh after host-side state advance; harmless when
    -- a bot DID fire (Refresh runs again on the bot's loopback).
    if B.UI and B.UI.Refresh then B.UI.Refresh() end
end

function N.LocalBid(bid)
    if S.s.paused then return end
    if not S.IsMyTurn() then return end
    if S.s.turnKind ~= "bid" then return end
    -- Dedupe: if we've already bid this round, ignore (e.g. double-click).
    if S.s.bids[S.s.localSeat] ~= nil then return end
    N.CancelTurnTimer()
    cancelLocalWarn()
    S.ApplyBid(S.s.localSeat, bid)
    N.SendBid(S.s.localSeat, bid)
    if S.s.isHost then N._HostStepBid() end
end

-- Each Local* escalation action takes an `open` flag (default true)
-- — controls whether the chain may continue with the opposing team's
-- next-rung counter. UI surfaces this as paired buttons (e.g., "Bel
-- (open)" vs "Bel (closed)"). Gahwa is terminal so no flag needed.
function N.LocalDouble(open)
    if S.s.paused then return end
    if not S.s.contract or S.s.contract.doubled then return end
    if S.s.phase ~= K.PHASE_DOUBLE then return end
    -- v1.0.11 (D MED M1 either-defender Bel): accept either defender.
    -- Localseat must be in S.s.belPending (set by S.ApplyContract to
    -- include both defenders).
    local function pendingContains(t, s)
        if not t then return false end
        for _, v in ipairs(t) do if v == s then return true end end
        return false
    end
    if not pendingContains(S.s.belPending, S.s.localSeat) then return end
    -- v0.5.9 Section 2 patch E-1: Sun Bel-100 legality gate.
    -- Local gate (UI surface). The Bel button should already be
    -- hidden by the UI when CanBel is false, but defend in depth.
    -- Sources: decision-trees.md Section 2 (Definite, video 11).
    if R and R.CanBel
       and not R.CanBel(R.TeamOf(S.s.localSeat), S.s.contract, S.s.cumulative) then
        return
    end
    cancelLocalWarn()
    if open == nil then open = true end
    -- In Sun, open/closed is moot — there's no Triple rung. Force
    -- closed so the chain doesn't pretend to advance.
    if S.s.contract.type == K.BID_SUN then open = false end
    S.ApplyDouble(S.s.localSeat, open)
    N.SendDouble(S.s.localSeat, open)
    if S.s.isHost then
        if S.s.contract.type == K.BID_SUN or not open then
            N.HostFinishDeal()
        else
            N.MaybeRunBot()
        end
    end
end

function N.LocalTriple(open)
    if S.s.paused then return end
    if not S.s.contract or S.s.contract.tripled then return end
    if S.s.phase ~= K.PHASE_TRIPLE then return end
    if S.s.localSeat ~= S.s.contract.bidder then return end
    cancelLocalWarn()
    if open == nil then open = true end
    S.ApplyTriple(S.s.localSeat, open)
    N.SendTriple(S.s.localSeat, open)
    if S.s.isHost then
        if open then N.MaybeRunBot() else N.HostFinishDeal() end
    end
end

function N.LocalFour(open)
    if S.s.paused then return end
    if not S.s.contract or S.s.contract.foured then return end
    if S.s.phase ~= K.PHASE_FOUR then return end
    -- v1.0.11 (D MED M1): Four eligibility = the SPECIFIC doubler seat
    -- (whoever Bel'd), with back-compat fallback to NextSeat(bidder)
    -- for stale pre-v1.0.11 saved state without contract.doublerSeat.
    local eligibleSeat = S.s.contract.doublerSeat
                          or ((S.s.contract.bidder % 4) + 1)
    if S.s.localSeat ~= eligibleSeat then return end
    cancelLocalWarn()
    if open == nil then open = true end
    S.ApplyFour(S.s.localSeat, open)
    N.SendFour(S.s.localSeat, open)
    if S.s.isHost then
        if open then N.MaybeRunBot() else N.HostFinishDeal() end
    end
end

function N.LocalGahwa()
    if S.s.paused then return end
    if not S.s.contract or S.s.contract.gahwa then return end
    if S.s.phase ~= K.PHASE_GAHWA then return end
    if S.s.localSeat ~= S.s.contract.bidder then return end
    cancelLocalWarn()
    S.ApplyGahwa(S.s.localSeat)
    N.SendGahwa(S.s.localSeat)
    -- Terminal: no further window.
    if S.s.isHost then N.HostFinishDeal() end
end

-- v1.0.11 (D HIGH-2): local Baloot/Belote announce. Called from the
-- BALOOT! UI button. Verifies the local seat actually holds K+Q-of-
-- trump in their hand (defensive UI gate), then broadcasts MSG_BELOTE
-- and applies state locally (the wire-back skips fromSelf).
function N.LocalBelote()
    if S.s.paused then return end
    if not S.s.contract or not S.s.contract.trump then return end
    if S.s.contract.type ~= K.BID_HOKM then return end
    if S.s.phase ~= K.PHASE_PLAY then return end
    if not S.s.localSeat then return end
    if S.s.beloteAnnounced and S.s.beloteAnnounced[S.s.localSeat] then
        return -- already announced, idempotent
    end
    -- Hand check: must hold both K and Q of trump.
    local hand = S.s.hostHands and S.s.hostHands[S.s.localSeat]
    if hand then
        local hasK, hasQ = false, false
        for _, c in ipairs(hand) do
            if C.Suit(c) == S.s.contract.trump then
                if C.Rank(c) == "K" then hasK = true
                elseif C.Rank(c) == "Q" then hasQ = true end
            end
        end
        -- Saudi rule: Baloot is announceable only if BOTH K+Q still
        -- in hand OR you've just played the second of the pair. Since
        -- the play-and-announce moment is just after playing the
        -- second card, allow if either both still present (just before
        -- play) or one present (just after first-of-pair played).
        if not (hasK or hasQ) then return end
    end
    S.ApplyBeloteAnnounce(S.s.localSeat)
    N.SendBelote(S.s.localSeat)
end

-- Local pre-emption (الثالث, "Triple-on-Ace") action.
--
-- 6th-audit fix: when the LOCAL player IS the host, we cannot route
-- through `_OnPreempt(localName, ...)` because that handler starts
-- with `if fromSelf(sender) then return end` and silently drops the
-- claim — the host's own preempt was being swallowed, leaving the
-- table soft-locked until 60s AFK fired. Instead, mirror the cleaner
-- `LocalGahwa` pattern: apply state locally, broadcast, then run the
-- host post-apply logic inline.
function N.LocalPreempt()
    if S.s.paused then return end
    if S.s.phase ~= K.PHASE_PREEMPT then return end
    if not S.s.localSeat or not S.s.preemptEligible then return end
    local eligible = false
    for _, s2 in ipairs(S.s.preemptEligible) do
        if s2 == S.s.localSeat then eligible = true; break end
    end
    if not eligible then return end
    cancelLocalWarn()
    -- Apply locally first (state mutation), then broadcast so peers
    -- can mirror. Order matches LocalGahwa for consistency.
    S.ApplyPreempt(S.s.localSeat)
    N.SendPreempt(S.s.localSeat)
    if S.s.isHost then
        -- Replicate _OnPreempt's host post-apply branch directly.
        S.s.pendingPreemptContract = nil
        S.ApplyContract(S.s.localSeat, K.BID_SUN, nil)
        N.SendContract(S.s.localSeat, K.BID_SUN, "")
        -- 14th-audit fix: Sun Bel only enabled for behind defender.
        if not N._SunBelAllowed(S.s.localSeat) then
            S.s.belPending = nil
            N.HostFinishDeal()
            return
        end
        N.MaybeRunBot()
    end
end

function N.LocalPreemptPass()
    if S.s.paused then return end
    if S.s.phase ~= K.PHASE_PREEMPT then return end
    if not S.s.localSeat or not S.s.preemptEligible then return end
    cancelLocalWarn()
    -- Apply locally first, then broadcast (mirrors LocalGahwa).
    S.ApplyPreemptPass(S.s.localSeat)
    N.SendPreemptPass(S.s.localSeat)
    if S.s.isHost then
        if not S.s.preemptEligible then
            -- All eligible seats waived → finalize original buyer.
            N._FinalizePreempt()
        else
            -- Non-final pass: dispatch the next eligible seat.
            N.MaybeRunBot()
        end
    end
end

-- Skip vote. Anyone with the eligible seat can broadcast; the host
-- (or anyone receiving) acts on it via _OnSkip*.
function N.LocalSkipDouble()
    if S.s.paused then return end
    if not S.s.contract or not S.s.localSeat then return end
    cancelLocalWarn()
    -- v1.0.11 (D MED M1): either-defender Bel — local skip eligible
    -- to either defender during PHASE_DOUBLE; the SPECIFIC doubler
    -- during PHASE_FOUR (set by S.ApplyDouble).
    local function pendingContains(t, sa)
        if not t then return false end
        for _, v in ipairs(t) do if v == sa then return true end end
        return false
    end
    local fourSeat = S.s.contract.doublerSeat
                      or ((S.s.contract.bidder % 4) + 1)
    if S.s.phase == K.PHASE_DOUBLE then
        if not pendingContains(S.s.belPending, S.s.localSeat) then return end
        broadcast(("%s;%d"):format(K.MSG_SKIP_DBL, S.s.localSeat))
        -- v1.0.11: mutate belPending locally (the wire echo skips
        -- via fromSelf, so this side has to update its own state).
        local newPending = {}
        for _, v in ipairs(S.s.belPending) do
            if v ~= S.s.localSeat then newPending[#newPending + 1] = v end
        end
        S.s.belPending = newPending
        if S.s.isHost then
            if #newPending == 0 then
                N.HostFinishDeal()
            else
                N.MaybeRunBot()
            end
        end
        if B.UI and B.UI.Refresh then B.UI.Refresh() end
    elseif S.s.phase == K.PHASE_TRIPLE then
        -- Bidder skips Triple.
        if S.s.localSeat ~= S.s.contract.bidder then return end
        broadcast(("%s;%d"):format(K.MSG_SKIP_TRP, S.s.localSeat))
        if S.s.isHost then N.HostFinishDeal() end
    elseif S.s.phase == K.PHASE_FOUR then
        -- Specific doubler skips Four.
        if S.s.localSeat ~= fourSeat then return end
        broadcast(("%s;%d"):format(K.MSG_SKIP_FOR, S.s.localSeat))
        if S.s.isHost then N.HostFinishDeal() end
    elseif S.s.phase == K.PHASE_GAHWA then
        -- Bidder skips Gahwa.
        if S.s.localSeat ~= S.s.contract.bidder then return end
        broadcast(("%s;%d"):format(K.MSG_SKIP_GHW, S.s.localSeat))
        if S.s.isHost then N.HostFinishDeal() end
    end
end

-- Host finishes the deal: send remaining 3 cards, transition to play.
function N.HostFinishDeal()
    if not S.s.isHost then return end
    local hands = S.HostDealRest()
    if not hands then
        -- v0.11.0 B2 fix (audit_v0.10.7 A_Net_audit.md HIGH): pre-
        -- v0.11.0 this branch silently returned with only a Log line,
        -- soft-locking the round with no user-facing surface. Reachable
        -- from 11+ call paths after a Reset/restore corruption (e.g.,
        -- /baloot reset between bid windows, hand-edited SavedVariables
        -- losing hostDeckRemainder, etc.). Now also surfaces an
        -- in-chat error so the player has a visible signal AND advises
        -- them to /baloot reset to recover. The log line is preserved
        -- for debug traces.
        log("Error", "HostFinishDeal: HostDealRest returned nil (hostHands=%s remainder=%s phase=%s)",
            tostring(S.s.hostHands ~= nil), tostring(S.s.hostDeckRemainder ~= nil),
            tostring(S.s.phase))
        print("|cffff5544WHEREDNGN error|r: deal state was lost between bidding windows "
            .. "(hostHands or hostDeckRemainder missing). Run |cffaaaaaa/baloot reset|r "
            .. "to recover and start a fresh round.")
        return
    end
    dealHandsToHumans(hands)
    S.ApplyHand(hands[S.s.localSeat])
    -- Skip the brief DEAL3 phase and go straight to PLAY: meld declaration
    -- is available throughout PLAY (until you commit your first card).
    S.ApplyPlayPhase()
    N.SendDealPhase("play")
    local leader = (S.s.dealer % 4) + 1
    S.ApplyTurn(leader, "play")
    N.SendTurn(leader, "play")
    N.MaybeRunBot()
    -- v0.10.5 user-reported bug fix: same shape as HostStartRound. If
    -- the trick-1 leader is the human host, no bot loopback Refresh
    -- fires → UI stays on prior phase. Force a Refresh.
    if B.UI and B.UI.Refresh then B.UI.Refresh() end
end

function N.LocalPlay(card)
    if S.s.paused then return end
    if not S.IsMyTurn() then return end
    if S.s.turnKind ~= "play" then return end
    cancelLocalWarn()
    -- Local guard against double-click: until the host echoes the
    -- turn change via SendTurn, IsMyTurn() stays true, so a second
    -- click would otherwise send a second card. ApplyTurn clears
    -- this flag when the next turn arrives.
    if S.s.localPlayedThisTrick then return end
    -- Saudi Takweesh rule: illegal plays are NOT blocked. We warn the
    -- player privately so they know what they're doing, but the card
    -- goes through. Opponents can call Takweesh to catch it.
    if S.s.contract then
        local ok, why = R.IsLegalPlay(card, S.s.hand, S.s.trick, S.s.contract, S.s.localSeat, S.s.akaCalled)
        if not ok then
            print(("|cffffaa00WHEREDNGN|r warning: this play is illegal (%s). Opponents can call Takweesh.")
                :format(why or "?"))
        end
    end
    if not S.s.meldsDeclared[S.s.localSeat] then
        S.s.meldsDeclared[S.s.localSeat] = true
    end
    N.CancelTurnTimer()
    local leadBefore = S.s.trick and S.s.trick.leadSuit or nil
    S.ApplyPlay(S.s.localSeat, card)
    S.s.localPlayedThisTrick = true
    if B.Bot and B.Bot.OnPlayObserved then
        B.Bot.OnPlayObserved(S.s.localSeat, card, leadBefore)
    end
    N.SendPlay(S.s.localSeat, card)
    if S.s.isHost then N._HostStepPlay() end
end

-- ---------------------------------------------------------------------
-- Takweesh — catch the cheater
--
-- Any player can press the Takweesh button during PLAY. The host scans
-- all plays so far for any marked .illegal from the opposing team:
--   - found        => caller's team wins the round (full handTotal x mult)
--   - not found    => caller's team forfeits (other team wins)
-- Either way the round ends immediately; game continues to next round
-- if no team has reached the cumulative target.
-- ---------------------------------------------------------------------

function N.LocalTakweesh()
    if S.s.paused then return end
    if S.s.phase ~= K.PHASE_PLAY then return end
    if not S.s.localSeat or not S.s.contract then return end
    broadcast(("%s;%d"):format(K.MSG_TAKWEESH, S.s.localSeat))
    if S.s.isHost then N.HostResolveTakweesh(S.s.localSeat) end
end

function N._OnTakweesh(sender, callerSeat)
    if fromSelf(sender) then return end
    if not callerSeat then return end
    -- Phase: Takweesh is a PLAY-only action.
    if S.s.phase ~= K.PHASE_PLAY then return end
    -- Authority: sender must own the seat raising the call. (Note: the
    -- host's HostResolveTakweesh does its own phase check + scan, so this
    -- is purely about preventing forged calls on someone else's behalf.)
    if not authorizeSeat(callerSeat, sender) then return end
    if S.s.isHost then N.HostResolveTakweesh(callerSeat) end
end

function N._OnTakweeshOut(sender, callerSeat, caught, illegalSeat, card, reason)
    if fromSelf(sender) then return end
    if not fromHost(sender) then return end
    if S.s.isHost then return end
    -- v0.11.5 NetA-07 / XR-04 fix: validate callerSeat ∈ [1,4] and
    -- illegalSeat ∈ [0,4] (0 = "no offender" sentinel from line 2456
    -- wire format). Pre-v0.11.5 a buggy/forked host emitting
    -- MSG_TAKWEESH_OUT with garbage callerSeat=99 wrote
    -- S.s.takweeshResult.caller = 99; the UI banner read S.s.seats[99]
    -- (nil) and label fallback dropped to "?". Wire-validation
    -- defense-in-depth.
    if not callerSeat or callerSeat < 1 or callerSeat > 4 then return end
    if illegalSeat and (illegalSeat < 0 or illegalSeat > 4) then return end
    -- Display only — score change rides through the parallel SendRound.
    local cName = S.s.seats[callerSeat] and (S.s.seats[callerSeat].name:match("^([^%-]+)") or S.s.seats[callerSeat].name) or "?"
    if caught then
        local iName = illegalSeat and S.s.seats[illegalSeat] and (S.s.seats[illegalSeat].name:match("^([^%-]+)") or S.s.seats[illegalSeat].name) or "?"
        local rankG, glyph = "?", "?"
        if card and #card >= 2 then
            rankG = C.RankGlyph(C.Rank(card)) or C.Rank(card)
            glyph = K.SUIT_GLYPH[C.Suit(card)] or C.Suit(card)
        end
        local rsn = (reason ~= nil and reason ~= "") and reason or "illegal play"
        print(("|cffff0000TAKWEESH!|r %s caught %s playing %s%s — %s."):format(
            cName, iName, rankG, glyph, rsn))
        -- Mirror onto receivers' takweeshResult so the banner shows
        -- the same details on every client.
        S.s.takweeshResult = {
            caller   = callerSeat,
            offender = illegalSeat,
            card     = card,
            reason   = rsn,
            caught   = true,
            ts       = (GetTime and GetTime()) or 0,
        }
    else
        print(("|cffff0000TAKWEESH!|r %s called incorrectly. Penalty applied."):format(cName))
        S.s.takweeshResult = {
            caller = callerSeat,
            caught = false,
            ts     = (GetTime and GetTime()) or 0,
        }
    end
end

function N.HostResolveTakweesh(callerSeat)
    if not S.s.isHost or not S.s.contract then return end
    if S.s.phase ~= K.PHASE_PLAY then return end
    -- Idempotence: a rapid double-click on the Takweesh button could
    -- reach here twice. The phase guard above handles re-entry from the
    -- second call (since the first sets phase=SCORE), but only after the
    -- first one finishes. Cancel any pending turn timer up front.
    N.CancelTurnTimer()
    -- 50-agent audit fix (Wave 6/9/10 concern): explicitly clear any
    -- in-flight SWA request. Takweesh is a Saudi-rule preempt of SWA
    -- (it points to an actual illegal play, which dominates the
    -- "I claim the rest" SWA). Without this nil, the SWA 5-sec timer
    -- only no-ops via the phase-guard check (phase ~= PHASE_PLAY) —
    -- works, but leaves stale `swaRequest` non-nil through PHASE_SCORE
    -- and contradicts the changelog claim that "Takweesh during the
    -- window clears swaRequest". Belt-and-braces with ApplyStart's
    -- round-start clear; harmless if no SWA was pending.
    S.s.swaRequest = nil

    local callerTeam = R.TeamOf(callerSeat)
    local oppTeam = (callerTeam == "A") and "B" or "A"

    -- Find any illegal play by a member of the opposing team.
    local function scanIllegal(plays)
        for _, p in ipairs(plays or {}) do
            if p.illegal and R.TeamOf(p.seat) ~= callerTeam then return p end
        end
    end
    local foundIllegal
    for _, t in ipairs(S.s.tricks) do
        foundIllegal = scanIllegal(t.plays)
        if foundIllegal then break end
    end
    if not foundIllegal and S.s.trick then
        foundIllegal = scanIllegal(S.s.trick.plays)
    end

    -- Takweesh is the canonical Saudi "Qayd" (قيد) early-termination
    -- penalty. Per the Saudi scoring system document:
    --   • Winner takes handTotal × mult (= 26 Sun / 16 Hokm in game
    --     points after div10).
    --   • "المشروع لصاحبه" — MELDS STAY WITH THEIR OWNERS. The
    --     loser's melds do NOT transfer. The winner only adds THEIR
    --     OWN declared melds × mult to their pile.
    --   • Belote independent +20 raw to its played-out K+Q holder.
    -- Same for both branches; the only thing that flips is which
    -- team is the winner (caught → caller's; not caught → opp).
    local c = S.s.contract
    local winnerTeam = foundIllegal and callerTeam or oppTeam

    local handTotal = (c.type == K.BID_SUN) and K.HAND_TOTAL_SUN or K.HAND_TOTAL_HOKM
    -- v1.0.9 D HIGH-1 (PDF §5-6 cap-at-Bel for melds): split multiplier
    -- into card vs meld so the Qaid path matches R.ScoreRound's
    -- canonical form. Cards cascade through Triple/Four/Gahwa; melds
    -- only ever multiply by Bel (×2). Sun has its own ×2 baseline on
    -- both. Pre-v1.0.9 used a single `mult = full cascade` and applied
    -- it to (cards + melds) — over-multiplied non-offender melds by
    -- ×3/×4 instead of ×2 on Triple/Four/Gahwa Qaid resolutions.
    local cardMult = K.MULT_BASE
    local meldMult = K.MULT_BASE
    if c.type == K.BID_SUN then
        cardMult = cardMult * K.MULT_SUN
        meldMult = meldMult * K.MULT_SUN
        if c.doubled then
            cardMult = cardMult * K.MULT_BEL
            meldMult = meldMult * K.MULT_BEL
        end
    else
        if     c.gahwa   then cardMult = cardMult * K.MULT_FOUR
        elseif c.foured  then cardMult = cardMult * K.MULT_FOUR
        elseif c.tripled then cardMult = cardMult * K.MULT_TRIPLE
        elseif c.doubled then cardMult = cardMult * K.MULT_BEL end
        if c.doubled or c.tripled or c.foured or c.gahwa then
            meldMult = meldMult * K.MULT_BEL
        end
    end

    local meldA = R.SumMeldValue(S.s.meldsByTeam.A)
    local meldB = R.SumMeldValue(S.s.meldsByTeam.B)
    local cardA = (winnerTeam == "A") and handTotal or 0
    local cardB = (winnerTeam == "B") and handTotal or 0
    -- Saudi Qaid rule (offender melds forfeited):
    --
    -- v0.10.0 review M1 — user-arbitrated reading (option A):
    --   * Source H H-36.12: offender's melds are "zeroed/forfeited"
    --   * PDF 02 K-04 (نظام التسجيل في البلوت): "the buyer's meld is
    --     forfeited (kept by neither side, just lost)"
    --   * PDF K-08's "stays with owner" wording was reread under the
    --     v0.10.0 audit as ambiguous — possibly "stays in the pile but
    --     doesn't count" rather than "owner scores it." User picked
    --     the explicit-forfeit reading per H + K-04.
    --
    -- Per the user's M1 arbitration, the offender's team forfeits its
    -- own declared melds when found illegal (Qaid). The non-offender
    -- team (winner) keeps theirs and adds them × mult. Belote
    -- independent regardless of side (rb3haa).
    --
    -- Pre-v0.10.1 the 14th-audit fix kept BOTH teams' melds (citing
    -- K-08); v0.10.1 reverses that for the Qaid context only —
    -- regular contract-fail in R.ScoreRound is a separate (non-Qaid)
    -- scenario and continues to keep both teams' own melds.
    local offenderTeam = (winnerTeam == "A") and "B" or "A"
    local mpA = (offenderTeam == "A") and 0 or meldA
    local mpB = (offenderTeam == "B") and 0 or meldB

    -- Belote (Hokm only, played cards only — Saudi rule rb3haa).
    -- Cancelled when the K+Q holder's TEAM declared a ≥100 meld
    -- (per "ماهو البلوت في لعبة البلوت"). v0.10.5 MED-1: switched
    -- from SAME-PLAYER check to TEAM-level via R.IsBeloteCancelled
    -- so this Qaid path matches R.ScoreRound's canonical post-v0.9.0
    -- M5 form. Pre-v0.10.5 the same-player check missed cancellation
    -- when the K+Q holder's PARTNER declared the ≥100 meld, over-
    -- crediting the bidder team by +2 gp on Takweesh-context rounds.
    local belote
    if c.type == K.BID_HOKM and c.trump then
        local kWho, qWho
        local function scan(plays_)
            for _, p in ipairs(plays_ or {}) do
                if C.Suit(p.card) == c.trump then
                    if C.Rank(p.card) == "K" then kWho = kWho or p.seat end
                    if C.Rank(p.card) == "Q" then qWho = qWho or p.seat end
                end
            end
        end
        for _, t in ipairs(S.s.tricks or {}) do scan(t.plays) end
        if S.s.trick then scan(S.s.trick.plays) end
        if kWho and qWho and kWho == qWho then
            belote = R.TeamOf(kWho)
            if R.IsBeloteCancelled(belote, S.s.meldsByTeam) then
                belote = nil
            end
            -- v1.0.11 (D HIGH-2): announcement gate also applies on
            -- the Takweesh/Qaid scoring path. Drop Belote bonus if
            -- the holder didn't announce (BALOOT button) AND the
            -- holder's team has no sequence meld in trump covering
            -- K+Q (PDF exception).
            if belote and S.s.beloteAnnounced
               and not S.s.beloteAnnounced[kWho]
               and R.TeamSequenceCoversBelote
               and not R.TeamSequenceCoversBelote(belote, S.s.meldsByTeam,
                                                   c.trump) then
                belote = nil
            end
        end
    end

    -- v1.0.9 D HIGH-1: cards × cardMult, melds × meldMult (cap at Bel
    -- per PDF §5-6). Belote alone is multiplier-immune (added post-mult).
    local rawA = (cardA * cardMult) + (mpA * meldMult)
    local rawB = (cardB * cardMult) + (mpB * meldMult)
    if belote == "A" then rawA = rawA + K.MELD_BELOTE
    elseif belote == "B" then rawB = rawB + K.MELD_BELOTE end

    -- v0.5.21 scoring-inconsistency fix: align with R.ScoreRound's
    -- v0.5.6 div10 fix (5 rounds UP per video #43). Pre-v0.5.21
    -- this Qaid path used the old (x+4)/10 (5 rounds DOWN) while
    -- R.ScoreRound used (x+5)/10. A Qaid penalty resolution
    -- rounded scores DIFFERENTLY than a regular round-end. User-
    -- reported "scoring not matching the docs" symptom.
    local addA = math.floor((rawA + 5) / 10)
    local addB = math.floor((rawB + 5) / 10)
    local totA = S.s.cumulative.A + addA
    local totB = S.s.cumulative.B + addB

    S.ApplyRoundEnd(addA, addB, totA, totB)
    -- Takweesh bypasses the normal scoring path, so lastRoundResult and
    -- the in-progress trick aren't cleaned up by anything else. Without
    -- this, the score banner shows the *previous* round's breakdown and
    -- the table still displays the half-played trick — which makes the
    -- transition to PHASE_SCORE invisible to the user (looks frozen).
    -- Stash a takweesh-result struct so the score banner can render
    -- the catch reason / card / suit instead of the generic "round done"
    -- fallback.
    S.s.lastRoundResult = nil
    S.s.trick = nil
    if foundIllegal then
        S.s.takweeshResult = {
            caller    = callerSeat,
            offender  = foundIllegal.seat,
            card      = foundIllegal.card,
            reason    = foundIllegal.illegalReason or "illegal play",
            caught    = true,
            ts        = (GetTime and GetTime()) or 0,
        }
    else
        S.s.takweeshResult = {
            caller    = callerSeat,
            caught    = false,
            ts        = (GetTime and GetTime()) or 0,
        }
    end
    N.SendRound(addA, addB, totA, totB)

    -- Print the outcome locally on host. Other clients receive
    -- _OnTakweeshOut from the broadcast below and print the same with
    -- the card + reason details too.
    local function shortN(seat)
        local info = S.s.seats[seat]
        if not info or not info.name then return "?" end
        return info.name:match("^([^%-]+)") or info.name
    end
    if foundIllegal then
        local card = foundIllegal.card or ""
        local r = (#card >= 1) and C.Rank(card) or "?"
        local s = (#card >= 2) and C.Suit(card) or "?"
        local glyph = K.SUIT_GLYPH[s] or s
        local rankG = C.RankGlyph(r) or r
        local reason = foundIllegal.illegalReason or "illegal play"
        print(("|cffff0000TAKWEESH!|r %s caught %s playing %s%s — %s."):format(
            shortN(callerSeat), shortN(foundIllegal.seat),
            rankG, glyph, reason))
    else
        print(("|cffff0000TAKWEESH!|r %s called incorrectly. Penalty applied."):format(
            shortN(callerSeat)))
    end
    -- Wire format extended: caught/illegalSeat/card/reason.
    -- "{tag};{caller};{caught};{offender};{card};{reason}"
    broadcast(("%s;%d;%s;%d;%s;%s"):format(K.MSG_TAKWEESH_OUT,
        callerSeat,
        foundIllegal and "1" or "0",
        foundIllegal and foundIllegal.seat or 0,
        foundIllegal and foundIllegal.card or "",
        foundIllegal and (foundIllegal.illegalReason or "") or ""))

    -- v0.10.5 MED-2: shared R.GameEndWinner with Qaid-context
    -- adapter. The Takweesh winner team (winnerTeam) wins the
    -- tiebreak — it was the team whose Takweesh call resolved the
    -- round. We map this onto bidderTeam/bidderMade by treating
    -- the Takweesh winner AS IF it were bidderMade=true. Pre-v0.10.5
    -- this path used pre-v0.8.6 raw-bidder-team logic, which could
    -- award the match to the OFFENDER team on simultaneous-target
    -- hits (the offender team was bidder team but lost the round).
    local winner = R.GameEndWinner(totA, totB, S.s.target, {
        gahwaWinner = nil,            -- Takweesh preempts Gahwa scoring
        bidderTeam  = winnerTeam,
        bidderMade  = true,
    })
    if winner then
        S.ApplyGameEnd(winner)
        N.SendGameEnd(winner)
    end
    -- Force an immediate UI repaint on host. Otherwise the player has
    -- to wait for the addon-message loopback (or close+reopen the frame)
    -- before the score panel becomes visible.
    if B.UI and B.UI.Refresh then B.UI.Refresh() end
end

-- Local AKA call. Validates that the local player actually holds the
-- highest unplayed card of `suit`, applies + broadcasts the cue.
-- Soft signal — does not change any legal-play constraints.
function N.LocalAKA(suit)
    if S.s.paused then return end
    if S.s.phase ~= K.PHASE_PLAY then return end
    if not S.s.contract or S.s.contract.type ~= K.BID_HOKM then return end
    if not S.s.localSeat then return end
    if not suit or suit == "" then return end
    -- v0.9.0 L4 fix (audit AUDIT_REPORT_v0.7.1.md): AKA must be called
    -- BEFORE leading. Pre-v0.9.0, a human pressing AKA mid-trick
    -- retroactively flipped s.akaCalled and suppressed the 4th-seat
    -- bot's ruff after the fact — informationally inconsistent. The
    -- correct gate: the local seat must be about to LEAD (no plays
    -- in the current trick yet), AND it must be their turn. The
    -- v0.5.16 implicit-AKA path is unaffected (it fires from
    -- pickFollow's pre-play observation, not via this wire).
    if S.s.trick and S.s.trick.plays and #S.s.trick.plays > 0 then
        return
    end
    if S.s.turn ~= S.s.localSeat or S.s.turnKind ~= "play" then
        return
    end
    -- Sanity-check: the caller really does hold the AKA in this suit.
    -- (Anti-misclick + light anti-cheat — UI would have hidden the
    -- button otherwise, but the network handler shouldn't trust UI.)
    local cand = S.LocalAKAcandidate()
    if not cand or cand.suit ~= suit then return end
    S.ApplyAKA(S.s.localSeat, suit)
    N.SendAKA(S.s.localSeat, suit)
    if B.UI and B.UI.Refresh then B.UI.Refresh() end
end

function N.LocalDeclareMeld(meld)
    if S.s.paused then return end
    if not meld then return end
    S.ApplyMeld(S.s.localSeat, meld.kind, meld.suit, meld.top, B.Cards.EncodeHand(meld.cards or {}))
    N.SendMeld(S.s.localSeat, meld)
    -- Don't lock here: a player can declare MULTIPLE melds (Pagat-strict).
    -- The lock fires when the player explicitly clicks "Done", or when
    -- they commit their first card of the trick (LocalPlay).
    if B.UI and B.UI.Refresh then B.UI.Refresh() end
end

-- ---------------------------------------------------------------------
-- Kawesh / Saneen — annul a hand whose 5 dealt cards are all 7/8/9.
-- Available only during round 1 bidding (PHASE_DEAL1). Triggers a
-- redeal with the next dealer (rotation advances).
-- ---------------------------------------------------------------------

-- ---------------------------------------------------------------------
-- Pause / resume.
-- Host-only entry point. Mirrors a paused flag to all clients via
-- MSG_PAUSE. While paused:
--   • MaybeRunBot returns immediately (bot scheduling suspended).
--   • The AFK turn timer is cancelled; resume re-arms it.
--   • UI disables hand-card clicks and bid/play buttons (UI side).
-- The in-flight state (turn pointer, trick, contract, hand) is left
-- intact, so resume picks up exactly where we paused.
-- ---------------------------------------------------------------------
function N.LocalPause(paused)
    if not S.s.isHost then return end
    paused = (paused and true) or false
    if S.s.paused == paused then return end  -- idempotent
    S.ApplyPause(paused)
    N.SendPause(paused)
    if paused then
        N.CancelTurnTimer()
    else
        -- Resume: re-arm timers and re-dispatch any pending bot turn.
        -- Codex #4 audit catch: if a 4-card trick was already complete
        -- when pause hit, the 2.2s resolution timer fired silently
        -- (bailed on s.paused). After resume, NOTHING re-triggers
        -- _HostStepPlay, so the trick stays stuck. Detect that case
        -- here and re-schedule resolution.
        --
        -- v0.10.6 user-reported bug fix: also handle the redeal-
        -- stuck case. If pause hit during the 3s redeal banner, the
        -- timer fires + bare-exits on paused → no deal. After resume,
        -- s.redealing is still set but no recovery exists. Re-arm a
        -- fresh 3s window so the user sees the banner one more time
        -- before the actual deal lands. Banner may already have
        -- expired client-side via ApplyRedealAnnouncement's 3.5s
        -- auto-clear, but the deal still proceeds correctly via
        -- _HostExecuteRedeal which validates s.redealing.
        if S.s.phase == K.PHASE_PLAY
           and S.s.trick and S.s.trick.plays
           and #S.s.trick.plays >= 4 then
            N._HostStepPlay()
        elseif S.s.redealing
           and (S.s.phase == K.PHASE_DEAL2BID or S.s.phase == K.PHASE_DEAL1) then
            local nextDealer = S.s.redealing.nextDealer
            if nextDealer and C_Timer and C_Timer.After then
                B._redealGen = (B._redealGen or 0) + 1
                local thisGen = B._redealGen
                C_Timer.After(3.0, function()
                    if thisGen ~= B._redealGen then return end
                    N._HostExecuteRedeal(nextDealer)
                end)
            end
        else
            N.MaybeRunBot()
            if S.s.turn and S.s.turnKind then
                N.StartTurnTimer(S.s.turn, S.s.turnKind)
            end
        end
        -- 4th-audit X8 fix: also re-arm the LOCAL T-10s pre-warn
        -- (audio ping + UI pulse). StartLocalWarn was cancelled
        -- when pause hit; without this re-dispatch, the human at
        -- the active seat / eligible escalation seat gets no
        -- pre-warn ping until the next phase change. Mirrors the
        -- PLAYER_LOGIN restore re-arm in WHEREDNGN.lua.
        if N.StartLocalWarn then
            local sk = S.s.turnKind
            if sk == "bid" or sk == "play" then
                N.StartLocalWarn(sk)
            elseif S.s.phase == K.PHASE_DOUBLE then
                N.StartLocalWarn("bel")
            elseif S.s.phase == K.PHASE_TRIPLE then
                N.StartLocalWarn("triple")
            elseif S.s.phase == K.PHASE_FOUR then
                N.StartLocalWarn("four")
            elseif S.s.phase == K.PHASE_GAHWA then
                N.StartLocalWarn("gahwa")
            elseif S.s.phase == K.PHASE_PREEMPT then
                N.StartLocalWarn("preempt")
            end
        end
    end
    if B.UI and B.UI.Refresh then B.UI.Refresh() end
end

function N._OnPause(sender, payload)
    if fromSelf(sender) then return end
    if not fromHost(sender) then return end
    if S.s.isHost then return end
    -- v0.11.5 XR-05 fix: enforce payload domain. Pre-v0.11.5 any
    -- non-"1" payload (nil, "0", "true", garbage) silently mapped to
    -- false (resume). Practically harmless because both states are
    -- valid game states, but bogus payloads should be rejected at
    -- the wire rather than silently coerced. Treat anything that's
    -- not exactly "1" or "0" as an unknown command and drop it.
    if payload ~= "1" and payload ~= "0" then return end
    local paused = (payload == "1")
    if S.s.paused == paused then return end
    S.ApplyPause(paused)
end

function N._OnTeams(sender, teamA, teamB)
    if fromSelf(sender) then return end
    if not fromHost(sender) then return end
    if S.s.isHost then return end
    S.ApplyTeamNames(teamA, teamB)
end

-- AKA call from the wire. Soft signal — we apply locally regardless of
-- whether the caller actually has the AKA (the sender already validated
-- on their side, and false-claims aren't worth the bandwidth to police).
-- Local SWA call. Validates phase + sends the remaining hand. Host
-- (which has all four hands) makes the final decision.
function N.LocalSWA()
    if S.s.paused then return end
    if S.s.phase ~= K.PHASE_PLAY then return end
    if not S.s.localSeat or not S.s.contract then return end
    if WHEREDNGNDB and WHEREDNGNDB.allowSWA == false then return end
    -- Saudi rule (per video tutorial): calls with 4+ cards remaining
    -- require opponent permission. Calls with ≤3 cards used to be
    -- instant; v0.5.17 routes ALL calls through the 5-second
    -- permission display so the caller's cards are visible to all
    -- players in every scenario (per user requirement). Opponents
    -- can still Takweesh during the window if they spot an illegal
    -- play; bots auto-accept.
    -- Toggle the permission requirement via WHEREDNGNDB.swaRequiresPermission.
    local handCount = #(S.s.hand or {})
    local needPerm = (WHEREDNGNDB == nil)
                  or (WHEREDNGNDB.swaRequiresPermission ~= false)
    -- Defensive: clear any stale SWA banner from earlier in the round
    -- before we send the new claim so no flicker / wrong-state UI.
    S.s.swaResult = nil
    -- Sim 13 / Audit 19 catch: if a permission request is already
    -- in flight, a rapid second click would clobber the existing
    -- request and lose any opponent votes already collected. Reject
    -- the second call until the first resolves or denies.
    if S.s.swaRequest and S.s.swaRequest.caller == S.s.localSeat then
        return
    end
    -- v0.5.17: route ≤3-card claims through the permission window
    -- too, so the SWA banner displays the caller's cards. Was:
    -- `if needPerm and handCount >= 4`. Now: `if needPerm` (any count).
    if needPerm then
        -- Permission flow: broadcast a request, wait for opponents.
        local enc = C.EncodeHand(S.s.hand or {})
        S.s.swaRequest = {
            caller    = S.s.localSeat,
            handCount = handCount,
            responses = {},  -- [seat] = true (accept) / false (deny)
            -- 7th-audit fix: stash the encoded hand locally too. The
            -- _OnSWAReq self-loopback is dropped by `fromSelf`, so the
            -- host calling its own SWA never gets encodedHand populated
            -- via the network path. When opponents accept and the
            -- host's _OnSWAResp tries `req.encodedHand or ""`, it
            -- would otherwise resolve as an empty hand (failing
            -- IsValidSWA and penalising the host).
            encodedHand = enc,
            -- Same 5-sec auto-approve window as _OnSWAReq.
            ts        = (GetTime and GetTime()) or 0,
            windowSec = K.SWA_TIMEOUT_SEC or 5,
        }
        N.SendSWAReq(S.s.localSeat, enc)
        -- 9th-audit fix: same bot auto-accept as the _OnSWAReq path.
        -- The host's own LocalSWA self-loopback is dropped by
        -- fromSelf, so without this branch a host calling SWA in a
        -- bot game would never get the bots to vote.
        -- v0.11.16 audit H1: bots now run Bot.PickSWAResponse to deny
        -- clearly-invalid SWAs. Default still ACCEPT for validator-
        -- pass or ambiguity. See _OnSWAReq for the same-shape change.
        if S.s.isHost then
            local callerTeam = R.TeamOf(S.s.localSeat)
            for s2 = 1, 4 do
                local info = S.s.seats[s2]
                if info and info.isBot and R.TeamOf(s2) ~= callerTeam then
                    local accept = true
                    if B.Bot and B.Bot.PickSWAResponse then
                        local ok, decided = pcall(B.Bot.PickSWAResponse, s2, S.s.localSeat, enc)
                        if ok and decided == false then accept = false end
                    end
                    N._OnSWAResp("__host__", s2, accept, S.s.localSeat)
                end
            end
            -- 5-sec auto-approve timer (mirrors _OnSWAReq). If the
            -- request is still pending when the timer fires, host
            -- resolves SWA. Takweesh / explicit deny during the
            -- window clears swaRequest, and the caller-match guard
            -- below makes the timer a no-op in that case.
            if C_Timer and C_Timer.After then
                local windowSec  = K.SWA_TIMEOUT_SEC or 5
                local mySeat     = S.s.localSeat
                local pinnedHand = {}
                for _, c in ipairs(S.s.hand or {}) do
                    pinnedHand[#pinnedHand + 1] = c
                end
                -- v0.10.3 SWA pause re-arm refactor (review_v0.10.2
                -- E-Net-01, HIGH). Pre-v0.10.3 this site had a
                -- ONE-STEP re-arm: if paused on first fire, schedule
                -- one more timer; that inner timer bare-exited on
                -- pause too. Multi-cycle pause-toggles within the
                -- window dropped subsequent re-arms → soft-lock.
                -- Refactored to a named function that recursively
                -- re-arms itself, mirroring the OVERCALL pattern
                -- at line ~1195. Same fix at the bot-fired site
                -- ~4059 and the _OnSWAReq host wrapper ~2691.
                local function localSWAResolveFn()
                    if not S.s.isHost then return end
                    if S.s.paused then
                        local req2 = S.s.swaRequest
                        if req2 and req2.caller == mySeat then
                            req2.ts = (GetTime and GetTime()) or req2.ts
                            if C_Timer and C_Timer.After then
                                C_Timer.After(K.SWA_TIMEOUT_SEC or 5,
                                              localSWAResolveFn)
                            end
                        end
                        return
                    end
                    local req = S.s.swaRequest
                    if not req or req.caller ~= mySeat then return end
                    if S.s.phase ~= K.PHASE_PLAY then return end
                    S.s.swaRequest = nil
                    N.HostResolveSWA(mySeat, pinnedHand)
                end
                C_Timer.After(windowSec, localSWAResolveFn)
            end
        end
        if B.UI and B.UI.Refresh then B.UI.Refresh() end
        return
    end
    -- Direct claim (permission disabled — `swaRequiresPermission == false`):
    -- send the actual SWA wire and let the host resolve immediately.
    --
    -- v1.0.2 (L1): comment cleanup. Pre-v0.5.17 the fall-through also
    -- fired for ≤3-card claims (Saudi rule: ≤3 cards = instant, no
    -- permission needed). v0.5.17 routed ALL counts through the
    -- permission window so the caller's cards display in the
    -- 5-second banner regardless of count — `if needPerm then ...`
    -- above now catches every claim when permission is enabled.
    -- The "≤3 cards" half of the prior comment was stale.
    local enc = C.EncodeHand(S.s.hand or {})
    N.SendSWA(S.s.localSeat, enc)
    if S.s.isHost then N.HostResolveSWA(S.s.localSeat, S.s.hand or {}) end
end

-- Local response to an in-flight SWA permission request. Called from
-- the UI's Accept / Deny buttons.
function N.LocalSWAResp(accept)
    if S.s.paused then return end
    local req = S.s.swaRequest
    if not req or not req.caller then return end
    -- Caller doesn't vote on their own request.
    if S.s.localSeat == req.caller then return end
    -- Only opponents (cross-team) vote; teammates of caller don't
    -- gate the request.
    if R.TeamOf(S.s.localSeat) == R.TeamOf(req.caller) then return end
    -- Idempotence: if we've already voted, ignore.
    if req.responses and req.responses[S.s.localSeat] ~= nil then return end
    N.SendSWAResp(S.s.localSeat, accept, req.caller)
    -- Host: also process locally for the host's own apply.
    if S.s.isHost then
        N._OnSWAResp("__host__", S.s.localSeat, accept, req.caller)
    else
        -- 10th-audit fix: non-host responder must also apply the
        -- response to their OWN swaRequest. The wire echo loops back
        -- via _OnSWAResp but the fromSelf gate drops it, leaving the
        -- responder with stale Accept/Deny buttons (and the
        -- _OnSWAReq pending-guard rejecting a fresh SWA later in the
        -- same round). For deny: clear local swaRequest immediately.
        -- For accept: record our own vote so the UI hides the
        -- buttons. Host-side resolution still drives the round
        -- outcome on the wire — this is purely local UI state.
        if accept then
            req.responses = req.responses or {}
            req.responses[S.s.localSeat] = true
        else
            S.s.swaRequest = nil
            S.s.swaDenied = {
                caller = req.caller,
                denier = S.s.localSeat,
                ts     = (GetTime and GetTime()) or 0,
            }
            if C_Timer and C_Timer.After then
                local denyCaller = req.caller
                C_Timer.After(3.0, function()
                    if S.s.swaDenied
                       and S.s.swaDenied.caller == denyCaller then
                        S.s.swaDenied = nil
                        if B.UI and B.UI.Refresh then B.UI.Refresh() end
                    end
                end)
            end
        end
        if B.UI and B.UI.Refresh then B.UI.Refresh() end
    end
end

function N._OnSWAReq(sender, seat, encodedHand)
    if fromSelf(sender) then return end
    if not seat or seat < 1 or seat > 4 then return end
    -- v0.11.5 XR-06 fix: cap encodedHand to 16 chars (max 8 cards × 2
    -- chars/card). Pre-v0.11.5 the encoded hand was stashed unbounded
    -- into S.s.swaRequest, which is NOT in TRANSIENT_FIELDS and so
    -- persists to SavedVariables. The actual attack surface is small
    -- (WoW addon-channel max payload caps ~252 bytes per chunk) but
    -- explicit cap means a future channel-format change can't re-open
    -- this for unbounded growth.
    if encodedHand and #encodedHand > 16 then return end
    if S.s.phase ~= K.PHASE_PLAY then return end
    if not authorizeSeat(seat, sender) then return end
    if WHEREDNGNDB and WHEREDNGNDB.allowSWA == false then return end
    -- 6th-audit fix: overwrite guard. If a request is already
    -- pending (e.g., a different player's request was just received
    -- and is still being voted on), a second MSG_SWA_REQ would
    -- clobber the in-flight request, dropping any votes that had
    -- already arrived. Reject the second request until the first
    -- resolves. Same caller re-sending is also a no-op (the first
    -- request struct is still authoritative).
    if S.s.swaRequest and S.s.swaRequest.caller then
        return
    end
    -- Stash the pending request so the UI can render the SWA-claim
    -- preview and the TAKWEESH counter button. User-requested change:
    -- the SWA cards display for 5 seconds and auto-approve on timeout
    -- — opponents counter exclusively via Takweesh (which scans prior
    -- tricks for illegal plays). Accept/Deny vote still works as a
    -- manual override path; bots auto-accept (no Takweesh needed) so
    -- the timer is mostly a safety net for human deadlocks.
    S.s.swaRequest = {
        caller    = seat,
        handCount = (encodedHand and (#encodedHand / 2)) or 0,
        responses = {},
        encodedHand = encodedHand,
        ts        = (GetTime and GetTime()) or 0,  -- UI countdown anchor
        windowSec = K.SWA_TIMEOUT_SEC or 5,
    }
    -- 9th-audit fix (Codex+Gemini consensus): bots never send
    -- MSG_SWA_RESP, so a host-with-bots game would deadlock here —
    -- MaybeRunBot's SWA guard blocks bot dispatch waiting for two
    -- accepts that never come. Auto-vote on behalf of any opponent
    -- bot (cross-team) by feeding _OnSWAResp the synthetic
    -- "__host__" sender.
    --
    -- v0.11.16 audit H1: bots used to default to ACCEPT (no meta-game
    -- read justifying denial). Now bots run R.IsValidSWA via
    -- Bot.PickSWAResponse on the caller's encoded hand (decoded) +
    -- known host hands. If the validator strictly rejects (false),
    -- bot DENIES — turning unsound human SWAs into Qaid penalty for
    -- the offender team. Default behavior on validator-pass or any
    -- ambiguity stays ACCEPT (matching the addon's "humans handle
    -- close calls verbally" UX intent).
    if S.s.isHost then
        local callerTeam = R.TeamOf(seat)
        for s2 = 1, 4 do
            local info = S.s.seats[s2]
            if info and info.isBot and R.TeamOf(s2) ~= callerTeam then
                local accept = true
                if B.Bot and B.Bot.PickSWAResponse then
                    local ok, decided = pcall(B.Bot.PickSWAResponse, s2, seat, encodedHand)
                    if ok and decided == false then accept = false end
                end
                N._OnSWAResp("__host__", s2, accept, seat)
            end
        end
        -- Audit (user-requested): 5-second auto-approve timer. If the
        -- swaRequest is still active and bound to the same caller when
        -- the timer fires, run HostResolveSWA. Takweesh during the
        -- window clears swaRequest (existing flow) and the timer
        -- becomes a no-op via the caller-match guard.
        if C_Timer and C_Timer.After then
            local windowSec = K.SWA_TIMEOUT_SEC or 5
            -- v0.10.3 SWA pause re-arm refactor (review_v0.10.2
            -- E-Net-01, HIGH). See companion fixes at ~2546 and
            -- ~4059. Recursive re-arm closes the multi-cycle pause-
            -- toggle leak in the prior one-step version.
            local function reqSWAResolveFn()
                if not S.s.isHost then return end
                if S.s.paused then
                    local req2 = S.s.swaRequest
                    if req2 and req2.caller == seat then
                        req2.ts = (GetTime and GetTime()) or req2.ts
                        if C_Timer and C_Timer.After then
                            C_Timer.After(K.SWA_TIMEOUT_SEC or 5,
                                          reqSWAResolveFn)
                        end
                    end
                    return
                end
                local req = S.s.swaRequest
                if not req or req.caller ~= seat then return end
                if S.s.phase ~= K.PHASE_PLAY then return end
                -- Decode the caller's hand from the wire (host's
                -- hostHands is authoritative; HostResolveSWA prefers
                -- it but falls back to the wire-supplied hand).
                local hand = (encodedHand and C.DecodeHand(encodedHand)) or {}
                S.s.swaRequest = nil
                N.HostResolveSWA(seat, hand)
            end
            C_Timer.After(windowSec, reqSWAResolveFn)
        end
    end
    if B.UI and B.UI.Refresh then B.UI.Refresh() end
end

function N._OnSWAResp(sender, responder, accept, caller)
    -- "__host__" is a synthetic in-process call from N.LocalSWAResp on
    -- the host; treat it like a remote message but skip fromSelf.
    if sender ~= "__host__" then
        if fromSelf(sender) then return end
        if not authorizeSeat(responder, sender) then return end
    end
    -- v0.11.11 NetU-08 fix: range-check responder + caller. Pre-v0.11.11
    -- garbage seat numbers wrote req.responses[99] which lingered in
    -- SavedVariables (swaRequest is not in TRANSIENT_FIELDS — host
    -- needs it across /reload).
    if not responder or responder < 1 or responder > 4 then return end
    if not caller or caller < 1 or caller > 4 then return end
    local req = S.s.swaRequest
    if not req or req.caller ~= caller then return end
    if R.TeamOf(responder) == R.TeamOf(caller) then return end
    req.responses = req.responses or {}
    if req.responses[responder] ~= nil then return end
    req.responses[responder] = accept

    -- Any deny cancels the request EVERYWHERE — every receiver clears
    -- the pending request and the round resumes from where it left
    -- off. No scoring change. We track the denier for a brief UI
    -- toast so the caller sees who blocked them.
    if not accept then
        S.s.swaRequest = nil
        S.s.swaDenied = {
            caller   = caller,
            denier   = responder,
            ts       = (GetTime and GetTime()) or 0,
        }
        if C_Timer and C_Timer.After then
            C_Timer.After(3.0, function()
                if S.s.swaDenied
                   and S.s.swaDenied.caller == caller then
                    S.s.swaDenied = nil
                    if B.UI and B.UI.Refresh then B.UI.Refresh() end
                end
            end)
        end
        if B.UI and B.UI.Refresh then B.UI.Refresh() end
        -- 8th-audit fix: resume bot dispatch / re-arm turn timer.
        -- The SWA pending guard at MaybeRunBot's entry caused a soft-
        -- lock when a bot's turn was waiting and the SWA was denied
        -- — without re-pumping, the table sits with no scheduled bot
        -- action until something else (a human play, /pause toggle)
        -- nudges the dispatcher.
        if S.s.isHost then
            if S.s.phase == K.PHASE_PLAY and S.s.turn and S.s.turnKind then
                if N.StartTurnTimer
                   and S.s.seats[S.s.turn] and not S.s.seats[S.s.turn].isBot
                then
                    -- Refresh the human turn's AFK timer with full budget.
                    N.StartTurnTimer(S.s.turn, S.s.turnKind)
                end
                N.MaybeRunBot()
            end
        end
        return
    end

    -- Accept counted. Check whether BOTH opponents have now accepted.
    if B.UI and B.UI.Refresh then B.UI.Refresh() end
    if not S.s.isHost then return end
    local oppTeam = (R.TeamOf(caller) == "A") and "B" or "A"
    local accepts = 0
    for s2 = 1, 4 do
        if R.TeamOf(s2) == oppTeam and req.responses[s2] == true then
            accepts = accepts + 1
        end
    end
    if accepts >= 2 then
        -- Both opponents granted permission. Resolve the claim using
        -- the encoded hand stashed in the request.
        local hand = C.DecodeHand(req.encodedHand or "")
        S.s.swaRequest = nil
        N.HostResolveSWA(caller, hand)
    end
end

function N._OnSWA(sender, seat, encodedHand)
    if fromSelf(sender) then return end
    if not seat or seat < 1 or seat > 4 then return end
    -- v0.11.5 XR-06 fix: cap encodedHand to 16 chars (mirrors the same
    -- guard added to _OnSWAReq above; instant-claim path needs the same
    -- bound).
    if encodedHand and #encodedHand > 16 then return end
    if S.s.phase ~= K.PHASE_PLAY then return end
    -- Authority: only the seat itself can call SWA on their behalf.
    if not authorizeSeat(seat, sender) then return end
    -- Host opt-out: in tournament mode (allowSWA = false), drop the
    -- claim. Hosts who disable SWA mid-round avoid awarding it on a
    -- late-arriving wire from a peer who hadn't seen the toggle yet.
    if S.s.isHost and WHEREDNGNDB
       and WHEREDNGNDB.allowSWA == false then
        return
    end
    -- v0.11.0 E2 fix (audit_v0.10.7 A_Net_audit.md MED): swaRequest
    -- mutex. _OnSWAReq has this guard at line 2783; _OnSWA didn't.
    -- A direct MSG_SWA claim from a different seat could race against
    -- an in-flight _OnSWAReq vote window — the second resolve would
    -- clobber the first. Reject the second when a request from a
    -- different caller is pending. Same-caller is also a no-op (the
    -- existing request is authoritative; we don't want to double-
    -- resolve).
    if S.s.swaRequest and S.s.swaRequest.caller then
        return
    end
    -- Host is the source of truth. Decode and resolve.
    if S.s.isHost then
        local hand = C.DecodeHand(encodedHand or "")
        N.HostResolveSWA(seat, hand)
    end
end

function N._OnSWAOut(sender, caller, valid, addA, addB, totA, totB, sweep, bidderMade, encodedHand)
    if fromSelf(sender) then return end
    if not fromHost(sender) then return end
    if S.s.isHost then return end
    if not caller then return end
    -- v0.11.5 NetA-07 / XR-04 fix: validate caller ∈ [1,4]. Pre-v0.11.5
    -- a buggy/forked host emitting MSG_SWA_OUT with garbage caller=99
    -- wrote S.s.swaResult.caller = 99; the SWA banner read
    -- S.s.seats[99] (nil) → label fallback "?". Same wire-validation
    -- shape as NetA-07 above.
    if caller < 1 or caller > 4 then return end
    -- v0.11.7 user feedback: encoded hand is field 10 (optional, for
    -- pre-v0.11.7 wire compat). Cap at 16 chars (max 8 cards × 2)
    -- mirroring the v0.11.5 XR-06 cap on MSG_SWA_REQ / MSG_SWA.
    if encodedHand and #encodedHand > 16 then encodedHand = nil end
    -- Mirror the takweesh-result struct so the score banner can
    -- render the SWA outcome with its own copy.
    S.s.swaResult = {
        caller = caller, valid = valid,
        sweep = sweep, contractMade = bidderMade,
        encodedHand = encodedHand,   -- v0.11.7
    }
    S.s.lastRoundResult = nil
    S.s.trick = nil
    -- 4th-audit X4 fix: pass sweep + bidderMade through so the BALOOT
    -- fanfare fires on remote clients too. Pre-v0.3.0 senders won't
    -- supply the flags; both decode to nil → no fanfare (back-compat).
    S.ApplyRoundEnd(addA or 0, addB or 0, totA or 0, totB or 0, sweep, bidderMade)
end

-- Host-only: resolve an SWA claim.
--
-- Saudi rule (per arabic-Baloot sources): a VALID SWA awards all
-- remaining trick points to the caller's team, who keep what they
-- already earned in played tricks. The contract still resolves
-- normally on the resulting team totals — sweep, made, or failed
-- as the math dictates. An INVALID SWA is a flat punitive penalty:
-- opponent takes handTotal × mult + all melds × mult.
--
-- Implementation: for valid SWA, we synthesize the remaining tricks
-- (each won by the caller seat) and reuse R.ScoreRound for the
-- actual scoring math. ScoreRound handles sweep / made / failed /
-- meld winner / last-trick bonus / belote correctly, so we get
-- everything right by construction.
function N.HostResolveSWA(callerSeat, callerHand)
    if not S.s.isHost or not S.s.contract then return end
    if S.s.phase ~= K.PHASE_PLAY then return end
    N.CancelTurnTimer()

    local callerTeam = R.TeamOf(callerSeat)
    local c          = S.s.contract
    local oppOfCaller = (callerTeam == "A") and "B" or "A"

    -- 9th-audit fix: prefer the host's authoritative hostHands for the
    -- caller too. The wire-supplied callerHand was previously trusted
    -- as-is, which let a stale or modified client validate impossible
    -- claims and miss real remaining card points in the score
    -- computation. Falling back to the wire only when hostHands is
    -- missing keeps the function usable when called from non-host
    -- contexts (defensive).
    local authoritative = (S.s.hostHands and S.s.hostHands[callerSeat])
    -- Snapshot all four hands. Caller's hand: trust the host's record;
    -- other three: same.
    local hands = { [callerSeat] = authoritative or callerHand }
    for s2 = 1, 4 do
        if s2 ~= callerSeat then
            hands[s2] = (S.s.hostHands and S.s.hostHands[s2]) or {}
        end
    end

    -- Reconstruct the current trick state for the minimax validator.
    local trickPlays = (S.s.trick and S.s.trick.plays) or {}
    local trickLead = S.s.trick and S.s.trick.leadSuit
    local trickLeader
    if #trickPlays > 0 then
        trickLeader = trickPlays[1].seat
    else
        -- 4th-audit X6 fix: when no plays are in flight (between
        -- tricks), the next-to-lead is whoever won the previous
        -- trick — i.e. S.s.turn. Hard-coding callerSeat as leader
        -- silently produced wrong validation when a non-leader seat
        -- called SWA between tricks.
        trickLeader = S.s.turn or callerSeat
    end
    local trickState = {
        leadSuit = trickLead, leader = trickLeader, plays = trickPlays,
    }

    -- Re-audit W7 fix: reject claims with no cards in caller's hand
    -- AND no in-flight plays. R.IsValidSWA's caller-empty short-
    -- circuit returns true in that case (legitimate when reached
    -- recursively at end-of-claim) but at top-level entry it's a
    -- corrupted-state signature — meaningless claim.
    local valid
    if (#(hands[callerSeat] or {})) == 0 and #trickPlays == 0 then
        valid = false
    else
        valid = R.IsValidSWA(callerSeat, hands, c, trickState)
    end

    local addA, addB, sweepTeam, contractMade
    -- v0.11.13 SU2-02 fix: hoist the per-team accounting locals out of
    -- the if/else blocks below. Pre-v0.11.13 these were declared with
    -- `local` INSIDE the `if not valid then ... else ... end` arms,
    -- which closes at the `end` BEFORE the breakdown-stash block. The
    -- breakdown reads at lines below (cardA/cardB/mpA/mpB/mult/
    -- beloteOwner for the invalid arm; `result` for the valid arm)
    -- therefore resolved to undefined globals (= nil), making both
    -- breakdown branches silently empty. SU-Ultra-01 (v0.11.11) was
    -- shipped UNREACHABLE — the same "shipped dead code" failure
    -- pattern as v0.11.2 SU-Ultra-01 itself was meant to fix. The
    -- audit U.11 source-string pin matched `breakdown = breakdown`
    -- but couldn't catch the scope error — only behavioral testing
    -- (XU-01 phase 2) would've caught it. Hoisted to outer scope so
    -- both arms can populate them and the breakdown block can read.
    local result
    local cardA, cardB, mpA, mpB, mult, beloteOwner

    if not valid then
        -- INVALID SWA → Qayd penalty (Saudi rule): opp takes
        -- handTotal × mult (= 26 Sun / 16 Hokm in final game
        -- points). Per "المشروع لصاحبه" the offender's meld STAYS
        -- WITH THEM — does NOT transfer to opp. Opp only adds
        -- THEIR OWN melds × mult. Belote independent.
        local handTotal = (c.type == K.BID_SUN) and K.HAND_TOTAL_SUN or K.HAND_TOTAL_HOKM
        -- v1.0.9 D HIGH-1 (PDF §5-6 cap-at-Bel): split multiplier into
        -- cardMult (cascades) vs meldMult (capped at Bel). Pre-v1.0.9
        -- a single full-cascade `mult` over-multiplied non-offender
        -- melds by ×3/×4 on Triple/Four/Gahwa Qaid resolutions.
        local cardMult = K.MULT_BASE
        local meldMult = K.MULT_BASE
        if c.type == K.BID_SUN then
            cardMult = cardMult * K.MULT_SUN
            meldMult = meldMult * K.MULT_SUN
            if c.doubled then
                cardMult = cardMult * K.MULT_BEL
                meldMult = meldMult * K.MULT_BEL
            end
        else
            if     c.gahwa   then cardMult = cardMult * K.MULT_FOUR
            elseif c.foured  then cardMult = cardMult * K.MULT_FOUR
            elseif c.tripled then cardMult = cardMult * K.MULT_TRIPLE
            elseif c.doubled then cardMult = cardMult * K.MULT_BEL end
            if c.doubled or c.tripled or c.foured or c.gahwa then
                meldMult = meldMult * K.MULT_BEL
            end
        end
        -- Legacy alias for the outer-scope telemetry (`multiplier`
        -- field at line ~3498). Older consumers expect the contract-
        -- rung multiplier (= cards' multiplier).
        mult = cardMult
        local meldA = R.SumMeldValue(S.s.meldsByTeam.A)
        local meldB = R.SumMeldValue(S.s.meldsByTeam.B)
        cardA = (oppOfCaller == "A") and handTotal or 0
        cardB = (oppOfCaller == "B") and handTotal or 0
        -- Saudi Qaid rule (offender melds forfeited).
        --
        -- v0.10.1 M1 fix (user-arbitrated): an invalid-SWA call is a
        -- Qaid context — the caller (offender) forfeits their team's
        -- own declared melds. Per Source H H-36.12 + PDF 02 K-04
        -- ("the buyer's meld is forfeited"), offender's melds are
        -- not just transferred elsewhere — they are zeroed for the
        -- round. The penalty (handTotal × mult) flows to the
        -- non-offender team; that team also keeps THEIR own melds.
        -- Belote independent. Pre-v0.10.1 the 14th-audit fix kept
        -- both teams' melds; v0.10.1 reverses for the Qaid context.
        mpA = (callerTeam == "A") and 0 or meldA
        mpB = (callerTeam == "B") and 0 or meldB
        -- Belote scan (played cards only — Saudi rule rb3haa).
        -- Cancelled when the K+Q holder also declared a ≥100 meld.
        -- v0.10.5 MED-1: Belote cancellation switched from SAME-PLAYER
        -- to TEAM-level via R.IsBeloteCancelled — matches R.ScoreRound
        -- and HostResolveTakweesh after their parallel v0.10.5 update.
        -- (beloteOwner hoisted to outer scope per v0.11.13 SU2-02 fix.)
        if c.type == K.BID_HOKM and c.trump then
            local kWho, qWho
            local function scan(p_)
                for _, p in ipairs(p_ or {}) do
                    if C.Suit(p.card) == c.trump then
                        if C.Rank(p.card) == "K" then kWho = kWho or p.seat end
                        if C.Rank(p.card) == "Q" then qWho = qWho or p.seat end
                    end
                end
            end
            for _, t in ipairs(S.s.tricks or {}) do scan(t.plays) end
            if S.s.trick then scan(S.s.trick.plays) end
            if kWho and qWho and kWho == qWho then
                beloteOwner = R.TeamOf(kWho)
                if R.IsBeloteCancelled(beloteOwner, S.s.meldsByTeam) then
                    beloteOwner = nil
                end
                -- v1.0.11 (D HIGH-2): announcement gate (SWA-Qaid path).
                if beloteOwner and S.s.beloteAnnounced
                   and not S.s.beloteAnnounced[kWho]
                   and R.TeamSequenceCoversBelote
                   and not R.TeamSequenceCoversBelote(beloteOwner,
                                                       S.s.meldsByTeam,
                                                       c.trump) then
                    beloteOwner = nil
                end
            end
        end
        -- v1.0.9 D HIGH-1: cards × cardMult, melds × meldMult (cap at
        -- Bel per PDF §5-6). Belote alone is multiplier-immune.
        local rawA = (cardA * cardMult) + (mpA * meldMult)
        local rawB = (cardB * cardMult) + (mpB * meldMult)
        if beloteOwner == "A" then rawA = rawA + K.MELD_BELOTE
        elseif beloteOwner == "B" then rawB = rawB + K.MELD_BELOTE end
        -- v0.5.21 scoring-inconsistency fix: same div10 alignment
        -- as HostResolveTakweesh above (5 rounds UP per video #43).
        addA = math.floor((rawA + 5) / 10)
        addB = math.floor((rawB + 5) / 10)
        contractMade = false
    else
        -- VALID SWA → caller's team takes all remaining trick points.
        -- Build a complete 8-trick history and let R.ScoreRound do
        -- the rest. Synthetic tricks pack remaining cards 4 at a
        -- time; .winner is set to callerSeat for each (ScoreRound
        -- uses .winner directly, not a recomputation).
        local synth = {}
        for _, t in ipairs(S.s.tricks or {}) do
            synth[#synth + 1] = t
        end

        -- Collect "remaining" plays: in-progress trick + every
        -- unplayed card from every hand.
        local remaining = {}
        for _, p in ipairs(trickPlays) do
            remaining[#remaining + 1] = { seat = p.seat, card = p.card }
        end
        for seat = 1, 4 do
            for _, card in ipairs(hands[seat] or {}) do
                remaining[#remaining + 1] = { seat = seat, card = card }
            end
        end

        -- Pack into 4-play tricks, all won by callerSeat. ScoreRound
        -- only reads .leadSuit, .plays, .winner — we don't have to
        -- reproduce the actual play order, just the cards' point
        -- values and the winning team.
        while #synth < 8 and #remaining > 0 do
            local plays = {}
            for j = 1, 4 do
                if #remaining > 0 then
                    plays[j] = table.remove(remaining, 1)
                end
            end
            synth[#synth + 1] = {
                leadSuit = (plays[1] and C.Suit(plays[1].card)) or "S",
                plays = plays,
                winner = callerSeat,
            }
        end
        -- Extreme edge: leftover cards (would only happen in a buggy
        -- state). Append to last trick so they're at least counted
        -- toward caller's team.
        if #remaining > 0 and #synth > 0 then
            local last = synth[#synth]
            for _, p in ipairs(remaining) do
                last.plays[#last.plays + 1] = p
            end
        end

        -- v1.0.9 (PDF Rule 2): pass dealer for tied-meld priority.
        result = R.ScoreRound(synth, c, S.s.meldsByTeam, S.s.dealer,
                               S.s.beloteAnnounced)
        addA = result.final.A
        addB = result.final.B
        sweepTeam = result.sweep
        contractMade = result.bidderMade
    end

    local totA = (S.s.cumulative.A or 0) + addA
    local totB = (S.s.cumulative.B or 0) + addB

    -- v0.11.7 user feedback: stash the caller's encoded hand into
    -- swaResult so the post-resolution banner (renderBanner SWA
    -- branch in PHASE_SCORE) can show the same card row that
    -- renderSWABanner showed during the pending window. Pre-v0.11.7
    -- the cards were only visible during the 5-second pending phase;
    -- once the result resolved ("SWA verified" banner), the cards
    -- vanished — particularly opaque for teammate-bot SWAs where the
    -- player saw "SWA from Bot 3 verified" with no card display.
    local callerEncodedHand
    do
        local pinHand = callerHand or (S.s.hostHands and S.s.hostHands[callerSeat]) or {}
        callerEncodedHand = (C and C.EncodeHand) and C.EncodeHand(pinHand) or nil
    end

    -- v0.11.11 SU-Ultra-01 fix: stash per-team breakdown so the
    -- renderBanner SWA branch can show the same row format the
    -- regular round-end banner does. Pre-v0.11.11 my v0.11.2 fix
    -- claimed to display "<Team>: cards X + melds Y" rows but the
    -- conditional read S.s.lastRoundResult — which this same code
    -- path nils at line 3401 BEFORE renderBanner runs. The
    -- per-team rows have therefore been UNREACHABLE since v0.11.2;
    -- users have only seen the degraded "Claim verified — all
    -- remaining tricks awarded." line. Now we stash the breakdown
    -- on swaResult itself (host-side) so renderBanner can display
    -- it directly. Non-host receivers don't get the breakdown
    -- (would require wire-format extension; deferred — host is the
    -- dominant SWA-observer).
    local breakdown
    if valid and result then
        breakdown = {
            bidderTeam = result.bidderTeam,
            teamPoints = result.teamPoints,
            meldPoints = result.meldPoints,
            multiplier = result.multiplier,
            belote     = result.belote,
        }
    elseif not valid then
        breakdown = {
            bidderTeam = R.TeamOf(c.bidder),
            teamPoints = { A = cardA, B = cardB },
            meldPoints = { A = mpA, B = mpB },
            multiplier = mult,
            belote     = beloteOwner,
        }
    end

    S.s.swaResult = {
        caller       = callerSeat,
        valid        = valid,
        contractMade = contractMade,
        sweep        = sweepTeam,
        encodedHand  = callerEncodedHand,   -- v0.11.7
        breakdown    = breakdown,           -- v0.11.11 SU-Ultra-01
    }
    S.s.lastRoundResult = nil
    S.s.trick = nil
    -- Re-audit W1 + 4th-audit X4 fix: pass sweepTeam + contractMade
    -- through so the BALOOT fanfare fires on host AND on remote
    -- clients (MSG_SWA_OUT now carries the flags too).
    S.ApplyRoundEnd(addA, addB, totA, totB, sweepTeam, contractMade)
    N.SendSWAOut(callerSeat, valid, addA, addB, totA, totB,
                 sweepTeam, contractMade, callerEncodedHand)

    -- v0.10.5 MED-2: shared R.GameEndWinner with SWA-context adapter.
    -- Round-winner team is the caller (valid SWA) or the opp (invalid
    -- SWA). Map to bidderTeam/bidderMade via "round-winner = bidderMade
    -- side" so the H3 tiebreak resolves correctly. Pre-v0.10.5 used raw
    -- bidder-team logic which could award the match to the OFFENDER on
    -- simultaneous-target hits during invalid-SWA Qaid resolution.
    local roundWinnerTeam = valid and callerTeam or oppOfCaller
    local winner = R.GameEndWinner(totA, totB, S.s.target, {
        gahwaWinner = nil,             -- SWA preempts Gahwa scoring
        bidderTeam  = roundWinnerTeam,
        bidderMade  = true,
    })
    if winner then
        S.ApplyGameEnd(winner)
        N.SendGameEnd(winner)
    end
    if B.UI and B.UI.Refresh then B.UI.Refresh() end
end

function N._OnAKA(sender, seat, suit, replayFlag)
    if fromSelf(sender) then return end
    if not seat or seat < 1 or seat > 4 then return end
    if not suit or suit == "" then return end
    -- v0.11.11 NetU-03 fix: enum-validate suit ∈ {S,H,D,C}. Garbage
    -- suits silently pass through to S.ApplyAKA + UI banner, where
    -- K.SUIT_GLYPH lookup yields "?" glyph. Defense-in-depth + UI
    -- consistency.
    if suit ~= "S" and suit ~= "H" and suit ~= "D" and suit ~= "C" then return end
    -- Audit fix: replay bypass — host whispers AKA replay during
    -- resync; sender is host, not the seat owner.
    local isReplay = (replayFlag == "1") and fromHost(sender)
    -- 13th-audit defense: hosts are never the target of a replay frame.
    if isReplay and S.s.isHost then return end
    -- Authority: only the seat itself can call AKA on its own behalf.
    -- Cosmetic protection — a spoofed AKA wouldn't change scoring,
    -- but it would mislead a partner's play decision.
    if not isReplay and not authorizeSeat(seat, sender) then return end
    -- Only meaningful during play; ignore stragglers from a previous
    -- hand that arrive after PHASE_SCORE.
    if S.s.phase ~= K.PHASE_PLAY then return end
    -- AKA is HOKM-only: in Sun there's no trump to over-trump with,
    -- so the call has no tactical meaning. Drop the message rather
    -- than display a confusing banner.
    if not S.s.contract or S.s.contract.type ~= K.BID_HOKM then return end
    -- v0.10.4 E1 wire guard (review_v0.10.2 D-RedTeam-01:29-60,
    -- B-Net-05 F8a, HIGH): trump-suit AKA is meaningless under Saudi
    -- convention (the AKA promise is "I have the boss of a non-trump
    -- suit"). UI hides the AKA button when `cand.suit == trump`, but
    -- a hostile peer can craft `MSG_AKA;<seat>;<trump>` directly on
    -- the wire. If accepted, it would mislead a partner-bot's
    -- pickFollow into suppressing a ruff that should fire — the
    -- canonical AKA-receiver-relief gate (Rules.lua:115-130) treats
    -- trump-led tricks specially but the misframed banner could
    -- still cascade through R.IsLegalPlay's implicit-AKA branch on
    -- a non-trump-led trick. Reject at wire entry.
    if suit == S.s.contract.trump then return end
    -- v0.10.4 E2 wire guard (review_v0.10.2 D-RedTeam-01:63-90,
    -- B-Net-05 F8b, HIGH): mirror the local-side lead-only gate at
    -- N.LocalAKA:2358. AKA must be announced AT lead time (zero
    -- prior plays in the trick); otherwise a hostile peer could
    -- inject MSG_AKA mid-trick to retroactively suppress the bot's
    -- subsequent ruff. Pre-v0.10.4 LocalAKA enforced this client-
    -- side but the wire path didn't, leaving a mispredict window.
    if S.s.trick and S.s.trick.plays and #S.s.trick.plays > 0 then return end
    S.ApplyAKA(seat, suit)
end

-- Resync request (broadcast). Only the host responds, and only if the
-- requester is in our seat roster — otherwise spurious requests from
-- unrelated party members would leak game state.
-- 8th-audit fix: per-sender resync cooldown. Without throttling, a
-- buggy or hostile peer can spam MSG_RESYNC_REQ and force the host
-- to whisper a multi-frame snapshot (snapshot + bidcard + N melds +
-- N tricks + in-flight plays + hand) on every request — saturating
-- the addon channel rate limit and wasting host CPU.
local _resyncCooldown = {}
local RESYNC_COOLDOWN_SEC = 5

function N._OnResyncReq(sender, gameID)
    if fromSelf(sender) then return end
    if not S.s.isHost then return end
    if not gameID or gameID == "" then return end
    if S.s.gameID ~= gameID then return end
    -- 6th-audit fix: normalize the sender before comparing against
    -- the seat roster. WoW addon-channel `sender` arrives with a
    -- "-Realm" suffix on cross-realm groups but the seat names were
    -- stored from GetUnitName which sometimes drops the suffix on
    -- same-realm parties — strict equality misses legitimate
    -- requests, leaving party members soft-locked after a /reload.
    -- Use the same normalization helper that fromSelf / fromHost /
    -- authorizeSeat already share.
    local nsender = normSender(sender)
    -- 8th-audit fix: per-sender cooldown gate. Reject repeated
    -- requests from the same peer within RESYNC_COOLDOWN_SEC so a
    -- spammy / hostile client cannot saturate the addon channel by
    -- forcing the host to re-whisper a 50+ message replay on every
    -- request. Use the normalized sender as the key so realm-suffix
    -- variants don't dodge the cooldown.
    do
        local key = nsender or sender
        local now = (GetTime and GetTime()) or 0
        local last = _resyncCooldown[key] or 0
        if (now - last) < RESYNC_COOLDOWN_SEC then return end
        _resyncCooldown[key] = now
    end
    -- 7th-audit fix: also normalize info.name. The previous fix
    -- normalized `sender` but compared against `info.name` raw. If
    -- the seat roster was populated from a saved-session restore
    -- (where names lacked the realm suffix) and the live sender
    -- arrives with "Name-Realm", strict equality still fails.
    local function nameEq(infoName, target)
        if not infoName or not target then return false end
        if infoName == target then return true end
        local n = (S.NormalizeName and S.NormalizeName(infoName)) or infoName
        return n == target
    end
    local found = false
    for i = 1, 4 do
        local info = S.s.seats[i]
        if info and nameEq(info.name, nsender) then found = true; break end
    end
    if not found then
        log("Warn", "resync from %s rejected (not in roster)", tostring(sender))
        return
    end
    log("Info", "resync to %s for game %s", sender, gameID)
    N.SendResyncRes(sender, gameID)
    -- Also re-whisper their hand. The host knows it from hostHands.
    -- Use the same nameEq helper so the seat lookup matches the
    -- normalized roster gate above.
    local seat
    for i = 1, 4 do
        if S.s.seats[i] and nameEq(S.s.seats[i].name, nsender) then
            seat = i; break
        end
    end
    if seat and S.s.hostHands and S.s.hostHands[seat] then
        N.SendHand(sender, S.s.hostHands[seat])
    end
end

-- Resync response (private whisper from host). Decode the snapshot and
-- hand it to State.ApplyResyncSnapshot which rehydrates the local state
-- without disturbing already-applied later messages.
function N._OnResyncRes(sender, gameID, payload)
    if fromSelf(sender) then return end
    if not gameID or not payload then return end
    -- 11th-audit fix (Codex catch): the active host must NEVER apply
    -- a resync snapshot from another peer — we're authoritative,
    -- not the rejoiner. Without this gate, a stale or buggy peer's
    -- MSG_RESYNC_RES with a matching lastGameID would route through
    -- ApplyResyncSnapshot's now-unconditional `s.isHost = false`
    -- (10th-audit fix) and demote the real host into a soft-locked
    -- non-host state.
    if S.s.isHost then return end
    -- v0.9.1 L5 fix: only accept resync snapshots within a 30-second
    -- window after we explicitly sent MSG_RESYNC_REQ. Pre-v0.9.1, any
    -- peer who knew the gameID (even from passive observation) could
    -- inject score-state. Now: the request flag must be set; one
    -- valid response consumes the flag.
    if not expectingResyncRes then return end
    -- Reject snapshots that don't match the gameID we asked about. A
    -- stale response from a slow host (or a snapshot for a different
    -- game we happened to overhear) shouldn't clobber state if we've
    -- since joined a fresh lobby.
    if WHEREDNGNDB and WHEREDNGNDB.lastGameID
       and WHEREDNGNDB.lastGameID ~= gameID then
        return
    end
    -- Consume the flag so a second/third stale response doesn't
    -- re-clobber. The expiry timer is still armed; cancel it cleanly.
    expectingResyncRes = false
    if resyncResExpiryTimer and resyncResExpiryTimer.Cancel then
        resyncResExpiryTimer:Cancel()
        resyncResExpiryTimer = nil
    end
    -- We don't yet know who the host is on a fresh /reload, so we
    -- trust that the sender claims to be host — but only if the
    -- gameID matches the one we asked about (already verified above
    -- via WHEREDNGNDB.lastGameID). A subsequent SendLobby will
    -- reconfirm. A peer not matching gameID was rejected at the
    -- guard above, so reaching here means either no recorded
    -- gameID (fresh client) or a match.
    --
    -- 4th-audit X9-3 fix: normalize the sender so subsequent
    -- fromHost(...) checks compare against the canonical form
    -- (matches what every other site uses).
    S.s.hostName = (S.NormalizeName and S.NormalizeName(sender)) or sender
    S.ApplyResyncSnapshot(gameID, payload)
end

function N.LocalKawesh()
    if S.s.paused then return end
    if S.s.phase ~= K.PHASE_DEAL1 then return end
    if not S.s.localSeat then return end
    if not C.IsKaweshHand(S.s.hand) then return end  -- can't fake
    -- Print announcement locally (broadcast won't echo it back to _OnKawesh
    -- because of fromSelf guard).
    local info = S.s.seats[S.s.localSeat]
    local nm = (info and info.name and (info.name:match("^([^%-]+)") or info.name)) or "?"
    print(("|cffff8800WHEREDNGN|r %s called Kawesh — hand annulled, redeal."):format(nm))
    broadcast(("%s;%d"):format(K.MSG_KAWESH, S.s.localSeat))
    if S.s.isHost then N.HostHandleKawesh(S.s.localSeat) end
end

function N._OnKawesh(sender, seat)
    if fromSelf(sender) then return end
    if not seat then return end
    -- Re-audit W8 fix: respect S.s.paused. Without this, a remote
    -- Kawesh announcement during a paused game would print + trigger
    -- a redeal banner; the actual deal aborts (the timer body checks
    -- paused) but the UI is left with a stale redeal banner until
    -- the 3.5s auto-clear, and the dealer rotation is silently lost.
    if S.s.paused then return end
    -- Phase: Kawesh is only available during round-1 bidding.
    if S.s.phase ~= K.PHASE_DEAL1 then return end
    -- Authority: sender must own the seat. (Host's HostHandleKawesh
    -- additionally validates the hand from hostHands, so even a passing
    -- authority check here can't fake a Kawesh on a non-qualifying hand.)
    if not authorizeSeat(seat, sender) then return end
    -- Print announcement on every client.
    local info = S.s.seats[seat]
    local nm = (info and info.name and (info.name:match("^([^%-]+)") or info.name)) or "?"
    print(("|cffff8800WHEREDNGN|r %s called Kawesh — hand annulled, redeal."):format(nm))
    if S.s.isHost then N.HostHandleKawesh(seat) end
end

-- ---------------------------------------------------------------------
-- Turn timeout (AFK protection)
--
-- On every SendTurn, host arms a 60s timer (K.TURN_TIMEOUT_SEC). If the
-- target seat doesn't act before it fires, host auto-acts on their
-- behalf:
--   - bid turn   → auto-PASS
--   - play turn  → auto-play lowest legal card by trick rank
-- Cancelled by any genuine action (LocalBid/Play, _OnBid/Play). Bots
-- run via MaybeRunBot's own delays and are not subject to the timeout.
-- ---------------------------------------------------------------------

local turnTimer

function N.CancelTurnTimer()
    if turnTimer then
        turnTimer:Cancel()
        turnTimer = nil
    end
end

-- Local-side AFK pre-warning. Runs on every client (not just the host)
-- so that a real player feels the prompt even though only the host's
-- authoritative timer can actually auto-act for them. Fires 10s before
-- the host would auto-pass / auto-play, with a soft ping + a UI pulse.
local localWarnTimer

-- NOTE: declared up top (forward-decl) so closures in N.LocalBid /
-- N.LocalPlay / N.LocalDouble / N.LocalSkipDouble
-- all bind to the SAME upvalue and see this assignment at runtime.
cancelLocalWarn = function()
    if localWarnTimer then
        localWarnTimer:Cancel()
        localWarnTimer = nil
    end
end
N.CancelLocalWarn = cancelLocalWarn

local function fireLocalWarn()
    B.Sound.Try(K.SND_TURN_PING)
    if B.UI and B.UI.PulseTurn then B.UI.PulseTurn() end
end

-- Arm only if the local player is the one we're actually waiting on.
-- `kind` is "bid" / "play" for normal turns, or "bel" / "triple" /
-- "four" / "gahwa" for the contract decision windows. Each window has
-- a different eligibility rule (seat that's allowed to act).
function N.StartLocalWarn(kind)
    cancelLocalWarn()
    if S.s.paused then return end
    -- v0.9.3 #56 fix (audit_v0.9.0/56_afk_new_phases.md): per-kind
    -- timeout selection. Pre-v0.9.3 the warn used unconditional
    -- TURN_TIMEOUT_SEC=60 → warnAt=50, fine for bid/play turns but
    -- a no-op for the 5-second OVERCALL window (warnAt > timeout).
    -- Now: short-window kinds use their own timeout, and the warn
    -- triggers proportionally early. For OVERCALL (5s) we surface
    -- the warn at 4s (1s before resolve) so a human about to be
    -- timed-out gets an audible/visual cue.
    local timeout
    if kind == "overcall" then
        timeout = K.OVERCALL_TIMEOUT_SEC or 5
    else
        timeout = K.TURN_TIMEOUT_SEC or 60
    end
    -- warnAt: 10s before timeout for long windows; 1s before for
    -- short windows. Clamp negative offsets.
    local warnAt
    if timeout >= 20 then
        warnAt = timeout - 10
    else
        warnAt = math.max(1, timeout - 1)
    end
    if warnAt < 1 then return end

    local mine = false
    if kind == "bid" or kind == "play" then
        mine = (S.s.turn == S.s.localSeat) and (S.s.turnKind == kind)
    elseif kind == "bel" then
        -- v1.0.11 (D MED M1): EITHER defender considers Bel — check
        -- belPending membership instead of hardcoding NextSeat(bidder).
        mine = false
        if S.s.contract and S.s.localSeat and S.s.belPending then
            for _, v in ipairs(S.s.belPending) do
                if v == S.s.localSeat then mine = true; break end
            end
        end
    elseif kind == "triple" then
        -- v0.2.0: Triple is bidder's response to Bel.
        mine = S.s.contract and S.s.localSeat
               and S.s.localSeat == S.s.contract.bidder
    elseif kind == "four" then
        -- v1.0.11 (D MED M1): Four is the SPECIFIC doubler's response
        -- to Triple (the defender who actually Bel'd, not just any
        -- defender). Use contract.doublerSeat with NextSeat fallback.
        local fourSeat = (S.s.contract and S.s.contract.doublerSeat)
                          or (S.s.contract
                              and ((S.s.contract.bidder % 4) + 1))
        mine = S.s.contract and S.s.localSeat
               and S.s.localSeat == fourSeat
    elseif kind == "gahwa" then
        -- Audit fix: Gahwa is the BIDDER's terminal escalation.
        mine = S.s.contract and S.s.localSeat
               and S.s.localSeat == S.s.contract.bidder
    elseif kind == "preempt" then
        -- Re-audit W6 fix: pre-emption window has multiple eligible
        -- seats; check membership in S.s.preemptEligible.
        if S.s.localSeat and S.s.preemptEligible then
            for _, eseat in ipairs(S.s.preemptEligible) do
                if eseat == S.s.localSeat then mine = true; break end
            end
        end
    elseif kind == "overcall" then
        -- v0.7 Sun-overcall: any seat that R.CanOvercall says can act
        -- (i.e., all 4 seats unless forced/Sun contract; bidder is
        -- only blocked from UPGRADE — they can still WAIVE; the warn
        -- fires for the local seat regardless of choice).
        if S.s.localSeat and S.s.contract and S.s.overcall
           and R.CanOvercall(S.s.localSeat, S.s.contract,
                              S.s.overcall.bidCard) then
            mine = true
        end
    end
    if not mine then return end

    localWarnTimer = C_Timer.NewTimer(warnAt, fireLocalWarn)
end

function N.StartTurnTimer(seat, kind)
    N.CancelTurnTimer()
    if not S.s.isHost then return end
    if S.s.paused then return end
    if not seat then return end
    local info = S.s.seats[seat]
    if not info or info.isBot then return end
    turnTimer = C_Timer.NewTimer(K.TURN_TIMEOUT_SEC, function()
        N._HostTurnTimeout(seat, kind)
    end)
end

function N._HostTurnTimeout(seat, kind)
    if not S.s.isHost then return end
    -- Re-audit W13 fix: respect S.s.paused. C_Timer:Cancel() doesn't
    -- catch a callback already queued for this frame, so a pause
    -- applied between fire and execution would otherwise let the
    -- auto-action run mid-pause.
    if S.s.paused then return end
    -- 8th-audit fix: also defer when an SWA permission request is in
    -- flight. The SWA caller's turn is locked behind voting, so the
    -- 60s AFK auto-pass would forcibly play their hand under them.
    -- _OnSWAResp re-arms the turn timer when the request resolves.
    if S.s.swaRequest and S.s.swaRequest.caller then return end
    if S.s.turn ~= seat or S.s.turnKind ~= kind then return end
    log("Info", "AFK timeout for seat %d kind=%s", seat, tostring(kind))
    if kind == "bid" then
        if S.s.bids[seat] ~= nil then return end
        S.ApplyBid(seat, K.BID_PASS)
        N.SendBid(seat, K.BID_PASS)
        N._HostStepBid()
    elseif kind == "play" then
        local hand = S.s.hostHands and S.s.hostHands[seat]
        if not hand or not S.s.contract then return end
        local legal = {}
        for _, c in ipairs(hand) do
            if R.IsLegalPlay(c, hand, S.s.trick, S.s.contract, seat, S.s.akaCalled) then
                legal[#legal + 1] = c
            end
        end
        if #legal == 0 then return end
        local best, bestRank = legal[1], math.huge
        for _, c in ipairs(legal) do
            local r = C.TrickRank(c, S.s.contract)
            if r < bestRank then best, bestRank = c, r end
        end
        -- 50-agent playtest audit fix: AFK auto-play during trick 1
        -- previously skipped meld declaration entirely. The Saudi
        -- meld window closes after trick 1 (`#s.tricks >= 1` gate in
        -- S.GetMeldsForLocal / ApplyMeld / Bot.PickMelds), so a human
        -- AFK'd through trick 1 silently forfeited their melds — a
        -- 50-point Quarte just disappears. Mirror MaybeRunBot's auto-
        -- declare logic at Net.lua:3454-3461: if the AFK'd seat hasn't
        -- declared yet, run the meld picker on their behalf and stamp
        -- meldsDeclared[seat]=true. The picker itself respects the
        -- trick-1 gate and returns {} after trick 1, so this is a
        -- no-op outside the meld window.
        if S.s.meldsDeclared and not S.s.meldsDeclared[seat] then
            local melds = (B.Bot and B.Bot.PickMelds and B.Bot.PickMelds(seat)) or {}
            for _, m in ipairs(melds) do
                S.ApplyMeld(seat, m.kind, m.suit, m.top,
                    C.EncodeHand(m.cards or {}))
                N.SendMeld(seat, m)
            end
            S.s.meldsDeclared[seat] = true
        end
        -- Audit C-1: AFK auto-play needs to feed Bot.OnPlayObserved
        -- like the regular dispatch path, otherwise void inference and
        -- firstDiscard miss the AFK seat for the rest of the round.
        local leadBefore = S.s.trick and S.s.trick.leadSuit or nil
        S.ApplyPlay(seat, best)
        if B.Bot and B.Bot.OnPlayObserved then
            B.Bot.OnPlayObserved(seat, best, leadBefore)
        end
        N.SendPlay(seat, best)
        N._HostStepPlay()
    end
    if B.UI and B.UI.Refresh then B.UI.Refresh() end
end

-- Escalation windows (Bel/Triple/Four/Gahwa/Pre-empt) have no turn
-- pointer (s.turn stays nil), so the standard AFK turn timer can't
-- cover them. We arm a dedicated timer that auto-skips after
-- K.TURN_TIMEOUT_SEC. Reuses turnTimer because only one window can
-- be active at a time.
function N.StartBelTimer(seat, kind)
    N.CancelTurnTimer()
    if not S.s.isHost then return end
    if S.s.paused then return end
    if not seat then return end
    local info = S.s.seats[seat]
    if not info or info.isBot then return end
    turnTimer = C_Timer.NewTimer(K.TURN_TIMEOUT_SEC, function()
        N._HostBelTimeout(seat, kind)
    end)
end

function N._HostBelTimeout(seat, kind)
    if not S.s.isHost or not S.s.contract then return end
    -- Re-audit W13 fix: respect pause same as _HostTurnTimeout.
    if S.s.paused then return end
    if kind == "double" and S.s.phase == K.PHASE_DOUBLE then
        log("Info", "AFK timeout: bel skip seat=%d", seat)
        broadcast(("%s;%d"):format(K.MSG_SKIP_DBL, seat))
        -- v1.0.11 (D MED M1): mutate belPending locally; finish only
        -- when all defenders have decided.
        local newPending = {}
        for _, v in ipairs(S.s.belPending or {}) do
            if v ~= seat then newPending[#newPending + 1] = v end
        end
        S.s.belPending = newPending
        if #newPending == 0 then
            N.HostFinishDeal()
        else
            N.MaybeRunBot()
        end
    elseif kind == "triple" and S.s.phase == K.PHASE_TRIPLE then
        log("Info", "AFK timeout: triple skip seat=%d", seat)
        broadcast(("%s;%d"):format(K.MSG_SKIP_TRP, seat))
        N.HostFinishDeal()
    elseif kind == "four" and S.s.phase == K.PHASE_FOUR then
        log("Info", "AFK timeout: four skip seat=%d", seat)
        broadcast(("%s;%d"):format(K.MSG_SKIP_FOR, seat))
        N.HostFinishDeal()
    elseif kind == "gahwa" and S.s.phase == K.PHASE_GAHWA then
        log("Info", "AFK timeout: gahwa skip seat=%d", seat)
        broadcast(("%s;%d"):format(K.MSG_SKIP_GHW, seat))
        N.HostFinishDeal()
    elseif kind == "preempt_pass" and S.s.phase == K.PHASE_PREEMPT then
        -- Pre-emption window timed out for an eligible seat — auto-pass
        -- on their behalf. May either close the window (if last seat)
        -- or hand off to the next eligible seat.
        log("Info", "AFK timeout: preempt waive seat=%d", seat)
        broadcast(("%s;%d"):format(K.MSG_PREEMPT_PASS, seat))
        S.ApplyPreemptPass(seat)
        if not S.s.preemptEligible then
            N._FinalizePreempt()
        else
            -- Non-final timeout: redispatch next eligible seat.
            N.MaybeRunBot()
        end
    end
    if B.UI and B.UI.Refresh then B.UI.Refresh() end
end

function N.HostHandleKawesh(seat)
    if not S.s.isHost then return end
    -- Re-audit W8 fix: don't process Kawesh while paused. _HostRedeal
    -- arms a 3-second timer; if pause was applied between the
    -- announcement and this handler, the timer body would still try
    -- to deal cards into a paused state.
    if S.s.paused then return end
    if S.s.phase ~= K.PHASE_DEAL1 then return end
    -- Validate: only the caller's seat can prove the hand from hostHands
    if S.s.hostHands and S.s.hostHands[seat] then
        if not C.IsKaweshHand(S.s.hostHands[seat]) then
            log("Warn", "kawesh rejected: seat %d hand isn't all 7/8/9", seat)
            return
        end
    end
    -- _HostRedeal advances the dealer itself; do NOT pre-rotate here
    -- or we'd skip a seat (was a bug — rotated twice).
    N._HostRedeal("kawesh")
end

-- ---------------------------------------------------------------------
-- Bot driver: when it's a bot's turn, schedule its action with a small
-- delay so humans can read the table. Chains: each bot action triggers
-- another MaybeRunBot at the end so consecutive bot turns flow.
--
-- Cancellation: each timer re-checks state before acting (turn / phase
-- still match what was scheduled). If a human acted in between or the
-- round was reset, the timer returns silently.
-- ---------------------------------------------------------------------

-- Bot pacing. The bid voice cue (~0.6s for the Saud "بَسْ"/"حكم"/etc)
-- has to finish before the next bot acts, otherwise rapid all-pass
-- rounds produce a "passpasspass" run that doesn't line up with the
-- visual turn pointer. 1.6s gives the announcement room to breathe.
local BOT_DELAY_BID  = 1.6
local BOT_DELAY_PLAY = 1.2
local BOT_DELAY_BEL  = 1.4   -- Bel/Triple/Four/Gahwa also have voice cues

local function isBotSeat(seat)
    return S.s.isHost and seat and S.s.seats[seat] and S.s.seats[seat].isBot
end

function N.MaybeRunBot()
    if not S.s.isHost then return end
    if not B.Bot then return end
    if S.s.paused then return end
    -- 7th-audit fix: also pause bot dispatch while a SWA permission
    -- request is in flight. Otherwise a bot whose play turn arrives
    -- DURING the human's voting window plays a card, advancing the
    -- trick state under the SWA caller — when the request finally
    -- resolves, IsValidSWA validates against the caller's encoded
    -- pre-play hand but the trick history has moved on.
    if S.s.swaRequest and S.s.swaRequest.caller then return end

    -- Phase-driven dispatch first. After ApplyContract, s.turn still
    -- points at the last bidder (and turnKind is still "bid"), so the
    -- old turn-first dispatch would erroneously schedule a bid timer
    -- for that seat and miss the bel-decision branch entirely. The
    -- contract phases (DOUBLE/REDOUBLE) take precedence.

    -- v0.7 Sun-overcall: decisions for bot seats are recorded
    -- synchronously by N._HostBeginOvercallWindow at window-open time,
    -- so we don't need (or want) MaybeRunBot to do any further work
    -- during PHASE_OVERCALL. The 5s timeout (or all-decided early
    -- close) calls N._HostResolveOvercall, which then re-invokes
    -- N.MaybeRunBot once the contract is finalized and we transition
    -- to PHASE_DOUBLE. Returning here prevents the stale-turn fallback
    -- branch below from spuriously firing during the window.
    if S.s.phase == K.PHASE_OVERCALL then return end

    -- v1.0.11 (D MED M1 either-defender Bel): dispatch ALL pending
    -- defenders in NextSeat-first order. Pre-v1.0.11 only NextSeat
    -- (bidder) was eligible; both defenders are now in S.s.belPending.
    -- Sequence: ask each bot defender PickDouble (NextSeat first per
    -- Saudi vocal-priority convention). First bot to say YES Bels and
    -- the chain advances. Bots that say NO emit MSG_SKIP_DBL and are
    -- removed from belPending. Remaining humans get a sequential AFK
    -- timer (re-armed via MaybeRunBot recursion when one of them skips).
    if S.s.phase == K.PHASE_DOUBLE and S.s.contract then
        local pending = S.s.belPending or {}
        if #pending == 0 then
            -- Defensive: no eligible defenders (shouldn't happen post-
            -- ApplyContract). Advance to play.
            N.HostFinishDeal()
            return
        end
        -- Build seat order: NextSeat(bidder) first, then PrevSeat(bidder).
        local nextSeat = (S.s.contract.bidder % 4) + 1
        local prevSeat = ((S.s.contract.bidder + 2) % 4) + 1
        local function inPending(seat)
            for _, v in ipairs(pending) do if v == seat then return true end end
            return false
        end
        local order = {}
        if inPending(nextSeat) then order[#order + 1] = nextSeat end
        if inPending(prevSeat) then order[#order + 1] = prevSeat end

        -- First non-bot defender (if any) — needs an AFK timer if no
        -- bot Bels first. Loop processes bots; humans accumulate.
        local firstHuman
        local botSkips = {}
        local belFired = false
        for _, belSeat in ipairs(order) do
            if isBotSeat(belSeat) then
                log("Info", "schedule bel-decision for bot seat=%d", belSeat)
                local bel, wantOpen = B.Bot.PickDouble(belSeat)
                log("Info", "bel-decision seat=%d pick=%s open=%s",
                    belSeat, tostring(bel), tostring(wantOpen))
                if bel then
                    local isSun = S.s.contract
                              and S.s.contract.type == K.BID_SUN
                    local effOpen = (not isSun) and wantOpen
                    S.ApplyDouble(belSeat, effOpen)
                    N.SendDouble(belSeat, effOpen)
                    belFired = true
                    if isSun or not effOpen then
                        N.HostFinishDeal()
                    else
                        N.MaybeRunBot()
                    end
                    return
                else
                    botSkips[#botSkips + 1] = belSeat
                end
            else
                firstHuman = firstHuman or belSeat
            end
        end
        -- No bot Bel'd. Broadcast skips for the bots and update
        -- belPending to drop them.
        for _, seat in ipairs(botSkips) do
            broadcast(("%s;%d"):format(K.MSG_SKIP_DBL, seat))
        end
        if #botSkips > 0 then
            local newPending = {}
            for _, seat in ipairs(pending) do
                local skipped = false
                for _, ss in ipairs(botSkips) do
                    if seat == ss then skipped = true; break end
                end
                if not skipped then newPending[#newPending + 1] = seat end
            end
            S.s.belPending = newPending
            pending = newPending
        end
        if #pending == 0 then
            N.HostFinishDeal()
        else
            -- Humans remain — arm AFK for the first, in NextSeat order.
            local timerSeat = inPending(nextSeat) and nextSeat or prevSeat
            N.StartBelTimer(timerSeat, "double")
        end
        return
    end

    -- v0.2.0: Triple decision is the BIDDER's response to Bel.
    -- Each escalation now picks (yes, wantOpen) — wantOpen=true means
    -- the chain may continue with the opposing team's next-rung
    -- counter; wantOpen=false closes the chain and goes straight to PLAY.
    if S.s.phase == K.PHASE_TRIPLE and S.s.contract then
        local bidder = S.s.contract.bidder
        if isBotSeat(bidder) then
            C_Timer.After(BOT_DELAY_BEL, function()
                local applied, skipSent = false, false
                local ok, err = pcall(function()
                    if S.s.paused then return end
                    if S.s.phase ~= K.PHASE_TRIPLE then return end
                    local yes, wantOpen = false, true
                    if B.Bot.PickTriple then
                        yes, wantOpen = B.Bot.PickTriple(bidder)
                    end
                    if yes then
                        S.ApplyTriple(bidder, wantOpen)
                        applied = true
                        N.SendTriple(bidder, wantOpen)
                        if wantOpen then N.MaybeRunBot() else N.HostFinishDeal() end
                    else
                        broadcast(("%s;%d"):format(K.MSG_SKIP_TRP, bidder))
                        skipSent = true
                        N.HostFinishDeal()
                    end
                end)
                if not ok then
                    log("Error", "triple-decision callback failed: %s", tostring(err))
                    if applied then
                        -- After ApplyTriple, phase is PHASE_FOUR (open)
                        -- or PHASE_PLAY (closed). For open: must run
                        -- defenders' Four decision via MaybeRunBot.
                        if S.s.phase == K.PHASE_PLAY then
                            N.HostFinishDeal()
                        else
                            N.MaybeRunBot()
                        end
                    elseif skipSent then
                        N.HostFinishDeal()
                    elseif S.s.phase == K.PHASE_TRIPLE then
                        broadcast(("%s;%d"):format(K.MSG_SKIP_TRP, bidder))
                        N.HostFinishDeal()
                    end
                end
                if B.UI then B.UI.Refresh() end
            end)
            return
        else
            N.StartBelTimer(bidder, "triple")
            return
        end
    end

    -- v0.2.0: Four decision is the DEFENDER's response to Triple.
    -- v1.0.11 (D MED M1): SPECIFIC doubler seat, not generic NextSeat.
    if S.s.phase == K.PHASE_FOUR and S.s.contract then
        local defSeat = S.s.contract.doublerSeat
                         or ((S.s.contract.bidder % 4) + 1)
        if isBotSeat(defSeat) then
            C_Timer.After(BOT_DELAY_BEL, function()
                local applied, skipSent = false, false
                local ok, err = pcall(function()
                    if S.s.paused then return end
                    if S.s.phase ~= K.PHASE_FOUR then return end
                    local yes, wantOpen = false, true
                    if B.Bot.PickFour then
                        yes, wantOpen = B.Bot.PickFour(defSeat)
                    end
                    if yes then
                        S.ApplyFour(defSeat, wantOpen)
                        applied = true
                        N.SendFour(defSeat, wantOpen)
                        if wantOpen then N.MaybeRunBot() else N.HostFinishDeal() end
                    else
                        broadcast(("%s;%d"):format(K.MSG_SKIP_FOR, defSeat))
                        skipSent = true
                        N.HostFinishDeal()
                    end
                end)
                if not ok then
                    log("Error", "four-decision callback failed: %s", tostring(err))
                    if applied then
                        -- After ApplyFour, phase is PHASE_GAHWA (open)
                        -- or PHASE_PLAY (closed). For open: must run
                        -- bidder's Gahwa decision via MaybeRunBot.
                        if S.s.phase == K.PHASE_PLAY then
                            N.HostFinishDeal()
                        else
                            N.MaybeRunBot()
                        end
                    elseif skipSent then
                        N.HostFinishDeal()
                    elseif S.s.phase == K.PHASE_FOUR then
                        broadcast(("%s;%d"):format(K.MSG_SKIP_FOR, defSeat))
                        N.HostFinishDeal()
                    end
                end
                if B.UI then B.UI.Refresh() end
            end)
            return
        else
            N.StartBelTimer(defSeat, "four")
            return
        end
    end

    -- v0.2.0: Gahwa decision is the BIDDER's terminal (match-win).
    if S.s.phase == K.PHASE_GAHWA and S.s.contract then
        local bidder = S.s.contract.bidder
        if isBotSeat(bidder) then
            C_Timer.After(BOT_DELAY_BEL, function()
                local applied, skipSent = false, false
                local ok, err = pcall(function()
                    if S.s.paused then return end
                    if S.s.phase ~= K.PHASE_GAHWA then return end
                    local yes = false
                    if B.Bot.PickGahwa then
                        yes = B.Bot.PickGahwa(bidder)
                    end
                    if yes then
                        S.ApplyGahwa(bidder)
                        applied = true
                        N.SendGahwa(bidder)
                    else
                        broadcast(("%s;%d"):format(K.MSG_SKIP_GHW, bidder))
                        skipSent = true
                    end
                    N.HostFinishDeal()
                end)
                if not ok then
                    log("Error", "gahwa-decision callback failed: %s", tostring(err))
                    -- Gahwa doesn't advance phase by itself; HostFinishDeal
                    -- always advances to PLAY. Recovery just pushes
                    -- forward. No double-skip because skipSent is tracked.
                    if applied or skipSent then
                        N.HostFinishDeal()
                    elseif S.s.phase == K.PHASE_GAHWA then
                        broadcast(("%s;%d"):format(K.MSG_SKIP_GHW, bidder))
                        N.HostFinishDeal()
                    end
                end
                if B.UI then B.UI.Refresh() end
            end)
            return
        else
            N.StartBelTimer(bidder, "gahwa")
            return
        end
    end

    -- Pre-emption window: each eligible seat (bot or human) decides
    -- whether to claim. Bots use Bot.PickPreempt (Sun-strength gated).
    -- Humans get a UI button + AFK auto-pass.
    if S.s.phase == K.PHASE_PREEMPT and S.s.preemptEligible then
        for _, seat in ipairs(S.s.preemptEligible) do
            if isBotSeat(seat) then
                C_Timer.After(BOT_DELAY_BEL, function()
                    -- Re-re-audit X1 fix: track per-step flags so the
                    -- recovery branch knows what already happened and
                    -- doesn't double-emit / contradict earlier sends.
                    --   claimSent — N.SendPreempt fired (claim path)
                    --   claimApplied — S.ApplyPreempt + ApplyContract done
                    --   passSent  — N.SendPreemptPass fired (pass path)
                    --   passApplied — S.ApplyPreemptPass done
                    local claimSent, claimApplied = false, false
                    local passSent,  passApplied  = false, false
                    local ok, err = pcall(function()
                        if S.s.paused then return end
                        if S.s.phase ~= K.PHASE_PREEMPT then return end
                        -- Re-check eligibility (another bot may have
                        -- claimed in the meantime).
                        if not S.s.preemptEligible then return end
                        local stillEligible = false
                        for _, s2 in ipairs(S.s.preemptEligible) do
                            if s2 == seat then stillEligible = true; break end
                        end
                        if not stillEligible then return end
                        if B.Bot.PickPreempt and B.Bot.PickPreempt(seat) then
                            N.SendPreempt(seat)
                            claimSent = true
                            -- Re-audit W5 fix: apply locally + run the
                            -- host-side post-apply directly. _OnPreempt
                            -- short-circuits on fromSelf and would never
                            -- reach authorizeSeat for a bot's claim.
                            S.ApplyPreempt(seat)
                            if S.s.isHost then
                                S.s.pendingPreemptContract = nil
                                S.ApplyContract(seat, K.BID_SUN, nil)
                                N.SendContract(seat, K.BID_SUN, "")
                                claimApplied = true
                                -- 14th-audit fix: Sun Bel restricted.
                                if not N._SunBelAllowed(seat) then
                                    S.s.belPending = nil
                                    N.HostFinishDeal()
                                else
                                    N.MaybeRunBot()
                                end
                            else
                                claimApplied = true
                            end
                        else
                            N.SendPreemptPass(seat)
                            passSent = true
                            S.ApplyPreemptPass(seat)
                            passApplied = true
                            if not S.s.preemptEligible then
                                N._FinalizePreempt()
                            else
                                N.MaybeRunBot()
                            end
                        end
                    end)
                    if not ok then
                        log("Error", "preempt-decision callback failed: %s", tostring(err))
                        -- 4th-audit X1 fix: branch on what already ran.
                        if claimApplied then
                            -- Claim fully landed (state + contract +
                            -- broadcast); error was downstream. Just
                            -- push the deal forward (or run next bot).
                            if S.s.isHost and S.s.phase == K.PHASE_PREEMPT then
                                -- Defensive: if phase wasn't advanced
                                -- (shouldn't happen post-ApplyContract),
                                -- finalize directly.
                                S.s.preemptEligible = nil
                                N.HostFinishDeal()
                            else
                                N.MaybeRunBot()
                            end
                        elseif claimSent then
                            -- Claim broadcast went out but ApplyPreempt
                            -- / ApplyContract didn't complete. Apply
                            -- now to match what peers think happened.
                            S.ApplyPreempt(seat)
                            if S.s.isHost then
                                S.s.pendingPreemptContract = nil
                                S.ApplyContract(seat, K.BID_SUN, nil)
                                N.SendContract(seat, K.BID_SUN, "")
                                N.HostFinishDeal()
                            end
                        elseif passApplied then
                            -- Pass fully landed; downstream finalize/
                            -- MaybeRunBot errored. Re-attempt the chain
                            -- advance without re-emitting the pass.
                            if not S.s.preemptEligible then
                                N._FinalizePreempt()
                            else
                                N.MaybeRunBot()
                            end
                        elseif passSent then
                            -- Pass broadcast went out but ApplyPreemptPass
                            -- didn't run; mirror it and continue.
                            S.ApplyPreemptPass(seat)
                            if not S.s.preemptEligible then
                                N._FinalizePreempt()
                            else
                                N.MaybeRunBot()
                            end
                        elseif S.s.phase == K.PHASE_PREEMPT then
                            -- Nothing applied or sent; default to pass.
                            N.SendPreemptPass(seat)
                            S.ApplyPreemptPass(seat)
                            if not S.s.preemptEligible then
                                N._FinalizePreempt()
                            else
                                N.MaybeRunBot()
                            end
                        end
                    end
                    if B.UI then B.UI.Refresh() end
                end)
                return
            else
                -- Human eligible. Arm an AFK auto-pass timer.
                N.StartBelTimer(seat, "preempt_pass")
                return
            end
        end
    end

    -- Turn-based dispatch — gated on phase so a stale turn pointer
    -- from a previous phase can't trigger a bot action in an unrelated
    -- state (e.g. phase=SCORE/GAME_END/LOBBY with leftover turn).

    -- Bidding: bot's turn to bid
    if (S.s.phase == K.PHASE_DEAL1 or S.s.phase == K.PHASE_DEAL2BID)
       and S.s.turn and S.s.turnKind == "bid" and isBotSeat(S.s.turn) then
        local seat = S.s.turn
        C_Timer.After(BOT_DELAY_BID, function()
            -- Audit fix: pcall to prevent a Bot.PickBid error from
            -- freezing the bid loop. Recovery: force-pass.
            local ok, err = pcall(function()
                if not S.s.isHost then return end
                if S.s.paused then return end
                if S.s.phase ~= K.PHASE_DEAL1 and S.s.phase ~= K.PHASE_DEAL2BID then return end
                if S.s.turn ~= seat or S.s.turnKind ~= "bid" then return end
                if S.s.bids[seat] ~= nil then return end
                -- 13th-bot-audit fix: Kawesh check before bidding.
                -- If the bot's hand is 5+ cards of {7,8,9}, call
                -- Kawesh to annul the deal — the hand is unwinnable.
                -- Humans had this option via UI; bots didn't. Match
                -- the LocalKawesh wire path so receivers see the
                -- announcement correctly.
                if S.s.phase == K.PHASE_DEAL1
                   and B.Bot.PickKawesh and B.Bot.PickKawesh(seat) then
                    local info = S.s.seats[seat]
                    local nm = (info and info.name
                                and (info.name:match("^([^%-]+)") or info.name))
                                or "?"
                    print(("|cffff8800WHEREDNGN|r %s called Kawesh — hand annulled, redeal."):format(nm))
                    broadcast(("%s;%d"):format(K.MSG_KAWESH, seat))
                    N.HostHandleKawesh(seat)
                    return
                end
                local bid = B.Bot.PickBid(seat)
                S.ApplyBid(seat, bid)
                N.SendBid(seat, bid)
                N._HostStepBid()
            end)
            if not ok then
                log("Error", "bid-decision callback failed: %s", tostring(err))
                -- Recovery: force-pass so the bid loop advances. Same
                -- shape as the AFK-timeout auto-pass for human seats.
                if S.s.turn == seat and S.s.turnKind == "bid"
                   and S.s.bids and S.s.bids[seat] == nil then
                    S.ApplyBid(seat, K.BID_PASS)
                    N.SendBid(seat, K.BID_PASS)
                    N._HostStepBid()
                end
            end
            if B.UI then B.UI.Refresh() end
        end)
        return
    end

    -- Playing: bot's turn to play (and possibly declare melds first)
    if S.s.phase == K.PHASE_PLAY
       and S.s.turn and S.s.turnKind == "play" and isBotSeat(S.s.turn) then
        local seat = S.s.turn
        C_Timer.After(BOT_DELAY_PLAY, function()
            -- Audit fix: pcall the play body. A Bot.PickPlay /
            -- BotMaster.PickPlay / PickMelds error otherwise leaves
            -- the bot's turn permanently — bots have no AFK timer
            -- (StartTurnTimer skips bot seats). Recovery: pick the
            -- lowest-rank legal play, mirroring _HostTurnTimeout.
            local ok, err = pcall(function()
                if not S.s.isHost then return end
                if S.s.paused then return end
                if S.s.phase ~= K.PHASE_PLAY then return end
                if S.s.turn ~= seat or S.s.turnKind ~= "play" then return end
                -- 8th-audit fix: re-check swaRequest at fire time.
                -- MaybeRunBot's entry guard catches the SWA-pending case
                -- when DISPATCHING, but a play timer that was already
                -- in flight when a human called SWA would otherwise
                -- still call ApplyPlay, advancing the trick state under
                -- the SWA caller. When the request finally resolves,
                -- IsValidSWA validates against the encoded pre-play
                -- hand vs. trick history that has since moved on.
                if S.s.swaRequest and S.s.swaRequest.caller then return end
                -- Takweesh check before the play. A bot scans for an
                -- opponent illegal play and rolls per-trick probability.
                -- If it decides to call, the round resolves immediately
                -- and we never schedule the play.
                if B.Bot.PickTakweesh and B.Bot.PickTakweesh(seat) then
                    broadcast(("%s;%d"):format(K.MSG_TAKWEESH, seat))
                    N.HostResolveTakweesh(seat)
                    return
                end
                -- v0.5.1 C-2: bot-initiated SWA. If the bot holds an
                -- unbeatable position (R.IsValidSWA returns true on
                -- the recursive minimax), claim the rest. Saudi rule:
                -- ≤3 cards = instant claim; 4+ = permission flow with
                -- the existing 5-sec auto-approve timer (v0.4.6). This
                -- branch fires before PickMelds + PickPlay so the bot
                -- short-circuits the trick when it can win them all.
                if B.Bot.PickSWA and B.Bot.PickSWA(seat) then
                    local hand = (S.s.hostHands and S.s.hostHands[seat]) or {}
                    local enc = C.EncodeHand(hand)
                    local handCount = #hand
                    -- v0.5.17 SWA card-display fix: previously the
                    -- ≤3-card "instant claim" branch resolved the SWA
                    -- without setting `swaRequest` — so the UI banner
                    -- (which only renders when swaRequest is non-nil)
                    -- never displayed the caller's cards. Per the
                    -- user's "in every scenario" requirement, ALL
                    -- SWA flows now go through the 5-second display
                    -- window. The opponent-team bot auto-accept still
                    -- fires for ≤3-card claims (no real permission
                    -- needed since opps can't Takweesh — there's no
                    -- defensive position with so few cards), but the
                    -- timer ensures the banner+cards are visible
                    -- before HostResolveSWA closes the round.
                    if C_Timer and C_Timer.After then
                        S.s.swaRequest = {
                            caller    = seat,
                            handCount = handCount,
                            responses = {},
                            encodedHand = enc,
                            ts        = (GetTime and GetTime()) or 0,
                            windowSec = K.SWA_TIMEOUT_SEC or 5,
                        }
                        broadcast(("%s;%d;%s"):format(K.MSG_SWA_REQ, seat, enc))
                        -- Auto-vote opponent bots (mirrors _OnSWAReq).
                        -- v0.11.16 audit H1: PickSWAResponse can deny
                        -- clearly-invalid SWAs (bot-fired SWAs are
                        -- self-validated already, so denials here are
                        -- rare — but symmetric with the human-caller
                        -- path so a buggy bot SWA gets defensive deny).
                        local callerTeam = R.TeamOf(seat)
                        for s2 = 1, 4 do
                            local info = S.s.seats[s2]
                            if info and info.isBot and R.TeamOf(s2) ~= callerTeam then
                                local accept = true
                                if B.Bot and B.Bot.PickSWAResponse then
                                    local ok, decided = pcall(B.Bot.PickSWAResponse, s2, seat, enc)
                                    if ok and decided == false then accept = false end
                                end
                                N._OnSWAResp("__host__", s2, accept, seat)
                            end
                        end
                        -- v0.10.3 SWA pause re-arm (review_v0.10.2
                        -- E-Net-01, HIGH). Pre-v0.10.3 the bot-fired
                        -- SWA timer bare-exited on `S.s.paused` with
                        -- NO re-arm — one pause inside the 5-sec
                        -- window soft-locked the SWA banner forever
                        -- (no second timer ever fires; HostResolveSWA
                        -- never runs; swaRequest stays non-nil through
                        -- the rest of the round). Pattern mirrors the
                        -- OVERCALL_TIMEOUT_SEC fix at line ~1195: a
                        -- named function re-arms ITSELF when paused,
                        -- so multi-cycle pause-toggles within one
                        -- window all resolve eventually. Each re-arm
                        -- is a fresh full SWA_TIMEOUT_SEC window from
                        -- resume — humans get a clean shot to deny.
                        local function botSWAResolveFn()
                            if not S.s.isHost then return end
                            if S.s.paused then
                                local req2 = S.s.swaRequest
                                if req2 and req2.caller == seat then
                                    req2.ts = (GetTime and GetTime()) or req2.ts
                                    if C_Timer and C_Timer.After then
                                        C_Timer.After(K.SWA_TIMEOUT_SEC or 5,
                                                      botSWAResolveFn)
                                    end
                                end
                                return
                            end
                            local req = S.s.swaRequest
                            if not req or req.caller ~= seat then return end
                            if S.s.phase ~= K.PHASE_PLAY then return end
                            S.s.swaRequest = nil
                            N.HostResolveSWA(seat, hand)
                        end
                        C_Timer.After(K.SWA_TIMEOUT_SEC or 5, botSWAResolveFn)
                    else
                        -- C_Timer unavailable: degrade to instant claim
                        -- rather than stall the round (test harness path).
                        broadcast(("%s;%d;%s"):format(K.MSG_SWA, seat, enc))
                        N.HostResolveSWA(seat, hand)
                    end
                    return
                end
                if not S.s.meldsDeclared[seat] then
                    local melds = B.Bot.PickMelds(seat)
                    for _, m in ipairs(melds) do
                        S.ApplyMeld(seat, m.kind, m.suit, m.top, C.EncodeHand(m.cards or {}))
                        N.SendMeld(seat, m)
                    end
                    S.s.meldsDeclared[seat] = true
                end
                -- Saudi Master tier picks via determinization sampling
                -- v0.5.2: Bot.PickPlay now delegates to BotMaster.PickPlay
                -- internally (C-1 fix in v0.5.0), so the previous explicit
                -- call here was redundant — and worse, would cause double
                -- ISMCTS computation if BotMaster.PickPlay returned nil
                -- and Bot.PickPlay then re-delegated. Single call is now
                -- canonical; tier dispatch happens in Bot.PickPlay.
                local card = B.Bot.PickPlay(seat)
                if not card then return end
                -- Advanced bot: if we're leading and the chosen lead card
                -- IS the AKA (highest unplayed) of a non-trump suit, fire
                -- the partner-coordination signal BEFORE the actual card.
                if B.Bot.PickAKA then
                    local akaSuit = B.Bot.PickAKA(seat, card)
                    if akaSuit then
                        S.ApplyAKA(seat, akaSuit)
                        N.SendAKA(seat, akaSuit)
                    elseif B.Bot.PickAKANoise then
                        -- v1.2.2 (HIGH-1 audit fix): noise-AKA emission
                        -- wiring. v1.2.1 introduced Bot.PickAKANoise
                        -- but never called it — the documented "~3%
                        -- noise-AKA on second-highest" feature was
                        -- structurally undelivered. Now: when the
                        -- real AKA path returns nil (we don't hold
                        -- the boss, OR the withhold roll fired), give
                        -- PickAKANoise a chance to emit a deceptive
                        -- AKA on K/Q where we DON'T hold the suit's A.
                        -- Saudi-Master tier only, ~3% probability.
                        local noiseSuit = B.Bot.PickAKANoise(seat, card)
                        if noiseSuit then
                            S.ApplyAKA(seat, noiseSuit)
                            N.SendAKA(seat, noiseSuit)
                        end
                    end
                end
                -- Audit C-1: capture leadSuit BEFORE ApplyPlay so the
                -- bot-memory observer sees whether `card` followed suit.
                -- Without this, void inference / firstDiscard / Fzloky /
                -- AKA dedup / trump-tempo counters miss every bot play —
                -- ~50% of all card observations dropped silently.
                local leadBefore = S.s.trick and S.s.trick.leadSuit or nil
                S.ApplyPlay(seat, card)
                if B.Bot and B.Bot.OnPlayObserved then
                    B.Bot.OnPlayObserved(seat, card, leadBefore)
                end
                N.SendPlay(seat, card)
                -- v1.0.11 (D HIGH-2): bot auto-announce Baloot/Belote
                -- when this play closes their K+Q-of-trump pair. PDF
                -- requires announcement-on-second-card to count the +20
                -- bonus; bots always announce (they would never miss
                -- the click in real play). Humans get the BALOOT! UI
                -- button and click manually.
                N._HostMaybeAutoBelote(seat, card)
                N._HostStepPlay()
            end)
            if not ok then
                log("Error", "play-decision callback failed: %s", tostring(err))
                if S.s.phase == K.PHASE_PLAY
                   and S.s.turn == seat and S.s.turnKind == "play"
                   -- 8th-audit fix: skip the fallback auto-play if SWA
                   -- voting is still in flight (same reason as the
                   -- guard in the success path above).
                   and not (S.s.swaRequest and S.s.swaRequest.caller) then
                    -- Re-audit V9 fix: if PickMelds errored mid-loop,
                    -- partial melds may have already broadcast but
                    -- meldsDeclared[seat] stayed false. Mark it true
                    -- now to prevent the next MaybeRunBot pass from
                    -- re-running the (already-erroring) meld pick.
                    if S.s.meldsDeclared and not S.s.meldsDeclared[seat] then
                        S.s.meldsDeclared[seat] = true
                    end
                    local hand = S.s.hostHands and S.s.hostHands[seat]
                    if hand and S.s.contract then
                        local legal = {}
                        for _, c in ipairs(hand) do
                            if R.IsLegalPlay(c, hand, S.s.trick, S.s.contract, seat, S.s.akaCalled) then
                                legal[#legal + 1] = c
                            end
                        end
                        if #legal > 0 then
                            local best, bestRank = legal[1], math.huge
                            for _, c in ipairs(legal) do
                                local r = C.TrickRank(c, S.s.contract)
                                if r < bestRank then best, bestRank = c, r end
                            end
                            -- Audit C-1: feed the recovery-path play
                            -- through the same observer the success path
                            -- and AFK timeout use.
                            local leadBefore = S.s.trick and S.s.trick.leadSuit or nil
                            S.ApplyPlay(seat, best)
                            if B.Bot and B.Bot.OnPlayObserved then
                                B.Bot.OnPlayObserved(seat, best, leadBefore)
                            end
                            N.SendPlay(seat, best)
                            N._HostMaybeAutoBelote(seat, best)
                            N._HostStepPlay()
                        end
                    end
                end
            end
            if B.UI then B.UI.Refresh() end
        end)
        return
    end
end
