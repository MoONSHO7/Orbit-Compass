local _, Addon = ...
local L = Addon.L
local C = Addon.Constants
local Services = Addon.Services
local Bridge = Addon.OrbitBridge
local Pixel = Services.pixel
local Plugin = Addon.Controller
local GOLD = C.NAVIGATION_TEXT_COLOR

function Plugin:CreateNavigationView()
    self.navigationSize = C.DEFAULT_NAVIGATION_SIZE
    self:CreateNavigationFrame()
    local frame = self.navigationFrame
    local arrow = frame:CreateTexture(nil, "OVERLAY", nil, C.MARKER_ICON_SUBLEVEL)
    arrow:SetTexture(Services.arrowTexture)
    local distance = frame:CreateFontString(nil, "OVERLAY")
    distance:SetMaxLines(1)
    distance:SetJustifyH("CENTER")
    local title = frame:CreateFontString(nil, "OVERLAY")
    title:SetMaxLines(1)
    title:SetJustifyH("LEFT")
    self.navigationView = { arrow = arrow, distance = distance, title = title }
    frame.Name, frame.Distance = title, distance
    if Bridge then
        Bridge.AttachText(title, frame, "Name")
        Bridge.AttachText(distance, frame, "Distance")
        self:SetupNavigationCanvas()
    end
    self:HideNavigationView()
end

function Plugin:LayoutNavigationView()
    local view = self.navigationView
    local scale = self.navigationFrame:GetEffectiveScale()
    local size = Pixel:Snap(self.navigationSize, scale)
    self.navigationFrame:SetSize(size, size)
    view.arrow:SetSize(size, size)
    view.arrow:ClearAllPoints()
    view.arrow:SetPoint("CENTER", self.navigationFrame, "CENTER")
    self:RestoreNavigationPosition()
    Services.PositionNavigationText(self)
end

function Plugin:StyleNavigationView(font)
    local view = self.navigationView
    local fontSize = self:GetSetting(C.NAVIGATION_SYSTEM_INDEX, "FontSize")
    Services.StyleText(view.distance, { font = font, textSize = fontSize, textColor = GOLD })
    Services.StyleText(view.title, { font = font, textSize = fontSize, textColor = GOLD })
    self.navigationFontPath, self.navigationFontSize = view.distance:GetFont()
    local positions = Services.NavigationPositions(self)
    for key, text in pairs({ Name = view.title, Distance = view.distance }) do
        local position = positions[key]
        if Bridge then
            Bridge.ApplyTextOverrides(text, position and position.overrides or {}, fontSize)
        end
        if not (position and position.overrides and position.overrides.CustomColorCurve) then
            text:SetTextColor(GOLD.r, GOLD.g, GOLD.b)
        end
    end
    self:LayoutNavigationView()
end

function Plugin:HideNavigationView()
    local view = self.navigationView
    if view.shown == false then
        return
    end
    view.arrow:Hide()
    view.distance:Hide()
    view.title:Hide()
    view.shown, view.titleShown, view.distanceShown = false, false, false
    self.navigationFrame:Hide()
    if Bridge then
        Bridge.RetireLayer(self.navigationFrame)
    end
end

function Plugin:RenderNavigation(facing)
    local preview = Addon.Services.IsEditMode()
    local target = preview and self.navigationPreview or self.navigationTarget
    if
        self.inInstance
        or self.hiddenByGame
        or not self:IsActive()
        or self:IsProfileSuppressed()
        or not self.frame:IsShown()
        or (
            not preview
            and (
                not target
                or not target.distance
                or not facing
                or (target.distance > C.ARRIVAL_DISTANCE and not target.bearing)
            )
        )
    then
        self:HideNavigationView()
        return false
    end
    local view = self.navigationView
    local arrived = target.distance <= C.ARRIVAL_DISTANCE
    local rotation = (preview or arrived) and 0 or -math.rad(Addon.Math:WrapDegrees(facing - target.bearing))
    if view.rotation ~= rotation then
        view.arrow:SetRotation(rotation)
        view.rotation = rotation
    end
    local distance = self:CompassDisplayDistance(target.distance)
    if view.lastDistance ~= distance or view.lastArrived ~= arrived or view.lastUnits ~= self.distanceUnits then
        view.distance:SetText(arrived and L.PLU_COMPASS_ARRIVED or self:FormatCompassDistance(target.distance))
        view.lastDistance, view.lastArrived, view.lastUnits = distance, arrived, self.distanceUnits
    end
    if view.lastTitle ~= target.name then
        view.title:SetText(target.name)
        view.lastTitle = target.name
    end
    local showName, showDistance = not self.navigationDisabled.Name, not self.navigationDisabled.Distance
    if view.titleShown ~= showName then
        view.title:SetShown(showName)
        view.titleShown = showName
    end
    if view.distanceShown ~= showDistance then
        view.distance:SetShown(showDistance)
        view.distanceShown = showDistance
    end
    if not view.shown then
        if Bridge then
            Bridge.RegisterLayer(self.navigationFrame, C.NAVIGATION_SYSTEM_INDEX, L.PLU_COMPASS_ARROW)
        end
        self.navigationFrame:Show()
        view.arrow:Show()
        view.shown = true
    end
    return true
end
