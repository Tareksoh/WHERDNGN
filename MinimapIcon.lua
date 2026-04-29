-- Minimap button.
--
-- Pure self-contained implementation (no LibDBIcon dependency). The
-- button shows a spade-suit card glyph, drags around the minimap rim,
-- and toggles the main window on left-click.
--
-- Position is stored as a polar angle (degrees) in BalootDB.minimapAngle,
-- which the user can drag-relocate. Default is 200° (lower-right of
-- minimap, away from the default Blizzard buttons).

WHEREDNGN = WHEREDNGN or {}
local B = WHEREDNGN
B.MinimapIcon = B.MinimapIcon or {}
local M = B.MinimapIcon
local K = B.K

local DEFAULT_ANGLE = 200      -- degrees, 0 = right, 90 = top
local RADIUS        = 80       -- distance from minimap center

local btn

local function positionButton()
    if not btn or not Minimap then return end
    local angle = (WHEREDNGNDB and WHEREDNGNDB.minimapAngle) or DEFAULT_ANGLE
    local rad = math.rad(angle)
    local x = math.cos(rad) * RADIUS
    local y = math.sin(rad) * RADIUS
    btn:ClearAllPoints()
    btn:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

local function angleFromCursor()
    local mx, my = Minimap:GetCenter()
    local cx, cy = GetCursorPosition()
    local scale = Minimap:GetEffectiveScale()
    cx = cx / scale; cy = cy / scale
    return math.deg(math.atan2(cy - my, cx - mx))
end

local function onDragStart(self)
    self:LockHighlight()
    self:SetScript("OnUpdate", function()
        WHEREDNGNDB = WHEREDNGNDB or {}
        WHEREDNGNDB.minimapAngle = angleFromCursor()
        positionButton()
    end)
end

local function onDragStop(self)
    self:UnlockHighlight()
    self:SetScript("OnUpdate", nil)
end

local function onClick(self, mouseButton)
    if mouseButton == "RightButton" then
        -- Right-click: print quick status.
        local s = B.State and B.State.s or {}
        print(("|cff66ddffWHEREDNGN|r phase=%s round=%d  /baloot help"):format(
            tostring(s.phase), s.roundNumber or 0))
        return
    end
    if B.UI and B.UI.Toggle then B.UI.Toggle() end
end

local function onEnter(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine("|cff66ddffWHEREDNGN|r")
    GameTooltip:AddLine("Saudi Baloot card game", 0.9, 0.9, 0.7)
    GameTooltip:AddLine(" ", 1, 1, 1)
    GameTooltip:AddLine("Left-click: toggle window", 1, 1, 1)
    GameTooltip:AddLine("Right-click: status", 1, 1, 1)
    GameTooltip:AddLine("Drag: move around minimap", 1, 1, 1)
    GameTooltip:Show()
end

local function onLeave() GameTooltip:Hide() end

function M.Show()
    if btn then btn:Show(); return end
    if not Minimap then return end

    btn = CreateFrame("Button", "WHEREDNGNMinimapButton", Minimap)
    btn:SetSize(32, 32)
    btn:SetFrameStrata("MEDIUM")
    btn:SetFrameLevel(Minimap:GetFrameLevel() + 8)

    -- Round backdrop (matches Blizzard minimap button look).
    btn:SetNormalTexture("Interface\\Minimap\\UI-Minimap-Background")
    local nt = btn:GetNormalTexture()
    nt:SetVertexColor(0.05, 0.18, 0.10, 1)
    nt:SetTexCoord(0, 1, 0, 1)

    -- Border ring like the world-map / tracking buttons.
    local border = btn:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetSize(54, 54)
    border:SetPoint("TOPLEFT", btn, "TOPLEFT", -2, 2)

    -- Spade-card glyph centered in the icon.
    local glyph = btn:CreateFontString(nil, "OVERLAY")
    glyph:SetFont(K.CARD_FONT or "Fonts\\ARIALN.TTF", 18, "OUTLINE")
    glyph:SetPoint("CENTER", 0, 1)
    glyph:SetText("|cffe8dec0\226\153\160|r")  -- ♠ on cream

    -- Highlight on hover.
    btn:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    btn:RegisterForDrag("LeftButton")
    btn:SetMovable(true)
    btn:SetScript("OnDragStart", onDragStart)
    btn:SetScript("OnDragStop", onDragStop)
    btn:SetScript("OnClick", onClick)
    btn:SetScript("OnEnter", onEnter)
    btn:SetScript("OnLeave", onLeave)

    positionButton()
end

function M.Hide() if btn then btn:Hide() end end
function M.Refresh() positionButton() end
