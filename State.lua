-- Game state and authoritative transitions.
--
-- Two roles:
--   HOST   - the player who clicks "Host Game". Owns the deck, deals
--            cards, validates plays, decides trick winners, broadcasts.
--   CLIENT - everyone else. Receives broadcasts and updates local view.
--
-- The host receives its own broadcasts via CHAT_MSG_ADDON loopback, so
-- most state transitions live in S.Apply* and run identically on host
-- and client. Only S.Host* paths are host-private (deal, score).
--
-- Hands: each player only knows their OWN hand. Host knows all hands
-- (required to validate plays). Trust assumption: friendly play, no
-- cheating client modification. Wire-level secrecy is via WHISPER for
-- the hand deal.

WHEREDNGN = WHEREDNGN or {}
local B = WHEREDNGN
B.State = B.State or {}
local S = B.State
local K, C, R = B.K, B.Cards, B.Rules
local L = B.Log

local function log(...) L.Debug("state", ...) end

-- -- State table --------------------------------------------------------

local s = {}
S.s = s

local function reset()
    -- session
    s.phase       = K.PHASE_IDLE
    s.isHost      = false
    s.hostName    = nil
    s.localName   = nil
    s.localSeat   = nil
    s.gameID      = nil
    s.winner      = nil  -- Audit C30 fix: clear stale winner from prior game
    s.seats       = { [1]=nil, [2]=nil, [3]=nil, [4]=nil }
    -- round
    s.dealer      = 1
    s.roundNumber = 0
    s.bidCard     = nil
    s.bidRound    = 1
    s.bids        = {}      -- [seat] = "PASS" | "HOKM:S/H/D/C" | "SUN"
    s.contract    = nil     -- {type, trump, bidder, doubled, tripled, foured, gahwa, openClosed}
    s.hand        = {}      -- our private hand
    s.hostHands   = nil     -- host only: [seat]={cards}
    s.turn        = nil
    s.turnKind    = nil     -- "bid" | "double" | "play" | "meld"
    s.trick       = nil     -- {leadSuit, plays}
    s.tricks      = {}
    s.meldsByTeam = { A = {}, B = {} }
    s.meldsDeclared = {}    -- [seat] = true once declared (or skipped)
    s.belPending  = nil     -- seats waiting to choose Bel/skip
    -- Pre-emption (Triple-on-Ace, الثالث): set when a round-2 SUN bid
    -- lands on an Ace bid card. Maps eligible seats (earlier-in-order,
    -- non-partner of buyer) to a pending decision. Cleared when a seat
    -- claims or all eligible seats waive.
    s.preemptEligible = nil
    -- scores
    s.cumulative  = { A = 0, B = 0 }
    s.target      = 152
    -- Team display names. Default to generic A/B labels but the host
    -- can rename via the lobby inputs (broadcast on MSG_TEAMS so all
    -- clients see the same labels). 20-char max enforced UI-side.
    s.teamNames   = { A = "Team A", B = "Team B" }
    -- Per-name version map, populated as host/join/lobby broadcasts
    -- arrive carrying the sender's addon version. Lets the lobby UI
    -- flag mismatched versions before someone starts a game.
    s.peerVersions = {}
    -- pause: host-driven freeze that suspends bot scheduling and AFK
    -- timers without dropping any in-flight state. Network-mirrored.
    s.paused      = false
    -- Audit fix: explicitly clear all per-trick / per-round transient
    -- fields so a Reset between games doesn't leave stale banners or
    -- intermediate-state structs alive. Each of these is mutated in
    -- regular gameplay; reset() is the only safe place that knows
    -- nothing is in flight.
    s.redealing             = nil
    s.lastTrick             = nil
    s.peekedThisRound       = nil
    s.pendingPreemptContract= nil
    s.handRound             = nil
    s.meldHoldUntil         = nil
    s.localPlayedThisTrick  = nil
    s.akaCalled             = nil
    s.playedCardsThisRound  = {}
    s.lastRoundResult       = nil
    s.lastRoundDelta        = nil
    s.takweeshResult        = nil
    s.swaResult             = nil
    s.swaRequest            = nil
    s.swaDenied             = nil
    s.pendingHost           = nil
    s.hostDeckRemainder     = nil
    -- Clear persisted resync hint and session so we don't re-request
    -- or restore a finished game after the next /reload.
    if WHEREDNGNDB then
        WHEREDNGNDB.lastGameID = nil
        WHEREDNGNDB.session    = nil
    end
end

function S.ApplyPause(paused)
    s.paused = (paused and true) or false
end

-- Set or clear the redeal-announcement banner. The host calls this
-- when all 4 players have passed both bidding rounds and is about to
-- rotate the dealer; receivers also call it from _OnDealPhase("redeal")
-- so every client shows the same "Next dealer: NAME" banner during the
-- 3-second hold before cards are re-dealt.
function S.ApplyRedealAnnouncement(nextDealerSeat)
    if not nextDealerSeat then
        s.redealing = nil
        return
    end
    s.redealing = {
        nextDealer = nextDealerSeat,
        ts         = (GetTime and GetTime()) or 0,
    }
    -- Auto-clear after 3.5s in case the actual deal is delayed by
    -- network or a paused host. UI re-renders on the next state
    -- change so this is best-effort cleanup.
    if C_Timer and C_Timer.After then
        C_Timer.After(3.5, function()
            if s.redealing
               and s.redealing.nextDealer == nextDealerSeat then
                s.redealing = nil
                if B.UI and B.UI.Refresh then B.UI.Refresh() end
            end
        end)
    end
end

-- Custom team labels. Falls back to "Team A"/"Team B" when the host
-- sends empty strings or this hasn't been called yet. UI-side reads
-- s.teamNames[t] anywhere it currently shows a bare A/B label.
function S.ApplyTeamNames(teamA, teamB)
    s.teamNames = s.teamNames or { A = "Team A", B = "Team B" }
    if teamA and teamA ~= "" then s.teamNames.A = teamA:sub(1, 20) end
    if teamB and teamB ~= "" then s.teamNames.B = teamB:sub(1, 20) end
    -- Persist per-account so the host's chosen names survive between
    -- sessions; the lobby UI pre-fills from this on next /reload.
    if WHEREDNGNDB then
        WHEREDNGNDB.teamNames = {
            A = s.teamNames.A,
            B = s.teamNames.B,
        }
    end
end

-- ---------------------------------------------------------------------
-- Session persistence (survives /reload and game logout).
--
-- The full in-memory state lives in `s`; SavedVariables persist any
-- table assigned to WHEREDNGNDB. SaveSession is called on
-- PLAYER_LOGOUT (which fires on /reload) and writes a shallow copy of
-- `s` into WHEREDNGNDB.session. RestoreSession runs on PLAYER_LOGIN
-- and copies the fields back into the fresh `s` table.
--
-- We skip persistence when the game is in IDLE / LOBBY / GAME_END
-- phases so a stale session doesn't pop up after a finished hand.
-- Sessions older than 1 hour are also discarded — a player who logs
-- back in days later doesn't want to resume an abandoned hand.
-- ---------------------------------------------------------------------
local TRANSIENT_FIELDS = {
    pendingHost = true,   -- ephemeral host announce we may have heard
    hostDeckRemainder = true,  -- only meaningful between deal-1 and deal-3
    -- Per-trick double-click guard: cleared by ApplyTurn whenever the
    -- turn advances. If we /reload AFTER the local player just played,
    -- a persisted true would stay true until the next ApplyTurn fires
    -- — and if turn already lands on us in the saved state, the host's
    -- own LocalPlay would be locked out until something else triggers
    -- a turn change. Treat it as a fresh-session local-only flag.
    localPlayedThisTrick = true,
    -- Timer-backed banner ("Next dealer: NAME"). The C_Timer.After
    -- that clears it doesn't survive /reload, so persisting the field
    -- would leave a stale banner that never auto-dismisses.
    redealing = true,
    -- Takweesh result banner is also transient — its display lifetime
    -- ends when the next round starts (handled by ApplyStart).
    takweeshResult = true,
    -- AKA call banner is per-trick; its lifetime ends with the trick.
    -- We rebuild s.playedCardsThisRound from s.tricks on resync, so
    -- both fields are transient w.r.t. SaveSession.
    akaCalled = true,
    playedCardsThisRound = true,
    -- Meld-display hold timer is wall-clock-based; restoring it after
    -- a /reload would either fire stale or expire instantly. UI cue
    -- only, drop on save.
    meldHoldUntil = true,
    -- SWA outcome is a per-round banner struct; cleared at next
    -- ApplyStart, no need to persist.
    swaResult = true,
    -- Pending SWA permission request — ephemeral state alive only
    -- while opponents are voting. Cleared on accept/deny resolution
    -- or round transition. Don't persist.
    swaRequest = true,
    -- Brief "SWA denied" toast struct, cleared by C_Timer 3 seconds
    -- after the deny. UI cue only.
    swaDenied = true,
    -- Round-end display state: only meaningful within the round
    -- they describe. After /reload they'd be stale and could
    -- surface a previous round's banner unintentionally.
    lastRoundResult = true,
    lastRoundDelta  = true,
    lastTrick       = true,
    -- NOTE: preemptEligible and pendingPreemptContract are NOT
    -- transient. The HOST needs them to survive a /reload mid-
    -- PHASE_PREEMPT — without persistence the host can't continue
    -- the window and would soft-lock until the 60s AFK fires (and
    -- even then, _FinalizePreempt wouldn't fire because pending-
    -- PreemptContract is gone). Non-host clients overwrite their
    -- copies on resync from the host (see N.SendResyncRes replay
    -- block).
}

