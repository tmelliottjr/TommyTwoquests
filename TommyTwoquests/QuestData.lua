----------------------------------------------------------------------
-- TommyTwoquests -- QuestData.lua
-- Quest log data layer: wraps C_QuestLog APIs into structured data
----------------------------------------------------------------------
local AddonName, TTQ                               = ...
local table, ipairs                                = table, ipairs
local C_QuestLog, C_Map, C_SuperTrack, C_TaskQuest = C_QuestLog, C_Map, C_SuperTrack, C_TaskQuest
local C_Timer                                      = C_Timer

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
        -- Intentionally avoid SetSelectedQuest/GetQuestLogQuestText here.
        -- Mutating quest selection taints Blizzard quest/map paths.
        descCache[questID] = false
    end)
end

----------------------------------------------------------------------
-- Tag ID -> quest classification
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

local function IsValidQuestID(questID)
    return type(questID) == "number" and questID > 0
end

local function IsActivelyWatchedQuest(questID)
    if C_QuestLog.IsQuestWatched then
        return C_QuestLog.IsQuestWatched(questID) and true or false
    end

    if C_QuestLog.GetQuestWatchType then
        local watchType = C_QuestLog.GetQuestWatchType(questID)
        if watchType == nil then
            return false
        end
        return watchType ~= 0
    end

    return false
end


----------------------------------------------------------------------
-- Determine if a quest is eligible for the Group Finder shortcut.
-- Relies purely on WoW API signals -- no hardcoded quest lists.
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
-- Task-quest eligibility for map/task sourced entries.
-- Allows real world/event area tasks that may not have a quest-log row,
-- while filtering out anonymous placeholder task records.
----------------------------------------------------------------------
local function IsEligibleTaskQuest(questID, inProgress)
    if not IsValidQuestID(questID) or not inProgress then
        return false
    end

    -- Always allow true world quests.
    if C_QuestLog.IsWorldQuest and C_QuestLog.IsWorldQuest(questID) then
        return true
    end

    -- Allow quests with a real quest-log entry.
    if C_QuestLog.GetLogIndexForQuestID then
        local logIndex = C_QuestLog.GetLogIndexForQuestID(questID)
        if logIndex and logIndex > 0 then
            return true
        end
    end

    -- Allow tagged/public/event-style tasks that expose quest tag metadata.
    if C_QuestLog.GetQuestTagInfo then
        local tagInfo = C_QuestLog.GetQuestTagInfo(questID)
        if tagInfo and (tagInfo.worldQuestType or tagInfo.tagID) then
            return true
        end
    end

    return false
end

