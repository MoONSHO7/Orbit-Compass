"""Boot the whole Orbit Compass TOC on Orbit's shared Lua 5.1 client double and drive it like a player.

Loads ``Orbit_Compass.toc`` in order (libraries, client policy, compatibility, localization, every Core bundle and the
``Bindings.xml`` bodies) with the real embedded LibOrbitUI and LibOrbitSearch, boots standalone on Retail 12.1.5 and
Forever 1.60.1, then drives slash commands, bindings, the ribbon, peek, search, navigation, settings, GatherMate2
and localization. It cannot certify rendering, taint, secret classification or real client events.
"""

import argparse
from pathlib import Path
import re
import sys
import unittest
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
WORKSPACE = ROOT.parent
HOST_TESTS = WORKSPACE / "Orbit/.scripts/tests"
if not (HOST_TESTS / "wow_fixture.py").is_file():
    raise SystemExit(f"check-full-boot needs Orbit's shared client double at {HOST_TESTS / 'wow_fixture.py'}")
sys.path.insert(0, str(HOST_TESTS))
# The shared double belongs to the Orbit checkout; importing it must not write a bytecode cache there.
sys.dont_write_bytecode = True

import wow_fixture  # noqa: E402

ADDON = "Orbit_Compass"
TOC = ROOT / "Orbit_Compass.toc"
BINDINGS = ROOT / "Bindings.xml"
CHUNK_PREFIX = "Interface/AddOns/Orbit_Compass/"
XML_NS = "{http://www.blizzard.com/wow/ui/}"
FAMILIES = ("retail", "forever")
# Third-party libraries come from the shared double, never from the linked checkout.
LIBRARY_DOUBLES = {"Libs/LibStub/LibStub.lua": "LibStub"}
COMMENT_LINE = re.compile(r"^\s*(--.*)?$")
HOSTED_LIBRARY = wow_fixture.ROOT / "Core/Libs/LibOrbitUI-1.0/LibOrbitUI-1.0.xml"
# Files no other Compass suite executes; --coverage reports their line share.
BOOT_ONLY_FILES = (
    "Core/CompassBoot.lua",
    "Core/Config/CompassPointHotkey.lua",
    "Core/Config/CompassPointsSettings.lua",
    "Core/Foundation/CompassFonts.lua",
    "Core/Integrations/CompassGatherMate.lua",
    "Core/Integrations/CompassIntegrations.lua",
    "Core/Integrations/Orbit/OrbitCanvas.lua",
    "Core/Navigation/CompassCommands.lua",
    "Core/Navigation/CompassNavigation.lua",
    "Core/Plugin/CompassController.lua",
    "Core/Plugin/CompassServices.lua",
    "Core/Ribbon/CompassPeek.lua",
    "Core/Ribbon/CompassProjection.lua",
    "Core/Search/CompassSearchView.lua",
    "Localization/Compass.lua",
    "Localization/Generated.lua",
)

