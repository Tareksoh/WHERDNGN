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

-- Palette ---------------------------------------------------------------
-- Universal online-WHEREDNGN aesthetic: green felt table, dark wood trim,
-- cream card faces with classic red/black French-deck suit colors,
-- gold active-turn accents.
--
-- Themes ---------------------------------------------------------------
-- Two independent axes the user can mix and match:
--   CARD_STYLES — face / back art and the back-tint colors. Selected
--                 via WHEREDNGNDB.cardStyle and /baloot cards <name>.
--                 texSubdir is prefixed onto cardTexturePath() so
--                 cards/<subdir>/<card>.tga resolves to the active set.
--   FELT_THEMES — table felt texture and the surrounding backdrop
--                 color tints. Selected via WHEREDNGNDB.feltTheme and
--                 /baloot felt <name>. feltTexPath is prefixed onto
--                 the texture lookup for cards/<path>.tga (no .tga ext).
--
-- The active values from both are stamped into COL (mutated in place)
-- so existing reads of COL.feltDark etc. pick up the new values
-- without touching individual call sites.
local CARD_STYLES = {
    classic = {
        name         = "Classic",          -- hayeah Vector Playing Cards
        texSubdir    = "",                 -- cards/<card>.tga
        cardBack     = { 0.10, 0.24, 0.50, 1.00 },
        cardBackEdge = { 0.04, 0.10, 0.22, 1.00 },
    },
    burgundy = {
        name         = "Burgundy",         -- SVGCards Accessible/Horizontal
        texSubdir    = "burgundy\\",       -- cards/burgundy/<card>.tga
        cardBack     = { 0.42, 0.10, 0.16, 1.00 },
        cardBackEdge = { 0.20, 0.04, 0.08, 1.00 },
    },
    tattoo = {
        name         = "Tattoo",           -- old-school tattoo SVG deck
        texSubdir    = "tattoo\\",         -- cards/tattoo/<card>.tga
        cardBack     = { 0.55, 0.16, 0.16, 1.00 },   -- burgundy back border
        cardBackEdge = { 0.30, 0.06, 0.06, 1.00 },
    },
    royal_noir = {
        name         = "Royal Noir",       -- gold-on-charcoal SVG deck
        texSubdir    = "royal_noir\\",     -- cards/royal_noir/<card>.tga
        cardBack     = { 0.10, 0.09, 0.12, 1.00 },   -- charcoal back body
        cardBackEdge = { 0.55, 0.43, 0.18, 1.00 },   -- warm gold edge
    },
}

local FELT_THEMES = {
    green = {
        name         = "Classic Green",
        feltDark     = { 0.05, 0.20, 0.11, 0.97 },
        feltLight    = { 0.08, 0.28, 0.16, 0.95 },
        centerPad    = { 0.04, 0.16, 0.09, 0.95 },
        feltTexPath  = "felt",             -- cards/felt.tga
    },
    burgundy = {
        name         = "Burgundy",
        feltDark     = { 0.20, 0.05, 0.09, 0.97 },
        feltLight    = { 0.30, 0.08, 0.13, 0.95 },
        centerPad    = { 0.18, 0.04, 0.07, 0.95 },
        feltTexPath  = "burgundy\\felt",   -- cards/burgundy/felt.tga
    },
    vintage = {
        name         = "Vintage Leather",
        feltDark     = { 0.16, 0.10, 0.06, 0.97 },
        feltLight    = { 0.24, 0.16, 0.10, 0.95 },
        centerPad    = { 0.14, 0.08, 0.05, 0.95 },
        feltTexPath  = "felt_vintage",     -- cards/felt_vintage.tga
    },
    midnight = {
        name         = "Midnight",
        feltDark     = { 0.04, 0.04, 0.06, 0.97 },
        feltLight    = { 0.08, 0.08, 0.12, 0.95 },
        centerPad    = { 0.03, 0.03, 0.05, 0.95 },
        feltTexPath  = "felt_midnight",    -- cards/felt_midnight.tga
    },
}
B._cardStyles = CARD_STYLES   -- expose for lobby UI option list
B._feltThemes = FELT_THEMES

local COL = {
    -- Theme-driven (overwritten by applyThemeColors).
    feltDark   = { 0.05, 0.20, 0.11, 0.97 },
    feltLight  = { 0.08, 0.28, 0.16, 0.95 },
    centerPad  = { 0.04, 0.16, 0.09, 0.95 },
    cardBack   = { 0.10, 0.24, 0.50, 1.00 },
    cardBackEdge = { 0.04, 0.10, 0.22, 1.00 },
    -- Theme-independent.
    woodEdge   = { 0.34, 0.22, 0.12, 1.00 },
    cardFace   = { 0.96, 0.94, 0.86, 1.00 },
    cardEdge   = { 0.18, 0.13, 0.08, 1.00 },
    badEdge    = { 0.55, 0.20, 0.20, 1.00 },
    legalEdge  = { 0.95, 0.78, 0.30, 1.00 },     -- gold
    activeGlow = { 1.00, 0.84, 0.30, 0.22 },     -- gold tint
    txtCream   = "ffe8dec0",
    txtGold    = "ffffd055",
    txtSoft    = "ff8da095",
    txtUs      = "ff66ff88",
    txtThem    = "ffff7777",
}

