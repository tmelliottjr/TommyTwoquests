----------------------------------------------------------------------
-- TommyTwoquests -- MythicPlus.lua
-- Mythic+ dungeon tracker: timer, chest tiers, bosses, enemy forces
----------------------------------------------------------------------
local AddonName, TTQ                                                                  = ...
local CreateFrame, C_Timer, C_ChallengeMode, C_Scenario, C_ScenarioInfo, C_MythicPlus =
    CreateFrame, C_Timer, C_ChallengeMode, C_Scenario, C_ScenarioInfo, C_MythicPlus
local GetWorldElapsedTime, GetWorldElapsedTimerInfo                                   =
    GetWorldElapsedTime, GetWorldElapsedTimerInfo
local math, string, table, ipairs, pairs, pcall, select, GetTime, wipe                =
    math, string, table, ipairs, pairs, pcall, select, GetTime, wipe
local CombatLogGetCurrentEventInfo                                                    = CombatLogGetCurrentEventInfo
local GetPlayerInfoByGUID                                                             = GetPlayerInfoByGUID
local UnitNameFromGUID                                                                = UnitNameFromGUID
local UnitClassFromGUID                                                               = UnitClassFromGUID
local UnitClass, UnitGUID, RAID_CLASS_COLORS                                          = UnitClass, UnitGUID,
    RAID_CLASS_COLORS
local UnitName, UnitExists, UnitIsDeadOrGhost                                         = UnitName, UnitExists,
    UnitIsDeadOrGhost
local UnitInParty, UnitHealth                                                         = UnitInParty, UnitHealth
local UnitIsFeignDeath                                                                = UnitIsFeignDeath
local GetInstanceInfo                                                                 = GetInstanceInfo
local GameTooltip                                                                     = GameTooltip
local bit, CursorHasItem, C_Container, C_Item                                         = bit, CursorHasItem,
    C_Container, C_Item
local COMBATLOG_OBJECT_TYPE_PLAYER                                                    = COMBATLOG_OBJECT_TYPE_PLAYER

----------------------------------------------------------------------
-- Constants
----------------------------------------------------------------------
local MP                                                                              = {}
TTQ.MythicPlus                                                                        = MP

-- Chest timer multipliers (fraction of base time to earn each tier)
-- +3 = within 60% of time, +2 = within 80%, +1 = within 100%
MP.CHEST_THRESHOLDS                                                                   = { 0.6, 0.8, 1.0 }
MP.CHEST_LABELS                                                                       = { "+3", "+2", "+1" }

-- Overtime buffer: extra seconds shown beyond the time limit on the progress bar
-- Allows the bar to visualize ~5 minutes of overtime and gives the +1 marker room
MP.OVERTIME_BUFFER                                                                    = 300 -- 5 minutes

-- Colors
MP.Colors                                                                             = {
  timerPlenty    = { r = 0.64, g = 0.21, b = 0.93 }, -- epic purple: lots of time
  timerOk        = { r = 0.00, g = 0.44, b = 0.87 }, -- rare blue: moderate
  timerLow       = { r = 0.12, g = 1.00, b = 0.00 }, -- common green: getting tight
  timerOver      = { r = 0.80, g = 0.20, b = 0.20 }, -- red: over time
  chestActive    = { r = 1.00, g = 0.82, b = 0.00 }, -- gold: still achievable
  chestLost      = { r = 0.40, g = 0.40, b = 0.40 }, -- grey: no longer possible
  chestEarned    = { r = 0.20, g = 0.80, b = 0.40 }, -- emerald: earned
  chest3         = { r = 0.64, g = 0.21, b = 0.93 }, -- epic purple: +3 tier
  chest2         = { r = 0.00, g = 0.44, b = 0.87 }, -- rare blue: +2 tier
  chest1         = { r = 0.12, g = 1.00, b = 0.00 }, -- common green: +1 tier
  bar3           = { r = 0.42, g = 0.18, b = 0.60 }, -- muted purple: +3 bar fill
  bar2           = { r = 0.08, g = 0.32, b = 0.58 }, -- muted blue: +2 bar fill
  bar1           = { r = 0.15, g = 0.55, b = 0.10 }, -- muted green: +1 bar fill
  trashBar       = { r = 0.48, g = 0.58, b = 0.82 }, -- soft blue
  trashBarFull   = { r = 0.20, g = 0.80, b = 0.40 }, -- emerald when 100%
  trashBg        = { r = 0.12, g = 0.12, b = 0.14 }, -- bar background
  deathColor     = { r = 0.90, g = 0.30, b = 0.30 }, -- red for deaths
  affixColor     = { r = 0.65, g = 0.65, b = 0.70 }, -- muted for affixes
  labelColor     = { r = 0.55, g = 0.58, b = 0.65 }, -- subtle labels
  bossComplete   = { r = 0.20, g = 0.80, b = 0.40 }, -- emerald
  bossIncomplete = { r = 0.85, g = 0.85, b = 0.85 }, -- light grey
}

-- Content indent from left edge (matches layout indent in UpdateMythicPlusDisplay)
local INDENT                                                                          = 0

-- Consolidated M+ run state (single table for easy reset)
local mpState                                                                         = {
  startTime       = nil,   -- GetTime() when the key started
  cachedTimerID   = nil,   -- cached world-elapsed-timer ID for this run
  runCompleted    = false, -- true after CHALLENGE_MODE_COMPLETED until player leaves instance
  completionTime  = nil,   -- elapsed time when the run completed
  completedOnTime = nil,   -- boolean from CompletionInfo API
  cachedData      = nil,   -- last-known M+ data snapshot for post-completion display
  deathLog        = {},    -- individual player deaths: { name, class, elapsed }
  lastDeathCount  = 0,     -- track previous count to detect new deaths
}

local function ResetMPState()
  mpState.startTime       = nil
  mpState.cachedTimerID   = nil
  mpState.runCompleted    = false
  mpState.completionTime  = nil
  mpState.completedOnTime = nil
  mpState.cachedData      = nil
  wipe(mpState.deathLog)
  mpState.lastDeathCount = 0
end

-- Returns the per-death time penalty (in seconds) for a given key level.
-- Keys at level 10 and above incur a 15-second penalty; lower keys incur 5s.
local function GetDeathPenaltyPer(keystoneLevel)
  if keystoneLevel and keystoneLevel >= 10 then
    return 15
  end
  return 5
end

----------------------------------------------------------------------
-- Detection: is the player in an active Mythic+ run?
----------------------------------------------------------------------
function TTQ:IsMythicPlusActive()
  -- Still show M+ display after completion until player leaves the instance
  if mpState.runCompleted then return true end
  -- Use GetInstanceInfo difficulty check (more reliable than IsChallengeModeActive
  -- which returns false after completion)
  local _, instanceType, difficultyID = GetInstanceInfo()
  if difficultyID == 8 and instanceType == "party" then return true end
  -- Fallback to API check
  if C_ChallengeMode and C_ChallengeMode.IsChallengeModeActive
      and C_ChallengeMode.IsChallengeModeActive() then
    return true
  end
  return false
end

