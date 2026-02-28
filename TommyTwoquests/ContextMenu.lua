----------------------------------------------------------------------
-- TommyTwoquests -- ContextMenu.lua
-- Generic reusable context menu: backdrop, buttons, cursor positioning
----------------------------------------------------------------------
local AddonName, TTQ          = ...
local CreateFrame, UIParent   = CreateFrame, UIParent
local GetCursorPosition, math = GetCursorPosition, math

local MENU_ROW                = 22
local MENU_PAD                = 6
local MENU_WIDTH              = 200

----------------------------------------------------------------------
-- Create a reusable context menu with dynamic button support
-- Returns a menu object with :Show(config) and :Hide() methods
--
-- config = {
--   title   = "Quest Name",
--   buttons = {
--     { label, tooltip, onClick, disabled, color = {r,g,b} },
--     ...
--   },
-- }
----------------------------------------------------------------------
function TTQ:CreateContextMenu(globalName)
  local menu = {}

  local frame = CreateFrame("Frame", globalName, UIParent, "BackdropTemplate")
  frame:SetWidth(MENU_WIDTH + MENU_PAD * 2)
  frame:SetClampedToScreen(true)
  frame:SetFrameStrata("TOOLTIP")
  frame:SetFrameLevel(100)
  frame:SetBackdrop({
    bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile     = true,
    tileSize = 16,
    edgeSize = 14,
    insets   = { left = 4, right = 4, top = 4, bottom = 4 },
  })
  frame:SetBackdropColor(0.06, 0.06, 0.08, 0.96)
  frame:SetBackdropBorderColor(0.25, 0.28, 0.35, 0.7)
  frame:Hide()
  menu.frame = frame

  -- Click-away catcher
  local catcher = CreateFrame("Button", nil, UIParent)
  catcher:SetFrameStrata("TOOLTIP")
  catcher:SetFrameLevel(99)
  catcher:SetAllPoints(UIParent)
  catcher:EnableMouse(true)
  catcher:RegisterForClicks("AnyUp")
  catcher:Hide()
  catcher:SetScript("OnClick", function()
    menu:Hide()
  end)
  frame.clickCatcher = catcher

  frame:SetScript("OnHide", function()
    if catcher:IsShown() then catcher:Hide() end
  end)

  local content = CreateFrame("Frame", nil, frame)
  content:SetPoint("TOPLEFT", frame, "TOPLEFT", MENU_PAD, -MENU_PAD)
  content:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -MENU_PAD, MENU_PAD)
  content:SetFrameLevel(frame:GetFrameLevel() + 1)
  menu.content = content

  -- Title
  local title = TTQ:CreateText(content, 13, { r = 1, g = 0.82, b = 0 }, "LEFT")
  title:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
  title:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, 0)
  title:SetWordWrap(true)
  title:SetNonSpaceWrap(false)
  menu.title = title

  -- Dynamic button pool
  local buttons = {}

  local function ensureButton(index)
    if buttons[index] then return buttons[index] end
    local btn = CreateFrame("Button", nil, content)
    btn:SetHeight(MENU_ROW)
    btn:SetWidth(MENU_WIDTH)
    btn:SetFrameLevel(content:GetFrameLevel() + 1)
    local hl = btn:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.06)
    local text = TTQ:CreateText(btn, 12, { r = 0.9, g = 0.9, b = 0.9 }, "LEFT")
    text:SetPoint("LEFT", btn, "LEFT", 4, 0)
    btn.label = text
    btn:SetScript("OnClick", function()
      if btn._disabled then
        menu:Hide(); return
      end
      if btn._onClick then btn._onClick() end
      menu:Hide()
    end)
    buttons[index] = btn
    return btn
  end

  function menu:Show(config)
    if not config then return end
    self.title:SetText(config.title or "")
    self.title:SetHeight(math.max(20, self.title:GetStringHeight() + 4))

    local titleH = math.max(24, self.title:GetStringHeight() + 8)
    local y = titleH + 2

    local btnList = config.buttons or {}
    for i, btnConfig in ipairs(btnList) do
      local btn = ensureButton(i)
      btn.label:SetText(btnConfig.label or "")
      btn._onClick = btnConfig.onClick
      btn._tooltip = btnConfig.tooltip
      btn._disabled = btnConfig.disabled

      local c = btnConfig.color or { r = 0.9, g = 0.9, b = 0.9 }
      if btnConfig.disabled then
        btn.label:SetTextColor(0.45, 0.45, 0.45)
      else
        btn.label:SetTextColor(c.r or 0.9, c.g or 0.9, c.b or 0.9)
      end

      btn:ClearAllPoints()
      btn:SetPoint("TOPLEFT", self.content, "TOPLEFT", 0, -y)
      btn:Show()
      y = y + MENU_ROW
    end

    -- Hide excess buttons
    for i = #btnList + 1, #buttons do
      buttons[i]:Hide()
    end

    self.frame:SetHeight(y + MENU_PAD * 2 + 4)
    self.frame:ClearAllPoints()
    local cursorX, cursorY = GetCursorPosition()
    local scale = UIParent:GetEffectiveScale()
    self.frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", cursorX / scale, cursorY / scale)
    self.frame:Show()
    self.frame.clickCatcher:Show()
  end

  function menu:Hide()
    self.frame:Hide()
    if self.frame.clickCatcher:IsShown() then
      self.frame.clickCatcher:Hide()
    end
  end

  return menu
end
