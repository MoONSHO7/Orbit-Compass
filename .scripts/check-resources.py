"""Check Compass live resources against Orbit's documented capability double in Lua 5.1; not native profiling."""

from compass_harness import ORBIT_RESOURCES, ROOT, UI, client, load_modules

LIVE = ORBIT_RESOURCES + r'''
mock.visible=true
function GetPlayerFacing()return 0 end
P.frame={IsVisible=function()return mock.visible end,Hide=function()mock.visible=false end,
 Show=function()mock.visible=true end}
P.navigationFrame={Hide=function()end}
P.events.RegisterUnitEvent=function()end
P.range,P.bearings,P.markerSlots,P.sortElapsed,P.markerClock=1000,{},{},0,0
mock.renders,mock.renderedResources,mock.rebuilds=0,0,0
local rebuild=P.RebuildCompassMarkers
function P:RebuildCompassMarkers()
 mock.rebuilds=mock.rebuilds+1
 rebuild(self)
 self.bearingsDirty=true
end
function P:HideCompassPeek()end
function P:PauseCompassPinLandmarks()end
function P:UpdateCompassAutoAdvance()end
function P:LayoutCompassArtwork()return true end
function P:RenderCompass()
 mock.renders,mock.renderedResources=mock.renders+1,0
 for _,marker in ipairs(self.bearings)do
  if marker.displayOnly then mock.renderedResources=mock.renderedResources+1 end
 end
 self.renderDirty,self.renderFacing,self.renderInteractive=false,0,true
end
function Tick(seconds)
 mock.now=mock.now+seconds
 P:UpdateCompass(seconds)
end
function Advance(seconds,fps)
 for i=1,math.floor(seconds*fps+0.5)do Tick(1/fps)end
end
function Resources()
 local state=P.compassDisplaySources.resources
 return state and state.markers or {}
end
function FinishDiscovery()
 for i=1,40 do P:DiscoverCompassMarkers()end
 assert(not P.discoveryJob)
end
function IdleSources()
 for _,source in pairs(P.compassSources)do source.dirty,source.pathDirty,source.nextRefresh=false,false,math.huge end
end
function CountProjections()
 local project,refresh,refreshing=P.ProjectCompassWorldPoint,P.RefreshCompassResources,false
 mock.projections=0
 function P:RefreshCompassResources(state)
  refreshing=true
  local delay=refresh(self,state)
  refreshing=false
  return delay
 end
 function P:ProjectCompassWorldPoint(...)
  if refreshing then mock.projections=mock.projections+1 end
  return project(self,...)
 end
end
function Near(actual,expected,label)
 assert(math.abs(actual-expected)<1e-9,(label or "value")..": "..actual.." ~= "..expected)
end
'''
LIVE_MODULES = ("Foundation/CompassMath.lua", "Navigation/CompassPosition.lua", "Navigation/CompassBearings.lua")
AUTO_ADVANCE = (ROOT / "Core/Navigation/CompassAutoAdvance.lua").read_text(encoding="utf-8")

cases = []


def check(name, code, family="forever", modules=LIVE_MODULES, setup=LIVE, real_pixel=False):
    cases.append((name, code, family, modules, setup, real_pixel))


check("Forever capability publishes display-only artwork at the player's world anchor", r'''
local id=OrbitResources.Add(mock.north+10,mock.west-20,"Peacebloom",134414)
Advance(.5,60)
local markers=Resources()
assert(#markers==1 and #P.displayMarkers==1 and P.displayMarkers[1]==markers[1])
local marker=markers[1]
assert(marker.key=="resource:"..id and marker.kind=="resource" and marker.displayOnly and marker.source=="resources")
assert(marker.texture==134414 and marker.sizeScale==.6 and marker.name=="Peacebloom")
Near(marker.x,.52,"x");Near(marker.y,.49,"y");Near(marker.distance,math.sqrt(500),"distance")
assert(mock.renderedResources==1)
for _,actionable in ipairs(P.markers)do assert(not actionable.displayOnly,"display marker became actionable") end
OrbitResources.AssertImmutable()
''')

for variant in ("standalone", "older", "future", "string"):
    check(f"Forever {variant} host provides no resource capability and retires polling", r'''
local variant="__VARIANT__"
if variant=="standalone" then Addon.OrbitHost=nil
elseif variant=="older" then Addon.OrbitHost.ExternalUIHost={legacyPluginVersion=1}
elseif variant=="future" then Addon.OrbitHost.ExternalUIHost.mapResourceObservationsVersion=2
else Addon.OrbitHost.ExternalUIHost.mapResourceObservationsVersion="1" end
OrbitResources.Add(mock.north,mock.west)
Advance(10,240)
assert(OrbitResources.reads==0 and #P.displayMarkers==0 and #Resources()==0)
assert(P.compassDisplaySources.resources.nextPoll==math.huge,"an unsupported capability kept polling")
P:InvalidateCompassSource("PLAYER_ENTERING_WORLD");Advance(1,60)
assert(OrbitResources.reads==0 and #P.displayMarkers==0)
'''.replace("__VARIANT__", variant))

check("Retail never reads a capable host or creates display state", r'''
OrbitResources.Fill(64)
Advance(10,240)
assert(OrbitResources.reads==0 and P.compassDisplaySources.resources==nil and #P.displayMarkers==0)
assert(P.compassSources.resources==nil and mock.renderedResources==0)
''', "retail")

for fps in (30, 240):
    check(f"{fps} FPS unchanged snapshots settle polls without jobs, projection or garbage", r'''
OrbitResources.Fill(80);Advance(.5,__FPS__)
assert(#Resources()==64 and #P.displayMarkers==64,"the bridge must bound external records to 64")
local display,first,reads,rebuilds=P.displayMarkers,Resources()[1],OrbitResources.reads,mock.rebuilds
local entries=P.compassDisplaySources.resources.entries
IdleSources();CountProjections()
local jobs,create=0,coroutine.create
coroutine.create=function(fn)jobs=jobs+1;return create(fn)end
Advance(10,__FPS__)
local polls=OrbitResources.reads-reads
assert(polls>=40 and polls<=51,"polls="..polls)
assert(mock.projections==0 and jobs==0,"unchanged polls projected "..mock.projections.." or built "..jobs.." jobs")
assert(P.displayMarkers==display and Resources()[1]==first and mock.rebuilds==rebuilds)
assert(P.compassDisplaySources.resources.entries==entries,"an unchanged snapshot was collected again")
collectgarbage("collect");collectgarbage("stop")
local heap=collectgarbage("count")
for i=1,__FPS__*10 do mock.now=mock.now+1/__FPS__;P:RefreshCompassDisplayMarkers()end
local grown=collectgarbage("count")-heap
collectgarbage("restart")
assert(grown<0.5,"unchanged polls allocated "..grown.." KiB")
mock.report=("10 s: %d polls, %d projections, %.3f KiB polling heap"):format(polls,mock.projections,grown)
OrbitResources.AssertImmutable()
'''.replace("__FPS__", str(fps)))

