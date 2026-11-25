dofile("setupTests.lua")

describe("QuestieGamepadMenu", function()
    ---@type QuestieGamepadMenu
    local QuestieGamepadMenu
    local frames
    local saved = {}
    local globalNames = {"CreateFrame", "UIParent", "InputUtil", "GetCursorPosition", "MenuResponse"}

    local function MockRegion()
        local region = {shown = true, scripts = {}, events = {}, points = {}}
        function region:Show()
            local wasShown = self.shown
            self.shown = true
            if (not wasShown) and self.scripts.OnShow then self.scripts.OnShow(self) end
        end
        function region:Hide()
            local wasShown = self.shown
            self.shown = false
            if wasShown and self.scripts.OnHide then self.scripts.OnHide(self) end
        end
        function region:IsShown() return self.shown end
        function region:SetShown(shown) if shown then self:Show() else self:Hide() end end
        function region:SetScript(name, callback) self.scripts[name] = callback end
        function region:RegisterEvent(event) self.events[event] = true end
        function region:UnregisterEvent(event) self.events[event] = nil end
        function region:SetHeight(height) self.height = height end
        function region:GetHeight() return self.height end
        function region:SetWidth(width) self.width = width end
        function region:SetText(text) self.text = text end
        function region:GetStringWidth() return #(self.text or "") * 6 end
        function region:SetTextColor(r, g, b) self.color = {r, g, b} end
        function region:SetPoint(...) self.points[#self.points + 1] = {...} end
        function region:ClearAllPoints() self.points = {} end
        function region:GetParent() return self.parent end
        function region:IsMouseOver() return self.mouseOver == true end
        function region:EnableMouse(enabled) self.mouseEnabled = enabled end
        function region:RegisterForClicks(...) self.clicks = {...} end
        function region:CreateTexture() return MockRegion() end
        function region:CreateFontString() return MockRegion() end
        return setmetatable(region, {__index = function() return function() end end})
    end

    ---@return table row
    local function Row(level, index)
        return frames["QuestieGamepadMenu" .. level].rows[index]
    end

    before_each(function()
        for _, name in ipairs(globalNames) do
            saved[name] = _G[name]
        end
        frames = {}
        _G.CreateFrame = function(_, name, parent)
            local frame = MockRegion()
            frame.parent = parent
            if name then frames[name] = frame end
            return frame
        end
        _G.UIParent = MockRegion()
        _G.UIParent.GetEffectiveScale = function() return 2 end
        _G.GetCursorPosition = function() return 200, 600 end
        _G.InputUtil = {IsGamepadUIEnabled = function() return true end}
        _G.MenuResponse = {Open = 1, Refresh = 2, Close = 3, CloseAll = 4}

        QuestieLoader._modules["QuestieGamepadMenu"] = nil
        dofile("Modules/Libs/QuestieGamepadMenu.lua")
        QuestieGamepadMenu = QuestieLoader:ImportModule("QuestieGamepadMenu")
    end)

    after_each(function()
        for _, name in ipairs(globalNames) do
            _G[name] = saved[name]
        end
    end)

    describe("IsGamepadActive", function()
        it("should follow InputUtil.IsGamepadUIEnabled", function()
            assert.is_true(QuestieGamepadMenu.IsGamepadActive())
            _G.InputUtil.IsGamepadUIEnabled = function() return false end
            assert.is_false(QuestieGamepadMenu.IsGamepadActive())
        end)

        it("should be false when the client has no InputUtil", function()
            _G.InputUtil = nil
            assert.is_false(QuestieGamepadMenu.IsGamepadActive())
        end)
    end)

    it("should open at the cursor and report itself as open", function()
        QuestieGamepadMenu.Show({{text = "A"}})

        assert.is_true(QuestieGamepadMenu.IsOpen())
        assert.are.same({"TOPLEFT", UIParent, "BOTTOMLEFT", 100, 300}, frames.QuestieGamepadMenu1.points[1])
        assert.is_true(frames.QuestieGamepadMenu1.events.GLOBAL_MOUSE_DOWN)
    end)

    it("should open at the given points of the anchor frame", function()
        local anchorFrame = MockRegion()
        QuestieGamepadMenu.Show({{text = "A"}}, anchorFrame, "TOPLEFT", "BOTTOMLEFT")

        assert.are.same({"TOPLEFT", anchorFrame, "BOTTOMLEFT"}, frames.QuestieGamepadMenu1.points[1])
    end)

    it("should prefix the label with the icon and color titles and disabled entries", function()
        QuestieGamepadMenu.Show({
            {text = "T", isTitle = true},
            {text = "B", icon = "Interface\\Icons\\x"},
            {text = "D", disabled = function() return true end},
        })

        assert.are.same({1, 0.82, 0}, Row(1, 1).fontString.color)
        assert.are.equal("|TInterface\\Icons\\x:16|t B", Row(1, 2).fontString.text)
        assert.are.same({0.5, 0.5, 0.5}, Row(1, 3).fontString.color)
    end)

    it("should ignore clicks on titles, dividers and disabled entries", function()
        local func = spy.new(function() end)
        QuestieGamepadMenu.Show({{text = "T", isTitle = true, func = func}, {isDivider = true}, {text = "D", disabled = true, func = func}})

        Row(1, 1).scripts.OnClick(Row(1, 1), "LeftButton")
        Row(1, 2).scripts.OnClick(Row(1, 2), "LeftButton")
        Row(1, 3).scripts.OnClick(Row(1, 3), "LeftButton")

        assert.spy(func).was.not_called()
        assert.is_true(QuestieGamepadMenu.IsOpen())
    end)

    it("should call func with the mouse button and close after a click by default", function()
        local func = spy.new(function() end)
        QuestieGamepadMenu.Show({{text = "B", func = func}})

        Row(1, 1).scripts.OnClick(Row(1, 1), "LeftButton")

        assert.spy(func).was.called_with("LeftButton")
        assert.is_false(QuestieGamepadMenu.IsOpen())
    end)

    it("should stay open and redraw checkboxes when keepShownOnClick is set", function()
        local value = true
        QuestieGamepadMenu.Show({
            {text = "C", checked = function() return value end, keepShownOnClick = true, func = function() value = false end},
        })
        assert.is_true(Row(1, 1).check.shown)

        Row(1, 1).scripts.OnClick(Row(1, 1), "LeftButton")

        assert.is_true(QuestieGamepadMenu.IsOpen())
        assert.is_false(Row(1, 1).check.shown)
    end)

    it("should prefer the response returned by func", function()
        QuestieGamepadMenu.Show({{text = "B", keepShownOnClick = true, func = function() return MenuResponse.CloseAll end}})

        Row(1, 1).scripts.OnClick(Row(1, 1), "LeftButton")

        assert.is_false(QuestieGamepadMenu.IsOpen())
    end)

    it("should register right clicks and run the initializer with the row", function()
        local initializer = spy.new(function() end)
        QuestieGamepadMenu.Show({{text = "B", registerForRightClick = true, initializer = initializer}, {text = "C"}})

        assert.are.same({"LeftButtonUp", "RightButtonUp"}, Row(1, 1).clicks)
        assert.are.same({"LeftButtonUp"}, Row(1, 2).clicks)
        assert.spy(initializer).was.called_with(Row(1, 1))
        assert.is_not_nil(Row(1, 1).fontString)
    end)

    it("should open a submenu on hover and close it when another entry is hovered", function()
        local childFunc = spy.new(function() end)
        QuestieGamepadMenu.Show({{text = "Parent", menuList = {{text = "Child", func = childFunc}}}, {text = "Other"}})

        Row(1, 1).scripts.OnEnter(Row(1, 1))
        assert.is_true(frames.QuestieGamepadMenu2:IsShown())
        assert.are.equal("Child", Row(2, 1).fontString.text)

        Row(1, 2).scripts.OnEnter(Row(1, 2))
        assert.is_false(frames.QuestieGamepadMenu2:IsShown())

        Row(1, 1).scripts.OnEnter(Row(1, 1))
        Row(2, 1).scripts.OnClick(Row(2, 1), "LeftButton")
        assert.spy(childFunc).was.called_with("LeftButton")
        assert.is_false(QuestieGamepadMenu.IsOpen())
        assert.is_false(frames.QuestieGamepadMenu2:IsShown())
    end)

    it("should hide the rows that a shorter menu doesn't use", function()
        QuestieGamepadMenu.Show({{text = "A"}, {text = "B"}})
        QuestieGamepadMenu.Show({{text = "C"}})

        assert.is_true(Row(1, 1):IsShown())
        assert.is_false(Row(1, 2):IsShown())
    end)

    it("should close on a click outside of the menus", function()
        QuestieGamepadMenu.Show({{text = "A"}})

        frames.QuestieGamepadMenu1.scripts.OnEvent(frames.QuestieGamepadMenu1, "GLOBAL_MOUSE_DOWN")

        assert.is_false(QuestieGamepadMenu.IsOpen())
        assert.is_nil(frames.QuestieGamepadMenu1.events.GLOBAL_MOUSE_DOWN)
    end)

    it("should stay open on a click inside the menu or on its anchor frame", function()
        local anchorFrame = MockRegion()
        QuestieGamepadMenu.Show({{text = "A"}}, anchorFrame)
        local root = frames.QuestieGamepadMenu1

        root.mouseOver = true
        root.scripts.OnEvent(root, "GLOBAL_MOUSE_DOWN")
        assert.is_true(QuestieGamepadMenu.IsOpen())

        root.mouseOver = false
        anchorFrame.mouseOver = true
        root.scripts.OnEvent(root, "GLOBAL_MOUSE_DOWN")
        assert.is_true(QuestieGamepadMenu.IsOpen())
    end)

    it("should close every level", function()
        QuestieGamepadMenu.Show({{text = "Parent", menuList = {{text = "Child"}}}})
        Row(1, 1).scripts.OnEnter(Row(1, 1))

        QuestieGamepadMenu.Close()

        assert.is_false(QuestieGamepadMenu.IsOpen())
        assert.is_false(frames.QuestieGamepadMenu2:IsShown())
    end)
end)
