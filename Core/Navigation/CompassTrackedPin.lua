local _, Addon = ...
local C = Addon.Constants
local Plugin = Addon.Controller
local Utils = Addon.SourceUtils
local Readable, Number = Utils.Readable, Utils.Number

function Plugin:GetCompassTrackedPin()
    local tracking = C_SuperTrack.GetHighestPrioritySuperTrackingType()
    if
        Addon.Services.IsSecret(tracking, "Compass.SuperTracking")
        or Number(tracking) ~= Enum.SuperTrackingType.MapPin
    then
        return
    end
    local pinType, id = C_SuperTrack.GetSuperTrackedMapPin()
    pinType, id = Number(pinType), Number(id)
    if pinType and id and C.PIN_KEY_PREFIXES[pinType] then
        return pinType, id
    end
end

function Plugin:FollowsCompassPin(pinType, id)
    local selection = self.compassPinSelection
    return self.followTracked or (selection ~= nil and selection.pinType == pinType and selection.id == id)
end

function Plugin:SelectCompassPin(landmark)
    self.compassPinSelection = { pinType = landmark.pinType, id = landmark.id }
    self.compassPinDestination = landmark
end

function Plugin:ResolveCompassPinDestination(pinType, id)
    local destination = self.compassPinDestination
    if destination and destination.pinType == pinType and destination.id == id then
        return destination
    end
    -- A world-map click leaves the clicked map open, which locates the pin without a global index.
    local worldMap = Readable(WorldMapFrame)
    local mapID = worldMap and worldMap:IsShown() and Number(worldMap:GetMapID())
    destination = mapID and self:FindCompassLandmarkOnMap(mapID, pinType, id) or self:FindCompassLandmark(pinType, id)
    if destination then
        self.compassPinDestination = destination
    elseif self:CompassLandmarksInclude(pinType) then
        self:RequestCompassLandmarkCatalog()
    end
    return destination
end
