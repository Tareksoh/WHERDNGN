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

-- High-level senders. These are called by State / UI; they format and
-- broadcast or whisper. Most are host-only invocations.

function N.SendHostAnnounce(gameID)
    broadcast(("%s;%s"):format(K.MSG_HOST, gameID))
end

function N.SendJoin(gameID)
    broadcast(("%s;%s"):format(K.MSG_JOIN, gameID))
end

function N.SendLobby(seats, gameID)
    -- Wire format extended: trailing 4-char bot mask after the names so
    -- non-host clients can tell bots from humans. Without this they'd
    -- treat bot seats as human-owned and reject any host-signed bot
    -- bid/play/meld via authorizeSeat (sender == host != "Bot 3").
    local names, bots = {}, {}
    for i = 1, 4 do
        local s = seats[i]
        names[i] = (s and s.name) or ""
        bots[i] = (s and s.isBot) and "1" or "0"
    end
    broadcast(("%s;%s;%s;%s"):format(K.MSG_LOBBY, gameID,
        table.concat(names, ";"), table.concat(bots, "")))
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
    broadcast(("%s;%s"):format(K.MSG_BIDCARD, card))
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

function N.SendDouble(seat)
    broadcast(("%s;%d"):format(K.MSG_DOUBLE, seat))
end

function N.SendRedouble(seat)
    broadcast(("%s;%d"):format(K.MSG_REDOUBLE, seat))
end

function N.SendTriple(seat)
    broadcast(("%s;%d"):format(K.MSG_TRIPLE, seat))
end

function N.SendFour(seat)
    broadcast(("%s;%d"):format(K.MSG_FOUR, seat))
end

function N.SendGahwa(seat)
    broadcast(("%s;%d"):format(K.MSG_GAHWA, seat))
end

function N.SendMeld(seat, meld)
    broadcast(("%s;%d;%s;%s;%s;%s"):format(
        K.MSG_MELD, seat, meld.kind, meld.suit or "", meld.top or "",
        C.EncodeHand(meld.cards or {})))
end

function N.SendPlay(seat, card)
    broadcast(("%s;%d;%s"):format(K.MSG_PLAY, seat, card))
end

function N.SendTrick(winner, points)
    broadcast(("%s;%d;%d"):format(K.MSG_TRICK, winner, points))
end

function N.SendRound(addA, addB, totA, totB)
    broadcast(("%s;%d;%d;%d;%d"):format(K.MSG_ROUND, addA, addB, totA, totB))
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
        c.doubled and "1" or "0",
        c.redoubled and "1" or "0",
        tostring(s.cumulative and s.cumulative.A or 0),
        tostring(s.cumulative and s.cumulative.B or 0),
        s.paused and "1" or "0",
        seats[1], seats[2], seats[3], seats[4],
        bids[1], bids[2], bids[3], bids[4],
    }, "|")
end

function N.SendResyncRes(target, gameID)
    if not target then return end
    local payload = packSnapshot()
    whisper(target, ("%s;%s;%s"):format(K.MSG_RESYNC_RES, gameID or "", payload))
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
        N._OnHost(sender, fields[2])
    elseif tag == K.MSG_JOIN then
        N._OnJoin(sender, fields[2])
    elseif tag == K.MSG_LOBBY then
        N._OnLobby(sender, fields[2],
            { fields[3] or "", fields[4] or "", fields[5] or "", fields[6] or "" },
            fields[7])
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
        N._OnDouble(sender, tonumber(fields[2]))
    elseif tag == K.MSG_REDOUBLE then
        N._OnRedouble(sender, tonumber(fields[2]))
    elseif tag == K.MSG_TRIPLE then
        N._OnTriple(sender, tonumber(fields[2]))
    elseif tag == K.MSG_FOUR then
        N._OnFour(sender, tonumber(fields[2]))
    elseif tag == K.MSG_GAHWA then
        N._OnGahwa(sender, tonumber(fields[2]))
    elseif tag == K.MSG_SKIP_DBL then
        N._OnSkipDouble(sender, tonumber(fields[2]))
    elseif tag == K.MSG_SKIP_RDBL then
        N._OnSkipRedouble(sender, tonumber(fields[2]))
    elseif tag == K.MSG_SKIP_TRP then
        N._OnSkipTriple(sender, tonumber(fields[2]))
    elseif tag == K.MSG_SKIP_FOR then
        N._OnSkipFour(sender, tonumber(fields[2]))
    elseif tag == K.MSG_SKIP_GHW then
        N._OnSkipGahwa(sender, tonumber(fields[2]))
    elseif tag == K.MSG_MELD then
        N._OnMeld(sender, tonumber(fields[2]), fields[3], fields[4], fields[5], fields[6])
    elseif tag == K.MSG_PLAY then
        N._OnPlay(sender, tonumber(fields[2]), fields[3])
    elseif tag == K.MSG_TRICK then
        N._OnTrick(sender, tonumber(fields[2]), tonumber(fields[3]))
    elseif tag == K.MSG_ROUND then
        N._OnRound(sender, tonumber(fields[2]), tonumber(fields[3]), tonumber(fields[4]), tonumber(fields[5]))
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

