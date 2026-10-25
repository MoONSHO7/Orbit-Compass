"""Check shipped landmark coroutine work bounds and publication with deterministic Lua instruction costs."""

from compass_harness import client

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
mock.profiler={active=true, stack={}, records={}, counts={}, nextID=0, exclusive=0, outer=0}
function mock.profiler:Count(_,label,amount) self.counts[label]=(self.counts[label] or 0)+(amount or 1) end
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
    lua = client(family, "C_AreaPoiInfo.GetAreaPOIForMap=function(mapID) return mapID==3 and mock.poiIDs or {} end")
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

# Spotlight re-runs every hosted search on each notification, so an unindexed first build must not notify per slice.
FIRST_BUILD_SEARCH = r'''
SetBudgeted(true)
local c,counts,records=P.compassLandmarks,mock.profiler.counts,mock.profiler.records
local notices={}
P:SetCompassLandmarkListener("spotlight",function()
  notices[#notices+1]={now=mock.now,unindexed=P:IsCompassLandmarkSearchUnindexed()}
end)
local function Search(text)
  local results=P:SearchCompassLandmarks(text,{},P:NewCompassSearchScratch())
  return #results
end
P:AcquireCompassLandmarkDemand("test",false)
local slices,searched=0,false
while c.state=="building" do
  if c.thread then debug.sethook(c.thread,function() mock.clock=mock.clock+.01 end,"",100) end
  mock.now=mock.now+.25
  P:StepCompassLandmarkDemand(.25)
  slices=slices+1; assert(slices<30000,"build did not settle")
  if not searched and #c.entries>=100 and P:IsCompassLandmarkSearchUnindexed() then
    searched=true
    assert(Search("Seperate")==0,"an unindexed first build ran the typo pass")
    assert(Search("Separate")>=12,"strict matches were withheld during the first build")
  end
end
debug.sethook()
assert(c.state=="complete" and searched and not P:IsCompassLandmarkSearchUnindexed())
assert(counts["Search/Unindexed"]==2 and counts["Search/FuzzySkipped"]==1 and records["Compass.Search.Fuzzy"]==nil)
assert(#notices==counts["Landmarks/Notify"],"listener notifications were not counted")
local unindexed,previous=0,nil
for _,notice in ipairs(notices) do
  if notice.unindexed then
    unindexed=unindexed+1
    assert(not previous or notice.now-previous>=1,"first-build notifications came less than a second apart")
    previous=notice.now
  end
end
assert(unindexed>10 and not notices[#notices].unindexed,"completion did not notify with its index")
assert(Search("Seperate")>0 and records["Compass.Search.Fuzzy"].calls==1,"the finished index did not restore typo matches")
'''

ABSENT_PROFILER = r'''
Addon.Services.profiler=nil
SetBudgeted(true)
P:AcquireCompassLandmarkDemand("test",false)
assert(Finish()>10)
assert(P.compassLandmarks.phaseStart==nil and P.compassLandmarks.phaseProfiler==nil)
'''

