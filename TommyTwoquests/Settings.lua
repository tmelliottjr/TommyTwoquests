----------------------------------------------------------------------
-- TommyTwoquests — Settings.lua
----------------------------------------------------------------------
local AddonName, TTQ = ...
local ipairs, type, math, pcall, tostring, pairs, select, string =
    ipairs, type, math, pcall, tostring, pairs, select, string
local CreateFrame, UIParent, C_Timer, GetTime, IsMouseButtonDown, GetCursorPosition =
    CreateFrame, UIParent, C_Timer, GetTime, IsMouseButtonDown, GetCursorPosition

----------------------------------------------------------------------
-- Design tokens (cinematic dark theme)
----------------------------------------------------------------------
local Def = {
    Padding            = 18,
    OptionGap          = 14,
    SectionGap         = 24,
    CardPadding        = 18,
    BorderEdge         = 1,
    LabelSize          = 13,
    SectionSize        = 11,
    HeaderSize         = 16,
    FontPath           = "Fonts\\FRIZQT__.TTF",
    TextColorNormal    = { 1, 1, 1 },
    TextColorHighlight = { 0.72, 0.8, 0.95, 1 },
    TextColorLabel     = { 0.84, 0.84, 0.88 },
    TextColorSection   = { 0.58, 0.64, 0.74 },
    TextColorTitleBar  = { 0.9, 0.92, 0.96, 1 },
    SectionCardBg      = { 0.09, 0.09, 0.11, 0.96 },
    SectionCardBorder  = { 0.18, 0.2, 0.24, 0.35 },
    AccentColor        = { 0.48, 0.58, 0.82, 0.9 },
    DividerColor       = { 0.35, 0.4, 0.5, 0.25 },
    InputBg            = { 0.07, 0.07, 0.1, 0.96 },
    InputBorder        = { 0.2, 0.22, 0.28, 0.4 },
    TrackOff           = { 0.14, 0.14, 0.18, 0.95 },
    TrackOn            = { 0.48, 0.58, 0.82, 0.85 },
    ThumbColor         = { 1, 1, 1, 0.98 },
}

----------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------
local function SetColor(obj, color)
    if not color or not obj then return end
    obj:SetTextColor(color[1], color[2], color[3], color[4] or 1)
end

local function easeOut(t) return 1 - (1 - t) * (1 - t) end

local function CreateBorder(frame, color, thickness)
    if not frame then return end
    local c = color or Def.SectionCardBorder
    local th = thickness or 1
    local top = frame:CreateTexture(nil, "BORDER")
    top:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
    top:SetHeight(th)
    top:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    top:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    local bottom = frame:CreateTexture(nil, "BORDER")
    bottom:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
    bottom:SetHeight(th)
    bottom:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
    bottom:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    local left = frame:CreateTexture(nil, "BORDER")
    left:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
    left:SetWidth(th)
    left:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    left:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
    local right = frame:CreateTexture(nil, "BORDER")
    right:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
    right:SetWidth(th)
    right:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    right:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
end

----------------------------------------------------------------------
-- DB helpers (proxy to TTQ:GetSetting / SetSetting)
----------------------------------------------------------------------
local function getDB(key, default)
    local v = TTQ:GetSetting(key)
    if v == nil then return default end
    return v
end

local function setDB(key, value)
    TTQ:SetSetting(key, value)
    TTQ:OnSettingChanged(key, value)
end

----------------------------------------------------------------------
-- Initialize settings panel (called from Core.lua OnReady)
----------------------------------------------------------------------
function TTQ:InitSettings()
    self:BuildSettingsUI()
end

----------------------------------------------------------------------
-- Widget: section card (dark card container)
----------------------------------------------------------------------
local function CreateSectionCard(parent, anchor)
    local card = CreateFrame("Frame", nil, parent)
    card:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -Def.SectionGap)
    card:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, 0)
    local inset = 1
    local bg = card:CreateTexture(nil, "BACKGROUND")
    bg:SetPoint("TOPLEFT", card, "TOPLEFT", inset, -inset)
    bg:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -inset, inset)
    bg:SetColorTexture(Def.SectionCardBg[1], Def.SectionCardBg[2], Def.SectionCardBg[3], Def.SectionCardBg[4])
    CreateBorder(card, Def.SectionCardBorder)
    return card
end

----------------------------------------------------------------------
-- Widget: section header (uppercase label)
----------------------------------------------------------------------
local function CreateSectionHeader(parent, text)
    local label = parent:CreateFontString(nil, "OVERLAY")
    label:SetFont(Def.FontPath, Def.SectionSize + 1, "OUTLINE")
    label:SetJustifyH("LEFT")
    SetColor(label, Def.TextColorSection)
    label:SetText(text and text:upper() or "")
    return label
end

----------------------------------------------------------------------
-- Widget: toggle switch (animated pill)
----------------------------------------------------------------------
local TOGGLE_TRACK_W, TOGGLE_TRACK_H = 48, 22
local TOGGLE_INSET = 2
local TOGGLE_THUMB_SIZE = 18
local TOGGLE_ANIM_DUR = 0.15

