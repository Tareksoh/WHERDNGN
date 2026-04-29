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

-- Forward declaration: buildTable wires this into a button OnClick,
-- but the implementation lives later in the file. Without forward-
-- declaring as a local, the closure captures a global (nil) instead
-- of the local function defined further down.
local peekLastTrick

-- Palette ---------------------------------------------------------------
-- Universal online-WHEREDNGN aesthetic: green felt table, dark wood trim,
-- cream card faces with classic red/black French-deck suit colors,
-- gold active-turn accents.
local COL = {
    feltDark   = { 0.05, 0.20, 0.11, 0.97 },
    feltLight  = { 0.08, 0.28, 0.16, 0.95 },
    centerPad  = { 0.04, 0.16, 0.09, 0.95 },
    woodEdge   = { 0.34, 0.22, 0.12, 1.00 },
    cardFace   = { 0.96, 0.94, 0.86, 1.00 },
    cardEdge   = { 0.18, 0.13, 0.08, 1.00 },
    cardBack   = { 0.10, 0.24, 0.50, 1.00 },
    cardBackEdge = { 0.04, 0.10, 0.22, 1.00 },
    badEdge    = { 0.55, 0.20, 0.20, 1.00 },
    legalEdge  = { 0.95, 0.78, 0.30, 1.00 },     -- gold
    activeGlow = { 1.00, 0.84, 0.30, 0.22 },     -- gold tint
    txtCream   = "ffe8dec0",
    txtGold    = "ffffd055",
    txtSoft    = "ff8da095",
    txtUs      = "ff66ff88",
    txtThem    = "ffff7777",
}

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

-- Build a "card face" frame: cream rectangle with dark thin border.
-- Caller anchors and sets size. Returns { frame, label } where `label`
-- is the FontString to set with C.PrettyOnCard(card).
local function makeCardFace(parent, w, h)
    local frame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    frame:SetSize(w or 50, h or 70)
    setBackdrop(frame, true, COL.cardFace, COL.cardEdge, 8, "solid")
    local label = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    label:SetFont(K.CARD_FONT, math.floor((h or 70) * 0.32), "OUTLINE")
    label:SetPoint("CENTER", 0, 0)
    label:SetJustifyH("CENTER")
    return { frame = frame, label = label }
end

