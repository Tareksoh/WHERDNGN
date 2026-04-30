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
    s.seats       = { [1]=nil, [2]=nil, [3]=nil, [4]=nil }
    -- round
    s.dealer      = 1
    s.roundNumber = 0
    s.bidCard     = nil
    s.bidRound    = 1
    s.bids        = {}      -- [seat] = "PASS" | "HOKM:S/H/D/C" | "SUN"
    s.contract    = nil     -- {type, trump, bidder, doubled, redoubled}
    s.hand        = {}      -- our private hand
    s.hostHands   = nil     -- host only: [seat]={cards}
    s.turn        = nil
    s.turnKind    = nil     -- "bid" | "double" | "redouble" | "play" | "meld"
    s.trick       = nil     -- {leadSuit, plays}
    s.tricks      = {}
    s.meldsByTeam = { A = {}, B = {} }
    s.meldsDeclared = {}    -- [seat] = true once declared (or skipped)
    s.belPending  = nil     -- seats waiting to choose Bel/skip
    s.belrePending= nil
    -- scores
    s.cumulative  = { A = 0, B = 0 }
    s.target      = 152
    -- pause: host-driven freeze that suspends bot scheduling and AFK
    -- timers without dropping any in-flight state. Network-mirrored.
    s.paused      = false
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
    -- A few field defaults need to be non-nil so the rest of the code
    -- can index them without nil-check noise.
    s.hand         = s.hand         or {}
    s.bids         = s.bids         or {}
    s.tricks       = s.tricks       or {}
    s.meldsByTeam  = s.meldsByTeam  or { A = {}, B = {} }
    s.meldsDeclared= s.meldsDeclared or {}
    s.cumulative   = s.cumulative   or { A = 0, B = 0 }
    s.seats        = s.seats        or { [1]=nil, [2]=nil, [3]=nil, [4]=nil }
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
    local f = {}
    local i = 1
    for chunk in payload:gmatch("([^|]*)|?") do
        f[i] = chunk; i = i + 1
        if i > 22 then break end
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
            type      = ctype,
            trump     = (f[8] ~= "" and f[8]) or nil,
            bidder    = tonumber(f[9]) or 0,
            doubled   = f[10] == "1",
            redoubled = f[11] == "1",
        }
    else
        s.contract = nil
    end

    s.cumulative = s.cumulative or { A = 0, B = 0 }
    s.cumulative.A = tonumber(f[12]) or 0
    s.cumulative.B = tonumber(f[13]) or 0
    s.paused       = (f[14] == "1")

    -- Seats: rebuild minimal info; isBot defaults to false here, the
    -- next SendLobby from the host will overwrite with full info.
    s.seats = s.seats or {}
    for seat = 1, 4 do
        local nm = f[14 + seat] or ""
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
        local b = f[18 + seat]
        if b and b ~= "" then s.bids[seat] = b end
    end

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

function S.IsSeatBot(seat)
    return s.seats[seat] and s.seats[seat].isBot or false
end

function S.LobbyFull()
    return s.seats[1] and s.seats[2] and s.seats[3] and s.seats[4]
end

-- -- Apply* (idempotent state updates from network) -------------------

function S.ApplyLobby(gameID, seatNames)
    -- seatNames: array of 4 names, possibly empty strings
    if s.phase ~= K.PHASE_LOBBY and s.phase ~= K.PHASE_IDLE then
        -- mid-game lobby update is ignored
        return
    end
    s.phase  = K.PHASE_LOBBY
    s.gameID = gameID
    for i = 1, 4 do
        local n = seatNames[i]
        if n and n ~= "" then s.seats[i] = { name = n } else s.seats[i] = nil end
    end
    -- find ourselves
    if s.localName then s.localSeat = S.SeatOf(s.localName) end
    if s.seats[1] then s.hostName = s.seats[1].name end
    -- Persist on the joining side too — this is the first time a
    -- non-host learns the gameID, so capture it for /reload resync.
    if WHEREDNGNDB and s.localSeat then WHEREDNGNDB.lastGameID = gameID end
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
    s.phase        = K.PHASE_DEAL1
    -- Round-start "Awal" announcement.
    if B.Sound and B.Sound.Cue then B.Sound.Cue(K.SND_VOICE_AWAL) end
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
    if B.Sound and B.Sound.Cue and bid then
        local snd
        if bid == K.BID_PASS then        snd = K.SND_VOICE_PASS
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
        type      = btype,
        trump     = trump ~= "" and trump or nil,
        bidder    = bidder,
        doubled   = false,
        redoubled = false,
    }
    s.phase = K.PHASE_DOUBLE
    -- Bidding is over. Clear turn/turnKind so the UI turn-glow doesn't
    -- linger on the last bidder and so the dispatcher can't read stale
    -- turn state during DOUBLE/REDOUBLE.
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