local function CreateToggleSwitch(parent, labelText, description, get, set)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(38)
    row.searchText = ((labelText or "") .. " " .. (description or "")):lower()

    local track = CreateFrame("Frame", nil, row)
    track:SetSize(TOGGLE_TRACK_W, TOGGLE_TRACK_H)
    track:SetPoint("TOPRIGHT", row, "TOPRIGHT", 0, -10)

    local trackBg = track:CreateTexture(nil, "BACKGROUND")
    trackBg:SetPoint("TOPLEFT", track, "TOPLEFT", TOGGLE_INSET, -TOGGLE_INSET)
    trackBg:SetPoint("BOTTOMRIGHT", track, "BOTTOMRIGHT", -TOGGLE_INSET, TOGGLE_INSET)
    trackBg:SetColorTexture(Def.TrackOff[1], Def.TrackOff[2], Def.TrackOff[3], Def.TrackOff[4])

    local trackFill = track:CreateTexture(nil, "ARTWORK")
    trackFill:SetPoint("TOPLEFT", track, "TOPLEFT", TOGGLE_INSET, -TOGGLE_INSET)
    trackFill:SetPoint("BOTTOMLEFT", track, "BOTTOMLEFT", TOGGLE_INSET, TOGGLE_INSET)
    trackFill:SetWidth(0)
    trackFill:SetColorTexture(Def.TrackOn[1], Def.TrackOn[2], Def.TrackOn[3], Def.TrackOn[4])

    local thumb = track:CreateTexture(nil, "OVERLAY")
    thumb:SetSize(TOGGLE_THUMB_SIZE, TOGGLE_THUMB_SIZE)
    thumb:SetColorTexture(Def.ThumbColor[1], Def.ThumbColor[2], Def.ThumbColor[3], Def.ThumbColor[4])
    thumb:SetPoint("CENTER", track, "LEFT", TOGGLE_INSET + TOGGLE_THUMB_SIZE / 2, 0)

    local label = row:CreateFontString(nil, "OVERLAY")
    label:SetFont(Def.FontPath, Def.LabelSize, "OUTLINE")
    label:SetJustifyH("LEFT")
    SetColor(label, Def.TextColorLabel)
    label:SetText(labelText or "")
    label:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
    label:SetPoint("RIGHT", track, "LEFT", -12, 0)
    label:SetWordWrap(true)

    local desc = row:CreateFontString(nil, "OVERLAY")
    desc:SetFont(Def.FontPath, Def.SectionSize, "OUTLINE")
    desc:SetJustifyH("LEFT")
    SetColor(desc, Def.TextColorSection)
    desc:SetText(description or "")
    desc:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -2)
    desc:SetPoint("RIGHT", track, "LEFT", -12, 0)
    desc:SetWordWrap(true)

    local btn = CreateFrame("Button", nil, row)
    btn:SetAllPoints(track)

    row.thumbPos = get() and 1 or 0

    local fillW = TOGGLE_TRACK_W - 2 * TOGGLE_INSET
    local thumbTravel = fillW - TOGGLE_THUMB_SIZE
    local function updateVisuals(t)
        thumb:ClearAllPoints()
        thumb:SetPoint("CENTER", track, "LEFT", TOGGLE_INSET + TOGGLE_THUMB_SIZE / 2 + t * thumbTravel, 0)
        trackFill:SetWidth(math.max(0.01, t * fillW))
    end

    local function toggleOnUpdate()
        if not row.animStart then
            track:SetScript("OnUpdate", nil)
            return
        end
        local elapsed = GetTime() - row.animStart
        if elapsed >= TOGGLE_ANIM_DUR then
            row.thumbPos = row.animTo
            row.animStart = nil
            updateVisuals(row.thumbPos)
            track:SetScript("OnUpdate", nil)
            return
        end
        row.thumbPos = row.animFrom + (row.animTo - row.animFrom) * easeOut(elapsed / TOGGLE_ANIM_DUR)
        updateVisuals(row.thumbPos)
    end

    btn:SetScript("OnClick", function()
        local next = not get()
        set(next)
        row.animStart = GetTime()
        row.animFrom = row.thumbPos
        row.animTo = next and 1 or 0
        track:SetScript("OnUpdate", toggleOnUpdate)
    end)

    function row:Refresh()
        local on = get()
        row.thumbPos = on and 1 or 0
        row.animStart = nil
        track:SetScript("OnUpdate", nil)
        updateVisuals(row.thumbPos)
    end

    row:Refresh()
    return row
end

----------------------------------------------------------------------
-- Widget: slider (track + thumb + editable readout)
----------------------------------------------------------------------
local SLIDER_TRACK_HEIGHT = 6
local SLIDER_THUMB_SIZE = 14
local SLIDER_TRACK_INSET = 2

local function CreateSliderWidget(parent, labelText, description, get, set, minVal, maxVal, step)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(40)
    row.searchText = ((labelText or "") .. " " .. (description or "")):lower()

    local label = row:CreateFontString(nil, "OVERLAY")
    label:SetFont(Def.FontPath, Def.LabelSize, "OUTLINE")
    label:SetJustifyH("LEFT")
    SetColor(label, Def.TextColorLabel)
    label:SetText(labelText or "")
    label:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)

    local desc = row:CreateFontString(nil, "OVERLAY")
    desc:SetFont(Def.FontPath, Def.SectionSize, "OUTLINE")
    desc:SetJustifyH("LEFT")
    SetColor(desc, Def.TextColorSection)
    desc:SetText(description or "")
    desc:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -2)
    desc:SetPoint("RIGHT", row, "RIGHT", -60, 0)
    desc:SetWordWrap(true)

    local trackWidth = 180
    local track = CreateFrame("Frame", nil, row)
    track:SetSize(trackWidth, SLIDER_TRACK_HEIGHT)
    track:SetPoint("TOPRIGHT", row, "TOPRIGHT", -52, -8)

    local trackBg = track:CreateTexture(nil, "BACKGROUND")
    trackBg:SetPoint("TOPLEFT", track, "TOPLEFT", SLIDER_TRACK_INSET, -SLIDER_TRACK_INSET)
    trackBg:SetPoint("BOTTOMRIGHT", track, "BOTTOMRIGHT", -SLIDER_TRACK_INSET, SLIDER_TRACK_INSET)
    trackBg:SetColorTexture(Def.TrackOff[1], Def.TrackOff[2], Def.TrackOff[3], Def.TrackOff[4])

    local trackFill = track:CreateTexture(nil, "ARTWORK")
    trackFill:SetPoint("TOPLEFT", track, "TOPLEFT", SLIDER_TRACK_INSET, -SLIDER_TRACK_INSET)
    trackFill:SetPoint("BOTTOMLEFT", track, "BOTTOMLEFT", SLIDER_TRACK_INSET, SLIDER_TRACK_INSET)
    trackFill:SetColorTexture(Def.TrackOn[1], Def.TrackOn[2], Def.TrackOn[3], Def.TrackOn[4])

    local thumbBtn = CreateFrame("Button", nil, track)
    thumbBtn:SetSize(SLIDER_THUMB_SIZE, SLIDER_THUMB_SIZE)
    thumbBtn:SetPoint("CENTER", track, "LEFT", 0, 0)
    local thumbTex = thumbBtn:CreateTexture(nil, "BACKGROUND")
    thumbTex:SetAllPoints(thumbBtn)
    thumbTex:SetColorTexture(Def.ThumbColor[1], Def.ThumbColor[2], Def.ThumbColor[3], Def.ThumbColor[4])

    local edit = CreateFrame("EditBox", nil, row, "InputBoxTemplate")
    edit:SetSize(44, 20)
    edit:SetPoint("LEFT", track, "RIGHT", 8, 0)
    edit:SetMaxLetters(6)
    edit:SetAutoFocus(false)
    edit:SetFont(Def.FontPath, Def.LabelSize, "OUTLINE")

    local function snap(v)
        if step and step > 0 then
            v = math.floor(v / step + 0.5) * step
        end
        return math.max(minVal, math.min(maxVal, v))
    end

    local function formatVal(v)
        if step and step < 1 then
            return string.format("%.2f", v)
        end
        return tostring(math.floor(v + 0.5))
    end

    edit:SetScript("OnEscapePressed", function() edit:ClearFocus() end)
    edit:SetScript("OnEnterPressed", function()
        local v = tonumber(edit:GetText())
        if v then
            v = snap(v); set(v); edit:SetText(formatVal(v))
        end
        edit:ClearFocus()
    end)
    edit:SetScript("OnTextChanged", function(self, userInput)
        if not userInput then return end
        local v = tonumber(self:GetText())
        if v then
            v = snap(v); set(v)
        end
    end)

    local function valueToNorm(v)
        if maxVal <= minVal then return 0 end
        return (v - minVal) / (maxVal - minVal)
    end
    local function normToValue(n)
        return minVal + n * (maxVal - minVal)
    end

    local fillWidth = trackWidth - 2 * SLIDER_TRACK_INSET
    local thumbTravel = fillWidth - SLIDER_THUMB_SIZE
    local function updateFromValue(v)
        v = math.max(minVal, math.min(maxVal, v))
        local n = valueToNorm(v)
        thumbBtn:ClearAllPoints()
        thumbBtn:SetPoint("CENTER", track, "LEFT", SLIDER_TRACK_INSET + SLIDER_THUMB_SIZE / 2 + n * thumbTravel, 0)
        trackFill:SetWidth(math.max(0.01, n * fillWidth))
        edit:SetText(formatVal(v))
    end

    thumbBtn:SetScript("OnMouseDown", function(_, mbtn)
        if mbtn ~= "LeftButton" then return end
        local startNorm = valueToNorm(get())
        local scale = track:GetEffectiveScale()
        local startX = GetCursorPosition() / scale
        thumbBtn:GetParent():SetScript("OnUpdate", function()
            if not IsMouseButtonDown("LeftButton") then
                thumbBtn:GetParent():SetScript("OnUpdate", nil)
                return
            end
            local x = GetCursorPosition() / scale
            local delta = (x - startX) / fillWidth
            local n = math.max(0, math.min(1, startNorm + delta))
            local v = snap(normToValue(n))
            set(v)
            updateFromValue(v)
            startNorm = n
            startX = x
        end)
    end)

    function row:Refresh()
        updateFromValue(get())
    end

    row:Refresh()
    return row
