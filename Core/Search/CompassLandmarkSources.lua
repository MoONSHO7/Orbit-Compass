local _, Addon = ...
local C = Addon.Constants
local F = Addon.ClientFeatures
local Utils = Addon.SourceUtils
local Readable, Number = Utils.Readable, Utils.Number
local Sources = {}

local MAP_CENTER = 0.5
local CONTINENT_CENTER = table.freeze({ x = MAP_CENTER, y = MAP_CENTER })
local RAID_INFO_INDEX = 12
local AREA_POI = Enum.SuperTrackingMapPinType.AreaPOI
local TAXI_NODE = Enum.SuperTrackingMapPinType.TaxiNode
local DIG_SITE = Enum.SuperTrackingMapPinType.DigSite
local CONTINENT_MAP = Enum.UIMapType.Continent
local ZONE_MAP = Enum.UIMapType.Zone
local MICRO_MAP = Enum.UIMapType.Micro
local MAP_DEPTH = { [CONTINENT_MAP] = 1, [MICRO_MAP] = 2, [ZONE_MAP] = 3 }
local PRIMARY_MAP_BONUS = 4
local TELEPORT_ATLAS_PREFIX = "taxinode_continent"
local CAVE_ATLAS_PATTERN = "cave"
local DIG_SITE_ATLAS = "ArchBlob"
local PET_TAMER_ATLAS = "WildBattlePetCapturable"
local WORLD_QUEST_ATLAS = "worldquest-icon"
local WORLD_BOSS_ATLAS = "vignettekillboss"
local BONUS_OBJECTIVE_ATLAS = "Bonus-Objective-Star"
local AREA_GROUPS = {
    { enabled = F.delves, query = C_AreaPoiInfo and C_AreaPoiInfo.GetDelvesForMap, kind = "delve" },
    { enabled = F.events, query = C_AreaPoiInfo and C_AreaPoiInfo.GetEventsForMap, kind = "event" },
    { enabled = F.races, query = C_AreaPoiInfo and C_AreaPoiInfo.GetDragonridingRacesForMap, kind = "race" },
    { enabled = F.questHubs, query = C_AreaPoiInfo and C_AreaPoiInfo.GetQuestHubsForMap, kind = "questHub" },
    { enabled = F.genericPOIs, query = C_AreaPoiInfo and C_AreaPoiInfo.GetAreaPOIForMap, kind = "poi" },
}
local PIN_KEYS = {}
for name, prefix in pairs({ AreaPOI = "poi:", TaxiNode = "taxi:", DigSite = "digSite:" }) do
    local value = Enum.SuperTrackingMapPinType[name]
    if value ~= nil and (name ~= "DigSite" or F.digSites) then
        PIN_KEYS[value] = prefix
    end
end
local QUEST_KEY = "quest:"
local MAP_KEY = "map:"
local GRAVEYARD_KEY = "graveyard:"
local INVASION_KEY = "invasion:"
local PHASE = {
    CHILDREN_NATIVE = "Compass.Landmarks.Children.Native",
    CHILDREN_COPY = "Compass.Landmarks.Children.Copy",
}

local function ReadList(value, checkpoint)
    value = Readable(value)
    checkpoint(value ~= false and type(value) ~= "table")
    return type(value) == "table" and value or {}
end

