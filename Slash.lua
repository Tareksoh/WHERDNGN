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
    print("  /baloot swa          - toggle SWA claim-the-rest (default on; off = tournament mode)")
    print("  /baloot preempt      - toggle Triple-on-Ace pre-emption (default on)")
    print("  /baloot start        - host: start the round once lobby is full")
    print("  /baloot debug        - toggle debug logging")
    print("  /baloot log [N]      - dump last N log lines (default 50)")
    print("  /baloot log clear    - wipe log buffer")
    print("  /baloot target <N>   - set game-win cumulative target (default 152)")
    print("  /baloot cards <name> - switch card style (run /baloot themes for the list)")
    print("  /baloot felt <name>  - switch felt theme (run /baloot themes for the list)")
    print("  /baloot themes       - list available card styles + felt themes")
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
        --
        -- 4th-audit X9-2 fix: refuse if a game is already running.
        -- HostBeginLobby calls reset() which silently destroys the
        -- active state — only safe from IDLE or GAME_END.
        local p = B.State.s.phase
        if p ~= K.PHASE_IDLE and p ~= K.PHASE_GAME_END then
            say("already in a game (phase=" .. tostring(p)
                .. "). /baloot reset first.")
            return
        end
        local id = B.State.HostBeginLobby()
        if id then
            B.Net.SendLobby(B.State.s.seats, id)
            -- Audit C19 fix: cancel any prior ticker before arming a
            -- new one. Rapid /baloot host invocations could otherwise
            -- create overlapping tickers, doubling lobby broadcasts.
            if B._lobbyTicker then
                B._lobbyTicker:Cancel(); B._lobbyTicker = nil
            end
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
        -- 9th-audit fix: invalidate any in-flight 3s redeal timer so
        -- it doesn't fire after the reset and spawn a ghost round.
        -- Same pattern is safe for any future deferred callbacks
        -- gated on B._redealGen.
        B._redealGen = (B._redealGen or 0) + 1
        -- Cancel host AFK turn timer + local pre-warn timer so they
        -- don't fire after reset on a stale seat (Codex 9th + 10th
        -- audit catches). fireLocalWarn() doesn't gate on phase, so
        -- a stale T-10s ping/pulse could otherwise still fire.
        if B.Net then
            if B.Net.CancelTurnTimer then B.Net.CancelTurnTimer() end
            if B.Net.CancelLocalWarn then B.Net.CancelLocalWarn() end
        end
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

    if msg == "swa" then
        WHEREDNGNDB = WHEREDNGNDB or {}
        if WHEREDNGNDB.allowSWA == nil then WHEREDNGNDB.allowSWA = true end
        WHEREDNGNDB.allowSWA = not WHEREDNGNDB.allowSWA
        say("SWA (سوا claim-the-rest) = " .. tostring(WHEREDNGNDB.allowSWA))
        if B.UI and B.UI.Refresh then B.UI.Refresh() end
        return
    end

    if msg == "preempt" or msg == "ahel" or msg == "thaleth" then
        WHEREDNGNDB = WHEREDNGNDB or {}
        if WHEREDNGNDB.preemptOnAce == nil then WHEREDNGNDB.preemptOnAce = true end
        WHEREDNGNDB.preemptOnAce = not WHEREDNGNDB.preemptOnAce
        say("Triple-on-Ace pre-emption (الثالث) = " .. tostring(WHEREDNGNDB.preemptOnAce))
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
        -- 8th-audit fix: reject target=0. The pattern matches /baloot
        -- target 0, which used to land in the score-target check
        -- (`totA >= s.target`) — true for any non-negative total — and
        -- ended the next round resolution as an instant game-end.
        -- Reject anything below the minimum sensible Saudi target.
        local n = tonumber(tNum) or 0
        if n < 21 then
            say("target must be at least 21 (Saudi sub-game minimum)")
            return
        end
        WHEREDNGNDB = WHEREDNGNDB or {}
        WHEREDNGNDB.target = n
        B.State.s.target = n
        say("target = " .. n)
        return
    end

    if msg == "themes" then
        if B.UI and B.UI.GetCardStyles then
            local activeCS = B.UI.GetActiveCardStyle and B.UI.GetActiveCardStyle() or "classic"
            say("card styles:")
            for _, t in ipairs(B.UI.GetCardStyles()) do
                local marker = (t.id == activeCS) and " *" or ""
                print(("  %s%s — %s"):format(t.id, marker, t.name))
            end
        end
        if B.UI and B.UI.GetFeltThemes then
            local activeFT = B.UI.GetActiveFeltTheme and B.UI.GetActiveFeltTheme() or "green"
            say("felt themes:")
            for _, t in ipairs(B.UI.GetFeltThemes()) do
                local marker = (t.id == activeFT) and " *" or ""
                print(("  %s%s — %s"):format(t.id, marker, t.name))
            end
        end
        return
    end

    local cardArg = msg:match("^cards%s+(%S+)$")
    if cardArg then
        if B.UI and B.UI.SetCardStyle and B.UI.SetCardStyle(cardArg) then
            say("card style = " .. cardArg)
        else
            say("unknown card style '" .. cardArg .. "'. try /baloot themes")
        end
        return
    end

    local feltArg = msg:match("^felt%s+(%S+)$")
    if feltArg then
        if B.UI and B.UI.SetFeltTheme and B.UI.SetFeltTheme(feltArg) then
            say("felt theme = " .. feltArg)
        else
            say("unknown felt theme '" .. feltArg .. "'. try /baloot themes")
        end
        return
    end

    -- Back-compat: pre-split single-axis selector. Maps "classic" /
    -- "burgundy" to a paired card-style + felt-theme set.
    local theme = msg:match("^theme%s+(%S+)$")
    if theme then
        if B.UI and B.UI.SetTheme and B.UI.SetTheme(theme) then
            say("theme = " .. theme)
        else
            say("unknown theme '" .. theme .. "'. try /baloot themes")
        end
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
