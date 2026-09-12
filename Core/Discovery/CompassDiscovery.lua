local _, Addon = ...
local Plugin = Addon.Controller
local C = Addon.Constants
local Number = Addon.SourceUtils.Number
local SOURCES = {
    {
        key = "quests",
        collect = "CollectCompassQuests",
        label = "Compass.Discovery.Quests",
        interval = 30,
        refreshPath = "RefreshCompassQuestPath",
        pathLabel = "Compass.Discovery.QuestPath",
    },
    { key = "vignettes", collect = "CollectCompassVignettes", label = "Compass.Discovery.Vignettes", interval = 2 },
    { key = "map", collect = "CollectCompassMapPoints", label = "Compass.Discovery.Map", interval = math.huge },
    { key = "taxi", collect = "CollectCompassFlightMasters", label = "Compass.Discovery.Taxi", interval = 60 },
    { key = "directions", collect = "CollectCompassDirections", label = "Compass.Discovery.Directions", interval = 30 },
    { key = "links", collect = "CollectCompassMapLinks", label = "Compass.Discovery.Links", interval = 60 },
    { key = "tamers", collect = "CollectCompassPetTamers", label = "Compass.Discovery.Tamers", interval = 60 },
    { key = "digsites", collect = "CollectCompassDigSites", label = "Compass.Discovery.DigSites", interval = 30 },
    { key = "content", collect = "CollectCompassTrackedContent", label = "Compass.Discovery.Content", interval = 30 },
    { key = "offers", collect = "CollectCompassQuestOffers", label = "Compass.Discovery.Offers", interval = 30 },
    { key = "locations", collect = "CollectCompassLocations", label = "Compass.Discovery.Locations", interval = 60 },
    { key = "corpse", collect = "CollectCompassCorpse", label = "Compass.Discovery.Corpse", interval = 2 },
    {
        key = "handynotes",
        collect = "CollectCompassHandyNotes",
        label = "Compass.Discovery.HandyNotes",
        interval = math.huge,
    },
}
local EVENT_SOURCES = {
    AREA_POIS_UPDATED = "map",
    VIGNETTES_UPDATED = "vignettes",
    VIGNETTE_MINIMAP_UPDATED = "vignettes",
    QUEST_LOG_UPDATE = { "quests", "offers" },
    QUEST_WATCH_LIST_CHANGED = "quests",
    QUEST_POI_UPDATE = { "quests", "offers" },
    QUEST_DATA_LOAD_RESULT = { "quests", "offers" },
    SUPER_TRACKING_CHANGED = { "quests", "content" },
    SUPER_TRACKING_PATH_UPDATED = "content",
    WORLD_QUEST_COMPLETED_BY_SPELL = "quests",
    TAXI_NODE_STATUS_CHANGED = "taxi",
    DYNAMIC_GOSSIP_POI_UPDATED = "directions",
    SPELLS_CHANGED = "tamers",
    RESEARCH_ARTIFACT_DIG_SITE_UPDATED = "digsites",
    ARTIFACT_DIGSITE_COMPLETE = "digsites",
    CONTENT_TRACKING_UPDATE = "content",
    CONTENT_TRACKING_LIST_UPDATE = "content",
    CONTENT_TRACKING_IS_ENABLED_UPDATE = "content",
    TRACKABLE_INFO_UPDATE = "content",
    TRACKING_TARGET_INFO_UPDATE = "content",
    QUESTLINE_UPDATE = { "offers", "map" },
    MINIMAP_UPDATE_TRACKING = { "offers", "map" },
    QUEST_ACCEPTED = { "quests", "offers" },
    QUEST_TURNED_IN = { "quests", "offers" },
    PLAYER_DEAD = "corpse",
    PLAYER_ALIVE = "corpse",
    PLAYER_UNGHOST = "corpse",
    CORPSE_IN_RANGE = "corpse",
    CORPSE_OUT_OF_RANGE = "corpse",
    ORBIT_COMPASS_LOCATIONS = "locations",
    ORBIT_COMPASS_HANDYNOTES = "handynotes",
}
local CONTEXT_EVENTS = {
    USER_WAYPOINT_UPDATED = true,
    PLAYER_ENTERING_WORLD = true,
    UNIT_PHASE = true,
    ZONE_CHANGED = true,
    ZONE_CHANGED_INDOORS = true,
    ZONE_CHANGED_NEW_AREA = true,
}

local function CancelDiscoveryJob(plugin, reason)
    local job = plugin.discoveryJob
    if not job then
        return
    end
    plugin.discoveryJob = nil
    local profiler = Addon.Services.profiler
    if profiler and profiler.active then
        profiler:Count(plugin, "Discovery/Cancelled/" .. job.countKey)
        profiler:Count(plugin, "Discovery/CancelReason/" .. reason)
    end
