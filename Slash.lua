-- /baloot dispatcher.

WHEREDNGN = WHEREDNGN or {}
local B = WHEREDNGN
local K = B.K
local L = B.Log

local function say(msg) print("|cff66ddffWHEREDNGN|r " .. tostring(msg)) end

local function help()
    say("commands (shorthand: /blt):")
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
    print("  /baloot swaperm      - toggle SWA permission requirement for 4+ cards (default on)")
    print("  /baloot preempt      - toggle Triple-on-Ace pre-emption (default on)")
    print("  /baloot start        - host: start the round once lobby is full")
    print("  /baloot debug        - toggle debug logging")
    print("  /baloot bidcalc      - toggle Sun-vs-Hokm bidding-decision trace (chat output)")
    print("  /baloot log [N]      - dump last N log lines (default 50)")
    print("  /baloot log clear    - wipe log buffer")
    print("  /baloot target <N>   - set game-win cumulative target (default 152)")
    print("  /baloot cards <name> - switch card style (run /baloot themes for the list)")
    print("  /baloot felt <name>  - switch felt theme (run /baloot themes for the list)")
    print("  /baloot themes       - list available card styles + felt themes")
    print("  /baloot status       - print current phase + seats")
    print("  /baloot history [N]  - dump last N round-result rows (default 20)")
    print("  /baloot history clear - wipe round-result history")
    print("  /baloot history off / on - toggle telemetry capture (default on)")
    print("  /baloot lastround [N] - print last round's per-trick plays (N=2 → 2 rounds back)")
    print("  /baloot config       - open the Settings panel (Esc → Options → AddOns)")
    print("  /baloot leave        - graceful exit (non-host); host sees you as dropped")
    print("  /baloot stats        - lifetime W/L + bidder stats (cross-session)")
    print("  /baloot rules        - Saudi Baloot quick-reference cheat-sheet")
    print("  /baloot help         - show this command list")
end

-- v1.7.0 (audit v1.6.1 PJ-1X): Saudi rules cheat-sheet for new players.
-- Pre-fix the addon had ZERO in-game rules education — players had to
-- read external Saudi Baloot tutorials or guess from button names.
-- This dumps a concise primer covering the bid types, card values, the
-- escalation chain, and the special signals (AKA / SWA / Belote).
local function rules()
    say("Saudi Baloot quick reference:")
    print("|cffffffffBidding (round 1):|r")
    print("  - Hokm (trump = up-card suit), Sun (no-trump), Pass, Ashkal")
    print("  - Sun overcalls Hokm. First non-pass wins.")
    print("|cffffffffBidding (round 2):|r runs only if R1 was all-pass.")
    print("  - Hokm with any non-up-card suit, Sun, or wla (skip).")
    print("|cffffffffCard values:|r")
    print("  Hokm trump: J=20, 9=14, A=11, T=10, K=4, Q=3, 8/7=0")
    print("  Off-trump / Sun: A=11, T=10, K=4, Q=3, J=2, 9/8/7=0")
    print("  Last trick: +10 raw bonus.")
    print("|cffffffffEscalation chain (Saudi-specific):|r")
    print("  Bel (×2) -> Bel x3 (×3) -> Four (×4) -> Gahwa (match-win)")
    print("  Each rung must be voluntarily declared. Default closed.")
    print("|cffffffffSignals:|r")
    print("  AKA (eka): \"I hold the boss in this suit, partner — don't trump\"")
    print("  SWA: \"I claim all remaining tricks\". <=3 cards instant; 4+ asks permission.")
    print("  BALOOT: K+Q-of-trump = +20 raw, multiplier-IMMUNE.")
    print("|cffffffffWin condition:|r first team to /baloot target points (default 152).")
    print("|cffffffffSaudi-specific traps:|r")
    print("  9 of trump is rank #2 (after J). FOUR 9s do NOT form a Carre.")
    print("  Bidder needs STRICT majority — tied 81/162 = bidder fails.")
end

