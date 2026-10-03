"""Check shipped landmark coroutine work bounds and publication with deterministic Lua instruction costs."""

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

CORPUS = r'''
mock.clock, mock.childrenReads, mock.entryCount = 0, 0, 12640
mock.children = {mock.maps[2], mock.maps[3]}
for id=1,mock.entryCount do
  mock.children[#mock.children+1] = {mapID=100+id, mapType=0, parentMapID=1, name="Child "..id}
end
C_Map.GetMapChildrenInfo=function()
  mock.childrenReads=mock.childrenReads+1
  mock.clock=mock.clock+6
  return mock.children
end
local ids={}
for id=1,mock.entryCount do ids[id]=id end
mock.poiIDs=ids
C_AreaPoiInfo.GetAreaPOIInfo=function(_,id)
  local name, x, y="Landmark "..id, id/(mock.entryCount+1), .2
  if id<=64 then name="Separate repeated name" end
  if id>=100 and id<=110 then name,x,y="Same place",.9,.9 end
  return {areaPoiID=id,name=name,position={x=x,y=y},atlasName="test"}
end
C_Map.GetWorldPosFromMapPos=function(_,p) return 42,{x=p.x*10000000,y=p.y*10000000} end
local concat=table.concat
table.concat=function(list,separator,...)
  if separator=="\n" and #list>12000 then mock.clock=mock.clock+1.5 end
  return concat(list,separator,...)
end
debugprofilestop=function() return mock.clock end
mock.profiler={active=true, stack={}, records={}, nextID=0, exclusive=0, outer=0}
function mock.profiler:Begin()
  self.nextID=self.nextID+1
  self.stack[#self.stack+1]={id=self.nextID,started=mock.clock,children=0}
  return self.nextID,0
end
function mock.profiler:End(_,label,id)
  local frame=self.stack[#self.stack]
  assert(frame and frame.id==id,"unbalanced profiler stack at "..label)
  self.stack[#self.stack]=nil
  local duration=mock.clock-frame.started
  local exclusive=duration-frame.children
  assert(exclusive>=-.000001,"negative exclusive duration")
  self.exclusive=self.exclusive+exclusive
  local parent=self.stack[#self.stack]
  if parent then parent.children=parent.children+duration else self.outer=self.outer+duration end
  local record=self.records[label] or {calls=0,max=0,total=0}
  record.calls,record.max,record.total=record.calls+1,math.max(record.max,duration),record.total+duration
  self.records[label]=record
end
Addon.Services.profiler=mock.profiler
function SetBudgeted(enabled)
  mock.budgeted=enabled
  if enabled then
    debugprofilestop=function() return mock.clock end
  else
    debug.sethook()
    debugprofilestop=function() return 0 end
  end
end
function Step()
  local c=P.compassLandmarks
  local entries,revision=c.entries,c.revision
  if mock.budgeted and c.thread then
    debug.sethook(c.thread,function() mock.clock=mock.clock+.01 end,"",100)
  end
  mock.now=mock.now+.01
  if P.compassLandmarkDriver.OnUpdate then P:StepCompassLandmarkDemand(.01) end
  assert(#mock.profiler.stack==0,"span escaped its resume")
  assert(c.queryIndex==nil or c.queryIndex.entries==c.entries,"split query/entry publication")
  assert(c.entries==entries or c.revision~=revision or c.state~="building","unannounced publication")
end
function Finish()
  local steps=0
  while P.compassLandmarks.state=="building" do
    steps=steps+1; assert(steps<30000,"build did not settle")
    Step()
  end
  assert(P.compassLandmarks.state=="complete",P.compassLandmarks.state)
  assert(#mock.profiler.stack==0)
  return steps
end
function Snapshot()
  local c=P.compassLandmarks
  assert(c.queryIndex.entries==c.entries)
  local rows={}
  for i,entry in ipairs(c.entries) do
    assert(c.positions[entry.key]==i)
    rows[i]=entry.key..":"..entry.name..":"..entry.mapID
  end
  return table.concat(rows,"|"),c.queryIndex.blob,#c.entries
end
function CheckPhases(budget)
  local phases={
    ["Compass.Landmarks.Children.Native"]=6.1,
    ["Compass.Landmarks.Children.Copy"]=budget+.1,
    ["Compass.Landmarks.Collect"]=budget+.1,
    ["Compass.Landmarks.Duplicates.Group"]=budget+.1,
    ["Compass.Landmarks.Duplicates.Compare"]=budget+.1,
    ["Compass.Landmarks.Duplicates.Compact"]=budget+.1,
    ["Compass.Landmarks.QueryIndex.Entries"]=budget+.1,
    ["Compass.Landmarks.QueryIndex.Blob"]=1.6,
  }
  for label,limit in pairs(phases) do
    local record=assert(mock.profiler.records[label],"missing phase "..label)
    assert(record.max<=limit,label.." exceeded bound: "..record.max.." > "..limit)
  end
  for label in pairs(mock.profiler.records) do
    assert(phases[label] or label=="Compass.Landmarks","unbounded label "..label)
  end
  assert(mock.profiler.records["Compass.Landmarks.Children.Native"].max>=6)
  assert(mock.profiler.records["Compass.Landmarks.QueryIndex.Blob"].max>=1.5)
  assert(math.abs(mock.profiler.exclusive-mock.profiler.outer)<.00001,"nested time double counted")
end
'''