check("Refinement re-projects one node in place without leaving the ribbon", r'''
local id=OrbitResources.Add(mock.north+10,mock.west-20)
OrbitResources.Add(mock.north-10,mock.west+20)
Advance(.5,60)
local first,neighbour,rebuilds=Resources()[1],Resources()[2],mock.rebuilds
CountProjections()
for step=1,10 do
 OrbitResources.Move(id,mock.north+10+step/2,mock.west-20)
 for frame=1,18 do
  Tick(1/60)
  assert(#P.displayMarkers==2 and mock.renderedResources==2,"a refined node left the ribbon")
 end
end
local marker=Resources()[1]
assert(marker.key==first.key and marker~=first,"refinement must replace the published marker under the same key")
assert(Resources()[2]==neighbour,"an unchanged neighbour was re-created")
Near(marker.y,.5-15/1000,"refined y")
assert(mock.projections==10,"projections="..mock.projections)
assert(mock.rebuilds==rebuilds,"display changes rebuilt actionable markers")
''')

check("Display markers merge into the ribbon's bearing order by priority and distance", r'''
mock.poiIDs={99}
OrbitResources.Add(mock.north+10,mock.west-20)
Advance(.5,60)
local resource,poi=P.displayMarkers[1],P.compassSources.map.markers[1]
assert(resource and poi and poi.navigation==false and poi.priority==resource.priority)
assert(resource.distance<poi.distance and #P.bearings==2)
assert(P.bearings[1]==resource and P.bearings[2]==poi,"display markers did not merge in ribbon order")
''', modules=LIVE_MODULES + ("Discovery/CompassSources.lua",))

check("Markers changed while the position was unavailable are ordered before the next merge", r'''
mock.poiIDs={99}
OrbitResources.Add(mock.north+10,mock.west-20)
Advance(.5,60)
assert(#P.bearings==2)
local position=C_Map.GetPlayerMapPosition
mock.noWorldPosition=true
C_Map.GetPlayerMapPosition=function()return nil end
Tick(1/60);assert(#P.bearings==0)
mock.poiIDs={98,99};P:InvalidateCompassSource("AREA_POIS_UPDATED");Advance(.5,60)
assert(#P.compassSources.map.markers==2 and #P.bearings==0)
mock.noWorldPosition=false;C_Map.GetPlayerMapPosition=position
P.sortElapsed=0;Tick(1/60)
assert(#P.bearings==3 and P.bearings[1].displayOnly,"returning position merged unordered markers")
''', modules=LIVE_MODULES + ("Discovery/CompassSources.lua",))

check("Additions and removals publish within one poll and release retired entries", r'''
local a=OrbitResources.Add(mock.north+5,mock.west)
local b=OrbitResources.Add(mock.north-5,mock.west)
Advance(.5,60);assert(#Resources()==2)
OrbitResources.Remove(a);Advance(.21,60)
local state=P.compassDisplaySources.resources
assert(#Resources()==1 and Resources()[1].key=="resource:"..b and state.entries[a]==nil and state.entries[b])
local weak=setmetatable({Resources()[1]},{__mode="v"})
OrbitResources.Clear();Advance(.21,60)
assert(#Resources()==0 and next(state.entries)==nil and mock.renderedResources==0)
collectgarbage("collect");collectgarbage("collect")
assert(weak[1]==nil,"a retired display marker stayed reachable")
OrbitResources.AssertImmutable()
''')

for reason in ("unavailable", "cleared"):
    check(f"First visible frame drops {reason} observations before rendering", r'''
OrbitResources.Add(mock.north+5,mock.west);Advance(.5,60)
assert(mock.renderedResources==1)
mock.visible=false
local reads=OrbitResources.reads
Advance(10,60)
assert(OrbitResources.reads==reads,"a hidden compass polled the capability")
if "__REASON__"=="unavailable" then OrbitResources.live=false else OrbitResources.Clear() end
mock.visible=true;P.renderDirty=true;Tick(1/60)
assert(#P.displayMarkers==0 and mock.renderedResources==0,"a stale observation rendered after resume")
OrbitResources.live=true;OrbitResources.Add(mock.north-5,mock.west);Advance(.25,60)
assert(#P.displayMarkers>=1,"the capability did not recover")
'''.replace("__REASON__", reason))

check("Display updates continue while an unrelated collector holds the discovery slot", r'''
OrbitResources.Add(mock.north+5,mock.west);Advance(.5,60)
assert(#P.displayMarkers==1)
function P:CollectCompassLocations(markers)
 for i=1,5000 do self:CompassDiscoveryCheckpoint()end
end
P:InvalidateCompassSourceSettings("locations")
Tick(.21)
assert(P.discoveryJob and P.discoveryJob.definition.key=="locations")
OrbitResources.Clear()
for i=1,20 do Tick(1/60)end
assert(P.discoveryJob and P.discoveryJob.definition.key=="locations")
assert(mock.renderedResources==0 and #P.displayMarkers==0)
''')

check("World-context resets replace display state before rendering", r'''
OrbitResources.Add(mock.north+5,mock.west);Advance(.5,60)
local state=P.compassDisplaySources.resources
assert(#P.displayMarkers==1)
state.nextPoll=GetTime()+10
OrbitResources.Clear()
P:InvalidateCompassSource("UNIT_PHASE");Tick(1/60)
assert(P.compassDisplaySources.resources~=state,"a context reset kept the provider's cache")
assert(#P.displayMarkers==0 and mock.renderedResources==0)
''')