# The continent repeats every zone record and the native list puts the cave before its zone.
REPEATED_WORLD = r'''
mock.maps[4]={mapID=4,mapType=3,parentMapID=2,name="Second zone"}
mock.maps[31]={mapID=31,mapType=5,parentMapID=3,name="Cave"}
mock.reads={info={},titles=0,worldQuests=0,journal=0}
local order={mock.maps[31],mock.maps[2],mock.maps[3],mock.maps[4]}
local function X(mapID) return (mapID%10)/10+.05 end
C_Map.GetMapChildrenInfo=function() return order end
local pois={[3]={101,104,105},[2]={101,104,105,102,103},[4]={103}}
local primary={[101]=3,[104]=3,[105]=3,[102]=2,[103]=4}
C_AreaPoiInfo.GetAreaPOIForMap=function(mapID) return pois[mapID] or {} end
C_AreaPoiInfo.GetAreaPOIInfo=function(mapID,id)
  mock.reads.info[#mock.reads.info+1]=mapID..":"..id
  return {areaPoiID=id,name="Place "..id,position={x=X(mapID),y=id/1000},atlasName="poi",
    isPrimaryMapForPOI=primary[id]==mapID}
end
local quests={[31]={{5003,0}},[3]={{5001,0},{5003,1}},[4]={{5002,0}},[2]={{5001,1},{5003,2},{5002,1}}}
C_TaskQuest.GetQuestsOnMap=function(mapID)
  local list={}
  for i,q in ipairs(quests[mapID] or {}) do
    list[i]={questID=q[1],childDepth=q[2],x=X(mapID),y=q[1]/10000,questTagType=0}
  end
  return list
end
C_TaskQuest.GetQuestInfoByQuestID=function(id) mock.reads.titles=mock.reads.titles+1; return "Quest "..id end
C_QuestLog.IsWorldQuest=function() mock.reads.worldQuests=mock.reads.worldQuests+1; return true end
local repeated={[3]=true,[2]=true}
C_EncounterJournal.GetDungeonEntrancesForMap=function(mapID)
  return repeated[mapID] and {{areaPoiID=301,name="Depths",position={x=X(mapID),y=.5},journalInstanceID=9}} or {}
end
function EJ_GetInstanceInfo()
  mock.reads.journal=mock.reads.journal+1
  return nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,false
end
C_TaxiMap.GetTaxiNodesForMap=function(mapID)
  return repeated[mapID] and {{nodeID=201,name="Roost",position={x=X(mapID),y=.25},faction=0}} or {}
end
C_DeathInfo.GetGraveyardsForMap=function(mapID)
  return repeated[mapID] and {{graveyardID=401,name="Rest",position={x=X(mapID),y=.75}}} or {}
end
'''

REPEATED_RECORDS = r'''
local F,c=Addon.ClientFeatures,P.compassLandmarks
local function Reads()
  local reads={}
  for i,read in ipairs(mock.reads.info) do reads[i]=read end
  table.sort(reads)
  return table.concat(reads,",")
end
local function MapOf(key) return c.entries[c.positions[key]].mapID end
Build()
assert(c.state=="complete",c.state)
assert(Reads()=="2:102,3:101,3:104,3:105,4:103","continent copies of zone records skipped their reads: "..Reads())
assert(MapOf("poi:101")==3 and MapOf("poi:102")==2 and MapOf("poi:103")==4 and MapOf("poi:104")==3)
assert(MapOf("taxi:201")==3 and MapOf("graveyard:401")==3 and MapOf("poi:301")==3)
if F.tasks then
  assert(MapOf("quest:5003")==31,"an equal rank keeps the record of the map the native list returned first")
  assert(MapOf("quest:5001")==3 and MapOf("quest:5002")==4)
  assert(mock.reads.titles==4 and mock.reads.worldQuests==4,"losing quest copies read no title or quest type")
end
if F.journalClassification then
  assert(mock.reads.journal==1,"the losing continent entrance read no journal entry")
end
local journal=mock.reads.journal
mock.reads.info={}
local found=P:FindCompassLandmarkOnMap(3,Enum.SuperTrackingMapPinType.AreaPOI,104)
assert(found and found.key=="poi:104" and found.mapID==3)
assert(Reads()=="3:104" and mock.reads.journal==journal,"a map click reads only the clicked record")
'''


