----------------------------------------------------------------------
-- TommyTwoquests -- Core.lua
-- Addon initialization via AceAddon-3.0, AceDB-3.0, AceConsole-3.0
----------------------------------------------------------------------
local AddonName, TTQ = ...
local table, ipairs, pairs, type, pcall, print = table, ipairs, pairs, type, pcall, print
local strtrim, Settings = strtrim, Settings

----------------------------------------------------------------------
-- Create the addon object using AceAddon with all core mixins.
-- The addon object IS the TTQ table (shared private namespace).
----------------------------------------------------------------------
LibStub("AceAddon-3.0"):NewAddon(TTQ, "TommyTwoquests",
    "AceConsole-3.0",
    "AceEvent-3.0",
    "AceTimer-3.0",
    "AceBucket-3.0",
    "AceHook-3.0"
)
_G.TommyTwoquests = TTQ

-- Read version from .toc metadata (single source of truth)
TTQ.Version = C_AddOns and C_AddOns.GetAddOnMetadata
    and C_AddOns.GetAddOnMetadata(AddonName, "Version") or "2.0.0"

----------------------------------------------------------------------
-- Legacy DB migration helpers
----------------------------------------------------------------------
-- Migrate font paths -> names
local function MigrateFontSettingsToNames(db)
    local keys = { "globalFont", "headerFont", "questNameFont", "objectiveFont" }
    local list = TTQ:GetFontList()
    for _, key in ipairs(keys) do
        local val = db[key]
        if val and type(val) == "string" and (val:find("/") or val:find("\\")) then
            local pathNorm = val:gsub("\\\\", "\\")
            for _, opt in ipairs(list) do
                local p = opt.value:gsub("\\\\", "\\")
                if p == pathNorm or opt.value == val then
                    db[key] = opt.name
                    break
                end
            end
        end
    end
end

-- Migrate grey objectiveCompleteColor -> emerald
local function MigrateCompleteColor(db)
    if db.objectiveCompleteColor then
        local c = db.objectiveCompleteColor
        if c.r == 0.5 and c.g == 0.5 and c.b == 0.5 then
            db.objectiveCompleteColor = { r = 0.20, g = 0.80, b = 0.40 }
        end
    end
end

-- Migrate superTrackedColor -> focusColor
local function MigrateFocusColor(db)
    local oldST = db.superTrackedColor
    if oldST and oldST.r == 0.4 and oldST.g == 0.8 and oldST.b == 1.0 then
        db.superTrackedColor = { r = 1.0, g = 0.82, b = 0.0 }
    end
    local fc = db.focusColor
    if fc and fc.r == 0.4 and fc.g == 0.8 and fc.b == 1.0 then
        db.focusColor = { r = 1.0, g = 0.82, b = 0.0 }
    end
    if not db.focusColor and db.superTrackedColor then
        db.focusColor = { r = db.superTrackedColor.r, g = db.superTrackedColor.g, b = db.superTrackedColor.b }
    end
    if db.clickToFocus == nil and db.clickToSuperTrack ~= nil then
        db.clickToFocus = db.clickToSuperTrack
    end
end

----------------------------------------------------------------------
-- One-time migration from the old flat TommyTwoquestsDB format
-- to AceDB-3.0's structured format.
-- Old format:  TommyTwoquestsDB = { trackerWidth = 250, ... }
-- New format:  TommyTwoquestsDB = { profileKeys = {...}, profiles = { Default = {...} } }
----------------------------------------------------------------------
local function MigrateLegacyDB()
    if not TommyTwoquestsDB then return end
    -- Detect old format: no profileKeys key means it's the old flat table
    if TommyTwoquestsDB.profileKeys then return end

    local oldDB = TommyTwoquestsDB

    -- Run all legacy migrations on the flat data first
    MigrateFontSettingsToNames(oldDB)
    MigrateCompleteColor(oldDB)
    MigrateFocusColor(oldDB)

    -- Wipe the global and let AceDB create fresh structure
    TommyTwoquestsDB = nil

    -- After AceDB:New() creates the clean structure, we'll copy old
    -- settings into the profile. Return the old data so OnInitialize
    -- can do the copy after AceDB init.
    return oldDB
end

