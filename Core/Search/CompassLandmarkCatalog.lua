local _, Addon = ...
local C = Addon.Constants
local Plugin = Addon.Controller
local F = Addon.ClientFeatures
local Utils = Addon.SourceUtils
local Readable, Number = Utils.Readable, Utils.Number
local Fold, Words, AddNameFields = Addon.Text.Fold, Addon.Text.Words, Addon.Text.AddNameFields
local ROOT_RETRY_SECONDS = 1
local DATA_RETRY_SECONDS = 30
local BUILD_BUDGET_MS = 1
local FOCUSED_BUILD_BUDGET_MS = 4
local REFRESH_AGE_SECONDS = 300
local LISTENER_INTERVAL = 0.25
local MAP_CENTER = 0.5
local CONTINENT_CENTER = table.freeze({ x = MAP_CENTER, y = MAP_CENTER })
local PIN_DEMAND = "pin"
local RAID_INFO_INDEX = 12
local AREA_POI = Enum.SuperTrackingMapPinType.AreaPOI
local TAXI_NODE = Enum.SuperTrackingMapPinType.TaxiNode
local DIG_SITE = Enum.SuperTrackingMapPinType.DigSite
local CONTINENT_MAP = Enum.UIMapType.Continent
local ZONE_MAP = Enum.UIMapType.Zone
local MICRO_MAP = Enum.UIMapType.Micro
local MAP_DEPTH = { [CONTINENT_MAP] = 1, [MICRO_MAP] = 2, [ZONE_MAP] = 3 }
local PRIMARY_MAP_BONUS = 4
local DUPLICATE_YARDS = 100
-- Zones outrank micro maps, which outrank continents, so later passes skip reads that cannot win.
local COLLECT_PASSES = { ZONE_MAP, MICRO_MAP, CONTINENT_MAP }
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
    COLLECT = "Compass.Landmarks.Collect",
    DUPLICATE_GROUPS = "Compass.Landmarks.Duplicates.Group",
    DUPLICATE_COMPARE = "Compass.Landmarks.Duplicates.Compare",
    DUPLICATE_COMPACT = "Compass.Landmarks.Duplicates.Compact",
}

local function EndPhase(catalog)
    if catalog.phaseStart then
        catalog.phaseProfiler:End(Plugin, catalog.phase, catalog.phaseStart, catalog.phaseStartKB)
        catalog.phaseStart, catalog.phaseStartKB, catalog.phaseProfiler = nil, nil, nil
    end
end

local function BeginPhase(catalog)
    local profiler = Addon.Services.profiler
    if catalog.phase and profiler then
        catalog.phaseStart, catalog.phaseStartKB = profiler:Begin()
        catalog.phaseProfiler = catalog.phaseStart and profiler or nil
    end
end

local function SetPhase(catalog, phase)
    EndPhase(catalog)
    catalog.phase = phase
    BeginPhase(catalog)
end

local function NoCheckpoint() end

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

local function NewStaticLayer()
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

local function Finalize(landmark, placeWords)
    local place = (landmark.zone or "") .. " " .. (landmark.continent or "")
    local words = placeWords[place]
    if not words then
        words = Words(Fold(place))
        table.freeze(words)
        placeWords[place] = words
    end
    landmark.placeWords = words
    return table.freeze(AddNameFields(landmark, landmark.name))
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

local function ContinentName(mapID, lookup)
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

local function CollectMapArea(details, place, add, seen, static)
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

local function IsAncestor(maps, ancestorID, mapID)
    local visited = {}
    local details = maps[mapID]
    while details and details.parentMapID and not visited[details.mapID] do
        visited[details.mapID] = true
        if details.parentMapID == ancestorID then
            return true
        end
        details = maps[details.parentMapID]
    end
    return false
end

local function MapDepth(maps, mapID)
    local details = maps[mapID]
    return details and MAP_DEPTH[details.mapType] or 0
end

local function WorldPosition(landmark, cache)
    local cached = cache[landmark]
    if not cached then
        local instance, position = C_Map.GetWorldPosFromMapPos(landmark.mapID, CreateVector2D(landmark.x, landmark.y))
        local x, y = Utils.ReadPosition(position)
        cached = { instance = Number(instance), x = x, y = y }
        cache[landmark] = cached
    end
    return cached
