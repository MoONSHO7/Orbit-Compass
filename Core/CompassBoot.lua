local addonName, Addon = ...
local UI = Addon.LibOrbitUI
local C = Addon.Constants
local L = Addon.L
local Plugin = Addon.Controller

if Addon.incompatibleOrbit or not Addon.ClientFeatures.supported then
    Addon.Services.context:Destroy()
    local warning = CreateFrame("Frame")
    warning:RegisterEvent("ADDON_LOADED")
    warning:SetScript("OnEvent", function(self, _, name)
        if name == addonName then
            self:UnregisterAllEvents()
            print(Addon.incompatibleOrbit and L.MSG_COMPASS_INCOMPATIBLE_ORBIT or L.MSG_COMPASS_UNSUPPORTED_CLIENT)
        end
    end)
    return
end

function Addon.GetFrames()
    local navigation = Plugin.navigationFrame
    if navigation and not navigation.defaultPosition then
        navigation.defaultPosition = Plugin:GetNavigationDefaultPosition()
    end
    local function CanEdit()
        return Plugin:IsActive() and not Plugin.inInstance and not Plugin.hiddenByGame
    end
    local function EditChanged()
        Plugin.renderDirty = true
        if Plugin:IsActive() then
            Plugin:RenderNavigation(Plugin:GetCompassFacing())
        end
    end
    return {
        {
            frame = Plugin.frame,
            index = C.SYSTEM_INDEX,
            label = L.PLG_NAME_COMPASS,
            defaultPosition = Addon.Definition.defaults.Position,
            canEdit = CanEdit,
            onEditChanged = EditChanged,
            applyOnEditChanged = false,
        },
        {
            frame = navigation,
            index = C.NAVIGATION_SYSTEM_INDEX,
            label = L.PLU_COMPASS_ARROW,
            defaultPosition = navigation and navigation.defaultPosition,
            canEdit = CanEdit,
            onEditChanged = EditChanged,
            applyOnEditChanged = false,
        },
    }
end

Addon.App = UI.Addon:Create({
    addonName = addonName,
    name = "OrbitCompass",
    title = L.PLG_NAME_COMPASS,
    settingsTitles = { [C.NAVIGATION_SYSTEM_INDEX] = L.PLU_COMPASS_ARROW_TITLE },
    context = Addon.Services.context,
    controller = Plugin,
    store = Addon.Store,
    bridge = Addon.OrbitBridge,
    readStore = function()
        return OrbitCompassDB
    end,
    writeStore = function(db)
        OrbitCompassDB = db
    end,
    frames = Addon.GetFrames,
    tabs = Addon.SettingsTabs,
    registerWidgets = Addon.RegisterSettingsWidgets,
    labels = {
        enabled = L.CFG_FP_ENABLED,
        close = L.CMN_CLOSE,
        settings = L.CFG_SETTINGS_FALLBACK,
        edit = L.CFG_TAB_EDIT_MODE,
        reset = L.CMN_RESET,
        notReady = L.MSG_COMPASS_NOT_READY,
    },
    slashKey = "ORBITCOMPASS",
    slash = { "/orbitcompass" },
})

if not Addon.OrbitBridge then
    function Addon.App:ResetPosition(index)
        if index ~= C.NAVIGATION_SYSTEM_INDEX then
            return UI.AddonMixin.ResetPosition(self, index)
        end
        if not self.ready then
            return
        end
        local movement = self.movements[index]
        if movement and movement:Reset(Plugin:GetNavigationDefaultPosition()) then
            Plugin:ResetNavigationPosition()
            Plugin:RestoreNavigationPosition()
            self:Apply()
        end
    end
end