# Narrow client doubles the shared fixture lacks. Each name and shape was checked in wow-ui-source on branches `live`
# (12.1.5.70575) and `forever` (1.60.1.70888), Blizzard_APIDocumentationGenerated unless another file is named; the two
# branches agree on every entry. They model state only and add no method a real object lacks.
CLIENT_GAPS = r'''
-- The client's error handler reports and returns; errors stay in wow.errors for assert_clean.
wow.strictErrors = false
-- MapConstants, SuperTrackManagerShared, TaxiMap, VignetteConstants and QuestConstants documentation.
Enum.UIMapType = { Cosmic = 0, World = 1, Continent = 2, Zone = 3, Dungeon = 4, Micro = 5, Orphan = 6 }
Enum.SuperTrackingMapPinType = { AreaPOI = 0, QuestOffer = 1, TaxiNode = 2, DigSite = 3, HousingPlot = 4 }
Enum.SuperTrackingType = { Quest = 0, UserWaypoint = 1, Corpse = 2, Scenario = 3, Content = 4, PartyMember = 5,
    MapPin = 6, Vignette = 7 }
Enum.FlightPathFaction = { Neutral = 0, Horde = 1, Alliance = 2 }
Enum.FlightPathState = { Current = 0, Reachable = 1, Unreachable = 2 }
Enum.VignetteType = { Normal = 0, PvPBounty = 1, Torghast = 2, Treasure = 3, FyrakkFlight = 4 }
Enum.QuestTagType = { Tag = 0, Profession = 1, Normal = 2, PvP = 3, PetBattle = 4, Bounty = 5, Dungeon = 6,
    Invasion = 7, Raid = 8, Contribution = 9, RatedReward = 10, InvasionWrapper = 11, FactionAssault = 12,
    Islands = 13, Threat = 14, CovenantCalling = 15, DragonRiderRacing = 16, Capstone = 17, WorldBoss = 18 }

-- SimpleEditBoxAPIDocumentation: GetText returns a non-nilable cstring, so an untouched box reads "".
wow.kinds.EditBox.GetText = function(self) return self.text or "" end

-- Blizzard_ChatFrameBase/Shared: SlashCommandsRegistry.lua declares the hash tables, ChatFrameSetup.lua gives
-- SlashCmdList its proxy metatable and ChatFrameUtil.ImportAllListsToHash moves handlers into hash and proxy before
-- wiping the list. ChatTypeInfo keeps the shared double's lazy metatable, so only the slash list is imported here.
setmetatable(SlashCmdList, { __index = {} })
hash_ChatTypeInfoList, hash_EmoteTokenList = {}, {}
function ChatFrameUtil.ImportAllListsToHash()
    local proxy = getmetatable(SlashCmdList).__index
    for key, handler in pairs(SlashCmdList) do
        local index, tag = 1, _G["SLASH_" .. key .. "1"]
        while tag do
            tag = strupper(tag)
            hash_SlashCmdList[tag] = handler
            hash_ChatTypeInfoList[tag] = key
            index = index + 1
            tag = _G["SLASH_" .. key .. index]
        end
        proxy[key] = handler
    end
    wipe(SlashCmdList)
end
-- ChatFrameEditBoxBaseMixin:ParseText with send == 1: import every list, then dispatch through hash_SlashCmdList.
function wow.ChatCommand(text)
    local command = strmatch(text, "^(/[^%s]+)") or ""
    local message = ""
    if command ~= text then
        message = strmatch(strsub(text, strlen(command) + 2), "^%s*(.*)$")
    end
    command = strupper(command)
    ChatFrameUtil.ImportAllListsToHash()
    local handler = hash_SlashCmdList[command]
    if handler then
        handler(strtrim(message), ChatFrame1EditBox)
        return true
    end
    return false
end

-- UnitDocumentation: UnitPosition returns posY (north), posX (west), posZ and the world instance ID. The map doubles
-- below read the same scene directly, so a case can replace UnitPosition alone.
local function RawPosition(unit)
    local player = wow.world.player
    if unit == "player" and not wow.instance.inInstance then
        return player.north, player.west, 0, player.instance
    end
end
UnitPosition = RawPosition
function GetPlayerFacing() return wow.world.player.facing end

-- MapDocumentation and MapConstantsDocumentation (C_Map), SuperTrackManagerDocumentation (C_SuperTrack). The shared
-- double's C_Map answers one fixed zone and its super-track keeps no waypoint, so both read the scene instead.
local function World() return wow.world end
local function MapRecord(mapID) return World().maps[mapID] end
local function ToMap(mapID, north, west)
    local map = MapRecord(mapID)
    return (map.left - west) / (map.left - map.right), (map.top - north) / (map.top - map.bottom)
end
local function ToWorld(mapID, x, y)
    local map = MapRecord(mapID)
    return map.top - y * (map.top - map.bottom), map.left - x * (map.left - map.right)
end
local function BestMap(instance, north, west)
    for _, mapID in ipairs(World().zoneOrder) do
        local map = MapRecord(mapID)
        local x, y = ToMap(mapID, north, west)
        if map.instance == instance and x >= 0 and x <= 1 and y >= 0 and y <= 1 then
            return mapID
        end
    end
end
local function MapInfo(mapID)
    local map = MapRecord(mapID)
    if map then
        return { mapID = mapID, name = map.name, mapType = map.mapType, parentMapID = map.parent, flags = 0 }
    end
end
local function PointCopy(point)
    if point then
        return { uiMapID = point.uiMapID, position = CreateVector2D(point.position.x, point.position.y), z = point.z }
    end
end
C_Map.GetBestMapForUnit = function(unit)
    local north, west, _, instance = RawPosition(unit)
    if north then
        return BestMap(instance, north, west)
    end
end
C_Map.GetMapInfo = MapInfo
C_Map.GetMapChildrenInfo = function(mapID, mapType, allDescendants)
    local children = {}
    for childID, map in pairs(World().maps) do
        local parent = map.parent
        while allDescendants and parent and parent ~= mapID and MapRecord(parent) do
            parent = MapRecord(parent).parent
        end
        if childID ~= mapID and parent == mapID and (mapType == nil or map.mapType == mapType) then
            children[#children + 1] = MapInfo(childID)
        end
    end
    table.sort(children, function(a, b) return a.mapID < b.mapID end)
    return children
end
C_Map.GetPlayerMapPosition = function(mapID, unit)
    local north, west, _, instance = RawPosition(unit)
    local map = MapRecord(mapID)
    if north and map and map.left and map.instance == instance then
        return CreateVector2D(ToMap(mapID, north, west))
    end
end
C_Map.GetWorldPosFromMapPos = function(mapID, position)
    local map = MapRecord(mapID)
    if map and map.left then
        return map.instance, CreateVector2D(ToWorld(mapID, position.x, position.y))
    end
end
C_Map.GetMapPosFromWorldPos = function(instance, position, overrideMapID)
    local mapID = overrideMapID or BestMap(instance, position.x, position.y)
    local map = mapID and MapRecord(mapID)
    if map and map.left and map.instance == instance then
        return mapID, CreateVector2D(ToMap(mapID, position.x, position.y))
    end
end
C_Map.GetMapWorldSize = function(mapID)
    local map = MapRecord(mapID)
    if not (map and map.left) then
        return 0, 0
    end
    return map.left - map.right, map.top - map.bottom
end
C_Map.GetMapRectOnMap = function(mapID, topMapID)
    local map, top = MapRecord(mapID), MapRecord(topMapID)
    if not (map and top and map.left and top.left) then
        return 0, 0, 0, 0
    end
    local left, upper = ToMap(topMapID, map.top, map.left)
    local right, lower = ToMap(topMapID, map.bottom, map.right)
    return left, right, upper, lower
end
C_Map.IsCityMap = function(mapID)
    local map = MapRecord(mapID)
    return map ~= nil and map.city == true
end
C_Map.CanSetUserWaypointOnMap = function(mapID)
    local map = MapRecord(mapID)
    return map ~= nil and map.mapType >= Enum.UIMapType.Zone
end
C_Map.GetUserWaypointFromHyperlink = function(hyperlink)
    local mapID, x, y = tostring(hyperlink):match("^worldmap:(%d+):(%d+):(%d+)")
    if mapID then
        return UiMapPoint.CreateFromCoordinates(tonumber(mapID), tonumber(x) / 10000, tonumber(y) / 10000)
    end
end
wow.waypointWrites = {}
C_Map.SetUserWaypoint = function(point)
    wow.userWaypoint = PointCopy(point)
    wow.waypointWrites[#wow.waypointWrites + 1] = PointCopy(point)
    wow.FireEvent("USER_WAYPOINT_UPDATED")
    return true
end
C_Map.GetUserWaypoint = function() return PointCopy(wow.userWaypoint) end
C_Map.HasUserWaypoint = function() return wow.userWaypoint ~= nil end
C_Map.ClearUserWaypoint = function()
    wow.userWaypoint = nil
    if wow.superTrack.kind == "waypoint" then
        wow.superTrack = {}
    end
    wow.FireEvent("USER_WAYPOINT_UPDATED")
end
UiMapPoint = {
    CreateFromCoordinates = function(mapID, x, y, z)
        return { uiMapID = mapID, position = CreateVector2D(x, y), z = z }
    end,
    CreateFromVector2D = function(mapID, position, z)
        return { uiMapID = mapID, position = CreateVector2D(position.x, position.y), z = z }
    end,
}
-- One super-tracked target at a time; tracking a new one replaces the previous kind, as in the client.
wow.superTrack = {}
local function Track(record)
    wow.superTrack = record
    wow.FireEvent("SUPER_TRACKING_CHANGED")
end
C_SuperTrack.SetSuperTrackedUserWaypoint = function(enabled)
    if enabled and wow.userWaypoint then
        Track({ kind = "waypoint" })
    elseif wow.superTrack.kind == "waypoint" then
        Track({})
    end
end
C_SuperTrack.IsSuperTrackingUserWaypoint = function() return wow.superTrack.kind == "waypoint" end
C_SuperTrack.SetSuperTrackedQuestID = function(questID) Track({ kind = "quest", questID = questID }) end
C_SuperTrack.GetSuperTrackedQuestID = function() return wow.superTrack.questID or 0 end
C_SuperTrack.SetSuperTrackedMapPin = function(pinType, pinID)
    Track({ kind = "pin", pinType = pinType, pinID = pinID })
end
C_SuperTrack.GetSuperTrackedMapPin = function() return wow.superTrack.pinType, wow.superTrack.pinID end
C_SuperTrack.ClearSuperTrackedMapPin = function()
    if wow.superTrack.kind == "pin" then
        Track({})
    end
end
C_SuperTrack.ClearAllSuperTracked = function() Track({}) end
C_SuperTrack.IsSuperTrackingAnything = function() return wow.superTrack.kind ~= nil end
C_SuperTrack.IsSuperTrackingQuest = function() return wow.superTrack.kind == "quest" end
C_SuperTrack.IsSuperTrackingMapPin = function() return wow.superTrack.kind == "pin" end
C_SuperTrack.GetHighestPrioritySuperTrackingType = function()
    local kind = wow.superTrack.kind
    if kind == "waypoint" then
        return Enum.SuperTrackingType.UserWaypoint
    elseif kind == "quest" then
        return Enum.SuperTrackingType.Quest
    elseif kind == "pin" then
        return Enum.SuperTrackingType.MapPin
    end
end
C_SuperTrack.GetSuperTrackedItemName = function() return "", "" end

-- AreaPoiInfoDocumentation; the shared double has no C_AreaPoiInfo namespace.
C_AreaPoiInfo = C_AreaPoiInfo or {}
C_AreaPoiInfo.GetAreaPOIForMap = function(mapID)
    local ids = {}
    for id, poi in pairs(World().pois) do
        if poi.mapID == mapID then
            ids[#ids + 1] = id
        end
    end
    table.sort(ids)
    return ids
end
C_AreaPoiInfo.GetAreaPOIInfo = function(_, areaPoiID)
    local poi = World().pois[areaPoiID]
    if poi then
        return { areaPoiID = areaPoiID, position = CreateVector2D(poi.x, poi.y), name = poi.name,
            description = poi.description, atlasName = poi.atlas, shouldGlow = false, isPrimaryMapForPOI = true,
            isAlwaysOnFlightmap = false, highlightWorldQuestsOnHover = false, highlightVignettesOnHover = false,
            isCurrentEvent = false, isSuppressible = false, isLocked = false }
    end
end
C_AreaPoiInfo.IsAreaPOITimed = function() return false, nil end
C_AreaPoiInfo.GetAreaPOISecondsLeft = function() return 0 end
for _, method in ipairs({ "GetEventsForMap", "GetDelvesForMap", "GetDragonridingRacesForMap", "GetQuestHubsForMap" }) do
    C_AreaPoiInfo[method] = function() return {} end
end
-- TaxiMapDocumentation: GetTaxiNodesForMap returns MapTaxiNodeInfo records.
C_TaxiMap = C_TaxiMap or {}
C_TaxiMap.GetTaxiNodesForMap = function(mapID)
    local nodes = {}
    for _, node in ipairs(World().taxi[mapID] or {}) do
        nodes[#nodes + 1] = { nodeID = node.nodeID, position = CreateVector2D(node.x, node.y), name = node.name,
            atlasName = "TaxiNode_Neutral", faction = Enum.FlightPathFaction.Neutral, textureKit = "",
            isUndiscovered = false }
    end
    return nodes
end
-- QuestLog, QuestLine, InGameNavigation and Minimap documentation.
C_QuestLog.GetNextWaypointForMap = function() return nil end
C_QuestLog.IsQuestFlaggedCompletedOnAccount = function() return false end
C_QuestLog.QuestIgnoresAccountCompletedFiltering = function() return false end
C_QuestLine = { RequestQuestLinesForMap = function() end, GetAvailableQuestLines = function() return {} end,
    GetForceVisibleQuests = function() return {} end, GetQuestLineInfo = function() return nil end,
    QuestLineIgnoresAccountCompletedFiltering = function() return false end }
C_Navigation = C_Navigation or {}
C_Navigation.GetNextWaypointForMap = function() return nil end
C_Minimap.IsTrackingAccountCompletedQuests = function() return false end
-- ContentTracking, DeathInfo, GossipInfo, InvasionInfo, PetInfo, ResearchInfo and VignetteInfo documentation.
C_ContentTracking.GetTrackablesOnMap = function() return 0, {} end
C_DeathInfo = C_DeathInfo or {}
C_DeathInfo.GetCorpseMapPosition = function() return nil end
C_DeathInfo.GetGraveyardsForMap = function() return {} end
C_GossipInfo.GetPoiForUiMapID = function() return nil end
C_GossipInfo.GetPoiInfo = function() return nil end
C_InvasionInfo = { GetInvasionForUiMapID = function() return nil end, GetInvasionInfo = function() return nil end }
C_PetInfo = C_PetInfo or {}
C_PetInfo.GetPetTamersForMap = function() return {} end
C_ResearchInfo = C_ResearchInfo or {}
C_ResearchInfo.GetDigSitesForMap = function() return {} end
C_VignetteInfo = C_VignetteInfo or {}
C_VignetteInfo.GetVignettes = function() return {} end
C_VignetteInfo.GetVignetteInfo = function() return nil end
C_VignetteInfo.GetVignettePosition = function() return nil end
-- IntlDocumentation: C_Intl.FoldCase(text) returns case-folded text.
C_Intl = C_Intl or {}
C_Intl.FoldCase = function(text) return wow.CaseFold(text) end
'''

