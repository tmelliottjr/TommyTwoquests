----------------------------------------------------------------------
-- TommyTwoquests — MythicPlus.lua
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
local GetInstanceInfo                                                                 = GetInstanceInfo
local GameTooltip                                                                     = GameTooltip

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
  timerPlenty    = { r = 0.40, g = 1.00, b = 0.40 }, -- green: lots of time
  timerOk        = { r = 1.00, g = 0.82, b = 0.00 }, -- gold: moderate
  timerLow       = { r = 1.00, g = 0.40, b = 0.20 }, -- orange-red: low
  timerOver      = { r = 0.80, g = 0.20, b = 0.20 }, -- red: over time
  chestActive    = { r = 1.00, g = 0.82, b = 0.00 }, -- gold: still achievable
  chestLost      = { r = 0.40, g = 0.40, b = 0.40 }, -- grey: no longer possible
  chestEarned    = { r = 0.20, g = 0.80, b = 0.40 }, -- emerald: earned
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

-- Manual start-time tracking (fallback when GetWorldElapsedTime is unreliable)
local mpStartTime                                                                     = nil   -- GetTime() when the key started
local mpCachedTimerID                                                                 = nil   -- cached world-elapsed-timer ID for this run
local mpRunCompleted                                                                  = false -- true after CHALLENGE_MODE_COMPLETED until player leaves instance
local mpCompletionTime                                                                = nil   -- elapsed time when the run completed

-- Death log: tracks individual player deaths during the M+ run
-- Each entry: { name, class, timestamp (elapsed seconds), penalty }
local mpDeathLog                                                                      = {}
local mpLastDeathCount                                                                = 0 -- track previous count to detect new deaths
local DEATH_PENALTY_PER                                                               = 5 -- seconds per death