-- Migrate the legacy single-axis WHEREDNGNDB.cardTheme to the split
-- cardStyle + feltTheme pair. Run before any other theme code reads
-- the saved variables so first-load post-upgrade still maps to the
-- user's previous choice.
local function migrateLegacyTheme()
    if not WHEREDNGNDB then return end
    if WHEREDNGNDB.cardStyle and WHEREDNGNDB.feltTheme then return end
    local legacy = WHEREDNGNDB.cardTheme
    -- Audit fix: only migrate when legacy is non-nil. Fresh installs
    -- (no prior cardTheme) should fall through to the runtime defaults
    -- in activeCardStyleName/activeFeltThemeName so future default
    -- changes still reach those users.
    if legacy == nil then return end
    if legacy == "burgundy" then
        WHEREDNGNDB.cardStyle = WHEREDNGNDB.cardStyle or "burgundy"
        WHEREDNGNDB.feltTheme = WHEREDNGNDB.feltTheme or "burgundy"
    elseif legacy == "classic" then
        WHEREDNGNDB.cardStyle = WHEREDNGNDB.cardStyle or "classic"
        WHEREDNGNDB.feltTheme = WHEREDNGNDB.feltTheme or "green"
    end
end
migrateLegacyTheme()

local function activeCardStyleName()
    local s = WHEREDNGNDB and WHEREDNGNDB.cardStyle
    if s and CARD_STYLES[s] then return s end
    return "classic"
end

local function activeFeltThemeName()
    local s = WHEREDNGNDB and WHEREDNGNDB.feltTheme
    if s and FELT_THEMES[s] then return s end
    return "green"
end

local function cardStyleData() return CARD_STYLES[activeCardStyleName()] end
local function feltThemeData() return FELT_THEMES[activeFeltThemeName()] end

local function applyThemeColors()
    local cs = cardStyleData()
    local ft = feltThemeData()
    COL.feltDark     = ft.feltDark
    COL.feltLight    = ft.feltLight
    COL.centerPad    = ft.centerPad
    COL.cardBack     = cs.cardBack
    COL.cardBackEdge = cs.cardBackEdge
end

-- Stamp the saved theme's colors into COL before any frame is built.
applyThemeColors()

-- Map a position label (relative to local player) to absolute seat.
local function seatAtPos(pos)
    local me = S.s.localSeat
    if not me then return nil end
    if pos == "bottom" then return me end
    if pos == "top"    then return R.Partner(me) end
    if pos == "right"  then return R.NextSeat(me) end
    if pos == "left"   then return R.Partner(R.NextSeat(me)) end
end

local function posOfSeat(seat)
    local me = S.s.localSeat
    if not me or not seat then return nil end
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

-- Path to the bundled card-face TGAs (Vector Playing Cards art,
-- 128x192 RGBA). Cards in cards/<rank><suit>.tga, plus back.tga.
-- WoW's texture loader takes a path WITHOUT the file extension.
local CARD_TEX_DIR = "Interface\\AddOns\\WHEREDNGN\\cards\\"

