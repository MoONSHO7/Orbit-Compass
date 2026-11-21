local _, Addon = ...
local C = Addon.Constants
local Plugin = Addon.Controller
local Utils = Addon.SourceUtils
local Readable, Number, Text = Utils.Readable, Utils.Number, Utils.Text
local Catalog = Addon.CompassCityCatalog
local CITY_KIND = "city"
local ROUTE_KIND = "route"
local QUEST_OFFER_KIND = "questOffer"
local CITY_KEY_PREFIX = "city:"
local TOWN_KEY_PREFIX = "town:"
local TOWN_EXIT_YARDS = 20
local PLACES_POINT = "ShowPlaces"
local FOLDED, UNFOLDED = 0, 1
local GROUP_SPAN = "Compass.Cities"
local BOUNDS_COUNT = "Cities/Bounds"
local STAMPED_COUNT = "Cities/Stamped"
local FOLD_STARTED_COUNT = "Cities/FoldStarted"

local function PlaceName(place)
    if place.areaID then
        return Text(C_Map.GetAreaInfo(place.areaID))
    end
    local info = Readable(C_Map.GetMapInfo(place.mapID))
    return type(info) == "table" and Text(info.name) or nil
end

local function BuildRegions(plugin)
    local regions = {}
    for _, place in ipairs(Catalog.places) do
        local rect = place.rect
        local first = plugin:ProjectCompassDestination(place.mapID, rect[1], rect[2])
        local last = first and plugin:ProjectCompassDestination(place.mapID, rect[3], rect[4])
        local name = last and PlaceName(place)
        if name then
            local left, right = math.min(first.x, last.x), math.max(first.x, last.x)
            local top, bottom = math.min(first.y, last.y), math.max(first.y, last.y)
            local x, y = (left + right) / 2, (top + bottom) / 2
            local key = place.areaID and TOWN_KEY_PREFIX .. place.areaID or CITY_KEY_PREFIX .. place.mapID
            local region = {
                place = place,
                mapID = plugin.mapID,
                name = name,
                left = left,
                right = right,
                top = top,
                bottom = bottom,
                marker = {
                    key = key,
                    kind = CITY_KIND,
                    point = PLACES_POINT,
                    name = name,
                    x = x,
                    y = y,
                    texture = place.texture,
                    textureFilter = C.CITY_TEXTURE_FILTER,
                    sizeScale = C.CITY_MARKER_SCALE,
                    priority = C.POI_PRIORITY,
                    -- On the place's own map: a town across a zone border projects outside the current map's bounds.
                    destination = { mapID = place.mapID, x = (rect[1] + rect[3]) / 2, y = (rect[2] + rect[4]) / 2 },
                },
            }
            region.marker.cityRegion = region
            regions[#regions + 1] = region
        end
    end
    return regions
end

local function Count(plugin, label, amount)
    local profiler = Addon.Services.profiler
    if profiler and profiler.active then
        profiler:Count(plugin, label, amount)
    end
end

-- Towns on other maps that could show from anywhere on this one (the farthest Points range from its edge), grouped
-- by their own map in catalogue order with their rectangles there.
local function TownMaps(plugin, regions)
    local maps, byMap = {}, {}
    for _, region in ipairs(regions) do
        local place = region.place
        if place.areaID and place.mapID ~= plugin.mapID then
            local east = math.max(0, -region.right, region.left - 1) * plugin.mapWidth
            local south = math.max(0, -region.bottom, region.top - 1) * plugin.mapHeight
            if east * east + south * south <= C.RANGE_MAX * C.RANGE_MAX then
                local entry = byMap[place.mapID]
                if not entry then
                    entry = { mapID = place.mapID, rects = {} }
                    byMap[place.mapID], maps[#maps + 1] = entry, entry
                end
                entry.rects[#entry.rects + 1] = place.rect
            end
        end
    end
    return maps
end

local function CurrentRegions(plugin)
    local mapID = plugin.mapID
    local regions = plugin.compassCityRegions[mapID]
    if not regions then
        regions = BuildRegions(plugin)
        local markers = {}
        for index, region in ipairs(regions) do
            markers[index] = region.marker
        end
        plugin.compassCityRegions[mapID], plugin.compassPlaceMarkers[mapID] = regions, markers
        plugin.compassTownMaps[mapID] = TownMaps(plugin, regions)
        Count(plugin, BOUNDS_COUNT)
    end
    return regions
end

-- A town also tests its terrain outline, scaled into the projected rectangle; a margin widens the point into a box.
local function Contains(region, x, y, marginX, marginY)
    local left, right = region.left, region.right
    if x < left - marginX or x > right + marginX then
        return false
    end
    local top, bottom = region.top, region.bottom
    if y < top - marginY or y > bottom + marginY then
        return false
    end
    local place = region.place
    local runs = place.runs
    if not runs then
        return true
    end
    local rowStarts, rows = place.rowStarts, place.rows
    local columnScale, rowScale = place.columns / (right - left), rows / (bottom - top)
    local low, high = (x - marginX - left) * columnScale, (x + marginX - left) * columnScale
    local first = math.max(1, math.floor((y - marginY - top) * rowScale) + 1)
    local last = math.min(rows, math.floor((y + marginY - top) * rowScale) + 1)
    for row = first, last do
        for index = rowStarts[row], rowStarts[row + 1] - 1, 2 do
            if high >= runs[index] and low < runs[index + 1] + 1 then
                return true
            end
        end
    end
    return false
end

local function FindRegion(regions, x, y)
    for _, region in ipairs(regions) do
        if Contains(region, x, y, 0, 0) then
            return region
        end
    end
    return false
end

local function PlayerCity(mapID)
    local visited = {}
    while mapID and mapID > 0 and not visited[mapID] do
        visited[mapID] = true
        local city = Catalog.byMap[mapID]
        if city then
            return city
        end
        local info = Readable(C_Map.GetMapInfo(mapID))
        mapID = type(info) == "table" and Number(info.parentMapID) or nil
    end
end

local function Inside(plugin, region)
    return region.place == plugin.compassPlayerCity
        or region.name == plugin.compassSubzoneName
        or region == plugin.compassPositionTown
end

local function Progress(state, clock)
    local moved = (clock - state.startedAt) / C.CITY_FOLD_SECONDS
    if state.to > state.from then
        return math.min(state.to, state.from + moved)
    end
    return math.max(state.to, state.from - moved)
end

local function Ease(progress)
    local rest = 1 - progress
    return 1 - rest * rest * rest
end

function Plugin:ResetCompassCities()
    self.compassCityRegions, self.compassPlaceMarkers, self.compassCityFoldRevision = {}, {}, 0
    self.compassTownMaps = {}
    self.compassPlaceFolds, self.compassCityFoldAnimating = {}, false
    self.compassPositionTown, self.compassFoldSettlesAt = nil, nil
end

-- A city map in the player's map ancestry, or the subzone the client names, places the player inside.
function Plugin:RefreshCompassCityArea(mapID)
    local city, subzone = PlayerCity(mapID), Text(GetSubZoneText())
    if city ~= self.compassPlayerCity or subzone ~= self.compassSubzoneName then
        self.compassPlayerCity, self.compassSubzoneName = city, subzone
        self.bearingsDirty = true
    end
end

-- Inns and halls carry their own subzone names, so standing on a town's terrain outline also counts as inside it.
function Plugin:RefreshCompassPositionTown(x, y)
    if not self.showPlaces then
        self.compassPositionTown = nil
        return
    end
    local current = self.compassPositionTown
    if current and current.mapID == self.mapID then
        local marginX, marginY = TOWN_EXIT_YARDS / self.mapWidth, TOWN_EXIT_YARDS / self.mapHeight
        if Contains(current, x, y, marginX, marginY) then
            return
        end
    end
    self.compassPositionTown = nil
    local regions = self.compassCityRegions[self.mapID]
    if not regions then
        return
    end
    for _, region in ipairs(regions) do
        if region.place.areaID and Contains(region, x, y, 0, 0) then
            self.compassPositionTown = region
            return
        end
    end
end

-- Membership is stamped once per marker position; bounds are static per map until the discovery context resets. A
-- place offers quests while any collected Available Quests point lies inside it, at whatever distance.
function Plugin:GroupCompassCityMarkers()
    local profiler = Addon.Services.profiler
    local start, startKB
    if profiler and profiler.active then
        start, startKB = profiler:Begin()
    end
    local mapID = self.mapID
    local regions = CurrentRegions(self)
    for _, region in ipairs(regions) do
        region.offersQuests = false
    end
    local stamped = 0
    for _, marker in ipairs(self.markers) do
        if marker.compassCityMap ~= mapID or marker.compassCityX ~= marker.x or marker.compassCityY ~= marker.y then
            marker.compassCityMap, marker.compassCityX, marker.compassCityY = mapID, marker.x, marker.y
            marker.compassCity = FindRegion(regions, marker.x, marker.y)
            stamped = stamped + 1
        end
        if marker.compassCity and marker.kind == QUEST_OFFER_KIND then
            marker.compassCity.offersQuests = true
        end
    end
    if start then
        if stamped > 0 then
            profiler:Count(self, STAMPED_COUNT, stamped)
        end
        profiler:End(self, GROUP_SPAN, start, startKB)
    end
end

-- Every place icon on the current map, for Bearings to rank as notable points in its own right.
function Plugin:GetCompassPlaceMarkers()
    CurrentRegions(self)
    return self.compassPlaceMarkers[self.mapID]
end

-- Collectors that read other maps add these towns' points, so a town across a zone border lists all of them.
function Plugin:GetCompassTownMaps()
    CurrentRegions(self)
    return self.compassTownMaps[self.mapID]
end

-- The current destination, waypoints and route steps keep their own icons inside a place the player is outside.
function Plugin:CompassCityFoldRegion(marker)
    local region = marker.compassCity
    if
        region
        and self.showPlaces
        and marker.key ~= self.navigationKey
        and marker.priority ~= C.WAYPOINT_PRIORITY
        and marker.kind ~= ROUTE_KIND
    then
        return region
    end
end

-- A town lists and shows every point inside it whatever that point's range; capitals keep each point type's range.
function Plugin:IsCompassTownPoint(marker)
    local region = self:CompassCityFoldRegion(marker)
    return region ~= nil and region.place.areaID ~= nil
end

function Plugin:FoldCompassCityMarker(marker)
    local region = self:CompassCityFoldRegion(marker)
    if region and not Inside(self, region) then
        return region.marker
    end
end

-- Places animate only while consecutive orderings see them; arriving from another continent snaps to the result.
function Plugin:UpdateCompassPlaceFolds(revision)
    local clock, folds = self.markerClock, self.compassPlaceFolds
    local settlesAt
    for _, region in ipairs(CurrentRegions(self)) do
        local target = Inside(self, region) and UNFOLDED or FOLDED
        local state = folds[region.place]
        if not state then
            state = { from = target, to = target, startedAt = clock }
            folds[region.place] = state
        elseif state.revision ~= revision - 1 then
            state.from, state.to, state.startedAt = target, target, clock
        elseif state.to ~= target then
            state.from, state.to, state.startedAt = Progress(state, clock), target, clock
            Count(self, FOLD_STARTED_COUNT)
        end
        state.revision = revision
        local settles = state.startedAt + math.abs(state.to - state.from) * C.CITY_FOLD_SECONDS
        if settles > clock and (not settlesAt or settles < settlesAt) then
            settlesAt = settles
        end
    end
    self.compassFoldSettlesAt = settlesAt
end

-- A settled fold reorders even with its points off screen, so the side that faded out leaves the ribbon's lists.
function Plugin:SettleCompassPlaceFolds()
    local settlesAt = self.compassFoldSettlesAt
    if settlesAt and self.markerClock >= settlesAt then
        self.compassFoldSettlesAt, self.bearingsDirty = nil, true
    end
end

-- Whether a place's points and its own marker belong on the ribbon; both do while it folds or unfolds.
function Plugin:CompassCityFoldShares(region)
    -- Inside a capital or hub, towns stay off the ribbon entirely: neither their icon nor the points folded into it.
    if self.compassPlayerCity and region.place.areaID then
        return false, false
    end
    local state = self.compassPlaceFolds[region.place]
    if not state then
        local inside = Inside(self, region)
        return inside, not inside
    end
    local progress = Progress(state, self.markerClock)
    return progress > FOLDED or state.to > FOLDED, progress < UNFOLDED or state.to < UNFOLDED
end

-- Entering, points glide out of the place's icon as it fades; leaving, they glide back in. An unselected icon still
-- anchors the glide at its own projection, extended past the view's edge.
function Plugin:BlendCompassCityFolds(selection, facing, width)
    self.compassCityFoldAnimating = false
    local clock, folds, selected = self.markerClock, self.compassPlaceFolds, self.selectionKeys
    for _, marker in ipairs(selection) do
        marker.projectedRetiring, marker.projectedMoving = false, false
        local region = marker.compassFoldRegion or marker.cityRegion
        local state = region and folds[region.place]
        if state then
            local progress = Progress(state, clock)
            local moving = progress ~= state.to
            local city = region.marker
            marker.projectedRetiring, marker.projectedMoving = (marker == city) == (state.to == UNFOLDED), moving
            self.compassCityFoldAnimating = self.compassCityFoldAnimating or moving
            if marker == city then
                marker.projectedAlpha = marker.projectedAlpha * (1 - progress)
            else
                marker.projectedAlpha = marker.projectedAlpha * progress
                local cityX = selected[city.key] and city.projectedX
                    or city.bearing and Addon.Math:WrapDegrees(facing - city.bearing) / self.viewAngle * width
                if cityX then
                    marker.projectedX = cityX + (marker.projectedX - cityX) * Ease(progress)
                end
            end
        end
    end
end

function Plugin:IsCompassPlaceHostile(cityMarker)
    local faction = cityMarker.cityRegion.place.faction
    return faction ~= nil and faction ~= Readable(UnitFactionGroup("player"))
end

local function DistanceBefore(a, b)
    if a.distance ~= b.distance then
        return a.distance < b.distance
    end
    return a.key < b.key
end

function Plugin:CollectCompassCityPoints(cityMarker)
    local points = {}
    for _, marker in ipairs(self.markers) do
        if marker.distance and self:FoldCompassCityMarker(marker) == cityMarker then
            points[#points + 1] = marker
        end
    end
    table.sort(points, DistanceBefore)
    return points
end