end

local function SamePlace(left, right, cache)
    local a, b = WorldPosition(left, cache), WorldPosition(right, cache)
    if not a.instance or a.instance ~= b.instance or not a.x or not b.x then
        return false
    end
    local east, north = a.x - b.x, a.y - b.y
    return east * east + north * north <= DUPLICATE_YARDS * DUPLICATE_YARDS
end

-- Parent and continent maps repeat a place under other POI IDs; only the deepest map's copy routes correctly.
local function Supersedes(keep, drop, target, maps, cache)
    if IsAncestor(maps, drop.mapID, keep.mapID) then
        return true
    end
    local keepDepth, dropDepth = MapDepth(maps, keep.mapID), MapDepth(maps, drop.mapID)
    if keepDepth > dropDepth and dropDepth == MAP_DEPTH[CONTINENT_MAP] then
        return true
    elseif keepDepth < dropDepth or IsAncestor(maps, keep.mapID, drop.mapID) or not SamePlace(keep, drop, cache) then
        return false
    end
    local keepRank, dropRank = target.ranks[keep.key], target.ranks[drop.key]
    return keepRank > dropRank or (keepRank == dropRank and keep.key < drop.key)
end

local function RemoveDuplicates(target, maps, checkpoint, phase)
    phase(PHASE.DUPLICATE_GROUPS)
    local groups = {}
    for _, landmark in ipairs(target.entries) do
        if not landmark.questID then
            local group = groups[landmark.name]
            if group then
                group[#group + 1] = landmark
            else
                groups[landmark.name] = { landmark }
            end
        end
        checkpoint()
    end
    local removed, cache = {}, {}
    phase(PHASE.DUPLICATE_COMPARE)
    for _, group in pairs(groups) do
        for _, candidate in ipairs(group) do
            for _, other in ipairs(group) do
                if other ~= candidate and Supersedes(other, candidate, target, maps, cache) then
                    removed[candidate.key] = true
                    checkpoint()
                    break
                end
                checkpoint()
            end
            checkpoint()
        end
    end
    local entries, positions, ranks = {}, {}, {}
    phase(PHASE.DUPLICATE_COMPACT)
    for _, landmark in ipairs(target.entries) do
        if not removed[landmark.key] then
            entries[#entries + 1] = landmark
            positions[landmark.key], ranks[landmark.key] = #entries, target.ranks[landmark.key]
        end
        checkpoint()
    end
    return entries, positions, ranks
end

local function BuildCatalog(catalog, target)
    local incomplete = false
    local placeWords = {}
    local function Phase(phase)
        SetPhase(catalog, phase)
    end
    local function Checkpoint(pending)
        incomplete = incomplete or pending == true
        if debugprofilestop() >= catalog.deadline then
            coroutine.yield()
        end
    end
    -- Collection is not in map order, so an equal rank still goes to the map the native list returned first.
    local owners, mapIndex = {}, 0
    local function Outranks(key, rank)
        local current = target.ranks[key]
        return not current or rank > current or (rank == current and mapIndex < owners[key])
    end
    local function Wins(prefix, id, rank)
        return Outranks(prefix .. id, rank)
    end
    local function Add(landmark, rank)
        if not landmark then
            return
        end
        local key = landmark.key
        local position = target.positions[key]
        if position and not Outranks(key, rank) then
            return
        end
        landmark = Finalize(landmark, placeWords)
        if not position then
            target.entries[#target.entries + 1] = landmark
            target.positions[key], target.ranks[key] = #target.entries, rank
        else
            target.entries[position], target.ranks[key] = landmark, rank
        end
        owners[key] = mapIndex
        if target == catalog then
            catalog.revision = catalog.revision + 1
        end
    end
    local static = catalog.static
    local maps, order = static.maps, static.order
    if not maps then
        maps, order = {}, {}
        Phase(PHASE.CHILDREN_NATIVE)
        local children = Readable(C_Map.GetMapChildrenInfo(catalog.rootID, nil, true))
        if type(children) ~= "table" then
            return false
        end
        Checkpoint()
        Phase(PHASE.CHILDREN_COPY)
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
            Checkpoint()
        end
        -- An empty world means the hierarchy was not available yet, so the next build reads it again.
        if order[1] then
            static.maps, static.order = maps, order
        end
    end
    local function Lookup(mapID)
        return maps[mapID]
    end
    local continents = {}
    local function Continent(mapID)
        local name = continents[mapID]
        if name == nil then
            name = ContinentName(mapID, Lookup) or false
            continents[mapID] = name
        end
        return name or nil
    end
    Checkpoint()
    local areas = {}
    Phase(PHASE.COLLECT)
    for index, mapID in ipairs(order) do
        local details = maps[mapID]
        if MAP_DEPTH[details.mapType] and details.parentMapID then
            mapIndex = index
            local parent = maps[details.parentMapID]
            CollectMapArea(details, { zone = parent and parent.name, continent = Continent(mapID) }, Add, areas, static)
        end
        Checkpoint()
    end
    for _, mapType in ipairs(COLLECT_PASSES) do
        local depth = MAP_DEPTH[mapType]
        for index, mapID in ipairs(order) do
            local details = maps[mapID]
            if details.mapType == mapType and details.parentMapID then
                mapIndex = index
                local place = { zone = details.name, continent = Continent(mapID) }
                CollectAreaPOIs(mapID, place, depth, Add, Checkpoint, {}, Wins, static)
                CollectTaxiNodes(mapID, place, depth, Add, Checkpoint, Wins, static)
                CollectDigSites(mapID, place, depth, Add, Checkpoint, Wins)
                CollectTaskQuests(mapID, place, depth, Add, Checkpoint, Wins)
                CollectGraveyards(mapID, place, depth, Add, Checkpoint, Wins, static)
                CollectInvasion(mapID, place, depth, Add, Checkpoint, Wins)
            end
            Checkpoint()
        end
    end
    local entries, positions, ranks = RemoveDuplicates(target, maps, Checkpoint, Phase)
    local queryIndex
    if not incomplete or target == catalog then
        queryIndex = Plugin:BuildCompassLandmarkQueryIndex(entries, Checkpoint, Phase)
    end
    target.entries, target.positions, target.ranks, target.queryIndex = entries, positions, ranks, queryIndex
    return incomplete and "incomplete" or true
end

function Plugin:InitializeCompassLandmarks()
    self.compassLandmarks = {
        state = "idle",
        entries = {},
        positions = {},
        ranks = {},
        revision = 0,
        demand = {},
        listeners = {},
        notifiedRevision = 0,
        listenerClock = 0,
    }
    self.compassLandmarkDriver = CreateFrame("Frame")
    local step = Addon.LibOrbitUI.Callbacks:Wrap(function(owner, elapsed)
        owner:StepCompassLandmarkDemand(elapsed)
    end, "Compass.LandmarkDemand")
    self.compassLandmarkDriverUpdate = function(_, elapsed)
        step(self, elapsed)
    end
end

local function IsDemandFocused(catalog)
    for _, focused in pairs(catalog.demand) do
        if focused then
            return true
        end
    end
    return false
end

local function NotifyListeners(catalog)
    catalog.notifiedRevision, catalog.listenerClock = catalog.revision, 0
    local profiler = Addon.Services.profiler
    if profiler and profiler.active and next(catalog.listeners) then
        profiler:Count(Plugin, "Landmarks/Notify")
    end
    for _, listener in pairs(catalog.listeners) do
        listener()
    end
end

function Plugin:RefreshCompassLandmarkDriver()
    local catalog = self.compassLandmarks
    local active = (catalog.state == "building" or catalog.state == "pending") and next(catalog.demand) ~= nil
    self.compassLandmarkDriver:SetScript("OnUpdate", active and self.compassLandmarkDriverUpdate or nil)
end

function Plugin:AcquireCompassLandmarkDemand(owner, focused)
    if not self:IsActive() or self:IsProfileSuppressed() then
        return
    end
    self.compassLandmarks.demand[owner] = focused == true
    self:RequestCompassLandmarkCatalog()
    self:RefreshCompassLandmarkDriver()
end

function Plugin:ReleaseCompassLandmarkDemand(owner)
    self.compassLandmarks.demand[owner] = nil
    self:RefreshCompassLandmarkDriver()
end

-- A persistent miss (dedup-removed, hostile or withheld pin) must not restart the world walk.
function Plugin:RequestCompassPinLandmarks(pinType, id)
    local catalog = self.compassLandmarks
    local key = PIN_KEYS[pinType] .. id
    if catalog.pinAttempted == key then
        return
    end
    self:AcquireCompassLandmarkDemand(PIN_DEMAND, false)
    catalog.pinAttempted = key
    if catalog.state ~= "building" and catalog.state ~= "pending" then
        catalog.demand[PIN_DEMAND] = nil
    end
end

function Plugin:PauseCompassPinLandmarks()
    local catalog = self.compassLandmarks
    if catalog.demand[PIN_DEMAND] ~= nil then
        catalog.demand[PIN_DEMAND], catalog.pinAttempted = nil, nil
        self.waypointDirty = true
        self:RefreshCompassLandmarkDriver()
    end
end

function Plugin:SetCompassLandmarkListener(owner, listener)
    self.compassLandmarks.listeners[owner] = listener
end

function Plugin:StepCompassLandmarkDemand(elapsed)
    local catalog = self.compassLandmarks
    self:StepCompassLandmarkCatalog()
    catalog.listenerClock = catalog.listenerClock + elapsed
    local interval = self:IsCompassLandmarkSearchUnindexed() and C.UNINDEXED_SEARCH_REFRESH or LISTENER_INTERVAL
    if catalog.listenerClock >= interval and catalog.revision ~= catalog.notifiedRevision then
        NotifyListeners(catalog)
    end
    if catalog.state ~= "building" then
        self:RefreshCompassLandmarkDriver()
    end
end

function Plugin:RequestCompassLandmarkCatalog()
    if not self:IsActive() or self:IsProfileSuppressed() then
        return
    end
    local catalog = self.compassLandmarks
    local now = GetTime()
    if catalog.rootRetryAt and now < catalog.rootRetryAt then
        return
    end
    local root = Addon.MapScope.Resolve(F.rootType, catalog.rootID)
    if not root then
        catalog.state, catalog.thread, catalog.target = "pending", nil, nil
        catalog.rootRetryAt = now + ROOT_RETRY_SECONDS
        return
    end
    catalog.rootRetryAt = nil
    if root ~= catalog.rootID then
        if catalog.rootID then
            catalog.pinAttempted = nil
        end
        catalog.rootID, catalog.state, catalog.thread, catalog.target = root, "idle", nil, nil
        catalog.entries, catalog.positions, catalog.ranks, catalog.queryIndex = {}, {}, {}, nil
        catalog.static = nil
        catalog.revision = catalog.revision + 1
        self.compassPinDestination = nil
        NotifyListeners(catalog)
    end
    catalog.static = catalog.static or NewStaticLayer()
    if not self:IsActive() or self:IsProfileSuppressed() or not next(catalog.demand) then
        return
    end
    local stale = catalog.state == "complete" and now - catalog.builtAt >= REFRESH_AGE_SECONDS
    if catalog.state == "idle" or catalog.state == "pending" or catalog.state == "failed" or stale then
        catalog.target = #catalog.entries == 0 and catalog or { entries = {}, positions = {}, ranks = {} }
        if catalog.target == catalog then
            catalog.queryIndex = nil
        end
        catalog.state = "building"
        catalog.phase = nil
        catalog.thread = coroutine.create(BuildCatalog)
    end
end

function Plugin:InvalidateCompassLandmarkScope()
    self:PauseCompassPinLandmarks()
    local catalog = self.compassLandmarks
    catalog.rootRetryAt = nil
    if catalog.rootID or next(catalog.demand) then
        self:RequestCompassLandmarkCatalog()
    end
    self:RefreshCompassLandmarkDriver()
end

function Plugin:StopCompassLandmarks()
    local catalog = self.compassLandmarks
    catalog.state, catalog.thread, catalog.target, catalog.static = "idle", nil, nil, nil
    catalog.pinAttempted = nil
    wipe(catalog.demand)
    wipe(catalog.listeners)
    self:RefreshCompassLandmarkDriver()
end

function Plugin:StepCompassLandmarkCatalog()
    local catalog = self.compassLandmarks
    local now = GetTime()
    if catalog.state == "pending" then
        self:RequestCompassLandmarkCatalog()
    end
    if catalog.state ~= "building" then
        return
    end
    local profiler = Addon.Services.profiler
    local start, startKB
    if profiler then
        start, startKB = profiler:Begin()
    end
    -- A refresh builds beside a published index that already answers searches, so typing never waits on it.
    local waiting = catalog.target == catalog and IsDemandFocused(catalog)
    local budget = waiting and FOCUSED_BUILD_BUDGET_MS or BUILD_BUDGET_MS
    catalog.deadline = debugprofilestop() + budget
    local thread = catalog.thread
    BeginPhase(catalog)
    local ok, err = coroutine.resume(thread, catalog, catalog.target)
    EndPhase(catalog)
    if start then
        profiler:End(self, "Compass.Landmarks", start, startKB)
    end
    if not ok then
        catalog.state, catalog.thread, catalog.target = "failed", nil, nil
        catalog.rootRetryAt = now + DATA_RETRY_SECONDS
        catalog.demand[PIN_DEMAND] = nil
        error(err, 0)
    end
    if catalog.thread ~= thread then
        return
    end
    if coroutine.status(thread) == "dead" then
        if err == false or err == "incomplete" then
            catalog.state, catalog.thread, catalog.target = "pending", nil, nil
            catalog.rootRetryAt = now + (err == false and ROOT_RETRY_SECONDS or DATA_RETRY_SECONDS)
            if err == "incomplete" then
                catalog.demand[PIN_DEMAND] = nil
            end
            NotifyListeners(catalog)
            return
        end
        local target = catalog.target
        catalog.entries, catalog.positions, catalog.ranks = target.entries, target.positions, target.ranks
        catalog.queryIndex = target.queryIndex
        catalog.state, catalog.thread, catalog.target = "complete", nil, nil
        catalog.builtAt, catalog.revision = GetTime(), catalog.revision + 1
        catalog.demand[PIN_DEMAND] = nil
        NotifyListeners(catalog)
        -- Pins tracked before the index existed can now resolve their destination and route artwork.
        self.compassSources.route.dirty = true
        self.discoveryPending, self.waypointDirty = true, true
    end
end

function Plugin:IsCompassLandmarkCatalogBuilding()
    return self.compassLandmarks.state == "building" or self.compassLandmarks.state == "pending"
end

-- A first build publishes entries before their index, so each search meanwhile scans every collected entry.
function Plugin:IsCompassLandmarkSearchUnindexed()
    local catalog = self.compassLandmarks
    return catalog.queryIndex == nil and #catalog.entries > 0 and self:IsCompassLandmarkCatalogBuilding()
end

function Plugin:CompassLandmarksInclude(pinType)
    return PIN_KEYS[pinType] ~= nil
end

function Plugin:FindCompassLandmark(pinType, id)
    local prefix = PIN_KEYS[pinType]
    local catalog = self.compassLandmarks
    local position = prefix and catalog.positions[prefix .. id]
    return position and catalog.entries[position]
end

function Plugin:FindCompassLandmarkOnMap(mapID, pinType, id)
    local details = ReadMapDetails(mapID)
    local place = { zone = details and details.name, continent = ContinentName(mapID, ReadMapDetails) }
    local key = PIN_KEYS[pinType] and PIN_KEYS[pinType] .. id
    local found
    local function Add(landmark)
        if landmark and landmark.key == key then
            found = Finalize(landmark, {})
        end
    end
    local function Wanted(prefix, candidate)
        return prefix .. candidate == key
    end
    if pinType == AREA_POI then
        CollectAreaPOIs(mapID, place, 0, Add, NoCheckpoint, {}, Wanted)
    elseif pinType == TAXI_NODE then
        CollectTaxiNodes(mapID, place, 0, Add, NoCheckpoint, Wanted)
    elseif pinType == DIG_SITE then
        CollectDigSites(mapID, place, 0, Add, NoCheckpoint, Wanted)
    end
    return found
end

function Plugin:GetCompassLandmarks()
    local catalog = self.compassLandmarks
    return catalog.entries, catalog.revision
end
