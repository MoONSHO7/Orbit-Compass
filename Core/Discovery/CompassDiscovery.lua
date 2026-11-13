local _, Addon = ...
local Plugin = Addon.Controller
local C = Addon.Constants
local Number = Addon.SourceUtils.Number
local SOURCE_RETRY_INTERVAL = 30
local QUEST_DATA_DIRTY = "questData"
local Catalog = Addon.CompassDiscoveryCatalog
local SOURCES = Catalog.sources
local EVENT_SOURCES = Catalog.eventSources
local PATH_SOURCES = Catalog.pathSources
local CONTEXT_EVENTS = Catalog.contextEvents
local SUBZONE_RETAINED_LABELS = {
    taxi = "Discovery/SubzoneTaxiRetained",
    handynotes = "Discovery/SubzoneHandyNotesRetained",
    questie = "Discovery/SubzoneQuestieRetained",
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

local function SameLines(old, new)
    if old == new then
        return true
    end
    if not old or not new or #old ~= #new then
        return false
    end
    for index, line in ipairs(new) do
        local before = old[index]
        if before.text ~= line.text or before.r ~= line.r or before.g ~= line.g or before.b ~= line.b then
            return false
        end
    end
    return true
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
            or not SameLines(old.tooltipLines, marker.tooltipLines)
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

local function RetainPendingSnapshot(job)
    local seen = {}
    for _, marker in ipairs(job.markers) do
        seen[marker.key] = true
    end
    for _, marker in ipairs(job.source.markers) do
        if not seen[marker.key] then
            job.markers[#job.markers + 1] = marker
        end
    end
end

function Plugin:CompassDiscoveryCheckpoint()
    self.discoverySteps = self.discoverySteps + 1
    if self.discoverySteps >= C.DISCOVERY_STEPS or debugprofilestop() >= self.discoveryDeadline then
        coroutine.yield()
    end
end

function Plugin:InitializeCompassDiscovery()
    self:ResetCompassAutoAdvance()
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
    self:ResetCompassDisplayMarkers()
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
    if key == "questie" then
        self:InvalidateCompassMapPoints()
    end
    local profiler = Addon.Services.profiler
    if profiler and profiler.active then
        profiler:Count(self, "Discovery/Settings/" .. key)
    end
end

local function ScheduleInvalidatedSource(plugin, key)
    if not plugin.mapWidth then
        return
    end
    local source = plugin.compassSources[key]
    if source.enabled then
        plugin.discoveryNext = math.min(plugin.discoveryNext, source.nextAllowed, source.nextRefresh)
    elseif source.reason == "provider" then
        plugin.discoveryPending = true
    end
end

function Plugin:InvalidateCompassSource(event)
    local profiler = Addon.Services.profiler
    if profiler and profiler.active and (EVENT_SOURCES[event] or CONTEXT_EVENTS[event]) then
        profiler:Count(self, "Discovery/Invalidate/" .. event)
    end
    if event == "USER_WAYPOINT_UPDATED" then
        self.compassSources.route.dirty = true
        self.discoveryPending, self.waypointDirty = true, true
    elseif event == "PLAYER_ENTERING_WORLD" or event == "UNIT_PHASE" then
        self.discoveryDirty = true
    elseif event:find("^ZONE_CHANGED") then
        local mapID = Number(C_Map.GetBestMapForUnit("player"))
        if mapID and mapID == self.mapID and self.mapWidth then
            self:RefreshCompassPointArea(mapID)
            local taxi, job = self.compassSources.taxi, self.discoveryJob
            local retainTaxi = taxi.status == "ready"
                and not taxi.dirty
                and not taxi.pathDirty
                and not (job and job.source == taxi)
            local questie = self.compassSources.questie
            local retainQuestie = questie.status == "ready"
                and not questie.dirty
                and not (job and job.source == questie)
            local notes = self.compassSources.handynotes
            local retainNotes = event == "ZONE_CHANGED"
                and notes.status == "ready"
                and notes.nextRefresh == math.huge
                and not notes.dirty
                and not notes.pathDirty
                and not (job and job.source == notes)
            if retainTaxi or retainNotes then
                local mapArtID = Number(C_Map.GetMapArtID(mapID))
                retainTaxi = retainTaxi and mapArtID ~= nil and mapArtID == taxi.mapArtID
                retainNotes = retainNotes and mapArtID ~= nil and mapArtID == notes.mapArtID
            end
            CancelDiscoveryJob(self, "Subzone")
            for key, source in pairs(self.compassSources) do
                -- QuestieDB markers depend on the map and character only, so a same-map subzone keeps them.
                local retained = key == "taxi" and retainTaxi
                    or key == "handynotes" and retainNotes
                    or key == "questie" and retainQuestie
                if not retained then
                    source.dirty, source.pathDirty, source.nextAllowed = true, false, self.discoveryClock
                    source.handynotesProviders = nil
                elseif profiler and profiler.active then
                    profiler:Count(self, SUBZONE_RETAINED_LABELS[key])
                end
            end
            self.discoveryPending, self.waypointDirty = true, true
        else
            self.discoveryDirty = true
        end
    elseif event == "SUPER_TRACKING_PATH_UPDATED" then
        -- Path updates repeat many times a second while moving, so each source refreshes only what a path can change.
        for _, key in ipairs(PATH_SOURCES) do
            self.compassSources[key].pathDirty = true
            ScheduleInvalidatedSource(self, key)
        end
    else
        local sources = EVENT_SOURCES[event]
        if type(sources) == "table" then
            for _, key in ipairs(sources) do
                local source = self.compassSources[key]
                if key ~= "quests" or event ~= "QUEST_DATA_LOAD_RESULT" then
                    source.dirty = true
                elseif not source.dirty then
                    source.dirty = QUEST_DATA_DIRTY
                end
                if key == "questie" then
                    self:InvalidateCompassMapPoints()
                end
                ScheduleInvalidatedSource(self, key)
            end
        else
            self.compassSources[sources].dirty = true
            if sources == "questie" then
                self:InvalidateCompassMapPoints()
            end
            ScheduleInvalidatedSource(self, sources)
        end
        if event == "SUPER_TRACKING_CHANGED" then
            self.waypointDirty = true
        end
    end
end

local function ReconcileSource(plugin, definition)
    local source = plugin.compassSources[definition.key]
    local enabled = definition.fields == nil
    if definition.fields then
        for _, field in ipairs(definition.fields) do
            enabled = enabled or not not plugin[field]
        end
    end
    local status, reason
    if not Addon.ClientFeatures.sources[definition.key] then
        status, reason = "unsupported", "client-contract"
    elseif not enabled then
        status, reason = "disabled", "preference"
    elseif definition.provider and not C_AddOns.IsAddOnLoaded(definition.provider) then
        status, reason = "pending", "provider"
    end
    if status then
        if #source.markers > 0 then
            wipe(source.markers)
            plugin.waypointDirty = true
        end
        source.status, source.reason, source.enabled = status, reason, false
        source.dirty, source.pathDirty = false, false
        source.nextRefresh = reason == "provider" and plugin.discoveryClock + SOURCE_RETRY_INTERVAL or math.huge
        return false
    end
    if not source.enabled then
        source.status, source.reason = "pending", "observation"
        source.dirty, source.nextAllowed, source.nextRefresh = true, 0, 0
    end
    source.enabled = true
    return true
end

function Plugin:MarkCompassSourcePending()
    self.discoveryJob.pending = true
end

-- A collector records the inputs a path update can change; the source keeps them only when its job completes.
function Plugin:SetCompassPathReceipt(receipt)
    self.discoveryJob.pathReceipt = receipt
end

function Plugin:RegisterCompassDiscoveryEvents()
    local excluded = {
        WORLD_QUEST_COMPLETED_BY_SPELL = not Addon.ClientFeatures.worldQuests,
    }
    for event, keys in pairs(EVENT_SOURCES) do
        if event:sub(1, 6) ~= "ORBIT_" and not excluded[event] then
            local supported = false
            for _, key in ipairs(type(keys) == "table" and keys or { keys }) do
                supported = supported or Addon.ClientFeatures.sources[key]
            end
            if supported and C_EventUtils.IsEventValid(event) then
                self.events:RegisterEvent(event)
            end
        end
    end
end

local function FailSource(plugin, source, key, pathOnly, message)
    source.status, source.reason, source.pathReceipt = "failed", "collector", nil
    local profiler = Addon.Services.profiler
    if profiler and profiler.active then
        profiler:Count(plugin, "Discovery/Failed/" .. key)
    end
    if not pathOnly then
        source.nextRefresh = plugin.discoveryClock + SOURCE_RETRY_INTERVAL
    end
    error(message, 0)
end

-- A path-only wake settles without a job when the completed collection's receipt still matches native state.
local function SettlePath(plugin, source, definition)
    local receipt = source.pathReceipt
    if
        not (definition.checkPath and receipt and source.pathDirty and not source.dirty)
        or plugin.discoveryClock >= source.nextRefresh
        or not plugin[definition.checkPath](plugin, receipt)
    then
        return false
    end
    source.pathDirty, source.nextAllowed = false, plugin.discoveryClock + C.DISCOVERY_MIN_INTERVAL
    plugin.discoverySteps = plugin.discoverySteps + 1
    local profiler = Addon.Services.profiler
    if profiler and profiler.active then
        profiler:Count(plugin, "Discovery/PathUnchanged/" .. definition.key)
    end
    return true
end

local function NextSource(plugin)
    local nextRefresh = math.huge
    for _, definition in ipairs(SOURCES) do
        local source = plugin.compassSources[definition.key]
        if ReconcileSource(plugin, definition) then
            local due = (source.dirty or source.pathDirty) and math.min(source.nextAllowed, source.nextRefresh)
                or source.nextRefresh
            if plugin.discoveryClock >= due then
                if not SettlePath(plugin, source, definition) then
                    return source, definition
                end
                due = source.nextRefresh
            end
            nextRefresh = math.min(nextRefresh, due)
        elseif source.reason == "provider" then
            nextRefresh = math.min(nextRefresh, source.nextRefresh)
        end
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
            local questDataOnly = not pathOnly
                and source.dirty == QUEST_DATA_DIRTY
                and self.discoveryClock < source.nextRefresh
            source.dirty, source.pathDirty = false, false
            source.nextAllowed = self.discoveryClock + C.DISCOVERY_MIN_INTERVAL
            source.mapArtID = nil
            local markers = {}
            job = {
                source = source,
                definition = definition,
                pathOnly = pathOnly,
                questDataOnly = questDataOnly,
                countKey = pathOnly and "questPath" or definition.key,
                mapArtID = definition.trackMapArt and Number(C_Map.GetMapArtID(self.mapID)) or nil,
                markers = markers,
                thread = coroutine.create(function()
                    local refreshInterval = self[collect](self, markers)
                    job.nextRefresh = refreshInterval and self.discoveryClock + refreshInterval
                    for _, marker in ipairs(markers) do
                        marker.source = definition.key
                    end
                    if job.pending then
                        RetainPendingSnapshot(job)
                    end
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
            FailSource(self, job.source, job.countKey, job.pathOnly, result)
        end
        if coroutine.status(job.thread) ~= "dead" then
            break
        end
        if profiler and profiler.active then
            profiler:Count(self, "Discovery/Completed/" .. job.countKey)
            profiler:Count(self, "Discovery/" .. (result and "Changed/" or "Unchanged/") .. job.countKey)
        end
        job.source.status, job.source.reason = job.pending and "pending" or "ready", job.pending and "data" or nil
        if result then
            job.source.markers = job.markers
            changed = true
        end
        if job.pending then
            job.nextRefresh = self.discoveryClock + SOURCE_RETRY_INTERVAL
        end
        job.source.nextAllowed = self.discoveryClock + C.DISCOVERY_MIN_INTERVAL
        job.source.mapArtID = job.mapArtID
        if not job.pathOnly then
            job.source.pathReceipt = job.pathReceipt
        end
        if not job.pathOnly and not job.questDataOnly then
            job.source.nextRefresh = job.nextRefresh or self.discoveryClock + job.definition.interval
        end
        self.discoveryJob = nil
    until self.discoverySteps >= C.DISCOVERY_STEPS or debugprofilestop() >= self.discoveryDeadline
    if changed or self.waypointDirty then
        self.waypointDirty = false
        self:RebuildCompassMarkers()
    end
end
