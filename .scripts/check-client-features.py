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
 "Foundation/CompassText.lua", "Plugin/CompassDefaults.lua", "Discovery/CompassSourceUtils.lua",
 "Discovery/CompassPointVisibility.lua", "Navigation/CompassAutoAdvance.lua", "Navigation/CompassLocations.lua",
 "Navigation/CompassWaypoint.lua", "Navigation/CompassTargets.lua", "Discovery/Sources/CompassTravelSources.lua",
 "Discovery/Sources/CompassContentSources.lua", "Discovery/Sources/CompassOfferSources.lua",
 "Discovery/Sources/CompassMapSources.lua", "Discovery/Sources/CompassQuestSources.lua", "Discovery/CompassDiscovery.lua",
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


def hosted_settings(family):
    lua = host_compatibility(family)
    lua.execute('''
        Addon.Services={}
        Addon.Constants={NAVIGATION_SYSTEM_INDEX=2}
        Addon.L={PLU_COMPASS_POINTS="Points"}
        Orbit.Media={Font={OrbitSansChat="Font"}}
        Orbit.SecretValueUtils={IsSecret=function()return false end}
        Orbit.Engine.SchemaBuilder={}
        function Orbit.Engine.SchemaBuilder:SetTabRefreshCallback(dialog)
            dialog.orbitTabCallback=function()end
        end
        function Orbit.Engine.SchemaBuilder:AddSettingsTabs(schema,dialog,labels)
            local selected
            for _,label in ipairs(labels) do
                if label==dialog.orbitCurrentTab then selected=label end
            end
            dialog.orbitCurrentTab=selected or labels[1]
            if #labels>1 then schema.controls[1]={type="tabs",tabs=labels} end
            return dialog.orbitCurrentTab
        end
        Orbit.Engine.Config={}
        function Orbit.Engine.Config:Render(dialog,frame,plugin,schema)Captured=schema end
        Addon.RegisterSettingsWidgets=function()end
        function Addon.SettingsTabs(index)
            return {{label=index==2 and "Arrow" or "Appearance",controls={{key="Width",type="slider"}}},
                {label="Points",controls={{key="PointVisibility",type="points"}}}}
        end
        Plugin={resets=0}
        function Plugin:ResetCompassPointVisibility()self.resets=self.resets+1 end
        function Plugin:SetSetting()error("Settings reset must not write frame placement")end
        Addon.Controller=Plugin
    ''')
    load = lua.eval('function(code) assert(loadstring(code,"Orbit.lua"))("Orbit_Compass",Addon) end')
    load((ROOT / "Core/Integrations/Orbit/Orbit.lua").read_text(encoding="utf-8"))
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
check("Request without demand starts no walk", 'P:RequestCompassLandmarkCatalog(); assert(P.compassLandmarks.thread==nil and P.compassLandmarks.state=="idle")')
check("Stale world entry does not rebuild", 'Build(); P:ReleaseCompassLandmarkDemand("test"); mock.now=mock.now+301; P:InvalidateCompassLandmarkScope(); assert(P.compassLandmarks.state=="complete" and P.compassLandmarks.thread==nil)')
check("Pin miss drives one finished walk", 'local c=P.compassLandmarks; P:RequestCompassPinLandmarks(0,999); assert(c.thread and c.demand.pin==false and c.pinAttempted=="poi:999"); for i=1,3 do P:StepCompassLandmarkCatalog() end; assert(c.state=="complete" and c.demand.pin==nil); mock.now=mock.now+301; P:RequestCompassPinLandmarks(0,999); assert(c.thread==nil and c.demand.pin==nil and c.state=="complete")')
check("World entry pauses pin walk", 'local t=0; debugprofilestop=function() t=t+10; return t end; local c=P.compassLandmarks; P:RequestCompassPinLandmarks(0,999); P:StepCompassLandmarkCatalog(); local th=c.thread; assert(th and c.state=="building"); P:InvalidateCompassLandmarkScope(); assert(c.demand.pin==nil and c.pinAttempted==nil and P.compassLandmarkDriver.OnUpdate==nil and c.thread==th); P:RequestCompassPinLandmarks(0,999); assert(c.thread==th and P.compassLandmarkDriver.OnUpdate)')
check("Search session acquires on first scored query", 'local c=P.compassLandmarks; P:ConnectCompassSearchProvider(); local s={Invalidate=function(self) self.invalidated=true end}; mock.provider.BeginSession(s); assert(not next(c.demand)); mock.provider.Query(s,{text="a"}); assert(not next(c.demand)); mock.provider.Query(s,{text="ab"}); assert(c.demand[s]==true and c.state=="building"); mock.provider.EndSession(s); assert(not next(c.demand))')
check("Pause keeps a finished pin memoised and a paused pin resumable", '''
local c=P.compassLandmarks
P:RequestCompassPinLandmarks(0,999); for i=1,3 do P:StepCompassLandmarkCatalog() end; assert(c.state=="complete" and c.pinAttempted=="poi:999")
P:PauseCompassPinLandmarks(); assert(c.pinAttempted=="poi:999"); mock.now=mock.now+301
P:RequestCompassPinLandmarks(0,999); assert(c.thread==nil and c.demand.pin==nil)
local t=0; debugprofilestop=function() t=t+10; return t end
P:RequestCompassPinLandmarks(0,998); P:StepCompassLandmarkCatalog(); local th=c.thread
assert(th and c.state=="building" and c.demand.pin==false)
P:PauseCompassPinLandmarks()
assert(c.demand.pin==nil and c.pinAttempted==nil and P.compassLandmarkDriver.OnUpdate==nil and c.thread==th)
P:RequestCompassPinLandmarks(0,998); assert(c.thread==th and c.demand.pin==false and P.compassLandmarkDriver.OnUpdate)
''')
check("Paused pin walk resumes when the ribbon returns", '''
local c=P.compassLandmarks; local t=0; debugprofilestop=function() t=t+10; return t end
P:RequestCompassPinLandmarks(0,998); P:StepCompassLandmarkCatalog(); local th=c.thread
assert(th and c.state=="building" and c.demand.pin==false)
P.waypointDirty, P.discoveryDirty = false, false
P:PauseCompassPinLandmarks(); assert(P.waypointDirty==true and c.demand.pin==nil and c.thread==th)
local rebuilds=0; function P:RebuildCompassMarkers() rebuilds=rebuilds+1; self:RequestCompassPinLandmarks(0,998) end
P:DiscoverCompassMarkers()
assert(rebuilds>=1 and P.waypointDirty==false and c.demand.pin==false and c.thread==th and P.compassLandmarkDriver.OnUpdate)
''')
check("Incomplete pin walk is not repeated", '''
local c=P.compassLandmarks; CountWalks(); mock.noPOIs=true
P:RequestCompassPinLandmarks(0,999); Drive(10)
assert(mock.walks==1 and c.state=="pending" and c.demand.pin==nil and c.pinAttempted=="poi:999")
P:RequestCompassPinLandmarks(0,999); mock.now=mock.now+31; Drive(10)
assert(mock.walks==1 and c.demand.pin==nil)
''')
check("Pin memo survives the first root resolution", '''
local c=P.compassLandmarks; CountWalks(); mock.noPOIs=true; mock.playerMap=nil
P:RequestCompassPinLandmarks(0,999); assert(c.state=="pending" and c.rootID==nil and c.demand.pin==false)
mock.playerMap=3; mock.now=mock.now+2; Drive(10)
assert(mock.walks==1 and c.rootID==1 and c.demand.pin==nil and c.pinAttempted=="poi:999")
P:RequestCompassPinLandmarks(0,999); mock.now=mock.now+31; Drive(10)
assert(mock.walks==1 and c.demand.pin==nil)
''')
check("Failed pin walk releases demand", '''
local c=P.compassLandmarks; C_Map.GetMapChildrenInfo=function() error("native failure") end
P:RequestCompassPinLandmarks(0,999); assert(not pcall(P.StepCompassLandmarkDemand,P,0.01))
assert(c.state=="failed" and c.demand.pin==nil and c.pinAttempted=="poi:999")
''')
check("Root change and disable clear the pin memo", '''
local c=P.compassLandmarks; P:RequestCompassPinLandmarks(0,999); Drive(10)
assert(c.state=="complete" and c.pinAttempted=="poi:999")
mock.maps[3].parentMapID=20; mock.maps[20]={mapID=20,mapType=1,parentMapID=0,name="Other"}
P:InvalidateCompassLandmarkScope(); assert(c.rootID==20 and c.pinAttempted==nil)
P:RequestCompassPinLandmarks(0,999); assert(c.thread and c.pinAttempted=="poi:999")
P:StopCompassLandmarks(); assert(c.pinAttempted==nil and c.thread==nil)
''')
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