for recovery in ("deadline", "context"):
    check(f"Provider failures publish nothing and back off before {recovery} recovery", r'''
OrbitResources.Add(mock.north+5,mock.west);Advance(.5,60)
assert(#P.displayMarkers==1)
OrbitResources.failure="resource getter failed"
local reads=OrbitResources.reads
local ok,message=pcall(Advance,.25,60)
assert(not ok and tostring(message):find("resource getter failed",1,true),tostring(message))
assert(OrbitResources.reads==reads+1 and #P.displayMarkers==0)
Tick(1/60);assert(mock.renderedResources==0)
Advance(1,240);assert(OrbitResources.reads==reads+1,"a failed provider retried before its backoff")
OrbitResources.failure=nil
if "__RECOVERY__"=="deadline" then
 Advance(28.5,60);assert(#P.displayMarkers==0 and OrbitResources.reads==reads+1)
 Advance(.75,60)
else
 P:InvalidateCompassSource("PLAYER_ENTERING_WORLD");Advance(.5,60)
end
assert(#P.displayMarkers==1)
'''.replace("__RECOVERY__", recovery))

check("Unreadable records are skipped and rejected projections stay cached", r'''
local far=OrbitResources.Add(mock.north,mock.west-600,"Far")
OrbitResources.Add({secret=true},mock.west,"Secret")
OrbitResources.Add(mock.north,mock.west,"No icon",0)
OrbitResources.Add(mock.north,mock.west,"")
local good=OrbitResources.Add(mock.north+5,mock.west,"Fresh")
OrbitResources.SetExtra({"not a record",{id=good,north=mock.north+50,west=mock.west,name="Duplicate",icon=123}})
Advance(.5,60)
assert(#Resources()==1 and Resources()[1].name=="Fresh")
local state=P.compassDisplaySources.resources
assert(state.entries[far] and state.entries[far].marker==false,"an off-map projection was not retained")
CountProjections()
OrbitResources.Move(good,mock.north+6,mock.west);Advance(.25,60)
assert(mock.projections==1 and #Resources()==1,"rejected records were projected again")
OrbitResources.AssertImmutable()
''')

check("Records wait for the player's world sample, then project without a new snapshot", r'''
mock.noWorldPosition=true
OrbitResources.Add(mock.north+5,mock.west)
Advance(1,60)
assert(#P.displayMarkers==0)
local revision=OrbitResources.revision
mock.noWorldPosition=false;Advance(.5,60)
assert(#P.displayMarkers==1 and OrbitResources.revision==revision)
''')

for fps in (10, 20, 30, 60, 240):
    for trigger in ("arrival", "removal"):
        check(f"Dense display markers keep {trigger} auto-advance at the empty baseline at {fps} FPS", r'''
assert(loadstring([==[__AUTO_ADVANCE__]==],"CompassAutoAdvance.lua"))("Orbit_Compass",Addon)
function P:RefreshCompassBearings()
 if self.mapWidth then self:ReadCompassPosition()end
end
local function Measure(nodes)
 local longest=0
 for offset=0,9 do
  OrbitResources.Clear();OrbitResources.Fill(nodes)
  P:InitializeCompassDiscovery()
  mock.advanceAt=nil;mock.poiIDs={1,2}
  C_AreaPoiInfo.GetAreaPOIInfo=function(_,id)
   return {areaPoiID=id,name="Point "..id,position={x=id==1 and .5 or .51,y=.5},atlasName="test"}
  end
  FinishDiscovery()
  P.autoAdvanceMode,P.autoAdvanceSameType,P.range="arrival",false,100
  P.bearingPlayerX,P.bearingPlayerY=.5,.5
  P.navigationKey="waypoint";P.navigationTarget={distance=50}
  assert(P:SetWaypoint(3,.5,.5,"Start",nil,"poi:1"));FinishDiscovery()
  P:UpdateCompassAutoAdvance();assert(P.compassAutoAdvance)
  P.compassAutoAdvanceNext=P.discoveryClock+offset*.025
  local original=C_Map.SetUserWaypoint
  C_Map.SetUserWaypoint=function(point)
   if point.position.x==.51 then mock.advanceAt=mock.now end
   return original(point)
  end
  if "__TRIGGER__"=="arrival" then P.navigationTarget.distance=1
  else mock.poiIDs={2};P:InvalidateCompassSource("AREA_POIS_UPDATED") end
  local started=mock.now
  for i=1,__FPS__*20 do
   mock.now=mock.now+1/__FPS__;P:UpdateCompass(1/__FPS__)
   if mock.advanceAt then break end
  end
  C_Map.SetUserWaypoint=original
  assert(mock.advanceAt,"starved at phase "..offset)
  longest=math.max(longest,mock.advanceAt-started)
 end
 assert(#P.displayMarkers==math.min(nodes,64),"display markers were not published during the measurement")
 return longest
end
local baseline=Measure(0)
local dense=Measure(64)
assert(dense<=baseline+1e-9,("64 display markers delayed auto-advance: %.3f s against %.3f s"):format(dense,baseline))
mock.report=("longest transition %.3f s, empty baseline %.3f s"):format(dense,baseline)
'''.replace("__AUTO_ADVANCE__", AUTO_ADVANCE).replace("__TRIGGER__", trigger).replace("__FPS__", str(fps)))

check("Disable and re-enable release display ownership across cycles", r'''
function IsInInstance()return false end
function IsAltKeyDown()return false end
function UnitHasVehicleUI()return false end
function P:DisableWaypointCommands()end
function P:EnableWaypointCommands()end
function P:DisableCompassIntegrations()end
function P:EnableCompassIntegrations()end
function P:RegisterStandardEvents()end
function P:RegisterVisibilityEvents()end
function P:ClearCompassMarkers()end
local weak=setmetatable({},{__mode="v"})
for cycle=1,32 do
 mock.disabled=false;P:OnEnable();P.frame:Show()
 OrbitResources.Clear();OrbitResources.Fill(64);Advance(.5,60)
 assert(#P.displayMarkers==64);weak[cycle]=P.displayMarkers[1]
 mock.disabled=true;P:OnDisable()
 assert(#P.displayMarkers==0 and P.compassDisplaySources.resources.entries==nil and not P.discoveryJob)
 local reads=OrbitResources.reads
 Advance(1,30);assert(OrbitResources.reads==reads,"a disabled compass polled the capability")
end
collectgarbage("collect");collectgarbage("collect")
assert(next(weak)==nil,"disabled display markers stayed reachable")
''')

check("Replacement churn retains only the current snapshot's state", r'''
OrbitResources.Fill(64);Advance(.5,60)
for i=1,50 do OrbitResources.Clear();OrbitResources.Fill(64);Advance(.21,60)end
collectgarbage("collect");collectgarbage("collect")
local warm=collectgarbage("count")
for i=1,500 do OrbitResources.Clear();OrbitResources.Fill(64);Advance(.21,60)end
collectgarbage("collect");collectgarbage("collect")
local settled=collectgarbage("count")
local entries=0
for _ in pairs(P.compassDisplaySources.resources.entries)do entries=entries+1 end
assert(#Resources()==64 and #P.displayMarkers==64 and entries==64)
assert(settled<=warm+64,"retained fixture heap grew "..(settled-warm).." KiB")
mock.report=("retained fixture heap %.1f -> %.1f KiB"):format(warm,settled)
OrbitResources.AssertImmutable()
''')

