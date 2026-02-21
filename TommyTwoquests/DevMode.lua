----------------------------------------------------------------------
-- TommyTwoquests — DevMode.lua
-- Dev/testing module for rapid M+ UI iteration without running dungeons.
--
-- Intercepts IsMythicPlusActive() and GetMythicPlusData() to feed
-- mock data through the real rendering pipeline, so you can iterate
-- on the M+ tracker UI in seconds with /reload instead of running
-- actual keystones.
--
-- Usage:  /ttdev   — opens the dev panel
----------------------------------------------------------------------
local AddonName, TTQ = ...
local CreateFrame, UIParent, C_Timer, GetTime =
    CreateFrame, UIParent, C_Timer, GetTime
local GetCursorPosition, IsMouseButtonDown =
    GetCursorPosition, IsMouseButtonDown
local math, string, ipairs, pairs, print, wipe, table, tonumber, strtrim =
    math, string, ipairs, pairs, print, wipe, table, tonumber, strtrim

----------------------------------------------------------------------
-- Dev mode flag
----------------------------------------------------------------------
TTQ._devModeActive = false

----------------------------------------------------------------------
-- Style constants (dark cinematic, matches Settings.lua)
----------------------------------------------------------------------
local S = {
  Font       = "Fonts\\FRIZQT__.TTF",
  PanelW     = 300,
  Pad        = 10,
  RowH       = 24,
  BtnH       = 24,
  -- Colors
  Bg         = { 0.06, 0.06, 0.08, 0.95 },
  Border     = { 0.22, 0.24, 0.30, 0.50 },
  Section    = { 0.55, 0.60, 0.70 },
  Label      = { 0.90, 0.90, 0.92 },
  Value      = { 1, 0.82, 0 },
  BtnBg      = { 0.14, 0.14, 0.18, 0.95 },
  BtnHover   = { 0.22, 0.24, 0.30, 0.95 },
  BtnText    = { 0.92, 0.92, 0.95 },
  BtnDanger  = { 0.80, 0.25, 0.25 },
  BtnSuccess = { 0.20, 0.80, 0.40 },
  BtnWarn    = { 1.00, 0.60, 0.15 },
  Active     = { 0.48, 0.58, 0.82 },
  Inactive   = { 0.40, 0.40, 0.44 },
  TrackBg    = { 0.14, 0.14, 0.18, 0.95 },
  TrackFill  = { 0.48, 0.58, 0.82, 0.90 },
  Thumb      = { 1, 1, 1, 0.95 },
  BossAlive  = { 0.85, 0.85, 0.85 },
  BossDead   = { 0.20, 0.80, 0.40 },
}

----------------------------------------------------------------------
-- Mock dungeon presets
----------------------------------------------------------------------
local DUNGEON_PRESETS = {
  {
    name       = "The Stonevault",
    mapID      = 375,
    timeLimit  = 2100,
    bosses     = { "E.D.N.A.", "Skarmorak", "Master Machinists", "Void Speaker Eirich" },
    enemyTotal = 300,
    affixes    = {
      { id = 9,   name = "Tyrannical",                     description = "Boss enemies have 30% more health and inflict up to 15% increased damage.", icon = 236401 },
      { id = 134, name = "Xal'atath's Bargain: Ascendant", description = "While in combat, Xal'atath will choose a non-boss enemy to empower.",       icon = 135994 },
    },
  },
  {
    name       = "Cinderbrew Meadery",
    mapID      = 376,
    timeLimit  = 1800,
    bosses     = { "Brew Master Aldryr", "I'pa", "Benk Buzzbee", "Goldie Baronbottom" },
    enemyTotal = 320,
    affixes    = {
      { id = 10,  name = "Fortified",                     description = "Non-boss enemies have 20% more health and inflict up to 30% increased damage.", icon = 236403 },
      { id = 136, name = "Xal'atath's Bargain: Frenzied", description = "Non-boss enemies become Frenzied at 30% health remaining.",                     icon = 132347 },
    },
  },
  {
    name       = "Darkflame Cleft",
    mapID      = 377,
    timeLimit  = 2100,
    bosses     = { "Ol' Waxbeard", "Blazikon", "The Candle King", "The Darkness" },
    enemyTotal = 280,
    affixes    = {
      { id = 9,   name = "Tyrannical",         description = "Boss enemies have 30% more health and inflict up to 15% increased damage.", icon = 236401 },
      { id = 152, name = "Challenger's Peril", description = "Dying subtracts 15 seconds from time remaining.",                           icon = 136201 },
    },
  },
}

----------------------------------------------------------------------
-- Mock M+ state
----------------------------------------------------------------------
local mockState = {
  active          = false,
  startTime       = nil,
  timeOffset      = 0,
  dungeonPreset   = 1,
  keystoneLevel   = 12,
  deaths          = 0,
  deathLog        = {},
  bossesKilled    = {},
  enemyForcePct   = 0,
  runCompleted    = false,
  completedOnTime = nil,
  completionTime  = nil,
}

