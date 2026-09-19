local _, Addon = ...
local L = Addon.L
local C = Addon.Constants
local Plugin = Addon.Controller
local Utils = Addon.SourceUtils
local DESTINATION_VERSION = 1
local MAX_LOCATION_NAME = 80
local MAX_LOCATIONS = 100
local INVALID_NAME_PATTERN = "[|%z\1-\31\127]"

local function LocationName(name)
    name = Utils.Readable(name)
    if type(name) ~= "string" then
        return
    end
    name = name:match("^%s*(.-)%s*$")
    if name ~= "" and strlenutf8(name) <= MAX_LOCATION_NAME and not name:find(INVALID_NAME_PATTERN) then
        return name
    end
end

function Plugin:IsCompassLocationUsable(location)
    if
        type(location) ~= "table"
        or location.destinationVersion ~= DESTINATION_VERSION
        or location.clientFamily ~= Addon.ClientFeatures.family
        or not Utils.IsMapPosition(location)
    then
        return false
    end
    local mapID = Utils.Number(location.mapID)
    local info = mapID and Utils.Readable(C_Map.GetMapInfo(mapID))
    if type(info) ~= "table" then
        return false
    end
    if location.worldInstance ~= nil then
        local instance = Utils.Number(C_Map.GetWorldPosFromMapPos(mapID, CreateVector2D(location.x, location.y)))
        if instance ~= location.worldInstance then
            return false
        end
    end
    return true
end

function Plugin:FindCompassLocation(name)
    local id = name:lower()
    return self.compassLocations:Get(Addon.ClientFeatures.family .. ":" .. id) or self.compassLocations:Get(id)
end

function Plugin:SaveCompassLocation(name, useTarget)
    name = LocationName(name)
    if not name then
        return false, L.CMD_COMPASS_LOCATION_NAME
    end
    local target = useTarget and self.navigationTarget
    if target and target.kind == "route" and not target.routeDestination then
        return false, L.CMD_COMPASS_UNAVAILABLE
    end
    local destination = target and target.destination
    local mapID, x, y
    if destination then
        mapID, x, y = destination.mapID, destination.x, destination.y
    elseif not useTarget then
        mapID = Utils.Number(C_Map.GetBestMapForUnit("player"))
        if mapID then
            x, y = Utils.ReadPosition(C_Map.GetPlayerMapPosition(mapID, "player"))
        end
    end
    if not mapID or not Utils.IsMapPosition({ x = x, y = y }) then
        return false, L.CMD_COMPASS_UNAVAILABLE
    end
    local id, count = Addon.ClientFeatures.family .. ":" .. name:lower(), 0
    for _ in pairs(self.compassLocations:Records()) do
        count = count + 1
    end
    if count >= MAX_LOCATIONS and not self.compassLocations:Get(id) then
        return false, L.CMD_COMPASS_LOCATION_LIMIT
    end
    local worldInstance = Utils.Number(C_Map.GetWorldPosFromMapPos(mapID, CreateVector2D(x, y)))
    self.compassLocations:Insert({
        id = id,
        name = name,
        mapID = mapID,
        x = x,
        y = y,
        clientFamily = Addon.ClientFeatures.family,
        destinationVersion = DESTINATION_VERSION,
        worldInstance = worldInstance,
    })
    self:InvalidateCompassSource("ORBIT_COMPASS_LOCATIONS")
    return true, L.CMD_COMPASS_LOCATION_SAVED_F:format(name)
end

function Plugin:CollectCompassLocations(markers)
    if not self.showSavedLocations then
        return
    end
    for id, location in pairs(self.compassLocations:Records()) do
        if self:IsCompassLocationUsable(location) then
            local mapID = Utils.Number(location.mapID)
            if mapID == self.mapID and Utils.IsMapPosition(location) then
                Utils.AddMarker(
                    self,
                    markers,
                    "saved:" .. id,
                    location,
                    location.name,
                    C.FALLBACK_ATLAS,
                    C.POI_PRIORITY,
                    "saved"
                )
            end
        end
        self:CompassDiscoveryCheckpoint()
    end
end

function Plugin:HandleCompassLocationCommand(command, argument)
    if command == "save" or command == "savepin" then
        local _, reason = self:SaveCompassLocation(argument, command == "savepin")
        print(reason)
    elseif command == "go" or command == "forget" then
        local name = LocationName(argument)
        local location = name and self:FindCompassLocation(name)
        if not location then
            print(L.CMD_COMPASS_NO_MATCH)
        elseif command == "forget" then
            self.compassLocations:Remove(location.id)
            self:InvalidateCompassSource("ORBIT_COMPASS_LOCATIONS")
            print(L.CMD_COMPASS_LOCATION_REMOVED_F:format(location.name))
        elseif not self:IsCompassLocationUsable(location) then
            print(L.CMD_COMPASS_LOCATION_CLIENT)
        else
            local success, reason = self:SetWaypoint(location.mapID, location.x, location.y, location.name)
            print(success and L.CMD_COMPASS_SET or reason)
        end
    elseif command == "list" then
        local names = {}
        for _, location in pairs(self.compassLocations:Records()) do
            names[#names + 1] = self:IsCompassLocationUsable(location) and location.name
                or L.CMD_COMPASS_LOCATION_DORMANT_F:format(location.name, location.id)
        end
        table.sort(names)
        print(#names > 0 and table.concat(names, ", ") or L.CMD_COMPASS_NO_MATCH)
    else
        return false
    end
    return true
end