check("Losers build no text", '''
C_Map.GetMapChildrenInfo=function(root) mock.queriedRoot=root; return {mock.maps[3],mock.maps[2]} end; mock.poiIDs={77}
local fold, folds = Addon.Text.Fold, 0
Addon.Text.Fold=function(text) if text=="Landmark" then folds=folds+1 end return fold(text) end
Build(); local c=P.compassLandmarks; local r=c.entries[c.positions["poi:77"]]
assert(r and r.mapID==3 and folds==1, "folds "..folds)
''')
check("Place words are shared per place", '''
mock.poiIDs={77,78}
C_AreaPoiInfo.GetAreaPOIInfo=function(_,id) return {areaPoiID=id,name="Alpha"..id,position={x=id==77 and 0.1 or 0.9,y=0.3},atlasName="test"} end
Build(); local c=P.compassLandmarks; local a, b=c.entries[c.positions["poi:77"]], c.entries[c.positions["poi:78"]]
assert(a.mapID==3 and b.mapID==3 and rawequal(a.placeWords,b.placeWords))
local T=Addon.Text; local expected=T.Words(T.Fold("Zone Continent"))
assert(#a.placeWords==#expected); for i, word in ipairs(expected) do assert(a.placeWords[i]==word) end
for _, r in ipairs({a,b}) do
  local fresh=T.AddSearchFields({}, r.name, "Zone Continent")
  assert(r.searchText==fresh.searchText and r.search==fresh.search and #r.nameWords==#fresh.nameWords)
  for i, word in ipairs(fresh.nameWords) do assert(r.nameWords[i]==word) end
end
''')
TRACK_FREEZE = 'mock.frozen=setmetatable({},{__mode="k"}); table.freeze=function(t) mock.frozen[t]=true; return t end'
check("Map lookup finalizes only its hit", '''
mock.poiIDs={77,78}
C_AreaPoiInfo.GetAreaPOIInfo=function(_,id) return {areaPoiID=id,name="Alpha"..id,position={x=0.2,y=0.3},atlasName="test"} end
local fold, folds = Addon.Text.Fold, {}
Addon.Text.Fold=function(text) folds[text]=(folds[text] or 0)+1 return fold(text) end
local r=P:FindCompassLandmarkOnMap(3, Enum.SuperTrackingMapPinType.AreaPOI, 77)
assert(r and r.key=="poi:77" and r.searchText and r.search and r.nameWords and r.placeWords)
assert(folds.Alpha77==1 and not folds.Alpha78, "hit-only fold")
assert(mock.frozen[r] and mock.frozen[r.placeWords], "hit frozen")
''', before=TRACK_FREEZE)
check("Catalog records and place words stay frozen", '''
mock.poiIDs={77,78}
C_AreaPoiInfo.GetAreaPOIInfo=function(_,id) return {areaPoiID=id,name="Alpha"..id,position={x=id==77 and 0.1 or 0.9,y=0.3},atlasName="test"} end
Build(); local c=P.compassLandmarks; assert(#c.entries>0)
local copies={}
for _, r in ipairs(c.entries) do
  assert(mock.frozen[r] and mock.frozen[r.placeWords], r.key)
  local copy={} for i, word in ipairs(r.placeWords) do copy[i]=word end copies[r]=copy
end
local out=P:SearchCompassLandmarks("zone",{},P:NewCompassSearchScratch()); assert(#out>0)
for r, copy in pairs(copies) do
  assert(#r.placeWords==#copy); for i, word in ipairs(copy) do assert(r.placeWords[i]==word) end
end
''', before=TRACK_FREEZE)

