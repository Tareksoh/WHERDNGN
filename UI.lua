-- WHEREDNGN main window.
--
-- Privacy rule: a player ONLY sees:
--   1. Their own hand (bottom).
--   2. Cards currently in the center trick (this trick only; cleared
--      after the trick is decided).
--   3. Declared melds (face-up, public once a player declares).
-- Other players' hands are rendered as a card-back count badge only.
-- The host happens to know all hands internally for validation, but
-- the UI never reads from s.hostHands.

WHEREDNGN = WHEREDNGN or {}
local B = WHEREDNGN
B.UI = B.UI or {}
local U = B.UI
local K, C, R, S = B.K, B.Cards, B.Rules, B.State

-- N is referenced lazily (Net.lua loads after UI in the .toc? we keep
-- it lazy to avoid load-order bugs).
local function net() return B.Net end

-- ----------------------------------------------------------------------
-- Frame state
-- ----------------------------------------------------------------------

local f                       -- main frame
local lobbyPanel, tablePanel
local statusText
local seatBadges = {}         -- [pos] = {frame, nameText, countText, meldText, turnGlow, dealerText, backs}
local centerCards = {}        -- [pos] = {frame, label}
local actionPanel             -- holds bid / double / play buttons
local scoreText, contractText, roundText, gameIDText
local hostStartBtn
local joinBtn

-- Theme refresh: card-back stack frames + tex pairs live deep inside
-- child frames built by helpers (one per seat-badge slot). Collected
-- into a module-local list at construction so SetCardStyle() can
-- re-bind their texture path AND re-apply the backdrop tint without
-- rebuilding the whole window.
-- (Glow textures are theme-independent; no tracking needed.)
local cardBackEntries = {}   -- { { frame = <Frame>, tex = <Texture> }, ... }

-- Forward declaration: buildTable wires this into a button OnClick,
-- but the implementation lives later in the file. Without forward-
-- declaring as a local, the closure captures a global (nil) instead
-- of the local function defined further down.
local peekLastTrick

-- Theme surface --------------------------------------------------------
-- Card styles, felt themes, the COL palette table, and theme helpers
-- live in UI/Themes.lua (loaded immediately before this file by the
-- .toc). Bind them as file-locals so existing call sites resolve
-- unchanged. The COL table is the same shared reference used inside
-- UI/Themes.lua, so applyThemeColors() mutations propagate to every
-- reader here automatically.
local Theme               = U.Theme
local COL                 = Theme.COL
local CARD_STYLES         = Theme.CARD_STYLES
local FELT_THEMES         = Theme.FELT_THEMES
local CARD_TEX_DIR        = Theme.CARD_TEX_DIR
local activeCardStyleName = Theme.ActiveCardStyleName
local activeFeltThemeName = Theme.ActiveFeltThemeName
local cardStyleData       = Theme.CardStyleData
local feltThemeData       = Theme.FeltThemeData
local applyThemeColors    = Theme.ApplyThemeColors
local cardTexturePath     = Theme.CardTexturePath

-- Map a position label (relative to local player) to absolute seat.
-- Spectators (5+ party members with no seat) anchor at seat 1 — the
-- badges show seats 2/3/4 in the right/top/left slots, and seat 1's
-- info renders in a compact spectator-info line where the hand row
-- would otherwise be. This is a display-only fallback; no player
-- action paths read these for spectators (they all gate on
-- S.s.localSeat).
local function seatAtPos(pos)
    local me = S.s.localSeat or 1   -- spectator anchor
    if pos == "bottom" then return me end
    if pos == "top"    then return R.Partner(me) end
    if pos == "right"  then return R.NextSeat(me) end
    if pos == "left"   then return R.Partner(R.NextSeat(me)) end
end

local function posOfSeat(seat)
    local me = S.s.localSeat or 1
    if not seat then return nil end
    if seat == me then return "bottom" end
    if seat == R.Partner(me) then return "top" end
    if seat == R.NextSeat(me) then return "right" end
    return "left"
end

-- ----------------------------------------------------------------------
-- Helpers
-- ----------------------------------------------------------------------

