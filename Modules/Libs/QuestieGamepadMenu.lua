---@class QuestieGamepadMenu
local QuestieGamepadMenu = QuestieLoader:CreateModule("QuestieGamepadMenu")

-- In gamepad mode, Blizzard's menu runs gamepad code (the prompt footer, smart navigation and the interact target) when it opens
-- and closes. Opened from Questie, that code runs with Questie's taint and Forever blocks it: BugSack showed
-- "SmartNavigation.lua:1042: ... tainted by 'Questie'", "Questie tried to call the protected function
-- SetPreferredGamepadInteractTarget()" and a secret value error in InputPrompts.lua from Menu.lua's footer on Forever (Interface 16001).
-- So in gamepad mode Questie's menus are drawn with these plain frames, which Blizzard's gamepad code doesn't know about.

local BUTTON_HEIGHT = 20
local DIVIDER_HEIGHT = 9
local PADDING = 8
local CHECK_WIDTH = 18
local ARROW_WIDTH = 14
local MIN_WIDTH = 120
local MAX_WIDTH = 420

---@type Frame[] One frame per menu level, the root menu is level 1
local levels = {}
---@type Frame? The frame the root menu was opened from
local menuAnchor

local _Close, _CloseFrom, _Refresh, _OpenLevel

---@param value any
---@return any
local function _Resolve(value)
    if type(value) == "function" then
        return value()
    end
    return value
end

---@param entry MenuBuilderEntry
---@return string
local function _GetLabel(entry)
    if entry.icon then
        return "|T" .. entry.icon .. ":16|t " .. entry.text
    end
    return entry.text
end

---@param fontString FontString
---@return number
local function _GetTextWidth(fontString)
    local width = fontString:GetStringWidth()
    if (not width) or (issecretvalue and issecretvalue(width)) then
        return MIN_WIDTH
    end
    return width
end

---@return boolean
function QuestieGamepadMenu.IsGamepadActive()
    return InputUtil ~= nil and InputUtil.IsGamepadUIEnabled ~= nil and InputUtil.IsGamepadUIEnabled() == true
end

---Closes the menus when a click lands outside of them.
local function _OnGlobalMouseDown()
    for _, levelFrame in ipairs(levels) do
        if levelFrame:IsShown() and levelFrame:IsMouseOver() then
            return
        end
    end
    -- A click on the frame the menu came from toggles the menu in that frame's own OnClick
    if menuAnchor and menuAnchor.IsMouseOver and menuAnchor:IsMouseOver() then
        return
    end
    _Close()
end

---@param level number
---@return Frame
local function _GetLevelFrame(level)
    local frame = levels[level]
    if frame then
        return frame
    end

    frame = CreateFrame("Frame", "QuestieGamepadMenu" .. level, UIParent, "BackdropTemplate")
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    frame:SetFrameLevel(100 + level * 10)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = {left = 4, right = 4, top = 4, bottom = 4},
    })
    frame:SetBackdropColor(0.05, 0.05, 0.05, 0.95)
    frame:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)
    frame:Hide()
    frame.level = level
    frame.rows = {}
    levels[level] = frame

    if level == 1 then
        frame:SetScript("OnEvent", _OnGlobalMouseDown)
        frame:SetScript("OnShow", function(self)
            self:RegisterEvent("GLOBAL_MOUSE_DOWN")
        end)
        frame:SetScript("OnHide", function(self)
            self:UnregisterEvent("GLOBAL_MOUSE_DOWN")
            _CloseFrom(2)
        end)
    end

    return frame
end

---@param row Button
local function _OnRowEnter(row)
    local entry = row.entry
    if (not entry) or entry.isDivider or entry.isTitle then
        return
    end
    local level = row:GetParent().level
    if entry.menuList and row.enabled then
        _OpenLevel(level + 1, entry.menuList, row)
    else
        _CloseFrom(level + 1)
    end
end

---@param row Button
---@param mouseButton string
local function _OnRowClick(row, mouseButton)
    local entry = row.entry
    if (not entry) or (not row.enabled) or entry.isDivider or entry.isTitle then
        return
    end
    if entry.menuList then
        _OpenLevel(row:GetParent().level + 1, entry.menuList, row)
        return
    end

    local response
    if entry.func then
        response = entry.func(mouseButton)
    end
    if type(response) ~= "number" then
        response = entry.keepShownOnClick and MenuResponse.Refresh or MenuResponse.CloseAll
    end

    if response == MenuResponse.Refresh or response == MenuResponse.Open then
        _Refresh()
    else
        _Close()
    end
end

---@param frame Frame
---@param index number
---@return Button
local function _GetRow(frame, index)
    local row = frame.rows[index]
    if row then
        return row
    end

    row = CreateFrame("Button", nil, frame)
    row:SetHeight(BUTTON_HEIGHT)
    row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")

    row.check = row:CreateTexture(nil, "ARTWORK")
    row.check:SetSize(16, 16)
    row.check:SetPoint("LEFT", row, "LEFT", 0, 0)
    row.check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")

    row.arrow = row:CreateTexture(nil, "ARTWORK")
    row.arrow:SetSize(12, 12)
    row.arrow:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    row.arrow:SetTexture("Interface\\ChatFrame\\ChatFrameExpandArrow")

    row.divider = row:CreateTexture(nil, "ARTWORK")
    row.divider:SetHeight(1)
    row.divider:SetPoint("LEFT", row, "LEFT", 0, 0)
    row.divider:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    row.divider:SetColorTexture(0.5, 0.5, 0.5, 0.8)

    -- Named fontString like the buttons of Blizzard's menu, so entry initializers work on both
    row.fontString = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.fontString:SetJustifyH("LEFT")
    row.fontString:SetWordWrap(false)

    row:SetScript("OnEnter", _OnRowEnter)
    row:SetScript("OnClick", _OnRowClick)

    frame.rows[index] = row
    return row