QUERY_CORPUS = r"""
local SYL={"dor","no","gal","val","dra","kar","thal","mur","en","il","ash","storm","wind","iron","forge","hold","moon","glade","fel","wood"}
local COMMON={"Flight Master","Camp","Ruins of","The","Hold","Portal to"}
local function Word(i,w)
  local s=SYL[(i*7+w*3+math.floor(i/#SYL))%#SYL+1]..SYL[(i*13+w*5)%#SYL+1]
  if (i+w)%4==0 then s=s..SYL[(i*3+w)%#SYL+1] end
  return s:sub(1,1):upper()..s:sub(2)
end
NAMES={}
for i=1,mock.corpus do
  local parts={} if i%3==0 then parts[1]=COMMON[i%#COMMON+1] end
  for w=1,1+i%3 do parts[#parts+1]=Word(i,w) end
  NAMES[i]=table.concat(parts," ")
end
NAMES[5]="Ironforge"; NAMES[6]="\208\147\208\190\209\128\208\180\208\190\208\188"
NAMES[7]="\233\147\129\231\130\137\229\160\161"; NAMES[8]="Storm-Wind's Keep"; NAMES[9]="Moonglade Hold"
for i=10,280,30 do NAMES[i]=i%60==10 and "Twin Hold" or "Hold Twinn" end
local poi, gate, taxi=math.floor(mock.corpus*0.75), math.floor(mock.corpus*0.875), mock.corpus
mock.poiIDs={} for i=1,poi do mock.poiIDs[i]=i end
C_AreaPoiInfo.GetAreaPOIInfo=function(_,id)
  return {areaPoiID=id,name=NAMES[id],position={x=(id%97)/100,y=(id%89)/100},atlasName="test"}
end
mock.entrances={}
for i=poi+1,gate do
  mock.entrances[#mock.entrances+1]={areaPoiID=i,name=NAMES[i],position={x=(i%83)/100,y=.2},atlasName="test"}
end
C_TaxiMap.GetTaxiNodesForMap=function()
  local t={}
  for i=gate+1,taxi do t[#t+1]={nodeID=i,faction=0,name=NAMES[i],position={x=(i%79)/100,y=.4},atlasName="test"} end
  return t
end
"""
INDEX_QUERIES = ["iron", "ironforge", "irnforge", "forg", "orge", "storm wind", "wind storm", "flight master storm",
    "instance kar", "poi", "rare", "saved", "notes", "delve", "dungeon", "mgl", "zzzz", "storm-wind's", "kp",
    "mgh", "irunforge", "zone", "\u0433\u0440\u043e\u0434", "\u0433\u043e\u0440\u0431", "\u0433\u043e\u0440", "\u94c1\u7089\u5821", "camp dor", "fel wood", "ashen", "twin hold", "hold"]
