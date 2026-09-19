local _, Addon = ...
local C = Addon.Constants
local Plugin = Addon.Controller
local Utils = Addon.SourceUtils
local Readable, Number, AddMarker = Utils.Readable, Utils.Number, Utils.AddMarker
local CONTENT_ATLAS = "waypoint-mappin-minimap-untracked"

function Plugin:CollectCompassTrackedContent(markers)
    if
        not Addon.ClientFeatures.content
        or not self.showTrackedContent
        or Readable(C_ContentTracking.GetCollectableSourceTrackingEnabled()) ~= true
    then
        return
    end
    local types = Utils.ReadList(self, C_ContentTracking.GetCollectableSourceTypes())
    self:CompassDiscoveryCheckpoint()
    local seen, titles = {}, {}
    for _, trackableType in ipairs(types or {}) do
        trackableType = Number(trackableType)
        if trackableType then
            local _, records = C_ContentTracking.GetTrackablesOnMap(trackableType, self.mapID)
            records = Utils.ReadList(self, records)
            self:CompassDiscoveryCheckpoint()
            for _, info in ipairs(records or {}) do
                info = Readable(info)
                local id = info and Number(info.trackableID)
                local targetType = info and Number(info.targetType)
                local targetID = info and Number(info.targetID)
                if
                    id
                    and targetType
                    and targetID
                    and Number(info.trackableType) == trackableType
                    and Utils.IsMapPosition(info)
                then
                    local titleKey = trackableType .. ":" .. id
                    local key = "content:" .. titleKey .. ":" .. targetType .. ":" .. targetID
                    if not seen[key] then
                        local title = titles[titleKey]
                        if title == nil then
                            title = Readable(C_ContentTracking.GetTitle(trackableType, id))
                            titles[titleKey] = title or false
                        end
                        if
                            AddMarker(
                                self,
                                markers,
                                key,
                                info,
                                title,
                                CONTENT_ATLAS,
                                C.TRACKED_QUEST_PRIORITY,
                                "content"
                            )
                        then
                            seen[key] = true
                        end
                    end
                end
                self:CompassDiscoveryCheckpoint()
            end
        end
        self:CompassDiscoveryCheckpoint()
    end
end