end

----------------------------------------------------------------------
-- Widget: custom dropdown (button + popup)
----------------------------------------------------------------------
local function CreateDropdownWidget(parent, labelText, description, options, get, set)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(52)
    row.searchText = ((labelText or "") .. " " .. (description or "")):lower()

    local label = row:CreateFontString(nil, "OVERLAY")
    label:SetFont(Def.FontPath, Def.LabelSize, "OUTLINE")
    label:SetJustifyH("LEFT")
    SetColor(label, Def.TextColorLabel)
    label:SetText(labelText or "")
    label:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)

    local desc = row:CreateFontString(nil, "OVERLAY")
    desc:SetFont(Def.FontPath, Def.SectionSize, "OUTLINE")
    desc:SetJustifyH("LEFT")
    SetColor(desc, Def.TextColorSection)
    desc:SetText(description or "")
    desc:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -2)
    desc:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    desc:SetWordWrap(true)

    local btn = CreateFrame("Button", nil, row)
    btn:SetHeight(26)
    btn:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -28)
    btn:SetPoint("RIGHT", row, "RIGHT", 0, 0)

    local btnBg = btn:CreateTexture(nil, "BACKGROUND")
    btnBg:SetPoint("TOPLEFT", btn, "TOPLEFT", 2, -2)
    btnBg:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -2, 2)
    btnBg:SetColorTexture(Def.InputBg[1], Def.InputBg[2], Def.InputBg[3], Def.InputBg[4])

    local btnText = btn:CreateFontString(nil, "OVERLAY")
    btnText:SetFont(Def.FontPath, Def.LabelSize, "OUTLINE")
    SetColor(btnText, Def.TextColorLabel)
    btnText:SetPoint("LEFT", btn, "LEFT", 8, 0)
    btnText:SetPoint("RIGHT", btn, "RIGHT", -24, 0)
    btnText:SetJustifyH("LEFT")

    local chevron = btn:CreateFontString(nil, "OVERLAY")
    chevron:SetFont(Def.FontPath, Def.LabelSize, "OUTLINE")
    SetColor(chevron, Def.TextColorSection)
    chevron:SetText("v")
    chevron:SetPoint("RIGHT", btn, "RIGHT", -6, 0)

    -- Popup list
    local list = CreateFrame("Frame", nil, UIParent)
    list:SetFrameStrata("TOOLTIP")
    list:Hide()
    list:SetSize(200, 1)
    local listBg = list:CreateTexture(nil, "BACKGROUND")
    listBg:SetAllPoints(list)
    listBg:SetColorTexture(Def.SectionCardBg[1], Def.SectionCardBg[2], Def.SectionCardBg[3], Def.SectionCardBg[4])
    CreateBorder(list, Def.SectionCardBorder)

    local catch = CreateFrame("Button", nil, UIParent)
    catch:SetFrameStrata("TOOLTIP")
    catch:SetAllPoints(UIParent)
    catch:Hide()
    local function closeList()
        list:Hide(); catch:Hide()
    end
    catch:SetScript("OnClick", closeList)

    local function setValue(value, display)
        set(value)
        btnText:SetText(display or tostring(value))
        closeList()
    end

    btn:SetScript("OnClick", function()
        if list:IsShown() then
            closeList()
            return
        end
        list:SetParent(UIParent)
        list:ClearAllPoints()
        list:SetPoint("TOPLEFT", btn, "BOTTOMLEFT", 0, -2)
        local opts = (type(options) == "function" and options()) or options or {}
        local num = #opts
        local rowH = 22
        list:SetHeight(num * rowH)
        list:SetWidth(btn:GetWidth())
        while list:GetNumChildren() < num do
            local b = CreateFrame("Button", nil, list)
            b:SetHeight(rowH)
            b:SetPoint("LEFT", list, "LEFT", 0, 0)
            b:SetPoint("RIGHT", list, "RIGHT", 0, 0)
            local tb = b:CreateFontString(nil, "OVERLAY")
            tb:SetFont(Def.FontPath, Def.LabelSize, "OUTLINE")
            tb:SetPoint("LEFT", b, "LEFT", 8, 0)
            tb:SetJustifyH("LEFT")
            b.text = tb
            local hi = b:CreateTexture(nil, "BACKGROUND")
            hi:SetAllPoints(b)
            hi:SetColorTexture(1, 1, 1, 0.06)
            hi:Hide()
            b:SetScript("OnEnter", function() hi:Show() end)
            b:SetScript("OnLeave", function() hi:Hide() end)
        end
        local children = { list:GetChildren() }
        for i, opt in ipairs(opts) do
            local b = children[i]
            if b then
                b:SetPoint("TOP", list, "TOP", 0, -(i - 1) * rowH)
                b.text:SetText(opt.name or opt[1] or "")
                b:SetScript("OnClick", function()
                    setValue(opt.value or opt[2], opt.name or opt[1])
                end)
                b:Show()
            end
        end
        for i = #opts + 1, #children do
            if children[i] then children[i]:Hide() end
        end
        list:Show()
        catch:Show()
    end)

    function row:Refresh()
        local val = get()
        local opts = (type(options) == "function" and options()) or options or {}
        for _, opt in ipairs(opts) do
            local ov = opt.value or opt[2]
            local on = opt.name or opt[1]
            if ov == val then
                btnText:SetText(on)
                return
            end
        end
        btnText:SetText(tostring(val))
    end

    row:Refresh()
    return row
end