function S.ApplyDouble(seat)
    if not s.contract then return end
    s.contract.doubled = true
    s.belPending  = nil
    s.phase = K.PHASE_REDOUBLE
    -- Bel decision is over; clear stale turn state.
    s.turn = nil
    s.turnKind = nil
    -- bidder team gets Bel-Re option
    local b = s.contract.bidder
    if b == 1 or b == 3 then s.belrePending = { 1, 3 } else s.belrePending = { 2, 4 } end
    -- AFK pre-warn for the bel-re decision (the original bidder).
    if B.Net and B.Net.StartLocalWarn then B.Net.StartLocalWarn("belre") end
end

function S.ApplyRedouble(seat)
    if not s.contract then return end
    s.contract.redoubled = true
    s.belrePending = nil
end

function S.ApplyMeld(seat, kind, suit, top, encodedCards)
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
    if s.isHost and s.hostHands and s.hostHands[seat] and s.contract then
        local trickBefore = { leadSuit = s.trick.leadSuit, plays = {} }
        for _, p in ipairs(s.trick.plays) do
            trickBefore.plays[#trickBefore.plays + 1] = p
        end
        local ok = R.IsLegalPlay(card, s.hostHands[seat], trickBefore, s.contract, seat)
        illegal = not ok
    end

    if #s.trick.plays == 0 then s.trick.leadSuit = C.Suit(card) end
    table.insert(s.trick.plays, { seat = seat, card = card, illegal = illegal or nil })

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
    end
    s.trick = { leadSuit = nil, plays = {} }
    -- Audio: only ping when OUR team won the trick. Saves the cue for
    -- moments that feel rewarding to the local player.
    if R and R.TeamOf and s.localSeat then
        if R.TeamOf(winner) == R.TeamOf(s.localSeat)
           and B.Sound and B.Sound.Cue then
            B.Sound.Cue(K.SND_TRICK_WON)
        end
    end
end

function S.ApplyRoundEnd(addA, addB, totA, totB)
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
end

-- Stash the full round-result object on the host so the round-end
-- summary panel can show details (cards, melds, multiplier, sweep, etc.)
-- The wire still only carries the four totals via MSG_ROUND.
function S.ApplyRoundResult(result)
    s.lastRoundResult = result
    -- Audio fanfare for AL-KABOOT (sweep) or contract failure (BALOOT).
    -- Only the host has lastRoundResult; non-hosts get the cue via the
    -- regular trick-won pings during the hand.
    if result and B.Sound and B.Sound.Cue then
        if result.sweep or result.bidderMade == false then
            B.Sound.Cue(K.SND_BALOOT)
        end
    end
end

function S.ApplyGameEnd(winnerTeam)
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
    --   Round 1: anyone can overcall Hokm with Sun; later Sun overcalls
    --            earlier Sun. Wait for all 4 before deciding.
    --   Round 2: first non-pass wins (no overcall). Hokm cannot reuse
    --            the originally-flipped suit (UI enforces that).
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
                        winning = { seat = seat, type = btype, trump = trump }
                    elseif btype == K.BID_ASHKAL and not winning then
                        -- Ashkal (Pagat-strict Saudi): "It is the same
                        -- as a bid of Sun, except that it is not the
                        -- bidder but the bidder's PARTNER who takes the
                        -- exposed card from the table and becomes the
                        -- declarer." So contract type = SUN (no trump).
                        --
                        -- Host-side authority check: caller must be the
                        -- 3rd or 4th bidder in turn order AND all prior
                        -- bidders must have passed. Otherwise reject.
                        local pos
                        for idx, ord in ipairs(order) do
                            if ord == seat then pos = idx; break end
                        end
                        local priorAllPass = true
                        if pos then
                            for i = 1, pos - 1 do
                                if s.bids[order[i]] ~= K.BID_PASS then
                                    priorAllPass = false; break
                                end
                            end
                        end
                        if pos and pos >= 3 and priorAllPass then
                            winning = {
                                seat  = R.Partner(seat),
                                type  = K.BID_SUN,
                                trump = nil,
                            }
                        end
                        -- else: silently drop the Ashkal
                    elseif btype == K.BID_HOKM and not winning then
                        winning = { seat = seat, type = btype, trump = trump }
                    end
                else
                    -- Round 2: no Ashkal; first non-pass wins.
                    if not winning and btype ~= K.BID_ASHKAL then
                        winning = { seat = seat, type = btype, trump = trump }
                    end
                end
            end
        end
    end

    -- Round 2 ends as soon as a non-pass appears.
    if s.bidRound == 2 and winning then
        return "contract", { bidder = winning.seat, type = winning.type, trump = winning.trump }
    end

    -- Round 1 must hear all 4 (Sun overcall window).
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
