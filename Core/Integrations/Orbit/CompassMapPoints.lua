local _, Addon = ...
local Plugin = Addon.Controller
local CAPABILITY_VERSION = 1
local REFRESH_SECONDS = 60

-- The host draws these on its own interactive map; a nil answer means the QuestieDB index is still building.
local provider = table.freeze({
    name = "Orbit Compass",
    Collect = function(mapID)
        return Plugin:CollectCompassQuestieGivers(mapID), REFRESH_SECONDS
    end,
})

local function Capability()
    local host = Addon.OrbitHost
    if
        host
        and host.ExternalUIHost.mapPointProviderVersion == CAPABILITY_VERSION
        and Addon.ClientFeatures.sources.questie
    then
        return host.MapPOICompanion
    end
end

function Plugin:ConnectCompassMapPoints()
    local points = Capability()
    if points then
        points:Register(provider)
    end
end

function Plugin:DisconnectCompassMapPoints()
    local points = Capability()
    if points then
        points:Unregister(provider)
    end
end

function Plugin:InvalidateCompassMapPoints()
    local points = Capability()
    if points then
        points:Invalidate(provider)
    end
end