end

local function SourceChanged(plugin, previous, markers)
    if #previous ~= #markers then
        return true
    end
    for index, marker in ipairs(markers) do
        local old = previous[index]
        if
            old.key ~= marker.key
            or old.x ~= marker.x
            or old.y ~= marker.y
            or old.name ~= marker.name
            or old.description ~= marker.description
            or old.handynotesNode ~= marker.handynotesNode
            or not Addon.HandyNotesClick:Matches(old.handynotesPoint, marker.handynotesPoint)
            or old.atlas ~= marker.atlas
            or old.priority ~= marker.priority
            or old.kind ~= marker.kind
            or old.destination.mapID ~= marker.destination.mapID
            or old.destination.x ~= marker.destination.x
            or old.destination.y ~= marker.destination.y
        then
            return true
        end
        for _, field in ipairs(C.MARKER_ART_FIELDS) do
            if old[field] ~= marker[field] then
                return true
            end
        end
        plugin:CompassDiscoveryCheckpoint()
    end
    return false
end

function Plugin:CompassDiscoveryCheckpoint()
    self.discoverySteps = self.discoverySteps + 1
    if self.discoverySteps >= C.DISCOVERY_STEPS or debugprofilestop() >= self.discoveryDeadline then
        coroutine.yield()
    end
end

function Plugin:InitializeCompassDiscovery()
    CancelDiscoveryJob(self, "ContextReset")
    self.compassHandyNotesGuide = nil
    self.compassOfferMapID = nil
    self.discoveryClock, self.discoveryNext = 0, 0
    self.bearingSampleX = nil
    self.selectionKeys = {}
    self.compassSources = {}
    for _, definition in ipairs(SOURCES) do
        self.compassSources[definition.key] = { markers = {}, dirty = true, nextAllowed = 0, nextRefresh = 0 }
    end
end

function Plugin:InvalidateCompassSourceSettings(key, retainProviders)
    if key == "handynotes" then
        self.compassHandyNotesGuide = nil
    end
    local source = self.compassSources[key]
    if self.discoveryJob and self.discoveryJob.source == source then
        CancelDiscoveryJob(self, "Settings")
    end
    source.mapArtID = nil
    wipe(source.markers)
    if not retainProviders then
        source.handynotesProviders = nil
    end
    source.dirty, source.pathDirty, source.nextAllowed = true, false, self.discoveryClock
    self.discoveryPending, self.waypointDirty = true, true
    local profiler = Addon.Services.profiler
    if profiler and profiler.active then
        profiler:Count(self, "Discovery/Settings/" .. key)
    end
end

function Plugin:InvalidateCompassSource(event)
    local profiler = Addon.Services.profiler
    if profiler and profiler.active and (EVENT_SOURCES[event] or CONTEXT_EVENTS[event]) then
        profiler:Count(self, "Discovery/Invalidate/" .. event)
    end
    if event == "USER_WAYPOINT_UPDATED" then
        self.waypointDirty = true
    elseif event == "PLAYER_ENTERING_WORLD" or event == "UNIT_PHASE" then
        self.discoveryDirty = true
    elseif event:find("^ZONE_CHANGED") then
        local mapID = Number(C_Map.GetBestMapForUnit("player"))
        if mapID and mapID == self.mapID and self.mapWidth then
            self:RefreshCompassPointArea(mapID)
            local taxi, job = self.compassSources.taxi, self.discoveryJob
            local retainTaxi = not taxi.dirty and not taxi.pathDirty and not (job and job.source == taxi)
            if retainTaxi then
                local mapArtID = Number(C_Map.GetMapArtID(mapID))
                retainTaxi = mapArtID ~= nil and mapArtID == taxi.mapArtID
            end
            CancelDiscoveryJob(self, "Subzone")
            for key, source in pairs(self.compassSources) do
                -- Native taxi data is map-scoped, but a different phased map artwork still invalidates it.
                if key ~= "taxi" or not retainTaxi then
                    source.dirty, source.pathDirty, source.nextAllowed = true, false, self.discoveryClock
                    source.handynotesProviders = nil
                elseif profiler and profiler.active then
                    profiler:Count(self, "Discovery/SubzoneTaxiRetained")
                end
            end
            self.discoveryPending, self.waypointDirty = true, true
        else
            self.discoveryDirty = true
        end
    else
        local sources = EVENT_SOURCES[event]
        if type(sources) == "table" then
            for _, key in ipairs(sources) do
                self.compassSources[key].dirty = true
            end
        else
            self.compassSources[sources].dirty = true
        end
        self.discoveryPending = true
        if event == "SUPER_TRACKING_PATH_UPDATED" then
            self.compassSources.quests.pathDirty = true
        elseif event == "SUPER_TRACKING_CHANGED" then
            self.waypointDirty = true
        end
    end
