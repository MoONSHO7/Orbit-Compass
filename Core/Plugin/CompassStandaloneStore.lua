local _, Addon = ...

-- Unreleased route-guidance builds wrote these; LibOrbitUI refuses a whole store that holds an undeclared key.
local RETIRED_SETTINGS = {
    RouteGuidance = true,
    RoutePanel = true,
    RouteMinimap = true,
    RouteFootprints = true,
    RouteMap = true,
    RouteAvoid = true,
}

function Addon.MigrateStandaloneStore(data)
    if type(data) ~= "table" or type(data.settings) ~= "table" then
        return data
    end
    for _, settings in pairs(data.settings) do
        if type(settings) == "table" then
            for key in pairs(RETIRED_SETTINGS) do
                settings[key] = nil
            end
        end
    end
    return data
end
