----------------------------------------------------------------------
-- TommyTwoquests -- EventFrame.lua
-- Taint-safe event dispatcher.
--
-- In some tainted UI environments, Frame:RegisterEvent itself is
-- blocked for addon code. This dispatcher avoids RegisterEvent
-- entirely and drives TTQ callbacks from a lightweight OnUpdate poll.
----------------------------------------------------------------------
local _, TTQ = ...
local C_Map, C_QuestLog, C_SuperTrack, InCombatLockdown, GetTime = C_Map, C_QuestLog, C_SuperTrack, InCombatLockdown,
    GetTime
local C_TaskQuest = C_TaskQuest

local function BuildTrackedQuestIDList()
  local questIDs = {}
  local seen = {}

  if C_QuestLog and C_QuestLog.GetNumQuestWatches and C_QuestLog.GetQuestIDForQuestWatchIndex then
    local numWatches = C_QuestLog.GetNumQuestWatches() or 0
    for i = 1, numWatches do
      local qid = C_QuestLog.GetQuestIDForQuestWatchIndex(i)
      if type(qid) == "number" and qid > 0 and not seen[qid] then
        seen[qid] = true
        questIDs[#questIDs + 1] = qid
      end
    end
  end

  local superTrackedQuestID = C_SuperTrack and C_SuperTrack.GetSuperTrackedQuestID and C_SuperTrack.GetSuperTrackedQuestID() or 0
  if type(superTrackedQuestID) == "number" and superTrackedQuestID > 0 and not seen[superTrackedQuestID] then
    seen[superTrackedQuestID] = true
    questIDs[#questIDs + 1] = superTrackedQuestID
  end

  if C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetInfo then
    local numEntries = C_QuestLog.GetNumQuestLogEntries() or 0
    for i = 1, numEntries do
      local info = C_QuestLog.GetInfo(i)
      if info and not info.isHeader and type(info.questID) == "number" and info.questID > 0 then
        local isWorldQuest = C_QuestLog.IsWorldQuest and C_QuestLog.IsWorldQuest(info.questID)
        local isCompleteBounty = info.isBounty and C_QuestLog.IsComplete and C_QuestLog.IsComplete(info.questID)
        if (isWorldQuest or isCompleteBounty or info.isTask) and not seen[info.questID] then
          seen[info.questID] = true
          questIDs[#questIDs + 1] = info.questID
        end
      end
    end
  end

  local mapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player") or nil
  if mapID and C_TaskQuest and C_TaskQuest.GetQuestsForPlayerByMapID then
    local taskQuests = C_TaskQuest.GetQuestsForPlayerByMapID(mapID)
    if taskQuests then
      for _, tq in ipairs(taskQuests) do
        local qid = tq and (tq.questID or (rawget(tq, "questId")))
        if type(qid) == "number" and qid > 0 and tq.inProgress and not seen[qid] then
          seen[qid] = true
          questIDs[#questIDs + 1] = qid
        end
      end
    end
  end

  table.sort(questIDs)
  return questIDs
end

local function BuildObjectiveProgressSignature()
  if not C_QuestLog or not C_QuestLog.GetQuestObjectives then
    return ""
  end

  local signature = ""
  local trackedQuestIDs = BuildTrackedQuestIDList()
  for _, questID in ipairs(trackedQuestIDs) do
    local isComplete = C_QuestLog.IsComplete and C_QuestLog.IsComplete(questID) and 1 or 0
    signature = signature .. "|" .. questID .. ":" .. isComplete

    local objectives = C_QuestLog.GetQuestObjectives(questID)
    if objectives and #objectives > 0 then
      for i = 1, #objectives do
        local obj = objectives[i]
        if obj then
          local finished = obj.finished and 1 or 0
          local fulfilled = obj.numFulfilled or 0
          local required = obj.numRequired or 0
          signature = signature .. ";" .. i .. "," .. finished .. "," .. fulfilled .. "," .. required
        end
      end
    else
      signature = signature .. ";none"
    end
  end

  return signature
end

do
  local eventCallbacks = {}
  local frame = CreateFrame("Frame")
  local elapsedSinceTick = 0
  local elapsedSinceAddonTick = 0
  local elapsedSinceDeathTick = 0

  local POLL_INTERVAL = 0.25
  local ADDON_TICK_INTERVAL = 1.0
  local DEATH_TICK_INTERVAL = 1.0

  local wasInCombat = InCombatLockdown and InCombatLockdown() or false
  local lastMapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player") or nil
  local sentInitialWorld = false
  local wasMythicPlusActive = false
  local lastQuestEntryCount = -1
  local lastWatchSig = ""
  local lastSuperTrackedQuestID = -1
  local lastObjectiveProgressSig = ""

  local function BuildWatchSignature()
    if not C_QuestLog or not C_QuestLog.GetNumQuestWatches or not C_QuestLog.GetQuestIDForQuestWatchIndex then
      return ""
    end

    local n = C_QuestLog.GetNumQuestWatches() or 0
    if n <= 0 then return "0:0:0" end

    local sum = 0
    local weighted = 0
    for i = 1, n do
      local qid = C_QuestLog.GetQuestIDForQuestWatchIndex(i)
      if type(qid) == "number" and qid > 0 then
        sum = sum + qid
        weighted = weighted + (qid * i)
      end
    end
    return n .. ":" .. sum .. ":" .. weighted
  end

  local function Dispatch(event, ...)
    local cbs = eventCallbacks[event]
    if not cbs then return end
    for i = 1, #cbs do
      cbs[i](event, ...)
    end
  end

  function TTQ:_DispatchQueuedEvent(event, ...)
    Dispatch(event, ...)
  end

  frame:SetScript("OnUpdate", function(_, elapsed)
    elapsedSinceTick = elapsedSinceTick + elapsed
    elapsedSinceAddonTick = elapsedSinceAddonTick + elapsed
    elapsedSinceDeathTick = elapsedSinceDeathTick + elapsed

    if elapsedSinceTick < POLL_INTERVAL then return end
    elapsedSinceTick = 0

    if not sentInitialWorld then
      sentInitialWorld = true
      Dispatch("PLAYER_ENTERING_WORLD")
      Dispatch("ZONE_CHANGED_NEW_AREA")
      Dispatch("ZONE_CHANGED")
    end

    -- Quest/watch state-change driven refresh (instead of unconditional spam)
    local questEntryCount = C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetNumQuestLogEntries() or 0
    local watchSig = BuildWatchSignature()
    local superTrackedQuestID = C_SuperTrack and C_SuperTrack.GetSuperTrackedQuestID and
    C_SuperTrack.GetSuperTrackedQuestID() or 0
    local objectiveProgressSig = BuildObjectiveProgressSignature()

    local questChanged = (questEntryCount ~= lastQuestEntryCount)
    local watchesChanged = (watchSig ~= lastWatchSig)
    local superChanged = (superTrackedQuestID ~= lastSuperTrackedQuestID)
    local objectivesChanged = (objectiveProgressSig ~= lastObjectiveProgressSig)

    if watchesChanged then
      Dispatch("QUEST_WATCH_LIST_CHANGED")
    end
    if superChanged then
      Dispatch("SUPER_TRACKING_CHANGED")
    end
    if questChanged or watchesChanged or superChanged or objectivesChanged then
      Dispatch("QUEST_LOG_UPDATE")
    end

    lastQuestEntryCount = questEntryCount
    lastWatchSig = watchSig
    lastSuperTrackedQuestID = superTrackedQuestID
    lastObjectiveProgressSig = objectiveProgressSig

    -- Combat transition emulation
    local inCombat = InCombatLockdown and InCombatLockdown() or false
    if inCombat ~= wasInCombat then
      wasInCombat = inCombat
      if inCombat then
        Dispatch("PLAYER_REGEN_DISABLED")
      else
        Dispatch("PLAYER_REGEN_ENABLED")
      end
    end

    -- Zone transition emulation
    local mapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player") or nil
    if mapID and mapID ~= lastMapID then
      lastMapID = mapID
      Dispatch("ZONE_CHANGED_NEW_AREA")
      Dispatch("ZONE_CHANGED")
      Dispatch("PLAYER_ENTERING_WORLD")
    end

    -- Mythic+ state transitions / periodic sync
    if TTQ.IsMythicPlusActive then
      local isActive = TTQ:IsMythicPlusActive() and true or false
      if isActive and not wasMythicPlusActive then
        wasMythicPlusActive = true
        Dispatch("WORLD_STATE_TIMER_START")
        Dispatch("CHALLENGE_MODE_START")
      elseif not isActive and wasMythicPlusActive then
        wasMythicPlusActive = false
        Dispatch("WORLD_STATE_TIMER_STOP")
        Dispatch("CHALLENGE_MODE_RESET")
      end

      if isActive and elapsedSinceDeathTick >= DEATH_TICK_INTERVAL then
        elapsedSinceDeathTick = 0
        Dispatch("CHALLENGE_MODE_DEATH_COUNT_UPDATED")
      end
    end

    -- Periodic addon-load style tick for delayed Blizzard UI modules
    if elapsedSinceAddonTick >= ADDON_TICK_INTERVAL then
      elapsedSinceAddonTick = 0
      Dispatch("ADDON_LOADED", "Blizzard_ChallengesUI")
    end
  end)

  -- QueueEvent stores callbacks only.
  function TTQ:QueueEvent(event, callback)
    if not event or type(callback) ~= "function" then return end
    if eventCallbacks[event] == nil then
      eventCallbacks[event] = {}
    end
    eventCallbacks[event][#eventCallbacks[event] + 1] = callback
  end

  TTQ._eventCallbacks = eventCallbacks
end
