----------------------------------------------------------------------
-- TommyTwoquests — QuestTracker.lua
-- Main tracker frame, layout engine, event registration
----------------------------------------------------------------------
local AddonName, TTQ = ...
local table, pairs, ipairs, pcall, CreateFrame, UIParent = table, pairs, ipairs, pcall, CreateFrame, UIParent
local C_QuestLog, C_Map, C_Texture, C_Timer = C_QuestLog, C_Map, C_Texture, C_Timer
local wipe, math, GetTime = wipe, math, GetTime

local HEADER_POOL = {}
local activeQuestItems = {}
local activeHeaders = {}
local GROUP_CONTAINER_POOL = {}
local activeGroupContainers = {}
TTQ._activeGroupContainers = activeGroupContainers

local SECTION_HEADER_HEIGHT = 22
local SECTION_ANIM_DURATION = 0.28
local SECTION_GROUP_SPACING = 4
-- Height of a section when collapsed (header + gap + spacing) — match layout so no jump on refresh
local COLLAPSED_SECTION_HEIGHT = SECTION_HEADER_HEIGHT + 2 + SECTION_GROUP_SPACING

----------------------------------------------------------------------
-- Acquire / release group header rows
----------------------------------------------------------------------
local function AcquireHeader(parent)
    local header = table.remove(HEADER_POOL)
    if not header then
        header = {}
        -- Button so it's clickable to collapse/expand
        local frame = CreateFrame("Button", nil, parent)
        frame:SetHeight(22)
        frame:EnableMouse(true)
        frame:RegisterForClicks("LeftButtonUp")
        header.frame = frame

        -- Subtle highlight on hover
        local hl = frame:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(1, 1, 1, 0.04)

        local icon = frame:CreateTexture(nil, "ARTWORK")
        icon:SetSize(12, 12)
        icon:SetPoint("LEFT", frame, "LEFT", 0, 0)
        header.icon = icon

        local text = TTQ:CreateText(frame,
            TTQ:GetSetting("headerFontSize"),
            TTQ:GetSetting("headerColor"), "LEFT")
        text:SetPoint("LEFT", icon, "RIGHT", 5, 0)
        header.text = text

        -- Collapse indicator (+/-) — font/color set during layout to match quest name style
        local collapseInd = TTQ:CreateText(frame, 12, { r = 1, g = 1, b = 1 }, "RIGHT")
        collapseInd:SetPoint("RIGHT", frame, "RIGHT", 0, 0)
        collapseInd:SetWidth(14)
        header.collapseInd = collapseInd

        local count = TTQ:CreateText(frame,
            TTQ:GetSetting("headerFontSize") - 2,
            { r = 0.6, g = 0.6, b = 0.6 }, "RIGHT")
        count:SetPoint("RIGHT", collapseInd, "LEFT", -2, 0)
        header.count = count

        -- Separator line below header
        local sep = frame:CreateTexture(nil, "ARTWORK")
        sep:SetHeight(1)
        sep:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
        sep:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
        sep:SetColorTexture(1, 1, 1, 0.08)
        header.sep = sep
    end
    header.frame:SetParent(parent)
    header.frame:Show()
    return header
end

local function ReleaseHeader(header)
    header.frame:Hide()
    header.frame:ClearAllPoints()
    table.insert(HEADER_POOL, header)
end

----------------------------------------------------------------------
-- Group container: wraps header + quest items for section collapse animation
----------------------------------------------------------------------
local function AcquireGroupContainer(parent)
    local gc = table.remove(GROUP_CONTAINER_POOL)
    if not gc then
        gc = {}
        local frame = CreateFrame("Frame", nil, parent)
        frame:SetClipsChildren(true)
        gc.frame = frame
        local contentFrame = CreateFrame("Frame", nil, frame)
        contentFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -(SECTION_HEADER_HEIGHT + 2))
        contentFrame:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, -(SECTION_HEADER_HEIGHT + 2))
        gc.contentFrame = contentFrame
    end
    gc.frame:SetParent(parent)
    gc.frame:Show()
    gc.frame:SetHeight(100)
    gc.contentFrame:SetAlpha(1)
    gc.header = nil
    gc.questItems = gc.questItems or {}
    wipe(gc.questItems)
    return gc
end

local function ReleaseGroupContainer(gc)
    if gc.header then
        ReleaseHeader(gc.header)
        gc.header = nil
    end
    for _, item in ipairs(gc.questItems) do
        TTQ:ReleaseQuestItem(item)
    end
    wipe(gc.questItems)
    -- Release scenario objective items (different pool)
    if gc._scenarioObjItems then
        for _, objItem in ipairs(gc._scenarioObjItems) do
            TTQ:ReleaseObjectiveItem(objItem)
        end
        wipe(gc._scenarioObjItems)
    end
    gc.frame:Hide()
    gc.frame:ClearAllPoints()
    gc.frame:SetClipsChildren(true)
    table.insert(GROUP_CONTAINER_POOL, gc)
end

----------------------------------------------------------------------
-- Initialize the tracker (called from Core.lua OnReady)
----------------------------------------------------------------------
function TTQ:InitTracker()
    self:CreateTrackerFrame()
    self:RefreshTracker()
end

