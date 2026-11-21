local _, Addon = ...
local Plugin = Addon.Controller
local C = Addon.Constants
local L = Addon.L
local Utils = Addon.SourceUtils
local Readable, Number = Utils.Readable, Utils.Number
local Bridge = LibStub("LibOrbitBridge-1.0")
local Questie = Bridge.Questie
local Lines = Addon.CompassQuestieLines
local Instances = Addon.CompassQuestieInstances
local LogRows = Addon.CompassQuestieLogRows
local Menu = Addon.CompassQuestieMenu
local Hidden, Hints = Addon.CompassQuestieHidden, Addon.CompassQuestieHints
local REFRESH_INTERVAL = 60
local BRIDGE_PROFILER_PREFIX = "Compass.Bridge."
local BRIDGE_EVENTS = { "QuestieIndexReady", "QuestieExistenceChanged", "QuestiePlacesFound", "QuestieLogChanged" }
local GIVER_ATLAS, ENTRANCE_ATLAS, RAID_ATLAS = "QuestNormal", "Dungeon", "Raid"
-- A giver on the host's map draws at three quarters of its atlas size, so a hub's givers crowd its ground less.
local MAP_GIVER_SCALE = 0.75
-- QuestNormal's mark and the service icons fill about 90% of their box where native POI art fills about 75%.
local RIBBON_ICON_SCALE = 0.8
-- Blizzard's 64px interaction art doubles the 32px tracking icons; bankers and auctioneers have none.
local SERVICE_ATLASES = table.freeze({
    Innkeeper = "crosshair_innkeeper_64",
    Mailbox = "crosshair_mail_64",
    Repair = "crosshair_repairnpc_64",
    Stablemaster = "crosshair_stablemaster_64",
})
local SERVICE_ATLAS_PIXELS = 64
local FULL_SERVICE_CROP =
    table.freeze({ left = 0, right = SERVICE_ATLAS_PIXELS, top = 0, bottom = SERVICE_ATLAS_PIXELS })
-- The envelope sits low and right in its atlas; this square of its pixels centres it.
local SERVICE_CROPS = table.freeze({ Mailbox = table.freeze({ left = 9, right = 64, top = 8.5, bottom = 63.5 }) })
-- Icons one map may show for quests an item starts: five such quests with their hints on at their full 24 spots.
local MAX_START_ROWS = 120
local DESCRIPTION_SEPARATOR = ", "
local WHITE = { r = 1, g = 1, b = 1 }
local NO_ROWS = table.freeze({})
local ENTRANCE_LINES = table.freeze({ table.freeze({ text = L.PLU_COMPASS_TYPE_INSTANCE, r = 1, g = 1, b = 1 }) })

-- Quests the player removed from the host's map stay out of every availability verdict.
local function Excluded(plugin)
    return function(questID)
        return Hidden.Has(plugin, questID)
    end
end

