----------------------------------------------------------------------
-- TommyTwoquests — QuestData.lua
-- Quest log data layer: wraps C_QuestLog APIs into structured data
----------------------------------------------------------------------
local AddonName, TTQ                               = ...
local table, ipairs                                = table, ipairs
local C_QuestLog, C_Map, C_SuperTrack, C_TaskQuest = C_QuestLog, C_Map, C_SuperTrack, C_TaskQuest
local C_Timer                                      = C_Timer
local GetQuestLogQuestText                         = GetQuestLogQuestText

----------------------------------------------------------------------
-- Quest description cache  (avoids tainting quest-log selection state)
-- Descriptions are fetched asynchronously so that SetSelectedQuest is
-- never called in the same execution path as the tracker refresh.
----------------------------------------------------------------------
local descCache                                    = {} -- [questID] = description string | false (pending)
local descPending                                  = {} -- set of questIDs currently queued for fetch

local function FetchDescriptionAsync(questID)
    if descCache[questID] ~= nil or descPending[questID] then return end
    descPending[questID] = true
    C_Timer.After(0, function()
        descPending[questID] = nil
        if not C_QuestLog.GetInfo then return end -- safety
        local old = C_QuestLog.GetSelectedQuest and C_QuestLog.GetSelectedQuest()
        if C_QuestLog.SetSelectedQuest then
            C_QuestLog.SetSelectedQuest(questID)
        end
        local desc
        if GetQuestLogQuestText then
            _, desc = GetQuestLogQuestText()
        end
        descCache[questID] = (desc and desc ~= "") and desc or false
        if C_QuestLog.SetSelectedQuest then
            C_QuestLog.SetSelectedQuest(old or 0)
        end
    end)
end

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
-- Determine if a quest is eligible for the Group Finder shortcut.
-- Relies purely on WoW API signals — no hardcoded quest lists.
----------------------------------------------------------------------
local function IsGroupFinderEligible(questID, info)
    -- Suggested group size > 1 means the quest is designed for groups
    if info.suggestedGroup and info.suggestedGroup > 1 then
        return true
    end

    -- Elite / group / raid world quests (dragon-framed WQs, world bosses)
    local tagInfo = C_QuestLog.GetQuestTagInfo(questID)
    if tagInfo then
        if tagInfo.isElite then return true end
    end

    return false
