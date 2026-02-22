----------------------------------------------------------------------
-- TommyTwoquests — Core.lua
-- Addon initialization via AceAddon-3.0, saved variables, slash cmds
----------------------------------------------------------------------
local AddonName, TTQ = ...
local table, ipairs, type, pcall, print = table, ipairs, type, pcall, print
local CreateFrame, C_Timer = CreateFrame, C_Timer
local strtrim, SlashCmdList, Settings = strtrim, SlashCmdList, Settings

-- Create the addon object using AceAddon + AceEvent + AceTimer.
-- The addon object IS the TTQ table (shared private namespace).
-- AceEvent provides RegisterEvent/UnregisterEvent that use the
-- library’s own clean frame (created during XML loading), which
-- permanently solves the ADDON_ACTION_FORBIDDEN taint issue.
LibStub("AceAddon-3.0"):NewAddon(TTQ, "TommyTwoquests", "AceEvent-3.0", "AceTimer-3.0")
_G.TommyTwoquests = TTQ

-- Read version from .toc metadata (single source of truth)
TTQ.Version = C_AddOns and C_AddOns.GetAddOnMetadata
    and C_AddOns.GetAddOnMetadata(AddonName, "Version") or "1.2.0"

----------------------------------------------------------------------
-- OnInitialize — called after ADDON_LOADED, saved vars are available
----------------------------------------------------------------------
function TTQ:OnInitialize()
    if not TommyTwoquestsDB then
        TommyTwoquestsDB = self:DeepCopy(self.Defaults)
    else
        self:DeepMerge(TommyTwoquestsDB, self.Defaults)
    end
end

----------------------------------------------------------------------
-- OnEnable — called at PLAYER_LOGIN, game data is available.
-- This is the safe place to register all events.
----------------------------------------------------------------------
function TTQ:OnEnable()
    -- Run versioned data migrations
    self:RunMigrations()

    -- Build multi-callback dispatch table from queued registrations.
    -- AceEvent only allows one callback per event per object, so we
    -- collect all callbacks into a table keyed by event name and
    -- register a single dispatcher function for each event.
    self._eventCallbacks = self._eventCallbacks or {}
    if self._pendingEvents then
        for _, entry in ipairs(self._pendingEvents) do
            local ev = entry.event
            if not self._eventCallbacks[ev] then
                self._eventCallbacks[ev] = {}
            end
            self._eventCallbacks[ev][#self._eventCallbacks[ev] + 1] = entry.callback
        end
        self._pendingEvents = nil
    end

    -- Register each event once via AceEvent, dispatching to all
    -- queued callbacks for that event.
    for ev, cbs in pairs(self._eventCallbacks) do
        self:RegisterEvent(ev, function(event, ...)
            for _, cb in ipairs(cbs) do
                cb(event, ...)
            end
        end)
    end

    -- Initialize the tracker (created in QuestTracker.lua)
    if self.InitTracker then
        self:InitTracker()
    end

    -- Initialize the settings panel (created in Settings.lua)
    if self.InitSettings then
        self:InitSettings()
    end

    -- Print load message
    print("|cff00ccffTommyTwoquests|r loaded. Type |cff00ccff/ttq|r for options.")
end

----------------------------------------------------------------------
-- QueueEvent — called at file scope by other files during loading.
-- Events are collected and bulk-registered in OnEnable() above.
----------------------------------------------------------------------
function TTQ:QueueEvent(event, callback)
    if not self._pendingEvents then self._pendingEvents = {} end
    self._pendingEvents[#self._pendingEvents + 1] = {
        event = event,
        callback = callback,
    }
end

----------------------------------------------------------------------
-- Versioned migrations — run once per schema bump
-- Each migration receives the DB table and mutates it in place.
----------------------------------------------------------------------
TTQ.Migrations = {
    -- v1: Migrate font paths → names
    [1] = function(db)
        if TTQ.MigrateFontSettingsToNames then
            TTQ:MigrateFontSettingsToNames()
        end
    end,
    -- v2: Migrate grey objectiveCompleteColor → emerald
    [2] = function(db)
        if db.objectiveCompleteColor then
            local c = db.objectiveCompleteColor
            if c.r == 0.5 and c.g == 0.5 and c.b == 0.5 then
                db.objectiveCompleteColor = TTQ:DeepCopy(TTQ.Defaults.objectiveCompleteColor)
            end
        end
    end,
    -- v3: Migrate superTrackedColor → focusColor, clickToSuperTrack → clickToFocus
    [3] = function(db)
        local oldST = db.superTrackedColor
        if oldST and oldST.r == 0.4 and oldST.g == 0.8 and oldST.b == 1.0 then
            db.superTrackedColor = { r = 1.0, g = 0.82, b = 0.0 }
        end
        local fc = db.focusColor
        if fc and fc.r == 0.4 and fc.g == 0.8 and fc.b == 1.0 then
            db.focusColor = { r = 1.0, g = 0.82, b = 0.0 }
        end
        if not db.focusColor and db.superTrackedColor then
            db.focusColor = TTQ:DeepCopy(db.superTrackedColor)
        end
        if db.clickToFocus == nil and db.clickToSuperTrack ~= nil then
            db.clickToFocus = db.clickToSuperTrack
        end
    end,
}

function TTQ:RunMigrations()
    if not TommyTwoquestsDB then return end
    local v = TommyTwoquestsDB._schemaVersion or 0
    for i = v + 1, #self.Migrations do
        self.Migrations[i](TommyTwoquestsDB)
    end
    TommyTwoquestsDB._schemaVersion = #self.Migrations
end

----------------------------------------------------------------------
-- TTQ:OpenSettings() is defined in Settings.lua (custom panel toggle)

----------------------------------------------------------------------
-- Slash commands
----------------------------------------------------------------------
SLASH_TTQ1 = "/ttq"
SLASH_TTQ2 = "/tommytwoquests"
SlashCmdList["TTQ"] = function(msg)
    msg = strtrim(msg):lower()
    if msg == "reset" then
        TTQ:ResetDefaults()
        if TTQ.Tracker then TTQ:SafeRefreshTracker() end
        print("|cff00ccffTommyTwoquests|r: Settings reset to defaults.")
    elseif msg == "toggle" then
        if TTQ.Tracker then
            TTQ.Tracker:SetShown(not TTQ.Tracker:IsShown())
        end
    elseif msg == "zone" then
        local current = TTQ:GetSetting("filterByCurrentZone")
        TTQ:SetSetting("filterByCurrentZone", not current)
        if TTQ.Tracker then TTQ:SafeRefreshTracker() end
        print("|cff00ccffTommyTwoquests|r: Zone filter " .. (not current and "enabled" or "disabled") .. ".")
    else
        TTQ:OpenSettings()
    end
end