-- Build a "card back" badge: navy blue card with a decorative inner
-- frame and centered diamond glyph, evoking a real playing-card back.
-- Caller anchors and sets initial visibility.
local function makeCardBack(parent, w, h)
    w = w or 24; h = h or 34
    local frame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    frame:SetSize(w, h)
    setBackdrop(frame, true, COL.cardBack, COL.cardBackEdge, 4, "solid")

    -- Inner inset rectangle creates the "framed" card-back look.
    local inset = frame:CreateTexture(nil, "ARTWORK")
    inset:SetTexture("Interface\\Buttons\\WHITE8X8")
    inset:SetVertexColor(0.06, 0.18, 0.42, 1)
    inset:SetPoint("TOPLEFT", 4, -4)
    inset:SetPoint("BOTTOMRIGHT", -4, 4)

    -- Lighter inner highlight stripe gives depth.
    local stripe = frame:CreateTexture(nil, "ARTWORK", nil, 1)
    stripe:SetTexture("Interface\\Buttons\\WHITE8X8")
    stripe:SetVertexColor(0.22, 0.36, 0.62, 1)
    stripe:SetPoint("TOPLEFT", 6, -6)
    stripe:SetPoint("BOTTOMRIGHT", -6, 6)

    -- Centered diamond glyph as a faux pattern.
    local glyph = frame:CreateFontString(nil, "OVERLAY")
    glyph:SetFont(K.CARD_FONT, math.floor(h * 0.55), "OUTLINE")
    glyph:SetPoint("CENTER", 0, 0)
    glyph:SetText("|cff7799bb\226\153\166|r")  -- ♦
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
        if WHEREDNGNDB then
            local p, _, rp, x, y = self:GetPoint()
            WHEREDNGNDB.framePos = { p, rp, x, y }
        end
    end)
    f:SetClampedToScreen(true)
    f:SetFrameStrata("HIGH")
    setBackdrop(f, true)

    -- Title
    local title = makeText(f, 16, "CENTER")
    title:SetPoint("TOP", 0, -10)
    title:SetText("|cff66ddffWHEREDNGN|r")

    gameIDText = makeText(f, 11, "RIGHT")
    gameIDText:SetPoint("TOPRIGHT", -36, -12)

    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 0, 0)
    close:SetScript("OnClick", function() U.Hide() end)

    -- Status line at top
    statusText = makeText(f, 12, "CENTER")
    statusText:SetPoint("TOP", 0, -32)

    -- Score / contract / round line at the very bottom
    scoreText = makeText(f, 12, "LEFT")
    scoreText:SetPoint("BOTTOMLEFT", 12, 8)

    roundText = makeText(f, 12, "RIGHT")
    roundText:SetPoint("BOTTOMRIGHT", -12, 8)

    contractText = makeText(f, 12, "CENTER")
    contractText:SetPoint("BOTTOM", 0, 8)

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

    -- 4 seat slots
    local seatLabels = { "Seat 1 (Host)", "Seat 2", "Seat 3 (Host's partner)", "Seat 4" }
    lobbyPanel.seatTexts = {}
    for i = 1, 4 do
        local row = CreateFrame("Frame", nil, lobbyPanel, "BackdropTemplate")
        row:SetSize(380, 28)
        row:SetPoint("TOP", 0, -38 - (i - 1) * 34)
        setBackdrop(row, true)
        local lbl = makeText(row, 12, "LEFT")
        lbl:SetPoint("LEFT", 8, 0)
        lbl:SetText(seatLabels[i])
        local nm = makeText(row, 12, "RIGHT")
        nm:SetPoint("RIGHT", -8, 0)
        nm:SetText("|cff666666(empty)|r")
        lobbyPanel.seatTexts[i] = nm
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

local function buildSeatBadge(parent, anchorCb)
    local b = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    b:SetSize(220, 100)
    setBackdrop(b, true, COL.feltLight, COL.woodEdge)
    anchorCb(b)

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

    local dealerTx = makeText(b, 12, "LEFT")
    dealerTx:SetPoint("TOPLEFT", 6, -6)
    dealerTx:SetTextColor(1, 0.84, 0.30)

    local turnGlow = b:CreateTexture(nil, "OVERLAY")
    turnGlow:SetAllPoints()
    turnGlow:SetColorTexture(unpack(COL.activeGlow))
    turnGlow:Hide()

    return { frame = b, nameText = nameTx, backs = backs,
             countText = countTx, meldText = meldTx,
             dealerText = dealerTx, turnGlow = turnGlow }
end

local function buildCenterSlot(parent, anchorCb)
    local face = makeCardFace(parent, 64, 90)
    anchorCb(face.frame)
    face.frame:Hide()  -- shown only when a card is in this slot
    return face
end

local function buildTable()
    tablePanel = CreateFrame("Frame", nil, f)
    tablePanel:SetPoint("TOPLEFT", 14, -56)
    tablePanel:SetPoint("BOTTOMRIGHT", -14, 30)

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

    -- Last-trick peek button: small "?" button anchored to centerPad.
    -- Disabled once used per hand (S.s.peekedThisRound).
    local peekBtn = makeButton(centerPad, "?", 22, 22)
    peekBtn:SetPoint("TOPRIGHT", -4, -4)
    peekBtn:SetScript("OnClick", function() peekLastTrick() end)
    peekBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("Peek the previous trick", 1, 1, 1)
        GameTooltip:AddLine("Once per hand, 3 seconds.", 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)
    peekBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    tablePanel.peekBtn = peekBtn

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
    local localBar = CreateFrame("Frame", nil, tablePanel, "BackdropTemplate")
    localBar:SetSize(540, 26)
    localBar:SetPoint("BOTTOM", actionPanel, "TOP", 0, 6)
    setBackdrop(localBar, true, COL.feltLight, COL.woodEdge, 8)
    localBar.nameText = makeText(localBar, 12, "LEFT")
    localBar.nameText:SetPoint("LEFT", 10, 0)
    localBar.nameText:SetTextColor(1, 0.84, 0.30)
    localBar.meldText = makeText(localBar, 11, "RIGHT")
    localBar.meldText:SetPoint("RIGHT", -10, 0)
    localBar.meldText:SetTextColor(1, 0.84, 0.30)
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
    b:SetScript("OnClick", onclick)
    b:Show()