INDEX_EQUIVALENCE = r"""
mock.corpus=400
""" + QUERY_CORPUS + r"""
Build(); local c=P.compassLandmarks; local index=c.queryIndex
assert(c.state=="complete" and index and index.entries==c.entries and #c.entries>300)
local function Run(q, fuzzy)
  local scratch=P:NewCompassSearchScratch(); local out=P:SearchCompassLandmarks(q,{},scratch,{fuzzy=fuzzy})
  local keys={} for i, e in ipairs(out) do keys[i]=e.key.."="..scratch.scores[e].."/"..scratch.tiers[e] end
  return table.concat(keys,","), scratch
end
for _, q in ipairs(QUERIES) do
  for _, fuzzy in ipairs({false,true}) do
    c.queryIndex=index; local indexed=Run(q,fuzzy); c.queryIndex=nil; local scanned=Run(q,fuzzy)
    assert(indexed==scanned, q.." fuzzy="..tostring(fuzzy))
  end
end
c.queryIndex=index; local _, scratch=Run("ironforge",false)
assert(#scratch.candidates>0 and #scratch.candidates<#c.entries/2)
"""


def lua_escape(text):
    return "".join(ch if ord(ch) < 128 else "".join("\\%d" % b for b in ch.encode("utf-8")) for ch in text)


def index_equivalence(family, before="", label=""):
    queries = "QUERIES={" + ",".join('"' + lua_escape(q) + '"' for q in INDEX_QUERIES) + "}\n"
    check(f"Indexed search matches a full scan ({family}{label})", queries + INDEX_EQUIVALENCE, family, before)


UNICODE_FOLD = (
    "C_Intl={FoldCase=function(text) mock.folds=(mock.folds or 0)+1;"
    " if not mock.foldNothing then return PyCaseFold(text) end end}"
)
FOLD_SAMPLE = lua_escape("\u0414\u0420\u0410\u041a\u041e\u041d \u00c9clair-Peak")
FOLD_RESULT = lua_escape("\u0434\u0440\u0430\u043a\u043e\u043d eclair peak")
index_equivalence("forever")
index_equivalence("retail")
index_equivalence("forever", UNICODE_FOLD, ", C_Intl folding")
check("C_Intl case folding precedes accent stripping", f'''
local T=Addon.Text; mock.folds=0
assert(T.Fold("{FOLD_SAMPLE}")=="{FOLD_RESULT}" and T.Fold("{lua_escape(chr(0x1E9E))}")=="ss" and mock.folds==2)
mock.foldNothing=true; assert(T.Fold("{FOLD_SAMPLE}")=="{FOLD_RESULT}" and mock.folds==3)
''', before=UNICODE_FOLD)
check("Byte tables fold case without C_Intl", f'assert(Addon.Text.Fold("{FOLD_SAMPLE}")=="{FOLD_RESULT}")', before="C_Intl=nil")
check("Completed walk publishes its query index", r"""
mock.poiIDs={77,78}; Build(); local c=P.compassLandmarks
assert(c.state=="complete" and c.queryIndex and c.queryIndex.entries==c.entries and #c.queryIndex.starts==#c.entries)
""")
check("Refresh swaps the query index with its entries", r"""
local children=C_Map.GetMapChildrenInfo; C_Map.GetMapChildrenInfo=function() return {} end
Build(); local c=P.compassLandmarks; assert(c.state=="complete" and #c.entries==0 and c.queryIndex.entries==c.entries)
C_Map.GetMapChildrenInfo=children; mock.poiIDs={77,78}; mock.now=mock.now+301
P:RequestCompassLandmarkCatalog(); assert(c.target==c and c.queryIndex==nil)
Build(); local old, entries=c.queryIndex, c.entries; assert(old.entries==entries and #entries>0)
mock.now=mock.now+301; Build()
assert(c.state=="complete" and c.entries~=entries and c.queryIndex~=old and c.queryIndex.entries==c.entries)
""")
check("Root change retires the query index", r"""
mock.poiIDs={77}; Build(); local c=P.compassLandmarks; assert(c.queryIndex); P:ReleaseCompassLandmarkDemand("test")
mock.maps[3].parentMapID=20; mock.maps[20]={mapID=20,mapType=1,parentMapID=0,name="Other"}
P:RequestCompassLandmarkCatalog(); assert(c.rootID==20 and c.queryIndex==nil)
Build(); assert(c.state=="complete" and c.queryIndex and c.queryIndex.entries==c.entries)
""")
check("Incomplete refresh keeps the published index and query-index build yields", r"""
mock.poiIDs={77}; Build(); local c=P.compassLandmarks; local old, entries=c.queryIndex, c.entries
mock.now=mock.now+301; mock.noPOIs=true; Build()
assert(c.state=="pending" and c.queryIndex==old and c.entries==entries)
P:StopCompassLandmarks(); c.entries, c.positions, c.ranks, c.queryIndex={}, {}, {}, nil; c.rootRetryAt=nil; mock.noPOIs=false
mock.corpus=200
""" + QUERY_CORPUS + r"""
local t=0; debugprofilestop=function() t=t+0.3; return t end
local build, inIndex, indexYields=P.BuildCompassLandmarkQueryIndex, false, 0
P.BuildCompassLandmarkQueryIndex=function(self, ...) inIndex=true; local q=build(self, ...); inIndex=false; return q end
P:AcquireCompassLandmarkDemand("test",false); assert(c.state=="building")
local steps=0
while c.state=="building" do
  steps=steps+1; assert(steps<1000); mock.now=mock.now+0.01; P:StepCompassLandmarkCatalog()
  if inIndex then indexYields=indexYields+1 end
  P:SearchCompassLandmarks("iron",{},P:NewCompassSearchScratch())
  assert(c.queryIndex==nil or c.queryIndex.entries==c.entries)
end
assert(c.state=="complete" and steps>5 and indexYields>0 and c.queryIndex.entries==c.entries, steps.." "..indexYields)
""")
check("First build publishes deduplicated entries with the revision", r"""
mock.corpus=200
""" + QUERY_CORPUS + r"""
local t=0; debugprofilestop=function() t=t+0.3; return t end
local c=P.compassLandmarks; P:AcquireCompassLandmarkDemand("test",false)
local steps=0
while c.state=="building" do
  local entries, revision=c.entries, c.revision
  steps=steps+1; assert(steps<1000); mock.now=mock.now+0.01; P:StepCompassLandmarkCatalog()
  assert(c.entries==entries or c.revision~=revision or c.state~="building", "unannounced publish at step "..steps)
end
assert(c.state=="complete" and steps>5 and c.queryIndex.entries==c.entries)
""")

