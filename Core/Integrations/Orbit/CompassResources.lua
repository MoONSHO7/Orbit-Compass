local _, Addon = ...
local Plugin = Addon.Controller
local C = Addon.Constants
local Utils = Addon.SourceUtils
local Readable, Number = Utils.Readable, Utils.Number
local MAX_OBSERVATIONS = 64
local OBSERVATION_LIFETIME = 2
local ICON_SCALE = 0.6

local function Provider()
    local host = Addon.OrbitHost
    if not Addon.ClientFeatures.sources.resources or not host then
        return
    end
    local dots, coordinates = Readable(host.MapDots), Readable(host.MapWorldCoordinates)
    if
        type(dots) == "table"
        and type(Readable(dots.GetResourceObservations)) == "function"
        and type(coordinates) == "table"
        and type(Readable(coordinates.WorldToMap)) == "function"
    then
        return dots, coordinates
    end
end

local function Snapshot(plugin, dots)
    local observations, count, instance = dots:GetResourceObservations()
    observations, count, instance = Readable(observations), Number(count), Number(instance)
    if type(observations) ~= "table" or not count or count < 0 or not instance then
        return
    end
    local records, now = {}, GetTime()
    for index = 1, math.min(count, MAX_OBSERVATIONS) do
        local node = Readable(observations[index])
        if type(node) == "table" and Readable(node.removed) ~= true then
            local north, west, icon = Number(node.north), Number(node.west), Number(node.icon)
            local name, lastSeen = Readable(node.name), Number(node.lastSeen)
            if
                north
                and west
                and icon
                and icon > 0
                and type(name) == "string"
                and name ~= ""
                and lastSeen
                and lastSeen <= now
                and now - lastSeen <= OBSERVATION_LIFETIME
            then
                local id = plugin.compassResourceIDs[node]
                if not id then
                    plugin.compassResourceSequence = plugin.compassResourceSequence + 1
                    id = plugin.compassResourceSequence
                    plugin.compassResourceIDs[node] = id
                end
                records[#records + 1] = {
                    id = id,
                    instance = instance,
                    north = north,
                    west = west,
                    icon = icon,
                    name = name,
                }
            end
        end
    end
    return records, instance
end

function Plugin:ReuseEmptyCompassResources(markers)
    if #markers > 0 then
        return false
    end
    local dots = Provider()
    if dots then
        local _, count = dots:GetResourceObservations()
        -- Positive observations still need projection, even if an earlier projection produced no markers.
        if Number(count) ~= 0 then
            return false
        end
    end
    self.compassResourceValidationAt = GetTime() + C.DISCOVERY_MIN_INTERVAL
    return true, not dots and math.huge or nil
end

function Plugin:CollectCompassResources(markers)
    local dots, coordinates = Provider()
    if not dots then
        return math.huge
    end
    -- The map scanner swaps and refines its array in place; copy observations before discovery can yield.
    local records, instance = Snapshot(self, dots)
    if not records then
        return
    end
    for _, record in ipairs(records) do
        local mapID, x, y = coordinates:WorldToMap(instance, record.north, record.west, self.mapID)
        mapID, x, y = Number(mapID), Number(x), Number(y)
        if mapID == self.mapID and x and y and x >= 0 and x <= 1 and y >= 0 and y <= 1 then
            local marker = Utils.AddMarker(
                self,
                markers,
                "resource:" .. record.id,
                { x = x, y = y },
                record.name,
                C.FALLBACK_ATLAS,
                C.POI_PRIORITY,
                "resource"
            )
            marker.texture, marker.sizeScale, marker.displayOnly = record.icon, ICON_SCALE, true
            marker.resourceObservation = record
        end
        self:CompassDiscoveryCheckpoint()
    end
end

function Plugin:ValidateCompassResources(markers)
    local dots = Provider()
    local observations, count, instance
    if dots then
        observations, count, instance = dots:GetResourceObservations()
    end
    observations, count, instance = Readable(observations), Number(count), Number(instance)
    local current, now = {}, GetTime()
    self.compassResourceValidationAt = now + C.DISCOVERY_MIN_INTERVAL
    if type(observations) == "table" and count and instance then
        for index = 1, math.min(count, MAX_OBSERVATIONS) do
            local node = Readable(observations[index])
            local id = type(node) == "table" and self.compassResourceIDs[node]
            if id then
                current[id] = node
            end
        end
    end
    local kept, total = 0, #markers
    for _, marker in ipairs(markers) do
        local record = marker.resourceObservation
        local node = current[record.id]
        local lastSeen = node and Number(node.lastSeen)
        if
            node
            and instance == record.instance
            and Readable(node.removed) ~= true
            and Number(node.north) == record.north
            and Number(node.west) == record.west
            and Number(node.icon) == record.icon
            and Readable(node.name) == record.name
            and lastSeen
            and lastSeen <= now
            and now - lastSeen <= OBSERVATION_LIFETIME
        then
            kept = kept + 1
            markers[kept] = marker
        end
    end
    for index = kept + 1, total do
        markers[index] = nil
    end
    return kept ~= total
end

function Plugin:RefreshCompassResources()
    local source = self.compassSources.resources
    if #source.markers == 0 then
        return
    end
    if self.compassResourceValidationAt and GetTime() < self.compassResourceValidationAt then
        return
    end
    -- A suspended source comparison may still hold the published array; replace it without mutating that snapshot.
    local markers = {}
    for index, marker in ipairs(source.markers) do
        markers[index] = marker
    end
    if self:ValidateCompassResources(markers) then
        source.markers = markers
        self:RebuildCompassMarkers()
    end
end
