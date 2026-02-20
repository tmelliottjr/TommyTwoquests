----------------------------------------------------------------------
-- TommyTwoquests — RecipeTracker.lua
-- Tracked profession recipes: data, display, Auctionator integration
-- Mirrors Kaliel's Tracker approach to recipe + AH search support.
----------------------------------------------------------------------
local AddonName, TTQ = ...
local table, ipairs, pairs, pcall, math, string, wipe, type =
    table, ipairs, pairs, pcall, math, string, wipe, type
local CreateFrame, UIParent, C_Timer, GetTime, GameTooltip =
    CreateFrame, UIParent, C_Timer, GetTime, GameTooltip
local C_TradeSkillUI = C_TradeSkillUI
local GetItemCount = GetItemCount
local C_Item = C_Item

----------------------------------------------------------------------
-- Recipe row object pool
----------------------------------------------------------------------
local RECIPE_ITEM_POOL = {}
local REAGENT_ITEM_POOL = {}

----------------------------------------------------------------------
-- Acquire / release recipe rows
----------------------------------------------------------------------
function TTQ:AcquireRecipeItem(parent)
  local item = table.remove(RECIPE_ITEM_POOL)
  if not item then
    item = self:CreateRecipeItem(parent)
  end
  item.frame:SetParent(parent)
  item.frame:Show()
  item.reagentItems = item.reagentItems or {}
  return item
end

function TTQ:ReleaseRecipeItem(item)
  if item.reagentItems then
    for _, ri in ipairs(item.reagentItems) do
      self:ReleaseReagentItem(ri)
    end
    wipe(item.reagentItems)
  end
  item.frame:Hide()
  item.frame:ClearAllPoints()
  item.frame:SetScript("OnUpdate", nil)
  table.insert(RECIPE_ITEM_POOL, item)
end

----------------------------------------------------------------------
-- Acquire / release reagent rows
----------------------------------------------------------------------
function TTQ:AcquireReagentItem(parent)
  local item = table.remove(REAGENT_ITEM_POOL)
  if not item then
    item = self:CreateReagentItem(parent)
  end
  item.frame:SetParent(parent)
  item.frame:Show()
  return item
end

function TTQ:ReleaseReagentItem(item)
  item.frame:Hide()
  item.frame:ClearAllPoints()
  item.frame:SetAlpha(1)
  table.insert(REAGENT_ITEM_POOL, item)
end

----------------------------------------------------------------------
-- Build a recipe row frame (similar to QuestItem)
----------------------------------------------------------------------
local RECIPE_NAME_ROW_HEIGHT = 20
local RECIPE_ICON_WIDTH = 14

function TTQ:CreateRecipeItem(parent)
  local item = {}
  item.reagentItems = {}

  local frame = CreateFrame("Button", nil, parent)
  frame:SetHeight(RECIPE_NAME_ROW_HEIGHT)
  frame:EnableMouse(true)
  frame:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  item.frame = frame

  -- Recipe icon
  local icon = frame:CreateTexture(nil, "ARTWORK")
  icon:SetSize(14, 14)
  icon:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -3)
  item.icon = icon

  -- Recipe name text
  local nameSize = TTQ:GetSetting("questNameFontSize")
  local nameColor = TTQ:GetSetting("questNameColor")
  local name = TTQ:CreateText(frame, nameSize, nameColor, "LEFT")
  name:SetPoint("TOPLEFT", frame, "TOPLEFT", RECIPE_ICON_WIDTH + 4, 0)
  name:SetPoint("RIGHT", frame, "RIGHT", -4, 0)
  name:SetHeight(RECIPE_NAME_ROW_HEIGHT)
  name:SetWordWrap(false)
  name:SetNonSpaceWrap(false)
  name:SetMaxLines(1)
  item.name = name

  -- Collapse indicator
  local expandInd = TTQ:CreateText(frame, 12, { r = 0.5, g = 0.5, b = 0.5 }, "CENTER")
  expandInd:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
  expandInd:SetSize(RECIPE_ICON_WIDTH, RECIPE_NAME_ROW_HEIGHT)
  expandInd:SetText("+")
  expandInd:Hide()
  item.expandInd = expandInd

  -- Click handler: left = collapse/expand; right = context menu
  frame:SetScript("OnClick", function(self, button)
    local recipeData = item.recipeData
    if not recipeData then return end

    if button == "LeftButton" then
      -- Toggle collapse
      local cq = TTQ:GetSetting("collapsedRecipes") or {}
      cq = TTQ:DeepCopy(cq)
      local key = "recipe_" .. recipeData.recipeID
      cq[key] = not cq[key] and true or nil
      TTQ:SetSetting("collapsedRecipes", cq)
      TTQ:RefreshTracker()
    elseif button == "RightButton" then
      TTQ:ShowRecipeContextMenu(item)
    end
  end)

  -- Hover: tooltip
  frame:SetScript("OnEnter", function(self)
    local recipeData = item.recipeData
    if not recipeData then return end
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:SetText(recipeData.name, 1, 1, 1)
    if recipeData.professionName and recipeData.professionName ~= "" then
      GameTooltip:AddLine(recipeData.professionName, 0.6, 0.6, 0.8)
    end
    -- Show reagent summary
    if recipeData.reagents and #recipeData.reagents > 0 then
      GameTooltip:AddLine(" ")
      GameTooltip:AddLine("Reagents:", 0.8, 0.8, 0.8)
      for _, reagent in ipairs(recipeData.reagents) do
        local r, g, b = 0.85, 0.85, 0.85
        if reagent.have >= reagent.needed then
          r, g, b = 0.2, 0.8, 0.4
        end
        GameTooltip:AddLine(
          string.format("  %s (%d/%d)", reagent.name, reagent.have, reagent.needed),
          r, g, b
        )
      end
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Click: Collapse/Expand", 0.5, 0.8, 1)
    GameTooltip:AddLine("Right-click: Menu", 0.5, 0.8, 1)
    GameTooltip:Show()
  end)
  frame:SetScript("OnLeave", function() GameTooltip:Hide() end)

  return item