local function dispatch(msg)
    msg = (msg or ""):lower():match("^%s*(.-)%s*$")

    if msg == "" or msg == "show" or msg == "toggle" then
        B.UI.Toggle()
        return
    end

    if msg == "help" or msg == "?" or msg == "h" then
        help()
        return
    end

    -- v3.0 (audit v1.6.1 PJ-53 LOW): /baloot config opens the
    -- WHEREDNGN settings panel under Esc → Options → AddOns. Pre-fix
    -- there was no shortcut — players had to navigate the menu by
    -- hand. The Settings API exposes a per-category open helper.
    if msg == "config" or msg == "settings" or msg == "options" then
        -- Modern (10.0+): Settings.OpenToCategory wants the category ID
        -- returned by RegisterAddOnCategory. We saved it; if Settings
        -- is unavailable, fall back to InterfaceOptionsFrame_OpenToCategory
        -- with the panel name.
        if Settings and Settings.OpenToCategory then
            -- Without the cached ID, fall back to opening top-level
            -- AddOns; users see the addon highlighted on first reach.
            Settings.OpenToCategory("Loot & Baloot (WHEREDNGN)")
        elseif InterfaceOptionsFrame_OpenToCategory then
            -- Legacy. Some clients require two calls due to a
            -- known Blizzard bug.
            InterfaceOptionsFrame_OpenToCategory("Loot & Baloot (WHEREDNGN)")
            InterfaceOptionsFrame_OpenToCategory("Loot & Baloot (WHEREDNGN)")
        else
            say("Settings panel not available on this client; "
                .. "use /baloot help.")
        end
        return
    end

    if msg == "rules" or msg == "rule" or msg == "ref" then
        rules()
        return
    end

    -- v2.1.0 (audit v1.6.1 PJ-40 MED): lifetime stats readout.
    if msg == "stats" or msg == "stat" then
        WHEREDNGNDB = WHEREDNGNDB or {}
        local s = WHEREDNGNDB.stats or {}
        local games = s.gamesPlayed or 0
        local wins  = s.gamesWon or 0
        local taken = s.contractsTaken or 0
        local made  = s.contractsMade or 0
        local swing = s.biggestSwing or 0
        local winPct = (games > 0) and (wins * 100 / games) or 0
        local madePct = (taken > 0) and (made * 100 / taken) or 0
        say("lifetime stats:")
        print(("  games played: %d   wins: %d   (%.1f%% win rate)"):format(
            games, wins, winPct))
        print(("  contracts taken: %d   made: %d   (%.1f%% make rate)"):format(
            taken, made, madePct))
        print(("  biggest single-game point swing: %d"):format(swing))
        return
    end

    if msg == "stats clear" or msg == "stats reset" then
        WHEREDNGNDB = WHEREDNGNDB or {}
        WHEREDNGNDB.stats = {
            gamesPlayed = 0, gamesWon = 0,
            contractsTaken = 0, contractsMade = 0,
            biggestSwing = 0,
        }
        say("lifetime stats wiped")
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
        -- v2.0.0 (audit v1.6.1 MP-22 HIGH): if we're host mid-round,
        -- /baloot reset wipes the game for ALL connected players
        -- without warning. The UI Reset button (UI.lua:543) goes
        -- through StaticPopup_Show("WHEREDNGN_RESET_CONFIRM") for
        -- exactly this reason — but the slash command bypassed the
        -- guard. Now slash routes through the same popup if we're
        -- host with a non-IDLE/non-LOBBY phase. `/baloot reset force`
        -- bypasses the popup for users who actually need the old
        -- behavior (e.g. recovering from a stuck state).
        local isHostMidGame = B.State and B.State.s and B.State.s.isHost
            and B.State.s.phase ~= K.PHASE_IDLE
            and B.State.s.phase ~= K.PHASE_LOBBY
            and B.State.s.phase ~= K.PHASE_GAME_END
        if isHostMidGame and StaticPopup_Show then
            StaticPopup_Show("WHEREDNGN_RESET_CONFIRM")
            return
        end
        -- v2.1.0 (audit v1.6.1 MP-71 MED): if we're host AND we have
        -- a gameID (active or lobby), broadcast a final teardown
        -- ping so remote clients can clear their pendingHost +
        -- exit any sticky lobby state. Pre-fix the host reset wiped
        -- their own state but never told remotes — the lobby ticker
        -- stops, but remotes hold pendingHost forever (until the
        -- 45s heartbeat timeout from v1.8.0 MP-21 fires). Faster
        -- recovery via explicit host-gone flag in a final MSG_LOBBY
        -- with empty botMask + name list.
        if B.State and B.State.s and B.State.s.isHost and B.State.s.gameID
           and B.Net and B.Net.SendLobby then
            -- Empty seat array signals "host's gone" to remotes;
            -- remotes' _OnLobby clears pendingHost when they see
            -- empty seats from a known host.
            B.Net.SendLobby({}, B.State.s.gameID)
        end
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

    if msg == "leave" or msg == "quit" then
        -- v2.1.0 (audit v1.6.1 MP-61 MED): graceful exit for non-host.
        -- Pre-fix the only way for a non-host to exit was /baloot
        -- reset, which silently dropped them with no notification to
        -- the table. /baloot leave does the same teardown locally
        -- but also pings the host's GROUP_ROSTER_UPDATE recovery
        -- path (Mid-round drop -> bot replace) by leaving the
        -- party — same effect as a real disconnect, but explicit.
        if B.State.s.isHost then
            say("you are the host — use /baloot reset to wipe the game")
            return
        end
        if B.State.s.phase == K.PHASE_IDLE then
            say("not in a game")
            return
        end
        -- Local teardown (mirror /baloot reset's body, no host-specific
        -- ticker cleanup since we're not hosting).
        B._redealGen = (B._redealGen or 0) + 1
        if B.Net then
            if B.Net.CancelTurnTimer then B.Net.CancelTurnTimer() end
            if B.Net.CancelLocalWarn then B.Net.CancelLocalWarn() end
        end
        B.State.Reset()
        B.State.SetLocalName(GetUnitName("player", true))
        if B.UI then B.UI.Refresh() end
        say("left the game (host's table sees you as dropped — bot fills in)")
        return
    end

    if msg == "reset force" then
        -- v2.0.0 MP-22 escape hatch: bypass the host-mid-round popup
        -- for users recovering from stuck state.
        if B._lobbyTicker then B._lobbyTicker:Cancel(); B._lobbyTicker = nil end
        B._redealGen = (B._redealGen or 0) + 1
        if B.Net then
            if B.Net.CancelTurnTimer then B.Net.CancelTurnTimer() end
            if B.Net.CancelLocalWarn then B.Net.CancelLocalWarn() end
        end
        B.State.Reset()
        B.State.SetLocalName(GetUnitName("player", true))
        if B.UI then B.UI.Refresh() end
        say("reset (forced)")
        return
    end

    if msg == "debug" then
        WHEREDNGNDB = WHEREDNGNDB or {}
        WHEREDNGNDB.debug = not WHEREDNGNDB.debug
        say("debug = " .. tostring(WHEREDNGNDB.debug))
        return
    end

    -- v0.11.8 — toggle bidding-decision trace. Prints each Bot.PickBid
    -- call's hand strength + thresholds + decision to chat. Used for
    -- diagnosing the user-reported "bots not bidding Sun" pattern:
    -- with this on, the player can see EXACTLY why each bot chose
    -- Hokm vs Sun vs Pass, including the jittered threshold and the
    -- urgency stack on each bid. Independent of the master `debug`
    -- flag (which gates Log.lua behavior); bidcalc is a focused
    -- short-term diagnostic toggle.
    if msg == "bidcalc" or msg == "bidtrace" or msg == "biddebug" then
        WHEREDNGNDB = WHEREDNGNDB or {}
        WHEREDNGNDB.debugBidcalc = not WHEREDNGNDB.debugBidcalc
        say("bidcalc trace = " .. tostring(WHEREDNGNDB.debugBidcalc))
        return
    end

    -- v0.11.18-final BM-03 (ultra audit): ISMCTS diagnostic slash.
    -- Surfaces wall-clock-budget telemetry from BotMaster: how many
    -- worlds the LAST Saudi Master move actually completed, vs. the
    -- configured ceiling. Useful when users notice ISMCTS-quality
    -- degradation on slow machines or under stress.
    if msg == "ismctsdiag" or msg == "ismctsdebug" then
        local bm = B.BotMaster
        if not bm then
            say("ISMCTS: BotMaster module not loaded")
            return
        end
        local last = bm._lastWorldsCompleted or 0
        local budget = K.BOT_ISMCTS_BUDGET_SEC or 0
        local shortCircuit = bm._lastShortCircuit
        -- v0.11.19 (ultra-audit BM-03 follow-up): differentiate the
        -- "0 worlds" cases. Single-card-shortcut is normal/expected;
        -- budget-cut-on-iter-1 would suggest a perf concern.
        if shortCircuit == "single-card" then
            say(("ISMCTS: last move had only 1 legal card (no rollout needed); "
                 .. "budget %.2fs"):format(budget))
        elseif shortCircuit == "no-legal-moves" then
            say("ISMCTS: last move had 0 legal moves (defensive fallback)")
        elseif shortCircuit == "legal-build-failed" then
            say("ISMCTS: legal-set build pcall failed — heuristic fallback")
        elseif last == 0 then
            say(("ISMCTS: last move completed 0 worlds (budget %.2fs cut on iter 1?); "
                 .. "if you see this often, raise K.BOT_ISMCTS_BUDGET_SEC"):format(budget))
        else
            say(("ISMCTS: last move completed %d worlds (budget %.2fs)")
                :format(last, budget))
        end
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

    -- v2.2.0 (audit v1.6.1 UX-43 LOW): /baloot sound — toggle audio.
    -- The lobby-window checkbox already exists; this gives the slash-
    -- only path the same affordance and re-syncs the checkbox visual
    -- so an open window doesn't show stale state after toggling via
    -- chat. Pre-fix there was no slash equivalent; muting required
    -- opening the window every time.
    if msg == "sound" or msg == "mute" or msg == "audio" then
        WHEREDNGNDB = WHEREDNGNDB or {}
        if WHEREDNGNDB.sound == nil then WHEREDNGNDB.sound = true end
        WHEREDNGNDB.sound = not (WHEREDNGNDB.sound == true)
        say("sound = " .. tostring(WHEREDNGNDB.sound))
        if B.UI and B.UI.GetMuteBtn then
            local btn = B.UI.GetMuteBtn()
            if btn and btn.Sync then btn:Sync() end
        end
        return
    end

    if msg == "swa" then
        WHEREDNGNDB = WHEREDNGNDB or {}
        if WHEREDNGNDB.allowSWA == nil then WHEREDNGNDB.allowSWA = true end
        WHEREDNGNDB.allowSWA = not WHEREDNGNDB.allowSWA
        say("SWA (claim-the-rest) = " .. tostring(WHEREDNGNDB.allowSWA))
        if B.UI and B.UI.Refresh then B.UI.Refresh() end
        return
    end

    -- v1.8.1 (audit v1.6.1 PJ-5X HIGH): /baloot swaperm subcommand.
    -- Pre-fix `swaRequiresPermission` was a real config knob referenced
    -- in WHEREDNGN.lua:54 (DEFAULTS) and Net.lua:~3040 (gate site), but
    -- the slash dispatch had no entry for it — typing /baloot swaperm
    -- was a no-op even though the comment in DEFAULTS said "toggle via
    -- /baloot swaperm". Now wired:
    if msg == "swaperm" or msg == "swapermission" then
        WHEREDNGNDB = WHEREDNGNDB or {}
        if WHEREDNGNDB.swaRequiresPermission == nil then
            WHEREDNGNDB.swaRequiresPermission = true
        end
        WHEREDNGNDB.swaRequiresPermission = not WHEREDNGNDB.swaRequiresPermission
        if WHEREDNGNDB.swaRequiresPermission then
            say("SWA permission required for 4+ cards (Saudi default)")
        else
            say("SWA permission DISABLED — all SWA calls instant "
                .. "(house-rule mode)")
        end
        if B.UI and B.UI.Refresh then B.UI.Refresh() end
        return
    end

    if msg == "preempt" or msg == "ahel" or msg == "thaleth" then
        WHEREDNGNDB = WHEREDNGNDB or {}
        if WHEREDNGNDB.preemptOnAce == nil then WHEREDNGNDB.preemptOnAce = true end
        WHEREDNGNDB.preemptOnAce = not WHEREDNGNDB.preemptOnAce
        say("Triple-on-Ace pre-emption = " .. tostring(WHEREDNGNDB.preemptOnAce))
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

    -- v0.8.3 telemetry export: /baloot history [N]
    -- /baloot history clear  → wipe
    -- /baloot history on/off → toggle capture
    -- /baloot history [N]    → dump last N rows (default 20)
    local histArg = msg:match("^history%s*(.*)$")
    if histArg then
        WHEREDNGNDB = WHEREDNGNDB or {}
        if histArg == "clear" then
            WHEREDNGNDB.history = {}
            say("round-result history cleared")
            return
        elseif histArg == "off" then
            WHEREDNGNDB.historyEnabled = false
            say("history capture OFF (existing rows preserved)")
            return
        elseif histArg == "on" then
            WHEREDNGNDB.historyEnabled = true
            say("history capture ON")
            return
        end
        -- v0.9.2 #47 fix (audit_v0.9.0/47_telemetry_growth.md):
        -- type-guard the dump path so a hand-edited non-table
        -- history doesn't crash the slash command. Mirrors the
        -- append-site guard in State.lua.
        local h = WHEREDNGNDB.history
        if type(h) ~= "table" then h = {} end
        local n = tonumber(histArg) or 20
        local total = #h
        if total == 0 then
            say("no round results recorded yet (toggle with /baloot history on)")
            return
        end
        local startIdx = math.max(1, total - n + 1)
        say(("history: %d row%s total, showing last %d:"):format(
            total, total == 1 and "" or "s", math.min(n, total)))
        for i = startIdx, total do
            local r = h[i]
            -- v0.9.2 #47: skip non-table rows (corrupt hand-edits)
            -- to prevent `r.field` indexing crashes on a string/
            -- number row.
            if type(r) == "table" then
                print(("  r%-3d  %-4s  trump=%-1s bidder=%d  Δ=%+d/%+d  cum=%d/%d  bel=%d trp=%d for=%d gah=%d  swp=%s  made=%d  br%d  bidc=%s"):format(
                    r.roundNumber or 0, r.type or "?",
                    r.trump or "-", r.bidder or 0,
                    r.addA or 0, r.addB or 0,
                    r.totA or 0, r.totB or 0,
                    r.doubled or 0, r.tripled or 0, r.foured or 0, r.gahwa or 0,
                    (r.sweep ~= "" and r.sweep) or "-",
                    r.bidderMade or -1,
                    r.bidRound or 0,
                    r.bidCard or "-"))
            end
        end
        say(("see SavedVariables/WHEREDNGN.lua for the full table " ..
             "(WHEREDNGNDB.history)"))
        return
    end

    -- v3.1.3 (user request — bot-behavior monitoring): print last
    -- round's play-by-play with per-trick cards. Sources from
    -- WHEREDNGNDB.history's v=4 trickPlays field.
    -- Usage:
    --   /baloot lastround       → most-recent round
    --   /baloot lastround N     → N rounds back (1 = most recent,
    --                              2 = previous, etc.)
    local lrArg = msg:match("^lastround%s*(.*)$")
    if lrArg then
        WHEREDNGNDB = WHEREDNGNDB or {}
        local h = WHEREDNGNDB.history
        if type(h) ~= "table" or #h == 0 then
            say("no rounds recorded yet (toggle with /baloot history on)")
            return
        end
        local back = tonumber(lrArg) or 1
        if back < 1 then back = 1 end
        local idx = #h - back + 1
        if idx < 1 then
            say(("only %d round%s recorded; cannot go %d back"):format(
                #h, #h == 1 and "" or "s", back))
            return
        end
        local r = h[idx]
        if type(r) ~= "table" then
            say("round entry is corrupt; check WHEREDNGNDB.history")
            return
        end
        local typeStr = r.type or "?"
        local trumpStr = (r.trump and r.trump ~= "") and (" trump=" .. r.trump) or ""
        local mods = {}
        if r.doubled == 1 then mods[#mods + 1] = "Bel" end
        if r.tripled == 1 then mods[#mods + 1] = "Bel x2" end
        if r.foured == 1  then mods[#mods + 1] = "Four"  end
        if r.gahwa == 1   then mods[#mods + 1] = "Gahwa" end
        local modStr = (#mods > 0) and (" [" .. table.concat(mods, " ") .. "]") or ""
        say(("round %d  %s%s%s  bidder=seat%d (%s)  bidcard=%s"):format(
            r.roundNumber or 0, typeStr, trumpStr, modStr,
            r.bidder or 0, r.bidderTier or "?",
            r.bidCard or "-"))
        say(("  outcome: A %+d  B %+d  → cum %d/%d  made=%s%s"):format(
            r.addA or 0, r.addB or 0, r.totA or 0, r.totB or 0,
            (r.bidderMade == 1) and "yes"
            or (r.bidderMade == 0) and "no" or "?",
            (r.sweep ~= nil and r.sweep ~= "")
                and (" sweep=" .. r.sweep) or ""))
        if type(r.trickPlays) ~= "table" or #r.trickPlays == 0 then
            say("  (no per-trick plays — pre-v3.1.3 row, schema v=" ..
                tostring(r.v or 1) .. ")")
            return
        end
        for ti, line in ipairs(r.trickPlays) do
            -- format: "{leadSuit}|{winner}|{points}|{seat-card,...}"
            local ls, w, pts, plays = line:match("^([^|]+)|([^|]+)|([^|]+)|(.*)$")
            if ls then
                say(("  T%d  lead=%s  winner=seat%s  pts=%s  plays: %s"):format(
                    ti, ls, w, pts, plays or ""))
            else
                say(("  T%d  (parse error) %s"):format(ti, line))
            end
        end
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
