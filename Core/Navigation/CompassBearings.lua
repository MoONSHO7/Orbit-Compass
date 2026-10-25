local _, Addon = ...
local C = Addon.Constants
local Plugin = Addon.Controller
local Number = Addon.SourceUtils.Number

local function MarkerBefore(a, b)
    -- Display-only markers carry no navigation flag; they rank with ordinary markers.
    local aNavigation, bNavigation = a.navigation == true, b.navigation == true
    if aNavigation ~= bNavigation then
        return aNavigation
    end
    if a.priority ~= b.priority then
        return a.priority < b.priority
    end
    if a.selectionDistanceSquared ~= b.selectionDistanceSquared then
        return a.selectionDistanceSquared < b.selectionDistanceSquared
    end
    return a.key < b.key
end

local function SortMarkers(plugin, markers)
    for _, marker in ipairs(markers) do
        local bias = plugin.selectionKeys[marker.key] and C.MARKER_RETAINED_DISTANCE_SQUARED or 1
        marker.selectionDistanceSquared = marker.distanceSquared * bias
    end
    -- Empty display lists are frozen sentinels; only a real ordering ever writes to the array.
    if #markers > 1 then
        table.sort(markers, MarkerBefore)
    end
end

local function OrderBearings(plugin, forceSort, profiler)
    plugin.selectionDirty = true
    local markers, display = plugin.markers, plugin.displayMarkers
    if forceSort or plugin.sortElapsed >= C.SORT_INTERVAL then
        SortMarkers(plugin, markers)
        SortMarkers(plugin, display)
        plugin.sortElapsed, plugin.sortPending = 0, false
        if profiler then
            profiler:Count(plugin, "Bearings/OrderSorted")
        end
    else
        plugin.sortPending = true
        if profiler then
            profiler:Count(plugin, "Bearings/OrderDeferred")
        end
    end
    -- Display-only markers join the ribbon here, merged in order; actionable consumers read `plugin.markers` alone.
    local bearings = plugin.bearings
    wipe(bearings)
    local index, displayIndex = 1, 1
    local marker, displayMarker = markers[1], display[1]
    while marker or displayMarker do
        local chosen
        if marker and (not displayMarker or not MarkerBefore(displayMarker, marker)) then
            chosen, index = marker, index + 1
            marker = markers[index]
        else
            chosen, displayIndex = displayMarker, displayIndex + 1
            displayMarker = display[displayIndex]
        end
        if chosen.bearing then
            bearings[#bearings + 1] = chosen
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

local function UpdateBearings(self, x, y, profiler)
    local resort = self.sortPending and self.sortElapsed >= C.SORT_INTERVAL
    local settle = x
        and self.bearingSampleX
        and (x ~= self.bearingSampleX or y ~= self.bearingSampleY)
        and self.discoveryClock >= self.bearingNextRefresh
    if not self.bearingsDirty and not settle and x == self.bearingPlayerX and y == self.bearingPlayerY then
        if profiler then
            profiler:Count(self, "Bearings/Unchanged")
        end
        if resort and x and y then
            OrderBearings(self, true, profiler)
            self.renderDirty = true
        end
        return
    end
    -- Membership that changed while the position was unavailable still owes one ordering before lists are merged.
    local forceSort = self.bearingsDirty or self.bearingsUnordered
    if forceSort or x ~= self.bearingPlayerX or y ~= self.bearingPlayerY then
        self.bearingRevision = (self.bearingRevision or 0) + 1
    end
    self.bearingsDirty, self.renderDirty = false, true
    self.bearingPlayerX, self.bearingPlayerY = x, y
    self.bearingsUnordered = forceSort and (not x or not y)
    if not x or not y then
        if profiler then
            profiler:Count(self, "Bearings/Unavailable")
        end
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
        if profiler then
            profiler:Count(self, "Bearings/Full")
        end
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
        for _, marker in ipairs(self.displayMarkers) do
            self:RefreshCompassMarkerBearing(marker)
        end
        OrderBearings(self, forceSort, profiler)
    else
        if profiler then
            profiler:Count(self, "Bearings/Incremental")
        end
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

function Plugin:RefreshCompassBearings()
    local profiler = Addon.Services.profiler
    local x, y
    if not profiler or not profiler.active then
        if self.mapID and self.mapWidth then
            x, y = self:ReadCompassPosition()
        end
        return UpdateBearings(self, x, y)
    end
    if self.mapID and self.mapWidth then
        local start, startKB = profiler:Begin()
        x, y = self:ReadCompassPosition()
        profiler:End(self, "Compass.Bearings.Position", start, startKB)
    end
    local start, startKB = profiler:Begin()
    UpdateBearings(self, x, y, profiler)
    profiler:End(self, "Compass.Bearings.Update", start, startKB)
end

function Plugin:GetCompassFacing()
    local facing = Number(GetPlayerFacing())
    return facing and math.deg(facing)
end
