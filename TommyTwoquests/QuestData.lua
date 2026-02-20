----------------------------------------------------------------------
-- TommyTwoquests — QuestData.lua
-- Quest log data layer: wraps C_QuestLog APIs into structured data
----------------------------------------------------------------------
local AddonName, TTQ = ...
local table, ipairs = table, ipairs
local C_QuestLog, C_Map, C_SuperTrack, C_TaskQuest = C_QuestLog, C_Map, C_SuperTrack, C_TaskQuest

----------------------------------------------------------------------
-- Tag ID → quest classification
----------------------------------------------------------------------
local TAG_MAP = {
    [81]  = "dungeon",
    [62]  = "raid",
    [1]   = "group",
    [41]  = "pvp",
    [83]  = "legendary",
    [109] = "worldquest",
    [102] = "account",
    [84]  = "normal",     -- escort
    [85]  = "dungeon",    -- heroic
    [88]  = "raid",       -- raid10
    [89]  = "raid",       -- raid25
    [98]  = "dungeon",    -- scenario
    [104] = "normal",     -- side quest
    [258] = "meta",       -- meta / wrapper quest
    [261] = "meta",       -- meta quest (alternate)
    [263] = "worldquest", -- public quest
    [255] = "pvp",        -- war mode
}

----------------------------------------------------------------------
-- Classify a quest by examining all available metadata
-- Uses C_QuestInfoSystem.GetQuestClassification (modern API) first,
-- then falls back to tag-based detection for dungeon/raid/pvp/group.
----------------------------------------------------------------------
local function ClassifyQuest(questID, info)
    -- World quests: check first since they override everything
    if C_QuestLog.IsWorldQuest and C_QuestLog.IsWorldQuest(questID) then
        -- Distinguish PvP world quests
        local tagInfo = C_QuestLog.GetQuestTagInfo(questID)
        if tagInfo and (tagInfo.tagID == 41 or tagInfo.tagID == 255) then
            return "pvpworldquest"
        end
        return "worldquest"
    end

    -- Modern classification API (Retail 10.x+)
    if C_QuestInfoSystem and C_QuestInfoSystem.GetQuestClassification then
        local qc = C_QuestInfoSystem.GetQuestClassification(questID)
        if qc then
            if qc == Enum.QuestClassification.Campaign then return "campaign" end
            if qc == Enum.QuestClassification.Calling then return "calling" end
            if qc == Enum.QuestClassification.Important then return "important" end
            if qc == Enum.QuestClassification.Legendary then return "legendary" end
            if qc == Enum.QuestClassification.Meta then return "meta" end
            if qc == Enum.QuestClassification.Recurring then
                -- Recurring can be daily or weekly; check frequency
                if info.frequency and info.frequency == Enum.QuestFrequency.Daily then
                    return "daily"
                end
                return "weekly"
            end
            -- Questline: significant story quests, treat as important
            if qc == Enum.QuestClassification.Questline then return "important" end
            -- BonusObjective: treat as world quest / task
            if qc == Enum.QuestClassification.BonusObjective then return "worldquest" end
            -- Threat: e.g. N'Zoth assaults, treat as world quest
            if qc == Enum.QuestClassification.Threat then return "worldquest" end
            -- WorldQuest classification (redundant with IsWorldQuest check above but safe)
            if qc == Enum.QuestClassification.WorldQuest then return "worldquest" end
            -- Normal: fall through to tag/frequency checks
        end
    end

    -- Campaign fallback (campaignID check for older clients)
    if info.campaignID and info.campaignID > 0 then
        return "campaign"
    end

    -- Tag-based classification (dungeon, raid, group, pvp, meta, account)
    local tagInfo = C_QuestLog.GetQuestTagInfo(questID)
    if tagInfo then
        if tagInfo.worldQuestType then
            if tagInfo.tagID == 41 or tagInfo.tagID == 255 then
                return "pvpworldquest"
            end
            return "worldquest"
        end
        if tagInfo.tagID and TAG_MAP[tagInfo.tagID] then
            return TAG_MAP[tagInfo.tagID]
        end
    end

    -- Legacy Is* checks (fallback if classification API unavailable)
    if C_QuestLog.IsQuestCalling and C_QuestLog.IsQuestCalling(questID) then
        return "calling"
    end
    if C_QuestLog.IsImportantQuest and C_QuestLog.IsImportantQuest(questID) then
        return "important"
    end

    -- Frequency-based
    if info.frequency then
        if info.frequency == Enum.QuestFrequency.Daily then
            return "daily"
        elseif info.frequency == Enum.QuestFrequency.Weekly then
            return "weekly"
        end
    end

    return "normal"
