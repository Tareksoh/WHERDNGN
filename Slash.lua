-- /baloot dispatcher.

WHEREDNGN = WHEREDNGN or {}
local B = WHEREDNGN
local K = B.K
local L = B.Log

local function say(msg) print("|cff66ddffWHEREDNGN|r " .. tostring(msg)) end

local function help()
    say("commands:")
    print("  /baloot              - toggle window")
    print("  /baloot host         - start hosting a new game (solo OK; fill empty with bots)")
    print("  /baloot join         - accept a pending host invite")
    print("  /baloot bots         - fill all empty seats with bots (host only)")
    print("  /baloot reset        - reset to idle (clears your local game state)")
    print("  /baloot advanced     - toggle Advanced bot heuristics (host only)")
    print("  /baloot m3lm         - toggle M3lm (pro) bot tier (host only)")
    print("  /baloot fzloky       - toggle Fzloky (signal-aware) tier (host only)")
    print("  /baloot saudimaster  - toggle Saudi Master (ISMCTS) tier (host only)")
    print("  /baloot start        - host: start the round once lobby is full")
    print("  /baloot debug        - toggle debug logging")
    print("  /baloot log [N]      - dump last N log lines (default 50)")
    print("  /baloot log clear    - wipe log buffer")
    print("  /baloot target <N>   - set game-win cumulative target (default 152)")
    print("  /baloot status       - print current phase + seats")
end

local function dispatch(msg)
    msg = (msg or ""):lower():match("^%s*(.-)%s*$")

    if msg == "" or msg == "show" or msg == "toggle" then
        B.UI.Toggle()
        return
    end

    if msg == "host" then
        -- Solo hosting is allowed; the lobby fills with bots via /baloot
        -- bots or the "Fill Bots" button. Broadcasts no-op when not in a
        -- party.
        local id = B.State.HostBeginLobby()
        if id then
            B.Net.SendLobby(B.State.s.seats, id)
            B._lobbyTicker = C_Timer.NewTicker(K.LOBBY_BROADCAST_SEC, function()
                if B.State.s.isHost and B.State.s.phase == K.PHASE_LOBBY then
                    B.Net.SendHostAnnounce(B.State.s.gameID)
                else
                    if B._lobbyTicker then B._lobbyTicker:Cancel(); B._lobbyTicker = nil end
                end
            end)
            B.Net.SendHostAnnounce(id)
            B.UI.Show()
            say("hosting WHEREDNGN game " .. id)
        end
        return
    end

    if msg == "bots" or msg == "fillbots" or msg == "addbots" then
        if not B.State.s.isHost then say("not host"); return end
        local n = B.State.HostAddBots()
        if n == 0 then
            say("no empty seats to fill")
        else
            B.Net.SendLobby(B.State.s.seats, B.State.s.gameID)
            if B.UI then B.UI.Refresh() end
            say(("filled %d seat(s) with bots"):format(n))
        end
        return
    end

    if msg == "join" then
        if B.State.s.pendingHost then
            B.State.SetLocalName(B.State.s.localName or GetUnitName("player", true))
            B.Net.SendJoin(B.State.s.pendingHost.gameID)
            B.UI.Show()
            say("joining " .. B.State.s.pendingHost.name)
        else
            say("no host invite pending. ask the host to /baloot host.")
        end
        return
    end

    if msg == "start" then
        if not B.State.s.isHost then say("not host"); return end
        if not B.State.LobbyFull() then say("lobby not full"); return end
        B.Net.HostStartRound()
        return
    end

    if msg == "reset" then
        if B._lobbyTicker then B._lobbyTicker:Cancel(); B._lobbyTicker = nil end
        B.State.Reset()
        B.State.SetLocalName(GetUnitName("player", true))
        if B.UI then B.UI.Refresh() end
        say("reset")
        return
    end

    if msg == "debug" then
        WHEREDNGNDB = WHEREDNGNDB or {}
        WHEREDNGNDB.debug = not WHEREDNGNDB.debug
        say("debug = " .. tostring(WHEREDNGNDB.debug))
        return
    end

    if msg == "advanced" or msg == "advbots" then
        WHEREDNGNDB = WHEREDNGNDB or {}
        WHEREDNGNDB.advancedBots = not WHEREDNGNDB.advancedBots
        say("advanced bots = " .. tostring(WHEREDNGNDB.advancedBots))
        if B.UI and B.UI.Refresh then B.UI.Refresh() end
        return
    end

    if msg == "m3lm" or msg == "master" then
        WHEREDNGNDB = WHEREDNGNDB or {}
        WHEREDNGNDB.m3lmBots = not WHEREDNGNDB.m3lmBots
        say("M3lm (master) bots = " .. tostring(WHEREDNGNDB.m3lmBots))
        if B.UI and B.UI.Refresh then B.UI.Refresh() end
        return
    end

    if msg == "fzloky" or msg == "signal" then
        WHEREDNGNDB = WHEREDNGNDB or {}
        WHEREDNGNDB.fzlokyBots = not WHEREDNGNDB.fzlokyBots
        say("Fzloky (signal-aware) bots = " .. tostring(WHEREDNGNDB.fzlokyBots))
        if B.UI and B.UI.Refresh then B.UI.Refresh() end
        return
    end

    if msg == "saudimaster" or msg == "master+" or msg == "ismcts" then
        WHEREDNGNDB = WHEREDNGNDB or {}
        WHEREDNGNDB.saudiMasterBots = not WHEREDNGNDB.saudiMasterBots
        say("Saudi Master (ISMCTS) bots = " .. tostring(WHEREDNGNDB.saudiMasterBots))
        if B.UI and B.UI.Refresh then B.UI.Refresh() end
        return
    end

    if msg == "status" then
        local s = B.State.s
        say(("phase=%s host=%s gameID=%s round=%d turn=%s/%s"):format(
            tostring(s.phase), tostring(s.isHost), tostring(s.gameID),
            s.roundNumber or 0, tostring(s.turn), tostring(s.turnKind)))
        for seat = 1, 4 do
            local info = s.seats[seat]
            print(("  seat %d: %s"):format(seat, info and info.name or "(empty)"))
        end
        return
    end

    local logArg = msg:match("^log%s*(.*)$")
    if logArg then
        if logArg == "clear" then L.Clear(); say("log cleared"); return end
        local n = tonumber(logArg) or 50
        L.Dump(n)
        return
    end

    local tNum = msg:match("^target%s+(%d+)$")
    if tNum then
        WHEREDNGNDB = WHEREDNGNDB or {}
        WHEREDNGNDB.target = tonumber(tNum)
        B.State.s.target = WHEREDNGNDB.target
        say("target = " .. WHEREDNGNDB.target)
        return
    end

    if msg == "help" or msg == "?" then
        help()
        return
    end

    say("unknown command. /baloot help")
end

SLASH_BALOOT1 = "/baloot"
SLASH_BALOOT2 = "/blt"
SlashCmdList["BALOOT"] = dispatch