# The scene: Eastern Kingdoms with Elwynn Forest and the Stormwind City map; the player stands in Elwynn facing north.
SCENE = r'''
wow.world = {
    maps = {
        [946] = { name = "Cosmic", mapType = 0, parent = 0 },
        [947] = { name = "Azeroth", mapType = 1, parent = 946 },
        [13] = { name = "Eastern Kingdoms", mapType = 2, parent = 947, instance = 0,
            left = 16000, right = -19200, top = 7466, bottom = -16000 },
        [37] = { name = "Elwynn Forest", mapType = 3, parent = 13, instance = 0,
            left = 1535, right = -1935, top = -7939, bottom = -10254 },
        [84] = { name = "Stormwind City", mapType = 3, parent = 13, instance = 0, city = true,
            left = 1722, right = -14, top = -7995, bottom = -9154 },
    },
    zoneOrder = { 84, 37, 13 },
    player = { north = -9500, west = 0, instance = 0, facing = 0 },
    pois = {
        [5001] = { mapID = 37, name = "Lion's Pride Inn", x = 0.442, y = 0.60, atlas = "poi-town" },
        [5002] = { mapID = 37, name = "Northshire Abbey", x = 0.50, y = 0.42, atlas = "poi-town" },
    },
    taxi = { [84] = { { nodeID = 2, name = "Stormwind, Elwynn", x = 0.66, y = 0.62 } } },
}
'''

# GatherMate2 is third-party and absent from the workspace: this models only the surface Compass documents in
# Core/Integrations/README.md (GetNodesForZone, DecodeLoc, GetNameForNode, IsEnabled, db_types, Visible, nodeTextures
# and the AceEvent RegisterMessage/UnregisterAllMessages pair). SendMessage drives AceEvent delivery for the suite.
GATHERMATE = r'''
wow.addons.GatherMate2 = { loaded = true, enabled = true, title = "GatherMate2", metadata = {} }
wow.addonOrder[#wow.addonOrder + 1] = "GatherMate2"
local function Encode(x, y) return math.floor(x * 10000 + 0.5) * 1000000 + math.floor(y * 10000 + 0.5) * 100 end
local receivers = {}
GatherMate2 = {
    db_types = { "Mining", "Herb Gathering" },
    Visible = { ["Herb Gathering"] = true, Mining = false },
    nodeTextures = { ["Herb Gathering"] = { [401] = 134215, [402] = 134190 } },
    names = { ["Herb Gathering"] = { [401] = "Peacebloom", [402] = "Silverleaf" }, Mining = { [201] = "Copper Vein" } },
    nodes = { [37] = { ["Herb Gathering"] = { [Encode(0.45, 0.65)] = 401 }, Mining = { [Encode(0.43, 0.66)] = 201 } } },
    Encode = Encode,
    receivers = receivers,
}
function GatherMate2:IsEnabled() return true end
function GatherMate2:GetNodesForZone(mapID, nodeType)
    return pairs(self.nodes[mapID] and self.nodes[mapID][nodeType] or {})
end
function GatherMate2:DecodeLoc(id)
    return math.floor(id / 1000000) / 10000, math.floor(id % 1000000 / 100) / 10000, id % 100
end
function GatherMate2:GetNameForNode(nodeType, nodeID) return self.names[nodeType] and self.names[nodeType][nodeID] end
function GatherMate2.RegisterMessage(receiver, message, callback)
    receivers[receiver] = receivers[receiver] or {}
    receivers[receiver][message] = callback
end
function GatherMate2.UnregisterAllMessages(receiver) receivers[receiver] = nil end
function GatherMate2:SendMessage(message, ...)
    for _, messages in pairs(receivers) do
        if messages[message] then
            messages[message](message, ...)
        end
    end
end
function GatherMate2:ReceiverCount()
    local count = 0
    for _ in pairs(receivers) do
        count = count + 1
    end
    return count
end
'''

# Player-shaped helpers evaluated in each booted runtime.
HELPERS = r'''
function Frames(count) wow.Advance(count / 60, count) end
function Command(text)
    local handled = wow.ChatCommand(text)
    Frames(3)
    return handled
end
function LastPrinted() return wow.printed[#wow.printed] end
function MarkerKeys()
    local keys = {}
    for _, marker in ipairs(OrbitCompass.markers) do
        keys[#keys + 1] = marker.key
    end
    table.sort(keys)
    return table.concat(keys, ",")
end
function ShownSlots()
    local count = 0
    for slot in OrbitCompass.markerPool:EnumerateActive() do
        if slot:IsShown() then
            count = count + 1
        end
    end
    return count
end
function VisibleWidget(kind)
    for _, frame in ipairs(wow.frames) do
        if frame.OrbitType == kind and frame:IsVisible() then
            return frame
        end
    end
end
function VisibleButton(text)
    for _, frame in ipairs(wow.frames) do
        if frame.Click and frame.GetText and frame:IsVisible() and frame:GetText() == text then
            return frame
        end
    end
end
-- The client flips a CheckButton before OnClick runs; the shared double's Click leaves the state alone.
function ClickCheck(button)
    button:SetChecked(not button:GetChecked())
    button:Click("LeftButton")
end
function Moved(point, x, y) return { point = point, relativePoint = point, x = x, y = y } end
function HoverFirst(frames)
    for _, frame in ipairs(frames) do
        if frame:GetScript("OnEnter") then
            wow.Hover(frame)
            return frame
        end
    end
end
function Waypoint()
    local point = wow.userWaypoint
    if point then
        return point.uiMapID, point.position.x, point.position.y
    end
end
function PointRowLabels(points)
    local labels = {}
    for row in points.rows:EnumerateActive() do
        labels[#labels + 1] = row.label:GetText()
    end
    table.sort(labels)
    return table.concat(labels, "|")
end
function PointCells(points, label)
    local row
    for candidate in points.rows:EnumerateActive() do
        if candidate.label:GetText() == label then
            row = candidate
        end
    end
    local cells = {}
    for _, cell in ipairs(points.cells) do
        if cell:GetParent() == row then
            cells[#cells + 1] = cell
        end
    end
    return cells
end
function OpenPointsTab()
    assert(Command("/orbitcompass"), "/orbitcompass is not registered")
    local dialog = CompassAddon.App.dialogs[1]
    dialog:SelectTab("points")
    Frames(2)
    return dialog, VisibleWidget("CompassPoints"), VisibleWidget("CompassPointHotkey")
end
function SearchRows()
    local names = {}
    for _, row in ipairs(OrbitCompass.compassSearch.rows) do
        if row:IsShown() then
            names[#names + 1] = row.name:GetText() .. "@" .. row.result.kind
        end
    end
    return table.concat(names, "|")
end
'''

