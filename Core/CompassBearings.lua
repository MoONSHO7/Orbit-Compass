local _, Addon = ...
local C = Addon.Constants
local Plugin = Addon.Controller
local Number = Addon.SourceUtils.Number

local function MarkerBefore(a, b)
    if a.navigation ~= b.navigation then
        return a.navigation
    end
    if a.priority ~= b.priority then
        return a.priority < b.priority
    end
    if a.selectionDistanceSquared ~= b.selectionDistanceSquared then
        return a.selectionDistanceSquared < b.selectionDistanceSquared
    end
    return a.key < b.key
end

local function OrderBearings(plugin, forceSort)
    plugin.selectionDirty = true
    if forceSort or plugin.sortElapsed >= C.SORT_INTERVAL then
        for _, marker in ipairs(plugin.markers) do
            local bias = plugin.selectionKeys[marker.key] and C.MARKER_RETAINED_DISTANCE_SQUARED or 1
            marker.selectionDistanceSquared = marker.distanceSquared * bias
        end
        table.sort(plugin.markers, MarkerBefore)
        plugin.sortElapsed, plugin.sortPending = 0, false
    else
        plugin.sortPending = true
    end
    wipe(plugin.bearings)
    for _, marker in ipairs(plugin.markers) do
        if marker.bearing then
            plugin.bearings[#plugin.bearings + 1] = marker
        end
    end
end

function Plugin:RefreshCompassMarkerBearing(marker)
    if marker.bearingRevision == self.bearingRevision then
        return
    end
    local x, y = self.bearingPlayerX, self.bearingPlayerY
    local east, north = (marker.x - x) * self.mapWidth, (y - marker.y) * self.mapHeight
    marker.distanceSquared = east * east + north * north
    if marker.distanceSquared <= self.rangeSquared or marker.navigation or marker.priority == C.WAYPOINT_PRIORITY then
        marker.bearing, marker.distance = Addon.Math:Bearing(east, north, marker.distanceSquared)
    else
        marker.bearing, marker.distance = nil, nil
    end
    marker.bearingRevision = self.bearingRevision
end

function Plugin:RefreshCompassBearings()
    local x, y
    if self.mapID and self.mapWidth then
        x, y = self:ReadCompassPosition()
    end
    local resort = self.sortPending and self.sortElapsed >= C.SORT_INTERVAL
    local settle = x
        and self.bearingSampleX
        and (x ~= self.bearingSampleX or y ~= self.bearingSampleY)
        and self.discoveryClock >= self.bearingNextRefresh
    if not self.bearingsDirty and not settle and x == self.bearingPlayerX and y == self.bearingPlayerY then
        if resort and x and y then
            OrderBearings(self, true)
            self.renderDirty = true
        end
        return
    end
    local forceSort = self.bearingsDirty
    if forceSort or x ~= self.bearingPlayerX or y ~= self.bearingPlayerY then
        self.bearingRevision = (self.bearingRevision or 0) + 1
    end
    self.bearingsDirty, self.renderDirty = false, true
    self.bearingPlayerX, self.bearingPlayerY = x, y
    if not x or not y then
        self.navigationTarget, self.bearingSampleX = nil, nil
        self.selectionDirty = true
        wipe(self.bearings)
        return
    end
    local fullRefresh = forceSort or not self.bearingSampleX or self.discoveryClock >= self.bearingNextRefresh
    if not fullRefresh then
        local east, north = (x - self.bearingSampleX) * self.mapWidth, (y - self.bearingSampleY) * self.mapHeight
        fullRefresh = east * east + north * north >= C.BEARING_RESET_DISTANCE * C.BEARING_RESET_DISTANCE
    end
    if fullRefresh then
        self.bearingNextRefresh = self.discoveryClock + C.BEARING_REFRESH_INTERVAL
        self.bearingSampleX, self.bearingSampleY = x, y
        self.rangeSquared = self.range * self.range
        self.navigationTarget = nil
        for _, marker in ipairs(self.markers) do
            self:RefreshCompassMarkerBearing(marker)
            if marker.key == self.navigationKey then
                self.navigationTarget = marker
            end
        end
        OrderBearings(self, forceSort)
    else
        if self.navigationTarget then
            self:RefreshCompassMarkerBearing(self.navigationTarget)
        end
        for _, slot in ipairs(self.markerSlots) do
            if slot.selected then
                self:RefreshCompassMarkerBearing(slot.marker)
            end
        end
    end
end

function Plugin:GetCompassFacing()
    local facing = Number(GetPlayerFacing())
    return facing and math.deg(facing)
end