----------------------------------------------------------------------
-- Gather all Mythic+ data into a structured table
----------------------------------------------------------------------
function TTQ:GetMythicPlusData()
  if not self:IsMythicPlusActive() then return nil end

  local data = {
    mapID           = 0,
    dungeonName     = "",
    keystoneLevel   = 0,
    affixes         = {},
    timeLimit       = 0,     -- base time limit in seconds
    elapsed         = 0,     -- seconds elapsed
    remaining       = 0,     -- seconds remaining (can be negative)
    isOverTime      = false,
    runCompleted    = false, -- true when CHALLENGE_MODE_COMPLETED fired
    completedOnTime = nil,   -- boolean from CompletionInfo API
    completionChest = 0,     -- 1/2/3 chest tier earned (0 if over time)
    chestTimers     = {},    -- { {label, limit, remaining, active} ... }
    deaths          = 0,
    deathPenalty    = 0,     -- seconds lost to deaths
    bosses          = {},    -- { {name, completed} ... }
    bossesKilled    = 0,
    bossesTotal     = 0,
    enemyForces     = 0, -- current count/progress
    enemyTotal      = 0, -- total needed
    enemyPct        = 0, -- 0-100
    enemyComplete   = false,
  }

  -- Map / dungeon info
  local mapID = C_ChallengeMode.GetActiveChallengeMapID()
  if mapID then
    data.mapID = mapID
    local name, _, timeLimit = C_ChallengeMode.GetMapUIInfo(mapID)
    data.dungeonName = name or "Mythic+"
    data.timeLimit = timeLimit or 0
  elseif mpState.cachedData then
    -- API returns nil after completion -- use cached values
    data.mapID = mpState.cachedData.mapID
    data.dungeonName = mpState.cachedData.dungeonName
    data.timeLimit = mpState.cachedData.timeLimit
  end

  -- Keystone level and affixes
  if C_ChallengeMode.GetActiveKeystoneInfo then
    local level, affixIDs = C_ChallengeMode.GetActiveKeystoneInfo()
    data.keystoneLevel = level or 0
    local seenAffixes = {}
    if affixIDs then
      for _, affixID in ipairs(affixIDs) do
        if not seenAffixes[affixID] then
          seenAffixes[affixID] = true
          local affixName, affixDesc, affixIcon = C_ChallengeMode.GetAffixInfo(affixID)
          if affixName then
            data.affixes[#data.affixes + 1] = {
              id = affixID,
              name = affixName,
              description = affixDesc or "",
              icon = affixIcon,
            }
          end
        end
      end
    end
    -- NOTE: GetActiveKeystoneInfo already returns only the affixes relevant
    -- to the current key level. Do NOT supplement with
    -- C_MythicPlus.GetCurrentAffixes() which returns ALL weekly affixes
    -- regardless of key level (e.g. showing +14 affixes on a +7 key).
  end

  -- Fallback: if keystone/affix APIs returned nothing (e.g. after completion),
  -- use the last cached values so the display doesn't go blank.
  if (data.keystoneLevel == 0 or #data.affixes == 0) and mpState.cachedData then
    if data.keystoneLevel == 0 then data.keystoneLevel = mpState.cachedData.keystoneLevel end
    if #data.affixes == 0 then data.affixes = mpState.cachedData.affixes end
  end

  -- Carry completion flags into data
  data.runCompleted = mpState.runCompleted
  data.completedOnTime = mpState.completedOnTime

  -- Timer: if run is completed, use frozen completion time
  if mpState.runCompleted and mpState.completionTime then
    data.elapsed = mpState.completionTime
  else
    local timerFound = false
    if GetWorldElapsedTime then
      local ok, _timerID, elapsed = pcall(GetWorldElapsedTime, 1)
      elapsed = tonumber(elapsed)
      if ok and elapsed and elapsed > 0 then
        data.elapsed = elapsed
        timerFound = true
      end
    end

    -- Strategy 2: Manual fallback using captured start time
    if not timerFound and mpState.startTime then
      data.elapsed = GetTime() - mpState.startTime
      timerFound = true
    end

    -- If Strategy 1 found a time, back-calculate mpState.startTime so it survives
    -- for the manual fallback (important after /reload when mpState.startTime is nil)
    if timerFound and data.elapsed > 0 and not mpState.startTime then
      mpState.startTime = GetTime() - data.elapsed
    end

    -- If no timer source is available yet (countdown phase), show 0
    if not timerFound then
      data.elapsed = 0
    end
  end -- close the else from "if mpState.runCompleted"

  data.remaining = data.timeLimit - data.elapsed
  -- Use the authoritative completedOnTime flag when available;
  -- fall back to elapsed vs timeLimit comparison otherwise.
  if mpState.runCompleted and mpState.completedOnTime ~= nil then
    data.isOverTime = not mpState.completedOnTime
  else
    data.isOverTime = data.remaining < 0
  end

  -- Determine which chest tier was earned on completion
  if mpState.runCompleted and not data.isOverTime then
    for i = 1, #MP.CHEST_THRESHOLDS do
      local limit = data.timeLimit * MP.CHEST_THRESHOLDS[i]
      if data.elapsed <= limit then
        data.completionChest = 3 - i + 1 -- +3, +2, +1
        break
      end
    end
    if data.completionChest == 0 then data.completionChest = 1 end
  end

  -- Chest tier timers
  for i, pct in ipairs(MP.CHEST_THRESHOLDS) do
    local limit = data.timeLimit * pct
    local rem = limit - data.elapsed
    data.chestTimers[i] = {
      label = MP.CHEST_LABELS[i],
      limit = limit,
      remaining = rem,
      active = rem > 0,
    }
  end

  -- Deaths
  if C_ChallengeMode.GetDeathCount then
    local numDeaths, timePenalty = C_ChallengeMode.GetDeathCount()
    data.deaths = numDeaths or 0
    data.deathPenalty = timePenalty or 0
  end

  -- Boss / criteria info from scenario
  if C_Scenario and C_Scenario.GetStepInfo then
    local _, _, numCriteria = C_Scenario.GetStepInfo()
    numCriteria = numCriteria or 0

    for i = 1, numCriteria do
      local criteriaInfo
      if C_ScenarioInfo and C_ScenarioInfo.GetCriteriaInfo then
        criteriaInfo = C_ScenarioInfo.GetCriteriaInfo(i)
      end

      local legacyDesc, _, legacyCompleted, legacyQty, legacyTotalQty
      if C_Scenario.GetCriteriaInfo then
        legacyDesc, _, legacyCompleted, legacyQty, legacyTotalQty = C_Scenario.GetCriteriaInfo(i)
      end

      if criteriaInfo or legacyDesc then
        local desc = ""
        local completed = false
        local qty = 0
        local totalQty = 0
        local isWeightedProgress = false
        local isForcesCriteria = false

        if criteriaInfo then
          desc = criteriaInfo.description
              or criteriaInfo.quantityString
              or ""
          completed = criteriaInfo.completed or false
          qty = criteriaInfo.quantity or 0
          totalQty = criteriaInfo.totalQuantity or 0
          isWeightedProgress = criteriaInfo.isWeightedProgress
          isForcesCriteria = criteriaInfo.isForcesCriteria
        end

        if (not desc or desc == "") and legacyDesc and legacyDesc ~= "" then
          desc = legacyDesc
        end
        if not completed and legacyCompleted ~= nil then
          completed = legacyCompleted
        end
        if qty == 0 and legacyQty and legacyQty > 0 then
          qty = legacyQty
        end
        if totalQty == 0 and legacyTotalQty and legacyTotalQty > 0 then
          totalQty = legacyTotalQty
        end

        -- Enemy forces detection:
        -- 1. isWeightedProgress (primary flag for enemy forces in M+)
        -- 2. isForcesCriteria (newer API flag)
        -- 3. Fallback: description contains "Enemy Forces" or "forces"
        local isEnemyForces = isWeightedProgress
            or isForcesCriteria
            or (desc and desc:lower():find("enemy forces"))
            or (desc and desc:lower():find("forces"))

        if isEnemyForces then
          -- Parse quantityString for the actual count (more reliable than quantity)
          local currentCount = qty
          if criteriaInfo.quantityString then
            local parsed = tonumber(criteriaInfo.quantityString:match("%d+"))
            if parsed then currentCount = parsed end
          end
          data.enemyForces = currentCount
          data.enemyTotal = totalQty
          if totalQty > 0 then
            data.enemyPct = math.min((currentCount / totalQty) * 100, 100)
          elseif currentCount > 0 and currentCount <= 100 then
            -- currentCount might already be a percentage
            data.enemyPct = currentCount
            data.enemyTotal = 100
          else
            data.enemyPct = 0
          end
          data.enemyComplete = completed or (totalQty > 0 and currentCount >= totalQty)
        else
          -- Boss encounter
          data.bosses[#data.bosses + 1] = {
            name = desc,
            completed = completed,
          }
          if completed then
            data.bossesKilled = data.bossesKilled + 1
          end
        end
      end
    end

    data.bossesTotal = #data.bosses
  end

  -- Fallback: if scenario APIs returned no boss/forces data (e.g. after
  -- completion), restore from the last cached snapshot so the display
  -- doesn't go blank.
  if mpState.cachedData and #data.bosses == 0 and data.enemyTotal == 0 then
    data.bosses = mpState.cachedData.bosses
    data.bossesKilled = mpState.cachedData.bossesKilled
    data.bossesTotal = mpState.cachedData.bossesTotal
    data.enemyForces = mpState.cachedData.enemyForces
    data.enemyTotal = mpState.cachedData.enemyTotal
    data.enemyPct = mpState.cachedData.enemyPct
    data.enemyComplete = mpState.cachedData.enemyComplete
    -- On completion, mark all bosses as completed and forces at 100%
    if mpState.runCompleted then
      for _, boss in ipairs(data.bosses) do
        boss.completed = true
      end
      data.bossesKilled = data.bossesTotal
      data.enemyComplete = true
      data.enemyPct = 100
      if data.enemyTotal > 0 then
        data.enemyForces = data.enemyTotal
      end
    end
  end

  -- Cache this data snapshot for use after completion (only when we
  -- have meaningful content -- skip caching empty/fallback-only tables).
  if data.dungeonName ~= "" and (data.bossesTotal > 0 or data.enemyTotal > 0) then
    mpState.cachedData = data
  end

  return data
end

----------------------------------------------------------------------
-- Format seconds into MM:SS or -MM:SS
----------------------------------------------------------------------
local function FormatTime(seconds)
  local negative = seconds < 0
  seconds = math.abs(seconds)
  local m = math.floor(seconds / 60)
  local s = math.floor(seconds % 60)
  local str = string.format("%d:%02d", m, s)
  if negative then str = "-" .. str end
  return str
end

----------------------------------------------------------------------
-- Get the timer remaining label text and color for the current state.
-- Returns (text, color) where color is an {r,g,b} table.
----------------------------------------------------------------------
local function GetTimerRemainingInfo(data)
  if data.runCompleted then
    -- Run is finished -- show result instead of countdown
    if data.isOverTime then
      return "OVER TIME", MP.Colors.timerOver
    end
    -- Completed on time -- show chest tier earned
    local chestLabel = "+" .. (data.completionChest or 1)
    return chestLabel .. " TIMED", MP.Colors.chestEarned
  end
  -- Still in progress
  if data.isOverTime then
    return "OVER TIME", MP.Colors.timerOver
  end
  return FormatTime(data.remaining) .. " left", nil -- nil = use timerColor
end

----------------------------------------------------------------------
-- Get timer color based on remaining time ratio
----------------------------------------------------------------------
local function GetTimerColor(remaining, total)
  if remaining <= 0 then
    return MP.Colors.timerOver
  end
  if not total or total <= 0 then
    return MP.Colors.timerPlenty
  end
  local ratio = remaining / total
  if ratio > 0.5 then
    return MP.Colors.timerPlenty -- epic purple: lots of time
  elseif ratio > 0.25 then
    return MP.Colors.timerOk     -- rare blue: moderate
  elseif ratio > 0.1 then
    return MP.Colors.timerLow    -- common green: getting tight
  else
    return MP.Colors.timerOver   -- red: almost out
  end
end

----------------------------------------------------------------------
-- Pool for M+ display elements (reused across refreshes)
----------------------------------------------------------------------
local mpFrame = nil   -- the persistent M+ display frame
local mpElements = {} -- named references to sub-elements
local mpTickerActive = false

----------------------------------------------------------------------
-- Create the M+ display frame (lazy, reused)
-- Returns the frame and its element table
----------------------------------------------------------------------
local function CreateMPDisplay(parent, width)
  if mpFrame then
    mpFrame:SetParent(parent)
    mpFrame:SetWidth(width)
    mpFrame:Show()
    return mpFrame, mpElements
  end

  local f = CreateFrame("Frame", nil, parent)
  f:SetWidth(width)
  f:SetHeight(1) -- dynamic

  local el = {}
  local fontFace = TTQ:GetResolvedFont("objective")
  local headerFont = TTQ:GetResolvedFont("header")
  local headerSize = TTQ:GetSetting("headerFontSize")
  local objSize = TTQ:GetSetting("objectiveFontSize")
  local nameSize = TTQ:GetSetting("questNameFontSize")
  local headerOutline = TTQ:GetSetting("headerFontOutline")
  local objOutline = TTQ:GetSetting("objectiveFontOutline")

  ----------------------------------------------------------------
  -- 1. Header row: Dungeon Name + Key Level
  ----------------------------------------------------------------
  local headerRow = CreateFrame("Frame", nil, f)
  headerRow:SetHeight(22)
  headerRow:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
  headerRow:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
  el.headerRow = headerRow

  local headerIcon = headerRow:CreateTexture(nil, "ARTWORK")
  headerIcon:SetSize(14, 14)
  headerIcon:SetPoint("LEFT", headerRow, "LEFT", 0, 0)
  pcall(headerIcon.SetAtlas, headerIcon, "ChallengeMode-pointed-pointed", false)
  if not headerIcon:GetAtlas() or headerIcon:GetAtlas() == "" then
    pcall(headerIcon.SetAtlas, headerIcon, "Dungeon", false)
  end
  el.headerIcon = headerIcon

  local headerText = TTQ:CreateText(headerRow, headerSize, TTQ:GetSetting("headerColor"), "LEFT")
  headerText:SetPoint("LEFT", headerIcon, "RIGHT", 5, 0)
  headerText:SetPoint("RIGHT", headerRow, "RIGHT", -30, 0)
  headerText:SetWordWrap(false)
  headerText:SetMaxLines(1)
  el.headerText = headerText

  -- Key level badge
  local keyBadge = TTQ:CreateText(headerRow, headerSize, { r = 1, g = 0.82, b = 0 }, "RIGHT")
  keyBadge:SetPoint("RIGHT", headerRow, "RIGHT", 0, 0)
  el.keyBadge = keyBadge

  -- Separator under header
  local sep = headerRow:CreateTexture(nil, "ARTWORK")
  sep:SetHeight(1)
  sep:SetPoint("BOTTOMLEFT", headerRow, "BOTTOMLEFT", 0, 0)
  sep:SetPoint("BOTTOMRIGHT", headerRow, "BOTTOMRIGHT", 0, 0)
  sep:SetColorTexture(1, 1, 1, 0.08)
  el.headerSep = sep

  ----------------------------------------------------------------
  -- 2. Timer row: big prominent timer
  ----------------------------------------------------------------
  local timerRow = CreateFrame("Frame", nil, f)
  timerRow:SetHeight(24)
  el.timerRow = timerRow

  -- Timer icon (small clock)
  local timerIcon = timerRow:CreateTexture(nil, "ARTWORK")
  timerIcon:SetSize(12, 12)
  timerIcon:SetPoint("LEFT", timerRow, "LEFT", 0, 0)
  timerIcon:SetTexture("Interface\\Icons\\Spell_Holy_BorrowedTime")
  timerIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92) -- trim icon borders
  el.timerIcon = timerIcon

  local timerText = TTQ:CreateText(timerRow, nameSize + 2, MP.Colors.timerPlenty, "LEFT")
  timerText:SetPoint("LEFT", timerIcon, "RIGHT", 5, 0)
  el.timerText = timerText

  -- Remaining label on the right
  local timerRemaining = TTQ:CreateText(timerRow, objSize, MP.Colors.labelColor, "RIGHT")
  timerRemaining:SetPoint("RIGHT", timerRow, "RIGHT", 0, 0)
  el.timerRemaining = timerRemaining

  ----------------------------------------------------------------
  -- 2b. Timer progress bar: left->right spanning full width with
  --     chest tier threshold tick marks (+3, +2, +1)
  ----------------------------------------------------------------
  local timerBarRow = CreateFrame("Frame", nil, f)
  timerBarRow:SetHeight(14)
  el.timerBarRow = timerBarRow

  -- Bar background (full width, subtle)
  local timerBarBg = timerBarRow:CreateTexture(nil, "BACKGROUND")
  timerBarBg:SetHeight(6)
  timerBarBg:SetPoint("BOTTOMLEFT", timerBarRow, "BOTTOMLEFT", INDENT, 0)
  timerBarBg:SetPoint("BOTTOMRIGHT", timerBarRow, "BOTTOMRIGHT", 0, 0)
  timerBarBg:SetColorTexture(0.12, 0.12, 0.14, 0.7)
  el.timerBarBg = timerBarBg

  -- Bar fill (grows left->right as time elapses)
  local timerBarFill = timerBarRow:CreateTexture(nil, "ARTWORK", nil, 1)
  timerBarFill:SetHeight(6)
  timerBarFill:SetPoint("BOTTOMLEFT", timerBarBg, "BOTTOMLEFT", 0, 0)
  timerBarFill:SetWidth(1)
  timerBarFill:SetColorTexture(0.40, 1.00, 0.40, 0.85)
  el.timerBarFill = timerBarFill

  -- Chest threshold tick marks (3 thin vertical lines on the bar)
  el.timerBarTicks = {}
  for i = 1, 3 do
    local tick = {}
    local tickLine = timerBarRow:CreateTexture(nil, "OVERLAY", nil, 2)
    tickLine:SetSize(1, 10)
    tickLine:SetColorTexture(1, 1, 1, 0.5)
    tick.line = tickLine

    local tickLabel = TTQ:CreateText(timerBarRow, objSize - 3, MP.Colors.chestActive, "CENTER")
    tickLabel:SetWidth(20)
    tick.label = tickLabel

    el.timerBarTicks[i] = tick
  end

  ----------------------------------------------------------------
  -- 3. Chest tier row: +3  +2  +1 indicators
  ----------------------------------------------------------------
  local chestRow = CreateFrame("Frame", nil, f)
  chestRow:SetHeight(16)
  el.chestRow = chestRow

  -- We'll create 3 chest indicators (centered text under each tick)
  el.chestIndicators = {}
  for i = 1, 3 do
    local ci = {}
    local cif = CreateFrame("Frame", nil, chestRow)
    cif:SetHeight(14)
    ci.frame = cif

    -- Combined label: hidden, only timeLabel is used now
    local label = TTQ:CreateText(cif, objSize, MP.Colors.chestActive, "CENTER")
    label:SetPoint("CENTER", cif, "CENTER", 0, 0)
    label:SetWidth(60)
    label:Hide() -- label is shown on the tick mark above the bar instead
    ci.label = label

    -- Time label centered in the frame
    local timeLabel = TTQ:CreateText(cif, objSize - 1, MP.Colors.labelColor, "CENTER")
    timeLabel:SetPoint("CENTER", cif, "CENTER", 0, 0)
    timeLabel:SetWidth(60)
    ci.timeLabel = timeLabel

    el.chestIndicators[i] = ci
  end

  ----------------------------------------------------------------
  -- 4. Deaths row (interactive -- hover for death log)
  ----------------------------------------------------------------
  local deathRow = CreateFrame("Button", nil, f)
  deathRow:SetHeight(14)
  deathRow:EnableMouse(true)
  deathRow:RegisterForClicks("AnyUp")
  el.deathRow = deathRow

  local deathIcon = deathRow:CreateTexture(nil, "ARTWORK")
  deathIcon:SetSize(10, 10)
  deathIcon:SetPoint("LEFT", deathRow, "LEFT", 0, 0)
  deathIcon:SetTexture("Interface\\RaidFrame\\UI-RaidFrame-Threat")
  el.deathIcon = deathIcon

  local deathText = TTQ:CreateText(deathRow, objSize, MP.Colors.deathColor, "LEFT")
  deathText:SetPoint("LEFT", deathIcon, "RIGHT", 4, 0)
  deathText:SetNonSpaceWrap(false)
  deathText:SetWordWrap(false)
  el.deathText = deathText

  local deathPenalty = TTQ:CreateText(deathRow, objSize - 1, MP.Colors.labelColor, "RIGHT")
  deathPenalty:SetPoint("RIGHT", deathRow, "RIGHT", 0, 0)
  el.deathPenalty = deathPenalty

  -- Invisible hitbox overlay to catch mouse (fontstrings can steal hover)
  local deathHitbox = CreateFrame("Frame", nil, deathRow)
  deathHitbox:SetAllPoints(deathRow)
  deathHitbox:SetFrameLevel(deathRow:GetFrameLevel() + 10)
  deathHitbox:EnableMouse(true)
  deathHitbox:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(deathRow, "ANCHOR_BOTTOMLEFT")
    GameTooltip:SetText("Death Log", 0.90, 0.30, 0.30)
    -- Get authoritative death count and time penalty from API
    local apiDeaths, apiTimePenalty = 0, 0
    if C_ChallengeMode and C_ChallengeMode.GetDeathCount then
      apiDeaths, apiTimePenalty = C_ChallengeMode.GetDeathCount()
      apiDeaths = apiDeaths or 0
      apiTimePenalty = apiTimePenalty or 0
    end
    local totalDeaths = math.max(apiDeaths, #mpState.deathLog)
    -- Derive per-death penalty from the API when possible,
    -- otherwise fall back to key-level-based calculation.
    local perDeathPenalty
    if apiDeaths > 0 and apiTimePenalty > 0 then
      perDeathPenalty = apiTimePenalty / apiDeaths
    else
      local curData = TTQ:GetMythicPlusData()
      perDeathPenalty = GetDeathPenaltyPer(curData and curData.keystoneLevel)
    end
    if #mpState.deathLog > 0 then
      -- Aggregate deaths per player: { name, class, count }
      local byPlayer = {} -- name -> { class, count }
      local order = {}    -- insertion-order of names
      for _, entry in ipairs(mpState.deathLog) do
        if not byPlayer[entry.name] then
          byPlayer[entry.name] = { class = entry.class, count = 0 }
          order[#order + 1] = entry.name
        end
        byPlayer[entry.name].count = byPlayer[entry.name].count + 1
        -- Upgrade class if a later entry has it
        if entry.class and not byPlayer[entry.name].class then
          byPlayer[entry.name].class = entry.class
        end
      end
      for _, pName in ipairs(order) do
        local info = byPlayer[pName]
        local cr, cg, cb = 0.85, 0.85, 0.85
        if info.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[info.class] then
          local cc = RAID_CLASS_COLORS[info.class]
          cr, cg, cb = cc.r, cc.g, cc.b
        end
        local penalty = info.count * perDeathPenalty
        local line = pName .. "  x" .. info.count .. "  |cff888888(+" .. penalty .. "s)|r"
        GameTooltip:AddLine(line, cr, cg, cb)
      end
      -- Show untracked deaths if API reports more than we identified
      local untracked = totalDeaths - #mpState.deathLog
      if untracked > 0 then
        local penalty = untracked * perDeathPenalty
        GameTooltip:AddLine("|cff666666Untracked|r  x" .. untracked .. "  |cff888888(+" .. penalty .. "s)|r", 0.4, 0.4,
          0.4)
      end
      -- Total summary -- use API penalty if available, otherwise calculate
      local totalPenalty = (apiTimePenalty > 0) and apiTimePenalty or (totalDeaths * perDeathPenalty)
      GameTooltip:AddLine(" ")
      GameTooltip:AddLine(
        totalDeaths ..
        " total " ..
        (totalDeaths == 1 and "death" or "deaths") .. "  |  +" .. FormatTime(totalPenalty) .. " penalty",
        0.6,
        0.6, 0.6)
    else
      -- Fallback: show count from API even if we missed the details
      local numDeaths = 0
      if C_ChallengeMode and C_ChallengeMode.GetDeathCount then
        numDeaths = C_ChallengeMode.GetDeathCount() or 0
      end
      if numDeaths > 0 then
        GameTooltip:AddLine(numDeaths .. " death(s) -- details not captured", 0.6, 0.6, 0.6)
      end
    end
    GameTooltip:Show()
  end)
  deathHitbox:SetScript("OnLeave", function()
    GameTooltip:Hide()
  end)
  el.deathHitbox = deathHitbox

  ----------------------------------------------------------------
  -- 5. Enemy forces bar -- taller bar with prominent percentage
  ----------------------------------------------------------------
  local trashRow = CreateFrame("Frame", nil, f)
  trashRow:SetHeight(28)
  el.trashRow = trashRow

  -- Label row: "Enemy Forces" on the left, percentage right next to it
  local trashLabel = TTQ:CreateText(trashRow, objSize, MP.Colors.labelColor, "LEFT")
  trashLabel:SetPoint("TOPLEFT", trashRow, "TOPLEFT", 0, 0)
  trashLabel:SetText("Enemy Forces")
  el.trashLabel = trashLabel

  local trashPct = TTQ:CreateText(trashRow, objSize + 2, { r = 1.0, g = 1.0, b = 1.0 }, "LEFT")
  trashPct:SetPoint("LEFT", trashLabel, "RIGHT", 6, 0)
  el.trashPct = trashPct

  -- Progress bar background
  local barBg = trashRow:CreateTexture(nil, "BACKGROUND")
  barBg:SetHeight(6)
  barBg:SetPoint("BOTTOMLEFT", trashRow, "BOTTOMLEFT", 0, 0)
  barBg:SetPoint("BOTTOMRIGHT", trashRow, "BOTTOMRIGHT", 0, 0)
  barBg:SetColorTexture(MP.Colors.trashBg.r, MP.Colors.trashBg.g, MP.Colors.trashBg.b, 0.6)
  el.barBg = barBg

  -- Progress bar fill
  local barFill = trashRow:CreateTexture(nil, "ARTWORK")
  barFill:SetHeight(6)
  barFill:SetPoint("BOTTOMLEFT", barBg, "BOTTOMLEFT", 0, 0)
  barFill:SetWidth(1)
  barFill:SetColorTexture(MP.Colors.trashBar.r, MP.Colors.trashBar.g, MP.Colors.trashBar.b, 0.9)
  el.barFill = barFill

  ----------------------------------------------------------------
  -- 6. Boss list (dynamic, created during update)
  ----------------------------------------------------------------
  el.bossItems = {}

  ----------------------------------------------------------------
  -- 7. Affixes container (individual buttons with tooltips)
  ----------------------------------------------------------------
  local affixRow = CreateFrame("Frame", nil, headerRow)
  affixRow:SetHeight(14)
  el.affixRow = affixRow

  -- Pool of per-affix buttons (created dynamically during update)
  el.affixButtons = {}

  -- Keep a single text as fallback (hidden, but used for sizing)
  local affixText = TTQ:CreateText(affixRow, objSize - 2, MP.Colors.affixColor, "LEFT")
  affixText:SetPoint("LEFT", affixRow, "LEFT", 0, 0)
  affixText:SetPoint("RIGHT", affixRow, "RIGHT", 0, 0)
  affixText:SetWordWrap(false)
  affixText:SetMaxLines(1)
  affixText:Hide()
  el.affixText = affixText

  mpFrame = f
  mpElements = el
  return f, el
end

----------------------------------------------------------------------
-- Create or reuse a boss row fontstring
----------------------------------------------------------------------
local function EnsureBossItem(el, parent, index)
  if el.bossItems[index] then
    return el.bossItems[index]
  end
  local objSize = TTQ:GetSetting("objectiveFontSize")
  local boss = {}

  local row = CreateFrame("Frame", nil, parent)
  row:SetHeight(16)
  boss.frame = row

  -- Checkmark texture (shown when completed)
  local checkmark = row:CreateTexture(nil, "ARTWORK")
  checkmark:SetSize(objSize, objSize)
  checkmark:SetPoint("LEFT", row, "LEFT", 0, 0)
  checkmark:SetTexture("Interface\\AddOns\\TommyTwoquests\\Textures\\checkmark")
  checkmark:Hide()
  boss.checkmark = checkmark

  -- Dash (shown when incomplete)
  local dash = TTQ:CreateText(row, objSize, MP.Colors.bossIncomplete, "LEFT")
  dash:SetPoint("LEFT", row, "LEFT", 0, 0)
  dash:SetWidth(10)
  dash:SetText("-")
  boss.dash = dash

  -- Boss name
  local name = TTQ:CreateText(row, objSize, MP.Colors.bossIncomplete, "LEFT")
  name:SetPoint("LEFT", dash, "RIGHT", 3, 0)
  name:SetPoint("RIGHT", row, "RIGHT", 0, 0)
  name:SetWordWrap(false)
  name:SetMaxLines(1)
  boss.name = name

  el.bossItems[index] = boss
  return boss
end

----------------------------------------------------------------------
-- Update the M+ display with current data
----------------------------------------------------------------------
function TTQ:UpdateMythicPlusDisplay(el, data, width)
  if not el or not data then return 0 end

  local headerFont, headerSize, headerOutline, headerColor = self:GetFontSettings("header")
  local questFont, nameSize = self:GetFontSettings("quest")
  local objFont, objSize, objOutline = self:GetFontSettings("objective")
  local completeColor = self:GetSetting("objectiveCompleteColor")
  local incompleteColor = self:GetSetting("objectiveIncompleteColor")

  local y = 0
  local indent = 0 -- no indent for M+ (centered feel)

  ----------------------------------------------------------------
  -- Header
  ----------------------------------------------------------------
  TTQ:SafeSetFont(el.headerText, headerFont, headerSize, headerOutline)
  el.headerText:SetTextColor(headerColor.r, headerColor.g, headerColor.b)
  el.headerText:SetText(data.dungeonName)

  TTQ:SafeSetFont(el.keyBadge, headerFont, headerSize, headerOutline)
  el.keyBadge:SetText("+" .. data.keystoneLevel)
  el.keyBadge:SetTextColor(headerColor.r, headerColor.g, headerColor.b)

  if self:GetSetting("showIcons") then
    el.headerIcon:Show()
    local iconSize = math.max(10, headerSize - 1)
    el.headerIcon:SetSize(iconSize + 4, iconSize + 4)
  else
    el.headerIcon:Hide()
  end

  el.headerRow:ClearAllPoints()
  el.headerRow:SetPoint("TOPLEFT", mpFrame, "TOPLEFT", 0, -y)
  el.headerRow:SetPoint("TOPRIGHT", mpFrame, "TOPRIGHT", 0, -y)
  y = y + 24 -- header height + gap

  ----------------------------------------------------------------
  -- Affixes (inline with header, icon-only with tooltip on hover)
  ----------------------------------------------------------------
  if #data.affixes > 0 then
    local AFFIX_ICON_SIZE = 14
    local AFFIX_SPACING = -5 -- negative for overlapping avatar-list style
    local totalAffixWidth = #data.affixes * AFFIX_ICON_SIZE + (#data.affixes - 1) * math.max(0, AFFIX_SPACING)
    -- Recalculate for overlap: each icon after the first adds (ICON_SIZE + SPACING) pixels
    if AFFIX_SPACING < 0 then
      totalAffixWidth = AFFIX_ICON_SIZE + math.max(0, #data.affixes - 1) * (AFFIX_ICON_SIZE + AFFIX_SPACING)
    end

    -- Position inline in header row, to the left of the key badge
    el.affixRow:ClearAllPoints()
    el.affixRow:SetPoint("RIGHT", el.keyBadge, "LEFT", -5, 0)
    el.affixRow:SetHeight(AFFIX_ICON_SIZE)
    el.affixRow:SetWidth(totalAffixWidth)
    el.affixRow:Show()

    for idx, aff in ipairs(data.affixes) do
      if not el.affixButtons[idx] then
        local btn = CreateFrame("Button", nil, el.affixRow)
        btn:SetSize(AFFIX_ICON_SIZE, AFFIX_ICON_SIZE)
        btn:EnableMouse(true)

        -- Icon texture (masked to circle via MaskTexture)
        local icon = btn:CreateTexture(nil, "ARTWORK", nil, 1)
        icon:SetAllPoints()
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        btn.icon = icon

        -- Apply circular mask using the proper MaskTexture API
        local mask = btn:CreateMaskTexture()
        mask:SetAllPoints(icon)
        mask:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE",
          "CLAMPTOBLACKADDITIVE")
        icon:AddMaskTexture(mask)
        btn.mask = mask

        -- Circular border ring: a slightly larger masked circle behind the icon
        local borderSize = AFFIX_ICON_SIZE + 2
        local border = btn:CreateTexture(nil, "BACKGROUND", nil, 0)
        border:SetPoint("CENTER", btn, "CENTER", 0, 0)
        border:SetSize(borderSize, borderSize)
        border:SetColorTexture(0.65, 0.58, 0.30, 0.6)
        btn.border = border

        -- Mask the border ring to a circle
        local borderMask = btn:CreateMaskTexture()
        borderMask:SetPoint("CENTER", border, "CENTER", 0, 0)
        borderMask:SetSize(borderSize, borderSize)
        borderMask:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE",
          "CLAMPTOBLACKADDITIVE")
        border:AddMaskTexture(borderMask)
        btn.borderMask = borderMask

        -- Hover glow (not needed, border highlight is enough)
        local glow = btn:CreateTexture(nil, "OVERLAY", nil, 3)
        glow:SetPoint("CENTER")
        glow:SetSize(AFFIX_ICON_SIZE + 4, AFFIX_ICON_SIZE + 4)
        glow:SetColorTexture(0, 0, 0, 0)
        glow:Hide()
        btn.glow = glow

        el.affixButtons[idx] = btn
      end

      local btn = el.affixButtons[idx]
      btn:SetSize(AFFIX_ICON_SIZE, AFFIX_ICON_SIZE)
      if btn.border then
        btn.border:SetSize(AFFIX_ICON_SIZE + 2, AFFIX_ICON_SIZE + 2)
      end
      if btn.borderMask then
        btn.borderMask:SetSize(AFFIX_ICON_SIZE + 2, AFFIX_ICON_SIZE + 2)
      end

      -- Set icon texture
      if aff.icon and btn.icon then
        btn.icon:SetTexture(aff.icon)
        btn.icon:Show()
      end

      -- Position within the header-inline affix row (overlapping avatar-list style)
      local xPos = (idx - 1) * (AFFIX_ICON_SIZE + AFFIX_SPACING)
      btn:ClearAllPoints()
      btn:SetPoint("LEFT", el.affixRow, "LEFT", xPos, 0)
      -- Stack frame levels so the first icon is on top (avatar-list effect)
      btn:SetFrameLevel(el.affixRow:GetFrameLevel() + (#data.affixes - idx + 1))
      btn:Show()

      -- Tooltip with affix name + description
      local affName = aff.name
      local affDesc = aff.description
      btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
        GameTooltip:SetText(affName, 1, 0.82, 0)
        if affDesc and affDesc ~= "" then
          GameTooltip:AddLine(affDesc, 0.85, 0.85, 0.85, true)
        end
        GameTooltip:Show()
        -- Highlight border on hover
        if self.border then
          self.border:SetColorTexture(1, 0.78, 0.15, 1)
        end
      end)
      btn:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
        if self.border then
          self.border:SetColorTexture(0.65, 0.58, 0.30, 0.6)
        end
      end)
    end

    -- Hide excess buttons
    for idx = #data.affixes + 1, 10 do
      if el.affixButtons[idx] then
        el.affixButtons[idx]:Hide()
      end
    end
    -- Hide old dot separators
    for key, v in pairs(el.affixButtons) do
      if type(key) == "string" and key:find("^dot") then
        if v.Hide then
          v:Hide()
        elseif v.SetText then
          v:SetText("")
        end
      end
    end
  else
    el.affixRow:Hide()
    if el.affixButtons then
      for _, v in pairs(el.affixButtons) do
        if v.Hide then v:Hide() end
      end
    end
  end

  -- Adjust header text boundaries after affix positioning
  el.headerText:ClearAllPoints()
  if self:GetSetting("showIcons") and el.headerIcon:IsShown() then
    el.headerText:SetPoint("LEFT", el.headerIcon, "RIGHT", 5, 0)
  else
    el.headerText:SetPoint("LEFT", el.headerRow, "LEFT", 0, 0)
  end
  if #data.affixes > 0 then
    el.headerText:SetPoint("RIGHT", el.affixRow, "LEFT", -4, 0)
  else
    el.headerText:SetPoint("RIGHT", el.headerRow, "RIGHT", -30, 0)
  end

  ----------------------------------------------------------------
  -- Timer
  ----------------------------------------------------------------
  local timerColor = GetTimerColor(data.remaining, data.timeLimit)

  TTQ:SafeSetFont(el.timerText, questFont, nameSize + 2, objOutline)
  el.timerText:SetText(FormatTime(data.elapsed))
  el.timerText:SetTextColor(timerColor.r, timerColor.g, timerColor.b)

  TTQ:SafeSetFont(el.timerRemaining, objFont, objSize, objOutline)
  local remText, remColor = GetTimerRemainingInfo(data)
  el.timerRemaining:SetText(remText)
  local rc = remColor or timerColor
  el.timerRemaining:SetTextColor(rc.r, rc.g, rc.b)

  el.timerRow:ClearAllPoints()
  el.timerRow:SetPoint("TOPLEFT", mpFrame, "TOPLEFT", 0, -y)
  el.timerRow:SetPoint("TOPRIGHT", mpFrame, "TOPRIGHT", 0, -y)
  y = y + 28 -- extra gap so +3/+2/+1 labels don't touch the remaining text

  ----------------------------------------------------------------
  -- Timer progress bar
  ----------------------------------------------------------------
  local barTotalWidth = width - indent
  -- The bar represents timeLimit + overtime buffer, so +1 isn't at the far edge
  local barRange = data.timeLimit + MP.OVERTIME_BUFFER
  local fillRatio = barRange > 0 and math.min(data.elapsed / barRange, 1.0) or 0
  local fillWidth = math.max(1, fillRatio * barTotalWidth)

  -- Bar fill: muted rarity color matching current chest tier, red when over time
  local barColor
  if data.isOverTime then
    barColor = MP.Colors.timerOver
  elseif data.chestTimers[1] and data.elapsed <= data.chestTimers[1].limit then
    barColor = MP.Colors.bar3 -- still on pace for +3
  elseif data.chestTimers[2] and data.elapsed <= data.chestTimers[2].limit then
    barColor = MP.Colors.bar2 -- missed +3, still on pace for +2
  else
    barColor = MP.Colors.bar1 -- missed +2, running for +1
  end
  el.timerBarFill:SetWidth(fillWidth)
  el.timerBarFill:SetColorTexture(barColor.r, barColor.g, barColor.b, 0.85)

  -- Position tick marks at each chest threshold (relative to barRange)
  for i = 1, 3 do
    local tick = el.timerBarTicks[i]
    local ct = data.chestTimers[i]
    if tick and ct then
      local tickPct = barRange > 0 and (ct.limit / barRange) or 0
      local barActualWidth = el.timerBarBg:GetWidth()
      if not barActualWidth or barActualWidth <= 0 then barActualWidth = barTotalWidth end
      local tickX = tickPct * barActualWidth

      tick.line:ClearAllPoints()
      tick.line:SetPoint("BOTTOM", el.timerBarBg, "BOTTOMLEFT", tickX, -1)
      tick.line:Show()

      -- Tick color: fixed rarity color per tier (+3=purple, +2=blue, +1=green), greyed when lost
      local tierColors = { MP.Colors.chest3, MP.Colors.chest2, MP.Colors.chest1 }
      local tickColor = data.elapsed <= ct.limit and tierColors[i] or MP.Colors.chestLost
      tick.line:SetColorTexture(tickColor.r, tickColor.g, tickColor.b, 0.7)

      TTQ:SafeSetFont(tick.label, objFont, objSize - 3, objOutline)
      tick.label:SetText(ct.label)
      tick.label:SetTextColor(tickColor.r, tickColor.g, tickColor.b)
      tick.label:ClearAllPoints()
      tick.label:SetPoint("BOTTOM", tick.line, "TOP", 0, 1)
      tick.label:Show()
    end
  end

  el.timerBarRow:ClearAllPoints()
  el.timerBarRow:SetPoint("TOPLEFT", mpFrame, "TOPLEFT", 0, -y)
  el.timerBarRow:SetPoint("TOPRIGHT", mpFrame, "TOPRIGHT", 0, -y)
  el.timerBarRow:Show()
  y = y + 16

  ----------------------------------------------------------------
  -- Chest tiers -- aligned under their tick marks on the bar
  ----------------------------------------------------------------
  local barActualWidth = el.timerBarBg:GetWidth()
  if not barActualWidth or barActualWidth <= 0 then barActualWidth = barTotalWidth end
  local barRange2 = data.timeLimit + MP.OVERTIME_BUFFER
  for i = 1, 3 do
    local ci = el.chestIndicators[i]
    local ct = data.chestTimers[i]
    if ci and ct then
      -- Fixed rarity color per tier (+3=purple, +2=blue, +1=green), greyed when lost
      local tierColors = { MP.Colors.chest3, MP.Colors.chest2, MP.Colors.chest1 }
      local color = data.elapsed <= ct.limit and tierColors[i] or MP.Colors.chestLost

      TTQ:SafeSetFont(ci.label, objFont, objSize, objOutline)
      TTQ:SafeSetFont(ci.timeLabel, objFont, objSize - 1, objOutline)

      ci.label:SetText(ct.label)
      ci.label:SetTextColor(color.r, color.g, color.b)

      if ct.active then
        ci.timeLabel:SetText(FormatTime(ct.remaining))
      else
        ci.timeLabel:SetText(FormatTime(ct.limit))
      end
      ci.timeLabel:SetTextColor(color.r, color.g, color.b)

      -- Position centered under the tick mark
      local tickPct = barRange2 > 0 and (ct.limit / barRange2) or 0
      local tickX = indent + tickPct * barActualWidth

      ci.frame:ClearAllPoints()
      ci.frame:SetWidth(60) -- enough for "24:27 +1" style text
      ci.frame:SetPoint("TOP", mpFrame, "TOPLEFT", tickX, -y)
      ci.frame:Show()
    end
  end
  y = y + 24 -- extra breathing room below timeline

  ----------------------------------------------------------------
  -- Deaths (only show if > 0)
  ----------------------------------------------------------------
  if data.deaths > 0 then
    TTQ:SafeSetFont(el.deathText, objFont, objSize, objOutline)
    TTQ:SafeSetFont(el.deathPenalty, objFont, objSize - 1, objOutline)

    el.deathText:SetText(data.deaths .. (data.deaths == 1 and " Death" or " Deaths"))
    el.deathText:SetTextColor(MP.Colors.deathColor.r, MP.Colors.deathColor.g, MP.Colors.deathColor.b)

    el.deathPenalty:SetText("+" .. FormatTime(data.deathPenalty))
    el.deathPenalty:SetTextColor(MP.Colors.deathColor.r, MP.Colors.deathColor.g, MP.Colors.deathColor.b)

    el.deathRow:ClearAllPoints()
    el.deathRow:SetPoint("TOPLEFT", mpFrame, "TOPLEFT", 0, -y)
    el.deathRow:SetPoint("TOPRIGHT", mpFrame, "TOPRIGHT", 0, -y)
    el.deathRow:Show()
    y = y + 16
  else
    el.deathRow:Hide()
  end

  ----------------------------------------------------------------
  -- Enemy forces bar
  ----------------------------------------------------------------
  if data.enemyTotal > 0 then
    TTQ:SafeSetFont(el.trashLabel, objFont, objSize, objOutline)
    -- Larger, brighter font for percentage -- key information
    local pctFontSize = objSize + 2
    TTQ:SafeSetFont(el.trashPct, objFont, pctFontSize, objOutline)

    local pctStr = string.format("%.2f%%", data.enemyPct)
    el.trashPct:SetText(pctStr)

    -- Use the player's class color for the bar fill
    local barColor
    if data.enemyComplete then
      barColor = MP.Colors.trashBarFull
    else
      local _, classToken = UnitClass("player")
      if classToken and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classToken] then
        local cc = RAID_CLASS_COLORS[classToken]
        barColor = { r = cc.r, g = cc.g, b = cc.b }
      else
        barColor = MP.Colors.trashBar
      end
    end
    -- Bright white percentage text so it stands out
    if data.enemyComplete then
      el.trashPct:SetTextColor(MP.Colors.trashBarFull.r, MP.Colors.trashBarFull.g, MP.Colors.trashBarFull.b)
    else
      el.trashPct:SetTextColor(1.0, 1.0, 1.0)
    end
    el.trashLabel:SetTextColor(MP.Colors.labelColor.r, MP.Colors.labelColor.g, MP.Colors.labelColor.b)

    -- Update bar fill width
    local barWidth = width - indent
    local fillWidth = math.max(1, (data.enemyPct / 100) * barWidth)
    el.barFill:SetWidth(fillWidth)
    el.barFill:SetColorTexture(barColor.r, barColor.g, barColor.b, 0.9)

    el.trashRow:ClearAllPoints()
    el.trashRow:SetPoint("TOPLEFT", mpFrame, "TOPLEFT", 0, -y)
    el.trashRow:SetPoint("TOPRIGHT", mpFrame, "TOPRIGHT", 0, -y)
    el.trashRow:Show()
    y = y + 38 -- row height + extra spacing before bosses
  else
    el.trashRow:Hide()
  end

  ----------------------------------------------------------------
  -- Boss progress (at the bottom)
  ----------------------------------------------------------------
  for i, boss in ipairs(data.bosses) do
    local bossItem = EnsureBossItem(el, mpFrame, i)

    TTQ:SafeSetFont(bossItem.name, objFont, objSize, objOutline)
    TTQ:SafeSetFont(bossItem.dash, objFont, objSize, objOutline)

    bossItem.name:SetText(boss.name)
    if boss.completed then
      local c = completeColor
      bossItem.name:SetTextColor(c.r, c.g, c.b)
      if bossItem.checkmark then
        bossItem.checkmark:SetSize(objSize, objSize)
        bossItem.checkmark:SetVertexColor(c.r, c.g, c.b)
        bossItem.checkmark:Show()
      end
      bossItem.dash:Hide()
      bossItem.name:ClearAllPoints()
      bossItem.name:SetPoint("LEFT", bossItem.checkmark or bossItem.dash, "RIGHT", 3, 0)
      bossItem.name:SetPoint("RIGHT", bossItem.frame, "RIGHT", 0, 0)
    else
      local c = incompleteColor
      bossItem.name:SetTextColor(c.r, c.g, c.b)
      if bossItem.checkmark then
        bossItem.checkmark:Hide()
      end
      bossItem.dash:Show()
      bossItem.dash:SetText("-")
      bossItem.dash:SetTextColor(c.r, c.g, c.b)
      bossItem.name:ClearAllPoints()
      bossItem.name:SetPoint("LEFT", bossItem.dash, "RIGHT", 3, 0)
      bossItem.name:SetPoint("RIGHT", bossItem.frame, "RIGHT", 0, 0)
    end

    bossItem.frame:ClearAllPoints()
    bossItem.frame:SetPoint("TOPLEFT", mpFrame, "TOPLEFT", 0, -y)
    bossItem.frame:SetPoint("TOPRIGHT", mpFrame, "TOPRIGHT", 0, -y)
    bossItem.frame:Show()
    y = y + 16 + 1
  end
  -- Hide excess boss items
  for i = #data.bosses + 1, #el.bossItems do
    if el.bossItems[i] then
      el.bossItems[i].frame:Hide()
    end
  end

  if #data.bosses > 0 then
    y = y + 2 -- small gap after bosses
  end

  return y