# Orbit's suites read absent GlobalStrings through the shared double's fallback, which also answers every
# SLASH_<key><n> probe; Compass's claimed-command scan walks those names until nil, so hosted runs drop them.
SLASH_FALLBACK_FILTER = r'''
local fallback = getmetatable(_G).__index
setmetatable(_G, { __index = function(globals, key)
    if type(key) == "string" and key:find("^SLASH_") then
        return nil
    end
    return fallback(globals, key)
end })
'''

COVERAGE_HOOK = r'''
local prefix = ...
wow.coverage = {}
local function Hook(_, line)
    local info = debug.getinfo(2, "S")
    local source = info and info.source
    if source and source:sub(1, #prefix) == prefix then
        local hits = wow.coverage[source]
        if not hits then
            hits = {}
            wow.coverage[source] = hits
        end
        hits[line] = true
    end
end
debug.sethook(Hook, "l")
-- Lua 5.1 hooks are per thread, and discovery and catalog builds run inside coroutines.
local create, wrap = coroutine.create, coroutine.wrap
coroutine.create = function(body) return create(function(...) debug.sethook(Hook, "l") return body(...) end) end
coroutine.wrap = function(body) return wrap(function(...) debug.sethook(Hook, "l") return body(...) end) end
'''


def bundle_files(relative):
    """Return the Lua files one Compass XML bundle loads, in order, following ``<Include>``."""
    base = Path(relative).parent
    files = []
    for node in ET.parse(ROOT / relative).getroot():
        target = node.attrib.get("file")
        if not target:
            continue
        path = (base / target.replace("\\", "/")).as_posix()
        if node.tag == XML_NS + "Script":
            files.append(path)
        elif node.tag == XML_NS + "Include":
            files.extend(bundle_files(path))
    return files


def load_order():
    """Flatten ``Orbit_Compass.toc`` into Lua files; a third-party library appears as its double's name."""
    files = []
    for line in TOC.read_text(encoding="utf-8-sig").splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        path = line.replace("\\", "/")
        if path in LIBRARY_DOUBLES:
            files.append(wow_fixture.DOUBLE_PREFIX + LIBRARY_DOUBLES[path])
        elif path.endswith(".xml"):
            files.extend(bundle_files(path))
        else:
            files.append(path)
    return files


def binding_bodies():
    """Return each ``Bindings.xml`` action with its Lua body, which the client runs when the key is pressed."""
    return {node.attrib["name"]: node.text for node in ET.parse(BINDINGS).getroot()}


def load_file(lua, relative):
    """Run one real Compass file with the client's ``(addonName, addonTable)`` varargs and its addon chunk name."""
    source = (ROOT / relative).read_text(encoding="utf-8-sig")
    lua.execute(wow_fixture.bytecode(source, "@" + CHUNK_PREFIX + relative), ADDON, lua.globals().CompassAddon)


def executable_lines(relative):
    """Approximate Lua active lines as the non-blank, non-comment lines of a Compass file."""
    lines, in_block = set(), False
    for number, text in enumerate((ROOT / relative).read_text(encoding="utf-8-sig").splitlines(), 1):
        stripped = text.strip()
        if in_block:
            in_block = "]]" not in stripped
            continue
        if stripped.startswith("--[["):
            in_block = "]]" not in stripped
            continue
        if not COMMENT_LINE.match(text):
            lines.add(number)
    return lines


class Coverage:
    """Fold executed Compass lines from every runtime into one share report (``--coverage``)."""

    enabled = False
    hits = {}

    @classmethod
    def attach(cls, lua):
        if cls.enabled:
            lua.execute(wow_fixture.bytecode(COVERAGE_HOOK, "=coverage"), "@" + CHUNK_PREFIX)

    @classmethod
    def collect(cls, lua):
        if not cls.enabled:
            return
        lua.execute("debug.sethook()")
        for source, lines in dict(lua.globals().wow.coverage).items():
            relative = str(source)[len(CHUNK_PREFIX) + 1:]
            cls.hits.setdefault(relative, set()).update(int(line) for line in dict(lines))

    @classmethod
    def report(cls):
        rows, total_hit, total_lines = [], 0, 0
        product = sorted(path.relative_to(ROOT).as_posix() for folder in ("Core", "Localization")
                         for path in (ROOT / folder).rglob("*.lua"))
        for relative in product:
            executable = executable_lines(relative)
            hit = cls.hits.get(relative, set()) & executable
            total_hit, total_lines = total_hit + len(hit), total_lines + len(executable)
            if relative in BOOT_ONLY_FILES:
                share = len(hit) / len(executable) if executable else 0.0
                rows.append(f"{share:6.1%}  {len(hit):4d}/{len(executable):<4d}  {relative}")
        rows.append(f"{total_hit / total_lines:6.1%}  {total_hit:4d}/{total_lines:<4d}  Core + Localization")
        print("\nLine share (non-blank, non-comment lines):\n" + "\n".join(rows))


def new_runtime(family, locale=None, setup="", strict_globals=True):
    """A shared client double with Compass's narrow gaps and scene; ``setup`` runs last, before any addon file.

    Standalone runs use strict globals, so an absent global reads nil as in the client.
    """
    lua = wow_fixture.new_runtime(family, strict_globals=strict_globals)
    state = lua.globals().wow
    state.CaseFold = lambda text: text.casefold()
    wow_fixture.execute(lua, CLIENT_GAPS)
    wow_fixture.execute(lua, SCENE)
    if locale:
        state.locale = locale
    if setup:
        lua.execute(setup)
    Coverage.attach(lua)
    return lua


def load_compass(lua, skip_doubles=False):
    """Run the TOC closure into ``CompassAddon``, compile the binding bodies and install the suite helpers."""
    lua.execute("CompassAddon = {}")
    for entry in load_order():
        if entry.startswith(wow_fixture.DOUBLE_PREFIX):
            if not skip_doubles:
                wow_fixture.install_library_double(lua, entry[len(wow_fixture.DOUBLE_PREFIX):])
        else:
            load_file(lua, entry)
    bodies = lua.eval("{}")
    for name, body in binding_bodies().items():
        bodies[name] = lua.execute(wow_fixture.bytecode("return function() " + body + " end", "=Bindings.xml:" + name))
    lua.globals().wow.compassBindings = bodies
    wow_fixture.execute(lua, HELPERS)


def boot(family, locale=None, setup=""):
    """Load the TOC closure standalone (no Orbit), register the bindings and replay login."""
    lua = new_runtime(family, locale, setup)
    load_compass(lua)
    wow_fixture.login(lua, ADDON)
    return lua


def boot_hosted(family):
    """Boot Orbit Core with Spotlight on the same double, then Compass as its compatible external addon."""
    lua = new_runtime(family, strict_globals=False)
    wow_fixture.boot_hub(lua, wow_fixture.CORE_LAST_ENTRY)
    lua.execute(SLASH_FALLBACK_FILTER)
    # Orbit's libraries already registered LibStub; the real LibStub keeps that registry, the double would replace it.
    load_compass(lua, skip_doubles=True)
    for event, args in (("ADDON_LOADED", ("Orbit", False)), ("ADDON_LOADED", (ADDON, False)), ("PLAYER_LOGIN", ()),
                        ("PLAYER_ENTERING_WORLD", (True, False))):
        wow_fixture.fire_event(lua, event, *args)
    return lua


def printed(lua):
    return [str(line) for line in dict(lua.globals().wow.printed).values()]