-- Returns the texture path for a card id ("AS", "9D", etc) or for the
-- card back if `card` is nil. Returns nil if the card id is unparseable.
-- Honors the active CARD STYLE via cardStyleData().texSubdir so a
-- card's path becomes cards/<subdir>/<card> when a non-default style
-- is active. (The felt theme is independent and doesn't affect card
-- paths.)
local function cardTexturePath(card)
    local sub = cardStyleData().texSubdir
    if not card then return CARD_TEX_DIR .. sub .. "back" end
    if not C.IsValid or not C.IsValid(card) then return nil end
    return CARD_TEX_DIR .. sub .. card
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
    title:SetText("|cff66ddffWHEREDNGN|r")

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
    muteBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("WHEREDNGN sound", 1, 1, 1)
        GameTooltip:AddLine("Toggle card play / chime / fanfare cues.",
                            0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)
    muteBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

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
            if B._lobbyTicker then
                B._lobbyTicker:Cancel()
                B._lobbyTicker = nil
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
    resetBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("Reset WHEREDNGN", 1, 1, 1)
        GameTooltip:AddLine("Same as |cffaaaaaa/baloot reset|r — clears the game"
            .. " state and returns to idle.", 0.85, 0.85, 0.85, true)
        GameTooltip:Show()
    end)
    resetBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
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

    local hostNewBtn = makeButton(lobbyPanel, "Host Game", 120, 26)
    hostNewBtn:SetPoint("BOTTOM", 0, 12)
    hostNewBtn:SetScript("OnClick", function()
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
    lobbyPanel.advancedCheck = makeBotDifficultyCheck(
        "Advanced", 78, true,
        function() return WHEREDNGNDB and WHEREDNGNDB.advancedBots end,
        function(v) WHEREDNGNDB = WHEREDNGNDB or {}; WHEREDNGNDB.advancedBots = v end,
        "Bots use human-style heuristics: partner-bid reads, "
            .. "AKA self-call, position-aware play, score-position "
            .. "threshold modifiers. Host only — affects bots in "
            .. "this game.")
    lobbyPanel.m3lmCheck = makeBotDifficultyCheck(
        "M3lm", 56, true,
        function() return WHEREDNGNDB and WHEREDNGNDB.m3lmBots end,
        function(v) WHEREDNGNDB = WHEREDNGNDB or {}; WHEREDNGNDB.m3lmBots = v end,
        "Master tier (pro level). Layers on top of Advanced: "
            .. "tracks each opponent and partner's play style across "
            .. "the game (trump aggression, Bel frequency), uses "
            .. "match-point urgency for finer score-position calls, "
            .. "and ramps escalations faster when partner has already "
            .. "Beled / Tripled.")
    lobbyPanel.fzlokyCheck = makeBotDifficultyCheck(
        "Fzloky", 34, true,
        function() return WHEREDNGNDB and WHEREDNGNDB.fzlokyBots end,
        function(v) WHEREDNGNDB = WHEREDNGNDB or {}; WHEREDNGNDB.fzlokyBots = v end,
        "Signal-aware tier on top of M3lm. Reads partner's first "
            .. "off-suit discard as a high/low suit-preference "
            .. "signal: a high discard (A/T/K) means \"lead this\", "
            .. "a low discard (7/8) means \"avoid this\". Bot biases "
            .. "lead choice accordingly.")
    lobbyPanel.saudiMasterCheck = makeBotDifficultyCheck(
        "Saudi Master", 12, true,
        function() return WHEREDNGNDB and WHEREDNGNDB.saudiMasterBots end,
        function(v) WHEREDNGNDB = WHEREDNGNDB or {}; WHEREDNGNDB.saudiMasterBots = v end,
        "Top tier (ISMCTS-flavoured). At each play decision, the "
            .. "bot samples 30 plausible opponent hands consistent "
            .. "with bidding history + observed plays + voids, then "
            .. "for each candidate card simulates the rest of the "
            .. "round across all worlds. Picks the card with the "
            .. "best aggregate outcome. ~150 ms per move.")

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

    local cardsBtn, cardsRefresh = makeCycleBtn(
        "Cards", 78,
        U.GetActiveCardStyle, U.GetCardStyles, U.SetCardStyle,
        "Card face / back art set. Independent of the felt — mix a "
            .. "burgundy deck with a green felt if you like. "
            .. "Persists in saved variables.")

    local feltBtn, feltRefresh = makeCycleBtn(
        "Felt", 56,
        U.GetActiveFeltTheme, U.GetFeltThemes, U.SetFeltTheme,
        "Table felt texture + the backdrop colors around it. "
            .. "Independent of the card style. Persists in saved "
            .. "variables.")

    lobbyPanel.cardsBtn        = cardsBtn
    lobbyPanel.cardsBtnUpdate  = cardsRefresh
    lobbyPanel.feltBtn         = feltBtn
    lobbyPanel.feltBtnUpdate   = feltRefresh

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
local function buildMeldStrip(parent)
    local strip = CreateFrame("Frame", nil, parent)
    strip:SetSize(140, 32)
    strip.slots = {}
    -- 22×30 cards on a 18-px stride gives a tight fan that fits below
    -- the seat badge's card-back row without overlapping it. The
    -- rank pip in the corner of each TGA stays clearly visible at
    -- this size.
    local W, H, STRIDE = 22, 30, 18
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

    -- Meld card strip: face-up mini cards showing the actual cards in
    -- this seat's declared melds. Per Saudi rule the cards are laid
    -- on the table during trick 1 only, then rejoin the hand. The
    -- strip sits at the bottom of the badge over the meldText slot —
    -- once the strip becomes visible we hide the text label so the
    -- two don't overlap.
    local meldStrip = buildMeldStrip(b)
    meldStrip:SetPoint("BOTTOM", b, "BOTTOM", 0, 4)

    local dealerTx = makeText(b, 12, "LEFT")
    dealerTx:SetPoint("TOPLEFT", 6, -6)
    dealerTx:SetTextColor(1, 0.84, 0.30)

    local turnGlow = b:CreateTexture(nil, "OVERLAY")
    turnGlow:SetAllPoints()
    turnGlow:SetColorTexture(unpack(COL.activeGlow))
    turnGlow:Hide()

    return { frame = b, nameText = nameTx, backs = backs,
             countText = countTx, meldText = meldTx,
             meldStrip = meldStrip,
             dealerText = dealerTx, turnGlow = turnGlow,
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
    local peekBtn = makeButton(f, "?", 22, 22)
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
    local pauseBtn = makeButton(centerPad, "II", 22, 22)
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
    akaBanner.text = makeText(akaBanner, 13, "CENTER")
    akaBanner.text:SetPoint("CENTER", 0, 0)
    akaBanner.text:SetTextColor(0.40, 1.00, 0.55)
    tablePanel.akaBanner = akaBanner

    -- BALOOT! / contract result banner with full breakdown (shown
    -- during PHASE_SCORE / PHASE_GAME_END). Title at top, then per-team
    -- breakdown lines, multiplier, Belote, and final delta.
    local banner = CreateFrame("Frame", nil, centerPad, "BackdropTemplate")
    banner:SetSize(270, 170)
    banner:SetPoint("CENTER", 0, 0)
    setBackdrop(banner, true, { 0.04, 0.04, 0.05, 0.96 }, COL.legalEdge, 12, "solid")
    banner:Hide()
    banner.title = makeText(banner, 16, "CENTER")
    banner.title:SetPoint("TOP", 0, -10)
    banner.bidder = makeText(banner, 11, "CENTER")
    banner.bidder:SetPoint("TOP", 0, -36)
    banner.defender = makeText(banner, 11, "CENTER")
    banner.defender:SetPoint("TOP", 0, -54)
    banner.modifiers = makeText(banner, 11, "CENTER")
    banner.modifiers:SetPoint("TOP", 0, -76)
    banner.belote = makeText(banner, 11, "CENTER")
    banner.belote:SetPoint("TOP", 0, -94)
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
    end
    btn:SetScript("OnClick", function()
        if btn.armed then
            disarm()
            fire()
        else
            btn.armed = true
            btn:SetText(armedLabel)
            if btn.armedTk then btn.armedTk:Cancel() end
            btn.armedTk = C_Timer.NewTimer(CONFIRM_WINDOW_SEC, disarm)
        end
    end)
end

local function clearActions()
    for i = 1, actionUsed do
        local b = actionPool[i]
        if b then b:Hide(); b:SetScript("OnClick", nil) end
    end
    actionUsed = 0
end

local function addAction(label, onclick)
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
    b:Show()
    return b
end

local function addConfirmAction(label, armedLabel, fire)
    local b = addAction(label, nil)
    bindConfirm(b, label, armedLabel, fire)
    return b
end

local function renderActions()
    clearActions()
    if S.s.phase == K.PHASE_DEAL1 or S.s.phase == K.PHASE_DEAL2BID then
        if S.IsMyTurn() and S.s.turnKind == "bid" then
            -- Pass label: "Pass" in round 1, "wla" (ولا) in round 2 to
            -- match the Saudi-table verbal convention. The round-2
            -- pass is essentially "I have no preference / confirm
            -- the existing bid".
            local passLabel = (S.s.phase == K.PHASE_DEAL2BID) and "wla" or "Pass"
            addAction(passLabel, function() net().LocalBid(K.BID_PASS) end)
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
                    addAction("Hokm "..K.SUIT_GLYPH[flippedSuit], function()
                        net().LocalBid(K.BID_HOKM..":"..flippedSuit)
                    end)
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
                    addAction("Ashkal", function() net().LocalBid(K.BID_ASHKAL) end)
                end

                addAction("Sun", function() net().LocalBid(K.BID_SUN) end)

                -- Kawesh: 5-card hand of only 7/8/9 → annul & redeal.
                -- Available throughout round 1 to the qualifying player.
                if C.IsKaweshHand(S.s.hand) then
                    addAction("|cffff8800Kawesh|r", function() net().LocalKawesh() end)
                end
            else
                -- Round 2: 3 Hokm buttons (excluding the flipped suit) + Sun
                for _, suit in ipairs(K.SUITS) do
                    if suit ~= flippedSuit then
                        local s2 = suit
                        addAction("H "..K.SUIT_GLYPH[suit], function()
                            net().LocalBid(K.BID_HOKM..":"..s2)
                        end)
                    end
                end
                addAction("Sun", function() net().LocalBid(K.BID_SUN) end)
            end
        end
    elseif S.s.phase == K.PHASE_DOUBLE then
        local b = S.s.contract and S.s.contract.bidder
        local nextSeat = b and ((b % 4) + 1) or nil
        if nextSeat == S.s.localSeat then
            -- Bel (×2). Open/Closed (التربيع) choice: open lets the
            -- bidder counter with Triple; closed stops the chain.
            -- Sun has no Triple rung, so only the Bel button shows.
            local isSun = S.s.contract and S.s.contract.type == K.BID_SUN
            if isSun then
                addConfirmAction("Bel (x2)", "|cffff7755Confirm Bel?|r",
                    function() net().LocalDouble(false) end)
            else
                addConfirmAction("Bel & open", "|cffff7755Confirm Bel & open?|r",
                    function() net().LocalDouble(true) end)
                addConfirmAction("Bel & closed", "|cffff7755Confirm Bel & close?|r",
                    function() net().LocalDouble(false) end)
            end
            addAction("Skip", function() net().LocalSkipDouble() end)
        end
    elseif S.s.phase == K.PHASE_TRIPLE then
        -- v0.2.0: Triple is the BIDDER's response to Bel.
        local b = S.s.contract and S.s.contract.bidder
        if b == S.s.localSeat then
            addConfirmAction("Triple & open (x3)",
                "|cffff5555Confirm Triple & open?|r",
                function() net().LocalTriple(true) end)
            addConfirmAction("Triple & closed (x3)",
                "|cffff5555Confirm Triple & close?|r",
                function() net().LocalTriple(false) end)
            addAction("Skip", function() net().LocalSkipDouble() end)
        end
    elseif S.s.phase == K.PHASE_FOUR then
        -- v0.2.0: Four is the DEFENDER's response to Triple.
        local b = S.s.contract and S.s.contract.bidder
        local def = b and ((b % 4) + 1) or nil
        if def == S.s.localSeat then
            addConfirmAction("Four & open (x4)",
                "|cffff3333Confirm Four & open?|r",
                function() net().LocalFour(true) end)
            addConfirmAction("Four & closed (x4)",
                "|cffff3333Confirm Four & close?|r",
                function() net().LocalFour(false) end)
            addAction("Skip", function() net().LocalSkipDouble() end)
        end
    elseif S.s.phase == K.PHASE_GAHWA then
        -- v0.2.0: Gahwa is the BIDDER's terminal — caller's team WINS
        -- the entire match outright if the contract makes; loses if
        -- it fails. No open/closed (terminal).
        local b = S.s.contract and S.s.contract.bidder
        if b == S.s.localSeat then
            addConfirmAction("|cffffd055Gahwa (match-win)|r",
                "|cffff0000Confirm Gahwa? (match-win or match-loss)|r",
                function() net().LocalGahwa() end)
            addAction("Skip", function() net().LocalSkipDouble() end)
        end
    elseif S.s.phase == K.PHASE_PREEMPT then
        -- Triple-on-Ace pre-emption (الثالث): earlier seats may claim
        -- the Sun bid for themselves. "قبلك" = "before you" / "I'll take it".
        if S.s.preemptEligible and S.s.localSeat then
            local eligible = false
            for _, s2 in ipairs(S.s.preemptEligible) do
                if s2 == S.s.localSeat then eligible = true; break end
            end
            if eligible then
                addConfirmAction("|cff66ddffقبلك (Pre-empt)|r",
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
            addConfirmAction("|cffff5555TAKWEESH|r",
                "|cffff5555TAKWEESH? again to confirm|r",
                function() net().LocalTakweesh() end)
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
                    function() net().LocalSWA() end)
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
                    addAction("|cff66ff88Accept SWA|r",
                        function() net().LocalSWAResp(true) end)
                    addAction("|cffff5544Deny SWA|r",
                        function() net().LocalSWAResp(false) end)
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
                        function() net().LocalAKA(cand.suit) end)
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
            end)
        end
    elseif S.s.phase == K.PHASE_GAME_END then
        if S.s.isHost then
            addAction("New Game", function()
                S.Reset()
                S.SetLocalName(GetUnitName("player", true))
                U.Refresh()
            end)
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

        local isPlayable = (S.s.phase == K.PHASE_PLAY and S.IsMyTurn())
        if isPlayable then
            if legalSet[card] then
                -- Gold border + bright = the "safe" play
                b:SetBackdropBorderColor(unpack(COL.legalEdge))
            else
                -- Orange/red border = warning-only. Still clickable
                -- (Saudi Takweesh rule: illegal plays go through; you
                -- get caught if opponents call it). Keep full opacity
                -- so it doesn't look disabled.
                b:SetBackdropBorderColor(unpack(COL.badEdge))
            end
        else
            b:SetBackdropBorderColor(unpack(COL.cardEdge))
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

