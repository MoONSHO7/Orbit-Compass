local _, Addon = ...
local C = Addon.Constants
local Plugin = Addon.Controller
local Number = Addon.SourceUtils.Number
local NO_PLACES = table.freeze({})

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
    local places = plugin.showPlaces and plugin:GetCompassPlaceMarkers() or NO_PLACES
    for _, place in ipairs(places) do
        place.compassRaisedBy = nil
        plugin:RefreshCompassMarkerBearing(place)
    end
    if forceSort or plugin.sortElapsed >= C.SORT_INTERVAL then
        SortMarkers(plugin, markers)
        SortMarkers(plugin, display)
        SortMarkers(plugin, places)
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
    -- Display-only markers and place icons merge in here by rank; actionable consumers read `plugin.markers` alone.
    -- A place joins once: alone within its own range, or where its nearest-ranked folded member would have been.
    local bearings = plugin.bearings
    wipe(bearings)
    local foldRevision = plugin.compassCityFoldRevision + 1
    plugin.compassCityFoldRevision = foldRevision
    if plugin.showPlaces then
        plugin:UpdateCompassPlaceFolds(foldRevision)
    end
    local index, displayIndex, placeIndex = 1, 1, 1
    local marker, displayMarker, place = markers[1], display[1], places[1]
    while marker or displayMarker or place do
        local chosen = marker
        if displayMarker and (not chosen or MarkerBefore(displayMarker, chosen)) then
            chosen = displayMarker
        end
        if place and (not chosen or MarkerBefore(place, chosen)) then
            chosen = place
        end
        if chosen == marker then
            index = index + 1
            marker = markers[index]
        elseif chosen == displayMarker then
            displayIndex = displayIndex + 1
            displayMarker = display[displayIndex]
        else
            placeIndex = placeIndex + 1
            place = places[placeIndex]
        end
        if chosen.cityRegion then
            local range = plugin:GetCompassMarkerRange(chosen)
            if chosen.foldRevision ~= foldRevision and chosen.distanceSquared <= range * range then
                local _, placeShown = plugin:CompassCityFoldShares(chosen.cityRegion)
                if placeShown then
                    chosen.foldRevision = foldRevision
                    bearings[#bearings + 1] = chosen
                end
            end
        elseif chosen.bearing then
            local region = plugin:CompassCityFoldRegion(chosen)
            chosen.compassFoldRegion = region
            if not region then
                bearings[#bearings + 1] = chosen
            else
                local membersShown, cityShown = plugin:CompassCityFoldShares(region)
                if membersShown then
                    bearings[#bearings + 1] = chosen
                end
                local city = region.marker
                local remaining = plugin:GetCompassMarkerRange(chosen) - chosen.distance
                if cityShown and remaining >= 0 then
                    -- The member deepest inside its own range lights the icon, whose own range applies only alone.
                    if not city.compassRaisedBy or remaining > city.compassRaisedRemaining then
                        city.compassRaisedBy, city.compassRaisedRemaining = chosen, remaining
                    end
                    if city.foldRevision ~= foldRevision then
                        city.foldRevision = foldRevision
                        plugin:RefreshCompassMarkerBearing(city)
                        bearings[#bearings + 1] = city
                    end
                end
            end
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
    local range = self:GetCompassMarkerRange(marker)
    -- Place icons and the points inside a town keep a bearing at any distance: a shown town lists all of its points.
    if
        marker.distanceSquared <= range * range
        or marker.navigation
        or marker.priority == C.WAYPOINT_PRIORITY
        or marker.cityRegion
        or self:IsCompassTownPoint(marker)
    then
        marker.bearing, marker.distance = Addon.Math:Bearing(east, north, marker.distanceSquared)
    else
        marker.bearing, marker.distance = nil, nil
    end
    marker.bearingRevision = self.bearingRevision
end

local function UpdateBearings(self, x, y, profiler)
    self:SettleCompassPlaceFolds()
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
        self.navigationTarget = nil
        self:RefreshCompassPositionTown(x, y)
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
