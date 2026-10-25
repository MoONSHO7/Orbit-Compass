"""Shared Lua 5.1 client doubles for the Compass suites; they simulate no WoW runtime, rendering or security."""

from pathlib import Path
import re
from lupa.lua51 import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]
WORKSPACE = ROOT.parent
UI = WORKSPACE / "Orbit-Libs/LibOrbitUI/LibOrbitUI-1.0"
NAMESPACES = sorted(set(re.findall(r"\b(C_\w+)\.", "\n".join(
    p.read_text(encoding="utf-8") for p in (ROOT / "Core").rglob("*.lua")
))))
HARNESS = r'''
mock = { now = 1, calls = {}, loaded = {}, events = {}, maps = {}, prints = {}, waypoints = 0 }
local frozen, sort = setmetatable({}, { __mode = "k" }), table.sort
table.freeze = function(t) frozen[t] = true; return t end
-- The strictest client rejects sorting a read-only table before reading its length, even when it is empty.
table.sort = function(t, ...) if frozen[t] then error("attempt to modify a readonly table", 2) end return sort(t, ...) end
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
function CopyTable(t) local c = {} for k,v in pairs(t) do c[k] = type(v) == "table" and CopyTable(v) or v end return c end
function Mixin(t, ...) for i = 1, select("#", ...) do for k,v in pairs(select(i,...)) do t[k] = v end end return t end
function issecretvalue(v) return type(v) == "table" and rawget(v, "secret") == true end
function GetTime() return mock.now end
function debugprofilestop() return 0 end
function strlenutf8(s) return #s end
function UnitFactionGroup() return "Alliance" end
function UnitIsGhost() return false end
function CreateVector2D(x,y) return { x=x, y=y } end
function print(s) mock.prints[#mock.prints+1] = s end
function LibStub() return mock.search end
mock.search = { PROVIDER_CONTRACT=1, RegisterCallback=function() end, IsKindIncluded=function() return false end,
 RegisterProvider=function(_, _, provider) mock.provider=provider; return true end }
function CreateFrame()
    return { SetScript = function(self,k,v) self[k]=v end,
        RegisterEvent = function(self,event) mock.events[event]=true end,
        UnregisterAllEvents = function() wipe(mock.events) end }
end
Enum = {
 UIMapType = { Cosmic=0, World=1, Continent=2, Zone=3, Micro=5 },
 SuperTrackingMapPinType = { AreaPOI=0, QuestOffer=1, TaxiNode=2, DigSite=3, HousingPlot=4 },
 SuperTrackingType = { Quest=0, UserWaypoint=1, MapPin=2, Content=3, Vignette=4 },
 FlightPathFaction = { Neutral=0, Horde=1, Alliance=2 }, VignetteType = { Treasure=1 },
 QuestTagType = { WorldBoss=5 }, QuestWatchType = { Manual=1 },
 QuestClassification = { Normal=0, Questline=1, Recurring=2, Meta=3, Calling=4, Campaign=5,
    Legendary=6, Important=7, BonusObjective=8, Threat=9 },
}
function Namespace(name)
 return setmetatable({}, { __index = function(self,method)
   local fn = function() local key=name.."."..method; mock.calls[key]=(mock.calls[key] or 0)+1 end
   rawset(self,method,fn); return fn
 end })
end
Addon = { LibOrbitUI = { VERSION_MAJOR=1, VERSION_MINOR=8, Callbacks={ Wrap=function(fn) return fn end } },
 Services={ IsSecret=issecretvalue, IsEditMode=function() return false end },
 L=setmetatable({}, { __index=function(_,key) return key end }),
 HandyNotesClick={ Matches=function(_,a,b) return a==b end }, Controller={} }
P=Addon.Controller
function P:IsActive() return not mock.disabled end
function P:IsProfileSuppressed() return false end
function P:ClearCompassHandyNotesGuides() end
function P:RetainCompassHandyNotesGuides() end
function P:ActivateCompassHandyNotesPoint() mock.providerClicks=(mock.providerClicks or 0)+1 end
function P:RebuildCompassMarkers()
 self.markers={}
 for _, source in pairs(self.compassSources) do for _, marker in ipairs(source.markers) do self.markers[#self.markers+1]=marker end end
end
function P:RefreshCompassMap() self.mapID=3; self.mapWidth=1000; self.mapHeight=1000 end
function P:CollectCompassGatherMate() end
function P:CollectCompassHandyNotes() end
function P:SelectCompassPin(point) self.compassPinSelection=point end
function P:GetCompassTrackedPin() end
function P:FollowsCompassPin() return false end
function P:ResolveCompassPinDestination() end
function P:ProjectCompassDestination() end
function P:GetCompassFacing() return 0 end
function P:HideNavigationView() end
'''

