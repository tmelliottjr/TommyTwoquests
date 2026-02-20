----------------------------------------------------------------------
-- TommyTwoquests — Core.lua
-- Addon initialization, event dispatcher, saved variables
----------------------------------------------------------------------
local AddonName, TTQ = ...
local table, ipairs, type, pcall, print = table, ipairs, type, pcall, print
local CreateFrame, C_Timer = CreateFrame, C_Timer
local strtrim, SlashCmdList, Settings = strtrim, SlashCmdList, Settings
_G.TommyTwoquests = TTQ

-- Read version from .toc metadata (single source of truth)
TTQ.Version = C_AddOns and C_AddOns.GetAddOnMetadata
    and C_AddOns.GetAddOnMetadata(AddonName, "Version") or "1.2.0"
TTQ.Callbacks = {}

----------------------------------------------------------------------
-- Event system — uses a clean, untainted frame for all registrations
----------------------------------------------------------------------
-- Create a separate, untainted event dispatcher frame
-- (distinct from any frame that might touch secure/protected content)
TTQ._EventDispatcher = CreateFrame("Frame")
TTQ._EventDispatcher:SetScript("OnEvent", function(_, event, ...)
    local cbs = TTQ.Callbacks[event]
    if cbs then
        for _, cb in ipairs(cbs) do
            cb(event, ...)
        end
    end
    -- When leaving combat, retry any deferred event registrations
    if event == "PLAYER_REGEN_ENABLED" and TTQ._deferredEvents then
        for ev in pairs(TTQ._deferredEvents) do
            TTQ._EventDispatcher:RegisterEvent(ev)
        end
        TTQ._deferredEvents = nil
    end
end)
TTQ._EventDispatcher:RegisterEvent("PLAYER_REGEN_ENABLED")

function TTQ:RegisterEvent(event, callback)
    if not self.Callbacks[event] then
        self.Callbacks[event] = {}
        if InCombatLockdown and InCombatLockdown() then
            -- Defer until combat ends
            if not self._deferredEvents then self._deferredEvents = {} end
            self._deferredEvents[event] = true
        else
            -- pcall guards against ADDON_ACTION_FORBIDDEN if this is
            -- called from a tainted execution path.  File-scope callers
            -- (the preferred approach) will always succeed.
            local ok, err = pcall(self._EventDispatcher.RegisterEvent,
                self._EventDispatcher, event)
            if not ok then
                -- Fall back: defer until combat ends (PLAYER_REGEN_ENABLED)
                if not self._deferredEvents then self._deferredEvents = {} end
                self._deferredEvents[event] = true
            end
        end
    end
    table.insert(self.Callbacks[event], callback)
end

function TTQ:UnregisterEvent(event)
    self.Callbacks[event] = nil
    self._EventDispatcher:UnregisterEvent(event)
end

----------------------------------------------------------------------
-- Saved Variables — load on ADDON_LOADED
----------------------------------------------------------------------
TTQ:RegisterEvent("ADDON_LOADED", function(event, addon)
    if addon ~= AddonName then return end

    if not TommyTwoquestsDB then
        TommyTwoquestsDB = TTQ:DeepCopy(TTQ.Defaults)
    else
        TTQ:DeepMerge(TommyTwoquestsDB, TTQ.Defaults)
    end

    TTQ:UnregisterEvent("ADDON_LOADED")

    -- Fire a custom ready event after a frame so all files are loaded.
    -- Use a one-shot OnUpdate instead of C_Timer.After to avoid tainting
    -- the execution path (C_Timer callbacks are dispatched through a
    -- secure frame, causing ADDON_ACTION_FORBIDDEN for RegisterEvent).
    local initFrame = CreateFrame("Frame")
    initFrame:SetScript("OnUpdate", function(self)
        self:SetScript("OnUpdate", nil)
        TTQ:OnReady()
    end)
end)

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
-- Ready handler — called once DB is loaded
----------------------------------------------------------------------
function TTQ:OnReady()
    -- Run versioned data migrations
    self:RunMigrations()

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
-- Open addon settings panel (custom Horizon-style panel)
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
