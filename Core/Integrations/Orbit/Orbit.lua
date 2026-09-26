local _, Addon = ...
local Orbit = Addon.OrbitHost
if not Orbit then
    return
end
local Engine = Orbit.Engine

local Services = Addon.Services
local C = Addon.Constants
local Bridge = {}
Addon.OrbitBridge = Bridge
Services.pixel = Engine.Pixel
Services.profiler = Orbit.Profiler
Services.tooltip = Orbit.Tooltip
Services.tooltipHide = Orbit.TooltipHide
Services.IsSecret = Orbit.SecretValueUtils.IsSecret
Services.navigationDescriptionFont = "PT Sans Narrow"
Services.searchFont = Orbit.Media.Font.OrbitSansChat
Bridge.events = Orbit.EventBus

function Bridge.CreateController()
    local plugin = Orbit:RegisterPlugin("Compass", C.SYSTEM_ID, Addon.Definition)
    Orbit.VisibilityEngine:RegisterFrame({
        key = "Compass",
        display = Addon.L.PLG_NAME_COMPASS,
        plugin = "Compass",
        index = 1,
        category = "HUD",
    })
    return plugin
end

function Bridge.Collection(plugin)
    return plugin:OpenSettingsCollection("CompassLocations")
end

function Services.GetFont()
    return Orbit:GetTheme("Font")
end

function Services.IsEditMode()
    return Orbit:IsEditMode()
end

function Services.StyleText(region, options)
    Orbit.Skin:SkinText(region, options)
end

function Services.ConfigureRoot(frame, index)
    frame:SetFrameStrata(Orbit.Constants.Strata.HUD)
    frame.orbitStrataEntity = Orbit.StrataEngine:MakeEntityID(C.SYSTEM_ID, index)
end

function Bridge.RegisterLayer(frame, index, label)
    Orbit.StrataEngine:Register("Global_HUD", frame.orbitStrataEntity, function(level)
        frame:SetFrameLevel(level)
    end, label, { family = C.SYSTEM_ID, orderKey = index, footprint = C.STRATA_FOOTPRINT })
end

function Bridge.RetireLayer(frame)
    Orbit.StrataEngine:Deactivate("Global_HUD", frame.orbitStrataEntity)
end

function Bridge.AttachFrame(frame, plugin, index)
    Engine.FramePersistence:AttachSettingsListener(frame, plugin, index)
end

function Services.RestorePosition(frame, index)
    Engine.FramePersistence:RestorePosition(frame, Addon.Controller, index)
end

function Services.AnchorTooltip(tooltip, owner)
    if Orbit:GetAccountData("Tooltips", true) then
        GameTooltip_SetDefaultAnchor(tooltip, owner)
    else
        tooltip:SetOwner(owner, Orbit.ResolveTooltipCursorAnchor("ANCHOR_CURSOR_RIGHT"))
    end
end

function Services.NavigationPositions(plugin)
    return plugin:GetComponentPositions(C.NAVIGATION_SYSTEM_INDEX)
end

function Services.DisabledNavigationComponents(plugin)
    local session = plugin:_ActiveTransaction(C.NAVIGATION_SYSTEM_INDEX)
    return session and session:GetDisabledComponents()
        or plugin:GetSetting(C.NAVIGATION_SYSTEM_INDEX, "DisabledComponents")
end

function Services.PositionNavigationText(plugin)
    Engine.ComponentDrag:RestoreFramePositions(plugin.navigationFrame, Services.NavigationPositions(plugin))
end

function Bridge.AttachText(region, frame, key)
    Engine.ComponentDrag:Attach(region, frame, { key = key, isFontString = true })
end

function Bridge.ApplyTextOverrides(region, overrides, fontSize)
    Engine.OverrideUtils.ApplyOverrides(region, overrides, { fontSize = fontSize })
end

function Bridge.ApplyFade(frame, plugin)
    Orbit.OOCFadeMixin:ApplyOOCFade(frame, plugin, C.SYSTEM_INDEX)
end

function Bridge.RemoveFade(frame)
    Orbit.OOCFadeMixin:RemoveOOCFade(frame)
end

function Bridge.EnableNavigationEditMode(plugin)
    Engine.EditMode:RegisterCallbacks({
        Enter = function()
            plugin.renderDirty = true
            plugin:RenderNavigation(plugin:GetCompassFacing())
        end,
        Exit = function()
            plugin.renderDirty = true
            plugin:HideNavigationView()
        end,
    }, plugin.navigationFrame, plugin)
    Orbit.EventBus:On("ORBIT_PROFILE_CHANGED", function()
        plugin.navigationFrame.defaultPosition = nil
        plugin.dismissedNavigationKey, plugin.nativeNavigationID = nil, nil
    end, plugin)
end

function Bridge.DisableNavigationEditMode(plugin)
    Engine.EditMode:UnregisterCallbacks(plugin.navigationFrame)
end

function Bridge.IsEnabled()
    return Orbit:IsPluginEnabled("Compass")
end

function Bridge.SetEnabled(enabled)
    Orbit:LiveTogglePlugin("Compass", enabled)
end

function Bridge.Apply()
    Orbit.PluginLifecycle:Apply(Addon.Controller)
end

function Bridge.EnterEditMode()
    Engine.EditMode:TryEnter()
end

function Bridge.ResetPosition(index)
    local plugin = Addon.Controller
    plugin:SetSetting(index, "Anchor", false)
    if index == C.NAVIGATION_SYSTEM_INDEX then
        plugin:ResetNavigationPosition()
    else
        plugin:SetSetting(index, "Position", CopyTable(Addon.Definition.defaults.Position))
    end
    Bridge.Apply()
end

function Bridge.ClearPosition(frame)
    Engine.PositionManager:ClearFrame(frame)
end

function Bridge.RenderSettings(plugin, dialog, frame)
    Addon.RegisterSettingsWidgets(Engine.Layout)
    Engine.SchemaBuilder:SetTabRefreshCallback(dialog, plugin, frame)
    local tabs = Addon.SettingsTabs(frame.systemIndex, dialog.orbitTabCallback)
    local labels, schema = {}, { hideNativeSettings = true, controls = {} }
    local selectedTab
    for index, tab in ipairs(tabs) do
        labels[index] = tab.label
        if tab.label == dialog.orbitCurrentTab then
            selectedTab = tab.label
        end
    end
    dialog.orbitCurrentTab = selectedTab or labels[1]
    local current = Engine.SchemaBuilder:AddSettingsTabs(schema, dialog, labels, labels[1], plugin)
    for _, tab in ipairs(tabs) do
        if tab.label == current then
            for _, control in ipairs(tab.controls) do
                schema.controls[#schema.controls + 1] = control
            end
            break
        end
    end
    schema.onReset = function()
        if current == Addon.L.PLU_COMPASS_POINTS then
            plugin:ResetCompassPointVisibility()
        end
        Bridge.ResetPosition(frame.systemIndex)
    end
    Engine.Config:Render(dialog, frame, plugin, schema)
end