local function fromHost(sender)
    return S.s.hostName and sender == S.s.hostName
end

local function fromSelf(sender)
    return S.s.localName and sender == S.s.localName
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
    if info.isBot then
        return S.s.hostName and sender == S.s.hostName
    end
    return info.name and info.name == sender
end

-- Loopback policy: SendAddonMessage delivers a copy back to the sender
-- via CHAT_MSG_ADDON. Local actions (Local* / Host*) already apply state
-- directly, so handlers SKIP self-loopbacks to avoid double-apply.

function N._OnHost(sender, gameID)
    if fromSelf(sender) then return end
    if S.s.phase ~= K.PHASE_IDLE and S.s.phase ~= K.PHASE_LOBBY then return end
    if S.s.isHost then return end
    S.s.pendingHost = { name = sender, gameID = gameID }
    log("Info", "host announce from %s gameID=%s", sender, tostring(gameID))
end

function N._OnJoin(sender, gameID)
    if fromSelf(sender) then return end
    if not S.s.isHost or S.s.phase ~= K.PHASE_LOBBY then return end
    if gameID ~= S.s.gameID then return end
    local seat = S.HostHandleJoin(sender)
    if seat then
        N.SendLobby(S.s.seats, S.s.gameID)
    end
end

function N._OnLobby(sender, gameID, names, botMask)
    if fromSelf(sender) then return end
    if not fromHost(sender) and not S.s.pendingHost then
        S.s.hostName = sender
    end
    S.ApplyLobby(gameID, names, botMask)
end

function N._OnStart(sender, roundNumber, dealer)
    if fromSelf(sender) then return end
    if not fromHost(sender) then return end
    S.ApplyStart(roundNumber, dealer)
end

function N._OnDealPhase(sender, phase, extra)
    if fromSelf(sender) then return end
    if not fromHost(sender) then return end
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
    S.ApplyHand(C.DecodeHand(encodedCards), forRound)
end

function N._OnBidCard(sender, card)
    if fromSelf(sender) then return end
    if not fromHost(sender) then return end
    S.ApplyBidCard(card)
end

function N._OnTurn(sender, seat, kind)
    if fromSelf(sender) then return end
    if not fromHost(sender) then return end
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
    if not bidder or not btype then return end
    S.ApplyContract(bidder, btype, trump)
end

function N._OnDouble(sender, seat)
    if fromSelf(sender) then return end
    if not seat then return end
    -- Idempotence: ignore if no contract or already doubled. Without this
    -- a duplicate/spoofed DOUBLE during PLAY would re-set s.phase back to
    -- REDOUBLE and freeze the hand mid-trick.
    if not S.s.contract or S.s.contract.doubled then return end
    if S.s.phase ~= K.PHASE_DOUBLE then return end
    -- Authority: only the eligible defender (NextSeat of bidder) can bel.
    local eligibleSeat = (S.s.contract.bidder % 4) + 1
    if seat ~= eligibleSeat then return end
    if not authorizeSeat(seat, sender) then return end
    S.ApplyDouble(seat)
    if S.s.isHost then N.MaybeRunBot() end   -- Bel-Re decision may now be a bot's
end

