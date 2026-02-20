----------------------------------------------------------------------
-- TommyTwoquests — Utils.lua
-- Shared utilities: font helpers, color conversion, atlas icon map
----------------------------------------------------------------------
local AddonName, TTQ = ...
local table, ipairs, pairs, string, type = table, ipairs, pairs, string, type
local C_QuestLog, C_Timer, pcall = C_QuestLog, C_Timer, pcall

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
-- Atlas icon mapping (MAP ICON GUIDE): quest type → atlas texture name
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
    daily         = 6,
    weekly        = 7,
    dungeon       = 8,
    raid          = 9,
    group         = 10,
    pvp           = 11,
    account       = 12,
    meta          = 13,
    normal        = 14,
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
            fulfilled = fulfilled + (obj.numRequired or 1)
            required = required + (obj.numRequired or 1)
        else
            fulfilled = fulfilled + (obj.numFulfilled or 0)
            required = required + (obj.numRequired or 1)
        end
    end
    local pct = required > 0 and (fulfilled / required) or 0
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
-- Safe font setter — applies font with pcall fallback to default
----------------------------------------------------------------------
function TTQ:SafeSetFont(fontString, face, size, outline)
    if not fontString then return end
    if not pcall(fontString.SetFont, fontString, face, size, outline or "") then
        pcall(fontString.SetFont, fontString, "Fonts\\FRIZQT__.TTF", size, outline or "")
    end
end

----------------------------------------------------------------------
-- Throttled tracker refresh — coalesces rapid event bursts
----------------------------------------------------------------------
function TTQ:ScheduleRefresh()
    if not self._refreshTimer then
        self._refreshTimer = C_Timer.NewTimer(0.1, function()
            self._refreshTimer = nil
            if self.RefreshTracker then
                self:SafeRefreshTracker()
            end
        end)
    end
end

----------------------------------------------------------------------
-- Error-boundary wrapper for RefreshTracker
----------------------------------------------------------------------
function TTQ:SafeRefreshTracker()
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
-- createFn(parent) → new object (must have .frame field)
-- resetFn(obj)     → clean up object before returning to pool
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
