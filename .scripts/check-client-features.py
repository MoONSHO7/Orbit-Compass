"""Exercise Compass client policy and native boundaries with Lua 5.1 doubles; not a WoW runtime test."""

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
table.freeze = function(t) return t end
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
 "Foundation/CompassText.lua", "Plugin/CompassDefaults.lua", "Discovery/CompassSourceUtils.lua",
 "Discovery/CompassPointVisibility.lua", "Navigation/CompassAutoAdvance.lua", "Navigation/CompassLocations.lua",
 "Navigation/CompassWaypoint.lua", "Navigation/CompassTargets.lua", "Discovery/Sources/CompassTravelSources.lua",
 "Discovery/Sources/CompassContentSources.lua", "Discovery/Sources/CompassOfferSources.lua",
 "Discovery/Sources/CompassMapSources.lua", "Discovery/Sources/CompassQuestSources.lua", "Discovery/CompassDiscovery.lua",
 "Search/CompassMapScope.lua", "Search/CompassLandmarkCatalog.lua", "Search/CompassLandmarkSearch.lua",
]


def client(family="forever", before=""):
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute(HARNESS)
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
      function Build() P:RequestCompassLandmarkCatalog(); for i=1,30 do mock.now=mock.now+0.01; P:StepCompassLandmarkCatalog() end end
    ''')
    return lua


tests = []


def check(name, code, family="forever", before=""):
    tests.append((name, code, family, before))


def host_compatibility(family="forever", legacy_version=1, existing=False):
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute(f'''
        Addon={{ClientFeatures={{family="{family}",supported=true}}}}
        Orbit={{
            Engine={{}},
            ExternalUIHost={{legacyPluginVersion={legacy_version}}},
            GetPlugin=function() return {"{}" if existing else "nil"} end,
        }}
    ''')
    load = lua.eval('function(code) assert(loadstring(code,"CompassCompatibility.lua"))("Orbit_Compass",Addon) end')
    load((ROOT / "Core/CompassCompatibility.lua").read_text(encoding="utf-8"))
    return lua


check("Forever withheld features", 'local F=Addon.ClientFeatures; assert(F.supported and not F.worldQuests and not F.races and not F.delves and not F.content and not F.petTamers and not F.digSites)')
check("Hosted clients declared", 'assert(Addon.Definition.supportedClients.retail and Addon.Definition.supportedClients.forever)')
check("Retail features preserved", 'local F=Addon.ClientFeatures; assert(F.supported and F.worldQuests and F.races and F.delves and F.content and F.petTamers and F.digSites)', "retail")
check("Unknown family dormant", 'assert(not Addon.ClientFeatures.supported and not Addon.ClientFeatures.AllowsPoint("ShowWaypoint"))', "unknown")
check("Missing optional namespace", 'assert(not Addon.ClientFeatures.petTamers and not Addon.ClientFeatures.digSites)', "retail", 'C_PetInfo=nil; C_ResearchInfo=nil')
check("Missing optional pin enum loads", 'assert(Addon.Constants.PIN_KEY_PREFIXES[2])', before='Enum.SuperTrackingMapPinType.HousingPlot=nil; Enum.SuperTrackingMapPinType.DigSite=nil; Enum.QuestClassification.Calling=nil')
check("Stored preferences retained", 'assert(P:GetSetting(1,"ShowWorldQuests")==true and P.showWorldQuests==false); P:SetCompassPointVisibility("ShowWorldQuests","toggle",true); P:CacheCompassPointVisibility(); P:ToggleCompassPoints(); assert(P.showWorldQuests==false and P:GetCompassPointVisibility("ShowWorldQuests","toggle")==true)')
check("Forever event filtering", 'P:RegisterCompassDiscoveryEvents(); assert(mock.events.QUEST_LOG_UPDATE and not mock.events.CONTENT_TRACKING_UPDATE and not mock.events.RESEARCH_ARTIFACT_DIG_SITE_UPDATED and not mock.events.WORLD_QUEST_COMPLETED_BY_SPELL)')
check("Retail event preservation", 'P:RegisterCompassDiscoveryEvents(); assert(mock.events.CONTENT_TRACKING_UPDATE and mock.events.WORLD_QUEST_COMPLETED_BY_SPELL)', "retail")
check("Forever root", 'Build(); assert(mock.queriedRoot==1 and P.compassLandmarks.state=="complete")')
check("Retail root", 'Build(); assert(mock.queriedRoot==10)', "retail")
check("Fallback seed", 'mock.playerMap=nil; mock.fallback=3; Build(); assert(mock.queriedRoot==1)')
check("Unknown root pending", 'mock.playerMap=nil; Build(); assert(P.compassLandmarks.state=="pending" and mock.queriedRoot==nil)')
check("Pending root recovers", 'mock.playerMap=nil; Build(); mock.playerMap=3; mock.now=mock.now+2; Build(); assert(P.compassLandmarks.state=="complete")')
check("Cyclic ancestry rejected", 'mock.maps[1].parentMapID=2; assert(Addon.MapScope.Resolve(1)==nil)')
check("Empty child data is pending", 'mock.noChildren=true; Build(); assert(P.compassLandmarks.state=="pending")')
check("Root change retires previous index", 'Build(); local old=P.compassLandmarks.entries; mock.maps[3].parentMapID=20; mock.maps[20]={mapID=20,mapType=1,parentMapID=0,name="Other"}; Build(); assert(P.compassLandmarks.rootID==20 and P.compassLandmarks.entries~=old)')
check("Unverified queries never run", 'local fail=function() error("withheld query called") end; C_TaskQuest.GetQuestsOnMap=fail; C_PetInfo.GetPetTamersForMap=fail; C_ResearchInfo.GetDigSitesForMap=fail; C_AreaPoiInfo.GetDelvesForMap=fail; C_AreaPoiInfo.GetDragonridingRacesForMap=fail; C_ContentTracking.GetCollectableSourceTrackingEnabled=fail; Drain(); Build()')
check("Ordinary quests survive", 'C_QuestLog.GetNumQuestWatches=function() return 1 end; C_QuestLog.GetQuestIDForQuestWatchIndex=function() return 123 end; Drain(); assert(#P.compassSources.quests.markers==1)', before='')
check("Dungeon entrance without journal", 'mock.entrances={{areaPoiID=456,journalInstanceID=10,name="Entrance",position={x=0.1,y=0.2},atlasName="test"}}; Build(); local i=P.compassLandmarks.positions["poi:456"]; assert(i and P.compassLandmarks.entries[i].kind=="instance")')
check("Ready empty differs from unsupported", 'Drain(); assert(P.compassSources.map.status=="ready" and P.compassSources.tamers.status=="unsupported" and P.compassSources.gathermate.status=="pending")')
check("Checkbox clears owned markers", 'mock.poiIDs={99}; Drain(); assert(#P.compassSources.map.markers==1); P:SetSetting(1,"ShowPOIs",false); P:CacheCompassPointVisibility(); Drain(); assert(#P.compassSources.map.markers==0)')
check("Incomplete source keeps snapshot", 'mock.poiIDs={99}; Drain(); mock.noPOIs=true; P.compassSources.map.dirty=true; P.discoveryClock=1; Drain(); assert(P.compassSources.map.status=="pending" and #P.compassSources.map.markers==1)')
check("Missing native atlas has bundled fallback", 'mock.missingArt={bad=true,[Addon.Constants.FALLBACK_ATLAS]=true}; local r={SetTexCoord=function() end,SetTexture=function(self,t) self.texture=t; return true end, SetAtlas=function() error("missing atlas") end}; Addon.Artwork.Apply(r,"bad"); assert(r.texture:find("orbit%-compass%-arrow.tga"))')
check("Invalid provider texture falls back", 'local r={SetTexture=function() return false end, SetAtlas=function(self,a) self.atlas=a end}; Addon.Artwork.ApplyTexture(r,"missing"); assert(r.atlas==Addon.Constants.FALLBACK_ATLAS)')
check("Location provenance saved", 'assert(P:SaveCompassLocation("Home")); local r=P.compassLocations:Get("forever:home"); assert(r.clientFamily=="forever" and r.destinationVersion==1 and r.worldInstance==42 and P:IsCompassLocationUsable(r))')
check("Foreign map ID rejected", 'local r={id="retail:home",name="Home",mapID=3,x=.5,y=.5,clientFamily="retail",destinationVersion=1}; P.compassLocations:Insert(r); assert(not P:IsCompassLocationUsable(r)); local out=P:SearchCompassLandmarks("home",{},P:NewCompassSearchScratch()); assert(#out==0)')
check("Legacy records retained unclassified", 'local r={id="home",name="Home",mapID=3,x=.5,y=.5}; P.compassLocations:Insert(r); assert(not P:IsCompassLocationUsable(r)); P:SaveCompassLocation("Home"); assert(P.compassLocations:Get("home")==r and r.clientFamily==nil and P.compassLocations:Get("forever:home"))')
check("Same names coexist across clients", 'P.compassLocations:Insert({id="retail:home",name="Home",mapID=3,x=.1,y=.1,clientFamily="retail",destinationVersion=1}); P:SaveCompassLocation("Home"); assert(P.compassLocations:Get("retail:home") and P.compassLocations:Get("forever:home"))')
check("Changed world identity rejected", 'P:SaveCompassLocation("Home"); mock.instance=43; assert(not P:IsCompassLocationUsable(P.compassLocations:Get("forever:home")))')
check("Saved search action succeeds", 'P:SaveCompassLocation("Home"); local out=P:SearchCompassLandmarks("home",{},P:NewCompassSearchScratch()); assert(#out==1 and P:ChooseCompassSearchResult(out[1]) and mock.waypoints==1)')
check("Deleted search destination refused", 'P:SaveCompassLocation("Home"); local out=P:SearchCompassLandmarks("home",{},P:NewCompassSearchScratch()); P.compassLocations:Remove("forever:home"); assert(not P:ChooseCompassSearchResult(out[1]) and mock.waypoints==0)')
check("Retired catalog result refused", 'Build(); local old=P.compassLandmarks.entries[1]; P.compassLandmarks.positions={}; assert(not P:ChooseCompassSearchResult(old) and mock.waypoints==0)')
check("Disabled action refused", 'mock.disabled=true; assert(not P:SetWaypoint(3,.5,.5) and mock.waypoints==0)')
check("Unsupported result cannot bypass Points", 'assert(not P:ChooseCompassSearchResult({kind="delve",mapID=3,x=.5,y=.5}) and mock.waypoints==0)')
check("Disable releases search demand", 'P:AcquireCompassLandmarkDemand("external",true); P:StopCompassLandmarks(); assert(next(P.compassLandmarks.demand)==nil and P.compassLandmarkDriver.OnUpdate==nil and P.compassLandmarks.thread==nil)')
check("Saved collection survives store roundtrip", 'P:SaveCompassLocation("Home"); local data=CopyTable(Addon.Store.data); local other=Addon.LibOrbitUI.SettingsStore:Create(Addon.Definition.defaults,Addon.Definition.indexDefaults); assert(other:Initialize(data)); assert(other:Collection("CompassLocations"):Get("forever:home").clientFamily=="forever")')

check("Points reset retains hidden Retail choices", 'P:SetSetting(1,"ShowWorldQuests",false); P:SetCompassPointVisibility("ShowWorldQuests","city",true); P:ResetCompassPointVisibility(); assert(P:GetSetting(1,"ShowWorldQuests")==false and P:GetSetting(1,"PointVisibility").ShowWorldQuests.city==true)')
check("Missing quest classification disables only quests", 'assert(Addon.ClientFeatures.supported and not Addon.ClientFeatures.quests and not Addon.ClientFeatures.offers); Drain(); Build()', before='C_QuestInfoSystem=nil')
check("Ordinary quests survive missing task API", 'assert(Addon.ClientFeatures.quests); Drain(); Build()', before='C_TaskQuest=nil')
check("Missing base map API refuses startup contract", 'assert(not Addon.ClientFeatures.supported)', before='C_Map.GetMapInfo=false')
check("Partial map data retains dungeon entrances", 'mock.noPOIs=true; mock.entrances={{areaPoiID=456,name="Entrance",position={x=.1,y=.2},atlasName="test"}}; Drain(); assert(P.compassSources.map.status=="pending" and #P.compassSources.map.markers==1); Build(); assert(P.compassLandmarks.positions["poi:456"] and P.compassLandmarks.state=="pending"); mock.noPOIs=false; mock.now=mock.now+31; Build(); assert(P.compassLandmarks.state=="complete")')
check("Idle world entry does not start Search", 'P:InvalidateCompassLandmarkScope(); assert(P.compassLandmarks.state=="idle" and P.compassLandmarks.thread==nil)')
check("Nested quest task cannot bypass through Search", 'C_QuestInfoSystem.GetQuestClassification=function() return Enum.QuestClassification.BonusObjective end; assert(not Addon.SourceUtils.AllowsQuest(123)); assert(not P:TrackCompassLandmark({kind="quest",questID=123,mapID=3,x=.5,y=.5}) and mock.waypoints==0)')
check("Disabled native tracking action refused", 'mock.disabled=true; C_SuperTrack.SetSuperTrackedMapPin=function() error("disabled native action") end; assert(not P:TrackCompassLandmark({kind="poi",pinType=0,id=99,mapID=3,x=.5,y=.5}))')
check("Disabled demand cannot restart Search", 'mock.disabled=true; P:AcquireCompassLandmarkDemand("late",true); P:RequestCompassLandmarkCatalog(); assert(P.compassLandmarks.thread==nil and not next(P.compassLandmarks.demand))')
check("Only completed collector assigns marker ownership", 'mock.poiIDs={99}; Drain(); assert(P.compassSources.map.markers[1].source=="map"); P.discoveryJob={definition={key="taxi"}}; local markers={}; Addon.SourceUtils.AddMarker(P,markers,"waypoint",{x=.5,y=.5},"Point","test",1,"waypoint"); assert(markers[1].source==nil)')
check("Withheld native query references remain dormant", 'Drain(); Build()', before='local fail=function() error("withheld native query") end; C_AreaPoiInfo.GetDelvesForMap=fail; C_AreaPoiInfo.GetDragonridingRacesForMap=fail; C_PetInfo.GetPetTamersForMap=fail; C_ResearchInfo.GetDigSitesForMap=fail; C_TaskQuest.GetQuestsOnMap=fail; C_ContentTracking.GetCollectableSourceTrackingEnabled=fail')
check("Retired live marker refused", 'local marker={key="poi:old",kind="poi",destination={mapID=3,x=.5,y=.5}}; assert(not P:ChooseCompassSearchResult({marker=marker,kind="poi"}) and mock.waypoints==0)')
check("Source re-enable schedules fresh observation", 'P:SetSetting(1,"ShowPOIs",false); P:SetSetting(1,"ShowEvents",false); P:SetSetting(1,"ShowQuestHubs",false); P:CacheCompassPointVisibility(); Drain(); assert(P.compassSources.map.status=="disabled"); P:SetSetting(1,"ShowPOIs",true); P:CacheCompassPointVisibility(); mock.poiIDs={99}; Drain(); assert(P.compassSources.map.status=="ready" and #P.compassSources.map.markers==1)')
check("Pending source cannot advance by removal", '''
Drain(); P.autoAdvanceMode="removal"; P.bearingPlayerX=.5; P.bearingPlayerY=.5; P.range=1000;
P.navigationKey="waypoint"; P.waypointDirty=false;
P.waypointLabel={sourceKey="poi:99"};
P.markers={{key="poi:99",kind="poi",source="map"}};
P:UpdateCompassAutoAdvance(); assert(P.compassAutoAdvance);
P.markers={}; P.compassSources.map.status="pending";
P.discoveryClock=10; P:UpdateCompassAutoAdvance(); assert(P.compassAutoAdvance and not P.compassAutoAdvance.missingSince);
P.compassSources.map.status="ready"; P.discoveryClock=11; P:UpdateCompassAutoAdvance();
assert(P.compassAutoAdvance.missingSince==11);
P.discoveryClock=13; P:UpdateCompassAutoAdvance(); assert(not P.compassAutoAdvance)
''')

failures = []
for name, code, family, before in tests:
    try:
        client(family, before).execute(code)
    except Exception as error:
        failures.append(name)
        print(f"FAIL {name}: {error}")
host_scenarios = (
    ("Forever host accepted", host_compatibility(), "assert(Addon.OrbitHost==Orbit and not Addon.incompatibleOrbit)"),
    ("Retail host accepted", host_compatibility("retail"), "assert(Addon.OrbitHost==Orbit and not Addon.incompatibleOrbit)"),
    ("Old host rejected", host_compatibility(legacy_version=0), "assert(Addon.incompatibleOrbit and not Addon.OrbitHost)"),
    ("Existing Compass rejected", host_compatibility(existing=True), "assert(Addon.incompatibleOrbit and not Addon.OrbitHost)"),
)
for name, lua, code in host_scenarios:
    try:
        lua.execute(code)
    except Exception as error:
        failures.append(name)
        print(f"FAIL {name}: {error}")
total = len(tests) + len(host_scenarios)
print(f"{total-len(failures)}/{total} Compass client boundary scenarios passed")
raise SystemExit(bool(failures))
