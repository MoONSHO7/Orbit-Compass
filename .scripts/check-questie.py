"""Check the QuestieDB adapter against a double of QuestieDB's documented contract-4 API in Lua 5.1; not a WoW runtime test."""

from compass_harness import client

# QuestieDB's public read semantics (docs/api.md): numeric getters return 0, empty tables come back nil, unknown ids are
# nil everywhere, GetAll returns a packed table, and the area-to-UiMap table is Lua source the consumer loads.
QUESTIE = r'''
mock.loaded.QuestieDB=true
P.questLevelRange=5
Addon.L.PLU_COMPASS_QUEST_LEVEL_F="[%d] %s"
function geterrorhandler() return function(message) mock.reported=message end end
RawDrain=Drain
-- The index builds on its own driver frame; run it to completion around discovery.
function Drain()
 RawDrain()
 local steps=0
 while P.compassQuestieDriving and steps<10000 do P.compassQuestieDriver.OnUpdate(P.compassQuestieDriver,0.016); steps=steps+1 end
 mock.buildSteps=(mock.buildSteps or 0)+steps
 RawDrain()
end
Addon.PointsSettings=Addon.PointsSettings or function() return {} end
mock.done,mock.log,mock.rep={},{},{}
mock.maps[5]={mapID=5,mapType=3,parentMapID=3,name="City"}
local children=C_Map.GetMapChildrenInfo
C_Map.GetMapChildrenInfo=function(id,...) if id==3 then return {mock.maps[5]} end return children(id,...) end
function P:ProjectCompassDestination(mapID,x,y) if mapID==self.mapID or mapID==5 then return {x=x,y=y} end end
function UnitClass() return "Warrior","WARRIOR",1 end
function UnitRace() return "Orc","Orc",2 end
function UnitLevel() return 30 end
function UnitFactionGroup() return "Horde" end
function GetRealZoneText(id) return ({[43]="Wailing Caverns"})[id] or "" end
C_QuestLog.IsQuestFlaggedCompleted=function(id) return mock.done[id]==true end
C_QuestLog.GetLogIndexForQuestID=function(id) return mock.log[id] end
C_QuestLog.GetTitleForQuestID=function(id) return "Quest "..id end
C_Reputation.GetFactionDataByID=function(id) return mock.rep[id] and {currentStanding=mock.rep[id]} end
function GetQuestDifficultyColor(level) return level>=29 and {r=1,g=1,b=0} or {r=0.25,g=0.75,b=0.25} end
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
-- QuestieDB's quest-side starters, derived from the doubles' NPC and object lists at read time.
local function StartedBy(questID)
 local npcs,objects
 for id,row in pairs(Npcs) do for _,q in ipairs(row.questStarts or {}) do if q==questID then npcs=npcs or {} npcs[#npcs+1]=id end end end
 for id,row in pairs(Objects) do for _,q in ipairs(row.questStarts or {}) do if q==questID then objects=objects or {} objects[#objects+1]=id end end end
 if npcs then table.sort(npcs) end
 return {npcs,objects}
end
local function Entity(store,numeric)
 local entity={GetAllIds=function()
  mock.idReads=(mock.idReads or 0)+1
  local ids={} for id in pairs(store) do ids[#ids+1]=id end table.sort(ids) return ids
 end}
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
 Quest={name=function(id) return Quests[id] and "DB "..id end,
  GetAllIds=function() local ids={} for id in pairs(Quests) do ids[#ids+1]=id end table.sort(ids) return ids end,
  startedBy=function(id) if mock.brokenStarters then error("broken starters") end return Quests[id] and StartedBy(id) end,
  GetAll=function(id,keys)
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
function Available(id) local A=Addon.CompassQuestieAvailability return A.IsAvailable(A.Context(LibQuestieDB,P.questLevelRange,{}),id) end
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
    "giver tooltips list each available quest with its level in difficulty colour": '''
        Npcs[1].questStarts={10,13,14}; Quests[10].questLevel=25
        Drain()
        local lines=Marker("questie:giver:npc:1:3:1").tooltipLines
        assert(#lines==2, #lines)
        assert(lines[1].text=="[25] Quest 10" and lines[1].g==0.75, lines[1].text)
        assert(lines[2].r==1 and lines[2].b==0)
    ''',
    "service and entrance tooltips name their role": '''
        Drain()
        assert(Marker("questie:service:npc:2:3:1").tooltipLines[1].text=="Innkeeper, Repair")
        assert(Marker("questie:entrance:instance:43:3:1").tooltipLines[1].text=="PLU_COMPASS_TYPE_INSTANCE")
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
    "the quest level range hides quests too far below the character": '''
        Drain(); assert(not Marker("questie:giver:npc:6:3:1"))
        P.questLevelRange=18; Recollect(); assert(Marker("questie:giver:npc:6:3:1"))
        P.questLevelRange=17; Recollect(); assert(not Marker("questie:giver:npc:6:3:1"))
    ''',
    "the range reaches the same distance above and below the character": '''
        Quests[10].questLevel=25; assert(Available(10), "5 below")
        Quests[10].questLevel=24; assert(not Available(10), "6 below")
        Quests[10].questLevel=35; assert(Available(10), "5 above")
        Quests[10].questLevel=36; assert(not Available(10), "6 above")
        Quests[10].questLevel=35; Quests[10].requiredLevel=31; assert(not Available(10), "required level still gates")
    ''',
    "the level range slider renders only with a compatible QuestieDB": '''
        local function HasRange()
            for _,tab in ipairs(Addon.SettingsTabs(1)) do
                if tab.id=="appearance" then
                    for _,control in ipairs(tab.controls) do if control.key=="QuestLevelRange" then return control end end
                end
            end
        end
        local range=HasRange(); assert(range and range.min==1 and range.max==60 and range.default==5)
        mock.contract=3; assert(not HasRange(), "incompatible contract")
        mock.contract=nil; mock.loaded.QuestieDB=false; assert(not HasRange(), "not loaded")
    ''',
    "exploration and scripted-event completion flags do not hide quests": '''
        Quests[10].specialFlags=2; assert(Available(10))
    ''',
    "quest turn-ins refresh giver tooltips through events": '''
        Quests[12].preQuestSingle={11}; Npcs[1].questStarts={10,11,12}
        Drain()
        local lines=Marker("questie:giver:npc:1:3:1").tooltipLines
        assert(#lines==2 and lines[2].text=="[28] Quest 11", lines[2].text)
        mock.done[11]=true; P.discoveryClock=P.discoveryClock+1; P:InvalidateCompassSource("QUEST_TURNED_IN"); Drain()
        lines=Marker("questie:giver:npc:1:3:1").tooltipLines
        assert(#lines==2 and lines[2].text=="[28] Quest 12", lines[2] and lines[2].text)
    ''',
    "the index builds on its own budget without holding discovery": '''
        for id=1000,1600 do Npcs[id]={name="Filler",spawns={[100]={{1,1}}},friendlyToFaction="AH"} end
        local clock=0; debugprofilestop=function() clock=clock+0.01 return clock end
        RawDrain()
        assert(P.compassQuestieDriving and not P.compassQuestieIndex, "built inside discovery")
        assert(P.compassSources.locations.status=="ready", "other sources waited for the build")
        local steps=0
        while P.compassQuestieDriving do P.compassQuestieDriver.OnUpdate(); steps=steps+1 end
        assert(steps>5, steps)
        assert(P.compassSources.questie.dirty, "completion did not request a collection")
        RawDrain(); assert(Marker("questie:giver:npc:1:3:1"))
    ''',
    "a failing build stops instead of erroring every frame": '''
        mock.brokenStarters=true; Drain()
        assert(not P.compassQuestieDriving and mock.reported and Keys()=="", tostring(mock.reported))
        local calls=mock.idReads; Recollect(); assert(not P.compassQuestieDriving and mock.idReads==calls)
    ''',
    "a same-map subzone keeps QuestieDB markers": '''
        Drain(); local source=P.compassSources.questie; assert(not source.dirty)
        P:InvalidateCompassSource("ZONE_CHANGED")
        assert(not source.dirty and P.compassSources.offers.dirty)
    ''',
    "unreadable native entrances leave QuestieDB entrances shown": '''
        Addon.ClientFeatures=setmetatable({dungeonEntrances=true},{__index=Addon.ClientFeatures})
        C_EncounterJournal.GetDungeonEntrancesForMap=function() return nil end
        Drain(); assert(Keys("entrance")=="questie:entrance:instance:43:3:1", Keys("entrance"))
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
        assert(mock.idReads==1, mock.idReads)
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
    for _,tab in ipairs(Addon.SettingsTabs(1)) do
        for _,control in ipairs(tab.controls) do assert(control.key~="QuestLevelRange", "Retail renders the slider") end
    end
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
