----------------------------------------------------------------------
-- TommyTwoquests -- ObjectiveItem.lua
-- Objective row: text, completion state (no progress bar)
----------------------------------------------------------------------
local AddonName, TTQ = ...
local table, string, math, pcall, CreateFrame = table, string, math, pcall, CreateFrame

local ROW_HEIGHT = 16
local ROW_HEIGHT_WITH_BAR = 26
local PROGRESS_BAR_HEIGHT = 6
local PROGRESS_BAR_MIN_WIDTH = 90
local PROGRESS_BAR_TEXT_GAP = 3

----------------------------------------------------------------------
-- Parse objective progress percentage from objective fields/text.
-- Returns value in [0, 1] or nil if objective is not percentage-driven.
----------------------------------------------------------------------
local function ParseObjectivePercent(objective)
    if not objective or objective.isDescription then
        return nil
    end

    local text = objective.text or ""
    local hasPercentText = text:find("%%") ~= nil
    if not hasPercentText then
        return nil
    end

    local fulfilled = tonumber(objective.numFulfilled)
    local required = tonumber(objective.numRequired)

    -- For percent objectives, prefer the visible percent text because some
    -- quests report stale/incompatible numFulfilled/numRequired values.
    local pctText = text ~= "" and string.match(text, "(%d+[%.,]?%d*)%s*%%") or nil
    if pctText then
        local pct = tonumber((pctText:gsub(",", ".")))
        if pct then
            if pct < 0 then pct = 0 end
            if pct > 100 then pct = 100 end
            return pct / 100
        end
    end

    -- Fallback to structured API ratio when percent text couldn't be parsed.
    if required and required > 0 then
        local ratio = (fulfilled or 0) / required
        if ratio < 0 then ratio = 0 end
        if ratio > 1 then ratio = 1 end
        return ratio
    end

    if objective.finished then
        return 1
    end

    return nil
end

-- Object pool for objective rows
local objectivePool = TTQ:CreateObjectPool(
    function(parent) return TTQ:CreateObjectiveItem(parent) end,
    function(item)
        item.frame:SetAlpha(1)
        item.questID = nil -- clear stale questID to prevent wrong quest opening
        if item.checkIcon then item.checkIcon:Hide() end
        if item.dash then item.dash:Show() end
        if item.progressBG then item.progressBG:Hide() end
        if item.progressFill then
            item.progressFill:ClearAllPoints()
            item.progressFill:SetPoint("TOPLEFT", item.progressBG, "TOPLEFT", 0, 0)
            item.progressFill:SetPoint("BOTTOMLEFT", item.progressBG, "BOTTOMLEFT", 0, 0)
            item.progressFill:SetWidth(0)
            item.progressFill:Hide()
        end
        item.frame:SetHeight(ROW_HEIGHT)
    end
)

----------------------------------------------------------------------
-- Create or reuse an objective row
----------------------------------------------------------------------
function TTQ:AcquireObjectiveItem(parent)
    return objectivePool:Acquire(parent)
end

function TTQ:ReleaseObjectiveItem(item)
    objectivePool:Release(item)
end

