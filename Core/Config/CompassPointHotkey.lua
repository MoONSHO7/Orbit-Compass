local _, Addon = ...
local L = Addon.L
local ACTION = "ORBIT_COMPASS_TOGGLE_POINTS"
local ROW_HEIGHT = 26
local BUTTON_WIDTH = 140
local BUTTON_HEIGHT = 22
local LAYOUT_PADDING = 10
local LABEL_GAP = 8
local SECTION_GAP = 14
local SELECTION_TEXTURE = 921208
local SELECTION_OFFSET_Y = -3

local function Refresh(button)
    local key = GetBindingKey(ACTION)
    button:SetText(
        button.listening and L.PLU_COMPASS_PRESS_KEY
            or (key and GetBindingText(key) or GRAY_FONT_COLOR:WrapTextInColorCode(L.PLU_COMPASS_UNBOUND))
    )
    button.selectedHighlight:SetShown(button.listening)
end

local function StopListening(button)
    button.listening = false
    button:EnableKeyboard(false)
    button:EnableMouseWheel(false)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    Refresh(button)
end

local function SaveKey(button, newKey)
    if InCombatLockdown() then
        StopListening(button)
        return
    end
    local key1, key2 = GetBindingKey(ACTION)
    if not newKey or SetBinding(newKey, ACTION) then
        if key1 and key1 ~= newKey then
            SetBinding(key1)
        end
        if key2 and key2 ~= newKey then
            SetBinding(key2)
        end
        SaveBindings(GetCurrentBindingSet())
    end
    StopListening(button)
end

local function ProcessInput(button, input)
    if not button.listening then
        return
    end
    local key = GetConvertedKeyOrButton(input)
    if key == "ESCAPE" or InCombatLockdown() then
        StopListening(button)
    elseif not IsKeyPressIgnoredForBinding(key) then
        SaveKey(button, CreateKeyChordStringUsingMetaKeyState(key))
    end
end

local function CreateHotkey(layout, container)
    local frame = CreateFrame("Frame", nil, container)
    frame.OrbitType = "CompassPointHotkey"
    frame.label = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    frame.label:SetJustifyH("LEFT")
    frame.label:SetWordWrap(true)
    frame.label:SetText(L.PLU_COMPASS_POINT_HOTKEY .. ":")
    local button = CreateFrame("Button", nil, frame, "UIMenuButtonStretchTemplate")
    frame.button = button
    button.selectedHighlight = button:CreateTexture(nil, "OVERLAY")
    button.selectedHighlight:SetTexture(SELECTION_TEXTURE)
    button.selectedHighlight:SetBlendMode("ADD")
    layout.pixel:Point(button.selectedHighlight, "CENTER", button, "CENTER", 0, SELECTION_OFFSET_Y)
    button:SetScript("OnKeyDown", ProcessInput)
    button:SetScript("OnMouseWheel", function(self, delta)
        ProcessInput(self, delta > 0 and "MOUSEWHEELUP" or "MOUSEWHEELDOWN")
    end)
    button:SetScript("OnClick", function(self, mouseButton, isDown)
        if self.listening then
            if isDown then
                ProcessInput(self, mouseButton)
            end
        elseif not InCombatLockdown() then
            if mouseButton == "RightButton" then
                SaveKey(self)
            else
                self.listening = true
                self:RegisterForClicks("AnyDown", "AnyUp")
                self:EnableKeyboard(true)
                self:EnableMouseWheel(true)
                self:SetPropagateKeyboardInput(false)
                Refresh(self)
            end
        end
    end)
    button:SetScript("OnEnter", function(self)
        local tooltip = layout.tooltip
        tooltip:SetOwner(self, "ANCHOR_RIGHT")
        tooltip:SetText(L.PLU_COMPASS_POINT_HOTKEY)
        tooltip:AddLine(L.PLU_COMPASS_POINT_HOTKEY_TT, 1, 1, 1, true)
        tooltip:Show()
    end)
    button:SetScript("OnLeave", layout.tooltipHide)
    frame:SetScript("OnShow", function()
        frame:RegisterEvent("UPDATE_BINDINGS")
        frame:RegisterEvent("PLAYER_REGEN_DISABLED")
        Refresh(button)
    end)
    frame:SetScript("OnHide", function()
        frame:UnregisterAllEvents()
        StopListening(button)
        layout.tooltipHide()
    end)
    frame:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_REGEN_DISABLED" then
            StopListening(button)
        else
            Refresh(button)
        end
    end)
    StopListening(button)
    frame:Hide()
    return frame
end

function Addon.RegisterPointHotkeyWidget(layout)
    if layout:HasWidgetType("compasspointhotkey") then
        return
    end
    layout:RegisterControlPool("CompassPointHotkey", "compassPointHotkeyPool")
    layout:RegisterWidgetType("compasspointhotkey", function(container)
        local frame = table.remove(layout.compassPointHotkeyPool) or CreateHotkey(layout, container)
        frame:SetParent(container)
        local pixel = layout.pixel
        local scale = frame:GetEffectiveScale()
        local width = pixel:Snap(container:GetWidth() - LAYOUT_PADDING * 2, scale)
        local buttonWidth = pixel:Snap(BUTTON_WIDTH, scale)
        frame:SetWidth(width)
        frame.label:SetWidth(0)
        frame.label:SetWidth(
            pixel:Snap(
                math.min(frame.label:GetStringWidth(), width - buttonWidth - pixel:Multiple(LABEL_GAP, scale)),
                scale
            )
        )
        local labelHeight = frame.label:GetStringHeight()
        local rowHeight = pixel:Snap(math.max(ROW_HEIGHT, labelHeight), scale)
        frame:SetHeight(rowHeight + pixel:Multiple(SECTION_GAP, scale))
        frame.button:SetSize(buttonWidth, pixel:Snap(BUTTON_HEIGHT, scale))
        frame.button.selectedHighlight:SetSize(buttonWidth, pixel:Snap(BUTTON_HEIGHT, scale))
        frame.label:ClearAllPoints()
        frame.label:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -pixel:Snap((rowHeight - labelHeight) / 2, scale))
        frame.button:ClearAllPoints()
        frame.button:SetPoint("RIGHT", frame, "TOPRIGHT", 0, -pixel:Snap(rowHeight / 2, scale))
        return frame
    end)
end

if not Addon.incompatibleOrbit then
    _G.BINDING_NAME_ORBIT_COMPASS_TOGGLE_POINTS = L.PLU_COMPASS_POINT_TOGGLE_BINDING
end

