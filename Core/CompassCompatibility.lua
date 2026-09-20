local _, Addon = ...
local Orbit = _G.Orbit
local LEGACY_PLUGIN_VERSION = 1

if Orbit == nil or not Addon.ClientFeatures.supported then
    return
end

if
    type(Orbit) ~= "table"
    or not Orbit.Engine
    or type(Orbit.ExternalUIHost) ~= "table"
    or Orbit.ExternalUIHost.legacyPluginVersion ~= LEGACY_PLUGIN_VERSION
    or type(Orbit.GetPlugin) ~= "function"
    or Orbit:GetPlugin("Compass")
then
    Addon.incompatibleOrbit = true
    return
end

Addon.OrbitHost = Orbit
