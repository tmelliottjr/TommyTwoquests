----------------------------------------------------------------------
-- TommyTwoquests -- Utils.lua
-- Shared utilities: font helpers, color conversion, atlas icon map
----------------------------------------------------------------------
local AddonName, TTQ = ...
local table, ipairs, pairs, string, type = table, ipairs, pairs, string, type
local C_QuestLog, C_Timer, pcall = C_QuestLog, C_Timer, pcall
local InCombatLockdown = InCombatLockdown

----------------------------------------------------------------------
-- Font list: use LibSharedMedia-3.0 (same as most addons) when available
----------------------------------------------------------------------
-- Fallback when LSM is not loaded (e.g. no other LSM addon)
TTQ.AvailableFontsFallback = {
    { name = "Friz Quadrata TT", value = "Fonts\\FRIZQT__.TTF" },
    { name = "Arial Narrow",     value = "Fonts\\ARIALN.TTF" },
    { name = "Morpheus",         value = "Fonts\\MORPHEUS.TTF" },
    { name = "Skurri",           value = "Fonts\\SKURRI.TTF" },
    { name = "Nimrod MT",        value = "Fonts\\NIM_____.ttf" },
    { name = "2002",             value = "Fonts\\2002.TTF" },
    { name = "2002 Bold",        value = "Fonts\\2002B.TTF" },
    { name = "MoK",              value = "Fonts\\K_Pagetext.TTF" },
}