end

----------------------------------------------------------------------
-- Hide the M+ display
----------------------------------------------------------------------
function TTQ:HideMythicPlusDisplay()
  if mpFrame then
    mpFrame:Hide()
  end
  mpTickerActive = false
end

----------------------------------------------------------------------
-- Render the M+ block into the tracker's content area
-- Returns the total height consumed (0 if not active)
----------------------------------------------------------------------
function TTQ:RenderMythicPlusBlock(contentParent, width, yOffset)
  if not self:IsMythicPlusActive() then
    self:HideMythicPlusDisplay()
    return 0
  end

  local data = self:GetMythicPlusData()
  if not data then
    self:HideMythicPlusDisplay()
    return 0
  end

  local frame, el = CreateMPDisplay(contentParent, width)
  frame:ClearAllPoints()
  frame:SetPoint("TOPLEFT", contentParent, "TOPLEFT", 0, -yOffset)
  frame:SetPoint("TOPRIGHT", contentParent, "TOPRIGHT", 0, -yOffset)

  local totalHeight = self:UpdateMythicPlusDisplay(el, data, width)
  frame:SetHeight(math.max(1, totalHeight))
  frame:Show()

  -- Start the live timer if not already running
  if not self._mpTimerRunning then
    self:StartMythicPlusTimer()
  end

  return totalHeight + 4 -- add spacing after the block