BOUNDARIES = r'''
local empty = function() return {} end
mock.maps = { [10]={mapID=10,mapType=0,parentMapID=0,name="Cosmos"},
 [1]={mapID=1,mapType=1,parentMapID=10,name="World"},
 [2]={mapID=2,mapType=2,parentMapID=1,name="Continent"},
 [3]={mapID=3,mapType=3,parentMapID=2,name="Zone"} }
mock.playerMap=3
C_Map.GetBestMapForUnit=function() return mock.playerMap end
C_Map.GetFallbackWorldMapID=function() return mock.fallback end
C_Map.GetMapInfo=function(id) return mock.maps[id] end
C_Map.GetMapChildrenInfo=function(root) mock.queriedRoot=root; if mock.noChildren then return nil end return {mock.maps[2],mock.maps[3]} end
C_Map.GetMapWorldSize=function() return 1000,1000 end
C_Map.GetPlayerMapPosition=function() return {x=0.5,y=0.5} end
C_Map.GetWorldPosFromMapPos=function(id,p) return mock.instance or 42, {x=p.x*1000,y=p.y*1000} end
C_Map.CanSetUserWaypointOnMap=function() return true end
C_Map.IsCityMap=function() return false end
C_Map.GetMapLinksForMap=empty
C_Map.GetUserWaypoint=function() return mock.waypoint end
C_Map.SetUserWaypoint=function(p) mock.waypoints=mock.waypoints+1; mock.waypoint=p; return true end
C_Map.ClearUserWaypoint=function() mock.waypoint=nil end
UiMapPoint={CreateFromCoordinates=function(id,x,y) return {uiMapID=id,position={x=x,y=y}} end}
C_AddOns.DoesAddOnExist=function() return false end
C_AddOns.IsAddOnLoaded=function(name) return mock.loaded[name]==true end
C_EventUtils.IsEventValid=function() return true end
C_Texture.GetAtlasInfo=function(atlas) return not (mock.missingArt and mock.missingArt[atlas]) and {width=32,height=32} or nil end
C_SuperTrack.GetHighestPrioritySuperTrackingType=function() return Enum.SuperTrackingType.UserWaypoint end
C_SuperTrack.GetSuperTrackedQuestID=function() return 0 end
C_QuestLog.GetQuestsOnMap=empty
C_QuestLog.GetNumQuestLogEntries=function() return 0 end
C_QuestLog.IsWorldQuest=function() return false end
C_QuestLog.IsOnQuest=function() return true end
C_QuestLog.GetTitleForQuestID=function() return "Ordinary quest" end
C_QuestLog.IsComplete=function() return false end
C_QuestInfoSystem.GetQuestClassification=function() return Enum.QuestClassification.Normal end
C_QuestLog.GetNextWaypointForMap=function() return 0.3,0.4 end
C_AreaPoiInfo.GetEventsForMap=empty
C_AreaPoiInfo.GetDragonridingRacesForMap=empty
C_AreaPoiInfo.GetQuestHubsForMap=empty
C_AreaPoiInfo.GetDelvesForMap=empty
C_AreaPoiInfo.GetAreaPOIForMap=function() if mock.noPOIs then return nil end return mock.poiIDs or {} end
C_AreaPoiInfo.GetAreaPOIInfo=function(_,id) return {areaPoiID=id,name="Landmark",position={x=0.2,y=0.3},atlasName="test"} end
C_AreaPoiInfo.IsAreaPOITimed=function() return false end
C_EncounterJournal.GetDungeonEntrancesForMap=function() return mock.entrances or {} end
C_PetInfo.GetPetTamersForMap=empty
C_TaxiMap.GetTaxiNodesForMap=empty
C_ResearchInfo.GetDigSitesForMap=empty
C_TaskQuest.GetQuestsOnMap=empty
C_VignetteInfo.GetVignettes=empty
C_QuestLine.GetAvailableQuestLines=empty
C_QuestLine.GetForceVisibleQuests=empty
C_DeathInfo.GetGraveyardsForMap=empty
'''