LIVE_MARKER = ('P.markers={{key="poi:7",kind="poi",name="Alpha Spire",atlas="test",destination={mapID=3,x=.5,y=.5}}}; '
    'function Find(q) local out=P:SearchCompassLandmarks(q,{},P:NewCompassSearchScratch()); return out[1], out end; ')
check("Live marker rows reuse identity", LIVE_MARKER + 'local a=Find("alpha"); local b=Find("alpha"); assert(a and a==b and b.marker==P.markers[1] and b.zone=="Zone")')
check("Replaced marker gets a new row", LIVE_MARKER + 'local a=Find("alpha"); local old=P.markers[1]; P.markers[1]=CopyTable(old); local b=Find("alpha"); assert(a and b and a~=b and b.marker==P.markers[1] and b.marker~=old)')
check("Emptied marker list empties live rows", LIVE_MARKER + 'assert(Find("alpha")); P.markers={}; local a, out=Find("alpha"); assert(#out==0 and next(P.compassLiveMarkers.previous)==nil and next(P.compassLiveMarkers.current)==nil)')
check("Map name change rebuilds marker rows", LIVE_MARKER + 'local a=Find("alpha"); mock.maps[3].name="Renamed"; local b=Find("alpha"); assert(a and b and a~=b and a.zone=="Zone" and b.zone=="Renamed")')
check("Indexed marker skip is per query", LIVE_MARKER + 'local a=Find("alpha"); P.compassLandmarks.positions={["poi:7"]=1}; local b, out=Find("alpha"); assert(a and #out==0); P.compassLandmarks.positions={}; local c=Find("alpha"); assert(c==a)')
check("Cached marker row is choosable", LIVE_MARKER + 'Find("alpha"); local a=Find("alpha"); assert(P:ChooseCompassSearchResult(a) and mock.waypoints==1)')
check("Duplicate marker object gets two rows", LIVE_MARKER + 'P.markers[2]=P.markers[1]; local _, a=Find("alpha"); local _, b=Find("alpha"); assert(#a==2 and #b==2 and a[1]~=a[2] and b[1]~=b[2])')
check("Fuzzy pass keeps cached rows", LIVE_MARKER + '''
local scratch=P:NewCompassSearchScratch()
local a=P:SearchCompassLandmarks("alpja",{},scratch)[1]; local tier, score=scratch.tiers[a], scratch.scores[a]
local b=P:SearchCompassLandmarks("alpja",{},scratch)[1]
assert(a and a==b and tier and scratch.tiers[b]==tier and scratch.scores[b]==score)
''')

