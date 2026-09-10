local _, Addon = ...
local C = Addon.Constants
local Plugin = Addon.Controller
local Utils = Addon.SourceUtils
local Readable, Number, ReadPosition, AddMarker = Utils.Readable, Utils.Number, Utils.ReadPosition, Utils.AddMarker
local WAYPOINT_MATCH_EPSILON = 0.00001

function Plugin:ProjectCompassDestination(mapID, x, y)
    if mapID == self.mapID then
        return { x = x, y = y }
    end
    local continent, world = C_Map.GetWorldPosFromMapPos(mapID, CreateVector2D(x, y))
    local ownContinent = C_Map.GetWorldPosFromMapPos(self.mapID, CreateVector2D(0, 0))
    continent, ownContinent = Number(continent), Number(ownContinent)
    local worldX, worldY = ReadPosition(world)
    if not continent or continent ~= ownContinent or not worldX or not worldY then
        return
    end
    local projectedMap, position = C_Map.GetMapPosFromWorldPos(continent, CreateVector2D(worldX, worldY), self.mapID)
    if Number(projectedMap) == self.mapID then
        x, y = ReadPosition(position)
        if x and y then
            return { x = x, y = y }
        end
    end
end

local function FindWaypointMarker(markers, position)
    local x, y = ReadPosition(position)
    local match
    if x and y then
        for _, marker in ipairs(markers) do
            if
                math.abs(marker.x - x) < WAYPOINT_MATCH_EPSILON
                and math.abs(marker.y - y) < WAYPOINT_MATCH_EPSILON
                and (
                    not match
                    or marker.priority < match.priority
                    or (marker.priority == match.priority and marker.key < match.key)
                )
            then
                match = marker
            end
        end
    end
    return match
end

local function CollectWaypoint(plugin)
    local point = Readable(C_Map.GetUserWaypoint())
    local mapID = point and Number(point.uiMapID)
    local position = point and Readable(point.position)
    if not mapID or not position then
        plugin.waypointLabel = nil
        return
    end
    local x, y = ReadPosition(position)
    if not x or not y then
        return
    end
    local title = plugin:GetWaypointTitle(mapID, x, y)
    position = plugin:ProjectCompassDestination(mapID, x, y)
    if not position then
        return
    end
    local match = FindWaypointMarker(plugin.markers, position)
    AddMarker(
        plugin,
        plugin.markers,
        "waypoint",
        position,
        title,
        match and match.atlas or C.FALLBACK_ATLAS,
        C.WAYPOINT_PRIORITY,
        match and match.kind or "waypoint",
        { mapID = mapID, x = x, y = y }
    )
end

function Plugin:RefreshCompassMap()
    self.bearingsDirty = true
    wipe(self.markers)
    self.mapID = Number(C_Map.GetBestMapForUnit("player"))
    self.mapWidth, self.mapHeight = nil, nil
    self.positionInstance = nil
    if not self.mapID then
        return
    end
    local width, height = C_Map.GetMapWorldSize(self.mapID)
    width, height = Number(width), Number(height)
    if not width or not height or width <= 0 or height <= 0 then
        return
    end
    self.mapWidth, self.mapHeight = width, height
end

function Plugin:RebuildCompassMarkers()
    self.bearingsDirty = true
    wipe(self.markers)
    if not self.mapWidth then
        return
    end
    for _, source in pairs(self.compassSources) do
        for _, marker in ipairs(source.markers) do
            self.markers[#self.markers + 1] = marker
        end
    end
    if self.showWaypoint then
        CollectWaypoint(self)
    end
    self:SelectCompassNavigation()
end
