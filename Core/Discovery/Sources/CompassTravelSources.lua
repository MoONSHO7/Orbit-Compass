local _, Addon = ...
local L = Addon.L
local C = Addon.Constants
local Plugin = Addon.Controller
local F = Addon.ClientFeatures
local Utils = Addon.SourceUtils
local Readable, Number, AddMarker = Utils.Readable, Utils.Number, Utils.AddMarker
local DIRECTIONS_ATLAS = C.DIRECTIONS_ATLAS
local DIG_SITE_ATLAS = "worldquest-icon-archaeology"
local PET_TAMER_ATLAS = "worldquest-icon-petbattle"
local ROUTED_TRACKING = {}
for name, enabled in pairs({ UserWaypoint = true, MapPin = true, Content = F.content, Vignette = F.vignettes }) do
    local value = Enum.SuperTrackingType[name]
    if enabled and value ~= nil then
        ROUTED_TRACKING[value] = true
    end
end

local function CollectMapRecords(plugin, markers, records, idField, kind, fallbackAtlas)
    records = Utils.ReadList(plugin, records)
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
    if self.showDirections and F.directions then
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

local function ReadUserWaypoint()
    local point = Readable(C_Map.GetUserWaypoint())
    local mapID = point and Number(point.uiMapID)
    local x, y = Utils.ReadPosition(point and point.position)
    if mapID and x and y then
        return { mapID = mapID, x = x, y = y }
    end
end

local function RouteTarget(plugin, tracking)
    if tracking == Enum.SuperTrackingType.UserWaypoint then
        local destination = ReadUserWaypoint()
        if not destination then
            return
        end
        local label = plugin.waypointLabel
        return destination, label and label.title, label and label.artwork or { atlas = C.FALLBACK_ATLAS }
    elseif tracking == Enum.SuperTrackingType.MapPin then
        local pinType, id = plugin:GetCompassTrackedPin()
        if not pinType or not plugin:FollowsCompassPin(pinType, id) then
            return
        end
        local landmark = plugin:ResolveCompassPinDestination(pinType, id)
        return landmark or false, landmark and landmark.name, landmark
    elseif plugin.followTracked then
        return false
    end
end

function Plugin:CollectCompassRoute(markers)
    if not F.route then
        return
    end
    local tracking = Number(C_SuperTrack.GetHighestPrioritySuperTrackingType())
    if not ROUTED_TRACKING[tracking] then
        return
    end
    local target, name, artwork = RouteTarget(self, tracking)
    if target == nil then
        return
    end
    local x, y, text = C_Navigation.GetNextWaypointForMap(self.mapID)
    self:CompassDiscoveryCheckpoint()
    if type(name) ~= "string" or name == "" then
        name = Readable(C_SuperTrack.GetSuperTrackedItemName())
    end
    if type(name) ~= "string" or name == "" then
        name = L.PLU_COMPASS_WAYPOINT
    end
    local shown = target and self:ProjectCompassDestination(target.mapID, target.x, target.y)
    if shown or not artwork then
        artwork = nil
    end
    local marker = AddMarker(
        self,
        markers,
        "route:" .. tracking,
        { x = x, y = y },
        name,
        artwork and artwork.atlas or DIRECTIONS_ATLAS,
        C.TRACKED_QUEST_PRIORITY,
        "route",
        target or nil
    )
    if marker then
        text = Readable(text)
        marker.description = type(text) == "string" and text ~= "" and text or nil
        marker.routeTracking, marker.routeDestination = tracking, target ~= false
        if artwork then
            for _, field in ipairs(C.MARKER_ART_FIELDS) do
                if artwork[field] ~= nil then
                    marker[field] = artwork[field]
                end
            end
        end
    end
end

function Plugin:CollectCompassMapLinks(markers)
    if self.showMapLinks and F.links then
        CollectMapRecords(self, markers, C_Map.GetMapLinksForMap(self.mapID), "areaPoiID", "mapLink")
    end
end

function Plugin:CollectCompassPetTamers(markers)
    if self.showPetTamers and F.petTamers and Readable(C_Minimap.CanTrackBattlePets()) == true then
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
    if self.showDigSites and F.digSites then
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