local function ResetMock()
  mockState.active        = false
  mockState.startTime     = nil
  mockState.timeOffset    = 0
  mockState.dungeonPreset = mockState.dungeonPreset or 1
  mockState.keystoneLevel = 12
  mockState.deaths        = 0
  wipe(mockState.deathLog)
  wipe(mockState.bossesKilled)
  mockState.enemyForcePct   = 0
  mockState.runCompleted    = false
  mockState.completedOnTime = nil
  mockState.completionTime  = nil
end

----------------------------------------------------------------------
-- Original function references
----------------------------------------------------------------------
local origIsMythicPlusActive = nil
local origGetMythicPlusData  = nil

----------------------------------------------------------------------
-- Build the mock data table
----------------------------------------------------------------------
local function BuildMockData()
  local preset = DUNGEON_PRESETS[mockState.dungeonPreset] or DUNGEON_PRESETS[1]

  local data = {
    mapID           = preset.mapID,
    dungeonName     = preset.name,
    keystoneLevel   = mockState.keystoneLevel,
    affixes         = {},
    timeLimit       = preset.timeLimit,
    elapsed         = 0,
    remaining       = 0,
    isOverTime      = false,
    runCompleted    = mockState.runCompleted,
    completedOnTime = mockState.completedOnTime,
    completionChest = 0,
    chestTimers     = {},
    deaths          = mockState.deaths,
    deathPenalty    = mockState.deaths * 5,
    bosses          = {},
    bossesKilled    = 0,
    bossesTotal     = #preset.bosses,
    enemyForces     = 0,
    enemyTotal      = preset.enemyTotal,
    enemyPct        = mockState.enemyForcePct,
    enemyComplete   = mockState.enemyForcePct >= 100,
  }

  for _, aff in ipairs(preset.affixes) do
    data.affixes[#data.affixes + 1] = {
      id          = aff.id,
      name        = aff.name,
      description = aff.description,
      icon        = aff.icon,
    }
  end

  if mockState.runCompleted and mockState.completionTime then
    data.elapsed = mockState.completionTime
  elseif mockState.startTime then
    data.elapsed = (GetTime() - mockState.startTime) + mockState.timeOffset
  else
    data.elapsed = mockState.timeOffset
  end

  data.remaining = data.timeLimit - data.elapsed
  if mockState.runCompleted and mockState.completedOnTime ~= nil then
    data.isOverTime = not mockState.completedOnTime
  else
    data.isOverTime = data.remaining < 0
  end

  local MP         = TTQ.MythicPlus
  local thresholds = MP and MP.CHEST_THRESHOLDS or { 0.6, 0.8, 1.0 }
  local labels     = MP and MP.CHEST_LABELS or { "+3", "+2", "+1" }
  for i, pct in ipairs(thresholds) do
    local limit = data.timeLimit * pct
    local rem = limit - data.elapsed
    data.chestTimers[i] = {
      label     = labels[i],
      limit     = limit,
      remaining = rem,
      active    = rem > 0,
    }
  end

  if mockState.runCompleted and not data.isOverTime then
    for i = 1, #thresholds do
      if data.elapsed <= data.timeLimit * thresholds[i] then
        data.completionChest = 3 - i + 1
        break
      end
    end
    if data.completionChest == 0 then data.completionChest = 1 end
  end

  for i, bossName in ipairs(preset.bosses) do
    local killed = mockState.bossesKilled[i] or false
    data.bosses[#data.bosses + 1] = { name = bossName, completed = killed }
    if killed then data.bossesKilled = data.bossesKilled + 1 end
  end

  data.enemyForces = math.floor((mockState.enemyForcePct / 100) * preset.enemyTotal)
  return data
end

----------------------------------------------------------------------
-- Activate / Deactivate dev mode
----------------------------------------------------------------------
local function ActivateDevMode()
  if TTQ._devModeActive then return end
  TTQ._devModeActive     = true
  origIsMythicPlusActive = TTQ.IsMythicPlusActive
  origGetMythicPlusData  = TTQ.GetMythicPlusData

  TTQ.IsMythicPlusActive = function(self)
    if mockState.active then return true end
    return origIsMythicPlusActive(self)
  end
  TTQ.GetMythicPlusData  = function(self)
    if mockState.active then return BuildMockData() end
    return origGetMythicPlusData(self)
  end
end

local function DeactivateDevMode()
  if not TTQ._devModeActive then return end
  if origIsMythicPlusActive then TTQ.IsMythicPlusActive = origIsMythicPlusActive end
  if origGetMythicPlusData then TTQ.GetMythicPlusData = origGetMythicPlusData end
  TTQ._devModeActive     = false
  origIsMythicPlusActive = nil
  origGetMythicPlusData  = nil
end

----------------------------------------------------------------------
-- Refresh helpers
----------------------------------------------------------------------
local function RefreshTracker()
  if TTQ.SafeRefreshTracker then TTQ:SafeRefreshTracker() end
end

local function StartTimer()
  if TTQ.StartMythicPlusTimer then TTQ:StartMythicPlusTimer() end
end

local function StopTimer()
  if TTQ.StopMythicPlusTimer then TTQ:StopMythicPlusTimer() end
end

----------------------------------------------------------------------
-- Mock action helpers
----------------------------------------------------------------------
local function DoStart()
  ActivateDevMode()
  if mockState.active then
    RefreshTracker()
    return
  end
  ResetMock()
  mockState.active    = true
  mockState.startTime = GetTime()
  StartTimer()
  RefreshTracker()
end

local function DoStop()
  StopTimer()
  ResetMock()
  DeactivateDevMode()
  RefreshTracker()
end

local function DoReset()
  StopTimer()
  local savedPreset = mockState.dungeonPreset
  ResetMock()
  mockState.dungeonPreset = savedPreset
  RefreshTracker()
end

local function DoKillBoss(idx)
  if not mockState.active then return end
  local preset = DUNGEON_PRESETS[mockState.dungeonPreset] or DUNGEON_PRESETS[1]
  if idx and idx >= 1 and idx <= #preset.bosses then
    mockState.bossesKilled[idx] = not mockState.bossesKilled[idx]
  end
  RefreshTracker()
end

local function DoAddDeath()
  if not mockState.active then return end
  mockState.deaths = mockState.deaths + 1
  local name = (UnitName and UnitName("player")) or "Player"
  local _, cls = UnitClass and UnitClass("player")
  mockState.deathLog[#mockState.deathLog + 1] = {
    name    = name,
    class   = cls or "WARRIOR",
    elapsed = mockState.startTime and (GetTime() - mockState.startTime + mockState.timeOffset) or 0,
  }
  RefreshTracker()
end

local function DoRemoveDeath()
  if not mockState.active then return end
  if mockState.deaths > 0 then
    mockState.deaths = mockState.deaths - 1
    if #mockState.deathLog > 0 then table.remove(mockState.deathLog) end
  end
  RefreshTracker()
end

local function DoComplete(onTime)
  if not mockState.active then return end
  local preset = DUNGEON_PRESETS[mockState.dungeonPreset] or DUNGEON_PRESETS[1]
  if onTime then
    local elapsed             = mockState.startTime and (GetTime() - mockState.startTime + mockState.timeOffset) or 0
    mockState.completionTime  = elapsed
    mockState.completedOnTime = elapsed <= preset.timeLimit
  else
    mockState.completionTime  = preset.timeLimit + 45
    mockState.completedOnTime = false
  end
  mockState.runCompleted = true
  for i = 1, #preset.bosses do mockState.bossesKilled[i] = true end
  mockState.enemyForcePct = 100
  StopTimer()
  RefreshTracker()
end

local function DoLoadPreset(name)
  ActivateDevMode()
  ResetMock()
  mockState.active    = true
  mockState.startTime = GetTime()
  local preset        = DUNGEON_PRESETS[mockState.dungeonPreset] or DUNGEON_PRESETS[1]

  if name == "mid" then
    mockState.timeOffset    = 720
    mockState.bossesKilled  = { [1] = true, [2] = true }
    mockState.enemyForcePct = 60
  elseif name == "late" then
    mockState.timeOffset    = preset.timeLimit * 0.85
    mockState.bossesKilled  = { [1] = true, [2] = true, [3] = true }
    mockState.enemyForcePct = 95
    mockState.deaths        = 2
    mockState.deathLog      = {
      { name = "Tank",   class = "WARRIOR", elapsed = 300 },
      { name = "Healer", class = "PRIEST",  elapsed = 600 },
    }
  elseif name == "done" then
    mockState.runCompleted    = true
    mockState.completionTime  = preset.timeLimit * 0.7
    mockState.completedOnTime = true
    mockState.enemyForcePct   = 100
    mockState.deaths          = 1
    mockState.deathLog        = { { name = "DPS", class = "MAGE", elapsed = 450 } }
    for i = 1, #preset.bosses do mockState.bossesKilled[i] = true end
  end

  StartTimer()
  RefreshTracker()
end

----------------------------------------------------------------------
-- UI Helpers
----------------------------------------------------------------------
local function MakeFont(parent, size, color, justify)
  local fs = parent:CreateFontString(nil, "OVERLAY")
  fs:SetFont(S.Font, size, "OUTLINE")
  fs:SetJustifyH(justify or "LEFT")
  if color then fs:SetTextColor(color[1], color[2], color[3], color[4] or 1) end
  fs:SetShadowOffset(1, -1)
  fs:SetShadowColor(0, 0, 0, 0.8)
  return fs
end

local function MakeButton(parent, text, width, color, onClick)
  local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
  btn:SetSize(width, S.BtnH)
  btn:SetBackdrop({
    bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    edgeSize = 8,
    insets   = { left = 2, right = 2, top = 2, bottom = 2 },
  })
  btn:SetBackdropColor(S.BtnBg[1], S.BtnBg[2], S.BtnBg[3], S.BtnBg[4])
  btn:SetBackdropBorderColor(S.Border[1], S.Border[2], S.Border[3], S.Border[4])

  local label = MakeFont(btn, 11, color or S.BtnText, "CENTER")
  label:SetPoint("CENTER")
  label:SetText(text)
  btn._label = label

  btn:SetScript("OnEnter", function(self)
    self:SetBackdropColor(S.BtnHover[1], S.BtnHover[2], S.BtnHover[3], S.BtnHover[4])
  end)
  btn:SetScript("OnLeave", function(self)
    self:SetBackdropColor(S.BtnBg[1], S.BtnBg[2], S.BtnBg[3], S.BtnBg[4])
  end)
  btn:SetScript("OnClick", onClick)
  return btn
end

local function MakeSeparator(parent, yOffset)
  local sep = parent:CreateTexture(nil, "ARTWORK")
  sep:SetHeight(1)
  sep:SetPoint("TOPLEFT", parent, "TOPLEFT", S.Pad, -yOffset)
  sep:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -S.Pad, -yOffset)
  sep:SetColorTexture(S.Border[1], S.Border[2], S.Border[3], 0.4)
  return sep
