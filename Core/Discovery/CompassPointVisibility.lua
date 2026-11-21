local _, Addon = ...
local Plugin = Addon.Controller
local C = Addon.Constants
local Readable, Number = Addon.SourceUtils.Readable, Addon.SourceUtils.Number
local POINTS = {
    {
        key = "ShowGatherMate",
        field = "showGatherMate",
        source = "gathermate",
        labelKey = "PLU_COMPASS_GATHERMATE",
        tooltipKey = "PLU_COMPASS_GATHERMATE_TT",
    },
    {
        key = "ShowHandyNotes",
        field = "showHandyNotes",
        source = "handynotes",
        labelKey = "PLU_COMPASS_HANDYNOTES",
        tooltipKey = "PLU_COMPASS_HANDYNOTES_TT",
    },
    {
        key = "ShowWaypoint",
        field = "showWaypoint",
        labelKey = "PLU_COMPASS_WAYPOINT",
        tooltipKey = "PLU_COMPASS_WAYPOINT_TT",
        ignoresRange = true,
    },
    {
        key = "ShowPlaces",
        field = "showPlaces",
        labelKey = "PLU_COMPASS_PLACES",
        tooltipKey = "PLU_COMPASS_PLACES_TT",
        places = true,
    },
    {
        key = "ShowQuestObjectives",
        field = "showQuestObjectives",
        source = { "quests", "questie" },
        kinds = { "quest" },
        labelKey = "PLU_COMPASS_QUEST_OBJECTIVES",
        tooltipKey = "PLU_COMPASS_QUEST_OBJECTIVES_TT",
    },
    {
        key = "ShowWorldQuests",
        field = "showWorldQuests",
        source = "quests",
        kinds = { "worldQuest" },
        labelKey = "PLU_COMPASS_WORLD_QUESTS",
        tooltipKey = "PLU_COMPASS_WORLD_QUESTS_TT",
    },
    {
        key = "ShowFlightMasters",
        field = "showFlightMasters",
        source = "taxi",
        labelKey = "PLU_COMPASS_FLIGHT_MASTERS",
        tooltipKey = "PLU_COMPASS_FLIGHT_MASTERS_TT",
    },
    {
        key = "ShowServices",
        field = "showServices",
        source = "questie",
        kinds = { "service" },
        labelKey = "PLU_COMPASS_SERVICES",
        tooltipKey = "PLU_COMPASS_SERVICES_TT",
    },
    {
        key = "ShowEvents",
        field = "showEvents",
        source = "map",
        kinds = { "event" },
        labelKey = "PLU_COMPASS_EVENTS",
        tooltipKey = "PLU_COMPASS_EVENTS_TT",
    },
    {
        key = "ShowRaces",
        field = "showRaces",
        source = "map",
        kinds = { "race" },
        labelKey = "PLU_COMPASS_RACES",
        tooltipKey = "PLU_COMPASS_RACES_TT",
    },
    {
        key = "ShowQuestHubs",
        field = "showQuestHubs",
        source = "map",
        kinds = { "questHub" },
        labelKey = "PLU_COMPASS_QUEST_HUBS",
        tooltipKey = "PLU_COMPASS_QUEST_HUBS_TT",
    },
    {
        key = "ShowPOIs",
        field = "showPOIs",
        source = { "map", "questie" },
        kinds = { "poi", "delve" },
        labelKey = "PLU_COMPASS_ZONE_POIS",
        tooltipKey = "PLU_COMPASS_ZONE_POIS_TT",
        foreverTooltipKey = "PLU_COMPASS_ZONE_POIS_FOREVER_TT",
    },
    {
        key = "ShowVignettes",
        field = "showVignettes",
        source = "vignettes",
        labelKey = "PLU_COMPASS_VIGNETTES",
        tooltipKey = "PLU_COMPASS_VIGNETTES_TT",
    },
    {
        key = "ShowDirections",
        field = "showDirections",
        source = "directions",
        labelKey = "PLU_COMPASS_DIRECTIONS",
        tooltipKey = "PLU_COMPASS_DIRECTIONS_TT",
    },
    {
        key = "ShowMapLinks",
        field = "showMapLinks",
        source = "links",
        labelKey = "PLU_COMPASS_MAP_LINKS",
        tooltipKey = "PLU_COMPASS_MAP_LINKS_TT",
    },
    {
        key = "ShowPetTamers",
        field = "showPetTamers",
        source = "tamers",
        labelKey = "PLU_COMPASS_PET_TAMERS",
        tooltipKey = "PLU_COMPASS_PET_TAMERS_TT",
    },
    {
        key = "ShowDigSites",
        field = "showDigSites",
        source = "digsites",
        labelKey = "PLU_COMPASS_DIG_SITES",
        tooltipKey = "PLU_COMPASS_DIG_SITES_TT",
    },
    {
        key = "ShowTrackedContent",
        field = "showTrackedContent",
        source = "content",
        labelKey = "PLU_COMPASS_TRACKED_CONTENT",
        tooltipKey = "PLU_COMPASS_TRACKED_CONTENT_TT",
    },
    {
        key = "ShowQuestOffers",
        field = "showQuestOffers",
        source = { "offers", "questie" },
        kinds = { "questOffer" },
        labelKey = "PLU_COMPASS_QUEST_OFFERS",
        tooltipKey = "PLU_COMPASS_QUEST_OFFERS_TT",
        foreverTooltipKey = "PLU_COMPASS_QUEST_OFFERS_FOREVER_TT",
    },
    {
        key = "ShowSavedLocations",
        field = "showSavedLocations",
        source = "locations",
        labelKey = "PLU_COMPASS_SAVED_LOCATIONS",
        tooltipKey = "PLU_COMPASS_SAVED_LOCATIONS_TT",
    },
}
Addon.CompassPointTypes = table.freeze(POINTS)
local ANY_KIND = true
-- A source shared by several rows names each row's marker kinds; a single-row source claims every kind.
local SOURCE_POINTS = {}
for _, point in ipairs(POINTS) do
    for _, source in ipairs(type(point.source) == "table" and point.source or { point.source }) do
        SOURCE_POINTS[source] = SOURCE_POINTS[source] or {}
        for _, kind in ipairs(point.kinds or { ANY_KIND }) do
            SOURCE_POINTS[source][kind] = point.key
        end
    end
