"""Check the QuestieDB adapter against a double of QuestieDB's documented contract-4 API in Lua 5.1; not a WoW runtime test."""

from compass_harness import client

# QuestieDB's public read semantics (docs/api.md): numeric getters return 0, empty tables come back nil, unknown ids are
# nil everywhere, GetAll returns a packed table, and the area-to-UiMap table is Lua source the consumer loads.
QUESTIE = r'''
mock.loaded.QuestieDB=true
mock.done,mock.log,mock.rep={},{},{}
mock.maps[5]={mapID=5,mapType=3,parentMapID=3,name="City"}
local children=C_Map.GetMapChildrenInfo
C_Map.GetMapChildrenInfo=function(id,...) if id==3 then return {mock.maps[5]} end return children(id,...) end
function P:ProjectCompassDestination(mapID,x,y) if mapID==self.mapID or mapID==5 then return {x=x,y=y} end end
function UnitClass() return "Warrior","WARRIOR",1 end
function UnitRace() return "Orc","Orc",2 end
function UnitLevel() return 30 end
function UnitFactionGroup() return "Horde" end
function UnitQuestTrivialLevelRange() return 7 end
function GetRealZoneText(id) return ({[43]="Wailing Caverns"})[id] or "" end
C_Minimap.IsTrackingHiddenQuests=function() return mock.trivial==true end
C_QuestLog.IsQuestFlaggedCompleted=function(id) return mock.done[id]==true end
C_QuestLog.GetLogIndexForQuestID=function(id) return mock.log[id] end
C_QuestLog.GetTitleForQuestID=function(id) return "Quest "..id end
C_Reputation.GetFactionDataByID=function(id) return mock.rep[id] and {currentStanding=mock.rep[id]} end
Enum.MinimapTrackingFilter=Enum.MinimapTrackingFilter or {Innkeeper=32,Repair=512,Banker=2,Auctioneer=1,Stablemaster=2048}
local tracking={{name="Innkeeper",texture=1001,filter=32},{name="Repair",texture=1002,filter=512}}
C_Minimap.GetNumTrackingTypes=function() return #tracking end
C_Minimap.GetTrackingInfo=function(i) return {name=tracking[i].name,texture=tracking[i].texture} end
C_Minimap.GetTrackingFilter=function(i) return {filterID=tracking[i].filter} end
local QUEST_FIELDS={"requiredLevel","questLevel","requiredRaces","requiredClasses","preQuestGroup","preQuestSingle",
 "exclusiveTo","zoneOrSort","requiredSkill","requiredMinRep","requiredMaxRep","nextQuestInChain","specialFlags",
 "parentQuest","breadcrumbForQuestId","requiredSpell","requiredSpecialization","requiredMaxLevel",
 "availableUntilCompleted","availableStartingWith","requiredRanks","disabledByQuest"}
local NUMERIC={requiredLevel=1,questLevel=1,requiredRaces=1,requiredClasses=1,zoneOrSort=1,nextQuestInChain=1,
 specialFlags=1,parentQuest=1,breadcrumbForQuestId=1,requiredSpell=1,requiredSpecialization=1,requiredMaxLevel=1,
 availableUntilCompleted=1,availableStartingWith=1,disabledByQuest=1}
Quests={[10]={questLevel=28},[11]={questLevel=28},[12]={questLevel=28,preQuestSingle={99}},
 [13]={questLevel=28,requiredClasses=128},[14]={questLevel=29},[15]={questLevel=12},[16]={questLevel=28,zoneOrSort=-22},
 [17]={questLevel=28},[18]={questLevel=28,requiredRaces=8589934592+2},[19]={questLevel=28,requiredRaces=8589934592},
 [20]={questLevel=28,exclusiveTo={11}},[21]={questLevel=28,requiredMinRep={76,3000}},[22]={questLevel=28,specialFlags=1},
 [23]={questLevel=28,requiredSkill={171,1}},[24]={questLevel=28,breadcrumbForQuestId=17},[25]={requiredLevel=40,questLevel=40}}
Npcs={
 [1]={name="Giver",questStarts={10,11,12,13},spawns={[100]={{50,50}}},friendlyToFaction="AH"},
 [2]={name="Innkeeper Pala",npcFlags=128+16384,spawns={[100]={{20,30}}},friendlyToFaction="H"},
 [3]={name="Alliance Banker",npcFlags=256,spawns={[100]={{40,40}}},friendlyToFaction="A"},
 [4]={name="City Giver",questStarts={14},spawns={[200]={{10,10}}},friendlyToFaction="AH"},
 [5]={name="Hostile",questStarts={14},spawns={[100]={{70,70}}}},
 [6]={name="Grey Giver",questStarts={15},spawns={[100]={{80,80}}},friendlyToFaction="H"},
 [8]={name="Alliance Giver",questStarts={14},spawns={[100]={{90,90}}},friendlyToFaction="A"},
}
Objects={[7]={name="Wanted Poster",questStarts={14},spawns={[100]={{60,60}}}}}
local function Entity(store,numeric)
 local ids={} for id in pairs(store) do ids[#ids+1]=id end table.sort(ids)
 local entity={GetAllIds=function() mock.idReads=(mock.idReads or 0)+1 return ids end}
 for _,field in ipairs({"name","questStarts","npcFlags","spawns","friendlyToFaction"}) do
  entity[field]=function(id) local row=store[id] if not row then return nil end
   local value=row[field] if value==nil and numeric[field] then return 0 end return value end
 end
 return entity
end
local ZoneDB={private={areaIdToUiMapId="return {[100]=3,[200]=5,[300]=3}",
 dungeons={[718]={"Wailing Caverns",nil,17,{{300,46,36.5}}},[9999]={"Utgarde Keep",nil,495,{{300,10,10}}}}},
 instanceIdToAreaId={[43]=718,[574]=9999}}
LibQuestieDB={
 RequireContract=function(v) return v>=1 and v<=(mock.contract or 4) end,
 Npc=Entity(Npcs,{npcFlags=1}),Object=Entity(Objects,{}),
 Quest={name=function(id) return Quests[id] and "DB "..id end,GetAll=function(id,keys)
  local row=Quests[id] if not row then return nil end
  local values={n=#keys} for i,key in ipairs(keys) do local v=row[key] if v==nil and NUMERIC[key] then v=0 end values[i]=v end
  return values end},
 Enum={npcFlags={INNKEEPER=128,REPAIR=16384,BANKER=256,AUCTIONEER=4096,STABLEMASTER=8192},
  classKeys={WARRIOR=1,MAGE=128},raceMaskById={[2]=2,[96]=8589934592}},
 Support={Get=function(name) return name=="ZoneDB" and ZoneDB or nil end},
}
function Keys(prefix)
 local keys={}
 for _,marker in ipairs(P.compassSources.questie.markers) do
  if not prefix or marker.key:find(prefix,1,true) then keys[#keys+1]=marker.key end
 end
 table.sort(keys) return table.concat(keys,",")
end
function Marker(key)
 for _,marker in ipairs(P.compassSources.questie.markers) do if marker.key==key then return marker end end
end
function Recollect() P.discoveryClock=P.discoveryClock+61; P:InvalidateCompassSourceSettings("questie"); Drain() end
function Available(id) return Addon.CompassQuestieAvailability.IsAvailable(Addon.CompassQuestieAvailability.Context(LibQuestieDB),id) end
'''

