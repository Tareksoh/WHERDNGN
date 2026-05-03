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
    local cumA = (S.s.cumulative and S.s.cumulative.A) or 0
    local cumB = (S.s.cumulative and S.s.cumulative.B) or 0
    local bidderTeam = R.TeamOf(bidderSeat)
    local cumBidder   = (bidderTeam == "A") and cumA or cumB
    local cumDefender = (bidderTeam == "A") and cumB or cumA
    return cumBidder >= 101 and cumDefender < 101
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

function N.SendSWAOut(caller, valid, addA, addB, totA, totB, sweep, bidderMade)
    -- 4th-audit X4 fix: append sweep + bidderMade flags so receivers
    -- can fire the BALOOT fanfare on SWA-resolved sweeps / failed
    -- contracts (host's direct ApplyRoundEnd call already covers
    -- the host side; this closes the gap for remote clients).
    -- Three-state encoding ("" | "0" | "1") matches MSG_ROUND.
    -- Append-only so pre-v0.3.0 clients reading the old 7-field
    -- form work unchanged.
    local sweepStr = (sweep == "A" or sweep == "B") and sweep or ""
    local madeStr
    if bidderMade == true       then madeStr = "1"
    elseif bidderMade == false  then madeStr = "0"
    else                              madeStr = "" end
    broadcast(("%s;%d;%s;%d;%d;%d;%d;%s;%s"):format(
        K.MSG_SWA_OUT, caller, valid and "1" or "0",
        addA, addB, totA, totB, sweepStr, madeStr))
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
function N.SendResyncReq(gameID)
    broadcast(("%s;%s"):format(K.MSG_RESYNC_REQ, gameID or ""))
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
    -- Replay closed-trick history (fed via MSG_TRICK so the receiver
    -- runs the same ApplyTrickEnd path; we provide the fully-encoded
    -- plays so they don't depend on MSG_PLAY arrival order).
    for _, t in ipairs(S.s.tricks or {}) do
        local enc = ""
        for _, p in ipairs(t.plays or {}) do
            enc = enc .. (p.card or "??") .. tostring(p.seat or 0)
        end
        whisper(target, ("%s;%d;%d;%s;%s"):format(
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
    elseif tag == K.MSG_PREEMPT then
        N._OnPreempt(sender, tonumber(fields[2]))
    elseif tag == K.MSG_PREEMPT_PASS then
        -- 7th-audit fix: forward the optional eligible CSV (fields[3])
        -- so the seat=0 "window open" frame can seed phase + eligible
        -- list on remote clients. Pre-7th senders won't include it;
        -- _OnPreemptPass treats nil as "no CSV provided".
        N._OnPreemptPass(sender, tonumber(fields[2]), fields[3])
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
        N._OnTrick(sender, tonumber(fields[2]), tonumber(fields[3]),
                   fields[4], fields[5])
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
        N._OnSWAOut(sender, tonumber(fields[2]),
                    fields[3] == "1",
                    tonumber(fields[4]), tonumber(fields[5]),
                    tonumber(fields[6]), tonumber(fields[7]),
                    swSweep, swMade)
    elseif tag == K.MSG_SWA_REQ then
        N._OnSWAReq(sender, tonumber(fields[2]), fields[3])
    elseif tag == K.MSG_SWA_RESP then
        N._OnSWAResp(sender, tonumber(fields[2]),
                     fields[3] == "1", tonumber(fields[4]))
    elseif tag == K.MSG_RESYNC_REQ then
        N._OnResyncReq(sender, fields[2])
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
    S.ApplyHand(C.DecodeHand(encodedCards), forRound)
end

function N._OnBidCard(sender, card)
    if fromSelf(sender) then return end
    if not fromHost(sender) then return end
    if S.s.isHost then return end
    S.ApplyBidCard(card)
end

function N._OnTurn(sender, seat, kind)
    if fromSelf(sender) then return end
    if not fromHost(sender) then return end
    if S.s.isHost then return end
    if not seat then return end
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
    S.ApplyContract(bidder, btype, trump)
end

function N._OnDouble(sender, seat, openField)
    if fromSelf(sender) then return end
    if not seat then return end
    -- Idempotence: ignore if no contract or already doubled.
    if not S.s.contract or S.s.contract.doubled then return end
    if S.s.phase ~= K.PHASE_DOUBLE then return end
    -- Authority: only the eligible defender (NextSeat of bidder) can bel.
    local eligibleSeat = (S.s.contract.bidder % 4) + 1
    if seat ~= eligibleSeat then return end
    if not authorizeSeat(seat, sender) then return end
    -- Open/Closed flag (v0.2.0+ wire). Pre-v0.2.0 senders won't include
    -- it; default to OPEN (current behavior).
    local open = (openField == nil) or (openField ~= "0")
    local wasSun = S.s.contract.type == K.BID_SUN
    S.ApplyDouble(seat, open)
    -- Audit fix: pass rung kind so the bot style ledger tracks Bel
    -- separately from Triple/Four/Gahwa.
    if B.Bot and B.Bot.OnEscalation then B.Bot.OnEscalation(seat, "double") end
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
    if not S.s.contract or S.s.contract.tripled then return end
    if S.s.phase ~= K.PHASE_TRIPLE then return end
    -- Triple is the BIDDER's response to Bel.
    if seat ~= S.s.contract.bidder then return end
    if not authorizeSeat(seat, sender) then return end
    local open = (openField == nil) or (openField ~= "0")
    S.ApplyTriple(seat, open)
    if B.Bot and B.Bot.OnEscalation then B.Bot.OnEscalation(seat, "triple") end
    if S.s.isHost then
        if open then N.MaybeRunBot() else N.HostFinishDeal() end
    end
end

function N._OnFour(sender, seat, openField)
    if fromSelf(sender) then return end
    if not seat then return end
    if not S.s.contract or S.s.contract.foured then return end
    if S.s.phase ~= K.PHASE_FOUR then return end
    -- Four is the DEFENDER's response to Triple.
    local eligibleSeat = (S.s.contract.bidder % 4) + 1
    if seat ~= eligibleSeat then return end
    if not authorizeSeat(seat, sender) then return end
    local open = (openField == nil) or (openField ~= "0")
    S.ApplyFour(seat, open)
    if B.Bot and B.Bot.OnEscalation then B.Bot.OnEscalation(seat, "four") end
    if S.s.isHost then
        if open then N.MaybeRunBot() else N.HostFinishDeal() end
    end
end

function N._OnGahwa(sender, seat)
    if fromSelf(sender) then return end
    if not seat then return end
    if not S.s.contract or S.s.contract.gahwa then return end
    if S.s.phase ~= K.PHASE_GAHWA then return end
    -- Gahwa is the BIDDER's terminal (match-win) escalation.
    if seat ~= S.s.contract.bidder then return end
    if not authorizeSeat(seat, sender) then return end
    S.ApplyGahwa(seat)
    if B.Bot and B.Bot.OnEscalation then B.Bot.OnEscalation(seat, "gahwa") end
    -- Terminal: no further window. Move into PLAY.
    if S.s.isHost then N.HostFinishDeal() end
end

function N._OnPreempt(sender, seat)
    if fromSelf(sender) then return end
    if not seat then return end
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

function N._OnSkipDouble(sender, seat)
    if fromSelf(sender) then return end
    if S.s.phase ~= K.PHASE_DOUBLE then return end
    if not seat or not S.s.contract then return end
    local eligibleSeat = (S.s.contract.bidder % 4) + 1
    if seat ~= eligibleSeat then return end
    if not authorizeSeat(seat, sender) then return end
    if S.s.isHost then N.HostFinishDeal() end
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
    -- Defender skips their Four window.
    local eligibleSeat = (S.s.contract.bidder % 4) + 1
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
    -- Authority: sender must own the seat (or host if it's a bot).
    if not isReplay and not authorizeSeat(seat, sender) then return end
    -- Capture lead suit BEFORE ApplyPlay so the bot memory observer
    -- knows whether `card` followed suit or was off-suit (a void tell).
    local leadBefore = S.s.trick and S.s.trick.leadSuit or nil
    S.ApplyPlay(seat, card)
    if B.Bot and B.Bot.OnPlayObserved then
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

function N._OnTrick(sender, winner, points, leadSuit, encPlays)
    if fromSelf(sender) then return end
    if not fromHost(sender) then return end
    if S.s.isHost then return end
    -- Authoritative trick snapshot from host. We rebuild s.trick from
    -- the encoded plays so ApplyTrickEnd's lastTrick stash is complete
    -- regardless of MSG_PLAY arrival order. Older hosts (pre-v0.1.25)
    -- send empty leadSuit/encPlays — fall back to the local view.
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
    S.ApplyTrickEnd(winner, points)
    if S.s.isHost then N._HostStepAfterTrick() end
end

function N._OnRound(sender, addA, addB, totA, totB, sweep, bidderMade)
    if fromSelf(sender) then return end
    if not fromHost(sender) then return end
    if S.s.isHost then return end
    S.ApplyRoundEnd(addA, addB, totA, totB, sweep, bidderMade)
end

function N._OnGameEnd(sender, winner)
    if fromSelf(sender) then return end
    if not fromHost(sender) then return end
    if S.s.isHost then return end
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
        if res.gahwaWonGame and res.gahwaWinner then
            local target = S.s.target or 152
            if res.gahwaWinner == "A" then
                addA = math.max(addA, target - (S.s.cumulative.A or 0))
            else
                addB = math.max(addB, target - (S.s.cumulative.B or 0))
            end
        end
        local totA = S.s.cumulative.A + addA
        local totB = S.s.cumulative.B + addB
        S.ApplyRoundEnd(addA, addB, totA, totB, res.sweep, res.bidderMade)
        N.SendRound(addA, addB, totA, totB, res.sweep, res.bidderMade)
        if totA >= S.s.target or totB >= S.s.target then
            -- Saudi convention: on an exact tie at the target, the
            -- BIDDING team wins — they took the contract risk and
            -- got over the line. Default fallback when there's no
            -- contract (shouldn't happen at game-end) is Team A.
            local winner
            if totA == totB and S.s.contract and S.s.contract.bidder then
                winner = R.TeamOf(S.s.contract.bidder)
            elseif totA > totB then winner = "A"
            elseif totB > totA then winner = "B"
            else                    winner = "A" end
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

    -- 9th-audit fix: capture a generation token so /baloot reset can
    -- invalidate this in-flight 3s callback. Without this, a reset
    -- during the redeal countdown would let the timer fire afterward
    -- and spawn a ghost round into the IDLE state. State.Reset bumps
    -- _redealGen to invalidate any pending callbacks.
    B._redealGen = (B._redealGen or 0) + 1
    local thisGen = B._redealGen
    C_Timer.After(3.0, function()
        if thisGen ~= B._redealGen then return end
        if not S.s.isHost then return end
        -- Reset / pause guards: if the user reset or paused during
        -- the 3s redeal banner, abort the deal — otherwise we'd
        -- write fresh round state into a wiped or paused game.
        if S.s.phase ~= K.PHASE_DEAL2BID and S.s.phase ~= K.PHASE_DEAL1
           and not S.s.redealing then
            return
        end
        if S.s.paused then return end
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
        dealer = 1
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
    local b = S.s.contract.bidder
    if S.s.localSeat ~= (b % 4) + 1 then return end
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
    local eligibleSeat = (S.s.contract.bidder % 4) + 1
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
    local def = (S.s.contract.bidder % 4) + 1
    if S.s.phase == K.PHASE_DOUBLE then
        if S.s.localSeat ~= def then return end
        broadcast(("%s;%d"):format(K.MSG_SKIP_DBL, S.s.localSeat))
        if S.s.isHost then N.HostFinishDeal() end
    elseif S.s.phase == K.PHASE_TRIPLE then
        -- Bidder skips Triple.
        if S.s.localSeat ~= S.s.contract.bidder then return end
        broadcast(("%s;%d"):format(K.MSG_SKIP_TRP, S.s.localSeat))
        if S.s.isHost then N.HostFinishDeal() end
    elseif S.s.phase == K.PHASE_FOUR then
        -- Defender skips Four.
        if S.s.localSeat ~= def then return end
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
        -- HostDealRest returns nil only when hostHands or
        -- hostDeckRemainder is missing — that means the bidding ended
        -- without a fresh HostDealInitial having run, OR the state was
        -- partly reset. Log it so a freeze is visible.
        log("Error", "HostFinishDeal: HostDealRest returned nil (hostHands=%s remainder=%s phase=%s)",
            tostring(S.s.hostHands ~= nil), tostring(S.s.hostDeckRemainder ~= nil),
            tostring(S.s.phase))
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
        local ok, why = R.IsLegalPlay(card, S.s.hand, S.s.trick, S.s.contract, S.s.localSeat)
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
    -- v0.2.0+ multiplier ladder: Bel(×2)/Triple(×3)/Four(×4). Gahwa is
    -- NOT a multiplier — it's a match-win. But for early-termination
    -- penalties (takweesh, invalid SWA), the per-round score is still
    -- computed to charge the bare 26 (Sun) / 16 (Hokm) penalty even
    -- when Gahwa was called — so we treat Gahwa as ×4 for THIS path
    -- (highest active rung). The match-win semantic only applies to
    -- a fully-played-out round, not a forfeit.
    local mult = K.MULT_BASE
    if c.type == K.BID_SUN then mult = mult * K.MULT_SUN end
    if     c.gahwa   then mult = mult * K.MULT_FOUR
    elseif c.foured  then mult = mult * K.MULT_FOUR
    elseif c.tripled then mult = mult * K.MULT_TRIPLE
    elseif c.doubled then mult = mult * K.MULT_BEL end

    local meldA = R.SumMeldValue(S.s.meldsByTeam.A)
    local meldB = R.SumMeldValue(S.s.meldsByTeam.B)
    local cardA = (winnerTeam == "A") and handTotal or 0
    local cardB = (winnerTeam == "B") and handTotal or 0
    -- Saudi Qayd rule (per "نظام التسجيل في البلوت"): "مشروعي لي
    -- ومشروعك لك" — both teams KEEP their OWN declared melds during
    -- a Qaid penalty. The penalty itself (handTotal × mult) goes to
    -- the winner; melds are NOT transferred or nullified.
    -- 14th-audit fix (Codex+Gemini scoring audit): previously the
    -- LOSER's meld was zeroed out, contradicting the rule's "your
    -- meld is yours regardless of the qaid outcome."
    local mpA = meldA
    local mpB = meldB

    -- Belote (Hokm only, played cards only — Saudi rule rb3haa).
    -- Cancelled when the K+Q holder also declared a ≥100 meld (per
    -- "ماهو البلوت في لعبة البلوت"). Same rule as R.ScoreRound.
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
            local list = (S.s.meldsByTeam and S.s.meldsByTeam[belote]) or {}
            for _, m in ipairs(list) do
                if m.declaredBy == kWho and (m.value or 0) >= 100 then
                    belote = nil
                    break
                end
            end
        end
    end

    local rawA = (cardA + mpA) * mult
    local rawB = (cardB + mpB) * mult
    if belote == "A" then rawA = rawA + K.MELD_BELOTE
    elseif belote == "B" then rawB = rawB + K.MELD_BELOTE end

    local addA = math.floor((rawA + 4) / 10)
    local addB = math.floor((rawB + 4) / 10)
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

    if totA >= S.s.target or totB >= S.s.target then
        -- Same Saudi tie-rule as the normal-round path above.
        local winner
        if totA == totB and S.s.contract and S.s.contract.bidder then
            winner = R.TeamOf(S.s.contract.bidder)
        elseif totA > totB then winner = "A"
        elseif totB > totA then winner = "B"
        else                    winner = "A" end
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
        if S.s.phase == K.PHASE_PLAY
           and S.s.trick and S.s.trick.plays
           and #S.s.trick.plays >= 4 then
            N._HostStepPlay()
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
    -- require opponent permission. Calls with ≤3 cards are instant.
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
    if needPerm and handCount >= 4 then
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
        if S.s.isHost then
            local callerTeam = R.TeamOf(S.s.localSeat)
            for s2 = 1, 4 do
                local info = S.s.seats[s2]
                if info and info.isBot and R.TeamOf(s2) ~= callerTeam then
                    N._OnSWAResp("__host__", s2, true, S.s.localSeat)
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
                C_Timer.After(windowSec, function()
                    if not S.s.isHost then return end
                    local req = S.s.swaRequest
                    if not req or req.caller ~= mySeat then return end
                    if S.s.phase ~= K.PHASE_PLAY then return end
                    S.s.swaRequest = nil
                    N.HostResolveSWA(mySeat, pinnedHand)
                end)
            end
        end
        if B.UI and B.UI.Refresh then B.UI.Refresh() end
        return
    end
    -- Direct claim (≤3 cards or permission disabled): send the actual
    -- SWA wire and let the host resolve immediately.
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
    -- "__host__" sender. Bots default to ACCEPT — they have no
    -- meta-game read that would justify denial.
    if S.s.isHost then
        local callerTeam = R.TeamOf(seat)
        for s2 = 1, 4 do
            local info = S.s.seats[s2]
            if info and info.isBot and R.TeamOf(s2) ~= callerTeam then
                N._OnSWAResp("__host__", s2, true, seat)
            end
        end
        -- Audit (user-requested): 5-second auto-approve timer. If the
        -- swaRequest is still active and bound to the same caller when
        -- the timer fires, run HostResolveSWA. Takweesh during the
        -- window clears swaRequest (existing flow) and the timer
        -- becomes a no-op via the caller-match guard.
        if C_Timer and C_Timer.After then
            local windowSec = K.SWA_TIMEOUT_SEC or 5
            C_Timer.After(windowSec, function()
                if not S.s.isHost then return end
                local req = S.s.swaRequest
                if not req or req.caller ~= seat then return end
                if S.s.phase ~= K.PHASE_PLAY then return end
                -- Decode the caller's hand from the wire (host's
                -- hostHands is authoritative; HostResolveSWA prefers
                -- it but falls back to the wire-supplied hand).
                local hand = (encodedHand and C.DecodeHand(encodedHand)) or {}
                S.s.swaRequest = nil
                N.HostResolveSWA(seat, hand)
            end)
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
    local req = S.s.swaRequest
    if not req or req.caller ~= caller then return end
    if not responder or R.TeamOf(responder) == R.TeamOf(caller) then return end
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
    -- Host is the source of truth. Decode and resolve.
    if S.s.isHost then
        local hand = C.DecodeHand(encodedHand or "")
        N.HostResolveSWA(seat, hand)
    end
end

function N._OnSWAOut(sender, caller, valid, addA, addB, totA, totB, sweep, bidderMade)
    if fromSelf(sender) then return end
    if not fromHost(sender) then return end
    if S.s.isHost then return end
    if not caller then return end
    -- Mirror the takweesh-result struct so the score banner can
    -- render the SWA outcome with its own copy.
    S.s.swaResult = {
        caller = caller, valid = valid,
        sweep = sweep, contractMade = bidderMade,
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

    if not valid then
        -- INVALID SWA → Qayd penalty (Saudi rule): opp takes
        -- handTotal × mult (= 26 Sun / 16 Hokm in final game
        -- points). Per "المشروع لصاحبه" the offender's meld STAYS
        -- WITH THEM — does NOT transfer to opp. Opp only adds
        -- THEIR OWN melds × mult. Belote independent.
        local handTotal = (c.type == K.BID_SUN) and K.HAND_TOTAL_SUN or K.HAND_TOTAL_HOKM
        -- v0.2.0+ multiplier ladder. Gahwa is treated as ×4 here (same
        -- as Four) because the match-win semantic only applies to a
        -- fully-played-out round; an invalid SWA is a per-round penalty.
        local mult = K.MULT_BASE
        if c.type == K.BID_SUN then mult = mult * K.MULT_SUN end
        if     c.gahwa   then mult = mult * K.MULT_FOUR
        elseif c.foured  then mult = mult * K.MULT_FOUR
        elseif c.tripled then mult = mult * K.MULT_TRIPLE
        elseif c.doubled then mult = mult * K.MULT_BEL end
        local meldA = R.SumMeldValue(S.s.meldsByTeam.A)
        local meldB = R.SumMeldValue(S.s.meldsByTeam.B)
        local cardA = (oppOfCaller == "A") and handTotal or 0
        local cardB = (oppOfCaller == "B") and handTotal or 0
        -- Saudi Qayd rule: BOTH teams keep their OWN declared melds.
        -- The penalty (handTotal × mult) goes to the winner; melds
        -- are NOT transferred or nullified. 14th-audit fix.
        local mpA = meldA
        local mpB = meldB
        -- Belote scan (played cards only — Saudi rule rb3haa).
        -- Cancelled when the K+Q holder also declared a ≥100 meld.
        local beloteOwner
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
                local list = (S.s.meldsByTeam and S.s.meldsByTeam[beloteOwner]) or {}
                for _, m in ipairs(list) do
                    if m.declaredBy == kWho and (m.value or 0) >= 100 then
                        beloteOwner = nil
                        break
                    end
                end
            end
        end
        local rawA = (cardA + mpA) * mult
        local rawB = (cardB + mpB) * mult
        if beloteOwner == "A" then rawA = rawA + K.MELD_BELOTE
        elseif beloteOwner == "B" then rawB = rawB + K.MELD_BELOTE end
        addA = math.floor((rawA + 4) / 10)
        addB = math.floor((rawB + 4) / 10)
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

        local result = R.ScoreRound(synth, c, S.s.meldsByTeam)
        addA = result.final.A
        addB = result.final.B
        sweepTeam = result.sweep
        contractMade = result.bidderMade
    end

    local totA = (S.s.cumulative.A or 0) + addA
    local totB = (S.s.cumulative.B or 0) + addB

    S.s.swaResult = {
        caller = callerSeat, valid = valid,
        contractMade = contractMade,
        sweep = sweepTeam,
    }
    S.s.lastRoundResult = nil
    S.s.trick = nil
    -- Re-audit W1 + 4th-audit X4 fix: pass sweepTeam + contractMade
    -- through so the BALOOT fanfare fires on host AND on remote
    -- clients (MSG_SWA_OUT now carries the flags too).
    S.ApplyRoundEnd(addA, addB, totA, totB, sweepTeam, contractMade)
    N.SendSWAOut(callerSeat, valid, addA, addB, totA, totB,
                 sweepTeam, contractMade)

    if totA >= S.s.target or totB >= S.s.target then
        local winner
        if totA == totB and S.s.contract and S.s.contract.bidder then
            winner = R.TeamOf(S.s.contract.bidder)
        elseif totA > totB then winner = "A"
        elseif totB > totA then winner = "B"
        else                    winner = "A" end
        S.ApplyGameEnd(winner)
        N.SendGameEnd(winner)
    end
    if B.UI and B.UI.Refresh then B.UI.Refresh() end
end

function N._OnAKA(sender, seat, suit, replayFlag)
    if fromSelf(sender) then return end
    if not seat or seat < 1 or seat > 4 then return end
    if not suit or suit == "" then return end
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
    -- Reject snapshots that don't match the gameID we asked about. A
    -- stale response from a slow host (or a snapshot for a different
    -- game we happened to overhear) shouldn't clobber state if we've
    -- since joined a fresh lobby.
    if WHEREDNGNDB and WHEREDNGNDB.lastGameID
       and WHEREDNGNDB.lastGameID ~= gameID then
        return
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
    if B.Sound and B.Sound.Cue then B.Sound.Cue(K.SND_TURN_PING) end
    if B.UI and B.UI.PulseTurn then B.UI.PulseTurn() end
end

-- Arm only if the local player is the one we're actually waiting on.
-- `kind` is "bid" / "play" for normal turns, or "bel" / "triple" /
-- "four" / "gahwa" for the contract decision windows. Each window has
-- a different eligibility rule (seat that's allowed to act).
function N.StartLocalWarn(kind)
    cancelLocalWarn()
    if S.s.paused then return end
    local timeout = K.TURN_TIMEOUT_SEC or 60
    local warnAt = timeout - 10
    if warnAt < 1 then return end

    local mine = false
    if kind == "bid" or kind == "play" then
        mine = (S.s.turn == S.s.localSeat) and (S.s.turnKind == kind)
    elseif kind == "bel" then
        -- Defender (bidder+1, the seat after bidder) considers Bel.
        mine = S.s.contract and S.s.localSeat
               and S.s.localSeat == ((S.s.contract.bidder % 4) + 1)
    elseif kind == "triple" then
        -- v0.2.0: Triple is bidder's response to Bel.
        mine = S.s.contract and S.s.localSeat
               and S.s.localSeat == S.s.contract.bidder
    elseif kind == "four" then
        -- Audit fix: Four is the DEFENDER's response to Triple.
        -- Same eligible seat as Bel (defender at bidder+1).
        mine = S.s.contract and S.s.localSeat
               and S.s.localSeat == ((S.s.contract.bidder % 4) + 1)
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
            if R.IsLegalPlay(c, hand, S.s.trick, S.s.contract, seat) then
                legal[#legal + 1] = c
            end
        end
        if #legal == 0 then return end
        local best, bestRank = legal[1], math.huge
        for _, c in ipairs(legal) do
            local r = C.TrickRank(c, S.s.contract)
            if r < bestRank then best, bestRank = c, r end
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
        N.HostFinishDeal()
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

    -- Bel decision: defender at NextSeat(bidder)
    if S.s.phase == K.PHASE_DOUBLE and S.s.contract then
        local belSeat = (S.s.contract.bidder % 4) + 1
        if isBotSeat(belSeat) then
            log("Info", "schedule bel-decision for bot seat=%d", belSeat)
            C_Timer.After(BOT_DELAY_BEL, function()
                -- Re-re-audit W2/W5 fix: track BOTH `applied` (ApplyX
                -- ran) and `skipSent` (broadcast SKIP_X already done)
                -- so recovery doesn't double-broadcast OR stall when
                -- ApplyX advanced phase past the simple PHASE check.
                local applied, skipSent = false, false
                local ok, err = pcall(function()
                    if S.s.paused then return end
                    if S.s.phase ~= K.PHASE_DOUBLE then
                        log("Info", "bel-decision skipped: phase=%s", tostring(S.s.phase))
                        return
                    end
                    local bel, wantOpen = B.Bot.PickDouble(belSeat)
                    log("Info", "bel-decision seat=%d pick=%s open=%s",
                        belSeat, tostring(bel), tostring(wantOpen))
                    if bel then
                        local isSun = S.s.contract
                                  and S.s.contract.type == K.BID_SUN
                        local effOpen = (not isSun) and wantOpen
                        S.ApplyDouble(belSeat, effOpen)
                        applied = true
                        N.SendDouble(belSeat, effOpen)
                        if isSun or not effOpen then
                            N.HostFinishDeal()
                        else
                            N.MaybeRunBot()
                        end
                    else
                        broadcast(("%s;%d"):format(K.MSG_SKIP_DBL, belSeat))
                        skipSent = true
                        N.HostFinishDeal()
                    end
                end)
                if not ok then
                    log("Error", "bel-decision callback failed: %s", tostring(err))
                    if applied then
                        -- ApplyDouble advanced phase. For an open Bel
                        -- in Hokm phase is now PHASE_TRIPLE — must
                        -- run MaybeRunBot for the bidder's Triple
                        -- decision, NOT HostFinishDeal which would
                        -- skip the entire Triple/Four/Gahwa chain.
                        if S.s.phase == K.PHASE_PLAY then
                            N.HostFinishDeal()
                        else
                            N.MaybeRunBot()
                        end
                    elseif skipSent then
                        -- broadcast already happened; just advance.
                        N.HostFinishDeal()
                    elseif S.s.phase == K.PHASE_DOUBLE then
                        broadcast(("%s;%d"):format(K.MSG_SKIP_DBL, belSeat))
                        N.HostFinishDeal()
                    end
                end
                if B.UI then B.UI.Refresh() end
            end)
            return
        else
            -- Human at the defender seat: arm an AFK timer so the
            -- contract doesn't freeze if they never click.
            N.StartBelTimer(belSeat, "double")
            return
        end
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
    if S.s.phase == K.PHASE_FOUR and S.s.contract then
        local defSeat = (S.s.contract.bidder % 4) + 1
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
                if not S.s.meldsDeclared[seat] then
                    local melds = B.Bot.PickMelds(seat)
                    for _, m in ipairs(melds) do
                        S.ApplyMeld(seat, m.kind, m.suit, m.top, C.EncodeHand(m.cards or {}))
                        N.SendMeld(seat, m)
                    end
                    S.s.meldsDeclared[seat] = true
                end
                -- Saudi Master tier picks via determinization sampling
                -- and falls through to Bot.PickPlay if it bails (e.g.,
                -- single legal play). Lower tiers go straight to PickPlay.
                local card = nil
                if B.BotMaster and B.BotMaster.PickPlay
                   and B.Bot.IsSaudiMaster and B.Bot.IsSaudiMaster() then
                    card = B.BotMaster.PickPlay(seat)
                end
                if not card then card = B.Bot.PickPlay(seat) end
                if not card then return end
                -- Advanced bot: if we're leading and the chosen lead card
                -- IS the AKA (highest unplayed) of a non-trump suit, fire
                -- the partner-coordination signal BEFORE the actual card.
                if B.Bot.PickAKA then
                    local akaSuit = B.Bot.PickAKA(seat, card)
                    if akaSuit then
                        S.ApplyAKA(seat, akaSuit)
                        N.SendAKA(seat, akaSuit)
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
                            if R.IsLegalPlay(c, hand, S.s.trick, S.s.contract, seat) then
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