end

local function MakeSectionLabel(parent, text, yOffset)
  local lbl = MakeFont(parent, 10, S.Section, "LEFT")
  lbl:SetPoint("TOPLEFT", parent, "TOPLEFT", S.Pad, -yOffset)
  lbl:SetText(text:upper())
  return lbl
end

----------------------------------------------------------------------
-- Compact slider:  [Label]  [===o===]  [value]
----------------------------------------------------------------------
local function MakeSlider(parent, labelText, yOffset, minVal, maxVal, step, getValue, setValue)
  local TRACK_W    = 120
  local TRACK_H    = 6
  local THUMB_SIZE = 12
  local INSET      = 2

  local row        = CreateFrame("Frame", nil, parent)
  row:SetHeight(S.RowH)
  row:SetPoint("TOPLEFT", parent, "TOPLEFT", S.Pad, -yOffset)
  row:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -S.Pad, -yOffset)

  local label = MakeFont(row, 11, S.Label, "LEFT")
  label:SetPoint("LEFT", row, "LEFT", 0, 0)
  label:SetText(labelText)

  local valText = MakeFont(row, 11, S.Value, "RIGHT")
  valText:SetPoint("RIGHT", row, "RIGHT", 0, 0)
  valText:SetWidth(40)

  local track = CreateFrame("Frame", nil, row)
  track:SetSize(TRACK_W, TRACK_H)
  track:SetPoint("RIGHT", valText, "LEFT", -6, 0)

  local bg = track:CreateTexture(nil, "BACKGROUND")
  bg:SetPoint("TOPLEFT", INSET, -INSET)
  bg:SetPoint("BOTTOMRIGHT", -INSET, INSET)
  bg:SetColorTexture(S.TrackBg[1], S.TrackBg[2], S.TrackBg[3], S.TrackBg[4])

  local fill = track:CreateTexture(nil, "ARTWORK")
  fill:SetPoint("TOPLEFT", INSET, -INSET)
  fill:SetPoint("BOTTOMLEFT", INSET, INSET)
  fill:SetColorTexture(S.TrackFill[1], S.TrackFill[2], S.TrackFill[3], S.TrackFill[4])

  local thumb = CreateFrame("Button", nil, track)
  thumb:SetSize(THUMB_SIZE, THUMB_SIZE)
  local thumbTex = thumb:CreateTexture(nil, "OVERLAY")
  thumbTex:SetAllPoints()
  thumbTex:SetColorTexture(S.Thumb[1], S.Thumb[2], S.Thumb[3], S.Thumb[4])

  local fillW     = TRACK_W - 2 * INSET
  local thumbTrav = fillW - THUMB_SIZE

  local function snap(v)
    if step and step > 0 then v = math.floor(v / step + 0.5) * step end
    return math.max(minVal, math.min(maxVal, v))
  end
  local function fmtVal(v)
    if step and step < 1 then return string.format("%.1f", v) end
    return tostring(math.floor(v + 0.5))
  end
  local function norm(v) return (maxVal > minVal) and ((v - minVal) / (maxVal - minVal)) or 0 end

  local function updateVisual(v)
    v = snap(v)
    local n = norm(v)
    thumb:ClearAllPoints()
    thumb:SetPoint("CENTER", track, "LEFT", INSET + THUMB_SIZE / 2 + n * thumbTrav, 0)
    fill:SetWidth(math.max(0.01, n * fillW))
    valText:SetText(fmtVal(v))
  end

  thumb:SetScript("OnMouseDown", function(_, mbtn)
    if mbtn ~= "LeftButton" then return end
    local startN = norm(getValue())
    local scale  = track:GetEffectiveScale()
    local startX = GetCursorPosition() / scale
    track:SetScript("OnUpdate", function()
      if not IsMouseButtonDown("LeftButton") then
        track:SetScript("OnUpdate", nil)
        return
      end
      local x     = GetCursorPosition() / scale
      local delta = (x - startX) / fillW
      local n2    = math.max(0, math.min(1, startN + delta))
      local v     = snap(minVal + n2 * (maxVal - minVal))
      setValue(v)
      updateVisual(v)
      startN = n2
      startX = x
    end)
  end)

  -- Click track to jump
  local trackBtn = CreateFrame("Button", nil, track)
  trackBtn:SetAllPoints()
  trackBtn:SetFrameLevel(track:GetFrameLevel())
  trackBtn:SetScript("OnClick", function()
    local scale = track:GetEffectiveScale()
    local cx    = GetCursorPosition() / scale
    local left  = track:GetLeft()
    if not left then return end
    local rel = math.max(0, math.min(1, (cx - left - INSET) / fillW))
    local v   = snap(minVal + rel * (maxVal - minVal))
    setValue(v)
    updateVisual(v)
  end)

  function row:Refresh() updateVisual(getValue()) end

  row:Refresh()
  row._valText = valText
  return row
