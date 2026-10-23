"""Check live-resource scheduler costs and retention with shipped Lua 5.1 owners; not native profiling."""

import ast
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
BOUNDARY_SUITE = ROOT / ".scripts/check-client-features.py"
tree = ast.parse(BOUNDARY_SUITE.read_text(encoding="utf-8"), filename=str(BOUNDARY_SUITE))
boundary = next(i for i, node in enumerate(tree.body) if isinstance(node, ast.Assign)
                and any(isinstance(target, ast.Name) and target.id == "tests" for target in node.targets))
tree.body = tree.body[:boundary]
harness = {"__file__": str(BOUNDARY_SUITE)}
exec(compile(tree, str(BOUNDARY_SUITE), "exec"), harness)
client = harness["client"]

SETUP = r'''
mock.resourceNodes={}
mock.resourcesAvailable=true
mock.loaded.Orbit=true
mock.resourceReads,mock.resourceProjects,mock.resourceCollections=0,0,0
mock.resourceValidations,mock.rebuilds,mock.renders=0,0,0
mock.resourceEmptyChecks,mock.resourceEmptyReuses=0,0
mock.renderedResources=0
Addon.OrbitHost={MapDots={GetResourceObservations=function()
 mock.resourceReads=mock.resourceReads+1
 if not mock.resourcesAvailable then return nil,0 end
 return mock.resourceNodes,#mock.resourceNodes,mock.resourceInstance or 42
end},MapWorldCoordinates={WorldToMap=function(_,instance,north,west,mapID)
 mock.resourceProjects=mock.resourceProjects+1
 if mock.projectionError then error("projection boundary failed") end
 return mapID,west/1000,north/1000
end}}
local collect=P.CollectCompassResources
local reuse=P.ReuseEmptyCompassResources
if reuse then
 function P:ReuseEmptyCompassResources(source)
  mock.resourceEmptyChecks=mock.resourceEmptyChecks+1
  local reused,interval=reuse(self,source)
  if reused then mock.resourceEmptyReuses=mock.resourceEmptyReuses+1 end
  return reused,interval
 end
end
function P:CollectCompassResources(markers)
 mock.resourceCollections=mock.resourceCollections+1
 return collect(self,markers)
end
local validate=P.ValidateCompassResources
function P:ValidateCompassResources(markers)
 mock.resourceValidations=mock.resourceValidations+1
 return validate(self,markers)
end
local rebuild=P.RebuildCompassMarkers
function P:RebuildCompassMarkers()
 mock.rebuilds=mock.rebuilds+1
 return rebuild(self)
end
function P:HideCompassPeek() end
function P:PauseCompassPinLandmarks() end
function P:RefreshCompassBearings() end
function P:UpdateCompassAutoAdvance() end
function P:LayoutCompassArtwork() return true end
function P:RenderCompass()
 mock.renders=mock.renders+1
 mock.renderedResources=0
 for _,marker in ipairs(self.markers) do
  if marker.kind=="resource" then mock.renderedResources=mock.renderedResources+1 end
 end
 self.renderDirty,self.renderFacing,self.renderInteractive=false,0,true
end
P.frame={IsVisible=function()return not mock.hidden end,
 Hide=function()mock.hidden=true end,Show=function()mock.hidden=false end}
P.navigationFrame={Hide=function()end}
P.events.RegisterUnitEvent=function()end
P.markerClock,P.sortElapsed=0,0
P.bearings={}
function ReplaceResources(count)
 mock.resourceNodes={}
 for i=1,count do
  mock.resourceNodes[i]={north=300+i,west=200+i,icon=123,name="Node "..i,lastSeen=mock.now}
 end
end
function RenewResources()
 for _,node in ipairs(mock.resourceNodes) do node.lastSeen=mock.now end
end
function AdvanceResources(seconds,fps,renew)
 for i=1,math.floor(seconds*fps+0.5) do
  mock.now=mock.now+1/fps
  if renew then RenewResources() end
  P:UpdateCompass(1/fps)
 end
end
function FinishDiscovery()
 for i=1,40 do P:DiscoverCompassMarkers() end
 assert(not P.discoveryJob)
end
function ResourceCount()
 return #P.compassSources.resources.markers
end
function WeakResourceCount()
 collectgarbage("collect");collectgarbage("collect")
 local count=0
 for key,value in pairs(P.compassResourceIDs) do
  count=count+1;assert(type(key)=="table" and type(value)=="number")
 end
 return count
end
'''