def fixture(family):
    lua = harness["client"](family, "C_AreaPoiInfo.GetAreaPOIForMap=function(mapID) return mapID==3 and mock.poiIDs or {} end")
    lua.execute(CORPUS)
    return lua


def check(name, code, family):
    lua = fixture(family)
    try:
        lua.execute(code)
    finally:
        lua.execute("debug.sethook()")
    print(f"PASS {family}: {name}")


LIFECYCLE = r'''
SetBudgeted(false)
P:AcquireCompassLandmarkDemand("test",false)
assert(Finish()==1)
local expected,blob,count=Snapshot()
assert(count>12000)

P:StopCompassLandmarks(); P:InitializeCompassLandmarks()
wipe(mock.profiler.records); mock.profiler.exclusive,mock.profiler.outer=0,0
SetBudgeted(true)
P:AcquireCompassLandmarkDemand("test",false)
Step()
assert(P.compassLandmarks.phase=="Compass.Landmarks.Children.Native")
assert(#P.compassLandmarks.entries==0,"native call overrun continued into copying")
Step()
assert(P.compassLandmarks.phase=="Compass.Landmarks.Children.Copy")
local thread=P.compassLandmarks.thread
P:ReleaseCompassLandmarkDemand("test")
local clock,reads=mock.clock,mock.childrenReads
assert(P.compassLandmarkDriver.OnUpdate==nil)
for i=1,5 do Step() end
assert(P.compassLandmarks.thread==thread and mock.childrenReads==reads)
P:AcquireCompassLandmarkDemand("test",false)
assert(P.compassLandmarks.thread==thread)
assert(Finish()>10)
local actual,actualBlob,actualCount=Snapshot()
assert(actual==expected and actualBlob==blob and actualCount==count,"budget changed publication")
CheckPhases(1)

local c=P.compassLandmarks
local previous,previousIndex=c.entries,c.queryIndex
mock.now=mock.now+301
P:AcquireCompassLandmarkDemand("test",false)
Step(); Step()
assert(c.entries==previous and c.queryIndex==previousIndex,"refresh replaced published snapshot early")
P:StopCompassLandmarks()
assert(c.thread==nil and c.target==nil and next(c.demand)==nil and P.compassLandmarkDriver.OnUpdate==nil)
assert(#mock.profiler.stack==0)
P:AcquireCompassLandmarkDemand("test",false)
Finish()
local renewed,renewedBlob=Snapshot()
assert(renewed==expected and renewedBlob==blob,"cancelled refresh did not recover")
CheckPhases(1)
'''

FOCUSED = r'''
SetBudgeted(true)
P:AcquireCompassLandmarkDemand("test",true)
assert(Finish()>5)
CheckPhases(4)
'''

FAILURE = r'''
SetBudgeted(true)
P:AcquireCompassLandmarkDemand("test",false)
Step()
assert(P.compassLandmarks.phase=="Compass.Landmarks.Children.Native")
C_AreaPoiInfo.GetAreaPOIInfo=function() error("synthetic collector failure") end
local ok,message=true,nil
for i=1,30000 do
  ok,message=pcall(Step)
  if not ok then break end
end
assert(not ok and string.find(message,"synthetic collector failure",1,true))
assert(P.compassLandmarks.state=="failed" and P.compassLandmarks.thread==nil)
assert(#mock.profiler.stack==0,"error left phase span open")
assert(math.abs(mock.profiler.exclusive-mock.profiler.outer)<.00001)
'''

ABSENT_PROFILER = r'''
Addon.Services.profiler=nil
SetBudgeted(true)
P:AcquireCompassLandmarkDemand("test",false)
assert(Finish()>10)
assert(P.compassLandmarks.phaseStart==nil and P.compassLandmarks.phaseProfiler==nil)
'''

for family in ("retail", "forever"):
    check("large build, pause, refresh cancellation and equivalent publication", LIFECYCLE, family)
    check("focused budget and indivisible native/blob attribution", FOCUSED, family)
    check("collector failure closes all phase spans", FAILURE, family)
    check("standalone build without profiler", ABSENT_PROFILER, family)

print("8/8 landmark budget scenarios passed (12640 POIs and 12642 child records each)")