function N._OnRedouble(sender, seat)
    if fromSelf(sender) then return end
    if not seat then return end
    -- Idempotence: same hazard as _OnDouble — a re-applied REDOUBLE would
    -- re-trigger HostFinishDeal in PLAY phase and re-deal cards.
    if not S.s.contract or not S.s.contract.doubled or S.s.contract.redoubled then return end
    if S.s.phase ~= K.PHASE_REDOUBLE then return end
    if seat ~= S.s.contract.bidder then return end
    if not authorizeSeat(seat, sender) then return end
    S.ApplyRedouble(seat)
    -- After Bel-Re the phase is TRIPLE (defender's escalation window).
    -- MaybeRunBot dispatches the bot triple decision OR arms the AFK
    -- timer for a human defender.
    if S.s.isHost then N.MaybeRunBot() end
end

function N._OnTriple(sender, seat)
    if fromSelf(sender) then return end
    if not seat then return end
    if not S.s.contract or S.s.contract.tripled then return end
    if S.s.phase ~= K.PHASE_TRIPLE then return end
    -- Triple is the DEFENDER's escalation: NextSeat(bidder).
    local eligibleSeat = (S.s.contract.bidder % 4) + 1
    if seat ~= eligibleSeat then return end
    if not authorizeSeat(seat, sender) then return end
    S.ApplyTriple(seat)
    if S.s.isHost then N.MaybeRunBot() end
end

function N._OnFour(sender, seat)
    if fromSelf(sender) then return end
    if not seat then return end
    if not S.s.contract or S.s.contract.foured then return end
    if S.s.phase ~= K.PHASE_FOUR then return end
    -- Four is the BIDDER's escalation.
    if seat ~= S.s.contract.bidder then return end
    if not authorizeSeat(seat, sender) then return end
    S.ApplyFour(seat)
    if S.s.isHost then N.MaybeRunBot() end
end

function N._OnGahwa(sender, seat)
    if fromSelf(sender) then return end
    if not seat then return end
    if not S.s.contract or S.s.contract.gahwa then return end
    if S.s.phase ~= K.PHASE_GAHWA then return end
    -- Gahwa is the DEFENDER's terminal escalation.
    local eligibleSeat = (S.s.contract.bidder % 4) + 1
    if seat ~= eligibleSeat then return end
    if not authorizeSeat(seat, sender) then return end
    S.ApplyGahwa(seat)
    -- Terminal: no further window. Move into PLAY.
    if S.s.isHost then N.HostFinishDeal() end
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

function N._OnSkipRedouble(sender, seat)
    if fromSelf(sender) then return end
    if S.s.phase ~= K.PHASE_REDOUBLE then return end
    if not seat or not S.s.contract then return end
    if seat ~= S.s.contract.bidder then return end
    if not authorizeSeat(seat, sender) then return end
    if S.s.isHost then N.HostFinishDeal() end
end

function N._OnSkipTriple(sender, seat)
    if fromSelf(sender) then return end
    if S.s.phase ~= K.PHASE_TRIPLE then return end
    if not seat or not S.s.contract then return end
    local eligibleSeat = (S.s.contract.bidder % 4) + 1
    if seat ~= eligibleSeat then return end
    if not authorizeSeat(seat, sender) then return end
    if S.s.isHost then N.HostFinishDeal() end
end

function N._OnSkipFour(sender, seat)
    if fromSelf(sender) then return end
    if S.s.phase ~= K.PHASE_FOUR then return end
    if not seat or not S.s.contract then return end
    if seat ~= S.s.contract.bidder then return end
    if not authorizeSeat(seat, sender) then return end
    if S.s.isHost then N.HostFinishDeal() end
end

function N._OnSkipGahwa(sender, seat)
    if fromSelf(sender) then return end
    if S.s.phase ~= K.PHASE_GAHWA then return end
    if not seat or not S.s.contract then return end
    local eligibleSeat = (S.s.contract.bidder % 4) + 1
    if seat ~= eligibleSeat then return end
    if not authorizeSeat(seat, sender) then return end
    if S.s.isHost then N.HostFinishDeal() end
end

function N._OnMeld(sender, seat, kind, suit, top, encodedCards)
    if fromSelf(sender) then return end
    if not seat or not kind then return end
    -- Phase: melds are declarable in DEAL3 / PLAY only. ApplyMeld already
    -- dedupes by (seat, kind, top, suit), but we still gate phase + author
    -- here so a stale message from a previous round can't poison the
    -- meldsByTeam table.
    if S.s.phase ~= K.PHASE_PLAY and S.s.phase ~= K.PHASE_DEAL3 then return end
    if not authorizeSeat(seat, sender) then return end
    S.ApplyMeld(seat, kind, suit, top, encodedCards)
end

function N._OnPlay(sender, seat, card)
    if fromSelf(sender) then return end
    if not seat or not card then return end
    -- Phase: plays only land during PLAY.
    if S.s.phase ~= K.PHASE_PLAY then return end
    -- Turn: only the seat whose turn it is may play.
    if S.s.turn ~= seat or S.s.turnKind ~= "play" then return end
    -- Idempotence: that seat must not have already played this trick.
    if S.s.trick and S.s.trick.plays then
        for _, p in ipairs(S.s.trick.plays) do
            if p.seat == seat then return end
        end
    end
    -- Authority: sender must own the seat (or host if it's a bot).
    if not authorizeSeat(seat, sender) then return end
    -- Capture lead suit BEFORE ApplyPlay so the bot memory observer
    -- knows whether `card` followed suit or was off-suit (a void tell).
    local leadBefore = S.s.trick and S.s.trick.leadSuit or nil
    S.ApplyPlay(seat, card)
    if B.Bot and B.Bot.OnPlayObserved then
        B.Bot.OnPlayObserved(seat, card, leadBefore)
    end
    N.CancelTurnTimer()
    if S.s.isHost then N._HostStepPlay() end
end

function N._OnTrick(sender, winner, points)
    if fromSelf(sender) then return end
    if not fromHost(sender) then return end
    S.ApplyTrickEnd(winner, points)
    if S.s.isHost then N._HostStepAfterTrick() end
end

function N._OnRound(sender, addA, addB, totA, totB)
    if fromSelf(sender) then return end
    if not fromHost(sender) then return end
    S.ApplyRoundEnd(addA, addB, totA, totB)
end

function N._OnGameEnd(sender, winner)
    if fromSelf(sender) then return end
    if not fromHost(sender) then return end
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
        S.ApplyContract(payload.bidder, payload.type, payload.trump)
        N.SendContract(payload.bidder, payload.type, payload.trump or "")
        N.MaybeRunBot()
    elseif action == "round2" then
        S.HostBeginRound2()
        N.SendDealPhase("2")
        local first = (S.s.dealer % 4) + 1
        S.ApplyTurn(first, "bid")
        N.SendTurn(first, "bid")
        N.MaybeRunBot()
    elseif action == "redeal" then
        N._HostRedeal()
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
        -- A Takweesh during the wait window can move phase to SCORE.
        -- Don't resolve the trick if we're no longer in PLAY.
        if S.s.phase ~= K.PHASE_PLAY then return end
        if not S.s.contract then return end
        if not S.s.trick or #S.s.trick.plays < 4 then return end
        local winner = R.TrickWinner(S.s.trick, S.s.contract)
        local points = R.TrickPoints(S.s.trick, S.s.contract)
        S.ApplyTrickEnd(winner, points)
        N.SendTrick(winner, points)
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
        local totA = S.s.cumulative.A + addA
        local totB = S.s.cumulative.B + addB
        S.ApplyRoundEnd(addA, addB, totA, totB)
        N.SendRound(addA, addB, totA, totB)
        if totA >= S.s.target or totB >= S.s.target then
            local winner = totA >= totB and "A" or "B"
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

function N._HostRedeal()
    -- All-pass / Kawesh redeal: per Saudi rule, the deal moves to the
    -- next dealer (no team scored, but the seat rotates). Round number
    -- stays the same since no real round was played.
    local nextDealer = (S.s.dealer % 4) + 1
    -- Surface a "redeal" banner with the next-dealer name on every
    -- client for 3 seconds before the actual deal lands. The host
    -- broadcasts a synthetic MSG_DEAL phase "redeal" so non-hosts can
    -- show the same banner; everyone counts down off their own clock.
    S.ApplyRedealAnnouncement(nextDealer)
    broadcast(("%s;redeal;%d"):format(K.MSG_DEAL, nextDealer))
    print("|cffaaaaaaWHEREDNGN|r all passed — redealing with next dealer.")
    if B.UI and B.UI.Refresh then B.UI.Refresh() end

    C_Timer.After(3.0, function()
        if not S.s.isHost then return end
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

function N.LocalDouble()
    if S.s.paused then return end
    if not S.s.contract or S.s.contract.doubled then return end
    if S.s.phase ~= K.PHASE_DOUBLE then return end
    local b = S.s.contract.bidder
    if S.s.localSeat ~= (b % 4) + 1 then return end
    cancelLocalWarn()
    S.ApplyDouble(S.s.localSeat)
    N.SendDouble(S.s.localSeat)
    if S.s.isHost then N.MaybeRunBot() end
end

function N.LocalRedouble()
    if S.s.paused then return end
    if not S.s.contract or not S.s.contract.doubled or S.s.contract.redoubled then return end
    if S.s.phase ~= K.PHASE_REDOUBLE then return end
    if S.s.localSeat ~= S.s.contract.bidder then return end
    cancelLocalWarn()
    S.ApplyRedouble(S.s.localSeat)
    N.SendRedouble(S.s.localSeat)
    -- Phase moved to TRIPLE; let MaybeRunBot dispatch the bot/AFK
    -- handling for the defender's window.
    if S.s.isHost then N.MaybeRunBot() end
end

function N.LocalTriple()
    if S.s.paused then return end
    if not S.s.contract or S.s.contract.tripled then return end
    if S.s.phase ~= K.PHASE_TRIPLE then return end
    local eligibleSeat = (S.s.contract.bidder % 4) + 1
    if S.s.localSeat ~= eligibleSeat then return end
    cancelLocalWarn()
    S.ApplyTriple(S.s.localSeat)
    N.SendTriple(S.s.localSeat)
    if S.s.isHost then N.MaybeRunBot() end
end

function N.LocalFour()
    if S.s.paused then return end
    if not S.s.contract or S.s.contract.foured then return end
    if S.s.phase ~= K.PHASE_FOUR then return end
    if S.s.localSeat ~= S.s.contract.bidder then return end
    cancelLocalWarn()
    S.ApplyFour(S.s.localSeat)
    N.SendFour(S.s.localSeat)
    if S.s.isHost then N.MaybeRunBot() end
end

function N.LocalGahwa()
    if S.s.paused then return end
    if not S.s.contract or S.s.contract.gahwa then return end
    if S.s.phase ~= K.PHASE_GAHWA then return end
    local eligibleSeat = (S.s.contract.bidder % 4) + 1
    if S.s.localSeat ~= eligibleSeat then return end
    cancelLocalWarn()
    S.ApplyGahwa(S.s.localSeat)
    N.SendGahwa(S.s.localSeat)
    -- Terminal: no further window.
    if S.s.isHost then N.HostFinishDeal() end
end

-- Skip vote. Anyone with the eligible seat can broadcast; the host
-- (or anyone receiving) acts on it via _OnSkipDouble / _OnSkipRedouble.
function N.LocalSkipDouble()
    if S.s.paused then return end
    if not S.s.contract or not S.s.localSeat then return end
    cancelLocalWarn()
    local def = (S.s.contract.bidder % 4) + 1
    if S.s.phase == K.PHASE_DOUBLE then
        if S.s.localSeat ~= def then return end
        broadcast(("%s;%d"):format(K.MSG_SKIP_DBL, S.s.localSeat))
        if S.s.isHost then N.HostFinishDeal() end
    elseif S.s.phase == K.PHASE_REDOUBLE then
        if S.s.localSeat ~= S.s.contract.bidder then return end
        broadcast(("%s;%d"):format(K.MSG_SKIP_RDBL, S.s.localSeat))
        if S.s.isHost then N.HostFinishDeal() end
    elseif S.s.phase == K.PHASE_TRIPLE then
        if S.s.localSeat ~= def then return end
        broadcast(("%s;%d"):format(K.MSG_SKIP_TRP, S.s.localSeat))
        if S.s.isHost then N.HostFinishDeal() end
    elseif S.s.phase == K.PHASE_FOUR then
        if S.s.localSeat ~= S.s.contract.bidder then return end
        broadcast(("%s;%d"):format(K.MSG_SKIP_FOR, S.s.localSeat))
        if S.s.isHost then N.HostFinishDeal() end
    elseif S.s.phase == K.PHASE_GAHWA then
        if S.s.localSeat ~= def then return end
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

    local winnerTeam = foundIllegal and callerTeam or oppTeam

    -- Penalty score: full handTotal x multiplier to the winner.
    local handTotal = (S.s.contract.type == K.BID_SUN) and K.HAND_TOTAL_SUN or K.HAND_TOTAL_HOKM
    local mult = K.MULT_BASE
    if S.s.contract.type == K.BID_SUN then mult = mult * K.MULT_SUN end
    if S.s.contract.redoubled then mult = mult * K.MULT_BELRE
    elseif S.s.contract.doubled then mult = mult * K.MULT_BEL end
    local raw = handTotal * mult
    local final = math.floor((raw + 4) / 10)

    local addA = (winnerTeam == "A") and final or 0
    local addB = (winnerTeam == "B") and final or 0
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
        local winner = (totA >= totB) and "A" or "B"
        S.ApplyGameEnd(winner)
        N.SendGameEnd(winner)
    end
    -- Force an immediate UI repaint on host. Otherwise the player has
    -- to wait for the addon-message loopback (or close+reopen the frame)
    -- before the score panel becomes visible.
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
        N.MaybeRunBot()
        if S.s.turn and S.s.turnKind then
            N.StartTurnTimer(S.s.turn, S.s.turnKind)
        end
    end
    if B.UI and B.UI.Refresh then B.UI.Refresh() end
end

function N._OnPause(sender, payload)
    if fromSelf(sender) then return end
    if not fromHost(sender) then return end
    local paused = (payload == "1")
    if S.s.paused == paused then return end
    S.ApplyPause(paused)
end

function N._OnTeams(sender, teamA, teamB)
    if fromSelf(sender) then return end
    if not fromHost(sender) then return end
    S.ApplyTeamNames(teamA, teamB)
end

-- Resync request (broadcast). Only the host responds, and only if the
-- requester is in our seat roster — otherwise spurious requests from
-- unrelated party members would leak game state.
function N._OnResyncReq(sender, gameID)
    if fromSelf(sender) then return end
    if not S.s.isHost then return end
    if not gameID or gameID == "" then return end
    if S.s.gameID ~= gameID then return end
    local found = false
    for i = 1, 4 do
        local info = S.s.seats[i]
        if info and info.name == sender then found = true; break end
    end
    if not found then
        log("Warn", "resync from %s rejected (not in roster)", tostring(sender))
        return
    end
    log("Info", "resync to %s for game %s", sender, gameID)
    N.SendResyncRes(sender, gameID)
    -- Also re-whisper their hand. The host knows it from hostHands.
    local seat
    for i = 1, 4 do
        if S.s.seats[i] and S.s.seats[i].name == sender then seat = i; break end
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
    -- Reject snapshots that don't match the gameID we asked about. A
    -- stale response from a slow host (or a snapshot for a different
    -- game we happened to overhear) shouldn't clobber state if we've
    -- since joined a fresh lobby.
    if WHEREDNGNDB and WHEREDNGNDB.lastGameID
       and WHEREDNGNDB.lastGameID ~= gameID then
        return
    end
    -- We don't yet know who the host is on a fresh /reload, so we trust
    -- that the sender claims to be host. A subsequent SendLobby (which
    -- the host broadcasts on lobby/seat changes) will reconfirm.
    S.s.hostName = sender
    S.ApplyResyncSnapshot(gameID, payload)
end

function N.LocalKawesh()
    if S.s.paused then return end
    if S.s.phase ~= K.PHASE_DEAL1 then return end
    if not S.s.localSeat then return end
    if not C.IsKaweshHand(S.s.hand) then return end  -- can't fake
    broadcast(("%s;%d"):format(K.MSG_KAWESH, S.s.localSeat))
    if S.s.isHost then N.HostHandleKawesh(S.s.localSeat) end
end

function N._OnKawesh(sender, seat)
    if fromSelf(sender) then return end
    if not seat then return end
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
-- N.LocalPlay / N.LocalDouble / N.LocalRedouble / N.LocalSkipDouble
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
-- `kind` is "bid" / "play" for normal turns, or "bel" / "belre" for the
-- contract decision windows.
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
        mine = S.s.contract and S.s.localSeat
               and S.s.localSeat == ((S.s.contract.bidder % 4) + 1)
    elseif kind == "belre" then
        mine = S.s.contract and S.s.localSeat
               and S.s.localSeat == S.s.contract.bidder
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
        S.ApplyPlay(seat, best)
        N.SendPlay(seat, best)
        N._HostStepPlay()
    end
    if B.UI and B.UI.Refresh then B.UI.Refresh() end
end

-- Bel/Bel-Re windows have no turn pointer (s.turn stays nil), so the
-- standard AFK turn timer can't cover them. We arm a dedicated timer
-- that auto-skips after K.TURN_TIMEOUT_SEC. Reuses turnTimer because
-- only one of {turn, bel, belre} can be active at a time.
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
    if kind == "double" and S.s.phase == K.PHASE_DOUBLE then
        log("Info", "AFK timeout: bel skip seat=%d", seat)
        broadcast(("%s;%d"):format(K.MSG_SKIP_DBL, seat))
        N.HostFinishDeal()
    elseif kind == "redouble" and S.s.phase == K.PHASE_REDOUBLE then
        log("Info", "AFK timeout: bel-re skip seat=%d", seat)
        broadcast(("%s;%d"):format(K.MSG_SKIP_RDBL, seat))
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
    end
    if B.UI and B.UI.Refresh then B.UI.Refresh() end
end

function N.HostHandleKawesh(seat)
    if not S.s.isHost then return end
    if S.s.phase ~= K.PHASE_DEAL1 then return end
    -- Validate: only the caller's seat can prove the hand from hostHands
    if S.s.hostHands and S.s.hostHands[seat] then
        if not C.IsKaweshHand(S.s.hostHands[seat]) then
            log("Warn", "kawesh rejected: seat %d hand isn't all 7/8/9", seat)
            return
        end
    end
    -- Local print for host
    local info = S.s.seats[seat]
    local nm = (info and info.name and (info.name:match("^([^%-]+)") or info.name)) or "?"
    print(("|cffff8800WHEREDNGN|r %s called Kawesh — hand annulled, redeal."):format(nm))
    -- _HostRedeal advances the dealer itself; do NOT pre-rotate here
    -- or we'd skip a seat (was a bug — rotated twice).
    N._HostRedeal()
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
local BOT_DELAY_BEL  = 1.4   -- Bel/Bel-Re also has a voice cue

local function isBotSeat(seat)
    return S.s.isHost and seat and S.s.seats[seat] and S.s.seats[seat].isBot
end

function N.MaybeRunBot()
    if not S.s.isHost then return end
    if not B.Bot then return end
    if S.s.paused then return end

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
                local ok, err = pcall(function()
                    if S.s.phase ~= K.PHASE_DOUBLE then
                        log("Info", "bel-decision skipped: phase=%s", tostring(S.s.phase))
                        return
                    end
                    local bel = B.Bot.PickDouble(belSeat)
                    log("Info", "bel-decision seat=%d pick=%s", belSeat, tostring(bel))
                    if bel then
                        S.ApplyDouble(belSeat)
                        N.SendDouble(belSeat)
                        N.MaybeRunBot()
                    else
                        broadcast(("%s;%d"):format(K.MSG_SKIP_DBL, belSeat))
                        N.HostFinishDeal()
                    end
                end)
                if not ok then
                    log("Error", "bel-decision callback failed: %s", tostring(err))
                    -- Defensive recovery: if the contract is still
                    -- waiting on a bel decision, force-skip so the game
                    -- doesn't freeze on this seat.
                    if S.s.phase == K.PHASE_DOUBLE then
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

    -- Bel-Re decision: bidder
    if S.s.phase == K.PHASE_REDOUBLE and S.s.contract then
        local bidder = S.s.contract.bidder
        if isBotSeat(bidder) then
            log("Info", "schedule belre-decision for bot seat=%d", bidder)
            C_Timer.After(BOT_DELAY_BEL, function()
                if S.s.phase ~= K.PHASE_REDOUBLE then return end
                if B.Bot.PickRedouble(bidder) then
                    S.ApplyRedouble(bidder)
                    N.SendRedouble(bidder)
                    -- Phase is now TRIPLE; recurse to handle that
                    -- window's defender response.
                    N.MaybeRunBot()
                else
                    broadcast(("%s;%d"):format(K.MSG_SKIP_RDBL, bidder))
                    N.HostFinishDeal()
                end
                if B.UI then B.UI.Refresh() end
            end)
            return
        else
            N.StartBelTimer(bidder, "redouble")
            return
        end
    end

    -- Triple decision: defender. Bots default to skip with a small
    -- chance to escalate so they're not perfectly predictable.
    local function escalateChance(_seat) return math.random() < 0.10 end
    if S.s.phase == K.PHASE_TRIPLE and S.s.contract then
        local defSeat = (S.s.contract.bidder % 4) + 1
        if isBotSeat(defSeat) then
            C_Timer.After(BOT_DELAY_BEL, function()
                if S.s.phase ~= K.PHASE_TRIPLE then return end
                if escalateChance(defSeat) then
                    S.ApplyTriple(defSeat)
                    N.SendTriple(defSeat)
                    N.MaybeRunBot()
                else
                    broadcast(("%s;%d"):format(K.MSG_SKIP_TRP, defSeat))
                    N.HostFinishDeal()
                end
                if B.UI then B.UI.Refresh() end
            end)
            return
        else
            N.StartBelTimer(defSeat, "triple")
            return
        end
    end

    -- Four decision: bidder.
    if S.s.phase == K.PHASE_FOUR and S.s.contract then
        local bidder = S.s.contract.bidder
        if isBotSeat(bidder) then
            C_Timer.After(BOT_DELAY_BEL, function()
                if S.s.phase ~= K.PHASE_FOUR then return end
                if escalateChance(bidder) then
                    S.ApplyFour(bidder)
                    N.SendFour(bidder)
                    N.MaybeRunBot()
                else
                    broadcast(("%s;%d"):format(K.MSG_SKIP_FOR, bidder))
                    N.HostFinishDeal()
                end
                if B.UI then B.UI.Refresh() end
            end)
            return
        else
            N.StartBelTimer(bidder, "four")
            return
        end
    end

    -- Gahwa decision: defender (terminal).
    if S.s.phase == K.PHASE_GAHWA and S.s.contract then
        local defSeat = (S.s.contract.bidder % 4) + 1
        if isBotSeat(defSeat) then
            C_Timer.After(BOT_DELAY_BEL, function()
                if S.s.phase ~= K.PHASE_GAHWA then return end
                if escalateChance(defSeat) then
                    S.ApplyGahwa(defSeat)
                    N.SendGahwa(defSeat)
                else
                    broadcast(("%s;%d"):format(K.MSG_SKIP_GHW, defSeat))
                end
                N.HostFinishDeal()
                if B.UI then B.UI.Refresh() end
            end)
            return
        else
            N.StartBelTimer(defSeat, "gahwa")
            return
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
            if not S.s.isHost then return end
            if S.s.phase ~= K.PHASE_DEAL1 and S.s.phase ~= K.PHASE_DEAL2BID then return end
            if S.s.turn ~= seat or S.s.turnKind ~= "bid" then return end
            if S.s.bids[seat] ~= nil then return end
            local bid = B.Bot.PickBid(seat)
            S.ApplyBid(seat, bid)
            N.SendBid(seat, bid)
            N._HostStepBid()
            if B.UI then B.UI.Refresh() end
        end)
        return
    end

    -- Playing: bot's turn to play (and possibly declare melds first)
    if S.s.phase == K.PHASE_PLAY
       and S.s.turn and S.s.turnKind == "play" and isBotSeat(S.s.turn) then
        local seat = S.s.turn
        C_Timer.After(BOT_DELAY_PLAY, function()
            if not S.s.isHost then return end
            if S.s.phase ~= K.PHASE_PLAY then return end
            if S.s.turn ~= seat or S.s.turnKind ~= "play" then return end
            -- Takweesh check before the play. A bot scans for an
            -- opponent illegal play and rolls per-trick probability.
            -- If it decides to call, the round resolves immediately
            -- and we never schedule the play.
            if B.Bot.PickTakweesh and B.Bot.PickTakweesh(seat) then
                broadcast(("%s;%d"):format(K.MSG_TAKWEESH, seat))
                N.HostResolveTakweesh(seat)
                if B.UI then B.UI.Refresh() end
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
            local card = B.Bot.PickPlay(seat)
            if not card then return end
            S.ApplyPlay(seat, card)
            N.SendPlay(seat, card)
            N._HostStepPlay()
            if B.UI then B.UI.Refresh() end
        end)
        return
    end
end
