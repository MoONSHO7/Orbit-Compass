local _, Addon = ...
local Plugin = Addon.Controller
local C = Addon.Constants
local Readable, Number = Addon.SourceUtils.Readable, Addon.SourceUtils.Number
local POINTS = {
    { key = "ShowWaypoint", field = "showWaypoint", labelKey = "PLU_COMPASS_WAYPOINT" },
    {
        key = "ShowQuestObjectives",
        field = "showQuestObjectives",
        source = "quests",
        labelKey = "PLU_COMPASS_QUEST_OBJECTIVES",
    },
    { key = "ShowWorldQuests", field = "showWorldQuests", source = "quests", labelKey = "PLU_COMPASS_WORLD_QUESTS" },
    {
        key = "ShowFlightMasters",
        field = "showFlightMasters",
        source = "taxi",
        labelKey = "PLU_COMPASS_FLIGHT_MASTERS",
    },
    { key = "ShowEvents", field = "showEvents", source = "map", labelKey = "PLU_COMPASS_EVENTS" },
    { key = "ShowRaces", field = "showRaces", source = "map", labelKey = "PLU_COMPASS_RACES" },
    { key = "ShowQuestHubs", field = "showQuestHubs", source = "map", labelKey = "PLU_COMPASS_QUEST_HUBS" },
    { key = "ShowPOIs", field = "showPOIs", source = "map", labelKey = "PLU_COMPASS_ZONE_POIS" },
    { key = "ShowVignettes", field = "showVignettes", source = "vignettes", labelKey = "PLU_COMPASS_VIGNETTES" },
    { key = "ShowDirections", field = "showDirections", source = "directions", labelKey = "PLU_COMPASS_DIRECTIONS" },
    { key = "ShowMapLinks", field = "showMapLinks", source = "links", labelKey = "PLU_COMPASS_MAP_LINKS" },
    { key = "ShowPetTamers", field = "showPetTamers", source = "tamers", labelKey = "PLU_COMPASS_PET_TAMERS" },
    { key = "ShowDigSites", field = "showDigSites", source = "digsites", labelKey = "PLU_COMPASS_DIG_SITES" },
    {
        key = "ShowTrackedContent",
        field = "showTrackedContent",
        source = "content",
        labelKey = "PLU_COMPASS_TRACKED_CONTENT",
    },
    { key = "ShowQuestOffers", field = "showQuestOffers", source = "offers", labelKey = "PLU_COMPASS_QUEST_OFFERS" },
    {
        key = "ShowSavedLocations",
        field = "showSavedLocations",
        source = "locations",
        labelKey = "PLU_COMPASS_SAVED_LOCATIONS",
    },
    { key = "ShowHandyNotes", field = "showHandyNotes", source = "handynotes", labelKey = "PLU_COMPASS_HANDYNOTES" },
}
Addon.CompassPointTypes = table.freeze(POINTS)

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

function Plugin:ResetCompassPointVisibility()
    self.compassPointsToggled = false
    for _, point in ipairs(POINTS) do
        self:SetSetting(C.SYSTEM_INDEX, point.key, Addon.Definition.defaults[point.key])
    end
    self:SetSetting(C.SYSTEM_INDEX, "PointVisibility", {})
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
    local area = PlayerArea(mapID or Number(C_Map.GetBestMapForUnit("player")))
    self.compassPointArea = area
    self.compassPointAreaRetry = not area and self.discoveryClock + C.DISCOVERY_INTERVAL or nil
    self:ApplyCompassPointVisibility()
end

function Plugin:ApplyCompassPointVisibility()
    local area = self.compassPointsToggled and "toggle" or self.compassPointArea
    for _, point in ipairs(POINTS) do
        local shown = area ~= nil and self.compassPointVisibility[area][point.key]
        if self[point.field] ~= shown then
            self[point.field] = shown
            if point.source then
                self:InvalidateCompassSourceSettings(point.source, true)
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
