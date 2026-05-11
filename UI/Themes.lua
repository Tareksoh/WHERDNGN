-- WHEREDNGN UI/Themes.lua
--
-- Card styles, felt themes, and the shared COL palette table.
-- Extracted from UI.lua in v3.2.0 cleanup batch 5A. UI.lua binds
-- locals from U.Theme near the top of the file so existing call
-- sites (COL.feltDark, cardTexturePath(...), etc.) keep working
-- unchanged. The .toc loads UI/Themes.lua immediately before
-- UI.lua so these symbols exist by the time UI.lua's locals are
-- resolved.
--
-- This module owns:
--   * CARD_STYLES, FELT_THEMES (the two independent theme axes)
--   * COL (the live palette table; theme-driven entries are
--     mutated in place by applyThemeColors())
--   * activeCardStyleName, activeFeltThemeName, cardStyleData,
--     feltThemeData (resolve the saved-variable name → table)
--   * applyThemeColors (stamps the active theme into COL)
--   * migrateLegacyTheme (one-shot legacy cardTheme upgrade)
--   * CARD_TEX_DIR + cardTexturePath (texture path resolver
--     that consumes cardStyleData().texSubdir)
--
-- The legacy-DB migration runs at file load, then applyThemeColors
-- stamps COL — identical timing to the pre-extraction code which
-- also ran both at UI.lua file-load time.

WHEREDNGN = WHEREDNGN or {}
local B = WHEREDNGN
B.UI = B.UI or {}
local U = B.UI
local C = B.Cards

local Theme = U.Theme or {}
U.Theme = Theme

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
    classic_v2 = {
        name         = "Classic v2",       -- htdebeer SVG-cards (LGPL)
        texSubdir    = "classic_v2\\",     -- cards/classic_v2/<card>.tga
        cardBack     = { 0.06, 0.06, 0.08, 1.00 },   -- charcoal back body
        cardBackEdge = { 0.50, 0.50, 0.55, 1.00 },   -- silver edge
    },
    burgundy = {
        name         = "4 Colors",         -- v1.0.6: user-renamed from
                                            -- "Burgundy" display label.
                                            -- Internal key + texSubdir
                                            -- preserved so existing
                                            -- WHEREDNGNDB.cardStyle =
                                            -- "burgundy" entries keep
                                            -- working without migration.
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
        name         = "Ba8ala SET",       -- v1.0.6: replaced Royal Noir
                                            -- assets with xCards (BSD-2)
                                            -- via tools/convert_xcards_
                                            -- to_baqala.py. Internal key
                                            -- + texSubdir kept so existing
                                            -- WHEREDNGNDB.cardStyle =
                                            -- "royal_noir" entries keep
                                            -- working. back.tga preserved
                                            -- from the original Royal
                                            -- Noir deck (charcoal/gold
                                            -- aesthetic still good).
        texSubdir    = "royal_noir\\",     -- cards/royal_noir/<card>.tga
        cardBack     = { 0.10, 0.09, 0.12, 1.00 },   -- charcoal back body
        cardBackEdge = { 0.55, 0.43, 0.18, 1.00 },   -- warm gold edge
    },
    wow = {
        name         = "WoW",              -- "Battle of Heroes" PNG deck
        texSubdir    = "wow\\",            -- cards/wow/<card>.tga
        cardBack     = { 0.06, 0.05, 0.11, 1.00 },   -- charcoal violet body
        cardBackEdge = { 0.86, 0.70, 0.39, 1.00 },   -- warm gold edge
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
    -- v2.1.0 (audit v1.6.1 UX-42 LOW): illegal-card edge tint shifted
    -- to a distinct orange so it doesn't blur into the deep-red
    -- Takweesh-warning border (which uses a similar dark-red).
    -- Orange reads as "warning, not error" — accurate semantics
    -- since Saudi Takweesh ALLOWS illegal plays (you just risk getting
    -- caught).
    badEdge    = { 0.85, 0.45, 0.20, 1.00 },     -- warning-orange
    legalEdge  = { 0.95, 0.78, 0.30, 1.00 },     -- gold (card edge "this is legal")
    -- v2.1.0 (audit v1.6.1 UX-30 MED): turnGlow tint shifted from
    -- gold-on-gold (visual mush against legalEdge cards) to a soft
    -- cyan-ish cool tint. Cool color signals "active seat" without
    -- competing with the warm legal-edge gold of playable cards.
    activeGlow = { 0.45, 0.75, 1.00, 0.22 },     -- soft cyan
    txtCream   = "ffe8dec0",
    txtGold    = "ffffd055",
    txtSoft    = "ff8da095",
    -- v2.2.0 (audit v1.6.1 UX-60 MED): colorblind-aware team palette.
    -- Pre-fix txtUs (mid-saturation green) and txtThem (mid-saturation
    -- red) had similar luminance — undistinguishable to deuteranopia /
    -- protanopia users (combined ~10% of male players). Shifted txtUs
    -- to a brighter mint and txtThem to a desaturated coral so the
    -- LUMINANCE differs (mint ≈0.85, coral ≈0.65) — distinguishable
    -- by brightness even when hue is lost. Hue palette preserved for
    -- non-colorblind users.
    txtUs      = "ff80ffaa",   -- mint (high-luminance)
    txtThem    = "ffe09080",   -- coral (mid-luminance)
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

-- Export the shared theme surface. UI.lua binds these to file-locals
-- near the top so existing call sites resolve unchanged.
Theme.CARD_TEX_DIR        = CARD_TEX_DIR
Theme.COL                 = COL
Theme.CARD_STYLES         = CARD_STYLES
Theme.FELT_THEMES         = FELT_THEMES
Theme.ActiveCardStyleName = activeCardStyleName
Theme.ActiveFeltThemeName = activeFeltThemeName
Theme.CardStyleData       = cardStyleData
Theme.FeltThemeData       = feltThemeData
Theme.ApplyThemeColors    = applyThemeColors
Theme.CardTexturePath     = cardTexturePath