cases = []


def check(name, code, family="forever"):
    cases.append((name, code, family))


for fps in (30, 240):
    check(f"{fps} FPS unchanged resources reuse published markers", rf'''
ReplaceResources(1);FinishDiscovery()
local marker=P.compassSources.resources.markers[1]
local rebuilds=mock.rebuilds
mock.resourceReads,mock.resourceCollections,mock.resourceValidations,mock.resourceProjects=0,0,0,0
AdvanceResources(10,{fps},true)
assert(mock.resourceCollections<=51 and mock.resourceCollections>=40,tostring(mock.resourceCollections))
assert(mock.resourceProjects==mock.resourceCollections)
assert(mock.resourceReads<=mock.resourceCollections*2+51,
 "reads="..mock.resourceReads.." collections="..mock.resourceCollections.." validations="..mock.resourceValidations)
assert(mock.resourceValidations<=mock.resourceCollections+51,tostring(mock.resourceValidations))
assert(mock.rebuilds==rebuilds and P.compassSources.resources.markers[1]==marker)
assert(WeakResourceCount()==1)
mock.reportCost=true
''')

check("Dense resources keep source work and retained identities bounded", r'''
ReplaceResources(80);FinishDiscovery()
assert(ResourceCount()==64 and mock.resourceProjects==64)
local previous=P.compassSources.resources.markers
AdvanceResources(5,60,true)
assert(ResourceCount()==64 and P.compassSources.resources.markers==previous)
assert(mock.resourceProjects<=mock.resourceCollections*64)
assert(WeakResourceCount()==64)
mock.resourceNodes={};P.discoveryClock=P.discoveryClock+0.21;FinishDiscovery()
assert(ResourceCount()==0 and WeakResourceCount()==0)
''')

check("Two thousand source replacements retain only current state", r'''
ReplaceResources(64);FinishDiscovery()
for i=1,100 do
 ReplaceResources(64);P.discoveryClock=P.discoveryClock+0.21;FinishDiscovery()
end
collectgarbage("collect");collectgarbage("collect")
local warm=collectgarbage("count")
for i=1,2000 do
 ReplaceResources(64);P.discoveryClock=P.discoveryClock+0.21;FinishDiscovery()
end
local retained=WeakResourceCount()
local settled=collectgarbage("count")
assert(retained==64 and ResourceCount()==64)
assert(settled<=warm+64, tostring(settled-warm))
mock.resourceNodes={};P.discoveryClock=P.discoveryClock+0.21;FinishDiscovery()
assert(WeakResourceCount()==0 and ResourceCount()==0)
mock.heapWarm,mock.heapSettled=warm,settled
''')

for reason in ("unavailable", "expired"):
    check(f"First visible refresh retires {reason} published observations", rf'''
ReplaceResources(1);FinishDiscovery()
assert(ResourceCount()==1)
mock.hidden=true
local reads,collections=mock.resourceReads,mock.resourceCollections
AdvanceResources(10,60,false)
assert(mock.resourceReads==reads and mock.resourceCollections==collections)
if "{reason}"=="unavailable" then mock.resourcesAvailable=false end
mock.hidden=false;P.renderDirty=true
P:UpdateCompass(1/60)
assert(ResourceCount()==0 and mock.renderedResources==0)
''')

