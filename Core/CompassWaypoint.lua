local _, Addon = ...
local L = Addon.L
local Plugin = Addon.Controller
local IsSecret = Addon.Services.IsSecret
local COORDINATE_SCALE = 100
local COORDINATE_EPSILON = 0.00001
local MAX_INPUT_LENGTH = 1024
local NUMBER_PATTERN = "([%+%-]?[%d%.]+)"

local function Number(value)
    if
        not IsSecret(value, "Compass.Waypoint")
        and type(value) == "number"
        and value == value
        and math.abs(value) < math.huge
    then
        return value
    end
end

local function Text(value)
    if not IsSecret(value, "Compass.Waypoint") and type(value) == "string" then
        return value:match("^%s*(.-)%s*$")
    end
end

function Plugin:SetWaypoint(mapID, x, y, title)
    mapID, x, y = Number(mapID), Number(x), Number(y)
    if not mapID or mapID <= 0 or mapID % 1 ~= 0 or not x or not y or x < 0 or x > 1 or y < 0 or y > 1 then
        return false, L.CMD_COMPASS_INVALID
    end
    local mapInfo, canSet = C_Map.GetMapInfo(mapID), C_Map.CanSetUserWaypointOnMap(mapID)
    if
        IsSecret(mapInfo, "Compass.Waypoint")
        or not mapInfo
        or IsSecret(canSet, "Compass.Waypoint")
        or canSet ~= true
    then
        return false, L.CMD_COMPASS_UNAVAILABLE
    end
    local success = C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(mapID, x, y))
    if IsSecret(success, "Compass.Waypoint") or success ~= true then
        return false, L.CMD_COMPASS_UNAVAILABLE
    end
    title = Text(title)
    C_SuperTrack.SetSuperTrackedUserWaypoint(true)
    self.dismissedNavigationKey = nil
    if self:IsActive() then
        self:SetCompassTomTomTarget(nil)
    end
    self.waypointLabel = { mapID = mapID, x = x, y = y, title = title ~= "" and title or nil }
    self.waypointDirty = true
    return true
end

function Plugin:ClearWaypoint()
    C_Map.ClearUserWaypoint()
    self.waypointLabel = nil
    self.waypointDirty = true
end

function Plugin:GetWaypointTitle(mapID, x, y)
    local label = self.waypointLabel
    if
        label
        and label.mapID == mapID
        and math.abs(label.x - x) < COORDINATE_EPSILON
        and math.abs(label.y - y) < COORDINATE_EPSILON
    then
        return label.title or L.PLU_COMPASS_WAYPOINT
    end
    self.waypointLabel = nil
    return L.PLU_COMPASS_WAYPOINT
end

function Plugin:SetWaypointFromText(input)
    input = Text(input)
    if not input or #input > MAX_INPUT_LENGTH then
        return false, L.CMD_COMPASS_INVALID
    end
    local command, rest = input:match("^(/%S+)%s+(.*)$")
    if command then
        command = command:lower()
        if
            command ~= "/way"
            and command ~= "/tway"
            and command ~= "/tomtomway"
            and command ~= "/orbitway"
            and command ~= "/oway"
        then
            return false, L.CMD_COMPASS_INVALID
        end
        input = rest
    end
    local link = input:match("|H(worldmap:[^|]+)|h") or input:match("^(worldmap:[%d:%.%-]+)$")
    if link then
        local point = C_Map.GetUserWaypointFromHyperlink(link)
        if
            not IsSecret(point, "Compass.Waypoint")
            and point
            and not IsSecret(point.position, "Compass.Waypoint")
            and point.position
        then
            return self:SetWaypoint(point.uiMapID, point.position.x, point.position.y)
        end
        return false, L.CMD_COMPASS_INVALID
    end
    local mapID, coordinates = input:match("^#(%d+)%s+(.*)$")
    if mapID then
        mapID, input = tonumber(mapID), coordinates
    else
        mapID = C_Map.GetBestMapForUnit("player")
    end
    local x, y, title = input:match("^" .. NUMBER_PATTERN .. "[%s,]+" .. NUMBER_PATTERN .. "(.*)$")
    if not x or (title ~= "" and not title:match("^%s")) then
        return false, L.CMD_COMPASS_INVALID
    end
    x, y = tonumber(x), tonumber(y)
    if not x or not y then
        return false, L.CMD_COMPASS_INVALID
    end
    return self:SetWaypoint(mapID, x / COORDINATE_SCALE, y / COORDINATE_SCALE, title)
end