----------------------------------------------------------------------
-- Detection: is the player in an active Mythic+ run?
----------------------------------------------------------------------
function TTQ:IsMythicPlusActive()
  -- Still show M+ display after completion until player leaves the instance
  if mpRunCompleted then return true end
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
    mapID         = 0,
    dungeonName   = "",
    keystoneLevel = 0,
    affixes       = {},
    timeLimit     = 0,  -- base time limit in seconds
    elapsed       = 0,  -- seconds elapsed
    remaining     = 0,  -- seconds remaining (can be negative)
    isOverTime    = false,
    chestTimers   = {}, -- { {label, limit, remaining, active} ... }
    deaths        = 0,
    deathPenalty  = 0,  -- seconds lost to deaths
    bosses        = {}, -- { {name, completed} ... }
    bossesKilled  = 0,
    bossesTotal   = 0,
    enemyForces   = 0, -- current count/progress
    enemyTotal    = 0, -- total needed
    enemyPct      = 0, -- 0-100
    enemyComplete = false,
  }

  -- Map / dungeon info
  local mapID = C_ChallengeMode.GetActiveChallengeMapID()
  if mapID then
    data.mapID = mapID
    local name, _, timeLimit = C_ChallengeMode.GetMapUIInfo(mapID)
    data.dungeonName = name or "Mythic+"
    data.timeLimit = timeLimit or 0
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
    -- Also pull from C_MythicPlus.GetCurrentAffixes() for seasonal/weekly affixes
    -- that may not be included in GetActiveKeystoneInfo
    if C_MythicPlus and C_MythicPlus.GetCurrentAffixes then
      local currentAffixes = C_MythicPlus.GetCurrentAffixes()
      if currentAffixes then
        for _, affixInfo in ipairs(currentAffixes) do
          local affixID = affixInfo.id
          if affixID and not seenAffixes[affixID] then
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
    end
  end

  -- Timer: if run is completed, use frozen completion time
  if mpRunCompleted and mpCompletionTime then
    data.elapsed = mpCompletionTime
  else
    -- Use GetWorldElapsedTime(1) directly (same as WarpDeplete)
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
    if not timerFound and mpStartTime then
      data.elapsed = GetTime() - mpStartTime
      timerFound = true
    end

    -- If Strategy 1 found a time, back-calculate mpStartTime so it survives
    -- for the manual fallback (important after /reload when mpStartTime is nil)
    if timerFound and data.elapsed > 0 and not mpStartTime then
      mpStartTime = GetTime() - data.elapsed
    end

    -- If no timer source is available yet (countdown phase), show 0
    if not timerFound then
      data.elapsed = 0
    end
  end -- close the else from "if mpRunCompleted"

  data.remaining = data.timeLimit - data.elapsed
  data.isOverTime = data.remaining < 0

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

      if criteriaInfo then
        local desc = criteriaInfo.description or ""
        local completed = criteriaInfo.completed or false
        local qty = criteriaInfo.quantity or 0
        local totalQty = criteriaInfo.totalQuantity or 0
        local isWeightedProgress = criteriaInfo.isWeightedProgress
        local isForcesCriteria = criteriaInfo.isForcesCriteria

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
      else
        -- Legacy fallback
        local desc, _, completed, qty, totalQty
        if C_Scenario.GetCriteriaInfo then
          desc, _, completed, qty, totalQty = C_Scenario.GetCriteriaInfo(i)
        end
        if desc then
          local isEF = (desc and desc:lower():find("forces"))
              or (totalQty and totalQty > 100 and i == numCriteria)
          if isEF then
            data.enemyForces = qty or 0
            data.enemyTotal = totalQty or 0
            data.enemyPct = (totalQty and totalQty > 0)
                and math.min(((qty or 0) / totalQty) * 100, 100) or 0
            data.enemyComplete = completed or ((qty or 0) >= (totalQty or 0))
          else
            data.bosses[#data.bosses + 1] = {
              name = desc,
              completed = completed or false,
            }
            if completed then
              data.bossesKilled = data.bossesKilled + 1
            end
          end
        end
      end
    end

    data.bossesTotal = #data.bosses
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
-- Get timer color based on remaining time ratio
----------------------------------------------------------------------
local function GetTimerColor(remaining, total)
  if remaining <= 0 then
    return MP.Colors.timerOver
  end
  local ratio = remaining / total
  if ratio > 0.5 then
    return MP.Colors.timerPlenty
  elseif ratio > 0.25 then
    -- Lerp green → gold
    local t = (ratio - 0.25) / 0.25
    return {
      r = MP.Colors.timerPlenty.r + (MP.Colors.timerOk.r - MP.Colors.timerPlenty.r) * (1 - t),
      g = MP.Colors.timerPlenty.g + (MP.Colors.timerOk.g - MP.Colors.timerPlenty.g) * (1 - t),
      b = MP.Colors.timerPlenty.b + (MP.Colors.timerOk.b - MP.Colors.timerPlenty.b) * (1 - t),
    }
  elseif ratio > 0.1 then
    -- Lerp gold → orange-red
    local t = (ratio - 0.1) / 0.15
    return {
      r = MP.Colors.timerOk.r + (MP.Colors.timerLow.r - MP.Colors.timerOk.r) * (1 - t),
      g = MP.Colors.timerOk.g + (MP.Colors.timerLow.g - MP.Colors.timerOk.g) * (1 - t),
      b = MP.Colors.timerOk.b + (MP.Colors.timerLow.b - MP.Colors.timerOk.b) * (1 - t),
    }
  else
    return MP.Colors.timerLow
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
  -- 2b. Timer progress bar: left→right spanning full width with
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

  -- Bar fill (grows left→right as time elapses)
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
  -- 4. Deaths row (interactive — hover for death log)
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
    if #mpDeathLog > 0 then
      -- Aggregate deaths per player: { name, class, count, totalPenalty }
      local byPlayer = {}  -- name -> { class, count }
      local order = {}     -- insertion-order of names
      for _, entry in ipairs(mpDeathLog) do
        if not byPlayer[entry.name] then
          byPlayer[entry.name] = { class = entry.class, count = 0 }
          order[#order + 1] = entry.name
        end
        byPlayer[entry.name].count = byPlayer[entry.name].count + 1
      end
      for _, pName in ipairs(order) do
        local info = byPlayer[pName]
        local cr, cg, cb = 0.85, 0.85, 0.85
        if info.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[info.class] then
          local cc = RAID_CLASS_COLORS[info.class]
          cr, cg, cb = cc.r, cc.g, cc.b
        end
        local penalty = info.count * DEATH_PENALTY_PER
        local line = pName .. "  x" .. info.count .. "  |cff888888(+" .. penalty .. "s)|r"
        GameTooltip:AddLine(line, cr, cg, cb)
      end
      -- Total summary
      local totalPenalty = #mpDeathLog * DEATH_PENALTY_PER
      GameTooltip:AddLine(" ")
      GameTooltip:AddLine(#mpDeathLog .. " total " .. (#mpDeathLog == 1 and "death" or "deaths") .. "  |  +" .. FormatTime(totalPenalty) .. " penalty", 0.6, 0.6, 0.6)
    else
      -- Fallback: show count from API even if we missed the details
      local numDeaths = 0
      if C_ChallengeMode and C_ChallengeMode.GetDeathCount then
        numDeaths = C_ChallengeMode.GetDeathCount() or 0
      end
      if numDeaths > 0 then
        GameTooltip:AddLine(numDeaths .. " death(s) — details not captured", 0.6, 0.6, 0.6)
      end
    end
    GameTooltip:Show()
  end)
  deathHitbox:SetScript("OnLeave", function()
    GameTooltip:Hide()
  end)
  el.deathHitbox = deathHitbox

  ----------------------------------------------------------------
  -- 5. Enemy forces bar
  ----------------------------------------------------------------
  local trashRow = CreateFrame("Frame", nil, f)
  trashRow:SetHeight(26)
  el.trashRow = trashRow

  local trashLabel = TTQ:CreateText(trashRow, objSize, MP.Colors.labelColor, "LEFT")
  trashLabel:SetPoint("LEFT", trashRow, "LEFT", 0, 6)
  trashLabel:SetText("Enemy Forces")
  el.trashLabel = trashLabel

  local trashPct = TTQ:CreateText(trashRow, objSize, MP.Colors.trashBar, "RIGHT")
  trashPct:SetPoint("RIGHT", trashRow, "RIGHT", 0, 6)
  el.trashPct = trashPct

  -- Progress bar background
  local barBg = trashRow:CreateTexture(nil, "BACKGROUND")
  barBg:SetHeight(4)
  barBg:SetPoint("BOTTOMLEFT", trashRow, "BOTTOMLEFT", 0, 1)
  barBg:SetPoint("BOTTOMRIGHT", trashRow, "BOTTOMRIGHT", 0, 1)
  barBg:SetColorTexture(MP.Colors.trashBg.r, MP.Colors.trashBg.g, MP.Colors.trashBg.b, 0.6)
  el.barBg = barBg

  -- Progress bar fill
  local barFill = trashRow:CreateTexture(nil, "ARTWORK")
  barFill:SetHeight(4)
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
  local affixRow = CreateFrame("Frame", nil, f)
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

  -- Dash / checkmark
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

  local objSize = self:GetSetting("objectiveFontSize")
  local nameSize = self:GetSetting("questNameFontSize")
  local headerSize = self:GetSetting("headerFontSize")
  local headerFont = self:GetResolvedFont("header")
  local questFont = self:GetResolvedFont("quest")
  local objFont = self:GetResolvedFont("objective")
  local headerOutline = self:GetSetting("headerFontOutline")
  local objOutline = self:GetSetting("objectiveFontOutline")
  local headerColor = self:GetSetting("headerColor")
  local completeColor = self:GetSetting("objectiveCompleteColor")
  local incompleteColor = self:GetSetting("objectiveIncompleteColor")

  local y = 0
  local indent = 0 -- no indent for M+ (centered feel)

  ----------------------------------------------------------------
  -- Header
  ----------------------------------------------------------------
  if not pcall(el.headerText.SetFont, el.headerText, headerFont, headerSize, headerOutline) then
    pcall(el.headerText.SetFont, el.headerText, "Fonts\\FRIZQT__.TTF", headerSize, headerOutline)
  end
  el.headerText:SetTextColor(headerColor.r, headerColor.g, headerColor.b)
  el.headerText:SetText(data.dungeonName)

  if not pcall(el.keyBadge.SetFont, el.keyBadge, headerFont, headerSize, headerOutline) then
    pcall(el.keyBadge.SetFont, el.keyBadge, "Fonts\\FRIZQT__.TTF", headerSize, headerOutline)
  end
  el.keyBadge:SetText("+" .. data.keystoneLevel)
  el.keyBadge:SetTextColor(headerColor.r, headerColor.g, headerColor.b)

  if self:GetSetting("showIcons") then
    el.headerIcon:Show()
    local iconSize = math.max(10, headerSize - 1)
    el.headerIcon:SetSize(iconSize + 4, iconSize + 4)
  else
    el.headerIcon:Hide()
    el.headerText:SetPoint("LEFT", el.headerRow, "LEFT", 0, 0)
  end

  el.headerRow:ClearAllPoints()
  el.headerRow:SetPoint("TOPLEFT", mpFrame, "TOPLEFT", 0, -y)
  el.headerRow:SetPoint("TOPRIGHT", mpFrame, "TOPRIGHT", 0, -y)
  y = y + 24 -- header height + gap

  ----------------------------------------------------------------
  -- Affixes (icon-only circles with border, tooltip on hover)
  ----------------------------------------------------------------
  if #data.affixes > 0 then
    local AFFIX_ICON_SIZE = 20
    local AFFIX_SPACING = 5
    -- Center the row of icons
    local totalAffixWidth = #data.affixes * AFFIX_ICON_SIZE + (#data.affixes - 1) * AFFIX_SPACING
    local startX = math.max(0, math.floor((width - totalAffixWidth) / 2))

    el.affixRow:ClearAllPoints()
    el.affixRow:SetPoint("TOPLEFT", mpFrame, "TOPLEFT", 0, -y)
    el.affixRow:SetPoint("TOPRIGHT", mpFrame, "TOPRIGHT", 0, -y)
    el.affixRow:SetHeight(AFFIX_ICON_SIZE + 2)
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

      -- Set icon texture
      if aff.icon and btn.icon then
        btn.icon:SetTexture(aff.icon)
        btn.icon:Show()
      end

      -- Position
      local xPos = startX + (idx - 1) * (AFFIX_ICON_SIZE + AFFIX_SPACING)
      btn:ClearAllPoints()
      btn:SetPoint("TOPLEFT", el.affixRow, "TOPLEFT", xPos, 0)
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

    y = y + AFFIX_ICON_SIZE + 4
  else
    el.affixRow:Hide()
    if el.affixButtons then
      for _, v in pairs(el.affixButtons) do
        if v.Hide then v:Hide() end
      end
    end
  end

  ----------------------------------------------------------------
  -- Timer
  ----------------------------------------------------------------
  local timerColor = GetTimerColor(data.remaining, data.timeLimit)

  if not pcall(el.timerText.SetFont, el.timerText, questFont, nameSize + 2, objOutline) then
    pcall(el.timerText.SetFont, el.timerText, "Fonts\\FRIZQT__.TTF", nameSize + 2, objOutline)
  end
  el.timerText:SetText(FormatTime(data.elapsed))
  el.timerText:SetTextColor(timerColor.r, timerColor.g, timerColor.b)

  if not pcall(el.timerRemaining.SetFont, el.timerRemaining, objFont, objSize, objOutline) then
    pcall(el.timerRemaining.SetFont, el.timerRemaining, "Fonts\\FRIZQT__.TTF", objSize, objOutline)
  end
  if data.isOverTime then
    el.timerRemaining:SetText("OVER TIME")
    el.timerRemaining:SetTextColor(MP.Colors.timerOver.r, MP.Colors.timerOver.g, MP.Colors.timerOver.b)
  else
    el.timerRemaining:SetText(FormatTime(data.remaining) .. " left")
    el.timerRemaining:SetTextColor(timerColor.r, timerColor.g, timerColor.b)
  end

  el.timerRow:ClearAllPoints()
  el.timerRow:SetPoint("TOPLEFT", mpFrame, "TOPLEFT", 0, -y)
  el.timerRow:SetPoint("TOPRIGHT", mpFrame, "TOPRIGHT", 0, -y)
  y = y + 22

  ----------------------------------------------------------------
  -- Timer progress bar
  ----------------------------------------------------------------
  local barTotalWidth = width - indent
  -- The bar represents timeLimit + overtime buffer, so +1 isn't at the far edge
  local barRange = data.timeLimit + MP.OVERTIME_BUFFER
  local fillRatio = barRange > 0 and math.min(data.elapsed / barRange, 1.0) or 0
  local fillWidth = math.max(1, fillRatio * barTotalWidth)

  -- Color the fill based on which chest tier we're in
  local barColor = GetTimerColor(data.remaining, data.timeLimit)
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

      -- Tick color: earned (green), active (gold), lost (grey)
      local tickColor
      if data.elapsed <= ct.limit then
        tickColor = (data.elapsed > 0 and ct.remaining < 30) and MP.Colors.timerLow or MP.Colors.chestActive
      else
        tickColor = MP.Colors.chestLost
      end
      tick.line:SetColorTexture(tickColor.r, tickColor.g, tickColor.b, 0.7)

      if not pcall(tick.label.SetFont, tick.label, objFont, objSize - 3, objOutline) then
        pcall(tick.label.SetFont, tick.label, "Fonts\\FRIZQT__.TTF", objSize - 3, objOutline)
      end
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
  -- Chest tiers — aligned under their tick marks on the bar
  ----------------------------------------------------------------
  local barActualWidth = el.timerBarBg:GetWidth()
  if not barActualWidth or barActualWidth <= 0 then barActualWidth = barTotalWidth end
  local barRange2 = data.timeLimit + MP.OVERTIME_BUFFER
  for i = 1, 3 do
    local ci = el.chestIndicators[i]
    local ct = data.chestTimers[i]
    if ci and ct then
      local color
      if ct.remaining > 0 and not data.isOverTime then
        if data.elapsed > 0 and ct.remaining < 30 then
          color = MP.Colors.timerLow
        else
          color = MP.Colors.chestActive
        end
      elseif ct.remaining <= 0 and data.elapsed <= ct.limit then
        color = MP.Colors.chestEarned
      else
        color = MP.Colors.chestLost
      end

      if not pcall(ci.label.SetFont, ci.label, objFont, objSize, objOutline) then
        pcall(ci.label.SetFont, ci.label, "Fonts\\FRIZQT__.TTF", objSize, objOutline)
      end
      if not pcall(ci.timeLabel.SetFont, ci.timeLabel, objFont, objSize - 1, objOutline) then
        pcall(ci.timeLabel.SetFont, ci.timeLabel, "Fonts\\FRIZQT__.TTF", objSize - 1, objOutline)
      end

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
  y = y + 16

  ----------------------------------------------------------------
  -- Deaths (only show if > 0)
  ----------------------------------------------------------------
  if data.deaths > 0 then
    if not pcall(el.deathText.SetFont, el.deathText, objFont, objSize, objOutline) then
      pcall(el.deathText.SetFont, el.deathText, "Fonts\\FRIZQT__.TTF", objSize, objOutline)
    end
    if not pcall(el.deathPenalty.SetFont, el.deathPenalty, objFont, objSize - 1, objOutline) then
      pcall(el.deathPenalty.SetFont, el.deathPenalty, "Fonts\\FRIZQT__.TTF", objSize - 1, objOutline)
    end

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
    if not pcall(el.trashLabel.SetFont, el.trashLabel, objFont, objSize, objOutline) then
      pcall(el.trashLabel.SetFont, el.trashLabel, "Fonts\\FRIZQT__.TTF", objSize, objOutline)
    end
    if not pcall(el.trashPct.SetFont, el.trashPct, objFont, objSize, objOutline) then
      pcall(el.trashPct.SetFont, el.trashPct, "Fonts\\FRIZQT__.TTF", objSize, objOutline)
    end

    local pctStr = string.format("%.1f%%", data.enemyPct)
    el.trashPct:SetText(pctStr)

    local barColor = data.enemyComplete and MP.Colors.trashBarFull or MP.Colors.trashBar
    el.trashPct:SetTextColor(barColor.r, barColor.g, barColor.b)
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
    y = y + 28
  else
    el.trashRow:Hide()
  end

  ----------------------------------------------------------------
  -- Boss progress (at the bottom)
  ----------------------------------------------------------------
  for i, boss in ipairs(data.bosses) do
    local bossItem = EnsureBossItem(el, mpFrame, i)

    if not pcall(bossItem.name.SetFont, bossItem.name, objFont, objSize, objOutline) then
      pcall(bossItem.name.SetFont, bossItem.name, "Fonts\\FRIZQT__.TTF", objSize, objOutline)
    end
    if not pcall(bossItem.dash.SetFont, bossItem.dash, objFont, objSize, objOutline) then
      pcall(bossItem.dash.SetFont, bossItem.dash, "Fonts\\FRIZQT__.TTF", objSize, objOutline)
    end

    bossItem.name:SetText(boss.name)
    if boss.completed then
      local c = completeColor
      bossItem.name:SetTextColor(c.r, c.g, c.b)
      bossItem.dash:SetText("|TInterface\\RaidFrame\\ReadyCheck-Ready:" .. objSize .. "|t")
      bossItem.dash:SetTextColor(c.r, c.g, c.b)
    else
      local c = incompleteColor
      bossItem.name:SetTextColor(c.r, c.g, c.b)
      bossItem.dash:SetText("-")
      bossItem.dash:SetTextColor(c.r, c.g, c.b)
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
      if TTQ.RefreshTracker then
        TTQ:RefreshTracker()
      end
      return
    end

    if not mpFrame:IsShown() or not mpElements.timerText then return end

    local data = TTQ:GetMythicPlusData()
    if not data then return end

    -- Timer text
    local timerColor = GetTimerColor(data.remaining, data.timeLimit)
    mpElements.timerText:SetText(FormatTime(data.elapsed))
    mpElements.timerText:SetTextColor(timerColor.r, timerColor.g, timerColor.b)

    if data.isOverTime then
      mpElements.timerRemaining:SetText("OVER TIME")
      mpElements.timerRemaining:SetTextColor(
        MP.Colors.timerOver.r, MP.Colors.timerOver.g, MP.Colors.timerOver.b)
    else
      mpElements.timerRemaining:SetText(FormatTime(data.remaining) .. " left")
      mpElements.timerRemaining:SetTextColor(timerColor.r, timerColor.g, timerColor.b)
    end

    -- Progress bar fill
    if mpElements.timerBarFill and mpElements.timerBarBg then
      local barWidth = mpElements.timerBarBg:GetWidth()
      if barWidth and barWidth > 0 then
        local barRange = data.timeLimit + MP.OVERTIME_BUFFER
        local fillRatio = barRange > 0
            and math.min(data.elapsed / barRange, 1.0) or 0
        local fillW = math.max(1, fillRatio * barWidth)
        mpElements.timerBarFill:SetWidth(fillW)
        mpElements.timerBarFill:SetColorTexture(
          timerColor.r, timerColor.g, timerColor.b, 0.85)
      end
    end

    -- Chest tier tick marks + remaining times
    for i = 1, 3 do
      local ci = mpElements.chestIndicators[i]
      local ct = data.chestTimers[i]
      if ci and ct then
        local color
        if ct.active then
          color = ct.remaining < 30 and MP.Colors.timerLow or MP.Colors.chestActive
          ci.timeLabel:SetText(FormatTime(ct.remaining))
        else
          color = (data.elapsed <= ct.limit)
              and MP.Colors.chestEarned or MP.Colors.chestLost
          ci.timeLabel:SetText(FormatTime(ct.limit))
        end
        ci.label:SetTextColor(color.r, color.g, color.b)
        ci.timeLabel:SetTextColor(color.r, color.g, color.b)
      end

      -- Update tick mark colors
      local tick = mpElements.timerBarTicks and mpElements.timerBarTicks[i]
      if tick and ct then
        local tickColor
        if data.elapsed <= ct.limit then
          tickColor = (ct.remaining < 30)
              and MP.Colors.timerLow or MP.Colors.chestActive
        else
          tickColor = MP.Colors.chestLost
        end
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
-- Create the M+ event frame at file scope (untainted execution
-- context) so Frame:RegisterEvent() never triggers
-- ADDON_ACTION_FORBIDDEN.
----------------------------------------------------------------------
do
  local evFrame = CreateFrame("Frame")
  TTQ._mpEventFrame = evFrame

  evFrame:RegisterEvent("CHALLENGE_MODE_START")
  evFrame:RegisterEvent("CHALLENGE_MODE_COMPLETED")
  evFrame:RegisterEvent("CHALLENGE_MODE_RESET")
  evFrame:RegisterEvent("CHALLENGE_MODE_DEATH_COUNT_UPDATED")
  evFrame:RegisterEvent("WORLD_STATE_TIMER_START")
  evFrame:RegisterEvent("WORLD_STATE_TIMER_STOP")
  evFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
  evFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
  -- In WoW 12.0 (Midnight) COMBAT_LOG_EVENT_UNFILTERED registration is
  -- protected; use the new standalone UNIT_DIED event instead (same
  -- approach as WarpDeplete).
  evFrame:RegisterEvent("UNIT_DIED")

  evFrame:SetScript("OnEvent", function(_, evt, ...)
    if evt == "WORLD_STATE_TIMER_START" then
      mpStartTime = GetTime()
      mpCachedTimerID = nil
      mpRunCompleted = false
      mpCompletionTime = nil
      wipe(mpDeathLog)
      mpLastDeathCount = 0

      -- Run completed — freeze timer, keep display
    elseif evt == "CHALLENGE_MODE_COMPLETED" then
      mpRunCompleted = true
      -- Capture the real dungeon elapsed time from the world timer.
      -- Never fall back to GetTime() - mpStartTime because mpStartTime
      -- includes the ~10s countdown phase, producing an inflated time
      -- that incorrectly shows OVER TIME on timed runs.
      local completionElapsed
      if GetWorldElapsedTime then
        local ok, _, elapsed = pcall(GetWorldElapsedTime, 1)
        elapsed = tonumber(elapsed)
        if ok and elapsed and elapsed > 0 then
          completionElapsed = elapsed
        end
      end
      mpCompletionTime = completionElapsed
      TTQ:StopMythicPlusTimer()

      -- Key reset
    elseif evt == "CHALLENGE_MODE_RESET" then
      mpRunCompleted = false
      mpCompletionTime = nil
      mpStartTime = nil
      mpCachedTimerID = nil
      TTQ:StopMythicPlusTimer()

      -- Detect leaving the instance after completion
    elseif evt == "PLAYER_ENTERING_WORLD" or evt == "ZONE_CHANGED_NEW_AREA" then
      if mpRunCompleted then
        local _, instanceType = GetInstanceInfo()
        if instanceType ~= "party" and instanceType ~= "raid" then
          mpRunCompleted = false
          mpCompletionTime = nil
          mpStartTime = nil
          mpCachedTimerID = nil
          wipe(mpDeathLog)
          mpLastDeathCount = 0
        end
      end

      -- Track individual player deaths via UNIT_DIED event
      -- (Midnight 12.0 standalone event — receives GUID as first arg)
    elseif evt == "UNIT_DIED" then
      local guid = ...
      if not guid then return end
      -- SecretWhenUnitIdentityRestricted: skip secret (non-party) GUIDs
      if issecretvalue and issecretvalue(guid) then return end

      -- Must be in an active or just-completed run
      local _, instanceType, difficultyID = GetInstanceInfo()
      if not (difficultyID == 8 and instanceType == "party") and not mpRunCompleted then return end

      -- Resolve name and class — try direct API first, then scan party GUIDs
      local destName, classToken

      -- Try UnitNameFromGUID / UnitClassFromGUID (12.0 API)
      if UnitNameFromGUID then destName = UnitNameFromGUID(guid) end
      if UnitClassFromGUID then
        local _, token = UnitClassFromGUID(guid)
        classToken = token
      end

      -- Fallback: scan party/player unit GUIDs directly
      if not destName then
        if UnitGUID("player") == guid then
          destName = UnitName("player")
          local _, cls = UnitClass("player")
          classToken = classToken or cls
        else
          for i = 1, 4 do
            local unit = "party" .. i
            if UnitExists(unit) and UnitGUID(unit) == guid then
              destName = UnitName(unit)
              local _, cls = UnitClass(unit)
              classToken = classToken or cls
              break
            end
          end
        end
      end

      if not destName then return end

      -- Must be in our party (or the player themselves)
      if not (UnitInParty(destName) or UnitName("player") == destName) then return end

      -- Fallback class detection via party scan
      if not classToken then
        classToken = TTQ:FindClassForName(destName)
      end

      -- Calculate elapsed time at death
      local elapsed = 0
      if mpStartTime then
        elapsed = GetTime() - mpStartTime
      end

      -- Deduplicate: skip if this player was already logged within 3 seconds
      -- (guards against CHALLENGE_MODE_DEATH_COUNT_UPDATED racing us)
      for idx = #mpDeathLog, math.max(1, #mpDeathLog - 4), -1 do
        local prev = mpDeathLog[idx]
        if prev and prev.name == destName and math.abs(prev.elapsed - elapsed) < 3 then
          return -- already logged by backup handler
        end
      end

      mpDeathLog[#mpDeathLog + 1] = {
        name = destName,
        class = classToken,
        elapsed = elapsed,
      }
      mpLastDeathCount = #mpDeathLog

      -- Trigger a throttled UI refresh so the death shows immediately
      if not TTQ._refreshTimer then
        TTQ._refreshTimer = C_Timer.NewTimer(0.1, function()
          TTQ._refreshTimer = nil
          if TTQ.RefreshTracker then
            TTQ:RefreshTracker()
          end
        end)
      end

      -- Backup death detection via official death count API
    elseif evt == "CHALLENGE_MODE_DEATH_COUNT_UPDATED" then
      if not C_ChallengeMode or not C_ChallengeMode.GetDeathCount then return end

      local numDeaths = C_ChallengeMode.GetDeathCount() or 0
      if numDeaths > mpLastDeathCount and #mpDeathLog < numDeaths then
        local elapsed = 0
        if mpStartTime then
          elapsed = GetTime() - mpStartTime
        end
        -- Build set of recently logged names to avoid duplicates
        local recentlyLogged = {}
        for _, entry in ipairs(mpDeathLog) do
          if math.abs(entry.elapsed - elapsed) < 2 then
            recentlyLogged[entry.name] = true
          end
        end
        -- Scan for dead party members
        local foundAny = false
        if UnitIsDeadOrGhost("player") then
          local pName = UnitName("player")
          if pName and not recentlyLogged[pName] then
            local _, cls = UnitClass("player")
            mpDeathLog[#mpDeathLog + 1] = { name = pName, class = cls, elapsed = elapsed }
            foundAny = true
          end
        end
        for i = 1, 4 do
          local unit = "party" .. i
          if UnitExists(unit) and UnitIsDeadOrGhost(unit) then
            local pName = UnitName(unit)
            if pName and not recentlyLogged[pName] then
              local _, cls = UnitClass(unit)
              mpDeathLog[#mpDeathLog + 1] = { name = pName, class = cls, elapsed = elapsed }
              foundAny = true
            end
          end
        end
      end
      -- Always sync count so we don't re-process the same deaths
      mpLastDeathCount = numDeaths
    end

    -- Throttled refresh for all M+ events
    if evt ~= "UNIT_DIED" then
      if not TTQ._refreshTimer then
        TTQ._refreshTimer = C_Timer.NewTimer(0.1, function()
          TTQ._refreshTimer = nil
          if TTQ.RefreshTracker then
            TTQ:RefreshTracker()
          end
        end)
      end
    end
  end)
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

----------------------------------------------------------------------
-- Helper: find a dead party member (for backup death detection)
----------------------------------------------------------------------
function TTQ:FindDeadPartyMember()
  -- Check player first
  if UnitIsDeadOrGhost("player") then
    local name = UnitName("player")
    local _, cls = UnitClass("player")
    return name, cls
  end
  -- Check party members
  for i = 1, 4 do
    local unit = "party" .. i
    if UnitExists(unit) and UnitIsDeadOrGhost(unit) then
      local name = UnitName(unit)
      local _, cls = UnitClass(unit)
      return name, cls
    end
  end
  return nil, nil
end