class CompassCase:
    """Cases shared by both client families; subclasses set ``family``."""

    family = None

    def boot(self, booter=boot, clean=True, **options):
        """Boot and, unless ``clean`` is false (an expected failure asserts its own errors), check it afterwards."""
        lua = booter(self.family, **options)
        self.addCleanup(Coverage.collect, lua)
        if clean:
            self.addCleanup(wow_fixture.assert_clean, self, lua)
        self.lua = lua
        return lua

    def errors(self):
        return [str(message) for message in dict(self.lua.globals().wow.errors).values()]

    def eval(self, code):
        return self.lua.eval(code)

    def run_lua(self, code):
        return self.lua.execute(code)

    def frames(self, count=30):
        self.lua.globals().Frames(count)


class StandaloneCases(CompassCase):
    def test_boot_creates_standalone_surfaces(self):
        self.boot()
        self.frames()
        self.assertTrue(self.eval("OrbitCompass == CompassAddon.Controller and OrbitCompass:IsActive()"))
        self.assertTrue(self.eval("CompassAddon.App.ready and CompassAddon.App.category ~= nil"))
        self.assertIsNone(self.eval("CompassAddon.OrbitBridge"))
        self.assertEqual(self.eval("CompassAddon.ClientFeatures.family"), self.family)
        self.assertEqual(self.eval("CompassAddon.ClientFeatures.worldQuests"), self.family == "retail")
        self.assertTrue(self.eval("OrbitCompassFrame:IsShown() and not OrbitCompassNavigationFrame:IsShown()"))
        self.assertEqual(self.eval("OrbitCompassFrame:GetFrameStrata()"), "MEDIUM")
        self.assertTrue(self.eval("OrbitCompassDB ~= nil and OrbitCompass.compassLocations ~= nil"))
        self.assertEqual(self.eval("CompassAddon.Services.searchFont"), self.eval("CompassAddon.Fonts.Path.Chat"))
        self.assertIn("Assets\\Fonts\\OrbitSansCondensedUI", self.eval("CompassAddon.Fonts.Path.UI"))
        self.run_lua("ChatFrameUtil.ImportAllListsToHash()")
        for command in ("/ORBITCOMPASS", "/ORBITWAY", "/OWAY", "/WAY"):
            self.assertIsNotNone(self.eval(f"hash_SlashCmdList['{command}']"), command)
        self.assertEqual(self.eval("BINDING_HEADER_ORBIT_COMPASS"), "Compass")
        self.assertEqual(self.eval("BINDING_NAME_ORBIT_COMPASS_TARGET"), "Compass: Navigate to Point Ahead")
        self.assertEqual(self.eval("BINDING_NAME_ORBIT_COMPASS_TOGGLE_POINTS"), "Toggle compass points")
        self.assertEqual(printed(self.lua), [])

    def test_ribbon_discovers_and_renders_nearby_points(self):
        self.boot()
        self.frames()
        self.assertEqual(self.eval("OrbitCompass.mapID"), 37)
        self.assertEqual(self.eval("MarkerKeys()"), "poi:5001,poi:5002")
        self.assertEqual(self.eval("#OrbitCompass.selectedMarkers"), 2)
        self.assertEqual(self.eval("ShownSlots()"), 2)
        self.assertEqual(self.eval("math.floor(OrbitCompass.markers[1].distance + 0.5)"), 172)
        self.assertTrue(self.eval("OrbitCompass.compassSearch.icon:IsShown()"))

    def test_turning_reprojects_and_drops_points_behind(self):
        self.boot()
        self.frames()
        ahead = self.eval("OrbitCompass.markers[1].projectedX")
        self.run_lua("wow.world.player.facing = 0.05")
        self.frames(2)
        self.assertNotEqual(self.eval("OrbitCompass.markers[1].projectedX"), ahead)
        self.assertEqual(self.eval("#OrbitCompass.selectedMarkers"), 2)
        self.run_lua("wow.world.player.facing = math.pi")
        self.frames(2)
        self.assertEqual(self.eval("#OrbitCompass.selectedMarkers"), 0)
        self.assertEqual(self.eval("ShownSlots()"), 0)
        self.run_lua("wow.world.player.facing = 0")
        self.frames(10)
        self.assertEqual(self.eval("ShownSlots()"), 2)

    def test_alt_peek_skips_the_tracked_point(self):
        self.boot()
        self.frames()
        self.eval('Command("/oway nearest inn")')
        self.run_lua('wow.keys.alt = true; wow.FireEvent("MODIFIER_STATE_CHANGED", "LALT", 1); Frames(2)')
        self.assertEqual(self.eval("OrbitCompass.compassPeek.name:GetText()"), "Northshire Abbey")

    def test_reset_restores_the_ribbon_position(self):
        self.boot()
        self.frames()
        self.run_lua('OrbitCompass:SetSetting(1, "Position", Moved("TOP", 40, -100))')
        self.frames(2)
        self.assertEqual(self.eval("OrbitCompassFrame.points[1].x"), 40)
        self.assertTrue(self.eval('Command("/orbitcompass reset")'))
        self.frames(2)
        self.assertEqual(self.eval("OrbitCompassFrame.points[1].x, OrbitCompassFrame.points[1].y"), (0, -58))

    def test_alt_peek_labels_the_nearest_visible_point(self):
        self.boot()
        self.frames()
        self.run_lua('wow.keys.alt = true; wow.FireEvent("MODIFIER_STATE_CHANGED", "LALT", 1); Frames(2)')
        self.assertTrue(self.eval("OrbitCompass.compassPeek.frame:IsShown()"))
        self.assertEqual(self.eval("OrbitCompass.compassPeek.name:GetText()"), "Lion's Pride Inn")
        self.assertEqual(self.eval("OrbitCompass.compassPeek.distance:GetText()"), "172 yd")
        self.run_lua('wow.keys.alt = false; wow.FireEvent("MODIFIER_STATE_CHANGED", "LALT", 0); Frames(2)')
        self.assertFalse(self.eval("OrbitCompass.compassPeek.frame:IsShown()"))

    def test_waypoint_commands_guide_the_arrow(self):
        self.boot()
        self.frames()
        self.assertTrue(self.eval('Command("/oway")'))
        self.assertTrue(printed(self.lua)[0].startswith("Usage: /way [#mapID] x y [name]"))
        self.assertIn("/oway save <name>", printed(self.lua)[1])
        self.assertTrue(self.eval('Command("/way 50 42 Abbey road")'))
        self.assertEqual(self.eval("LastPrinted()"), "Waypoint set.")
        self.assertEqual(self.eval("Waypoint()"), (37, 0.5, 0.42))
        self.assertEqual(self.eval("wow.superTrack.kind"), "waypoint")
        self.assertTrue(self.eval("OrbitCompassNavigationFrame:IsShown()"))
        self.assertEqual(self.eval("OrbitCompass.navigationView.title:GetText()"), "Abbey road")
        self.assertEqual(self.eval("OrbitCompass.navigationView.distance:GetText()"), "622 yd")
        self.eval('Command("/way |cffffff00|Hworldmap:84:5000:5000|h[Map Pin]|h|r")')
        self.assertEqual(self.eval("Waypoint()"), (84, 0.5, 0.5))
        self.eval('Command("/orbitway #84 40 60")')
        self.assertEqual(self.eval("Waypoint()"), (84, 0.4, 0.6))
        self.eval('Command("/way garbage")')
        self.assertTrue(self.eval("LastPrinted()").startswith("Invalid location."))
        self.eval('Command("/oway clear")')
        self.assertEqual(self.eval("LastPrinted()"), "Waypoint cleared.")
        self.assertIsNone(self.eval("Waypoint()"))
        self.assertFalse(self.eval("OrbitCompassNavigationFrame:IsShown()"))

    def test_saved_location_and_point_commands(self):
        self.boot()
        self.frames()
        self.eval('Command("/oway save Home")')
        self.assertEqual(self.eval("LastPrinted()"), "Saved location: Home")
        self.eval('Command("/oway list")')
        self.assertEqual(self.eval("LastPrinted()"), "Home")
        self.eval('Command("/oway go Home")')
        self.assertEqual(self.eval("OrbitCompass.navigationView.title:GetText()"), "Home")
        self.eval('Command("/oway forget Home")')
        self.assertEqual(self.eval("LastPrinted()"), "Removed location: Home")
        self.eval('Command("/oway go Home")')
        self.assertEqual(self.eval("LastPrinted()"), self.eval("CompassAddon.L.CMD_COMPASS_NO_MATCH"))
        self.eval('Command("/oway nearest abbey")')
        self.assertEqual(self.eval("OrbitCompass.navigationView.title:GetText()"), "Northshire Abbey")
        self.eval('Command("/oway nearby")')
        self.assertEqual(self.eval("wow.menu.children[1].label"), self.eval("CompassAddon.L.PLU_COMPASS_NEARBY"))
        self.run_lua("""Entry = CompassAddon.L.PLU_COMPASS_DETAIL_F:format("Lion's Pride Inn", "172 yd")""")
        self.run_lua("wow.menu:Find(Entry).callback()")
        self.frames(3)
        self.assertEqual(self.eval("Waypoint()"), (37, 0.442, 0.6))

    def test_way_yields_to_an_addon_that_claims_it_later(self):
        self.boot()
        self.frames()
        self.run_lua("SLASH_TOMTOM_WAY1 = '/way'; SlashCmdList.TOMTOM_WAY = function(text) wow.otherWay = text end")
        self.run_lua('wow.FireEvent("ADDON_LOADED", "TomTom", false); Frames(2)')
        self.assertIsNone(self.eval("SLASH_ORBITCOMPASSWAY1"))
        self.eval('Command("/way 1 2")')
        self.assertEqual(self.eval("wow.otherWay"), "1 2")
        self.assertIsNone(self.eval("Waypoint()"))

    def test_way_stays_with_the_addon_that_claimed_it(self):
        self.boot(setup="SLASH_OTHERWAY1 = '/way'; SlashCmdList.OTHERWAY = function(text) wow.otherWay = text end")
        self.frames()
        self.eval('Command("/way 12 34")')
        self.assertEqual(self.eval("wow.otherWay"), "12 34")
        self.assertIsNone(self.eval("Waypoint()"))
        self.eval('Command("/oway 50 50")')
        self.assertEqual(self.eval("Waypoint()"), (37, 0.5, 0.5))

    def test_bindings_toggle_points_target_ahead_and_dismiss(self):
        self.boot()
        self.frames()
        self.run_lua("wow.compassBindings.ORBIT_COMPASS_TOGGLE_POINTS(); Frames(10)")
        self.assertTrue(self.eval("OrbitCompass.compassPointsToggled"))
        self.assertEqual(self.eval("MarkerKeys()"), "")
        self.run_lua("wow.compassBindings.ORBIT_COMPASS_TOGGLE_POINTS(); Frames(10)")
        self.assertEqual(self.eval("MarkerKeys()"), "poi:5001,poi:5002")
        self.run_lua("wow.compassBindings.ORBIT_COMPASS_TARGET(); Frames(3)")
        self.assertEqual(self.eval("Waypoint()"), (37, 0.442, 0.6))
        self.assertEqual(self.eval("OrbitCompass.navigationView.title:GetText()"), "Lion's Pride Inn")
        self.run_lua('OrbitCompassNavigationFrame:Click("RightButton"); Frames(3)')
        self.assertIsNone(self.eval("Waypoint()"))
        self.assertFalse(self.eval("OrbitCompassNavigationFrame:IsShown()"))

    def test_points_settings_table_and_hotkey_capture(self):
        self.boot()
        self.frames()
        self.run_lua("Dialog, Points, Hotkey = OpenPointsTab()")
        self.assertTrue(self.eval("Dialog:IsShown() and Points ~= nil and Hotkey ~= nil"))
        labels = self.eval("PointRowLabels(Points)").split("|")
        self.assertIn("Zone Points of Interest", labels)
        self.assertEqual("World Quests" in labels, self.family == "retail")
        self.assertNotIn("GatherMate2", labels)
        self.assertEqual(self.eval("#Points.cells"), len(labels) * 3)
        self.assertEqual(self.eval("Hotkey.button:GetText()"), "|cff808080Not bound|r")
        self.run_lua('SetBinding("G", "ORBIT_COMPASS_TOGGLE_POINTS"); wow.FireEvent("UPDATE_BINDINGS")')
        self.assertEqual(self.eval("Hotkey.button:GetText()"), "G")
        self.run_lua("HoverFirst(Points.children)")
        self.assertEqual(self.eval("CompassAddon.Services.tooltip.lines[1].left"), "Cities")
        self.run_lua("wow.Hover(Hotkey.button)")
        self.assertEqual(self.eval("CompassAddon.Services.tooltip.lines[2].left"),
                         self.eval("CompassAddon.L.PLU_COMPASS_POINT_HOTKEY_TT"))
        self.run_lua('wow.Hover(nil); Hotkey.button:Click("LeftButton")')
        self.assertEqual(self.eval("Hotkey.button:GetText()"), "Press a key")
        self.run_lua('wow.Key(Hotkey.button, "F")')
        self.assertEqual(self.eval("GetBindingKey('ORBIT_COMPASS_TOGGLE_POINTS')"), "F")
        self.assertEqual(self.eval("Hotkey.button:GetText()"), "F")
        self.run_lua('Hotkey.button:Click("LeftButton"); wow.Key(Hotkey.button, "ESCAPE")')
        self.assertFalse(self.eval("Hotkey.button.listening"))
        self.run_lua('Hotkey.button:Click("LeftButton"); wow.Wheel(Hotkey.button, 1)')
        self.assertEqual(self.eval("GetBindingKey('ORBIT_COMPASS_TOGGLE_POINTS')"), "MOUSEWHEELUP")
        self.run_lua('Hotkey.button:Click("RightButton")')
        self.assertIsNone(self.eval("GetBindingKey('ORBIT_COMPASS_TOGGLE_POINTS')"))
        self.run_lua('Hotkey.button:Click("LeftButton"); wow.SetCombat(true)')
        self.assertFalse(self.eval("Hotkey.button.listening"))
        self.run_lua('Hotkey.button:Click("LeftButton")')
        self.assertFalse(self.eval("Hotkey.button.listening"))
        self.run_lua("wow.SetCombat(false)")
        self.assertFalse(self.eval("Dialog:IsShown()"))
        self.run_lua("Dialog, Points, Hotkey = OpenPointsTab()")
        self.run_lua("World = PointCells(Points, CompassAddon.L.PLU_COMPASS_ZONE_POIS)[2]")
        self.run_lua("ClickCheck(World._cb); Frames(30)")
        self.assertFalse(self.eval("OrbitCompass:GetCompassPointVisibility('ShowPOIs', 'world')"))
        self.assertEqual(self.eval("MarkerKeys()"), "")
        self.run_lua("ClickCheck(World._cb); Frames(30)")
        self.assertEqual(self.eval("MarkerKeys()"), "poi:5001,poi:5002")
        self.run_lua("Dialog:Hide()")
        self.assertFalse(self.eval("Points:IsVisible() or Hotkey:IsVisible()"))

    def test_edit_mode_previews_the_arrow_and_resets_it(self):
        self.boot()
        self.frames()
        self.assertTrue(self.eval('Command("/orbitcompass move")'))
        # ShowUIPanel only shows the double's manager; the client enters Edit Mode from its OnShow.
        self.run_lua("EditModeManagerFrame:EnterEditMode(); Frames(10)")
        self.assertTrue(self.eval("CompassAddon.Services.IsEditMode()"))
        self.assertTrue(self.eval("OrbitCompassNavigationFrame:IsShown()"))
        self.assertEqual(self.eval("OrbitCompass.navigationView.title:GetText()"), "Arrow")
        self.assertFalse(self.eval("OrbitCompass.compassSearch.icon:IsShown()"))
        self.run_lua('wow.Click(CompassAddon.App.movements[2].overlay, "LeftButton"); Frames(2)')
        self.assertTrue(self.eval("CompassAddon.App.dialogs[2]:IsShown()"))
        self.run_lua('OrbitCompass:SetSetting(2, "Position", Moved("CENTER", 100, 50))')
        self.run_lua("VisibleButton(CompassAddon.L.CMN_RESET_POSITION):Click('LeftButton'); Frames(2)")
        self.assertFalse(self.eval('OrbitCompass:GetSetting(2, "Position")'))
        self.assertEqual(self.eval("OrbitCompassNavigationFrame.points[1].x"), 0)
        self.run_lua("EditModeManagerFrame:ExitEditMode(); Frames(10)")
        self.assertFalse(self.eval("OrbitCompassNavigationFrame:IsShown()"))
        self.assertFalse(self.eval("CompassAddon.App.dialogs[2]:IsShown()"))
        self.assertTrue(self.eval("OrbitCompass.compassSearch.icon:IsShown()"))

    def test_search_view_finds_tracks_and_closes(self):
        self.boot()
        self.frames()
        self.run_lua("View = OrbitCompass.compassSearch; wow.Hover(View.icon)")
        self.assertEqual(self.eval("CompassAddon.Services.tooltip.lines[1].left"), "Search landmarks")
        self.run_lua("wow.Hover(nil); wow.Click(View.icon)")
        self.assertTrue(self.eval("View.field:HasFocus()"))
        self.assertTrue(self.eval("OrbitCompass:IsCompassLandmarkCatalogBuilding()"))
        self.run_lua('View.field:Type("storm"); Frames(60)')
        self.assertFalse(self.eval("OrbitCompass:IsCompassLandmarkCatalogBuilding()"))
        self.assertEqual(self.eval("SearchRows()"), "Stormwind City@city|Stormwind, Elwynn@flightMaster")
        self.assertEqual(self.eval("View.rows[1].detail:GetText()"), "Eastern Kingdoms")
        self.run_lua('View.field:GetScript("OnTabPressed")(View.field)')
        self.assertEqual(self.eval("View.highlight"), 2)
        self.run_lua('wow.keys.shift = true; View.field:GetScript("OnTabPressed")(View.field); wow.keys.shift = false')
        self.assertEqual(self.eval("View.highlight"), 1)
        self.run_lua("wow.Hover(View.rows[2]); wow.Hover(nil)")
        self.assertEqual(self.eval("View.highlight"), 2)
        self.run_lua('View.field:GetScript("OnArrowPressed")(View.field, "UP")')
        self.assertEqual(self.eval("View.highlight"), 1)
        self.run_lua('View.field:GetScript("OnArrowPressed")(View.field, "DOWN")')
        self.assertEqual(self.eval("View.highlight"), 2)
        self.run_lua('View.field:GetScript("OnEnterPressed")(View.field); Frames(3)')
        self.assertFalse(self.eval("View.list:IsShown() or View.field:HasFocus()"))
        self.assertEqual(self.eval("View.field:GetText()"), "")
        self.assertEqual(self.eval("wow.superTrack.pinType, wow.superTrack.pinID"), (2, 2))
        self.assertEqual(self.eval("OrbitCompass.navigationView.title:GetText()"), "Stormwind, Elwynn")
        self.run_lua('wow.Click(View.icon); View.field:Type("eastern"); Frames(10); wow.Click(View.rows[1])')
        self.assertEqual(self.eval("View.field:GetText()"), "Eastern Kingdoms ")
        self.run_lua('View.field:Type("zzzqqq"); Frames(10)')
        self.assertEqual(self.eval("SearchRows()"), "")
        self.assertEqual(self.eval("View.status:GetText()"), "No landmarks found.")
        self.run_lua('View.field:Type("elwynn"); Frames(10)')
        self.assertEqual(self.eval("SearchRows()").split("|")[0], "Elwynn Forest@zone")
        self.assertIn("Northshire Abbey@poi", self.eval("SearchRows()"))
        self.run_lua('View.field:GetScript("OnEscapePressed")(View.field)')
        self.assertFalse(self.eval("View.list:IsShown() or View.field:HasFocus()"))
        self.run_lua('wow.Click(View.icon); View.field:Type("storm"); Frames(10); View.field:ClearFocus()')
        self.assertTrue(self.eval("View.list:IsShown()"))
        self.run_lua('wow.FireEvent("GLOBAL_MOUSE_DOWN", "LeftButton")')
        self.assertFalse(self.eval("View.list:IsShown()"))
        self.run_lua("wow.Click(View.icon)")
        self.assertTrue(self.eval("View.field:HasFocus()"))
        self.run_lua("wow.Click(View.icon)")
        self.assertFalse(self.eval("View.field:HasFocus() or View.list:IsShown()"))

    # Bug: CompassWaypoint.lua:122 gives a pin-less landmark artwork without sizeScale; CompassSources.lua:109-112
    # copies that nil over the marker default and CompassMarkerGroups.lua:75 then fails on every ribbon frame.
    @unittest.expectedFailure
    def test_choosing_a_city_result_keeps_the_ribbon_rendering(self):
        self.boot(clean=False)
        self.frames()
        self.run_lua('View = OrbitCompass.compassSearch; wow.Click(View.icon); View.field:Type("stormwind city")')
        self.frames(30)
        self.run_lua('View.field:GetScript("OnEnterPressed")(View.field)')
        self.frames(5)
        self.assertEqual(self.eval("Waypoint()"), (84, 0.5, 0.5))
        self.assertEqual(self.eval("OrbitCompass.navigationView.title:GetText()"), "Stormwind City")
        self.assertEqual(self.errors(), [])

    def test_instance_and_vehicle_pause_the_ribbon(self):
        self.boot()
        self.frames()
        self.run_lua('wow.instance.inInstance = true; wow.FireEvent("PLAYER_ENTERING_WORLD", false, false); Frames(3)')
        self.assertFalse(self.eval("OrbitCompassFrame:IsShown()"))
        self.assertIsNone(self.eval('OrbitCompass.events:GetScript("OnUpdate")'))
        self.assertEqual(self.eval("#OrbitCompass.markers"), 0)
        self.run_lua('wow.instance.inInstance = false; wow.FireEvent("PLAYER_ENTERING_WORLD", false, false)')
        self.frames()
        self.assertTrue(self.eval("OrbitCompassFrame:IsShown()"))
        self.assertEqual(self.eval("MarkerKeys()"), "poi:5001,poi:5002")
        self.run_lua('wow.units.player.vehicle = true; wow.FireEvent("UNIT_ENTERED_VEHICLE", "player"); Frames(3)')
        self.assertFalse(self.eval("OrbitCompassFrame:IsShown()"))
        self.run_lua('wow.units.player.vehicle = false; wow.FireEvent("UNIT_EXITED_VEHICLE", "player"); Frames(30)')
        self.assertTrue(self.eval("OrbitCompassFrame:IsShown()"))
        self.assertEqual(self.eval("ShownSlots()"), 2)

    def test_disable_releases_commands_and_enable_restores_them(self):
        self.boot()
        self.frames()
        self.assertTrue(self.eval("OrbitCompass:Disable()"))
        self.frames(3)
        self.run_lua("ChatFrameUtil.ImportAllListsToHash()")
        self.assertIsNone(self.eval("hash_SlashCmdList['/WAY']"))
        self.assertFalse(self.eval("OrbitCompassFrame:IsShown()"))
        self.assertIsNone(self.eval('OrbitCompass.events:GetScript("OnUpdate")'))
        self.eval('Command("/oway 50 50")')
        self.assertEqual(self.eval("LastPrinted()"), "Enable Compass in its settings to use the navigation arrow.")
        self.assertIsNone(self.eval("Waypoint()"))
        self.assertTrue(self.eval("OrbitCompass:Enable()"))
        self.frames()
        self.run_lua("ChatFrameUtil.ImportAllListsToHash()")
        self.assertIsNotNone(self.eval("hash_SlashCmdList['/WAY']"))
        self.assertEqual(self.eval("MarkerKeys()"), "poi:5001,poi:5002")

    def test_gathermate_records_join_the_ribbon(self):
        self.boot(setup=GATHERMATE)
        self.frames()
        herb = "gathermate:37:Herb Gathering:4500650000:401"
        self.assertEqual(self.eval("MarkerKeys()"), herb + ",poi:5001,poi:5002")
        self.assertEqual(self.eval("OrbitCompass.markers[1].sizeScale"), 0.6)
        self.assertEqual(self.eval("OrbitCompass.markers[1].description"),
                         self.eval("CompassAddon.L.PLU_COMPASS_GATHERMATE_LOCATION"))
        self.assertEqual(self.eval("GatherMate2:ReceiverCount()"), 1)
        self.run_lua("Dialog, Points = OpenPointsTab()")
        self.assertIn("GatherMate2", self.eval("PointRowLabels(Points)").split("|"))
        self.run_lua("Dialog:Hide()")
        self.run_lua("GatherMate2.nodes[37]['Herb Gathering'][GatherMate2.Encode(0.44, 0.64)] = 402")
        self.run_lua("GatherMate2:SendMessage('GatherMate2NodeAdded'); Frames(30)")
        self.assertIn("gathermate:37:Herb Gathering:4400640000:402", self.eval("MarkerKeys()"))
        self.assertTrue(self.eval("OrbitCompass:Disable()"))
        self.assertEqual(self.eval("GatherMate2:ReceiverCount()"), 0)

    def test_gathermate_loaded_after_compass_connects(self):
        self.boot()
        self.frames()
        self.run_lua(GATHERMATE)
        self.run_lua('wow.FireEvent("ADDON_LOADED", "GatherMate2", false); Frames(30)')
        self.assertEqual(self.eval("GatherMate2:ReceiverCount()"), 1)
        self.assertIn("gathermate:37:Herb Gathering:4500650000:401", self.eval("MarkerKeys()"))

    def test_secret_map_reads_are_skipped_without_faults(self):
        self.boot(setup=r'''
            local info = C_AreaPoiInfo.GetAreaPOIInfo
            C_AreaPoiInfo.GetAreaPOIInfo = function(mapID, id)
                local poi = info(mapID, id)
                if id == 5002 then poi.name = NewSecret(poi.name, "poi") end
                return poi
            end
        ''')
        self.frames()
        self.assertEqual(self.eval("MarkerKeys()"), "poi:5001")
        self.run_lua("local position = UnitPosition; UnitPosition = function(unit) "
                     "local n, w, z, i = position(unit) return NewSecret(n), NewSecret(w), z, NewSecret(i) end")
        self.frames()
        self.assertEqual(self.eval("ShownSlots()"), 1)

    def test_german_locale_localizes_commands_and_bindings(self):
        self.boot(locale="deDE")
        self.frames()
        self.assertEqual(self.eval("CompassAddon.L.PLG_NAME_COMPASS"), "Kompass")
        self.assertEqual(self.eval("BINDING_HEADER_ORBIT_COMPASS"), "Kompass")
        self.eval('Command("/oway clear")')
        self.assertEqual(self.eval("LastPrinted()"), "Wegpunkt entfernt.")
        self.eval('Command("/oway")')
        self.assertTrue(printed(self.lua)[-2].startswith("Verwendung: /way [#mapID] x y [Name]"))
        self.assertIn("/way funktioniert, wenn", printed(self.lua)[-2])
        self.eval('Command("/way 50 42")')
        self.assertEqual(self.eval("LastPrinted()"), "Wegpunkt gesetzt.")
        self.assertEqual(self.eval("OrbitCompass.navigationView.title:GetText()"), "Wegpunkt")

    def test_korean_locale_uses_the_client_font(self):
        self.boot(locale="koKR", setup="LOCALE_koKR = true")
        self.frames()
        self.assertEqual(self.eval("CompassAddon.L.PLG_NAME_COMPASS"), "나침반")
        self.assertEqual(self.eval("CompassAddon.Fonts.Path.UI"), self.eval("STANDARD_TEXT_FONT"))
        self.assertEqual(self.eval("CompassAddon.Services.searchFont"), self.eval("STANDARD_TEXT_FONT"))

    def test_regional_locales_fall_back_to_their_base_table(self):
        for locale, name in (("esMX", "Brújula"), ("enGB", "Compass")):
            with self.subTest(locale=locale):
                self.boot(locale=locale)
                self.assertEqual(self.eval("CompassAddon.L.PLG_NAME_COMPASS"), name)

    def test_incompatible_orbit_pauses_with_a_warning(self):
        self.boot(setup="Orbit = { Engine = {} }")
        self.frames()
        self.assertTrue(self.eval("CompassAddon.incompatibleOrbit"))
        self.assertEqual(printed(self.lua), [self.eval("CompassAddon.L.MSG_COMPASS_INCOMPATIBLE_ORBIT")])
        self.assertIsNone(self.eval("OrbitCompass"))
        self.assertIsNone(self.eval("CompassAddon.App"))
        self.assertIsNone(self.eval("SLASH_ORBITWAY1"))
        self.assertIsNone(self.eval("BINDING_NAME_ORBIT_COMPASS_TARGET"))
        self.assertFalse(self.eval('Command("/orbitcompass")'))

    def test_unsupported_client_prints_a_warning(self):
        self.boot(setup="C_Map.IsCityMap = nil")
        self.frames()
        self.assertFalse(self.eval("CompassAddon.ClientFeatures.supported"))
        self.assertEqual(printed(self.lua), [self.eval("CompassAddon.L.MSG_COMPASS_UNSUPPORTED_CLIENT")])
        self.assertIsNone(self.eval("OrbitCompass"))
        self.assertFalse(self.eval('Command("/orbitcompass")'))

    # Bug: CompassCommands.lua:134 registers /orbitway and /oway when only the host is checked; the dormant client
    # still clears the native waypoint. CompassController.lua:26 also requires ClientFeatures.supported.
    @unittest.expectedFailure
    def test_unsupported_client_registers_no_waypoint_command(self):
        self.boot(setup="C_Map.IsCityMap = nil")
        self.frames()
        self.assertFalse(self.eval('Command("/oway clear")'))