-- The player's map, its direct child maps (cities inside a zone) and its parent zone in full, then other maps that
-- hold nearby towns, limited to the points inside those towns' rectangles (returned by map position).
local function NearbyMaps(plugin)
    local maps, seen, towns = { plugin.mapID }, { [plugin.mapID] = true }, {}
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
        seen[parentID] = true
        maps[#maps + 1] = parentID
    end
    for _, town in ipairs(plugin:GetCompassTownMaps()) do
        if not seen[town.mapID] then
            seen[town.mapID] = true
            maps[#maps + 1] = town.mapID
            towns[#maps] = town.rects
        end
    end
    return maps, towns
end

local function InTowns(rects, point)
    if not rects then
        return true
    end
    for _, rect in ipairs(rects) do
        if point.x >= rect[1] and point.x <= rect[3] and point.y >= rect[2] and point.y <= rect[4] then
            return true
        end
    end
    return false
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

-- Nil when none of the giver's quests is available; otherwise its summary and per-quest tooltip lines.
local function GiverQuests(lib, context, record)
    local first, count, lines, quests = nil, 0, {}, {}
    for _, questID in ipairs(record.quests) do
        if Questie.IsAvailable(context, questID) then
            count = count + 1
            local title = QuestTitle(lib, questID)
            if title then
                first = first or title
                lines[#lines + 1] = Lines.Quest(Questie.Level(context, questID), title)
                quests[#quests + 1] = { id = questID, title = lines[#lines].text }
            end
        end
    end
    if count == 0 then
        return
    end
    local description = first and (count > 1 and L.PLU_COMPASS_QUEST_MORE_F:format(first, count - 1) or first)
    return { description = description, lines = lines, quests = quests }
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

-- A texture window rather than SetAtlas, so the envelope's crop applies on the ribbon, its menus and search alike.
local function ServiceArt(plugin, filter)
    local cache = plugin.compassQuestieServiceArt
    if not cache then
        cache = {}
        plugin.compassQuestieServiceArt = cache
    end
    local art = cache[filter]
    if art ~= nil then
        return art
    end
    local atlas = SERVICE_ATLASES[filter]
    local info = atlas and C_Texture.GetAtlasInfo(atlas)
    art = false
    if type(info) == "table" and (info.file or info.filename) then
        local crop = SERVICE_CROPS[filter] or FULL_SERVICE_CROP
        local width = (info.rightTexCoord - info.leftTexCoord) / SERVICE_ATLAS_PIXELS
        local height = (info.bottomTexCoord - info.topTexCoord) / SERVICE_ATLAS_PIXELS
        art = {
            texture = info.file or info.filename,
            texLeft = info.leftTexCoord + width * crop.left,
            texRight = info.leftTexCoord + width * crop.right,
            texTop = info.topTexCoord + height * crop.top,
            texBottom = info.topTexCoord + height * crop.bottom,
        }
    end
    cache[filter] = art
    return art
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

local function AddGivers(plugin, markers, lib, context, summaries, mapID, givers, rects)
    for _, point in ipairs(givers) do
        local record = point.record
        if InTowns(rects, point) and Questie.Serves(context, record) then
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
                    marker.sizeScale = RIBBON_ICON_SCALE
                end
            end
        end
        plugin:CompassDiscoveryCheckpoint()
    end
end

local function AddServices(plugin, markers, lib, context, mapID, services, rects)
    local art = Questie.TrackingArt()
    for _, point in ipairs(services) do
        local record = point.record
        if InTowns(rects, point) and Questie.Serves(context, record) then
            local name = EntityName(lib, record)
            local marker =
                AddPoint(plugin, markers, mapID, point, name, "service", C.FALLBACK_ATLAS, C.POI_PRIORITY, "service")
            if marker then
                local filter = record.services[1]
                local hd = ServiceArt(plugin, filter)
                if hd then
                    marker.texture, marker.texLeft, marker.texRight = hd.texture, hd.texLeft, hd.texRight
                    marker.texTop, marker.texBottom = hd.texTop, hd.texBottom
                else
                    local primary = art[Enum.MinimapTrackingFilter[filter]]
                    marker.texture = primary and primary.texture
                end
                marker.sizeScale = marker.texture and RIBBON_ICON_SCALE or marker.sizeScale
                local description = ServiceDescription(art, record)
                if description ~= "" and description ~= name then
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

-- The group finder names an instance a raid and suggests its levels; one it does not list keeps the plain label.
local function AddEntrances(plugin, markers, mapID, entrances, levels, rects)
    for _, point in ipairs(entrances) do
        if InTowns(rects, point) then
            local range = levels[point.record.id]
            local atlas = range and range.raid and RAID_ATLAS or ENTRANCE_ATLAS
            local marker =
                AddPoint(plugin, markers, mapID, point, point.record.name, "entrance", atlas, C.POI_PRIORITY, "poi")
            if marker and range then
                marker.description = range.raid and L.PLU_COMPASS_TYPE_RAID or L.PLU_COMPASS_TYPE_INSTANCE
                marker.tooltipLines = { Lines.Plain(marker.description), Lines.Level(range.minLevel, range.maxLevel) }
            elseif marker then
                marker.description, marker.tooltipLines = L.PLU_COMPASS_TYPE_INSTANCE, ENTRANCE_LINES
            end
        end
        plugin:CompassDiscoveryCheckpoint()
    end
end

-- A quest an item starts has no giver, so it draws where that item drops: one icon at the densest spot to stand
-- for it, or every spot once the player shows its hint from that icon's right-click.
local function AddStartRows(plugin, rows, lib, index, context, mapID, menus)
    local count = 0
    for _, start in ipairs(index.startQuests) do
        local questID = start.id
        local places = Questie.InRange(context, start.level)
            and Questie.IsAvailable(context, questID)
            and Questie.Places(index, questID, mapID, true)
        local title = places and QuestTitle(lib, questID)
        if places == nil then
            Questie.Prepare(plugin, index, questID, mapID, true)
        elseif title then
            local hinted = Hints.Has(plugin, questID)
            local line = Lines.Quest(Questie.Level(context, questID), title)
            for position, item in ipairs(places.plan.objectives) do
                local spots = places.spots[position]
                for rank = 1, spots and (hinted and #spots or 1) or 0 do
                    if count >= MAX_START_ROWS then
                        return
                    end
                    count = count + 1
                    local spot = spots[rank]
                    local row = {
                        key = ("start:%d:%d:%d"):format(questID, position, spot.cell),
                        x = spot.x,
                        y = spot.y,
                        atlas = GIVER_ATLAS,
                        scale = MAP_GIVER_SCALE,
                        name = item.name or title,
                        lines = { line, Lines.Sources(spot.sources) },
                    }
                    Menu.Add(menus, row, questID, line.text, hinted, true)
                    rows[#rows + 1] = row
                end
                if spots and not hinted then
                    break
                end
            end
        end
    end
end

local function AddGiverRows(plugin, rows, lib, index, mapID, menus)
    local context, summaries = Questie.Context(index, plugin.questLevelRange, Excluded(plugin)), {}
    AddStartRows(plugin, rows, lib, index, context, mapID, menus)
    local entry = index.byMap[mapID]
    if not entry then
        return
    end
    for _, point in ipairs(entry.givers) do
        local record = point.record
        if Questie.Serves(context, record) then
            local quests = summaries[record]
            if quests == nil then
                quests = GiverQuests(lib, context, record) or false
                summaries[record] = quests
            end
            local name = quests and EntityName(lib, record)
            if type(name) == "string" and name ~= "" then
                local row = {
                    key = ("giver:%s:%d:%d"):format(record.entity, record.id, point.ordinal),
                    x = point.x,
                    y = point.y,
                    atlas = GIVER_ATLAS,
                    scale = MAP_GIVER_SCALE,
                    name = name,
                    description = quests.description,
                    lines = quests.lines,
                }
                for _, quest in ipairs(quests.quests) do
                    Menu.Add(menus, row, quest.id, quest.title)
                end
                rows[#rows + 1] = row
            end
        end
    end
end

-- Nil tells the host's map the index is still building; an empty list that there is nothing to draw.
function Plugin:CollectCompassQuestieMapRows(mapID)
    local lib = (self.showQuestOffers or self.showQuestObjectives) and Questie.Provider()
    if not lib then
        return NO_ROWS
    end
    local index, building = Questie.Request(self, lib)
    if not index then
        return not building and NO_ROWS or nil
    end
    local rows, menus = {}, Menu.Begin(self, mapID)
    if self.showQuestOffers then
        AddGiverRows(self, rows, lib, index, mapID, menus)
    end
    if self.showQuestObjectives then
        LogRows.Add(self, rows, index, mapID, menus)
    end
    return rows
end

function Plugin:CollectCompassQuestieDB(markers)
    local lib = Questie.Provider()
    if not lib then
        return REFRESH_INTERVAL
    end
    local index, building = Questie.Request(self, lib)
    if not index then
        if building then
            self:MarkCompassSourcePending()
        end
        return REFRESH_INTERVAL
    end
    local context, summaries = Questie.Context(index, self.questLevelRange, Excluded(self)), {}
    local levels
    local maps, towns = NearbyMaps(self)
    for position, mapID in ipairs(maps) do
        local entry, rects = index.byMap[mapID], towns[position]
        if entry then
            if self.showQuestOffers then
                AddGivers(self, markers, lib, context, summaries, mapID, entry.givers, rects)
            end
            if self.showServices then
                AddServices(self, markers, lib, context, mapID, entry.services, rects)
            end
            if self.showPOIs and #entry.entrances > 0 and not HasNativeEntrances(mapID) then
                levels = levels or Instances.Read(self)
                AddEntrances(self, markers, mapID, entry.entrances, levels, rects)
            end
        end
    end
    return REFRESH_INTERVAL
end

local function BridgeProfiler(plugin)
    local profiler = Addon.Services.profiler
    if not profiler then
        return
    end
    return {
        Begin = function()
            if profiler.active then
                return profiler:Begin()
            end
        end,
        End = function(_, name, start, startKB)
            profiler:End(plugin, BRIDGE_PROFILER_PREFIX .. name, start, startKB)
        end,
        Count = function(_, name)
            if profiler.active then
                profiler:Count(plugin, name)
            end
        end,
    }
end

function Plugin:ConnectCompassQuestie()
    Bridge:SetProfiler(BridgeProfiler(self))
    Bridge.RegisterCallback(self, "QuestieIndexReady", function()
        self:InvalidateCompassSourceSettings("questie", true)
    end)
    Bridge.RegisterCallback(self, "QuestieExistenceChanged", function()
        self:InvalidateCompassMapPoints()
    end)
    Bridge.RegisterCallback(self, "QuestiePlacesFound", function()
        self:InvalidateCompassMapPoints()
    end)
    Bridge.RegisterCallback(self, "QuestieLogChanged", function()
        if self.showQuestObjectives then
            self:InvalidateCompassMapPoints()
        end
    end)
end

-- Disabling Compass gives up its demand, so the bridge pauses background work no other addon still wants.
function Plugin:DisconnectCompassQuestie()
    for _, event in ipairs(BRIDGE_EVENTS) do
        Bridge.UnregisterCallback(self, event)
    end
    Bridge.Release(self)
end