end

local function renderActions()
    clearActions()
    if S.s.phase == K.PHASE_DEAL1 or S.s.phase == K.PHASE_DEAL2BID then
        if S.IsMyTurn() and S.s.turnKind == "bid" then
            addAction("Pass", function() net().LocalBid(K.BID_PASS) end)
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

                -- Ashkal: only the 3rd or 4th bidder, only if all prior
                -- bidders passed. Hands Hokm-on-flipped to your partner.
                local order = { (S.s.dealer % 4) + 1, ((S.s.dealer + 1) % 4) + 1,
                                ((S.s.dealer + 2) % 4) + 1, S.s.dealer }
                local myPos
                for i, seat in ipairs(order) do
                    if seat == S.s.localSeat then myPos = i; break end
                end
                if myPos and myPos >= 3 and not anyBidYet then
                    local allPriorPassed = true
                    for i = 1, myPos - 1 do
                        if S.s.bids[order[i]] ~= K.BID_PASS then
                            allPriorPassed = false; break
                        end
                    end
                    if allPriorPassed then
                        addAction("Ashkal", function() net().LocalBid(K.BID_ASHKAL) end)
                    end
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
            addAction("Bel (x2)", function() net().LocalDouble() end)
            addAction("Skip", function() net().LocalSkipDouble() end)
        end
    elseif S.s.phase == K.PHASE_REDOUBLE then
        local b = S.s.contract and S.s.contract.bidder
        if b == S.s.localSeat then
            addAction("Bel-Re (x4)", function() net().LocalRedouble() end)
            addAction("Skip", function() net().LocalSkipDouble() end)
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
                    S.s.meldsDeclared[S.s.localSeat] = true
                    U.Refresh()
                end)
            end
        end
        -- Takweesh button is always available during PLAY. Any player
        -- can press to call out an illegal play by the opposing team.
        if S.s.phase == K.PHASE_PLAY and S.s.localSeat then
            addAction("|cffff5555TAKWEESH|r", function() net().LocalTakweesh() end)
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