QUEST_WATCHES = ('mock.n=0; C_QuestLog.GetNumQuestWatches=function() return mock.watches or 2 end; '
    'C_QuestLog.GetQuestIDForQuestWatchIndex=function(i) return 100+i end; '
    'C_QuestLog.GetNextWaypointForMap=function() mock.n=mock.n+1; if mock.secret then return {secret=true},{secret=true} end return 0.3,0.4 end; ')
QUEST_LOAD = 'P:InvalidateCompassSource("QUEST_DATA_LOAD_RESULT"); '
check("Quest-data load reuses watched waypoints", QUEST_WATCHES + 'Drain(); assert(mock.n==2); P.discoveryClock=1; ' + QUEST_LOAD + 'Drain(); assert(mock.n==2 and #P.compassSources.quests.markers==2); P.discoveryClock=2; P:InvalidateCompassSource("QUEST_LOG_UPDATE"); Drain(); assert(mock.n==4 and #P.compassSources.quests.markers==2)')
check("Mixed quest invalidation re-queries waypoints", QUEST_WATCHES + 'Drain(); P.discoveryClock=1; ' + QUEST_LOAD + 'P:InvalidateCompassSource("QUEST_POI_UPDATE"); Drain(); assert(mock.n==4); P.discoveryClock=2; P:InvalidateCompassSource("SUPER_TRACKING_CHANGED"); ' + QUEST_LOAD + 'Drain(); assert(mock.n==6)')
check("Quest-data pass keeps the waypoint refresh deadline", QUEST_WATCHES + 'Drain(); local due=P.compassSources.quests.nextRefresh; P.discoveryClock=10; ' + QUEST_LOAD + 'Drain(); assert(mock.n==2 and P.compassSources.quests.nextRefresh==due); P.discoveryClock=31; Drain(); assert(mock.n==4)')
check("Super-tracked waypoint always re-queried", QUEST_WATCHES + 'mock.watches=1; C_SuperTrack.GetSuperTrackedQuestID=function() return 123 end; Drain(); assert(mock.n==2); P.discoveryClock=1; ' + QUEST_LOAD + 'Drain(); assert(mock.n==3 and #P.compassSources.quests.markers==2)')
check("Secret waypoint never reused", QUEST_WATCHES + 'mock.watches=1; mock.secret=true; Drain(); assert(mock.n==1 and #P.compassSources.quests.markers==0); P.discoveryClock=1; ' + QUEST_LOAD + 'Drain(); assert(mock.n==2)')
check("Settings and context changes re-query waypoints", QUEST_WATCHES + 'Drain(); P.discoveryClock=1; P:InvalidateCompassSourceSettings("quests"); ' + QUEST_LOAD + 'Drain(); assert(mock.n==4); P.discoveryClock=2; P.discoveryDirty=true; ' + QUEST_LOAD + 'Drain(); assert(mock.n==6)')

DISCOVERY_RUNTIME = r'''
P.frame={IsVisible=function() return not mock.hidden end}
P.markerClock,P.sortElapsed=0,0
function P:HideCompassPeek() end
function P:RefreshCompassBearings() end
function P:UpdateCompassAutoAdvance() end
function P:LayoutCompassArtwork() return false end
P.showHandyNotes=true
P.showTrackedContent=true
C_ContentTracking.GetCollectableSourceTrackingEnabled=function() return true end
C_ContentTracking.GetCollectableSourceTypes=function() return {0} end
C_ContentTracking.GetTrackablesOnMap=function() return 0,{} end
Drain()
mock.visits,mock.counts=0,{}
local discover=P.DiscoverCompassMarkers
P.DiscoverCompassMarkers=function(self) mock.visits=mock.visits+1; return discover(self) end
Addon.Services.profiler={active=true,Begin=function() end,
 Count=function(_,_,key) mock.counts[key]=(mock.counts[key] or 0)+1 end}
function Tick(elapsed,event)
  mock.now=mock.now+elapsed
  if event then P:InvalidateCompassSource(event) end
  P:UpdateCompass(elapsed)
end
function Completed(key) return mock.counts["Discovery/Completed/"..key] or 0 end
'''

