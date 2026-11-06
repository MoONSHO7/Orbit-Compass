local _, Addon = ...
local Plugin = Addon.Controller
local C = Addon.Constants
local DISPLAY_RETRY_INTERVAL = 30
local NO_MARKERS = table.freeze({})
-- Display-only sources poll synchronously on wall-clock deadlines, outside the cooperative job queue.
local DISPLAY_SOURCES = {
    {
        key = "resources",
        refresh = "RefreshCompassResources",
        label = "Compass.Discovery.Resources",
        interval = C.DISCOVERY_MIN_INTERVAL,
    },
}

function Plugin:ResetCompassDisplayMarkers()
    -- Each context gets fresh display states, so providers keep their caches there and never reset them.
    self.compassDisplaySources = {}
    for _, definition in ipairs(DISPLAY_SOURCES) do
        if Addon.ClientFeatures.sources[definition.key] then
            self.compassDisplaySources[definition.key] = { markers = NO_MARKERS, nextPoll = 0 }
        end
    end
    self.displayMarkers = NO_MARKERS
end

local function PublishDisplayMarkers(plugin)
    local markers = {}
    for _, definition in ipairs(DISPLAY_SOURCES) do
        local state = plugin.compassDisplaySources[definition.key]
        if state then
            for _, marker in ipairs(state.markers) do
                marker.source, marker.displayOnly = definition.key, true
                markers[#markers + 1] = marker
            end
        end
    end
    plugin.displayMarkers, plugin.bearingsDirty = markers, true
end

function Plugin:RefreshCompassDisplayMarkers()
    local now, changed = GetTime(), false
    local profiler = Addon.Services.profiler
    profiler = profiler and profiler.active and profiler
    for _, definition in ipairs(DISPLAY_SOURCES) do
        local state = self.compassDisplaySources[definition.key]
        if state and now >= state.nextPoll then
            local published = state.markers
            local start, startKB
            if profiler then
                start, startKB = profiler:Begin()
            end
            -- A failing provider publishes nothing and re-raises at once; its next poll waits for the retry interval.
            local ok, delay = pcall(self[definition.refresh], self, state)
            if start then
                profiler:End(self, definition.label, start, startKB)
            end
            if not ok then
                self.compassDisplaySources[definition.key] =
                    { markers = NO_MARKERS, nextPoll = now + DISPLAY_RETRY_INTERVAL }
                PublishDisplayMarkers(self)
                if profiler then
                    profiler:Count(self, "Discovery/Failed/" .. definition.key)
                end
                error(delay, 0)
            end
            state.nextPoll = now + (delay or definition.interval)
            if state.markers ~= published then
                changed = true
                if profiler then
                    profiler:Count(self, "Discovery/DisplayChanged/" .. definition.key)
                end
            end
        end
    end
    if changed then
        PublishDisplayMarkers(self)
    end
end