end

----------------------------------------------------------------------
-- Build a reagent row frame (similar to ObjectiveItem)
----------------------------------------------------------------------
local REAGENT_ROW_HEIGHT = 16

function TTQ:CreateReagentItem(parent)
  local item = {}

  local frame = CreateFrame("Button", nil, parent)
  frame:SetHeight(REAGENT_ROW_HEIGHT)
  frame:EnableMouse(true)
  frame:RegisterForClicks("LeftButtonUp")
  item.frame = frame

  -- Click: search Auctionator for this reagent
  frame:SetScript("OnClick", function()
    if item.reagentData then
      TTQ:SearchAuctionator({ item.reagentData })
    end
  end)

  -- Dash / bullet
  local dash = TTQ:CreateText(frame, TTQ:GetSetting("objectiveFontSize"),
    TTQ:GetSetting("objectiveIncompleteColor"), "LEFT")
  dash:SetPoint("LEFT", frame, "LEFT", 0, 0)
  dash:SetText("-")
  dash:SetWidth(10)
  item.dash = dash

  -- Checkmark icon (shown when reagent requirement is met)
  local checkIcon = frame:CreateTexture(nil, "ARTWORK")
  checkIcon:SetSize(10, 10)
  checkIcon:SetPoint("LEFT", frame, "LEFT", 0, 0)
  checkIcon:SetTexture("Interface\\AddOns\\TommyTwoquests\\Textures\\checkmark")
  checkIcon:Hide()
  item.checkIcon = checkIcon

  -- Reagent text
  local text = TTQ:CreateText(frame, TTQ:GetSetting("objectiveFontSize"),
    TTQ:GetSetting("objectiveIncompleteColor"), "LEFT")
  text:SetPoint("LEFT", dash, "RIGHT", 2, 0)
  text:SetPoint("RIGHT", frame, "RIGHT", 0, 0)
  text:SetWordWrap(false)
  text:SetNonSpaceWrap(false)
  text:SetMaxLines(1)
  item.text = text

  -- Tooltip for reagent
  frame:SetScript("OnEnter", function(self)
    if not item.reagentData then return end
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:SetText(item.reagentData.name, 1, 1, 1)
    GameTooltip:AddLine(
      string.format("Have: %d / Need: %d", item.reagentData.have, item.reagentData.needed),
      0.8, 0.8, 0.8
    )
    if TTQ:IsAuctionatorAvailable() then
      GameTooltip:AddLine("Click: Search Auction House", 0.5, 0.8, 1)
    end
    GameTooltip:Show()
  end)
  frame:SetScript("OnLeave", function() GameTooltip:Hide() end)

  return item
end

