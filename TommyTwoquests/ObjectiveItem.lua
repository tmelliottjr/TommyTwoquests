----------------------------------------------------------------------
-- TommyTwoquests — ObjectiveItem.lua
-- Objective row: text, completion state (no progress bar)
----------------------------------------------------------------------
local AddonName, TTQ = ...
local table, string, pcall, CreateFrame = table, string, pcall, CreateFrame

local ROW_HEIGHT = 16

-- Object pool for objective rows
local objectivePool = TTQ:CreateObjectPool(
    function(parent) return TTQ:CreateObjectiveItem(parent) end,
    function(item)
        item.frame:SetAlpha(1)
        if item.checkIcon then item.checkIcon:Hide() end
        if item.dash then item.dash:Show() end
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
    item.frame:SetHeight(ROW_HEIGHT)
end
