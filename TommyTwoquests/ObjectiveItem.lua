----------------------------------------------------------------------
-- TommyTwoquests — ObjectiveItem.lua
-- Objective row: text, completion state (no progress bar)
----------------------------------------------------------------------
local AddonName, TTQ = ...
local table, string, pcall, CreateFrame = table, string, pcall, CreateFrame

local OBJECTIVE_POOL = {}
local ROW_HEIGHT = 16

----------------------------------------------------------------------
-- Create or reuse an objective row
----------------------------------------------------------------------
function TTQ:AcquireObjectiveItem(parent)
    local item = table.remove(OBJECTIVE_POOL)
    if not item then
        item = self:CreateObjectiveItem(parent)
    end
    item.frame:SetParent(parent)
    item.frame:Show()
    return item
end

function TTQ:ReleaseObjectiveItem(item)
    item.frame:SetAlpha(1) -- reset alpha so pooled items aren't invisible
    if item.checkIcon then item.checkIcon:Hide() end
    if item.dash then item.dash:Show() end
    item.frame:Hide()
    item.frame:ClearAllPoints()
    table.insert(OBJECTIVE_POOL, item)
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

    local fontSize = self:GetSetting("objectiveFontSize")
    local fontFace = self:GetResolvedFont("objective")
    local fontOutline = self:GetSetting("objectiveFontOutline")
    if not pcall(item.text.SetFont, item.text, fontFace, fontSize, fontOutline) then
        pcall(item.text.SetFont, item.text, "Fonts\\FRIZQT__.TTF", fontSize, fontOutline)
    end
    if not pcall(item.dash.SetFont, item.dash, fontFace, fontSize, fontOutline) then
        pcall(item.dash.SetFont, item.dash, "Fonts\\FRIZQT__.TTF", fontSize, fontOutline)
    end

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