end

----------------------------------------------------------------------
-- Live timer: per-frame OnUpdate for smooth real-time ticking
-- Updates timer text, remaining label, progress bar fill, chest
-- tier countdowns every frame for a crisp, responsive display.
----------------------------------------------------------------------
function TTQ:StartMythicPlusTimer()
  if self._mpTimerRunning then return end
  self._mpTimerRunning = true

  -- Use the mpFrame's OnUpdate for zero-overhead per-frame ticks
  if not mpFrame then return end

  mpFrame:SetScript("OnUpdate", function(_, elapsed)
    if not TTQ:IsMythicPlusActive() then
      TTQ:StopMythicPlusTimer()
      TTQ:SafeRefreshTracker()
      return
    end

    if not mpFrame:IsShown() or not mpElements.timerText then return end

    local data = TTQ:GetMythicPlusData()
    if not data then return end

    -- Timer text
    local timerColor = GetTimerColor(data.remaining, data.timeLimit)
    mpElements.timerText:SetText(FormatTime(data.elapsed))
    mpElements.timerText:SetTextColor(timerColor.r, timerColor.g, timerColor.b)

    local remText, remColor = GetTimerRemainingInfo(data)
    mpElements.timerRemaining:SetText(remText)
    local rc = remColor or timerColor
    mpElements.timerRemaining:SetTextColor(rc.r, rc.g, rc.b)

    -- Progress bar fill: muted rarity color matching current chest tier
    if mpElements.timerBarFill and mpElements.timerBarBg then
      local barWidth = mpElements.timerBarBg:GetWidth()
      if barWidth and barWidth > 0 then
        local barRange = data.timeLimit + MP.OVERTIME_BUFFER
        local fillRatio = barRange > 0
            and math.min(data.elapsed / barRange, 1.0) or 0
        local fillW = math.max(1, fillRatio * barWidth)
        mpElements.timerBarFill:SetWidth(fillW)
        local barC
        if data.isOverTime then
          barC = MP.Colors.timerOver
        elseif data.chestTimers[1] and data.elapsed <= data.chestTimers[1].limit then
          barC = MP.Colors.bar3
        elseif data.chestTimers[2] and data.elapsed <= data.chestTimers[2].limit then
          barC = MP.Colors.bar2
        else
          barC = MP.Colors.bar1
        end
        mpElements.timerBarFill:SetColorTexture(barC.r, barC.g, barC.b, 0.85)
      end
    end

    -- Chest tier tick marks + remaining times (fixed rarity colors)
    local tierColorsLive = { MP.Colors.chest3, MP.Colors.chest2, MP.Colors.chest1 }
    for i = 1, 3 do
      local ci = mpElements.chestIndicators[i]
      local ct = data.chestTimers[i]
      if ci and ct then
        local color = data.elapsed <= ct.limit and tierColorsLive[i] or MP.Colors.chestLost
        if ct.active then
          ci.timeLabel:SetText(FormatTime(ct.remaining))
        else
          ci.timeLabel:SetText(FormatTime(ct.limit))
        end
        ci.label:SetTextColor(color.r, color.g, color.b)
        ci.timeLabel:SetTextColor(color.r, color.g, color.b)
      end

      -- Update tick mark colors
      local tick = mpElements.timerBarTicks and mpElements.timerBarTicks[i]
      if tick and ct then
        local tickColor = data.elapsed <= ct.limit and tierColorsLive[i] or MP.Colors.chestLost
        tick.line:SetColorTexture(tickColor.r, tickColor.g, tickColor.b, 0.7)
        tick.label:SetTextColor(tickColor.r, tickColor.g, tickColor.b)
      end
    end

    -- Deaths
    if data.deaths > 0 then
      mpElements.deathText:SetText(
        data.deaths .. (data.deaths == 1 and " Death" or " Deaths"))
      mpElements.deathPenalty:SetText("+" .. FormatTime(data.deathPenalty))
      mpElements.deathRow:Show()
    else
      mpElements.deathRow:Hide()
    end
  end)
