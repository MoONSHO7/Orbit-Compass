local _, Addon = ...
local F = Addon.ClientFeatures
local Utils = Addon.SourceUtils
local Readable, Number = Utils.Readable, Utils.Number
local Record = Addon.LandmarkRecord
local Landmark, InMap = Record.New, Record.InMap
local PIN_KEYS = Record.PinKeys
local StaticRecords = Addon.LandmarkRead.StaticRecords

local TAXI_NODE = Enum.SuperTrackingMapPinType.TaxiNode
local GRAVEYARD_KEY = "graveyard:"

-- Taxi lists repeat a continent's nodes on every map, so only nodes a landmark could place are kept.
local function ReadTaxiNode(node)
    local id = type(node) == "table" and Number(node.nodeID)
    local x, y = Utils.ReadPosition(id and node.position)
    if InMap(x, y) then
        local name, atlas = Readable(node.name), Readable(node.atlasName)
        return { id = id, x = x, y = y, name = name, atlas = atlas, side = Number(node.faction) }
    end
end

local function ReadTaxiNodes(mapID)
    return C_TaxiMap.GetTaxiNodesForMap(mapID)
end

local function CollectTaxiNodes(mapID, place, depth, add, checkpoint, wins, static)
    if not F.taxi then
        return
    end
    local faction = Readable(UnitFactionGroup("player"))
    local key = PIN_KEYS[TAXI_NODE]
    for _, node in ipairs(StaticRecords(static, "taxi", mapID, checkpoint, ReadTaxiNodes, ReadTaxiNode)) do
        local side = node.side
        local friendly = side == Enum.FlightPathFaction.Neutral
            or (side == Enum.FlightPathFaction.Alliance and faction == "Alliance")
            or (side == Enum.FlightPathFaction.Horde and faction == "Horde")
        if friendly and wins(key, node.id, depth) then
            add(Landmark(key, TAXI_NODE, node.id, mapID, node, node.name, node.atlas, "flightMaster", place), depth)
        end
        checkpoint()
    end
end

local function ReadGraveyard(info)
    local id = type(info) == "table" and Number(info.graveyardID)
    local x, y = Utils.ReadPosition(id and info.position)
    if InMap(x, y) then
        return { id = id, x = x, y = y, name = Readable(info.name) }
    end
end

local function ReadGraveyards(mapID)
    return C_DeathInfo.GetGraveyardsForMap(mapID)
end

local function CollectGraveyards(mapID, place, depth, add, checkpoint, wins, static)
    if not F.graveyards then
        return
    end
    for _, grave in ipairs(StaticRecords(static, "graveyards", mapID, checkpoint, ReadGraveyards, ReadGraveyard)) do
        if wins(GRAVEYARD_KEY, grave.id, depth) then
            add(Landmark(GRAVEYARD_KEY, nil, grave.id, mapID, grave, grave.name, nil, "graveyard", place), depth)
        end
        checkpoint()
    end
end

Addon.LandmarkTravel = table.freeze({
    CollectTaxiNodes = CollectTaxiNodes,
    CollectGraveyards = CollectGraveyards,
})