for family in ("retail", "forever"):
    for fps in (60, 208):
        check(f"{family} path storm respects source deadlines at {fps} FPS", DISCOVERY_RUNTIME + f'''
local fps={fps}; local duration=1000/fps
for i=1,1000 do Tick(1/fps,"SUPER_TRACKING_PATH_UPDATED") end
local maximum=math.ceil(duration/Addon.Constants.DISCOVERY_MIN_INTERVAL)+1
assert(Completed("route")>0 and Completed("route")<=maximum)
assert(Completed("questPath")>0 and Completed("questPath")<=maximum)
assert(mock.visits<=maximum+math.ceil(duration/2)+5, "visits="..mock.visits)
assert(Completed("content")==0, "path events recollected content")
''', family)
        check(f"{family} missing map keeps recovery deadline at {fps} FPS", DISCOVERY_RUNTIME + f'''
P.mapWidth=nil; mock.mapReads=0
function P:RefreshCompassMap() mock.mapReads=mock.mapReads+1 end
P:DiscoverCompassMarkers(); mock.visits=0
for i=1,1000 do Tick(1/{fps},"SUPER_TRACKING_PATH_UPDATED") end
assert(mock.visits<=math.floor((1000/{fps})/Addon.Constants.DISCOVERY_INTERVAL)+1, mock.visits)
assert(mock.mapReads==mock.visits+1)
''', family)
    check(f"{family} path event schedules quest deadline outside event source list", DISCOVERY_RUNTIME + '''
P.compassSources.route.nextAllowed=100; P.compassSources.route.nextRefresh=100
P:InvalidateCompassSource("SUPER_TRACKING_PATH_UPDATED")
assert(P.discoveryNext==P.compassSources.quests.nextAllowed)
Tick(.21); assert(Completed("questPath")==1 and Completed("route")==0)
''', family)
    check(f"{family} coalesced path updates publish the latest route", DISCOVERY_RUNTIME + '''
mock.waypoint={uiMapID=3,position={x=.8,y=.8}}; mock.routeX=.2
C_Navigation.GetNextWaypointForMap=function() return mock.routeX,.3,"Route" end
Tick(.3,"SUPER_TRACKING_PATH_UPDATED")
local route=P.compassSources.route
assert(#route.markers==1 and route.markers[1].x==.2)
local before=Completed("route")
for i=1,10 do mock.routeX=.2+i*.01; Tick(.005,"SUPER_TRACKING_PATH_UPDATED") end
assert(Completed("route")==before and route.markers[1].x==.2)
Tick(.2); assert(Completed("route")==before+1 and route.markers[1].x==mock.routeX)
''', family)
    check(f"{family} disabled source events cannot wake idle discovery", DISCOVERY_RUNTIME + '''
P.showVignettes=false; P:InvalidateCompassSourceSettings("vignettes"); P:DiscoverCompassMarkers()
assert(P.compassSources.vignettes.status=="disabled")
mock.visits=0
for i=1,100 do Tick(.001,"VIGNETTES_UPDATED") end
assert(mock.visits==0, mock.visits)
''', family)
    check(f"{family} non-path event advances idle discovery", DISCOVERY_RUNTIME + '''
Tick(.3); mock.visits=0; mock.poiIDs={99}
P:InvalidateCompassSource("AREA_POIS_UPDATED")
Tick(.01)
assert(mock.visits==1 and #P.compassSources.map.markers==1)
assert(P.compassSources.map.markers[1].key=="poi:99")
''', family)
    check(f"{family} new source event preserves an earlier scheduler deadline", DISCOVERY_RUNTIME + '''
P.compassSources.route.dirty=true; P.compassSources.route.nextAllowed=.1
P.discoveryNext=.1
P:InvalidateCompassSource("AREA_POIS_UPDATED")
assert(P.discoveryNext==.1)
Tick(.11); assert(Completed("route")==1 and Completed("map")==0)
''', family)
    check(f"{family} pending HandyNotes provider wakes on availability", DISCOVERY_RUNTIME + '''
assert(P.compassSources.handynotes.reason=="provider")
assert(P.compassSources.handynotes.nextRefresh>=30)
mock.loaded.HandyNotes=true
P:InvalidateCompassSource("ORBIT_COMPASS_HANDYNOTES")
Tick(.001)
assert(mock.visits==1 and Completed("handynotes")==1)
assert(P.compassSources.handynotes.status=="ready")
''', family)
    check(f"{family} suspended discovery keeps progressing without more events", DISCOVERY_RUNTIME + '''
local passes=0
function P:CollectCompassMapPoints(markers) passes=passes+1; coroutine.yield() end
Tick(.3,"AREA_POIS_UPDATED"); assert(P.discoveryJob)
Tick(.001); assert(not P.discoveryJob and Completed("map")==1 and passes==1)
''', family)
    check(f"{family} in-flight invalidation survives completion", DISCOVERY_RUNTIME + '''
local passes=0
function P:CollectCompassMapPoints(markers)
  passes=passes+1
  if passes==1 then self:InvalidateCompassSource("AREA_POIS_UPDATED") end
end
Tick(.3,"AREA_POIS_UPDATED")
assert(passes==1 and P.compassSources.map.dirty)
Tick(.01); assert(passes==1)
Tick(.2); assert(passes==2 and not P.compassSources.map.dirty)
''', family)
    for event in ("PLAYER_ENTERING_WORLD", "settings"):
        invalidate = 'P:InvalidateCompassSourceSettings("map")' if event == "settings" else f'P:InvalidateCompassSource("{event}")'
        check(f"{family} {event} cancels suspended discovery before publication", DISCOVERY_RUNTIME + '''
local passes=0
function P:CollectCompassMapPoints(markers)
  passes=passes+1
  Addon.SourceUtils.AddMarker(self,markers,"poi:"..passes,{x=.2,y=.3},"Point","test",1,"poi")
  if passes==1 then coroutine.yield() end
end
Tick(.3,"AREA_POIS_UPDATED")
local retired=P.discoveryJob
assert(retired and #retired.source.markers==0)
''' + invalidate + '''
Tick(.001)
assert(P.discoveryJob~=retired and passes==2)
assert(#P.compassSources.map.markers==1 and P.compassSources.map.markers[1].key=="poi:2")
''', family)

