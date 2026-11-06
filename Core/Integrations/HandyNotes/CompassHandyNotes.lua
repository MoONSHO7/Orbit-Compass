local _, Addon = ...
local C = Addon.Constants
local Plugin = Addon.Controller
local Utils = Addon.SourceUtils
local Readable, Number = Utils.Readable, Utils.Number
local Read = Addon.HandyNotesRead
local Providers = Addon.HandyNotesProviders
local RETRY_INTERVAL = 30

function Plugin:CollectCompassHandyNotes(markers)
    local job = self.discoveryJob
    if not self.compassIntegrationsEnabled or not self.showHandyNotes then
        self.compassHandyNotesGuide = nil
        return
    end
    self:ConnectCompassHandyNotes()
    if self.discoveryJob ~= job then
        return
    end
    local addon = self.compassHandyNotesAddon
    if not addon then
        self.compassHandyNotesGuide = nil
        return
    end
    local database = addon and Read.Table(addon.db)
    local profile = database and Read.Table(database.profile)
    local enabledPlugins = profile and Read.Table(profile.enabledPlugins)
    if not enabledPlugins then
        return RETRY_INTERVAL
    end
    if
        Readable(profile.enabled) ~= true or (Read.Callable(addon.IsEnabled) and Readable(addon:IsEnabled()) ~= true)
    then
        self.compassHandyNotesGuide = nil
        return
    end
    local scale, alpha = Number(profile.icon_scale) or 1, Number(profile.icon_alpha) or 1
    if scale <= 0 or alpha <= 0 then
        self.compassHandyNotesGuide = nil
        return
    end
    if self.discoveryJob ~= job then
        return
    end
    local snapshots, failures, incomplete = Providers.Collect(self, addon, enabledPlugins, scale, alpha, job)
    if self.discoveryJob ~= job then
        return
    end
    if #failures > 0 then
        self:MarkCompassSourcePending()
    end
    local guidesPending = self:CollectCompassHandyNotesGuides(snapshots, failures)
    if self.discoveryJob ~= job then
        return
    end
    incomplete = incomplete or guidesPending
    table.sort(snapshots, function(left, right)
        return left.key < right.key
    end)
    for _, snapshot in ipairs(snapshots) do
        local position = self:ProjectCompassDestination(snapshot.mapID, snapshot.x, snapshot.y)
        if position then
            local marker = Utils.AddMarker(
                self,
                markers,
                snapshot.key,
                position,
                snapshot.name,
                C.FALLBACK_ATLAS,
                C.POI_PRIORITY,
                "handynotes",
                { mapID = snapshot.mapID, x = snapshot.x, y = snapshot.y }
            )
            marker.description = snapshot.description
            marker.handynotesNode = snapshot.handynotesNode
            marker.handynotesPoint = snapshot.handynotesPoint
            marker.handynotesGuide = snapshot.handynotesGuide
            marker.texture = snapshot.texture
            marker.texLeft, marker.texRight = snapshot.texLeft, snapshot.texRight
            marker.texTop, marker.texBottom = snapshot.texTop, snapshot.texBottom
            marker.colorR, marker.colorG, marker.colorB = snapshot.colorR, snapshot.colorG, snapshot.colorB
            marker.sourceAlpha, marker.sizeScale = snapshot.sourceAlpha, snapshot.sizeScale
        end
        self:CompassDiscoveryCheckpoint()
    end
    if #failures > 0 or incomplete then
        return RETRY_INTERVAL
    end
end
