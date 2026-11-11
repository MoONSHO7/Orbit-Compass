local _, Addon = ...
local F = Addon.ClientFeatures
local Utils = Addon.SourceUtils
local Readable, Number = Utils.Readable, Utils.Number
local Record = Addon.LandmarkRecord
local Read = Addon.LandmarkRead
local ReadList, StaticRecords = Read.List, Read.StaticRecords
local Landmark, ReadAtlas = Record.New, Record.ReadAtlas
local PIN_KEYS = Record.PinKeys

local AREA_POI = Enum.SuperTrackingMapPinType.AreaPOI
local RAID_INFO_INDEX = 12
local PRIMARY_MAP_BONUS = 4
local TELEPORT_ATLAS_PREFIX = "taxinode_continent"
local CAVE_ATLAS_PATTERN = "cave"
local PET_TAMER_ATLAS = "WildBattlePetCapturable"
local AREA_GROUPS = {
    { enabled = F.delves, query = C_AreaPoiInfo and C_AreaPoiInfo.GetDelvesForMap, kind = "delve" },
    { enabled = F.events, query = C_AreaPoiInfo and C_AreaPoiInfo.GetEventsForMap, kind = "event" },
    { enabled = F.races, query = C_AreaPoiInfo and C_AreaPoiInfo.GetDragonridingRacesForMap, kind = "race" },
    { enabled = F.questHubs, query = C_AreaPoiInfo and C_AreaPoiInfo.GetQuestHubsForMap, kind = "questHub" },
    { enabled = F.genericPOIs, query = C_AreaPoiInfo and C_AreaPoiInfo.GetAreaPOIForMap, kind = "poi" },
}

local function AreaKind(kind, atlas)
    local lowered = type(atlas) == "string" and string.lower(atlas) or ""
    if string.sub(lowered, 1, #TELEPORT_ATLAS_PREFIX) == TELEPORT_ATLAS_PREFIX then
        return "teleport"
    end
    return kind
end

local function AddAreaPOI(add, id, mapID, info, kind, place, rank)
    local atlas = Readable(info.atlasName)
    add(Landmark(PIN_KEYS[AREA_POI], AREA_POI, id, mapID, info.position, info.name, atlas, kind, place), rank)
end

-- Off-map entrances and links stay cached because their IDs still claim the map's later category lists.
local function ReadAreaRecord(info)
    local id = type(info) == "table" and Number(info.areaPoiID)
    if id then
        local x, y = Utils.ReadPosition(info.position)
        local name, atlas = Readable(info.name), Readable(info.atlasName)
        return { id = id, x = x, y = y, name = name, atlas = atlas, journalID = Number(info.journalInstanceID) }
    end
end

local function ReadEntrances(mapID)
    return F.dungeonEntrances and C_EncounterJournal.GetDungeonEntrancesForMap(mapID)
end

local function ReadLinks(mapID)
    return F.links and C_Map.GetMapLinksForMap(mapID)
end

local function EntranceKind(record)
    if record.kind == nil then
        record.kind = "instance"
        if F.journalClassification and record.journalID then
            local isRaid = Readable(select(RAID_INFO_INDEX, EJ_GetInstanceInfo(record.journalID)))
            if isRaid ~= nil then
                record.kind = isRaid and "raid" or "dungeon"
            end
        end
    end
    return record.kind
end

local function AddAreaRecord(add, record, mapID, kind, place, rank)
    add(Landmark(PIN_KEYS[AREA_POI], AREA_POI, record.id, mapID, record, record.name, record.atlas, kind, place), rank)
end

local function CollectAreaPOIs(mapID, place, depth, add, checkpoint, seen, wins, static)
    local prefix = PIN_KEYS[AREA_POI]
    for _, record in ipairs(StaticRecords(static, "entrances", mapID, checkpoint, ReadEntrances, ReadAreaRecord)) do
        local id = record.id
        if not seen[id] then
            seen[id] = true
            if wins(prefix, id, depth) then
                AddAreaRecord(add, record, mapID, EntranceKind(record), place, depth)
            end
        end
        checkpoint()
    end
    for _, group in ipairs(AREA_GROUPS) do
        local ids = ReadList(group.enabled and group.query(mapID), checkpoint)
        for _, id in ipairs(ids) do
            id = Number(id)
            if id and not seen[id] then
                -- Claim category membership first; the generic list repeats categorized IDs.
                seen[id] = true
                local info = wins(prefix, id, depth + PRIMARY_MAP_BONUS)
                    and Readable(C_AreaPoiInfo.GetAreaPOIInfo(mapID, id))
                if type(info) == "table" then
                    local rank = depth + (Readable(info.isPrimaryMapForPOI) == true and PRIMARY_MAP_BONUS or 0)
                    AddAreaPOI(add, id, mapID, info, AreaKind(group.kind, Readable(info.atlasName)), place, rank)
                end
                checkpoint()
            end
        end
    end
    for _, record in ipairs(StaticRecords(static, "links", mapID, checkpoint, ReadLinks, ReadAreaRecord)) do
        local id = record.id
        if not seen[id] then
            seen[id] = true
            if wins(prefix, id, depth) then
                local atlas = record.atlas
                local isCave = type(atlas) == "string" and string.find(string.lower(atlas), CAVE_ATLAS_PATTERN, 1, true)
                AddAreaRecord(add, record, mapID, isCave and "cave" or AreaKind("mapLink", atlas), place, depth)
            end
        end
        checkpoint()
    end
    for _, info in ipairs(ReadList(F.petTamers and C_PetInfo.GetPetTamersForMap(mapID), checkpoint)) do
        info = Readable(info)
        local id = type(info) == "table" and Number(info.areaPoiID)
        if id and not seen[id] then
            seen[id] = true
            if wins(prefix, id, depth) then
                local atlas = ReadAtlas(info.atlasName, PET_TAMER_ATLAS)
                add(Landmark(prefix, AREA_POI, id, mapID, info.position, info.name, atlas, "petTamer", place), depth)
            end
        end
        checkpoint()
    end
end

Addon.LandmarkAreaPOIs = table.freeze({
    Collect = CollectAreaPOIs,
})