end

function Addon.CompassMarkerPoint(source, kind)
    local points = SOURCE_POINTS[source]
    return points and (points[kind] or points[ANY_KIND])
end

local function ClampRange(yards)
    return math.max(C.RANGE_MIN, math.min(C.RANGE_MAX, yards))
end

local function PointValue(plugin, visibility, key, area)
    local values = visibility[key]
    if values and values[area] ~= nil then
        return values[area]
    end
    if area == "toggle" then
        return false
    end
    return plugin:GetSetting(C.SYSTEM_INDEX, key)
end

function Plugin:GetCompassPointVisibility(key, area)
    return PointValue(self, self:GetSetting(C.SYSTEM_INDEX, "PointVisibility"), key, area)
end

function Plugin:SetCompassPointVisibility(key, area, value)
    local visibility = CopyTable(self:GetSetting(C.SYSTEM_INDEX, "PointVisibility"))
    local values = {
        city = PointValue(self, visibility, key, "city"),
        world = PointValue(self, visibility, key, "world"),
        toggle = PointValue(self, visibility, key, "toggle"),
    }
    values[area] = value
    visibility[key] = values
    self:SetSetting(C.SYSTEM_INDEX, "PointVisibility", visibility)
end

function Plugin:GetCompassPointRange(key)
    local yards = self:GetSetting(C.SYSTEM_INDEX, "PointRanges")[key]
    return ClampRange(yards or self:GetSetting(C.SYSTEM_INDEX, "Range")), yards ~= nil
end

function Plugin:SetCompassPointRange(key, yards)
    local ranges = CopyTable(self:GetSetting(C.SYSTEM_INDEX, "PointRanges"))
    ranges[key] = yards
    self:SetSetting(C.SYSTEM_INDEX, "PointRanges", ranges)