----------------------------------------------------------------------
-- Widget: search input
----------------------------------------------------------------------
local function CreateSearchInput(parent, onTextChanged, placeholder)
    local row = CreateFrame("Frame", nil, parent)
    row:SetAllPoints(parent)

    local edit = CreateFrame("EditBox", nil, row)
    edit:SetHeight(28)
    edit:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
    edit:SetPoint("TOPRIGHT", row, "TOPRIGHT", -24, 0)
    edit:SetAutoFocus(false)
    edit:SetFont(Def.FontPath, Def.LabelSize, "OUTLINE")
    edit:SetTextInsets(28, 24, 0, 0)
    local tc = Def.TextColorLabel
    edit:SetTextColor(tc[1], tc[2], tc[3], tc[4] or 1)

    local editBg = edit:CreateTexture(nil, "BACKGROUND")
    editBg:SetPoint("TOPLEFT", edit, "TOPLEFT", 6, -6)
    editBg:SetPoint("BOTTOMRIGHT", edit, "BOTTOMRIGHT", -6, 6)
    editBg:SetColorTexture(Def.InputBg[1], Def.InputBg[2], Def.InputBg[3], Def.InputBg[4])

    -- Borders
    local ib = Def.InputBorder
    local borderTop = edit:CreateTexture(nil, "BORDER"); borderTop:SetHeight(1)
    borderTop:SetPoint("TOPLEFT", edit, "TOPLEFT", 0, 0); borderTop:SetPoint("TOPRIGHT", edit, "TOPRIGHT", 0, 0)
    borderTop:SetColorTexture(ib[1], ib[2], ib[3], ib[4])
    local borderBottom = edit:CreateTexture(nil, "BORDER"); borderBottom:SetHeight(1)
    borderBottom:SetPoint("BOTTOMLEFT", edit, "BOTTOMLEFT", 0, 0); borderBottom:SetPoint("BOTTOMRIGHT", edit,
        "BOTTOMRIGHT", 0, 0)
    borderBottom:SetColorTexture(ib[1], ib[2], ib[3], ib[4])
    local borderLeft = edit:CreateTexture(nil, "BORDER"); borderLeft:SetWidth(1)
    borderLeft:SetPoint("TOPLEFT", edit, "TOPLEFT", 0, 0); borderLeft:SetPoint("BOTTOMLEFT", edit, "BOTTOMLEFT", 0, 0)
    borderLeft:SetColorTexture(ib[1], ib[2], ib[3], ib[4])
    local borderRight = edit:CreateTexture(nil, "BORDER"); borderRight:SetWidth(1)
    borderRight:SetPoint("TOPRIGHT", edit, "TOPRIGHT", 0, 0); borderRight:SetPoint("BOTTOMRIGHT", edit, "BOTTOMRIGHT", 0,
        0)
    borderRight:SetColorTexture(ib[1], ib[2], ib[3], ib[4])

    local searchIcon = edit:CreateTexture(nil, "OVERLAY")
    searchIcon:SetSize(14, 14)
    searchIcon:SetPoint("LEFT", edit, "LEFT", 10, 0)
    searchIcon:SetTexture("Interface\\Icons\\INV_Misc_Spyglass_03")
    searchIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    local ph = edit:CreateFontString(nil, "OVERLAY")
    ph:SetFont(Def.FontPath, Def.LabelSize, "OUTLINE")
    SetColor(ph, Def.TextColorSection)
    ph:SetText(placeholder or "Search settings...")
    ph:SetPoint("LEFT", edit, "LEFT", 28, 0)
    ph:SetJustifyH("LEFT")

    local clearBtn = CreateFrame("Button", nil, row)
    clearBtn:SetSize(20, 20)
    clearBtn:SetPoint("RIGHT", edit, "RIGHT", -6, 0)
    clearBtn:EnableMouse(true)
    clearBtn:Hide()
    local clearText = clearBtn:CreateFontString(nil, "OVERLAY")
    clearText:SetFont(Def.FontPath, Def.LabelSize - 1, "OUTLINE")
    SetColor(clearText, Def.TextColorSection)
    clearText:SetText("X")
    clearText:SetPoint("CENTER", clearBtn, "CENTER", 0, 0)
    clearBtn:SetScript("OnClick", function()
        edit:SetText(""); ph:Show()
        if onTextChanged then onTextChanged("") end
        clearBtn:Hide()
    end)
    clearBtn:SetScript("OnEnter", function() SetColor(clearText, Def.TextColorHighlight) end)
    clearBtn:SetScript("OnLeave", function() SetColor(clearText, Def.TextColorSection) end)

    edit:SetScript("OnEditFocusGained", function()
        ph:Hide(); clearBtn:SetShown(edit:GetText() ~= "")
    end)
    edit:SetScript("OnEditFocusLost",
        function()
            if edit:GetText() == "" then ph:Show() end; clearBtn:SetShown(edit:GetText() ~= "")
        end)
    edit:SetScript("OnEscapePressed", function()
        edit:SetText(""); ph:Show(); edit:ClearFocus()
        if onTextChanged then onTextChanged("") end
        clearBtn:Hide()
    end)
    edit:SetScript("OnTextChanged", function(self, userInput)
        ph:SetShown(self:GetText() == "")
        if userInput and onTextChanged then onTextChanged(self:GetText()) end
        clearBtn:SetShown(self:GetText() ~= "")
    end)

    row.edit = edit
    row.clearBtn = clearBtn
    return row
end