end

----------------------------------------------------------------------
-- Dev Panel (created lazily)
----------------------------------------------------------------------
local devPanel      = nil
local panelElements = {}

local function GetCurrentPreset()
  return DUNGEON_PRESETS[mockState.dungeonPreset] or DUNGEON_PRESETS[1]
end

-- Forward declaration
local RefreshPanel

----------------------------------------------------------------------
-- Build the panel
----------------------------------------------------------------------
local function CreateDevPanel()
  if devPanel then return devPanel end

  local f = CreateFrame("Frame", "TTQDevPanel", UIParent, "BackdropTemplate")
  f:SetSize(S.PanelW, 600)   -- height set at the end
  f:SetPoint("LEFT", UIParent, "LEFT", 20, 0)
  f:SetFrameStrata("DIALOG")
  f:SetFrameLevel(100)
  f:SetMovable(true)
  f:EnableMouse(true)
  f:SetClampedToScreen(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", f.StopMovingOrSizing)

  f:SetBackdrop({
    bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    edgeSize = 12,
    insets   = { left = 3, right = 3, top = 3, bottom = 3 },
  })
  f:SetBackdropColor(S.Bg[1], S.Bg[2], S.Bg[3], S.Bg[4])
  f:SetBackdropBorderColor(S.Border[1], S.Border[2], S.Border[3], S.Border[4])

  -- Escape key closes the panel
  table.insert(UISpecialFrames, "TTQDevPanel")

  local y = S.Pad
  local contentW = S.PanelW - 2 * S.Pad

  ----------------------------------------------------------------
  -- Title bar
  ----------------------------------------------------------------
  local title = MakeFont(f, 13, S.Value, "LEFT")
  title:SetPoint("TOPLEFT", f, "TOPLEFT", S.Pad, -y)
  title:SetText("M+ Dev Panel")

  local status = MakeFont(f, 10, S.Inactive, "RIGHT")
  status:SetPoint("TOPRIGHT", f, "TOPRIGHT", -S.Pad - 22, -y - 2)
  panelElements.statusBadge = status

  local closeBtn = CreateFrame("Button", nil, f)
  closeBtn:SetSize(16, 16)
  closeBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -S.Pad + 2, -y + 2)
  local closeTex = closeBtn:CreateTexture(nil, "ARTWORK")
  closeTex:SetAllPoints()
  closeTex:SetColorTexture(0.8, 0.25, 0.25, 0.8)
  local closeHL = closeBtn:CreateTexture(nil, "HIGHLIGHT")
  closeHL:SetAllPoints()
  closeHL:SetColorTexture(1, 0.4, 0.4, 0.4)
  closeBtn:SetScript("OnClick", function() f:Hide() end)

  y = y + 24

  ----------------------------------------------------------------
  -- Section: Run Controls
  ----------------------------------------------------------------
  MakeSeparator(f, y); y = y + 8
  MakeSectionLabel(f, "Run Controls", y); y = y + 18

  local startBtn = MakeButton(f, "Start Run", 80, S.BtnSuccess, function()
    if mockState.active then DoStop() else DoStart() end
    RefreshPanel()
  end)
  startBtn:SetPoint("TOPLEFT", f, "TOPLEFT", S.Pad, -y)
  panelElements.startStopBtn = startBtn

  local resetBtn = MakeButton(f, "Reset", 55, S.BtnWarn, function()
    DoReset(); RefreshPanel()
  end)
  resetBtn:SetPoint("LEFT", startBtn, "RIGHT", 4, 0)

  local completeBtn = MakeButton(f, "Complete", 65, S.BtnSuccess, function()
    DoComplete(true); RefreshPanel()
  end)
  completeBtn:SetPoint("LEFT", resetBtn, "RIGHT", 4, 0)

  local overtimeBtn = MakeButton(f, "Overtime", 65, S.BtnDanger, function()
    DoComplete(false); RefreshPanel()
  end)
  overtimeBtn:SetPoint("LEFT", completeBtn, "RIGHT", 4, 0)

  y = y + S.BtnH + 8

  ----------------------------------------------------------------
  -- Section: Dungeon
  ----------------------------------------------------------------
  MakeSeparator(f, y); y = y + 8
  MakeSectionLabel(f, "Dungeon", y); y = y + 18

  panelElements.dungeonButtons = {}
  local dungBtnW = math.floor((contentW - (#DUNGEON_PRESETS - 1) * 4) / #DUNGEON_PRESETS)
  for i, preset in ipairs(DUNGEON_PRESETS) do
    local btn = MakeButton(f, preset.name, dungBtnW, nil, function()
      mockState.dungeonPreset = i
      if mockState.active then
        local saved = {
          level  = mockState.keystoneLevel,
          deaths = mockState.deaths,
          trash  = mockState.enemyForcePct,
          bosses = {},
        }
        for idx, v in pairs(mockState.bossesKilled) do saved.bosses[idx] = v end
        DoStart()
        mockState.keystoneLevel = saved.level
        mockState.deaths        = saved.deaths
        mockState.enemyForcePct = saved.trash
        mockState.bossesKilled  = saved.bosses
        RefreshTracker()
      end
      RefreshPanel()
    end)
    btn._label:SetFont(S.Font, 9, "OUTLINE")
    if i == 1 then
      btn:SetPoint("TOPLEFT", f, "TOPLEFT", S.Pad, -y)
    else
      btn:SetPoint("LEFT", panelElements.dungeonButtons[i - 1], "RIGHT", 4, 0)
    end
    panelElements.dungeonButtons[i] = btn
  end
  y = y + S.BtnH + 8

  ----------------------------------------------------------------
  -- Section: Keystone Level
  ----------------------------------------------------------------
  MakeSeparator(f, y); y = y + 8
  MakeSectionLabel(f, "Keystone", y); y = y + 18

  local keySlider = MakeSlider(f, "Key Level", y, 2, 35, 1,
    function() return mockState.keystoneLevel end,
    function(v)
      mockState.keystoneLevel = v; RefreshTracker()
    end)
  panelElements.keySlider = keySlider
  y = y + S.RowH + 8

  ----------------------------------------------------------------
  -- Section: Timer
  ----------------------------------------------------------------
  MakeSeparator(f, y); y = y + 8
  MakeSectionLabel(f, "Timer", y); y = y + 18

  local timerSlider = MakeSlider(f, "Elapsed (sec)", y, 0, 2400, 15,
    function()
      if mockState.startTime then
        return math.floor((GetTime() - mockState.startTime) + mockState.timeOffset)
      end
      return mockState.timeOffset
    end,
    function(v)
      mockState.startTime  = GetTime()
      mockState.timeOffset = v
    end)
  panelElements.timerSlider = timerSlider
  y = y + S.RowH + 4

  -- Quick time jump buttons
  local timeJumps = { { "5m", 300 }, { "15m", 900 }, { "25m", 1500 }, { "30m", 1800 }, { "35m", 2100 } }
  local tjW = math.floor((contentW - (#timeJumps - 1) * 4) / #timeJumps)
  local tjPrevBtn
  for i, tj in ipairs(timeJumps) do
    local btn = MakeButton(f, tj[1], tjW, S.Active, function()
      mockState.startTime  = GetTime()
      mockState.timeOffset = tj[2]
      RefreshPanel()
    end)
    if i == 1 then
      btn:SetPoint("TOPLEFT", f, "TOPLEFT", S.Pad, -y)
    else
      btn:SetPoint("LEFT", tjPrevBtn, "RIGHT", 4, 0)
    end
    tjPrevBtn = btn
  end
  y = y + S.BtnH + 8

  ----------------------------------------------------------------
  -- Section: Enemy Forces
  ----------------------------------------------------------------
  MakeSeparator(f, y); y = y + 8
  MakeSectionLabel(f, "Enemy Forces", y); y = y + 18

  local trashSlider = MakeSlider(f, "Forces %", y, 0, 100, 1,
    function() return mockState.enemyForcePct end,
    function(v)
      mockState.enemyForcePct = v; RefreshTracker()
    end)
  panelElements.trashSlider = trashSlider
  y = y + S.RowH + 4

  local trashJumps = { { "0%", 0 }, { "25%", 25 }, { "50%", 50 }, { "75%", 75 }, { "100%", 100 } }
  local trW = math.floor((contentW - (#trashJumps - 1) * 4) / #trashJumps)
  local trPrevBtn
  for i, tj in ipairs(trashJumps) do
    local btn = MakeButton(f, tj[1], trW, S.Active, function()
      mockState.enemyForcePct = tj[2]
      RefreshTracker(); RefreshPanel()
    end)
    if i == 1 then
      btn:SetPoint("TOPLEFT", f, "TOPLEFT", S.Pad, -y)
    else
      btn:SetPoint("LEFT", trPrevBtn, "RIGHT", 4, 0)
    end
    trPrevBtn = btn
  end
  y = y + S.BtnH + 8

  ----------------------------------------------------------------
  -- Section: Deaths
  ----------------------------------------------------------------
  MakeSeparator(f, y); y = y + 8
  MakeSectionLabel(f, "Deaths", y); y = y + 18

  local deathLabel = MakeFont(f, 11, S.Label, "LEFT")
  deathLabel:SetPoint("TOPLEFT", f, "TOPLEFT", S.Pad, -y)
  deathLabel:SetText("Count:")

  local deathCount = MakeFont(f, 13, S.Value, "LEFT")
  deathCount:SetPoint("LEFT", deathLabel, "RIGHT", 6, 0)
  deathCount:SetText("0")

  local deathMinus = MakeButton(f, "-", 36, S.BtnDanger, function()
    DoRemoveDeath(); deathCount:SetText(tostring(mockState.deaths))
  end)
  deathMinus:SetPoint("TOPRIGHT", f, "TOPRIGHT", -S.Pad - 40, -y + 2)

  local deathPlus = MakeButton(f, "+", 36, S.BtnSuccess, function()
    DoAddDeath(); deathCount:SetText(tostring(mockState.deaths))
  end)
  deathPlus:SetPoint("LEFT", deathMinus, "RIGHT", 4, 0)

  panelElements.deathCount = { Refresh = function() deathCount:SetText(tostring(mockState.deaths)) end }
  y = y + S.RowH + 8

  ----------------------------------------------------------------
  -- Section: Bosses
  ----------------------------------------------------------------
  MakeSeparator(f, y); y = y + 8
  MakeSectionLabel(f, "Bosses  (click to toggle kill)", y); y = y + 18

  panelElements.bossButtons = {}
  for i = 1, 6 do
    local btn = MakeButton(f, "Boss " .. i, contentW, nil, function()
      DoKillBoss(i); RefreshPanel()
    end)
    btn:SetPoint("TOPLEFT", f, "TOPLEFT", S.Pad, -y)
    btn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -S.Pad, -y)
    btn:SetHeight(22)
    btn._label:SetJustifyH("LEFT")
    btn._label:ClearAllPoints()
    btn._label:SetPoint("LEFT", btn, "LEFT", 8, 0)

    -- Status indicator on right
    local statusTxt = MakeFont(btn, 10, S.BossAlive, "RIGHT")
    statusTxt:SetPoint("RIGHT", btn, "RIGHT", -8, 0)
    btn._statusTxt = statusTxt

    panelElements.bossButtons[i] = btn
    y = y + 24
    if i > 4 then btn:Hide() end
  end
  y = y + 4

  ----------------------------------------------------------------
  -- Section: Quick Presets
  ----------------------------------------------------------------
  MakeSeparator(f, y); y = y + 8
  MakeSectionLabel(f, "Quick Presets", y); y = y + 18

  local presets = {
    { "Mid-Run",   "mid",  "2 bosses, 60% trash, 12:00" },
    { "Late Run",  "late", "3 bosses, 95% trash, tight timer" },
    { "Completed", "done", "+2 timed, 1 death, all done" },
  }
  local pW = math.floor((contentW - (#presets - 1) * 4) / #presets)
  local pPrevBtn
  for i, p in ipairs(presets) do
    local btn = MakeButton(f, p[1], pW, S.Active, function()
      DoLoadPreset(p[2]); RefreshPanel()
    end)
    if i == 1 then
      btn:SetPoint("TOPLEFT", f, "TOPLEFT", S.Pad, -y)
    else
      btn:SetPoint("LEFT", pPrevBtn, "RIGHT", 4, 0)
    end
    btn:SetScript("OnEnter", function(self)
      self:SetBackdropColor(S.BtnHover[1], S.BtnHover[2], S.BtnHover[3], S.BtnHover[4])
      GameTooltip:SetOwner(self, "ANCHOR_TOP")
      GameTooltip:SetText(p[1], S.Value[1], S.Value[2], S.Value[3])
      GameTooltip:AddLine(p[3], 0.8, 0.8, 0.8)
      GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function(self)
      self:SetBackdropColor(S.BtnBg[1], S.BtnBg[2], S.BtnBg[3], S.BtnBg[4])
      GameTooltip:Hide()
    end)
    pPrevBtn = btn
  end
  y = y + S.BtnH + S.Pad

  ----------------------------------------------------------------
  -- Finalize
  ----------------------------------------------------------------
  f:SetHeight(y)

  -- Periodic refresh while panel is visible
  f:SetScript("OnUpdate", function(self, elapsed)
    self._elapsed = (self._elapsed or 0) + elapsed
    if self._elapsed >= 0.5 then
      self._elapsed = 0
      RefreshPanel()
    end
  end)

  devPanel = f
  return f
end

----------------------------------------------------------------------
-- Refresh all panel widgets to match current mockState
----------------------------------------------------------------------
RefreshPanel = function()
  if not devPanel or not devPanel:IsShown() then return end

  -- Sliders
  for _, key in ipairs({ "keySlider", "timerSlider", "trashSlider", "deathCount" }) do
    local el = panelElements[key]
    if el and el.Refresh then el:Refresh() end
  end

  -- Status badge
  if panelElements.statusBadge then
    if mockState.active then
      if mockState.runCompleted then
        local onTime = mockState.completedOnTime
        panelElements.statusBadge:SetText(onTime and "COMPLETED" or "OVER TIME")
        local c = onTime and S.BtnSuccess or S.BtnDanger
        panelElements.statusBadge:SetTextColor(c[1], c[2], c[3])
      else
        panelElements.statusBadge:SetText("RUNNING")
        panelElements.statusBadge:SetTextColor(S.BtnSuccess[1], S.BtnSuccess[2], S.BtnSuccess[3])
      end
    else
      panelElements.statusBadge:SetText("STOPPED")
      panelElements.statusBadge:SetTextColor(S.Inactive[1], S.Inactive[2], S.Inactive[3])
    end
  end

  -- Start/Stop button
  if panelElements.startStopBtn then
    if mockState.active then
      panelElements.startStopBtn._label:SetText("Stop")
      panelElements.startStopBtn._label:SetTextColor(S.BtnDanger[1], S.BtnDanger[2], S.BtnDanger[3])
    else
      panelElements.startStopBtn._label:SetText("Start Run")
      panelElements.startStopBtn._label:SetTextColor(S.BtnSuccess[1], S.BtnSuccess[2], S.BtnSuccess[3])
    end
  end

  -- Dungeon selector highlights
  if panelElements.dungeonButtons then
    for i, btn in ipairs(panelElements.dungeonButtons) do
      if i == mockState.dungeonPreset then
        btn:SetBackdropColor(S.Active[1], S.Active[2], S.Active[3], 0.3)
        btn._label:SetTextColor(S.Value[1], S.Value[2], S.Value[3])
      else
        btn:SetBackdropColor(S.BtnBg[1], S.BtnBg[2], S.BtnBg[3], S.BtnBg[4])
        btn._label:SetTextColor(S.BtnText[1], S.BtnText[2], S.BtnText[3])
      end
    end
  end

  -- Boss buttons
  if panelElements.bossButtons then
    local preset = GetCurrentPreset()
    for i, btn in ipairs(panelElements.bossButtons) do
      if i <= #preset.bosses then
        btn._label:SetText(preset.bosses[i])
        if mockState.bossesKilled[i] then
          btn:SetBackdropColor(S.BossDead[1], S.BossDead[2], S.BossDead[3], 0.15)
          btn._label:SetTextColor(S.BossDead[1], S.BossDead[2], S.BossDead[3])
          if btn._statusTxt then
            btn._statusTxt:SetText("KILLED")
            btn._statusTxt:SetTextColor(S.BossDead[1], S.BossDead[2], S.BossDead[3])
          end
        else
          btn:SetBackdropColor(S.BtnBg[1], S.BtnBg[2], S.BtnBg[3], S.BtnBg[4])
          btn._label:SetTextColor(S.BossAlive[1], S.BossAlive[2], S.BossAlive[3])
          if btn._statusTxt then
            btn._statusTxt:SetText("ALIVE")
            btn._statusTxt:SetTextColor(S.Inactive[1], S.Inactive[2], S.Inactive[3])
          end
        end
        btn:Show()
      else
        btn:Hide()
      end
    end
  end
end

----------------------------------------------------------------------
-- Toggle
----------------------------------------------------------------------
local function ToggleDevPanel()
  local panel = CreateDevPanel()
  if panel:IsShown() then
    panel:Hide()
  else
    RefreshPanel()
    panel:Show()
  end
end

----------------------------------------------------------------------
-- Slash command: /ttdev  (opens panel)
----------------------------------------------------------------------
SLASH_TTDEV1 = "/ttdev"
SlashCmdList["TTDEV"] = function(msg)
  msg = strtrim(msg or ""):lower()
  if msg == "stop" then
    DoStop()
  elseif msg == "start" then
    DoStart()
    ToggleDevPanel()
  else
    ToggleDevPanel()
  end
end