----------------------------------------------------------------------
-- Update recipe item with data
----------------------------------------------------------------------
function TTQ:UpdateRecipeItem(item, recipe, parentWidth)
  item.recipeData = recipe

  -- Check if collapsed
  local cr = self:GetSetting("collapsedRecipes") or {}
  local key = "recipe_" .. recipe.recipeID
  local isCollapsed = cr[key] and true or false

  -- Font
  local nameSize = self:GetSetting("questNameFontSize")
  local nameFont = self:GetResolvedFont("quest")
  local nameOutline = self:GetSetting("questNameFontOutline")
  if not pcall(item.name.SetFont, item.name, nameFont, nameSize, nameOutline) then
    pcall(item.name.SetFont, item.name, "Fonts\\FRIZQT__.TTF", nameSize, nameOutline)
  end

  -- Icon
  if recipe.icon and self:GetSetting("showIcons") then
    item.icon:SetTexture(recipe.icon)
    item.icon:SetSize(14, 14)
    item.icon:Show()
    item.name:ClearAllPoints()
    item.name:SetPoint("TOPLEFT", item.frame, "TOPLEFT", RECIPE_ICON_WIDTH + 4, 0)
    item.name:SetPoint("RIGHT", item.frame, "RIGHT", -4, 0)
  else
    item.icon:Hide()
    item.name:ClearAllPoints()
    item.name:SetPoint("TOPLEFT", item.frame, "TOPLEFT", RECIPE_ICON_WIDTH + 2, 0)
    item.name:SetPoint("RIGHT", item.frame, "RIGHT", -4, 0)
  end

  -- Collapse indicator
  if isCollapsed then
    item.expandInd:Show()
    item.icon:SetAlpha(0)
    local nc = self:GetSetting("questNameColor")
    item.expandInd:SetTextColor(nc.r, nc.g, nc.b, 1)
  else
    item.expandInd:Hide()
    item.icon:SetAlpha(1)
  end

  -- Name
  item.name:SetText(recipe.name or "Unknown Recipe")

  -- Color: show as complete color if all reagents are satisfied
  local allReady = recipe.allReagentsReady
  if allReady then
    local ec = self:GetSetting("objectiveCompleteColor")
    item.name:SetTextColor(ec.r, ec.g, ec.b)
  else
    local nc = self:GetSetting("questNameColor")
    item.name:SetTextColor(nc.r, nc.g, nc.b)
  end

  -- Width
  item.frame:SetWidth(parentWidth)
  item.name:SetHeight(RECIPE_NAME_ROW_HEIGHT)

  -- Build reagent items (skip if collapsed)
  if item.reagentItems then
    for _, ri in ipairs(item.reagentItems) do
      self:ReleaseReagentItem(ri)
    end
    wipe(item.reagentItems)
  end

  if not isCollapsed and recipe.reagents and #recipe.reagents > 0 then
    local showNums = self:GetSetting("showObjectiveNumbers")
    for _, reagent in ipairs(recipe.reagents) do
      local ri = self:AcquireReagentItem(item.frame)
      ri.reagentData = reagent
      ri.frame:SetWidth(parentWidth - RECIPE_ICON_WIDTH - 2)
      self:UpdateReagentItem(ri, reagent, showNums)
      table.insert(item.reagentItems, ri)
    end
  end
end

----------------------------------------------------------------------
-- Update reagent row with data
----------------------------------------------------------------------
function TTQ:UpdateReagentItem(item, reagent, showNumbers)
  if not reagent then return end

  local fontSize = self:GetSetting("objectiveFontSize")
  local fontFace = self:GetResolvedFont("objective")
  local fontOutline = self:GetSetting("objectiveFontOutline")
  if not pcall(item.text.SetFont, item.text, fontFace, fontSize, fontOutline) then
    pcall(item.text.SetFont, item.text, "Fonts\\FRIZQT__.TTF", fontSize, fontOutline)
  end
  if not pcall(item.dash.SetFont, item.dash, fontFace, fontSize, fontOutline) then
    pcall(item.dash.SetFont, item.dash, "Fonts\\FRIZQT__.TTF", fontSize, fontOutline)
  end

  local have = reagent.have or 0
  local needed = reagent.needed or 1

  if have >= needed then
    local color = self:GetSetting("objectiveCompleteColor")
    item.text:SetTextColor(color.r, color.g, color.b)
    item.dash:Hide()
    item.checkIcon:SetVertexColor(color.r, color.g, color.b)
    item.checkIcon:Show()
  else
    local color = self:GetSetting("objectiveIncompleteColor")
    item.text:SetTextColor(color.r, color.g, color.b)
    item.dash:SetTextColor(color.r, color.g, color.b)
    item.dash:SetText("-")
    item.dash:Show()
    item.checkIcon:Hide()
  end

  -- Text: "ReagentName 3/5" or just "ReagentName"
  local displayText = reagent.name or "Unknown"
  if showNumbers then
    displayText = string.format("%s %d/%d", displayText, have, needed)
  end
  item.text:SetText(displayText)
  item.frame:SetHeight(REAGENT_ROW_HEIGHT)
end

----------------------------------------------------------------------
-- Layout reagent items under recipe name, returns total height
----------------------------------------------------------------------
local REAGENT_SPACING = 2

function TTQ:LayoutRecipeItem(item)
  local totalHeight = RECIPE_NAME_ROW_HEIGHT

  if #item.reagentItems > 0 then
    totalHeight = totalHeight + REAGENT_SPACING
    for _, ri in ipairs(item.reagentItems) do
      ri.frame:SetPoint("TOPLEFT", item.frame, "TOPLEFT", RECIPE_ICON_WIDTH + 2, -totalHeight)
      totalHeight = totalHeight + ri.frame:GetHeight()
    end
  end

  item.frame:SetHeight(totalHeight)
  return totalHeight
