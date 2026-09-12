local _, Addon = ...
local L = Addon.L
local C = Addon.Constants
local Services = Addon.Services
local Bridge = Addon.OrbitBridge
local Pixel = Services.pixel
local Plugin = Addon.Controller
local FEET_Y_OFFSET = 15

function Plugin:CreateNavigationFrame()
    local frame = CreateFrame("Button", C.NAVIGATION_FRAME_NAME, UIParent, "OrbitCompassNavigationButtonTemplate")
    frame:Hide()
    frame:RegisterForClicks("RightButtonUp")
    frame:SetScript("OnClick", function(_, button)
        if button ~= "RightButton" or Addon.Services.IsEditMode() then
            return
        end
        self:DismissCompassNavigation()
    end)
    frame:SetScript("OnShow", function()
        if self.inInstance then
            frame:Hide()
        end
    end)
    Pixel:Enforce(frame, { centerAnchored = true })
    frame:SetClampedToScreen(true)
    Services.ConfigureRoot(frame, C.NAVIGATION_SYSTEM_INDEX)
    frame:SetSize(C.DEFAULT_NAVIGATION_SIZE, C.DEFAULT_NAVIGATION_SIZE)
    frame.systemIndex = C.NAVIGATION_SYSTEM_INDEX
    frame.editModeName = L.PLU_COMPASS_ARROW_TITLE
    frame.anchorOptions = { horizontal = false, vertical = false }
    frame.orbitNoSnap, frame.orbitSnapExclude = true, true
    self.navigationFrame = frame
    self.containers = { [C.NAVIGATION_SYSTEM_INDEX] = frame }
    self.navigationPreview = { name = L.PLU_COMPASS_ARROW, distance = C.NAVIGATION_PREVIEW_DISTANCE, bearing = 0 }
    self.navigationLayerApplier = function(level)
        frame:SetFrameLevel(level)
    end
    if Bridge then
        Bridge.AttachFrame(frame, self, C.NAVIGATION_SYSTEM_INDEX)
    end
end

function Plugin:GetNavigationDefaultPosition()
    local scale = self.navigationFrame:GetEffectiveScale()
    return {
        point = "CENTER",
        relativePoint = "CENTER",
        x = 0,
        y = -UIParent:GetHeight() * C.NAVIGATION_FEET_OFFSET_FRACTION + Pixel:Multiple(FEET_Y_OFFSET, scale),
    }
end

function Plugin:RestoreNavigationPosition()
    local frame = self.navigationFrame
    if not frame.defaultPosition then
        frame.defaultPosition = self:GetNavigationDefaultPosition()
        frame.defaultPosition.relativeTo = UIParent
    end
    Services.RestorePosition(frame, C.NAVIGATION_SYSTEM_INDEX)
end

function Plugin:ResetNavigationPosition()
    self:SetSetting(C.NAVIGATION_SYSTEM_INDEX, "Position", false)
    if Bridge then
        Bridge.ClearPosition(self.navigationFrame)
    end
    self.navigationFrame.defaultPosition = nil
end
