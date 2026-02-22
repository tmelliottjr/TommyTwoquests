----------------------------------------------------------------------
-- TommyTwoquests -- QuestItem.lua
-- Quest row: focus icon, quest name, per-quest collapse, click handlers
----------------------------------------------------------------------
local AddonName, TTQ = ...
local table, ipairs, pcall, CreateFrame, UIParent = table, ipairs, pcall, CreateFrame, UIParent
local C_SuperTrack, C_QuestLog, C_Texture = C_SuperTrack, C_QuestLog, C_Texture
local C_Timer = C_Timer
local wipe, math, string, GetTime, InCombatLockdown = wipe, math, string, GetTime, InCombatLockdown

-- Width reserved for focus icon on the left
local FOCUS_ICON_WIDTH = 14

-- Width of the quest item-use button on the right
local ITEM_BTN_SIZE = 20

-- Counter for unique secure button names
local itemBtnCounter = 0

-- Object pool for quest rows
local questItemPool = TTQ:CreateObjectPool(
    function(parent) return TTQ:CreateQuestItem(parent) end,
    function(item)
        if item.objectiveItems then
            for _, objItem in ipairs(item.objectiveItems) do
                TTQ:ReleaseObjectiveItem(objItem)
            end
            wipe(item.objectiveItems)
        end
        -- Clear stale visual state so recycled frames never show old content
        if item.name then item.name:SetText("") end
        if item.strikethrough then item.strikethrough:Hide() end
        if item.expandInd then item.expandInd:Hide() end
        -- Clear any running animation state
        item._animState = nil
        -- Reset hover color state so pooled items don't carry stale tints
        item._hoverAnimT = 0
        item.frame:SetScript("OnUpdate", nil)
        -- Reset focus icon position so world-quest offset doesn't leak
        if item.focusIcon then
            item.focusIcon:ClearAllPoints()
            item.focusIcon:SetPoint("TOPLEFT", item.frame, "TOPLEFT", 0, -4)
            item.focusIcon:SetAlpha(0)
        end
        -- Hide quest item button on release and reset parent/tracking
        if item.itemBtn then
            item.itemBtn:SetScript("OnUpdate", nil)
            item.itemBtn._trackFrame = nil
            item.itemBtn:SetParent(item.frame)
            item.itemBtn:Hide()
            item.itemBtn:SetAlpha(0)
        end
        -- Hide group finder button on release and reset parent/tracking
        if item.groupFinderBtn then
            item.groupFinderBtn:SetScript("OnUpdate", nil)
            item.groupFinderBtn._trackFrame = nil
            item.groupFinderBtn:SetParent(item.frame)
            item.groupFinderBtn:Hide()
            item.groupFinderBtn:SetAlpha(0)
        end
    end
)

----------------------------------------------------------------------
-- Acquire / release quest rows
----------------------------------------------------------------------
function TTQ:AcquireQuestItem(parent)
    local item = questItemPool:Acquire(parent)
    item.objectiveItems = item.objectiveItems or {}
    return item
end

function TTQ:ReleaseQuestItem(item)
    questItemPool:Release(item)
end

----------------------------------------------------------------------
-- Is a quest collapsed?
----------------------------------------------------------------------
function TTQ:IsQuestCollapsed(questID)
    local cq = self:GetSetting("collapsedQuests")
    return cq and cq[questID] and true or false
end

function TTQ:SetQuestCollapsed(questID, collapsed)
    local cq = self:GetSetting("collapsedQuests")
    if type(cq) ~= "table" then cq = {} end
    if collapsed == true then
        cq[questID] = true
    elseif collapsed == false then
        -- Explicit false: used to override auto-collapse for completed quests
        cq[questID] = false
    else
        cq[questID] = nil
    end
    self:SetSetting("collapsedQuests", cq)
end