function S.SaveSession()
    WHEREDNGNDB = WHEREDNGNDB or {}
    if s.phase == K.PHASE_IDLE or s.phase == K.PHASE_LOBBY
       or s.phase == K.PHASE_GAME_END then
        WHEREDNGNDB.session = nil
        return
    end
    local snap = {}
    for k, v in pairs(s) do
        if not TRANSIENT_FIELDS[k] then snap[k] = v end
    end
    -- Tag with the saving character's name. WHEREDNGNDB is per-account,
    -- so on a different character the restore must reject this session
    -- — otherwise we'd resurface character A's hand for character B.
    WHEREDNGNDB.session = {
        ts    = time(),
        owner = s.localName,
        state = snap,
    }
end

function S.RestoreSession()
    if not WHEREDNGNDB or not WHEREDNGNDB.session then return false end
    local sess = WHEREDNGNDB.session
    if not sess.ts or (time() - sess.ts) > 3600 then
        WHEREDNGNDB.session = nil
        return false
    end
    -- Cross-character guard. WHEREDNGNDB is per-account; a session
    -- saved by character A must not restore on character B.
    if sess.owner and s.localName and sess.owner ~= s.localName then
        return false
    end
    if not sess.state then return false end
    -- Hard-reset s, then overlay the saved fields. Without the wipe a
    -- field that was nil at save time would carry over from reset()'s
    -- defaults instead of being explicitly absent.
    for k in pairs(s) do s[k] = nil end
    for k, v in pairs(sess.state) do s[k] = v end
    -- v0.2.0 upgrader: the escalation chain rewrite removed the
    -- `redoubled` rung and the `belrePending` window. A pre-v0.2.0
    -- session restored on a v0.2.0+ install would carry these stale
    -- fields and confuse the dispatcher (especially if the saved
    -- phase was REDOUBLE). Strip them and bump REDOUBLE → DOUBLE so
    -- the eligible defender can act fresh. Stale `redoubled=true` on
    -- a multi-rung contract just gets cleared — Triple/Four/Gahwa
    -- flags supersede it in the new chain.
    if s.contract then
        s.contract.redoubled = nil
        s.contract.belOpen    = s.contract.belOpen    or false
        s.contract.tripleOpen = s.contract.tripleOpen or false
        s.contract.fourOpen   = s.contract.fourOpen   or false
    end
    s.belrePending = nil
    if s.phase == "redouble" then s.phase = K.PHASE_DOUBLE end
    -- A few field defaults need to be non-nil so the rest of the code
    -- can index them without nil-check noise.
    s.hand         = s.hand         or {}
    s.bids         = s.bids         or {}
    s.tricks       = s.tricks       or {}
    s.meldsByTeam  = s.meldsByTeam  or { A = {}, B = {} }
    s.meldsDeclared= s.meldsDeclared or {}
    s.cumulative   = s.cumulative   or { A = 0, B = 0 }
    s.seats        = s.seats        or { [1]=nil, [2]=nil, [3]=nil, [4]=nil }
    -- Rebuild the played-cards set from the restored trick history so
    -- the AKA helper sees the correct unplayed-card frontier after a
    -- /reload. Includes the partial in-flight trick (s.trick.plays).
    s.playedCardsThisRound = {}
    for _, tr in ipairs(s.tricks or {}) do
        for _, p in ipairs(tr.plays or {}) do
            s.playedCardsThisRound[p.card] = true
        end
    end
    if s.trick and s.trick.plays then
        for _, p in ipairs(s.trick.plays) do
            s.playedCardsThisRound[p.card] = true
        end
    end
    return true
end

-- Rehydrate session state from a host-built snapshot. Wire format
-- (top-level fields separated by '|', see N.SendResyncRes):
--   gameID | phase | dealer | round | turn | turnKind |
--   ctype | ctrump | cbidder | cdbl | crdbl |
--   cumA | cumB | paused |
--   seat1Name | seat2Name | seat3Name | seat4Name |
--   bid1 | bid2 | bid3 | bid4
-- Anything not in the snapshot (private hand, in-flight trick plays,
-- meld declarations, full trick history) is filled in by subsequent
-- broadcasts/whispers — the host re-whispers MSG_HAND right after
-- SendResyncRes so the receiver's own cards arrive promptly.
function S.ApplyResyncSnapshot(gameID, payload)
    if not gameID or gameID == "" then return end
    if not payload or payload == "" then return end
    -- Wire layout (matches packSnapshot in Net.lua) — v0.1.34 escalation
    -- rewrite removed the `redoubled` slot, so the layout is now:
    --   1  gameID
    --   2  phase
    --   3  dealer
    --   4  roundNumber
    --   5  turn
    --   6  turnKind
    --   7  contract.type
    --   8  contract.trump
    --   9  contract.bidder
    --  10  doubled         (×2)
    --  11  tripled         (×3)
    --  12  foured          (×4)
    --  13  gahwa           (match-win)
    --  14  contract.tripleOpen   (1 = open / next rung allowed)
    --  15  contract.fourOpen
    --  16  cumulative.A
    --  17  cumulative.B
    --  18  paused
    --  19  bidRound
    --  20..23 seat names
    --  24..27 bids
    local f = {}
    local i = 1
    for chunk in payload:gmatch("([^|]*)|?") do
        f[i] = chunk; i = i + 1
        if i > 27 then break end
    end
    if (f[1] or "") ~= gameID then return end

    s.gameID      = gameID
    s.phase       = (f[2] ~= "" and f[2]) or s.phase
    s.dealer      = tonumber(f[3]) or s.dealer
    s.roundNumber = tonumber(f[4]) or s.roundNumber

    local turnNum = tonumber(f[5]) or 0
    s.turn        = (turnNum > 0) and turnNum or nil
    s.turnKind    = (f[6] ~= "" and f[6]) or nil

    local ctype = f[7]
    if ctype and ctype ~= "" then
        s.contract = {
            type       = ctype,
            trump      = (f[8] ~= "" and f[8]) or nil,
            bidder     = tonumber(f[9]) or 0,
            doubled    = f[10] == "1",
            tripled    = f[11] == "1",
            foured     = f[12] == "1",
            gahwa      = f[13] == "1",
            tripleOpen = f[14] == "1",
            fourOpen   = f[15] == "1",
        }
    else
        s.contract = nil
    end

    s.cumulative = s.cumulative or { A = 0, B = 0 }
    s.cumulative.A = tonumber(f[16]) or 0
    s.cumulative.B = tonumber(f[17]) or 0
    s.paused       = (f[18] == "1")
    s.bidRound     = tonumber(f[19]) or s.bidRound or 1

    -- Seats: rebuild minimal info; isBot defaults to false here, the
    -- next SendLobby from the host will overwrite with full info.
    s.seats = s.seats or {}
    for seat = 1, 4 do
        local nm = f[19 + seat] or ""
        if nm ~= "" then
            s.seats[seat] = s.seats[seat] or {}
            s.seats[seat].name = nm
            -- Re-derive our own seat number now that we know the names.
            if s.localName and nm == s.localName then
                s.localSeat = seat
                s.isHost = false  -- we're definitely not host (we asked).
            end
        else
            s.seats[seat] = nil
        end
    end

    s.bids = {}
    for seat = 1, 4 do
        local b = f[23 + seat]
        if b and b ~= "" then s.bids[seat] = b end
    end

    -- Round history is not snapshotted; it arrives via replayed
    -- MSG_MELD / MSG_TRICK broadcasts right after the snapshot.
    -- Clear any local state (including RestoreSession leftovers)
    -- so the replayed history doesn't duplicate.
    s.tricks       = {}
    s.meldsByTeam  = { A = {}, B = {} }
    s.meldsDeclared= {}
    s.playedCardsThisRound = {}

    -- Audit fix: clear remaining transient round state so stale
    -- per-trick banners (AKA, Takweesh outcome, SWA result, redeal
    -- announcement) and pre-emption state from before the rejoin
    -- don't leak through the snapshot. The host will re-broadcast any
    -- of these that are still active right after the snapshot.
    s.akaCalled             = nil
    s.lastTrick             = nil
    s.takweeshResult        = nil
    s.swaResult             = nil
    s.swaRequest            = nil
    s.swaDenied             = nil
    s.redealing             = nil
    s.pendingPreemptContract= nil
    s.preemptEligible       = nil
    s.lastRoundResult       = nil
    s.lastRoundDelta        = nil

    -- Trick / hand are not snapshotted; they'll arrive via the next
    -- play broadcast and the re-whispered MSG_HAND respectively.
    s.trick = nil
    s.hand  = s.hand or {}