check("Display-only markers never become targets, menus, Search results or auto-advance choices", r'''
assert(loadstring([==[__AUTO_ADVANCE__]==],"CompassAutoAdvance.lua"))("Orbit_Compass",Addon)
OrbitResources.Add(mock.north,mock.west-1,"Peacebloom")
Advance(.5,60)
local resource=P.displayMarkers[1]
assert(resource and resource.bearing)
resource.renderShown=true
P:TargetCompassPoint()
assert(not P:FindCompassPoint(false) and not P:FindCompassPoint(true) and mock.waypoints==0)
local results={};P:SearchCompassLandmarks("Peacebloom",results,P:NewCompassSearchScratch())
assert(#results==0 and not P:ChooseCompassSearchResult({kind="resource",marker=resource}) and mock.waypoints==0)
local menuButtons=0
MenuUtil={CreateContextMenu=function(_,callback)
 callback(nil,{CreateTitle=function()end,SetScrollMode=function()end,CreateButton=function()
  menuButtons=menuButtons+1;return{AddInitializer=function()end}
 end})
end}
Addon.Services.pixel={Snap=function(_,n)return n end};UIParent={GetEffectiveScale=function()return 1 end}
P:ShowCompassNearby();assert(menuButtons==0)
local original={key="poi:1",kind="poi",source="map",x=.5,y=.5,distance=1,destination={mapID=3,x=.5,y=.5}}
local ordinary={key="poi:2",kind="poi",source="map",name="Next",x=.51,y=.5,destination={mapID=3,x=.51,y=.5}}
Near(resource.x,.501,"resource x")
P.markers={original,ordinary};P.autoAdvanceMode="arrival";P.autoAdvanceSameType=false
P.bearingPlayerX,P.bearingPlayerY=.5,.5;P.navigationKey="waypoint";P.navigationTarget=original
P.waypointLabel={sourceKey="poi:1"};P.discoveryClock=P.discoveryClock+10
P.discoveryDirty,P.waypointDirty,P.discoveryJob=false,false,nil
P.compassSources.map.status="ready"
for _,source in pairs(P.compassSources)do source.enabled=false end
P:UpdateCompassAutoAdvance();assert(mock.waypoint.position.x==.51)
'''.replace("__AUTO_ADVANCE__", AUTO_ADVANCE), modules=LIVE_MODULES + ("Navigation/CompassPointMenu.lua",))

check("A coincident waypoint keeps its identity beside a display-only observation", r'''
OrbitResources.Add(mock.north+10,mock.west-20,"Camp herb")
Advance(.5,60)
local resource=P.displayMarkers[1]
assert(resource and P:SetWaypoint(3,resource.x,resource.y,"Camp"))
Advance(.25,60)
local waypoint
for _,marker in ipairs(P.markers)do if marker.key=="waypoint"then waypoint=marker end end
assert(waypoint and waypoint.kind=="waypoint" and not waypoint.texture)
assert(waypoint.navigation and not waypoint.sourceKey)
local results={};P:SearchCompassLandmarks("Camp",results,P:NewCompassSearchScratch())
assert(#results==0 and mock.waypoints==1)
''', modules=LIVE_MODULES + ("Discovery/CompassSources.lua",))

for family in ("forever", "retail"):
    check(f"{family} selected ordinary waypoint retains matched artwork and identity", r'''
local marker=Addon.SourceUtils.AddMarker(P,P.compassSources.gathermate.markers,"gathermate:1",
 {x=.2,y=.3},"Recorded herb","test",6,"gathermate:Herb")
marker.texture,marker.sizeScale=134414,.6
assert(P:SetWaypoint(3,.2,.3,"Recorded herb",nil,"gathermate:1"))
P:RebuildCompassMarkers()
local waypoint
for _,candidate in ipairs(P.markers)do if candidate.key=="waypoint"then waypoint=candidate end end
assert(waypoint and waypoint.kind=="gathermate:Herb" and waypoint.texture==134414)
assert(waypoint.sourceKey=="gathermate:1" and waypoint.navigation)
assert(P.waypointLabel.artwork.kind=="gathermate:Herb")
''', family=family, modules=LIVE_MODULES + ("Discovery/CompassSources.lua",))

