local _, Addon = ...
local C = Addon.Constants
local Plugin = Addon.Controller
local F = Addon.ClientFeatures
local Utils = Addon.SourceUtils
local Readable, Number = Utils.Readable, Utils.Number
local AddSearchFields = Addon.Text.AddSearchFields
local ROOT_RETRY_SECONDS = 1
local DATA_RETRY_SECONDS = 30
local BUILD_BUDGET_MS = 1
local FOCUSED_BUILD_BUDGET_MS = 4
local REFRESH_AGE_SECONDS = 300
local LISTENER_INTERVAL = 0.25
local MAP_CENTER = 0.5
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

local function NoCheckpoint() end

local function ReadList(value, checkpoint)
    value = Readable(value)
    if value ~= false and type(value) ~= "table" then
        checkpoint(true)
    end
    return type(value) == "table" and value or {}
end

local function ReadAtlas(atlas, fallback)
    atlas = Readable(atlas)
    return Addon.Artwork.Resolve(type(atlas) == "string" and atlas ~= "" and atlas or fallback)
end

local function Landmark(key, pinType, id, mapID, position, name, atlas, kind, place)
    if not F.AllowsKind(kind) then
        return
    end
    local x, y = Utils.ReadPosition(position)
    name = Readable(name)
    if not x or not y or x < 0 or x > 1 or y < 0 or y > 1 or type(name) ~= "string" or name == "" then
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
    return table.freeze(AddSearchFields(landmark, name, (zone or "") .. " " .. (continent or "")))
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

local function CollectAreaPOIs(mapID, place, depth, add, checkpoint, seen)
    for _, info in
        ipairs(ReadList(F.dungeonEntrances and C_EncounterJournal.GetDungeonEntrancesForMap(mapID), checkpoint))
    do
        info = Readable(info)
        local id = type(info) == "table" and Number(info.areaPoiID)
        if id and not seen[id] then
            seen[id] = true
            local journalID = Number(info.journalInstanceID)
            local kind = "instance"
            if F.journalClassification and journalID then
                local isRaid = Readable(select(RAID_INFO_INDEX, EJ_GetInstanceInfo(journalID)))
                if isRaid ~= nil then
                    kind = isRaid and "raid" or "dungeon"
                end
            end
            AddAreaPOI(add, id, mapID, info, kind, place, depth)
        end
        checkpoint()
    end
    for _, group in ipairs(AREA_GROUPS) do
        local ids = ReadList(group.enabled and group.query(mapID), checkpoint)
        checkpoint()
        for _, id in ipairs(ids) do
            id = Number(id)
            if id and not seen[id] then
                -- Claim category membership first; the generic list repeats categorized IDs.
                seen[id] = true
                local info = Readable(C_AreaPoiInfo.GetAreaPOIInfo(mapID, id))
                if type(info) == "table" then
                    local rank = depth + (Readable(info.isPrimaryMapForPOI) == true and PRIMARY_MAP_BONUS or 0)
                    AddAreaPOI(add, id, mapID, info, AreaKind(group.kind, Readable(info.atlasName)), place, rank)
                end
                checkpoint()
            end
        end
    end
    for _, info in ipairs(ReadList(F.links and C_Map.GetMapLinksForMap(mapID), checkpoint)) do
        info = Readable(info)
        local id = type(info) == "table" and Number(info.areaPoiID)
        if id and not seen[id] then
            seen[id] = true
            local atlas = Readable(info.atlasName)
            local isCave = type(atlas) == "string" and string.find(string.lower(atlas), CAVE_ATLAS_PATTERN, 1, true)
            AddAreaPOI(add, id, mapID, info, isCave and "cave" or AreaKind("mapLink", atlas), place, depth)
        end
        checkpoint()
    end
    for _, info in ipairs(ReadList(F.petTamers and C_PetInfo.GetPetTamersForMap(mapID), checkpoint)) do
        info = Readable(info)
        local id = type(info) == "table" and Number(info.areaPoiID)
        if id and not seen[id] then
            seen[id] = true
            local atlas = ReadAtlas(info.atlasName, PET_TAMER_ATLAS)
            add(
                Landmark(PIN_KEYS[AREA_POI], AREA_POI, id, mapID, info.position, info.name, atlas, "petTamer", place),
                depth
            )
        end
        checkpoint()
    end
