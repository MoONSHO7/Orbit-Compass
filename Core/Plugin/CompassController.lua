local _, Addon = ...
local UI = Addon.LibOrbitUI
local Bridge = Addon.OrbitBridge
if Bridge then
    Addon.Events = Bridge.events
    Addon.Controller = Bridge.CreateController()
else
    Addon.Events = UI.Events:Create()
    Addon.Store = UI.SettingsStore:Create(Addon.Definition.defaults, Addon.Definition.indexDefaults)
    Addon.Controller = UI.Controller:Create({
        name = "Compass",
        system = Addon.Constants.SYSTEM_ID,
        displayName = Addon.L.PLG_NAME_COMPASS,
        defaults = Addon.Definition.defaults,
        indexDefaults = Addon.Definition.indexDefaults,
        context = Addon.Services.context,
        events = Addon.Events,
        store = Addon.Store,
        shouldApplyVisibility = function(controller)
            local hidden = C_PetBattles.IsInBattle() or UnitHasVehicleUI("player")
            return hidden ~= controller.hiddenByGame
        end,
    })
end
if not Addon.incompatibleOrbit then
    _G.OrbitCompass = Addon.Controller
end