-- Build font list from LibSharedMedia-3.0 (same list/previews as other addons)
function TTQ:GetFontList()
    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
    if LSM and LSM.List and LSM.Fetch then
        local list = LSM:List("font")
        if list and #list > 0 then
            local out = {}
            for _, name in ipairs(list) do
                local path = LSM:Fetch("font", name)
                if path and path ~= "" then
                    -- Normalize to double backslash so saved vars match dropdown selection
                    path = path:gsub("\\", "\\\\")
                    out[#out + 1] = { name = name, value = path }
                end
            end
            table.sort(out, function(a, b) return (a.name or "") < (b.name or "") end)
            return out
        end
    end
    return self.AvailableFontsFallback
end

TTQ.FontOutlines = {
    { name = "None",    value = "" },
    { name = "Outline", value = "OUTLINE" },
    { name = "Thick",   value = "THICKOUTLINE" },
    { name = "Mono",    value = "MONOCHROME" },
}

----------------------------------------------------------------------
-- Atlas icon mapping (MAP ICON GUIDE): quest type -> atlas texture name
-- Available = not accepted / available in world; Turnin = tracked or complete
----------------------------------------------------------------------
-- Default/available state (e.g. not yet turned in, or generic)
TTQ.QuestIcons = {
    -- Campaign: main story, shield/banner badge
    campaign      = "quest-campaign-available",
    -- Important: purple chevron (available); active = yellow-gold chevron (tracked)
    important     = "quest-important-available",
    legendary     = "quest-legendary-available",
    -- World quests: red ! in circle; PvP world = crossed swords
    worldquest    = "worldquest-tracker-questmarker",
    pvpworldquest = "questlog-questtypeicon-pvp",
    bonusobjective = "QuestBonusObjective",
    calling       = "quest-recurring-available",
    daily         = "quest-recurring-available",
    weekly        = "quest-recurring-available",
    dungeon       = "Dungeon",
    raid          = "Raid",
    group         = "QuestRepeatableTurnin",
    pvp           = "questlog-questtypeicon-pvp",
    -- Local stories / side quests: simple yellow !
    normal        = "QuestNormal",
    meta          = "quest-wrapper-available",
    account       = "QuestSharing-QuestLog-Active",
    -- Public events (major / minor)
    publicevent   = "quest-public-event",
    worldboss     = "quest-worldboss-available",
}

-- Turnin/active/complete variants (when quest is tracked or complete)
TTQ.QuestIconsTurnin = {
    campaign      = "quest-campaign-available", -- same style
    important     = "quest-important-turnin",   -- Active Important (yellow-gold chevron)
    legendary     = "quest-legendary-turnin",
    worldquest    = "worldquest-tracker-questmarker",
    pvpworldquest = "questlog-questtypeicon-pvp",
    bonusobjective = "QuestBonusObjective",
    calling       = "quest-recurring-turnin",
    daily         = "quest-recurring-turnin",
    weekly        = "quest-recurring-turnin",
    dungeon       = "Dungeon",
    raid          = "Raid",
    group         = "QuestRepeatableTurnin",
    pvp           = "questlog-questtypeicon-pvp",
    normal        = "QuestTurnin", -- complete/turnin local story
    meta          = "quest-wrapper-turnin",
    account       = "QuestSharing-QuestLog-Active",
    publicevent   = "quest-public-event",
    worldboss     = "quest-worldboss-turnin",
}

----------------------------------------------------------------------
-- Return the correct atlas for a quest based on type and state (tracked/complete)
-- Matches MAP ICON GUIDE: Campaign, Important vs Active Important, Local Stories, etc.
----------------------------------------------------------------------
function TTQ:GetQuestIconAtlas(quest)
    if not quest or not self.QuestIcons then
        return self.QuestIcons and self.QuestIcons.normal or "QuestNormal"
    end
    local qtype = quest.questType or "normal"
    -- Use turnin/complete icon only when quest is actually complete or focused
    local useTurnin = quest.isSuperTracked
    if quest.isComplete then
        useTurnin = true
    end
    -- Important: "Active Important" (yellow-gold chevron) when tracked
    if qtype == "important" then
        useTurnin = true
    end
    local atlas
    if useTurnin and self.QuestIconsTurnin and self.QuestIconsTurnin[qtype] then
        atlas = self.QuestIconsTurnin[qtype]
    else
        atlas = self.QuestIcons[qtype] or self.QuestIcons.normal
    end
    return atlas
end

----------------------------------------------------------------------
-- Quest type display names
----------------------------------------------------------------------
TTQ.QuestTypeNames = {
    campaign      = "Campaign",
    important     = "Important",
    legendary     = "Legendary",
    worldquest    = "World Quests",
    pvpworldquest = "PvP World Quests",
    bonusobjective = "Bonus Objectives",
    calling       = "Callings",
    daily         = "Daily",
    weekly        = "Weekly",
    dungeon       = "Dungeon",
    raid          = "Raid",
    group         = "Group",
    pvp           = "PvP",
    normal        = "Side Quests",
    meta          = "Meta Quests",
    account       = "Account",
}

----------------------------------------------------------------------
-- Quest type sort priority (lower = higher on the list)
----------------------------------------------------------------------
TTQ.QuestTypePriority = {
    campaign      = 1,
    important     = 2,
    legendary     = 3,
    calling       = 4,
    worldquest    = 5,
    pvpworldquest = 5,
    bonusobjective = 6,
    daily         = 7,
    weekly        = 8,
    dungeon       = 9,
    raid          = 10,
    group         = 11,
    pvp           = 12,
    account       = 13,
    meta          = 14,
    normal        = 15,
}

----------------------------------------------------------------------
-- Color helpers
----------------------------------------------------------------------
function TTQ:RGBToHex(r, g, b)
    return string.format("|cff%02x%02x%02x", r * 255, g * 255, b * 255)
end

function TTQ:ColorText(text, color)
    return self:RGBToHex(color.r, color.g, color.b) .. text .. "|r"
end

----------------------------------------------------------------------
-- Font string factory
----------------------------------------------------------------------
function TTQ:CreateText(parent, size, color, justify)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    fs:SetFont("Fonts\\FRIZQT__.TTF", size or 12, "")
    fs:SetShadowOffset(1, -1)
    fs:SetShadowColor(0, 0, 0, 0.8)
    if color then
        fs:SetTextColor(color.r, color.g, color.b, color.a or 1)
    end
    fs:SetJustifyH(justify or "LEFT")
    fs:SetWordWrap(false)
    return fs
end

----------------------------------------------------------------------
-- Progress calculation
----------------------------------------------------------------------
function TTQ:CalcProgress(objectives)
    if not objectives or #objectives == 0 then return 0, 0, 0 end
    local fulfilled, required = 0, 0
    for _, obj in ipairs(objectives) do
        if obj.finished then
            local objRequired = tonumber(obj.numRequired)
            if objRequired and objRequired > 0 then
                fulfilled = fulfilled + objRequired
                required = required + objRequired
            else
                fulfilled = fulfilled + 1
                required = required + 1
            end
        else
            local objFulfilled = tonumber(obj.numFulfilled)
            local objRequired = tonumber(obj.numRequired)

            if objRequired and objRequired > 0 then
                fulfilled = fulfilled + (objFulfilled or 0)
                required = required + objRequired
            else
                local text = obj.text or ""
                local pctText = text ~= "" and string.match(text, "(%d+)%s*%%") or nil
                if pctText then
                    local pctValue = tonumber(pctText) or 0
                    if pctValue < 0 then pctValue = 0 end
                    if pctValue > 100 then pctValue = 100 end
                    fulfilled = fulfilled + pctValue
                    required = required + 100
                else
                    local numText, denomText = string.match(text, "(%d+)%s*/%s*(%d+)")
                    local parsedNum = numText and tonumber(numText) or nil
                    local parsedDenom = denomText and tonumber(denomText) or nil
                    if parsedNum and parsedDenom and parsedDenom > 0 then
                        fulfilled = fulfilled + parsedNum
                        required = required + parsedDenom
                    else
                        required = required + 1
                    end
                end
            end
        end
    end
    local pct = required > 0 and (fulfilled / required) or 0
    if pct < 0 then pct = 0 end
    if pct > 1 then pct = 1 end
    return pct, fulfilled, required
end

----------------------------------------------------------------------
-- String truncation
----------------------------------------------------------------------
function TTQ:Truncate(text, maxLen)
    if not text then return "" end
    if #text <= maxLen then return text end
    return string.sub(text, 1, maxLen - 3) .. "..."
end

----------------------------------------------------------------------
-- Deep copy a table
----------------------------------------------------------------------
function TTQ:DeepCopy(src)
    if type(src) ~= "table" then return src end
    local copy = {}
    for k, v in pairs(src) do
        copy[k] = self:DeepCopy(v)
    end
    return copy
end

----------------------------------------------------------------------
-- Deep merge: fills missing keys in dst from src
----------------------------------------------------------------------
function TTQ:DeepMerge(dst, src)
    for k, v in pairs(src) do
        if type(v) == "table" then
            if type(dst[k]) ~= "table" then
                dst[k] = self:DeepCopy(v)
            else
                self:DeepMerge(dst[k], v)
            end
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
    return dst
end

----------------------------------------------------------------------
-- Tracker tooltip helpers -- centralises the showTrackerTooltips guard.
-- Use for quest items, section headers, recipes, reagents -- anything
-- inside the tracker content area.  Header-bar buttons (gear, filter,
-- abandon, collapse) should call GameTooltip directly so they always
-- show tooltips regardless of this setting.
--
-- Usage:
--   if TTQ:BeginTooltip(owner) then
--       GameTooltip:SetText(...)
--       GameTooltip:AddLine(...)
--       TTQ:EndTooltip()
--   end
----------------------------------------------------------------------
function TTQ:BeginTooltip(owner, anchor)
    if not self:GetSetting("showTrackerTooltips") then return false end
    GameTooltip:SetOwner(owner, anchor or "ANCHOR_LEFT")
    return true
end

function TTQ:EndTooltip()
    GameTooltip:Show()
end

function TTQ:HideTooltip()
    GameTooltip:Hide()
end

----------------------------------------------------------------------
-- Safe font setter -- applies font with pcall fallback to default
----------------------------------------------------------------------
function TTQ:SafeSetFont(fontString, face, size, outline)
    if not fontString then return end
    if not pcall(fontString.SetFont, fontString, face, size, outline or "") then
        pcall(fontString.SetFont, fontString, "Fonts\\FRIZQT__.TTF", size, outline or "")
    end
end

----------------------------------------------------------------------
-- Combat-lockdown deferred refresh.
-- When a refresh is requested during combat, we flag it and listen
-- for PLAYER_REGEN_ENABLED so we can rebuild once combat ends.
-- Uses QueueEvent to avoid tainted RegisterEvent calls.
----------------------------------------------------------------------
do
    function TTQ:_DeferRefreshAfterCombat()
        self._refreshPendingCombat = true
        -- PLAYER_REGEN_ENABLED is already registered via QueueEvent
        -- in QuestTracker.lua (combat events).  The callback in
        -- SafeRefreshTracker checks _refreshPendingCombat and handles it.
    end
end

----------------------------------------------------------------------
-- Debounced tracker refresh -- waits for event bursts to settle.
-- Always resets the timer so the refresh fires 0.1s after the LAST
-- event, ensuring the quest log is in its final state (e.g. after
-- QUEST_TURNED_IN + QUEST_REMOVED both fire before we rebuild).
----------------------------------------------------------------------
function TTQ:ScheduleRefresh()
    if self._refreshTimer then
        self._refreshTimer:Cancel()
    end
    self._refreshTimer = C_Timer.NewTimer(0.1, function()
        self._refreshTimer = nil
        if self.RefreshTracker then
            self:SafeRefreshTracker()
        end
    end)
end

----------------------------------------------------------------------
-- Error-boundary wrapper for RefreshTracker
----------------------------------------------------------------------
function TTQ:SafeRefreshTracker()
    -- Cancel any pending throttled refresh to avoid a redundant rebuild
    if self._refreshTimer then
        self._refreshTimer:Cancel()
        self._refreshTimer = nil
    end

    -- During combat, do a lightweight objective visual refresh only,
    -- then defer the full rebuild until PLAYER_REGEN_ENABLED.
    if InCombatLockdown() then
        if self.RefreshObjectiveProgressInCombat then
            self:RefreshObjectiveProgressInCombat()
        end
        self:_DeferRefreshAfterCombat()
        return
    end

    local ok, err = xpcall(self.RefreshTracker, function(e)
        return e .. "\n" .. (debugstack and debugstack() or "")
    end, self)
    if not ok then
        if not self._lastRefreshError or self._lastRefreshError ~= err then
            self._lastRefreshError = err
            print("|cffff0000TommyTwoquests error:|r " .. tostring(err))
        end
    end
end

----------------------------------------------------------------------
-- Toggle a collapsed-state entry in a saved table setting
----------------------------------------------------------------------
function TTQ:ToggleCollapse(settingKey, id)
    local tbl = self:GetSetting(settingKey)
    if type(tbl) ~= "table" then tbl = {} end
    tbl = self:DeepCopy(tbl)
    if tbl[id] then
        tbl[id] = nil
    else
        tbl[id] = true
    end
    self:SetSetting(settingKey, tbl)
end

----------------------------------------------------------------------
-- Generic object pool factory
-- createFn(parent) -> new object (must have .frame field)
-- resetFn(obj)     -> clean up object before returning to pool
----------------------------------------------------------------------
function TTQ:CreateObjectPool(createFn, resetFn)
    local pool = {}
    local poolObj = {}

    function poolObj:Acquire(parent)
        local item = table.remove(pool)
        if not item then
            item = createFn(parent)
        else
            if item.frame then
                item.frame:SetParent(parent)
                item.frame:Show()
            end
        end
        return item
    end

    function poolObj:Release(item)
        if resetFn then resetFn(item) end
        if item.frame then
            item.frame:Hide()
            item.frame:ClearAllPoints()
        end
        table.insert(pool, item)
    end

    return poolObj
end
