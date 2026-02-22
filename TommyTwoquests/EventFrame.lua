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

    local questChanged = (questEntryCount ~= lastQuestEntryCount)
    local watchesChanged = (watchSig ~= lastWatchSig)
    local superChanged = (superTrackedQuestID ~= lastSuperTrackedQuestID)

    if watchesChanged then
      Dispatch("QUEST_WATCH_LIST_CHANGED")
    end
    if superChanged then
      Dispatch("SUPER_TRACKING_CHANGED")
    end
    if questChanged or watchesChanged or superChanged then
      Dispatch("QUEST_LOG_UPDATE")
    end

    lastQuestEntryCount = questEntryCount
    lastWatchSig = watchSig
    lastSuperTrackedQuestID = superTrackedQuestID

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