end

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
        if info and not info.isHeader then
            local questID = info.questID
            local isOnMap = true -- default

            -- Determine tracking and world-quest status early so the
            -- hidden-entry filter below can use them.
            local isTracked = C_QuestLog.GetQuestWatchType(questID) ~= nil
            local isSuperTracked = C_SuperTrack.GetSuperTrackedQuestID() == questID
            local isTask = info.isTask -- world quests / bonus objectives
            local isBounty = info.isBounty
            local isWorldQuest = C_QuestLog.IsWorldQuest and C_QuestLog.IsWorldQuest(questID)

            -- Include quests that are tracked, focused, task-type, bounty,
            -- or world quests.  Hidden quests are allowed through when they
            -- meet any of these criteria (covers event / prepatch quests
            -- with unusual isHidden flags).
            if isTracked or isSuperTracked or isTask or isBounty or isWorldQuest then
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
                -- Uses async cache to avoid tainting quest-log selection state
                local questDescription = nil
                if (not objectives or #objectives == 0) and not isComplete then
                    local cached = descCache[questID]
                    if cached then            -- string = already fetched
                        questDescription = cached
                    elseif cached == nil then -- not yet requested
                        FetchDescriptionAsync(questID)
                    end
                    -- cached == false means fetch is pending; show nothing yet
                end

                table.insert(quests, {
                    questID               = questID,
                    title                 = info.title or "Unknown Quest",
                    level                 = level,
                    difficultyLevel       = difficultyLevel,
                    questType             = questType,
                    frequency             = info.frequency or 0,
                    isComplete            = isComplete,
                    isSuperTracked        = isSuperTracked,
                    isTask                = isTask or false,
                    isBounty              = isBounty or false,
                    objectives            = objectives or {},
                    progress              = pct,
                    fulfilled             = fulfilled,
                    required              = required,
                    questLogIndex         = i,
                    campaignID            = info.campaignID,
                    questDescription      = questDescription,
                    hasQuestItem          = false, -- populated below
                    questItemLink         = nil,
                    questItemTexture      = nil,
                    isGroupFinderEligible = IsGroupFinderEligible(questID, info),
                })
            end
        end
    end

    -- Secondary pass: discover active world / task quests in the current
    -- zone that may be missing from the quest-log iteration above.
    -- This catches event-zone world quests with unusual quest flags
    -- (e.g. prepatch / timewalking event quests).
    local currentMapID = C_Map.GetBestMapForUnit("player")
    if currentMapID and C_TaskQuest and C_TaskQuest.GetQuestsForPlayerByMapID then
        local seenQuestIDs = {}
        for _, q in ipairs(quests) do
            seenQuestIDs[q.questID] = true
        end

        local taskQuests = C_TaskQuest.GetQuestsForPlayerByMapID(currentMapID)
        if taskQuests then
            for _, tq in ipairs(taskQuests) do
                local tqID = tq.questId
                if tqID and not seenQuestIDs[tqID] and tq.inProgress then
                    local objectives = C_QuestLog.GetQuestObjectives(tqID)
                    local questType = "worldquest"

                    -- Refine type classification
                    local isWQ = C_QuestLog.IsWorldQuest and C_QuestLog.IsWorldQuest(tqID)
                    if isWQ then
                        local tagInfo = C_QuestLog.GetQuestTagInfo(tqID)
                        if tagInfo and (tagInfo.tagID == 41 or tagInfo.tagID == 255) then
                            questType = "pvpworldquest"
                        end
                    end

                    -- Try to get quest title from task quest API, then quest log
                    local title = "World Quest"
                    if C_TaskQuest.GetQuestInfoByQuestID then
                        title = C_TaskQuest.GetQuestInfoByQuestID(tqID) or title
                    end
                    if C_QuestLog.GetTitleForQuestID then
                        title = C_QuestLog.GetTitleForQuestID(tqID) or title
                    end

                    local pct, fulfilled, required = self:CalcProgress(objectives)
                    local isComplete = C_QuestLog.IsComplete(tqID) and true or false
                    local logIndex = C_QuestLog.GetLogIndexForQuestID
                        and C_QuestLog.GetLogIndexForQuestID(tqID) or 0

                    table.insert(quests, {
                        questID               = tqID,
                        title                 = title,
                        level                 = 0,
                        difficultyLevel       = 0,
                        questType             = questType,
                        frequency             = 0,
                        isComplete            = isComplete,
                        isSuperTracked        = C_SuperTrack.GetSuperTrackedQuestID() == tqID,
                        isTask                = true,
                        isBounty              = false,
                        objectives            = objectives or {},
                        progress              = pct,
                        fulfilled             = fulfilled,
                        required              = required,
                        questLogIndex         = logIndex,
                        campaignID            = nil,
                        questDescription      = nil,
                        hasQuestItem          = false,
                        questItemLink         = nil,
                        questItemTexture      = nil,
                        isGroupFinderEligible = false,
                    })
                    seenQuestIDs[tqID] = true
                end
            end
        end
    end

    return quests
end

----------------------------------------------------------------------
-- Enrich quests with special-item info (post-pass so that
-- GetQuestLogSpecialItemInfo is called outside the tight loop that
-- also touches SetSelectedQuest).
----------------------------------------------------------------------
function TTQ:EnrichQuestItems(quests)
    if not GetQuestLogSpecialItemInfo then return end
    for _, quest in ipairs(quests) do
        local link, tex = GetQuestLogSpecialItemInfo(quest.questLogIndex)
        if link and tex then
            quest.hasQuestItem     = true
            quest.questItemLink    = link
            quest.questItemTexture = tex
            -- Extract numeric item ID from the link for cooldown lookups
            local itemID           = link:match("item:(%d+)")
            quest.questItemID      = itemID and tonumber(itemID) or nil
        end
    end
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

    local zoneQuestIDs = {}

    -- Regular quests associated with this map
    local questsOnMap = C_QuestLog.GetQuestsOnMap(mapID)
    if questsOnMap then
        for _, quest in ipairs(questsOnMap) do
            zoneQuestIDs[quest.questID] = true
        end
    end

    -- Task quests (world quests / bonus objectives) on this map —
    -- ensures event-zone and prepatch world quests are included in
    -- zone filtering and zone-group headers.
    if C_TaskQuest and C_TaskQuest.GetQuestsForPlayerByMapID then
        local taskQuests = C_TaskQuest.GetQuestsForPlayerByMapID(mapID)
        if taskQuests then
            for _, tq in ipairs(taskQuests) do
                if tq.questId then
                    zoneQuestIDs[tq.questId] = true
                end
            end
        end
    end

    return zoneQuestIDs
end
