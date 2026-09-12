local _, Addon = ...
local L = Addon.L
local C = Addon.Constants
local Plugin = Addon.Controller
local Services = Addon.Services

function Plugin:GetDefaultComponentPositions()
    return self.indexDefaults[C.NAVIGATION_SYSTEM_INDEX].ComponentPositions
end

function Plugin:GetDefaultDisabledComponents()
    return self.indexDefaults[C.NAVIGATION_SYSTEM_INDEX].DisabledComponents
end

function Plugin:CacheNavigationComponents()
    local index = C.NAVIGATION_SYSTEM_INDEX
    local positions = Services.NavigationPositions(self)
    local distance = positions.Distance
    self.distanceUnits = distance and distance.overrides and distance.overrides.DistanceUnits or "yards"
    local disabled = Services.DisabledNavigationComponents(self)
    self.navigationDisabled = {}
    for _, key in ipairs(disabled) do
        self.navigationDisabled[key] = true
    end
end

function Plugin:IsComponentDisabled(key)
    local disabled = Services.DisabledNavigationComponents(self)
    for _, disabledKey in ipairs(disabled) do
        if key == disabledKey then
            return true
        end
    end
    return false
end

function Plugin:CompassDisplayDistance(yards, units)
    return math.floor(yards * ((units or self.distanceUnits) == "meters" and C.METERS_PER_YARD or 1) + 0.5)
end

function Plugin:FormatCompassDistance(yards, units)
    local format = (units or self.distanceUnits) == "meters" and L.PLU_COMPASS_METERS_F or L.PLU_COMPASS_YARDS_F
    return format:format(self:CompassDisplayDistance(yards, units))
end