check("Empty sources poll without constructing collection jobs", r'''
ReplaceResources(0);FinishDiscovery()
mock.resourceReads,mock.resourceCollections,mock.resourceValidations=0,0,0
mock.resourceEmptyChecks,mock.resourceEmptyReuses=0,0
for key,source in pairs(P.compassSources) do
 if key~="resources" then source.nextRefresh=math.huge end
end
local jobs,create=0,coroutine.create
coroutine.create=function(fn)jobs=jobs+1;return create(fn)end
AdvanceResources(10,240,false)
assert(mock.resourceCollections==0,"empty collections="..mock.resourceCollections)
assert(jobs==0,"empty coroutines="..jobs)
assert(mock.resourceEmptyReuses<=51 and mock.resourceEmptyReuses>=40,tostring(mock.resourceEmptyReuses))
assert(mock.resourceReads==mock.resourceEmptyReuses and mock.resourceValidations==0)
assert(mock.resourceProjects==0 and ResourceCount()==0)
''')

check("Inactive scanner recovers through bounded polling without cache checks", r'''
mock.resourcesAvailable=false
FinishDiscovery()
mock.resourceReads,mock.resourceCollections,mock.resourceValidations=0,0,0
mock.resourceEmptyChecks,mock.resourceEmptyReuses=0,0
AdvanceResources(10,240,false)
assert(mock.resourceCollections==0,"unavailable collections="..mock.resourceCollections)
assert(mock.resourceEmptyReuses<=51 and mock.resourceEmptyReuses>=40,tostring(mock.resourceEmptyReuses))
assert(mock.resourceReads==mock.resourceEmptyReuses and mock.resourceValidations==0)
assert(mock.resourceProjects==0 and ResourceCount()==0)
mock.resourcesAvailable=true;ReplaceResources(1);AdvanceResources(0.5,60,true)
assert(ResourceCount()==1 and mock.resourceProjects>0)
''')

check("Positive observations retry previously unavailable projection", r'''
ReplaceResources(1)
local project=Addon.OrbitHost.MapWorldCoordinates.WorldToMap
Addon.OrbitHost.MapWorldCoordinates.WorldToMap=function()return nil end
FinishDiscovery();assert(ResourceCount()==0)
local collected=mock.resourceCollections
local reads=mock.resourceReads
AdvanceResources(0.5,60,true)
assert(mock.resourceCollections>collected and ResourceCount()==0)
assert(mock.resourceReads-reads==(mock.resourceCollections-collected)*3)
Addon.OrbitHost.MapWorldCoordinates.WorldToMap=project
AdvanceResources(0.5,60,true)
assert(ResourceCount()==1)
''')

check("Unknown observation counts retain collection and validation", r'''
ReplaceResources(0);FinishDiscovery()
local getter=Addon.OrbitHost.MapDots.GetResourceObservations
local values={false,{secret=true},-1,1}
for _,value in ipairs(values) do
 Addon.OrbitHost.MapDots.GetResourceObservations=function()
  mock.resourceReads=mock.resourceReads+1
  return {},value or nil,42
 end
 local collected,validated,reused=mock.resourceCollections,mock.resourceValidations,mock.resourceEmptyReuses
 AdvanceResources(0.25,60,false)
 assert(mock.resourceCollections>collected and mock.resourceValidations>validated)
 assert(mock.resourceEmptyReuses==reused)
end
Addon.OrbitHost.MapDots.GetResourceObservations=getter
AdvanceResources(0.25,60,false)
assert(mock.resourceEmptyReuses>0 and ResourceCount()==0)
''')

for recovery in ("deadline", "event"):
    check(f"Empty provider failure backs off before {recovery} recovery", rf'''
ReplaceResources(0);FinishDiscovery()
local getter=Addon.OrbitHost.MapDots.GetResourceObservations
local calls=0
Addon.OrbitHost.MapDots.GetResourceObservations=function()
 calls=calls+1;error("resource getter failed")
end
local source=P.compassSources.resources
source.dirty,source.pathDirty=true,true
local ok,message=pcall(AdvanceResources,0.25,60,false)
assert(not ok and message:find("resource getter failed",1,true))
assert(calls==1 and source.status=="failed" and source.reason=="collector")
assert(not source.dirty and not source.pathDirty and not P.discoveryJob)
local deadline=source.nextRefresh
assert(math.abs(deadline-P.discoveryClock-30)<.000001)
AdvanceResources(1,240,false);assert(calls==1)
Addon.OrbitHost.MapDots.GetResourceObservations=getter
ReplaceResources(1)
if "{recovery}"=="deadline" then
 AdvanceResources(28.5,60,true)
 assert(ResourceCount()==0 and P.discoveryClock<deadline)
 AdvanceResources(0.75,60,true)
else
 P:InvalidateCompassSource("ZONE_CHANGED_NEW_AREA")
 AdvanceResources(0.25,60,true)
 assert(P.discoveryClock<deadline)
end
assert(ResourceCount()==1 and source.status=="ready")
''')