-- Fixed places are normalized once per root; `static` nil reads natively for a single map lookup.
local function StaticRecords(static, source, mapID, checkpoint, read, normalize)
    local cache = static and static[source]
    local records = cache and cache[mapID]
    if records then
        return records
    end
    local value = Readable(read(mapID))
    checkpoint(value ~= false and type(value) ~= "table")
    if value ~= false and type(value) ~= "table" then
        return {}
    end
    records = {}
    for _, item in ipairs(value or {}) do
        records[#records + 1] = normalize(Readable(item))
        checkpoint()
    end
    if cache then
        cache[mapID] = records
    end
    return records
end

function Sources.NewStaticLayer()
    return { areas = {}, entrances = {}, links = {}, taxi = {}, graveyards = {} }
end

local function ReadAtlas(atlas, fallback)
    atlas = Readable(atlas)
    return Addon.Artwork.Resolve(type(atlas) == "string" and atlas ~= "" and atlas or fallback)
end

local function InMap(x, y)
    return x ~= nil and y ~= nil and x >= 0 and x <= 1 and y >= 0 and y <= 1
end

local function Landmark(key, pinType, id, mapID, position, name, atlas, kind, place)
    if not F.AllowsKind(kind) then
        return
    end
    local x, y = Utils.ReadPosition(position)
    name = Readable(name)
    if not InMap(x, y) or type(name) ~= "string" or name == "" then
        return
    end
    local zone = place.zone ~= name and place.zone or nil
    local continent = place.continent ~= name and place.continent ~= zone and place.continent or nil
    local landmark = {
        indexed = true,
        key = key .. id,
        pinType = pinType,
        id = id,
        questID = key == QUEST_KEY and id or nil,
        mapID = mapID,
        x = x,
        y = y,
        name = name,
        atlas = ReadAtlas(atlas, C.FALLBACK_ATLAS),
        kind = kind,
        zone = zone,
        continent = continent,
    }
    return landmark
end

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

function Sources.ContinentName(mapID, lookup)
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

local function CollectDigSites(mapID, place, depth, add, checkpoint, wins)
    if not F.digSites then
        return
    end
    for _, info in ipairs(ReadList(C_ResearchInfo.GetDigSitesForMap(mapID), checkpoint)) do
        info = Readable(info)
        local id = type(info) == "table" and Number(info.researchSiteID)
        local key = PIN_KEYS[DIG_SITE]
        if id and wins(key, id, depth) then
            add(Landmark(key, DIG_SITE, id, mapID, info.position, info.name, DIG_SITE_ATLAS, "digSite", place), depth)
        end
        checkpoint()
    end
end

local function CollectTaskQuests(mapID, place, depth, add, checkpoint, wins)
    if not F.tasks then
        return
    end
    for _, info in ipairs(ReadList(C_TaskQuest.GetQuestsOnMap(mapID), checkpoint)) do
        info = Readable(info)
        local questID = type(info) == "table" and Number(info.questID)
        local rank = questID and depth - (Number(info.childDepth) or 0)
        if questID and Readable(info.isMapIndicatorQuest) ~= true and wins(QUEST_KEY, questID, rank) then
            local title = Readable(C_TaskQuest.GetQuestInfoByQuestID(questID))
            local kind, atlas = "bonusObjective", BONUS_OBJECTIVE_ATLAS
            if Number(info.questTagType) == Enum.QuestTagType.WorldBoss then
                kind, atlas = "worldBoss", WORLD_BOSS_ATLAS
            elseif Readable(C_QuestLog.IsWorldQuest(questID)) == true then
                kind, atlas = "worldQuest", WORLD_QUEST_ATLAS
            end
            local position = { x = info.x, y = info.y }
            add(Landmark(QUEST_KEY, nil, questID, mapID, position, title, atlas, kind, place), rank)
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

local function CollectInvasion(mapID, place, depth, add, checkpoint, wins)
    if not F.invasions then
        return
    end
    local id = Number(C_InvasionInfo.GetInvasionForUiMapID(mapID))
    checkpoint()
    local info = id and wins(INVASION_KEY, id, depth) and Readable(C_InvasionInfo.GetInvasionInfo(id))
    if type(info) == "table" then
        add(Landmark(INVASION_KEY, nil, id, mapID, info.position, info.name, info.atlasName, "invasion", place), depth)
    end
end

-- A zone's waypoint kind or a micro map's centre on its parent; false when neither can take a waypoint.
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

function Sources.CollectArea(details, place, add, seen, static)
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

function Sources.ReadHierarchy(rootID, static, checkpoint, phase)
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

function Sources.ReadMapPlace(mapID)
    local details = ReadMapDetails(mapID)
    return { zone = details and details.name, continent = Sources.ContinentName(mapID, ReadMapDetails) }
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

Sources.MapDepth = table.freeze(MAP_DEPTH)
Sources.PinKeys = table.freeze(PIN_KEYS)
Addon.LandmarkSources = table.freeze(Sources)
