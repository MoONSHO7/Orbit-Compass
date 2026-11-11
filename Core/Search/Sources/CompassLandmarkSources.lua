local _, Addon = ...
local CollectAreaPOIs = Addon.LandmarkAreaPOIs.Collect
local Travel = Addon.LandmarkTravel
local Activities = Addon.LandmarkActivities
local CollectTaxiNodes, CollectGraveyards = Travel.CollectTaxiNodes, Travel.CollectGraveyards
local CollectDigSites = Activities.CollectDigSites
local CollectTaskQuests = Activities.CollectTaskQuests
local CollectInvasion = Activities.CollectInvasion

local AREA_POI = Enum.SuperTrackingMapPinType.AreaPOI
local TAXI_NODE = Enum.SuperTrackingMapPinType.TaxiNode
local DIG_SITE = Enum.SuperTrackingMapPinType.DigSite
local Sources = {}

function Sources.NewStaticLayer()
    return { areas = {}, entrances = {}, links = {}, taxi = {}, graveyards = {} }
end

function Sources.CollectMap(mapID, place, depth, add, checkpoint, wins, static)
    CollectAreaPOIs(mapID, place, depth, add, checkpoint, {}, wins, static)
    CollectTaxiNodes(mapID, place, depth, add, checkpoint, wins, static)
    CollectDigSites(mapID, place, depth, add, checkpoint, wins)
    CollectTaskQuests(mapID, place, depth, add, checkpoint, wins)
    CollectGraveyards(mapID, place, depth, add, checkpoint, wins, static)
    CollectInvasion(mapID, place, depth, add, checkpoint, wins)
end

local function NoCheckpoint() end

function Sources.CollectPin(mapID, pinType, place, add, wanted)
    if pinType == AREA_POI then
        CollectAreaPOIs(mapID, place, 0, add, NoCheckpoint, {}, wanted)
    elseif pinType == TAXI_NODE then
        CollectTaxiNodes(mapID, place, 0, add, NoCheckpoint, wanted)
    elseif pinType == DIG_SITE then
        CollectDigSites(mapID, place, 0, add, NoCheckpoint, wanted)
    end
end

Addon.LandmarkSources = table.freeze(Sources)