REGIONS = r'''
mock.maskCreates,mock.maskAdds,mock.maskRemoves=0,0,0
mock.textureCreates,mock.regionCreates,mock.regionWrites=0,0,0
function Region()
 mock.regionCreates=mock.regionCreates+1
 local r={scripts={},shown=false,level=0,width=20,height=20}
 function r:CreateTexture(name,layer,template,sublevel)
  mock.textureCreates=mock.textureCreates+1
  local texture=Region();texture.layer,texture.sublevel=layer,sublevel;return texture
 end
 function r:CreateMaskTexture()mock.maskCreates=mock.maskCreates+1;return Region()end
 function r:AddMaskTexture(mask)
  self.masks=self.masks or {};assert(not self.masks[mask]);self.masks[mask]=true
  mock.maskAdds=mock.maskAdds+1
 end
 function r:RemoveMaskTexture(mask)
  assert(self.masks and self.masks[mask]);self.masks[mask]=nil
  mock.maskRemoves=mock.maskRemoves+1
 end
 function r:SetAllPoints(target)mock.regionWrites=mock.regionWrites+1;self.allPoints=target end
 function r:SetScript(k,v)self.scripts[k]=v end
 function r:GetScript(k)return self.scripts[k]end
 function r:SetSize(w,h)mock.regionWrites=mock.regionWrites+1;self.width,self.height=w,h end
 function r:GetSize()return self.width,self.height end
 function r:GetEffectiveScale()return 1 end
 function r:SetPoint(...)mock.regionWrites=mock.regionWrites+1;self.point={...}end
 function r:GetFrameLevel()return self.level end
 function r:SetFrameLevel(n)mock.regionWrites=mock.regionWrites+1;self.level=n end
 function r:SetTexture(t)mock.regionWrites=mock.regionWrites+1;self.texture=t;return true end
 function r:SetAtlas(t)mock.regionWrites=mock.regionWrites+1;self.atlas=t end
 function r:SetText(t)self.text=t end
 function r:Show()mock.regionWrites=mock.regionWrites+1;self.shown=true end
 function r:Hide()mock.regionWrites=mock.regionWrites+1;self.shown=false;if self.scripts.OnHide then self.scripts.OnHide(self)end end
 function r:SetShown(v)if v then self:Show()else self:Hide()end end
 function r:IsShown()return self.shown end
 function r:IsOwned(owner)return self.owner==owner end
 function r:ClearLines()self.lines={} end
 function r:AddLine(text)self.lines[#self.lines+1]=text end
 function r:EnableMouse(v)self.mouse=v end
 for _,method in ipairs({"SetAlpha","SetVertexColor","SetRotation","SetSnapToPixelGrid",
 "SetTexelSnappingBias","SetTexCoord","RegisterForClicks","ClearAllPoints"})do
  r[method]=function()mock.regionWrites=mock.regionWrites+1 end
 end
 return r
end
function CreateFrame()return Region()end
function CreateObjectPool(create,reset)
 local pool={active={},inactive={},created=0}
 function pool:Acquire()
  local object=table.remove(self.inactive)
  local fresh=object==nil
  if fresh then object=create(self);self.created=self.created+1;reset(self,object,true)end
  assert(not self.active[object]);self.active[object]=true
  return object,fresh
 end
 function pool:Release(object)
  assert(self.active[object]);reset(self,object);self.active[object]=nil
  self.inactive[#self.inactive+1]=object
 end
 function pool:ReleaseAll()for object in pairs(self.active)do self:Release(object)end end
 return pool
end
Addon.Services.tooltip=Region();Addon.Services.tooltip.lines={}
function Addon.Services.tooltipHide()Addon.Services.tooltip:Hide()end
function Addon.Services.AnchorTooltip(t,owner)t.owner=owner;t.lines={}end
Addon.Services.pixel={Snap=function(_,n)return n end,Multiple=function(_,n)return n end,
 ToCount=function(_,n)return n end}
UIParent=Region()
Addon.L.PLU_COMPASS_OVERLAP_HINT_F="Choose among %d points"
function P:HideCompassHandyNotesTooltip()end
function P:ShowCompassHandyNotesTooltip()return false end
function P:CompassDisplayDistance(n)return n end
function P:FormatCompassDistance(n)return tostring(n)end
P.frame=Region();P.frame:Show()
P.iconSize=20;P.range=1000;P.markerClock=10;P.lineY=0
P.artworkLayout={scale=1,centerX=0,centerY=0}
P.markerGroupOrder,P.markerGroups,P.markerLeftOrder,P.markerGroupMembers={},{},{},{}
function MakeMarker(key,kind,displayOnly,x)
 return {key=key,kind=kind,displayOnly=displayOnly,name=key,texture=134414,atlas="test",sizeScale=.6,
 x=x or .2,y=.3,distance=20,distanceSquared=400,projectedX=0,priority=6,
 destination={mapID=3,x=x or .2,y=.3}}
end
function Click(button)
 button.scripts.OnMouseDown(button,"LeftButton")
 button.scripts.OnClick(button,"LeftButton")
end
mock.menuButtons={}
MenuUtil={CreateContextMenu=function(_,callback)
 mock.menuButtons={}
 callback(nil,{CreateTitle=function()end,SetScrollMode=function()end,
  CreateButton=function(_,label,action)
   mock.menuButtons[#mock.menuButtons+1]={label=label,action=action}
   return {AddInitializer=function()end}
  end})
end}
'''

PIXEL_REGIONS = REGIONS + r'''
mock.physicalHeight,mock.scale,mock.centerX,mock.centerY=1080,1,0,0
local BasicRegion=Region
function Region()
 local region=BasicRegion()
 function region:GetEffectiveScale()return mock.scale end
 function region:GetCenter()return mock.centerX,mock.centerY end
 function region:SetWidth(width)mock.regionWrites=mock.regionWrites+1;self.width=width end
 function region:SetHeight(height)mock.regionWrites=mock.regionWrites+1;self.height=height end
 function region:RegisterEvent()end
 function region:UnregisterAllEvents()end
 return region
end
function GetPhysicalScreenSize()return mock.physicalHeight*16/9,mock.physicalHeight end
function CreateFrame()local region=Region();mock.pixelEventFrame=region;return region end
P.frame=Region();P.frame:Show();P.frame:SetSize(420,Addon.Constants.RIBBON_HEIGHT)
P.artwork={Region(),Region(),Region()};P.pointer=Region();P.detail=Region();P.headingHeight=11
P.ticks={{bearing=0,texture=Region(),label=Region(),labelText="N"}};P.viewAngle=180
function Near(actual,expected,label)
 assert(math.abs(actual-expected)<1e-6,(label or "geometry")..": "..actual.." ~= "..expected)
end
'''

RENDER_MODULES = ("Navigation/CompassPointMenu.lua", "Ribbon/CompassMarkerGroups.lua",
                  "Ribbon/CompassMarkerView.lua")

for family in ("forever", "retail"):
    check(f"{family} ordinary marker click and artwork remain intact", r'''
local marker=MakeMarker("gathermate:1","gathermate:Herb",false)
P:LayoutCompassMarkerGroups({marker});P:CreateCompassMarkerPool()
local button=P.markerPool:Acquire()
local textures=mock.textureCreates
assert(P:RenderCompassMarker(button,marker,true,0,1,0,2,1))
assert(button.icon.texture==134414 and button.shadow.texture==134414)
assert(mock.maskCreates==0 and mock.maskAdds==0 and mock.maskRemoves==0)
assert(not button.resourceBorder and mock.textureCreates==textures)
assert(marker.projectedHitSize==marker.projectedIconSize+2)
assert(marker.projectedBelowLine)
Click(button);assert(mock.waypoints==1 and #mock.menuButtons==0)
''', family=family, modules=RENDER_MODULES, setup=REGIONS)

check("live resource icon keeps artwork but cannot click-track", r'''
local marker=MakeMarker("resource:1","resource",true)
P:LayoutCompassMarkerGroups({marker});P:CreateCompassMarkerPool()
local button=P.markerPool:Acquire()
P:RenderCompassMarker(button,marker,true,0,1,0,2,1)
assert(button.icon.texture==134414 and marker.projectedBelowLine)
Click(button);assert(mock.waypoints==0 and #mock.menuButtons==0)
button.scripts.OnEnter(button)
assert(Addon.Services.tooltip.text=="resource:1")
assert(#Addon.Services.tooltip.lines==2)
''', modules=RENDER_MODULES, setup=REGIONS)

