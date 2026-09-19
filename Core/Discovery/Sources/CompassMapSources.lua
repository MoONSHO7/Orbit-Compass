local _, Addon = ...
local C = Addon.Constants
local Plugin = Addon.Controller
local F = Addon.ClientFeatures
local Utils = Addon.SourceUtils
local Readable, Number, AddMarker = Utils.Readable, Utils.Number, Utils.AddMarker
local POI_RETRY_INTERVAL = 30
local POI_GROUPS = {
    {
        enabled = F.events,
        setting = "showEvents",
        query = C_AreaPoiInfo and C_AreaPoiInfo.GetEventsForMap,
        kind = "event",
    },
    {
        enabled = F.races,
        setting = "showRaces",
        query = C_AreaPoiInfo and C_AreaPoiInfo.GetDragonridingRacesForMap,
        kind = "race",
    },
    {
        enabled = F.questHubs,
        setting = "showQuestHubs",
        query = C_AreaPoiInfo and C_AreaPoiInfo.GetQuestHubsForMap,
        kind = "questHub",
    },
    {
        enabled = F.delves,
        setting = "showPOIs",
        query = C_AreaPoiInfo and C_AreaPoiInfo.GetDelvesForMap,
        kind = "delve",
    },
    {
        enabled = F.genericPOIs,
        setting = "showPOIs",
        query = C_AreaPoiInfo and C_AreaPoiInfo.GetAreaPOIForMap,
        kind = "poi",
    },
}
local VIGNETTE_KINDS = { vignettekill = "rare", vignettekillelite = "rareElite", vignettekillboss = "worldBoss" }

local function POIRefreshInterval(id)
    local timed = Readable(C_AreaPoiInfo.IsAreaPOITimed(id))
    if timed == false then
        return math.huge
    end
    local seconds = timed == true and Number(C_AreaPoiInfo.GetAreaPOISecondsLeft(id))
    return seconds and seconds > 0 and seconds or POI_RETRY_INTERVAL
end

local function VignetteKind(info)
    local atlas = Readable(info.atlasName)
    atlas = type(atlas) == "string" and atlas:lower() or ""
    if Number(info.type) == Enum.VignetteType.Treasure or atlas:find("^vignetteloot") then
        return "treasure"
    end
    return VIGNETTE_KINDS[atlas] or "poi"
end

function Plugin:CollectCompassMapPoints(markers)
    if not self.showPOIs and not self.showEvents and not self.showRaces and not self.showQuestHubs then
        return
    end
    local seen, refreshAt = {}, math.huge
    for _, group in ipairs(POI_GROUPS) do
        local ids = {}
        if group.enabled then
            ids = Readable(group.query(self.mapID))
        end
        if type(ids) ~= "table" then
            ids = nil
            self:MarkCompassSourcePending()
            refreshAt = math.min(refreshAt, self.discoveryClock + POI_RETRY_INTERVAL)
        end
        self:CompassDiscoveryCheckpoint()
        for _, id in ipairs(ids or {}) do
            id = Number(id)
            if not id then
                refreshAt = math.min(refreshAt, self.discoveryClock + POI_RETRY_INTERVAL)
            elseif not seen[id] then
                -- Claim category membership even when disabled; generic POIs can contain the same IDs.
                seen[id] = true
                if self[group.setting] then
                    local info = Readable(C_AreaPoiInfo.GetAreaPOIInfo(self.mapID, id))
                    local marker
                    if type(info) == "table" then
                        marker = AddMarker(
                            self,
                            markers,
                            "poi:" .. id,
                            info.position,
                            info.name,
                            info.atlasName,
                            C.POI_PRIORITY,
                            group.kind
                        )
                    end
                    local interval = marker and POIRefreshInterval(id) or POI_RETRY_INTERVAL
                    refreshAt = math.min(refreshAt, self.discoveryClock + interval)
                end
            end
            self:CompassDiscoveryCheckpoint()
        end
    end
    if self.showPOIs and F.dungeonEntrances then
        local entrances = Readable(C_EncounterJournal.GetDungeonEntrancesForMap(self.mapID))
        if type(entrances) ~= "table" then
            entrances = nil
            self:MarkCompassSourcePending()
            refreshAt = math.min(refreshAt, self.discoveryClock + POI_RETRY_INTERVAL)
        end
        self:CompassDiscoveryCheckpoint()
        for _, info in ipairs(entrances or {}) do
            info = Readable(info)
            local id = type(info) == "table" and Number(info.areaPoiID)
            if not id then
                refreshAt = math.min(refreshAt, self.discoveryClock + POI_RETRY_INTERVAL)
            elseif not seen[id] then
                seen[id] = true
                if
                    not AddMarker(
                        self,
                        markers,
                        "poi:" .. id,
                        info.position,
                        info.name,
                        info.atlasName,
                        C.POI_PRIORITY,
                        "poi"
                    )
                then
                    refreshAt = math.min(refreshAt, self.discoveryClock + POI_RETRY_INTERVAL)
                end
            end
            self:CompassDiscoveryCheckpoint()
        end
    end
    if refreshAt < math.huge then
        return math.max(C.DISCOVERY_MIN_INTERVAL, refreshAt - self.discoveryClock)
    end
end

function Plugin:CollectCompassFlightMasters(markers)
    if self.showFlightMasters and F.taxi then
        local faction = Readable(UnitFactionGroup("player"))
        local nodes = Utils.ReadList(self, C_TaxiMap.GetTaxiNodesForMap(self.mapID))
        self:CompassDiscoveryCheckpoint()
        for _, node in ipairs(nodes or {}) do
            node = Readable(node)
            if node then
                local id, side = Number(node.nodeID), Number(node.faction)
                local friendly = side == Enum.FlightPathFaction.Neutral
                    or (side == Enum.FlightPathFaction.Alliance and faction == "Alliance")
                    or (side == Enum.FlightPathFaction.Horde and faction == "Horde")
                if id and friendly then
                    AddMarker(
                        self,
                        markers,
                        "taxi:" .. id,
                        node.position,
                        node.name,
                        node.atlasName,
                        C.POI_PRIORITY,
                        "flightMaster"
                    )
                end
            end
            self:CompassDiscoveryCheckpoint()
        end
    end
end

function Plugin:CollectCompassVignettes(markers)
    if not self.showVignettes or not F.vignettes then
        return
    end
    local ids = Utils.ReadList(self, C_VignetteInfo.GetVignettes())
    self:CompassDiscoveryCheckpoint()
    for _, id in ipairs(ids or {}) do
        id = Readable(id)
        local info = id and Readable(C_VignetteInfo.GetVignetteInfo(id))
        if
            info
            and Readable(info.isDead) == false
            and Readable(info.inFogOfWar) == false
            and (Readable(info.onWorldMap) == true or Readable(info.onMinimap) == true)
        then
            local position = C_VignetteInfo.GetVignettePosition(id, self.mapID)
            AddMarker(
                self,
                markers,
                "vignette:" .. id,
                position,
                info.name,
                info.atlasName,
                C.VIGNETTE_PRIORITY,
                VignetteKind(info)
            )
        end
        self:CompassDiscoveryCheckpoint()
    end
end
