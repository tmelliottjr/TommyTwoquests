----------------------------------------------------------------------
-- TommyTwoquests — Filters.lua
-- Filter engine: by type, zone, frequency
----------------------------------------------------------------------
local AddonName, TTQ = ...
local pairs, ipairs, table = pairs, ipairs, table

----------------------------------------------------------------------
-- Filter setting keys mapped to quest types
----------------------------------------------------------------------
local TYPE_FILTER_MAP = {
    campaign      = "showCampaign",
    important     = "showImportant",
    legendary     = "showLegendary",
    worldquest    = "showWorldQuests",
    pvpworldquest = "showWorldQuests",
    calling       = "showCallings",
    daily         = "showDailies",
    weekly        = "showWeeklies",
    dungeon       = "showDungeonRaid",
    raid          = "showDungeonRaid",
    group         = "showSideQuests",
    pvp           = "showPvP",
    normal        = "showSideQuests",
    meta          = "showMeta",
    account       = "showAccount",
}

----------------------------------------------------------------------
-- Apply all active filters to a quest list
-- Returns a filtered + sorted list and a table of group headers.
-- When groupCurrentZoneQuests is enabled, quests in the player's
-- current zone are pulled into a special zone group at the top.
----------------------------------------------------------------------
function TTQ:FilterAndGroupQuests(quests)
    local filtered = {}
    local zoneQuestIDs = nil
    local groupByZone = self:GetSetting("groupCurrentZoneQuests")

    -- Zone filter: build zone lookup if enabled (or if zone grouping is on)
    if self:GetSetting("filterByCurrentZone") or groupByZone then
        zoneQuestIDs = self:GetQuestsForCurrentZone()
    end

    for _, quest in ipairs(quests) do
        local pass = true

        -- Type filter: only hide when the setting is explicitly false
        local filterKey = TYPE_FILTER_MAP[quest.questType]
        if filterKey then
            local enabled = self:GetSetting(filterKey)
            if enabled == false then
                pass = false
            end
        end

        -- Zone filter (strict mode: only show zone quests)
        if pass and self:GetSetting("filterByCurrentZone") and zoneQuestIDs then
            if not zoneQuestIDs[quest.questID] then
                pass = false
            end
        end

        -- Collapse completed
        if pass and self:GetSetting("collapseCompleted") and quest.isComplete then
            -- Still show, but they'll be rendered differently
        end

        -- Tag whether this quest is in the current zone (for grouping)
        if pass and groupByZone and zoneQuestIDs then
            quest._isInCurrentZone = zoneQuestIDs[quest.questID] and true or false
        else
            quest._isInCurrentZone = false
        end

        if pass then
            table.insert(filtered, quest)
        end
    end

    -- Sort: by type priority, then alphabetical
    table.sort(filtered, function(a, b)
        local prioA = TTQ.QuestTypePriority[a.questType] or 99
        local prioB = TTQ.QuestTypePriority[b.questType] or 99
        if prioA ~= prioB then return prioA < prioB end
        return (a.title or "") < (b.title or "")
    end)

    -- Group by type using a lookup table (avoids relying on sort contiguity)
    local groups = {}
    local groupByType = {} -- questType → group table
    local groupOrder = {}  -- ordered list of quest types as encountered

    -- Helper: add a quest to its type group, creating the group if needed
    local function addToTypeGroup(quest)
        local qtype = quest.questType
        if not groupByType[qtype] then
            groupByType[qtype] = {
                questType = qtype,
                headerName = TTQ.QuestTypeNames[qtype] or "Quests",
                quests = {},
            }
            table.insert(groupOrder, qtype)
        end
        table.insert(groupByType[qtype].quests, quest)
    end

    -- If zone grouping is enabled, build the zone group first
    if groupByZone and zoneQuestIDs then
        local mapID = self:GetCurrentZoneMapID()
        local mapInfo = mapID and C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(mapID)
        local zoneName = (mapInfo and mapInfo.name) or "Current Zone"

        local zoneGroup = {
            questType = "_zone",
            headerName = zoneName,
            quests = {},
        }

        -- Split filtered quests into zone group and remaining
        for _, quest in ipairs(filtered) do
            if quest._isInCurrentZone then
                table.insert(zoneGroup.quests, quest)
            else
                addToTypeGroup(quest)
            end
        end

        -- Sort zone group: world quests at the top, then by priority/alpha
        if #zoneGroup.quests > 0 then
            table.sort(zoneGroup.quests, function(a, b)
                local aIsWQ = (a.questType == "worldquest" or a.questType == "pvpworldquest") and true or false
                local bIsWQ = (b.questType == "worldquest" or b.questType == "pvpworldquest") and true or false
                if aIsWQ ~= bIsWQ then
                    return aIsWQ -- world quests first
                end
                local prioA = TTQ.QuestTypePriority[a.questType] or 99
                local prioB = TTQ.QuestTypePriority[b.questType] or 99
                if prioA ~= prioB then return prioA < prioB end
                return (a.title or "") < (b.title or "")
            end)
            table.insert(groups, zoneGroup)
        end
    else
        for _, quest in ipairs(filtered) do
            addToTypeGroup(quest)
        end
    end

    -- Sort groups by their type priority, then append in order.
    -- When zone grouping is off, push world quest groups to the bottom
    -- so they sit below regular tracked quests.
    table.sort(groupOrder, function(a, b)
        if not groupByZone then
            local aIsWQ = (a == "worldquest" or a == "pvpworldquest")
            local bIsWQ = (b == "worldquest" or b == "pvpworldquest")
            if aIsWQ ~= bIsWQ then
                return bIsWQ -- non-WQ sorts before WQ
            end
        end
        local prioA = TTQ.QuestTypePriority[a] or 99
        local prioB = TTQ.QuestTypePriority[b] or 99
        return prioA < prioB
    end)

    for _, qtype in ipairs(groupOrder) do
        table.insert(groups, groupByType[qtype])
    end

    return filtered, groups
end