check("resource masks follow icon and shadow geometry without repeated work", r'''
local marker=MakeMarker("resource:1","resource",true)
P:LayoutCompassMarkerGroups({marker});P:CreateCompassMarkerPool()
local button=P.markerPool:Acquire()
assert(mock.maskCreates==0)
local textures=mock.textureCreates
P:RenderCompassMarker(button,marker,true,0,1,0,2,1)
assert(mock.maskCreates==2 and mock.maskAdds==2 and mock.maskRemoves==0)
local border=button.resourceBorder
assert(border and border:IsShown() and border.atlas=="ChallengeMode-AffixRing-Sm")
assert(border.layer=="OVERLAY" and border.sublevel==Addon.Constants.MARKER_SYMBOL_SUBLEVEL)
assert(mock.textureCreates==textures+1)
for _,texture in ipairs({button.icon,button.shadow})do
 assert(texture.resourceMask.atlas=="CircleMaskScalable")
 assert(texture.resourceMask.allPoints==texture and texture.masks[texture.resourceMask])
end
assert(button.shadow.width==button.icon.width+2)
for index=1,500 do P:RenderCompassMarker(button,marker,true,0,1,0,2,1)end
marker.projectedIconSize=30
marker.projectedHitSize,marker.projectedResourceBorderSize=P:CalculateCompassResourceSizes(30,4,.8)
P:RenderCompassMarker(button,marker,true,0,1,0,4,.8)
assert(button.icon.width==30 and button.shadow.width==34)
assert(mock.maskCreates==2 and mock.maskAdds==2 and mock.maskRemoves==0)
assert(button.resourceBorder==border and border:IsShown() and mock.textureCreates==textures+1)
''', modules=RENDER_MODULES, setup=REGIONS)

check("actual pixel geometry keeps ring bounds, heading clearance and overlap edges aligned", r'''
local C=Addon.Constants
local pixel=Addon.Services.pixel
assert(C.MARKER_RESOURCE_BORDER_SCALE==22/20)
local marker=MakeMarker("resource:1","resource",true)
local neighbor=MakeMarker("resource:2","resource",true)
local upper=MakeMarker("poi:1","poi",false)
P.displayMarkers={marker}
P:CreateCompassMarkerPool();local button=P.markerPool:Acquire()
local layouts,overlaps=0,0
for _,height in ipairs({720,1080,2160})do
 mock.physicalHeight=height;mock.pixelDriver.scripts.OnEvent()
 for _,scale in ipairs({.64,1,1.5})do
  mock.scale=scale
  local step,outline=pixel:Multiple(1,scale),pixel:Multiple(C.MARKER_OUTLINE*2,scale)
  for _,size in ipairs({C.ICON_MIN,C.DEFAULT_ICON_SIZE,C.ICON_MAX})do
   P.iconSize=size
   for _,center in ipairs({{0,0},{123.123,345.456}})do
    mock.centerX,mock.centerY=center[1],center[2]
    assert(P:LayoutCompassArtwork());P:RenderCompassHeadings(0)
    local headingY=P.ticks[1].label.point[5]
    local nearSize
    for _,distance in ipairs({0,150,575,1000,5000})do
     marker.distance,marker.distanceSquared,marker.projectedX=distance,distance*distance,.37
     local writes=mock.regionWrites
     assert(P:LayoutCompassArtwork() and mock.regionWrites==writes,"distance changes reuse heading layout")
     Near(P.artworkLayout.headingY,headingY,"stationary heading")
     P:LayoutCompassMarkerGroups({marker})
     P:RenderCompassMarker(button,marker,true,.37,1,P.artworkLayout.markerY,outline,scale)
     local left,top=mock.centerX+button.point[4],mock.centerY+button.point[5]
     local icon,border,shadow=button.icon,button.resourceBorder,button.shadow
     local function Bounds(region)
      return left+region.point[4],top+region.point[5],region.width,region.height
     end
     local il,it,iw,ih=Bounds(icon)
     local bl,bt,bw,bh=Bounds(border)
     local sl,st,sw,sh=Bounds(shadow)
     Near(il+iw/2,bl+bw/2,"ring x center");Near(it-ih/2,bt-bh/2,"ring y center")
     Near(il+iw/2,sl+sw/2,"shadow x center");Near(it-ih/2,st-sh/2,"shadow y center")
     Near(il+iw/2,left+button.width/2,"hit x center");Near(it-ih/2,top-button.height/2,"hit y center")
     Near(iw,ih,"square icon");Near(bw,bh,"square ring")
     assert(bw>=iw and button.width+1e-6>=bw and button.width+1e-6>=sw)
     for _,edge in ipairs({il,it,il+iw,it-ih,bl,bt,bl+bw,bt-bh,sl,st,sl+sw,st-sh})do
      Near(edge/step,math.floor(edge/step+.5),"physical pixel edge")
     end
     local lineBottom=mock.centerY+P.lineY-pixel:Multiple(C.LINE_THICKNESS,scale)
     Near((lineBottom-top)/step,C.MARKER_BELOW_LINE_GAP,"below-line gap")
     assert(bt-bh-(mock.centerY+headingY)+1e-6>=pixel:Multiple(C.HEADING_GAP,scale),
      "heading must clear the complete ring rectangle at every distance")
     assert(math.abs(bw-iw*C.MARKER_RESOURCE_BORDER_SCALE)/step<=1+1e-6,
      "symmetric snapping stays within one physical pixel of the native ring ratio")
     if distance<=C.MARKER_NEAR_DISTANCE then
      nearSize=nearSize or iw;Near(iw,nearSize,"near-size plateau")
     elseif distance>=C.MARKER_FAR_DISTANCE then
      Near(iw,pixel:Snap(size*marker.sizeScale*C.MARKER_FAR_SCALE,scale),"far-size plateau")
     end
     Near(marker.projectedLeftPx,left/step,"group left equals rendered left")
     Near(marker.projectedRightPx,(left+button.width)/step,"group right equals rendered right")
     neighbor.distance,neighbor.distanceSquared=distance,distance*distance
     for _,delta in ipairs({-1,0,1})do
      neighbor.projectedX=marker.projectedX+marker.projectedHitSize+delta*step
      P:LayoutCompassMarkerGroups({marker,neighbor,upper})
      assert((marker.overlapGroup==neighbor.overlapGroup)==(delta<0),"ring overlap boundary")
      assert(upper.overlapGroup~=marker.overlapGroup,"upper row retains separate groups")
      overlaps=overlaps+1
     end
     layouts=layouts+1
    end
   end
  end
 end
end
assert(mock.maskCreates==2 and mock.maskAdds==2 and mock.maskRemoves==0)
mock.auditPixelMetrics={layouts=layouts,overlaps=overlaps}
''', modules=RENDER_MODULES+("Foundation/CompassMath.lua","Ribbon/CompassView.lua"),
      setup=PIXEL_REGIONS, real_pixel=True)