end

local function CollectTaxiNodes(mapID, place, depth, add, checkpoint)
    if not F.taxi then
        return
    end
    local faction = Readable(UnitFactionGroup("player"))
    for _, node in ipairs(ReadList(C_TaxiMap.GetTaxiNodesForMap(mapID), checkpoint)) do
        node = Readable(node)
        local id = type(node) == "table" and Number(node.nodeID)
        local side = id and Number(node.faction)
        local friendly = side == Enum.FlightPathFaction.Neutral
            or (side == Enum.FlightPathFaction.Alliance and faction == "Alliance")
            or (side == Enum.FlightPathFaction.Horde and faction == "Horde")
        if id and friendly then
            local key = PIN_KEYS[TAXI_NODE]
            add(
                Landmark(key, TAXI_NODE, id, mapID, node.position, node.name, node.atlasName, "flightMaster", place),
                depth
            )
        end
        checkpoint()
    end
end

local function CollectDigSites(mapID, place, depth, add, checkpoint)
    if not F.digSites then
        return
    end
    for _, info in ipairs(ReadList(C_ResearchInfo.GetDigSitesForMap(mapID), checkpoint)) do
        info = Readable(info)
        local id = type(info) == "table" and Number(info.researchSiteID)
        if id then
            local key = PIN_KEYS[DIG_SITE]
            add(Landmark(key, DIG_SITE, id, mapID, info.position, info.name, DIG_SITE_ATLAS, "digSite", place), depth)
        end
        checkpoint()
    end
end

local function CollectTaskQuests(mapID, place, depth, add, checkpoint)
    if not F.tasks then
        return
    end
    for _, info in ipairs(ReadList(C_TaskQuest.GetQuestsOnMap(mapID), checkpoint)) do
        info = Readable(info)
        local questID = type(info) == "table" and Number(info.questID)
        if questID and Readable(info.isMapIndicatorQuest) ~= true then
            local title = Readable(C_TaskQuest.GetQuestInfoByQuestID(questID))
            local kind, atlas = "bonusObjective", BONUS_OBJECTIVE_ATLAS
            if Number(info.questTagType) == Enum.QuestTagType.WorldBoss then
                kind, atlas = "worldBoss", WORLD_BOSS_ATLAS
            elseif Readable(C_QuestLog.IsWorldQuest(questID)) == true then
                kind, atlas = "worldQuest", WORLD_QUEST_ATLAS
            end
            local rank = depth - (Number(info.childDepth) or 0)
            local position = { x = info.x, y = info.y }
            add(Landmark(QUEST_KEY, nil, questID, mapID, position, title, atlas, kind, place), rank)
        end
        checkpoint()
    end
end

local function CollectGraveyards(mapID, place, depth, add, checkpoint)
    if not F.graveyards then
        return
    end
    for _, info in ipairs(ReadList(C_DeathInfo.GetGraveyardsForMap(mapID), checkpoint)) do
        info = Readable(info)
        local id = type(info) == "table" and Number(info.graveyardID)
        if id then
            add(Landmark(GRAVEYARD_KEY, nil, id, mapID, info.position, info.name, nil, "graveyard", place), depth)
        end
        checkpoint()
    end
end

local function CollectInvasion(mapID, place, depth, add, checkpoint)
    if not F.invasions then
        return
    end
    local id = Number(C_InvasionInfo.GetInvasionForUiMapID(mapID))
    checkpoint()
    local info = id and Readable(C_InvasionInfo.GetInvasionInfo(id))
    if type(info) == "table" then
        add(Landmark(INVASION_KEY, nil, id, mapID, info.position, info.name, info.atlasName, "invasion", place), depth)
    end
end