# Each map read counts per source; taxi lists repeat the continent's nodes on every map, as the client returns them.
SOURCE_WORLD = r'''
mock.reads, mock.generic = {}, {}
local function Read(source) mock.reads[source]=(mock.reads[source] or 0)+1 end
local children, zonesOf, continentOf = {}, {}, {}
for c=1,2 do
  local cid=1000+c
  mock.maps[cid]={mapID=cid,mapType=2,parentMapID=1,name="Continent "..c}
  children[#children+1]=mock.maps[cid]
  zonesOf[cid]={}
  for z=1,3 do
    local zid=10000+c*100+z
    mock.maps[zid]={mapID=zid,mapType=3,parentMapID=cid,name="Zone "..zid}
    children[#children+1]=mock.maps[zid]
    zonesOf[cid][z],continentOf[zid]=zid,cid
    mock.generic[zid]={zid*100+41,zid*100+42}
    for m=1,2 do
      local mid=zid*10+m
      mock.maps[mid]={mapID=mid,mapType=5,parentMapID=zid,name="Micro "..mid}
      children[#children+1]=mock.maps[mid]
      continentOf[mid]=cid
    end
  end
end
ZONE=10101
local function ZonesFor(mapID)
  if zonesOf[mapID] then return zonesOf[mapID] end
  return mock.maps[mapID] and mock.maps[mapID].mapType==3 and {mapID} or {}
end
local function Pos(mapID, zid, n)
  if mapID==zid then return {x=(n%9+1)/10,y=.5} end
  return {x=(zid%100)/4,y=(n%9+1)/10}
end
local function List(source, mapID, per, build)
  Read(source)
  local list={}
  for _,zid in ipairs(ZonesFor(mapID)) do for n=1,per do list[#list+1]=build(zid,n,Pos(mapID,zid,n)) end end
  return list
end
local function Ids(source, mapID, values)
  Read(source)
  local ids={}
  for _,zid in ipairs(ZonesFor(mapID)) do for _,id in ipairs(values(zid)) do ids[#ids+1]=id end end
  return ids
end
C_Map.GetMapChildrenInfo=function() Read("children") return children end
C_Map.GetMapRectOnMap=function() Read("mapRect") return .4,.6,.4,.6 end
C_Map.CanSetUserWaypointOnMap=function() Read("canWaypoint") return true end
C_Map.IsCityMap=function() Read("isCity") return false end
C_EncounterJournal.GetDungeonEntrancesForMap=function(mapID)
  return List("entrances",mapID,1,function(zid,n,p) return {areaPoiID=zid*100+n,name="Dungeon "..zid,position=p} end)
end
C_Map.GetMapLinksForMap=function(mapID)
  return List("links",mapID,1,function(zid,n,p) return {areaPoiID=zid*100+20+n,name="Link "..zid,position=p} end)
end
C_DeathInfo.GetGraveyardsForMap=function(mapID)
  return List("graveyards",mapID,2,function(zid,n,p) return {graveyardID=zid*10+n,name="Rest "..zid.."-"..n,position=p} end)
end
C_TaxiMap.GetTaxiNodesForMap=function(mapID)
  Read("taxi")
  local cid,list=continentOf[mapID] or mapID,{}
  for _,zid in ipairs(zonesOf[cid] or {}) do
    local shown=mapID==zid or mapID==cid
    list[#list+1]={nodeID=zid,name="Roost "..zid,faction=0,position=shown and Pos(mapID,zid,7) or {x=2,y=2}}
  end
  return list
end
C_PetInfo.GetPetTamersForMap=function(mapID)
  return List("tamers",mapID,1,function(zid,n,p) return {areaPoiID=zid*100+30+n,name="Tamer "..zid,position=p} end)
end
C_AreaPoiInfo.GetAreaPOIForMap=function(mapID) return Ids("generic",mapID,function(zid) return mock.generic[zid] end) end
C_AreaPoiInfo.GetEventsForMap=function(mapID) return Ids("events",mapID,function(zid) return {zid*100+60} end) end
C_AreaPoiInfo.GetAreaPOIInfo=function(mapID,id)
  Read("poiInfo")
  local zid=math.floor(id/100)
  return {areaPoiID=id,name="Place "..id,position=Pos(mapID,zid,id%100),atlasName="poi",isPrimaryMapForPOI=mapID==zid}
end
C_TaskQuest.GetQuestsOnMap=function(mapID)
  return List("tasks",mapID,1,function(zid,n,p) return {questID=zid*10+n,x=p.x,y=p.y,questTagType=0} end)
end
C_TaskQuest.GetQuestInfoByQuestID=function(id) return "Task "..id end
'''

