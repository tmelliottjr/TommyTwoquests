----------------------------------------------------------------------
-- TommyTwoquests -- Config.lua
-- Default settings (AceDB-3.0 format) and font helpers
----------------------------------------------------------------------
local AddonName, TTQ = ...
local ipairs, type, math = ipairs, type, math

----------------------------------------------------------------------
-- Default configuration -- structured for AceDB-3.0
-- All user settings live under the "profile" key so they get
-- per-profile support (switch, copy, delete, reset) for free.
----------------------------------------------------------------------
TTQ.Defaults = {
    profile = {
        -- Layout
        trackerWidth             = 250,
        trackerMaxHeight         = 600,
        trackerAnchor            = { point = "TOPRIGHT", relativeTo = nil, relativePoint = "TOPRIGHT", x = -60, y = -200 },
        maxQuests                = 10,
        collapsed                = false,
        locked                   = false,

        -- Fonts (stored as names; ResolveFontPath turns them into paths for SetFont)
        useGlobalFont            = true,
        globalFont               = "Friz Quadrata TT",
        headerFont               = "Friz Quadrata TT",
        questNameFont            = "Friz Quadrata TT",
        objectiveFont            = "Friz Quadrata TT",

        -- Font Sizes
        headerFontSize           = 13,
        questNameFontSize        = 12,
        objectiveFontSize        = 11,

        -- Font Outline
        headerFontOutline        = "",
        questNameFontOutline     = "",
        objectiveFontOutline     = "",

        -- Colors
        headerColor              = { r = 1.0, g = 0.82, b = 0.0 },
        questNameColor           = { r = 0.95, g = 0.95, b = 0.95 },
        questHoverColor          = { r = 1.0, g = 1.0, b = 1.0 },
        focusColor               = { r = 1.0, g = 0.82, b = 0.0 },
        superTrackedColor        = { r = 1.0, g = 0.82, b = 0.0 },
        objectiveCompleteColor   = { r = 0.20, g = 0.80, b = 0.40 },
        objectiveIncompleteColor = { r = 0.85, g = 0.85, b = 0.85 },

        -- Filters
        showCampaign             = true,
        showImportant            = true,
        showLegendary            = true,
        showWorldQuests          = true,
        showSideQuests           = true,
        showMeta                 = true,
        showDungeonRaid          = true,
        showDailies              = true,
        showWeeklies             = true,
        showCallings             = true,
        showPvP                  = true,
        showAccount              = true,
        filterByCurrentZone      = false,
        groupCurrentZoneQuests   = false,

        -- Behavior
        showTrackerTooltips      = true,
        showIcons                = true,
        showObjectiveNumbers     = true,
        showQuestLevel           = false,
        showHeaderCount          = true,
        showTrackerHeader        = true,
        rightClickMenu           = true,
        hideInCombat             = false,

        -- Background
        showBackground           = true,
        classColorGradient       = true,
        bgAlpha                  = 0.6,
        bgColor                  = { r = 0.05, g = 0.05, b = 0.05 },
        bgPadding                = 8,

        -- Recipes
        showRecipes              = true,

        -- Abandon all quests button
        showAbandonAllButton     = false,

        -- Quest item button position: "right" (inside row) or "left" (outside tracker)
        questItemPosition        = "right",

        -- Collapsed category groups (keyed by quest type)
        collapsedGroups          = {},

        -- Collapsed individual quests (keyed by questID)
        collapsedQuests          = {},

        -- Collapsed individual recipes (keyed by "recipe_<recipeID>")
        collapsedRecipes         = {},

        -- Mythic+
        autoInsertKeystone       = true,
    },
}

----------------------------------------------------------------------
-- Convenience accessors -- thin wrappers around self.db.profile
-- These allow gradual migration: code that still calls GetSetting
-- continues to work, and we can replace call sites incrementally.
----------------------------------------------------------------------
function TTQ:GetSetting(key)
    if self.db and self.db.profile and self.db.profile[key] ~= nil then
        return self.db.profile[key]
    end
    -- Fallback to flat defaults during early loading (before AceDB init)
    if self.Defaults and self.Defaults.profile and self.Defaults.profile[key] ~= nil then
        return self.Defaults.profile[key]
    end
    return nil
end

function TTQ:SetSetting(key, value)
    if self.db and self.db.profile then
        self.db.profile[key] = value
    end
end

function TTQ:ResetDefaults()
    if self.db then
        self.db:ResetProfile()
    end
end

----------------------------------------------------------------------
-- Resolve stored font (may be name, path, or dropdown index) to a path for SetFont
----------------------------------------------------------------------
function TTQ:ResolveFontPath(stored)
    if stored == nil or stored == "" then
        stored = self.Defaults.profile.globalFont
    end
    local list = self:GetFontList()
    -- Dropdown may pass 1-based index
    if type(stored) == "number" then
        local idx = math.floor(stored)
        if idx >= 1 and idx <= #list and list[idx].value then
            return list[idx].value:gsub("\\\\", "\\")
        end
        stored = self.Defaults.profile.globalFont
    end
    -- Must be string from here
    if type(stored) ~= "string" then
        local v = list[1] and list[1].value
        return (v and v:gsub("\\\\", "\\")) or "Fonts\\FRIZQT__.TTF"
    end
    -- Already a path (legacy or from code); normalize for SetFont
    if stored:find("[/\\]") then
        return stored:gsub("\\\\", "\\")
    end
    -- Stored value is a font name: look up path for SetFont
    for _, opt in ipairs(list) do
        if opt.name == stored and opt.value and opt.value ~= "" then
            local path = opt.value:gsub("\\\\", "\\")
            return path
        end
    end
    -- Never return a name; return a valid path so SetFont never fails
    return (list[1] and list[1].value and list[1].value:gsub("\\\\", "\\")) or "Fonts\\FRIZQT__.TTF"
end

----------------------------------------------------------------------
-- Resolved font: when "Use one font for all" is on, returns globalFont
----------------------------------------------------------------------
function TTQ:GetResolvedFont(which)
    local raw
    if self:GetSetting("useGlobalFont") then
        raw = self:GetSetting("globalFont") or self.Defaults.profile.globalFont
    elseif which == "header" then
        raw = self:GetSetting("headerFont")
    elseif which == "quest" then
        raw = self:GetSetting("questNameFont")
    elseif which == "objective" then
        raw = self:GetSetting("objectiveFont")
    else
        raw = self:GetSetting("globalFont") or self.Defaults.profile.globalFont
    end
    return self:ResolveFontPath(raw)
end

----------------------------------------------------------------------
-- Get all font settings for a category in one call
-- which: "header" | "quest" | "objective"
-- Returns: fontPath, fontSize, fontOutline, colorTable
----------------------------------------------------------------------
function TTQ:GetFontSettings(which)
    local face = self:GetResolvedFont(which)
    local size, outline, color
    if which == "header" then
        size    = self:GetSetting("headerFontSize")
        outline = self:GetSetting("headerFontOutline")
        color   = self:GetSetting("headerColor")
    elseif which == "quest" then
        size    = self:GetSetting("questNameFontSize")
        outline = self:GetSetting("questNameFontOutline")
        color   = self:GetSetting("questNameColor")
    elseif which == "objective" then
        size    = self:GetSetting("objectiveFontSize")
        outline = self:GetSetting("objectiveFontOutline")
        color   = self:GetSetting("objectiveIncompleteColor")
    else
        size    = self:GetSetting("headerFontSize")
        outline = self:GetSetting("headerFontOutline")
        color   = self:GetSetting("headerColor")
    end
    return face, size, outline, color
end