end
reset()
S.Reset = reset

-- -- Session helpers ----------------------------------------------------

-- Canonicalize a player name to "Name-Realm" form. CHAT_MSG_ADDON
-- senders are always in this form; GetUnitName("player", true) may
-- return just "Name" in same-realm scenarios in some clients.
function S.NormalizeName(name)
    if not name or name == "" then return name end
    if name:find("-", 1, true) then return name end
    local realm = GetRealmName and GetRealmName() or ""
    realm = realm:gsub("%s+", "")
    if realm == "" then return name end
    return name .. "-" .. realm
end

function S.SetLocalName(name) s.localName = S.NormalizeName(name) end

function S.LocalSeat() return s.localSeat end

function S.IsMyTurn()
    return s.localSeat ~= nil and s.turn == s.localSeat
end

function S.MyHand() return s.hand end

function S.SeatOf(name)
    if not name then return nil end
    for seat, info in pairs(s.seats) do
        if info and info.name == name then return seat end
    end
    return nil
end

-- Generate a 6-char game id. Crypto-grade not required; just unique-ish
-- so old "host" announcements don't get mistaken for new games.
local function newGameID()
    local chars = "ABCDEFGHJKMNPQRSTUVWXYZ23456789"
    local id = {}
    for _ = 1, 6 do
        local i = math.random(1, #chars)
        id[#id + 1] = chars:sub(i, i)
    end
    return table.concat(id)
end

-- -- Lobby (host) ------------------------------------------------------

function S.HostBeginLobby()
    if not s.localName then return end
    -- Save localName because reset() clears it; without this the
    -- subsequent assignments (hostName, seats[1].name) end up nil and
    -- the host's own seat shows as empty in their lobby and over the
    -- wire — friend sees no host either, and the lobby can't start.
    local saved = s.localName
    reset()
    s.localName = saved
    s.phase     = K.PHASE_LOBBY
    s.isHost    = true
    s.hostName  = s.localName
    s.gameID    = newGameID()
    s.localSeat = 1
    s.seats[1]  = { name = s.localName }
    -- Persist for resync-on-reload. Cleared in S.Reset.
    if WHEREDNGNDB then WHEREDNGNDB.lastGameID = s.gameID end
    log("HostBeginLobby gameID=%s", s.gameID)
    return s.gameID
end

-- Host receives a join request for our game.
function S.HostHandleJoin(name)
    if not s.isHost or s.phase ~= K.PHASE_LOBBY then return end
    if not name or name == s.localName then return end
    -- already seated?
    for _, info in pairs(s.seats) do
        if info and info.name == name then return end
    end
    -- find first empty seat (2..4)
    for seat = 2, 4 do
        if not s.seats[seat] then
            s.seats[seat] = { name = name }
            log("HostHandleJoin %s -> seat %d", name, seat)
            return seat
        end
    end
end

-- Host kicks a seat (e.g. someone who left).
function S.HostKickSeat(seat)
    if not s.isHost or seat == 1 then return end
    s.seats[seat] = nil
end

-- Fill all empty non-host seats with bot stubs. Bots have a placeholder
-- name (so the host's UI can label them) and an isBot flag that the
-- networking and UI paths key off of.
function S.HostAddBots()
    if not s.isHost or s.phase ~= K.PHASE_LOBBY then return 0 end
    local added = 0
    for seat = 2, 4 do
        if not s.seats[seat] then
            -- Space (not hyphen) so the realm-stripping shortName helper
            -- in the UI doesn't truncate "Bot 2" to "Bot".
            s.seats[seat] = { name = "Bot " .. seat, isBot = true }
            added = added + 1
        end
    end
    return added
end

-- Swap two seats so the host can re-team players. Teams are derived
-- from seat parity (seats 1+3 = Team A, seats 2+4 = Team B), so moving
-- a player one seat over flips their team. Host-only; lobby-only.
-- localSeat is updated for whichever swapped seat hosts the local
-- player so the UI keeps tracking the right cards.
function S.HostSwapSeats(seatA, seatB)
    if not s.isHost or s.phase ~= K.PHASE_LOBBY then return false end
    if not seatA or not seatB or seatA == seatB then return false end
    if seatA < 1 or seatA > 4 or seatB < 1 or seatB > 4 then return false end
    s.seats[seatA], s.seats[seatB] = s.seats[seatB], s.seats[seatA]
    -- Re-derive localSeat in case we moved ourselves (or a bot/peer
    -- who's the local player) into a different seat.
    if s.localName then s.localSeat = S.SeatOf(s.localName) end
    return true
end

function S.IsSeatBot(seat)
    return s.seats[seat] and s.seats[seat].isBot or false
end

function S.LobbyFull()
    return s.seats[1] and s.seats[2] and s.seats[3] and s.seats[4]
end

-- -- Apply* (idempotent state updates from network) -------------------

function S.ApplyLobby(gameID, seatNames, botMask)
    -- seatNames: array of 4 names, possibly empty strings.
    -- botMask: optional 4-char string of "0"/"1" indicating which
    -- seats are bots. Without this, non-host clients couldn't tell
    -- bots from humans, and authorizeSeat would reject any
    -- host-signed bot bid/play.
    --
    -- We accept lobby updates during any "passive" phase: IDLE, LOBBY,
    -- SCORE and GAME_END. Mid-active-play (DEAL/BID/PLAY/etc.) we
    -- ignore the update — a stale broadcast can't tear down a live hand.
    local p = s.phase
    local passive = (p == K.PHASE_IDLE or p == K.PHASE_LOBBY
                  or p == K.PHASE_SCORE or p == K.PHASE_GAME_END)
    if not passive then return end

    -- New game (different gameID and we have one) means the previous
    -- game is over and the host has started fresh. Wipe leftover round
    -- artifacts (contract, hand, tricks, score banner, winner) so the
    -- new lobby UI doesn't bleed through. Preserve session-level
    -- identity (localName, target, persisted team-name labels) — the
    -- usual reset() clears those, so we save and restore.
    local newGame = (s.gameID and s.gameID ~= "" and s.gameID ~= gameID)
                 or (p == K.PHASE_SCORE or p == K.PHASE_GAME_END)
    if newGame then
        local savedName   = s.localName
        local savedTarget = s.target
        local savedNames  = s.teamNames
        local savedPeers  = s.peerVersions
        local savedHost   = s.hostName
        local savedPend   = s.pendingHost
        S.Reset()
        s.localName     = savedName
        s.target        = savedTarget or s.target
        s.teamNames     = savedNames or s.teamNames
        s.peerVersions  = savedPeers or {}
        s.hostName      = savedHost
        s.pendingHost   = savedPend
    end

    s.phase  = K.PHASE_LOBBY
    s.gameID = gameID
    for i = 1, 4 do
        local n = seatNames[i]
        if n and n ~= "" then
            local isBot = botMask and botMask:sub(i, i) == "1"
            s.seats[i] = { name = n, isBot = isBot or nil }
        else
            s.seats[i] = nil
        end
    end
    -- find ourselves
    if s.localName then s.localSeat = S.SeatOf(s.localName) end
    if s.seats[1] then s.hostName = s.seats[1].name end
    -- Persist on the joining side too — this is the first time a
    -- non-host learns the gameID, so capture it for /reload resync.
    if WHEREDNGNDB and s.localSeat then WHEREDNGNDB.lastGameID = gameID end
    -- Once we're seated in the announced lobby, the pendingHost record
    -- has done its job. Clearing it prevents a stale entry from masking
    -- a future host announcement that arrives before any lobby update.
    if s.localSeat then s.pendingHost = nil end
end

function S.ApplyStart(roundNumber, dealer)
    -- Loopback double-apply is prevented by fromSelf skip in handlers,
    -- so we always reset round state here. Re-applying mid-round would
    -- only happen via rare network duplicates; acceptable in v1.
    local newRoundNum = roundNumber or (s.roundNumber + 1)
    s.roundNumber  = newRoundNum
    s.dealer       = dealer or s.dealer
    s.bidCard      = nil
    s.bidRound     = 1
    s.bids         = {}
    s.contract     = nil
    -- Only wipe the hand if the stored hand is for a different round.
    -- The hand whisper (WHISPER channel) and the Start broadcast (PARTY
    -- channel) have no cross-channel ordering guarantee — if WHISPER
    -- arrives first, the hand was already set for the new round and we
    -- mustn't wipe it. ApplyHand stores s.handRound to mark this.
    if s.handRound ~= newRoundNum then
        s.hand = {}
    end
    s.hostHands    = nil
    s.trick        = nil
    s.tricks       = {}
    s.meldsByTeam  = { A = {}, B = {} }
    s.meldsDeclared= {}
    -- Audit C17 fix: peek allowance must reset at NEW round start, not
    -- only at previous round-end. Without this, abandoned-round and
    -- mid-reload edge cases could leave peekedThisRound=true when a
    -- fresh round begins, hiding the peek button.
    s.peekedThisRound = false
    -- Per-hand played-cards set used by the AKA helper to compute the
    -- highest unplayed card in any non-trump suit. Reset every round.
    s.playedCardsThisRound = {}
    -- Latest AKA call display state. {seat, suit} while a call is in
    -- effect (banner shown). Cleared at the start of the next trick so
    -- the visual cue doesn't linger past its tactical relevance.
    s.akaCalled    = nil
    -- Per-seat meld-display hold timer. Trick 2 normally shows each
    -- seat's melds only while it's that seat's turn — but the LAST
    -- player in trick 2 has no "next turn" to clip them, so we hold
    -- their strip visible for 4 seconds via a GetTime() timestamp.
    s.meldHoldUntil = {}
    s.phase        = K.PHASE_DEAL1
    -- A redeal announcement banner (all-pass) is dismissed by the
    -- arrival of a real ApplyStart for the new round.
    s.redealing    = nil
    -- Last hand's takweesh / SWA banners cleared at next round.
    s.takweeshResult = nil
    s.swaResult      = nil
    -- Round-start "Awal" announcement. Delayed half a second so the
    -- new hand + bid card finish landing visually before the voice
    -- fires — without the delay, clicking "Next Round" plays Awal
    -- immediately while the previous round's score banner is still
    -- on screen, which feels off.
    if B.Sound and B.Sound.Cue then
        C_Timer.After(0.5, function() B.Sound.Cue(K.SND_VOICE_AWAL) end)
    end
end

function S.ApplyHand(cards, forRound)
    -- Reject stale whispers from old rounds (e.g. delayed delivery
    -- crossing a round boundary) so we don't show a previous hand.
    if forRound and s.roundNumber and forRound < s.roundNumber then
        return
    end
    s.hand = cards or {}
    -- Remember which round this hand belongs to so a late-arriving
    -- ApplyStart for the same round doesn't wipe it (see ApplyStart).
    s.handRound = forRound or s.roundNumber
end

function S.ApplyBidCard(card)
    s.bidCard = card
end

function S.ApplyTurn(seat, kind)
    local prevTurn = s.turn
    s.turn = seat
    s.turnKind = kind
    -- Clear the local "I just played this trick" guard whenever turn
    -- changes. By the time turn lands on the local player again, the
    -- flag has been reset and they can act normally.
    s.localPlayedThisTrick = nil
    log("turn: seat=%d kind=%s", seat or -1, tostring(kind))

    -- Saudi meld-display rule (trick 2 only):
    --   • When a declarer's PLAY turn starts in the SECOND trick,
    --     their cards become public for 5 seconds, then hide.
    --   • Only declarers on the WINNING team show — Pagat: "the
    --     opposing team are not allowed to show or score for any
    --     projects." A teammate of the winning declarer may also
    --     show their meld; this is implicit in the team-membership
    --     check below.
    --   • In a tie or with no melds, no team reveals.
    -- Trick 1 stays text-announcement-only; tricks 3+ never show.
    if kind == "play" and #(s.tricks or {}) == 1
       and prevTurn ~= seat
       and S.SeatHasDeclaredMelds and S.SeatHasDeclaredMelds(seat) then
        local verdict = S.MeldVerdict and S.MeldVerdict() or nil
        if verdict and verdict ~= "tie"
           and R.TeamOf(seat) == verdict then
            s.meldHoldUntil = s.meldHoldUntil or {}
            local now = (GetTime and GetTime()) or 0
            s.meldHoldUntil[seat] = now + 5
            if C_Timer and C_Timer.After then
                C_Timer.After(5.05, function()
                    if B.UI and B.UI.Refresh then B.UI.Refresh() end
                end)
            end
        end
    end
    -- Audio: ping when our turn arrives (transition into our seat).
    if seat == s.localSeat and prevTurn ~= seat then
        if B.Sound and B.Sound.Cue then B.Sound.Cue(K.SND_TURN_PING) end
        -- Schedule the AFK pre-warn (T-10s) for our turn.
        if B.Net and B.Net.StartLocalWarn then
            B.Net.StartLocalWarn(kind)
        end
    elseif seat ~= s.localSeat and B.Net and B.Net.CancelLocalWarn then
        B.Net.CancelLocalWarn()
    end
end

function S.ApplyBid(seat, bid)
    -- Idempotence at the apply layer. Even though every wire-side
    -- handler dedupes on `s.bids[seat] ~= nil` already, the AUDIO cue
    -- below previously fired any time ApplyBid was invoked — so a
    -- harmless re-apply (e.g. AFK-timeout firing right as the player
    -- clicks Pass, or a delayed loopback that bypassed fromSelf) would
    -- play "بَسْ" twice. Skip same-bid replays here.
    if s.bids[seat] == bid then return end
    s.bids[seat] = bid
    log("bid seat=%d bid=%s", seat, bid)
    -- Voice cue per bid type, using the bundled ElevenLabs OGGs.
    -- Saudi convention: round-1 pass is "بَسْ", round-2 pass is "ولا"
    -- ("nothing / no preference" — the player has no Hokm-suit choice
    -- they want to commit to either).
    if B.Sound and B.Sound.Cue and bid then
        local snd
        if bid == K.BID_PASS then
            -- Round 1 has a Sun-overcall window: every seat bids even
            -- after someone has already called Hokm/Sun. Those late
            -- passes are confirming an existing contract, not opening
            -- the bidding — playing "بَسْ" for each one creates noisy
            -- repetition right after the contract voice. Suppress the
            -- pass voice once a non-pass bid is already on the table.
            local anyNonPass = false
            for seat2, b in pairs(s.bids) do
                if seat2 ~= seat and b and b ~= K.BID_PASS then
                    anyNonPass = true; break
                end
            end
            if not anyNonPass then
                snd = (s.bidRound == 2) and K.SND_VOICE_WLA or K.SND_VOICE_PASS
            end
        elseif bid == K.BID_SUN then     snd = K.SND_VOICE_SUN
        elseif bid == K.BID_ASHKAL then  snd = K.SND_VOICE_ASHKAL
        elseif bid:sub(1, #K.BID_HOKM) == K.BID_HOKM then
            snd = K.SND_VOICE_HOKM
        end
        if snd then B.Sound.Cue(snd) end
    end
end

function S.ApplyContract(bidder, btype, trump)
    s.contract = {
        type    = btype,
        trump   = trump ~= "" and trump or nil,
        bidder  = bidder,
        doubled = false,
        tripled = false,
        foured  = false,
        gahwa   = false,
        -- Open/Closed (التربيع) flags. Default open=true so legacy
        -- callers that don't pass openFlag advance to the next rung
        -- (matches old behaviour).
        belOpen    = false,  -- defenders chose to allow the next rung
        tripleOpen = false,  -- bidder chose to allow defenders' Four
        fourOpen   = false,  -- defenders chose to allow bidder's Gahwa
    }
    s.phase = K.PHASE_DOUBLE
    -- Bidding is over. Clear turn/turnKind so the UI turn-glow doesn't
    -- linger on the last bidder and so the dispatcher can't read stale
    -- turn state during the escalation windows.
    s.turn = nil
    s.turnKind = nil
    -- defenders are partner-pair opposite to bidder
    s.belPending = {}
    local oppA = bidder == 1 or bidder == 3
    if oppA then s.belPending = { 2, 4 } else s.belPending = { 1, 3 } end
    log("contract bidder=%d type=%s trump=%s", bidder, btype, tostring(trump))
    -- Audio: contract finalized.
    if B.Sound and B.Sound.Cue then B.Sound.Cue(K.SND_CONTRACT) end
    -- AFK pre-warn for the bel decision (defender at NextSeat(bidder)).
    if B.Net and B.Net.StartLocalWarn then B.Net.StartLocalWarn("bel") end
end

-- Bel (×2) — defenders' first escalation.
-- `open` (default true): allow bidder's Triple counter; if false,
-- the chain stops here ("Bel & closed" / Bel-and-end-here).
function S.ApplyDouble(seat, open)
    if not s.contract then return end
    s.contract.doubled = true
    s.contract.belOpen = (open ~= false)
    s.belPending = nil
    s.turn = nil
    s.turnKind = nil
    -- Sun rule (Saudi): "في الصن لايوجد الثري والفور والقهوة" — Sun
    -- has only Bel; no Triple/Four/Gahwa. Sun + Bel goes straight to
    -- PLAY regardless of open/closed (no rung to advance to).
    if s.contract.type == K.BID_SUN then
        s.phase = K.PHASE_PLAY
        return
    end
    -- Closed: chain ends; no Triple window.
    if not s.contract.belOpen then
        s.phase = K.PHASE_PLAY
        return
    end
    s.phase = K.PHASE_TRIPLE
    -- AFK pre-warn for the triple decision (the bidder).
    if B.Net and B.Net.StartLocalWarn then B.Net.StartLocalWarn("triple") end
end

-- Triple (×3) — bidder's counter to a Bel.
-- `open` (default true): allow defenders' Four counter.
function S.ApplyTriple(seat, open)
    if not s.contract then return end
    s.contract.tripled = true
    s.contract.tripleOpen = (open ~= false)
    s.turn = nil
    s.turnKind = nil
    if B.Sound and B.Sound.Cue then B.Sound.Cue(K.SND_VOICE_TRIPLE) end
    if not s.contract.tripleOpen then
        s.phase = K.PHASE_PLAY
    else
        s.phase = K.PHASE_FOUR
        -- Audit fix: AFK pre-warn for the Four decision (defender).
        if B.Net and B.Net.StartLocalWarn then B.Net.StartLocalWarn("four") end
    end
end

-- Four (×4) — defenders' counter to a Triple.
-- `open` (default true): allow bidder's Gahwa counter.
function S.ApplyFour(seat, open)
    if not s.contract then return end
    s.contract.foured = true
    s.contract.fourOpen = (open ~= false)
    s.turn = nil
    s.turnKind = nil
    if B.Sound and B.Sound.Cue then B.Sound.Cue(K.SND_VOICE_FOUR) end
    if not s.contract.fourOpen then
        s.phase = K.PHASE_PLAY
    else
        s.phase = K.PHASE_GAHWA
        -- Audit fix: AFK pre-warn for the Gahwa decision (bidder).
        if B.Net and B.Net.StartLocalWarn then B.Net.StartLocalWarn("gahwa") end
    end
end

-- Gahwa / Coffee (match-win) — bidder's terminal escalation.
-- Per "نظام الدبل في لعبة البلوت", a successful Gahwa wins the entire
-- MATCH for the caller's team (cumulative jumps to target). A failed
-- Gahwa hands the match to defenders. Round-multiplier semantics from
-- the old ×32 rung are gone — see R.ScoreRound for the special branch.
function S.ApplyGahwa(seat)
    if not s.contract then return end
    s.contract.gahwa = true
    -- No further escalation; HostFinishDeal proceeds to PLAY.
    s.turn = nil
    s.turnKind = nil
    if B.Sound and B.Sound.Cue then B.Sound.Cue(K.SND_VOICE_GAHWA) end
end

function S.ApplyMeld(seat, kind, suit, top, encodedCards)
    -- Saudi rule: melds must be declared during trick 1 only. Reject
    -- any wire-side declaration that arrives after trick 1 has closed
    -- (#s.tricks >= 1) — this is the authoritative gate that backs up
    -- the UI / Bot.PickMelds / S.GetMeldsForLocal trick-1 locks.
    if (#(s.tricks or {})) >= 1 then return end
    local team = R.TeamOf(seat)
    s.meldsByTeam[team] = s.meldsByTeam[team] or {}
    -- Idempotent: dedupe by (seat, kind, top, suit).
    local nsuit = (suit ~= "" and suit) or nil
    for _, m in ipairs(s.meldsByTeam[team]) do
        if m.declaredBy == seat and m.kind == kind and m.top == top
           and (m.suit or nil) == nsuit then return end
    end
    local cards = C.DecodeHand(encodedCards)
    -- Mirror R.DetectMelds value derivation. Constants only define
    -- MELD_CARRE_OTHER (T/Q/K/J — all 100 raw) and MELD_CARRE_A_SUN
    -- (Aces in Sun only — 200 raw). 9/8/7 carrés don't score.
    local value
    if kind == "seq3" then value = K.MELD_SEQ3
    elseif kind == "seq4" then value = K.MELD_SEQ4
    elseif kind == "seq5" then value = K.MELD_SEQ5
    elseif kind == "carre" then
        if K.CARRE_RANKS[top] then
            if top == "A" then
                if s.contract and s.contract.type == K.BID_SUN then
                    value = K.MELD_CARRE_A_SUN     -- "Four Hundred", Sun only
                end
                -- Hokm 4-Aces: doesn't score (per Pagat-strict)
            else
                value = K.MELD_CARRE_OTHER          -- T, K, Q, J → 100 raw
            end
        end
        -- 9 carrés (and 8/7) drop through with value=nil → not scored
    end
    if not value then return end
    table.insert(s.meldsByTeam[team], {
        kind = kind, value = value, suit = nsuit,
        top = top, cards = cards, len = #cards, declaredBy = seat,
    })
end

-- After deal-3, transition to play and seat-after-dealer leads.
function S.ApplyPlayPhase()
    s.phase = K.PHASE_PLAY
    s.trick = { leadSuit = nil, plays = {} }
end

function S.ApplyPlay(seat, card)
    if not s.trick then s.trick = { leadSuit = nil, plays = {} } end
    -- One-play-per-seat-per-trick: reject ANY second play from the same
    -- seat in the current trick (not just an identical card). This stops
    -- a rapid-double-click on a non-host's UI from registering two
    -- DIFFERENT cards before the host's SendTurn loopback updates their
    -- IsMyTurn() state. Also defends against tampered clients.
    for _, p in ipairs(s.trick.plays) do
        if p.seat == seat then return end
    end

    -- Host-only: validate this play AGAINST the trick state BEFORE
    -- adding it, and mark .illegal on the play record. Used later by
    -- Takweesh resolution. Other clients leave .illegal nil since they
    -- don't have hostHands to validate.
    local illegal = false
    local illegalWhy
    if s.isHost and s.hostHands and s.hostHands[seat] and s.contract then
        local trickBefore = { leadSuit = s.trick.leadSuit, plays = {} }
        for _, p in ipairs(s.trick.plays) do
            trickBefore.plays[#trickBefore.plays + 1] = p
        end
        local ok, why = R.IsLegalPlay(card, s.hostHands[seat], trickBefore, s.contract, seat)
        illegal = not ok
        illegalWhy = why
    end

    if #s.trick.plays == 0 then s.trick.leadSuit = C.Suit(card) end
    table.insert(s.trick.plays, {
        seat = seat, card = card,
        illegal = illegal or nil,
        illegalReason = (illegal and illegalWhy) or nil,
    })
    -- Track every played card for the AKA helper. We key by the 2-char
    -- card string (e.g. "AS"). The set is rebuilt on resync from
    -- s.tricks + s.trick.plays so this purely-additive write is safe.
    s.playedCardsThisRound = s.playedCardsThisRound or {}
    s.playedCardsThisRound[card] = true

    -- (Meld card reveal is now handled in S.ApplyTurn — see the
    -- 5-second per-turn hold there. ApplyPlay no longer needs to
    -- arm a special last-player timer because every seat in trick 2
    -- gets the same 5-second window when their turn starts.)

    -- Audio: card-rustle on every play. Fires on every client because
    -- ApplyPlay runs on every client when host broadcasts MSG_PLAY.
    if B.Sound and B.Sound.Cue then B.Sound.Cue(K.SND_CARD_PLAY) end

    if seat == s.localSeat then
        for i, c in ipairs(s.hand) do
            if c == card then table.remove(s.hand, i); break end
        end
    end
    if s.isHost and s.hostHands and s.hostHands[seat] then
        for i, c in ipairs(s.hostHands[seat]) do
            if c == card then table.remove(s.hostHands[seat], i); break end
        end
    end
end

function S.ApplyTrickEnd(winner, points)
    if not s.trick or not s.trick.plays or #s.trick.plays == 0 then return end
    -- Audit fix: only accept a complete 4-play trick. A malformed or
    -- partial broadcast (e.g. host bug, replayed mid-trick frame
    -- arriving out of order) would otherwise stamp a 1/2/3-play trick
    -- into s.tricks, corrupting trick history + ScoreRound math.
    if #s.trick.plays ~= 4 then
        L.Debug("state", "ApplyTrickEnd ignored partial trick (%d plays)",
                #s.trick.plays)
        return
    end
    s.trick.winner = winner
    s.trick.points = points
    table.insert(s.tricks, s.trick)
    -- Stash a shallow copy so the last-trick peek button can still show
    -- it after the trick area is cleared (s.trick is reset below).
    s.lastTrick = {
        leadSuit = s.trick.leadSuit, winner = winner, points = points,
        plays = {}
    }
    for _, p in ipairs(s.trick.plays) do
        s.lastTrick.plays[#s.lastTrick.plays + 1] = { seat = p.seat, card = p.card }
        if s.playedCardsThisRound then s.playedCardsThisRound[p.card] = true end
    end
    s.trick = { leadSuit = nil, plays = {} }
    -- AKA banner only persists for the trick it was called on; clear it
    -- so the next trick starts visually clean.
    s.akaCalled = nil
    -- Audio: only ping when OUR team won the trick. Saves the cue for
    -- moments that feel rewarding to the local player.
    if R and R.TeamOf and s.localSeat then
        if R.TeamOf(winner) == R.TeamOf(s.localSeat)
           and B.Sound and B.Sound.Cue then
            B.Sound.Cue(K.SND_TRICK_WON)
        end
    end
end

-- ---------------------------------------------------------------------
-- AKA (إكَهْ) — partner-coordination signal in Hokm contracts.
-- The caller holds the highest unplayed card in a non-trump suit
-- (Sun ranking: A > 10 > K > Q > J > 9 > 8 > 7). Calling AKA tells
-- their teammate not to over-trump, since the trick is already won.
--
-- This is a SOFT signal — it doesn't constrain anyone's legal plays.
-- It just plays a voice cue and shows a banner so the partner can
-- adjust their play.
-- ---------------------------------------------------------------------

-- Sun ranking order (highest first). Used to walk down the AKA ladder
-- as cards fall. The trump-only ranking (RANK_TRUMP_HOKM) doesn't
-- apply here — AKA is by definition called on NON-trump suits.
local AKA_ORDER = { "A", "T", "K", "Q", "J", "9", "8", "7" }

-- Returns the rank string of the highest unplayed card in `suit`,
-- ignoring any cards already in s.playedCardsThisRound. Returns nil
-- if every card in the suit has been played (shouldn't happen mid-hand).
function S.HighestUnplayedRank(suit)
    if not suit or suit == "" then return nil end
    s.playedCardsThisRound = s.playedCardsThisRound or {}
    for _, r in ipairs(AKA_ORDER) do
        if not s.playedCardsThisRound[r .. suit] then
            return r
        end
    end
    return nil
end

-- Walks the local hand and returns {suit, card} for any non-trump suit
-- where the local player holds the current AKA, or nil if the local
-- player doesn't have any AKA available. AKA is only meaningful in
-- HOKM contracts; non-HOKM contracts return nil.
function S.LocalAKAcandidate()
    if not s.contract or s.contract.type ~= K.BID_HOKM then return nil end
    if not s.hand or #s.hand == 0 then return nil end
    local trump = s.contract.trump
    for _, c in ipairs(s.hand) do
        local r = c:sub(1, 1)
        local su = c:sub(2, 2)
        if su ~= trump then
            local top = S.HighestUnplayedRank(su)
            if top and top == r then
                return { suit = su, card = c }
            end
        end
    end
    return nil
end

function S.SeatHasDeclaredMelds(seat)
    if not seat then return false end
    local team = R.TeamOf(seat)
    local list = s.meldsByTeam and s.meldsByTeam[team]
    if not list then return false end
    for _, m in ipairs(list) do
        if m.declaredBy == seat then return true end
    end
    return false
end

-- SWA (سوا) "claim" helper. Returns the residual point value the
-- caller's team would collect if every remaining trick was theirs.
-- Computed as: sum of all remaining card values + last-trick bonus
-- (the last unplayed trick contains the +10 bonus).
-- Used by the host's SWA resolver to score the round.
function S.SWARemainingPoints()
    if not s.contract or not s.hostHands then return 0 end
    local total = 0
    for seat = 1, 4 do
        for _, c in ipairs(s.hostHands[seat] or {}) do
            total = total + (B.Cards.PointValue(c, s.contract) or 0)
        end
    end
    -- Plus any uncollected card points already in the in-progress
    -- trick — they belong to whoever wins THAT trick, which is part
    -- of the caller's claim.
    if s.trick and s.trick.plays then
        for _, p in ipairs(s.trick.plays) do
            total = total + (B.Cards.PointValue(p.card, s.contract) or 0)
        end
    end
    -- Last-trick bonus: if there are still tricks to play, the +10
    -- last-trick is part of the claim.
    local tricksDone = #(s.tricks or {})
    if tricksDone < 8 then total = total + K.LAST_TRICK_BONUS end
    return total
end

function S.ApplyAKA(seat, suit)
    if not seat or not suit or suit == "" then return end
    -- Display state for the rest of the current trick.
    s.akaCalled = { seat = seat, suit = suit }
    -- Voice cue fires on every client. The Sound.Cue path is shared
    -- with the existing escalation cues so timing/ducking matches.
    if B.Sound and B.Sound.Cue then B.Sound.Cue(K.SND_VOICE_AKA) end
end

-- Meld verdict ("A"/"B"/"tie") is fully recomputable from
-- s.meldsByTeam + s.contract via R.CompareMelds, so we don't track it
-- in state or broadcast it. The UI calls this once trick 1 has closed
-- (#s.tricks >= 1) to drive the strip styling.
function S.MeldVerdict()
    if not s.contract then return nil end
    if not s.tricks or #s.tricks < 1 then return nil end
    if not R or not R.CompareMelds then return nil end
    return R.CompareMelds(s.meldsByTeam.A, s.meldsByTeam.B, s.contract)
end

function S.ApplyRoundEnd(addA, addB, totA, totB, sweep, bidderMade)
    s.cumulative.A = totA
    s.cumulative.B = totB
    s.phase = K.PHASE_SCORE
    s.lastRoundDelta = { A = addA, B = addB }
    -- Reset peek allowance for the next hand
    s.peekedThisRound = false
    -- Round is over; nobody is "up". Clears stale UI glow on whichever
    -- seat won the last trick.
    s.turn = nil
    s.turnKind = nil
    -- Audit fix: BALOOT fanfare for AL-KABOOT (sweep) or contract
    -- failure now fires on EVERY client, not just the host. The
    -- sweep / bidderMade flags arrive via MSG_ROUND (broadcast by
    -- the host's SendRound). Pre-v0.3.0 hosts and Takweesh/SWA call
    -- sites pass nil for both — treat as no-fanfare. Only fire when
    -- we have an explicit signal (sweep set, or bidderMade==false).
    -- (Re-audit V16/V10/V9 finding: the old `bidderMade==false`
    -- check fired on the absent case too because nil ~= false.)
    if B.Sound and B.Sound.Cue
       and (sweep ~= nil or bidderMade == false) then
        B.Sound.Cue(K.SND_BALOOT)
    end
end

-- Stash the full round-result object on the host so the round-end
-- summary panel can show details (cards, melds, multiplier, sweep, etc.)
-- The wire carries the headline totals + sweep/bidderMade flags via
-- MSG_ROUND; this struct is host-only state.
function S.ApplyRoundResult(result)
    s.lastRoundResult = result
    -- Fanfare moved to S.ApplyRoundEnd so every client hears it on
    -- MSG_ROUND receipt — see audit fix above.
end

function S.ApplyGameEnd(winnerTeam)
    -- Idempotent re-apply: if we're already in GAME_END with the
    -- same winner, skip — prevents the BALOOT-fanfare cue from
    -- double-firing on a duplicate broadcast (host loopback +
    -- _OnGameEnd from another client).
    if s.phase == K.PHASE_GAME_END and s.winner == winnerTeam then
        return
    end
    s.phase = K.PHASE_GAME_END
    s.winner = winnerTeam
end

-- -- Host-only computation -------------------------------------------

function S.HostDealInitial()
    if not s.isHost then return end
    local deck = C.NewDeck()
    C.Shuffle(deck, math.floor(GetTime() * 1000) % 1e9)
    local hands = { {}, {}, {}, {} }
    for seat = 1, 4 do hands[seat] = C.DealCount(deck, 5) end
    local bidCard = table.remove(deck)
    s.hostHands = hands
    s.hostDeckRemainder = deck
    s.bidCard = bidCard
    return hands, bidCard
end

function S.HostDealRest()
    if not s.isHost or not s.hostHands or not s.hostDeckRemainder then return end
    local bidder = s.contract and s.contract.bidder
    local bidCard = s.bidCard

    -- Standard Saudi rule: the face-up bid card belongs to the bidder
    -- and is counted as one of their final 3 cards. The other 11 cards
    -- in the remainder are split: bidder gets 2 more, the other three
    -- seats get 3 each (2 + 9 + 1 bid = 12 cards distributed).
    if bidder and bidCard then
        table.insert(s.hostHands[bidder], bidCard)
        local two = C.DealCount(s.hostDeckRemainder, 2)
        for _, c in ipairs(two) do table.insert(s.hostHands[bidder], c) end
        for seat = 1, 4 do
            if seat ~= bidder then
                local three = C.DealCount(s.hostDeckRemainder, 3)
                for _, c in ipairs(three) do
                    table.insert(s.hostHands[seat], c)
                end
            end
        end
    else
        -- No contract (shouldn't reach here in v1 — redeal handles all-pass).
        table.insert(s.hostDeckRemainder, 1, bidCard)
        for seat = 1, 4 do
            local three = C.DealCount(s.hostDeckRemainder, 3)
            for _, c in ipairs(three) do
                table.insert(s.hostHands[seat], c)
            end
        end
    end
    s.hostDeckRemainder = nil
    return s.hostHands
end

-- Validate that a play from `seat` is legal.
function S.HostValidatePlay(seat, card)
    if not s.isHost then return true end
    if not s.hostHands or not s.hostHands[seat] then return false, "no hand" end
    if s.turn ~= seat then return false, "not your turn" end
    if not s.contract then return false, "no contract" end
    return R.IsLegalPlay(card, s.hostHands[seat], s.trick, s.contract, seat)
end

-- Advance bidding turn or finalize contract.
-- Returns: action ∈ { "next", "contract", "round2", "redeal" }, payload.
-- Parse a bid string into (type, trump). type ∈ {PASS, HOKM, SUN, ASHKAL}.
local function parseBid(b)
    if b == K.BID_PASS then return K.BID_PASS, nil end
    if b == K.BID_SUN then return K.BID_SUN, nil end
    if b == K.BID_ASHKAL then return K.BID_ASHKAL, nil end
    if b and b:sub(1, 4) == K.BID_HOKM then
        return K.BID_HOKM, b:sub(6, 6)
    end
    return nil
end

function S.HostAdvanceBidding()
    if not s.isHost then return end
    if s.contract then return end

    local order = { (s.dealer % 4) + 1, ((s.dealer + 1) % 4) + 1,
                    ((s.dealer + 2) % 4) + 1, s.dealer }

    -- Walk the bidding history in turn order, picking the winning bid
    -- according to round rules.
    --   Round 1: anyone can overcall Hokm with Sun, but the FIRST direct
    --            Sun locks the declarer chair (later direct Sun does not
    --            reassign). Direct Sun can still overcall an Ashkal-Sun.
    --            Wait for all 4 before deciding.
    --   Round 2: same Sun-overcalls-Hokm rule, but Hokm cannot reuse
    --            the originally-flipped suit. Wait for all 4 so a later
    --            seat can Sun-overcall an earlier Hokm.
    local count = 0
    local winning = nil   -- {seat, type, trump}
    for _, seat in ipairs(order) do
        local b = s.bids[seat]
        if b then
            count = count + 1
            local btype, trump = parseBid(b)
            if btype and btype ~= K.BID_PASS then
                if s.bidRound == 1 then
                    if btype == K.BID_SUN then
                        -- Strict Saudi: first DIRECT Sun bid locks.
                        -- A later direct Sun in the same round does
                        -- NOT re-claim the declarer chair from an
                        -- earlier direct Sun. (Sun overcalls Hokm,
                        -- but Sun does not overcall Sun.) A direct
                        -- Sun CAN still overcall an Ashkal-derived
                        -- Sun (where the winner.viaAshkal flag is
                        -- set), since direct Sun reassigns declarer
                        -- to the actual bidder per Saudi convention.
                        local priorDirectSun = winning
                            and winning.type == K.BID_SUN
                            and not winning.viaAshkal
                        if not priorDirectSun then
                            winning = {
                                seat = seat, type = btype, trump = trump,
                                viaAshkal = false,
                            }
                        end
                    elseif btype == K.BID_ASHKAL then
                        -- Ashkal (Saudi): converts the contract to Sun
                        -- with the caller's PARTNER as declarer.
                        -- RESTRICTIONS:
                        --   • Only the 3rd and 4th players in turn
                        --     order may call Ashkal (per "نظام لعبة
                        --     البلوت الأساسي" rule 3 — only seats 3
                        --     & 4 can Ashkal). 1st and 2nd bidders
                        --     can't.
                        --   • A prior direct Sun blocks Ashkal —
                        --     direct Sun already locked the contract
                        --     type, no point in Ashkal.
                        --   • A later direct Sun can still overcall
                        --     Ashkal (reassigns declarer).
                        local bidPosition = 0
                        for i, ord in ipairs(order) do
                            if ord == seat then bidPosition = i; break end
                        end
                        if bidPosition < 3 then
                            -- Silently drop — 1st and 2nd bidders
                            -- can't legally call Ashkal.
                        else
                            local priorSun = false
                            for _, ord in ipairs(order) do
                                if ord == seat then break end
                                if s.bids[ord] == K.BID_SUN then
                                    priorSun = true; break
                                end
                            end
                            if not priorSun then
                                winning = {
                                    seat  = R.Partner(seat),
                                    type  = K.BID_SUN,
                                    trump = nil,
                                    viaAshkal = true,
                                }
                            end
                        end
                    elseif btype == K.BID_HOKM and not winning then
                        winning = { seat = seat, type = btype, trump = trump }
                    end
                else
                    -- Round 2: like round 1, Sun overcalls Hokm. Ashkal
                    -- is NOT available in round 2. Hokm cannot reuse the
                    -- originally-flipped suit (silently dropped if it
                    -- comes through). Round 2 ALSO waits for all 4 bids
                    -- so a later seat can Sun-overcall an earlier Hokm
                    -- — the Saudi convention is "first non-pass wins"
                    -- only for HOKM-vs-HOKM ordering, not for the
                    -- Sun-vs-Hokm overcall window.
                    if btype == K.BID_SUN then
                        local priorDirectSun = winning
                            and winning.type == K.BID_SUN
                        if not priorDirectSun then
                            winning = {
                                seat = seat, type = btype, trump = trump,
                            }
                        end
                    elseif btype == K.BID_HOKM and not winning then
                        local flippedSuit = s.bidCard and C.Suit(s.bidCard) or nil
                        if not (flippedSuit and trump == flippedSuit) then
                            winning = { seat = seat, type = btype, trump = trump }
                        end
                        -- else: silently dropped — same as a pass
                    end
                    -- Ashkal in round 2: silently dropped (also already
                    -- gated upstream).
                end
            end
        end
    end

    -- Round 1 / Round 2: both wait for all 4 bids before resolving.
    -- Sun overcalls Hokm in either round.
    if count >= 4 then
        if winning then
            return "contract", { bidder = winning.seat, type = winning.type, trump = winning.trump }
        end
        if s.bidRound == 1 then return "round2" end
        return "redeal"
    end

    -- Next bidder
    for _, seat in ipairs(order) do
        if not s.bids[seat] then return "next", { seat = seat } end
    end
end

function S.HostBeginRound2()
    s.bidRound = 2
    s.bids = {}
    s.phase = K.PHASE_DEAL2BID
    -- Round-2 bidding starts: announce "ثآني" (Thany / second).
    -- Same 0.5s delay as Awal so the bid-card flip / UI re-render
    -- finishes before the voice plays.
    if B.Sound and B.Sound.Cue then
        C_Timer.After(0.5, function() B.Sound.Cue(K.SND_VOICE_THANY) end)
    end
end

-- ---------------------------------------------------------------------
-- Pre-emption (الثالث "Triple-on-Ace") — earlier-seat right
-- ---------------------------------------------------------------------
-- When a round-2 SUN bid lands and the bid card's rank is A, an EARLIER
-- seat in bidding order may "claim before you" — taking the contract
-- as their own SUN bid. Restrictions per "الثالث" doc:
--   • Must be earlier in turn order than the buyer.
--   • May NOT be the buyer's partner ("can't Triple your partner").
--   • Hokm-on-Ace (someone earlier picked Hokm on the bid card)
--     cancels the right entirely — moot under this code path because
--     the contract type is Sun, not Hokm.
-- The eligible-seat list is built host-side and broadcast as part of
-- the synthetic preempt phase; clients render the "قبلك" button when
-- their seat is in the list.
function S.PreemptEligibleSeats(buyerSeat, bidder)
    if not buyerSeat or not bidder then return {} end
    local out = {}
    -- Bidding order is determined by dealer (dealer+1 acts first).
    -- We collect seats that BID before `buyerSeat` excluding partner
    -- of `buyerSeat`. Use the s.bids map: any seat with a bid (not
    -- nil) in the SAME round that came before buyerSeat in turn order.
    local d = s.dealer or 1
    local order = {
        (d % 4) + 1, ((d + 1) % 4) + 1,
        ((d + 2) % 4) + 1, d,
    }
    local partnerOfBuyer = R.Partner(buyerSeat)
    for _, seat in ipairs(order) do
        if seat == buyerSeat then break end
        if seat ~= partnerOfBuyer then
            -- Only seats with a recorded bid this round are eligible.
            -- (PASS counts — they "saw" the bid card and chose not to
            -- act. They retain pre-emption right.)
            if s.bids and s.bids[seat] ~= nil then
                out[#out + 1] = seat
            end
        end
    end
    return out
end

function S.ApplyPreempt(seat)
    -- Seat claims the contract as a SUN bid. Reassign declarer.
    if not s.preemptEligible then return end
    s.contract = nil
    s.preemptEligible = nil
    s.phase = K.PHASE_DEAL2BID
    if B.Sound and B.Sound.Cue then B.Sound.Cue(K.SND_VOICE_SUN) end
end

function S.ApplyPreemptPass(seat)
    -- One eligible seat declined. Remove from list; if list now empty,
    -- finalize the original bid.
    if not s.preemptEligible then return end
    for i, s2 in ipairs(s.preemptEligible) do
        if s2 == seat then table.remove(s.preemptEligible, i); break end
    end
    if #s.preemptEligible == 0 then
        s.preemptEligible = nil
    end
end

function S.HostScoreRoundResult()
    if not s.isHost then return end
    if not s.contract then return end
    local result = R.ScoreRound(s.tricks, s.contract, s.meldsByTeam)
    return result
end

-- -- Convenience getters --------------------------------------------

function S.GetMeldsForLocal()
    if not s.localSeat or not s.contract then return {} end
    if s.meldsDeclared[s.localSeat] then return {} end
    if s.phase ~= K.PHASE_DEAL3 and s.phase ~= K.PHASE_PLAY then return {} end
    -- Saudi rule: melds must be declared during trick 1 only. Once
    -- trick 1 closes (#s.tricks >= 1), the declaration window is
    -- shut for everyone — even players who haven't yet played their
    -- first card of trick 2. Late declarations are forbidden.
    if (#(s.tricks or {})) >= 1 then return {} end
    local detected = R.DetectMelds(s.hand, s.contract)
    -- Filter out melds this seat already declared so each meld appears
    -- as a button at most once. Match key: (kind, top, suit) — for
    -- carrés the suit is nil/"" on both sides; (or "") normalizes.
    local team = R.TeamOf(s.localSeat)
    local declared = (s.meldsByTeam and s.meldsByTeam[team]) or {}
    local out = {}
    for _, m in ipairs(detected) do
        local already = false
        for _, d in ipairs(declared) do
            if d.declaredBy == s.localSeat
               and d.kind == m.kind
               and d.top == m.top
               and (d.suit or "") == (m.suit or "") then
                already = true; break
            end
        end
        if not already then out[#out + 1] = m end
    end
    return out
end

function S.GetLegalPlays()
    if not s.localSeat or not S.IsMyTurn() or not s.contract then return {} end
    if s.phase ~= K.PHASE_PLAY then return {} end
    local legal = {}
    for _, c in ipairs(s.hand) do
        local ok = R.IsLegalPlay(c, s.hand, s.trick, s.contract, s.localSeat)
        if ok then legal[#legal + 1] = c end
    end
    return legal
end