AGED_REFRESH = r'''
local FIXED={"children","canWaypoint","isCity","mapRect","entrances","links","taxi","graveyards"}
local function Build()
  local c,steps=P.compassLandmarks,0
  while c.state=="building" or c.state=="pending" do
    steps=steps+1;assert(steps<1000,"build did not settle")
    mock.now=mock.now+.01
    if P.compassLandmarkDriver.OnUpdate then P:StepCompassLandmarkDemand(.01) end
  end
  assert(c.state=="complete",c.state)
end
local function Snapshot()
  local c,rows=P.compassLandmarks,{}
  for i,entry in ipairs(c.entries) do
    rows[i]=entry.key..":"..entry.name..":"..entry.mapID..":"..entry.x..":"..entry.y..":"..entry.kind
  end
  return table.concat(rows,"|").."#"..c.queryIndex.blob
end
local function Refresh()
  wipe(mock.reads);mock.now=mock.now+301
  P:AcquireCompassLandmarkDemand("test",false);Build()
end
P:AcquireCompassLandmarkDemand("test",false);Build()
for _,source in ipairs(FIXED) do assert(mock.reads[source],"the first build skipped "..source) end
local first=Snapshot()
Refresh()
for _,source in ipairs(FIXED) do assert(not mock.reads[source],"an aged refresh re-read fixed "..source) end
assert(mock.reads.generic and mock.reads.poiInfo and mock.reads.events,"an aged refresh skipped changing places")
assert(Snapshot()==first,"a refresh over unchanged data changed the catalog")
mock.generic[ZONE][#mock.generic[ZONE]+1]=ZONE*100+49
Refresh()
local refreshed=Snapshot()
assert(P.compassLandmarks.positions["poi:"..(ZONE*100+49)],"an aged refresh missed a new place")
P:StopCompassLandmarks();P:InitializeCompassLandmarks();wipe(mock.reads)
P:AcquireCompassLandmarkDemand("test",false);Build()
assert(mock.reads.children,"a stopped catalog kept its fixed layer")
assert(Snapshot()==refreshed,"an aged refresh differs from a full rebuild")
'''


def aged_refresh_sources(family):
    lua = client(family, SOURCE_WORLD)
    lua.execute(AGED_REFRESH)
    print(f"PASS {family}: aged refreshes re-read only changing sources and equal a full rebuild")


def repeated_records(family):
    lua = client(family, REPEATED_WORLD)
    lua.execute(REPEATED_RECORDS)
    print(f"PASS {family}: repeated records skip losing reads and keep native-order ties")


EMPTY_LIST_COSTS = r'''
mock.clock,mock.nativeCalls,mock.overdueCalls=0,0,0
local specs={
 {C_EncounterJournal,"GetDungeonEntrancesForMap"},
 {C_AreaPoiInfo,"GetDelvesForMap"},{C_AreaPoiInfo,"GetEventsForMap"},
 {C_AreaPoiInfo,"GetDragonridingRacesForMap"},{C_AreaPoiInfo,"GetQuestHubsForMap"},
 {C_AreaPoiInfo,"GetAreaPOIForMap"},{C_Map,"GetMapLinksForMap"},
 {C_PetInfo,"GetPetTamersForMap"},{C_TaxiMap,"GetTaxiNodesForMap"},
 {C_ResearchInfo,"GetDigSitesForMap"},{C_TaskQuest,"GetQuestsOnMap"},
 {C_DeathInfo,"GetGraveyardsForMap"},{C_InvasionInfo,"GetInvasionForUiMapID"},
}
for _,spec in ipairs(specs) do
 local base=spec[1][spec[2]]
 spec[1][spec[2]]=function(...)
  if P.compassLandmarks and mock.clock>=P.compassLandmarks.deadline then
   mock.overdueCalls=mock.overdueCalls+1
  end
  mock.clock=mock.clock+.8;mock.nativeCalls=mock.nativeCalls+1
  return base(...)
 end
end
debugprofilestop=function() return mock.clock end
'''