----------------------------------------------------------------------
-- Build a quest row frame
----------------------------------------------------------------------
function TTQ:CreateQuestItem(parent)
    local item = {}
    item.objectiveItems = {}

    local frame = CreateFrame("Button", nil, parent)
    frame:SetHeight(20)
    frame:EnableMouse(true)
    item.frame = frame

    -- Focus indicator icon (left of quest name, always occupies space)
    local focusIcon = frame:CreateTexture(nil, "OVERLAY")
    focusIcon:SetSize(12, 12)
    focusIcon:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -4)
    pcall(focusIcon.SetAtlas, focusIcon, "Waypoint-MapPin-Tracked", false)
    focusIcon:SetAlpha(0) -- invisible but space reserved
    item.focusIcon = focusIcon

    -- Quest type icon (for completed quests)
    local icon = frame:CreateTexture(nil, "ARTWORK")
    icon:SetSize(14, 14)
    icon:SetPoint("TOPLEFT", frame, "TOPLEFT", FOCUS_ICON_WIDTH + 2, 0)
    item.icon = icon

    -- Expand indicator "+" (shown only when quest is collapsed)
    local expandInd = TTQ:CreateText(frame, 12, { r = 0.5, g = 0.5, b = 0.5 }, "CENTER")
    expandInd:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    expandInd:SetSize(FOCUS_ICON_WIDTH, 20)
    expandInd:SetText("+")
    expandInd:Hide()
    item.expandInd = expandInd

    -- Quest name text -- fixed indent so position never shifts
    local nameSize = TTQ:GetSetting("questNameFontSize")
    local nameColor = TTQ:GetSetting("questNameColor")
    local name = TTQ:CreateText(frame, nameSize, nameColor, "LEFT")
    name:SetPoint("TOPLEFT", frame, "TOPLEFT", FOCUS_ICON_WIDTH + 2, 0)
    name:SetPoint("RIGHT", frame, "RIGHT", -4, 0)
    name:SetHeight(20)
    name:SetWordWrap(false)
    name:SetNonSpaceWrap(false)
    name:SetMaxLines(1)
    item.name = name

    -- Quest item-use button (SecureActionButton -- can use items without tainting)
    -- Created parented to the quest row; re-parented at update time when
    -- the user picks "left" positioning (floats outside the tracker).
    itemBtnCounter = itemBtnCounter + 1
    local itemBtn = CreateFrame("Button", "TTQItemBtn" .. itemBtnCounter, frame,
        "SecureActionButtonTemplate, BackdropTemplate")
    itemBtn:SetSize(ITEM_BTN_SIZE, ITEM_BTN_SIZE)
    itemBtn:SetPoint("RIGHT", frame, "RIGHT", 0, 0)
    itemBtn:SetFrameLevel(frame:GetFrameLevel() + 5)
    itemBtn:RegisterForClicks("AnyUp", "AnyDown")

    -- Dark rounded backdrop
    itemBtn:SetBackdrop({
        bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 8,
        tile     = true,
        tileSize = 8,
        insets   = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    itemBtn:SetBackdropColor(0.08, 0.08, 0.10, 0.92)
    itemBtn:SetBackdropBorderColor(0.35, 0.35, 0.40, 0.6)

    local itemIcon = itemBtn:CreateTexture(nil, "ARTWORK")
    itemIcon:SetSize(ITEM_BTN_SIZE - 6, ITEM_BTN_SIZE - 6)
    itemIcon:SetPoint("CENTER")
    itemIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92) -- trim icon edges
    itemBtn.icon = itemIcon

    -- Highlight glow on hover
    local itemHl = itemBtn:CreateTexture(nil, "HIGHLIGHT")
    itemHl:SetAllPoints(itemIcon)
    itemHl:SetColorTexture(1, 1, 1, 0.18)

    -- Cooldown spinner
    local itemCooldown = CreateFrame("Cooldown", nil, itemBtn, "CooldownFrameTemplate")
    itemCooldown:SetAllPoints(itemIcon)
    itemCooldown:SetDrawEdge(false)
    itemCooldown:SetSwipeColor(0, 0, 0, 0.65)
    itemCooldown:SetHideCountdownNumbers(false)
    -- Style the countdown number region with a small font
    local cdText = itemCooldown:GetRegions()
    if cdText and cdText.SetFont then
        local fontFace = TTQ:GetResolvedFont("objective")
        TTQ:SafeSetFont(cdText, fontFace, 12, "OUTLINE")
    end
    itemBtn.cooldown = itemCooldown

    -- Tooltip: show the item tooltip on hover
    itemBtn:SetScript("OnEnter", function(self)
        if self._itemLink then
            GameTooltip:SetOwner(self, "ANCHOR_LEFT")
            GameTooltip:SetHyperlink(self._itemLink)
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Click to use", 0.5, 0.8, 1)
            GameTooltip:Show()
        end
    end)
    itemBtn:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    itemBtn:Hide()
    item.itemBtn = itemBtn

    -- Group Finder button (eye icon for group / elite / world boss quests)
    local groupFinderBtn = CreateFrame("Button", nil, frame, "BackdropTemplate")
    groupFinderBtn:SetSize(ITEM_BTN_SIZE, ITEM_BTN_SIZE)
    groupFinderBtn:SetPoint("RIGHT", frame, "RIGHT", 0, 0)
    groupFinderBtn:SetFrameLevel(frame:GetFrameLevel() + 5)
    groupFinderBtn:RegisterForClicks("LeftButtonUp")

    groupFinderBtn:SetBackdrop({
        bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 8,
        tile     = true,
        tileSize = 8,
        insets   = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    groupFinderBtn:SetBackdropColor(0.08, 0.08, 0.10, 0.92)
    groupFinderBtn:SetBackdropBorderColor(0.35, 0.35, 0.40, 0.6)

    local gfIcon = groupFinderBtn:CreateTexture(nil, "ARTWORK")
    gfIcon:SetSize(ITEM_BTN_SIZE - 6, ITEM_BTN_SIZE - 6)
    gfIcon:SetPoint("CENTER")
    pcall(gfIcon.SetAtlas, gfIcon, "socialqueuing-icon-eye", false)
    groupFinderBtn.icon = gfIcon

    local gfHl = groupFinderBtn:CreateTexture(nil, "HIGHLIGHT")
    gfHl:SetAllPoints(gfIcon)
    gfHl:SetColorTexture(1, 1, 1, 0.18)

    groupFinderBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("Find a Group", 1, 1, 1)
        GameTooltip:AddLine("Click to search for a group for this quest.", 0.5, 0.8, 1)
        GameTooltip:Show()
    end)
    groupFinderBtn:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    groupFinderBtn:SetScript("OnClick", function(self)
        local qID = self._questID
        if not qID then return end
        if InCombatLockdown() then
            print("|cffFFCC00TommyTwoquests:|r Cannot open Group Finder during combat.")
            return
        end
        -- Ensure the LFG list addon is loaded (it is demand-loaded)
        if C_AddOns and C_AddOns.LoadAddOn then
            C_AddOns.LoadAddOn("Blizzard_LFGList")
        elseif LoadAddOn then
            LoadAddOn("Blizzard_LFGList")
        end
        if LFGListUtil_FindQuestGroup then
            LFGListUtil_FindQuestGroup(qID)
        end
    end)

    groupFinderBtn:Hide()
    item.groupFinderBtn = groupFinderBtn

    -- Store original color for hover restore
    item._nameColorR = nameColor.r
    item._nameColorG = nameColor.g
    item._nameColorB = nameColor.b
    item._hoverAnimT = 0 -- 0 = normal color, 1 = class color

    -- Click handlers
    frame:SetScript("OnClick", function(self, button)
        local questData = item.questData
        if not questData then return end
        local questID = questData.questID

        if button == "LeftButton" then
            if IsShiftKeyDown() then
                -- Shift-click: toggle collapse/expand
                local isCollapsed = TTQ:IsQuestCollapsed(questID)
                TTQ:SetQuestCollapsed(questID, not isCollapsed)
                TTQ:SafeRefreshTracker()
            else
                -- Kaliel-style behavior: complete auto-complete quests directly.
                if questData.isAutoComplete and questData.isComplete and ShowQuestComplete then
                    ShowQuestComplete(questID)
                    TTQ:SafeRefreshTracker()
                    return
                end

                -- Click: focus the quest and open it on the map
                C_SuperTrack.SetSuperTrackedQuestID(questID)
                if QuestMapFrame_OpenToQuestDetails then
                    QuestMapFrame_OpenToQuestDetails(questID)
                end
                TTQ:SafeRefreshTracker()
            end
        elseif button == "RightButton" then
            TTQ:ShowQuestContextMenu(item)
        end
    end)

    frame:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    -- Hover: smooth class-color text transition (glassmorphic feel)
    frame:SetScript("OnEnter", function(self)
        local questData = item.questData
        if not questData then return end
        -- Track hovered quest globally so recycled items can restore hover state
        TTQ._hoveredQuestID = questData.questID
        -- Animate text color toward class color
        local cr, cg, cb = TTQ:GetClassColor()
        item._hoverTargetR, item._hoverTargetG, item._hoverTargetB = cr, cg, cb
        item._hoverDirection = 1 -- fading toward class color
        item._hoverAnimStart = GetTime()
        item._hoverAnimFrom = item._hoverAnimT or 0
        item.frame:SetScript("OnUpdate", function(f)
            local elapsed = GetTime() - (item._hoverAnimStart or 0)
            local raw = math.min(elapsed / 0.18, 1)
            local eased = 1 - (1 - raw) ^ 2 -- easeOutQuad
            if item._hoverDirection == 1 then
                item._hoverAnimT = item._hoverAnimFrom + (1 - item._hoverAnimFrom) * eased
            else
                item._hoverAnimT = item._hoverAnimFrom * (1 - eased)
            end
            local t = item._hoverAnimT
            local nr = item._nameColorR + (item._hoverTargetR - item._nameColorR) * t
            local ng = item._nameColorG + (item._hoverTargetG - item._nameColorG) * t
            local nb = item._nameColorB + (item._hoverTargetB - item._nameColorB) * t
            item.name:SetTextColor(nr, ng, nb)
            if raw >= 1 then f:SetScript("OnUpdate", nil) end
        end)
        -- Tooltip (gated by showTrackerTooltips via helper)
        if TTQ:BeginTooltip(self) then
            GameTooltip:SetText(questData.title, 1, 1, 1)
            if questData.isTask then
                GameTooltip:AddLine("World Quest", 0.4, 0.8, 1.0)
            end
            if questData.objectives then
                for _, obj in ipairs(questData.objectives) do
                    if obj.text then
                        local r, g, b = 0.85, 0.85, 0.85
                        if obj.finished then r, g, b = 0.5, 0.5, 0.5 end
                        GameTooltip:AddLine(obj.text, r, g, b)
                    end
                end
            end
            if questData.timeLeftMinutes and questData.timeLeftMinutes > 0 then
                local hours = math.floor(questData.timeLeftMinutes / 60)
                local mins = questData.timeLeftMinutes % 60
                local timeStr
                if hours > 0 then
                    timeStr = string.format("%dh %dm remaining", hours, mins)
                else
                    timeStr = string.format("%dm remaining", mins)
                end
                GameTooltip:AddLine(timeStr, 1, 0.82, 0)
            end
            GameTooltip:AddLine(" ")
            if questData.isAutoComplete and questData.isComplete then
                GameTooltip:AddLine("Click: Complete quest", 0.5, 0.8, 1)
            else
                GameTooltip:AddLine("Click: Focus & show on map", 0.5, 0.8, 1)
            end
            GameTooltip:AddLine("Shift-click: Expand/Collapse", 0.5, 0.8, 1)
            GameTooltip:AddLine("Right-click: Menu", 0.5, 0.8, 1)
            TTQ:EndTooltip()
        end
    end)

    frame:SetScript("OnLeave", function(self)
        TTQ:HideTooltip()
        -- Only clear hovered quest if the frame is still visible (not being released to pool)
        if self:IsVisible() then
            TTQ._hoveredQuestID = nil
        end
        -- Animate text color back to normal
        local cr, cg, cb = TTQ:GetClassColor()
        item._hoverTargetR, item._hoverTargetG, item._hoverTargetB = cr, cg, cb
        item._hoverDirection = 0 -- fading back to normal
        item._hoverAnimStart = GetTime()
        item._hoverAnimFrom = item._hoverAnimT or 1
        item.frame:SetScript("OnUpdate", function(f)
            local elapsed = GetTime() - (item._hoverAnimStart or 0)
            local raw = math.min(elapsed / 0.18, 1)
            local eased = 1 - (1 - raw) ^ 2
            item._hoverAnimT = item._hoverAnimFrom * (1 - eased)
            local t = item._hoverAnimT
            local nr = item._nameColorR + (item._hoverTargetR - item._nameColorR) * t
            local ng = item._nameColorG + (item._hoverTargetG - item._nameColorG) * t
            local nb = item._nameColorB + (item._hoverTargetB - item._nameColorB) * t
            item.name:SetTextColor(nr, ng, nb)
            if raw >= 1 then
                f:SetScript("OnUpdate", nil)
                item.name:SetTextColor(item._nameColorR, item._nameColorG, item._nameColorB)
                item._hoverAnimT = 0
            end
        end)
    end)

    return item
end

----------------------------------------------------------------------
-- Update quest row with data
----------------------------------------------------------------------
function TTQ:UpdateQuestItem(item, quest, parentWidth)
    item.questData = quest
    item.frame._ttqQuestItem = item -- back-reference for animation lookup
    local questID = quest.questID
    local isCollapsed = self:IsQuestCollapsed(questID)

    -- Focus icon / expand indicator
    if isCollapsed then
        -- Show "+" when quest is collapsed; use quest name font settings
        item.focusIcon:SetAlpha(0)
        local nameFont, nameSize, nameOutline = self:GetFontSettings("quest")
        self:SafeSetFont(item.expandInd, nameFont, nameSize, nameOutline)
        if quest.isSuperTracked then
            local sc = self:GetSetting("focusColor") or self:GetSetting("superTrackedColor") or
                { r = 1, g = 0.82, b = 0 }
            item.expandInd:SetTextColor(sc.r, sc.g, sc.b, 1)
        else
            local nc = self:GetSetting("questNameColor")
            item.expandInd:SetTextColor(nc.r, nc.g, nc.b, 1)
        end
        item.expandInd:Show()
    else
        item.expandInd:Hide()
        -- Reset focus icon position before setting branch-specific values
        item.focusIcon:ClearAllPoints()
        item.focusIcon:SetPoint("TOPLEFT", item.frame, "TOPLEFT", 0, -4)
        -- Focus icon: visible when focused; world quest icon for active WQs;
        -- otherwise invisible (space reserved)
        if quest.isSuperTracked then
            pcall(item.focusIcon.SetAtlas, item.focusIcon, "Waypoint-MapPin-Tracked", false)
            item.focusIcon:SetSize(12, 12)
            item.focusIcon:SetDesaturated(false)
            item.focusIcon:SetVertexColor(1, 1, 1)
            item.focusIcon:SetAlpha(1)
        elseif quest.questType == "worldquest" or quest.questType == "pvpworldquest" then
            pcall(item.focusIcon.SetAtlas, item.focusIcon, "worldquest-icon", false)
            item.focusIcon:SetSize(12, 12)
            item.focusIcon:ClearAllPoints()
            item.focusIcon:SetPoint("TOPLEFT", item.frame, "TOPLEFT", -2, -4)
            item.focusIcon:SetDesaturated(false)
            item.focusIcon:SetDesaturated(false)
            item.focusIcon:SetVertexColor(1, 1, 1)
            item.focusIcon:SetAlpha(1)
        else
            item.focusIcon:SetAlpha(0)
        end
    end

    -- Icon always hidden (using strikethrough for completed quests instead)
    item.icon:Hide()
    item.name:ClearAllPoints()
    item.name:SetPoint("TOPLEFT", item.frame, "TOPLEFT", FOCUS_ICON_WIDTH + 2, 0)
    item.name:SetPoint("RIGHT", item.frame, "RIGHT", -4, 0)
    item.name:SetHeight(20)

    -- Font
    local nameFont, nameSize, nameOutline = self:GetFontSettings("quest")
    self:SafeSetFont(item.name, nameFont, nameSize, nameOutline)

    -- Title text
    local title = quest.title
    if self:GetSetting("showQuestLevel") and quest.level > 0 then
        title = "[" .. quest.level .. "] " .. title
    end
    item.name:SetText(title)

    -- Strikethrough line overlay for completed quests
    -- Use sublevel 7 so the line renders in front of the text, not behind
    if not item.strikethrough then
        local st = item.frame:CreateTexture(nil, "OVERLAY", nil, 7)
        st:SetColorTexture(0.20, 0.80, 0.40, 0.45)
        st:SetHeight(1)
        item.strikethrough = st
    end
    if quest.isComplete then
        -- Measure actual text width so the line doesn't extend past it
        local textWidth = item.name:GetStringWidth() or 0
        item.strikethrough:ClearAllPoints()
        item.strikethrough:SetPoint("LEFT", item.name, "LEFT", 0, 0)
        item.strikethrough:SetWidth(math.min(textWidth, item.name:GetWidth() or textWidth))
        item.strikethrough:Show()
    else
        item.strikethrough:Hide()
    end

    -- Text color
    local nameColor = self:GetSetting("questNameColor")
    if quest.isComplete then
        -- Completed quests: emerald tone with strikethrough
        local ec = self:GetSetting("objectiveCompleteColor")
        item._nameColorR = ec.r
        item._nameColorG = ec.g
        item._nameColorB = ec.b
    else
        item._nameColorR = nameColor.r
        item._nameColorG = nameColor.g
        item._nameColorB = nameColor.b
    end

    -- If this quest is currently hovered (even after pool recycle), snap to class color
    if TTQ._hoveredQuestID and TTQ._hoveredQuestID == questID then
        local cr, cg, cb = self:GetClassColor()
        item.name:SetTextColor(cr, cg, cb)
        item._hoverAnimT = 1
        item._hoverTargetR = cr
        item._hoverTargetG = cg
        item._hoverTargetB = cb
    else
        item.name:SetTextColor(item._nameColorR, item._nameColorG, item._nameColorB)
    end

    -- Width
    item.frame:SetWidth(parentWidth)

    -- Quest item-use button
    if item.itemBtn then
        if quest.hasQuestItem and quest.questItemTexture and not InCombatLockdown() then
            local btn = item.itemBtn
            btn.icon:SetTexture(quest.questItemTexture)
            btn._itemLink = quest.questItemLink
            -- Configure secure action: use the quest item by item link
            btn:SetAttribute("type", "item")
            btn:SetAttribute("item", quest.questItemLink)

            local position = TTQ:GetSetting("questItemPosition") or "right"
            btn:ClearAllPoints()

            if position == "left" and TTQ.Tracker then
                -- Float outside the tracker on the left, centered on the quest row.
                -- Re-parent to the Tracker (which doesn't clip) so it renders
                -- outside the scroll frame.
                btn:SetParent(TTQ.Tracker)
                btn:SetFrameLevel(TTQ.Tracker:GetFrameLevel() + 10)
                -- Track the quest row position via OnUpdate
                btn._trackFrame = item.frame
                btn._cdPollElapsed = 0
                btn:SetScript("OnUpdate", function(self, elapsed)
                    local tf = self._trackFrame
                    if not tf or not tf:IsVisible() then
                        self:SetAlpha(0)
                        return
                    end
                    -- Get the quest row's vertical center in tracker coordinates
                    local _, frameY = tf:GetCenter()
                    local _, trackerY = TTQ.Tracker:GetCenter()
                    if not frameY or not trackerY then return end
                    local scale = tf:GetEffectiveScale() / TTQ.Tracker:GetEffectiveScale()
                    local relY = (frameY * scale) - trackerY
                    self:ClearAllPoints()
                    self:SetPoint("RIGHT", TTQ.Tracker, "LEFT", -4, relY)
                    -- Hide if the quest row is scrolled out of the visible scroll area
                    if TTQ.ScrollFrame then
                        local sfTop = TTQ.ScrollFrame:GetTop()
                        local sfBottom = TTQ.ScrollFrame:GetBottom()
                        local fTop = tf:GetTop()
                        local fBottom = tf:GetBottom()
                        if sfTop and sfBottom and fTop and fBottom then
                            if fTop < sfBottom or fBottom > sfTop then
                                self:SetAlpha(0)
                            else
                                self:SetAlpha(1)
                            end
                        end
                    else
                        self:SetAlpha(1)
                    end
                    -- Poll cooldown
                    self._cdPollElapsed = (self._cdPollElapsed or 0) + elapsed
                    if self._cdPollElapsed >= 0.2 then
                        self._cdPollElapsed = 0
                        local idx = self._questLogIndex
                        if idx and GetQuestLogSpecialItemCooldown then
                            local start, duration = GetQuestLogSpecialItemCooldown(idx)
                            if start and duration and duration > 1.5 then
                                self.cooldown:Show()
                                self.cooldown:SetCooldown(start, duration)
                            else
                                self.cooldown:Clear()
                                self.cooldown:Hide()
                            end
                        end
                    end
                end)
                -- Quest name keeps full width
                item.name:SetPoint("RIGHT", item.frame, "RIGHT", -4, 0)
            else
                -- Right position (default): inside the quest row
                btn:SetParent(item.frame)
                btn:SetFrameLevel(item.frame:GetFrameLevel() + 5)
                btn:SetPoint("RIGHT", item.frame, "RIGHT", 0, 0)
                btn:SetScript("OnUpdate", nil)
                btn._trackFrame = nil
                -- Shrink quest name to make room for item button
                item.name:SetPoint("RIGHT", btn, "LEFT", -3, 0)
            end

            btn:SetAlpha(1)
            btn:Show()

            -- Update cooldown text font to match user settings
            local cdText = btn.cooldown:GetRegions()
            if cdText and cdText.SetFont then
                local fontFace = TTQ:GetResolvedFont("objective")
                TTQ:SafeSetFont(cdText, fontFace, 12, "OUTLINE")
            end

            -- Cooldown: use the quest-log-specific cooldown API and
            -- poll for updates so the spinner appears after item use.
            btn._questLogIndex = quest.questLogIndex
            btn.cooldown:Clear()
            btn.cooldown:Hide()

            local function UpdateQuestItemCooldown(self)
                local idx = self._questLogIndex
                if not idx then return end
                local start, duration, enable
                if GetQuestLogSpecialItemCooldown then
                    start, duration, enable = GetQuestLogSpecialItemCooldown(idx)
                end
                if start and duration and duration > 1.5 then
                    self.cooldown:Show()
                    self.cooldown:SetCooldown(start, duration)
                else
                    self.cooldown:Clear()
                    self.cooldown:Hide()
                end
            end

            -- Initial check
            UpdateQuestItemCooldown(btn)

            -- If in "left" mode we already have an OnUpdate; merge cooldown
            -- polling into it. For "right" mode, add a lightweight poller.
            if position ~= "left" or not TTQ.Tracker then
                local existingOnUpdate = btn:GetScript("OnUpdate")
                btn._cdPollElapsed = 0
                btn:SetScript("OnUpdate", function(self, elapsed)
                    self._cdPollElapsed = (self._cdPollElapsed or 0) + elapsed
                    if self._cdPollElapsed >= 0.2 then
                        self._cdPollElapsed = 0
                        UpdateQuestItemCooldown(self)
                    end
                end)
            end
        else
            item.itemBtn:SetScript("OnUpdate", nil)
            item.itemBtn._trackFrame = nil
            item.itemBtn:SetParent(item.frame)
            item.itemBtn:Hide()
            item.itemBtn:SetAlpha(0)
            item.name:SetPoint("RIGHT", item.frame, "RIGHT", -4, 0)
        end
    end

    -- Group Finder button (eye icon for group / elite / world boss quests)
    if item.groupFinderBtn then
        if quest.isGroupFinderEligible and not quest.isComplete then
            local gfBtn = item.groupFinderBtn
            gfBtn._questID = questID
            gfBtn:ClearAllPoints()

            local position = self:GetSetting("questItemPosition") or "right"
            local itemBtnVisible = item.itemBtn:IsShown() and item.itemBtn:GetAlpha() > 0

            if position == "left" and TTQ.Tracker then
                -- Float outside the tracker on the left, mirroring the quest item button.
                gfBtn:SetParent(TTQ.Tracker)
                gfBtn:SetFrameLevel(TTQ.Tracker:GetFrameLevel() + 10)
                gfBtn._trackFrame = item.frame
                gfBtn._trackItemBtn = itemBtnVisible and item.itemBtn or nil
                gfBtn:SetScript("OnUpdate", function(self)
                    local tf = self._trackFrame
                    if not tf or not tf:IsVisible() then
                        self:SetAlpha(0)
                        return
                    end
                    local _, frameY = tf:GetCenter()
                    local _, trackerY = TTQ.Tracker:GetCenter()
                    if not frameY or not trackerY then return end
                    local scale = tf:GetEffectiveScale() / TTQ.Tracker:GetEffectiveScale()
                    local relY = (frameY * scale) - trackerY
                    self:ClearAllPoints()
                    -- If the item button is also floating left, stack to its left
                    local siblingBtn = self._trackItemBtn
                    if siblingBtn and siblingBtn:IsShown() and siblingBtn:GetAlpha() > 0 then
                        self:SetPoint("RIGHT", siblingBtn, "LEFT", -2, 0)
                    else
                        self:SetPoint("RIGHT", TTQ.Tracker, "LEFT", -4, relY)
                    end
                    -- Hide if scrolled out of the visible scroll area
                    if TTQ.ScrollFrame then
                        local sfTop = TTQ.ScrollFrame:GetTop()
                        local sfBottom = TTQ.ScrollFrame:GetBottom()
                        local fTop = tf:GetTop()
                        local fBottom = tf:GetBottom()
                        if sfTop and sfBottom and fTop and fBottom then
                            if fTop < sfBottom or fBottom > sfTop then
                                self:SetAlpha(0)
                            else
                                self:SetAlpha(1)
                            end
                        end
                    else
                        self:SetAlpha(1)
                    end
                end)
                -- Quest name keeps full width in left mode
                item.name:SetPoint("RIGHT", item.frame, "RIGHT", -4, 0)
            else
                -- Right position (default): inside the quest row
                gfBtn:SetParent(item.frame)
                gfBtn:SetFrameLevel(item.frame:GetFrameLevel() + 5)
                gfBtn:SetScript("OnUpdate", nil)
                gfBtn._trackFrame = nil
                gfBtn._trackItemBtn = nil

                if itemBtnVisible then
                    gfBtn:SetPoint("RIGHT", item.itemBtn, "LEFT", -2, 0)
                else
                    gfBtn:SetPoint("RIGHT", item.frame, "RIGHT", 0, 0)
                end

                -- Shrink quest name to make room for the group finder button
                item.name:SetPoint("RIGHT", gfBtn, "LEFT", -3, 0)
            end

            gfBtn:SetAlpha(1)
            gfBtn:Show()
        else
            item.groupFinderBtn:SetScript("OnUpdate", nil)
            item.groupFinderBtn._trackFrame = nil
            item.groupFinderBtn._trackItemBtn = nil
            item.groupFinderBtn:SetParent(item.frame)
            item.groupFinderBtn:Hide()
            item.groupFinderBtn:SetAlpha(0)
        end
    end

    -- Build objective items (skip if collapsed)
    if item.objectiveItems then
        for _, objItem in ipairs(item.objectiveItems) do
            self:ReleaseObjectiveItem(objItem)
        end
        wipe(item.objectiveItems)
    end

    if not isCollapsed and quest.objectives and #quest.objectives > 0 then
        local showNums = self:GetSetting("showObjectiveNumbers")
        for _, obj in ipairs(quest.objectives) do
            local objItem = self:AcquireObjectiveItem(item.frame)
            objItem.questID = questID -- store questID for click-to-map
            objItem.frame:SetWidth(parentWidth - FOCUS_ICON_WIDTH - 2)
            self:UpdateObjectiveItem(objItem, obj, showNums)
            table.insert(item.objectiveItems, objItem)
        end
    elseif not isCollapsed and (not quest.objectives or #quest.objectives == 0) and not quest.isComplete then
        -- No objectives: show quest description text as a single line
        local descText = quest.questDescription
        if descText and descText ~= "" then
            local objItem = self:AcquireObjectiveItem(item.frame)
            objItem.questID = questID
            objItem.frame:SetWidth(parentWidth - FOCUS_ICON_WIDTH - 2)
            -- Truncate long descriptions and show as italic hint
            local truncated = self:Truncate(descText, 80)
            local descObj = {
                text = truncated,
                finished = false,
            }
            self:UpdateObjectiveItem(objItem, descObj, false)
            -- Style as italic to distinguish from real objectives
            local fontFace, fontSize, fontOutline = self:GetFontSettings("objective")
            self:SafeSetFont(objItem.text, fontFace, fontSize, fontOutline)
            local hintColor = self:GetSetting("objectiveIncompleteColor")
            objItem.text:SetTextColor(hintColor.r * 0.8, hintColor.g * 0.8, hintColor.b * 0.8)
            objItem.dash:SetText("")
            table.insert(item.objectiveItems, objItem)
        end
    end
end

----------------------------------------------------------------------
-- Layout objective items under the quest name, returns total height
----------------------------------------------------------------------
local QUEST_NAME_ROW_HEIGHT = 20
local OBJECTIVE_SPACING = 2

function TTQ:LayoutQuestItem(item, yOffset)
    local totalHeight = QUEST_NAME_ROW_HEIGHT

    if #item.objectiveItems > 0 then
        totalHeight = totalHeight + OBJECTIVE_SPACING
        for _, objItem in ipairs(item.objectiveItems) do
            objItem.frame:SetPoint("TOPLEFT", item.frame, "TOPLEFT", FOCUS_ICON_WIDTH + 2, -totalHeight)
            totalHeight = totalHeight + objItem.frame:GetHeight()
        end
    end

    item.frame:SetHeight(totalHeight)
    return totalHeight
end

----------------------------------------------------------------------
-- Right-click context menu
----------------------------------------------------------------------
function TTQ:ShowQuestContextMenu(item)
    local quest = item.questData
    if not quest then return end

    if not self._questContextMenu then
        self._questContextMenu = self:CreateContextMenu("TTQQuestContextMenu")
    end

    local questID = quest.questID
    local isCollapsed = self:IsQuestCollapsed(questID)
    local isFocused = quest.isSuperTracked

    local isWorldQuestTask = quest.isTask
    local isWorldQuest = quest.questType == "worldquest" or quest.questType == "pvpworldquest"
    local isTask = quest.isTask

    local shareDisabled = not (C_QuestLog and C_QuestLog.IsPushableQuest
        and C_QuestLog.IsPushableQuest(questID) and IsInGroup())
    local abandonDisabled = isWorldQuest or isTask

    local config = {
        title = quest.title,
        buttons = {
            {
                label = isFocused and "Unfocus" or "Focus",
                tooltip = isFocused
                    and "Stop focusing this quest."
                    or "Focus on this quest. The game will guide you with an on-screen arrow.",
                onClick = function()
                    if isFocused then
                        C_SuperTrack.SetSuperTrackedQuestID(0)
                    else
                        C_SuperTrack.SetSuperTrackedQuestID(questID)
                    end
                    self:SafeRefreshTracker()
                end,
            },
            {
                label = isCollapsed and "Expand" or "Collapse",
                tooltip = isCollapsed
                    and "Show objectives for this quest."
                    or "Hide objectives for this quest.",
                onClick = function()
                    self:SetQuestCollapsed(questID, not isCollapsed)
                    self:SafeRefreshTracker()
                end,
            },
            {
                label = "Show on Map",
                tooltip = "Open the world map with this quest highlighted.",
                onClick = function()
                    if QuestMapFrame_OpenToQuestDetails then
                        QuestMapFrame_OpenToQuestDetails(questID)
                    end
                end,
            },
            {
                label = "Untrack",
                tooltip = isWorldQuestTask
                    and "World quests are automatically tracked while you are in the area."
                    or "Stop tracking this quest in the tracker.",
                disabled = isWorldQuestTask,
                onClick = function()
                    if isWorldQuestTask then return end
                    if C_QuestLog and C_QuestLog.RemoveQuestWatch then
                        C_QuestLog.RemoveQuestWatch(questID)
                        self:SafeRefreshTracker()
                    end
                end,
            },
            {
                label = "Share Quest",
                tooltip = shareDisabled
                    and "Requires a pushable quest and being in a group."
                    or "Share this quest with your party or raid.",
                disabled = shareDisabled,
                onClick = function()
                    if not shareDisabled and QuestLogPushQuest then
                        if C_QuestLog.SetSelectedQuest then
                            C_QuestLog.SetSelectedQuest(questID)
                        end
                        QuestLogPushQuest()
                    end
                end,
            },
            {
                label = "Abandon Quest",
                tooltip = abandonDisabled
                    and "World quests and bonus objectives cannot be abandoned."
                    or "Permanently abandon this quest. You will lose all progress.",
                disabled = abandonDisabled,
                color = { r = 0.9, g = 0.4, b = 0.4 },
                onClick = function()
                    if abandonDisabled then return end
                    if C_QuestLog.SetSelectedQuest then
                        C_QuestLog.SetSelectedQuest(questID)
                    end
                    if C_QuestLog.SetAbandonQuest then
                        C_QuestLog.SetAbandonQuest()
                    end
                    if StaticPopup_Show then
                        StaticPopup_Show("ABANDON_QUEST", quest.title)
                    end
                end,
            },
        },
    }

    -- Conditionally insert "Find Group" after "Show on Map" (index 3)
    if quest.isGroupFinderEligible then
        table.insert(config.buttons, 4, {
            label = "Find Group",
            tooltip = "Search the Group Finder for groups doing this quest.",
            onClick = function()
                if InCombatLockdown() then return end
                if C_AddOns and C_AddOns.LoadAddOn then
                    C_AddOns.LoadAddOn("Blizzard_LFGList")
                elseif LoadAddOn then
                    LoadAddOn("Blizzard_LFGList")
                end
                if LFGListUtil_FindQuestGroup then
                    LFGListUtil_FindQuestGroup(questID)
                end
            end,
        })
    end

    self._questContextMenu:Show(config)
end
