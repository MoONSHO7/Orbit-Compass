local _, Addon = ...
local C = Addon.Constants
local Plugin = Addon.Controller
local Utils = Addon.SourceUtils
local Readable, Number, AddMarker = Utils.Readable, Utils.Number, Utils.AddMarker
local DIRECTIONS_ATLAS = "poi-traveldirections-arrow"
local DIG_SITE_ATLAS = "worldquest-icon-archaeology"
local PET_TAMER_ATLAS = "worldquest-icon-petbattle"

local function CollectMapRecords(plugin, markers, records, idField, kind, fallbackAtlas)
    records = Readable(records)
    plugin:CompassDiscoveryCheckpoint()
    local seen = {}
    for _, info in ipairs(records or {}) do
        info = Readable(info)
        local id = info and Number(info[idField])
        if id and not seen[id] and Utils.IsMapPosition(info.position) then
            local atlas = Readable(info.atlasName) or fallbackAtlas
            if AddMarker(plugin, markers, kind .. ":" .. id, info.position, info.name, atlas, C.POI_PRIORITY, kind) then
                seen[id] = true
            end
        end
        plugin:CompassDiscoveryCheckpoint()
    end
end

function Plugin:CollectCompassDirections(markers)
    if self.showDirections then
        local id = Number(C_GossipInfo.GetPoiForUiMapID(self.mapID))
        self:CompassDiscoveryCheckpoint()
        if id then
            local info = Readable(C_GossipInfo.GetPoiInfo(self.mapID, id))
            if info and Utils.IsMapPosition(info.position) then
                AddMarker(
                    self,
                    markers,
                    "directions:" .. id,
                    info.position,
                    info.name,
                    DIRECTIONS_ATLAS,
                    C.TRACKED_QUEST_PRIORITY,
                    "directions"
                )
            end
            self:CompassDiscoveryCheckpoint()
        end
    end
end

function Plugin:CollectCompassMapLinks(markers)
    if self.showMapLinks then
        CollectMapRecords(self, markers, C_Map.GetMapLinksForMap(self.mapID), "areaPoiID", "mapLink")
    end
end

function Plugin:CollectCompassPetTamers(markers)
    if self.showPetTamers and Readable(C_Minimap.CanTrackBattlePets()) == true then
        CollectMapRecords(
            self,
            markers,
            C_PetInfo.GetPetTamersForMap(self.mapID),
            "areaPoiID",
            "petTamer",
            PET_TAMER_ATLAS
        )
    end
end

function Plugin:CollectCompassDigSites(markers)
    if self.showDigSites then
        CollectMapRecords(
            self,
            markers,
            C_ResearchInfo.GetDigSitesForMap(self.mapID),
            "researchSiteID",
            "digSite",
            DIG_SITE_ATLAS
        )
    end
end
