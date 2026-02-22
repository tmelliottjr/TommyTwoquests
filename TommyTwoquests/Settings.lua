----------------------------------------------------------------------
-- TommyTwoquests -- Settings.lua
-- AceConfig-3.0 options table + AceConfigDialog integration
----------------------------------------------------------------------
local AddonName, TTQ = ...
local ipairs, type, math, pairs = ipairs, type, math, pairs

----------------------------------------------------------------------
-- Font option builder (dynamic from LibSharedMedia or fallback list)
----------------------------------------------------------------------
local function GetFontValues()
    local list = TTQ:GetFontList()
    local values = {}
    for _, opt in ipairs(list) do
        values[opt.name] = opt.name
    end
    return values
end

local function GetFontSorting()
    local list = TTQ:GetFontList()
    local order = {}
    for _, opt in ipairs(list) do
        order[#order + 1] = opt.name
    end
    table.sort(order)
    return order
end

----------------------------------------------------------------------
-- Outline option values
----------------------------------------------------------------------
local OUTLINE_VALUES = {
    [""]             = "None",
    ["OUTLINE"]      = "Outline",
    ["THICKOUTLINE"] = "Thick",
    ["MONOCHROME"]   = "Mono",
}

----------------------------------------------------------------------
-- Helper: create a simple get/set pair for a profile key
----------------------------------------------------------------------
local function getter(key)
    return function() return TTQ:GetSetting(key) end
end

local function setter(key)
    return function(_, value)
        TTQ:SetSetting(key, value)
        TTQ:OnSettingChanged(key, value)
    end
end

local function colorGetter(key)
    return function()
        local c = TTQ:GetSetting(key)
        if c then return c.r, c.g, c.b end
        return 1, 1, 1
    end
end

local function colorSetter(key)
    return function(_, r, g, b)
        TTQ:SetSetting(key, { r = r, g = g, b = b })
        TTQ:OnSettingChanged(key, { r = r, g = g, b = b })
    end
end

----------------------------------------------------------------------
-- Build the AceConfig options table
----------------------------------------------------------------------
local function BuildOptions()
    local options = {
        name = "TommyTwoquests",
        handler = TTQ,
        type = "group",
        childGroups = "tab",
        args = {
            ------------------------------------------------------
            -- Display Tab
            ------------------------------------------------------
            display = {
                type = "group",
                name = "Display",
                order = 1,
                args = {
                    panelHeader = {
                        type = "header",
                        name = "Panel",
                        order = 1,
                    },
                    trackerWidth = {
                        type = "range",
                        name = "Tracker Width",
                        desc = "Width of the quest tracker frame.",
                        min = 150, max = 500, step = 10,
                        get = getter("trackerWidth"),
                        set = setter("trackerWidth"),
                        order = 2,
                    },
                    maxQuests = {
                        type = "range",
                        name = "Max Visible Quests",
                        desc = "Maximum number of quests shown at once.",
                        min = 1, max = 25, step = 1,
                        get = getter("maxQuests"),
                        set = setter("maxQuests"),
                        order = 3,
                    },
                    trackerMaxHeight = {
                        type = "range",
                        name = "Max Tracker Height",
                        desc = "Maximum height of the tracker in pixels. Content scrolls when exceeded.",
                        min = 200, max = 1200, step = 25,
                        get = getter("trackerMaxHeight"),
                        set = setter("trackerMaxHeight"),
                        order = 4,
                    },
                    locked = {
                        type = "toggle",
                        name = "Lock Position",
                        desc = "Prevent the tracker from being dragged.",
                        get = getter("locked"),
                        set = setter("locked"),
                        order = 5,
                    },
                    showTrackerHeader = {
                        type = "toggle",
                        name = "Show Tracker Header",
                        desc = "Show the title bar with 'Quests' text. When hidden, only the icon buttons appear.",
                        get = getter("showTrackerHeader"),
                        set = setter("showTrackerHeader"),
                        order = 6,
                    },
                    bgHeader = {
                        type = "header",
                        name = "Background",
                        order = 10,
                    },
                    showBackground = {
                        type = "toggle",
                        name = "Show Background",
                        desc = "Show a semi-transparent background behind the tracker.",
                        get = getter("showBackground"),
                        set = setter("showBackground"),
                        order = 11,
                    },
                    bgAlpha = {
                        type = "range",
                        name = "Background Opacity",
                        desc = "Opacity of the tracker background.",
                        min = 0, max = 1, step = 0.05,
                        isPercent = true,
                        get = getter("bgAlpha"),
                        set = setter("bgAlpha"),
                        order = 12,
                    },
                    classColorGradient = {
                        type = "toggle",
                        name = "Class Color Gradient",
                        desc = "Add a subtle class-colored gradient and glow to the background.",
                        get = getter("classColorGradient"),
                        set = setter("classColorGradient"),
                        order = 13,
                    },
                    visHeader = {
                        type = "header",
                        name = "Visibility",
                        order = 20,
                    },
                    hideInCombat = {
                        type = "toggle",
                        name = "Hide in Combat",
                        desc = "Hide the tracker when you enter combat.",
                        get = getter("hideInCombat"),
                        set = setter("hideInCombat"),
                        order = 21,
                    },
                    showAbandonAllButton = {
                        type = "toggle",
                        name = "Show Abandon All Button",
                        desc = "Show a skull button in the header to abandon all quests at once.",
                        get = getter("showAbandonAllButton"),
                        set = setter("showAbandonAllButton"),
                        order = 22,
                    },
                    showTrackerTooltips = {
                        type = "toggle",
                        name = "Show Tracker Tooltips",
                        desc = "Show tooltips when hovering over quests and section headers in the tracker.",
                        get = getter("showTrackerTooltips"),
                        set = setter("showTrackerTooltips"),
                        order = 23,
                    },
                    actionHeader = {
                        type = "header",
                        name = "Action Buttons",
                        order = 30,
                    },
                    questItemPosition = {
                        type = "select",
                        name = "Button Position",
                        desc = "Position of the quest item and group finder buttons. Right places them inside the row; Left floats them outside the tracker.",
                        values = {
                            ["right"] = "Right (inline)",
                            ["left"]  = "Left (outside)",
                        },
                        get = getter("questItemPosition"),
                        set = setter("questItemPosition"),
                        order = 31,
                    },
                },
            },
            ------------------------------------------------------
            -- Typography Tab
            ------------------------------------------------------
            typography = {
                type = "group",
                name = "Typography",
                order = 2,
                args = {
                    globalHeader = {
                        type = "header",
                        name = "Global Font",
                        order = 1,
                    },
                    useGlobalFont = {
                        type = "toggle",
                        name = "Use One Font for All",
                        desc = "When enabled, the global font is used for headers, quest names, and objectives.",
                        get = getter("useGlobalFont"),
                        set = setter("useGlobalFont"),
                        order = 2,
                    },
                    globalFont = {
                        type = "select",
                        name = "Global Font",
                        desc = "Font used for the entire tracker.",
                        values = GetFontValues,
                        sorting = GetFontSorting,
                        get = getter("globalFont"),
                        set = setter("globalFont"),
                        order = 3,
                    },
                    headerHeader = {
                        type = "header",
                        name = "Header",
                        order = 10,
                    },
                    headerFont = {
                        type = "select",
                        name = "Header Font",
                        desc = "Font for group headers (used when global font is off).",
                        values = GetFontValues,
                        sorting = GetFontSorting,
                        get = getter("headerFont"),
                        set = setter("headerFont"),
                        order = 11,
                    },
                    headerFontSize = {
                        type = "range",
                        name = "Header Size",
                        desc = "Font size for group headers.",
                        min = 8, max = 24, step = 1,
                        get = getter("headerFontSize"),
                        set = setter("headerFontSize"),
                        order = 12,
                    },
                    headerFontOutline = {
                        type = "select",
                        name = "Header Outline",
                        desc = "Outline style for group headers.",
                        values = OUTLINE_VALUES,
                        get = getter("headerFontOutline"),
                        set = setter("headerFontOutline"),
                        order = 13,
                    },
                    questHeader = {
                        type = "header",
                        name = "Quest Names",
                        order = 20,
                    },
                    questNameFont = {
                        type = "select",
                        name = "Quest Name Font",
                        desc = "Font for quest names (used when global font is off).",
                        values = GetFontValues,
                        sorting = GetFontSorting,
                        get = getter("questNameFont"),
                        set = setter("questNameFont"),
                        order = 21,
                    },
                    questNameFontSize = {
                        type = "range",
                        name = "Quest Name Size",
                        desc = "Font size for quest names.",
                        min = 8, max = 24, step = 1,
                        get = getter("questNameFontSize"),
                        set = setter("questNameFontSize"),
                        order = 22,
                    },
                    questNameFontOutline = {
                        type = "select",
                        name = "Quest Name Outline",
                        desc = "Outline style for quest names.",
                        values = OUTLINE_VALUES,
                        get = getter("questNameFontOutline"),
                        set = setter("questNameFontOutline"),
                        order = 23,
                    },
                    objectiveHeader = {
                        type = "header",
                        name = "Objectives",
                        order = 30,
                    },
                    objectiveFont = {
                        type = "select",
                        name = "Objective Font",
                        desc = "Font for objective text (used when global font is off).",
                        values = GetFontValues,
                        sorting = GetFontSorting,
                        get = getter("objectiveFont"),
                        set = setter("objectiveFont"),
                        order = 31,
                    },
                    objectiveFontSize = {
                        type = "range",
                        name = "Objective Size",
                        desc = "Font size for objective text.",
                        min = 8, max = 20, step = 1,
                        get = getter("objectiveFontSize"),
                        set = setter("objectiveFontSize"),
                        order = 32,
                    },
                    objectiveFontOutline = {
                        type = "select",
                        name = "Objective Outline",
                        desc = "Outline style for objective text.",
                        values = OUTLINE_VALUES,
                        get = getter("objectiveFontOutline"),
                        set = setter("objectiveFontOutline"),
                        order = 33,
                    },
                },
            },
            ------------------------------------------------------
            -- Colors Tab
            ------------------------------------------------------
            colors = {
                type = "group",
                name = "Colors",
                order = 3,
                args = {
                    headerColor = {
                        type = "color",
                        name = "Header Color",
                        desc = "Color for group header text.",
                        get = colorGetter("headerColor"),
                        set = colorSetter("headerColor"),
                        order = 1,
                    },
                    questNameColor = {
                        type = "color",
                        name = "Quest Name Color",
                        desc = "Color for quest name text.",
                        get = colorGetter("questNameColor"),
                        set = colorSetter("questNameColor"),
                        order = 2,
                    },
                    focusColor = {
                        type = "color",
                        name = "Focus Color",
                        desc = "Color for focused/super-tracked quest indicators.",
                        get = colorGetter("focusColor"),
                        set = colorSetter("focusColor"),
                        order = 3,
                    },
                    objectiveCompleteColor = {
                        type = "color",
                        name = "Objective Complete Color",
                        desc = "Color for completed objective text.",
                        get = colorGetter("objectiveCompleteColor"),
                        set = colorSetter("objectiveCompleteColor"),
                        order = 4,
                    },
                    objectiveIncompleteColor = {
                        type = "color",
                        name = "Objective Incomplete Color",
                        desc = "Color for incomplete objective text.",
                        get = colorGetter("objectiveIncompleteColor"),
                        set = colorSetter("objectiveIncompleteColor"),
                        order = 5,
                    },
                },
            },
            ------------------------------------------------------
            -- Icons & Info Tab
            ------------------------------------------------------
            icons = {
                type = "group",
                name = "Icons & Info",
                order = 4,
                args = {
                    iconsHeader = {
                        type = "header",
                        name = "Icons",
                        order = 1,
                    },
                    showIcons = {
                        type = "toggle",
                        name = "Show Quest Type Icons",
                        desc = "Display icons next to quests and category headers.",
                        get = getter("showIcons"),
                        set = setter("showIcons"),
                        order = 2,
                    },
                    infoHeader = {
                        type = "header",
                        name = "Information",
                        order = 10,
                    },
                    showObjectiveNumbers = {
                        type = "toggle",
                        name = "Show Objective Numbers",
                        desc = "Append progress numbers (e.g., 3/5) to objectives.",
                        get = getter("showObjectiveNumbers"),
                        set = setter("showObjectiveNumbers"),
                        order = 11,
                    },
                    showQuestLevel = {
                        type = "toggle",
                        name = "Show Quest Level",
                        desc = "Prefix quest names with their level.",
                        get = getter("showQuestLevel"),
                        set = setter("showQuestLevel"),
                        order = 12,
                    },
                    showHeaderCount = {
                        type = "toggle",
                        name = "Show Quest Count",
                        desc = "Show number of quests per group in headers.",
                        get = getter("showHeaderCount"),
                        set = setter("showHeaderCount"),
                        order = 13,
                    },
                },
            },
            ------------------------------------------------------
            -- Mythic+ Tab
            ------------------------------------------------------
            mythicplus = {
                type = "group",
                name = "Mythic+",
                order = 5,
                args = {
                    keystoneHeader = {
                        type = "header",
                        name = "Keystone",
                        order = 1,
                    },
                    autoInsertKeystone = {
                        type = "toggle",
                        name = "Auto-insert Keystone",
                        desc = "Automatically insert your Mythic+ keystone when you open the keystone socket UI.",
                        get = getter("autoInsertKeystone"),
                        set = setter("autoInsertKeystone"),
                        order = 2,
                    },
                },
            },
        },
    }

    return options
end

----------------------------------------------------------------------
-- Register AceConfig options + add profile tab from AceDBOptions
-- Called from Core.lua OnInitialize after AceDB is set up.
----------------------------------------------------------------------
function TTQ:RegisterAceOptions()
    local options = BuildOptions()

    -- Add profile management tab (auto-generated by AceDBOptions)
    options.args.profiles = LibStub("AceDBOptions-3.0"):GetOptionsTable(self.db)
    options.args.profiles.order = 99

    -- Register with AceConfig
    LibStub("AceConfig-3.0"):RegisterOptionsTable("TommyTwoquests", options)

    -- Add to Blizzard Settings panel
    self._optionsFrame = LibStub("AceConfigDialog-3.0"):AddToBlizOptions(
        "TommyTwoquests", "TommyTwoquests")
end

----------------------------------------------------------------------
-- Initialize settings (called from Core.lua OnEnable)
----------------------------------------------------------------------
function TTQ:InitSettings()
    -- AceConfig options are already registered in OnInitialize.
    -- Nothing else needed -- the panel is created on demand by AceConfigDialog.
end

----------------------------------------------------------------------
-- Open settings panel
----------------------------------------------------------------------
function TTQ:OpenSettings()
    -- Open the AceConfigDialog standalone window
    LibStub("AceConfigDialog-3.0"):Open("TommyTwoquests")
end

----------------------------------------------------------------------
-- Callback when any setting changes -- refresh tracker
----------------------------------------------------------------------
function TTQ:OnSettingChanged(key, value)
    -- Refresh backdrop if appearance changed
    if key == "showBackground" or key == "bgAlpha" or key == "bgColor" or key == "classColorGradient" then
        if self.UpdateTrackerBackdrop then self:UpdateTrackerBackdrop() end
    end

    -- Refresh abandon button visibility
    if key == "showAbandonAllButton" then
        if self.UpdateAbandonButtonVisibility then self:UpdateAbandonButtonVisibility() end
    end

    -- Refresh tracker width
    if key == "trackerWidth" and self.Tracker then
        self.Tracker:SetWidth(value)
    end

    -- Throttle tracker refresh (avoids 60fps rebuild storms from slider drags)
    if self.Tracker then
        self:ScheduleRefresh()
    end
end