check("Reused empty observations wake for replacement refinement and removal", r'''
ReplaceResources(0);FinishDiscovery()
AdvanceResources(1,60,false)
ReplaceResources(1);AdvanceResources(0.25,60,true)
assert(ResourceCount()==1)
local first=P.compassSources.resources.markers[1]
mock.resourceNodes[1].north=350
AdvanceResources(0.25,60,true)
assert(ResourceCount()==1 and P.compassSources.resources.markers[1].resourceObservation.north==350)
assert(P.compassSources.resources.markers[1]~=first)
mock.resourceNodes={};AdvanceResources(0.25,60,false)
assert(ResourceCount()==0)
mock.resourceCollections,mock.resourceEmptyReuses=0,0
AdvanceResources(1,60,false)
assert(mock.resourceCollections==0 and mock.resourceEmptyReuses>=4)
''')

check("Published resources expire while an unrelated discovery job is suspended", r'''
ReplaceResources(1);FinishDiscovery();assert(ResourceCount()==1)
local source=P.compassSources.quests
P.discoveryJob={source=source,definition={key="quests",label="Compass.Discovery.Quests"},
 countKey="quests",markers={},thread=coroutine.create(function()while true do coroutine.yield()end end)}
mock.resourceReads,mock.resourceCollections,mock.resourceValidations=0,0,0
AdvanceResources(4,240,false)
assert(ResourceCount()==0 and mock.resourceCollections==0)
assert(mock.resourceReads==mock.resourceValidations and mock.resourceReads<=11)
P.discoveryDirty=true;mock.resourceNodes={};P:UpdateCompass(1/60)
assert(not P.discoveryJob and ResourceCount()==0 and WeakResourceCount()==0)
''')

check("Collector errors cannot retain expired published resources until retry", r'''
ReplaceResources(1);FinishDiscovery();assert(ResourceCount()==1)
mock.projectionError=true
mock.now=mock.now+0.21
local ok,message=pcall(P.UpdateCompass,P,0.21)
assert(not ok and message:find("projection boundary failed",1,true))
assert(not P.discoveryJob and P.compassSources.resources.status=="failed")
local collections=mock.resourceCollections
AdvanceResources(3,60,false)
assert(ResourceCount()==0 and mock.resourceCollections==collections)
mock.projectionError=false;RenewResources();P:InvalidateCompassSource("ZONE_CHANGED_NEW_AREA")
AdvanceResources(0.5,60,true);assert(ResourceCount()==1)
''')

check("Retail never reads or validates the resource provider", r'''
ReplaceResources(64);FinishDiscovery();AdvanceResources(10,240,true)
assert(ResourceCount()==0 and mock.resourceReads==0 and mock.resourceProjects==0)
assert(mock.resourceCollections==0 and mock.resourceValidations==0)
assert(WeakResourceCount()==0)
''', "retail")

check("Standalone never collects unavailable hosted resources", r'''
Addon.OrbitHost=nil;mock.loaded.Orbit=false
FinishDiscovery();AdvanceResources(10,240,false)
assert(mock.resourceReads==0 and mock.resourceProjects==0 and mock.resourceCollections==0)
assert(ResourceCount()==0 and WeakResourceCount()==0)
''')