check("published resource rows reserve heading clearance and restore the empty layout", r'''
local C=Addon.Constants
assert(not Addon.OrbitHost and #P.displayMarkers==0)
for _,height in ipairs({720,1080,2160})do
 mock.physicalHeight=height;mock.pixelDriver.scripts.OnEvent()
 for _,scale in ipairs({.64,1,1.5})do
  mock.scale=scale;mock.centerX,mock.centerY=123.123,345.456
  for _,size in ipairs({C.ICON_MIN,C.DEFAULT_ICON_SIZE,C.ICON_MAX})do
   P.iconSize=size
   P.displayMarkers={}
   assert(P:LayoutCompassArtwork())
   local emptyHeading,emptyDetail=P.artworkLayout.headingY,P.detail.point[5]
   local writes=mock.regionWrites
   for index=1,100 do assert(P:LayoutCompassArtwork())end
   assert(mock.regionWrites==writes,"empty layout has no repeated region writes")
   local marker=MakeMarker("resource:1","resource",true)
   P.displayMarkers={marker}
   assert(P:LayoutCompassArtwork())
   local withResource=P.artworkLayout.headingY
   assert(withResource<=emptyHeading and mock.regionWrites>writes,"arrival reserves at least the existing row clearance")
   Near(P.detail.point[5]-emptyDetail,withResource-emptyHeading,"details follow the heading movement")
   local regions=mock.regionCreates
   writes=mock.regionWrites
   for index=1,100 do
    marker.distance=index*100
    assert(P:LayoutCompassArtwork())
   end
   P.displayMarkers={MakeMarker("resource:replacement","resource",true),MakeMarker("gathermate:1","gathermate:Herb",false)}
   assert(P:LayoutCompassArtwork())
   Near(P.artworkLayout.headingY,withResource,"identity and distance do not move headings")
   assert(mock.regionWrites==writes and mock.regionCreates==regions,"unchanged reservation reuses its geometry")
   P.displayMarkers={}
   assert(P:LayoutCompassArtwork())
   Near(P.artworkLayout.headingY,emptyHeading,"removal restores ordinary heading geometry")
   Near(P.detail.point[5],emptyDetail,"removal restores ordinary detail geometry")
   writes=mock.regionWrites
   assert(P:LayoutCompassArtwork() and mock.regionWrites==writes,"removed resources leave no layout work")
  end
 end
end
''', modules=RENDER_MODULES+("Ribbon/CompassView.lua",), setup=PIXEL_REGIONS, real_pixel=True)

check("Retail headings keep the ordinary layout beside a capable host", r'''
P.iconSize=Addon.Constants.DEFAULT_ICON_SIZE
assert(P:LayoutCompassArtwork())
local heading,writes=P.artworkLayout.headingY,mock.regionWrites
OrbitResources.Fill(8)
for index=1,100 do
 mock.now=mock.now+.25;P:RefreshCompassDisplayMarkers()
 assert(P:LayoutCompassArtwork())
end
assert(OrbitResources.reads==0 and #P.displayMarkers==0)
assert(P.artworkLayout.headingY==heading and mock.regionWrites==writes,"Retail moved its headings")
''', family="retail", modules=RENDER_MODULES+("Ribbon/CompassView.lua",), setup=PIXEL_REGIONS+ORBIT_RESOURCES,
      real_pixel=True)

check("pooled resource masks clear on identical-art rebinding and release", r'''
local resource=MakeMarker("resource:1","resource",true)
local recorded=MakeMarker("gathermate:1","gathermate:Herb",false)
P:LayoutCompassMarkerGroups({resource,recorded});P:CreateCompassMarkerPool()
local button=P.markerPool:Acquire()
local textures=mock.textureCreates
local border
for index=1,500 do
 P:RenderCompassMarker(button,resource,true,0,1,0,2,1)
 border=border or button.resourceBorder
 assert(button.resourceBorder==border and border:IsShown())
 assert(button.icon.masks[button.icon.resourceMask] and button.shadow.masks[button.shadow.resourceMask])
 P:RenderCompassMarker(button,recorded,true,0,1,0,2,1)
 assert(button.resourceBorder==border and not border:IsShown())
 assert(not next(button.icon.masks) and not next(button.shadow.masks))
end
assert(mock.maskCreates==2 and mock.maskAdds==1000 and mock.maskRemoves==1000)
P:RenderCompassMarker(button,resource,true,0,1,0,2,1)
P.markerPool:Release(button)
assert(not button.resourceMasked and not button.marker and not button:IsShown())
assert(not border:IsShown())
assert(not next(button.icon.masks) and not next(button.shadow.masks))
assert(P.markerPool:Acquire()==button)
P:RenderCompassMarker(button,recorded,true,0,1,0,2,1)
assert(not border:IsShown())
assert(not next(button.icon.masks) and not next(button.shadow.masks))
P:RenderCompassMarker(button,resource,true,0,1,0,2,1)
assert(button.icon.masks[button.icon.resourceMask] and button.shadow.masks[button.shadow.resourceMask])
assert(mock.maskCreates==2 and mock.maskAdds==1004 and mock.maskRemoves==1002)
assert(button.resourceBorder==border and border:IsShown() and mock.textureCreates==textures+1)
''', modules=RENDER_MODULES, setup=REGIONS)