----------------------------------------------------------------------
-- Create the main tracker frame
----------------------------------------------------------------------
function TTQ:CreateTrackerFrame()
    local anchor = self:GetSetting("trackerAnchor")
    local width = self:GetSetting("trackerWidth")

    -- Main container
    local tracker = CreateFrame("Frame", "TommyTwoquestsTracker", UIParent, "BackdropTemplate")
    tracker:SetWidth(width)
    tracker:SetHeight(400) -- dynamic, resized after layout
    tracker:SetPoint(anchor.point, UIParent, anchor.relativePoint or anchor.point, anchor.x, anchor.y)
    tracker:SetClampedToScreen(true)
    tracker:SetFrameStrata("MEDIUM")
    tracker:SetFrameLevel(5)
    tracker:EnableMouseWheel(true)
    tracker:SetScript("OnMouseWheel", function(self, delta)
        if TTQ.ScrollFrame then
            local maxScroll = TTQ.ScrollFrame:GetVerticalScrollRange() or 0
            local current = TTQ.ScrollFrame:GetVerticalScroll() or 0
            local step = 30
            local newScroll = math.max(0, math.min(current - delta * step, maxScroll))
            TTQ.ScrollFrame:SetVerticalScroll(newScroll)
            TTQ:UpdateScrollFades()
        end
    end)
    self.Tracker = tracker

    -- Backdrop
    self:UpdateTrackerBackdrop()

    -- Make draggable
    tracker:SetMovable(true)
    tracker:EnableMouse(true)
    tracker:RegisterForDrag("LeftButton")
    tracker:SetScript("OnDragStart", function(self)
        if not TTQ:GetSetting("locked") then
            self:StartMoving()
        end
    end)
    tracker:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        -- Always normalize to a TOP anchor so the top edge stays fixed when height changes
        local point, _, relativePoint, x, y = self:GetPoint()
        -- Convert whatever anchor WoW gave us into a TOPRIGHT-based anchor
        local top = self:GetTop()
        local right = self:GetRight()
        local parentRight = UIParent:GetRight() or GetScreenWidth()
        local parentTop = UIParent:GetTop() or GetScreenHeight()
        local scale = self:GetEffectiveScale() / UIParent:GetEffectiveScale()
        local newX = (right * scale) - parentRight
        local newY = (top * scale) - parentTop
        self:ClearAllPoints()
        self:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", newX, newY)
        TTQ:SetSetting("trackerAnchor", {
            point = "TOPRIGHT",
            relativePoint = "TOPRIGHT",
            x = newX,
            y = newY,
        })
    end)

    -- Fade behavior
    if self:GetSetting("fadeWhenNotHovered") then
        tracker:SetAlpha(self:GetSetting("fadeAlpha"))
        tracker:SetScript("OnEnter", function(self)
            self:SetAlpha(1)
        end)
        tracker:SetScript("OnLeave", function(self)
            TTQ:SetFadeIfEnabled(self)
        end)
    end

    -- Title bar
    local titleBar = CreateFrame("Frame", nil, tracker)
    titleBar:SetHeight(28)
    titleBar:SetPoint("TOPLEFT", tracker, "TOPLEFT", 0, 0)
    titleBar:SetPoint("TOPRIGHT", tracker, "TOPRIGHT", 0, 0)
    self.TitleBar = titleBar

    -- Soft bottom divider under title bar (inset to avoid square corners)
    local titleDivider = titleBar:CreateTexture(nil, "ARTWORK")
    titleDivider:SetHeight(1)
    titleDivider:SetPoint("BOTTOMLEFT", titleBar, "BOTTOMLEFT", 8, 0)
    titleDivider:SetPoint("BOTTOMRIGHT", titleBar, "BOTTOMRIGHT", -8, 0)
    titleDivider:SetTexture("Interface\\Buttons\\WHITE8x8")
    titleDivider:SetColorTexture(1, 1, 1, 0.08)

    self.TitleDivider = titleDivider

    -- Title text (centered)
    local headerSize = self:GetSetting("headerFontSize")
    local headerColor = self:GetSetting("headerColor")
    local title = self:CreateText(titleBar, headerSize + 1, headerColor, "CENTER")
    title:SetPoint("CENTER", titleBar, "CENTER", 0, 0)
    title:SetText("Quests")
    self.TitleText = title

    -- Collapse button
    local collapseBtn = CreateFrame("Button", nil, titleBar)
    collapseBtn:SetSize(16, 16)
    collapseBtn:SetPoint("RIGHT", titleBar, "RIGHT", -4, 0)
    collapseBtn:SetNormalTexture("Interface\\Buttons\\UI-MinusButton-UP")
    collapseBtn:SetHighlightTexture("Interface\\Buttons\\UI-PlusButton-Hilight")
    collapseBtn:GetNormalTexture():SetDesaturated(true)
    collapseBtn:GetNormalTexture():SetVertexColor(0.85, 0.85, 0.85)
    collapseBtn:SetScript("OnClick", function()
        local collapsed = TTQ:GetSetting("collapsed")
        TTQ:SetSetting("collapsed", not collapsed)
        TTQ:RefreshTracker()
    end)
    self.CollapseBtn = collapseBtn

    -- Settings button (gear) — open addon options
    local settingsBtn = CreateFrame("Button", nil, titleBar)
    settingsBtn:SetSize(16, 16)
    settingsBtn:SetPoint("RIGHT", collapseBtn, "LEFT", -2, 0)
    local settingsIcon = settingsBtn:CreateTexture(nil, "ARTWORK")
    settingsIcon:SetAllPoints()
    if C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo("Gear_64") then
        settingsIcon:SetAtlas("Gear_64", false)
    else
        settingsIcon:SetTexture("Interface\\Buttons\\UI-OptionsButton")
    end
    settingsIcon:SetDesaturated(true)
    settingsIcon:SetVertexColor(0.85, 0.85, 0.85)
    settingsBtn:SetScript("OnClick", function()
        TTQ:OpenSettings()
    end)
    settingsBtn:SetScript("OnEnter", function(btn)
        GameTooltip:SetOwner(btn, "ANCHOR_LEFT")
        GameTooltip:SetText("Settings")
        GameTooltip:AddLine("Open TommyTwoquests options.", 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)
    settingsBtn:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    self.SettingsBtn = settingsBtn

    -- Filter dropdown button
    local filterBtn = CreateFrame("Button", nil, titleBar)
    filterBtn:SetSize(16, 16)
    filterBtn:SetPoint("RIGHT", settingsBtn, "LEFT", -2, 0)
    filterBtn:RegisterForClicks("LeftButtonUp")

    local filterIcon = filterBtn:CreateTexture(nil, "ARTWORK")
    filterIcon:SetSize(14, 14)
    filterIcon:SetPoint("CENTER")
    -- Use a funnel/filter atlas distinct from the settings cogwheel
    if C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo("bags-icon-filter") then
        filterIcon:SetAtlas("bags-icon-filter", false)
    elseif C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo("search-filtertoggle-off") then
        filterIcon:SetAtlas("search-filtertoggle-off", false)
    else
        filterIcon:SetTexture("Interface\\Minimap\\Tracking\\None")
    end
    filterIcon:SetDesaturated(true)
    filterIcon:SetVertexColor(0.85, 0.85, 0.85)
    filterBtn.icon = filterIcon

    local filterHighlight = filterBtn:CreateTexture(nil, "HIGHLIGHT")
    filterHighlight:SetAllPoints()
    filterHighlight:SetColorTexture(1, 1, 1, 0.15)

    filterBtn:SetScript("OnClick", function(btn)
        TTQ:ShowFilterDropdown(btn)
    end)
    filterBtn:SetScript("OnEnter", function(btn)
        GameTooltip:SetOwner(btn, "ANCHOR_LEFT")
        GameTooltip:SetText("Quest Filters")
        GameTooltip:AddLine("Click to toggle quest type filters.", 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)
    filterBtn:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    self.FilterBtn = filterBtn

    -- Scroll frame wrapping the content area for overflow
    local scrollFrame = CreateFrame("ScrollFrame", nil, tracker)
    scrollFrame:SetPoint("TOPLEFT", titleBar, "BOTTOMLEFT", 0, -4)
    scrollFrame:SetPoint("TOPRIGHT", titleBar, "BOTTOMRIGHT", 0, -4)
    scrollFrame:SetHeight(1) -- dynamic
    scrollFrame:SetClipsChildren(true)
    scrollFrame:EnableMouseWheel(true)
    scrollFrame:SetScript("OnMouseWheel", function(self, delta)
        local maxScroll = self:GetVerticalScrollRange() or 0
        local current = self:GetVerticalScroll() or 0
        local step = 30
        local newScroll = math.max(0, math.min(current - delta * step, maxScroll))
        self:SetVerticalScroll(newScroll)
        TTQ:UpdateScrollFades()
    end)
    self.ScrollFrame = scrollFrame

    -- Scroll bound indicator: small L-shape corner mark at bottom-right when content overflows
    local CORNER_SIZE = 6
    local CORNER_ALPHA = 0.35

    local cornerBR_h = tracker:CreateTexture(nil, "OVERLAY", nil, 7)
    cornerBR_h:SetSize(CORNER_SIZE + 4, 1)
    cornerBR_h:SetColorTexture(1, 1, 1, CORNER_ALPHA)
    cornerBR_h:Hide()

    local cornerBR_v = tracker:CreateTexture(nil, "OVERLAY", nil, 7)
    cornerBR_v:SetSize(1, CORNER_SIZE + 4)
    cornerBR_v:SetColorTexture(1, 1, 1, CORNER_ALPHA)
    cornerBR_v:Hide()

    self.ScrollCorners = { cornerBR_h, cornerBR_v }

    -- Content area (holds quest items); child of scroll frame
    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetWidth(width)
    content:SetHeight(1) -- dynamic
    scrollFrame:SetScrollChild(content)
    self.Content = content

    -- Zone filter indicator (constrained so it doesn't overlap title)
    local zoneLabel = self:CreateText(titleBar, headerSize - 2, { r = 0.5, g = 0.8, b = 1.0 }, "RIGHT")
    zoneLabel:SetPoint("RIGHT", filterBtn, "LEFT", -8, 0)
    zoneLabel:SetPoint("LEFT", titleBar, "LEFT", 10, 0)
    zoneLabel:SetWordWrap(false)
    zoneLabel:SetNonSpaceWrap(false)
    zoneLabel:SetText("")
    self.ZoneLabel = zoneLabel

    -- Filter dropdown panel (custom frame so it works without EasyMenu/UIDropDownMenu)
    self:CreateFilterDropdownFrame()

    -- Apply initial header visibility
    self:UpdateHeaderVisibility()

    -- Hide the Blizzard tracker
    self:HideBlizzardTracker()
end

----------------------------------------------------------------------
-- Toggle tracker header visibility (showTrackerHeader setting)
-- When hidden: title text, divider, zone label hidden; title bar
-- shrinks to a compact row with just the icon buttons floating above.
----------------------------------------------------------------------
function TTQ:UpdateHeaderVisibility()
    if not self.TitleBar then return end
    local show = self:GetSetting("showTrackerHeader")
    if show then
        self.TitleBar:SetHeight(28)
        self.TitleText:Show()
        self.TitleDivider:Show()
        self.ZoneLabel:Show()
        -- ScrollFrame anchors below the full title bar
        if self.ScrollFrame then
            self.ScrollFrame:ClearAllPoints()
            self.ScrollFrame:SetPoint("TOPLEFT", self.TitleBar, "BOTTOMLEFT", 8, -4)
            self.ScrollFrame:SetPoint("TOPRIGHT", self.TitleBar, "BOTTOMRIGHT", -8, -4)
        end
    else
        self.TitleBar:SetHeight(18)
        self.TitleText:Hide()
        self.TitleDivider:Hide()
        self.ZoneLabel:Hide()
        -- Hide buttons until user hovers over the tracker
        self.CollapseBtn:SetAlpha(0)
        self.SettingsBtn:SetAlpha(0)
        self.FilterBtn:SetAlpha(0)
        -- ScrollFrame anchors below the compact button row
        if self.ScrollFrame then
            self.ScrollFrame:ClearAllPoints()
            self.ScrollFrame:SetPoint("TOPLEFT", self.TitleBar, "BOTTOMLEFT", 8, -2)
            self.ScrollFrame:SetPoint("TOPRIGHT", self.TitleBar, "BOTTOMRIGHT", -8, -2)
        end
    end

    -- Set up hover reveal for header buttons when header is hidden
    self:UpdateHeaderButtonHover()
end

----------------------------------------------------------------------
-- Show/hide header buttons on tracker hover when header is hidden
----------------------------------------------------------------------
function TTQ:UpdateHeaderButtonHover()
    if not self.Tracker then return end
    local show = self:GetSetting("showTrackerHeader")

    if not show then
        -- Use OnEnter/OnLeave on the tracker to reveal buttons
        local oldOnEnter = self.Tracker._origOnEnter
        local oldOnLeave = self.Tracker._origOnLeave

        self.Tracker:SetScript("OnEnter", function(frame)
            if TTQ.CollapseBtn then TTQ.CollapseBtn:SetAlpha(1) end
            if TTQ.SettingsBtn then TTQ.SettingsBtn:SetAlpha(1) end
            if TTQ.FilterBtn then TTQ.FilterBtn:SetAlpha(1) end
            -- Also handle fade behavior
            if TTQ:GetSetting("fadeWhenNotHovered") then
                frame:SetAlpha(1)
            end
        end)
        self.Tracker:SetScript("OnLeave", function(frame)
            if not TTQ:GetSetting("showTrackerHeader") then
                -- Only hide if mouse isn't over a child button
                if not frame:IsMouseOver() then
                    if TTQ.CollapseBtn then TTQ.CollapseBtn:SetAlpha(0) end
                    if TTQ.SettingsBtn then TTQ.SettingsBtn:SetAlpha(0) end
                    if TTQ.FilterBtn then TTQ.FilterBtn:SetAlpha(0) end
                end
            end
            TTQ:SetFadeIfEnabled(frame)
        end)

        -- Also hook the title bar for mouse detection (buttons are children of it)
        self.TitleBar:SetScript("OnEnter", function()
            if TTQ.CollapseBtn then TTQ.CollapseBtn:SetAlpha(1) end
            if TTQ.SettingsBtn then TTQ.SettingsBtn:SetAlpha(1) end
            if TTQ.FilterBtn then TTQ.FilterBtn:SetAlpha(1) end
            if TTQ:GetSetting("fadeWhenNotHovered") then
                TTQ.Tracker:SetAlpha(1)
            end
        end)
        self.TitleBar:SetScript("OnLeave", function()
            if not TTQ.Tracker:IsMouseOver() then
                if not TTQ:GetSetting("showTrackerHeader") then
                    if TTQ.CollapseBtn then TTQ.CollapseBtn:SetAlpha(0) end
                    if TTQ.SettingsBtn then TTQ.SettingsBtn:SetAlpha(0) end
                    if TTQ.FilterBtn then TTQ.FilterBtn:SetAlpha(0) end
                end
                TTQ:SetFadeIfEnabled(TTQ.Tracker)
            end
        end)
    else
        -- Header is shown: ensure buttons are visible and restore normal hover
        self.CollapseBtn:SetAlpha(1)
        self.SettingsBtn:SetAlpha(1)
        self.FilterBtn:SetAlpha(1)

        -- Restore fade-only hover behavior
        if self:GetSetting("fadeWhenNotHovered") then
            self.Tracker:SetScript("OnEnter", function(frame)
                frame:SetAlpha(1)
            end)
            self.Tracker:SetScript("OnLeave", function(frame)
                TTQ:SetFadeIfEnabled(frame)
            end)
        else
            self.Tracker:SetScript("OnEnter", nil)
            self.Tracker:SetScript("OnLeave", nil)
        end
        self.TitleBar:SetScript("OnEnter", nil)
        self.TitleBar:SetScript("OnLeave", nil)
    end
end

----------------------------------------------------------------------
-- Get the current player's class color
----------------------------------------------------------------------
function TTQ:GetClassColor()
    local _, class = UnitClass("player")
    if class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class] then
        local c = RAID_CLASS_COLORS[class]
        return c.r, c.g, c.b
    end
    return 0.48, 0.58, 0.82 -- fallback: soft blue
end

----------------------------------------------------------------------
-- Backdrop styling — glassmorphic: rounded border, class gradient
----------------------------------------------------------------------
function TTQ:UpdateTrackerBackdrop()
    if not self.Tracker then return end
    local tracker = self.Tracker

    -- Clean up previous glass layers if they exist
    if tracker._glassLayers then
        for _, tex in ipairs(tracker._glassLayers) do
            tex:Hide()
            tex:SetParent(nil)
        end
    end
    tracker._glassLayers = {}

    if self:GetSetting("showBackground") then
        local bgAlpha = self:GetSetting("bgAlpha")
        local cr, cg, cb = self:GetClassColor()
        local useGradient = self:GetSetting("classColorGradient")

        -- Rounded backdrop with soft border
        tracker:SetBackdrop({
            bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile     = true,
            tileSize = 16,
            edgeSize = 14,
            insets   = { left = 4, right = 4, top = 4, bottom = 4 },
        })
        -- Dark frosted base
        tracker:SetBackdropColor(0.04, 0.04, 0.06, bgAlpha * 0.92)

        if useGradient then
            -- Subtle class-tinted border
            tracker:SetBackdropBorderColor(cr * 0.4, cg * 0.4, cb * 0.4, bgAlpha * 0.55)

            -- === Class color gradient: top-left corner wash ===
            -- Vertical gradient: class color at top fading to transparent at ~60% height
            local gradV = tracker:CreateTexture(nil, "BACKGROUND", nil, 1)
            gradV:SetTexture("Interface\\Buttons\\WHITE8x8")
            gradV:SetPoint("TOPLEFT", tracker, "TOPLEFT", 4, -4)
            gradV:SetPoint("TOPRIGHT", tracker, "TOPRIGHT", -4, -4)
            gradV:SetHeight(120)
            gradV:SetGradient("VERTICAL",
                CreateColor(cr, cg, cb, 0),
                CreateColor(cr, cg, cb, bgAlpha * 0.18))
            tracker._glassLayers[#tracker._glassLayers + 1] = gradV

            -- Horizontal gradient: class color from left edge fading right
            local gradH = tracker:CreateTexture(nil, "BACKGROUND", nil, 2)
            gradH:SetTexture("Interface\\Buttons\\WHITE8x8")
            gradH:SetPoint("TOPLEFT", tracker, "TOPLEFT", 4, -4)
            gradH:SetPoint("BOTTOMLEFT", tracker, "BOTTOMLEFT", 4, 4)
            gradH:SetWidth(100)
            gradH:SetGradient("HORIZONTAL",
                CreateColor(cr, cg, cb, bgAlpha * 0.12),
                CreateColor(cr, cg, cb, 0))
            tracker._glassLayers[#tracker._glassLayers + 1] = gradH

            -- Top-left corner accent: brighter class glow
            local cornerGlow = tracker:CreateTexture(nil, "BACKGROUND", nil, 3)
            cornerGlow:SetTexture("Interface\\Buttons\\WHITE8x8")
            cornerGlow:SetSize(60, 40)
            cornerGlow:SetPoint("TOPLEFT", tracker, "TOPLEFT", 4, -4)
            cornerGlow:SetGradient("HORIZONTAL",
                CreateColor(cr, cg, cb, bgAlpha * 0.15),
                CreateColor(cr, cg, cb, 0))
            tracker._glassLayers[#tracker._glassLayers + 1] = cornerGlow

            -- Inner highlight: thin white line at top for the "glass edge" reflection
            local glassEdge = tracker:CreateTexture(nil, "ARTWORK", nil, -1)
            glassEdge:SetTexture("Interface\\Buttons\\WHITE8x8")
            glassEdge:SetHeight(1)
            glassEdge:SetPoint("TOPLEFT", tracker, "TOPLEFT", 6, -5)
            glassEdge:SetPoint("TOPRIGHT", tracker, "TOPRIGHT", -6, -5)
            glassEdge:SetGradient("HORIZONTAL",
                CreateColor(1, 1, 1, bgAlpha * 0.12),
                CreateColor(1, 1, 1, 0.02))
            tracker._glassLayers[#tracker._glassLayers + 1] = glassEdge
        else
            -- Plain dark border (no class color tint)
            tracker:SetBackdropBorderColor(0.2, 0.2, 0.2, bgAlpha * 0.55)
        end
    else
        tracker:SetBackdrop(nil)
    end
end

----------------------------------------------------------------------
-- Fade helper
----------------------------------------------------------------------
function TTQ:SetFadeIfEnabled(frame)
    if self:GetSetting("fadeWhenNotHovered") then
        frame:SetAlpha(self:GetSetting("fadeAlpha"))
    else
        frame:SetAlpha(1)
    end
end

----------------------------------------------------------------------
-- Update scroll indicators based on current scroll position
-- Positions corner marks just below the last visible content line
----------------------------------------------------------------------
function TTQ:UpdateScrollFades()
    if not self.ScrollFrame or not self.ScrollCorners then return end
    local maxScroll = self.ScrollFrame:GetVerticalScrollRange() or 0

    -- Show corner marks when content is scrollable (overflows)
    local show = maxScroll > 2
    if show then
        for _, tex in ipairs(self.ScrollCorners) do
            tex:ClearAllPoints()
            tex:Show()
        end
        -- Anchor to the scroll frame bottom-right
        self.ScrollCorners[1]:SetPoint("BOTTOMRIGHT", self.ScrollFrame, "BOTTOMRIGHT", 0, -2)
        self.ScrollCorners[2]:SetPoint("BOTTOMRIGHT", self.ScrollFrame, "BOTTOMRIGHT", 0, -2)
    else
        for _, tex in ipairs(self.ScrollCorners) do
            tex:Hide()
        end
    end
end

----------------------------------------------------------------------
-- File-scope event frames — registered during addon loading (clean
-- execution context) so Frame:RegisterEvent() never triggers
-- ADDON_ACTION_FORBIDDEN.
----------------------------------------------------------------------
do
    -- Quest-related events
    local qf = CreateFrame("Frame")
    TTQ._questEventFrame = qf

    local questEvents = {
        "QUEST_LOG_UPDATE",
        "QUEST_WATCH_LIST_CHANGED",
        "QUEST_ACCEPTED",
        "QUEST_REMOVED",
        "QUEST_TURNED_IN",
        "SUPER_TRACKING_CHANGED",
        "ZONE_CHANGED_NEW_AREA",
        "ZONE_CHANGED",
        "PLAYER_ENTERING_WORLD",
        "UNIT_QUEST_LOG_CHANGED",
        "QUEST_POI_UPDATE",
        -- Recipe tracking events
        "TRACKED_RECIPE_UPDATE",
        "BAG_UPDATE",
        "BAG_UPDATE_DELAYED",
        "TRADE_SKILL_LIST_UPDATE",
        "CRAFTINGORDERS_RECIPE_LIST_UPDATE",
    }
    for _, ev in ipairs(questEvents) do
        pcall(qf.RegisterEvent, qf, ev)
    end
    qf:SetScript("OnEvent", function()
        if not TTQ._refreshTimer then
            TTQ._refreshTimer = C_Timer.NewTimer(0.1, function()
                TTQ._refreshTimer = nil
                if TTQ.RefreshTracker then
                    TTQ:RefreshTracker()
                end
            end)
        end
    end)

    -- Scenario / dungeon events
    local sf = CreateFrame("Frame")
    TTQ._scenarioEventFrame = sf

    local scenarioEvents = {
        "SCENARIO_UPDATE",
        "SCENARIO_CRITERIA_UPDATE",
        "SCENARIO_COMPLETED",
        "ENCOUNTER_END",
        "INSTANCE_ENCOUNTER_ENGAGE_UNIT",
        "BOSS_KILL",
        "UPDATE_INSTANCE_INFO",
    }
    for _, ev in ipairs(scenarioEvents) do
        pcall(sf.RegisterEvent, sf, ev)
    end
    sf:SetScript("OnEvent", function()
        if not TTQ._refreshTimer then
            TTQ._refreshTimer = C_Timer.NewTimer(0.1, function()
                TTQ._refreshTimer = nil
                if TTQ.RefreshTracker then
                    TTQ:RefreshTracker()
                end
            end)
        end
    end)

    -- Combat hiding (enter / leave combat)
    local cf = CreateFrame("Frame")
    TTQ._combatEventFrame = cf
    cf:RegisterEvent("PLAYER_REGEN_DISABLED")
    cf:RegisterEvent("PLAYER_REGEN_ENABLED")
    cf:SetScript("OnEvent", function(_, evt)
        if not TTQ.Tracker then return end
        if not TTQ.GetSetting then return end
        if not TTQ:GetSetting("hideInCombat") then return end
        -- Never hide the tracker during an active M+ run — the timer
        -- is critical information that must always be visible.
        if TTQ.IsMythicPlusActive and TTQ:IsMythicPlusActive() then return end
        if evt == "PLAYER_REGEN_DISABLED" then
            TTQ.Tracker:Hide()
        elseif evt == "PLAYER_REGEN_ENABLED" then
            TTQ.Tracker:Show()
        end
    end)
end

----------------------------------------------------------------------
-- Scenario / dungeon / boss tracking data
----------------------------------------------------------------------
function TTQ:GetScenarioInfo()
    if not C_Scenario or not C_Scenario.GetInfo then return nil end
    local name, instanceType, _, difficultyName, maxPlayers,
    _, _, _, _, scenarioType = C_Scenario.GetInfo()
    if not name or name == "" then return nil end

    local result = {
        name = name,
        instanceType = instanceType,
        difficultyName = difficultyName or "",
        maxPlayers = maxPlayers or 0,
        scenarioType = scenarioType,
        stages = {},
        bosses = {},
    }

    -- Scenario stages / criteria
    local numStages = C_Scenario.GetStepInfo and select(3, C_Scenario.GetStepInfo()) or 0
    if C_Scenario.GetStepInfo then
        local stageName, stageDesc, numCriteria, _, _, _, _, numSpells, spellInfo, weightedProgress
                                                                                                    = C_Scenario
            .GetStepInfo()
        result.stageName                                                                            = stageName or ""
        result.stageDesc                                                                            = stageDesc or ""
        result.numCriteria                                                                          = numCriteria or 0

        -- Get criteria (objectives/bosses)
        if numCriteria and numCriteria > 0 then
            for i = 1, numCriteria do
                local criteriaInfo = C_ScenarioInfo and C_ScenarioInfo.GetCriteriaInfo
                    and C_ScenarioInfo.GetCriteriaInfo(i)
                if criteriaInfo then
                    result.stages[#result.stages + 1] = {
                        description = criteriaInfo.description or "",
                        completed = criteriaInfo.completed or false,
                        quantity = criteriaInfo.quantity or 0,
                        totalQuantity = criteriaInfo.totalQuantity or 0,
                    }
                else
                    -- Fallback: try legacy GetCriteriaInfo
                    local desc, _, completed, qty, totalQty =
                        C_Scenario.GetCriteriaInfo(i)
                    if desc then
                        result.stages[#result.stages + 1] = {
                            description = desc,
                            completed = completed or false,
                            quantity = qty or 0,
                            totalQuantity = totalQty or 0,
                        }
                    end
                end
            end
        end
    end

    -- Dungeon boss info via encounter journal
    local _, _, _, _, _, _, _, instanceID = GetInstanceInfo()
    if instanceID and instanceID > 0 and C_EncounterJournal then
        -- Track killed bosses via saved instance info
        local numBosses = 0
        local numKilled = 0
        if C_Scenario.GetStepInfo then
            for _, stage in ipairs(result.stages) do
                numBosses = numBosses + 1
                if stage.completed then
                    numKilled = numKilled + 1
                end
            end
        end
        result.numBosses = numBosses
        result.numBossesKilled = numKilled
    end

    return result
end

----------------------------------------------------------------------
-- Main refresh: rebuild the entire tracker display
----------------------------------------------------------------------
function TTQ:RefreshTracker()
    if not self.Tracker or not self.Content then return end

    -- Save scroll position before rebuilding
    local savedScroll = self.ScrollFrame and self.ScrollFrame:GetVerticalScroll() or 0

    -- Update header visibility
    self:UpdateHeaderVisibility()
    local headerHeight = self.TitleBar:GetHeight() + (self:GetSetting("showTrackerHeader") and 4 or 2)

    -- Release all group containers (each holds header + quest items)
    for _, gc in ipairs(activeGroupContainers) do
        ReleaseGroupContainer(gc)
    end
    wipe(activeGroupContainers)
    wipe(activeQuestItems)
    wipe(activeHeaders)

    -- Check collapsed state
    local collapsed = self:GetSetting("collapsed")
    local isMythicPlus = self:IsMythicPlusActive()

    -- During an active M+ run, always keep Content visible so the timer
    -- and tracker remain on screen (even when the tracker is collapsed).
    if collapsed and isMythicPlus then
        self.Content:SetShown(true)
    else
        self.Content:SetShown(not collapsed)
    end

    if collapsed and not isMythicPlus then
        self.CollapseBtn:SetNormalTexture("Interface\\Buttons\\UI-PlusButton-UP")
        self.CollapseBtn:GetNormalTexture():SetDesaturated(true)
        self.CollapseBtn:GetNormalTexture():SetVertexColor(0.85, 0.85, 0.85)
        self.TitleText:SetText("Quests")
        self.Tracker:SetHeight(headerHeight)
        return
    end

    -- When collapsed during M+, show PlusButton but don't return early
    -- so the M+ block still renders below.
    if collapsed and isMythicPlus then
        self.CollapseBtn:SetNormalTexture("Interface\\Buttons\\UI-PlusButton-UP")
        self.CollapseBtn:GetNormalTexture():SetDesaturated(true)
        self.CollapseBtn:GetNormalTexture():SetVertexColor(0.85, 0.85, 0.85)
    else
        self.CollapseBtn:SetNormalTexture("Interface\\Buttons\\UI-MinusButton-UP")
        self.CollapseBtn:GetNormalTexture():SetDesaturated(true)
        self.CollapseBtn:GetNormalTexture():SetVertexColor(0.85, 0.85, 0.85)
    end
    -- Get data
    local quests = self:GetTrackedQuests()

    -- Merge active world quests (player is in the quest area) if enabled
    if self:GetSetting("showActiveWorldQuests") and self:GetSetting("showWorldQuests") ~= false then
        local activeWQs = self:GetActiveWorldQuests()
        if activeWQs and #activeWQs > 0 then
            -- Build a set of already-tracked quest IDs to avoid duplicates
            local trackedIDs = {}
            for _, q in ipairs(quests) do
                trackedIDs[q.questID] = true
            end
            for _, wq in ipairs(activeWQs) do
                if not trackedIDs[wq.questID] then
                    table.insert(quests, wq)
                end
            end
        end
    end

    local _, groups = self:FilterAndGroupQuests(quests)

    -- Zone label (truncate so it doesn't overlap header)
    if self:GetSetting("filterByCurrentZone") then
        local mapID = self:GetCurrentZoneMapID()
        local mapInfo = mapID and C_Map.GetMapInfo(mapID)
        local zoneName = mapInfo and mapInfo.name or "Zone"
        self.ZoneLabel:SetText(self:Truncate(zoneName, 14))
    else
        self.ZoneLabel:SetText("")
    end

    -- Layout
    local width = self:GetSetting("trackerWidth") - 16 -- padding
    local yOffset = 0
    local totalQuests = 0
    local maxQuests = self:GetSetting("maxQuests")
    local padding = self:GetSetting("bgPadding")
    local collapsedGroups = self:GetSetting("collapsedGroups") or {}

    -- === Mythic+ Block (supersedes scenario when active) ===
    -- (isMythicPlus already computed above for collapse logic)
    if isMythicPlus then
        local mpHeight = self:RenderMythicPlusBlock(self.Content, width, yOffset)
        yOffset = yOffset + mpHeight
    else
        -- Hide M+ display if it was previously shown
        self:HideMythicPlusDisplay()
    end

    -- === Scenario / Dungeon Block (skipped during M+ — already shown above) ===
    local scenarioInfo = not isMythicPlus and self:GetScenarioInfo() or nil
    if scenarioInfo and #scenarioInfo.stages > 0 then
        local gc = AcquireGroupContainer(self.Content)
        gc.frame:ClearAllPoints()
        gc.frame:SetPoint("TOPLEFT", self.Content, "TOPLEFT", 0, -yOffset)
        gc.frame:SetWidth(width)
        gc.questType = "_scenario"

        local header = AcquireHeader(gc.frame)
        gc.header = header
        header.frame:ClearAllPoints()
        header.frame:SetPoint("TOPLEFT", gc.frame, "TOPLEFT", 0, 0)
        header.frame:SetWidth(width)
        header.frame:SetHeight(SECTION_HEADER_HEIGHT)

        local headerSize = self:GetSetting("headerFontSize")
        local headerFont = self:GetResolvedFont("header")
        local headerOutline = self:GetSetting("headerFontOutline")
        local headerColor = self:GetSetting("headerColor")
        if not pcall(header.text.SetFont, header.text, headerFont, headerSize, headerOutline) then
            pcall(header.text.SetFont, header.text, "Fonts\\FRIZQT__.TTF", headerSize, headerOutline)
        end
        header.text:SetTextColor(headerColor.r, headerColor.g, headerColor.b)

        local headerLabel = scenarioInfo.name
        if scenarioInfo.difficultyName and scenarioInfo.difficultyName ~= ""
            and not tonumber(scenarioInfo.difficultyName) then
            headerLabel = headerLabel .. " (" .. scenarioInfo.difficultyName .. ")"
        end
        header.text:SetText(headerLabel)

        if self:GetSetting("showIcons") then
            local iconSize = math.max(10, headerSize - 1)
            pcall(header.icon.SetAtlas, header.icon, "Dungeon", false)
            header.icon:SetSize(iconSize, iconSize)
            header.icon:SetDesaturated(false)
            header.icon:SetVertexColor(1, 1, 1)
            header.icon:Show()
        else
            header.icon:Hide()
            header.text:SetPoint("LEFT", header.frame, "LEFT", 0, 0)
        end

        local isScenarioCollapsed = collapsedGroups["_scenario"] and true or false

        local numDone = 0
        for _, s in ipairs(scenarioInfo.stages) do
            if s.completed then numDone = numDone + 1 end
        end
        if self:GetSetting("showHeaderCount") then
            header.count:SetText(numDone .. "/" .. #scenarioInfo.stages)
            header.count:Show()
        else
            header.count:Hide()
        end
        header.collapseInd:SetText(isScenarioCollapsed and "+" or "-")
        -- Style the collapse indicator to match quest name font
        local indFont = self:GetResolvedFont("quest")
        local indSize = self:GetSetting("questNameFontSize")
        local indOutline = self:GetSetting("questNameFontOutline")
        if not pcall(header.collapseInd.SetFont, header.collapseInd, indFont, indSize, indOutline) then
            pcall(header.collapseInd.SetFont, header.collapseInd, "Fonts\\FRIZQT__.TTF", indSize, indOutline)
        end
        header.collapseInd:SetTextColor(1, 1, 1)

        -- Click: toggle collapse/expand instantly
        header.frame:SetScript("OnClick", function()
            local cg = TTQ:GetSetting("collapsedGroups")
            if type(cg) ~= "table" then cg = {} end
            cg = TTQ:DeepCopy(cg)
            cg["_scenario"] = not cg["_scenario"] and true or false
            TTQ:SetSetting("collapsedGroups", cg)
            TTQ:RefreshTracker()
        end)

        header.frame:SetScript("OnEnter", function(btn)
            GameTooltip:SetOwner(btn, "ANCHOR_LEFT")
            GameTooltip:SetText(scenarioInfo.name, 1, 1, 1)
            if scenarioInfo.stageName and scenarioInfo.stageName ~= "" then
                GameTooltip:AddLine(scenarioInfo.stageName, 0.8, 0.8, 0.8)
            end
            if scenarioInfo.stageDesc and scenarioInfo.stageDesc ~= "" then
                GameTooltip:AddLine(scenarioInfo.stageDesc, 0.6, 0.6, 0.6, true)
            end
            GameTooltip:AddLine(isScenarioCollapsed and "Click to expand" or "Click to collapse", 0.7, 0.7, 0.7)
            GameTooltip:Show()
        end)
        header.frame:SetScript("OnLeave", function() GameTooltip:Hide() end)

        table.insert(activeHeaders, header)
        local groupContentHeight = SECTION_HEADER_HEIGHT + 2

        -- Boss objectives (skip if collapsed)
        if not isScenarioCollapsed then
            local yInGroup = 0
            local objFontSize = self:GetSetting("objectiveFontSize")
            local objFont = self:GetResolvedFont("objective")
            local objOutline = self:GetSetting("objectiveFontOutline")
            local completeColor = self:GetSetting("objectiveCompleteColor")
            local incompleteColor = self:GetSetting("objectiveIncompleteColor")
            -- Indent to align objective text with quest names under category headers
            local scenarioIndent = 16 -- matches FOCUS_ICON_WIDTH (14) + 2 from QuestItem.lua

            for _, criteria in ipairs(scenarioInfo.stages) do
                local objItem = self:AcquireObjectiveItem(gc.contentFrame)
                objItem.frame:SetWidth(width - scenarioIndent)
                if not pcall(objItem.text.SetFont, objItem.text, objFont, objFontSize, objOutline) then
                    pcall(objItem.text.SetFont, objItem.text, "Fonts\\FRIZQT__.TTF", objFontSize, objOutline)
                end
                if not pcall(objItem.dash.SetFont, objItem.dash, objFont, objFontSize, objOutline) then
                    pcall(objItem.dash.SetFont, objItem.dash, "Fonts\\FRIZQT__.TTF", objFontSize, objOutline)
                end
                if criteria.completed then
                    objItem.text:SetTextColor(completeColor.r, completeColor.g, completeColor.b)
                    objItem.dash:SetTextColor(completeColor.r, completeColor.g, completeColor.b)
                    objItem.dash:SetText("|T Interface\\RaidFrame\\ReadyCheck-Ready:" .. objFontSize .. "|t")
                else
                    objItem.text:SetTextColor(incompleteColor.r, incompleteColor.g, incompleteColor.b)
                    objItem.dash:SetTextColor(incompleteColor.r, incompleteColor.g, incompleteColor.b)
                    objItem.dash:SetText("-")
                end
                local desc = criteria.description
                if criteria.totalQuantity and criteria.totalQuantity > 1 then
                    desc = desc .. " (" .. criteria.quantity .. "/" .. criteria.totalQuantity .. ")"
                end
                objItem.text:SetText(desc)
                objItem.frame:SetHeight(16)
                objItem.frame:ClearAllPoints()
                objItem.frame:SetPoint("TOPLEFT", gc.contentFrame, "TOPLEFT", scenarioIndent, -yInGroup)
                if not gc._scenarioObjItems then gc._scenarioObjItems = {} end
                gc._scenarioObjItems[#gc._scenarioObjItems + 1] = objItem
                yInGroup = yInGroup + 16 + 2
            end

            gc.contentFrame:SetHeight(math.max(1, yInGroup))
            groupContentHeight = groupContentHeight + yInGroup
        else
            gc.contentFrame:SetHeight(0)
        end

        groupContentHeight = groupContentHeight + SECTION_GROUP_SPACING
        gc.frame:SetHeight(groupContentHeight)
        gc.fullHeight = groupContentHeight
        gc.startY = yOffset
        table.insert(activeGroupContainers, gc)
        yOffset = yOffset + groupContentHeight
    end

    -- === Recipe Tracking Block ===
    if not isMythicPlus and self.RenderRecipeBlock then
        local recipeHeight = self:RenderRecipeBlock(self.Content, width, yOffset)
        yOffset = yOffset + recipeHeight
    elseif self.HideRecipeDisplay then
        self:HideRecipeDisplay()
    end

    -- Skip all quest categories when Mythic+ is active (M+ block is the sole display)
    for _, group in ipairs(isMythicPlus and {} or groups) do
        if totalQuests >= maxQuests then break end

        local questType = group.questType
        local isGroupCollapsed = collapsedGroups[questType] and true or false

        -- Group container (header + content area for quests)
        local gc = AcquireGroupContainer(self.Content)
        gc.frame:ClearAllPoints()
        gc.frame:SetPoint("TOPLEFT", self.Content, "TOPLEFT", 0, -yOffset)
        gc.frame:SetWidth(width)
        gc.questType = questType

        -- Header inside container
        local header = AcquireHeader(gc.frame)
        gc.header = header
        header.frame:ClearAllPoints()
        header.frame:SetPoint("TOPLEFT", gc.frame, "TOPLEFT", 0, 0)
        header.frame:SetWidth(width)
        header.frame:SetHeight(SECTION_HEADER_HEIGHT)

        local headerSize = self:GetSetting("headerFontSize")
        local headerFont = self:GetResolvedFont("header")
        local headerOutline = self:GetSetting("headerFontOutline")
        local headerColor = self:GetSetting("headerColor")
        if not pcall(header.text.SetFont, header.text, headerFont, headerSize, headerOutline) then
            pcall(header.text.SetFont, header.text, "Fonts\\FRIZQT__.TTF", headerSize, headerOutline)
        end
        header.text:SetTextColor(headerColor.r, headerColor.g, headerColor.b)
        header.text:SetText(group.headerName)

        local atlas = self.QuestIcons[questType]
        -- Zone group gets a map-pin icon
        if questType == "_zone" then
            atlas = "Waypoint-MapPin-ChatIcon"
        end
        if atlas and self:GetSetting("showIcons") then
            local iconSize = math.max(10, headerSize - 1)
            -- Raid and Dungeon atlas icons render visually smaller; bump them up
            if questType == "raid" or questType == "dungeon" then
                iconSize = iconSize + 4
            end
            header.icon:SetAtlas(atlas, false)
            header.icon:SetSize(iconSize, iconSize)
            header.icon:SetDesaturated(false)
            header.icon:SetVertexColor(1, 1, 1)
            header.icon:Show()
        else
            header.icon:Hide()
            header.text:SetPoint("LEFT", header.frame, "LEFT", 0, 0)
        end

        if self:GetSetting("showHeaderCount") then
            local numComplete = 0
            for _, q in ipairs(group.quests) do
                if q.isComplete then numComplete = numComplete + 1 end
            end
            header.count:SetText(numComplete .. "/" .. #group.quests)
            -- Apply correct font to count
            local countSize = math.max(9, headerSize - 2)
            if not pcall(header.count.SetFont, header.count, headerFont, countSize, headerOutline) then
                pcall(header.count.SetFont, header.count, "Fonts\\FRIZQT__.TTF", countSize, headerOutline)
            end
            if numComplete == #group.quests and #group.quests > 0 then
                local ec = self:GetSetting("objectiveCompleteColor")
                header.count:SetTextColor(ec.r, ec.g, ec.b)
            else
                header.count:SetTextColor(0.6, 0.6, 0.6)
            end
            header.count:Show()
        else
            header.count:Hide()
        end

        header.collapseInd:SetText(isGroupCollapsed and "+" or "-")
        -- Style the collapse indicator to match quest name font
        do
            local indFont = self:GetResolvedFont("quest")
            local indSize = self:GetSetting("questNameFontSize")
            local indOutline = self:GetSetting("questNameFontOutline")
            if not pcall(header.collapseInd.SetFont, header.collapseInd, indFont, indSize, indOutline) then
                pcall(header.collapseInd.SetFont, header.collapseInd, "Fonts\\FRIZQT__.TTF", indSize, indOutline)
            end
            header.collapseInd:SetTextColor(1, 1, 1)
        end

        -- Click: toggle collapse/expand instantly
        header.frame:SetScript("OnClick", function()
            local cg = TTQ:GetSetting("collapsedGroups")
            if type(cg) ~= "table" then cg = {} end
            cg = TTQ:DeepCopy(cg)
            cg[questType] = not cg[questType] and true or false
            TTQ:SetSetting("collapsedGroups", cg)
            TTQ:RefreshTracker()
        end)

        header.frame:SetScript("OnEnter", function(btn)
            GameTooltip:SetOwner(btn, "ANCHOR_LEFT")
            GameTooltip:SetText(group.headerName)
            GameTooltip:AddLine(isGroupCollapsed and "Click to expand" or "Click to collapse", 0.7, 0.7, 0.7)
            GameTooltip:Show()
        end)
        header.frame:SetScript("OnLeave", function() GameTooltip:Hide() end)

        table.insert(activeHeaders, header)
        local groupContentHeight = SECTION_HEADER_HEIGHT + 2

        -- Quest items inside container content frame (or skip if collapsed)
        if not isGroupCollapsed then
            local yInGroup = 0
            for _, quest in ipairs(group.quests) do
                if totalQuests >= maxQuests then break end

                local questItem = self:AcquireQuestItem(gc.contentFrame)
                self:UpdateQuestItem(questItem, quest, width)
                local itemHeight = self:LayoutQuestItem(questItem, yInGroup)
                itemHeight = math.max(20, itemHeight)

                questItem.frame:ClearAllPoints()
                questItem.frame:SetPoint("TOPLEFT", gc.contentFrame, "TOPLEFT", 4, -yInGroup)
                questItem.frame:SetWidth(width - 4)
                questItem.frame:SetHeight(itemHeight)

                -- Store layout data for per-quest animation
                questItem._layoutY = yInGroup
                questItem._gcQuestItems = gc.questItems
                questItem._contentFrame = gc.contentFrame
                questItem._gcFrame = gc.frame

                table.insert(gc.questItems, questItem)
                table.insert(activeQuestItems, questItem)
                yInGroup = yInGroup + itemHeight + 2
                totalQuests = totalQuests + 1
            end
            gc.contentFrame:SetHeight(math.max(1, yInGroup))
            groupContentHeight = groupContentHeight + yInGroup
        else
            gc.contentFrame:SetHeight(0)
        end

        groupContentHeight = groupContentHeight + SECTION_GROUP_SPACING
        gc.frame:SetHeight(groupContentHeight)
        gc.fullHeight = groupContentHeight
        gc.startY = yOffset
        table.insert(activeGroupContainers, gc)
        yOffset = yOffset + groupContentHeight
    end

    -- Update title and its font
    local totalTracked = 0
    for _, g in ipairs(groups) do totalTracked = totalTracked + #g.quests end
    if isMythicPlus then
        -- During M+, show key info in the title
        local mpData = self:GetMythicPlusData()
        if mpData and mpData.keystoneLevel > 0 then
            self.TitleText:SetText("Mythic+ (" .. "+" .. mpData.keystoneLevel .. ")")
        else
            self.TitleText:SetText("Mythic+")
        end
    elseif self:GetSetting("showHeaderCount") then
        self.TitleText:SetText("Quests (" .. totalTracked .. ")")
    else
        self.TitleText:SetText("Quests")
    end
    local titleFont = self:GetResolvedFont("header")
    local titleSize = self:GetSetting("headerFontSize") + 1
    local titleOutline = self:GetSetting("headerFontOutline")
    if not pcall(self.TitleText.SetFont, self.TitleText, titleFont, titleSize, titleOutline or "") then
        pcall(self.TitleText.SetFont, self.TitleText, "Fonts\\FRIZQT__.TTF", titleSize, titleOutline or "")
    end

    -- Resize tracker to fit content, capped at max height
    local contentHeight = math.max(1, yOffset)
    self.Content:SetHeight(contentHeight)
    self.Content:SetWidth(width)

    local maxHeight = self:GetSetting("trackerMaxHeight") or 600
    local naturalHeight = headerHeight + contentHeight + padding * 2
    local scrollAreaHeight = contentHeight + padding

    if naturalHeight > maxHeight and maxHeight > headerHeight + 20 then
        -- Cap tracker height; scroll frame gets the remaining space
        self.Tracker:SetHeight(maxHeight)
        local scrollHeight = maxHeight - headerHeight - padding
        self.ScrollFrame:SetHeight(scrollHeight)
    else
        self.Tracker:SetHeight(naturalHeight)
        self.ScrollFrame:SetHeight(scrollAreaHeight)
    end
    -- Restore scroll position immediately (clamp to new range)
    local maxScrollRange = self.ScrollFrame:GetVerticalScrollRange() or 0
    self.ScrollFrame:SetVerticalScroll(math.min(savedScroll, maxScrollRange))
    self:UpdateScrollFades()
end

----------------------------------------------------------------------
-- Hide/disable Blizzard's ObjectiveTrackerFrame
-- Uses non-tainting approach: alpha/scale tricks + hook to prevent Show
----------------------------------------------------------------------
function TTQ:HideBlizzardTracker()
    if not ObjectiveTrackerFrame then return end

    -- Create a dedicated untainted frame to handle the hiding
    if not self._blizzHiderFrame then
        self._blizzHiderFrame = CreateFrame("Frame")
        -- Wait until out of combat to manipulate the secure frame
        self._blizzHiderFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
        self._blizzHiderFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
        self._blizzHiderFrame:SetScript("OnEvent", function()
            if InCombatLockdown() then return end
            if ObjectiveTrackerFrame then
                ObjectiveTrackerFrame:SetAlpha(0)
                ObjectiveTrackerFrame:SetScale(0.001)
                -- Move it off-screen
                ObjectiveTrackerFrame:ClearAllPoints()
                ObjectiveTrackerFrame:SetPoint("TOPLEFT", UIParent, "BOTTOMRIGHT", 10000, -10000)
            end
        end)
    end

    -- Immediately apply if not in combat
    if not InCombatLockdown() then
        ObjectiveTrackerFrame:SetAlpha(0)
        ObjectiveTrackerFrame:SetScale(0.001)
        ObjectiveTrackerFrame:ClearAllPoints()
        ObjectiveTrackerFrame:SetPoint("TOPLEFT", UIParent, "BOTTOMRIGHT", 10000, -10000)
    end
end

----------------------------------------------------------------------
-- Elegant filter dropdown — cinematic dark theme, cursor-anchored,
-- atlas icons per quest type, pill toggles, Show/Hide All actions.
----------------------------------------------------------------------
local FILTER_DD = {
    Width       = 230,
    RowHeight   = 26,
    Padding     = 10,
    IconSize    = 16,
    ToggleW     = 32,
    ToggleH     = 16,
    ThumbSize   = 12,
    AnimDur     = 0.12,
    Font        = "Fonts\\FRIZQT__.TTF",
    -- Colors
    Bg          = { 0.06, 0.06, 0.08, 0.97 },
    Border      = { 0.22, 0.24, 0.30, 0.50 },
    TitleColor  = { 1, 0.82, 0 },
    SectionCol  = { 0.55, 0.60, 0.70 },
    LabelOn     = { 0.92, 0.92, 0.95 },
    LabelOff    = { 0.50, 0.50, 0.55 },
    TrackOn     = { 0.48, 0.58, 0.82, 0.90 },
    TrackOff    = { 0.14, 0.14, 0.18, 0.95 },
    Thumb       = { 1, 1, 1, 0.98 },
    HoverRow    = { 1, 1, 1, 0.05 },
    DividerCol  = { 0.30, 0.34, 0.42, 0.30 },
    ActionColor = { 0.60, 0.72, 0.95 },
    ActionHover = { 0.80, 0.88, 1.0 },
}

-- Atlas name to use for each filter row's icon
local FILTER_ICON_ATLAS = {
    showCampaign    = "Campaign-QuestLog-LoreBook",
    showImportant   = "quest-important-available",
    showLegendary   = "quest-legendary-available",
    showWorldQuests = "worldquest-tracker-questmarker",
    showCallings    = "quest-recurring-available",
    showDailies     = "quest-recurring-available",
    showWeeklies    = "quest-recurring-available",
    showDungeonRaid = "Dungeon",
    showSideQuests  = "QuestNormal",
    showMeta        = "quest-wrapper-available",
    showPvP         = "questlog-questtypeicon-pvp",
    showAccount     = "QuestSharing-QuestLog-Active",
}

----------------------------------------------------------------------
-- Pill toggle helper (mini version used inside the dropdown)
----------------------------------------------------------------------
local function CreateFilterToggle(parent, size)
    local tw, th = size or FILTER_DD.ToggleW, FILTER_DD.ToggleH
    local thumbSz = FILTER_DD.ThumbSize
    local inset = (th - thumbSz) / 2

    local track = CreateFrame("Frame", nil, parent)
    track:SetSize(tw, th)

    local trackBg = track:CreateTexture(nil, "BACKGROUND")
    trackBg:SetAllPoints()
    trackBg:SetColorTexture(FILTER_DD.TrackOff[1], FILTER_DD.TrackOff[2], FILTER_DD.TrackOff[3], FILTER_DD.TrackOff[4])

    local trackFill = track:CreateTexture(nil, "ARTWORK")
    trackFill:SetPoint("TOPLEFT")
    trackFill:SetPoint("BOTTOMLEFT")
    trackFill:SetWidth(0.01)
    trackFill:SetColorTexture(FILTER_DD.TrackOn[1], FILTER_DD.TrackOn[2], FILTER_DD.TrackOn[3], FILTER_DD.TrackOn[4])

    local thumb = track:CreateTexture(nil, "OVERLAY")
    thumb:SetSize(thumbSz, thumbSz)
    thumb:SetColorTexture(FILTER_DD.Thumb[1], FILTER_DD.Thumb[2], FILTER_DD.Thumb[3], FILTER_DD.Thumb[4])

    local travel = tw - thumbSz - inset * 2

    function track:SetState(on, instant)
        local target = on and 1 or 0
        if instant then
            track._pos = target
            thumb:ClearAllPoints()
            thumb:SetPoint("LEFT", track, "LEFT", inset + target * travel, 0)
            trackFill:SetWidth(math.max(0.01, target * tw))
            return
        end
        -- Animate
        local from = track._pos or 0
        track._animFrom = from
        track._animTo = target
        track._animStart = GetTime()
        track:SetScript("OnUpdate", function(self)
            local elapsed = GetTime() - self._animStart
            local t = math.min(elapsed / FILTER_DD.AnimDur, 1)
            t = 1 - (1 - t) * (1 - t) -- ease-out
            local pos = self._animFrom + (self._animTo - self._animFrom) * t
            self._pos = pos
            thumb:ClearAllPoints()
            thumb:SetPoint("LEFT", track, "LEFT", inset + pos * travel, 0)
            trackFill:SetWidth(math.max(0.01, pos * tw))
            if elapsed >= FILTER_DD.AnimDur then
                self._pos = self._animTo
                self:SetScript("OnUpdate", nil)
            end
        end)
    end

    return track
end

----------------------------------------------------------------------
-- Build the filter dropdown (called lazily once)
----------------------------------------------------------------------
function TTQ:CreateFilterDropdownFrame()
    if self.FilterDropdownFrame then return end

    local dd = FILTER_DD
    local frame = CreateFrame("Frame", "TTQFilterDropdown", UIParent, "BackdropTemplate")
    frame:SetWidth(dd.Width)
    frame:SetClampedToScreen(true)
    frame:SetFrameStrata("TOOLTIP")
    frame:SetFrameLevel(100)
    frame:SetBackdrop({
        bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 12,
        tile     = true,
        tileSize = 16,
        insets   = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    frame:SetBackdropColor(dd.Bg[1], dd.Bg[2], dd.Bg[3], dd.Bg[4])
    frame:SetBackdropBorderColor(dd.Border[1], dd.Border[2], dd.Border[3], dd.Border[4])
    frame:Hide()

    -- Fade-in on show
    frame:SetScript("OnShow", function(self)
        self:SetAlpha(0)
        self._fadeStart = GetTime()
        self:SetScript("OnUpdate", function(s)
            local t = math.min((GetTime() - s._fadeStart) / 0.12, 1)
            s:SetAlpha(t)
            if t >= 1 then s:SetScript("OnUpdate", nil) end
        end)
    end)
    frame:SetScript("OnHide", function(self)
        if self.clickCatcher and self.clickCatcher:IsShown() then
            self.clickCatcher:Hide()
        end
    end)

    -- Click-catcher: full-screen invisible button to dismiss on outside click
    local catcher = CreateFrame("Button", nil, UIParent)
    catcher:SetFrameStrata("TOOLTIP")
    catcher:SetFrameLevel(99)
    catcher:SetAllPoints(UIParent)
    catcher:EnableMouse(true)
    catcher:Hide()
    catcher:SetScript("OnClick", function()
        TTQ:HideFilterDropdown()
    end)
    frame.clickCatcher = catcher

    -- Inner content host
    local pad = dd.Padding
    local content = CreateFrame("Frame", nil, frame)
    content:SetPoint("TOPLEFT", frame, "TOPLEFT", pad, -pad)
    content:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -pad, -pad)
    frame.content = content

    --------------------------------------------------------------------
    -- Title row
    --------------------------------------------------------------------
    local title = content:CreateFontString(nil, "OVERLAY")
    title:SetFont(dd.Font, 13, "OUTLINE")
    title:SetTextColor(dd.TitleColor[1], dd.TitleColor[2], dd.TitleColor[3])
    title:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
    title:SetJustifyH("LEFT")
    title:SetText("Quest Filters")

    local y = -20

    --------------------------------------------------------------------
    -- Section: Zone Filter
    --------------------------------------------------------------------
    local secZone = content:CreateFontString(nil, "OVERLAY")
    secZone:SetFont(dd.Font, 10, "OUTLINE")
    secZone:SetTextColor(dd.SectionCol[1], dd.SectionCol[2], dd.SectionCol[3])
    secZone:SetPoint("TOPLEFT", content, "TOPLEFT", 0, y)
    secZone:SetJustifyH("LEFT")
    secZone:SetText("ZONE")
    y = y - 16

    -- Zone filter row
    local zoneRow = CreateFrame("Button", nil, content)
    zoneRow:SetHeight(dd.RowHeight)
    zoneRow:SetPoint("TOPLEFT", content, "TOPLEFT", 0, y)
    zoneRow:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, y)

    local zoneHl = zoneRow:CreateTexture(nil, "HIGHLIGHT")
    zoneHl:SetAllPoints()
    zoneHl:SetColorTexture(dd.HoverRow[1], dd.HoverRow[2], dd.HoverRow[3], dd.HoverRow[4])

    local zoneIcon = zoneRow:CreateTexture(nil, "ARTWORK")
    zoneIcon:SetSize(dd.IconSize, dd.IconSize)
    zoneIcon:SetPoint("LEFT", zoneRow, "LEFT", 2, 0)
    if C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo("Waypoint-MapPin-ChatIcon") then
        zoneIcon:SetAtlas("Waypoint-MapPin-ChatIcon", false)
    else
        zoneIcon:SetTexture("Interface\\Minimap\\Tracking\\None")
    end

    local zoneLabel = zoneRow:CreateFontString(nil, "OVERLAY")
    zoneLabel:SetFont(dd.Font, 12, "")
    zoneLabel:SetPoint("LEFT", zoneIcon, "RIGHT", 6, 0)
    zoneLabel:SetJustifyH("LEFT")
    zoneLabel:SetText("Current Zone Only")

    local zoneToggle = CreateFilterToggle(zoneRow)
    zoneToggle:SetPoint("RIGHT", zoneRow, "RIGHT", -2, 0)
    zoneRow.toggle = zoneToggle
    zoneRow.settingKey = "filterByCurrentZone"
    zoneRow.label = zoneLabel

    zoneRow:SetScript("OnClick", function()
        local cur = TTQ:GetSetting("filterByCurrentZone")
        TTQ:SetSetting("filterByCurrentZone", not cur)
        TTQ:RefreshFilterDropdown()
        TTQ:RefreshTracker()
    end)

    frame.zoneRow = zoneRow
    y = y - dd.RowHeight

    -- Group by zone row
    local groupZoneRow = CreateFrame("Button", nil, content)
    groupZoneRow:SetHeight(dd.RowHeight)
    groupZoneRow:SetPoint("TOPLEFT", content, "TOPLEFT", 0, y)
    groupZoneRow:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, y)

    local gzHl = groupZoneRow:CreateTexture(nil, "HIGHLIGHT")
    gzHl:SetAllPoints()
    gzHl:SetColorTexture(dd.HoverRow[1], dd.HoverRow[2], dd.HoverRow[3], dd.HoverRow[4])

    local gzIcon = groupZoneRow:CreateTexture(nil, "ARTWORK")
    gzIcon:SetSize(dd.IconSize, dd.IconSize)
    gzIcon:SetPoint("LEFT", groupZoneRow, "LEFT", 2, 0)
    if C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo("MapCornerShadow-Right") then
        gzIcon:SetAtlas("MapCornerShadow-Right", false)
    elseif C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo("Waypoint-MapPin-ChatIcon") then
        gzIcon:SetAtlas("Waypoint-MapPin-ChatIcon", false)
    else
        gzIcon:SetTexture("Interface\\Minimap\\Tracking\\None")
    end

    local gzLabel = groupZoneRow:CreateFontString(nil, "OVERLAY")
    gzLabel:SetFont(dd.Font, 12, "")
    gzLabel:SetPoint("LEFT", gzIcon, "RIGHT", 6, 0)
    gzLabel:SetJustifyH("LEFT")
    gzLabel:SetText("Group by Zone")

    local gzToggle = CreateFilterToggle(groupZoneRow)
    gzToggle:SetPoint("RIGHT", groupZoneRow, "RIGHT", -2, 0)
    groupZoneRow.toggle = gzToggle
    groupZoneRow.settingKey = "groupCurrentZoneQuests"
    groupZoneRow.label = gzLabel

    groupZoneRow:SetScript("OnClick", function()
        local cur = TTQ:GetSetting("groupCurrentZoneQuests")
        TTQ:SetSetting("groupCurrentZoneQuests", not cur)
        TTQ:RefreshFilterDropdown()
        TTQ:RefreshTracker()
    end)

    frame.groupZoneRow = groupZoneRow
    y = y - dd.RowHeight

    -- Active World Quests row
    local awqRow = CreateFrame("Button", nil, content)
    awqRow:SetHeight(dd.RowHeight)
    awqRow:SetPoint("TOPLEFT", content, "TOPLEFT", 0, y)
    awqRow:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, y)

    local awqHl = awqRow:CreateTexture(nil, "HIGHLIGHT")
    awqHl:SetAllPoints()
    awqHl:SetColorTexture(dd.HoverRow[1], dd.HoverRow[2], dd.HoverRow[3], dd.HoverRow[4])

    local awqIcon = awqRow:CreateTexture(nil, "ARTWORK")
    awqIcon:SetSize(dd.IconSize, dd.IconSize)
    awqIcon:SetPoint("LEFT", awqRow, "LEFT", 2, 0)
    if C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo("worldquest-tracker-questmarker") then
        awqIcon:SetAtlas("worldquest-tracker-questmarker", false)
    else
        awqIcon:SetTexture("Interface\\Minimap\\Tracking\\None")
    end

    local awqLabel = awqRow:CreateFontString(nil, "OVERLAY")
    awqLabel:SetFont(dd.Font, 12, "")
    awqLabel:SetPoint("LEFT", awqIcon, "RIGHT", 6, 0)
    awqLabel:SetJustifyH("LEFT")
    awqLabel:SetText("Active World Quests")

    local awqToggle = CreateFilterToggle(awqRow)
    awqToggle:SetPoint("RIGHT", awqRow, "RIGHT", -2, 0)
    awqRow.toggle = awqToggle
    awqRow.settingKey = "showActiveWorldQuests"
    awqRow.label = awqLabel

    awqRow:SetScript("OnClick", function()
        local cur = TTQ:GetSetting("showActiveWorldQuests")
        TTQ:SetSetting("showActiveWorldQuests", not cur)
        TTQ:RefreshFilterDropdown()
        TTQ:RefreshTracker()
    end)

    frame.awqRow = awqRow
    y = y - dd.RowHeight - 6

    --------------------------------------------------------------------
    -- Divider
    --------------------------------------------------------------------
    local divider1 = content:CreateTexture(nil, "ARTWORK")
    divider1:SetHeight(1)
    divider1:SetPoint("TOPLEFT", content, "TOPLEFT", 0, y)
    divider1:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, y)
    divider1:SetColorTexture(dd.DividerCol[1], dd.DividerCol[2], dd.DividerCol[3], dd.DividerCol[4])
    y = y - 8

    --------------------------------------------------------------------
    -- Section: Quest Types
    --------------------------------------------------------------------
    local secTypes = content:CreateFontString(nil, "OVERLAY")
    secTypes:SetFont(dd.Font, 10, "OUTLINE")
    secTypes:SetTextColor(dd.SectionCol[1], dd.SectionCol[2], dd.SectionCol[3])
    secTypes:SetPoint("TOPLEFT", content, "TOPLEFT", 0, y)
    secTypes:SetJustifyH("LEFT")
    secTypes:SetText("QUEST TYPES")
    y = y - 16

    -- Filter items list — order matches Config.lua priority
    local filterItems = {
        { setting = "showCampaign",    label = "Campaign",       icon = "campaign" },
        { setting = "showImportant",   label = "Important",      icon = "important" },
        { setting = "showLegendary",   label = "Legendary",      icon = "legendary" },
        { setting = "showWorldQuests", label = "World Quests",   icon = "worldquest" },
        { setting = "showCallings",    label = "Callings",       icon = "calling" },
        { setting = "showDailies",     label = "Dailies",        icon = "daily" },
        { setting = "showWeeklies",    label = "Weeklies",       icon = "weekly" },
        { setting = "showDungeonRaid", label = "Dungeon / Raid", icon = "dungeon" },
        { setting = "showSideQuests",  label = "Side Quests",    icon = "normal" },
        { setting = "showMeta",        label = "Meta Quests",    icon = "meta" },
        { setting = "showPvP",         label = "PvP",            icon = "pvp" },
        { setting = "showAccount",     label = "Account",        icon = "account" },
    }

    local rows = {}
    for _, entry in ipairs(filterItems) do
        local row = CreateFrame("Button", nil, content)
        row:SetHeight(dd.RowHeight)
        row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, y)
        row:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, y)

        -- Hover highlight
        local hl = row:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(dd.HoverRow[1], dd.HoverRow[2], dd.HoverRow[3], dd.HoverRow[4])

        -- Quest-type icon
        local icon = row:CreateTexture(nil, "ARTWORK")
        icon:SetSize(dd.IconSize, dd.IconSize)
        icon:SetPoint("LEFT", row, "LEFT", 2, 0)
        local atlasName = FILTER_ICON_ATLAS[entry.setting] or (TTQ.QuestIcons and TTQ.QuestIcons[entry.icon])
        if atlasName and C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlasName) then
            icon:SetAtlas(atlasName, false)
        else
            icon:SetTexture("Interface\\Minimap\\Tracking\\None")
        end
        row.icon = icon

        -- Label
        local lbl = row:CreateFontString(nil, "OVERLAY")
        lbl:SetFont(dd.Font, 12, "")
        lbl:SetPoint("LEFT", icon, "RIGHT", 6, 0)
        lbl:SetPoint("RIGHT", row, "RIGHT", -(dd.ToggleW + 10), 0)
        lbl:SetJustifyH("LEFT")
        lbl:SetText(entry.label)
        row.label = lbl

        -- Toggle pill
        local toggle = CreateFilterToggle(row)
        toggle:SetPoint("RIGHT", row, "RIGHT", -2, 0)
        row.toggle = toggle
        row.settingKey = entry.setting

        row:SetScript("OnClick", function()
            local cur = TTQ:GetSetting(entry.setting)
            TTQ:SetSetting(entry.setting, not cur)
            TTQ:RefreshFilterDropdown()
            TTQ:RefreshTracker()
        end)

        table.insert(rows, row)
        y = y - dd.RowHeight
    end
    frame.rows = rows

    --------------------------------------------------------------------
    -- Divider before actions
    --------------------------------------------------------------------
    y = y - 4
    local divider2 = content:CreateTexture(nil, "ARTWORK")
    divider2:SetHeight(1)
    divider2:SetPoint("TOPLEFT", content, "TOPLEFT", 0, y)
    divider2:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, y)
    divider2:SetColorTexture(dd.DividerCol[1], dd.DividerCol[2], dd.DividerCol[3], dd.DividerCol[4])
    y = y - 6

    --------------------------------------------------------------------
    -- Action row: Show All / Hide All
    --------------------------------------------------------------------
    local actionRow = CreateFrame("Frame", nil, content)
    actionRow:SetHeight(20)
    actionRow:SetPoint("TOPLEFT", content, "TOPLEFT", 0, y)
    actionRow:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, y)

    local function createActionLink(parent, text, xAnchor, onClick)
        local btn = CreateFrame("Button", nil, parent)
        btn:SetHeight(18)
        local fs = btn:CreateFontString(nil, "OVERLAY")
        fs:SetFont(dd.Font, 11, "")
        fs:SetTextColor(dd.ActionColor[1], dd.ActionColor[2], dd.ActionColor[3])
        fs:SetText(text)
        fs:SetPoint("LEFT")
        btn:SetWidth(fs:GetStringWidth() + 4)
        btn:SetPoint(xAnchor, parent, xAnchor, xAnchor == "LEFT" and 0 or 0, 0)
        fs:SetAllPoints()
        btn:SetScript("OnClick", onClick)
        btn:SetScript("OnEnter", function()
            fs:SetTextColor(dd.ActionHover[1], dd.ActionHover[2], dd.ActionHover[3])
        end)
        btn:SetScript("OnLeave", function()
            fs:SetTextColor(dd.ActionColor[1], dd.ActionColor[2], dd.ActionColor[3])
        end)
        return btn
    end

    createActionLink(actionRow, "Show All", "LEFT", function()
        for _, row in ipairs(rows) do
            TTQ:SetSetting(row.settingKey, true)
        end
        TTQ:RefreshFilterDropdown()
        TTQ:RefreshTracker()
    end)

    local sep = actionRow:CreateFontString(nil, "OVERLAY")
    sep:SetFont(dd.Font, 11, "")
    sep:SetTextColor(dd.SectionCol[1], dd.SectionCol[2], dd.SectionCol[3])
    sep:SetText("·")
    sep:SetPoint("CENTER", actionRow, "CENTER", 0, 0)

    createActionLink(actionRow, "Hide All", "RIGHT", function()
        for _, row in ipairs(rows) do
            TTQ:SetSetting(row.settingKey, false)
        end
        TTQ:RefreshFilterDropdown()
        TTQ:RefreshTracker()
    end)

    y = y - 22

    --------------------------------------------------------------------
    -- Finalize sizing
    --------------------------------------------------------------------
    local totalHeight = math.abs(y) + pad * 2
    content:SetHeight(math.max(1, math.abs(y)))
    frame:SetHeight(totalHeight)

    self.FilterDropdownFrame = frame
end

----------------------------------------------------------------------
-- Refresh toggle states and label colors
----------------------------------------------------------------------
function TTQ:RefreshFilterDropdown()
    local frame = self.FilterDropdownFrame
    if not frame then return end

    -- Zone row
    if frame.zoneRow then
        local on = self:GetSetting("filterByCurrentZone") and true or false
        frame.zoneRow.toggle:SetState(on, true)
        local col = on and FILTER_DD.LabelOn or FILTER_DD.LabelOff
        frame.zoneRow.label:SetTextColor(col[1], col[2], col[3])
    end

    -- Group by zone row
    if frame.groupZoneRow then
        local on = self:GetSetting("groupCurrentZoneQuests") and true or false
        frame.groupZoneRow.toggle:SetState(on, true)
        local col = on and FILTER_DD.LabelOn or FILTER_DD.LabelOff
        frame.groupZoneRow.label:SetTextColor(col[1], col[2], col[3])
    end

    -- Active World Quests row
    if frame.awqRow then
        local on = self:GetSetting("showActiveWorldQuests") and true or false
        frame.awqRow.toggle:SetState(on, true)
        local col = on and FILTER_DD.LabelOn or FILTER_DD.LabelOff
        frame.awqRow.label:SetTextColor(col[1], col[2], col[3])
    end

    -- Quest-type rows
    if frame.rows then
        for _, row in ipairs(frame.rows) do
            local on = self:GetSetting(row.settingKey) and true or false
            row.toggle:SetState(on, true)
            local col = on and FILTER_DD.LabelOn or FILTER_DD.LabelOff
            row.label:SetTextColor(col[1], col[2], col[3])
            if row.icon then
                row.icon:SetAlpha(on and 1 or 0.35)
                row.icon:SetDesaturated(not on)
            end
        end
    end
end

----------------------------------------------------------------------
-- Show near the cursor (clamped to screen) and dismiss on outside click
----------------------------------------------------------------------
function TTQ:ShowFilterDropdown(anchorFrame)
    self:CreateFilterDropdownFrame()
    local frame = self.FilterDropdownFrame
    if not frame then return end

    -- Toggle behavior: if already shown, just hide
    if frame:IsShown() then
        self:HideFilterDropdown()
        return
    end

    self:RefreshFilterDropdown()

    -- Position near the cursor so the dropdown feels attached to where the user clicked
    local scale  = frame:GetEffectiveScale()
    local cx, cy = GetCursorPosition()
    cx, cy       = cx / scale, cy / scale
    local fw, fh = frame:GetWidth(), frame:GetHeight()
    local sw, sh = UIParent:GetWidth(), UIParent:GetHeight()

    -- Default: place top-left of dropdown at cursor with small offset
    local left   = cx + 4
    local top    = cy + 4

    -- Clamp right edge
    if left + fw > sw then
        left = cx - fw - 4
    end
    -- Clamp bottom edge
    if top - fh < 0 then
        top = fh
    end
    -- Clamp top edge
    if top > sh then
        top = sh
    end
    -- Clamp left edge
    if left < 0 then
        left = 0
    end

    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
    frame:Show()

    if frame.clickCatcher then
        frame.clickCatcher:Show()
    end
end

----------------------------------------------------------------------
-- Hide the dropdown and its click-catcher
----------------------------------------------------------------------
function TTQ:HideFilterDropdown()
    if self.FilterDropdownFrame then
        self.FilterDropdownFrame:Hide()
    end
    if self.FilterDropdownFrame and self.FilterDropdownFrame.clickCatcher then
        self.FilterDropdownFrame.clickCatcher:Hide()
    end
end