check("Unsupported source events cannot wake idle discovery", DISCOVERY_RUNTIME + '''
assert(P.compassSources.tamers.status=="unsupported")
for i=1,100 do Tick(.001,"SPELLS_CHANGED") end
assert(mock.visits==0, mock.visits)
''')
check("Tracked content retains its own events and timed recovery", DISCOVERY_RUNTIME + '''
local events={"CONTENT_TRACKING_UPDATE","CONTENT_TRACKING_LIST_UPDATE","CONTENT_TRACKING_IS_ENABLED_UPDATE",
 "TRACKABLE_INFO_UPDATE","TRACKING_TARGET_INFO_UPDATE","SUPER_TRACKING_CHANGED"}
for index,event in ipairs(events) do
  Tick(.3,event)
  assert(Completed("content")==index, event)
end
local count=Completed("content")
for i=1,31 do Tick(1) end
assert(Completed("content")==count+1)
''', "retail")

for family in ("retail", "forever"):
    check(f"{family} canonical settings tabs and owned reset", r'''
        Addon.App={Apply=function()end};Addon.OrbitBridge={}
        Addon.PointsSettings=function()return {{type="compassPoints",label="Points"}} end
        function P:IsComponentDisabled(key)
            for _,value in ipairs(self:GetSetting(2,"DisabledComponents")) do if value==key then return true end end
            return false
        end
        local refreshes=0
        local tabs=Addon.SettingsTabs(2,function()refreshes=refreshes+1 end)
        assert(#tabs==3 and tabs[1].id=="layout" and tabs[2].id=="appearance" and tabs[3].id=="behaviour")
        for _,tab in ipairs(tabs) do assert(tab.scopeText==Addon.L.CFG_SETTINGS_SCOPE_LAYOUT) end
        local controls=tabs[3].controls
        P:SetSetting(1,"AutoAdvanceMode","off");P:SetSetting(1,"AutoAdvanceSameType",false)
        assert(controls[2].disabled() and not controls[2].visibleIf and controls[2].disabledReason)
        controls[1].onChange(true)
        assert(not controls[2].disabled() and refreshes==1 and not P:GetSetting(1,"AutoAdvanceSameType"))
        P:SetSetting(2,"Position",{point="CENTER",x=123,y=45})
        controls[1].onReset();assert(P:GetSetting(1,"AutoAdvanceMode")==Addon.Definition.defaults.AutoAdvanceMode)
        assert(P:GetSetting(2,"Position").x==123)
        P:SetSetting(2,"DisabledComponents",{"Name","Distance","Unrelated"})
        for _,control in ipairs(tabs[2].controls) do
            if control.label==Addon.L.CFG_CM_PREVIEW_NAME then control.onReset() end
        end
        assert(not P:IsComponentDisabled("Name") and P:IsComponentDisabled("Distance") and P:IsComponentDisabled("Unrelated"))
        P:SetSetting(2,"ComponentPositions",{Distance={x=12,overrides={DistanceUnits="meters",FontSize=23}},Name={x=54}})
        tabs[2].controls[1].onReset()
        local positions=P:GetSetting(2,"ComponentPositions")
        assert(positions.Distance.x==12 and positions.Distance.overrides.FontSize==23 and positions.Name.x==54)
        assert(not positions.Distance.overrides.DistanceUnits)
        local ribbon=Addon.SettingsTabs(1)
        assert(#ribbon==4 and ribbon[1].id=="layout" and ribbon[2].id=="appearance" and ribbon[3].id=="behaviour" and ribbon[4].id=="points")
    ''', family)

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
    *((f"{family} hosted tab reset preserves placement", hosted_settings(family), '''
        local dialog={orbitCurrentTab="Appearance"}
        Addon.OrbitBridge.RenderSettings(Plugin,dialog,{systemIndex=2})
        assert(dialog.orbitCurrentTab=="Arrow" and Captured.controls[1].type=="tabs")
        Captured.onReset()
        assert(Plugin.resets==0)
        dialog.orbitCurrentTab="Points"
        Addon.OrbitBridge.RenderSettings(Plugin,dialog,{systemIndex=1})
        assert(dialog.orbitCurrentTab=="Points" and Captured.controls[2].key=="PointVisibility")
        Captured.onReset()
        assert(Plugin.resets==1)
    ''') for family in ("retail", "forever")),
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
