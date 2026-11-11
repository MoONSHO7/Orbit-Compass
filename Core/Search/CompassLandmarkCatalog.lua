local _, Addon = ...
local C = Addon.Constants
local Plugin = Addon.Controller
local Build = Addon.LandmarkBuild
local F = Addon.ClientFeatures
local PIN_KEYS = Addon.LandmarkRecord.PinKeys

local ROOT_RETRY_SECONDS = 1
local DATA_RETRY_SECONDS = 30
local BUILD_BUDGET_MS = 1
local FOCUSED_BUILD_BUDGET_MS = 4
local REFRESH_AGE_SECONDS = 300
local LISTENER_INTERVAL = 0.25
local PIN_DEMAND = "pin"

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
        catalog.thread = coroutine.create(Build.Run)
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
    local ok, err = coroutine.resume(thread, catalog, catalog.target, SetPhase)
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

function Plugin:GetCompassLandmarks()
    local catalog = self.compassLandmarks
    return catalog.entries, catalog.revision
end
