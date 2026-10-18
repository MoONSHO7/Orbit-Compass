local _, Addon = ...
local Plugin = Addon.Controller

function Plugin:EnableCompassIntegrations()
    self.compassIntegrationsEnabled = true
    self:ConnectCompassHandyNotes()
    self:ConnectCompassGatherMate()
    self:ConnectCompassSearchProvider()
    self:ConnectCompassNavigationRoute()
    Addon.Events:On("ADDON_LOADED", self.ConnectCompassGatherMate, self)
    Addon.Events:On("ADDON_LOADED", self.ConnectCompassHandyNotes, self)
    Addon.Events:On("ADDON_LOADED", self.ConnectCompassNavigationRoute, self)
end

function Plugin:DisableCompassIntegrations()
    self.compassIntegrationsEnabled = false
    self:DisconnectCompassHandyNotes()
    self:DisconnectCompassGatherMate()
    self:DisconnectCompassSearchProvider()
    self:DisconnectCompassNavigationRoute()
    Addon.Events:Off("ADDON_LOADED", self.ConnectCompassGatherMate)
    Addon.Events:Off("ADDON_LOADED", self.ConnectCompassHandyNotes)
    Addon.Events:Off("ADDON_LOADED", self.ConnectCompassNavigationRoute)
end
