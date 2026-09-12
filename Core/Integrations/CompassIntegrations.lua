local _, Addon = ...
local Plugin = Addon.Controller

function Plugin:EnableCompassIntegrations()
    self.compassIntegrationsEnabled = true
    self:ConnectCompassHandyNotes()
    Addon.Events:On("ADDON_LOADED", self.ConnectCompassHandyNotes, self)
end

function Plugin:DisableCompassIntegrations()
    self.compassIntegrationsEnabled = false
    self:DisconnectCompassHandyNotes()
    Addon.Events:Off("ADDON_LOADED", self.ConnectCompassHandyNotes)
end