local function meldsDescForSeat(seat)
    -- Trick-1 announcement format: type + length + top rank + value.
    -- The SUIT is deliberately omitted — Saudi convention announces
    -- "Tartib of 3, top King" without naming the suit, since suits
    -- don't matter for meld comparison. The actual cards (and thus
    -- suit) are revealed only in trick 2 during the owner's turn.
    local team = R.TeamOf(seat)
    local list = S.s.meldsByTeam[team] or {}
    local mine = {}
    for _, m in ipairs(list) do
        if m.declaredBy == seat then
            local s
            if m.kind == "carre" then
                s = ("Carré %s"):format(C.RankGlyph(m.top))
            else
                s = ("Seq%d %s"):format(m.len or 3, C.RankGlyph(m.top))
            end
            mine[#mine + 1] = s .. (" (%d)"):format(m.value or 0)
        end
    end
    if #mine == 0 then return "" end
    return table.concat(mine, ", ")
end

-- Concatenate every card across every meld this seat has declared,
-- ordered by declaration order. Caller (renderSeats) feeds the result
-- into setMeldStripCards. Caps at 5 cards (the strip's slot count) so
-- a player declaring 2 melds of 3 cards each has the second meld
-- partially hidden — by Saudi rule that's fine, the comparison only
-- cares about the BEST meld each side declared.
local function meldCardsForSeat(seat)
    local team = R.TeamOf(seat)
    local list = S.s.meldsByTeam[team] or {}
    local out = {}
    for _, m in ipairs(list) do
        if m.declaredBy == seat and m.cards then
            for _, c in ipairs(m.cards) do
                out[#out + 1] = c
                if #out >= 5 then return out end
            end
        end
    end
    return out
end

-- Per Saudi rule the meld CARDS are only visible briefly in trick 2:
--   • Trick 1: announcement only — text label shows the kind, length
--     and top rank ("Seq3 K (20)"), no cards, no suit.
--   • Trick 2: when a declarer's turn starts, their actual cards are
--     revealed for 5 seconds (set via S.ApplyTurn -> meldHoldUntil),
--     then hidden permanently for the rest of the hand.
--   • Trick 3+: cards never visible. Text label also hidden — at this
--     point only the score the meld earned matters, shown in the
--     round-end banner.
local function meldStripVisibleFor(seat)
    if S.s.phase ~= K.PHASE_PLAY then return false end
    if not S.s.meldHoldUntil or not S.s.meldHoldUntil[seat] then
        return false
    end
    local now = (GetTime and GetTime()) or 0
    return now < S.s.meldHoldUntil[seat]
end

-- Trick-1 text-announcement window. Visible from the moment the
-- meld is declared (PHASE_DEAL3 onwards) through the end of trick 1
-- (when #s.tricks transitions from 0 to 1). After that the cards
-- take over (trick 2 reveal) and the text label hides.
local function meldTextVisible()
    if S.s.phase ~= K.PHASE_DEAL3 and S.s.phase ~= K.PHASE_PLAY then
        return false
    end
    return (#(S.s.tricks or {}) == 0)
end

local function renderSeats()
    if not S.s.localSeat then return end

    -- Top, left, right are seat badges (other players). Bottom is the
    -- local-player bar (no card-back row; the hand below shows everything).
    -- Team coloring: top = partner (Us, green), left/right = opponents
    -- (Them, red).
    for _, pos in ipairs({ "top", "left", "right" }) do
        local seat = seatAtPos(pos)
        local b = seatBadges[pos]
        if seat and b then
            local info = S.s.seats[seat]
            local nm = info and shortName(info.name) or "(empty)"
            local teamCol = (pos == "top") and COL.txtUs or COL.txtThem
            b.nameText:SetText("|c" .. teamCol .. nm .. "|r")
            local cnt = cardCountForSeat(seat)
            for i = 1, 8 do
                if i <= cnt then b.backs[i]:Show() else b.backs[i]:Hide() end
            end
            b.countText:SetText(("|c"..COL.txtSoft.."%d|r"):format(cnt))
            -- Meld display follows two independent windows:
            --   • text label: visible during trick 1 only (announcement)
            --   • card strip: visible only during the seat's 5-second
            --     hold in trick 2 (S.s.meldHoldUntil[seat])
            -- They never overlap.
            if meldStripVisibleFor(seat) then
                setMeldStripCards(b.meldStrip, meldCardsForSeat(seat), 1.0)
                b.meldText:SetText("")
            else
                if b.meldStrip then b.meldStrip:Hide() end
                if meldTextVisible() then
                    b.meldText:SetText(meldsDescForSeat(seat))
                else
                    b.meldText:SetText("")
                end
            end
            b.dealerText:SetText(seat == S.s.dealer and "D" or "")
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
            else
                b.turnGlow:Hide()
                b.frame:SetBackdropBorderColor(unpack(COL.woodEdge))
            end
        end
    end

    -- Local bar — fall back to S.s.localName if the seat record was
    -- somehow stripped of its name (e.g. an empty SendLobby payload).
    local lb = tablePanel.localBar
    local me = S.s.localSeat
    local meInfo = S.s.seats[me]
    local rawName = (meInfo and meInfo.name) or S.s.localName
    local nm = rawName and shortName(rawName) or "you"
    local prefix = me == S.s.dealer and "D " or ""
    lb.nameText:SetText(prefix .. "|c" .. COL.txtGold .. nm .. "|r")
    -- Same two-window split for the local player. Strip during the
    -- 5-sec trick-2 reveal; text label during trick 1 announcement.
    if meldStripVisibleFor(me) then
        setMeldStripCards(lb.meldStrip, meldCardsForSeat(me), 1.0)
        lb.meldText:SetText("")
    else
        if lb.meldStrip then lb.meldStrip:Hide() end
        if meldTextVisible() then
            lb.meldText:SetText(meldsDescForSeat(me))
        else
            lb.meldText:SetText("")
        end
    end
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
    if B.Sound and B.Sound.Cue then B.Sound.Cue(K.SND_CARD_SWISH) end

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
        if S.s.bidCard then
            local slot = centerCards.bid
            slot.frame:Show()
            setCardSlot(slot, S.s.bidCard)
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
    end
    hostStartBtn:SetShown(S.s.isHost and S.LobbyFull())
    -- Fill Bots only useful for host while in lobby with empty seats
    local hasEmpty = S.s.isHost and S.s.phase == K.PHASE_LOBBY and not S.LobbyFull()
    if lobbyPanel.fillBotsBtn then
        lobbyPanel.fillBotsBtn:SetShown(hasEmpty)
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
                local ver = S.s.peerVersions and S.s.peerVersions[m.full]
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
local function renderBanner()
    local banner = tablePanel and tablePanel.banner
    if not banner then return end

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

    -- Hide subline elements by default; we re-show what's relevant.
    banner.bidder:SetText(""); banner.defender:SetText("")
    banner.modifiers:SetText(""); banner.belote:SetText("")
    banner.final:SetText("")

    if S.s.phase == K.PHASE_GAME_END then
        banner:Show()
        banner:SetBackdropBorderColor(unpack(COL.legalEdge))
        banner.title:SetText(("|cffffd0558amt!! go play something else|r"))
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
    -- SWA result banner: same priority position as Takweesh — both
    -- replace the normal score breakdown with the claim's outcome.
    if S.s.swaResult then
        local sw = S.s.swaResult
        local d = S.s.lastRoundDelta or { A = 0, B = 0 }
        local cName = (sw.caller and S.s.seats[sw.caller]
                       and shortName(S.s.seats[sw.caller].name)) or "?"
        banner:Show()
        if sw.valid then
            banner:SetBackdropBorderColor(0.30, 0.85, 0.45, 1)
            banner.title:SetText(("|cffffd055SWA!|r %s claimed the rest"):format(cName))
            banner.bidder:SetText("Claim verified — all remaining tricks awarded.")
        else
            banner:SetBackdropBorderColor(0.95, 0.30, 0.20, 1)
            banner.title:SetText(("|cffff5544SWA failed|r — %s claimed wrongly"):format(cName))
            banner.bidder:SetText("Penalty applied (full hand to opponents).")
        end
        banner.final:SetText(("A +%d   B +%d"):format(d.A or 0, d.B or 0))
        return
    end

    if S.s.takweeshResult then
        local tk = S.s.takweeshResult
        local d = S.s.lastRoundDelta or { A = 0, B = 0 }
        local cName = (tk.caller and S.s.seats[tk.caller]
                       and shortName(S.s.seats[tk.caller].name)) or "?"
        banner:Show()
        if tk.caught then
            local oName = (tk.offender and S.s.seats[tk.offender]
                           and shortName(S.s.seats[tk.offender].name)) or "?"
            local rankG, glyph = "?", "?"
            if tk.card and #tk.card >= 2 then
                rankG = C.RankGlyph(C.Rank(tk.card)) or C.Rank(tk.card)
                glyph = K.SUIT_GLYPH[C.Suit(tk.card)] or C.Suit(tk.card)
            end
            banner:SetBackdropBorderColor(0.95, 0.30, 0.20, 1)
            banner.title:SetText(("|cffff5544TAKWEESH!|r %s caught %s"):format(cName, oName))
            banner.bidder:SetText(("Played |cffffd055%s%s|r — %s"):format(
                rankG, glyph, tk.reason or "illegal"))
        else
            banner:SetBackdropBorderColor(0.95, 0.30, 0.20, 1)
            banner.title:SetText(("|cffff5544TAKWEESH!|r %s called incorrectly"):format(cName))
            banner.bidder:SetText("No illegal play found — penalty applied.")
        end
        banner.final:SetText(("A +%d   B +%d"):format(d.A or 0, d.B or 0))
        return
    end

    local r = S.s.lastRoundResult
    local d = S.s.lastRoundDelta or { A = 0, B = 0 }

    if not r then
        -- Non-host: degraded view, just the delta.
        banner:Show()
        banner:SetBackdropBorderColor(unpack(COL.woodEdge))
        banner.title:SetText("Round done")
        banner.final:SetText(("A +%d   B +%d"):format(d.A or 0, d.B or 0))
        return
    end

    -- Host: full breakdown.
    local bidT = r.bidderTeam
    local oppT = (bidT == "A") and "B" or "A"

    -- Title
    if r.sweep then
        banner:SetBackdropBorderColor(1.0, 0.84, 0.30, 1)
        banner.title:SetText(("|cffffd055AL-KABOOT!|r %s sweeps"):format(teamLabel(r.sweep)))
    elseif not r.bidderMade then
        banner:SetBackdropBorderColor(0.95, 0.30, 0.20, 1)
        banner.title:SetText("|cffff5544BALOOT!|r contract failed")
    else
        banner:SetBackdropBorderColor(0.30, 0.85, 0.45, 1)
        banner.title:SetText("|cff66ff88ALLY B3DO|r")
    end

    -- Per-team breakdown lines: cards + melds raw
    banner.bidder:SetText(("%s: cards %d + melds %d"):format(
        teamLabel(bidT), r.teamPoints[bidT] or 0, r.meldPoints[bidT] or 0))
    banner.defender:SetText(("%s: cards %d + melds %d"):format(
        teamLabel(oppT), r.teamPoints[oppT] or 0, r.meldPoints[oppT] or 0))

    -- Modifiers line: contract type + multiplier
    local typeStr = (S.s.contract and S.s.contract.type == K.BID_SUN) and "Sun" or "Hokm"
    local mods = { typeStr }
    if S.s.contract and S.s.contract.doubled then mods[#mods + 1] = "Bel" end
    if S.s.contract and S.s.contract.tripled then mods[#mods + 1] = "Triple" end
    if S.s.contract and S.s.contract.foured then mods[#mods + 1] = "Four" end
    if S.s.contract and S.s.contract.gahwa then mods[#mods + 1] = "Gahwa (match-win)" end
    if r.multiplier and r.multiplier > 1 then
        mods[#mods + 1] = ("×%d"):format(r.multiplier)
    end
    banner.modifiers:SetText("|cffaaaaaa" .. table.concat(mods, "  ·  ") .. "|r")

    -- Belote line (if applicable)
    if r.belote then
        banner.belote:SetText(("Belote (K+Q ♥): %s +20 raw"):format(teamLabel(r.belote)))
    end

    -- Final delta
    banner.final:SetText(("|cff66ff88A +%d|r   |cffff7777B +%d|r"):format(
        d.A or 0, d.B or 0))

    banner:Show()
end

-- Peek-button visibility: only meaningful when there's a previous
-- AKA banner: small toast above the trick area showing who called the
-- AKA signal and on which suit. Persists until the trick closes
-- (cleared in State.ApplyTrickEnd). Label uses Latin "AKA" because the
-- bundled WoW fonts can't render Arabic glyphs — the voice cue handles
-- the إكَهْ pronunciation.
local function renderAKABanner()
    local b = tablePanel and tablePanel.akaBanner
    if not b then return end
    local call = S.s.akaCalled
    if not call or not call.seat or not call.suit
       or S.s.phase ~= K.PHASE_PLAY then
        b:Hide(); return
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
    b:Show()
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

local function renderStatus()
    statusText:SetText(statusFor(S.s.phase))

    -- score (uses host-customizable team names; falls back to "Team A"/"B")
    local nA = (S.s.teamNames and S.s.teamNames.A) or "Team A"
    local nB = (S.s.teamNames and S.s.teamNames.B) or "Team B"
    scoreText:SetText(("%s: |cff66ff66%d|r   %s: |cffff6666%d|r   /  %d"):format(
        nA, S.s.cumulative.A or 0, nB, S.s.cumulative.B or 0,
        S.s.target or 152))

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
        local mods = {}
        if c.doubled    then mods[#mods + 1] = "Bel (x2)"        end
        if c.tripled    then mods[#mods + 1] = "Triple (x3)"     end
        if c.foured     then mods[#mods + 1] = "Four (x4)"       end
        if c.gahwa      then mods[#mods + 1] = "Gahwa (match)"   end
        local modStr = #mods > 0
            and (" |cffff7755[" .. table.concat(mods, "+") .. "]|r")
            or ""
        local bidder = (c.bidder and S.s.seats[c.bidder]
                        and shortName(S.s.seats[c.bidder].name)) or "?"
        contractText:SetText(("|cffaaaaaaContract:|r %s%s  by  |cff66ddff%s|r%s"):format(
            typeStr, trumpStr, bidder, modStr))
        if f.contractBg then f.contractBg:Show() end
    else
        contractText:SetText("")
        if f.contractBg then f.contractBg:Hide() end
    end

    -- round
    roundText:SetText(S.s.roundNumber > 0 and ("Round %d"):format(S.s.roundNumber) or "")
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
        renderHand()
        renderBanner()
        renderAKABanner()
        renderPeekButton()
        renderPauseControls()
    end
    renderActions()
    renderStatus()
end

-- AFK pre-warn pulse: flash the local-player bar's border between
-- alert-red and the normal gold a few times. Driven by Net.lua's local
-- warn timer when a turn / bel decision has 10s remaining. Uses a
-- ticker rather than a Blizzard AnimationGroup so the inner color
-- swap is trivially predictable.
function U.PulseTurn()
    if not tablePanel or not tablePanel.localBar then return end
    local lb = tablePanel.localBar
    if not lb.SetBackdropBorderColor then return end
    local ticks, every = 8, 0.18
    local i = 0
    local on = false
    C_Timer.NewTicker(every, function()
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
        end
    end, ticks)
end

function U.Show()
    if not f then
        buildMain()
        buildLobby()
        buildTable()
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