local function CollectMapArea(details, place, add, seen)
    local mapID, parentID = details.mapID, details.parentMapID
    -- Phased copies of one map share a name and parent; the first copy represents it.
    local identity = details.name .. "\0" .. parentID
    if seen[identity] then
        return
    end
    local center = { x = MAP_CENTER, y = MAP_CENTER }
    if details.mapType == CONTINENT_MAP then
        seen[identity] = true
        local landmark = Landmark(MAP_KEY, nil, mapID, mapID, center, details.name, nil, "continent", place)
        add(landmark, MAP_DEPTH[CONTINENT_MAP])
        return
    elseif details.mapType == ZONE_MAP then
        if Readable(C_Map.CanSetUserWaypointOnMap(mapID)) == true then
            seen[identity] = true
            local kind = Readable(C_Map.IsCityMap(mapID)) == true and "city" or "zone"
            add(Landmark(MAP_KEY, nil, mapID, mapID, center, details.name, nil, kind, place), MAP_DEPTH[ZONE_MAP])
        end
        return
    elseif Readable(C_Map.CanSetUserWaypointOnMap(parentID)) ~= true then
        return
    end
    local left, right, top, bottom = C_Map.GetMapRectOnMap(mapID, parentID)
    left, right, top, bottom = Number(left), Number(right), Number(top), Number(bottom)
    if left and right and top and bottom then
        seen[identity] = true
        center.x, center.y = (left + right) / 2, (top + bottom) / 2
        add(Landmark(MAP_KEY, nil, mapID, parentID, center, details.name, nil, "area", place), MAP_DEPTH[MICRO_MAP])
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

