"""Audit live-resource publication and marker actions with shipped Compass modules in Lua 5.1."""

import ast
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
HARNESS = ROOT / ".scripts/check-client-features.py"
tree = ast.parse(HARNESS.read_text(encoding="utf-8"), filename=str(HARNESS))
boundary = next(i for i, node in enumerate(tree.body) if isinstance(node, ast.Assign)
                and any(isinstance(target, ast.Name) and target.id == "tests" for target in node.targets))
tree.body = tree.body[:boundary]
harness = {"__file__": str(HARNESS)}
exec(compile(tree, str(HARNESS), "exec"), harness)

RESOURCE_HOST = r'''
mock.loaded.Orbit=true
mock.nodes={{north=300,west=200,icon=134414,name="Peacebloom",lastSeen=mock.now}}
mock.resourceReads,mock.resourceProjects=0,0
Addon.OrbitHost={MapDots={GetResourceObservations=function()
 mock.resourceReads=mock.resourceReads+1;return mock.nodes,#mock.nodes,42
end},MapWorldCoordinates={WorldToMap=function(_,instance,north,west,mapID)
 assert(instance==42);mock.resourceProjects=mock.resourceProjects+1
 return mapID,west/1000,north/1000
end}}
mock.visible=true
P.frame={IsVisible=function()return mock.visible end}
P.markerClock,P.sortElapsed=0,0
function P:HideCompassPeek()end
function P:PauseCompassPinLandmarks()end
function P:RefreshCompassBearings()mock.rendered=#self.markers end
function P:UpdateCompassAutoAdvance()end
function P:LayoutCompassArtwork()return false end
function Tick(seconds)
 mock.now=mock.now+seconds
 P:UpdateCompass(seconds)
end
'''

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

tests = []


def check(name, code, family="forever", modules=(), setup=RESOURCE_HOST, real_pixel=False):
    tests.append((name, code, family, modules, setup, real_pixel))


check("published resources expire before first render after hidden resume", r'''
Drain();assert(#P.compassSources.resources.markers==1 and not P.discoveryJob)
mock.visible=false;mock.nodes={};Tick(10)
assert(P.discoveryClock==0)
mock.visible=true;Tick(1/60)
assert(mock.rendered==0 and #P.compassSources.resources.markers==0)
''')

check("published resources retire while an unrelated collector remains suspended", r'''
Drain();assert(#P.compassSources.resources.markers==1)
function P:CollectCompassLocations(markers)
 for i=1,5000 do self:CompassDiscoveryCheckpoint()end
end
local locations=P.compassSources.locations
locations.dirty,locations.nextAllowed=true,0
Tick(.21)
assert(P.discoveryJob and P.discoveryJob.definition.key=="locations")
mock.nodes={}
for i=1,20 do Tick(1/60)end
assert(P.discoveryJob and P.discoveryJob.definition.key=="locations")
assert(mock.rendered==0 and #P.compassSources.resources.markers==0)
''')

check("published reconciliation cannot invalidate a paused comparison array", r'''
mock.nodes={}
for i=1,64 do mock.nodes[i]={north=i,west=i,icon=123,name="Node",lastSeen=mock.now}end
Drain();assert(#P.compassSources.resources.markers==64)
P.discoveryClock=.21;mock.now=1.21
P:DiscoverCompassMarkers();P:DiscoverCompassMarkers()
assert(P.discoveryJob and P.discoveryJob.definition.key=="resources")
mock.nodes={};mock.now=4
Tick(1/60)
for i=1,12 do Tick(1/60)end
assert(#P.compassSources.resources.markers==0)
''')

check("renewed identities recover after published cache replacement during comparison", r'''
mock.nodes={}
for i=1,64 do mock.nodes[i]={north=i,west=i,icon=123,name="Node",lastSeen=mock.now}end
Drain();assert(#P.compassSources.resources.markers==64)
P.discoveryClock=.21;mock.now=1.21
P:DiscoverCompassMarkers();P:DiscoverCompassMarkers()
assert(P.discoveryJob and P.discoveryJob.definition.key=="resources")
mock.now=4;Tick(1/60)
assert(P.discoveryJob and #P.compassSources.resources.markers==0)
for _,node in ipairs(mock.nodes)do node.lastSeen=mock.now end
Tick(1/60);Tick(1/60)
assert(#P.compassSources.resources.markers==64)
''')

check("world-context changes remove published resources before rendering", r'''
Drain();assert(#P.compassSources.resources.markers==1)
mock.nodes={};P:InvalidateCompassSource("UNIT_PHASE");Tick(1/60)
assert(mock.rendered==0 and #P.compassSources.resources.markers==0)
''')

check("Retail never queries the Forever provider during ordinary updates", r'''
for i=1,90 do Tick(1/30)end
assert(mock.resourceReads==0 and mock.resourceProjects==0)
assert(P.compassSources.resources.status=="unsupported")
''', family="retail")