----------------------------------------------------------------------
-- Option category data
----------------------------------------------------------------------
local function GetFontOptions()
    local fontList = TTQ:GetFontList()
    local out = {}
    for _, opt in ipairs(fontList) do
        out[#out + 1] = { name = opt.name, value = opt.name }
    end
    return out
end

local OUTLINE_OPTIONS = {
    { name = "None",    value = "" },
    { name = "Outline", value = "OUTLINE" },
    { name = "Thick",   value = "THICKOUTLINE" },
    { name = "Mono",    value = "MONOCHROME" },
}

local function BuildOptionCategories()
    return {
        {
            key = "Display",
            name = "Display",
            options = {
                { type = "section",  name = "Panel" },
                { type = "slider",   name = "Tracker width",           desc = "Width of the quest tracker frame.",                                                                             dbKey = "trackerWidth",        min = 150,                                                                                              max = 500,  step = 10 },
                { type = "slider",   name = "Max visible quests",      desc = "Maximum number of quests shown at once.",                                                                       dbKey = "maxQuests",           min = 1,                                                                                                max = 25,   step = 1 },
                { type = "slider",   name = "Max tracker height",      desc = "Maximum height of the tracker in pixels. Content scrolls when exceeded.",                                       dbKey = "trackerMaxHeight",    min = 200,                                                                                              max = 1200, step = 25 },
                { type = "toggle",   name = "Lock position",           desc = "Prevent the tracker from being dragged.",                                                                       dbKey = "locked" },
                { type = "toggle",   name = "Show tracker header",     desc = "Show the title bar with 'Quests' text. When hidden, only the icon buttons appear.",                             dbKey = "showTrackerHeader" },
                { type = "section",  name = "Background" },
                { type = "toggle",   name = "Show background",         desc = "Show a semi-transparent background behind the tracker.",                                                        dbKey = "showBackground" },
                { type = "slider",   name = "Background opacity",      desc = "Opacity of the tracker background.",                                                                            dbKey = "bgAlpha",             min = 0,                                                                                                max = 1,    step = 0.05 },
                { type = "toggle",   name = "Class color gradient",    desc = "Add a subtle class-colored gradient and glow to the background.",                                               dbKey = "classColorGradient" },
                { type = "section",  name = "Visibility" },
                { type = "toggle",   name = "Hide in combat",          desc = "Hide the tracker when you enter combat.",                                                                       dbKey = "hideInCombat" },
                { type = "toggle",   name = "Show abandon all button", desc = "Show a skull button in the header to abandon all quests at once.",                                              dbKey = "showAbandonAllButton" },
                { type = "toggle",   name = "Show tracker tooltips",   desc = "Show tooltips when hovering over quests and section headers in the tracker.",                                   dbKey = "showTrackerTooltips" },
                { type = "section",  name = "Quest Items" },
                { type = "dropdown", name = "Quest item button",       desc = "Position of the usable quest item button. Right places it inside the row; Left floats it outside the tracker.", dbKey = "questItemPosition",   options = { { name = "Right (inline)", value = "right" }, { name = "Left (outside)", value = "left" } } },
            },
        },
        {
            key = "Typography",
            name = "Typography",
            options = {
                { type = "section",  name = "Global font" },
                { type = "toggle",   name = "Use one font for all", desc = "When enabled, the global font is used for headers, quest names, and objectives.", dbKey = "useGlobalFont" },
                { type = "dropdown", name = "Global font",          desc = "Font used for the entire tracker.",                                               dbKey = "globalFont",           options = GetFontOptions },
                { type = "section",  name = "Header" },
                { type = "dropdown", name = "Header font",          desc = "Font for group headers (used when global font is off).",                          dbKey = "headerFont",           options = GetFontOptions },
                { type = "slider",   name = "Header size",          desc = "Font size for group headers.",                                                    dbKey = "headerFontSize",       min = 8,                  max = 24, step = 1 },
                { type = "dropdown", name = "Header outline",       desc = "Outline style for group headers.",                                                dbKey = "headerFontOutline",    options = OUTLINE_OPTIONS },
                { type = "section",  name = "Quest names" },
                { type = "dropdown", name = "Quest name font",      desc = "Font for quest names (used when global font is off).",                            dbKey = "questNameFont",        options = GetFontOptions },
                { type = "slider",   name = "Quest name size",      desc = "Font size for quest names.",                                                      dbKey = "questNameFontSize",    min = 8,                  max = 24, step = 1 },
                { type = "dropdown", name = "Quest name outline",   desc = "Outline style for quest names.",                                                  dbKey = "questNameFontOutline", options = OUTLINE_OPTIONS },
                { type = "section",  name = "Objectives" },
                { type = "dropdown", name = "Objective font",       desc = "Font for objective text (used when global font is off).",                         dbKey = "objectiveFont",        options = GetFontOptions },
                { type = "slider",   name = "Objective size",       desc = "Font size for objective text.",                                                   dbKey = "objectiveFontSize",    min = 8,                  max = 20, step = 1 },
                { type = "dropdown", name = "Objective outline",    desc = "Outline style for objective text.",                                               dbKey = "objectiveFontOutline", options = OUTLINE_OPTIONS },
            },
        },
        {
            key = "Icons",
            name = "Icons & Info",
            options = {
                { type = "section", name = "Icons" },
                { type = "toggle",  name = "Show quest type icons",  desc = "Display icons next to quests and category headers.", dbKey = "showIcons" },
                { type = "section", name = "Information" },
                { type = "toggle",  name = "Show objective numbers", desc = "Append progress numbers (e.g., 3/5) to objectives.", dbKey = "showObjectiveNumbers" },
                { type = "toggle",  name = "Show quest level",       desc = "Prefix quest names with their level.",               dbKey = "showQuestLevel" },
                { type = "toggle",  name = "Show quest count",       desc = "Show number of quests per group in headers.",        dbKey = "showHeaderCount" },
            },
        },
    }
end

----------------------------------------------------------------------
-- Build the full settings panel
----------------------------------------------------------------------
local PAGE_WIDTH = 720
local PAGE_HEIGHT = 600
local SIDEBAR_WIDTH = 180
local PADDING = Def.Padding
local SCROLL_STEP = 44
local HEADER_HEIGHT = PADDING + Def.HeaderSize + 10 + 2
local ROW_HEIGHTS = { toggle = 40, slider = 40, dropdown = 52, sectionLabel = 14 }
local ANIM_DUR = 0.2
local TAB_ROW_HEIGHT = 32

function TTQ:BuildSettingsUI()
    local optionCategories = BuildOptionCategories()

    -- Auto-generate get/set from dbKey when not explicitly provided
    for _, cat in ipairs(optionCategories) do
        for _, opt in ipairs(cat.options) do
            if opt.dbKey and not opt.get then
                local key = opt.dbKey
                opt.get = function() return getDB(key, TTQ.Defaults[key]) end
                opt.set = function(v) setDB(key, v) end
            end
        end
    end

    -- Main panel
    local panel = CreateFrame("Frame", "TTQOptionsPanel", UIParent)
    panel:SetSize(PAGE_WIDTH, PAGE_HEIGHT)
    panel:SetFrameStrata("DIALOG")
    panel:SetClampedToScreen(true)
    panel:SetMovable(true)
    panel:RegisterForDrag("LeftButton")
    panel:Hide()
    self.OptionsPanel = panel

    local bg = panel:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(panel)
    bg:SetColorTexture(Def.SectionCardBg[1], Def.SectionCardBg[2], Def.SectionCardBg[3], 0.97)
    CreateBorder(panel, Def.SectionCardBorder)

    -- Title bar
    local titleBar = CreateFrame("Frame", nil, panel)
    titleBar:SetPoint("TOPLEFT", 0, 0)
    titleBar:SetPoint("TOPRIGHT", 0, 0)
    titleBar:SetHeight(HEADER_HEIGHT)
    titleBar:EnableMouse(true)
    titleBar:RegisterForDrag("LeftButton")
    titleBar:SetScript("OnDragStart", function() panel:StartMoving() end)
    titleBar:SetScript("OnDragStop", function()
        panel:StopMovingOrSizing()
        if TommyTwoquestsDB then
            local x, y = panel:GetCenter()
            local ux, uy = UIParent:GetCenter()
            TommyTwoquestsDB.optionsPanelPos = { x = x - ux, y = y - uy }
        end
    end)
    local titleBg = titleBar:CreateTexture(nil, "BACKGROUND")
    titleBg:SetAllPoints(titleBar)
    titleBg:SetColorTexture(0.07, 0.07, 0.09, 0.96)

    local titleText = titleBar:CreateFontString(nil, "OVERLAY")
    titleText:SetFont(Def.FontPath, Def.HeaderSize, "OUTLINE")
    SetColor(titleText, Def.TextColorTitleBar)
    titleText:SetPoint("TOPLEFT", titleBar, "TOPLEFT", PADDING, -PADDING)
    titleText:SetText("TOMMYTWOQUESTS")

    -- Close button
    local closeBtn = CreateFrame("Button", nil, panel)
    closeBtn:SetSize(28, 28)
    closeBtn:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -10, -10)
    closeBtn:SetFrameLevel(titleBar:GetFrameLevel() + 2)
    local closeBg = closeBtn:CreateTexture(nil, "BACKGROUND")
    closeBg:SetAllPoints(closeBtn)
    closeBg:SetColorTexture(0.12, 0.12, 0.15, 0.5)
    closeBg:Hide()
    local closeLabel = closeBtn:CreateFontString(nil, "OVERLAY")
    closeLabel:SetFont(Def.FontPath, 14, "OUTLINE")
    SetColor(closeLabel, Def.TextColorSection)
    closeLabel:SetText("X")
    closeLabel:SetPoint("CENTER", closeBtn, "CENTER", 0, 0)
    closeBtn:SetScript("OnClick", function() self:CloseOptionsPanel() end)
    closeBtn:SetScript("OnEnter", function()
        closeBg:Show(); SetColor(closeLabel, Def.TextColorHighlight)
    end)
    closeBtn:SetScript("OnLeave", function()
        closeBg:Hide(); SetColor(closeLabel, Def.TextColorSection)
    end)

    -- Divider
    local dividerLine = panel:CreateTexture(nil, "ARTWORK")
    dividerLine:SetPoint("TOPLEFT", titleBar, "BOTTOMLEFT", 0, 0)
    dividerLine:SetPoint("TOPRIGHT", titleBar, "BOTTOMRIGHT", 0, 0)
    dividerLine:SetHeight(1)
    dividerLine:SetColorTexture(Def.AccentColor[1], Def.AccentColor[2], Def.AccentColor[3], 0.25)

    -- Sidebar
    local sidebar = CreateFrame("Frame", nil, panel)
    sidebar:SetPoint("TOPLEFT", panel, "TOPLEFT", PADDING, -(HEADER_HEIGHT + 6))
    sidebar:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", PADDING, PADDING)
    sidebar:SetWidth(SIDEBAR_WIDTH)
    local sidebarBg = sidebar:CreateTexture(nil, "BACKGROUND")
    sidebarBg:SetAllPoints(sidebar)
    sidebarBg:SetColorTexture(0.07, 0.07, 0.09, 0.96)

    -- Version at bottom of sidebar
    local versionLabel = sidebar:CreateFontString(nil, "OVERLAY")
    versionLabel:SetFont(Def.FontPath, Def.SectionSize, "OUTLINE")
    SetColor(versionLabel, Def.TextColorSection)
    versionLabel:SetText("v" .. (self.Version or "1.0.0"))
    versionLabel:SetPoint("BOTTOMLEFT", sidebar, "BOTTOMLEFT", 10, 10)

    local contentWidth = PAGE_WIDTH - PADDING * 2 - SIDEBAR_WIDTH - 12

    -- Search bar
    local searchRow = CreateFrame("Frame", nil, panel)
    searchRow:SetPoint("TOPLEFT", panel, "TOPLEFT", PADDING + SIDEBAR_WIDTH + 12, -(HEADER_HEIGHT + 6))
    searchRow:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -PADDING, 0)
    searchRow:SetHeight(36)

    -- Scroll frame
    local scrollFrame = CreateFrame("ScrollFrame", nil, panel)
    scrollFrame:SetPoint("TOPLEFT", panel, "TOPLEFT", PADDING + SIDEBAR_WIDTH + 12, -(HEADER_HEIGHT + 6 + 40))
    scrollFrame:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -PADDING, PADDING)
    scrollFrame:EnableMouseWheel(true)
    scrollFrame:SetScript("OnMouseWheel", function(_, delta)
        local cur = scrollFrame:GetVerticalScroll()
        local childH = scrollFrame:GetScrollChild() and scrollFrame:GetScrollChild():GetHeight() or 0
        local frameH = scrollFrame:GetHeight() or 0
        scrollFrame:SetVerticalScroll(math.max(0, math.min(cur - delta * SCROLL_STEP, math.max(0, childH - frameH))))
    end)

    -- Tab content frames
    local tabFrames = {}
    for i = 1, #optionCategories do
        local f = CreateFrame("Frame", nil, panel)
        f:SetSize(contentWidth, 3000)
        local top = CreateFrame("Frame", nil, f)
        top:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
        top:SetSize(1, 1)
        f.topAnchor = top
        tabFrames[i] = f
    end
    scrollFrame:SetScrollChild(tabFrames[1])
    for i = 2, #tabFrames do tabFrames[i]:Hide() end

    -- State
    local selectedTab = 1
    local tabButtons = {}
    local allRefreshers = {}
    local optionFrames = {}

    local function UpdateTabVisuals()
        for _, tbtn in ipairs(tabButtons) do
            local sel = (tbtn.categoryIndex == selectedTab)
            tbtn.selected = sel
            SetColor(tbtn.label, sel and Def.TextColorNormal or Def.TextColorSection)
            if tbtn.leftAccent then tbtn.leftAccent:SetShown(sel) end
            if tbtn.highlight then tbtn.highlight:SetShown(sel) end
        end
    end

    -- Build sidebar tabs
    for i, cat in ipairs(optionCategories) do
        local tbtn = CreateFrame("Button", nil, sidebar)
        tbtn:SetSize(SIDEBAR_WIDTH, TAB_ROW_HEIGHT)
        if i == 1 then
            tbtn:SetPoint("TOPLEFT", sidebar, "TOPLEFT", 0, -4)
        else
            tbtn:SetPoint("TOPLEFT", tabButtons[#tabButtons], "BOTTOMLEFT", 0, 0)
        end
        tbtn.categoryIndex = i

        tbtn.label = tbtn:CreateFontString(nil, "OVERLAY")
        tbtn.label:SetFont(Def.FontPath, Def.LabelSize, "OUTLINE")
        tbtn.label:SetPoint("LEFT", tbtn, "LEFT", 12, 0)
        tbtn.label:SetText(cat.name)

        tbtn.highlight = tbtn:CreateTexture(nil, "BACKGROUND")
        tbtn.highlight:SetAllPoints(tbtn)
        tbtn.highlight:SetColorTexture(1, 1, 1, 0.05)

        tbtn.hoverBg = tbtn:CreateTexture(nil, "BACKGROUND")
        tbtn.hoverBg:SetAllPoints(tbtn)
        tbtn.hoverBg:SetColorTexture(1, 1, 1, 0.03)
        tbtn.hoverBg:Hide()

        tbtn.leftAccent = tbtn:CreateTexture(nil, "OVERLAY")
        tbtn.leftAccent:SetWidth(3)
        tbtn.leftAccent:SetColorTexture(Def.AccentColor[1], Def.AccentColor[2], Def.AccentColor[3],
            Def.AccentColor[4] or 0.9)
        tbtn.leftAccent:SetPoint("TOPLEFT", tbtn, "TOPLEFT", 0, 0)
        tbtn.leftAccent:SetPoint("BOTTOMLEFT", tbtn, "BOTTOMLEFT", 0, 0)

        tbtn:SetScript("OnClick", function()
            selectedTab = i
            UpdateTabVisuals()
            for j = 1, #tabFrames do tabFrames[j]:SetShown(j == i) end
            scrollFrame:SetScrollChild(tabFrames[i])
            scrollFrame:SetVerticalScroll(0)
        end)
        tbtn:SetScript("OnEnter", function()
            if not tbtn.selected then
                SetColor(tbtn.label, Def.TextColorHighlight)
                tbtn.hoverBg:Show()
            end
        end)
        tbtn:SetScript("OnLeave", function()
            tbtn.hoverBg:Hide()
            UpdateTabVisuals()
        end)

        tabButtons[#tabButtons + 1] = tbtn
    end

    -- Build category content
    for catIdx, cat in ipairs(optionCategories) do
        local tab = tabFrames[catIdx]
        local anchor = tab.topAnchor
        local currentCard = nil

        for _, opt in ipairs(cat.options) do
            if opt.type == "section" then
                -- Finalize previous card
                if currentCard then
                    currentCard:SetHeight(currentCard.contentHeight + Def.CardPadding)
                end
                currentCard = CreateSectionCard(tab, anchor)
                local hasHeader = opt.name and opt.name ~= ""
                if hasHeader then
                    local lbl = CreateSectionHeader(currentCard, opt.name)
                    lbl:SetPoint("TOPLEFT", currentCard, "TOPLEFT", Def.CardPadding, -Def.CardPadding)
                    currentCard.contentAnchor = lbl
                    currentCard.contentHeight = Def.CardPadding + ROW_HEIGHTS.sectionLabel
                else
                    local spacer = currentCard:CreateFontString(nil, "OVERLAY")
                    spacer:SetPoint("TOPLEFT", currentCard, "TOPLEFT", Def.CardPadding, -Def.CardPadding)
                    spacer:SetHeight(0); spacer:SetWidth(1)
                    currentCard.contentAnchor = spacer
                    currentCard.contentHeight = Def.CardPadding
                end
                anchor = currentCard
            elseif opt.type == "toggle" and currentCard then
                local w = CreateToggleSwitch(currentCard, opt.name, opt.desc, opt.get, opt.set)
                w:SetPoint("TOPLEFT", currentCard.contentAnchor, "BOTTOMLEFT", 0, -Def.OptionGap)
                w:SetPoint("RIGHT", currentCard, "RIGHT", -Def.CardPadding, 0)
                currentCard.contentAnchor = w
                currentCard.contentHeight = currentCard.contentHeight + Def.OptionGap + ROW_HEIGHTS.toggle
                if opt.dbKey then optionFrames[opt.dbKey] = { tabIndex = catIdx, frame = w } end
                allRefreshers[#allRefreshers + 1] = w
            elseif opt.type == "slider" and currentCard then
                local w = CreateSliderWidget(currentCard, opt.name, opt.desc, opt.get, opt.set, opt.min, opt.max,
                    opt.step)
                w:SetPoint("TOPLEFT", currentCard.contentAnchor, "BOTTOMLEFT", 0, -Def.OptionGap)
                w:SetPoint("RIGHT", currentCard, "RIGHT", -Def.CardPadding, 0)
                currentCard.contentAnchor = w
                currentCard.contentHeight = currentCard.contentHeight + Def.OptionGap + ROW_HEIGHTS.slider
                if opt.dbKey then optionFrames[opt.dbKey] = { tabIndex = catIdx, frame = w } end
                allRefreshers[#allRefreshers + 1] = w
            elseif opt.type == "dropdown" and currentCard then
                local opts = opt.options
                local w = CreateDropdownWidget(currentCard, opt.name, opt.desc, opts, opt.get, opt.set)
                w:SetPoint("TOPLEFT", currentCard.contentAnchor, "BOTTOMLEFT", 0, -Def.OptionGap)
                w:SetPoint("RIGHT", currentCard, "RIGHT", -Def.CardPadding, 0)
                currentCard.contentAnchor = w
                currentCard.contentHeight = currentCard.contentHeight + Def.OptionGap + ROW_HEIGHTS.dropdown
                if opt.dbKey then optionFrames[opt.dbKey] = { tabIndex = catIdx, frame = w } end
                allRefreshers[#allRefreshers + 1] = w
            end
        end

        -- Finalize last card
        if currentCard then
            currentCard:SetHeight(currentCard.contentHeight + Def.CardPadding)
        end
    end

    UpdateTabVisuals()

    -- -------- Search --------
    local searchIndex = nil

    local function BuildSearchIndex()
        local index = {}
        for catIdx, cat in ipairs(optionCategories) do
            local currentSection = ""
            for _, opt in ipairs(cat.options) do
                if opt.type == "section" then
                    currentSection = opt.name or ""
                elseif opt.type ~= "section" then
                    local name = (opt.name or ""):lower()
                    local ddesc = (opt.desc or ""):lower()
                    local searchText = name .. " " .. ddesc .. " " .. (currentSection or ""):lower()
                    local optionId = opt.dbKey or (cat.key .. "_" .. (opt.name or ""):gsub("%s+", "_"))
                    index[#index + 1] = {
                        categoryName = cat.name,
                        categoryIndex = catIdx,
                        sectionName = currentSection,
                        option = opt,
                        optionId = optionId,
                        searchText = searchText,
                    }
                end
            end
        end
        return index
    end

    -- Search dropdown
    local searchDropdown = CreateFrame("Frame", nil, panel)
    searchDropdown:SetFrameStrata("DIALOG")
    searchDropdown:SetFrameLevel(panel:GetFrameLevel() + 10)
    searchDropdown:SetPoint("TOPLEFT", searchRow, "BOTTOMLEFT", 0, -2)
    searchDropdown:SetPoint("TOPRIGHT", searchRow, "BOTTOMRIGHT", 0, 0)
    searchDropdown:SetHeight(240)
    searchDropdown:EnableMouse(true)
    searchDropdown:Hide()
    local sdBg = searchDropdown:CreateTexture(nil, "BACKGROUND")
    sdBg:SetAllPoints(searchDropdown)
    sdBg:SetColorTexture(Def.SectionCardBg[1], Def.SectionCardBg[2], Def.SectionCardBg[3], 0.98)
    CreateBorder(searchDropdown, Def.SectionCardBorder)

    local searchDropdownScroll = CreateFrame("ScrollFrame", nil, searchDropdown)
    searchDropdownScroll:SetPoint("TOPLEFT", searchDropdown, "TOPLEFT", 6, -6)
    searchDropdownScroll:SetPoint("BOTTOMRIGHT", searchDropdown, "BOTTOMRIGHT", -6, 6)
    searchDropdownScroll:EnableMouseWheel(true)
    local searchDropdownContent = CreateFrame("Frame", nil, searchDropdownScroll)
    searchDropdownContent:SetSize(1, 1)
    searchDropdownScroll:SetScrollChild(searchDropdownContent)
    searchDropdownScroll:SetScript("OnMouseWheel", function(_, delta)
        local cur = searchDropdownScroll:GetVerticalScroll()
        local childH = searchDropdownContent:GetHeight() or 0
        local frameH = searchDropdownScroll:GetHeight() or 0
        searchDropdownScroll:SetVerticalScroll(math.max(0, math.min(cur - delta * 24, math.max(0, childH - frameH))))
    end)

    local searchDropdownButtons = {}
    local searchDropdownCatch = CreateFrame("Button", nil, UIParent)
    searchDropdownCatch:SetAllPoints(UIParent)
    searchDropdownCatch:SetFrameStrata("DIALOG")
    searchDropdownCatch:SetFrameLevel(panel:GetFrameLevel() + 5)
    searchDropdownCatch:Hide()

    local searchInput -- forward declaration for closures

    local function HideSearchDropdown()
        searchDropdown:Hide(); searchDropdownCatch:Hide()
    end
    searchDropdownCatch:SetScript("OnClick", HideSearchDropdown)

    local SEARCH_ROW_H = 34
    local function NavigateToOption(entry)
        if not entry or not entry.optionId then return end
        local reg = optionFrames[entry.optionId]
        if not reg or not reg.frame then return end
        selectedTab = reg.tabIndex
        UpdateTabVisuals()
        for j = 1, #tabFrames do tabFrames[j]:SetShown(j == selectedTab) end
        scrollFrame:SetScrollChild(tabFrames[selectedTab])
        local frame = reg.frame
        local child = scrollFrame:GetScrollChild()
        if child and frame then
            local fTop = frame:GetTop()
            local cTop = child:GetTop()
            if fTop and cTop then
                scrollFrame:SetVerticalScroll(math.max(0, cTop - fTop - 40))
            end
        end
        -- Flash effect
        if frame and frame.SetAlpha then
            frame:SetAlpha(0.5)
            C_Timer.After(0.5, function() if frame and frame.SetAlpha then frame:SetAlpha(1) end end)
        end
    end

    local function ShowSearchResults(matches)
        if not matches or #matches == 0 then
            HideSearchDropdown()
            return
        end
        local num = math.min(#matches, 12)
        for i = 1, num do
            if not searchDropdownButtons[i] then
                local b = CreateFrame("Button", nil, searchDropdownContent)
                b:SetHeight(SEARCH_ROW_H)
                b:SetPoint("LEFT", searchDropdownContent, "LEFT", 0, 0)
                b:SetPoint("RIGHT", searchDropdownContent, "RIGHT", 0, 0)
                b.subLabel = b:CreateFontString(nil, "OVERLAY")
                b.subLabel:SetFont(Def.FontPath, Def.SectionSize, "OUTLINE")
                b.subLabel:SetPoint("TOPLEFT", b, "TOPLEFT", 8, -4)
                b.subLabel:SetJustifyH("LEFT")
                SetColor(b.subLabel, Def.TextColorSection)
                b.label = b:CreateFontString(nil, "OVERLAY")
                b.label:SetFont(Def.FontPath, Def.LabelSize, "OUTLINE")
                b.label:SetPoint("TOPLEFT", b.subLabel, "BOTTOMLEFT", 0, -1)
                b.label:SetJustifyH("LEFT")
                local hi = b:CreateTexture(nil, "BACKGROUND")
                hi:SetAllPoints(b)
                hi:SetColorTexture(1, 1, 1, 0.08)
                hi:Hide()
                b:SetScript("OnEnter", function()
                    hi:Show(); SetColor(b.label, Def.TextColorHighlight)
                end)
                b:SetScript("OnLeave", function()
                    hi:Hide(); SetColor(b.label, Def.TextColorLabel)
                end)
                searchDropdownButtons[i] = b
            end
            local b = searchDropdownButtons[i]
            local m = matches[i]
            b.subLabel:SetText((m.categoryName or "") .. " \194\187 " .. (m.sectionName or ""))
            b.label:SetText(m.option and m.option.name or "")
            b:SetPoint("TOP", searchDropdownContent, "TOP", 0, -(i - 1) * SEARCH_ROW_H)
            b:SetScript("OnClick", function()
                NavigateToOption(m)
                HideSearchDropdown()
                if searchInput and searchInput.edit then searchInput.edit:ClearFocus() end
            end)
            b:Show()
        end
        for i = num + 1, #searchDropdownButtons do
            searchDropdownButtons[i]:Hide()
        end
        searchDropdownContent:SetHeight(num * SEARCH_ROW_H)
        searchDropdownContent:SetWidth((searchDropdown:GetWidth() or 1) - 12)
        searchDropdownScroll:SetVerticalScroll(0)
        searchDropdown:Show()
        searchDropdownCatch:Show()
    end

    local searchDebounceTimer = nil
    local function FilterBySearch(query)
        query = query and query:match("^%s*(.-)%s*$"):lower() or ""
        if query == "" then
            HideSearchDropdown(); return
        end
        if #query < 2 then
            HideSearchDropdown(); return
        end
        if not searchIndex then searchIndex = BuildSearchIndex() end
        local matches = {}
        for _, entry in ipairs(searchIndex) do
            if entry.searchText:find(query, 1, true) then
                matches[#matches + 1] = entry
            end
        end
        ShowSearchResults(matches)
    end

    local function OnSearchTextChanged(text)
        if searchDebounceTimer then
            if searchDebounceTimer.Cancel then searchDebounceTimer:Cancel() end
            searchDebounceTimer = nil
        end
        if C_Timer and C_Timer.NewTimer then
            searchDebounceTimer = C_Timer.NewTimer(0.18, function()
                searchDebounceTimer = nil
                FilterBySearch(text)
            end)
        else
            FilterBySearch(text)
        end
    end

    searchInput = CreateSearchInput(searchRow, OnSearchTextChanged, "Search settings...")
    searchInput.edit:SetScript("OnEscapePressed", function()
        searchInput.edit:SetText("")
        if searchInput.edit.placeholder then searchInput.edit.placeholder:Show() end
        if searchInput.clearBtn then searchInput.clearBtn:Hide() end
        FilterBySearch("")
        HideSearchDropdown()
        searchInput.edit:ClearFocus()
    end)

    -- OnShow animation
    panel:SetScript("OnShow", function()
        -- Position
        if TommyTwoquestsDB and TommyTwoquestsDB.optionsPanelPos then
            panel:ClearAllPoints()
            panel:SetPoint("CENTER", UIParent, "CENTER", TommyTwoquestsDB.optionsPanelPos.x,
                TommyTwoquestsDB.optionsPanelPos.y)
        else
            panel:ClearAllPoints()
            panel:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        end
        -- Refresh all widgets
        for _, ref in ipairs(allRefreshers) do if ref and ref.Refresh then ref:Refresh() end end
        -- Fade-in
        panel:SetAlpha(0)
        panel.animStart = GetTime()
        panel:SetScript("OnUpdate", function(self)
            local elapsed = GetTime() - self.animStart
            if elapsed >= ANIM_DUR then
                self:SetAlpha(1); self:SetScript("OnUpdate", nil); return
            end
            self:SetAlpha(easeOut(elapsed / ANIM_DUR))
        end)
    end)

    panel:SetScript("OnHide", function()
    end)
end

----------------------------------------------------------------------
-- Open / close helpers
----------------------------------------------------------------------
function TTQ:OpenSettings()
    local panel = self.OptionsPanel
    if not panel then return end
    if panel:IsShown() then
        self:CloseOptionsPanel()
    else
        panel:Show()
    end
end

function TTQ:CloseOptionsPanel()
    local panel = self.OptionsPanel
    if not panel or not panel:IsShown() then return end
    panel.animStart = GetTime()
    panel:SetScript("OnUpdate", function(self)
        local elapsed = GetTime() - self.animStart
        if elapsed >= 0.2 then
            self:SetAlpha(1)
            self:SetScript("OnUpdate", nil)
            self:Hide()
            return
        end
        self:SetAlpha(1 - easeOut(elapsed / 0.2))
    end)
end

----------------------------------------------------------------------
-- Callback when any setting changes — refresh tracker
----------------------------------------------------------------------
function TTQ:OnSettingChanged(key, value)
    -- Refresh backdrop if appearance changed
    if key == "showBackground" or key == "bgAlpha" or key == "bgColor" or key == "classColorGradient" then
        if self.UpdateTrackerBackdrop then self:UpdateTrackerBackdrop() end
    end

    -- Refresh abandon button visibility
    if key == "showAbandonAllButton" then
        if self.UpdateAbandonButtonVisibility then self:UpdateAbandonButtonVisibility() end
    end

    -- Refresh tracker width
    if key == "trackerWidth" and self.Tracker then
        self.Tracker:SetWidth(value)
    end

    -- Throttle tracker refresh (avoids 60fps rebuild storms from slider drags)
    if self.Tracker then
        self:ScheduleRefresh()
    end
end