def empty_list_boundaries(family):
    for focused, budget in ((False, 1), (True, 4)):
        lua = client(family, EMPTY_LIST_COSTS)
        lua.globals().focused = focused
        lua.globals().budget = budget
        lua.execute(r'''
CountWalks()
P:AcquireCompassLandmarkDemand("test",focused)
local c=P.compassLandmarks
local function Step()
 local before=mock.clock
 P:StepCompassLandmarkDemand(.01)
 assert(mock.clock-before<budget+.800001,"empty native queries accumulated past the slice budget")
end
Step()
local thread,reads=c.thread,mock.nativeCalls
P:ReleaseCompassLandmarkDemand("test")
assert(P.compassLandmarkDriver.OnUpdate==nil)
Drive(3)
assert(c.thread==thread and mock.nativeCalls==reads,"paused list retrieval resumed")
P:AcquireCompassLandmarkDemand("test",focused)
assert(c.thread==thread,"resuming an empty-list yield restarted the walk")
local steps=0
while c.state=="building" do Step();steps=steps+1;assert(steps<100) end
assert(c.state=="complete" and c.queryIndex.entries==c.entries)
assert(mock.walks==1 and mock.overdueCalls==0,"another native query ran after budget exhaustion")
assert(#c.entries==2,"ready-empty lists changed the area catalog")

mock.now=mock.now+301
P:AcquireCompassLandmarkDemand("test",focused)
Step()
local previous=c.entries
local retired=setmetatable({c.thread,c.target},{__mode="v"})
P:StopCompassLandmarks()
thread=nil
collectgarbage("collect");collectgarbage("collect")
assert(next(retired)==nil and c.entries==previous,"cancelled refresh retained its suspended list or target")
assert(P.compassLandmarkDriver.OnUpdate==nil)

P:AcquireCompassLandmarkDemand("test",focused)
Step()
local retiredThread=setmetatable({c.thread},{__mode="v"})
mock.maps[110]={mapID=110,mapType=0,parentMapID=0,name="Other cosmos"}
mock.maps[101]={mapID=101,mapType=1,parentMapID=110,name="Other world"}
mock.maps[102]={mapID=102,mapType=2,parentMapID=101,name="Other continent"}
mock.maps[103]={mapID=103,mapType=3,parentMapID=102,name="Other zone"}
mock.playerMap=103
C_Map.GetMapChildrenInfo=function(root)
 assert(root==(Addon.ClientFeatures.family=="retail" and 110 or 101),"old root resumed after replacement")
 return {mock.maps[102],mock.maps[103]}
end
P:InvalidateCompassLandmarkScope()
collectgarbage("collect");collectgarbage("collect")
assert(next(retiredThread)==nil,"root replacement retained the suspended native list")
steps=0
while c.state=="building" do Step();steps=steps+1;assert(steps<100) end
assert(c.state=="complete" and #c.entries==2 and c.queryIndex.entries==c.entries)
for _,entry in ipairs(c.entries) do assert(entry.mapID>=100,"retired root published a landmark") end
''')
    print(f"PASS {family}: empty native lists respect budgets, pause, cancellation and root replacement")


for family in ("retail", "forever"):
    check("large build, pause, refresh cancellation and equivalent publication", LIFECYCLE, family)
    check("focused budget and indivisible native/blob attribution", FOCUSED, family)
    check("collector failure closes all phase spans", FAILURE, family)
    check("unindexed first-build searches skip typo scans and notify at most once a second", FIRST_BUILD_SEARCH, family)
    check("standalone build without profiler", ABSENT_PROFILER, family)
    repeated_records(family)
    empty_list_boundaries(family)
    aged_refresh_sources(family)

print("16/16 landmark budget scenarios passed (large builds: 12640 POIs and 12642 child records each)")