CASES = {
    "givers with available quests appear on the player's map and nearby city map": '''
        mock.done[11]=true; Drain()
        assert(Keys("giver")=="questie:giver:npc:1:3:1,questie:giver:npc:4:5:1,questie:giver:object:7:3:1", Keys("giver"))
        local giver=Marker("questie:giver:npc:1:3:1")
        assert(giver.name=="Giver" and giver.atlas=="QuestNormal" and giver.kind=="questOffer")
        assert(giver.description=="Quest 10", giver.description)
        assert(giver.destination.mapID==3 and giver.destination.x==0.5)
    ''',
    "several available quests name the first and count the rest": '''
        Npcs[1].questStarts={10,22}
        Drain()
        assert(Marker("questie:giver:npc:1:3:1").description=="PLU_COMPASS_QUEST_MORE_F")
    ''',
    "quest rules hide unavailable quests": '''
        mock.done[11]=true; mock.log[17]=4
        assert(Available(10) and Available(14) and Available(18) and Available(22))
        assert(not Available(11), "completed")
        assert(not Available(12), "missing prerequisite")
        assert(not Available(13), "other class")
        assert(not Available(16), "holiday")
        assert(not Available(17), "in log")
        assert(not Available(19), "other race beyond 32 bits")
        assert(not Available(20), "exclusive quest taken")
        assert(not Available(23), "unverifiable skill")
        assert(not Available(24), "breadcrumb target taken")
        assert(not Available(25), "too low level")
        assert(not Available(999), "unknown quest")
        mock.done[99]=true; assert(Available(12), "prerequisite done")
        mock.done[22]=true; assert(Available(22), "repeatable stays available")
    ''',
    "reputation gates use the player's standing": '''
        assert(not Available(21))
        mock.rep[76]=3000; assert(Available(21))
    ''',
    "trivial quests follow the hidden-quest tracking choice": '''
        Drain(); assert(not Marker("questie:giver:npc:6:3:1"))
        mock.trivial=true; Recollect(); assert(Marker("questie:giver:npc:6:3:1"))
    ''',
    "hostile and other-faction givers stay hidden": '''
        Drain(); assert(not Marker("questie:giver:npc:5:3:1") and not Marker("questie:giver:npc:8:3:1"))
    ''',
    "services show friendly NPCs with the native tracking icon and names": '''
        Drain()
        assert(Keys("service")=="questie:service:npc:2:3:1", Keys("service"))
        local inn=Marker("questie:service:npc:2:3:1")
        assert(inn.texture==1001 and inn.kind=="service" and inn.description=="Innkeeper, Repair", inn.description)
    ''',
    "services follow their point toggle": '''
        Drain(); assert(Keys("service")~="")
        P:SetCompassPointVisibility("ShowServices","world",false); P:SetCompassPointVisibility("ShowServices","city",false)
        P:CacheCompassPointVisibility(); Drain()
        assert(Keys("service")=="" and Keys("giver")~="", Keys())
    ''',
    "entrances fill in only instances this client names": '''
        Drain()
        assert(Keys("entrance")=="questie:entrance:instance:43:3:1", Keys("entrance"))
        local entrance=Marker("questie:entrance:instance:43:3:1")
        assert(entrance.name=="Wailing Caverns" and entrance.atlas=="Dungeon" and entrance.kind=="poi")
    ''',
    "native journal entrances suppress QuestieDB entrances": '''
        Addon.ClientFeatures=setmetatable({dungeonEntrances=true},{__index=Addon.ClientFeatures})
        mock.entrances={{areaPoiID=1,name="Native",position={x=0.1,y=0.1},atlasName="Dungeon"}}
        Drain(); assert(Keys("entrance")=="", Keys("entrance"))
    ''',
    "the index builds once across collections": '''
        Drain(); Recollect(); Recollect()
        assert(mock.idReads==2, mock.idReads)
    ''',
    "quest events refresh the source": '''
        Drain(); local source=P.compassSources.questie; assert(not source.dirty)
        P:InvalidateCompassSource("QUEST_ACCEPTED"); assert(source.dirty)
    ''',
    "an incompatible QuestieDB contributes nothing": '''
        mock.contract=3; Drain(); assert(Keys()=="", Keys())
    ''',
    "without QuestieDB the source waits for the provider": '''
        mock.loaded.QuestieDB=false; Drain()
        assert(Keys()=="" and P.compassSources.questie.reason=="provider")
    ''',
}

RETAIL = '''
    Drain()
    assert(P.compassSources.questie.status=="unsupported" and Keys()=="")
    assert(not Addon.ClientFeatures.AllowsPoint("ShowServices"))
'''

failures, total = [], 0
for name, code in CASES.items():
    total += 1
    try:
        lua = client("forever")
        lua.execute(QUESTIE)
        lua.execute(code)
    except Exception as error:
        failures.append(name)
        print(f"FAIL {name}: {error}")
total += 1
try:
    lua = client("retail")
    lua.execute(QUESTIE)
    lua.execute(RETAIL)
except Exception as error:
    failures.append("retail")
    print(f"FAIL retail stays without QuestieDB points: {error}")
print(f"{total-len(failures)}/{total} Compass QuestieDB scenarios passed")
raise SystemExit(bool(failures))
