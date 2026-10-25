local _, Addon = ...
local Plugin = Addon.Controller
local C = Addon.Constants
local Utils = Addon.SourceUtils
local Readable, Number, AddMarker = Utils.Readable, Utils.Number, Utils.AddMarker
local CAPABILITY_VERSION = 1
local MAX_OBSERVATIONS = 64
local ICON_SCALE = 0.6
local KIND = "resource"
local KEY_PREFIX = "resource:"
local UNSUPPORTED_RETRY = math.huge
local PENDING_PROJECTION = false
local NO_ENTRIES = table.freeze({})
local NO_MARKERS = table.freeze({})

local function Capability()
    local host = Addon.OrbitHost
    if host and host.ExternalUIHost.mapResourceObservationsVersion == CAPABILITY_VERSION then
        return host.MapDots
    end
end

local function SameMarkers(previous, markers)
    if #previous ~= #markers then
        return false
    end
    for index, marker in ipairs(markers) do
        if previous[index] ~= marker then
            return false
        end
    end
    return true
end

local function Project(plugin, markers, id, instance, north, west, icon, name)
    local x, y = plugin:ProjectCompassWorldPoint(instance, north, west)
    if not x then
        return
    end
    local marker
    if x >= 0 and x <= 1 and y >= 0 and y <= 1 then
        marker =
            AddMarker(plugin, markers, KEY_PREFIX .. id, { x = x, y = y }, name, C.FALLBACK_ATLAS, C.POI_PRIORITY, KIND)
        if marker then
            marker.texture, marker.sizeScale = icon, ICON_SCALE
        end
    end
    return { north = north, west = west, icon = icon, name = name, marker = marker or false }
end

local function Collect(plugin, state, snapshot)
    local count, instance = Number(snapshot.count), Number(snapshot.instance)
    local previous = state.instance == instance and state.entries or NO_ENTRIES
    local entries, markers, pending = {}, {}, false
    for index = 1, math.min(count or 0, MAX_OBSERVATIONS) do
        local record = Readable(snapshot[index])
        local id = type(record) == "table" and Number(record.id)
        local north, west = id and Number(record.north), id and Number(record.west)
        local icon, name = id and Number(record.icon), id and Readable(record.name)
        if north and west and icon and icon > 0 and type(name) == "string" and name ~= "" and not entries[id] then
            local entry = previous[id]
            if entry and entry.north == north and entry.west == west and entry.icon == icon and entry.name == name then
                if entry.marker then
                    markers[#markers + 1] = entry.marker
                end
            else
                entry = Project(plugin, markers, id, instance, north, west, icon, name)
                pending = pending or not entry
            end
            entries[id] = entry
        end
    end
    state.snapshot = snapshot
    if pending then
        -- Records seen before the first player world sample retry on the next poll, although the snapshot is unchanged.
        state.snapshot = PENDING_PROJECTION
    end
    state.entries, state.instance = entries, instance
    if not SameMarkers(state.markers, markers) then
        state.markers = markers
    end
end

function Plugin:RefreshCompassResources(state)
    local dots = Capability()
    if not dots then
        return UNSUPPORTED_RETRY
    end
    local snapshot = Readable(dots:GetResourceSnapshot())
    -- Orbit returns one immutable table per scanner revision, so an unchanged table settles the poll without work.
    if snapshot == state.snapshot then
        return
    end
    if type(snapshot) == "table" then
        Collect(self, state, snapshot)
        return
    end
    state.snapshot, state.entries, state.instance = nil, NO_ENTRIES, nil
    if #state.markers > 0 then
        state.markers = NO_MARKERS
    end
end
