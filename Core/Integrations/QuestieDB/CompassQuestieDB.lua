local _, Addon = ...
local Plugin = Addon.Controller
local C = Addon.Constants
local L = Addon.L
local Utils = Addon.SourceUtils
local Readable, Number = Utils.Readable, Utils.Number
local Index = Addon.CompassQuestieIndex
local Availability = Addon.CompassQuestieAvailability
local REFRESH_INTERVAL = 60
local GIVER_ATLAS, ENTRANCE_ATLAS = "QuestNormal", "Dungeon"
local DESCRIPTION_SEPARATOR = ", "
local WHITE = { r = 1, g = 1, b = 1 }
local ENTRANCE_LINES = table.freeze({ table.freeze({ text = L.PLU_COMPASS_TYPE_INSTANCE, r = 1, g = 1, b = 1 }) })

-- Each service's localized name and icon from the client's own minimap tracking list; empty until that list loads.
local function TrackingArt(plugin)
    local art = plugin.compassQuestieTracking
    if art then
        return art
    end
    local minimap = C_Minimap
    if
        type(minimap.GetNumTrackingTypes) ~= "function"
        or type(minimap.GetTrackingInfo) ~= "function"
        or type(minimap.GetTrackingFilter) ~= "function"
    then
        return {}
    end
    local count = Number(C_Minimap.GetNumTrackingTypes())
    if not count or count <= 0 then
        return {}
    end
    art = {}
    for index = 1, count do
        local info, filter = Readable(C_Minimap.GetTrackingInfo(index)), Readable(C_Minimap.GetTrackingFilter(index))
        local filterID = type(filter) == "table" and Number(filter.filterID)
        if filterID and type(info) == "table" and not art[filterID] then
            local name = Readable(info.name)
            art[filterID] = { texture = Number(info.texture), name = type(name) == "string" and name or nil }
        end
    end
    plugin.compassQuestieTracking = art
    return art
end