end

----------------------------------------------------------------------
-- Stop the live timer
----------------------------------------------------------------------
function TTQ:StopMythicPlusTimer()
  mpTickerActive = false
  self._mpTimerRunning = false
  if mpFrame then
    mpFrame:SetScript("OnUpdate", nil)
  end
  -- Legacy ticker cleanup
  if self._mpTimerTicker then
    self._mpTimerTicker:Cancel()
    self._mpTimerTicker = nil
  end
end

----------------------------------------------------------------------
-- M+ events -- all routing through TTQ:RegisterEvent() which uses
-- the single _EventDispatcher frame created in Utils.lua (first
-- loaded file, clean execution context).  No per-file frames needed.
----------------------------------------------------------------------
do
  -- Auto-insert keystone: hook ChallengesKeystoneFrame OnShow
  -- The frame is part of a load-on-demand UI addon
  local keystoneHooked = false
  local function SlotKeystoneFromBags()
    if not C_Container or not C_ChallengeMode then return end
    for container = 0, (NUM_BAG_SLOTS or 4) do
      local slots = C_Container.GetContainerNumSlots(container)
      for slot = 1, slots do
        local itemLink = C_Container.GetContainerItemLink(container, slot)
        if itemLink and itemLink:match("|Hkeystone:") then
          C_Container.PickupContainerItem(container, slot)
          if CursorHasItem() then
            C_ChallengeMode.SlotKeystone()
          end
          return
        end
      end
    end
  end
  local function TryHookKeystoneFrame()
    if keystoneHooked then return end
    local frame = ChallengesKeystoneFrame or ChallengeKeystoneFrame
    if frame and frame.HookScript then
      frame:HookScript("OnShow", function()
        if TTQ:GetSetting("autoInsertKeystone") then
          SlotKeystoneFromBags()
        end
      end)
      keystoneHooked = true
    end
  end
  -- Try immediately in case the addon is already loaded
  TryHookKeystoneFrame()

  -- Helper: log a player death with dedup
  local function LogPlayerDeath(name, classToken, elapsed)
    if not name then return false end
    -- Deduplicate: skip if this player was already logged within 3 seconds
    for idx = #mpState.deathLog, math.max(1, #mpState.deathLog - 8), -1 do
      local prev = mpState.deathLog[idx]
      if prev and prev.name == name and math.abs(prev.elapsed - elapsed) < 3 then
        return false -- already logged
      end
    end
    mpState.deathLog[#mpState.deathLog + 1] = {
      name = name,
      class = classToken,
      elapsed = elapsed,
    }
    return true
  end

  -- M+ event handler -- dispatched by TTQ:RegisterEvent()
  local function OnMPEvent(evt, ...)
    -- Hook the keystone frame when Blizzard_ChallengesUI loads
    if evt == "ADDON_LOADED" then
      local addon = ...
      if not keystoneHooked then
        -- Try hooking on every addon load (frame name may appear late)
        TryHookKeystoneFrame()
      end
      return
    elseif evt == "WORLD_STATE_TIMER_START" then
      ResetMPState()
      mpState.startTime = GetTime()

      -- Run completed -- freeze timer, keep display
    elseif evt == "CHALLENGE_MODE_COMPLETED" then
      mpState.runCompleted = true
      -- Use the authoritative CompletionInfo API
      -- to get the precise completion time and onTime flag.
      local completionElapsed
      if C_ChallengeMode.GetChallengeCompletionInfo then
        local ok, info = pcall(C_ChallengeMode.GetChallengeCompletionInfo)
        if ok and info then
          if info.time and info.time > 0 then
            completionElapsed = info.time / 1000 -- convert ms -> seconds
          end
          if info.onTime ~= nil then
            mpState.completedOnTime = info.onTime
          end
        end
      end
      -- Fallback: try GetWorldElapsedTime if CompletionInfo didn't work
      if not completionElapsed and GetWorldElapsedTime then
        local ok2, _, elapsed = pcall(GetWorldElapsedTime, 1)
        elapsed = tonumber(elapsed)
        if ok2 and elapsed and elapsed > 0 then
          completionElapsed = elapsed
        end
      end
      mpState.completionTime = completionElapsed
      TTQ:StopMythicPlusTimer()

      -- Key reset
    elseif evt == "CHALLENGE_MODE_RESET" then
      ResetMPState()
      TTQ:StopMythicPlusTimer()

      -- Detect leaving the instance after completion
    elseif evt == "PLAYER_ENTERING_WORLD" or evt == "ZONE_CHANGED_NEW_AREA" then
      if mpState.runCompleted then
        local _, instanceType = GetInstanceInfo()
        if instanceType ~= "party" and instanceType ~= "raid" then
          ResetMPState()
        end
      end

      -- Track player deaths via combat log (primary method)
    elseif evt == "COMBAT_LOG_EVENT_UNFILTERED" then
      local _, subEvent, _, _, _, _, _, destGUID, destName, destFlags =
          CombatLogGetCurrentEventInfo()
      if subEvent ~= "UNIT_DIED" then return end
      if not destGUID or not destName then return end
      -- Only handle player deaths (not NPCs, pets, etc.)
      if not destFlags or bit.band(destFlags, COMBATLOG_OBJECT_TYPE_PLAYER) == 0 then return end
      -- Must be in an active M+ run
      local _, instanceType, difficultyID = GetInstanceInfo()
      if not (difficultyID == 8 and instanceType == "party") and not mpState.runCompleted then return end
      -- Ignore Feign Death (hunter ability that triggers UNIT_DIED in combat log)
      if UnitIsFeignDeath and UnitIsFeignDeath(destName) then return end
      -- Must be in our party
      if not (UnitInParty(destName) or UnitName("player") == destName) then return end

      local _, classToken = UnitClass(destName)
      if not classToken then classToken = TTQ:FindClassForName(destName) end

      local elapsed = mpState.startTime and (GetTime() - mpState.startTime) or 0
      if LogPlayerDeath(destName, classToken, elapsed) then
        mpState.lastDeathCount = #mpState.deathLog
        TTQ:ScheduleRefresh()
      end

      -- Death count API -- sync total count only (do not try to identify who died)
    elseif evt == "CHALLENGE_MODE_DEATH_COUNT_UPDATED" then
      if not C_ChallengeMode or not C_ChallengeMode.GetDeathCount then return end
      local numDeaths = C_ChallengeMode.GetDeathCount() or 0
      mpState.lastDeathCount = numDeaths

      -- Standalone UNIT_DIED event (12.0+, receives unitGUID)
    elseif evt == "UNIT_DIED" then
      local guid = ...
      if not guid then return end
      if issecretvalue and issecretvalue(guid) then return end
      if type(guid) ~= "string" or not guid:match("^Player%-") then return end

      local _, instanceType, difficultyID = GetInstanceInfo()
      if not (difficultyID == 8 and instanceType == "party") and not mpState.runCompleted then return end

      local destName, classToken
      -- Resolve name from GUID via party scan
      if UnitGUID("player") == guid then
        destName = UnitName("player")
        local _, cls = UnitClass("player")
        classToken = cls
      else
        for i = 1, 4 do
          local unit = "party" .. i
          if UnitExists(unit) and UnitGUID(unit) == guid then
            destName = UnitName(unit)
            local _, cls = UnitClass(unit)
            classToken = cls
            break
          end
        end
      end
      -- Fallback GUID resolution APIs
      if not destName and GetPlayerInfoByGUID then
        local ok, _, engClass, _, _, pName = pcall(GetPlayerInfoByGUID, guid)
        if ok and pName and pName ~= "" then
          destName = pName; classToken = engClass
        end
      end
      if not destName and UnitNameFromGUID then destName = UnitNameFromGUID(guid) end
      if not classToken and destName then classToken = TTQ:FindClassForName(destName) end
      if not destName then return end
      if UnitIsFeignDeath and UnitIsFeignDeath(destName) then return end
      if not (UnitInParty(destName) or UnitName("player") == destName) then return end

      local elapsed = mpState.startTime and (GetTime() - mpState.startTime) or 0
      if LogPlayerDeath(destName, classToken, elapsed) then
        mpState.lastDeathCount = #mpState.deathLog
        TTQ:ScheduleRefresh()
      end
    end

    -- Throttled refresh for all M+ events (skip high-frequency combat log events)
    if evt ~= "UNIT_DIED" and evt ~= "COMBAT_LOG_EVENT_UNFILTERED" then
      TTQ:ScheduleRefresh()
    end
  end

  ----------------------------------------------------------------------
  -- M+ event registration -- routes through QueueEvent (EventFrame.lua)
  -- which registers via EventRegistry BEFORE embeds.xml loads, so the
  -- execution context is untainted.
  ----------------------------------------------------------------------
  local mpEvents = {
    "PLAYER_ENTERING_WORLD",
    "ZONE_CHANGED_NEW_AREA",
    "ADDON_LOADED",
    "CHALLENGE_MODE_START",
    "CHALLENGE_MODE_COMPLETED",
    "CHALLENGE_MODE_RESET",
    "CHALLENGE_MODE_DEATH_COUNT_UPDATED",
    "WORLD_STATE_TIMER_START",
    "WORLD_STATE_TIMER_STOP",
    "COMBAT_LOG_EVENT_UNFILTERED",
    "UNIT_DIED",
  }
  for _, ev in ipairs(mpEvents) do
    TTQ:QueueEvent(ev, OnMPEvent)
  end

  -- Stub so InitTracker's conditional call is harmless
  function TTQ:RegisterMythicPlusEvents()
    -- Already registered at file scope above via QueueEvent
  end
end

----------------------------------------------------------------------
-- Helper: find class for a player name by scanning party/raid
----------------------------------------------------------------------
function TTQ:FindClassForName(name)
  if not name then return nil end
  -- Check party
  for i = 1, 4 do
    local unit = "party" .. i
    local unitName = UnitName(unit)
    if unitName and unitName == name then
      local _, cls = UnitClass(unit)
      return cls
    end
  end
  -- Check player
  local playerName = UnitName("player")
  if playerName == name then
    local _, cls = UnitClass("player")
    return cls
  end
  return nil
end