----------------------------------------------------------------------
-- Build the complete quest list from the quest log
----------------------------------------------------------------------
function TTQ:GetTrackedQuests()
    local quests = {}
    local watchedQuestIDs = {}
    local addedQuestIDs = {}

    local function TryAddQuest(questID, logIndex, source)
        if not IsValidQuestID(questID) then return end
        if addedQuestIDs[questID] then return end
        if not logIndex or logIndex <= 0 then return end

        local info = C_QuestLog.GetInfo(logIndex)
        if not info or info.isHeader then return end

        local isTracked = watchedQuestIDs[questID] and true or false
        local isSuperTracked = C_SuperTrack.GetSuperTrackedQuestID() == questID
        local isTask = info.isTask and true or false
        local isBounty = info.isBounty and true or false
        local isWorldQuest = C_QuestLog.IsWorldQuest and C_QuestLog.IsWorldQuest(questID) and true or false
        local isCompleteBounty = isBounty and C_QuestLog.IsComplete(questID) and true or false
        local isExplicitTaskType = isWorldQuest or isCompleteBounty

        -- Authoritative inclusion policy:
        -- 1) tracked/supertracked quests from the watch list,
        -- 2) explicit world/bounty quests (even if not watched).
        if not (isTracked or isSuperTracked or isExplicitTaskType) then
            return
        end

        -- For normal quest entries, require this to be a real on-quest log item.
        if not isExplicitTaskType then
            if info.isHidden then return end
            if isTask then return end
            if not (C_QuestLog.IsOnQuest and C_QuestLog.IsOnQuest(questID)) then return end
        end

        local objectives = C_QuestLog.GetQuestObjectives(questID)
        local questType = ClassifyQuest(questID, info)
        local pct, fulfilled, required = self:CalcProgress(objectives)
        local isComplete = C_QuestLog.IsComplete(questID) and true or false
        local isAutoComplete = false
        if info.isAutoComplete ~= nil then
            isAutoComplete = info.isAutoComplete and true or false
        end
        local level = info.level or 0
        local difficultyLevel = info.difficultyLevel or 0

        local questDescription = nil
        if (not objectives or #objectives == 0) and not isComplete then
            local cached = descCache[questID]
            if cached then
                questDescription = cached
            elseif cached == nil then
                FetchDescriptionAsync(questID)
            end
        end

        table.insert(quests, {
            questID               = questID,
            title                 = info.title or "Unknown Quest",
            level                 = level,
            difficultyLevel       = difficultyLevel,
            questType             = questType,
            frequency             = info.frequency or 0,
            isComplete            = isComplete,
            isAutoComplete        = isAutoComplete,
            isSuperTracked        = isSuperTracked,
            isTask                = isTask,
            isBounty              = isBounty,
            objectives            = objectives or {},
            progress              = pct,
            fulfilled             = fulfilled,
            required              = required,
            questLogIndex         = logIndex,
            campaignID            = info.campaignID,
            questDescription      = questDescription,
            hasQuestItem          = false,
            questItemLink         = nil,
            questItemTexture      = nil,
            isGroupFinderEligible = IsGroupFinderEligible(questID, info),
            source                = source or "unknown",
        })

        addedQuestIDs[questID] = true
    end

    if C_QuestLog.GetNumQuestWatches and C_QuestLog.GetQuestIDForQuestWatchIndex then
        local numWatches = C_QuestLog.GetNumQuestWatches()
        for watchIndex = 1, numWatches do
            local watchedQuestID = C_QuestLog.GetQuestIDForQuestWatchIndex(watchIndex)
            if type(watchedQuestID) == "number" and watchedQuestID > 0 then
                watchedQuestIDs[watchedQuestID] = true
            end
        end
    end

    -- Primary source: tracked watches.
    for questID in pairs(watchedQuestIDs) do
        local logIndex = C_QuestLog.GetLogIndexForQuestID and C_QuestLog.GetLogIndexForQuestID(questID)
        TryAddQuest(questID, logIndex, "watch")
    end

    -- Always include super-tracked quest when available.
    local superTrackedQuestID = C_SuperTrack.GetSuperTrackedQuestID()
    if type(superTrackedQuestID) == "number" and superTrackedQuestID > 0 then
        local logIndex = C_QuestLog.GetLogIndexForQuestID and C_QuestLog.GetLogIndexForQuestID(superTrackedQuestID)
        TryAddQuest(superTrackedQuestID, logIndex, "super")
    end

    -- Include explicit world/bounty quests that may not be watched.
    local numEntries = C_QuestLog.GetNumQuestLogEntries()
    for i = 1, numEntries do
        local info = C_QuestLog.GetInfo(i)
        if info and not info.isHeader and IsValidQuestID(info.questID) and not addedQuestIDs[info.questID] then
            local isWorldQuest = C_QuestLog.IsWorldQuest and C_QuestLog.IsWorldQuest(info.questID)
            local isCompleteBounty = info.isBounty and C_QuestLog.IsComplete(info.questID)
            if isWorldQuest or isCompleteBounty then
                TryAddQuest(info.questID, i, "world_or_bounty")
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
                local isWorldQuest = tqID and C_QuestLog.IsWorldQuest and C_QuestLog.IsWorldQuest(tqID)
                local logIndex = tqID and C_QuestLog.GetLogIndexForQuestID
                    and C_QuestLog.GetLogIndexForQuestID(tqID) or 0
                local hasRealLogEntry = type(logIndex) == "number" and logIndex > 0

                if tqID and not seenQuestIDs[tqID] and IsEligibleTaskQuest(tqID, tq.inProgress) then
                    local objectives = C_QuestLog.GetQuestObjectives(tqID)
                    local questType = isWorldQuest and "worldquest" or "normal"

                    -- Refine type classification
                    local isWQ = isWorldQuest
                    if isWQ then
                        local tagInfo = C_QuestLog.GetQuestTagInfo(tqID)
                        if tagInfo and (tagInfo.tagID == 41 or tagInfo.tagID == 255) then
                            questType = "pvpworldquest"
                        end
                    end

                    local info = hasRealLogEntry and C_QuestLog.GetInfo(logIndex) or nil
                    if info then
                        questType = ClassifyQuest(tqID, info)
                    end

                    -- Try to get quest title from quest log first, then task API
                    local title = (info and info.title) or "World Quest"
                    if C_QuestLog.GetTitleForQuestID then
                        title = C_QuestLog.GetTitleForQuestID(tqID) or title
                    end
                    if C_TaskQuest.GetQuestInfoByQuestID then
                        title = C_TaskQuest.GetQuestInfoByQuestID(tqID) or title
                    end

                    local pct, fulfilled, required = self:CalcProgress(objectives)
                    local isComplete = C_QuestLog.IsComplete(tqID) and true or false
                    local isAutoComplete = false
                    if info and info.isAutoComplete ~= nil then
                        isAutoComplete = info.isAutoComplete and true or false
                    end

                    table.insert(quests, {
                        questID               = tqID,
                        title                 = title,
                        level                 = 0,
                        difficultyLevel       = 0,
                        questType             = questType,
                        frequency             = 0,
                        isComplete            = isComplete,
                        isAutoComplete        = isAutoComplete,
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
                        source                = "task_map",
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

    -- Task quests (world quests / bonus objectives) on this map --
    -- ensures event-zone and prepatch world quests are included in
    -- zone filtering and zone-group headers.
    if C_TaskQuest and C_TaskQuest.GetQuestsForPlayerByMapID then
        local taskQuests = C_TaskQuest.GetQuestsForPlayerByMapID(mapID)
        if taskQuests then
            for _, tq in ipairs(taskQuests) do
                local tqID = tq.questId
                if tqID and IsEligibleTaskQuest(tqID, tq.inProgress) then
                    zoneQuestIDs[tqID] = true
                end
            end
        end
    end

    return zoneQuestIDs
end