-- The player's map, its direct child maps (cities inside a zone) and its parent zone hold nearby spawns.
local function NearbyMaps(plugin)
    local maps, seen = { plugin.mapID }, { [plugin.mapID] = true }
    local children = Readable(C_Map.GetMapChildrenInfo(plugin.mapID))
    for _, child in ipairs(type(children) == "table" and children or {}) do
        local mapID = Readable(child) and Number(child.mapID)
        if mapID and not seen[mapID] and Number(child.parentMapID) == plugin.mapID then
            seen[mapID] = true
            maps[#maps + 1] = mapID
        end
    end
    local info = Readable(C_Map.GetMapInfo(plugin.mapID))
    local parentID = type(info) == "table" and Number(info.parentMapID)
    local parent = parentID and Readable(C_Map.GetMapInfo(parentID))
    if parent and Number(parent.mapType) == Enum.UIMapType.Zone and not seen[parentID] then
        maps[#maps + 1] = parentID
    end
    return maps
end

local function EntityName(lib, record)
    if record.entity == "instance" then
        return record.name
    end
    return Readable((record.entity == "npc" and lib.Npc or lib.Object).name(record.id))
end

local function QuestTitle(lib, questID)
    local title = Readable(C_QuestLog.GetTitleForQuestID(questID))
    if type(title) ~= "string" or title == "" then
        title = Readable(lib.Quest.name(questID))
    end
    return type(title) == "string" and title ~= "" and title or nil
end

-- Each available quest as a tooltip line, "[level] title" in the client's quest difficulty colour.
local function QuestLine(context, questID, title)
    local level = Availability.Level(context, questID)
    if not level then
        return { text = title, r = WHITE.r, g = WHITE.g, b = WHITE.b }
    end
    local color = type(GetQuestDifficultyColor) == "function" and Readable(GetQuestDifficultyColor(level))
    color = type(color) == "table" and color or WHITE
    return { text = L.PLU_COMPASS_QUEST_LEVEL_F:format(level, title), r = color.r, g = color.g, b = color.b }
end

-- Nil when none of the giver's quests is available; otherwise its summary and per-quest tooltip lines.
local function GiverQuests(lib, context, record)
    local first, count, lines = nil, 0, {}
    for _, questID in ipairs(record.quests) do
        if Availability.IsAvailable(context, questID) then
            count = count + 1
            local title = QuestTitle(lib, questID)
            if title then
                first = first or title
                lines[#lines + 1] = QuestLine(context, questID, title)
            end
        end
    end
    if count == 0 then
        return
    end
    local description = first and (count > 1 and L.PLU_COMPASS_QUEST_MORE_F:format(first, count - 1) or first)
    return { description = description, lines = lines }
end

local function ServiceDescription(art, record)
    local names = {}
    for _, filter in ipairs(record.services) do
        local entry = art[Enum.MinimapTrackingFilter[filter]]
        if entry and entry.name then
            names[#names + 1] = entry.name
        end
    end
    return table.concat(names, DESCRIPTION_SEPARATOR)
end

local function AddPoint(plugin, markers, mapID, point, name, prefix, atlas, priority, kind)
    local position = plugin:ProjectCompassDestination(mapID, point.x, point.y)
    if not position or type(name) ~= "string" or name == "" then
        return
    end
    local key = ("questie:%s:%s:%d:%d:%d"):format(prefix, point.record.entity, point.record.id, mapID, point.ordinal)
    return Utils.AddMarker(plugin, markers, key, position, name, atlas, priority, kind, {
        mapID = mapID,
        x = point.x,
        y = point.y,
    })
end

local function AddGivers(plugin, markers, lib, context, summaries, mapID, givers)
    for _, point in ipairs(givers) do
        local record = point.record
        if Availability.Serves(context, record) then
            -- One summary per giver per collection; its spawns share the read-only tooltip lines.
            local quests = summaries[record]
            if quests == nil then
                quests = GiverQuests(lib, context, record) or false
                summaries[record] = quests
            end
            if quests then
                local name = EntityName(lib, record)
                local marker =
                    AddPoint(plugin, markers, mapID, point, name, "giver", GIVER_ATLAS, C.QUEST_PRIORITY, "questOffer")
                if marker then
                    marker.description, marker.tooltipLines = quests.description, quests.lines
                end
            end
        end
        plugin:CompassDiscoveryCheckpoint()
    end
end

local function AddServices(plugin, markers, lib, context, mapID, services)
    local art = TrackingArt(plugin)
    for _, point in ipairs(services) do
        local record = point.record
        if Availability.Serves(context, record) then
            local marker = AddPoint(
                plugin,
                markers,
                mapID,
                point,
                EntityName(lib, record),
                "service",
                C.FALLBACK_ATLAS,
                C.POI_PRIORITY,
                "service"
            )
            if marker then
                local primary = art[Enum.MinimapTrackingFilter[record.services[1]]]
                marker.texture = primary and primary.texture
                local description = ServiceDescription(art, record)
                if description ~= "" then
                    marker.description = description
                    marker.tooltipLines = { { text = description, r = WHITE.r, g = WHITE.g, b = WHITE.b } }
                end
            end
        end
        plugin:CompassDiscoveryCheckpoint()
    end
end

-- Native journal entrances win for their map; Forever's client has none, so QuestieDB's entrances fill the gap there.
local function HasNativeEntrances(mapID)
    if not Addon.ClientFeatures.dungeonEntrances then
        return false
    end
    local entrances = Readable(C_EncounterJournal.GetDungeonEntrancesForMap(mapID))
    return type(entrances) == "table" and #entrances > 0
end

local function AddEntrances(plugin, markers, mapID, entrances)
    for _, point in ipairs(entrances) do
        local marker = AddPoint(
            plugin,
            markers,
            mapID,
            point,
            point.record.name,
            "entrance",
            ENTRANCE_ATLAS,
            C.POI_PRIORITY,
            "poi"
        )
        if marker then
            marker.description, marker.tooltipLines = L.PLU_COMPASS_TYPE_INSTANCE, ENTRANCE_LINES
        end
        plugin:CompassDiscoveryCheckpoint()
    end
end

function Plugin:CollectCompassQuestieDB(markers)
    local lib = Index.Provider()
    if not lib then
        return REFRESH_INTERVAL
    end
    local index, building = Index.Request(self, lib)
    if not index then
        if building then
            self:MarkCompassSourcePending()
        end
        return REFRESH_INTERVAL
    end
    local context, summaries = Availability.Context(lib, self.questLevelRange, index.quests), {}
    for _, mapID in ipairs(NearbyMaps(self)) do
        local entry = index.byMap[mapID]
        if entry then
            if self.showQuestOffers then
                AddGivers(self, markers, lib, context, summaries, mapID, entry.givers)
            end
            if self.showServices then
                AddServices(self, markers, lib, context, mapID, entry.services)
            end
            if self.showPOIs and #entry.entrances > 0 and not HasNativeEntrances(mapID) then
                AddEntrances(self, markers, mapID, entry.entrances)
            end
        end
    end
    return REFRESH_INTERVAL
end