end

local function NextSource(plugin)
    local nextRefresh = math.huge
    for _, definition in ipairs(SOURCES) do
        local source = plugin.compassSources[definition.key]
        local due = (source.dirty or source.pathDirty) and math.min(source.nextAllowed, source.nextRefresh)
            or source.nextRefresh
        if plugin.discoveryClock >= due then
            return source, definition
        end
        nextRefresh = math.min(nextRefresh, due)
    end
    plugin.discoveryNext, plugin.discoveryPending = nextRefresh, false
end

function Plugin:DiscoverCompassMarkers()
    if self.discoveryDirty or not self.mapWidth then
        self:InitializeCompassDiscovery()
        self.discoveryDirty, self.waypointDirty = false, true
        self:RefreshCompassMap()
    end
    if self.compassPointAreaRetry and self.discoveryClock >= self.compassPointAreaRetry then
        self:RefreshCompassPointArea()
    end
    if self.waypointDirty then
        self:RebuildCompassMarkers()
        self.waypointDirty = false
    end
    if not self.mapWidth then
        self.discoveryNext, self.discoveryPending = self.discoveryClock + C.DISCOVERY_INTERVAL, false
        return
    end
    self.discoveryDeadline = debugprofilestop() + C.DISCOVERY_BUDGET_MS
    self.discoverySteps = 0
    local changed = false
    repeat
        local job = self.discoveryJob
        if not job then
            local source, definition = NextSource(self)
            if not source then
                break
            end
            local pathOnly = definition.refreshPath
                and source.pathDirty
                and not source.dirty
                and self.discoveryClock < source.nextRefresh
            local collect = pathOnly and definition.refreshPath or definition.collect
            source.dirty, source.pathDirty = false, false
            source.nextAllowed = self.discoveryClock + C.DISCOVERY_MIN_INTERVAL
            source.mapArtID = nil
            local markers = {}
            job = {
                source = source,
                definition = definition,
                pathOnly = pathOnly,
                countKey = pathOnly and "questPath" or definition.key,
                mapArtID = definition.key == "taxi" and Number(C_Map.GetMapArtID(self.mapID)) or nil,
                markers = markers,
                thread = coroutine.create(function()
                    local refreshInterval = self[collect](self, markers)
                    job.nextRefresh = refreshInterval and self.discoveryClock + refreshInterval
                    return SourceChanged(self, source.markers, markers)
                end),
            }
            self.discoveryJob = job
            local profiler = Addon.Services.profiler
            if profiler and profiler.active then
                profiler:Count(self, "Discovery/Started/" .. job.countKey)
            end
        end
        local profiler = Addon.Services.profiler
        local start, startKB
        if profiler and profiler.active then
            start, startKB = profiler:Begin()
        end
        local ok, result = coroutine.resume(job.thread)
        if start then
            profiler:End(self, job.pathOnly and job.definition.pathLabel or job.definition.label, start, startKB)
        end
        if self.discoveryJob ~= job then
            if not ok then
                error(result, 0)
            end
            break
        end
        if not ok then
            self.discoveryJob = nil
            if profiler and profiler.active then
                profiler:Count(self, "Discovery/Failed/" .. job.countKey)
            end
            if not job.pathOnly then
                job.source.nextRefresh = self.discoveryClock + job.definition.interval
            end
            error(result, 0)
        end
        if coroutine.status(job.thread) ~= "dead" then
            break
        end
        if profiler and profiler.active then
            profiler:Count(self, "Discovery/Completed/" .. job.countKey)
            profiler:Count(self, "Discovery/" .. (result and "Changed/" or "Unchanged/") .. job.countKey)
        end
        if result then
            job.source.markers = job.markers
            changed = true
        end
        job.source.nextAllowed = self.discoveryClock + C.DISCOVERY_MIN_INTERVAL
        job.source.mapArtID = job.mapArtID
        if not job.pathOnly then
            job.source.nextRefresh = job.nextRefresh or self.discoveryClock + job.definition.interval
        end
        self.discoveryJob = nil
    until self.discoverySteps >= C.DISCOVERY_STEPS or debugprofilestop() >= self.discoveryDeadline
    if changed then
        self:RebuildCompassMarkers()
    end
end