end

----------------------------------------------------------------------
-- Build the complete quest list from the quest log
----------------------------------------------------------------------
function TTQ:GetTrackedQuests()
    local quests = {}
    local numEntries = C_QuestLog.GetNumQuestLogEntries()

    for i = 1, numEntries do
        local info = C_QuestLog.GetInfo(i)
        -- Allow hidden entries through if they are task quests (world quests /
        -- bonus objectives that activate when the player enters the area).
        -- Normal hidden quests are still skipped.
        if info and not info.isHeader and (not info.isHidden or info.isTask) then
            local questID = info.questID
            local isOnMap = true -- default

            -- Only include tracked or focused quests
            local isTracked = C_QuestLog.GetQuestWatchType(questID) ~= nil
            local isSuperTracked = C_SuperTrack.GetSuperTrackedQuestID() == questID
            local isTask = info.isTask -- world quests / bonus objectives
            local isBounty = info.isBounty

            if isTracked or isSuperTracked or isTask or isBounty then
                local objectives = C_QuestLog.GetQuestObjectives(questID)
                local questType = ClassifyQuest(questID, info)
                local pct, fulfilled, required = self:CalcProgress(objectives)

                -- Use game's completion state only (avoids wrong "complete" icon/title for side quests)
                local isComplete = C_QuestLog.IsComplete(questID) and true or false

                -- Zone info
                local questMapID = nil
                if C_QuestLog.GetQuestAdditionalHighlights then
                    -- Try to get map for this quest
                end

                -- Get quest level
                local level = info.level or 0
                local difficultyLevel = info.difficultyLevel or 0

                -- Fetch quest description when there are no objectives
                local questDescription = nil
                if (not objectives or #objectives == 0) and not isComplete then
                    -- GetQuestLogQuestText requires the quest to be selected
                    local oldSelection = C_QuestLog.GetSelectedQuest and C_QuestLog.GetSelectedQuest()
                    if C_QuestLog.SetSelectedQuest then
                        C_QuestLog.SetSelectedQuest(questID)
                    end
                    local desc
                    if GetQuestLogQuestText then
                        _, desc = GetQuestLogQuestText()
                    end
                    questDescription = desc and desc ~= "" and desc or nil
                    -- Restore previous selection
                    if oldSelection and C_QuestLog.SetSelectedQuest then
                        C_QuestLog.SetSelectedQuest(oldSelection)
                    end
                end

                table.insert(quests, {
                    questID          = questID,
                    title            = info.title or "Unknown Quest",
                    level            = level,
                    difficultyLevel  = difficultyLevel,
                    questType        = questType,
                    frequency        = info.frequency or 0,
                    isComplete       = isComplete,
                    isSuperTracked   = isSuperTracked,
                    isTask           = isTask or false,
                    isBounty         = isBounty or false,
                    objectives       = objectives or {},
                    progress         = pct,
                    fulfilled        = fulfilled,
                    required         = required,
                    questLogIndex    = i,
                    campaignID       = info.campaignID,
                    questDescription = questDescription,
                })
            end
        end
    end

    return quests
end

----------------------------------------------------------------------
-- Get current zone map ID
----------------------------------------------------------------------
function TTQ:GetCurrentZoneMapID()
    return C_Map.GetBestMapForUnit("player")
end

----------------------------------------------------------------------
-- Get quests relevant to current zone
----------------------------------------------------------------------
function TTQ:GetQuestsForCurrentZone()
    local mapID = self:GetCurrentZoneMapID()
    if not mapID then return {} end

    local questsOnMap = C_QuestLog.GetQuestsOnMap(mapID)
    if not questsOnMap then return {} end

    local zoneQuestIDs = {}
    for _, quest in ipairs(questsOnMap) do
        zoneQuestIDs[quest.questID] = true
    end
    return zoneQuestIDs
end