----------------------------------------------------------------------
-- OnInitialize -- called after ADDON_LOADED, saved vars are available
----------------------------------------------------------------------
function TTQ:OnInitialize()
    -- Check for legacy DB format and extract old data if present
    local legacyData = MigrateLegacyDB()

    -- Initialize AceDB with our defaults
    self.db = LibStub("AceDB-3.0"):New("TommyTwoquestsDB", self.Defaults, true)

    -- If we migrated from legacy, copy old settings into the new profile
    if legacyData then
        local defaults = self.Defaults.profile
        for k, v in pairs(legacyData) do
            -- Only copy keys that exist in our defaults (skip _schemaVersion, etc.)
            if k ~= "_schemaVersion" and defaults[k] ~= nil then
                if type(v) == "table" then
                    -- Deep copy table values (colors, anchor, collapsed tables)
                    self.db.profile[k] = self:DeepCopyTable(v)
                else
                    self.db.profile[k] = v
                end
            end
        end
        self:Print("Settings migrated to new profile system.")
    end

    -- Register profile callbacks so the UI refreshes on profile changes
    self.db.RegisterCallback(self, "OnProfileChanged", "OnProfileRefresh")
    self.db.RegisterCallback(self, "OnProfileCopied", "OnProfileRefresh")
    self.db.RegisterCallback(self, "OnProfileReset", "OnProfileRefresh")

    -- Register slash commands via AceConsole
    self:RegisterChatCommand("ttq", "SlashCommand")
    self:RegisterChatCommand("tommytwoquests", "SlashCommand")

    -- Register AceConfig options (Settings.lua populates TTQ.AceOptions)
    if self.RegisterAceOptions then
        self:RegisterAceOptions()
    end
end

----------------------------------------------------------------------
-- OnEnable -- called at PLAYER_LOGIN, game data is available.
----------------------------------------------------------------------
function TTQ:OnEnable()
    -- Initialize the tracker (created in QuestTracker.lua)
    if self.InitTracker then
        self:InitTracker()
    end

    -- Initialize the settings panel (created in Settings.lua)
    if self.InitSettings then
        self:InitSettings()
    end

    self:Print("loaded. Type |cff00ccff/ttq|r for options.")
end

----------------------------------------------------------------------
-- Profile change callback -- refresh everything when profile switches
----------------------------------------------------------------------
function TTQ:OnProfileRefresh()
    if self.UpdateTrackerBackdrop then self:UpdateTrackerBackdrop() end
    if self.UpdateAbandonButtonVisibility then self:UpdateAbandonButtonVisibility() end
    if self.Tracker then
        self.Tracker:SetWidth(self:GetSetting("trackerWidth"))
        self:SafeRefreshTracker()
    end
end

----------------------------------------------------------------------
-- Simple deep copy for table values (used in migration)
----------------------------------------------------------------------
function TTQ:DeepCopyTable(src)
    if type(src) ~= "table" then return src end
    local copy = {}
    for k, v in pairs(src) do
        copy[k] = self:DeepCopyTable(v)
    end
    return copy
end

----------------------------------------------------------------------
-- Slash commands via AceConsole
----------------------------------------------------------------------
function TTQ:SlashCommand(msg)
    msg = strtrim(msg or ""):lower()
    if msg == "reset" then
        self:ResetDefaults()
        if self.Tracker then self:SafeRefreshTracker() end
        self:Print("Settings reset to defaults.")
    elseif msg == "toggle" then
        if self.Tracker then
            self.Tracker:SetShown(not self.Tracker:IsShown())
        end
    elseif msg == "zone" then
        local current = self:GetSetting("filterByCurrentZone")
        self:SetSetting("filterByCurrentZone", not current)
        if self.Tracker then self:SafeRefreshTracker() end
        self:Print("Zone filter " .. (not current and "enabled" or "disabled") .. ".")
    elseif msg == "dumpquests" then
        if not self.GetTrackedQuests then
            self:Print("Quest data module not ready.")
            return
        end

        local quests = self:GetTrackedQuests() or {}
        table.sort(quests, function(a, b)
            return (a.questID or 0) < (b.questID or 0)
        end)

        self:Print("Tracked quest dump: " .. #quests .. " entries")
        for _, q in ipairs(quests) do
            self:Print(string.format(
                "ID=%d | src=%s | type=%s | task=%s | bounty=%s | complete=%s | title=%s",
                q.questID or 0,
                q.source or "unknown",
                q.questType or "?",
                tostring(q.isTask and true or false),
                tostring(q.isBounty and true or false),
                tostring(q.isComplete and true or false),
                tostring(q.title or "")
            ))
        end
    elseif msg == "config" or msg == "options" then
        -- Open AceConfig dialog
        LibStub("AceConfigDialog-3.0"):Open("TommyTwoquests")
    else
        self:OpenSettings()
    end
end
