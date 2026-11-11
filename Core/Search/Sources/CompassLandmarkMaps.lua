local _, Addon = ...
local Utils = Addon.SourceUtils
local Readable, Number = Utils.Readable, Utils.Number
local Landmark = Addon.LandmarkRecord.New
local Maps = {}

local MAP_CENTER = 0.5
local CONTINENT_CENTER = table.freeze({ x = MAP_CENTER, y = MAP_CENTER })

local CONTINENT_MAP = Enum.UIMapType.Continent
local ZONE_MAP = Enum.UIMapType.Zone
local MICRO_MAP = Enum.UIMapType.Micro
local MAP_DEPTH = { [CONTINENT_MAP] = 1, [MICRO_MAP] = 2, [ZONE_MAP] = 3 }

local MAP_KEY = "map:"
local PHASE = {
    CHILDREN_NATIVE = "Compass.Landmarks.Children.Native",
    CHILDREN_COPY = "Compass.Landmarks.Children.Copy",
}

local function ReadMapDetails(mapID)
    local info = Readable(C_Map.GetMapInfo(mapID))
    if type(info) ~= "table" then
        return
    end
    local name = Readable(info.name)
    return {
        mapID = mapID,
        name = type(name) == "string" and name or nil,
        mapType = Number(info.mapType),
        parentMapID = Number(info.parentMapID),
    }
end

function Maps.ContinentName(mapID, lookup)
    local visited = {}
    while mapID and not visited[mapID] do
        visited[mapID] = true
        local details = lookup(mapID)
        if not details then
            return
        elseif details.mapType == CONTINENT_MAP then
            return details.name
        end
        mapID = details.parentMapID
    end
end

local function ReadMapArea(details)
    local mapID, parentID = details.mapID, details.parentMapID
    if details.mapType == ZONE_MAP then
        if Readable(C_Map.CanSetUserWaypointOnMap(mapID)) ~= true then
            return false
        end
        return { x = MAP_CENTER, y = MAP_CENTER, kind = Readable(C_Map.IsCityMap(mapID)) == true and "city" or "zone" }
    elseif Readable(C_Map.CanSetUserWaypointOnMap(parentID)) ~= true then
        return false
    end
    local left, right, top, bottom = C_Map.GetMapRectOnMap(mapID, parentID)
    left, right, top, bottom = Number(left), Number(right), Number(top), Number(bottom)
    return left and right and top and bottom and { x = (left + right) / 2, y = (top + bottom) / 2, kind = "area" }
        or false
end

function Maps.CollectArea(details, place, add, seen, static)
    local mapID, parentID = details.mapID, details.parentMapID
    -- Phased copies of one map share a name and parent; the first copy represents it.
    local identity = details.name .. "\0" .. parentID
    if seen[identity] then
        return
    end
    if details.mapType == CONTINENT_MAP then
        seen[identity] = true
        local landmark = Landmark(MAP_KEY, nil, mapID, mapID, CONTINENT_CENTER, details.name, nil, "continent", place)
        add(landmark, MAP_DEPTH[CONTINENT_MAP])
        return
    end
    local area = static and static.areas[mapID]
    if area == nil then
        area = ReadMapArea(details)
        if static then
            static.areas[mapID] = area
        end
    end
    if area then
        seen[identity] = true
        local zone = details.mapType == ZONE_MAP
        local landmark =
            Landmark(MAP_KEY, nil, mapID, zone and mapID or parentID, area, details.name, nil, area.kind, place)
        add(landmark, MAP_DEPTH[details.mapType])
    end
end

function Maps.ReadHierarchy(rootID, static, checkpoint, phase)
    local maps, order = static.maps, static.order
    if not maps then
        maps, order = {}, {}
        phase(PHASE.CHILDREN_NATIVE)
        local children = Readable(C_Map.GetMapChildrenInfo(rootID, nil, true))
        if type(children) ~= "table" then
            return
        end
        checkpoint()
        phase(PHASE.CHILDREN_COPY)
        for _, details in ipairs(children) do
            details = Readable(details)
            local mapID = type(details) == "table" and Number(details.mapID)
            local name = mapID and Readable(details.name)
            if type(name) == "string" and name ~= "" then
                maps[mapID] = {
                    mapID = mapID,
                    name = name,
                    mapType = Number(details.mapType),
                    parentMapID = Number(details.parentMapID),
                }
                order[#order + 1] = mapID
            end
            checkpoint()
        end
        -- An empty world means the hierarchy was not available yet, so the next build reads it again.
        if order[1] then
            static.maps, static.order = maps, order
        end
    end
    return maps, order
end

function Maps.ReadMapPlace(mapID)
    local details = ReadMapDetails(mapID)
    return { zone = details and details.name, continent = Maps.ContinentName(mapID, ReadMapDetails) }
end

Maps.Depth = table.freeze(MAP_DEPTH)
Addon.LandmarkMaps = table.freeze(Maps)