FILES = [
 "Foundation/CompassClientFeatures.lua", "Foundation/CompassConstants.lua", "Foundation/CompassArtwork.lua",
 "Foundation/CompassText.lua", "Plugin/CompassDefaults.lua", "Plugin/CompassStandaloneStore.lua",
 "Discovery/CompassSourceUtils.lua",
 "Discovery/CompassPointVisibility.lua", "Navigation/CompassAutoAdvance.lua", "Navigation/CompassLocations.lua",
 "Navigation/CompassWaypoint.lua", "Navigation/CompassTargets.lua", "Discovery/Sources/CompassTravelSources.lua",
 "Discovery/Sources/CompassContentSources.lua", "Discovery/Sources/CompassOfferSources.lua",
 "Discovery/Sources/CompassMapSources.lua", "Discovery/Sources/CompassQuestSources.lua", "Discovery/CompassDiscovery.lua",
 "Integrations/CompassNavigationRoute.lua", "Integrations/Orbit/CompassResources.lua",
 "Search/CompassMapScope.lua", "Search/CompassLandmarkCatalog.lua", "Search/CompassLandmarkSearch.lua",
  "Integrations/CompassSearchProvider.lua", "Plugin/Compass.lua", "Config/CompassSettings.lua",
]


def client(family="forever", before=""):
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute(HARNESS)
    lua.globals().PyCaseFold = lambda text: text.casefold()
    lua.execute("\n".join(f'{name}=Namespace("{name}")' for name in NAMESPACES))
    lua.execute(BOUNDARIES)
    versions = {"retail": "12.1.0", "forever": "1.60.1", "unknown": "11.2.0"}
    lua.execute(f'function GetBuildInfo() return "{versions[family]}", "test", "", 16001 end')
    lua.execute(before)
    load = lua.eval('function(code, name) assert(loadstring(code,name))("Orbit_Compass",Addon) end')
    load((UI / "Core/Client.lua").read_text(encoding="utf-8"), "Client.lua")
    for file in FILES:
        load((ROOT / "Core" / file).read_text(encoding="utf-8"), file)
    load((UI / "Core/SettingsStore.lua").read_text(encoding="utf-8"), "SettingsStore.lua")
    lua.execute('''
      Addon.Store=Addon.LibOrbitUI.SettingsStore:Create(Addon.Definition.defaults,Addon.Definition.indexDefaults)
      assert(Addon.Store:Initialize())
      function P:GetSetting(i,k) return Addon.Store:Get(i,k) end
      function P:SetSetting(i,k,v) assert(Addon.Store:Set(i,k,v)) end
      P.compassLocations=Addon.Store:Collection("CompassLocations")
      P.events=CreateFrame(); P.mapID=3; P.mapWidth=1000; P.mapHeight=1000; P.markers={}
      P:InitializeCompassDiscovery(); if Addon.ClientFeatures.supported then P:CacheCompassPointVisibility() end; P:InitializeCompassLandmarks()
      function Drain() for i=1,30 do P:DiscoverCompassMarkers() end end
      function Build() P:AcquireCompassLandmarkDemand("test",true); for i=1,30 do mock.now=mock.now+0.01; P:StepCompassLandmarkCatalog() end end
      function Drive(n) for i=1,n do mock.now=mock.now+0.01; if P.compassLandmarkDriver.OnUpdate then P:StepCompassLandmarkDemand(0.01) end end end
      function CountWalks() local base=C_Map.GetMapChildrenInfo; mock.walks=0; C_Map.GetMapChildrenInfo=function(...) mock.walks=mock.walks+1; return base(...) end end
    ''')
    return lua