----------------------------------------------------------------------
-- Build objective row frame
----------------------------------------------------------------------
function TTQ:CreateObjectiveItem(parent)
    local item = {}

    local frame = CreateFrame("Button", nil, parent)
    frame:SetHeight(ROW_HEIGHT)
    frame:EnableMouse(true)
    frame:RegisterForClicks("LeftButtonUp")
    item.frame = frame

    -- Click: open quest in map/log
    frame:SetScript("OnClick", function()
        if item.questID and QuestMapFrame_OpenToQuestDetails then
            QuestMapFrame_OpenToQuestDetails(item.questID)
        end
    end)

    -- Dash / bullet
    local dash = self:CreateText(frame, self:GetSetting("objectiveFontSize"),
        self:GetSetting("objectiveIncompleteColor"), "LEFT")
    dash:SetPoint("LEFT", frame, "LEFT", 0, 0)
    dash:SetText("-")
    dash:SetWidth(10)
    item.dash = dash

    -- Checkmark icon (shown instead of dash when objective is complete)
    local checkIcon = frame:CreateTexture(nil, "ARTWORK")
    checkIcon:SetSize(10, 10)
    checkIcon:SetPoint("LEFT", frame, "LEFT", 0, 0)
    checkIcon:SetTexture("Interface\\AddOns\\TommyTwoquests\\Textures\\checkmark")
    checkIcon:Hide()
    item.checkIcon = checkIcon

    -- Objective text (single line, constrained so it doesn't overlap)
    local text = self:CreateText(frame, self:GetSetting("objectiveFontSize"),
        self:GetSetting("objectiveIncompleteColor"), "LEFT")
    text:SetPoint("LEFT", dash, "RIGHT", 2, 0)
    text:SetPoint("RIGHT", frame, "RIGHT", 0, 0)
    text:SetWordWrap(false)
    text:SetNonSpaceWrap(false)
    text:SetMaxLines(1)
    item.text = text

    -- Subtle objective progress bar (shown for percentage-driven objectives)
    local progressBG = frame:CreateTexture(nil, "ARTWORK")
    progressBG:SetPoint("TOPLEFT", text, "BOTTOMLEFT", 0, -PROGRESS_BAR_TEXT_GAP)
    progressBG:SetPoint("TOPRIGHT", text, "BOTTOMRIGHT", -40, -PROGRESS_BAR_TEXT_GAP)
    progressBG:SetHeight(PROGRESS_BAR_HEIGHT)
    progressBG:SetWidth(PROGRESS_BAR_MIN_WIDTH)
    progressBG:SetColorTexture(0.05, 0.05, 0.06, 0.75)
    progressBG:Hide()
    item.progressBG = progressBG

    local progressFill = frame:CreateTexture(nil, "OVERLAY")
    progressFill:SetPoint("TOPLEFT", progressBG, "TOPLEFT", 0, 0)
    progressFill:SetPoint("BOTTOMLEFT", progressBG, "BOTTOMLEFT", 0, 0)
    progressFill:SetWidth(0)
    progressFill:SetColorTexture(1.0, 0.82, 0.0, 0.90)
    progressFill:Hide()
    item.progressFill = progressFill

    return item
end

----------------------------------------------------------------------
-- Update objective row with data
----------------------------------------------------------------------
function TTQ:UpdateObjectiveItem(item, objective, showNumbers)
    if not objective then return end

    local fontFace, fontSize, fontOutline = self:GetFontSettings("objective")
    self:SafeSetFont(item.text, fontFace, fontSize, fontOutline)
    self:SafeSetFont(item.dash, fontFace, fontSize, fontOutline)

    if objective.finished then
        local color = self:GetSetting("objectiveCompleteColor")
        item.text:SetTextColor(color.r, color.g, color.b)
        item.dash:Hide()
        item.checkIcon:SetVertexColor(color.r, color.g, color.b)
        item.checkIcon:Show()
    else
        local color = self:GetSetting("objectiveIncompleteColor")
        item.text:SetTextColor(color.r, color.g, color.b)
        item.dash:SetTextColor(color.r, color.g, color.b)
        item.dash:SetText("-")
        item.dash:Show()
        item.checkIcon:Hide()
    end

    -- Build objective text
    local objText = objective.text or ""
    if not showNumbers then
        -- Strip progress numbers like "3/5" or "0/1" from the text
        objText = objText:gsub("%s*%d+/%d+%s*", " "):gsub("^%s+", ""):gsub("%s+$", "")
    end
    item.text:SetText(objText)

    local progressPct = ParseObjectivePercent(objective)
    if progressPct ~= nil then
        if objective.finished then
            progressPct = 1
        end

        local safePct = math.max(0, math.min(1, progressPct))
        local availableWidth = (item.frame:GetWidth() or 0) - 46
        local progressWidth = math.max(availableWidth, PROGRESS_BAR_MIN_WIDTH)
        item.progressBG:SetWidth(progressWidth)
        item.progressFill:SetWidth(progressWidth * safePct)

        if objective.finished then
            local complete = self:GetSetting("objectiveCompleteColor")
            item.progressFill:SetColorTexture(complete.r, complete.g, complete.b, 0.95)
        else
            local focus = self:GetSetting("focusColor")
            item.progressFill:SetColorTexture(focus.r, focus.g, focus.b, 0.9)
        end

        item.progressBG:Show()
        item.progressFill:Show()
        item.frame:SetHeight(ROW_HEIGHT_WITH_BAR)
    else
        item.progressBG:Hide()
        item.progressFill:SetWidth(0)
        item.progressFill:Hide()
        item.frame:SetHeight(ROW_HEIGHT)
    end
end