for family in ("forever", "retail"):
    check(f"{family} full marker pool stays bounded across churn, idle and clear/reopen", r'''
local C=Addon.Constants
P.markerSlots,P.nextMarkerSlots,P.markerSlotsByKey={},{},{}
P.selectedMarkers,P.selectionKeys={},{}
P.markerGeneration=0;P.detail=Region()
function P:HideCompassPeek()end
P:CreateCompassMarkerPool()
local weakMarkers=setmetatable({},{__mode="v"})
local resourceAllowed=Addon.ClientFeatures.sources.resources
local function Render(selection)
 P.selectedMarkers=selection
 P:LayoutCompassMarkerGroups(selection)
 P:AssignCompassMarkerSlots(selection,false)
 for index,marker in ipairs(selection)do
  P:RenderCompassMarker(P.markerSlots[index],marker,true,0,1,0,2,1)
 end
end
local function Replace(cycle)
 local selection={}
 for index=1,C.MAX_MARKERS do
  local resource=resourceAllowed and cycle%2==0
  local marker=MakeMarker(cycle..":"..index,resource and "resource" or "gathermate:Herb",resource)
  marker.projectedX=index*30
  selection[index]=marker;weakMarkers[index]=marker
 end
 P.markerSlotsDirty=true;Render(selection)
end
local function Clear()
 P:ClearCompassMarkers()
 assert(not next(P.markerPool.active) and #P.markerPool.inactive==C.MAX_MARKERS)
 assert(not next(P.markerSlotsByKey) and not next(P.markerGroupMembers))
 for _,button in ipairs(P.markerPool.inactive)do
  assert(not button.marker and not button.resourceMasked and not button:IsShown())
  assert(not button.resourceBorder or not button.resourceBorder:IsShown())
 end
 collectgarbage("collect")
 assert(not next(weakMarkers))
end
for cycle=1,20 do Replace(cycle);if cycle%4==0 then Clear()end end
local regions,textures,masks=mock.regionCreates,mock.textureCreates,mock.maskCreates
collectgarbage("collect");local before=collectgarbage("count")
for cycle=21,1020 do Replace(cycle);if cycle%4==0 then Clear()end end
collectgarbage("collect");local after=collectgarbage("count")
assert(P.markerPool.created==C.MAX_MARKERS)
assert(mock.regionCreates==regions and mock.textureCreates==textures and mock.maskCreates==masks)
assert(after-before<4,"retained fixture heap grew by "..(after-before).." KiB")
assert(masks==(resourceAllowed and 2*C.MAX_MARKERS or 0))
Replace(1022)
local writes,adds,removes=mock.regionWrites,mock.maskAdds,mock.maskRemoves
for cycle=1,500 do Render(P.selectedMarkers)end
assert(mock.regionWrites==writes and mock.maskAdds==adds and mock.maskRemoves==removes)
assert(mock.regionCreates==regions and mock.textureCreates==textures and mock.maskCreates==masks)
local rings=0
for _,button in ipairs(P.markerSlots)do if button.resourceBorder then rings=rings+1 end end
assert(rings==(resourceAllowed and C.MAX_MARKERS or 0))
mock.auditStyleMetrics={masks=masks,rings=rings,slots=P.markerPool.created,heapDelta=after-before}
Clear()
''', family=family, modules=RENDER_MODULES+("Ribbon/CompassView.lua",), setup=REGIONS)

check("mixed resource and GatherMate overlap keeps ordinary direct action", r'''
local resource=MakeMarker("resource:1","resource",true)
local recorded=MakeMarker("gathermate:1","gathermate:Herb",false,.4)
P:LayoutCompassMarkerGroups({resource,recorded})
recorded.projectedX=(resource.projectedHitSize+recorded.projectedHitSize)/2-1
P:LayoutCompassMarkerGroups({resource,recorded})
assert(recorded.projectedLeftPx<resource.projectedRightPx)
assert(resource.overlapGroup==recorded.overlapGroup)
P:CreateCompassMarkerPool();local button=P.markerPool:Acquire()
P:RenderCompassMarker(button,recorded,true,0,1,0,2,1)
button.scripts.OnEnter(button);assert(#Addon.Services.tooltip.lines==2)
Click(button)
assert(mock.waypoints==1 and mock.waypoint.position.x==.4 and #mock.menuButtons==0)
''', modules=RENDER_MODULES, setup=REGIONS)

check("mixed overlap menu exposes only actionable destinations", r'''
local resource=MakeMarker("resource:1","resource",true)
local first=MakeMarker("gathermate:1","gathermate:Herb",false,.4)
local second=MakeMarker("gathermate:2","gathermate:Ore",false,.6)
P:LayoutCompassMarkerGroups({resource,first,second})
P:CreateCompassMarkerPool();local button=P.markerPool:Acquire()
P:RenderCompassMarker(button,first,true,0,1,0,2,1)
button.scripts.OnEnter(button)
assert(Addon.Services.tooltip.lines[3]=="Choose among 2 points")
assert(#first.overlapGroup.markers==3 and #first.overlapGroup.actions==2 and first.overlapGroup==resource.overlapGroup)
Click(button);assert(mock.waypoints==0 and #mock.menuButtons==2)
mock.menuButtons[2].action()
assert(mock.waypoints==1 and mock.waypoint.position.x==.6)
''', modules=RENDER_MODULES, setup=REGIONS)

check("upper POI and lower live resource remain separate overlap groups", r'''
local resource=MakeMarker("resource:1","resource",true)
local poi=MakeMarker("poi:1","poi",false)
P:LayoutCompassMarkerGroups({resource,poi})
assert(resource.projectedBelowLine and not poi.projectedBelowLine)
assert(resource.overlapGroup~=poi.overlapGroup)
''', modules=RENDER_MODULES, setup=REGIONS)

failures = []
for name, code, family, modules, setup, real_pixel in cases:
    try:
        lua = client(family)
        lua.execute(setup)
        if real_pixel:
            lua.eval('function(code,name) assert(loadstring(code,name))("Orbit_Compass",Addon) end')(
                (UI / "Rendering/Pixel.lua").read_text(encoding="utf-8"), "Rendering/Pixel.lua")
            lua.execute("Addon.Services.pixel=Addon.LibOrbitUI.Pixel:Create();mock.pixelDriver=mock.pixelEventFrame")
        load_modules(lua, modules)
        lua.execute(code)
        measured = lua.globals().mock
        details = []
        if measured.report:
            details.append(measured.report)
        if measured.auditStyleMetrics:
            metrics = measured.auditStyleMetrics
            details.append(f"{metrics.slots} slots, {metrics.masks} masks, {metrics.rings} rings, "
                           f"retained fixture heap delta {metrics.heapDelta:.3f} KiB")
        if measured.auditPixelMetrics:
            pixels = measured.auditPixelMetrics
            details.append(f"real Pixel: {pixels.layouts} layouts, {pixels.overlaps} overlap boundaries")
        print(f"PASS {name}" + ("; " + "; ".join(details) if details else ""))
    except Exception as error:
        failures.append(name)
        print(f"FAIL {name}: {error}")
print(f"{len(cases) - len(failures)}/{len(cases)} Compass live-resource scenarios passed")
raise SystemExit(bool(failures))