end

---Re-evaluates checked, disabled and the initializer of a row.
---@param row Button
local function _UpdateRow(row)
    local entry = row.entry
    if entry.isDivider then
        return
    end

    if entry.isTitle then
        row.enabled = false
        row.fontString:SetTextColor(1, 0.82, 0)
    else
        row.enabled = (not _Resolve(entry.disabled))
        if row.enabled then
            row.fontString:SetTextColor(1, 1, 1)
        else
            row.fontString:SetTextColor(0.5, 0.5, 0.5)
        end
    end

    row.check:SetShown(entry.checked ~= nil and _Resolve(entry.checked) and true or false)

    if entry.initializer then
        entry.initializer(row)
    end
end

---@param row Button
---@param entry MenuBuilderEntry
---@param textLeft number
---@return number textWidth
local function _SetupRow(row, entry, textLeft)
    row.entry = entry
    row.fontString:ClearAllPoints()
    row.fontString:SetPoint("LEFT", row, "LEFT", textLeft, 0)
    row.fontString:SetPoint("RIGHT", row, "RIGHT", -ARROW_WIDTH, 0)

    if entry.isDivider then
        row:SetHeight(DIVIDER_HEIGHT)
        row.fontString:SetText("")
        row.divider:Show()
        row.check:Hide()
        row.arrow:Hide()
        row:EnableMouse(false)
        row.enabled = false
        return 0
    end

    row:SetHeight(BUTTON_HEIGHT)
    row.divider:Hide()
    -- Rows are reused, and an initializer of an earlier menu may have changed the font, like the font dropdown's previews
    row.fontString:SetFontObject("GameFontHighlightSmall")
    row.fontString:SetText(_GetLabel(entry))
    row.arrow:SetShown(entry.menuList ~= nil)
    row:EnableMouse(not entry.isTitle)
    if entry.registerForRightClick then
        row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    else
        row:RegisterForClicks("LeftButtonUp")
    end
    _UpdateRow(row)
    return _GetTextWidth(row.fontString)
end

---@param level number
---@param entries MenuBuilderEntry[]
---@param parentRow Button? Row of the parent level that opens this submenu
---@param anchorFrame Frame?
---@param point FramePoint?
---@param relativePoint FramePoint?
_OpenLevel = function(level, entries, parentRow, anchorFrame, point, relativePoint)
    _CloseFrom(level + 1)

    local frame = _GetLevelFrame(level)
    if frame:IsShown() and frame.entries == entries then
        return
    end
    frame.entries = entries

    local textLeft = 0
    for _, entry in ipairs(entries) do
        if entry.checked ~= nil then
            textLeft = CHECK_WIDTH
            break
        end
    end

    local maxTextWidth = 0
    local y = -PADDING
    for index, entry in ipairs(entries) do
        local row = _GetRow(frame, index)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", frame, "TOPLEFT", PADDING, y)
        row:SetPoint("RIGHT", frame, "RIGHT", -PADDING, 0)
        maxTextWidth = math.max(maxTextWidth, _SetupRow(row, entry, textLeft))
        row:Show()
        y = y - row:GetHeight()
    end

    for index = #entries + 1, #frame.rows do
        frame.rows[index]:Hide()
        frame.rows[index].entry = nil
    end

    local width = textLeft + maxTextWidth + ARROW_WIDTH + PADDING * 2 + 4
    frame:SetWidth(math.min(MAX_WIDTH, math.max(MIN_WIDTH, width)))
    frame:SetHeight(PADDING - y)

    frame:ClearAllPoints()
    if parentRow then
        frame:SetPoint("TOPLEFT", parentRow, "TOPRIGHT", PADDING, PADDING)
    elseif anchorFrame then
        frame:SetPoint(point or "TOPLEFT", anchorFrame, relativePoint or "TOPRIGHT")
    else
        local scale = UIParent:GetEffectiveScale()
        local cursorX, cursorY = GetCursorPosition()
        frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", cursorX / scale, cursorY / scale)
    end

    frame:Show()
end

---@param level number Closes this level and every level below it
_CloseFrom = function(level)
    for index = #levels, level, -1 do
        local frame = levels[index]
        if frame:IsShown() then
            frame:Hide()
            frame.entries = nil
        end
    end
end

_Close = function()
    _CloseFrom(1)
    menuAnchor = nil
end

_Refresh = function()
    for _, frame in ipairs(levels) do
        if frame:IsShown() then
            for _, row in ipairs(frame.rows) do
                if row:IsShown() and row.entry then
                    _UpdateRow(row)
                end
            end
        end
    end
end

---Opens the entries at the cursor, or next to the anchor frame when one is given. Takes the same entries as QuestieMenuBuilder.
---@param entries MenuBuilderEntry[]
---@param anchorFrame Frame?
---@param point FramePoint? Point of the menu to attach, defaults to "TOPLEFT"
---@param relativePoint FramePoint? Point of the anchor frame to attach to, defaults to "TOPRIGHT"
function QuestieGamepadMenu.Show(entries, anchorFrame, point, relativePoint)
    _Close()
    menuAnchor = anchorFrame
    _OpenLevel(1, entries, nil, anchorFrame, point, relativePoint)
end

function QuestieGamepadMenu.Close()
    _Close()
end

---@param anchorFrame Frame
---@return boolean
function QuestieGamepadMenu.IsOpenFrom(anchorFrame)
    return QuestieGamepadMenu.IsOpen() and menuAnchor == anchorFrame
end

---@return boolean
function QuestieGamepadMenu.IsOpen()
    local root = levels[1]
    return root ~= nil and root:IsShown()
end
