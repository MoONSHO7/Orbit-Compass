local _, Addon = ...
if not Addon.OrbitBridge then
    return
end
local Orbit = Orbit
local L = Addon.L
local C = Addon.Constants
local Engine = Orbit.Engine
local Plugin = Addon.Controller
local GOLD = C.NAVIGATION_TEXT_COLOR

function Plugin:RegisterNavigationCanvasSettings()
    local schema = Engine.CanvasMode.SettingsSchema
    local controls = CopyTable(schema.STATIC_TEXT)
    controls[#controls + 1] = {
        type = "dropdown",
        key = "DistanceUnits",
        label = L.PLU_COMPASS_UNITS,
        default = "yards",
        options = {
            { text = L.PLU_COMPASS_YARDS, value = "yards" },
            { text = L.PLU_COMPASS_METERS, value = "meters" },
        },
    }
    schema.KEY_SCHEMAS.Distance = { controls = controls }
    schema.COMPONENT_TITLES.Distance = L.PLU_COMPASS_DISTANCE
end

function Plugin:GetCanvasPreviewText(key)
    if key == "Name" then
        return self.navigationPreview.name
    elseif key == "Distance" then
        return self:FormatCompassDistance(C.NAVIGATION_PREVIEW_DISTANCE)
    end
end

local function ApplyDistanceOverride(component, key, value)
    if key == "DistanceUnits" then
        component.visual:SetText(Plugin:FormatCompassDistance(C.NAVIGATION_PREVIEW_DISTANCE, value or "yards"))
        component:RequestFontRemeasure()
    end
end

function Plugin:OnCanvasLivePreview()
    self:CacheNavigationComponents()
    self:StyleNavigationView(Orbit:GetTheme("Font"))
    self.renderDirty = true
    self:RenderNavigation(self:GetCompassFacing())
    local dialog = Engine.CanvasModeDialog
    if dialog.targetPlugin == self and dialog.targetSystemIndex == C.NAVIGATION_SYSTEM_INDEX then
        local component = dialog.previewComponents and dialog.previewComponents.Distance
        if component then
            component.ApplyCustomOverride = ApplyDistanceOverride
            ApplyDistanceOverride(component, "DistanceUnits", self.distanceUnits)
        end
    end
end

function Plugin:SetupNavigationCanvas()
    self:CacheNavigationComponents()
    self.navigationFrame.GetCanvasBorderInset = function()
        return 0
    end
    self.navigationFrame.CreateCanvasPreview = function(frame, options)
        self:RegisterNavigationCanvasSettings()
        local parent = options.parent or UIParent
        local preview = options.reuse or CreateFrame("Frame", nil, parent)
        preview:SetParent(parent)
        preview:ClearAllPoints()
        preview:SetPoint("CENTER", parent, "CENTER")
        preview:SetSize(frame:GetWidth(), frame:GetHeight())
        preview.sourceFrame, preview.systemIndex = frame, C.NAVIGATION_SYSTEM_INDEX
        preview.sourceWidth, preview.sourceHeight = frame:GetWidth(), frame:GetHeight()
        preview._sourceGeometryScale, preview.borderInset = frame:GetEffectiveScale(), 0
        preview.previewScale = 1
        preview.components = preview.components or {}
        wipe(preview.components)
        if not preview.arrow then
            preview.arrow = preview:CreateTexture(nil, "OVERLAY", nil, C.MARKER_ICON_SUBLEVEL)
            preview.arrow:SetAllPoints()
            preview.arrow:SetTexture(Addon.Services.arrowTexture)
        end
        local fontPath, fontSize = self.navigationFontPath, self.navigationFontSize
        local positions = self:GetComponentPositions(C.NAVIGATION_SYSTEM_INDEX)
        Engine.IconCanvasPreview:AttachTextComponents(preview, {
            { key = "Name", preview = self:GetCanvasPreviewText("Name"), fontSize = fontSize },
            { key = "Distance", preview = self:GetCanvasPreviewText("Distance"), fontSize = fontSize },
        }, positions, fontPath)
        for key, component in pairs(preview.components) do
            local position = positions[key]
            if not (position and position.overrides and position.overrides.CustomColorCurve) then
                component.visual:SetTextColor(GOLD.r, GOLD.g, GOLD.b)
            end
        end
        preview.components.Distance.ApplyCustomOverride = ApplyDistanceOverride
        preview:Show()
        return preview
    end
end