check("coincident waypoint cannot acquire a live resource identity or Search action", r'''
assert(P:SetWaypoint(3,.2,.3,"Camp"))
Drain()
local waypoint
for _,marker in ipairs(P.markers)do if marker.key=="waypoint"then waypoint=marker end end
assert(waypoint and waypoint.kind=="waypoint" and not waypoint.texture)
assert(waypoint.navigation and not waypoint.sourceKey)
local results={};P:SearchCompassLandmarks("Camp",results,P:NewCompassSearchScratch())
assert(#results==0 and mock.waypoints==1)
''', modules=("Discovery/CompassSources.lua",))

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
''', family=family, modules=("Discovery/CompassSources.lua",))

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
P.compassSources.resources.markers={marker}
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

for family in ("forever", "retail"):
    check(f"{family} resource heading reservation follows publication and preserves empty layout", r'''
local C=Addon.Constants
local pixel=Addon.Services.pixel
assert(not Addon.OrbitHost and #P.compassSources.resources.markers==0)
for _,height in ipairs({720,1080,2160})do
 mock.physicalHeight=height;mock.pixelDriver.scripts.OnEvent()
 for _,scale in ipairs({.64,1,1.5})do
  mock.scale=scale;mock.centerX,mock.centerY=123.123,345.456
  for _,size in ipairs({C.ICON_MIN,C.DEFAULT_ICON_SIZE,C.ICON_MAX})do
   P.iconSize=size
   P.compassSources.resources.markers={}
   assert(P:LayoutCompassArtwork())
   local emptyHeading,emptyDetail=P.artworkLayout.headingY,P.detail.point[5]
   local writes=mock.regionWrites
   for index=1,100 do assert(P:LayoutCompassArtwork())end
   assert(mock.regionWrites==writes,"empty standalone layout has no repeated region writes")
   local marker=MakeMarker("resource:1","resource",true)
   P.compassSources.resources.markers={marker}
   assert(P:LayoutCompassArtwork())
   local withResource=P.artworkLayout.headingY
   if Addon.ClientFeatures.sources.resources then
    assert(withResource<=emptyHeading and mock.regionWrites>writes,"arrival reserves at least the existing row clearance")
    Near(P.detail.point[5]-emptyDetail,withResource-emptyHeading,"details follow the heading movement")
   else
    Near(withResource,emptyHeading,"Retail ignores accidental resource rows")
    assert(mock.regionWrites==writes,"Retail keeps the cached ordinary layout")
   end
   local regions=mock.regionCreates
   writes=mock.regionWrites
   for index=1,100 do
    marker.distance=index*100
    assert(P:LayoutCompassArtwork())
   end
   marker=MakeMarker("resource:replacement","resource",true)
   P.compassSources.resources.markers={marker}
   assert(P:LayoutCompassArtwork())
   Near(P.artworkLayout.headingY,withResource,"identity and distance do not move headings")
   assert(mock.regionWrites==writes and mock.regionCreates==regions,"unchanged reservation reuses its geometry")
   P.compassSources.resources.markers={}
   assert(P:LayoutCompassArtwork())
   Near(P.artworkLayout.headingY,emptyHeading,"removal restores ordinary heading geometry")
   Near(P.detail.point[5],emptyDetail,"removal restores ordinary detail geometry")
   writes=mock.regionWrites
   assert(P:LayoutCompassArtwork() and mock.regionWrites==writes,"removed resources leave no layout work")
  end
 end
end
''', family=family, modules=RENDER_MODULES+("Ribbon/CompassView.lua",), setup=PIXEL_REGIONS, real_pixel=True)

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
for name, code, family, modules, setup, real_pixel in tests:
    try:
        lua = harness["client"](family)
        lua.execute(setup)
        load = lua.eval('function(code,name) assert(loadstring(code,name))("Orbit_Compass",Addon) end')
        if real_pixel:
            load((harness["UI"] / "Rendering/Pixel.lua").read_text(encoding="utf-8"), "Rendering/Pixel.lua")
            lua.execute("Addon.Services.pixel=Addon.LibOrbitUI.Pixel:Create();mock.pixelDriver=mock.pixelEventFrame")
        for module in modules:
            load((ROOT / "Core" / module).read_text(encoding="utf-8"), module)
        lua.execute(code)
        metrics = lua.globals().mock.auditStyleMetrics
        if metrics:
            print(f"{family} style pool: {metrics.slots} slots, {metrics.masks} masks, "
                  f"{metrics.rings} rings; retained fixture heap delta {metrics.heapDelta:.3f} KiB")
        pixels = lua.globals().mock.auditPixelMetrics
        if pixels:
            print(f"{family} real Pixel: {pixels.layouts} layouts, {pixels.overlaps} overlap boundaries")
    except Exception as error:
        failures.append(name)
        print(f"FAIL {name}: {error}")
print(f"{len(tests) - len(failures)}/{len(tests)} Compass resource audit scenarios passed")
raise SystemExit(bool(failures))
