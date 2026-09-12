local _, Addon = ...
local Plugin = Addon.Controller
local Readable = Addon.SourceUtils.Readable
local COORDINATE_EPSILON = 0.00001

local function InvalidateGuides(plugin)
    if plugin.discoveryJob and plugin.discoveryJob.source == plugin.compassSources.handynotes then
        plugin.discoveryJob = nil
    end
    plugin:InvalidateCompassSource("ORBIT_COMPASS_HANDYNOTES")
    plugin.waypointDirty = true
end

function Plugin:ClearCompassHandyNotesGuides()
    if not self.compassHandyNotesGuide then
        return
    end
    self.compassHandyNotesGuide = nil
    local markers = self.compassSources.handynotes.markers
    local retained = 0
    for _, marker in ipairs(markers) do
        if not marker.handynotesGuide then
            retained = retained + 1
            markers[retained] = marker
        end
    end
    for index = #markers, retained + 1, -1 do
        markers[index] = nil
    end
    InvalidateGuides(self)
end

local function MatchesDestination(record, sourceKey, mapID, x, y)
    return record.key == sourceKey
        and record.mapID == mapID
        and math.abs(record.x - x) < COORDINATE_EPSILON
        and math.abs(record.y - y) < COORDINATE_EPSILON
end

function Plugin:RetainCompassHandyNotesGuides(sourceKey, mapID, x, y)
    local guide = self.compassHandyNotesGuide
    if not guide then
        return
    end
    if MatchesDestination(guide.parent, sourceKey, mapID, x, y) then
        return
    end
    if guide.records then
        for _, record in ipairs(guide.records) do
            if MatchesDestination(record, sourceKey, mapID, x, y) then
                return
            end
        end
    end
    self:ClearCompassHandyNotesGuides()
end

function Plugin:SelectCompassHandyNotesGuides(action, parent)
    self:ClearCompassHandyNotesGuides()
    self.compassHandyNotesGuide = { action = action, key = parent.key, parent = parent }
    InvalidateGuides(self)
end

function Plugin:CollectCompassHandyNotesGuides(snapshots, failures)
    local guide = self.compassHandyNotesGuide
    if not guide then
        return false
    end
    local job = self.discoveryJob
    local parent
    for _, record in ipairs(snapshots) do
        if record.key == guide.key and Addon.HandyNotesClick:Matches(record.handynotesPoint, guide.action) then
            parent = record
            break
        end
    end
    if not parent then
        for _, failure in ipairs(failures) do
            if failure.providerName == guide.action.providerName then
                return true
            end
        end
        self.compassHandyNotesGuide = nil
        return false
    end
    if not guide.records or guide.parent ~= parent or guide.pending then
        local success, records, pending =
            pcall(Addon.HandyNotesGuides.Read, Addon.HandyNotesGuides, guide.action, parent.name, parent.description)
        if self.compassHandyNotesGuide ~= guide or self.discoveryJob ~= job then
            return false
        end
        if not success then
            local err = Readable(records)
            err = type(err) == "string" and err or type(err)
            if guide.error ~= err then
                guide.error = err
                Addon.LibOrbitUI.Callbacks:LogError("Compass.HandyNotes.Guides", guide.action.providerName, err)
            end
            records, pending = {}, true
        end
        guide.parent, guide.records, guide.pending = parent, records, pending
    end
    for _, record in ipairs(guide.records) do
        record.handynotesGuide = true
        snapshots[#snapshots + 1] = record
    end
    return guide.pending
end