check("Older compatible host retires unsupported resource polling", r'''
Addon.OrbitHost={}
FinishDiscovery()
local collections=mock.resourceCollections
AdvanceResources(10,240,false)
assert(mock.resourceCollections==collections,tostring(mock.resourceCollections-collections))
assert(mock.resourceReads==0 and mock.resourceProjects==0 and ResourceCount()==0)
''')

check("Disable and re-enable release resource ownership across cycles", r'''
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
for cycle=1,128 do
 mock.disabled=false;P:OnEnable();P.frame:Show()
 ReplaceResources(64);FinishDiscovery();assert(ResourceCount()==64)
 mock.disabled=true;P:OnDisable()
 mock.resourceNodes={};assert(WeakResourceCount()==0 and ResourceCount()==0 and not P.discoveryJob)
 local reads=mock.resourceReads
 AdvanceResources(1,30,false);assert(mock.resourceReads==reads)
end
''')

AUTO_ADVANCE = (ROOT / "Core/Navigation/CompassAutoAdvance.lua").read_text(encoding="utf-8")
for fps in (10, 20, 30, 60, 240):
    for trigger in ("arrival", "removal"):
        check(f"Dense resources allow {trigger} auto-advance at {fps} FPS", rf'''
assert(loadstring([==[{AUTO_ADVANCE}]==],"CompassAutoAdvance.lua"))("Orbit_Compass",Addon)
local longest=0
for offset=0,9 do
 P:InitializeCompassDiscovery()
 mock.advanceAt=nil;mock.poiIDs={{1,2}}
 C_AreaPoiInfo.GetAreaPOIInfo=function(_,id)
  return {{areaPoiID=id,name="Point "..id,position={{x=id==1 and .5 or .51,y=.5}},atlasName="test"}}
 end
 ReplaceResources(64);FinishDiscovery()
 P.autoAdvanceMode,P.autoAdvanceSameType,P.range="arrival",false,100
 P.bearingPlayerX,P.bearingPlayerY=.5,.5
 P.navigationKey="waypoint";P.navigationTarget={{distance=50}}
 assert(P:SetWaypoint(3,.5,.5,"Start",nil,"poi:1"));FinishDiscovery()
 P:UpdateCompassAutoAdvance();assert(P.compassAutoAdvance)
 P.compassAutoAdvanceNext=P.discoveryClock+offset*.025
 local original=C_Map.SetUserWaypoint
 C_Map.SetUserWaypoint=function(point)
  if point.position.x==.51 then mock.advanceAt=mock.now end
  return original(point)
 end
 if "{trigger}"=="arrival" then P.navigationTarget.distance=1
 else mock.poiIDs={{2}};P:InvalidateCompassSource("AREA_POIS_UPDATED") end
 local started=mock.now
 for i=1,{fps * 20} do
  mock.now=mock.now+1/{fps};RenewResources();P:UpdateCompass(1/{fps})
  if mock.advanceAt then break end
 end
 C_Map.SetUserWaypoint=original
 assert(mock.advanceAt,"starved at phase "..offset)
 local latency=mock.advanceAt-started
 longest=math.max(longest,latency)
 assert(latency<5,"progress delayed "..latency.." seconds at phase "..offset)
end
mock.advanceLatency=longest
''')

failed = []
for name, code, family in cases:
    try:
        lua = client(family)
        lua.execute(SETUP + code)
        measured = lua.globals().mock
        heap = ""
        if measured.heapWarm is not None:
            heap = f"; retained fixture heap {measured.heapWarm:.1f} -> {measured.heapSettled:.1f} KiB"
        if measured.reportCost:
            heap += (f"; 10 s: {measured.resourceCollections} collections, "
                     f"{measured.resourceReads} getter reads, {measured.resourceValidations} validations")
        if measured.advanceLatency is not None:
            heap += f"; longest transition {measured.advanceLatency:.3f} s across ten phases"
        print(f"PASS {name}{heap}")
    except Exception as error:
        failed.append(name)
        print(f"FAIL {name}: {error}")

print(f"{len(cases)-len(failed)}/{len(cases)} resource performance/lifecycle scenarios passed")
raise SystemExit(bool(failed))