end

----------------------------------------------------------------------
-- Get tracked recipes from the profession system
----------------------------------------------------------------------
function TTQ:GetTrackedRecipes()
  local recipes = {}

  -- Guard: C_TradeSkillUI must exist (retail only)
  if not C_TradeSkillUI then return recipes end

  -- Get list of tracked recipe IDs
  -- Each entry: { id = recipeID, isRecraft = bool }
  local trackedEntries = {}
  if C_TradeSkillUI.GetRecipesTracked then
    -- TWW/Modern API - get both normal and recraft tracked recipes
    local normalIDs = C_TradeSkillUI.GetRecipesTracked(false)
    if normalIDs then
      for _, id in ipairs(normalIDs) do
        table.insert(trackedEntries, { id = id, isRecraft = false })
      end
    end
    local recraftIDs = C_TradeSkillUI.GetRecipesTracked(true)
    if recraftIDs then
      for _, id in ipairs(recraftIDs) do
        table.insert(trackedEntries, { id = id, isRecraft = true })
      end
    end
  elseif C_TradeSkillUI.GetTrackedRecipeIDs then
    local ids = C_TradeSkillUI.GetTrackedRecipeIDs()
    if ids then
      for _, id in ipairs(ids) do
        table.insert(trackedEntries, { id = id, isRecraft = false })
      end
    end
  end

  if #trackedEntries == 0 then return recipes end

  for _, entry in ipairs(trackedEntries) do
    local recipeData = self:BuildRecipeData(entry.id, entry.isRecraft)
    if recipeData then
      table.insert(recipes, recipeData)
    end
  end

  return recipes
end

----------------------------------------------------------------------
-- Build structured data for a single tracked recipe
----------------------------------------------------------------------
function TTQ:BuildRecipeData(recipeID, isRecraft)
  if not C_TradeSkillUI then return nil end

  local recipeInfo
  if C_TradeSkillUI.GetRecipeInfo then
    recipeInfo = C_TradeSkillUI.GetRecipeInfo(recipeID)
  end

  local name = recipeInfo and recipeInfo.name or "Unknown Recipe"
  local icon = recipeInfo and recipeInfo.icon or nil
  local professionName = ""

  -- Try to get profession name from the recipe info
  if recipeInfo and recipeInfo.categoryID then
    -- Attempt to resolve profession name from the category
    if C_TradeSkillUI.GetCategoryInfo then
      local catInfo = C_TradeSkillUI.GetCategoryInfo(recipeInfo.categoryID)
      if catInfo and catInfo.name then
        professionName = catInfo.name
      end
    end
  end

  -- Get recipe schematic for reagent details
  local reagents = {}
  local allReady = true

  if C_TradeSkillUI.GetRecipeSchematic then
    local schematic = C_TradeSkillUI.GetRecipeSchematic(recipeID, false)
    if schematic and schematic.reagentSlotSchematics then
      for _, slot in ipairs(schematic.reagentSlotSchematics) do
        -- Only track required reagents (not optional/finishing)
        local isRequired = true
        if slot.reagentType then
          -- Enum.CraftingReagentType: 0=None, 1=Basic, 2=Optional,
          -- 3=Finishing, 4=Modifying (varies by expansion)
          if slot.reagentType == 1 then
            isRequired = true  -- Basic/required reagent
          elseif slot.reagentType == 0 then
            isRequired = true  -- Treat None/untyped as required
          else
            isRequired = false -- Optional/Finishing/Modifying
          end
        end

        if isRequired and slot.reagents and #slot.reagents > 0 then
          -- Each slot can have multiple quality tiers of the same
          -- reagent. Sum player inventory across all quality tiers.
          local needed = slot.quantityRequired or 1
          local totalHave = 0
          local primaryName = nil
          local primaryItemID = nil

          for _, reagent in ipairs(slot.reagents) do
            local itemID = reagent.itemID
            if itemID then
              if not primaryItemID then
                primaryItemID = itemID
              end
              -- Get item name
              if not primaryName then
                local itemName = C_Item and C_Item.GetItemNameByID
                    and C_Item.GetItemNameByID(itemID)
                if not itemName or itemName == "" then
                  -- Fallback: use GetItemInfo
                  if GetItemInfo then
                    itemName = GetItemInfo(itemID)
                  end
                end
                if itemName and itemName ~= "" then
                  primaryName = itemName
                end
              end
              -- Count across bags/bank
              local count = 0
              if GetItemCount then
                count = GetItemCount(itemID, true) or 0
              elseif C_Item and C_Item.GetItemCount then
                count = C_Item.GetItemCount(itemID) or 0
              end
              totalHave = totalHave + count
            end
          end

          if primaryItemID then
            if totalHave < needed then
              allReady = false
            end
            table.insert(reagents, {
              itemID = primaryItemID,
              name   = primaryName or ("Item " .. primaryItemID),
              icon   = nil, -- could fetch icon but keeping lightweight
              have   = math.min(totalHave, needed),
              needed = needed,
            })
          end
        end
      end
    end
  end

  -- If we couldn't get any schematic data, still show the recipe
  return {
    recipeID         = recipeID,
    isRecraft        = isRecraft or false,
    name             = name,
    icon             = icon,
    professionName   = professionName,
    reagents         = reagents,
    allReagentsReady = allReady and #reagents > 0,
  }
