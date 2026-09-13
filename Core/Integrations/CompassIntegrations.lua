local _, Addon = ...
local Plugin = Addon.Controller

function Plugin:EnableCompassIntegrations()
    self.compassIntegrationsEnabled = true
    self:ConnectCompassHandyNotes()
    self:ConnectCompassGatherMate()
    Addon.Events:On("ADDON_LOADED", self.ConnectCompassGatherMate, self)
    Addon.Events:On("ADDON_LOADED", self.ConnectCompassHandyNotes, self)
end

function Plugin:DisableCompassIntegrations()
    self.compassIntegrationsEnabled = false
    self:DisconnectCompassHandyNotes()
    self:DisconnectCompassGatherMate()
    Addon.Events:Off("ADDON_LOADED", self.ConnectCompassGatherMate)
    Addon.Events:Off("ADDON_LOADED", self.ConnectCompassHandyNotes)
end