-- Real-card layout: corner pips have the rank on top with a smaller
-- suit symbol stacked underneath; the center shows a large suit symbol
-- alongside the rank for at-a-glance reading.
local function makeHandButton(parent)
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    setBackdrop(b, true, COL.cardFace, COL.cardEdge, 6, "solid")

    -- Top-left corner: rank then suit, stacked
    b.tlRank = b:CreateFontString(nil, "OVERLAY")
    b.tlRank:SetFont(K.CARD_FONT, 14, "")
    b.tlRank:SetPoint("TOPLEFT", 5, -4)
    b.tlSuit = b:CreateFontString(nil, "OVERLAY")
    b.tlSuit:SetFont(K.CARD_FONT, 12, "")
    b.tlSuit:SetPoint("TOPLEFT", 5, -19)

    -- Center: big suit symbol
    b.center = b:CreateFontString(nil, "OVERLAY")
    b.center:SetFont(K.CARD_FONT, 36, "OUTLINE")
    b.center:SetPoint("CENTER", 0, 0)

    -- Bottom-right corner: rank + suit, stacked (suit on top, rank on
    -- bottom — visually "rotated 180°" without actual rotation).
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

    -- Rank+suit colored separately so we can place them in distinct slots
    -- and pick a single suit color for ♥/♦ (red) and ♠/♣ (black-ish).
    local function rankSuitFor(card)
        local r, s = C.Rank(card), C.Suit(card)
        local color = (s == "H" or s == "D") and "ffcc1f1f" or "ff111111"
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

        local rankStr, suitStr, color = rankSuitFor(card)
        b.tlRank:SetText(rankStr)
        b.tlSuit:SetText(suitStr)
        b.brRank:SetText(rankStr)
        b.brSuit:SetText(suitStr)
        -- Center: rank + suit together so rank is readable at a glance.
        b.center:SetText(rankStr .. suitStr)

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
       or S.s.phase == K.PHASE_DOUBLE or S.s.phase == K.PHASE_REDOUBLE then
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
    local team = R.TeamOf(seat)
    local list = S.s.meldsByTeam[team] or {}
    local mine = {}
    for _, m in ipairs(list) do
        if m.declaredBy == seat then
            local s
            if m.kind == "carre" then
                s = ("Carré %s"):format(C.RankGlyph(m.top))
            else
                s = ("S%d %s%s"):format(m.len or 3, C.RankGlyph(m.top), K.SUIT_GLYPH[m.suit] or "")
            end
            mine[#mine + 1] = s .. (" (%d)"):format(m.value or 0)
        end
    end
    if #mine == 0 then return "" end
    return table.concat(mine, ", ")
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
            b.meldText:SetText(meldsDescForSeat(seat))
            b.dealerText:SetText(seat == S.s.dealer and "D" or "")
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
    lb.meldText:SetText(meldsDescForSeat(me))
    if S.s.turn == me then
        lb:SetBackdropBorderColor(unpack(COL.legalEdge))
    else
        lb:SetBackdropBorderColor(unpack(COL.woodEdge))
    end
end

-- Rendering target for the center area. Default is the live trick;
-- the last-trick peek temporarily swaps this to the previous trick.
local centerOverride = nil

-- Track number of plays in the current trick across renders so we can
-- detect "a new card just landed" and run the scale+fade animation
-- without re-animating cards that were already in place.
local prevTrickPlayCount = 0

-- Brief scale+fade animation when a fresh card lands in a center slot.
-- Cheap C_Timer ticker — 6 steps over CARD_ANIM_SEC.
local function animateLand(slot)
    if not slot or not slot.frame then return end
    local frame = slot.frame
    local steps = 6
    local stepDur = (K.CARD_ANIM_SEC or 0.18) / steps
    local i = 0
    frame:SetScale(0.45)
    frame:SetAlpha(0.35)
    local ticker
    ticker = C_Timer.NewTicker(stepDur, function()
        i = i + 1
        local t = i / steps
        frame:SetScale(0.45 + 0.55 * t)
        frame:SetAlpha(0.35 + 0.65 * t)
        if i >= steps then
            ticker:Cancel()
            frame:SetScale(1)
            frame:SetAlpha(1)
        end
    end, steps)
end

local function renderCenter()
    for _, slot in pairs(centerCards) do
        slot.frame:Hide()
        slot.label:SetText("")
        slot.frame:SetBackdropBorderColor(unpack(COL.cardEdge))
    end
    -- Last-trick peek override: show the previous trick exactly where
    -- the live one would appear, with the winning card glowing gold.
    if centerOverride and centerOverride.plays then
        for _, p in ipairs(centerOverride.plays) do
            local pos = posOfSeat(p.seat)
            local slot = centerCards[pos]
            if slot then
                slot.frame:Show()
                slot.label:SetText(C.PrettyOnCard(p.card))
                if p.seat == centerOverride.winner then
                    slot.frame:SetBackdropBorderColor(unpack(COL.legalEdge))
                end
            end
        end
        return
    end
    -- During bidding, show the face-up bid card in the dedicated center slot.
    if S.s.phase == K.PHASE_DEAL1 or S.s.phase == K.PHASE_DEAL2BID then
        if S.s.bidCard then
            local slot = centerCards.bid
            slot.frame:Show()
            slot.label:SetText(C.PrettyOnCard(S.s.bidCard))
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
            slot.label:SetText(C.PrettyOnCard(p.card))
            if highlight and p.seat == highlight then
                slot.frame:SetBackdropBorderColor(unpack(COL.legalEdge))
            end
            if newFromIdx and i >= newFromIdx then
                animateLand(slot)
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
    local canJoin = S.s.pendingHost and not S.s.isHost
    for _, info in pairs(S.s.seats) do
        if info and info.name == S.s.localName then canJoin = false end
    end
    joinBtn:SetShown(canJoin)
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
    if phase == K.PHASE_DOUBLE then return "Defenders: Bel?" end
    if phase == K.PHASE_REDOUBLE then return "Bidder: Bel-Re?" end
    if phase == K.PHASE_DEAL3 then return "Final 3 dealt — declare melds" end
    if phase == K.PHASE_PLAY then
        if S.IsMyTurn() then return "|cff55ff55Your turn|r" end
        local seat = S.s.turn
        local nm = seat and S.s.seats[seat] and shortName(S.s.seats[seat].name) or "?"
        return ("Playing — %s to act"):format(nm)
    end
    if phase == K.PHASE_SCORE then
        local d = S.s.lastRoundDelta or { A = 0, B = 0 }
        return ("Round done: A +%d, B +%d"):format(d.A or 0, d.B or 0)
    end
    if phase == K.PHASE_GAME_END then
        return ("Game over — Team %s wins"):format(S.s.winner or "?")
    end
    return ""
end

-- Helper: short team label including the seated names of that team.
local function teamLabel(t)
    if not S.s.localSeat then return ("Team " .. t) end
    local seats = (t == "A") and { 1, 3 } or { 2, 4 }
    local names = {}
    for _, sn in ipairs(seats) do
        local info = S.s.seats[sn]
        if info and info.name then
            names[#names + 1] = shortName(info.name)
        end
    end
    if #names == 0 then return ("Team " .. t) end
    return ("Team %s (%s)"):format(t, table.concat(names, "+"))
end

-- Show/hide the round-result banner. Host has the full result struct
-- in S.s.lastRoundResult and shows a multi-line breakdown; non-host
-- clients only have the deltas, so they get a compact one-liner.
local function renderBanner()
    local banner = tablePanel and tablePanel.banner
    if not banner then return end
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
        banner.title:SetText(("|cffffd055GAME OVER|r"))
        banner.final:SetText(("Team %s wins  —  %d / %d"):format(
            S.s.winner or "?", S.s.cumulative.A or 0, S.s.cumulative.B or 0))
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
        banner.title:SetText("|cff66ff88Contract made|r")
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
    if S.s.contract and S.s.contract.redoubled then mods[#mods + 1] = "Bel-Re" end
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

local function renderStatus()
    statusText:SetText(statusFor(S.s.phase))

    -- score
    scoreText:SetText(("Us(A): |cff66ff66%d|r   Them(B): |cffff6666%d|r   /  %d"):format(
        S.s.cumulative.A or 0, S.s.cumulative.B or 0, S.s.target or 152))

    -- contract
    if S.s.contract then
        local c = S.s.contract
        local typeStr = c.type == K.BID_SUN and "SUN" or "HOKM"
        local trumpStr = c.trump and (" " .. K.SUIT_GLYPH[c.trump]) or ""
        local mods = {}
        if c.doubled then mods[#mods + 1] = "Bel" end
        if c.redoubled then mods[#mods + 1] = "Bel-Re" end
        local modStr = #mods > 0 and (" [" .. table.concat(mods, "+") .. "]") or ""
        local bidder = c.bidder and S.s.seats[c.bidder] and shortName(S.s.seats[c.bidder].name) or "?"
        contractText:SetText(("Contract: %s — %s%s%s"):format(bidder, typeStr, trumpStr, modStr))
    else
        contractText:SetText("")
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
        renderPeekButton()
    end
    renderActions()
    renderStatus()
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
