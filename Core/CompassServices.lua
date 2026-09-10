local addonName, Addon = ...
local UI = Addon.LibOrbitUI
assert(UI.VERSION_MAJOR == 1 and UI.VERSION_MINOR >= 4, "Orbit Compass requires LibOrbitUI 1.4")
local C = Addon.Constants
local HUD_STRATA = "MEDIUM"
local ROOT_LEVEL_OFFSET = 1
local SHADOW_OFFSET = 1
local Services = {}
Addon.Services = Services
Services.context = UI.CreateContext({ owner = Addon, name = "OrbitCompass" })
Services.pixel = Services.context.pixel
Services.tooltip = Services.context.tooltip
Services.tooltipHide = Services.context.tooltipHide
Services.IsSecret = issecretvalue
Services.arrowTexture = "Interface\\AddOns\\" .. addonName .. "\\Assets\\orbit-compass-arrow.tga"

function Services.IsEditMode()
    return Addon.App:IsEditMode()
end

function Services.GetFont()
    return STANDARD_TEXT_FONT
end

function Services.StyleText(region, options)
    UI.Text.ApplyFont(region, options.font, options.textSize, "OUTLINE")
    local offset = Services.pixel:Multiple(SHADOW_OFFSET, region:GetEffectiveScale())
    UI.Text.ApplyShadow(region, true, offset, -offset)
    local color = options.textColor
    region:SetTextColor(color.r, color.g, color.b, color.a or 1)
end

function Services.ConfigureRoot(frame)
    frame:SetFrameStrata(HUD_STRATA)
    frame:SetFrameLevel(UIParent:GetFrameLevel() + ROOT_LEVEL_OFFSET)
end

function Services.RestorePosition(frame, index)
    Addon.App:RestorePosition(frame, index)
end

function Services.AnchorTooltip(tooltip, owner)
    tooltip:SetOwner(owner, "ANCHOR_CURSOR_RIGHT")
end

function Services.NavigationPositions(plugin)
    return plugin:GetSetting(C.NAVIGATION_SYSTEM_INDEX, "ComponentPositions")
end

function Services.DisabledNavigationComponents(plugin)
    return plugin:GetSetting(C.NAVIGATION_SYSTEM_INDEX, "DisabledComponents")
end

function Services.PositionNavigationText(plugin)
    local frame, view = plugin.navigationFrame, plugin.navigationView
    view.title:ClearAllPoints()
    Services.pixel:Point(view.title, "LEFT", frame, "RIGHT", C.NAVIGATION_NAME_GAP, 0)
    view.distance:ClearAllPoints()
    Services.pixel:Point(view.distance, "TOP", frame, "BOTTOM", 0, -C.NAVIGATION_DISTANCE_GAP)
end