local function RemoveDuplicates(target, maps, checkpoint)
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
    for _, group in pairs(groups) do
        for _, candidate in ipairs(group) do
            for _, other in ipairs(group) do
                if other ~= candidate and Supersedes(other, candidate, target, maps, cache) then
                    removed[candidate.key] = true
                    break
                end
            end
            checkpoint()
        end
    end
    local entries, positions, ranks = {}, {}, {}
    for _, landmark in ipairs(target.entries) do
        if not removed[landmark.key] then
            entries[#entries + 1] = landmark
            positions[landmark.key], ranks[landmark.key] = #entries, target.ranks[landmark.key]
        end
    end
    target.entries, target.positions, target.ranks = entries, positions, ranks
end

local function BuildCatalog(catalog, target)
    local incomplete = false
    local function Checkpoint(pending)
        incomplete = incomplete or pending == true
        if debugprofilestop() >= catalog.deadline then
            coroutine.yield()
        end
    end
    local function Add(landmark, rank)
        if not landmark then
            return
        end
        local position = target.positions[landmark.key]
        if not position then
            target.entries[#target.entries + 1] = landmark
            target.positions[landmark.key], target.ranks[landmark.key] = #target.entries, rank
        elseif rank > target.ranks[landmark.key] then
            target.entries[position], target.ranks[landmark.key] = landmark, rank
        else
            return
        end
        if target == catalog then
            catalog.revision = catalog.revision + 1
        end
    end
    local maps, order = {}, {}
    local children = Readable(C_Map.GetMapChildrenInfo(catalog.rootID, nil, true))
    if type(children) ~= "table" then
        return false
    end
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
    end
    local function Lookup(mapID)
        return maps[mapID]
    end
    Checkpoint()
    local areas = {}
    for _, mapID in ipairs(order) do
        local details = maps[mapID]
        local depth = MAP_DEPTH[details.mapType]
        if depth and details.parentMapID then
            local continent = ContinentName(mapID, Lookup)
            local parent = maps[details.parentMapID]
            CollectMapArea(details, { zone = parent and parent.name, continent = continent }, Add, areas)
            local place = { zone = details.name, continent = continent }
            CollectAreaPOIs(mapID, place, depth, Add, Checkpoint, {})
            CollectTaxiNodes(mapID, place, depth, Add, Checkpoint)
            CollectDigSites(mapID, place, depth, Add, Checkpoint)
            CollectTaskQuests(mapID, place, depth, Add, Checkpoint)
            CollectGraveyards(mapID, place, depth, Add, Checkpoint)
            CollectInvasion(mapID, place, depth, Add, Checkpoint)
        end
        Checkpoint()
    end
    RemoveDuplicates(target, maps, Checkpoint)
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
    for _, listener in pairs(catalog.listeners) do
        listener()
    end
end

function Plugin:RefreshCompassLandmarkDriver()
    local catalog = self.compassLandmarks
    local active = (catalog.state == "building" or catalog.state == "pending") and next(catalog.demand) ~= nil
    self.compassLandmarkDriver:SetScript("OnUpdate", active and self.compassLandmarkDriverUpdate or nil)
end

-- Search consumers outside the ribbon (Orbit sessions, the inline field) must advance the index while the
-- ribbon is hidden or the player is inside an instance, where UpdateCompass returns before stepping.
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

function Plugin:SetCompassLandmarkListener(owner, listener)
    self.compassLandmarks.listeners[owner] = listener
end

function Plugin:StepCompassLandmarkDemand(elapsed)
    local catalog = self.compassLandmarks
    self:StepCompassLandmarkCatalog()
    catalog.listenerClock = catalog.listenerClock + elapsed
    if catalog.listenerClock >= LISTENER_INTERVAL and catalog.revision ~= catalog.notifiedRevision then
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
        catalog.rootID, catalog.state, catalog.thread, catalog.target = root, "idle", nil, nil
        catalog.entries, catalog.positions, catalog.ranks = {}, {}, {}
        catalog.revision = catalog.revision + 1
        self.compassPinDestination = nil
        NotifyListeners(catalog)
    end
    if not self:IsActive() or self:IsProfileSuppressed() then
        return
    end
    local stale = catalog.state == "complete" and now - catalog.builtAt >= REFRESH_AGE_SECONDS
    if catalog.state == "idle" or catalog.state == "pending" or catalog.state == "failed" or stale then
        catalog.target = #catalog.entries == 0 and catalog or { entries = {}, positions = {}, ranks = {} }
        catalog.state = "building"
        catalog.thread = coroutine.create(BuildCatalog)
    end
end

function Plugin:InvalidateCompassLandmarkScope()
    local catalog = self.compassLandmarks
    catalog.rootRetryAt = nil
    if catalog.rootID or next(catalog.demand) then
        self:RequestCompassLandmarkCatalog()
    end
    self:RefreshCompassLandmarkDriver()
end

function Plugin:StopCompassLandmarks()
    local catalog = self.compassLandmarks
    catalog.state, catalog.thread, catalog.target = "idle", nil, nil
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
    if catalog.state ~= "building" or catalog.steppedAt == now then
        return
    end
    catalog.steppedAt = now
    local profiler = Addon.Services.profiler
    local start, startKB
    if profiler then
        start, startKB = profiler:Begin()
    end
    local budget = IsDemandFocused(catalog) and FOCUSED_BUILD_BUDGET_MS or BUILD_BUDGET_MS
    catalog.deadline = debugprofilestop() + budget
    local thread = catalog.thread
    local ok, err = coroutine.resume(thread, catalog, catalog.target)
    if start then
        profiler:End(self, "Compass.Landmarks", start, startKB)
    end
    if not ok then
        catalog.state, catalog.thread, catalog.target = "failed", nil, nil
        catalog.rootRetryAt = now + DATA_RETRY_SECONDS
        error(err, 0)
    end
    if catalog.thread ~= thread then
        return
    end
    if coroutine.status(thread) == "dead" then
        if err == false or err == "incomplete" then
            catalog.state, catalog.thread, catalog.target = "pending", nil, nil
            catalog.rootRetryAt = now + (err == false and ROOT_RETRY_SECONDS or DATA_RETRY_SECONDS)
            NotifyListeners(catalog)
            return
        end
        local target = catalog.target
        catalog.entries, catalog.positions, catalog.ranks = target.entries, target.positions, target.ranks
        catalog.state, catalog.thread, catalog.target = "complete", nil, nil
        catalog.builtAt, catalog.revision = GetTime(), catalog.revision + 1
        NotifyListeners(catalog)
        -- Pins tracked before the index existed can now resolve their destination and route artwork.
        self.compassSources.route.dirty = true
        self.discoveryPending, self.waypointDirty = true, true
    end
end

function Plugin:IsCompassLandmarkCatalogBuilding()
    return self.compassLandmarks.state == "building" or self.compassLandmarks.state == "pending"
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
            found = landmark
        end
    end
    if pinType == AREA_POI then
        CollectAreaPOIs(mapID, place, 0, Add, NoCheckpoint, {})
    elseif pinType == TAXI_NODE then
        CollectTaxiNodes(mapID, place, 0, Add, NoCheckpoint)
    elseif pinType == DIG_SITE then
        CollectDigSites(mapID, place, 0, Add, NoCheckpoint)
    end
    return found
end

function Plugin:GetCompassLandmarks()
    local catalog = self.compassLandmarks
    return catalog.entries, catalog.revision
end