end

function Plugin:CacheCompassRanges()
    self.range = ClampRange(self:GetSetting(C.SYSTEM_INDEX, "Range"))
    local saved, ranges = self:GetSetting(C.SYSTEM_INDEX, "PointRanges"), {}
    for _, point in ipairs(POINTS) do
        if saved[point.key] then
            ranges[point.key] = ClampRange(saved[point.key])
        end
    end
    self.compassPointRanges = ranges
end

function Plugin:GetCompassMarkerRange(marker)
    return self.compassPointRanges[marker.point] or self.range
end

function Plugin:ResetCompassPoints()
    self.compassPointsToggled = false
    local visibility = CopyTable(self:GetSetting(C.SYSTEM_INDEX, "PointVisibility"))
    local ranges = CopyTable(self:GetSetting(C.SYSTEM_INDEX, "PointRanges"))
    for _, point in ipairs(POINTS) do
        if Addon.ClientFeatures.AllowsPoint(point.key) then
            self:SetSetting(C.SYSTEM_INDEX, point.key, Addon.Definition.defaults[point.key])
            visibility[point.key], ranges[point.key] = nil, nil
        end
    end
    self:SetSetting(C.SYSTEM_INDEX, "PointVisibility", visibility)
    self:SetSetting(C.SYSTEM_INDEX, "PointRanges", ranges)
end

local function PlayerArea(mapID)
    local visited = {}
    while mapID and mapID > 0 and not visited[mapID] do
        visited[mapID] = true
        local isCity = Readable(C_Map.IsCityMap(mapID))
        if isCity == true then
            return "city"
        elseif isCity ~= false then
            return
        end
        local info = Readable(C_Map.GetMapInfo(mapID))
        if type(info) ~= "table" then
            return
        end
        mapID = Number(info.parentMapID)
    end
    if mapID == 0 then
        return "world"
    end
end

function Plugin:RefreshCompassPointArea(mapID)
    mapID = mapID or Number(C_Map.GetBestMapForUnit("player"))
    local area = PlayerArea(mapID)
    self.compassPointArea = area
    self.compassPointAreaRetry = not area and self.discoveryClock + C.DISCOVERY_INTERVAL or nil
    self:RefreshCompassCityArea(mapID)
    self:ApplyCompassPointVisibility()
end

function Plugin:ApplyCompassPointVisibility()
    local area = self.compassPointsToggled and "toggle" or self.compassPointArea
    for _, point in ipairs(POINTS) do
        local shown = Addon.ClientFeatures.AllowsPoint(point.key)
            and area ~= nil
            and self.compassPointVisibility[area][point.key]
        if self[point.field] ~= shown then
            if self.compassAutoAdvance then
                self.compassAutoAdvance.awaitingSource = true
                self.compassAutoAdvance.missingSince = nil
            end
            self[point.field] = shown
            if type(point.source) == "table" then
                for _, source in ipairs(point.source) do
                    self:InvalidateCompassSourceSettings(source, true)
                end
            elseif point.source then
                self:InvalidateCompassSourceSettings(point.source, true)
            elseif point.places then
                self.bearingsDirty = true
            else
                self.waypointDirty = true
            end
        end
    end
end

function Plugin:ToggleCompassPoints()
    if not self.compassPointVisibility or not self:IsActive() or self:IsProfileSuppressed() then
        return
    end
    self.compassPointsToggled = not self.compassPointsToggled
    self:ApplyCompassPointVisibility()
    self.renderDirty = true
end

function Plugin:CacheCompassPointVisibility()
    local visibility = self:GetSetting(C.SYSTEM_INDEX, "PointVisibility")
    local cached = { city = {}, world = {}, toggle = {} }
    for _, point in ipairs(POINTS) do
        cached.city[point.key] = PointValue(self, visibility, point.key, "city")
        cached.world[point.key] = PointValue(self, visibility, point.key, "world")
        cached.toggle[point.key] = PointValue(self, visibility, point.key, "toggle")
    end
    self.compassPointVisibility = cached
    self:RefreshCompassPointArea()
end