@unittest.skipUnless(HOSTED_LIBRARY.is_file(), "Orbit's embedded libraries are neither linked nor fetched")
class HostedCases(CompassCase):
    def test_hosted_under_orbit_core(self):
        self.boot(boot_hosted)
        self.frames()
        self.assertTrue(self.eval("CompassAddon.OrbitHost == Orbit and CompassAddon.OrbitBridge ~= nil"))
        self.assertTrue(self.eval('Orbit:GetPlugin("Orbit_Compass") == OrbitCompass and OrbitCompass:IsActive()'))
        self.assertEqual(self.eval("MarkerKeys()"), "poi:5001,poi:5002")
        self.assertTrue(self.eval("OrbitCompass:IsCompassSearchHosted()"))
        self.assertFalse(self.eval("OrbitCompass.compassSearch.icon:IsShown()"))
        self.assertEqual(self.eval('OrbitCompass:GetCanvasPreviewText("Name")'), "Arrow")
        self.assertEqual(self.eval('OrbitCompass:GetCanvasPreviewText("Distance")'), "120 yd")
        self.run_lua("Preview = OrbitCompassNavigationFrame:CreateCanvasPreview({ parent = UIParent })")
        self.assertEqual(self.eval("Preview.components.Name.visual:GetText()"), "Arrow")
        self.assertEqual(self.eval("Orbit.Engine.CanvasMode.SettingsSchema.COMPONENT_TITLES.Distance"), "Distance")
        self.run_lua('Distance = Preview.components.Distance')
        self.run_lua('Distance.ApplyCustomOverride(Distance, "DistanceUnits", "meters")')
        self.assertEqual(self.eval("Distance.visual:GetText()"), "110 m")
        self.run_lua("OrbitCompass:OnCanvasLivePreview()")
        self.eval('Command("/way 50 42 Abbey")')
        self.assertEqual(self.eval("OrbitCompass.navigationView.title:GetText()"), "Abbey")


def family_cases(base, prefix):
    for family in FAMILIES:
        name = prefix + family.capitalize()
        globals()[name] = type(name, (base, unittest.TestCase), {"family": family})


family_cases(StandaloneCases, "Standalone")
family_cases(HostedCases, "Hosted")


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--coverage", action="store_true", help="report line shares for the Compass product files")
    args, rest = parser.parse_known_args()
    Coverage.enabled = args.coverage
    program = unittest.main(argv=[sys.argv[0], *rest], exit=False)
    if args.coverage:
        Coverage.report()
    return 0 if program.result.wasSuccessful() else 1


if __name__ == "__main__":
    raise SystemExit(main())