def load_modules(lua, modules):
    load = lua.eval('function(code, name) assert(loadstring(code, name))("Orbit_Compass", Addon) end')
    for module in modules:
        load((ROOT / "Core" / module).read_text(encoding="utf-8"), module)


# Orbit's resource-observation capability v1 as Orbit/Core/MapDisplay/Render/README.md documents it: nil while no
# leased view scans, else one immutable snapshot per revision whose session-unique record ids never repeat. Orbit's
# producer suite (map_performance `test_resource_snapshots_*`) checks the same contract against the real scanner.
ORBIT_RESOURCES = r'''
OrbitResources={nodes={},extra={},revision=1,nextID=0,live=true,reads=0,instance=42,
 copies=setmetatable({},{__mode="k"})}
local R=OrbitResources
local function Revise() R.revision=R.revision+1;R.snapshot=nil end
local function Find(id)
 for index,node in ipairs(R.nodes) do if node.id==id then return node,index end end
end
local function Copy(value)
 if type(value)~="table" then return value end
 local copy={}
 for key,field in pairs(value) do copy[key]=field end
 return copy
end
function R.Add(north,west,name,icon)
 R.nextID=R.nextID+1
 R.nodes[#R.nodes+1]={id=R.nextID,itemID=2447,name=name or "Peacebloom",icon=icon or 134414,north=north,west=west}
 Revise()
 return R.nextID
end
function R.Fill(count)
 for index=1,count do R.Add(mock.north+index,mock.west+index,"Node "..index,123) end
end
function R.Move(id,north,west) local node=Find(id);node.north,node.west=north,west;Revise() end
function R.Remove(id)
 local _,index=Find(id)
 R.nodes[index]=R.nodes[#R.nodes];R.nodes[#R.nodes]=nil;Revise()
end
function R.Clear() if #R.nodes>0 then R.nodes={};Revise() end end
function R.SetExtra(records) R.extra=records;Revise() end
function R.Snapshot()
 R.reads=R.reads+1
 if R.failure then error(R.failure,0) end
 if not R.live then return nil end
 if not R.snapshot then
  local count=#R.nodes+#R.extra
  local snapshot,copy={revision=R.revision,count=count,instance=count>0 and R.instance or nil},{}
  for index,node in ipairs(R.nodes) do
   snapshot[index]={id=node.id,itemID=node.itemID,name=node.name,icon=node.icon,north=node.north,west=node.west}
  end
  for _,record in ipairs(R.extra) do snapshot[#snapshot+1]=record end
  for index=1,count do copy[index]=Copy(snapshot[index]) end
  copy.revision,copy.count,copy.instance=snapshot.revision,snapshot.count,snapshot.instance
  R.snapshot,R.copies[snapshot]=snapshot,copy
 end
 return R.snapshot
end
function R.AssertImmutable()
 for snapshot,copy in pairs(R.copies) do
  assert(snapshot.revision==copy.revision and snapshot.count==copy.count and snapshot.instance==copy.instance,
   "consumer mutated a snapshot")
  for index=1,copy.count do
   local record,expected=snapshot[index],copy[index]
   if type(expected)=="table" then
    for key,field in pairs(expected) do assert(record[key]==field,"consumer mutated a snapshot record") end
    for key in pairs(record) do assert(expected[key]~=nil,"consumer added a snapshot record field") end
   else
    assert(record==expected,"consumer replaced a snapshot record")
   end
  end
 end
end
mock.north,mock.west=1000,2000
function UnitPosition()
 if mock.noWorldPosition then return nil end
 return mock.north,mock.west,0,R.instance
end
Addon.OrbitHost={ExternalUIHost={legacyPluginVersion=1,mapResourceObservationsVersion=1},
 MapDots={RESOURCE_LIFETIME_SECONDS=2,GetResourceSnapshot=function() return R.Snapshot() end}}
'''