-- bgKind: "tooltip" (default, has texture/grain — good for table felt) or
--         "solid"   (WHITE8X8 — clean color for card faces).
local function setBackdrop(frame, edge, bgRGBA, edgeRGBA, edgeSize, bgKind)
    if not frame.SetBackdrop then
        Mixin(frame, BackdropTemplateMixin)
        if frame.OnBackdropLoaded then frame:OnBackdropLoaded() end
    end
    local bgFile
    if bgKind == "solid" then
        bgFile = "Interface\\Buttons\\WHITE8X8"
    else
        bgFile = "Interface/Tooltips/UI-Tooltip-Background"
    end
    frame:SetBackdrop({
        bgFile   = bgFile,
        edgeFile = edge and "Interface/Tooltips/UI-Tooltip-Border" or nil,
        edgeSize = edgeSize or 12,
        insets   = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    bgRGBA = bgRGBA or COL.feltDark
    frame:SetBackdropColor(bgRGBA[1], bgRGBA[2], bgRGBA[3], bgRGBA[4])
    if edge then
        edgeRGBA = edgeRGBA or COL.woodEdge
        frame:SetBackdropBorderColor(edgeRGBA[1], edgeRGBA[2], edgeRGBA[3], edgeRGBA[4])
    end
end

-- Build a "card face" frame: shows a real card image (Texture). When
-- the texture is missing or no card is set yet, falls back to a cream
-- rectangle with a centered FontString so partial deploys don't render
-- an empty white box.
-- Caller anchors and sets size. Returned table:
--   .frame   the parent Frame
--   .label   FontString fallback (used only if no texture set)
--   .tex     Texture for the card image; SetCard(slot, card) writes here
local function makeCardFace(parent, w, h)
    local frame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    frame:SetSize(w or 50, h or 70)
    setBackdrop(frame, true, COL.cardFace, COL.cardEdge, 8, "solid")
    local tex = frame:CreateTexture(nil, "ARTWORK")
    tex:SetPoint("TOPLEFT", 2, -2)
    tex:SetPoint("BOTTOMRIGHT", -2, 2)
    tex:Hide()
    local label = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    label:SetFont(K.CARD_FONT, math.floor((h or 70) * 0.32), "OUTLINE")
    label:SetPoint("CENTER", 0, 0)
    label:SetJustifyH("CENTER")
    return { frame = frame, label = label, tex = tex }
end

-- Set a card-face slot to display `card` (id like "AS"), or pass nil
-- to clear it. Hides the fallback label when the texture is in use.
local function setCardSlot(slot, card)
    if not slot then return end
    if not card then
        slot.tex:Hide()
        if slot.label then slot.label:SetText("") end
        return
    end
    local path = cardTexturePath(card)
    if path then
        slot.tex:SetTexture(path)
        slot.tex:Show()
        if slot.label then slot.label:SetText("") end
    else
        slot.tex:Hide()
        if slot.label then slot.label:SetText(C.PrettyOnCard(card)) end
    end
end

-- Build a "card back" badge: navy blue card with a decorative inner
-- frame and centered diamond glyph, evoking a real playing-card back.
-- Caller anchors and sets initial visibility.
local function makeCardBack(parent, w, h)
    w = w or 24; h = h or 34
    local frame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    frame:SetSize(w, h)
    setBackdrop(frame, true, COL.cardBack, COL.cardBackEdge, 4, "solid")

    -- Use the bundled card-back image so seat hands match the face-card
    -- art style. Falls back to a tinted rectangle if the texture is
    -- missing (which shouldn't happen post-install, but keeps the
    -- partial-deploy debug experience sane).
    local tex = frame:CreateTexture(nil, "ARTWORK")
    tex:SetPoint("TOPLEFT", 2, -2)
    tex:SetPoint("BOTTOMRIGHT", -2, 2)
    tex:SetTexture(cardTexturePath(nil))   -- theme-aware "back" path
    -- Track frame+tex so SetCardStyle can re-bind both the texture
    -- path AND the solid backdrop tint (was tex-only previously).
    cardBackEntries[#cardBackEntries + 1] = { frame = frame, tex = tex }
    return frame
end

-- All card / suit / meld text uses K.CARD_FONT so the U+2660-U+2666
-- glyphs render. Falls back to STANDARD_TEXT_FONT only if SetFont errors
-- (shouldn't happen — ARIALN.TTF ships with the client).
local function makeText(parent, size, justify)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fs:SetFont(K.CARD_FONT, size or 12, "OUTLINE")
    fs:SetJustifyH(justify or "LEFT")
    return fs
end

local function makeButton(parent, label, w, h)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(w or 80, h or 22)
    b:SetText(label)
    -- UIPanelButtonTemplate's default font lacks the suit glyphs;
    -- override so labels like "Hokm ♥" render correctly.
    local fs = b:GetFontString()
    if fs then fs:SetFont(K.CARD_FONT, 12, "") end
    return b
end

-- v2.0.0 (audit v1.6.1 PJ-06): tooltip helper for direct-makeButton
-- call sites (lobby + control buttons that don't go through addAction).
-- Mirrors the GameTooltip pattern at the muteBtn checkbox.
local function setLobbyTooltip(btn, headline, body)
    if not btn then return end
    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(headline, 1, 1, 1)
        if body then GameTooltip:AddLine(body, 0.85, 0.85, 0.85, true) end
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

-- v2.0.0 (audit v1.6.1 SA-01 HIGH): Arabic-font availability detection
-- and romanized↔Arabic name resolution. Probes K.ARABIC_FONT once at
-- first call: creates a throwaway FontString and tries SetFont. If
-- SetFont returns true (font loadable), Arabic strings are rendered
-- correctly and the helper returns the Arabic form. If false (file
-- missing or unsupported by client), falls back to the romanized form.
-- Cached after first probe so we don't re-test on every call.
--
-- The helper is safe under EVERY existing call site — passing an
-- unknown key returns the key unchanged (no crash, no formatting
-- glitch).
local _arabicProbed, _arabicAvailable = false, false
local function arabicAvailable()
    if _arabicProbed then return _arabicAvailable end
    _arabicProbed = true
    if not K.ARABIC_FONT or not f or not f.CreateFontString then
        return false
    end
    -- Probe: create an off-screen FontString and try SetFont.
    -- v3.0.1 (audit v3.0.0 HIGH#2): pcall returns (ok, retval). The
    -- SetFont method itself returns `true` if the font file loaded,
    -- `false` if it couldn't be opened. Pre-fix `_arabicAvailable =
    -- (ok == true)` set to true whenever pcall didn't error — i.e.,
    -- whenever the call dispatched (always). Result: on installs
    -- WITHOUT the font file present, _arabicAvailable was stuck
    -- true — SaudiName returned the Arabic glyph entry, the engine
    -- silently fell back to a default font that lacks Arabic, and
    -- buttons rendered as boxes (the v2.0.2 hotfix's exact failure
    -- mode survived). Now check the SECOND return value (the actual
    -- SetFont result) so the probe correctly detects font absence.
    local probe = f:CreateFontString(nil, "BACKGROUND", "GameFontNormal")
    if probe then
        local ok, setOk = pcall(probe.SetFont, probe, K.ARABIC_FONT, 12, "")
        _arabicAvailable = (ok == true) and (setOk == true)
        probe:Hide()
        probe:SetText("")
    end
    return _arabicAvailable
end

local function SaudiName(key)
    local entry = K.SAUDI_NAMES and K.SAUDI_NAMES[key]
    if not entry then return key end
    if arabicAvailable() then
        -- Return both forms — Arabic primary, romanized parenthetical
        -- for readers who don't read Arabic. Format: "حكم Hokm" so
        -- the visual emphasis is on the Saudi term but the Latin
        -- gloss stays for cross-language groups.
        return ("%s |cff999999%s|r"):format(entry[2], entry[1])
    end
    return entry[1]   -- romanized only
end

-- Expose for other modules (e.g. Slash.lua /baloot rules to surface
-- Arabic terms when font is available).
B.UI = B.UI or {}
B.UI.SaudiName = SaudiName
B.UI.ArabicAvailable = arabicAvailable
-- v2.2.0 UX-43 hook: slash command /baloot sound calls this to
-- re-sync the checkbox visual after toggling WHEREDNGNDB.sound.
B.UI.GetMuteBtn = function() return f and f.muteBtn end

-- v2.1.0 (audit v1.6.1 UX-31 LOW): banner fade helper. Wraps Show /
-- Hide with a soft alpha animation. Falls back to Show/Hide on hosts
-- that lack UIFrameFadeIn/Out (test harness). The banner's content
-- (text/cards) renders during the fade — alpha-only animation, no
-- layout reflow.
local function fadeBanner(b, duration, hide)
    if not b then return end
    duration = duration or 0.20
    if hide then
        if b:IsShown() and UIFrameFadeOut then
            UIFrameFadeOut(b, duration, b:GetAlpha() or 1, 0)
            -- UIFrameFadeOut doesn't auto-Hide; schedule it.
            if C_Timer and C_Timer.After then
                C_Timer.After(duration, function()
                    if b and b.Hide then b:Hide() end
                end)
            else
                b:Hide()
            end
        elseif b.Hide then
            b:Hide()
        end
    else
        if not b:IsShown() then
            b:SetAlpha(0)
            b:Show()
            if UIFrameFadeIn then
                UIFrameFadeIn(b, duration, 0, 1)
            else
                b:SetAlpha(1)
            end
        end
    end
end
B.UI.FadeBanner = fadeBanner

local function shortName(fullName)
    if not fullName then return "?" end
    return (fullName:match("^([^%-]+)") or fullName)
end

-- ----------------------------------------------------------------------
-- Build: main window
-- ----------------------------------------------------------------------

local function buildMain()
    f = CreateFrame("Frame", "WHEREDNGNFrame", UIParent, "BackdropTemplate")
    f:SetSize(740, 600)
    f:SetPoint("CENTER")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    -- v2.0.0 (audit v1.6.1 UX-24 MED): register with UISpecialFrames so
    -- pressing Escape closes the window (matches the WoW convention
    -- for every other movable, dismissable UI panel — chat config,
    -- macro window, dressing room, etc.). Pre-fix you had to click
    -- the X or `/baloot toggle` to dismiss, which players reach for
    -- after the WoW reflex of "press Escape" fails.
    if UISpecialFrames then
        table.insert(UISpecialFrames, "WHEREDNGNFrame")
    end
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        -- Audit fix: nil-safe init. The previous `if WHEREDNGNDB then`
        -- silently dropped the first drag on a fresh install before
        -- any other write site had created the table. This ensures
        -- the dragged position is always saved.
        WHEREDNGNDB = WHEREDNGNDB or {}
        local p, _, rp, x, y = self:GetPoint()
        WHEREDNGNDB.framePos = { p, rp, x, y }
    end)
    f:SetClampedToScreen(true)
    f:SetFrameStrata("HIGH")
    setBackdrop(f, true)

    -- Title
    local title = makeText(f, 16, "CENTER")
    title:SetPoint("TOP", 0, -10)
    -- v0.11.21 user-requested rename: window title now "Loot & Baloot"
    -- (the addon's friendly Saudi-Baloot brand). Internal namespace
    -- WHEREDNGN remains for code organization (no folder rename, no
    -- SavedVariables migration needed). Subtitle "(KZKZ will come)"
    -- below preserved as the tagline/branding.
    title:SetText("|cff66ddffLoot & Baloot|r")

    -- Subtitle next to the title (host's tagline / branding).
    local subtitle = makeText(f, 12, "LEFT")
    subtitle:SetPoint("LEFT", title, "RIGHT", 8, 0)
    subtitle:SetText("|cffaaaaaa(KZKZ will come)|r")

    -- Scale controls. The whole window scales as a single unit (the
    -- main frame is the parent of every child; SetScale propagates).
    -- Persisted to WHEREDNGNDB.scale and restored on Show. Placed on
    -- the top-left after the Sound checkbox so they never overlap the
    -- centered title.
    local SCALE_MIN, SCALE_MAX, SCALE_STEP = 0.7, 1.5, 0.1
    local scaleDown = makeButton(f, "−", 22, 22)
    scaleDown:SetPoint("TOPLEFT", 96, -8)
    local scaleUp = makeButton(f, "+", 22, 22)
    scaleUp:SetPoint("LEFT", scaleDown, "RIGHT", 2, 0)
    local function applyScale(s)
        s = math.max(SCALE_MIN, math.min(SCALE_MAX, s))
        WHEREDNGNDB = WHEREDNGNDB or {}
        WHEREDNGNDB.scale = s
        f:SetScale(s)
    end
    scaleDown:SetScript("OnClick", function()
        local cur = (WHEREDNGNDB and WHEREDNGNDB.scale) or 1.0
        applyScale(cur - SCALE_STEP)
    end)
    scaleUp:SetScript("OnClick", function()
        local cur = (WHEREDNGNDB and WHEREDNGNDB.scale) or 1.0
        applyScale(cur + SCALE_STEP)
    end)
    scaleDown:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine("Shrink window", 1, 1, 1)
        GameTooltip:Show()
    end)
    scaleDown:SetScript("OnLeave", function() GameTooltip:Hide() end)
    scaleUp:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine("Grow window", 1, 1, 1)
        GameTooltip:Show()
    end)
    scaleUp:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Sound toggle (top-left). Persists in WHEREDNGNDB.sound. Default
    -- ON. The Sound module already reads this flag — we just need a
    -- one-click affordance instead of a /baloot sound chat command.
    local muteBtn = CreateFrame("CheckButton", nil, f,
                                "UICheckButtonTemplate")
    muteBtn:SetSize(22, 22)
    muteBtn:SetPoint("TOPLEFT", 8, -8)
    muteBtn:SetHitRectInsets(0, -60, 0, 0)  -- extend hitbox to cover label
    if muteBtn.text then
        muteBtn.text:SetText("|cffaaaaaaSound|r")
    else
        local lbl = muteBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        lbl:SetPoint("LEFT", muteBtn, "RIGHT", 2, 1)
        lbl:SetText("|cffaaaaaaSound|r")
    end
    muteBtn:SetScript("OnShow", function(self)
        local on = not (WHEREDNGNDB and WHEREDNGNDB.sound == false)
        self:SetChecked(on)
    end)
    muteBtn:SetScript("OnClick", function(self)
        WHEREDNGNDB = WHEREDNGNDB or {}
        WHEREDNGNDB.sound = self:GetChecked() and true or false
    end)
    -- v2.2.0 (audit v1.6.1 UX-43 LOW): expose the sync-to-saved-vars
    -- closure as a frame method so /baloot sound (slash toggle) can
    -- bring the checkbox visual in line. Pre-fix the slash toggle
    -- mutated WHEREDNGNDB.sound but the open window kept showing the
    -- pre-toggle check state until the next OnShow (close/re-open).
    function muteBtn:Sync()
        local on = not (WHEREDNGNDB and WHEREDNGNDB.sound == false)
        self:SetChecked(on)
    end
    f.muteBtn = muteBtn  -- exposed for slash-toggle re-sync
    muteBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("WHEREDNGN sound", 1, 1, 1)
        GameTooltip:AddLine("Toggle card play / chime / fanfare cues.",
                            0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)
    muteBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- v3.1.0 NASHRAH (نشرة) — per-round scoreboard panel, top-left,
    -- below the Sound row. Shows R1: TeamA-delta TeamB-delta per
    -- round, then TOTAL: cumulative-A cumulative-B. Pre-v3.1.0 the
    -- only score display was the bottom-left scoreText line which
    -- showed cumulative totals — players had no easy way to see
    -- per-round deltas without scrolling chat / opening the score
    -- breakdown panel. The Nashrah aggregates everything in one
    -- compact panel.
    --
    -- v3.1.1 layout:
    --   * Removed redundant score-with-target line (TOTAL already
    --     shows the same team scores; target is fixed at 152).
    --   * Rows live inside a ScrollFrame with a 5-row viewport. When
    --     the game runs longer than 5 rounds, mouse-wheel scrolls the
    --     hidden rows into view. Auto-scrolls to the bottom on each
    --     refresh so the latest round is always visible.
    local NASHRAH_VISIBLE_ROWS = 5
    local NASHRAH_ROW_H = 12
    local NASHRAH_HEADER_H = 18
    local NASHRAH_TOTAL_GAP = 4
    local NASHRAH_TOTAL_H = 14
    local NASHRAH_PADDING = 6
    local nashrahPanel = CreateFrame("Frame", nil, f, "BackdropTemplate")
    -- Fixed total height: header + 5-row viewport + TOTAL gap + TOTAL.
    local panelHeight = NASHRAH_HEADER_H
                      + (NASHRAH_VISIBLE_ROWS * NASHRAH_ROW_H)
                      + NASHRAH_TOTAL_GAP + NASHRAH_TOTAL_H
                      + NASHRAH_PADDING
    nashrahPanel:SetSize(220, panelHeight)
    nashrahPanel:SetPoint("TOPLEFT", 8, -38)
    setBackdrop(nashrahPanel, true,
        { 0.05, 0.05, 0.06, 0.85 }, { 0.55, 0.45, 0.30, 1 }, 6, "solid")
    nashrahPanel:Hide()  -- only shown once a round has ended
    nashrahPanel.header = makeText(nashrahPanel, 11, "CENTER")
    nashrahPanel.header:SetPoint("TOP", 0, -4)
    nashrahPanel.header:SetText("|cffd9b56b— NASHRAH —|r")

    -- v3.1.1 ScrollFrame for per-round rows. Viewport height = 5 rows;
    -- scrollChild height grows with #hist. Mouse-wheel scrolls when
    -- count exceeds 5; otherwise no scroll bar / no wheel response
    -- (handler clamps to range).
    local viewportH = NASHRAH_VISIBLE_ROWS * NASHRAH_ROW_H
    local scrollFrame = CreateFrame("ScrollFrame", nil, nashrahPanel)
    scrollFrame:SetPoint("TOPLEFT", 8, -NASHRAH_HEADER_H)
    scrollFrame:SetSize(204, viewportH)  -- 220 panel - 16 horizontal padding
    scrollFrame:EnableMouseWheel(true)
    scrollFrame:SetScript("OnMouseWheel", function(self, delta)
        local cur = self:GetVerticalScroll() or 0
        local maxScroll = self:GetVerticalScrollRange() or 0
        -- delta = +1 (wheel up) → scroll up (decrease offset);
        -- delta = -1 (wheel down) → scroll down (increase offset).
        local nxt = cur - (delta * NASHRAH_ROW_H)
        nxt = math.max(0, math.min(maxScroll, nxt))
        self:SetVerticalScroll(nxt)
    end)
    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetSize(204, viewportH)  -- resized in renderer
    scrollFrame:SetScrollChild(scrollChild)
    nashrahPanel.scrollFrame = scrollFrame
    nashrahPanel.scrollChild = scrollChild
    -- Rows live in scrollChild now (so mouse wheel scrolls them).
    nashrahPanel.rows = {}

    -- TOTAL row anchored at the bottom of the panel (below the scroll
    -- viewport). Fixed position regardless of row count.
    nashrahPanel.totalLine = makeText(nashrahPanel, 11, "LEFT")
    nashrahPanel.totalLine:SetPoint(
        "TOPLEFT", 8,
        -(NASHRAH_HEADER_H + viewportH + NASHRAH_TOTAL_GAP))
    f.nashrahPanel = nashrahPanel

    gameIDText = makeText(f, 11, "RIGHT")
    gameIDText:SetPoint("TOPRIGHT", -36, -12)

    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 0, 0)
    close:SetScript("OnClick", function() U.Hide() end)

    -- Reset button under the game-code line. Uses a Blizzard
    -- StaticPopup so the confirmation is unmissable (a single click
    -- on the button alone does NOT reset the game).
    StaticPopupDialogs["WHEREDNGN_RESET_CONFIRM"] = {
        text         = "Reset WHEREDNGN to idle? Current game state will be lost.",
        button1      = "Reset",
        button2      = "Cancel",
        OnAccept     = function()
            -- v3.0.1 (audit v3.0.0 CFI-01 CRITICAL): mirror Slash.lua
            -- reset's MP-71 host-gone broadcast + heartbeat stop on
            -- the popup-accept path. Pre-fix the slash command had
            -- the broadcast guarded behind the popup branch (so it
            -- only fired on the bypass-popup path), and the popup
            -- itself only did local teardown — the most common reset
            -- path (host-mid-round) silently skipped both. Remotes
            -- waited 45s for heartbeat-timeout. Now both the popup
            -- and the slash bypass route through the same teardown.
            if B.State and B.State.s and B.State.s.isHost
               and B.State.s.gameID
               and B.Net and B.Net.SendLobby then
                -- Empty seat array: remotes' _OnLobby treats this as
                -- host-gone signal (v2.1.0 MP-71). Drops sticky lobby.
                B.Net.SendLobby({}, B.State.s.gameID)
            end
            if B.Net and B.Net.StopHostHeartbeat then
                B.Net.StopHostHeartbeat()
            end
            if B._lobbyTicker then
                B._lobbyTicker:Cancel()
                B._lobbyTicker = nil
            end
            -- 10th-audit fix: mirror /baloot reset's full cleanup.
            -- Without bumping _redealGen, an in-flight 3s redeal
            -- callback would still spawn a ghost round into IDLE.
            -- Without CancelTurnTimer / CancelLocalWarn, stale AFK
            -- timer or T-10s pre-warn ping could fire after reset.
            B._redealGen = (B._redealGen or 0) + 1
            if B.Net then
                if B.Net.CancelTurnTimer then B.Net.CancelTurnTimer() end
                if B.Net.CancelLocalWarn then B.Net.CancelLocalWarn() end
            end
            S.Reset()
            S.SetLocalName(GetUnitName("player", true))
            U.Refresh()
            print("|cff66ddffWHEREDNGN|r reset.")
        end,
        timeout       = 0,
        whileDead     = true,
        hideOnEscape  = true,
        preferredIndex = 3,
    }
    local resetBtn = makeButton(f, "Reset", 70, 22)
    resetBtn:SetPoint("TOPRIGHT", gameIDText, "BOTTOMRIGHT", 0, -4)
    resetBtn:SetScript("OnClick", function()
        StaticPopup_Show("WHEREDNGN_RESET_CONFIRM")
    end)
    -- v2.0.0 (audit v1.6.1 PJ-06): lobby/window control button tooltip.
    -- v3.0.1 (audit v3.0.0 PM-09): removed dead-code override block.
    -- Pre-fix setLobbyTooltip wired the host-broadcast-reset warning,
    -- then a SECOND OnEnter handler immediately overrode it with a
    -- less informative message (older v1.x text). The setLobbyTooltip
    -- body was permanently dead. Single tooltip now wins.
    setLobbyTooltip(resetBtn, "Reset",
        "Wipe local game state and return to idle. If you are the "
        .. "HOST mid-round, this also kicks all other players out of "
        .. "the game (a confirm prompt is shown first).")
    f.resetBtn = resetBtn

    -- Minimal-background toggle (bottom-left). Hides the outer green
    -- backdrop, seat-badge backgrounds and the local player bar
    -- background so only the cards + the middle felt square ("the
    -- green") remain visible. Useful for streaming or cluttered views.
    local minBgBtn = makeButton(f, "Min", 60, 22)
    minBgBtn:SetPoint("BOTTOMLEFT", 12, 30)
    local function applyMinimalBg(on)
        WHEREDNGNDB = WHEREDNGNDB or {}
        WHEREDNGNDB.minimalBg = on and true or false
        local outerA = on and 0 or 1.0
        if f and f.SetBackdropColor and COL.feltDark then
            local r, g, b = COL.feltDark[1], COL.feltDark[2], COL.feltDark[3]
            f:SetBackdropColor(r, g, b, outerA)
            -- Edge softens too: keep the fine border at low alpha so a
            -- moved window is still grabbable but not visually heavy.
            local er, eg, eb = (COL.woodEdge or {0.2,0.2,0.2,1})[1],
                               (COL.woodEdge or {0.2,0.2,0.2,1})[2],
                               (COL.woodEdge or {0.2,0.2,0.2,1})[3]
            f:SetBackdropBorderColor(er, eg, eb, on and 0.15 or 1.0)
        end
        for _, sb in pairs(seatBadges) do
            local fr = sb and sb.frame
            if fr and fr.SetBackdropColor then
                local r, g, b = (COL.feltLight or {0,0,0,1})[1],
                                (COL.feltLight or {0,0,0,1})[2],
                                (COL.feltLight or {0,0,0,1})[3]
                fr:SetBackdropColor(r, g, b, outerA)
                fr:SetBackdropBorderColor(0.3, 0.3, 0.3, on and 0.25 or 1.0)
            end
        end
        if tablePanel and tablePanel.localBar
           and tablePanel.localBar.SetBackdropColor then
            local r, g, b = (COL.feltLight or {0,0,0,1})[1],
                            (COL.feltLight or {0,0,0,1})[2],
                            (COL.feltLight or {0,0,0,1})[3]
            tablePanel.localBar:SetBackdropColor(r, g, b, outerA)
        end
    end
    minBgBtn:SetScript("OnClick", function()
        local now = WHEREDNGNDB and WHEREDNGNDB.minimalBg
        applyMinimalBg(not now)
    end)
    minBgBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Toggle minimal background", 1, 1, 1)
        GameTooltip:AddLine("Hides the outer green frame so only the"
            .. " felt trick area stays visible.", 0.85, 0.85, 0.85, true)
        GameTooltip:Show()
    end)
    minBgBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    -- Stash for U.Show to re-apply on first display.
    f._applyMinimalBg = applyMinimalBg

    -- Status line at top
    statusText = makeText(f, 12, "CENTER")
    statusText:SetPoint("TOP", 0, -32)

    -- Score / contract / round line at the very bottom
    scoreText = makeText(f, 12, "LEFT")
    scoreText:SetPoint("BOTTOMLEFT", 12, 8)

    roundText = makeText(f, 12, "RIGHT")
    roundText:SetPoint("BOTTOMRIGHT", -12, 8)

    -- Contract banner at the bottom of the main frame. Sits ABOVE the
    -- score / round line so long team names + score don't get covered.
    -- Wood-edged plate so the contract reads at a glance.
    local contractBg = CreateFrame("Frame", nil, f, "BackdropTemplate")
    contractBg:SetSize(360, 22)
    contractBg:SetPoint("BOTTOM", f, "BOTTOM", 0, 30)
    setBackdrop(contractBg, true,
        { 0.06, 0.10, 0.07, 0.92 }, COL.legalEdge, 8, "solid")
    contractBg:Hide()  -- only shown once a contract exists
    f.contractBg = contractBg

    contractText = contractBg:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    contractText:SetFont(K.CARD_FONT, 15, "OUTLINE")
    contractText:SetPoint("CENTER", 0, 0)
    contractText:SetJustifyH("CENTER")

    f:Hide()
end

-- ----------------------------------------------------------------------
-- Build: lobby panel
-- ----------------------------------------------------------------------

local function buildLobby()
    lobbyPanel = CreateFrame("Frame", nil, f)
    lobbyPanel:SetPoint("TOPLEFT", 14, -56)
    lobbyPanel:SetPoint("BOTTOMRIGHT", -14, 30)

    local h = makeText(lobbyPanel, 14, "CENTER")
    h:SetPoint("TOP", 0, -8)
    h:SetText("|cffaaaaaaLobby|r")

    -- Team-name inputs (host-only). Edits broadcast to all clients via
    -- MSG_TEAMS so everyone sees matching labels in the score line and
    -- the round-end banner.
    local teamRow = CreateFrame("Frame", nil, lobbyPanel)
    teamRow:SetSize(440, 24)
    teamRow:SetPoint("TOP", h, "BOTTOM", 0, -10)
    local function makeTeamEdit(letter, anchorX)
        local lbl = makeText(teamRow, 11, "RIGHT")
        lbl:SetPoint("LEFT", teamRow, "LEFT", anchorX, 0)
        lbl:SetWidth(54)
        lbl:SetText(("|cff66ff88Team %s|r"):format(letter))
        local box = CreateFrame("EditBox", nil, teamRow, "InputBoxTemplate")
        box:SetSize(140, 18)
        box:SetPoint("LEFT", lbl, "RIGHT", 8, 0)
        box:SetAutoFocus(false)
        box:SetMaxLetters(20)
        box:SetFontObject("ChatFontNormal")
        box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        local function commit(self)
            self:ClearFocus()
            if not S.s.isHost then return end
            local a = lobbyPanel.teamA:GetText() or ""
            local b = lobbyPanel.teamB:GetText() or ""
            S.ApplyTeamNames(a, b)
            if B.Net and B.Net.SendTeams then B.Net.SendTeams(a, b) end
            U.Refresh()
        end
        box:SetScript("OnEnterPressed", commit)
        box:SetScript("OnEditFocusLost", commit)
        return box
    end
    lobbyPanel.teamA = makeTeamEdit("A", 16)
    lobbyPanel.teamB = makeTeamEdit("B", 230)

    -- Party-members sidebar. Lists the current WoW party so the host
    -- can see who's around to invite without alt-tabbing to the unit
    -- frames. Each row shows the short name + seat status (in seat N
    -- / available). Refreshed on GROUP_ROSTER_UPDATE plus every UI
    -- refresh so an unfilled seat updates immediately.
    local partyPanel = CreateFrame("Frame", nil, lobbyPanel, "BackdropTemplate")
    partyPanel:SetSize(180, 200)
    partyPanel:SetPoint("TOPRIGHT", -8, -76)
    setBackdrop(partyPanel, true, COL.feltLight, COL.woodEdge)
    local pHeader = makeText(partyPanel, 12, "CENTER")
    pHeader:SetPoint("TOP", 0, -6)
    pHeader:SetText("|cffaaaaaaParty|r")
    partyPanel.rows = {}
    for i = 1, 5 do
        local row = makeText(partyPanel, 11, "LEFT")
        row:SetPoint("TOPLEFT", 10, -24 - (i - 1) * 18)
        row:SetWidth(160)
        row:SetText("")
        partyPanel.rows[i] = row
    end
    lobbyPanel.partyPanel = partyPanel

    -- 4 seat slots
    local seatLabels = { "Seat 1 (Host)", "Seat 2", "Seat 3 (Host's partner)", "Seat 4" }
    lobbyPanel.seatTexts = {}
    lobbyPanel.swapBtns  = {}
    -- Re-audit fix V5: track the row frames so SetFeltTheme can
    -- re-tint their backdrop (default uses COL.feltDark via setBackdrop's
    -- bgRGBA fallback).
    lobbyPanel.seatRows  = {}
    for i = 1, 4 do
        local row = CreateFrame("Frame", nil, lobbyPanel, "BackdropTemplate")
        -- Anchor each row to the lobby's left edge and the party panel's
        -- left edge so the rows auto-fit and don't overlap the sidebar.
        -- Vertical offset is the same on both anchors so the row stays
        -- horizontal regardless of how wide the lobby panel is.
        row:SetHeight(28)
        row:SetPoint("TOPLEFT",  lobbyPanel, "TOPLEFT",  12, -76 - (i - 1) * 34)
        row:SetPoint("TOPRIGHT", partyPanel, "TOPLEFT",  -8,      -(i - 1) * 34)
        setBackdrop(row, true)
        lobbyPanel.seatRows[i] = row
        local lbl = makeText(row, 12, "LEFT")
        lbl:SetPoint("LEFT", 8, 0)
        lbl:SetText(seatLabels[i])
        local nm = makeText(row, 12, "RIGHT")
        nm:SetPoint("RIGHT", -8, 0)
        nm:SetText("|cff666666(empty)|r")
        lobbyPanel.seatTexts[i] = nm
        -- Swap-down button on seats 1-3 only (last seat has nobody to
        -- swap with). Host-only; visible only while in lobby. Used to
        -- re-team — e.g. move a friend from seat 2 (Team B) to seat 3
        -- (Team A) so the two humans share a side against the bots.
        if i <= 3 then
            local sw = makeButton(row, "↕", 22, 22)
            sw:SetPoint("LEFT", lbl, "RIGHT", 8, 0)
            local fromSeat, toSeat = i, i + 1
            sw:SetScript("OnClick", function()
                if not S.s.isHost then return end
                if S.HostSwapSeats(fromSeat, toSeat) then
                    net().SendLobby(S.s.seats, S.s.gameID)
                    U.Refresh()
                end
            end)
            sw:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:AddLine(
                    ("Swap seat %d ↔ seat %d"):format(fromSeat, toSeat), 1, 1, 1)
                GameTooltip:AddLine("Teams are seat-parity (1+3 vs 2+4); use these"
                    .. " to put the right players on the right team.",
                    0.85, 0.85, 0.85, true)
                GameTooltip:Show()
            end)
            sw:SetScript("OnLeave", function() GameTooltip:Hide() end)
            lobbyPanel.swapBtns[i] = sw
        end
        -- v3.0 (audit v1.6.1 MP-41 MED): Kick button on seats 2-4
        -- (host can't kick themselves). Lobby-phase only. Pre-fix
        -- the only way to remove a player was waiting for them to
        -- /baloot reset / leave the party — host had no graceful
        -- "no thanks, you're out" path. Kick removes the seat
        -- record + re-broadcasts the lobby; the kicked client sees
        -- their seat go away on next MSG_LOBBY.
        if i >= 2 then
            local kb = makeButton(row, "✕", 22, 22)
            kb:SetPoint("RIGHT", row, "RIGHT", -4, 0)
            local kSeat = i
            kb:SetScript("OnClick", function()
                if not S.s.isHost then return end
                if S.s.phase ~= K.PHASE_LOBBY then return end
                if not S.s.seats or not S.s.seats[kSeat] then return end
                S.HostKickSeat(kSeat)
                if net().SendLobby then
                    net().SendLobby(S.s.seats, S.s.gameID)
                end
                U.Refresh()
            end)
            kb:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_LEFT")
                GameTooltip:AddLine(("Kick seat %d"):format(kSeat), 1, 0.5, 0.5)
                GameTooltip:AddLine("Host only. Lobby phase only. "
                    .. "The kicked player sees their seat clear on "
                    .. "the next lobby broadcast. Replace with bot "
                    .. "via Fill Bots.", 0.85, 0.85, 0.85, true)
                GameTooltip:Show()
            end)
            kb:SetScript("OnLeave", function() GameTooltip:Hide() end)
            row.kickBtn = kb
        end
    end

    -- Host or Join buttons
    hostStartBtn = makeButton(lobbyPanel, "Start Round", 120, 26)
    hostStartBtn:SetPoint("BOTTOM", -130, 12)
    hostStartBtn:SetScript("OnClick", function()
        if not S.s.isHost then return end
        if not S.LobbyFull() then
            print("|cffff5555WHEREDNGN|r: lobby not full")
            return
        end
        net().HostStartRound()
    end)
    setLobbyTooltip(hostStartBtn, "Start Round",
        "Host: deal cards and begin round 1. Requires all 4 seats "
        .. "filled (humans + bots).")

    local hostNewBtn = makeButton(lobbyPanel, "Host Game", 120, 26)
    hostNewBtn:SetPoint("BOTTOM", 0, 12)
    hostNewBtn:SetScript("OnClick", function()
        -- 4th-audit X9-2 fix: refuse to /host while a game is
        -- already in progress. HostBeginLobby calls reset() which
        -- silently destroys the active round/game with no
        -- confirmation. Only IDLE / GAME_END are safe states to
        -- start a fresh lobby from.
        if S.s.phase ~= K.PHASE_IDLE and S.s.phase ~= K.PHASE_GAME_END then
            print("|cffff5555WHEREDNGN|r already in a game — /baloot reset first.")
            return
        end
        -- 4th-audit X9-1 fix: cancel any prior lobby ticker before
        -- arming a new one. Slash.lua's /baloot host had this guard
        -- (commit 2803dcf) but the lobby button was missed —
        -- repeated clicks would otherwise leak overlapping tickers
        -- and double the lobby broadcast rate.
        if B._lobbyTicker then
            B._lobbyTicker:Cancel(); B._lobbyTicker = nil
        end
        local id = S.HostBeginLobby()
        if id then
            net().SendLobby(S.s.seats, id)
            B._lobbyTicker = C_Timer.NewTicker(K.LOBBY_BROADCAST_SEC, function()
                if S.s.isHost and S.s.phase == K.PHASE_LOBBY then
                    net().SendHostAnnounce(S.s.gameID)
                else
                    if B._lobbyTicker then B._lobbyTicker:Cancel(); B._lobbyTicker = nil end
                end
            end)
            net().SendHostAnnounce(id)
            U.Refresh()
        end
    end)
    setLobbyTooltip(hostNewBtn, "Host Game",
        "Become the host of a new Saudi Baloot game. Broadcasts an "
        .. "invite to your party. Solo hosting is fine — fill empty "
        .. "seats with bots before starting.")

    -- Fill empty seats with bots
    local fillBotsBtn = makeButton(lobbyPanel, "Fill Bots", 120, 26)
    fillBotsBtn:SetPoint("BOTTOM", 130, 12)
    fillBotsBtn:SetScript("OnClick", function()
        if not S.s.isHost then return end
        local n = S.HostAddBots()
        if n > 0 then
            net().SendLobby(S.s.seats, S.s.gameID)
            U.Refresh()
        end
    end)
    lobbyPanel.fillBotsBtn = fillBotsBtn
    setLobbyTooltip(fillBotsBtn, "Fill Bots",
        "Host: claim every empty seat with a bot. Bots play at the "
        .. "tier you've selected (Basic / Advanced / M3lm / Fzloky / "
        .. "Saudi Master).")

    -- v3.2.11 private raid-lobby invitee editor. Host-only, lobby-only,
    -- and only meaningful in a raid/instance group (hidden in a normal
    -- party — a party host can never reach this, guaranteeing
    -- inviteAllow stays nil and PARTY behavior is unchanged). Adding
    -- the first invitee implicitly opts the host into raid-lobby mode
    -- (S.HostAddInvitee). See the design doc in .swarm_findings/.
    local invPanel = CreateFrame("Frame", nil, lobbyPanel)
    invPanel:SetSize(440, 24)
    invPanel:SetPoint("BOTTOM", 0, 44)
    local invLbl = makeText(invPanel, 11, "LEFT")
    invLbl:SetPoint("LEFT", invPanel, "LEFT", 0, 0)
    invLbl:SetWidth(52)
    invLbl:SetText("|cff66ddffInvite|r")
    local invBox = CreateFrame("EditBox", nil, invPanel, "InputBoxTemplate")
    invBox:SetSize(150, 18)
    invBox:SetPoint("LEFT", invLbl, "RIGHT", 8, 0)
    invBox:SetAutoFocus(false)
    invBox:SetMaxLetters(48)
    invBox:SetFontObject("ChatFontNormal")
    invBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    local function doInvite(nm)
        if not nm or nm == "" then return end
        local added = S.HostAddInvitee(nm)
        if added then
            invBox:SetText("")
            net().SendLobby(S.s.seats, S.s.gameID)
            net().SendHostAnnounce(S.s.gameID)
            U.Refresh()
        else
            print("|cffff5555WHEREDNGN|r: could not invite \""
                .. tostring(nm) .. "\" (host? lobby? yourself?)")
        end
    end
    invBox:SetScript("OnEnterPressed", function(self)
        doInvite((self:GetText() or ""):match("^%s*(.-)%s*$"))
        self:ClearFocus()
    end)
    local invAddBtn = makeButton(invPanel, "Add", 52, 22)
    invAddBtn:SetPoint("LEFT", invBox, "RIGHT", 6, 0)
    invAddBtn:SetScript("OnClick", function()
        doInvite((invBox:GetText() or ""):match("^%s*(.-)%s*$"))
    end)
    local invTgtBtn = makeButton(invPanel, "Add Target", 84, 22)
    invTgtBtn:SetPoint("LEFT", invAddBtn, "RIGHT", 6, 0)
    invTgtBtn:SetScript("OnClick", function()
        if UnitExists and UnitExists("target") and GetUnitName then
            doInvite(GetUnitName("target", true))
        else
            print("|cffff5555WHEREDNGN|r: no target to invite")
        end
    end)
    local invClrBtn = makeButton(invPanel, "Clear", 52, 22)
    invClrBtn:SetPoint("LEFT", invTgtBtn, "RIGHT", 6, 0)
    invClrBtn:SetScript("OnClick", function()
        for _, n in ipairs(S.HostInvitees()) do S.HostRemoveInvitee(n) end
        net().SendHostAnnounce(S.s.gameID)
        U.Refresh()
    end)
    setLobbyTooltip(invTgtBtn, "Invitees (raid/instance)",
        "In a raid or instance group WHEREDNGN does NOT broadcast a "
        .. "public invite. Add the 3 players you want; only they see "
        .. "the invite and only they may take a seat. Adding the first "
        .. "invitee starts the private game advertisement.")
    local invList = makeText(lobbyPanel, 11, "CENTER")
    invList:SetPoint("BOTTOM", invPanel, "TOP", 0, 4)
    invList:SetWidth(440)
    invList:SetText("")
    lobbyPanel.invPanel = invPanel
    lobbyPanel.invList  = invList

    -- Bot difficulty selector. Two checkboxes stacked just above the
    -- Fill Bots button: "Advanced" (functional) and "M3lm" (greyed —
    -- reserved for the deeper heuristic tier still in design). Both
    -- are host-side toggles since bots only run on the host. The
    -- saved-variable flags live in WHEREDNGNDB.advancedBots /
    -- WHEREDNGNDB.m3lmBots; Bot.IsAdvanced / IsM3lm read them.
    local function makeBotDifficultyCheck(label, anchorY, enabled, getter, setter, tooltip)
        local cb = CreateFrame("CheckButton", nil, lobbyPanel,
                               "UICheckButtonTemplate")
        cb:SetSize(20, 20)
        cb:SetPoint("BOTTOM", -90, anchorY)
        local txt = makeText(cb, 11, "LEFT")
        txt:SetPoint("LEFT", cb, "RIGHT", 4, 0)
        txt:SetText(label)
        cb:SetChecked(getter() and true or false)
        if not enabled then
            cb:Disable()
            txt:SetTextColor(0.55, 0.55, 0.55)
        end
        cb:SetScript("OnClick", function(self)
            if not enabled then return end
            setter(self:GetChecked() and true or false)
            if B.UI and B.UI.Refresh then B.UI.Refresh() end
        end)
        if tooltip then
            cb:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:AddLine(label, 1, 1, 1)
                GameTooltip:AddLine(tooltip, 0.85, 0.85, 0.85, true)
                GameTooltip:Show()
            end)
            cb:SetScript("OnLeave", function() GameTooltip:Hide() end)
        end
        return cb
    end
    -- Player-reported UI fix: 4-tier checkbox stack at y={78,56,34,12}
    -- placed Saudi Master at y=12, the same vertical band as the
    -- "Start Round" / "Host Game" / "Fill Bots" button row (y=12,
    -- height 26). The Saudi Master label visually overlapped the
    -- centred Host Game button. Shift the entire stack up by 30
    -- (new y={108,86,64,42}) so Saudi Master clears the button row
    -- with ~24px breathing room. Cards/Felt cycle buttons in the
    -- right column are bumped to match (line 908/974) so the top
    -- pair (Advanced+Cards, M3lm+Felt) stays visually aligned.
    lobbyPanel.advancedCheck = makeBotDifficultyCheck(
        "Advanced", 108, true,
        function() return WHEREDNGNDB and WHEREDNGNDB.advancedBots end,
        function(v) WHEREDNGNDB = WHEREDNGNDB or {}; WHEREDNGNDB.advancedBots = v end,
        "Bots use human-style heuristics: partner-bid reads, "
            .. "AKA self-call, position-aware play, score-position "
            .. "threshold modifiers. Host only — affects bots in "
            .. "this game.\n\n"
            .. "|cff999999Tier 2/5. Higher tiers (M3lm / Fzloky / "
            .. "Saudi Master) STRICTLY EXTEND this layer — checking "
            .. "any of them activates Advanced too.|r")
    lobbyPanel.m3lmCheck = makeBotDifficultyCheck(
        "M3lm", 86, true,
        function() return WHEREDNGNDB and WHEREDNGNDB.m3lmBots end,
        function(v) WHEREDNGNDB = WHEREDNGNDB or {}; WHEREDNGNDB.m3lmBots = v end,
        "Master tier (pro level). Layers on top of Advanced: "
            .. "tracks each opponent and partner's play style across "
            .. "the game (trump aggression, Bel frequency), uses "
            .. "match-point urgency for finer score-position calls, "
            .. "and ramps escalations faster when partner has already "
            .. "Bel'd / Bel x3'd.\n\n"
            .. "|cff999999Tier 3/5. Strictly EXTENDS Advanced (auto-on). "
            .. "Higher tiers (Fzloky / Saudi Master) extend this in turn.|r")
    lobbyPanel.fzlokyCheck = makeBotDifficultyCheck(
        "Fzloky", 64, true,
        function() return WHEREDNGNDB and WHEREDNGNDB.fzlokyBots end,
        function(v) WHEREDNGNDB = WHEREDNGNDB or {}; WHEREDNGNDB.fzlokyBots = v end,
        "Signal-aware tier on top of M3lm. Reads partner's first "
            .. "off-suit discard as a high/low suit-preference "
            .. "signal: a high discard (A/T/K) means \"lead this\", "
            .. "a low discard (7/8) means \"avoid this\". Bot biases "
            .. "lead choice accordingly.\n\n"
            .. "|cff999999Tier 4/5. Strictly EXTENDS Advanced + M3lm "
            .. "(both auto-on). Saudi Master extends this further.|r")
    lobbyPanel.saudiMasterCheck = makeBotDifficultyCheck(
        "Saudi Master", 42, true,
        function() return WHEREDNGNDB and WHEREDNGNDB.saudiMasterBots end,
        function(v) WHEREDNGNDB = WHEREDNGNDB or {}; WHEREDNGNDB.saudiMasterBots = v end,
        "Top tier (ISMCTS-flavoured). At each play decision, the "
            .. "bot samples 30 plausible opponent hands consistent "
            .. "with bidding history + observed plays + voids, then "
            .. "for each candidate card simulates the rest of the "
            .. "round across all worlds. Picks the card with the "
            .. "best aggregate outcome. ~150 ms per move.\n\n"
            .. "|cff999999Tier 5/5 (top). Strictly EXTENDS Advanced + "
            .. "M3lm + Fzloky (all auto-on). No higher tier.|r")

    -- Theme cycle buttons. Two independent axes the user can mix and
    -- match: card style (face / back art) and felt theme (table felt
    -- + backdrop tint). Sit on the left column of the lobby, mirroring
    -- the bot-tier checkboxes on the right. Each button label shows
    -- the current selection; clicking cycles to the next entry.
    local function makeCycleBtn(prefix, anchorY,
                                getActiveFn, getListFn, setFn, tooltipText)
        local b = makeButton(lobbyPanel, prefix .. ": ?", 130, 22)
        b:SetPoint("BOTTOM", 90, anchorY)
        local function refresh()
            if not (getActiveFn and getListFn) then return end
            local active = getActiveFn()
            local label
            for _, t in ipairs(getListFn()) do
                if t.id == active then label = t.name end
            end
            b:SetText(prefix .. ": " .. (label or active))
        end
        b:SetScript("OnClick", function()
            if not (getActiveFn and getListFn and setFn) then return end
            local list = getListFn()
            if #list == 0 then return end
            local active = getActiveFn()
            local idx = 1
            for i, t in ipairs(list) do if t.id == active then idx = i end end
            -- Audit fix: avoid shadowing the `next` builtin (foot-gun
            -- if any future edit calls `next(t, k)` in this closure).
            local nextEntry = list[(idx % #list) + 1]
            if setFn(nextEntry.id) then refresh() end
        end)
        b:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(prefix, 1, 1, 1)
            GameTooltip:AddLine(tooltipText, 0.85, 0.85, 0.85, true)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        refresh()
        return b, refresh
    end

    -- Player-reported UI fix: bumped Cards/Felt y to match the new
    -- bot checkbox stack (Advanced=108, M3lm=86) so the top two rows
    -- still pair visually. Was: Cards=78, Felt=56.
    local cardsBtn, cardsRefresh = makeCycleBtn(
        "Cards", 108,
        U.GetActiveCardStyle, U.GetCardStyles, U.SetCardStyle,
        "Card face / back art set. Independent of the felt — mix a "
            .. "burgundy deck with a green felt if you like. "
            .. "Persists in saved variables.")

    -- 3-card preview strip to the right of the Cards button. Shows
    -- AS / KH / TD at the currently-active card style so the user
    -- can see the actual face art before committing to a cycle.
    -- A (ace), K (face), 10 (number) covers all three card-art
    -- categories per the user spec; mixed suits (S/H/D) demonstrate
    -- the four-color suit tinting.
    local function buildCardsPreview()
        local strip = CreateFrame("Frame", nil, lobbyPanel)
        local W, H, STRIDE = 22, 32, 18
        strip:SetSize(STRIDE * 2 + W, H)
        strip:SetPoint("LEFT", cardsBtn, "RIGHT", 6, 0)
        strip.slots = {}
        for i = 1, 3 do
            local sf = CreateFrame("Frame", nil, strip)
            sf:SetSize(W, H)
            sf:SetPoint("LEFT", strip, "LEFT", (i - 1) * STRIDE, 0)
            sf:SetFrameLevel(strip:GetFrameLevel() + i)  -- later on top
            local edge = sf:CreateTexture(nil, "BACKGROUND", nil, 0)
            edge:SetAllPoints(sf)
            edge:SetColorTexture(COL.cardEdge[1], COL.cardEdge[2],
                                 COL.cardEdge[3], 1.0)
            local body = sf:CreateTexture(nil, "BACKGROUND", nil, 1)
            body:SetPoint("TOPLEFT", sf, "TOPLEFT", 1, -1)
            body:SetPoint("BOTTOMRIGHT", sf, "BOTTOMRIGHT", -1, 1)
            body:SetColorTexture(COL.cardFace[1], COL.cardFace[2],
                                 COL.cardFace[3], 1.0)
            local tex = sf:CreateTexture(nil, "ARTWORK")
            tex:SetPoint("TOPLEFT", sf, "TOPLEFT", 1, -1)
            tex:SetPoint("BOTTOMRIGHT", sf, "BOTTOMRIGHT", -1, 1)
            sf.tex = tex
            strip.slots[i] = sf
        end
        return strip
    end
    local cardsPreview = buildCardsPreview()
    local PREVIEW_CARDS = { "AS", "KH", "TD" }
    local function refreshCardsPreview()
        for i, card in ipairs(PREVIEW_CARDS) do
            local sf = cardsPreview.slots[i]
            local path = cardTexturePath(card)
            if path then
                sf.tex:SetTexture(path)
                sf.tex:Show()
            else
                sf.tex:Hide()
            end
        end
    end
    refreshCardsPreview()
    -- Re-render the preview every time the user cycles, on top of the
    -- normal label refresh. SetCardStyle's own U.Refresh() rebuilds
    -- the in-game cards (renderHand etc.) but doesn't reach this
    -- lobby-panel preview.
    local cardsCycleOnClick = cardsBtn:GetScript("OnClick")
    cardsBtn:SetScript("OnClick", function(self, button)
        if cardsCycleOnClick then cardsCycleOnClick(self, button) end
        refreshCardsPreview()
    end)

    local feltBtn, feltRefresh = makeCycleBtn(
        "Felt", 86,
        U.GetActiveFeltTheme, U.GetFeltThemes, U.SetFeltTheme,
        "Table felt texture + the backdrop colors around it. "
            .. "Independent of the card style. Persists in saved "
            .. "variables.")

    lobbyPanel.cardsBtn          = cardsBtn
    lobbyPanel.cardsBtnUpdate    = cardsRefresh
    lobbyPanel.cardsPreview      = cardsPreview
    lobbyPanel.cardsPreviewRefresh = refreshCardsPreview
    lobbyPanel.feltBtn           = feltBtn
    lobbyPanel.feltBtnUpdate     = feltRefresh

    joinBtn = makeButton(lobbyPanel, "Join", 100, 26)
    joinBtn:SetPoint("BOTTOM", 0, 44)
    joinBtn:SetScript("OnClick", function()
        if S.s.pendingHost then
            if not S.s.localName then
                S.SetLocalName(GetUnitName("player", true))
            end
            net().SendJoin(S.s.pendingHost.gameID)
        end
    end)
    setLobbyTooltip(joinBtn, "Join",
        "Accept a pending Saudi Baloot invite. Active only when "
        .. "another player has invited you (chat line + popup will "
        .. "have appeared). One join request per game.")
end

-- ----------------------------------------------------------------------
-- Build: table panel
-- ----------------------------------------------------------------------

-- Mini-card strip for meld display. 5 slots wide (max meld size).
-- Each slot is a Frame with an explicit cream body texture + dark
-- border textures behind the card-face TGA. We do this with manual
-- Texture layers rather than BackdropTemplate because BackdropTemplate
-- is unreliable at sizes this small — the edge file gets clipped and
-- the bg sometimes fails to render at all. The solid-texture approach
-- always shows.
local function buildMeldStrip(parent, scale)
    -- 28th-audit / player feedback: scale parameter (default 1.0)
    -- lets seat badges build a larger strip than the local bar.
    -- Players reported the seat-side meld strip was too small to read
    -- during the 5-second trick-2 reveal; scaling 1.45x gives ~40%
    -- larger glyphs while still fanning across the badge width.
    scale = scale or 1.0
    local strip = CreateFrame("Frame", nil, parent)
    local W      = math.floor(22 * scale + 0.5)
    local H      = math.floor(30 * scale + 0.5)
    local STRIDE = math.floor(18 * scale + 0.5)
    strip:SetSize(W + STRIDE * 4 + 4, H + 2)
    strip.slots = {}
    for i = 1, 5 do
        local sf = CreateFrame("Frame", nil, strip)
        sf:SetSize(W, H)
        sf:SetPoint("LEFT", strip, "LEFT", (i - 1) * STRIDE, 0)
        sf:SetFrameLevel(strip:GetFrameLevel() + i) -- later cards on top

        -- Edge: a dark slab behind everything else.
        local edge = sf:CreateTexture(nil, "BACKGROUND", nil, 0)
        edge:SetAllPoints(sf)
        edge:SetColorTexture(COL.cardEdge[1], COL.cardEdge[2],
                             COL.cardEdge[3], 1.0)

        -- Body: cream slab inset 1 px on each side, sitting on top of
        -- the edge so it reads as a 1-px frame around the body.
        local body = sf:CreateTexture(nil, "BACKGROUND", nil, 1)
        body:SetPoint("TOPLEFT", sf, "TOPLEFT", 1, -1)
        body:SetPoint("BOTTOMRIGHT", sf, "BOTTOMRIGHT", -1, 1)
        body:SetColorTexture(COL.cardFace[1], COL.cardFace[2],
                             COL.cardFace[3], 1.0)

        -- Card-face artwork on top of the body. The art TGA is
        -- transparent outside the pips, which is exactly why we need
        -- the body slab beneath.
        local tex = sf:CreateTexture(nil, "ARTWORK")
        tex:SetPoint("TOPLEFT", sf, "TOPLEFT", 1, -1)
        tex:SetPoint("BOTTOMRIGHT", sf, "BOTTOMRIGHT", -1, 1)
        tex:Hide()

        sf:Hide()
        strip.slots[i] = { frame = sf, tex = tex }
    end
    strip:Hide()
    return strip
end

local function setMeldStripCards(strip, cards, alpha)
    if not strip then return end
    local n = (cards and #cards) or 0
    if n == 0 then strip:Hide(); return end
    for i = 1, 5 do
        local slot = strip.slots[i]
        if i <= n then
            local card = cards[i]
            slot.tex:SetTexture(cardTexturePath(card))
            slot.tex:Show()
            slot.frame:SetAlpha(alpha or 1.0)
            slot.frame:Show()
        else
            slot.frame:Hide()
        end
    end
    strip:Show()
end

local function buildSeatBadge(parent, anchorCb)
    local b = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    b:SetSize(220, 100)
    setBackdrop(b, true, COL.feltLight, COL.woodEdge)
    anchorCb(b)

    -- Avatar circle: bot seats show a colored numbered badge generated
    -- in cards/avatar_<seat>.tga; human seats leave the texture hidden.
    local avatar = b:CreateTexture(nil, "OVERLAY")
    avatar:SetSize(28, 28)
    avatar:SetPoint("TOPLEFT", 6, -4)
    avatar:Hide()

    local nameTx = makeText(b, 13, "CENTER")
    nameTx:SetPoint("TOP", 0, -6)
    nameTx:SetTextColor(0.94, 0.90, 0.78)

    -- Card-back fan: 8 backs overlap by ~10px so a near-full hand
    -- looks like a fanned grip. Each back is 22×30, 12px stride.
    local backsRow = CreateFrame("Frame", nil, b)
    backsRow:SetSize(192, 36)
    backsRow:SetPoint("CENTER", 0, -2)
    local backs = {}
    local stride = 12
    for i = 1, 8 do
        local cb = makeCardBack(backsRow, 22, 32)
        cb:SetPoint("LEFT", backsRow, "LEFT", (i - 1) * stride, 0)
        cb:SetFrameLevel(backsRow:GetFrameLevel() + i)  -- later cards on top
        backs[i] = cb
    end

    local countTx = makeText(b, 11, "RIGHT")
    countTx:SetPoint("BOTTOMRIGHT", -8, 18)
    countTx:SetTextColor(0.85, 0.80, 0.55)

    local meldTx = makeText(b, 10, "CENTER")
    meldTx:SetPoint("BOTTOM", 0, 4)
    meldTx:SetTextColor(1, 0.84, 0.30)

    -- 28th-audit / player feedback: seat-side meld strip is now
    -- 1.45x larger AND anchored BELOW the badge frame (extending
    -- ~46 px down) so the cards are readable during the 5-second
    -- trick-2 reveal. The local bar's strip is kept at 1.0x +
    -- inside-the-bar to preserve its existing layout.
    local meldStrip = buildMeldStrip(b, 1.45)
    meldStrip:SetPoint("TOP", b, "BOTTOM", 0, -2)

    local dealerTx = makeText(b, 12, "LEFT")
    dealerTx:SetPoint("TOPLEFT", 6, -6)
    dealerTx:SetTextColor(1, 0.84, 0.30)

    -- 28th-audit / player feedback: bid label visible during the
    -- bidding phases (DEAL1 / DEAL2BID). When a player calls Hokm
    -- in round 2, the suit they declared is now visible to other
    -- players — so over-bidders can decide whether to Sun, Bel, or
    -- skip. Hidden once contract is finalized or play starts.
    local bidTx = makeText(b, 12, "CENTER")
    bidTx:SetPoint("TOP", nameTx, "BOTTOM", 0, -2)
    bidTx:SetTextColor(0.95, 0.78, 0.30)
    bidTx:SetText("")

    local turnGlow = b:CreateTexture(nil, "OVERLAY")
    turnGlow:SetAllPoints()
    turnGlow:SetColorTexture(unpack(COL.activeGlow))
    turnGlow:Hide()

    return { frame = b, nameText = nameTx, backs = backs,
             countText = countTx, meldText = meldTx,
             meldStrip = meldStrip,
             dealerText = dealerTx, turnGlow = turnGlow,
             bidText = bidTx,
             avatar = avatar }
end

local function buildCenterSlot(parent, anchorCb)
    local face = makeCardFace(parent, 64, 90)
    anchorCb(face.frame)
    face.frame:Hide()  -- shown only when a card is in this slot

    -- Winner glow: soft gold halo behind the card. Drawn on a child
    -- frame so it can extend BEYOND the card edge without being
    -- clipped. Hidden by default; renderCenter shows it for the seat
    -- that won the trick.
    local glow = face.frame:CreateTexture(nil, "BACKGROUND", nil, 0)
    -- Glow is shared across themes (always the warm-gold radial in
    -- cards/glow.tga). No theme-axis tracking needed for it.
    glow:SetTexture(CARD_TEX_DIR .. "glow")
    glow:SetBlendMode("ADD")
    glow:SetPoint("TOPLEFT", -16, 16)
    glow:SetPoint("BOTTOMRIGHT", 16, -16)
    glow:Hide()
    face.glow = glow
    return face
end

local function buildTable()
    tablePanel = CreateFrame("Frame", nil, f)
    tablePanel:SetPoint("TOPLEFT", 14, -56)
    -- Bottom anchor at y=60 instead of 30 so the cards don't reach
    -- down into the contract banner's vertical strip (y=30..52).
    -- Contract banner sits cleanly between the table area and the
    -- score/round line at the very bottom.
    tablePanel:SetPoint("BOTTOMRIGHT", -14, 60)

    -- Top seat (partner across the table)
    seatBadges.top = buildSeatBadge(tablePanel, function(b)
        b:SetPoint("TOP", 0, -4)
    end)

    -- Center pad: green felt for the trick area
    local centerPad = CreateFrame("Frame", nil, tablePanel, "BackdropTemplate")
    centerPad:SetSize(280, 230)
    centerPad:SetPoint("TOP", seatBadges.top.frame, "BOTTOM", 0, -10)
    setBackdrop(centerPad, true, COL.centerPad, COL.woodEdge, 10)
    tablePanel.centerPad = centerPad

    -- Felt-green tiled texture overlaid on the solid backdrop. The
    -- felt.tga is 128x128 tileable noise; SetHorizTile/SetVertTile
    -- repeats it instead of stretching, so the grain stays consistent
    -- regardless of the pad size.
    local feltTex = centerPad:CreateTexture(nil, "BACKGROUND", nil, 1)
    feltTex:SetTexture(CARD_TEX_DIR .. feltThemeData().feltTexPath,
                       "REPEAT", "REPEAT")
    feltTex:SetHorizTile(true)
    feltTex:SetVertTile(true)
    feltTex:SetPoint("TOPLEFT", 4, -4)
    feltTex:SetPoint("BOTTOMRIGHT", -4, 4)
    tablePanel.feltTex = feltTex   -- expose for SetTheme refresh

    -- Last-trick peek button: small "?" button parented to the main
    -- frame and anchored at the top-right edge, between the Reset
    -- button (which sits under the game-code line) and the right
    -- opponent's seat badge (bot 2 in a host POV). Disabled once used
    -- per hand (S.s.peekedThisRound).
    -- v2.1.0 (audit v1.6.1 PJ-70 LOW): "?" glyph was misleading —
    -- read as "help" rather than "peek last trick". Replaced with
    -- "↺" (anticlockwise revert glyph) which is the universal
    -- visual for "look back at what just happened". Tooltip retains
    -- the explicit "Peek the previous trick" text.
    local peekBtn = makeButton(f, "↺", 22, 22)
    peekBtn:SetPoint("TOPRIGHT", f.resetBtn, "BOTTOMRIGHT", 0, -8)
    peekBtn:SetScript("OnClick", function() peekLastTrick() end)
    peekBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("Peek the previous trick", 1, 1, 1)
        GameTooltip:AddLine("Once per hand, 3 seconds.", 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)
    peekBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    tablePanel.peekBtn = peekBtn

    -- Pause toggle (host-only). Suspends bot scheduling and AFK timers
    -- without dropping any in-flight state. The label flips to "Resume"
    -- while paused.
    -- v2.1.0 (audit v1.6.1 PJ-70 LOW): "II" was unstable visually
    -- (rendered as small dashes in some font scales). "‖" (double
    -- vertical bar Unicode U+2016) is the universal pause glyph and
    -- renders consistently. Tooltip retains "Pause game" explicit.
    local pauseBtn = makeButton(centerPad, "‖", 22, 22)
    pauseBtn:SetPoint("TOPRIGHT", -4, -4)
    pauseBtn:SetScript("OnClick", function()
        if not S.s.isHost then return end
        net().LocalPause(not S.s.paused)
    end)
    pauseBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine(S.s.paused and "Resume game" or "Pause game", 1, 1, 1)
        GameTooltip:AddLine("Host only. Freezes bots and the AFK timer.",
            0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)
    pauseBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    tablePanel.pauseBtn = pauseBtn

    -- "PAUSED" overlay shown while S.s.paused is true. Sits at DIALOG
    -- strata to dim the trick area, but the peek/pause buttons get
    -- bumped HIGHER (FULLSCREEN_DIALOG) below so the host can still
    -- click Resume without first dismissing the overlay.
    local pauseOverlay = CreateFrame("Frame", nil, centerPad, "BackdropTemplate")
    pauseOverlay:SetAllPoints(centerPad)
    pauseOverlay:SetFrameStrata("DIALOG")
    setBackdrop(pauseOverlay, true, { 0, 0, 0, 0.55 }, COL.legalEdge, 12, "solid")
    -- v2.0.0 (audit v1.6.1 UX-22 MED): block click pass-through. Pre-
    -- fix the overlay was visible but didn't capture mouse — clicks
    -- went through to cards / banners / buttons beneath it, which
    -- silently no-op'd downstream (UI.lua:2426 hand-card paused
    -- check, etc.). Capturing mouse here makes the pause "real" —
    -- the overlay swallows clicks instead of leaking through.
    pauseOverlay:EnableMouse(true)
    pauseOverlay:Hide()
    pauseOverlay.title = makeText(pauseOverlay, 28, "CENTER")
    pauseOverlay.title:SetPoint("CENTER", 0, 8)
    pauseOverlay.title:SetText("|cffffd055PAUSED|r")
    pauseOverlay.sub = makeText(pauseOverlay, 12, "CENTER")
    pauseOverlay.sub:SetPoint("CENTER", 0, -22)
    pauseOverlay.sub:SetTextColor(0.9, 0.9, 0.9)
    tablePanel.pauseOverlay = pauseOverlay

    -- Re-stack the pause button ABOVE the pause overlay so it remains
    -- clickable while the game is paused. The button was created
    -- inside centerPad with default strata (MEDIUM); bumping it to
    -- FULLSCREEN_DIALOG puts it on top of the DIALOG overlay
    -- regardless of creation order. The peek button lives in the
    -- main frame (top-right corner) so it's unaffected by the
    -- centerPad overlay.
    pauseBtn:SetFrameStrata("FULLSCREEN_DIALOG")

    -- AKA toast: small short-lived banner anchored just ABOVE the
    -- centre pad's top edge, so it doesn't fight the trick cards for
    -- space. Hidden by default; renderAKABanner shows it for the
    -- lifetime of the trick (cleared in ApplyTrickEnd).
    local akaBanner = CreateFrame("Frame", nil, centerPad, "BackdropTemplate")
    -- Anchor inside centerPad's top edge instead of above it. The gap
    -- between the centerPad and the top seat-badge is only 10 px —
    -- a 26-px banner anchored to "BOTTOM, centerPad, TOP" pokes ~16
    -- px into the partner badge and covers their card-back fan.
    -- Sitting INSIDE the top of centerPad keeps the trick area clear
    -- below (centre cross is at +/-58 from centre, banner at top edge).
    akaBanner:SetSize(180, 22)
    akaBanner:SetPoint("TOP", centerPad, "TOP", 0, -4)
    setBackdrop(akaBanner, true,
        { 0.05, 0.10, 0.05, 0.90 }, COL.legalEdge, 8, "solid")
    -- Audit fix: bump frame-level above the centre-cross trick cards.
    -- AKA banner inside centerPad's top edge (y≈+89..+111 from centre)
    -- otherwise overlaps centerCards.top (90 tall at +58, top edge
    -- at +103) by ~14 px, partially obscuring the banner text right
    -- when the partner needs to read it.
    akaBanner:SetFrameLevel(centerPad:GetFrameLevel() + 50)
    akaBanner:Hide()
    -- v2.1.0 (audit v1.6.1 UX-31 LOW): fade-in/out animations for the
    -- AKA banner. Pre-fix the banner snapped on/off — abrupt visual
    -- pop/disappear on every state transition. SetAlpha + UIFrameFadeIn/
    -- FadeOut wrap the existing Show/Hide pattern; Show() is replaced
    -- with B.UI.FadeBanner(b, 0.25) and Hide() with B.UI.FadeBanner(b,
    -- 0.25, true). Same applied to overcallBanner / swaBanner below.
    akaBanner:SetAlpha(0)
    akaBanner.text = makeText(akaBanner, 13, "CENTER")
    akaBanner.text:SetPoint("CENTER", 0, 0)
    akaBanner.text:SetTextColor(0.40, 1.00, 0.55)
    -- v2.0.0 (audit v1.6.1 PJ-21 HIGH): tooltip explains the AKA cue.
    akaBanner:EnableMouse(true)
    setLobbyTooltip(akaBanner, "AKA — partner signal",
        "Caller holds the highest live card in this suit. Their "
        .. "partner shouldn't over-trump — let them win this suit. "
        .. "Saudi-only signal (eka); the only explicit partner-"
        .. "coordination call in Saudi Baloot.")
    tablePanel.akaBanner = akaBanner

    -- v0.7 Sun-overcall countdown banner. Visible during the 5-sec
    -- post-Hokm overcall window. Self-ticks at ~3 Hz to keep the
    -- countdown digit honest without depending on full U.Refresh.
    -- Hidden whenever S.s.phase ~= PHASE_OVERCALL.
    local overcallBanner = CreateFrame("Frame", nil, centerPad, "BackdropTemplate")
    overcallBanner:SetSize(280, 38)
    overcallBanner:SetPoint("TOP", centerPad, "TOP", 0, -8)
    setBackdrop(overcallBanner, true,
        { 0.06, 0.10, 0.14, 0.94 }, { 0.40, 0.78, 1.00, 1 }, 8, "solid")
    overcallBanner:SetFrameLevel(centerPad:GetFrameLevel() + 50)
    overcallBanner:Hide()
    overcallBanner.title = makeText(overcallBanner, 12, "CENTER")
    overcallBanner.title:SetPoint("TOP", 0, -3)
    overcallBanner.title:SetTextColor(0.55, 0.85, 1.00)
    overcallBanner.body = makeText(overcallBanner, 11, "CENTER")
    overcallBanner.body:SetPoint("TOP", overcallBanner.title, "BOTTOM", 0, -2)
    overcallBanner.body:SetTextColor(0.95, 0.95, 0.95)
    -- v2.0.0 (audit v1.6.1 PJ-23 HIGH): tooltip explains the overcall
    -- window so new players know what the 5-second countdown means.
    overcallBanner:EnableMouse(true)
    setLobbyTooltip(overcallBanner, "Sun-overcall window",
        "Saudi rule: 5 seconds after a Hokm bid, anyone may upgrade "
        .. "the contract to Sun (no-trump, ×2 multiplier). Bidder "
        .. "can self-upgrade; non-bidders can take it as their own "
        .. "Sun. wla (decline) is the safe default.")
    overcallBanner._tickAccum = 0
    overcallBanner._lastRemain = nil
    overcallBanner:SetScript("OnUpdate", function(self, elapsed)
        self._tickAccum = (self._tickAccum or 0) + (elapsed or 0)
        if self._tickAccum < 0.33 then return end
        self._tickAccum = 0
        if S.s.phase ~= K.PHASE_OVERCALL or not S.s.overcall then
            self:Hide(); self._lastRemain = nil; return
        end
        -- v0.9.0 L1 fix (audit AUDIT_REPORT_v0.7.1.md): freeze countdown
        -- under pause. Pre-v0.9.0 the OnUpdate kept ticking the digit
        -- and decrementing remain even while host had paused; the
        -- M1-fix re-arms the timer cleanly on resume but the visual
        -- countdown looked broken. Now: skip the body refresh under
        -- pause; banner stays visible with stale digits until resume.
        if S.s.paused then return end
        local windowSec = K.OVERCALL_TIMEOUT_SEC or 5
        local now = (GetTime and GetTime()) or 0
        local startedAt = S.s.overcall.startedAt or now
        local remain = math.max(0, math.ceil(windowSec - (now - startedAt)))
        self.title:SetText("Sun-overcall window")
        -- Count decisions for the body line.
        local decided, total = 0, 4
        if S.s.overcall.decisions then
            for s2 = 1, 4 do
                if S.s.overcall.decisions[s2] then decided = decided + 1 end
            end
        end
        self.body:SetText(("%ds left  ·  %d/%d decided"):format(
            remain, decided, total))
        if remain ~= self._lastRemain then
            self._lastRemain = remain
            -- Trigger a U.Refresh so action buttons re-render with
            -- the updated remain count in their labels.
            if U.Refresh then U.Refresh() end
        end
    end)
    tablePanel.overcallBanner = overcallBanner

    -- SWA pending preview banner. Visible during the 5-sec
    -- auto-approve window after a permission-required SWA call:
    -- shows the caller's name + remaining-card count + countdown,
    -- prompting the opponent team to inspect and decide whether to
    -- press the always-visible TAKWEESH button (illegal-play counter)
    -- or just let the timer auto-approve. Anchored below the AKA
    -- slot so both can coexist.
    --
    -- v0.5.4 player-feedback fix: previously the banner showed only
    -- the count ("N cards remaining"), so the player had to approve
    -- (or auto-approve) without seeing WHICH cards the caller was
    -- claiming. Especially opaque for bot-initiated SWA. Now: a
    -- card-face row is rendered inside the banner, decoded from
    -- req.encodedHand. Saudi convention is "show your hand on SWA"
    -- so opponents can verify the claim before accepting/Takweeshing.
    local SWA_CARD_W, SWA_CARD_H, SWA_CARD_GAP = 36, 52, 4
    local swaBanner = CreateFrame("Frame", nil, centerPad, "BackdropTemplate")
    swaBanner:SetSize(280, 100)  -- v0.5.4: was 38; +62 for card row
    -- v2.3.0 (audit v1.6.1 UX-23 MED): banner Y offset shifted from
    -- -32 to -68 so the card row at the bottom of the banner no
    -- longer overlaps the top trick-card slot at centerCards.top
    -- (+58 from centre, 90 tall → top edge at +103). Pre-fix the
    -- SWA card row at y≈-92 collided with the trick-card. Frame
    -- level (centerPad+50) keeps banner-on-top when overlap is
    -- unavoidable, but spatial separation is cleaner.
    swaBanner:SetPoint("TOP", centerPad, "TOP", 0, -68)
    setBackdrop(swaBanner, true,
        { 0.10, 0.07, 0.04, 0.94 }, { 1.0, 0.85, 0.30, 1 }, 8, "solid")
    swaBanner:SetFrameLevel(centerPad:GetFrameLevel() + 50)
    swaBanner:Hide()
    swaBanner.title = makeText(swaBanner, 12, "CENTER")
    swaBanner.title:SetPoint("TOP", 0, -3)
    swaBanner.title:SetTextColor(1.00, 0.85, 0.30)
    swaBanner.body = makeText(swaBanner, 11, "CENTER")
    swaBanner.body:SetPoint("TOP", swaBanner.title, "BOTTOM", 0, -2)
    swaBanner.body:SetTextColor(0.95, 0.95, 0.85)
    -- v2.0.0 (audit v1.6.1 PJ-24 HIGH): tooltip explains SWA mechanic.
    swaBanner:EnableMouse(true)
    setLobbyTooltip(swaBanner, "SWA — claim the rest",
        "Caller asserts they will win every remaining trick. With "
        .. "<=3 cards left it's auto-allowed; with 4+ cards opps "
        .. "must vote (Accept = let them claim, Deny = demand proof). "
        .. "If the claim fails, caller's team takes a ~30-pt penalty.")

    -- Card-face row (max 4 cards — SWA fires at <=4 remaining). Slots
    -- are pre-built once and shown/hidden + repositioned per refresh.
    swaBanner.cardSlots = {}
    for i = 1, 4 do
        local slot = makeCardFace(swaBanner, SWA_CARD_W, SWA_CARD_H)
        -- makeCardFace returns frame parented to swaBanner already;
        -- bump its frame-level above the banner's backdrop so the
        -- card art renders on top of the brown gradient.
        slot.frame:SetFrameLevel(swaBanner:GetFrameLevel() + 1)
        slot.frame:Hide()
        swaBanner.cardSlots[i] = slot
    end

    -- Re-anchor the visible slots, centered horizontally, anchored to
    -- the banner's bottom edge. Hides slots beyond `n`.
    swaBanner.layoutCards = function(self, n)
        n = math.max(0, math.min(n or 0, 4))
        local total = (n > 0)
            and (n * SWA_CARD_W + (n - 1) * SWA_CARD_GAP) or 0
        local startX = -(total / 2) + (SWA_CARD_W / 2)
        for i, slot in ipairs(self.cardSlots) do
            if i <= n then
                slot.frame:ClearAllPoints()
                slot.frame:SetPoint("BOTTOM", self, "BOTTOM",
                    startX + (i - 1) * (SWA_CARD_W + SWA_CARD_GAP), 6)
                slot.frame:Show()
            else
                slot.frame:Hide()
            end
        end
    end

    -- Decode req.encodedHand and populate the slots. Used by both
    -- self-tick OnUpdate and renderSWABanner (Refresh path).
    swaBanner.populateCards = function(self, encodedHand)
        local cards = (encodedHand and C.DecodeHand)
            and C.DecodeHand(encodedHand) or {}
        self:layoutCards(#cards)
        for i, slot in ipairs(self.cardSlots) do
            setCardSlot(slot, cards[i])
        end
    end

    -- Self-ticking countdown: while shown, OnUpdate refreshes ~3x/sec
    -- so the "auto-approve in N s" digit decrements smoothly without
    -- needing the rest of U.Refresh to fire.
    swaBanner._tickAccum = 0
    swaBanner._lastEnc   = nil
    swaBanner:SetScript("OnUpdate", function(self, elapsed)
        self._tickAccum = (self._tickAccum or 0) + (elapsed or 0)
        if self._tickAccum < 0.33 then return end
        self._tickAccum = 0
        -- v0.9.0 L1 fix: freeze SWA banner countdown under pause.
        -- Same rationale as the overcall banner above.
        if S.s.paused then return end
        local req = S.s.swaRequest
        if not req or not req.caller or S.s.phase ~= K.PHASE_PLAY then
            self:Hide(); self._lastEnc = nil; return
        end
        local windowSec = req.windowSec or K.SWA_TIMEOUT_SEC or 5
        local now = (GetTime and GetTime()) or 0
        local elapsed2 = (req.ts and now and (now - req.ts)) or 0
        local remain = math.max(0, math.ceil(windowSec - elapsed2))
        local sameTeam = S.s.localSeat
                     and R.TeamOf(S.s.localSeat) == R.TeamOf(req.caller)
        local handCount = req.handCount or 0
        local cardLine = ("%d card%s remaining"):format(
            handCount, handCount == 1 and "" or "s")
        -- v2.1.0 (audit v1.6.1 UX-33 MED): when countdown hits 0,
        -- show "approving…" instead of frozen "0s". The actual auto-
        -- approve happens host-side; this is the visual confirmation
        -- that the timer reached the gate. Pre-fix the banner just
        -- showed "0s" indefinitely while the host's resolution lag
        -- played out — looked frozen.
        if remain <= 0 then
            if sameTeam then
                self.body:SetText(("%s · |cffaaffaaapproving…|r"):format(cardLine))
            else
                self.body:SetText(("%s · |cffffaa55resolving…|r"):format(cardLine))
            end
        elseif sameTeam then
            self.body:SetText(("%s · auto-approve in %ds"):format(cardLine, remain))
        else
            self.body:SetText(("%s · %ds — Takweesh to counter"):format(cardLine, remain))
        end
        -- Repopulate cards only when the encoded hand changes (every
        -- request is a fresh encoded payload; no need to redecode 3x/s).
        if self._lastEnc ~= req.encodedHand then
            self._lastEnc = req.encodedHand
            self:populateCards(req.encodedHand)
        end
    end)
    tablePanel.swaBanner = swaBanner

    -- v3.0.8: Takweesh REVIEW banner. Per video #36 «throw cards
    -- face-up to reveal proof» — caller's hand displayed for 8s
    -- while host (in multi-human games) decides Approve/Reject;
    -- timeout defaults to auto-validate via rule-engine scan.
    -- Modeled after swaBanner but taller (8 cards possible vs SWA's 4)
    -- and with optional Approve/Reject button row.
    local takweeshBanner = CreateFrame("Frame", nil, centerPad, "BackdropTemplate")
    takweeshBanner:SetSize(380, 150)
    takweeshBanner:SetPoint("TOP", centerPad, "TOP", 0, -68)
    setBackdrop(takweeshBanner, true,
        { 0.16, 0.04, 0.04, 0.96 }, { 1.0, 0.40, 0.30, 1 }, 8, "solid")
    takweeshBanner:SetFrameLevel(centerPad:GetFrameLevel() + 60)
    takweeshBanner:Hide()
    takweeshBanner.title = makeText(takweeshBanner, 13, "CENTER")
    takweeshBanner.title:SetPoint("TOP", 0, -4)
    takweeshBanner.title:SetTextColor(1.00, 0.55, 0.40)
    takweeshBanner.body = makeText(takweeshBanner, 11, "CENTER")
    takweeshBanner.body:SetPoint("TOP", takweeshBanner.title, "BOTTOM", 0, -2)
    takweeshBanner.body:SetTextColor(0.95, 0.92, 0.85)
    takweeshBanner.subtext = makeText(takweeshBanner, 10, "CENTER")
    takweeshBanner.subtext:SetPoint("TOP", takweeshBanner.body, "BOTTOM", 0, -1)
    takweeshBanner.subtext:SetTextColor(0.85, 0.85, 0.70)

    -- Card-face row: caller may have up to 8 cards remaining; build 8 slots.
    takweeshBanner.cardSlots = {}
    for i = 1, 8 do
        local slot = makeCardFace(takweeshBanner, SWA_CARD_W, SWA_CARD_H)
        slot.frame:SetFrameLevel(takweeshBanner:GetFrameLevel() + 1)
        slot.frame:Hide()
        takweeshBanner.cardSlots[i] = slot
    end
    takweeshBanner.layoutCards = function(self, n)
        n = math.max(0, math.min(n or 0, 8))
        local total = (n > 0) and (n * SWA_CARD_W + (n - 1) * SWA_CARD_GAP) or 0
        local startX = -(total / 2) + (SWA_CARD_W / 2)
        for i, slot in ipairs(self.cardSlots) do
            if i <= n then
                slot.frame:ClearAllPoints()
                slot.frame:SetPoint("BOTTOM", self, "BOTTOM",
                    startX + (i - 1) * (SWA_CARD_W + SWA_CARD_GAP), 30)
                slot.frame:Show()
            else
                slot.frame:Hide()
            end
        end
    end
    takweeshBanner.populateCards = function(self, encodedHand)
        local cards = (encodedHand and C.DecodeHand)
            and C.DecodeHand(encodedHand) or {}
        self:layoutCards(#cards)
        for i, slot in ipairs(self.cardSlots) do
            setCardSlot(slot, cards[i])
        end
    end

    -- Approve / Reject buttons (host-only, multi-human gate).
    -- Anchored bottom-left and bottom-right of the banner.
    local function makeReviewBtn(parent, label, onClick)
        local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
        btn:SetSize(72, 22)
        setBackdrop(btn, true, { 0.10, 0.10, 0.10, 0.92 },
            COL.legalEdge or { 1, 1, 1, 1 }, 6, "solid")
        local txt = makeText(btn, 11, "CENTER")
        txt:SetPoint("CENTER", 0, 0)
        txt:SetText(label)
        btn.text = txt
        btn:SetScript("OnEnter", function(s)
            s:SetBackdropColor(0.18, 0.18, 0.18, 0.96)
        end)
        btn:SetScript("OnLeave", function(s)
            s:SetBackdropColor(0.10, 0.10, 0.10, 0.92)
        end)
        btn:SetScript("OnClick", onClick)
        return btn
    end
    takweeshBanner.approveBtn = makeReviewBtn(takweeshBanner, "|cff55ff55Approve|r",
        function()
            if B.Net and B.Net.HostApproveTakweesh then
                B.Net.HostApproveTakweesh()
            end
        end)
    takweeshBanner.approveBtn:SetPoint("BOTTOMLEFT", takweeshBanner, "BOTTOMLEFT", 8, 6)
    takweeshBanner.approveBtn:Hide()
    takweeshBanner.rejectBtn = makeReviewBtn(takweeshBanner, "|cffff5555Reject|r",
        function()
            if B.Net and B.Net.HostRejectTakweesh then
                B.Net.HostRejectTakweesh()
            end
        end)
    takweeshBanner.rejectBtn:SetPoint("BOTTOMRIGHT", takweeshBanner, "BOTTOMRIGHT", -8, 6)
    takweeshBanner.rejectBtn:Hide()

    -- Self-ticking countdown (parallel to swaBanner pattern).
    takweeshBanner._tickAccum = 0
    takweeshBanner._lastEnc   = nil
    takweeshBanner:SetScript("OnUpdate", function(self, elapsed)
        self._tickAccum = (self._tickAccum or 0) + (elapsed or 0)
        if self._tickAccum < 0.33 then return end
        self._tickAccum = 0
        if S.s.paused then return end
        local rv = S.s.takweeshReview
        if not rv or not rv.caller
           or S.s.phase ~= K.PHASE_TAKWEESH_REVIEW then
            self:Hide(); self._lastEnc = nil; return
        end
        local windowSec = rv.windowSec or K.TAKWEESH_REVIEW_SEC or 8
        local now = (GetTime and GetTime()) or 0
        local elapsed2 = (rv.ts and now and (now - rv.ts)) or 0
        local remain = math.max(0, math.ceil(windowSec - elapsed2))
        if remain <= 0 then
            self.subtext:SetText("|cffffaa55resolving…|r")
        else
            self.subtext:SetText(("|cffaaaaaa%ds remaining|r"):format(remain))
        end
    end)
    tablePanel.takweeshBanner = takweeshBanner

    -- BALOOT! / contract result banner with full breakdown (shown
    -- during PHASE_SCORE / PHASE_GAME_END). Title at top, then per-team
    -- breakdown lines, multiplier, Belote, and final delta.
    --
    -- Player-reported UI fix: prepend a large WIN / LOST headline
    -- above the title so the local player sees their own outcome at
    -- a glance regardless of the contract framing (made/failed/sweep
    -- all map to a clear win/lose for their team). The existing title
    -- (BALOOT / ALLY B3DO / AL-KABOOT) stays as the contextual
    -- detail line. Banner height bumped from 170 to 196 to fit.
    local banner = CreateFrame("Frame", nil, centerPad, "BackdropTemplate")
    banner:SetSize(270, 196)
    banner:SetPoint("CENTER", 0, 0)
    setBackdrop(banner, true, { 0.04, 0.04, 0.05, 0.96 }, COL.legalEdge, 12, "solid")
    banner:Hide()
    banner.outcome = makeText(banner, 22, "CENTER")
    banner.outcome:SetPoint("TOP", 0, -10)
    banner.title = makeText(banner, 14, "CENTER")
    banner.title:SetPoint("TOP", 0, -38)
    -- v1.3.3 (user-reported UI fix): pre-fix the title FontString
    -- had no width constraint, so long titles like "TAKWEESH! X
    -- called incorrectly — YA MRW7 TEAM ONE (X+Y)" overflowed the
    -- banner box on both sides. Now: cap the width so word-wrap
    -- engages cleanly inside the banner. Banner is 270 wide; 256
    -- leaves 7px padding each side. Subsequent text rows pushed
    -- down 16px so a 2-line title doesn't overlap the bidder line.
    banner.title:SetWidth(256)
    banner.title:SetWordWrap(true)
    banner.bidder = makeText(banner, 11, "CENTER")
    banner.bidder:SetPoint("TOP", 0, -78)
    banner.defender = makeText(banner, 11, "CENTER")
    banner.defender:SetPoint("TOP", 0, -96)
    banner.modifiers = makeText(banner, 11, "CENTER")
    banner.modifiers:SetPoint("TOP", 0, -118)
    banner.belote = makeText(banner, 11, "CENTER")
    banner.belote:SetPoint("TOP", 0, -136)
    banner.belote:SetTextColor(1, 0.84, 0.30)
    banner.final = makeText(banner, 14, "CENTER")
    banner.final:SetPoint("BOTTOM", 0, 14)
    tablePanel.banner = banner

    -- Left and right opponents
    seatBadges.left = buildSeatBadge(tablePanel, function(b)
        b:SetPoint("RIGHT", centerPad, "LEFT", -12, 0)
    end)
    seatBadges.right = buildSeatBadge(tablePanel, function(b)
        b:SetPoint("LEFT", centerPad, "RIGHT", 12, 0)
    end)

    -- Bottom-half elements anchor UP from the hand row so the gaps
    -- adjust automatically when card sizes change.

    -- Hand row at very bottom (cards are 92 tall — leave a few px margin)
    local handRow = CreateFrame("Frame", nil, tablePanel)
    handRow:SetSize(680, 100)
    handRow:SetPoint("BOTTOM", 0, 10)
    tablePanel.handRow = handRow

    -- Spectator info line: occupies the handRow space when localSeat
    -- is nil. Shows the bottom-anchor seat (seat 1) name + card count
    -- and a small "Spectating" tag. Hidden for seated players —
    -- handRow renders cards there. Adds NO action paths; spectators
    -- remain pure observers.
    local specInfo = CreateFrame("Frame", nil, tablePanel)
    specInfo:SetAllPoints(handRow)
    specInfo:Hide()
    specInfo.tag = makeText(specInfo, 11, "CENTER")
    specInfo.tag:SetPoint("TOP", 0, -8)
    specInfo.tag:SetTextColor(0.85, 0.85, 0.55)
    specInfo.tag:SetText("|cffe0d588Spectating|r")
    specInfo.bottomSeat = makeText(specInfo, 13, "CENTER")
    specInfo.bottomSeat:SetPoint("TOP", 0, -28)
    tablePanel.specInfo = specInfo

    -- Action panel sits just above the hand row
    actionPanel = CreateFrame("Frame", nil, tablePanel)
    actionPanel:SetSize(680, 28)
    actionPanel:SetPoint("BOTTOM", handRow, "TOP", 0, 6)

    -- Local player bar: name + meld text. Above the action panel.
    -- Sized to match the side seat-badges (~280 wide, centered) so the
    -- four players read as a balanced cross around the felt rather
    -- than a long banner across the bottom.
    local localBar = CreateFrame("Frame", nil, tablePanel, "BackdropTemplate")
    localBar:SetSize(280, 26)
    localBar:SetPoint("BOTTOM", actionPanel, "TOP", 0, 6)
    setBackdrop(localBar, true, COL.feltLight, COL.woodEdge, 8)
    localBar.nameText = makeText(localBar, 12, "LEFT")
    localBar.nameText:SetPoint("LEFT", 10, 0)
    localBar.nameText:SetTextColor(1, 0.84, 0.30)
    localBar.meldText = makeText(localBar, 11, "RIGHT")
    localBar.meldText:SetPoint("RIGHT", -10, 0)
    localBar.meldText:SetTextColor(1, 0.84, 0.30)
    -- Local meld strip sits ABOVE the local bar so it doesn't fight
    -- the name label for horizontal space. Same 5-card layout as the
    -- seat badges, hidden until melds are declared.
    localBar.meldStrip = buildMeldStrip(localBar)
    -- Audit fix: anchor INSIDE localBar so the strip doesn't extend
    -- 36 px into the centerPad/trick area when shown during the
    -- trick-1 meld-declaration window. The strip overlays the
    -- localBar's name/score text — acceptable since melds and
    -- per-seat score never need to be read together.
    localBar.meldStrip:SetPoint("BOTTOM", localBar, "BOTTOM", 0, 0)
    -- Turn glow overlay matching the other seat badges. Shown only
    -- when it's our turn so the highlight reads as strongly as the
    -- other three seats' glow when they're up.
    localBar.turnGlow = localBar:CreateTexture(nil, "OVERLAY")
    localBar.turnGlow:SetAllPoints()
    localBar.turnGlow:SetColorTexture(unpack(COL.activeGlow))
    localBar.turnGlow:Hide()
    tablePanel.localBar = localBar

    -- Center trick: 4 card faces in a cross inside centerPad
    centerCards.bottom = buildCenterSlot(centerPad, function(cs) cs:SetPoint("CENTER", 0, -58) end)
    centerCards.top    = buildCenterSlot(centerPad, function(cs) cs:SetPoint("CENTER", 0, 58)  end)
    centerCards.left   = buildCenterSlot(centerPad, function(cs) cs:SetPoint("CENTER", -78, 0) end)
    centerCards.right  = buildCenterSlot(centerPad, function(cs) cs:SetPoint("CENTER", 78, 0)  end)
    -- Dedicated bid-card slot, shown only during bidding phases
    centerCards.bid    = buildCenterSlot(centerPad, function(cs) cs:SetPoint("CENTER", 0, 0)   end)
end

-- ----------------------------------------------------------------------
-- Render: action panel (bidding / double / meld declaration)
-- ----------------------------------------------------------------------

-- Pooled action buttons. Refresh hides unused ones and re-binds the
-- active ones — no CreateFrame churn per state change.
local actionPool = {}
local actionUsed = 0

-- Double-click-to-confirm wrapper for high-stakes actions. The first
-- click flips the button label to a red "ARE YOU SURE?" prompt and arms
-- a 2-second window; a second click within that window fires the real
-- action, anything else cancels. Cheaper than a modal and harder to
-- mis-fire than a single-click button.
local CONFIRM_WINDOW_SEC = 2.0
local function bindConfirm(btn, normalLabel, armedLabel, fire)
    btn.armed   = false
    btn.armedTk = nil
    local function disarm()
        btn.armed = false
        if btn.armedTk then btn.armedTk:Cancel(); btn.armedTk = nil end
        btn:SetText(normalLabel)
        -- v3.0.1 (audit v3.0.0 REG-02): restore default 90px width on
        -- disarm. Pre-fix only the AUTO-disarm path (timer fire)
        -- restored width; the CLICK-confirm path called disarm() then
        -- fire() but never restored width — pooled buttons stayed at
        -- 220px after a confirm-fire, leaking into the next phase's
        -- action panel layout.
        btn:SetWidth(90)
    end
    btn:SetScript("OnClick", function()
        if btn.armed then
            disarm()
            fire()
        else
            btn.armed = true
            btn:SetText(armedLabel)
            -- v2.0.0 (audit v1.6.1 UX-04 HIGH): auto-resize on arm.
            -- Pre-fix the 90px fixed-width button truncated long
            -- armed-confirm labels (e.g. "Confirm Bel x3 (closed)?",
            -- "Confirm Deny — caller's invalid claim costs them
            -- ~30 pts; if Deny is wrong..."). Now measures the FontString
            -- and grows the button to fit (capped at 220 to avoid
            -- overflowing the action panel). Resets on disarm.
            local fs = btn.GetFontString and btn:GetFontString()
            if fs and fs.GetStringWidth then
                local w = fs:GetStringWidth() + 20
                if w > 90 and w < 220 then btn:SetWidth(w) end
            end
            if btn.armedTk then btn.armedTk:Cancel() end
            btn.armedTk = C_Timer.NewTimer(CONFIRM_WINDOW_SEC, function()
                disarm()
                btn:SetWidth(90)  -- restore default on auto-disarm
            end)
        end
    end)
end

local function clearActions()
    for i = 1, actionUsed do
        local b = actionPool[i]
        if b then
            b:Hide()
            b:SetScript("OnClick", nil)
            -- v1.7.0 (audit v1.6.1 PJ + UX): clear tooltip handlers
            -- on pool reuse so a stale tooltip from a previous phase
            -- doesn't show on a button repurposed for a new action.
            b:SetScript("OnEnter", nil)
            b:SetScript("OnLeave", nil)
            -- v1.8.1 (audit v1.6.1 UX-13 CRITICAL): clear OnUpdate too.
            -- The BALOOT! pulse OnUpdate (UI.lua:~2230) was set on a
            -- pooled button but never cleared on pool reuse — a button
            -- repurposed for a different action in a later phase kept
            -- pulsing its label color forever, fighting whatever the
            -- new phase wanted to display. Clearing OnUpdate + resetting
            -- alpha/text-color closes the leak.
            b:SetScript("OnUpdate", nil)
            b:SetAlpha(1.0)
            -- v3.0.2 (user-reported: "Pass grayed out sometimes when
            -- all 4 are humans, regardless of seat position"). Root
            -- cause: v2.2.0 MP-62's "(host advances)" disabled-label
            -- affordance for non-host PHASE_SCORE called btn:Disable()
            -- on a pooled button — but clearActions() only unset
            -- scripts and alpha. The :Disable() state stayed sticky.
            -- Next render reused the same pool slot for Pass / Hokm /
            -- whatever — still disabled. Player saw greyed Pass with
            -- no idea why. Fix: re-Enable on pool reuse.
            if b.Enable then b:Enable() end
            local fs = b.GetFontString and b:GetFontString()
            if fs and fs.SetTextColor then
                fs:SetTextColor(1, 1, 1)
            end
        end
    end
    actionUsed = 0
end

-- v1.7.0 (audit v1.6.1 PJ-CRITICAL + UX-many): addAction now accepts
-- an optional tooltip parameter. Pre-fix the action panel's buttons
-- (Hokm/Sun/Pass/Ashkal/Bel*/Triple*/Four*/Gahwa/AKA/SWA/BALOOT/Take
-- as Sun/wla/Skip/Confirm-prompt) had ZERO tooltip layer. New players
-- pressing "Ashkal" or "BALOOT!" with no in-game explanation had to
-- read the source code. Tooltip mirrors the existing checkbox tooltip
-- pattern at UI.lua:849-856. Tooltip is OPTIONAL — call sites that
-- pass nil keep the pre-v1.7.0 behavior (no tooltip shown).
local function addAction(label, onclick, tooltip)
    actionUsed = actionUsed + 1
    local b = actionPool[actionUsed]
    if not b then
        b = makeButton(actionPanel, label, 90, 24)
        actionPool[actionUsed] = b
    end
    b:SetText(label)
    b:ClearAllPoints()
    if actionUsed == 1 then
        b:SetPoint("LEFT", actionPanel, "LEFT", 4, 0)
    else
        b:SetPoint("LEFT", actionPool[actionUsed - 1], "RIGHT", 4, 0)
    end
    -- Reset any leftover confirm-arm state from a previous render so a
    -- pooled button doesn't carry "armed" state into a new phase.
    if b.armedTk then b.armedTk:Cancel(); b.armedTk = nil end
    b.armed = false
    b:SetScript("OnClick", onclick)
    -- Tooltip wiring. Strips |cAARRGGBB...|r color codes from `label`
    -- for the tooltip header so colored UI labels render plain in the
    -- tooltip box.
    if tooltip and tooltip ~= "" then
        local plainLabel = label:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
        b:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine(plainLabel, 1, 1, 1)
            GameTooltip:AddLine(tooltip, 0.85, 0.85, 0.85, true)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    else
        b:SetScript("OnEnter", nil)
        b:SetScript("OnLeave", nil)
    end
    b:Show()
    return b
end

local function addConfirmAction(label, armedLabel, fire, tooltip)
    local b = addAction(label, nil, tooltip)
    bindConfirm(b, label, armedLabel, fire)
    return b
end

local function renderActions()
    clearActions()
    -- 50-agent codebase audit fix (M-4): top-level localSeat guard.
    -- A spectator (joined party but no seat) had no guard at this
    -- entry — most action branches gate on localSeat comparisons
    -- internally, but PHASE_SCORE/GAME_END only check isHost. A
    -- spectator who is also the host (rare but possible) saw
    -- "Next Round" / "New Game" buttons. Adding a single explicit
    -- guard makes the intent uniform and protects future phase
    -- branches from accidental spectator exposure. Host-only phase
    -- buttons remain reachable because the host always has a seat.
    if not S.s.localSeat then return end
    if S.s.phase == K.PHASE_DEAL1 or S.s.phase == K.PHASE_DEAL2BID then
        -- v3.2.14 F1: once this seat has bid, suppress the bid action
        -- buttons even while S.IsMyTurn() is still true. Non-host
        -- LocalBid does not advance S.s.turn locally, so during the
        -- echo gap before the host's MSG_TURN the optimistic refresh
        -- would otherwise still present a (duplicate-inviting) bid.
        if S.IsMyTurn() and S.s.turnKind == "bid"
           and S.s.bids[S.s.localSeat] == nil then
            -- Pass label: "Pass" in round 1, "wla" (ولا) in round 2 to
            -- match the Saudi-table verbal convention. The round-2
            -- pass is essentially "I have no preference / confirm
            -- the existing bid".
            local passLabel = (S.s.phase == K.PHASE_DEAL2BID) and "wla" or "Pass"
            local passTip = (S.s.phase == K.PHASE_DEAL2BID)
                and "Decline to bid (round 2). Saudi: 'wla' — no preference."
                or "Decline to bid (round 1). Saudi: 'bas' — pass."
            addAction(passLabel, function() net().LocalBid(K.BID_PASS) end, passTip)
            local flippedSuit = S.s.bidCard and C.Suit(S.s.bidCard) or nil
            if S.s.phase == K.PHASE_DEAL1 then
                -- Round 1: scan prior bids to know which buttons apply.
                local anyHokm, anySun, anyAshkal = false, false, false
                for seat = 1, 4 do
                    local b = S.s.bids[seat]
                    if b == K.BID_SUN then anySun = true
                    elseif b == K.BID_ASHKAL then anyAshkal = true
                    elseif b and b:sub(1, 4) == K.BID_HOKM then anyHokm = true end
                end
                local anyBidYet = anyHokm or anySun or anyAshkal

                -- Hokm-on-flipped: available only if no prior bid.
                if flippedSuit and not anyBidYet then
                    -- v2.0.0 (audit v1.6.1 SA-21): SaudiName resolves
                    -- to "حكم Hokm" with Arabic font present, "Hokm"
                    -- otherwise. Same for Sun below. Suit glyph stays
                    -- universal cards.
                    -- v2.3.0 (audit v1.6.1 PJ-25 MED): tooltip now
                    -- mentions the trump rank-order quirk so new
                    -- players don't misplay J-of-trump (highest!) or
                    -- 9-of-trump (second-highest, NOT a Carre).
                    addAction(SaudiName("HOKM").." "..K.SUIT_GLYPH[flippedSuit], function()
                        net().LocalBid(K.BID_HOKM..":"..flippedSuit)
                    end, "Take the contract with this suit as Hokm (trump). "
                        .. "Round-1 Hokm is locked to the up-card suit.\n\n"
                        .. "|cffaaaaaaSaudi quirk: in trump suit only, "
                        .. "rank order is J > 9 > A > T > K > Q > 8 > 7. "
                        .. "Four 9s do NOT form a Carre.|r")
                end

                -- Ashkal (Saudi rule): converts the contract to Sun
                -- with the caller's PARTNER as declarer. RESTRICTED
                -- to the 3rd and 4th bidders in turn order — 1st
                -- and 2nd seats can't call it (per "نظام لعبة البلوت
                -- الأساسي" rule 3). Also blocked once a direct Sun
                -- has been bid.
                local bidPos = 0
                if S.s.dealer and S.s.localSeat then
                    -- Bid order: dealer's left first, dealer last.
                    --   pos 1 = (dealer % 4) + 1
                    --   pos 2 = ((dealer + 1) % 4) + 1
                    --   pos 3 = ((dealer + 2) % 4) + 1
                    --   pos 4 = dealer
                    local d = S.s.dealer
                    local order = {
                        (d % 4) + 1, ((d + 1) % 4) + 1,
                        ((d + 2) % 4) + 1, d,
                    }
                    for i, st in ipairs(order) do
                        if st == S.s.localSeat then bidPos = i; break end
                    end
                end
                if not anySun and bidPos >= 3 then
                    addAction("Ashkal", function() net().LocalBid(K.BID_ASHKAL) end,
                        "Saudi rule (Ashkal): convert the contract to Sun, "
                        .. "with your PARTNER as declarer. Available only "
                        .. "to bidders 3 and 4. Used to swing partner's Hokm "
                        .. "into a stronger Sun when you hold the goods.")
                end

                -- v0.11.20 user-reported UI bug: Sun button was shown
                -- unconditionally in R1, but per State.lua:2046 the
                -- FIRST direct Sun locks the contract — subsequent
                -- Sun bids are no-ops. Showing the button after `anySun`
                -- was misleading. Saudi rule: once Sun is bid, remaining
                -- seats can only PASS (the bid round still completes
                -- formally for record-keeping; per host wait-for-all-4
                -- design at HostAdvanceBidding line 2023). Now hidden
                -- when anySun=true.
                if not anySun then
                    addAction(SaudiName("SUN"), function() net().LocalBid(K.BID_SUN) end,
                        "Take the contract as Sun (no-trump). Saudi rule: "
                        .. "Sun overcalls Hokm, hand total is 130 with a "
                        .. "×2 multiplier baked in (260 effective).")
                end

                -- Kawesh: 5-card hand of only 7/8/9 → annul & redeal.
                -- Available throughout round 1 to the qualifying player.
                if C.IsKaweshHand(S.s.hand) then
                    -- v2.3.0 (audit v1.6.1 PJ-13 MED): expanded tooltip
                    -- with the Saudi rule context. "Annul and redeal"
                    -- alone didn't explain WHY it's allowed; new
                    -- players might think it's a cheat / cheap escape
                    -- rather than a canonical rule.
                    addAction("|cffff8800Kawesh|r", function() net().LocalKawesh() end,
                        "Saudi rule: annul this deal and redeal from a "
                        .. "fresh shuffle. Available ONLY when your initial "
                        .. "5-card hand contains exclusively 7s, 8s, and "
                        .. "9s (no J/9-of-trump value, no Aces, no Tens) — "
                        .. "structurally unwinnable. The button only "
                        .. "shows when you're eligible. Saudi name: "
                        .. "Kawesh / Saneen.")
                end
            else
                -- Round 2: 3 Hokm buttons (excluding the flipped suit) + Sun
                -- v2.0.0 SA-21: "H ♠" stays compact even with SaudiName
                -- because "حكم ♠" is too wide for round-2's 3 buttons +
                -- Sun on one row. Use the Latin-only short form here.
                for _, suit in ipairs(K.SUITS) do
                    if suit ~= flippedSuit then
                        local s2 = suit
                        addAction("H "..K.SUIT_GLYPH[suit], function()
                            net().LocalBid(K.BID_HOKM..":"..s2)
                        end, "Take the contract with this suit as Hokm. "
                            .. "Round-2 Hokm can be any non-up-card suit.")
                    end
                end
                addAction(SaudiName("SUN"), function() net().LocalBid(K.BID_SUN) end,
                    "Take the contract as Sun (no-trump, ×2 multiplier).")
            end
        end
    elseif S.s.phase == K.PHASE_DOUBLE then
        local b = S.s.contract and S.s.contract.bidder
        -- v1.0.11 (D MED M1 either-defender Bel): show Bel buttons to
        -- either defender on the bidder's opposite team. S.s.belPending
        -- is the source-of-truth list (set by S.ApplyContract; mutated
        -- by skip/timeout to track who hasn't yet decided).
        local nextSeat = b and ((b % 4) + 1) or nil
        local function inPending(seat)
            if not S.s.belPending then return false end
            for _, v in ipairs(S.s.belPending) do
                if v == seat then return true end
            end
            return false
        end
        if inPending(S.s.localSeat) then
            -- Bel (×2). Open/Closed (التربيع) choice: open lets the
            -- bidder counter with Triple; closed stops the chain.
            -- Sun has no Triple rung, so only the Bel button shows.
            --
            -- v0.5.15: gate the Bel buttons on R.CanBel. Saudi rule
            -- (E-1, v0.5.9): in Sun, only the team at <100 cumulative
            -- may Bel. Without this UI gate, the local player would
            -- see clickable Bel buttons that fail silently via
            -- Net.LocalDouble's R.CanBel guard — confusing UX.
            -- When the gate forbids, surface a "Bel forbidden" tip
            -- in place of the actionable buttons.
            local canBel = (R and R.CanBel) and
                R.CanBel(R.TeamOf(S.s.localSeat),
                         S.s.contract, S.s.cumulative)
            if canBel == false then
                addAction("Skip", function() net().LocalSkipDouble() end)
                addAction("|cff999999Bel forbidden (Sun >=100)|r",
                          function() end)
            else
                -- v1.0.1 user-reported (Comment 3): Skip leftmost so a
                -- click-momentum misfire from the just-finished overcall
                -- phase (slot 1 = "Take as Sun") lands on Skip — the
                -- safe-default outcome — rather than arming Bel. Bel
                -- buttons ALREADY use addConfirmAction (two-click arm/
                -- fire) for an additional safety layer; Skip-leftmost
                -- closes the residual fast-double-click hole.
                --
                -- v1.7.0 (audit v1.6.1 SA-20): re-Saudi-fied escalation
                -- labels. v1.0.2's rename to "Double x2" violated
                -- CLAUDE.md's "Saudi names in player-visible text"
                -- mandate. Restored to romanized Saudi (Bel x2 — NOT
                -- Arabic glyphs since WoW's bundled fonts don't
                -- render Arabic). Internal names (PHASE_DOUBLE,
                -- LocalDouble, MSG_DOUBLE) unchanged.
                addAction("Skip", function() net().LocalSkipDouble() end,
                    "Decline to call Bel and let the contract play at base value.")
                local isSun = S.s.contract and S.s.contract.type == K.BID_SUN
                if isSun then
                    addConfirmAction("Bel x2", "|cffff7755Confirm Bel x2?|r",
                        function() net().LocalDouble(false) end,
                        "Bel a Sun contract — doubles the round score (×2). "
                        .. "Sun has no Bel x3 / Four / Gahwa rungs, so this "
                        .. "is the terminal escalation.")
                else
                    addConfirmAction("Bel & open", "|cffff7755Confirm Bel & open?|r",
                        function() net().LocalDouble(true) end,
                        "Bel & open — doubles the round (×2) AND lets the bidder "
                        .. "counter with Bel x3 (×3). Higher upside, higher risk.")
                    addConfirmAction("Bel & closed", "|cffff7755Confirm Bel & close?|r",
                        function() net().LocalDouble(false) end,
                        "Bel & closed — doubles the round (×2) and STOPS the "
                        .. "escalation chain. Bidder cannot counter.")
                end
            end
        end
    elseif S.s.phase == K.PHASE_TRIPLE then
        -- v0.2.0: the bidder's response to Bel. Saudi calls this "Bel x3"
        -- (or "Theri" / ثري in some regional usage); the addon uses
        -- "Bel x3" to match the "Bel x2" sibling at PHASE_DOUBLE.
        -- v1.7.0 (audit v1.6.1 SA-20): restored Saudi label. Internal
        -- name PHASE_TRIPLE / LocalTriple unchanged.
        local b = S.s.contract and S.s.contract.bidder
        if b == S.s.localSeat then
            addAction("Skip", function() net().LocalSkipDouble() end,
                "Decline to counter. Round plays at the defenders' Bel x2 (×2).")
            addConfirmAction("Bel x3 (open)",
                "|cffff5555Confirm Bel x3 (open)?|r",
                function() net().LocalTriple(true) end,
                "Bel x3 & open — counter the defenders' Bel x2, raising to ×3 "
                .. "AND letting them counter with Four (×4). Confidence play.")
            addConfirmAction("Bel x3 (closed)",
                "|cffff5555Confirm Bel x3 (closed)?|r",
                function() net().LocalTriple(false) end,
                "Bel x3 & closed — raises to ×3 and STOPS the chain. Defenders "
                .. "cannot counter Four. Locks in the ×3 multiplier.")
        end
    elseif S.s.phase == K.PHASE_FOUR then
        -- v0.2.0: Four is the DEFENDER's response to Triple.
        -- v1.0.11 (D MED M1): use the SPECIFIC doubler seat
        -- (S.s.contract.doublerSeat) — pre-v1.0.11 hardcoded
        -- NextSeat(bidder); back-compat fallback for stale state.
        local b = S.s.contract and S.s.contract.bidder
        local def = (S.s.contract and S.s.contract.doublerSeat)
                     or (b and ((b % 4) + 1)) or nil
        if def == S.s.localSeat then
            addConfirmAction("Four & open (x4)",
                "|cffff3333Confirm Four & open?|r",
                function() net().LocalFour(true) end,
                "Four & open — counter the bidder's Bel x3, raising to ×4 AND "
                .. "letting them counter with Gahwa (match-win). High-stakes.")
            addConfirmAction("Four & closed (x4)",
                "|cffff3333Confirm Four & close?|r",
                function() net().LocalFour(false) end,
                "Four & closed — raises to ×4 and STOPS the chain. Bidder "
                .. "cannot counter Gahwa. Locks the ×4 multiplier.")
            addAction("Skip", function() net().LocalSkipDouble() end,
                "Decline to counter. Round plays at the bidder's Bel x3 (×3).")
        end
    elseif S.s.phase == K.PHASE_GAHWA then
        -- v0.2.0: Gahwa is the BIDDER's terminal — caller's team WINS
        -- the entire match outright if the contract makes; loses if
        -- it fails. No open/closed (terminal).
        local b = S.s.contract and S.s.contract.bidder
        if b == S.s.localSeat then
            addConfirmAction("|cffffd055Gahwa (match-win)|r",
                "|cffff0000Confirm Gahwa? (match-win or match-loss)|r",
                function() net().LocalGahwa() end,
                "Gahwa — terminal escalation. If your contract makes, "
                .. "your team WINS the entire match outright, regardless of "
                .. "score. If it fails, your team LOSES the match outright. "
                .. "All-or-nothing.")
            addAction("Skip", function() net().LocalSkipDouble() end,
                "Decline Gahwa. Round plays at the defenders' Four (×4).")
        end
    elseif S.s.phase == K.PHASE_OVERCALL then
        -- v0.7 Sun-overcall window: 5s post-Hokm chance for the bidder
        -- to upgrade Hokm→Sun (non-Ace bid card only) or for any
        -- non-bidder seat to take the contract as their own Sun.
        --
        -- After our local seat has decided, the buttons disappear
        -- (lock-out per Q3=A in the design discussion). If the contract
        -- makes us ineligible (R.CanOvercall returns false — only
        -- happens for forced/Sun contracts which shouldn't have opened
        -- the window in the first place), no buttons.
        local oc = S.s.overcall
        if oc and S.s.localSeat and S.s.contract then
            local alreadyDecided = oc.decisions
                                   and oc.decisions[S.s.localSeat]
            local canAct = R and R.CanOvercall and S.s.localSeat ~= nil
                           and R.CanOvercall(S.s.localSeat, S.s.contract,
                                              oc.bidCard)
            -- Compute remaining seconds for the button-label hint.
            local windowSec = K.OVERCALL_TIMEOUT_SEC or 5
            local now = (GetTime and GetTime()) or 0
            local elapsed = (oc.startedAt and now)
                            and (now - oc.startedAt) or 0
            local remain = math.max(0, math.ceil(windowSec - elapsed))
            local rTag = (" (%ds)"):format(remain)
            if not alreadyDecided then
                local isBidder = (S.s.localSeat == S.s.contract.bidder)
                if isBidder then
                    -- Bidder: UPGRADE + WAIVE. UPGRADE is filtered out
                    -- by R.CanOvercall when the bid card is an Ace,
                    -- in which case only the WAIVE button shows. The
                    -- net effect: bidder with Ace bid only sees WAIVE.
                    if canAct then
                        addAction("|cff66ff88Upgrade to Sun|r" .. rTag,
                            function() net().LocalOvercall("UPGRADE") end,
                            "Upgrade your Hokm bid to Sun (×2 multiplier). "
                            .. "Saudi-rule overcall window — 5 seconds. "
                            .. "Use when the bid card revealed makes Sun "
                            .. "stronger than Hokm.")
                    end
                    -- v2.3.0 (audit v1.6.1 SA-23 LOW): normalized
                    -- to lowercase "wla" for consistency with the
                    -- bidding-phase button + how Saudi players type
                    -- in chat. Pre-fix mixed "WLA (waive)" in overcall
                    -- vs "wla" in bidding. Tooltip carries the gloss.
                    addAction("|cff999999wla|r" .. rTag,
                        function() net().LocalOvercall("WAIVE") end,
                        "Decline. Saudi 'wla' — keep your current Hokm.")
                else
                    if canAct then
                        addAction("|cff66ddffTake as Sun|r" .. rTag,
                            function() net().LocalOvercall("TAKE") end,
                            "Take the contract for yourself, as Sun (no-trump, "
                            .. "×2). 5-second Saudi overcall window. Use when "
                            .. "your hand is stronger as Sun than the bidder's "
                            .. "declared Hokm.")
                    end
                    -- v2.3.0 (audit v1.6.1 SA-23 LOW): normalized
                    -- to lowercase "wla" for consistency with the
                    -- bidding-phase button + how Saudi players type
                    -- in chat. Pre-fix mixed "WLA (waive)" in overcall
                    -- vs "wla" in bidding. Tooltip carries the gloss.
                    addAction("|cff999999wla|r" .. rTag,
                        function() net().LocalOvercall("WAIVE") end,
                        "Decline. Saudi 'wla' — let the Hokm contract stand.")
                end
            else
                -- Decided already — show what we picked, no clickable.
                local label
                if alreadyDecided == "UPGRADE" then
                    label = "|cff66ff88Upgraded to Sun|r — waiting for others"
                elseif alreadyDecided == "TAKE" then
                    label = "|cff66ddffTook as Sun|r — waiting for others"
                elseif alreadyDecided == "WAIVE" then
                    label = "|cff999999Waived (wla)|r — waiting for others"
                else
                    -- v1.5.3: TAKE_HOKM_* labels removed (cross-trump
                    -- take is no longer accepted upstream). Any stale
                    -- value falls through to "Decided".
                    label = "Decided"
                end
                addAction(label .. rTag, function() end)
            end
        end
    elseif S.s.phase == K.PHASE_PREEMPT then
        -- Triple-on-Ace pre-emption (الثالث): earlier seats may claim
        -- the Sun bid for themselves. Saudi name "قبلك" ("before you" /
        -- "I'll take it") rendered as Latin "Qablak" because WoW's
        -- bundled fonts (Arial Narrow / Frizz / Skurri) don't include
        -- Arabic glyphs — Arabic chars in a button label render as
        -- empty boxes. Same pattern as the AKA button at line 2046.
        -- v0.10.3 UI fix (review_v0.10.2 E-UI-01-2): pre-v0.10.3 used
        -- raw Arabic glyph here, the only remaining hardcoded glyph
        -- in v0.10.2's UI label set.
        if S.s.preemptEligible and S.s.localSeat then
            local eligible = false
            for _, s2 in ipairs(S.s.preemptEligible) do
                if s2 == S.s.localSeat then eligible = true; break end
            end
            if eligible then
                addConfirmAction("|cff66ddffQablak|r",
                    "|cffff7755Take this Sun for yourself?|r",
                    function() net().LocalPreempt() end)
                addAction("Pass",
                    function() net().LocalPreemptPass() end)
            end
        end
    elseif S.s.phase == K.PHASE_DEAL3 or S.s.phase == K.PHASE_PLAY then
        -- Meld declaration window — Pagat allows multiple melds per
        -- player. Each "Declare" click sends a single meld; once all
        -- detected melds are declared (filtered list empties), the
        -- buttons disappear naturally. "Done" finalizes early.
        if S.s.localSeat and not S.s.meldsDeclared[S.s.localSeat] then
            local available = S.GetMeldsForLocal()
            if #available > 0 then
                for _, m in ipairs(available) do
                    local m2 = m
                    local label
                    if m.kind == "carre" then
                        label = ("Carré %s (%d)"):format(C.RankGlyph(m.top), m.value)
                    else
                        label = ("Seq%d %s%s (%d)"):format(m.len or 3,
                            C.RankGlyph(m.top), K.SUIT_GLYPH[m.suit] or "?", m.value)
                    end
                    addAction(label, function() net().LocalDeclareMeld(m2) end)
                end
                addAction("Done", function()
                    -- "Done" hides the per-meld buttons for the local
                    -- player. It's a UX-only flag — the authoritative
                    -- meld lock is the trick-1 gate (#s.tricks >= 1)
                    -- enforced in S.ApplyMeld, S.GetMeldsForLocal, and
                    -- Bot.PickMelds. So no network round-trip needed
                    -- here: any actual declaration already broadcasted
                    -- via LocalDeclareMeld; "Done" just dismisses the
                    -- buttons on the local screen.
                    S.s.meldsDeclared[S.s.localSeat] = true
                    U.Refresh()
                end)
            end
        end
        -- Takweesh button is always available during PLAY. Any player
        -- can press to call out an illegal play by the opposing team.
        -- Confirmation required: a false call ends the round with the
        -- full handTotal × mult going to the OTHER team — easy to fire
        -- by mistake from the always-visible action bar otherwise.
        if S.s.phase == K.PHASE_PLAY and S.s.localSeat then
            -- v3.0.1 (audit v3.0.0 PM-01/02 HIGH): TAKWEESH tooltip
            -- added. Pre-fix the button was prominently visible
            -- with no explanation — sibling SWA at line ~2487 had
            -- full prose tooltip but TAKWEESH (the most consequential
            -- accusation in Saudi Baloot) had nothing. Critical
            -- asymmetry on a paired-button row.
            -- v3.2.7 (post-v3.2.6 UX follow-up,
            -- .swarm_findings/v3_2_7_takweesh_tooltip_design.md):
            -- expand wording to (a) reflect both qualifying
            -- patterns (false-AKA marker, later same-suit reveal
            -- after off-suit) per the v3.2.6 Bot.PickTakweesh
            -- carve-out + the original v1.5.1 realism gate; and
            -- (b) explicitly warn that only OPPOSING-team illegal
            -- plays qualify — calling Takweesh on a same-team
            -- teammate's illegal play counts as a wrong call
            -- (HostBeginTakweeshReview / HostResolveTakweesh scan
            -- filter at Net.lua:3362 + 3545). Pre-v3.2.7 the
            -- tooltip was silent on the same-team rule, causing
            -- the v3.2.6 investigation's Scenario B UX hazard
            -- when a human teammate of a noise-AKA-emitting bot
            -- pre-emptively clicked TAKWEESH.
            -- Two phrases are deliberately kept on single source
            -- lines so the BN.1 / BN.2 source-pin tests can anchor
            -- the v3.2.7 clarifications via single-line Lua-pattern
            -- finds (see .swarm_findings/v3_2_7_takweesh_tooltip_design.md).
            -- Re-flowing across line breaks would defeat the pin
            -- without changing the rendered tooltip.
            addConfirmAction("|cffff5555TAKWEESH|r",
                "|cffff5555TAKWEESH? again to confirm|r",
                function() net().LocalTakweesh() end,
                "TAKWEESH — accuse the most recent illegal play "
                .. "(Saudi 'tikweesh', accusation of foul). If the "
                .. "play was actually illegal and publicly provable "
                .. "(for example, a false AKA marker or a later same-suit reveal after an off-suit play), "
                .. "the offending team takes a ~30-pt qaid penalty. "
                .. "Only OPPOSING-team illegal plays qualify; "
                .. "calling Takweesh on your own teammate counts as a wrong call. "
                .. "Wrong call costs YOUR team the same penalty. Use only when you're sure.")
            -- SWA (سوا) — claim-the-rest. Saudi-table convention:
            -- ≤3 cards = instant, 4+ cards requires opponent
            -- permission (handled by N.LocalSWA branch). Toggle the
            -- mechanic via /baloot swa, the permission gate via
            -- /baloot swaperm.
            local swaEnabled = (WHEREDNGNDB == nil)
                or (WHEREDNGNDB.allowSWA ~= false)
            -- Hide the SWA button if a request is already in flight
            -- (caller waiting on opponents) so it doesn't double-fire.
            local swaPending = S.s.swaRequest ~= nil
            if swaEnabled and not swaPending then
                addConfirmAction("|cffffd055SWA|r",
                    "|cffffd055SWA? again to confirm|r",
                    function() net().LocalSWA() end,
                    "SWA — claim you can take all remaining tricks. "
                    .. "<=3 cards is auto-allowed; 4+ requires opps' permission. "
                    .. "If your claim fails, you take a ~30 game-point penalty.")
            end
            -- If we're a non-caller opponent of a pending SWA request,
            -- show Accept/Deny vote buttons. Caller's team and the
            -- caller themselves don't vote.
            if S.s.swaRequest and S.s.swaRequest.caller
               and S.s.localSeat ~= S.s.swaRequest.caller
               and R.TeamOf(S.s.localSeat) ~= R.TeamOf(S.s.swaRequest.caller) then
                local already = S.s.swaRequest.responses
                                and S.s.swaRequest.responses[S.s.localSeat]
                if already == nil then
                    -- v0.11.0 U-7 fix (audit_v0.10.7 B_UIState_audit.md
                    -- HIGH): Deny SWA was single-click via addAction —
                    -- a misclick costs the team ~30 game points (handTotal
                    -- × mult, awarded as the qaid penalty against the
                    -- caller). Takweesh has confirm-action protection;
                    -- Deny didn't, even though the consequence is
                    -- comparable. Switching to addConfirmAction matches
                    -- the protection level. Accept stays single-click —
                    -- accepting an SWA where caller could lose is the
                    -- BENIGN outcome for the responder (the loss falls
                    -- on the caller if they're wrong).
                    -- v2.2.0 (audit v1.6.1 UX-07 MED): Accept now also
                    -- two-clicks (matches Deny pattern) for symmetry.
                    -- Pre-fix Accept was single-click while Deny was
                    -- confirm-armed — asymmetric protection. Both
                    -- consequences are real (Accept locks the team
                    -- into letting a possibly-bluffing claim through);
                    -- both deserve the same misclick guard.
                    addConfirmAction("|cff66ff88Accept SWA|r",
                        "|cff66ff88Confirm Accept — let them claim?|r",
                        function() net().LocalSWAResp(true) end,
                        "Allow the SWA. Saudi 'nasmah' — let them claim. "
                        .. "If wrong, the loss falls on the caller.")
                    addConfirmAction("|cffff5544Deny SWA|r",
                        "|cffff7755Confirm Deny — caller's invalid claim costs them ~30 pts; if Deny is wrong, your team takes the penalty.|r",
                        function() net().LocalSWAResp(false) end,
                        "Demand proof. Saudi 'sharh'. If caller's hand actually "
                        .. "holds the claim, your team takes a ~30-pt penalty.")
                end
            end
            -- AKA (إكَهْ) — partner-coordination call. Visible only when
            -- the local player holds the highest unplayed card in some
            -- non-trump suit (Hokm contracts only). Soft signal: it
            -- broadcasts a voice cue + banner so the partner can avoid
            -- over-trumping, but the player still has to actually play
            -- the card themselves.
            if S.s.contract and S.s.contract.type == K.BID_HOKM then
                local cand = S.LocalAKAcandidate and S.LocalAKAcandidate()
                if cand then
                    local glyph = K.SUIT_GLYPH[cand.suit] or cand.suit
                    -- Label uses Latin "AKA" because WoW's bundled fonts
                    -- (Arial Narrow / Frizz / Skurri) don't include
                    -- Arabic glyphs — Arabic chars in a button label
                    -- render as empty boxes. The voice cue still says
                    -- إكَهْ, so the audio carries the Saudi feel.
                    addAction(("|cff66ff88AKA|r %s"):format(glyph),
                        function() net().LocalAKA(cand.suit) end,
                        "AKA — partner-coordination call (Saudi 'eka'). "
                        .. "Tells your partner you hold the highest live "
                        .. "card in this suit, so they shouldn't over-"
                        .. "trump. Soft signal — you still have to play "
                        .. "the card yourself.")
                end
            end
            -- v1.0.11 (D HIGH-2): BALOOT! button — Saudi spelling per
            -- user request. Shown when local seat holds at least one
            -- of K-or-Q-of-trump (the other may have just been played
            -- on the second-card-of-pair moment, per PDF rule), Hokm
            -- contract, hasn't yet announced. Click broadcasts
            -- MSG_BELOTE so R.ScoreRound counts the +20 bonus. Bots
            -- auto-announce (Net._HostMaybeAutoBelote); humans must
            -- click manually.
            if S.s.contract and S.s.contract.type == K.BID_HOKM
               and S.s.contract.trump and S.s.localSeat then
                local already = S.s.beloteAnnounced
                                  and S.s.beloteAnnounced[S.s.localSeat]
                if not already then
                    -- v3.1.12 (codex audit P2): use LOCAL hand (S.s.hand)
                    -- not host-only S.s.hostHands. Pre-fix the in-hand
                    -- scan only worked on the HOST — non-host humans
                    -- holding K+Q of trump never saw the BALOOT button
                    -- until BOTH cards had been played (only then did
                    -- the played-card scan below catch them, by which
                    -- time the K/Q pair was already on the table and
                    -- the player had missed their click window).
                    --
                    -- Per UI.lua:10 (file-level invariant): UI never
                    -- reads s.hostHands. The pre-fix line was the lone
                    -- violation of that invariant.
                    --
                    -- Detect: did local seat ever HOLD K+Q-of-trump?
                    -- Combine current hand + cards already played by
                    -- this seat. If both K and Q seen, show button.
                    local trump = S.s.contract.trump
                    local hasK, hasQ = false, false
                    for _, c in ipairs(S.s.hand or {}) do
                        if C.Suit(c) == trump then
                            if     C.Rank(c) == "K" then hasK = true
                            elseif C.Rank(c) == "Q" then hasQ = true end
                        end
                    end
                    -- Also count played cards by this seat.
                    local function scan(plays)
                        for _, p in ipairs(plays or {}) do
                            if p.seat == S.s.localSeat
                               and C.Suit(p.card) == trump then
                                if     C.Rank(p.card) == "K" then hasK = true
                                elseif C.Rank(p.card) == "Q" then hasQ = true end
                            end
                        end
                    end
                    for _, t in ipairs(S.s.tricks or {}) do scan(t.plays) end
                    if S.s.trick then scan(S.s.trick.plays) end
                    if hasK and hasQ then
                        -- Bright yellow label, all-caps Saudi spelling.
                        local btn = addAction("|cffffff00BALOOT!|r",
                            function() net().LocalBelote() end,
                            "BALOOT! — declare K+Q-of-trump for +20 raw "
                            .. "points. Saudi rule: multiplier-IMMUNE (a ×4 "
                            .. "round doesn't ×4 the bonus). Click to "
                            .. "announce; otherwise the bonus isn't awarded.")
                        -- Flash: pulse the text color via OnUpdate so
                        -- it grabs attention. WoW Button:GetFontString
                        -- returns the label FontString; SetTextColor
                        -- uses RGB ∈ [0,1]. Cycle 2 Hz between bright
                        -- gold and white. PulseScript is a no-op if
                        -- the frame API isn't available (test env).
                        --
                        -- v2.1.0 (audit v1.6.1 UX-05 LOW): pulse only
                        -- for the first 5s after appearance, then
                        -- settle to a static gold. Pre-fix the
                        -- always-pulsing yellow added persistent
                        -- visual chatter even after the player had
                        -- noticed. Pulse-window long enough to grab
                        -- attention; settle prevents fatigue.
                        if btn and btn.SetScript then
                            btn._beloteT = 0
                            btn:SetScript("OnUpdate", function(self, elapsed)
                                self._beloteT = (self._beloteT or 0) + (elapsed or 0)
                                local fs = self.GetFontString and self:GetFontString()
                                if not (fs and fs.SetTextColor) then return end
                                if self._beloteT > 5.0 then
                                    -- Settle to static gold; clear OnUpdate
                                    -- to stop the per-tick churn.
                                    fs:SetTextColor(1, 0.92, 0.10)
                                    self:SetScript("OnUpdate", nil)
                                else
                                    local pulse = (math.sin(self._beloteT * 6.283) + 1) * 0.5
                                    -- Flash: gold → bright yellow.
                                    fs:SetTextColor(1, 0.85 + pulse * 0.15, pulse * 0.4)
                                end
                            end)
                        end
                    end
                end
            end
        end
    elseif S.s.phase == K.PHASE_SCORE then
        if S.s.isHost then
            addAction("Next Round", function()
                if S.s.cumulative.A >= S.s.target or S.s.cumulative.B >= S.s.target then
                    return
                end
                net().HostStartRound()
            end,
            "Host: deal the next round. Locked when either team has "
            .. "reached the cumulative target.")
        else
            -- v2.2.0 (audit v1.6.1 MP-62 LOW): non-host affordance at
            -- score phase. Pre-fix non-hosts saw zero buttons during
            -- PHASE_SCORE — host could stall indefinitely with no
            -- way for the table to nudge them. Adds a soft "Ready"
            -- indicator (cosmetic — doesn't actually advance the
            -- round, but tells the host visually that everyone has
            -- finished reading the score banner). For now just a
            -- disabled label; future work could broadcast a "ready"
            -- ping to the host.
            local readyBtn = addAction("|cff999999(host advances)|r",
                function() end,
                "Only the host can advance to the next round. They'll "
                .. "see your seat is no longer holding their attention.")
            -- Keep the button visually disabled so it's clearly not
            -- actionable.
            if readyBtn and readyBtn.Disable then
                readyBtn:Disable()
            end
        end
    elseif S.s.phase == K.PHASE_GAME_END then
        if S.s.isHost then
            addAction("New Game", function()
                -- v3.0.1 (audit v3.0.0 REG-04 HIGH): broadcast host-
                -- gone teardown so remotes don't hold a sticky
                -- GAME_END banner waiting for the 45s heartbeat
                -- timeout. Mirrors the v3.0.1 CFI-01 fix on the
                -- popup-Reset path.
                if S.s.gameID and net().SendLobby then
                    net().SendLobby({}, S.s.gameID)
                end
                if net().StopHostHeartbeat then
                    net().StopHostHeartbeat()
                end
                S.Reset()
                S.SetLocalName(GetUnitName("player", true))
                U.Refresh()
            end,
            "Reset to a fresh lobby. Wipes the current game state "
            .. "for all connected players.")
        end
        -- v2.1.0 (audit v1.6.1 PJ-43 MED): give game-end MORE paths
        -- than just "New Game". Pre-fix the only affordance was the
        -- host's "New Game" button — non-hosts saw no actions at
        -- all, and even the host had no quick way to view stats /
        -- history without typing slash commands.
        addAction("Stats", function()
            -- Re-uses /baloot stats output via SlashCmdList route.
            if SlashCmdList and SlashCmdList["BALOOT"] then
                SlashCmdList["BALOOT"]("stats")
            end
        end, "Show your lifetime W/L + bidder stats (cross-session).")
        if WHEREDNGNDB and WHEREDNGNDB.history and #WHEREDNGNDB.history > 0 then
            addAction("History", function()
                if SlashCmdList and SlashCmdList["BALOOT"] then
                    SlashCmdList["BALOOT"]("history 10")
                end
            end, "Show the last 10 round-result rows (full table via "
                .. "/baloot history).")
        end
    end
end

-- ----------------------------------------------------------------------
-- Render: hand
-- ----------------------------------------------------------------------

-- Pooled hand-card buttons.
local handPool = {}
local handUsed = 0

-- Hand button layout:
--   • A Texture child fills the button with the bundled card-face image.
--   • FontString labels (corner + center) are kept as a fallback for
--     situations where the texture isn't available; they get cleared
--     once the texture is bound.
local function makeHandButton(parent)
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    setBackdrop(b, true, COL.cardFace, COL.cardEdge, 6, "solid")

    b.tex = b:CreateTexture(nil, "ARTWORK")
    b.tex:SetPoint("TOPLEFT", 2, -2)
    b.tex:SetPoint("BOTTOMRIGHT", -2, 2)
    b.tex:Hide()

    -- Fallback FontStrings, used only if the card texture is missing.
    b.tlRank = b:CreateFontString(nil, "OVERLAY")
    b.tlRank:SetFont(K.CARD_FONT, 14, "")
    b.tlRank:SetPoint("TOPLEFT", 5, -4)
    b.tlSuit = b:CreateFontString(nil, "OVERLAY")
    b.tlSuit:SetFont(K.CARD_FONT, 12, "")
    b.tlSuit:SetPoint("TOPLEFT", 5, -19)
    b.center = b:CreateFontString(nil, "OVERLAY")
    b.center:SetFont(K.CARD_FONT, 36, "OUTLINE")
    b.center:SetPoint("CENTER", 0, 0)
    b.brSuit = b:CreateFontString(nil, "OVERLAY")
    b.brSuit:SetFont(K.CARD_FONT, 12, "")
    b.brSuit:SetPoint("BOTTOMRIGHT", -5, 19)
    b.brRank = b:CreateFontString(nil, "OVERLAY")
    b.brRank:SetFont(K.CARD_FONT, 14, "")
    b.brRank:SetPoint("BOTTOMRIGHT", -5, 4)

    return b
end

local function clearHand()
    for i = 1, handUsed do
        local b = handPool[i]
        if b then
            b:Hide()
            b:SetScript("OnClick", nil)
            b:SetScript("OnEnter", nil)
            b:SetScript("OnLeave", nil)
        end
    end
    handUsed = 0
end

local function renderHand()
    clearHand()
    local hand = S.s.hand or {}
    if #hand == 0 then return end

    local sortable = { unpack(hand) }
    C.SortHand(sortable, S.s.contract or { type = K.BID_SUN })

    local legalSet = {}
    for _, c in ipairs(S.GetLegalPlays()) do legalSet[c] = true end

    local btnW, btnH = 70, 100
    local total = #sortable * (btnW + 6) - 6
    local startX = -total / 2 + btnW / 2

    -- FontString fallback (only used when the card texture is missing).
    -- Four-color deck colors so same-shape suits are still distinct.
    local function rankSuitFor(card)
        local r, s = C.Rank(card), C.Suit(card)
        local color = K.SUIT_COLOR_ONCARD[s] or "ff111111"
        local rankStr = ("|c%s%s|r"):format(color, C.RankGlyph(r))
        local suitStr = ("|c%s%s|r"):format(color, K.SUIT_GLYPH[s] or s)
        return rankStr, suitStr, color
    end

    for i, card in ipairs(sortable) do
        handUsed = handUsed + 1
        local b = handPool[handUsed]
        if not b then
            b = makeHandButton(tablePanel.handRow)
            b:SetSize(btnW, btnH)
            handPool[handUsed] = b
        end
        b:ClearAllPoints()
        b:SetPoint("CENTER", tablePanel.handRow, "CENTER",
            startX + (i - 1) * (btnW + 6), 0)

        -- Prefer the bundled card texture. If it loads, blank out the
        -- fallback FontStrings; otherwise leave them populated so the
        -- card is still readable.
        local path = cardTexturePath(card)
        if path then
            b.tex:SetTexture(path)
            b.tex:Show()
            b.tlRank:SetText(""); b.tlSuit:SetText("")
            b.brRank:SetText(""); b.brSuit:SetText("")
            b.center:SetText("")
        else
            b.tex:Hide()
            local rankStr, suitStr = rankSuitFor(card)
            b.tlRank:SetText(rankStr); b.tlSuit:SetText(suitStr)
            b.brRank:SetText(rankStr); b.brSuit:SetText(suitStr)
            b.center:SetText(rankStr .. suitStr)
        end

        local labels = { b.center, b.tlRank, b.tlSuit, b.brRank, b.brSuit }
        for _, fs in ipairs(labels) do fs:SetAlpha(1) end

        -- v3.2.14 F1: after this seat has played this trick the cards
        -- must not look or behave playable even while S.IsMyTurn() is
        -- still true. Non-host LocalPlay does not advance S.s.turn
        -- locally, so the echo-gap optimistic refresh must not invite
        -- a second play (N.LocalPlay also dedupes; this is the visible
        -- affordance half of the same guard).
        local isPlayable = (S.s.phase == K.PHASE_PLAY and S.IsMyTurn()
            and not S.s.localPlayedThisTrick)
        if isPlayable then
            if legalSet[card] then
                -- Gold border + bright = the "safe" play
                b:SetBackdropBorderColor(unpack(COL.legalEdge))
                -- v2.2.0 PJ-31: hide the warning corner-tag if present
                -- (pool reuse from a previous illegal state).
                if b.warnTag then b.warnTag:Hide() end
            else
                -- Orange/red border = warning-only. Still clickable
                -- (Saudi Takweesh rule: illegal plays go through; you
                -- get caught if opponents call it). Keep full opacity
                -- so it doesn't look disabled.
                b:SetBackdropBorderColor(unpack(COL.badEdge))
                -- v2.2.0 (audit v1.6.1 PJ-31 MED): visible "!" warning
                -- tag in the card's top-left corner for illegal cards.
                -- Pre-fix the orange border alone wasn't distinct
                -- enough from cardEdge / hover-lift states — colorblind
                -- and quick-glance players missed the warning. The
                -- corner glyph is unmissable and reads as "stop, look".
                if not b.warnTag then
                    b.warnTag = b:CreateFontString(nil, "OVERLAY",
                                                   "GameFontNormalLarge")
                    b.warnTag:SetPoint("TOPLEFT", b, "TOPLEFT", 4, -2)
                    b.warnTag:SetTextColor(0.95, 0.55, 0.20, 1)
                    b.warnTag:SetText("|cffff8833!|r")
                end
                b.warnTag:Show()
            end
        else
            b:SetBackdropBorderColor(unpack(COL.cardEdge))
            if b.warnTag then b.warnTag:Hide() end
        end

        local thisI, thisCard = i, card
        b:SetScript("OnEnter", function(self)
            if isPlayable then
                self:ClearAllPoints()
                self:SetPoint("CENTER", tablePanel.handRow, "CENTER",
                    startX + (thisI - 1) * (btnW + 6), 6)
            end
        end)
        b:SetScript("OnLeave", function(self)
            self:ClearAllPoints()
            self:SetPoint("CENTER", tablePanel.handRow, "CENTER",
                startX + (thisI - 1) * (btnW + 6), 0)
        end)
        b:SetScript("OnClick", function()
            if S.s.phase ~= K.PHASE_PLAY then return end
            if not S.IsMyTurn() then return end
            -- v3.2.14 F1: belt-and-suspenders — this seat already
            -- played this trick (echo gap before S.s.turn advances).
            -- N.LocalPlay also dedupes, but a stale-pooled clickable
            -- card must not even attempt a second play.
            if S.s.localPlayedThisTrick then return end
            -- v1.8.1 (audit v1.6.1 UX-21 HIGH): paused-state gate.
            -- Pre-fix the click was rejected silently downstream by
            -- N.LocalPlay's `S.s.paused` check at Net.lua:~2300, but
            -- the user got NO visible feedback — they thought their
            -- click landed and just sat waiting. Gate here AND surface
            -- a chat message so they know to /baloot status or ask the
            -- host to unpause.
            if S.s.paused then
                print("|cff66ddff[WHEREDNGN]|r Game is paused — wait for "
                    .. "host to resume.")
                return
            end
            -- DO NOT gate on legalSet. LocalPlay warns the player
            -- privately and lets the card through; that's the whole
            -- point of Takweesh.
            net().LocalPlay(thisCard)
        end)
        b:Show()
    end
end

-- ----------------------------------------------------------------------
-- Render: seat badges, center trick
-- ----------------------------------------------------------------------

-- Count cards remaining for each seat. We compute this only from public
-- info: total dealt minus plays we've witnessed via the trick log.
-- Local seat reads from s.hand (authoritative).
local function cardCountForSeat(seat)
    if seat == S.s.localSeat then return #S.s.hand end
    -- Total dealt: 5 (deal1) + 3 (deal3) = 8 if we've passed deal3,
    -- else 5 if mid-bidding. Simplest: deduce from phase.
    local total = 0
    if S.s.phase == K.PHASE_DEAL1 or S.s.phase == K.PHASE_DEAL2BID
       or S.s.phase == K.PHASE_PREEMPT
       or S.s.phase == K.PHASE_DOUBLE
       or S.s.phase == K.PHASE_TRIPLE or S.s.phase == K.PHASE_FOUR
       or S.s.phase == K.PHASE_GAHWA then
        total = 5
    elseif S.s.phase == K.PHASE_DEAL3 or S.s.phase == K.PHASE_PLAY
       or S.s.phase == K.PHASE_SCORE or S.s.phase == K.PHASE_GAME_END then
        total = 8
    end
    -- subtract plays we've seen from this seat
    local played = 0
    for _, t in ipairs(S.s.tricks) do
        for _, p in ipairs(t.plays) do if p.seat == seat then played = played + 1 end end
    end
    if S.s.trick then
        for _, p in ipairs(S.s.trick.plays) do if p.seat == seat then played = played + 1 end end
    end
    return math.max(0, total - played)
end

-- v1.0.6 (B#3+#4 cleanup): `meldsDescForSeat` removed. Since v1.0.5
-- the trick-1 meld text label is permanently hidden (`meldTextVisible()`
-- always returns false). The function generated the text-label
-- description ("Carré K (100)" etc.) which had no consumer post-v1.0.5.
-- Sound cue (S.ApplyMeld in State.lua) handles the trick-1 announcement;
-- trick-2 card strip (meldCardsForSeat below) handles the proof reveal.

-- Show only the seat's BEST meld (highest .value). Pre-v1.0.1 this
-- function concatenated cards from EVERY meld the seat declared, then
-- truncated to the 5-slot strip — producing misleading visuals like
-- "JS JH JD JC + KS" (carré-J + first card of an unrelated seq3),
-- which a player could misread as "three Js with K" (an illegal meld
-- shape). Saudi rule says only the best meld counts for the team-vs-
-- team comparison anyway, so render only the best one — deterministic
-- and unambiguous.
--
-- Tie-break (same .value across multiple melds): pick the one with
-- the higher .top rank, then the one declared first (stable order
-- via list iteration). Sequence vs carré at equal value (e.g. seq5=100
-- vs carre-K=100) — no canonical Saudi rule, so first-declared wins
-- (matches `R.CompareMelds` ordering at Rules.lua:548+).
local function meldCardsForSeat(seat)
    local team = R.TeamOf(seat)
    local list = S.s.meldsByTeam[team] or {}
    -- v3.0.2 (user-reported: "melds are not counted when player has
    -- two"). The SCORING is correct (R.SumMeldValue sums all melds
    -- per team — pinned by the v3.0.2 multi-meld test in test_rules.lua)
    -- but this trick-2 reveal previously showed only the BEST meld's
    -- cards — players seeing only one meld card-strip on a multi-meld
    -- declarer assumed only one was counted.
    --
    -- Trade-off: v1.0.1 documented that concatenating cards across
    -- distinct melds + truncating to the 5-slot strip produced
    -- visually-misleading combos (e.g. "JS JH JD JC + KS" reads as
    -- a 5-card K-J shape — illegal). v3.0.2 splits the difference:
    -- if all the seat's meld cards fit in 5 slots, show them all
    -- (no truncation, no misleading shape). If they don't fit, fall
    -- back to v1.0.1's best-only — still misleading visual would be
    -- worse than the under-display.
    local seatMelds = {}
    local totalCards = 0
    for _, m in ipairs(list) do
        if m.declaredBy == seat and m.cards then
            seatMelds[#seatMelds + 1] = m
            totalCards = totalCards + #m.cards
        end
    end
    if totalCards <= 5 then
        -- All meld cards fit — show every meld.
        local out = {}
        for _, m in ipairs(seatMelds) do
            for _, c in ipairs(m.cards) do
                out[#out + 1] = c
            end
        end
        return out
    end
    -- Doesn't fit — show only best meld's cards (v1.0.1 behavior).
    local best = nil
    for _, m in ipairs(seatMelds) do
        if not best or (m.value or 0) > (best.value or 0) then
            best = m
        end
    end
    if not best then return {} end
    local out = {}
    for _, c in ipairs(best.cards) do
        out[#out + 1] = c
        if #out >= 5 then break end
    end
    return out
end

-- Per Saudi rule the meld CARDS are only visible briefly in trick 2:
--   • Trick 1: ANNOUNCEMENT only — sound cue (S.ApplyMeld fires
--     K.SND_MELD_SERA / 50 / 100 / 400 from v1.0.2). Text label is
--     intentionally HIDDEN — Saudi convention is verbal-only in real
--     play (no on-screen badge). User-requested behavior change in
--     v1.0.5.
--   • Trick 2: when a declarer's turn starts, their actual cards are
--     revealed for 5 seconds (set via S.ApplyTurn -> meldHoldUntil),
--     then hidden permanently for the rest of the hand.
--   • Trick 3+: cards never visible. Text label never visible at any
--     phase post-v1.0.5. Round-end banner is the canonical source of
--     "what melds got declared" after the round.
local function meldStripVisibleFor(seat)
    if S.s.phase ~= K.PHASE_PLAY then return false end
    if not S.s.meldHoldUntil or not S.s.meldHoldUntil[seat] then
        return false
    end
    local now = (GetTime and GetTime()) or 0
    return now < S.s.meldHoldUntil[seat]
end

-- v1.0.5 hid the trick-1 meld text label (Saudi convention is verbal-
-- only declaration, no on-screen badge). v1.0.6 removed the now-dead
-- `meldTextVisible()` helper and the `meldsDescForSeat()` builder it
-- gated, since neither has any consumer. The meldText widget is kept
-- only for layout anchoring — `:SetText("")` calls are at renderSeats.

-- 28th-audit / player feedback: render a player's bid for the seat
-- badges during the bidding phases. "HOKM:S" → "حكم ♠" with the
-- suit glyph so over-bidders see the Hokm direction. PASS / SUN /
-- ASHKAL render as their plain labels. Returns "" outside bidding
-- phases or when the seat has no bid yet.
local function bidLabelForSeat(seat)
    if not seat then return "" end
    if S.s.phase ~= K.PHASE_DEAL1 and S.s.phase ~= K.PHASE_DEAL2BID then
        return ""
    end
    local b = S.s.bids and S.s.bids[seat]
    if not b or b == "" then return "" end
    if b == K.BID_PASS then
        -- Player-reported UI fix: was "|cff888888بس|r" (Arabic
        -- "Pass") but WoW's bundled fonts (Arial Narrow / Frizz /
        -- Skurri) don't include Arabic glyphs — the label rendered
        -- as empty boxes under other players' names. Same constraint
        -- documented on the AKA button. Match the local-side label
        -- convention: "wla" in R2 (transliteration of ولا), "Pass"
        -- in R1.
        local label = (S.s.phase == K.PHASE_DEAL2BID) and "wla" or "Pass"
        return ("|cff888888%s|r"):format(label)
    elseif b == K.BID_SUN then
        return "|cffffd055SUN|r"
    elseif b == K.BID_ASHKAL then
        return "|cffffd055ASHKAL|r"
    elseif b:sub(1, #K.BID_HOKM) == K.BID_HOKM then
        local suit = b:sub(#K.BID_HOKM + 2)  -- skip "HOKM:"
        local glyph = K.SUIT_GLYPH and K.SUIT_GLYPH[suit] or suit
        local color = K.SUIT_COLOR_ONCARD and K.SUIT_COLOR_ONCARD[suit]
                       or "ffffd055"
        return ("|cffffd055HOKM|r |c%s%s|r"):format(color, glyph)
    end
    return b  -- fallback: raw bid string
end

local function renderSeats()
    -- Spectators (no localSeat) anchor at seat 1 — the right/top/left
    -- badges show seats 2/3/4. Seat 1 is rendered in a separate
    -- spectator-info line (see renderSpectatorInfo). For seated
    -- players this branch is unchanged.
    --
    -- Team coloring: for seated players, top = partner (Us, green),
    -- left/right = opponents (Them, red). For spectators (no team
    -- identity), all three badges fall back to neutral A/B coloring
    -- via teamColor() so they don't claim partner-of-anyone status.

    -- Top, left, right are seat badges (other players). Bottom is the
    -- local-player bar (no card-back row; the hand below shows everything).
    for _, pos in ipairs({ "top", "left", "right" }) do
        local seat = seatAtPos(pos)
        local b = seatBadges[pos]
        if seat and b then
            local info = S.s.seats[seat]
            local nm = info and shortName(info.name) or "(empty)"
            -- For seated players: top = partner (us-green), left/right
            -- = opponents (them-red). For spectators: no team identity,
            -- so render names by absolute team (A green / B red) using
            -- the same neutral fallback applied elsewhere.
            local teamCol
            if S.s.localSeat then
                teamCol = (pos == "top") and COL.txtUs or COL.txtThem
            else
                teamCol = (R.TeamOf(seat) == "A") and COL.txtUs or COL.txtThem
            end
            b.nameText:SetText("|c" .. teamCol .. nm .. "|r")
            local cnt = cardCountForSeat(seat)
            for i = 1, 8 do
                if i <= cnt then b.backs[i]:Show() else b.backs[i]:Hide() end
            end
            b.countText:SetText(("|c"..COL.txtSoft.."%d|r"):format(cnt))
            -- v1.0.6 (B#3 cleanup): single-window meld display.
            -- Trick 1 = sound cue only (S.ApplyMeld in State.lua);
            -- Trick 2 = card strip during the seat's 5-second hold.
            -- The trick-1 text label was retired in v1.0.5; the
            -- meldText widget is now reused only as an empty-string
            -- carrier (kept for layout — frame is anchored to it).
            if meldStripVisibleFor(seat) then
                setMeldStripCards(b.meldStrip, meldCardsForSeat(seat), 1.0)
            else
                if b.meldStrip then b.meldStrip:Hide() end
            end
            b.meldText:SetText("")
            b.dealerText:SetText(seat == S.s.dealer and "D" or "")
            -- 28th-audit: bid label below the name. Shows "HOKM ♠"
            -- when a player calls Hokm in round 2, so over-bidders
            -- can choose Sun / Bel knowingly. Hidden outside the
            -- bidding phases.
            if b.bidText then
                b.bidText:SetText(bidLabelForSeat(seat))
            end
            -- Avatar: bot seats get the bundled colored badge; humans
            -- have no avatar so the seat reads "live player".
            if b.avatar then
                if info and info.isBot and seat >= 2 and seat <= 4 then
                    b.avatar:SetTexture(
                        "Interface\\AddOns\\WHEREDNGN\\cards\\avatar_" .. seat)
                    b.avatar:Show()
                else
                    b.avatar:Hide()
                end
            end
            if S.s.turn == seat then
                b.turnGlow:Show()
                b.frame:SetBackdropBorderColor(unpack(COL.legalEdge))
                -- v1.8.0 (audit v1.6.1 BF-10 CRITICAL): "Thinking…"
                -- indicator on bot-active seats. Pre-fix the turnGlow
                -- was identical for bot-thinking and human-AFK — players
                -- couldn't tell whether to wait or reload. Adds a
                -- soft-cycling "thinking" suffix to the count text only
                -- when the active seat is a bot AND we're locally on
                -- host (so the indicator only shows on the machine
                -- actually running the bot's decision timer).
                if info and info.isBot and S.s.isHost
                   and (S.s.turnKind == "bid" or S.s.turnKind == "play") then
                    -- v2.0.1 fix: WoW FontStrings don't support
                    -- SetScript("OnUpdate", …) — only Frame-derived
                    -- objects do. The original v1.8.0 BF-10 code
                    -- attached the pulse OnUpdate directly to the
                    -- FontString and crashed on first Show. Now wrap
                    -- the label in a tiny Frame; OnUpdate lives on
                    -- the Frame, which cycles the inner FontString's
                    -- alpha each tick.
                    if not b.thinkBox then
                        b.thinkBox = CreateFrame("Frame", nil, b.frame)
                        b.thinkBox:SetSize(80, 14)
                        b.thinkBox:SetPoint("BOTTOM", b.frame, "BOTTOM", 0, 4)
                        b.thinkBox._t = 0
                        b.thinkBox.label = b.thinkBox:CreateFontString(
                            nil, "OVERLAY", "GameFontNormalSmall")
                        b.thinkBox.label:SetAllPoints(b.thinkBox)
                        b.thinkBox.label:SetTextColor(0.4, 0.8, 1, 0.9)
                        b.thinkBox:SetScript("OnUpdate", function(self, elapsed)
                            self._t = (self._t or 0) + (elapsed or 0)
                            local pulse = (math.sin(self._t * 4.4) + 1) * 0.5
                            if self.label and self.label.SetAlpha then
                                self.label:SetAlpha(0.55 + pulse * 0.40)
                            end
                        end)
                    end
                    b.thinkBox.label:SetText("|cff66ddffthinking…|r")
                    b.thinkBox:Show()
                elseif b.thinkBox then
                    b.thinkBox:Hide()
                end
            else
                b.turnGlow:Hide()
                b.frame:SetBackdropBorderColor(unpack(COL.woodEdge))
                -- v2.0.1: thinkText was the v1.8.0 FontString; v2.0.1
                -- wraps it in thinkBox. Hide both for back-compat in
                -- case state was persisted across the upgrade.
                if b.thinkText then b.thinkText:Hide() end
                if b.thinkBox then b.thinkBox:Hide() end
            end
        end
    end

    -- Spectator branch: hide the local bar (we have no seat to display)
    -- and show the specInfo line in its place with seat 1's name +
    -- card count. Players' rendering below is fully gated on
    -- S.s.localSeat so we early-return here for spectators without
    -- side-effects on player paths.
    local lb = tablePanel.localBar
    local specInfo = tablePanel.specInfo
    if not S.s.localSeat then
        if lb then lb:Hide() end
        if specInfo then
            local info = S.s.seats and S.s.seats[1]
            local nm = (info and info.name) and shortName(info.name) or "(empty)"
            local cnt = cardCountForSeat(1)
            local teamCol = (R.TeamOf(1) == "A") and COL.txtUs or COL.txtThem
            specInfo.bottomSeat:SetText(("|c%s%s|r |c%s(%d)|r"):format(
                teamCol, nm, COL.txtSoft, cnt))
            specInfo:Show()
        end
        return
    end
    if specInfo then specInfo:Hide() end
    if lb then lb:Show() end

    -- Local bar — fall back to S.s.localName if the seat record was
    -- somehow stripped of its name (e.g. an empty SendLobby payload).
    local me = S.s.localSeat
    local meInfo = S.s.seats[me]
    local rawName = (meInfo and meInfo.name) or S.s.localName
    local nm = rawName and shortName(rawName) or "you"
    local prefix = me == S.s.dealer and "D " or ""
    lb.nameText:SetText(prefix .. "|c" .. COL.txtGold .. nm .. "|r")
    -- v1.0.6 (B#3 cleanup): single-window meld display for local
    -- player too. Trick 1 = sound cue only; Trick 2 = card strip.
    -- meldText is empty-string carrier post-v1.0.5.
    if meldStripVisibleFor(me) then
        setMeldStripCards(lb.meldStrip, meldCardsForSeat(me), 1.0)
    else
        if lb.meldStrip then lb.meldStrip:Hide() end
    end
    lb.meldText:SetText("")
    if S.s.turn == me then
        lb:SetBackdropBorderColor(unpack(COL.legalEdge))
        if lb.turnGlow then lb.turnGlow:Show() end
    else
        lb:SetBackdropBorderColor(unpack(COL.woodEdge))
        if lb.turnGlow then lb.turnGlow:Hide() end
    end
end

-- Rendering target for the center area. Default is the live trick;
-- the last-trick peek temporarily swaps this to the previous trick.
local centerOverride = nil

-- Track number of plays in the current trick across renders so we can
-- detect "a new card just landed" and run the scale+fade animation
-- without re-animating cards that were already in place.
local prevTrickPlayCount = 0

-- Slide-in animation: card flies from the seat edge toward the center.
-- We animate the frame's anchor offset in steps via a C_Timer ticker
-- (Blizzard's AnimationGroup / Translation only translates the visual
-- position WITHOUT moving the anchor, which makes "land at the anchor"
-- awkward to express. A few re-anchors per second is cheap and keeps
-- the math obvious.)
local SLIDE_FROM = {
    top    = { dx =    0, dy =  140 },
    bottom = { dx =    0, dy = -140 },
    left   = { dx = -180, dy =    0 },
    right  = { dx =  180, dy =    0 },
}

local function animateLand(slot, fromPos)
    if not slot or not slot.frame then return end
    local off = SLIDE_FROM[fromPos] or SLIDE_FROM.bottom
    local frame = slot.frame
    -- Capture the slot's anchored position once. SetPoint with the
    -- same args restores it to the canonical "landing spot".
    if not slot._origPoint then
        slot._origPoint = { frame:GetPoint(1) }
    end
    local pt, rel, relPt, ox, oy = unpack(slot._origPoint)

    -- Swish on the slide. Lands as a card_play slap from S.ApplyPlay.
    B.Sound.Try(K.SND_CARD_SWISH)

    local steps = 8
    local stepDur = (K.CARD_ANIM_SEC or 0.22) / steps
    local i = 0
    frame:ClearAllPoints()
    frame:SetPoint(pt, rel, relPt, ox + off.dx, oy + off.dy)
    frame:SetAlpha(0.5)

    local ticker
    ticker = C_Timer.NewTicker(stepDur, function()
        i = i + 1
        local t = i / steps
        -- Ease-out: 1 - (1-t)^2 — fast at start, soft landing.
        local eased = 1 - (1 - t) * (1 - t)
        frame:ClearAllPoints()
        frame:SetPoint(pt, rel, relPt,
            ox + off.dx * (1 - eased),
            oy + off.dy * (1 - eased))
        frame:SetAlpha(0.5 + 0.5 * eased)
        if i >= steps then
            ticker:Cancel()
            frame:ClearAllPoints()
            frame:SetPoint(pt, rel, relPt, ox, oy)
            frame:SetAlpha(1)
        end
    end, steps)
end

local function renderCenter()
    for _, slot in pairs(centerCards) do
        slot.frame:Hide()
        setCardSlot(slot, nil)   -- clears tex + label together
        slot.frame:SetBackdropBorderColor(unpack(COL.cardEdge))
        if slot.glow then slot.glow:Hide() end
    end
    -- Last-trick peek override: show the previous trick exactly where
    -- the live one would appear, with the winning card glowing gold.
    if centerOverride and centerOverride.plays then
        for _, p in ipairs(centerOverride.plays) do
            local pos = posOfSeat(p.seat)
            local slot = centerCards[pos]
            if slot then
                slot.frame:Show()
                setCardSlot(slot, p.card)
                if p.seat == centerOverride.winner then
                    slot.frame:SetBackdropBorderColor(unpack(COL.legalEdge))
                    if slot.glow then slot.glow:Show() end
                end
            end
        end
        return
    end
    -- During bidding AND the escalation chain, keep the bid card
    -- visible so players retain the "what was bid" reference all the
    -- way through Pre-empt / Bel / Triple / Four / Gahwa decisions.
    -- The bid card is only finally cleared when PHASE_PLAY starts.
    if S.s.phase == K.PHASE_DEAL1 or S.s.phase == K.PHASE_DEAL2BID
       or S.s.phase == K.PHASE_PREEMPT
       or S.s.phase == K.PHASE_DEAL3
       or S.s.phase == K.PHASE_DOUBLE
       or S.s.phase == K.PHASE_TRIPLE
       or S.s.phase == K.PHASE_FOUR
       or S.s.phase == K.PHASE_GAHWA then
        -- v1.4.4 (UI fix — user-reported): hide the bid card during
        -- the dice-roll window so it doesn't bleed through behind
        -- the DICE ROLL banner. Banner shows for ~3.5s at game start;
        -- bid card resumes when dealerRollAt expires.
        local now = (GetTime and GetTime()) or 0
        if S.s.dealerRollAt and now < S.s.dealerRollAt then
            local slot = centerCards.bid
            if slot and slot.frame then slot.frame:Hide() end
            return
        end
        if S.s.bidCard then
            local slot = centerCards.bid
            slot.frame:Show()
            setCardSlot(slot, S.s.bidCard)
            -- v2.0.0 (audit v1.6.1 PJ-10 HIGH): label the bid card so
            -- new players know what the centre card represents.
            -- Pre-fix the up-card was rendered with no caption — a
            -- new player saw a single card sitting in the middle of
            -- the table with no idea why. Now adds "Bid card" label
            -- above the slot during DEAL1 (round-1 bidding only —
            -- round-2 has all-suit-options so the bid card is no
            -- longer the trump constraint).
            if not slot.bidLabel then
                slot.bidLabel = slot.frame:CreateFontString(
                    nil, "OVERLAY", "GameFontNormalSmall")
                slot.bidLabel:SetPoint("BOTTOM", slot.frame, "TOP", 0, 4)
                slot.bidLabel:SetTextColor(0.85, 0.85, 0.55, 1)
            end
            if S.s.phase == K.PHASE_DEAL1 then
                slot.bidLabel:SetText("|cffd0c055Bid card|r")
                slot.bidLabel:Show()
            else
                slot.bidLabel:Hide()
            end
        end
        return
    end
    -- Trick play: position each played card relative to who played it.
    if not S.s.trick or not S.s.trick.plays then
        prevTrickPlayCount = 0
        return
    end
    -- Trick-winner glow: when 4 cards are in, briefly highlight the
    -- winning card before the host clears the trick. The host's 1.5s
    -- delay in N._HostStepPlay gives us the window.
    local highlight
    if S.s.contract and #S.s.trick.plays == 4 then
        highlight = R.CurrentTrickWinner(S.s.trick, S.s.contract)
    end
    -- Detect newly-arrived plays since the last render (only animate
    -- those — already-rendered cards just stay put).
    local curCount = #S.s.trick.plays
    local newFromIdx = (curCount > prevTrickPlayCount) and (prevTrickPlayCount + 1) or nil
    for i, p in ipairs(S.s.trick.plays) do
        local pos = posOfSeat(p.seat)
        local slot = centerCards[pos]
        if slot then
            slot.frame:Show()
            setCardSlot(slot, p.card)
            if highlight and p.seat == highlight then
                slot.frame:SetBackdropBorderColor(unpack(COL.legalEdge))
                if slot.glow then slot.glow:Show() end
            end
            if newFromIdx and i >= newFromIdx then
                -- Card slides in from whichever edge the player sits at.
                animateLand(slot, pos)
            end
        end
    end
    prevTrickPlayCount = curCount
end

-- Last-trick peek: temporarily display s.lastTrick for ~3 seconds,
-- only once per hand. Triggered by a small button next to the table.
-- Assigned to the file-level forward-declared `peekLastTrick` so
-- closures created earlier (in buildTable) resolve correctly.
peekLastTrick = function()
    if not S.s.lastTrick or not S.s.lastTrick.plays
       or #S.s.lastTrick.plays == 0 then
        return
    end
    if S.s.peekedThisRound then return end
    -- 6th-audit fix: phase gate. Peek is meant for the brief lull
    -- between tricks during PLAY (and the SWA voting window). If a
    -- player triggers the peek while a Takweesh / SWA banner has
    -- already moved phase to SCORE/GAME_END, the centerOverride lays
    -- the trick cards on top of the round-end banner for 3 seconds.
    if S.s.phase ~= K.PHASE_PLAY and S.s.phase ~= K.PHASE_DEAL3 then
        return
    end
    S.s.peekedThisRound = true
    centerOverride = S.s.lastTrick
    if U.Refresh then U.Refresh() end
    C_Timer.After(K.LAST_TRICK_PEEK_SEC, function()
        centerOverride = nil
        if U.Refresh then U.Refresh() end
    end)
end

-- ----------------------------------------------------------------------
-- Render: lobby
-- ----------------------------------------------------------------------

local function renderLobby()
    if S.s.gameID then
        gameIDText:SetText("|cffaaaaaaGame: " .. S.s.gameID .. "|r")
    else
        gameIDText:SetText("")
    end
    for i = 1, 4 do
        local txt = lobbyPanel.seatTexts[i]
        local info = S.s.seats[i]
        if info and info.name then
            local nm = shortName(info.name)
            if info.isBot then
                nm = "|cffaaccff" .. nm .. " |cff8899bb(bot)|r|r"
            elseif info.name == S.s.localName then
                nm = "|cff66ddff" .. nm .. " (you)|r"
            end
            txt:SetText(nm)
        else
            txt:SetText("|cff666666(empty)|r")
        end
        -- v3.0 MP-41: kick button visibility. Show only on host
        -- during lobby phase, only on occupied seats >= 2.
        local row = lobbyPanel.seatRows[i]
        if row and row.kickBtn then
            local canKick = S.s.isHost
                and S.s.phase == K.PHASE_LOBBY
                and i >= 2
                and info ~= nil
            row.kickBtn:SetShown(canKick)
        end
    end
    hostStartBtn:SetShown(S.s.isHost and S.LobbyFull())
    -- Fill Bots only useful for host while in lobby with empty seats
    local hasEmpty = S.s.isHost and S.s.phase == K.PHASE_LOBBY and not S.LobbyFull()
    if lobbyPanel.fillBotsBtn then
        lobbyPanel.fillBotsBtn:SetShown(hasEmpty)
    end
    -- v3.2.11: invitee editor — host + lobby + raid/instance group only
    -- (hidden in a normal party so the legacy flow is untouched).
    if lobbyPanel.invPanel then
        local ch = net() and net()._GroupChannel and net()._GroupChannel()
        local showInv = S.s.isHost and S.s.phase == K.PHASE_LOBBY
                        and (ch == "RAID" or ch == "INSTANCE_CHAT")
        lobbyPanel.invPanel:SetShown(showInv)
        if lobbyPanel.invList then
            lobbyPanel.invList:SetShown(showInv)
            if showInv then
                local inv = S.HostInvitees()
                if #inv == 0 then
                    lobbyPanel.invList:SetText("|cffaaaaaaNo invitees yet — "
                        .. "no public raid invite is sent until you add "
                        .. "one.|r")
                else
                    local disp = {}
                    for _, n in ipairs(inv) do
                        disp[#disp + 1] = shortName(n)
                    end
                    lobbyPanel.invList:SetText("|cff66ddffInvited:|r "
                        .. table.concat(disp, ", "))
                end
            end
        end
    end
    -- Bot difficulty checkboxes: host-only, lobby-only. Re-sync state
    -- with WHEREDNGNDB on every render so slash-command toggles
    -- propagate without a click. The cascade is:
    --   Saudi Master → Fzloky → M3lm → Advanced
    -- Lower-tier checkboxes auto-tick AND grey out when a higher
    -- tier is on.
    local hostInLobby = S.s.isHost and S.s.phase == K.PHASE_LOBBY
    local masterOn = WHEREDNGNDB and WHEREDNGNDB.saudiMasterBots == true
    local fzlokyOn = WHEREDNGNDB and WHEREDNGNDB.fzlokyBots == true
    local m3lmOn   = WHEREDNGNDB and WHEREDNGNDB.m3lmBots == true
    local advOn    = WHEREDNGNDB and WHEREDNGNDB.advancedBots == true
    if lobbyPanel.advancedCheck then
        lobbyPanel.advancedCheck:SetShown(hostInLobby)
        lobbyPanel.advancedCheck:SetChecked(advOn or m3lmOn or fzlokyOn or masterOn)
        if m3lmOn or fzlokyOn or masterOn then
            lobbyPanel.advancedCheck:Disable()
        else
            lobbyPanel.advancedCheck:Enable()
        end
    end
    if lobbyPanel.m3lmCheck then
        lobbyPanel.m3lmCheck:SetShown(hostInLobby)
        lobbyPanel.m3lmCheck:SetChecked(m3lmOn or fzlokyOn or masterOn)
        if fzlokyOn or masterOn then
            lobbyPanel.m3lmCheck:Disable()
        else
            lobbyPanel.m3lmCheck:Enable()
        end
    end
    if lobbyPanel.fzlokyCheck then
        lobbyPanel.fzlokyCheck:SetShown(hostInLobby)
        lobbyPanel.fzlokyCheck:SetChecked(fzlokyOn or masterOn)
        if masterOn then
            lobbyPanel.fzlokyCheck:Disable()
        else
            lobbyPanel.fzlokyCheck:Enable()
        end
    end
    if lobbyPanel.saudiMasterCheck then
        lobbyPanel.saudiMasterCheck:SetShown(hostInLobby)
        lobbyPanel.saudiMasterCheck:SetChecked(masterOn)
    end
    -- Swap buttons only visible to the host while in lobby phase
    local canSwap = S.s.isHost and S.s.phase == K.PHASE_LOBBY
    if lobbyPanel.swapBtns then
        for _, sw in pairs(lobbyPanel.swapBtns) do
            sw:SetShown(canSwap)
        end
    end
    local canJoin = S.s.pendingHost and not S.s.isHost
    for _, info in pairs(S.s.seats) do
        if info and info.name == S.s.localName then canJoin = false end
    end
    joinBtn:SetShown(canJoin)
    -- Party-members sidebar. List the WoW party so the host knows who's
    -- around to invite, and surface each peer's WHEREDNGN version so
    -- mismatches are visible before anyone starts a game.
    if lobbyPanel.partyPanel and lobbyPanel.partyPanel.rows then
        local rows = lobbyPanel.partyPanel.rows
        local myVersion = K.GetAddonVersion()
        -- Helper: find which (if any) seat a name occupies. Match is on
        -- the short name because UnitName() returns no realm for same-
        -- realm party members.
        local function seatOf(short)
            for seat = 1, 4 do
                local info = S.s.seats[seat]
                if info and info.name then
                    local infoShort = info.name:match("^([^%-]+)") or info.name
                    if infoShort == short then return seat end
                end
            end
        end
        local members = {}
        if UnitExists("player") then
            local n = UnitName("player")
            members[#members + 1] = {
                name  = n,
                short = n,
                full  = S.s.localName or n,
                you   = true,
            }
        end
        for i = 1, 4 do
            local u = "party" .. i
            if UnitExists(u) then
                local n = UnitName(u)
                local realm = select(2, UnitName(u))
                members[#members + 1] = {
                    name  = n,
                    short = n,
                    full  = (realm and realm ~= "") and (n .. "-" .. realm) or n,
                }
            end
        end
        for i = 1, 5 do
            local m = members[i]
            if m then
                local seat = seatOf(m.short)
                local seatStr
                if seat then
                    seatStr = ("|cff66ff88seat %d|r"):format(seat)
                else
                    seatStr = "|cffaaaaaaavailable|r"
                end
                -- v2.2.0 (audit v1.6.1 MP-52 LOW): peerVersions is keyed
                -- by NORMALIZED sender (write side, Net.lua:_OnHost +
                -- _OnLobby) but was previously read by `m.full` which
                -- is the suffixed form. Cross-realm clients arrive as
                -- "Name-Realm" in m.full but were normalized to "Name"
                -- on write — read miss. Now read via NormalizeName(m.full)
                -- to match the write key.
                local verKey = (S.NormalizeName and S.NormalizeName(m.full))
                               or m.full
                local ver = S.s.peerVersions and S.s.peerVersions[verKey]
                local verStr
                if m.you then
                    verStr = ("|cff66ddff%s|r"):format(myVersion)
                elseif ver then
                    if ver == myVersion then
                        verStr = ("|cff66ff88%s|r"):format(ver)
                    else
                        verStr = ("|cffff5555%s|r"):format(ver)
                    end
                else
                    verStr = "|cff666666?|r"
                end
                local you = m.you and "*" or " "
                -- One-line layout: " name(*)  seat-or-available  ver"
                rows[i]:SetText(("|cffffd055%s%s|r %s %s"):format(
                    you, m.short, seatStr, verStr))
            else
                rows[i]:SetText("")
            end
        end
    end

    -- Team-name boxes: pre-fill from current state, host-only editable.
    if lobbyPanel.teamA and lobbyPanel.teamB and S.s.teamNames then
        if not lobbyPanel.teamA:HasFocus() then
            lobbyPanel.teamA:SetText(S.s.teamNames.A or "")
        end
        if not lobbyPanel.teamB:HasFocus() then
            lobbyPanel.teamB:SetText(S.s.teamNames.B or "")
        end
        local editable = S.s.isHost
        lobbyPanel.teamA:SetEnabled(editable)
        lobbyPanel.teamB:SetEnabled(editable)
        local color = editable and { 1, 1, 1, 1 } or { 0.6, 0.6, 0.6, 1 }
        lobbyPanel.teamA:SetTextColor(unpack(color))
        lobbyPanel.teamB:SetTextColor(unpack(color))
    end
end

-- ----------------------------------------------------------------------
-- Render: status / score / contract
-- ----------------------------------------------------------------------

local function statusFor(phase)
    if phase == K.PHASE_IDLE then return "Idle. /baloot host to start." end
    if phase == K.PHASE_LOBBY then return "Lobby — waiting for 4 players" end
    if phase == K.PHASE_DEAL1 then
        if S.IsMyTurn() then return "|cffffaa55Your turn to bid|r" end
        local seat = S.s.turn
        local nm = seat and S.s.seats[seat] and shortName(S.s.seats[seat].name) or "?"
        return ("Bidding (round 1) — %s to act"):format(nm)
    end
    if phase == K.PHASE_DEAL2BID then
        if S.IsMyTurn() then return "|cffffaa55Your turn to bid (round 2)|r" end
        local seat = S.s.turn
        local nm = seat and S.s.seats[seat] and shortName(S.s.seats[seat].name) or "?"
        return ("Bidding (round 2) — %s to act"):format(nm)
    end
    if phase == K.PHASE_PREEMPT then return "Pre-empt window — earlier seats may claim" end
    if phase == K.PHASE_DOUBLE then return "Defenders: Bel? (×2)" end
    if phase == K.PHASE_TRIPLE then return "Bidder: Triple? (×3)" end
    if phase == K.PHASE_FOUR then return "Defenders: Four? (×4)" end
    if phase == K.PHASE_GAHWA then return "Bidder: Gahwa? (match-win)" end
    if phase == K.PHASE_DEAL3 then return "Final 3 dealt — declare melds" end
    if phase == K.PHASE_PLAY then
        if S.IsMyTurn() then return "|cff55ff55Your turn|r" end
        local seat = S.s.turn
        local nm = seat and S.s.seats[seat] and shortName(S.s.seats[seat].name) or "?"
        return ("Playing — %s to act"):format(nm)
    end
    if phase == K.PHASE_SCORE then
        local d = S.s.lastRoundDelta or { A = 0, B = 0 }
        -- Audit fix: use custom team names where set, falling back to
        -- generic "A"/"B". Mirrors the round-end banner (commit ed9181e).
        local nm = (S.s.teamNames or { A = "A", B = "B" })
        local nA = (nm.A and nm.A ~= "") and nm.A or "A"
        local nB = (nm.B and nm.B ~= "") and nm.B or "B"
        return ("Round done: %s +%d, %s +%d")
                  :format(nA, d.A or 0, nB, d.B or 0)
    end
    if phase == K.PHASE_GAME_END then
        local nm = (S.s.teamNames or { A = "A", B = "B" })
        local team = S.s.winner
        local label = team and ((nm[team] and nm[team] ~= "" and nm[team])
                                  or ("Team " .. team)) or "?"
        return ("Game over — %s wins"):format(label)
    end
    return ""
end

-- Helper: short team label including the seated names of that team.
local function teamLabel(t)
    local custom = (S.s.teamNames and S.s.teamNames[t]) or ("Team " .. t)
    if not S.s.localSeat then return custom end
    local seats = (t == "A") and { 1, 3 } or { 2, 4 }
    local names = {}
    for _, sn in ipairs(seats) do
        local info = S.s.seats[sn]
        if info and info.name then
            names[#names + 1] = shortName(info.name)
        end
    end
    if #names == 0 then return custom end
    return ("%s (%s)"):format(custom, table.concat(names, "+"))
end

-- Show/hide the round-result banner. Host has the full result struct
-- in S.s.lastRoundResult and shows a multi-line breakdown; non-host
-- clients only have the deltas, so they get a compact one-liner.
-- Player-team-aware coloring for the round-end banner. Returns
-- |c<color>...|r-wrapped strings — `usVsThem` paints the local
-- player's team green and the opponents red. When localSeat is
-- unknown (spectator / pre-join state), falls back to the legacy
-- A=green, B=red so the banner still has visible structure.
local function teamColor(t)
    if not t then return "ffaaaaaa" end
    if S.s.localSeat then
        local myTeam = (S.s.localSeat == 1 or S.s.localSeat == 3) and "A" or "B"
        return (t == myTeam) and COL.txtUs or COL.txtThem
    end
    return (t == "A") and COL.txtUs or COL.txtThem
end

-- Wrap a label in the team color so the user reads who they are
-- vs who they aren't at a glance, instead of memorising A=green.
local function colorTeam(t, text)
    return ("|c%s%s|r"):format(teamColor(t), text or teamLabel(t))
end

-- "YA MRW7" — tease the losing team. Returned as a |c-wrapped red
-- snippet to append onto the banner title. `loser` is the team
-- letter ("A" or "B"). When loser is unknown (rare ties / structural
-- weirdness), returns empty string so the title degrades silently.
local function yaMrw7(loser)
    if not loser then return "" end
    return (" |cffff5544—  YA MRW7|r %s"):format(colorTeam(loser))
end

local function renderBanner()
    local banner = tablePanel and tablePanel.banner
    if not banner then return end

    -- v1.3.5 (dealer dice roll): at NEW-game start (round 1 transition
    -- from idle/round-0), S.ApplyStart arms s.dealerRollAt = now+3.5.
    -- Show a "DICE ROLL" banner during this window naming the rolled
    -- first dealer. Takes priority over phase-based content so the
    -- pick is visible before deal-phase animations kick in. The
    -- structural fix is in N.HostStartRound (`dealer = math.random(1,4)`
    -- replaces the previous hardcoded `dealer = 1` at game start);
    -- this banner is the per-client visual feedback.
    do
        local now = (GetTime and GetTime()) or 0
        if S.s.dealerRollAt and now < S.s.dealerRollAt then
            local seat = S.s.dealer
            local info = S.s.seats and seat and S.s.seats[seat]
            local nm = (info and info.name) and shortName(info.name)
                       or ("seat " .. tostring(seat))
            banner:Show()
            banner:SetBackdropBorderColor(unpack(COL.legalEdge))
            if banner.outcome then banner.outcome:SetText("") end
            banner.bidder:SetText("")
            banner.defender:SetText("")
            banner.modifiers:SetText("")
            banner.belote:SetText("")
            -- v1.4.4 (UI fix — user-reported): WoW's default font
            -- doesn't render the 🎲 emoji (U+1F3B2) — was showing as
            -- a missing-glyph box. Replace with plain text title.
            -- The bid card backdrop is now hidden during this window
            -- (see bid-card render block) so the banner stands clean.
            banner.title:SetText("|cffffd055-=  DICE ROLL  =-|r")
            banner.final:SetText(("First dealer: |cff66ddff%s|r"):format(nm))
            return
        end
    end

    -- Redeal announcement (all-pass both rounds → dealer rotates).
    -- Shown for ~3 seconds before the actual deal lands. Takes priority
    -- over any other banner state so the player can clearly see who
    -- the next dealer is.
    if S.s.redealing and S.s.redealing.nextDealer then
        local seat = S.s.redealing.nextDealer
        local info = S.s.seats and S.s.seats[seat]
        local nm = (info and info.name) and shortName(info.name) or ("seat " .. seat)
        banner:Show()
        banner:SetBackdropBorderColor(unpack(COL.legalEdge))
        if banner.outcome then banner.outcome:SetText("") end
        banner.bidder:SetText(""); banner.defender:SetText("")
        banner.modifiers:SetText("|cffaaaaaaShuffling…|r")
        banner.belote:SetText("")
        banner.title:SetText("|cffffd055All passed — redealing|r")
        banner.final:SetText(("Next dealer: |cff66ddff%s|r"):format(nm))
        return
    end

    if S.s.phase ~= K.PHASE_SCORE and S.s.phase ~= K.PHASE_GAME_END then
        banner:Hide(); return
    end

    -- Player-reported UI fix: WIN / LOST headline above the contract
    -- title. Computes the local player's team outcome per round end:
    --   sweep   → sweepTeam wins
    --   made    → bidderTeam wins
    --   failed  → oppTeam (defenders) wins
    --   takeBranch (Bel'd-tie inversion)  → bidderTeam wins
    -- Spectators (no localSeat) get an empty outcome line, falling
    -- back to the existing color-coded title for context.
    local function setOutcome(winningTeam)
        if not banner.outcome then return end
        if not winningTeam or not S.s.localSeat then
            banner.outcome:SetText(""); return
        end
        local myTeam = R.TeamOf(S.s.localSeat)
        if myTeam == winningTeam then
            banner.outcome:SetText("|cff66ff88WIN|r")
        else
            banner.outcome:SetText("|cffff5544LOST|r")
        end
    end
    if banner.outcome then banner.outcome:SetText("") end

    -- Hide subline elements by default; we re-show what's relevant.
    banner.bidder:SetText(""); banner.defender:SetText("")
    banner.modifiers:SetText(""); banner.belote:SetText("")
    banner.final:SetText("")

    if S.s.phase == K.PHASE_GAME_END then
        -- Match-end WIN/LOST headline (re-uses round-end outcome
        -- styling for consistency).
        setOutcome(S.s.winner)
        banner:Show()
        banner:SetBackdropBorderColor(unpack(COL.legalEdge))
        -- v1.7.0 (audit v1.6.1 SA-30): branch the title on local-team
        -- vs winner. Pre-fix, "8amt!! go play something else" was shown
        -- to BOTH winner and loser — Saudi banter has loser-targeted
        -- "غامت" (8amt — blowout, lost badly) and winner-targeted
        -- "علي بضو / يا بطل" (champion). Showing the loser line to
        -- the winner reads as condescending or confusing. Branch:
        -- winners get "WALLAH WIN!" banter; losers keep the 8amt
        -- tease (which IS the right register for Saudi loser banter).
        local localTeam = S.s.localSeat and R.TeamOf(S.s.localSeat) or nil
        local won = (localTeam and S.s.winner and localTeam == S.s.winner)
        if won then
            banner.title:SetText("|cffffd055ya batal — match win!|r")
        else
            banner.title:SetText("|cffffd0558amt!! go play something else|r")
        end
        -- Audit C30 fix: use teamLabel for custom team-name display.
        -- Previously showed "Team A wins" even when host had set custom
        -- names like "Champs" / "Rivals".
        local winLabel = S.s.winner and teamLabel(S.s.winner) or "?"
        banner.final:SetText(("%s wins  —  %d / %d"):format(
            winLabel, S.s.cumulative.A or 0, S.s.cumulative.B or 0))
        return
    end

    -- Takweesh result (caught-or-false-call) takes priority over the
    -- normal score breakdown, with the offending card + reason called
    -- out so the player learns WHY the call succeeded.
    -- SWA result banner: same priority position as Takweesh — but
    -- v0.11.2 user-reported UX: the SWA banner no longer REPLACES the
    -- normal score breakdown. Instead it overrides only the title
    -- (with an "SWA verified / SWA failed" prefix) and shows the same
    -- per-team breakdown rows the regular round-end banner shows.
    -- WIN/LOST is computed from the actual score delta (relative to
    -- local team), not from SWA validity — a valid claim can still
    -- coincide with a contract loss when the bidder team's trick
    -- points fall short of the make threshold.
    if S.s.swaResult then
        local sw = S.s.swaResult
        local r  = S.s.lastRoundResult
        local d  = S.s.lastRoundDelta or { A = 0, B = 0 }
        local cName = (sw.caller and S.s.seats[sw.caller]
                       and shortName(S.s.seats[sw.caller].name)) or "?"

        -- WIN/LOST relative to actual round outcome (score delta),
        -- NOT to SWA validity. Tied delta → no headline.
        local roundWinner = nil
        if (d.A or 0) > (d.B or 0) then roundWinner = "A"
        elseif (d.B or 0) > (d.A or 0) then roundWinner = "B"
        end
        setOutcome(roundWinner)

        banner:Show()
        -- v0.11.7 user feedback: render the caller's hand as a glyph
        -- string in the title so the cards stay visible after the
        -- 5-second pending window closes. Pre-v0.11.7 the cards were
        -- only visible during the pending banner; once the result
        -- resolved (PHASE_SCORE renderBanner SWA branch), the cards
        -- vanished — opaque for teammate-bot SWAs which the player
        -- previously saw as "verified" with no card display. Visible
        -- to ALL viewers regardless of caller team (per user spec:
        -- "you should be able to see the cards regardless").
        -- v0.11.11 SU-Ultra-03 fix: whitelist-validate rank+suit before
        -- rendering glyph. Pre-v0.11.11 any 2-char pair (e.g. "XY")
        -- passed through; downstream RankGlyph/SUIT_GLYPH fallbacks
        -- emitted visually-nonsense rows. Now invalid cards are
        -- silently skipped — display only canonical rank+suit.
        -- v0.11.14 SU2-08 cleanup: reuse K.RANK_INDEX / K.SUIT_INDEX
        -- as the whitelist source-of-truth instead of maintaining
        -- duplicate VALID_RANKS / VALID_SUITS tables here. Truthiness
        -- check works because the index tables map valid ranks/suits
        -- to non-zero integers (1-8 for ranks, 1-4 for suits) and
        -- omit invalid keys.
        local function renderCardGlyphs(enc)
            if not enc or #enc < 2 then return "" end
            local parts = {}
            for i = 1, #enc, 2 do
                local card = enc:sub(i, i + 1)
                if card and #card == 2 then
                    local rank = C.Rank(card)
                    local suit = C.Suit(card)
                    if K.RANK_INDEX[rank] and K.SUIT_INDEX[suit] then
                        local rankG = (C and C.RankGlyph) and C.RankGlyph(rank) or rank
                        local sGlyph = (K.SUIT_GLYPH and K.SUIT_GLYPH[suit]) or suit
                        -- Color red suits red, black suits white.
                        local col = (suit == "H" or suit == "D") and "|cffff5555" or "|cffeeeeee"
                        parts[#parts + 1] = ("%s%s%s|r"):format(col, rankG, sGlyph)
                    end
                end
            end
            return (#parts > 0) and ("  ·  " .. table.concat(parts, " ")) or ""
        end
        local cardSuffix = renderCardGlyphs(sw.encodedHand)

        if sw.valid then
            banner:SetBackdropBorderColor(0.30, 0.85, 0.45, 1)
            banner.title:SetText(
                ("|cffffd055SWA!|r %s claimed — |cff66ff88verified|r%s"):format(cName, cardSuffix))
        else
            banner:SetBackdropBorderColor(0.95, 0.30, 0.20, 1)
            banner.title:SetText(
                ("|cffff5544SWA failed|r — %s claimed wrongly%s"):format(cName, cardSuffix))
        end

        -- Show the regular per-team breakdown. v0.11.11 SU-Ultra-01
        -- fix: read sw.breakdown (populated by HostResolveSWA) since
        -- S.s.lastRoundResult is nilled before renderBanner runs.
        -- Non-host receivers (no breakdown) fall through to the
        -- single-line degraded view as before.
        local bd = sw.breakdown
        if bd and bd.bidderTeam and bd.teamPoints and bd.meldPoints then
            local bidT = bd.bidderTeam
            local oppT = (bidT == "A") and "B" or "A"
            banner.bidder:SetText(("%s: cards %d + melds %d"):format(
                teamLabel(bidT), bd.teamPoints[bidT] or 0, bd.meldPoints[bidT] or 0))
            banner.defender:SetText(("%s: cards %d + melds %d"):format(
                teamLabel(oppT), bd.teamPoints[oppT] or 0, bd.meldPoints[oppT] or 0))
            local typeStr = (S.s.contract and S.s.contract.type == K.BID_SUN)
                and "Sun" or "Hokm"
            local mods = { typeStr }
            -- v1.7.0 (audit v1.6.1 SA-20): Saudi rung names in player-
            -- visible chips. Internal *.doubled / *.tripled flags
            -- unchanged.
            if S.s.contract and S.s.contract.doubled then mods[#mods + 1] = "Bel x2" end
            if S.s.contract and S.s.contract.tripled then mods[#mods + 1] = "Bel x3" end
            if S.s.contract and S.s.contract.foured then mods[#mods + 1] = "Four" end
            if S.s.contract and S.s.contract.gahwa  then mods[#mods + 1] = "Gahwa (match-win)" end
            if bd.multiplier and bd.multiplier > 1 then
                mods[#mods + 1] = ("×%d"):format(bd.multiplier)
            end
            banner.modifiers:SetText("|cffaaaaaa" .. table.concat(mods, "  ·  ") .. "|r")
            if bd.belote then
                -- v1.7.0 (audit v1.6.1 SA-03): Belote glyph dynamic per
                -- trump suit. Pre-fix hardcoded ♥ regardless of contract
                -- trump — wrong on every non-hearts Hokm.
                local trumpGlyph = K.SUIT_GLYPH
                                   and S.s.contract
                                   and K.SUIT_GLYPH[S.s.contract.trump]
                                   or "♥"
                banner.belote:SetText(("Belote (K+Q %s): %s +20 raw"):format(
                    trumpGlyph, teamLabel(bd.belote)))
            end
        else
            -- Degraded (non-host receiver — no breakdown broadcast):
            -- keep the SWA explanation visible in the bidder slot.
            banner.bidder:SetText(sw.valid
                and "Claim verified — all remaining tricks awarded."
                or  "Penalty applied (full hand to opponents).")
        end

        banner.final:SetText(("%s +%d   %s +%d"):format(
            colorTeam("A", "A"), d.A or 0,
            colorTeam("B", "B"), d.B or 0))
        return
    end

    if S.s.takweeshResult then
        local tk = S.s.takweeshResult
        local d = S.s.lastRoundDelta or { A = 0, B = 0 }
        local cName = (tk.caller and S.s.seats[tk.caller]
                       and shortName(S.s.seats[tk.caller].name)) or "?"
        local callerTeam = tk.caller and R.TeamOf(tk.caller)
        local offenderTeam = tk.offender and R.TeamOf(tk.offender)
        banner:Show()
        if tk.caught then
            -- Takweesh caught → caller's team wins
            setOutcome(callerTeam)
            local oName = (tk.offender and S.s.seats[tk.offender]
                           and shortName(S.s.seats[tk.offender].name)) or "?"
            local rankG, glyph = "?", "?"
            if tk.card and #tk.card >= 2 then
                rankG = C.RankGlyph(C.Rank(tk.card)) or C.Rank(tk.card)
                glyph = K.SUIT_GLYPH[C.Suit(tk.card)] or C.Suit(tk.card)
            end
            banner:SetBackdropBorderColor(0.95, 0.30, 0.20, 1)
            banner.title:SetText(("|cffff5544TAKWEESH!|r %s caught %s%s"):format(
                cName, oName, yaMrw7(offenderTeam)))
            banner.bidder:SetText(("Played |cffffd055%s%s|r — %s"):format(
                rankG, glyph, tk.reason or "illegal"))
        else
            -- Takweesh false call → opp team wins (caller penalised)
            local callerOpp = callerTeam and ((callerTeam == "A") and "B" or "A") or nil
            setOutcome(callerOpp)
            banner:SetBackdropBorderColor(0.95, 0.30, 0.20, 1)
            banner.title:SetText(("|cffff5544TAKWEESH!|r %s called incorrectly%s"):format(
                cName, yaMrw7(callerTeam)))
            banner.bidder:SetText("No illegal play found — penalty applied.")
        end
        banner.final:SetText(("%s +%d   %s +%d"):format(
            colorTeam("A", "A"), d.A or 0,
            colorTeam("B", "B"), d.B or 0))
        return
    end

    local r = S.s.lastRoundResult
    local d = S.s.lastRoundDelta or { A = 0, B = 0 }

    if not r then
        -- Non-host: degraded view, just the delta. Loser inferred from
        -- the broadcast delta (lower delta = the team that took the
        -- penalty side of this round). Tied deltas (rare) get no tease.
        local nonHostLoser, nonHostWinner = nil, nil
        if (d.A or 0) > (d.B or 0) then
            nonHostLoser, nonHostWinner = "B", "A"
        elseif (d.B or 0) > (d.A or 0) then
            nonHostLoser, nonHostWinner = "A", "B"
        end
        setOutcome(nonHostWinner)
        banner:Show()
        banner:SetBackdropBorderColor(unpack(COL.woodEdge))
        banner.title:SetText("Round done" .. yaMrw7(nonHostLoser))
        banner.final:SetText(("%s +%d   %s +%d"):format(
            colorTeam("A", "A"), d.A or 0,
            colorTeam("B", "B"), d.B or 0))
        return
    end

    -- Host: full breakdown.
    local bidT = r.bidderTeam
    local oppT = (bidT == "A") and "B" or "A"

    -- 27th-audit fix (player feedback): the round-end title was
    -- ambiguous about WHO actually lost. Add a "YA MRW7" tease
    -- pointing at the losing team in red. AL-KABOOT loser = the
    -- team that didn't sweep; BALOOT loser = bidder team (contract
    -- failed); ALLY B3DO loser = defender team (contract made).
    if r.sweep then
        local sweepLoser = (r.sweep == "A") and "B" or "A"
        setOutcome(r.sweep)  -- sweeping team wins
        banner:SetBackdropBorderColor(1.0, 0.84, 0.30, 1)
        banner.title:SetText(("|cffffd055AL-KABOOT!|r %s sweeps%s"):format(
            teamLabel(r.sweep), yaMrw7(sweepLoser)))
    elseif not r.bidderMade then
        setOutcome(oppT)  -- contract failed → defenders win
        banner:SetBackdropBorderColor(0.95, 0.30, 0.20, 1)
        -- v2.0.0 (audit v1.6.1 SA-25 HIGH): "BALOOT!" is a Saudi
        -- success-only call (the K+Q-of-trump fanfare for a made
        -- contract). Pre-fix the addon used "BALOOT!" to herald a
        -- contract FAILURE — semantically inverted; reads as a bug
        -- to a Saudi player. Replaced with "TAH!" (طاح — "crashed,
        -- went down") which is the canonical Saudi loss-banter for
        -- a failed contract. Romanized only — no Arabic glyphs since
        -- WoW fonts can't render them (per CLAUDE.md ceiling).
        banner.title:SetText("|cffff5544TAH!|r contract failed" .. yaMrw7(bidT))
    else
        setOutcome(bidT)  -- contract made → bidder team wins
        banner:SetBackdropBorderColor(0.30, 0.85, 0.45, 1)
        banner.title:SetText("|cff66ff88ALLY B3DO|r" .. yaMrw7(oppT))
    end

    -- Per-team breakdown lines: cards + melds raw
    banner.bidder:SetText(("%s: cards %d + melds %d"):format(
        teamLabel(bidT), r.teamPoints[bidT] or 0, r.meldPoints[bidT] or 0))
    banner.defender:SetText(("%s: cards %d + melds %d"):format(
        teamLabel(oppT), r.teamPoints[oppT] or 0, r.meldPoints[oppT] or 0))

    -- Modifiers line: contract type + multiplier
    -- v1.7.0 (audit v1.6.1 SA-20): Saudi rung names. Mirrors block above.
    local typeStr = (S.s.contract and S.s.contract.type == K.BID_SUN) and "Sun" or "Hokm"
    local mods = { typeStr }
    if S.s.contract and S.s.contract.doubled then mods[#mods + 1] = "Bel x2" end
    if S.s.contract and S.s.contract.tripled then mods[#mods + 1] = "Bel x3" end
    if S.s.contract and S.s.contract.foured then mods[#mods + 1] = "Four" end
    if S.s.contract and S.s.contract.gahwa then mods[#mods + 1] = "Gahwa (match-win)" end
    if r.multiplier and r.multiplier > 1 then
        mods[#mods + 1] = ("×%d"):format(r.multiplier)
    end
    banner.modifiers:SetText("|cffaaaaaa" .. table.concat(mods, "  ·  ") .. "|r")

    -- Belote line (if applicable). v1.7.0 (audit v1.6.1 SA-03): glyph
    -- now reflects the actual trump suit, not a hardcoded heart.
    if r.belote then
        local trumpGlyph = K.SUIT_GLYPH
                           and S.s.contract
                           and K.SUIT_GLYPH[S.s.contract.trump]
                           or "♥"
        banner.belote:SetText(("Belote (K+Q %s): %s +20 raw"):format(
            trumpGlyph, teamLabel(r.belote)))
    end

    -- Final delta — color each team's number by us-vs-them so the
    -- player reads "my team +X" at a glance instead of decoding A/B.
    -- The labels themselves carry the same color, doubling the cue.
    banner.final:SetText(("%s +%d   %s +%d"):format(
        colorTeam("A", "A"), d.A or 0,
        colorTeam("B", "B"), d.B or 0))

    banner:Show()
end

-- Peek-button visibility: only meaningful when there's a previous
-- AKA banner: small toast above the trick area showing who called the
-- AKA signal and on which suit. Persists until the trick closes
-- (cleared in State.ApplyTrickEnd). Label uses Latin "AKA" because the
-- bundled WoW fonts can't render Arabic glyphs — the voice cue handles
-- the إكَهْ pronunciation.
-- SWA pending preview banner. Visible during the 5-sec auto-approve
-- window so opponents can inspect the claim, then either let the
-- timer auto-approve, press the always-visible TAKWEESH button to
-- counter, or use the Accept/Deny manual override. Hidden once the
-- request resolves (timer fires, takweesh fires, or accept/deny).
--
-- v0.5.4: also populates the card-face row inside the banner so the
-- player sees the actual cards being claimed (Saudi convention =
-- show your hand on SWA). Especially needed for bot-initiated SWA
-- where the player previously approved/auto-approved blind.
local function renderOvercallBanner()
    local b = tablePanel and tablePanel.overcallBanner
    if not b then return end
    if S.s.phase ~= K.PHASE_OVERCALL or not S.s.overcall then
        b:Hide(); b._lastRemain = nil; return
    end
    -- Body text and remain are kept fresh by the OnUpdate self-tick
    -- on the banner itself (3 Hz). The render-path show is only
    -- responsible for making the frame visible when phase enters
    -- PHASE_OVERCALL; the OnUpdate loop hides it on phase exit.
    b:Show()
end

-- v3.0.8: Takweesh REVIEW banner renderer. Per video #36 the caller's
-- hand is shown face-up to all seats during the 8-second review window,
-- with optional Approve/Reject buttons for the host in multi-human
-- games (the host acts as الجلسة arbiter when there's more than one
-- human at the table; in bot-only or single-human cases the timeout
-- auto-validates via the rule-engine's `p.illegal` scan).
local function renderTakweeshReviewBanner()
    local b = tablePanel and tablePanel.takweeshBanner
    if not b then return end
    local rv = S.s.takweeshReview
    if not rv or not rv.caller or S.s.phase ~= K.PHASE_TAKWEESH_REVIEW then
        b:Hide()
        if b.cardSlots then
            for _, slot in ipairs(b.cardSlots) do slot.frame:Hide() end
        end
        if b.approveBtn then b.approveBtn:Hide() end
        if b.rejectBtn then b.rejectBtn:Hide() end
        b._lastEnc = nil
        return
    end
    local info = S.s.seats and S.s.seats[rv.caller]
    local nm = (info and info.name) and shortName(info.name)
                or ("seat " .. rv.caller)
    -- Title: who called.
    b.title:SetText(("|cffff5544TAKWEESH|r — %s reveals proof"):format(nm))
    -- Body: alleged illegal play (or "no proof found").
    if rv.illegalSeat and rv.illegalCard then
        local infoOff = S.s.seats and S.s.seats[rv.illegalSeat]
        local nmOff = (infoOff and infoOff.name) and shortName(infoOff.name)
                       or ("seat " .. rv.illegalSeat)
        local r = (#(rv.illegalCard) >= 1) and C.Rank(rv.illegalCard) or "?"
        local s = (#(rv.illegalCard) >= 2) and C.Suit(rv.illegalCard) or "?"
        local glyph = K.SUIT_GLYPH[s] or s
        local rankG = C.RankGlyph(r) or r
        b.body:SetText(("alleging %s played %s%s — %s"):format(
            nmOff, rankG, glyph, rv.illegalReason or "illegal play"))
    else
        b.body:SetText("|cffaaaaaano scan-flagged illegal play|r")
    end
    -- Cards: caller's remaining hand (the "proof" reveal).
    if b.populateCards and b._lastEnc ~= rv.encodedHand then
        b._lastEnc = rv.encodedHand
        b:populateCards(rv.encodedHand)
    end
    -- Approve / Reject buttons: only when local seat is host AND there
    -- are >1 humans at the table AND the host is not the caller (the
    -- caller can't validate their own call). Per user spec: in single-
    -- human or bot-only games, no approval — just timeout auto-validate.
    local showHostButtons = false
    if S.s.isHost then
        local humanCount = 0
        for i = 1, 4 do
            local seatInfo = S.s.seats and S.s.seats[i]
            if seatInfo and not seatInfo.isBot then
                humanCount = humanCount + 1
            end
        end
        if humanCount > 1 and S.s.localSeat ~= rv.caller then
            showHostButtons = true
        end
    end
    if b.approveBtn then b.approveBtn:SetShown(showHostButtons) end
    if b.rejectBtn  then b.rejectBtn:SetShown(showHostButtons)  end
    b:Show()
end

local function renderSWABanner()
    local b = tablePanel and tablePanel.swaBanner
    if not b then return end
    local req = S.s.swaRequest
    if not req or not req.caller or S.s.phase ~= K.PHASE_PLAY then
        b:Hide()
        if b.cardSlots then
            for _, slot in ipairs(b.cardSlots) do slot.frame:Hide() end
        end
        b._lastEnc = nil
        return
    end
    local info = S.s.seats and S.s.seats[req.caller]
    local nm = (info and info.name) and shortName(info.name) or ("seat " .. req.caller)
    -- Countdown — graceful degradation if GetTime/ts missing.
    local windowSec = req.windowSec or K.SWA_TIMEOUT_SEC or 5
    local now = (GetTime and GetTime()) or 0
    local elapsed = (req.ts and now and (now - req.ts)) or 0
    local remain = math.max(0, math.ceil(windowSec - elapsed))
    -- Recolour title based on caller team vs us.
    local me = S.s.localSeat
    local cTeam = R.TeamOf(req.caller)
    local sameTeam = me and (R.TeamOf(me) == cTeam)
    local cardLine = ("%d card%s remaining"):format(
        req.handCount or 0, (req.handCount or 0) == 1 and "" or "s")
    if sameTeam then
        b.title:SetText(("|cffffd055SWA|r — %s claims the rest"):format(nm))
        b.body:SetText(("%s · auto-approve in %ds"):format(cardLine, remain))
    else
        b.title:SetText(("|cffff5544SWA from %s|r"):format(nm))
        b.body:SetText(("%s · %ds — Takweesh to counter"):format(cardLine, remain))
    end
    -- v0.5.4: populate card-face row from the encoded hand. Only
    -- redecode when the encoded payload changes (the OnUpdate self-
    -- tick uses the same _lastEnc guard).
    if b.populateCards and b._lastEnc ~= req.encodedHand then
        b._lastEnc = req.encodedHand
        b:populateCards(req.encodedHand)
    end
    b:Show()
end

local function renderAKABanner()
    local b = tablePanel and tablePanel.akaBanner
    if not b then return end
    local call = S.s.akaCalled
    if not call or not call.seat or not call.suit
       or S.s.phase ~= K.PHASE_PLAY then
        -- v2.1.0 (audit v1.6.1 UX-31 LOW): fade-out instead of snap-Hide.
        if B.UI and B.UI.FadeBanner then B.UI.FadeBanner(b, 0.25, true)
        else b:Hide() end
        return
    end
    local info = S.s.seats and S.s.seats[call.seat]
    local nm = (info and info.name) and shortName(info.name) or ("seat " .. call.seat)
    local glyph = K.SUIT_GLYPH[call.suit] or call.suit
    -- Recolour based on whether the caller is on our team.
    local me = S.s.localSeat
    local teamCol
    if me and R.TeamOf(call.seat) == R.TeamOf(me) then
        teamCol = COL.txtUs       -- partner / self call → green
    else
        teamCol = COL.txtThem     -- opponent call → red
    end
    b.text:SetText(("|c%sAKA|r %s — %s"):format(teamCol, glyph, nm))
    -- v2.1.0 UX-31: fade-in on first show.
    if B.UI and B.UI.FadeBanner then B.UI.FadeBanner(b, 0.25)
    else b:Show() end
end

-- trick to show, the local player hasn't peeked yet this hand, and
-- we're in the play phase (can't peek during bidding).
local function renderPeekButton()
    local btn = tablePanel and tablePanel.peekBtn
    if not btn then return end
    local can = S.s.phase == K.PHASE_PLAY
              and S.s.lastTrick and S.s.lastTrick.plays
              and #S.s.lastTrick.plays > 0
              and not S.s.peekedThisRound
    btn:SetShown(can)
end

-- The Pause toggle is host-only and meaningful only during the
-- "active" phases (bidding through play). Outside that range we hide
-- the button entirely. Label flips between II and ▶ to reflect state.
local function renderPauseControls()
    local btn = tablePanel and tablePanel.pauseBtn
    local overlay = tablePanel and tablePanel.pauseOverlay
    if not btn or not overlay then return end

    local activePhase =
        S.s.phase == K.PHASE_DEAL1 or S.s.phase == K.PHASE_DEAL2BID
        or S.s.phase == K.PHASE_PREEMPT
        or S.s.phase == K.PHASE_DOUBLE
        or S.s.phase == K.PHASE_TRIPLE or S.s.phase == K.PHASE_FOUR
        or S.s.phase == K.PHASE_GAHWA
        or S.s.phase == K.PHASE_DEAL3 or S.s.phase == K.PHASE_PLAY
    btn:SetShown(S.s.isHost and activePhase)
    btn:SetText(S.s.paused and ">" or "II")

    overlay:SetShown(S.s.paused and activePhase)
    if S.s.paused and overlay.sub then
        overlay.sub:SetText(S.s.isHost
            and "Click |cffffd055>|r to resume."
            or  "Waiting for host to resume.")
    end
end

-- v3.1.0 NASHRAH (نشرة) panel renderer. Top-left scoreboard showing
-- per-round deltas + cumulative totals.
--
-- v3.1.1 layout:
--   --- NASHRAH ---
--   R1: TeamA: 12  TeamB: 8     ┐
--   R2: TeamA: 24  TeamB: 18    │ ScrollFrame viewport
--   R3: ...                     │ (5 rows visible)
--   R4: ...                     │ Mouse-wheel to scroll
--   R5: ...                     ┘
--   TOTAL: TeamA: 56  TeamB: 84  ← anchored bottom of panel
--
-- The panel is hidden until at least one round has ended. Removed
-- the redundant "TeamA: X TeamB: Y / 152 pts" line that v3.1.0 had
-- (TOTAL row already shows the same team scores; target is fixed).
-- Auto-scrolls to bottom on each refresh so the latest round is
-- always visible.
local NASHRAH_VISIBLE_ROWS = 5
local NASHRAH_ROW_H = 12
local function renderNashrahPanel()
    local p = f and f.nashrahPanel
    if not p then return end
    local hist = S.s.roundHistory or {}
    if #hist == 0 then
        p:Hide()
        if p.rows then
            for _, row in ipairs(p.rows) do row:Hide() end
        end
        return
    end
    local nA = (S.s.teamNames and S.s.teamNames.A) or "Team A"
    local nB = (S.s.teamNames and S.s.teamNames.B) or "Team B"
    -- Per-round rows live in scrollChild (so mouse-wheel scroll works).
    -- Reuse existing FontStrings; create new ones as needed.
    p.rows = p.rows or {}
    for i, entry in ipairs(hist) do
        local row = p.rows[i]
        if not row then
            row = makeText(p.scrollChild, 10, "LEFT")
            p.rows[i] = row
        end
        row:ClearAllPoints()
        -- Inside scrollChild, rows stack from top.
        row:SetPoint("TOPLEFT", 0, -(i - 1) * NASHRAH_ROW_H)
        row:SetText(("|cffd9b56bR%d:|r %s: |cff66ff66%d|r  %s: |cffff6666%d|r"):format(
            i, nA, entry.A or 0, nB, entry.B or 0))
        row:Show()
    end
    -- Hide any leftover rows from a longer prior history.
    for i = #hist + 1, #p.rows do
        p.rows[i]:Hide()
    end
    -- Resize scrollChild to fit all rows; the ScrollFrame's
    -- VerticalScrollRange becomes (scrollChild.height - viewport.height)
    -- automatically, enabling scroll when #hist > NASHRAH_VISIBLE_ROWS.
    local childHeight = math.max(NASHRAH_VISIBLE_ROWS * NASHRAH_ROW_H,
                                 #hist * NASHRAH_ROW_H)
    p.scrollChild:SetHeight(childHeight)
    -- Auto-scroll to bottom so the latest round is always visible.
    -- For ≤5 rounds, scroll range is 0 and SetVerticalScroll(0) is no-op.
    if p.scrollFrame then
        local maxScroll = math.max(0,
            childHeight - (NASHRAH_VISIBLE_ROWS * NASHRAH_ROW_H))
        p.scrollFrame:SetVerticalScroll(maxScroll)
    end
    -- TOTAL row text. Position is fixed (anchored at panel build time
    -- below the scroll viewport).
    p.totalLine:SetText(("|cffffe066TOTAL:|r %s: |cff66ff66%d|r  %s: |cffff6666%d|r"):format(
        nA, S.s.cumulative.A or 0, nB, S.s.cumulative.B or 0))
    p:Show()
end

local function renderStatus()
    statusText:SetText(statusFor(S.s.phase))

    -- v3.1.0: bottom-left scoreText is now blank — score lives in
    -- the top-left NASHRAH panel under the TOTAL row. Pre-v3.1.0 this
    -- read "TeamA: X  TeamB: Y  /  N pts"; the data moved to the
    -- panel for unified scoreboard view. Empty string keeps the
    -- FontString allocated (referenced elsewhere) without rendering.
    scoreText:SetText("")

    -- contract
    if S.s.contract then
        local c = S.s.contract
        -- Contract type — gold for HOKM, white for SUN.
        local typeStr = (c.type == K.BID_SUN)
            and "|cffeeeeeeSUN|r"
            or  "|cffffd055HOKM|r"
        local trumpStr = ""
        if c.trump then
            local glyph = K.SUIT_GLYPH[c.trump] or c.trump
            -- Red for red-suit trumps, light grey for black.
            local col = (c.trump == "H" or c.trump == "D")
                and "|cffff5555" or "|cffeeeeee"
            trumpStr = (" %s%s|r"):format(col, glyph)
        end
        -- v1.7.0 (audit v1.6.1 SA-20): Saudi rung names in contract
        -- banner. Internal *.doubled / *.tripled flags unchanged.
        local mods = {}
        if c.doubled    then mods[#mods + 1] = "Bel x2"          end
        if c.tripled    then mods[#mods + 1] = "Bel x3"          end
        if c.foured     then mods[#mods + 1] = "Four (x4)"       end
        if c.gahwa      then mods[#mods + 1] = "Gahwa (match)"   end
        local modStr = #mods > 0
            and (" |cffff7755[" .. table.concat(mods, "+") .. "]|r")
            or ""
        local bidder = (c.bidder and S.s.seats[c.bidder]
                        and shortName(S.s.seats[c.bidder].name)) or "?"
        -- v2.1.0 (audit v1.6.1 SA-32 MED): drop "Contract:" Latin
        -- prefix. Visual context (HOKM ♠ by PlayerName at the top of
        -- the table) is self-explanatory; the prefix added cognitive
        -- load without new info. Generic "Contract:" was a placeholder
        -- from before the visual context was clear; v2.1.0 cleans it.
        contractText:SetText(("%s%s  by  |cff66ddff%s|r%s"):format(
            typeStr, trumpStr, bidder, modStr))
        if f.contractBg then f.contractBg:Show() end
    else
        contractText:SetText("")
        if f.contractBg then f.contractBg:Hide() end
    end

    -- round
    -- v2.3.0 (audit v1.6.1 SA-33 LOW): "Round %d" → "Round %d" with
    -- a soft grey tint and "·" separator from the score chip so the
    -- round counter reads as ancillary metadata, not a primary
    -- score line. Same data, less visual weight.
    roundText:SetText(S.s.roundNumber > 0
        and ("|cffaaaaaaRound %d|r"):format(S.s.roundNumber)
        or "")
end

-- ----------------------------------------------------------------------
-- Public API
-- ----------------------------------------------------------------------

function U.Refresh()
    if not f then return end
    if not f:IsShown() then return end
    -- Switch panels by phase
    local inLobby = (S.s.phase == K.PHASE_IDLE or S.s.phase == K.PHASE_LOBBY)
    lobbyPanel:SetShown(inLobby)
    tablePanel:SetShown(not inLobby)
    if inLobby then
        renderLobby()
    else
        renderSeats()
        renderCenter()
        -- 6th-audit fix: hide the hand row during SCORE / GAME_END.
        -- Cards are anchored to handRow which lives in the table
        -- frame's hierarchy and renders ABOVE the round-end banner
        -- (banner created earlier → lower sibling z-order). Players
        -- saw their cards bleeding over the score banner. Clearing
        -- the hand pool when the round ends is also correct
        -- semantically — the round is done, those plays are over.
        if S.s.phase == K.PHASE_SCORE or S.s.phase == K.PHASE_GAME_END then
            clearHand()
        else
            renderHand()
        end
        renderBanner()
        renderAKABanner()
        renderSWABanner()
        renderTakweeshReviewBanner()  -- v3.0.8
        renderOvercallBanner()
        renderPeekButton()
        renderPauseControls()
    end
    renderActions()
    renderStatus()
    renderNashrahPanel()  -- v3.1.0
end

-- AFK pre-warn pulse: flash the local-player bar's border between
-- alert-red and the normal gold a few times. Driven by Net.lua's local
-- warn timer when a turn / bel decision has 10s remaining. Uses a
-- ticker rather than a Blizzard AnimationGroup so the inner color
-- swap is trivially predictable.
-- 9th-audit fix: store the active pulse ticker so back-to-back calls
-- (or window hide while a pulse is mid-flight) can cancel the old one
-- before arming a new one. Without this, two overlapping animations
-- could fight over the localBar border color, AND a stale ticker
-- could keep poking a torn-down frame after U.Hide.
local _pulseTicker
function U.PulseTurn()
    if not tablePanel or not tablePanel.localBar then return end
    local lb = tablePanel.localBar
    if not lb.SetBackdropBorderColor then return end
    -- v2.2.0 (audit v1.6.1 UX-62 LOW): on cancel, force-restore the
    -- legal-edge gold. Pre-fix a back-to-back PulseTurn call canceled
    -- the prior ticker mid-pulse but left the border in whatever
    -- state the last tick painted (could be alert-red), then started
    -- a new ticker — visible flash of "stuck red border" before the
    -- new pulse cycle ran.
    if _pulseTicker then
        _pulseTicker:Cancel()
        _pulseTicker = nil
        lb:SetBackdropBorderColor(unpack(COL.legalEdge))
    end
    -- v3.0 (audit v1.6.1 UX-35 LOW): cadence pulled to K.UI_AFK_PULSE_*
    local ticks, every = K.UI_AFK_PULSE_TICKS or 8,
                         K.UI_AFK_PULSE_PERIOD or 0.18
    local i = 0
    local on = false
    _pulseTicker = C_Timer.NewTicker(every, function()
        i = i + 1
        on = not on
        if on then
            lb:SetBackdropBorderColor(1.0, 0.20, 0.20, 1)  -- red
        else
            lb:SetBackdropBorderColor(unpack(COL.legalEdge))
        end
        if i >= ticks then
            -- Final state: leave it on the legal-edge gold; the next
            -- Refresh re-derives the right color from S.s.turn anyway.
            lb:SetBackdropBorderColor(unpack(COL.legalEdge))
            _pulseTicker = nil
        end
    end, ticks)
end

function U.Show()
    local justBuilt = (f == nil)
    if not f then
        buildMain()
        buildLobby()
        buildTable()
    end
    -- v0.10.4 user-reported UI fix: on first launch with a non-default
    -- felt theme saved (e.g. WHEREDNGNDB.feltTheme = "midnight"), the
    -- cycle button label rendered correctly ("Felt: Midnight") but
    -- the backdrop tints rendered the CLASSIC GREEN values. Cause:
    -- `setBackdrop` reads `COL.feltDark`/`COL.feltLight` at frame-
    -- construction time. Although `applyThemeColors()` runs at module-
    -- load (line 211) and SHOULD have updated the COL globals before
    -- buildMain/Lobby/Table fire, an edge case in the load order left
    -- some frames captured against the pre-mutation COL defaults
    -- (the green hardcoded values at lines 143-145). Defensive fix:
    -- after the freshly-built frames exist, force-reapply the theme
    -- by re-invoking SetFeltTheme(active). That function's existing
    -- re-tint loop (lines ~3527-3557) walks every captured frame and
    -- writes the current COL values, guaranteeing the saved theme is
    -- visible regardless of how the construction-time read resolved.
    -- Idempotent — SetFeltTheme writes the same name back to
    -- WHEREDNGNDB.feltTheme; no behavioural change for users on the
    -- default green theme.
    if justBuilt and U.SetFeltTheme then
        U.SetFeltTheme(activeFeltThemeName())
    end
    -- restore saved position
    if WHEREDNGNDB and WHEREDNGNDB.framePos then
        local p, rp, x, y = unpack(WHEREDNGNDB.framePos)
        f:ClearAllPoints()
        f:SetPoint(p or "CENTER", UIParent, rp or "CENTER", x or 0, y or 0)
    end
    -- restore saved scale (defaults to 1.0; SetScale propagates to all
    -- child frames so the window grows/shrinks as a single unit).
    if WHEREDNGNDB and WHEREDNGNDB.scale then
        f:SetScale(WHEREDNGNDB.scale)
    end
    f:Show()
    U.Refresh()
end

function U.Hide()
    if f then f:Hide() end
end

function U.Toggle()
    if not f or not f:IsShown() then U.Show() else U.Hide() end
end

function U.IsShown()
    return f and f:IsShown()
end

-- Switch the active CARD STYLE (face / back art set). Persists in
-- WHEREDNGNDB.cardStyle, re-stamps COL.cardBack/cardBackEdge, and
-- rebinds the seat-side card-back textures + the on-table card faces
-- (via Refresh, which re-resolves cardTexturePath for every slot).
-- Independent of the felt theme — the user can mix and match.
function U.SetCardStyle(name)
    if not name or not CARD_STYLES[name] then return false end
    WHEREDNGNDB = WHEREDNGNDB or {}
    WHEREDNGNDB.cardStyle = name
    applyThemeColors()
    -- Audit fix: rebind BOTH the card-back texture path AND the solid
    -- backdrop tint of every tracked card-back stack frame. The
    -- previous version only updated the texture, leaving the
    -- pre-switch cardBack/cardBackEdge color visible at the frame
    -- edges (and as a fallback when the new texture hadn't loaded).
    local back, edge = COL.cardBack, COL.cardBackEdge
    local newPath = cardTexturePath(nil)
    for _, entry in ipairs(cardBackEntries) do
        if entry.tex   then entry.tex:SetTexture(newPath) end
        if entry.frame then
            if entry.frame.SetBackdropColor then
                entry.frame:SetBackdropColor(back[1], back[2], back[3], back[4])
            end
            if entry.frame.SetBackdropBorderColor then
                entry.frame:SetBackdropBorderColor(edge[1], edge[2], edge[3], edge[4])
            end
        end
    end
    -- Refresh redraws every face card via setCardSlot, which calls
    -- cardTexturePath again and picks up the new subdir automatically.
    if U.Refresh then U.Refresh() end
    -- Re-render the lobby preview strip (A/K/T sample) so a slash-
    -- command style switch keeps the on-screen preview in sync, not
    -- just an in-lobby button cycle. cardsBtnUpdate keeps the label
    -- ("Cards: <name>") aligned with the active style.
    if lobbyPanel and lobbyPanel.cardsPreviewRefresh then
        lobbyPanel.cardsPreviewRefresh()
    end
    if lobbyPanel and lobbyPanel.cardsBtnUpdate then
        lobbyPanel.cardsBtnUpdate()
    end
    return true
end

-- Switch the active FELT THEME (table felt texture + backdrop tints).
-- Persists in WHEREDNGNDB.feltTheme. Independent of the card style.
function U.SetFeltTheme(name)
    if not name or not FELT_THEMES[name] then return false end
    WHEREDNGNDB = WHEREDNGNDB or {}
    WHEREDNGNDB.feltTheme = name
    applyThemeColors()
    -- Rebind the felt texture (single instance on tablePanel.feltTex).
    if tablePanel and tablePanel.feltTex then
        tablePanel.feltTex:SetTexture(
            CARD_TEX_DIR .. feltThemeData().feltTexPath,
            "REPEAT", "REPEAT")
    end
    -- Center-pad solid backdrop tint follows the felt theme.
    if tablePanel and tablePanel.centerPad
       and tablePanel.centerPad.SetBackdropColor then
        local c = COL.centerPad
        tablePanel.centerPad:SetBackdropColor(c[1], c[2], c[3], c[4])
    end
    -- Audit fix: re-apply COL.feltDark / COL.feltLight to every other
    -- frame whose backdrop tint was captured at construction. Without
    -- this, switching felt while the window is open leaves stale
    -- tints on the seat badges, the localBar, the party panel, and
    -- the main frame's outer rim until the next /reload.
    local function reTintFL(frame)   -- felt-light frames
        if frame and frame.SetBackdropColor then
            local c = COL.feltLight
            frame:SetBackdropColor(c[1], c[2], c[3], c[4])
        end
    end
    local function reTintFD(frame)   -- felt-dark frames (main rim)
        if frame and frame.SetBackdropColor then
            local c = COL.feltDark
            frame:SetBackdropColor(c[1], c[2], c[3], c[4])
        end
    end
    if seatBadges then
        for _, b in pairs(seatBadges) do
            if type(b) == "table" then reTintFL(b.frame) end
        end
    end
    if tablePanel and tablePanel.localBar then reTintFL(tablePanel.localBar) end
    if lobbyPanel and lobbyPanel.partyPanel then reTintFL(lobbyPanel.partyPanel) end
    -- Re-audit V5 fix: also re-tint the 4 lobby seat-rows. They use
    -- setBackdrop's default bg (COL.feltDark) and were previously left
    -- with a stale tint when the user switched felt while the lobby
    -- panel was visible.
    if lobbyPanel and lobbyPanel.seatRows then
        for _, row in ipairs(lobbyPanel.seatRows) do reTintFD(row) end
    end
    -- Outer rim of the main frame uses the dark default from setBackdrop.
    -- Note: the turn-glow renderer in Refresh re-derives this from
    -- COL.feltDark every tick, so we don't strictly need to touch f
    -- here — but doing so makes the switch instantaneous.
    reTintFD(f)
    if U.Refresh then U.Refresh() end
    return true
end

-- Back-compat: legacy /baloot theme <name> set both axes together.
-- Map "classic" → cards classic + felt green; "burgundy" → both
-- burgundy. Otherwise, try to interpret `name` as either axis.
function U.SetTheme(name)
    if name == "classic" then
        local a = U.SetCardStyle("classic")
        local b = U.SetFeltTheme("green")
        return a and b
    elseif name == "burgundy" then
        local a = U.SetCardStyle("burgundy")
        local b = U.SetFeltTheme("burgundy")
        return a and b
    elseif CARD_STYLES[name] then
        return U.SetCardStyle(name)
    elseif FELT_THEMES[name] then
        return U.SetFeltTheme(name)
    end
    return false
end

local function styleListFrom(tbl)
    local out = {}
    for k, v in pairs(tbl) do out[#out + 1] = { id = k, name = v.name } end
    table.sort(out, function(a, b) return a.id < b.id end)
    return out
end

function U.GetCardStyles() return styleListFrom(CARD_STYLES) end
function U.GetFeltThemes() return styleListFrom(FELT_THEMES) end
function U.GetActiveCardStyle() return activeCardStyleName() end
function U.GetActiveFeltTheme() return activeFeltThemeName() end

-- Back-compat aliases for the lobby button + slash command that
-- existed before the split.
function U.GetThemes() return U.GetCardStyles() end
function U.GetActiveTheme() return activeCardStyleName() end