end

----------------------------------------------------------------------
-- Auctionator integration
----------------------------------------------------------------------

-- Check if Auctionator (or Auctioneer with compatible API) is available
function TTQ:IsAuctionatorAvailable()
  -- Modern Auctionator uses a global Auctionator table with API namespace
  if Auctionator and Auctionator.API and Auctionator.API.v1 then
    return true
  end
  return false
end

-- Search Auctionator for a list of reagents
-- reagentList: { { name = "Item Name", itemID = 12345, needed = 5, have = 2 }, ... }
function TTQ:SearchAuctionator(reagentList)
  if not self:IsAuctionatorAvailable() then
    print("|cff00ccffTommyTwoquests|r: Auctionator is not installed or not loaded.")
    return
  end

  -- Build search term list: only include items the player still needs
  local searchTerms = {}
  for _, reagent in ipairs(reagentList) do
    local stillNeeded = (reagent.needed or 0) - (reagent.have or 0)
    if stillNeeded > 0 and reagent.name then
      table.insert(searchTerms, reagent.name)
    end
  end

  if #searchTerms == 0 then
    print("|cff00ccffTommyTwoquests|r: All reagents already collected!")
    return
  end

  -- Use Auctionator's multi-search API
  -- Auctionator.API.v1.MultiSearchExact(callerID, searchTerms)
  -- or Auctionator.API.v1.MultiSearchAdvanced(callerID, searchList)
  local ok, err
  if Auctionator.API.v1.MultiSearchExact then
    ok, err = pcall(Auctionator.API.v1.MultiSearchExact,
      "TommyTwoquests", searchTerms)
  elseif Auctionator.API.v1.MultiSearch then
    ok, err = pcall(Auctionator.API.v1.MultiSearch,
      "TommyTwoquests", searchTerms)
  end

  if ok then
    print("|cff00ccffTommyTwoquests|r: Searching AH for "
      .. #searchTerms .. " reagent(s)...")
  else
    -- Fallback: try individual search
    if Auctionator.API.v1.MultiSearchAdvanced then
      local searchList = {}
      for _, term in ipairs(searchTerms) do
        table.insert(searchList, { searchString = term, isExact = true })
      end
      pcall(Auctionator.API.v1.MultiSearchAdvanced,
        "TommyTwoquests", searchList)
    else
      print("|cff00ccffTommyTwoquests|r: Could not search AH. "
        .. (err or "Unknown error"))
    end
  end
end

-- Search AH for all missing reagents in a single recipe
function TTQ:SearchAuctionatorForRecipe(recipeData)
  if not recipeData or not recipeData.reagents then return end
  self:SearchAuctionator(recipeData.reagents)
end

----------------------------------------------------------------------
-- Recipe context menu
----------------------------------------------------------------------
function TTQ:CreateRecipeContextMenuFrame()
  if self.RecipeContextMenuFrame then return end

  local MENU_ROW = 22
  local MENU_PAD = 6
  local MENU_WIDTH = 200

  local frame = CreateFrame("Frame", "TTQRecipeContextMenu", UIParent, "BackdropTemplate")
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

  -- Click-away catcher
  local catcher = CreateFrame("Button", nil, UIParent)
  catcher:SetFrameStrata("TOOLTIP")
  catcher:SetFrameLevel(99)
  catcher:SetAllPoints(UIParent)
  catcher:EnableMouse(true)
  catcher:RegisterForClicks("AnyUp")
  catcher:Hide()
  catcher:SetScript("OnClick", function()
    catcher:Hide()
    TTQ:HideRecipeContextMenu()
  end)
  frame.clickCatcher = catcher

  local content = CreateFrame("Frame", nil, frame)
  content:SetPoint("TOPLEFT", frame, "TOPLEFT", MENU_PAD, -MENU_PAD)
  content:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -MENU_PAD, MENU_PAD)
  content:SetFrameLevel(frame:GetFrameLevel() + 1)
  frame.content = content

  -- Title
  local title = TTQ:CreateText(content, 13, { r = 1, g = 0.82, b = 0 }, "LEFT")
  title:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
  title:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, 0)
  title:SetWordWrap(true)
  title:SetNonSpaceWrap(false)
  frame.title = title

  -- Menu button factory
  local function makeBtn(label)
    local btn = CreateFrame("Button", nil, content)
    btn:SetHeight(MENU_ROW)
    btn:SetWidth(MENU_WIDTH)
    btn:SetFrameLevel(content:GetFrameLevel() + 1)
    local hl = btn:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.06)
    local text = TTQ:CreateText(btn, 12, { r = 0.9, g = 0.9, b = 0.9 }, "LEFT")
    text:SetPoint("LEFT", btn, "LEFT", 4, 0)
    text:SetText(label)
    btn.label = text
    btn:SetScript("OnClick", function()
      if btn.onClick then btn.onClick() end
      TTQ:HideRecipeContextMenu()
    end)
    btn:SetScript("OnEnter", function(self)
      if btn.tooltip then
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText(btn.tooltip, 0.9, 0.9, 0.9)
        GameTooltip:Show()
      end
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return btn
  end

  frame.btnOpenRecipe = makeBtn("Open Recipe")
  frame.btnSearchAH   = makeBtn("Search Auction House")
  frame.btnUntrack    = makeBtn("Untrack Recipe")

  frame.buttons       = { frame.btnOpenRecipe, frame.btnSearchAH, frame.btnUntrack }

  frame:SetScript("OnHide", function()
    if frame.clickCatcher and frame.clickCatcher:IsShown() then
      frame.clickCatcher:Hide()
    end
  end)

  self.RecipeContextMenuFrame = frame
end

function TTQ:HideRecipeContextMenu()
  if self.RecipeContextMenuFrame then
    self.RecipeContextMenuFrame:Hide()
  end
  if self.RecipeContextMenuFrame and self.RecipeContextMenuFrame.clickCatcher then
    self.RecipeContextMenuFrame.clickCatcher:Hide()
  end
end

function TTQ:ShowRecipeContextMenu(item)
  local recipe = item.recipeData
  if not recipe then return end

  self:CreateRecipeContextMenuFrame()
  local frame = self.RecipeContextMenuFrame
  local MENU_ROW = 22
  local MENU_PAD = 6

  frame.title:SetText(recipe.name)
  frame.title:SetHeight(math.max(20, frame.title:GetStringHeight() + 4))

  local recipeID = recipe.recipeID

  -- Open Recipe
  frame.btnOpenRecipe.tooltip = "Open this recipe in the profession window."
  frame.btnOpenRecipe.onClick = function()
    if C_TradeSkillUI and C_TradeSkillUI.OpenRecipe then
      C_TradeSkillUI.OpenRecipe(recipeID)
    end
  end
  frame.btnOpenRecipe.label:SetTextColor(0.9, 0.9, 0.9)

  -- Search AH
  local ahAvailable = self:IsAuctionatorAvailable()
  local allReady = recipe.allReagentsReady
  local ahDisabled = not ahAvailable or allReady
  frame.btnSearchAH.tooltip = not ahAvailable
      and "Auctionator addon is required for AH search."
      or allReady
      and "All reagents are already collected."
      or "Search the Auction House for missing reagents."
  frame.btnSearchAH.onClick = function()
    if not ahDisabled then
      TTQ:SearchAuctionatorForRecipe(recipe)
    end
  end
  frame.btnSearchAH.label:SetTextColor(ahDisabled and 0.5 or 0.9, 0.9, 0.9)

  -- Untrack
  frame.btnUntrack.tooltip = "Stop tracking this recipe."
  frame.btnUntrack.onClick = function()
    if C_TradeSkillUI and C_TradeSkillUI.SetRecipeTracked then
      C_TradeSkillUI.SetRecipeTracked(recipeID, false, recipe.isRecraft)
    end
    TTQ:RefreshTracker()
  end
  frame.btnUntrack.label:SetTextColor(0.9, 0.9, 0.9)

  -- Layout buttons
  local titleH = math.max(24, frame.title:GetStringHeight() + 8)
  local y = titleH + 2
  for _, btn in ipairs(frame.buttons) do
    btn:ClearAllPoints()
    btn:SetPoint("TOPLEFT", frame.content, "TOPLEFT", 0, -y)
    y = y + MENU_ROW
  end

  frame:SetHeight(y + MENU_PAD * 2 + 4)
  frame:ClearAllPoints()
  local cursorX, cursorY = GetCursorPosition()
  local scale = UIParent:GetEffectiveScale()
  frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", cursorX / scale, cursorY / scale)
  frame:Show()
  if frame.clickCatcher then
    frame.clickCatcher:Show()
  end
end

----------------------------------------------------------------------
-- Render recipe block in the tracker
-- Returns: total height consumed (0 if no recipes tracked)
----------------------------------------------------------------------
function TTQ:RenderRecipeBlock(parentFrame, width, yOffset)
  if not self:GetSetting("showRecipes") then
    self:HideRecipeDisplay()
    return 0
  end

  local recipes = self:GetTrackedRecipes()
  if #recipes == 0 then
    self:HideRecipeDisplay()
    return 0
  end

  -- Lazily create container
  if not self._recipeContainer then
    self._recipeContainer = CreateFrame("Frame", nil, parentFrame)
  end
  local container = self._recipeContainer
  container:SetParent(parentFrame)
  container:ClearAllPoints()
  container:SetPoint("TOPLEFT", parentFrame, "TOPLEFT", 0, -yOffset)
  container:SetWidth(width)
  container:Show()

  -- Release previous recipe items
  if self._activeRecipeItems then
    for _, ri in ipairs(self._activeRecipeItems) do
      self:ReleaseRecipeItem(ri)
    end
  end
  self._activeRecipeItems = {}

  if self._recipeHeader then
    self._recipeHeader:Hide()
  end

  -- Header
  local SECTION_HEADER_HEIGHT = 22
  if not self._recipeHeaderFrame then
    local hf = CreateFrame("Button", nil, container)
    hf:SetHeight(SECTION_HEADER_HEIGHT)
    hf:EnableMouse(true)
    hf:RegisterForClicks("LeftButtonUp")

    local hl = hf:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.04)

    local icon = hf:CreateTexture(nil, "ARTWORK")
    icon:SetSize(12, 12)
    icon:SetPoint("LEFT", hf, "LEFT", 0, 0)

    local text = self:CreateText(hf, self:GetSetting("headerFontSize"),
      self:GetSetting("headerColor"), "LEFT")
    text:SetPoint("LEFT", icon, "RIGHT", 5, 0)

    local collapseInd = self:CreateText(hf, 12, { r = 1, g = 1, b = 1 }, "RIGHT")
    collapseInd:SetPoint("RIGHT", hf, "RIGHT", 0, 0)
    collapseInd:SetWidth(14)

    local count = self:CreateText(hf,
      self:GetSetting("headerFontSize") - 2,
      { r = 0.6, g = 0.6, b = 0.6 }, "RIGHT")
    count:SetPoint("RIGHT", collapseInd, "LEFT", -2, 0)

    local sep = hf:CreateTexture(nil, "ARTWORK")
    sep:SetHeight(1)
    sep:SetPoint("BOTTOMLEFT", hf, "BOTTOMLEFT", 0, 0)
    sep:SetPoint("BOTTOMRIGHT", hf, "BOTTOMRIGHT", 0, 0)
    sep:SetColorTexture(1, 1, 1, 0.08)

    self._recipeHeaderFrame = hf
    self._recipeHeaderIcon = icon
    self._recipeHeaderText = text
    self._recipeHeaderCount = count
    self._recipeHeaderCollapseInd = collapseInd
  end

  local hf = self._recipeHeaderFrame
  hf:SetParent(container)
  hf:ClearAllPoints()
  hf:SetPoint("TOPLEFT", container, "TOPLEFT", 0, 0)
  hf:SetWidth(width)
  hf:SetHeight(SECTION_HEADER_HEIGHT)
  hf:Show()

  -- Style header
  local headerSize = self:GetSetting("headerFontSize")
  local headerFont = self:GetResolvedFont("header")
  local headerOutline = self:GetSetting("headerFontOutline")
  local headerColor = self:GetSetting("headerColor")
  if not pcall(self._recipeHeaderText.SetFont, self._recipeHeaderText, headerFont, headerSize, headerOutline) then
    pcall(self._recipeHeaderText.SetFont, self._recipeHeaderText, "Fonts\\FRIZQT__.TTF", headerSize, headerOutline)
  end
  self._recipeHeaderText:SetTextColor(headerColor.r, headerColor.g, headerColor.b)
  self._recipeHeaderText:SetText("Recipes")

  -- Icon
  if self:GetSetting("showIcons") then
    local iconSize = math.max(10, headerSize - 1)
    -- Use profession-related atlas
    local atlasOK = pcall(self._recipeHeaderIcon.SetAtlas, self._recipeHeaderIcon,
      "Campaign-QuestLog-LoreBook", false)
    if not atlasOK then
      pcall(self._recipeHeaderIcon.SetAtlas, self._recipeHeaderIcon, "Profession", false)
    end
    self._recipeHeaderIcon:SetSize(iconSize, iconSize)
    self._recipeHeaderIcon:SetDesaturated(false)
    self._recipeHeaderIcon:SetVertexColor(1, 1, 1)
    self._recipeHeaderIcon:Show()
  else
    self._recipeHeaderIcon:Hide()
    self._recipeHeaderText:SetPoint("LEFT", hf, "LEFT", 0, 0)
  end

  -- Collapse state for recipe section
  local collapsedGroups = self:GetSetting("collapsedGroups") or {}
  local isRecipeSectionCollapsed = collapsedGroups["_recipes"] and true or false

  -- Count
  local numReady = 0
  for _, r in ipairs(recipes) do
    if r.allReagentsReady then numReady = numReady + 1 end
  end
  if self:GetSetting("showHeaderCount") then
    self._recipeHeaderCount:SetText(numReady .. "/" .. #recipes)
    local countSize = math.max(9, headerSize - 2)
    if not pcall(self._recipeHeaderCount.SetFont, self._recipeHeaderCount, headerFont, countSize, headerOutline) then
      pcall(self._recipeHeaderCount.SetFont, self._recipeHeaderCount, "Fonts\\FRIZQT__.TTF", countSize, headerOutline)
    end
    if numReady == #recipes and #recipes > 0 then
      local ec = self:GetSetting("objectiveCompleteColor")
      self._recipeHeaderCount:SetTextColor(ec.r, ec.g, ec.b)
    else
      self._recipeHeaderCount:SetTextColor(0.6, 0.6, 0.6)
    end
    self._recipeHeaderCount:Show()
  else
    self._recipeHeaderCount:Hide()
  end

  -- Collapse indicator
  self._recipeHeaderCollapseInd:SetText(isRecipeSectionCollapsed and "+" or "-")
  local indFont = self:GetResolvedFont("quest")
  local indSize = self:GetSetting("questNameFontSize")
  local indOutline = self:GetSetting("questNameFontOutline")
  if not pcall(self._recipeHeaderCollapseInd.SetFont, self._recipeHeaderCollapseInd, indFont, indSize, indOutline) then
    pcall(self._recipeHeaderCollapseInd.SetFont, self._recipeHeaderCollapseInd, "Fonts\\FRIZQT__.TTF", indSize,
      indOutline)
  end
  self._recipeHeaderCollapseInd:SetTextColor(1, 1, 1)

  -- Click: toggle section collapse
  hf:SetScript("OnClick", function()
    local cg = TTQ:GetSetting("collapsedGroups")
    if type(cg) ~= "table" then cg = {} end
    cg = TTQ:DeepCopy(cg)
    cg["_recipes"] = not cg["_recipes"] and true or false
    TTQ:SetSetting("collapsedGroups", cg)
    TTQ:RefreshTracker()
  end)

  hf:SetScript("OnEnter", function(btn)
    GameTooltip:SetOwner(btn, "ANCHOR_LEFT")
    GameTooltip:SetText("Tracked Recipes")
    local ahStatus = TTQ:IsAuctionatorAvailable()
        and "|cff00cc00Auctionator detected|r"
        or "|cffff6666Auctionator not detected|r"
    GameTooltip:AddLine(ahStatus, 1, 1, 1)
    GameTooltip:AddLine(isRecipeSectionCollapsed and "Click to expand" or "Click to collapse", 0.7, 0.7, 0.7)
    GameTooltip:Show()
  end)
  hf:SetScript("OnLeave", function() GameTooltip:Hide() end)

  local totalHeight = SECTION_HEADER_HEIGHT + 2

  -- Render recipe items if not collapsed
  if not isRecipeSectionCollapsed then
    local yInBlock = totalHeight
    for _, recipe in ipairs(recipes) do
      local recipeItem = self:AcquireRecipeItem(container)
      self:UpdateRecipeItem(recipeItem, recipe, width)
      local itemHeight = self:LayoutRecipeItem(recipeItem)
      itemHeight = math.max(RECIPE_NAME_ROW_HEIGHT, itemHeight)

      recipeItem.frame:ClearAllPoints()
      recipeItem.frame:SetPoint("TOPLEFT", container, "TOPLEFT", 4, -yInBlock)
      recipeItem.frame:SetWidth(width - 4)
      recipeItem.frame:SetHeight(itemHeight)

      table.insert(self._activeRecipeItems, recipeItem)
      yInBlock = yInBlock + itemHeight + 2
    end
    totalHeight = yInBlock
  end

  totalHeight = totalHeight + 4 -- section spacing
  container:SetHeight(totalHeight)
  return totalHeight
end

----------------------------------------------------------------------
-- Hide recipe display (cleanup)
----------------------------------------------------------------------
function TTQ:HideRecipeDisplay()
  if self._activeRecipeItems then
    for _, ri in ipairs(self._activeRecipeItems) do
      self:ReleaseRecipeItem(ri)
    end
    wipe(self._activeRecipeItems)
  end
  if self._recipeContainer then
    self._recipeContainer:Hide()
  end
  if self._recipeHeaderFrame then
    self._recipeHeaderFrame:Hide()
  end
end
