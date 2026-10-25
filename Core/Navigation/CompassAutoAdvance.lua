local _, Addon = ...
local Plugin = Addon.Controller
local C = Addon.Constants
local CHECK_INTERVAL = 0.25
local REMOVAL_DELAY = 1

local function FindSource(plugin, key)
    for _, marker in ipairs(plugin.markers) do
        if marker.key == key then
            return marker
        end
    end
end

local function SourcesReady(plugin)
    if plugin.discoveryDirty or plugin.discoveryJob or plugin.waypointDirty then
        return false
    end
    for _, source in pairs(plugin.compassSources) do
        if source.enabled and (source.dirty or source.pathDirty) then
            return false
        end
    end
    return true
end

local function FindNext(plugin, route)
    local best, bestDistance
    for _, marker in ipairs(plugin.markers) do
        local source = marker.source and plugin.compassSources[marker.source]
        if
            marker.key ~= "waypoint"
            and marker.kind ~= "corpse"
            and marker.kind ~= "route"
            and source
            and source.status == "ready"
            and not route.visited[marker.key]
            and (not plugin.autoAdvanceSameType or marker.kind == route.kind)
        then
            local east = (marker.x - plugin.bearingPlayerX) * plugin.mapWidth
            local north = (marker.y - plugin.bearingPlayerY) * plugin.mapHeight
            local distance = east * east + north * north
            if
                distance <= plugin.range * plugin.range
                and (not best or distance < bestDistance or (distance == bestDistance and marker.key < best.key))
            then
                best, bestDistance = marker, distance
            end
        end
    end
    return best
end

function Plugin:ResetCompassAutoAdvance()
    self.compassAutoAdvance, self.compassAutoAdvanceBlockedLabel = nil, nil
    self.compassAutoAdvanceNext = 0
end

function Plugin:UpdateCompassAutoAdvance()
    if self.autoAdvanceMode == "off" or Addon.Services.IsEditMode() then
        return
    end
    if self.discoveryClock < self.compassAutoAdvanceNext then
        return
    end
    self.compassAutoAdvanceNext = self.discoveryClock + CHECK_INTERVAL
    local label = self.waypointLabel
    if not label or not label.sourceKey then
        self.compassAutoAdvance = nil
        return
    end
    if label == self.compassAutoAdvanceBlockedLabel or not self.bearingPlayerX or not self.bearingPlayerY then
        return
    end
    if self.navigationKey ~= "waypoint" or not SourcesReady(self) then
        return
    end
    local source = FindSource(self, label.sourceKey)
    local route = self.compassAutoAdvance
    if not route or route.label ~= label or route.mapID ~= self.mapID then
        if not source then
            return
        end
        route = { label = label, kind = source.kind, source = source.source, mapID = self.mapID, visited = {} }
        self.compassAutoAdvance = route
    end
    local observed = route.source and self.compassSources[route.source].status == "ready"
    if source or not observed then
        route.missingSince = nil
        if source then
            route.awaitingSource = nil
        end
    elseif not route.awaitingSource then
        route.missingSince = route.missingSince or self.discoveryClock
    end
    local target = self.navigationTarget
    local arrived = self.autoAdvanceMode == "arrival"
        and target
        and target.distance
        and target.distance <= C.ARRIVAL_DISTANCE
    local removed = observed and route.missingSince and self.discoveryClock - route.missingSince >= REMOVAL_DELAY
    if not arrived and not removed then
        return
    end
    route.visited[label.sourceKey] = true
    local nextPoint = FindNext(self, route)
    if not nextPoint then
        self:ClearWaypoint()
        self.compassAutoAdvance = nil
        return
    end
    local destination = nextPoint.destination
    -- Automatic routing must not invoke a provider's native click action.
    local success, reason = self:SetWaypoint(
        destination.mapID,
        destination.x,
        destination.y,
        nextPoint.name,
        nextPoint.description,
        nextPoint.key
    )
    if success then
        route.label, route.missingSince = self.waypointLabel, nil
        route.source = nextPoint.source
    else
        self.compassAutoAdvanceBlockedLabel = label
        print(reason)
    end
end
